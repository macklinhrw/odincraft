package main

import "base:builtin"
import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import sdl "vendor:sdl3"

// Before play (docs/foundations/interface.md, section 5; step I-2): the front door, the worlds this
// machine has made, a new world, settings, and the way through from them to the world's screen
// (chart.odin) and into play (`game`, main.odin) and back.
//
// Each is a screen as the play screen is (ADR 0010): a procedure that lists parts each frame, over
// the map of the world in hand, which moves slowly behind the front door. The world is made on a
// thread of its own (making.odin), so these screens are drawn at the screen's rate while it is
// made, and say how far each stage has come.
//
//   the front door   Enter the last world, Worlds, Make a new world, Settings, Quit. The choice in
//                    focus is brass and shows its key; the arrows move the focus and Enter takes it,
//                    and so does the pointer. Enter the last world goes straight into play, as soon
//                    as its start island and those near it are formed.
//   Worlds           every world with a history kept in build/worlds/, and what was written down of
//                    it. A row opens that world's screen.
//   a new world      a seed, typed or drawn. Making it goes to its world's screen, where the land
//                    arrives as it is made.
//   settings         the interface's size, and the keys, which are the rows of BINDS: a row clicked
//                    takes the next key pressed.
//   the world        its map, an island in the hand, and the doors (chart.odin)
//   planning         an expedition to the island in the hand: where it lands and who goes (plan.odin)
//
// A run with no window draws any of them in a state the options set (options.odin), and says what
// it says; `press` works their buttons, across the way into play and out again.

Before :: enum u8 { Door, Worlds, New, Settings, Chart, Plan }
Wish :: enum u8 { None, Hold, Walk }

Door :: struct {
	opt:      ^Options,
	g:        ^Gpu,
	window:   ^sdl.Window,
	unseen:   bool,
	running:  bool,
	screen:   Before,
	focus:    int,             // the choice in focus at the front door, or the world in the list
	last:     u32,             // the seed of the world last entered, kept between runs; 0 before any
	typed:    [dynamic]u8,     // a new world's seed, as typed
	worlds:   []Kept_World,    // read when the list is opened, and when a world is made
	scroll, over: f32,         // how far a list longer than its panel is scrolled, and how far it can be
	wish:     Wish,            // play is to begin as soon as the world can be entered: with a hold, or on foot
	isle:     int,             // on this island
	planned:  bool,            // and with the expedition that was planned (plan.odin), not the game's own landing and the seed's first party
	rebind:   int,             // the row of BINDS that takes the next key pressed, or -1
	took:     [Stage]f64,      // how long each stage of making a world last took on this machine, kept between runs
	now, rest, dt: f64,        // real seconds here, those the pointer has rested, and this frame's
	pointer:  [2]f32,
	ratio:    f32,             // pixels of the picture to a point of the window
	pressing: bool,            // the left button went down on a part
	pressed:  Act,
	pressed_arg: int,
	press:    [2]f32,          // where it went down on the map
	on_map, dragged: bool,     // it went down on the map, and has moved far enough to be a drag
	posed:    bool,            // the options' state was set, once
	said:     bool,            // the picture's state was not reached, and that was said
	kept_size: f64,            // metres across the start island's square in the picture kept from the last run; 0 with none
	kept_pixels: []u8,         // that picture, held until this run's has taken its place
}
door := Door{rebind = -1}

// The front door's choices, in their order.
DOOR_CHOICES :: 5

// ---- the way through --------------------------------------------------------------------------

// Whether a run begins at the front door: one asked for, or one with no option that names where to go.
door_first :: proc(opt: ^Options) -> bool {
	if opt.has_door do return true
	straight := opt.has_over || opt.has_pos || opt.has_look || opt.fly || opt.first || opt.place != 0 || opt.bench > 0 || opt.shot != "" || opt.enter ||
		opt.island != 0 || opt.kind != "" || opt.origin != {} || opt.map_path != "" || opt.archipelago != "" || opt.known != "" || opt.has_why || opt.survey ||
		opt.has_plates_why || opt.dwarves > 0 || opt.orders != "" || opt.has_select || opt.has_cursor || opt.play != "" ||
		opt.has_site || opt.seam > 0 || opt.landmap != ""   // a site on a large land, and the tools that measure or map one and exit (continents.odin)
	return !straight
}

// The screens before play, until the player quits: from the start of a run with no window yet and
// no world, or out of play (`to`) with both.
door_run :: proc(opt: ^Options, g_in: ^Gpu, window_in: ^sdl.Window, to: Leave) {
	d := &door
	d.opt, d.running = opt, true
	g, window := g_in, window_in
	own: Gpu
	if g == nil {
		unseen: bool
		window, unseen = window_open(opt)
		gpu_init(&own, window)
		own.unseen = unseen
		g = &own
	}
	d.g, d.window, d.unseen = g, window, g.unseen
	settings_read()
	if !sync.atomic_load(&making.records) && !sync.atomic_load(&making.working) {   // no world in hand: the one asked for, or the last entered
		door_kept(g, world_seed if opt.has_seed || d.unseen || d.last == 0 else d.last)
		world_open(world_seed if opt.has_seed || d.unseen || d.last == 0 else d.last, opt.near, opt.continent)
	}
	if sync.atomic_load(&making.records) && chart.painter == nil do chart_painter_begin()   // a world start-up made itself has no pictures yet
	screen_go(.Chart if to == .World else .Door)
	switch opt.door {
	case "worlds":   screen_go(.Worlds)
	case "new":      screen_go(.New)
	case "settings": screen_go(.Settings)
	case "world":    screen_go(.Chart)
	}
	plan_first := opt.door == "plan"   // the planning screen, once the island asked for is formed (--pick, or the start)

	if script.on && script.at == 0 && len(script.steps) > 0 && script.steps[0].kind == .Loaded do script.at = 1   // a script begun here waits for no world: the first frame is its to look at
	script_step, script_waited := -1, 0.0
	frequency := f64(sdl.GetPerformanceFrequency())
	last := sdl.GetPerformanceCounter()
	began := time.now()
	seconds := 0.0
	intervals, work, listing: [dynamic]f32
	for d.running {
		now := sdl.GetPerformanceCounter()
		dt := f64(now - last)/frequency
		last = now
		seconds += dt
		append(&intervals, f32(dt))
		dt = min(dt, 0.1)
		pw, ph: i32
		points: [2]i32
		sdl.GetWindowSizeInPixels(window, &pw, &ph)
		sdl.GetWindowSize(window, &points.x, &points.y)
		d.ratio = f32(pw)/f32(max(points.x, 1))
		making_sync()   // the list of regions, made again with the mainland's pieces where the making asks
		// The hand's events, and with a script playing the script's (script.odin): both go through door_event.
		events := make([dynamic]sdl.Event, context.temp_allocator)
		polled: sdl.Event
		for sdl.PollEvent(&polled) do append(&events, polled)
		script_shot := ""
		say_now, under_now := false, false
		if script.on {
			ended: bool
			script_shot, say_now, under_now, ended = script_frame(&events, nil, nil, nil, !chart.going && (chart_painted() || !sync.atomic_load(&making.records)) || seconds > script_waited + 20, seconds, d.ratio)
			if script.at != script_step do script_step, script_waited = script.at, seconds   // a picture waits twenty seconds at the most for the world's pictures
			if ended do d.running = false
			g.hurry = false
		}
		for &e in events do door_event(&e)
		at := [2]f32{-1, -1}
		if d.unseen && opt.has_cursor do at = {f32(opt.cursor[0]), f32(opt.cursor[1])}
		if script.on do at = script.pointer
		if !d.unseen {
			mx, my: f32
			_ = sdl.GetMouseState(&mx, &my)
			at = {mx, my}*d.ratio
			if d.screen == .Chart && d.rebind < 0 {   // the arrows move the map, as they move the view over the land
				keys := sdl.GetKeyboardState(nil)
				pan := [2]f64{f64(int(keys[int(sdl.Scancode.RIGHT)]) - int(keys[int(sdl.Scancode.LEFT)])), f64(int(keys[int(sdl.Scancode.DOWN)]) - int(keys[int(sdl.Scancode.UP)]))}
				if pan != {} do chart.going = false
				chart.at += pan*chart.span*0.6*dt
			}
		}
		if plan_first && sync.atomic_load(&making.records) && is_formed(&formed[clamp(opt.pick, 0, len(archipelago) - 1) if opt.has_pick else 0]) {
			plan_first = false
			chart_take(clamp(opt.pick, 0, len(archipelago) - 1) if opt.has_pick else 0)
			screen_go(.Plan)
		}
		listed := sdl.GetPerformanceCounter()
		door_frame(f32(pw), f32(ph), at, 0 if d.unseen && opt.shot != "" else dt)
		append(&listing, f32(f64(sdl.GetPerformanceCounter() - listed)/frequency))
		script_parts()
		if say_now do play_say()
		if under_now do fmt.printfln("script: the pointer is on %s", plan_under() if d.screen == .Plan && plan_under() != "" else chart_tip(at) if d.screen == .Chart && chart_tip(at) != "" else "nothing the map names")
		shot := script_shot
		posed := (opt.shot != "" || len(opt.press) > 0) && seconds >= opt.after && door_posed(opt) && pressed_all(opt, door_act)   // the state the options ask for, and their parts pressed
		if opt.shot != "" && posed {
			shot = opt.shot
			d.running = false
			if opt.say do play_say()
		}
		if opt.bench > 0 && seconds > opt.bench do d.running = false
		door_render(g, shot)
		append(&work, f32(f64(sdl.GetPerformanceCounter() - now)/frequency - g.waited))
		if d.wish != .None && world_enterable(d.isle) {   // into play, and back here when it is left
			switch door_play() {
			case .Quit:  d.running = false
			case .World: screen_go(.Chart)
			case .Door:  screen_go(.Door)
			}
			last = sdl.GetPerformanceCounter()
		}
		free_all(context.temp_allocator)
	}
	settings_keep()
	if opt.bench > 0 {
		// What it was like while the world was made: the frames from the first on, since the making begins with them.
		report :: proc(name: string, samples: []f32) {
			if len(samples) == 0 do return
			slice.sort(samples)
			n, late := len(samples), 0
			for s in samples do if s > 0.0125 do late += 1
			fmt.printfln("%s  frames %d  median %.2f ms  99%% %.2f ms  worst %.2f ms  over 12.5 ms: %d", name, n, samples[n/2]*1000, samples[n*99/100]*1000, samples[n - 1]*1000, late)
		}
		skip := min(2, len(intervals))   // the first two frames make the text's atlas and the GPU's pipelines
		report("frame interval", intervals[skip:])
		report("our work      ", work[skip:])
		report("  the interface", listing[skip:])
		fmt.printfln("the interface drew %d parts as %d rectangles in the last frame; its text takes %d of the atlas's %d rows at this scale", len(screen.items), len(ui.quads), ui.filled, ATLAS)
		making_say(time.duration_seconds(time.since(began)))
	}
}

// So many seconds in words: seconds under two minutes, then minutes.
span_words :: proc(seconds: f64) -> string {
	if seconds < 120 do return fmt.tprintf("%.0f s", max(seconds, 1))
	return fmt.tprintf("%.0f min", math.round(seconds/60))
}

// How long each stage of making the world in hand took, as a bench says it.
making_say :: proc(ran: f64) {
	m := &making
	near_done, near_all, _ := making_progress(.Near)
	far_done, far_all, _ := making_progress(.Far)
	fmt.printfln("the world of seed %d in %.1f s: the plates' history %s; the region round the start %.2f s; the mainland %s; the islands near the start %d of %d in %.2f s%s; the far islands %d of %d",
		m.seed, ran, "kept from an earlier run" if m.kept else fmt.tprintf("%.2f s", m.took[.Plates]), m.took[.Region],
		fmt.tprintf("at hand on 64 m cells in %.1f s", m.took[.Mainland]) if sync.atomic_load_explicit(&lands_state.regions, .Acquire) else "left as the history has it", near_done, near_all, m.took[.Near],
		", and it could be entered" if world_enterable(0) else "", far_done, far_all)
	if sync.atomic_load(&m.records) && is_formed(&formed[0]) {   // the start island's land, as the forming test hashes it: the same seed gives the same figure however the world was come to
		f := &formed[0]
		fmt.printfln("the start island's land: hash %x", fnv.fnv64a(slice.to_bytes(f.land.z[0])) ~ fnv.fnv64a(slice.to_bytes(f.land.wet)) ~ fnv.fnv64a(slice.to_bytes(f.land.age)) ~ fnv.fnv64a(f.land.community))
	}
}

// Into play on the island wished for, with a hold or on foot, until the player leaves it.
door_play :: proc() -> Leave {
	d := &door
	o := d.opt^   // the run's own options, with where to go set by the door taken
	o.first, o.island = d.wish == .Walk, d.isle
	d.wish = .None
	if making.stopped do world_open(making.seed, making.near_km, making.continent)   // the far islands go on being made beside play
	home = &formed[d.isle]
	bind(home)   // the frame's thread reads the island played on
	play_again()
	hold, watch = {}, {selected = -1}
	if !o.first {
		hold_make(&hold, home, "", o.party, &planning.set if d.planned else nil)
		d.planned = false
		if !hold.found do tell("No boat can come in to any shore of this island, so no dwarves have landed. You stand on the bank of its largest river.")
	}
	sky_choose(&o)
	d.last = making.seed
	if !d.unseen do _ = sdl.StopTextInput(d.window)
	leave := game(&o, d.g, d.window, d.unseen, nil)
	d.opt.press = o.press   // the parts play pressed are not pressed again here
	clear(&d.opt.digs)
	return leave
}

// The play screen as it is at the start of a game: what a game before it left is put down, and what
// the player keeps between games stays (the interface's size, the lessons learned, the lens's texture).
play_again :: proc() {
	u := &play
	for u.lens_job != nil && !sync.atomic_load(&u.lens_job.done) do time.sleep(time.Millisecond)   // a lens being read of an island still stands on that island
	if u.lens_job != nil {
		delete(u.lens_job.pixels)
		free(u.lens_job)
	}
	card_free(&u.card)
	for m in u.said do delete(m.text)
	for w in u.wrong { delete(w.id); delete(w.text) }
	delete(u.said); delete(u.wrong); delete(u.several); delete(u.kept); delete(u.need); delete(u.needing); delete(u.find); delete(u.tip); delete(u.mourned); delete(u.lean_said)
	was := u^
	u^ = {lens = -1, lens_shown = -1, open = {0}}
	u.scale, u.learned, u.lens_tex = was.scale, was.learned, was.lens_tex
	typing = false
	delete(bar.food); delete(bar.picked)   // what the last game's tools knew of what was gathered
	bar = {dig = .Out, build = .Wall, deep = 2, high = 2, job = -1}
}

// Go to a screen.
screen_go :: proc(to: Before) {
	d := &door
	was := d.screen
	d.screen, d.scroll, d.rebind, d.wish = to, 0, -1, .None
	if to == .Worlds {
		worlds_read()
		d.focus = 0
		for w, i in d.worlds do if w.seed == making.seed do d.focus = i
	}
	if to == .Door do d.focus = 0
	if to != .Chart {   // the map's lens is the world's screen's own, and its view's journey that screen's and the planning's
		sync.atomic_store(&chart.lens, -1)
		chart.lenses = false
		if to != .Plan do chart.going = false
	}
	if to == .Plan || to == .Chart && was == .Plan do chart_go(chart.pick)   // the island whole, between the panels
	if to == .Chart && was != .Chart && chart.pick == -1 do chart.homed = false   // the islands there are to choose from, and the start in the hand
	if d.window != nil && !d.unseen {
		if to == .New do _ = sdl.StartTextInput(d.window)
		else do _ = sdl.StopTextInput(d.window)
	}
}

worlds_read :: proc() {
	d := &door
	for w in d.worlds {
		for s in w.says do delete(s)
		delete(w.says)
	}
	delete(d.worlds)
	d.worlds = worlds_kept(context.allocator)
}

// Open a world's screen: the world in hand, or another, which is then made.
world_show :: proc(seed: u32) {
	d := &door
	if seed != making.seed || !sync.atomic_load(&making.records) && !sync.atomic_load(&making.working) {
		world_gpu_drop()
		chart_forget()
		world_open(seed, d.opt.near, d.opt.continent)
	}
	screen_go(.Chart)
}

// What the frame's thread kept on the GPU of the world in hand's islands, let go before the world
// is put down: each island's rivers and falls and its field for the cloud cap (islands_upload).
world_gpu_drop :: proc() {
	g := door.g
	if g == nil || !sync.atomic_load(&making.records) do return
	for &f in formed {
		if f.ribbon != nil do sdl.ReleaseGPUBuffer(g.dev, f.ribbon)
		if f.falls != nil do sdl.ReleaseGPUBuffer(g.dev, f.falls)
		if f.lifted != nil do sdl.ReleaseGPUTexture(g.dev, f.lifted)
		f.ribbon, f.falls, f.lifted = nil, nil, nil
	}
}

// ---- the picture kept for the front door ------------------------------------------------------

// The start island's picture is kept beside its world when it is painted, so that the front door of
// the next run stands over land from its first frame, and not over an empty sea until the island is
// formed and painted again. It is the island as this game last made it: the run's own picture takes
// its place as soon as it is painted.
door_path :: proc(s: u32) -> string { return fmt.tprintf("%s/door-%d.bin", worlds_dir(), s) }

door_keep :: proc(pixels: []u8) {
	if len(archipelago) == 0 do return
	head := [2]f64{archipelago[0].size, f64(PICTURE_ISLE)}
	out := make([dynamic]u8, context.temp_allocator)
	append(&out, ..slice.to_bytes(head[:]))
	append(&out, ..pixels)
	_ = os.make_directory(worlds_dir())
	_ = os.write_entire_file(door_path(world_seed), out[:])
}

// Put the kept picture of a world's start island on the GPU, where there is one. The frame's thread,
// before the first frame.
door_kept :: proc(g: ^Gpu, s: u32) {
	d, c := &door, &chart
	data, err := os.read_entire_file(door_path(s), context.temp_allocator)
	if err != nil || len(data) != 16 + PICTURE_ISLE*PICTURE_ISLE*4 do return
	head := (^[2]f64)(raw_data(data))^
	if head[1] != PICTURE_ISLE || head[0] <= 0 do return
	picture_put(g, 0, 2, data[16:])
	d.kept_size, d.kept_pixels = head[0], slice.clone(data[16:])
	sync.guard(&c.mutex)
	c.door = true
}

// ---- what is kept between runs ----------------------------------------------------------------

// The keys as the game has them before any is changed.
BINDS_WERE := BINDS

// Read build/interface.txt: the interface's size, the world last entered, the keys changed, and how
// long a world took to make. A run with no window reads none of it, so its pictures are the same anywhere.
settings_read :: proc() {
	d := &door
	if d.unseen {
		if d.opt.scale != 0 do play.scale = d.opt.scale
		return
	}
	data, err := os.read_entire_file("build/interface.txt", context.temp_allocator)
	if err != nil do return
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		f := strings.fields(line, context.temp_allocator)
		if len(f) < 2 do continue
		switch f[0] {
		case "learned":
			for l in Lesson do if f[1] == fmt.tprint(l) do play.learned += {l}
		case "scale":
			if m, ok := strconv.parse_int(f[1]); ok && m >= 3 && m <= 8 && d.opt.scale == 0 do play.scale = m
		case "world":
			if s, ok := strconv.parse_uint(f[1], 10); ok do d.last = u32(s)
		case "took":
			for s in Stage do if len(f) == 3 && f[1] == fmt.tprint(s) do d.took[s], _ = strconv.parse_f64(f[2])
		case "key":   // a row of BINDS, the key it had and the key it has: a row that has since changed is left as it is
			if len(f) != 4 do continue
			i, a := strconv.parse_int(f[1])
			was, b := strconv.parse_int(f[2])
			now, c := strconv.parse_int(f[3])
			if a && b && c && i >= 0 && i < len(BINDS) && int(BINDS_WERE[i].key) == was do key_set(i, sdl.Scancode(now))
		}
	}
	if d.opt.scale != 0 do play.scale = d.opt.scale
}

// The lines this file keeps there, beside the play screen's own (play_keep).
settings_lines :: proc(b: ^strings.Builder) {
	d := &door
	if d.last != 0 do fmt.sbprintfln(b, "world %d", d.last)
	for s in Stage do if d.took[s] > 0 do fmt.sbprintfln(b, "took %v %.2f", s, d.took[s])
	for row, i in BINDS do if row.key != BINDS_WERE[i].key do fmt.sbprintfln(b, "key %d %d %d", i, int(BINDS_WERE[i].key), int(row.key))
}

settings_keep :: proc() {
	d := &door
	if d.unseen do return
	m := &making
	if !m.kept && m.took[.Plates] > 0 do d.took[.Plates], d.took[.Region] = m.took[.Plates], m.took[.Region]
	if m.took[.Near] > 0 do d.took[.Near] = m.took[.Near]
	play_keep()
}

// ---- keys -------------------------------------------------------------------------------------

// The key written on the button of an act before play: a row of BINDS for the screen that is up.
door_key :: proc(act: Act, arg := 0) -> string {
	views := door_views()
	for b in BINDS do if b.act == act && b.arg == arg && b.views == views do return b.name
	return ""
}

// The rows of BINDS the screen that is up reads.
door_views :: proc() -> Views { return .Chart if door.screen == .Chart else .Plan if door.screen == .Plan else .Door }

// Give a row of BINDS another key, with the name a button shows for it.
key_set :: proc(row: int, key: sdl.Scancode) {
	b := &BINDS[row]
	b.key = key
	if key == BINDS_WERE[row].key {
		b.name = BINDS_WERE[row].name
		return
	}
	name := string(sdl.GetScancodeName(key))
	switch name {
	case "Return":    name = "Enter"
	case "Escape":    name = "Esc"
	case "Backspace": name = "Bksp"
	case "":          name = fmt.tprintf("Key %d", int(key))
	}
	b.name = strings.clone(name)
}

// What a key does, in words: each act a row of BINDS can name, with what it is done with.
Key_Said :: struct { act: Act, arg: int, says: string }
KEYS_SAID := [?]Key_Said{
	{.Escape, 0, "Close the topmost thing, then open the menu"}, {.Pause, 0, "Stop the world, or let it go on"},
	{.Speed, 0, "The world at its own pace"}, {.Speed, 1, "Three times as fast"}, {.Speed, 2, "Six times as fast"},
	{.Cut_Move, 1, "Raise the cut (with Shift, by eight)"}, {.Cut_Move, -1, "Lower the cut (with Shift, by eight)"},
	{.Cut, 0, "Cut the world open, or show it whole"}, {.Follow, 0, "Hold the cut over the ground"},
	{.Bare, 0, "Leaves off, or on"}, {.Lenses, 0, "The lenses"}, {.Walk, 0, "Walk here, or back up to the view from above"},
	{.Why, 0, "Take what is under the pointer in the hand"}, {.Go, 0, "Go to what is in the hand, or follow a dwarf"},
	{.Keep, -1, "Keep the dwarf in the hand in view"},
	{.List, int(List.Dwarves), "The list of dwarves"}, {.List, int(List.Places), "The list of places"},
	{.Order, int(Tool.Dig), "The tool to dig"}, {.Order, int(Tool.Fell), "The tool to fell"}, {.Order, int(Tool.Build), "The tool to build"},
	{.Order, int(Tool.Send), "Send the party"}, {.Order, int(Tool.Remove), "Take marks back, built blocks down, or a stockpile away"},
	{.Order, int(Tool.Store), "The tool to mark a stockpile"}, {.Order, int(Tool.Sleep), "The tool to mark a place to sleep"}, {.Order, int(Tool.Gather), "The tool to gather food from plants and trees"}, {.Order, int(Tool.Fish), "The tool to fish"}, {.More, 0, "The card of what is in the hand, or shut it"},
	{.Back, 0, "Back to the game"}, {.Leave, int(Leave.World), "Leave to the world"}, {.Leave, int(Leave.Door), "Leave to the front door"}, {.Quit, 0, "Quit the game"},
	{.Door_Move, -1, "The choice above"}, {.Door_Move, 1, "The choice below"}, {.Door_Go, 0, "Take the choice in focus"},
	{.Door_Back, 0, "Back: put down, then to the front door"}, {.Draw, 0, "Draw a seed"}, {.Stop, 0, "Stop making the world, or go on"},
	{.Found, 0, "Plan an expedition to the island in the hand"}, {.Roam, 0, "Walk the island in the hand"},
	{.Chart_Home, 0, "The map over all the islands"}, {.Chart_Zoom, 1, "The map nearer"}, {.Chart_Zoom, -1, "The map further"}, {.Chart_Lenses, 0, "The map's lenses"},
	{.Set_Out, 0, "Set out"}, {.Site, 0, "Land at the first landing offered"}, {.Site, 1, "Land at the second"}, {.Site, 2, "Land at the third"}, {.Site, 3, "Land at the fourth"},
	{.Party_Move, -1, "The dwarf above"}, {.Party_Move, 1, "The dwarf below"}, {.Draw_Dwarf, -1, "Draw the dwarf in focus again"}, {.Draw_Party, 0, "Draw the whole party again"},
}
VIEWS_SAID := [Views]string{.Above = "From above", .Afoot = "On foot", .Either = "From above and on foot", .Menu = "In the menu", .Door = "At the front door", .Chart = "On the world's map", .Plan = "Planning an expedition"}

key_says :: proc(b: Bind) -> string {
	for row in KEYS_SAID do if row.act == b.act && row.arg == b.arg do return row.says
	return fmt.tprint(b.act)
}

// Whether two rows are read in the same view, so that one key on both means the first alone is obeyed.
views_meet :: proc(a, b: Views) -> bool {
	return a == b || a == .Either && (b == .Above || b == .Afoot) || b == .Either && (a == .Above || a == .Afoot)
}

// ---- acts and events --------------------------------------------------------------------------

door_act :: proc(act: Act, arg: int) {
	d, c := &door, &chart
	#partial switch act {
	case .Door_Move:
		n := DOOR_CHOICES if d.screen == .Door else len(d.worlds) if d.screen == .Worlds else 0
		if n > 0 do d.focus = (d.focus + arg + n)%n
	case .Door_Pick:
		d.focus = arg
		door_act(.Door_Go, 0)
	case .Door_Go:
		switch d.screen {
		case .Door:
			switch d.focus {
			case 0: d.wish, d.isle, d.planned = .Hold, 0, false   // into play at the start, as soon as it can be entered
			case 1: screen_go(.Worlds)
			case 2: screen_go(.New)
			case 3: screen_go(.Settings)
			case 4: d.running = false
			}
		case .Worlds:
			if d.focus < len(d.worlds) do world_show(d.worlds[d.focus].seed)
		case .New:
			if s, ok := strconv.parse_uint(string(d.typed[:]), 10); ok && s > 0 && s <= uint(max(u32)) do world_show(u32(s))
		case .Settings, .Chart, .Plan:
		}
	case .Door_Back:
		switch {
		case d.rebind >= 0: d.rebind = -1
		case d.wish != .None: d.wish = .None
		case d.screen == .Plan: screen_go(.Chart)   // back to the world's map, the island still in the hand and what was planned kept
		case d.screen == .Chart && c.lenses && c.lens < 0: c.lenses = false
		case d.screen == .Chart && c.pick != -1:   // the island is put down, and the view goes back to all of them
			chart_take(-1)
			chart_go(-1)
		case d.screen != .Door: screen_go(.Door)
		}
	case .Draw:
		if d.screen != .New do return
		clear(&d.typed)
		append(&d.typed, fmt.tprint(1 + hash(i32(time.now()._nsec >> 10), i32(len(d.worlds)), 77)%999_999))
	case .Stop:
		if making.stopped do world_open(making.seed, making.near_km, making.continent)
		else if sync.atomic_load(&making.working) || !world_whole() do making_stop()
	case .Rebind: d.rebind = arg
	case .Keys_Back:
		for _, i in BINDS do key_set(i, BINDS_WERE[i].key)
		settings_keep()
	case .Scale:
		play.scale = arg
		settings_keep()
	case .Quit: d.running = false
	case .Chart_Lens: sync.atomic_store(&c.lens, -1 if c.lens == arg else arg)
	case .Chart_Lenses:
		c.lenses = !(c.lenses || c.lens >= 0)
		if !c.lenses do sync.atomic_store(&c.lens, -1)
	case .Isle_Depth: c.depth, c.scroll, c.row = Isle_Depth(arg), 0, -1
	case .Isle_Row: c.row = -1 if c.row == arg else arg
	case .Isle_Take: chart_take(arg, true)
	case .Chart_Zoom: chart_zoom(math.pow(0.9, f64(arg)), {c.free.x + c.free.w/2, c.free.y + c.free.h/2})
	case .Chart_Home: chart_go(c.pick if d.screen == .Plan else -1)
	case .Mass_Leave: sync.atomic_store(&lands_state.leave, true)
	case .Found:   // an expedition to the island in the hand is planned, once its land is formed
		if d.screen == .Chart && c.pick >= 0 && is_formed(&formed[c.pick]) do screen_go(.Plan)
	case .Roam:
		if d.screen == .Chart && c.pick >= 0 && world_enterable(c.pick) do d.wish, d.isle, d.planned = .Walk, c.pick, false
	case .Set_Out:
		if d.screen == .Plan && c.pick >= 0 && world_enterable(c.pick) && len(planning.offered) > 0 do d.wish, d.isle, d.planned = .Hold, c.pick, true
	case .Site, .Site_Row, .Party_Who, .Party_Move, .Draw_Dwarf, .Draw_Party:
		if d.screen == .Plan do plan_act(act, arg)
	}
}

door_event :: proc(e: ^sdl.Event) {
	d, c := &door, &chart
	#partial switch e.type {
	case .QUIT:
		d.running = false
	case .KEY_DOWN:
		if d.rebind >= 0 {   // the next key pressed is that row's; Escape leaves it as it is
			if e.key.scancode != .ESCAPE && !e.key.repeat {
				key_set(d.rebind, e.key.scancode)
				settings_keep()
			}
			d.rebind = -1
			return
		}
		if d.screen == .New && e.key.scancode == .BACKSPACE {
			builtin.resize(&d.typed, len(without_last(string(d.typed[:]))))
			return
		}
		views := door_views()
		for b in BINDS do if b.key == e.key.scancode && b.views == views {
			if !e.key.repeat || b.held do door_act(b.act, b.shifted if e.key.mod & sdl.KMOD_SHIFT != {} else b.arg)
			return
		}
	case .TEXT_INPUT:
		if d.screen == .New do for r in string(e.text.text) do if r >= '0' && r <= '9' && len(d.typed) < 9 do append(&d.typed, u8(r))
	case .MOUSE_MOTION:
		at := [2]f32{e.motion.x, e.motion.y}*d.ratio
		if d.on_map && e.motion.state & sdl.BUTTON_LMASK != {} {   // the map is dragged under the pointer
			if abs(at.x - d.press.x) + abs(at.y - d.press.y) > 6*d.ratio do d.dragged = true
			if d.dragged {
				c.going = false
				c.at -= [2]f64{f64(e.motion.xrel), f64(e.motion.yrel)}*f64(d.ratio)*c.span/f64(max(c.wide, 1))
			}
			return
		}
		if hot, _, _ := screen_over(&screen, at); hot >= 0 && screen.items[hot].act == .Door_Pick do d.focus = screen.items[hot].arg   // the pointer moves the focus as the arrows do
	case .MOUSE_BUTTON_DOWN:
		if e.button.button != sdl.BUTTON_LEFT do return
		at := [2]f32{e.button.x, e.button.y}*d.ratio
		hot, solid, _ := screen_over(&screen, at)
		d.pressing, d.on_map, d.dragged = false, false, false
		if hot >= 0 {
			d.pressing, d.pressed, d.pressed_arg = true, screen.items[hot].act, screen.items[hot].arg
		} else if !solid && (d.screen == .Chart || d.screen == .Plan) do d.on_map, d.press = true, at
	case .MOUSE_BUTTON_UP:
		if e.button.button != sdl.BUTTON_LEFT do return
		at := [2]f32{e.button.x, e.button.y}*d.ratio
		if d.pressing {
			if hot, _, _ := screen_over(&screen, at); hot >= 0 && screen.items[hot].act == d.pressed && screen.items[hot].arg == d.pressed_arg do door_act(d.pressed, d.pressed_arg)
		} else if d.on_map && !d.dragged && d.screen == .Plan {   // a click on the island chooses the shore under it
			plan_click()
		} else if d.on_map && !d.dragged && sync.atomic_load(&making.records) {   // a click on the map takes what is under it in the hand
			chart_take(chart_under(chart_from(at)), true)
		}
		d.pressing, d.on_map, d.dragged = false, false, false
	case .MOUSE_WHEEL:
		_, solid, on := screen_over(&screen, d.pointer)
		if (d.screen == .Chart || d.screen == .Plan) && !solid do chart_zoom(math.pow(0.88, f64(e.wheel.y)), d.pointer)
		else if d.screen == .Plan && on >= 0 && screen.items[on].area == .Hand do planning.scroll -= e.wheel.y*px(8)
		else if d.screen == .Plan && on >= 0 && screen.items[on].area == .List do planning.who_scroll -= e.wheel.y*px(13)
		else if d.screen == .Chart && on >= 0 && screen.items[on].area == .Hand do c.scroll -= e.wheel.y*px(8)
		else if d.screen == .Chart && on >= 0 && screen.items[on].area == .List do c.list_scroll -= e.wheel.y*px(13)
		else if d.screen == .Settings || d.screen == .Worlds do d.scroll -= e.wheel.y*px(14)
	}
}

// ---- the frame --------------------------------------------------------------------------------

// List the parts of the screen that is up, and say which the pointer is on.
door_frame :: proc(wide, high: f32, pointer: [2]f32, dt: f64) {
	d, s := &door, &screen
	clear(&s.items)
	clear(&ui.quads)
	s.w, s.h, s.hot = wide, high, -1
	d.now += dt
	d.dt = dt
	d.rest = d.rest + dt if pointer == d.pointer else 0
	d.pointer = pointer
	ui_bake(play.scale if play.scale != 0 else scale_for(high))
	play.clip, play.menu = {}, false
	if d.screen == .Plan do plan_build()
	else if d.screen == .Chart do chart_build()
	else do front_build()
	s.hot, _, _ = screen_over(s, pointer)
	if d.on_map do s.hot = -1
	if d.pressing && (s.hot < 0 || s.items[s.hot].act != d.pressed || s.items[s.hot].arg != d.pressed_arg) do s.hot = -1
	// A few words beside the part the pointer rests on, or of what lies under it on the map.
	text := ""
	_, solid, on := screen_over(s, pointer)
	if s.hot >= 0 && (d.rest > 0.45 || d.unseen) do text = s.items[s.hot].tip
	else if s.hot < 0 && on >= 0 && !d.pressing && (d.rest > 0.45 || d.unseen) {   // a part that does nothing and has something to say: the why of a stage left, of a caution
		text = s.items[on].tip
		if text != "" do s.hot = on
	} else if !solid && d.screen == .Chart && pointer.x >= 0 && !d.on_map && (d.rest > 0.6 || d.unseen) do text = chart_tip(pointer)
	else if !solid && d.screen == .Plan && pointer.x >= 0 && !d.on_map && (d.rest > 0.3 || d.unseen) do text = plan_tip()
	if text != "" {
		L := &LOOK
		play.area = .World
		tw := min(text_wide(.Small, text), px(96))
		w, h := tw + 2*px(L.chip_pad.x), text_high(.Small, text, tw) + 2*px(L.chip_pad.y)
		x, y := pointer.x + px(4), pointer.y + px(5)
		if s.hot >= 0 {
			r := s.items[s.hot].rect
			if r.y > 0.85*s.h do x, y = r.x, r.y - px(2) - h   // a part at the picture's foot: over it, clear of those beside it
			else if r.x + r.w/2 > 0.5*s.w do x, y = r.x - px(2) - w, r.y
			else do x, y = r.x + r.w + px(2), r.y   // beside it, toward the picture's middle, so that nothing of its own panel is covered
		}
		if s.hot < 0 && d.screen == .Plan && x + w > s.w - px(L.margin) - px(L.isles_wide) - px(2) do x = pointer.x - px(4) - w   // beside the pointer on the island: on the side away from the expedition's column
		if x + w > s.w - px(1) do x = s.w - px(1) - w
		if y + h > s.h - px(1) do y = s.h - px(1) - h
		part(.Tip, {math.round(x), math.round(y), w, h}, text, .Small, {}, {.Wrap}, id = "tip")
	}
	screen_draw(s)
}

// Draw the frame: the sea's own dark where no picture lies, and the screen's parts over it.
door_render :: proc(g: ^Gpu, shot: string) {
	chart_upload(g)
	cmd, swap, sw, sh, ok := frame_begin(g, shot)
	if !ok do return
	sea := LOOK.seas[1]
	ground := sdl.GPUColorTargetInfo{texture = g.scene, load_op = .CLEAR, store_op = .STORE, clear_color = {f32(sea.r)/255, f32(sea.g)/255, f32(sea.b)/255, 1}}
	pass := sdl.BeginGPURenderPass(cmd, &ground, 1, nil)
	sdl.EndGPURenderPass(pass)
	ui_render(g, cmd)
	frame_end(g, cmd, swap, sw, sh, shot)
}

// A button for an act before play, with that act's key written on it.
door_button :: proc(r: Rect, text: string, act: Act, arg := 0, id := "", tip := "", main := false, faint := false, held := false) {
	state: bit_set[State]
	if main do state += {.Main}
	if faint do state += {.Faint}
	if held do state += {.Held}
	part(.Button, r, text, .Body, {}, state, act, arg, door_key(act, arg), id, tip)
}

// The front door and the screens that stand in its place: the world's map behind, moving slowly,
// dark toward the left; the game's name; and under it the choices, or the screen chosen.
front_build :: proc() {
	d, c, u, L := &door, &chart, &play, &LOOK
	// The view: the start island a little right of the middle, the sea round it, drifting.
	was_at, was_span := c.at, c.span
	records := sync.atomic_load(&making.records)
	if size := archipelago[0].size if records else d.kept_size; size > 0 {
		origin := [2]f64{f64(archipelago[0].origin.x), f64(archipelago[0].origin.y)} if records else [2]f64{}
		c.span = 1.2*size   // its land fills the picture's height and runs in under the words
		reach := 0.05*size
		pace := f64(px(L.drift))*c.span/f64(max(screen.w, 1))/reach   // so that the picture moves so many pixels a second at its fastest
		c.at = origin + {-0.13*c.span + reach*math.sin(d.now*pace), 0.02*c.span + 0.6*reach*math.sin(0.7*d.now*pace + 1)}
		if !records && c.door {   // the world's records are not made yet: the start island as the last run painted it, where it will stand
			c.wide, c.high = screen.w, screen.h
			u.area = .Chart
			at, side := chart_to(origin), f32(f64(c.wide)/c.span*size)
			it := part(.Picture, {at.x - side/2, at.y - side/2, side, side}, id = "chart.isle")
			it.uv, it.arg = {0, 0, 1, 1}, 1
		}
	}
	chart_map(true)
	c.at, c.span = was_at, was_span
	u.area = .Door
	part(.Fade, {0, 0, screen.w, screen.h}, id = "door.shade")
	x := min(px(L.door_left), 0.07*screen.w)
	y := min(px(L.door_top), 0.17*screen.h)
	y += words(x, y, "OdinCraft", .Door, id = "door.title") + px(1)
	y += words(x, y, door_says(), .Body, L.ash, "door.world", px(L.door_wide)) + px(12)
	inset := min(px(L.door_left), 0.07*screen.w)*0.6
	first := len(screen.items)
	made := making_build(screen.w - inset, screen.h - inset, screen.w - 2*inset, false)
	u.area = .Door
	switch d.screen {
	case .Door:     choices_build(x, y, made)
	case .Worlds:   worlds_build(x, y)
	case .New:      new_build(x, y)
	case .Settings: settings_build(x, y)
	case .Chart, .Plan:
	}
	panels := [Before]string{.Door = "", .Worlds = "worlds", .New = "new", .Settings = "settings", .Chart = "", .Plan = ""}
	if panel := screen_find(&screen, panels[d.screen]); panels[d.screen] != "" && panel != nil && made.h > 0 {
		r := panel.rect   // a screen's own panel has the room first: the world being made is told at the front door
		if made.x < r.x + r.w + px(2) && made.y < r.y + r.h + px(2) {
			for i := len(screen.items) - 1; i >= first; i -= 1 do if screen.items[i].area == .Making do ordered_remove(&screen.items, i)
		}
	}
}

// What the world in hand is, under the game's name.
door_says :: proc() -> string {
	if !sync.atomic_load(&making.records) do return fmt.tprintf("The world of seed %d. Nothing of it is known yet.", making.seed)
	return fmt.tprintf("The world of seed %d. %s", making.seed, start_says())
}

// The five choices. The one in focus is brass, with its key.
choices_build :: proc(x, y: f32, made: Rect) {
	d, L := &door, &LOOK
	y := y
	Row :: struct { name, note, id, tip: string }
	entering := fmt.tprintf("%s, seed %d", isle_name(0), making.seed) if sync.atomic_load(&making.records) else fmt.tprintf("seed %d", making.seed)
	if !world_enterable(0) {
		done, all, _ := making_progress(.Near)
		entering = fmt.tprintf("seed %d: %s of its %s islands near the start %s made", making.seed, number_words(done) if done > 0 else "none", number_words(all), "is" if done == 1 else "are") if all > 0 else fmt.tprintf("seed %d: its history is being read", making.seed)
		if all > 0 && !sync.atomic_load(&making.massed) do entering = fmt.tprintf("seed %d: its mainland is being formed, and its islands after", making.seed)
		if d.wish != .None do entering = fmt.tprintf("%s. You go in when they are", entering)
	}
	worlds := worlds_count()
	rows := [DOOR_CHOICES]Row{
		{"Enter the last world" if d.last == 0 || d.last == making.seed else fmt.tprintf("Enter the world of seed %d", making.seed), entering, "door.enter", "Into the world at its start, where the party comes ashore."},
		{"Worlds", fmt.tprintf("%s on this machine", number_words(worlds)) if worlds > 0 else "none kept yet", "door.worlds", "The worlds this machine has made, and what is known of each."},
		{"Make a new world", "", "door.new", "A world from a seed, typed or drawn."},
		{"Settings", "", "door.settings", "The interface's size, and the keys."},
		{"Quit", "", "door.quit", ""},
	}
	for row, i in rows {
		w := px(L.choice_pad) + text_wide(.Figure, row.name) + px(L.key_gap) + px(1) + key_wide("Enter") + px(3)
		part(.Choice, {x - px(L.choice_pad), y, w, px(L.choice)}, row.name, .Figure, {}, {.Chosen} if d.focus == i else {}, .Door_Pick, i, door_key(.Door_Go), row.id, row.tip)
		if row.note != "" {
			nx := x + text_wide(.Figure, row.name) + px(3) + (px(L.key_gap) + px(1) + key_wide("Enter") + px(1) if d.focus == i else 0)
			room := (made.x - px(3) if made.h > 0 && y + px(L.choice) > made.y else screen.w - px(L.margin)) - nx   // not under the world being made
			words(nx, y + math.round((px(L.choice) - line_of(.Body))/2) + px(0.5), fit(.Body, row.note, room), .Body, L.ash, "door.note")
		}
		y += px(L.choice)
	}
}

// How many worlds have a history kept on this machine, read when it is asked first and when one is made.
worlds_count :: proc() -> int {
	d := &door
	@(static) read: bool
	@(static) order: int
	if !read || order != making.order && sync.atomic_load(&making.records) {
		worlds_read()
		read, order = true, making.order
	}
	return len(d.worlds)
}

// A panel standing in the choices' place, with a name: returns where its words begin and how wide they may be.
front_panel :: proc(x, y: f32, title, id: string) -> (cx, cy, inner: f32, r: ^Screen_Part) {
	L := &LOOK
	w := px(L.door_wide)
	r = part(.Panel, {x - px(L.pad.x), y, w, screen.h - y - min(px(L.door_left), 0.07*screen.w)*0.6}, id = id)
	cx, cy, inner = x, y + px(L.pad.y), w - 2*px(L.pad.x)
	cy += words(cx, cy, title, .Great, id = fmt.tprintf("%s.title", id)) + px(2)
	return
}

// The worlds this machine has made: each with what was written down of it. A row opens its screen.
worlds_build :: proc(x, y: f32) {
	d, u, L := &door, &play, &LOOK
	cx, cy, inner, panel := front_panel(x, y, "Worlds", "worlds")
	if len(d.worlds) == 0 do cy += words(cx, cy, "No world is kept on this machine yet. Make a new one, and it is kept here.", .Body, L.ash, "worlds.none", inner)
	row_of :: proc(w: Kept_World, inner: f32) -> (high: f32, kept: string) {
		days := int(time.duration_hours(time.since(w.kept))/24)
		kept = ("within the last day" if days < 1 else "a day ago" if days == 1 else fmt.tprintf("%d days ago", days)) if w.fresh else "by an earlier build: it is run again when opened"
		high = px(LOOK.row_pad.y)*2 + line_of(.Name) + px(1) + f32(max(len(w.says), 1) + 1)*line_of(.Small)
		return
	}
	all := f32(0)
	for w in d.worlds { h, _ := row_of(w, inner); all += h }
	foot := min(panel.rect.y + panel.rect.h - px(L.pad.y) - px(L.button) - px(3), cy + all)
	panel.rect.h = foot + px(3) + px(L.button) + px(L.pad.y) - panel.rect.y
	box := Rect{panel.rect.x + 1, cy, panel.rect.w - 2, foot - cy}
	u.clip = box
	top := cy
	cy -= d.scroll
	for w, i in d.worlds {
		name := fmt.tprintf("The world of seed %d", w.seed)
		note := "in hand" if w.seed == making.seed else ""
		high, when_ := row_of(w, inner)
		row := part(.Row, {box.x, cy, box.w, high}, state = {.Chosen} if d.focus == i else {}, act = .Door_Pick, arg = i, id = "worlds.row", tip = "Open this world's map.")
		if d.focus == i {   // the row in focus is kept in view
			if row.rect.y < box.y do d.scroll -= box.y - row.rect.y
			if row.rect.y + high > box.y + box.h do d.scroll += row.rect.y + high - box.y - box.h
		}
		ry := cy + px(L.row_pad.y)
		words(cx, ry, name, .Name, id = "worlds.name")
		if d.focus == i do key_part(door_key(.Door_Go), cx + text_wide(.Name, name) + px(L.key_gap), ry, line_of(.Name))
		if note != "" do part(.Text, {cx, ry, inner, line_of(.Name)}, note, .Body, L.brass, {.Right}, id = "worlds.note")
		ry += line_of(.Name) + px(1)
		fact :: proc(cx, ry, inner: f32, thing, says: string) -> f32 {   // a thing and what is so of it, on one line
			words(cx, ry, thing, .Small, LOOK.ash, "worlds.thing")
			words(cx + px(26), ry, fit(.Small, says, inner - px(26)), .Small, {}, "worlds.says")
			return line_of(.Small)
		}
		for s in w.says {
			thing, _, says := strings.partition(s, ": ")
			ry += fact(cx, ry, inner, thing, says) if says != "" else words(cx, ry, fit(.Small, s, inner), .Small, {}, "worlds.says")
		}
		if len(w.says) == 0 do ry += words(cx, ry, "Nothing was written down of it yet.", .Small, L.ash, "worlds.says")
		fact(cx, ry, inner, "Kept", when_)
		cy += high
	}
	u.clip = {}
	d.over = max(cy + d.scroll - top - box.h, 0)
	d.scroll = clamp(d.scroll, 0, d.over)
	if d.over > 0 do part(.Thumb, {box.x + box.w - px(1.5), box.y + box.h*d.scroll/(d.over + box.h), px(1.5), box.h*box.h/(d.over + box.h)}, id = "worlds.thumb")
	door_button({cx, foot + px(3), button_wide("Back", door_key(.Door_Back)), px(L.button)}, "Back", .Door_Back, 0, "worlds.back")
}

// A key's tab after some words, on their line.
key_part :: proc(key: string, x, y, high: f32) {
	if key == "" do return
	L := &LOOK
	w, h := key_wide(key), px(L.key_high)
	r := Rect{x, y + math.round((high - h)/2), w, h}
	part(.Fill, r, colour = L.edge)
	part(.Fill, {r.x + 1, r.y + 1, r.w - 2, r.h - 3}, colour = L.deep)
	part(.Text, {r.x + math.round((w - text_wide(.Key, key))/2), r.y, text_wide(.Key, key), line_of(.Key)}, key, .Key, L.ash)
}

// A new world: its seed, typed or drawn, and what making it will do.
new_build :: proc(x, y: f32) {
	d, L := &door, &LOOK
	cx, cy, inner, panel := front_panel(x, y, "A new world", "new")
	cy += words(cx, cy, "Every world comes whole from one number, its seed. The same seed makes the same world.", .Body, L.ash, "new.says", inner) + px(5)
	cy += words(cx, cy, "Its seed", .Body, L.ash) + px(2)
	typed := string(d.typed[:])
	field := line_of(.Figure) + 2*px(2)
	draw := button_wide("Draw one", door_key(.Draw))
	part(.Field, {cx, cy, inner - draw - px(L.gap), field}, typed if typed != "" else "type a number", .Figure, {}, {.Held} + ({.Faint} if typed == "" else {}), id = "new.seed")
	door_button({cx + inner - draw, cy, draw, field}, "Draw one", .Draw, 0, "new.draw", "Draw a seed.")
	cy += field + px(5)
	s, ok := strconv.parse_uint(typed, 10)
	ok &&= s > 0 && s <= uint(max(u32))
	says := "Type a seed, or draw one."
	if typed != "" && !ok do says = "A seed is a whole number from 1 to 4,294,967,295."
	if ok {
		kept := false
		for w in d.worlds do if w.seed == u32(s) && w.fresh do kept = true
		if u32(s) == making.seed do says = "This is the world in hand. Its map is opened."
		else if kept do says = "A world of this seed is kept on this machine. Its history is read back."
		else do says = "It is made in these stages, and can be looked at from the second on."
	}
	cy += words(cx, cy, says, .Body, {}, "new.will", inner) + px(2)
	if ok && u32(s) != making.seed {   // what making it will take: a stage a row, with how long it took on this machine where that is known
		kept := false
		for w in d.worlds do if w.seed == u32(s) && w.fresh do kept = true
		for stage in Stage {
			took := ""
			switch stage {
			case .Plates:   took = "read back" if kept else fmt.tprintf("about %.0f s", math.ceil(d.took[.Plates])) if d.took[.Plates] > 0 else "a few seconds"
			case .Region:   took = "read back" if kept else fmt.tprintf("about %.0f s", math.ceil(d.took[.Region])) if d.took[.Region] > 0 else "under a second"
			case .Mainland: took = "minutes, once, where it is small enough"
			case .Near:     took = fmt.tprintf("about %.0f s", math.ceil(d.took[.Near])) if d.took[.Near] > 0 else "a few seconds"
			case .Far:      took = "as you look or play"
			}
			part(.Rule, {cx, cy, inner, 1})
			cy += px(1)
			words(cx, cy, STAGES[stage].name, .Body, L.ash, "new.stage")
			part(.Text, {cx, cy, inner, line_of(.Body)}, took, .Body, {}, {.Right}, id = "new.took")
			cy += line_of(.Body) + px(1)
		}
		part(.Rule, {cx, cy, inner, 1})
	}
	cy += px(5)
	make_wide := button_wide("Make it", door_key(.Door_Go), .Bold)
	door_button({cx, cy, make_wide, px(L.button)}, "Make it" if !(ok && u32(s) == making.seed) else "Open it", .Door_Go, 0, "new.make", main = ok, faint = !ok)
	door_button({cx + make_wide + px(L.gap), cy, button_wide("Back", door_key(.Door_Back)), px(L.button)}, "Back", .Door_Back, 0, "new.back")
	panel.rect.h = cy + px(L.button) + px(L.pad.y) - panel.rect.y
}

// Settings: the interface's size, and the keys, a row of BINDS each.
settings_build :: proc(x, y: f32) {
	d, u, L := &door, &play, &LOOK
	cx, cy, inner, panel := front_panel(x, y, "Settings", "settings")
	cy += words(cx, cy, "The interface's size", .Body, L.ash) + px(2)
	sizes := [6]string{"75%", "100%", "125%", "150%", "175%", "200%"}
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	sx := cx
	for n, i in sizes {
		cw := text_wide(.Body, n) + 2*px(L.chip_pad.x)
		part(.Chip, {sx, cy, cw, chip}, n, .Body, {}, {.Chosen} if ui.module == i + 3 else {}, .Scale, i + 3, id = "settings.size")
		sx += cw + px(L.gap)
	}
	cy += chip + px(6)
	cy += words(cx, cy, "The keys", .Body, L.ash) + px(1)
	cy += words(cx, cy, "Click a key, then press the one it is to be. The keys that move the view and the walker are not in this list yet: the arrows, Q and E, Page Up and Page Down from above; W A S D, Space and Shift on foot.", .Small, L.ash, "settings.says", inner) + px(3)
	foot := panel.rect.y + panel.rect.h - px(L.pad.y) - px(L.button) - px(3)
	box := Rect{panel.rect.x + 1, cy, panel.rect.w - 2, foot - cy}
	part(.Rule, {box.x, cy, box.w, 1}, colour = L.edge)
	u.clip = box
	top := cy
	cy -= d.scroll
	row_high := line_of(.Body) + 2*px(L.row_pad.y)
	for view in Views {
		cy += px(2)
		part(.Text, {cx, cy, inner, line_of(.Small)}, VIEWS_SAID[view], .Small, L.ash, id = "settings.view")
		cy += line_of(.Small) + px(1)
		for b, i in BINDS do if b.views == view {
			waiting := d.rebind == i
			clash := false
			for o, j in BINDS do if j < i && o.key == b.key && views_meet(o.views, b.views) do clash = true
			part(.Row, {box.x, cy, box.w, row_high}, state = {.Chosen} if waiting else {}, act = .Rebind, arg = i, id = "settings.key",
				tip = "Another row before this one has the same key in the same view, and is obeyed in its place." if clash else "Click, then press the key this is to be. Escape leaves it as it is.")
			words(cx, cy + px(L.row_pad.y), key_says(b), .Body, id = "settings.does")
			if waiting {
				part(.Text, {cx, cy + px(L.row_pad.y), inner, line_of(.Body)}, "press a key", .Body, L.brass, {.Right}, id = "settings.waits")
			} else {
				kw := key_wide(b.name)
				key_part(b.name, cx + inner - kw, cy, row_high)
				screen.items[len(screen.items) - 1].id = "settings.name"
				if clash do part(.Sign, {cx + inner - kw - px(L.sign) - px(2), cy + math.round((row_high - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = .Caution
				if b.key != BINDS_WERE[i].key do part(.Fill, {cx + inner - kw - px(1), cy + px(L.row_pad.y), px(L.bar), line_of(.Body)}, colour = L.brass)   // changed from what the game began with
			}
			cy += row_high
		}
	}
	u.clip = {}
	d.over = max(cy + d.scroll - top - box.h, 0)
	d.scroll = clamp(d.scroll, 0, d.over)
	if d.over > 0 do part(.Thumb, {box.x + box.w - px(1.5), box.y + box.h*d.scroll/(d.over + box.h), px(1.5), box.h*box.h/(d.over + box.h)}, id = "settings.thumb")
	back := button_wide("Back", door_key(.Door_Back))
	door_button({cx, foot + px(3), back, px(L.button)}, "Back", .Door_Back, 0, "settings.back")
	door_button({cx + back + px(L.gap), foot + px(3), button_wide("The keys as they were", ""), px(L.button)}, "The keys as they were", .Keys_Back, 0, "settings.were", "Give every row the key the game began with.")
}

// A world being made: each stage named, with what is made and what is left, and the way to stop.
// It stands with its right and its foot at a point, as tall as it needs.
making_build :: proc(right, foot, wide: f32, brief: bool) -> (at: Rect) {
	m, u, L := &making, &play, &LOOK
	working := sync.atomic_load(&m.working)
	records := sync.atomic_load(&m.records)
	if !working && !m.stopped && (!records || world_whole()) do return
	u.area = .Making
	w := min(px(L.making_wide), wide)
	inner := w - 2*px(L.pad.x)
	x := right - w
	first := len(screen.items)
	part(.Panel, {x, 0, w, 0}, id = "making")
	cx, y := x + px(L.pad.x), px(L.pad.y)
	stage := making_stage()
	can := world_enterable(0)
	if sync.atomic_load(&m.waiting) {   // ordered, and the world before it not yet put down: nothing of its stages is this world's
		y += words(cx, y, fmt.tprintf("Making the world of seed %d", m.seed), .Title, id = "making.title")
		y += words(cx, y, "The world before it is put down first: the island in hand there is finished.", .Body, L.ash, "making.state", inner) + px(L.pad.y)
		screen.items[first].rect.h = y
		for &it in screen.items[first:] do it.rect.y += foot - y
		return screen.items[first].rect
	}
	y += words(cx, y, fmt.tprintf("%s the world of seed %d", "Forming" if m.kept else "Making", m.seed), .Title, id = "making.title")
	state := "You can enter when the islands near the start are made."
	if records && !sync.atomic_load(&m.massed) do state = "The islands are made once the mainland is. You can look at the world meanwhile."
	switch {
	case m.stopped && working: state = "Stopping. The plates' history runs to its end first." if !records else "Stopping once the mainland's stage is done. Leave it as known to stop now." if !sync.atomic_load(&m.massed) else "Stopping. The island in hand is finished first."
	case m.stopped: state = "Stopped. Nothing more is made until you say."
	case can: state = "It can be entered. The far islands are made as you look or play."
	}
	if !brief || m.stopped {   // in brief, the stage running says it; a world stopped has none
		if can && !m.stopped do part(.Sign, {cx, y + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = .Well
		y += words(cx + (px(L.sign) + px(2) if can && !m.stopped else 0), y, state, .Body, L.ash, "making.state", inner - px(L.sign) - px(2))
	}
	y += px(3)
	for s in Stage {
		done, all, now := making_progress(s)
		near_done, near_all, _ := making_progress(.Near)
		massed := sync.atomic_load(&m.massed)
		landed := sync.atomic_load_explicit(&lands_state.regions, .Acquire)   // a large land's coarse stage stands
		lands_kept := true   // and none of them was formed in this run
		if landed do for &l in lands do if l.ready && !l.kept do lands_kept = false
		made := s <= .Region && (stage > s || records) || s == .Mainland && records && massed || s >= .Near && records && massed && done >= all
		running := !made && !m.stopped && (s <= .Region && working && stage == s || s == .Mainland && records && stage == .Mainland || s == .Near && records && massed || s == .Far && records && massed && near_done >= near_all)
		if brief && !running do continue   // in brief: the stage running alone
		row := STAGES[s]
		said := ""
		switch {
		case made && s <= .Region: said = "kept from an earlier run" if m.kept else fmt.tprintf("made in %.1f s", m.took[s])
		case made && s == .Mainland: said = ("kept from an earlier run" if lands_kept else fmt.tprintf("made in %s", span_words(m.took[s]))) if landed else "left as the history has it"
		case made && s == .Near:   said = fmt.tprintf("made in %.1f s", m.took[s]) if m.took[s] > 0 else "made"
		case made:                 said = "made" if all > 0 else "none"
		case running && s == .Mainland: said = fmt.tprintf("%d of %d steps", done, all) if all > 0 else ""
		case running:              said = fmt.tprintf("%d of %d%s", done, all, " million years" if s <= .Region else "")
		case s == .Far:            said = "made as you look or play"
		case all > 0 && done > 0:  said = fmt.tprintf("%d of %d", done, all)
		}
		part(.Rule, {cx, y, inner, 1})
		y += px(1.5)
		if made && !(s == .Mainland && !landed) do part(.Sign, {cx, y + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = .Well
		if made && s == .Mainland && !landed {   // why it was left, beside the pointer
			part(.Fill, {cx, y, inner, line_of(.Body)}, colour = {}, state = {.Solid}, id = "making.why", tip = fmt.tprintf("The mainland is not formed as land: %s.", land_why(0)))
		}
		if running do part(.Sign, {cx, y + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = .Caution
		words(cx + px(L.sign) + px(2), y, row.name, .Body, L.brass if running else L.chalk if made else L.ash, "making.stage")
		if px(L.sign) + px(2) + text_wide(.Body, row.name) + px(3) + text_wide(.Body, said) > inner {   // no room beside its name: under it
			y += line_of(.Body)
			words(cx + px(L.sign) + px(2), y - px(1), said, .Small, L.brass if running else L.ash, "making.said")
			y += line_of(.Small) + px(0.5)
		} else {
			part(.Text, {cx, y, inner, line_of(.Body)}, said, .Body, L.brass if running else L.ash, {.Right}, id = "making.said")
			y += line_of(.Body) + px(1.5)
		}
		if !running do continue
		part(.Fill, {cx, y, inner, px(L.meter)}, colour = L.pit, id = "making.track")
		if all > 0 do part(.Fill, {cx, y, math.round(inner*f32(done)/f32(all)), px(L.meter)}, colour = L.brass, id = "making.meter")
		y += px(L.meter) + px(2)
		what := row.makes
		if s == .Mainland {   // long the first time: how long, and the way to leave it
			left := lands_state.expect*f64(all - done)/f64(max(all, 1))   // by what such land takes here, until it has run long enough to say by its own pace
			if done >= 8 do left = time.duration_seconds(time.since(lands_state.began))*f64(all - done)/f64(done)
			if all > 0 do what = fmt.tprintf("%s About %s more on this machine.", what, span_words(left))
		}
		if len(now) > 0 {
			b := strings.builder_make(context.temp_allocator)
			for i, k in now do fmt.sbprintf(&b, "%s%s", "" if k == 0 else ", ", isle_name(i))
			what = fmt.tprintf("In hand: %s.", strings.to_string(b))
		}
		if !brief do y += words(cx, y, what, .Small, L.ash, "making.makes", inner) + px(2)
		if s == .Mainland && all > 0 {   // in brief too: it is the one way to leave a stage that runs for minutes
			leave := "Leave it as known"
			door_button({cx, y, button_wide(leave, ""), px(L.button)}, leave, .Mass_Leave, 0, "making.leave", "Stop forming the mainland: it stays as the plates' history has it for now, and the islands are made. It is formed the next time this world is opened.", faint = sync.atomic_load(&lands_state.leave))
			y += px(L.button) + px(3)
		}
	}
	part(.Rule, {cx, y, inner, 1})
	y += px(3)
	stop := "Go on making it" if m.stopped else "Stop making it"
	door_button({cx, y, button_wide(stop, door_key(.Stop)), px(L.button)}, stop, .Stop, 0, "making.stop",
		"Go on from where it stopped." if m.stopped else "Begin no more islands. The one in hand is finished, since forming has no place to stop inside an island.", faint = m.stopped && working)
	y += px(L.button) + px(L.pad.y)
	screen.items[first].rect.h = y
	for &it in screen.items[first:] do it.rect.y += foot - y   // to its place, its foot where it was asked to stand
	return screen.items[first].rect
}

// ---- without a window -------------------------------------------------------------------------

// Put the screen in the state the options ask for, once; then say whether the world being made has
// come as far as the picture is to show it (`when`).
door_posed :: proc(opt: ^Options) -> bool {
	d, c := &door, &chart
	records := sync.atomic_load(&making.records)
	if !d.posed {
		d.posed = true
		clear(&d.typed)
		append(&d.typed, opt.find)
		if opt.focus > 0 do d.focus = opt.focus - 1
	}
	if records && opt.has_door && (opt.has_pick || opt.lens != "" || opt.tab != "" || opt.has_over) && c.wide > 0 {   // set once the records are there to set it on
		if opt.has_pick do chart_take(opt.pick if opt.pick < len(archipelago) else -1, true)
		for l, i in WORLD_LENSES do if strings.equal_fold(l.name, opt.lens) || FIELDS[l.field].name == opt.lens do sync.atomic_store(&c.lens, i)
		for name, t in ISLE_DEPTHS do if strings.equal_fold(name, opt.tab) do c.depth = t
		if opt.has_over do c.at = opt.over
		if opt.span != 160 do c.span = clamp(opt.span, SPAN_WORLD[0], SPAN_WORLD[1])
		if opt.has_over || opt.span != 160 do c.going = false
	}
	name, _, count := strings.partition(opt.at_when, ":")
	n := 2
	if k, ok := strconv.parse_int(count); ok do n = k
	stage := making_stage()
	painted := records && chart_painted()
	late :: proc(what: string) -> bool {
		if !door.said do fmt.eprintfln("the making was past %s before a picture could be taken of it: this one is of where it had come to", what)
		door.said = true
		return true
	}
	switch name {
	case "now": return true
	case "plates", "region":
		want := Stage.Plates if name == "plates" else Stage.Region
		done, all, _ := making_progress(want)
		if stage == want && done*2 >= all do return true
		return late(name) if stage > want else false
	case "islands":
		done, _, _ := making_progress(.Near)
		if stage == .Near && done >= n && c.known do return true
		return late("the islands near the start") if stage > .Near && painted else false
	case "mainland":   // while its coarse stage runs, a few steps in
		done, _, _ := making_progress(.Mainland)
		if stage == .Mainland && done >= 2 && c.known do return true
		return late("the mainland") if stage > .Mainland && painted else false
	case "all": return world_whole() && painted
	}
	return world_enterable(0) && painted
}

// Press the next of the parts the options name (`press`), by what it does, and say whether none is left.
pressed_all :: proc(opt: ^Options, act: proc(act: Act, arg: int)) -> bool {
	@(static) waited: int
	if len(opt.press) == 0 do return true
	it := screen_find(&screen, opt.press[0])
	if it == nil || it.act == .None {
		waited += 1
		if waited > 600 {
			fmt.eprintfln("no part named %s can be pressed on this screen", opt.press[0])
			os.exit(2)
		}
		return false
	}
	waited = 0
	ordered_remove(&opt.press, 0)
	act(it.act, it.arg)
	return false
}
