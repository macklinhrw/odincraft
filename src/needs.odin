package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:strings"

// Needs (plan.md, P4, first half; docs/adr/0014): a dwarf gets thirsty, hungry and tired, each at
// its own pace, and sees to itself without being told, as the pawns of RimWorld and the dwarves of
// Dwarf Fortress do. A need is a row of WANTS: how fast it falls, when a dwarf with nothing in hand
// sees to it, when it leaves its work for it, how long the act takes, and how long a dwarf lasts
// with nothing. What it does about each is the land's: it drinks standing in fresh water that runs
// all year (fresh, landing.odin), eats a thing that lies in the hold or about it (goods.odin) and,
// where nothing lies, marks the nearest food the land bears and gathers it; and it sleeps on dry
// ground where it is, at night for choice. Work waits meanwhile.
//
// A dwarf with nothing to drink or to eat for too long dies of it, after the log and the screen
// have said so at each stage. Its body lies where it fell. Nothing here counts on seven.
//
// All of it is the hold's own (docs/adr/0009): the hour is read from the tick (date_tick), the
// water from the generator through the floors, what bears from the rows of FOODS.

Want :: enum u8 { Drink, Food, Sleep, Warm }
Want_Row :: struct {
	name:   string,      // what a dwarf with it wanting has: "thirst"
	of:     string,      // what it dies of
	falls:  f32,         // of the whole, in a day awake
	asleep: f32,         // the share of that it falls by asleep
	seeks:  f32,         // under this a dwarf with nothing in hand sees to it
	urgent: f32,         // under this it leaves its work for it
	kills:  f32,         // days with nothing before it dies of it; 0 for never
	takes:  f32,         // seconds the act takes: a drink, one thing eaten
	slows:  f32,         // the share of its hands' speed a dwarf loses while the need is urgent, before it harms
	how:    [5]string,   // how a dwarf is: met, wanting, urgent, with nothing, and near its death
	ends:   string,      // what is said of one with nothing left, with how long it has
}
// Read against the real games (colony-sim-reference.md, section 14). RimWorld's food falls 1.6 of
// its whole in a day and a pawn eats under 0.3 of it, about twice a day, in 500 ticks, eight
// seconds; with nothing it starves to death in 2.2 days (Need_Food, Malnutrition 0.453 a day). Its
// rest falls from full to tired, 0.28, in 18 hours, and a night of ten and a half hours mends it
// (Need_Rest); a pawn sleeps under 0.3 at any hour and from 22 to 6 by its timetable. It has no
// thirst. Dwarf Fortress's thirst runs twice as fast as its hunger (thirsty at 25,000 ticks and
// dehydrated at 50,000, hungry at 50,000 and starving at 75,000, of 1,200 a day; the 50,000 and
// 75,000 are in DFHack's notify, the rest from memory), so a dwarf there drinks about twice for each
// meal. Here a dwarf drinks about three times a day and eats twice; a meal is two or three things,
// ten seconds each. It dies of thirst a day and a half after it ran dry and of hunger three days
// after: longer than RimWorld's, since here the remedy may be a walk and an order away.
//
// A need that is urgent slows the hands before it harms (slows): a fifth for thirst, hunger and cold,
// and they add, to a half at most. RimWorld's hungry pawn works as fast as a fed one and only its
// mood falls; once it starves, malnutrition takes 5% of its consciousness, then 10, 20 and 30
// (Hediffs_Global_Needs.xml), and its hypothermia takes 20% of its hands at the stage called minor
// and 50% at serious (Hediffs_Global_Temperature.xml). A tired dwarf is not slowed: it sleeps.
WANTS := [Want]Want_Row{
	.Drink = {"thirst", "thirst", 2.0, 0.5, 0.45, 0.2, 1.5, 6, 0.2, {"not thirsty", "thirsty", "very thirsty", "parched", "dying of thirst"}, "it has had nothing to drink, and will die of thirst in %s unless it does"},
	.Food  = {"hunger", "hunger", 1.2, 0.6, 0.5, 0.2, 3.0, 10, 0.2, {"fed", "hungry", "very hungry", "starving", "dying of hunger"}, "it has had nothing to eat, and will die of hunger in %s unless it does"},
	.Sleep = {"tiredness", "", 1.05, 0, 0.3, 0.1, 0, 0, 0, {"rested", "tired", "worn out", "asleep on its feet", ""}, ""},
	// Cold (shelter.odin): it falls by what a dwarf feels, so much of the whole in a day ten degrees under
	// what is comfortable, and comes back where it is warm; with none left, in cold that harms, a dwarf
	// dies in a day and a half. RimWorld's hypothermia kills in a day and a third at most.
	.Warm  = {"cold", "cold", 2.5, 1, 0.5, 0.2, 1.5, 0, 0.2, {"warm", "chilled", "cold", "numb with cold", "dying of cold"}, "it has been out in the cold and the wet too long, and will die of cold in %s of such cold unless it is warmed"},
}
SLEEP_MENDS :: 2.1    // of the whole, in a day asleep: eight hours make good sixteen awake
SLEEPS_AT   :: 0.75   // at night a dwarf lies down under this (RimWorld's DefaultFallAsleepMaxLevel)
FULL        :: 0.9    // a dwarf eating stops over this
PROVISIONS  :: 4      // days of food the party brings in the boat, for each of them. RimWorld's three colonists land with 30 survival meals, five days; a Dwarf Fortress embark's default stores last the seven a season. Four days is the time to find where food grows and set a stockpile, and no more; what a party chooses to bring is expedition planning's, with P5
RETRY       :: 300    // ticks before a dwarf looks again for what it found no way to
KEPT_FAR    :: 120    // steps farther off that food which keeps counts as lying, to a dwarf choosing what to eat: so what will spoil is eaten first, and the store is kept for a lean season
FORAGES     :: 12     // things, at most, a hungry dwarf marks to gather for itself at a time
FORAGE_CELLS :: 24    // cells of the land, the nearest that bear something first, that it looks over for them; five times as many where those were all taken already
WELLS       :: 6      // waters round a dwarf, the nearest first, that are tried for a place to drink it has a way to

// What a hold keeps of the day in hand, for its word at the next dawn.
Day_Tally :: struct { drank: int, ate: [Food_Kind]int }

// How a level of a need stands, by its row: 0 met, 1 wanting, 2 urgent, 3 with nothing.
want_stage :: proc(w: Want, level: f32) -> int {
	row := WANTS[w]
	return 3 if level <= 0 else 2 if level < row.urgent else 1 if level < row.seeks else 0
}

// The share of its hands' speed a dwarf loses to the needs that are urgent, by their rows: none to a half.
SLOWEST :: 0.5
slowed :: proc(want: [Want]f32) -> (by: f32) {
	for row, w in WANTS do if want[w] < row.urgent do by += row.slows
	return min(by, SLOWEST)
}

// How much slower a dwarf's hands are and for what, in words, or "" where no need is urgent: "a fifth slower: it is very hungry".
slow_words :: proc(want: [Want]f32) -> string {
	by := slowed(want)
	if by <= 0 do return ""
	b := strings.builder_make(context.temp_allocator)
	said, n := 0, 0
	for row, w in WANTS do n += int(want[w] < row.urgent && row.slows > 0)
	for row, w in WANTS do if want[w] < row.urgent && row.slows > 0 {
		fmt.sbprintf(&b, "%s%s", "" if said == 0 else " and " if said == n - 1 else ", ", row.how[2] if want[w] > 0 else row.how[3])
		said += 1
	}
	return fmt.tprintf("%s slower: it is %s", "a fifth" if by < 0.3 else "two fifths" if by < 0.5 else "half", strings.to_string(b))
}

// The dwarves as the boat brings them: watered, fed and rested, each a little differently, and each
// with a pace of its own at every need, drawn from who it is.
needs_init :: proc(h: ^Hold) {
	for &d, i in h.dwarves {
		key := fnv.fnv32a(transmute([]u8)h.party[i].given)*31 + fnv.fnv32a(transmute([]u8)h.party[i].byname)
		for w in Want {
			d.pace[w] = 0.85 + 0.3*hash01(i32(key & 0xFFFF), i32(w), world_seed + 920)
			start := [Want][2]f32{.Drink = {0.85, 1}, .Food = {0.9, 1}, .Sleep = {0.85, 1}, .Warm = {0.95, 1}}
			d.want[w] = math.lerp(start[w][0], start[w][1], hash01(i32(key & 0xFFFF), i32(w), world_seed + 921))
		}
	}
}

who :: proc(h: ^Hold, i: int) -> string { return fmt.tprintf("%s %s", h.party[i].given, h.party[i].byname) }

// How many of the hold are alive.
living :: proc(h: ^Hold) -> (n: int) {
	for d in h.dwarves do n += int(d.doing != .Dead)
	return
}

// A tick of a dwarf's needs: each falls, or sleep mends; a need with nothing left is said, and
// kills in its time; and a need that will not wait takes the dwarf from its work.
needs_tick :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	asleep := d.doing == .Sleeping
	for &row, w in WANTS {
		if w == .Sleep && asleep {
			d.want[w] = min(d.want[w] + SLEEP_MENDS*TICK/DAY, 1)
			continue
		}
		harmed := false
		if w == .Warm do harmed = warm_tick(h, i)   // by what it feels of the weather where it stands (shelter.odin)
		else {
			d.want[w] = max(d.want[w] - row.falls*d.pace[w]*(row.asleep if asleep else 1)*TICK/DAY, 0)
			harmed = d.want[w] <= 0
		}
		if row.kills == 0 do continue
		if harmed do d.spent[w] += TICK/DAY
		else if d.want[w] > 0 do d.spent[w] = max(d.spent[w] - TICK/DAY, 0)   // made good as slowly as it was lost, as RimWorld's malnutrition is: a dwarf that goes without half its days does not mend
		if d.spent[w] >= row.kills {
			die(h, i, w)
			return
		}
		stage := u8(4 if d.spent[w] >= row.kills/2 else want_stage(w, d.want[w]))
		if stage > d.told[w] && stage >= 3 {
			h.at = feet_of(h, i)
			left := row.kills - d.spent[w]
			if stage == 3 {
				h.short = fmt.tprintf("%s is %s.", who(h, i), row.how[3])
				say(h, "%s is %s: %s.", who(h, i), row.how[3], fmt.tprintf(row.ends, days_words(left)))
			} else {
				h.short = fmt.tprintf("%s is %s.", who(h, i), row.how[4])
				say(h, "%s is %s: %s is left to it.", who(h, i), row.how[4], days_words(left))
			}
		}
		if stage > d.told[w] || stage == 0 do d.told[w] = stage   // said again only after the need was met in between: a mouthful does not make it news twice
	}
	if d.caring || !(d.job || d.haul.on) do return
	feeding := false   // the work in hand is to gather or to fish: it is not left for hunger, which it is the remedy of
	if k, ok := h.marked[d.job_at]; ok && d.job do feeding = h.marks[k].work == .Gather || h.marks[k].work == .Fish
	warming := fire_work(h, i)   // nor is a fire's laying or feeding left for the cold
	for &row, w in WANTS do if d.want[w] < row.urgent && h.tick >= d.retry[w] && !(w == .Food && feeding) && !(w == .Warm && warming) {   // it will not wait: the work is let go, and the dwarf looks to itself when it next stands
		job_drop(h, i, 0)
		haul_drop(h, i)
		return
	}
}

// A length of days in words, as a dwarf's end is told: "a day and a half", "about three days".
days_words :: proc(days: f32) -> string {
	return "a few hours" if days < 0.3 else "half a day" if days < 0.6 else "under a day" if days < 0.9 else "a day" if days < 1.25 else "a day and a half" if days < 1.75 else fmt.tprintf("about %s days", count_words(int(math.round(days))))
}

// A dwarf dies of a need. Its body lies where it fell; what it had in hand is let go.
die :: proc(h: ^Hold, i: int, w: Want) {
	d := &h.dwarves[i]
	care_drop(h, i)
	job_drop(h, i, 0)
	haul_drop(h, i)
	clear(&d.path)
	if o, ok := h.held[d.cell]; ok && o == i do delete_key(&h.held, d.cell)
	at := feet_of(h, i)
	d.doing, d.takes, d.into, d.fall, d.pass, d.errand = .Dead, 0, 0, false, false, false
	d.died, d.died_on = w, h.tick
	h.at = at
	left := living(h)
	h.short = fmt.tprintf("%s has died of %s.", who(h, i), WANTS[w].of)
	say(h, "%s, has died of %s at %s, on the %s. %s", dwarf_name(h.party[i]), WANTS[w].of, place_say(h, d.cell), date_words(date_tick(h.tick)),
		"No one of the hold is left alive." if left == 0 else fmt.tprintf("The hold is %s.", count_words(left)))
	errand_sum(h)
}

// ---- seeing to itself -----------------------------------------------------------------------------

// A dwarf with nothing in hand looks to its needs: what will not wait first, then what it would see
// to, thirst before hunger before sleep. True if it has set about one, or must wait its turn to look.
care_look :: proc(h: ^Hold, i: int) -> bool {
	d := &h.dwarves[i]
	hour := date_tick(h.tick).hour
	for pass in 0..<2 do for w in ([4]Want{.Drink, .Food, .Warm, .Sleep}) {   // a cold dwarf warms itself before it lies down
		row := &WANTS[w]
		under := row.urgent if pass == 0 else row.seeks
		if w == .Sleep && pass == 1 && night(hour) do under = SLEEPS_AT
		if d.want[w] >= under || h.tick < d.retry[w] do continue
		if h.looked >= LOOKS do return true
		h.looked += 1
		if care_begin(h, i, w) do return true
		d.retry[w] = h.tick + (4*RETRY if w == .Warm else RETRY if w not_in d.forages else 30)
	}
	return false
}

// Whether a need calls a dwarf from taking the next work at once (work_tick).
care_calls :: proc(h: ^Hold, i: int) -> bool {
	d := &h.dwarves[i]
	hour := date_tick(h.tick).hour
	for &row, w in WANTS {
		under := SLEEPS_AT if w == .Sleep && night(hour) else row.seeks
		if d.want[w] < under && h.tick >= d.retry[w] do return true
	}
	return false
}

// A dwarf sets out for what a need wants, or begins where it stands. False if it found none.
care_begin :: proc(h: ^Hold, i: int, w: Want) -> bool {
	d, walk := &h.dwarves[i], &h.walk
	walk.budget = ASKING
	to: [3]i32
	d.forages -= {w}
	switch w {
	case .Drink:
		spot, ok := drink_find(h, i)
		if !ok {
			if .Drink not_in d.lacks {
				d.lacks += {.Drink}
				h.at = feet_of(h, i)
				h.short = fmt.tprintf("%s finds no way to fresh water.", who(h, i))
				say(h, "%s is thirsty, and finds no way to fresh water from %s.", who(h, i), place_say(h, d.cell))
			}
			return false
		}
		to = spot
	case .Food:
		pile, stand, lies, ok := food_find(h, i)
		if !ok {
			if !lies && !d.shut && forage(h, i) {   // food that lies where it has no way to, or a dwarf shut in, is not mended by marking more
				d.forages += {.Food}
				return false   // it takes the marks it made as any work, and eats when something lies
			}
			if .Food not_in d.lacks {
				d.lacks += {.Food}
				h.at = feet_of(h, i)
				h.short = fmt.tprintf("%s finds nothing to eat.", who(h, i))
				if lies || d.shut do say(h, "%s is hungry, and has no way to food from %s.", who(h, i), place_say(h, d.cell))
				else do say(h, "%s is hungry, and finds nothing to eat: no food lies in the hold or about it, and nothing within reach of %s bears any now.", who(h, i), place_say(h, d.cell))
			}
			return false
		}
		if k, lies := h.lying[pile]; lies do h.goods[k].held += 1
		d.eats, d.care_at = true, pile
		to = stand
	case .Sleep:
		if walk_floor(walk, d.cell.x, d.cell.y, d.cell.z) < 0 do return false
		to = sleep_find(h, i)   // a sleeping place, a roof, a fire; or where it is (shelter.odin)
	case .Warm:
		spot, ok := warm_find(h, i)
		if !ok {
			if .Warm not_in d.lacks {
				d.lacks += {.Warm}
				h.at = feet_of(h, i)
				today := date_tick(h.tick).day
				h.aside = h.chilled && h.chilled_on == today   // on the screen once a day: after that the log has it, and the alert counts them (NEEDS, crowd.odin)
				h.chilled, h.chilled_on = true, today
				h.short = fmt.tprintf("%s is cold: no fire and no roof.", who(h, i))
				say(h, "%s is cold, and finds no fire burning and no roof within reach of %s.", who(h, i), place_say(h, d.cell))
			}
			return false
		}
		to = spot
	}
	if w != .Food do d.care_at = to
	d.caring, d.care = true, w
	if to == d.cell {
		clear(&d.path)
		care_arrive(h, i)
		return true
	}
	clear(&walk.shun)
	for o, j in h.dwarves do if j != i && o.doing != .Aboard && o.doing != .Walking && o.doing != .Dead do append(&walk.shun, o.cell)
	for f in h.fires do append(&walk.shun, f.at)   // and round a fire, where there is room
	for b in h.benches do append(&walk.shun, b.at)
	_, why, _, _ := way_timed(h, d.cell, to, &d.path)
	clear(&walk.shun)
	if why != .Way {
		care_drop(h, i)
		return false
	}
	h.claims[to] = i
	h.spots[i] = to
	d.doing, d.seek, d.next, d.wait, d.said, d.errand = .Walking, false, 1, 0, "", false
	return true
}

// A dwarf has come to where it sees to itself: it begins.
care_arrive :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if o, ok := h.claims[h.spots[i]]; ok && o == i do delete_key(&h.claims, h.spots[i])
	switch d.care {
	case .Drink:
		f := walk_floor(&h.walk, d.cell.x, d.cell.y, d.cell.z)
		if f < 0 || !drinkable(h, f) {   // it ended beside the place, another standing in it: it tries again in a moment
			care_drop(h, i)
			d.retry[.Drink] = h.tick + 20
			return
		}
		d.doing, d.work = .Drinking, i32(WANTS[.Drink].takes*1000)
	case .Food:
		k, lies := h.lying[d.care_at]
		if !lies || !is(h.goods[k].kind, FOOD) || max(abs(d.care_at.x - d.cell.x), abs(d.care_at.z - d.cell.z)) > 2 {
			care_drop(h, i)
			d.retry[.Food] = h.tick + 20
			return
		}
		d.doing, d.work, d.cut = .Eating, i32(WANTS[.Food].takes*1000), h.goods[k].kind
		if dx, dz := f64(d.care_at.x - d.cell.x), f64(d.care_at.z - d.cell.z); dx != 0 || dz != 0 do d.facing = f32(math.atan2(dx, -dz))
	case .Sleep:
		d.doing = .Sleeping
		d.slept = slept_as(h, d.cell)
	case .Warm:
		d.doing = .Warming
		d.lacks -= {.Warm}
	}
}

// A tick of a dwarf drinking, eating or asleep.
care_tick :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	switch d.care {
	case .Drink:
		d.work -= TICK_MS
		if d.work > 0 do return
		d.want[.Drink] = 1
		d.lacks -= {.Drink}
		h.tally.drank += 1
		care_drop(h, i)
	case .Food:
		d.work -= TICK_MS
		if d.work > 0 do return
		k, lies := h.lying[d.care_at]
		if !lies || !is(h.goods[k].kind, FOOD) {
			care_drop(h, i)
			return
		}
		kind := h.goods[k].kind
		food := food_of(kind)
		h.goods[k].held = max(h.goods[k].held - 1, 0)
		d.eats = false
		good_take(h, k, 1)
		d.want[.Food] = min(d.want[.Food] + FOODS[food].feeds, 1)
		d.lacks -= {.Food}
		h.tally.ate[food] += 1
		if k2, still := h.lying[d.care_at]; still && d.want[.Food] < FULL && h.goods[k2].n - h.goods[k2].held > 0 {   // and another, while it is hungry and the heap lasts
			h.goods[k2].held += 1
			d.eats, d.work = true, i32(WANTS[.Food].takes*1000)
			return
		}
		care_drop(h, i)
		if d.want[.Food] < WANTS[.Food].seeks do d.retry[.Food] = h.tick   // still hungry: it looks for the next heap at once
	case .Sleep:
		woken := d.want[.Sleep] >= 1
		for w in ([3]Want{.Drink, .Food, .Warm}) do woken ||= d.want[w] < WANTS[w].urgent && h.tick >= d.retry[w]   // thirst, hunger or cold that will not wait wakes it, where there is a remedy to look for
		if woken do care_drop(h, i)
	case .Warm:   // until it is warm, or the place is warm no longer, or thirst or hunger will not wait
		done := d.want[.Warm] >= FULL
		if d.felt < COMFORT {
			done = true
			d.retry[.Warm] = h.tick + 20
		}
		for w in ([2]Want{.Drink, .Food}) do done ||= d.want[w] < WANTS[w].urgent && h.tick >= d.retry[w]
		if done do care_drop(h, i)
	}
}

// A dwarf leaves off seeing to itself: done, called away or woken.
care_drop :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if !d.caring do return
	if d.eats do if k, lies := h.lying[d.care_at]; lies do h.goods[k].held = max(h.goods[k].held - 1, 0)
	if o, ok := h.claims[h.spots[i]]; ok && o == i do delete_key(&h.claims, h.spots[i])
	d.caring, d.eats, d.rest = false, false, 0
	if d.doing == .Drinking || d.doing == .Eating || d.doing == .Sleeping || d.doing == .Warming || d.doing == .Walking && d.takes == 0 {
		clear(&d.path)
		d.doing = .Waiting
	} else if d.doing == .Walking {   // in a step: it stands at the step's end
		d.next = len(d.path)
		d.seek = false
	}
}

// ---- water to drink -------------------------------------------------------------------------------

// Whether a dwarf standing on a floor can drink there: it stands in water of the land that is fresh,
// a stream that runs all year, a lake or a pond, and stands over the sea's own level.
drinkable :: proc(h: ^Hold, f: i32) -> bool {
	w := &h.walk
	at := w.floors[f]
	if at.wet == 0 do return false
	b := floor_block(w, f)
	if f32(b.y) + f32(at.wet)/10 <= SEA_SURFACE + 0.3 do return false   // the sea, or a mouth the tide salts
	c, n := land_cell(f64(b.x - region.origin.x) + 0.5, f64(b.z - region.origin.y) + 0.5), land.n
	for dy in -1..=1 do for dx in -1..=1 do if k := c + dy*n + dx; k >= 0 && k < n*n && fresh(k) do return true   // the channel wanders a cell's width
	return false
}

// A place for a dwarf to drink, with a way to it: the nearest the hold knows of, or one found in the
// fresh cells of the land nearest it, which the hold then knows.
drink_find :: proc(h: ^Hold, i: int) -> (spot: [3]i32, ok: bool) {
	d, w := &h.dwarves[i], &h.walk
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + 2*abs(a.y - b.y) }
	try :: proc(h: ^Hold, i: int, well: [3]i32) -> (spot: [3]i32, ok: bool) {
		d, w := &h.dwarves[i], &h.walk
		w.budget = ASKING
		f := walk_floor(w, well.x, well.y, well.z)
		if f < 0 || !drinkable(h, f) do return
		// The nearest drinkable floor to the well that no other dwarf holds or is bound for.
		w.stamp += 1
		queue := make([dynamic]i32, context.temp_allocator)
		append(&queue, f)
		w.seen[f] = w.stamp
		for k := 0; k < len(queue) && k < 200; k += 1 {
			c := floor_block(w, queue[k])
			o, held := h.held[c]
			p, claimed := h.claims[c]
			if drinkable(h, queue[k]) && (!held || o == i) && (!claimed || p == i) {
				if c == d.cell do return c, true
				way := make([dynamic][3]i32, context.temp_allocator)
				if _, why, _, _ := way_timed(h, d.cell, c, &way); why == .Way do return c, true
				return   // no way to this water: its other floors are no nearer
			}
			for way in 0..<8 do if t := floor_step(w, queue[k], way); t >= 0 && w.seen[t] != w.stamp {
				w.seen[t] = w.stamp
				append(&queue, t)
			}
		}
		return
	}
	// The wells known, the nearest first.
	order := make([dynamic]int, context.temp_allocator)
	for _, k in h.wells do append(&order, k)
	for a in 1..<len(order) do for k := a; k > 0 && far(h.wells[order[k]], d.cell) < far(h.wells[order[k - 1]], d.cell); k -= 1 do order[k], order[k - 1] = order[k - 1], order[k]
	for k in order[:min(len(order), 3)] do if far(h.wells[k], d.cell) < 2*640 {   // as far as fresh water is looked for at all (fresh_water, landing.odin)
		if spot, ok = try(h, i, h.wells[k]); ok do return
	}
	// Fresh cells of the land round it, the nearest first: in each, the wet floor nearest the dwarf.
	x, z := f64(d.cell.x - region.origin.x) + 0.5, f64(d.cell.z - region.origin.y) + 0.5
	c, n := land_cell(x, z), land.n
	Near :: struct { d2, c: int }
	cells := make([dynamic]Near, context.temp_allocator)
	for dy in -40..=40 do for dx in -40..=40 {
		cx, cy := c%n + dx, c/n + dy
		if cx < 0 || cy < 0 || cx >= n || cy >= n || !fresh(cy*n + cx) do continue
		at := len(cells)
		append(&cells, Near{dx*dx + dy*dy, cy*n + cx})
		for at > 0 && (cells[at - 1].d2 > cells[at].d2 || cells[at - 1].d2 == cells[at].d2 && cells[at - 1].c > cells[at].c) {
			cells[at], cells[at - 1] = cells[at - 1], cells[at]
			at -= 1
		}
	}
	tried := 0
	no_way := make([dynamic][2]f64, context.temp_allocator)   // waters no way was found to: their other cells are not tried
	next: for cell in cells {
		if tried >= WELLS do break
		m := middle_of(land.grid, cell.c)
		for at in no_way do if abs(at.x - m.x) + abs(at.y - m.y) < 5*LAND_CELL do continue next
		x0, z0 := i32(math.floor(m.x)) + region.origin.x - LAND_CELL/2 - 2, i32(math.floor(m.y)) + region.origin.y - LAND_CELL/2 - 2
		best, least := [3]i32{}, max(i32)
		w.budget = ASKING
		for bz in z0..<z0 + LAND_CELL + 4 do for bx in x0..<x0 + LAND_CELL + 4 {
			p := patch_at(w, bx >> CHUNK_SHIFT, bz >> CHUNK_SHIFT)
			if p == nil do continue
			col := (bz & (CHUNK - 1))*CHUNK + bx & (CHUNK - 1)
			for k in p.first[col]..<p.first[col + 1] do if f := p.base + i32(k); drinkable(h, f) {
				if b := floor_block(w, f); far(b, d.cell) < least do best, least = b, far(b, d.cell)
			}
		}
		if least == max(i32) do continue   // its water is too deep to stand in, or runs under a roof
		tried += 1
		known := false
		for well in h.wells do known ||= far(well, best) < 12
		if known do continue   // tried already, as a well
		if spot, ok = try(h, i, best); ok {
			append(&h.wells, best)
			return
		}
		append(&no_way, m)
	}
	return
}

// ---- food to eat ----------------------------------------------------------------------------------

// Food for a dwarf to eat, with a way to it: the nearest heap of it that lies anywhere, stored or
// loose, and the floor to eat it from.
food_find :: proc(h: ^Hold, i: int) -> (pile, stand: [3]i32, lies, ok: bool) {
	d, w := &h.dwarves[i], &h.walk
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + 2*abs(a.y - b.y) }
	Near :: struct { far: i32, k: int }
	tries: [4]Near
	count := 0
	for g, k in h.goods do if is(g.kind, FOOD) && g.n - g.held > 0 {
		f := far(g.at, d.cell) + (KEPT_FAR if keeps_well(g.kind) else 0)   // what will spoil is eaten before what keeps, where both are within a short walk
		at := min(count, len(tries) - 1)
		if count == len(tries) && f >= tries[at].far do continue
		for at > 0 && tries[at - 1].far > f {
			tries[at] = tries[at - 1]
			at -= 1
		}
		tries[at] = {f, k}
		count = min(count + 1, len(tries))
	}
	lies = count > 0   // food lies somewhere: whether it has a way to any is what is asked next
	for t in tries[:count] {
		g := h.goods[t.k]
		w.budget = ASKING
		stand = g.at
		if o, held := h.held[stand]; walk_floor(w, stand.x, stand.y, stand.z) < 0 || held && o != i {
			f := walk_near(w, g.at.x, g.at.y, g.at.z, 2, false, &h.held)
			if f < 0 do continue
			stand = floor_block(w, f)
		}
		if stand != d.cell {
			way := make([dynamic][3]i32, context.temp_allocator)
			if _, why, _, _ := way_timed(h, d.cell, stand, &way); why != .Way do continue
		}
		return g.at, stand, true, true
	}
	return
}

// A hungry dwarf with no food lying anywhere looks for some: it marks the nearest plants, trees and
// fish that the land bears now, as much as fills it, for the hold to gather. They are marks like
// any, shown and taken as any; a hungry dwarf takes them before other work (work_look). True if
// such marks stand, new or from before.
forage :: proc(h: ^Hold, i: int) -> bool {
	d := &h.dwarves[i]
	for m in h.marks do if (m.work == .Gather || m.work == .Fish) && (m.taker < 0 || m.taker == i) && (m.wait == .None || m.by >= 0 && m.by != i) do return true
	if h.tick < h.foraged do return false
	h.foraged = h.tick + RETRY
	// What the hungry marked before and no dwarf found a way to is taken back: it is their own mark, and nothing for the player to mend.
	for k := len(h.marks) - 1; k >= 0; k -= 1 do if m := h.marks[k]; h.sites[m.site].thing == "foraging" && m.taker < 0 && m.wait != .None && (m.by < 0 || m.by == i) do mark_remove(h, k, false)
	date := date_tick(h.tick)
	found := make([dynamic]Bearing, context.temp_allocator)
	// The cells of the land within a short walk that bear something in season, the nearest first; each is
	// looked over block by block (bearing_of) until a meal for the hungry is found, FORAGE_CELLS at most.
	want := f32(0)
	for o in h.dwarves do if o.doing != .Dead && o.want[.Food] < WANTS[.Food].seeks do want += 1 - o.want[.Food]
	x, z := f64(d.cell.x - region.origin.x) + 0.5, f64(d.cell.z - region.origin.y) + 0.5
	c, n := land_cell(x, z), land.n
	Near :: struct { d2, c: int }
	cells := make([dynamic]Near, context.temp_allocator)
	r := FORAGE/LAND_CELL
	for dy in -r..=r do for dx in -r..=r {
		cx, cy := c%n + dx, c/n + dy
		if cx < 0 || cy < 0 || cx >= n || cy >= n || dx*dx + dy*dy > r*r || land.grid.sea[cy*n + cx] do continue
		bears := false
		for things, food in cell_bears(cy*n + cx) do bears ||= things >= 1 && in_season(&FOODS[food], date.sun)
		if !bears do continue
		at := len(cells)
		append(&cells, Near{dx*dx + dy*dy, cy*n + cx})
		for at > 0 && (cells[at - 1].d2 > cells[at].d2 || cells[at - 1].d2 == cells[at].d2 && cells[at - 1].c > cells[at].c) {
			cells[at], cells[at - 1] = cells[at - 1], cells[at]
			at -= 1
		}
	}
	feeds, looked := f32(0), 0
	for cell in cells {
		if feeds >= want && len(found) > 0 || looked >= FORAGE_CELLS && len(found) > 0 || looked >= 5*FORAGE_CELLS do break
		looked += 1
		m := middle_of(land.grid, cell.c)
		lo := [3]i32{i32(math.floor(m.x)) + region.origin.x - LAND_CELL/2, d.cell.y, i32(math.floor(m.y)) + region.origin.y - LAND_CELL/2}
		from := len(found)
		for work in ([2]Work{.Gather, .Fish}) do bearing_of(work, lo, lo + {LAND_CELL - 1, 0, LAND_CELL - 1}, date.sun, date.day, hold_blocks(h), &h.picked, &found)
		for k := len(found) - 1; k >= from; k -= 1 {
			if found[k].at in h.marked do unordered_remove(&found, k)
			else do feeds += f32(found[k].n)*FOODS[found[k].food].feeds
		}
	}
	if len(found) == 0 do return false
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + 2*abs(a.y - b.y) }
	less :: proc(a, b: Bearing, from: [3]i32) -> bool {
		fa, fb := far(a.at, from), far(b.at, from)
		return fa < fb || fa == fb && (a.at.x < b.at.x || a.at.x == b.at.x && a.at.z < b.at.z)
	}
	for a in 1..<len(found) do for k := a; k > 0 && less(found[k], found[k - 1], d.cell); k -= 1 do found[k], found[k - 1] = found[k - 1], found[k]
	// As much as a meal for those of the hold who are hungry, and no more than FORAGES marks.
	take := 0
	feeds = 0
	for f in found {
		if take >= FORAGES || feeds >= want do break
		feeds += f32(f.n)*FOODS[f.food].feeds
		take += 1
	}
	id := gather_site(h, .Gather, found[:take], d.cell, d.cell, "foraging")
	h.at = site_middle(&h.sites[id])
	h.aside = h.foraged_on == date.day && h.forages > 0   // on the screen once a day: after that the log has it, and the alert stands (alerts_keep, bar.odin)
	h.foraged_on = date.day
	h.forages += 1
	h.short = fmt.tprintf("%s forages: no food lies in the hold.", who(h, i))
	say(h, "%s is hungry and no food lies in the hold or about it: it marks %s to gather near where it stands, at %s.", who(h, i), bearing_words(found[:take], false), h.sites[id].place)
	return true
}

// ---- the day ----------------------------------------------------------------------------------------

// How many days the food that lies in the hold's stockpiles feeds those alive, how many of those days
// are of food that keeps (keeps_well), and how many things of food lie loose.
food_days :: proc(h: ^Hold) -> (days, kept: f32, loose: int) {
	for g in h.goods do if is(g.kind, FOOD) {
		if stored(h, g) {
			feeds := f32(g.n)*FOODS[food_of(g.kind)].feeds
			days += feeds
			if keeps_well(g.kind) do kept += feeds
		} else do loose += int(g.n)
	}
	eaten := f32(max(living(h), 1))*WANTS[.Food].falls
	return days/eaten, kept/eaten, loose
}

// ---- the lean season ---------------------------------------------------------------------------------

// The lean season a hold lays up for. A season is lean where the land within a walk of where the
// party gathered bears less in it than twice what those alive eat (larder_round, food.odin): a hold
// finds and brings in about half of what bears, and the rest of its days it must have in store.
// It is said a season ahead, when there is still time to gather, dry and store, and while it lasts.
// On the start island summer and winter are lean: gobies alone.
// Neither game says it: RimWorld's alert rises when the food in store is under four meals a
// colonist (Alert_LowFood), whatever the season, and its caravan says the days its food is worth
// and when it rots (DaysWorthOfFoodCalculator); Dwarf Fortress shows the count and no more.
LEAN_FOUND :: 0.5   // the share of what the land bears in a season that a hold finds and brings in
Lean_Season :: struct {
	on:     bool,
	season: int,                  // which of SEASONS it is
	off:    int,                  // days until it begins; none once it has
	days:   int,                  // days of it ahead, or left
	bears:  bit_set[Food_Kind],   // what the land within a walk bears in it
	kept:   f32,                  // days the kept food in the stockpiles feeds those alive,
	loose:  f32,                  // and days the kept food that lies loose would
}

lean_of :: proc(h: ^Hold) -> (l: Lean_Season) {
	alive := living(h)
	if alive == 0 do return
	m := h.landed.camp
	larder := larder_round(land_cell(f64(m.x - region.origin.x) + 0.5, f64(m.z - region.origin.y) + 0.5))
	date := date_tick(h.tick)
	lean :: proc(larder: ^Larder, s, alive: int) -> bool { return larder.days[s%4]*LEAN_FOUND < f32(alive)*SEASON_DAYS }
	left := SEASON_DAYS - date.nth + 1   // days of this season still to come, today among them
	first := date.season
	if lean(&larder, first, alive) do l.days = left
	else if lean(&larder, first + 1, alive) do first, l.off = first + 1, left
	else do return
	l.on, l.season, l.bears = true, first%4, larder.foods[first%4]
	if l.off > 0 do l.days = SEASON_DAYS
	for s := first + 1; s < first + 4 && lean(&larder, s, alive); s += 1 do l.days += SEASON_DAYS   // and the lean seasons that follow it without a break
	_, l.kept, _ = food_days(h)
	for g in h.goods do if is(g.kind, FOOD) && keeps_well(g.kind) && !stored(h, g) do l.loose += f32(g.n)*FOODS[food_of(g.kind)].feeds
	l.loose /= f32(alive)*WANTS[.Food].falls
	return
}

// How a lean season's store stands, in words: the kept food in the stockpiles against its days; and
// where none is stored, what lies loose, as the stores say it.
lean_store :: proc(l: Lean_Season, short := false) -> string {
	kept := min(int(l.kept + 0.25), l.days)
	if kept <= 0 && l.loose >= 0.75 do return fmt.tprintf("Kept food for %d of %s, lying loose", min(int(l.loose + 0.25), l.days), "them" if short else fmt.tprintf("its %d days", l.days))
	if short do return fmt.tprintf("Kept food for %d of them", kept)
	return "No kept food is in store" if kept <= 0 else fmt.tprintf("Kept food in store for %d of them", kept) if kept < l.days else "Kept food in store for all of them"
}

// Whether the kept food in store falls short of a lean season, by the whole days the screen says.
LEAN_WARNS :: 6   // days before a lean season from which its alert stands, while the kept food falls short of it
lean_short :: proc(l: Lean_Season) -> bool { return l.on && int(l.kept + 0.25) < l.days }

// What a lean season's land bears, in words: "nothing", "gobies alone", "too little: gobies and shii nuts".
lean_bears :: proc(l: Lean_Season) -> string {
	b := strings.builder_make(context.temp_allocator)
	said, kinds := 0, card(l.bears)
	if kinds == 0 do return "nothing"
	for food in Food_Kind do if food in l.bears {
		fmt.sbprintf(&b, "%s%s", "" if said == 0 else " and " if said == kinds - 1 else ", ", FOODS[food].name)
		said += 1
	}
	return fmt.tprintf("%s alone", strings.to_string(b)) if kinds == 1 else fmt.tprintf("too little: %s", strings.to_string(b))
}

// The lean season in one line, as the dawn's word and the alert say it: "Winter is 12 days off: the
// land bears gobies alone for its 12 days. Kept food in store for 4 of them."
lean_words :: proc(l: Lean_Season) -> string {
	if !l.on do return ""
	store := lean_store(l)
	if l.off > 0 do return fmt.tprintf("%s is %d %s off: the land here bears %s for its %d days. %s.", capital(SEASONS[l.season]), l.off, "day" if l.off == 1 else "days", lean_bears(l), l.days, store)
	return fmt.tprintf("%s has %d %s left: the land here bears %s. %s.", capital(SEASONS[l.season]), l.days, "day" if l.days == 1 else "days", lean_bears(l), store)
}

// At each dawn after the first the hold says the day, what the dwarves drank and ate the day before,
// and how long its food will last: one line a day, where a line for every drink would bury the log.
day_tick :: proc(h: ^Hold) {
	date := date_tick(h.tick)
	if date.day == h.today || date.hour < NIGHT[1] do return
	h.today = date.day
	alive := living(h)
	if alive == 0 do return
	b := strings.builder_make(context.temp_allocator)
	if date.nth == 1 do fmt.sbprintf(&b, "%s has come. ", capital(SEASONS[date.season]))
	fmt.sbprintf(&b, "The %s. Yesterday the %s drank %d times", date_words(date), count_words(alive), h.tally.drank)
	ate, kinds, said := 0, 0, 0
	for n in h.tally.ate {
		ate += n
		kinds += int(n > 0)
	}
	if ate == 0 do fmt.sbprint(&b, " and ate nothing.")
	else {
		fmt.sbprint(&b, " and ate ")
		for n, food in h.tally.ate do if n > 0 {
			fmt.sbprintf(&b, "%s%d of %s", "" if said == 0 else " and " if said == kinds - 1 else ", ", n, FOODS[food].name)
			said += 1
		}
		fmt.sbprint(&b, ".")
	}
	days, kept, loose := food_days(h)
	store := "no food" if days <= 0 else "food for under a day" if days < 0.75 else fmt.tprintf("food for %s", days_words(days))
	keeps := "" if days < 0.75 else ", none of it food that keeps" if kept < 0.25 else ", all of it food that keeps" if kept > days - 0.25 else fmt.tprintf(", kept food for %s", days_words(kept))
	fmt.sbprintf(&b, " The stockpiles hold %s%s%s.", store, keeps, fmt.tprintf("; %d more things of food lie loose", loose) if loose > 0 else "")
	if h.spoiled > 0 do fmt.sbprintf(&b, " %d things of food spoiled.", h.spoiled)
	h.spoiled = 0
	fmt.sbprint(&b, night_words(h, date.day - 1))   // the weather that was, and how the party slept (shelter.odin)
	lean := lean_of(h)
	h.short = fmt.tprintf("The %s: %s in store.", date_words(date), store)
	if lean_short(lean) && (date.nth == 1 || date.nth == 7 || date.nth == 10 || date.day == 1) {   // the lean season ahead, or in hand, while the store falls short of it: three times a season, and the alert stands between (crowd.odin)
		fmt.sbprintf(&b, " %s", lean_words(lean))
		h.short = fmt.tprintf("%s %s", h.short, fmt.tprintf("%s is %d %s off.", capital(SEASONS[lean.season]), lean.off, "day" if lean.off == 1 else "days") if lean.off > 0 else fmt.tprintf("%s has %d %s left.", capital(SEASONS[lean.season]), lean.days, "day" if lean.days == 1 else "days"))
	}
	say(h, "%s", strings.to_string(b))
	h.tally = {}
}

// The same for the alert at the top right, which is short and says what to do: "Winter in 12 days:
// the land bears gobies alone then. Kept food for 4 of its 12 days: gather, dry and store."
lean_alert :: proc(l: Lean_Season) -> string {
	kept := min(int(l.kept + 0.25), l.days)
	if kept <= 0 && l.loose >= 0.75 {
		if l.off > 0 do return fmt.tprintf("%s in %d %s: the land bears %s then. %s: gather, dry and store.", capital(SEASONS[l.season]), l.off, "day" if l.off == 1 else "days", lean_bears(l), lean_store(l))
		return fmt.tprintf("%s, %d %s left: the land bears %s. %s.", capital(SEASONS[l.season]), l.days, "day" if l.days == 1 else "days", lean_bears(l), lean_store(l, true))
	}
	if l.off > 0 do return fmt.tprintf("%s in %d %s: the land bears %s then. Kept food for %d of its %d days: gather, dry and store.", capital(SEASONS[l.season]), l.off, "day" if l.off == 1 else "days", lean_bears(l), kept, l.days)
	return fmt.tprintf("%s, %d %s left: the land bears %s. Kept food for %d of them.", capital(SEASONS[l.season]), l.days, "day" if l.days == 1 else "days", lean_bears(l), kept)
}

// What the land round the landing bears, said once when the party stands ashore: the plain word on
// whether a party can live there, by the rule a landing's card is read from (larder_round).
larder_tell :: proc(h: ^Hold) {
	m := h.landed.camp
	c := land_cell(f64(m.x - region.origin.x) + 0.5, f64(m.z - region.origin.y) + 0.5)
	l := larder_round(c)
	good := food_seasons(c)
	h.at = feet_on(h.landed.camp)
	// What it brought is carried up from the boat and lies where it gathers: sacks of provisions, PROVISIONS days of them for each.
	sacks := i32(math.ceil(f32(living(h))*PROVISIONS*WANTS[.Food].falls/FOODS[.Provisions].feeds))   // by the measure the stores count days of food in (food_days)
	if sacks > 0 do good_drop(h, h.landed.camp + {0, 1, 0}, .Provisions, sacks)
	brought := fmt.tprintf("The party brought provisions for %s, %d sacks, which lie where it gathered", days_words(PROVISIONS), sacks)
	if good == 0 {
		h.short = fmt.tprintf("Provisions for %s. No food a party could live on lies within a walk of here.", days_words(PROVISIONS))
		say(h, "%s, and no food a party could live on lies within a walk of the landing. %s When the sacks are empty, what it eats it must go far for.", brought, larder_words(l))
		return
	}
	h.short = fmt.tprintf("Provisions for %s. Food within a walk: %s.", days_words(PROVISIONS), larder_says(l))
	say(h, "%s: after them, what it eats it must gather or catch. Within a walk of the landing the land and its water bear food %s. %s", brought, larder_says(l), larder_words(l))
}
