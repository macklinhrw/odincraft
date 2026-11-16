package main

import "core:math"
import "core:math/linalg"

// Walking ground (docs/adr/0007): where a dwarf can stand in the block world, which standing places
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
DWARF  :: 1.25   // how many times longer than a person a dwarf takes over the same ground (a guess: its stride is shorter)
CLIMB  :: 0.6    // the steepest grade counted against a step: a stair of blocks is climbed faster than a bare slope as steep (a guess)
BUILDS :: 400    // patches one search may make before it gives up
FOLLOW :: 24     // rooms the goal's ground is followed through to learn whether it is closed off

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
	edits:   [dynamic]Edit,       // the session's changes to the blocks, as the dwarves' world was told of them
	going:   []Going,             // on each of the land's cells: what its wetness and plants make of the pace (trails.odin)
	columns: ^Columns,
	// A search's own.
	cost:             [dynamic]f32,
	back:             [dynamic]i32,
	seen, shut:       [dynamic]u32,
	stamp:            u32,
	heap:             Heap,
	budget:           int,    // patches the search in hand may still make
	starved:          bool,   // it wanted one more
	made:             int,    // patches made in all
}

walk_init :: proc(w: ^Walk, island: ^Formed) {
	bound(island)
	w.island, w.columns = island, new(Columns)
	n := land.n
	w.going = make([]Going, n*n)
	for c in 0..<n*n do w.going[c] = going(c)
}

// The patch of a chunk, made if it has not been and the search in hand may still make one.
patch_at :: proc(w: ^Walk, cx, cz: i32, make_it := true) -> ^Patch {
	if p, ok := w.patches[{cx, cz}]; ok do return p
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
	p := patch_make(w, cx, cz)
	w.patches[{cx, cz}] = p
	return p
}

patch_make :: proc(w: ^Walk, cx, cz: i32) -> ^Patch {
	c := w.columns
	c^ = {}
	gen_columns(0, cx, cz, c)
	edits := make([dynamic]Edit, context.temp_allocator)
	x0, z0 := cx*CHUNK - 1, cz*CHUNK - 1
	for e in w.edits do if e.x >= x0 && e.x < x0 + P && e.z >= z0 && e.z < z0 + P do append(&edits, e)
	blocks, y_base, h := build_volume({0, cx, cz}, c, edits[:])
	defer delete(blocks)
	bound(w.island)

	open :: #force_inline proc(blocks: []Mat, h: i32, k: int, y: i32) -> bool { return y >= h || y >= 0 && blocks[k + int(y)*P*P] == .Air }
	// Every column's floors, the border's too: a step off the patch is read from this patch's own blocks.
	ys: [P*P][FLOORS]i16
	wet: [P*P][FLOORS]u8
	count: [P*P]u8
	for k in 0..<P*P {
		level := c.water[k]
		if c.hollow[k][1] > c.hollow[k][0] && f32(c.hollow[k][0]) < SEA_SURFACE do level = max(level, SEA_SURFACE)   // the sea reaches under a roof
		for y in 0..=h {
			if count[k] == FLOORS do break
			if !open(blocks, h, k, y) || !open(blocks, h, k, y + 1) do continue
			if y > 0 && (blocks[k + int(y - 1)*P*P] == .Air || is(blocks[k + int(y - 1)*P*P], LEAVES)) do continue   // nothing stands on air or on leaves
			deep := level - f32(y + y_base) if y + y_base <= c.top[k] else 0
			if deep > WADE do continue
			ys[k][count[k]], wet[k][count[k]] = i16(y), u8(math.ceil(max(deep, 0)*10))
			count[k] += 1
		}
	}
	p := new(Patch)
	p.cx, p.cz, p.base, p.room = cx, cz, i32(len(w.floors)), i32(len(w.rooms))
	for col in 0..<CHUNK*CHUNK {
		k := (col/CHUNK + 1)*P + col%CHUNK + 1
		p.first[col] = u16(i32(len(w.floors)) - p.base)
		for i in 0..<count[k] {
			f := Floor{y = ys[k][i] + i16(y_base), col = u16(col), wet = wet[k][i]}
			y := i32(ys[k][i])
			f.grown = y + y_base == c.top[k] && is(c.mat[k], COVERS) && c.mat[k] != .Dirt
			f.tall = y + y_base == c.top[k] && c.plant[k] > 0 && GROUND_PLANTS[Plant_Kind(c.plant[k] - 1)].tall
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
			append(&w.floors, f)
			append(&w.owner, p)
		}
	}
	p.first[CHUNK*CHUNK] = u16(i32(len(w.floors)) - p.base)
	// Its rooms: the floors joined by steps inside it.
	mine := w.floors[p.base:]
	stack := make([dynamic]i32, context.temp_allocator)
	for &f, i in mine do if f.room == 0 {
		append(&w.rooms, Room{patch = p, back = -1})
		room := &w.rooms[len(w.rooms) - 1]
		f.room = u16(i32(len(w.rooms)) - p.room)
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
	for f, i in mine do w.rooms[p.room + i32(f.room)].pace += floor_pace(w, p.base + i32(i))
	for &r in w.rooms[p.room:] do r.pace /= f32(r.cells)
	for len(w.cost) < len(w.floors) {
		append(&w.cost, 0)
		append(&w.back, -1)
		append(&w.seen, 0)
		append(&w.shut, 0)
	}
	return p
}

// A block has changed: the patches that read it are forgotten, and made again when next asked for.
walk_edit :: proc(w: ^Walk, e: Edit) {
	replaced := false
	for &o in w.edits do if o.x == e.x && o.y == e.y && o.z == e.z do o.mat, replaced = e.mat, true
	if !replaced do append(&w.edits, e)
	for dz in i32(-1)..=1 do for dx in i32(-1)..=1 {
		key := [2]i32{(e.x + dx) >> CHUNK_SHIFT, (e.z + dz) >> CHUNK_SHIFT}
		if p, ok := w.patches[key]; ok && p != nil do delete_key(&w.patches, key)
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

// The floor nearest a block within `reach` columns of it, or -1; with `grown`, the nearest dry one under plants.
walk_near :: proc(w: ^Walk, x, y, z, reach: i32, grown := false) -> (best: i32) {
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
// over a dwarf's head, in the order a walker spreading out from it would come to them.
walk_spots :: proc(w: ^Walk, f: i32, out: [][3]i32) -> (n: int) {
	w.stamp += 1
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, f)
	w.seen[f] = w.stamp
	for i := 0; i < len(queue) && n < len(out) && i < 600; i += 1 {
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
	return
}

// Seconds a dwarf takes over a step between two floors side by side: the walking cost the trails
// are laid by (Tobler's, trails.odin) at the grade of the floors along the step, slower by the
// wetness of the land's cell each floor lies in and, where plants cover the floor, by that cell's
// plants, or quicker there on a worn trail; and through water, the time to wade it, much slower the
// deeper, as a stream is costed there. It is the mean of the two floors' paces.
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
	s *= w.going[c].wet*(1 if !at.grown || land.community[c] == 255 else 0.7 if trails.worn[c] > 0 else w.going[c].plants)
	return DWARF*(s + 100*(f32(at.wet)/10)*(f32(at.wet)/10))
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
walk_way :: proc(w: ^Walk, from, to: [3]i32, out: ^[dynamic][3]i32) -> (seconds: f32, why: Found) {
	bound(w.island)
	clear(out)
	w.budget, w.starved = BUILDS, false
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
			g := w.cost[f] + step_seconds(w, f, t)
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
