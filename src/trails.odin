package main

import "core:fmt"
import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:slice"
import "core:time"

// Trails (foundations/living-world.md, D2): one cost of crossing ground on foot, one tracer of
// least-cost routes over it, and the animal's trails it lays once the land and plants are formed. A
// walked route is cheaper to walk again, so later routes join earlier ones into a few trunks. A
// trail is a mark (foundations.md, D4): it changes what covers the ground, never its height.

// The animal (interesting-world/notes/real-animals.md). Of the reference islands only Tsushima,
// once joined to larger land while the sea stood low, has a large wild animal of its own, the sika
// deer; the oceanic ones have only what people brought. Whether an island has the animal is never
// a preference (the owner, 2026-11-12): it must have reached the island, by walking over land the
// sea bared or swimming a strait (its row in DISPERSAL, arrivals.odin), and the island must be able
// to keep it, which is `herd`, the fewest squares with ground to lie up on that hold a herd
// (Okinoshima of Tomogashima, 1.5 km², keeps one), with fresh water and ground to feed on. It lies up on dry, gentle, sheltered,
// wooded ground, a bed in each square `across` metres wide, and walks to water, to open ground to
// feed and to the next bed, at most `limit` seconds of a person's walking away.
Animal :: struct { name: string, bed, feed: []Window, across: f64, limit: f32, herd: int }
DEER := Animal{"sika deer",
	{{.Slope, -ANY, 0.36, 0.15}, {.Wetness, -ANY, 0.5, 0.2}, {.Exposure, -ANY, 0.6, 0.2}, {.Woods, 0.7, ANY, 0.2}, {.Humped, 0, ANY, 6}},
	{{.Woods, -ANY, 0.5, 0}}, 500, 2400, 6}

// How many times slower than open ground a person goes through each community's plants (guesses):
// old laurel and valley forest are halls with an open floor, the ridge wood is low and close, susuki
// and dwarf bamboo stand over a person's head. A young stand of close poles is twice as slow again.
GOING := [Community_Kind]f32{.Valley = 1.3, .Slope = 1.2, .Ridge = 2, .Windy = 3, .Coast = 1.5, .Fresh = 2.5, .Alder = 2.5, .Young = 1.8}

Trail_Segment :: struct { a, b: [2]f32, route: i32, worn: u16 }   // the first route along it, and how many
Trails :: struct {
	segments:   [dynamic]Trail_Segment,
	buckets:    [][dynamic]i32,   // as the rivers' (rivers.side to a side)
	wade, cost: []f32,            // on each land cell: seconds to wade its stream, or 0; the tracer's seconds to reach it
	worn:       []u16,            // routes through it
	first, ford, back: []i32,     // the first route through it (a feature) or -1; 1 + its ford, or 0; where the tracer came from
	seen:       []u32, stamp: u32,   // when the tracer reached it, and the tracer's count
	going:      []Going,          // on each land cell, while the trails are laid
}
TRAIL_REACH :: 4   // metres from a trail's line within which anything asks about it

// Metres the sea has risen over the island since it stood lowest.
risen :: proc() -> f32 {
	sea, low: f32
	for p in region.history do sea, low = sea + p.sea, min(low, sea + p.sea)
	return sea - low
}

// Seconds a person takes to walk a metre of a land cell at a grade along the way, on ground this
// steep: Tobler's hiking function, 0.6 s on the flat (6 km/h) and slower by e^3.5 for each unit of
// grade (Tobler 1993), a wall past 45° (`walking`), slower again on the wettest valley floors and in
// standing water, and by the plants in the way, which a worn trail has trodden down (`going`).
pace :: proc(c: int, way: f32, at: Going) -> f32 {
	s := way*at.wet*(30 if land.lake[c] > 0 else 1)
	if land.community[c] == 255 do return s
	return s*(0.7 if trails.worn[c] > 0 else at.plants)
}

walking :: proc(grade, steep: f32) -> f32 { return 0.6*math.exp(3.5*grade)*(1 + 99*smoothstep(0.84, 1, steep)) }

// What a cell's wetness and its plants, unworn, make of the pace on it, which the tracer reads for
// each cell once (`trails.going`) rather than at every step.
Going :: struct { wet, plants: f32 }
going :: proc(c: int) -> Going {
	if land.community[c] == 255 do return {1 + smoothstep(0.75, 1, land.wet[c]), 0}
	_, _, old := stand(land.age[c])
	return {1 + smoothstep(0.75, 1, land.wet[c]), GOING[Community_Kind(land.community[c])]*(2 - old)}
}

// The cheapest route from a cell to the first it wants, within the animal's limit: the cell
// reached, or -1, with `back` leading home.
End :: enum u8 { Drink, Feed, Bed }
trace :: proc(from, to: int, want: End, feeds: []bool) -> int {
	g, n := land.grid, land.n
	trails.stamp += 1
	heap_clear(&g.heap)
	trails.cost[from], trails.back[from], trails.seen[from] = 0, -1, trails.stamp
	heap_push(&g.heap, {0, i32(from)})
	for g.heap.n > 0 {
		top := heap_pop(&g.heap)
		c := int(top.c)
		if top.h > trails.cost[c] do continue
		if top.h > DEER.limit do break
		if want == .Drink && (trails.wade[c] > 0 || land.lake[c] > 0) || want == .Feed && feeds[c] || c == to do return c
		for o, k in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			b := y*n + x
			if x < 1 || y < 1 || x >= n - 1 || y >= n - 1 || g.sea[b] do continue
			if trails.seen[b] == trails.stamp && trails.cost[b] <= top.h do continue   // reached already for no more than a step from here could cost
			step, wade, steep := g.d, trails.wade[b], max(land.slope[c], land.slope[b])
			if k >= 4 {   // a diagonal step also crosses its two corners: a cliff there, or a stream it must step into
				if trails.wade[c + o.x] > 0 && trails.wade[c + o.y*n] > 0 do continue
				step *= math.SQRT_TWO
				steep = max(steep, land.slope[c + o.x], land.slope[c + o.y*n])
			}
			way := walking(abs(g.z[b] - g.z[c])/step, steep)
			t := top.h + step*(pace(c, way, trails.going[c]) + pace(b, way, trails.going[b]))/2 + wade
			if trails.seen[b] != trails.stamp || t < trails.cost[b] {
				trails.cost[b], trails.back[b], trails.seen[b] = t, i32(c), trails.stamp
				heap_push(&g.heap, {t, i32(b)})
			}
		}
	}
	return -1
}

// Where a cell's node lies, as the rivers have it, or its ford.
node :: proc(c: int) -> [2]f32 {
	g := land.grid
	if k := trails.ford[c]; k > 0 do return {f32(region.features[k - 1].at.x), f32(region.features[k - 1].at.y)}
	return ([2]f32{f32(c%g.n), f32(c/g.n)} + 0.5 + g.jitter[c])*g.d - f32(region.size/2)
}

// Lay the animal's trails, if the island has the animal. Called once, after the plants.
trails_make :: proc() {
	started := time.now()
	g, n := land.grid, land.n
	trails.wade, trails.cost, trails.worn, trails.first, trails.ford, trails.back = make([]f32, n*n), make([]f32, n*n), make([]u16, n*n), make([]i32, n*n), make([]i32, n*n), make([]i32, n*n)
	trails.seen, trails.buckets = make([]u32, n*n), make([][dynamic]i32, rivers.side*rivers.side)
	slice.fill(trails.first, -1)
	// A stream costs the time to wade it: across its width, much slower the deeper, and out up its
	// banks. Just above a drop it runs over a lip a hand deep, where it is cheapest: a ford.
	lips := make(map[int][2]f32, 64, context.temp_allocator)
	for s in rivers.segments do for t in ([5]f32{0, 0.25, 0.5, 0.75, 1}) {
		p, half := math.lerp(s.a, s.b, t), math.lerp(s.half_a, s.half_b, t)
		c := land_cell(f64(p.x), f64(p.y))
		deep := f32(0.15) if s.drop > 0 && t == 1 else river_depth(half)
		if deep < 0.2 do lips[c] = p
		if w := 2*half*(1 + 100*deep*deep) + 4; !g.sea[c] do trails.wade[c] = w if trails.wade[c] == 0 else min(trails.wade[c], w)
	}
	if !came(DEER.name).reached {
		fmt.printfln("no large animal: the %s did not reach the island: %s", DEER.name, arrival_words(DEER.name))
		return
	}

	// A bed in each square where its host holds best, the seed breaking ties; feeding ground wherever its host holds.
	side := int(region.size/DEER.across) + 1
	beds, best := make([]int, side*side, context.temp_allocator), make([]f32, side*side, context.temp_allocator)
	feeds := make([]bool, n*n, context.temp_allocator)
	slice.fill(beds, -1)
	for ci in g.order {
		c := int(ci)
		p := Point{x = middle_of(g, c).x, z = middle_of(g, c).y, cell = LAND_CELL}
		feeds[c] = host(DEER.feed, &p) > 0
		k := int((p.z + region.size/2)/DEER.across)*side + int((p.x + region.size/2)/DEER.across)
		if s := host(DEER.bed, &p)*(0.8 + 0.4*hash01(i32(c), 0, seed + 800)); s > 0.3 && s > best[k] do beds[k], best[k] = c, s
	}
	// Reached is not kept: the island must hold a herd.
	lie, feed, water := 0, 0, 0
	for b in beds do lie += int(b >= 0)
	for ci in g.order {
		feed += int(feeds[ci])
		water += int(trails.wade[ci] > 0 || land.lake[ci] > 0)
	}
	if lie < DEER.herd || feed == 0 || water == 0 {
		fmt.printfln("no large animal: %s, but the island cannot keep a herd: %s", arrival_words(DEER.name),
			"it has no fresh water" if water == 0 else "it has no open ground to feed on" if feed == 0 else fmt.tprintf("it has sheltered wood to lie up in in only %d squares of %.0f m, and a herd needs %d", lie, DEER.across, DEER.herd))
		return
	}

	// Each bed's routes: to water, to feed and to the bed beside it to the east or the south, as the
	// seed has it, each laid as it is found so that the next is drawn to it. A stream crossed on the
	// way is a ford.
	trails.going = make([]Going, n*n, context.temp_allocator)
	defer trails.going = nil
	shared(len(g.order), 2048, g, proc(g: ^Grid, lo, hi: int) { for c in g.order[lo:hi] do trails.going[c] = going(int(c)) })
	links := make([]u8, n*n, context.temp_allocator)   // bit k: a trail runs to the neighbour OFFSETS[k]
	path := make([dynamic]int, context.temp_allocator)
	age := region.history[len(region.history) - 1].steps*region.history[len(region.history) - 1].years   // since the sea last moved: a guess
	routes, fords := 0, 0
	for b, k in beds do if b >= 0 do for want in End {
		to := -1
		if want == .Bed {
			east := int(hash(i32(k), 0, seed + 801) & 1)
			x, y := k%side + east, k/side + 1 - east
			if x >= side || y >= side || beds[y*side + x] < 0 do continue
			to = beds[y*side + x]
		}
		end := trace(b, to, want, feeds)
		if end < 0 do continue
		clear(&path)
		for c := end; c >= 0; c = int(trails.back[c]) do append(&path, c)
		f := Feature{kind = .Trail, at = middle_of(g, b), to = middle_of(g, end), level = -1e9, age = age, cause = -1}
		for c, j in path {
			f.level = max(f.level, g.z[c])   // its highest point
			if abs(land.slid[c]) > 0.5 do f.age = min(f.age, region.features[landslide.feature].age)
			if j == 0 do continue
			f.size += span(g, c, path[j - 1])
			for o, d in OFFSETS do if path[j - 1] == c + o.y*n + o.x do links[c] |= 1 << u8(d)
			for o, d in OFFSETS do if c == path[j - 1] + o.y*n + o.x do links[path[j - 1]] |= 1 << u8(d)
		}
		f.measured = {{"minutes for a person to walk it", trails.cost[end]/60}, {"metres from its lower end to its highest point", f.level - min(g.z[b], g.z[end])}, {"routes before it", f32(routes)}}
		id := len(region.features)
		append(&region.features, f)
		routes += 1
		for c, j in path {
			trails.worn[c] += 1
			if trails.first[c] < 0 do trails.first[c] = i32(id)
			if j == 0 || j == len(path) - 1 || trails.wade[c] == 0 || trails.ford[c] > 0 do continue
			at, lip := lips[c]   // the trail crosses on the lip, or where the tracer took it
			if !lip do at = node(c)
			r, _ := river_near(at.x, at.y)
			append(&region.features, Feature{kind = .Ford, at = {f64(at.x), f64(at.y)}, reach = r.half, size = 2*r.half, level = r.bank - FREEBOARD, age = age, cause = id,
				measured = {{"seconds to wade it", trails.wade[c]}, {"metres deep where it is crossed", math.sqrt(max((trails.wade[c] - 4)/(2*r.half) - 1, 0)/100)}, {"km² drained above it", g.area[c]/1e6}}})
			trails.ford[c] = i32(len(region.features))
			fords += 1
		}
	}

	// The network as lines: chains of cells between the places where trails meet, end or ford, eased
	// and rounded at their corners as a river is, so they keep near the cells the routes chose.
	walked := slice.clone(links, context.temp_allocator)
	OPPOSITE, offsets := [8]u8{1, 0, 3, 2, 7, 6, 5, 4}, OFFSETS
	length: f32
	for pass in 0..<2 do for start in 0..<n*n do for walked[start] != 0 && (pass == 1 || bits.count_ones(links[start]) != 2 || trails.ford[start] > 0) {
		pts := make([dynamic][2]f32, context.temp_allocator)
		append(&pts, node(start))
		c, least := start, start   // the cell along it fewest routes have worn
		for {
			d := bits.count_trailing_zeros(walked[c])
			next := c + offsets[d].y*n + offsets[d].x
			walked[c] &~= 1 << d
			walked[next] &~= 1 << OPPOSITE[d]
			append(&pts, node(next))
			c = next
			if trails.worn[c] < trails.worn[least] do least = c
			if bits.count_ones(links[c]) != 2 || walked[c] == 0 || trails.ford[c] > 0 do break   // a ford stays where it is
		}
		for _ in 0..<2 {
			before := pts[0]
			for i in 1..<len(pts) - 1 do before, pts[i] = pts[i], (before + 2*pts[i] + pts[i + 1])/4
		}
		for _ in 0..<2 {
			out := make([dynamic][2]f32, 0, 2*len(pts), context.temp_allocator)
			append(&out, pts[0])
			for i in 0..<len(pts) - 1 do append(&out, math.lerp(pts[i], pts[i + 1], f32(0.25)), math.lerp(pts[i], pts[i + 1], f32(0.75)))
			append(&out, pts[len(pts) - 1])
			pts = out
		}
		for i in 0..<len(pts) - 1 {
			a, b := pts[i], pts[i + 1]
			length += linalg.length(b - a)
			append(&trails.segments, Trail_Segment{a, b, trails.first[least], trails.worn[least]})
			lo, hi := linalg.min(a, b) - TRAIL_REACH + f32(region.size/2), linalg.max(a, b) + TRAIL_REACH + f32(region.size/2)
			for bz in max(int(lo.y)/BUCKET, 0)..=min(int(hi.y)/BUCKET, rivers.side - 1) do for bx in max(int(lo.x)/BUCKET, 0)..=min(int(hi.x)/BUCKET, rivers.side - 1) {
				append(&trails.buckets[bz*rivers.side + bx], i32(len(trails.segments) - 1))
			}
		}
	}
	fmt.printfln("%s: %d routes from %d beds traced in %.0f ms, %.1f km of trail, %.0f m in each km² of land, %d fords", DEER.name, routes, len(beds) - slice.count(beds, -1),
		time.duration_milliseconds(time.since(started)), length/1000, length/(f32(len(g.order))*g.d*g.d/1e6), fords)
}

// Metres to the middle of the nearest trail, if one is within reach, and its segment.
trail_near :: proc(x, z: f64, seg: ^i32 = nil) -> (d: f32) {
	d = ANY
	rim := region.size/2
	bx, bz := int(x + rim)/BUCKET, int(z + rim)/BUCKET
	if len(trails.segments) == 0 || x < -rim || z < -rim || bx >= rivers.side || bz >= rivers.side do return
	p := [2]f32{f32(x), f32(z)}
	for id in trails.buckets[bz*rivers.side + bx] {
		ab, ap := trails.segments[id].b - trails.segments[id].a, p - trails.segments[id].a
		if e := linalg.length(ap - ab*clamp(linalg.dot(ap, ab)/max(linalg.dot(ab, ab), 1e-6), 0, 1)); e < d {
			d = e
			if seg != nil do seg^ = id
		}
	}
	return
}

// What lies at one end of a trail, in words.
place_words :: proc(at: [2]f64) -> string {
	c := land_cell(at.x, at.y)
	if land.lake[c] > 0 do return "the lake"
	if trails.ford[c] > 0 do return "the ford"
	if trails.wade[c] > 0 do return "the stream"
	k := Community_Kind(land.community[c])
	return fmt.tprintf("the %s %s", COMMUNITIES[k].name, "on a spur" if land.hump[c] > 4 else "in a hollow" if land.hump[c] < -4 else "on a slope")
}

// The trail or ford at a point, in a sentence, as --why prints it.
trail_words :: proc(x, z: f64) {
	if k := trails.ford[land_cell(x, z)]; k > 0 {
		f := region.features[k - 1]
		fmt.printfln("%s a stream %.0f m wide draining %.1f km², %.0f m off at %.0f, %.0f: it is %.2f m deep there and takes a person %.0f s to wade. %d deer trails meet at it; the first came from %s.", "at a ford, where deer cross" if f.measured[1].value < 0.6 else "where deer swim",
			f.size, f.measured[2].value, math.hypot(f.at.x - x, f.at.y - z), f.at.x + f64(region.origin.x), f.at.y + f64(region.origin.y), f.measured[1].value, f.measured[0].value, trails.worn[land_cell(x, z)], place_words(region.features[f.cause].at))
	}
	seg := i32(-1)
	d := trail_near(x, z, &seg)
	if seg < 0 || d > TRAIL_REACH do return
	s := trails.segments[seg]
	f := region.features[s.route]
	fmt.printfln("%.1f m from the middle of a %s trail worn by %d route%s, about %s years old. The first was from %s at %.0f m to %s at %.0f m, %.0f m off: %.0f m long, %.0f minutes for a person, over a high point of %.0f m.", d, DEER.name,
		s.worn, "" if s.worn == 1 else "s", years(f.age), place_words(f.at), land_at(land.z[0], land.n, f.at.x, f.at.y), place_words(f.to), land_at(land.z[0], land.n, f.to.x, f.to.y), math.hypot(f.to.x - x, f.to.y - z), f.size, f.measured[0].value, f.level)
}
