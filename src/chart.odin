package main

import "base:builtin"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// The world's screen (docs/foundations/interface.md, section 5; step I-2): the known world's map
// with the islands near the start on it, panned and zoomed, with lenses that are the world's
// fields; an island clicked says what it is, in the hand's place and in the card's shape, and has
// the doors into play on it. The front door (door.odin) stands over the same map, moving slowly.
//
// The map is pictures, not parts. The known world is one, half a kilometre to a pixel, drawn from
// what the plates' history left (known.odin): the sea by its depth, and land the history made and
// nothing has formed, pale. Each island is another once it is formed, drawn as --map draws it
// (map_at, land_report.odin), and laid over the first where it stands. They are painted on a thread
// of their own as the world is made, handed to the frame's thread, and put on the GPU there; the
// frame only moves and scales them. A lens paints the known world again by one of the world's
// fields, and tints each island by its own figure.
//
//   top left      the world: its seed and what is known of it. Read its history will stand here.
//   top right     the lenses, and the key to the one that is on
//   lower left    the hand: the island chosen, and the doors into play: Found a hold, Walk the world
//   bottom right  the start, and the way back to the front door; over them, the world being made (door.odin)
//
// Keys, each a row of BINDS: Enter founds a hold on the island in the hand, W walks it, Home goes to
// the start, = and - zoom, Escape puts the island down and then goes to the front door. The arrows
// pan, as they do over the land. A drag pans too, the wheel zooms about the pointer, a click chooses.

// A lens of the world's map: a field of the world (FIELDS, fields.odin) read at a point of the
// world, in metres, and for a formed island its own figure where it has one.
World_Lens :: struct {
	name:  string,
	field: Field,   // whose colours and span it is painted in
	says:  string,
	at:    proc(x, z: f64) -> f32,
	isle:  proc(f: ^Formed) -> f32,   // nil: the island is painted as the world is at its middle
}
WORLD_LENSES := [?]World_Lens{
	{"Setting", .Setting, "Where the plates put each place.", proc(x, z: f64) -> f32 { return f32(world_at(x, z).setting) }, nil},
	{"Depth of the sea", .Depth, "How deep the sea stands over its floor: a trench, the forearc's ridge, the shelf rising to the mainland.", proc(x, z: f64) -> f32 { return world_at(x, z).depth }, nil},
	{"Rain", .Rain, "A year's rain on the sea, by how far north it lies; and on each island formed, what falls on its land.", proc(x, z: f64) -> f32 { l, _ := climate_latitude(x, z); return sea_rain(l) }, proc(f: ^Formed) -> f32 { return f.land.rained }},
	{"Warmth", .Temperature, "The year's mean in the air at the sea's level, by how far north a place lies.", proc(x, z: f64) -> f32 { l, _ := climate_latitude(x, z); return sea_mean(l) }, nil},
	{"Age of the land", .Age, "How long ago the land was made: a young volcano's, or the crust's.", proc(x, z: f64) -> f32 { return world_at(x, z).age }, nil},
	{"Rising", .Rising, "How fast the crust rises, or under nought sinks: fastest on the forearc's outer ridge.", proc(x, z: f64) -> f32 { return world_at(x, z).rising }, nil},
	{"The volcanic front", .Front, "How far each place lies from the line the arc's young volcanoes stand on.", proc(x, z: f64) -> f32 { return world_at(x, z).front }, nil},
	{"Crust", .Crust, "How thick the crust is: thin under the ocean, thicker under an arc, thickest under the mainland.", proc(x, z: f64) -> f32 { return world_at(x, z).crust }, nil},
}

// Where the plates put a place, in the words "an island ...".
SETTING_SAID := [Setting]string{.Open_Sea = "in the open sea", .Hotspot = "on a hotspot's track", .Forearc = "on the forearc", .Arc = "on the volcanic arc", .Back_Arc = "behind the arc", .Shelf = "on the mainland's shelf", .Continent = "on the mainland"}

// An island's card: what it is in a line and why in the next, then its depths.
Isle_Depth :: enum u8 { Land, Rock, Climate, Life, Places }
ISLE_DEPTHS := [Isle_Depth]string{.Land = "Land", .Rock = "Rock", .Climate = "Climate", .Life = "Life", .Places = "Places"}
Isle_Card :: struct {
	of:     int,    // the island it is of, -2 the mainland, -1 none
	formed: bool,   // as it was when the card was written: an island says more once formed
	title, sub, line: string,
	says:   [Isle_Depth]string,
}

MAINLAND :: -2
SHOAL :: 150   // metres deep the known world's picture draws the sea in an island's square, where the history has it shallower
SPAN_WORLD :: [2]f64{6_000, 1_400_000}   // metres across the picture's width, from an island's bay to the whole known world

// A picture painted and waiting for the frame's thread to put it on the GPU.
Painted :: struct { layer, lens: int, pixels: []u8, tint: Colour }

Chart :: struct {
	at:      [2]f64,   // the point of the world at the picture's middle, metres
	span:    f64,      // metres across the picture's width
	pick:    int,      // the island in the hand, MAINLAND, or -1
	depth:   Isle_Depth,
	lens:    int,      // the lens on, or -1
	card:    Isle_Card,
	scroll, over: f32, // how far the card's depth is scrolled, and how far it can be
	wide, high: f32,   // the picture, in pixels
	// The pictures, shared with the thread that paints them under the mutex.
	mutex:   sync.Mutex,
	painter: ^thread.Thread,
	stop:    bool,
	ready:   [dynamic]Painted,
	shown:   [dynamic]bool,   // for each island, its picture is on the GPU
	tints:   [dynamic]Colour, // and what the lens tints it
	known:   bool,            // the known world's picture is on the GPU
	lens_on: int,             // the lens the known world's picture was painted by, or -1
	waiting: int,             // pictures being painted or waiting to be put on the GPU
	homed:   bool,            // the view was put over this world's start, once
	brief:   bool,            // the world's panel says less, to leave the island's card its room
	card_at: Rect,            // where the card stands this frame; no width where there is none
}
chart := Chart{pick = -1, lens = -1, lens_on = -1, span = 240_000, card = {of = -1}}

// ---- pictures -------------------------------------------------------------------------------

// The painting thread: the known world first, and again whenever the lens changes; then each
// island as it is formed. Begun once a world's records are made, ended before they are put down.
chart_painter_begin :: proc() {
	c := &chart
	sync.atomic_store(&c.stop, false)
	sync.lock(&c.mutex)
	builtin.resize(&c.shown, len(formed))
	builtin.resize(&c.tints, len(formed))
	for &s in c.shown do s = false
	c.known, c.lens_on = false, -1
	sync.unlock(&c.mutex)
	c.painter = thread.create_and_start(proc() {
		c := &chart
		done := make([]bool, len(formed), context.temp_allocator)
		known, lens := false, -1
		for !sync.atomic_load(&c.stop) {
			want := sync.atomic_load(&c.lens)
			worked := false
			if !known || want != lens {
				sync.atomic_add(&c.waiting, 1)
				p := Painted{layer = -1, lens = want, pixels = known_paint(want)}
				known, lens, worked = true, want, true
				for &d in done do d = false   // each island's tint is the lens's
				sync.guard(&c.mutex)
				append(&c.ready, p)
			} else do for &f, i in formed do if !done[i] && is_formed(&f) {
				sync.atomic_add(&c.waiting, 1)
				p := Painted{layer = i, lens = lens}
				shown := false
				{
					sync.guard(&c.mutex)
					shown = c.shown[i]
				}
				if !shown do p.pixels = isle_paint(&f)   // its picture is painted once; a lens only tints it
				if lens >= 0 do p.tint = lens_colour(lens, &f)
				done[i], worked = true, true
				sync.guard(&c.mutex)
				append(&c.ready, p)
				break
			}
			if !worked do time.sleep(20*time.Millisecond)
		}
	}, priority = .Low)
}

chart_painter_end :: proc() {
	c := &chart
	if c.painter == nil do return
	sync.atomic_store(&c.stop, true)
	thread.join(c.painter)
	thread.destroy(c.painter)
	c.painter = nil
	sync.guard(&c.mutex)
	for p in c.ready do delete(p.pixels)
	clear(&c.ready)
	sync.atomic_store(&c.waiting, 0)
}

// Put what has been painted on the GPU. The frame's thread, before it draws.
chart_upload :: proc(g: ^Gpu) {
	c := &chart
	if !sync.try_lock(&c.mutex) do return
	ready := make([]Painted, len(c.ready), context.temp_allocator)
	copy(ready, c.ready[:])
	clear(&c.ready)
	sync.unlock(&c.mutex)
	for p in ready {
		if p.pixels != nil do picture_put(g, p.layer, len(c.shown), p.pixels)
		delete(p.pixels)
		if p.layer < 0 do c.known, c.lens_on = true, p.lens
		else if p.layer < len(c.shown) {
			c.tints[p.layer] = p.tint
			sync.guard(&c.mutex)
			c.shown[p.layer] = true
		}
		sync.atomic_sub(&c.waiting, 1)
	}
}

// Whether everything formed so far is drawn: the known world by the lens that is on, and every island formed.
chart_painted :: proc() -> bool {
	c := &chart
	if sync.atomic_load(&c.waiting) != 0 || !c.known || c.lens >= 0 && c.lens_on != c.lens do return false
	for &f, i in formed do if is_formed(&f) && !(i < len(c.shown) && c.shown[i]) do return false
	return true
}

// A new world is ordered: nothing of the old one is drawn from here on.
chart_forget :: proc() {
	c := &chart
	c.pick, c.lens, c.scroll, c.homed = -1, -1, 0, false
	c.card.of = -3   // no island's: the card is written afresh for whatever is taken next
	sync.guard(&c.mutex)
	for &s in c.shown do s = false
	c.known = false
}

// The colour a lens gives a value.
lens_paint :: proc(lens: int, v: f32) -> [3]f32 {
	row := WORLD_LENSES[lens]
	if row.field == .Setting {
		k := LOOK.kinds[clamp(int(v), 0, len(LOOK.kinds) - 1)]
		return {f32(k.r), f32(k.g), f32(k.b)}/255
	}
	return field_paint(&FIELDS[row.field], v, 0, 0)
}

// What a lens tints a formed island: its own figure, or the world's at its middle.
lens_colour :: proc(lens: int, f: ^Formed) -> Colour {
	row := WORLD_LENSES[lens]
	v := row.isle(f) if row.isle != nil else row.at(f64(f.island.origin.x), f64(f.island.origin.y))
	c := lens_paint(lens, v)
	return {u8(clamp(c.r, 0, 1)*255), u8(clamp(c.g, 0, 1)*255), u8(clamp(c.b, 0, 1)*255), 255}
}

// The known world's picture: the sea by its depth and the land the history made, pale, since
// nothing has formed it; or all of it by a lens. The squares islands stand in are left as sea,
// for the islands' own pictures. Worked in bands on the crew of threads forming leaves free.
known_paint :: proc(lens: int) -> []u8 {
	N :: PICTURE_KNOWN
	Job :: struct { lens: int, h: []f32, pixels: []u8 }
	job := Job{lens, make([]f32, N*N), make([]u8, N*N*4)}
	defer delete(job.h)
	km :: proc(px, py: int) -> [2]f32 { return ([2]f32{f32(px), f32(py)} + 0.5)*(WINDOW/N) - WINDOW/2 }
	bands :: proc(job: ^Job, work: proc(job: ^Job, lo, hi: int)) {
		BANDS :: 6
		Band :: struct { job: ^Job, work: proc(job: ^Job, lo, hi: int), lo, hi: int }
		pool: [BANDS]^thread.Thread
		for &t, i in pool {
			b := Band{job, work, N*i/BANDS, N*(i + 1)/BANDS}
			t = thread.create_and_start_with_poly_data(b, proc(b: Band) { b.work(b.job, b.lo, b.hi) }, priority = .Low)
		}
		for t in pool {
			thread.join(t)
			thread.destroy(t)
		}
	}
	bands(&job, proc(job: ^Job, lo, hi: int) {
		for py in lo..<hi do for px in 0..<N {
			at := km(px, py)
			k, _ := known_at(at)
			if k.h > -SHOAL {   // an island's square holds its own picture: the history's land and shallows there give way to it
				w := world_of(at)
				for is in archipelago do if max(abs(w.x - f64(is.origin.x)), abs(w.y - f64(is.origin.y))) < is.size/2 do k.h = -SHOAL
			}
			job.h[py*N + px] = k.h
		}
	})
	// The history's cells are 6 km and the known world's samples 2: smoothed over a few kilometres,
	// so that a slope crossing them is drawn as a slope and not as their steps.
	{
		R :: 5
		other := make([]f32, N*N)
		defer delete(other)
		from, to := job.h, other
		for pass in 0..<6 {
			down := pass%2 == 1
			for a in 0..<N {
				sum := f32(0)
				at :: #force_inline proc(v: []f32, a, b: int, down: bool) -> f32 { return v[clamp(b, 0, N - 1)*N + a] if down else v[a*N + clamp(b, 0, N - 1)] }
				for b in -R..=R do sum += at(from, a, b, down)
				for b in 0..<N {
					to[b*N + a if down else a*N + b] = sum/(2*R + 1)
					sum += at(from, a, b + R + 1, down) - at(from, a, b - R, down)
				}
			}
			from, to = to, from
		}
	}
	bands(&job, proc(job: ^Job, lo, hi: int) {
		L := &LOOK
		mix :: proc(a, b: Colour, t: f32) -> [3]f32 { return math.lerp([3]f32{f32(a.r), f32(a.g), f32(a.b)}, [3]f32{f32(b.r), f32(b.g), f32(b.b)}, t)/255 }
		for py in lo..<hi do for px in 0..<N {
			h := job.h[py*N + px]
			east, south := job.h[py*N + min(px + 1, N - 1)], job.h[min(py + 1, N - 1)*N + px]
			west, north := job.h[py*N + max(px - 1, 0)], job.h[max(py - 1, 0)*N + px]
			slope := (west - east + north - south)/(2*WINDOW/N)   // metres a kilometre, falling toward the south-east
			col: [3]f32
			if job.lens >= 0 {
				w := world_of(km(px, py))
				col = lens_paint(job.lens, WORLD_LENSES[job.lens].at(w.x, w.y))*(clamp(1 + slope/1500, 0.86, 1.1) if h > 0 else 1)   // the land's relief under the paint; the sea flat
				if (h > 0) != (east > 0) || (h > 0) != (south > 0) do col *= 0.45   // the coast, so the land can be found under the paint
			} else if h > 0 {
				col = linalg.lerp(land_colour(h)*clamp(0.82 + slope/700, 0.45, 1.25), mix(L.unformed, L.unformed, 0), f32(0.42))   // pale: known, and not formed
			} else {
				col = mix(L.seas[0], L.seas[1], math.sqrt(clamp(-h/6000, 0, 1)))*clamp(1 + slope/2500, 0.88, 1.1)
			}
			for j in 0..<3 do job.pixels[(py*N + px)*4 + j] = u8(clamp(col[j], 0, 1)*255)
			rim := f32(min(px, py, N - 1 - px, N - 1 - py))   // the known world ends without a line: its last 20 km clear to the sea's dark beyond
			job.pixels[(py*N + px)*4 + 3] = u8(255*smoothstep(0, 40, rim))
		}
	})
	return job.pixels
}

// An island's picture: its land as --map draws it, and its shallows, clearing to nothing where the
// sea deepens and toward its square's edge, so that the known world's sea shows round it.
isle_paint :: proc(f: ^Formed) -> []u8 {
	N :: PICTURE_ISLE
	bound(f)
	pixels := make([]u8, N*N*4)
	for py in 0..<N do for px in 0..<N {
		x, z := (f64(px) + 0.5)*region.size/N - region.size/2, (f64(py) + 0.5)*region.size/N - region.size/2
		col, h := map_at(x, z, nil, .Wetness, false)
		edge := 1 - f32(max(abs(x), abs(z)))/f32(region.size/2)
		a := f32(1) if h > 0 else clamp(1 + h/22, 0, 1)*smoothstep(0, 0.08, edge)
		for j in 0..<3 do pixels[(py*N + px)*4 + j] = u8(clamp(col[j], 0, 1)*255)
		pixels[(py*N + px)*4 + 3] = u8(a*255)
	}
	free_all(context.temp_allocator)
	return pixels
}

// ---- the view ---------------------------------------------------------------------------------

// A point of the world, metres, in the picture, pixels; and back.
chart_to :: proc(p: [2]f64) -> [2]f32 {
	c := &chart
	k := f64(c.wide)/c.span
	return {f32(f64(c.wide)/2 + (p.x - c.at.x)*k), f32(f64(c.high)/2 + (p.y - c.at.y)*k)}
}
chart_from :: proc(p: [2]f32) -> [2]f64 {
	c := &chart
	k := c.span/f64(c.wide)
	return c.at + {(f64(p.x) - f64(c.wide)/2)*k, (f64(p.y) - f64(c.high)/2)*k}
}

// Zoom by a factor, keeping the point of the world under a pixel where it is.
chart_zoom :: proc(by: f64, about: [2]f32) {
	c := &chart
	if c.wide == 0 do return
	under := chart_from(about)
	limits := SPAN_WORLD
	c.span = clamp(c.span*by, limits[0], limits[1])
	c.at += under - chart_from(about)
}

// Put the view over an island, with the sea round it; or over the islands near the start.
chart_go :: proc(island: int) {
	c := &chart
	if island < 0 || island >= len(archipelago) {
		c.at, c.span = world_frame.origin, 1.08*NEAR_SIDE*f64(c.wide)/f64(max(c.high, 1)) if c.wide > 0 else 2*NEAR_SIDE
		return
	}
	is := archipelago[island]
	c.at, c.span = {f64(is.origin.x), f64(is.origin.y)}, 2.6*is.size
}

// What lies at a point of the world: an island's square, the mainland, or nothing of note.
chart_under :: proc(p: [2]f64) -> int {
	for is in archipelago do if max(abs(p.x - f64(is.origin.x)), abs(p.y - f64(is.origin.y))) < max(is.size/2, 0.5*f64(px(LOOK.isle))*chart.span/f64(max(chart.wide, 1))) do return is.id
	if world_at(p.x, p.y).inland > 0 do return MAINLAND
	return -1
}

// The map: the known world's picture, the islands formed, a mark where one is still to be, and
// their names. `plain` leaves the names out, for the front door.
chart_map :: proc(plain: bool) {
	c, u, L := &chart, &play, &LOOK
	u.area = .Chart
	c.wide, c.high = screen.w, screen.h
	if !sync.atomic_load(&making.records) do return
	if c.known {
		side := f64(WINDOW)*1000
		lo := chart_to(world_of({0, 0}) - side/2)
		k := f32(f64(c.wide)/c.span*side)
		part(.Picture, {lo.x, lo.y, k, k}, id = "chart.known").uv = {0, 0, 1, 1}
		screen.items[len(screen.items) - 1].arg = 0
	}
	lensed := c.lens >= 0 && c.lens_on == c.lens
	for is, i in archipelago {
		at := chart_to({f64(is.origin.x), f64(is.origin.y)})
		side := f32(f64(c.wide)/c.span*is.size)
		if at.x + side/2 < 0 || at.y + side/2 < 0 || at.x - side/2 > c.wide || at.y - side/2 > c.high do continue
		if i < len(c.shown) && c.shown[i] {
			it := part(.Picture, {at.x - side/2, at.y - side/2, side, side}, id = "chart.isle")
			it.uv, it.arg = {0, 0, 1, 1}, i + 1
			if lensed do it.colour, it.state = c.tints[i], {.Faint}
		}
		mark := clamp(0.5*side, px(L.isle), 3*px(L.isle)) if !(i < len(c.shown) && c.shown[i]) else px(L.isle)
		if !(i < len(c.shown) && c.shown[i]) || side < 2*px(L.isle) {   // not formed yet, or too small in the picture to be seen: a ring where it stands
			part(.Ring, {at.x - mark/2, at.y - mark/2, mark, mark}, colour = L.brass if i == 0 else L.chalk, id = "chart.mark")
		}
		if c.pick == i {   // the island in the hand: brass corners round its square
			r, arm, t := max(side, 2*px(L.isle))/2 + px(1), max(px(3), side/10), px(L.bar)
			for sx in ([2]f32{-1, 1}) do for sy in ([2]f32{-1, 1}) {
				cx, cy := at.x + sx*r, at.y + sy*r
				part(.Fill, {min(cx, cx - sx*arm), cy - t/2, arm, t}, colour = L.brass, id = "chart.picked")
				part(.Fill, {cx - t/2, min(cy, cy - sy*arm), t, arm}, colour = L.brass)
			}
		}
		if plain || c.span > 700_000 do continue
		name := "the start" if i == 0 else kind_said(is.kind).short
		if !is_formed(&formed[i]) do name = fmt.tprintf("%s, not formed yet", name)
		w := text_wide(.Small, name)
		r := Rect{math.round(at.x - w/2), math.round(at.y + max(side, mark)/2 + px(1)), w, line_of(.Small)}
		part(.Fill, {r.x - px(1.5), r.y, r.w + px(3), r.h}, colour = L.said)
		part(.Text, r, name, .Small, L.brass if i == 0 || c.pick == i else L.chalk, id = "chart.name")
	}
	if !plain && len(continent.crest) > 0 && c.span > 150_000 {   // the land larger than an island, named where its range's crest runs
		at := chart_to(continent.crest[len(continent.crest)/2])
		name := "the mainland, not formed yet"
		w := text_wide(.Small, name)
		if at.x > 0 && at.y > 0 && at.x < c.wide && at.y < c.high {
			r := Rect{math.round(at.x - w/2), math.round(at.y), w, line_of(.Small)}
			part(.Fill, {r.x - px(1.5), r.y, r.w + px(3), r.h}, colour = L.said)
			part(.Text, r, name, .Small, L.brass if c.pick == MAINLAND else L.chalk, id = "chart.mainland")
		}
	}
}

// ---- the island's card ------------------------------------------------------------------------

chart_take :: proc(island: int) {
	c := &chart
	if island == c.pick do return
	c.pick, c.scroll, c.depth = island, 0, .Land
	if island >= 0 do forming_toward(island)   // its land and its neighbours' are made next
}

// What a card says of an island, written when it is taken in the hand and again once it is formed.
card_write :: proc() {
	c := &chart
	k := &c.card
	was := k.of
	now := c.pick >= 0 && is_formed(&formed[c.pick])
	if c.pick == was && now == k.formed do return
	delete(k.title); delete(k.sub); delete(k.line)
	for s in k.says do delete(s)
	k^ = {of = c.pick, formed = now}
	if c.pick == -1 do return
	if c.pick == MAINLAND {
		o := world_frame.origin
		ashore := f64(1e12)
		for p in continent.coast do ashore = min(ashore, math.hypot(p.x - o.x, p.y - o.y))
		k.title = strings.clone("The mainland")
		k.sub = fmt.aprintf("land larger than an island, %.0f km from the start", ashore/1000)
		k.line = strings.clone("The plates' history made it, and the world knows its coast and its heights. It is not formed as land yet, so no one can land there.")
		k.says[.Land] = fmt.aprintf("The crest of its range stands about %.0f m over the sea. The islands' animals came from it: every kind the islands have is taken to live there, until it is formed and can say.", continent.height)
		return
	}
	is := archipelago[c.pick]
	f := &formed[c.pick]
	said := kind_said(is.kind)
	o, start := [2]f64{f64(is.origin.x), f64(is.origin.y)}, world_frame.origin
	k.title = strings.clone(capital(said.one))
	far := math.hypot(o.x - start.x, o.y - start.y)
	where_ := "the start" if c.pick == 0 else fmt.tprintf("%.0f km %s of the start", far/1000, compass(o.x - start.x, o.y - start.y))
	k.sub = fmt.aprintf("%.0f km across, %s, %s", is.size/1000, where_, SETTING_SAID[is.setting])
	k.line = strings.clone(said.made)

	b := strings.builder_make(context.temp_allocator)
	rec := record_of(is)
	// Land.
	if now {
		bound(f)
		fmt.sbprintf(&b, "%.0f km² of land, its highest ground %.0f m over the sea. ", survey.land, land.grid.z[survey.top])
	} else if sync.atomic_load(&making.doing[c.pick]) != 0 {
		fmt.sbprintf(&b, "Its land is being formed now. ")
	} else {
		before := 0
		for &g, i in formed do if i != c.pick && !is_formed(&g) && islands_apart(i, c.pick) < islands_apart(c.pick, c.pick) + 1 do before += 1
		fmt.sbprintf(&b, "Its land is not formed yet: it is made when its turn comes. ")
	}
	fmt.sbprintf(&b, "Its land was made %s ago. Over the last half million years its crust %s.", myr_words(is.age),
		fmt.tprintf("rose %.2f mm a year", rec.past[0]) if rec.past[0] > 0.005 else fmt.tprintf("sank %.2f mm a year", -rec.past[0]) if rec.past[0] < -0.005 else "neither rose nor sank")
	k.says[.Land] = strings.clone(strings.to_string(b))
	// Rock.
	strings.builder_reset(&b)
	if now {
		bound(f)
		fmt.sbprintf(&b, "Its rock tells of %s.", region.story.name)
		first := true
		for t, m in survey.rocks do if t.cells*50 >= len(land.grid.order) {
			fmt.sbprintf(&b, "%s %s %d%%", " At the surface:" if first else ",", mat_words(m), t.cells*100/len(land.grid.order))
			first = false
		}
		if !first do fmt.sbprintf(&b, ".")
	} else do fmt.sbprintf(&b, "Its rock is read from where it stands when it is formed.")
	if rec.on do fmt.sbprintf(&b, " It stands on the foot of a volcano that began %s ago and built %.0f m over the ground under it.", myr_words(rec.vent.born), rec.vent.built)
	k.says[.Rock] = strings.clone(strings.to_string(b))
	// Climate: from where it stands, as forming works it out (climate_init).
	strings.builder_reset(&b)
	latitude, truly := climate_latitude(o.x, o.y)
	offshore := max(-world_at(o.x, o.y).inland, 0)
	mean, swing := sea_mean(latitude), sea_swing(latitude, offshore)
	fmt.sbprintf(&b, "At %.1f° N. At the sea's level the year's mean is %.1f °C, %.1f in its coldest month and %.1f in its warmest. %.0f mm of rain a year fall on the sea round it", truly, mean, mean - swing, mean + swing, sea_rain(latitude))
	if now do fmt.sbprintf(&b, ", and %.0f on its land", f.land.rained)
	fmt.sbprintf(&b, ". The wind and the swell come from the %s.", compass(math.sin(math.to_radians(world_frame.wind)), -math.cos(math.to_radians(world_frame.wind))))
	k.says[.Climate] = strings.clone(strings.to_string(b))
	// Life: who reached it, and why or why not (arrivals.odin).
	strings.builder_reset(&b)
	for row, d in DISPERSAL {
		a := arrivals[c.pick][d]
		from := "the mainland" if a.from < 0 else kind_said(archipelago[a.from].kind).one
		sea := fmt.tprintf("%.0f km of sea", a.open) if a.open >= 10 else fmt.tprintf("%.1f km of sea", a.open)
		if a.reached {
			how := fmt.tprintf("walked from %s over ground the sea bared when it stood lower", from) if a.way == .Walked else fmt.tprintf("%s from %s across %s", WAYS[a.way], from, sea)
			fmt.sbprintf(&b, "The %s %s%s.", row.name, how, ", further than it is sure to cross: the seed's draw let it" if a.chance < 1 && a.way != .Walked else "")
			if now {
				bound(f)
				fmt.sbprintf(&b, " %s", "It lives here." if kept(row.name) else "The island cannot keep it.")
			}
		} else {
			fmt.sbprintf(&b, "No %s: the nearest land with it, %s, lies across %s, and it %s %.0f km at most%s.", row.name, from, sea, ACROSS[row.way], row.most, ", so it might have crossed, and the seed's draw said no" if a.chance > 0 else "")
		}
		fmt.sbprintf(&b, "\n")
	}
	k.says[.Life] = strings.clone(strings.trim_right(strings.to_string(b), "\n"))
	// Places: its named places, once it has them.
	if now && len(f.places) > 0 {
		strings.builder_reset(&b)
		for p, i in f.places {
			why, _, _ := strings.partition(f.candidates[p.c].why, ";")
			fmt.sbprintf(&b, "%s%s: %s.", "" if i == 0 else "\n", p.name, why)
		}
		k.says[.Places] = strings.clone(strings.to_string(b))
	}
}

// So many million years in words.
myr_words :: proc(myr: f32) -> string {
	if myr < 0.95 do return fmt.tprintf("%.0f thousand years", math.round(myr*100)*10)
	return fmt.tprintf("%.1f million years", myr) if myr < 10 else fmt.tprintf("%.0f million years", myr)
}

// Why play cannot begin on an island yet, or "" where it can.
enter_waits :: proc(island: int) -> string {
	if island < 0 do return ""
	if world_enterable(island) do return ""
	if !is_formed(&formed[island]) do return "Its land is still being formed." if !making.stopped else "Its land is not formed, and the making is stopped."
	n := 0
	for &f, i in formed do if !is_formed(&f) && islands_apart(i, island) <= making.near_km*1000 do n += 1
	return fmt.tprintf("%s of the islands within %.0f km of it %s still to be formed.", capital(number_words(n)), making.near_km, "is" if n == 1 else "are")
}

// Lower left: the island in the hand, in the card's shape, and the doors into play.
isle_build :: proc() {
	c, u, L := &chart, &play, &LOOK
	u.area = .Hand
	card_write()
	k := &c.card
	c.brief, c.card_at = false, {}
	if k.of == -1 do return
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x, foot := px(L.margin), screen.h - px(L.margin)
	tabs: [Isle_Depth]bool
	count := 0
	for d in Isle_Depth {
		tabs[d] = k.says[d] != ""
		count += int(tabs[d])
	}
	if !tabs[c.depth] do c.depth = .Land
	isle := k.of >= 0
	waits := enter_waits(k.of)
	head := px(L.block_large)
	beside := inner - head - px(4)
	head = max(head, line_of(.Title) + text_high(.Body, k.sub, beside))
	line_high := text_high(.Body, k.line, inner)
	tabs_high := line_of(.Body) + px(1.5) + px(2.5) if count > 1 else 0
	doors := (text_high(.Body, waits, inner) + px(2) if waits != "" else 0) + px(L.button) if isle else 0
	fixed := 2*px(L.pad.y) + head + px(L.space) + line_high + px(L.space) + tabs_high + (px(4) + doors if isle else 0)
	longest := px(L.card_high[0]) if isle else 0
	for d in Isle_Depth do if tabs[d] do longest = max(longest, text_high(.Small, k.says[d], inner - px(3)))
	// As deep as its longest depth, where the world's own panel leaves it room; where it does not, that panel says less.
	room := foot - (px(L.margin) + world_high(true) + px(4)) - fixed
	c.brief = room < min(longest, px(L.card_high[0]))
	if c.brief do room = foot - (px(L.margin) + world_high(false) + px(4)) - fixed
	depth := max(min(longest, room), px(8))
	r := Rect{x, foot - fixed - depth, w, fixed + depth}
	c.card_at = r
	part(.Panel, r, id = "isle")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	square := Rect{cx, y, px(L.block_large), px(L.block_large)}
	part(.Fill, square, colour = L.brass)
	part(.Fill, {square.x + 1, square.y + 1, square.w - 2, square.h - 2}, colour = L.seas[1])
	if isle && k.of < len(c.shown) && c.shown[k.of] {   // the island itself, as the map has it
		it := part(.Picture, {square.x + 1, square.y + 1, square.w - 2, square.h - 2}, id = "isle.picture")
		it.uv, it.arg = {0.08, 0.08, 0.92, 0.92}, k.of + 1
	} else if isle {
		m := px(L.isle)*1.5
		part(.Ring, {square.x + (square.w - m)/2, square.y + (square.h - m)/2, m, m}, colour = L.chalk)
	}
	tx := cx + px(L.block_large) + px(4)
	words(tx, y, k.title, .Title, id = "isle.title")
	words(tx, y + line_of(.Title), k.sub, .Body, L.ash, "isle.sub", beside)
	y += head + px(L.space)
	y += words(cx, y, k.line, .Body, {}, "isle.line", inner) + px(L.space)
	if count > 1 {
		tx = cx
		for d in Isle_Depth do if tabs[d] {
			tw := text_wide(.Body, ISLE_DEPTHS[d])
			part(.Tab, {tx, y, tw, line_of(.Body) + px(1.5)}, ISLE_DEPTHS[d], .Body, {}, {.Chosen} if d == c.depth else {}, .Isle_Depth, int(d), id = "isle.tab")
			tx += tw + px(L.tab_gap)
		}
		y += line_of(.Body) + px(1.5)
		part(.Rule, {cx, y - 1, inner, 1}, colour = L.edge)
		y += px(2.5)
	}
	box := Rect{cx, y, inner, depth}
	u.clip = box
	all := text_high(.Small, k.says[c.depth], inner - px(3))
	c.over = max(all - depth, 0)
	c.scroll = clamp(c.scroll, 0, c.over)
	part(.Text, {cx, y - c.scroll, inner - px(3), all}, k.says[c.depth], .Small, L.ash, {.Wrap}, id = "isle.says")
	u.clip = {}
	part(.Fill, box, colour = {}, state = {.Solid})   // the wheel over it scrolls it
	if c.over > 0 do part(.Thumb, {cx + inner - px(1.5), y + depth*c.scroll/all, px(1.5), depth*depth/all}, id = "isle.thumb")
	y += depth
	if !isle do return
	// The doors. Read its history will stand in the world's own panel, top left, once the world has one.
	y += px(4)
	if waits != "" do y += words(cx, y, waits, .Body, L.ash, "isle.waits", inner) + px(2)
	half := math.floor((inner - px(L.gap))/2)
	door_button({cx, y, half, px(L.button)}, "Found a hold", .Found, 0, "isle.found", "Land the party on this island, where the land's rule for a landing puts it, and lead it from above.", main = waits == "", faint = waits != "")
	door_button({cx + inner - half, y, half, px(L.button)}, "Walk the world", .Roam, 0, "isle.walk", "Stand on this island on foot, with no party: the bank of its largest river.", faint = waits != "")
}

// Top left: the world, and what is known of it. Where the island's card needs the room, its name and
// the picture's scale alone.
world_words :: proc() -> (title, sub, across: string, wide: f32) {
	title = fmt.tprintf("The world of seed %d", making.seed)
	known := sync.atomic_load(&making.records)
	sub = world_says() if known else "Nothing of it is known yet."
	across = fmt.tprintf("The picture is %.0f km across. Pale land is known from the plates' history and not formed yet.", chart.span/1000) if known else "Its map is drawn when the plates' history has run."
	wide = max(text_wide(.Great, title), px(LOOK.hand_wide) - 2*px(LOOK.pad.x))
	return
}
world_high :: proc(full: bool) -> f32 {
	_, sub, across, wide := world_words()
	return 2*px(LOOK.pad.y) + line_of(.Great) + px(1) + (text_high(.Body, sub, wide) + px(1.5) if full else 0) + text_high(.Small, across, wide)
}
world_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Place
	title, sub, across, wide := world_words()
	r := Rect{px(L.margin), px(L.margin), wide + 2*px(L.pad.x), world_high(!chart.brief)}
	part(.Panel, r, id = "world")
	x, y := r.x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(x, y, title, .Great, id = "world.title") + px(1)
	if !chart.brief do y += words(x, y, sub, .Body, L.ash, "world.says", wide) + px(1.5)
	words(x, y, across, .Small, L.ash, "world.across", wide)
	u.place_foot = r.y + r.h
}

// Top right: the lenses, and the key to the one that is on.
chart_lenses :: proc(foot: f32) {
	c, u, L := &chart, &play, &LOOK
	u.area = .Lenses
	w := px(L.chart_wide)
	inner := w - 2*px(L.pad.x)
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	x, y := screen.w - px(L.margin) - w, px(L.margin)
	first := len(screen.items)
	part(.Panel, {x, y, w, 0}, id = "lenses")
	cx, cy := x + px(L.pad.x), y + px(L.pad.y)
	cy += words(cx, cy, "Lenses", .Small, L.ash, "lenses.title") + px(2.5)
	for l, i in WORLD_LENSES {
		part(.Chip, {cx, cy, inner, chip}, l.name, .Body, {}, {.Chosen} if c.lens == i else {}, .Chart_Lens, i, "", "lens.row", l.says)
		cy += chip + px(L.gap)
	}
	cy -= px(L.gap)
	key_high := f32(0)   // its key, where there is room for it under the choices: what the pointer rests on says the figure either way
	if c.lens >= 0 {
		row := WORLD_LENSES[c.lens]
		key_high = px(L.space) + text_high(.Small, row.says, inner) + px(2) + (f32(len(Setting))*line_of(.Small) if row.field == .Setting else px(3) + px(1) + line_of(.Small))
	}
	if c.lens >= 0 && cy + key_high + px(L.pad.y) <= foot {   // a ramp from one end to the other, or each setting by name
		row := WORLD_LENSES[c.lens]
		paint := FIELDS[row.field]
		cy += px(L.gap)
		cy += px(L.space) - px(L.gap)
		cy += words(cx, cy, row.says, .Small, L.ash, "lens.says", inner) + px(2)
		byte :: proc(k: [3]f32) -> Colour { return {u8(clamp(k.r, 0, 1)*255), u8(clamp(k.g, 0, 1)*255), u8(clamp(k.b, 0, 1)*255), 255} }
		if row.field == .Setting {
			for name, s in SETTINGS {
				part(.Fill, {cx, cy + px(0.75), px(L.block), px(L.block)}, colour = L.kinds[int(s)])
				cy += words(cx + px(L.block) + px(2), cy, name, .Small, {}, "lens.kind")
			}
		} else {
			STEPS :: 32
			for i in 0..<STEPS do part(.Fill, {cx + math.floor(inner*f32(i)/STEPS), cy, math.ceil(inner/STEPS), px(3)}, colour = byte(math.lerp(paint.from_colour, paint.to_colour, f32(i)/(STEPS - 1))))
			cy += px(3) + px(1)
			lo, hi := paint.lo, paint.hi
			if paint.paint == .Log do lo, hi = math.pow(10, lo), math.pow(10, hi)
			low, high := fmt.tprintf("%.4g%s", lo, paint.unit), fmt.tprintf("%.4g%s", hi, paint.unit)
			words(cx, cy, low, .Small, {}, "lens.low")
			words(cx + inner - text_wide(.Small, high), cy, high, .Small, {}, "lens.high")
			cy += line_of(.Small)
		}
	}
	screen.items[first].rect.h = cy + px(L.pad.y) - y
}

// Bottom right: the start, and the way back to the front door. Returns where they begin.
chart_ways :: proc() -> (top: f32) {
	u, L := &play, &LOOK
	u.area = .Lists
	Way :: struct { name, id, tip: string, act: Act, key: string }
	ways := [2]Way{
		{"The start", "ways.start", "Put the view over the islands near the start.", .Chart_Home, door_key(.Chart_Home)},
		{"Front door", "ways.door", "Back to the front door. The world goes on being made.", .Door_Back, door_key(.Door_Back)},
	}
	wide := f32(0)
	for k in ways do wide += button_wide(k.name, k.key, .Body, L.know_pad)
	r := Rect{screen.w - px(L.margin) - wide, screen.h - px(L.margin) - px(L.button), wide, px(L.button)}
	part(.Panel, r, id = "ways")
	x := r.x
	for k in ways {
		w := button_wide(k.name, k.key, .Body, L.know_pad)
		part(.Know, {x, r.y, w, r.h}, k.name, .Body, {}, {}, k.act, 0, k.key, k.id, k.tip)
		x += w
	}
	return r.y
}

// What the pointer rests on, on the map: an island, the mainland, or with a lens on, what the lens says there.
chart_tip :: proc(pointer: [2]f32) -> string {
	c := &chart
	if !sync.atomic_load(&making.records) || c.wide == 0 do return ""
	p := chart_from(pointer)
	under := chart_under(p)
	if c.lens >= 0 {
		row := WORLD_LENSES[c.lens]
		v := row.at(p.x, p.y)
		if under >= 0 && row.isle != nil && is_formed(&formed[under]) do v = row.isle(&formed[under])
		if row.field == .Setting do return SETTINGS[Setting(clamp(int(v), 0, len(Setting) - 1))]
		return fmt.tprintf("%.4g%s", v, FIELDS[row.field].unit)
	}
	if under >= 0 do return kind_said(archipelago[under].kind).one
	if under == MAINLAND do return "the mainland"
	return ""
}

// How tall the lenses' choices stand, without the key to the one that is on.
lenses_high :: proc() -> f32 {
	L := &LOOK
	return 2*px(L.pad.y) + line_of(.Small) + px(2.5) + f32(len(WORLD_LENSES))*(line_of(.Body) + 2*px(L.chip_pad.y) + px(L.gap)) - px(L.gap)
}

// The world's screen, listed. Where the picture is small for the interface's size, the parts give way
// in an order: the world's panel says less before the island's card loses its depth; the world being
// made is told in brief before the lenses lose their choices; and the lens's key goes before either.
chart_build :: proc() {
	c, L := &chart, &LOOK
	c.wide, c.high = screen.w, screen.h
	records := sync.atomic_load(&making.records)
	if !c.homed && records {   // a world just known: the islands near its start, and the start in the hand
		c.homed = true
		chart_go(-1)
		chart_take(0)
	}
	chart_map(false)
	c.brief, c.card_at = false, {}
	if records do isle_build()
	world_build()
	top := chart_ways()
	wide := screen.w - 2*px(L.margin) - (c.card_at.w + px(2) if c.card_at.w > 0 else 0)
	first := len(screen.items)
	made := making_build(screen.w - px(L.margin), top - px(2), wide, false)
	if made.h > 0 && made.y - px(2) - px(L.margin) < lenses_high() {
		builtin.resize(&screen.items, first)
		made = making_build(screen.w - px(L.margin), top - px(2), wide, true)
	}
	if records do chart_lenses((made.y if made.h > 0 else top) - px(2))
}
