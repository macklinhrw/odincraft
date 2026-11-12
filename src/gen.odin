package main

import "core:fmt"
import "core:math"
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
	Litter, Susuki, Dune,             // what covers the ground between the trees (COMMUNITIES)
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
	.Litter    = {{0.096, 0.058, 0.025}, 0, 0, .Air},      // fallen evergreen leaves
	.Susuki    = {{0.096, 0.157, 0.038}, 0, 0, .Air},    // susuki grass and dwarf bamboo
	.Dune      = {{0.128, 0.139, 0.062}, 0, 0, .Air},   // dune grass, straw
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
NO_WATER    :: -1e6
seed        := u32(7)   // every random choice in the world is keyed from this; --seed= sets it

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
	plants_init()
	return true
}

Ground :: struct {
	h, steep: f32,   // elevation, and how steep the ground is there, rise over run
	base:     f32,   // height of the rock stack's base under it (rock.odin)
	water:    f32,   // level of the river or sea standing here, or NO_WATER
	cover:    Mat,   // river gravel, or the loose rock lying under a face; Air for neither
	fallen:   f32,   // depth of the loose rock fallen from a face, under any gravel
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
			if abs(x - bx) < size/2 && abs(z - bz) < size/2 do h, g.cover, g.fallen = h + f32(1 + (r >> 20)%u32(size)), landslide.rock, 1
		}
	}
	lake, inside, bank := lake_near(x, z)
	h = max(h, bank)
	gravel: bool
	g.h, gravel, g.water = river_cut(h, x, z, cell)
	if inside {
		g.h, gravel = min(g.h, h), false
		if g.h < lake do g.h, g.water = max(g.h, lake - 1) if cell > 1 else g.h, lake   // far off, a lake's bed is drawn flat under it, so its cells do not show through
	}
	if gravel do g.cover = .Gravel
	if g.h < SEA_SURFACE do g.water = max(g.water, SEA_SURFACE)
	g.steep = steep*l.rise
	return
}

height_at :: proc(x, z, cell: f64) -> f32 {
	return ground(x, z, cell).h
}

// What covers the ground, as an ordered catalogue: the first row whose host holds is the
// surface. Air brings the rock itself: what has fallen there, or else the bed.
// Soil and forest hold on ground up to about 45°, as on real flanks; only a face steeper than
// that is bare, which a weak rock makes only where the sea undercuts it or as the riser of a ledge.
Surface :: struct {
	name, why: string,
	brings:    Mat,
	host:      []Window,
}

SURFACES := [?]Surface{
	{"river gravel", "a river lays gravel on its bars and its bed", .Gravel, {{.Gravel, 0, ANY, 0}}},
	{"sand", "the waves throw sand up the shore", .Sand, {{.Beach, 0, ANY, 0}}},
	{"lake bed", "silt settles out of the still water of a lake or pond", .Silt, {{.Under_Water, 0, ANY, 0}}},
	{"loose rock", "rock fallen from the face above lies at its angle of rest", .Air, {{.Fallen, 0, ANY, 0}}},
	{"bare rock", "soil cannot hold on ground this steep, so the beds show", .Air, {{.Too_Steep, 0, ANY, 0}}},
	{"bare scar", "a slide stripped the hillside to the rock, and no soil has yet weathered back", .Air, {{.Disturbed, -ANY, 1e4, 0}, {.Slid, -ANY, -0.5, 0}, {.Soil_Depth, -ANY, 0.15, 0}}},
	{"soil", "soil holds, and the plants cover it", .Grass, {}},   // the plant community brings what covers it
}

surface_row :: proc(p: ^Point) -> int {
	for r, i in SURFACES do if host(r.host, p) > 0 do return i
	return len(SURFACES) - 1
}

// What the ground is at a point, what covers it, and the plant community growing there, if
// soil holds.
surface_at :: proc(x, z, cell: f64) -> (g: Ground, m: Mat, plants: Maybe(Community_Kind)) {
	p := point_at(x, z, cell)
	row := surface_row(&p)
	m = SURFACES[row].brings
	if row == len(SURFACES) - 1 {
		k, _ := community_at(x, z, cell)
		m, plants = COMMUNITIES[k].cover, k
	}
	if m == .Air do m = p.cover if p.cover != .Air else rock_in(p.h - 0.5, p.base, rock_level(cell))
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

// A species: its bark and leaf blocks, the form of its crown, and its height to the crown's top
// and the crown's radius, in metres. The cast is the evergreen wood of the warm islands of
// southern Japan (docs/interesting-world/notes/real-vegetation.md). True heights wait for the
// tree grower; these keep near the sizes trees have had.
Tree_Kind :: enum u8 { Tabu, Shii, Camellia, Hisakaki, Pine, Scrub, Alder }
Species :: struct {
	name:           string,
	bark, leaf:     Mat,
	crown:          enum u8 { Broad, Dome, Flat, Bush },
	height, radius: [2]i32,
}

SPECIES := [Tree_Kind]Species{
	.Tabu     = {"tabu", .Wood, .Leaves, .Broad, {12, 15}, {3, 4}},                    // Machilus: the big tree of moist ground, a broad dark dome
	.Shii     = {"shii", .Shii_Bark, .Shii_Leaves, .Dome, {10, 14}, {2, 3}},           // Castanopsis: the round olive crowns that close over the slopes
	.Camellia = {"camellia", .Grey_Bark, .Camellia_Leaves, .Dome, {5, 7}, {2, 2}},     // a small dark tree under them, in flower
	.Hisakaki = {"hisakaki", .Grey_Bark, .Hisakaki_Leaves, .Broad, {4, 7}, {2, 2}},    // Eurya and its like: the low wood of dry ridges
	.Pine     = {"black pine", .Pine_Bark, .Pine_Needles, .Flat, {9, 13}, {2, 3}},     // a flat top on a dark bole, by the sea and on rock
	.Scrub    = {"scrub", .Wood, .Scrub_Leaves, .Bush, {1, 3}, {1, 2}},                // tobira and other bushes, from the ground up
	.Alder    = {"alder", .Grey_Bark, .Scrub_Leaves, .Broad, {5, 8}, {2, 3}},          // Alnus sieboldiana: the first trees on raw ground, fixing their own nitrogen
}
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
		{{{.Cold, -ANY, 3, 3}, {.Slope, -ANY, 0.2, 0.1}}, {{.Humped, -ANY, -8, 4}, {.Wetness, 0.35, ANY, 0.1}}}, 0.8, 0.3, {0.8, 0.2, 0, 0, 0, 0, 0}, .Grass, {0.45, 0.85, 0.30}},
	.Slope = {"laurel forest", "shii and tabu close over the slopes wherever nothing else does better, with camellia under them", 1, 400,
		{}, 0.95, 0.3, {0.15, 0.7, 0.15, 0, 0, 0, 0}, .Litter, {0.10, 0.42, 0.16}},
	.Ridge = {"ridge wood", "a low wood of small-leaved evergreens and pine holds dry humps and thin soil over rock", 3, 250,
		{{{.Humped, 4, ANY, 3}, {.Wetness, -ANY, 0.25, 0.1}}, {{.Soil_Depth, -ANY, 0.5, 0.25}}}, 0.95, 0.15, {0, 0.1, 0.1, 0.6, 0.2, 0, 0}, .Litter, {0.20, 0.55, 0.60}},
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
		{{{.Disturbed, -ANY, 120, 180}}}, 0.75, 0.2, {0, 0, 0, 0, 0, 0.2, 0.8}, .Susuki, {0.80, 1.00, 0.30}},
	.Young = {"young wood", "tabu and small evergreens grow up through the alders, a darker and lower wood than the old forest round it", 8, 100,
		{{{.Disturbed, -ANY, 400, 500}}}, 0.9, 0.4, {0.45, 0, 0.1, 0.25, 0, 0, 0.2}, .Litter, {0.30, 0.65, 0.55}},
}
COVERS :: bit_set[Mat]{.Grass, .Litter, .Susuki, .Dune}
closure: [Community_Kind]f32   // the share of a community's ground its crowns cover, which is how much of the far canopy is leaf

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
	land.community = make([]u8, n*n)
	count, soils := [Community_Kind]int{}, [len(SOILS)]int{}
	for c in 0..<n*n {
		land.community[c] = 255
		if land.grid.sea[c] do continue
		p := Point{x = (f64(c%n) + 0.5)*LAND_CELL - region.size/2, z = (f64(c/n) + 0.5)*LAND_CELL - region.size/2, cell = LAND_CELL}
		k, _, _ := race(&p)
		land.community[c] = u8(k)
		count[k] += 1
		row, _ := soil_at(&p)
		soils[row] += 1
	}
	for com, k in COMMUNITIES {
		for share, s in com.trees do closure[k] += share*math.PI*math.pow(f32(SPECIES[Tree_Kind(s)].radius[0] + SPECIES[Tree_Kind(s)].radius[1])/2 + 0.5, 2)
		closure[k] = min(closure[k]*com.density/(TREE_GRID*TREE_GRID), 1)
	}
	fmt.printf("plants in %.0f ms:", time.duration_milliseconds(time.since(started)))
	for k, i in count do fmt.printf(" %s %.0f%%", COMMUNITIES[i].name, 100*f32(k)/f32(len(land.grid.order)))
	fmt.print("; soil:")
	for k, i in soils do fmt.printf(" %s %.0f%%", SOILS[i].name, 100*f32(k)/f32(len(land.grid.order)))
	fmt.println()
}

// ---- trees --------------------------------------------------------------------------------

Tree :: struct {
	x, z:   i32,   // block the trunk stands on
	base:   i32,   // elevation of the ground there
	height: i32,   // to the crown's top, over the base
	radius: i32,   // of the crown
	kind:   Tree_Kind,
	under:  bool,  // a bush under the trees, drawn only near by
	dead:   bool,  // a bare trunk: a tree a lake drowned, drawn only near by
}

TREE_GRID  :: 6   // at most one tree per square of this many metres
TREE_REACH :: 4   // the widest crown

// The share of the community's trees each species has, picked by a number in 0..1.
pick_species :: proc(k: Community_Kind, u: f32) -> Tree_Kind {
	u := u
	for share, s in COMMUNITIES[k].trees {
		u -= share
		if u < 0 do return Tree_Kind(s)
	}
	return .Shii
}

// Every tree whose trunk stands in a rectangle of blocks. The same tree is found whichever
// chunk or level of detail asks.
trees_in :: proc(x0, z0, x1, z1: i32, out: ^[dynamic]Tree) {
	floor_div :: proc(a, b: i32) -> i32 { return (a - a %% b)/b }
	for gz in floor_div(z0, TREE_GRID)..=floor_div(z1, TREE_GRID) {
		for gx in floor_div(x0, TREE_GRID)..=floor_div(x1, TREE_GRID) {
			// Each square may hold a tree, and a bush under the trees.
			for bush in ([2]bool{false, true}) {
				r := hash(gx, gz, seed + (143 if bush else 140))
				x, z := gx*TREE_GRID + i32(r % TREE_GRID), gz*TREE_GRID + i32((r >> 4) % TREE_GRID)
				if x < x0 || x > x1 || z < z0 || z > z1 do continue
				fx, fz := f64(x) + 0.5, f64(z) + 0.5
				near, _ := community_at(fx, fz, 1)
				if f32((r >> 8) & 0xFF)/255 >= (COMMUNITIES[near].bushes if bush else COMMUNITIES[near].density) do continue
				g, _, plants := surface_at(fx, fz, 1)
				// A young lake still has the trunks of the trees it drowned standing in it.
				if level, inside, _ := lake_near(fx, fz); inside && g.h < level && !bush && region.features[landslide.feature].age < DROWNED {
					if (r >> 24)&1 == 0 do continue   // half have fallen
					append(out, Tree{x = x, z = z, base = i32(math.round(g.h)), height = 5 + i32((r >> 16)%6), kind = .Shii, dead = true})
					continue
				}
				k := plants.? or_continue
				kind := Tree_Kind.Scrub if bush else pick_species(k, hash01(gx, gz, seed + 141))
				s, v := SPECIES[kind], hash(gx, gz, seed + (144 if bush else 142))
				append(out, Tree{x, z, i32(math.round(g.h)), s.height[0] + i32(v % u32(s.height[1] - s.height[0] + 1)), s.radius[0] + i32((v >> 8) % u32(s.radius[1] - s.radius[0] + 1)), kind, bush, false})
			}
		}
	}
}

// A tree's crown, as the height of its underside and its top over the tree's base, at a
// distance from the trunk; the underside lies over the top outside it. The near blocks and the
// far crowns both draw this.
envelope :: proc(t: Tree, d: f32) -> (under, over: f32) {
	r := f32(t.radius) + 0.5
	if d >= r do return 1, 0
	top, q := f32(t.height), math.sqrt(1 - d*d/(r*r))
	switch SPECIES[t.kind].crown {
	case .Broad: return top - r*(0.65 + 0.45*q), top - r*0.65*(1 - q)
	case .Dome:  return top - r*0.85*(1 + q), top - r*0.85*(1 - q)
	case .Flat:  return top - 1.2 - 1.6*q, top - 0.8*(1 - q)
	case .Bush:  return 0, top*q
	}
	return 1, 0
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
			g, m, plants := surface_at(x, z, cell)
			heights[k], c.water[k], c.base[k], c.mat[k] = g.h, g.water, g.base, m
			c.top[k] = i32(math.round(heights[k]))
			c.ground[k] = c.top[k]
			// The canopy: a cell is the leaf of a tree its community would grow, raised to about
			// the height of that tree's crown.
			if com, ok := plants.?; ok && s >= 8 {
				r := hash(i32(math.floor(x/cell)), i32(math.floor(z/cell)), seed + 160 + u32(level))
				if f32(r & 0xFFFF)/65536 < closure[com] {
					sp := SPECIES[pick_species(com, f32((r >> 16) & 0xFF)/256)]
					c.top[k] += sp.height[0] - 1 + i32((r >> 24) % u32(sp.height[1] - sp.height[0] + 1))
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
	if level == 1 || level == 2 {
		trees := make([dynamic]Tree, context.temp_allocator)
		x0, z0 := (cx*CHUNK - 1)*s - ox, (cz*CHUNK - 1)*s - oz
		trees_in(x0 - TREE_REACH, z0 - TREE_REACH, x0 + P*s + TREE_REACH, z0 + P*s + TREE_REACH, &trees)
		for t in trees {
			if t.under || t.dead do continue
			for j in max((t.z - TREE_REACH - z0)/s, 0)..=min((t.z + TREE_REACH - z0)/s, P - 1) {
				for i in max((t.x - TREE_REACH - x0)/s, 0)..=min((t.x + TREE_REACH - x0)/s, P - 1) {
					dx := f32(x0 + i*s) + f32(s)/2 - (f32(t.x) + 0.5)
					dz := f32(z0 + j*s) + f32(s)/2 - (f32(t.z) + 0.5)
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
		c.lo = min(c.lo, c.ground[k])
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
	case .Sand, .Silt: return surface if depth < 4 else bed
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
	for t in trees do top = max(top, t.base + t.height + 1)

	y_base = min(lo, c.lo) - 4   // room below for the rim faces and corner light
	h = top - y_base + 1
	blocks = make([]u8, P*P*int(h))
	for k in 0..<P*P {
		t := c.top[k]
		x, z := x0 + i32(k%P), z0 + i32(k/P)
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
			blocks[k + int(y - y_base)*P*P] = u8(block_below(c.mat[k], t - 1 - y, bed, soil, deep, stone))
		}
	}
	for t in trees {
		put :: proc(blocks: []u8, x, y, z: i32, m: Mat, replace: bool) {
			if x < 0 || x >= P || z < 0 || z >= P || y < 0 do return   // below y is this chunk's solid ground: a tree at a cliff's foot
			k := int(x) + int(z)*P + int(y)*P*P
			if replace || blocks[k] == 0 do blocks[k] = u8(m)
		}
		sp := SPECIES[t.kind]
		trunk, _ := envelope(t, 0)
		if sp.crown != .Bush do for y in t.base..=t.base + i32(trunk) do put(blocks, t.x - x0, y - y_base, t.z - z0, sp.bark, true)
		if t.dead do continue
		r := t.radius
		for dz in -r..=r {
			for dx in -r..=r {
				d := math.sqrt(f32(dx*dx + dz*dz))
				lo, hi := envelope(t, d - 0.4)
				for dy in i32(math.floor(lo))..<i32(math.ceil(hi)) {
					under, over := envelope(t, d - 0.4 + hash01(t.x + dx + dy*57, t.z + dz, seed + 180))   // a soft, uneven edge
					if f32(dy) + 0.5 < under || f32(dy) + 0.5 > over do continue
					put(blocks, t.x + dx - x0, t.base + dy - y_base, t.z + dz - z0, sp.leaf, false)
				}
			}
		}
	}
	return
}
