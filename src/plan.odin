package main

import "core:fmt"
import "core:math"
import "core:strings"

// Expedition planning (plan.md, E-1; docs/foundations/interface.md, section 16): the screen between
// the world's map and play. The island in the hand fills the picture, as it does on the world's
// screen, and the player says where on its shore the boat lands and who is in it, and sets out.
//
//   top left      the expedition: which island it goes to
//   the picture   the island. Its shore is marked where it has a landing: where a boat lies sheltered
//                 with fresh water a short walk off, and where it lies sheltered alone. The landings
//                 offered stand on it by their numbers, the one chosen in brass.
//   lower left    the hand: the place chosen, as a card of rows with the ground's beds beside them;
//                 while the pointer is on the shore, the place under it
//   right         the expedition, from its top to the one button at its foot: 1 Where, the landings
//                 offered, the game's own first; 2 Who, the party a row a dwarf, and what work it has
//                 hands for; then what to look at twice in the place chosen, Back and Set out
//
// A landing is offered and already chosen when the screen opens, and the seed's party is drawn, so
// Enter alone sets out as the game did before there was anything to plan. A click on the shore
// chooses that shore: the boat is brought in at the nearest low shore a boat can come in to, which is
// asked of the ground by the rule the hold lands by (landing_near), so what is shown is what happens.
// Only a shore that stands as a cliff takes no boat, and the pointer on it says so; an open shore, a
// dry one or a steep one is chosen like any other, and its cautions stand over the button.
//
// The party is the world's seed's, drawn again as often as the player likes: all of it, or the dwarf
// in focus. What is chosen is an `Expedition` (hold.odin), which the hold is made with and says
// again in its log. It is kept while the world is in hand, so going back and coming in again finds it.
//
// Keys, each a row of BINDS: Enter sets out, Escape goes back to the world's map, 1 to 4 choose a
// landing offered, Up and Down move among the party, D draws the dwarf in focus again and A all of
// them, Home shows the island whole, = and - zoom. A drag moves the map and the wheel zooms it.

OFFERED     :: 4       // landings offered at the most, the game's own first
OFFER_APART :: 800.0   // metres between two of them: each is another stretch of shore
SITE_DEEP   :: 40      // metres of the ground's beds a place's card shows: where a first hall would be dug
SITE_ROWS   :: 9       // rows a place's card has room for: the six of SHORE that always stand, the bed under the rock, and two of what the land may do
SITE_SHOWN  :: 900.0   // metres across the island's picture that a place's card shows round the place

Shore_Cell :: struct {
	cell: i32,
	row:  i8,        // the first of the landing's rows that holds on it, or -1: too high for a boat
	at:   [2]f32,    // its middle, from the island's
}
Site_Card :: struct {
	cell:       int,              // the cell of shore it is of, or -1
	title, sub: string,
	rows:       [dynamic]Card_Row,
	runs:       [dynamic]Run,     // the beds under the ground the party would gather on
	top:        i32,
}
Planning :: struct {
	isle:    int,                 // the island it is of, or -1
	seed:    u32,                 // and the world: another world has another party
	order:   int,
	count:   int,                 // dwarves in the boat
	set:     Expedition,          // what is chosen: the hold is made with it
	party:   [dynamic]Facts,      // the party as that draws it
	focus:   int,                 // the dwarf in focus
	shore:   [dynamic]Shore_Cell, // the island's shore, read when it is come to
	offered: [dynamic]int,        // the cells of shore offered as landings, the game's own first
	choice:  int,                 // the one of them chosen, or -1: a shore of the player's own
	landed:  Landed,              // how a boat comes in at the shore chosen
	moved:   f32,                 // metres from where the player pointed to there
	walk:    ^Walk,               // the island's ground, read for whether a boat can come in and the party walk up
	cards:   [2]Site_Card,        // of the place chosen, and of the place under the pointer
	under:   int,                 // the cell of low shore under the pointer, or -1
	cliff:   int,                 // or the cell of high shore under it, or -1
	row:     int,                 // the row of the chosen place's card that says its why, or -1
	scroll, over: f32,            // how far the card's rows are scrolled, and how far they can be
	who_scroll, who_over: f32,    // and the party's
	card_at: Rect,                // where the card stood last frame
	reveal:  bool,                // a row's why was opened: the rows are scrolled to show it
}
planning := Planning{isle = -1, under = -1, cliff = -1, row = -1, cards = {{cell = -1}, {cell = -1}}}

// ---- what is chosen ---------------------------------------------------------------------------

// Draw the party as the expedition has it.
plan_party :: proc() {
	p := &planning
	for f in p.party { delete(f.given); delete(f.byname) }
	party_draw(world_seed, p.count, &p.party, p.set.draws, p.set.again[:])
	p.focus = clamp(p.focus, 0, max(p.count - 1, 0))
}

// Come to an island to plan an expedition to it: read its shore, find the landings it offers and
// take the game's own. False where its land is not formed. What was chosen there before is kept.
plan_open :: proc(island: int) -> bool {
	p := &planning
	if island < 0 || island >= len(archipelago) || !is_formed(&formed[island]) do return false
	count := door.opt.party if door.opt != nil && door.opt.party > 0 else LANDING
	if p.seed != making.seed || p.order != making.order {   // another world: its seed's own party, and no island of the last
		clear(&p.set.again)
		p.set = {again = p.set.again}
		p.seed, p.order, p.isle, p.focus, p.count = making.seed, making.order, -1, 0, 0
	}
	if p.count != count {
		p.count = count
		plan_party()
	}
	if p.isle == island do return true
	f := &formed[island]
	bound(f)
	p.isle, p.row, p.scroll, p.under, p.cliff = island, -1, 0, -1, -1
	p.cards[0].cell, p.cards[1].cell = -1, -1
	g := land.grid
	clear(&p.shore)
	for c in shore_cells() {
		m := middle_of(g, c)
		append(&p.shore, Shore_Cell{i32(c), i8(landing_row(c)), {f32(m.x), f32(m.y)}})
	}
	if p.walk != nil {
		walk_drop(p.walk)
		free(p.walk)
	}
	p.walk = new(Walk)
	walk_init(p.walk, f)
	p.walk.budget = ASKING
	// The landings it offers: the game's own, then the best of its row and of the sheltered rows after
	// it, each on another stretch of shore.
	clear(&p.offered)
	p.set.lands, p.choice, p.landed, p.moved = false, -1, {}, 0
	own, found := landing_choose(p.walk)
	if !found do return true   // no boat can come in anywhere: the screen says so, and nothing sets out
	append(&p.offered, own.cell)
	p.landed, p.choice = own, 0
	for r in own.row..=max(own.row, len(LANDINGS) - 2) {
		for len(p.offered) < OFFERED {
			best, at := f32(-1), -1
			next: for sc in p.shore do if int(sc.row) == r {
				for o in p.offered {
					m := middle_of(g, o)
					if math.hypot(f64(sc.at.x) - m.x, f64(sc.at.y) - m.y) < OFFER_APART do continue next
				}
				q := point_at(f64(sc.at.x), f64(sc.at.y), LAND_CELL)
				if s := host(LANDINGS[r].likes, &q); s > best do best, at = s, int(sc.cell)
			}
			if at < 0 do break
			append(&p.offered, at)
		}
	}
	return true
}

// Choose a cell of shore: the boat is brought in at the low shore nearest it that a boat can come in
// to, as the hold will bring it (landing_near). `offered` is the landing offered that was asked for, or -1.
plan_take :: proc(cell: int, offered := -1) {
	p := &planning
	f := &formed[p.isle]
	bound(f)
	m := middle_of(land.grid, cell)
	asked := [2]i32{i32(math.floor(m.x)) + region.origin.x, i32(math.floor(m.y)) + region.origin.y}
	p.walk.budget = ASKING
	l, ok := landing_near(p.walk, asked)
	if !ok do return
	p.landed, p.moved, p.row, p.scroll = l, l.off if l.cell != cell else 0, -1, 0
	p.choice = offered
	if offered >= 0 do p.offered[offered] = l.cell
	for o, i in p.offered do if o == l.cell do p.choice = i
	// The game's own landing is what the hold chooses with nothing asked of it; any other is asked for
	// by the middle of its cell, which is the nearest low shore to itself.
	at := middle_of(land.grid, l.cell)
	p.set.lands = p.choice != 0
	p.set.shore = {i32(math.floor(at.x)) + region.origin.x, i32(math.floor(at.y)) + region.origin.y}
}

// What a click on the picture chooses: the shore under the pointer.
plan_click :: proc() {
	p := &planning
	if p.under < 0 do return
	for o, i in p.offered do if o == p.under {
		plan_take(o, i)
		return
	}
	plan_take(p.under)
}

plan_act :: proc(act: Act, arg: int) {
	p := &planning
	#partial switch act {
	case .Site:
		if arg >= 0 && arg < len(p.offered) do plan_take(p.offered[arg], arg)
	case .Party_Who:
		p.focus = clamp(arg, 0, max(p.count - 1, 0))
	case .Party_Move:
		if p.count > 0 do p.focus = (p.focus + arg + p.count)%p.count
	case .Draw_Dwarf:   // the one in focus, drawn again: another dwarf in its seat
		append(&p.set.again, p.focus)
		plan_party()
	case .Draw_Party:   // all of them: the seed's next party
		p.set.draws += 1
		clear(&p.set.again)
		plan_party()
	case .Site_Row:
		p.row = -1 if p.row == arg else arg
		p.reveal = true
	}
}

// ---- a place's card ---------------------------------------------------------------------------

// A place on the shore by name: the named place it is at, or which way it lies from the nearest
// (place_title, play.odin), as the play screen will name it once the party is there. The island is bound.
shore_name :: proc(at: [2]f32) -> string {
	i, d := place_near(f64(at.x), f64(at.y))
	if i < 0 do return fmt.tprintf("The %s shore", compass(f64(at.x), f64(at.y)))
	name := places[i].name
	if d < GATHER do return capital(name)
	c := candidates[places[i].c]
	return fmt.tprintf("%s of %s", capital(compass(f64(at.x) - c.at.x, f64(at.y) - c.at.y)), name)
}

// What landing a cell of shore is, in a few words.
LANDING_SAID := [len(LANDINGS)]string{"sheltered, by fresh water", "sheltered, water a walk off", "an open shore"}
LANDING_SIGN := [len(LANDINGS)]Sign{.Well, .None, .Caution}

// Write a place's card, where it is not that cell's already.
site_card :: proc(k: ^Site_Card, cell: int, landed: ^Landed) {
	p := &planning
	if k.cell == cell do return
	delete(k.title); delete(k.sub)
	for r in k.rows { delete(r.thing); delete(r.says); delete(r.why); delete(r.named) }
	clear(&k.rows)
	clear(&k.runs)
	k.cell = cell
	bound(&formed[p.isle])
	g := land.grid
	m := middle_of(g, cell)
	row := landing_row(cell)
	k.title = strings.clone(shore_name({f32(m.x), f32(m.y)}))
	k.sub = strings.clone(capital(LANDINGS[row].name) if row >= 0 && row < len(LANDINGS) - 1 else "An open shore")
	site_write(&k.rows, cell)
	if landed != nil && landed.shut do for &r in k.rows do if r.thing == "Ground to live on" {   // found by going there: no way leads up to it
		delete(r.says); delete(r.named)
		r.says, r.sign, r.named = strings.clone("near, and no way up to it"), .Caution, strings.clone("No way up from the shore to ground to live on")
	}
	// The beds under the ground the party would gather on.
	camp := cell
	if _, live := cell_near(cell, 16, livable); live >= 0 do camp = live
	at := middle_of(g, camp)
	x, z := i32(math.floor(at.x)) + region.origin.x, i32(math.floor(at.y)) + region.origin.y
	k.top = ground_top(f64(x) + 0.5, f64(z) + 0.5) + 1
	append(&k.runs, ..column_runs(nil, x, z, k.top, k.top - 1 - SITE_DEEP))
}

// ---- the screen -------------------------------------------------------------------------------

// The shore's marks, and the landings on it.
plan_marks :: proc() {
	c, p, u, L := &chart, &planning, &play, &LOOK
	u.area = .Chart
	is := archipelago[p.isle]
	o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
	per := c.span/f64(max(c.wide, 1))   // metres to a pixel
	side := clamp(f32(1.5*LAND_CELL/per), px(1.5), px(2.5))
	for sc in p.shore do if sc.row >= 0 && int(sc.row) < len(LANDINGS) - 1 {   // where the shore has a landing: the land shuts the sea in
		at := chart_to(o + {f64(sc.at.x), f64(sc.at.y)})
		if at.x < -side || at.y < -side || at.x > c.wide + side || at.y > c.high + side do continue
		part(.Fill, {math.round(at.x - side/2), math.round(at.y - side/2), side, side}, colour = L.verdigris if sc.row == 0 else L.shelter, id = "planning.shore")
	}
	place :: proc(cell: int) -> [2]f32 {
		for sc in planning.shore do if int(sc.cell) == cell {
			is := archipelago[planning.isle]
			return chart_to({f64(is.origin.x) + f64(sc.at.x), f64(is.origin.y) + f64(sc.at.y)})
		}
		return {-1e6, -1e6}
	}
	ring := px(L.isle)
	mark :: proc(at: [2]f32, chosen: bool) {   // a ring where a boat comes in: the one chosen larger, brass, with a dark line round it and a dot at its middle
		L := &LOOK
		r := px(L.isle) + (px(2) if chosen else 0)
		if chosen do part(.Ring, {at.x - r/2 - px(0.5), at.y - r/2 - px(0.5), r + px(1), r + px(1)}, colour = L.pit)
		part(.Ring, {at.x - r/2, at.y - r/2, r, r}, colour = L.brass if chosen else L.chalk, id = "plan.mark")
	}
	if p.under >= 0 && p.under != p.landed.cell {   // the shore the pointer is on
		at := place(p.under)
		part(.Ring, {at.x - ring/2, at.y - ring/2, ring, ring}, colour = L.chalk, id = "plan.under")
	}
	for cell, i in p.offered {
		at := place(cell)
		chosen := p.choice == i
		mark(at, chosen)
		// Its number, on a tab over it: the key that chooses it, and its row's at the right.
		w, h := key_wide(fmt.tprint(i + 1)), px(L.key_high)
		r := Rect{math.round(at.x - w/2), math.round(at.y - ring/2 - h - px(1.5)), w, h}
		part(.Fill, r, colour = L.brass if chosen else L.edge, act = .Site, arg = i, id = "plan.number", tip = "Land here.")
		part(.Fill, {r.x + 1, r.y + 1, r.w - 2, r.h - 2}, colour = L.brass if chosen else L.deep)
		n := fmt.tprint(i + 1)
		part(.Text, {r.x + math.round((w - text_wide(.Key, n))/2), r.y, text_wide(.Key, n), line_of(.Key)}, n, .Key, L.on_brass if chosen else L.chalk)
		if chosen do part(.Fill, {at.x - px(0.75), at.y - px(0.75), px(1.5), px(1.5)}, colour = L.brass)
	}
	if p.choice < 0 && len(p.offered) > 0 {   // a shore of the player's own
		mark(place(p.landed.cell), true)
	}
}

// Top left: the expedition, and where it goes.
plan_head :: proc() {
	p, u, L := &planning, &play, &LOOK
	u.area = .Place
	is := archipelago[p.isle]
	title := fmt.tprintf("An expedition to %s", isle_name(p.isle))
	o, start := [2]f64{f64(is.origin.x), f64(is.origin.y)}, world_frame.origin
	sub := fmt.tprintf("%s, %s.", capital(kind_said(is.kind).one), "where the world of this seed begins" if p.isle == 0 else fmt.tprintf("%.0f km %s of the start", math.hypot(o.x - start.x, o.y - start.y)/1000, compass(o.x - start.x, o.y - start.y)))
	wide := max(text_wide(.Great, title), px(L.hand_wide) - 2*px(L.pad.x))
	r := Rect{px(L.margin), px(L.margin), wide + 2*px(L.pad.x), 2*px(L.pad.y) + line_of(.Great) + px(1) + text_high(.Body, sub, wide)}
	part(.Panel, r, id = "plan")
	x, y := r.x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(x, y, title, .Great, id = "plan.title") + px(1)
	words(x, y, sub, .Body, L.ash, "plan.says", wide)
	u.place_foot = r.y + r.h
}

// A head of the expedition's column: its number, what it asks, and a few words at its right.
plan_step :: proc(cx, y, inner: f32, n: int, name, says: string) -> f32 {
	L := &LOOK
	num := fmt.tprint(n)
	words(cx, y, num, .Title, L.brass)
	words(cx + text_wide(.Title, num) + px(3), y, name, .Title, id = "plan.step")
	if says != "" do part(.Text, {cx, y + line_of(.Title) - line_of(.Small) - px(0.5), inner, line_of(.Small)}, says, .Small, L.ash, {.Right}, id = "plan.step.says")
	return line_of(.Title) + px(1.5)
}

// Right: the expedition, from where to who to the one button.
plan_side :: proc() {
	p, u, L := &planning, &play, &LOOK
	u.area = .List
	w := px(L.isles_wide)
	x, top, foot := screen.w - px(L.margin) - w, px(L.margin), screen.h - px(L.margin)
	inner := w - 2*px(L.pad.x)
	cx := x + px(L.pad.x)
	part(.Panel, {x, top, w, foot - top}, id = "expedition")
	y := top + px(L.pad.y)
	y += words(cx, y, "The expedition", .Great, id = "expedition.title") + px(2)

	// What to look at twice in the place chosen, and what play waits for: the foot's, measured before the rest.
	Caution :: struct { name, why: string, sign: Sign }
	cautions := make([dynamic]Caution, context.temp_allocator)
	if len(p.offered) > 0 {
		site_card(&p.cards[0], p.landed.cell, &p.landed)
		for r in p.cards[0].rows do if r.named != "" do append(&cautions, Caution{r.named, r.why, r.sign})
	}
	waits := enter_waits(p.isle)
	can := waits == "" && len(p.offered) > 0
	line := line_of(.Body) + px(1)
	foot_high := f32(max(len(cautions), 1))*line + px(3) + (text_high(.Small, waits, inner) + px(2) if waits != "" else 0) + px(L.button) + px(L.pad.y)
	high, who := px(L.plan_row), px(L.who_row)
	work_high := f32(len(WORKS))*line + px(L.space)
	step := line_of(.Title) + px(1.5)

	// 1 Where: the landings offered, a row each, by the number that stands on the shore.
	bound(&formed[p.isle])
	Entry :: struct { cell, row, offered: int }
	entries := make([dynamic]Entry, context.temp_allocator)
	for cell, i in p.offered do append(&entries, Entry{cell, 0, i})
	if p.choice < 0 && len(p.offered) > 0 do append(&entries, Entry{p.landed.cell, 0, -1})
	for &e in entries do for sc in p.shore do if int(sc.cell) == e.cell do e.row = int(sc.row)
	// Where the picture is small for the interface's size the column gives way in an order, so that the party keeps three rows:
	// first the work it has hands for is left out, then the landings not chosen, which stand on the island by their numbers.
	rest := foot - foot_high - y - 2*step - px(L.space) - 1 - px(3) - px(L.button)   // what is left for the landings, the party and its work
	works := rest - f32(len(entries))*high - work_high >= min(f32(p.count), 3)*who
	if !works do work_high = 0
	if rest - f32(len(entries))*high - work_high < min(f32(p.count), 3)*who && len(entries) > 1 {
		for i := len(entries) - 1; i >= 0; i -= 1 do if entries[i].offered != p.choice do ordered_remove(&entries, i)
	}
	y += plan_step(cx, y, inner, 1, "Where", "the game's own first" if len(entries) > 1 else fmt.tprintf("one of %s", number_words(len(p.offered) + int(p.choice < 0))) if len(p.offered) > 1 else "")
	for e in entries {
		chosen := e.offered == p.choice
		part(.Row, {x + 1, y, w - 2, high}, state = {.Chosen} if chosen else {}, act = .Site if e.offered >= 0 else .None, arg = e.offered, id = "landing.row", tip = "Land here." if !chosen else "")
		ty := y + math.round((high - line_of(.Name) - line_of(.Small))/2)
		kw := key_wide("0")
		if e.offered >= 0 do key_part(fmt.tprint(e.offered + 1), cx, ty, line_of(.Name))
		else {
			ring := px(L.sign) + px(1)
			part(.Ring, {cx + math.round((kw - ring)/2), ty + math.round((line_of(.Name) - ring)/2), ring, ring}, colour = L.brass)
		}
		tx := cx + kw + px(3)
		m := middle_of(land.grid, e.cell)
		name := shore_name({f32(m.x), f32(m.y)})
		q := point_at(m.x, m.y, LAND_CELL)
		says := fmt.tprintf("%s%s, %.1f ha", "" if e.offered >= 0 else "your own: ", LANDING_SAID[clamp(e.row, 0, len(LANDINGS) - 1)], FIELDS[.Livable_Round].at(&q))
		words(tx, ty, fit(.Name, name, inner - (tx - cx) - px(L.sign) - px(2)), .Name, L.brass if chosen else L.chalk, "landing.name")
		words(tx, ty + line_of(.Name), fit(.Small, says, inner - (tx - cx)), .Small, L.ash, "landing.says")
		if sign := LANDING_SIGN[clamp(e.row, 0, len(LANDINGS) - 1)]; sign != .None {
			part(.Sign, {cx + inner - px(L.sign), ty + math.round((line_of(.Name) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = sign
		}
		y += high
	}
	if len(p.offered) == 0 do y += words(cx, y, "No boat can come in to any shore of this island.", .Body, L.ash, "landing.none", inner)
	part(.Rule, {x + 1, y, w - 2, 1})
	y += px(L.space)

	// 2 Who: the party, a row a dwarf, as many as the room lets, scrolled where there are more; how to draw them again; and what work it has hands for.
	y += plan_step(cx, y, inner, 2, "Who", fmt.tprintf("%s, %s", number_words(p.count), "the seed's own" if p.set.draws == 0 && len(p.set.again) == 0 else "drawn again"))
	room := foot - foot_high - y - px(L.button) - px(3) - work_high - px(2)
	box := Rect{x + 1, y, w - 2, max(min(f32(p.count)*who, room), who)}
	p.who_over = max(f32(p.count)*who - box.h, 0)
	if rel := f32(p.focus)*who - p.who_scroll; rel < 0 do p.who_scroll += rel   // the one in focus is kept in view
	else if rel + who > box.h do p.who_scroll += rel + who - box.h
	p.who_scroll = clamp(p.who_scroll, 0, p.who_over)
	part(.Fill, box, colour = {}, state = {.Solid}, id = "who.box")
	u.clip = box
	for f, i in p.party {
		ry := box.y + f32(i)*who - p.who_scroll
		if ry + who < box.y || ry > box.y + box.h do continue
		t := TRADES[f.trade]
		age := "young" if f.age < 40 else "in its prime" if f.age < 80 else "old"
		part(.Row, {box.x, ry, box.w, who}, state = {.Chosen} if p.focus == i else {}, act = .Party_Who, arg = i, id = "who.row", tip = fmt.tprintf("A %s %s. %s years old, %s for a dwarf.", t.name, t.does, capital(number_words(f.age)), age))
		b := px(L.who_bust)
		bust({cx, ry + math.round((who - b)/2), b, b}, f, p.focus == i, .Party_Who, i, "who.bust")
		tx := cx + b + px(3)
		ty := ry + math.round((who - line_of(.Name) - line_of(.Small))/2)
		words(tx, ty, fit(.Name, fmt.tprintf("%s %s", f.given, f.byname), inner - (tx - cx)), .Name, L.brass if p.focus == i else L.chalk, "who.name")
		words(tx, ty + line_of(.Name), fmt.tprintf("%s, %d", t.name, f.age), .Small, L.ash, "who.trade")
	}
	u.clip = {}
	if p.who_over > 0 do part(.Thumb, {box.x + box.w - px(1.5), box.y + box.h*p.who_scroll/(p.who_over + box.h), px(1.5), box.h*box.h/(p.who_over + box.h)}, id = "who.thumb")
	y += box.h + px(3)
	if p.count > 0 {
		all := button_wide("All", door_key(.Draw_Party))
		one := fmt.tprintf("Draw %s again", p.party[p.focus].given)
		door_button({cx, y, inner - all - px(L.gap), px(L.button)}, fit(.Body, one, inner - all - px(L.gap) - 2*px(L.button_pad) - px(L.key_gap) - key_wide("D")), .Draw_Dwarf, -1, "who.again", "Another dwarf takes this one's seat in the boat: another name, age and look, and a trade no other of the party has.")
		door_button({cx + inner - all, y, all, px(L.button)}, "All", .Draw_Party, 0, "who.all", "Draw the whole party again: the seed's next.")
	}
	y += px(L.button) + px(L.space)
	// What work it has hands for: each kind of work (WORKS), and the dwarves whose trade it is.
	if works do for row, work in WORKS {
		names := strings.builder_make(context.temp_allocator)
		n := 0
		for f in p.party do if skilled(f, work, .Stone) || skilled(f, work, .Timber) {
			fmt.sbprintf(&names, "%s%s", ", " if n > 0 else "", f.given)
			n += 1
		}
		tip := fmt.tprintf("Any dwarf can %s. One whose trade it is, a %s%s, does it half again as fast.", row.name, row.hands[0], fmt.tprintf(" or a %s", row.hands[1]) if row.hands[1] != row.hands[0] else "")
		part(.Fill, {x + 1, y, w - 2, line}, colour = {}, state = {.Solid}, id = "work.row", tip = tip)
		words(cx, y, capital(row.doing), .Body, L.ash, "work.thing")
		says := fit(.Body, strings.to_string(names), inner - text_wide(.Body, capital(row.doing)) - px(4)) if n > 0 else "no one's trade"
		sw := text_wide(.Body, says)
		part(.Text, {cx + inner - sw, y, sw, line_of(.Body)}, says, .Body, L.chalk if n > 0 else L.ash, id = "work.says")
		if n == 0 do part(.Sign, {cx + inner - sw - px(1.5) - px(L.sign), y + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = .Caution
		y += line
	}

	// The foot: what to look at twice, by name, then Back and Set out.
	y = foot - foot_high
	part(.Rule, {x + 1, y - px(2), w - 2, 1}, colour = L.edge)
	for k in cautions {
		part(.Fill, {x + 1, y, w - 2, line}, colour = {}, state = {.Solid}, id = "caution.row", tip = k.why)
		part(.Sign, {cx, y + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = k.sign
		words(cx + px(L.sign) + px(2), y, fit(.Body, k.name, inner - px(L.sign) - px(2)), .Body, id = "caution")
		y += line
	}
	if len(cautions) == 0 {
		if len(p.offered) > 0 do part(.Sign, {cx, y + math.round((line_of(.Body) - px(L.sign))/2), px(L.sign), px(L.sign)}).sign = .Well
		words(cx + px(L.sign) + px(2), y, "Nothing here to look at twice" if len(p.offered) > 0 else "Nowhere to land", .Body, L.ash, "caution.none")
		y += line
	}
	y += px(3)
	if waits != "" do y += words(cx, y, waits, .Small, L.ash, "plan.waits", inner) + px(2)
	back := button_wide("Back", door_key(.Door_Back))
	door_button({cx, y, back, px(L.button)}, "Back", .Door_Back, 0, "plan.back", "Back to the world's map, with the island still in the hand. What is chosen here is kept.")
	door_button({cx + back + px(L.gap), y, inner - back - px(L.gap), px(L.button)}, "Set out", .Set_Out, 0, "plan.go", "The boat comes in at the landing chosen, with this party in it, and you lead them from above.", main = can, faint = !can)
}

// Lower left: a place on the shore, as a card of rows with the ground's beds beside them.
plan_card :: proc(k: ^Site_Card, chosen: bool) {
	c, p, u, L := &chart, &planning, &play, &LOOK
	u.area = .Hand
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x, foot := px(L.margin), screen.h - px(L.margin)
	head := line_of(.Small) + line_of(.Title) + line_of(.Body)
	depth := SITE_ROWS*(line_of(.Body) + 2*px(1))
	depth = max(min(depth, foot - (u.place_foot + px(4)) - 2*px(L.pad.y) - head - px(L.space)), px(8))
	r := Rect{x, foot - 2*px(L.pad.y) - head - px(L.space) - depth, w, 2*px(L.pad.y) + head + px(L.space) + depth}
	p.card_at = r
	part(.Panel, r, id = "site")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	// The place as the island's picture has it, with a mark where the boat comes in.
	square := Rect{cx, y + math.round((head - px(L.block_large))/2), px(L.block_large), px(L.block_large)}
	part(.Fill, square, colour = L.brass if chosen else L.edge)
	part(.Fill, {square.x + 1, square.y + 1, square.w - 2, square.h - 2}, colour = L.seas[1])
	if p.isle < len(c.shown) && c.shown[p.isle] do for sc in p.shore do if int(sc.cell) == k.cell {
		size := f32(archipelago[p.isle].size)
		mid, half := (sc.at + size/2)/size, f32(SITE_SHOWN/2)/size
		it := part(.Picture, {square.x + 1, square.y + 1, square.w - 2, square.h - 2}, id = "site.picture")
		it.uv, it.arg = {mid.x - half, mid.y - half, mid.x + half, mid.y + half}, p.isle + 1
		part(.Fill, {square.x + square.w/2 - px(0.75), square.y + square.h/2 - px(0.75), px(1.5), px(1.5)}, colour = L.brass if chosen else L.chalk)
	}
	tx := cx + px(L.block_large) + px(4)
	beside := inner - px(L.block_large) - px(4)
	tag := "Under the pointer"
	if chosen {
		tag = "The landing chosen"
		if p.choice == 0 do tag = "The landing chosen: the game's own"
		if p.moved > 1.5*LAND_CELL do tag = fmt.tprintf("Chosen: the nearest a boat can come in, %.0f m off", math.round(p.moved/10)*10)
	}
	words(tx, y, fit(.Small, tag, beside), .Small, L.brass if chosen else L.ash, "site.tag")
	words(tx, y + line_of(.Small), fit(.Title, k.title, beside), .Title, id = "site.title")
	words(tx, y + line_of(.Small) + line_of(.Title), fit(.Body, k.sub, beside), .Body, L.ash, "site.sub")
	y += head + px(L.space)
	// The beds under the ground the party would gather on, named at their left; and the rows.
	names, col := px(L.site_beds), px(L.column_wide)
	first := len(screen.items)
	column_put(k.runs[:], {cx + names, y + 1, col, depth - 2}, k.top, 1 + SITE_DEEP, max(i32), true, id = "site.bed")
	for &it in screen.items[first:] do it.act = .None   // a bed here is read, and moves no cut
	rx := cx + names + col + px(5)
	none: f32
	rows_put(k.rows[:], rx, y, inner - (rx - cx), depth, &p.scroll if chosen else &none, &p.over if chosen else &none, p.row if chosen else -1, .Site_Row if chosen else .None, "site", chosen && p.reveal)
	if chosen do p.reveal = false
}

// What the pointer is on, on the island: a shore a boat can be drawn up on, or one that stands too high.
plan_point :: proc(pointer: [2]f32) {
	c, p := &chart, &planning
	p.under, p.cliff = -1, -1
	if pointer.x < 0 || inside(p.card_at, pointer) do return
	if _, solid, _ := screen_over(&screen, pointer); solid do return
	is := archipelago[p.isle]
	at := chart_from(pointer) - {f64(is.origin.x), f64(is.origin.y)}
	per := c.span/f64(max(c.wide, 1))
	reach := max(f64(px(7))*per, 3*LAND_CELL)   // the pointer takes the shore within a few modules of it
	low, high := reach, reach
	for sc in p.shore {
		d := math.hypot(f64(sc.at.x) - at.x, f64(sc.at.y) - at.y)
		if sc.row >= 0 && d < low do low, p.under = d, int(sc.cell)
		if sc.row < 0 && d < high do high, p.cliff = d, int(sc.cell)
	}
	if p.under >= 0 && low <= high + 2*LAND_CELL do p.cliff = -1   // a low shore as near as the cliff is the one meant
	else if p.cliff >= 0 do p.under = -1
	for o in p.offered do for sc in p.shore do if int(sc.cell) == o {   // on a landing's mark, that landing
		if math.hypot(f64(sc.at.x) - at.x, f64(sc.at.y) - at.y) <= f64(px(LOOK.isle))*per*0.75 do p.under, p.cliff = o, -1
	}
}

// A few words beside the pointer on the island: why a shore takes no boat.
plan_tip :: proc() -> string {
	p := &planning
	if p.cliff < 0 do return ""
	bound(&formed[p.isle])
	m := middle_of(land.grid, p.cliff)
	return fmt.tprintf("No boat can be drawn up here: the shore stands %.0f m over the sea.", ground(m.x, m.y, LAND_CELL).h)
}

// What the pointer is on, in words, for a script to ask.
plan_under :: proc() -> string {
	p := &planning
	if p.under >= 0 {
		k := &p.cards[1 if p.under != p.landed.cell else 0]
		return fmt.tprintf("%s: %s", k.title, strings.to_lower(k.sub, context.temp_allocator))
	}
	return plan_tip()
}

// The screen, listed.
plan_build :: proc() {
	c, p, d := &chart, &planning, &door
	if !plan_open(c.pick) {   // no island in the hand, or its land not formed: the world's screen
		d.screen = .Chart
		chart_build()
		return
	}
	c.wide, c.high = screen.w, screen.h
	c.free = chart_free()
	chart_move(d.dt)
	chart_map(false)
	c.card_at = {}
	plan_marks()
	plan_head()
	plan_side()
	plan_point(d.pointer)
	if len(p.offered) == 0 do return
	if p.under >= 0 && p.under != p.landed.cell {
		site_card(&p.cards[1], p.under, nil)
		plan_card(&p.cards[1], false)
	} else do plan_card(&p.cards[0], true)
}
