package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:time"

// The plate history as a research run (--plates=dir, --plates-why=x,z): keep frames through the
// history that plates.odin runs, draw them and the known world's map, write the grids
// tools/plates_compare.py measures against the real Earth's plate history
// (docs/interesting-world/notes/real-plates.md), and follow one point's crust through time. The
// game reads the history through known.odin and needs none of this.

// What is kept of each frame through the history, to draw once the known world is chosen.
Snap_Cell :: struct { plate, bound, age, kind: u8, h: i16 }   // kind: 0 ocean, 1 continent, 2 ocean floor an arc has built on
Snap :: struct {
	t:         f32,
	cells:     []Snap_Cell,
	spins:     [MAX_PLATES][3]f32,
	serials:   [MAX_PLATES]int,
	volcanoes: [dynamic][4]f32,   // where, and its height over the sea, negative for an arc vent's, which are drawn apart
	hotspots:  [dynamic][3]f32,
}

snap_take :: proc() -> Snap {
	g := globe
	s := Snap{t = g.t, cells = make([]Snap_Cell, GLOBE_CELLS)}
	for c in 0..<GLOBE_CELLS {
		cr := g.crust[c]
		kind: u8 = 1 if cr.cont else 2 if cr.thick > 12 else 0
		s.cells[c] = {plate = cr.plate, bound = g.bound[c], age = u8(clamp(g.t - cr.born, 0, 255)), kind = kind, h = i16(clamp(g.h[c] - g.sea, -12000, 9000))}
	}
	for p, i in g.plates do s.spins[i], s.serials[i] = p.spin, p.serial
	for v in g.volcanoes do if !v.gone && g.t - v.last < 2*DT || v.top > 0 && !v.gone {
		append(&s.volcanoes, [4]f32{v.at.x, v.at.y, v.at.z, v.top if !v.arc else -1 - max(v.top, 0)})
	}
	for h in g.hotspots do if g.t >= h.from && g.t < h.until do append(&s.hotspots, h.at)
	return s
}

sphere_point :: proc(lon, lat: f32) -> [3]f32 { return {math.cos(lat)*math.cos(lon), math.cos(lat)*math.sin(lon), math.sin(lat)} }

hue :: proc(serial: int) -> [3]f32 {
	a := f32(serial)*2.39996
	return 0.62 + 0.25*[3]f32{math.cos(a), math.cos(a - 2.1), math.cos(a + 2.1)}
}
land_colour :: proc(h: f32) -> [3]f32 {
	t := clamp(h/4000, 0, 1)
	return linalg.lerp(linalg.lerp([3]f32{0.36, 0.56, 0.26}, [3]f32{0.70, 0.62, 0.40}, clamp(t*3, 0, 1)), [3]f32{0.95, 0.94, 0.92}, clamp(t*2 - 1, 0, 1))
}

// A frame: above, the plates, their motion and their boundaries (red converging, yellow spreading,
// white sliding), hotspots ringed; below, the crust (ocean floor pale where young, dark where old,
// continent under the sea grey-blue, ocean floor arcs built on violet), land by height, volcanoes
// standing over the sea as dots, active arc vents red. The known world is boxed in magenta.
FW, FH :: 1200, 600
frame_draw :: proc(s: ^Snap, path: string) {
	pixels := make([]u8, FW*FH*2*4)
	defer delete(pixels)
	put :: proc(pixels: []u8, x, y: int, c: [3]f32) {
		if x < 0 || y < 0 || x >= FW || y >= 2*FH do return
		for k in 0..<3 do pixels[(y*FW + x)*4 + k] = u8(clamp(c[k], 0, 1)*255)
	}
	cells := make([]int, FW*FH, context.temp_allocator)
	for py in 0..<FH do for px in 0..<FW do cells[py*FW + px] = cell_of(sphere_point((f32(px) + 0.5)/FW*2*math.PI - math.PI, math.PI/2 - (f32(py) + 0.5)/FH*math.PI))
	for py in 0..<FH do for px in 0..<FW {
		c := s.cells[cells[py*FW + px]]
		right, below := s.cells[cells[py*FW + (px + 1)%FW]], s.cells[cells[min(py + 1, FH - 1)*FW + px]]
		col := hue(s.serials[c.plate])*(0.72 if c.kind == 1 else 1)
		if right.plate != c.plate || below.plate != c.plate {
			b := max(c.bound, right.bound if right.plate != c.plate else 0)
			lines := [4][3]f32{{0.3, 0.3, 0.3}, {0.85, 0.1, 0.1}, {1, 0.85, 0.1}, {1, 1, 1}}
			col = lines[b]
		}
		put(pixels, px, py, col)
		h := f32(c.h)
		low := clamp(f32(c.age)/180, 0, 1)
		col = linalg.lerp([3]f32{0.55, 0.78, 0.95}, [3]f32{0.04, 0.12, 0.38}, math.sqrt(low))
		if c.kind == 1 do col = [3]f32{0.55, 0.68, 0.74}
		if c.kind == 2 do col = linalg.lerp(col, [3]f32{0.55, 0.35, 0.75}, 0.6)
		if h > 0 do col = land_colour(h)
		put(pixels, px, FH + py, col)
	}
	to_pixel :: proc(p: [3]f32) -> (int, int) {
		lon, lat := math.atan2(p.y, p.x), math.asin(clamp(p.z, -1, 1))
		return int((lon + math.PI)/(2*math.PI)*FW), int((math.PI/2 - lat)/math.PI*FH)
	}
	// Arrows of motion, a pixel for each 4 mm/yr, from points 30 pixels apart.
	for py := 15; py < FH; py += 30 do for px := 15; px < FW; px += 30 {
		lat := math.PI/2 - (f32(py) + 0.5)/FH*math.PI
		lon := (f32(px) + 0.5)/FW*2*math.PI - math.PI
		p := sphere_point(lon, lat)
		c := s.cells[cell_of(p)]
		v := linalg.cross(s.spins[c.plate], p)*PLANET
		e, n := east_north(p)
		ve, vn := linalg.dot(v, e), linalg.dot(v, n)
		for k in 0..<int(math.hypot(ve, vn)/4) {
			f := f32(k)/max(math.hypot(ve, vn)/4, 1)
			put(pixels, px + int(ve/4*f/max(math.cos(lat), 0.5)), py - int(vn/4*f), {0.1, 0.1, 0.1})
		}
		put(pixels, px, py, {0, 0, 0})
	}
	for h in s.hotspots {
		x, y := to_pixel(h)
		for a in 0..<24 do for row in 0..<2 do put(pixels, x + int(5*math.cos(f32(a)*0.2618)), y + row*FH + int(5*math.sin(f32(a)*0.2618)), {1, 1, 1})
	}
	for v in s.volcanoes {
		x, y := to_pixel(v.xyz)
		col := [3]f32{0.95, 0.25, 0.1} if v.w < 0 else [3]f32{1, 1, 0.6}
		if v.w < 0 && v.w > -1.5 do col = {0.65, 0.2, 0.1}   // an arc vent under the sea
		for dy in 0..=1 do for dx in 0..=1 do put(pixels, x + dx, FH + y + dy, col)
	}
	if globe.window != {} do for row in 0..<2 {
		for i in 0..<400 {
			a := f32(i)/400*WINDOW - WINDOW/2
			for side in 0..<4 {
				u, v := [4]f32{a, a, -WINDOW/2, WINDOW/2}[side], [4]f32{-WINDOW/2, WINDOW/2, a, a}[side]
				x, y := to_pixel(window_point(u, v))
				put(pixels, x, y + row*FH, {1, 0.2, 0.9})
			}
		}
	}
	write_png(path, pixels, FW, 2*FH, false)
}

// The known world today at 1 km a pixel, -z (north) at the top, and its islands counted.
world_draw :: proc(path: string) {
	g := globe
	SIZE :: 1000
	cones := make([dynamic]Cone)
	defer delete(cones)
	for v in g.volcanoes do if !v.gone && v.built > 0 && km(v.at, g.window) < WINDOW {
		append(&cones, Cone{at = v.at, built = v.built, radius = v.built/(1000*(0.2 if v.arc else 0.09))})
	}
	height := make([]f32, SIZE*SIZE)
	defer delete(height)
	local := make([dynamic]Cone)
	defer delete(local)
	for py in 0..<SIZE do for px in 0..<SIZE {
		p := window_point(f32(px) + 0.5 - SIZE/2, f32(py) + 0.5 - SIZE/2)
		clear(&local)
		for v in cones do if km(p, v.at) < v.radius do append(&local, v)
		height[py*SIZE + px] = fine_height(p, local[:])
	}
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	for py in 0..<SIZE do for px in 0..<SIZE {
		h := height[py*SIZE + px]
		gx := height[py*SIZE + min(px + 1, SIZE - 1)] - height[py*SIZE + max(px - 1, 0)]
		gy := height[min(py + 1, SIZE - 1)*SIZE + px] - height[max(py - 1, 0)*SIZE + px]
		shade := clamp(0.8 + (-gx - gy)/600, 0.4, 1.25)
		col := land_colour(h)*shade if h > 0 else linalg.lerp([3]f32{0.45, 0.70, 0.88}, [3]f32{0.05, 0.14, 0.38}, clamp(-h/5000, 0, 1))
		for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
	}
	// Each land mass, by flood fill: what is cut by the window's edge is the continent's.
	group := make([]i32, SIZE*SIZE)
	defer delete(group)
	sizes, edges := make([dynamic]int, context.temp_allocator), make([dynamic]bool, context.temp_allocator)
	stack := make([dynamic]int, context.temp_allocator)
	for start in 0..<SIZE*SIZE do if height[start] > 0 && group[start] == 0 {
		append(&sizes, 0); append(&edges, false)
		id := i32(len(sizes))
		group[start] = id
		append(&stack, start)
		for len(stack) > 0 {
			c := pop(&stack)
			sizes[id - 1] += 1
			x, y := c%SIZE, c/SIZE
			if x == 0 || y == 0 || x == SIZE - 1 || y == SIZE - 1 do edges[id - 1] = true
			for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				nx, ny := x + d.x, y + d.y
				if nx < 0 || ny < 0 || nx >= SIZE || ny >= SIZE do continue
				if n := ny*SIZE + nx; height[n] > 0 && group[n] == 0 { group[n] = id; append(&stack, n) }
			}
		}
	}
	write_png(path, pixels, SIZE, SIZE, false)
	islands := make([dynamic]int, context.temp_allocator)
	mainland := 0
	for s, i in sizes { if edges[i] && s >= 5000 { mainland += s } else { append(&islands, s) } }
	slice.reverse_sort(islands[:])
	fmt.printf("the known world, 1,000 km across at %.1f° N: %d km² of continent cut by its edges and %d islands of 1 km² or more", math.to_degrees(math.asin(g.window.z)), mainland, len(islands))
	if len(islands) > 0 do fmt.printf(", the largest %d km²", islands[0])
	over := [3]int{}
	for s in islands do for b, k in ([3]int{10, 100, 1000}) do if s >= b do over[k] += 1
	fmt.printfln("; %d over 10 km², %d over 100, %d over 1,000", over[0], over[1], over[2])
	// The islands by what made the ground under their middle.
	kinds := make(map[string]int, context.temp_allocator)
	middles := make([][2]int, len(sizes), context.temp_allocator)
	counts := make([]int, len(sizes), context.temp_allocator)
	for c in 0..<SIZE*SIZE do if id := group[c]; id > 0 { middles[id - 1] += {c%SIZE, c/SIZE}; counts[id - 1] += 1 }
	for s, i in sizes do if !(edges[i] && s >= 5000) {
		m := middles[i]/counts[i]
		kinds[setting_of(cell_of(window_point(f32(m.x) - SIZE/2, f32(m.y) - SIZE/2)))] += 1
	}
	fmt.print("  islands by setting:")
	for k, n in kinds do fmt.printf(" %s %d,", k, n)
	fmt.println()
}

// The comparison grids (tools/plates_compare.py): each frame on half-degree cells of latitude and
// longitude, from the north pole and the date line: plate, crust (0 ocean, 1 continent, 2 arc-built
// ocean floor), ocean floor's age in Myr, ground over the sea in m, motion east and north in mm/yr.
raw_write :: proc(path: string) {
	g := globe
	W, H :: 720, 360
	out := make([dynamic]u8, 0, W*H*9)
	defer delete(out)
	for y in 0..<H do for x in 0..<W {
		p := sphere_point((f32(x) + 0.5)/W*2*math.PI - math.PI, math.PI/2 - (f32(y) + 0.5)/H*math.PI)
		c := cell_of(p)
		cr := g.crust[c]
		v := velocity(int(cr.plate), p)
		e, n := east_north(p)
		kind: u8 = 1 if cr.cont else 2 if cr.thick > 12 else 0
		h := i16(clamp(g.h[c] - g.sea, -12000, 9000))
		ve, vn := i16(clamp(linalg.dot(v, e), -3000, 3000)), i16(clamp(linalg.dot(v, n), -3000, 3000))
		append(&out, cr.plate, kind, u8(clamp(g.t - cr.born, 0, 255)), u8(h), u8(u16(h) >> 8), u8(ve), u8(u16(ve) >> 8), u8(vn), u8(u16(vn) >> 8))
	}
	_ = os.write_entire_file(path, out[:])
}

// --plates=dir: run the history, write its frames and the known world's map, and say what it made.
plates_main :: proc(dir: string) {
	os.make_directory(dir)
	snaps: [dynamic]Snap
	crew_init()
	defer crew_end()
	took := plates_history(&snaps, dir)
	g := globe
	window_choose()
	drawing := time.now()
	for &s in snaps do frame_draw(&s, fmt.tprintf("%s/frame-%03d.png", dir, int(math.round(-s.t))))
	world_draw(fmt.tprintf("%s/world.png", dir))
	fmt.printfln("the plates' history: %.0f Myr in %.0f steps of %.0f Myr on %d cells of about %.0f km, in %.2f s; drawing took %.2f s", SPAN + SPIN_UP, (SPAN + SPIN_UP)/DT, DT, GLOBE_CELLS, math.sqrt(f64(4*math.PI*PLANET*PLANET/GLOBE_CELLS)), took, time.duration_seconds(time.since(drawing)))
	alive, largest := 0, f32(0)
	for p in g.plates do if p.alive { alive += 1; largest = max(largest, p.area) }
	fmt.printfln("%d plates today, the largest %.0f million km²; %d splits and %d joins over the history; the sea %.0f m over the datum", alive, largest/1e6, g.splits, g.merges, g.sea)
	// Land masses on the planet, by flood fill over the cells: continents of a million km² or more.
	group := make([]i32, GLOBE_CELLS)
	defer delete(group)
	masses := make([dynamic]f32)
	defer delete(masses)
	stack := make([dynamic]int)
	defer delete(stack)
	land, cont: f32
	for c in 0..<GLOBE_CELLS {
		if g.crust[c].cont do cont += g.area[c]
		if g.h[c] <= g.sea || group[c] != 0 do continue
		append(&masses, 0)
		group[c] = i32(len(masses))
		append(&stack, c)
		for len(stack) > 0 {
			k := pop(&stack)
			masses[len(masses) - 1] += g.area[k]
			land += g.area[k]
			for n in g.nbr[k][:4] do if g.h[n] > g.sea && group[n] == 0 { group[n] = i32(len(masses)); append(&stack, int(n)) }
		}
	}
	slice.reverse_sort(masses[:])
	whole := f32(4*math.PI*PLANET*PLANET)
	continents, large := 0, 0
	for m in masses { if m >= 1e6 { continents += 1 } else if m >= 1e4 { large += 1 } }
	fmt.printf("land %.1f%% of the planet and continental crust %.1f%%: %d continents of a million km² or more (", 100*land/whole, 100*cont/whole, continents)
	for m, i in masses[:continents] do fmt.printf("%s%.1f", ", " if i > 0 else "", m/1e6)
	islands := 0
	for v in g.volcanoes do if !v.gone && v.top > 0 && g.h[cell_of(v.at)] <= g.sea do islands += 1
	fmt.printfln(" million km²), %d islands of 10,000 km² to a million, and %d volcanoes standing as islands of their own", large, islands)
	// How fast each hotspot's chain ages along its length: the plate's speed over it.
	rates := make([dynamic]f32)
	defer delete(rates)
	for h, k in g.hotspots do if g.t < h.until && g.t >= h.from + 10 {
		sx, sy, sxx, sxy, n: f32
		for v in g.volcanoes do if !v.gone && int(v.spot) == k && !v.arc && g.t - v.born < 40 {
			d, age := km(v.at, h.at), g.t - v.born
			sx += age; sy += d; sxx += age*age; sxy += age*d; n += 1
		}
		if n >= 4 do append(&rates, (n*sxy - sx*sy)/(n*sxx - sx*sx))
	}
	slice.sort(rates[:])
	if len(rates) > 0 do fmt.printfln("%d hotspot chains with volcanoes over the last 40 Myr age along their length at %.0f to %.0f km/Myr (median %.0f)", len(rates), rates[0], rates[len(rates) - 1], rates[len(rates)/2])
	fmt.printfln("frames in %s: frame-250.png (the first continent) to frame-000.png (today), world.png (the known world)", dir)
	for &s in snaps { delete(s.cells); delete(s.volcanoes); delete(s.hotspots) }
	delete(snaps)
}

// --plates-why=x,z: what happened to the ground now at this point of the known world (metres east
// and south of its middle) through the history. The history runs once to find which crust is
// there and where it formed, and again following that crust from then on.
trace_last: string
plates_why :: proc(x, z: f64) {
	g := globe
	crew_init()
	defer crew_end()
	recording = true
	plates_history(nil, "")
	recording = false
	window_choose()
	here := window_point(f32(x/1000), f32(z/1000))
	c := cell_of(here)
	cr := g.crust[c]
	window, east, north := g.window, g.east, g.north
	// Walk back from today's cell through where each step's crust came from, to where it formed.
	trace_path = make([]i32, len(trace_steps) + 1)
	defer delete(trace_path)
	trace_path[len(trace_steps)] = i32(c)
	for n := len(trace_steps); n > 0; n -= 1 do trace_path[n - 1] = trace_steps[n - 1][trace_path[n]] if trace_path[n] >= 0 else -1
	for t in trace_steps do delete(t)
	clear(&trace_steps)
	start := max(cr.born, -(SPAN + SPIN_UP))
	fmt.printfln("%.0f km east and %.0f km south of the known world's middle, at %.1f° N %.1f° E of the planet; %s crust %.0f km thick, formed %s", x/1000, z/1000, math.to_degrees(math.asin(here.z)), math.to_degrees(math.atan2(here.y, here.x)), "continental" if cr.cont else "oceanic", cr.thick, fmt.tprintf("%.0f Myr ago", -cr.born) if cr.born > -(SPAN + SPIN_UP) else "before the history began")
	fmt.println("  Myr ago  plate  crust                          ground      setting")
	tracing, trace_from = true, start
	trace_last = ""
	plates_history(nil, "")
	tracing = false
	clear(&trace_steps)
	g.window, g.east, g.north = window, east, north
	for e in g.events do if km(e.at, here) < 1500 && e.t >= start do fmt.printfln("  %.0f Myr ago, %.0f km off: %s (plate %d, %d)", -e.t, km(e.at, here), e.what, e.a, e.b)
	vents := 0
	for v in g.volcanoes do if !v.gone && km(v.at, here) < 60 {
		vents += 1
		if vents <= 8 do fmt.printfln("  %s vent %.0f km off, built from %.0f to %.0f Myr ago, its top %.0f m %s the sea", "an arc" if v.arc else "a hotspot", km(v.at, here), -v.born, -v.last, abs(v.top), "over" if v.top > 0 else "under")
	}
	fmt.printfln("  today: %s", setting_of(c))
}

trace_note :: proc() {
	g := globe
	if g.t < trace_from || trace_path[len(trace_steps)] < 0 do return
	c := cell_of(followed)
	cr := g.crust[c]
	set := setting_of(c)
	if int(math.round(-g.t))%FRAME_EVERY != 0 && set == trace_last do return
	trace_last = set
	crust := fmt.tprintf("%s %.0f km%s", "continent" if cr.cont else "ocean floor", cr.thick, fmt.tprintf(", %.0f Myr old", g.t - cr.born) if !cr.cont else "")
	fmt.printfln("  %-8s %-6s %-30s %-11s %s", fmt.tprintf("%.0f", max(-g.t, 0)), fmt.tprintf("%d", g.plates[cr.plate].serial), crust, fmt.tprintf("%.0f m", g.h[c] - g.sea), set)
}
