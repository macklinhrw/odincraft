package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:time"

// Events and the features they leave (foundations/kinds-and-places.md, D6). A feature is a
// record with an identity: what it is, where and how large, how many years ago it was made, what
// made it and what was measured when it was. One event happens so far, a landslide, near the end
// of the forming (foundations/landforms.md, D4), and it leaves three kinds of feature: its own
// scar and debris, the lake its debris dams, and the ponds among its hummocks.

Feature_Kind :: enum u8 { Slide, Lake, Pond }
Measure :: struct { what: string, value: f32 }
Feature :: struct {
	kind:     Feature_Kind,
	at:       [2]f64,   // its middle, relative to the region's
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
landslide := Slide{box = {1e9, 1e9, -1e9, -1e9}}

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
	if !in_slide(x, z) do return
	s := region.features[landslide.feature]
	ago := fmt.tprintf("the slide about %s years ago", years(s.age))
	if level, inside, _ := lake_near(x, z); inside {
		k := int(land.lake[land_cell(x, z)]) - 1
		if k < 0 do for f, i in region.features do if f.kind != .Slide && f.level == level do k = i
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
