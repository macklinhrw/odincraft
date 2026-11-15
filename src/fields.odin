package main

import "core:fmt"
import fnv "core:hash"
import "core:math"

// The fields every catalogue's rows are written in (docs/foundations/kinds-and-places.md, D2
// and D3). A field has a value everywhere, in its own unit, read at a point at a cell size.
// The map paints any of them (--overlay=), and --why= reports them. A condition of a new shape
// becomes a new field here, never new code in a row.
Field :: enum u8 {
	// on the land's 16 m grid
	Wetness, Livable, Slope, Drainage, Uplift, Rock, Facing, Humped, Inland, Sunlight, Exposure, Cold, Soil_Depth, Soil, Plants, Volcanic, Woods,
	At_Limit, Cap, Valley, Slid, Disturbed, Stand_Age, Swell, Headland, Contact, Strength, Crossing, Risen, Trail, Lifted, Discharge, Surf, Sand_Kept, Washed, Canopy, Lift, Barrier,
	// from the world's plates at the point's place in the world (archipelago.odin): a fixed stand-in, which step 22's plate story replaces with the same fields
	Setting, Front, Trench, Track, Age, Rising, Depth,
	// from the ground the generator makes at the point
	Height, Steepness, Gravel, Fallen, Beach, Too_Steep, Under_Water, Over_Water,
}
GROUND_FIELDS :: bit_set[Field]{.Washed, .Height, .Steepness, .Gravel, .Fallen, .Beach, .Too_Steep, .Under_Water, .Over_Water}

// What a field is read from: a point, and the ground made there when the field needs it.
Point :: struct {
	using g:    Ground,
	x, z, cell: f64,
	vary:       f32,   // broad patches broken at their edges, about -1.7 to 1.7, that move what soil holds
}

point_at :: proc(x, z, cell: f64) -> (p: Point) {
	p.g, p.x, p.z, p.cell = ground(x, z, cell), x, z, cell
	p.vary = fbm(x, z, 120, cell, 2, seed + 100) + 0.7*fbm(x, z, 22, cell, 2, seed + 101)
	return
}

// A field on the land's grid at a point: smooth between cells, or a cell's own value when asked at
// the grid's own size, as the race is.
grid_at :: proc(v: []f32, p: ^Point) -> f32 {
	return v[land_cell(p.x, p.z)] if p.cell == LAND_CELL else land_at(v, land.n, p.x, p.z)
}

Field_Info :: struct {
	name, unit, from: string,   // `from` reads after the value: "0.4 m under the line the waves..."
	at:      proc(p: ^Point) -> f32,
	lo, hi:  f32,               // the span the map paints from one colour to the other; also the scale of a near miss
	paint:   enum u8 { Ramp, Log, Kinds, Wheel, Soils, Plants },   // Log: lo and hi are powers of ten; Kinds: a material; Wheel: a bearing, grey where flat; Soils, Plants: a row's colour
	from_colour, to_colour: [3]f32,
}

FIELDS := [Field]Field_Info{
	.Wetness   = {"wetness", "", "0 on ridges to 1 in valley floors, by the land draining through", proc(p: ^Point) -> f32 { return grid_at(land.wet, p) }, 0, 1, .Ramp, {0.90, 0.80, 0.50}, {0.05, 0.45, 0.40}},
	.Livable   = {"livable", "", "1 on ground a person could live on: under 20°, 2 m over the sea, a hectare or more", proc(p: ^Point) -> f32 { return land.live[land_cell(p.x, p.z)] }, 0, 1, .Ramp, {0.55, 0.55, 0.55}, {1.00, 0.55, 0.05}},
	.Slope     = {"slope", "", "rise over run of the formed land, smooth over 16 m", proc(p: ^Point) -> f32 { return grid_at(land.slope, p) }, 0, 1.2, .Ramp, {0.95, 0.95, 0.90}, {0.65, 0.05, 0.05}},
	.Drainage  = {"drainage", " m²", "land draining through", proc(p: ^Point) -> f32 { return land.grid.area[land_cell(p.x, p.z)] }, 2.4, 7.4, .Log, {0.95, 0.95, 0.90}, {0.05, 0.10, 0.45}},
	.Uplift    = {"uplift", "", "share of the island's fastest rise", proc(p: ^Point) -> f32 { return land.grid.uplift[land_cell(p.x, p.z)]/f32(region.shape.rate) }, 0, 1.3, .Ramp, {0.20, 0.25, 0.45}, {0.95, 0.85, 0.30}},
	.Rock      = {"rock", "", "the bed at the formed land's surface, as a material", proc(p: ^Point) -> f32 { return f32(rock(p.x, f64(land_at(land.z[0], land.n, p.x, p.z)) - 0.5, p.z, p.cell)) }, 0, 0, .Kinds, {}, {}},
	.Facing    = {"facing", "°", "the bearing the ground falls toward, from north", proc(p: ^Point) -> f32 { return land.facing[land_cell(p.x, p.z)] }, 0, 360, .Wheel, {}, {}},
	.Humped    = {"humped", " m", "over the mean ground 208 m round; under 0, a hollow", proc(p: ^Point) -> f32 { return grid_at(land.hump, p) }, -15, 15, .Ramp, {0.10, 0.35, 0.90}, {1.00, 0.75, 0.15}},
	.Inland    = {"inland", " m", "to the nearest sea", proc(p: ^Point) -> f32 { return grid_at(land.inland, p) }, 0, 2000, .Ramp, {0.95, 0.95, 0.85}, {0.25, 0.10, 0.45}},
	.Sunlight  = {"sunlight", "", "sunlight in a year against flat ground", proc(p: ^Point) -> f32 { return grid_at(land.sun, p) }, 0.6, 1.1, .Ramp, {0.20, 0.30, 0.80}, {1.00, 0.80, 0.15}},
	.Exposure  = {"exposure", "", "0 sheltered to 1 on a crest or shore open to the wind and salt", proc(p: ^Point) -> f32 { return land.exposed[land_cell(p.x, p.z)] }, 0, 1, .Ramp, {0.10, 0.40, 0.20}, {0.95, 0.90, 0.85}},
	.Cold      = {"cold", " m", "over the stream or shore the ground drains to, where a still night's cold air pools", proc(p: ^Point) -> f32 { return grid_at(land.above, p) }, 50, 0, .Ramp, {0.95, 0.92, 0.85}, {0.10, 0.25, 0.70}},   // painted as a pool 50 m deep
	.Soil_Depth = {"soil-depth", " m", "deeper in hollows, where water gathers, beside streams and over weak rock, thinner on humps and steep ground", proc(p: ^Point) -> f32 { return grid_at(land.soil, p) }, 0, 3, .Ramp, {0.80, 0.80, 0.78}, {0.30, 0.18, 0.08}},
	.Soil      = {"soil", "", "the kind of soil (SOILS)", proc(p: ^Point) -> f32 { row, _ := soil_at(p); return f32(row) }, 0, 0, .Soils, {}, {}},
	.Plants    = {"plants", "", "the plant community that won the race for the ground (COMMUNITIES)", proc(p: ^Point) -> f32 { k, _ := community_at(p.x, p.z, p.cell); return f32(k) }, 0, 0, .Plants, {}, {}},
	.Volcanic  = {"volcanic", "", "1 where the rock is lava and ash laid by the island's vents", proc(p: ^Point) -> f32 { return 1 if region.story.drape else 0 }, 0, 1, .Ramp, {0.90, 0.88, 0.80}, {0.25, 0.15, 0.12}},
	.Woods     = {"woods", "", "share of the places in the canopy a tree takes, which the plant community sets", proc(p: ^Point) -> f32 { k, _ := community_at(p.x, p.z, p.cell); return COMMUNITIES[k].density }, 0, 1, .Ramp, {0.90, 0.85, 0.65}, {0.05, 0.30, 0.08}},
	.At_Limit  = {"at-limit", "", "steepness against the steepest the rock at the surface holds", proc(p: ^Point) -> f32 { c := land_cell(p.x, p.z); return grid_at(land.slope, p)/rocks.law[rock_in(land.grid.z[c] - 2, land.grid.base[c], ROCK_SIM)].limit }, 0, 1.2, .Ramp, {0.95, 0.95, 0.90}, {0.65, 0.05, 0.05}},
	.Cap       = {"cap", "", "how much stronger a bed in the top 50 m is than the weakest bed under it, in strength from 0 to 1", proc(p: ^Point) -> f32 { s, _, _, _ := cap_at(land_cell(p.x, p.z)); return s }, 0, 0.6, .Ramp, {0.95, 0.95, 0.90}, {0.30, 0.20, 0.60}},
	.Valley    = {"valley", " m²", "drained by the stream the ground drains to", proc(p: ^Point) -> f32 { return land.valley[land_cell(p.x, p.z)] }, 4, 7.4, .Log, {0.95, 0.95, 0.90}, {0.05, 0.10, 0.45}},
	.Slid      = {"slid", " m", "of a slide's debris laid here, or under 0, of ground it took away", proc(p: ^Point) -> f32 { return grid_at(land.slid, p) }, -30, 30, .Ramp, {0.30, 0.45, 0.85}, {0.85, 0.50, 0.15}},
	.Disturbed = {"disturbed", " years", "since the ground was laid bare, where an event records it, else 100,000", proc(p: ^Point) -> f32 { return region.features[landslide.feature].age if abs(grid_at(land.slid, p)) > 0.5 else 1e5 }, 1, 5, .Log, {0.95, 0.60, 0.20}, {0.10, 0.35, 0.15}},
	.Stand_Age = {"stand-age", " years", "since a storm or a slide last threw the canopy of the stand, which sets how far apart its trees stand and how tall they are", proc(p: ^Point) -> f32 { return land.age[land_cell(p.x, p.z)] }, 1, 3, .Log, {0.95, 0.80, 0.25}, {0.05, 0.25, 0.10}},
	.Swell     = {"swell", "", "0 on a sheltered shore to 1 on one open all round and toward the swell, as the waves cut it; 0 off the shore", proc(p: ^Point) -> f32 { return land.swell[land_cell(p.x, p.z)] }, 0, 0.5, .Ramp, {0.95, 0.95, 0.90}, {0.10, 0.25, 0.70}},
	.Headland  = {"headland", "", "share of sea within 48 m", proc(p: ^Point) -> f32 { return headland(land_cell(p.x, p.z)) }, 0, 1, .Ramp, {0.95, 0.95, 0.90}, {0.10, 0.25, 0.70}},
	.Contact   = {"contact", "", "how much stronger a bed is than the one under it, where the two meet on the hillside within 8 m of the ground, in strength from 0 to 1", proc(p: ^Point) -> f32 { s, _ := contact_at(land_cell(p.x, p.z)); return s }, 0, 0.6, .Ramp, {0.95, 0.95, 0.90}, {0.30, 0.20, 0.60}},
	.Strength  = {"strength", "", "of the rock at the surface, from 0 for the weakest to 1 (rock.odin)", proc(p: ^Point) -> f32 { c := land_cell(p.x, p.z); return MATERIALS[rock_in(land.grid.z[c] - 2, land.grid.base[c], ROCK_SIM)].strength }, 0, 1, .Ramp, {0.95, 0.95, 0.90}, {0.35, 0.20, 0.10}},
	.Crossing  = {"crossing", " s/m", "for a person to walk a metre of this ground straight up its slope, wading any stream across the cell (pace, trails.odin)", proc(p: ^Point) -> f32 { c := land_cell(p.x, p.z); return pace(c, land.slope[c], land.slope[c]) + trails.wade[c]/LAND_CELL }, -0.3, 1.7, .Log, {0.95, 0.95, 0.90}, {0.45, 0.05, 0.30}},
	.Risen     = {"risen", " m", "the sea has risen over the island since it stood lowest, when it may have been joined to larger land", proc(p: ^Point) -> f32 { return risen() }, 0, 120, .Ramp, {0.90, 0.88, 0.80}, {0.10, 0.30, 0.70}},
	.Trail     = {"trail", " m", "from the middle of the nearest animal trail, less half of any cell over a metre; far, at cells over 2 m", proc(p: ^Point) -> f32 { return trail_near(p.x, p.z) - 0.5*f32(p.cell - 1) if p.cell <= 2 else ANY }, 0, 20, .Ramp, {0.60, 0.12, 0.05}, {0.95, 0.95, 0.90}},
	.Lifted    = {"lifted", " m", "the wind off the sea has been raised to by the ground it crossed; cloud caps the ground where this passes the cloud base", proc(p: ^Point) -> f32 { return grid_at(land.lifted, p) }, 0, 400, .Ramp, {0.20, 0.30, 0.55}, {0.95, 0.95, 0.95}},
	.Discharge = {"discharge", " m³/s", "the mean flow of the stream the ground drains to, the share of the rain on the land it drains that runs off", proc(p: ^Point) -> f32 { return discharge(land.valley[land_cell(p.x, p.z)]) }, -3, 0, .Log, {0.95, 0.95, 0.90}, {0.05, 0.10, 0.45}},
	.Surf      = {"surf", "", "how open the nearest shore is to the swell, within 48 m of it on land or at sea; 0 farther", proc(p: ^Point) -> f32 { return grid_at(land.surf, p) }, 0, 0.5, .Ramp, {0.95, 0.95, 0.90}, {0.10, 0.25, 0.70}},
	.Sand_Kept = {"sand-kept", "", "the sand the rivers bring the shore, less what the swell carries off; over 0 a beach of sand stays", proc(p: ^Point) -> f32 { return sand_kept(p.x, p.z) }, -1, 1, .Ramp, {0.40, 0.40, 0.45}, {0.95, 0.85, 0.50}},
	.Washed    = {"washed", " m", "under the height the waves wash over a shore, 1 m and 8 m more for each unit of surf", proc(p: ^Point) -> f32 { return 1 + 8*grid_at(land.surf, p) - p.h }, -3, 3, .Ramp, {0.30, 0.55, 0.30}, {0.55, 0.50, 0.45}},
	.Canopy    = {"canopy", "", "share of the sky the stand's crowns hide from the ground: little in the open and in a fresh gap, nearly all under a closed wood", proc(p: ^Point) -> f32 { return canopy_at(p.x, p.z) }, 0, 1, .Ramp, {0.95, 0.90, 0.60}, {0.05, 0.25, 0.08}},
	.Lift      = {"lift", " m/s", "the wind of 8 m/s off the sea is turned upward by the ground facing it, which a soaring bird rides: the wind's speed times the sine of the slope times the cosine between the way the ground faces and the way the wind comes from", proc(p: ^Point) -> f32 { c := land_cell(p.x, p.z); s := land.slope[c]; return SKY.wind*s/math.sqrt(1 + s*s)*math.cos(math.to_radians(land.facing[c] - f32(region.shape.swell))) if !land.grid.sea[c] else 0 }, 0, 3, .Ramp, {0.95, 0.95, 0.90}, {0.10, 0.30, 0.75}},
	.Barrier   = {"barrier", " m", "the tallest fall between the stream the ground drains to and the sea, which a fish coming up from the sea must get past; 10,000 where no stream reaches the sea", proc(p: ^Point) -> f32 { return fauna.barrier[land_cell(p.x, p.z)] }, 0, 50, .Ramp, {0.10, 0.35, 0.80}, {0.85, 0.20, 0.10}},
	.Setting   = {"setting", "", "where the plates put the point: 0 open sea, 1 a hotspot's track, 2 forearc, 3 the arc's volcanic front, 4 back-arc, 5 shelf, 6 the continent", proc(p: ^Point) -> f32 { return f32(world_point(p).setting) }, 0, 5, .Ramp, {0.10, 0.20, 0.50}, {0.95, 0.80, 0.30}},
	.Front     = {"front", " km", "from the arc's volcanic front, where its young volcanoes stand", proc(p: ^Point) -> f32 { return world_point(p).front }, 0, 60, .Ramp, {0.85, 0.20, 0.10}, {0.95, 0.95, 0.90}},
	.Trench    = {"trench", " km", "from the trench where one plate goes down under the other, back on the plate riding over it; under 0, out on the plate going down", proc(p: ^Point) -> f32 { return world_point(p).trench }, -50, 100, .Ramp, {0.10, 0.20, 0.50}, {0.95, 0.95, 0.90}},
	.Track     = {"track", " km", "from the line the plate has carried the hotspot's islands along, on the plate going down; 10,000 elsewhere", proc(p: ^Point) -> f32 { return world_point(p).track }, 0, 40, .Ramp, {1.00, 0.60, 0.10}, {0.95, 0.95, 0.90}},
	.Age       = {"age", " Myr", "since the land was made: a young volcano's on the arc's front, as long as the plate has carried it on the hotspot's track, else the crust's", proc(p: ^Point) -> f32 { return world_point(p).age }, -1, 2.3, .Log, {0.95, 0.40, 0.10}, {0.20, 0.20, 0.45}},
	.Rising    = {"rising", " mm/yr", "the crust rises, fastest on the forearc's outer ridge; under 0 it sinks, into the trench or cooling off the hotspot", proc(p: ^Point) -> f32 { return world_point(p).rising }, -0.5, 2, .Ramp, {0.10, 0.30, 0.75}, {0.95, 0.60, 0.15}},
	.Depth     = {"depth", " m", "of the sea over the floor the plates shape: a trench, a forearc ridge, the arc's platform, a trough, a shelf rising to the continent's coast, and the swell over the hotspot; 0 on the continent", proc(p: ^Point) -> f32 { return world_point(p).depth }, 0, 7000, .Ramp, {0.60, 0.80, 0.90}, {0.05, 0.10, 0.30}},
	.Height    = {"height", " m", "of the ground over the sea", proc(p: ^Point) -> f32 { return p.h }, 0, 400, .Ramp, {0.95, 0.95, 0.90}, {0.35, 0.20, 0.10}},
	.Steepness = {"steepness", "", "rise over run of the ground in blocks, ledges and all", proc(p: ^Point) -> f32 { return p.steep }, 0, 1.5, .Ramp, {0.95, 0.95, 0.90}, {0.65, 0.05, 0.05}},
	.Gravel    = {"gravel", "", "1 on a bar or bed where a river lays gravel", proc(p: ^Point) -> f32 { return 1 if p.cover == .Gravel else 0 }, 0, 1, .Ramp, {0.95, 0.95, 0.90}, {0.10, 0.30, 0.75}},
	.Fallen    = {"fallen", " m", "depth of rock fallen from the face above", proc(p: ^Point) -> f32 { return p.fallen }, 0, 3, .Ramp, {0.95, 0.95, 0.90}, {0.40, 0.30, 0.25}},
	.Beach     = {"beach", " m", "of sand or stones the waves have laid on the shore (waters_edge, gen.odin)", proc(p: ^Point) -> f32 { return p.laid }, 0, 3, .Ramp, {0.30, 0.55, 0.30}, {0.95, 0.85, 0.50}},
	.Too_Steep = {"too-steep", "", "how much steeper than soil holds, which is a rise over run of 1.3 (52°) give or take 0.15 in patches", proc(p: ^Point) -> f32 { return p.steep - (SOIL_HOLDS + 0.15*p.vary) }, -0.5, 0.5, .Ramp, {0.30, 0.55, 0.30}, {0.55, 0.50, 0.45}},
	.Under_Water = {"under-water", " m", "of a lake's or pond's still water over the ground", proc(p: ^Point) -> f32 { l, inside, _ := lake_near(p.x, p.z); return max(l - p.h, 0) if inside else 0 }, 0, 5, .Ramp, {0.95, 0.95, 0.90}, {0.10, 0.30, 0.75}},
	.Over_Water = {"over-water", " m", "of the ground over the level of the lake or pond it lies in or beside, or of a slow stream (on ground gentler than 1 in 5) within 8 m; under 0, the depth of water over it", proc(p: ^Point) -> f32 { return over_water(p) }, -1, 3, .Ramp, {0.10, 0.30, 0.75}, {0.95, 0.95, 0.90}},
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

// The weighted race among the plant communities (kinds-and-places.md, D4). Each row scores its
// weight times its best host and draws a number u in 0..1 from smooth noise on the scale of its
// patches, keyed by its name; its key is u to the power one over its score, and the highest key
// wins. A row then wins in proportion to its score, in patches of its own size, and adding a
// row changes only the ground it wins.
race :: proc(p: ^Point) -> (first, second: Community_Kind, score: [Community_Kind]f32) {
	best := [2]f32{-1, -1}
	for row, k in COMMUNITIES {
		score[k] = 1 if len(row.hosts) == 0 else 0
		for h in row.hosts do score[k] = max(score[k], host(h, p))
		u := clamp(0.5 + fbm(p.x, p.z, f64(row.patch), LAND_CELL, 2, seed + fnv.fnv32a(transmute([]u8)row.name)), 0.001, 1)
		key := math.pow(u, 1/(row.weight*score[k])) if score[k] > 0 else 0
		if key > best[0] do first, second, best = k, first, {key, best[0]}
		else if key > best[1] do second, best[1] = k, key
	}
	return
}

// A host's windows as words, the nearest its edge first, and how far into it (or, below zero,
// short of it) the point lies.
edges :: proc(windows: []Window, p: ^Point) -> (near: [2]string, by: f32) {
	m := [2]f32{ANY, ANY}
	for w in windows {
		words, margin := window_words(w, p)
		if margin < m[0] do near, m = {words, near[0]}, {margin, m[0]}
		else if margin < m[1] do near[1], m[1] = words, margin
	}
	return near, m[0]
}

// What the ground is at a point in the world and why, as `--why=x,z` prints it.
why_at :: proc(wx, wz: f64) {
	x, z := math.floor(wx) - f64(region.origin.x) + 0.5, math.floor(wz) - f64(region.origin.y) + 0.5
	p := point_at(x, z, 1)
	fmt.printfln("at %.0f, %.0f: ground %.1f m over the sea, %.0f° steep, wetness %.2f", wx, wz, p.h, math.to_degrees(math.atan(p.steep)), FIELDS[.Wetness].at(&p))
	win := surface_row(&p)
	_, m, plants := surface_at(x, z, 1)
	r := SURFACES[win]
	fmt.printf("the ground is %s%s: %s", r.name, fmt.tprintf(" (%v)", m) if r.brings == .Air || plants != nil else "", r.why)
	if len(r.host) == 0 do fmt.print(", wherever no row before it holds")
	near, _ := edges(r.host, &p)
	for n, i in near do if n != "" do fmt.print(";" if i > 0 else ". Here", n)
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
		worst, by := edges(row.host, &p)
		if by < 0 && by > miss_by do miss, miss_words, miss_by = i, worst[0], by
	}
	if miss >= 0 do fmt.printfln("nearest miss: %s, ruled out because %s", SURFACES[miss].name, miss_words)

	// The plants: the race on the cell this point reads, its runner-up, and what held that back.
	k, cell := community_at(x, z, 1)
	q := Point{x = (f64(cell%land.n) + 0.5)*LAND_CELL - region.size/2, z = (f64(cell/land.n) + 0.5)*LAND_CELL - region.size/2, cell = LAND_CELL}
	first, second, score := race(&q)
	explain :: proc(k: Community_Kind, q: ^Point) -> (near: [2]string, by: f32) {
		by = -ANY
		for h in COMMUNITIES[k].hosts do if words, b := edges(h, q); b > by do near, by = words, b
		return
	}
	c := COMMUNITIES[k]
	fmt.printf("the plants are %s%s: %s", c.name, "" if plants != nil else ", though none grow on this spot", c.why)
	if k != first do fmt.printf(" (at the edge of %s, which won this cell)", COMMUNITIES[first].name)
	if near, _ := explain(first, &q); near[0] != "" do fmt.printf(". Here %s", near[0])
	held, _ := explain(second, &q)
	fmt.printfln(". Second in the race, %s: %s", COMMUNITIES[second].name, fmt.tprintf("held back because %s", held[0]) if score[second] < 1 else
		fmt.tprintf("it holds here as well (%.2f to %.2f by weight and host) and lost the draw", COMMUNITIES[second].weight*score[second], COMMUNITIES[first].weight*score[first]))
	fmt.printf("trees take %.0f%% of the places in the canopy:", 100*c.density)
	for share, s in c.trees do if share > 0 do fmt.printf(" %s %.0f%%", SPECIES[Tree_Kind(s)].name, 100*share)

	// The stand: how old it is and what set that, and the tree nearest the point.
	age := land.age[land_cell(x, z)]
	spacing, tall, old := stand(age)
	if abs(land.slid[land_cell(x, z)]) > 0.5 && age == region.features[landslide.feature].age do fmt.printf("\nthe stand is %s years old: the slide laid its ground bare", years(age))
	else do fmt.printf("\nthe stand is about %s years old: a typhoon threw its canopy then, as one does about once in %s years on ground as open to the wind as this", years(max(age, 1)), years(math.lerp(STANDS.interval[0], STANDS.interval[1], FIELDS[.Exposure].at(&p))))
	fmt.printf(". Its canopy trees stand about %.0f m apart and have %.0f%% of their full height", spacing, 100*tall)
	gap, fall, ago := gap_at(x, z, old)
	if gap do fmt.printf("; here is a gap where the canopy fell toward %.0f° about %.0f years ago", math.mod(math.to_degrees(math.atan2(fall.x, -fall.y)) + 360, 360), ago)
	trees := make([dynamic]Tree, context.temp_allocator)
	trees_in(i32(x) - 12, i32(z) - 12, i32(x) + 12, i32(z) + 12, &trees, true)
	t, by := Tree{}, f32(1e9)
	for o in trees do if d := math.hypot(f32(o.x) + 0.5 - f32(x), f32(o.z) + 0.5 - f32(z)); d < by do t, by = o, d
	FORMS := [Tree_Form]string{.Canopy = "in the canopy: no stronger tree stands within reach of its crown", .Between = "between the canopy trees, smaller, with a stronger one beside it", .Under = "under a taller one", .Dead = "standing dead", .Fallen = "fallen, with its root mound and pit"}
	if by < 1e9 do fmt.printf(".\nThe nearest tree, %.0f m off at %d, %d, is a %s %d m %s, %s", by, t.x + region.origin.x, t.z + region.origin.y, SPECIES[t.kind].name, t.height, "long" if t.form == .Fallen else "tall", "young growth in the gap" if gap && t.form == .Under else FORMS[t.form])
	row, depth := soil_at(&p)
	soil := SOILS[row]
	fmt.println()
	plant_words(&p, m, plants)
	fmt.printfln("the soil is %s, %.1f m deep (%s), %s: under the cover %v, then %v down to %v and the rock", soil.name, depth, FIELDS[.Soil_Depth].from, soil.why, soil.top, soil.sub, soil.foot)
	feature_words(x, z, p.h)
	hollow_words(x, z)
	stack_words(x, z)
	trail_words(x, z)
	named_words(x, z)
	creature_words(x, z)
}
