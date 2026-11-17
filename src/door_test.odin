package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

// The screens before play are data, as the play screen is (docs/adr/0010): each a list of parts made
// with no window. This test stands at the front door over the world the forming test made, moves
// its focus by key and by pointer, goes through Worlds, a new world and settings, opens the world's
// screen, takes an island in the hand, puts a lens on, and asks for the doors into play; plans an
// expedition (plan.odin): reads the landing offered, chooses others by key, by a click on the shore and
// not on a cliff, draws the party and one dwarf again, and checks that a hold made with what was
// chosen lands there with that party and says so in a log that plays again; and checks that every
// screen lies inside the picture at every scale. It makes no world and enters no game:
// those need the GPU, and are run with no window by `--door ... --press=`, as AGENTS.md says.
// Called by the forming test once the start island and island 1 are formed.

@(private="file")
frame :: proc(pointer := [2]f32{-1, -1}) { door_frame(2560, 1440, pointer, 1.0/60) }

@(private="file")
key :: proc(code: sdl.Scancode) {
	e: sdl.Event
	e.type, e.key.scancode = .KEY_DOWN, code
	door_event(&e)
	frame()
}

@(private="file")
click :: proc(id: string, words := "") -> bool {
	for it in screen.items do if it.id == id && (words == "" || it.text == words) {
		e: sdl.Event
		e.button.x, e.button.y, e.button.button = it.rect.x + it.rect.w/2, it.rect.y + it.rect.h/2, sdl.BUTTON_LEFT
		e.type = .MOUSE_BUTTON_DOWN
		door_event(&e)
		e.type = .MOUSE_BUTTON_UP
		door_event(&e)
		frame()
		return true
	}
	return false
}

// Frames until the map has come to where it is going.
@(private="file")
settle :: proc() {
	for _ in 0..<200 do if chart.going do frame()
}

// What the card's row of a thing says, and its why.
@(private="file")
row_says :: proc(thing: string) -> (says, why: string) {
	for it, i in screen.items do if it.id == "isle.thing" && it.text == thing {
		for o in screen.items[i + 1:] do if o.id == "isle.says" do return o.text, screen.items[i - 1].tip if screen.items[i - 1].id == "isle.row" else ""
	}
	return
}

@(private="file")
says :: proc(id: string) -> string {
	it := screen_find(&screen, id)
	return it.text if it != nil else ""
}

@(private="file")
count :: proc(id: string) -> (n: int) {
	for it in screen.items do n += int(it.id == id)
	return
}

// Every panel lies inside the picture, and no two cover each other.
@(private="file")
laid_out :: proc(t: ^testing.T, what: string) {
	panels := make([dynamic]Screen_Part, context.temp_allocator)
	for it in screen.items do if it.part == .Panel do append(&panels, it)
	for a, i in panels {
		r := a.rect
		testing.expectf(t, r.x >= 0 && r.y >= 0 && r.x + r.w <= 2560 && r.y + r.h <= 1440, "%s at %d%%: the panel %s leaves the picture", what, ui.module*25, a.id)
		for b in panels[i + 1:] {
			o := b.rect
			testing.expectf(t, r.x >= o.x + o.w || o.x >= r.x + r.w || r.y >= o.y + o.h || o.y >= r.y + r.h, "%s at %d%%: the panels %s and %s cover each other", what, ui.module*25, a.id, b.id)
		}
	}
}

// Expedition planning, come to with the start island in the hand (plan.odin).
@(private="file")
an_expedition_is_planned :: proc(t: ^testing.T) {
	p := &planning
	settle()
	names :: proc(party: []Facts) -> string {
		b := strings.builder_make(context.temp_allocator)
		for f in party do fmt.sbprintf(&b, "%s %s, %s %d; ", f.given, f.byname, TRADES[f.trade].name, f.age)
		return strings.to_string(b)
	}
	shown :: proc() -> string {   // the party as the screen's rows say it
		b := strings.builder_make(context.temp_allocator)
		for it, i in screen.items do if it.id == "who.name" do fmt.sbprintf(&b, "%s, %s; ", it.text, screen.items[i + 1].text)
		return strings.to_string(b)
	}
	at :: proc(cell: int) -> [2]f32 {   // where a cell of the island's shore stands in the picture
		for sc in planning.shore do if int(sc.cell) == cell {
			o := archipelago[planning.isle].origin
			return chart_to({f64(o.x) + f64(sc.at.x), f64(o.y) + f64(sc.at.y)})
		}
		return {-1, -1}
	}
	press :: proc(where_: [2]f32) {
		frame(where_)
		e: sdl.Event
		e.button.x, e.button.y, e.button.button = where_.x, where_.y, sdl.BUTTON_LEFT
		for type in ([2]sdl.EventType{.MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP}) {
			e.type = type
			door_event(&e)
		}
		frame()
	}

	// It opens with the landing the hold would choose in the hand, and the seed's party drawn: Enter alone is the game as it was.
	testing.expect_value(t, says("plan.title"), fmt.tprintf("An expedition to %s", isle_name(0)))
	testing.expect_value(t, says("expedition.title"), "The expedition")
	own := new(Hold)
	own.quiet = true
	hold_make(own, home, "")
	testing.expect(t, len(p.offered) >= 1 && p.choice == 0 && p.landed.cell == own.landed.cell && p.landed.at == own.landed.at, "the landing offered first is not the one the hold chooses")
	testing.expect(t, !p.set.lands && p.set.draws == 0 && len(p.set.again) == 0, "an expedition with nothing chosen asks the hold for something")
	testing.expect_value(t, count("landing.row"), len(p.offered))
	testing.expect(t, strings.contains(says("site.tag"), "the game's own"), "the card does not say the landing in the hand is the game's own")
	testing.expect_value(t, says("site.sub"), capital(LANDINGS[own.landed.row].name))
	testing.expect_value(t, count("who.row"), LANDING)
	testing.expect_value(t, names(p.party[:]), names(own.party[:]))
	testing.expect(t, strings.contains(shown(), own.party[0].given) && strings.contains(shown(), TRADES[own.party[LANDING - 1].trade].name), "the party's rows do not say who is in the boat")
	// The place's card is rows, and so is everything beside it: no sentence, the why on asking.
	for thing in ([7]string{"Shelter", "Fresh water", "Ground to live on", "Slope", "Timber", "Rock", "Under it"}) {
		found := false
		for it in screen.items do found ||= it.id == "site.thing" && it.text == thing
		testing.expectf(t, found, "the place's card has no row for %s", thing)
	}
	short :: proc(t: ^testing.T) {
		for it in screen.items do if it.id == "site.says" || it.id == "site.thing" || it.id == "landing.says" || it.id == "work.says" || it.id == "caution" || it.id == "who.trade" {
			testing.expectf(t, len(it.text) <= 46 && !strings.contains(it.text, ". "), "planning answers in a sentence: %q (%s)", it.text, it.id)
		}
	}
	short(t)
	testing.expect(t, count("site.bed") >= 1, "the place's card does not show the ground's beds")
	testing.expect_value(t, count("work.thing"), len(WORKS))
	testing.expect(t, screen_find(&screen, "plan.go").key == "Enter" && screen_find(&screen, "plan.back").key == "Esc" && screen_find(&screen, "who.again").key == "D" && screen_find(&screen, "who.all").key == "A", "the planning screen's buttons have not their keys")
	testing.expect_value(t, count("site.why"), 0)
	click("site.thing", "Shelter")
	testing.expect(t, strings.contains(says("site.why"), "sea round"), "a row of the place's card clicked does not say its why, with its figures")
	click("site.thing", "Shelter")

	// What the land may do is named where the world knows it: the shore below a lake a slide dammed.
	bound(home)
	for f, i in region.features do if f.kind == .Lake && f.cause >= 0 && region.features[f.cause].kind == .Slide {
		least, below := f32(FAR), -1
		for sc in p.shore do if d, lake := dam_below(int(sc.cell)); lake == i && d < least do least, below = d, int(sc.cell)
		if testing.expectf(t, least <= 200, "no shore lies below the slide's lake: the nearest is %.0f m from its stream", least) {
			rows := make([dynamic]Card_Row, context.temp_allocator)
			site_write(&rows, below)
			named := false
			for r in rows do named ||= r.thing == "Slide's lake" && r.sign == .Trouble && r.named == "A slide's lake above"
			testing.expect(t, named, "the shore below a slide's lake does not name it as a danger")
			m := middle_of(land.grid, below)
			fmt.printfln("the shore below the slide's lake: at %.0f, %.0f from the island's middle, %.0f m from its stream", m.x, m.y, least)
		}
	}

	// The party drawn again, and one dwarf of it: each a function of the seed and the draws.
	before := names(p.party[:])
	key(.A)
	again := make([dynamic]Facts, context.temp_allocator)
	party_draw(world_seed, LANDING, &again, 1)
	testing.expect(t, p.set.draws == 1 && names(p.party[:]) != before && names(p.party[:]) == names(again[:]), "A did not draw the seed's next party")
	key(.DOWN)
	second := fmt.tprintf("%s %s", p.party[1].given, p.party[1].byname)
	key(.D)
	party_draw(world_seed, LANDING, &again, 1, {1})
	testing.expect(t, p.focus == 1 && len(p.set.again) == 1 && fmt.tprintf("%s %s", p.party[1].given, p.party[1].byname) != second && names(p.party[:]) == names(again[:]), "D did not draw the dwarf in focus again, and no other")
	for f, i in p.party do for o in p.party[:i] do testing.expectf(t, f.given != o.given && f.trade != o.trade, "two of the party share a name or a trade: %s and %s", f.given, o.given)
	testing.expect(t, strings.contains(says("who.again"), p.party[1].given), "the button does not name the dwarf it draws again")
	click("who.bust")
	testing.expect_value(t, p.focus, 0)

	// A landing offered, by its number; a hold made with what is chosen lands there, with that party.
	if len(p.offered) > 1 {
		key(._2)
		testing.expect(t, p.choice == 1 && p.set.lands, "2 did not choose the second landing offered")
		made := new(Hold)
		made.quiet = true
		hold_make(made, home, "", LANDING, &p.set)
		testing.expect(t, made.found && made.landed.cell == p.landed.cell && made.landed.at == p.landed.at && made.landed.camp == p.landed.camp, "the hold does not land where the screen says the boat comes in")
		testing.expect_value(t, names(made.party[:]), names(p.party[:]))
		// What it set out with is said in its log, in the form an orders file takes: played again from those lines it is the same game.
		hold_run(made, 40)
		lines := strings.builder_make(context.temp_allocator)
		for line in made.log do if i := strings.index(line, `The hold says "`); i >= 0 {
			rest := line[i + len(`The hold says "`):]
			fmt.sbprintfln(&lines, "0 %s", rest[:strings.index(rest, `"`)])
		}
		testing.expect(t, strings.contains(strings.to_string(lines), "0 land ") && strings.contains(strings.to_string(lines), "0 party 1 2"), "the hold's log does not say what the expedition set out with")
		path := "build/plan_test_orders.txt"
		testing.expect(t, os.write_entire_file(path, transmute([]u8)strings.to_string(lines)) == nil, "the orders file is written")
		replayed := new(Hold)
		replayed.quiet = true
		hold_make(replayed, home, path)
		hold_run(replayed, 40)
		testing.expect(t, replayed.landed.at == made.landed.at && log_hash(replayed) == log_hash(made) && len(made.log) > 5, "an expedition's log played again is not the same game")
		fmt.printfln("the expedition: landed at %v with the party drawn again once and one dwarf again; its log %x as planned and %x played again from its own lines", made.landed.at, log_hash(made), log_hash(replayed))
		key(._1)
		testing.expect(t, p.choice == 0 && !p.set.lands, "1 did not go back to the game's own landing")
	}

	// The pointer on the shore: the place under it is read without a click, and a click chooses it, however bad it is.
	open, cliff := -1, -1
	reach := f64(px(7))*chart.span/f64(chart.wide) + 4*LAND_CELL
	for sc in p.shore {
		far, low := true, f64(1e9)
		for o in p.offered do far &&= at(o) != at(int(sc.cell)) && abs(at(o).x - at(int(sc.cell)).x) + abs(at(o).y - at(int(sc.cell)).y) > 60
		for o in p.shore do if o.row >= 0 do low = min(low, f64(abs(o.at.x - sc.at.x) + abs(o.at.y - sc.at.y)))
		if sc.row == i8(len(LANDINGS) - 1) && far && open < 0 && inside(chart.free, at(int(sc.cell))) do open = int(sc.cell)
		if sc.row < 0 && low > 2*reach && cliff < 0 && inside(chart.free, at(int(sc.cell))) do cliff = int(sc.cell)
	}
	if testing.expect(t, open >= 0, "the start island has no open shore to choose") {
		frame(at(open))
		testing.expect(t, says("site.tag") == "Under the pointer" && p.under == open, "the place under the pointer is not on the card")
		testing.expect(t, says("site.sub") == "An open shore", "an open shore under the pointer is not said to be one")
		was := p.landed.cell
		frame({1280, 12})
		testing.expect(t, strings.contains(says("site.tag"), "The landing chosen") && p.landed.cell == was, "the card does not go back to the place chosen when the pointer leaves the shore")
		press(at(open))
		frame({1280, 12})
		testing.expect(t, p.choice == -1 && p.set.lands && p.landed.cell != was && p.landed.row == len(LANDINGS) - 1, "a click on an open shore did not choose it")
		testing.expect(t, count("caution") >= 1 && count("landing.row") == len(p.offered) + 1, "a bad place chosen does not stand among the landings with its cautions named")
		hard := new(Hold)
		hard.quiet = true
		hold_make(hard, home, "", LANDING, &p.set)
		testing.expect(t, hard.found && hard.landed.at == p.landed.at, "the hold does not land on the open shore that was chosen")
		short(t)
	}
	if cliff >= 0 {   // a shore that stands too high takes no boat, says so, and is not chosen
		was := p.landed.cell
		frame(at(cliff))
		testing.expect(t, p.under == -1 && strings.contains(says("tip"), "No boat can be drawn up here"), "the pointer on a cliff does not say that no boat can be drawn up")
		press(at(cliff))
		testing.expect(t, p.landed.cell == was, "a click on a cliff chose a landing")
	}
	frame({1280, 12})

	// Set out waits for the island's neighbours, and says so; then it is the one thing to do.
	testing.expect(t, strings.contains(says("plan.waits"), "still to be formed") && .Faint in screen_find(&screen, "plan.go").state, "planning does not say why the party cannot set out yet")
	key(.RETURN)
	testing.expect(t, door.wish == .None, "the party set out before the island could be entered")
	making.near_km = 10   // as if its neighbours were formed
	frame()
	testing.expect(t, says("plan.waits") == "" && .Main in screen_find(&screen, "plan.go").state, "Set out is not the main thing to do once it can be done")
	key(.RETURN)
	testing.expect(t, door.wish == .Hold && door.isle == 0 && door.planned, "Enter did not set out with the expedition planned")
	door.wish, door.planned = .None, false
	making.near_km = 64

	// It holds at every size, with more dwarves than the boat's seven too.
	for module in 3..=8 {
		play.scale = module
		frame()
		laid_out(t, "planning")
		panel := screen_find(&screen, "expedition").rect
		for it in screen.items do if it.area == .List && it.clip.w == 0 && it.part != .Tip {
			testing.expectf(t, it.rect.y + it.rect.h <= panel.y + panel.h + 1 && it.rect.x + it.rect.w <= panel.x + panel.w + 1, "planning at %d%%: %s %q leaves the expedition's panel", module*25, it.id, it.text)
		}
		for a, i in screen.items do if a.id == "plan.go" || a.id == "who.again" || a.id == "landing.row" || a.id == "caution.row" || a.id == "work.row" || a.id == "who.box" {
			for b in screen.items[i + 1:] do if (b.id == "plan.go" || b.id == "who.again" || b.id == "landing.row" || b.id == "caution.row" || b.id == "work.row" || b.id == "who.box") && b.id != a.id {
				testing.expectf(t, a.rect.y >= b.rect.y + b.rect.h || b.rect.y >= a.rect.y + a.rect.h, "planning at %d%%: %s lies on %s", module*25, a.id, b.id)
			}
		}
	}
	play.scale = 0
	frame()

	// Escape goes back with the island in the hand; in again, what was chosen is as it was left.
	chosen, drawn := p.landed.cell, names(p.party[:])
	key(.ESCAPE)
	testing.expect_value(t, door.screen, Before.Chart)
	key(.RETURN)
	testing.expect(t, door.screen == .Plan && p.landed.cell == chosen && p.choice == -1 && names(p.party[:]) == drawn && p.set.draws == 1, "what was planned was not kept when the player went back and came in again")
	key(.ESCAPE)
}

the_front_door_and_the_world :: proc(t: ^testing.T) {
	// A run begins at the front door unless an option names where to go.
	plain, over, seeded, shot, asked := Options{}, Options{has_over = true}, Options{has_seed = true}, Options{shot = "x.png"}, Options{shot = "x.png", has_door = true}
	testing.expect(t, door_first(&plain) && door_first(&seeded), "a run with no option that names where to go does not begin at the front door")
	testing.expect(t, !door_first(&over) && !door_first(&shot), "a run that names where to go begins at the front door")
	testing.expect(t, door_first(&asked), "--door with a picture does not draw the front door")

	opt := Options{near = 64}
	door = {rebind = -1, opt = &opt, unseen = true, running = true, ratio = 1}
	play = {lens = -1, lens_shown = -1, open = {0}}
	chart_forget()
	names_make()
	lands_make()   // the large lands' records, as the world's records are made with them (world_records)
	world_adopt(0, 64)   // the world the forming test made is the world in hand

	// Every island has a name of its own, of two words, and no two share one.
	for is, i in archipelago {
		testing.expectf(t, strings.count(isle_name(i), " ") == 1, "island %d is named %q, not by a cause and its kind", is.id, isle_name(i))
		for _, j in archipelago[:i] do testing.expectf(t, isle_name(i) != isle_name(j), "islands %d and %d are both named %s", j, i, isle_name(i))
	}
	// Every key that is a row has words for what it does, so Settings names none by its act's name.
	for b in BINDS do testing.expectf(t, key_says(b) != fmt.tprint(b.act), "the key %s has no words for what it does", b.name)
	screen_go(.Door)
	frame()

	// The front door: five choices, the first in focus with its key; the arrows and the pointer move the focus.
	testing.expect_value(t, says("door.title"), "OdinCraft")
	testing.expect(t, strings.contains(says("door.world"), "The world of seed 7"), "the front door does not say which world is in hand")
	testing.expect_value(t, count("door.enter") + count("door.worlds") + count("door.new") + count("door.settings") + count("door.quit"), DOOR_CHOICES)
	enter := screen_find(&screen, "door.enter")
	testing.expect(t, enter.text == "Enter the last world" && .Chosen in enter.state && enter.key == "Enter", "Enter the last world is not in focus with its key on it")
	key(.DOWN)
	testing.expect(t, .Chosen in screen_find(&screen, "door.worlds").state && .Chosen not_in screen_find(&screen, "door.enter").state, "Down did not move the focus")
	key(.UP)
	key(.UP)
	testing.expect(t, .Chosen in screen_find(&screen, "door.quit").state, "Up from the first choice did not go round to the last")
	move: sdl.Event
	r := screen_find(&screen, "door.settings").rect
	move.type, move.motion.x, move.motion.y = .MOUSE_MOTION, r.x + 20, r.y + 10
	door_event(&move)
	frame()
	testing.expect(t, .Chosen in screen_find(&screen, "door.settings").state, "the pointer did not move the focus")

	// Enter the last world waits for the islands near the start, and goes in when they are made.
	key(.UP); key(.UP); key(.UP)
	key(.RETURN)
	testing.expect(t, door.wish == .Hold && door.isle == 0 && !world_enterable(0), "Enter on the first choice did not ask for play at the start")
	testing.expect(t, strings.contains(says("door.note"), "You go in when they are"), "the front door does not say it is waiting to go in")
	testing.expect(t, strings.contains(screen_says(&screen, .Making), "The islands near the start") && strings.contains(screen_says(&screen, .Making), "2 of 5"), "the world being made does not say how far its islands have come")
	key(.ESCAPE)
	testing.expect(t, door.wish == .None && door.screen == .Door, "Escape did not take the wish to go in back")

	// Worlds: the worlds on disk, and Escape back.
	click("door.worlds")
	testing.expect(t, door.screen == .Worlds && says("worlds.title") == "Worlds", "a click on Worlds did not open the list")
	for w in door.worlds do testing.expect(t, w.seed != 0, "a world is listed with no seed")
	laid_out(t, "Worlds")
	key(.ESCAPE)
	testing.expect_value(t, door.screen, Before.Door)

	// A new world: a seed typed, taken back, and drawn; nothing is made until Make it.
	click("door.new")
	testing.expect_value(t, says("new.title"), "A new world")
	typed: sdl.Event
	typed.type, typed.text.text = .TEXT_INPUT, "4x2"
	door_event(&typed)
	frame()
	testing.expect_value(t, says("new.seed"), "42")
	testing.expect(t, .Main in screen_find(&screen, "new.make").state, "a seed typed does not make Make it the main thing to do")
	key(.BACKSPACE)
	testing.expect_value(t, says("new.seed"), "4")
	key(.D)
	testing.expect(t, len(door.typed) > 0 && says("new.seed") == string(door.typed[:]), "D did not draw a seed")
	testing.expect_value(t, screen_find(&screen, "new.draw").key, "D")
	clear(&door.typed)
	frame()
	testing.expect(t, .Faint in screen_find(&screen, "new.make").state, "Make it is offered with no seed")
	key(.RETURN)
	testing.expect(t, door.screen == .New && making.seed == 7, "Enter with no seed made a world")
	key(.ESCAPE)

	// Settings: the interface's size, and the keys, each a row of BINDS that takes the next key pressed.
	click("door.settings")
	testing.expect_value(t, says("settings.title"), "Settings")
	click("settings.size", "150%")
	testing.expect(t, play.scale == 6 && ui.module == 6, "a size chosen did not change the interface's size")
	click("settings.size", "100%")
	testing.expect_value(t, ui.module, 4)
	testing.expect(t, count("settings.key") > 8, "the keys are not listed")
	row := -1
	for b, i in BINDS do if b.act == .Pause && b.views == .Above do row = i
	for &it in screen.items do if it.id == "settings.key" && it.arg == row do it.id = "the row"
	testing.expect(t, click("the row") && door.rebind == row && says("settings.waits") == "press a key", "a click on a key's row did not wait for a key")
	key(.J)
	testing.expect(t, BINDS[row].key == .J && BINDS[row].name == "J" && door.rebind == -1, "the next key pressed did not become the row's")
	door_act(.Keys_Back, 0)
	testing.expect(t, BINDS[row].key == .SPACE && BINDS[row].name == "Space", "the keys were not put back as they were")
	laid_out(t, "Settings")
	key(.ESCAPE)

	// The world's screen opens framed on the islands there are to choose from, each named on the map
	// and a row of the list, with the start in the hand in the card's shape.
	screen_go(.Chart)
	frame()
	testing.expect_value(t, says("world.title"), "The world of seed 7")
	testing.expect(t, strings.contains(says("world.says"), "islands near the start"), "the world's screen does not say what is known of the world")
	testing.expect_value(t, count("chart.name"), len(archipelago))
	for is in archipelago {
		at := chart_to({f64(is.origin.x), f64(is.origin.y)})
		testing.expectf(t, inside(chart.free, at), "island %d lies outside the part of the picture no panel stands on when the world's screen opens", is.id)
	}
	testing.expect_value(t, count("isles.row"), len(archipelago))
	testing.expect_value(t, count("isles.mainland"), max(len(lands), 1))   // a row for each land larger than an island
	testing.expect(t, says("isles.name") == isle_name(0) && strings.contains(says("isles.land"), "km²"), "the list's first row is not the start, with its land")
	testing.expect(t, chart.pick == 0 && says("isle.title") == isle_name(0), "the start is not in the hand when the world's screen opens")
	testing.expect(t, strings.contains(says("isle.sub"), "the start") && strings.contains(says("isle.sub"), kind_said(archipelago[0].kind).one[2:]), "the card does not say the island's kind, and that it is the start")
	hand := screen_says(&screen, .Hand)
	for d in ISLE_DEPTHS do testing.expectf(t, strings.contains(hand, d), "the island's card has not its depth %s", d)
	// The card is rows: a thing, and a word or a figure. No row is a sentence; the why is asked for.
	for d in Isle_Depth {
		click("isle.tab", ISLE_DEPTHS[d])
		testing.expectf(t, count("isle.thing") >= 3 || d == .Places, "the card's depth %s has not its rows", ISLE_DEPTHS[d])
		for it in screen.items do if it.id == "isle.says" || it.id == "isle.thing" {
			testing.expectf(t, len(it.text) <= 44 && !strings.contains(it.text, ". "), "the card's depth %s answers in a sentence: %q", ISLE_DEPTHS[d], it.text)
		}
	}
	click("isle.tab", "Land")
	land, _ := row_says("Land")
	testing.expect(t, strings.contains(land, "km²"), "a formed island does not say its land")
	landing, why := row_says("Landing")
	testing.expect(t, landing != "" && strings.contains(why, "boat"), "the card does not say what landing the island offers, and why")
	testing.expect_value(t, count("isle.why"), 0)
	click("isle.thing", "Landing")   // a click on the row's words says its why under it, and again takes it back
	testing.expect(t, chart.row >= 0 && strings.contains(says("isle.why"), "boat"), "a row chosen does not say its why")
	click("isle.thing", "Landing")
	testing.expect_value(t, count("isle.why"), 0)
	click("isle.tab", "Life")
	deer, swims := row_says("Sika deer")
	testing.expect(t, deer == "not here" && strings.contains(swims, "swims"), "the card does not say who reached the island, and why not")
	click("isle.tab", "Rock")
	rock, _ := row_says("Its rock tells of")
	testing.expect_value(t, rock, home.region.story.name)
	click("isle.tab", "Land")

	// The doors: not while the islands near it are unformed, and the card says why; then by key.
	testing.expect(t, screen_find(&screen, "isle.found").key == "Enter" && screen_find(&screen, "isle.walk").key == "W", "the doors have not their keys on them")
	testing.expect_value(t, says("isle.found"), "Plan an expedition")
	testing.expect(t, strings.contains(says("isle.waits"), "still to be formed"), "the card does not say why play cannot begin yet")
	testing.expect(t, .Main in screen_find(&screen, "isle.found").state, "an expedition cannot be planned on an island whose land is formed")
	key(.W)
	testing.expect(t, door.wish == .None, "the island was walked before it could be entered")
	key(.RETURN)
	testing.expect_value(t, door.screen, Before.Plan)
	an_expedition_is_planned(t)
	testing.expect(t, door.screen == .Chart && chart.pick == 0, "Escape from planning did not go back to the world's map with the island still in the hand")
	making.near_km = 10   // as if its neighbours were formed
	frame()
	testing.expect_value(t, says("isle.waits"), "")
	key(.W)
	testing.expect(t, door.wish == .Walk && door.isle == 0, "W did not walk the island in the hand")
	door.wish = .None
	making.near_km = 64

	// A click on the map takes what is under it in the hand: another island, the open sea.
	there := chart_to({f64(archipelago[1].origin.x), f64(archipelago[1].origin.y)})
	down: sdl.Event
	down.button.x, down.button.y, down.button.button = there.x, there.y, sdl.BUTTON_LEFT
	for type in ([2]sdl.EventType{.MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP}) {
		down.type = type
		door_event(&down)
	}
	frame()
	testing.expect(t, chart.pick == 1 && says("isle.title") == isle_name(1), "a click on an island did not take it in the hand")
	testing.expect(t, strings.contains(says("isle.sub"), "of the start"), "the card does not say where the island lies")
	// The view goes to it: it fills the free part of the picture, large enough that its places are named on it.
	settle()
	side := f32(f64(chart.wide)/chart.span*archipelago[1].size)
	there = chart_to({f64(archipelago[1].origin.x), f64(archipelago[1].origin.y)})
	testing.expect(t, side > 0.5*chart.free.h && inside(chart.free, there), "an island taken in the hand was not gone to")
	testing.expect_value(t, count("chart.place"), len(formed[1].places))

	// A row of the list takes its island in the hand and the view to it; the mainland's says how it stands, and why.
	click("isles.name", isle_name(0))
	settle()
	testing.expect(t, chart.pick == 0 && says("isle.title") == isle_name(0), "a row of the list did not take its island in the hand")
	click("isles.name", "The mainland")
	settle()
	stands, cause := row_says("As land")
	testing.expect(t, chart.pick == MAINLAND && stands == "known, not formed" && strings.contains(cause, "not formed as land"), "the mainland's card does not say how it stands, and why")
	// Every large land has a name of its own, and its row takes it in the hand with its own card.
	for i in 1..<len(lands) do for j in 0..<i do testing.expectf(t, land_name(i) != land_name(j), "large lands %d and %d are both named %s", j, i, land_name(i))
	if len(lands) > 1 {
		click("isles.name", land_name(1))
		settle()
		stands, _ = row_says("As land")
		land, _ := row_says("Land")
		testing.expect(t, chart.pick == MAINLAND - 1 && says("isle.title") == land_name(1) && stands == "known, not formed" && strings.contains(land, "km²"), "another large land's card does not say how it stands")
	}
	testing.expect_value(t, count("isle.found"), 0)
	click("isles.name", isle_name(1))
	settle()
	there = chart_to({f64(archipelago[1].origin.x), f64(archipelago[1].origin.y)})

	// The lenses open from their button: a lens of the world's fields, with the key to it; and the pointer on the map says what it says there.
	testing.expect_value(t, count("lens.row"), 0)
	key(.L)
	testing.expect_value(t, count("lens.row"), len(WORLD_LENSES))
	click("lens.row", "Setting")
	testing.expect(t, sync.atomic_load(&chart.lens) == 0 && count("lens.kind") == len(Setting), "the lens did not come on with its key")
	testing.expect_value(t, chart_tip(there), SETTINGS[archipelago[1].setting])
	click("lens.row", "Setting")
	testing.expect_value(t, chart.lens, -1)
	key(.L)
	testing.expect_value(t, count("lens.row"), 0)

	// The wheel and the keys zoom; Home shows all the islands again, and leaves the hand as it is.
	span := chart.span
	key(.EQUALS)
	testing.expect(t, chart.span < span, "= did not bring the map nearer")
	key(.HOME)
	settle()
	testing.expect(t, chart.pick == 1 && chart.span > 10*archipelago[1].size, "Home did not show all the islands")
	for is in archipelago do testing.expectf(t, inside(chart.free, chart_to({f64(is.origin.x), f64(is.origin.y)})), "island %d is out of view after Home", is.id)

	// It holds at every scale, with an island in the hand, a lens on and the world being made.
	for module in 3..=8 {
		play.scale = module
		for s in Before {
			door.screen = s
			sync.atomic_store(&chart.lens, 0 if s == .Chart else -1)
			frame()
			laid_out(t, "before play")
		}
	}
	play.scale = 0
	sync.atomic_store(&chart.lens, -1)
	door.screen = .Chart
	frame()

	// Escape puts the island down, then goes to the front door.
	key(.ESCAPE)
	testing.expect(t, chart.pick == -1 && door.screen == .Chart, "Escape did not put the island down first")
	key(.ESCAPE)
	testing.expect_value(t, door.screen, Before.Door)

	// Out of play: the menu's two ways, each with its key, end the game's loop and say where to.
	running := true
	play.running, play.menu = &running, true
	testing.expect(t, key_for(.Leave, int(Leave.World)) == "W" && key_for(.Leave, int(Leave.Door)) == "D", "the menu's ways out have not their keys")
	play_act(.Leave, int(Leave.World))
	testing.expect(t, !running && leaving == .World, "Leave to the world did not end the game for the world's screen")
	play.menu, leaving = false, .Quit
}
