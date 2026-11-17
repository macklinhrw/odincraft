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
//   top left      the world: its seed, and what there is in it
//   right         what to know: the islands there are to choose from, a row each with its picture and
//                 its figures, and the mainland; under them the lenses, behind their button
//   lower left    the hand: the island chosen, as a card of rows, and the doors into play
//   bottom right  all the islands, the lenses, and the way back to the front door; over them, the
//                 world being made (door.odin)
//
// The screen opens framed on the islands there are, the start in the hand. An island taken in the
// hand is gone to: it fills the part of the picture no panel stands on, so its relief, its streams
// and its coast can be read. Keys, each a row of BINDS: Enter lands the party on the island in the
// hand, W walks it, Home shows all the islands, = and - zoom, L opens the lenses, Escape puts the
// island down and then goes to the front door. The arrows pan, as they do over the land. A drag pans
// too, the wheel zooms about the pointer, a click chooses.

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
	{"Volcanic front", .Front, "How far each place lies from the line the arc's young volcanoes stand on.", proc(x, z: f64) -> f32 { return world_at(x, z).front }, nil},
	{"Crust", .Crust, "How thick the crust is: thin under the ocean, thicker under an arc, thickest under the mainland.", proc(x, z: f64) -> f32 { return world_at(x, z).crust }, nil},
}

// Where the plates put a place, in the words "an island ...".
SETTING_SAID := [Setting]string{.Open_Sea = "in the open sea", .Hotspot = "on a hotspot's track", .Forearc = "on the forearc", .Arc = "on the volcanic arc", .Back_Arc = "behind the arc", .Shelf = "on the mainland's shelf", .Continent = "on the mainland"}

// An island's card: its name and what it is, then its depths, each a list of rows: a thing, a word or
// a figure, and the why, which is said beside the pointer and under the row once it is chosen.
Isle_Depth :: enum u8 { Land, Water, Rock, Climate, Life, Places }
ISLE_DEPTHS := [Isle_Depth]string{.Land = "Land", .Water = "Water", .Rock = "Rock", .Climate = "Climate", .Life = "Life", .Places = "Places"}
Card_Row :: struct {
	thing, says, why: string,
	sign:  Sign,     // a disc where it is well, a triangle where a founder should look twice
	block: Colour,   // a rock or a wood shown as a block of its own colour on the map
	faint: bool,     // not known yet, or not there
	named: string,   // a place's card (landing.odin): what the row is called among the cautions, where it is one
}
Isle_Card :: struct {
	of:     int,    // the island it is of, a large land's pick (MAINLAND and below), or -1 for none
	formed: bool,   // as it was when the card was written: an island says more once formed
	pieces: int,    // the large land's pieces formed when it was written
	stands: int,    // and how the large land stood (land_stands)
	title, sub: string,
	rows:   [Isle_Depth][dynamic]Card_Row,
}

MAINLAND :: -2   // the pick of the large land nearest the start; the next nearest is -3, and so on down `lands` (continents.odin)
SHOAL :: 150   // metres deep the known world's picture draws the sea in an island's square, where the history has it shallower
SPAN_WORLD :: [2]f64{4_000, 1_400_000}   // metres across the picture's width, from an island's bay to the whole known world
MASS_TILES :: 4   // a large land's picture is so many tiles along a side at the most, each an island's picture across

// A picture painted and waiting for the frame's thread to put it on the GPU.
Painted :: struct { layer, lens: int, pixels: []u8, tint: Colour }

Chart :: struct {
	at:      [2]f64,   // the point of the world at the picture's middle, metres
	span:    f64,      // metres across the picture's width
	to_at:   [2]f64,   // where the view is going, and how wide: it goes there over a third of a second
	to_span: f64,
	going:   bool,
	pick:    int,      // the island in the hand, a large land's pick (MAINLAND and below), or -1
	depth:   Isle_Depth,
	row:     int,      // the row of the card's depth that says its why, or -1
	lens:    int,      // the lens on, or -1
	lenses:  bool,     // the lenses' choices are open
	card:    Isle_Card,
	scroll, over: f32, // how far the card's depth is scrolled, and how far it can be
	list_scroll, list_over: f32,   // and the list of islands
	wide, high: f32,   // the picture, in pixels
	free:    Rect,     // the part of it no panel stands on: where the land is framed
	// The pictures, shared with the thread that paints them under the mutex.
	mutex:   sync.Mutex,
	painter: ^thread.Thread,
	stop:    bool,
	ready:   [dynamic]Painted,
	shown:   [dynamic]bool,   // for each island and each tile of a large land, its picture is on the GPU
	tints:   [dynamic]Colour, // and what the lens tints it
	tiles:   [dynamic][3]int, // the large lands' tiles that hold land, by column, row and the land's place in `lands`; each a layer after the islands'
	known:   bool,            // the known world's picture is on the GPU
	lens_on: int,             // the lens the known world's picture was painted by, or -1
	waiting: int,             // pictures being painted or waiting to be put on the GPU
	homed:   bool,            // the view was put over this world's islands, once
	card_at: Rect,            // where the card stands this frame; no width where there is none
	door:    bool,            // a picture kept from the last run stands in the start island's layer (door.odin)
}
chart := Chart{pick = -1, lens = -1, lens_on = -1, row = -1, span = 240_000, card = {of = -1}}

// ---- pictures -------------------------------------------------------------------------------

// The painting thread: the known world first, and again whenever the lens changes; then each
// island as it is formed. Begun once a world's records are made, ended before they are put down.
chart_painter_begin :: proc() {
	c := &chart
	sync.atomic_store(&c.stop, false)
	sync.lock(&c.mutex)
	// The large lands' tiles that hold land, where a coarse stage stands: each a layer after the islands'.
	clear(&c.tiles)
	for &m, i in lands do if mass_listed(&m) {
		st, tiled := &m.store, land_tiled(&m)
		land := make([]bool, tiled*tiled, context.temp_allocator)
		for slot, sq in st.slot do if slot >= 0 {   // a square the coarse stage kept: land, or sea beside it
			land[min((sq/st.m*SQUARE + SQUARE/2)*tiled/st.n, tiled - 1)*tiled + min((sq%st.m*SQUARE + SQUARE/2)*tiled/st.n, tiled - 1)] = true
		}
		for l, t in land do if l do append(&c.tiles, [3]int{t%tiled, t/tiled, i})
	}
	builtin.resize(&c.shown, len(archipelago) + len(c.tiles))
	builtin.resize(&c.tints, len(archipelago) + len(c.tiles))
	for &s, i in c.shown do s = c.door && i == 0   // a picture kept from the last run stands until this run's is painted
	c.known, c.lens_on = false, -1
	sync.unlock(&c.mutex)
	c.painter = thread.create_and_start(proc() {
		c := &chart
		isles := len(archipelago)
		done := make([]bool, isles + len(c.tiles), context.temp_allocator)
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
			} else do for i in 0..<len(done) do if !done[i] && (i >= isles || is_formed(&formed[i])) {
				sync.atomic_add(&c.waiting, 1)
				p := Painted{layer = i, lens = lens}
				shown := false
				{
					sync.guard(&c.mutex)
					shown = c.shown[i] && !(c.door && i == 0)
				}
				if !shown do p.pixels = isle_paint(&formed[i]) if i < isles else mass_paint(c.tiles[i - isles])   // its picture is painted once; a lens only tints it
				if i == 0 && p.pixels != nil do door_keep(p.pixels)   // kept for the front door of the next run (door.odin)
				if lens >= 0 && i < isles do p.tint = lens_colour(lens, &formed[i])
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
		layers := ui.layers
		if p.pixels != nil do picture_put(g, p.layer, len(c.shown), p.pixels)
		if ui.layers != layers && c.door && p.layer != 0 && door.kept_pixels != nil do picture_put(g, 0, len(c.shown), door.kept_pixels)   // the pictures were made again with more layers: the kept one is put back
		delete(p.pixels)
		if p.layer < 0 do c.known, c.lens_on = true, p.lens
		else if p.layer < len(c.shown) {
			c.tints[p.layer] = p.tint
			sync.guard(&c.mutex)
			c.shown[p.layer] = true
			if p.layer == 0 && p.pixels != nil {
				c.door = false
				delete(door.kept_pixels)
				door.kept_pixels = nil
			}
		}
		sync.atomic_sub(&c.waiting, 1)
	}
}

// Whether everything formed so far is drawn: the known world by the lens that is on, and every island formed.
chart_painted :: proc() -> bool {
	c := &chart
	if sync.atomic_load(&c.waiting) != 0 || !c.known || c.lens >= 0 && c.lens_on != c.lens do return false
	if c.door do return false
	for &f, i in formed[:islands_count()] do if is_formed(&f) && !(i < len(c.shown) && c.shown[i]) do return false
	for i in len(archipelago)..<len(c.shown) do if !c.shown[i] do return false
	return true
}

// A new world is ordered: nothing of the old one is drawn from here on.
chart_forget :: proc() {
	c := &chart
	c.pick, c.lens, c.scroll, c.homed, c.row, c.list_scroll, c.going, c.door = -1, -1, 0, false, -1, 0, false, false
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
				// A large land whose coarse stage stands is drawn from that, finer: the history's land gives way to it.
				if k.h > 0 && len(chart.tiles) > 0 {
					u, v := clamp(int((at.x + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1), clamp(int((at.y + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1)
					for &m in lands do if m.ready && known.mass[v*KNOWN_N + u] == m.mass do k.h = -SHOAL
				}
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
				col = linalg.lerp(land_colour(h)*clamp(0.82 + slope/700, 0.45, 1.25), [3]f32{f32(L.unformed.r), f32(L.unformed.g), f32(L.unformed.b)}/255, f32(0.42))   // pale: known, and not formed
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

// How many tiles a large land's picture is along a side.
land_tiled :: proc(m: ^Landmass) -> int { return clamp(int(math.ceil(m.side/128_000)), 1, MASS_TILES) }

// A tile of a large land's picture: its coarse stage as it is kept (continents.odin, kept.odin), the
// whole of it on cells 64 m across under the sea as it stands today, drawn as the islands are, by its
// height and lit, with the water its larger valleys carry; its shallows clear to nothing, so that
// the known world's sea shows round it.
mass_paint :: proc(tile: [3]int) -> []u8 {
	N :: PICTURE_ISLE
	m := &lands[tile.z]
	st := &m.store
	pixels := make([]u8, N*N*4)
	per := f64(st.n)/f64(land_tiled(m))/N   // cells of the lattice to a pixel
	at :: proc(st: ^Store, x, y: f64) -> f32 { return store_now(st, clamp(int(x), 0, st.n - 1), clamp(int(y), 0, st.n - 1)) }
	for py in 0..<N do for px in 0..<N {
		x, y := (f64(tile.x*N + px) + 0.5)*per, (f64(tile.y*N + py) + 0.5)*per
		h := at(st, x, y)
		slope := (at(st, x - per, y) - at(st, x + per, y) + at(st, x, y - per) - at(st, x, y + per))/f32(2*per*64)   // rise over run, falling toward the south-east
		col: [3]f32
		a := f32(1)
		if h <= 0 {
			col = math.lerp([3]f32{0.35, 0.62, 0.80}, [3]f32{0.08, 0.22, 0.42}, clamp(-h/30, 0, 1))
			a = clamp(1 + h/40, 0, 1)
		} else {
			t := math.sqrt(clamp(h/1500, 0, 1))   // as an island's map (map_at), its heights spread over a range's
			col = math.lerp(math.lerp([3]f32{0.42, 0.60, 0.30}, [3]f32{0.66, 0.58, 0.38}, clamp(t*2.2, 0, 1)), [3]f32{0.52, 0.42, 0.34}, clamp(t*3.3 - 1.45, 0, 1))
			col = math.lerp(col, [3]f32{0.90, 0.89, 0.86}, clamp(t*4 - 3, 0, 1))*clamp(0.8 + 1.6*slope, 0.35, 1.3)
			drained := f32(0)   // the most land any cell under the pixel drains: a river is a line of cells
			for j in int(y - per/2)..=int(y + per/2) do for i in int(x - per/2)..=int(x + per/2) do drained = max(drained, store_area(st, i, j))
			if drained > 40e6 do col = math.lerp(col, [3]f32{0.10, 0.30, 0.75}, clamp(0.45 + drained/400e6, 0, 1))
		}
		for j in 0..<3 do pixels[(py*N + px)*4 + j] = u8(clamp(col[j], 0, 1)*255)
		pixels[(py*N + px)*4 + 3] = u8(a*255)
	}
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
	c.going = false
	under := chart_from(about)
	limits := SPAN_WORLD
	c.span = clamp(c.span*by, limits[0], limits[1])
	c.at += under - chart_from(about)
}

// The part of the picture no panel stands on: between the hand's side and the islands' list.
chart_free :: proc() -> Rect {
	L := &LOOK
	left, right := px(L.margin) + px(L.hand_wide) + px(4), screen.w - px(L.margin) - px(L.isles_wide) - px(4)
	if right - left < 0.3*screen.w do return {0, 0, screen.w, screen.h}   // a picture too small for the interface's size: the panels lie over the land
	return {left, px(L.margin), right - left, screen.h - 2*px(L.margin)}
}

// Go to a box of the world: it comes to fill so much of the free part of the picture, at its middle.
chart_frame :: proc(lo, hi: [2]f64, fill: f64) {
	c := &chart
	f := c.free if c.free.w > 0 else Rect{0, 0, max(c.wide, 1), max(c.high, 1)}
	k := fill*min(f64(f.w)/max(hi.x - lo.x, 1), f64(f.h)/max(hi.y - lo.y, 1))   // pixels to a metre
	c.to_span = clamp(f64(max(c.wide, 1))/k, SPAN_WORLD[0], SPAN_WORLD[1])
	k = f64(max(c.wide, 1))/c.to_span
	c.to_at = (lo + hi)/2 - [2]f64{f64(f.x + f.w/2 - c.wide/2), f64(f.y + f.h/2 - c.high/2)}/k
	c.going = true
}

// Go to an island, so that its land can be read; or to all the islands there are to choose from.
chart_go :: proc(island: int) {
	if island >= 0 && island < len(archipelago) {
		is := archipelago[island]
		o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
		chart_frame(o - is.size/2, o + is.size/2, 0.92)
		return
	}
	lo, hi := [2]f64{1e12, 1e12}, [2]f64{-1e12, -1e12}
	for is in archipelago {
		o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
		lo, hi = {min(lo.x, o.x - is.size/2), min(lo.y, o.y - is.size/2)}, {max(hi.x, o.x + is.size/2), max(hi.y, o.y + is.size/2)}
	}
	if len(archipelago) == 0 do lo, hi = world_frame.origin - NEAR_SIDE/2, world_frame.origin + NEAR_SIDE/2
	if island == MAINLAND {   // the islands, and the mainland's coast within 400 km of the start: where it lies from them
		for p in continent.coast do if math.hypot(p.x - world_frame.origin.x, p.y - world_frame.origin.y) < 400_000 {
			lo, hi = {min(lo.x, p.x), min(lo.y, p.y)}, {max(hi.x, p.x), max(hi.y, p.y)}
		}
	} else if i := land_of(island); i >= 0 {   // the islands, and the nearest shore of a large land farther off
		p := lands[i].shore
		lo, hi = {min(lo.x, p.x), min(lo.y, p.y)}, {max(hi.x, p.x), max(hi.y, p.y)}
	}
	chart_frame(lo, hi, 0.86)
}

// The view moves toward where it is going, a share of the way each frame; at once where no time passes.
chart_move :: proc(dt: f64) {
	c := &chart
	if !c.going do return
	t := 1 - math.exp(-dt*11) if dt > 0 else 1
	c.at += (c.to_at - c.at)*t
	c.span *= math.pow(c.to_span/c.span, t)
	if abs(c.span/c.to_span - 1) < 0.002 do c.at, c.span, c.going = c.to_at, c.to_span, false
}

// What lies at a point of the world: an island's square, a large land, or nothing of note.
chart_under :: proc(p: [2]f64) -> int {
	for is in archipelago do if max(abs(p.x - f64(is.origin.x)), abs(p.y - f64(is.origin.y))) < max(is.size/2, 0.5*f64(px(LOOK.isle))*chart.span/f64(max(chart.wide, 1))) do return is.id
	if world_at(p.x, p.y).inland > 0 {
		k := known_point(p.x, p.y)
		u, v := clamp(int((k.x + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1), clamp(int((k.y + WINDOW/2)/KNOWN_STEP), 0, KNOWN_N - 1)
		for m, i in lands do if m.mass == known.mass[v*KNOWN_N + u] do return MAINLAND - i
		return MAINLAND
	}
	return -1
}

// A name on the map: words on a dark ground, their middle at x, under a thing or, where another
// name already stands there, over it (`over` is the y of its foot there); left out where both are taken.
map_names: [dynamic]Rect   // the names put on the map this frame
map_name :: proc(x, y: f32, name: string, colour: Colour, id: string, style := Style.Small, over: f32 = -1, take := -1) -> bool {
	w := text_wide(style, name)
	for at in ([2]f32{y, over - line_of(style)}) {
		if at < 0 do continue
		r := Rect{math.round(x - w/2) - px(1.5), math.round(at), w + px(3), line_of(style)}
		taken := false
		for o in map_names do taken ||= r.x < o.x + o.w && o.x < r.x + r.w && r.y < o.y + o.h && o.y < r.y + r.h
		if taken do continue
		append(&map_names, r)
		part(.Fill, r, colour = LOOK.said)
		it := part(.Text, {r.x + px(1.5), r.y, w, r.h}, name, style, colour, id = id)
		if take != -1 do it.act, it.arg = .Isle_Take, take   // a click on an island's name takes it, as a click on its land does
		return true
	}
	return false
}

// The large land a pick names, as its place in `lands`, or -1.
land_of :: proc(pick: int) -> int { return MAINLAND - pick if pick <= MAINLAND && MAINLAND - pick < len(lands) else -1 }

// A large land's place in `lands`, or -1.
land_index :: proc(m: ^Landmass) -> int {
	for &l, i in lands do if &l == m do return i
	return -1
}

// A large land's name: the nearest the start is the mainland, and the others are called by where
// they lie from it, until the peoples who live on them name them (the plan's P9).
land_name :: proc(i: int) -> string {
	if i <= 0 || i >= len(lands) do return "The mainland"
	start := world_frame.origin
	way := compass(lands[i].shore.x - start.x, lands[i].shore.y - start.y)
	same := 0
	for m in lands[1:i] do same += int(compass(m.shore.x - start.x, m.shore.y - start.y) == way)
	return fmt.tprintf("The %s land", way) if same == 0 else fmt.tprintf("The far %s land", way) if same == 1 else fmt.tprintf("The %s land, %d", way, same + 1)
}

// Why a large land is not formed as land, in a player's words.
land_why :: proc(i: int) -> string {
	if i < 0 || i >= len(lands) do return "the known world holds no land larger than an island"
	m := &lands[i]
	switch {
	case m.left: return "its forming was stopped before it had run, so it is left as the plates' history has it until this world is opened again"
	case making.continent == 0: return "it was asked to be left as the plates' history has it (--continent=0)"
	case !sync.atomic_load(&making.massed): return "its stage has not been come to"
	}
	return fmt.tprintf("its nearest shore lies %.0f km from the start, and a world's large lands are formed when it is made only within %d km of the start. It is formed from this card, or in play when the view nears it: the whole of it on cells 64 m across, once, and kept",
		m.near/1000, COARSE_REACH/1000)
}

// Seconds a land mass's coarse stage takes to form on this kind of machine, about: half a minute for
// 45,000 km² and six minutes for 317,000 km² under some load (continents-forming.md). For the screen
// that says what forming one would cost.
mass_seconds :: proc(m: ^Landmass) -> f64 { return 5 + 0.001*f64(m.area) }

// GB a land mass's coarse stage holds at the most while it is formed, about: 13.5 for 317,000 km²
// (continents-forming.md). For the screen that says what forming one costs.
mass_memory :: proc(m: ^Landmass) -> f64 { return 1.5 + 0.038*f64(m.area)/1000 }

// How a large land stands: known and not formed, asked for and waiting its turn, being formed, or formed.
Land_Stands :: enum { Known, Asked, Forming, Formed }
land_stands :: proc(i: int) -> Land_Stands {
	if i < 0 || i >= len(lands) do return .Known
	m := &lands[i]
	if mass_listed(m) do return .Formed
	if sync.atomic_load(&lands_state.forming) == m.mass do return .Forming
	return .Asked if sync.atomic_load(&m.asked) else .Known
}

// What forming a large land takes here, in a few words: how long, and the memory it holds meanwhile.
land_costs :: proc(i: int) -> string {
	m := &lands[i]
	return fmt.tprintf("about %s, %.0f GB", span_words(mass_seconds(m)), mass_memory(m))
}

// How far the forming of the land being formed has come, and about how long is left, in words.
land_progress :: proc() -> string {
	done, all, _ := making_progress(.Mainland)
	if all == 0 do return "begun"
	left := lands_state.expect*f64(all - done)/f64(max(all, 1))   // by what such land takes here, until it has run long enough to say by its own pace
	if done >= 8 do left = time.duration_seconds(time.since(lands_state.began))*f64(all - done)/f64(done)
	return fmt.tprintf("%d of %d steps, about %s more", done, all, span_words(left))
}

// How a large land stands, in a few words.
land_says :: proc(i: int) -> string {
	if i < 0 || i >= len(lands) do return "none in the known world"
	m := &lands[i]
	switch land_stands(i) {
	case .Formed:  return "formed on 64 m cells" if len(m.cut.size) > 0 else "under the sea"
	case .Forming: return "being formed"
	case .Asked:   return "waiting to be formed"
	case .Known:
	}
	return "known, not formed"
}

// The map: the known world's picture, each large land where its coarse stage stands, the islands
// formed, a mark where one is still to be, and their names. `plain` leaves the names out, for the
// front door.
chart_map :: proc(plain: bool) {
	c, u, L := &chart, &play, &LOOK
	u.area = .Chart
	c.wide, c.high = screen.w, screen.h
	clear(&map_names)
	if !sync.atomic_load(&making.records) do return
	if c.known {
		side := f64(WINDOW)*1000
		lo := chart_to(world_of({0, 0}) - side/2)
		k := f32(f64(c.wide)/c.span*side)
		part(.Picture, {lo.x, lo.y, k, k}, id = "chart.known").uv = {0, 0, 1, 1}
		screen.items[len(screen.items) - 1].arg = 0
	}
	lensed := c.lens >= 0 && c.lens_on == c.lens
	isles := len(archipelago)
	for tile, t in c.tiles do if isles + t < len(c.shown) && c.shown[isles + t] && !lensed && mass_listed(&lands[tile.z]) {
		m := &lands[tile.z]
		side := m.side/f64(land_tiled(m))
		corner := [2]f64{f64(m.origin.x), f64(m.origin.y)} - m.side/2 + {f64(tile.x), f64(tile.y)}*side
		lo, k := chart_to(corner), f32(f64(c.wide)/c.span*side)
		if lo.x > c.wide || lo.y > c.high || lo.x + k < 0 || lo.y + k < 0 do continue
		it := part(.Picture, {lo.x, lo.y, k, k}, id = "chart.mass")
		it.uv, it.arg = {0, 0, 1, 1}, isles + t + 1
	}
	for is, i in archipelago {
		at := chart_to({f64(is.origin.x), f64(is.origin.y)})
		side := f32(f64(c.wide)/c.span*is.size)
		if at.x + side/2 < 0 || at.y + side/2 < 0 || at.x - side/2 > c.wide || at.y - side/2 > c.high do continue
		shown := i < len(c.shown) && c.shown[i]
		if shown {
			it := part(.Picture, {at.x - side/2, at.y - side/2, side, side}, id = "chart.isle")
			it.uv, it.arg = {0, 0, 1, 1}, i + 1
			if lensed && WORLD_LENSES[c.lens].isle != nil do it.colour, it.state = c.tints[i], {.Faint}   // tinted by its own figure where it has one; else it keeps its colours on the painted sea
		}
		mark := clamp(0.5*side, px(L.isle), 3*px(L.isle)) if !shown else px(L.isle)
		if !shown || side < 2*px(L.isle) {   // not formed yet, or too small in the picture to be seen: a ring where it stands
			part(.Ring, {at.x - mark/2, at.y - mark/2, mark, mark}, colour = L.brass if i == 0 else L.chalk, id = "chart.mark")
		}
		large := side > 0.45*c.high   // near enough that its own places are named on it
		if c.pick == i && !large {   // the island in the hand: brass corners round its square
			r, arm, t := max(side, 2*px(L.isle))/2 + px(1), clamp(side/10, px(3), px(8)), px(L.bar)
			for sx in ([2]f32{-1, 1}) do for sy in ([2]f32{-1, 1}) {
				cx, cy := at.x + sx*r, at.y + sy*r
				part(.Fill, {min(cx, cx - sx*arm), cy - t/2, arm, t}, colour = L.brass, id = "chart.picked")
				part(.Fill, {cx - t/2, min(cy, cy - sy*arm), t, arm}, colour = L.brass)
			}
		}
		if plain || c.span > 900_000 do continue
		if large && is_formed(&formed[i]) {
			f := &formed[i]
			for p in f.places {
				k := f.candidates[p.c]
				spot := chart_to({f64(is.origin.x) + k.at.x, f64(is.origin.y) + k.at.y})
				part(.Fill, {spot.x - px(0.75), spot.y - px(0.75), px(1.5), px(1.5)}, colour = L.chalk, id = "chart.spot")
				map_name(spot.x, spot.y + px(1.5), p.name, L.chalk, "chart.place")
			}
			continue
		}
		name := isle_name(i)   // a ring says it is not formed yet, and so does its row
		reach := max(side, 2*px(L.isle))/2 + px(2.5) if c.pick == i else max(side*0.36, mark/2) + px(1)
		map_name(at.x, at.y + reach, name, L.brass if c.pick == i else L.chalk, "chart.name", .Body if side > 14*px(L.isle) else .Small, at.y - reach, i)
	}
	if !plain && c.span > 60_000 do for i in 0..<max(len(lands), 1) {   // each land larger than an island: the mainland named where its range's crest runs, the others at their nearest shore
		if i == 0 && len(continent.crest) == 0 || i > 0 && i >= len(lands) do continue
		at := chart_to(continent.crest[len(continent.crest)/2] if i == 0 else lands[i].shore)
		if at.x > 0 && at.y > 0 && at.x < c.wide && at.y < c.high {
			map_name(at.x, at.y, fmt.tprintf("%s: %s", land_name(i), land_says(i)), L.brass if c.pick == MAINLAND - i else L.chalk, "chart.mainland", take = MAINLAND - i)
		}
	}
	if plain do return
	// How far a length of the picture is: a round figure, at the foot of the free part.
	f := c.free
	per := c.span/f64(max(c.wide, 1))   // metres to a pixel
	want := per*f64(f.w)*0.16
	unit := math.pow(10, math.floor(math.log10(want)))
	for k in ([3]f64{5, 2, 1}) do if k*unit <= want {
		unit *= k
		break
	}
	w := f32(unit/per)
	x, y := math.round(f.x + (f.w - w)/2), f.y + f.h - px(3)
	says := fmt.tprintf("%.0f km", unit/1000) if unit >= 1000 else fmt.tprintf("%.0f m", unit)
	part(.Fill, {x, y, w, px(L.bar)}, colour = L.chalk, id = "chart.scale")
	for end in ([2]f32{x, x + w - px(L.bar)}) do part(.Fill, {end, y - px(1.5), px(L.bar), px(1.5) + px(L.bar)}, colour = L.chalk)
	part(.Text, {x, y - line_of(.Small) - px(1.5), w, line_of(.Small)}, says, .Small, L.chalk, {.Centre, .Shadow}, id = "chart.scale.says")
}

// ---- the island's card ------------------------------------------------------------------------

// Take an island in the hand, or put it down (-1); `go` takes the view to it.
chart_take :: proc(island: int, go := false) {
	c := &chart
	if island != c.pick {
		c.pick, c.scroll, c.row = island, 0, -1   // the depth shown is kept from island to island, so that two can be compared in it
		if island <= MAINLAND do c.depth = .Land
		if island >= 0 do forming_toward(island)   // its land and its neighbours' are made next
	}
	if go && (island >= 0 || island <= MAINLAND) do chart_go(island)
}

card_row :: proc(k: ^Isle_Card, d: Isle_Depth, thing, says: string, why := "", sign := Sign.None, block := Colour{}, faint := false) {
	append(&k.rows[d], Card_Row{strings.clone(thing), strings.clone(says), strings.clone(why), sign, block, faint, ""})
}

// The landing an island's shore offers, as the hold will choose it (landing.odin): the first of the
// landing's rows that holds on any cell of its shore, and on how many. The island is bound.
shore_offers :: proc() -> (row, held, shores: int) {
	g := land.grid
	row = -1
	shore := shore_cells()
	shores = len(shore)
	for r, i in LANDINGS {
		for c in shore {
			m := middle_of(g, c)
			p := point_at(m.x, m.y, LAND_CELL)
			held += int(host(r.host, &p) > 0)
		}
		if held > 0 do return i, held, shores
	}
	return
}

// What a card says of an island, written when it is taken in the hand and again once it is formed.
card_write :: proc() {
	c := &chart
	k := &c.card
	now := c.pick >= 0 && is_formed(&formed[c.pick])
	pieces := 0
	li := land_of(c.pick)
	landed := li >= 0 && mass_listed(&lands[li])
	if landed do for &f in formed[lands[li].first:][:len(lands[li].cut.size)] do pieces += int(is_formed(&f))
	stands := int(land_stands(li))
	if c.pick == k.of && now == k.formed && pieces == k.pieces && stands == k.stands && !(c.pick <= MAINLAND && (making_stage() == .Mainland || stands == int(Land_Stands.Forming))) do return
	delete(k.title); delete(k.sub)
	for &rows in k.rows {
		for r in rows { delete(r.thing); delete(r.says); delete(r.why) }
		delete(rows)
	}
	k^ = {of = c.pick, formed = now, pieces = pieces, stands = stands}
	if c.pick == -1 do return
	byte :: proc(v: [3]f32) -> Colour { return {u8(clamp(v.r, 0, 1)*255), u8(clamp(v.g, 0, 1)*255), u8(clamp(v.b, 0, 1)*255), 255} }
	o_start := world_frame.origin
	if c.pick <= MAINLAND {   // a large land: how it stands as land, and why; then what the world knows of it
		ashore := f64(1e12)
		if li >= 0 do ashore = lands[li].near
		else do for p in continent.coast do ashore = min(ashore, math.hypot(p.x - o_start.x, p.y - o_start.y))
		k.title = strings.clone(land_name(li))
		k.sub = fmt.aprintf("Land larger than an island, %.0f km %s of the start", ashore/1000, compass(lands[li].shore.x - o_start.x, lands[li].shore.y - o_start.y)) if li >= 0 else fmt.aprintf("Land larger than an island, %.0f km from the start", ashore/1000)
		switch {
		case landed && len(lands[li].cut.size) == 0:
			card_row(k, .Land, "As land", "under the sea", "Its coarse stage is run, and nothing of it is left over the sea: its ground starts under the sea when its forming begins, since the history is still raising it and the sea floor does not rise with the land.", .Caution)
			card_row(k, .Land, "Can be landed on", "no", "Nothing is formed there to stand on.", faint = true)
		case landed:
			m := &lands[li]
			card_row(k, .Land, "As land", "formed on 64 m cells", fmt.tprintf("Its coarse stage is run: the whole of it through the history's 64 m steps, %s. That gives its ranges, its valleys and where its rivers run, which is what the map draws.", "read back from where an earlier run kept it" if m.kept else fmt.tprintf("formed in this run in %s and kept", span_words(m.took))), .Well)
			card_row(k, .Land, "Ground to walk on", fmt.tprintf("%d of %s pieces", pieces, thousands(len(m.cut.size))), fmt.tprintf("It is cut along its drainage into pieces of about %d km². A piece is formed down to the ground you walk on when the start lies within %d km of it, round where you come ashore to walk it, and within %.0f km of the view while you play; one left far behind is let go and read back on return. Beyond the pieces formed its land is drawn from the 64 m cells.", PIECE_KM2, NEAR_REACH/1000, mass_reach/1000), .Caution if pieces == 0 else .None)
			if m.landing_piece >= 0 {
				o := m.landing - o_start
				card_row(k, .Land, "Come ashore", fmt.tprintf("%.0f km %s of the start", math.hypot(o.x, o.y)/1000, compass(o.x, o.y)), fmt.tprintf("Walking it begins on its land nearest the start, once the pieces within %d km of there are formed. No boat lands a party on it yet.", WALK_REACH/1000))
			}
		case stands == int(Land_Stands.Forming):
			done, all, _ := making_progress(.Mainland)
			card_row(k, .Land, "As land", "being formed", fmt.tprintf("Its coarse stage is running: the whole of it through the history's 64 m steps, %d of %d so far. It is made once for a world and kept.", done, all), .Caution)
		case stands == int(Land_Stands.Asked):
			card_row(k, .Land, "As land", "waiting to be formed", "It is formed once the land in hand is: one large land is formed at a time, since each takes most of the machine.", .Caution)
		case:
			card_row(k, .Land, "As land", "known, not formed", fmt.tprintf("The plates' history made it, and the world knows its coast and its heights. It is not formed as land: %s.", land_why(li)), .Caution)
			if li >= 0 do card_row(k, .Land, "Forming it takes", land_costs(li), "The whole of it through the history's 64 m steps, on every core while you look and on a few while you play. The memory is held only while it forms. It is made once for this world and kept on disk.")
			card_row(k, .Land, "Can be landed on", "no", "Nothing is formed there to stand on.", faint = true)
		}
		if li >= 0 {
			card_row(k, .Land, "Land", fmt.tprintf("%s km²", thousands(int(lands[li].area))), "As the plates' history left it, within the known world.")
			card_row(k, .Land, "Highest ground", fmt.tprintf("%s m", thousands(int(lands[li].top))), "The history's highest ground on it, on cells 2 km across.")
		}
		if li <= 0 do card_row(k, .Land, "Its range's crest", fmt.tprintf("%s m", thousands(int(continent.height))), "The middle height of the crest of the range behind the coast nearest the start.")
		card_row(k, .Land, "Coast from the start", fmt.tprintf("%.0f km", ashore/1000))
		if li <= 0 do card_row(k, .Life, "Animals", "every kind the islands have", "The islands' animals came from it, so every kind is taken to live there until it is formed and can say.")
		return
	}
	is := archipelago[c.pick]
	f := &formed[c.pick]
	said := kind_said(is.kind)
	o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
	k.title = strings.clone(isle_name(c.pick))
	far := math.hypot(o.x - o_start.x, o.y - o_start.y)
	k.sub = fmt.aprintf("%s, %s", capital(said.one), "the start" if c.pick == 0 else fmt.tprintf("%.0f km %s of the start", far/1000, compass(o.x - o_start.x, o.y - o_start.y)))
	rec := record_of(is)
	not_yet := "being formed now" if sync.atomic_load(&making.doing[c.pick]) != 0 else "not formed yet"
	wait_why :: "Its land is made when its turn comes. Taking it in the hand brings its turn nearer."

	// Land: what a founder asks first.
	card_row(k, .Land, "Kind", said.short, said.made)
	if now {
		bound(f)
		g := land.grid
		steep, live := 0, 0
		for ci in g.order {
			steep += int(land.slope[ci] > 1)
			live += int(land.live[ci] > 0)
		}
		cells := max(len(g.order), 1)
		card_row(k, .Land, "Land", fmt.tprintf("%.0f km²", survey.land), fmt.tprintf("Of the %.0f km square it stands in.", is.size/1000))
		card_row(k, .Land, "Highest ground", fmt.tprintf("%.0f m", g.z[survey.top]))
		card_row(k, .Land, "Ground to live on", fmt.tprintf("%d%% of it", live*100/cells), "Ground under 20°, 2 m or more over the sea, a hectare or more together.", .Caution if live*100 < cells*10 else .None)
		card_row(k, .Land, "Steep ground", fmt.tprintf("%d%% of it", steep*100/cells), "Ground steeper than 45°.")
		row, held, shores := shore_offers()
		switch row {
		case 0: card_row(k, .Land, "Landing", "sheltered, by fresh water", fmt.tprintf("Along %.1f km of its %.0f km of shore %s.", f32(held)*LAND_CELL/1000, f32(shores)*LAND_CELL/1000, LANDINGS[0].why), .Well)
		case 1: card_row(k, .Land, "Landing", "sheltered, water a walk off", fmt.tprintf("Along %.1f km of its %.0f km of shore %s.", f32(held)*LAND_CELL/1000, f32(shores)*LAND_CELL/1000, LANDINGS[1].why))
		case 2: card_row(k, .Land, "Landing", "an open shore", fmt.tprintf("%s.", capital(LANDINGS[2].why)), .Caution)
		case:   card_row(k, .Land, "Landing", "none", "No shore of the island is low enough for a boat to be drawn up.", .Caution)
		}
	} else {
		card_row(k, .Land, "Land", not_yet, wait_why, faint = true)
	}
	card_row(k, .Land, "Land made", fmt.tprintf("%s ago", myr_words(is.age)))
	card_row(k, .Land, "Crust", fmt.tprintf("rising %.2f mm a year", rec.past[0]) if rec.past[0] > 0.005 else fmt.tprintf("sinking %.2f mm a year", -rec.past[0]) if rec.past[0] < -0.005 else "still", "Over the last half million years, by the plates' history.")
	card_row(k, .Land, "Setting", strings.trim_prefix(strings.trim_prefix(SETTING_SAID[is.setting], "on "), "in "), "Where the plates put it.")

	// Water.
	if now {
		bound(f)
		mouths, springs, falls, lakes, ponds, tallest := 0, 0, 0, 0, 0, f32(0)
		for ft in region.features {
			#partial switch ft.kind {
			case .Mouth:  mouths += 1
			case .Spring: springs += 1
			case .Lake:   lakes += 1
			case .Pond:   ponds += 1
			case .Fall:
				falls += 1
				tallest = max(tallest, ft.measured[0].value)
			}
		}
		if mouths == 0 do card_row(k, .Water, "Streams to the sea", "none", "Its rain sinks into its rock, so no stream crosses it.", .Caution)
		else {
			card_row(k, .Water, "Streams to the sea", fmt.tprint(mouths))
			card_row(k, .Water, "Longest river", fmt.tprintf("%.1f km", survey.river/1000), "From its farthest head to the sea.")
		}
		card_row(k, .Water, "Springs", fmt.tprint(springs) if springs > 0 else "none", "Where a bed that passes water lies on one that holds it, in a hollow on a valley side.", faint = springs == 0)
		card_row(k, .Water, "Falls", fmt.tprintf("%d, the tallest %.0f m", falls, tallest) if falls > 0 else "none", faint = falls == 0)
		card_row(k, .Water, "Lakes and ponds", fmt.tprintf("%d and %d", lakes, ponds) if lakes + ponds > 0 else "none", "A lake stands behind a slide's dam; a pond in a hollow no stream leaves.", faint = lakes + ponds == 0)
		card_row(k, .Water, "Rain on its land", fmt.tprintf("%s mm a year", thousands(int(f.land.rained))), "The mean over its land: the wind's rain is wrung out on the side it comes to.")
	} else do card_row(k, .Water, "Streams", not_yet, wait_why, faint = true)

	// Rock.
	if now {
		bound(f)
		card_row(k, .Rock, "Its rock tells of", region.story.name)
		for t, m in survey.rocks do if t.cells*50 >= len(land.grid.order) {
			card_row(k, .Rock, capital(mat_words(m)), fmt.tprintf("%d%%", t.cells*100/len(land.grid.order)), "Of the rock at its surface.", block = byte(map_colour(m)))
		}
	} else do card_row(k, .Rock, "Rock", not_yet, "Its rock is read from where it stands when it is formed.", faint = true)
	if rec.on do card_row(k, .Rock, "Volcano", fmt.tprintf("on the foot of one, %s old", myr_words(rec.vent.born)), fmt.tprintf("It built %.0f m over the ground under it.", rec.vent.built))

	// Climate: from where it stands, as forming works it out (climate_init).
	latitude, truly := climate_latitude(o.x, o.y)
	offshore := max(-world_at(o.x, o.y).inland, 0)
	mean, swing := sea_mean(latitude), sea_swing(latitude, offshore)
	card_row(k, .Climate, "Latitude", fmt.tprintf("%.1f° N", truly))
	card_row(k, .Climate, "The year's mean", fmt.tprintf("%.1f °C", mean), "In the air at the sea's level.")
	card_row(k, .Climate, "Coldest month", fmt.tprintf("%.1f °C", mean - swing))
	card_row(k, .Climate, "Warmest month", fmt.tprintf("%.1f °C", mean + swing))
	card_row(k, .Climate, "Rain on the sea round it", fmt.tprintf("%s mm a year", thousands(int(sea_rain(latitude)))))
	if now do card_row(k, .Climate, "Rain on its land", fmt.tprintf("%s mm a year", thousands(int(f.land.rained))))
	card_row(k, .Climate, "Wind and swell", fmt.tprintf("from the %s", compass(math.sin(math.to_radians(world_frame.wind)), -math.cos(math.to_radians(world_frame.wind)))), "One wind for the whole world, drawn from its seed.")

	// Life: its woods, and who reached it and why or why not (arrivals.odin).
	if now {
		bound(f)
		for t, kind in survey.plants do if t.cells*20 >= len(land.grid.order) {
			card_row(k, .Life, capital(COMMUNITIES[kind].name), fmt.tprintf("%d%%", t.cells*100/len(land.grid.order)), fmt.tprintf("%s.", capital(COMMUNITIES[kind].why)), block = byte(COMMUNITIES[kind].colour))
		}
	}
	for row, d in DISPERSAL {
		a := arrivals[c.pick][d]
		from := "the mainland" if a.from < 0 else isle_name(a.from)
		sea := fmt.tprintf("%.0f km of sea", a.open) if a.open >= 10 else fmt.tprintf("%.1f km of sea", a.open)
		if a.reached {
			how := fmt.tprintf("It walked from %s over ground the sea bared when it stood lower", from) if a.way == .Walked else fmt.tprintf("It %s from %s across %s", WAYS[a.way], from, sea)
			why := fmt.tprintf("%s%s.", how, ", further than it is sure to cross: the seed's draw let it" if a.chance < 1 && a.way != .Walked else "")
			if !now do card_row(k, .Life, capital(row.name), "reached it", why)
			else {
				bound(f)
				if kept(row.name) do card_row(k, .Life, capital(row.name), "lives here", why, .Well)
				else do card_row(k, .Life, capital(row.name), "reached it, cannot live here", fmt.tprintf("%s The island has not what it needs.", why))
			}
		} else {
			card_row(k, .Life, capital(row.name), "not here", fmt.tprintf("The nearest land with it, %s, lies across %s, and it %s %.0f km at most%s.", from, sea, ACROSS[row.way], row.most, ", so it might have crossed, and the seed's draw said no" if a.chance > 0 else ""), faint = true)
		}
	}

	// Places: its named places, once it has them.
	if now do for p in f.places {
		cand := f.candidates[p.c]
		why, _, _ := strings.partition(cand.why, ";")
		card_row(k, .Places, p.name, PLACE_ROWS[cand.kind].what, fmt.tprintf("%s.", capital(why)))
	}
}

// A whole number with its thousands set apart.
thousands :: proc(n: int) -> string {
	if n < 1000 do return fmt.tprint(n)
	return fmt.tprintf("%s,%03d", thousands(n/1000), n%1000)
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
	if !sync.atomic_load(&making.massed) && !making.stopped do return "The islands are formed once the mainland is."
	if !is_formed(&formed[island]) do return "Its land is still being formed." if !making.stopped else "Its land is not formed, and the making is stopped."
	n := 0
	for &f, i in formed[:islands_count()] do if !is_formed(&f) && islands_apart(i, island) <= making.near_km*1000 do n += 1
	if n == 0 do return "The mainland's land within reach of it is still to be formed." if sync.atomic_load(&making.massed) else "The mainland's stage comes first."
	return fmt.tprintf("%s of the islands within %.0f km of it %s still to be formed.", capital(number_words(n)), making.near_km, "is" if n == 1 else "are")
}

// In play: say when a large land begins to be formed and when it stands, once each (lands_near,
// continents.odin, asks for one as the view nears it).
lands_tell :: proc() {
	ls := &lands_state
	now := sync.atomic_load(&ls.forming) if sync.atomic_load(&ls.asking) else 0
	if now == ls.told do return
	for &m, i in lands {
		if m.mass == ls.told && mass_listed(&m) do tell(fmt.tprintf("%s is formed: its land is drawn from here on, and its ground is made as you come near.", land_name(i)) if len(m.cut.size) > 0 else fmt.tprintf("%s is formed, and nothing of it stands over the sea.", land_name(i)))
		if m.mass == now do tell(fmt.tprintf("%s lies %.0f km off and is being formed as land, about %s.", land_name(i), mass_from(&m, mass_focus)/1000, span_words(ls.expect)))
	}
	ls.told = now
}

// What stands between a large land and its doors, in a line; "" where nothing does.
land_waits :: proc(li: int) -> string {
	m := &lands[li]
	switch land_stands(li) {
	case .Known:
		if !lands_can(li) do return "It can be formed once the world's own making has gone through its large lands, and while the making is not stopped."
	case .Asked: return "It is formed once the land in hand is."
	case .Forming: return fmt.tprintf("Being formed: %s.", land_progress())
	case .Formed:
		if m.landing_piece < 0 || world_enterable(MAINLAND - li) do return ""
		left := masses_near(m.landing, WALK_REACH)
		going := " You go in when it is." if door.wish == .Walk && door.isle == MAINLAND - li else ""
		return fmt.tprintf("Its ground where you come ashore is formed when you walk it: %s piece%s to form.%s", number_words(left), "" if left == 1 else "s", going)
	}
	return ""
}

// Whether a large land's coarse stage can be asked for now.
lands_can :: proc(li: int) -> bool {
	return li >= 0 && li < len(lands) && sync.atomic_load(&making.massed) && !sync.atomic_load(&forming.stop) && !making.stopped
}

// How high a row of the card stands: a line, two where its words do not fit beside its thing, and its why under it once chosen.
row_high :: proc(r: Card_Row, inner: f32, chosen: bool) -> (high: f32, two: bool) {
	L := &LOOK
	lead := px(L.block) + px(2) if r.block.a > 0 else 0
	two = lead + text_wide(.Body, r.thing) + px(4) + text_wide(.Body, r.says) + (px(L.sign) + px(1.5) if r.sign != .None else 0) > inner
	high = line_of(.Body)*(2 if two else 1) + 2*px(1)
	if chosen && r.why != "" do high += text_high(.Small, r.why, inner) + px(1)
	return
}

// A card's rows in their box, `depth` high: a thing, then a word or a figure with its sign, and under
// the row chosen its why. Scrolled where they are deeper than the box, with the wheel over it. A row
// with a why takes `act` with its number; the parts are named `id`.row, .thing, .says, .why and .thumb.
// `reveal` scrolls them so that the row chosen stands whole in the box, once, when it is chosen.
rows_put :: proc(rows: []Card_Row, cx, y, inner, depth: f32, scroll, over: ^f32, chosen: int, act: Act, id: string, reveal := false) {
	u, L := &play, &LOOK
	name :: proc(id, part: string) -> string { return fmt.tprintf("%s.%s", id, part) }
	box := Rect{cx, y, inner, depth}
	all := f32(0)
	for row, i in rows { h, _ := row_high(row, inner, i == chosen); all += h }
	over^ = max(all - depth, 0)
	if reveal && chosen >= 0 && chosen < len(rows) {   // the row just chosen, whole, with its why
		top := f32(0)
		for row in rows[:chosen] { h, _ := row_high(row, inner, false); top += h }
		high, _ := row_high(rows[chosen], inner, true)
		if top + high - scroll^ > depth do scroll^ = top + high - depth
		if top < scroll^ do scroll^ = top
	}
	scroll^ = clamp(scroll^, 0, over^)
	part(.Fill, box, colour = {}, state = {.Solid})   // the wheel over it scrolls it
	u.clip = {box.x - px(L.pad.x) + 1, box.y, box.w + 2*px(L.pad.x) - 2, box.h}
	ry := y - scroll^
	for row, i in rows {
		high, two := row_high(row, inner, i == chosen)
		part(.Row, {box.x - px(L.pad.x) + 1, ry, box.w + 2*px(L.pad.x) - 2, high}, state = {.Chosen} if i == chosen else {}, act = act if row.why != "" else .None, arg = i, id = name(id, "row"), tip = row.why if i != chosen else "")
		ty, lx := ry + px(1), cx
		if row.block.a > 0 {
			part(.Fill, {lx, ty + math.round((line_of(.Body) - px(L.block))/2), px(L.block), px(L.block)}, colour = row.block)
			lx += px(L.block) + px(2)
		}
		words(lx, ty, row.thing, .Body, L.ash, name(id, "thing"))
		sy := ty + (line_of(.Body) if two else 0)
		sw := text_wide(.Body, row.says)
		if two {
			words(lx, sy, fit(.Body, row.says, inner - (lx - cx)), .Body, L.ash if row.faint else L.chalk, name(id, "says"))
		} else {
			part(.Text, {cx + inner - sw, sy, sw, line_of(.Body)}, row.says, .Body, L.ash if row.faint else L.chalk, id = name(id, "says"))
			if row.sign != .None do part(.Sign, {cx + inner - sw - px(1.5) - px(L.sign), sy + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = row.sign
		}
		if i == chosen && row.why != "" do words(cx, sy + line_of(.Body) + px(0.5), row.why, .Small, L.ash, name(id, "why"), inner)
		ry += high
	}
	u.clip = {}
	if over^ > 0 do part(.Thumb, {cx + inner + px(1.5), y + depth*scroll^/all, px(1.5), depth*depth/all}, id = name(id, "thumb"))
}

// Lower left: the island in the hand, as a card of rows, and the doors into play.
isle_build :: proc() {
	c, u, L := &chart, &play, &LOOK
	u.area = .Hand
	card_write()
	k := &c.card
	c.card_at = {}
	if k.of == -1 do return
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x, foot := px(L.margin), screen.h - px(L.margin)
	tabs: [Isle_Depth]bool
	count := 0
	for d in Isle_Depth {
		tabs[d] = len(k.rows[d]) > 0
		count += int(tabs[d])
	}
	if !tabs[c.depth] do c.depth, c.row = .Land, -1
	isle := k.of >= 0
	li := land_of(k.of)
	stands := land_stands(li)
	waits := enter_waits(k.of) if isle else land_waits(li) if li >= 0 else ""
	if isle && waits == "" {   // what a founder should look at twice before the door is taken, in a line: each is a row of the card, with its why
		b := strings.builder_make(context.temp_allocator)
		for rows in k.rows do for row in rows do if row.sign == .Caution {
			fmt.sbprintf(&b, "%s%s: %s", "Look twice. " if strings.builder_len(b) == 0 else "; ", row.thing, row.says)
		}
		if strings.builder_len(b) > 0 do waits = fmt.tprintf("%s.", strings.to_string(b))
	}
	blocked := isle && !world_enterable(k.of)
	head := px(L.block_large)
	beside := inner - head - px(4)
	head = max(head, line_of(.Title) + text_high(.Body, k.sub, beside))
	tabs_high := line_of(.Body) + px(1.5) + px(2.5) if count > 1 else 0
	doored := isle || li >= 0 && !(stands == .Formed && lands[li].landing_piece < 0)   // a land under the sea has no door
	doors := (text_high(.Small, waits, inner) + px(2) if waits != "" else 0) + px(L.button) if doored else 0
	fixed := 2*px(L.pad.y) + head + px(L.space) + tabs_high + (px(4) + doors if doored else 0)
	// As deep as its longest depth with no row chosen, so that it stands as tall whichever is shown; a why opened scrolls it.
	longest := f32(0)
	for d in Isle_Depth {
		high := f32(0)
		for r in k.rows[d] { h, _ := row_high(r, inner, false); high += h }
		longest = max(longest, high)
	}
	room := foot - (u.place_foot + px(4)) - fixed
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
	} else {
		part(.Fill, {square.x + 1, square.y + 1, square.w - 2, square.h - 2}, colour = L.unformed)
	}
	tx := cx + px(L.block_large) + px(4)
	words(tx, y, k.title, .Title, id = "isle.title")
	words(tx, y + line_of(.Title), k.sub, .Body, L.ash, "isle.sub", beside)
	y += head + px(L.space)
	if count > 1 {
		tx = cx
		for d in Isle_Depth do if tabs[d] {
			tw := text_wide(.Body, ISLE_DEPTHS[d])
			part(.Tab, {tx, y, tw, line_of(.Body) + px(1.5)}, ISLE_DEPTHS[d], .Body, {}, {.Chosen} if d == c.depth else {}, .Isle_Depth, int(d), id = "isle.tab")
			tx += tw + px(L.tab_gap)*0.75
		}
		y += line_of(.Body) + px(1.5)
		part(.Rule, {cx, y - 1, inner, 1}, colour = L.edge)
		y += px(2.5)
	}
	rows_put(k.rows[c.depth][:], cx, y, inner, depth, &c.scroll, &c.over, c.row, .Isle_Row, "isle")
	y += depth
	if !doored do return
	y += px(4)
	if waits != "" do y += words(cx, y, waits, .Small, L.ash, "isle.waits", inner) + px(2)
	if !isle {   // a large land's doors: formed from its card, left while it forms, and walked once it stands
		switch stands {
		case .Known:
			door_button({cx, y, inner, px(L.button)}, "Form it", .Found, 0, "land.form", "Form the whole of this land on cells 64 m across: its ranges, its valleys and where its rivers run. You can go on looking, or play, while it is made.", main = lands_can(li), faint = !lands_can(li))
		case .Asked, .Forming:
			door_button({cx, y, inner, px(L.button)}, "Leave it as known", .Mass_Leave, li, "land.leave", "Stop forming it: nothing of it is kept, and it stays as the plates' history has it until it is asked for again.", faint = stands == .Forming && sync.atomic_load(&lands_state.leave))
		case .Formed:
			door_button({cx, y, inner, px(L.button)}, "Walk it", .Roam, 0, "land.walk", "Stand on this land on foot, with no party: on its ground nearest the start, where it is come ashore.", main = world_enterable(k.of), held = door.wish == .Walk && door.isle == k.of)
		}
		return
	}
	// The doors: an expedition is planned on an island once its land is formed (plan.odin); walking it waits for its neighbours.
	walk := button_wide("Walk it", door_key(.Roam))
	unformed := !is_formed(&formed[k.of])
	door_button({cx, y, inner - walk - px(L.gap), px(L.button)}, "Plan an expedition", .Found, 0, "isle.found", "Choose where on this island the boat lands and who comes, and set out.", main = !unformed, faint = unformed)
	door_button({cx + inner - walk, y, walk, px(L.button)}, "Walk it", .Roam, 0, "isle.walk", "Stand on this island on foot, with no party: the bank of its largest river.", faint = blocked)
}

// Top left: the world, and what there is in it.
world_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Place
	title := fmt.tprintf("The world of seed %d", making.seed)
	sub := "Nothing of it is known yet."
	if sync.atomic_load(&making.records) {
		ashore := f64(1e12)
		o := world_frame.origin
		for p in continent.coast do ashore = min(ashore, math.hypot(p.x - o.x, p.y - o.y))
		n := len(archipelago)
		sub = fmt.tprintf("%s island%s near the start", capital(number_words(n)), "" if n == 1 else "s")
		sub = fmt.tprintf("%s, %.0f km off the mainland.", sub, ashore/1000) if ashore < 1.5e6 else fmt.tprintf("%s, and no mainland in the known world.", sub)
	}
	wide := max(text_wide(.Great, title), px(L.hand_wide) - 2*px(L.pad.x))
	r := Rect{px(L.margin), px(L.margin), wide + 2*px(L.pad.x), 2*px(L.pad.y) + line_of(.Great) + px(1) + text_high(.Body, sub, wide)}
	part(.Panel, r, id = "world")
	x, y := r.x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(x, y, title, .Great, id = "world.title") + px(1)
	words(x, y, sub, .Body, L.ash, "world.says", wide)
	u.place_foot = r.y + r.h
}

// Right: the islands there are to choose from, a row each, and the large lands. A row takes its island
// in the hand and the view to it. Returns where the list ends.
isles_build :: proc(room: f32) -> (foot: f32) {
	c, u, L := &chart, &play, &LOOK
	u.area = .List
	w := px(L.isles_wide)
	x, y := screen.w - px(L.margin) - w, px(L.margin)
	inner := w - 2*px(L.pad.x)
	first := len(screen.items)
	part(.Panel, {x, y, w, 0}, id = "isles")
	cx, cy := x + px(L.pad.x), y + px(L.pad.y)
	col := [2]f32{px(21), px(19)}   // the figures' columns: land and highest ground
	words(cx, cy, "Islands", .Title, id = "isles.title")
	part(.Text, {cx + inner - col.x - col.y, cy + line_of(.Title) - line_of(.Small), col.x, line_of(.Small)}, "land", .Small, L.ash, {.Right}, id = "isles.head")
	part(.Text, {cx + inner - col.y, cy + line_of(.Title) - line_of(.Small), col.y, line_of(.Small)}, "highest", .Small, L.ash, {.Right}, id = "isles.head")
	cy += line_of(.Title) + px(2)
	high := px(L.isle_row)
	rows := len(archipelago) + max(len(lands), 1)
	box := Rect{x + 1, cy, w - 2, min(f32(rows)*high, max(room - (cy - y) - px(L.pad.y), 2*high))}
	c.list_over = max(f32(rows)*high - box.h, 0)
	c.list_scroll = clamp(c.list_scroll, 0, c.list_over)
	u.clip = box
	start := world_frame.origin
	for i in 0..<rows {
		ry := cy + f32(i)*high - c.list_scroll
		if ry + high < box.y || ry > box.y + box.h do continue
		mass := i >= len(archipelago)
		li := i - len(archipelago)   // which large land, the nearest the start first
		of := MAINLAND - li if mass else i
		part(.Row, {box.x, ry, box.w, high}, state = {.Chosen} if c.pick == of else {}, act = .Isle_Take, arg = of, id = "isles.row" if !mass else "isles.mainland", tip = "Take it in the hand, and go to it." if !mass else "Take it in the hand, and see where it lies.")
		pic := Rect{cx, ry + math.round((high - px(L.thumb))/2), px(L.thumb), px(L.thumb)}
		part(.Fill, pic, colour = L.seas[1])
		name, under, land, top := land_name(li), land_says(li), "", ""
		if mass {
			part(.Fill, {pic.x + px(1.5), pic.y + px(2.5), pic.w - px(3), pic.h - px(5)}, colour = L.unformed)
			if li < len(lands) {
				land = fmt.tprintf("%s km²", thousands(int(lands[li].area)))
				if li > 0 do under = fmt.tprintf("%s, %.0f km %s", under, lands[li].near/1000, compass_short(lands[li].shore.x - start.x, lands[li].shore.y - start.y))
			}
		} else {
			is := archipelago[i]
			if i < len(c.shown) && c.shown[i] {
				it := part(.Picture, pic, id = "isles.picture")
				it.uv, it.arg = {0.1, 0.1, 0.9, 0.9}, i + 1
			} else {
				m := px(L.isle)
				part(.Ring, {pic.x + (pic.w - m)/2, pic.y + (pic.h - m)/2, m, m}, colour = L.chalk)
			}
			o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
			name = isle_name(i)
			under = fmt.tprintf("%s, %s", kind_said(is.kind).short, "the start" if i == 0 else fmt.tprintf("%.0f km %s", math.hypot(o.x - start.x, o.y - start.y)/1000, compass_short(o.x - start.x, o.y - start.y)))
			if f := &formed[i]; is_formed(f) {
				land, top = fmt.tprintf("%.0f km²", f.survey.land), fmt.tprintf("%.0f m", f.land.grid.z[f.survey.top])
			} else do top = "forming" if sync.atomic_load(&making.doing[i]) != 0 else "not formed"
		}
		tx := cx + px(L.thumb) + px(3)
		ty := ry + math.round((high - line_of(.Name) - line_of(.Small))/2)
		if mass && land != "" {   // a large land's name stands beside its figure: shorter where the two do not fit, and cut where that does not either
			room := inner - (tx - cx) - text_wide(.Body, land) - px(2)
			if text_wide(.Name, name) > room && strings.has_prefix(name, "The ") do name = capital(name[4:])
			name = fit(.Name, name, room)
		}
		words(tx, ty, name, .Name, L.brass if c.pick == of else L.chalk, "isles.name")
		words(tx, ty + line_of(.Name), fit(.Small, under, inner - (tx - cx)), .Small, L.ash, "isles.kind")
		if land != "" do part(.Text, {cx + inner - col.x - col.y, ty, col.x, line_of(.Body)} if !mass else Rect{cx + inner - col.x - col.y, ty, col.x + col.y, line_of(.Body)}, land, .Body, {}, {.Right}, id = "isles.land")
		if top != "" do part(.Text, {cx + inner - col.y - px(12), ty + (0 if land != "" else line_of(.Name)), col.y + px(12), line_of(.Body)}, top, .Body if land != "" else .Small, L.chalk if land != "" else L.ash, {.Right}, id = "isles.top")
	}
	u.clip = {}
	if c.list_over > 0 do part(.Thumb, {box.x + box.w - px(1.5), box.y + box.h*c.list_scroll/(c.list_over + box.h), px(1.5), box.h*box.h/(c.list_over + box.h)}, id = "isles.thumb")
	foot = box.y + box.h + px(L.pad.y)
	screen.items[first].rect.h = foot - y
	return
}

// A bearing in a letter or two.
compass_short :: proc(dx, dz: f64) -> string {
	names := [8]string{"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
	return names[int(math.round(math.mod(math.to_degrees(math.atan2(dx, -dz)) + 360, 360)/45))%8]
}

// Right, under the islands: the lenses' choices, and the key to the one that is on where it is asked
// for. Listed with its top at the picture's; returns how high it stands, for the caller to put it in its place.
chart_lenses :: proc(keyed: bool) -> f32 {
	c, u, L := &chart, &play, &LOOK
	u.area = .Lenses
	w := px(L.isles_wide)
	inner := w - 2*px(L.pad.x)
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	x := screen.w - px(L.margin) - w
	first := len(screen.items)
	part(.Panel, {x, 0, w, 0}, id = "lenses")
	cx, cy := x + px(L.pad.x), px(L.pad.y)
	cy += words(cx, cy, "Lenses", .Small, L.ash, "lenses.title") + px(2)
	half := math.floor((inner - px(L.gap))/2)
	for l, i in WORLD_LENSES {   // two across: eight choices, four rows
		part(.Chip, {cx + f32(i%2)*(half + px(L.gap)), cy, half, chip}, fit(.Body, l.name, half - 2*px(L.chip_pad.x)), .Body, {}, {.Chosen} if c.lens == i else {}, .Chart_Lens, i, "", "lens.row", l.says)
		if i%2 == 1 || i == len(WORLD_LENSES) - 1 do cy += chip + px(L.gap)
	}
	cy -= px(L.gap)
	if c.lens >= 0 && keyed {   // its key: a ramp from one end to the other, or each setting by name
		row := WORLD_LENSES[c.lens]
		paint := FIELDS[row.field]
		cy += px(L.space)
		cy += words(cx, cy, row.says, .Small, L.ash, "lens.says", inner) + px(2)
		byte :: proc(k: [3]f32) -> Colour { return {u8(clamp(k.r, 0, 1)*255), u8(clamp(k.g, 0, 1)*255), u8(clamp(k.b, 0, 1)*255), 255} }
		if row.field == .Setting {
			for name, s in SETTINGS {   // two across
				kx := cx + f32(int(s)%2)*(half + px(L.gap))
				part(.Fill, {kx, cy + px(0.75), px(L.block), px(L.block)}, colour = L.kinds[int(s)])
				words(kx + px(L.block) + px(2), cy, name, .Small, {}, "lens.kind")
				if int(s)%2 == 1 || int(s) == len(Setting) - 1 do cy += line_of(.Small)
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
	cy += px(L.pad.y)
	screen.items[first].rect.h = cy
	return cy
}

// Bottom right: all the islands, the lenses, and the way back to the front door. Returns where they begin.
chart_ways :: proc() -> (top: f32) {
	c, u, L := &chart, &play, &LOOK
	u.area = .Lists
	Way :: struct { name, id, tip: string, act: Act, key: string, open: bool }
	ways := [3]Way{
		{"All islands", "ways.start", "Put the view over all the islands near the start.", .Chart_Home, door_key(.Chart_Home), false},
		{"Lenses", "ways.lenses", "Paint the map by one of the world's fields: the sea's depth, rain, the age of the land.", .Chart_Lenses, door_key(.Chart_Lenses), c.lenses || c.lens >= 0},
		{"Front door", "ways.door", "Back to the front door. The world goes on being made.", .Door_Back, door_key(.Door_Back), false},
	}
	wide := f32(0)
	for k in ways do wide += button_wide(k.name, k.key, .Body, L.know_pad)
	r := Rect{screen.w - px(L.margin) - wide, screen.h - px(L.margin) - px(L.button), wide, px(L.button)}
	part(.Panel, r, id = "ways")
	x := r.x
	for k in ways {
		w := button_wide(k.name, k.key, .Body, L.know_pad)
		part(.Know, {x, r.y, w, r.h}, k.name, .Body, {}, {.Open} if k.open else {}, k.act, 0, k.key, k.id, k.tip)
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
	if under >= 0 && under != c.pick do return fmt.tprintf("%s: %s", isle_name(under), kind_said(archipelago[under].kind).one)
	if under <= MAINLAND do return fmt.tprintf("%s: %s", land_name(MAINLAND - under), land_says(MAINLAND - under))
	return ""
}

// The world's screen, listed. On the right the islands have the room first; the lenses' choices stand
// under them where they are open, and the world being made over the ways, in brief where the rest
// leaves it no more.
chart_build :: proc() {
	c, L := &chart, &LOOK
	c.wide, c.high = screen.w, screen.h
	c.free = chart_free()
	records := sync.atomic_load(&making.records)
	if !c.homed && records {   // a world just known: the islands there are to choose from, and the start in the hand
		c.homed = true
		chart_go(-1)
		chart_move(0)
		chart_take(0)
	}
	chart_move(door.dt)
	chart_map(false)
	c.card_at = {}
	world_build()
	if records do isle_build()
	top := chart_ways()
	first := len(screen.items)
	wide := px(L.isles_wide)   // the right side is one column: the islands, the lenses, the world being made
	lenses := (c.lenses || c.lens >= 0) && records
	lens_high, keyed := f32(0), true
	if lenses {   // measured, and listed again once its place is known
		lens_high = chart_lenses(true) + px(2)
		builtin.resize(&screen.items, first)
	}
	head := px(L.pad.y)*2 + line_of(.Title) + px(2)
	rows_high := f32(len(archipelago) + 1)*px(L.isle_row) + head if records else 0   // the islands and the mainland; the large lands farther off are scrolled to where the world being made needs the room
	made := making_build(screen.w - px(L.margin), top - px(2), wide, false)
	foot := (made.y if made.h > 0 else top) - px(2)
	if made.h > 0 && foot - px(L.margin) < rows_high + lens_high {   // no room for all of it: the making is told in brief
		builtin.resize(&screen.items, first)
		made = making_build(screen.w - px(L.margin), top - px(2), wide, true)
		foot = (made.y if made.h > 0 else top) - px(2)
	}
	if !records do return
	if lenses && foot - px(L.margin) - lens_high < head + 3*px(L.isle_row) {   // nor for the lens's key: what the pointer rests on says the figure
		at := len(screen.items)
		lens_high, keyed = chart_lenses(false) + px(2), false
		builtin.resize(&screen.items, at)
		if made.h > 0 && foot - px(L.margin) - lens_high < head + 2*px(L.isle_row) {   // nor, at the largest sizes, for the world being made: the front door tells it
			builtin.resize(&screen.items, first)
			foot = top - px(2)
		}
	}
	list_foot := isles_build(foot - px(L.margin) - lens_high)
	if lenses {
		at := len(screen.items)
		chart_lenses(keyed)
		for &it in screen.items[at:] do it.rect.y += list_foot + px(2)
	}
}
