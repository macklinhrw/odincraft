package main

import "core:math"

// The world generator. Everything the engine knows about the world comes through
// gen_columns and gen_volume, which read the land formed in land.odin and the rivers
// traced in rivers.odin.
//
// One block is one metre, y is up and sea level is y = 0. The generator is asked for the
// ground at a cell size: 1 m beside the player, up to 64 m at the horizon. Detail finer
// than the cell fades out, so a coarse answer is the average of the fine one and distant
// terrain shows the same hills as near terrain.

Mat :: enum u8 { Air, Grass, Dirt, Stone, Sand, Snow, Wood, Leaves, Gravel }

CHUNK       :: 32               // cells along a chunk side
CHUNK_SHIFT :: 5
P           :: CHUNK + 2        // a chunk plus a one-cell border, which meshing needs
SEA_LEVEL   :: 0
SEED        :: 7

// The ground under one chunk and its border.
Columns :: struct {
	top:    [P*P]i32,   // elevation of the top face, metres
	ground: [P*P]i32,   // elevation of the ground, which is lower than the top under a tree crown
	mat:    [P*P]Mat,   // what the surface is made of
	slope:  [P*P][2]u8, // the smooth ground normal's x and z, packed; zero in the border
	lo, hi: i32,        // lowest ground and highest top
}

hash :: proc(x, y: i32, seed: u32) -> u32 {
	h := u32(x)*0x9E3779B1 ~ u32(y)*0x85EBCA77 ~ seed*0xC2B2AE3D
	h ~= h >> 15; h *= 0x2C1B3C6D
	h ~= h >> 12; h *= 0x297A2D39
	h ~= h >> 15
	return h
}

hash01 :: proc(x, y: i32, seed: u32) -> f32 {
	return f32(hash(x, y, seed) >> 8)*(1.0/16777216.0)
}

// Smooth noise in 0..1 with its gradient.
noise :: proc(x, y: f64, seed: u32) -> (v, dx, dy: f32) {
	fx, fy := math.floor(x), math.floor(y)
	ix, iy := i32(fx), i32(fy)
	tx, ty := f32(x - fx), f32(y - fy)
	ux := tx*tx*tx*(tx*(tx*6 - 15) + 10)
	uy := ty*ty*ty*(ty*(ty*6 - 15) + 10)
	a, b := hash01(ix, iy, seed), hash01(ix + 1, iy, seed)
	c, d := hash01(ix, iy + 1, seed), hash01(ix + 1, iy + 1, seed)
	k1, k2, k4 := b - a, c - a, a - b - c + d
	v = a + k1*ux + k2*uy + k4*ux*uy
	dx = 30*tx*tx*(tx*(tx - 2) + 1)*(k1 + k4*uy)
	dy = 30*ty*ty*(ty*(ty - 2) + 1)*(k2 + k4*ux)
	return
}

// How much of a wave survives at a cell size: all of it at four cells per wavelength,
// none at two.
band :: proc(wavelength, cell: f64) -> f32 {
	return f32(clamp(wavelength/cell*0.5 - 1, 0, 1))
}

// Layered noise in -1..1.
fbm :: proc(x, z, wavelength, cell: f64, octaves: int, seed: u32) -> f32 {
	sum, amp, total: f32 = 0, 1, 0
	px, pz, wl := x, z, wavelength
	for i in 0..<octaves {
		total += amp
		if w := band(wl, cell); w > 0 {
			v, _, _ := noise(px/wl, pz/wl, seed + u32(i))
			sum += w*amp*(v*2 - 1)
		}
		amp *= 0.5
		wl *= 0.5
		px, pz = 0.8*px - 0.6*pz, 0.6*px + 0.8*pz
	}
	return sum/total
}

smoothstep :: proc(a, b, x: f32) -> f32 {
	t := clamp((x - a)/(b - a), 0, 1)
	return t*t*(3 - 2*t)
}

// Form the land and its rivers. Call once, before anything asks about the world.
gen_init :: proc() {
	land_form()
	rivers_trace()
}

// The ground at a point as seen at a cell size: its elevation, how steep the hillside is,
// and whether the point is river bed.
ground :: proc(x, z, cell: f64) -> (h, steep: f32, gravel: bool) {
	level := 0 if cell <= 16 else 1 if cell <= 32 else 2
	h = land_at(land.z[level], LAND_N >> uint(level), x, z)
	steep = max(land_at(land.slope, LAND_N, x, z), 0)
	// Small rises and hollows the simulation is too coarse to hold: more on slopes, none at the shore.
	h += fbm(x, z, 70, cell, 3, SEED + 80)*(0.5 + 2.2*min(steep, 1))*smoothstep(0, 3, h)
	h, gravel = river_cut(h, x, z, cell)
	return
}

height_at :: proc(x, z, cell: f64) -> f32 {
	h, _, _ := ground(x, z, cell)
	return h
}

// What the ground is at a point: its elevation and what covers it.
surface_at :: proc(x, z, cell: f64) -> (h: f32, m: Mat) {
	steep: f32
	gravel: bool
	h, steep, gravel = ground(x, z, cell)
	vary := fbm(x, z, 120, cell, 2, SEED + 100) + 0.7*fbm(x, z, 22, cell, 2, SEED + 101)   // broad patches, broken at the edges
	hard := -fbm(x, z, 1100, 1, 3, SEED + 5)   // above zero where the rock resists; the simulation used the same bands
	switch {
	case gravel:                                   m = .Gravel
	case h < 1.8 + vary*1.2:                       m = .Sand
	case steep > 0.64 + vary*0.08 - hard*0.10:     m = .Stone   // too steep to keep its soil
	case:                                          m = .Grass
	}
	return
}

// ---- trees --------------------------------------------------------------------------------

Tree :: struct {
	x, z:   i32,   // block the trunk stands on
	base:   i32,   // elevation of the ground there
	trunk:  i32,   // height of the trunk; the crown is centred on its top and clears head height
	radius: i32,   // of the crown
}

TREE_GRID  :: 6   // at most one tree per square of this many metres
TREE_REACH :: 4   // the widest crown

// How wooded the land is, 0..1. Trees follow water: thick in valley floors and hollows,
// thinning up the slopes, absent from the high ridges.
forest_at :: proc(x, z: f64) -> f32 {
	wet := land_at(land.wet, LAND_N, x, z)
	h := land_at(land.z[0], LAND_N, x, z)
	return clamp(0.12 + 1.3*wet + 0.4*fbm(x, z, 500, 1, 3, SEED + 120) - smoothstep(170, 320, h), 0, 1)
}

// Every tree whose trunk stands in a rectangle of blocks. The same tree is found whichever
// chunk or level of detail asks.
trees_in :: proc(x0, z0, x1, z1: i32, out: ^[dynamic]Tree) {
	floor_div :: proc(a, b: i32) -> i32 { return (a - a %% b)/b }
	for gz in floor_div(z0, TREE_GRID)..=floor_div(z1, TREE_GRID) {
		for gx in floor_div(x0, TREE_GRID)..=floor_div(x1, TREE_GRID) {
			r := hash(gx, gz, SEED + 140)
			x, z := gx*TREE_GRID + i32(r % TREE_GRID), gz*TREE_GRID + i32((r >> 4) % TREE_GRID)
			if x < x0 || x > x1 || z < z0 || z > z1 do continue
			fx, fz := f64(x) + 0.5, f64(z) + 0.5
			if f32((r >> 8) & 0xFF)/255 >= forest_at(fx, fz)*0.92 do continue
			h, m := surface_at(fx, fz, 1)
			if m != .Grass do continue
			radius := 2 + i32((r >> 24) % 3)
			append(out, Tree{x, z, i32(math.round(h)), radius + 3 + i32((r >> 16) % 4), radius})
		}
	}
}

// Height of a tree's crown above its base at a horizontal distance from the trunk, or
// zero outside the crown.
crown_top :: proc(t: Tree, distance: f32) -> i32 {
	r := f32(t.radius) + 0.5
	if distance >= r do return 0
	return t.trunk + i32(math.sqrt(r*r - distance*distance)*0.85)
}

// ---- what the engine asks for -------------------------------------------------------------

// The ground under a chunk at a level of detail. Beyond the nearest level, trees are part
// of the columns: single crowns while cells are small enough to show them, then a canopy.
gen_columns :: proc(level, cx, cz: i32, c: ^Columns) {
	s := i32(1) << u32(level)
	cell := f64(s)
	heights: [P*P]f32
	for j in 0..<i32(P) {
		for i in 0..<i32(P) {
			ix, iz := cx*CHUNK + i - 1, cz*CHUNK + j - 1   // cell coordinates at this level
			x, z := (f64(ix) + 0.5)*cell, (f64(iz) + 0.5)*cell
			k := j*P + i
			heights[k], c.mat[k] = surface_at(x, z, cell)
			c.top[k] = i32(math.round(heights[k]))
			c.ground[k] = c.top[k]
			if s >= 8 && c.mat[k] == .Grass {
				r := hash(ix, iz, SEED + 160 + u32(level))
				if f32(r & 0xFFFF)/65536 < forest_at(x, z)*0.75 {
					c.top[k] += 7 + i32((r >> 16) % 4)
					c.mat[k] = .Leaves
				}
			}
		}
	}
	// The slope of the ground before it was cut into blocks. Light uses it so that a
	// hillside shades as a hillside and not only as a staircase. Crowns keep zero.
	for j in 1..<P - 1 {
		for i in 1..<P - 1 {
			k := j*P + i
			if c.mat[k] == .Leaves do continue
			gx := (heights[k + 1] - heights[k - 1])/f32(2*s)
			gz := (heights[k + P] - heights[k - P])/f32(2*s)
			inv := 127/math.sqrt(gx*gx + gz*gz + 1)
			c.slope[k] = {u8(128 - gx*inv), u8(128 - gz*inv)}
		}
	}
	if level == 1 || level == 2 {
		trees := make([dynamic]Tree, context.temp_allocator)
		x0, z0 := (cx*CHUNK - 1)*s, (cz*CHUNK - 1)*s
		trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P*s + TREE_REACH, z0 + P*s + TREE_REACH, &trees)
		for t in trees {
			for j in max((t.z - TREE_REACH - z0)/s, 0)..=min((t.z + TREE_REACH - z0)/s, P - 1) {
				for i in max((t.x - TREE_REACH - x0)/s, 0)..=min((t.x + TREE_REACH - x0)/s, P - 1) {
					dx := f32(x0 + i*s) + f32(s)/2 - (f32(t.x) + 0.5)
					dz := f32(z0 + j*s) + f32(s)/2 - (f32(t.z) + 0.5)
					if rise := crown_top(t, math.sqrt(dx*dx + dz*dz)); rise > 0 {
						k := j*P + i
						c.top[k] = max(c.top[k], t.base + rise)
						c.mat[k] = .Leaves
						c.slope[k] = {}
					}
				}
			}
		}
	}
	c.lo, c.hi = max(i32), min(i32)
	for k in 0..<P*P {
		c.lo = min(c.lo, c.ground[k])
		c.hi = max(c.hi, c.top[k])
	}
}

// The block at a depth below the surface of a column.
block_below :: proc(surface: Mat, depth: i32) -> Mat {
	#partial switch surface {
	case .Grass: return .Grass if depth == 0 else .Dirt if depth < 4 else .Stone
	case .Sand:  return .Sand if depth < 4 else .Stone
	case .Snow:  return .Snow if depth < 2 else .Stone
	case .Gravel: return .Gravel if depth < 2 else .Stone
	}
	return .Stone
}

// The blocks of a nearest-level chunk and its border, in layers from y_base up. `lo` and
// `hi` widen the vertical range, for edits that reach outside the generated ground.
gen_volume :: proc(cx, cz: i32, c: ^Columns, lo, hi: i32) -> (blocks: []u8, y_base, h: i32) {
	trees := make([dynamic]Tree, context.temp_allocator)
	x0, z0 := cx*CHUNK - 1, cz*CHUNK - 1
	trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P + TREE_REACH, z0 + P + TREE_REACH, &trees)
	top := max(hi, c.hi)
	for t in trees do top = max(top, t.base + t.trunk + t.radius + 1)

	y_base = min(lo, c.lo) - 4   // room below for the rim faces and corner light
	h = top - y_base + 1
	blocks = make([]u8, P*P*int(h))
	for k in 0..<P*P {
		t := c.top[k]
		for y in y_base..<t do blocks[k + int(y - y_base)*P*P] = u8(block_below(c.mat[k], t - 1 - y))
	}
	for t in trees {
		put :: proc(blocks: []u8, x, y, z: i32, m: Mat, replace: bool) {
			if x < 0 || x >= P || z < 0 || z >= P do return
			k := int(x) + int(z)*P + int(y)*P*P
			if replace || blocks[k] == 0 do blocks[k] = u8(m)
		}
		crown := t.base + t.trunk
		for y in t.base..<crown do put(blocks, t.x - x0, y - y_base, t.z - z0, .Wood, true)
		r := t.radius
		for dy in -r..=r {
			for dz in -r..=r {
				for dx in -r..=r {
					ragged := hash01(t.x + dx + dy*57, t.z + dz, SEED + 180)*1.6   // a soft, uneven edge
					if f32(dx*dx + dz*dz) + f32(dy*dy)*1.4 > f32(r*r) + 0.6 - ragged do continue
					put(blocks, t.x + dx - x0, crown + dy - y_base, t.z + dz - z0, .Leaves, false)
				}
			}
		}
	}
	return
}
