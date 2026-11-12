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

CHANNEL_AREA :: 120_000   // m² of land that must drain through a cell before it carries a stream

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

Kind :: struct {
	name:    string,
	weight:  f32,      // how often the seed draws this kind, against the other rows' weights
	story:   string,   // what the rock is (STORIES, rock.odin)
	shape:   Shape([2]f64),
	history: []Phase([2]f32),
}

KINDS := [?]Kind{
	{
		// A long island, a range north of its middle and a south slope with room for rivers. It
		// rises for 3 to 4 million years, and the sea then rises 40 to 60 m into the mouths of its
		// valleys, leaving coves between the cliffs; much more and it is the inlets kind. After
		// Hahajima, though its shore is half as long.
		name = "ridge", weight = 3, story = "layered, gently tilted",
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
		name = "inlets", weight = 3, story = "layered, gently tilted",
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
		name = "cone", weight = 1, story = "lava and ash",
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
		name = "crater", weight = 1, story = "lava and ash",
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
		name = "domes", weight = 2, story = "pale lava and pumice",
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
		name = "worn", weight = 2, story = "layered, gently tilted",
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
		name = "raised", weight = 2, story = "layered, gently tilted",
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
}

Region :: struct {
	kind:     string,
	size:     f64,      // metres along a side; the region's rim is always sea
	origin:   [2]i32,   // where its middle lies in the world; everything in it is stored relative to that
	latitude: f64,      // degrees north, which the sun's path and the land's sunlight both read
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

region: Region

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

// Draw the region's record from the seed, of the named kind or, with none named, of the kind
// the seed picks: each row draws a number keyed by its name, raised to one over its weight, and
// the highest wins, so a row wins in proportion to its weight and a new row changes only the
// seeds it wins. False if no kind has the name.
region_init :: proc(name: string) -> bool {
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
	draw :: proc(r: [2]f32, i, key: i32) -> f32 { return r[0] + (r[1] - r[0])*hash01(i, key, seed + 521) }
	region.kind, region.size, region.shape = kind.name, REFERENCE, transmute(Shape(f64))drawn
	region.latitude = 30   // where the sun has always stood: 60° high at noon on an equinox; the world frame will set it
	for &s in STORIES do if s.name == kind.story do region.story = &s
	region.history = make([]Phase(f32), len(kind.history))
	from := [2]f64{}   // the middle of the last vents to open
	for p, i in kind.history {
		k := i32(3*i)
		region.history[i] = {cell = p.cell, years = p.years, steps = math.round(draw(p.steps, k, key)), uplift = draw(p.uplift, k + 1, key), sea = draw(p.sea, k + 2, key)}
		region.history[i].vents = math.round(draw(p.vents, k, key + 1))
		// Each vent draws its own place, size and form within the phase's ranges.
		middle, first := [2]f64{}, len(region.vents)   // the vents of a phase erupt together, each onto the ground as it stood
		for _ in 0..<int(region.history[i].vents) {
			j := i32(len(region.vents))*8
			vary :: proc(r: [2]f32, j, key: i32) -> f32 { return r[0] + (r[1] - r[0])*hash01(j, key, seed + 522) }
			turn, out := 2*math.PI*f64(hash01(j, key, seed + 523)), f64(vary(p.spread, j, key))*region.size/REFERENCE
			v := Vent{phase = i, at = from + out*[2]f64{math.cos(turn), math.sin(turn)}, build = vary(p.build, j + 1, key), form = vary(p.form, j + 2, key)}
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
	base:   []f32,          // height of the rock stack's base under each cell (rock.odin)
	jitter: [][2]f32,       // where each cell's node sits in its square, so flow has no favourite compass direction
	seen:   []bool,
	order:  [dynamic]i32,   // land cells from the shore upward
	heap:   [dynamic]Heap_Item,
	lift:   f32,            // the share of the uplift in this phase
	left:   f32,            // years of full uplift still to come
	rise:   f32,            // metres the sea has still to rise
	keep:   bool,           // the water that stands in a hollow is a lake, and the ground under it is left as it is
}

// The finished land, read by the generator.
Land :: struct {
	n:     int,        // cells along a side at 16 m
	z:     [3][]f32,   // elevation at 16, 32 and 64 m cells
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
}

// Ground a person could live on, from where the villages on eight real islands stand
// (interesting-world/notes/real-islands.md, "Livable ground"): no steeper than 20°, which
// holds 85 to 93% of their buildings on six of them and the gentler half of Mikurajima's, at
// least 2 m above the sea, in a patch of a hectare or more. Height above the sea, distance
// from it and distance from a stream told the villages from the rest of the land not at all.
LIVABLE :: 0.364   // tan 20°

land: Land

// Positive inland, negative at sea, at a point relative to the region's middle.
shore :: proc(x, z: f64) -> f32 {
	sh, k := region.shape, REFERENCE/region.size
	if sh.radius == 0 do return -1
	r := f32(math.sqrt(x*x*sh.xx + z*z*sh.zz + x*z*sh.xz))/f32(sh.radius*region.size)
	edge := f32(max(abs(x), abs(z)))/f32(0.5*region.size)
	return 1 - r*(1 + f32(sh.ragged)*fbm(x*k, z*k, sh.ragged_wave, 1, 4, seed + 1)) - 4*smoothstep(0.86, 1, edge)
}

// A grid over the region as it stands at the start.
grid_make :: proc(n: int) -> ^Grid {
	g := new(Grid)
	g.n, g.d = n, f32(region.size)/f32(n)
	g.z, g.fill, g.area = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	g.uplift, g.soft, g.base, g.cut, g.face, g.load = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	g.next, g.jitter, g.seen, g.sea = make([]i32, n*n), make([][2]f32, n*n), make([]bool, n*n), make([]bool, n*n)
	k := REFERENCE/region.size
	for c in 0..<n*n {
		x, z := (f64(c%n) + 0.5)*f64(g.d) - region.size/2, (f64(c/n) + 0.5)*f64(g.d) - region.size/2
		s := shore(x, z)
		ix, iz := i32(c%n), i32(c/n)
		g.face[c] = 1
		g.jitter[c] = [2]f32{hash01(ix, iz, seed + 7 + u32(n)) - 0.5, hash01(ix, iz, seed + 8 + u32(n)) - 0.5}*0.9
		// The beds decide how the rock wears; it also varies a little from one outcrop to the
		// next, which keeps streams from running in straight lines along the grid.
		g.soft[c] = math.exp(0.8*(hash01(ix, iz, seed + 6 + u32(n)) - 0.5))
		g.base[c] = rock_base(x, z, LAND_CELL)
		g.z[c] = -2 - 60*smoothstep(0, 0.2, -s) + (SEA_BED + 62)*smoothstep(0.2, 0.5, -s)   // sea bed, falling away steeply as off a real high island
		g.sea[c] = s <= 0
		g.uplift[c] = uplift_at(x, z, s)
		if s > 0 do g.z[c] = 0.5 + 30*s + 25*(1 + fbm(x*k, z*k, 900, 1, 3, seed + 9))
	}
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
		lift += f32(sh.floor)
		if sh.ridge > 0 {
			axis := sh.axis + sh.bend*math.sin(x*k/sh.bend_wave) + sh.wander*f64(fbm(x*k, 0, sh.wander_wave, 1, 2, seed + 2))
			lift += f32(sh.ridge)*f32(math.exp(-math.pow((z*k - axis)/sh.width, 2)))
		}
	}
	return f32(sh.rate)*lift*(1 + f32(sh.lumps)*fbm(x*k, z*k, sh.lumps_wave, 1, 3, seed + 3)) if lift > 0 else 0
}

grid_free :: proc(g: ^Grid) {
	delete(g.z); delete(g.fill); delete(g.area); delete(g.uplift); delete(g.soft); delete(g.base); delete(g.cut); delete(g.face); delete(g.load)
	delete(g.next); delete(g.jitter); delete(g.seen); delete(g.sea); delete(g.order); delete(g.heap)
	free(g)
}

OFFSETS :: [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

// Distance between the nodes of two cells.
span :: #force_inline proc(g: ^Grid, a, b: int) -> f32 {
	dx := f32(b%g.n - a%g.n) + g.jitter[b].x - g.jitter[a].x
	dz := f32(b/g.n - a/g.n) + g.jitter[b].y - g.jitter[a].y
	return g.d*math.sqrt(dx*dx + dz*dz)
}

Heap_Item :: struct { h: f32, c: i32 }

heap_push :: proc(heap: ^[dynamic]Heap_Item, item: Heap_Item) {
	append(heap, item)
	i := len(heap) - 1
	for i > 0 {
		parent := (i - 1)/2
		if heap[parent].h <= item.h do break
		heap[i] = heap[parent]
		i = parent
	}
	heap[i] = item
}

heap_pop :: proc(heap: ^[dynamic]Heap_Item) -> Heap_Item {
	top := heap[0]
	last := pop(heap)
	n := len(heap)
	if n == 0 do return top
	i := 0
	for {
		child := 2*i + 1
		if child >= n do break
		if child + 1 < n && heap[child + 1].h < heap[child].h do child += 1
		if heap[child].h >= last.h do break
		heap[i] = heap[child]
		i = child
	}
	heap[i] = last
	return top
}

// Decide where water goes. The land is flooded from the shore upward, lowest ground
// first, so every cell is reached along a path that never climbs and hollows fill to
// their rims. The one exception is a fallen crater: its floor is broken rock and ash that
// the water sinks into, as on Aogashima's, so the flood starts again from its lowest point
// and the crater stays a closed, dry hollow. Then each cell drains to its steepest lower
// neighbour, and the land above each cell is added up.
SINK :: -2   // in `next`: the water sinks into the ground here
route :: proc(g: ^Grid) {
	n := g.n
	clear(&g.order)
	clear(&g.heap)
	for c in 0..<n*n {
		g.seen[c] = g.sea[c]
		g.next[c] = -1
		g.fill[c] = g.z[c]
	}
	for c in 0..<n*n {
		if g.sea[c] do continue
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n || g.sea[y*n + x] {
				g.fill[c] = max(g.z[c], 0.05)
				g.seen[c] = true
				heap_push(&g.heap, {g.fill[c], i32(c)})
				break
			}
		}
	}
	sinks: [dynamic]i32
	defer delete(sinks)
	for v in region.vents do if v.fallen {
		lowest := -1
		x0, y0, r := int((v.at.x + region.size/2)/f64(g.d)), int((v.at.y + region.size/2)/f64(g.d)), int(v.crater/g.d)
		for y in max(y0 - r, 0)..=min(y0 + r, n - 1) do for x in max(x0 - r, 0)..=min(x0 + r, n - 1) {
			if c := y*n + x; (x - x0)*(x - x0) + (y - y0)*(y - y0) <= r*r && !g.seen[c] && (lowest < 0 || g.z[c] < g.z[lowest]) do lowest = c
		}
		if lowest < 0 do continue
		g.seen[lowest] = true
		heap_push(&g.heap, {g.fill[lowest], i32(lowest)})
		append(&sinks, i32(lowest))
	}
	for len(g.heap) > 0 {
		item := heap_pop(&g.heap)
		c := int(item.c)
		append(&g.order, item.c)
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n do continue
			nb := y*n + x
			if g.seen[nb] do continue
			g.seen[nb] = true
			g.fill[nb] = max(g.z[nb], item.h + 0.001*span(g, c, nb))   // a filled hollow keeps a trace of slope
			g.next[nb] = item.c
			heap_push(&g.heap, {g.fill[nb], i32(nb)})
		}
	}
	for ci in g.order {
		c := int(ci)
		best := g.next[c]
		steepest := g.fill[c]/g.d if best < 0 else (g.fill[c] - g.fill[best])/span(g, c, int(best))
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n do continue
			nb := y*n + x
			sea := g.sea[nb]
			s := (g.fill[c] - (0 if sea else g.fill[nb]))/span(g, c, nb)
			if s > steepest do steepest, best = s, (-1 if sea else i32(nb))
		}
		g.next[c] = best
	}
	for c in sinks do if g.next[c] < 0 do g.next[c] = SINK
	for c in g.order do g.area[c] = g.d*g.d
	#reverse for c in g.order {
		if r := g.next[c]; r >= 0 do g.area[r] += g.area[c]
	}
}

// How the rock at height z in a cell wears. The rock is read where it will stand in the
// finished world, once the uplift still to come and the sea's rise have moved it, so the
// beds cut here are the beds the blocks show.
wear :: #force_inline proc(g: ^Grid, c: int, z: f32) -> Rock_Law {
	law := rocks.law[rock_in(z + g.uplift[c]*g.left - g.rise, g.base[c], ROCK_SIM)]
	if g.keep && land.slid[c] > 0.5 do law.erodes, law.creep = landslide.law.erodes, landslide.law.creep   // the debris wears as its blocks do
	return law
}

// One step of uplift and cutting, worked from the shore upward so each cell knows where
// the cell below it has ended up. Solving for the new height rather than stepping toward
// it keeps the result steady however long the step. Weak rock is cut faster and holds a
// gentler slope.
erode :: proc(g: ^Grid, dt: f32) {
	for ci in g.order {
		c := int(ci)
		below, run: f32 = 0, g.d
		if g.next[c] == SINK || (g.keep && g.fill[c] > g.z[c] + 0.01) {   // nothing runs on from a sink to cut it, and a lake's floor is still
			g.z[c] += g.uplift[c]*g.lift*dt
			g.load[c] = 0
			continue
		}
		if r := g.next[c]; r >= 0 {
			below, run = g.z[r], span(g, c, int(r))
			g.face[c] = 1 + (g.face[r] - 1)*math.exp(-run/100)   // a cliff the sea undercuts eases over 100 m inland
		}
		law := wear(g, c, g.z[c])
		f := ERODE*g.soft[c]*law.erodes*math.sqrt(g.area[c])*dt/run
		z := (g.fill[c] + g.uplift[c]*g.lift*dt + f*below)/(1 + f)
		was := g.z[c] + g.uplift[c]*g.lift*dt
		g.z[c] = clamp(z, below + 0.001*run, below + law.limit*run*g.face[c])
		g.load[c] = max(was - g.z[c], 0)*g.d*g.d
	}
	#reverse for c in g.order do if r := g.next[c]; r >= 0 do g.load[r] += g.load[c]
}

creep :: proc(g: ^Grid, dt: f32) {
	n := g.n
	rounds := int(math.ceil(CREEP*dt/(0.2*g.d*g.d)))
	k := CREEP*dt/(f32(rounds)*g.d*g.d)
	old := g.fill   // free to use: route rebuilds it
	for _ in 0..<rounds {
		for c in 0..<n*n do old[c] = max(g.z[c], 0)
		for y in 1..<n - 1 {
			for x in 1..<n - 1 {
				c := y*n + x
				if g.sea[c] do continue
				g.z[c] = max(old[c] + k*wear(g, c, old[c]).creep*(old[c - 1] + old[c + 1] + old[c - n] + old[c + n] - 4*old[c]), 0.02)
			}
		}
	}
}

// The sea cuts its shore back to a platform just under the water, and the land behind, which
// goes on rising, stands over it as a cliff at the steepest its rock holds. The waves wear away
// rock by how much open sea lies around a shore and toward the swell, so headlands and shores
// facing the swell give way, bays and lee shores are spared, and weak rock gives way faster
// than strong. What they wear away is the whole cliff, so a low shore is cut back quickly and a
// high one slowly; and they break on the platform they leave, so a coast that has cut a wide
// shallow one retreats only as fast as the platform is worn deeper.
WAVES     :: 0.3    // m² of a rock that erodes at 1 worn from each metre of shore a year, open to the swell all round
FETCH     :: 500    // metres around a shore cell, and toward the swell, over which the sea is counted
PLATFORM  :: 2      // metres under the sea that a cut shore is left,
ABRADE    :: 1e-5   // and m/yr the waves wear it lower, slowing to nothing at
WAVE_BASE :: 20     // this depth, so a platform deepens away from its cliff
SHELTER   :: 0.07   // exposure below which the waves neither undercut a shore nor carry silt off
FLAT      :: 4      // metres over the sea that floods build a flat of river silt to

// The sea cells above and to the left of each corner of the grid, so that the share of sea in
// any square is four reads.
sea_table :: proc(g: ^Grid, allocator := context.temp_allocator) -> []i32 {
	n := g.n
	open := make([]i32, (n + 1)*(n + 1), allocator)
	for y in 0..<n {
		row: i32
		for x in 0..<n {
			row += i32(g.sea[y*n + x])
			open[(y + 1)*(n + 1) + x + 1] = open[y*(n + 1) + x + 1] + row
		}
	}
	return open
}

// The share of sea in a square r cells either side of a cell.
share :: proc(open: []i32, n, x, y, r: int) -> f32 {
	x0, y0, x1, y1 := clamp(x - r, 0, n), clamp(y - r, 0, n), clamp(x + r + 1, 0, n), clamp(y + r + 1, 0, n)
	w := n + 1
	return f32(open[y1*w + x1] - open[y0*w + x1] - open[y1*w + x0] + open[y0*w + x0])/f32(max((x1 - x0)*(y1 - y0), 1))
}

coast :: proc(g: ^Grid, dt: f32) {
	n := g.n
	open := sea_table(g, context.allocator)
	defer delete(open)
	for c in 0..<n*n do if g.sea[c] && g.z[c] > -WAVE_BASE do g.z[c] -= ABRADE*dt*(1 + g.z[c]/WAVE_BASE)
	r := max(int(FETCH/g.d), 2)
	bearing := math.to_radians(f32(region.shape.swell))
	ahead := [2]int{int(math.round(math.sin(bearing)*f32(r))), int(math.round(-math.cos(bearing)*f32(r)))}
	back := max(int(100/g.d), 1)   // the cliff is the highest ground this many cells inland
	for ci in g.order {
		c := int(ci)
		x, y := c%n, c/n
		beside := false
		for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x]
		if !beside do continue
		cliff, deep: f32   // the highest ground and the deepest water within 100 m
		for j in max(y - back, 0)..=min(y + back, n - 1) do for i in max(x - back, 0)..=min(x + back, n - 1) do cliff, deep = max(cliff, g.z[j*n + i]), max(deep, -g.z[j*n + i])
		exposed := exposure(open, n, x, y, r, ahead)
		law := wear(g, c, 0.5)
		if exposed >= SHELTER do g.cut[c] += WAVES*dt*exposed*law.erodes*min(deep/WAVE_BASE, 1)/(cliff + PLATFORM)
		if g.cut[c] >= g.d do g.z[c], g.sea[c] = -PLATFORM, true
		// A face the waves undercut stands steeper than the rock holds on a hillside: up to twice
		// as steep where the shore is open, and no steeper than a hillside where it is sheltered.
		g.face[c] = 1 + smoothstep(SHELTER, 0.2, exposed)
	}

	// What the streams carry down settles where the sea is sheltered. Off each mouth it fills the
	// water nearest first to just over the sea, so a flat grows out from the head of a bay until
	// the silt runs out or the water grows open, where the waves carry the rest away.
	if region.shape.silt == 0 do return
	reached, queue := make([]i32, n*n), make([dynamic]i32)   // the last mouth whose silt reached a cell
	defer { delete(reached); delete(queue) }
	for ci, mouth in g.order {
		if g.next[ci] >= 0 || g.area[ci] < CHANNEL_AREA do continue
		left := g.load[ci]*f32(region.shape.silt)
		clear(&queue)
		append(&queue, ci)
		for head := 0; head < len(queue) && left > 0; head += 1 {
			k := int(queue[head])
			for o in OFFSETS {
				x, y := k%n + o.x, k/n + o.y
				c := y*n + x
				if x < 0 || y < 0 || x >= n || y >= n || !g.sea[c] || reached[c] == i32(mouth) + 1 do continue
				reached[c] = i32(mouth) + 1
				if exposure(open, n, x, y, r, ahead) >= SHELTER do continue
				need := (FLAT - g.z[c])*g.d*g.d
				if left < need {
					g.z[c] += left/(g.d*g.d)
					left = 0
					break
				}
				g.z[c], g.sea[c] = FLAT, false
				left -= need
				append(&queue, i32(c))
			}
		}
	}
}

// How open a shore is to the waves: the share of open sea around it, squared, and more where
// the sea toward the swell is open too.
exposure :: proc(open: []i32, n, x, y, r: int, ahead: [2]int) -> f32 {
	around := share(open, n, x, y, r)
	return around*around*(0.3 + 0.7*share(open, n, x + ahead.x, y + ahead.y, r))
}

// The same land and sea bed at twice the detail: land and sea are where the coarse grid has
// them, with the coast the waves cut and the sea bed they wore.
refine :: proc(coarse: ^Grid) -> ^Grid {
	g := grid_make(coarse.n*2)
	g.left = coarse.left
	n, m := g.n, coarse.n
	for c in 0..<n*n {
		// Read the coarse land through a gentle warp, so a valley that ran straight along the
		// coarse grid comes out winding. The steps that follow settle it.
		wx, _, _ := noise(f64(c%n)/9, f64(c/n)/9, seed + 11 + u32(n))
		wz, _, _ := noise(f64(c%n)/9, f64(c/n)/9, seed + 12 + u32(n))
		u, v := (f32(c%n) + 0.5)/2 - 0.5 + 1.6*(wx - 0.5), (f32(c/n) + 0.5)/2 - 0.5 + 1.6*(wz - 0.5)
		x0, y0 := clamp(int(math.floor(u)), 0, m - 2), clamp(int(math.floor(v)), 0, m - 2)
		tu, tv := clamp(u - f32(x0), 0, 1), clamp(v - f32(y0), 0, 1)
		k := y0*m + x0
		z := math.lerp(math.lerp(coarse.z[k], coarse.z[k + 1], tu), math.lerp(coarse.z[k + m], coarse.z[k + m + 1], tu), tv)
		g.sea[c] = z <= 0
		if g.sea[c] {
			g.z[c] = z
			continue
		}
		g.face[c] = coarse.face[k]
		// A little roughness, so the finer streams have something to start from.
		g.z[c] = max(z, 0.3) + 0.03*g.d*(hash01(i32(c%n), i32(c/n), seed + 10) - 0.5)
	}
	grid_free(coarse)
	return g
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
			for c in 0..<n*n {
				x, z := at(g, c)
				form[c] = -1e6
				for v in region.vents do if t, th := vent_top(v, x, z); v.phase == i && t > form[c] do form[c], grow[c], thick[c] = t, v.build, th
			}
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

	land.n, land.grid, land.z[0] = n, g, g.z
	land.slid, land.lake = make([]f32, n*n), make([]u8, n*n)
	highest := land_finish(g)
	if slide_make(g) do highest = land_finish(g)
	fmt.printfln("land formed in %.2f s: %d land cells, highest point %.0f m", time.duration_seconds(time.since(started)), len(g.order), highest)
	fmt.printfln("a step cut at the coast climbs to the farthest stream head in %.0f kyr; the land has had %.0f kyr on its finest cells, %.2f of that", response/1000, last/1000, last/response)
	land_stats(g)
}

// What the generator reads off the formed land: coarser grids, slope, wetness, livable ground
// and the local fields.
land_finish :: proc(g: ^Grid) -> (highest: f32) {
	n := g.n
	for level in 1..<3 {
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
	for f in ([?][]f32{land.facing, land.hump, land.inland, land.sun, land.exposed, land.above, land.soil, land.valley, land.swell}) do delete(f)
	land.facing, land.hump, land.inland, land.valley = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	land.sun, land.exposed, land.above, land.soil, land.swell = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)

	// Distance to the sea, nearest first: each cell takes the sea cell nearest a neighbour
	// already reached, which is near enough the true nearest that no contour shows the grid.
	from := make([]i32, n*n, context.temp_allocator)   // the sea cell nearest each cell
	clear(&g.heap)
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
	for len(g.heap) > 0 {
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

	// A year of clear sky at the region's latitude: the sun each hour of six days from midwinter
	// to midsummer, each the weaker by 0.7 for every depth of air it comes through.
	sky := make([dynamic][3]f32, context.temp_allocator)   // x east, y up, z south, as `sun_dir` has it
	flat: f32
	lat := math.to_radians(f32(region.latitude))
	for day in 0..<6 do for hour in 0..<24 {
		dec, h := -math.to_radians(f32(23.44))*math.cos(math.PI*(f32(day) + 0.5)/6), (f32(hour) - 11.5)*math.PI/12
		s := [3]f32{-math.cos(dec)*math.sin(h), math.sin(dec)*math.sin(lat) + math.cos(dec)*math.cos(lat)*math.cos(h), math.cos(dec)*math.sin(lat)*math.cos(h) - math.sin(dec)*math.cos(lat)}
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
	open, fetch := sea_table(g), max(int(FETCH/g.d), 2)
	bearing := math.to_radians(f32(region.shape.swell))
	wind := [2]f32{math.sin(bearing), -math.cos(bearing)}   // toward where it comes from
	ahead := [2]int{int(math.round(wind.x*f32(fetch))), int(math.round(wind.y*f32(fetch)))}
	for ci in g.order {
		c := int(ci)
		x, y := c%n, c/n
		dx, dz := (g.z[c + 1] - g.z[c - 1])/(2*g.d), (g.z[c + n] - g.z[c - n])/(2*g.d)
		land.facing[c] = math.mod(math.to_degrees(math.atan2(-dx, dz)) + 360, 360)
		up := [3]f32{-dx, 1, -dz}/math.sqrt(dx*dx + dz*dz + 1)
		for s in sky do land.sun[c] += max(up.x*s.x + up.y*s.y + up.z*s.z, 0)/flat
		x0, y0, x1, y1 := max(x - HUMP, 0), max(y - HUMP, 0), min(x + HUMP + 1, n), min(y + HUMP + 1, n)
		land.hump[c] = g.z[c] - f32((sums[y1*w + x1] - sums[y0*w + x1] - sums[y1*w + x0] + sums[y0*w + x0])/f64((x1 - x0)*(y1 - y0)))
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
		// Where cold air pools: the height over the stream a cell drains to, or over the sea.
		r := g.next[c]
		land.above[c] = 0 if g.area[c] >= CHANNEL_AREA || r == SINK else g.z[c] if r < 0 else g.z[c] - g.z[r] + land.above[r]
		land.valley[c] = g.area[c] if g.area[c] >= CHANNEL_AREA || r < 0 else land.valley[r]
		// Soil gathers in hollows and where water collects, thins on humps and as the ground
		// steepens toward what it holds, and lies deeper over weak rock, which weathers faster.
		// Within a few metres of a stream the floods lay silt as well.
		steep := min(land.slope[c]/SOIL_HOLDS, 1)
		weak := 1.3 - 0.6*MATERIALS[rock_in(g.z[c] - 0.5, g.base[c], ROCK_SIM)].strength
		land.soil[c] = min((clamp(1 - land.hump[c]/12, 0.3, 2.5) + 1.5*land.wet[c])*(1 - 0.7*steep*steep)*weak + 2*max(1 - land.above[c]/4, 0), 4)
		// A slide's scar is bare rock and its debris rubble; soil weathers back on both with the years.
		if s := land.slid[c]; abs(s) > 0.5 do land.soil[c] = min(land.soil[c], (0.3 if s > 0 else 0) + SOIL_GROWS*region.features[landslide.feature].age)
	}
}

// How steep the land came out: the share of land steeper than 45° and the median slope,
// each cell taken by its steepest neighbour, and the tallest face, followed down the
// drainage while it stays steeper than 45°.
land_stats :: proc(g: ^Grid) {
	n := g.n
	slopes := make([dynamic]f32, context.temp_allocator)
	face, top, foot, steep := f32(0), 0, 0, 0
	kinds: [Mat]int
	for ci in g.order {
		c := int(ci)
		kinds[rock_in(g.z[c] - 0.5, g.base[c], ROCK_SIM)] += 1
		if c%n == 0 || c/n == 0 || c%n == n - 1 || c/n == n - 1 do continue
		most: f32
		for o in OFFSETS do most = max(most, (g.z[c] - max(g.z[c + o.y*n + o.x], 0))/(g.d*math.sqrt(f32(o.x*o.x + o.y*o.y))))
		append(&slopes, most)
		if most > 1 do steep += 1
		drop, at := f32(0), c
		for ; g.next[at] >= 0 && (g.z[at] - g.z[g.next[at]])/span(g, at, int(g.next[at])) >= 1; at = int(g.next[at]) {
			drop += g.z[at] - g.z[g.next[at]]
		}
		if drop > face do face, top, foot = drop, c, at
	}
	slice.sort(slopes[:])
	at :: proc(g: ^Grid, c: int) -> [3]f32 { return {(f32(c%g.n) + 0.5)*g.d - f32(region.size/2), g.z[c], (f32(c/g.n) + 0.5)*g.d - f32(region.size/2)} }
	fmt.printfln("steeper than 45°: %.1f%% of land; median slope %.0f°; tallest face %.0f m, from %.0f to %.0f",
		100*f32(steep)/f32(len(slopes)), math.to_degrees(math.atan(slopes[len(slopes)/2])), face, at(g, top), at(g, foot))
	fmt.print("rock at the surface:")
	for k, m in kinds do if k > 0 do fmt.printf(" %v %.0f%%", m, 100*f32(k)/f32(len(g.order)))
	fmt.println()
	land_figures(g)
	free_all(context.temp_allocator)
}

// The figures the real islands were measured by (interesting-world/notes/real-islands.md),
// taken the same way, with the real high islands' range beside each. Slope is by central
// differences on land whose eight neighbours are land; a crest is such a cell steeper than 5°
// that nothing drains into; a shore cell is land beside the sea.
land_figures :: proc(g: ^Grid) {
	n := g.n
	coast := make([]bool, n*n, context.temp_allocator)   // within 100 m of the sea
	lists: [5][dynamic]f32   // height within 100 m of a shore cell, slope near the sea, crest fall, height above the stream, within 50 m of a shore cell
	for &l in lists do l = make([dynamic]f32, context.temp_allocator)
	for y in 8..<n - 8 {
		for x in 8..<n - 8 {
			c := y*n + x
			beside := false
			for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x] != g.sea[c]
			if !beside do continue
			top: [2]f32
			for dy in -6..=6 do for dx in -6..=6 {
				d := dx*dx + dy*dy
				k := c + dy*n + dx
				if g.sea[c] && d <= 39 do coast[k] = true
				if !g.sea[c] && !g.sea[k] && d <= 36 do top = {max(top[0], g.z[k]), max(top[1], g.z[k] if d <= 9 else 0)}
			}
			if !g.sea[c] {
				append(&lists[0], top[0])
				append(&lists[4], top[1])
			}
		}
	}
	low, steep, inner := 0, 0, 0
	for ci in g.order {
		c := int(ci)
		append(&lists[3], land.above[c])
		if g.z[c] < 50 do low += 1
		sea := false
		for o in OFFSETS do sea ||= g.sea[c + o.y*n + o.x]
		if sea do continue
		inner += 1
		if land.slope[c] > math.tan(math.to_radians(f32(60))) do steep += 1
		if coast[c] do append(&lists[1], land.slope[c])
		if g.area[c] <= g.d*g.d*1.01 && land.slope[c] > math.tan(math.to_radians(f32(5))) do append(&lists[2], g.z[c] - (g.z[c - 1] + g.z[c + 1] + g.z[c - n] + g.z[c + n])/4)
	}
	median :: proc(l: [dynamic]f32) -> f32 { slice.sort(l[:]); return l[len(l)/2] if len(l) > 0 else 0 }
	rising := 0
	for h in lists[4] do if h > 30 do rising += 1
	fmt.printfln("against real high islands: shore height within 100 m %.0f m (60-117); shore rising 30 m in 50 m %.0f%% (40-85); slope in the first 100 m %.0f° (29-51)",
		median(lists[0]), 100*f32(rising)/f32(max(len(lists[4]), 1)), math.to_degrees(math.atan(median(lists[1]))))
	fmt.printfln("  land under 50 m %.0f%% (5-16); over 60° %.1f%% (0.8-2.9); fall at a crest %.2f m (0.56-1.25); height above the nearest stream %.0f m (54-130)",
		100*f32(low)/f32(len(g.order)), 100*f32(steep)/f32(max(inner, 1)), median(lists[2]), median(lists[3]))

	// A sheltered landing is shore under 5 m where the sea fills less than a third of the
	// square a kilometre across around it, with livable ground within 100 m; shore of that kind
	// less than 50 m apart is one landing.
	live, landing := make([]bool, n*n, context.temp_allocator), make([]bool, n*n, context.temp_allocator)
	livable: int
	for c in 0..<n*n do live[c], livable = land.live[c] > 0, livable + int(land.live[c] > 0)
	_, patch := patches(n, live, 1)
	open := sea_table(g)
	for y in 16..<n - 16 {
		for x in 16..<n - 16 {
			c := y*n + x
			if g.sea[c] || g.z[c] >= 5 || share(open, n, x, y, int(500/g.d)) >= 1.0/3 do continue
			beside, behind := false, false
			for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x]
			for dy in -6..=6 do for dx in -6..=6 do behind ||= dx*dx + dy*dy <= 36 && live[c + dy*n + dx]
			landing[c] = beside && behind
		}
	}
	_, landings := patches(n, landing, 3)

	// The deepest closed hollow, as the real islands were measured: how deep water would stand
	// in it if none sank into a crater's floor.
	hollow: f32
	for &v in region.vents do v.fallen = false
	route(g)
	for c in g.order do hollow = max(hollow, g.fill[c] - g.z[c])
	for &v in region.vents do v.fallen = v.crater > 0
	route(g)
	fmt.printfln("  livable %.0f%% of land, the largest patch %.0f ha (15-46, 63-417); sheltered landings %d, %.1f in 10 km of shore (0 on the cones, 7-14 and 1.3-1.9, 80 and 3.6 on Tsushima); deepest closed hollow %.0f m (2-10, 77 on Aogashima)",
		100*f32(livable)/f32(len(g.order)), f32(slice.max(patch[:]) if len(patch) > 0 else 0)*g.d*g.d/10_000, len(landings), f32(len(landings))*10_000/(f32(len(lists[0]))*g.d), hollow)
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

// A material's colour as the map shows it.
map_colour :: proc(m: Mat) -> [3]f32 {
	c := MATERIALS[m].colour
	c = {math.sqrt(c.r), math.sqrt(c.g), math.sqrt(c.b)}*1.2
	grey := (c.r + c.g + c.b)/3
	return grey + (c - grey)*3   // hues told apart more easily than on the ground
}

// A picture of the land from above, eight metres to the pixel: relief shaded from the
// north-west, sea by depth, and the rivers. With an overlay, the land is painted by that
// field instead.
land_map :: proc(path, overlay: string) {
	SIZE :: 1024
	paint: ^Field_Info
	field: Field
	for &f, k in FIELDS do if f.name == overlay do paint, field = &f, k
	if overlay != "" && paint == nil {
		fmt.eprint("no field named", overlay, "; there are:")
		for f in FIELDS do fmt.eprint("", f.name)
		fmt.eprintln()
		return
	}
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	for py in 0..<SIZE {
		for px in 0..<SIZE {
			x, z := (f64(px) + 0.5)*region.size/SIZE - region.size/2, (f64(py) + 0.5)*region.size/SIZE - region.size/2
			h := land_at(land.z[0], land.n, x, z)
			gx := land_at(land.z[0], land.n, x + 8, z) - land_at(land.z[0], land.n, x - 8, z)
			gz := land_at(land.z[0], land.n, x, z + 8) - land_at(land.z[0], land.n, x, z - 8)
			shade := clamp(0.75 + 0.9*(-gx - gz)/16, 0.25, 1.3)
			col: [3]f32
			if h <= 0 {
				col = math.lerp([3]f32{0.35, 0.62, 0.80}, [3]f32{0.08, 0.22, 0.42}, clamp(-h/30, 0, 1))
			} else {
				if paint != nil {
					p := point_at(x, z, 8) if field in GROUND_FIELDS else Point{x = x, z = z, cell = 8}
					v := paint.at(&p)
					switch paint.paint {
					case .Kinds: col = map_colour(Mat(v))*shade
					case .Soils: col = SOILS[int(v)].colour*shade
					case .Plants: col = COMMUNITIES[Community_Kind(v)].colour*shade
					case .Wheel:
						a := math.to_radians(v)
						col = math.lerp([3]f32{0.6, 0.6, 0.6}, 0.55 + 0.4*[3]f32{math.cos(a), math.cos(a - 2.1), math.cos(a + 2.1)}, clamp(land_at(land.slope, land.n, x, z)/0.2, 0, 1))*shade
					case .Log:  col = math.lerp(paint.from_colour, paint.to_colour, clamp((math.log10(v) - paint.lo)/(paint.hi - paint.lo), 0, 1))*shade
					case .Ramp: col = math.lerp(paint.from_colour, paint.to_colour, clamp((v - paint.lo)/(paint.hi - paint.lo), 0, 1))*shade
					}
				} else {
					// Green at the sea, tan at 200 m, brown at 500 and pale only near 1,000, so that
					// the height of a high island still reads.
					t := math.sqrt(clamp(h/1000, 0, 1))
					col = math.lerp(math.lerp([3]f32{0.42, 0.60, 0.30}, [3]f32{0.66, 0.58, 0.38}, clamp(t*2.2, 0, 1)), [3]f32{0.52, 0.42, 0.34}, clamp(t*3.3 - 1.45, 0, 1))
					col = math.lerp(col, [3]f32{0.90, 0.89, 0.86}, clamp(t*4 - 3, 0, 1))*shade
					// Rock shows where the ground is too steep to hold soil, as on the ground.
					bed := rock(x, f64(h) - 0.5, z, 8)
					bare := smoothstep(0.85, 1.15, land_at(land.slope, land.n, x, z)/SOIL_HOLDS)
					col = math.lerp(col, map_colour(bed)*shade, 0.8*bare)
					// A slide's debris is tinted ochre and its scar pale.
					if s := land_at(land.slid, land.n, x, z); abs(s) > 0.5 do col = math.lerp(col, ([3]f32{0.80, 0.50, 0.20} if s > 0 else {0.90, 0.88, 0.84})*shade, f32(0.5))
				}
				if r, near := river_near(f32(x), f32(z)); near && r.d < max(r.half, 4) do col = {0.10, 0.30, 0.75}
				if level, inside, _ := lake_near(x, z); inside && h < level do col = {0.10, 0.30, 0.75}
				if trail_near(x, z) < 4.5 do col = {0.65, 0.10, 0.05}
				if k := trails.ford[land_cell(x, z)]; k > 0 && math.hypot(x - region.features[k - 1].at.x, z - region.features[k - 1].at.y) < 14 do col = {1, 1, 1}
			}
			for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
		}
	}
	// Each roofed place (events.odin) is ringed, in orange for a notch, white for a shelter and red for a sea cave.
	for h in hollows {
		f := region.features[h.feature]
		cx, cy := int((f.at.x + region.size/2)*SIZE/region.size), int((f.at.y + region.size/2)*SIZE/region.size)
		for dy in -6..=6 do for dx in -6..=6 do if r := dx*dx + dy*dy; r >= 16 && r <= 36 && cx + dx >= 0 && cy + dy >= 0 && cx + dx < SIZE && cy + dy < SIZE {
			ring := #partial [Feature_Kind][3]u8{.Notch = {255, 140, 0}, .Shelter = {255, 255, 255}, .Cave = {230, 20, 20}}
			for k in 0..<3 do pixels[((cy + dy)*SIZE + cx + dx)*4 + k] = ring[f.kind][k]
		}
	}
	write_png(path, pixels, SIZE, SIZE, false)
}
