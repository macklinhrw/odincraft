package main

import "core:math"

// The world generator. Everything the engine knows about the world comes through
// gen_columns and gen_volume, which read the land formed in land.odin and the rivers
// traced in rivers.odin. Those two take a chunk in the world; everything below them works
// relative to the region's middle (region.origin), so the island is the same wherever it lies.
//
// One block is one metre, y is up and sea level is y = 0. The generator is asked for the
// ground at a cell size: 1 m beside the player, up to 64 m at the horizon. Detail finer
// than the cell fades out, so a coarse answer is the average of the fine one and distant
// terrain shows the same hills as near terrain.

// A block is an index into one table of materials. The shader's palette is written from it.
// A rock kind's loose form follows the solid ones, so each kind can later gain its broken
// and gravel forms as rows of their own.
Mat :: enum u8 {
	Air, Grass, Dirt, Stone, Sand, Snow, Wood, Leaves, Gravel,
	Mudstone, Siltstone, Sandstone, Grit, Limestone, Basalt, Scoria, Rhyolite, Tuff,
	Mudstone_Scree, Siltstone_Scree, Sandstone_Scree, Grit_Scree, Limestone_Scree, Basalt_Scree, Scoria_Scree, Rhyolite_Scree, Tuff_Scree,
}

Material :: struct {
	colour:   [3]f32,   // albedo, linear
	strength: f32,      // of a rock, 0..1 (rock.odin); zero for anything else
	crack:    f32,      // metres between the cracks that break a face of it, along the strike
	loose:    Mat,      // what it is once fallen from a face
}

MATERIALS := [Mat]Material{
	.Air       = {{1.0, 0.0, 1.0}, 0, 0, .Air},
	.Grass     = {{0.070, 0.135, 0.032}, 0, 0, .Air},
	.Dirt      = {{0.130, 0.085, 0.048}, 0, 0, .Air},
	.Stone     = {{0.165, 0.155, 0.140}, 0, 0, .Air},
	.Sand      = {{0.330, 0.285, 0.180}, 0, 0, .Air},
	.Snow      = {{0.780, 0.800, 0.840}, 0, 0, .Air},
	.Wood      = {{0.105, 0.068, 0.036}, 0, 0, .Air},
	.Leaves    = {{0.036, 0.105, 0.024}, 0, 0, .Air},
	.Gravel    = {{0.105, 0.097, 0.085}, 0, 0, .Air},
	.Mudstone  = {{0.062, 0.064, 0.074}, 0.25, 0.1, .Mudstone_Scree},   // dark blue-grey, crumbles into flakes; never holds a face
	.Siltstone = {{0.098, 0.082, 0.062}, 0.4, 0.3, .Siltstone_Scree},   // grey-brown flags, thin ledges
	.Sandstone = {{0.136, 0.108, 0.074}, 0.6, 1.5, .Sandstone_Scree},   // warm buff rectangular blocks
	.Grit      = {{0.150, 0.134, 0.128}, 0.8, 4, .Grit_Scree},          // pinkish grey pebbly rock that caps the hills, in huge blocks
	.Limestone = {{0.178, 0.180, 0.178}, 0.65, 1, .Limestone_Scree},    // pale grey
	.Basalt    = {{0.050, 0.047, 0.045}, 0.75, 1, .Basalt_Scree},       // black-grey lava flows, jointed into columns
	.Scoria    = {{0.085, 0.043, 0.033}, 0.25, 0.1, .Scoria_Scree},     // red-brown cinders and ash between the flows; crumbles
	.Rhyolite  = {{0.200, 0.186, 0.172}, 0.7, 2, .Rhyolite_Scree},      // pale grey-pink stiff lava, in sheeted crags
	.Tuff      = {{0.215, 0.200, 0.160}, 0.3, 0.1, .Tuff_Scree},        // cream pumice and ash
	.Mudstone_Scree  = {{0.066, 0.068, 0.079}, 0, 0, .Air},   // fresh broken rock is a little paler than the weathered face
	.Siltstone_Scree = {{0.105, 0.088, 0.066}, 0, 0, .Air},
	.Sandstone_Scree = {{0.146, 0.116, 0.079}, 0, 0, .Air},
	.Grit_Scree      = {{0.160, 0.143, 0.137}, 0, 0, .Air},
	.Limestone_Scree = {{0.190, 0.193, 0.190}, 0, 0, .Air},
	.Basalt_Scree    = {{0.058, 0.054, 0.051}, 0, 0, .Air},
	.Scoria_Scree    = {{0.093, 0.047, 0.036}, 0, 0, .Air},
	.Rhyolite_Scree  = {{0.214, 0.200, 0.185}, 0, 0, .Air},
	.Tuff_Scree      = {{0.228, 0.212, 0.170}, 0, 0, .Air},
}

CHUNK       :: 32               // cells along a chunk side
CHUNK_SHIFT :: 5
P           :: CHUNK + 2        // a chunk plus a one-cell border, which meshing needs
SEA_LEVEL   :: 0
SEA_SURFACE :: SEA_LEVEL - 0.15   // where the sea stands, a little under the block tops at the shore
NO_WATER    :: -1e6
seed        := u32(7)   // every random choice in the world is keyed from this; --seed= sets it

// The ground under one chunk and its border.
Columns :: struct {
	top:    [P*P]i32,   // elevation of the top face, metres
	ground: [P*P]i32,   // elevation of the ground, which is lower than the top under a canopy
	crown:  [P*P][2]i32, // the underside and top of a single tree's crown over the ground, where one hangs here
	stem:   [P*P]u8,    // where a trunk stands in the cell: 1 + its x + 4 times its z in metres from the cell's corner, or 0
	water:  [P*P]f32,   // level of the river or sea standing here, or NO_WATER
	mat:    [P*P]Mat,   // what the surface is made of
	base:   [P*P]f32,   // height of the rock stack's base, which places the beds (rock.odin)
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
gen_init :: proc(kind: string) -> bool {
	region_init(kind) or_return
	rock_init()
	land_form()
	rivers_trace()
	return true
}

Ground :: struct {
	h, steep: f32,   // elevation, and how steep the ground is there, rise over run
	base:     f32,   // height of the rock stack's base under it (rock.odin)
	water:    f32,   // level of the river or sea standing here, or NO_WATER
	cover:    Mat,   // river gravel, or the loose rock lying under a face; Air for neither
}

REPOSE     :: 0.67   // loose rock comes to rest at about 34°
SOIL_HOLDS :: 1      // and soil holds on ground up to about 45°, rise over run

// How strongly a bed of `lo` under a bed of `hi` stands as a ledge on a hillside this steep:
// a riser at the foot of `lo` and a tread on its top. Only a stronger bed under a weaker one,
// and only where the land forming left the stronger near the steepest slope it holds.
ledge :: proc(lo, hi: Mat, steep: f32) -> f32 {
	return smoothstep(0.05, 0.3, MATERIALS[lo].strength - MATERIALS[hi].strength)*smoothstep(0.5, 0.9, steep/rocks.law[lo].limit)
}

Ledge :: struct {
	h, rise: f32,   // height, and how many times steeper than the smooth hillside the ground is
	lift:    f32,   // depth of the loose rock lying there
	face:    Mat,   // the rock of the face above, if this bed lies under one
}

// The beds in a hillside (docs/foundations/ground-and-underground.md, §5). The land forming
// leaves a face as a smooth slope through its beds. Here the height within each bed is pushed
// toward its contact with a weaker bed above, from both sides, so a strong bed stands as a
// riser with a tread on its top and the weak bed above begins on that tread. The contacts
// stay where the rock has them; only the ground between them moves, and the change fades
// once a cell is too coarse to hold a riser. Under a riser, rock fallen from it lies at its
// angle of rest.
ledges :: proc(h, steep, base: f32, cell: f64) -> (l: Ledge) {
	l.h, l.rise = h, 1
	y := h - base - STACK_LO
	n := int(rocks.bed[clamp(int(y), 0, STACK_LEN - 1)])
	if n == 0 || n + 2 >= len(rocks.beds) do return
	bed, floor := rocks.beds[n], rocks.floor[n]
	fade := band(2*f64(bed.thick/max(steep, 0.1)), cell)
	// A tread on this bed's top: under a weaker bed, or on a thick hard bed standing at the
	// steepest slope it holds, which breaks as a face whatever lies above it.
	massive := smoothstep(0.4, 0.6, MATERIALS[bed.kind].strength)*smoothstep(25, 40, bed.thick)*smoothstep(0.85, 1, steep/rocks.law[bed.kind].limit)
	top := fade*max(ledge(bed.kind, rocks.beds[n + 1].kind, steep), massive)
	foot := fade*ledge(rocks.beds[n - 1].kind, bed.kind, steep)   // a tread at its foot, on the bed below's top
	if top + foot > 1 do top, foot = top/(top + foot), foot/(top + foot)   // so the ground never folds back over itself
	q := clamp((y - floor)/bed.thick, 0, 1)
	p := 1 - q
	SHARP :: 8   // how abruptly a riser turns into its tread
	g := q + top*(1 - math.pow(p, SHARP) - q) + foot*(math.pow(q, SHARP) - q)
	l.rise = 1 + top*(SHARP*math.pow(p, SHARP - 1) - 1) + foot*(SHARP*math.pow(q, SHARP - 1) - 1)
	l.h = h + bed.thick*(g - q)
	// Under the riser of the bed above: rock fallen from it, lying from the contact down at its
	// angle of rest, or where the hillside is steeper than that, no steeper than the hillside,
	// so it always comes to ground within this bed.
	above := rocks.beds[n + 1].kind
	if face := fade*max(ledge(above, rocks.beds[n + 2].kind, steep), smoothstep(0.9, 1.1, steep/max(rocks.law[above].limit, SOIL_HOLDS))); face > 0 {
		l.face = above
		fall := max(REPOSE/max(steep, 0.01), 1)   // its fall per metre of the smooth hillside's
		if lift := face*(h + bed.thick*p*(1 - fall) - l.h); lift > 0 {
			l.h, l.lift, l.rise = l.h + lift, lift, fall
		}
	}
	return
}

// The ground the land forming left at a point, shaped by its beds, read `back` metres up the
// hillside from where it stands.
shaped :: proc(x, z, cell: f64, back: f32 = 0) -> (l: Ledge, steep, base: f32) {
	level := 0 if cell <= 16 else 1 if cell <= 32 else 2
	steep = max(land_at(land.slope, land.n, x, z), 0)
	base = rock_base(x, z, cell)
	l = ledges(land_at(land.z[level], land.n >> uint(level), x, z) - back*steep, steep, base, cell)
	return
}

// The ground at a point as seen at a cell size.
ground :: proc(x, z, cell: f64) -> (g: Ground) {
	l, steep, base := shaped(x, z, cell)
	g.base = base
	near := band(8, cell)   // cracks are gone by 4 m cells
	// A face that breaks along its cracks: each block between two cracks stands up to a metre
	// forward of the face or back from it, so the face breaks into prisms. One set of cracks
	// runs along the strike of the beds and the other across it, each bed with its own.
	n := rocks.bed[clamp(int(l.h - 0.5 - base - STACK_LO), 0, STACK_LEN - 1)]
	kind := rocks.beds[n].kind
	if gap := MATERIALS[kind].crack; near > 0 && l.lift == 0 && gap >= 1 {
		if bare := near*smoothstep(1, 1.5, steep*l.rise/rocks.law[kind].limit); bare > 0 {
			strike := rock_strike(x, z)
			u, v := (x*strike.x + z*strike.y)/f64(gap), (z*strike.x - x*strike.y)/f64(2.5*gap)
			across := i32(math.floor(v + f64(hash01(i32(n), 1, seed + 401))))
			along := i32(math.floor(u + f64(hash01(across, i32(n), seed + 402))))
			l, _, _ = shaped(x, z, cell, 2*bare*(hash01(along, across, seed + 403 + u32(n)) - 0.5))
		}
	}
	if l.lift > 0 do g.cover = MATERIALS[l.face].loose
	// Small rises and hollows the simulation is too coarse to hold: more on slopes, none at
	// the shore, and none on a ledged face or loose rock, whose shapes have their own causes.
	h := l.h + fbm(x, z, 70, cell, 3, seed + 80)*(0.5 + 2.2*min(steep, 1))*smoothstep(0, 3, l.h)*min(l.rise, 1)*(1 - smoothstep(0, 1, l.lift))
	gravel: bool
	g.h, gravel, g.water = river_cut(h, x, z, cell)
	if gravel do g.cover = .Gravel
	if g.h < SEA_SURFACE do g.water = max(g.water, SEA_SURFACE)
	g.steep = steep*l.rise
	return
}

height_at :: proc(x, z, cell: f64) -> f32 {
	return ground(x, z, cell).h
}

// What the ground is at a point, and what covers it.
surface_at :: proc(x, z, cell: f64) -> (g: Ground, m: Mat) {
	g = ground(x, z, cell)
	vary := fbm(x, z, 120, cell, 2, seed + 100) + 0.7*fbm(x, z, 22, cell, 2, seed + 101)   // broad patches, broken at the edges
	bed := rock_in(g.h - 0.5, g.base, rock_level(cell))
	// Soil and forest hold on ground up to about 45°, as on real flanks; only a face steeper
	// than that is bare, which a weak rock makes only where the sea undercuts it or as the riser
	// of a ledge.
	holds := SOIL_HOLDS + 0.15*vary
	switch {
	case g.cover == .Gravel:       m = .Gravel
	case g.h < 1.8 + vary*1.2:     m = .Sand
	case g.cover != .Air:          m = g.cover
	case g.steep > holds:          m = bed
	case:                          m = .Grass
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
	wet := land_at(land.wet, land.n, x, z)
	h := land_at(land.z[0], land.n, x, z)
	return clamp(0.12 + 1.3*wet + 0.4*fbm(x, z, 500, 1, 3, seed + 120) - smoothstep(170, 320, h), 0, 1)
}

// Every tree whose trunk stands in a rectangle of blocks. The same tree is found whichever
// chunk or level of detail asks.
trees_in :: proc(x0, z0, x1, z1: i32, out: ^[dynamic]Tree) {
	floor_div :: proc(a, b: i32) -> i32 { return (a - a %% b)/b }
	for gz in floor_div(z0, TREE_GRID)..=floor_div(z1, TREE_GRID) {
		for gx in floor_div(x0, TREE_GRID)..=floor_div(x1, TREE_GRID) {
			r := hash(gx, gz, seed + 140)
			x, z := gx*TREE_GRID + i32(r % TREE_GRID), gz*TREE_GRID + i32((r >> 4) % TREE_GRID)
			if x < x0 || x > x1 || z < z0 || z > z1 do continue
			fx, fz := f64(x) + 0.5, f64(z) + 0.5
			if f32((r >> 8) & 0xFF)/255 >= forest_at(fx, fz)*0.92 do continue
			g, m := surface_at(fx, fz, 1)
			if m != .Grass do continue
			radius := 2 + i32((r >> 24) % 3)
			append(out, Tree{x, z, i32(math.round(g.h)), radius + 3 + i32((r >> 16) % 4), radius})
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

// The ground under a chunk at a level of detail. Beyond the nearest level, single trees are
// crowns hung over the ground on their trunks while cells are small enough to show them, then
// a canopy that is part of the columns.
gen_columns :: proc(level, cx, cz: i32, c: ^Columns) {
	s := i32(1) << u32(level)
	cell := f64(s)
	ox, oz := region.origin.x, region.origin.y
	heights: [P*P]f32
	for j in 0..<i32(P) {
		for i in 0..<i32(P) {
			ix, iz := cx*CHUNK + i - 1, cz*CHUNK + j - 1   // cell coordinates at this level, in the world
			x, z := (f64(ix) + 0.5)*cell - f64(ox), (f64(iz) + 0.5)*cell - f64(oz)
			k := j*P + i
			g: Ground
			g, c.mat[k] = surface_at(x, z, cell)
			heights[k], c.water[k], c.base[k] = g.h, g.water, g.base
			c.top[k] = i32(math.round(heights[k]))
			c.ground[k] = c.top[k]
			if s >= 8 && c.mat[k] == .Grass {
				r := hash(i32(math.floor(x/cell)), i32(math.floor(z/cell)), seed + 160 + u32(level))
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
		x0, z0 := (cx*CHUNK - 1)*s - ox, (cz*CHUNK - 1)*s - oz
		trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P*s + TREE_REACH, z0 + P*s + TREE_REACH, &trees)
		for t in trees {
			for j in max((t.z - TREE_REACH - z0)/s, 0)..=min((t.z + TREE_REACH - z0)/s, P - 1) {
				for i in max((t.x - TREE_REACH - x0)/s, 0)..=min((t.x + TREE_REACH - x0)/s, P - 1) {
					dx := f32(x0 + i*s) + f32(s)/2 - (f32(t.x) + 0.5)
					dz := f32(z0 + j*s) + f32(s)/2 - (f32(t.z) + 0.5)
					// A crown is as deep below the top of its trunk as it is high above it.
					if rise := crown_top(t, math.sqrt(dx*dx + dz*dz)); rise > 0 {
						k := j*P + i
						under, over := max(t.base + 2*t.trunk - rise, c.ground[k]), t.base + rise
						if over <= under do continue
						if c.crown[k][1] > c.crown[k][0] do under, over = min(under, c.crown[k][0]), max(over, c.crown[k][1])
						c.crown[k] = {under, over}
					}
				}
			}
			// The trunk's own cell always carries crown, so a small tree is never lost between cells.
			if i, j := (t.x - x0)/s, (t.z - z0)/s; t.x >= x0 && t.z >= z0 && i < P && j < P {
				k := j*P + i
				c.stem[k] = u8(1 + (t.x - x0 - i*s) + 4*(t.z - z0 - j*s))
				if rise := crown_top(t, 0); c.crown[k][1] <= c.crown[k][0] do c.crown[k] = {max(t.base + 2*t.trunk - rise, c.ground[k]), t.base + rise}
			}
		}
	}
	c.lo, c.hi = max(i32), min(i32)
	for k in 0..<P*P {
		c.lo = min(c.lo, c.ground[k])
		c.hi = max(c.hi, c.top[k], c.crown[k][1])
	}
}

// The block at a depth below the surface of a column, where `bed` is the rock at that
// height. Bare rock is rock all the way down, so a face and a hole show the same beds.
block_below :: proc(surface: Mat, depth: i32, bed: Mat) -> Mat {
	#partial switch surface {
	case .Grass: return .Grass if depth == 0 else .Dirt if depth < 4 else bed
	case .Sand:  return .Sand if depth < 4 else bed
	case .Snow:  return .Snow if depth < 2 else bed
	case .Gravel: return .Gravel if depth < 2 else bed
	}
	if surface >= .Mudstone_Scree do return surface if depth < 5 else bed   // loose rock lies on the bed
	return bed
}

// The blocks of a nearest-level chunk and its border, in layers from y_base up. `lo` and
// `hi` widen the vertical range, for edits that reach outside the generated ground.
gen_volume :: proc(cx, cz: i32, c: ^Columns, lo, hi: i32) -> (blocks: []u8, y_base, h: i32) {
	trees := make([dynamic]Tree, context.temp_allocator)
	x0, z0 := cx*CHUNK - 1 - region.origin.x, cz*CHUNK - 1 - region.origin.y
	trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P + TREE_REACH, z0 + P + TREE_REACH, &trees)
	top := max(hi, c.hi)
	for t in trees do top = max(top, t.base + t.trunk + t.radius + 1)

	y_base = min(lo, c.lo) - 4   // room below for the rim faces and corner light
	h = top - y_base + 1
	blocks = make([]u8, P*P*int(h))
	for k in 0..<P*P {
		t := c.top[k]
		for y in y_base..<t do blocks[k + int(y - y_base)*P*P] = u8(block_below(c.mat[k], t - 1 - y, rock_in(f32(y) + 0.5, c.base[k], 0)))
	}
	for t in trees {
		put :: proc(blocks: []u8, x, y, z: i32, m: Mat, replace: bool) {
			if x < 0 || x >= P || z < 0 || z >= P || y < 0 do return   // below y is this chunk's solid ground: a tree at a cliff's foot
			k := int(x) + int(z)*P + int(y)*P*P
			if replace || blocks[k] == 0 do blocks[k] = u8(m)
		}
		crown := t.base + t.trunk
		for y in t.base..<crown do put(blocks, t.x - x0, y - y_base, t.z - z0, .Wood, true)
		r := t.radius
		for dy in -r..=r {
			for dz in -r..=r {
				for dx in -r..=r {
					ragged := hash01(t.x + dx + dy*57, t.z + dz, seed + 180)*1.6   // a soft, uneven edge
					if f32(dx*dx + dz*dz) + f32(dy*dy)*1.4 > f32(r*r) + 0.6 - ragged do continue
					put(blocks, t.x + dx - x0, crown + dy - y_base, t.z + dz - z0, .Leaves, false)
				}
			}
		}
	}
	return
}
