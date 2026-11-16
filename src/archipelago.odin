package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// The islands near the start, and the continent they lie off, read from the world's history
// (plates.odin, docs/foundations/plates.md). The history moves plates over a whole planet for 350
// million years; the known world, 1,000 km across, is what it left at one place (known.odin): the
// height of the ground, how far each place lies from a trench and its volcanic front, how old its
// crust is, how fast it rises or sinks, and its volcanoes. The world's fields are read from that
// (`world_at`, read as `setting`, `front`, `trench`, `track`, `age`, `rising` and `depth` in
// FIELDS). Islands stand where the rows of SITES say the history makes them, on the volcanic front,
// across the forearc, on its old volcanoes and where its ground stands over the sea, each the kind
// whose host it holds best (`hosts` in KINDS), so a kind is the name of a kind of history. Land
// larger than a region is the continent's, a record not yet formed (step 21). Nothing here is
// formed: --archipelago= forms every island to draw the group.

// One island of the archipelago: what the world knows of it before it is formed.
Island :: struct {
	id:      int,      // 0 is the start island, today's island at the origin
	origin:  [2]i32,   // where its region's middle lies in the world, metres (Region.origin)
	size:    f64,      // its region's side, metres (Region.size)
	kind:    int,      // its row in KINDS
	seed:    u32,      // the seed its region is formed from: the start island's is the world's seed, the others the world's seed hashed with id
	setting: Setting,  // where the plates put it
	age:     f32,      // Myr since its land was made, the world's `age` at its middle
}
archipelago: [dynamic]Island   // made by archipelago_make(), from the world's seed

// The land larger than a region that the islands lie off: what the world knows of it before any of
// it can be formed (step 21 looks for how).
Continent :: struct {
	coast:  [dynamic][2]f64,   // the coast nearest the start, in the world, metres: a closed loop, along the known world's edge where the land runs past it
	crest:  [dynamic][2]f64,   // the line of the range behind it: the highest ground within 60 km of each stretch of coast
	height: f32,               // metres, the range's crest, its median
}
continent: Continent   // made by archipelago_make()

Setting :: enum u8 { Open_Sea, Hotspot, Forearc, Arc, Back_Arc, Shelf, Continent }
SETTINGS := [Setting]string{.Open_Sea = "open sea", .Hotspot = "hotspot", .Forearc = "forearc", .Arc = "arc", .Back_Arc = "back-arc", .Shelf = "shelf", .Continent = "continent"}

World_Point :: struct {
	setting: Setting,
	front, trench, track, age, rising, depth, inland: f32,   // km, km, km, Myr, mm/yr, m, km behind the coast of land larger than a region
	crust, across: f32,   // km of crust; the share of the way from the trench back to the volcanic front
	vent:    f32,         // Myr since the volcano whose foot the point lies on began to build; 1e4 on none
}

// Where the start stands in the known world, and what is drawn for the whole world from its seed.
World_Frame :: struct {
	start:  [2]f32,   // km east and south of the known world's middle: the start island's middle,
	origin: [2]f64,   // which lies here in the game's world, metres
	wind:   f64,      // the bearing every island's swell and wind come from, degrees from north
}
world_frame: World_Frame

// How near a point of the known world lies to the crest of the forearc's outer high, which the
// regional history raises (OUTER, plates.odin), from 0 to 1.
outer_high :: proc(k: Known_Sample) -> f32 {
	if k.front >= 0 || k.front > 1e3 do return 0
	return math.exp(-math.pow(((k.front + k.setback)/k.setback - OUTER.at)/OUTER.width, 2))
}

NEAR_SIDE :: 200_000   // metres, the side of the square round the start the islands are placed in: an arc's front and much of its forearc, which lie 170 to 260 km apart on real arcs

// Where islands stand, as rows: what in the history makes them, and how far apart they stand, km.
// Every site takes the kind whose host it holds best; a site no kind holds is left out.
Site_Line :: enum u8 {
	Front,     // on one of the history's live vents on the volcanic front, whose top stands within 200 m of the sea
	Forearc,   // on the forearc's outer high (OUTER), within a half of its width of its crest
	Shelf,     // on continental crust the sea stands less than 300 m over: a continent's stretched margin or a piece rifted off it
	Vent,      // on one of the history's dead volcanoes whose top still stands over the sea
	Land,      // on one of the history's own islands, where its ground stands over the sea in a mass smaller than LARGE
}
Site_Row :: struct { name: string, line: Site_Line, apart: [2]f32 }
SITES := [?]Site_Row{
	{"on a live vent of the volcanic front", .Front, {15, 15}},   // the regional history puts its vents 20 to 60 km apart (VENT_APART, plates.odin)
	{"on the forearc's outer high", .Forearc, {50, 90}},   // the Bonin islands' groups, 50 to 70 km apart; Kikaijima stands alone
	{"on a shelf", .Shelf, {30, 60}},   // Tsushima, Iki and the Gotō islands, 30 to 70 km apart on theirs
	{"on an old volcano", .Vent, {20, 20}},
	{"on the history's own land", .Land, {12, 12}},
}

// Island sizes follow Korčák's law: the number with more than an area A falls as A to the -0.65, half
// the fractal dimension of a coast (a guess, not measured on real groups). Only regions 8 to 16 km
// across form islands that read as their kind, so the law is cut there.
KORCAK :: 0.65
SIDES  :: [2]f64{8192, 16384}

// A point in the game's world as km in the known world.
known_point :: proc(x, z: f64) -> [2]f32 {
	return world_frame.start + [2]f32{f32(x - world_frame.origin.x), f32(z - world_frame.origin.y)}/1000
}

// The world's fields at a point in the world. A host reads several at one point, so the last point
// read on each thread is kept.
world_at :: proc(x, z: f64) -> (w: World_Point) {
	@(thread_local) last: struct { x, z: f64, start: [2]f32, w: World_Point, ok: bool }
	if last.ok && last.x == x && last.z == z && last.start == world_frame.start do return last.w
	defer last = {x, z, world_frame.start, w, true}
	at := known_point(x, z)
	k, inland := known_at(at)
	over := k.front < 1e3   // on a plate over a sinking slab, within reach of its trench
	w.front = abs(k.front) if over else 1e4
	w.trench = k.front + k.setback if over else -k.slab if k.slab < 1e3 else 1e4
	w.track = track_at(at)
	w.age, w.vent = age_at(at, k.age)
	w.rising = k.rising   // the regional history's, the forearc's outer high's rise in it
	w.depth, w.inland = max(-k.h, 0), inland
	w.crust, w.across = k.thick, (k.front + k.setback)/k.setback if over else 1e4
	w.setting = .Continent if inland > 0 else .Arc if w.front < 10 else .Hotspot if w.track < 10 else .Forearc if over && k.front < 0 else .Back_Arc if over && k.front < 400 && !k.cont else .Shelf if k.cont else .Open_Sea
	return
}

world_point :: proc(p: ^Point) -> World_Point { return world_at(p.x + f64(region.origin.x), p.z + f64(region.origin.y)) }

// What the regional history says of an island at its middle, read in place of draws from its seed
// where it can say it (record_phases, land.odin): how fast its crust rose over the regional
// history's last steps, and the volcano it stands on.
Record :: struct {
	past: [PAST]f32,   // mm/yr over each step of REGION_DT, newest first
	vent: Known_Vent,
	on:   bool,        // it stands on that volcano's foot
}
record_of :: proc(is: Island) -> (r: Record) {
	at := known_point(f64(is.origin.x), f64(is.origin.y))
	r.past = past_at(at)
	r.vent, r.on = vent_under(at)
	return
}

// How well a kind's host holds at a point in the world.
holds :: proc(k: int, at: [2]f64) -> (s: f32) {
	p := Point{x = at.x - f64(region.origin.x), z = at.y - f64(region.origin.y), cell = 2000}
	for h in KINDS[k].hosts do s = max(s, host(h, &p))
	return
}

// km in the known world as a point in the game's world, metres.
world_of :: proc(at: [2]f32) -> [2]f64 {
	return world_frame.origin + [2]f64{f64(at.x - world_frame.start.x), f64(at.y - world_frame.start.y)}*1000
}

// Read the islands near the start from the known world. The start is put where the history makes an
// island; the others stand where the rows of SITES put them round it; each is the kind whose host it
// holds best, no two nearest neighbours alike. It reads the record drawn at the start's place
// (`region`: its origin, the swell, and any kind asked for), so call it after `region_init`
// and `known_make`. With `say`, print what was left out. With a kind `forced` (--kind=), the start is
// of that kind and stands where its host holds best.
archipelago_make :: proc(say := false, forced := -1) {
	world_frame = {origin = {f64(region.origin.x), f64(region.origin.y)}, wind = region.shape.swell}   // the swell the seed draws for its own kind
	o := world_frame.origin
	// The start: where some kind's host holds best in the known world (or the forced kind's), 6 km
	// or more off land larger than a region; where one holds as well, where most islands would stand
	// round it, on the forearc 60 km from the volcanic front, 30 km or more off land larger than a
	// region, nearer the middle of the known world, which was chosen for its islands. It is then an
	// island like the others: its size drawn, its kind the one whose host holds best there.
	holds_any :: proc(p: [2]f64, forced: int) -> (s: f32) {
		if forced >= 0 do return holds(forced, p)
		for _, k in KINDS do s = max(s, holds(k, p))
		return
	}
	best, chosen := f32(-1), [2]f32{}
	for j in -80..=80 do for i in -80..=80 {
		c := [2]f32{f32(i), f32(j)}*5
		p := world_of(c)
		w := world_at(p.x, p.y)
		if w.inland > -6 do continue
		k, _ := known_at(c)
		rich := math.exp(-math.pow((k.front + 60)/70, 2)) + 0.5*smoothstep(10, 30, -w.inland) - linalg.length(c)/800
		if s := 100*math.floor(holds_any(p, forced)*50)/50 + 0.2*rich + 0.01*hash01(i32(i), i32(j), world_seed + 1701); s > best do best, chosen = s, c   // the host first, to 0.02
	}
	world_frame.start = chosen

	Site :: struct { at: [2]f64, size: f64 }
	sites := make([dynamic]Site, context.temp_allocator)
	// A site takes a size drawn by Korčák's law, as large as fits beside those already placed, within the
	// square round the start and off land larger than a region. One no kind's host holds is left out.
	sized :: proc(sites: []Site, at: [2]f64, key: i32) -> f64 {
		u := f64(hash01(key, 1, world_seed + 1702))
		size := SIDES[0]*math.pow(1 - u*(1 - math.pow(SIDES[1]/SIDES[0], -2*KORCAK)), -0.5/KORCAK)
		for s in sites do size = min(size, 2*max(abs(at.x - s.at.x), abs(at.y - s.at.y)) - s.size)
		size = math.floor(size/2048)*2048
		for ; size >= SIDES[0]; size -= 2048 {
			ashore := false
			for c in ([8][2]f64{{-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}}) do ashore ||= world_at(at.x + c.x*size/2, at.y + c.y*size/2).inland > 0
			if !ashore do break
		}
		return size
	}
	append(&sites, Site{o, max(sized(nil, o, -1), SIDES[0])})   // the start, 6 km or more off land larger than a region, which a region of 8 km clears
	place :: proc(sites: ^[dynamic]Site, at: [2]f64, key: i32, say: bool, why: string) -> bool {
		some := false
		for _, k in KINDS do some ||= holds(k, at) > 0
		if w := world_at(at.x, at.y); !some {
			if say do fmt.printfln("  left out %s at %.1f, %.1f km (%s, %.1f Myr, rising %.2f mm/yr, %.0f m deep): %s", why, at.x/1000, at.y/1000, SETTINGS[w.setting], w.age, w.rising, w.depth,
				"a young hotspot shield would stand here, and no kind makes one" if w.track < 10 && w.age < 1 else "no kind's host holds here")
			return false
		}
		size := sized(sites[:], at, key)
		o := world_frame.origin
		if size < SIDES[0] || max(abs(at.x - o.x), abs(at.y - o.y)) + size/2 > NEAR_SIDE/2 do return false
		append(sites, Site{at, size})
		return true
	}
	// Where each row of SITES says the history makes an island, within the square round the start,
	// taken nearest the start first, each at least its row's distance from those already taken.
	Candidate :: struct { at: [2]f32, row: int, key: i32, d: f32 }
	cands := make([dynamic]Candidate, context.temp_allocator)
	in_square :: proc(at: [2]f32) -> bool { d := at - world_frame.start; return max(abs(d.x), abs(d.y)) < NEAR_SIDE/2000 }
	for s, i in known.samples {
		at := [2]f32{f32(i%KNOWN_N) + 0.5, f32(i/KNOWN_N) + 0.5}*KNOWN_STEP - WINDOW/2
		if !in_square(at) do continue
		share := (s.front + s.setback)/s.setback if s.front < 1e3 else -1   // of the way back from the trench to the volcanic front
		jitter := ([2]f32{hash01(i32(i), 1, world_seed + 1703), hash01(i32(i), 2, world_seed + 1703)} - 0.5)*KNOWN_STEP
		for row, r in SITES {
			on: bool
			switch row.line {
			case .Forearc: on = abs(share - OUTER.at) < 0.5*OUTER.width
			case .Shelf:   on = s.cont && s.h < 0 && s.h > -300 && known.inland[i] < -10
			case .Front, .Vent, .Land:
			}
			if on do append(&cands, Candidate{at + jitter, r, i32(i), 0})
		}
	}
	for v, i in known.vents do if live := v.arc && v.last < 2*REGION_DT; in_square(v.at) && v.top > (-200 if live else 0) {   // a growing vent near the sea, or a dead one not yet planed to it
		for row, r in SITES do if row.line == (.Front if live else .Vent) do append(&cands, Candidate{v.at, r, i32(i) + 1_000_000, 0})
	}
	for m, i in known.masses do if !m.large {
		at := [2]f32{f32(m.top%KNOWN_N) + 0.5, f32(m.top/KNOWN_N) + 0.5}*KNOWN_STEP - WINDOW/2
		if in_square(at) do for row, r in SITES do if row.line == .Land do append(&cands, Candidate{at, r, i32(i) + 2_000_000, 0})
	}
	for &c in cands do c.d = linalg.length(c.at - world_frame.start)
	slice.sort_by(cands[:], proc(a, b: Candidate) -> bool { return a.d < b.d })
	taken := make([dynamic][2]f32, context.temp_allocator)
	append(&taken, world_frame.start)
	counts: [len(SITES)][2]int
	for c in cands {
		apart := math.lerp(SITES[c.row].apart[0], SITES[c.row].apart[1], hash01(c.key, i32(c.row), world_seed + 1706))
		near := false
		for t in taken do near ||= linalg.length(t - c.at) < apart
		if near do continue
		append(&taken, c.at)
		counts[c.row] += {1, int(place(&sites, world_of(c.at), c.key, say, SITES[c.row].name))}
	}
	if say do for row, r in SITES do fmt.printfln("  %s: %d sites, %d islands", row.name, counts[r][0], counts[r][1])

	// Each site takes the kind whose host it holds best, ties broken by a draw keyed by the kind's
	// name and weighted as the race's are; a kind its nearest neighbour has, or that has it as
	// nearest, is passed over for the next best. A site whose neighbours took every kind that holds
	// there is left out.
	kind := make([]int, len(sites), context.temp_allocator)
	kept := make([]bool, len(sites), context.temp_allocator)
	for &k in kept do k = true
	kind[0] = forced
	nearest :: proc(sites: []Site, kept: []bool, i: int) -> (n: int) {
		n = -1
		for s, j in sites do if kept[j] && j != i && (n < 0 || math.hypot(s.at.x - sites[i].at.x, s.at.y - sites[i].at.y) < math.hypot(sites[n].at.x - sites[i].at.x, sites[n].at.y - sites[i].at.y)) do n = j
		return
	}
	for again := true; again; {
		again = false
		for i in (1 if forced >= 0 else 0)..<len(sites) do if kept[i] {
			s, best, key := sites[i], f32(0), f32(-1)
			kind[i] = -1
			for k, r in KINDS {
				h := holds(r, s.at)
				taken := false
				for j in 0..<i do taken ||= kept[j] && kind[j] == r && (nearest(sites[:], kept, i) == j || nearest(sites[:], kept, j) == i)
				u := math.pow(hash01(i32(i), i32(fnv.fnv32a(transmute([]u8)k.name)), world_seed + 1704), 1/k.weight)
				if h > 0 && !taken && (h > best + 1e-4 || h > best - 1e-4 && u > key) do kind[i], best, key = r, h, u
			}
			if kind[i] < 0 && i == 0 {   // the start stands whatever holds; where none does, the seed's own kind
				for k, r in KINDS do if k.name == region.kind do kind[0] = r
			} else if kind[i] < 0 {
				kept[i], again = false, true
				if say do fmt.printfln("  left out at %.1f, %.1f km: its neighbours took every kind its setting holds", s.at.x/1000, s.at.y/1000)
				break
			}
		}
	}
	clear(&archipelago)
	for s, i in sites do if kept[i] {
		w, id := world_at(s.at.x, s.at.y), len(archipelago)
		append(&archipelago, Island{id = id, origin = {i32(math.round(s.at.x)), i32(math.round(s.at.y))}, size = s.size, kind = kind[i],
			seed = world_seed if id == 0 else hash(i32(id), 0, world_seed + 1705), setting = w.setting, age = w.age})
	}
	continent_make()
	ashore := f64(1e12)
	for c in continent.coast do ashore = min(ashore, math.hypot(c.x - o.x, c.y - o.y))
	w := world_at(o.x, o.y)
	names := strings.builder_make(context.temp_allocator)
	by_kind: [len(KINDS)]int
	by_setting: [Setting]int
	for is in archipelago { by_kind[is.kind] += 1; by_setting[is.setting] += 1 }
	for n, k in by_kind do if n > 0 do fmt.sbprintf(&names, "%s %d, ", KINDS[k].name, n)
	for n, s in by_setting do if n > 0 do fmt.sbprintf(&names, "%d on the %s, ", n, SETTINGS[s])
	strings.pop_rune(&names); strings.pop_rune(&names)
	fmt.printfln("near the start: %d islands (%s), off land whose coast is %.0f km away; this one, %s, %.1f km across, stands on the %s, %s, where its kind's host holds %.2f; the wind from %.0f°",
		len(archipelago), strings.to_string(names), ashore/1000, KINDS[archipelago[0].kind].name, archipelago[0].size/1000, SETTINGS[archipelago[0].setting], fmt.tprintf("%.0f km from the volcanic front", w.front) if w.front < 1e3 else "with no volcanic front within reach", holds(archipelago[0].kind, o), world_frame.wind)
	lat := math.to_degrees(math.asin(linalg.normalize(known.centre + (world_frame.start.x*known.east - world_frame.start.y*known.north)/PLANET).z))
	fmt.printfln("the known world: 1,000 km at %.1f° N, read from the plates' history%s; the start %.0f km east and %.0f km south of its middle, at %.1f° N",
		math.to_degrees(math.asin(known.centre.z)), fmt.tprintf(", which ran in %.2f s (its regional history %.2f s of it)", known.took, known.regional_took) if known.took > 0 else ", kept from an earlier run", world_frame.start.x, world_frame.start.y, lat)
}

// What the plates' history says of the island in hand, as --why prints it: where it stands, what
// its crust is, how it moves, and why it is its kind.
plates_words :: proc() {
	o := [2]f64{f64(region.origin.x), f64(region.origin.y)}
	w := world_at(o.x, o.y)
	k, _ := known_at(known_point(o.x, o.y))
	fmt.printf("the plates: the island's middle stands on the %s (%s in the history)", SETTINGS[w.setting], PLATE_SETTINGS[k.row].name)
	if w.front < 1e3 do fmt.printf(", %.0f km %s the volcanic front and %.0f km from the trench", w.front, "before" if k.front < 0 else "behind", w.trench)
	else if w.trench < 0 do fmt.printf(", on the plate going down, %.0f km before the trench", -w.trench)
	fmt.printf("; on %s crust %.0f km thick, its land %.1f Myr old; the sea %.0f m deep round it; it rises %.2f mm/yr (the history's own %.2f", "continental" if k.cont else "oceanic", k.thick, w.age, w.depth, w.rising, k.rising)
	if high := outer_high(k); high > 0.01 do fmt.printf(", on the forearc's outer high, %.0f%% of the way to its crest", 100*high)
	fmt.printf(")")
	if w.vent < 1e3 do fmt.printf("; on the foot of a volcano that began %.1f Myr ago", w.vent)
	if w.track < 1e3 do fmt.printf("; %.0f km from a hotspot's track", w.track)
	start := -1
	for r, i in KINDS do if r.name == region.kind do start = i
	fmt.printf(". It is the %s kind", region.kind)
	if here.island.id == 0 do fmt.printf(", the start, put where some kind's host holds best")
	if start >= 0 && len(KINDS[start].hosts) > 0 {
		fmt.printf(": its host holds %.2f here, on", holds(start, o))
		p := Point{cell = 2000}
		for win, i in KINDS[start].hosts[0] {
			f := FIELDS[win.field]
			fmt.printf("%s %s %.4g%s (%s)", "," if i > 0 else "", f.name, f.at(&p), f.unit, fmt.tprintf("over %.4g", win.lo) if win.hi >= ANY else fmt.tprintf("up to %.4g", win.hi) if win.lo <= -ANY else fmt.tprintf("%.4g to %.4g", win.lo, win.hi))
		}
	}
	{
		r := record_of(here.island)
		fmt.printf(". Its record is read from the regional history: its crust rose")
		for v, k in r.past do fmt.printf("%s %.2f", "," if k > 0 else "", v)
		fmt.printf(" mm/yr over each half million years back from today, which sets its uplift within its kind's range")
		if r.on && r.vent.arc && laid_by(&KINDS[here.island.kind]) != .Plates do fmt.printf("; its volcano, %.0f m high over the ground it was built on, began %.1f Myr ago, which sets how high it builds and how long the sea has cut it", r.vent.built, r.vent.born)
	}
	fmt.printfln(". --plates-why=%.0f,%.0f follows its crust back through the history.", o.x, o.y)
}

// The land larger than a region nearest the start: its coast traced round its samples, and the
// highest ground within 60 km of each stretch of it.
continent_make :: proc() {
	N :: KNOWN_N
	clear(&continent.coast)
	clear(&continent.crest)
	continent.height = 0
	from, by := -1, f32(1e9)
	for _, i in known.samples do if m := known.mass[i]; m > 0 && known.masses[m - 1].large {
		at := [2]f32{f32(i%N) + 0.5, f32(i/N) + 0.5}*KNOWN_STEP - WINDOW/2
		if d := linalg.length(at - world_frame.start); d < by do from, by = i, d
	}
	if from < 0 {   // none in the known world: a coast beyond it, 2,000 km off, which nothing reaches
		far := world_of(world_frame.start + {2000, 0})
		append(&continent.coast, far, far)
		return
	}
	id := known.mass[from]
	inside :: proc(p: [2]int, id: i32) -> bool { return p.x >= 0 && p.y >= 0 && p.x < N && p.y < N && known.mass[p.y*N + p.x] == id }
	point :: proc(p: [2]int) -> [2]f64 { return world_of([2]f32{f32(p.x) + 0.5, f32(p.y) + 0.5}*KNOWN_STEP - WINDOW/2) }
	// Round the mass's edge by its neighbours, turning the same way at each sample, until it makes its
	// first move again: it may pass the sample it began at more than once, from different sides.
	dirs := [8][2]int{{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}}
	cur, back := [2]int{from%N, from/N}, 0
	for d, k in dirs do if !inside(cur + d, id) { back = k; break }
	edge := make([dynamic][2]int, context.temp_allocator)
	for len(edge) < 32*N {   // 32,000 km of coast at most
		append(&edge, cur)
		moved := false
		for t in 1..=8 {
			k := (back + t)%8
			if n := cur + dirs[k]; inside(n, id) {
				before := cur + dirs[(back + t - 1)%8]
				cur, moved = n, true
				for d, j in dirs do if cur + d == before do back = j
				break
			}
		}
		if !moved || len(edge) > 1 && edge[len(edge) - 1] == edge[0] && cur == edge[1] {
			if len(edge) > 1 do pop(&edge)
			break
		}
	}
	for p, i in edge do if i%2 == 0 do append(&continent.coast, point(p))
	append(&continent.coast, continent.coast[0])
	heights := make([dynamic]f32, context.temp_allocator)
	last := -1
	for p, i in edge do if i%5 == 0 {
		top := -1
		for dy in -30..=30 do for dx in -30..=30 do if q := p + {dx, dy}; inside(q, id) && (top < 0 || known.samples[q.y*N + q.x].h > known.samples[top].h) do top = q.y*N + q.x
		if top >= 0 && top != last {
			append(&continent.crest, point({top%N, top/N}))
			append(&heights, known.samples[top].h)
			last = top
		}
	}
	slice.sort(heights[:])
	if len(heights) > 0 do continent.height = heights[len(heights)/2]
}

GLYPHS     :: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,.-:/"
GLYPH_BITS :: [?]u16{   // 3 by 5, the top row in the high bits
	0x2BED, 0x6BAE, 0x3923, 0x6B6E, 0x79A7, 0x79A4, 0x396B, 0x5BED, 0x7497, 0x126A, 0x5BAD, 0x4927, 0x5FED, 0x6B6D, 0x2B6A, 0x6BA4, 0x2B73, 0x6BAD, 0x388E,
	0x7492, 0x5B6F, 0x5B6A, 0x5BFD, 0x5AAD, 0x5A92, 0x72A7, 0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9, 0x79CF, 0x79EF, 0x7292, 0x7BEF, 0x7BCF, 0x0014, 0x0002, 0x01C0, 0x0410, 0x12A4,
}

// Write `s` in capitals, `scale` pixels to a dot, its top left at x, y, in `ink` over a black rim.
write :: proc(pixels: []u8, size, x, y: int, s: string, scale: int, ink: [3]u8) {
	bits := GLYPH_BITS
	for pass in 0..<2 do for c, i in s {
		k := strings.index_byte(GLYPHS, u8(c) - 32 if c >= 'a' && c <= 'z' else u8(c))
		if k < 0 do continue
		for v in 0..<5 do for u in 0..<3 do if bits[k] >> uint(14 - v*3 - u) & 1 == 1 {
			r := 1 - pass   // the rim reaches a pixel past each dot
			for dy in -r..<scale + r do for dx in -r..<scale + r {
				if px, py := x + (i*4 + u)*scale + dx, y + v*scale + dy; px >= 0 && py >= 0 && px < size && py < size {
					for j in 0..<3 do pixels[(py*size + px)*4 + j] = ink[j] if pass == 1 else 0
				}
			}
		}
	}
}

// --archipelago=: form every island side by side with the one region's code, sample its heights into a
// picture 200 km across round the start, then draw what the history left there (its trench, volcanic
// front and volcanoes, the hotspots' tracks, the land larger than a region) and name each island.
archipelago_map :: proc(path: string) {
	MAP, VIEW :: 3000, NEAR_SIDE + 40_000   // pixels, and the metres they cover: the square the islands are placed in and a margin
	started := time.now()
	all := make([]int, len(formed))
	defer delete(all)
	for &a, i in all do a = i
	islands_done(islands_form(all, max(os.get_processor_core_count() - 1, 1), .Normal, false), all)   // side by side, each saying its line
	heights := make([]f32, MAP*MAP)
	defer delete(heights)
	pixel :: proc(px, py: int) -> [2]f64 { return world_frame.origin - VIEW/2 + ([2]f64{f64(px), f64(py)} + 0.5)*VIEW/MAP }
	tops := make([]f32, len(archipelago))
	defer delete(tops)
	for &f, i in formed {
		bind(&f)
		is := f.island
		for h in land.z[0] do tops[i] = max(tops[i], h)
		o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
		lo, hi := (o - is.size/2 - world_frame.origin + VIEW/2)*MAP/VIEW, (o + is.size/2 - world_frame.origin + VIEW/2)*MAP/VIEW
		for py in max(int(lo.y), 0)..<min(int(hi.y) + 1, MAP) do for px in max(int(lo.x), 0)..<min(int(hi.x) + 1, MAP) {
			if p := pixel(px, py) - o; max(abs(p.x), abs(p.y)) < is.size/2 do heights[py*MAP + px] = max(land_at(land.z[2], land.n/4, p.x, p.y), 0)
		}
		fmt.printfln("%d %s, %s, %.1f Myr, at %.1f, %.1f km; region %.1f km, highest %.0f m, formed in %.2f s; its rock %s%s; lives on it: %s",
			is.id, KINDS[is.kind].name, SETTINGS[is.setting], is.age, o.x/1000, o.y/1000, is.size/1000, tops[i], f.seconds, region.story.name, "" if rocks.full else " (its kind's)", lives_words())
	}
	bind(home)

	// Each island and the nearest summit of another: whether it shows over the curve from the shore,
	// the world drawn round with refraction (R = 7,400 km).
	far, hidden := 0.0, 0
	for a, i in archipelago {
		near, d := 0, f64(1e12)
		for b, j in archipelago do if e := math.hypot(f64(a.origin.x - b.origin.x), f64(a.origin.y - b.origin.y)); j != i && e < d do near, d = j, e
		far = max(far, d)
		if math.sqrt(f64(2*7.4e6*2)) + math.sqrt(2*7.4e6*f64(tops[near])) < d do hidden += 1
	}
	fmt.printfln("nearest neighbours at most %.0f km apart, middle to middle; %d of %d islands cannot see the nearest one's top from the shore over the curve", far/1000, hidden, len(archipelago))
	// And the continent's range, from each island's shore.
	ashore, crest, seen := [2]f64{1e12, 0}, [2]f64{1e12, 0}, 0
	for is in archipelago {
		o, a, c := [2]f64{f64(is.origin.x), f64(is.origin.y)}, f64(1e12), f64(1e12)
		for p in continent.coast[:len(continent.coast) - 1] do a = min(a, math.hypot(p.x - o.x, p.y - o.y))
		for p in continent.crest do c = min(c, math.hypot(p.x - o.x, p.y - o.y))
		ashore, crest = {min(ashore[0], a), max(ashore[1], a)}, {min(crest[0], c), max(crest[1], c)}
		if math.sqrt(f64(2*7.4e6*2)) + math.sqrt(2*7.4e6*f64(continent.height)) >= c do seen += 1
	}
	fmt.printfln("the coast of the land larger than a region lies %.0f to %.0f km from the islands' middles; the crest of its range, %.0f m, %.0f to %.0f km, shows over the curve from the shore of %d of %d",
		ashore[0]/1000, ashore[1]/1000, continent.height, crest[0]/1000, crest[1]/1000, seen, len(archipelago))

	// The hotspots' tracks within reach of the picture, to measure each pixel against.
	tracks := make([dynamic][2][2]f32, context.temp_allocator)
	for t in known.chains do if linalg.length(0.5*(t[0] + t[1]) - world_frame.start) < VIEW/1000 + linalg.length(t[1] - t[0]) do append(&tracks, t)
	pixels := make([]u8, MAP*MAP*4)
	defer delete(pixels)
	// Each line is drawn where its field changes sign between a pixel and the one left of it or above
	// it: the coast of land larger than a region, the trench, the volcanic front, the forearc's outer
	// high. A field is had only where its plate has it (NaN elsewhere), so no line is drawn across a gap.
	LINES :: 4
	inks := [LINES][3]f32{{0.92, 0.90, 0.84}, {0.55, 0.12, 0.10}, {0.95, 0.30, 0.20}, {0.30, 0.75, 0.80}}
	rows := make([][LINES]f32, 2*MAP)
	defer delete(rows)
	for py in 0..<MAP do for px in 0..<MAP {
		h, p := heights[py*MAP + px], pixel(px, py)
		at := known_point(p.x, p.y)
		k, inland := known_at(at)
		grey: f32
		if h > 0 {
			gx := heights[py*MAP + min(px + 1, MAP - 1)] - heights[py*MAP + max(px - 1, 0)]
			gz := heights[min(py + 1, MAP - 1)*MAP + px] - heights[max(py - 1, 0)*MAP + px]
			grey = (0.62 + 0.33*math.sqrt(min(h/1000, 1)))*clamp(0.85 + (-gx - gz)/120, 0.35, 1.25)
		} else if k.h > 0 {
			grey = (0.50 if inland > 0 else 0.46) if (px + py)%16 > 1 else 0.40   // the history's land, hatched: not formed
		} else {
			grey = 0.40 - 0.27*clamp(math.ln(max(-k.h, 5)/50)/math.ln(f32(7000.0/50)), 0, 1)
		}
		col := [3]f32{grey, grey, grey}
		over := k.front < 1e3
		nan := math.nan_f32()
		row := &rows[(py%2)*MAP + px]
		row^ = {k.h if inland > -4 else nan, k.front + k.setback if over else -k.slab if k.slab < 1e3 else nan, k.front if over else nan, k.front + (1 - OUTER.at)*k.setback if over && k.front < 0 else nan}
		if h <= 0 {
			for f in 0..<LINES {
				left, up := rows[(py%2)*MAP + max(px - 1, 0)][f], rows[((py + 1)%2)*MAP + px][f]
				if row[f] < 0 && (left >= 0 || py > 0 && up >= 0) || row[f] >= 0 && (left < 0 || py > 0 && up < 0) do col = inks[f]
			}
			for t in tracks {
				u := clamp(linalg.dot(at - t[0], t[1] - t[0])/max(linalg.dot(t[1] - t[0], t[1] - t[0]), 1e-6), 0, 1)
				if linalg.length(at - linalg.lerp(t[0], t[1], u)) < 0.07 do col = {1.00, 0.60, 0.10}
			}
		}
		for k in 0..<3 do pixels[(py*MAP + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
	}
	at :: proc(p: [2]f64) -> [2]int { return {int((p.x - world_frame.origin.x + VIEW/2)*MAP/VIEW), int((p.y - world_frame.origin.y + VIEW/2)*MAP/VIEW)} }
	dot :: proc(pixels: []u8, q: [2]int, r0, r1: int, ink: [3]u8) {
		for dy in -r1..=r1 do for dx in -r1..=r1 do if r := dx*dx + dy*dy; r >= r0*r0 && r <= r1*r1 && q.x + dx >= 0 && q.y + dy >= 0 && q.x + dx < MAP && q.y + dy < MAP {
			for k, j in ink do pixels[((q.y + dy)*MAP + q.x + dx)*4 + j] = k
		}
	}
	// The crest of the range behind the coast.
	for c, i in continent.crest[1:] {
		a, b := at(continent.crest[i]), at(c)
		if abs(a.x - b.x) + abs(a.y - b.y) > 400 do continue
		for t in 0..=40 do dot(pixels, a + (b - a)*t/40, 0, 1, {205, 140, 75})
	}
	// What a label must not cover: each island's land, the key, then each label written.
	boxes := make([dynamic][4]int, context.temp_allocator)
	for is in archipelago {
		q, r := at({f64(is.origin.x), f64(is.origin.y)}), int(0.4*is.size*MAP/VIEW)
		append(&boxes, [4]int{q.x - r, q.y - r, q.x + r, q.y + r})
	}
	append(&boxes, [4]int{0, 0, 1300, 236})
	clear_of :: proc(boxes: [][4]int, b: [4]int, skip := -1) -> bool {
		if b.x < 0 || b.y < 0 || b.z > MAP || b.w > MAP do return false
		for o, j in boxes do if j != skip && !(o.z < b.x || o.x > b.z || o.w < b.y || o.y > b.w) do return false
		return true
	}
	if len(continent.crest) > 0 {
		c := at(continent.crest[len(continent.crest)/2])
		note := fmt.tprintf("LAND LARGER THAN A REGION, NOT YET FORMED: ITS RANGE ABOUT %.0f M HIGH", continent.height)
		c = {clamp(c.x - 6*len(note), 20, MAP - 20 - 12*len(note)), clamp(c.y + 12, 250, MAP - 60)}
		if clear_of(boxes[:], {c.x, c.y, c.x + 12*len(note), c.y + 16}) {
			write(pixels, MAP, c.x, c.y, note, 3, {230, 225, 215})
			append(&boxes, [4]int{c.x, c.y, c.x + 12*len(note), c.y + 16})
		}
	}
	// The history's volcanoes: the arc's live vents red, its dead ones dark red, the hotspots'
	// with their ages, each hotspot ringed where it stands now.
	for v in known.vents {
		q := at(world_of(v.at))
		if q.x < 0 || q.y < 0 || q.x >= MAP || q.y >= MAP do continue
		if v.arc {
			dot(pixels, q, 0, 5, {255, 60, 40} if v.last < 2 else {140, 30, 20})
			continue
		}
		dot(pixels, q, 0, 5, {255, 160, 30})
		if b := ([4]int{q.x + 8, q.y + 6, q.x + 92, q.y + 21}); clear_of(boxes[:], b) {
			write(pixels, MAP, b.x, b.y, fmt.tprintf("%.0f MYR", v.born), 3, {255, 160, 30})
			append(&boxes, b)
		}
	}
	for hs in known.hotspots {
		q := at(world_of(hs.at))
		dot(pixels, q, 22, 26, {255, 160, 30})
		if b := ([4]int{q.x + 30, q.y - 9, q.x + 32 + 12*12, q.y + 10}); clear_of(boxes[:], b) {
			write(pixels, MAP, q.x + 32, q.y - 7, "HOTSPOT, NOW", 3, {255, 160, 30})
			append(&boxes, b)
		}
	}
	// Each island named on whichever side of it is clear: right, left, below, above.
	for is, i in archipelago {
		label := fmt.tprintf("%d %s, %s: %s", is.id, KINDS[is.kind].name, SETTINGS[is.setting], formed[i].region.story.name)
		q, r, w := at({f64(is.origin.x), f64(is.origin.y)}), int(0.42*is.size*MAP/VIEW), 12*len(label)
		spot := [4]int{q.x + r, q.y - 7, q.x + r + w, q.y + 9}
		for c in ([4][2]int{{q.x + r, q.y - 7}, {q.x - r - w, q.y - 7}, {q.x - w/2, q.y + r}, {q.x - w/2, q.y - r - 16}}) {
			if b := ([4]int{c.x, c.y, c.x + w, c.y + 16}); clear_of(boxes[:], b, i) {
				spot = b
				break
			}
		}
		append(&boxes, spot)
		write(pixels, MAP, spot.x, spot.y, label, 3, {255, 255, 255})
	}
	// The key to the lines.
	for line, n in ([7]struct { name: string, ink: [3]u8 }{{"TRENCH", {200, 60, 50}}, {"VOLCANIC FRONT, ITS LIVE VENTS AND DEAD ONES", {255, 90, 60}}, {"OUTER HIGH OF THE FOREARC", {90, 200, 210}}, {"HOTSPOT TRACK, THE AGES OF ITS VOLCANOES", {255, 160, 30}}, {"COAST OF LAND LARGER THAN A REGION", {235, 230, 215}}, {"CREST OF ITS RANGE", {205, 140, 75}}, {"HATCHED: LAND THE HISTORY MADE, NOT FORMED", {200, 200, 200}}}) {
		write(pixels, MAP, 20, 56 + 26*n, line.name, 3, line.ink)
	}
	write(pixels, MAP, 20, 20, fmt.tprintf("SEED %d: THE %d ISLANDS NEAR THE START, READ FROM THE HISTORY OF THE PLATES, %.0f KM ACROSS, NORTH UP. WIND AND SWELL FROM %.0f DEGREES", world_seed, len(archipelago), VIEW/1000.0, world_frame.wind), 3, {255, 255, 255})
	for y in MAP - 40..<MAP - 34 do for x in 20..<20 + 10_000*MAP/VIEW do for k in 0..<3 do pixels[(y*MAP + x)*4 + k] = 255
	write(pixels, MAP, 20, MAP - 30, "10 KM", 3, {255, 255, 255})
	write_png(path, pixels, MAP, MAP, false)
	fmt.printfln("the islands formed and drawn in %.1f s", time.duration_seconds(time.since(started)))
}

// --known=: the known world as its regional history of the plates left it, 1 km a pixel, north up:
// the ground and the sea's depth, the trench, the volcanic front, the forearc's outer high, the
// boundaries between plates, the history's vents, live and dead, and the square the islands near
// the start stand in.
known_map :: proc(path: string) {
	SIZE :: 1000
	km_at :: proc(px, py: int) -> [2]f32 { return {f32(px) + 0.5 - SIZE/2, f32(py) + 0.5 - SIZE/2} }
	samples := make([]Known_Sample, SIZE*SIZE)
	defer delete(samples)
	for py in 0..<SIZE do for px in 0..<SIZE do samples[py*SIZE + px], _ = known_at(km_at(px, py))
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	LINES :: 4
	inks := [LINES][3]f32{{0.55, 0.12, 0.10}, {0.95, 0.30, 0.20}, {0.30, 0.75, 0.80}, {1, 1, 0.55}}
	field :: proc(k: Known_Sample) -> [LINES]f32 {
		over := k.front < 1e3
		nan := math.nan_f32()
		return {k.front + k.setback if over else -k.slab if k.slab < 1e3 else nan, k.front if over else nan, (k.front + k.setback)/k.setback - OUTER.at if over && k.front < 0 else nan, 0}
	}
	for py in 0..<SIZE do for px in 0..<SIZE {
		k := samples[py*SIZE + px]
		gx := samples[py*SIZE + min(px + 1, SIZE - 1)].h - samples[py*SIZE + max(px - 1, 0)].h
		gy := samples[min(py + 1, SIZE - 1)*SIZE + px].h - samples[max(py - 1, 0)*SIZE + px].h
		col := land_colour(k.h)*clamp(0.8 + (-gx - gy)/600, 0.4, 1.25) if k.h > 0 else linalg.lerp([3]f32{0.45, 0.70, 0.88}, [3]f32{0.05, 0.14, 0.38}, clamp(-k.h/5000, 0, 1))
		here := field(k)
		if px > 0 && py > 0 {
			left, up := samples[py*SIZE + px - 1], samples[(py - 1)*SIZE + px]
			for f in 0..<LINES - 1 {
				a, b := field(left)[f], field(up)[f]
				if here[f] < 0 && (a >= 0 || b >= 0) || here[f] >= 0 && (a < 0 || b < 0) do col = inks[f]
			}
			if left.plate != k.plate || up.plate != k.plate do col = inks[3]
		}
		for j in 0..<3 do pixels[(py*SIZE + px)*4 + j] = u8(clamp(col[j], 0, 1)*255)
	}
	dot :: proc(pixels: []u8, at: [2]f32, r: int, ink: [3]u8) {
		q := [2]int{int(at.x + SIZE/2), int(at.y + SIZE/2)}
		for dy in -r..=r do for dx in -r..=r do if dx*dx + dy*dy <= r*r && q.x + dx >= 0 && q.y + dy >= 0 && q.x + dx < SIZE && q.y + dy < SIZE {
			for k, j in ink do pixels[((q.y + dy)*SIZE + q.x + dx)*4 + j] = k
		}
	}
	for v in known.vents do dot(pixels, v.at, 2 if v.top > -200 else 1, ({255, 60, 40} if v.last < 0.6 else {140, 30, 20}) if v.arc else {255, 160, 30})
	for h in known.hotspots do for a in 0..<48 do dot(pixels, h.at + 9*[2]f32{math.cos(f32(a)*0.1309), math.sin(f32(a)*0.1309)}, 0, {255, 160, 30})
	for i in 0..<800 {
		a := f32(i)/800*NEAR_SIDE/1000 - NEAR_SIDE/2000
		for c in ([4][2]f32{{a, -NEAR_SIDE/2000}, {a, NEAR_SIDE/2000}, {-NEAR_SIDE/2000, a}, {NEAR_SIDE/2000, a}}) do dot(pixels, world_frame.start + c, 0, {255, 255, 255})
	}
	for line, n in ([6]struct { name: string, ink: [3]u8 }{{"TRENCH", {140, 30, 25}}, {"VOLCANIC FRONT, ITS LIVE VENTS AND DEAD ONES", {242, 77, 51}}, {"OUTER HIGH OF THE FOREARC", {77, 191, 204}}, {"BOUNDARY BETWEEN PLATES", {255, 255, 140}}, {"HOTSPOT AND ITS VOLCANOES", {255, 160, 30}}, {"WHITE: THE SQUARE OF THE ISLANDS NEAR THE START", {255, 255, 255}}}) {
		write(pixels, SIZE, 12, 36 + 16*n, line.name, 2, line.ink)
	}
	write(pixels, SIZE, 12, 12, fmt.tprintf("SEED %d: THE KNOWN WORLD, 1000 KM, AS ITS REGIONAL HISTORY OF THE PLATES LEFT IT. NORTH UP", world_seed), 2, {255, 255, 255})
	write_png(path, pixels, SIZE, SIZE, false)
	plates := make(map[u8]int, context.temp_allocator)
	for s in known.samples do plates[s.plate] += 1
	fmt.printfln("the known world drawn: %d plates in it, %d of them the regional history's own; %d vents", len(plates), len(plates) - len(plates) + count_own(plates), len(known.vents))
	count_own :: proc(m: map[u8]int) -> (n: int) { for p in m do n += int(p >= MICRO); return }
}
