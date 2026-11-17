package main

import "base:runtime"
import "core:math"
import "core:math/linalg"

// Walking ground (docs/adr/0009): where a dwarf can stand in the block world, which standing places
// are joined, and the way from one to another.
//
// The ground is the blocks the generator gives with the session's edits laid over them, a chunk at a
// time (gen_columns, build_volume), the same blocks the player walks on. A chunk's blocks are read
// once into a patch: every floor in it, a block of ground with two of air over it under no more water
// than a dwarf wades, and for each floor the steps that leave it, level or up or down one block, to
// the eight sides. The blocks are then let go. A patch's floors that are joined by steps inside it
// are a room; open ground is one room to a chunk, and a ledge, a boulder's top or the far bank of a
// deep pool is a room of its own.
//
// A way is found in two searches. The first is over rooms, from the walker's to the goal's, making
// patches as it goes: it says whether a way exists, and which rooms it runs through, without looking
// at a single floor between. This is what Dwarf Fortress keeps connected ground for
// (interesting-world/notes/df-rimworld-ideas.md): it cannot be kept for a whole island here, where
// ground is made only when asked for, so it is kept room by room and joined on the way. The second
// search is over the floors of those rooms alone, by the cost of crossing ground that the deer's
// trails are laid by (trails.odin).

WADE   :: 0.5    // metres of water a dwarf wades; deeper turns it back (it stands 1.4 m)
FLOORS :: 6      // floors kept in one column at most, from the lowest up
DWARF  :: 0.42   // how many times a walker's 0.6 s a metre (trails.odin) a dwarf takes on flat open ground: 0.25 s, four metres a second, which is RimWorld's 4.6 cells a second on soil (13 ticks a cell and 2 for the soil, of 60)
CLIMB  :: 0.2    // the steepest grade counted against a step: twice as long as the flat, on a stair of blocks as on a hillside
THICK  :: 2.1    // how many times slower the wettest, thickest ground is at most: RimWorld's mud (path cost 14 on a cell of 13 ticks)
WADING :: 4.6    // how much slower a metre of water over a floor makes it: 3.3 times at half a metre, RimWorld's shallow water (path cost 30)
BUILDS :: 400    // patches one search may make before it gives up
FOLLOW :: 24     // rooms the goal's ground is followed through to learn whether it is closed off
ROUND  :: 0.5    // seconds a way is longer for each floor a dwarf stands on: it goes round one where there is room, and by it where there is none

Floor :: struct {
	y:     i16,   // the block its feet are in
	col:   u16,   // its column in the patch, x + CHUNK*z
	links: u16,   // for each of the eight ways (OFFSETS) two bits: 0 no step, 1 down a block, 2 level, 3 up a block
	room:  u16,   // the room of its patch it lies in
	wet:   u8,    // tenths of a metre of water over it
	fall:  [2]i8, // the fall of the floors round it over four blocks east and south, rise over run, in 32nds
	grown: bool,  // it is the ground under a cover of plants, which a walker pushes through
	tall:  bool,  // and a plant taller than a dwarf stands on it
}
Patch :: struct {
	cx, cz: i32,
	base:   i32,                    // its first floor among the walk's
	first:  [CHUNK*CHUNK + 1]u16,   // a column's floors are those from first[col] up to first[col + 1], the lowest first
	room:   i32,                    // its first room among the walk's
	slots, rooms, room_slots: i32,  // floors it has room for among the walk's, its rooms, and the rooms it has room for
	kept:   ^Kept,                  // its blocks, where the hold works this ground
	keep:   bool,                   // they are to be kept when next read
	stale:  bool,                   // a block changed: its floors are read again when next asked for
}
// A chunk's true blocks and what its columns say that floors are read from. A patch the dwarves only
// walk lets them go once its floors are read; one where a block was changed, or a block asked
// after, keeps them, so a changed block is one block written and the floors read again from memory
// (docs/adr/0011): the generator is asked again only when a change falls outside the layers kept
// or a tree is felled.
Kept :: struct {
	blocks:      []Mat,
	y_base, h:   i32,
	level:       [P*P]f32,     // the water standing in each column, by the land
	top:         [P*P]i32,
	grown, tall: [P*P]bool,
	under:       [P*P]Under,   // the rock under the layers kept
}
Room :: struct {
	patch:        ^Patch,
	cells:        i32,
	pace:         f32,            // seconds a dwarf takes over a metre of it, on average
	flood, seen, shut, on: u32,   // the search that last followed it back from a goal, reached it, left it, and laid its way through it
	cost:         f32,
	back, entry:  i32,            // the room it was reached from, and the floor it was entered by
}
Found :: enum u8 { Way, No_Ground, Cut_Off, Too_Far }
Walk :: struct {
	island:  ^Formed,
	patches: map[[2]i32]^Patch,   // by chunk; nil where the chunk lies off the island's region
	floors:  [dynamic]Floor,      // every patch's floors, one patch after another
	owner:   [dynamic]^Patch,     // and the patch of each
	rooms:   [dynamic]Room,
	edits:   [dynamic]Edit,       // the session's changes to the blocks, as the dwarves' world was told of them or made them
	edited:  map[[3]i32]i32,      // and which of them is each block's
	kept:    int,                 // patches whose blocks are kept, and the bytes of them
	kept_bytes: int,
	wasted:  int,                 // floors' places left behind by patches that outgrew them
	going:   []Going,             // on each of the land's cells: what its wetness and plants make of the pace (trails.odin)
	columns: ^Columns,
	// A search's own.
	cost:             [dynamic]f32,
	back:             [dynamic]i32,
	seen, shut, held: [dynamic]u32,   // held: the search in which a floor was one a dwarf stood on (shun)
	shun:             [dynamic][3]i32,   // the floors standing dwarves take up, for the search in hand to go round
	stamp:            u32,
	heap:             Heap,
	budget:           int,    // patches the search in hand may still make
	starved:          bool,   // it wanted one more
	made:             int,    // patches made in all
	roomy:            int,    // places the last walk_spots found clear of each other, of water and of tall plants
}

walk_init :: proc(w: ^Walk, island: ^Formed) {
	bound(island)
	w.island, w.columns = island, new(Columns)
	n := land.n
	w.going = make([]Going, n*n)
	for c in 0..<n*n do w.going[c] = going(c)
}

// Let go what a walk read of its island: one made to ask a question of the ground, and done with (plan.odin).
walk_drop :: proc(w: ^Walk) {
	for _, p in w.patches do if p != nil {
		kept_drop(w, p)
		free(p)
	}
	delete(w.patches); delete(w.floors); delete(w.owner); delete(w.rooms); delete(w.edits); delete(w.edited)
	delete(w.going); delete(w.cost); delete(w.back); delete(w.seen); delete(w.shut); delete(w.held); delete(w.shun)
	free(w.columns)
	w^ = {}
}

// The patch of a chunk, made if it has not been and the search in hand may still make one; its
// floors are read again first if a block of it has changed.
patch_at :: proc(w: ^Walk, cx, cz: i32, make_it := true) -> ^Patch {
	if p, ok := w.patches[{cx, cz}]; ok {
		if p != nil && p.stale do patch_read(w, p)
		return p
	}
	if !make_it do return nil
	// Only the hold's island is walked: a chunk whose blocks, border and trees reach outside its
	// region is the open sea's or another island's.
	f := w.island
	lo, hi := [2]f64{f64(cx), f64(cz)}*CHUNK - 2*CHUNK, [2]f64{f64(cx + 1), f64(cz + 1)}*CHUNK + 2*CHUNK
	o, half := [2]f64{f64(f.island.origin.x), f64(f.island.origin.y)}, f.island.size/2
	if lo.x < o.x - half || lo.y < o.y - half || hi.x > o.x + half || hi.y > o.y + half {
		w.patches[{cx, cz}] = nil
		return nil
	}
	if w.budget <= 0 {
		w.starved = true
		return nil
	}
	w.budget -= 1
	w.made += 1
	p := new(Patch)
	p.cx, p.cz, p.base, p.room = cx, cz, -1, -1
	w.patches[{cx, cz}] = p
	patch_read(w, p)
	return p
}

// Read a patch's floors: from the blocks it keeps, or from the generator's with the edits laid over them.
patch_read :: proc(w: ^Walk, p: ^Patch) {
	context.allocator = runtime.heap_allocator()   // kept blocks are let go by whichever thread next changes them
	k := p.kept
	if k == nil do k = ground_read(w, p.cx, p.cz)
	patch_floors(w, p, k)
	p.stale = false
	if p.kept == nil {
		if p.keep {
			p.kept = k
			w.kept += 1
			w.kept_bytes += size_of(Kept) + len(k.blocks)*size_of(Mat)
		} else {
			delete(k.blocks)
			free(k)
		}
	}
}

// Let a patch's kept blocks go: they are read from the generator again when next asked for.
kept_drop :: proc(w: ^Walk, p: ^Patch) {
	context.allocator = runtime.heap_allocator()
	if p.kept == nil do return
	w.kept -= 1
	w.kept_bytes -= size_of(Kept) + len(p.kept.blocks)*size_of(Mat)
	delete(p.kept.blocks)
	free(p.kept)
	p.kept = nil
}

// A chunk's blocks from the generator with the edits laid over them, and what its columns say.
ground_read :: proc(w: ^Walk, cx, cz: i32) -> ^Kept {
	c := w.columns
	c^ = {}
	gen_columns(0, cx, cz, c)
	edits := make([dynamic]Edit, context.temp_allocator)
	x0, z0 := cx*CHUNK - 1, cz*CHUNK - 1
	for e in w.edits do if edit_reaches(e, x0, z0) do append(&edits, e)
	k := new(Kept)
	k.blocks, k.y_base, k.h = build_volume({0, cx, cz}, c, edits[:])
	bound(w.island)
	for i in 0..<P*P {
		k.level[i] = c.water[i] if f32(c.top[i]) < c.water[i] else NO_WATER   // the land wets only the columns it made wet: a pit dug in a dry bank is dry, as it is in the world drawn (world.odin, build)
		if c.hollow[i][1] > c.hollow[i][0] && f32(c.hollow[i][0]) < SEA_SURFACE do k.level[i] = max(k.level[i], SEA_SURFACE)   // the sea reaches under a roof
		k.top[i], k.under[i] = c.top[i], c.under[i]
		k.grown[i] = is(c.mat[i], COVERS) && c.mat[i] != .Dirt
		k.tall[i] = c.plant[i] > 0 && GROUND_PLANTS[Plant_Kind(c.plant[i] - 1)].tall
	}
	return k
}

// Read a patch's floors, steps and rooms from a chunk's blocks into its places among the walk's.
patch_floors :: proc(w: ^Walk, p: ^Patch, kept: ^Kept) {
	blocks, y_base, h := kept.blocks, kept.y_base, kept.h
	open :: #force_inline proc(blocks: []Mat, h: i32, k: int, y: i32) -> bool { return y >= h || y >= 0 && blocks[k + int(y)*P*P] == .Air }
	// Every column's floors, the border's too: a step off the patch is read from this patch's own blocks.
	ys: [P*P][FLOORS]i16
	wet: [P*P][FLOORS]u8
	count: [P*P]u8
	for k in 0..<P*P {
		level := kept.level[k]
		for y in 0..=h {
			if count[k] == FLOORS do break
			if !open(blocks, h, k, y) || !open(blocks, h, k, y + 1) do continue
			if y > 0 && (blocks[k + int(y - 1)*P*P] == .Air || is(blocks[k + int(y - 1)*P*P], LEAVES)) do continue   // nothing stands on air or on leaves
			deep := level - f32(y + y_base) if y + y_base <= kept.top[k] else 0
			if deep > WADE do continue
			ys[k][count[k]], wet[k][count[k]] = i16(y), u8(math.ceil(max(deep, 0)*10))
			count[k] += 1
		}
	}
	mine := make([dynamic]Floor, context.temp_allocator)
	for col in 0..<CHUNK*CHUNK {
		k := (col/CHUNK + 1)*P + col%CHUNK + 1
		p.first[col] = u16(len(mine))
		for i in 0..<count[k] {
			f := Floor{y = ys[k][i] + i16(y_base), col = u16(col), wet = wet[k][i]}
			y := i32(ys[k][i])
			f.grown = y + y_base == kept.top[k] && kept.grown[k]
			f.tall = y + y_base == kept.top[k] && kept.tall[k]
			// How the floors round it fall, two blocks either way: a single step is a grade of a quarter, a stair of them one.
			level :: proc(ys: ^[P*P][FLOORS]i16, count: ^[P*P]u8, k: int, y: i32) -> f32 {
				best := y
				for j in 0..<count[k] do if d := abs(i32(ys[k][j]) - y); d <= 4 && (best == y || d < abs(best - y)) do best = i32(ys[k][j])
				return f32(best)
			}
			px, pz := col%CHUNK + 1, col/CHUNK + 1
			x0, x1, z0, z1 := max(px - 2, 0), min(px + 2, P - 1), max(pz - 2, 0), min(pz + 2, P - 1)
			f.fall = {i8(clamp(32*(level(&ys, &count, pz*P + x1, y) - level(&ys, &count, pz*P + x0, y))/f32(x1 - x0), -127, 127)),
			          i8(clamp(32*(level(&ys, &count, z1*P + px, y) - level(&ys, &count, z0*P + px, y))/f32(z1 - z0), -127, 127))}
			for o, d in OFFSETS {
				kn := k + o.y*P + o.x
				for j in 0..<count[kn] {
					to := i32(ys[kn][j])
					if abs(to - y) > 1 do continue
					top := max(y, to)
					ok := to <= y || open(blocks, h, k, y + 2)           // room over its head to step up
					ok &&= to >= y || open(blocks, h, kn, y + 1)         // and where it steps down to
					if d >= 4 do for corner in ([2]int{k + o.x, k + o.y*P}) do ok &&= open(blocks, h, corner, top) && open(blocks, h, corner, top + 1)   // no cutting a corner through a block
					if ok do f.links |= u16(to - y + 2) << u16(2*d)
				}
			}
			append(&mine, f)
		}
	}
	p.first[CHUNK*CHUNK] = u16(len(mine))
	// Its rooms: the floors joined by steps inside it.
	rooms := make([dynamic]Room, context.temp_allocator)
	stack := make([dynamic]i32, context.temp_allocator)
	for &f, i in mine do if f.room == 0 {
		append(&rooms, Room{patch = p, back = -1})
		room := &rooms[len(rooms) - 1]
		f.room = u16(len(rooms))
		append(&stack, i32(i))
		for len(stack) > 0 {
			at := mine[pop(&stack)]
			room.cells += 1
			x, z := i32(at.col%CHUNK), i32(at.col/CHUNK)
			for o, d in OFFSETS do if code := i32(at.links >> u16(2*d)) & 3; code != 0 {
				nx, nz := x + i32(o.x), z + i32(o.y)
				if nx < 0 || nz < 0 || nx >= CHUNK || nz >= CHUNK do continue
				col := nz*CHUNK + nx
				for j in p.first[col]..<p.first[col + 1] do if t := &mine[j]; i32(t.y) == i32(at.y) + code - 2 && t.room == 0 {
					t.room = f.room
					append(&stack, i32(j))
				}
			}
		}
	}
	for &f in mine do f.room -= 1
	// Its places among the walk's floors and rooms: those it had, if they still hold it, or new ones with room to grow.
	if n := i32(len(mine)); p.base < 0 || n > p.slots {
		if p.base >= 0 do w.wasted += int(p.slots)
		p.base, p.slots = i32(len(w.floors)), n + n/4 + 64
		for _ in 0..<p.slots {
			append(&w.floors, Floor{})
			append(&w.owner, p)
			append(&w.cost, 0)
			append(&w.back, -1)
			append(&w.seen, 0)
			append(&w.shut, 0)
			append(&w.held, 0)
		}
	}
	copy(w.floors[p.base:], mine[:])
	if n := i32(len(rooms)); p.room < 0 || n > p.room_slots {
		p.room, p.room_slots = i32(len(w.rooms)), n + 8
		for _ in 0..<p.room_slots do append(&w.rooms, Room{patch = p, back = -1})
	}
	p.rooms = i32(len(rooms))
	copy(w.rooms[p.room:], rooms[:])
	for f, i in mine do w.rooms[p.room + i32(f.room)].pace += floor_pace(w, p.base + i32(i))
	for &r in w.rooms[p.room:][:p.rooms] do r.pace /= f32(r.cells)
}

// Whether an edit falls in a chunk's blocks and border, whose low corner is x0, z0: a felled tree's
// stump does wherever its crown reached them.
edit_reaches :: proc(e: Edit, x0, z0: i32) -> bool {
	r := i32(TREE_REACH + 1) if is(e.mat, RINGS) else 0
	return e.x >= x0 - r && e.x < x0 + P + r && e.z >= z0 - r && e.z < z0 + P + r
}

// The block at a place, as the dwarves' world knows it: from a patch that keeps its blocks from
// then on. False off the island's ground.
walk_block :: proc(w: ^Walk, b: [3]i32) -> (m: Mat, ok: bool) {
	p := patch_at(w, b.x >> CHUNK_SHIFT, b.z >> CHUNK_SHIFT)
	if p == nil do return .Air, false
	if p.kept == nil {
		p.keep = true
		patch_read(w, p)
	}
	k := p.kept
	i := int(b.x & (CHUNK - 1) + 1) + int(b.z & (CHUNK - 1) + 1)*P
	if ly := b.y - k.y_base; ly >= k.h do return .Air, true
	else if ly >= 0 do return k.blocks[i + int(ly)*P*P], true
	return crushed(rock_in(f32(b.y) + 0.5, k.under[i], 0), k.under[i]), true
}

// A block has changed. In each patch that reads it, the block is written among the blocks kept
// and the floors are read again when next asked for; a patch that keeps none, or keeps layers the
// block lies outside, or stands under a felled tree's crown, reads the generator again, and keeps.
walk_edit :: proc(w: ^Walk, e: Edit) {
	at := [3]i32{e.x, e.y, e.z}
	if i, ok := w.edited[at]; ok do w.edits[i].mat = e.mat
	else {
		w.edited[at] = i32(len(w.edits))
		append(&w.edits, e)
	}
	r := i32(TREE_REACH + 2) if is(e.mat, RINGS) else 1
	for cz in (e.z - r) >> CHUNK_SHIFT..=(e.z + r) >> CHUNK_SHIFT do for cx in (e.x - r) >> CHUNK_SHIFT..=(e.x + r) >> CHUNK_SHIFT {
		p := w.patches[{cx, cz}] or_else nil
		if p == nil do continue
		p.stale, p.keep = true, true
		k := p.kept
		if k == nil do continue
		if ly := e.y - k.y_base; r == 1 && ly >= 0 && ly < k.h do k.blocks[int(e.x - cx*CHUNK + 1) + int(e.z - cz*CHUNK + 1)*P + int(ly)*P*P] = e.mat
		else do kept_drop(w, p)
	}
}

// The floor at a block, or -1.
walk_floor :: proc(w: ^Walk, x, y, z: i32, make_it := true) -> i32 {
	p := patch_at(w, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT, make_it)
	if p == nil do return -1
	col := (z & (CHUNK - 1))*CHUNK + x & (CHUNK - 1)
	for i in p.first[col]..<p.first[col + 1] do if i32(w.floors[p.base + i32(i)].y) == y do return p.base + i32(i)
	return -1
}

floor_block :: proc(w: ^Walk, f: i32) -> [3]i32 {
	p, at := w.owner[f], w.floors[f]
	return {p.cx*CHUNK + i32(at.col%CHUNK), i32(at.y), p.cz*CHUNK + i32(at.col/CHUNK)}
}

floor_room :: proc(w: ^Walk, f: i32) -> i32 { return w.owner[f].room + i32(w.floors[f].room) }

// The floor a step from a floor leads to, or -1.
floor_step :: proc(w: ^Walk, f: i32, d: int, make_it := true) -> i32 {
	at := w.floors[f]
	code := i32(at.links >> u16(2*d)) & 3
	if code == 0 do return -1
	p, offsets := w.owner[f], OFFSETS
	x, z, y := i32(at.col%CHUNK) + i32(offsets[d].x), i32(at.col/CHUNK) + i32(offsets[d].y), i32(at.y) + code - 2
	if x >= 0 && z >= 0 && x < CHUNK && z < CHUNK {   // in its own patch
		col := z*CHUNK + x
		for i in p.first[col]..<p.first[col + 1] do if i32(w.floors[p.base + i32(i)].y) == y do return p.base + i32(i)
		return -1
	}
	return walk_floor(w, p.cx*CHUNK + x, y, p.cz*CHUNK + z, make_it)
}

// The floor nearest a block within `reach` columns of it, or -1; with `grown`, the nearest dry one under plants;
// with `level`, the nearest that is no higher than the block.
walk_near :: proc(w: ^Walk, x, y, z, reach: i32, grown := false, taken: ^map[[3]i32]int = nil, level := false) -> (best: i32) {
	best = -1
	least := max(i32)
	for r in 0..=reach {
		if 4*r*r > least do break
		for dz in -r..=r do for dx in -r..=r do if max(abs(dx), abs(dz)) == r {
			p := patch_at(w, (x + dx) >> CHUNK_SHIFT, (z + dz) >> CHUNK_SHIFT)
			if p == nil do continue
			col := ((z + dz) & (CHUNK - 1))*CHUNK + (x + dx) & (CHUNK - 1)
			for i in p.first[col]..<p.first[col + 1] {
				f := w.floors[p.base + i32(i)]
				dy := i32(f.y) - y
				if level && dy > 0 do continue   // none higher: the top of a wall is no place to be moved to
				if at := ([3]i32{x + dx, i32(f.y), z + dz}); taken != nil && at in taken^ do continue   // a dwarf stands there
				if s := 4*(dx*dx + dz*dz) + dy*dy; s < least && (f.grown && f.wet == 0 || !grown) do best, least = p.base + i32(i), s
			}
		}
	}
	return
}

// The highest floor of a column.
walk_top :: proc(w: ^Walk, x, z: i32) -> (f: i32, ok: bool) {
	p := patch_at(w, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT)
	if p == nil do return
	col := (z & (CHUNK - 1))*CHUNK + x & (CHUNK - 1)
	return p.base + i32(p.first[col + 1]) - 1, p.first[col + 1] > p.first[col]
}

// Places to stand round a floor, the floor first, no two side by side, none in water or in plants
// over a dwarf's head, in the order a walker spreading out from it would come to them. Where the
// ground joined to the floor has too few such places, as in a passage, a stream or tall grass, the
// rest are taken in water and plants, and then side by side: no two are ever the same floor.
walk_spots :: proc(w: ^Walk, f: i32, out: [][3]i32) -> (n: int) {
	w.stamp += 1
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, f)
	w.seen[f] = w.stamp
	for i := 0; i < len(queue) && n < len(out) && i < 600 + 60*len(out); i += 1 {
		b := floor_block(w, queue[i])
		beside := false
		for o in out[:n] do beside ||= abs(o.x - b.x) <= 1 && abs(o.z - b.z) <= 1
		if at := w.floors[queue[i]]; !beside && at.wet == 0 && !at.tall || i == 0 {
			out[n] = b
			n += 1
		}
		for d in 0..<4 do if t := floor_step(w, queue[i], d); t >= 0 && w.seen[t] != w.stamp {
			w.seen[t] = w.stamp
			append(&queue, t)
		}
	}
	w.roomy = n
	for apart in ([2]bool{true, false}) do for q in queue {
		if n == len(out) do return
		b := floor_block(w, q)
		beside := false
		for o in out[:n] do beside ||= o == b || apart && abs(o.x - b.x) <= 1 && abs(o.z - b.z) <= 1
		if !beside {
			out[n] = b
			n += 1
		}
	}
	return
}

// Seconds a dwarf takes over a step between two floors side by side: the walking cost the trails
// are laid by (Tobler's, trails.odin) at the grade of the floors along the step, slower by the
// wetness of the land's cell each floor lies in and, where plants cover the floor, by that cell's
// plants, or quicker there on a worn trail; and through water, slower the deeper. The land still
// says which way is quicker, but a dwarf is brisk on all of it, as the walkers of the games this
// is measured by are (interesting-world/notes/colony-sim-reference.md, section 5): the grade, the
// plants and the water each slow it by a few times at most. It is the mean of the two floors' paces.
step_seconds :: proc(w: ^Walk, fa, fb: i32) -> f32 {
	a, b := floor_block(w, fa), floor_block(w, fb)
	dir := [2]f32{f32(b.x - a.x), f32(b.z - a.z)}
	d := linalg.length(dir)
	return d*(floor_pace(w, fa, dir/d) + floor_pace(w, fb, dir/d))/2
}

// Seconds a dwarf takes over a metre of a floor, heading a way; with no way given, as it comes on average.
floor_pace :: proc(w: ^Walk, f: i32, dir := [2]f32{0.64, 0.64}) -> f32 {
	at, b, o := w.floors[f], floor_block(w, f), region.origin
	c := land_cell(f64(b.x - o.x) + 0.5, f64(b.z - o.y) + 0.5)
	s := walking(min((abs(f32(at.fall.x)*dir.x) + abs(f32(at.fall.y)*dir.y))/32, CLIMB), 0) if dir != {0.64, 0.64} else walking(min(0.64*math.hypot(f32(at.fall.x), f32(at.fall.y))/32, CLIMB), 0)
	s *= min(w.going[c].wet*(1 if !at.grown || land.community[c] == 255 else 0.7 if trails.worn[c] > 0 else w.going[c].plants), THICK)
	return DWARF*s*(1 + WADING*f32(at.wet)/10)
}
QUICKEST :: DWARF*0.6*0.7   // seconds a metre on the best going there is: flat, dry, on a worn trail
TYPICAL  :: DWARF*2.0       // and on ground as the room search guesses it ahead: it leans toward the goal, and need not find the very best rooms (a guess)

// What the steps over a room's border lead to: the floor left, the floor come to and its room.
Exit :: struct { from, to, room: i32 }
room_exits :: proc(w: ^Walk, r: i32, out: ^[dynamic]Exit, make_it := true) {
	clear(out)
	p := w.rooms[r].patch
	local := u16(r - p.room)
	for col in 0..<CHUNK*CHUNK {
		x, z := col%CHUNK, col/CHUNK
		if x != 0 && z != 0 && x != CHUNK - 1 && z != CHUNK - 1 do continue
		for i in p.first[col]..<p.first[col + 1] {
			f := p.base + i32(i)
			if w.floors[f].room != local do continue
			for o, d in OFFSETS {
				if nx, nz := x + o.x, z + o.y; nx >= 0 && nz >= 0 && nx < CHUNK && nz < CHUNK do continue
				if t := floor_step(w, f, d, make_it); t >= 0 do append(out, Exit{f, t, floor_room(w, t)})
			}
		}
	}
}

// The way from one floor to another, as the blocks to step through, the first the one stood on, and
// the seconds it takes; or why there is none: the goal's ground is closed off from the walker's, or
// the search made as many patches as it may without joining them.
walk_way :: proc(w: ^Walk, from, to: [3]i32, out: ^[dynamic][3]i32, builds := BUILDS) -> (seconds: f32, why: Found) {
	bound(w.island)
	clear(out)
	w.budget, w.starved = builds, false
	a, b := walk_floor(w, from.x, from.y, from.z), walk_floor(w, to.x, to.y, to.z)
	if a < 0 || b < 0 do return 0, .No_Ground
	ra, rb := floor_room(w, a), floor_room(w, b)
	exits := make([dynamic]Exit, context.temp_allocator)
	apart :: proc(a, b: [3]i32) -> f32 { return math.hypot(f32(a.x - b.x), f32(a.z - b.z)) }

	// Is the goal's ground closed off? Followed back from the goal through a few rooms: a ledge or a
	// rock in the sea is found whole at once, and no search is made toward it.
	w.stamp += 1
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, rb)
	w.rooms[rb].flood = w.stamp
	closed, met := true, ra == rb
	for i := 0; i < len(queue) && !met; i += 1 {
		if len(queue) > FOLLOW {
			closed = false
			break
		}
		room_exits(w, queue[i], &exits)
		for e in exits do if w.rooms[e.room].flood != w.stamp {
			w.rooms[e.room].flood = w.stamp
			append(&queue, e.room)
			met ||= e.room == ra
		}
	}
	if closed && !met && !w.starved do return 0, .Cut_Off

	// The rooms the way runs through, the nearest the goal first.
	w.stamp += 1
	laid := w.stamp
	heap_clear(&w.heap)
	w.rooms[ra].seen, w.rooms[ra].cost, w.rooms[ra].back, w.rooms[ra].entry = laid, 0, -1, a
	heap_push(&w.heap, {TYPICAL*apart(from, to), ra})
	found := false
	for w.heap.n > 0 {
		r := heap_pop(&w.heap).c
		if w.rooms[r].shut == laid do continue
		w.rooms[r].shut = laid
		if r == rb {
			found = true
			break
		}
		room_exits(w, r, &exits)
		here := floor_block(w, w.rooms[r].entry)
		for e in exits {
			g := w.rooms[r].cost + w.rooms[r].pace*(apart(here, floor_block(w, e.from)) + 1)
			if t := &w.rooms[e.room]; t.seen != laid || g < t.cost {
				t.seen, t.cost, t.back, t.entry = laid, g, r, e.to
				heap_push(&w.heap, {g + TYPICAL*apart(floor_block(w, e.to), to), e.room})
			}
		}
	}
	if !found do return 0, .Too_Far if w.starved else .Cut_Off
	// And the rooms beside them that are known already, so a way along a chunk's edge is not held to one side of it.
	for r := rb; r >= 0; r = w.rooms[r].back do w.rooms[r].on = laid
	for r := rb; r >= 0; r = w.rooms[r].back {
		room_exits(w, r, &exits, false)
		for e in exits do w.rooms[e.room].on = laid
	}

	// The floors of those rooms, by the cost of each step.
	w.stamp += 1
	for s in w.shun do if f := walk_floor(w, s.x, s.y, s.z, false); f >= 0 do w.held[f] = w.stamp
	heap_clear(&w.heap)
	w.seen[a], w.cost[a], w.back[a] = w.stamp, 0, -1
	heap_push(&w.heap, {QUICKEST*apart(from, to), a})
	for w.heap.n > 0 {
		f := heap_pop(&w.heap).c
		if w.shut[f] == w.stamp do continue
		w.shut[f] = w.stamp
		if f == b do break
		for d in 0..<8 {
			t := floor_step(w, f, d, false)
			if t < 0 || w.shut[t] == w.stamp || w.rooms[floor_room(w, t)].on != laid do continue
			next := floor_block(w, t)
			g := w.cost[f] + step_seconds(w, f, t) + (ROUND if w.held[t] == w.stamp && t != b else 0)
			if w.seen[t] != w.stamp || g < w.cost[t] {
				w.seen[t], w.cost[t], w.back[t] = w.stamp, g, f
				heap_push(&w.heap, {g + QUICKEST*apart(next, to), t})
			}
		}
	}
	if w.shut[b] != w.stamp do return 0, .Cut_Off   // not reached: the rooms were joined, so this is not come to
	for f := b; f >= 0; f = w.back[f] do append(out, floor_block(w, f))
	for i in 0..<len(out)/2 do out[i], out[len(out) - 1 - i] = out[len(out) - 1 - i], out[i]
	return w.cost[b], .Way
}
