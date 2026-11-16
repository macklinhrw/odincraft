package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:time"

// What the game keeps of the world's history (plates.odin): the known world as the history left it,
// read once the history has run, and kept on disk, since it depends only on the world's seed. The
// islands near the start and the continent they lie off are read from it (archipelago.odin).
KNOWN_N    :: 500         // samples along a side of the known world,
KNOWN_STEP :: f32(2)      // km apart
Known_Sample :: struct {
	h:       f32,   // m over the sea: the history's ground and its relief, without its volcanoes
	front:   f32,   // km past the volcanic front toward the back-arc, under 0 toward the trench; 1e4 with no trench within 700 km on the plate
	setback: f32,   // km from the trench back to the volcanic front, where there is one
	slab:    f32,   // km out from the trench on the plate going down; 1e4 if none within 150 km
	age:     f32,   // Myr, of the crust
	rising:  f32,   // mm/yr, over the history's last step
	thick:   f32,   // km of crust
	row:     u8,    // its row in PLATE_SETTINGS
	plate:   u8,    // the plate it rides
	cont:    bool,  // continental crust
}
Known_Vent :: struct {
	at:          [2]f32,   // km east and south of the known world's middle
	arc:         bool,     // on an arc's volcanic front; otherwise over a hotspot
	spot:        i16,      // the hotspot that built it
	born, last:  f32,      // Myr ago it began, and last erupted
	built, top:  f32,      // m it stands over the ground it was built on, and its top over the sea
}
Known_Hotspot :: struct { at: [2]f32, spot: i16 }
Known :: struct {
	seed:                u32,
	centre, east, north: [3]f32,   // the known world's middle on the planet, and its axes
	samples:             []Known_Sample,
	vents:               [dynamic]Known_Vent,
	hotspots:            [dynamic]Known_Hotspot,   // alive today
	// Made from the above once read (known_finish):
	mass:                []i32,                 // each sample's land mass, from 1, or 0 under the sea
	masses:              [dynamic]Known_Mass,
	inland:              []f32,                 // km behind the coast of land larger than a region; under 0, out to sea from it
	chains:              [dynamic][2][2]f32,    // the hotspots' tracks, as segments from each volcano to the next older
	feet:                [VENT_N*VENT_N][dynamic]i32,   // the volcanoes whose foot reaches each square of the known world,
	tracks:              [VENT_N*VENT_N][dynamic]i32,   // and the tracks within a square of it
	past:                [][PAST]f32,           // each cell of the regional history: how fast its crust rose over its last steps (regional_past)
	took, regional_took: f64,                   // seconds the history and its reading took, and of it the regional history, when not read back
}
Known_Mass :: struct { area: f32, top: int, large: bool }   // km²; its highest sample; larger than a region could hold, or cut by the known world's edge
known: Known

VENT_N :: 50   // squares along a side of the known world that its volcanoes and tracks are filed in, 20 km each

// km a volcano's foot reaches from its top, as the known world's map draws it.
foot :: proc(v: Known_Vent) -> f32 { return v.built/(1000*(0.2 if v.arc else 0.09)) }
vent_square :: proc(at: [2]f32) -> [2]int { return {int((at.x + WINDOW/2)/(WINDOW/VENT_N)), int((at.y + WINDOW/2)/(WINDOW/VENT_N))} }

// A land mass of more than this many km² is land larger than an island a region forms: it is not
// formed yet (step 21), and stands in the record as the continent's.
LARGE :: f32(400)

// A point of the planet as km east and south of the known world's middle.
window_of :: proc(p: [3]f32) -> [2]f32 {
	q := p/linalg.dot(p, globe.window) - globe.window
	return {linalg.dot(q, globe.east), -linalg.dot(q, globe.north)}*PLANET
}

// Read the known world from the regional history that has just run (regional_history), its
// cells blended between the four round each sample.
known_read :: proc() {
	r := &regional
	k := &known
	k^ = {seed = world_seed, centre = r.window, east = r.east, north = r.north, samples = make([]Known_Sample, KNOWN_N*KNOWN_N), past = regional_past()}
	globe = r
	defer globe = &planet
	crew_run(KNOWN_N*KNOWN_N, proc(id, lo, hi: int) {
		r := &regional
		for i in lo..<hi {
			e, s := (f32(i%KNOWN_N) + 0.5)*KNOWN_STEP - WINDOW/2, (f32(i/KNOWN_N) + 0.5)*KNOWN_STEP - WINDOW/2
			p := window_point(e, s)
			cells, share := square(e, s)
			// A field blended over the cells that have it: a distance to a boundary is had only on its own plate.
			blend :: proc(cells: [4]i32, share: [4]f32, v: []f32, f: proc(c: i32) -> f32 = nil) -> f32 {
				sum, total: f32
				for c, j in cells do if v[c] < 1e8 {
					sum += share[j]*(f(c) if f != nil else v[c])
					total += share[j]
				}
				return sum/total if total > 0 else 1e4
			}
			o := &known.samples[i]
			o.front = blend(cells, share, r.dist[.Front][:])
			o.setback = blend(cells, share, r.dist[.Front][:], proc(c: i32) -> f32 { return arc_front(regional.from[.Front][c]) })
			o.slab = blend(cells, share, r.dist[.Slab][:])
			o.rising = blend(cells, share, r.rose)/1000
			most := 0
			for c, j in cells {
				// The ground and its relief, read where the crust formed so that it moves with it.
				cr := r.crust[c]
				amp: f32 = 350 if cr.cont else 260 if cr.thick > 12 else 150
				o.h += share[j]*(r.h[c] - r.sea + amp*noise3(linalg.quaternion_mul_vector3(conj(cr.q), p), 160, 6, world_seed + 31))
				o.age += share[j]*(r.t - cr.born)
				o.thick += share[j]*cr.thick
				if share[j] > share[most] do most = j
			}
			o.row, o.cont, o.plate = u8(setting_row(int(cells[most]))), r.crust[cells[most]].cont, r.crust[cells[most]].plate
		}
	})
	for v in r.volcanoes do if !v.gone && v.built > 0 && km(v.at, r.window) < WINDOW {
		append(&k.vents, Known_Vent{at = window_of(v.at), arc = v.arc, spot = v.spot, born = -v.born, last = -v.last, built = v.built, top = v.top})
	}
	for h, i in r.hotspots do if r.t >= h.from && r.t < h.until && km(h.at, r.window) < WINDOW do append(&k.hotspots, Known_Hotspot{window_of(h.at), i16(i)})
}

// The four cells of the regional history round a point of the known world, km east and south of
// its middle, and their shares.
square :: proc(e, s: f32) -> (cells: [4]i32, share: [4]f32) {
	u, v := (e + REGION_SIDE/2)/REGION_KM - 0.5, (s + REGION_SIDE/2)/REGION_KM - 0.5
	i, j := clamp(int(math.floor(u)), 0, REGION_N - 2), clamp(int(math.floor(v)), 0, REGION_N - 2)
	fx, fy := clamp(u - f32(i), 0, 1), clamp(v - f32(j), 0, 1)
	c := i32(j*REGION_N + i)
	return {c, c + 1, c + REGION_N, c + REGION_N + 1}, {(1 - fx)*(1 - fy), fx*(1 - fy), (1 - fx)*fy, fx*fy}
}

// How fast the crust at a point of the known world rose over each of the regional history's last
// PAST steps, newest first, mm/yr.
past_at :: proc(at: [2]f32) -> (rates: [PAST]f32) {
	cells, share := square(at.x, at.y)
	for c, j in cells do rates += share[j]*known.past[c]
	return
}

// What is made from the samples once they are read: the land masses, how far each place lies
// behind the coast of land larger than a region, and the hotspots' tracks.
known_finish :: proc() {
	k := &known
	N :: KNOWN_N
	k.mass, k.inland = make([]i32, N*N), make([]f32, N*N)
	stack := make([dynamic]int, context.temp_allocator)
	for start in 0..<N*N do if k.samples[start].h > 0 && k.mass[start] == 0 {
		append(&k.masses, Known_Mass{top = start})
		id := i32(len(k.masses))
		m := &k.masses[id - 1]
		k.mass[start] = id
		append(&stack, start)
		for len(stack) > 0 {
			c := pop(&stack)
			m.area += KNOWN_STEP*KNOWN_STEP
			if k.samples[c].h > k.samples[m.top].h do m.top = c
			x, y := c%N, c/N
			if x == 0 || y == 0 || x == N - 1 || y == N - 1 do m.large = true
			for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				nx, ny := x + d.x, y + d.y
				if nx < 0 || ny < 0 || nx >= N || ny >= N do continue
				if n := ny*N + nx; k.samples[n].h > 0 && k.mass[n] == 0 { k.mass[n] = id; append(&stack, n) }
			}
		}
		m.large ||= m.area > LARGE
	}
	// km to the coast of large land, by two sweeps of the grid, then signed: over 0 on that land.
	on := proc(k: ^Known, c: int) -> bool { return k.mass[c] > 0 && k.masses[k.mass[c] - 1].large }
	for c in 0..<N*N {
		k.inland[c] = 1e4
		x, y := c%N, c/N
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do if nx, ny := x + d.x, y + d.y; nx >= 0 && ny >= 0 && nx < N && ny < N && on(k, ny*N + nx) != on(k, c) do k.inland[c] = 0.5*KNOWN_STEP
	}
	steps := [4][3]f32{{-1, 0, 1}, {0, -1, 1}, {-1, -1, math.SQRT_TWO}, {1, -1, math.SQRT_TWO}}
	for pass in 0..<2 {
		for i in 0..<N*N {
			c := i if pass == 0 else N*N - 1 - i
			x, y := c%N, c/N
			for s in steps {
				dx, dy := int(s.x) if pass == 0 else -int(s.x), int(s.y) if pass == 0 else -int(s.y)
				if nx, ny := x + dx, y + dy; nx >= 0 && ny >= 0 && nx < N do if ny < N do k.inland[c] = min(k.inland[c], k.inland[ny*N + nx] + s.z*KNOWN_STEP)
			}
		}
	}
	for c in 0..<N*N do if !on(k, c) do k.inland[c] = -k.inland[c]
	// Each volcano filed in every square its foot reaches.
	for v, i in k.vents {
		lo, hi := vent_square(v.at - foot(v)), vent_square(v.at + foot(v))
		for y in max(lo.y, 0)..=min(hi.y, VENT_N - 1) do for x in max(lo.x, 0)..=min(hi.x, VENT_N - 1) do append(&k.feet[y*VENT_N + x], i32(i))
	}
	// Each hotspot's volcanoes, youngest first from the hotspot itself, joined where they lie close
	// enough to be one track.
	for spot in i16(0)..<i16(64) {
		chain := make([dynamic]Known_Vent, context.temp_allocator)
		for h in k.hotspots do if h.spot == spot do append(&chain, Known_Vent{at = h.at, born = -1})
		for v in k.vents do if !v.arc && v.spot == spot do append(&chain, v)
		for i in 1..<len(chain) do for j := i; j > 0 && chain[j].born < chain[j - 1].born; j -= 1 do chain[j], chain[j - 1] = chain[j - 1], chain[j]
		for i in 1..<len(chain) do if linalg.length(chain[i].at - chain[i - 1].at) < 150 do append(&k.chains, [2][2]f32{chain[i - 1].at, chain[i].at})
	}
	for c, i in k.chains {
		lo, hi := vent_square(linalg.min(c[0], c[1])) - 2, vent_square(linalg.max(c[0], c[1])) + 2
		for y in max(lo.y, 0)..=min(hi.y, VENT_N - 1) do for x in max(lo.x, 0)..=min(hi.x, VENT_N - 1) do append(&k.tracks[y*VENT_N + x], i32(i))
	}
}

// The known world's samples at a point, km east and south of its middle, blended between the four
// round it; out of it, the open ocean.
known_at :: proc(at: [2]f32) -> (o: Known_Sample, inland: f32) {
	u, v := (at.x + WINDOW/2)/KNOWN_STEP - 0.5, (at.y + WINDOW/2)/KNOWN_STEP - 0.5
	if !(u >= 0 && v >= 0 && u <= KNOWN_N - 1 && v <= KNOWN_N - 1) do return {h = -5000, front = 1e4, setback = 200, slab = 1e4, age = 100, row = u8(len(PLATE_SETTINGS) - 1)}, -1e4
	i, j := min(int(u), KNOWN_N - 2), min(int(v), KNOWN_N - 2)
	fx, fy := u - f32(i), v - f32(j)
	share := [4]f32{(1 - fx)*(1 - fy), fx*(1 - fy), (1 - fx)*fy, fx*fy}
	at := [4]int{j*KNOWN_N + i, j*KNOWN_N + i + 1, (j + 1)*KNOWN_N + i, (j + 1)*KNOWN_N + i + 1}
	over, slab: [3]f32   // front, setback and weight, where the plate is over a slab; slab and weight before a trench
	for c, q in at {
		s := known.samples[c]
		o.h += share[q]*s.h
		o.age += share[q]*s.age
		o.rising += share[q]*s.rising
		o.thick += share[q]*s.thick
		inland += share[q]*known.inland[c]
		if s.front < 1e3 do over += share[q]*[3]f32{s.front, s.setback, 1}
		if s.slab < 1e3 do slab += share[q]*[3]f32{s.slab, 0, 1}
	}
	o.front, o.setback = 1e4, 200
	if over.z > 0.5 do o.front, o.setback = over.x/over.z, over.y/over.z
	o.slab = slab.x/slab.z if slab.z > 0.5 else 1e4
	near := known.samples[at[int(fx > 0.5) + 2*int(fy > 0.5)]]
	o.row, o.cont, o.plate = near.row, near.cont, near.plate
	return
}

// km from the nearest hotspot's track, exact within 40 km; 1e4 with none within reach.
track_at :: proc(at: [2]f32) -> f32 {
	d := f32(1e4)
	q := vent_square(at)
	if q.x < 0 || q.y < 0 || q.x >= VENT_N || q.y >= VENT_N do return d
	for i in known.tracks[q.y*VENT_N + q.x] {
		a, b := known.chains[i][0], known.chains[i][1]
		t := clamp(linalg.dot(at - a, b - a)/max(linalg.dot(b - a, b - a), 1e-6), 0, 1)
		d = min(d, linalg.length(at - linalg.lerp(a, b, t)))
	}
	return d
}

// Myr since the land at a point was made: on a volcano's foot, since it was built over its
// hotspot, or since an arc's vent last erupted, and half a million years more, the young cone's
// own, which the regional history's steps of 0.5 Myr cannot tell; elsewhere the crust's age. And
// Myr since the volcano whose foot it lies on began, 1e4 on none.
age_at :: proc(at: [2]f32, crust: f32) -> (age, vent: f32) {
	v, on := vent_under(at)
	if !on do return crust, 1e4
	return v.last + 0.5 if v.arc else v.born, v.born
}

// The volcano whose foot a point of the known world lies on, the nearest its top by its foot's reach.
vent_under :: proc(at: [2]f32) -> (v: Known_Vent, on: bool) {
	best := f32(1)
	if q := vent_square(at); q.x >= 0 && q.y >= 0 && q.x < VENT_N && q.y < VENT_N do for i in known.feet[q.y*VENT_N + q.x] {
		w := known.vents[i]
		if d := linalg.length(w.at - at)/foot(w); d < best do best, v, on = d, w, true
	}
	return
}

// Where the known world of the world's seed is kept: beside the game, named by the seed and by what
// made it, so a change to the history or its reading makes it again.
known_path :: proc() -> string {
	PLATES_SOURCE :: #load_hash("plates.odin", "fnv32a")
	KNOWN_SOURCE :: #load_hash("known.odin", "fnv32a")
	helpers := hash(12345, 678, 9) ~ transmute(u32)smoothstep(0, 1, 0.3)   // the noise's hash and blend, which live elsewhere
	return fmt.tprintf("%s/worlds/known-%d-%08x.bin", os.dir(os.args[0]), world_seed, u32(PLATES_SOURCE) ~ u32(KNOWN_SOURCE) ~ helpers*16777619)
}

Known_Header :: struct { magic, seed: u32, samples, vents, hotspots, past: i32, centre, east, north: [3]f32 }
KNOWN_MAGIC :: 0x4b4e5730   // "0WNK"

known_save :: proc(path: string) {
	k := &known
	h := Known_Header{KNOWN_MAGIC, k.seed, i32(len(k.samples)), i32(len(k.vents)), i32(len(k.hotspots)), i32(len(k.past)), k.centre, k.east, k.north}
	out := make([dynamic]u8, context.temp_allocator)
	append(&out, ..mem.ptr_to_bytes(&h))
	append(&out, ..mem.slice_to_bytes(k.samples))
	append(&out, ..mem.slice_to_bytes(k.vents[:]))
	append(&out, ..mem.slice_to_bytes(k.hotspots[:]))
	append(&out, ..mem.slice_to_bytes(k.past))
	_ = os.make_directory(os.dir(path))
	// Written whole under another name and then renamed, so a game reading it never sees half.
	temp := fmt.tprintf("%s.%d", path, os.get_pid())
	if err := os.write_entire_file(temp, out[:]); err == nil { _ = os.rename(temp, path) } else { fmt.eprintln("could not keep the known world in", temp, err) }
}

known_load :: proc(path: string) -> bool {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil || len(data) < size_of(Known_Header) do return false
	h := (^Known_Header)(raw_data(data))^
	body := data[size_of(Known_Header):]
	sizes := [4]int{int(h.samples)*size_of(Known_Sample), int(h.vents)*size_of(Known_Vent), int(h.hotspots)*size_of(Known_Hotspot), int(h.past)*size_of([PAST]f32)}
	if h.magic != KNOWN_MAGIC || h.seed != world_seed || int(h.samples) != KNOWN_N*KNOWN_N || int(h.past) != REGION_N*REGION_N || len(body) != sizes[0] + sizes[1] + sizes[2] + sizes[3] do return false
	k := &known
	k^ = {seed = h.seed, centre = h.centre, east = h.east, north = h.north, samples = make([]Known_Sample, h.samples)}
	copy(mem.slice_to_bytes(k.samples), body[:sizes[0]])
	resize_dynamic_array(&k.vents, int(h.vents))
	copy(mem.slice_to_bytes(k.vents[:]), body[sizes[0]:][:sizes[1]])
	resize_dynamic_array(&k.hotspots, int(h.hotspots))
	copy(mem.slice_to_bytes(k.hotspots[:]), body[sizes[0] + sizes[1]:][:sizes[2]])
	k.past = make([][PAST]f32, h.past)
	copy(mem.slice_to_bytes(k.past), body[sizes[0] + sizes[1] + sizes[2]:])
	return true
}

// The known world of the world's seed: read back from where it was kept, or made by running the
// history (about 2.3 s on its crew of threads) and kept.
known_make :: proc() {
	if !known_load(known_path()) {
		started := time.now()
		crew_init()
		regional_wanted = true
		plates_history(nil, "")
		regional_wanted = false
		window_choose()
		took := regional_history()
		known_read()
		crew_end()
		globe_free()
		known.took, known.regional_took = time.duration_seconds(time.since(started)), took
		known_save(known_path())   // made again: the history frees the temporary memory as it runs
	}
	known_finish()
}

// Let the histories' grids go once the known world is read from them.
globe_free :: proc() {
	for g in ([2]^Globe{&planet, &regional}) {
		delete(g.centre); delete(g.area); delete(g.nbr); delete(g.block); delete(g.near); delete(g.masks)
		delete(g.crust); delete(g.next); delete(g.h); delete(g.sank); delete(g.src); delete(g.before); delete(g.setback)
		delete(g.bound); delete(g.collide); delete(g.fresh); delete(g.worn); delete(g.flow); delete(g.incoming); delete(g.rose)
		for f in Globe_Field { delete(g.dist[f]); delete(g.from[f]) }
		delete(g.volcanoes); delete(g.hotspots); delete(g.events)
		g^ = {}
	}
	for &f in spread_buckets do for &b in f { delete(b); b = nil }
	globe = &planet
}
