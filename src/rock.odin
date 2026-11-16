package main

import "core:fmt"
import "core:math"

// The rock under the island: one function of a point, fixed in the finished world. The
// land forming reads it shifted by the uplift still to come, so the beds the erosion cut
// are the beds the blocks show; the surface, the blocks and the map read it as it is.
// Nothing is stored per block.
//
// The rock is drawn from the seed within the ranges of a story (geology.md, section 4): a stack of
// beds, tilted and gently folded, or folded into ridges, or laid over the forms the island's vents
// built, so that a volcano's flows and ash lie parallel to its slopes and dip away from its vent. A
// point's place in the stack is its height less the height of the stack's base under it, and the
// bed there is read from a table, one entry a metre. Across the beds cut bodies (D2): faults, which
// lift the stack on one side; dikes, plugs and plutons, which stand in place of the beds; and a
// pluton bakes the beds over it into harder rock. A story may lay a second stack over the first on a
// surface worn across it, as lava poured over older rock (a cover). Each column's part of all this is
// worked out once (`Under`), so a rock at a height is a lookup.
//
// Which story an island's rock tells is read from its setting in the plates' history (story_for).

// A kind a story draws its beds from: how often, between which places in the stack (metres above
// the base, which is about the height above sea level under the island's middle), and how thick
// its beds are where not as the story's.
Story_Kind :: struct {
	kind:   Mat,
	weight: f32,
	at:     [2]f32,
	thick:  [2]f32,   // a coal seam's metre or two; zero for the story's own
}

// What laid an island's rock, which its history says (laid_by): the plates, before and as the
// island rose from the sea floor; its own vents, of runny lava or of stiff; or coral, as it rose.
Laid :: enum u8 { Plates, Runny_Lava, Stiff_Lava, Coral }

// A body cutting the beds (geology.md, D2), drawn `count` times, each `out` (a share of the region's
// side) from the island's middle, or for a dike or plug of a story laid over vents, out from a vent
// by that share of how far its form reaches. Lengths are metres on a region 8,192 m across and
// stretch with it, as a kind's are; widths, throws and heights are true.
//   Fault:  a steep break `long` metres, gently bent, the stack on one side of it lifted `size`
//           metres at its middle and less toward its ends, with a crushed core a metre or a few wide
//   Dike:   a wall `size` metres wide and `long` long that tapers to its ends; a story's dikes share
//           one direction, or run out from a vent
//   Plug:   the filled pipe of an old vent, `size` metres across
//   Pluton: a dome that cooled under the ground, its top `high` metres over the sea, its roof
//           falling to PLUTON_FOOT under the sea `long` metres from its middle
Body_Kind :: enum u8 { Fault, Dike, Plug, Pluton }
Story_Body :: struct {
	what:  Body_Kind,
	kind:  Mat,
	count, size, long, high, out: [2]f32,
}

Story :: struct {
	name, after: string,   // and the real places it is after
	judged: []string,      // the real islands (REAL, land.odin) an island telling it is judged against, in place of those its kind is after; none: its kind's
	laid:   Laid,
	hosts:  []Window,      // where the plates make it, on the world's fields at the island's middle (story_for); none: wherever no row before it holds
	kinds:  [6]Story_Kind,
	thick:  [2]f32,   // bed thickness, metres
	hard:   f32,      // share of beds drawn from the hard kinds, those of strength 0.5 or more
	gap:    f32,      // the most soft rock between two hard beds, metres
	tilt:   [2]f32,   // dip of the beds, degrees
	fold:   [2]f32,   // height of the folds, metres
	wave:   [2]f32,   // their wavelength, metres
	ridges: bool,     // the folds stand in parallel ridges, as in a belt squeezed from one side, rather than in domes and basins
	drape:  bool,     // the beds lie over the ground the vents built (land.odin), rather than level
	mantle: f32,      // the least a hillside of it creeps where soil holds: ash and cinders mantle a volcano's lava and creep whatever lies under them
	cover:  string,   // a story whose beds lie over this one's on a surface worn across them: lava poured over older rock
	over:   [2]f32,   // the height of that surface over the base, metres
	bodies: []Story_Body,
}

ANYWHERE :: [2]f32{-1e5, 1e5}
NONE     :: [2]f32{}

// The stories, as rows (geology.md, section 4: its twelve, with the young volcanic island's in two
// rows, one for runny lava and one for stiff, and two after real islands the game is measured
// against: the reef, and the old arc lavas of the Bonin islands). An island's history says what laid
// its rock (`laid`); of the rows so laid, its rock tells the first whose host holds at its middle, so
// the rows run from the most particular cause to the most common.
STORIES := [?]Story{
	{
		// A pluton under a fast-rising thick crust, unroofed: the island is granite, its rim the
		// baked beds it rose into. Only within reach of the magma the arc's front rises over:
		// Yakushima stands about 20 km from Kuchinoerabujima on the front, where Kikaijima, rising
		// as fast on the forearc's outer ridge far in front of it, is mudstone under its reef. Judged
		// against Yakushima, not its kind's islands, none of which is granite.
		name = "granite massif", after = "Yakushima", judged = {"Yakushima"}, laid = .Plates,
		hosts = {{.Crust, 20, ANY, 3}, {.Rising, 0.9, ANY, 0.2}, {.Front, -ANY, 50, 20}},
		kinds = {0 = {.Sandstone, 2, ANYWHERE, NONE}, 1 = {.Mudstone, 2, ANYWHERE, NONE}, 2 = {.Siltstone, 1, ANYWHERE, NONE}},
		thick = {10, 40}, hard = 0.4, gap = 80, tilt = {10, 30}, fold = {30, 80}, wave = {1500, 3000},
		bodies = {
			{.Pluton, .Granite, {1, 1}, NONE, {2600, 3400}, {700, 1200}, {0, 0.08}},
			{.Dike, .Dolerite, {3, 6}, {1, 3}, {300, 900}, NONE, {0, 0.3}},
		},
	},
	{
		// The arc's lavas reached it: a pile of flows over the soft beds the sea laid before, near
		// flat, so the cap stands as a long scarp over slopes of mudstone that slip.
		name = "hard cap over weak rock", after = "Iki's lava over its mudstone; Trotternish on Skye", laid = .Plates,
		hosts = {{.Front, -ANY, 40, 10}},   // within reach of the lava the volcanic front's vents pour out
		kinds = {0 = {.Mudstone, 3, ANYWHERE, NONE}, 1 = {.Siltstone, 1.5, ANYWHERE, NONE}, 2 = {.Sandstone, 1, ANYWHERE, NONE}},
		thick = {10, 40}, hard = 0.2, gap = 200, tilt = {2, 6}, fold = {10, 30}, wave = {2000, 4000},
		cover = "lava plateau", over = {90, 190},
		bodies = {
			{.Fault, .Air, {1, 2}, {20, 80}, {3000, 7000}, NONE, {0, 0.3}},           // older than the lava, which lies across them
			{.Dike, .Dolerite, {4, 9}, {2, 5}, {400, 1200}, NONE, {0, 0.35}},         // the feeders of the flows
		},
	},
	{
		// Old continental crust worn down where it barely rises: banded gneiss on end, ridges of
		// quartzite, cut by a swarm of dark dikes. Not on a forearc, whose crust lies under what the
		// trench scrapes up and the basin behind it fills with: behind the arc, as Oki-Dōgo, or on a
		// margin no trench works, as Lewis.
		name = "metamorphic shield", after = "the Lewisian gneiss of Lewis and Harris; Oki-Dōgo", laid = .Plates,
		hosts = {{.Crust, 28, ANY, 3}, {.Age, 250, ANY, 50}, {.Rising, -ANY, 0.3, 0.2}, {.Across, 1, ANY, 0.1}},
		kinds = {0 = {.Gneiss, 3, ANYWHERE, NONE}, 1 = {.Schist, 1.5, ANYWHERE, NONE}, 2 = {.Quartzite, 0.8, ANYWHERE, NONE}},
		thick = {10, 40}, hard = 0.7, gap = 60, tilt = {0, 5}, fold = {400, 700}, wave = {1500, 2500}, ridges = true,
		bodies = {{.Dike, .Dolerite, {6, 12}, {3, 10}, {800, 2000}, NONE, {0, 0.35}}},
	},
	{
		// Thick crust under an arc, where magma pooled and cooled: a granite on one side of the
		// island, the beds it rose into on the other, baked hard round it. Not on a forearc, as the
		// shield: behind the arc, as Tsushima, or on a margin no trench works, as Arran.
		name = "granite against sediments", after = "Arran; the granite of Tsushima's south", laid = .Plates,
		hosts = {{.Crust, 18, ANY, 3}, {.Across, 1, ANY, 0.1}},
		kinds = {
			0 = {.Mudstone, 3, ANYWHERE, NONE}, 1 = {.Siltstone, 1.5, ANYWHERE, NONE}, 2 = {.Sandstone, 2, ANYWHERE, NONE},
			3 = {.Limestone, 0.8, {-1e5, 0}, NONE}, 4 = {.Grit, 1, {40, 1e5}, NONE},
		},
		thick = {12, 45}, hard = 0.3, gap = 110, tilt = {5, 15}, fold = {20, 60}, wave = {1800, 4000},
		bodies = {
			{.Pluton, .Granite, {1, 1}, NONE, {1700, 2400}, {150, 450}, {0.12, 0.25}},
			{.Fault, .Air, {1, 2}, {50, 150}, {3000, 8000}, NONE, {0, 0.3}},
			{.Dike, .Dolerite, {6, 12}, {2, 6}, {500, 1500}, NONE, {0, 0.35}},
		},
	},
	{
		// Flood lavas over a hotspot: flow on flow with red soil baked between them, near flat, so
		// hillsides step and cliffs stand in tiers.
		name = "lava plateau", after = "the Faroes; Staffa", laid = .Plates,
		hosts = {{.Track, -ANY, 10, 5}},   // on a hotspot's track
		kinds = {0 = {.Basalt, 1, ANYWHERE, NONE}, 1 = {.Scoria, 1, ANYWHERE, NONE}},
		thick = {10, 25}, hard = 0.65, gap = 12, tilt = {0, 2}, fold = {5, 15}, wave = {3000, 5000},
		bodies = {
			{.Dike, .Dolerite, {6, 12}, {2, 6}, {600, 1500}, NONE, {0, 0.35}},
			{.Plug, .Dolerite, {1, 3}, {120, 280}, NONE, NONE, {0.05, 0.3}},
		},
	},
	{
		// The sediment a continent's rivers pour into the trench, scraped off the plate going down
		// and squeezed into folds: sandstone and slate on end, in ridges along the arc.
		name = "folded belt", after = "the Shimanto belt; Tsushima's Taishu group", laid = .Plates,
		hosts = {{.Offshore, -ANY, 120, 40}, {.Across, -ANY, 0.4, 0.03}},   // a continent near enough to feed the trench, and nearer the trench than the outer high's crest
		kinds = {0 = {.Sandstone, 2, ANYWHERE, NONE}, 1 = {.Slate, 2, ANYWHERE, NONE}, 2 = {.Mudstone, 1, ANYWHERE, NONE}, 3 = {.Siltstone, 1, ANYWHERE, NONE}},
		thick = {8, 30}, hard = 0.45, gap = 60, tilt = {0, 5}, fold = {250, 500}, wave = {1200, 2600}, ridges = true,
		bodies = {{.Fault, .Air, {2, 3}, {40, 200}, {4000, 9000}, NONE, {0, 0.35}}},
	},
	{
		// The same sediment laid in a basin on crust that hardly rises or sinks, so nothing tilted it:
		// benches, flat tops, a seam of coal. Not on a forearc, whose basin the trench tilts, as
		// Boso's beds (layered, gently tilted): behind the arc, or on a margin no trench works.
		name = "flat-bedded", after = "the Coal Measures", laid = .Plates,
		hosts = {{.Offshore, -ANY, 120, 40}, {.Rising, -ANY, 0.25, 0.1}, {.Across, 1, ANY, 0.1}},
		kinds = {
			0 = {.Mudstone, 3, ANYWHERE, NONE}, 1 = {.Siltstone, 2, ANYWHERE, NONE}, 2 = {.Sandstone, 2, ANYWHERE, NONE},
			3 = {.Coal, 0.5, ANYWHERE, {1, 3}}, 4 = {.Limestone, 0.8, {-1e5, -20}, NONE}, 5 = {.Grit, 1.5, {40, 1e5}, NONE},
		},
		thick = {8, 30}, hard = 0.3, gap = 60, tilt = {0, 1.5}, fold = {3, 10}, wave = {3000, 6000},
		bodies = {{.Fault, .Air, {1, 2}, {20, 60}, {3000, 7000}, NONE, {0, 0.3}}},
	},
	{
		// A drowned bank carried toward a trench rises on the bulge in front of it, a cap of
		// limestone on shale. No island stands before a trench yet (SITES).
		name = "limestone platform", after = "Minami-Daitō; Christmas Island", laid = .Plates,
		hosts = {{.Trench, -ANY, -20, 5}},   // on the plate going down, before the trench
		kinds = {0 = {.Limestone, 4, ANYWHERE, NONE}, 1 = {.Mudstone, 0.6, ANYWHERE, NONE}},
		thick = {15, 60}, hard = 0.85, gap = 15, tilt = {0, 1}, fold = {3, 8}, wave = {3000, 6000},
		bodies = {{.Fault, .Air, {1, 2}, {10, 40}, {2000, 5000}, NONE, {0, 0.3}}},
	},
	{
		// Chalk laid in a calm warm sea on a shelf far from any arc. No shelf near the start lies so
		// far from one.
		name = "soft coast", after = "the Seven Sisters; Møns Klint", laid = .Plates,
		hosts = {{.Setting, 4.5, 5.5, 0}, {.Front, 300, ANY, 0}},
		kinds = {0 = {.Chalk, 3, {-20, 1e5}, NONE}, 1 = {.Sandstone, 1, {-1e5, -20}, NONE}, 2 = {.Mudstone, 1, {-1e5, -20}, NONE}},
		thick = {20, 60}, hard = 0.2, gap = 400, tilt = {0, 2}, fold = {5, 20}, wave = {3000, 6000},
	},
	{
		// Salt and red beds where a sea dried, in a dry climate: they wait for one (step 25), and the
		// salt for the wide world's rocks.
		name = "evaporite basin", after = "the Zechstein; the Dead Sea", laid = .Plates,
		hosts = {{.Setting, 5.5, ANY, 0}},   // inland on a continent, where no island stands
		kinds = {0 = {.Red_Sandstone, 2, ANYWHERE, NONE}, 1 = {.Mudstone, 2, ANYWHERE, NONE}, 2 = {.Limestone, 0.5, ANYWHERE, NONE}},
		thick = {10, 40}, hard = 0.4, gap = 80, tilt = {0, 2}, fold = {5, 20}, wave = {3000, 6000},
	},
	{
		// A forearc too far from any continent for its rivers to feed it, on a high that has stopped
		// rising or rises slowly, is bare old arc crust: pillow lavas and the breccia they shattered
		// into, tilted, cut by the dikes that fed them. As the Bonin ridge, which stands still; a
		// high rising as fast as Kikaijima's was deep under the sea until lately, and carries up
		// the beds laid on it there.
		name = "old arc lavas", after = "Hahajima; Chichijima", laid = .Plates,
		hosts = {{.Offshore, 140, ANY, 0}, {.Rising, -ANY, 1, 0}},   // beyond the 140 km where the beds a continent's rivers feed hold, and rising slower than the raised kind's 1 mm/yr
		kinds = {0 = {.Basalt, 2, ANYWHERE, NONE}, 1 = {.Breccia, 2, ANYWHERE, NONE}},
		thick = {10, 35}, hard = 0.4, gap = 60, tilt = {8, 20}, fold = {20, 60}, wave = {1500, 3000},
		bodies = {
			{.Dike, .Dolerite, {10, 18}, {1, 4}, {300, 1000}, NONE, {0, 0.35}},
			{.Plug, .Dolerite, {1, 2}, {100, 240}, NONE, NONE, {0.05, 0.3}},
		},
	},
	{
		// The basin's sediment tilted as the outer high rose under it: fed by a continent's rivers
		// where one is near, and elsewhere by the arc's ash and the reefs, and carried up where the
		// high rises fast. Wherever no row before it holds.
		name = "layered, gently tilted", after = "the Shimajiri mudstone under Kikaijima's reef; the Boso peninsula", laid = .Plates,
		// Grit gathers high in the stack and caps the hills; limestone is rare and low, so it
		// shows only in the deepest valleys.
		kinds = {
			{.Mudstone, 3, ANYWHERE, NONE}, {.Siltstone, 2, ANYWHERE, NONE}, {.Sandstone, 2, ANYWHERE, NONE},
			{.Grit, 0.4, {-1e5, 50}, NONE}, {.Grit, 3, {50, 1e5}, NONE}, {.Limestone, 1.2, {-1e5, -20}, NONE},
		},
		thick = {12, 50}, hard = 0.3, gap = 110, tilt = {3, 8}, fold = {20, 70}, wave = {1800, 4500},
		bodies = {{.Fault, .Air, {1, 3}, {30, 120}, {3000, 8000}, NONE, {0, 0.3}}},
	},
	{
		// Runny lava: black flows of basalt between beds of red cinders and ash, after the
		// sea cliffs of Toshima and Mikurajima, cut by the dikes that fed its flanks, which Toshima's
		// cliffs show.
		name = "lava and ash", after = "Toshima; Mikurajima", laid = .Runny_Lava,
		kinds = {0 = {.Basalt, 1, ANYWHERE, NONE}, 1 = {.Scoria, 1, ANYWHERE, NONE}},
		thick = {12, 40}, hard = 0.4, gap = 40, fold = {30, 70}, wave = {400, 1000}, drape = true, mantle = 0.35,
		bodies = {
			{.Dike, .Dolerite, {8, 16}, {1, 3}, {300, 900}, NONE, {0.1, 0.7}},   // basalt cooled slowly in its crack: dolerite, its columns lying across the wall
			{.Plug, .Dolerite, {1, 3}, {60, 160}, NONE, NONE, {0.2, 0.7}},
		},
	},
	{
		// Stiff lava: pale domes and thick flows of rhyolite in sheets of pumice and ash, after
		// Kōzushima.
		name = "pale lava and pumice", after = "Kōzushima", laid = .Stiff_Lava,
		kinds = {0 = {.Rhyolite, 1, ANYWHERE, NONE}, 1 = {.Tuff, 1, ANYWHERE, NONE}},
		thick = {10, 50}, hard = 0.5, gap = 60, fold = {15, 40}, wave = {600, 1500}, drape = true, mantle = 0.35,
		bodies = {
			{.Dike, .Rhyolite, {3, 6}, {2, 5}, {300, 800}, NONE, {0.1, 0.5}},
			{.Plug, .Rhyolite, {1, 2}, {120, 300}, NONE, NONE, {0.1, 0.5}},
		},
	},
	{
		// Reef: coral and the sand and rubble of its breaking, grown on a sunken bank as the island
		// rose (`reef` in the kind's shape, land.odin), over the soft grey mudstone of the bank, which
		// lies too deep to show above the sea. After the Ryukyu limestone of Kikaijima on its
		// Shimajiri mudstone. The beds are thin so the contact lies within 30 m of where it is put.
		name = "reef on mudstone", after = "Kikaijima", laid = .Coral,
		kinds = {0 = {.Mudstone, 1, {-1e5, -100}, NONE}, 1 = {.Reef, 1, {-100, 1e5}, NONE}},
		thick = {10, 30}, tilt = {0, 1}, fold = {5, 15}, wave = {3000, 5000},
	},
}

// The rocks the rain sinks into rather than running off them (the trait `.Sinks` in TRAITS,
// gen.odin), and the share of it that does: the reef, full of holes, which the water widens as it
// dissolves it (karst), so that few streams cut it.
SINKS :: bit_set[Trait]{.Sinks}
SOAKS :: 0.95

STACK_LO    :: -2048   // the table covers this far below the base
STACK_LEN   :: 8192    // and this far up: enough for the uplift still to come when the forming starts
COVER_AT    :: 4096    // where a cover's beds begin in the table, past every height the stack under it is read at
ROCK_LEVELS :: 5       // tables with the beds thinner than 1 to 16 m merged
ROCK_SIM    :: 4       // the table the 16 m land forming reads
AUREOLE     :: 120     // metres over a pluton's roof that its heat baked the beds (FORMS, gen.odin)
PLUTON_FOOT :: 400     // metres under the sea a pluton's roof lies at its edge
NO_COVER    :: 1e9
NO_ROOF     :: -1e9
ROOF_ALL    :: 1e9     // a dike's or plug's roof: it runs up through everything

// How a rock wears, from its strength: D4 in docs/foundations/geology.md, with erosion
// (0.4/strength)² rather than (0.5/strength)², which keeps the island near its old height.
// Slopes run from 35° on the weakest rock to 60° on rock of strength 0.8 and more, rising most
// steeply at the strong end, so that a strong bed stands as a face and the weak ones as steep
// hillsides, and creep falls with the square of weakness, so crests in strong rock stay sharp.
Rock_Law :: struct {
	erodes: f32,   // how fast running water cuts it, around 1
	limit:  f32,   // the steepest slope it holds, rise over run
	creep:  f32,   // how fast its hillsides creep, at most 1
	runs:   f32,   // the share of the rain on it that runs off rather than sinking in
}

Bed :: struct { kind: Mat, thick: f32 }

// A body as drawn for an island (Story_Body), relative to the region's middle.
Body :: struct {
	what:  Body_Kind,
	kind:  Mat,
	at:    [2]f64,   // a fault's or dike's middle, a plug's or pluton's
	along: [2]f64,   // the way a fault or dike runs
	long:  f64,      // a fault's or dike's length; a plug's radius; a pluton's radius at PLUTON_FOOT under the sea
	size:  f32,      // a fault's throw at its middle; a dike's width
	high:  f32,      // a pluton's top over the sea
	key:   u32,
}

// A land cell's cover and body (Grid.bodies, land.odin).
Grid_Body :: struct { cover, roof: f32, body: Mat }

// Whether the island's rock has a cover or a body wide enough for the land's cells to hold, so its
// grids keep them beside the stack's base: a dike is narrower than a cell and drops out.
rocks_held :: proc() -> bool {
	if rocks.cover != nil do return true
	for b in rocks.bodies do if b.what == .Plug || b.what == .Pluton || b.what == .Dike && f64(b.size) >= LAND_CELL/2 do return true
	return false
}

// What lies under a land cell.
grid_under :: #force_inline proc(g: ^Grid, c: int) -> Under {
	if g.bodies == nil do return {base = g.base[c], cover = NO_COVER, roof = NO_ROOF}
	b := g.bodies[c]
	return {base = g.base[c], cover = b.cover, roof = b.roof, body = b.body}
}

// What a column holds under it (rock_base), from which the rock at any height is a lookup (rock_in).
Under :: struct {
	base:  f32,    // height of the stack's base: its tilt and folds, the ground the vents built, the faults' throws
	cover: f32,    // height of the surface the cover lies on; NO_COVER where there is none
	roof:  f32,    // top of the body standing in place of the beds; NO_ROOF where there is none, ROOF_ALL for a dike or plug
	body:  Mat,    // what that body is
	crush: bool,   // in a fault's crushed core, where at the nearest level the rock is broken (FORMS)
}

Rocks :: struct {
	dip:    [2]f64,   // rise of the stack's base per metre east and south
	fold:   f32,
	wave:   f64,
	ridge:  [2]f64,   // the way across the folds' ridges, where they stand in ridges; zero where they do not
	table:  [ROCK_LEVELS][STACK_LEN]Mat,
	law:    [Mat]Rock_Law,
	beds:   [dynamic]Bed,       // the stack from the bottom up, as a one-metre cell sees it
	bed:    [STACK_LEN]u16,     // which of them each metre lies in
	floor:  [dynamic]f32,       // where each begins, metres from the table's start
	drape:  []f32,              // the ground the vents built, on a grid of DRAPE m, where the story lays its beds over it
	sinks:  bool,               // the rain sinks into some rock of the story (SINKS)
	full:   bool,               // read from the island's setting: its bodies, its cover and the rock's broken and gravel forms (story_for)
	cover:  ^Story,             // the story laid over the stack, or nil
	over:   f32,                // the height of the surface it lies on, over the base,
	slant:  [2]f64,             // its rise per metre east and south,
	swell:  f32,                // and how far its old hills and hollows stand from that, metres
	cover_at:   f32,            // where the cover's beds begin in the table, metres from its start
	cover_from: int,            // the first of them in `beds`
	bodies: [dynamic]Body,
}

DRAPE :: 32

// What laid a kind's rock, from what its history does: vents of runny lava (a cone's form, under
// 1.5) or stiff (a dome's), coral where it grows, and the plates otherwise.
laid_by :: proc(k: ^Kind) -> Laid {
	if k.shape.reef[1] > 0 do return .Coral
	for p in k.history do if p.vents[1] > 0 do return .Stiff_Lava if p.form[0] > 1.5 else .Runny_Lava
	return .Plates
}

HOLDS :: 0.5   // a story's host holds at an island where it scores this much or more

// The story read from the island's setting: of the rows laid as its kind's history lays rock, the
// first whose host holds at its middle, with the rows before it that did not hold; nil where none
// holds. It reads the island bound (region.origin).
story_read :: proc(k: ^Kind) -> (story: ^Story, passed: [dynamic]^Story) {
	p := Point{cell = 2000}
	passed = make([dynamic]^Story, context.temp_allocator)
	laid := laid_by(k)
	for &s in STORIES do if s.laid == laid {
		if host(s.hosts, &p) >= HOLDS do return &s, passed
		append(&passed, &s)
	}
	return nil, passed
}

// The story an island's rock tells, read from its setting (true); where no row's host holds, the one
// its kind names.
story_for :: proc(island: Island) -> (story: ^Story, read: bool) {
	if s, _ := story_read(&KINDS[island.kind]); s != nil do return s, true
	return region.story, true
}

// Draw the island's rock from its story and seed; with `full`, its bodies, its cover and its
// rock's four forms.
rock_init :: proc(full: bool) {
	story := region.story
	rocks.full = full
	draw :: proc(r: [2]f32, k: i32) -> f32 { return math.lerp(r[0], r[1], hash01(k, 0, seed + 301)) }
	dip, turn := math.tan(math.to_radians(f64(draw(story.tilt, 0)))), 2*math.PI*f64(hash01(1, 0, seed + 301))
	rocks.dip = {dip*math.cos(turn), dip*math.sin(turn)}
	rocks.fold, rocks.wave = draw(story.fold, 2), f64(draw(story.wave, 3))
	if story.ridges {
		across := 2*math.PI*f64(hash01(4, 0, seed + 301))
		rocks.ridge = {math.cos(across), math.sin(across)}
	}
	if story.drape {
		n := int(region.size)/DRAPE + 1
		rocks.drape = make([]f32, n*n)
		shared(n, rows(n), &n, proc(n: ^int, lo, hi: int) {
			for c in lo*n^..<hi*n^ do rocks.drape[c] = built(f64(c%n^*DRAPE) - region.size/2, f64(c/n^*DRAPE) - region.size/2)
		})
		fmt.printf("rock: %s, laid over the forms the vents built; folds %.0f m high every %.1f km", story.name, rocks.fold, rocks.wave/1000)
	} else {
		fmt.printf("rock: %s; beds dip %.1f° toward %.0f° (0 is north, 90 east), folds %.0f m high every %.1f km%s",
			story.name, draw(story.tilt, 0), math.mod(math.to_degrees(math.atan2(-math.cos(turn), math.sin(turn))) + 360, 360), rocks.fold, rocks.wave/1000,
			fmt.tprintf(" in ridges running %.0f°", math.mod(math.to_degrees(math.atan2(rocks.ridge.x, rocks.ridge.y)) + 360, 180)) if story.ridges else "")
	}
	for m in Mat {
		s := MATERIALS[m].strength
		if s == 0 do continue
		rocks.law[m] = {clamp(0.16/(s*s), 0.2, 5), math.tan(math.to_radians(35 + 25*math.pow(min((s - 0.2)/0.6, 1), 1.5))), (1 - s)*(1 - s)/0.5625, 1 - SOAKS if is(m, SINKS) else 1}
	}
	if full && story.cover != "" {
		for &s in STORIES do if s.name == story.cover do rocks.cover = &s
		c := rocks.cover
		tilt := draw(c.tilt, 20)
		slant, way := math.tan(math.to_radians(f64(tilt))), 2*math.PI*f64(hash01(21, 0, seed + 301))
		rocks.over, rocks.slant, rocks.swell = draw(story.over, 22), {slant*math.cos(way), slant*math.sin(way)}, draw(c.fold, 23)
		fmt.printf("; under %s from %.0f m over the base, dipping %.1f°", c.name, rocks.over, tilt)
	}
	for k in story.kinds do rocks.sinks ||= k.weight > 0 && is(k.kind, SINKS)

	// The beds, from the bottom of the stack up; a cover's from where it begins.
	beds: [dynamic]Bed
	defer delete(beds)
	lay :: proc(beds: ^[dynamic]Bed, story: ^Story, from, to: f32, key: u32) -> f32 {
		soft: f32   // metres of soft rock since the last hard bed
		at := from
		for i := i32(0); at < to; i += 1 {
			hard := hash01(i, 1, key + 1) < story.hard || soft > story.gap
			total: [2]f32   // weight of the soft and the hard kinds that may lie here
			for k in story.kinds do if at >= k.at[0] && at < k.at[1] do total[int(MATERIALS[k.kind].strength >= 0.5)] += k.weight
			if total[int(hard)] == 0 do hard = !hard
			pick := hash01(i, 2, key + 1)*total[int(hard)]
			bed := Bed{thick = math.lerp(story.thick[0], story.thick[1], hash01(i + 10, 0, key))}
			chosen: Story_Kind
			for k in story.kinds {
				if at < k.at[0] || at >= k.at[1] || (MATERIALS[k.kind].strength >= 0.5) != hard do continue
				bed.kind, chosen = k.kind, k
				pick -= k.weight
				if pick < 0 do break
			}
			if chosen.thick[1] > 0 do bed.thick = math.lerp(chosen.thick[0], chosen.thick[1], hash01(i + 10, 1, key))
			if hard do bed.thick = max(bed.thick, 20)   // so the 16 m land forming holds it
			append(beds, bed)
			at += bed.thick
			soft = 0 if hard else soft + bed.thick
		}
		return at
	}
	rocks.cover_at, rocks.cover_from = STACK_LEN, max(int)
	if rocks.cover == nil {
		lay(&beds, story, STACK_LO, STACK_LO + STACK_LEN, seed + 301)
	} else {
		rocks.cover_at = lay(&beds, story, STACK_LO, STACK_LO + COVER_AT, seed + 301) - STACK_LO
		lay(&beds, rocks.cover, 0, STACK_LEN - rocks.cover_at, seed + 305)
	}

	// Each table holds the stack with the beds thinner than its size merged into their
	// thicker neighbour. The land forming reads the one at its cell size, which is all it can
	// hold; what is drawn reads a finer one (rock_level).
	for level in 0..<ROCK_LEVELS {
		cell := f32(i32(1) << uint(level))
		for len(beds) > 1 {
			thin := -1
			for b, i in beds do if b.thick < cell && (thin < 0 || b.thick < beds[thin].thick) do thin = i
			if thin < 0 do break
			into := thin + 1
			if thin == len(beds) - 1 || (thin > 0 && beds[thin - 1].thick > beds[thin + 1].thick) do into = thin - 1
			beds[into].thick += beds[thin].thick
			ordered_remove(&beds, thin)
		}
		i, top := 0, f32(0)
		for b, n in beds {
			if level == 0 {
				append(&rocks.beds, b)
				append(&rocks.floor, top)
				if rocks.cover != nil && top >= rocks.cover_at - 0.5 && rocks.cover_from == max(int) do rocks.cover_from = n
			}
			top += b.thick
			for ; i < STACK_LEN && f32(i) < top; i += 1 {
				rocks.table[level][i] = b.kind
				if level == 0 do rocks.bed[i] = u16(n)
			}
		}
	}
	if full do bodies_draw(story)
	fmt.println()
}

// The bodies of the island's story, drawn from its seed, and a word for each kind of them.
bodies_draw :: proc(story: ^Story) {
	stretch := region.size/REFERENCE
	for sb, j in story.bodies {
		n := int(math.round(math.lerp(sb.count[0], sb.count[1], hash01(i32(j), 0, seed + 309))))
		if n == 0 do continue
		swarm := 2*math.PI*f64(hash01(i32(j), 1, seed + 309))   // the way the story's dikes run
		lo, hi := f32(1e9), f32(0)
		for k in 0..<n {
			key := seed + 310 + u32(j*64 + k)
			r :: proc(range: [2]f32, key: u32, n: i32) -> f32 { return math.lerp(range[0], range[1], hash01(n, 0, key)) }
			turn := 2*math.PI*f64(hash01(3, 0, key))
			dir := [2]f64{math.cos(turn), math.sin(turn)}
			b := Body{what = sb.what, kind = sb.kind, size = r(sb.size, key, 0), high = r(sb.high, key, 1), long = f64(r(sb.long, key, 2))*stretch, key = key}
			out := f64(r(sb.out, key, 4))
			b.at, b.along = out*region.size*dir, {math.cos(turn + 1.3), math.sin(turn + 1.3)}
			if story.drape && len(region.vents) > 0 && (sb.what == .Dike || sb.what == .Plug) {
				// Out from a vent, as the dikes that fed its flanks run.
				v := region.vents[hash(i32(k), 5, key) % u32(len(region.vents))]
				b.at, b.along = v.at + out*f64(v.reach)*dir, dir
			} else if sb.what == .Dike {
				t := swarm + 0.35*(f64(hash01(6, 0, key)) - 0.5)
				b.along = {math.cos(t), math.sin(t)}
			}
			if sb.what == .Plug do b.long = f64(b.size)/2
			append(&rocks.bodies, b)
			lo, hi = min(lo, b.size if sb.what != .Pluton else f32(b.long)), max(hi, b.size if sb.what != .Pluton else f32(b.long))
		}
		switch sb.what {
		case .Fault:  fmt.printf("; %d fault%s throwing %.0f to %.0f m", n, "s" if n > 1 else "", lo, hi)
		case .Dike:   fmt.printf("; %d dike%s of %v %.0f to %.0f m wide", n, "s" if n > 1 else "", sb.kind, lo, hi)
		case .Plug:   fmt.printf("; %d plug%s of %v %.0f to %.0f m across", n, "s" if n > 1 else "", sb.kind, lo, hi)
		case .Pluton: fmt.printf("; a pluton of %v, its roof %.0f m over the sea at its top and %.0f m under it %.1f km out", sb.kind, rocks.bodies[len(rocks.bodies) - 1].high, f32(PLUTON_FOOT), lo/1000)
		}
	}
}

// Where a point lies against a fault: how far across its trace (over 0 on its lifted side), how
// far along it from its middle, and how much of its throw it has there, 0 past its ends.
fault_at :: proc(b: Body, x, z, cell: f64) -> (across, along: f64, share: f32) {
	d := [2]f64{x, z} - b.at
	along = d.x*b.along.x + d.y*b.along.y
	across = d.y*b.along.x - d.x*b.along.y
	if abs(along) >= b.long/2 do return across, along, 0
	bend := 0.05*b.long
	if abs(across) < bend + 60 do across += bend*f64(fbm(along, 0, b.long/3, cell, 2, b.key))
	t := 2*along/b.long
	return across, along, f32(1 - t*t)
}

// What lies under a point, as seen at a cell size: the height of the stack's base (the tilt, the
// folds, the ground the vents built and the faults' throws), the surface a cover lies on, and the
// body standing there. Bodies narrower than half a cell drop out, as `band` drops noise.
rock_base :: proc(x, z, cell: f64) -> (u: Under) {
	fold := fbm(x, z, rocks.wave, cell, 2, seed + 303)
	if rocks.ridge != {} do fold = f32(math.sin(2*math.PI*(x*rocks.ridge.x + z*rocks.ridge.y)/rocks.wave + 2*f64(fold)))   // parallel ridges, bent by the same noise
	u = {base = f32(rocks.dip.x*x + rocks.dip.y*z) + rocks.fold*fold + drape_at(x, z), cover = NO_COVER, roof = NO_ROOF}
	if !rocks.full do return
	if rocks.cover != nil do u.cover = rocks.over + f32(rocks.slant.x*x + rocks.slant.y*z) + rocks.swell*fbm(x, z, 2500, cell, 2, seed + 304)
	for b in rocks.bodies {
		switch b.what {
		case .Fault:
			across, _, share := fault_at(b, x, z, cell)
			if share == 0 do continue
			if across > 0 do u.base += b.size*share
			if cell <= 2 && abs(across) < f64(1 + b.size*share/40) do u.crush = true
		case .Dike:
			if f64(b.size) < cell/2 do continue
			d := [2]f64{x, z} - b.at
			t := 2*(d.x*b.along.x + d.y*b.along.y)/b.long
			if abs(t) >= 1 do continue
			if abs(d.y*b.along.x - d.x*b.along.y) < f64(b.size)/2*math.sqrt(1 - t*t) do u.roof, u.body = ROOF_ALL, b.kind
		case .Plug:
			if b.long < cell/2 do continue
			r := math.hypot(x - b.at.x, z - b.at.y)
			if r > 1.4*b.long do continue
			w, _, _ := noise(x/b.long, z/b.long, b.key)
			if r < b.long*(0.8 + 0.5*f64(w)) do u.roof, u.body = ROOF_ALL, b.kind
		case .Pluton:
			r := math.hypot(x - b.at.x, z - b.at.y)
			if r > 1.8*b.long do continue
			r *= 1 + 0.15*f64(fbm(x, z, b.long/2, cell, 2, b.key))
			if roof := b.high - (b.high + PLUTON_FOOT)*f32((r/b.long)*(r/b.long)); roof > u.roof do u.roof, u.body = roof, b.kind
		}
	}
	return
}

// How much faster water cuts the ground at a point than its rock alone says: up to three times
// along a fault, whose crushed rock it follows (Rock_Law; land.odin multiplies it into `soft`).
rock_weak :: proc(x, z: f64) -> (w: f32) {
	w = 1
	for b in rocks.bodies do if b.what == .Fault {
		across, _, share := fault_at(b, x, z, LAND_CELL)
		w = max(w, 1 + 2*share*smoothstep(40, 0, f32(abs(across))))
	}
	return
}

drape_at :: proc(x, z: f64) -> f32 {
	if len(rocks.drape) == 0 do return 0
	n := int(region.size)/DRAPE + 1
	u, v := clamp((x + region.size/2)/DRAPE, 0, f64(n) - 1.001), clamp((z + region.size/2)/DRAPE, 0, f64(n) - 1.001)
	i, j := int(u), int(v)
	tu, tv := f32(u - f64(i)), f32(v - f64(j))
	k := j*n + i
	return math.lerp(math.lerp(rocks.drape[k], rocks.drape[k + 1], tu), math.lerp(rocks.drape[k + n], rocks.drape[k + n + 1], tu), tv)
}

// Which way the beds run level at a point, across the slope of the stack's base: along the
// folds' ridges where they stand in ridges.
rock_strike :: proc(x, z: f64) -> [2]f64 {
	d := rocks.dip + [2]f64{f64(drape_at(x + 8, z) - drape_at(x - 8, z)), f64(drape_at(x, z + 8) - drape_at(x, z - 8))}/16
	if rocks.ridge != {} do d = rocks.ridge
	l := math.hypot(d.x, d.y)
	return [2]f64{-d.y, d.x}/l if l > 1e-6 else {1, 0}
}

// The base of the stack a height reads: the stack's own below the cover's surface, the cover's above it.
stack_base :: #force_inline proc(y: f32, u: Under) -> f32 {
	return u.base if y < u.cover else u.cover - rocks.cover_at - STACK_LO
}

// The base of the stack bed `n` belongs to.
bed_base :: #force_inline proc(n: int, u: Under) -> f32 {
	return u.base if n < rocks.cover_from else u.cover - rocks.cover_at - STACK_LO
}

// The bed of the stacks at a height, or -1 inside a body.
bed_at :: #force_inline proc(y: f32, u: Under) -> int {
	if y < u.roof do return -1
	return int(rocks.bed[clamp(int(y - stack_base(y, u) - STACK_LO), 0, STACK_LEN - 1)])
}

// The rock at height y over a point, from one level's table: the body there, or the bed, baked
// near a pluton's roof.
rock_in :: #force_inline proc(y: f32, u: Under, level: int) -> Mat {
	if y < u.roof do return u.body
	m := rocks.table[level][clamp(int(y - stack_base(y, u) - STACK_LO), 0, STACK_LEN - 1)]
	if y < u.roof + AUREOLE do if b := FORMS[m].baked; b != .Air do m = b
	return m
}

// Which table a cell size is drawn from. A far face is drawn in whole metres however wide its
// cells are, so its beds are merged only once they are thinner than a quarter of a cell, about
// two pixels where that cell is in use; merged at the cell's own size, every face beyond 4 km
// lost its upper beds and beyond 9 km was one rock.
rock_level :: proc(cell: f64) -> int {
	return clamp(int(math.log2(cell)) - 2, 0, ROCK_LEVELS - 1)
}

// The rock at a point, as seen at a cell size.
rock :: proc(x, y, z, cell: f64) -> Mat {
	return rock_in(f32(y), rock_base(x, z, cell), rock_level(cell))
}

// The gravel the stream through each land cell carries (`pebble`, land.odin): the rock most of the
// land it drains is cut in, of the rocks strong enough to stay gravel (strength 0.5 or more), as a
// count carried down the drainage that keeps the rock with the most cells behind it (a majority
// vote: exact where one rock has more than half). Weaker rock is ground to sand and mud.
pebbles_make :: proc(g: ^Grid) {
	Vote :: struct { kind: Mat, count: f32 }
	vote :: proc(v: ^Vote, kind: Mat, count: f32) {
		if v.kind == kind || v.count == 0 do v^ = {kind, v.count + count}
		else if v.count >= count do v.count -= count
		else do v^ = {kind, count - v.count}
	}
	votes := make([]Vote, g.n*g.n, context.temp_allocator)
	delete(land.pebble)
	land.pebble = make([]Mat, g.n*g.n)
	#reverse for ci in g.order {
		c := int(ci)
		if own := rock_in(g.z[c] - 0.5, grid_under(g, c), ROCK_SIM); MATERIALS[own].strength >= 0.5 do vote(&votes[c], own, 1)
		land.pebble[c] = votes[c].kind if votes[c].count > 0 else .Air
		if r := g.next[c]; r >= 0 do vote(&votes[r], votes[c].kind, votes[c].count)
	}
}

// What --why says of the island's rock: which story it tells and why, and why not each row before it.
story_words :: proc() {
	s := region.story
	kind := &KINDS[here.island.kind]
	read, passed := story_read(kind)
	fmt.printf("the rock tells the story %s, after %s", s.name, s.after)
	LAID := [Laid]string{.Plates = "the plates laid it before and as the island rose", .Runny_Lava = "its vents poured it out as runny lava", .Stiff_Lava = "its vents pushed it up as stiff lava", .Coral = "coral built it as the island rose"}
	fmt.printf(". %s; of the stories so laid, it is the first whose host holds at the island's middle", LAID[laid_by(kind)])
	p := Point{cell = 2000}
	short :: proc(w: Window, p: ^Point) -> string {
		f := FIELDS[w.field]
		return fmt.tprintf("%s %.3g%s, where it needs %s", f.name, f.at(p), f.unit, fmt.tprintf("over %.3g", w.lo) if w.hi >= ANY else fmt.tprintf("up to %.3g", w.hi) if w.lo <= -ANY else fmt.tprintf("%.3g to %.3g", w.lo, w.hi))
	}
	if read == nil do fmt.printf(": none holds, so it is the one the %s kind names", kind.name)
	else if len(s.hosts) == 0 do fmt.printf(", and it holds wherever none before it does")
	else do for w, i in s.hosts do fmt.printf("%s %s", ": here" if i == 0 else ";", short(w, &p))
	for o in passed {
		worst, by := Window{}, f32(ANY)
		for w in o.hosts do if v := FIELDS[w.field].at(&p); score(w, v) < by do worst, by = w, score(w, v)
		fmt.printf("; not %s: %s", o.name, short(worst, &p))
	}
	fmt.println(".")
}

// The bodies cutting the island's beds, where they lie in the world, as --survey lists them.
bodies_words :: proc() {
	if len(rocks.bodies) > 0 do fmt.print("\n  bodies in the rock:")
	o := [2]f64{f64(region.origin.x), f64(region.origin.y)}
	for b in rocks.bodies {
		a, e := o + b.at - b.along*b.long/2, o + b.at + b.along*b.long/2
		switch b.what {
		case .Fault:  fmt.printf(" a fault throwing %.0f m from %.0f, %.0f to %.0f, %.0f;", b.size, a.x, a.y, e.x, e.y)
		case .Dike:   fmt.printf(" a dike of %v %.1f m wide from %.0f, %.0f to %.0f, %.0f;", b.kind, b.size, a.x, a.y, e.x, e.y)
		case .Plug:   fmt.printf(" a plug of %v %.0f m across at %.0f, %.0f;", b.kind, 2*b.long, o.x + b.at.x, o.y + b.at.y)
		case .Pluton: fmt.printf(" a pluton of %v at %.0f, %.0f, its top %.0f m over the sea;", b.kind, o.x + b.at.x, o.y + b.at.y, b.high)
		}
	}
}

// The rock at a point in the region and the bodies near it, as --why says them.
rock_words :: proc(x, z, h: f64) {
	u := rock_base(x, z, 1)
	y := f32(h) - 0.5
	m := rock_in(y, u, 0)
	fmt.printf("the rock under the ground is %v", m)
	if y < u.roof {
		fmt.printf(", %s", "a dike or plug that cuts the beds" if u.roof >= ROOF_ALL else "the pluton itself")
	} else {
		if y >= u.cover do fmt.printf(", of the %s laid on a surface worn across the beds %.0f m up", rocks.cover.name, u.cover)
		if b := FORMS[rock_in(y, {base = u.base, cover = u.cover, roof = NO_ROOF}, 0)].baked; y < u.roof + AUREOLE && b != .Air do fmt.printf(", baked from the bed by the pluton %.0f m under it", y - u.roof)
		else if n := bed_at(y, u); n >= 0 do fmt.printf(", a bed %.0f m thick", rocks.beds[n].thick)
	}
	if u.crush do fmt.printf(", broken in the crushed core of a fault")
	for b in rocks.bodies do if b.what == .Fault {
		across, _, share := fault_at(b, x, z, 1)
		if share > 0 && abs(across) < 300 do fmt.printf("; %.0f m from a fault %.1f km long, which lifts the beds %.0f m here on %s", abs(across), b.long/1000, b.size*share, "this side" if across > 0 else "its far side")
	}
	fmt.println(".")
}
