package main

import "core:fmt"
import "core:math"
import "core:sync"
import "core:time"

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
	Shii_Bark, Shii_Leaves, Grey_Bark, Camellia_Leaves, Hisakaki_Leaves, Pine_Bark, Pine_Needles, Scrub_Leaves,   // each species' bark and leaf (SPECIES); the tabu's are Wood and Leaves
	Wood_End, Shii_End, Grey_End, Pine_End,               // a trunk cut across: its rings. Only faces are these, never blocks (grain, mesh.odin)
	Wood_Across, Shii_Across, Grey_Across, Pine_Across,   // and the bark of a lying trunk, turned to run along it
	Litter, Susuki, Dune,             // what covers the ground between the trees (COMMUNITIES)
	Black_Sand,                       // a beach ground from dark lava
	Shingle, Black_Shingle,           // the stones the waves round and throw up where they leave no sand
	Loam, Silt, Red_Clay, Ash,        // the soils under it (SOILS)
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
	.Leaves    = {{0.021, 0.074, 0.017}, 0, 0, .Air},   // tabu: dark and glossy
	.Gravel    = {{0.105, 0.097, 0.085}, 0, 0, .Air},
	.Shii_Bark       = {{0.087, 0.070, 0.055}, 0, 0, .Air},   // dark grey-brown, furrowed
	.Shii_Leaves     = {{0.074, 0.139, 0.021}, 0, 0, .Air},  // olive with a yellow cast
	.Grey_Bark       = {{0.184, 0.177, 0.151}, 0, 0, .Air},   // smooth and pale, on camellia and hisakaki
	.Camellia_Leaves = {{0.010, 0.048, 0.013}, 0, 0, .Air},   // the darkest, with red flowers
	.Hisakaki_Leaves = {{0.045, 0.087, 0.023}, 0, 0, .Air},   // small, dull
	.Pine_Bark       = {{0.106, 0.087, 0.074}, 0, 0, .Air},   // black pine: dark plates
	.Pine_Needles    = {{0.015, 0.058, 0.028}, 0, 0, .Air},
	.Scrub_Leaves    = {{0.058, 0.128, 0.030}, 0, 0, .Air},  // tobira and its like: glossy mid green
	.Wood_End        = {{0.300, 0.190, 0.105}, 0, 0, .Air},   // the wood inside: tabu's is reddish
	.Shii_End        = {{0.330, 0.240, 0.140}, 0, 0, .Air},
	.Grey_End        = {{0.400, 0.320, 0.210}, 0, 0, .Air},   // camellia's pale and fine
	.Pine_End        = {{0.380, 0.260, 0.120}, 0, 0, .Air},   // pine's yellow with resin
	.Wood_Across     = {{0.105, 0.068, 0.036}, 0, 0, .Air},
	.Shii_Across     = {{0.087, 0.070, 0.055}, 0, 0, .Air},
	.Grey_Across     = {{0.184, 0.177, 0.151}, 0, 0, .Air},
	.Pine_Across     = {{0.106, 0.087, 0.074}, 0, 0, .Air},
	.Litter    = {{0.096, 0.058, 0.025}, 0, 0, .Air},      // fallen evergreen leaves
	.Susuki    = {{0.096, 0.157, 0.038}, 0, 0, .Air},    // susuki grass and dwarf bamboo
	.Dune      = {{0.128, 0.139, 0.062}, 0, 0, .Air},   // dune grass, straw
	.Black_Sand = {{0.060, 0.057, 0.054}, 0, 0, .Air},   // basalt and cinder sand, dark grey
	.Shingle       = {{0.128, 0.120, 0.108}, 0, 0, .Air},   // sea-worn pebbles, paler than the rock they came from
	.Black_Shingle = {{0.075, 0.072, 0.070}, 0, 0, .Air},
	.Loam      = {{0.058, 0.040, 0.026}, 0, 0, .Air},   // dark topsoil
	.Silt      = {{0.050, 0.046, 0.038}, 0, 0, .Air},   // grey river silt
	.Red_Clay  = {{0.184, 0.062, 0.030}, 0, 0, .Air},     // the red clay long rain leaves on old ground
	.Ash       = {{0.019, 0.013, 0.010}, 0, 0, .Air},      // black soil weathered from ash and cinders
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
COARSE      :: 64               // metres: a column wider than this, 16 km off and more, is the mean of the land, with no stream cut or stack in it
NO_WATER    :: -1e6
@(thread_local) seed: u32   // every random choice in a region is keyed from this: its island's seed (bind)

// The ground under one chunk and its border.
Columns :: struct {
	top:    [P*P]i32,   // elevation of the top face, metres
	ground: [P*P]i32,   // elevation of the ground, which is lower than the top under a canopy
	crown:  [P*P][2]i32, // the underside and top of a single tree's crown over the ground, where one hangs here
	stem:   [P*P]u8,    // where a trunk stands in the cell: 1 + its x + 4 times its z in metres from the cell's corner, or 0
	kind:   [P*P]Tree_Kind, // the species of that crown and trunk
	water:  [P*P]f32,   // level of the river or sea standing here, or NO_WATER
	mat:    [P*P]Mat,   // what the surface is made of
	base:   [P*P]f32,   // height of the rock stack's base, which places the beds (rock.odin)
	slope:  [P*P][2]u8, // the smooth ground normal's x and z, packed; zero in the border
	hollow: [P*P][2]i32, // the floor and roof of a hollow carved under the top here (events.odin); far off, of its mouth
	plant:  [P*P]u8,    // at the nearest level, 1 + the ground plant standing here (plants.odin), or 0
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

// Form an island's land and its rivers, and all that lies and lives on them, from its record and
// seed alone (regions.odin), on whichever thread calls. Nothing asks about the island before.
gen_init :: proc(f: ^Formed) {
	bound(f)
	started := time.now()
	f.region.origin, f.region.size, f.landslide = f.island.origin, f.island.size, {box = {1e9, 1e9, -1e9, -1e9}}
	region_init(KINDS[f.island.kind].name, f.island.size)
	region.shape.swell = plates.wind   // every island's swell comes from the one wind (archipelago.odin); the start island's is the one it drew
	rock_init()
	land_form()
	rivers_trace()
	plants_init()
	hollows_make()
	trails_make()
	places_make()
	creatures_make()
	f.seconds = time.duration_seconds(time.since(started))
	sync.atomic_store_explicit(&f.ready, true, .Release)
}

Ground :: struct {
	h, steep: f32,   // elevation, and how steep the ground is there, rise over run
	base:     f32,   // height of the rock stack's base under it (rock.odin)
	water:    f32,   // level of the river or sea standing here, or NO_WATER
	cover:    Mat,   // river gravel, the loose rock lying under a face, or the stones of a shore; Air for none
	fallen:   f32,   // depth of the loose rock fallen from a face, under any gravel
	laid:     f32,   // depth of the sand or stones the waves have laid on a shore
}

REPOSE     :: 0.67   // loose rock comes to rest at about 34°
SOIL_HOLDS :: 1.3    // and soil holds on ground up to about 52°, rise over run: forest to 45° and scrub clinging above it

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
ledges :: proc(h, steep, base: f32, x, z, cell: f64) -> (l: Ledge) {
	l.h, l.rise = h, 1
	y := h - base - STACK_LO
	n := int(rocks.bed[clamp(int(y), 0, STACK_LEN - 1)])
	if n == 0 || n + 2 >= len(rocks.beds) do return
	bed, floor := rocks.beds[n], rocks.floor[n]
	fade := band(2*f64(bed.thick/max(steep, 0.1)), cell)
	// A tread on this bed's top: under a weaker bed, or on a thick hard bed standing at the
	// steepest slope it holds, which breaks as a face whatever lies above it.
	massive := smoothstep(0.4, 0.6, MATERIALS[bed.kind].strength)*smoothstep(25, 40, bed.thick)*smoothstep(0.85, 1, steep/rocks.law[bed.kind].limit)
	// A bed is not equally strong all along: it stands as a face only in stretches, most of the
	// way along the strongest rocks and about a third of the way along the least of the strong, and
	// between them the hillside runs smooth through it under scrub. So a hill wears crags and
	// bluffs, not a wall round it at every strong bed.
	stands :: proc(n: int, x, z, cell: f64) -> f32 {
		return smoothstep(0, 0.15, fbm(x, z, 320, cell, 2, seed + 420 + u32(n)) - 0.25 + 2*(MATERIALS[rocks.beds[n].kind].strength - 0.6))
	}
	top := fade*max(ledge(bed.kind, rocks.beds[n + 1].kind, steep), massive)*stands(n, x, z, cell)
	foot := fade*ledge(rocks.beds[n - 1].kind, bed.kind, steep)*stands(n - 1, x, z, cell)   // a tread at its foot, on the bed below's top
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
	if face := fade*max(ledge(above, rocks.beds[n + 2].kind, steep), smoothstep(0.9, 1.1, steep/max(rocks.law[above].limit, SOIL_HOLDS)))*stands(n + 1, x, z, cell); face > 0 {
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
	level := clamp(int(math.log2(cell)) - 4, 0, len(land.z) - 1)   // the land's grid as coarse as the cell, or its finest
	steep = max(land_at(land.slope, land.n, x, z), 0)
	base = rock_base(x, z, cell)
	l = ledges(land_at(land.z[level], land.n >> uint(level), x, z) - back*steep, steep, base, x, z, cell)
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
	if l.lift > 0 do g.cover, g.fallen = MATERIALS[l.face].loose, l.lift
	// Small rises and hollows the simulation is too coarse to hold: more on slopes, none at
	// the shore, and none on a ledged face or loose rock, whose shapes have their own causes.
	h := l.h + fbm(x, z, 70, cell, 3, seed + 80)*(0.5 + 2.2*min(steep, 1))*smoothstep(0, 3, l.h)*min(l.rise, 1)*(1 - smoothstep(0, 1, l.lift))
	// A lake or pond stands at its level over the ground below it in its cells and the cells round
	// them, where its shore lies. Beyond them the ground stands as a bank that holds it, as at a
	// river; only its outlet stream is cut through. A river reaching it never raises its bed.
	// Blocks of the cap lie where the slide left them, as large as a room or a house: one in
	// about six of the 7 m squares of its debris, more where it lies thick.
	if t := slid_at(x, z); t > 2 && cell <= 2 {
		gx, gz := i32(math.floor(x/7)), i32(math.floor(z/7))
		if r := hash(gx, gz, seed + 710); f32(r & 0xFF)/255 < min(t/60, 0.3) {
			size := 2 + f64((r >> 8)%4)
			bx, bz := f64(gx)*7 + size/2 + f64((r >> 12)%u32(8 - size)), f64(gz)*7 + size/2 + f64((r >> 16)%u32(8 - size))
			// Its corners are worn and its top is humped, longer one way than the other: a box reads as built.
				u, v := (x - bx)/(size/2), (z - bz)/(size/2)*(1.5 if (r >> 28) & 1 == 0 else 0.7)
				if q := f32(u*u*u*u + v*v*v*v); q < 1 do h, g.cover, g.fallen = h + f32(1 + (r >> 20)%u32(size))*math.sqrt(1 - q) + 0.5, landslide.rock, 1
		}
	}
	h, g.laid = waters_edge(h, x, z, cell)
	lake, inside, bank := lake_near(x, z)
	h = max(h, bank)
	gravel: bool
	g.h, gravel, g.water = river_cut(h, x, z, cell)
	if inside {
		g.h, gravel = min(g.h, h), false
		if g.h < lake do g.h, g.water = max(g.h, lake - 1) if cell > 1 else g.h, lake   // far off, a lake's bed is drawn flat under it, so its cells do not show through
	}
	g.steep = steep*l.rise
	if g.laid > 0 do g.cover = MATERIALS[rock_in(g.h - g.laid - 0.5, base, rock_level(cell))].loose
	if gravel do g.cover = .Gravel
	if t, rubble := stack_at(x, z, cell, g.h, base); t > g.h {   // a stack is bare rock to its top
		if rubble do g.laid, g.cover = g.laid + t - g.h, MATERIALS[rock_in(g.h - 0.5, base, rock_level(cell))].loose
		else do g.steep = 3
		g.h, g.water = t, NO_WATER
	}
	if g.h < SEA_SURFACE do g.water = max(g.water, SEA_SURFACE)
	return
}

// ---- the shore -----------------------------------------------------------------------------

// What the waves leave at the water's edge (ground-and-underground.md §4, the beach and platform
// rows), from how open the shore is to the swell (`surf`) and how much of the sand its rivers bring
// they leave it (`sand-kept`). Where they leave sand, it lies as a beach: a flat berm as high as
// the waves run up, wider the more sand there is, and a face falling to the sea at the angle sand
// rests at under them. Where they leave none, they throw stones into a bank that is higher and
// steeper the more open the shore. Either is laid over the ground the forming left where that is
// steeper than its face, and neither stands under a sheer cliff or on a shore the swell breaks on.
// There the waves have cut the rock flat at the sea's level, with pools where it is worn deeper,
// and boulders too large for them to move lie along the foot of what stands over it.
CARRY :: 2.5 // the sand a shore loses to the swell, against the supply from a mouth (land_local)

sand_kept :: proc(x, z: f64) -> f32 {
	return land_at(land.supply, land.n, x, z) - CARRY*land_at(land.surf, land.n, x, z)
}

waters_edge :: proc(h: f32, x, z, cell: f64) -> (top, laid: f32) {
	top = h
	if h > 6 || h < -8 do return
	surf := land_at(land.surf, land.n, x, z)
	if surf < 0.01 do return
	slope := max(land_at(land.slope, land.n, x, z), 0.02)
	// A bench at the sea's level under steep ground, where the waves cut the foot of a cliff back,
	// with gullies and pools along the strike of the beds, where they found a weakness. A gentle
	// shore has none: the land runs down into the sea, and the rock the forming cut lies under it.
	if open := smoothstep(0.1, 0.2, surf)*smoothstep(0.45, 0.8, slope); open > 0 {
		along := rock_strike(x, z)
		u, v := x*along.x + z*along.y, z*along.x - x*along.y
		flat := 0.2 + 0.9*fbm(u/2, v, 10, cell, 3, seed + 740) - (1.3 if fbm(u/4, v, 5, cell, 2, seed + 741) < -0.2 else 0)
		top += open*smoothstep(-4.5, -2.5, h)*max(flat - h, 0)
	}
	sand := smoothstep(-0.05, 0.05, sand_kept(x, z))
	berm := 1.2 + 6*surf*(1 - sand) + 0.3*fbm(x, z, 60, cell, 2, seed + 742)
	face := math.lerp(f32(0.22), 0.06, sand)
	out := max(berm - top, 0)/slope - 30*sand*clamp(sand_kept(x, z), 0, 0.5)   // metres seaward of the berm's edge
	TOE :: -2.5   // the face reaches down to here, and the bank ends in a steep front under the water
	s := berm - face*max(out, 0)
	if s < TOE do s = TOE - 0.6*(TOE - s)/face
	if s > top do laid = (s - top)*(1 - smoothstep(0.8, 1.5, slope))*(1 - smoothstep(0.2, 0.3, surf))
	top += laid
	if cell <= 2 {
		// Boulders lie in heaps along the foot of what stands over the platform, larger under a cliff.
		chance := smoothstep(0.15, 0.3, surf)*smoothstep(0.6, 1.2, top)*(1 - smoothstep(3, 6, top))*smoothstep(-0.3, 0.1, fbm(x, z, 40, cell, 2, seed + 743))
		if b := stones(x, z, 0.45*chance, 1 + 0.6*smoothstep(0.4, 1.5, slope)); b > 0 do top, laid = top + b, laid + b
	}
	return
}

// Stones on a 3 m grid: in each square, with this chance, one of about this radius in metres,
// rounded, the tallest where two meet, so that they lie in heaps.
stones :: proc(x, z: f64, chance, size: f32) -> (h: f32) {
	if chance <= 0 do return
	gx, gz := i32(math.floor(x/3)), i32(math.floor(z/3))
	for j in gz - 1..=gz + 1 do for i in gx - 1..=gx + 1 {
		r := hash(i, j, seed + 730)
		if f32(r & 0xFF)/255 >= chance do continue
		rad := size*(1.3 + f32((r >> 8) & 0xFF)/255)   // none so small that it is one block, which reads as a box
		dx, dz := f32(x) - (f32(i)*3 + 3*f32((r >> 16) & 0xFF)/255), f32(z) - (f32(j)*3 + 3*f32(r >> 24)/255)
		if q := (dx*dx + dz*dz)/(rad*rad); q < 1 do h = max(h, rad*math.sqrt(1 - q))
	}
	return
}

height_at :: proc(x, z, cell: f64) -> f32 {
	return ground(x, z, cell).h
}

// What covers the ground, as an ordered catalogue: the first row whose host holds is the
// surface. Air brings the rock itself: what has fallen there, or else the bed.
// Forest holds on ground up to about 45° and scrub clings to about 52°, as on real flanks in a
// wet climate; only a face steeper than that is bare, which a weak rock makes only where the sea
// undercuts it or as the riser of a ledge.
Surface :: struct {
	name, why: string,
	brings:    Mat,
	host:      []Window,
}

SURFACES := [?]Surface{
	{"river gravel", "a river lays gravel on its bars and its bed", .Gravel, {{.Gravel, 0, ANY, 0}}},
	{"sand", "the waves keep the sand the rivers bring where the shore is sheltered enough", .Sand, {{.Beach, 0.3, ANY, 0}, {.Sand_Kept, 0, ANY, 0}}},
	{"boulders", "the swell breaks on this shore and leaves only stones too large for it to move", .Air, {{.Beach, 0.3, ANY, 0}, {.Surf, 0.25, ANY, 0}}},
	{"shingle", "the waves round the stones the shore gives them and throw them up in a bank", .Shingle, {{.Beach, 0.3, ANY, 0}}},
	{"washed rock", "the waves wash the rock bare to this height, and a little way under the sea, where sand cannot settle for them", .Air, {{.Surf, 0.1, ANY, 0}, {.Washed, 0, ANY, 0}, {.Height, -1.5, ANY, 0}}},
	{"lake bed", "silt settles out of the still water of a lake or pond", .Silt, {{.Under_Water, 0, ANY, 0}}},
	{"loose rock", "rock fallen from the face above lies at its angle of rest", .Air, {{.Fallen, 0, ANY, 0}}},
	{"bare rock", "soil cannot hold on ground this steep, so the beds show", .Air, {{.Too_Steep, 0, ANY, 0}}},
	{"sea floor", "sand settles under the sea where the waves do not stir it", .Sand, {{.Height, -ANY, 0.5, 0}}},
	{"bare scar", "a slide stripped the hillside to the rock, and no soil has yet weathered back", .Air, {{.Disturbed, -ANY, 1e4, 0}, {.Slid, -ANY, -0.5, 0}, {.Soil_Depth, -ANY, 0.15, 0}}},
	{"trail", "animals have trodden a path through the plants to the earth", .Dirt, {{.Trail, -ANY, 0.75, 0}}},
	{"soil", "soil holds, and the plants cover it", .Grass, {}},   // the plant community brings what covers it
}

// Sand and shingle are ground from the island's rock: black from basalt and scoria (Miyakejima,
// Ōshima), pale from every other (Kōzushima's rhyolite, Kikaijima's coral, sandstone).
shore_of :: proc(m, bed: Mat) -> Mat {
	if bed != .Basalt && bed != .Scoria do return m
	return .Black_Sand if m == .Sand else .Black_Shingle if m == .Shingle else m
}

surface_row :: proc(p: ^Point) -> int {
	for r, i in SURFACES do if host(r.host, p) > 0 do return i
	return len(SURFACES) - 1
}

// What the ground is at a point, what covers it, and the plant community growing there, if
// soil holds.
surface_at :: proc(x, z, cell: f64, at: ^Point = nil) -> (g: Ground, m: Mat, plants: Maybe(Community_Kind)) {
	p := point_at(x, z, cell)
	defer if at != nil do at^ = p
	row := surface_row(&p)
	m = SURFACES[row].brings
	if row == len(SURFACES) - 1 {
		k, _ := community_at(x, z, cell)
		m, plants = COMMUNITIES[k].cover, k
	}
	if m == .Air do m = p.cover if p.cover != .Air else rock_in(p.h - 0.5, p.base, rock_level(cell))
	if m == .Sand || m == .Shingle do m = shore_of(m, rock_in(p.h - p.laid - 0.5, p.base, rock_level(cell)))
	return p.g, m, plants
}

// ---- soil and plants ----------------------------------------------------------------------

// What the soil is, as an ordered catalogue over the land's fields: the first row whose host
// holds. A row gives the block under the cover, the blocks below it, and the last block before
// the rock, and how many of them are stones broken from the bed beneath. How deep the soil lies
// is a field of its own (`soil-depth`, land_local).
Soil :: struct {
	name, why:       string,
	top, sub, foot:  Mat,
	stones:          f32,
	host:            []Window,
	colour:          [3]f32,   // on the map
}

SOILS := [?]Soil{
	{"river silt", "floods lay silt over the gravel of old bars", .Silt, .Silt, .Gravel, 0, {{.Cold, -ANY, 2.5, 0}, {.Slope, -ANY, 0.15, 0}}, {0.35, 0.35, 0.40}},
	{"shore sand", "the wind blows sand in off the beach", .Sand, .Sand, .Sand, 0, {{.Inland, -ANY, 120, 0}, {.Cold, -ANY, 10, 0}}, {0.95, 0.85, 0.55}},
	{"stony wash", "soil creeping down a steep slope carries stones broken from the beds", .Loam, .Dirt, .Dirt, 0.35, {{.Slope, 0.65, ANY, 0}}, {0.60, 0.55, 0.50}},
	{"ash soil", "ash and cinders weather into a black soil full of humus", .Ash, .Ash, .Dirt, 0.1, {{.Volcanic, 0.5, ANY, 0}}, {0.22, 0.18, 0.17}},
	{"red soil", "long rain on old dry ground leaches it to a red clay", .Loam, .Red_Clay, .Red_Clay, 0, {{.Humped, 3, ANY, 0}, {.Wetness, -ANY, 0.3, 0}}, {0.85, 0.40, 0.22}},
	{"brown forest soil", "fallen leaves rot into loam over the weathered rock", .Loam, .Dirt, .Dirt, 0, {}, {0.42, 0.34, 0.26}},
}

soil_at :: proc(p: ^Point) -> (row: int, depth: f32) {
	for r, i in SOILS do if host(r.host, p) > 0 do return i, FIELDS[.Soil_Depth].at(p)
	return len(SOILS) - 1, FIELDS[.Soil_Depth].at(p)
}

// A species: its bark and leaf blocks, the envelope its crown fills, its height to the crown's
// top and the crown's radius in metres, and how the tree grower (grow) builds it: stems from
// the ground, which fork into limbs or keep a leader the limbs leave in tiers, each limb carrying
// a lobe of leaves at its end. The cast is the evergreen wood of the warm islands of southern
// Japan, and the forms are from docs/interesting-world/notes/real-vegetation.md.
Tree_Kind :: enum u8 { Tabu, Shii, Camellia, Hisakaki, Pine, Scrub, Alder }
Species :: struct {
	name:           string,
	bark, leaf:     Mat,
	crown:          enum u8 { Broad, Dome, Oval, Flat, Bush },   // the envelope, which far crowns draw
	height, radius: [2]i32,
	stems:          [2]i32,   // stems from the ground
	fork:           f32,      // share of the height where a stem gives out into its limbs, or where a leader's first tier leaves it
	leader:         bool,     // the stem goes on to the top and the limbs leave it in tiers, nearly level
	limbs:          [2]i32,   // limbs on each stem
	reach:          f32,      // how far out a limb carries its lobe, as a share of the crown's radius
	lobe:           f32,      // the lobe's radius, as a share of the crown's radius
	squash:         f32,      // its depth over its width
	lean:           f32,      // how far the crown moves toward the open, as a share of the height
	wind:           f32,      // how far it bends downwind and is cut back on the windward side, fully exposed
	crook:          f32,      // metres a stem wanders from straight
}

SPECIES := [Tree_Kind]Species{
	// Machilus: a stout trunk forking into heavy spreading limbs under a broad dark dome
	.Tabu     = {"tabu", .Wood, .Leaves, .Broad, {14, 20}, {5, 5}, {1, 1}, 0.3, false, {3, 5}, 0.75, 0.5, 0.8, 0.06, 0.05, 0.2},
	// Castanopsis: a short thick bole forking low into great ascending limbs, a dense crown of rounded lumps
	.Shii     = {"shii", .Shii_Bark, .Shii_Leaves, .Dome, {13, 19}, {3, 5}, {1, 1}, 0.3, false, {3, 5}, 0.55, 0.55, 0.8, 0.06, 0.05, 0.2},
	// much-branched from low down, a dense dark oval. In blocks every tree stands on one stem: two or
	// three a block apart read as a wall, so the species that grow in clumps fork low instead
	.Camellia = {"camellia", .Grey_Bark, .Camellia_Leaves, .Oval, {5, 9}, {2, 2}, {1, 1}, 0.35, false, {2, 3}, 0.35, 0.65, 1.2, 0.05, 0, 0.2},
	// Eurya: a thin stem with level spreading branches and an open, uneven crown
	.Hisakaki = {"hisakaki", .Grey_Bark, .Hisakaki_Leaves, .Broad, {4, 8}, {2, 3}, {1, 1}, 0.4, false, {2, 3}, 0.8, 0.45, 0.9, 0.08, 0.15, 0.3},
	// a crooked bare trunk to the top, with a few long level limbs carrying flat plates of needles
	.Pine     = {"black pine", .Pine_Bark, .Pine_Needles, .Flat, {10, 15}, {3, 5}, {1, 1}, 0.6, true, {2, 4}, 0.8, 0.55, 0.3, 0.1, 0.2, 0.5},
	// tobira and other bushes, rounded from the ground up, cut into a wedge by the wind
	.Scrub    = {"scrub", .Wood, .Scrub_Leaves, .Bush, {1, 3}, {1, 2}, {1, 1}, 0, false, {0, 0}, 0, 1, 1, 0, 0.6, 0},
	// Alnus sieboldiana: a sinuous grey stem forking low, spreading limbs, a rounded crown
	.Alder    = {"alder", .Grey_Bark, .Scrub_Leaves, .Dome, {6, 10}, {2, 3}, {1, 1}, 0.35, false, {2, 3}, 0.6, 0.55, 0.8, 0.1, 0.1, 0.4},
}
LEAVES :: bit_set[Mat]{.Leaves, .Shii_Leaves, .Camellia_Leaves, .Hisakaki_Leaves, .Pine_Needles, .Scrub_Leaves}   // seen through, near by: the gaps in their tiles are clear
PLANT_BLOCKS :: bit_set[Mat]{.Wood, .Leaves, .Shii_Bark, .Shii_Leaves, .Grey_Bark, .Camellia_Leaves, .Hisakaki_Leaves, .Pine_Bark, .Pine_Needles, .Scrub_Leaves}

// The plant communities, which compete for ground in a race (race, fields.odin). A row brings
// how thickly trees stand (the share of 6 m squares with one), how many of those squares have a
// bush under the trees as well, the species in their shares, what covers the ground between
// them, and its colour on the map.
Community_Kind :: enum u8 { Valley, Slope, Ridge, Windy, Coast, Fresh, Alder, Young }
Community :: struct {
	name, why:       string,
	weight, patch:   f32,          // its weight in the race, and the size of its patches, metres
	hosts:           [][]Window,   // it takes the best of them; with none it holds everywhere
	density, bushes: f32,
	trees:           [len(Tree_Kind)]f32,   // tabu, shii, camellia, hisakaki, pine, scrub, alder
	cover:           Mat,
	colour:          [3]f32,
}

COMMUNITIES := [Community_Kind]Community{
	.Valley = {"valley forest", "tall tabu trees stand in the deep moist soil of valley floors and hollows", 4, 150,
		{{{.Cold, -ANY, 3, 3}, {.Slope, -ANY, 0.2, 0.1}}, {{.Humped, -ANY, -8, 4}, {.Wetness, 0.35, ANY, 0.1}}}, 0.7, 0.08, {0.8, 0.2, 0, 0, 0, 0, 0}, .Grass, {0.45, 0.85, 0.30}},
	.Slope = {"laurel forest", "shii and tabu close over the slopes wherever nothing else does better, with camellia under them", 1, 400,
		{}, 0.85, 0.1, {0.15, 0.7, 0.15, 0, 0, 0, 0}, .Litter, {0.10, 0.42, 0.16}},
	.Ridge = {"ridge wood", "a low wood of small-leaved evergreens and pine holds dry humps and thin soil over rock", 3, 250,
		{{{.Humped, 4, ANY, 3}, {.Wetness, -ANY, 0.25, 0.1}}, {{.Soil_Depth, -ANY, 0.5, 0.25}}}, 0.6, 0.1, {0, 0.1, 0.1, 0.6, 0.2, 0, 0}, .Litter, {0.20, 0.55, 0.60}},
	.Windy = {"susuki grass and scrub", "sea wind and salt keep the trees out: tall grass, dwarf bamboo and wind-cut bushes", 4, 200,
		{{{.Exposure, 0.8, ANY, 0.08}}}, 0.35, 0, {0, 0, 0, 0.1, 0.05, 0.85, 0}, .Susuki, {0.80, 0.80, 0.45}},
	.Coast = {"coast strand", "salt and blown sand behind the shore: black pine and tobira scrub over dune grass", 5, 150,
		{{{.Inland, -ANY, 50, 40}, {.Cold, -ANY, 12, 8}}}, 0.3, 0, {0, 0, 0, 0, 0.55, 0.45, 0}, .Dune, {0.95, 0.85, 0.45}},
	// Raw ground a slide laid bare is taken first by susuki, then by alder, then by a young wood
	// of tabu, and the old forest of shii is back after some eight centuries (Miyakejima's lava
	// flows of known age; interesting-world/notes/real-vegetation.md).
	.Fresh = {"susuki on raw ground", "susuki grass is first onto rock and rubble a slide laid bare", 40, 60,
		{{{.Disturbed, -ANY, 30, 30}}}, 0.04, 0, {0, 0, 0, 0, 0, 1, 0}, .Susuki, {1.00, 0.55, 0.55}},
	.Alder = {"alder scrub", "alders follow the grass onto raw ground and shade it for the forest to return", 12, 80,
		{{{.Disturbed, -ANY, 120, 180}}}, 0.6, 0.1, {0, 0, 0, 0, 0, 0.2, 0.8}, .Susuki, {0.80, 1.00, 0.30}},
	.Young = {"young wood", "tabu and small evergreens grow up through the alders, a darker and lower wood than the old forest round it", 8, 100,
		{{{.Disturbed, -ANY, 400, 500}}}, 0.8, 0.12, {0.45, 0, 0.1, 0.25, 0, 0, 0.2}, .Litter, {0.30, 0.65, 0.55}},
}
COVERS :: bit_set[Mat]{.Grass, .Litter, .Susuki, .Dune, .Dirt}   // and the earth of a trail
crowns: [Community_Kind]f32   // the mean radius of a community's crowns, metres
@(init) crowns_init :: proc "contextless" () {
	for com, k in COMMUNITIES do for share, s in com.trees do crowns[k] += share*f32(SPECIES[Tree_Kind(s)].radius[0] + SPECIES[Tree_Kind(s)].radius[1])/2
}

// The community at a point: the race's winner on the land's grid, read a little way off by
// noise, so its edges wander over 10 to 50 m rather than follow the grid. And the cell read.
community_at :: proc(x, z, cell: f64) -> (Community_Kind, int) {
	c := land_cell(x + 24*f64(fbm(x, z, 40, cell, 2, seed + 600)), z + 24*f64(fbm(x, z, 40, cell, 2, seed + 601)))
	if land.community[c] == 255 do c = land_cell(x, z)
	return Community_Kind(land.community[c]) if land.community[c] != 255 else .Coast, c
}

// Run the race on every land cell once the land is formed, and print each community's share.
plants_init :: proc() {
	started := time.now()
	n := land.n
	land.community, land.age = make([]u8, n*n), make([]f32, n*n)
	soil := make([]u8, n*n, context.temp_allocator)   // each cell's row in SOILS
	shared(n, rows(n), &soil, proc(soil: ^[]u8, lo, hi: int) {
		n := land.n
		for c in lo*n..<hi*n {
			land.community[c] = 255
			if land.grid.sea[c] do continue
			p := Point{x = (f64(c%n) + 0.5)*LAND_CELL - region.size/2, z = (f64(c/n) + 0.5)*LAND_CELL - region.size/2, cell = LAND_CELL}
			k, _, _ := race(&p)
			land.community[c] = u8(k)
			land.age[c] = stand_draw(p.x, p.z, c)
			row, _ := soil_at(&p)
			soil[c] = u8(row)
		}
	})
	count, soils, ages := [Community_Kind]int{}, [len(SOILS)]int{}, [3]int{}
	for c in 0..<n*n do if !land.grid.sea[c] {
		ages[0 if land.age[c] < 50 else 1 if land.age[c] < 200 else 2] += 1
		count[Community_Kind(land.community[c])] += 1
		soils[soil[c]] += 1
	}
	fmt.printf("plants in %.0f ms:", time.duration_milliseconds(time.since(started)))
	for k, i in count do fmt.printf(" %s %.0f%%", COMMUNITIES[i].name, 100*f32(k)/f32(len(land.grid.order)))
	fmt.print("; soil:")
	for k, i in soils do fmt.printf(" %s %.0f%%", SOILS[i].name, 100*f32(k)/f32(len(land.grid.order)))
	fmt.printfln("; stands: young (under 50 years) %.0f%%, middle %.0f%%, old (200 and more) %.0f%%", 100*f32(ages[0])/f32(len(land.grid.order)), 100*f32(ages[1])/f32(len(land.grid.order)), 100*f32(ages[2])/f32(len(land.grid.order)))
}

// ---- trees --------------------------------------------------------------------------------

Tree :: struct {
	x, z:   i32,   // block the trunk stands on
	base:   i32,   // elevation of the ground there
	height: i32,   // to the crown's top, over the base; of a fallen trunk, its length
	radius: i32,   // of the crown
	kind:   Tree_Kind,
	form:   Tree_Form,
	fall:   [2]f32,   // a fallen trunk: the way it lies from its stump
	open:   [2]f32,   // how far the crown's middle stands off the trunk, toward the light and downwind, metres
	wind:   [2]f32,   // downwind, times how open the tree's place is to the wind
}
// Its place in the stand. Only canopy trees and the trees between them are drawn far off; small
// trees under the canopy, standing dead trunks and fallen ones are drawn only near by.
Tree_Form :: enum u8 { Canopy, Between, Under, Dead, Fallen }

TREE_GRID   :: 3     // at most one tree stands in a square of this many metres
TREE_REACH  :: 6     // the farthest a crown reaches from its trunk
CROWNS_MEET :: 0.75 // a crown's radius is at most this share of the spacing, so neighbours' crowns interlock
FALLEN     :: 8    // the longest fallen trunk, and its stump

// How storms age the woods (foundations/vegetation.md, D3 and D6). The land's grid is cut into
// stands round middles `across` metres apart, the reach of each drawn from the seed, and each has
// the years since a typhoon last threw its canopy, drawn from the seed with the storms coming more
// often to ground open to the wind: young stands gather on windward slopes and crests, old ones in
// sheltered valleys. Ground a slide laid bare is as old as the slide. A young stand is many thin
// trees close together; as it ages the trees grow and the fastest shade out their neighbours, until
// the canopy trees stand `spacing[1]` apart with smaller trees between and beneath them, and gaps
// open where one or a group was thrown, with the trunks lying the way the wind blew.
// The figures are from interesting-world/notes/real-vegetation.md, "Stands".
Stand_Rule :: struct {
	across:   f64,      // metres between the middles of neighbouring stands
	interval: [2]f32,   // mean years between storms that throw a stand's canopy, on sheltered ground and on ground fully exposed
	spacing:  [2]f32,   // metres between canopy trees in a stand just thrown and in an old one
	grows:    f32,      // years for a stand's trees to grow most of the way to their full height
	thins:    f32,      // years for its canopy to thin most of the way to the old spacing
	gaps:     f32,      // share of an old stand's ground in gaps, each where a tree or a group fell
	gap:      [2]f32,   // radius of a gap, metres
	refill:   f32,      // years a gap stays open before its young growth closes it
	between:  f32,      // share of the places between the canopy trees where a smaller tree stands
	snags:    f32,      // share of an old stand's canopy trees standing dead, as broken stubs
	young:    f32,      // share of the places in a gap where young growth has come up
	fallen:   f32,      // share of the canopy trees thrown in a gap whose trunk still lies, and as many again stand as stubs; the rest have rotted away
}
STANDS := Stand_Rule{across = 140, interval = {2000, 40}, spacing = {3.5, 7.5}, grows = 40, thins = 150, gaps = 0.2, gap = {4, 11}, refill = 50, between = 0.25, snags = 0.015, young = 0.2, fallen = 0.1}

// The land's cell a tree or a far cell reads its stand and community from: its own, with the
// edges dithered over 24 m by the hash `r`, so that two stands or communities mix along their edge.
dithered :: proc(x, z: f64, r: u32) -> int {
	return land_cell(x + f64(r & 0xFF)/10.6 - 12, z + f64((r >> 8) & 0xFF)/10.6 - 12)
}

// Which stand a point of the land's grid lies in, and its age: the stand whose middle is nearest
// for its reach, read a little way off by noise so the edges wander. A slide's ground is as old as
// the slide.
stand_draw :: proc(x, z: f64, c: int) -> f32 {
	x, z := x + 30*f64(fbm(x, z, 80, LAND_CELL, 2, seed + 622)), z + 30*f64(fbm(x, z, 80, LAND_CELL, 2, seed + 623))
	D := STANDS.across
	best, age := f64(1e9), f32(0)
	for j in i32(math.floor(z/D)) - 2..=i32(math.floor(z/D)) + 2 do for i in i32(math.floor(x/D)) - 2..=i32(math.floor(x/D)) + 2 {
		r := hash(i, j, seed + 620)
		mx, mz := (f64(i) + f64(r & 0xFF)/256)*D, (f64(j) + f64((r >> 8) & 0xFF)/256)*D
		if d := math.hypot(x - mx, z - mz)/(0.4 + 1.2*f64(r >> 24)/255); d < best {
			mc := land_cell(mx, mz)
			wind := land.exposed[mc if !land.grid.sea[mc] else c]
			best, age = d, -math.lerp(STANDS.interval[0], STANDS.interval[1], wind)*math.ln(max(hash01(i, j, seed + 621), 1e-4))
		}
	}
	if abs(land.slid[c]) > 0.5 do age = min(age, region.features[landslide.feature].age)
	return age
}

// What a stand of an age grows: metres between its canopy trees, the share of their full height
// they have reached, and how far it is from new to old, 0 to 1.
stand :: proc(age: f32) -> (spacing, tall, old: f32) {
	old = 1 - math.exp(-age/STANDS.thins)
	return math.lerp(STANDS.spacing[0], STANDS.spacing[1], old), 0.35 + 0.65*(1 - math.exp(-age/STANDS.grows)), old
}

// The gap a point lies in, if any: one may open in each 24 m square, the likelier the older the
// stand, so that gaps take `gaps` of an old stand's ground and a young one has none. It is where
// a canopy tree or a group fell the way the storm blew, `ago` years since.
GAP_TILE :: 24
gap_at :: proc(x, z: f64, old: f32) -> (inside: bool, fall: [2]f32, ago: f32) {
	a, b := STANDS.gap[0], STANDS.gap[1]
	chance := old*old*STANDS.gaps*GAP_TILE*GAP_TILE/(math.PI*(a*a + a*b + b*b)/3)
	gx, gz := i32(math.floor(x/GAP_TILE)), i32(math.floor(z/GAP_TILE))
	for j in gz - 1..=gz + 1 do for i in gx - 1..=gx + 1 {
		r := hash(i, j, seed + 630)
		if f32(r & 0xFF)/256 >= chance do continue
		mx, mz := (f64(i) + f64((r >> 8) & 0xFF)/256)*GAP_TILE, (f64(j) + f64((r >> 16) & 0xFF)/256)*GAP_TILE
		if math.hypot(x - mx, z - mz) < f64(math.lerp(a, b, f32(r >> 24)/255)) {
			bearing := math.to_radians(f32(region.shape.swell)) + 1.2*(hash01(i, j, seed + 631) - 0.5)   // downwind, give or take 35°
			return true, {-math.sin(bearing), math.cos(bearing)}, STANDS.refill*hash01(i, j, seed + 632)
		}
	}
	return
}

// The share of a community's ground its crowns cover at a canopy spacing, which is how much of the
// far canopy is leaf.
cover :: proc(k: Community_Kind, spacing: f32) -> f32 {
	r := min(crowns[k], CROWNS_MEET*spacing) + 0.5
	return min(COMMUNITIES[k].density*math.PI*r*r/(spacing*spacing)*(1 + 0.5*STANDS.between), 1)
}

// The share of the community's trees each species has, picked by a number in 0..1.
pick_species :: proc(k: Community_Kind, u: f32) -> Tree_Kind {
	u := u
	for share, s in COMMUNITIES[k].trees {
		u -= share
		if u < 0 do return Tree_Kind(s)
	}
	return .Shii
}

// Every tree whose trunk stands in a rectangle of blocks, and `near`, the small, dead and fallen as
// well, with the fallen whose trunks reach into it. The same tree is found whichever chunk or level
// of detail asks. Each 3 m square holds a candidate with a vigour; of the candidates whose crowns
// would meet at the stand's spacing, the most vigorous takes the canopy (after Deussen et al.
// 1998). One shaded only from beyond half that reach may stand between the canopy trees, smaller;
// one shaded from nearer is beneath them, a small tree or a bush if anything. In a gap the canopy
// trees lie fallen or stand dead and the rest is young growth.
trees_in :: proc(x0, z0, x1, z1: i32, out: ^[dynamic]Tree, near := false) {
	floor_div :: proc(a, b: i32) -> i32 { return (a - a %% b)/b }
	m := i32(FALLEN) if near else 0
	for gz in floor_div(z0 - m, TREE_GRID)..=floor_div(z1 + m, TREE_GRID) {
		for gx in floor_div(x0 - m, TREE_GRID)..=floor_div(x1 + m, TREE_GRID) {
			r := hash(gx, gz, seed + 140)
			x, z := gx*TREE_GRID + i32(r % TREE_GRID), gz*TREE_GRID + i32((r >> 4) % TREE_GRID)
			inside := x >= x0 && x <= x1 && z >= z0 && z <= z1
			if !inside && (x < x0 - m || x > x1 + m || z < z0 - m || z > z1 + m) || trail_near(f64(x) + 0.5, f64(z) + 0.5) < 2.5 do continue   // nothing grows within a stride of a trail
			fx, fz := f64(x) + 0.5, f64(z) + 0.5
			cell := dithered(fx, fz, r >> 8)
			if land.community[cell] == 255 do continue
			spacing, tall, old := stand(land.age[cell])
			gap, fall, ago := gap_at(fx, fz, old)
			if !inside && !gap do continue   // from beyond the rectangle only a fallen trunk reaches into it
			reach, v, shade := 0.56*spacing, hash01(gx, gz, seed + 141), f32(0)   // canopy trees `spacing` apart on average
			k := i32(math.ceil(reach/TREE_GRID))
			for j in gz - k..=gz + k do for i in gx - k..=gx + k do if hash01(i, j, seed + 141) > v {
				q := hash(i, j, seed + 140)
				dx, dz := f32(i*TREE_GRID + i32(q % TREE_GRID) - x), f32(j*TREE_GRID + i32((q >> 4) % TREE_GRID) - z)
				shade = max(shade, 1 - math.sqrt(dx*dx + dz*dz)/reach)
			}
			u := hash(gx, gz, seed + 142)
			form: Tree_Form
			switch {
			case shade == 0 && gap: form = .Fallen if f32(u%1000)/1000 < STANDS.fallen else .Dead if f32(u%1000)/1000 < 2*STANDS.fallen else .Under
			case shade == 0:        form = .Dead if f32(u%1000)/1000 < old*STANDS.snags else .Canopy
			case gap:               form = .Under
			case shade < 0.5:       form = .Between if f32(u%1000)/1000 < STANDS.between else .Under
			case:                   form = .Under
			}
			if !near && form > .Between || !inside && form != .Fallen do continue
			com := Community_Kind(land.community[cell])
			c := COMMUNITIES[com]
			if f32((u >> 10) & 0xFF)/255 >= (c.density if form != .Under else STANDS.young if gap else c.bushes) do continue
			p := point_at(fx, fz, 1)
			soil, g := surface_row(&p) == len(SURFACES) - 1, p.g
			t := Tree{x = x, z = z, base = i32(math.round(g.h)), form = form}
			// A young lake still has the trunks of the trees it drowned standing in it.
			if level, under, _ := lake_near(fx, fz); under && g.h < level && form <= .Between && region.features[landslide.feature].age < DROWNED {
				if (u >> 24)&1 == 0 do continue   // half have fallen
				t.height, t.kind, t.form = 5 + i32((u >> 16)%6), .Shii, .Dead
				append(out, t)
				continue
			}
			if !soil do continue
			t.kind = pick_species(com, hash01(gx, gz, seed + 143))
			if form == .Under && !gap && (u >> 18)&1 == 0 do t.kind = .Scrub   // a bush, or a sapling of the canopy's own trees
			sp, w := SPECIES[t.kind], hash(gx, gz, seed + 144)
			full := f32(sp.height[0] + i32(w % u32(sp.height[1] - sp.height[0] + 1)))*tall
			t.radius = clamp(i32(CROWNS_MEET*spacing + 0.5), 1, sp.radius[0] + i32((w >> 8) % u32(sp.radius[1] - sp.radius[0] + 1)))
			switch form {
			case .Canopy:  t.height = max(i32(full), 3)
			case .Between: t.height, t.radius = max(i32(0.65*full), 3), clamp(t.radius - 1, 1, 2)
			case .Under:   t.height, t.radius = clamp(i32(4 + ago/6) if gap else (1 + i32((w >> 16)%2) if t.kind == .Scrub else 4 + i32((w >> 16)%3)), 1, max(i32(full), 2)), 1   // a bush a walker sees over, or a sapling whose leaves begin over his head
			case .Dead:    t.height = clamp(i32(0.3*full), 2, 6)   // broken off by the storm that killed it
			case .Fallen:
				// In blocks a trunk lies along the grid, or it is a row of steps: a stump, a stride of
				// clear ground, and the trunk for as far as the ground stays level under it.
				t.fall = {math.round(fall.x), 0} if abs(fall.x) > abs(fall.y) else {0, math.round(fall.y)}
				for t.height < 4 + i32((w >> 16)%4) && i32(math.round(ground(fx + f64(t.fall.x)*f64(t.height + 2), fz + f64(t.fall.y)*f64(t.height + 2), 1).h)) == t.base do t.height += 1
				if t.height < 3 do t.height = 0
			}
			// Which way the crown reaches: away from stronger neighbours out to twice the reach of a
			// crown, toward a gap beside it, down the slope, where the light comes from, and downwind
			// as far as the place is open to the wind.
			if form <= .Between {
				push: [2]f32
				for j in gz - 2*k..=gz + 2*k do for i in gx - 2*k..=gx + 2*k do if hash01(i, j, seed + 141) > v {
					q := hash(i, j, seed + 140)
					d := [2]f32{f32(i*TREE_GRID + i32(q % TREE_GRID) - x), f32(j*TREE_GRID + i32((q >> 4) % TREE_GRID) - z)}
					if l := math.sqrt(d.x*d.x + d.y*d.y); l < 2*reach do push -= d/l*(1 - l/(2*reach))
				}
				for a in 0..<4 {
					d := [2]f32{f32(1 - a%2*2)*f32(a/2), f32(1 - a%2*2)*f32(1 - a/2)}
					if in_gap, _, _ := gap_at(fx + f64(d.x)*8, fz + f64(d.y)*8, old); in_gap do push += 1.5*d
				}
				bearing := math.to_radians(land.facing[cell])
				push += 0.8*min(land.slope[cell], 1)*[2]f32{math.sin(bearing), -math.cos(bearing)}
				if l := math.sqrt(push.x*push.x + push.y*push.y); l > 1 do push /= l
				swell := math.to_radians(f32(region.shape.swell))
				t.wind = land.exposed[cell]*[2]f32{-math.sin(swell), math.cos(swell)}
				if sp.crown != .Bush do t.open = (sp.lean*push + sp.wind*t.wind)*f32(t.height)   // a bush grows from its root, and the wind only cuts it
				if l, most := math.sqrt(t.open.x*t.open.x + t.open.y*t.open.y), f32(TREE_REACH - t.radius); l > most do t.open *= most/l
			}
			append(out, t)
		}
	}
}

// A tree's crown, as the height of its underside and its top over the tree's base, at a
// distance from the crown's middle (the trunk moved by `open`); the underside lies over the top
// outside it. The grower keeps a tree's leaves inside it, and the far crowns draw it.
envelope :: proc(t: Tree, d: f32) -> (under, over: f32) {
	r := f32(t.radius) + 0.5
	if d >= r do return 1, 0
	top, q := f32(t.height), math.sqrt(1 - d*d/(r*r))
	clear := min(3, top - 1)   // a tree's leaves begin over a walker's head, as its lower branches die in the shade
	switch SPECIES[t.kind].crown {
	case .Broad: return max(top - r*(1.9 - 0.4*q), clear), top - r*0.5*(1 - q)
	case .Dome:  return max(top - r*(1 + q), clear), top - r*0.8*(1 - q)
	case .Oval:  return max(top - r*1.2*(1 + q), clear), top - r*1.2*(1 - q)
	case .Flat:  return max(top - 0.45*top*q, clear), top - 1.5*(1 - q)
	case .Bush:  return 0, top*q
	}
	return 1, 0
}

// The crown's middle, from which the envelope is measured.
crown_at :: proc(t: Tree) -> [2]f32 {
	return {f32(t.x) + 0.5 + t.open.x, f32(t.z) + 0.5 + t.open.y}
}

// The tree grower (foundations/vegetation.md, D4 and section 5). One procedure grows every
// species from its row: each stem leans with the crown toward the open and wanders as the
// species does, then gives out into limbs, or goes on to the top as a leader and the limbs leave
// it in tiers. Each limb runs out to a lobe of leaves set inside the envelope, so the crown is a
// cluster of lobes whose lumps and gaps are the species' own, and the far crown is the same
// tree. Downwind the limbs are longer, and the wind cuts the windward side lower. Everything
// is drawn from the tree's own hash and its place, so every chunk grows the same tree.
// Blocks go into a volume whose block (0, 0, 0) is the world block `o`, over the ground in `c`.
grow :: proc(blocks: []u8, t: Tree, o: [3]i32, c: ^Columns) {
	layers := i32(len(blocks)/(P*P))
	put :: proc(blocks: []u8, layers: i32, p: [3]i32, m: Mat, replace: bool) {
		if p.x < 0 || p.x >= P || p.z < 0 || p.z >= P || p.y < 0 || p.y >= layers do return   // below y is this chunk's solid ground: a tree at a cliff's foot
		k := int(p.x) + int(p.z)*P + int(p.y)*P*P
		if replace || blocks[k] == 0 do blocks[k] = u8(m)
	}
	// A line of bark half a metre at a time, so it joins face to face where it runs aslant;
	// `thick` makes it two blocks across.
	line :: proc(blocks: []u8, layers: i32, o: [3]i32, a, b: [3]f32, m: Mat, thick: bool, replace: bool) {
		n := i32(2*max(abs(b.x - a.x), abs(b.y - a.y), abs(b.z - a.z))) + 1
		for s in 0..=n {
			f := f32(s)/f32(n)
			p := a + (b - a)*f
			at := [3]i32{i32(math.floor(p.x)), i32(math.floor(p.y)), i32(math.floor(p.z))} - o
			for k in 0..<(4 if thick else 1) do put(blocks, layers, at + {i32(k%2), 0, i32(k/2)}, m, replace)
		}
	}
	sp := SPECIES[t.kind]
	h := hash(t.x, t.z, seed + 150)
	draw :: proc(h: ^u32) -> f32 {   // the tree's own stream of numbers in 0..1
		h^ = h^*0x2C1B3C6D + 0x297A2D39
		return f32(h^ >> 8)/16777216
	}
	H, r := f32(t.height), f32(t.radius) + 0.5
	foot := [3]f32{f32(t.x) + 0.5, f32(t.base), f32(t.z) + 0.5}
	mid := crown_at(t)
	middle := [3]f32{mid.x, foot.y, mid.y}
	big := t.height >= 18 && t.form == .Canopy   // the tallest trees stand on a trunk two blocks across
	small := t.form >= .Between || t.height < 6   // crowns too small to carry limbs that show, and a dead stub
	stems := 1 if small else sp.stems[0] + i32(draw(&h)*f32(sp.stems[1] - sp.stems[0] + 1))
	limbs := 0 if small else sp.limbs[0] + i32(draw(&h)*f32(sp.limbs[1] - sp.limbs[0] + 1))
	clear := 0 if sp.crown == .Bush else min(f32(3), H - 1)
	turn := 2*math.PI*draw(&h)

	Lobe :: struct { at: [3]f32, a, b: f32 }
	lobes: [24]Lobe
	n := 0
	ends: [24][3]f32   // where each stem and limb gives out: leaves close over it whatever the wind has cut
	e := 0
	for s in 0..<stems {
		spread := [3]f32{math.cos(turn + 2*math.PI*f32(s)/f32(stems)), 0, math.sin(turn + 2*math.PI*f32(s)/f32(stems))}
		base := foot + (0.5*spread if s > 0 else 0) - {0, 1, 0}
		// Where the stem gives out, or for a leader its top. Stems of a clump splay apart.
		fork := max(sp.fork*H, min(4, H - 2)) if !sp.leader else H - 2
		if small do fork = max(H - 2, 1)   // under its crown's top
		end := foot + (middle - foot)*(fork/H) + {0, fork, 0}
		if stems > 1 do end += 0.35*r*spread
		// The stem in three lengths, each kinked aside by up to the species' crook.
		knee: [4][3]f32 = {base, 0, 0, end}
		for i in 1..=2 {   // the lean is taken low, so a leaning bole turns upright toward the crown
			f := f32(i)/3
			knee[i] = base + (end - base)*f + [3]f32{(end - base).x, 0, (end - base).z}*(math.sqrt(f) - f) + [3]f32{draw(&h) - 0.5, 0, draw(&h) - 0.5}*2*sp.crook*(0 if small || i == 1 else 1)   // straight where a walker passes
		}
		along :: proc(knee: [4][3]f32, f: f32) -> [3]f32 {   // the point a share f of the way up the stem
			i := clamp(int(f*3), 0, 2)
			return knee[i] + (knee[i + 1] - knee[i])*(f*3 - f32(i))
		}
		if sp.crown != .Bush do for i in 0..<3 do line(blocks, layers, o, knee[i], knee[i + 1], sp.bark, big && s == 0, true)
		if small || sp.leader {
			ends[e] = end
			e += 1
		}
		if small || sp.crown == .Bush {
			// One crown, as wide as the room it has over the clear bole is deep; a bush is a dome from
			// the ground, low at its edge.
			deep := (H - clear)/2 + 0.5
			if n < len(lobes) do lobes[n] = {middle + {0, clear + deep - 0.5, 0}, min(r - 0.3, deep + 0.5), deep} if sp.crown != .Bush else {middle, r - 0.3, H + 0.5}
			n += 1
			continue
		}
		// The limbs: from the fork, or from the leader in tiers up it.
		for l in 0..<limbs {
			az := turn + math.PI/f32(stems) + 2*math.PI*(f32(l) + 0.6*draw(&h))/f32(limbs)
			if stems > 1 do az = turn + 2*math.PI*f32(s)/f32(stems) + 0.9*math.PI*(draw(&h) - 0.5)   // each stem of a clump carries its own side of the crown
			dir := [3]f32{math.cos(az), 0, math.sin(az)}
			out := sp.reach*r*(0.75 + 0.5*draw(&h))*(1 + 0.6*(dir.x*t.wind.x + dir.z*t.wind.y))   // longer downwind
			a := sp.lobe*r*(0.8 + 0.4*draw(&h))
			b := a*sp.squash
			tip := middle + min(out, r - 0.9*a)*dir   // the lobe's middle stays well inside the envelope
			from := along(knee, 1 - 1.5*draw(&h)/fork)   // limbs leave over the stem's top metre and a half
			if sp.leader {
				f := (f32(l) + 0.5*draw(&h))/f32(limbs)
				from = along(knee, (sp.fork*H + (H - 2.5 - sp.fork*H)*f)/H)
				tip.y = from.y + 0.25*out
			} else {
				// Anywhere in the depth of the envelope at its distance, so the lobes stand at
				// different heights and the crown is lumpy and deep.
				d := math.sqrt((tip.x - mid.x)*(tip.x - mid.x) + (tip.z - mid.y)*(tip.z - mid.y))
				under, over := envelope(t, d)
				tip.y = foot.y + max(math.lerp(min(under + b, over - b), over - b, draw(&h)), clear + 0.7*b)   // and rounded underneath, over the clear bole
			}
			line(blocks, layers, o, from, tip - {0, 0.5*b, 0}, sp.bark, false, false)
			if e < len(ends) do ends[e] = tip - {0, 0.5*b, 0}
			e = min(e + 1, len(ends))
			if n < len(lobes) do lobes[n] = {tip, a, b}
			n += 1
			// The limb forks once near its end, and the twig carries a smaller lobe beside the first.
			if sp.leader do continue
			side := az + (0.5*math.PI if l%2 == 0 else -0.5*math.PI)*(0.6 + 0.6*draw(&h))
			twig := tip + 0.9*a*[3]f32{math.cos(side), (draw(&h) - 0.4)*sp.squash, math.sin(side)}
			if n < len(lobes) do lobes[n] = {twig, 0.75*a, 0.75*b}
			n += 1
		}
		// The top of the crown over the fork, or the leader's top plate.
		a := sp.lobe*r*(1.1 if sp.leader else 0.9)
		if n < len(lobes) do lobes[n] = {{mid.x, foot.y + H - a*sp.squash, mid.y}, a, a*sp.squash}
		n += 1
	}
	if t.form == .Dead || sp.crown == .Bush do e = 0
	for p in ends[:e] {
		at := [3]i32{i32(math.floor(p.x)), i32(math.floor(p.y)), i32(math.floor(p.z))} - o
		for d in ([5][3]i32{{0, 1, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}) do put(blocks, layers, at + d, sp.leaf, false)
	}
	if t.form == .Dead do return
	// The leaves: every lobe, its edge a little uneven, inside the envelope and over the clear
	// bole, and cut lower on the windward side.
	for lb in lobes[:min(n, len(lobes))] {
		lo := [3]i32{i32(math.floor(lb.at.x - lb.a)), i32(math.floor(max(lb.at.y - lb.b, foot.y + clear))), i32(math.floor(lb.at.z - lb.a))}
		hi := [3]i32{i32(math.ceil(lb.at.x + lb.a)), i32(math.ceil(min(lb.at.y + lb.b, foot.y + H))), i32(math.ceil(lb.at.z + lb.a))}
		if hi.x < o.x || lo.x >= o.x + P || hi.z < o.z || lo.z >= o.z + P do continue
		for y in lo.y..<hi.y do for z in lo.z..<hi.z do for x in lo.x..<hi.x {
			p := [3]f32{f32(x), f32(y), f32(z)} + 0.5
			d := (p - lb.at)/{lb.a, lb.b, lb.a}
			e := 1.02 - 0.08*hash01(x + y*57, z, seed + 180)
			if d.x*d.x + d.y*d.y + d.z*d.z > e*e do continue
			if (p.x - mid.x)*(p.x - mid.x) + (p.z - mid.y)*(p.z - mid.y) > r*r do continue   // inside the envelope, and so within reach of every chunk that grows the tree
			u := (p.x - mid.x)*t.wind.x + (p.z - mid.y)*t.wind.y   // metres downwind of the middle, times how exposed
			if p.y > foot.y + H - sp.wind*H*max(-u/r, 0) do continue
			if k := (z - o.z)*P + x - o.x; z >= o.z && z < o.z + P && x >= o.x && x < o.x + P && f32(y - c.top[k]) < clear do continue   // over a walker's head on the ground beneath as well
			put(blocks, layers, {x, y, z} - o, sp.leaf, false)
		}
	}
}

// ---- what the engine asks for -------------------------------------------------------------

// Whether a chunk of columns wider than COARSE lies wholly outside every island's region, in the open
// sea between them: under the sea such columns have no faces (mesh_columns), so nothing need be
// worked out for it.
open_sea :: proc(key: Key) -> bool {
	s := f64(i32(1) << u32(key.level))
	if s <= COARSE do return false
	lo := [2]f64{f64(key.x), f64(key.z)}*CHUNK*s
	for &f in formed {
		o, h := [2]f64{f64(f.island.origin.x), f64(f.island.origin.y)}, f.island.size/2
		if lo.x < o.x + h && lo.x + CHUNK*s > o.x - h && lo.y < o.y + h && lo.y + CHUNK*s > o.y - h do return false
	}
	return true
}

// The ground under a chunk at a level of detail. Beyond the nearest level, single trees are
// crowns hung over the ground on their trunks while cells are small enough to show them, then
// a canopy that is part of the columns. Each column is the island's whose region holds it, or
// the open sea's, whose floor lies level with every region's rim.
gen_columns :: proc(level, cx, cz: i32, c: ^Columns) {
	s := i32(1) << u32(level)
	cell := f64(s)
	heights: [P*P]f32
	for j in 0..<i32(P) {
		for i in 0..<i32(P) {
			ix, iz := cx*CHUNK + i - 1, cz*CHUNK + j - 1   // cell coordinates at this level, in the world
			k := j*P + i
			if !bind_at((f64(ix) + 0.5)*cell, (f64(iz) + 0.5)*cell) {
				heights[k], c.water[k], c.mat[k], c.top[k], c.ground[k] = SEA_BED, SEA_SURFACE, .Sand, SEA_BED, SEA_BED
				continue
			}
			x, z := (f64(ix) + 0.5)*cell - f64(region.origin.x), (f64(iz) + 0.5)*cell - f64(region.origin.y)
			p: Point
			g, m, plants := surface_at(x, z, cell, &p)
			heights[k], c.water[k], c.base[k], c.mat[k] = g.h, g.water, g.base, m
			if s == 1 do if kind, ok := plant_at(&p, m, plants); ok && g.water - g.h <= GROUND_PLANTS[kind].wet do c.plant[k] = u8(kind) + 1
			c.top[k] = i32(math.round(heights[k]))
			if heights[k] < SEA_SURFACE do c.top[k] = min(c.top[k], SEA_LEVEL - 1)   // what the land says is under the sea is drawn under it: a shoal is a shallow, not a raft of sand
			c.ground[k] = c.top[k]
			if s <= 8 do c.hollow[k] = hollow_at(x, z, cell)
			// The canopy: a cell is the leaf of a tree its community would grow, raised to about
			// the height of that tree's crown.
			if com, ok := plants.?; ok && s >= 8 {
				r := hash(i32(math.floor(x/cell)), i32(math.floor(z/cell)), seed + 160 + u32(level))
				spacing, tall, old := stand(land.age[dithered(x, z, r)])
				if gap, _, _ := gap_at(x, z, old); !gap && f32(r & 0xFFFF)/65536 < cover(com, spacing) {
					sp := SPECIES[pick_species(com, f32((r >> 16) & 0xFF)/256)]
					c.top[k] += i32(f32(sp.height[0] + i32((r >> 24) % u32(sp.height[1] - sp.height[0] + 1)))*tall) - 1
					c.mat[k] = sp.leaf
				}
			}
		}
	}
	// The slope of the ground before it was cut into blocks. Light uses it so that a
	// hillside shades as a hillside and not only as a staircase. Crowns keep zero.
	for j in 1..<P - 1 {
		for i in 1..<P - 1 {
			k := j*P + i
			if c.top[k] > c.ground[k] do continue
			gx := (heights[k + 1] - heights[k - 1])/f32(2*s)
			gz := (heights[k + P] - heights[k - P])/f32(2*s)
			inv := 127/math.sqrt(gx*gx + gz*gz + 1)
			c.slope[k] = {u8(128 - gx*inv), u8(128 - gz*inv)}
		}
	}
	if (level == 1 || level == 2) && bind_at(f64((cx*CHUNK + CHUNK/2)*s), f64((cz*CHUNK + CHUNK/2)*s)) {   // the trees of the island under the chunk's middle
		trees := make([dynamic]Tree, context.temp_allocator)
		x0, z0 := (cx*CHUNK - 1)*s - region.origin.x, (cz*CHUNK - 1)*s - region.origin.y
		trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P*s + TREE_REACH, z0 + P*s + TREE_REACH, &trees)
		for t in trees {
			if t.form > (.Between if level == 1 else .Canopy) do continue   // past half a kilometre only the canopy trees: the ones between them are smaller than a cell there
			mid := crown_at(t)
			for j in max((t.z - TREE_REACH - z0)/s, 0)..=min((t.z + TREE_REACH - z0)/s, P - 1) {
				for i in max((t.x - TREE_REACH - x0)/s, 0)..=min((t.x + TREE_REACH - x0)/s, P - 1) {
					dx := f32(x0 + i*s) + f32(s)/2 - mid.x
					dz := f32(z0 + j*s) + f32(s)/2 - mid.y
					k := j*P + i
					lo, hi := envelope(t, math.sqrt(dx*dx + dz*dz))
					under, over := max(t.base + i32(math.round(lo)), c.ground[k]), t.base + i32(math.round(hi))
					if over <= under do continue
					if c.crown[k][1] > c.crown[k][0] do under, over = min(under, c.crown[k][0]), max(over, c.crown[k][1])
					c.crown[k], c.kind[k] = {under, over}, t.kind
				}
			}
			// The trunk's own cell always carries crown, so a small tree is never lost between cells.
			if i, j := (t.x - x0)/s, (t.z - z0)/s; t.x >= x0 && t.z >= z0 && i < P && j < P {
				k := j*P + i
				c.stem[k], c.kind[k] = u8(1 + (t.x - x0 - i*s) + 4*(t.z - z0 - j*s)), t.kind
				if lo, hi := envelope(t, 0); c.crown[k][1] <= c.crown[k][0] do c.crown[k] = {max(t.base + i32(math.round(lo)), c.ground[k]), t.base + i32(math.round(hi))}
			}
		}
	}
	c.lo, c.hi = max(i32), min(i32)
	for k in 0..<P*P {
		c.lo = min(c.lo, c.ground[k], c.hollow[k][0] if c.hollow[k][1] > c.hollow[k][0] else max(i32))
		c.hi = max(c.hi, c.top[k], c.crown[k][1])
	}
}

// The block at a depth below the surface of a column, where `bed` is the rock at that
// height. Bare rock is rock all the way down, so a face and a hole show the same beds. Under a
// plant cover lie `deep` blocks of the soil, counting the cover, and some may be stones.
block_below :: proc(surface: Mat, depth: i32, bed: Mat, soil: ^Soil, deep: i32, stone: bool) -> Mat {
	if surface in COVERS {
		if depth == 0 do return surface
		if depth >= deep do return bed
		if stone && MATERIALS[bed].loose != .Air do return MATERIALS[bed].loose
		return soil.top if depth == 1 else soil.foot if depth == deep - 1 && deep > 2 else soil.sub
	}
	#partial switch surface {
	case .Sand, .Silt, .Black_Sand, .Shingle, .Black_Shingle: return surface if depth < 4 else bed
	case .Snow:  return .Snow if depth < 2 else bed
	case .Gravel: return .Gravel if depth < 2 else bed
	}
	if surface >= .Mudstone_Scree do return surface if depth < 5 else bed   // loose rock lies on the bed
	return bed
}

// The blocks of a nearest-level chunk and its border, in layers from y_base up. `lo` and
// `hi` widen the vertical range, for edits that reach outside the generated ground. They are
// the island's under the chunk's middle, which stays bound for meshing; a column of the open sea
// is sand to the bottom.
gen_volume :: proc(cx, cz: i32, c: ^Columns, lo, hi: i32) -> (blocks: []u8, y_base, h: i32) {
	trees := make([dynamic]Tree, context.temp_allocator)
	sea := !bind_at(f64(cx*CHUNK + CHUNK/2), f64(cz*CHUNK + CHUNK/2))
	x0, z0 := cx*CHUNK - 1 - region.origin.x, cz*CHUNK - 1 - region.origin.y
	if !sea do trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P + TREE_REACH, z0 + P + TREE_REACH, &trees, true)
	top := max(hi, c.hi)
	for t in trees do top = max(top, t.base + t.height + 1)

	y_base = min(lo, c.lo) - 4   // room below for the rim faces and corner light
	h = top - y_base + 1
	blocks = make([]u8, P*P*int(h))
	for k in 0..<P*P {
		t := c.top[k]
		x, z := x0 + i32(k%P), z0 + i32(k/P)
		if sea || island_at(f64(x + region.origin.x) + 0.5, f64(z + region.origin.y) + 0.5) == nil {
			for y in y_base..<t do blocks[k + int(y - y_base)*P*P] = u8(Mat.Sand)
			continue
		}
		soil, deep := &SOILS[0], i32(0)
		if c.mat[k] in COVERS {
			p := Point{x = f64(x) + 0.5, z = f64(z) + 0.5, cell = 1}
			row, depth := soil_at(&p)
			soil, deep = &SOILS[row], 1 + i32(math.ceil(depth))
		}
		debris := slid_at(f64(x) + 0.5, f64(z) + 0.5)   // a slide's broken rock lies over the beds
		for y in y_base..<t {
			stone := hash01(x + y*131, z, seed + 190) < soil.stones
			bed := (landslide.rock if c.mat[k] == landslide.rock && t - y <= 6 else MATERIALS[landslide.rock].loose) if f32(t - y) <= debris else rock_in(f32(y) + 0.5, c.base[k], 0)   // a block of the cap is whole
			b := block_below(c.mat[k], t - 1 - y, bed, soil, deep, stone)
			blocks[k + int(y - y_base)*P*P] = u8(shore_of(b, bed))
		}
		for y in c.hollow[k][0]..<min(c.hollow[k][1], t) do blocks[k + int(y - y_base)*P*P] = 0   // a hollow under a roof of the beds
	}
	for t in trees {
		put :: proc(blocks: []u8, x, y, z: i32, m: Mat, replace: bool) {
			if x < 0 || x >= P || z < 0 || z >= P || y < 0 do return   // below y is this chunk's solid ground: a tree at a cliff's foot
			k := int(x) + int(z)*P + int(y)*P*P
			if replace || blocks[k] == 0 do blocks[k] = u8(m)
		}
		if t.form != .Fallen {
			grow(blocks, t, {x0, y_base, z0}, c)
			continue
		}
		// A stump, and the trunk lying beyond it (trees_in).
		bark := SPECIES[t.kind].bark
		put(blocks, t.x - x0, t.base - y_base, t.z - z0, bark, false)
		for d in 2..<2 + t.height do put(blocks, t.x - x0 + i32(t.fall.x)*d, t.base - y_base, t.z - z0 + i32(t.fall.y)*d, bark, false)
	}
	return
}
