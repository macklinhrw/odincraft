package main

import "core:math"
import sdl "vendor:sdl3"

// Water near the player. Every column of the block volume holds a depth of water standing
// on its ground. Each step, water crosses each edge from the higher surface to the lower,
// faster the bigger the drop, so it runs downhill, settles level in hollows and pours
// into anything dug beside it.
//
// The land's own water is where it comes from. A column the generator says is river is
// topped up to the river's level whenever it falls short, and a sea column is held at sea
// level both ways. So a breached bank lets the river out and the river keeps coming,
// while water with no supply behind it slowly sinks away.
//
// The columns live in a square window that wraps around: a column's place in the arrays
// is its world position modulo the window, so the window follows the player without any
// data moving. Chunks that are loaded own their part of it; the rest is wall.

WATER_N    :: 1024              // columns across the window
WATER_SPAN :: WATER_N/CHUNK     // chunks across the window
WATER_STEP :: 1.0/30            // seconds per step
RUN        :: 5.0               // metres a second water runs down a drop of one in one
DRY_UP     :: 0.004             // metres a second a puddle with no supply sinks away
SHOWN      :: 0.015             // water shallower than this is not drawn
WALL       :: 1e6

// One piece of water surface: four corners, and at each corner how the water is moving,
// how deep it is and how broken it is.
Water_Quad :: struct {
	p:    [4][3]f32,   // x and z from the chunk's corner, y in the world
	more: [4][4]f32,   // flow x and z in metres a second, depth, and 0 for level water to 1 for falling
}
#assert(size_of(Water_Quad) == 112)

Water :: struct {
	floor:          []f32,    // top of the ground in each column; WALL where no chunk is loaded
	depth:          []f32,
	hold:           []f32,    // level of the river or sea the generator put here, or NO_WATER
	sea:            []bool,
	flow_x, flow_z: []f32,    // depth that crossed to the +x and +z neighbour in the last step
	before, shown:  []f32,    // depth a step ago, and when the surface was last built
	chunks:         [WATER_SPAN*WATER_SPAN]^Chunk,   // the chunk loaded in each square of the window
	awake:          [WATER_SPAN*WATER_SPAN]bool,     // something is still moving here
	wet:            [WATER_SPAN*WATER_SPAN]bool,     // there is water here
	stale:          [WATER_SPAN*WATER_SPAN]bool,     // the surface no longer matches the water
	unbuilt:        [WATER_SPAN*WATER_SPAN]bool,     // loaded, and its surface has not been built yet
	turn:           int,      // where the next round of rebuilding starts
	behind:         f64,      // seconds of stepping owed
	mask:           ^sdl.GPUTexture,   // which squares have simulated water drawn, for the far water to give way to
	mask_stale:     bool,
}

water_cell :: #force_inline proc(x, z: i32) -> int {
	return int(x & (WATER_N - 1)) + int(z & (WATER_N - 1))*WATER_N
}

water_slot :: #force_inline proc(cx, cz: i32) -> int {
	return int(cx & (WATER_SPAN - 1)) + int(cz & (WATER_SPAN - 1))*WATER_SPAN
}

water_init :: proc(wt: ^Water, dev: ^sdl.GPUDevice) {
	n := WATER_N*WATER_N
	wt.floor, wt.depth, wt.hold = make([]f32, n), make([]f32, n), make([]f32, n)
	wt.flow_x, wt.flow_z = make([]f32, n), make([]f32, n)
	wt.before, wt.shown, wt.sea = make([]f32, n), make([]f32, n), make([]bool, n)
	for &f in wt.floor do f = WALL
	wt.mask = sdl.CreateGPUTexture(dev, {
		type = .D2, format = .R8_UNORM, usage = {.SAMPLER},
		width = WATER_SPAN, height = WATER_SPAN, layer_count_or_depth = 1, num_levels = 1,
	})
	wt.mask_stale = true
}

// Top of the ground in a column of a chunk's blocks: the highest block that is not part
// of a tree. Water lies on this, and under any crown.
column_floor :: proc(blocks: []u8, h, y_base, x, z: i32) -> f32 {
	for y := h - 1; y >= 0; y -= 1 {
		m := Mat(blocks[int(x + 1) + int(z + 1)*P + int(y)*P*P])
		if m != .Air && m not_in PLANT_BLOCKS do return f32(y_base + y + 1)
	}
	return f32(y_base)
}

water_wake :: proc(wt: ^Water, cx, cz: i32) {
	for dz in i32(-1)..=1 do for dx in i32(-1)..=1 do wt.awake[water_slot(cx + dx, cz + dz)] = true
}

// Ground moved under a column. Water standing on ground that rose is pushed out.
water_set_floor :: proc(wt: ^Water, i: int, floor: f32) {
	if floor > wt.floor[i] do wt.depth[i] = max(wt.depth[i] - (floor - wt.floor[i]), 0)
	wt.floor[i] = floor
}

// A chunk has arrived, for the first time or rebuilt after an edit.
water_load :: proc(wt: ^Water, c: ^Chunk, b: ^Built) {
	s := water_slot(c.key.x, c.key.z)
	fresh := wt.chunks[s] != c
	wt.chunks[s] = c
	for z in 0..<i32(CHUNK) {
		for x in 0..<i32(CHUNK) {
			i, k := water_cell(c.key.x*CHUNK + x, c.key.z*CHUNK + z), z*CHUNK + x
			if fresh {
				wt.floor[i], wt.hold[i], wt.sea[i] = b.floor[k], b.hold[k], b.sea[k]
				wt.depth[i] = max(b.hold[k] - b.floor[k], 0)
				wt.before[i], wt.shown[i] = wt.depth[i], -1
				wt.flow_x[i], wt.flow_z[i] = 0, 0
			} else {
				water_set_floor(wt, i, b.floor[k])
			}
		}
	}
	wt.stale[s], wt.mask_stale = true, true
	wt.wet[s] = true   // until a step finds otherwise
	if fresh do wt.unbuilt[s] = true
	water_wake(wt, c.key.x, c.key.z)
}

// Chunks whose water has not been drawn yet.
water_backlog :: proc(wt: ^Water) -> (n: int) {
	for u in wt.unbuilt do n += int(u)
	return
}

water_unload :: proc(wt: ^Water, dev: ^sdl.GPUDevice, c: ^Chunk) {
	if c.water != nil do sdl.ReleaseGPUBuffer(dev, c.water)
	s := water_slot(c.key.x, c.key.z)
	if wt.chunks[s] != c do return
	wt.chunks[s], wt.unbuilt[s] = nil, false
	for z in 0..<i32(CHUNK) {
		for x in 0..<i32(CHUNK) {
			i := water_cell(c.key.x*CHUNK + x, c.key.z*CHUNK + z)
			wt.floor[i], wt.depth[i] = WALL, 0
		}
	}
	wt.mask_stale = true
	water_wake(wt, c.key.x, c.key.z)
}

// A block changed at a column: find its ground again.
water_refloor :: proc(wt: ^Water, x, z: i32) {
	cx, cz := x >> CHUNK_SHIFT, z >> CHUNK_SHIFT
	s := water_slot(cx, cz)
	c := wt.chunks[s]
	if c == nil || c.key.x != cx || c.key.z != cz do return
	water_set_floor(wt, water_cell(x, z), column_floor(c.blocks, c.h, c.y_base, x & (CHUNK - 1), z & (CHUNK - 1)))
	wt.stale[s] = true
	water_wake(wt, cx, cz)
}

// Depth of water crossing from column a to column b in one step; negative the other way.
// Only the water above both floors can cross, and never so much that the levels pass
// each other or a column runs dry.
water_cross :: proc(wt: ^Water, a, b: int) -> f32 {
	fa, fb := wt.floor[a], wt.floor[b]
	ha, hb := fa + wt.depth[a], fb + wt.depth[b]
	open := max(ha, hb) - max(fa, fb)
	if open <= 0.001 do return 0
	drop := abs(ha - hb)
	donor := wt.depth[a] if ha > hb else wt.depth[b]
	amount := min(open*min(RUN*math.sqrt(drop), 5)*WATER_STEP, drop/4, donor/4)
	return amount if ha > hb else -amount
}

water_step :: proc(wt: ^Water) {
	// Chunks where something is moving and there is water in reach. Most of the land is
	// dry hillside and is skipped.
	work := make([dynamic]^Chunk, context.temp_allocator)
	for c, s in wt.chunks {
		if c == nil || !wt.awake[s] do continue
		near := false
		for dz in i32(-1)..=1 do for dx in i32(-1)..=1 do near ||= wt.wet[water_slot(c.key.x + dx, c.key.z + dz)]
		if near do append(&work, c)
	}

	// How much crosses each edge, all from the state as it stands; then move it.
	for c in work {
		for z in c.key.z*CHUNK..<(c.key.z + 1)*CHUNK {
			for x in c.key.x*CHUNK..<(c.key.x + 1)*CHUNK {
				i, east, south := water_cell(x, z), water_cell(x + 1, z), water_cell(x, z + 1)
				wet := wt.depth[i] > 0
				wt.flow_x[i] = water_cross(wt, i, east) if wet || wt.depth[east] > 0 else 0
				wt.flow_z[i] = water_cross(wt, i, south) if wet || wt.depth[south] > 0 else 0
			}
		}
	}
	for c in work {
		for z in c.key.z*CHUNK..<(c.key.z + 1)*CHUNK {
			for x in c.key.x*CHUNK..<(c.key.x + 1)*CHUNK {
				i := water_cell(x, z)
				if fx := wt.flow_x[i]; fx != 0 {
					wt.depth[i] -= fx
					wt.depth[water_cell(x + 1, z)] += fx
				}
				if fz := wt.flow_z[i]; fz != 0 {
					wt.depth[i] -= fz
					wt.depth[water_cell(x, z + 1)] += fz
				}
			}
		}
	}

	// Supply and loss, and whether anything is still changing.
	for c in work {
		cx, cz := c.key.x, c.key.z
		west, east := wt.chunks[water_slot(cx - 1, cz)] == nil, wt.chunks[water_slot(cx + 1, cz)] == nil
		north, south := wt.chunks[water_slot(cx, cz - 1)] == nil, wt.chunks[water_slot(cx, cz + 1)] == nil
		change: f32
		redraw, wet := false, false
		for z in i32(0)..<CHUNK {
			for x in i32(0)..<CHUNK {
				i := water_cell(cx*CHUNK + x, cz*CHUNK + z)
				d := wt.depth[i]
				standing := wt.hold[i] - wt.floor[i]   // depth of the land's own water here
				// On the rim of what is loaded, water is whatever the land says: rivers
				// arrive and leave there, and spills drain away.
				rim := (west && x == 0) || (east && x == CHUNK - 1) || (north && z == 0) || (south && z == CHUNK - 1)
				switch {
				case wt.sea[i] || rim: d = max(standing, 0)
				case standing > d:     d = standing
				case standing <= 0 && d > 0:
					d -= DRY_UP*WATER_STEP
					if d < 0.002 do d = 0
				}
				change = max(change, abs(d - wt.before[i]))
				redraw ||= abs(d - wt.shown[i]) > 0.004
				wet ||= d > 0
				wt.depth[i], wt.before[i] = d, d
			}
		}
		s := water_slot(cx, cz)
		wt.awake[s] = change > 0.0002
		wt.wet[s] = wet
		wt.stale[s] ||= redraw
	}
	for c in work do if wt.awake[water_slot(c.key.x, c.key.z)] do water_wake(wt, c.key.x, c.key.z)
}

// How fast the water in a column is moving, metres a second.
water_velocity :: proc(wt: ^Water, x, z: i32) -> [2]f32 {
	i := water_cell(x, z)
	across := max(wt.depth[i], 0.08)*WATER_STEP
	return [2]f32{wt.flow_x[i] + wt.flow_x[water_cell(x - 1, z)], wt.flow_z[i] + wt.flow_z[water_cell(x, z - 1)]}/(2*across)
}

// The water at one corner of a column, taken over the four columns that share the corner
// so that neighbouring quads agree and the surface, its movement and its depth all vary
// smoothly. The height is kept clear of this column's own floor. `more` is the flow, the
// depth, and how broken the water is: 0 where the columns stand level, 1 where one falls
// to the next.
water_corner :: proc(wt: ^Water, x, z, u, v: i32) -> (y: f32, more: [4]f32) {
	i := water_cell(x, z)
	sum, n, depth: f32
	lo, hi: f32 = WALL, -WALL
	flow: [2]f32
	for dz in v - 1..=v {
		for dx in u - 1..=u {
			j := water_cell(x + dx, z + dz)
			if wt.depth[j] <= SHOWN do continue
			top := wt.floor[j] + wt.depth[j]
			sum += top
			n += 1
			lo, hi = min(lo, top), max(hi, top)
			depth += wt.depth[j]
			flow += water_velocity(wt, x + dx, z + dz)
		}
	}
	y = clamp(sum/n, wt.floor[i] + 0.01, wt.floor[i] + wt.depth[i] + 0.25)
	return y, {flow.x/n, flow.y/n, depth/4, clamp((hi - lo - 0.05)/0.6, 0, 1)}
}

// The water surface of a chunk: a top for each wet column, and a sheet down each side
// where the water next to it is lower.
water_surface :: proc(wt: ^Water, c: ^Chunk, out: ^[dynamic]Water_Quad) {
	for lz in i32(0)..<CHUNK {
		for lx in i32(0)..<CHUNK {
			x, z := c.key.x*CHUNK + lx, c.key.z*CHUNK + lz
			i := water_cell(x, z)
			wt.shown[i] = wt.depth[i]
			if wt.depth[i] <= SHOWN do continue
			y: [4]f32
			more: [4][4]f32
			for k in i32(0)..<4 do y[k], more[k] = water_corner(wt, x, z, k & 1, k >> 1)
			fx, fz := f32(lx), f32(lz)
			append(out, Water_Quad{{{fx, y[0], fz}, {fx + 1, y[1], fz}, {fx, y[2], fz + 1}, {fx + 1, y[3], fz + 1}}, more})

			// Each side: the two corners along it, and the column beyond.
			sides := [4][6]i32{{1, 0, 1, 3, 0, 0}, {-1, 0, 0, 2, 1, 1}, {0, 1, 2, 3, 0, 0}, {0, -1, 0, 1, 0, 1}}   // dx, dz, corner a, corner b, the neighbour's u or v on this side
			for side in sides {
				nx, nz := x + side[0], z + side[1]
				j := water_cell(nx, nz)
				ca, cb := side[2], side[3]
				a, b := y[ca], y[cb]
				below: [2]f32
				if wt.depth[j] > SHOWN {
					if side[0] != 0 {
						below[0], _ = water_corner(wt, nx, nz, side[4], 0)
						below[1], _ = water_corner(wt, nx, nz, side[4], 1)
					} else {
						below[0], _ = water_corner(wt, nx, nz, 0, side[5])
						below[1], _ = water_corner(wt, nx, nz, 1, side[5])
					}
				} else {
					below = wt.floor[j]
				}
				drop := max(a - below[0], b - below[1])
				if drop < 0.06 do continue
				fall := clamp((drop - 0.06)/0.5, 0, 1)
				ma, mb := more[ca], more[cb]
				ma[3], mb[3] = fall, fall
				// The sheet leans out from the block it falls past, so the two never share a plane.
				ax, az := fx + f32(ca & 1), fz + f32(ca >> 1)
				bx, bz := fx + f32(cb & 1), fz + f32(cb >> 1)
				ox, oz := f32(side[0])*0.12, f32(side[1])*0.12
				append(out, Water_Quad{
					{{ax, a, az}, {bx, b, bz}, {ax + ox, min(below[0], a), az + oz}, {bx + ox, min(below[1], b), bz + oz}},
					{ma, mb, ma, mb},
				})
			}
		}
	}
}

// Step the water for the time that has passed, then rebuild the surfaces that changed, a
// few each frame.
water_update :: proc(wt: ^Water, dev: ^sdl.GPUDevice, dt: f64) {
	wt.behind = min(wt.behind + dt, 2*WATER_STEP)
	for wt.behind >= WATER_STEP {
		water_step(wt)
		wt.behind -= WATER_STEP
	}

	Piece :: struct { chunk: ^Chunk, first, count: int }
	quads := make([dynamic]Water_Quad, context.temp_allocator)
	pieces := make([dynamic]Piece, context.temp_allocator)
	for k in 0..<len(wt.chunks) {
		s := (wt.turn + k)%len(wt.chunks)
		c := wt.chunks[s]
		if c == nil || !wt.stale[s] do continue
		wt.mask_stale ||= wt.unbuilt[s]
		wt.stale[s], wt.unbuilt[s] = false, false
		first := len(quads)
		water_surface(wt, c, &quads)
		append(&pieces, Piece{c, first, len(quads) - first})
		if len(pieces) == 12 {
			wt.turn = s + 1
			break
		}
	}
	if len(pieces) == 0 && !wt.mask_stale do return

	MASK :: WATER_SPAN*WATER_SPAN
	bytes := u32(len(quads)*size_of(Water_Quad))
	staging := sdl.CreateGPUTransferBuffer(dev, {usage = .UPLOAD, size = bytes + MASK})
	mapped := cast([^]u8)sdl.MapGPUTransferBuffer(dev, staging, false)
	if bytes > 0 do copy(mapped[:bytes], (cast([^]u8)raw_data(quads))[:bytes])
	for c, s in wt.chunks do mapped[int(bytes) + s] = 255 if c != nil && !wt.unbuilt[s] else 0   // the far water stays until a chunk's own is drawn
	sdl.UnmapGPUTransferBuffer(dev, staging)

	cmd := sdl.AcquireGPUCommandBuffer(dev)
	pass := sdl.BeginGPUCopyPass(cmd)
	for piece in pieces {
		c := piece.chunk
		if c.water != nil do sdl.ReleaseGPUBuffer(dev, c.water)
		c.water, c.water_count = nil, u32(piece.count)
		if piece.count == 0 do continue
		size := u32(piece.count*size_of(Water_Quad))
		c.water = sdl.CreateGPUBuffer(dev, {usage = {.VERTEX}, size = size})
		sdl.UploadToGPUBuffer(pass, {staging, u32(piece.first*size_of(Water_Quad))}, {c.water, 0, size}, false)
	}
	if wt.mask_stale {
		sdl.UploadToGPUTexture(pass,
			{transfer_buffer = staging, offset = bytes, pixels_per_row = WATER_SPAN, rows_per_layer = WATER_SPAN},
			{texture = wt.mask, w = WATER_SPAN, h = WATER_SPAN, d = 1}, false)
		wt.mask_stale = false
	}
	sdl.EndGPUCopyPass(pass)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
	sdl.ReleaseGPUTransferBuffer(dev, staging)
}
