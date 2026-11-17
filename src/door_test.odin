package main

import "core:strings"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

// The screens before play are data, as the play screen is (docs/adr/0010): each a list of parts made
// with no window. This test stands at the front door over the world the forming test made, moves
// its focus by key and by pointer, goes through Worlds, a new world and settings, opens the world's
// screen, takes an island in the hand, puts a lens on, and asks for the doors into play; and checks
// that every screen lies inside the picture at every scale. It makes no world and enters no game:
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
	world_adopt(0, 64)   // the world the forming test made is the world in hand
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

	// The world's screen: the world, its islands, and the start in the hand in the card's shape.
	screen_go(.Chart)
	frame()
	testing.expect_value(t, says("world.title"), "The world of seed 7")
	testing.expect(t, strings.contains(says("world.says"), "islands near the start"), "the world's screen does not say what is known of the world")
	testing.expect_value(t, count("chart.name"), len(archipelago))
	testing.expect(t, chart.pick == 0 && says("isle.title") == capital(kind_said(archipelago[0].kind).one), "the start is not in the hand when the world's screen opens")
	testing.expect(t, strings.contains(says("isle.sub"), "the start"), "the card does not say the island is the start")
	hand := screen_says(&screen, .Hand)
	testing.expect(t, strings.contains(hand, "* Land") && strings.contains(hand, "Rock") && strings.contains(hand, "Climate") && strings.contains(hand, "Life") && strings.contains(hand, "Places"), "the island's card has not its depths")
	testing.expect(t, strings.contains(says("isle.says"), "km² of land"), "a formed island does not say its land")
	click("isle.tab", "Life")
	testing.expect(t, strings.contains(says("isle.says"), "sika deer"), "the card does not say who reached the island")
	click("isle.tab", "Rock")
	testing.expect(t, strings.contains(says("isle.says"), home.region.story.name), "the card does not say the island's rock")

	// The doors: not while the islands near it are unformed, and the card says why; then by key.
	testing.expect(t, screen_find(&screen, "isle.found").key == "Enter" && screen_find(&screen, "isle.walk").key == "W", "the doors have not their keys on them")
	testing.expect(t, strings.contains(says("isle.waits"), "still to be formed"), "the card does not say why play cannot begin yet")
	key(.RETURN)
	testing.expect(t, door.wish == .None, "Found a hold was taken before the island could be entered")
	making.near_km = 10   // as if its neighbours were formed
	frame()
	testing.expect(t, says("isle.waits") == "" && .Main in screen_find(&screen, "isle.found").state, "a door that can be taken is not the main thing to do")
	key(.RETURN)
	testing.expect(t, door.wish == .Hold && door.isle == 0, "Enter did not found a hold on the island in the hand")
	door.wish = .None
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
	testing.expect(t, chart.pick == 1 && says("isle.title") == capital(kind_said(archipelago[1].kind).one), "a click on an island did not take it in the hand")
	testing.expect(t, strings.contains(says("isle.sub"), "of the start"), "the card does not say where the island lies")

	// A lens of the world's fields, with the key to it; and the pointer on the map says what it says there.
	click("lens.row", "Setting")
	testing.expect(t, sync.atomic_load(&chart.lens) == 0 && count("lens.kind") == len(Setting), "the lens did not come on with its key")
	testing.expect_value(t, chart_tip(there), SETTINGS[archipelago[1].setting])
	click("lens.row", "Setting")
	testing.expect_value(t, chart.lens, -1)

	// The wheel and the keys zoom; Home goes back over the start.
	span := chart.span
	key(.EQUALS)
	testing.expect(t, chart.span < span, "= did not bring the map nearer")
	key(.HOME)
	testing.expect(t, chart.pick == 0 && chart.at == world_frame.origin, "Home did not put the map over the start")

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
