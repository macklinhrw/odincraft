package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
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
//   shot=file.png   wait for the world to load, save one frame and exit
//   map=file.png    save a map of the land and exit
//   bench=seconds   travel straight ahead and report frame times: flying at `speed` m/s
//                   with fly, otherwise running on the ground

Options :: struct {
	pos:           [3]f64,
	has_pos:       bool,
	has_look:      bool,
	yaw, pitch:    f32,
	hour:          f32,
	fly:           bool,
	width, height: i32,
	shot:          string,
	map_path:      string,
	bench, speed:  f64,
}

options :: proc() -> Options {
	o := Options{hour = 9.5, width = 1280, height = 720, speed = 60}
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
		case "above": ok = numbers(value, ",", v[:]); o.pos, o.has_pos = {v.x, f64(height_at(v.x, v.z, 1)) + v.y, v.z}, true
		case "look":  ok = numbers(value, ",", v[:2]); o.yaw, o.pitch, o.has_look = f32(v.x), f32(v.y), true
		case "size":  ok = numbers(value, "x", v[:2]); o.width, o.height = i32(v.x), i32(v.y)
		case "hour":  ok = numbers(value, ",", v[:1]); o.hour = f32(v.x)
		case "bench": ok = numbers(value, ",", v[:1]); o.bench = v.x
		case "speed": ok = numbers(value, ",", v[:1]); o.speed = v.x
		case "shot":  o.shot = value
		case "map":   o.map_path = value
		case "fly":   o.fly = true
		case:         ok = false
		}
		if !ok {
			fmt.eprintln("bad option:", arg)
			os.exit(2)
		}
	}
	return o
}

// Start on the bank of the largest river, above the reach the sea floods, facing downstream.
find_start :: proc() -> (pos: [3]f64, yaw: f32) {
	slice.sort_by(rivers.spots[:], proc(a, b: Spot) -> bool { return a.area > b.area })
	trees: [dynamic]Tree
	defer delete(trees)
	for s in rivers.spots {
		if s.p.y < 12 do continue
		clear(&trees)
		trees_in(i32(s.p.x) - 6, i32(s.p.z) - 6, i32(s.p.x) + 6, i32(s.p.z) + 6, &trees)
		if len(trees) > 0 do continue
		x, z := math.floor(f64(s.p.x)) + 0.5, math.floor(f64(s.p.z)) + 0.5
		return {x, math.round(f64(height_at(x, z, 1))) + 0.1, z}, s.yaw
	}
	return {0.5, math.round(f64(height_at(0.5, 0.5, 1))) + 0.1, 0.5}, 0
}

main :: proc() {
	gen_init()
	opt := options()
	if opt.map_path != "" {
		land_map(opt.map_path)
		return
	}
	if !sdl.Init({.VIDEO}) do fatal("SDL")
	window := sdl.CreateWindow("OdinCraft", opt.width, opt.height, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil do fatal("window")
	g: Gpu
	gpu_init(&g, window)
	w := new(World)
	world_init(w)

	p := Player{eye = EYE, fly = opt.fly, yaw = math.to_radians(opt.yaw), pitch = math.to_radians(opt.pitch)}
	p.pos = opt.pos
	if !opt.has_pos {
		yaw: f32
		p.pos, yaw = find_start()
		if !opt.has_look do p.yaw = yaw
	}
	hour := opt.hour
	place := Mat.Stone
	captured := false

	frequency := f64(sdl.GetPerformanceFrequency())
	last := sdl.GetPerformanceCounter()
	seconds, title_at := 0.0, 0.0
	start := p.pos
	intervals: [dynamic]f32   // seconds between frames
	work: [dynamic]f32        // seconds of our own work per frame: everything but the wait for the display
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
		backlog := world_backlog(w)
		idle_frames = idle_frames + 1 if backlog == 0 else 0
		if opt.shot != "" && (idle_frames > 3 || seconds > 120) {
			shot = opt.shot
			running = false
		}
		if opt.bench > 0 && seconds > opt.bench do running = false

		view := View {
			eye = eye, yaw = p.yaw, pitch = p.pitch, hour = hour, seconds = f32(seconds),
			target = hit, has_target = aiming, crosshair = shot == "",
		}
		render(&g, w, view, shot)
		append(&work, f32(f64(sdl.GetPerformanceCounter() - now)/frequency - g.waited))

		if seconds - title_at > 0.5 {
			recent := intervals[title_from:]
			sdl.SetWindowTitle(window, fmt.ctprintf(
				"OdinCraft   %.0f fps   worst %.1f ms   %d k quads   %d loading   %.0f %.0f %.0f   %02d:%02d   %s%s",
				f64(len(recent))/(seconds - title_at), slice.max(recent)*1000, g.quads_drawn/1000, backlog,
				p.pos.x, p.pos.y, p.pos.z, int(hour), int(hour*60)%60, "flying" if p.fly else "walking",
				"" if captured else "   (click to look around)",
			))
			title_at, title_from = seconds, len(intervals)
		}
		free_all(context.temp_allocator)
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
		report("frame interval", intervals[skip:])
		report("our work      ", work[skip:])
		fmt.printfln("travelled %.0f m to %.1f %.1f %.1f, ground %.1f", math.hypot(p.pos.x - start.x, p.pos.z - start.z), p.pos.x, p.pos.y, p.pos.z, height_at(p.pos.x, p.pos.z, 1))
	}
	world_destroy(w)
}
