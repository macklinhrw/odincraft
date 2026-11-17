package main

import "base:intrinsics"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:os"
import "core:math/linalg"
import "core:sync"
import "core:thread"
import "core:time"
import "core:slice"

// Land larger than a region, formed in pieces with no seam (step 21; docs/interesting-world/notes/
// continents-forming.md). The landmass is formed whole on coarse cells, then cut along its drainage
// into pieces, and the pieces take up the finer cells one after another, downstream first. Each piece
// holds, right at the cut, what the pieces formed before it left there, through every step of the
// history: a band of cells whose heights, filled surface, drainage, land drained and rock carried are
// theirs (`Holding`). Toward pieces not yet formed it forms a margin past the cut, and holds the cells
// beyond that to the coarse pass, with the water and rock the coarse pass says come in. What a piece
// leaves beside the pieces after it is kept for them (`Band`), and with it what it made of their
// ground in its margin, which their own cells near the cut lean toward (`held_lean`). The pieces
// round the player are kept formed and those far behind let go (`masses_keep`); land not yet formed
// is drawn from the coarse stage (afar.odin).

// A land mass of the known world larger than a region can hold. What the world knows of it before it
// is formed: its ground at the start of the forming, its uplift and its sea are read from the plates'
// regional history at each place (known.odin), as an island's record is. It is formed on a lattice of
// cells laid over its whole extent: its coarse stage whole (coarse.odin), kept (kept.odin), then cut
// into pieces that take up the finer cells.
Landmass :: struct {
	mass:   i32,       // its land mass in the known world, from 1
	origin: [2]i32,    // the world point at its lattice's middle, metres
	side:   f64,       // the lattice's side, metres
	seed:   u32,       // the seed it is formed from
	area:   f32,       // km² of land, in the known world
	top:    f32,       // m, the history's highest ground on it
	near:   f64,       // metres from the start to its nearest land in the known world,
	shore:  [2]f64,    // and where in the world that land is
	frame:  Formed,    // its own region, which its coarse stage is formed on and every piece reads
	store:  Store,     // its coarse stage, kept
	path:   string,    // where
	cut:    Cut,
	all:    Pieces,
	from:   int,       // the phase its pieces take up from,
	rest:   f32,       // and the years of the phases from there on
	first:  int,       // its first piece's place in `formed`
	mutex:  sync.Mutex,   // pieces are formed one at a time, each after those it waits on
	seconds: f64,      // spent forming its pieces
	ready:  bool,      // its coarse stage is at hand
	kept:   bool,      // it was read back from where an earlier run kept it,
	took:   f64,       // or formed in this many seconds
	left:   bool,      // its coarse stage was stopped before it had run (lands_state.leave): it stays a record until the world is opened again
}

MASS_ROUGH :: 80     // metres the starting ground wanders over a few km, so the coast does not follow the history's 2 km samples
MASS_SHELF :: -600   // the deepest the sea floor inside the lattice starts at

// A cell of a landmass's grid as the forming starts: the history's ground there, lowered by the
// uplift still to come, and roughened. Where the known world's ground is another land mass's, it is
// sea floor here: each mass is formed on its own lattice.
mass_cell :: proc(g: ^Grid, c: int, x, z: f64) {
	h: f32
	h, g.uplift[c] = mass_ground(x, z)
	if l, i, j := g.at, c%g.n + g.at.x, c/g.n + g.at.z; i == 0 || j == 0 || i == l.n - 1 || j == l.n - 1 do h = min(h, MASS_SHELF)   // the lattice's rim is sea, as a region's is
	g.sea[c] = h <= 0
	g.z[c] = max(h, MASS_SHELF) if g.sea[c] else 0.5 + max(h, 0) + 12*(1 + fbm(x, z, 900, 1, 3, seed + 9))
	u_ := rock_base(x, z, LAND_CELL)
	g.base[c] = u_.base
	if g.bodies != nil do g.bodies[c] = {u_.cover, u_.roof, u_.body}
}

// The history's ground at a point of a landmass as the forming starts, lowered by the uplift still to
// come and roughened, and how fast it rises there, m/yr at the shape's rate of 1.
mass_ground :: proc(x, z: f64) -> (h, uplift: f32) {
	m := region.mass
	at := known_point(f64(region.origin.x) + x, f64(region.origin.y) + z)
	k, _ := known_at(at)
	h = k.h
	u, v := clamp(int((at.x + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1), clamp(int((at.y + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1)
	if known.mass[v*KNOWN_N + u] != m.mass && h > 0 do h = -50
	rates := past_at(at)
	mean: f32
	for r in rates do mean += r/PAST
	uplift = max(mean, 0)/1000
	left: f32
	for p in region.history do left += p.steps*p.years*p.uplift
	h += MASS_ROUGH*fbm(x, z, 5000, 1, 4, seed + 9) - uplift*left
	return
}

ONWARD :: -3   // in `next`: the water leaves the piece of a landmass in hand into another, which carries it on

BAND :: 8   // cells a piece holds of each formed neighbour at each cell size, and keeps of its own for the pieces after it
LEAN :: 384   // metres past the cut over which a piece's own cells lean toward what the pieces formed before it made of them

// A held cell's values for one step: its height at the start, its filled surface, the cell on the
// lattice it drains to (or -1), the land it drains and the rock it carries, and its height after
// the cutting, after creep and after the coast.
Held :: struct { z0, fill, area, load, z1, z2, z3: f32, next: i32 }

// What a formed piece keeps for the pieces after it, at one cell size: its cells within BAND of them,
// as indices on the lattice at that size, and their values at each step at that size.
Band :: struct {
	cell:  int,
	cells: []i32,
	vals:  [dynamic][]Held,   // by step, then by cell
	place: map[i32]i32,   // lattice index to index in cells
	// The cells of the pieces after it that it formed as margin, within LEAN of its own: what it made
	// of them, which they lean toward (held_lean). Lattice indices, the metres each lies from its own
	// cells, and their heights at the end of each step.
	toward: []i32,
	apart:  []f32,
	lean:   [dynamic][]f32,
	there:  map[i32]i32,
}

// One of a piece's own cells that leans toward an earlier neighbour's making of it: the cell, that
// neighbour's band, the cell's place in it and how hard it leans, from 1 at the cut to 0 at LEAN.
Lean :: struct { c: i32, band: ^Band, at: i32, w: f32 }

// The cells of a piece's grid held to what was formed beside it, at one cell size.
Holding :: struct {
	held:   []bool,     // each cell of the grid
	index:  []i32,      // each cell's place among the held, or -1
	cells:  []i32,      // the held cells
	band:   []^Band,    // each held cell's band, or nil where it is held to the coarse pass
	at:     []i32,      // its place in that band
	coarse: []Held,     // where held to the coarse pass, its values
	vals:   []Held,     // this step's values
	into:   [dynamic][3]f32,   // water and rock coming in from the coarse pass: the cell it enters (as a float), m², m³ a year
	keep:   []i32,      // own cells kept for the pieces after this one
	toward: []i32,      // margin cells kept for them, which they lean toward
	leans:  []Lean,     // own cells that lean toward what an earlier neighbour made of them, a cell's entries together
	out:    ^Band,      // what is kept of them
	step:   int,        // steps taken at this cell size
	rose:   []f32,      // each cell: m/yr the ground goes on rising as the rebound left the coarse stage rising (coarse.odin)
}

// The held cells as they stand at a stage of this step: 0 at its start, 2 after creep, 3 after the coast.
held_stage :: proc(g: ^Grid, stage: int) {
	h := g.holding
	for c, i in h.cells {
		v := h.vals[i]
		g.z[c] = v.z0 if stage == 0 else v.z2 if stage == 2 else v.z3
		if stage != 2 do g.sea[c] = g.z[c] <= 0
	}
}

// A piece's own cells near a cut it shares with a piece formed before it lean toward what that piece
// made of them in its margin, wholly at the cut and not at all LEAN past it. The two makings of the
// same ground part where the land turns on a threshold (a strong bed worn through in one and not in
// the other, after which the weak rock under it goes in a few steps), and a cell that was free right
// up to a cut held fast would stand as a wall there. Each step ends with the lean, so the next step's
// water and cutting run over it.
held_lean :: proc(g: ^Grid) {
	h := g.holding
	for i := 0; i < len(h.leans); {
		c := h.leans[i].c
		sum, weight, most: f32
		for ; i < len(h.leans) && h.leans[i].c == c; i += 1 {
			e := h.leans[i]
			sum, weight, most = sum + e.w*e.band.lean[min(h.step, len(e.band.lean) - 1)][e.at], weight + e.w, max(most, e.w)
		}
		g.z[c] = math.lerp(g.z[c], sum/weight, most)
		g.sea[c] = g.z[c] <= 0
	}
}

// Fill this step's values of the held cells.
held_values :: proc(g: ^Grid) {
	h := g.holding
	for _, i in h.cells {
		if b := h.band[i]; b != nil do h.vals[i] = b.vals[min(h.step, len(b.vals) - 1)][h.at[i]]
		else do h.vals[i] = h.coarse[i]
	}
}

// The flood starts from every held land cell at its own filled level, as from the shore.
held_seed :: proc(g: ^Grid) {
	h := g.holding
	for c, i in h.cells do if !g.sea[c] {
		g.fill[c] = max(h.vals[i].fill, 0.05)
		g.seen[c] = true
		heap_push(&g.heap, {g.fill[c], i32(c)})
	}
}

// Held cells drain nowhere in the piece, but those whose water enters it bring the land they drain.
held_route :: proc(g: ^Grid) {
	h := g.holding
	for c, i in h.cells {
		g.next[c], g.area[c] = -1, 0
		v := h.vals[i]
		if v.next == -1 || g.sea[c] do continue
		if r := lattice_cell(g, v.next); r >= 0 && !h.held[r] && !g.sea[r] do g.area[r] += v.area
	}
	for in_ in h.into do if r := int(in_[0]); !g.sea[r] do g.area[r] += in_[1]
}

// The rock coming in with that water.
held_load :: proc(g: ^Grid, dt: f32) {
	h := g.holding
	for c, i in h.cells {
		v := h.vals[i]
		if v.next == -1 || g.sea[c] do continue
		if r := lattice_cell(g, v.next); r >= 0 && !h.held[r] do g.load[r] += v.load
	}
	for in_ in h.into do g.load[int(in_[0])] += in_[2]*dt
}

// The grid's cell at an index on its lattice, or -1 off the grid. A lattice of 16 m cells over a
// known world 1,000 km across has more cells than a signed 32 bits count, so an index is kept as
// unsigned bits, with -1 for none.
lattice_cell :: proc(g: ^Grid, k: i32) -> int {
	u := int(u32(k))
	x, z := u%g.at.n - g.at.x, u/g.at.n - g.at.z
	return z*g.n + x if x >= 0 && z >= 0 && x < g.n && z < g.n else -1
}

// A cell's index on the grid's lattice.
lattice_of :: proc(g: ^Grid, c: int) -> i32 {
	return i32(u32((c/g.n + g.at.z)*g.at.n + c%g.n + g.at.x))
}

// One step's values of the cells kept for the pieces after this one, at a stage: 0 at its start, 1
// once routed, 2 once cut, 3 after creep, 4 after the coast.
held_keep :: proc(g: ^Grid, stage: int) {
	h := g.holding
	if h.out == nil do return
	if stage == 0 {
		append(&h.out.vals, make([]Held, len(h.keep)))
		append(&h.out.lean, make([]f32, len(h.toward)))
	}
	if stage == 4 do for c, i in h.toward do h.out.lean[len(h.out.lean) - 1][i] = g.z[c]
	vals := h.out.vals[len(h.out.vals) - 1]
	for c, i in h.keep {
		v := &vals[i]
		switch stage {
		case 0: v.z0 = g.z[c]
		case 1: v.fill, v.area, v.next = g.fill[c], g.area[c], lattice_of(g, int(g.next[c])) if g.next[c] >= 0 else -1
		case 2: v.z1, v.load = g.z[c], g.load[c]
		case 3: v.z2 = g.z[c]
		case 4: v.z3 = g.z[c]
		}
	}
}

// The history's steps on one grid, from phase `from` on, while the cells are no finer than `finest`,
// a piece's held cells held and its kept cells kept. `level` makes the hold for each new cell size.
// Returns the grid it ends on (refining frees the coarser).
Leveller :: #type proc(g: ^Grid, data: rawptr)
form_phases :: proc(g: ^Grid, from, upto: int, level: Leveller = nil, data: rawptr = nil) -> ^Grid {
	g := g
	history := region.history
	rise, sea: f32
	for p in history do rise += p.sea
	for p in history[:from] do sea += p.sea
	if level != nil do level(g, data)
	for p in history[from:upto] {
		for g.d > f32(p.cell) {
			g = refine(g)
			if level != nil do level(g, data)
		}
		if p.sea != 0 {
			for c in 0..<g.n*g.n {
				g.z[c] -= p.sea
				g.sea[c] = g.z[c] <= 0
			}
			if g.holding != nil do for &v in g.holding.coarse do v.z0, v.fill, v.z1, v.z2, v.z3 = v.z0 - p.sea, v.fill - p.sea, v.z1 - p.sea, v.z2 - p.sea, v.z3 - p.sea
			sea += p.sea
		}
		g.lift, g.rise = p.uplift, rise - sea
		for _ in 0..<int(p.steps) {
			if g.holding != nil {
				held_values(g)
				held_stage(g, 0)
				held_keep(g, 0)
			}
			route(g)
			if g.holding != nil do held_keep(g, 1)
			erode(g, p.years)
			if g.holding != nil do held_keep(g, 2)
			creep(g, p.years)
			if g.holding != nil {
				held_stage(g, 2)
				held_keep(g, 3)
			}
			coast(g, p.years)
			if g.holding != nil {
				for c in 0..<g.n*g.n do if !g.sea[c] do g.z[c] += g.holding.rose[c]*p.years   // the crust goes on rising as rock is worn off it (coarse.odin)
				held_lean(g)
				held_stage(g, 3)
				held_keep(g, 4)
				g.holding.step += 1
			}
			g.left -= p.years*p.uplift
		}
	}
	return g
}

// ---- cutting a landmass into pieces ------------------------------------------------------------

// A landmass cut into pieces on the coarse stage's cells: for each piece, the piece its water leaves
// through, its order, its neighbours, the box round its cells and the window of the lattice it forms on.
// Each cell's piece is kept with the coarse stage (kept.odin).
Cut :: struct {
	down:   []i32,          // each piece's: the piece its outlet drains into, or -1 at the sea
	depth:  []i32,          // pieces between it and the sea
	rank:   []i32,          // its place in the order pieces are formed in
	size:   []i32,          // land cells
	near:   [][dynamic]i32, // the pieces beside it
	box:    [][4]i32,       // its cells' least and greatest column and row
	window: [][3]i32,       // the corner and side of the square of the lattice it forms on (piece_window)
}

SEA_REACH :: 32   // cells of the coarse pass the sea belongs to the nearest land's piece for; beyond, it is the open sea
CUT_ROOT  :: 64   // in a cell's flag while its landmass is cut: a piece begins at it

// A cell's donors, the last the flood reached first.
donors_sorted :: #force_inline proc(g: ^Grid, c: int, ahead: ^[8]int, cells: ^[8]int) -> (count: int) #no_bounds_check {
	keys: [8]u64
	for m := g.coarse.donors[c]; m != 0; m &= m - 1 {
		nb := c + ahead[intrinsics.count_trailing_zeros(m)]
		k := ckey(g, nb)
		i := count
		for ; i > 0 && keys[i - 1] < k; i -= 1 do keys[i], cells[i] = keys[i - 1], cells[i - 1]
		keys[i], cells[i] = k, nb
		count += 1
	}
	return
}

// Cut the land of a coarse stage's grid along its drainage into pieces of about `most` cells: each a
// part of a drainage tree, cut across a trunk where a basin is larger, and the small basins along a
// coast joined. Then order them: a piece through which another's water leaves comes first; among
// pieces as far from the sea, by a colouring of their borders, so that no long chain of neighbours
// waits on each other. Where the order of the land's cells matters it is the flood's (lowest filled
// level first, then the lower index), which the grid still holds. Returns each cell's piece and 1.
cut_make :: proc(g: ^Grid, most: int, margin: f32) -> (cut: Cut, own: []i32) {
	n, co := g.n, g.coarse
	fl := co.flags
	// The sea's cells drain nowhere; land whose water ran into a cell the sea has since cut runs into the sea.
	for &l in co.roots do clear(&l)
	over(g, co, proc(co: ^Coarse, g: ^Grid, ty, y, x0, x1: int) {
		#no_bounds_check for c in y*g.n + x0..<y*g.n + x1 {
			co.flags[c] = 0
			if g.sea[c] do g.next[c] = -1
			else if r := g.next[c]; r >= 0 && g.sea[r] do g.next[c] = -1
		}
	})
	over(g, co, proc(co: ^Coarse, g: ^Grid, ty, y, x0, x1: int) {
		#no_bounds_check for c in y*g.n + x0..<y*g.n + x1 do if !g.sea[c] && g.next[c] < 0 do append(&co.roots[ty], i32(c))
	})
	trees_make(g, false)
	batches := co.batches[:]
	rem := make([]i32, n*n)
	defer delete(rem)
	own = make([]i32, n*n)
	// From the last cell the flood reached to the first: the cells behind each that go with it, and
	// where a piece is full, the cell the next begins at.
	Rem :: struct { g: ^Grid, rem, own: []i32, most: i32 }
	rm := Rem{g, rem, own, i32(most)}
	shared(len(batches), 1, &rm, proc(rm: ^Rem, lo, hi: int) {
		g, n, fl := rm.g, rm.g.n, rm.g.coarse.flags
		ways := OFFSETS
		ahead: [8]int
		for o, k in ways do ahead[k] = o.y*n + o.x
		#no_bounds_check for b in g.coarse.batches[lo:hi] do #reverse for ci in b.buf[b.lo:b.hi] {
			c := int(ci)
			cells: [8]int
			behind := i32(0)
			for d in cells[:donors_sorted(g, c, &ahead, &cells)] {
				if behind + rm.rem[d] > rm.most && rm.rem[d] >= rm.most/4 do fl[d] |= CUT_ROOT
				else do behind += rm.rem[d]
			}
			rm.rem[c] = behind + 1
			if g.next[c] < 0 do fl[c] |= CUT_ROOT
		}
	})
	// The pieces, numbered in the order the flood reached the cells they begin at.
	keys := make([dynamic]u64)
	defer delete(keys)
	for b in batches do for c in b.buf[b.lo:b.hi] do if fl[c] & CUT_ROOT != 0 do append(&keys, ckey(g, int(c)))
	slice.sort(keys[:])
	pieces := i32(len(keys))
	roots := make([]i32, pieces)
	defer delete(roots)
	for k, i in keys {
		roots[i] = i32(u32(k))
		own[u32(k)] = i32(i) + 1
	}
	shared(len(batches), 1, &rm, proc(rm: ^Rem, lo, hi: int) {
		g, fl := rm.g, rm.g.coarse.flags
		#no_bounds_check for b in g.coarse.batches[lo:hi] do for c in b.buf[b.lo:b.hi] do if fl[c] & CUT_ROOT == 0 do rm.own[c] = rm.own[g.next[c]]
	})
	// Pieces too small to stand alone, small basins along a coast, joined to the smallest neighbour,
	// until none is left under a quarter of `most` that has one no larger than `most`.
	size := make([]i32, pieces)
	boxes := make([][4]i32, pieces)   // which a join keeps as near square as it can: a piece's grid is a square round it
	beside := make([]map[i32]bool, pieces)
	defer { delete(size); delete(boxes); for m in beside do delete(m); delete(beside) }
	for &b in boxes do b = {i32(n), i32(n), -1, -1}
	for b in batches do for ci in b.buf[b.lo:b.hi] {
		c := int(ci)
		a := own[c] - 1
		size[a] += 1
		x, y := i32(c%n), i32(c/n)
		bx := &boxes[a]
		bx^ = {min(bx.x, x), min(bx.y, y), max(bx.z, x), max(bx.w, y)}
		for k in ([2]int{c + 1, c + n}) do if q := own[k] - 1; q >= 0 && q != a { beside[a][q] = true; beside[q][a] = true }
	}
	into := make([]i32, pieces)
	defer delete(into)
	for &v, i in into do v = i32(i)
	find :: proc(into: []i32, p: i32) -> i32 { p := p; for into[p] != p do p = into[p]; return p }
	span :: proc(a, b: [4]i32) -> i32 { return max(max(a.z, b.z) - min(a.x, b.x), max(a.w, b.w) - min(a.y, b.y)) + 1 }
	long :: proc(b: [4]i32) -> bool { w, h := b.z - b.x + 1, b.w - b.y + 1; return max(w, h) > 2*min(w, h) }
	widest := i32(1.6*math.sqrt(f64(most)))   // cells: a join no wider than 1.6 times the side of a square piece of `most`
	for {
		merged := false
		for p in 0..<pieces {
			// A basin along a coast joins its neighbours while it is small, or long and narrow, as the
			// basins of a coastal range are: a piece forms in a square round it, so a strip costs
			// several times its land.
			if find(into, p) != p || size[p] >= i32(most/2) && !long(boxes[p]) || g.next[roots[p]] >= 0 do continue
			best := i32(-1)
			lesser := make([dynamic]i32, context.temp_allocator)
			for q0 in beside[p] do append(&lesser, find(into, q0))
			slice.sort(lesser[:])   // a map has no order of its own
			for q in lesser {
				if q == p || size[q] + size[p] > i32(most*3/2) || span(boxes[p], boxes[q]) > widest do continue
				if best < 0 || span(boxes[p], boxes[q]) < span(boxes[p], boxes[best]) do best = q
			}
			if best < 0 do continue
			into[p] = best
			size[best] += size[p]
			a, b := boxes[best], boxes[p]
			boxes[best] = {min(a.x, b.x), min(a.y, b.y), max(a.z, b.z), max(a.w, b.w)}
			for q in beside[p] do beside[best][q] = true
			merged = true
		}
		if !merged do break
	}
	// Numbered again from 0, in the order of their first cell up from the sea.
	number := make([]i32, pieces)
	defer delete(number)
	slice.fill(number, -1)
	count := i32(0)
	for p in 0..<pieces do if r := find(into, p); number[r] < 0 {
		number[r] = count
		count += 1
	}
	for p in 0..<pieces do number[p] = number[find(into, p)]
	Num :: struct { g: ^Grid, own, number: []i32 }
	nm := Num{g, own, number}
	shared(len(batches), 1, &nm, proc(nm: ^Num, lo, hi: int) {
		#no_bounds_check for b in nm.g.coarse.batches[lo:hi] do for c in b.buf[b.lo:b.hi] do nm.own[c] = nm.number[nm.own[c] - 1] + 1
	})
	cut.down, cut.depth, cut.rank, cut.size = make([]i32, count), make([]i32, count), make([]i32, count), make([]i32, count)
	cut.near, cut.box, cut.window = make([][dynamic]i32, count), make([][4]i32, count), make([][3]i32, count)
	slice.fill(cut.down, -1)
	for &b in cut.box do b = {i32(n), i32(n), -1, -1}
	for p in 0..<pieces {
		a := number[p]
		if into[p] == p do cut.size[a] = size[p]
		bx, b := &cut.box[a], boxes[p]
		bx^ = {min(bx.x, b.x), min(bx.y, b.y), max(bx.z, b.z), max(bx.w, b.w)}
		if r := g.next[roots[p]]; r >= 0 && own[r] - 1 != a do cut.down[a] = own[r] - 1
	}
	// The sea within SEA_REACH goes with the nearest land, nearest first, the land in the flood's order.
	reach := make([]u8, n*n)
	defer delete(reach)
	clear(&keys)
	for b in batches do for ci in b.buf[b.lo:b.hi] {
		c := int(ci)
		if g.sea[c + 1] || g.sea[c - 1] || g.sea[c + n] || g.sea[c - n] do append(&keys, ckey(g, c))
	}
	slice.sort(keys[:])
	queue := make([dynamic]i32)
	defer delete(queue)
	for k in keys do append(&queue, i32(u32(k)))
	for head := 0; head < len(queue); head += 1 {
		c := int(queue[head])
		if reach[c] >= SEA_REACH do continue
		for o in FOUR {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n do continue
			if k := y*n + x; own[k] == 0 {
				own[k], reach[k] = own[c], reach[c] + 1
				append(&queue, i32(k))
				bx := &cut.box[own[c] - 1]
				bx^ = {min(bx.x, i32(x)), min(bx.y, i32(y)), max(bx.z, i32(x)), max(bx.w, i32(y))}
			}
		}
	}
	// Neighbours are pieces whose cells come within two of each other's, 128 m at 64 m, the BAND a
	// piece holds of a neighbour at the finest cells.
	Pairs :: struct { own: []i32, rows: [][dynamic][2]i32 }
	pr := Pairs{own, make([][dynamic][2]i32, co.m)}
	defer { for l in pr.rows do delete(l); delete(pr.rows) }
	over(g, &pr, proc(pr: ^Pairs, g: ^Grid, ty, y, x0, x1: int) {
		n := g.n
		last := [2]i32{-1, -1}
		#no_bounds_check for x in x0..<x1 do if a := pr.own[y*n + x] - 1; a >= 0 {
			for dy in -2..=2 do for dx in 0..=2 do if dx > 0 || dy > 0 {
				if xx, yy := x + dx, y + dy; xx < n && yy >= 0 && yy < n {
					if q := pr.own[yy*n + xx] - 1; q >= 0 && q != a {
						pair := [2]i32{min(a, q), max(a, q)}
						if pair != last do append(&pr.rows[ty], pair)
						last = pair
					}
				}
			}
		}
	})
	pairs := make(map[[2]i32]bool)
	defer delete(pairs)
	for l in pr.rows do for k in l do pairs[k] = true
	for k in pairs { append(&cut.near[k.x], k.y); append(&cut.near[k.y], k.x) }
	for &l in cut.near do slice.sort(l[:])
	// Depth from the sea, by the pieces' own drainage.
	for p in 0..<count {
		d, q := i32(0), cut.down[p]
		for ; q >= 0 && d < count; q = cut.down[q] do d += 1
		cut.depth[p] = d
	}
	// A colour for each piece among its neighbours as far from the sea, the least not taken by one
	// coloured before it, in the order of their numbers.
	colour := make([]i32, count)
	defer delete(colour)
	slice.fill(colour, -1)
	for p in 0..<count {
		taken: bit_set[0..<64]
		for q in cut.near[p] do if cut.depth[q] == cut.depth[p] && colour[q] >= 0 && colour[q] < 64 do taken += {int(colour[q])}
		for k in 0..<64 do if k not_in taken {
			colour[p] = i32(k)
			break
		}
	}
	Key :: struct { depth, colour, p: i32 }
	order := make([]Key, count)
	defer delete(order)
	for p in 0..<count do order[p] = {cut.depth[p], colour[p], i32(p)}
	slice.sort_by(order, proc(x, y: Key) -> bool { return x.depth < y.depth || x.depth == y.depth && (x.colour < y.colour || x.colour == y.colour && x.p < y.p) })
	for k, r in order do cut.rank[k.p] = i32(r)
	// The window each piece forms on.
	Windows :: struct { cut: ^Cut, own: []i32, n: int, margin: f32, d: f32 }
	ws := Windows{&cut, own, n, margin, g.d}
	shared(int(count), 1, &ws, proc(ws: ^Windows, lo, hi: int) { for p in lo..<hi do ws.cut.window[p] = piece_window(ws.cut, ws.own, ws.n, i32(p), ws.margin, ws.d) })
	return
}

// The pieces formed before `p` that it waits on: its neighbours earlier in the order, and theirs,
// those it waits on longest first, so that forming them in this order forms each after its own.
cut_waits :: proc(cut: ^Cut, p: i32, allocator := context.temp_allocator) -> []i32 {
	all := make([dynamic]i32, allocator)
	seen := make(map[i32]bool, 16, context.temp_allocator)
	stack := make([dynamic]i32, context.temp_allocator)
	append(&stack, p)
	seen[p] = true
	for len(stack) > 0 {
		q := pop(&stack)
		for r in cut.near[q] do if !seen[r] && cut.rank[r] < cut.rank[q] {
			seen[r] = true
			append(&all, r)
			append(&stack, r)
		}
	}
	context.user_ptr = cut
	slice.sort_by(all[:], proc(a, b: i32) -> bool { c := (^Cut)(context.user_ptr); return c.rank[a] < c.rank[b] })
	return all[:]
}

// Whether piece `q` comes before its neighbour `p` in the order, so that `p` holds its land at their cut.
// It depends on the order alone, never on what happens to be formed: a piece comes out the same
// however it was reached. A piece that is not a neighbour is never held, formed or not.
earlier :: proc(cut: ^Cut, q, p: i32) -> bool {
	if q < 0 || q == p || cut.rank[q] >= cut.rank[p] do return false
	_, found := slice.binary_search(cut.near[p][:], q)
	return found
}

// The window of the coarse pass's cells a piece forms on: its corner and side. It holds the piece's own
// cells, its margin toward pieces not yet formed, and a ring of RING coarse cells round both, which is
// held: the bands of the pieces formed before it, and the coarse pass beyond its margin. `own` is each
// cell's piece and 1.
piece_window :: proc(cut: ^Cut, own: []i32, n: int, p: i32, reach, d: f32) -> [3]i32 {
	b := cut.box[p]
	margin, ring := int(math.ceil(reach/d)), RING
	lo := [2]int{max(int(b.x) - margin - ring, 0), max(int(b.y) - margin - ring, 0)}
	hi := [2]int{min(int(b.z) + margin + ring, n - 1), min(int(b.w) + margin + ring, n - 1)}
	w, h := hi.x - lo.x + 1, hi.y - lo.y + 1
	far := make([]f32, w*h)
	defer delete(far)
	for j in 0..<h do for i in 0..<w do far[j*w + i] = 0 if own[(lo.y + j)*n + lo.x + i] - 1 == p else 1e9
	steps := [4][3]f32{{-1, 0, 1}, {0, -1, 1}, {-1, -1, math.SQRT_TWO}, {1, -1, math.SQRT_TWO}}
	for sweep in 0..<2 do for k in 0..<w*h {
		c := k if sweep == 0 else w*h - 1 - k
		x, y := c%w, c/w
		for st in steps {
			dx, dy := int(st.x) if sweep == 0 else -int(st.x), int(st.y) if sweep == 0 else -int(st.y)
			if nx, ny := x + dx, y + dy; nx >= 0 && ny >= 0 && nx < w && ny < h do far[c] = min(far[c], far[ny*w + nx] + st.z)
		}
	}
	in_lo, in_hi := [2]int{n, n}, [2]int{-1, -1}
	for j in 0..<h do for i in 0..<w {
		q := own[(lo.y + j)*n + lo.x + i] - 1
		at := far[j*w + i]
		if at <= f32(ring) || at <= f32(margin) && !earlier(cut, q, p) {
			in_lo, in_hi = {min(in_lo.x, lo.x + i), min(in_lo.y, lo.y + j)}, {max(in_hi.x, lo.x + i), max(in_hi.y, lo.y + j)}
		}
	}
	lo = {max(in_lo.x - ring, 0), max(in_lo.y - ring, 0)}
	hi = {min(in_hi.x + ring, n - 1), min(in_hi.y + ring, n - 1)}
	side := max(hi.x - lo.x, hi.y - lo.y) + 1
	side = (side + 3)/4*4   // a whole number of 256 m, which the finer grids halve into
	lo = {clamp(lo.x, 0, max(n - side, 0)), clamp(lo.y, 0, max(n - side, 0))}
	return {i32(lo.x), i32(lo.y), i32(side)}
}

// ---- forming a piece ----------------------------------------------------------------------------

// What forming the pieces of one landmass shares: the coarse pass (its grid at the cell size the
// pieces take up from), the cut on that grid's cells, the phase they take up from, how far they
// form past the cut toward pieces not yet formed, and the bands each formed piece keeps, by piece.
Pieces :: struct {
	m:      ^Landmass,
	from:   int,
	margin: f32,          // metres
	formed: []bool,       // by piece: formed, and kept where it can be read back
}

// What a piece's grid is while it forms, for making its hold at each cell size: the window of the
// coarse stage it forms on, a cell wider all round, and each of that window's cells' piece.
// With them, the bands its earlier neighbours left it, read back for this forming, and those it leaves.
Piece_Form :: struct { all: ^Pieces, p: i32, pass: ^Grid, owner: []i32, held: map[i32][dynamic]^Band, out: [dynamic]^Band }

RING :: 8   // coarse cells held round a piece's own cells and margin: the coast's exposure reads 500 m

// The grid a piece forms on at the coarse pass's cells: a window round its own cells, its margin and
// a ring beyond, taken from the coarse pass as it stood.
piece_grid :: proc(f: ^Piece_Form) -> ^Grid {
	pass, w := f.pass, f.all.m.cut.window[f.p]
	side := int(w.z)
	g := grid_make(side, {int(w.x), int(w.y), pass.at.n})
	for j in 0..<side do for i in 0..<side {
		c, k := j*side + i, (j + 1)*pass.n + i + 1
		g.z[c], g.sea[c], g.cut[c], g.face[c], g.load[c] = pass.z[k], pass.sea[k], pass.cut[k], pass.face[k], pass.load[k]
	}
	g.left, g.lift, g.rise = pass.left, pass.lift, pass.rise
	return g
}

// The hold of a piece's grid at its cell size: which cells are its own, which are held to the bands
// of the pieces formed before it, which it forms as margin, and which are held to the coarse pass;
// and which of its own it keeps for the pieces after it.
piece_level :: proc(g: ^Grid, data: rawptr) {
	f := (^Piece_Form)(data)
	all, p := f.all, f.p
	pass, cut := f.pass, &all.m.cut
	if g.holding != nil {   // the coarser grid's hold, gone with it
		h := g.holding
		delete(h.held); delete(h.index); delete(h.cells); delete(h.band); delete(h.at); delete(h.coarse); delete(h.vals); delete(h.into); delete(h.keep); delete(h.rose); delete(h.toward); delete(h.leans)
		free(h)
		g.holding = nil
	}
	n := g.n
	scale := int(math.round(pass.d/g.d))   // this grid's cells to a coarse cell
	owner := make([]i32, n*n, context.temp_allocator)
	for c in 0..<n*n {
		x, z := (c%n + g.at.x)/scale - pass.at.x, (c/n + g.at.z)/scale - pass.at.z
		owner[c] = f.owner[clamp(z, 0, pass.n - 1)*pass.n + clamp(x, 0, pass.n - 1)]
	}
	// Metres from the piece's own cells, by two sweeps.
	far := make([]f32, n*n, context.temp_allocator)
	for c in 0..<n*n do far[c] = 0 if owner[c] == p else 1e9
	sweep :: proc(far: []f32, n: int, d: f32) {
		steps := [4][3]f32{{-1, 0, 1}, {0, -1, 1}, {-1, -1, math.SQRT_TWO}, {1, -1, math.SQRT_TWO}}
		for pass in 0..<2 do for i in 0..<n*n {
			c := i if pass == 0 else n*n - 1 - i
			x, y := c%n, c/n
			for s in steps {
				dx, dy := int(s.x) if pass == 0 else -int(s.x), int(s.y) if pass == 0 else -int(s.y)
				if nx, ny := x + dx, y + dy; nx >= 0 && ny >= 0 && nx < n && ny < n do far[c] = min(far[c], far[ny*n + nx] + s.z*d)
			}
		}
	}
	sweep(far, n, g.d)
	h := new(Holding)
	h.held, h.index, h.rose = make([]bool, n*n), make([]i32, n*n), make([]f32, n*n)
	for c in 0..<n*n do h.rose[c] = store_rose(&all.m.store, (f32(c%n + g.at.x) + 0.5)*g.d/64, (f32(c/n + g.at.z) + 0.5)*g.d/64)
	slice.fill(h.index, -1)
	cells, bands, at, coarse := make([dynamic]i32), make([dynamic]^Band), make([dynamic]i32), make([dynamic]Held)
	// The coarse pass at a point, metres from the lattice's corner: its height by the four cells round it.
	coarse_z :: proc(pass: ^Grid, x, z: f32) -> f32 {
		u, v := x/pass.d - 0.5 - f32(pass.at.x), z/pass.d - 0.5 - f32(pass.at.z)
		i, j := clamp(int(math.floor(u)), 0, pass.n - 2), clamp(int(math.floor(v)), 0, pass.n - 2)
		tu, tv := clamp(u - f32(i), 0, 1), clamp(v - f32(j), 0, 1)
		k := j*pass.n + i
		return math.lerp(math.lerp(pass.z[k], pass.z[k + 1], tu), math.lerp(pass.z[k + pass.n], pass.z[k + pass.n + 1], tu), tv)
	}
	for c in 0..<n*n {
		q := owner[c]
		if q == p do continue
		if earlier(cut, q, p) {
			k := lattice_of(g, c)
			found := false
			for b in f.held[q] do if int(math.round(f32(b.cell))) == int(math.round(g.d)) {
				if i, ok := b.place[k]; ok {
					append(&cells, i32(c)); append(&bands, b); append(&at, i); append(&coarse, Held{})
					found = true
				}
			}
			if found do continue
		} else if far[c] <= all.margin do continue   // margin: formed, and let go
		x, z := (f32(c%n + g.at.x) + 0.5)*g.d, (f32(c/n + g.at.z) + 0.5)*g.d
		h0 := coarse_z(pass, x, z)
		append(&cells, i32(c)); append(&bands, nil); append(&at, 0); append(&coarse, Held{z0 = h0, fill = h0, z1 = h0, z2 = h0, z3 = h0, next = -1})
	}
	h.cells, h.band, h.at, h.coarse = cells[:], bands[:], at[:], coarse[:]
	h.vals = make([]Held, len(h.cells))
	for c, i in h.cells {
		h.held[c] = true
		h.index[c] = i32(i)
	}
	// Water and rock the coarse pass brings in: each coarse cell held whole whose water runs into a
	// coarse cell with a cell this grid forms brings its land drained and its rock, which enter at the
	// lowest such cell.
	h.into = make([dynamic][3]f32)
	m := n/scale
	for j in 0..<m do for i in 0..<m {
		k := (j + g.at.z/scale - pass.at.z)*pass.n + i + g.at.x/scale - pass.at.x
		if k < 0 || k >= pass.n*pass.n || pass.sea[k] || pass.next[k] < 0 do continue
		whole := true
		for y in 0..<scale do for x in 0..<scale do whole &&= h.held[(j*scale + y)*n + i*scale + x]
		if !whole do continue
		r := int(pass.next[k])
		ri, rj := r%pass.n + pass.at.x - g.at.x/scale, r/pass.n + pass.at.z - g.at.z/scale
		if ri < 0 || rj < 0 || ri >= m || rj >= m do continue
		low := -1
		for y in 0..<scale do for x in 0..<scale {
			c := (rj*scale + y)*n + ri*scale + x
			if !h.held[c] && !g.sea[c] && (low < 0 || g.z[c] < g.z[low]) do low = c
		}
		if low >= 0 do append(&h.into, [3]f32{f32(low), pass.area[k], pass.load[k]/max(pass_years(), 1)})
	}
	// Its own cells within BAND of a piece formed after it, kept for that piece.
	keep := make([dynamic]i32)
	for c in 0..<n*n do if owner[c] == p {
		x, y := c%n, c/n
		near := false
		for dy in -BAND..=BAND do for dx in -BAND..=BAND {
			if near do break
			if x + dx < 0 || y + dy < 0 || x + dx >= n || y + dy >= n do continue
			q := owner[(y + dy)*n + x + dx]
			near ||= q >= 0 && earlier(cut, p, q)
		}
		if near do append(&keep, i32(c))
	}
	h.keep = keep[:]
	// The cells of the pieces after it within LEAN of its own, which it forms as margin: kept for them.
	toward := make([dynamic]i32)
	for c in 0..<n*n do if q := owner[c]; q >= 0 && q != p && far[c] <= LEAN && !h.held[c] && earlier(cut, p, q) do append(&toward, i32(c))
	h.toward = toward[:]
	// Its own cells that an earlier neighbour formed as margin lean toward what it made of them.
	leans := make([dynamic]Lean)
	for c in 0..<n*n do if owner[c] == p {
		k := lattice_of(g, c)
		for q in cut.near[p] do if earlier(cut, q, p) do for b in f.held[q] do if b.cell == int(math.round(g.d)) {
			if i, ok := b.there[k]; ok {
				x := clamp((b.apart[i] - g.d/2)/LEAN, 0, 1)
				if w := (1 - x)*(1 - x); w > 0 do append(&leans, Lean{i32(c), b, i, w})
			}
		}
	}
	h.leans = leans[:]
	b := new(Band)
	b.cell = int(math.round(g.d))
	b.cells = make([]i32, len(h.keep))
	b.place = make(map[i32]i32, len(h.keep))
	for c, i in h.keep {
		b.cells[i] = lattice_of(g, int(c))
		b.place[b.cells[i]] = i32(i)
	}
	b.toward, b.apart = make([]i32, len(h.toward)), make([]f32, len(h.toward))
	for c, i in h.toward do b.toward[i], b.apart[i] = lattice_of(g, int(c)), far[c]
	h.out = b
	append(&f.out, b)
	g.holding = h
}

// Years in a step of the coarse pass's last phase, which its rock carried down is counted over.
pass_years :: proc() -> f32 {
	last: f32
	for p in region.history do if p.cell >= 64 do last = p.years
	return last
}

// Form piece `p` from the coarse pass, holding what the pieces formed before it left, which are read
// back from where they were kept: its finished grid, the bands it leaves for the pieces after it, and
// the bands it held, which its grid still reads until it is finished.
piece_form :: proc(all: ^Pieces, p: i32) -> (g: ^Grid, out: [dynamic]^Band, held: map[i32][dynamic]^Band) {
	m := all.m
	w := m.cut.window[p]
	f := Piece_Form{all = all, p = p}
	f.pass, f.owner = store_window(&m.store, {int(w.x) - 1, int(w.y) - 1}, int(w.z) + 2)
	for q in m.cut.near[p] do if earlier(&m.cut, q, p) do f.held[q] = band_load(m, q)
	defer {
		delete(f.owner)
		grid_free(f.pass)
	}
	g = form_phases(piece_grid(&f), all.from, len(region.history), piece_level, &f)
	return g, f.out, f.held
}

FOUR :: [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

// ---- the landmasses in the game -----------------------------------------------------------------

PIECE_KM2 :: 300        // km² of land in a piece, about; a basin larger is cut across its trunk
MARGIN    :: 6000       // metres a piece forms past the cut toward pieces not yet formed
MASS_PAD  :: 8192       // metres of sea round the landmass's land on its lattice
// How near the player (or, before entering, the start or a site) a landmass's pieces are formed, and
// how far they are kept: beyond, a piece's land is let go, and read back from where it was kept when
// the player comes near again. Past the formed pieces the land is drawn from the coarse stage.
NEAR_REACH       :: 16_000
BACKGROUND_REACH :: 40_000
// How near the start, a site or the view a landmass must lie for its coarse stage to be formed where
// it is not kept already and the whole world's is not asked for (--continent=1): within what is drawn.
COARSE_REACH :: 80_000

lands: []Landmass   // every land mass of the known world larger than a region, the nearest the start first

// How the land larger than a region stands as a whole, for the thread that makes a world and the
// screens that watch it (making.odin, chart.odin): each a word, stored whole.
Lands_State :: struct {
	regions: bool,      // the pieces of the land masses at hand are regions in `formed` (regions_make): until then no point is anybody's piece
	step, steps: i32,   // how far the coarse stages being formed have come, of how many steps of their histories: for the eye
	forming: i32,       // the land mass whose coarse stage is being formed, or 0
	leave:   bool,      // the coarse stage being formed is to be left where it stands, and those after it: they stay records
	expect:  f64,       // seconds the coarse stages to be formed are expected to take in all (mass_seconds)
	began:   time.Time, // when the first of them was begun
}
lands_state: Lands_State

// Seconds a land mass's coarse stage takes to form on this kind of machine, about: 25 s for 45,000 km²
// and 200 to 360 s for 317,000 km², by the load (continents-forming.md). For the screen that says
// what forming one would cost.
mass_seconds :: proc(m: ^Landmass) -> f64 { return 5 + 0.0008*f64(m.area) }

// The coarse stages of the world's land masses (mass_pass), as start-up and the making of a world
// both ask for them: one that is kept is read back; one that is not is formed if `all` is asked for
// or it lies within COARSE_REACH of the start or of one of `views`; none is touched with `none`.
// How far the forming has come is counted for the screen, and it can be left (lands_state).
// Returns how many pieces the land masses at hand are cut into.
lands_pass :: proc(views: [][2]f64, all, none: bool) -> (pieces: int) {
	ls := &lands_state
	if none || len(lands) == 0 do return
	began := time.now()
	form := make([]bool, len(lands), context.temp_allocator)
	steps, expect := 0, f64(0)
	for &m, i in lands {
		near := m.near
		for v in views do near = min(near, mass_from(&m, v))
		form[i] = all || near <= COARSE_REACH
		if form[i] && !os.exists(pass_path(&m)) {
			mass_bind(&m, &m.frame, -1, m.origin, m.side)
			for p in region.history do if p.cell >= 64 do steps += int(p.steps)
			expect += mass_seconds(&m)
		}
	}
	ls.expect, ls.began = expect, time.now()
	sync.atomic_store(&ls.step, 0)
	sync.atomic_store(&ls.steps, i32(steps))
	left, left_area := 0, f32(0)
	for &m, i in lands {
		if mass_pass(&m, form[i] && !sync.atomic_load(&ls.leave)) do pieces += len(m.cut.size)
		else do left, left_area = left + 1, left_area + m.area
	}
	if left > 0 do fmt.printfln("land larger than a region: %d land masses, %.0f km², lie beyond what is drawn from here and their coarse stage is not kept, or were left: they stay records until a view comes within %.0f km of them or --continent=1 forms the whole world's", left, left_area, f64(COARSE_REACH)/1000)
	if pieces > 0 do fmt.printfln("land larger than a region: the coarse stages at hand in %.1f s, %d pieces in all", time.duration_seconds(time.since(began)), pieces)
	return
}

// Put the land masses down with their world: each one's coarse stage is let go of (it is a file,
// mapped) and its cut freed. The pieces formed stay where they lie, as formed islands do, and so do
// the records themselves, which those pieces still point at (making.odin). No thread is forming.
lands_drop :: proc() {
	sync.atomic_store_explicit(&lands_state.regions, false, .Release)
	for &m in lands {
		if !m.ready do continue
		m.ready = false
		store_close(&m.store)
		cut := &m.cut
		delete(cut.down); delete(cut.depth); delete(cut.rank); delete(cut.size); delete(cut.box); delete(cut.window)
		for l in cut.near do delete(l)
		delete(cut.near)
		cut^ = {}
		delete(m.all.formed)
		m.all = {}
	}
	lands = nil
	lands_state = {}
}

// How many pieces of the land masses at hand lie within `reach` metres of a point and are not formed.
masses_near :: proc(at: [2]f64, reach: f64) -> (count: int) {
	if !sync.atomic_load_explicit(&lands_state.regions, .Acquire) do return
	for &m in lands do if m.ready do for p in mass_order(&m, at, reach) do count += int(!is_formed(&formed[m.first + int(p)]))
	return
}

// Form the pieces within `reach` metres of a point, each after those it waits on, side by side: what
// must stand before a world is entered there. Returns how many were asked for.
masses_form :: proc(at: [2]f64, reach: f64) -> (count: int) {
	if !sync.atomic_load_explicit(&lands_state.regions, .Acquire) do return
	for &m in lands do if m.ready {
		near := mass_order(&m, at, reach, context.allocator)   // its own memory: forming frees the temporary as it goes
		was := quiet
		quiet = true
		mass_form(&m, near, max(os.get_processor_core_count() - 2, 1))
		quiet = was
		count += len(near)
		delete(near)
	}
	return
}

// Every land mass of the known world larger than a region can hold: their records.
lands_make :: proc() {
	list := make([dynamic]Landmass)
	for mass, k in known.masses do if mass.large {
		id := i32(k + 1)
		lo, hi := [2]f64{1e12, 1e12}, [2]f64{-1e12, -1e12}
		top, start, near := f32(0), -1, f32(1e9)
		for _, i in known.samples do if known.mass[i] == id {
			at := [2]f32{f32(i%KNOWN_N) + 0.5, f32(i/KNOWN_N) + 0.5}*KNOWN_STEP - WINDOW/2
			w := world_of(at)
			lo, hi = {min(lo.x, w.x), min(lo.y, w.y)}, {max(hi.x, w.x), max(hi.y, w.y)}
			top = max(top, known.samples[i].h)
			if d := linalg.length(at - world_frame.start); d < near do start, near = i, d
		}
		lo, hi = lo - MASS_PAD - f64(KNOWN_STEP)*500, hi + MASS_PAD + f64(KNOWN_STEP)*500
		middle := (lo + hi)/2
		append(&list, Landmass{mass = id, origin = {i32(math.round(middle.x/1024))*1024, i32(math.round(middle.y/1024))*1024}, side = math.ceil(max(hi.x - lo.x, hi.y - lo.y)/4096)*4096,
			area = mass.area, top = top, near = f64(near - KNOWN_STEP/2)*1000, seed = hash(i32(start), 21, world_seed + 2100),
			shore = world_of([2]f32{f32(start%KNOWN_N) + 0.5, f32(start/KNOWN_N) + 0.5}*KNOWN_STEP - WINDOW/2)})
	}
	slice.sort_by(list[:], proc(a, b: Landmass) -> bool { return a.near < b.near || a.near == b.near && a.mass < b.mass })
	lands = list[:]
	if len(lands) == 0 {
		fmt.println("no land larger than a region in the known world")
		return
	}
	all: f32
	for m in lands do all += m.area
	fmt.printfln("land larger than a region in the known world: %d land masses, %.0f km² in all; the nearest the start %.0f km² of land, its coast %.0f km off at %.0f, %.0f, the history's ground up to %.0f m; the largest %.0f km²",
		len(lands), all, lands[0].area, lands[0].near/1000, lands[0].shore.x, lands[0].shore.y, lands[0].top, slice.max(slice.mapper(lands, proc(m: Landmass) -> f32 { return m.area }, context.temp_allocator)))
}

// Bind a landmass's own region, or a piece's, its record drawn from the landmass's seed as an island's is.
mass_bind :: proc(m: ^Landmass, f: ^Formed, id: int, origin: [2]i32, size: f64) {
	f.island = {id = id, origin = origin, size = size, kind = mass_kind(), seed = m.seed, setting = .Continent}
	bind(f)   // after its seed is set: binding reads the seed, and helper threads bind the same record
	f.region.origin, f.region.size, f.region.mass, f.landslide = m.origin, m.side, m, {box = {1e9, 1e9, -1e9, -1e9}}
	q := quiet
	quiet = true
	region_init("mainland", m.side)
	quiet = q
	region.origin, region.mass = m.origin, m   // region_init keeps them; set again in case
	region.shape.swell = world_frame.wind
	climate_init(Island{origin = m.origin})   // one climate for the whole landmass, read at its middle (a weak point: it spans many degrees)
	quiet = true
	rock_init(false)
	quiet = q
}

mass_kind :: proc() -> int {
	for k, i in KINDS do if k.name == "mainland" do return i
	return -1
}

// A landmass's coarse stage: the whole of it formed through its 64 m phases and cut along its drainage,
// or read back from where it was kept. With `form` false, only if it is kept.
mass_pass :: proc(m: ^Landmass, form: bool) -> bool {
	started := time.now()
	mass_bind(m, &m.frame, -1, m.origin, m.side)
	m.from, m.rest = 0, 0
	for p, i in region.history do if p.cell >= 64 do m.from = i + 1
	for p in region.history[m.from:] do m.rest += p.steps*p.years
	n := int(m.side)/64
	m.path = pass_path(m)
	path := m.path
	kept := store_open(&m.store, path, n)
	m.kept, m.left = kept, false
	if !kept {
		if !form do return false
		fmt.printfln("land mass %d: %.0f km² of land in the known world, on a lattice %.0f km across, its middle at %d, %d: its coarse stage, the whole of it through the 64 m phases", m.mass, m.area, m.side/1000, m.origin.x, m.origin.y)
		sync.atomic_store(&lands_state.forming, m.mass)
		g := coarse_form(n, m.from)
		sync.atomic_store(&lands_state.forming, 0)
		if sync.atomic_load(&lands_state.leave) {   // left where it stood: nothing of it is kept, and it stays a record
			coarse_free(g)
			grid_free(g)
			m.left = true
			fmt.printfln("land mass %d: its coarse stage was left before it had run; it stays a record", m.mass)
			return false
		}
		cutting := time.now()
		cut, own := cut_make(g, PIECE_KM2*1e6/4096, MARGIN)
		cut_time := time.duration_seconds(time.since(cutting))
		_ = os.make_directory(os.dir(path))
		if !store_write(path, g, &cut, own) do fmt.eprintln("could not keep the coarse stage in", path)
		fmt.printfln("land mass %d: cut along its drainage into %d pieces in %.1f s, and kept in %.1f s", m.mass, len(cut.size), cut_time, time.duration_seconds(time.since(cutting)) - cut_time)
		delete(own)
		coarse_free(g)
		grid_free(g)
		if !store_open(&m.store, path, n) do return false
	}
	// The cut, as it is kept.
	st := &m.store
	count := len(st.pieces)
	c := &m.cut
	c.down, c.depth, c.rank, c.size = make([]i32, count), make([]i32, count), make([]i32, count), make([]i32, count)
	c.near, c.box, c.window = make([][dynamic]i32, count), make([][4]i32, count), make([][3]i32, count)
	land_cells := 0
	for p, i in st.pieces {
		c.down[i], c.depth[i], c.rank[i], c.size[i], c.box[i], c.window[i] = p.down, p.depth, p.rank, p.size, p.box, p.window
		land_cells += int(p.size)
	}
	for k in st.pairs { append(&c.near[k.x], k.y); append(&c.near[k.y], k.x) }
	for &l in c.near do slice.sort(l[:])
	m.all = Pieces{m = m, from = m.from, margin = MARGIN, formed = make([]bool, count)}
	m.took = time.duration_seconds(time.since(started))
	sync.atomic_store(&m.ready, true)
	// How many pieces each waits on: the cost of forming one alone, anywhere.
	waits := make([]int, count, context.temp_allocator)
	deepest := i32(0)
	for p in 0..<count {
		waits[p] = len(cut_waits(c, i32(p)))
		deepest = max(deepest, c.depth[p])
	}
	slice.sort(waits)
	fmt.printfln("land mass %d: its coarse stage, %.0f km² of land before the sea's last rise in %d pieces, %s in %.1f s (%.0f MB kept); the pieces up to %d from the sea along their drainage, each waiting on a median %d before it, 90%% on %d or fewer, at most %d",
		m.mass, f64(land_cells)*4096/1e6, count, "read back from where it was kept" if kept else "formed", time.duration_seconds(time.since(started)), f64(len(st.file))/1e6,
		deepest, waits[count/2] if count > 0 else 0, waits[count*9/10] if count > 0 else 0, waits[count - 1] if count > 0 else 0)
	if !kept && count > 0 {   // how high the land stands, as the forming's own figures on it
		heights := make([dynamic]f32)
		defer delete(heights)
		for slot in 0..<len(st.z) do for k in 0..<KEPT_CELLS do if st.next[slot][k] != NEXT_SEA do append(&heights, st.z[slot][k])
		slice.sort(heights[:])
		dry := 0
		for h in heights do if h > st.rise do dry += 1
		fmt.printfln("land mass %d: its land before the sea's last rise of %.0f m: median %.0f m, 90th percentile %.0f m, highest %.0f m; %.0f%% of it stays over that rise", m.mass, st.rise, heights[len(heights)/2], heights[len(heights)*9/10], heights[len(heights) - 1], 100*f64(dry)/f64(len(heights)))
	}
	return true
}

// The landmass whose lattice holds a point in the world and the piece the point lies in, or nil: off
// every lattice, or out on the open sea.
mass_piece :: proc(x, z: f64) -> (^Landmass, int) {
	if !sync.atomic_load_explicit(&lands_state.regions, .Acquire) do return nil, -1
	for &m in lands do if m.ready {
		n := m.store.n
		u, v := int(math.floor((x - f64(m.origin.x))/64 + f64(n)/2)), int(math.floor((z - f64(m.origin.y))/64 + f64(n)/2))
		if p := store_owner(&m.store, u, v); p >= 0 do return &m, p
	}
	return nil, -1
}

// The world square a piece forms on: its middle and side.
piece_square :: proc(m: ^Landmass, p: i32) -> (origin: [2]i32, size: f64) {
	w, n := m.cut.window[p], m.store.n
	return {m.origin.x + i32((f64(w.x) + f64(w.z)/2 - f64(n)/2)*64), m.origin.y + i32((f64(w.y) + f64(w.z)/2 - f64(n)/2)*64)}, f64(w.z)*64
}

// Form the pieces listed, and everything that lives on them, with the pieces they wait on, side by
// side on up to `threads` threads: each once the earlier neighbours it holds are formed. A piece is
// the same whatever is formed beside it, so the order they are taken in decides nothing.
mass_form :: proc(m: ^Landmass, want: []i32, threads: int) {
	sync.lock(&m.mutex)
	defer sync.unlock(&m.mutex)
	Work :: struct {
		m:      ^Landmass,
		need:   []u8,           // by piece: 1, formed because another waits on it; 2, wanted as a region
		left:   []i32,          // earlier neighbours still to form
		ready:  [dynamic]i32,
		read_back: []bool,      // wanted, and kept already: it waits on nothing
		todo:   int,
		mutex:  sync.Mutex,
		wake:   sync.Cond,
		quiet:  bool,
	}
	count := len(m.cut.size)
	w := Work{m = m, need = make([]u8, count), left = make([]i32, count), read_back = make([]bool, count), quiet = quiet}
	defer { delete(w.need); delete(w.left); delete(w.ready); delete(w.read_back) }
	stack := make([dynamic]i32)
	defer delete(stack)
	for p in want do if !is_formed(&formed[m.first + int(p)]) && w.need[p] == 0 {
		w.need[p] = 2
		append(&stack, p)
	}
	for len(stack) > 0 {
		q := pop(&stack)
		w.todo += 1
		if w.need[q] == 2 && piece_kept(m, q) {   // read back: it waits on nothing
			w.read_back[q] = true
			continue
		}
		for r in m.cut.near[q] do if earlier(&m.cut, r, q) && !m.all.formed[r] {
			if piece_kept(m, r) {
				m.all.formed[r] = true
				continue
			}
			w.left[q] += 1
			if w.need[r] == 0 {
				w.need[r] = 1
				append(&stack, r)
			}
		}
	}
	if w.todo == 0 do return
	for p in 0..<i32(count) do if w.need[p] != 0 && w.left[p] == 0 do append(&w.ready, p)
	worker :: proc(w: ^Work) {
		m := w.m
		was_alone, was_quiet, was := alone, quiet, here
		alone, quiet = true, w.quiet
		defer { alone, quiet = was_alone, was_quiet; bind(was) }
		for {
			sync.lock(&w.mutex)
			for len(w.ready) == 0 && w.todo > 0 do sync.cond_wait(&w.wake, &w.mutex)
			if sync.atomic_load(&forming.stop) do w.todo = 0   // told to stop (making.odin): no piece is begun; those in hand are finished
			if w.todo == 0 {
				sync.unlock(&w.mutex)
				sync.cond_broadcast(&w.wake)
				return
			}
			p := pop(&w.ready)
			sync.unlock(&w.mutex)
			waited_on := !piece_kept(m, p)   // read back, it was counted by none of the pieces after it
			piece_make(m, p, w.need[p] == 2)
			free_all(context.temp_allocator)
			sync.lock(&w.mutex)
			w.todo -= 1
			if waited_on do for s in m.cut.near[p] do if w.need[s] != 0 && earlier(&m.cut, p, s) && !(w.need[s] == 2 && w.read_back[s]) {
				w.left[s] -= 1
				if w.left[s] == 0 do append(&w.ready, s)
			}
			sync.unlock(&w.mutex)
			sync.cond_broadcast(&w.wake)
		}
	}
	pool := make([]^thread.Thread, max(min(threads, w.todo) - 1, 0))
	defer delete(pool)
	for &t in pool do t = thread.create_and_start_with_poly_data(&w, worker)
	worker(&w)
	for t in pool {
		thread.join(t)
		thread.destroy(t)
	}
}

// The coarse stage's ground at a cell of the lattice of the landmass in hand; the open sea off it.
mass_z64 :: proc(i, j: int) -> f32 {
	m := region.mass
	return store_z(&m.store, i, j) if m != nil && m.ready else SEA_BED
}

// Metres from a point in the world to the land of piece `p`.
mass_off :: proc(m: ^Landmass, p: i32, at: [2]f64) -> f64 {
	b, n := m.cut.box[p], m.store.n
	lo := [2]f64{f64(m.origin.x) + (f64(b.x) - f64(n)/2)*64, f64(m.origin.y) + (f64(b.y) - f64(n)/2)*64}
	hi := [2]f64{f64(m.origin.x) + (f64(b.z) + 1 - f64(n)/2)*64, f64(m.origin.y) + (f64(b.w) + 1 - f64(n)/2)*64}
	return math.hypot(max(lo.x - at.x, at.x - hi.x, 0), max(lo.y - at.y, at.y - hi.y, 0))
}

// A landmass's pieces within `reach` of a point, nearest first.
mass_order :: proc(m: ^Landmass, at: [2]f64, reach: f64, allocator := context.temp_allocator) -> []i32 {
	Near :: struct { far: f64, p: i32 }
	near := make([dynamic]Near, context.temp_allocator)
	for p in 0..<i32(len(m.cut.size)) do if far := mass_off(m, p, at); far <= reach do append(&near, Near{far, p})
	slice.sort_by(near[:], proc(a, b: Near) -> bool { return a.far < b.far || a.far == b.far && a.p < b.p })
	order := make([]i32, len(near), allocator)
	for v, i in near do order[i] = v.p
	return order
}

PASS_VERSION :: 6   // raised whenever what this file or coarse.odin does to form or keep the coarse stage changes

// Where the coarse stage of a landmass is kept: beside the known world, named by the seed and by what
// forms it, so a change to the forming forms it again.
pass_path :: proc(m: ^Landmass) -> string {
	SOURCES :: #load_hash("land.odin", "fnv32a") ~ #load_hash("erosion.odin", "fnv32a") ~ #load_hash("rock.odin", "fnv32a") ~ #load_hash("gen.odin", "fnv32a") ~ #load_hash("known.odin", "fnv32a") ~ #load_hash("plates.odin", "fnv32a") ~ #load_hash("coarse.odin", "fnv32a")
	return fmt.aprintf("%s/worlds/landmass-%d-%d-%d-%08x.bin", os.dir(os.args[0]), world_seed, m.mass, PASS_VERSION, u32(SOURCES))
}

// ---- a piece in the game --------------------------------------------------------------------------

// Form one piece whose earlier neighbours are formed, or read it back from where it was kept. A piece
// formed is kept at once: its finished grid, and the bands it leaves for the pieces after it, which
// are read back when one of those is formed and held in memory no longer. With `live` the piece is
// then made a region like an island's, with all that lies and lives on it; without, it was wanted
// only because another waits on it, and takes no memory.
piece_make :: proc(m: ^Landmass, p: i32, live: bool) {
	f := &formed[m.first + int(p)]
	started := time.now()
	kept := piece_kept(m, p)
	if !live && kept {
		m.all.formed[p] = true
		return
	}
	origin, size := piece_square(m, p)
	mass_bind(m, f, m.first + int(p), origin, size)
	g := piece_load(m, p) if kept else nil
	if g == nil {
		kept = false
		out: [dynamic]^Band
		held: map[i32][dynamic]^Band
		g, out, held = piece_form(&m.all, p)
		// The land as it is left: routed once more with its held cells at their last, and its outermost
		// cells, which are held and not its own, the sea, as an island's rim is, for what reads a cell's
		// neighbours.
		h := g.holding
		h.step = max(h.step - 1, 0)
		held_values(g)
		held_stage(g, 3)
		for c in 0..<g.n*g.n do if x, y := c%g.n, c/g.n; x < 2 || y < 2 || x >= g.n - 2 || y >= g.n - 2 {
			g.z[c], g.sea[c] = min(g.z[c], -1), true
		}
		route(g)
		// Held cells drain as the pieces they are held to left them, so a stream runs on through the band
		// into the piece below; where it leaves the window it goes ONWARD, and no mouth is made there.
		for c, i in h.cells {
			v := h.vals[i]
			if g.sea[c] do continue
			g.area[c] = v.area
			r := lattice_cell(g, v.next) if v.next != -1 else -1
			g.next[c] = i32(r) if r >= 0 else ONWARD if v.next != -1 else -1
		}
		order_make(g)
		g = piece_crop(g, m, p)
		for _, l in held do band_free(l)
		delete(held)
		piece_save(m, p, g)
		band_save(m, p, out[:])
		band_free(out)
		m.all.formed[p] = true
		// The bands of the pieces before it that no piece still to form reads are kept no longer.
		for q in m.cut.near[p] do if m.all.formed[q] {
			needed := false
			for r in m.cut.near[q] do needed ||= !m.all.formed[r] && m.cut.rank[r] > m.cut.rank[q]
			if !needed do _ = os.remove(piece_path(m, q, "bands"))
		}
	}
	m.all.formed[p] = true
	b, w := m.cut.box[p], m.cut.window[p]
	if !live {
		grid_free(g)
		if !quiet do fmt.printfln("land mass %d piece %d: %.0f km² of land, formed on a window %.1f km across in %.1f s and kept, for a piece that waits on it", m.mass, p, f64(m.cut.size[p])*4096/1e6, f64(w.z)*64/1000, time.duration_seconds(time.since(started)))
		return
	}
	n := g.n
	land.n, land.grid, land.z[0], land.at = n, g, g.z, g.at
	land.slid, land.lake = make([]f32, n*n), make([]u8, n*n)
	land_finish(g, false)
	land_finish(g)
	if rocks.full do pebbles_make(g)
	rivers_trace()
	plants_init()
	hollows_make()
	trails_make()
	places_make()
	creatures_make()
	f.seconds = time.duration_seconds(time.since(started))
	m.seconds += f.seconds
	sync.atomic_store_explicit(&f.ready, true, .Release)
	if !quiet do fmt.printfln("land mass %d piece %d: %.0f km² of land, its own box %.1f by %.1f km, %s, on land %.1f km across, in %.1f s",
		m.mass, p, f64(m.cut.size[p])*4096/1e6, f64(b.z - b.x + 1)*0.064, f64(b.w - b.y + 1)*0.064,
		"read back from where it was kept" if kept else fmt.tprintf("formed on a window %.1f km across", f64(w.z)*64/1000), f64(n)*LAND_CELL/1000, f.seconds)
}

// Where a piece's finished grid or its bands are kept.
piece_path :: proc(m: ^Landmass, p: i32, what: string) -> string {
	SOURCES :: #load_hash("continents.odin", "fnv32a") ~ #load_hash("events.odin", "fnv32a")
	return fmt.tprintf("%s.piece-%d-%08x.%s", m.path[:len(m.path) - 4], p, u32(SOURCES), what)
}

piece_kept :: proc(m: ^Landmass, p: i32) -> bool { return os.exists(piece_path(m, p, "land")) }

Piece_Head :: struct { n, x, z, lattice, order: i32, left, lift, rise: f32 }

// Keep a piece's finished grid: where it lies, and what the forming left in each cell. What a cell is
// given at the start (its rock, its uplift) is worked out again when it is read back.
piece_save :: proc(m: ^Landmass, p: i32, g: ^Grid) {
	out := make([dynamic]u8)
	defer delete(out)
	head := Piece_Head{i32(g.n), i32(g.at.x), i32(g.at.z), i32(g.at.n), i32(len(g.order)), g.left, g.lift, g.rise}
	append(&out, ..mem.ptr_to_bytes(&head))
	for a in ([?][]f32{g.z, g.fill, g.area, g.cut, g.face, g.load}) do append(&out, ..slice.to_bytes(a))
	append(&out, ..slice.to_bytes(g.next))
	append(&out, ..slice.to_bytes(g.order[:]))
	append(&out, ..slice.to_bytes(g.sea))
	path := piece_path(m, p, "land")
	temp := fmt.tprintf("%s.%d", path, os.get_pid())
	if err := os.write_entire_file(temp, out[:]); err == nil { _ = os.rename(temp, path) } else do fmt.eprintln("could not keep a piece in", path)
}

// A piece's finished grid, read back; nil if it is not kept whole. The region bound is the piece's.
piece_load :: proc(m: ^Landmass, p: i32) -> ^Grid {
	data, err := os.read_entire_file(piece_path(m, p, "land"), context.allocator)
	if err != nil do return nil
	defer delete(data)
	if len(data) < size_of(Piece_Head) do return nil
	head := (^Piece_Head)(raw_data(data))^
	n := int(head.n)
	if len(data) != size_of(Piece_Head) + n*n*(7*4 + 1) + int(head.order)*4 do return nil
	g := grid_make(n, {int(head.x), int(head.z), int(head.lattice)})
	at := size_of(Piece_Head)
	take :: proc(dst: []$T, data: []u8, at: ^int) { copy(slice.to_bytes(dst), data[at^:][:len(dst)*size_of(T)]); at^ += len(dst)*size_of(T) }
	for a in ([?][]f32{g.z, g.fill, g.area, g.cut, g.face, g.load}) do take(a, data, &at)
	take(g.next, data, &at)
	resize_dynamic_array(&g.order, int(head.order))
	take(g.order[:], data, &at)
	take(g.sea, data, &at)
	g.left, g.lift, g.rise = head.left, head.lift, head.rise
	return g
}

// Keep the bands a piece left for the pieces after it.
band_save :: proc(m: ^Landmass, p: i32, bands: []^Band) {
	out := make([dynamic]u8)
	defer delete(out)
	count := i32(len(bands))
	append(&out, ..mem.ptr_to_bytes(&count))
	for b in bands {
		head := [5]i32{i32(b.cell), i32(len(b.cells)), i32(len(b.vals)), i32(len(b.toward)), i32(len(b.lean))}
		append(&out, ..mem.ptr_to_bytes(&head))
		append(&out, ..slice.to_bytes(b.cells))
		for v in b.vals do append(&out, ..slice.to_bytes(v))
		append(&out, ..slice.to_bytes(b.toward))
		append(&out, ..slice.to_bytes(b.apart))
		for v in b.lean do append(&out, ..slice.to_bytes(v))
	}
	path := piece_path(m, p, "bands")
	temp := fmt.tprintf("%s.%d", path, os.get_pid())
	if err := os.write_entire_file(temp, out[:]); err == nil { _ = os.rename(temp, path) } else do fmt.eprintln("could not keep a piece's bands in", path)
}

band_load :: proc(m: ^Landmass, p: i32) -> (bands: [dynamic]^Band) {
	data, err := os.read_entire_file(piece_path(m, p, "bands"), context.allocator)
	if err != nil {
		fmt.eprintfln("land mass %d piece %d: the bands it left for the pieces after it are not where they were kept", m.mass, p)
		return
	}
	defer delete(data)
	at := 4
	for _ in 0..<(^i32)(raw_data(data))^ {
		head := (^[5]i32)(&data[at])^
		at += 20
		b := new(Band)
		b.cell = int(head[0])
		b.cells = make([]i32, head[1])
		copy(slice.to_bytes(b.cells), data[at:])
		at += int(head[1])*4
		b.place = make(map[i32]i32, int(head[1]))
		for c, i in b.cells do b.place[c] = i32(i)
		for _ in 0..<head[2] {
			v := make([]Held, head[1])
			copy(slice.to_bytes(v), data[at:])
			at += int(head[1])*size_of(Held)
			append(&b.vals, v)
		}
		b.toward, b.apart = make([]i32, head[3]), make([]f32, head[3])
		copy(slice.to_bytes(b.toward), data[at:])
		at += int(head[3])*4
		copy(slice.to_bytes(b.apart), data[at:])
		at += int(head[3])*4
		b.there = make(map[i32]i32, int(head[3]))
		for c, i in b.toward do b.there[c] = i32(i)
		for _ in 0..<head[4] {
			v := make([]f32, head[3])
			copy(slice.to_bytes(v), data[at:])
			at += int(head[3])*4
			append(&b.lean, v)
		}
		append(&bands, b)
	}
	return
}

band_free :: proc(bands: [dynamic]^Band) {
	for b in bands {
		for v in b.vals do delete(v)
		for v in b.lean do delete(v)
		delete(b.vals); delete(b.cells); delete(b.place); delete(b.toward); delete(b.apart); delete(b.lean); delete(b.there)
		free(b)
	}
	delete(bands)
}

CROP :: 64   // fine cells kept round a finished piece's own land, for what reads the land round a cell

// A finished piece's grid cut down to its own cells and CROP round them: a new grid, the old let go.
// Where a cell's water leaves the crop it leaves the piece; the cells keep the order they were in.
piece_crop :: proc(g: ^Grid, m: ^Landmass, p: i32) -> ^Grid {
	scale := int(math.round(64/g.d))
	b := m.cut.box[p]
	lo := [2]int{int(b.x)*scale - g.at.x - CROP, int(b.y)*scale - g.at.z - CROP}
	hi := [2]int{(int(b.z) + 1)*scale - g.at.x + CROP, (int(b.w) + 1)*scale - g.at.z + CROP}
	lo, hi = {max(lo.x, 0), max(lo.y, 0)}, {min(hi.x, g.n), min(hi.y, g.n)}
	side := max(hi.x - lo.x, hi.y - lo.y)
	side = (side + 3)/4*4
	lo = {clamp(lo.x, 0, g.n - side), clamp(lo.y, 0, g.n - side)}
	c := grid_make_empty(side, {g.at.x + lo.x, g.at.z + lo.y, g.at.n})
	from :: proc(g: ^Grid, side: int, lo: [2]int, k: int) -> int { return (k/side + lo.y)*g.n + k%side + lo.x }
	for k in 0..<side*side {
		o := from(g, side, lo, k)
		c.z[k], c.fill[k], c.area[k], c.uplift[k], c.soft[k], c.base[k] = g.z[o], g.fill[o], g.area[o], g.uplift[o], g.soft[o], g.base[o]
		c.cut[k], c.face[k], c.load[k], c.jitter[k], c.sea[k] = g.cut[o], g.face[o], g.load[o], g.jitter[o], g.sea[o]
		if c.bodies != nil do c.bodies[k] = g.bodies[o]
		c.next[k] = g.next[o] if g.next[o] < 0 else ONWARD
		if r := int(g.next[o]); r >= 0 {
			x, y := r%g.n - lo.x, r/g.n - lo.y
			if x >= 0 && y >= 0 && x < side && y < side do c.next[k] = i32(y*side + x)
		}
	}
	for ci in g.order {
		x, y := int(ci)%g.n - lo.x, int(ci)/g.n - lo.y
		if x > 0 && y > 0 && x < side - 1 && y < side - 1 do append(&c.order, i32(y*side + x))
	}
	c.left, c.lift, c.rise = g.left, g.lift, g.rise
	for x in 0..<side do for y in ([2]int{0, side - 1}) do c.sea[y*side + x], c.sea[x*side + y] = true, true   // the rim, as an island's, so what reads a neighbour stays on the grid
	h := g.holding
	if h != nil {
		delete(h.held); delete(h.index); delete(h.cells); delete(h.band); delete(h.at); delete(h.coarse); delete(h.vals); delete(h.into); delete(h.keep); delete(h.rose)
		free(h)
		g.holding = nil
	}
	grid_free(g)
	return c
}

// The land cells in an order where each comes after the cell it drains to: from every cell that drains
// out of the grid, up its streams.
order_make :: proc(g: ^Grid) {
	n := g.n
	count := make([]i32, n*n + 1, context.temp_allocator)
	for c in 0..<n*n do if !g.sea[c] && g.next[c] >= 0 do count[g.next[c] + 1] += 1
	for c in 1..=n*n do count[c] += count[c - 1]
	donors := make([]i32, n*n, context.temp_allocator)
	fill := slice.clone(count[:n*n], context.temp_allocator)
	for c in 0..<n*n do if !g.sea[c] && g.next[c] >= 0 {
		r := g.next[c]
		donors[fill[r]] = i32(c)
		fill[r] += 1
	}
	clear(&g.order)
	for c in 0..<n*n do if !g.sea[c] && g.next[c] < 0 do append(&g.order, i32(c))
	for head := 0; head < len(g.order); head += 1 {
		c := g.order[head]
		for k in count[c]..<count[c + 1] do append(&g.order, donors[k])
	}
}

// ---- the coarse stage of the landmass bound -------------------------------------------------------

// The whole lattice through the phases before `upto`: in parallel (coarse.odin); as the serial forming
// takes it (--coarse=plain); or both step by step, every stage compared (--coarse=check).
coarse_how: enum { Fast, Plain, Check }
coarse_form :: proc(n, upto: int) -> ^Grid {
	fast := coarse_how != .Plain && coarse_can(upto)
	g: ^Grid
	started := time.now()
	plain :: proc(n: int) -> ^Grid {
		p := grid_make(n)
		coarse_attach(p, true)
		for ph in region.history do p.left += ph.steps*ph.years*ph.uplift
		return p
	}
	if !fast {
		g = plain(n)
		plain_phases(g, upto)
		fmt.printfln("the coarse stage as the serial forming takes it: %d steps in %.1f s", g.coarse.steps, time.duration_seconds(time.since(started)))
		return g
	}
	g = coarse_grid(n)
	for p in region.history do g.left += p.steps*p.years*p.uplift
	if coarse_how == .Check {
		p := plain(n)
		check_phases(g, p, upto)
		differ, land_ := coarse_differ(g, p)
		fmt.printfln("the coarse stage formed both ways, in parallel and as the serial forming takes it: %d of %d land cells differ", differ, land_)
		coarse_free(p)
		grid_free(p)
	} else do mass_phases(g, upto)
	co := g.coarse
	fmt.printfln("the coarse stage in parallel: %d steps in %.1f s: routing %.1f (of it the flood through hollows %.1f in blocks, %.1f in wide blocks, %.1f over the whole lattice), cutting %.1f, creep %.1f, the coast %.1f, the rebound %.1f, starting cells %.1f; %d steps routed plainly because a cell did not check",
		co.steps, time.duration_seconds(time.since(started)), co.took[0], co.flood[0], co.flood[1], co.flood[2], co.took[1], co.took[2], co.took[3], co.took[4], co.took[5], co.failed)
	return g
}

// Metres from a point in the world to a landmass's land in the known world, to the 2 km of its samples.
mass_from :: proc(m: ^Landmass, at: [2]f64) -> f64 {
	near := f32(1e9)
	k := known_point(at.x, at.y)
	for _, i in known.samples do if known.mass[i] == m.mass {
		near = min(near, linalg.length([2]f32{f32(i%KNOWN_N) + 0.5, f32(i/KNOWN_N) + 0.5}*KNOWN_STEP - WINDOW/2 - k))
	}
	return f64(max(near - KNOWN_STEP/2, 0))*1000
}

// Where the player is, for the pieces kept formed round them: set by the frame.
mass_focus: [2]f64

KEEP_THREADS :: 3   // threads that form pieces beside play
LET_GO   :: 1.5   // a piece this many times the reach from the player is let go,
GRACE    :: 8     // and its land's memory freed this many seconds later, when nothing that was reading it still is

// Keep the landmasses' pieces within reach of the view (`mass_focus`, `mass_reach`) formed, nearest
// first, on one thread of low priority beside play or the screens before it; and let go those left
// far behind, which are read back from where they were kept when the view comes near again, so that
// what is held does not grow with how far the player has been. Asked for more than once, it is begun
// once; it ends when forming is told to stop.
masses_keep :: proc() {
	sync.guard(&forming.mutex)
	if keeper != nil || mass_reach <= 0 || !sync.atomic_load_explicit(&lands_state.regions, .Acquire) do return
	keeper = thread.create_and_start(proc() {
		alone, quiet = true, true
		Gone :: struct { f: ^Formed, at: time.Time }
		gone := make([dynamic]Gone)
		defer delete(gone)
		for !sync.atomic_load(&forming.stop) {
			at := mass_focus
			formed_one := false
			for &m in lands do if m.ready && !formed_one {
				for p in mass_order(&m, at, mass_reach, context.allocator) do if f := &formed[m.first + int(p)]; !is_formed(f) {   // its own memory: forming frees the temporary as it goes
					waiting := false
					for g in gone do waiting ||= g.f == f   // let go a moment ago, and not yet freed
					if waiting do continue
					mass_form(&m, {p}, KEEP_THREADS)
					formed_one = true
					break
				}
			}
			for &m in lands do if m.ready do for p in 0..<i32(len(m.cut.size)) {
				if f := &formed[m.first + int(p)]; is_formed(f) && mass_off(&m, p, at) > LET_GO*mass_reach {
					sync.atomic_store_explicit(&f.ready, false, .Release)
					append(&gone, Gone{f, time.now()})
				}
			}
			for i := len(gone) - 1; i >= 0; i -= 1 do if time.duration_seconds(time.since(gone[i].at)) > GRACE {
				piece_free(gone[i].f)
				unordered_remove(&gone, i)
			}
			free_all(context.temp_allocator)
			if !formed_one do time.sleep(250*time.Millisecond)
		}
	}, priority = .Low)
}
keeper: ^thread.Thread   // the thread that keeps pieces formed; made and ended under forming.mutex
mass_reach: f64          // metres round the view within which pieces are kept formed (--reach); none are kept at 0

// Wait for the keeper, which forming.stop has told to end (forming_stop, making.odin).
masses_end :: proc() {
	sync.lock(&forming.mutex)
	k := keeper
	keeper = nil
	sync.unlock(&forming.mutex)
	if k != nil {
		thread.join(k)
		thread.destroy(k)
	}
}

// Free what a piece's land holds for each of its cells, once the piece has been let go and nothing reads
// it. What it keeps on the GPU the frame lets go (islands_upload); its lists of a few hundred things
// (places, haunts) stay until it is formed again.
piece_free :: proc(f: ^Formed) {
	l := &f.land
	for a in ([?][]f32{l.slope, l.wet, l.live, l.facing, l.hump, l.inland, l.sun, l.exposed, l.above, l.table, l.soil, l.age, l.valley, l.slid, l.swell, l.surf, l.supply, l.lifted, l.rain}) do delete(a)
	for level in 1..<len(l.z) do delete(l.z[level])
	delete(l.community); delete(l.lake); delete(l.pebble); delete(l.mouth)
	if l.grid != nil do grid_free(l.grid)
	l^ = {}
	t := &f.trails
	delete(t.wade); delete(t.cost); delete(t.worn); delete(t.first); delete(t.ford); delete(t.back); delete(t.seen); delete(t.going); delete(t.segments)
	for b in t.buckets do delete(b)
	delete(t.buckets)
	t^ = {}
	delete(f.fauna.barrier); delete(f.fauna.over); delete(f.fauna.fish)
	f.fauna.barrier, f.fauna.over, f.fauna.fish = nil, nil, nil
	r := &f.rivers
	for b in r.buckets do delete(b)
	delete(r.buckets); delete(r.segments); delete(r.ribbon); delete(r.spots); delete(r.falls); delete(r.drops)
	r^ = {}
	clear(&f.hollows); clear(&f.pillars); clear(&f.candidates); clear(&f.places); clear(&f.fauna.haunts)
	f.drawn = false
}
