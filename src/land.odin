package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:os"
import "core:slice"
import "core:time"

// The land is formed before play. An island is pushed up out of the sea for about four
// million years while running water cuts it down, hillsides slump to the steepest
// angle they can hold, the sea cuts its exposed shores back into cliffs and what the streams
// carry down fills its sheltered bays. Valleys, ridges, flats and the river network come out of
// that together, which is the point: a river here is the reason its valley exists.
//
// The work runs coarse to fine. Most of the time passes on a 64 m grid, where a step is
// cheap; each refinement doubles the detail and runs long enough for the next size of
// valley to cut in.

LAND_CELL :: 16          // metres, on the finest grid
ERODE     :: 1.3e-5      // how fast water cuts: per year, times root of drainage area, times slope
CREEP     :: 0.012       // m²/yr of soil creep, which rounds hilltops, on the weakest rock

CHANNEL_AREA :: 120_000   // m² of land that must drain through a cell before its valley is a stream's, as the real islands were measured; streams themselves begin higher (HEAD_AREA, rivers.odin)

// What kind of island this is lives in one record, drawn from the seed within the ranges of
// a kind's row. Forming reads nothing else, so a seed and a record make the same land
// wherever the region lies. Lengths in a row are metres on a region 8,192 m across and
// stretch with the region; heights, rates and years are true.
REFERENCE :: 8192

// The island's outline, and the pattern it rises in.
Shape :: struct($T: typeid) {
	radius:              T,   // of the island at the start, as a share of the region's side; 0 for none, where vents build it from the sea floor
	xx, zz, xz:          T,   // how the outline, and the forms the vents build, are stretched and turned
	ragged, ragged_wave: T,   // the coast wanders in and out by this share of the radius, over this distance
	rate:                T,   // uplift at the heart of the island, m/yr
	swell:               T,   // the bearing the swell and the wind that raises it come from, degrees from north
	silt:                T,   // the share of what the rivers carry down that settles where the sea is sheltered
	floor:               T,   // the share of it found everywhere, to the shore,
	ridge:               T,   // and more along a range
	axis:                T,   // that runs east to west this far south of the middle,
	bend, bend_wave:     T,   // swinging this far north and south over this distance,
	wander, wander_wave: T,   // wandering this far besides,
	width:               T,   // and this wide.
	lumps, lumps_wave:   T,   // The uplift, and the fall of a vent's form, vary by this share over this distance.
	taper:               T,   // the uplift dies away to nothing toward the outline over this share of the way in from it; 0 for none
	bank:                T,   // the share of the uplift the sea floor inside the outline takes; 0 where it stands still, as in the kinds made before the reef
	reef:                T,   // m/yr coral builds up toward the sea where the water over it is shallower than REEF_DEPTH; 0 in a cold sea
}

// A stretch of the island's history: steps of so many years on cells of a size, with the
// island rising at a share of the shape's rate, begun by the sea rising (or, below zero,
// falling) so many metres. Cells halve from one phase to the next or stay.
//
// Vents may open at a phase's start, each `spread` metres from the middle of the vents of the
// phase before (from the region's middle, for the first). Over the phase each raises the
// ground at its top by `build` metres and lays what it erupts over the land and sea around,
// filling valleys and building out into the sea, in a form that falls away from its top as
// distance to the power `form`, `flank` metres a metre on average down to the ground it was
// built on. What is erupted decides the form: runny lava and ash (under 1) build a cone whose
// flanks steepen toward its top, stiff lava (over 1) a dome with a broad top and steep sides.
// At the phase's end a vent's top may fall in within `crater` metres of it, to a closed floor
// `deep` metres under the lowest point of what is left of its rim.
Phase :: struct($T: typeid) {
	cell:  int,
	years: f32,   // per step
	steps, uplift, sea: T,
	vents, spread, build, form, flank, crater, deep: T,
}

// The real islands the kinds and stories stand for, by the figures start-up prints (measured on the
// game's own grid: interesting-world/notes/real-islands.md): metres standing within 100 m of the
// shore, the share of shore rising 30 m within 50 m, the slope of the first 100 m, the share of land
// under 50 m and over 60°, the fall at a crest, the height above the nearest stream and the deepest
// closed hollow; and the streams' figures (interesting-world/notes/real-hydrology.md): km of stream
// draining CHANNEL_AREA or more for each km² of land, and the largest basin that reaches the sea,
// km², in the window where a window cuts the island (Aogashima's crater, whose water sinks, is not one). An island is judged against the islands its rock's story names (`judged` in
// STORIES), or where it names none, against those its kind is after; not against all of them.
// Yakushima is an 8 km window from its south coast up its granite to 1,731 m.
Real :: struct { name: string, v: [10]f32 }
REAL := [?]Real{
	{"Toshima", {82, 65, 40, 14, 1.2, 0.19, 130, 2, 0.49, 0.2}}, {"Mikurajima", {117, 81, 51, 5, 2.5, 0.69, 122, 7, 1.58, 2.6}}, {"Aogashima", {107, 85, 50, 9, 2.9, 0.63, 96, 77, 0.99, 0.2}},
	{"Kōzushima", {70, 48, 34, 14, 1.8, 0.56, 72, 10, 1.26, 1.9}}, {"Hahajima", {85, 85, 39, 16, 1.9, 0.81, 79, 9, 0.92, 1.9}}, {"Chichijima", {60, 67, 29, 28, 0.8, 0.73, 54, 7, 1.19, 3.5}},
	{"Kikaijima", {4, 0, 2, 57, 0, 0.05, 10, 1, 1.83, 4.4}}, {"Tsushima", {39, 40, 24, 74, 0, 1.25, 29, 4, 0.32, 0.7}}, {"Yakushima", {24, 4, 15, 6, 0.0, 0.42, 80, 3, 2.05, 11.7}},
}

// The real islands the island is judged against, and whether its rock's story names them.
judged_by :: proc() -> (names: []string, by_story: bool) {
	if region.story != nil && len(region.story.judged) > 0 do return region.story.judged, true
	for k in KINDS do if k.name == region.kind do return k.after, false
	return nil, false
}

// A figure of ours beside the same on the islands this one is judged against, with a ! where ours
// lies outside theirs by more than half as much again and `slack`.
against :: proc(i: int, ours: f32, format: string, slack: f32) -> string {
	lo, hi := max(f32), min(f32)
	names, _ := judged_by()
	for name in names do for r in REAL do if r.name == name do lo, hi = min(lo, r.v[i]), max(hi, r.v[i])
	if lo > hi do return fmt.tprintf(format, ours)
	real := fmt.tprintf(format, lo) if lo == hi else fmt.tprintf("%s-%s", fmt.tprintf(format, lo), fmt.tprintf(format, hi))
	return fmt.tprintf("%s (%s)%s", fmt.tprintf(format, ours), real, "!" if ours > 1.5*hi + slack || ours < lo/1.5 - slack else "")
}

Kind :: struct {
	name:    string,
	after:   []string, // the real islands it stands for (REAL); none is a guess
	weight:  f32,      // how often the seed draws this kind, against the other rows' weights
	story:   string,   // what an island's rock is where no story's host holds at its middle (story_for, rock.odin)
	hosts:   [][]Window, // where the world's plates put it, on the world's fields (archipelago.odin): it takes the best of them
	shape:   Shape([2]f64),
	history: []Phase([2]f32),
}

KINDS := [?]Kind{
	{
		// A long island, a range north of its middle and a south slope with room for rivers. It
		// rises for 3 to 4 million years, and the sea then rises 40 to 60 m into the mouths of its
		// valleys, leaving coves between the cliffs; much more and it is the inlets kind. After
		// Hahajima, though its shore is half as long.
		name = "ridge", after = {"Hahajima"}, weight = 3, story = "layered, gently tilted",
		hosts = {{{.Rising, 0.3, 1.2, 0.5}, {.Front, 12, ANY, 4}, {.Depth, -ANY, 4000, 300}}},   // rising steadily, off the volcanic front, on a raised floor: the forearc's flanks
		shape = {
			radius = {0.35, 0.39}, xx = {0.85, 1.0}, zz = {1.3, 1.8}, xz = {-0.4, 0.4}, ragged = {0.35, 0.45}, ragged_wave = {2500, 3500},
			rate = {0.00055, 0.0007}, swell = {0, 360}, silt = {0.1, 0.3}, floor = {0.25, 0.35}, ridge = {0.8, 1.1},
			axis = {-1100, -600}, bend = {250, 550}, bend_wave = {1400, 2200}, wander = {250, 450}, wander_wave = {2000, 3000}, width = {850, 1200},
			lumps = {0.3, 0.45}, lumps_wave = {1800, 2600},
		},
		history = {
			{cell = 64, years = 20000, steps = {140, 175}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {40, 60}, uplift = {1, 1}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {1, 1}},
			{cell = 16, years = 1000, steps = {5, 8}, uplift = {1, 1}, sea = {40, 60}},   // the last rise, and the thousands of years since
		},
	},
	{
		// Drowned: a ridge island, larger, that the sea rose 115 to 120 m into at the end of the
		// last ice age, so its valleys are long branching inlets between high steep spurs, and in
		// the 5,000 to 8,000 years since the rivers have filled the head of each with a flat.
		// After Tsushima's Asō Bay and Chichijima.
		name = "inlets", after = {"Tsushima", "Chichijima"}, weight = 3, story = "layered, gently tilted",
		hosts = {{{.Rising, -ANY, 0.3, 0.3}, {.Age, 1, ANY, 0.5}, {.Front, 12, ANY, 4}, {.Depth, -ANY, 4000, 300}}},   // rising slowly or sinking, so the sea drowned its valleys once they were cut
		shape = {
			radius = {0.40, 0.42}, xx = {0.85, 1.0}, zz = {1.15, 1.35}, xz = {-0.4, 0.4}, ragged = {0.35, 0.45}, ragged_wave = {2500, 3500},
			rate = {0.0004, 0.0005}, swell = {0, 360}, silt = {0.4, 0.8}, floor = {0.25, 0.35}, ridge = {0.8, 1.1},
			axis = {-1100, -600}, bend = {250, 550}, bend_wave = {1400, 2200}, wander = {250, 450}, wander_wave = {2000, 3000}, width = {850, 1200},
			lumps = {0.3, 0.45}, lumps_wave = {1800, 2600},
		},
		history = {
			{cell = 64, years = 20000, steps = {140, 175}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {40, 60}, uplift = {1, 1}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {1, 1}},
			{cell = 16, years = 1000, steps = {5, 8}, uplift = {1, 1}, sea = {115, 120}},
		},
	},
	{
		// A cone after Toshima and Mikurajima, the rare inhospitable kind: one vent builds it out
		// of the sea from lava and ash in a few tens of thousands of years, and the sea and its
		// streams then cut it for a few hundred thousand, into a wall of cliffs round radial gorges.
		name = "cone", after = {"Toshima", "Mikurajima"}, weight = 1, story = "lava and ash",
		hosts = {{{.Front, 0, 6, 4}, {.Vent, -ANY, 1, 0.5}, {.Crust, -ANY, 22, 4}}},   // a young vent on the volcanic front, of runny lava from an arc's thin crust
		shape = {xx = {0.9, 1.1}, zz = {0.9, 1.1}, xz = {-0.2, 0.2}, rate = {0.0012, 0.0016}, swell = {0, 360}, silt = {0, 0.1}, lumps = {0.05, 0.1}, lumps_wave = {2000, 3000}},
		history = {
			{cell = 64, years = 2000, steps = {15, 25}, vents = {1, 1}, spread = {0, 400}, build = {700, 1000}, form = {0.7, 0.9}, flank = {0.28, 0.38}},
			{cell = 64, years = 10000, steps = {25, 40}, uplift = {1, 1}},
			{cell = 32, years = 5000, steps = {30, 30}, uplift = {1, 1}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {1, 1}},
			{cell = 16, years = 1000, steps = {5, 8}, uplift = {1, 1}, sea = {3, 8}},
		},
	},
	{
		// A crater after Aogashima: a steep cone of lava and ash, cut by the sea into cliffs for a
		// few hundred thousand years, whose top then falls in after a last small eruption, leaving
		// a rim round a closed floor, in which a small cone grows with a crater of its own.
		name = "crater", after = {"Aogashima"}, weight = 1, story = "lava and ash",
		hosts = {{{.Front, 0, 6, 4}, {.Vent, 0.6, ANY, 0.3}}},   // a vent on the front long at work, whose top falls in at the end of its life
		shape = {xx = {0.75, 1}, zz = {1, 1.3}, xz = {-0.3, 0.3}, rate = {0.0011, 0.0015}, swell = {0, 360}, silt = {0, 0.1}, lumps = {0.04, 0.08}, lumps_wave = {1500, 2500}},
		history = {
			{cell = 64, years = 2000, steps = {15, 20}, vents = {1, 1}, build = {880, 980}, form = {1, 1.2}, flank = {0.55, 0.65}},
			{cell = 64, years = 10000, steps = {5, 10}, uplift = {1, 1}},
			{cell = 32, years = 5000, steps = {30, 40}, uplift = {1, 1}},
			{cell = 16, years = 3000, steps = {25, 30}, uplift = {1, 1}},
			{cell = 16, years = 500, steps = {2, 3}, vents = {1, 1}, spread = {0, 200}, build = {20, 40}, form = {0.6, 0.8}, flank = {0.3, 0.4}, crater = {550, 700}, deep = {60, 110}},
			{cell = 16, years = 500, steps = {3, 5}, vents = {1, 1}, spread = {0, 250}, build = {80, 140}, form = {0.6, 0.8}, flank = {0.3, 0.4}, crater = {50, 90}, deep = {10, 25}},
			{cell = 16, years = 1000, steps = {3, 5}, sea = {3, 8}},
		},
	},
	{
		// Domes after Kōzushima: an explosive vent spreads a low fan of pumice and ash, then
		// several vents of stiff pale lava pile steep-sided domes on it, with bays where the sea
		// lies between them. The sea cuts the headlands, the streams fill the bays' heads, and at
		// last a young dome grows with a shallow sunken top.
		name = "domes", after = {"Kōzushima"}, weight = 2, story = "pale lava and pumice",
		hosts = {{{.Front, 0, 6, 4}, {.Crust, 20, ANY, 4}}},   // a vent on the front over thick crust, which melts to stiff pale lava
		shape = {xx = {0.9, 1.1}, zz = {0.9, 1.1}, xz = {-0.2, 0.2}, rate = {0.0011, 0.0016}, swell = {0, 360}, silt = {0.2, 0.5}, lumps = {0.15, 0.25}, lumps_wave = {1500, 2500}},
		history = {
			{cell = 64, years = 2000, steps = {3, 5}, vents = {1, 1}, spread = {0, 600}, build = {230, 290}, form = {2.5, 3.5}, flank = {0.1, 0.13}},
			{cell = 64, years = 2000, steps = {10, 15}, vents = {4, 6}, spread = {1000, 2300}, build = {350, 550}, form = {2, 3.5}, flank = {0.35, 0.5}},
			{cell = 32, years = 5000, steps = {8, 12}, uplift = {1, 1}},
			{cell = 16, years = 3000, steps = {10, 15}, uplift = {1, 1}},
			{cell = 16, years = 1000, steps = {3, 5}, vents = {1, 1}, spread = {0, 1000}, build = {250, 350}, form = {2.5, 3.5}, flank = {0.35, 0.45}, crater = {150, 250}, deep = {10, 30}},
			{cell = 16, years = 1000, steps = {5, 8}, sea = {3, 8}},
		},
	},
	{
		// Worn down: it rose as the ridge island does, then the uplift stopped some 400,000 years
		// ago, the sea rose into its valleys, and the land has been wearing away and the waves
		// cutting the new shore since: low rounded hills round wide bays whose heads have filled
		// with flats. No real island in the set is close; the drowned ones are the inlets kind.
		// Much longer at rest and it wears down to the sea.
		name = "worn", after = {}, weight = 2, story = "layered, gently tilted",
		hosts = {{{.Rising, -ANY, 0.05, 0.25}, {.Age, 2.5, ANY, 1}, {.Front, 12, ANY, 4}, {.Depth, -ANY, 4000, 300}}},   // still or sinking, and long enough for the land to wear low
		shape = {
			radius = {0.34, 0.38}, xx = {0.85, 1.15}, zz = {0.85, 1.2}, xz = {-0.5, 0.5}, ragged = {0.35, 0.5}, ragged_wave = {2500, 3500},
			rate = {0.0005, 0.0007}, swell = {0, 360}, silt = {0.1, 0.3}, floor = {0.3, 0.5}, ridge = {0.6, 0.95},
			axis = {-900, 900}, bend = {200, 500}, bend_wave = {1500, 2500}, wander = {200, 400}, wander_wave = {2500, 2500}, width = {1000, 1400},
			lumps = {0.3, 0.5}, lumps_wave = {2000, 3000},
		},
		history = {
			{cell = 64, years = 20000, steps = {150, 170}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {40, 60}, uplift = {0, 0}, sea = {20, 40}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {0, 0}},
			{cell = 16, years = 1000, steps = {5, 8}, uplift = {0, 0}, sea = {4, 8}},
		},
	},
	{
		// Raised: the sea fell twice late in the island's rise and uncovered the platform its
		// waves had cut, broad where the swell struck and narrow in the lee, so the old cliff
		// stands behind a terrace, and the streams crossing it cut back into it, the larger
		// faster, until a last rise of 10 to 20 m floods their mouths into small coves. A step for
		// each fall waits for the sea to cut its own shore. After Kikaijima, though steeper behind
		// its terraces.
		name = "raised", after = {"Kikaijima"}, weight = 2, story = "layered, gently tilted",
		hosts = {{{.Rising, 1, ANY, 0.5}, {.Front, 12, ANY, 4}, {.Depth, -ANY, 4000, 300}}},   // rising fast: the forearc's outer ridge
		shape = {
			radius = {0.26, 0.30}, xx = {0.8, 1.2}, zz = {0.8, 1.25}, xz = {-0.5, 0.5}, ragged = {0.3, 0.45}, ragged_wave = {2500, 3500},
			rate = {0.0005, 0.0007}, swell = {0, 360}, silt = {0.1, 0.3}, floor = {0.3, 0.5}, ridge = {0.6, 0.95},
			axis = {-900, 900}, bend = {200, 500}, bend_wave = {1500, 2500}, wander = {200, 400}, wander_wave = {2500, 2500}, width = {1000, 1400},
			lumps = {0.3, 0.5}, lumps_wave = {2000, 3000},
		},
		history = {
			{cell = 64, years = 20000, steps = {150, 170}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {40, 50}, uplift = {1, 1}, sea = {-8, -12}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {1, 1}, sea = {-8, -12}},
			{cell = 16, years = 1000, steps = {5, 8}, uplift = {1, 1}, sea = {10, 20}},
		},
	},
	{
		// Reef, after Kikaijima: a bank lies drowned in a warm sea, and rises with the island, most
		// along a line and in lumps a few hundred metres across, nothing at its edge, while the sea
		// falls and rises with the ice six times in 100,000 years, each time to about where it
		// stands today. Each rise floods a band of the land the last fall left, coral fills it up
		// to the sea as a flat in a few thousand years, and the next fall leaves that flat as a
		// terrace over the reef's front: the island comes up a ring at a time, a flight of terraces
		// round the oldest, highest flat, and only a few metres of each rise reach the slowly rising
		// shore. The rain sinks into the reef, so no stream cuts it. Where its host holds as well as
		// the raised kind's, it is as likely: no field says yet how warm or clear the sea is, which
		// decides whether coral caps a rising bank. (At weight 0 it lost every such tie, and stood on
		// the forearc only where a neighbour had taken the raised kind.)
		name = "reef", after = {"Kikaijima"}, weight = 2, story = "reef on mudstone",
		hosts = {
			{{.Rising, 1.2, ANY, 0.4}, {.Front, 12, ANY, 4}, {.Depth, -ANY, 4000, 300}},   // rising fast on the forearc, as Kikaijima on the Ryukyu forearc's outer ridge
			{{.Setting, 4.5, 5, 0}, {.Rising, 0.1, ANY, 0.2}},                            // or a little on the shelf
		},
		shape = {
			radius = {0.36, 0.39}, xx = {0.82, 0.92}, zz = {1.15, 1.35}, xz = {-0.4, 0.4}, ragged = {0.1, 0.2}, ragged_wave = {2500, 3500},
			rate = {0.0016, 0.0019}, swell = {0, 360}, floor = {0.3, 0.4}, ridge = {0.6, 0.7},
			axis = {-1100, 1100}, bend = {100, 300}, bend_wave = {2500, 3500}, wander = {100, 200}, wander_wave = {3000, 4000}, width = {900, 1200},
			lumps = {0.45, 0.55}, lumps_wave = {500, 850}, taper = {0.9, 1}, bank = {1, 1}, reef = {0.010, 0.015},
		},
		history = {
			{cell = 32, years = 2000, steps = {3, 4}, uplift = {1, 1}, sea = {102, 108}},   // the sea rises over the bank as the ice melts, and the reef caps its top
			{cell = 32, years = 2000, steps = {4, 5}, uplift = {1, 1}, sea = {-28, -22}},   // then falls, and rises again, five times more
			{cell = 32, years = 2000, steps = {3, 3}, uplift = {1, 1}, sea = {22, 28}},
			{cell = 32, years = 2000, steps = {4, 5}, uplift = {1, 1}, sea = {-28, -22}},
			{cell = 16, years = 2000, steps = {3, 3}, uplift = {1, 1}, sea = {22, 28}},
			{cell = 16, years = 2000, steps = {4, 5}, uplift = {1, 1}, sea = {-28, -22}},
			{cell = 16, years = 2000, steps = {3, 3}, uplift = {1, 1}, sea = {22, 28}},
			{cell = 16, years = 2000, steps = {4, 5}, uplift = {1, 1}, sea = {-28, -22}},
			{cell = 16, years = 2000, steps = {3, 3}, uplift = {1, 1}, sea = {22, 28}},
			{cell = 16, years = 2000, steps = {4, 5}, uplift = {1, 1}, sea = {-28, -22}},
			{cell = 16, years = 2000, steps = {3, 3}, uplift = {1, 1}, sea = {22, 28}},
			{cell = 16, years = 2000, steps = {4, 5}, uplift = {1, 1}, sea = {-28, -22}},
			{cell = 16, years = 1000, steps = {7, 9}, uplift = {1, 1}, sea = {30, 36}},     // the last rise, and the thousands of years since
		},
	},
}

Region :: struct {
	kind:     string,
	size:     f64,      // metres along a side; the region's rim is always sea
	origin:   [2]i32,   // where its middle lies in the world; everything in it is stored relative to that
	latitude: f64,      // degrees north the island's climate follows (climate.odin), which the sun's path and the land's sunlight both read
	climate:  Climate,  // its base climate, from that latitude and the sea round it
	shape:    Shape(f64),
	story:    ^Story,
	history:  []Phase(f32),
	vents:    [dynamic]Vent,   // in the order they open
	features: [dynamic]Feature,   // what events made, in the order they were made (events.odin)
}

// A vent, drawn from its phase's ranges.
Vent :: struct {
	phase:         int,
	at:            [2]f64,   // relative to the region's middle
	top, build:    f32,      // height of its top once built, and how much it raised the ground there
	reach:         f32,      // how far out its form comes down to the ground it was built on
	form:          f32,
	crater, deep:  f32,      // the radius its top falls in over, or 0, and the depth of the floor under the rim
	floor:         f32,      // the height of that floor
	fallen:        bool,     // its top has fallen in, and the water reaching its floor sinks there
}

SEA_BED :: -200   // metres, the floor of the open sea round a high island

// Height of a vent's form at a point, once built, and how much rock it lays there at most: the
// height of its form over the ground it was built on, all it built at its top and nothing at its
// foot. So it fills the hollows near it up to its form, and lies thinly over the ground further
// out, never more than it erupted. It falls away faster or slower by direction, as flows ran
// further one way than another.
vent_top :: proc(v: Vent, x, z: f64) -> (top, thick: f32) {
	sh, k := region.shape, REFERENCE/region.size
	dx, dz := x - v.at.x, z - v.at.y
	r := math.sqrt(dx*dx*sh.xx + dz*dz*sh.zz + dx*dz*sh.xz)
	out := [2]f64{dx, dz}/max(r, 1)*f64(v.reach)   // the point at the foot of the form in this direction
	top = v.top - v.build*math.pow(f32(r)/v.reach, v.form)*(1 + f32(sh.lumps)*fbm((v.at.x + out.x)*k, (v.at.y + out.y)*k, sh.lumps_wave, 1, 3, seed + 3))
	return top, max(top - (v.top - v.build), 0)
}

// The ground the vents built at a point, before anything wore it: the open sea's floor, raised
// to each vent's form in turn, lowered into each crater, and swelled as the magma rose. With
// `upto`, the ground the next vent opened on. The rock's beds lie parallel to it; the forming
// builds each vent on the ground as the history has left it, worn as well.
built :: proc(x, z: f64, upto := max(int)) -> f32 {
	upto := min(upto, len(region.vents))
	lift := uplift_at(x, z, shore(x, z))
	h, phase := f32(SEA_BED), 0
	swell :: proc(h: ^f32, phase: ^int, until: int, lift: f32) {
		for ; phase^ < until; phase^ += 1 do h^ += lift*region.history[phase^].steps*region.history[phase^].years*region.history[phase^].uplift
	}
	for v in region.vents[:upto] {
		swell(&h, &phase, v.phase, lift)
		top, thick := vent_top(v, x, z)
		h = max(h, min(top, h + thick))
		if v.crater > 0 && math.hypot(x - v.at.x, z - v.at.y) < f64(v.crater) do h = min(h, v.floor)
	}
	swell(&h, &phase, region.vents[upto].phase if upto < len(region.vents) else len(region.history), lift)
	return h
}

// A phase of a kind's history as a seed draws it: its steps, uplift, sea and how many vents open,
// but not where. Its own procedure, so that the world can read an island's sea before forming it
// (arrivals.odin).
phase_draw :: proc(p: Phase([2]f32), i: int, key: i32, s: u32) -> Phase(f32) {
	draw :: proc(r: [2]f32, i, key: i32, s: u32) -> f32 { return r[0] + (r[1] - r[0])*hash01(i, key, s + 521) }
	k := i32(3*i)
	return {cell = p.cell, years = p.years, steps = math.round(draw(p.steps, k, key, s)), uplift = draw(p.uplift, k + 1, key, s), sea = draw(p.sea, k + 2, key, s), vents = math.round(draw(p.vents, k, key + 1, s))}
}

// Draw the region's record from the seed, of the named kind or, with none named, of the kind
// the seed picks: each row draws a number keyed by its name, raised to one over its weight, and
// the highest wins, so a row wins in proportion to its weight and a new row changes only the
// seeds it wins. The region is `size` metres across. With a record of the regional history's, what
// it says is read in place of the draws (record_phases). False if no kind has the name.
region_init :: proc(name: string, size: f64 = REFERENCE, record: ^Record = nil) -> bool {
	kind: ^Kind
	best: f32 = -1
	for &k in KINDS {
		h := math.pow(hash01(i32(fnv.fnv32a(transmute([]u8)k.name)), 0, seed + 500), 1/k.weight)
		if (name == "" && h > best) || k.name == name do kind, best = &k, h
	}
	if kind == nil do return false
	key := i32(fnv.fnv32a(transmute([]u8)kind.name))
	N :: size_of(Shape(f64))/size_of(f64)
	ranges, drawn := transmute([N][2]f64)kind.shape, [N]f64{}
	for r, i in ranges do drawn[i] = r[0] + (r[1] - r[0])*f64(hash01(i32(i), key, seed + 520))
	region.kind, region.size, region.shape = kind.name, size, transmute(Shape(f64))drawn   // its origin is its island's (gen_init)
	region.latitude = 30   // as the islands the plants come from (27 to 34° N), until the island's own is read (climate_init)
	for &s in STORIES do if s.name == kind.story do region.story = &s
	region.history = make([]Phase(f32), len(kind.history))
	plan := make([]Phase(f32), len(kind.history), context.temp_allocator)
	for p, i in kind.history do plan[i] = phase_draw(p, i, key, seed)
	if record != nil do record_phases(kind, record, plan, &region.shape)
	from := [2]f64{}   // the middle of the last vents to open
	for p, i in kind.history {
		region.history[i] = plan[i]
		// Each vent draws its own place, size and form within the phase's ranges.
		middle, first := [2]f64{}, len(region.vents)   // the vents of a phase erupt together, each onto the ground as it stood
		for _ in 0..<int(region.history[i].vents) {
			j := i32(len(region.vents))*8
			vary :: proc(r: [2]f32, j, key: i32) -> f32 { return r[0] + (r[1] - r[0])*hash01(j, key, seed + 522) }
			turn, out := 2*math.PI*f64(hash01(j, key, seed + 523)), f64(vary(p.spread, j, key))*region.size/REFERENCE
			v := Vent{phase = i, at = from + out*[2]f64{math.cos(turn), math.sin(turn)}, build = vary(p.build, j + 1, key), form = vary(p.form, j + 2, key)}
			if record != nil && record.on && record.vent.arc && j == 0 do v.build = math.lerp(p.build[0], p.build[1], clamp((record.vent.built - ARC_TOP[0])/(ARC_TOP[1] - ARC_TOP[0]), 0, 1))   // the history's volcano, the taller the higher it builds
			v.reach = v.build/vary(p.flank, j + 3, key)*f32(region.size/REFERENCE)
			v.top = built(v.at.x, v.at.y, first) + v.build
			append(&region.vents, v)
			middle += v.at/f64(region.history[i].vents)
			// The floor lies under the lowest point of the rim, so the crater is closed.
			if crater := vary(p.crater, j + 4, key)*f32(region.size/REFERENCE); crater > 0 {
				rim: f32 = 1e6
				for a in 0..<32 do rim = min(rim, built(v.at.x + f64(crater)*math.cos(f64(a)*math.PI/16), v.at.y + f64(crater)*math.sin(f64(a)*math.PI/16)))
				last := &region.vents[len(region.vents) - 1]
				last.crater, last.deep = crater, vary(p.deep, j + 5, key)
				last.floor = rim - last.deep
			}
		}
		if region.history[i].vents > 0 do from = middle
	}
	fmt.printf("island: %s, %.1f km across, the swell from %.0f°", region.kind, region.size/1000, region.shape.swell)
	if r := region.shape.reef; r > 0 do fmt.printf("; coral builds up to the sea %.1f mm/yr where it is shallower than %.0f m, on a bank rising with the island", r*1000, f32(REEF_DEPTH))
	for p, i in region.history {
		if p.sea != 0 do fmt.printf("; the sea %s %.0f m", "rises" if p.sea > 0 else "falls", abs(p.sea))
		for v in region.vents do if v.phase == i {
			fmt.printf("; a vent %.1f km from the middle builds a %s %.0f m high", math.hypot(v.at.x, v.at.y)/1000, "cone" if v.form < 1.5 else "dome", v.build)
			if v.crater > 0 do fmt.printf(" whose top falls in, %.1f km across, to a floor %.0f m under its rim", 2*v.crater/1000, v.deep)
		}
		rising := fmt.tprintf(" rising %.2f mm/yr", p.uplift*f32(region.shape.rate)*1000) if p.uplift > 0 else " at rest" if region.shape.rate > 0 else ""
		if p.steps > 0 do fmt.printf("; %.0f kyr%s on %d m cells", p.steps*p.years/1000, rising, p.cell)
	}
	fmt.println()
	return true
}

// What an island's record says, read in place of its kind's draws, each into its kind's range, since
// the forming's rates are its own, not the plates' (they make an island's relief from its rock and
// the erosion's law, over a few million years): its uplift at the heart, by how fast its crust rose
// on average over the regional history's last steps, against the window on how fast it rises that
// its kind's host reads; on a volcano, how high it builds by how high the history's built, and how
// long the sea has cut it since, by the volcano's age.
record_phases :: proc(kind: ^Kind, record: ^Record, plan: []Phase(f32), shape: ^Shape(f64)) {
	rising := Window{lo = 1e30}
	for w in (kind.hosts[0] if len(kind.hosts) > 0 else nil) do if w.field == .Rising do rising = w
	if rising.lo < 1e29 {
		lo, hi := rising.lo if rising.lo > -ANY else rising.hi - 1, rising.hi if rising.hi < ANY else rising.lo + 1
		mean: f32
		for r in record.past do mean += r/PAST
		shape.rate = math.lerp(kind.shape.rate[0], kind.shape.rate[1], f64(clamp((mean - lo)/(hi - lo), 0, 1)))
	}
	// The phases after a volcano's first: the older it is, against the window on a volcano's age its
	// kind's host reads (or with none, a vent's whole life), the longer the sea has cut it.
	age := Window{lo = 0, hi = VENT_LIFE[1]}
	for w in (kind.hosts[0] if len(kind.hosts) > 0 else nil) do if w.field == .Vent do age = w
	young, old := age.lo if age.lo > -ANY else max(age.hi - 1, 0), age.hi if age.hi < ANY else age.lo + 1
	if record.on && record.vent.arc && laid_by(kind) != .Plates do for &p, i in plan[1:] {
		r := kind.history[i + 1].steps
		if p.vents == 0 do p.steps = math.round(math.lerp(r[0], r[1], clamp((record.vent.born - young)/(old - young), 0, 1)))
	}
}

Grid :: struct {
	n:      int,
	d:      f32,            // cell size, metres
	z:      []f32,          // ground elevation, over the sea as it stands now
	fill:   []f32,          // elevation once hollows are filled: the surface water runs down
	next:   []i32,          // the cell each land cell drains into, -1 for the sea or SINK for a crater floor
	area:   []f32,          // land draining through each cell, m²
	uplift: []f32,          // m/yr at the shape's full rate
	sea:    []bool,
	soft:   []f32,          // how easily the rock erodes, around 1, from one outcrop to the next
	cut:    []f32,          // metres the sea has cut into a shore cell
	load:   []f32,          // m³ of rock the water carries down through each cell in a step
	face:   []f32,          // how many times steeper than on a hillside the ground stands, where the sea undercuts it
	base:   []f32,          // height of the rock stack's base under each cell (rock.odin),
	bodies: []Grid_Body,    // and any cover or body, where the island's rock has one the cells can hold; nil where not (grid_under)
	jitter: [][2]f32,       // where each cell's node sits in its square, so flow has no favourite compass direction
	seen:   []bool,
	order:  [dynamic]i32,   // land cells from the shore upward
	heap:   Heap,
	lift:   f32,            // the share of the uplift in this phase
	left:   f32,            // years of full uplift still to come
	rise:   f32,            // metres the sea has still to rise
	keep:   bool,           // the water that stands in a hollow is a lake, and the ground under it is left as it is
	block:  []u8,           // where all the arrays above are kept
	open:   []i32,          // the table of sea cells the coast reads, kept from step to step (sea_table),
	reached: []i32,         // the last mouth whose silt reached each cell, numbered on the grid from 1 so it is never cleared,
	mouths: i32,            // and the mouths so far
}

// The finished land, read by the generator.
Land :: struct {
	n:     int,        // cells along a side at 16 m
	z:     [5][]f32,   // elevation at 16 to 256 m cells, each the mean of the one finer
	slope: []f32,      // steepness
	wet:   []f32,      // 0 on ridges to 1 in valley floors
	live:  []f32,      // 1 on ground a person could live on, else 0
	grid:  ^Grid,      // the finest grid, kept for the river network
	// What a place on the land gives what grows there (land_local): on land cells only.
	facing:  []f32,    // the bearing the ground falls toward, degrees from north
	hump:    []f32,    // metres the ground stands over the mean ground in a square 208 m across; under it, a hollow
	inland:  []f32,    // metres to the nearest sea
	sun:     []f32,    // clear-sky sunlight through a year, against the same ground lying flat
	exposed: []f32,    // 0 in a hollow sheltered from the wind to 1 on a crest or shore facing the wind and salt
	above:   []f32,    // metres over the stream or shore a cell drains to; the cold air of a still night pools from there up
	soil:    []f32,    // metres of soil over the rock
	community: []u8,   // the plant community that won the race for each land cell (plants_init), 255 at sea
	age:     []f32,    // years since a storm or slide last threw the canopy of the stand a cell lies in (plants_init)
	valley:  []f32,    // m² drained by the stream a cell drains to
	slid:    []f32,    // metres of slide debris laid on a cell, or under 0, taken from it (events.odin)
	lake:    []u8,     // 1 + the feature whose lake or pond covers a cell, or 0
	swell:   []f32,    // on land beside the sea, how open the shore is to the waves (exposure)
	surf:    []f32,    // within 48 m of the shore, on land or at sea, how open the shore nearest is to the waves
	supply:  []f32,    // sand the rivers bring the shore, from each mouth along 320 m of it
	lifted:  []f32,    // metres the wind off the sea has been raised to by the ground it crossed, at sea too
	pebble:  []Mat,    // the rock a stream's gravel is of (pebbles_make, rock.odin), or Air; none where the rock was not read from the island's setting
	rain:    []f32,    // mm a year, on the 64 m grid (land_rain, climate.odin)
	rained:  f32,      // and its mean over the land
}

// Ground a person could live on, from where the villages on eight real islands stand
// (interesting-world/notes/real-islands.md, "Livable ground"): no steeper than 20°, which
// holds 85 to 93% of their buildings on six of them and the gentler half of Mikurajima's, at
// least 2 m above the sea, in a patch of a hectare or more. Height above the sea, distance
// from it and distance from a stream told the villages from the rest of the land not at all.
LIVABLE :: 0.364   // tan 20°

// Positive inland, negative at sea, at a point relative to the region's middle.
shore :: proc(x, z: f64) -> f32 {
	sh, k := region.shape, REFERENCE/region.size
	if sh.radius == 0 do return -1
	r := f32(math.sqrt(x*x*sh.xx + z*z*sh.zz + x*z*sh.xz))/f32(sh.radius*region.size)
	edge := f32(max(abs(x), abs(z)))/f32(0.5*region.size)
	return 1 - r*(1 + f32(sh.ragged)*fbm(x*k, z*k, sh.ragged_wave, 1, 4, seed + 1)) - 4*smoothstep(0.86, 1, edge)
}

// Arrays of a value for each of n × n cells, carved one after another from a block, each begun 20
// cache lines further into a page than the one before. Arrays made alone begin a whole number of
// pages apart, which puts a cell's values in all of them into one set of the cache, which holds
// eight, and a step of the forming reads a dozen for each cell.
room :: proc(n: int, $T: typeid) -> int { return (n*n*size_of(T) + 63)/64*64 + 1280 }
carve :: proc(block: []u8, at: ^int, n: int, $T: typeid) -> []T {
	defer at^ += room(n, T)
	return slice.from_ptr((^T)(&block[at^]), n*n)
}

// Rows of an n × n grid to a part of the work shared among threads (`shared`, regions.odin).
rows :: proc(n: int) -> int { return max(8192/n, 1) }

// A grid over the region as it stands at the start.
grid_make :: proc(n: int) -> ^Grid {
	g := new(Grid)
	g.n, g.d = n, f32(region.size)/f32(n)
	g.block = make([]u8, 9*room(n, f32) + room(n, i32) + room(n, [2]f32) + 2*room(n, bool))
	b, at := g.block, 0
	g.z, g.fill, g.area = carve(b, &at, n, f32), carve(b, &at, n, f32), carve(b, &at, n, f32)
	g.uplift, g.soft, g.base, g.cut, g.face, g.load = carve(b, &at, n, f32), carve(b, &at, n, f32), carve(b, &at, n, f32), carve(b, &at, n, f32), carve(b, &at, n, f32), carve(b, &at, n, f32)
	if rocks_held() do g.bodies = make([]Grid_Body, n*n)
	g.next, g.jitter, g.seen, g.sea = carve(b, &at, n, i32), carve(b, &at, n, [2]f32), carve(b, &at, n, bool), carve(b, &at, n, bool)
	shared(n, rows(n), g, proc(g: ^Grid, lo, hi: int) {
		n, k := g.n, REFERENCE/region.size
		for c in lo*n..<hi*n {
			x, z := (f64(c%n) + 0.5)*f64(g.d) - region.size/2, (f64(c/n) + 0.5)*f64(g.d) - region.size/2
			s := shore(x, z)
			ix, iz := i32(c%n), i32(c/n)
			g.face[c] = 1
			g.jitter[c] = [2]f32{hash01(ix, iz, seed + 7 + u32(n)) - 0.5, hash01(ix, iz, seed + 8 + u32(n)) - 0.5}*0.9
			// The beds decide how the rock wears; it also varies a little from one outcrop to the
			// next, which keeps streams from running in straight lines along the grid, and is
			// crushed along a fault.
			g.soft[c] = math.exp(0.8*(hash01(ix, iz, seed + 6 + u32(n)) - 0.5))
			if len(rocks.bodies) > 0 do g.soft[c] *= rock_weak(x, z)
			u := rock_base(x, z, LAND_CELL)
			g.base[c] = u.base
			if g.bodies != nil do g.bodies[c] = {u.cover, u.roof, u.body}
			g.z[c] = -2 - 60*smoothstep(0, 0.2, -s) + (SEA_BED + 62)*smoothstep(0.2, 0.5, -s)   // sea bed, falling away steeply as off a real high island
			g.sea[c] = s <= 0
			g.uplift[c] = uplift_at(x, z, s)
			if s > 0 do g.z[c] = 0.5 + 30*s + 25*(1 + fbm(x*k, z*k, 900, 1, 3, seed + 9))
		}
	})
	return g
}

// Uplift at a point whose shore value is s, m/yr at the shape's full rate: everywhere inland and
// more along the range; and wherever magma rising into a vent's cone swells it from within, the
// more the more it built, most under its top or evenly across the floor of a crater and its rim.
uplift_at :: proc(x, z: f64, s: f32) -> f32 {
	sh, k := region.shape, REFERENCE/region.size
	lift: f32
	for v in region.vents {
		if r := max(f32(math.hypot(x - v.at.x, z - v.at.y)), v.crater); r < v.reach do lift += v.build/1000*(1 - math.pow(r/v.reach, v.form))
	}
	if s > 0 {
		t := smoothstep(0, f32(sh.taper), s) if sh.taper > 0 else 1
		lift += f32(sh.floor)*t
		if sh.ridge > 0 {
			axis := sh.axis + sh.bend*math.sin(x*k/sh.bend_wave) + sh.wander*f64(fbm(x*k, 0, sh.wander_wave, 1, 2, seed + 2))
			lift += f32(sh.ridge)*t*f32(math.exp(-math.pow((z*k - axis)/sh.width, 2)))
		}
	}
	return f32(sh.rate)*lift*(1 + f32(sh.lumps)*fbm(x*k, z*k, sh.lumps_wave, 1, 3, seed + 3)) if lift > 0 else 0
}

grid_free :: proc(g: ^Grid) {
	delete(g.block); delete(g.open); delete(g.reached); delete(g.order); delete(g.heap.items); delete(g.bodies)
	free(g)
}

land_form :: proc() {
	started := time.now()
	history := region.history
	sea, rise: f32   // metres the sea has risen so far, and will in all
	for p in history do rise += p.sea
	g := grid_make(int(region.size)/history[0].cell)
	for p in history do g.left += p.steps*p.years*p.uplift
	for p, i in history {
		for g.d > f32(p.cell) do g = refine(g)
		n := g.n
		at :: proc(g: ^Grid, c: int) -> (x, z: f64) { return (f64(c%g.n) + 0.5)*f64(g.d) - region.size/2, (f64(c/g.n) + 0.5)*f64(g.d) - region.size/2 }
		ground :: proc(g: ^Grid, x, z: f64) -> f32 { return g.z[clamp(int((z + region.size/2)/f64(g.d)), 0, g.n - 1)*g.n + clamp(int((x + region.size/2)/f64(g.d)), 0, g.n - 1)] }
		// Where the sea moves, what lies below it now is sea bed and what it leaves is land: a
		// rise floods the valley mouths into inlets.
		if p.sea != 0 {
			for c in 0..<n*n {
				g.z[c] -= p.sea
				g.sea[c] = g.z[c] <= 0
			}
			sea += p.sea
		}
		g.lift, g.rise = p.uplift, rise - sea
		// The forms this phase's vents build, as they will stand, how much each raises the ground
		// at its top and how much rock it lays at most. They grow over the phase, burying what
		// they reach.
		form, grow, low, thick: []f32
		for &v in region.vents do if v.phase == i do v.top = ground(g, v.at.x, v.at.y) + v.build
		if p.vents > 0 {
			form, grow = make([]f32, n*n, context.temp_allocator), make([]f32, n*n, context.temp_allocator)
			low, thick = slice.clone(g.z, context.temp_allocator), make([]f32, n*n, context.temp_allocator)
			Forms :: struct { g: ^Grid, phase: int, form, grow, thick: []f32 }
			forms := Forms{g, i, form, grow, thick}
			shared(n, rows(n), &forms, proc(f: ^Forms, lo, hi: int) {
				for c in lo*f.g.n..<hi*f.g.n {
					x, z := at(f.g, c)
					f.form[c] = -1e6
					for v in region.vents do if t, th := vent_top(v, x, z); v.phase == f.phase && t > f.form[c] do f.form[c], f.grow[c], f.thick[c] = t, v.build, th
				}
			})
		}
		for s in 0..<int(p.steps) {
			done := f32(s + 1)/p.steps
			if p.vents > 0 do for c in 0..<n*n {
				if h := min(form[c] - grow[c]*(1 - done), low[c] + thick[c]*done); h > g.z[c] do g.z[c], g.sea[c], g.cut[c] = h, h <= 0, 0   // fresh rock the sea has yet to cut
			}
			route(g)
			erode(g, p.years)
			creep(g, p.years)
			coast(g, p.years)
			g.left -= p.years*p.uplift
		}
		// The tops of the vents that will fall in, fall, to a floor under the lowest point of the
		// rim, so the crater is closed.
		for &v in region.vents do if v.phase == i && v.crater > 0 {
			rim: f32 = 1e6
			for a in 0..<int(4*math.PI*v.crater/g.d) do rim = min(rim, ground(g, v.at.x + f64(v.crater)*math.cos(f64(a)*f64(g.d)/f64(2*v.crater)), v.at.y + f64(v.crater)*math.sin(f64(a)*f64(g.d)/f64(2*v.crater))))
			v.floor = rim - v.deep
			for c in 0..<n*n {
				if x, z := at(g, c); math.hypot(x - v.at.x, z - v.at.y) < f64(v.crater) do g.z[c], g.sea[c] = min(g.z[c], v.floor), min(g.z[c], v.floor) <= 0
			}
			v.fallen = true
		}
	}
	route(g)
	n := g.n
	if len(g.order) == 0 {
		fmt.eprintfln("no land: the %s island's history wore it away below the sea", region.kind)
		os.exit(1)
	}

	// How long a step cut at the coast takes to climb to the head of the farthest stream
	// (landforms.md, D3): against it, the length of the last phase says how finished the land is.
	climb := make([]f32, n*n, context.temp_allocator)
	response: f32
	for ci in g.order {
		c := int(ci)
		if r := g.next[c]; r >= 0 do climb[c] = climb[r] + span(g, c, int(r))/(ERODE*g.soft[c]*wear(g, c, g.z[c]).erodes*math.sqrt(g.area[c]))
		if g.area[c] >= CHANNEL_AREA do response = max(response, climb[c])
	}
	last: f32   // years on the finest cells
	for p in history do if p.cell == history[len(history) - 1].cell do last += p.steps*p.years

	delete(g.open); delete(g.reached)
	g.open, g.reached = nil, nil
	land.n, land.grid, land.z[0] = n, g, g.z
	land.slid, land.lake = make([]f32, n*n), make([]u8, n*n)
	land_finish(g, false)   // what the slide's place is found by
	slide_make(g)
	highest := land_finish(g)
	if rocks.full do pebbles_make(g)
	fmt.printfln("land formed in %.2f s: %d land cells, highest point %.0f m", time.duration_seconds(time.since(started)), len(g.order), highest)
	if response > 0 do fmt.printfln("a step cut at the coast climbs to the farthest stream head in %.0f kyr; the land has had %.0f kyr on its finest cells, %.2f of that", response/1000, last/1000, last/response)
	else do fmt.printfln("no stream reaches the sea, so nothing cut at the coast climbs inland; the land has had %.0f kyr on its finest cells", last/1000)
	land_stats(g)
}

// What the generator reads off the formed land: coarser grids, slope, wetness, livable ground
// and the local fields.
land_finish :: proc(g: ^Grid, all := true) -> (highest: f32) {
	n := g.n
	for level in 1..<len(land.z) {
		m := n >> uint(level)
		fine := land.z[level - 1]
		delete(land.z[level])
		land.z[level] = make([]f32, m*m)
		for c in 0..<m*m {
			k := (c/m)*2*(m*2) + (c%m)*2
			land.z[level][c] = (fine[k] + fine[k + 1] + fine[k + m*2] + fine[k + m*2 + 1])/4
		}
	}
	delete(land.slope); delete(land.wet); delete(land.live)
	land.slope, land.wet = make([]f32, n*n), make([]f32, n*n)
	for y in 1..<n - 1 {
		for x in 1..<n - 1 {
			c := y*n + x
			dx, dz := g.z[c + 1] - g.z[c - 1], g.z[c + n] - g.z[c - n]
			land.slope[c] = math.sqrt(dx*dx + dz*dz)/(2*g.d)
			// Wetness follows the land draining to a place: none on a ridge, full in a valley floor.
			if !g.sea[c] do land.wet[c] = clamp((math.log10(g.area[c]) - 2.6)/2.4, 0, 1)
			highest = max(highest, g.z[c])
		}
	}
	if !all {
		land_drained(g)
		return
	}
	// Spread wetness out from the channels into the ground beside them.
	scratch := make([]f32, n*n)
	defer delete(scratch)
	for _ in 0..<3 {
		copy(scratch, land.wet)
		for y in 1..<n - 1 {
			for x in 1..<n - 1 {
				c := y*n + x
				land.wet[c] = (scratch[c]*2 + scratch[c - 1] + scratch[c + 1] + scratch[c - n] + scratch[c + n])/6
			}
		}
	}
	live := make([]bool, n*n, context.temp_allocator)
	for c in 0..<n*n do live[c] = !g.sea[c] && land.lake[c] == 0 && g.z[c] >= 2 && land.slope[c] <= LIVABLE
	group, sizes := patches(n, live, 1)
	land.live = make([]f32, n*n)
	for c in 0..<n*n do if group[c] >= 0 && f32(sizes[group[c]])*g.d*g.d >= 10_000 do land.live[c] = 1
	land_local(g)
	return
}

// What each place on the land gives what grows there (foundations/climate.md, "Region rung"):
// the way it faces, whether it stands in a hollow or on a hump, how far the sea is, the sun it
// gets in a year, the wind and salt it takes, and how high it stands over its stream.
HUMP :: 6   // cells either side of the square a cell's height is set against, 208 m across
land_local :: proc(g: ^Grid) {
	n := g.n
	for f in ([?][]f32{land.facing, land.hump, land.inland, land.sun, land.exposed, land.soil, land.swell, land.lifted, land.surf, land.supply}) do delete(f)
	land.facing, land.hump, land.inland, land.lifted = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	land.sun, land.exposed, land.soil, land.swell = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	land.surf, land.supply = make([]f32, n*n), make([]f32, n*n)

	// Distance to the sea, nearest first: each cell takes the sea cell nearest a neighbour
	// already reached, which is near enough the true nearest that no contour shows the grid.
	from := make([]i32, n*n, context.temp_allocator)   // the sea cell nearest each cell
	heap_clear(&g.heap)
	for c in 0..<n*n {
		from[c] = i32(c)
		if !g.sea[c] do land.inland[c] = 1e9
		else do for o in OFFSETS {
			if x, y := c%n + o.x, c/n + o.y; x >= 0 && y >= 0 && x < n && y < n && !g.sea[y*n + x] {
				heap_push(&g.heap, {0, i32(c)})
				break
			}
		}
	}
	for g.heap.n > 0 {
		top := heap_pop(&g.heap)
		c := int(top.c)
		if top.h > land.inland[c] do continue   // reached nearer since
		for o in OFFSETS {
			x, y, s := c%n + o.x, c/n + o.y, int(from[c])
			if x < 0 || y < 0 || x >= n || y >= n do continue
			if d := g.d*math.hypot(f32(x - s%n), f32(y - s/n)); d < land.inland[y*n + x] {
				land.inland[y*n + x], from[y*n + x] = d, i32(s)
				heap_push(&g.heap, {d, i32(y*n + x)})
			}
		}
	}

	// A year of clear sky: the sun the sky draws (`sun_dir`), each hour of six days from midwinter
	// to midsummer, each the weaker by 0.7 for every depth of air it comes through.
	sky := make([dynamic][3]f32, context.temp_allocator)
	flat: f32
	for day in 0..<6 do for hour in 0..<24 {
		s := sun_dir(f32(hour) + 0.5, 355 + (f32(day) + 0.5)*365/12)
		if s.y < 0.02 do continue
		append(&sky, s*math.pow(0.7, 1/s.y))
		flat += sky[len(sky) - 1].y
	}

	// Height summed over the squares above and to the left of each corner, the sea as its surface.
	sums, w := make([]f64, (n + 1)*(n + 1), context.temp_allocator), n + 1
	for y in 0..<n {
		row: f64
		for x in 0..<n {
			row += f64(max(g.z[y*n + x], 0))
			sums[(y + 1)*w + x + 1] = sums[y*w + x + 1] + row
		}
	}
	// The wind blows from the swell's bearing, which it raised.
	Local :: struct { g: ^Grid, sky: [][3]f32, flat: f32, sums: []f64, open: []i32, fetch: int, wind: [2]f32, ahead: [2]int }
	l := Local{g = g, sky = sky[:], flat = flat, sums = sums, open = sea_table(g), fetch = max(int(FETCH/g.d), 2)}
	bearing := math.to_radians(f32(region.shape.swell))
	l.wind = {math.sin(bearing), -math.cos(bearing)}   // toward where it comes from
	l.ahead = {int(math.round(l.wind.x*f32(l.fetch))), int(math.round(l.wind.y*f32(l.fetch)))}
	// How high the wind has been lifted when it reaches each place, sea or land: the highest ground
	// it crossed in the last 400 m, less a metre for each four it has run on since, sinking and
	// drying in the lee. Cloud caps the ground where this passes the cloud base (`cloud_top`).
	shared(n, rows(n), &l, proc(l: ^Local, lo, hi: int) {
		g, n, wind := l.g, l.g.n, l.wind
		for c in lo*n..<hi*n do for d := f32(0); d <= 400; d += g.d {
			i, j := clamp(int(f32(c%n) + 0.5 + wind.x*d/g.d), 0, n - 1), clamp(int(f32(c/n) + 0.5 + wind.y*d/g.d), 0, n - 1)
			land.lifted[c] = max(land.lifted[c], g.z[j*n + i] - d/4)
		}
	})
	land_drained(g)
	shared(len(g.order), 2048, &l, proc(l: ^Local, lo, hi: int) {
		g, n, wind, w, open, fetch, ahead := l.g, l.g.n, l.wind, l.g.n + 1, l.open, l.fetch, l.ahead
		for ci in g.order[lo:hi] {
			c := int(ci)
			x, y := c%n, c/n
			dx, dz := (g.z[c + 1] - g.z[c - 1])/(2*g.d), (g.z[c + n] - g.z[c - n])/(2*g.d)
			land.facing[c] = math.mod(math.to_degrees(math.atan2(-dx, dz)) + 360, 360)
			up := [3]f32{-dx, 1, -dz}/math.sqrt(dx*dx + dz*dz + 1)
			for s in l.sky do land.sun[c] += max(up.x*s.x + up.y*s.y + up.z*s.z, 0)/l.flat
			x0, y0, x1, y1 := max(x - HUMP, 0), max(y - HUMP, 0), min(x + HUMP + 1, n), min(y + HUMP + 1, n)
			land.hump[c] = g.z[c] - f32((l.sums[y1*w + x1] - l.sums[y0*w + x1] - l.sums[y1*w + x0] + l.sums[y0*w + x0])/f64((x1 - x0)*(y1 - y0)))
			// Exposure: the steepest rise of the ground toward the wind within 300 m (Winstral's index),
			// lower on a hump and higher in a hollow, and the salt off the first sea toward the wind, by
			// the share of open sea in the kilometre beyond it, fading over a kilometre inland.
			rise, salt, hit := f32(-1), f32(0), false
			for d := g.d; d < 3000 && !(hit && d > 300); d += g.d if d < 300 else 2*g.d {
				i, j := clamp(int(f32(x) + 0.5 + wind.x*d/g.d), 0, n - 1), clamp(int(f32(y) + 0.5 + wind.y*d/g.d), 0, n - 1)
				if d <= 300 do rise = max(rise, (max(g.z[j*n + i], 0) - g.z[c])/d)
				if g.sea[j*n + i] && !hit do salt, hit = share(open, n, i + ahead.x, j + ahead.y, fetch)*math.exp(-d/1000), true
			}
			land.exposed[c] = 1 - (1 - clamp(0.5 - 2*rise + land.hump[c]/40, 0, 1))*(1 - salt)
			for o in OFFSETS do if g.sea[c + o.y*n + o.x] do land.swell[c] = exposure(open, n, x, y, fetch, ahead)
			// Soil gathers in hollows and where water collects, thins on humps and as the ground
			// steepens toward what it holds, and lies deeper over weak rock, which weathers faster.
			// Within a few metres of a stream the floods lay silt as well.
			steep := min(land.slope[c]/SOIL_HOLDS, 1)
			weak := 1.3 - 0.6*MATERIALS[rock_in(g.z[c] - 0.5, grid_under(g, c), ROCK_SIM)].strength
			land.soil[c] = min((clamp(1 - land.hump[c]/12, 0.3, 2.5) + 1.5*land.wet[c])*(1 - 0.7*steep*steep)*weak + 2*max(1 - land.above[c]/4, 0), 4)
			// A slide's scar is bare rock and its debris rubble; soil weathers back on both with the years.
			if s := land.slid[c]; abs(s) > 0.5 do land.soil[c] = min(land.soil[c], (0.3 if s > 0 else 0) + SOIL_GROWS*region.features[landslide.feature].age)
		}
	})
	// The shore the waves work (step 15): each place within 48 m of it, on land or at sea, takes the
	// swell of the shore round it, the nearest the most; and each river's mouth gives the shore sand
	// for 320 m along it, as much as the square root of the km² it drains, up to 1.
	shared(n, rows(n), g, proc(g: ^Grid, lo, hi: int) {
		n := g.n
		for y in max(lo, 3)..<min(hi, n - 3) do for x in 3..<n - 3 {
			c := y*n + x
			if !g.sea[c] && land.inland[c] > 48 do continue
			sum, weight: f32
			for j in -3..=3 do for i in -3..=3 do if s := land.swell[c + j*n + i]; s > 0 {
				w := 1/(1 + math.hypot(f32(i), f32(j)))
				sum, weight = sum + w*s, weight + w
			}
			if weight > 0 do land.surf[c] = sum/weight
		}
	})
	land_rain()
	for ci in g.order do if g.next[ci] == -1 && g.area[ci] >= CHANNEL_AREA {
		x, y, r := int(ci)%n, int(ci)/n, 20
		for j in max(y - r, 0)..=min(y + r, n - 1) do for i in max(x - r, 0)..=min(x + r, n - 1) {
			k := j*n + i
			if land.surf[k] > 0 do land.supply[k] = max(land.supply[k], min(math.sqrt(g.area[ci]/1e6), 1)*(1 - math.hypot(f32(i - x), f32(j - y))/f32(r)))
		}
	}
}

// Where cold air pools: the height over the stream a cell drains to, or over the sea; and the
// land the stream drains.
land_drained :: proc(g: ^Grid) {
	delete(land.above); delete(land.valley)
	land.above, land.valley = make([]f32, g.n*g.n), make([]f32, g.n*g.n)
	for ci in g.order {
		c, r := int(ci), g.next[ci]
		land.above[c] = 0 if g.area[c] >= CHANNEL_AREA || r == SINK else g.z[c] if r < 0 else g.z[c] - g.z[r] + land.above[r]
		land.valley[c] = g.area[c] if g.area[c] >= CHANNEL_AREA || r < 0 else land.valley[r]
	}
}

// The value in the middle of a list once sorted, 0 for none, found without sorting it all (Hoare's
// selection): the list is left in another order.
middle :: proc(v: []f32) -> f32 {
	if len(v) == 0 do return 0
	k, lo, hi := len(v)/2, 0, len(v) - 1
	for lo < hi {
		p, i, j := v[(lo + hi)/2], lo, hi
		for i <= j {
			for v[i] < p do i += 1
			for v[j] > p do j -= 1
			if i <= j {
				v[i], v[j] = v[j], v[i]
				i, j = i + 1, j - 1
			}
		}
		if k <= j do hi = j
		else if k >= i do lo = i
		else do break
	}
	return v[k]
}

// Group marked cells lying within `reach` cells of each other: each cell's group, or -1, and
// the number of cells in each group.
patches :: proc(n: int, marked: []bool, reach: int) -> (group: []i32, sizes: [dynamic]i32) {
	group, sizes = make([]i32, n*n, context.temp_allocator), make([dynamic]i32, context.temp_allocator)
	stack := make([dynamic]i32, context.temp_allocator)
	for &v in group do v = -1
	for c in 0..<n*n {
		if !marked[c] || group[c] >= 0 do continue
		id := i32(len(sizes))
		append(&sizes, 0)
		group[c] = id
		append(&stack, i32(c))
		for len(stack) > 0 {
			k := int(pop(&stack))
			sizes[id] += 1
			for y in max(k/n - reach, 0)..=min(k/n + reach, n - 1) do for x in max(k%n - reach, 0)..=min(k%n + reach, n - 1) {
				if j := y*n + x; marked[j] && group[j] < 0 {
					group[j] = id
					append(&stack, i32(j))
				}
			}
		}
	}
	return
}

// Smooth value of one of the land's grids at a point in the world. The curve through each
// four values never rises past its neighbours (Steffen 1990), so the edge of a face does not
// bulge above the face's top.
land_at :: proc(v: []f32, n: int, x, z: f64) -> f32 {
	d := region.size/f64(n)
	u, w := (x + region.size/2)/d - 0.5, (z + region.size/2)/d - 0.5
	fu, fw := math.floor(u), math.floor(w)
	iu, iw := int(fu), int(fw)
	curve :: #force_inline proc(p: [4]f32, t: f32) -> f32 {
		slope :: #force_inline proc(a, b: f32) -> f32 {   // at a point between rises a and b
			if a*b <= 0 do return 0
			return math.sign(a)*min(abs(a), abs(b), 0.25*abs(a + b))*2
		}
		s0, s1, s2 := p[1] - p[0], p[2] - p[1], p[3] - p[2]
		m1, m2 := slope(s0, s1), slope(s1, s2)
		return p[1] + t*(m1 + t*(3*s1 - 2*m1 - m2 + t*(m1 + m2 - 2*s1)))
	}
	rows: [4]f32
	for j in 0..<4 {
		row := clamp(iw + j - 1, 0, n - 1)*n
		p: [4]f32
		for i in 0..<4 do p[i] = v[row + clamp(iu + i - 1, 0, n - 1)]
		rows[j] = curve(p, f32(u - fu))
	}
	return curve(rows, f32(w - fw))
}

// The finest grid's cell under a point.
land_cell :: proc(x, z: f64) -> int {
	return clamp(int((z + region.size/2)/LAND_CELL), 0, land.n - 1)*land.n + clamp(int((x + region.size/2)/LAND_CELL), 0, land.n - 1)
}
