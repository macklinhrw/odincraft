package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"

// The islands near the start, and the continent they lie off (foundations/world-frame.md, D4). The
// world's land is to come from one story of how its plates have moved (step 22 in foundations.md);
// until that exists, a fixed stand-in for the plates near the start says where the crust is
// continental and where oceanic, and where islands form. One plate goes down under another along a
// trench, curved as an arc of a circle. Set back from it on the plate riding over it is the arc's
// volcanic front, where young volcanoes stand; between the two the forearc, rising fastest along its
// outer ridge; behind the front a trough, then the shelf, the drowned margin of a continent, and the
// continent's coast. On the plate going down, a hotspot stays put while the plate carries what it
// built toward the trench, so its islands age along the plate's motion and sink as they cool.
//
// The stand-in makes the world's fields (`world_at`, read as `setting`, `front`, `trench`, `track`,
// `age`, `rising` and `depth` in FIELDS); each kind of island has a host on them (`hosts` in KINDS),
// and an island is the kind whose host it holds best. A plate history that replaces it must give
// the same: the fields the hosts read (`front` in km, `rising` in mm/yr, `age` in Myr, `depth` in m)
// and `setting` for the names; each island's place, size and age; the continent's coast and range;
// and the wind. Nothing here is formed: --archipelago= forms each island in turn to draw the group.

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

// The continent the islands lie off: what the world knows of it before any of it can be formed
// (step 21 looks for how). Its coast near the start comes from the stand-in, as the islands' settings
// do; its range is a guess, there being nothing yet to form it.
Continent :: struct {
	coast:  [dynamic][2]f64,   // its coastline for 300 km round the start, in the world, metres, then the middle of the trench's circle far inland, which closes the outline
	crest:  [dynamic][2]f64,   // the line of the range behind the coast, as far along
	height: f32,               // metres, the range's crest
}
continent: Continent   // made by archipelago_make()

Setting :: enum u8 { Open_Sea, Hotspot, Forearc, Arc, Back_Arc, Shelf, Continent }
SETTINGS := [Setting]string{.Open_Sea = "open sea", .Hotspot = "hotspot", .Forearc = "forearc", .Arc = "arc", .Back_Arc = "back-arc", .Shelf = "shelf", .Continent = "continent"}

// The stand-in's numbers, drawn from the seed within the ranges of PLATES.
Plates :: struct($T: typeid) {
	radius:  T,   // km, of the circle the trench is an arc of; its middle lies on the plate riding over it
	facing:  T,   // degrees from north: the way the trench faces, out from the arc
	middle:  T,   // km from the trench back to the middle of the square round the start
	setback: T,   // km from the trench back to the volcanic front: 100 to 250 on real arcs, squeezed in here
	margin:  T,   // km of shelf from its edge to the continent's coast
	crest:   T,   // km from the coast to the crest of the range behind it,
	height:  T,   // and its height in metres: a guess, after the coastal ranges behind the arcs of Japan and China
	rise:    T,   // mm/yr the forearc rises along its outer ridge, two fifths of the way back to the front
	shake:   T,   // mm/yr the crust's rise varies by, from one block about 40 km across to the next
	beyond:  T,   // km beyond the trench the hotspot lies,
	along:   T,   // and along it from the square's middle, to one side or the other
	side:    T,   // which side: under 0.5 the one, else the other
	oblique: T,   // degrees the plate's motion lies off straight at the trench, back toward the square's middle
	speed:   T,   // km/Myr the plate carries what the hotspot built
	sink:    T,   // mm/yr an island sinks as the plate carries it off the hotspot, less by e every `cools` Myr
	cools:   T,
	front, forearc, track: T,   // km between islands along the front, across the forearc and along the hotspot's track
	shelf:   T,   // how many islands stand on the shelf
}
PLATES := Plates([2]f64){
	radius = {200, 360}, facing = {0, 360}, middle = {12, 20}, setback = {38, 46}, margin = {15, 35}, crest = {20, 40}, height = {1000, 2200},
	rise = {1.3, 2}, shake = {0.15, 0.25}, beyond = {34, 48}, along = {20, 40}, side = {0, 1}, oblique = {38, 56}, speed = {9, 13}, sink = {0.4, 0.6},
	cools = {1.5, 2.5}, front = {14, 24}, forearc = {18, 28}, track = {12, 17}, shelf = {3, 6},
}
NEAR_SIDE   :: 150_000   // metres, the side of the square round the start the islands are placed in
SHELF  :: 1.4       // where the shelf's edge stands, in setbacks from the trench
// The sea's floor across the arc: setbacks from the trench (under 0 on the plate going down), and metres
// deep. Past the shelf's edge the floor rises to the coast.
DEPTHS :: [?][2]f64{{-3, 5000}, {-0.2, 5300}, {0, 7000}, {0.12, 4000}, {0.4, 900}, {0.65, 2000}, {1, 700}, {1.2, 1800}, {SHELF, 200}}
// Island sizes follow Korčák's law: the number with more than an area A falls as A to the -0.65, half
// the fractal dimension of a coast (a guess, not measured on real groups). Only regions 8 to 16 km
// across form islands that read as their kind, so the law is cut there.
KORCAK :: 0.65
SIDES  :: [2]f64{8192, 16384}

Drawn_Plates :: struct {
	using drawn: Plates(f64),
	mid, centre, hotspot, motion: [2]f64,   // the square's middle, the trench's circle's, the hotspot, in the world, metres; the plate's motion, a unit
	reach: f64,   // metres from the hotspot along the motion to the trench
	wind:  f64,   // the bearing every island's swell and wind come from, degrees from north
}
plates: Drawn_Plates   // the stand-in as archipelago_make drew it

World_Point :: struct {
	setting: Setting,
	front, trench, track, age, rising, depth, inland: f32,   // km, km, km, Myr, mm/yr, m, km behind the coast
}

// How far behind the trench the continent's coast runs at a bearing from the trench's circle's
// middle, in km: a shelf's width behind the shelf's edge, wandering in bays and headlands.
coast_at :: proc(a: f64) -> f64 {
	r := (plates.radius - SHELF*plates.setback - plates.margin)*1000
	return SHELF*plates.setback + plates.margin + 16*f64(fbm(plates.centre.x + r*math.cos(a), plates.centre.y + r*math.sin(a), 50_000, 1000, 5, world_seed + 1733))
}

// The world's fields at a point in the world.
world_at :: proc(x, z: f64) -> (w: World_Point) {
	trench := plates.radius - math.hypot(x - plates.centre.x, z - plates.centre.y)/1000
	t := clamp((x - plates.hotspot.x)*plates.motion.x + (z - plates.hotspot.y)*plates.motion.y, 0, plates.reach)
	on := plates.hotspot + plates.motion*t
	s, track, myr := trench/plates.setback, f32(math.hypot(x - on.x, z - on.y)/1000) if trench < 0 else 1e4, f32(t/1000/plates.speed)
	coast := coast_at(math.atan2(z - plates.centre.y, x - plates.centre.x))
	w.trench, w.track, w.front, w.inland = f32(trench), track, f32(abs(trench - plates.setback)), f32(trench - coast)
	depths := DEPTHS
	w.depth = f32(math.lerp(200.0, 5, clamp((trench - SHELF*plates.setback)/(coast - SHELF*plates.setback), 0, 1)))
	for b, i in depths[1:] do if a := depths[i]; s < b.x {
		w.depth = f32(math.lerp(a.y, b.y, clamp((s - a.x)/(b.x - a.x), 0, 1)))
		break
	}
	if w.inland > 0 do w.depth = 0
	// Over the hotspot the plate swells, and its volcanoes built a ridge along the track.
	if trench < 0 do w.depth -= 600*f32(math.exp(-math.pow(math.hypot(x - plates.hotspot.x, z - plates.hotspot.y)/40_000, 2))) + 1200*math.exp(-math.pow(track/8, 2))
	// Young volcanoes on the front; on the track, as old as the plate's carrying; else the crust's age,
	// the ocean's, the arc's or the continent's.
	w.age = 60 if trench < 0 else 40 if s < SHELF else 200
	if trench < 0 do w.age = math.lerp(myr, w.age, smoothstep(6, 14, track))
	w.age = math.lerp(0.1 + 0.4*(1 + fbm(x, z, 30_000, 1000, 2, world_seed + 1730)), w.age, smoothstep(5, 12, w.front))
	// The forearc rises along its outer ridge and sinks into the trench; an island sinks as it cools off the hotspot.
	w.rising = f32(plates.rise*math.exp(-math.pow((s - 0.4)/0.2, 2)) - 0.3*math.exp(-math.pow(s/0.1, 2)) - 0.05) + f32(plates.shake)*fbm(x, z, 40_000, 1000, 2, world_seed + 1731)
	if trench < 0 do w.rising -= f32(plates.sink)*math.exp(-myr/f32(plates.cools))*smoothstep(14, 6, track)
	w.setting = Setting.Arc if w.front < 10 else (Setting.Hotspot if track < 10 else Setting.Open_Sea) if trench < 0 else Setting.Forearc if s < 1 else Setting.Back_Arc if s < SHELF else Setting.Shelf if w.inland < 0 else Setting.Continent
	return
}

world_point :: proc(p: ^Point) -> World_Point { return world_at(p.x + f64(region.origin.x), p.z + f64(region.origin.y)) }

// How well a kind's host holds at a point in the world.
holds :: proc(k: int, at: [2]f64) -> (s: f32) {
	p := Point{x = at.x - f64(region.origin.x), z = at.y - f64(region.origin.y), cell = 2000}
	for h in KINDS[k].hosts do s = max(s, host(h, &p))
	return
}

// Draw the plates from the world's seed, put them so the start island's kind holds where it stands,
// place islands along the front, across the forearc, along the hotspot's track and on the shelf, and
// give each the kind whose host it holds best, no two nearest neighbours alike. It reads the start
// island's record (`region`), so call it after `region_init`. With `say`, print what was left out.
archipelago_make :: proc(say := false) {
	N :: size_of(Plates(f64))/size_of(f64)
	ranges, drawn := transmute([N][2]f64)PLATES, [N]f64{}
	for r, i in ranges do drawn[i] = r[0] + (r[1] - r[0])*f64(hash01(i32(i), 0, world_seed + 1700))
	plates = {drawn = transmute(Plates(f64))drawn, wind = region.shape.swell}   // the start island's own swell, so it forms as it always has
	turn :: proc(v: [2]f64, a: f64) -> [2]f64 { return {v.x*math.cos(a) - v.y*math.sin(a), v.x*math.sin(a) + v.y*math.cos(a)} }
	face, side := [2]f64{math.sin(math.to_radians(plates.facing)), -math.cos(math.to_radians(plates.facing))}, 1.0 if plates.side < 0.5 else -1.0
	plates.centre = -face*(plates.radius - plates.middle)*1000
	out := turn(face, side*plates.along/plates.radius)
	plates.hotspot = plates.centre + out*(plates.radius + plates.beyond)*1000
	plates.hotspot = {clamp(plates.hotspot.x, 12_000 - NEAR_SIDE/2, NEAR_SIDE/2 - 12_000), clamp(plates.hotspot.y, 12_000 - NEAR_SIDE/2, NEAR_SIDE/2 - 12_000)}   // within the square round the start
	ob := math.to_radians(plates.oblique)
	plates.motion = -out*math.cos(ob) - side*[2]f64{-out.y, out.x}*math.sin(ob)
	// Where the track meets the trench; one that misses its curve runs on out of the square.
	v := plates.hotspot - plates.centre
	b := v.x*plates.motion.x + v.y*plates.motion.y
	c := b*b - (v.x*v.x + v.y*v.y) + plates.radius*plates.radius*1e6
	plates.reach = -b - math.sqrt(c) if c > 0 else 2*NEAR_SIDE

	// The start island's kind is the seed's, as it always was; the plates are put round it.
	start := 0
	for k, i in KINDS do if k.name == region.kind do start = i
	best, at := f32(-1), [2]f64{}
	for j in -24..=24 do for i in -24..=24 {
		p := [2]f64{f64(i), f64(j)}*2000
		if s := holds(start, p) + 0.01*hash01(i32(i), i32(j), world_seed + 1701); s > best && world_at(p.x, p.y).inland < -6 do best, at = s, p   // its square off the continent
	}
	o := [2]f64{f64(region.origin.x), f64(region.origin.y)}
	plates.mid, plates.centre, plates.hotspot = o - at, plates.centre + o - at, plates.hotspot + o - at

	Site :: struct { at: [2]f64, size: f64 }
	sites := make([dynamic]Site, context.temp_allocator)
	append(&sites, Site{o, REFERENCE})
	// A site takes a size drawn by Korčák's law, as large as fits beside those already placed, within the
	// square round the start and off the continent. One no kind's host holds is left out.
	place :: proc(sites: ^[dynamic]Site, at: [2]f64, key: i32, say: bool) -> bool {
		some := false
		for _, k in KINDS do some ||= holds(k, at) > 0
		if w := world_at(at.x, at.y); !some {
			if say do fmt.printfln("  left out at %.1f, %.1f km (%s, %.1f Myr): %s", at.x/1000, at.y/1000, SETTINGS[w.setting], w.age,
				"a young hotspot shield would stand here, and no kind makes one" if w.setting == .Hotspot && w.age < 1 else "no kind's host holds here")
			return false
		}
		u := f64(hash01(key, 1, world_seed + 1702))
		size := SIDES[0]*math.pow(1 - u*(1 - math.pow(SIDES[1]/SIDES[0], -2*KORCAK)), -0.5/KORCAK)
		for s in sites do size = min(size, 2*max(abs(at.x - s.at.x), abs(at.y - s.at.y)) - s.size)
		size = math.floor(size/2048)*2048
		for ; size >= SIDES[0]; size -= 2048 {
			ashore := false
			for c in ([8][2]f64{{-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}}) do ashore ||= world_at(at.x + c.x*size/2, at.y + c.y*size/2).inland > 0
			if !ashore do break
		}
		if size < SIDES[0] || max(abs(at.x - plates.mid.x), abs(at.y - plates.mid.y)) + size/2 > NEAR_SIDE/2 do return false
		append(sites, Site{at, size})
		return true
	}
	// Along the front and across the forearc, both ways round the trench's circle from the start island.
	from := math.atan2(o.y - plates.centre.y, o.x - plates.centre.x)
	for line, l in ([2][3]f64{{plates.setback, plates.front, 0}, {0.45*plates.setback, plates.forearc, 0.25*plates.setback}}) do for way in ([2]f64{1, -1}) {
		a := from
		for n in i32(1)..<40 {
			key := i32(l*1000) + i32(way)*n
			ring := (plates.radius - line[0] + line[2]*(2*f64(hash01(key, 2, world_seed + 1703)) - 1))*1000
			a += way*line[1]*(0.7 + 0.6*f64(hash01(key, 3, world_seed + 1703)))*1000/ring
			p := plates.centre + [2]f64{math.cos(a), math.sin(a)}*ring
			if max(abs(p.x - plates.mid.x), abs(p.y - plates.mid.y)) > NEAR_SIDE/2 do break
			place(&sites, p, key, say)
		}
	}
	// Over the hotspot, then along its track to the trench.
	for t, n := 0.0, i32(3000); t < min(plates.reach - 10_000, 1.5*NEAR_SIDE); t, n = t + plates.track*(0.8 + 0.4*f64(hash01(n, 3, world_seed + 1703)))*1000, n + 1 {
		place(&sites, plates.hotspot + plates.motion*t + [2]f64{-plates.motion.y, plates.motion.x}*3000*(2*f64(hash01(n, 2, world_seed + 1703)) - 1), n, say)
	}
	// On the shelf, anywhere a site fits.
	for n, placed := i32(0), 0; n < 400 && f64(placed) < math.round(plates.shelf); n += 1 {
		p := plates.mid + NEAR_SIDE*([2]f64{f64(hash01(n, 4, world_seed + 1703)), f64(hash01(n, 5, world_seed + 1703))} - 0.5)
		if world_at(p.x, p.y).setting == .Shelf do placed += int(place(&sites, p, 4000 + n, say))
	}

	// Each site takes the kind whose host it holds best, ties broken by a draw keyed by the kind's
	// name and weighted as the race's are; a kind its nearest neighbour has, or that has it as
	// nearest, is passed over for the next best. A site whose neighbours took every kind that holds
	// there is left out.
	kind := make([]int, len(sites), context.temp_allocator)
	kept := make([]bool, len(sites), context.temp_allocator)
	for &k in kept do k = true
	kind[0] = start
	nearest :: proc(sites: []Site, kept: []bool, i: int) -> (n: int) {
		n = -1
		for s, j in sites do if kept[j] && j != i && (n < 0 || math.hypot(s.at.x - sites[i].at.x, s.at.y - sites[i].at.y) < math.hypot(sites[n].at.x - sites[i].at.x, sites[n].at.y - sites[i].at.y)) do n = j
		return
	}
	for again := true; again; {
		again = false
		for i in 1..<len(sites) do if kept[i] {
			s, best, key := sites[i], f32(0), f32(-1)
			kind[i] = -1
			for k, r in KINDS {
				h := holds(r, s.at)
				taken := false
				for j in 0..<i do taken ||= kept[j] && kind[j] == r && (nearest(sites[:], kept, i) == j || nearest(sites[:], kept, j) == i)
				u := math.pow(hash01(i32(i), i32(fnv.fnv32a(transmute([]u8)k.name)), world_seed + 1704), 1/k.weight)
				if h > 0 && !taken && (h > best + 1e-4 || h > best - 1e-4 && u > key) do kind[i], best, key = r, h, u
			}
			if kind[i] < 0 {
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
	// The continent: its coast for 300 km round the start, closed far inland, and its range.
	clear(&continent.coast)
	clear(&continent.crest)
	mid := math.atan2(plates.mid.y - plates.centre.y, plates.mid.x - plates.centre.x)
	for k in -150..=150 {
		a := mid + f64(k)/(plates.radius - SHELF*plates.setback - plates.margin)
		d := [2]f64{math.cos(a), math.sin(a)}*1000
		append(&continent.coast, plates.centre + d*(plates.radius - coast_at(a)))
		append(&continent.crest, plates.centre + d*(plates.radius - coast_at(a) - plates.crest))
	}
	append(&continent.coast, plates.centre)
	continent.height = f32(plates.height)
	ashore := f64(1e12)
	for c in continent.coast do ashore = min(ashore, math.hypot(c.x - o.x, c.y - o.y))
	fmt.printfln("near the start: %d islands, off a continent whose coast is %.0f km away; this one stands on the %s, %.0f km from the volcanic front, where its kind's host holds %.2f; the wind from %.0f°",
		len(archipelago), ashore/1000, SETTINGS[archipelago[0].setting], world_at(o.x, o.y).front, holds(start, o), plates.wind)
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

// --archipelago=: form each island in turn with the one region's code, sample its heights into a
// picture 200 km across, then draw the plates and the continent's coast and name each island. False
// if no kind has the name given.
archipelago_map :: proc(path: string) {
	MAP, VIEW :: 3000, 200_000   // pixels, and the metres they cover: the square the islands are placed in and the continent's coast beyond it
	started := time.now()
	all := make([]int, len(formed))
	defer delete(all)
	for &a, i in all do a = i
	islands_done(islands_form(all, max(os.get_processor_core_count() - 1, 1), .Normal, false), all)   // side by side, each saying its line
	heights := make([]f32, MAP*MAP)
	defer delete(heights)
	pixel :: proc(px, py: int) -> [2]f64 { return plates.mid - VIEW/2 + ([2]f64{f64(px), f64(py)} + 0.5)*VIEW/MAP }
	tops := make([]f32, len(archipelago))
	defer delete(tops)
	for &f, i in formed {
		bind(&f)
		is := f.island
		for h in land.z[0] do tops[i] = max(tops[i], h)
		o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
		lo, hi := (o - is.size/2 - plates.mid + VIEW/2)*MAP/VIEW, (o + is.size/2 - plates.mid + VIEW/2)*MAP/VIEW
		for py in max(int(lo.y), 0)..<min(int(hi.y) + 1, MAP) do for px in max(int(lo.x), 0)..<min(int(hi.x) + 1, MAP) {
			if p := pixel(px, py) - o; max(abs(p.x), abs(p.y)) < is.size/2 do heights[py*MAP + px] = max(land_at(land.z[2], land.n/4, p.x, p.y), 0)
		}
		fmt.printfln("%d %s, %s, %.1f Myr, at %.1f, %.1f km; region %.1f km, highest %.0f m, formed in %.2f s",
			is.id, KINDS[is.kind].name, SETTINGS[is.setting], is.age, o.x/1000, o.y/1000, is.size/1000, tops[i], f.seconds)
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
	fmt.printfln("the continent's coast lies %.0f to %.0f km from the islands' middles; the crest of its range, %.0f m (a guess), %.0f to %.0f km, shows over the curve from the shore of %d of %d",
		ashore[0]/1000, ashore[1]/1000, continent.height, crest[0]/1000, crest[1]/1000, seen, len(archipelago))

	pixels := make([]u8, MAP*MAP*4)
	defer delete(pixels)
	for py in 0..<MAP do for px in 0..<MAP {
		h, p := heights[py*MAP + px], pixel(px, py)
		w := world_at(p.x, p.y)
		grey: f32
		if h > 0 {
			gx := heights[py*MAP + min(px + 1, MAP - 1)] - heights[py*MAP + max(px - 1, 0)]
			gz := heights[min(py + 1, MAP - 1)*MAP + px] - heights[max(py - 1, 0)*MAP + px]
			grey = (0.62 + 0.33*math.sqrt(min(h/1000, 1)))*clamp(0.85 + (-gx - gz)/120, 0.35, 1.25)
		} else if w.inland > 0 {
			grey = 0.50 if (px + py)%16 > 1 else 0.40   // the continent, hatched: a record, not yet formed
		} else {
			grey = 0.40 - 0.27*clamp(math.ln(max(w.depth, 5)/50)/math.ln(f32(7000.0/50)), 0, 1)
		}
		col := [3]f32{grey, grey, grey}
		// The trench, the volcanic front, the shelf's edge, the hotspot's track, the continent's coast and the crest of its range.
		if h <= 0 {
			if abs(w.inland) < 0.07 do col = {0.92, 0.90, 0.84}
			if abs(w.inland - f32(plates.crest)) < 0.07 do col = {0.80, 0.55, 0.30}
			if abs(w.trench) < 0.07 do col = {0.55, 0.12, 0.10}
			if abs(w.front) < 0.07 do col = {0.95, 0.30, 0.20}
			if abs(w.trench - f32(SHELF*plates.setback)) < 0.07 do col = {0.30, 0.75, 0.80}
			if w.track < 0.07 do col = {1.00, 0.60, 0.10}
		}
		for k in 0..<3 do pixels[(py*MAP + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
	}
	at :: proc(p: [2]f64) -> [2]int { return {int((p.x - plates.mid.x + VIEW/2)*MAP/VIEW), int((p.y - plates.mid.y + VIEW/2)*MAP/VIEW)} }
	// What a label must not cover: each island's land, the key, then each label written.
	boxes := make([dynamic][4]int, context.temp_allocator)
	for is in archipelago {
		q, r := at({f64(is.origin.x), f64(is.origin.y)}), int(0.4*is.size*MAP/VIEW)
		append(&boxes, [4]int{q.x - r, q.y - r, q.x + r, q.y + r})
	}
	append(&boxes, [4]int{0, 0, 1100, 210})
	c := at(continent.crest[len(continent.crest)/2])
	note := fmt.tprintf("THE CONTINENT, NOT YET FORMED: A RANGE ABOUT %.0f M HIGH, A GUESS", continent.height)
	c = {clamp(c.x - 6*len(note), 20, MAP - 20 - 12*len(note)), clamp(c.y + 12, 230, MAP - 60)}
	write(pixels, MAP, c.x, c.y, note, 3, {230, 225, 215})
	append(&boxes, [4]int{c.x, c.y, c.x + 12*len(note), c.y + 16})
	clear_of :: proc(boxes: [][4]int, b: [4]int, skip := -1) -> bool {
		if b.x < 0 || b.y < 0 || b.z > MAP || b.w > MAP do return false
		for o, j in boxes do if j != skip && !(o.z < b.x || o.x > b.z || o.w < b.y || o.y > b.w) do return false
		return true
	}
	// A tick each Myr along the track, and the hotspot ringed where it stands now.
	ring :: proc(pixels: []u8, q: [2]int, r0, r1: int) {
		for dy in -r1..=r1 do for dx in -r1..=r1 do if r := dx*dx + dy*dy; r >= r0*r0 && r <= r1*r1 && q.x + dx >= 0 && q.y + dy >= 0 && q.x + dx < MAP && q.y + dy < MAP {
			for k, j in ([3]u8{255, 160, 30}) do pixels[((q.y + dy)*MAP + q.x + dx)*4 + j] = k
		}
	}
	for m := 1.0; m*plates.speed*1000 < min(plates.reach, 1.5*VIEW); m += 1 {
		q := at(plates.hotspot + plates.motion*m*plates.speed*1000)
		ring(pixels, q, 0, 4)
		if b := ([4]int{q.x + 8, q.y + 6, q.x + 80, q.y + 21}); clear_of(boxes[:], b) {
			write(pixels, MAP, b.x, b.y, fmt.tprintf("%.0f MYR", m), 3, {255, 160, 30})
			append(&boxes, b)
		}
	}
	h := at(plates.hotspot)
	ring(pixels, h, 22, 26)
	write(pixels, MAP, h.x + 32, h.y - 7, "HOTSPOT, NOW", 3, {255, 160, 30})
	append(&boxes, [4]int{h.x + 30, h.y - 9, h.x + 32 + 12*12, h.y + 10})
	// Each island named on whichever side of it is clear: right, left, below, above.
	for is, i in archipelago {
		label := fmt.tprintf("%d %s, %s", is.id, KINDS[is.kind].name, SETTINGS[is.setting])
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
	for line, n in ([6]struct { name: string, ink: [3]u8 }{{"TRENCH", {200, 60, 50}}, {"VOLCANIC FRONT", {255, 90, 60}}, {"SHELF EDGE", {90, 200, 210}}, {"HOTSPOT TRACK, A TICK EACH MYR", {255, 160, 30}}, {"COAST OF THE CONTINENT", {235, 230, 215}}, {"CREST OF ITS RANGE", {205, 140, 75}}}) {
		write(pixels, MAP, 20, 56 + 26*n, line.name, 3, line.ink)
	}
	write(pixels, MAP, 20, 20, fmt.tprintf("SEED %d: THE %d ISLANDS NEAR THE START AND THE CONTINENT THEY LIE OFF, 200 KM ACROSS, NORTH UP. WIND AND SWELL FROM %.0f DEGREES", world_seed, len(archipelago), plates.wind), 3, {255, 255, 255})
	for y in MAP - 40..<MAP - 34 do for x in 20..<20 + 10_000*MAP/VIEW do for k in 0..<3 do pixels[(y*MAP + x)*4 + k] = 255
	write(pixels, MAP, 20, MAP - 30, "10 KM", 3, {255, 255, 255})
	write_png(path, pixels, MAP, MAP, false)
	fmt.printfln("the islands formed and drawn in %.1f s", time.duration_seconds(time.since(started)))
}
