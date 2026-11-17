package main

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:sync"
import "core:time"

// A landmass's coarse stage, formed fast enough and small enough for the largest (step 21, second
// part; docs/interesting-world/notes/continents-forming.md). It is the forming of erosion.odin, rule
// for rule, on a lattice of 64 m cells a thousand kilometres across, where that forming's one flood
// through one heap, its one pass up the land's cells and its tables over the whole lattice would take
// half an hour and sixteen gigabytes:
//
// - The flood that routes the water puts through a heap only the cells that lie in a hollow or on a
//   flat, half a cell in a hundred of an eroded land. Every other cell's filled level is its own
//   height, and the cell the flood would have reached it from is its lowest neighbour, which each cell
//   finds for itself (`route_mass`).
// - What is worked from the shore upward (the cutting, the land drained, the rock carried) is worked
//   over the drainage's own trees: the trunks of the large rivers first, then every tributary and
//   hillside at once, each on its own thread (`trees`).
// - The sea cuts its shore in the order of the flood only where a cell is cut through, which few are
//   in a step; the rest each on their own (`coast_mass`).
// - Only the squares of the lattice with land or shallow sea in them, and a ring round those, are ever
//   written, so the open sea round a landmass takes no memory (`Coarse.ready`).
//
// The land is the land the serial forming makes when two cells of exactly the same filled level are
// taken lowest index first (`route_plain`, `plain_phases`): `--coarse=check` forms a landmass both
// ways and compares every cell. So nothing here decides anything about the land; it is engineering.

SQUARE       :: 64      // cells along a side of a square of the lattice: 4,096 m
RING_SQUARES :: 3       // squares kept started round any with land or shallow sea: 12 km, past half the rebound's width and the coast's reach
BIG_CELLS  :: 16384   // a cell that drained this many cells at the last step is a trunk's, worked before the trees that hang on it
MID_CELLS  :: 2048    // a tree that drained this many is a part of the work of its own
LEAF_BATCH :: 48      // smaller trees to a part of the work

Coarse :: struct {
	m:        int,                  // squares along a side
	all:      bool,                 // every square started, as the serial forming has them
	core:     []bool,               // each square: land in it, or sea shallow enough for the waves to wear
	ready:    []bool,               // each square: its cells started (cell_start): the core and RING_SQUARES round it
	grew:     bool,                 // a square became core in this step
	runs:     [][dynamic][2]i32,    // by row of squares: the runs of ready squares along it, as cells from and to
	flags:    []u8,                 // `seen`, as bytes: the flood's and the shore's marks
	donors:   []u8,                 // each land cell: which of its eight neighbours drain into it, a bit each in the order of OFFSETS
	bits:     []u64,                // the sea, a bit a cell, a word to a square's row
	was:      []f32,                // the ground at the step's start, for the rebound
	rose:     []f32,                // at every ROSE_STEP cells: m/yr the rebound raised the ground over the last ROSE_STEPS steps, which the pieces go on rising at
	keeping:  f32,                  // while those steps are taken: one over their years
	pits:     [][dynamic]i32,       // by row of squares and block along it: cells the flood has to reach through the heap,
	blocks:   [2][]Flood_Block,     // the flood's blocks, and those four times as wide
	wide:     int,                  // blocks along a side
	late:     Flood_Block,          // the flood over the whole lattice, of what no block could settle alone
	roots:    [][dynamic]i32,       // by row of squares: cells that drain into the sea,
	cuts:     [][dynamic]i32,       // and shore cells the sea may cut through this step
	heap:     [dynamic]u64,
	stack:    [dynamic]i32,
	trunk:    [dynamic]i32,         // the trunks' cells, each after the cell it drains to,
	units:    [dynamic][2]i32,      // by river: from and to in `trunk`
	leaves:   [dynamic]i32,         // the cells the trees hang by: each drains into a trunk or the sea
	parts:    [dynamic]i32,         // where each part of the work begins in them
	batches:  [dynamic]Batch,
	mouths:   [dynamic]u64,
	sea_new:  [dynamic]i32,         // cells the sea cut through in the last step, whose drainage is forgotten at the next
	epoch:    int,
	drained:  bool,                 // the trees are being listed to add up the land each cell drains
	flood:    [3]f64,               // seconds flooding hollows in blocks, in wide blocks and over the whole lattice
	land:     int,                  // land cells, as the last routing counted them
	steps, failed: int,             // steps taken, and of them those routed plainly because a cell did not check
	took:     [6]f64,               // seconds routing, cutting, creeping, on the coast, rebounding and starting cells
}

// The cells of some trees in the order they were reached, in the memory of the thread that reached them.
Batch :: struct { buf: ^[dynamic]i32, lo, hi: int }

@(thread_local) tree_order: [dynamic]i32
@(thread_local) tree_stack: [dynamic]i32
@(thread_local) tree_epoch: int
@(thread_local) row_sums:   [dynamic]f64
coarse_epochs: int
BLOCK :: 512   // cells along a side of a block of the lattice whose hollows are flooded apart from its neighbours

// A block's flood: the cells handed to it (its pits, or what the floods below left undecided), its
// heap, and the cells it left undecided in its turn.
Flood_Block :: struct {
	pits, undecided, later: [dynamic]i32,
	heap: [dynamic]u64,
}

// Flood marks, in the low bits of a cell's flag.
OUT     :: 0   // not in the heap: its filled level is its height
SOURCE  :: 1   // in the heap at its height: checked when it comes out
PENDING :: 2   // waiting for the flood to reach it
CLAIMED :: 3   // reached, and in the heap at its filled level
DONE    :: 4   // out of the heap: its level stands
REPLAY  :: 5   // settled by a flood below, and in the heap again to reach a waiting cell in its turn
STATE   :: 7
SEED    :: 8   // land beside the sea, where the flood starts
BIG     :: 16  // a trunk's cell, by the land it drained at the last step
MID     :: 32  // a cell that drained MID_CELLS then: the tree that hangs by it is a part of the work of its own
TAINT   :: 64  // a flood could not decide it, and handed it on
PIT     :: 128 // a pit

AHEAD_BY_INDEX :: [8][2]int{{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}}

// A float as an integer that stands in the floats' order, and a cell's place in the flood's order:
// lowest filled level first, and of two cells at one level the lower index.
fkey :: #force_inline proc(h: f32) -> u32 { b := transmute(u32)h; return b ~ 0x8000_0000 if b & 0x8000_0000 == 0 else ~b }
ckey :: #force_inline proc(g: ^Grid, c: int) -> u64 #no_bounds_check { return u64(fkey(g.fill[c])) << 32 | u64(u32(c)) }

heap64_push :: proc(h: ^[dynamic]u64, k: u64) #no_bounds_check {
	append(h, k)
	i := len(h) - 1
	for i > 0 {
		p := (i - 1)/2
		if h[p] <= k do break
		h[i] = h[p]
		i = p
	}
	h[i] = k
}

heap64_pop :: proc(h: ^[dynamic]u64) -> u64 #no_bounds_check {
	top := h[0]
	last := pop(h)
	n := len(h)
	if n == 0 do return top
	i := 0
	for {
		ch := 2*i + 1
		if ch >= n do break
		if ch + 1 < n && h[ch + 1] < h[ch] do ch += 1
		if h[ch] >= last do break
		h[i] = h[ch]
		i = ch
	}
	h[i] = last
	return top
}

// ---- the lattice's squares ------------------------------------------------------------------------

// What the parallel forming keeps for a grid over a whole landmass. With `all`, every square is
// started already, as grid_make leaves them (the serial forming's, which the check compares).
coarse_attach :: proc(g: ^Grid, all: bool) {
	n := g.n
	co := new(Coarse)
	g.coarse, co.m, co.all = co, n/SQUARE, all
	m := co.m
	co.core, co.ready, co.runs = make([]bool, m*m), make([]bool, m*m), make([][dynamic][2]i32, m)
	co.wide = (n + BLOCK - 1)/BLOCK
	co.pits, co.roots, co.cuts = make([][dynamic]i32, m*co.wide), make([][dynamic]i32, m), make([][dynamic]i32, m)
	co.blocks = {make([]Flood_Block, co.wide*co.wide), make([]Flood_Block, ((n + FLOOD_WIDE - 1)/FLOOD_WIDE)*((n + FLOOD_WIDE - 1)/FLOOD_WIDE))}
	co.flags = slice.reinterpret([]u8, g.seen)
	co.donors, co.was, g.old = make([]u8, n*n), make([]f32, n*n), make([]f32, n*n)
	co.bits = make([]u64, n*m)
	co.rose = make([]f32, (n/ROSE_STEP)*(n/ROSE_STEP))
	if all {
		slice.fill(co.core, true)
		slice.fill(co.ready, true)
		for ty in 0..<m do append(&co.runs[ty], [2]i32{0, i32(n)})
	}
}

coarse_free :: proc(g: ^Grid) {
	co := g.coarse
	if co == nil do return
	delete(co.core); delete(co.ready); delete(co.donors); delete(co.was); delete(co.bits); delete(g.old); delete(co.rose)
	for l in co.runs do delete(l)
	for l in co.pits do delete(l)
	for l in co.roots do delete(l)
	for l in co.cuts do delete(l)
	delete(co.runs); delete(co.pits); delete(co.roots); delete(co.cuts)
	delete(co.heap); delete(co.stack); delete(co.trunk); delete(co.units); delete(co.leaves); delete(co.batches); delete(co.mouths); delete(co.sea_new)
	free(co)
	g.coarse, g.old = nil, nil
}

// A grid over a whole landmass as its forming starts, with only the squares that hold land or shallow
// sea, and a ring round them, started: the rest is open sea that nothing reads or writes, and memory
// never written is never taken.
coarse_grid :: proc(n: int) -> ^Grid {
	started := time.now()
	g := grid_make_empty(n)
	coarse_attach(g, false)
	co := g.coarse
	m := co.m
	slice.fill(g.sea, true)
	slice.fill(co.bits, ~u64(0))
	shared(m*m, m, g, proc(g: ^Grid, lo, hi: int) {
		n, m := g.n, g.coarse.m
		for t in lo..<hi {
			core := false
			for j in 0..<SQUARE {
				if core do break
				for i in 0..<SQUARE {
					x, y := (t%m)*SQUARE + i, (t/m)*SQUARE + j
					h, _ := mass_ground((f64(x) + 0.5)*f64(g.d) - region.size/2, (f64(y) + 0.5)*f64(g.d) - region.size/2)
					if h > -WAVE_BASE && x > 0 && y > 0 && x < n - 1 && y < n - 1 {
						core = true
						break
					}
				}
			}
			g.coarse.core[t] = core
		}
	})
	coarse_ready(g)
	co.took[5] += time.duration_seconds(time.since(started))
	return g
}

// Start the cells of every square within RING_SQUARES of the core that is not started yet, and list the
// runs of started squares again.
coarse_ready :: proc(g: ^Grid) {
	co := g.coarse
	m := co.m
	co.grew = false
	fresh := make([dynamic]i32, context.temp_allocator)
	for t in 0..<m*m do if co.core[t] {
		for j in max(t/m - RING_SQUARES, 0)..=min(t/m + RING_SQUARES, m - 1) do for i in max(t%m - RING_SQUARES, 0)..=min(t%m + RING_SQUARES, m - 1) {
			if k := j*m + i; !co.ready[k] {
				co.ready[k] = true
				append(&fresh, i32(k))
			}
		}
	}
	if len(fresh) == 0 do return
	Fresh :: struct { g: ^Grid, list: []i32 }
	f := Fresh{g, fresh[:]}
	shared(len(fresh), 4, &f, proc(f: ^Fresh, lo, hi: int) {
		g, n, m := f.g, f.g.n, f.g.coarse.m
		for t in f.list[lo:hi] do for j in 0..<SQUARE do for i in 0..<SQUARE {
			c := (int(t)/m*SQUARE + j)*n + int(t)%m*SQUARE + i
			cell_start(g, c)
			g.next[c] = -1
		}
	})
	for ty in 0..<m {
		clear(&co.runs[ty])
		for tx := 0; tx < m; tx += 1 {
			if !co.ready[ty*m + tx] do continue
			from := tx
			for tx + 1 < m && co.ready[ty*m + tx + 1] do tx += 1
			append(&co.runs[ty], [2]i32{i32(from*SQUARE), i32((tx + 1)*SQUARE)})
		}
	}
}

// A cell written by something that can make land or shallow sea where there was neither: its square
// is the core's from now on.
coarse_touch :: #force_inline proc(g: ^Grid, c: int) {
	co := g.coarse
	if co == nil do return
	if t := (c/g.n)/SQUARE*co.m + (c%g.n)/SQUARE; !co.core[t] do co.core[t], co.grew = true, true
}

// Work over the started squares, shared among threads a row of squares to a part: `work` is given each
// row of cells of each run of them.
Over :: struct($T: typeid) { g: ^Grid, data: ^T, work: proc(data: ^T, g: ^Grid, ty, y, x0, x1: int) }
over :: proc(g: ^Grid, data: ^$T, work: proc(data: ^T, g: ^Grid, ty, y, x0, x1: int)) {
	o := Over(T){g, data, work}
	shared(g.coarse.m, 1, &o, proc(o: ^Over(T), lo, hi: int) {
		for ty in lo..<hi do for run in o.g.coarse.runs[ty] do for y in ty*SQUARE..<(ty + 1)*SQUARE do o.work(o.data, o.g, ty, y, int(run[0]), int(run[1]))
	})
}

// ---- where water goes -----------------------------------------------------------------------------

// The lowest of a cell's eight neighbours in the flood's order, and the way to it. All eight are land:
// the cell is not beside the sea.
lowest :: #force_inline proc(g: ^Grid, c: int) -> (best: int, way: [2]int) #no_bounds_check {
	n, least := g.n, max(u32)
	for d in AHEAD_BY_INDEX {
		nb := c + d.y*n + d.x
		if k := fkey(g.fill[nb]); k < least do least, best, way = k, nb, d
	}
	return
}

// The level the flood leaves a cell at when it reaches it from `from`, which lies `way` back from it.
reached :: #force_inline proc(g: ^Grid, c, from: int, way: [2]int) -> f32 #no_bounds_check {
	return max(g.z[c], g.fill[from] + 0.001*step(g, from, {-way.x, -way.y}))   // a filled hollow keeps a trace of slope
}

// `route` for a whole landmass: the same filled surface, drainage and land drained, to the bit, as the
// flood from the shore upward that takes of two cells at one level the lower index (`route_plain`).
//
// The flood reaches a cell from the first of its neighbours to come out of the heap: its lowest
// neighbour in the flood's order. A cell that stands over that neighbour by the trace of slope a
// filled hollow keeps is left at its own height; one that does not is raised to it. So a cell is
// raised only if it does not stand over its lowest neighbour by that much (a pit, or a cell on a
// flat), or if its lowest neighbour is itself raised. The flood is therefore run only from the pits:
// each waits for the first neighbour to come out of the heap, and a cell next to one that waits or is
// raised is put in the heap at its own height, and checked when it comes out, by which time every
// cell the flood reaches sooner is settled. A cell whose lowest settled neighbour leaves it at its own
// height goes on as it is; one that is raised goes back in at its new level; one with no settled
// neighbour yet waits in its turn. Every cell is then checked against its neighbours as they were left,
// and since only one surface passes that check, a step where a cell fails it is routed plainly.
route_mass :: proc(g: ^Grid) {
	co := g.coarse
	for c in co.sea_new do g.next[c] = -1
	clear(&co.sea_new)
	// Each land cell's level if nothing raises it, and the land beside the sea, where the flood starts.
	co.land = 0
	over(g, co, proc(co: ^Coarse, g: ^Grid, ty, y, x0, x1: int) {
		n, fl := g.n, co.flags
		count := 0
		defer sync.atomic_add(&co.land, count)
		#no_bounds_check for x := x0; x < x1; x += 1 {
			c := y*n + x
			if x + 8 <= x1 && intrinsics.unaligned_load((^u64)(&g.sea[c])) == 0x0101010101010101 {
				intrinsics.unaligned_store((^u64)(&fl[c]), u64(0))
				for i in 0..<8 do co.was[c + i] = g.z[c + i]   // the sea's floor too: silt may make land of it before the rebound
				x += 7
				continue
			}
			if g.sea[c] {
				fl[c], co.was[c] = 0, g.z[c]
				continue
			}
			count += 1
			beside := beside_sea(g.sea, c, n)
			g.fill[c] = max(g.z[c], 0.05) if beside else g.z[c]
			fl[c] = SEED if beside else 0
			co.was[c] = g.z[c]
		}
	})
	// The pits: cells not beside the sea that do not stand over their lowest neighbour by a trace of slope.
	for &l in co.pits do clear(&l)
	over(g, co, proc(co: ^Coarse, g: ^Grid, ty, y, x0, x1: int) {
		n, fl := g.n, co.flags
		#no_bounds_check for x in x0..<x1 {
			c := y*n + x
			if g.sea[c] || fl[c] != 0 do continue
			low, way := lowest(g, c)
			if reached(g, c, low, way) != g.z[c] {
				fl[c] = PIT
				append(&co.pits[ty*co.wide + x/BLOCK], i32(c))
			}
		}
	})
	flood_pits(g)
	// Each cell checked, and drained to the neighbour its filled surface falls to most steeply.
	bad: int
	Drain :: struct { co: ^Coarse, bad: ^int }
	dr := Drain{co, &bad}
	drain :: proc(dr: ^Drain, g: ^Grid, ty, y, x0, x1: int) #no_bounds_check {
		n, co, fl := g.n, dr.co, dr.co.flags
		for x in x0..<x1 {
			c := y*n + x
			if g.sea[c] do continue
			seed := fl[c] & SEED != 0
			g.next[c] = -1
			if !seed {
				low, way := lowest(g, c)
				if reached(g, c, low, way) != g.fill[c] do sync.atomic_add(dr.bad, 1)
				g.next[c] = i32(low)
			}
			was := g.area[c]
			drain_cell(g, c, x, y)
			fl[c] = (SEED if seed else 0) | (BIG if was >= BIG_CELLS*g.d*g.d else MID if was >= MID_CELLS*g.d*g.d else 0)
			if g.next[c] < 0 do append(&co.roots[ty], i32(c))
		}
	}
	for &l in co.roots do clear(&l)
	over(g, &dr, drain)
	if bad > 0 {   // never seen; kept so that a fault in the reasoning above costs time and not the land
		co.failed += 1
		flood_plain(g)
		bad = 0
		for &l in co.roots do clear(&l)
		over(g, &dr, drain)
	}
	trees_make(g)
	// The mouths the silt is laid from, in the flood's order.
	clear(&co.mouths)
	for l in co.roots do for c in l do if g.area[c] >= CHANNEL_AREA do append(&co.mouths, ckey(g, int(c)))
	slice.sort(co.mouths[:])
}

// The flood from the pits (route_mass). Hollows far apart know nothing of each other, so the lattice
// is flooded block by block, side by side: each block's pits in one heap, in the flood's order. A
// block's flood reads no cell of another block. What it would have to read there, it cannot decide: a
// cell with a neighbour on the block's outermost ring, or beside a cell left undecided, or reached
// from a cell beside one, is itself left undecided, put back as it stood and handed on. The undecided
// cells are flooded again in blocks four times as wide, which settle all but those along their own
// edges, and the rest over the whole lattice. Each of those floods takes up the flood's order where
// the cells settled below it stand in it: a settled cell that comes out of the heap later than a
// waiting cell beside it is put in again, to reach it in its turn.
//
// One thing a block cannot see is a hollow outside it that floods back into it, up a valley that
// leaves the block. So where a flood raises a cell or makes it wait, any cell settled below it that
// came later in the flood's order and was left at its own height over that cell, or reached from it,
// is put back and settled again in its turn, and so on through whatever was settled from it.
FLOOD_WIDE :: 4*BLOCK
flood_pits :: proc(g: ^Grid) #no_bounds_check {
	co := g.coarse
	n := g.n
	T := time.now()
	lap :: proc(co: ^Coarse, t: ^time.Time, i: int) {
		now := time.now()
		co.flood[i] += time.duration_seconds(time.diff(t^, now))
		t^ = now
	}
	shared(len(co.blocks[0]), 1, g, proc(g: ^Grid, lo, hi: int) { for b in lo..<hi do flood_block(g, 0, b) })
	lap(co, &T, 0)
	wide := (n + FLOOD_WIDE - 1)/FLOOD_WIDE
	for &fb in co.blocks[1] do clear(&fb.pits)
	for &fb in co.blocks[0] do for c in fb.later do append(&co.blocks[1][int(c)/n/FLOOD_WIDE*wide + int(c)%n/FLOOD_WIDE].pits, c)
	shared(len(co.blocks[1]), 1, g, proc(g: ^Grid, lo, hi: int) { for b in lo..<hi do flood_block(g, 1, b) })
	lap(co, &T, 1)
	clear(&co.late.pits)
	for &fb in co.blocks[1] do append(&co.late.pits, ..fb.later[:])
	flood_block(g, 2, 0)
	lap(co, &T, 2)
}

// The cells handed to a block flooded: its pits (level 0), or what the blocks below left undecided
// (level 1: block b of those four times as wide; 2: the whole lattice).
flood_block :: proc(g: ^Grid, level, b: int) #no_bounds_check {
	co := g.coarse
	n, fl := g.n, co.flags
	fb := &co.late if level == 2 else &co.blocks[level][b]
	clear(&fb.later); clear(&fb.heap); clear(&fb.undecided)
	if level == 0 {
		clear(&fb.pits)
		for ty in b/co.wide*BLOCK/SQUARE..<min((b/co.wide + 1)*BLOCK/SQUARE, co.m) do append(&fb.pits, ..co.pits[ty*co.wide + b%co.wide][:])
	}
	if len(fb.pits) == 0 do return
	ways := OFFSETS
	Run :: struct { g: ^Grid, fb: ^Flood_Block, ahead: [8]int, level: int, x0, y0, x1, y1: int, stack, waits: [dynamic]i32 }
	run := Run{g = g, fb = fb, level = level, x1 = n, y1 = n}
	defer { delete(run.stack); delete(run.waits) }
	for o, k in ways do run.ahead[k] = o.y*n + o.x
	if level < 2 {   // the cells a block's flood may read: all of the block; and decide: all but its outermost ring
		side := BLOCK if level == 0 else FLOOD_WIDE
		wide := (n + side - 1)/side
		run.x0, run.y0, run.x1, run.y1 = b%wide*side + 1, b/wide*side + 1, min((b%wide + 1)*side, n) - 1, min((b/wide + 1)*side, n) - 1
	}
	inside :: #force_inline proc(run: ^Run, c: int) -> bool { x, y := c%run.g.n, c/run.g.n; return x >= run.x0 && y >= run.y0 && x < run.x1 && y < run.y1 }
	// Whether a cell has a neighbour this flood cannot decide.
	unsure :: #force_inline proc(run: ^Run, c: int) -> bool #no_bounds_check {
		g, fl := run.g, run.g.coarse.flags
		for k in 0..<8 {
			nb := c + run.ahead[k]
			if g.sea[nb] do continue
			if fl[nb] & TAINT != 0 || run.level < 2 && !inside(run, nb) do return true
		}
		return false
	}
	// Leave a cell undecided, and with it every waiting cell beside it, which it might have reached.
	leave :: proc(run: ^Run, c: int) #no_bounds_check {
		fl := run.g.coarse.flags
		append(&run.stack, i32(c))
		fl[c] |= TAINT
		for len(run.stack) > 0 {
			t := int(pop(&run.stack))
			append(&run.fb.undecided, i32(t))
			for k in 0..<8 {
				nb := t + run.ahead[k]
				if fl[nb] & (STATE | TAINT) != PENDING do continue
				fl[nb] |= TAINT
				append(&run.stack, i32(nb))
			}
		}
	}
	// Whether settled cell q was left at its own height over x, or reached from it: x, at `key`, came
	// first in the flood's order of all the settled cells round q.
	leans :: #force_inline proc(run: ^Run, q, x: int, key: u64) -> bool #no_bounds_check {
		g, fl := run.g, run.g.coarse.flags
		for k in 0..<8 {
			j := q + run.ahead[k]
			if j == x || g.sea[j] do continue
			if s := fl[j] & STATE; (s == OUT || s == DONE || s == REPLAY) && ckey(g, j) < key do return false
		}
		return true
	}
	// A settled cell that comes out of the heap after a waiting cell beside it began to wait goes in again.
	replay :: #force_inline proc(run: ^Run, q: int) #no_bounds_check {
		fl := run.g.coarse.flags
		if fl[q] & STATE != DONE do return
		fl[q] = fl[q] & ~u8(STATE) | REPLAY
		heap64_push(&run.fb.heap, ckey(run.g, q))
	}
	// A cell settled below that leant on one this flood has now raised or made wait, at `now`: put back
	// to be settled again in its turn, with every cell settled from it.
	again :: proc(run: ^Run, first: int, now: u64) #no_bounds_check {
		g, fl := run.g, run.g.coarse.flags
		append(&run.stack, i32(first))
		clear(&run.waits)
		for len(run.stack) > 0 {
			x := int(pop(&run.stack))
			if s := fl[x] & STATE; s != DONE && s != REPLAY do continue
			old := ckey(g, x)
			for k in 0..<8 {
				q := x + run.ahead[k]
				if g.sea[q] || fl[q] & SEED != 0 do continue
				if s := fl[q] & STATE; (s == DONE || s == REPLAY) && ckey(g, q) > old && leans(run, q, x, old) do append(&run.stack, i32(q))
			}
			own := u64(fkey(g.z[x])) << 32 | u64(u32(x))
			joined := g.fill[x] != g.z[x] || fl[x] & PIT != 0
			g.fill[x] = g.z[x]
			if joined && (fl[x] & PIT != 0 || own < now) {   // it waited before now, and waits again for what reaches it
				fl[x] = fl[x] & ~u8(STATE) | PENDING
				append(&run.waits, i32(x))
			} else {
				fl[x] = fl[x] & ~u8(STATE) | SOURCE
				heap64_push(&run.fb.heap, own)
			}
		}
		for x in run.waits {
			if fl[x] & STATE != PENDING do continue
			if run.level < 2 && unsure(run, int(x)) {
				leave(run, int(x))
				continue
			}
			for k in 0..<8 {
				q := int(x) + run.ahead[k]
				if !g.sea[q] && fl[q] & (STATE | TAINT) == DONE && ckey(g, q) > now do replay(run, q)
			}
		}
	}
	// A cell has joined a hollow (it waits, or is raised), at `now` in the flood's order: every
	// neighbour not in the heap goes in at its own height, to be checked when it comes out. `first`:
	// it waited from the start, as a pit does.
	beside :: proc(run: ^Run, c: int, now: u64, first := false) #no_bounds_check {
		g, fb := run.g, run.fb
		fl := g.coarse.flags
		for k in 0..<8 {
			nb := c + run.ahead[k]
			if g.sea[nb] || fl[nb] & TAINT != 0 do continue
			if run.level < 2 && !inside(run, nb) {   // out of this flood's reach, and now to be looked at: handed on
				if fl[nb] & STATE == OUT {
					fl[nb] |= TAINT
					append(&fb.later, i32(nb))
				}
				continue
			}
			switch fl[nb] & STATE {
			case OUT:
				fl[nb] |= SOURCE
				heap64_push(&fb.heap, ckey(g, nb))
			case DONE, REPLAY:   // settled by a flood below
				key := ckey(g, nb)
				if key < now do continue
				if !first && fl[nb] & SEED == 0 && leans(run, nb, c, now) do again(run, nb, now)
				else if fl[c] & STATE == PENDING do replay(run, nb)
			}
		}
	}
	// The cells handed in: out of reach, handed on; pits wait; the rest go in the heap at their own height.
	for c in fb.pits {
		if level < 2 && !inside(&run, int(c)) {
			fl[c] |= TAINT
			append(&fb.later, c)
		} else do fl[c] &= ~u8(TAINT)
	}
	for c in fb.pits do if fl[c] & (TAINT | PIT) == PIT do fl[c] = fl[c] & ~u8(STATE) | PENDING
	for c in fb.pits do if fl[c] & TAINT == 0 {
		if fl[c] & PIT != 0 {
			if unsure(&run, int(c)) do leave(&run, int(c))
			else do beside(&run, int(c), 0, true)
		} else if fl[c] & STATE == OUT {
			fl[c] |= SOURCE
			heap64_push(&fb.heap, ckey(g, int(c)))
		}
	}
	h := &fb.heap
	for len(h) > 0 {
		key := heap64_pop(h)
		c := int(u32(key))
		state := fl[c] & STATE
		if fl[c] & TAINT != 0 || state == PENDING || state == OUT || state == DONE || key != ckey(g, c) do continue   // put back or settled since it went in
		if fl[c] & (STATE | SEED) == SOURCE {   // not beside the sea: is it left at its own height?
			if unsure(&run, c) {
				leave(&run, c)
				continue
			}
			low, way, least := -1, [2]int{}, key
			for o, k in ways {
				nb := c + run.ahead[k]
				if s := fl[nb] & STATE; s != OUT && s != DONE do continue
				if kk := ckey(g, nb); kk < least do least, low, way = kk, nb, o
			}
			if low < 0 {   // nothing has reached it yet: it waits
				fl[c] = fl[c] & ~u8(STATE) | PENDING
				beside(&run, c, key)
				continue
			}
			if level < 2 && fl[low] & STATE == OUT && unsure(&run, low) {   // the cell it would be reached from is itself beside one this flood cannot decide
				leave(&run, c)
				continue
			}
			if level_ := reached(g, c, low, way); level_ != g.fill[c] {   // raised: back in at its level
				beside(&run, c, key)
				if fl[c] & TAINT != 0 do continue
				g.fill[c] = level_
				fl[c] = fl[c] & ~u8(STATE) | CLAIMED
				heap64_push(h, ckey(g, c))
				continue
			}
		}
		// Settled. A cell settled below that this one now comes before, of all the settled cells round it,
		// must stand as this one leaves it; one that does not is put back, to be settled again in its turn.
		if level > 0 && state != REPLAY do for o, k in ways {
			nb := c + run.ahead[k]
			if s := fl[nb] & STATE; s != DONE && s != REPLAY || g.sea[nb] || fl[nb] & (SEED | TAINT) != 0 do continue
			if ckey(g, nb) > key && g.fill[nb] != max(g.z[nb], g.fill[c] + 0.001*step(g, c, o)) && leans(&run, nb, c, key) do again(&run, nb, key)
		}
		fl[c] = fl[c] & ~u8(STATE) | DONE
		for o, k in ways {
			nb := c + run.ahead[k]
			if fl[nb] & (STATE | TAINT) != PENDING do continue
			g.fill[nb] = max(g.z[nb], g.fill[c] + 0.001*step(g, c, o))
			fl[nb] = fl[nb] & ~u8(STATE) | CLAIMED
			heap64_push(h, ckey(g, nb))
		}
	}
	// What was left undecided, put back as it stood and handed on.
	for c in fb.undecided {
		if fl[c] & SEED == 0 do g.fill[c] = g.z[c]
		fl[c] &= SEED | PIT | TAINT
		append(&fb.later, c)
	}
}

// The whole flood through the heap, lowest first and of two at one level the lower index: every land
// cell's filled level, on the squares that are started. The cells' own levels are set already.
flood_plain :: proc(g: ^Grid) #no_bounds_check {
	co := g.coarse
	n, fl, h := g.n, co.flags, &co.heap
	ways := OFFSETS
	clear(h)
	for runs, ty in co.runs do for run in runs do for y in ty*SQUARE..<(ty + 1)*SQUARE do for x in int(run[0])..<int(run[1]) {
		c := y*n + x
		if g.sea[c] do continue
		if fl[c] & SEED != 0 {
			g.fill[c] = max(g.z[c], 0.05)
			fl[c] = SEED | DONE
			heap64_push(h, ckey(g, c))
		} else do fl[c] = PENDING
	}
	for len(h) > 0 {
		c := int(u32(heap64_pop(h)))
		for o in ways {
			nb := c + o.y*n + o.x
			if g.sea[nb] || fl[nb] != PENDING do continue
			g.fill[nb] = max(g.z[nb], g.fill[c] + 0.001*step(g, c, o))
			fl[nb] = DONE
			heap64_push(h, ckey(g, nb))
		}
	}
}

// `route` as the serial forming runs it on a whole landmass, with the heap taking of two cells at one
// level the lower index: what `route_mass` is checked against.
route_plain :: proc(g: ^Grid) #no_bounds_check {
	n := g.n
	h := &g.coarse.heap
	clear(&g.order)
	clear(h)
	copy(g.seen, g.sea)
	slice.fill(g.next, -1)
	copy(g.fill, g.z)
	copy(g.coarse.was, g.z)
	for y in 0..<n do for x in 0..<n {
		c := y*n + x
		if g.sea[c] || !(x == 0 || y == 0 || x == n - 1 || y == n - 1 || beside_sea(g.sea, c, n)) do continue
		g.fill[c] = max(g.z[c], 0.05)
		g.seen[c] = true
		heap64_push(h, ckey(g, c))
	}
	for len(h) > 0 {
		c := int(u32(heap64_pop(h)))
		append(&g.order, i32(c))
		y := c/n
		x := c - y*n
		for o in OFFSETS {
			if x + o.x < 0 || y + o.y < 0 || x + o.x >= n || y + o.y >= n do continue
			nb := c + o.y*n + o.x
			if g.seen[nb] do continue
			g.seen[nb] = true
			g.fill[nb] = max(g.z[nb], g.fill[c] + 0.001*step(g, c, o))
			g.next[nb] = i32(c)
			heap64_push(h, ckey(g, nb))
		}
	}
	shared(n, rows(n), g, proc(g: ^Grid, lo, hi: int) {
		n := g.n
		#no_bounds_check for y in lo..<hi do for x in 0..<n do if c := y*n + x; !g.sea[c] do drain_cell(g, c, x, y)
	})
	#reverse for c in g.order {
		if r := g.next[c]; r >= 0 do g.area[r] += g.area[c]
	}
}

// ---- the drainage's trees ---------------------------------------------------------------------------

// The land's cells in an order where each comes after the cell it drains to, in parts that can be
// worked side by side: the trunks, river by river (the cells that drained BIG_CELLS at the last step,
// from each mouth up; nothing depends on which they are, only how evenly the work is shared), and the
// trees that hang on the trunks or stand on the shore, LEAF_BATCH to a part. Each cell's donors are
// noted on the way.
trees_make :: proc(g: ^Grid, drained := true) #no_bounds_check {
	co := g.coarse
	n, fl := g.n, co.flags
	ways := OFFSETS
	ahead: [8]int
	for o, k in ways do ahead[k] = o.y*n + o.x
	clear(&co.trunk); clear(&co.units); clear(&co.leaves); clear(&co.stack)
	for l in co.roots do for r in l {
		if fl[r] & BIG == 0 {
			append(&co.leaves, r)
			continue
		}
		from := len(co.trunk)
		append(&co.stack, r)
		for len(co.stack) > 0 {
			c := int(pop(&co.stack))
			append(&co.trunk, i32(c))
			mask: u8
			for k in 0..<8 {
				nb := c + ahead[k]
				if g.next[nb] != i32(c) do continue
				mask |= 1 << u8(k)
				if fl[nb] & BIG != 0 do append(&co.stack, i32(nb))
				else do append(&co.leaves, i32(nb))
			}
			co.donors[c] = mask
		}
		append(&co.units, [2]i32{i32(from), i32(len(co.trunk))})
	}
	// The trees in parts of about even work: a large tree alone, the small LEAF_BATCH together.
	clear(&co.parts)
	for i, small := 0, 0; i < len(co.leaves); i += 1 {
		mid := fl[co.leaves[i]] & (MID | BIG) != 0
		if mid || small == 0 do append(&co.parts, i32(i))
		small = 0 if mid else (small + 1)%LEAF_BATCH
	}
	append(&co.parts, i32(len(co.leaves)))
	resize_dynamic_array(&co.batches, len(co.parts) - 1)
	co.epoch = sync.atomic_add(&coarse_epochs, 1) + 1
	co.drained = drained
	shared(len(co.batches), 1, g, proc(g: ^Grid, lo, hi: int) {
		co, n := g.coarse, g.n
		ways := OFFSETS
		ahead: [8]int
		for o, k in ways do ahead[k] = o.y*n + o.x
		if tree_epoch != co.epoch {
			clear(&tree_order)
			tree_epoch = co.epoch
		}
		#no_bounds_check for b in lo..<hi {
			from := len(tree_order)
			for r in co.leaves[co.parts[b]:co.parts[b + 1]] {
				append(&tree_stack, r)
				for len(tree_stack) > 0 {
					c := int(pop(&tree_stack))
					append(&tree_order, i32(c))
					mask: u8
					for k in 0..<8 {
						nb := c + ahead[k]
						if g.next[nb] != i32(c) do continue
						mask |= 1 << u8(k)
						append(&tree_stack, i32(nb))
					}
					co.donors[c] = mask
				}
			}
			co.batches[b] = {&tree_order, from, len(tree_order)}
			if co.drained do #reverse for c in tree_order[from:] do gather(g, g.area, int(c), &ahead)   // the land each drains, while its cells are at hand
		}
	})
	if drained do trunks_up(g, g.area)
}

// Add to a cell's value its donors', the last the flood reached first, as adding each cell's to the
// cell it drains to does when the cells are taken from the last the flood reached to the first.
gather :: #force_inline proc(g: ^Grid, v: []f32, c: int, ahead: ^[8]int) #no_bounds_check {
	mask := g.coarse.donors[c]
	if mask == 0 do return
	if mask & (mask - 1) == 0 {
		v[c] += v[c + ahead[intrinsics.count_trailing_zeros(mask)]]
		return
	}
	cells: [8]int
	keys: [8]u64
	count := 0
	for m := mask; m != 0; m &= m - 1 {
		nb := c + ahead[intrinsics.count_trailing_zeros(m)]
		k := ckey(g, nb)
		i := count
		for ; i > 0 && keys[i - 1] < k; i -= 1 do keys[i], cells[i] = keys[i - 1], cells[i - 1]
		keys[i], cells[i] = k, nb
		count += 1
	}
	sum := v[c]
	for i in 0..<count do sum += v[cells[i]]
	v[c] = sum
}

// A value carried down the trunks, once the trees that hang on them have carried theirs.
trunks_up :: proc(g: ^Grid, v: []f32) {
	Up :: struct { g: ^Grid, v: []f32 }
	up := Up{g, v}
	shared(len(g.coarse.units), 1, &up, proc(up: ^Up, lo, hi: int) {
		g, n := up.g, up.g.n
		ways := OFFSETS
		ahead: [8]int
		for o, k in ways do ahead[k] = o.y*n + o.x
		#no_bounds_check for u in g.coarse.units[lo:hi] do #reverse for c in g.coarse.trunk[u.x:u.y] do gather(g, up.v, int(c), &ahead)
	})
}

// `erode` for a whole landmass: each cell once the cell it drains to has had its step, and the rock
// each carries with all that is carried into it.
erode_mass :: proc(g: ^Grid, dt: f32) {
	co := g.coarse
	Cut :: struct { g: ^Grid, dt: f32 }
	cut := Cut{g, dt}
	shared(len(co.units), 1, &cut, proc(cut: ^Cut, lo, hi: int) {
		for u in cut.g.coarse.units[lo:hi] do for c in cut.g.coarse.trunk[u.x:u.y] do erode_cell(cut.g, int(c), cut.dt)
	})
	shared(len(co.batches), 1, &cut, proc(cut: ^Cut, lo, hi: int) {
		g, n := cut.g, cut.g.n
		ways := OFFSETS
		ahead: [8]int
		for o, k in ways do ahead[k] = o.y*n + o.x
		#no_bounds_check for b in g.coarse.batches[lo:hi] {
			for c in b.buf[b.lo:b.hi] do erode_cell(g, int(c), cut.dt)
			#reverse for c in b.buf[b.lo:b.hi] do gather(g, g.load, int(c), &ahead)
		}
	})
	trunks_up(g, g.load)
}

// `creep` for a whole landmass.
creep_mass :: proc(g: ^Grid, dt: f32) {
	rounds := int(math.ceil(CREEP*dt/(0.2*g.d*g.d)))
	k := CREEP*dt/(f32(rounds)*g.d*g.d)
	for _ in 0..<rounds {
		over(g, &k, proc(k: ^f32, g: ^Grid, ty, y, x0, x1: int) { #no_bounds_check for c in y*g.n + x0..<y*g.n + x1 do g.old[c] = max(g.z[c], 0) })
		over(g, &k, proc(k: ^f32, g: ^Grid, ty, y, x0, x1: int) { #no_bounds_check for c in y*g.n + x0..<y*g.n + x1 do if !g.sea[c] do creep_cell(g, g.old, c, k^) })
	}
}

// ---- the coast --------------------------------------------------------------------------------------

// The sea as bits, as it stands.
sea_bits :: proc(g: ^Grid) {
	over(g, g.coarse, proc(co: ^Coarse, g: ^Grid, ty, y, x0, x1: int) {
		#no_bounds_check for x := x0; x < x1; x += SQUARE {
			w: u64
			for i in 0..<8 {
				b := intrinsics.unaligned_load((^u64)(&g.sea[y*g.n + x + 8*i]))
				w |= ((b*0x0102040810204080) >> 56) << u64(8*i)
			}
			co.bits[y*co.m + x/SQUARE] = w
		}
	})
}

// The share of sea in a square r cells either side of a cell, from the bits (`share`).
share_bits :: proc(co: ^Coarse, n, x, y, r: int) -> f32 #no_bounds_check {
	x0, y0, x1, y1 := clamp(x - r, 0, n), clamp(y - r, 0, n), clamp(x + r + 1, 0, n), clamp(y + r + 1, 0, n)
	if x1 <= x0 || y1 <= y0 do return 0
	count := 0
	for j in y0..<y1 do for w in x0/64..=(x1 - 1)/64 {
		word := co.bits[j*co.m + w]
		if lo := x0 - w*64; lo > 0 do word &= ~u64(0) << u64(lo)
		if hi := x1 - w*64; hi < 64 do word &= ~u64(0) >> u64(64 - hi)
		count += int(intrinsics.count_ones(word))
	}
	return f32(count)/f32(max((x1 - x0)*(y1 - y0), 1))
}

exposure_bits :: proc(co: ^Coarse, n, x, y, r: int, ahead: [2]int) -> f32 {
	around := share_bits(co, n, x, y, r)
	return around*around*(0.3 + 0.7*share_bits(co, n, x + ahead.x, y + ahead.y, r))
}

// `coast` for a whole landmass. The serial forming takes the shore's cells in the flood's order
// because a cell the sea cuts through changes what its neighbours later in that order meet: the
// highest ground and deepest water beside them, and whether they lie beside the sea at all. Few
// cells are cut through in a step. So every shore cell is first worked as if none were, side by
// side; then those that would be cut through are taken in the flood's order, each cut exposing its
// neighbours later in that order, which are worked again from how they stood.
coast_mass :: proc(g: ^Grid, dt: f32) #no_bounds_check {
	co := g.coarse
	n, fl := g.n, co.flags
	assert(region.shape.bank == 0 && region.shape.reef == 0)
	sea_bits(g)
	Shore :: struct { co: ^Coarse, dt: f32, r, back: int, ahead: [2]int }
	bearing := math.to_radians(f32(region.shape.swell))
	r := max(int(FETCH/g.d), 2)
	sh := Shore{co, dt, r, max(int(100/g.d), 1), {int(math.round(math.sin(bearing)*f32(r))), int(math.round(-math.cos(bearing)*f32(r)))}}
	over(g, &sh, proc(sh: ^Shore, g: ^Grid, ty, y, x0, x1: int) {
		n, fl := g.n, sh.co.flags
		#no_bounds_check for x in x0..<x1 {
			c := y*n + x
			if g.sea[c] {
				if g.z[c] > -WAVE_BASE do g.z[c] -= ABRADE*sh.dt*(1 + g.z[c]/WAVE_BASE)
				continue
			}
			fl[c] = u8(beside_sea(g.sea, c, n))
		}
	})
	// What a shore cell meets: the highest ground and the deepest water within 100 m, and how open it lies.
	meets :: #force_inline proc(g: ^Grid, sh: ^Shore, c: int) -> (wears, exposed: f32) #no_bounds_check {
		n := g.n
		x, y := c%n, c/n
		cliff, deep: f32
		for j in max(y - sh.back, 0)..=min(y + sh.back, n - 1) do for i in max(x - sh.back, 0)..=min(x + sh.back, n - 1) do cliff, deep = max(cliff, g.z[j*n + i]), max(deep, -g.z[j*n + i])
		exposed = exposure_bits(sh.co, n, x, y, sh.r, sh.ahead)
		law := wear(g, c, 0.5)
		return WAVES*sh.dt*exposed*law.erodes*min(deep/WAVE_BASE, 1)/(cliff + PLATFORM), exposed
	}
	for &l in co.cuts do clear(&l)
	over(g, &sh, proc(sh: ^Shore, g: ^Grid, ty, y, x0, x1: int) {
		n, fl := g.n, sh.co.flags
		#no_bounds_check for x in x0..<x1 {
			c := y*n + x
			if g.sea[c] || fl[c] == 0 do continue
			wears, exposed := meets(g, sh, c)
			g.old[c] = g.cut[c]
			if exposed >= SHELTER {
				if g.cut[c] + wears >= g.d do append(&sh.co.cuts[ty], i32(c))
				else do g.cut[c] += wears
			} else if g.cut[c] >= g.d do append(&sh.co.cuts[ty], i32(c))
			g.face[c] = 1 + smoothstep(SHELTER, 0.2, exposed)
		}
	})
	h := &co.heap
	clear(h)
	for l in co.cuts do for c in l {
		fl[c] = 2
		heap64_push(h, ckey(g, int(c)))
	}
	for len(h) > 0 {
		key := heap64_pop(h)
		c := int(u32(key))
		wears, exposed := meets(g, &sh, c)
		if exposed >= SHELTER do g.cut[c] += wears
		if g.cut[c] >= g.d {
			g.z[c], g.sea[c] = -PLATFORM, true
			append(&co.sea_new, i32(c))
			for o in OFFSETS {   // the cells after it beside it now lie beside the sea
				nb := c + o.y*n + o.x
				if g.sea[nb] || fl[nb] == 2 || ckey(g, nb) < key do continue
				if fl[nb] == 1 do g.cut[nb] = g.old[nb]
				fl[nb] = 2
				heap64_push(h, ckey(g, nb))
			}
		}
		g.face[c] = 1 + smoothstep(SHELTER, 0.2, exposed)
		fl[c] = 3
	}
	// What the streams carry down settles where the sea is sheltered, mouth by mouth in the flood's order (`coast`).
	if region.shape.silt == 0 do return
	if g.reached == nil do g.reached = make([]i32, n*n)
	queue := make([dynamic][2]i32)
	defer delete(queue)
	for key in co.mouths {
		ci := i32(u32(key))
		g.mouths += 1
		left := g.load[ci]*f32(region.shape.silt)
		clear(&queue)
		append(&queue, [2]i32{ci, 0})
		for head := 0; head < len(queue) && left > 0; head += 1 {
			k, out := int(queue[head].x), queue[head].y + 1
			top := max(FLAT - FLAT_FALL*g.d*f32(out), FLAT_FOOT)
			for o in OFFSETS {
				x, y := k%n + o.x, k/n + o.y
				c := y*n + x
				if x < 0 || y < 0 || x >= n || y >= n || !g.sea[c] || g.reached[c] == g.mouths do continue
				g.reached[c] = g.mouths
				if exposure_bits(co, n, x, y, sh.r, sh.ahead) >= SHELTER do continue
				coarse_touch(g, c)
				need := max(top - g.z[c], 0)*g.d*g.d
				if left < need {
					g.z[c] += left/(g.d*g.d)
					left = 0
					break
				}
				g.z[c] = max(g.z[c], top)
				if g.z[c] > 0 do g.sea[c] = false
				append(&queue, [2]i32{i32(c), out})
			}
		}
	}
}

// ---- the rebound ------------------------------------------------------------------------------------

// A landmass floats: as rock is worn off it, the crust under it rises by the worn rock's weight over
// the mantle's, 2,700 kg/m³ over 3,300 (Airy), spread over the flexure of the plate, here the mean over
// a square REBOUND_WIDE across. Islands are too small for it to matter; a continent that hardly rises
// is otherwise planed to the sea in the 64 m phases' 3 Myr (seed 1's, from the history's median of
// 1,156 m to 73 m). Only the coarse stage rebounds: the finer phases' 0.4 Myr wear too little.
//
// The mean is taken as a sum along each row and then down each column, each a running sum from the
// lattice's first cell in which the open sea counts for nothing, so it comes out the same whichever
// squares are started and however the rows and columns are shared among threads.
// The crust does not stop rising when the cells get finer: the pieces go on rising through their finer
// phases at the rate the rebound raised the coarse stage over its last ROSE_STEPS steps, kept every
// ROSE_STEP cells (it is a mean over 24 km) and the same on both sides of every cut. Without it a piece
// wears a hundred metres and more below the coarse stage beside it (measured on seed 7's coast: a
// median 145 m), which drowns its coast and leaves a step where formed land meets land drawn from afar.
ROSE_STEPS   :: 8
ROSE_STEP    :: 8
ISOSTASY     :: 0.82
REBOUND_WIDE :: 24_000   // metres (a guess within the 50 to 200 km a continental plate's flexure spreads a load; a smaller square keeps valleys and ranges apart)
rebound :: proc(g: ^Grid, uplifted: f32) {
	co := g.coarse
	Up :: struct { g: ^Grid, r: int, uplifted: f32 }
	up := Up{g, max(int(REBOUND_WIDE/2/g.d), 1), uplifted}
	assert(up.r <= RING_SQUARES*SQUARE)
	// The rock worn off the land this step, summed over the cells r either side along the row, into `old`.
	shared(co.m, 1, &up, proc(up: ^Up, lo, hi: int) {
		g, co, n, r := up.g, up.g.coarse, up.g.n, up.r
		resize_dynamic_array(&row_sums, n + 1)
		p := row_sums[:]
		#no_bounds_check for ty in lo..<hi do if runs := co.runs[ty][:]; len(runs) > 0 do for y in ty*SQUARE..<(ty + 1)*SQUARE {
			done, sum := 0, f64(0)
			for run in runs {
				from, to := max(int(run[0]) - r, done), min(int(run[1]) + r, n)
				p[from] = sum
				for x in from..<to {
					c := y*n + x
					if !g.sea[c] do sum += f64(co.was[c] + g.uplift[c]*up.uplifted - g.z[c])
					p[x + 1] = sum
				}
				done = to
				for x in int(run[0])..<int(run[1]) do g.old[y*n + x] = f32(p[min(x + r + 1, n)] - p[max(x - r, 0)])
			}
		}
	})
	// And those sums summed over the rows r either side, down each column of squares.
	shared(co.m, 1, &up, proc(up: ^Up, lo, hi: int) {
		g, co, n, m, r := up.g, up.g.coarse, up.g.n, up.g.coarse.m, up.r
		ring := 2*r + 2
		resize_dynamic_array(&row_sums, (ring + 2)*SQUARE)
		#no_bounds_check for tx in lo..<hi {
			first, last := -1, -1
			for ty in 0..<m do if co.ready[ty*m + tx] {
				if first < 0 do first = ty
				last = ty
			}
			if first < 0 do continue
			top, end := first*SQUARE, min((last + 1)*SQUARE + r, n)
			sums := row_sums[ring*SQUARE:][:SQUARE]   // down to the row in hand: nothing above `top`
			for &s in sums do s = 0
			for y in top..<end {
				copy(row_sums[(y%ring)*SQUARE:][:SQUARE], sums)
				if co.ready[y/SQUARE*m + tx] do for i in 0..<SQUARE do sums[i] += f64(g.old[y*n + tx*SQUARE + i])
				rebound_row(g, tx, y - r, top, (last + 1)*SQUARE, ring, r, sums)   // the row whose square ends with this one
			}
			if end == n do for at in n - r..<(last + 1)*SQUARE do rebound_row(g, tx, at, top, (last + 1)*SQUARE, ring, r, sums)   // the last rows, whose squares the lattice's edge cuts
		}
	})
}

// Raise one row of a column of squares by its share of the rock worn off round it: `sums` are the
// column's sums down to the last row of the row's square, and the thread's ring holds them down to
// each of the rows before.
rebound_row :: proc(g: ^Grid, tx, at, top, bottom, ring, r: int, sums: []f64) #no_bounds_check {
	n, co := g.n, g.coarse
	if at < top || at >= bottom || !co.ready[at/SQUARE*co.m + tx] do return
	y0, y1 := max(at - r, 0), min(at + r + 1, n)
	above := row_sums[(y0%ring)*SQUARE:][:SQUARE] if y0 >= top else row_sums[(ring + 1)*SQUARE:][:SQUARE]
	if y0 < top do for &s in above do s = 0
	kept := co.keeping > 0 && at%ROSE_STEP == 0
	for i in 0..<SQUARE {
		x := tx*SQUARE + i
		c := at*n + x
		if g.sea[c] && !(kept && i%ROSE_STEP == 0) do continue
		mean := (sums[i] - above[i])/f64((min(x + r + 1, n) - max(x - r, 0))*(y1 - y0))
		if !g.sea[c] do g.z[c] += ISOSTASY*f32(mean)
		if kept && i%ROSE_STEP == 0 do co.rose[at/ROSE_STEP*(n/ROSE_STEP) + x/ROSE_STEP] += ISOSTASY*f32(mean)*co.keeping
	}
}

// ---- the steps ----------------------------------------------------------------------------------------

// Whether a landmass's coarse stage can be formed in parallel: nothing in its history that the
// parallel forming does not do (vents, a sea that moves, a bank or a reef).
coarse_can :: proc(from: int) -> bool {
	for p in region.history[:from] do if p.vents > 0 || p.sea != 0 do return false
	return region.shape.bank == 0 && region.shape.reef == 0 && len(region.vents) == 0
}

// The history's steps on a whole landmass's grid, up to phase `upto`, in parallel.
mass_phases :: proc(g: ^Grid, upto: int) {
	co := g.coarse
	rise: f32
	for p in region.history do rise += p.sea
	began, steps := time.now(), 0
	for p in region.history[:upto] do steps += int(p.steps)
	for p in region.history[:upto] {
		g.lift, g.rise = p.uplift, rise
		for _ in 0..<int(p.steps) {
			co.keeping = 1/(p.years*ROSE_STEPS) if steps - co.steps <= ROSE_STEPS else 0
			t := time.now()
			lap :: proc(co: ^Coarse, t: ^time.Time, i: int) {
				now := time.now()
				co.took[i] += time.duration_seconds(time.diff(t^, now))
				t^ = now
			}
			route_mass(g)
			lap(co, &t, 0)
			erode_mass(g, p.years)
			lap(co, &t, 1)
			creep_mass(g, p.years)
			lap(co, &t, 2)
			coast_mass(g, p.years)
			lap(co, &t, 3)
			rebound(g, p.years*p.uplift)
			lap(co, &t, 4)
			if co.grew do coarse_ready(g)
			lap(co, &t, 5)
			g.left -= p.years*p.uplift
			co.steps += 1
			if co.steps%16 == 0 do fmt.printfln("  %d steps of %d, %.0f s", co.steps, steps, time.duration_seconds(time.since(began)))
		}
	}
}

// The same steps as the serial forming takes them, the flood through one heap: what the parallel
// forming is checked against. It writes every cell of the lattice, so it is for small landmasses.
plain_phases :: proc(g: ^Grid, upto: int) {
	rise: f32
	for p in region.history do rise += p.sea
	steps := 0
	for p in region.history[:upto] do steps += int(p.steps)
	for p in region.history[:upto] {
		g.lift, g.rise = p.uplift, rise
		for _ in 0..<int(p.steps) {
			g.coarse.keeping = 1/(p.years*ROSE_STEPS) if steps - g.coarse.steps <= ROSE_STEPS else 0
			route_plain(g)
			erode(g, p.years)
			creep(g, p.years)
			coast(g, p.years)
			rebound(g, p.years*p.uplift)
			g.left -= p.years*p.uplift
			g.coarse.steps += 1
		}
	}
}

// How many cells of two grids over one landmass differ in what the coarse stage keeps: on the squares
// with land in either, the ground, the sea, the shore's cut and faces, the rock carried, the land
// drained, and on land the filled level and where it drains.
coarse_differ :: proc(a, b: ^Grid) -> (differ, land: int) {
	n := a.n
	for c in 0..<n*n {
		if a.sea[c] != b.sea[c] {
			differ += 1
			continue
		}
		if a.sea[c] do continue
		land += 1
		same := a.z[c] == b.z[c] && a.cut[c] == b.cut[c] && a.face[c] == b.face[c] && a.load[c] == b.load[c] && a.area[c] == b.area[c] && a.fill[c] == b.fill[c] && a.next[c] == b.next[c]
		if !same do differ += 1
	}
	for v, i in a.coarse.rose do if v != b.coarse.rose[i] do differ += 1
	// The sea's floor wherever the parallel forming started a square.
	for c in 0..<n*n do if a.sea[c] && b.sea[c] {
		t := (c/n)/SQUARE*a.coarse.m + (c%n)/SQUARE
		if a.coarse.ready[t] && b.coarse.ready[t] && a.z[c] != b.z[c] do differ += 1
	}
	return
}

// Both formings step by step, side by side, each stage compared: says the first stage of the first
// step after which a cell differs, and how many.
check_phases :: proc(g, p: ^Grid, upto: int) {
	rise: f32
	for ph in region.history do rise += ph.sea
	differ :: proc(a, b: ^Grid, v, w: []$T, land: bool) -> (count: int) {
		for c in 0..<a.n*a.n do if !a.sea[c] && !b.sea[c] && v[c] != w[c] do count += 1
		return
	}
	said := 0
	say :: proc(g, p: ^Grid, step: int, stage: string, said: ^int) {
		if said^ > 12 do return
		sea := 0
		for c in 0..<g.n*g.n do if g.sea[c] != p.sea[c] do sea += 1
		routed := stage == "routing" || stage == "cutting"   // the filled level and the drainage are routing's, and stand until the creep
		counts := [?]int{sea, differ(g, p, g.z, p.z, true), differ(g, p, g.fill, p.fill, true) if routed else 0, differ(g, p, g.next, p.next, true) if routed else 0, differ(g, p, g.area, p.area, true) if routed else 0,
			differ(g, p, g.load, p.load, true) if stage == "cutting" else 0, differ(g, p, g.cut, p.cut, true), differ(g, p, g.face, p.face, true)}
		total := 0
		for k in counts do total += k
		if total == 0 do return
		said^ += 1
		fmt.printfln("step %d after %s: cells that differ: sea %d, ground %d, filled level %d, drainage %d, land drained %d, rock carried %d, cut %d, face %d", step, stage, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7])
	}
	step, steps := 0, 0
	for ph in region.history[:upto] do steps += int(ph.steps)
	for ph in region.history[:upto] {
		g.lift, g.rise, p.lift, p.rise = ph.uplift, rise, ph.uplift, rise
		for _ in 0..<int(ph.steps) {
			g.coarse.keeping = 1/(ph.years*ROSE_STEPS) if steps - step <= ROSE_STEPS else 0
			p.coarse.keeping = g.coarse.keeping
			route_mass(g); route_plain(p)
			say(g, p, step, "routing", &said)
			erode_mass(g, ph.years); erode(p, ph.years)
			say(g, p, step, "cutting", &said)
			creep_mass(g, ph.years); creep(p, ph.years)
			say(g, p, step, "creep", &said)
			coast_mass(g, ph.years); coast(p, ph.years)
			say(g, p, step, "the coast", &said)
			rebound(g, ph.years*ph.uplift); rebound(p, ph.years*ph.uplift)
			say(g, p, step, "the rebound", &said)
			if g.coarse.grew do coarse_ready(g)
			g.left -= ph.years*ph.uplift
			p.left -= ph.years*ph.uplift
			g.coarse.steps += 1
			step += 1
		}
	}
}
