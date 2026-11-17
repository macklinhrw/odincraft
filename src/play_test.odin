package main

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

// The play screen is data (docs/adr/0010): a list of parts made from the game as it stands, with
// no window. These tests make it over the default world's start island and ask what it says, press
// its buttons as the pointer and the keys do, and check that it lies inside the picture at every scale.
// Called by the forming test once the start island is formed and bound, as the dwarves' test is.
// The second test puts a hold on the screen, of seven, of thirty-four and of a hundred, as the hold
// shows it (Shown, hold.odin), and asks the same of the dwarves' place at the top, their list, their
// alerts and several of them in the hand (crowd.odin).

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
	testing.expect_value(t, says("place.date"), fmt.tprintf("%s, 16th of spring", isle_name(0)))
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

	// The hand: a block of the ground picked up says what it is in one line, and opens no card (I2);
	// asked for, by its key or a second click, the card says why, with the column it lies in.
	top := ground_top(s.a.at.x, s.a.at.z)
	block := [3]i32{i32(math.floor(s.a.at.x)), top - 12, i32(math.floor(s.a.at.z))}
	testing.expect(t, screen_says(&screen, .Hand) == "", "the hand holds something before anything is picked")
	hand_pick({block = block, ok = true, exact = true}, {0.5, 0.5})
	frame(s)
	title := mat_words(block_made(s.w, block))
	testing.expect_value(t, strings.to_lower(says("hand.title"), context.temp_allocator), title)
	testing.expect(t, strings.contains(says("hand.sub"), "11 m under the ground"), "the line does not say where the block lies")
	testing.expect(t, screen_find(&screen, "hand.line") == nil && screen_find(&screen, "hand.bed") == nil, "a click opened the card unasked")
	testing.expect(t, strings.contains(screen_says(&screen, .Hand), "More [I]"), "the line has no way to its card")
	shut := screen_find(&screen, "hand").rect
	testing.expectf(t, shut.h <= 48, "the hand shut is %v pixels high: more than a line", shut.h)
	key(s, .I)
	testing.expect(t, play.card_open && len(says("hand.line")) > 20, "the card asked for does not say why")
	hand_pick({block = block + {1, 0, 0}, ok = true, exact = true}, {0.5, 0.5})
	frame(s)
	testing.expect(t, !play.card_open && screen_find(&screen, "hand.line") == nil, "a click on other ground left the card open")
	hand_pick({block = block + {1, 0, 0}, ok = true, exact = true}, {0.5, 0.5})
	frame(s)
	testing.expect(t, play.card_open, "a second click on the thing in the hand did not open its card")
	hand_pick({block = block, ok = true, exact = true}, {0.5, 0.5})
	key(s, .I)
	testing.expect(t, play.card_open && len(says("hand.line")) > 20, "the card asked for does not say why")
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

	// The orders bar (plan.md, P3; bar.odin): each order a button with its key on it. Taking one puts
	// its tool in the hand, with its choices, what the land says of the ground and, while a box is
	// dragged, the mark's size in words. Escape puts it down.
	orders := screen_says(&screen, .Orders)
	for name in ([6]string{"Dig [D]", "Fell [T]", "Build [B]", "Store [S]", "Send [M]", "Remove [X]"}) do testing.expectf(t, strings.contains(orders, name), "the orders bar lacks %s", name)
	key(s, .D)
	testing.expect_value(t, says("tool.title"), "Dig")
	testing.expect(t, bar.tool == .Dig && play.hand.kind == .None && .Held in screen_find(&screen, "orders.dig").state, "D did not put the digging tool in the hand")
	testing.expect(t, strings.contains(screen_says(&screen, .Hand), "Dig out") && strings.contains(screen_says(&screen, .Hand), "Stair down") && strings.contains(screen_says(&screen, .Hand), "Deep"), "the digging tool does not show its choices")
	card := screen_find(&screen, "hand").rect
	s.a.mark, s.a.marked, s.a.marking = {block, block + {4, 0, 6}}, true, true
	bar.dragged = true
	frame(s)
	testing.expect(t, strings.has_prefix(says("tool.says"), "5 by 7, 2 deep: ") && strings.contains(says("tool.says"), "With the way in"), says("tool.says"))   // twelve blocks under the ground: a stair is found for it
	s.a.mark = {block + {0, 8, 0}, block + {4, 8, 6}}
	frame(s)
	testing.expect(t, strings.has_prefix(says("tool.says"), "5 by 7, 2 deep: ") && strings.contains(says("tool.says"), "With the way in"), says("tool.says"))   // four under it: the order digs its own way in
	s.a.mark = {block, block + {4, 0, 6}}
	frame(s)
	testing.expect(t, screen_find(&screen, "hand").rect == card, "the tool's card moved when its line changed")
	play_act(.Deep, 3)
	frame(s)
	testing.expect(t, strings.has_prefix(says("tool.says"), "5 by 7, 3 deep: "), says("tool.says"))
	play_act(.Plan, int(Plan.Down))
	frame(s)
	testing.expect(t, strings.has_prefix(says("tool.says"), "7 steps down, heading south"), says("tool.says"))
	testing.expect(t, screen_find(&screen, "hand").rect == card, "the tool's card moved when its choice changed")
	play_act(.Plan, int(Plan.Out))
	play_act(.Deep, 2)
	s.a.marking, s.a.marked = false, false
	testing.expect(t, click(s, "orders.build") && bar.tool == .Build, "a click on Build did not take the tool")
	testing.expect(t, strings.contains(screen_says(&screen, .Hand), "Stone 0") && strings.contains(screen_says(&screen, .Hand), "Timber 0"), "building does not say what is in store")
	for module in 3..=8 {   // the tallest card, at every scale
		play.scale = module
		frame(s)
		for it in screen.items do if it.part == .Panel {
			r := it.rect
			testing.expectf(t, r.x >= 0 && r.y >= 0 && r.x + r.w <= 2560 && r.y + r.h <= 1440, "at %d%% the panel %s leaves the picture with a tool held", module*25, it.id)
		}
	}
	play.scale = 0
	key(s, .ESCAPE)
	testing.expect(t, bar.tool == .None && !play.menu, "Escape did not put the tool down")
	hand_pick({block = block, ok = true, exact = true}, {0.5, 0.5})
	frame(s)

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

// Press the part with an id that says these words.
@(private="file")
click_words :: proc(s: ^Stage, id, words: string) -> bool {
	for &it in screen.items do if it.id == id && it.text == words {
		was := it.id
		it.id = "the one"
		ok := click(s, "the one")
		if found := screen_find(&screen, "the one"); found != nil do found.id = was
		return ok
	}
	return false
}

@(private="file")
count :: proc(id: string) -> (n: int) {
	for it in screen.items do n += int(it.id == id)
	return
}

// A hold of so many as the hold would show it, standing in rows by the start and waiting for word.
@(private="file")
hold_shown :: proc(s: ^Stage, n: int) {
	party: [dynamic]Facts
	party_draw(world_seed, n, &party)
	clear(&watch.seen.dwarves)
	for f, i in party {
		at := s.a.at + {f64(i%10)*2 - 9, 0, f64(i/10)*2 + 4}
		append(&watch.seen.dwarves, Seen{who = f, was = at, at = at, doing = .Waiting})
	}
	watch.seen.place = "ground above the landing"
	play.greeted, play.alerted = false, {}
	clear(&play.kept)
	hand_take({})
}

@(private="file")
plight :: proc(i: int, p: Plight) {
	d := &watch.seen.dwarves[i]
	d.plight, d.doing = p, .Stopped if p != .None else .Waiting
}

the_dwarves_are_on_screen :: proc(t: ^testing.T) {
	s := new(Stage)
	stage_make(s)
	hold_shown(s, 7)
	frame(s)
	seen := &watch.seen

	// Top middle: the seven of the first boat are kept in view from the start, then the count of all. No alert stands.
	testing.expect_value(t, count("crowd.kept"), 7)
	testing.expect_value(t, says("crowd.count"), "7")
	testing.expect(t, screen_says(&screen, .Wrong) == "", "an alert stands over a hold where nothing is wrong")
	first := seen.dwarves[0].who
	name := fmt.aprintf("%s %s", first.given, first.byname)
	testing.expect_value(t, says("crowd.kept"), fmt.tprintf("%s, %s", name, TRADES[first.trade].name))

	// A click on a picture takes the dwarf in the hand; a second takes the view to it; Enter follows it.
	click(s, "crowd.kept")
	testing.expect(t, play.hand.kind == .Dwarf && play.hand.dwarf == 0 && hold_selected() == 0, "a click on a picture did not take the dwarf in the hand")
	testing.expect_value(t, says("hand.title"), name)
	testing.expect_value(t, says("hand.sub"), fmt.tprintf("%s, %s", TRADES[first.trade].name, number_words(first.age)))
	testing.expect(t, strings.contains(says("hand.line"), "Standing on the ground above the landing"), "the card does not say what the dwarf is doing")
	testing.expect(t, !strings.contains(screen_says(&screen, .Hand), "Self") && strings.contains(screen_says(&screen, .Hand), "More [I]"), "a dwarf's short card shows its tabs unasked")
	key(s, .I)
	testing.expect(t, strings.contains(screen_says(&screen, .Hand), "* Trade") && strings.contains(screen_says(&screen, .Hand), "Self"), "the card has not the tabs for what exists")
	key(s, .I)
	testing.expect(t, screen_find(&screen, "hand.need") == nil, "a dwarf that needs nothing says it needs something")
	testing.expect(t, math.hypot(s.a.at.x - seen.dwarves[0].at.x, s.a.at.z - seen.dwarves[0].at.z) > 1, "the view was at the dwarf before it was sent there")
	click(s, "crowd.kept")
	testing.expect(t, math.hypot(s.a.at.x - seen.dwarves[0].at.x, s.a.at.z - seen.dwarves[0].at.z) < 0.01, "a second click did not take the view to the dwarf")
	key(s, .RETURN)
	testing.expect(t, play.following, "Enter did not follow the dwarf in the hand")

	// Keep in view: K lets the dwarf in the hand go from the top, and K again keeps it, last.
	testing.expect_value(t, screen_find(&screen, "hand.keep").key, "K")
	key(s, .K)
	testing.expect_value(t, count("crowd.kept"), 6)
	key(s, .K)
	testing.expect(t, count("crowd.kept") == 7 && play.kept[6] == 0, "K did not keep the dwarf in view again")

	// Who needs you comes first, worst first, each with a sign; and an alert counts them (I14).
	plight(1, .No_Way)
	plight(3, .Shut_In)
	plight(5, .Shut_In)
	frame(s)
	testing.expect(t, slice.equal(play.needing[:], []int{3, 5, 1}), "those who need the player are not listed worst first")
	testing.expect(t, count("crowd.need") == 3 && count("crowd.kept") == 4, "the top does not show those who need the player, then those kept")
	testing.expect(t, strings.has_suffix(says("crowd.need"), ": shut in"), "the worst off is not first at the top")
	signs := 0
	for it in screen.items do signs += int(it.area == .Dwarves && it.part == .Sign && it.colour.a == 0)
	testing.expect_value(t, signs, 3)
	wrong := screen_says(&screen, .Wrong)
	testing.expect(t, strings.contains(wrong, "Two dwarves are shut in: no way leads out of where they stand."), "two shut in are not one alert that counts them")
	testing.expect(t, strings.contains(wrong, fmt.tprintf("%s %s is stopped: it found no way to where it was sent.", seen.dwarves[1].who.given, seen.dwarves[1].who.byname)), "one with no way is not named by its alert")
	testing.expect_value(t, count("wrong.row"), 2)
	click(s, "wrong.row")   // it opens those two
	testing.expect(t, play.hand.kind == .Dwarves && slice.equal(play.several[:], []int{3, 5}), "the alert did not take the two it counts in the hand")
	testing.expect_value(t, says("hand.title"), "Two dwarves")
	testing.expect(t, strings.contains(says("hand.next"), "Need you: two shut in."), "the group does not say what its dwarves share")
	middle := (seen.dwarves[3].at + seen.dwarves[5].at)/2
	testing.expect(t, math.hypot(s.a.at.x - middle.x, s.a.at.z - middle.z) < 0.01, "the alert did not take the view to its dwarves")
	click(s, "hand.dwarf")   // a picture in the group takes that one alone
	testing.expect(t, play.hand.kind == .Dwarf && play.hand.dwarf == 3 && says("hand.need") == "shut in", "a picture in the group did not take that dwarf alone, with what it needs")
	for i in ([3]int{1, 3, 5}) do plight(i, .None)
	frame(s)
	testing.expect(t, screen_says(&screen, .Wrong) == "" && count("crowd.need") == 0, "an alert stands when nothing is wrong any more")

	// Several in the hand: with Shift a click adds a dwarf, or takes it out; a box dragged over dwarves takes them.
	play.adding = true
	click_words(s, "crowd.kept", fmt.tprintf("%s %s, %s", seen.dwarves[1].who.given, seen.dwarves[1].who.byname, TRADES[seen.dwarves[1].who.trade].name))
	click_words(s, "crowd.kept", fmt.tprintf("%s %s, %s", seen.dwarves[4].who.given, seen.dwarves[4].who.byname, TRADES[seen.dwarves[4].who.trade].name))
	testing.expect(t, slice.equal(play.several[:], []int{1, 3, 4}) && says("hand.title") == "Three dwarves", "Shift and a click did not add to the hand")
	testing.expect_value(t, count("hand.dwarf"), 3)
	click(s, "hand.dwarf")
	testing.expect(t, slice.equal(play.several[:], []int{3, 4}), "Shift and a click on one in the hand did not take it out")
	play.adding = false
	floor :: proc(p: [3]f64) -> [3]i32 { return {i32(math.floor(p.x)), i32(math.floor(p.y)), i32(math.floor(p.z))} }
	s.a.mark, s.a.marking, s.a.marked = {floor(seen.dwarves[0].at) - {0, 1, 0}, floor(seen.dwarves[2].at) - {0, 1, 0}}, true, true
	play.owner = .World
	up: sdl.Event
	up.type, up.button.button, up.button.x, up.button.y = .MOUSE_BUTTON_UP, sdl.BUTTON_LEFT, 1280, 720
	play_event(&up)
	frame(s)
	testing.expect(t, play.hand.kind == .Dwarves && slice.equal(play.several[:], []int{0, 1, 2}), "a box dragged over three dwarves did not take them in the hand")
	testing.expect(t, !s.a.marked, "the box is still marked once its dwarves are in the hand")
	key(s, .ESCAPE)
	testing.expect(t, play.hand.kind == .None, "Escape did not put the dwarves down")

	// A message about a dwarf leads to where it happened, with the dwarf in the hand (I4).
	there := seen.dwarves[6].at + {30, 0, 0}
	tell("Someone is there.", there, 6)
	frame(s)
	testing.expect(t, click(s, "said") && play.hand.kind == .Dwarf && play.hand.dwarf == 6, "a message about a dwarf did not take it in the hand")
	testing.expect(t, math.hypot(s.a.at.x - there.x, s.a.at.z - there.z) < 0.01, "a message did not lead to its place")

	// The Dwarves list: a row each; it groups by need, by trade or by place, and finds by name, trade or place.
	key(s, .F1)
	testing.expect_value(t, says("list.title"), "Dwarves")
	testing.expect(t, count("list.row") == 7 && says("list.group.name") == "Waiting for word", "the list has not a row for each dwarf, grouped by need")
	testing.expect(t, strings.has_prefix(says("list.row.doing"), "Waiting for word at"), "a row does not say what its dwarf is doing")
	testing.expect_value(t, says("list.row.how"), "well")
	click(s, "list.row")   // every row takes the view to its dwarf and puts it in the hand
	testing.expect(t, play.hand.kind == .Dwarf && play.hand.dwarf == 0 && math.hypot(s.a.at.x - seen.dwarves[0].at.x, s.a.at.z - seen.dwarves[0].at.z) < 0.01, "a row did not lead to its dwarf")
	click(s, "list.keep")
	testing.expect(t, !slice.contains(play.kept[:], 0) && says("list.keep") == "Keep", "a row's Keep did not let its dwarf go from the top")
	click(s, "list.keep")
	plight(2, .No_Way)
	frame(s)
	testing.expect(t, says("list.group.name") == "Need you" && says("list.row.how") == "no way", "one that needs the player does not head the list")
	plight(2, .None)

	// A hold of thirty-four: a long group folds to its count, and the list finds.
	hold_shown(s, 34)
	frame(s)
	testing.expect_value(t, says("crowd.count"), "34")
	testing.expect(t, count("list.row") == FOLD_SHOW && says("list.more.count") == "Twenty-nine more", "a long group does not fold to its count")
	click(s, "list.more")
	testing.expect(t, count("list.row") > FOLD_SHOW && play.list_over > 0, "a folded group did not open")
	click(s, "list.group")
	testing.expect(t, count("list.row") == 0 && count("list.group") == 1, "a group's head did not fold it away")
	click_words(s, "list.sort", "By trade")
	trades: bit_set[0..<32]
	miners := 0
	for d in seen.dwarves {
		trades += {d.who.trade}
		miners += int(TRADES[d.who.trade].name == "miner")
	}
	play.list_scroll = 1e6   // to the list's foot, where the last group's head is
	frame(s)
	groups := 0
	for it in screen.items do if it.id == "list.group" && it.rect.y < 1e5 do groups += 1
	testing.expect_value(t, groups, card(trades))
	append(&play.find, "miner")
	play.list_scroll = 0
	frame(s)
	testing.expect(t, count("list.row") == miners && miners > 0, "the list did not find by trade")
	for it in screen.items do if it.id == "list.row.trade" do testing.expect_value(t, it.text, ", miner")
	clear(&play.find)
	append(&play.find, strings.to_lower(seen.dwarves[20].who.byname, context.temp_allocator))
	frame(s)
	testing.expect(t, count("list.row") >= 1 && strings.contains(screen_says(&screen, .List), seen.dwarves[20].who.byname), "the list did not find by name")
	clear(&play.find)
	click_words(s, "list.sort", "By place")
	_, place := dwarf_place(20)
	testing.expect_value(t, says("list.group.name"), place)
	append(&play.find, strings.to_lower(place[5:], context.temp_allocator))
	frame(s)
	testing.expect(t, count("list.row") > 0, "the list did not find by place")
	clear(&play.find)
	click(s, "list.only")
	testing.expect_value(t, count("list.row"), len(play.kept))
	click(s, "list.only")
	play.adding = true   // with Shift, rows are added to the hand, and the view stays
	at := s.a.at
	for who in 0..<3 do for &it in screen.items do if it.id == "list.row" && it.arg == who {
		it.id = "the row"
		click(s, "the row")
		break
	}
	play.adding = false
	testing.expect(t, play.hand.kind == .Dwarves && len(play.several) == 3 && s.a.at == at, "Shift and a click on three rows did not put the three in the hand")
	key(s, .F1)
	testing.expect(t, play.list == .None, "F1 did not shut the list")

	// It holds at seven, thirty-four and a hundred, with many in need, at every scale, the list open or
	// shut: every panel lies inside the picture, no two cover each other, and the top is never wider
	// for a larger hold.
	full := f32(0)   // how wide the top is with every place taken
	for n in ([3]int{7, 34, 100}) {
		hold_shown(s, n)
		for i in 0..<n do if i%5 == 1 do plight(i, .Shut_In if i%2 == 0 else .No_Way)
		for i in 7..<min(n, 30) do keep(i)
		for list in ([2]List{.None, .Dwarves}) do for module in 3..=8 {
			play.scale, play.list = module, list
			frame(s)
			panels := make([dynamic]Screen_Part, context.temp_allocator)
			for it in screen.items do if it.part == .Panel do append(&panels, it)
			for a, i in panels {
				r := a.rect
				testing.expectf(t, r.x >= 0 && r.y >= 0 && r.x + r.w <= 2560 && r.y + r.h <= 1440, "with %d dwarves at %d%% the panel %s leaves the picture", n, module*25, a.id)
				for b in panels[i + 1:] {
					o := b.rect
					testing.expectf(t, r.x >= o.x + o.w || o.x >= r.x + r.w || r.y >= o.y + o.h || o.y >= r.y + r.h, "with %d dwarves at %d%% the panels %s and %s cover each other", n, module*25, a.id, b.id)
				}
			}
			testing.expectf(t, count("crowd.need") + count("crowd.kept") + count("crowd.more") <= LOOK.crowd, "with %d dwarves at %d%% the top shows more pictures than it has places", n, module*25)
			if module == 4 {
				crowd := screen_find(&screen, "crowd")
				if testing.expectf(t, crowd != nil, "with %d dwarves the top has no place for them at the standard scale", n) && list == .None {
					if n == 34 do full = crowd.rect.w
					if n == 100 do testing.expect(t, crowd.rect.w <= full + text_wide(.Figure, "0") + 1, "the top is wider with a hundred dwarves than with thirty-four, by more than the count's own figure")
				}
				testing.expect_value(t, says("crowd.count"), fmt.tprint(n))
				if n > 7 && list == .None do testing.expect(t, count("crowd.more") > 0, "a crowd in need is not counted where it has no room")
			}
		}
	}
	play.scale, play.list = 0, .None
}
