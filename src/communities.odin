package main

import "core:fmt"
import "core:time"

// Soil and the plant communities, as ordered catalogues over the land's fields: the first row whose
// host holds wins. The communities compete for ground in a race (race, fields.odin); plants_init runs
// it once the land is formed. See docs/foundations/vegetation.md.

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
	// Red and yellow soils form today only in Japan's subtropical islands, the Ryukyus; the warm-temperate
	// belt has yellow-brown and brown forest soils, and red clay there is a relic of warmer times (Britannica,
	// "Japan: Soils"; Matsui 1964). Kira's subtropical line, a warmth of 180, stands for it.
	{"red soil", "long rain in a subtropical warmth leaches old dry ground to a red clay", .Loam, .Red_Clay, .Red_Clay, 0, {{.Humped, 3, ANY, 0}, {.Wetness, -ANY, 0.3, 0}, {.Warmth, 180, ANY, 0}}, {0.85, 0.40, 0.22}},
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

// The plant communities, which compete for ground in a race (race, fields.odin). A row brings
// how thickly trees stand (the share of 6 m squares with one), how many of those squares have a
// bush under the trees as well, the species in their shares, what covers the ground between
// them, and its colour on the map.
Community_Kind :: enum u8 { Valley, Slope, Ridge, Windy, Coast, Fresh, Alder, Young, Marsh }
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
	// A hump or thin soil is dry where the rain is not so much for the warmth that it stays moist: where
	// the year's warmth could draw under a third of the rain (dryness), about 3,000 to 4,500 mm a year at
	// 17 °C, a crest carries the slope's forest, as the windward ridges of Yakushima's wet east do (a
	// guess at where; climate.odin).
	.Ridge = {"ridge wood", "a low wood of small-leaved evergreens and pine holds dry humps and thin soil over rock", 3, 250,
		{{{.Humped, 4, ANY, 3}, {.Wetness, -ANY, 0.25, 0.1}, {.Dryness, 0.35, ANY, 0.12}}, {{.Soil_Depth, -ANY, 0.5, 0.25}, {.Dryness, 0.35, ANY, 0.12}}}, 0.6, 0.1, {0, 0.1, 0.1, 0.6, 0.2, 0, 0}, .Litter, {0.20, 0.55, 0.60}},
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
	// Where the water in the ground stands within a metre of the surface, on a valley floor or the flat
	// at a bay's head, the trees of the forest cannot root: reeds and sedges take it, with a few alders.
	.Marsh = {"reed marsh", "the water stands at the ground on this flat, too wet for the forest's trees to root: reeds and sedges, and a few alders", 40, 80,
		{{{.Water_Table, -ANY, 1, 0.5}, {.Slope, -ANY, MARSH_FLAT, 0.01}}}, 0.03, 0, {0, 0, 0, 0, 0, 0, 1}, .Susuki, {0.80, 0.40, 0.75}},
}
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
			o := land_corner()
			p := Point{x = (f64(c%n) + 0.5)*LAND_CELL + o.x, z = (f64(c/n) + 0.5)*LAND_CELL + o.y, cell = LAND_CELL}
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
