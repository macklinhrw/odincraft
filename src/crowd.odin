package main

import "base:builtin"
import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

// The dwarves on screen (docs/foundations/interface.md, I14 and section 4): their place at the top
// of the play screen, their list, and several of them in the hand. The hold grows, so nothing here
// is made for seven: the top shows who needs the player, then who the player keeps in view, then the
// count of all, and is as wide at a hundred dwarves as at seven; the list finds, groups and folds.
//
// Everything is read from what the hold last showed, through its calls (hold_count, hold_card,
// hold_where; hold.odin). What "needs you" means is a table, NEEDS: a row for each cause, worst
// first. Before dwarves have needs (plan.md, P4) the causes are the three the hold can tell of where
// a dwarf stands. Hunger and hurt will be rows.

// A cause for a dwarf to need the player: the word for how a dwarf with it is; what is so of one
// such dwarf and of several, which its row, its card and its alert say ("Yrsa Coalsleeve is shut
// in: ...", "Two dwarves are shut in: ...": one alert that counts them, I14); what such a dwarf
// waits for; and its sign, a shape and not only a colour (I9).
Need :: struct {
	id, word:  string,
	one, many: string,
	waits:     string,
	sign:      Sign,
	holds:     proc(d: ^Seen) -> bool,
}
NEEDS := [?]Need{
	// Needs (needs.odin): a dwarf with nothing left to drink or to eat is dying, and one that has looked for water or food and found none soon will be.
	{"parched", "parched", "parched: it has had nothing to drink, and dies of thirst unless it does", "parched: they have had nothing to drink, and die of thirst unless they do",
		"Send the party to a stream, a lake or a pond, or make a way to one", .Trouble, proc(d: ^Seen) -> bool { return d.doing != .Dead && d.doing != .Aboard && d.want[.Drink] <= 0 }},
	{"starving", "starving", "starving: it has had nothing to eat, and dies of hunger unless it does", "starving: they have had nothing to eat, and die of hunger unless they do",
		"Mark plants to gather or water to fish, or send the party where food grows", .Trouble, proc(d: ^Seen) -> bool { return d.doing != .Dead && d.doing != .Aboard && d.want[.Food] <= 0 }},
	{"freezing", "numb with cold", "numb with cold: it has no warmth left, and dies of cold unless it is warmed", "numb with cold: they have no warmth left, and die of cold unless they are warmed",
		"Have a fire built (Build, then Fire), or a room dug or roofed, and mark a place to sleep there", .Trouble, proc(d: ^Seen) -> bool { return d.doing != .Dead && d.doing != .Aboard && d.want[.Warm] <= 0 }},
	{"no-water", "no water", "thirsty: it finds no way to fresh water", "thirsty: they find no way to fresh water",
		"Send the party to a stream, a lake or a pond, or make a way to one", .Caution, proc(d: ^Seen) -> bool { return d.doing != .Dead && .Drink in d.lacks }},
	{"no-food", "no food", "hungry: no food lies in the hold, and nothing within its reach bears any now", "hungry: no food lies in the hold, and nothing within their reach bears any now",
		"Mark plants to gather or water to fish, or send the party where food grows", .Caution, proc(d: ^Seen) -> bool { return d.doing != .Dead && .Food in d.lacks }},
	{"no-warmth", "cold", "cold: no fire burns and no roof stands within its reach", "cold: no fire burns and no roof stands within their reach",
		"Have a fire built (Build, then Fire), or a room dug or roofed, and mark a place to sleep there", .Caution, proc(d: ^Seen) -> bool { return d.doing != .Dead && .Warm in d.lacks }},
	{"no-ground", "no ground", "without ground: none lies under it or within six steps", "without ground: none lies under them or within six steps",
		"Waits for a block to be laid within its reach", .Trouble, proc(d: ^Seen) -> bool { return d.plight == .No_Ground }},
	{"shut-in", "shut in", "shut in: no way leads out of where it stands", "shut in: no way leads out of where they stand",
		"Waits for a way out to be dug or laid", .Trouble, proc(d: ^Seen) -> bool { return d.plight == .Shut_In }},
	{"no-way", "no way", "stopped: it found no way to where it was sent", "stopped: they found no way to where they were sent",
		"Waits for word from the hold, or for a way to be made", .Caution, proc(d: ^Seen) -> bool { return d.plight == .No_Way }},
	// Orders (orders.odin): a dwarf with nothing to do while work is marked that it cannot take, by what the work waits for.
	{"no-reach", "cannot reach the work", "idle: no way leads to the work that is marked", "idle: no way leads to the work that is marked",
		"Waits for a way to it to be dug or built, or for other work", .Caution, proc(d: ^Seen) -> bool { return d.lack == .No_Way }},
	{"no-stuff", "nothing to build with", "idle: no stone or timber lies anywhere to build what is marked", "idle: no stone or timber lies anywhere to build what is marked",
		"Waits for rock to be dug or trees felled, or for other work", .Caution, proc(d: ^Seen) -> bool { return d.lack == .No_Stuff }},
	{"too-hard", "rock too hard", "idle: what is marked is rock too hard for the party's picks", "idle: what is marked is rock too hard for the party's picks",
		"Waits for softer ground to be marked", .Caution, proc(d: ^Seen) -> bool { return d.lack == .Too_Hard }},
}

FOLD_OVER :: 8   // a group of the list longer than this folds to its count,
FOLD_SHOW :: 5   // under its first few

// A word begun with a capital.
capital :: proc(s: string) -> string {
	if s == "" || s[0] < 'a' || s[0] > 'z' do return s
	return fmt.tprintf("%c%s", s[0] - 32, s[1:])
}

// A count of years or of things in words, as far as a dwarf lives.
number_words :: proc(n: int) -> string {
	ONES := [20]string{"no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"}
	TENS := [10]string{"", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"}
	switch {
	case n < 0 || n >= 1000: return fmt.tprint(n)
	case n < 20:   return ONES[n]
	case n < 100:  return TENS[n/10] if n%10 == 0 else fmt.tprintf("%s-%s", TENS[n/10], ONES[n%10])
	case n%100 == 0: return fmt.tprintf("%s hundred", ONES[n/100])
	}
	return fmt.tprintf("%s hundred and %s", ONES[n/100], number_words(n%100))
}

// A line of text cut to a width, with a mark that there is more.
fit :: proc(style: Style, s: string, wide: f32) -> string {
	if text_wide(style, s) <= wide do return s
	b, face := &ui.baked[style], LOOK.type[style].face
	room := wide - text_wide(style, "…")
	last, w, cut := -1, f32(0), 0
	for r, i in s {
		g := glyph_of(r)
		if last >= 0 && last < 95 && g < 95 do w += f32(ui.kern[face][last][g])*b.scale
		w += b.glyphs[g].advance
		if w > room do break
		cut, last = i + utf8.rune_size(r), g
	}
	return fmt.tprintf("%s…", strings.trim_right_space(s[:cut]))
}

who_name :: proc(i: int) -> string {
	who := watch.seen.dwarves[i].who
	return fmt.tprintf("%s %s", who.given, who.byname)
}

// ---- who needs the player, and the alerts that count them ---------------------------------------

// Each frame: every dwarf's row of NEEDS, those with one worst first, and an alert for each row that
// holds for anyone. An alert is raised again only when those it counts have changed.
crowd_read :: proc() {
	u := &play
	n := hold_count()
	if !u.greeted && n > 0 {   // those who came in the first boat are kept in view from the start
		u.greeted = true
		for i in 0..<min(n, LANDING) do append(&u.kept, i)
	}
	for list in ([2]^[dynamic]int{&u.kept, &u.several}) do for k := len(list^) - 1; k >= 0; k -= 1 do if list[k] >= n do ordered_remove(list, k)
	for k := len(u.kept) - 1; k >= 0; k -= 1 do if watch.seen.dwarves[u.kept[k]].doing == .Dead do ordered_remove(&u.kept, k)   // the dead are not kept in view at the top: the list has them
	// A death is told as an alert that stands until it is looked at; and a hold with no food lying, whose dwarves forage as they hunger, is told so with what to do.
	for len(u.mourned) < n do append(&u.mourned, false)
	for &d, i in watch.seen.dwarves do if d.doing == .Dead && !u.mourned[i] {
		u.mourned[i] = true
		alert_raise(fmt.tprintf("died-%d", i), fmt.tprintf("%s has died of %s.", who_name(i), WANTS[d.died].of), .Trouble, d.at)
	}
	if hungry := watch.seen.foraging && watch.seen.food_days <= 0; hungry != u.foraging {
		u.foraging = hungry
		if hungry do alert_raise("hand-to-mouth", fmt.tprintf("No food in store: the dwarves forage as they hunger. Gather (%s) or fish (%s), and store it.", key_for(.Order, int(Tool.Gather)), key_for(.Order, int(Tool.Fish))), .Caution)
		else do alert_clear("hand-to-mouth")
	}
	// The lean season ahead, or in hand, while the kept food in store falls short of it: one alert, said anew when its figures change (lean_of, needs.odin).
	lean := watch.seen.lean
	text := lean_alert(lean) if lean.on && lean.kept < f32(lean.days) else ""
	if text != u.lean_said {
		delete(u.lean_said)
		u.lean_said = strings.clone(text)
		if text == "" do alert_clear("lean")
		else do alert_raise("lean", text, .Trouble if lean.off == 0 && lean.kept < 1 else .Caution)
	}
	builtin.resize(&u.need, n)
	clear(&u.needing)
	for &d, i in watch.seen.dwarves {
		u.need[i] = -1
		for row, k in NEEDS do if row.holds(&d) {
			u.need[i] = i8(k)
			break
		}
	}
	for row, k in NEEDS {
		sum, count, first := u64(0xcbf29ce484222325), 0, -1
		for v, i in u.need do if int(v) == k {
			append(&u.needing, i)
			sum = (sum ~ u64(i + 1))*0x100000001b3
			count += 1
			if first < 0 do first = i
		}
		if count == 0 do sum = 0
		if sum == u.alerted[k] do continue
		u.alerted[k] = sum
		if count == 0 {
			alert_clear(row.id)
			continue
		}
		at, _ := hold_where(first)
		alert_raise(row.id, fmt.tprintf("%s is %s.", who_name(first), row.one) if count == 1 else fmt.tprintf("%s dwarves are %s.", capital(number_words(count)), row.many), row.sign, at, k)
	}
}

// ---- the hand: one dwarf, or several ------------------------------------------------------------

in_hand :: proc(i: int) -> bool {
	return (play.hand.kind == .Dwarf || play.hand.kind == .Dwarves) && slice.contains(play.several[:], i)
}

// Take these dwarves in the hand: one as itself, several as a group, none as an empty hand.
dwarves_take :: proc(who: []int) {
	u := &play
	list := slice.clone(who, context.temp_allocator)
	slice.sort(list)
	switch len(list) {
	case 0: hand_take({})
	case 1: hand_take({kind = .Dwarf, dwarf = list[0], feature = -1})
	case:
		hand_take({kind = .Dwarves, dwarf = -1, feature = -1})
		clear(&u.several)
		append(&u.several, ..list)
	}
}

// Take a dwarf in the hand; or, adding, put it with those there, or take it from among them.
dwarf_take :: proc(i: int, add := false) {
	u := &play
	if i < 0 || i >= hold_count() do return
	list := make([dynamic]int, context.temp_allocator)
	if add && (u.hand.kind == .Dwarf || u.hand.kind == .Dwarves) do append(&list, ..u.several[:])
	if at, found := slice.linear_search(list[:], i); found do ordered_remove(&list, at)
	else do append(&list, i)
	dwarves_take(list[:])
}

// The dwarves that stand in a box of blocks marked from above, or a little over it.
dwarves_in :: proc(lo, hi: [3]i32) -> []int {
	who := make([dynamic]int, context.temp_allocator)
	for i in 0..<hold_count() {
		at, _ := hold_where(i)
		x, y, z := i32(math.floor(at.x)), i32(math.floor(at.y)), i32(math.floor(at.z))
		if x >= lo.x && x <= hi.x && z >= lo.z && z <= hi.z && y >= lo.y - 2 && y <= hi.y + 4 do append(&who, i)
	}
	return who[:]
}

// The middle of the dwarves in the hand, for the view to go to.
several_middle :: proc() -> (at: [2]f64, ok: bool) {
	for i in play.several do if p, there := hold_where(i); there do at, ok = at + p.xz/f64(len(play.several)), true
	return
}

// Keep a dwarf in view at the top, or let it go; with -1, those in the hand: all kept, unless all are already.
keep :: proc(i: int) {
	u := &play
	who := []int{i}
	if i < 0 do who = u.several[:] if u.hand.kind == .Dwarf || u.hand.kind == .Dwarves else nil
	all := len(who) > 0
	for w in who do all &&= slice.contains(u.kept[:], w)
	for w in who {
		at, found := slice.linear_search(u.kept[:], w)
		if all && found do ordered_remove(&u.kept, at)
		if !all && !found do append(&u.kept, w)
	}
}

// ---- a dwarf's picture --------------------------------------------------------------------------

// The cuts a hood and a beard come in. With a dwarf's own colours and its trade's cloth they make
// its picture its own.
HOODS_CUT  := [3][2]string{{".hhhhhh.", "hhhhhhhh"}, {"...hh...", ".hhhhhh."}, {"hhhhhhhh", "hhhhhhhh"}}
BEARDS_CUT := [4][3]string{{"bbbbbbbb", "cbbbbbbc", "ccbbbbcc"}, {"bbbbbbbb", "ccbbbbcc", "cccccccc"}, {"bbbbbbbb", "cbbbbbbc", "cccbbccc"}, {"bbbbbbbb", "cbbccbbc", "cbbccbbc"}}
FACE       := [3]string{"hssssssh", "hsessesh", "bssnnssb"}

// A dwarf's picture: a small bust of blocks, eight by eight (I10): hood, face and beard over the
// shoulders of its tunic. Its colours are the ones it wears on the land, and the cut of its hood and
// beard come of its name, so it is the same wherever it is shown. Its edge is brass where the dwarf
// is in the hand, and a sign stands on its corner where it needs the player.
bust :: proc(r: Rect, who: Facts, chosen := false, act := Act.None, arg := 0, id := "", says := "", tip := "", sign := Sign.None) {
	L := &LOOK
	shade :: proc(c: u32, by: f32 = 1) -> Colour { return {u8(f32(c >> 16 & 255)*by), u8(f32(c >> 8 & 255)*by), u8(f32(c & 255)*by), 255} }
	part(.Niche, r, says, state = {.Chosen} if chosen else {}, act = act, arg = arg, id = id, tip = tip)
	cut := fnv.fnv32a(transmute([]u8)who.given)*31 + fnv.fnv32a(transmute([]u8)who.byname)
	hood, beard := HOODS_CUT[cut%len(HOODS_CUT)], BEARDS_CUT[cut/7%len(BEARDS_CUT)]
	rows := [8]string{hood[0], hood[1], FACE[0], FACE[1], FACE[2], beard[0], beard[1], beard[2]}
	edge := max(1, math.round(f32(ui.module)/4))
	cell := math.floor((r.w - 4*edge)/8)
	x0, y0 := r.x + math.floor((r.w - 8*cell)/2), r.y + math.floor((r.h - 8*cell)/2)
	for row, y in rows {
		from := 0
		for x in 1..=8 do if x == 8 || row[x] != row[from] {   // a run of one colour is one rectangle
			c: Colour
			switch row[from] {
			case 'h': c = shade(who.hood)
			case 's': c = shade(who.skin)
			case 'n': c = shade(who.skin, 0.86)
			case 'b': c = shade(who.beard)
			case 'c': c = shade(TRADES[who.trade].cloth)
			case 'e': c = L.eye
			}
			if c.a != 0 do part(.Fill, {x0 + f32(from)*cell, y0 + f32(y)*cell, f32(x - from)*cell, cell}, colour = c)
			from = x
		}
	}
	if sign != .None {   // on its corner, with a dark edge to stand clear of the hood
		s, o := px(L.sign), px(0.75)
		at := Rect{r.x + r.w - math.round(s*0.7), r.y - math.round(s*0.3), s, s}
		part(.Sign, {at.x - o, at.y - o, s + 2*o, s + 2*o}, colour = L.pit).sign = sign
		part(.Sign, at).sign = sign
	}
}

need_sign :: proc(i: int) -> Sign { return NEEDS[play.need[i]].sign if play.need[i] >= 0 else .None }

// How a dwarf is, in a word, and how grave that is (0 well, 1 wanting, 2 urgent, 3 and over dying):
// what needs the player first; then dead, or asleep; then the worst of its thirst, hunger and
// tiredness by its row of WANTS; else well.
dwarf_how :: proc(i: int) -> (word: string, grave: int) {
	d := &watch.seen.dwarves[i]
	if k := play.need[i]; k >= 0 do return NEEDS[k].word, 3 if NEEDS[k].sign == .Trouble else 2
	if d.doing == .Dead do return "dead", 0
	if d.doing == .Aboard || d.doing == .Ashore do return "well", 0
	worst, at := 0, Want.Drink
	for w in Want do if s := want_stage(w, d.want[w]); s > worst do worst, at = s, w
	if d.doing == .Sleeping && worst < 2 do return "asleep", 0
	if worst == 0 && d.wet > 0.5 do return "wet", 1
	if worst == 0 do return "well", 0
	return WANTS[at].how[worst], worst
}

// A dwarf's needs as four meters, two to a row, each with its name, the word for how it stands
// and a bar that empties, coloured by how grave it is: what it feels, at a glance (I3, I9: a word
// and a length, not only a colour). Returns how high they are.
FEELS := [Want]string{.Drink = "Drink", .Food = "Food", .Sleep = "Sleep", .Warm = "Warmth"}
feel_high :: proc() -> f32 { return line_of(.Small) + px(0.75) + px(1.25) }
feels_high :: proc() -> f32 { return 2*feel_high() + px(2) }
feels_row :: proc(x, y, wide: f32, i: int) -> f32 {
	L := &LOOK
	d := &watch.seen.dwarves[i]
	gap := px(6)
	w := math.floor((wide - gap)/2)
	for want, k in Want {
		row := WANTS[want]
		stage := want_stage(want, d.want[want])
		if row.kills > 0 && d.spent[want] >= 0.5 do stage = 4
		word := "asleep" if want == .Sleep && d.doing == .Sleeping else "wet" if want == .Warm && stage == 0 && d.wet > 0.5 else row.how[stage]
		colour := L.ash if stage == 0 else L.brass if stage <= 2 else L.cinnabar
		cx, cy := x + f32(k%2)*(w + gap), y + f32(k/2)*(feel_high() + px(2))
		tip: string
		switch want {
		case .Drink: tip = "A dwarf drinks about three times a day, standing in fresh water."
		case .Food:  tip = "A dwarf eats about twice a day, of what lies in the hold or about it."
		case .Sleep: tip = "A dwarf sleeps at night for choice: in a place marked to sleep in, under its roof first; with none, under a roof or by a fire near it, or on dry ground where it is."
		case .Warm:
			at := "indoors" if indoors({d.roof, d.walls}) else "under a roof" if d.roof else "in the open"
			tip = fmt.tprintf("It feels %.0f °C where it stands, %s%s%s. A dwarf is chilled under %.0f °C: by the cold, by the wind and by being wet. It warms itself by a fire, or under a roof and inside walls.", math.round(d.felt), at,
				", by a fire" if d.by_fire else "", ", wet through" if d.wet > 0.7 else ", wet" if d.wet > 0.2 else "", f32(COMFORT))
		}
		if row.slows > 0 && d.want[want] < row.urgent do tip = fmt.tprintf("%s While it is %s its hands are a fifth slower at work.", tip, row.how[2] if d.want[want] > 0 else row.how[3])
		part(.Head, {cx, cy, w, feel_high()}, tip = fmt.tprintf("%s: %s. %s", capital(row.name), word, tip))
		part(.Text, {cx, cy, w, line_of(.Small)}, FEELS[want], .Small, L.ash, id = "hand.feel.name")
		part(.Text, {cx, cy, w, line_of(.Small)}, word, .Small, colour if stage > 0 else L.chalk, {.Right}, id = "hand.feel")
		by := cy + line_of(.Small) + px(0.75)
		part(.Fill, {cx, by, w, px(1.25)}, colour = L.pit)
		part(.Fill, {cx, by, math.round(w*clamp(d.want[want], 0, 1)), px(1.25)}, colour = L.verdigris if stage == 0 else colour)
	}
	return feels_high()
}

// ---- top middle: the dwarves --------------------------------------------------------------------

// How wide the count of all is, which is the least the dwarves' place at the top can be.
crowd_count :: proc(n: int) -> f32 { return max(text_wide(.Figure, fmt.tprint(n)), text_wide(.Small, "dwarves")) + 2*px(LOOK.chip_pad.x) }
crowd_least :: proc() -> f32 { return 2*px(LOOK.pad.x) + crowd_count(hold_living()) if hold_count() > 0 else 0 }

// Top middle: first the dwarves who need the player, worst first, each with its sign; then those
// kept in view; then the count of all, which opens the list. It takes the room between the place
// and the alerts and never more pictures than LOOK.crowd, so it reads the same at seven dwarves and
// at seventy: where more need the player or are kept than it has room for, the last picture's place
// says how many more, and opens the list on them. A click takes a dwarf in the hand, a second takes
// the view to it, and with Shift a click adds it to the hand.
crowd_build :: proc() {
	u, L := &play, &LOOK
	u.area = .Dwarves
	if hold_count() == 0 do return
	n := hold_living()   // the count is of the living: the hold is as many as are alive
	left, right := px(L.margin) + u.place_wide + px(2), u.crowd_right - px(2)
	b, gap, space := px(L.bust), px(L.gap), px(L.space)
	count := crowd_count(n)
	if right - left < 2*px(L.pad.x) + count do return   // no room at this size: the lists' button still leads to them
	slots := clamp(int((right - left - 2*px(L.pad.x) - count - 2*space)/(b + gap)), 0, L.crowd)
	others := make([dynamic]int, context.temp_allocator)   // kept in view, and not already shown as needing
	for k in u.kept do if u.need[k] < 0 do append(&others, k)
	// Who gets a picture: those who need the player first; where there are more than places, the last place counts the rest.
	take :: proc(have, places: int) -> (shown, more: int) {
		shown = min(have, places)
		if more = have - shown; more > 0 && shown > 0 do shown, more = shown - 1, more + 1
		return shown, more if places > 0 else 0
	}
	a, more_a := take(len(u.needing), slots - min(len(others), slots/3))   // those kept in view hold a third of the places against a crowd in need
	k, more_k := take(len(others), slots - a - int(more_a > 0))
	wide :: proc(pictures: int, b, gap: f32) -> f32 { return f32(pictures)*b + f32(max(pictures - 1, 0))*gap }
	first, second := a + int(more_a > 0), k + int(more_k > 0)
	inner := wide(first, b, gap) + (space if first > 0 else 0) + wide(second, b, gap) + (space if second > 0 else 0) + count
	high := max(b, line_of(.Figure) + line_of(.Small))
	w := inner + 2*px(L.pad.x)
	r := Rect{clamp(math.round((screen.w - w)/2), left, right - w), px(L.margin), w, high + 2*px(L.pad.y)}
	part(.Panel, r, id = "crowd")
	x, y := r.x + px(L.pad.x), r.y + px(L.pad.y) + math.round((high - b)/2)
	picture :: proc(x, y: f32, i: int, id: string) {
		who := watch.seen.dwarves[i].who
		says := fmt.tprintf("%s, %s%s", who_name(i), TRADES[who.trade].name, fmt.tprintf(": %s", NEEDS[play.need[i]].word) if play.need[i] >= 0 else "")
		bust({x, y, px(LOOK.bust), px(LOOK.bust)}, who, in_hand(i), .Who, i, id, says, fmt.tprintf("%s. %s", says, dwarf_brief(i)), need_sign(i))
	}
	more :: proc(x, y: f32, n, which: int, tip: string) {
		b := px(LOOK.bust)
		part(.Head, {x, y, b, b}, act = .Crowd, arg = which, tip = tip)
		part(.Text, {x, y + math.round((b - line_of(.Body))/2), b, line_of(.Body)}, fmt.tprintf("+%d", n), .Body, LOOK.ash, {.Centre}, id = "crowd.more")
	}
	rule :: proc(x, y, high: f32) { part(.Fill, {x, y, 1, high}, colour = LOOK.edge) }
	for i in u.needing[:a] {
		picture(x, y, i, "crowd.need")
		x += b + gap
	}
	if more_a > 0 {
		more(x, y, more_a, 0, "More dwarves need you than there is room to show. Open the list on them.")
		x += b + gap
	}
	if first > 0 {
		rule(x - gap + math.round(space/2), r.y + px(L.pad.y), high)
		x += space - gap
	}
	for i in others[:k] {
		picture(x, y, i, "crowd.kept")
		x += b + gap
	}
	if more_k > 0 {
		more(x, y, more_k, 1, "More dwarves are kept in view than there is room to show. Open the list on them.")
		x += b + gap
	}
	if second > 0 {
		rule(x - gap + math.round(space/2), r.y + px(L.pad.y), high)
		x += space - gap
	}
	// The count of all, which opens the list.
	top := r.y + px(L.pad.y) + math.round((high - line_of(.Figure) - line_of(.Small))/2)
	part(.Head, {x, r.y + px(L.pad.y), count, high}, act = .List, arg = int(List.Dwarves), tip = "Every dwarf of the hold, in a list.")
	part(.Text, {x, top, count, line_of(.Figure)}, fmt.tprint(n), .Figure, {}, {.Centre}, id = "crowd.count")
	part(.Text, {x, top + line_of(.Figure), count, line_of(.Small)}, "dwarves" if n != 1 else "dwarf", .Small, L.ash, {.Centre})
}

// On the land: a brass square round each dwarf in the hand, and over each that needs the player its sign.
crowd_marks :: proc() {
	u, L := &play, &LOOK
	for i in 0..<hold_count() {
		held := in_hand(i)
		if !held && u.need[i] < 0 do continue
		at, _ := hold_where(i)
		tall := f64(watch.seen.dwarves[i].who.tall)
		foot, _ := project(at)
		head, seen := project(at + {0, tall, 0})
		if !seen do continue
		h := max(foot.y - head.y, px(3)) + px(2)
		x, y := math.round(head.x - h/2), math.round(head.y - px(1))
		if held {
			e := max(2, px(0.5))
			for k in ([4]Rect{{x, y, h, e}, {x, y + h - e, h, e}, {x, y, e, h}, {x + h - e, y, e, h}}) do part(.Fill, k, colour = L.brass)
		}
		if u.need[i] >= 0 {
			s, o := px(L.sign), px(0.75)
			sign := Rect{math.round(head.x - s/2), y - s - px(1), s, s}
			part(.Sign, {sign.x - o, sign.y - o, s + 2*o, s + 2*o}, colour = L.pit).sign = need_sign(i)
			part(.Sign, sign).sign = need_sign(i)
		}
	}
}

// ---- the Dwarves list ---------------------------------------------------------------------------

// The named place a dwarf is nearest, as the list groups by it and finds by it.
dwarf_place :: proc(i: int) -> (key: int, name: string) {
	if watch.seen.dwarves[i].doing == .Aboard do return 0, "In the boat"
	at, _ := hold_where(i)
	f := island_near(at.x, at.z)
	if f == nil do return 1, "On ground with no name"
	bound(f)
	p, _ := place_near(at.x - f64(region.origin.x), at.z - f64(region.origin.y))
	if p < 0 do return 1, "On ground with no name"
	return 2 + p, fmt.tprintf("Near %s", capital(places[p].name))
}

// The Dwarves list, down the right side: a row each, with its picture, name, trade, what it is
// doing and a word for how it is. It finds by name, trade or place; groups by need, by trade or by
// place; a group longer than FOLD_OVER shows its first few and folds the rest to their count; and
// a row takes the view to its dwarf and puts it in the hand, or with Shift adds it to the hand
// (I4, I14). Only the rows in view are listed, so a hundred cost what a dozen do.
dwarves_build :: proc() {
	u, L := &play, &LOOK
	u.area = .List
	n := hold_count()
	found := string(u.find[:])
	box, x, inner := list_head("Dwarves", fmt.tprint(n), "Find by name, trade or place", {"By need", "By trade", "By place"}, u.by, "Kept in view", u.only_kept)
	Entry :: struct { who, group, rank: int, name: string }
	rows := make([dynamic]Entry, context.temp_allocator)
	needle := strings.to_lower(found, context.temp_allocator)
	GROUPS := [7]string{"Need you", "Seeing to themselves", "At work", "Walking", "Idle", "Coming ashore", "Dead"}
	for i in 0..<n {
		d := &watch.seen.dwarves[i]
		if u.only_kept && !slice.contains(u.kept[:], i) do continue
		e := Entry{who = i, rank = int(u.need[i]) if u.need[i] >= 0 else len(NEEDS)}   // in any group, those who need the player first, worst first
		place := ""
		if u.by == 2 || needle != "" do e.group, place = dwarf_place(i)
		switch u.by {
		case 0:
			e.group = 0 if u.need[i] >= 0 else 6 if d.doing == .Dead else 1 if d.caring else 2 if d.job || d.working || d.carrying > 0 || d.fetching else 3 if d.doing == .Walking else 4 if d.doing == .Waiting || d.doing == .Stopped else 5
			e.name = GROUPS[e.group]
		case 1:
			e.group, e.name = d.who.trade, fmt.tprintf("%ss", capital(TRADES[d.who.trade].name))
		case:
			e.name = place
		}
		how, _ := dwarf_how(i)
		if needle != "" && !strings.contains(strings.to_lower(fmt.tprintf("%s %s %s %s", who_name(i), TRADES[d.who.trade].name, place, how), context.temp_allocator), needle) do continue
		append(&rows, e)
	}
	slice.stable_sort_by(rows[:], proc(a, b: Entry) -> bool { return a.group < b.group || a.group == b.group && a.rank < b.rank })
	counts: [128]int
	for e in rows do counts[e.group%len(counts)] += 1

	u.clip = box
	row_high := 2*line_of(.Body) + 2*px(L.row_pad.y)
	head_high := line_of(.Body) + px(3) + px(1.5)
	b := px(L.bust)
	top := list_top(box)
	cy := top
	group, shown := -1, 0
	for e, k in rows {
		g := e.group%len(counts)
		if e.group != group {
			group, shown = e.group, 0
			part(.Head, {box.x, cy, box.w, head_high}, act = .Fold, arg = g, id = "list.group", tip = "Fold this group to its count, or open it.")
			part(.Text, {x, cy + px(3), inner, line_of(.Body)}, e.name, .Body, L.ash, id = "list.group.name")
			part(.Text, {x, cy + px(3), inner, line_of(.Body)}, fmt.tprint(counts[g]), .Body, L.ash, {.Right})
			cy += head_high
		}
		if needle == "" && g in u.folded do continue
		long := needle == "" && counts[g] > FOLD_OVER
		shown += 1
		if long && g not_in u.whole && shown > FOLD_SHOW {
			if shown == FOLD_SHOW + 1 {   // the rest of a long group, as their count
				part(.Head, {box.x, cy, box.w, head_high}, act = .Whole, arg = g, id = "list.more", tip = "Show the whole group.")
				part(.Text, {x, cy + px(1.5), inner, line_of(.Body)}, fmt.tprintf("%s more", capital(number_words(counts[g] - FOLD_SHOW))), .Body, L.ash, id = "list.more.count")
				part(.Text, {x, cy + px(1.5), inner, line_of(.Body)}, "show all", .Body, L.ash, {.Right})
				cy += head_high
			}
			continue
		}
		if cy + row_high > box.y && cy < box.y + box.h {   // in view
			i := e.who
			d := &watch.seen.dwarves[i]
			part(.Row, {box.x, cy, box.w, row_high}, state = {.Chosen} if in_hand(i) else {}, act = .Lead, arg = i, id = "list.row", tip = "Go to this dwarf, and take it in the hand. With Shift, add it to the hand.")
			bust({x, cy + math.round((row_high - b)/2), b, b}, d.who, false, sign = need_sign(i))
			tx := x + b + px(3)
			how, grave := dwarf_how(i)
			colour := L.ash if grave == 0 else L.cinnabar if grave >= 3 else L.brass
			part(.Text, {x, cy + px(L.row_pad.y), inner, line_of(.Body)}, how, .Body, colour, {.Right}, id = "list.row.how")
			name := who_name(i)
			part(.Text, {tx, cy + px(L.row_pad.y), text_wide(.Name, name), line_of(.Body)}, name, .Name, id = "list.row.name")
			part(.Text, {tx + text_wide(.Name, name), cy + px(L.row_pad.y), inner, line_of(.Body)}, fmt.tprintf(", %s", TRADES[d.who.trade].name), .Body, L.ash, id = "list.row.trade")
			kept := slice.contains(u.kept[:], i)
			word := "Kept" if kept else "Keep"
			chip := text_wide(.Small, "Keep") + 2*px(L.chip_pad.x)
			part(.Text, {tx, cy + px(L.row_pad.y) + line_of(.Body), inner, line_of(.Body)}, fit(.Body, dwarf_brief(i), x + inner - tx - chip - px(3)), .Body, L.ash, id = "list.row.doing")
			part(.Chip, {x + inner - chip, cy + px(L.row_pad.y) + line_of(.Body) + math.round((line_of(.Body) - line_of(.Small) - 2*px(L.chip_pad.y))/2), chip, line_of(.Small) + 2*px(L.chip_pad.y)}, word, .Small, {}, {.Chosen, .Faint} if kept else {.Faint}, .Keep, i, id = "list.keep",
				tip = "Keep this dwarf's picture at the top of the screen, or let it go.")
		}
		cy += row_high
		if long && g in u.whole && (k + 1 == len(rows) || rows[k + 1].group != e.group) {
			part(.Head, {box.x, cy, box.w, head_high}, act = .Whole, arg = g, id = "list.fewer", tip = "Fold the group to its first few again.")
			part(.Text, {x, cy + px(1.5), inner, line_of(.Body)}, "show fewer", .Body, L.ash, {.Right})
			cy += head_high
		}
	}
	if len(rows) == 0 do part(.Text, {x, cy + px(3), inner, line_of(.Body)}, "No dwarf of the hold answers to that." if n > 0 else "No dwarves have come.", .Body, L.ash, id = "list.none")
	u.clip = {}
	list_foot(box, top, cy)
}

// What a dwarf is doing, in a line short enough for a row: its point first, since the row may cut its end.
dwarf_brief :: proc(i: int) -> string {
	s := &watch.seen
	if k := play.need[i]; k >= 0 do return fmt.tprintf("%s.", capital(NEEDS[k].one))
	if d := s.dwarves[i]; d.job || d.caring || d.doing == .Dead || d.carrying > 0 || d.fetching do return fmt.tprintf("%s.", hold_card(i).doing)   // at work, on its way to it, or seeing to itself (orders.odin, needs.odin)
	to := fmt.tprintf("the %s", s.place) if s.errand == 0 else s.place
	switch s.dwarves[i].doing {
	case .Aboard:  return "In the boat."
	case .Ashore:  return "Stepping ashore."
	case .Walking: return fmt.tprintf("Walking to %s.", to)
	case .Waiting, .Stopped: return fmt.tprintf("Waiting for word at %s.", to)
	case .Working, .Drinking, .Eating, .Sleeping, .Warming, .Dead: return fmt.tprintf("%s.", hold_card(i).doing)
	}
	return ""
}

// ---- the cards ----------------------------------------------------------------------------------

// A dwarf's card (I2, I3): its name, its trade and age, what it is doing and why, what it waits
// for, and under tabs what there is to know of it so far: its trade, and what it knows of itself.
Dwarf_Card :: struct { title, sub, line, next, trade, self: string }
dwarf_says :: proc(i: int) -> (c: Dwarf_Card) {
	d := &watch.seen.dwarves[i]
	who, card := d.who, hold_card(i)
	t := TRADES[who.trade]
	c.title, c.sub = who_name(i), fmt.tprintf("%s, %s", t.name, number_words(who.age))
	c.line, c.next = fmt.tprintf("%s.", card.doing), fmt.tprintf("%s.", card.next) if card.next != "" else ""
	if k := play.need[i]; k >= 0 {   // what is wrong leads, in the screen's own words; the hold's are long, and say where it was sent
		c.line = dwarf_brief(i)
		c.next = fmt.tprintf("%s%s.", fmt.tprintf("It was sent to %s. ", watch.seen.place) if watch.seen.errand > 0 else "", NEEDS[k].waits)
	}
	with := strings.builder_make(context.temp_allocator)
	others := 0
	for o, k in watch.seen.dwarves do if k != i && o.who.trade == who.trade {
		if others < 3 do fmt.sbprintf(&with, "%s%s", ", " if others > 0 else "", who_name(k))
		others += 1
	}
	c.trade = fmt.tprintf("A %s %s.\n%s", t.name, t.does,
		fmt.tprintf("%s is the hold's only %s.", who.given, t.name) if others == 0 else
		fmt.tprintf("The hold has %s other%s: %s%s.", number_words(others), "" if others == 1 else "s", strings.to_string(with), fmt.tprintf(" and %s more", number_words(others - 3)) if others > 3 else ""))
	age := "young" if who.age < 40 else "in its prime" if who.age < 80 else "old"
	c.self = fmt.tprintf("%s is %s years old, %s for a dwarf: they come of age at twenty-five and are old past a hundred.\nIt stands %.2f m tall.%s%s", who.given, number_words(who.age), age, who.tall,
		"\nIt came in the first boat." if i < LANDING else "",
		fmt.tprintf("\nIt has walked about %s since it stepped ashore.", far_words(d.stride)) if d.stride >= 10 else "")
	return
}

// Several dwarves in the hand, as a group (I14): how many and of what trades, who they are, and what they share.
several_says :: proc() -> (title, sub, line, next: string) {
	u, s := &play, &watch.seen
	who := u.several[:]
	title = fmt.tprintf("%s dwarves", capital(number_words(len(who))))
	list :: proc(b: ^strings.Builder, items: []string, rest := "") {
		for it, k in items do fmt.sbprintf(b, "%s%s", "" if k == 0 else " and " if k == len(items) - 1 && rest == "" else ", ", it)
		if rest != "" do fmt.sbprintf(b, " and %s", rest)
	}
	// Their trades, the commonest first.
	Count :: struct { n, row: int }
	trades := make([dynamic]Count, context.temp_allocator)
	for row in 0..<len(TRADES) {
		n := 0
		for i in who do n += int(s.dwarves[i].who.trade == row)
		if n > 0 do append(&trades, Count{n, row})
	}
	slice.stable_sort_by(trades[:], proc(a, b: Count) -> bool { return a.n > b.n })
	items := make([dynamic]string, context.temp_allocator)
	left := len(who)
	for t in trades[:min(len(trades), 3)] {
		append(&items, fmt.tprintf("%s %s%s", "a" if t.n == 1 else number_words(t.n), TRADES[t.row].name, "" if t.n == 1 else "s"))
		left -= t.n
	}
	b := strings.builder_make(context.temp_allocator)
	list(&b, items[:], fmt.tprintf("%s of other trades", number_words(left)) if left > 0 else "")
	sub = strings.clone(strings.to_string(b), context.temp_allocator)
	// Who they are.
	clear(&items)
	for i in who[:min(len(who), 4)] do append(&items, who_name(i))
	strings.builder_reset(&b)
	list(&b, items[:], fmt.tprintf("%s more", number_words(len(who) - 4)) if len(who) > 4 else "")
	line = fmt.tprintf("%s.", strings.to_string(b))
	// What they share: what they are doing, and what is wrong with any.
	to := fmt.tprintf("the %s", s.place) if s.errand == 0 else s.place
	DOING := [Doing]string{.Aboard = "in the boat", .Ashore = "stepping ashore", .Walking = fmt.tprintf("walking to %s", to), .Waiting = fmt.tprintf("waiting for word at %s", to), .Stopped = "stopped where they stand", .Working = "at work", .Drinking = "drinking", .Eating = "eating", .Sleeping = "asleep", .Warming = "warming themselves", .Dead = "dead"}
	doing: [Doing]int
	for i in who do doing[s.dwarves[i].doing] += 1
	share := strings.builder_make(context.temp_allocator)
	for n, d in doing do if n == len(who) do fmt.sbprintf(&share, "All are %s.", DOING[d])
	if strings.builder_len(share) == 0 {
		clear(&items)
		for n, d in doing do if n > 0 do append(&items, fmt.tprintf("%s %s %s", number_words(n), "is" if n == 1 else "are", DOING[d]))
		strings.builder_reset(&b)
		list(&b, items[:])
		fmt.sbprintf(&share, "%s.", capital(strings.to_string(b)))
	}
	clear(&items)
	for row, k in NEEDS {
		n := 0
		for i in who do n += int(int(u.need[i]) == k)
		if n > 0 do append(&items, fmt.tprintf("%s %s", number_words(n), row.word))
	}
	if len(items) > 0 {
		strings.builder_reset(&b)
		list(&b, items[:])
		fmt.sbprintf(&share, " Need you: %s.", strings.to_string(b))
	}
	return title, sub, line, strings.to_string(share)
}

// The hand with several dwarves in it: their count and trades, a picture of each, who they are and
// what they share. A picture takes that one alone; with Shift, it leaves the group.
several_build :: proc() {
	u, L := &play, &LOOK
	if len(u.several) < 2 do return
	title, sub, line, next := several_says()
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	b, gap := px(L.bust), px(L.gap)
	most := int((inner + gap)/(b + gap))
	high := 2*px(L.pad.y) + line_of(.Title) + text_high(.Body, sub, inner) + px(L.space) + b + px(L.space) + text_high(.Body, line, inner) + px(1) + text_high(.Body, next, inner) + px(4) + px(L.button)
	r := Rect{x, screen.h - hand_foot() - high, w, high}
	part(.Panel, r, id = "hand")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(cx, y, title, .Title, id = "hand.title")
	y += words(cx, y, sub, .Body, L.ash, "hand.sub", inner) + px(L.space)
	shown := len(u.several) if len(u.several) <= most else most - 1
	for i, k in u.several[:shown] {
		bust({cx + f32(k)*(b + gap), y, b, b}, watch.seen.dwarves[i].who, false, .Who, i, "hand.dwarf", who_name(i), fmt.tprintf("%s. Take it alone; with Shift, take it out of the hand.", who_name(i)), need_sign(i))
	}
	if shown < len(u.several) do part(.Text, {cx + f32(shown)*(b + gap), y + math.round((b - line_of(.Body))/2), b, line_of(.Body)}, fmt.tprintf("+%d", len(u.several) - shown), .Body, L.ash, {.Centre}, id = "hand.more")
	y += b + px(L.space)
	y += words(cx, y, line, .Body, {}, "hand.line", inner) + px(1)
	y += words(cx, y, next, .Body, L.ash, "hand.next", inner) + px(4)
	hand_buttons(cx, y, "Go there", "Put the view over them.")
}
