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
	took:                f64,                   // seconds the history and its reading took, when not read back
}
Known_Mass :: struct { area: f32, top: int, large: bool }   // km²; its highest sample; larger than a region could hold, or cut by the known world's edge
known: Known

// A land mass of more than this many km² is land larger than an island a region forms: it is not
// formed yet (step 21), and stands in the record as the continent's.
LARGE :: f32(400)

// A point of the planet as km east and south of the known world's middle.
window_of :: proc(p: [3]f32) -> [2]f32 {
	q := p/linalg.dot(p, globe.window) - globe.window
	return {linalg.dot(q, globe.east), -linalg.dot(q, globe.north)}*PLANET
}

// Read the known world from the history that has just run, its window chosen.
known_read :: proc() {
	g := &globe
	k := &known
	k^ = {seed = world_seed, centre = g.window, east = g.east, north = g.north, samples = make([]Known_Sample, KNOWN_N*KNOWN_N)}
	// Each cell's rise over the last step: its height over the sea against that of the cell its
	// crust came from; new ocean floor deepens as it cools.
	known_rise = make([]f32, GLOBE_CELLS)
	defer delete(known_rise)
	for c in 0..<GLOBE_CELLS {
		s := g.src[c]
		known_rise[c] = ((g.h[c] - g.sea) - g.before[s])/(DT*1000) if s >= 0 else (ocean_depth(DT) - ocean_depth(2*DT))/(DT*1000)
	}
	crew_run(KNOWN_N*KNOWN_N, proc(id, lo, hi: int) {
		g := &globe
		for i in lo..<hi {
			e, s := (f32(i%KNOWN_N) + 0.5)*KNOWN_STEP - WINDOW/2, (f32(i/KNOWN_N) + 0.5)*KNOWN_STEP - WINDOW/2
			p := window_point(e, s)
			cells, share := corners(warped(p))
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
			o.h = fine_height(p, nil)
			o.front = blend(cells, share, g.dist[.Front][:])
			o.setback = blend(cells, share, g.dist[.Front][:], proc(c: i32) -> f32 { return arc_front(globe.from[.Front][c]) })
			o.slab = blend(cells, share, g.dist[.Slab][:])
			o.rising = blend(cells, share, known_rise)
			most := 0
			for c, j in cells {
				o.age += share[j]*(g.t - g.crust[c].born)
				o.thick += share[j]*g.crust[c].thick
				if share[j] > share[most] do most = j
			}
			o.row, o.cont = u8(setting_row(int(cells[most]))), g.crust[cells[most]].cont
		}
	})
	for v in g.volcanoes do if !v.gone && v.built > 0 && km(v.at, g.window) < WINDOW {
		append(&k.vents, Known_Vent{at = window_of(v.at), arc = v.arc, spot = v.spot, born = -v.born, last = -v.last, built = v.built, top = v.top})
	}
	for h, i in g.hotspots do if g.t >= h.from && g.t < h.until && km(h.at, g.window) < WINDOW do append(&k.hotspots, Known_Hotspot{window_of(h.at), i16(i)})
}
known_rise: []f32

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
	// Each hotspot's volcanoes, youngest first from the hotspot itself, joined where they lie close
	// enough to be one track.
	for spot in i16(0)..<i16(64) {
		chain := make([dynamic]Known_Vent, context.temp_allocator)
		for h in k.hotspots do if h.spot == spot do append(&chain, Known_Vent{at = h.at, born = -1})
		for v in k.vents do if !v.arc && v.spot == spot do append(&chain, v)
		for i in 1..<len(chain) do for j := i; j > 0 && chain[j].born < chain[j - 1].born; j -= 1 do chain[j], chain[j - 1] = chain[j - 1], chain[j]
		for i in 1..<len(chain) do if linalg.length(chain[i].at - chain[i - 1].at) < 150 do append(&k.chains, [2][2]f32{chain[i - 1].at, chain[i].at})
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
	o.row, o.cont = near.row, near.cont
	return
}

// km from the nearest hotspot's track; 1e4 with none within reach.
track_at :: proc(at: [2]f32) -> f32 {
	d := f32(1e4)
	for s in known.chains {
		a, b := s[0], s[1]
		t := clamp(linalg.dot(at - a, b - a)/max(linalg.dot(b - a, b - a), 1e-6), 0, 1)
		d = min(d, linalg.length(at - linalg.lerp(a, b, t)))
	}
	return d
}

// Myr since the land at a point was made: on a volcano's foot, since it was built over its
// hotspot, or since an arc's vent last erupted, and half a million years more, the young cone's
// own, which the history's steps of 2 Myr cannot tell; elsewhere the crust's age.
age_at :: proc(at: [2]f32, crust: f32) -> f32 {
	best, age := f32(1), crust
	for v in known.vents {
		foot := v.built/(1000*(0.2 if v.arc else 0.09))   // km, as the known world's map draws it
		if d := linalg.length(v.at - at)/foot; d < best do best, age = d, v.last + 0.5 if v.arc else v.born
	}
	return age
}

// Where the known world of the world's seed is kept: beside the game, named by the seed and by what
// made it, so a change to the history or its reading makes it again.
known_path :: proc() -> string {
	PLATES_SOURCE :: #load_hash("plates.odin", "fnv32a")
	KNOWN_SOURCE :: #load_hash("known.odin", "fnv32a")
	helpers := hash(12345, 678, 9) ~ transmute(u32)smoothstep(0, 1, 0.3)   // the noise's hash and blend, which live elsewhere
	return fmt.tprintf("%s/worlds/known-%d-%08x.bin", os.dir(os.args[0]), world_seed, u32(PLATES_SOURCE) ~ u32(KNOWN_SOURCE) ~ helpers*16777619)
}

Known_Header :: struct { magic, seed: u32, samples, vents, hotspots: i32, centre, east, north: [3]f32 }
KNOWN_MAGIC :: 0x4b4e5730   // "0WNK"

known_save :: proc(path: string) {
	k := &known
	h := Known_Header{KNOWN_MAGIC, k.seed, i32(len(k.samples)), i32(len(k.vents)), i32(len(k.hotspots)), k.centre, k.east, k.north}
	out := make([dynamic]u8, context.temp_allocator)
	append(&out, ..mem.ptr_to_bytes(&h))
	append(&out, ..mem.slice_to_bytes(k.samples))
	append(&out, ..mem.slice_to_bytes(k.vents[:]))
	append(&out, ..mem.slice_to_bytes(k.hotspots[:]))
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
	sizes := [3]int{int(h.samples)*size_of(Known_Sample), int(h.vents)*size_of(Known_Vent), int(h.hotspots)*size_of(Known_Hotspot)}
	if h.magic != KNOWN_MAGIC || h.seed != world_seed || int(h.samples) != KNOWN_N*KNOWN_N || len(body) != sizes[0] + sizes[1] + sizes[2] do return false
	k := &known
	k^ = {seed = h.seed, centre = h.centre, east = h.east, north = h.north, samples = make([]Known_Sample, h.samples)}
	copy(mem.slice_to_bytes(k.samples), body[:sizes[0]])
	resize_dynamic_array(&k.vents, int(h.vents))
	copy(mem.slice_to_bytes(k.vents[:]), body[sizes[0]:][:sizes[1]])
	resize_dynamic_array(&k.hotspots, int(h.hotspots))
	copy(mem.slice_to_bytes(k.hotspots[:]), body[sizes[0] + sizes[1]:])
	return true
}

// The known world of the world's seed: read back from where it was kept, or made by running the
// history (about 2.3 s on its crew of threads) and kept.
known_make :: proc() {
	if !known_load(known_path()) {
		started := time.now()
		crew_init()
		plates_history(nil, "")
		window_choose()
		known_read()
		crew_end()
		globe_free()
		known.took = time.duration_seconds(time.since(started))
		known_save(known_path())   // made again: the history frees the temporary memory as it runs
	}
	known_finish()
}

// Let the history's grids go once the known world is read from them.
globe_free :: proc() {
	g := &globe
	delete(g.centre); delete(g.area); delete(g.nbr); delete(g.block); delete(g.near); delete(g.masks)
	delete(g.crust); delete(g.next); delete(g.h); delete(g.sank); delete(g.src); delete(g.before); delete(g.setback)
	delete(g.bound); delete(g.collide); delete(g.fresh); delete(g.worn)
	for f in Globe_Field { delete(g.dist[f]); delete(g.from[f]) }
	delete(g.volcanoes); delete(g.hotspots); delete(g.events)
	for &f in spread_buckets do for &b in f { delete(b); b = nil }
	g^ = {}
}
