package main

import "base:builtin"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import sdl "vendor:sdl3"

// The play screen (docs/foundations/interface.md, section 4; docs/adr/0010): four regions, each
// with one job, laid over the edges of the world. Each frame play_frame lists the screen's parts
// from the game as it stands (ui.odin draws them), and the keys and the pointer come here first.
//
//   top left      the place under the view, the date, and the clock's control
//   top middle    the dwarves: who needs you, who you keep in view, and the count of all (crowd.odin)
//   left, under   messages: what happened. They fade, and are kept
//   top right     the stores and what is wrong: an alert for each thing that is, which leads to its cause
//   right         the ground here: the column of beds under the view's middle with the cut marked
//                 on it, its controls, the lenses, and the walk
//   lower left    the hand: the thing selected (hand.odin), or the tool held; the orders bar under it (bar.odin)
//   bottom right  the lists: Dwarves, Places, and the menu
//
// Every action is an Act. A key is a row of BINDS that names an act, and a button names its act
// and shows that row's key, so the key written on a button is always the key that presses it.
//
// The pointer is shared with the world by one rule. A press belongs to what lies under it, a panel
// or the world (over_world, above.odin), and so does everything until that button is let go: a box
// dragged from the world on over a panel goes on being marked, and a drag begun on the column goes
// on moving the cut off it. The wheel belongs to what the pointer is over: a list scrolls, the
// column moves the cut, the world zooms.

Act :: enum u8 {
	None,
	Pause, Speed,                                        // the clock
	Cut, Cut_Move, Cut_Drag, Follow, Bare, Lenses, Lens, Walk,   // the ground here
	Why, Go, Drop, Depth,                                // the hand
	Order, Plan, Stuff, Takes, Deep, High, Take_Back, More,     // the orders bar, a tool's choices and numbers, an order's card (bar.odin), and the card asked for or shut
	Zone_Takes, Zone_Grow, Zone_Remove,                  // a stockpile in the hand: what it takes, the Store tool taken up to make it larger, and the whole of it removed (bar.odin)
	Tend, Fire_Remove,                                   // a fire in the hand: kept fed or let go out, and put out and taken up (shelter_view.odin)
	List, Sort, Fold, Row, Find, Thumb,                  // the lists
	Who, Lead, Keep, Only, Whole, Crowd,                 // the dwarves: a picture, a row, kept in view, the list's kept alone, a group whole, the list opened on some (crowd.odin)
	Menu, Back, Quit, Scale, Escape,
	Said, Wrong,                                         // a message or an alert, which leads to its place
	Leave,                                               // out of play, to the world's screen or the front door (door.odin)
	Door_Move, Door_Pick, Door_Go, Door_Back, Draw, Stop, Rebind, Keys_Back,   // before play: the front door and its screens (door.odin)
	Chart_Lens, Chart_Lenses, Chart_Zoom, Chart_Home, Isle_Depth, Isle_Row, Isle_Take, Found, Roam,   // the world's screen (chart.odin)
	Mass_Leave,                                                                // a world being made: the mainland's long stage left (door.odin)
	Site, Site_Row, Party_Who, Party_Move, Draw_Dwarf, Draw_Party, Set_Out,           // expedition planning (plan.odin): a landing, a row of its card, a dwarf, the party drawn again, and away
}

// A key: which act it does and with what, in which view, and whether holding it goes on doing it.
Views :: enum u8 { Above, Afoot, Either, Menu, Door, Chart, Plan }   // Door, Chart and Plan: before play, at the front door's screens, on the world's map and planning an expedition
Bind :: struct {
	key:          sdl.Scancode,
	name:         string,   // as it is written on a button
	act:          Act,
	arg, shifted: int,      // what it does it with, and with Shift held
	views:        Views,
	held:         bool,
}
BINDS := [?]Bind{
	{.ESCAPE, "Esc", .Escape, 0, 0, .Either, false},
	{.SPACE, "Space", .Pause, 0, 0, .Above, false},
	{.P, "P", .Pause, 0, 0, .Either, false},
	{._1, "1", .Speed, 0, 0, .Above, false}, {._2, "2", .Speed, 1, 1, .Above, false}, {._3, "3", .Speed, 2, 2, .Above, false},
	{.R, "R", .Cut_Move, 1, 8, .Above, true}, {.F, "F", .Cut_Move, -1, -8, .Above, true},
	{.C, "C", .Cut, 0, 0, .Above, false}, {.H, "H", .Follow, 0, 0, .Above, false},
	{.V, "V", .Bare, 0, 0, .Above, false}, {.L, "L", .Lenses, 0, 0, .Above, false},
	{.TAB, "Tab", .Walk, 0, 0, .Either, false},
	{.Y, "Y", .Why, 0, 0, .Either, false},
	{.E, "E", .Why, 0, 0, .Afoot, false},   // P2's key for the dwarf aimed at; from above E turns the view
	{.RETURN, "Enter", .Go, 0, 0, .Either, false},
	{.K, "K", .Keep, -1, -1, .Either, false},
	{.I, "I", .More, 0, 0, .Either, false},
	{.F1, "F1", .List, int(List.Dwarves), int(List.Dwarves), .Either, false},
	{.F4, "F4", .List, int(List.Places), int(List.Places), .Either, false},
	{.D, "D", .Order, int(Tool.Dig), int(Tool.Dig), .Above, false}, {.T, "T", .Order, int(Tool.Fell), int(Tool.Fell), .Above, false},
	{.B, "B", .Order, int(Tool.Build), int(Tool.Build), .Above, false}, {.M, "M", .Order, int(Tool.Send), int(Tool.Send), .Either, false},
	{.S, "S", .Order, int(Tool.Store), int(Tool.Store), .Above, false},
	{.Z, "Z", .Order, int(Tool.Sleep), int(Tool.Sleep), .Above, false},
	{.G, "G", .Order, int(Tool.Gather), int(Tool.Gather), .Above, false}, {.N, "N", .Order, int(Tool.Fish), int(Tool.Fish), .Above, false},
	{.X, "X", .Order, int(Tool.Remove), int(Tool.Remove), .Above, false},
	{.ESCAPE, "Esc", .Back, 0, 0, .Menu, false},
	{.W, "W", .Leave, int(Leave.World), int(Leave.World), .Menu, false}, {.D, "D", .Leave, int(Leave.Door), int(Leave.Door), .Menu, false},
	{.Q, "Q", .Quit, 0, 0, .Menu, false},
	// Before play (door.odin, chart.odin).
	{.UP, "Up", .Door_Move, -1, -1, .Door, true}, {.DOWN, "Down", .Door_Move, 1, 1, .Door, true},
	{.RETURN, "Enter", .Door_Go, 0, 0, .Door, false}, {.ESCAPE, "Esc", .Door_Back, 0, 0, .Door, false},
	{.D, "D", .Draw, 0, 0, .Door, false}, {.S, "S", .Stop, 0, 0, .Door, false},
	{.RETURN, "Enter", .Found, 0, 0, .Chart, false}, {.W, "W", .Roam, 0, 0, .Chart, false},
	{.ESCAPE, "Esc", .Door_Back, 0, 0, .Chart, false}, {.HOME, "Home", .Chart_Home, 0, 0, .Chart, false},
	{.EQUALS, "=", .Chart_Zoom, 1, 1, .Chart, true}, {.MINUS, "-", .Chart_Zoom, -1, -1, .Chart, true},
	{.S, "S", .Stop, 0, 0, .Chart, false}, {.L, "L", .Chart_Lenses, 0, 0, .Chart, false},
	// Planning an expedition (plan.odin).
	{.RETURN, "Enter", .Set_Out, 0, 0, .Plan, false}, {.ESCAPE, "Esc", .Door_Back, 0, 0, .Plan, false},
	{._1, "1", .Site, 0, 0, .Plan, false}, {._2, "2", .Site, 1, 1, .Plan, false}, {._3, "3", .Site, 2, 2, .Plan, false}, {._4, "4", .Site, 3, 3, .Plan, false},
	{.UP, "Up", .Party_Move, -1, -1, .Plan, true}, {.DOWN, "Down", .Party_Move, 1, 1, .Plan, true},
	{.D, "D", .Draw_Dwarf, -1, -1, .Plan, false}, {.A, "A", .Draw_Party, 0, 0, .Plan, false},
	{.HOME, "Home", .Chart_Home, 0, 0, .Plan, false}, {.EQUALS, "=", .Chart_Zoom, 1, 1, .Plan, true}, {.MINUS, "-", .Chart_Zoom, -1, -1, .Plan, true},
}

// The key written on the button of an act.
key_for :: proc(act: Act, arg := 0) -> string {
	for b in BINDS do if b.act == act && b.arg == arg && b.views <= .Menu && (b.views == .Menu) == play.menu do return b.name
	return ""
}

List :: enum u8 { None, Dwarves, Places }

// A lens: one of the land's fields painted over the world (fields.odin), as --overlay= paints it on the map.
Lens_Row :: struct { name: string, field: Field, says: string, blocks: bool }   // blocks: it is read from the blocks round the view, not painted from a field of the land (shelter_scan)
LENSES := [?]Lens_Row{
	{"Rock", .Rock, "The rock at the ground's top, each kind in its own colour.", false},
	{"Water in the ground", .Water_Table, "How far under the ground the water in it stands: bluest where it lies at the surface.", false},
	{"Rain", .Rain, "A year's rain: more on high ground and on ground rising into the wind, less in its lee.", false},
	{"Livable ground", .Livable, "Ground a hold could stand on: gentle, clear of the sea, a hectare or more.", false},
	{"Plants", .Plants, "The plants that took each piece of ground.", false},
	{"Soil", .Soil, "The kind of soil.", false},
	{"Shelter", .Rock, "Where a dwarf is out of the weather: ground with a roof over it, and ground with walls round it as well.", true},
}
LENS_SIZE :: 1024   // texels across an island
Lens_Job :: struct { island: ^Formed, field: Field, pixels: []u8, done: bool, rank: [Mat]u8 }   // rank: which of the island's rocks each is, for a lens of kinds

// The rocks at an island's surface in the order a lens of kinds colours them (LOOK.kinds).
kinds_rank :: proc(f: ^Formed) -> (rank: [Mat]u8) {
	n := u8(0)
	for t, m in f.survey.rocks do if t.cells > 0 {
		rank[m] = n%len(LOOK.kinds)
		n += 1
	}
	return
}

// A lesson (I11): one line, shown beside the thing the first time it matters and gone when it is done.
Lesson :: enum u8 { Select, Cut, Walk }
LESSONS := [Lesson]string{
	.Select = "Click anything on the land to ask what it is and why.",
	.Cut = "Drag the brass mark, or press R and F, to cut the ground open higher or lower.",
	.Walk = "Press Tab to walk the ground under the view's middle, and Tab again to come back up.",
}

// A message: something that happened. It is shown for a while and kept.
Said :: struct { text: string, at: [3]f64, placed: bool, since: f64, who: int, more: string }   // who: the dwarf it is about, or -1; more: the whole of it, where the line is the short of it
SAID_FOR  :: 8.0    // seconds a message is shown
SAID_MOST :: 4      // messages shown at once

// An alert: a problem that is still true. It stays until it is cleared.
Wrong :: struct { id, text: string, sign: Sign, at: [3]f64, placed: bool, need: int }   // need: the row of NEEDS it counts dwarves by (crowd.odin), or -1

Play :: struct {
	// What the game hands it, once.
	a:        ^Above,
	clock:    ^Clock,
	w:        ^World,
	p:        ^Player,
	afoot, captured, running: ^bool,
	window:   ^sdl.Window,
	unseen:   bool,            // no window is shown: a picture or a measure
	still:    bool,            // and nothing plays it: a picture of one moment, in which nothing fades, eases or waits for the pointer to rest
	plain:    bool,            // the interface is not drawn
	// The frame's.
	area:     Area,
	clip:     Rect,
	ratio:    f32,             // pixels of the picture to a point of the window
	aspect:   f32,
	eye:      [3]f64,
	yaw, pitch, fov, hour, day: f32,
	date:     Date,            // the day and the hour of the world, as the clock has them (clock.odin)
	sky:      Weather,         // the weather over the view, and the ground it was read on (weather.odin)
	sky_stand: Stand,
	aim:      Pick,            // in first person, the block aimed at
	now:      f64,             // real seconds since the game began
	rest:     f64,             // seconds the pointer has rested
	pointer:  [2]f32,
	place_foot, place_wide, wrong_foot: f32,
	crowd_right: f32,          // where the dwarves' place at the top must end: at the alerts, at a list, or at the picture's edge
	ground:   Rect,            // the ground's panel
	beds:     Rect,            // its column, for the pointer to drag the cut on
	walk_row: Rect,
	// What it keeps.
	scale:    int,             // pixels to a module, or 0 for the picture's own
	hand:     Thing,
	card:     Hand_Card,
	tab:      Depth,
	card_scroll, card_over: f32,   // how far the card's depth is scrolled, and how far it can be
	card_open: bool,           // the card is shown whole, as the player last left it; shut, a thing in the hand is one line
	following: bool,           // the view follows the dwarf in the hand
	// The dwarves on screen (crowd.odin).
	several:  [dynamic]int,    // the dwarves in the hand, one or more, in the party's order
	kept:     [dynamic]int,    // those kept in view at the top, in the order they were chosen
	greeted:  bool,            // the first boat's were kept in view, once
	mourned:  [dynamic]bool,   // the dwarves whose deaths were told
	foraging: bool,            // the alert that the hold lives from hand to mouth stands
	need:     [dynamic]i8,     // for each dwarf its row of NEEDS, or -1
	needing:  [dynamic]int,    // the dwarves who need the player, worst first
	alerted:  [len(NEEDS)]u64, // those each need's alert was last raised for
	by:       int,             // the Dwarves list is grouped by need, by trade or by place
	only_kept: bool,           // and holds only those kept in view
	whole, folded: bit_set[0..<128],   // its groups shown whole, and folded to their count
	adding:   bool,            // Shift is held: a click adds to the hand
	posed:    bool,            // the options' dwarves were taken in the hand and kept in view (play_posed)
	goal:     [2]f64,          // where the view is going
	going:    bool,
	list:     List,
	sort:     int,             // 0 named first and by kind, 1 nearest first
	open:     bit_set[0..<32], // the groups of the list that are not folded
	list_scroll, list_over: f32,
	find:     [dynamic]u8,     // what has been typed in the list's field
	typing:   bool,
	lenses:   bool,            // the lenses' choices are open
	lens:     int,             // the lens on, or -1
	lens_job: ^Lens_Job,
	lens_tex: ^sdl.GPUTexture,
	lens_island: ^Formed,      // the island the texture is of, and the lens it shows
	lens_shown: int,
	menu:     bool,
	owner:    enum u8 { None, World, Panel },   // whose the pointer is while a button is down
	press:    [2]f32,
	pressed:  Act,
	pressed_arg: int,
	pressing: bool,
	drag:     enum u8 { None, Cut, List, Card },
	drag_from, drag_scroll: f32,
	column:   [2]i32,          // the top and the span of the column, held while the cut is dragged
	said:     [dynamic]Said,
	wrong:    [dynamic]Wrong,
	learned:  bit_set[Lesson],
	teach:    bool,            // lessons are shown
	animal:   struct { row: int, at: [3]f64, nest, ok: bool },   // under the pointer this frame
	tip_block: [3]i32,
	tip:      string,
}
play := Play{lens = -1, lens_shown = -1, open = {0}}   // the frame thread's
typing: bool   // the keyboard is a field's: nothing else reads the keys

// ---- messages and alerts --------------------------------------------------------------------

// What other systems tell the player. tell may be called from any thread; the frame takes what was told.
told: struct { mutex: sync.Mutex, lines: [dynamic]Said }

// Something happened: a message. With a place, a click on it takes the view there (I4).
tell :: proc(text: string, at: Maybe([3]f64) = nil, who := -1, more := "") {
	s := Said{text = strings.clone(text), who = who, more = strings.clone(more)}
	if place, ok := at.?; ok do s.at, s.placed = place, true
	sync.guard(&told.mutex)
	append(&told.lines, s)
}

// A line of the hold's log (say, hold.odin) as a message, with where it happened and which dwarf it
// is about (about, hold.odin): its time and the order's own form are the log's.
tell_log :: proc(line: string, at: [3]f64, who: int, short := "") {
	l := line
	if i := strings.index(l, "] "); i >= 0 && strings.has_prefix(l, "[") do l = l[i + 2:]
	if strings.has_prefix(l, `The hold says "`) {
		if i := strings.index(l, `": `); i >= 0 do l = l[i + 3:]
	}
	tell(short if short != "" else sentence(l), at, who, sentence(l) if short != "" else "")
}

// A problem that is still true: it stands at the top right until alert_clear. Raised again under
// the same id it is the same alert, said anew, so "three dwarves are thirsty" is one that counts (I14).
// With a row of NEEDS, a click on it takes the dwarves it counts in the hand.
alert_raise :: proc(id, text: string, sign := Sign.Trouble, at: Maybe([3]f64) = nil, need := -1) {
	alert_clear(id)
	w := Wrong{id = strings.clone(id), text = strings.clone(text), sign = sign, need = need}
	if place, ok := at.?; ok do w.at, w.placed = place, true
	append(&play.wrong, w)
	slice.stable_sort_by(play.wrong[:], proc(a, b: Wrong) -> bool { return a.sign == .Trouble && b.sign != .Trouble || a.sign == b.sign && a.need >= 0 && b.need >= 0 && a.need < b.need })
}
alert_clear :: proc(id: string) {
	for w, i in play.wrong do if w.id == id {
		delete(w.id); delete(w.text)
		ordered_remove(&play.wrong, i)
		return
	}
}

// ---- beginning ------------------------------------------------------------------------------

play_begin :: proc(opt: ^Options, a: ^Above, clock: ^Clock, w: ^World, p: ^Player, afoot, captured, running: ^bool, window: ^sdl.Window, unseen: bool) {
	u := &play
	u.a, u.clock, u.w, u.p, u.afoot, u.captured, u.running, u.window, u.unseen = a, clock, w, p, afoot, captured, running, window, unseen
	u.still = unseen && !script.on
	u.plain, u.scale, u.menu, u.lenses, u.teach = opt.plain, opt.scale, opt.menu, opt.lenses, opt.lessons || !unseen
	if !unseen do if data, err := os.read_entire_file("build/interface.txt", context.temp_allocator); err == nil {   // what was learned, and the scale chosen
		text := string(data)
		for line in strings.split_lines_iterator(&text) {
			for l in Lesson do if line == fmt.tprintf("learned %v", l) do u.learned += {l}
			for m in 3..=8 do if line == fmt.tprintf("scale %d", m) && opt.scale == 0 do u.scale = m
		}
	}
	if opt.list == "places" do u.list = .Places
	if opt.list == "dwarves" do u.list = .Dwarves
	for name, i in ([3]string{"need", "trade", "place"}) do if opt.group == name do u.by = i
	u.only_kept = opt.group == "kept"
	append(&u.find, opt.find)
	if opt.tell != "" do tell(opt.tell)
	if opt.alert != "" do alert_raise("asked", opt.alert, .Caution if strings.has_prefix(opt.alert, "?") else .Trouble, a.at)
	for l, i in LENSES do if opt.lens != "" && (strings.equal_fold(l.name, opt.lens) || !l.blocks && FIELDS[l.field].name == opt.lens) do u.lens = i
	if opt.lens != "" && u.lens < 0 && opt.lens != "leaves" {
		fmt.eprint("no lens named", opt.lens, "; there are: leaves")
		for l in LENSES do fmt.eprintf(", %s", strings.to_lower(l.name, context.temp_allocator) if l.blocks else FIELDS[l.field].name)
		fmt.eprintln()
		os.exit(2)
	}
	if opt.lens == "leaves" do a.bare = true
}

// What is kept from one game to the next, until the game has settings of its own (I-2).
play_keep :: proc() {
	u := &play
	if u.unseen do return
	b := strings.builder_make(context.temp_allocator)
	for l in u.learned do fmt.sbprintfln(&b, "learned %v", l)
	if u.scale != 0 do fmt.sbprintfln(&b, "scale %d", u.scale)
	settings_lines(&b)   // the world last entered, the keys changed, and how long a world took to make (door.odin)
	_ = os.write_entire_file("build/interface.txt", b.buf[:])
}

learn :: proc(l: Lesson) {
	if l in play.learned do return
	play.learned += {l}
	play_keep()
}

// Work the interface has under way that a picture should wait for.
play_backlog :: proc() -> int { return int(play.lens_job != nil) + int(play.going) }

// ---- the hand -------------------------------------------------------------------------------

// Whether a thing is the one in the hand.
held_now :: proc(t: Thing) -> bool {
	h := play.hand
	return t.kind != .Dwarves && t.kind != .None && t.kind == h.kind && t.block == h.block && t.lo == h.lo && t.hi == h.hi && t.place == h.place && t.creature == h.creature && t.dwarf == h.dwarf && t.island == h.island
}

hand_take :: proc(t: Thing) {
	u := &play
	if held_now(t) do return
	card_free(&u.card)
	u.hand, u.tab, u.card_scroll, u.following = t, .Own if t.kind != .Ground else .Rock, 0, false
	if t.kind != .Dwarf && t.kind != .Dwarves && t.kind != .None do u.card = card_make(u.w, t)
	clear(&u.several)   // one dwarf is the one; several are put there by dwarves_take (crowd.odin)
	if t.kind == .Dwarf do append(&u.several, t.dwarf)
	hold_select(t.dwarf if t.kind == .Dwarf else -1)
	if t.kind != .None do learn(.Select)
}
hand_drop :: proc() {
	hand_take({})
	mark_clear(play.a)
}

// What a click on the world picked: a dwarf before an animal, an animal before the block behind it.
// A click selects, and says what the thing is in a line; its card is asked for (I2). A second click
// on the thing in the hand asks for it, or shuts it. A click on bare ground shuts a card left open,
// as a click away does in the games this is measured by; on anything else it stays as it was left.
hand_pick :: proc(pick: Pick, pointer: [2]f32) {
	u := &play
	if !u.afoot^ {
		ray := view_ray(u.yaw, u.pitch, u.fov, u.aspect, pointer)
		if who := hold_aimed(u.w, u.eye, ray, 4*linalg.length(u.a.at - u.eye) + 600, u.a); who >= 0 {
			if !u.adding && u.hand.kind == .Dwarf && u.hand.dwarf == who do u.card_open = !u.card_open
			dwarf_take(who, u.adding)
			return
		}
		if u.animal.ok {
			at := u.animal.at
			b := [3]i32{i32(math.floor(at.x)), i32(math.floor(at.y)), i32(math.floor(at.z))}
			if f := island_near(at.x, at.z); f != nil do hand_take({kind = .Animal, island = f, block = b, lo = b, hi = b, creature = u.animal.row, nest = u.animal.nest, feature = -1})
			return
		}
	}
	if !pick.ok {
		hand_drop()
		return
	}
	t := thing_at(u.w, pick)
	if !u.afoot^ {   // a pile before the ground behind it; a stockpile's ground as the stockpile
		ray := view_ray(u.yaw, u.pitch, u.fov, u.aspect, pointer)
		if k := fire_aimed(u.eye, ray, pick); k >= 0 {   // a fire before what lies or stands behind it
			at := watch.seen.fires[k].at
			t = {kind = .Fire, island = t.island, block = at, lo = at, hi = at, feature = -1}
		} else if k := pile_aimed(u.eye, ray, pick); k >= 0 {
			p := watch.seen.piles[k]
			t = {kind = .Pile, island = t.island, block = p.at, lo = p.at, hi = p.at, mat = p.kind, feature = int(p.n)}
		} else if _, on := zone_under(t.block + {0, 1, 0}); on && t.kind == .Ground {   // a click on a stockpile's ground takes the whole stockpile, and its own card (zone_card, bar.odin)
			t.kind = .Zone
			if !held_now(t) do u.card_open = false
		}
	}
	if held_now(t) do u.card_open = !u.card_open
	else if t.kind == .Ground && job_of(t) < 0 do u.card_open = false
	hand_take(t)
}

// Take the view to a place in the world, with the ground there shown.
go_to :: proc(at: [2]f64, near := false) {
	u, a := &play, play.a
	u.goal, u.going, u.following = at, true, false
	if near do a.span = min(a.span, 500)
	if a.cut && !a.follow do a.level = max(a.level, ground_top(at.x, at.y) + HEADROOM)
	if u.afoot^ do play_act(.Walk, 0)
	if u.still do a.at.xz, a.settled, u.going = at, false, false
}

// A place of the island under the view: go there, and take it in the hand (I4).
place_take :: proc(c: int) {
	u := &play
	f := island_near(u.a.at.x, u.a.at.z)
	if f == nil || c < 0 || c >= len(f.candidates) do return
	k := f.candidates[c]
	at := k.at + {f64(f.region.origin.x), f64(f.region.origin.y)}
	b := [3]i32{i32(math.floor(at.x)), i32(k.top), i32(math.floor(at.y))}
	go_to(at, true)
	hand_take({kind = .Place, island = f, block = b, lo = b, hi = b, place = c, feature = -1})
}

// ---- acts -----------------------------------------------------------------------------------

play_act :: proc(act: Act, arg: int) {
	u, a := &play, play.a
	switch act {
	case .None, .Cut_Drag, .Thumb:
	case .Pause: u.clock.paused = !u.clock.paused
	case .Speed: u.clock.speed, u.clock.paused = arg, false
	case .Cut:
		cut_set(a, !a.cut)
		if !a.cut do a.follow = false
		learn(.Cut)
	case .Cut_Move:
		cut_move(a, i32(arg))
		learn(.Cut)
	case .Follow: cut_follow(a, !a.follow)
	case .Bare: a.bare = !a.bare
	case .Lenses: u.lenses = !u.lenses
	case .Lens: u.lens = -1 if u.lens == arg else arg
	case .Walk:
		u.afoot^ = !u.afoot^
		u.captured^ = u.afoot^ && !u.unseen
		if u.window != nil do _ = sdl.SetWindowRelativeMouseMode(u.window, u.captured^)
		if u.afoot^ do walk_down(a, u.w, u.p, u.aspect)
		else do walk_up(a, u.p)
		u.lenses, u.going = false, false
		learn(.Walk)
	case .Why:
		if u.afoot^ {   // the dwarf aimed at, before the block behind it
			if who := hold_aimed(u.w, u.eye, look_dir(u.yaw, u.pitch), AIM_REACH, nil); who >= 0 do dwarf_take(who)
			else do hand_pick(u.aim, {0.5, 0.5})
		} else {
			under := a.under
			if !under.ok do under = pick_far(u.eye, view_ray(u.yaw, u.pitch, u.fov, u.aspect, a.pointer), above_level(a))
			hand_pick(under, a.pointer)
		}
	case .Go:
		if u.hand.kind == .Dwarf {
			u.following, u.going = !u.following, false
			if u.following && u.afoot^ do play_act(.Walk, 0)
		} else if u.hand.kind == .Dwarves {
			if at, ok := several_middle(); ok do go_to(at)
		} else if u.hand.kind != .None do go_to({f64(u.hand.block.x) + 0.5, f64(u.hand.block.z) + 0.5})
	case .Drop: hand_drop()
	case .Depth: u.tab, u.card_scroll = Depth(arg), 0
	case .Order: tool_take(Tool(arg))
	case .Plan:
		if bar.tool == .Dig do bar.dig = Plan(arg)
		else do bar.build = Plan(arg)
	case .Stuff: bar.stuff = Stuff(arg)
	case .Takes: bar.takes = Takes(arg)
	case .Deep: bar.deep = i32(clamp(arg, 1, DEEPEST))
	case .High: bar.high = i32(clamp(arg, 1, 2))
	case .More: u.card_open, u.card_scroll = !u.card_open, 0
	case .Take_Back:
		if site, ok := site_seen(bar.job); ok do hold_order({kind = .Unmark, at = site.lo, to = site.hi})
		hand_drop()
	case .Zone_Takes:
		if u.hand.kind == .Zone do hold_order({kind = .Takes, at = u.hand.block, to = u.hand.block, takes = Takes(arg)})
	case .Zone_Remove:
		if u.hand.kind == .Zone do hold_order({kind = .Unstore, at = u.hand.block, to = u.hand.block})
		hand_drop()
	case .Zone_Grow:
		if z, ok := zone_seen(bar.zone); ok {
			bar.takes = z.takes
			grows := Tool.Sleep if z.sleep else .Store
			if bar.tool != grows do tool_take(grows)
		}
	case .Tend:
		if u.hand.kind == .Fire do hold_order({kind = .Tend, at = u.hand.block - {0, 1, 0}, to = u.hand.block - {0, 1, 0}, on = arg != 0})
	case .Fire_Remove:
		if u.hand.kind == .Fire do hold_order({kind = .Unmark, at = u.hand.block - {0, 1, 0}, to = u.hand.block - {0, 1, 0}})
		hand_drop()
	case .List:
		u.list = .None if u.list == List(arg) else List(arg)
		u.list_scroll, u.typing = 0, false
		clear(&u.find)
	case .Sort:
		if u.list == .Dwarves do u.by, u.whole, u.folded = arg, {}, {}
		else do u.sort = arg
		u.list_scroll = 0
	case .Fold:
		if u.list == .Dwarves do u.folded ~= {arg}
		else do u.open ~= {arg}
	case .Row: place_take(arg)
	case .Who:   // a dwarf's picture: a click takes it in the hand, a second takes the view to it, and with Shift it joins or leaves those in the hand
		if u.adding do dwarf_take(arg, true)
		else if u.hand.kind == .Dwarf && u.hand.dwarf == arg {
			if at, ok := hold_where(arg); ok do go_to(at.xz)
		} else do dwarf_take(arg)
	case .Lead:   // a dwarf's row: it is in the hand and the view goes to it
		dwarf_take(arg, u.adding)
		if at, ok := hold_where(arg); ok && !u.adding do go_to(at.xz)
	case .Keep: keep(arg)
	case .Only: u.only_kept, u.list_scroll = !u.only_kept, 0
	case .Whole: u.whole ~= {arg}
	case .Crowd:   // the list, opened on those who need the player, or on those kept in view
		u.list, u.by, u.only_kept, u.list_scroll, u.typing = .Dwarves, 0, arg == 1, 0, false
		u.whole, u.folded = {0}, {}
		clear(&u.find)
	case .Find:
		u.typing = true
		if u.window != nil do _ = sdl.StartTextInput(u.window)
	case .Menu: u.menu = true
	case .Back: u.menu = false
	case .Quit: u.running^ = false
	case .Leave:   // out of play: the frame loop ends, and the way through goes on from there (main.odin)
		leaving = Leave(arg)
		u.running^ = false
	case .Door_Move, .Door_Pick, .Door_Go, .Door_Back, .Draw, .Stop, .Rebind, .Keys_Back, .Chart_Lens, .Chart_Lenses, .Chart_Zoom, .Chart_Home, .Isle_Depth, .Isle_Row, .Isle_Take, .Found, .Roam, .Mass_Leave, .Site, .Site_Row, .Party_Who, .Party_Move, .Draw_Dwarf, .Draw_Party, .Set_Out:   // before play (door_act)
	case .Scale:
		u.scale = arg
		play_keep()
	case .Said:   // a message leads to where it happened, and to the dwarf it is about (I4)
		if arg < len(u.said) && u.said[arg].placed {
			if u.said[arg].who >= 0 do dwarf_take(u.said[arg].who)
			go_to(u.said[arg].at.xz)
		}
	case .Wrong:   // an alert leads to its cause; one that counts dwarves takes them in the hand (I14)
		if arg < len(u.wrong) && u.wrong[arg].placed {
			m := u.wrong[arg]
			if m.need >= 0 {
				who := make([dynamic]int, context.temp_allocator)
				for v, i in u.need do if int(v) == m.need do append(&who, i)
				dwarves_take(who[:])
				if at, ok := several_middle(); ok do go_to(at)
			} else do go_to(m.at.xz)
			if strings.has_prefix(m.id, "died-") do alert_clear(m.id)   // a death is told until it is looked at
		}
	case .Escape:   // closes the topmost thing (I6); with nothing open, it opens the menu
		switch {
		case u.typing: typing_end()
		case u.menu: u.menu = false
		case u.afoot^ && u.captured^:
			u.captured^ = false
			if u.window != nil do _ = sdl.SetWindowRelativeMouseMode(u.window, false)
		case u.lenses: u.lenses = false
		case u.list != .None: u.list = .None
		case a.marking: mark_clear(a)
		case bar.tool != .None: tool_take(bar.tool)
		case u.hand.kind != .None: hand_drop()
		case: u.menu = true
		}
	}
	typing = u.typing
}

typing_end :: proc() {
	play.typing, typing = false, false
	if play.window != nil do _ = sdl.StopTextInput(play.window)
}

// An event, before the game sees it: true where it was the interface's.
play_event :: proc(e: ^sdl.Event) -> bool {
	u, a := &play, play.a
	if u.plain do return false
	held := u.afoot^ && u.captured^   // the mouse turns the head
	if !u.still do u.adding = shift_held()
	#partial switch e.type {
	case .KEY_DOWN:
		if u.typing {
			#partial switch e.key.scancode {
			case .BACKSPACE: builtin.resize(&u.find, len(without_last(string(u.find[:]))))
			case .ESCAPE, .RETURN: typing_end()
			}
			return true
		}
		for b in BINDS do if b.key == e.key.scancode && b.views <= .Menu && (b.views == .Menu) == u.menu && (b.views != .Above || !u.afoot^) && (b.views != .Afoot || u.afoot^) {
			if !e.key.repeat || b.held do play_act(b.act, b.shifted if e.key.mod & sdl.KMOD_SHIFT != {} else b.arg)
			return true
		}
		return u.menu
	case .TEXT_INPUT:
		if u.typing do append(&u.find, string(e.text.text))
		u.list_scroll = 0
		return u.typing
	case .MOUSE_BUTTON_DOWN:
		if held do return false
		at := [2]f32{e.button.x, e.button.y}*u.ratio
		hot, solid, _ := screen_over(&screen, at)
		if u.typing && !(hot >= 0 && screen.items[hot].act == .Find) do typing_end()
		if !solid {
			if u.owner == .None do u.owner, u.press = .World, at
			return u.owner != .World
		}
		if u.owner == .None do u.owner = .Panel
		if e.button.button == sdl.BUTTON_LEFT && hot >= 0 && u.owner == .Panel {
			it := screen.items[hot]
			u.pressed, u.pressed_arg, u.pressing = it.act, it.arg, true
			if it.act == .Cut_Drag do u.drag = .Cut
			if it.act == .Thumb do u.drag, u.drag_from, u.drag_scroll = .List if it.area == .List else .Card, at.y, u.list_scroll if it.area == .List else u.card_scroll
		}
		return u.owner == .Panel
	case .MOUSE_BUTTON_UP:
		owner := u.owner
		if pointer_buttons() == {} do u.owner = .None
		if held || owner == .None do return false
		at := [2]f32{e.button.x, e.button.y}*u.ratio
		left := e.button.button == sdl.BUTTON_LEFT
		if owner == .Panel {
			if left && u.drag == .None && u.pressing {
				if hot, _, _ := screen_over(&screen, at); hot >= 0 && screen.items[hot].act == u.pressed && screen.items[hot].arg == u.pressed_arg do play_act(u.pressed, u.pressed_arg)
			}
			if left do u.drag, u.pressing = .None, false
			return true
		}
		if !left || u.afoot^ do return false
		if tool_marks() {   // a tool is in the hand: the box is its order
			if a.marking {
				mark_end(a)
				tool_give(a)
			}
		} else if a.marking {   // a block was under the press: a click picks up what it is part of, a drag the box it marked
			mark_end(a)
			if lo, hi, _, _ := mark_box(a); lo != hi {
				if who := dwarves_in(lo, hi); len(who) > 0 {   // a box dragged over dwarves takes them, and with Shift adds them to the hand
					all := make([dynamic]int, context.temp_allocator)
					if u.adding && (u.hand.kind == .Dwarf || u.hand.kind == .Dwarves) do append(&all, ..u.several[:])
					for i in who do if !slice.contains(all[:], i) do append(&all, i)
					dwarves_take(all[:])
					mark_clear(a)
				} else do hand_take({kind = .Box, island = island_at(f64(lo.x) + 0.5, f64(lo.z) + 0.5), block = lo, lo = lo, hi = hi, feature = -1})
			} else {
				hand_pick({block = lo, ok = true, exact = true}, at/{screen.w, screen.h})
			}
		} else if linalg.length(at - u.press) < 6*u.ratio {   // the ground beyond the block volume, a dwarf, an animal, or nothing
			hand_pick(pick_far(u.eye, view_ray(u.yaw, u.pitch, u.fov, u.aspect, at/{screen.w, screen.h}), above_level(a)), at/{screen.w, screen.h})
		}
		return true
	case .MOUSE_WHEEL:
		if held do return false
		_, solid, on := screen_over(&screen, u.pointer)
		if !solid do return u.owner == .Panel
		#partial switch screen.items[on].area {
		case .List: u.list_scroll -= e.wheel.y*px(14)
		case .Hand: u.card_scroll -= e.wheel.y*px(8)
		case .Ground: if e.wheel.y != 0 do play_act(.Cut_Move, 1 if e.wheel.y > 0 else -1)
		}
		return true
	}
	return false
}

// ---- parts ----------------------------------------------------------------------------------

part :: proc(p: Part_Kind, r: Rect, text := "", style := Style.Body, colour := Colour{}, state: bit_set[State] = {}, act := Act.None, arg := 0, key := "", id := "", tip := "") -> ^Screen_Part {
	append(&screen.items, Screen_Part{part = p, area = play.area, rect = r, clip = play.clip, text = text, style = style, colour = colour, state = state, act = act, arg = arg, key = key, id = id, tip = tip})
	return &screen.items[len(screen.items) - 1]
}
line_of :: proc(style: Style) -> f32 { return ui.baked[style].line }

// Words at a place: one line as wide as it is, or broken to a width. Returns how high they stand.
words :: proc(x, y: f32, text: string, style := Style.Body, colour := Colour{}, id := "", wide: f32 = 0, state: bit_set[State] = {}) -> f32 {
	if wide > 0 {
		h := text_high(style, text, wide)
		part(.Text, {x, y, wide, h}, text, style, colour, state + {.Wrap}, id = id)
		return h
	}
	part(.Text, {x, y, text_wide(style, text), line_of(style)}, text, style, colour, state, id = id)
	return line_of(style)
}

// A button for an act, with that act's key written on it.
button :: proc(r: Rect, text: string, act: Act, arg := 0, held := false, id := "", tip := "", main := false) {
	state: bit_set[State]
	if held do state += {.Held}
	if main do state += {.Main}
	part(.Button, r, text, .Body, {}, state, act, arg, key_for(act, arg), id, tip)
}

// ---- words of the place and the day ----------------------------------------------------------

// The place under the view: the named place it is at, or which way it lies from the nearest.
place_title :: proc(at: [3]f64) -> string {
	f := island_near(at.x, at.z)
	if f == nil || off_island(f, at.x, at.z) > 1500 do return "The open sea"
	bound(f)
	x, z := at.x - f64(region.origin.x), at.z - f64(region.origin.y)
	i, d := place_near(x, z)
	if i < 0 do return "An island with no name yet"
	name := places[i].name
	if d < GATHER do return sentence(name)[:len(name)]
	c := candidates[places[i].c]
	return fmt.tprintf("%s of %s", sentence(compass(x - c.at.x, z - c.at.y))[:len(compass(x - c.at.x, z - c.at.y))], name)
}

// A point of the world in the picture, in pixels, where it is in front of the eye.
project :: proc(p: [3]f64) -> (at: [2]f32, ok: bool) {
	u := &play
	rel := [3]f32{f32(p.x - u.eye.x), f32(p.y - u.eye.y), f32(p.z - u.eye.z)}
	rel.y -= (rel.x*rel.x + rel.z*rel.z)/(2*EARTH)   // as the world is drawn (drawn, shaders.metal)
	forward := look_dir(u.yaw, u.pitch)
	right := [3]f32{math.cos(u.yaw), 0, math.sin(u.yaw)}
	up := linalg.cross(right, forward)
	d := linalg.dot(rel, forward)
	if d < 1 do return
	tan_y := math.tan(math.to_radians(u.fov)/2)
	at = {(0.5 + 0.5*linalg.dot(rel, right)/(d*tan_y*u.aspect))*screen.w, (0.5 - 0.5*linalg.dot(rel, up)/(d*tan_y))*screen.h}
	return at, at.x > 0 && at.y > 0 && at.x < screen.w && at.y < screen.h
}

// ---- the frame ------------------------------------------------------------------------------

// List the screen's parts for this frame, and say which the pointer is on. `pointer` is in the
// picture's pixels; `boxes` are the frame's animals, for the pointer to find one among.
play_frame :: proc(wide, high: f32, pointer: [2]f32, dt: f64, hour, day: f32, date: Date, eye: [3]f64, yaw, pitch, fov: f32, boxes: []Box) {
	play.date = date
	u, a, s := &play, play.a, &screen
	clear(&s.items)
	clear(&ui.quads)
	s.w, s.h, s.hot = wide, high, -1
	u.eye, u.yaw, u.pitch, u.fov, u.hour, u.day, u.aspect = eye, yaw, pitch, fov, hour, day, wide/max(high, 1)
	u.now += dt
	u.rest = u.rest + dt if pointer == u.pointer else 0
	u.pointer = pointer
	if u.plain do return
	ui_bake(u.scale if u.scale != 0 else scale_for(high))
	above := !u.afoot^

	// What was told since the last frame, the hold's log among it (say, hold.odin).
	if sync.try_lock(&told.mutex) {
		for l in told.lines do append(&u.said, Said{l.text, l.at, l.placed, u.now, l.who, l.more})
		clear(&told.lines)
		sync.unlock(&told.mutex)
	}

	// The view goes where it was sent, or follows the dwarf in the hand; the hand holds what the hold has selected.
	if who := hold_selected(); who >= 0 && (u.hand.kind != .Dwarf || u.hand.dwarf != who) do hand_take({kind = .Dwarf, dwarf = who, feature = -1})
	else if who < 0 && u.hand.kind == .Dwarf do hand_take({})
	if u.following && u.hand.kind == .Dwarf {
		if at, ok := hold_where(u.hand.dwarf); ok do a.at.xz += (at.xz - a.at.xz)*(1 if u.still else min(1, 6*dt))
	} else if u.going {
		a.at.xz += (u.goal - a.at.xz)*min(1, 7*dt)
		if linalg.length(u.goal - a.at.xz) < 0.5 do u.going = false
	}
	if above && !a.marking {   // the hand's thing is what is marked in the world
		t := u.hand
		a.marked = t.kind != .None && t.kind != .Place && t.kind != .Animal && t.kind != .Dwarf && t.kind != .Dwarves && t.island != nil
		if a.marked do a.mark = {t.lo, t.hi}
	}
	u.animal = {}
	if above && a.shown {
		ray := view_ray(yaw, pitch, fov, u.aspect, a.pointer)
		u.animal.row, u.animal.at, u.animal.nest, u.animal.ok = animal_under(boxes, eye, ray, 6*math.tan(math.to_radians(fov)/2)/high)
		if u.animal.ok && hold_aimed(u.w, eye, ray, 4*linalg.length(a.at - eye) + 600, a) >= 0 do u.animal = {}   // a dwarf stands before it: no dwarf is a bird, whatever its cloth's colour
	}
	lens_follow()
	bar_frame()

	u.place_foot, u.wrong_foot, u.ground, u.beds = 0, 0, {}, {}
	crowd_read()
	if above do labels_build()
	place_build()
	said_build()
	wrong_build()
	crowd_build()
	if above && u.list == .None {
		ground_build()
		lenses_build()
	}
	hand_build()
	bar_build()
	lists_build()
	if u.list == .Places do places_build()
	if u.list == .Dwarves do dwarves_build()
	if above do lesson_build()
	if u.menu do menu_build()

	s.hot, _, _ = screen_over(s, pointer)
	if u.owner == .World || u.afoot^ && u.captured^ do s.hot = -1
	if u.pressing && u.drag == .None && (s.hot < 0 || s.items[s.hot].act != u.pressed || s.items[s.hot].arg != u.pressed_arg) do s.hot = -1
	tip_build()
	screen_draw(s)
}

// The names of the island's places, standing on the land where each lies.
labels_build :: proc() {
	u := &play
	u.area = .World
	f := island_near(u.a.at.x, u.a.at.z)
	if f == nil do return
	for p in f.places {
		c := f.candidates[p.c]
		at, ok := project({c.at.x + f64(f.region.origin.x), f64(c.top), c.at.y + f64(f.region.origin.y)})
		if !ok do continue
		name := sentence(p.name)[:len(p.name)]
		w := text_wide(.Name, name)
		chosen := u.hand.kind == .Place && u.hand.place == p.c && u.hand.island == f
		r := Rect{math.round(at.x - w/2), math.round(at.y - line_of(.Name)), w, line_of(.Name)}
		part(.Fill, {r.x - px(2), r.y, r.w + px(4), r.h}, colour = LOOK.said)
		part(.Text, r, name, .Name, LOOK.brass if chosen else LOOK.chalk, {}, .Row, p.c, id = "label", tip = sentence(c.why))
	}
	crowd_marks()   // the dwarves in the hand, and those who need the player, marked where they stand
	stair_marks()   // and how deep each step of a stair the tool would mark lies (bar.odin)
}

// Top left: the place, the date, and the clock.
place_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Place
	title := place_title(u.p.pos if u.afoot^ else u.a.at)
	date := date_words(u.date)
	at := u.p.pos if u.afoot^ else u.a.at
	if f := island_near(at.x, at.z); f != nil && off_island(f, at.x, at.z) <= 1500 {   // the island it is on, by its name (making.odin), before the day
		if name := isle_name(f.island.id) if f.island.id < len(archipelago) else "The mainland"; name != "" do date = fmt.tprintf("%s, %s", name, date)
	}
	hour := fmt.tprintf("%02d:%02d", int(u.date.hour), int(u.date.hour*60)%60)   // the hour the dwarves live by, whatever the sun was turned to
	first := button_wide("Running at 00:00", key_for(.Pause))
	names := [3]string{"Slow", "Fast", "Fastest"}
	ids := [3]string{"clock.slow", "clock.fast", "clock.fastest"}
	tips := [3]string{"The world runs at its own pace.", "The world runs three times as fast.", "The world runs six times as fast."}
	row := first
	for n, i in names do row += px(L.gap) + button_wide(n, key_for(.Speed, i))
	// The weather over the view, under the date: what falls, the air and the wind, by the island's own climate (weather.odin).
	sky, why := "", ""
	if f := island_near(at.x, at.z); f != nil {
		was := bound(f)
		sky, why = weather_line(u.sky), weather_why(u.sky, u.sky_stand, u.date)
		bound(was)
	}
	inner := max(row, text_wide(.Great, title), text_wide(.Body, date), text_wide(.Body, sky))
	r := Rect{px(L.margin), px(L.margin), inner + 2*px(L.pad.x), 2*px(L.pad.y) + line_of(.Great) + px(1) + 2*line_of(.Body) + px(3) + px(L.button)}
	part(.Panel, r, id = "place")
	x, y := r.x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(x, y, title, .Great, id = "place.title") + px(1)
	y += words(x, y, date, .Body, L.ash, "place.date")
	y += words(x, y, sky, .Body, L.chalk if u.sky.rain > 0 else L.ash, "place.weather")
	part(.Head, {x, y - line_of(.Body), inner, line_of(.Body)}, tip = why)   // over the words, so the pointer resting on them is told why
	y += px(3)
	paused := u.clock.paused
	button({x, y, first, px(L.button)}, fmt.tprintf("%s at %s", "Paused" if paused else "Running", hour), .Pause, 0, paused, "clock.pause", "Stop the world, or let it go on. You can look and give orders while it stands still.")
	x += first + px(L.gap)
	for n, i in names {
		w := button_wide(n, key_for(.Speed, i))
		button({x, y, w, px(L.button)}, n, .Speed, i, !paused && u.clock.speed == i, ids[i], tips[i])
		x += w + px(L.gap)
	}
	u.place_foot, u.place_wide = r.y + r.h, r.w
}

// Left, under the place: what happened, newest lowest, fading.
said_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Said
	first := len(u.said)
	for first > 0 && len(u.said) - first < SAID_MOST && (u.still || u.now - u.said[first - 1].since < SAID_FOR) do first -= 1
	if first == len(u.said) do return
	// A message is one line, as wide as its words and no wider than the band's most; the whole of it
	// is said beside the pointer that rests on it, and a click leads to where it happened.
	x, y := px(L.margin), max(u.place_foot + px(2), px(L.said_top))
	most := px(L.said_wide) - 2*px(L.pad.x)
	wide := f32(0)
	for m in u.said[first:] do wide = max(wide, min(text_wide(.Body, m.text), most))
	h := line_of(.Body)
	part(.Band, {x, y, wide + 2*px(L.pad.x), f32(len(u.said) - first)*h + 2*px(2)})
	y += px(2)
	for m, i in u.said[first:] {
		left := 1.0 if u.still else clamp((SAID_FOR - (u.now - m.since))/2, 0, 1)   // its last two seconds
		older := 1.0 if i == len(u.said) - first - 1 else 0.72
		line := fit(.Body, m.text, most)
		it := part(.Text, {x + px(L.pad.x), y, wide, h}, line, .Body, {L.chalk.r, L.chalk.g, L.chalk.b, u8(255*left*older)}, {.Shadow}, id = "said")
		whole := m.more if m.more != "" else m.text if line != m.text else ""
		if m.placed do it.act, it.arg, it.tip = .Said, first + i, fmt.tprintf("%s%sClick to go there.", whole, " " if whole != "" else "")
		else do it.tip = whole
		y += h
	}
}

// Top right: the stores. What the hold has is what lies in its stockpiles: each kind beside a
// block of itself, the stones by their rock and the timber together. What lies loose is said, and is
// not counted; with nothing marked to store on, it says how to mark it. Returns where the alerts
// may begin under it.
stores_build :: proc() -> (foot: f32) {
	u, L := &play, &LOOK
	s := &watch.seen
	foot = px(L.margin)
	loose, timber := 0, 0
	Row :: struct { mat: Mat, name: string, n: int }
	rows := make([dynamic]Row, context.temp_allocator)
	food := make([dynamic]Row, context.temp_allocator)
	for n, m in s.store do if n > 0 {
		if is(m, FOOD) do append(&food, Row{m, capital(store_words(m)), int(n)})
		else if is_stuff(m, .Timber) do timber += int(n)
		else do append(&rows, Row{m, sentence(mat_words(m))[:len(mat_words(m))], int(n)})
	}
	for n in s.loose do loose += int(n)
	if timber > 0 do append(&rows, Row{.Timber, "Timber", timber})
	if len(rows) == 0 && len(food) == 0 && loose == 0 && len(s.zones) == 0 do return
	slice.sort_by(rows[:], proc(a, b: Row) -> bool { return a.n > b.n })
	slice.sort_by(food[:], proc(a, b: Row) -> bool { return a.n > b.n })
	if len(rows) > 4 do builtin.resize(&rows, 4)
	if len(food) > 4 do builtin.resize(&food, 4)
	note := fmt.tprintf("%d loose: no stockpile", loose) if len(s.zones) == 0 && loose > 0 else "No stockpile yet" if len(s.zones) == 0 else fmt.tprintf("%d lie loose, not counted", loose) if loose > 0 else ""
	// How long the food stored lasts those alive (needs.odin): the one figure a player plans a season by.
	days := s.food_days
	lasts := "No food stored" if days <= 0 else "Food for under a day" if days < 0.75 else fmt.tprintf("Food for %s", days_words(days))
	// With none stored, food that lies loose is still eaten: the sacks the party brought, before any stockpile is marked. It is said, and is no alarm.
	lying := f32(0)
	for n, m in s.loose do if n > 0 && is(m, FOOD) do lying += f32(n)*FOODS[food_of(m)].feeds
	lying /= f32(max(hold_living(), 1))*WANTS[.Food].falls
	loose_only := days <= 0 && lying >= 0.75
	if loose_only do lasts = fmt.tprintf("Food for %s, loose", days_words(lying))
	fed := hold_living() > 0 && s.tick > 0
	w := px(78)
	line := line_of(.Body)
	high := 2*px(L.pad.y) + line_of(.Small) + px(1) + f32(max(len(rows) + len(food), 1))*line + (px(1.5) + line_of(.Small) + px(0.5) if fed else 0) + (px(1) + line_of(.Small) if note != "" else 0)
	x, y := screen.w - px(L.margin) - w, px(L.margin)
	part(.Panel, {x, y, w, high}, id = "stores", tip = "What lies in the hold's stockpiles. Things lying anywhere else are not counted until they are carried in.")
	u.crowd_right = x
	cx := x + px(L.pad.x)
	y += px(L.pad.y)
	y += words(cx, y, "Stores", .Small, L.ash, "stores.title") + px(1)
	inner := w - 2*px(L.pad.x)
	put :: proc(cx, y, inner, line: f32, r: Row) {
		L := &LOOK
		part(.Block, {cx, y + math.round((line - px(L.block))/2), px(L.block), px(L.block)}, id = "stores.block").mat = r.mat
		count := fmt.tprint(r.n)
		words(cx + px(L.block) + px(2.5), y, fit(.Body, r.name, inner - px(L.block) - px(4) - text_wide(.Figure, count)), .Body, {}, "stores.kind")
		words(cx + inner - text_wide(.Figure, count), y, count, .Figure, {}, "stores.count")
	}
	if len(rows) == 0 && len(food) == 0 do y += words(cx, y, "Nothing stored", .Body, L.ash, "stores.none")
	for r in rows {
		put(cx, y, inner, line, r)
		y += line
	}
	if fed {   // the food, under its own line
		y += px(1.5)
		y += words(cx, y, lasts, .Small, L.brass if loose_only else L.cinnabar if days <= 0 else L.brass if days < 1.5 else L.ash, "stores.food") + px(0.5)
		part(.Head, {cx, y - line_of(.Small) - px(0.5), inner, line_of(.Small)}, tip = "How long the food in the stockpiles feeds the dwarves alive: each eats about twice a day. Food lying loose is eaten too, and is not counted here.")
	}
	for r in food {
		put(cx, y, inner, line, r)
		y += line
	}
	if note != "" do y += px(1) + words(cx, y, note, .Small, L.brass if len(s.zones) == 0 else L.ash, "stores.loose")
	return px(L.margin) + high + px(2)
}

// Top right: the stores, when the hold has any, then what is wrong, worst first. Each leads to its cause.
wrong_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Wrong
	u.crowd_right = screen.w - px(L.margin)
	if u.list != .None {   // a list stands where the alerts do; they show again when it is shut
		u.crowd_right = list_rect().x
		return
	}
	top := stores_build()   // the stores first, then what is wrong (I1)
	if len(u.wrong) == 0 do return
	w := clamp(screen.w - 2*px(L.margin) - u.place_wide - 2*px(2) - crowd_least(), px(L.wrong_least), px(L.wrong_wide))   // narrower where the picture is, to leave the dwarves their place
	x, y := screen.w - px(L.margin) - w, top
	u.crowd_right = min(u.crowd_right, x) if top > px(L.margin) + px(L.button) else x   // beside the dwarves only where it stands at their height
	show := text_wide(.Body, "show")
	wide := w - 2*px(L.pad.x) - px(L.sign) - px(2.5) - show - px(6)
	high := 2*px(L.pad.y)
	for m in u.wrong do high += text_high(.Body, m.text, wide) + 2*px(1.5)
	part(.Panel, {x, y, w, high}, id = "wrong")
	u.wrong_foot = y + high
	y += px(L.pad.y)
	for m, i in u.wrong {
		h := text_high(.Body, m.text, wide) + 2*px(1.5)
		row := part(.Row, {x + 1, y, w - 2, h}, id = "wrong.row")
		if m.placed do row.act, row.arg, row.tip = .Wrong, i, "Go to them, and take them in the hand." if m.need >= 0 else "Go to its cause."
		part(.Sign, {x + px(L.pad.x), y + px(1.5) + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = m.sign
		part(.Text, {x + px(L.pad.x) + px(L.sign) + px(2.5), y + px(1.5), wide, h}, m.text, .Body, {}, {.Wrap}, id = "wrong.text")
		if m.placed do part(.Text, {x + w - px(L.pad.x) - show, y + px(1.5), show, line_of(.Body)}, "show", .Body, L.ash)
		y += h
	}
}

// A column of the ground drawn bed by bed: the runs between `top` and `top - span` metres in a
// rectangle, each in its own material, with its name beside it where there is room. What stands
// over `cut` is dimmed: it is not drawn in the world.
column_put :: proc(runs: []Run, col: Rect, top, span, cut: i32, names_left: bool, water: f32 = 1e9, id := "bed") {
	L := &LOOK
	per := col.h/f32(span)
	if len(runs) > 0 {   // a dark line round the ground, from its top down
		y0 := col.y + math.round(f32(top - runs[0].top)*per)
		part(.Fill, {col.x - 1, y0 - 1, col.w + 2, col.y + col.h - y0 + 2}, colour = L.pit)
	}
	label := f32(-1e9)   // where the last name ended
	line := line_of(.Small)
	cut_y := col.y + f32(top - cut)*per
	if depth := f32(top) - water; water < 1e8 && depth > 0 && depth < f32(span) && abs(col.y + depth*per - cut_y) > line {   // the water in the ground has first call on a name's place, after the cut's
		y := col.y + math.round(depth*per)
		name := "water in the ground"
		x := col.x - px(3) - text_wide(.Small, name) if names_left else col.x + col.w + px(3)
		part(.Text, {x, y - line/2, text_wide(.Small, name), line}, name, .Small, L.verdigris, id = "water")
		label = y + line/2
	}
	water_y := label - line/2
	soil := f32(-1)   // where a run of soils began
	for r, i in runs {
		y0, y1 := col.y + math.round(f32(top - r.top)*per), col.y + math.round(f32(top - r.foot)*per)
		if y1 <= y0 do continue
		rect := Rect{col.x, y0, col.w, y1 - y0}
		thick := r.top - r.foot
		tip := fmt.tprintf("%s, %d m thick, from %d to %d m over the sea", sentence(mat_words(r.mat))[:len(mat_words(r.mat))], thick, r.foot, r.top)
		dim := Colour{120, 126, 132, 255} if r.foot >= cut else Colour{}
		it: ^Screen_Part
		if r.mat == .Air {
			it = part(.Fill, rect, colour = L.water if r.sea else L.pit, id = id)
			tip = fmt.tprintf("%s, %d m deep", "The sea" if r.sea else "Open: dug out, or a hollow", thick)
		} else {
			it = part(.Bed, rect, colour = dim, id = id)
			it.mat = r.mat
		}
		it.tip, it.act = tip, .Cut_Drag if names_left else .None
		// Its name: the soils together as one, where a single block of each is too thin to name.
		name := "the sea" if r.sea else "open" if r.mat == .Air else mat_words(r.mat)
		a, b := y0, y1
		if soil_like(r.mat) {
			if soil < 0 do soil = y0
			if i + 1 < len(runs) && soil_like(runs[i + 1].mat) do continue
			a, name = soil, "soil" if soil < y0 else name
		}
		soil = -1
		y := math.round((a + b)/2 - line/2)
		if y < label || y + line > col.y + col.h + line/2 || b - a < line*0.45 || y < water_y + line && y + line > water_y do continue
		x := col.x - px(3) - text_wide(.Small, name) if names_left else col.x + col.w + px(3)
		part(.Text, {x, y, text_wide(.Small, name), line}, name, .Small, L.ash, id = "bed.name")
		label = y + line
	}
	if cut < top && cut > top - span && water < 1e8 && f32(top) - water > 0 do part(.Mark, {col.x, col.y + math.round((f32(top) - water)*per) - 1, col.w, 2}, colour = L.verdigris)
}

// Right: the ground here. The column of the beds under the view's middle with the cut marked on
// it, which the pointer drags; the cut's keys; the lenses; and the walk.
ground_build :: proc() {
	u, a, L := &play, play.a, &LOOK
	u.area = .Ground
	w := px(L.ground_wide)
	inner := w - 2*px(L.pad.x)
	head := px(L.key_high) + 2*px(L.chip_pad.y)
	controls := 4*px(L.button) + 3*px(L.gap)
	fixed := 2*px(L.pad.y) + head + px(2.5) + px(4) + controls
	foot := screen.h - hand_foot()
	least := max(px(L.margin), u.wrong_foot + px(2))
	room := foot - least - fixed   // what the alerts over it leave the column
	if room < px(L.beds_high[0])/2 do return   // none worth the name: the alerts have its place until they clear, and its keys still work
	high := min(clamp(foot - px(L.ground_top) - fixed, px(L.beds_high[0]), px(L.beds_high[1])), room)
	y := max(least, min(px(L.ground_top), foot - fixed - high))
	r := Rect{screen.w - px(L.margin) - w, y, w, fixed + high}
	u.ground = r
	part(.Panel, r, id = "ground")
	x := r.x + px(L.pad.x)
	y += px(L.pad.y)
	part(.Text, {x, y + math.round((head - line_of(.Small))/2), inner, line_of(.Small)}, "The ground here", .Small, L.ash, id = "ground.title")
	chip := button_wide("Cut", key_for(.Cut), .Small, L.chip_pad.x)
	part(.Chip, {x + inner - chip, y, chip, head}, "Cut", .Small, {}, {.Chosen} if a.cut else {}, .Cut, 0, key_for(.Cut), "ground.cut", "Cut the world open at a level, so the ground under the trees and the inside of a hill show; or show it whole.")
	y += head + px(2.5)

	// The column: as much of the ground as holds its top and the cut, held still while the cut is dragged.
	bx, bz := i32(math.floor(a.at.x)), i32(math.floor(a.at.z))
	top_of := ground_top(a.at.x, a.at.z)
	if u.drag != .Cut do u.column[0], u.column[1] = column_fit(top_of, a.level if a.cut else top_of)
	top, span := u.column[0], u.column[1]
	col := Rect{x + inner - px(L.column_wide), y, px(L.column_wide), high}
	u.beds = col
	if u.drag == .Cut && !u.still {   // the pointer holds the mark: over the column's top the world is whole again
		level := f32(top) - (u.pointer.y - col.y)/col.h*f32(span)
		a.cut, a.follow = level < f32(top) + f32(span)/30, false
		a.level = clamp(i32(math.round(level)), top - span, top)
		learn(.Cut)
	}
	runs := column_runs(u.w, bx, bz, top, top - span)
	table := f32(1e9)
	if f := island_at(a.at.x, a.at.z); f != nil && is_formed(f) && top_of > SEA_LEVEL {
		bound(f)
		p := Point{x = a.at.x - f64(region.origin.x), z = a.at.z - f64(region.origin.y), cell = LAND_CELL}
		if t := FIELDS[.Water_Table].at(&p); t < 1000 do table = f32(top_of) - t
	}
	column_put(runs, col, top, span, a.level if a.cut else max(i32), true, table)
	if a.cut {
		at := col.y + math.round(clamp(f32(top - a.level)/f32(span), 0, 1)*col.h)
		words_cut := fmt.tprintf("cut at %d m", a.level)
		tw := text_wide(.Small_Bold, words_cut)
		lx := col.x - px(2) - tw - px(2)
		part(.Fill, {r.x + px(L.pad.x) - px(2), at - px(3), inner + px(4), px(6)}, colour = {}, act = .Cut_Drag, id = "ground.handle", tip = "Drag to move the cut. It stands at this height over the sea.")
		part(.Mark, {r.x + px(L.pad.x) - px(2), at - math.round(px(L.bar)/2), inner + px(4), px(L.bar) if u.drag != .Cut else 2*px(L.bar)}, id = "ground.mark")
		part(.Fill, {lx - px(2), at - line_of(.Small_Bold)/2, tw + px(4), line_of(.Small_Bold)}, colour = L.basalt)
		part(.Text, {lx, at - line_of(.Small_Bold)/2, tw, line_of(.Small_Bold)}, words_cut, .Small_Bold, L.brass, id = "ground.level")
		if u.drag == .Cut {   // while it is dragged, what the cut stands in
			in_words := "over the ground"
			for run in runs do if a.level <= run.top && a.level > run.foot do in_words = fmt.tprintf("in %s, %d m under the ground", "the sea" if run.sea else mat_words(run.mat), top_of - a.level)
			tip := fmt.tprintf("%d m over the sea, %s", a.level, in_words)
			tw = text_wide(.Small, tip) + 2*px(L.chip_pad.x)
			part(.Tip, {r.x - px(2) - tw, at - (line_of(.Small) + 2*px(L.chip_pad.y))/2, tw, line_of(.Small) + 2*px(L.chip_pad.y)}, tip, .Small, id = "ground.drag")
		}
	}
	y += high + px(4)
	half := math.floor((inner - px(L.gap))/2)
	button({x, y, half, px(L.button)}, "Up", .Cut_Move, 1, false, "ground.up", "Raise the cut a block. With Shift, eight.")
	button({x + inner - half, y, half, px(L.button)}, "Down", .Cut_Move, -1, false, "ground.down", "Lower the cut a block. With Shift, eight.")
	y += px(L.button) + px(L.gap)
	button({x, y, inner, px(L.button)}, "Follow the ground", .Follow, 0, a.follow, "ground.follow", "The cut keeps three blocks over the ground under the view's middle as the view moves.")
	y += px(L.button) + px(L.gap)
	button({x, y, inner, px(L.button)}, "Lenses", .Lenses, 0, u.lenses || u.lens >= 0 || a.bare, "ground.lenses", "How the land is seen: without its leaves, or painted with one of its fields.")
	u.walk_row = {x, y, inner, px(L.button)}
	y += px(L.button) + px(L.gap)
	button({x, y, inner, px(L.button)}, "Walk here", .Walk, 0, false, "ground.walk", "Stand on the ground under the view's middle, on the cut where the world is cut there.")
}

// A lens's colours in words: a ramp from one end to the other, or each kind the island has.
legend_build :: proc(x, y, wide: f32, lens: Lens_Row) -> f32 {
	u, L := &play, &LOOK
	paint := FIELDS[lens.field]
	from, y := y, y
	byte :: proc(c: [3]f32) -> Colour { return {u8(clamp(c.r, 0, 1)*255), u8(clamp(c.g, 0, 1)*255), u8(clamp(c.b, 0, 1)*255), 255} }
	y += words(x, y, lens.says, .Small, L.ash, "lens.says", wide) + px(2)
	f := island_near(u.a.at.x, u.a.at.z)
	if f == nil do return y - from
	bound(f)
	row :: proc(x, y, wide: f32, c: Colour, name: string) -> f32 {
		part(.Fill, {x, y + px(0.75), px(LOOK.block), px(LOOK.block)}, colour = c)
		words(x + px(LOOK.block) + px(2), y, name, .Small, {}, "lens.kind")
		return line_of(.Small)
	}
	switch paint.paint {
	case .Ramp, .Log:
		STEPS :: 32
		for i in 0..<STEPS do part(.Fill, {x + math.floor(wide*f32(i)/STEPS), y, math.ceil(wide/STEPS), px(3)}, colour = byte(math.lerp(paint.from_colour, paint.to_colour, f32(i)/(STEPS - 1))))
		y += px(3) + px(1)
		lo, hi := paint.lo, paint.hi
		if paint.paint == .Log do lo, hi = math.pow(10, lo), math.pow(10, hi)
		low, high := fmt.tprintf("%.4g%s", lo, paint.unit), fmt.tprintf("%.4g%s", hi, paint.unit)
		if lens.field == .Livable do low, high = "not", "livable"
		words(x, y, low, .Small, {}, "lens.low")
		words(x + wide - text_wide(.Small, high), y, high, .Small, {}, "lens.high")
		y += line_of(.Small)
	case .Kinds:
		rank := kinds_rank(f)
		for t, m in survey.rocks do if t.cells > 0 do y += row(x, y, wide, L.kinds[rank[m]], mat_words(m))
	case .Soils:
		for t, k in survey.soils do if t.cells > 0 do y += row(x, y, wide, byte(SOILS[k].colour), SOILS[k].name)
	case .Plants:
		for t, k in survey.plants do if t.cells > 0 do y += row(x, y, wide, byte(COMMUNITIES[k].colour), COMMUNITIES[k].name)
	case .Zones, .Wheel:
	}
	return y - from
}

// Beside the ground: the lenses' choices while they are open, and the key to the one that is on.
lenses_build :: proc() {
	u, a, L := &play, play.a, &LOOK
	u.area = .Lenses
	if !u.lenses && u.lens < 0 do return
	w := px(L.ground_wide)
	inner := w - 2*px(L.pad.x)
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	high := 2*px(L.pad.y)
	if u.lenses do high += line_of(.Small) + px(2.5) + chip + px(L.space) + f32(len(LENSES))*(chip + px(L.gap)) - px(L.gap)
	legend := len(screen.items)   // the key is measured by listing it, then moved to its place
	lh := f32(0)
	if u.lens >= 0 {
		lh = (shelter_legend(0, 0, inner, LENSES[u.lens].says) if LENSES[u.lens].blocks else legend_build(0, 0, inner, LENSES[u.lens])) + (px(L.space) if u.lenses else line_of(.Small) + px(1.5))
		high += lh
	}
	x := u.ground.x - px(2) - w
	y := max(px(L.margin), u.walk_row.y + px(L.button) - high)
	if y < u.place_foot + px(2) && x < px(L.margin) + px(L.hand_wide) do y = u.place_foot + px(2)
	panel := Screen_Part{part = .Panel, area = .Lenses, rect = {x, y, w, high}, id = "lenses"}
	inject_at(&screen.items, legend, panel)
	cx, cy := x + px(L.pad.x), y + px(L.pad.y)
	if u.lenses {
		cy += words(cx, cy, "Lenses", .Small, L.ash, "lenses.title") + px(2.5)
		part(.Chip, {cx, cy, inner, chip}, "Leaves off", .Body, {}, {.Chosen} if a.bare else {}, .Bare, 0, key_for(.Bare), "lens.leaves", "The woods without their leaves: the ground under them, and the stems standing on it.")
		cy += chip + px(L.space)
		for l, i in LENSES {
			part(.Chip, {cx, cy, inner, chip}, l.name, .Body, {}, {.Chosen} if u.lens == i else {}, .Lens, i, "", "lens.row", l.says)
			cy += chip + px(L.gap)
		}
		cy += px(L.space) - px(L.gap)
	} else {
		cy += words(cx, cy, LENSES[u.lens].name, .Small_Bold, L.brass, "lens.name") + px(1.5)
	}
	for &it in screen.items[legend + 1:] do if it.area == .Lenses && it.rect.x < x {   // the key, to its place
		it.rect.x += cx
		it.rect.y += cy
	}
}

// Lower left: the hand. The thing selected, in a line what it is and in the next why, then its
// depths under tabs, then what can be done with it. The orders bar's place lies under it.
hand_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Hand
	if bar_hand() do return   // a tool is held, or the thing is marked ground: the order's card (bar.odin)
	t := u.hand
	if t.kind == .None do return
	if t.kind == .Dwarves {
		several_build()
		return
	}
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	foot := screen.h - hand_foot()
	title, sub, line, next := u.card.title, u.card.sub, u.card.line, ""
	says := u.card.says
	need := -1
	if t.kind == .Dwarf {   // a dwarf goes on with its day: its card is read afresh (dwarf_says, crowd.odin)
		if t.dwarf >= hold_count() do return
		c := dwarf_says(t.dwarf)
		title, sub, line, next = c.title, c.sub, c.line, c.next
		says[.Own], says[.Self] = c.trade, c.self
		need = int(u.need[t.dwarf])
	}
	if !u.card_open {   // shut: a dwarf's short card, and of anything else one line
		hand_short(t, title, sub, line, next, need)
		return
	}
	// Its depths: the tabs that have anything to say.
	tabs: [Depth]bool
	count := 0
	for d in Depth {
		tabs[d] = says[d] != "" || d == .Rock && u.card.column && t.island != nil
		count += int(tabs[d])
	}
	if !tabs[u.tab] do for d in Depth do if tabs[d] {
		u.tab = d
		break
	}
	head := px(L.block_large)
	text_wide_here := inner - head - px(4)
	head = max(head, line_of(.Title) + text_high(.Body, sub, text_wide_here) + (line_of(.Body) if need >= 0 else 0))
	feels := t.kind == .Dwarf && watch.seen.dwarves[t.dwarf].doing != .Dead   // a living dwarf's needs, as meters (crowd.odin)
	line_high := text_high(.Body, line, inner) + (text_high(.Body, next, inner) + px(1) if next != "" else 0) + (px(L.space) + feels_high() if feels else 0)
	tabs_high := line_of(.Body) + px(1.5) + px(2.5) if count > 0 else 0
	fixed := 2*px(L.pad.y) + head + px(L.space) + line_high + (px(L.space) + tabs_high if count > 0 else 0) + px(4) + px(L.button)
	// A card is as deep as its longest tab needs, within limits, so that changing tabs moves nothing.
	room := foot - max(u.place_foot + px(4), px(L.said_top)) - fixed
	longest := px(L.card_high[0])
	for d in Depth do if tabs[d] do longest = max(longest, text_high(.Small, says[d], inner - px(3) - (px(L.column_wide) + px(3) + px(34) if d == .Rock && u.card.column else 0)))
	depth := max(min(longest, px(L.card_high[1]), room), px(8)) if count > 0 else 0
	r := Rect{x, foot - fixed - depth, w, fixed + depth}
	part(.Panel, r, id = "hand")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	square := Rect{cx, y, px(L.block_large), px(L.block_large)}
	if t.kind == .Dwarf do bust(square, watch.seen.dwarves[t.dwarf].who, true, sign = need_sign(t.dwarf))
	else if u.card.mat != .Air do part(.Block, square, state = {.Chosen}, id = "hand.block").mat = u.card.mat
	else {
		part(.Fill, square, colour = L.brass)
		part(.Fill, {square.x + 1, square.y + 1, square.w - 2, square.h - 2}, colour = u.card.tint)
	}
	tx := cx + px(L.block_large) + px(4)
	less := button_wide("Less", key_for(.More), .Small, L.chip_pad.x)
	part(.Chip, {cx + inner - less, y, less, line_of(.Small) + 2*px(L.chip_pad.y)}, "Less", .Small, {}, {}, .More, 0, key_for(.More), "hand.less", "Shut the card: the thing stays in the hand, in a line.")
	words(tx, y, title, .Title, id = "hand.title")
	sub_high := words(tx, y + line_of(.Title), sub, .Body, L.ash, "hand.sub", text_wide_here)
	if need >= 0 {   // how it is, where that needs the player: its sign and the word for it
		row := NEEDS[need]
		ny := y + line_of(.Title) + sub_high
		part(.Sign, {tx, ny + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = row.sign
		words(tx + px(L.sign) + px(2), ny, row.word, .Bold, L.cinnabar if row.sign == .Trouble else L.brass, "hand.need")
	}
	y += head + px(L.space)
	y += words(cx, y, line, .Body, {}, "hand.line", inner)
	if next != "" do y += px(1) + words(cx, y, next, .Body, L.ash, "hand.next", inner)
	if feels do y += px(L.space) + feels_row(cx, y + px(L.space), inner, t.dwarf)
	if count > 0 {
		y += px(L.space)
		tx = cx
		for d in Depth do if tabs[d] {
			name := DEPTHS[d] if d != .Own else OWN[t.kind]
			tw := text_wide(.Body, name)
			part(.Tab, {tx, y, tw, line_of(.Body) + px(1.5)}, name, .Body, {}, {.Chosen} if d == u.tab else {}, .Depth, int(d), id = "hand.tab")
			tx += tw + px(L.tab_gap)
		}
		y += line_of(.Body) + px(1.5)
		part(.Rule, {cx, y - 1, inner, 1}, colour = L.edge)
		y += px(2.5)
		// What the tab says, scrolled where it is longer than its room; under Rock, the column it lies in.
		box := Rect{cx, y, inner, depth}
		u.clip = box
		said := says[u.tab]
		left := cx
		if u.tab == .Rock && u.card.column {
			top, span := column_fit(ground_top(f64(u.card.x) + 0.5, f64(u.card.z) + 0.5), u.card.level)
			col := Rect{cx + 1, y + 1, px(L.column_wide), depth - 2}
			column_put(column_runs(u.w, u.card.x, u.card.z, top, top - span), col, top, span, max(i32), false, id = "hand.bed")
			at := col.y + math.round((f32(top - u.card.level) - 0.5)/f32(span)*col.h)
			part(.Mark, {col.x - px(1.5), at - math.round(px(L.bar)/2), col.w + px(3), max(px(L.bar), math.round(col.h/f32(span)))}, id = "hand.level")
			left = col.x + col.w + px(3) + px(34)
		}
		wide := cx + inner - left - px(3)
		all := text_high(.Small, said, wide)
		u.card_over = max(all - depth, 0)
		u.card_scroll = clamp(u.card_scroll, 0, u.card_over)
		if u.drag == .Card do u.card_scroll = clamp(u.drag_scroll + (u.pointer.y - u.drag_from)*all/depth, 0, u.card_over)
		part(.Text, {left, y - u.card_scroll, wide, all}, said, .Small, L.ash, {.Wrap}, id = "hand.says")
		u.clip = {}
		part(.Fill, box, colour = {}, state = {.Solid})   // the wheel over it scrolls it
		if u.card_over > 0 do part(.Thumb, {cx + inner - px(1.5), y + depth*u.card_scroll/all, px(1.5), depth*depth/all}, act = .Thumb, id = "hand.thumb")
		y += depth
	}
	y += px(4)
	if t.kind == .Dwarf do hand_buttons(cx, y, "Follow", "Take the view to this dwarf, and keep it over it as it walks.")
	else do hand_buttons(cx, y, "Go there", "Put the view over it.")
}

// The hand shut (I2): of a block, a plant, water, a place or an animal, one line at the foot of the
// hand's place, what it is and where, with a small More; of a dwarf, its short card: who it is, what
// it is doing and what it waits for. The whole card is a key, a second click or More away.
hand_short :: proc(t: Thing, title, sub, line, next: string, need: int) {
	u, L := &play, &LOOK
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	foot := screen.h - hand_foot()
	more := button_wide("More", key_for(.More), .Small, L.chip_pad.x)
	chip := line_of(.Small) + 2*px(L.chip_pad.y)
	if t.kind != .Dwarf {
		high := line_of(.Body) + 2*px(2)
		r := Rect{x, foot - high, w, high}
		part(.Panel, r, id = "hand")
		cx, y := x + px(L.pad.x), r.y + px(2)
		square := Rect{cx, y + math.round((line_of(.Body) - px(L.block))/2), px(L.block), px(L.block)}
		if u.card.mat != .Air do part(.Block, square, id = "hand.block").mat = u.card.mat
		else do part(.Fill, square, colour = u.card.tint)
		tx := cx + px(L.block) + px(2.5)
		words(tx, y, title, .Bold, id = "hand.title")
		tx += text_wide(.Bold, title) + px(3)
		room := cx + inner - more - px(3) - tx
		if room > px(12) do words(tx, y, fit(.Body, sub, room), .Body, L.ash, "hand.sub")
		part(.Chip, {cx + inner - more, r.y + math.round((high - chip)/2), more, chip}, "More", .Small, {}, {}, .More, 0, key_for(.More), "hand.more", "Its card: why it is as it is, and what can be done with it.")
		return
	}
	head := px(L.block_large)
	text_wide_here := inner - head - px(4)
	head = max(head, line_of(.Title) + text_high(.Body, sub, text_wide_here) + (line_of(.Body) if need >= 0 else 0))
	feels := watch.seen.dwarves[t.dwarf].doing != .Dead
	high := 2*px(L.pad.y) + head + px(L.space) + text_high(.Body, line, inner) + (text_high(.Body, next, inner) + px(1) if next != "" else 0) + (px(L.space) + feels_high() if feels else 0) + px(3) + px(L.button)
	r := Rect{x, foot - high, w, high}
	part(.Panel, r, id = "hand")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	bust({cx, y, px(L.block_large), px(L.block_large)}, watch.seen.dwarves[t.dwarf].who, true, sign = need_sign(t.dwarf))
	tx := cx + px(L.block_large) + px(4)
	part(.Chip, {cx + inner - more, y, more, chip}, "More", .Small, {}, {}, .More, 0, key_for(.More), "hand.more", "Its card: its trade, and what it knows of itself.")
	words(tx, y, title, .Title, id = "hand.title")
	sub_high := words(tx, y + line_of(.Title), sub, .Body, L.ash, "hand.sub", text_wide_here)
	if need >= 0 {
		row := NEEDS[need]
		ny := y + line_of(.Title) + sub_high
		part(.Sign, {tx, ny + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = row.sign
		words(tx + px(L.sign) + px(2), ny, row.word, .Bold, L.cinnabar if row.sign == .Trouble else L.brass, "hand.need")
	}
	y += head + px(L.space)
	y += words(cx, y, line, .Body, {}, "hand.line", inner)
	if next != "" do y += px(1) + words(cx, y, next, .Body, L.ash, "hand.next", inner)
	if feels do y += px(L.space) + feels_row(cx, y + px(L.space), inner, t.dwarf)
	y += px(3)
	hand_buttons(cx, y, "Follow", "Take the view to this dwarf, and keep it over it as it walks.")
}

// What can be done with the thing in the hand: go to it, keep a dwarf in view, and put it down.
hand_buttons :: proc(x, y: f32, go, tip: string) {
	u, L := &play, &LOOK
	x := x
	dwarves := u.hand.kind == .Dwarf || u.hand.kind == .Dwarves
	keep, down := "Keep in view", "Put it down" if u.hand.kind != .Dwarves else "Put them down"
	room := px(L.hand_wide) - 2*px(L.pad.x) - button_wide(go, key_for(.Go)) - px(L.gap) - (px(L.gap) if dwarves else 0)
	wide :: proc(keep, down: string, dwarves: bool) -> f32 { return button_wide(down, key_for(.Escape)) + (button_wide(keep, key_for(.Keep, -1)) if dwarves else 0) }
	if wide(keep, down, dwarves) > room do down = "Put down"   // shorter words where the card is too narrow for the three
	if wide(keep, down, dwarves) > room do keep = "Keep"
	gw := button_wide(go, key_for(.Go))
	button({x, y, gw, px(L.button)}, go, .Go, 0, u.following, "hand.go", tip)
	x += gw + px(L.gap)
	if dwarves {
		kept := true
		for i in u.several do kept &&= slice.contains(u.kept[:], i)
		kw := button_wide(keep, key_for(.Keep, -1))
		button({x, y, kw, px(L.button)}, keep, .Keep, -1, kept, "hand.keep", "Keep its picture at the top of the screen, or let it go." if u.hand.kind == .Dwarf else "Keep their pictures at the top of the screen, or let them go.")
		x += kw + px(L.gap)
	}
	button({x, y, button_wide(down, key_for(.Escape)), px(L.button)}, down, .Drop, 0, false, "hand.drop", "Empty the hand.")
	screen.items[len(screen.items) - 1].key = key_for(.Escape)
}

// Bottom right: the lists. The others come with their systems.
lists_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Lists
	Know :: struct { name, id, tip: string, act: Act, arg: int, key: string, open: bool }
	knows := [3]Know{
		{"Dwarves", "lists.dwarves", "Every dwarf of the hold: found by name, trade or place, grouped by need, by trade or by place. Each row goes to its dwarf.", .List, int(List.Dwarves), key_for(.List, int(List.Dwarves)), u.list == .Dwarves},
		{"Places", "lists.places", "The island's named places and what else is remarkable on it. Each row goes there.", .List, int(List.Places), key_for(.List, int(List.Places)), u.list == .Places},
		{"Menu", "lists.menu", "Back to the game, the interface's size, and quit.", .Menu, 0, key_for(.Escape), u.menu},
	}
	wide := f32(0)
	for k in knows do wide += button_wide(k.name, k.key, .Body, L.know_pad)
	r := Rect{screen.w - px(L.margin) - wide, screen.h - px(L.margin) - px(L.button), wide, px(L.button)}
	part(.Panel, r, id = "lists")
	x := r.x
	for k in knows {
		w := button_wide(k.name, k.key, .Body, L.know_pad)
		part(.Know, {x, r.y, w, r.h}, k.name, .Body, {}, {.Open} if k.open else {}, k.act, k.arg, k.key, k.id, k.tip)
		x += w
	}
}

// Where a list stands: down the right side, a third of the screen wide, and never over the hand or the place.
list_rect :: proc() -> Rect {
	u, L := &play, &LOOK
	w := min(px(L.list_wide), screen.w - 3*px(L.margin) - max(px(L.hand_wide), u.place_wide))
	return {screen.w - px(L.margin) - w, px(L.margin), w, screen.h - hand_foot() - px(L.margin)}
}

// The head of a list: its name and how many it holds, the field it finds by, and its choices, one of
// `sorts` and, where it has one, `only` on or off. Returns the room under them for its rows, where
// their words begin and how wide they may be.
list_head :: proc(title, count, hint: string, sorts: []string, sort: int, only := "", only_on := false) -> (box: Rect, x, inner: f32) {
	u, L := &play, &LOOK
	r := list_rect()
	part(.Panel, r, id = "list")
	x = r.x + px(L.pad.x)
	y := r.y + px(L.pad.y)
	inner = r.w - 2*px(L.pad.x)
	words(x, y, title, .Title, id = "list.title")
	words(x + inner - text_wide(.Body, count), y + px(1), count, .Body, L.ash, "list.count")
	y += line_of(.Title) + px(3)
	field := line_of(.Body) + 2*px(2)
	found := string(u.find[:])
	part(.Field, {x, y, inner, field}, found if found != "" || u.typing else hint, .Body, {}, ({.Held} if u.typing else {}) + ({.Faint} if found == "" else {}), .Find, id = "list.find")
	y += field + px(3)
	cx, high := x, line_of(.Body) + 2*px(L.chip_pad.y)
	for k in 0..=len(sorts) {   // the choices, on a second line where one is too narrow for them
		name := sorts[k] if k < len(sorts) else only
		if name == "" do continue
		cw := text_wide(.Body, name) + 2*px(L.chip_pad.x)
		if cx > x && cx + cw > x + inner do cx, y = x, y + high + px(L.gap)
		if k < len(sorts) do part(.Chip, {cx, y, cw, high}, name, .Body, {}, {.Chosen} if sort == k else {}, .Sort, k, id = "list.sort")
		else do part(.Chip, {cx, y, cw, high}, name, .Body, {}, {.Chosen} if only_on else {}, .Only, 0, id = "list.only")
		cx += cw + px(L.gap)
	}
	y += high + px(L.pad.y)
	part(.Rule, {r.x + 1, y, r.w - 2, 1}, colour = L.edge)
	return {r.x + 1, y + 1, r.w - 2, r.y + r.h - y - 2}, x, inner
}

// Where a list's rows begin, scrolled as far as it has been; and, once they are listed, how far it can be.
list_top :: proc(box: Rect) -> f32 {
	u := &play
	if u.drag == .List do u.list_scroll = u.drag_scroll + (u.pointer.y - u.drag_from)*(u.list_over + box.h)/box.h
	u.list_scroll = clamp(u.list_scroll, 0, u.list_over)
	return box.y - u.list_scroll
}
list_foot :: proc(box: Rect, top, foot: f32) {
	u := &play
	u.list_over = max(foot - top - box.h, 0)
	if all := foot - top; u.list_over > 0 do part(.Thumb, {box.x + box.w - px(1.5), box.y + box.h*u.list_scroll/all, px(1.5), box.h*box.h/all}, act = .Thumb, id = "list.thumb")
}

// The Places list, down the right side: the island's named places, then what else is remarkable
// on it, by kind. It finds by name or kind, sorts by kind or by how near, folds a long group to its
// count, and every row goes to its place (I4, I14).
places_build :: proc() {
	u, L := &play, &LOOK
	u.area = .List
	f := island_near(u.a.at.x, u.a.at.z)
	if f != nil do bound(f)
	found := string(u.find[:])
	box, x, inner := list_head("Places", fmt.tprint(len(candidates) if f != nil else 0), "Find by name or kind", {"Named first", "Nearest first"}, u.sort)
	if f == nil do return

	// The rows: each candidate for a place, with the name it was given if it was the one named.
	Entry :: struct { c, group: int, name, why, far: string, d: f64 }
	rows := make([dynamic]Entry, context.temp_allocator)
	at := [2]f64{u.a.at.x - f64(region.origin.x), u.a.at.z - f64(region.origin.y)}
	needle := strings.to_lower(found, context.temp_allocator)
	for c, i in candidates {
		e := Entry{c = i, group = 1 + int(c.kind), d = linalg.length(c.at - at)}
		first, _, rest := strings.partition(c.why, ", ")
		e.name, e.why = sentence(first)[:len(first)], sentence(rest)
		for p in places do if p.c == i do e.group, e.name, e.why = 0, sentence(p.name)[:len(p.name)], sentence(c.why)
		e.far = fmt.tprintf("%s %s", far_words(e.d), compass(c.at.x - at.x, c.at.y - at.y)) if e.d > 30 else "here"
		if needle != "" && !strings.contains(strings.to_lower(fmt.tprintf("%s %s %s", e.name, e.why, PLACE_ROWS[c.kind].what), context.temp_allocator), needle) do continue
		append(&rows, e)
	}
	if u.sort == 1 do slice.sort_by(rows[:], proc(a, b: Entry) -> bool { return a.d < b.d })
	else do slice.stable_sort_by(rows[:], proc(a, b: Entry) -> bool { return a.group < b.group })

	u.clip = box
	row_high := 2*line_of(.Body) + 2*px(L.row_pad.y)
	head_high := line_of(.Body) + px(3) + px(1.5)
	top := list_top(box)
	cy := top
	group := -1
	for e in rows {
		if u.sort == 0 && e.group != group {
			group = e.group
			n := 0
			for o in rows do n += int(o.group == group)
			name := "Named places" if group == 0 else fmt.tprintf("%s%s", sentence(PLACE_ROWS[Place_Kind(group - 1)].what)[:len(PLACE_ROWS[Place_Kind(group - 1)].what)], "es" if strings.has_suffix(PLACE_ROWS[Place_Kind(group - 1)].what, "s") else "s")
			part(.Head, {box.x, cy, box.w, head_high}, act = .Fold, arg = group, id = "list.group", tip = "Fold this group to its count, or open it.")
			part(.Text, {x, cy + px(3), inner, line_of(.Body)}, name, .Body, L.ash, id = "list.group.name")
			part(.Text, {x, cy + px(3), inner, line_of(.Body)}, fmt.tprintf("%d", n), .Body, L.ash, {.Right})
			cy += head_high
		}
		if u.sort == 0 && needle == "" && e.group not_in u.open do continue
		chosen := u.hand.kind == .Place && u.hand.place == e.c && u.hand.island == f
		part(.Row, {box.x, cy, box.w, row_high}, state = {.Chosen} if chosen else {}, act = .Row, arg = e.c, id = "list.row", tip = "Go there.")
		fw := text_wide(.Body, e.far)
		part(.Text, {x, cy + px(L.row_pad.y), inner - fw - px(4), line_of(.Body)}, e.name, .Name if e.group == 0 else .Body, id = "list.row.name")
		part(.Text, {x, cy + px(L.row_pad.y), inner, line_of(.Body)}, e.far, .Body, L.ash, {.Right})
		part(.Text, {x, cy + px(L.row_pad.y) + line_of(.Body), inner, line_of(.Body)}, fit(.Body, e.why, inner), .Body, L.ash, id = "list.row.why")
		cy += row_high
	}
	if len(rows) == 0 do part(.Text, {x, cy + px(3), inner, line_of(.Body)}, "Nothing on the island answers to that.", .Body, L.ash, id = "list.none")
	u.clip = {}
	list_foot(box, top, cy)
}

// One line of advice beside the thing it is about, until the thing has been done once.
lesson_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Lesson
	if !u.teach || u.menu || u.list != .None do return
	for l in Lesson do if l not_in u.learned {
		text := LESSONS[l]
		wide := min(text_wide(.Body, text), px(120))
		h := text_high(.Body, text, wide) + 2*px(L.chip_pad.y)
		w := wide + 2*px(L.chip_pad.x)
		r: Rect
		switch l {
		case .Select: r = {px(L.margin), screen.h - hand_foot() - h, w, h}
		case .Cut:    r = {u.ground.x - px(3) - w, u.beds.y + u.beds.h/2 - h/2, w, h}
		case .Walk:   r = {u.ground.x - px(3) - w, u.walk_row.y + px(L.button) + px(L.gap), w, h}
		}
		if l == .Select && u.hand.kind != .None || l != .Select && u.ground.w == 0 do return
		part(.Tip, r, text, .Body, {}, {.Wrap}, id = "lesson")
		return
	}
}

// A few words beside the pointer once it rests: what a button does, which bed of the column it is
// on, or what lies under it in the world.
tip_build :: proc() {
	u, a, L := &play, play.a, &LOOK
	if u.menu || u.owner != .None || u.afoot^ && u.captured^ do return
	text := ""
	told := -1   // a part with something to say and nothing to do, under the pointer: a meter, a line of the stores, the weather
	if screen.hot < 0 do #reverse for it, i in screen.items {
		if !inside(it.rect, u.pointer) || it.clip.w > 0 && !inside(it.clip, u.pointer) do continue
		if it.tip != "" do told = i
		if it.tip != "" || it.part == .Panel || it.part == .Veil || .Solid in it.state do break
	}
	if hot := screen.hot; hot >= 0 {
		if u.rest > 0.45 || u.still do text = screen.items[hot].tip
	} else if told >= 0 {
		if u.rest > 0.45 || u.still do text = screen.items[told].tip
	} else if _, solid, _ := screen_over(&screen, u.pointer); !solid && !u.afoot^ && !tool_marks() && a.shown && a.under.ok && u.pointer.x >= 0 && (u.rest > 0.6 || u.still) {   // a tool's own line says what lies under it
		if a.under.block != u.tip_block || u.tip == "" {   // asked once for each block the pointer rests on
			delete(u.tip)
			t := thing_at(u.w, a.under)
			if u.animal.ok do t = {kind = .Animal, creature = u.animal.row, nest = u.animal.nest}
			u.tip_block = a.under.block
			switch t.kind {
			case .None, .Box, .Dwarf, .Dwarves, .Place, .Pile, .Zone, .Fire: u.tip = strings.clone("")
			case .Ground: u.tip = strings.clone(mat_words(t.mat))
			case .Tree:   u.tip = fmt.aprintf("a %s%s, %d m", SPECIES[t.tree.kind].name, "" if t.tree.kind == .Scrub else " tree", t.tree.height)
			case .Stream: u.tip = strings.clone("a stream")
			case .Lake:   u.tip = strings.clone("still water")
			case .Sea:    u.tip = strings.clone("the sea")
			case .Animal: u.tip = fmt.aprintf("%s %s%s", "an" if strings.contains_rune("aeiou", rune(CREATURES[t.creature].name[0])) else "a", CREATURES[t.creature].name, "'s nest" if t.nest else "")
			}
		}
		text = u.tip
	}
	if text == "" do return
	u.area = .World
	wide := min(text_wide(.Small, text), px(96))
	w, h := wide + 2*px(L.chip_pad.x), text_high(.Small, text, wide) + 2*px(L.chip_pad.y)
	x, y := u.pointer.x + px(4), u.pointer.y + px(5)
	if hot := screen.hot; hot >= 0 && screen.items[hot].area != .World {   // beside the part it is about, on the side the world is
		r := screen.items[hot].rect
		if r.x + r.w/2 > 0.6*screen.w do x, y = r.x - px(2) - w, r.y
		else if r.y > screen.h/2 do x, y = r.x, r.y - px(2) - h
		else do x, y = r.x, r.y + r.h + px(2)
	}
	if x + w > screen.w - px(1) do x = u.pointer.x - px(2) - w
	if y + h > screen.h - px(1) do y = u.pointer.y - px(3) - h
	part(.Tip, {math.round(x), math.round(y), w, h}, text, .Small, {}, {.Wrap}, id = "tip")
}

// The menu: over the whole screen, with the world standing still behind it.
menu_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Menu
	part(.Veil, {0, 0, screen.w, screen.h})
	w := px(L.menu_wide)
	inner := w - 2*px(L.pad.x)
	sizes := [6]string{"75%", "100%", "125%", "150%", "175%", "200%"}
	lessons := f32(0)
	for l in LESSONS do lessons += text_high(.Body, l, inner) + px(1)
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	high := 2*px(L.pad.y) + line_of(.Great) + line_of(.Body) + px(6) + px(L.button) + px(6) + line_of(.Body) + px(2) + chip + px(6) + line_of(.Body) + px(2) + lessons + px(5) + 3*px(L.button) + 2*px(L.gap)
	r := Rect{math.round((screen.w - w)/2), math.round((screen.h - high)/2), w, high}
	part(.Panel, r, id = "menu")
	x, y := r.x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(x, y, "OdinCraft", .Great, id = "menu.title")
	y += words(x, y, fmt.tprintf("The world of seed %d. It stands still while this is open.", world_seed), .Body, L.ash, "menu.world") + px(6)
	button({x, y, inner, px(L.button)}, "Back to the game", .Back, 0, false, "menu.back")
	y += px(L.button) + px(6)
	y += words(x, y, "The interface's size", .Body, L.ash) + px(2)
	cx := x
	now := ui.module
	for n, i in sizes {
		cw := text_wide(.Body, n) + 2*px(L.chip_pad.x)
		part(.Chip, {cx, y, cw, chip}, n, .Body, {}, {.Chosen} if now == i + 3 else {}, .Scale, i + 3, id = "menu.size")
		cx += cw + px(L.gap)
	}
	y += chip + px(6)
	y += words(x, y, "What the game has told you", .Body, L.ash) + px(2)
	for l in LESSONS do y += words(x, y, l, .Body, {}, "menu.lesson", inner) + px(1)
	y += px(4)
	button({x, y, inner, px(L.button)}, "Leave to the world", .Leave, int(Leave.World), false, "menu.leave.world", "Out of this game to the world's map, where another island can be chosen. What was dug and built is not kept yet.")
	y += px(L.button) + px(L.gap)
	button({x, y, inner, px(L.button)}, "Leave to the front door", .Leave, int(Leave.Door), false, "menu.leave.door", "Out of this game to the front door: the worlds, a new world, and settings.")
	y += px(L.button) + px(L.gap)
	button({x, y, button_wide("Quit", key_for(.Quit)), px(L.button)}, "Quit", .Quit, 0, false, "menu.quit")
}

// ---- lenses ---------------------------------------------------------------------------------

// Keep the lens's picture that of the island under the view: when the lens or the island changes,
// the field is read over the whole island on a thread of its own, and painted when it is ready.
lens_follow :: proc() {
	u := &play
	if u.lens < 0 || u.afoot^ || LENSES[u.lens].blocks do return   // the shelter lens is read from the blocks, each frame it changes (shelter_scan)
	f := island_near(u.a.at.x, u.a.at.z)
	if f == nil || u.lens_job != nil || u.lens_island == f && u.lens_shown == u.lens do return
	u.lens_job = new(Lens_Job)
	u.lens_job^ = {island = f, field = LENSES[u.lens].field, pixels = make([]u8, LENS_SIZE*LENS_SIZE*4), rank = kinds_rank(f)}
	thread.create_and_start_with_poly_data(u.lens_job, proc(job: ^Lens_Job) {
		bind(job.island)
		paint := &FIELDS[job.field]
		for py in 0..<LENS_SIZE do for qx in 0..<LENS_SIZE {
			x, z := (f64(qx) + 0.5)*region.size/LENS_SIZE - region.size/2, (f64(py) + 0.5)*region.size/LENS_SIZE - region.size/2
			if land_at(land.z[0], land.n, x, z) <= 0 do continue
			p := point_at(x, z, 8) if job.field in GROUND_FIELDS else Point{x = x, z = z, cell = 8}
			v := paint.at(&p)
			col := field_paint(paint, v, x, z)
			if paint.paint == .Kinds do for k in 0..<3 do col[k] = f32(LOOK.kinds[job.rank[Mat(v)]][k])/255   // the map's own colours for rock are too alike to read over the land
			for k in 0..<3 do job.pixels[(py*LENS_SIZE + qx)*4 + k] = u8(clamp(col[k], 0, 1)*255)
			job.pixels[(py*LENS_SIZE + qx)*4 + 3] = 255
		}
		free_all(context.temp_allocator)
		sync.atomic_store(&job.done, true)
	}, self_cleanup = true)
}

// The lens for the frame's picture: its texture, and where the eye stands on it (Frame.lens,
// shaders.metal). A lens just read is put on the GPU here. Called by render.
lens_bind :: proc(g: ^Gpu, eye: [3]f64) -> (texture: ^sdl.GPUTexture, at: [4]f32) {
	u := &play
	if job := u.lens_job; job != nil && sync.atomic_load(&job.done) {
		if u.lens_tex == nil do u.lens_tex = sdl.CreateGPUTexture(g.dev, {type = .D2, format = .R8G8B8A8_UNORM_SRGB, usage = {.SAMPLER}, width = LENS_SIZE, height = LENS_SIZE, layer_count_or_depth = 1, num_levels = 1})
		bytes := u32(len(job.pixels))
		staging := sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = bytes})
		copy((cast([^]u8)sdl.MapGPUTransferBuffer(g.dev, staging, false))[:bytes], job.pixels)
		sdl.UnmapGPUTransferBuffer(g.dev, staging)
		cmd := sdl.AcquireGPUCommandBuffer(g.dev)
		pass := sdl.BeginGPUCopyPass(cmd)
		sdl.UploadToGPUTexture(pass, {transfer_buffer = staging}, {texture = u.lens_tex, w = LENS_SIZE, h = LENS_SIZE, d = 1}, false)
		sdl.EndGPUCopyPass(pass)
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		sdl.ReleaseGPUTransferBuffer(g.dev, staging)
		u.lens_island = job.island
		for l, i in LENSES do if l.field == job.field do u.lens_shown = i
		delete(job.pixels)
		free(job)
		u.lens_job = nil
	}
	f := u.lens_island
	if u.plain || u.afoot^ || u.lens < 0 || LENSES[u.lens].blocks || u.lens_shown != u.lens || f == nil do return nil, {}
	size := f.region.size
	return u.lens_tex, {f32(eye.x - f64(f.region.origin.x) + size/2), f32(eye.z - f64(f.region.origin.y) + size/2), f32(1/size), 1}
}

// In a run with no window, the state the options ask for (options.odin): a thing selected, a tab
// chosen, the cut's mark as it is while it is dragged.
play_posed :: proc(opt: ^Options) {
	u, a := &play, play.a
	if !u.still || screen.w == 0 do return
	if opt.has_select && !u.afoot^ {
		at := [2]f32{f32(opt.select.x)/screen.w, f32(opt.select.y)/screen.h}
		ray := view_ray(u.yaw, u.pitch, u.fov, u.aspect, at)
		under := pick(u.w, u.eye, ray, above_level(a), a.bare, 4*linalg.length(a.at - u.eye) + 600) if u.w.finest == 0 else Pick{}
		if !under.ok do under = pick_far(u.eye, ray, above_level(a))
		was := u.animal
		u.animal = {}
		if under.ok || hold_aimed(u.w, u.eye, ray, 4*linalg.length(a.at - u.eye) + 600, a) >= 0 do hand_pick(under, at)
		u.animal = was
		for d in Depth do if opt.tab != "" && (strings.equal_fold(opt.tab, DEPTHS[d]) || d == .Own && strings.equal_fold(opt.tab, OWN[u.hand.kind])) do u.tab = d
	}
	if opt.drag && a.cut do u.drag = .Cut
	if !u.posed && hold_count() > 0 {   // --keep and --who name dwarves as start-up lists them, from 1
		u.posed = true
		for k in opt.keep do if k >= 1 && k <= hold_count() && !slice.contains(u.kept[:], k - 1) do append(&u.kept, k - 1)
		who := make([dynamic]int, context.temp_allocator)
		for k in opt.who do if k >= 1 && k <= hold_count() do append(&who, k - 1)
		if len(who) > 0 do dwarves_take(who[:])
	}
}

// What the screen says, area by area, as --say prints it.
play_say :: proc() {
	for area in Area do if says := screen_says(&screen, area); says != "" do fmt.printf("[%v]\n%s", area, says)
}

// The pile a ray from the eye meets, of those the hold last showed, where it lies before the block
// picked behind it; or -1.
pile_aimed :: proc(eye: [3]f64, ray: [3]f32, behind: Pick) -> (which: int) {
	which = -1
	near := f64(1e9)
	if behind.ok do near = linalg.length([3]f64{f64(behind.block.x) + 0.5, f64(behind.block.y) + 0.5, f64(behind.block.z) + 0.5} - eye) + 0.9
	for p, k in watch.seen.piles {
		lo := [3]f64{f64(p.at.x) + 0.05, f64(p.at.y), f64(p.at.z) + 0.05}
		hi := lo + {0.9, 0.25 + 0.1*f64(min(p.n, HEAP)), 0.9}
		t0, t1 := 0.0, near
		for a in 0..<3 {
			v := f64(ray[a])
			if abs(v) < 1e-9 {
				if eye[a] < lo[a] || eye[a] > hi[a] do t1 = -1
				continue
			}
			a0, a1 := (lo[a] - eye[a])/v, (hi[a] - eye[a])/v
			t0, t1 = max(t0, min(a0, a1)), min(t1, max(a0, a1))
		}
		if t0 <= t1 do which, near = k, t0
	}
	return
}
