package main

import "core:fmt"
import "core:math"

// The fields every catalogue's rows are written in (docs/foundations/kinds-and-places.md, D2
// and D3). A field has a value everywhere, in its own unit, read at a point at a cell size.
// The map paints any of them (--overlay=), and --why= reports them. A condition of a new shape
// becomes a new field here, never new code in a row.
Field :: enum u8 {
	// on the land's 16 m grid
	Wetness, Livable, Slope, Drainage, Uplift, Rock, Facing, Humped, Inland, Sunlight, Exposure, Cold, Woods,
	// from the ground the generator makes at the point
	Height, Steepness, Gravel, Fallen, Beach, Too_Steep,
}
GROUND_FIELDS :: bit_set[Field]{.Height, .Steepness, .Gravel, .Fallen, .Beach, .Too_Steep}

// What a field is read from: a point, and the ground made there when the field needs it.
Point :: struct {
	using g:    Ground,
	x, z, cell: f64,
	vary:       f32,   // broad patches broken at their edges, about -1.7 to 1.7, that move the beach and what soil holds
}

point_at :: proc(x, z, cell: f64) -> (p: Point) {
	p.g, p.x, p.z, p.cell = ground(x, z, cell), x, z, cell
	p.vary = fbm(x, z, 120, cell, 2, seed + 100) + 0.7*fbm(x, z, 22, cell, 2, seed + 101)
	return
}

Field_Info :: struct {
	name, unit, from: string,   // `from` reads after the value: "0.4 m under the line the waves..."
	at:      proc(p: ^Point) -> f32,
	lo, hi:  f32,               // the span the map paints from one colour to the other; also the scale of a near miss
	paint:   enum u8 { Ramp, Log, Kinds, Wheel },   // Log: lo and hi are powers of ten; Kinds: a material; Wheel: a bearing, grey where flat
	from_colour, to_colour: [3]f32,
}

FIELDS := [Field]Field_Info{
	.Wetness   = {"wetness", "", "0 on ridges to 1 in valley floors, by the land draining through", proc(p: ^Point) -> f32 { return land_at(land.wet, land.n, p.x, p.z) }, 0, 1, .Ramp, {0.90, 0.80, 0.50}, {0.05, 0.45, 0.40}},
	.Livable   = {"livable", "", "1 on ground a person could live on: under 20°, 2 m over the sea, a hectare or more", proc(p: ^Point) -> f32 { return land.live[land_cell(p.x, p.z)] }, 0, 1, .Ramp, {0.55, 0.55, 0.55}, {1.00, 0.55, 0.05}},
	.Slope     = {"slope", "", "rise over run of the formed land, smooth over 16 m", proc(p: ^Point) -> f32 { return land_at(land.slope, land.n, p.x, p.z) }, 0, 1.2, .Ramp, {0.95, 0.95, 0.90}, {0.65, 0.05, 0.05}},
	.Drainage  = {"drainage", " m²", "land draining through", proc(p: ^Point) -> f32 { return land.grid.area[land_cell(p.x, p.z)] }, 2.4, 7.4, .Log, {0.95, 0.95, 0.90}, {0.05, 0.10, 0.45}},
	.Uplift    = {"uplift", "", "share of the island's fastest rise", proc(p: ^Point) -> f32 { return land.grid.uplift[land_cell(p.x, p.z)]/f32(region.shape.rate) }, 0, 1.3, .Ramp, {0.20, 0.25, 0.45}, {0.95, 0.85, 0.30}},
	.Rock      = {"rock", "", "the bed at the formed land's surface, as a material", proc(p: ^Point) -> f32 { return f32(rock(p.x, f64(land_at(land.z[0], land.n, p.x, p.z)) - 0.5, p.z, p.cell)) }, 0, 0, .Kinds, {}, {}},
	.Facing    = {"facing", "°", "the bearing the ground falls toward, from north", proc(p: ^Point) -> f32 { return land.facing[land_cell(p.x, p.z)] }, 0, 360, .Wheel, {}, {}},
	.Humped    = {"humped", " m", "over the mean ground 208 m round; under 0, a hollow", proc(p: ^Point) -> f32 { return land_at(land.hump, land.n, p.x, p.z) }, -15, 15, .Ramp, {0.10, 0.35, 0.90}, {1.00, 0.75, 0.15}},
	.Inland    = {"inland", " m", "to the nearest sea", proc(p: ^Point) -> f32 { return land_at(land.inland, land.n, p.x, p.z) }, 0, 2000, .Ramp, {0.95, 0.95, 0.85}, {0.25, 0.10, 0.45}},
	.Sunlight  = {"sunlight", "", "sunlight in a year against flat ground", proc(p: ^Point) -> f32 { return land_at(land.sun, land.n, p.x, p.z) }, 0.6, 1.1, .Ramp, {0.20, 0.30, 0.80}, {1.00, 0.80, 0.15}},
	.Exposure  = {"exposure", "", "0 sheltered to 1 on a crest or shore open to the wind and salt", proc(p: ^Point) -> f32 { return land.exposed[land_cell(p.x, p.z)] }, 0, 1, .Ramp, {0.10, 0.40, 0.20}, {0.95, 0.90, 0.85}},
	.Cold      = {"cold", " m", "over the stream or shore the ground drains to, where a still night's cold air pools", proc(p: ^Point) -> f32 { return land_at(land.above, land.n, p.x, p.z) }, 50, 0, .Ramp, {0.95, 0.92, 0.85}, {0.10, 0.25, 0.70}},   // painted as a pool 50 m deep
	.Woods     = {"woods", "", "share of the thickest wood, by wetness, height and the woods' own patches", proc(p: ^Point) -> f32 { return forest_at(p.x, p.z) }, 0, 1, .Ramp, {0.90, 0.85, 0.65}, {0.05, 0.30, 0.08}},
	.Height    = {"height", " m", "of the ground over the sea", proc(p: ^Point) -> f32 { return p.h }, 0, 400, .Ramp, {0.95, 0.95, 0.90}, {0.35, 0.20, 0.10}},
	.Steepness = {"steepness", "", "rise over run of the ground in blocks, ledges and all", proc(p: ^Point) -> f32 { return p.steep }, 0, 1.5, .Ramp, {0.95, 0.95, 0.90}, {0.65, 0.05, 0.05}},
	.Gravel    = {"gravel", "", "1 on a bar or bed where a river lays gravel", proc(p: ^Point) -> f32 { return 1 if p.cover == .Gravel else 0 }, 0, 1, .Ramp, {0.95, 0.95, 0.90}, {0.10, 0.30, 0.75}},
	.Fallen    = {"fallen", " m", "depth of rock fallen from the face above", proc(p: ^Point) -> f32 { return p.fallen }, 0, 3, .Ramp, {0.95, 0.95, 0.90}, {0.40, 0.30, 0.25}},
	.Beach     = {"beach", " m", "how far under the line the waves throw sand to, which is 1.8 m over the sea give or take 1.2 in patches", proc(p: ^Point) -> f32 { return 1.8 + p.vary*1.2 - p.h }, -3, 3, .Ramp, {0.30, 0.55, 0.30}, {0.95, 0.85, 0.50}},
	.Too_Steep = {"too-steep", "", "how much steeper than soil holds, which is a rise over run of 1 (45°) give or take 0.15 in patches", proc(p: ^Point) -> f32 { return p.steep - (SOIL_HOLDS + 0.15*p.vary) }, -0.5, 0.5, .Ramp, {0.30, 0.55, 0.30}, {0.55, 0.50, 0.45}},
}

// A window holds where its field is over `lo` and up to `hi`, and fades to nothing `edge`
// beyond. A host's windows multiply; a host with none holds everywhere.
Window :: struct {
	field:        Field,
	lo, hi, edge: f32,
}
ANY :: 1e30   // no limit on that side

score :: proc(w: Window, v: f32) -> f32 {
	if v > w.lo && v <= w.hi do return 1
	if w.edge <= 0 do return 0
	return max(1 - max(w.lo - v, v - w.hi)/w.edge, 0)
}

host :: proc(windows: []Window, p: ^Point) -> (s: f32) {
	s = 1
	for w in windows do s *= score(w, FIELDS[w.field].at(p))
	return
}

// A window as words, "beach is 0.42 m (how far under ...); it needs over 0", and how far
// into it (or, below zero, short of it) the value lies, in the field's span.
window_words :: proc(w: Window, p: ^Point) -> (words: string, margin: f32) {
	f := FIELDS[w.field]
	v := f.at(p)
	needs := fmt.tprintf("over %.3g", w.lo) if w.hi >= ANY else fmt.tprintf("up to %.3g", w.hi) if w.lo <= -ANY else fmt.tprintf("%.3g to %.3g", w.lo, w.hi)
	margin = min(v - w.lo, w.hi - v)/abs(f.hi - f.lo)
	return fmt.tprintf("%s is %.2f%s (%s), where it needs %s", f.name, v, f.unit, f.from, needs), margin
}

// What the ground is at a point in the world and why, as `--why=x,z` prints it.
why_at :: proc(wx, wz: f64) {
	x, z := math.floor(wx) - f64(region.origin.x) + 0.5, math.floor(wz) - f64(region.origin.y) + 0.5
	p := point_at(x, z, 1)
	fmt.printfln("at %.0f, %.0f: ground %.1f m over the sea, %.0f° steep, wetness %.2f", wx, wz, p.h, math.to_degrees(math.atan(p.steep)), FIELDS[.Wetness].at(&p))
	win := surface_row(&p)
	_, m := surface_at(x, z, 1)
	r := SURFACES[win]
	fmt.printf("the ground is %s%s: %s", r.name, fmt.tprintf(" (%v)", m) if r.brings == .Air else "", r.why)
	if len(r.host) == 0 do fmt.print(", wherever no row before it holds")
	near: [2]struct { words: string, margin: f32 } = {{"", ANY}, {"", ANY}}   // the two windows nearest their edges
	for w in r.host {
		words, margin := window_words(w, &p)
		if margin < near[0].margin do near[0], near[1] = {words, margin}, near[0]
		else if margin < near[1].margin do near[1] = {words, margin}
	}
	for n, i in near do if n.words != "" do fmt.print(";" if i > 0 else ". Here", n.words)
	fmt.println(".")
	for after in SURFACES[win + 1:] do if host(after.host, &p) > 0 {
		fmt.printfln("were it not, it would be %s: %s", after.name, after.why)
		break
	}
	// The nearest miss: of the rows that do not hold, the one whose worst window is nearest to
	// holding, if within the field's span. A field at its very limit, as no gravel or no fallen
	// rock, is absent rather than near.
	miss, miss_words, miss_by := -1, "", f32(-1)
	for row, i in SURFACES do if i != win {
		worst, worst_by := "", f32(ANY)
		for w in row.host {
			words, margin := window_words(w, &p)
			if margin < worst_by do worst, worst_by = words, margin
		}
		if worst_by < 0 && worst_by > miss_by do miss, miss_words, miss_by = i, worst, worst_by
	}
	if miss >= 0 do fmt.printfln("nearest miss: %s, ruled out because %s", SURFACES[miss].name, miss_words)
	wet, patch, high := forest_terms(x, z)
	woods := forest_at(x, z)
	fmt.printfln("woods %.2f of the thickest, a sum for now that the plant communities will replace: 0.12 everywhere, + %.2f for wetness %.2f, %+.2f for the woods' own patches, - %.2f for the land standing %.0f m high (thinning from 170 m, none from 320 m)",
		woods, 1.3*wet, wet, 0.4*patch, smoothstep(170, 320, high), high)
	if m == .Grass do fmt.printfln("a tree stands in about %.0f%% of the 6 m squares here", 92*woods)
	else do fmt.printfln("no tree stands here, since trees grow only on grass; on grass about %.0f%% of the 6 m squares would have one", 92*woods)
}
