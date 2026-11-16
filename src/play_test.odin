package main

import "core:math"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

// The play screen is data (docs/adr/0010): a list of parts made from the game as it stands, with
// no window. These tests make it over the default world's start island and ask what it says, press
// its buttons as the pointer and the keys do, and check that it lies inside the picture at every scale.
// Called by the forming test once the start island is formed and bound, as the dwarves' test is.

@(private="file")
Stage :: struct {
	a:       Above,
	clock:   Clock,
	p:       Player,
	w:       ^World,
	afoot, captured, running: bool,
	eye:     [3]f64,
	pitch:   f32,
}

@(private="file")
stage_make :: proc(s: ^Stage) {
	hold, watch = {}, {selected = -1}   // no dwarves: this is the screen's own test
	at, yaw := find_start()
	s.a = {at = at, yaw = yaw, tilt = math.to_radians(f32(50)), span = 160}
	s.w, s.running = new(World), true
	play = {lens = -1, lens_shown = -1, open = {0}}
	opt := Options{}
	play_begin(&opt, &s.a, &s.clock, s.w, &s.p, &s.afoot, &s.captured, &s.running, nil, true)
	play.ratio = 1
}

// One frame of the screen, 2,560 by 1,440, with the pointer nowhere.
@(private="file")
frame :: proc(s: ^Stage, pointer := [2]f32{-1, -1}) {
	above_update(&s.a, 1.0/60, {}, 0, 0, 0, false)
	s.eye, s.pitch, _ = above_camera(&s.a, 2560.0/1440)
	play_frame(2560, 1440, pointer, 1.0/60, 9.5, 95, s.eye, s.a.yaw, s.pitch, ABOVE_FOV, nil)
}

// Press a part as the pointer does: the left button down and up on its middle.
@(private="file")
click :: proc(s: ^Stage, id: string) -> bool {
	it := screen_find(&screen, id)
	if it == nil do return false
	e: sdl.Event
	e.button.x, e.button.y, e.button.button = it.rect.x + it.rect.w/2, it.rect.y + it.rect.h/2, sdl.BUTTON_LEFT
	e.type = .MOUSE_BUTTON_DOWN
	play_event(&e)
	e.type = .MOUSE_BUTTON_UP
	play_event(&e)
	frame(s)
	return true
}

@(private="file")
key :: proc(s: ^Stage, code: sdl.Scancode) {
	e: sdl.Event
	e.type, e.key.scancode = .KEY_DOWN, code
	play_event(&e)
	frame(s)
}

@(private="file")
says :: proc(id: string) -> string {
	it := screen_find(&screen, id)
	return it.text if it != nil else ""
}

the_play_screen_says_what_is_so :: proc(t: ^testing.T) {
	s := new(Stage)
	stage_make(s)
	frame(s)

	// Text is read at arm's length (I9): the standard scale on 1,440 pixels, and body text of 24 there, set on whole pixels.
	testing.expect_value(t, ui.module, 4)
	testing.expect(t, LOOK.type[.Body].size*f32(ui.module) >= 24, "body text is under 24 pixels at the standard scale")
	for q in ui.quads do if q.uv != WHITE && q.extra.x == 0 && q.extra.y == 0 {
		testing.expect(t, q.rect.x == math.round(q.rect.x) && q.rect.y == math.round(q.rect.y), "a glyph is not set on whole pixels")
	}

	// Top left: the place, the date, and the clock, which a click and its key both work.
	testing.expect(t, says("place.title") != "", "the place has no name")
	testing.expect_value(t, says("place.date"), "16th of spring")
	testing.expect_value(t, says("clock.pause"), "Running at 09:30")
	testing.expect_value(t, screen_find(&screen, "clock.pause").key, "Space")
	testing.expect(t, click(s, "clock.pause") && s.clock.paused, "a click on the clock did not pause it")
	testing.expect_value(t, says("clock.pause"), "Paused at 09:30")
	key(s, .SPACE)
	testing.expect(t, !s.clock.paused, "Space did not let the clock go on")
	click(s, "clock.fastest")
	testing.expect_value(t, s.clock.speed, 2)

	// The pointer is shared by one rule: a panel is the interface's, the land is the world's.
	place := screen_find(&screen, "place").rect
	testing.expect(t, !over_world({(place.x + 8)/2560, (place.y + 8)/1440}), "a point on a panel was taken for the world")
	testing.expect(t, over_world({0.5, 0.5}), "the middle of the picture was not the world's")

	// Right: the ground here, the column's beds named, and the cut marked on it once the world is cut.
	ground := screen_says(&screen, .Ground)
	testing.expect(t, strings.contains(ground, "The ground here") && strings.contains(ground, "Walk here [Tab]"), "the ground's panel is not whole")
	testing.expect(t, screen_find(&screen, "bed") != nil, "the column has no beds")
	testing.expect(t, screen_find(&screen, "ground.mark") == nil, "the cut is marked on a world not cut")
	key(s, .F)
	testing.expect(t, s.a.cut && screen_find(&screen, "ground.mark") != nil, "F did not cut the world and mark the cut")
	level := s.a.level
	click(s, "ground.up")
	testing.expect_value(t, s.a.level, level + 1)

	// The hand: a block of the ground picked up says what it is, why, and the column it lies in.
	top := ground_top(s.a.at.x, s.a.at.z)
	block := [3]i32{i32(math.floor(s.a.at.x)), top - 12, i32(math.floor(s.a.at.z))}
	testing.expect(t, screen_says(&screen, .Hand) == "", "the hand holds something before anything is picked")
	hand_pick({block = block, ok = true, exact = true}, {0.5, 0.5})
	frame(s)
	title := mat_words(block_made(s.w, block))
	testing.expect_value(t, strings.to_lower(says("hand.title"), context.temp_allocator), title)
	testing.expect(t, strings.contains(says("hand.sub"), "11 m under the ground"), "the card does not say where the block lies")
	testing.expect(t, len(says("hand.line")) > 20, "the card does not say why")
	testing.expect(t, screen_find(&screen, "hand.bed") != nil, "a block of ground shows no column")
	testing.expect(t, s.a.marked && s.a.mark[0] == block, "the thing in the hand is not marked in the world")
	testing.expect(t, strings.contains(screen_says(&screen, .Hand), "Put it down [Esc]"), "the hand's way out has no key on it")

	// Messages, and alerts with the call that raises and clears them. An empty region draws nothing.
	testing.expect(t, screen_says(&screen, .Wrong) == "" && screen_says(&screen, .Said) == "", "an empty region says something")
	tell("A boat stands off the shore.")
	alert_raise("drink", "No drink in the store. Three dwarves are thirsty.", .Trouble, s.a.at)
	frame(s)
	testing.expect(t, strings.contains(screen_says(&screen, .Said), "A boat stands off the shore."), "a message was not shown")
	testing.expect(t, strings.contains(screen_says(&screen, .Wrong), "Three dwarves are thirsty"), "an alert was not shown")
	alert_clear("drink")
	frame(s)
	testing.expect(t, screen_says(&screen, .Wrong) == "", "a cleared alert still stands")

	// The Places list: every row goes to its place and takes it in the hand (I4).
	key(s, .F4)
	testing.expect_value(t, says("list.title"), "Places")
	testing.expect(t, screen_find(&screen, "ground") == nil, "the ground's panel stands under the list")
	rows := 0
	for it in screen.items do rows += int(it.id == "list.row")
	testing.expect_value(t, rows, len(home.places))
	testing.expect(t, click(s, "list.row"), "the list has no row to click")
	first := home.candidates[home.places[0].c]
	testing.expect(t, math.hypot(s.a.at.x - first.at.x - f64(home.region.origin.x), s.a.at.z - first.at.y - f64(home.region.origin.y)) < 1, "a row did not take the view to its place")
	testing.expect_value(t, strings.to_lower(says("hand.title"), context.temp_allocator), strings.to_lower(home.places[0].name, context.temp_allocator))
	testing.expect(t, screen_find(&screen, "place.title").text == says("hand.title"), "the view is not at the place the row named")

	// The layout holds at every scale (I9): each panel lies inside the picture, and no two cover each other.
	for list in ([2]List{.Places, .None}) do for module in 3..=8 {
		play.scale, play.list = module, list
		frame(s)
		panels := make([dynamic]Screen_Part, context.temp_allocator)
		for it in screen.items do if it.part == .Panel do append(&panels, it)
		for a, i in panels {
			r := a.rect
			testing.expectf(t, r.x >= 0 && r.y >= 0 && r.x + r.w <= 2560 && r.y + r.h <= 1440, "at %d%% the panel %s leaves the picture", module*25, a.id)
			for b in panels[i + 1:] {
				o := b.rect
				testing.expectf(t, r.x >= o.x + o.w || o.x >= r.x + r.w || r.y >= o.y + o.h || o.y >= r.y + r.h, "at %d%% the panels %s and %s cover each other", module*25, a.id, b.id)
			}
		}
	}
	play.scale, play.list = 0, .Places
	frame(s)

	// Escape closes the topmost thing, and with nothing open it opens the menu (I6).
	key(s, .ESCAPE)
	testing.expect(t, play.list == .None && play.hand.kind == .Place, "Escape did not close the list first")
	key(s, .ESCAPE)
	testing.expect(t, play.hand.kind == .None && !play.menu, "Escape did not empty the hand next")
	key(s, .ESCAPE)
	testing.expect(t, play.menu && says("menu.back") == "Back to the game", "Escape with nothing open did not open the menu")
	testing.expect_value(t, screen_find(&screen, "menu.quit").key, "Q")
	key(s, .ESCAPE)
	testing.expect(t, !play.menu && s.running, "Escape did not close the menu")
}
