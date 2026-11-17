package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:math/linalg"
import "core:sync"
import "core:time"
import "core:slice"

// Land larger than a region, formed in pieces with no seam (step 21; docs/interesting-world/notes/
// continents-forming.md). The landmass is formed whole on coarse cells, then cut along its drainage
// into pieces, and the pieces take up the finer cells one after another, downstream first. Each piece
// holds, right at the cut, what the pieces formed before it left there, through every step of the
// history: a band of cells whose heights, filled surface, drainage, land drained and rock carried are
// theirs (`Holding`). Toward pieces not yet formed it forms a margin past the cut, and holds the cells
// beyond that to the coarse pass, with the water and rock the coarse pass says come in. What a piece
// leaves beside the pieces after it is kept for them (`Band`).

// The landmass of the known world nearest the start, larger than a region can hold: what the world
// knows of it before it is formed. Its ground at the start of the forming, its uplift and its sea are
// read from the plates' regional history at each place (known.odin), as an island's record is; it is
// formed on a lattice of cells laid over its whole extent, in pieces.
Landmass :: struct {
	mass:   i32,       // its land mass in the known world, from 1; 0 for none
	origin: [2]i32,    // the world point at its lattice's middle, metres
	side:   f64,       // the lattice's side, metres
	seed:   u32,       // the seed it is formed from
	area:   f32,       // km² of land, in the known world
	top:    f32,       // m, the history's highest ground on it
}
mainland: Landmass

MASS_ROUGH :: 80     // metres the starting ground wanders over a few km, so the coast does not follow the history's 2 km samples
MASS_SHELF :: -600   // the deepest the sea floor inside the lattice starts at

// A cell of a landmass's grid as the forming starts: the history's ground there, lowered by the
// uplift still to come, and roughened. Where the known world's ground is another land mass's, it is
// sea floor here: each mass is formed on its own lattice.
mass_cell :: proc(g: ^Grid, c: int, x, z: f64) {
	m := region.mass
	at := known_point(f64(region.origin.x) + x, f64(region.origin.y) + z)
	k, _ := known_at(at)
	h := k.h
	u, v := clamp(int((at.x + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1), clamp(int((at.y + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1)
	if known.mass[v*KNOWN_N + u] != m.mass && h > 0 do h = -50
	rates := past_at(at)
	mean: f32
	for r in rates do mean += r/PAST
	g.uplift[c] = max(mean, 0)/1000   // m/yr, at the shape's rate of 1
	left: f32
	for p in region.history do left += p.steps*p.years*p.uplift
	h += MASS_ROUGH*fbm(x, z, 5000, 1, 4, seed + 9) - g.uplift[c]*left
	g.sea[c] = h <= 0
	g.z[c] = max(h, MASS_SHELF) if g.sea[c] else 0.5 + max(h, 0) + 12*(1 + fbm(x, z, 900, 1, 3, seed + 9))
	u_ := rock_base(x, z, LAND_CELL)
	g.base[c] = u_.base
	if g.bodies != nil do g.bodies[c] = {u_.cover, u_.roof, u_.body}
}

ONWARD :: -3   // in `next`: the water leaves the piece of a landmass in hand into another, which carries it on

BAND :: 8   // cells a piece holds of each formed neighbour at each cell size, and keeps of its own for the pieces after it

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
}

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
	out:    ^Band,      // what is kept of them
	step:   int,        // steps taken at this cell size
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
		if v.next < 0 || g.sea[c] do continue
		if r := lattice_cell(g, v.next); r >= 0 && !h.held[r] && !g.sea[r] do g.area[r] += v.area
	}
	for in_ in h.into do if r := int(in_[0]); !g.sea[r] do g.area[r] += in_[1]
}

// The rock coming in with that water.
held_load :: proc(g: ^Grid, dt: f32) {
	h := g.holding
	for c, i in h.cells {
		v := h.vals[i]
		if v.next < 0 || g.sea[c] do continue
		if r := lattice_cell(g, v.next); r >= 0 && !h.held[r] do g.load[r] += v.load
	}
	for in_ in h.into do g.load[int(in_[0])] += in_[2]*dt
}

// The grid's cell at an index on its lattice, or -1 off the grid.
lattice_cell :: proc(g: ^Grid, k: i32) -> int {
	x, z := int(k)%g.at.n - g.at.x, int(k)/g.at.n - g.at.z
	return z*g.n + x if x >= 0 && z >= 0 && x < g.n && z < g.n else -1
}

// A cell's index on the grid's lattice.
lattice_of :: proc(g: ^Grid, c: int) -> i32 {
	return i32((c/g.n + g.at.z)*g.at.n + c%g.n + g.at.x)
}

// One step's values of the cells kept for the pieces after this one, at a stage: 0 at its start, 1
// once routed, 2 once cut, 3 after creep, 4 after the coast.
held_keep :: proc(g: ^Grid, stage: int) {
	h := g.holding
	if h.out == nil do return
	if stage == 0 do append(&h.out.vals, make([]Held, len(h.keep)))
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
		was: []f32
		if region.mass != nil && g.holding == nil do was = make([]f32, g.n*g.n)
		defer delete(was)
		for _ in 0..<int(p.steps) {
			if was != nil {   // the landmass's coarse stage: how far it has come, and whether it is to be left where it stands
				if sync.atomic_load(&mainland_state.leave) do return g
				sync.atomic_add(&mainland_state.step, 1)
				copy(was, g.z)
			}
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
				held_stage(g, 3)
				held_keep(g, 4)
				g.holding.step += 1
			}
			if was != nil do rebound(g, was, p.years*p.uplift)
			g.left -= p.years*p.uplift
		}
	}
	return g
}

// A landmass floats: as rock is worn off it, the crust under it rises by the worn rock's weight over
// the mantle's, 2,700 kg/m³ over 3,300 (Airy), spread over the flexure of the plate, here the mean over
// a square REBOUND_WIDE across. Islands are too small for it to matter; a continent that hardly rises
// is otherwise planed to the sea in the 64 m phases' 3 Myr (seed 1's, from the history's median of
// 1,156 m to 73 m). Only the coarse stage rebounds: the finer phases' 0.4 Myr wear too little.
ISOSTASY     :: 0.82
REBOUND_WIDE :: 24_000   // metres (a guess within the 50 to 200 km a continental plate's flexure spreads a load; a smaller square keeps valleys and ranges apart)
rebound :: proc(g: ^Grid, was: []f32, uplifted: f32) {
	n := g.n
	r := max(int(REBOUND_WIDE/2/g.d), 1)
	sums := make([]f64, (n + 1)*(n + 1))
	defer delete(sums)
	w := n + 1
	for y in 0..<n {
		row: f64
		for x in 0..<n {
			c := y*n + x
			worn := f64(was[c] + g.uplift[c]*uplifted - g.z[c]) if !g.sea[c] else 0   // the rock worn off a land cell this step
			row += worn
			sums[(y + 1)*w + x + 1] = sums[y*w + x + 1] + row
		}
	}
	Up :: struct { g: ^Grid, sums: []f64, r: int }
	up := Up{g, sums, r}
	shared(n, rows(n), &up, proc(u: ^Up, lo, hi: int) {
		g, n, w, r := u.g, u.g.n, u.g.n + 1, u.r
		for y in lo..<hi do for x in 0..<n {
			c := y*n + x
			if g.sea[c] do continue
			x0, y0, x1, y1 := max(x - r, 0), max(y - r, 0), min(x + r + 1, n), min(y + r + 1, n)
			mean := (u.sums[y1*w + x1] - u.sums[y0*w + x1] - u.sums[y1*w + x0] + u.sums[y0*w + x0])/f64((x1 - x0)*(y1 - y0))
			g.z[c] += ISOSTASY*f32(mean)
		}
	})
}

// ---- cutting a landmass into pieces ------------------------------------------------------------

// A landmass cut into pieces on one grid's cells (the coarse pass's): each cell's piece, and for each
// piece, the piece its water leaves through, its order, its neighbours and the box round its cells.
Cut :: struct {
	n:      int,
	owner:  []i32,          // each cell's piece; the sea within SEA_REACH of land the nearest land's; -1 beyond
	down:   []i32,          // each piece's: the piece its outlet drains into, or -1 at the sea
	depth:  []i32,          // pieces between it and the sea
	rank:   []i32,          // its place in the order pieces are formed in
	size:   []i32,          // land cells
	near:   [][dynamic]i32, // the pieces beside it
	box:    [][4]i32,       // its cells' least and greatest column and row
}

SEA_REACH :: 32   // cells of the coarse pass the sea belongs to the nearest land's piece for; beyond, it is the open sea

// Cut the land of a coarse grid along its drainage into pieces of about `most` cells: each a part of a
// drainage tree, cut across a trunk where a basin is larger, and the small basins along a coast
// joined. Then order them: a piece through which another's water leaves comes first; among pieces
// as far from the sea, by a colouring of their borders, so that no long chain of neighbours waits on
// each other.
cut_make :: proc(g: ^Grid, most: int) -> (cut: Cut) {
	n := g.n
	cut.n = n
	cut.owner = make([]i32, n*n)
	slice.fill(cut.owner, -1)
	rem := make([]i32, n*n)
	defer delete(rem)
	root := make([]bool, n*n)
	defer delete(root)
	#reverse for ci in g.order {
		c := int(ci)
		rem[c] += 1
		r := g.next[c]
		if r < 0 {
			root[c] = true
			continue
		}
		if rem[r] + rem[c] > i32(most) && rem[c] >= i32(most/4) do root[c] = true
		else do rem[r] += rem[c]
	}
	// Each cell's piece: that of the first root on its way down.
	pieces := i32(0)
	roots := make([dynamic]int, context.temp_allocator)
	for ci in g.order {
		c := int(ci)
		if root[c] {
			cut.owner[c] = pieces
			append(&roots, c)
			pieces += 1
		} else do cut.owner[c] = cut.owner[g.next[c]]
	}
	// Pieces too small to stand alone, small basins along a coast, joined to the smallest neighbour,
	// until none is left under a quarter of `most` that has one no larger than `most`.
	size := make([]i32, pieces, context.temp_allocator)
	for ci in g.order do size[cut.owner[ci]] += 1
	beside := make([]map[i32]bool, pieces, context.temp_allocator)
	for &m in beside do m = make(map[i32]bool, 8, context.temp_allocator)
	for c in 0..<n*n do if a := cut.owner[c]; a >= 0 {
		x, y := c%n, c/n
		if x + 1 < n do if b := cut.owner[c + 1]; b >= 0 && b != a { beside[a][b] = true; beside[b][a] = true }
		if y + 1 < n do if b := cut.owner[c + n]; b >= 0 && b != a { beside[a][b] = true; beside[b][a] = true }
	}
	into := make([]i32, pieces, context.temp_allocator)
	for &v, i in into do v = i32(i)
	find :: proc(into: []i32, p: i32) -> i32 { p := p; for into[p] != p do p = into[p]; return p }
	// Each piece's box, which a join keeps as near square as it can: a piece's grid is a square round it.
	boxes := make([][4]i32, pieces, context.temp_allocator)
	for &b in boxes do b = {i32(n), i32(n), -1, -1}
	for ci in g.order {
		b := &boxes[cut.owner[ci]]
		x, y := i32(ci)%i32(n), i32(ci)/i32(n)
		b^ = {min(b.x, x), min(b.y, y), max(b.z, x), max(b.w, y)}
	}
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
			for q0 in beside[p] {
				q := find(into, q0)
				if q == p || size[q] + size[p] > i32(most*3/2) || span(boxes[p], boxes[q]) > widest do continue
				if best < 0 || span(boxes[p], boxes[q]) < span(boxes[p], boxes[best]) || span(boxes[p], boxes[q]) == span(boxes[p], boxes[best]) && q < best do best = q
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
	number := make([]i32, pieces, context.temp_allocator)
	slice.fill(number, -1)
	count := i32(0)
	for ci in g.order {
		p := find(into, cut.owner[ci])
		if number[p] < 0 {
			number[p] = count
			count += 1
		}
		cut.owner[ci] = number[p]
	}
	cut.down, cut.depth, cut.rank, cut.size = make([]i32, count), make([]i32, count), make([]i32, count), make([]i32, count)
	cut.near, cut.box = make([][dynamic]i32, count), make([][4]i32, count)
	slice.fill(cut.down, -1)
	for ci in g.order {
		c := int(ci)
		cut.size[cut.owner[c]] += 1
		if r := g.next[c]; r >= 0 && cut.owner[r] != cut.owner[c] do cut.down[cut.owner[c]] = cut.owner[r]
	}
	// The sea within SEA_REACH goes with the nearest land, nearest first.
	reach := make([]i32, n*n)
	defer delete(reach)
	queue := make([dynamic]int)
	defer delete(queue)
	for ci in g.order do append(&queue, int(ci))
	for head := 0; head < len(queue); head += 1 {
		c := queue[head]
		if reach[c] >= SEA_REACH do continue
		for o in FOUR {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n do continue
			if k := y*n + x; cut.owner[k] < 0 {
				cut.owner[k], reach[k] = cut.owner[c], reach[c] + 1
				append(&queue, k)
			}
		}
	}
	for &b in cut.box do b = {i32(n), i32(n), -1, -1}
	pairs := make(map[[2]i32]bool, 64, context.temp_allocator)
	for c in 0..<n*n do if a := cut.owner[c]; a >= 0 {
		x, y := i32(c%n), i32(c/n)
		b := &cut.box[a]
		b^ = {min(b.x, x), min(b.y, y), max(b.z, x), max(b.w, y)}
		// Neighbours are pieces whose cells come within two of each other's, 128 m at 64 m, the BAND
		// a piece holds of a neighbour at the finest cells.
		for dy in -2..=2 do for dx in 0..=2 do if dx > 0 || dy > 0 {
			if xx, yy := int(x) + dx, int(y) + dy; xx < n && yy >= 0 && yy < n {
				if q := cut.owner[yy*n + xx]; q >= 0 && q != a do pairs[{min(a, q), max(a, q)}] = true
			}
		}
	}
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
	colour := make([]i32, count, context.temp_allocator)
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
	keys := make([]Key, count, context.temp_allocator)
	for p in 0..<count do keys[p] = {cut.depth[p], colour[p], i32(p)}
	slice.sort_by(keys, proc(x, y: Key) -> bool { return x.depth < y.depth || x.depth == y.depth && (x.colour < y.colour || x.colour == y.colour && x.p < y.p) })
	for k, r in keys do cut.rank[k.p] = i32(r)
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

// ---- forming a piece ----------------------------------------------------------------------------

// What forming the pieces of one landmass shares: the coarse pass (its grid at the cell size the
// pieces take up from), the cut on that grid's cells, the phase they take up from, how far they
// form past the cut toward pieces not yet formed, and the bands each formed piece keeps, by piece.
Pieces :: struct {
	pass:   ^Grid,
	cut:    ^Cut,
	from:   int,
	margin: f32,          // metres
	bands:  [][dynamic]^Band,
	formed: []bool,
}

// What a piece's grid is while it forms, for making its hold at each cell size.
Piece_Form :: struct { all: ^Pieces, p: i32 }

RING :: 8   // coarse cells held round a piece's own cells and margin: the coast's exposure reads 500 m

// The grid a piece forms on at the coarse pass's cells: a window round its own cells, its margin and
// a ring beyond, taken from the coarse pass as it stood.
piece_grid :: proc(all: ^Pieces, p: i32) -> ^Grid {
	pass := all.pass
	n := pass.n
	lo, side := piece_window(all, p)
	g := grid_make(side, {lo.x + pass.at.x, lo.y + pass.at.z, pass.at.n})
	for j in 0..<side do for i in 0..<side {
		c, k := j*side + i, (j + lo.y)*n + i + lo.x
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
	pass, cut := all.pass, all.cut
	if g.holding != nil {   // the coarser grid's hold, gone with it
		h := g.holding
		delete(h.held); delete(h.index); delete(h.cells); delete(h.band); delete(h.at); delete(h.coarse); delete(h.vals); delete(h.into); delete(h.keep)
		free(h)
		g.holding = nil
	}
	n := g.n
	scale := int(math.round(pass.d/g.d))   // this grid's cells to a coarse cell
	owner := make([]i32, n*n, context.temp_allocator)
	for c in 0..<n*n {
		x, z := (c%n + g.at.x)/scale - pass.at.x, (c/n + g.at.z)/scale - pass.at.z
		owner[c] = cut.owner[clamp(z, 0, pass.n - 1)*pass.n + clamp(x, 0, pass.n - 1)]
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
	h.held, h.index = make([]bool, n*n), make([]i32, n*n)
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
		if earlier(all, q, p) {
			k := lattice_of(g, c)
			found := false
			for b in all.bands[q] do if int(math.round(f32(b.cell))) == int(math.round(g.d)) {
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
			near ||= q >= 0 && earlier(all, p, q)
		}
		if near do append(&keep, i32(c))
	}
	h.keep = keep[:]
	b := new(Band)
	b.cell = int(math.round(g.d))
	b.cells = make([]i32, len(h.keep))
	b.place = make(map[i32]i32, len(h.keep))
	for c, i in h.keep {
		b.cells[i] = lattice_of(g, int(c))
		b.place[b.cells[i]] = i32(i)
	}
	h.out = b
	append(&all.bands[p], b)
	g.holding = h
}

// Whether piece `q` comes before its neighbour `p` in the order, so that `p` holds its land at their cut.
// It depends on the order alone, never on what happens to be formed: a piece comes out the same
// however it was reached. A piece that is not a neighbour is never held, formed or not.
earlier :: proc(all: ^Pieces, q, p: i32) -> bool {
	if q < 0 || q == p || all.cut.rank[q] >= all.cut.rank[p] do return false
	_, found := slice.binary_search(all.cut.near[p][:], q)
	return found
}

// Years in a step of the coarse pass's last phase, which its rock carried down is counted over.
pass_years :: proc() -> f32 {
	last: f32
	for p in region.history do if p.cell >= 64 do last = p.years
	return last
}

// The window of the coarse pass's cells a piece forms on: its corner and side. It holds the piece's own
// cells, its margin toward pieces not yet formed, and a ring of RING coarse cells round both, which is
// held: the bands of the pieces formed before it, and the coarse pass beyond its margin.
piece_window :: proc(all: ^Pieces, p: i32) -> (lo: [2]int, side: int) {
	pass, cut, b := all.pass, all.cut, all.cut.box[p]
	n := pass.n
	margin, ring := int(math.ceil(all.margin/pass.d)), RING
	lo = {max(int(b.x) - margin - ring, 0), max(int(b.y) - margin - ring, 0)}
	hi := [2]int{min(int(b.z) + margin + ring, n - 1), min(int(b.w) + margin + ring, n - 1)}
	w, h := hi.x - lo.x + 1, hi.y - lo.y + 1
	far := make([]f32, w*h, context.temp_allocator)
	for j in 0..<h do for i in 0..<w do far[j*w + i] = 0 if cut.owner[(lo.y + j)*n + lo.x + i] == p else 1e9
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
		q := cut.owner[(lo.y + j)*n + lo.x + i]
		d := far[j*w + i]
		if d <= f32(ring) || d <= f32(margin) && !earlier(all, q, p) {
			in_lo, in_hi = {min(in_lo.x, lo.x + i), min(in_lo.y, lo.y + j)}, {max(in_hi.x, lo.x + i), max(in_hi.y, lo.y + j)}
		}
	}
	lo = {max(in_lo.x - ring, 0), max(in_lo.y - ring, 0)}
	hi = {min(in_hi.x + ring, n - 1), min(in_hi.y + ring, n - 1)}
	side = max(hi.x - lo.x, hi.y - lo.y) + 1
	side = (side + 3)/4*4   // a whole number of 256 m, which the finer grids halve into
	lo = {clamp(lo.x, 0, max(n - side, 0)), clamp(lo.y, 0, max(n - side, 0))}
	return
}

// Form piece `p` from the coarse pass, holding what the pieces formed before it left: its finished grid.
piece_form :: proc(all: ^Pieces, p: i32) -> ^Grid {
	g := piece_grid(all, p)
	f := Piece_Form{all, p}
	g = form_phases(g, all.from, len(region.history), piece_level, &f)
	all.formed[p] = true
	return g
}

FOUR :: [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}


// ---- the landmass in the game -------------------------------------------------------------------

PIECE_KM2 :: 300        // km² of land in a piece, about; a basin larger is cut across its trunk
MARGIN    :: 6000       // metres a piece forms past the cut toward pieces not yet formed
MASS_PAD  :: 8192       // metres of sea round the landmass's land on its lattice
// How near the start (or a site) a landmass's pieces are formed: before entering, and beside play. A
// piece kept whole at 16 m holds about 590 MB for each 1,000 km² of the square its land is kept on (3 to
// 12 times its own land on seed 1's coast, whose basins are long and narrow), so not the 64 km the islands
// are formed to (a weak point: pieces are not yet kept on disk and formed again on approach). A chunk over
// a piece not formed waits, as over an island formed in the background.
NEAR_REACH       :: 16_000
BACKGROUND_REACH :: 40_000

// What the coarse stage may cost before it is run in the game, on one thread at today's rate of the
// 64 m phases (171 ns a land cell a step, measured on a 131 km region), and in memory for its grid
// (63 bytes a cell). Beyond either, the landmass stays a record (`Mainland_State.why`).
PASS_SECONDS :: 480
PASS_BYTES   :: 2.5e9

Mainland_State :: struct {
	frame:  Formed,       // the landmass's own region, which its coarse stage is formed on and every piece reads
	pass:   ^Grid,        // the coarse stage: the whole landmass through the 64 m phases
	cut:    Cut,
	all:    Pieces,
	first:  int,          // the first piece's place in `formed`
	mutex:  sync.Mutex,   // pieces are formed one at a time, each after those it waits on
	why:    string,       // why the landmass is not formed, where it is not
	seconds, pass_seconds: f64,
	formable: bool,
	ready:    bool,       // its pieces are regions in `formed`: set once they are, and read by every thread that asks whose ground a point is
	step, steps: i32,     // how far the coarse stage has come, of how many steps of the history: for the eye (making.odin)
	leave:    bool,       // the coarse stage is to be left where it stands, and the landmass a record
	kept:     bool,       // the coarse stage was read back from where an earlier run kept it
}
mainland_state: Mainland_State

// The landmass nearest the start among those larger than a region: its record, and whether its coarse
// stage can be run here, by its size.
mainland_make :: proc() {
	ms := &mainland_state
	mainland = {}
	ms.why, ms.formable = "", false
	start, by := -1, f32(1e9)
	for _, i in known.samples do if m := known.mass[i]; m > 0 && known.masses[m - 1].large {
		at := [2]f32{f32(i%KNOWN_N) + 0.5, f32(i/KNOWN_N) + 0.5}*KNOWN_STEP - WINDOW/2
		if d := linalg.length(at - world_frame.start); d < by do start, by = i, d
	}
	if start < 0 {
		ms.why = "no land larger than a region in the known world"
		return
	}
	id := known.mass[start]
	lo, hi := [2]f64{1e12, 1e12}, [2]f64{-1e12, -1e12}
	top := f32(0)
	for _, i in known.samples do if known.mass[i] == id {
		at := world_of([2]f32{f32(i%KNOWN_N) + 0.5, f32(i/KNOWN_N) + 0.5}*KNOWN_STEP - WINDOW/2)
		lo, hi = {min(lo.x, at.x), min(lo.y, at.y)}, {max(hi.x, at.x), max(hi.y, at.y)}
		top = max(top, known.samples[i].h)
	}
	lo, hi = lo - MASS_PAD - f64(KNOWN_STEP)*500, hi + MASS_PAD + f64(KNOWN_STEP)*500
	side := math.ceil(max(hi.x - lo.x, hi.y - lo.y)/4096)*4096
	middle := (lo + hi)/2
	mainland = {mass = id, origin = {i32(math.round(middle.x/1024))*1024, i32(math.round(middle.y/1024))*1024}, side = side, area = known.masses[id - 1].area, top = top,
		seed = hash(i32(start), 21, world_seed + 2100)}
	cells := f64(mainland.area)*1e6/4096
	ms.pass_seconds = cells*159*171e-9
	bytes := (side/64)*(side/64)*63
	ms.formable = ms.pass_seconds <= PASS_SECONDS && bytes <= PASS_BYTES
	if !ms.formable do ms.why = fmt.tprintf("its coarse stage, the whole of its %.0f km² through the 64 m phases on a lattice %.0f km across, would take about %.0f min on one thread and %.1f GB, more than the %.0f min and %.1f GB allowed before it runs in parallel",
		mainland.area, side/1000, ms.pass_seconds/60, bytes/1e9, f64(PASS_SECONDS)/60, PASS_BYTES/1e9)
	fmt.printfln("the land larger than a region nearest the start: %.0f km² of land in the known world, its coast %.0f km off, the history's ground up to %.0f m; %s",
		mainland.area, by - KNOWN_STEP/2, top, "formed as land: its coarse stage before entering, its pieces within reach of the start before entering and the rest in the background" if ms.formable else fmt.tprintf("not formed: %s", ms.why))
}

// Bind the landmass's own region, its record drawn from its seed as an island's is.
mainland_bind :: proc(f: ^Formed, id: int, origin: [2]i32, size: f64) {
	f.island = {id = id, origin = origin, size = size, kind = mainland_kind(), seed = mainland.seed, setting = .Continent}
	bind(f)   // after its seed is set: binding reads the seed, and helper threads bind the same record
	f.region.origin, f.region.size, f.region.mass, f.landslide = mainland.origin, mainland.side, &mainland, {box = {1e9, 1e9, -1e9, -1e9}}
	q := quiet
	quiet = true
	region_init("mainland", mainland.side)
	quiet = q
	region.origin, region.mass = mainland.origin, &mainland   // region_init keeps them; set again in case
	region.shape.swell = world_frame.wind
	climate_init(Island{origin = mainland.origin})   // one climate for the whole landmass, read at its middle (a weak point: it spans many degrees)
	quiet = true
	rock_init(false)
	quiet = q
}

mainland_kind :: proc() -> int {
	for k, i in KINDS do if k.name == "mainland" do return i
	return -1
}

// The coarse stage: the whole landmass formed through its 64 m phases, then cut along its drainage.
mainland_pass :: proc() {
	ms := &mainland_state
	started := time.now()
	mainland_bind(&ms.frame, -1, mainland.origin, mainland.side)
	from := 0
	for p, i in region.history do if p.cell >= 64 do from = i + 1
	g := grid_make(int(mainland.side)/64)
	for p in region.history do g.left += p.steps*p.years*p.uplift
	steps := f32(0)
	for p in region.history[:from] do steps += p.steps
	sync.atomic_store(&ms.step, 0)
	sync.atomic_store(&ms.steps, i32(steps))
	kept := pass_load(g)
	if !kept {
		g = form_phases(g, 0, from)
		if sync.atomic_load(&ms.leave) {   // left where it stood: nothing of it is kept, and the landmass stays a record
			grid_free(g)
			ms.why = "its coarse stage was stopped before it had run, so it is left as the plates' history has it until this world is opened again"
			fmt.println("the landmass's coarse stage: left before it had run; the landmass stays a record")
			return
		}
		pass_save(g)
	}
	ms.kept = kept
	sync.atomic_store(&ms.step, i32(steps))
	ms.pass = g
	ms.cut = cut_make(g, PIECE_KM2*1e6/4096)
	count := len(ms.cut.size)
	ms.all = Pieces{pass = g, cut = &ms.cut, from = from, margin = MARGIN, bands = make([][dynamic]^Band, count), formed = make([]bool, count)}
	ms.pass_seconds = time.duration_seconds(time.since(started))
	land_cells := 0
	nearest, by := [2]f64{}, f64(1e18)
	for c in 0..<g.n*g.n do if !g.sea[c] {
		land_cells += 1
		at := [2]f64{f64(mainland.origin.x) + (f64(c%g.n) + 0.5 - f64(g.n)/2)*64, f64(mainland.origin.y) + (f64(c/g.n) + 0.5 - f64(g.n)/2)*64}
		if d := math.hypot(at.x - world_frame.origin.x, at.y - world_frame.origin.y); d < by do nearest, by = at, d
	}
	fmt.printfln("the landmass's lattice: %.0f km across, its middle at %d, %d; its land nearest the start, as its coarse stage leaves it before the sea's last rise: %.0f, %.0f, %.1f km off", mainland.side/1000, mainland.origin.x, mainland.origin.y, nearest.x, nearest.y, by/1000)
	// How many pieces each waits on: the cost of forming one alone, anywhere.
	waits := make([]int, count, context.temp_allocator)
	deepest := i32(0)
	for p in 0..<count {
		waits[p] = len(cut_waits(&ms.cut, i32(p)))
		deepest = max(deepest, ms.cut.depth[p])
	}
	slice.sort(waits)
	if count > 0 do fmt.printfln("the landmass's pieces: up to %d from the sea along their drainage; each waits on a median %d pieces before it, 90%% on %d or fewer, at most %d", deepest, waits[count/2], waits[count*9/10], waits[count - 1])
	fmt.printfln("the landmass's coarse stage: %.0f km² of land through its 64 m phases, %s in %.1f s, cut along its drainage into %d pieces", f64(land_cells)*4096/1e6, "read back from where it was kept" if kept else "formed", ms.pass_seconds, count)
}

// The piece a point in the world lies in, or -1: off the landmass's lattice or out on the open sea.
mainland_piece :: proc(x, z: f64) -> int {
	ms := &mainland_state
	if !sync.atomic_load_explicit(&ms.ready, .Acquire) do return -1
	g := ms.pass
	u, v := int(math.floor((x - f64(mainland.origin.x))/64 + f64(g.n)/2)), int(math.floor((z - f64(mainland.origin.y))/64 + f64(g.n)/2))
	if u < 0 || v < 0 || u >= g.n || v >= g.n do return -1
	return int(ms.cut.owner[v*g.n + u])
}

// The world square a piece's land covers: its middle and side.
piece_square :: proc(p: i32) -> (origin: [2]i32, size: f64) {
	ms := &mainland_state
	lo, side := piece_window(&ms.all, p)
	n := ms.pass.n
	return {mainland.origin.x + i32((f64(lo.x) + f64(side)/2 - f64(n)/2)*64), mainland.origin.y + i32((f64(lo.y) + f64(side)/2 - f64(n)/2)*64)}, f64(side)*64
}

// Form a piece and everything that lives on it, after the pieces it waits on, on this thread.
mainland_form :: proc(p: i32) {
	ms := &mainland_state
	sync.lock(&ms.mutex)
	defer sync.unlock(&ms.mutex)
	if ms.all.formed[p] do return
	was := here
	defer bind(was)
	waits := cut_waits(&ms.cut, p, context.allocator)   // forming frees the temporary memory as it goes
	defer delete(waits)
	for q in waits do if !ms.all.formed[q] do piece_finish(q)
	piece_finish(p)
}

// Form one piece whose earlier neighbours are formed, and make it a region like an island's.
piece_finish :: proc(p: i32) {
	ms := &mainland_state
	f := &formed[ms.first + int(p)]
	started := time.now()
	origin, size := piece_square(p)
	mainland_bind(f, ms.first + int(p), origin, size)
	_, window := piece_window(&ms.all, p)
	g := piece_form(&ms.all, p)
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
		r := lattice_cell(g, v.next) if v.next >= 0 else -1
		g.next[c] = i32(r) if r >= 0 && !g.sea[r] || r >= 0 && v.next >= 0 && g.sea[r] else ONWARD if v.next >= 0 else -1
	}
	order_make(g)
	g = piece_crop(g, p)
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
	ms.seconds += f.seconds
	sync.atomic_store_explicit(&f.ready, true, .Release)
	// The bands of the pieces before it that no piece still to form reads, let go.
	kept := 0
	for q in ms.cut.near[p] do if ms.all.formed[q] && len(ms.all.bands[q]) > 0 {
		needed := false
		for r in ms.cut.near[q] do needed ||= !ms.all.formed[r] && ms.cut.rank[r] > ms.cut.rank[q]
		if needed do continue
		for b in ms.all.bands[q] {
			for v in b.vals do delete(v)
			delete(b.vals); delete(b.cells); delete(b.place)
			free(b)
		}
		clear(&ms.all.bands[q])
	}
	for l in ms.all.bands do for b in l do kept += len(b.cells)*len(b.vals)*size_of(Held)
	b := ms.cut.box[p]
	if !quiet do fmt.printfln("the landmass's piece %d: %.0f km² of land, its own box %.1f by %.1f km, formed on a window %.1f km across and kept on one %.1f km across, in %.1f s; the bands kept between pieces %.0f MB",
		p, f64(ms.cut.size[p])*4096/1e6, f64(b.z - b.x + 1)*0.064, f64(b.w - b.y + 1)*0.064, f64(window)*64/1000, f64(n)*LAND_CELL/1000, f.seconds, f64(kept)/1e6)
}

// The landmass's pieces' bands that no piece still to form will read, let go.
_ :: linalg

// The coarse stage's ground at a cell of its 64 m lattice; the open sea off it.
mass_z64 :: proc(i, j: int) -> f32 {
	g := mainland_state.pass
	if g == nil || i < 0 || j < 0 || i >= g.n || j >= g.n do return SEA_BED
	return g.z[j*g.n + i]
}

// Metres from a point in the world to the land of piece `p`.
mainland_off :: proc(p: i32, at: [2]f64) -> f64 {
	ms := &mainland_state
	b, n := ms.cut.box[p], ms.pass.n
	lo := [2]f64{f64(mainland.origin.x) + (f64(b.x) - f64(n)/2)*64, f64(mainland.origin.y) + (f64(b.y) - f64(n)/2)*64}
	hi := [2]f64{f64(mainland.origin.x) + (f64(b.z) + 1 - f64(n)/2)*64, f64(mainland.origin.y) + (f64(b.w) + 1 - f64(n)/2)*64}
	return math.hypot(max(lo.x - at.x, at.x - hi.x, 0), max(lo.y - at.y, at.y - hi.y, 0))
}

// The landmass's pieces, nearest a point first.
mainland_order :: proc(at: [2]f64) -> []i32 {
	count := len(mainland_state.cut.size)
	order := make([]i32, count, context.temp_allocator)
	far := make([]f64, count, context.temp_allocator)
	for &v, i in order {
		v = i32(i)
		far[i] = mainland_off(i32(i), at)
	}
	context.user_ptr = raw_data(far)
	slice.sort_by(order, proc(a, b: i32) -> bool { f := ([^]f64)(context.user_ptr); return f[a] < f[b] || f[a] == f[b] && a < b })
	return order
}

// Put the landmass down with its world: its coarse stage, its cut and the bands between its pieces.
// The pieces formed stay where they lie, as formed islands do (making.odin). No thread is forming.
mainland_drop :: proc() {
	ms := &mainland_state
	sync.atomic_store_explicit(&ms.ready, false, .Release)
	if ms.pass != nil do grid_free(ms.pass)
	c := &ms.cut
	delete(c.owner); delete(c.down); delete(c.depth); delete(c.rank); delete(c.size); delete(c.box)
	for l in c.near do delete(l)
	delete(c.near)
	for l in ms.all.bands {
		for b in l {
			for v in b.vals do delete(v)
			delete(b.vals); delete(b.cells); delete(b.place)
			free(b)
		}
		delete(l)
	}
	delete(ms.all.bands); delete(ms.all.formed)
	ms^ = {}
	mainland = {}
}

PASS_VERSION :: 3   // raised whenever what this file does to form the coarse stage (mass_cell, form_phases) changes

// Where the coarse stage of the landmass is kept: beside the known world, named by the seed and by what
// forms it, so a change to the forming forms it again.
pass_path :: proc() -> string {
	SOURCES :: #load_hash("land.odin", "fnv32a") ~ #load_hash("erosion.odin", "fnv32a") ~ #load_hash("rock.odin", "fnv32a") ~ #load_hash("gen.odin", "fnv32a") ~ #load_hash("known.odin", "fnv32a") ~ #load_hash("plates.odin", "fnv32a")
	return fmt.tprintf("%s/worlds/landmass-%d-%d-%d-%08x.bin", os.dir(os.args[0]), world_seed, mainland.mass, PASS_VERSION, u32(SOURCES))
}

// The coarse stage's grid as the pieces read it: its ground, sea, cut shore, faces, rock carried,
// drainage and land drained, and its cells in drainage order.
pass_save :: proc(g: ^Grid) {
	out := make([dynamic]u8)
	defer delete(out)
	head := [2]i32{i32(g.n), i32(len(g.order))}
	append(&out, ..slice.to_bytes(head[:]))
	for a in ([?][]f32{g.z, g.cut, g.face, g.load, g.area}) do append(&out, ..slice.to_bytes(a))
	append(&out, ..slice.to_bytes(g.next))
	append(&out, ..slice.to_bytes(g.order[:]))
	append(&out, ..slice.to_bytes(g.sea))
	path := pass_path()
	_ = os.make_directory(os.dir(path))
	temp := fmt.tprintf("%s.%d", path, os.get_pid())
	if err := os.write_entire_file(temp, out[:]); err == nil { _ = os.rename(temp, path) }
}

pass_load :: proc(g: ^Grid) -> bool {
	data, err := os.read_entire_file(pass_path(), context.allocator)
	if err != nil do return false
	defer delete(data)
	if len(data) < 8 do return false
	head := (^[2]i32)(raw_data(data))^
	n, k := int(head[0]), int(head[1])
	if n != g.n || len(data) != 8 + n*n*(6*4 + 1) + k*4 do return false
	at := 8
	take :: proc(dst: []$T, data: []u8, at: ^int) { copy(slice.to_bytes(dst), data[at^:][:len(dst)*size_of(T)]); at^ += len(dst)*size_of(T) }
	for a in ([?][]f32{g.z, g.cut, g.face, g.load, g.area}) do take(a, data, &at)
	take(g.next, data, &at)
	resize_dynamic_array(&g.order, k)
	take(g.order[:], data, &at)
	take(g.sea, data, &at)
	return true
}

CROP :: 64   // fine cells kept round a finished piece's own land, for what reads the land round a cell

// A finished piece's grid cut down to its own cells and CROP round them: a new grid, the old let go.
// Where a cell's water leaves the crop it leaves the piece; the cells keep the order they were in.
piece_crop :: proc(g: ^Grid, p: i32) -> ^Grid {
	ms := &mainland_state
	scale := int(math.round(ms.pass.d/g.d))
	b := ms.cut.box[p]
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
		delete(h.held); delete(h.index); delete(h.cells); delete(h.band); delete(h.at); delete(h.coarse); delete(h.vals); delete(h.into); delete(h.keep)
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
