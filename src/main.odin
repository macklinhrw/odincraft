package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import sdl "vendor:sdl3"

// Controls
//   click            capture the mouse        Esc      release it, then quit
//   W A S D          move                     Shift    run, or fly fast
//   Space            jump, or rise            Ctrl     sink (flying)
//   F                walk / fly               1-6      choose the block to place
//   left / right     break / place            [ ]      turn the clock back / forward
//   F2               save a screenshot
//
// Options, each as --name=value
//   pos=x,y,z  above=x,height,z (over the ground)  look=yaw,pitch (degrees)  hour=0..24  fly  size=WxH
//   day=N           day of the year, 0 on 1 January (default: the first fair day from 80, the March
//                   equinox, on): sets the sun's path
//   weather=c[,b]   force the cloud cover, 0 clear to 1 overcast, and the cloud base in metres (default
//                   1000, too high for a cap); otherwise both are drawn from the seed, the day and the hour
//   shot=file.png   wait for the world to load, save one frame and exit
//   after=seconds   with shot: let this much time pass first, so water can move; with bench as
//                   well, the frame is saved then without waiting, in mid-flight. A picture's birds and
//                   fish are posed this many seconds into the hour, so two runs show the same ones
//   dig=x0,y0,z0,x1,y1,z1   once the world has loaded, clear this box of blocks; may be repeated
//   probe=x0,z0,x1,z1       on exit, print the ground and water in these columns
//   seed=N          which world: every random choice is keyed from it (default 7)
//   island=N        which island near the start the start, map, why, survey and place act on (default 0,
//                   the start island at the origin); it says all its start-up lines
//   near=km         the islands within this many km of that one are formed beside it before entering (default 64);
//                   the rest form in the background, nearest first, and the world waits for each
//   kind=name       which kind of island that one is, whatever the seed would pick (names in KINDS, land.odin)
//   origin=x,z      where island 0's middle lies in the world, in whole metres (default 0,0); the
//                   islands near it and the stand-in's plates move with it
//   map=file.png    save a map of the island's land and exit
//   archipelago=file.png   form every island near the start side by side, save a map of them and the
//                   continent they lie off, and exit
//   overlay=name    with map: paint one field over the relief (names in FIELDS, fields.odin)
//   why=x,z         print what the ground is at this point in the world and why, and exit
//   survey          print what the island holds and the ranked candidates for named places, and exit
//   plates=dir      run the world's history of moving plates, write its frames through time, the known
//                   world's map and the comparison grids into dir, say what it made, and exit (plates.odin)
//   plates-why=x,z  print what happened through that history at this point in the world (as for why), and exit
//   place=N         look at named place N (from 1, as start-up lists them) from 1 to 2 km off, flying
//   bench=seconds   travel straight ahead and report frame times: flying at `speed` m/s
//                   with fly, otherwise running on the ground
//   show            with shot or bench: open the window. Without it they draw unseen and take no focus

Options :: struct {
	pos:           [3]f64,
	has_pos:       bool,
	has_look:      bool,
	yaw, pitch:    f32,
	hour, day:     f32,
	has_day:       bool,
	weather:       [2]f32,
	fly, show:     bool,
	width, height: i32,
	shot:          string,
	after:         f64,
	digs:          [dynamic][6]i32,
	probe:         [4]i32,
	has_probe:     bool,
	map_path:      string,
	archipelago:   string,
	overlay:       string,
	above:         bool,
	bench, speed:  f64,
	kind:          string,
	why:           [2]f64,
	has_why:       bool,
	survey:        bool,
	place:         int,
	island:        int,
	near:          f64,
	origin:        [2]i32,
	plates:        string,
	plates_why:    [2]f64,
	has_plates_why: bool,
}

options :: proc() -> Options {
	o := Options{hour = 9.5, day = 80, weather = {-1, -1}, width = 1280, height = 720, speed = 60, near = 64}
	numbers :: proc(s, sep: string, out: []f64) -> bool {
		parts := strings.split(s, sep, context.temp_allocator)
		if len(parts) != len(out) do return false
		for p, i in parts do out[i] = strconv.parse_f64(p) or_return
		return true
	}
	for arg in os.args[1:] {
		name, _, value := strings.partition(strings.trim_prefix(arg, "--"), "=")
		ok := true
		v: [3]f64
		switch name {
		case "pos":   ok = numbers(value, ",", v[:]); o.pos, o.has_pos = v, true
		case "above": ok = numbers(value, ",", v[:]); o.pos, o.has_pos, o.above = v, true, true   // the ground is added once the land is formed
		case "seed":  ok = numbers(value, ",", v[:1]); world_seed = u32(v.x)
		case "overlay": o.overlay = value
		case "kind":  o.kind = value
		case "origin": ok = numbers(value, ",", v[:2]); o.origin = {i32(v.x), i32(v.y)}
		case "island": ok = numbers(value, ",", v[:1]); o.island = int(v.x)
		case "near":  ok = numbers(value, ",", v[:1]); o.near = v.x
		case "look":  ok = numbers(value, ",", v[:2]); o.yaw, o.pitch, o.has_look = f32(v.x), f32(v.y), true
		case "size":  ok = numbers(value, "x", v[:2]); o.width, o.height = i32(v.x), i32(v.y)
		case "hour":  ok = numbers(value, ",", v[:1]); o.hour = f32(v.x)
		case "day":   ok = numbers(value, ",", v[:1]); o.day, o.has_day = f32(v.x), true
		case "weather":
			ok = numbers(value, ",", v[:2]) || numbers(value, ",", v[:1])
			o.weather = {f32(v.x), f32(v.y) if strings.contains(value, ",") else SKY.base[1]}
		case "bench": ok = numbers(value, ",", v[:1]); o.bench = v.x
		case "speed": ok = numbers(value, ",", v[:1]); o.speed = v.x
		case "shot":  o.shot = value
		case "after": ok = numbers(value, ",", v[:1]); o.after = v.x
		case "probe":
			box: [4]f64
			ok = numbers(value, ",", box[:])
			o.probe, o.has_probe = {i32(box[0]), i32(box[1]), i32(box[2]), i32(box[3])}, true
		case "dig":
			box: [6]f64
			ok = numbers(value, ",", box[:])
			append(&o.digs, [6]i32{i32(box[0]), i32(box[1]), i32(box[2]), i32(box[3]), i32(box[4]), i32(box[5])})
		case "map":   o.map_path = value
		case "archipelago": o.archipelago = value
		case "plates": o.plates = value
		case "plates-why": ok = numbers(value, ",", o.plates_why[:]); o.has_plates_why = true
		case "why":   ok = numbers(value, ",", o.why[:]); o.has_why = true
		case "fly":   o.fly = true
		case "survey": o.survey = true
		case "place": ok = numbers(value, ",", v[:1]); o.place = int(v.x)
		case "show":  o.show = true
		case:         ok = false
		}
		if !ok {
			fmt.eprintln("bad option:", arg)
			os.exit(2)
		}
	}
	return o
}

// Start on the bank of the largest river, above the reach the sea floods, facing downstream,
// with no tree within 6 m and no small one within 3, on gentle ground with nothing in the three
// strides ahead to fill the first view if any bank has that; where every bank is wooded closer,
// with none within 3 m and no small one within 1.5. Found relative to the region's middle, returned in the world.
find_start :: proc() -> (pos: [3]f64, yaw: f32) {
	ox, oz := f64(region.origin.x), f64(region.origin.y)
	slice.sort_by(rivers.spots[:], proc(a, b: Spot) -> bool { return a.area > b.area })
	trees: [dynamic]Tree
	defer delete(trees)
	for clear_of in ([2]f32{6, 3}) do for steep in ([2]f32{0.2, 1e9}) do for s in rivers.spots {
		if s.p.y < 12 || land.slope[land_cell(f64(s.p.x), f64(s.p.z))] > steep do continue
		clear(&trees)
		trees_in(i32(s.p.x) - 6, i32(s.p.z) - 6, i32(s.p.x) + 6, i32(s.p.z) + 6, &trees, true)
		near := false
		for t in trees do near ||= max(abs(f32(t.x) - s.p.x), abs(f32(t.z) - s.p.z)) <= (clear_of if t.form <= .Between else clear_of/2)
		if near do continue
		x, z := math.floor(f64(s.p.x)) + 0.5, math.floor(f64(s.p.z)) + 0.5
		if g := ground(x, z, 1); g.water > g.h do continue   // a bank a lake has drowned
		hidden := false   // nor one where a plant or a rise in the three strides ahead fills the first view
		for d in 1..=3 {
			at: Point
			g, m, com := surface_at(x + f64(d)*math.sin(f64(s.yaw)), z - f64(d)*math.cos(f64(s.yaw)), 1, &at)
			kind, ok := plant_at(&at, m, com)
			hidden ||= g.h > s.p.y + 1.5 || ok && (GROUND_PLANTS[kind].tall || g.h > s.p.y + 0.5)
		}
		if hidden && steep < 1 do continue
		return {x + ox, math.round(f64(height_at(x, z, 1))) + 0.1, z + oz}, s.yaw
	}
	return {0.5 + ox, math.round(f64(height_at(0.5, 0.5, 1))) + 0.1, 0.5 + oz}, 0
}

main :: proc() {
	opt := options()
	if opt.plates != "" {
		plates_main(opt.plates)
		return
	}
	quiet_init()
	seed = world_seed   // the islands are made from the world's seed
	// The start island's record is drawn first, at its place; the islands near it and the land they
	// lie off are read from the world's history round it (known.odin, archipelago.odin).
	first: Formed
	first.island, first.region.origin = {origin = opt.origin, size = REFERENCE, seed = world_seed}, opt.origin
	bind(&first)
	if !region_init(opt.kind if opt.island == 0 else "") {
		fmt.eprint("no kind of island named", opt.kind, "; there are:")
		for k in KINDS do fmt.eprint("", k.name)
		fmt.eprintln()
		os.exit(2)
	}
	known_make()
	archipelago_make(opt.archipelago != "")
	if opt.has_plates_why {
		at := known_point(opt.plates_why.x, opt.plates_why.y)*1000
		plates_why(f64(at.x), f64(at.y))
		return
	}
	if opt.island < 0 || opt.island >= len(archipelago) {
		fmt.eprintfln("no island %d: there are %d near the start, from 0", opt.island, len(archipelago))
		os.exit(2)
	}
	if opt.kind != "" && opt.island != 0 {
		kind := -1
		for k, i in KINDS do if k.name == opt.kind do kind = i
		if kind < 0 {
			fmt.eprint("no kind of island named", opt.kind, "; there are:")
			for k in KINDS do fmt.eprint("", k.name)
			fmt.eprintln()
			os.exit(2)
		}
		archipelago[opt.island].kind = kind
	}
	formed = make([]Formed, len(archipelago))
	for &f, i in formed do f.island = archipelago[i]
	home = &formed[opt.island]
	if opt.archipelago != "" {
		archipelago_map(opt.archipelago)
		return
	}
	// The other islands, nearest the start first: those within `near` km formed side by side beside
	// the start island, before entering, and the rest on three threads of low priority once play has
	// begun. A run that exits once the start island is formed forms only that.
	others := make([dynamic]int)
	apart :: proc(i: int) -> f64 { return math.hypot(f64(formed[i].island.origin.x - home.island.origin.x), f64(formed[i].island.origin.y - home.island.origin.y)) }
	if !opt.survey && opt.map_path == "" && !opt.has_why do for _, i in formed do if &formed[i] != home do append(&others, i)
	slice.sort_by(others[:], proc(a, b: int) -> bool { return apart(a) < apart(b) })
	soon := 0
	for soon < len(others) && apart(others[soon]) <= opt.near*1000 do soon += 1
	early := islands_form(others[:soon], max(os.get_processor_core_count() - 1, 1), .Normal, false)
	gen_init(home)
	bind(home)   // the frame thread reads the start island unless it binds another
	if opt.place != 0 {
		if opt.place < 1 || opt.place > len(places) {
			fmt.eprintfln("no place %d: the island has %d named places", opt.place, len(places))
			os.exit(2)
		}
		c := candidates[places[opt.place - 1].c]
		d := [3]f64{c.at.x, f64(c.top), c.at.y} - c.view
		opt.pos, opt.has_pos, opt.has_look, opt.fly = c.view + {f64(region.origin.x), -EYE, f64(region.origin.y)}, true, true, true
		opt.yaw, opt.pitch = f32(math.to_degrees(math.atan2(d.x, -d.z))), f32(math.to_degrees(math.atan2(d.y, math.hypot(d.x, d.z))))
		fmt.printfln("looking at %s from %.0f, %.0f, %.0f m up, %.1f km off", places[opt.place - 1].name, opt.pos.x, opt.pos.z, c.view.y, math.hypot(d.x, d.z)/1000)
	}
	if opt.survey {
		survey_print()
		return
	}
	if opt.map_path != "" {
		land_map(opt.map_path, opt.overlay)
		return
	}
	if opt.has_why {
		why_at(opt.why.x, opt.why.y)
		return
	}
	islands_done(early, others[:soon])
	if opt.above && opt.place == 0 do opt.pos.y += f64(height_in_world(opt.pos.x, opt.pos.z, 1))
	// With no day named, the first fair day from the March equinox on: a person looking at the
	// land sees it in sunlight, and pictures taken on different days of work can be compared.
	if !opt.has_day do for c, _ := weather_at(opt.day, opt.hour); c > FAIR && opt.day < 140; c, _ = weather_at(opt.day, opt.hour) do opt.day += 1
	cover, base := weather_at(opt.day, opt.hour)
	daylight: f32
	for h := f32(0.025); h < 24; h += 0.05 do daylight += 0.05 if sun_dir(h, opt.day).y > 0 else 0
	fmt.printfln("sky on day %.0f at %.1f h: the sun %.0f° high at noon, %.1f h of daylight; drawn cover %.2f, cloud base %.0f m%s",
		opt.day, opt.hour, math.to_degrees(math.asin(sun_dir(12, opt.day).y)), daylight, cover, base, ", forced by --weather" if opt.weather.x >= 0 else "")
	// A run that only takes a picture or measures opens no window and takes no focus: it draws
	// unseen, at the size and pace it would have on a display.
	unseen := (opt.shot != "" || opt.bench > 0) && !opt.show
	// A window is opened only for a person: one asked for by --show, or a run started from a terminal.
	// A script or an agent that forgets --shot or --bench is told so, and nothing appears on the owner's screen.
	if !unseen && !opt.show && !posix.isatty(posix.STDIN_FILENO) {
		fmt.eprintln("no terminal: this run would open the game's window. Add --shot=file or --bench=seconds to draw unseen, or --show if the owner asked to watch")
		os.exit(2)
	}
	if unseen do sdl.SetHint(sdl.HINT_MAC_BACKGROUND_APP, "1")
	if !sdl.Init({.VIDEO}) do fatal("SDL")
	window := sdl.CreateWindow("OdinCraft", opt.width, opt.height, {.RESIZABLE, .HIGH_PIXEL_DENSITY} + ({.HIDDEN} if unseen else {}))
	if window == nil do fatal("window")
	g: Gpu
	gpu_init(&g, window)
	g.unseen = unseen
	w := new(World)
	world_init(w)
	water_init(&w.water, g.dev)

	p := Player{eye = EYE, fly = opt.fly, yaw = math.to_radians(opt.yaw), pitch = math.to_radians(opt.pitch)}
	p.pos = opt.pos
	if !opt.has_pos {
		yaw: f32
		p.pos, yaw = find_start()
		if !opt.has_look do p.yaw = yaw
	}
	islands_form(others[soon:], 3, .Low, false)
	hour := opt.hour
	place := Mat.Stone
	captured := false

	frequency := f64(sdl.GetPerformanceFrequency())
	last := sdl.GetPerformanceCounter()
	seconds, title_at := 0.0, 0.0
	start := p.pos
	intervals: [dynamic]f32   // seconds between frames
	work: [dynamic]f32        // seconds of our own work per frame: everything but the wait for the display
	drawn: [dynamic][4]int    // faces, ground plants, creatures' boxes and quads of water drawn each frame
	idle_frames, title_from := 0, 0

	running := true
	for running {
		now := sdl.GetPerformanceCounter()
		dt := f64(now - last)/frequency
		last = now
		seconds += dt
		append(&intervals, f32(dt))
		dt = min(dt, 0.1)

		break_block, place_block := false, false
		shot := ""
		e: sdl.Event
		for sdl.PollEvent(&e) {
			#partial switch e.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				if e.key.repeat do continue
				#partial switch e.key.scancode {
				case .ESCAPE:
					if captured {
						captured = false
						_ = sdl.SetWindowRelativeMouseMode(window, false)
					} else {
						running = false
					}
				case .F:
					p.fly = !p.fly
					p.vel = 0
				case ._1..=._6:
					place = Mat(int(e.key.scancode) - int(sdl.Scancode._1) + int(Mat.Grass))
				case .F2:
					os.make_directory("screenshots")
					shot = fmt.tprintf("screenshots/%d.png", sdl.GetTicksNS()/1e6)
				}
			case .MOUSE_BUTTON_DOWN:
				if !captured {
					captured = true
					_ = sdl.SetWindowRelativeMouseMode(window, true)
				} else {
					break_block = e.button.button == sdl.BUTTON_LEFT
					place_block = e.button.button == sdl.BUTTON_RIGHT
				}
			case .MOUSE_MOTION:
				if captured {
					p.yaw += e.motion.xrel*0.0022
					p.pitch = clamp(p.pitch - e.motion.yrel*0.0022, -1.55, 1.55)
				}
			}
		}

		keys := sdl.GetKeyboardState(nil)
		down :: proc(keys: [^]bool, s: sdl.Scancode) -> f32 { return 1 if keys[int(s)] else 0 }
		wish := [3]f32{down(keys, .D) - down(keys, .A), down(keys, .SPACE) - down(keys, .LCTRL), down(keys, .W) - down(keys, .S)}
		hour = math.mod(hour + (down(keys, .RIGHTBRACKET) - down(keys, .LEFTBRACKET))*f32(dt)*3 + 24, 24)

		if opt.bench > 0 && p.fly {
			forward := look_dir(p.yaw, 0)
			p.pos += [3]f64{f64(forward.x), 0, f64(forward.z)}*opt.speed*dt
		} else if opt.bench > 0 {
			player_update(&p, w, dt, {0, 0, 1}, false, true)
		} else {
			player_update(&p, w, dt, wish, wish.y > 0, down(keys, .LSHIFT) > 0)
		}
		eye := p.pos + [3]f64{0, p.eye, 0}
		world_update(w, g.dev, eye)
		water_update(&w.water, g.dev, dt)

		look := look_dir(p.yaw, p.pitch)
		hit, before, aiming := raycast(w, eye, look)
		if aiming && break_block do world_set(w, hit.x, hit.y, hit.z, .Air)
		if aiming && place_block {
			// Not inside the player.
			b := [3]f64{f64(before.x), f64(before.y), f64(before.z)}
			clear := b.x + 1 <= p.pos.x - HALF_WIDTH || b.x >= p.pos.x + HALF_WIDTH ||
			         b.z + 1 <= p.pos.z - HALF_WIDTH || b.z >= p.pos.z + HALF_WIDTH ||
			         b.y + 1 <= p.pos.y || b.y >= p.pos.y + BODY
			if clear || p.fly do world_set(w, before.x, before.y, before.z, place)
		}

		// A requested screenshot waits until the world has finished loading.
		backlog := world_backlog(w) + water_backlog(&w.water)
		idle_frames = idle_frames + 1 if backlog == 0 else 0
		if len(opt.digs) > 0 && idle_frames > 3 {
			for b in opt.digs {
				for x in b[0]..=b[3] do for y in b[1]..=b[4] do for z in b[2]..=b[5] do world_set(w, x, y, z, .Air)
			}
			clear(&opt.digs)
			opt.after += seconds   // the wait counts from the dig
			idle_frames = 0
		}
		if opt.shot != "" && seconds >= opt.after && (idle_frames > 3 || seconds > opt.after + 120 || opt.bench > 0) {
			shot = opt.shot
			running = false
		}
		if opt.bench > 0 && seconds > opt.bench do running = false

		// The creatures' clock runs from the day and hour; a picture is taken `after` seconds into it, so two
		// runs show the same animals, and two pictures with different `after` show them moved on.
		clock := f64(opt.day)*86400 + f64(hour)*3600 + (opt.after if opt.shot != "" && opt.bench == 0 else seconds)
		view := View {
			eye = eye, yaw = p.yaw, pitch = p.pitch, hour = hour, day = opt.day, weather = opt.weather, seconds = f32(seconds),
			target = hit, has_target = aiming, crosshair = shot == "", boxes = creatures_pose(eye, clock, f32(dt), hour, opt.day, &w.water),
		}
		render(&g, w, view, shot)
		append(&work, f32(f64(sdl.GetPerformanceCounter() - now)/frequency - g.waited))
		append(&drawn, [4]int{g.quads_drawn, g.plants_drawn, g.boxes_drawn, g.water_drawn})

		if seconds - title_at > 0.5 {
			recent := intervals[title_from:]
			island := island_near(p.pos.x, p.pos.z)
			bound(island)
			near, far := place_near(p.pos.x - f64(region.origin.x), p.pos.z - f64(region.origin.y))
			sdl.SetWindowTitle(window, fmt.ctprintf(
				"OdinCraft   %.0f fps   worst %.1f ms   %d k quads   %d loading   %.0f %.0f %.0f   island %d   %s   %02d:%02d   %s%s",
				f64(len(recent))/(seconds - title_at), slice.max(recent)*1000, g.quads_drawn/1000, backlog,
				p.pos.x, p.pos.y, p.pos.z, island.island.id, "" if near < 0 else fmt.tprintf("at %s", places[near].name) if far < GATHER else fmt.tprintf("%s %.1f km", places[near].name, far/1000),
				int(hour), int(hour*60)%60, "flying" if p.fly else "walking",
				"" if captured else "   (click to look around)",
			))
			title_at, title_from = seconds, len(intervals)
		}
		free_all(context.temp_allocator)
	}

	if opt.bench == 0 && opt.shot == "" && len(intervals) > 1 {
		// What the session was like to play, from the first frame after entering.
		total, late, worst := f32(0), 0, f32(0)
		for s in intervals[1:] {
			total += s
			late += int(s > 0.0125)
			worst = max(worst, s)
		}
		fmt.printfln("played %.0f s: average %.1f fps, %d frames over 12.5 ms, the worst %.1f ms", total, f32(len(intervals) - 1)/total, late, worst*1000)
	}
	if opt.bench > 0 {
		// Skip the first two seconds, while the world around the start is still loading.
		skip, t := 0, f32(0)
		for skip < len(intervals) && t < 2 {
			t += intervals[skip]
			skip += 1
		}
		report :: proc(name: string, samples: []f32) {
			if len(samples) == 0 do return
			slice.sort(samples)
			n := len(samples)
			late := 0
			for s in samples do if s > 0.0125 do late += 1   // more than one and a half refreshes at 120 Hz
			fmt.printfln("%s  frames %d  median %.2f ms  99%% %.2f ms  worst %.2f ms  over 12.5 ms: %d", name, n, samples[n/2]*1000, samples[n*99/100]*1000, samples[n - 1]*1000, late)
		}
		total := f32(0)
		for s in intervals[skip:] do total += s
		if total > 0 do fmt.printfln("average %.1f fps", f32(len(intervals) - skip)/total)
		report("frame interval", intervals[skip:])
		report("our work      ", work[skip:])
		if skip < len(drawn) {
			mid := skip + (len(drawn) - skip)/2
			slice.sort_by(drawn[skip:], proc(a, b: [4]int) -> bool { return a.x < b.x })
			faces := drawn[mid].x
			slice.sort_by(drawn[skip:], proc(a, b: [4]int) -> bool { return a.z < b.z })
			boxes, most := drawn[mid].z, drawn[len(drawn) - 1].z
			slice.sort_by(drawn[skip:], proc(a, b: [4]int) -> bool { return a.w < b.w })
			water := drawn[mid].w
			slice.sort_by(drawn[skip:], proc(a, b: [4]int) -> bool { return a.y < b.y })
			fmt.printfln("drawn a frame (median): %d k faces, %d k ground plants, %d k quads of water, %d creatures' boxes (at most %d)", faces/1000, drawn[mid].y/1000, water/1000, boxes, most)
		}
		fmt.printfln("travelled %.0f m to %.1f %.1f %.1f, ground %.1f", math.hypot(p.pos.x - start.x, p.pos.z - start.z), p.pos.x, p.pos.y, p.pos.z, height_in_world(p.pos.x, p.pos.z, 1))
	}
	if opt.has_probe {
		for z in opt.probe[1]..=opt.probe[3] {
			for x in opt.probe[0]..=opt.probe[2] {
				i := water_cell(x, z)
				fmt.printfln("%d %d: ground %.0f  water %.2f deep%s", x, z, w.water.floor[i], w.water.depth[i], "  supplied" if w.water.hold[i] > w.water.floor[i] else "")
			}
		}
	}
	world_destroy(w)
}
