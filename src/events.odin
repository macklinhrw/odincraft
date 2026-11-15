package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:slice"
import "core:time"

// Events and the features they leave (foundations/kinds-and-places.md, D6). A feature is a
// record with an identity: what it is, where and how large, how many years ago it was made, what
// made it and what was measured when it was. One event happens so far, a landslide, near the end
// of the forming (foundations/landforms.md, D4), and it leaves three kinds of feature: its own
// scar and debris, the lake its debris dams, and the ponds among its hummocks.

Feature_Kind :: enum u8 { Slide, Lake, Pond, Notch, Shelter, Cave, Trail, Ford, Fall, Spring, Stack, Place, Haunt }
Measure :: struct { what: string, value: f32 }
Feature :: struct {
	kind:     Feature_Kind,
	at:       [2]f64,   // its middle, relative to the region's; a trail's first end
	to:       [2]f64,   // a trail's other end
	reach:    f32,      // metres from there to its farthest part
	size:     f32,      // m³ of rock moved, or m² of water
	level:    f32,      // where a lake's or pond's water stands
	age:      f32,      // years since it was made
	cause:    int,      // the feature that made it, or -1
	measured: [3]Measure,
}

// The island's slide, if it had one: its feature, the bed it broke from and how its debris wears,
// and the square round all it touched, scar, debris and water.
Slide :: struct {
	feature: int,
	rock:    Mat,
	law:     Rock_Law,
	box:     [4]f64,   // x0, z0, x1, z1 relative to the region's middle; empty with no slide
}

// A landslide happens where its host holds best (landforms.md, "Choosing events"): a slope near
// the steepest its rock holds, with a stronger bed over a weaker within the depth a slide reaches,
// standing over a valley whose stream drains 0.5 to 5 km². Ties are broken by the seed. How large
// it is, how far its debris runs and how long ago it fell are drawn from the seed within ranges.
Event :: struct {
	host:          []Window,
	length, width: [2]f32,   // of the scar, which runs from its head to the valley floor, held within these metres, and its width as a share of that
	runout:        [2]f32,   // how far the top of the debris falls for each metre it runs out
	bulk:          [2]f32,   // how much the rock swells as it breaks
	age:           [2]f32,   // years ago, drawn evenly in its logarithm
}
SLIDE := Event{
	host = {{.At_Limit, 0.9, ANY, 0.3}, {.Cap, 0.3, ANY, 0.2}, {.Valley, 5e5, 5e6, 3e5}, {.Cold, 60, ANY, 40}},
	length = {300, 800}, width = {0.9, 1.5}, runout = {0.05, 0.1}, bulk = {1.15, 1.3}, age = {30, 1000},
}
SOIL_GROWS :: 0.0004   // metres of soil that weathers on bare rock in a year (a guess)
DROWNED    :: 100      // years the trunks of drowned trees stand in a lake before they rot and fall (a guess, after Taishō pond)

// The strongest contrast between a bed in the top 50 m of a cell and a weaker one below it, the
// depth of that weaker bed, and the two rocks.
cap_at :: proc(c: int) -> (contrast, depth: f32, strong, weak: Mat) {
	g := land.grid
	top := Mat.Air
	for d := f32(2); d <= 50; d += 4 {
		m := rock_in(g.z[c] - d, g.base[c], ROCK_SIM)
		if MATERIALS[top].strength - MATERIALS[m].strength > contrast do contrast, depth, strong, weak = MATERIALS[top].strength - MATERIALS[m].strength, d, top, m
		if MATERIALS[m].strength > MATERIALS[top].strength do top = m
	}
	return
}

middle_of :: proc(g: ^Grid, c: int) -> [2]f64 {
	return {(f64(c%g.n) + 0.5)*f64(g.d) - region.size/2, (f64(c/g.n) + 0.5)*f64(g.d) - region.size/2}
}

// Choose the slide's place, take its scar out of the hillside and lay its debris in the valley,
// then let the land wear for its age with the water behind the debris standing as a lake, and
// record the lake and ponds that are left. False if nowhere is a host.
slide_make :: proc(g: ^Grid) -> bool {
	started := time.now()
	n := g.n
	best, head := f32(0), -1
	for ci in g.order {
		p := Point{x = middle_of(g, int(ci)).x, z = middle_of(g, int(ci)).y, cell = LAND_CELL}
		if s := host(SLIDE.host, &p); s > 0 && s + 0.02*hash01(ci, 0, seed + 700) > best do best, head = s + 0.02*hash01(ci, 0, seed + 700), int(ci)
	}
	if head < 0 {
		fmt.println("no slide: no slope near the steepest its rock holds, over a weaker bed, stands 60 m above a valley draining 0.5 to 5 km²")
		return false
	}
	draw :: proc(r: [2]f32, i: i32) -> f32 { return math.lerp(r[0], r[1], hash01(i, i32(fnv.fnv32a(transmute([]u8)region.kind)), seed + 701)) }   // each kind of island draws its own
	valley := head
	for g.next[valley] >= 0 && g.area[valley] < CHANNEL_AREA do valley = int(g.next[valley])
	to := middle_of(g, valley) - middle_of(g, head)
	long := clamp(f32(math.hypot(to.x, to.y)), SLIDE.length[0], SLIDE.length[1])*f32(region.size/REFERENCE)
	wide := long*draw(SLIDE.width, 1)
	age := SLIDE.age[0]*math.pow(SLIDE.age[1]/SLIDE.age[0], draw({0, 1}, 2))
	contrast, deep, strong, weak := cap_at(head)
	deep = clamp(deep + 5, 12, 50)   // it breaks through the cap into the weaker bed
	landslide.rock, landslide.law = strong, rocks.law[strong]   // the debris is the cap's blocks
	p := Point{x = middle_of(g, head).x, z = middle_of(g, head).y, cell = LAND_CELL}
	down := to/max(math.hypot(to.x, to.y), 1)
	middle := middle_of(g, head) + down*f64(long/2)   // the host is where it broke away, at its head

	// The scar: a spoon reaching through the cap, steep at its head and sides, thinning to
	// nothing at its foot, where the mass left the hillside, and never lower than the valley floor.
	// Only ground nearly as steep as at its head gives way; the gentle foot of the slope stays.
	before := make([]f32, n*n, context.temp_allocator)
	copy(before, g.z)
	moved: f64
	r := int(long/g.d) + 1
	foot, lowest := middle + down*f64(long/2), g.z[valley]
	for y in max(head/n - r, 1)..=min(head/n + r, n - 2) do for x in max(head%n - r, 1)..=min(head%n + r, n - 2) {
		c := y*n + x
		d := middle_of(g, c) - middle
		a, b := f32(d.x*down.x + d.y*down.y)/(long/2), f32(d.y*down.x - d.x*down.y)/(wide/2)
		if cut := min(deep*math.sqrt(max(1 - a*a - b*b, 0))*(1 - max(a, 0))*smoothstep(0.3, 0.6, land.slope[c]/land.slope[head]), g.z[c] - lowest); cut > 0 && !g.sea[c] {
			g.z[c] -= cut
			land.slid[c] = -cut
			moved += f64(cut*g.d*g.d)
		}
	}

	// The debris runs out from the scar's foot and comes to rest under a surface that falls away
	// from there, three times faster back toward the scar and half again across the slide's path,
	// filling the valley and riding up its far side. It breaks into slabs about as large as the
	// mass was thick, which come to rest as hummocks about twice that across and half that high,
	// on the debris and scattered beyond its front, which they break into lobes. How high that
	// surface starts is found so the debris holds all that slid, swollen as it broke.
	Lay :: struct { c: i32, run, lump: f32 }   // metres out, and the hummock's rise over the debris' top
	lay := make([dynamic]Lay, context.temp_allocator)
	fall, swell := draw(SLIDE.runout, 3), draw(SLIDE.bulk, 4)
	for ci in g.order {
		at := middle_of(g, int(ci))
		d := at - foot
		along, across := f32(d.x*down.x + d.y*down.y), f32(d.y*down.x - d.x*down.y)
		if run := math.sqrt(math.pow(along*(1 if along > 0 else 3), 2) + math.pow(1.5*across, 2)); run < 2500 {
			append(&lay, Lay{ci, run, deep*fbm(at.x, at.y, f64(max(2*deep, 80)), LAND_CELL, 2, seed + 702)})   // no smaller than the land's cells can hold
		}
	}
	lo, hi := f32(-200), f32(2000)
	for _ in 0..<40 {
		top, laid := (lo + hi)/2, f64(0)
		for l in lay do laid += f64(max(top - fall*l.run + l.lump - g.z[l.c], 0))
		if laid*f64(g.d*g.d) > moved*f64(swell) do hi = top
		else do lo = top
	}
	for l in lay {
		t := max(lo - fall*l.run + l.lump - g.z[l.c], 0)
		g.z[l.c] += t
		land.slid[l.c] += t
	}
	append(&region.features, Feature{kind = .Slide, at = middle, reach = long, size = f32(moved), age = age, cause = -1,
		measured = {{"its steepness against what its rock holds", FIELDS[.At_Limit].at(&p)}, {"the strength of the cap over the bed under it", contrast}, {"km² drained by the valley below", land.valley[head]/1e6}}})
	landslide.feature = len(region.features) - 1

	// The land wears for the slide's age, with the water standing behind the debris kept as a
	// lake: the stream cuts its outlet into the debris, the scar's head stands back to what its
	// rock holds and the hummocks soften. What it carries into the lake is not yet laid there.
	g.keep = true
	for _ in 0..<3 {
		route(g)
		erode(g, age/3)
		creep(g, age/3)
	}
	g.keep = false
	route(g)
	for c in g.order do if abs(land.slid[c]) > 0.5 || math.hypot(middle_of(g, int(c)).x - middle.x, middle_of(g, int(c)).y - middle.y) < f64(long) {
		if t := g.z[c] - before[c] - g.uplift[c]*g.lift*age; abs(t) > 1 do land.slid[c] = t   // what it laid and took, and the wear since: its head stands back
	}

	// Lakes and ponds: each hollow the slide made holds water to a little under its lowest spill,
	// at a block's top as a river's pools do. One a stream runs into is a lake its debris dammed,
	// and leaves over its spill, which the stream cuts; one without is a pond among the hummocks
	// or in the scar, and seeps away through the debris. Hollows the slide did not make have no
	// cause and hold no water, nor do those on a fallen crater's floor, where water sinks.
	hollow := make([]bool, n*n, context.temp_allocator)
	for c in g.order {
		hollow[c] = g.fill[c] > g.z[c] + 0.05
		for v in region.vents do if v.fallen && math.hypot(middle_of(g, int(c)).x - v.at.x, middle_of(g, int(c)).y - v.at.y) < f64(v.crater) do hollow[c] = false
	}
	group, sizes := patches(n, hollow, 2)   // hollows a few cells apart share a shore, so they are one water at one level
	Pool :: struct { spill, inflow: f32, slid: bool }
	pools := make([]Pool, len(sizes), context.temp_allocator)
	for &q in pools do q.spill = 1e9
	for c in g.order do if k := group[c]; k >= 0 {
		pools[k].spill, pools[k].inflow = min(pools[k].spill, g.fill[c]), max(pools[k].inflow, g.area[c])
		pools[k].slid ||= abs(land.slid[c]) > 0.5
	}
	lakes, ponds := -1, 0
	for q, k in pools do if q.slid && len(region.features) < 255 {
		f := Feature{kind = .Lake if q.inflow >= CHANNEL_AREA else .Pond, level = math.floor(q.spill - 0.55) + 0.55, age = age, cause = landslide.feature}
		cells, deepest := 0, f32(0)
		for c in g.order do if group[c] == i32(k) && g.z[c] < f.level {
			cells += 1
			f.at += middle_of(g, int(c))
			deepest = max(deepest, f.level - g.z[c])
			land.lake[c] = u8(len(region.features) + 1)
		}
		if cells == 0 do continue
		f.at /= f64(cells)
		f.size = f32(cells)*g.d*g.d
		for c in g.order do if land.lake[c] == u8(len(region.features) + 1) do f.reach = max(f.reach, f32(math.hypot(middle_of(g, int(c)).x - f.at.x, middle_of(g, int(c)).y - f.at.y)) + g.d/2)
		f.measured = {{"its deepest, metres", deepest}, {"km² draining into it", q.inflow/1e6}, {}}
		if f.kind == .Lake && (lakes < 0 || f.size > region.features[lakes].size) do lakes = len(region.features)
		ponds += int(f.kind == .Pond)
		append(&region.features, f)
	}
	for c in 0..<n*n do if land.lake[c] > 0 || abs(land.slid[c]) > 0.5 {
		at, e := middle_of(g, c), 3*f64(g.d)
		landslide.box = {min(landslide.box[0], at.x - e), min(landslide.box[1], at.y - e), max(landslide.box[2], at.x + e), max(landslide.box[3], at.y + e)}
	}

	fmt.printf("a slide about %s years ago, in %.0f ms: %.1f million m³ of %v over %v, %.0f m long, from %.0f, %.0f into a valley draining %.1f km²",
		years(age), time.duration_milliseconds(time.since(started)), moved/1e6, strong, weak, long, middle.x + f64(region.origin.x), middle.y + f64(region.origin.y), land.valley[head]/1e6)
	if lakes >= 0 {
		l := region.features[lakes]
		fmt.printf("; it dammed a lake of %.1f ha at %.1f m, %.0f m deep, that %s", l.size/1e4, l.level, l.measured[0].value, "spills over it")
	} else do fmt.print("; it dammed no lake")
	fmt.printfln("; %d pond%s", ponds, "" if ponds == 1 else "s")
	return true
}

// The age of an event to two figures, as a person would say it.
years :: proc(age: f32) -> string {
	step := math.pow(10, math.floor(math.log10(age)) - 1)
	return fmt.tprintf("%.0f", math.round(age/step)*step)
}

// Whether a point is near the slide at all, so the rest of the world asks nothing more.
in_slide :: #force_inline proc(x, z: f64) -> bool {
	return x > landslide.box[0] && x < landslide.box[2] && z > landslide.box[1] && z < landslide.box[3]
}

// The level of the water a point may lie under, if it lies in the cells of a lake or pond or the
// cells beside them, where its shore lies (inside); and, outside them, how high a bank must stand
// to hold it: a block clear of the water at their edge and falling away at about the angle of
// rest. The highest where two meet; NO_WATER for none.
lake_near :: proc(x, z: f64) -> (level: f32, inside: bool, bank: f32) {
	level, bank = NO_WATER, NO_WATER
	if !in_slide(x, z) do return
	c, n := land_cell(x, z), land.n
	for dy in -2..=2 do for dx in -2..=2 do if l := land.lake[c + dy*n + dx]; l > 0 {
		at := middle_of(land.grid, c + dy*n + dx)
		out := f32(math.hypot(max(abs(x - at.x) - 1.5*LAND_CELL, 0), max(abs(z - at.y) - 1.5*LAND_CELL, 0)))
		if out == 0 do level, inside = max(level, region.features[l - 1].level), true
		else do bank = max(bank, region.features[l - 1].level + 0.45 - 0.7*out)
	}
	if inside do bank = NO_WATER
	return
}

// Metres of slide debris at a point.
slid_at :: proc(x, z: f64) -> f32 {
	return max(land_at(land.slid, land.n, x, z), 0) if in_slide(x, z) else 0
}

// What the far lakes and ponds look like: a quad at the level over each of their cells and each
// cell beside them, where their shore lies; the ground hides it where it stands above the level,
// so the ground and not the grid draws the shore, as near by. Added to the rivers' strip.
lakes_draw :: proc() {
	n, d := land.n, f32(LAND_CELL)/2
	for c in n + 1..<n*n - n - 1 {
		y := f32(NO_WATER)
		for dy in -1..=1 do for dx in -1..=1 do if l := land.lake[c + dy*n + dx]; l > 0 do y = max(y, region.features[l - 1].level)
		if y == NO_WATER do continue
		at := middle_of(land.grid, c)
		x0, z0, x1, z1 := f32(at.x) - d, f32(at.y) - d, f32(at.x) + d, f32(at.y) + d
		quad := [4][4]f32{{x0, y, z0, 2}, {x1, y, z0, 2}, {x0, y, z1, 2}, {x1, y, z1, 2}}   // 2: still and deep, not a river's width
		if len(rivers.ribbon) > 0 do append(&rivers.ribbon, rivers.ribbon[len(rivers.ribbon) - 1], quad[0])
		append(&rivers.ribbon, ..quad[:])
	}
}

// The feature a point lies in, in a sentence, as --why prints it.
feature_words :: proc(x, z: f64, h: f32) {
	fall, by := -1, f64(1e9)
	for f, i in region.features do if d := math.hypot(x - f.at.x, z - f.at.y); f.kind == .Fall && d < max(f64(f.reach), 12) && d < by do fall, by = i, d
	if fall >= 0 {
		f := region.features[fall]
		fmt.printfln("%s a fall %.0f m high, %.0f m off: a stream draining %.2f km², %.3f m³/s, leaves a lip of %v and falls %s into a pool %.1f m deep that its floods have scoured (Veronese's rule, from the fall's height and a flood's flow over each metre of the lip)%s.",
			"at the lip of" if h > f.level - 1.5 else "in the pool under" if by < 12 else "in the gorge below", f.measured[0].value, by, f.measured[1].value, f.size, fall_rock(f),
			"to the sea" if f.level - f.measured[0].value < 0.5 else "past the weaker beds under it", f.measured[2].value,
			fmt.tprintf("; below it the stream runs %.0f m in the gorge the fall cut as it wore back", f.reach) if f.reach > 8 else "")
	}
	for f in region.features do if f.kind == .Spring && math.hypot(x - f.at.x, z - f.at.y) < 30 {
		c := land_cell(f.at.x, f.at.y)
		fmt.printfln("by a spring %.0f m off: rain soaking down through %v comes out where it meets %v, which holds it, and %.2f km² of land above feed it %.4f m³/s; a brook starts here.",
			math.hypot(x - f.at.x, z - f.at.y), rock_in(f.level + 3, land.grid.base[c], ROCK_SIM), rock_in(f.level - 2, land.grid.base[c], ROCK_SIM), f.measured[0].value, f.size)
	}
	if !in_slide(x, z) do return
	s := region.features[landslide.feature]
	ago := fmt.tprintf("the slide about %s years ago", years(s.age))
	if level, inside, _ := lake_near(x, z); inside {
		k := int(land.lake[land_cell(x, z)]) - 1
		if k < 0 do for f, i in region.features do if (f.kind == .Lake || f.kind == .Pond) && f.level == level do k = i
		f, under := region.features[k], h < level
		fmt.printfln("%s a %s of %.1f ha whose water stands at %.1f m%s, %s by %s; %s.", "in" if under else "on the shore of", "lake" if f.kind == .Lake else "pond", f.size/1e4, f.level,
			fmt.tprintf(", %.1f m deep here", level - h) if under else "", "dammed" if f.kind == .Lake else "left in a hollow", ago,
			"no stream leaves it, and it seeps away through the debris" if f.kind == .Pond else "its stream leaves over the lowest point of the debris, which it has cut")
	}
	if t := land_at(land.slid, land.n, x, z); t > 0.5 {
		fmt.printfln("debris of %s, %.0f m deep here: blocks of %v broken from a scar %.0f m off, which held %.2f million m³. Soil has had %s years to grow on it.", ago, t, landslide.rock, math.hypot(x - s.at.x, z - s.at.y), s.size/1e6, years(s.age))
	} else if t < -0.5 {
		fmt.printfln("in the scar of %s, where %.0f m of the hillside slid away. Measured when it fell: %s %.2f; %s %.2f; %s %.1f.", ago, -t, s.measured[0].what, s.measured[0].value, s.measured[1].what, s.measured[1].value, s.measured[2].what, s.measured[2].value)
	}
}

// ---- Roofed places (ground-and-underground.md, D4) ------------------------------------------

// Three kinds of hollow under a roof of rock, each a feature placed where its host holds best, as
// the slide is, and carved out of the blocks once they are filled, so its roof and walls are the
// beds. A notch is cut by the waves into the foot of a sea cliff at the sea's level; a shelter is
// where a weak bed has weathered back under a strong one at the foot of a face; a sea cave is
// driven into a headland along one of its cracks. Each keeps its outline: for every metre of
// ground in its square, the floor and roof of the space carved there and the top of the ground
// over it, which the blocks, the far rings, the water and the light under its roof all read.
Hollow_Row :: struct {
	why:   string,
	host:  []Window,
	most:  [2]f32,   // how many the island has at most, drawn
	apart: f32,      // metres at least from any other
	reach: [2]f32,   // metres along the face it is cut into, or for a cave, into the rock
	deep:  [2]f32,   // metres into the rock at its deepest, or for a cave, across
	high:  [2]f32,   // metres from floor to roof at its mouth
	floor: f32,      // metres from the sea to its floor; a shelter's lies under its roof instead
}
HOLLOWS := #partial [Feature_Kind]Hollow_Row{
	.Notch   = {"the waves cut it at the sea's level into the foot of a cliff open to the swell", {{.Swell, 0.15, ANY, 0.1}, {.Inland, -ANY, 24, 16}, {.Slope, 1.5, ANY, 0.5}}, {1, 3}, 400, {50, 110}, {2.5, 5}, {2.5, 4}, -1},
	.Shelter = {"a weak bed weathered back under a strong one at the foot of a face", {{.Contact, 0.25, ANY, 0.1}, {.At_Limit, 0.8, ANY, 0.2}, {.Inland, 150, ANY, 100}}, {2, 4}, 400, {16, 40}, {4, 16}, {2, 4}, 0},
	.Cave    = {"the waves drove it into a headland open to the swell along one of its cracks", {{.Headland, 0.5, ANY, 0.1}, {.Swell, 0.15, ANY, 0.1}, {.Slope, 1.5, ANY, 0.5}, {.Strength, 0.5, ANY, 0.1}}, {1, 2}, 300, {18, 40}, {4, 7}, {8, 14}, -2},
	// A stack is not a hollow but is placed the same way: `reach` is how far off the cliff's foot it
	// stands, `deep` its radius and `high` the share of the cliff's height it keeps.
	.Stack   = {"the waves cut the cliff back round it and left its harder rock standing", {{.Headland, 0.5, ANY, 0.15}, {.Swell, 0.2, ANY, 0.1}, {.Strength, 0.5, ANY, 0.15}, {.Slope, 1, ANY, 0.5}}, {2, 6}, 250, {5, 40}, {6, 13}, {0.4, 0.9}, 0},
}
Hollow :: struct {
	feature:   int,
	x0, z0, w: i32,       // its square: corner and side, metres relative to the region's middle
	span:      [][3]i16,  // for each metre in it: the floor and roof of what is carved, and the top of the ground over it
}

// The strongest step up from a weaker bed to a stronger one on the hillside within a cell, the
// foot of a face, and where it lies.
contact_at :: proc(c: int) -> (contrast, y: f32) {
	g := land.grid
	for h := g.z[c] - 8*land.slope[c]; h < g.z[c] + 8*land.slope[c]; h += 1 {
		below := MATERIALS[rock_in(h, g.base[c], 0)].strength
		if s := MATERIALS[rock_in(h + 1, g.base[c], 0)].strength - below; below > 0 && s > contrast do contrast, y = s, h + 1
	}
	return
}

// The share of sea within 48 m of a cell.
headland :: proc(c: int) -> (s: f32) {
	n := land.n
	for dy in -3..=3 do for dx in -3..=3 do s += f32(int(land.grid.sea[clamp(c + dy*n + dx, 0, n*n - 1)]))/49
	return
}

hollows_make :: proc() {
	started := time.now()
	g := land.grid
	made: [Feature_Kind]int
	first := len(region.features)
	for row, kind in HOLLOWS do if len(row.host) > 0 {
		Spot :: struct { s: f32, c: i32 }
		spots := make([dynamic]Spot, context.temp_allocator)
		for ci in g.order {
			p := Point{x = middle_of(g, int(ci)).x, z = middle_of(g, int(ci)).y, cell = LAND_CELL}
			if s := host(row.host, &p); s > 0.5 do append(&spots, Spot{s + 0.05*hash01(ci, i32(kind), seed + 720), ci})
		}
		slice.sort_by(spots[:], proc(a, b: Spot) -> bool { return a.s > b.s })
		most := int(math.round(math.lerp(row.most[0], row.most[1], hash01(i32(kind), 0, seed + 721))))
		next: for sp in spots {
			if made[kind] >= most do break
			at := middle_of(g, int(sp.c))
			for f in region.features[first:] do if math.hypot(f.at.x - at.x, f.at.y - at.y) < f64(row.apart) do continue next
			made[kind] += int(stack_make(int(sp.c), at) if kind == .Stack else hollow_carve(kind, int(sp.c), at))
		}
	}
	fmt.printf("roofed places and stacks in %.0f ms: %d sea notches, %d rock shelters, %d sea caves, %d sea stacks with %d skerries; at", time.duration_milliseconds(time.since(started)), made[.Notch], made[.Shelter], made[.Cave], made[.Stack], len(pillars) - made[.Stack])
	for f, i in region.features[first:] do fmt.printf("%s %v %.0f, %.0f", "," if i > 0 else "", f.kind, f.at.x + f64(region.origin.x), f.at.y + f64(region.origin.y))
	fmt.println()
}

// A sea stack and the skerries round it: columns of the cliff's own beds standing in the sea,
// each longer along the strike of its beds, where its cracks part it, than across.
Pillar :: struct {
	at:      [2]f64,
	along:   [2]f64,   // the strike of its beds
	r, top:  f32,      // mean radius, and height of its top over the sea
	long:    f32,      // its length over its breadth
	feature: int,
}

// Stand a stack off the cliff at a headland, out from where the ground first lies under the sea,
// as high as a share of the cliff, with up to three lower skerries seaward of it. False if the
// sea there is too shallow.
stack_make :: proc(c: int, at: [2]f64) -> bool {
	row, g, i := HOLLOWS[.Stack], land.grid, i32(len(region.features))
	draw :: proc(r: [2]f32, i, k: i32) -> f32 { return math.lerp(r[0], r[1], hash01(i, k, seed + 731)) }
	b := math.to_radians(f64(land.facing[c]))
	out := [2]f64{math.sin(b), -math.cos(b)}   // the way the ground falls, toward the sea
	cliff: f32
	for dy in -3..=3 do for dx in -3..=3 do cliff = max(cliff, g.z[clamp(c + dy*g.n + dx, 0, g.n*g.n - 1)])
	foot := at
	for k := 0; ground(foot.x, foot.y, 1).h > -1; k += 1 {
		if k == 100 do return false
		foot += out
	}
	r := draw(row.deep, i, 1)
	middle := foot + out*f64(draw(row.reach, i, 0) + r)
	if ground(middle.x, middle.y, 1).h > -1 do return false
	top := cliff*draw(row.high, i, 2)
	along, long := rock_strike(middle.x, middle.y), draw({1, 1.8}, i, 4)
	append(pillars, Pillar{middle, along, r, top, long, len(region.features)})
	for k in 0..<i32(draw({0, 3.99}, i, 3)) {
		a, d := f64(draw({-1.4, 1.4}, i, 10 + k)), f64(draw({12, 40}, i, 20 + k))
		p := middle + d*[2]f64{out.x*math.cos(a) - out.y*math.sin(a), out.x*math.sin(a) + out.y*math.cos(a)}
		if ground(p.x, p.y, 1).h < -0.5 do append(pillars, Pillar{p, along, draw({2, 4.5}, i, 30 + k), draw({1.5, max(0.35*top, 2)}, i, 40 + k), long, len(region.features)})
	}
	append(&region.features, Feature{kind = .Stack, at = middle, reach = f32(math.hypot(middle.x - foot.x, middle.y - foot.y)) - r, size = math.PI*r*r*top, level = top,
		age = region.history[len(region.history) - 1].years*region.history[len(region.history) - 1].steps, cause = -1,
		measured = {{"how open its shore is to the swell", land.swell[c]}, {"the share of sea within 48 m of the headland", headland(c)}, {"the strength of the rock at the cliff's foot", MATERIALS[rock_in(g.z[c] - 2, g.base[c], ROCK_SIM)].strength}}})
	return true
}

// The top of any stack or skerry at a point over ground at `under`, whose rock base is `base`,
// and whether it is the rubble round its foot rather than the column. Each bed of the column
// stands out as far as it is strong, its outline ragged and shifted by its own amount, and the
// column widens toward its foot; so its sides step at the beds as the cliff's do, and its top is
// whatever bed the waves have left last. Far off, it is widened by a third of a cell, so that the
// cells it touches draw it.
stack_at :: proc(x, z, cell: f64, under, base: f32) -> (h: f32, rubble: bool) {
	h = under
	for p in pillars {
		dx, dz := x - p.at.x, z - p.at.y
		reach := f64(p.r*p.long*2 + 8)
		if abs(dx) > reach || abs(dz) > reach do continue
		grow := 0.35*f32(cell) if cell > 1 else 0
		u, v := f32(dx*p.along.x + dz*p.along.y)/(p.r*p.long + grow), f32(dz*p.along.x - dx*p.along.y)/(p.r/math.sqrt(p.long) + grow)
		ragged := 0.25*fbm(x, z, f64(1.5*p.r), cell, 3, seed + 732)
		top := p.top*(1 - 0.15*(1 + fbm(x, z, f64(p.r), cell, 2, seed + 733)))
		for y := top; y > under; y -= 1 {   // from the top down, the first bed that reaches out to here
			n := rocks.bed[clamp(int(y - base - STACK_LO), 0, STACK_LEN - 1)]
			wide := (0.6 + 0.5*MATERIALS[rocks.beds[n].kind].strength + 0.3*(hash01(i32(n), 0, seed + 734) - 0.5))*(1 + 0.7*(1 - y/p.top)*(1 - y/p.top))
			if du, dv := u - 0.3*(hash01(i32(n), 1, seed + 734) - 0.5), v - 0.3*(hash01(i32(n), 2, seed + 734) - 0.5); math.sqrt(du*du + dv*dv)*(1 + ragged) < wide {
				if y > h do h, rubble = y, false
				break
			}
		}
		if cell <= 2 && math.sqrt(u*u + v*v) < 2.2 do if s := under + stones(x, z, 0.7, 1.2); s > h do h, rubble = s, true
	}
	return
}

// The stack a point lies on or beside, in a sentence, as --why prints it.
stack_words :: proc(x, z: f64) {
	for p in pillars do if math.hypot(x - p.at.x, z - p.at.y) < f64(2.2*p.r*p.long + 3) {
		f := region.features[p.feature]
		fmt.printfln("%s, %.0f m high and %.0f m across, %.0f m off the foot of the cliff: %s. Measured when it was made: %s %.2f; %s %.2f; %s %.2f.",
			"a sea stack" if p.top == f.level else "a skerry beside a sea stack", p.top, 2*p.r, f.reach, HOLLOWS[.Stack].why,
			f.measured[0].what, f.measured[0].value, f.measured[1].what, f.measured[1].value, f.measured[2].what, f.measured[2].value)
		return
	}
}

// Draw a hollow's size from the seed, find its outline in the ground and record it. False if
// no rock is left to carve.
hollow_carve :: proc(kind: Feature_Kind, c: int, at: [2]f64) -> bool {
	row, g, i := HOLLOWS[kind], land.grid, i32(len(hollows))
	draw :: proc(r: [2]f32, i, k: i32) -> f32 { return math.lerp(r[0], r[1], hash01(i, k, seed + 722)) }
	reach, deep, high := draw(row.reach, i, 0), draw(row.deep, i, 1), draw(row.high, i, 2)
	// A cave runs along the set of cracks nearer the way into the land, from where its line
	// first meets the sea.
	inland := [2]f64{-math.sin(math.to_radians(f64(land.facing[c]))), math.cos(math.to_radians(f64(land.facing[c])))}
	along := rock_strike(at.x, at.y)
	if abs(along.x*inland.x + along.y*inland.y) < 0.7071 do along = {-along.y, along.x}
	if along.x*inland.x + along.y*inland.y < 0 do along = -along
	middle, mouth := at, at
	if kind == .Cave {
		for k := 0; ground(mouth.x, mouth.y, 1).h >= row.floor; k += 1 {
			if k == 80 do return false
			mouth -= along
		}
		middle = mouth + along*f64(reach/2)
	}
	half := i32(reach/2 + deep + 6) if kind != .Cave else i32(reach/2 + 8)
	h := Hollow{feature = len(region.features), x0 = i32(math.floor(middle.x)) - half, z0 = i32(math.floor(middle.y)) - half, w = 2*half}
	n := int(h.w)
	h.span = make([][3]i16, n*n)
	far := make([]f32, n*n, context.temp_allocator)   // metres from where the open air reaches the floor
	contrast, contact := contact_at(c)
	strong := int(rocks.bed[clamp(int(contact + 0.5 - g.base[c] - STACK_LO), 0, STACK_LEN - 1)])
	for k in 0..<n*n {
		x, z := f64(h.x0 + i32(k%n)) + 0.5, f64(h.z0 + i32(k/n)) + 0.5
		gr := ground(x, z, 1)
		floor, roof := row.floor, row.floor + high*(1 + 0.25*fbm(x, z, 16, 1, 2, seed + 723))
		if kind == .Shelter {   // its roof is the underside of the strong bed, wherever that lies here
			y := math.floor(gr.base + STACK_LO + rocks.floor[strong]) - 1
			for int(rocks.bed[clamp(int(y + 0.5 - gr.base - STACK_LO), 0, STACK_LEN - 1)]) < strong do y += 1
			floor, roof = y - high, y
		}
		h.span[k] = {i16(floor), i16(math.round(roof)), i16(math.round(gr.h))}
		far[k] = 0 if h.span[k][2] <= h.span[k][0] + 1 else 1e9
	}
	// How far each metre lies from the open air, by two sweeps across the square.
	for pass in 0..<2 do for j in 0..<n do for i in 0..<n {
		x, y := i if pass == 0 else n - 1 - i, j if pass == 0 else n - 1 - j
		s := 1 if pass == 0 else -1
		for o in ([4][3]f32{{-1, 0, 1}, {0, -1, 1}, {-1, -1, 1.41}, {1, -1, 1.41}}) {
			u, v := x + s*int(o.x), y + s*int(o.y)
			if u >= 0 && v >= 0 && u < n && v < n do far[y*n + x] = min(far[y*n + x], far[v*n + u] + o.z)
		}
	}
	carved: f32
	for k in 0..<n*n {
		x, z := f64(h.x0 + i32(k%n)) + 0.5, f64(h.z0 + i32(k/n)) + 0.5
		s := &h.span[k]
		floor, roof := f32(s[0]), f32(s[1])
		if kind == .Cave {   // a slot along the crack, wandering a little, narrowing and rising to its end
			t, a := f32((x - mouth.x)*along.x + (z - mouth.y)*along.y), f32((z - mouth.y)*along.x - (x - mouth.x)*along.y) - 1.5*fbm(x*along.x + z*along.y, 0, 12, 1, 2, seed + 724)
			wide := deep/2*(1 - math.pow(clamp(t/reach, 0, 1), 3))*(0.8 + 0.4*fbm(x, z, 3, 1, 2, seed + 725))
			q := clamp(t/reach, 0, 1)
			floor += 3*smoothstep(0.6, 1, q)
			roof = row.floor + high*math.sqrt(max(1 - a*a/max(wide*wide, 0.01), 0))*(1 - 0.5*q*q) + 1.5*fbm(x, z, 4, 1, 1, seed + 727)   // a tall slot, ragged where blocks broke from its roof
			if t < -6 || abs(a) >= wide do roof = floor
		} else {   // deepest at its middle and tapering to its ends, its back ragged, rounded in section
			ends := smoothstep(0, 0.4, 1 - f32(math.hypot(x - at.x, z - at.y))/(reach/2))
			q := far[k]/max(deep*ends*(0.8 + 0.4*fbm(x, z, 5, 1, 2, seed + 726)), 0.01)
			if q >= 1 do roof = floor
			else if kind == .Notch do roof = floor + (roof - floor)*math.sqrt((1 - q*q)*ends)
			else do floor = roof - (roof - floor)*math.sqrt((1 - q*q)*ends)
		}
		s[0], s[1] = i16(math.round(floor)), i16(math.round(roof))
		if s[2] - s[1] < 2 do s[1] = max(s[1], s[2])   // a roof thinner than that has fallen in
		if s[1] > s[0] && s[2] > s[0] do carved += f32(min(s[1], s[2]) - s[0])
	}
	if carved < 20 {
		delete(h.span)
		return false
	}
	measured := #partial [Feature_Kind][3]Measure{
		.Slide = {}, .Lake = {}, .Pond = {},
		.Notch = {{"how open its shore is to the swell", land.swell[c]}, {"the steepness of the cliff, rise over run", land.slope[c]}, {"the strength of its rock", MATERIALS[rock_in(0, g.base[c], 0)].strength}},
		.Shelter = {{"how much stronger its roof's bed is than the bed under it", contrast}, {"the steepness of the face against what its rock holds", land.slope[c]/rocks.law[rocks.beds[strong].kind].limit}, {"metres to the sea", land.inland[c]}},
		.Cave = {{"the share of sea within 48 m of the headland", headland(c)}, {"how open its shore is to the swell", land.swell[c]}, {"metres between the cracks of its rock", MATERIALS[rock_in(0, g.base[c], 0)].crack}},
	}
	append(&region.features, Feature{kind = kind, at = middle if kind == .Cave else at, reach = reach, size = carved, level = f32(row.floor) if kind != .Shelter else contact, age = region.history[len(region.history) - 1].years*region.history[len(region.history) - 1].steps if kind != .Shelter else 0, cause = -1, measured = measured[kind]})
	append(hollows, h)
	return true
}

// The space carved at a column, relative to the region's middle: its floor and the roof over it,
// or the ground's top where nothing is left over it. At a far cell, the lowest floor and highest
// roof of the metres in it that have a roof, so a mouth is drawn on the face from afar.
hollow_at :: proc(x, z, cell: f64) -> (span: [2]i32) {
	r := i32(cell)/2
	for h in hollows {
		i, j := i32(math.floor(x)) - r - h.x0, i32(math.floor(z)) - r - h.z0
		if i + i32(cell) <= 0 || j + i32(cell) <= 0 || i >= h.w || j >= h.w do continue
		if cell <= 1 {
			s := h.span[j*h.w + i]
			if top := min(s[1], s[2]); top > s[0] do return {i32(s[0]), i32(top)}
			continue
		}
		for v in max(j, 0)..<min(j + i32(cell), h.w) do for u in max(i, 0)..<min(i + i32(cell), h.w) {
			s := h.span[v*h.w + u]
			if s[1] > s[0] && s[1] < s[2] do span = {i32(s[0]), i32(s[1])} if span[1] <= span[0] else {min(span[0], i32(s[0])), max(span[1], i32(s[1]))}
		}
	}
	return
}

// Whether a block, relative to the region's middle, is rock as generated, where it lies in a
// hollow's square; unknown elsewhere.
hollow_rock :: proc(x, y, z: i32) -> (rock, known: bool) {
	for h in hollows do if x >= h.x0 && z >= h.z0 && x < h.x0 + h.w && z < h.z0 + h.w {
		s := h.span[(z - h.z0)*h.w + x - h.x0]
		return y < i32(s[2]) && (y < i32(s[0]) || y >= i32(s[1])), true
	}
	return false, false
}

// The hollow a point lies in, in a sentence, as --why prints it.
hollow_words :: proc(x, z: f64) {
	NAMES := #partial [Feature_Kind]string{.Notch = "sea notch", .Shelter = "rock shelter", .Cave = "sea cave"}
	for h in hollows {
		span := hollow_at(x, z, 1)
		f := region.features[h.feature]
		i, j := i32(math.floor(x)) - h.x0, i32(math.floor(z)) - h.z0
		if span[1] <= span[0] || i < 0 || j < 0 || i >= h.w || j >= h.w do continue
		s := h.span[j*h.w + i]
		fmt.printfln("%s a %s, %s: %s%s. Here its floor is at %d m and %s. Measured when it was made: %s %.2f; %s %.2f; %s %.2f.",
			"under the roof of" if s[1] < s[2] else "at the mouth of", NAMES[f.kind], fmt.tprintf("%.0f m long", f.reach), HOLLOWS[f.kind].why, fmt.tprintf(", over the %s years the sea has stood where it is", years(f.age)) if f.kind != .Shelter else "", s[0],
			fmt.tprintf("its roof %d m over it, the underside of %v", s[1] - s[0], rock_in(f32(s[1]) + 0.5, ground(x, z, 1).base, 0)) if s[1] < s[2] else "it is open to the sky",
			f.measured[0].what, f.measured[0].value, f.measured[1].what, f.measured[1].value, f.measured[2].what, f.measured[2].value)
		return
	}
}
