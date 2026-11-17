package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sys/posix"
import "core:time"
import sdl "vendor:sdl3"

// The game: start-up, the frame loop and its input, and the bench report. Command-line options are
// in options.odin; the offline tools they start live beside what they inspect.
//
// The way through. With no option that names where to go, `main` opens the front door (door.odin),
// which makes the world while it is looked at (making.odin) and goes into play from there. With one,
// it makes the world itself, as it always did, and goes straight into play. Play is `game`: it is
// left by its menu for the world's screen or the front door, and may be entered again.
//
// The game begins in the view from above, whose own controls are in above.odin. Tab goes down to
// first person at the place under the view's middle, and back up from where the player stands.
// The interface is laid over both (play.odin): every event goes to it first, and the keys that do
// what a button does are its rows (BINDS), so each is written on its button.
//
// Controls in either view
//   Tab              walk / the view from above   Esc      close the topmost thing; then the menu
//   P                pause the world              Y        why: take what is under the pointer, or
//   [ ]              turn the clock back / forward         aimed at, in the hand, which says what it is
//   \                save a screenshot            F1, F4   the lists of dwarves and of places
//   in the menu: W leaves to the world's screen, D to the front door, Q quits
//   Enter            go to what is in the hand, or follow a dwarf   K   keep the dwarf in the hand in view at the top
//   G                send the dwarves to the block under the pointer, or aimed at (hold.odin)
//   from above: right click sends them there too; a click on a dwarf takes it in the hand, a drag over several
//   takes them all, and Shift adds to the hand (crowd.odin)
//   in first person: E takes the dwarf aimed at in the hand
//
// Controls in first person
//   click            capture the mouse
//   W A S D          move                     Shift    run, or fly fast
//   Space            jump, or rise            Ctrl     sink (flying)
//   F                walk / fly               1-6      choose the block to place
//   left / right     break / place

// Start on the bank of the largest river, above the reach the sea floods, facing downstream,
// with no tree within 6 m and no small one within 3, on gentle ground with nothing in the three
// strides ahead to fill the first view if any bank has that; where every bank is wooded closer,
// with none within 3 m and no small one within 1.5. On an island with no river, where the rain
// sinks into the rock, the same on ground 12 to 30 m over the sea, the nearest the shore first,
// facing down toward it. Found relative to the region's middle, returned in the world.
find_start :: proc() -> (pos: [3]f64, yaw: f32) {
	ox, oz := f64(region.origin.x), f64(region.origin.y)
	spots := rivers.spots
	if len(spots) == 0 {
		spots = make([dynamic]Spot, context.temp_allocator)
		g := land.grid
		for ci in g.order do if c := int(ci); c%g.n%2 == 0 && c/g.n%2 == 0 && g.z[c] >= 12 && g.z[c] <= 30 {
			at := middle_of(g, c)
			append(&spots, Spot{{f32(at.x), g.z[c], f32(at.y)}, math.to_radians(land.facing[c]), -land.inland[c]})
		}
	}
	slice.sort_by(spots[:], proc(a, b: Spot) -> bool { return a.area > b.area })
	trees: [dynamic]Tree
	defer delete(trees)
	for clear_of in ([2]f32{6, 3}) do for steep in ([2]f32{0.2, 1e9}) do for s in spots {
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
	mass_reach = opt.reach*1000
	if door_first(&opt) {   // nothing names where to go: the front door, which makes the world while it is looked at (door.odin)
		door_run(&opt, nil, nil, .Door)
		return
	}
	seed = world_seed   // the islands are made from the world's seed
	// A record is drawn first at the start's place, for the swell and any kind asked for, unsaid; the
	// islands near it, the start among them, and the land they lie off are read from the world's
	// history round it (known.odin, archipelago.odin).
	@(static) first: Formed   // static: the bound names keep pointing at it
	first.island, first.region.origin = {origin = opt.origin, size = REFERENCE, seed = world_seed}, opt.origin
	bind(&first)
	quiet = true
	ok := region_init(opt.kind if opt.island == 0 else "")
	quiet = false
	if !ok {
		fmt.eprint("no kind of island named", opt.kind, "; there are:")
		for k in KINDS do fmt.eprint("", k.name)
		fmt.eprintln()
		os.exit(2)
	}
	known_make()
	forced := -1   // --kind= for the start
	if opt.kind != "" && opt.island == 0 do for k, i in KINDS do if k.name == region.kind do forced = i
	archipelago_make(opt.archipelago != "", forced)
	if opt.has_plates_why {
		at := known_point(opt.plates_why.x, opt.plates_why.y)*1000
		plates_why(f64(at.x), f64(at.y))
		return
	}
	if opt.known != "" {
		known_map(opt.known)
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
	arrivals_make()
	names_make()
	if opt.origin == {} && opt.kind == "" do world_note()   // what is known of it, kept for the list of worlds (making.odin)
	// The land larger than a region (continents.odin): each land mass's coarse stage before the islands'
	// records are made into regions, since its pieces are regions beside theirs. One that is kept is
	// read back; one that is not is formed if it lies within what is drawn from the start, a site or the
	// view asked for, or if the whole world's is asked for (--continent=1). The tools that act on one
	// island and exit leave them records.
	offline := opt.survey || opt.map_path != "" || opt.has_why || opt.archipelago != "" || hold_alone(&opt)
	lands_make()
	first_at := archipelago[opt.island].origin
	around := [2]f64{opt.site.x, opt.site.y} if opt.has_site else [2]f64{f64(first_at.x), f64(first_at.y)}
	if !offline {
		views := make([dynamic][2]f64, context.temp_allocator)
		append(&views, around)
		if opt.has_pos do append(&views, opt.pos.xz)
		if opt.has_over do append(&views, opt.over)
		lands_pass(views[:], opt.continent == 1, opt.continent == 0)
	}
	pieces := regions_make()
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
	if !opt.survey && opt.map_path == "" && !opt.has_why && !hold_alone(&opt) do for _, i in formed[:len(archipelago)] do if &formed[i] != home do append(&others, i)
	slice.sort_by(others[:], proc(a, b: int) -> bool { return apart(a) < apart(b) })
	soon := 0
	for soon < len(others) && apart(others[soon]) <= opt.near*1000 do soon += 1
	forming_begin(others[:soon], max(os.get_processor_core_count() - 1, 1), .Normal, false)
	gen_init(home)
	bind(home)   // the frame thread reads the start island unless it binds another
	hold_make(&hold, home, opt.orders, opt.party)   // the dwarves and their landing
	hold_run(&hold, opt.dwarves)
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
	if hold_alone(&opt) {
		hold_report(&hold)
		return
	}
	forming_wait(others[:soon])
	// The land masses' pieces within `near` km of the start, or of the site asked for, formed before
	// entering, each after the pieces it waits on; from then on those within reach of the view, on a
	// thread of low priority (masses_keep).
	if pieces > 0 {
		started := time.now()
		before := masses_form(around, min(opt.near*1000, NEAR_REACH))
		fmt.printfln("land larger than a region: %d pieces within %.0f km of %s formed before entering, in %.1f s", before, min(opt.near, NEAR_REACH/1000), "the site" if opt.has_site else "the start", time.duration_seconds(time.since(started)))
	}
	if opt.seam > 0 {
		mass_seam(around, opt.seam*1000)
		if opt.landmap == "" do return
	}
	if opt.landmap != "" {
		if len(lands) == 0 || !lands[0].ready do fmt.eprintln("no land larger than a region is at hand to map")
		else if opt.has_site do mass_map(opt.landmap, around, (opt.mapspan if opt.mapspan > 0 else 64)*1000, opt.cuts)
		else {
			m := &lands[0]
			for &l in lands do if l.ready && l.area > m.area do m = &l
			mass_map(opt.landmap, {f64(m.origin.x), f64(m.origin.y)}, opt.mapspan*1000 if opt.mapspan > 0 else m.side, opt.cuts)
		}
		return
	}
	if opt.has_site && !opt.has_pos {
		opt.pos, opt.has_pos, opt.above, opt.fly = {opt.site.x, 60 + max(-f64(height_in_world(opt.site.x, opt.site.y, 1)), 0), opt.site.y}, true, true, true   // over the sea where the site is at sea
		if !opt.has_look do opt.yaw, opt.pitch, opt.has_look = 0, -20, true
	}
	if opt.above && opt.place == 0 do opt.pos.y += f64(height_in_world(opt.pos.x, opt.pos.z, 1))
	sky_choose(&opt)
	window, unseen := window_open(&opt)
	g: Gpu
	gpu_init(&g, window)
	g.unseen = unseen
	world_adopt(opt.island, opt.near)
	leave := game(&opt, &g, window, unseen, others[soon:])
	if leave != .Quit do door_run(&opt, &g, window, leave)   // out of play to the world's screen or the front door, with this world in hand
}

// What the sky is when the boat stands off: the first fair morning from the March equinox on
// (weather_origin), so a person looking at the land sees it in sunlight.
sky_choose :: proc(opt: ^Options) {
	cover, base, _ := sky_at(0)
	if opt.weather.x >= 0 do cover, base = opt.weather.x, opt.weather.y
	daylight: f32
	for h := f32(0.025); h < 24; h += 0.05 do daylight += 0.05 if sun_dir(h, opt.day).y > 0 else 0
	fmt.printfln("sky on day %.0f at %.1f h: the sun %.0f° high at noon, %.1f h of daylight; the spells of weather counted from %.0f days after the equinox, the first fair morning; drawn cover %.2f, cloud base %.0f m%s",
		opt.day, opt.hour, math.to_degrees(math.asin(sun_dir(12, opt.day).y)), daylight, weather_origin(), cover, base, ", forced by --weather" if opt.weather.x >= 0 else "")
}

// The window, opened once for the whole run.
window_open :: proc(opt: ^Options) -> (window: ^sdl.Window, unseen: bool) {
	// A run that only takes a picture or measures opens no window and takes no focus: it draws
	// unseen, at the size and pace it would have on a display.
	if opt.play != "" do script_read(opt.play)
	unseen = (opt.shot != "" || opt.bench > 0 || script.on) && !opt.show
	// A window is opened only for a person: one asked for by --show, or a run started from a terminal.
	// A script or an agent that forgets --shot or --bench is told so, and nothing appears on the owner's screen.
	if !unseen && !opt.show && !posix.isatty(posix.STDIN_FILENO) {
		fmt.eprintln("no terminal: this run would open the game's window. Add --shot=file or --bench=seconds to draw unseen, or --show if the owner asked to watch")
		os.exit(2)
	}
	if unseen do sdl.SetHint(sdl.HINT_MAC_BACKGROUND_APP, "1")
	if !sdl.Init({.VIDEO}) do fatal("SDL")
	window = sdl.CreateWindow("OdinCraft", opt.width, opt.height, {.RESIZABLE, .HIGH_PIXEL_DENSITY} + ({.HIDDEN} if unseen else {}))
	if window == nil do fatal("window")
	return
}

// Why play ended: the game is left for good, or for the world's screen or the front door (door.odin).
Leave :: enum u8 { Quit, World, Door }
leaving: Leave

// Play, from entering the world in hand on its start island (`home`) until the player leaves it:
// the frame loop and its input. `far` are the islands still to be formed beside it.
game :: proc(opt: ^Options, g: ^Gpu, window: ^sdl.Window, unseen: bool, far: []int) -> Leave {
	leaving = .Quit
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
	// The view from above, over the start facing downstream, unless the options ask for first person.
	afoot := opt.has_pos || opt.has_look || opt.fly || opt.first || opt.bench > 0 && !opt.has_over
	a := Above {
		at = p.pos, yaw = p.yaw, tilt = f32(math.to_radians(clamp(opt.tilt, 0, 90))), span = clamp(opt.span, SPAN_MIN, SPAN_MAX),
		cut = opt.has_cut || opt.cut_ground, level = i32(opt.cut), follow = opt.cut_ground, bare = opt.bare,
	}
	if opt.has_over do a.at, a.yaw = {opt.over.x, 0, opt.over.y}, 0
	if opt.has_turn do a.yaw = math.to_radians(opt.turn)
	clock := Clock{speed = 2 if opt.pace == 6 else 1 if opt.pace == 3 else 0, paused = opt.pace == 0}
	hold_enter(&p, &a, opt)   // the dwarves' world begins; the player and the view are put where the landing can be watched
	forming_begin(far, 3, .Low, false)
	mass_focus = (p.pos if afoot else a.at).xz
	masses_keep()   // the land masses' pieces within reach of the view, nearest first, and those left far behind let go
	turned := f32(0)   // hours the sun was turned by hand
	place := Mat.Stone
	captured := false

	frequency := f64(sdl.GetPerformanceFrequency())
	last := sdl.GetPerformanceCounter()
	seconds, title_at := 0.0, 0.0
	start := p.pos if afoot else a.at
	intervals: [dynamic]f32   // seconds between frames
	work: [dynamic]f32        // seconds of our own work per frame: everything but the wait for the display
	listing: [dynamic]f32     // and of them, seconds listing the interface's parts and making its rectangles
	drawn: [dynamic][4]int    // faces, ground plants, creatures' boxes and quads of water drawn each frame
	idle_frames, title_from := 0, 0

	running := true
	play_begin(opt, &a, &clock, w, &p, &afoot, &captured, &running, window, unseen)
	if opt.row > 0 && opt.row <= len(home.places) do place_take(home.places[opt.row - 1].c)
	for running {
		now := sdl.GetPerformanceCounter()
		dt := f64(now - last)/frequency
		last = now
		seconds += dt
		append(&intervals, f32(dt))
		dt = min(dt, 0.1)
		if script.on do dt = SCRIPT_FRAME   // a script's frame is a sixtieth of a second however long it took to draw

		pw, ph: i32   // the picture's size in pixels, and the window's in the points the pointer is told in
		points: [2]i32
		sdl.GetWindowSizeInPixels(window, &pw, &ph)
		sdl.GetWindowSize(window, &points.x, &points.y)
		aspect := f32(pw)/f32(max(ph, 1))
		play.ratio, play.aspect = f32(pw)/f32(max(points.x, 1)), aspect

		break_block, place_block := false, false
		shot := ""
		// The hand's events, and with a script playing the script's (script.odin): both go through the one loop.
		events := make([dynamic]sdl.Event, context.temp_allocator)
		polled: sdl.Event
		for sdl.PollEvent(&polled) do append(&events, polled)
		say_now, under_now := false, false
		if script.on {
			ended: bool
			shot, say_now, under_now, ended = script_frame(&events, &a, &p, &afoot, idle_frames > 3, seconds, play.ratio)
			if ended do running = false
			g.hurry = script.hurry
		}
		for &e in events {
			if play_event(&e) do continue   // the interface's: a key that is one of its rows, or the pointer on a panel
			#partial switch e.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				if e.key.repeat do continue
				#partial switch e.key.scancode {
				case .BACKSLASH:
					os.make_directory("screenshots")
					shot = fmt.tprintf("screenshots/%d.png", sdl.GetTicksNS()/1e6)
					tell(fmt.tprintf("A picture of this was saved as %s.", shot))
				case .F:
					if afoot do p.fly, p.vel = !p.fly, 0
				case ._1..=._6:
					if afoot do place = Mat(int(e.key.scancode) - int(sdl.Scancode._1) + int(Mat.Grass))
				}
			case .MOUSE_BUTTON_DOWN:
				if !afoot {
					if e.button.button == sdl.BUTTON_LEFT do mark_begin(&a)
				} else if !captured {
					captured = true
					_ = sdl.SetWindowRelativeMouseMode(window, true)
				} else {
					break_block = e.button.button == sdl.BUTTON_LEFT
					place_block = e.button.button == sdl.BUTTON_RIGHT
				}
			case .MOUSE_MOTION:
				if afoot && captured {
					p.yaw += e.motion.xrel*0.0022
					p.pitch = clamp(p.pitch - e.motion.yrel*0.0022, -1.55, 1.55)
				} else if !afoot && play.owner == .World && e.motion.state & sdl.BUTTON_RMASK != {} {   // dragged with the right button, the view turns and tilts; a drag begun on the world is the world's wherever it goes
					a.yaw -= e.motion.xrel*0.005
					a.tilt = clamp(a.tilt + e.motion.yrel*0.005, TILT_MIN, math.PI/2)
				} else if !afoot && play.owner == .World && e.motion.state & sdl.BUTTON_MMASK != {} {   // with the middle one, the ground is dragged under the pointer
					per := a.span/f64(max(points.x, 1))   // metres of ground to a point of the window, at the view's middle
					a.at.xz -= ([2]f64{f64(math.cos(a.yaw)), f64(math.sin(a.yaw))}*f64(e.motion.xrel) - [2]f64{f64(math.sin(a.yaw)), f64(-math.cos(a.yaw))}*f64(e.motion.yrel)/f64(math.sin(a.tilt)))*per
				}
			case .MOUSE_WHEEL:
				if !afoot && a.shown do a.span = clamp(a.span*math.pow(0.88, f64(e.wheel.y)), SPAN_MIN, SPAN_MAX)
			}
		}

		keys := sdl.GetKeyboardState(nil)
		down :: proc(keys: [^]bool, s: sdl.Scancode) -> f32 { return 1 if keys[int(s)] && !typing && !play.menu else 0 }   // not while a field is typed in, or the menu is open
		wish := [3]f32{down(keys, .D) - down(keys, .A), down(keys, .SPACE) - down(keys, .LCTRL), down(keys, .W) - down(keys, .S)}
		turned = math.mod(turned + (down(keys, .RIGHTBRACKET) - down(keys, .LEFTBRACKET))*f32(dt)*3 + 24, 24)   // the sun turned by hand, to look: the dwarves' day is the clock's

		// The camera: the player's eye, or the view from above, and the point the world streams round.
		eye, centre: [3]f64
		yaw, pitch, fov: f32
		if afoot {
			if opt.bench > 0 && p.fly {
				forward := look_dir(p.yaw, 0)
				p.pos += [3]f64{f64(forward.x), 0, f64(forward.z)}*opt.speed*dt
			} else if opt.bench > 0 {
				player_update(&p, w, dt, {0, 0, 1}, false, true)
			} else {
				player_update(&p, w, dt, wish, wish.y > 0, down(keys, .LSHIFT) > 0)
			}
			eye = p.pos + [3]f64{0, p.eye, 0}
			centre, yaw, pitch, fov = eye, p.yaw, p.pitch, FOV
		} else {
			if opt.bench > 0 do a.at.xz += [2]f64{f64(math.sin(a.yaw)), f64(-math.cos(a.yaw))}*opt.speed*dt
			pan := [2]f32{down(keys, .RIGHT) - down(keys, .LEFT), down(keys, .UP) - down(keys, .DOWN)}
			above_update(&a, dt, pan, down(keys, .E) - down(keys, .Q), down(keys, .PAGEUP) - down(keys, .PAGEDOWN), down(keys, .MINUS) - down(keys, .EQUALS), down(keys, .LSHIFT) > 0)
			eye, pitch, centre = above_camera(&a, aspect)
			yaw, fov = a.yaw, ABOVE_FOV
		}
		passed := clock_step(&clock, 0 if play.menu else dt)   // the world's time this frame: none while the menu is open
		mass_focus = centre.xz
		// The day and the hour (clock.odin): the dwarves' own where a hold runs, since the screen says the
		// day they live by, and else the clock's. --hour and --day hold the sun where they say, for a
		// picture of the land; the date said is the true one all the same.
		today := date_at(watch.clock if hold.found else clock.seconds)
		hour := math.mod((opt.hour if opt.has_hour else today.hour) + turned, 24)
		sun_day := opt.day if opt.has_day else today.sun
		sky, sky_place := weather_over(p.pos if afoot else a.at, watch.clock if hold.found else clock.seconds, afoot)   // the weather over the view, by the rule the dwarves feel it by (weather.odin)
		if opt.rain >= 0 do sky.rain, sky.wet, sky.snow = opt.rain, min(1.5*opt.rain, 1), false
		play.sky, play.sky_stand = sky, sky_place
		world_update(w, g.dev, centre)
		water_update(&w.water, g.dev, passed)

		// The block aimed at in first person, which can be broken and built on; from above, the block
		// under the pointer, picked through the cut, and the box of blocks marked with it.
		hit, before: [3]i32
		aiming: bool
		if afoot {
			hit, before, aiming = raycast(w, eye, look_dir(p.yaw, p.pitch))
			play.aim = {block = hit if aiming else {i32(math.floor(p.pos.x)), i32(math.floor(p.pos.y)) - 1, i32(math.floor(p.pos.z))}, ok = true, exact = true}
		} else {
			pointer := [2]f32{0.5, 0.5}   // in a run with no window, the middle, or where the options put it
			if unseen && opt.has_cursor do pointer = {f32(opt.cursor[0])/f32(pw), f32(opt.cursor[1])/f32(ph)}
			if script.on do pointer = {script.pointer.x/f32(pw), script.pointer.y/f32(ph)}
			else if !unseen {
				mx, my: f32
				_ = sdl.GetMouseState(&mx, &my)
				pointer = {mx/f32(max(points.x, 1)), my/f32(max(points.y, 1))}
			}
			above_point(&a, w, eye, pitch, aspect, pointer)
			hit, before, aiming = a.under.block, a.under.before, a.under.ok && a.shown && (!unseen || opt.has_cursor || script.on)
			if opt.cursor_box {
				one := a.under
				above_point(&a, w, eye, pitch, aspect, {f32(opt.cursor[2])/f32(pw), f32(opt.cursor[3])/f32(ph)})
				a.mark, a.marked = {one.block, a.under.block}, one.ok && a.under.ok
				a.under = one
			}
		}
		hold_frame(w, eye, look_dir(p.yaw, p.pitch) if afoot else view_ray(yaw, pitch, fov, aspect, a.pointer), nil if afoot else &a, passed, dt)
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
		backlog := world_backlog(w) + water_backlog(&w.water) + play_backlog()
		idle_frames = idle_frames + 1 if backlog == 0 else 0
		if len(opt.digs) > 0 && idle_frames > 3 {
			for b in opt.digs {
				for x in b[0]..=b[3] do for y in b[1]..=b[4] do for z in b[2]..=b[5] do world_set(w, x, y, z, .Air)
			}
			clear(&opt.digs)
			opt.after += seconds   // the wait counts from the dig
			idle_frames = 0
		}
		if opt.shot != "" && seconds >= opt.after && (idle_frames > 3 || seconds > opt.after + 120 || opt.bench > 0) && pressed_all(opt, play_act) {   // and every part --press names has been pressed
			shot = opt.shot
			running = false
			if !afoot && opt.has_cursor {   // what the pointer is on, said as the picture is taken
				under := a.under
				if !under.ok do under = pick_far(eye, view_ray(yaw, pitch, fov, aspect, a.pointer), above_level(&a))
				if !under.ok do fmt.println("nothing under the pointer")
				else if opt.why_cursor do fmt.print(why_words(w, under.block))
				else do fmt.printfln("the pointer is on the block at %d, %d, %d m over the sea: %v%s", under.block.x, under.block.z, under.block.y, block_made(w, under.block), "" if under.exact else ", the top of a column of the ground beyond the block volume")
				if lo, hi, blocks, ok := mark_box(&a); ok do fmt.printfln("marked %d, %d, %d to %d, %d, %d: %d blocks", lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, blocks)
			}
		}
		if opt.bench > 0 && seconds > opt.bench do running = false

		// The creatures' clock runs from the day and hour; a picture is taken `after` seconds into it, so two
		// runs show the same animals, and two pictures with different `after` show them moved on.
		posed := f64(sun_day)*86400 + f64(hour)*3600 + (opt.after if opt.shot != "" && opt.bench == 0 else clock.seconds)
		// From above the animals are posed round the ground under the view's middle, not round an eye
		// that may stand a kilometre off, and from the eye's height, where no fish takes fright at it.
		near := eye if afoot else [3]f64{a.at.x, eye.y, a.at.z}
		boxes := creatures_pose(near, posed, f32(passed), hour, sun_day, &w.water)
		for &b in boxes do b.centre += {f32(near.x - eye.x), 0, f32(near.z - eye.z)}
		boxes = hold_pose(boxes, eye, dt)   // the boat and the dwarves
		// The interface's parts for this frame, with the pointer where it is: nowhere while the mouse turns the head, or in a picture with no --cursor.
		at := [2]f32{-1, -1}
		if unseen && opt.has_cursor do at = {f32(opt.cursor[0]), f32(opt.cursor[1])}
		if script.on do at = script.pointer if !afoot else {-1, -1}
		else if !unseen && !(afoot && captured) {
			mx, my: f32
			_ = sdl.GetMouseState(&mx, &my)
			at = {mx, my}*play.ratio
		}
		play_posed(opt)
		if unseen && opt.tool != "" && !afoot {   // a tool in the hand, as --tool= asks, the cursor's box its mark
			for row, t in TOOL_ROWS do if strings.equal_fold(row.name, opt.tool) do bar.tool = t
			for c in DIG_CHOICES do if bar.tool == .Dig && strings.contains(opt.plan, PLANS[c.plan]) do bar.dig = c.plan
			for c in BUILD_CHOICES do if bar.tool == .Build && strings.has_prefix(opt.plan, PLANS[c.plan]) do bar.build = c.plan
			if strings.contains(opt.plan, "timber") do bar.stuff = .Timber
			bar.posed = opt.cursor_box
			if bar.posed && bar.tool != .Fell && bar.tool != .Send && bar.tool != .Gather && bar.tool != .Fish {   // as a drag lies: flat on the level it began on, and a line where the tool draws one
				a.mark[1].y = a.mark[0].y
				if tool_line() {
					if abs(a.mark[1].x - a.mark[0].x) >= abs(a.mark[1].z - a.mark[0].z) do a.mark[1].z = a.mark[0].z
					else do a.mark[1].x = a.mark[0].x
				}
				bar.press, bar.dragged = Pick{block = a.mark[0], ok = true}, true
			}
			a.marking = bar.posed && a.marked   // as while the button is down
		}
		listed := sdl.GetPerformanceCounter()
		play_frame(f32(pw), f32(ph), at, dt, hour, sun_day, today, eye, yaw, pitch, fov, boxes)
		append(&listing, f32(f64(sdl.GetPerformanceCounter() - listed)/frequency))
		script_parts()
		if shot == opt.shot && shot != "" && opt.say || say_now do play_say()
		if under_now {
			if a.under.ok do fmt.printfln("script: the pointer is on the block at %d, %d, %d: %v", a.under.block.x, a.under.block.y, a.under.block.z, block_made(w, a.under.block))
			else do fmt.println("script: nothing is under the pointer")
		}
		view := View {
			eye = eye, yaw = yaw, pitch = pitch, hour = hour, day = sun_day, sky = sky, weather = opt.weather, dry = afoot && roofed(world_blocks(w), {i32(math.floor(eye.x)), i32(math.floor(eye.y)) - 1, i32(math.floor(eye.z))}), seconds = f32(clock.seconds),
			target = hit, has_target = aiming, crosshair = shot == "", boxes = boxes,
			fov = fov, focus = eye if afoot else a.at, above = !afoot, level = NO_CUT if afoot else above_level(&a), bare = !afoot && (a.bare || bar.tool == .Gather),   // with Gather in the hand the woods are shown without their leaves: what it takes grows under them has_mark = !afoot && a.marked,
		}
		view.mark[0], view.mark[1], _, _ = mark_box(&a)
		view.boxes = marks_view(&view, boxes, eye)   // what is marked for the dwarves, and what the box being dragged would mark
		render(g, w, view, shot)
		append(&work, f32(f64(sdl.GetPerformanceCounter() - now)/frequency - g.waited))
		append(&drawn, [4]int{g.quads_drawn, g.plants_drawn, g.boxes_drawn, g.water_drawn})

		if seconds - title_at > 0.5 {
			recent := intervals[title_from:]
			at := p.pos if afoot else a.at
			island := island_near(at.x, at.z)
			bound(island)
			near, far := place_near(at.x - f64(region.origin.x), at.z - f64(region.origin.y))
			speeds := SPEEDS
			view := fmt.tprintf("%s%s", "flying" if p.fly else "walking", "" if captured else "   (click to look around)")
			if !afoot {
				view = fmt.tprintf("from above, %.0f m across%s%s", a.span, fmt.tprintf("   cut at %d%s", a.level, ", following the ground" if a.follow else "") if a.cut else "", "   no leaves" if a.bare else "")
				if aiming do view = fmt.tprintf("%s   block %d %d %d %v", view, hit.x, hit.y, hit.z, block_made(w, hit))
			}
			sdl.SetWindowTitle(window, fmt.ctprintf(
				"OdinCraft   %.0f fps   worst %.1f ms   %d k quads   %d loading   %.0f %.0f %.0f   island %d   %s   %02d:%02d   %s   %s",
				f64(len(recent))/(seconds - title_at), slice.max(recent)*1000, g.quads_drawn/1000, backlog,
				at.x, at.y, at.z, island.island.id, "" if near < 0 else fmt.tprintf("at %s", places[near].name) if far < GATHER else fmt.tprintf("%s %.1f km", places[near].name, far/1000),
				int(hour), int(hour*60)%60, "paused" if clock.paused else fmt.tprintf("x%.0f", speeds[clock.speed]), view,
			))
			title_at, title_from = seconds, len(intervals)
		}
		free_all(context.temp_allocator)
	}

	if opt.bench == 0 && opt.shot == "" && len(intervals) > 1 {
		// What the session was like to play, from the afoot frame after entering.
		total, late, worst := f32(0), 0, f32(0)
		for s in intervals[1:] {
			total += s
			late += int(s > 0.0125)
			worst = max(worst, s)
		}
		fmt.printfln("played %.0f s: average %.1f fps, %d frames over 12.5 ms, the worst %.1f ms", total, f32(len(intervals) - 1)/total, late, worst*1000)
	}
	if opt.bench > 0 {
		// Skip the afoot two seconds, while the world around the start is still loading.
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
		report("  the interface", listing[skip:])
		fmt.printfln("the interface drew %d parts as %d rectangles in the last frame; its text takes %d of the atlas's %d rows at this scale", len(screen.items), len(ui.quads), ui.filled, ATLAS)
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
		fmt.printfln("the world's clock ran %.1f s in %.1f s", clock.seconds, seconds)
		at := p.pos if afoot else a.at
		fmt.printfln("travelled %.0f m to %.1f %.1f %.1f, ground %.1f", math.hypot(at.x - start.x, at.z - start.z), at.x, at.y, at.z, height_in_world(at.x, at.z, 1))
	}
	if opt.has_probe {
		for z in opt.probe[1]..=opt.probe[3] {
			for x in opt.probe[0]..=opt.probe[2] {
				i := water_cell(x, z)
				fmt.printfln("%d %d: ground %.0f  water %.2f deep%s", x, z, w.water.floor[i], w.water.depth[i], "  supplied" if w.water.hold[i] > w.water.floor[i] else "")
			}
		}
	}
	hold_leave()
	play_keep()
	world_destroy(w)
	if leaving != .Quit do game_end(w, g)
	return leaving
}
