package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import sdl "vendor:sdl3"

// The play script (--play=file): the game played with no window by a file of what a player's hand
// does, so that a step can be played before it is merged (open-decisions.md, 2026-11-16). Each line
// is one thing the hand does, or one thing the script asks; the pointer's moves, its presses and
// the keys become the events a real pointer and keyboard send, and go through the one loop that
// reads those (main.odin), so a click here is a click there. A frame is a sixtieth of a second, and
// each press, move and release has a frame of its own, as a hand's do.
//
// The hand's lines, the pointer's figures in pixels of the picture (twice the size asked for):
//   move x y                the pointer goes there
//   press [right|middle]    a button goes down where the pointer is; release lets it go
//   click x y [right]       move, press, release
//   drag x y x y [right]    press at the first, move to the second over a quarter of a second, release
//   key NAME [shift]        a key goes down: a letter, a digit, Space, Tab, Esc, Enter, F1 to F12, Up, Down, Left, Right, PageUp, PageDown,
//                           Home, Backspace, = and -
//   type words              the keyboard types them, as into a field
//   wheel n                 the wheel turns n notches
//   part words              click the middle of the part of the screen that says those words, or has that name (--say prints
//                           both); words ending in * are the beginning of what it says
// What the script asks, which no hand does:
//   view over=x,z [span=m] [tilt=deg] [turn=deg] [cut=level|ground|off] [bare|leaves]
//                           put the view from above somewhere, as the options do, and wait for the world there
//   foot x,h,z yaw,pitch    stand h metres over the ground at x, z, looking that way, in first person
//   wait seconds            let that much of the player's time pass
//   run seconds             let that much of the dwarves' time pass, at whatever speed the clock is running
//   timer                   note the dwarves' time
//   until hour h            let the dwarves' time pass until their day next comes to that hour: until hour 22.5
//   until done [seconds]    wait until nothing is marked and no dwarf has work in hand or carries anything, or so many seconds of
//                           the dwarves' time; say how long it took since the timer, in their time and the player's
//   shot file.png           wait for the world to be drawn whole, and save the picture
//   snap file.png           save the picture as it stands this frame, waiting for nothing
// Before play (door.odin), where a run begun with --door starts, the same lines go through the event
// the front door and the world's screen read; `wait` is then real seconds, since a world is made in
// real time, and besides:
//   until ready [seconds]   wait until the world in hand can be entered and its pictures are painted, and say how long it took
//   until made [seconds]    wait until every island of it is formed
//   until mainland          wait until the mainland's long stage is running, a few steps in
//   view over=x,z span=m    put the world's map somewhere
//   under                   print what the pointer is on, on the map
//   say                     print what the screen says, area by area
//   under                   print the block under the pointer
//   print words             print a line
// A line beginning with # is a note.

Step_Kind :: enum u8 { Frames, Loaded, Part, Move, Press, Release, Key, Wheel, View, Foot, Wait, Run, Timer, Until, Shot, Say, Under, Print, Type }
Step :: struct {
	kind:   Step_Kind,
	v:      [5]f64,
	n:      int,
	text:   string,
	button: u8,
	shift:  bool,
	set:    bit_set[0..<8],   // view: which of its figures were given
}
Script :: struct {
	on:      bool,
	steps:   [dynamic]Step,
	at:      int,
	count:   int,                    // frames waited in the step in hand
	began:   f64,                    // the time the step in hand began waiting from; negative when it has not
	timer:   f64,
	pointer: [2]f32,                 // in the picture's pixels
	buttons: sdl.MouseButtonFlags,
	shift:   bool,
	hurry:   bool,                   // only waiting: frames need not be paced as a display's
}
script: Script

SCRIPT_FRAME :: 1.0/60   // seconds of the player's time in a frame of a script

// The buttons held and whether Shift is, from the script while one plays and else from the hand.
pointer_buttons :: proc() -> sdl.MouseButtonFlags { return script.buttons if script.on else sdl.GetMouseState(nil, nil) }
shift_held :: proc() -> bool { return script.shift if script.on else sdl.GetModState() & sdl.KMOD_SHIFT != {} }

script_key :: proc(name: string) -> (code: sdl.Scancode, ok: bool) {
	NAMED := [?]struct { name: string, code: sdl.Scancode }{
		{"space", .SPACE}, {"tab", .TAB}, {"esc", .ESCAPE}, {"enter", .RETURN}, {"up", .UP}, {"down", .DOWN}, {"left", .LEFT}, {"right", .RIGHT},
		{"pageup", .PAGEUP}, {"pagedown", .PAGEDOWN}, {"backspace", .BACKSPACE}, {"0", ._0}, {"home", .HOME}, {"=", .EQUALS}, {"-", .MINUS},
	}
	n := strings.to_lower(name, context.temp_allocator)
	for k in NAMED do if k.name == n do return k.code, true
	if len(n) == 1 && n[0] >= 'a' && n[0] <= 'z' do return sdl.Scancode(int(sdl.Scancode.A) + int(n[0] - 'a')), true
	if len(n) == 1 && n[0] >= '1' && n[0] <= '9' do return sdl.Scancode(int(sdl.Scancode._1) + int(n[0] - '1')), true
	if len(n) >= 2 && n[0] == 'f' do if k, good := strconv.parse_int(n[1:]); good && k >= 1 && k <= 12 do return sdl.Scancode(int(sdl.Scancode.F1) + k - 1), true
	return
}

// Read a script, each line into the steps it is made of.
script_read :: proc(path: string) {
	s := &script
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintln("cannot read the play script in", path)
		os.exit(2)
	}
	figures :: proc(words: []string, out: []f64) -> bool {
		if len(words) < len(out) do return false
		for &o, i in out do o = strconv.parse_f64(words[i]) or_return
		return true
	}
	button :: proc(words: []string) -> u8 {
		for w in words {
			if w == "right" do return sdl.BUTTON_RIGHT
			if w == "middle" do return sdl.BUTTON_MIDDLE
		}
		return sdl.BUTTON_LEFT
	}
	append(&s.steps, Step{kind = .Loaded})
	for line in strings.split_lines(string(data)) {
		words := strings.fields(strings.trim_space(line))
		if len(words) == 0 || strings.has_prefix(words[0], "#") do continue
		rest := words[1:]
		ok := true
		v: [5]f64
		switch words[0] {
		case "move":
			ok = figures(rest, v[:2])
			append(&s.steps, Step{kind = .Move, v = v})
		case "press":   append(&s.steps, Step{kind = .Press, button = button(rest)})
		case "release": append(&s.steps, Step{kind = .Release, button = button(rest)})
		case "click":
			ok = figures(rest, v[:2])
			append(&s.steps, Step{kind = .Move, v = v}, Step{kind = .Frames, n = 2}, Step{kind = .Press, button = button(rest)}, Step{kind = .Frames, n = 2}, Step{kind = .Release, button = button(rest)}, Step{kind = .Frames, n = 2})
		case "drag":
			ok = figures(rest, v[:4])
			append(&s.steps, Step{kind = .Move, v = v}, Step{kind = .Frames, n = 2}, Step{kind = .Press, button = button(rest)})
			for i in 1..=15 {
				t := f64(i)/15
				append(&s.steps, Step{kind = .Move, v = {math.lerp(v[0], v[2], t), math.lerp(v[1], v[3], t), 0, 0, 0}})
			}
			append(&s.steps, Step{kind = .Frames, n = 2}, Step{kind = .Release, button = button(rest)}, Step{kind = .Frames, n = 2})
		case "key":
			code: sdl.Scancode
			if len(rest) > 0 do code, ok = script_key(rest[0])
			else do ok = false
			append(&s.steps, Step{kind = .Key, n = int(code), shift = len(rest) > 1 && rest[1] == "shift"}, Step{kind = .Frames, n = 2})
		case "part":
			ok = len(rest) > 0
			append(&s.steps, Step{kind = .Part, text = strings.clone(strings.join(rest, " ", context.temp_allocator))})
		case "wheel":
			ok = figures(rest, v[:1])
			append(&s.steps, Step{kind = .Wheel, v = v})
		case "view":
			step := Step{kind = .View}
			for w in rest {
				name, _, value := strings.partition(w, "=")
				part := strings.split(value, ",", context.temp_allocator)
				switch name {
				case "over": ok &&= figures(part, step.v[:2]); step.set += {0}
				case "span": ok &&= figures(part, step.v[2:3]); step.set += {1}
				case "tilt": ok &&= figures(part, step.v[3:4]); step.set += {2}
				case "turn": ok &&= figures(part, step.v[4:5]); step.set += {3}
				case "cut":
					step.set += {4}
					step.text = strings.clone(value)
				case "bare":   step.set += {5}
				case "leaves": step.set += {6}
				case: ok = false
				}
			}
			append(&s.steps, step, Step{kind = .Frames, n = 3}, Step{kind = .Loaded})
		case "foot":
			ok = len(rest) == 2
			if ok {
				ok = figures(strings.split(rest[0], ",", context.temp_allocator), v[:3]) && figures(strings.split(rest[1], ",", context.temp_allocator), v[3:5])
				append(&s.steps, Step{kind = .Foot, v = v}, Step{kind = .Frames, n = 3}, Step{kind = .Loaded})
			}
		case "wait", "run":
			ok = figures(rest, v[:1])
			append(&s.steps, Step{kind = .Wait if words[0] == "wait" else .Run, v = v})
		case "timer": append(&s.steps, Step{kind = .Timer})
		case "until":
			ok = len(rest) >= 1 && (rest[0] == "done" || rest[0] == "ready" || rest[0] == "made" || rest[0] == "mainland" || rest[0] == "hour" && len(rest) == 2)
			v[0] = 3600
			if len(rest) > 1 do ok &&= figures(rest[1:], v[:1])
			if ok do append(&s.steps, Step{kind = .Until, v = v, text = strings.clone(rest[0])})
		case "shot":
			ok = len(rest) == 1
			if ok do append(&s.steps, Step{kind = .Frames, n = 3}, Step{kind = .Loaded}, Step{kind = .Shot, text = strings.clone(rest[0])})
		case "snap":
			ok = len(rest) == 1
			if ok do append(&s.steps, Step{kind = .Shot, text = strings.clone(rest[0])})
		case "type":
			ok = len(rest) > 0
			append(&s.steps, Step{kind = .Type, text = strings.clone(strings.join(rest, " ", context.temp_allocator))}, Step{kind = .Frames, n = 2})
		case "say":   append(&s.steps, Step{kind = .Say})
		case "under": append(&s.steps, Step{kind = .Under})
		case "print": append(&s.steps, Step{kind = .Print, text = strings.clone(strings.join(rest, " ", context.temp_allocator))})
		case: ok = false
		}
		if !ok {
			fmt.eprintfln("bad line in the play script %s: %s", path, line)
			os.exit(2)
		}
	}
	s.on, s.began, s.pointer = true, -1, {-1, -1}
}

// One frame of the script: the events the hand makes in it, and what the script asks of this frame.
// `loaded` says the world round the view is drawn whole; `ratio` is pixels of the picture to a
// point of the window, which the pointer's events are told in.
script_frame :: proc(events: ^[dynamic]sdl.Event, a: ^Above, p: ^Player, afoot: ^bool, loaded: bool, seconds: f64, ratio: f32) -> (shot: string, say, under, ended: bool) {
	s := &script
	speeds := SPEEDS
	s.hurry = false
	for s.at < len(s.steps) {
		step := s.steps[s.at]
		e: sdl.Event
		at := s.pointer/ratio
		switch step.kind {
		case .Frames:
			if s.count < step.n {
				s.count += 1
				return
			}
			s.count = 0
		case .Loaded:
			s.hurry = true
			if !loaded do return
		case .Part:   // its place is found when the frame's parts have been listed (script_parts)
			return
		case .Move:
			to := [2]f32{f32(step.v[0]), f32(step.v[1])}
			e.type = .MOUSE_MOTION
			e.motion.x, e.motion.y, e.motion.xrel, e.motion.yrel, e.motion.state = to.x/ratio, to.y/ratio, (to.x - s.pointer.x)/ratio, (to.y - s.pointer.y)/ratio, s.buttons
			s.pointer = to
			append(events, e)
			s.at += 1
			return
		case .Press, .Release:
			down := step.kind == .Press
			flag := sdl.MouseButtonFlags{.LEFT} if step.button == sdl.BUTTON_LEFT else {.RIGHT} if step.button == sdl.BUTTON_RIGHT else {.MIDDLE}
			if down do s.buttons += flag
			else do s.buttons -= flag
			e.type = .MOUSE_BUTTON_DOWN if down else .MOUSE_BUTTON_UP
			e.button.button, e.button.x, e.button.y, e.button.down = step.button, at.x, at.y, down
			append(events, e)
			s.at += 1
			return
		case .Key:
			e.type = .KEY_DOWN
			e.key.scancode, e.key.down = sdl.Scancode(step.n), true
			if step.shift do e.key.mod = sdl.KMOD_LSHIFT
			s.shift = step.shift
			append(events, e)
			s.at += 1
			return
		case .Wheel:
			e.type = .MOUSE_WHEEL
			e.wheel.y = f32(step.v[0])
			append(events, e)
			s.at += 1
			return
		case .Type:
			e.type = .TEXT_INPUT
			e.text.text = strings.clone_to_cstring(step.text, context.temp_allocator)
			append(events, e)
			s.at += 1
			return
		case .View:
			if a == nil {   // before play: the world's map
				if 0 in step.set do chart.at, chart.going = {step.v[0], step.v[1]}, false
				if 1 in step.set do chart.span, chart.going = clamp(step.v[2], SPAN_WORLD[0], SPAN_WORLD[1]), false
				break
			}
			afoot^ = false
			if 0 in step.set do a.at, a.settled = {step.v[0], 0, step.v[1]}, false
			if 1 in step.set do a.span = clamp(step.v[2], SPAN_MIN, SPAN_MAX)
			if 2 in step.set do a.tilt = f32(math.to_radians(clamp(step.v[3], 0, 90)))
			if 3 in step.set do a.yaw = f32(math.to_radians(step.v[4]))
			if 4 in step.set {
				switch step.text {
				case "ground": cut_follow(a, true)
				case "off":    a.cut, a.follow = false, false
				case:          a.cut, a.follow, a.level = true, false, i32(strconv.parse_int(step.text) or_else 0)
				}
			}
			if 5 in step.set do a.bare = true
			if 6 in step.set do a.bare = false
		case .Foot:
			if a == nil {
				fmt.println("script: there is nowhere to stand before play")
				break
			}
			afoot^ = true
			p.pos = {step.v[0], f64(height_in_world(step.v[0], step.v[2], 1)) + step.v[1], step.v[2]}
			p.yaw, p.pitch, p.fly, p.vel = f32(math.to_radians(step.v[3])), f32(math.to_radians(step.v[4])), true, 0
		case .Wait:
			if s.began < 0 do s.began = seconds
			if seconds - s.began < step.v[0] do return
			s.began = -1
		case .Run:
			if a == nil {
				fmt.println("script: the dwarves' time does not run before play")
				break
			}
			s.hurry = true
			if s.began < 0 do s.began = watch.clock
			if watch.clock - s.began < step.v[0] do return
			s.began = -1
		case .Timer:
			s.timer = watch.clock
		case .Until:
			if step.text == "hour" {   // the next time the dwarves' day comes to that hour
				if a == nil {
					fmt.println("script: the dwarves' time does not run before play")
					break
				}
				s.hurry = true
				if s.began < 0 do s.began = watch.clock
				ahead := math.mod(f64(step.v[0]) - f64(date_at(s.began).hour) + 24, 24)
				if (watch.clock - s.began)*24/DAY < ahead do return
				s.began = -1
				break
			}
			if step.text != "done" {   // the world in hand, as it is made in real time (making.odin)
				if s.began < 0 do s.began = seconds
				there := false
				switch step.text {
				case "ready": there = world_enterable(0) && chart_painted()
				case "made":  there = world_whole() && chart_painted()
				case "mainland":
					done, _, _ := making_progress(.Mainland)
					there = making_stage() == .Mainland && done >= 2 || sync.atomic_load(&making.massed)
				}
				if !there && seconds - s.began < step.v[0] do return
				if there do fmt.printfln("script: the world of seed %d %s %.1f s after the script asked", making.seed, "can be entered" if step.text == "ready" else "is whole" if step.text == "made" else "has come to its mainland", seconds - s.began)
				else do fmt.printfln("script: the world of seed %d had not come to \"%s\" after %.0f s", making.seed, step.text, seconds - s.began)
				s.began = -1
				break
			}
			if a == nil {
				fmt.println("script: no dwarves are at work before play")
				break
			}
			s.hurry = true
			if s.began < 0 do s.began = watch.clock
			busy := watch.seen.marks > 0
			for d in watch.seen.dwarves do busy ||= d.job || d.carrying > 0 || d.fetching
			if watch.clock - s.began < 1 || busy && watch.clock - s.began < step.v[0] do return   // an order just given takes a tick to be the hold's
			took := watch.clock - s.timer
			pace := speeds[play.clock.speed]
			if busy {
				fmt.printfln("script: the work is not done %.0f s of the dwarves' time after it was begun: %d marks are left", took, watch.seen.marks)
				for site in watch.seen.sites {
					fmt.printf("script:   the %s: %d of %d left, %d in hand", site.place, site.left, site.total, site.busy)
					for n, why in site.waits do if n > 0 do fmt.printf("; %d %s", n, WAITS[why] if why != .None else "free to take")
					fmt.println()
				}
				for t in watch.seen.tints do fmt.printfln("script:   still to dig: %d %d %d to %d %d %d", t.lo.x, t.lo.y, t.lo.z, t.hi.x, t.hi.y, t.hi.z)
				for d in watch.seen.dwarves do fmt.printfln("script:   %s: %v at %.1f %.1f %.1f%s%s", d.who.given, d.doing, d.at.x, d.at.y, d.at.z, ", with work" if d.job else "", ", shut in" if d.shut else "")
			}
			else do fmt.printfln("script: the work is done %.1f s of the dwarves' time after it was begun: %.1f s of the player's with the clock at %.0f times", took, took/pace, pace)
			s.began = -1
		case .Shot:
			s.at += 1
			return step.text, false, false, false
		case .Say:
			s.at += 1
			return "", true, false, false
		case .Under:
			s.at += 1
			return "", false, true, false
		case .Print:
			fmt.printfln("script: %s", step.text)
		}
		s.at += 1
	}
	return "", false, false, true
}

// Once the frame's parts are listed: the part a step asks for is found, and the step becomes the
// moves and presses of a click on its middle. Its words are the frame's own, gone by the next.
script_parts :: proc() {
	s := &script
	if !s.on || s.at >= len(s.steps) || s.steps[s.at].kind != .Part do return
	want := s.steps[s.at].text
	// A part that does something first; then any that says the words, since a hand clicks on words and
	// the click lands on whatever lies under them (a row of a list, a row of a card).
	for pass in 0..<2 do for it in screen.items do if (it.id == want || it.text == want || strings.has_suffix(want, "*") && strings.has_prefix(it.text, want[:len(want) - 1])) && (it.act != .None || pass == 1) {
		c := [2]f64{f64(it.rect.x + it.rect.w/2), f64(it.rect.y + it.rect.h/2)}
		s.steps[s.at] = Step{kind = .Move, v = {c.x, c.y, 0, 0, 0}}
		inject_at(&s.steps, s.at + 1, Step{kind = .Frames, n = 2}, Step{kind = .Press, button = sdl.BUTTON_LEFT}, Step{kind = .Frames, n = 2}, Step{kind = .Release, button = sdl.BUTTON_LEFT}, Step{kind = .Frames, n = 2})
		return
	}
	fmt.printfln("script: no part of the screen says or is named \"%s\"", want)
	s.at += 1
}
