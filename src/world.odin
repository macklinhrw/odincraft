package main

import "core:math"
import "core:os"
import "core:sync"
import "core:thread"
import sdl "vendor:sdl3"

// The world the player is standing in: rings of chunks around the camera, one ring per
// level of detail. A chunk at level L has cells of 2^L metres, so each ring reaches twice
// as far as the one inside it with the same number of chunks. Chunks are built on worker
// threads from the generator and the player's edits; the frame thread only uploads them.
// The rings reach about 256 m at the nearest level and 65 km at the farthest, where the round
// world has taken land of a few hundred metres under the horizon (drawn, shaders.metal).

LEVELS :: 9   // cells of 1 m to 256 m
RADIUS :: 8   // chunks kept on each side of the camera, per level

Key :: struct { level, x, z: i32 }

Edit :: struct { x, y, z: i32, mat: Mat }

Chunk :: struct {
	key:                Key,
	ready:              bool,          // has a mesh, possibly empty
	building, dirty:    bool,
	buffer:             ^sdl.GPUBuffer,
	ranges:             [6][4][2]u32,  // first quad and count for each facing (+X to -Z) and part (by_face, mesh.odin)
	y_base, y_lo, y_hi: i32,           // mesh origin and vertical extent, metres
	blocks:             []Mat,         // level 0 only: the block volume, for collision and edits
	h:                  i32,           // layers in blocks
	water:              ^sdl.GPUBuffer, // level 0 only: the water surface, built in water.odin
	water_count:        u32,
	calm:               bool,          // level 0 only: its water is calm open sea, drawn as one quad (water_calm)
	plants:             []Quad,        // level 0 only: the ground plants (plants.odin), all of them
	plant_buf:          ^sdl.GPUBuffer, // and those drawn: all but any the water has drowned
	plant_count:        u32,
	drowned:            int,
}

Job :: struct { key: Key, edits: []Edit, urgent: bool }

Built :: struct {
	key:                Key,
	quads, plants:      []Quad,
	ranges:             [6][4][2]u32,
	y_base, y_lo, y_hi: i32,
	blocks:             []Mat,
	h:                  i32,
	floor, hold:        []f32,         // level 0 only, per column: top of the ground, and the land's water level
	sea, still, roof:   []bool,        // the sea; a lake or pond, whose water is all there is of it; under a roof
}

World :: struct {
	chunks:  map[Key]^Chunk,
	edits:   map[Key][dynamic]Edit,   // by level-0 chunk
	dirty:   [dynamic]Key,
	center:  [LEVELS][2]i32,          // chunk under the camera at each level
	finest:  i32,                     // the finest level any ground is near enough to need
	sited:   [3]f64,                  // where the camera was when that was last worked out
	started: bool,
	islands: int,                     // islands formed when the rings were last filled: a chunk over one not yet formed waits for it
	behind:  bool,                    // the rings moved while a worker held the queue: they are filled next frame
	backlog: int,                     // work queued, building or waiting for upload, when last counted
	water:   Water,

	// The frame thread only tries this lock: a worker holds it for moments, but a worker that other
	// programs' threads hold off the processor while it has it must not hold up a frame. What finds
	// it held waits for the next frame.
	mutex:   sync.Mutex,              // guards everything below
	wake:    sync.Cond,
	pending: [dynamic]Job,
	done:    [dynamic]Built,
	focus:   [LEVELS][2]i32,
	active:  int,                     // jobs being built right now
	quit:    bool,
	threads: [dynamic]^thread.Thread,
}

world_init :: proc(w: ^World) {
	// Leave the efficiency cores and the frame thread alone.
	for _ in 0..<max(2, os.get_processor_core_count()*5/8) {
		append(&w.threads, thread.create_and_start_with_poly_data(w, worker))
	}
}

world_destroy :: proc(w: ^World) {
	sync.lock(&w.mutex)
	w.quit = true
	sync.unlock(&w.mutex)
	sync.cond_broadcast(&w.wake)
	for t in w.threads do thread.join(t)
}

// ---- building, on worker threads ----------------------------------------------------------

worker :: proc(w: ^World) {
	bind(home)   // so a chunk at the open sea has an island to ask, which answers nothing there
	for {
		sync.lock(&w.mutex)
		for len(w.pending) == 0 && !w.quit do sync.cond_wait(&w.wake, &w.mutex)
		if w.quit {
			sync.unlock(&w.mutex)
			return
		}
		// Nearest first, measured in chunks, so every level fills outward together. Edits jump the queue.
		best, best_cost := 0, max(i32)
		for job, i in w.pending {
			f := w.focus[job.key.level]
			cost := max(abs(job.key.x - f.x), abs(job.key.z - f.y))*LEVELS - job.key.level
			if job.urgent do cost = -1
			if cost < best_cost do best, best_cost = i, cost
		}
		job := w.pending[best]
		unordered_remove(&w.pending, best)
		w.active += 1
		sync.unlock(&w.mutex)

		built := build(job)

		sync.lock(&w.mutex)
		append(&w.done, built)
		w.active -= 1
		sync.unlock(&w.mutex)
	}
}

build :: proc(job: Job) -> (b: Built) {
	defer delete(job.edits)
	b.key = job.key
	if open_sea(job.key) do return   // no faces to make
	c := new(Columns)
	defer free(c)
	defer free_all(context.temp_allocator)
	gen_columns(job.key.level, job.key.x, job.key.z, c)

	quads := make([dynamic]Quad, 0, 4096)
	plants: [dynamic]Quad
	parts: [4][2]u32
	if job.key.level == 0 {
		b.blocks, b.y_base, b.h = build_volume(job.key, c, job.edits)
		outer, inner := mesh_volume(b.blocks, b.h, c, &quads, &plants, {job.key.x*CHUNK - region.origin.x, b.y_base, job.key.z*CHUNK - region.origin.y})
		all := u32(len(quads))
		parts[0], parts[1], parts[2] = {0, all - outer - inner}, {all - outer - inner, outer}, {all - inner, inner}   // at this level: the solid faces, the crowns' outer faces, the faces within them
		b.y_lo, b.y_hi = b.y_base, b.y_base + b.h
		// What the water needs to know about each column.
		b.floor, b.hold, b.sea, b.still, b.roof = make([]f32, CHUNK*CHUNK), make([]f32, CHUNK*CHUNK), make([]bool, CHUNK*CHUNK), make([]bool, CHUNK*CHUNK), make([]bool, CHUNK*CHUNK)
		for z in 0..<i32(CHUNK) {
			for x in 0..<i32(CHUNK) {
				i, k := z*CHUNK + x, (z + 1)*P + x + 1
				b.floor[i], b.roof[i] = column_floor(b.blocks, b.h, b.y_base, x, z)
				b.sea[i] = f32(c.top[k]) < SEA_SURFACE || (c.hollow[k][1] > c.hollow[k][0] && f32(c.hollow[k][0]) < SEA_SURFACE)   // judged on the land as generated, so digging inland does not make sea; it reaches under a roof
				// The land supplies water only to columns it made wet. A dry bank beside the
				// river stays dry when it is dug, until something lets the water in.
				b.hold[i] = SEA_SURFACE if b.sea[i] else c.water[k] if f32(c.top[k]) < c.water[k] else NO_WATER
				if b.hold[i] != NO_WATER && !b.sea[i] do _, b.still[i], _ = lake_near(f64(job.key.x*CHUNK + x - region.origin.x) + 0.5, f64(job.key.z*CHUNK + z - region.origin.y) + 0.5)
				b.y_hi = max(b.y_hi, i32(math.ceil(b.hold[i])))   // so the chunk is drawn, and its water, wherever its water is in view
			}
		}
	} else {
		s := i32(1) << u32(job.key.level)
		b.y_base = c.lo - 2*s - 1
		mesh_columns(c, s, b.y_base, &quads, &parts)
		b.y_lo, b.y_hi = b.y_base, c.hi
	}
	b.ranges = by_face(quads[:], parts)
	b.quads, b.plants = quads[:], plants[:]
	return
}

// The block volume for a nearest-level chunk: the generated world, then the player's edits.
build_volume :: proc(key: Key, c: ^Columns, edits: []Edit) -> (blocks: []Mat, y_base, h: i32) {
	lo, hi := max(i32), min(i32)
	for e in edits {
		lo = min(lo, e.y)
		hi = max(hi, e.y + 1)
	}
	blocks, y_base, h = gen_volume(key.x, key.z, c, lo, hi)
	ox, oz := key.x*CHUNK - 1, key.z*CHUNK - 1
	for e in edits {
		blocks[int(e.x - ox) + int(e.z - oz)*P + int(e.y - y_base)*P*P] = e.mat
	}
	return
}

// ---- streaming, on the frame thread ---------------------------------------------------------

in_ring :: proc(w: ^World, key: Key, radius: i32) -> bool {
	c := w.center[key.level]
	return abs(key.x - c.x) <= radius && abs(key.z - c.y) <= radius
}

// How far it is from a point to the nearest ground or sea, crowns and all: the land tried at eighty-one
// points round it at each of five spacings, the wider ones allowed more relief between points.
clearance :: proc(p: [3]f64) -> (clear: f64) {
	clear = max(f64)
	for l in 0..<5 {
		step := f64(i32(CHUNK*2) << u32(l))
		for j in -4..=4 do for i in -4..=4 {
			d := [2]f64{f64(i), f64(j)}*step
			top := f64(max(height_in_world(p.x + d.x, p.z + d.y, step), SEA_SURFACE)) + 30 + step/4
			clear = min(clear, math.sqrt(d.x*d.x + d.y*d.y + math.pow(max(p.y - top, 0), 2)))
		}
	}
	return
}

world_update :: proc(w: ^World, dev: ^sdl.GPUDevice, cam: [3]f64) {
	moved := !w.started || w.behind
	// A level's ring reaches RADIUS chunks from the camera, and beyond that the next level is fine
	// enough. From high in the air no ground is that near, so the level is not built or drawn at all;
	// it comes back a fifth of its reach sooner than it went, so hovering at the height costs nothing.
	if !w.started || abs(cam.x - w.sited.x) + abs(cam.y - w.sited.y) + abs(cam.z - w.sited.z) > 8 {
		w.sited = cam
		clear := clearance(cam)
		finest := w.finest
		for finest < LEVELS - 2 && clear > f64(i32(RADIUS*CHUNK) << u32(finest))*1.2 do finest += 1
		for finest > 0 && clear < f64(i32(RADIUS*CHUNK) << u32(finest - 1)) do finest -= 1
		if finest != w.finest do moved = true
		w.finest = finest
	}
	for l in 0..<LEVELS {
		size := f64(i32(CHUNK) << u32(l))
		c := [2]i32{i32(math.floor(cam.x/size)), i32(math.floor(cam.z/size))}
		if c != w.center[l] do moved = true
		w.center[l] = c
	}
	islands := 0
	for &f in formed do islands += int(is_formed(&f))
	if islands != w.islands do moved = true
	w.islands = islands

	if moved {
		w.started = true
		// Chunks get one chunk of slack before they are dropped, so pacing back and forth
		// across a boundary costs nothing.
		gone := make([dynamic]Key, context.temp_allocator)
		for key in w.chunks do if !in_ring(w, key, RADIUS + 1) || key.level < w.finest do append(&gone, key)
		for key in gone {
			c := w.chunks[key]
			if c.buffer != nil do sdl.ReleaseGPUBuffer(dev, c.buffer)
			if key.level == 0 do water_unload(&w.water, dev, c)
			if c.plant_buf != nil do sdl.ReleaseGPUBuffer(dev, c.plant_buf)
			delete(c.plants)
			delete(c.blocks)
			free(c)
			delete_key(&w.chunks, key)
		}

		// The queue: what has left the rings leaves it, and what has come into them joins it.
		if w.behind = !sync.try_lock(&w.mutex); !w.behind {
			w.focus = w.center
			for i := len(w.pending) - 1; i >= 0; i -= 1 {
				if !in_ring(w, w.pending[i].key, RADIUS + 1) || w.pending[i].key.level < w.finest {
					delete(w.pending[i].edits)
					unordered_remove(&w.pending, i)
				}
			}
			for l in w.finest..<i32(LEVELS) {
				for dz in -i32(RADIUS)..=RADIUS {
					for dx in -i32(RADIUS)..=RADIUS {
						key := Key{l, w.center[l].x + dx, w.center[l].y + dz}
						if key in w.chunks || waits(key) do continue
						c := new(Chunk)
						c.key = key
						c.building = true
						w.chunks[key] = c
						append(&w.pending, Job{key = key, edits = edits_near(w, key)})
					}
				}
			}
			sync.unlock(&w.mutex)
			sync.cond_broadcast(&w.wake)
		}
	}

	// Rebuild chunks the player has changed. The old mesh stays up until the new one lands.
	for i := len(w.dirty) - 1; i >= 0; i -= 1 {
		c := w.chunks[w.dirty[i]] or_else nil
		if c != nil && c.building do continue
		if c != nil {
			if !sync.try_lock(&w.mutex) do continue
			c.building, c.dirty = true, false
			append(&w.pending, Job{key = c.key, edits = edits_near(w, c.key), urgent = true})
			sync.unlock(&w.mutex)
			sync.cond_signal(&w.wake)
		}
		unordered_remove(&w.dirty, i)
	}

	// Take finished chunks, a bounded amount per frame so a burst cannot cost a frame.
	UPLOAD_BUDGET :: 3 << 20
	batch := make([dynamic]Built, context.temp_allocator)
	bytes := 0
	if !sync.try_lock(&w.mutex) do return
	for len(w.done) > 0 && bytes < UPLOAD_BUDGET {
		b := w.done[0]
		ordered_remove(&w.done, 0)
		append(&batch, b)
		bytes += (len(b.quads) + len(b.plants))*size_of(Quad)
	}
	sync.unlock(&w.mutex)
	if len(batch) == 0 do return

	cmd := sdl.AcquireGPUCommandBuffer(dev)
	staging: ^sdl.GPUTransferBuffer
	mapped: [^]u8
	if bytes > 0 {
		staging = sdl.CreateGPUTransferBuffer(dev, {usage = .UPLOAD, size = u32(bytes)})
		mapped = cast([^]u8)sdl.MapGPUTransferBuffer(dev, staging, false)
		at := 0
		for b in batch {
			for list in ([2][]Quad{b.quads, b.plants}) {
				n := len(list)*size_of(Quad)
				if n > 0 do copy(mapped[at:at + n], (cast([^]u8)raw_data(list))[:n])
				at += n
			}
		}
		sdl.UnmapGPUTransferBuffer(dev, staging)
	}
	pass := sdl.BeginGPUCopyPass(cmd)
	at := u32(0)
	for &b in batch {
		n, plants := u32(len(b.quads)*size_of(Quad)), u32(len(b.plants)*size_of(Quad))
		c := w.chunks[b.key] or_else nil
		defer {
			delete(b.floor)
			delete(b.hold)
			delete(b.sea)
			delete(b.still)
			delete(b.roof)
		}
		if c == nil {   // left the ring while it was being built
			delete(b.blocks)
			delete(b.plants)
		} else {
			if c.buffer != nil do sdl.ReleaseGPUBuffer(dev, c.buffer)
			delete(c.blocks)
			c.buffer = nil
			if n > 0 {
				c.buffer = sdl.CreateGPUBuffer(dev, {usage = {.VERTEX}, size = n})
				sdl.UploadToGPUBuffer(pass, {staging, at}, {c.buffer, 0, n}, false)
			}
			c.ranges, c.y_base, c.y_lo, c.y_hi = b.ranges, b.y_base, b.y_lo, b.y_hi
			c.blocks, c.h = b.blocks, b.h
			c.ready, c.building = true, false
			if b.key.level == 0 {
				// All its plants, as the generator left them clear of its water. If the simulated water
				// has risen over any, the next rebuild of its surface takes them out (plants_drowned).
				water_load(&w.water, c, &b)
				if c.plant_buf != nil do sdl.ReleaseGPUBuffer(dev, c.plant_buf)
				delete(c.plants)
				c.plants, c.plant_buf, c.plant_count, c.drowned = b.plants, nil, u32(len(b.plants)), 0
				if plants > 0 {
					c.plant_buf = sdl.CreateGPUBuffer(dev, {usage = {.VERTEX}, size = plants})
					sdl.UploadToGPUBuffer(pass, {staging, at + n}, {c.plant_buf, 0, plants}, false)
				}
			}
		}
		at += n + plants
		delete(b.quads)
	}
	sdl.EndGPUCopyPass(pass)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
	if staging != nil do sdl.ReleaseGPUTransferBuffer(dev, staging)
}

// Whether a chunk, with its border and the trees reaching into it, lies over an island not yet
// formed. It is not built until the island is, and nothing is drawn there meanwhile.
waits :: proc(key: Key) -> bool {
	s := f64(i32(CHUNK) << u32(key.level))
	lo, hi := [2]f64{f64(key.x), f64(key.z)}*s - s/CHUNK - TREE_REACH, [2]f64{f64(key.x + 1), f64(key.z + 1)}*s + s/CHUNK + TREE_REACH
	for &f in formed {
		o, h := [2]f64{f64(f.island.origin.x), f64(f.island.origin.y)}, f.island.size/2
		if !is_formed(&f) && lo.x < o.x + h && hi.x > o.x - h && lo.y < o.y + h && hi.y > o.y - h do return true
	}
	return false
}

// Work still queued, building or waiting for upload; at least one while a worker holds the queue.
world_backlog :: proc(w: ^World) -> int {
	if !sync.try_lock(&w.mutex) do return max(w.backlog, 1)
	w.backlog = len(w.pending) + w.active + len(w.done)
	sync.unlock(&w.mutex)
	return w.backlog
}

// ---- blocks ---------------------------------------------------------------------------------

// The block at a world position. `known` is false where the near volume is not loaded yet.
world_block :: proc(w: ^World, x, y, z: i32) -> (m: Mat, known: bool) {
	c := w.chunks[Key{0, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT}] or_else nil
	if c == nil || !c.ready do return .Stone, false
	ly := y - c.y_base
	if ly < 0 do return .Stone, true
	if ly >= c.h do return .Air, true
	lx, lz := x & (CHUNK - 1), z & (CHUNK - 1)
	return c.blocks[int(lx + 1) + int(lz + 1)*P + int(ly)*P*P], true
}

// Change one block. The edit is remembered for as long as the program runs.
world_set :: proc(w: ^World, x, y, z: i32, m: Mat) {
	key := Key{0, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT}
	if key not_in w.edits do w.edits[key] = make([dynamic]Edit)
	list := &w.edits[key]
	replaced := false
	for &e in list {
		if e.x == x && e.y == y && e.z == z {
			e.mat = m
			replaced = true
		}
	}
	if !replaced do append(list, Edit{x, y, z, m})
	hold_block(x, y, z, m)   // the dwarves walk the same blocks

	// Collision should not wait for the rebuild.
	if c := w.chunks[key] or_else nil; c != nil && c.ready {
		if ly := y - c.y_base; ly >= 0 && ly < c.h {
			c.blocks[int(x & (CHUNK - 1) + 1) + int(z & (CHUNK - 1) + 1)*P + int(ly)*P*P] = m
			water_refloor(&w.water, x, z)
		}
	}
	// This chunk, and any neighbour whose border includes the block.
	for dz in i32(-1)..=1 {
		for dx in i32(-1)..=1 {
			k := Key{0, (x + dx) >> CHUNK_SHIFT, (z + dz) >> CHUNK_SHIFT}
			if c := w.chunks[k] or_else nil; c != nil && !c.dirty {
				c.dirty = true
				append(&w.dirty, k)
			}
		}
	}
}

// The edits that fall inside a level-0 chunk or its border. The caller owns the copy.
edits_near :: proc(w: ^World, key: Key) -> []Edit {
	if key.level != 0 || len(w.edits) == 0 do return nil
	out: [dynamic]Edit
	x0, z0 := key.x*CHUNK - 1, key.z*CHUNK - 1
	for dz in i32(-1)..=1 {
		for dx in i32(-1)..=1 {
			list := w.edits[Key{0, key.x + dx, key.z + dz}] or_else nil
			for e in list {
				if e.x >= x0 && e.x < x0 + P && e.z >= z0 && e.z < z0 + P do append(&out, e)
			}
		}
	}
	return out[:]
}
