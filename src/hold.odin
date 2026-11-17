package main

import "base:builtin"
import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// The dwarves' world (plan.md, P2; docs/adr/0009). It is a simulation of its own beside the frame:
// it advances in ticks of a tenth of a second from the world's seed and a list of orders, each
// order with the tick it is obeyed at, and the same seed and orders give the same events every
// time, with a window or without one. All it is lies in one record, `Hold`, that only the thread
// running it touches. The frame thread hands it orders through an inbox and reads a copy of where
// everyone stood at the last two ticks, which the hold lays out after each tick; nothing else
// passes between them. What happens is written as a log of plain sentences, each with its time,
// and the log's hash is what a test compares.
//
// The player is the will of the hold, not a hand on each dwarf: an order sends the party to a
// place and each dwarf finds its own way (paths.odin). One order exists in this step, "go", and
// one notice, "block", which tells the hold that a block was changed.
//
// A dwarf takes up the floor it stands still on (`held`): no other comes to rest there. A walker
// goes by whoever is on its way, as the walkers of RimWorld and Ingnomia do (docs/adr/0012), and
// plans its way round those who stand where there is room. One whose place at the end is taken
// ends on the nearest free floor (held_off, ends_elsewhere). A dwarf whose floor a changed block took away falls to the first ground below, or
// is pushed out of a block laid where it stood, and takes orders again where it lands (settle).
//
// An orders file has a line for each: the time, in seconds or as the log prints it, then
//   go x z          send the party to the ground at that column
//   go x y z        send it to stand on that block
//   block x y z M   the block there is now the material M (Air for dug out)
//   dig, fell, build, unmark   mark ground to dig, trees to fell and blocks to lay, or take marks back (orders.odin)
//   store            mark ground as a stockpile (goods.odin)
// and two that say what the expedition set out with (plan.md, E-1), read before anything is drawn
// or chosen, whatever time they give:
//   land x z         the boat is brought in at the low shore nearest that column of the world
//   party n [i ..]   the party is the seed's, drawn again n times, and after that its ith dwarves, from 1, each again
// A line of the log that begins `The hold says "..."` gives the order in this form, with its time
// before it, so the log of a played game can be played again.

TICK      :: 0.1     // seconds of the dwarves' world in a tick
TICK_MS   :: 100
LANDING   :: 7       // who come in the first boat. The hold grows: nothing below counts on seven
ROWING    :: 3.0     // metres a second the boat comes in
STEP_OUT  :: 6       // ticks between one dwarf stepping ashore and the next
IN_FILE   :: 3       // ticks between one dwarf setting out and the next, so a party walks in file and looks for its ways one at a time
ASKING    :: 64      // patches the hold may make to answer one order, before any way is looked for
AIM_REACH :: 160.0   // metres off a block can be aimed at in first person to send the party to it, or a dwarf asked
PATIENCE  :: 8       // ticks a walker waits behind one that stands in a file or waits its turn, before it goes round or squeezes past
SQUEEZE   :: 2.5     // how many times longer a step takes two dwarves who squeeze past each other
ASIDE     :: 0.22    // metres each keeps to its right as they do
ADRIFT    :: 6       // steps round a dwarf with no floor that ground is looked for

Doing :: enum u8 { Aboard, Ashore, Walking, Waiting, Stopped, Working, Drinking, Eating, Sleeping, Dead }   // the last four are needs.odin's
Dwarf :: struct {
	doing:       Doing,
	cell:        [3]i32,              // the floor it stands on, or is stepping onto
	from:        [3]f64,              // where its feet were when the step began
	into, takes: i32,                 // milliseconds into the step, and how many it takes; none when it stands
	path:        [dynamic][3]i32,     // the floors of its way
	next:        int,                 // the one it steps to next
	seek:        bool,                // it has yet to look for its way
	wait:        int,                 // ticks before it looks, or sets out
	stride:      f64,                 // metres walked since landing
	facing:      f32,                 // radians from north
	said:        string,              // why it stopped
	fall:        bool,                // the step it is in is a fall
	pass:        bool,                // or a squeeze past another, keeping to its right
	adrift:      bool,                // it has no floor, and none is near: it looks again when a block changes or an order comes
	stuck:       int,                 // ticks it has waited for the floor ahead
	errand:      bool,                // it walks for the hold's word to go somewhere, and says so when it is there
	// Its work (orders.odin).
	job:         bool,                // it has taken a mark
	job_at:      [3]i32,              // the block marked
	stand:       [3]i32,              // the floor it works from
	work:        i32,                 // milliseconds of the work left
	toil:        f64,                 // seconds it has worked, which swing its arms
	cut:         Mat,                 // what it works
	rest:        int,                 // ticks before it looks for work again
	gave:        bool,                // it has just left a mark for a dwarf whose trade the work is
	lack:        Waits,               // why it found no work when it last looked, where all that is marked waits for one thing
	// What it carries (goods.odin).
	haul:        Haul,                // the things it fetches or brings
	carry:       Mat,                 // what it has in its arms
	carrying:    i32,                 // and how many
	shut:        bool,                // it stands in a pit with no way out
	checked:     int,                 // the ground's changes when it last looked to itself
	// Its needs (needs.odin).
	want:        [Want]f32,           // how well each is met, from 1 down to nothing
	pace:        [Want]f32,           // its own pace at each
	spent:       [Want]f32,           // days it has gone with nothing
	told:        [Want]u8,            // the stage of each that was last said
	retry:       [Want]int,           // the tick before which it does not look again for what it found no way to
	lacks:       bit_set[Want],       // what it looked for and found none of
	forages:     bit_set[Want],       // what it has marked the land's own for, to gather
	caring:      bool,                // it is seeing to a need, or on its way to
	care:        Want,                // which
	care_at:     [3]i32,              // where: the floor it drinks or sleeps on, the heap it eats from
	eats:        bool,                // one thing of that heap is kept for it
	died:        Want,                // what it died of, and when
	died_on:     int,
}
Order_Kind :: enum u8 { Go, Block, Dig, Fell, Build, Unmark, Store, Gather, Fish }
Order :: struct {
	tick:   int,
	kind:   Order_Kind,
	at:     [3]i32,
	to:     [3]i32,   // a mark's box runs from `at`, where the drag began, to here
	shape:  Plan,
	stuff:  Stuff,
	takes:  Takes,  // store: what the stockpile takes
	column: bool,   // go: only the column was given, and its ground is meant
	mat:    Mat,
	frame:  bool,   // block: the frame changed it and told the hold; otherwise the frame is to be told (Hold.out)
}

// What the frame may know: who each dwarf is, where it stood at a tick and at the tick before, and what it was doing.
Seen :: struct {
	who:            Facts,
	was, at:        [3]f64,
	trod, stride:   f64,
	facing:         f32,
	doing:          Doing,
	left, of:       int,      // floors of its way still to walk, and in all
	said:           string,
	fall:           bool,
	job, working, shut: bool,   // it has work in hand; it is at it; it is shut in
	site:           int,        // the order its work is for, or -1
	cut:            Mat,        // what it is working
	toil:           f64,
	plight:         Plight,   // what is wrong with where it stands, for the screen to say who needs the player (plight_of)
	lack:           Waits,    // idle with work marked that it cannot take: why (orders.odin); None otherwise
	carry:          Mat,      // what it carries, and how many: none when it carries nothing (goods.odin)
	carrying:       i32,
	fetching:       bool,     // it walks to fetch something
	want:           [Want]f32,       // how well each need is met (needs.odin)
	spent:          [Want]f32,       // and the share of the days it lasts with nothing that are gone
	lacks:          bit_set[Want],   // what it looked for and found none of
	caring:         bool,            // it is seeing to a need, or on its way to
	care:           Want,
	died:           Want,            // of a dead dwarf: what it died of, and on which tick
	died_on:        int,
}
Shown :: struct {
	tick:      int,
	boat_was, boat: [2]f64,
	grounded:  bool,
	errand:    int,
	place:     string,
	dwarves:   [dynamic]Seen,
	// The orders (orders.odin).
	sites:     [dynamic]Site_Seen,
	tints:     [dynamic]Tint,
	ghosts:    [dynamic]Ghost,
	store:     [Mat]i32,      // what lies in stockpiles that take it: what the hold has (goods.odin)
	loose:     [Mat]i32,      // and what lies anywhere else, which is not counted
	piles:     [dynamic]Pile_Seen,
	zones:     [dynamic]Zone_Seen,
	zone_boxes: [dynamic]Tint,
	marks:     int,
	foraging:  bool,            // a hungry dwarf marked food for itself today or yesterday: the hold has none lying
	food_days: f32,             // days the food in the stockpiles feeds those alive
	taken:     [dynamic]Taken,  // the plants, trees and water gathered and fished, and on which day (food.odin)
	taken_v:   int,             // counts every change to them
}
Taken :: struct { col: [2]i32, day: int }

// What an expedition sets out with (plan.md, E-1): where its boat is brought in, and which draw of
// the seed's party it is. With nothing chosen the landing is the island's rows' and the party the
// seed's first, as the game began before there was anything to plan.
Expedition :: struct {
	lands: bool,            // a shore was chosen:
	shore: [2]i32,          // the column of the world the boat is brought in nearest
	draws: int,             // how often the whole party was drawn again
	again: [dynamic]int,    // and after the last of those, which of its dwarves were, one at a time, from 0, in order
}

Hold :: struct {
	island:   ^Formed,
	walk:     Walk,
	set:      Expedition,     // what it set out with
	landed:   Landed,
	found:    bool,           // the island has a landing
	boat_from, boat_to: [2]f64,
	boat_ticks: int,
	quiet:    bool,           // say nothing: a test
	// Its own, touched by the thread running it alone.
	tick:     int,
	party:    [dynamic]Facts, // who each dwarf is
	dwarves:  [dynamic]Dwarf,
	spots:    [dynamic][3]i32, // where each stands when the errand is done
	held:     map[[3]i32]int, // the floor each dwarf ashore takes up, and whose it is: the one it stands on, or is stepping onto
	// The orders (orders.odin).
	marks:    [dynamic]Mark,  // every block marked and not yet done
	marked:   map[[3]i32]int, // and which of them is each block's
	sites:    [dynamic]Site,  // every order to mark, in the order given
	store:    [Mat]i32,       // what lies in stockpiles that take it, by kind
	goods:    [dynamic]Good,  // every pile of things lying in the world (goods.odin)
	lying:    map[[3]i32]int, // and which of them lies in each cell
	zones:    [dynamic]Stockpile,  // the stockpiles
	zoned:    map[[3]i32]Zone_Cell,   // and the cells of ground that are theirs
	built:    map[[3]i32]Plan,        // the blocks the dwarves laid, and what each was laid as
	goods_v, goods_shown: int,        // counts every change to the goods, and the count shown
	claims:   map[[3]i32]int, // the floors dwarves are bound for to work from
	// Needs and food (needs.odin, food.odin).
	wells:    [dynamic][3]i32,   // places to drink that a dwarf has found a way to
	picked:   map[[2]i32]int,    // the columns gathered and fished, and the day each was
	picked_v, picked_shown: int, // counts every change to them, and the count shown
	tally:    Day_Tally,         // what the dwarves drank and ate today
	today:    int,               // the day last said
	foraged:  int,               // the tick before which no hungry dwarf looks over the land again
	foraged_on, forages: int,    // the day a hungry dwarf last marked food for itself, and how often one has
	ground:   int,            // changes to the blocks so far
	looked:   int,            // dwarves that have looked for work this tick
	cared:    bool,           // an idle dwarf has looked to itself this tick
	marks_v, shown_v: int,    // counts every change to the marks, and the count shown
	at:       Maybe([3]f64),  // where the next thing said happened
	aside:    bool,           // and it is for the log alone, not the screen's messages
	short:    string,         // or it is said on the screen in these few words, the log's sentence behind them
	errand:   int,            // orders to go obeyed so far; none while the party gathers above the landing
	place:    string,         // where the errand leads, in words
	summed:   bool,           // its end has been said
	orders:   [dynamic]Order, // by tick
	taken:    int,
	log:      [dynamic]string,
	showing:  [dynamic]Seen,  // the next tick's picture, as it is laid out
	work:     struct { ways, patches, round, squeezed, fell, looks, counts, done: int, walking, finding, worst_tick, worst_way, looking, counting: time.Duration },
	// Shared with the frame thread, under the mutex.
	mutex:    sync.Mutex,
	wake:     sync.Cond,
	inbox:    [dynamic]Order,
	out:      [dynamic]Edit,  // blocks the dwarves changed, or an orders file, for the frame to change in the world it draws
	out_laid: [dynamic]Laid_Block,  // and which of them were laid as a wall, a floor or a stair, or are such no longer
	shown:    Shown,
	target:   int,            // the tick the game's clock has reached (atomic)
	until:    int,            // the tick to stop at
	quit:     bool,
	runner:   ^thread.Thread,
}
hold: Hold   // the player's hold

// ---- making it ------------------------------------------------------------------------------

// Make the hold on an island: draw the party the boat brings, choose the landing and say both, and
// read the orders. `set` is what an expedition planned before play chose (plan.odin); an orders file
// may say the same in its own lines, and what the hold set out with it says again in its log.
hold_make :: proc(h: ^Hold, island: ^Formed, orders: string, count := LANDING, set: ^Expedition = nil) {
	started := time.now()
	bound(island)
	h.island = island
	walk_init(&h.walk, island)
	if set != nil {
		h.set = {lands = set.lands, shore = set.shore, draws = set.draws}
		append(&h.set.again, ..set.again[:])
	}
	orders_read(h, orders)
	party_draw(world_seed, count, &h.party, h.set.draws, h.set.again[:])
	builtin.resize(&h.dwarves, count)
	builtin.resize(&h.spots, count)
	needs_init(h)
	h.walk.budget = ASKING
	if h.set.lands do h.landed, h.found = landing_near(&h.walk, h.set.shore)
	if !h.found {
		if h.set.lands && !h.quiet do fmt.printfln("the hold: no boat can come in to the shore near %d, %d that the expedition chose, so the landing is the island's own", h.set.shore.x, h.set.shore.y)
		h.walk.budget = ASKING
		h.landed, h.found = landing_choose(&h.walk)
	}
	if !h.found {
		if !h.quiet do fmt.println("the hold: no boat can come in to any shore of this island, so no dwarves land")
		return
	}
	l := h.landed
	at := [2]f64{f64(l.at.x) + 0.5, f64(l.at.z) + 0.5}
	h.boat_to = at + l.out*3.9   // its bow on the shore
	h.boat_from = h.boat_to + l.out*f64(min(l.run - 6, 60))
	h.boat_ticks = int(math.hypot(h.boat_from.x - h.boat_to.x, h.boat_from.y - h.boat_to.y)/ROWING/TICK)
	spots_take(h, l.camp)
	h.place = "ground above the landing" if !l.shut else "the shore it landed on"
	for &d in h.dwarves do d.facing = f32(math.atan2(-l.out.x, l.out.y))
	hold_show(h)
	if h.quiet do return
	fmt.printfln("the hold: %s dwarves come by boat, their landing chosen in %.0f ms:", count_words(count), time.duration_milliseconds(time.since(started)))
	landing_words(l)
	m := middle_of(land.grid, l.cell)
	c := land_cell(m.x, m.y)
	fmt.printfln("  the boat comes in %.0f m from the %s and grounds at %d, %d, %d; the party gathers at %d, %d, %d, %.0f m from the boat and %.0f m from fresh water",
		math.hypot(h.boat_from.x - h.boat_to.x, h.boat_from.y - h.boat_to.y), compass(l.out.x, l.out.y), l.at.x, l.at.y, l.at.z, l.camp.x, l.camp.y, l.camp.z,
		math.hypot(f64(l.camp.x - l.at.x), f64(l.camp.z - l.at.z)), fresh_water(c))
	if l.shut do fmt.println("  no way leads from the shore to the ground to live on near it, so the party gathers where it lands")
	fmt.printf("  the %s%s:", count_words(count), party_words(h.set))
	for f, i in h.party do fmt.printf("%s %s", "" if i == 0 else ";", dwarf_name(f))
	fmt.println()
}

// Which draw of the seed's party an expedition's is, in words: nothing for the seed's first.
party_words :: proc(set: Expedition) -> string {
	if set.draws == 0 && len(set.again) == 0 do return ""
	whole := fmt.tprintf("the seed's party drawn again %s", "once" if set.draws == 1 else "twice" if set.draws == 2 else fmt.tprintf("%d times", set.draws)) if set.draws > 0 else "the seed's party"
	if len(set.again) == 0 do return fmt.tprintf(", %s", whole)
	return fmt.tprintf(", %s, and then %s of them one at a time", whole, count_words(len(set.again)))
}

// What the expedition set out with, as the lines of an orders file that say it: none where it chose nothing.
set_lines :: proc(set: Expedition, lines: ^[2]string) -> (n: int) {
	if set.lands {
		lines[n] = fmt.tprintf("land %d %d", set.shore.x, set.shore.y)
		n += 1
	}
	if set.draws > 0 || len(set.again) > 0 {
		b := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&b, "party %d", set.draws)
		for i in set.again do fmt.sbprintf(&b, " %d", i + 1)
		lines[n] = strings.to_string(b)
		n += 1
	}
	return
}

// A count in a word, while a word will do.
count_words :: proc(n: int) -> string {
	words := [?]string{"no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"}
	return words[n] if n >= 0 && n < len(words) else fmt.tprint(n)
}

// The party's standing places round a floor.
spots_take :: proc(h: ^Hold, at: [3]i32) {
	h.walk.budget = ASKING
	n := 0
	if f := walk_floor(&h.walk, at.x, at.y, at.z); f >= 0 do n = walk_spots(&h.walk, f, h.spots[:])
	for i in n..<len(h.spots) do h.spots[i] = at   // no ground joined to it for so many: each such ends where it finds a free floor (ends_elsewhere)
	if !h.quiet && h.walk.roomy < len(h.spots) do fmt.printfln("    (little room there: %d places to stand clear of each other, of water and of tall plants, so the rest stand in them or side by side)", h.walk.roomy)
}

orders_read :: proc(h: ^Hold, path: string) {
	if path == "" do return
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintln("cannot read the orders in", path)
		os.exit(2)
	}
	for line in strings.split_lines(string(data), context.temp_allocator) do if !order_read(h, line) {
		fmt.eprintfln("bad order in %s: %s", path, line)
		os.exit(2)
	}
}

// One line of an orders file, put among the hold's orders by its time; false if it is not an order.
order_read :: proc(h: ^Hold, line: string) -> bool {
	{
		words := strings.fields(strings.trim_space(line), context.temp_allocator)
		if len(words) == 0 || strings.has_prefix(words[0], "#") do return true
		o: Order
		when_, rest := strings.trim(words[0], "[]"), words[2:] if len(words) > 2 else nil
		seconds := 0.0
		for part in strings.split(when_, ":", context.temp_allocator) do seconds = seconds*60 + (strconv.parse_f64(part) or_else -1e9)
		if seconds >= 0 && len(words) >= 3 && (words[1] == "land" || words[1] == "party") {   // what the expedition set out with: no order, and read before the party is drawn
			n := make([dynamic]int, context.temp_allocator)
			for w in words[2:] {
				k, good := strconv.parse_int(w)
				if !good do return false
				append(&n, k)
			}
			if words[1] == "land" {
				if len(n) != 2 do return false
				h.set.lands, h.set.shore = true, {i32(n[0]), i32(n[1])}
			} else {
				if n[0] < 0 do return false
				h.set.draws = n[0]
				clear(&h.set.again)
				for i in n[1:] {
					if i < 1 do return false
					append(&h.set.again, i - 1)
				}
			}
			return true
		}
		v: [3]i32
		ok := seconds >= 0 && len(words) >= 4
		marking := len(words) > 1 && (words[1] == "dig" || words[1] == "fell" || words[1] == "build" || words[1] == "unmark" || words[1] == "store" || words[1] == "gather" || words[1] == "fish")
		if ok && marking {   // a mark: its kind, what it is to be, and the six figures of its box
			o.kind = .Dig if words[1] == "dig" else .Fell if words[1] == "fell" else .Build if words[1] == "build" else .Store if words[1] == "store" else .Gather if words[1] == "gather" else .Fish if words[1] == "fish" else .Unmark
			rest = words[2:]
			named := 1 if o.kind == .Dig || o.kind == .Store else 2 if o.kind == .Build else 0
			ok = len(rest) == named + 6
			if ok && o.kind == .Store {
				ok = false
				for name, takes in TAKES do if name == rest[0] do o.takes, ok = takes, true
			} else if ok && named > 0 {
				ok = false
				for name, shape in PLANS do if name == rest[0] && (o.kind == .Dig) == (shape <= .Up) do o.shape, ok = shape, true
			}
			if ok && named > 1 {
				ok = false
				for name, stuff in STUFFS do if name == rest[1] do o.stuff, ok = stuff, true
			}
			if ok do for i in 0..<6 {
				n, good := strconv.parse_int(rest[named + i])
				ok &&= good
				if i < 3 do o.at[i] = i32(n)
				else do o.to[i - 3] = i32(n)
			}
		}
		if ok && !marking do for i in 0..<min(len(rest), 3) {
			n, good := strconv.parse_int(rest[i])
			v[i], ok = i32(n), ok && good
		}
		if ok && !marking do switch words[1] {
		case "go":
			o.kind, o.at, o.column = .Go, v, len(rest) == 2
			if o.column do o.at = {v[0], 0, v[1]}
			ok = len(rest) == 2 || len(rest) == 3
		case "block":
			o.kind, o.at = .Block, v
			ok = false
			if len(rest) == 4 do for m in Mat do if fmt.tprint(m) == rest[3] do o.mat, ok = m, true
		case:
			ok = false
		}
		if !ok do return false
		o.tick = int(seconds/TICK + 0.5)
		at := len(h.orders)
		for at > 0 && h.orders[at - 1].tick > o.tick do at -= 1
		inject_at(&h.orders, at, o)
	}
	return true
}

// ---- running it -----------------------------------------------------------------------------

// A line of the log, with the time it happened.
say :: proc(h: ^Hold, format: string, args: ..any) {
	s := h.tick/10
	line := fmt.aprintf("[%d:%02d.%d] %s", s/60, s%60, h.tick%10, fmt.tprintf(format, ..args))
	append(&h.log, line)
	if !h.quiet do fmt.println(line)
	if !h.quiet && !h.aside {   // and to the screen's messages (play.odin), with where it happened and to whom
		at, who := about(h, line)
		if place, ok := h.at.?; ok do at = place   // where the orders say it happened (orders.odin)
		tell_log(line, at, who, h.short)
	}
	h.at, h.aside, h.short = nil, false, ""
}

feet_on :: proc(b: [3]i32) -> [3]f64 { return {f64(b.x) + 0.5, f64(b.y), f64(b.z) + 0.5} }

boat_at :: proc(h: ^Hold, tick: int) -> [2]f64 {
	return math.lerp(h.boat_from, h.boat_to, clamp(f64(tick)/f64(max(h.boat_ticks, 1)), 0, 1))
}

// Where a dwarf's feet are at the tick in hand.
feet_of :: proc(h: ^Hold, i: int) -> [3]f64 {
	d := &h.dwarves[i]
	if d.doing == .Aboard {
		b, out, seat := boat_at(h, h.tick), h.landed.out, SEATS[i%len(SEATS)]
		p := b - out*seat.y + [2]f64{out.y, -out.x}*seat.x
		return {p.x, SEA_SURFACE + 0.1, p.y}
	}
	if d.takes == 0 do return feet_on(d.cell)
	f, to := f64(d.into)/f64(d.takes), feet_on(d.cell)
	if d.fall do f *= f   // faster as it goes
	at := math.lerp(d.from, to, f)
	if d.pass do if way := linalg.normalize0([2]f64{to.x - d.from.x, to.z - d.from.z}); way != 0 do at.xz += [2]f64{-way.y, way.x}*ASIDE*math.sin(math.PI*f)
	return at
}

// A dwarf takes up a floor, and gives up the one it had.
take :: proc(h: ^Hold, i: int, cell: [3]i32) {
	d := &h.dwarves[i]
	if o, ok := h.held[d.cell]; ok && o == i do delete_key(&h.held, d.cell)
	d.cell = cell
	h.held[cell] = i
}

// Lay out what the frame may see of the tick in hand, and put it where the frame reads it.
hold_show :: proc(h: ^Hold) {
	builtin.resize(&h.showing, len(h.dwarves))
	for &d, i in h.dwarves {
		at := feet_of(h, i)
		was, trod := at, d.stride
		if h.tick > 0 && i < len(h.shown.dwarves) do was, trod = h.shown.dwarves[i].at, h.shown.dwarves[i].stride
		h.showing[i] = {who = h.party[i], was = was, at = at, trod = trod, stride = d.stride, facing = d.facing, doing = d.doing, left = len(d.path) - d.next, of = len(d.path), said = d.said, fall = d.fall,
			job = d.job, working = d.doing == .Working, shut = d.shut, site = -1, cut = d.cut, toil = d.toil,
			carry = d.carry, carrying = d.carrying, fetching = d.haul.on && !d.haul.bringing,
			want = d.want, lacks = d.lacks, caring = d.caring, care = d.care, died = d.died, died_on = d.died_on}
		for row, w in WANTS do if row.kills > 0 do h.showing[i].spent[w] = d.spent[w]/row.kills
		if k, ok := h.marked[d.job_at]; ok && d.job do h.showing[i].site = h.marks[k].site
		h.showing[i].plight = plight_of(h, i)
		if !d.job && !d.shut && (d.doing == .Waiting || d.doing == .Stopped) && len(h.marks) > 0 do h.showing[i].lack = d.lack
	}
	boat := boat_at(h, h.tick)
	sync.lock(&h.mutex)
	h.shown.boat_was, h.shown.boat = h.shown.boat if h.tick > 0 else boat, boat
	h.shown.tick, h.shown.errand, h.shown.place, h.shown.grounded = h.tick, h.errand, h.place, h.tick >= h.boat_ticks
	h.shown.foraging = h.forages > 0 && date_tick(h.tick).day - h.foraged_on <= 1
	if h.tick%16 == 0 || h.goods_shown != h.goods_v do h.shown.food_days, _ = food_days(h)
	if h.picked_shown != h.picked_v {
		h.picked_shown, h.shown.taken_v = h.picked_v, h.picked_v
		clear(&h.shown.taken)
		for col, day in h.picked do append(&h.shown.taken, Taken{col, day})
	}
	h.shown.dwarves, h.showing = h.showing, h.shown.dwarves
	orders_show(h)
	goods_show(h)
	sync.unlock(&h.mutex)
}

// A copy of what the hold shows, into a picture that keeps its own room.
shown_copy :: proc(to: ^Shown, from: Shown) {
	dwarves, sites, tints, ghosts := to.dwarves, to.sites, to.tints, to.ghosts
	piles, zones, zone_boxes := to.piles, to.zones, to.zone_boxes
	taken, taken_v := to.taken, to.taken_v
	to^ = from
	to.dwarves, to.sites, to.tints, to.ghosts = dwarves, sites, tints, ghosts
	to.piles, to.zones, to.zone_boxes = piles, zones, zone_boxes
	to.taken = taken
	if taken_v != from.taken_v || len(taken) != len(from.taken) {   // only when one was taken: the list is long
		builtin.resize(&to.taken, len(from.taken))
		copy(to.taken[:], from.taken[:])
	}
	builtin.resize(&to.piles, len(from.piles))
	copy(to.piles[:], from.piles[:])
	builtin.resize(&to.zones, len(from.zones))
	copy(to.zones[:], from.zones[:])
	builtin.resize(&to.zone_boxes, len(from.zone_boxes))
	copy(to.zone_boxes[:], from.zone_boxes[:])

	builtin.resize(&to.dwarves, len(from.dwarves))
	copy(to.dwarves[:], from.dwarves[:])
	builtin.resize(&to.sites, len(from.sites))
	copy(to.sites[:], from.sites[:])
	builtin.resize(&to.tints, len(from.tints))
	copy(to.tints[:], from.tints[:])
	builtin.resize(&to.ghosts, len(from.ghosts))
	copy(to.ghosts[:], from.ghosts[:])
}

// One tick: obey the orders due, bring the boat in, land the party and move every dwarf. A dwarf
// that stands costs a glance; one that walks, a step now and then; one that must look for its way
// looks when its turn in the file comes, so an order to a hundred is a hundred searches a moment apart.
hold_tick :: proc(h: ^Hold) {
	bound(h.island)
	started := time.now()
	found := h.work.finding
	for h.taken < len(h.orders) && h.orders[h.taken].tick <= h.tick {
		obey(h, h.orders[h.taken])
		h.taken += 1
	}
	if h.tick == 0 {   // what the expedition set out with, in the form an orders file takes, so that the log can be played again
		lines: [2]string
		for line in lines[:set_lines(h.set, &lines)] {
			h.aside = true
			if strings.has_prefix(line, "land") do say(h, `The hold says "%s": the boat is brought in at the shore the expedition chose%s.`, line, fmt.tprintf(", %.0f m from there, the nearest a boat can come in to", h.landed.off) if h.landed.off > 1.5*LAND_CELL else "" if h.landed.chosen else ", but no boat can come in near it, so the landing is the island's own")
			else do say(h, `The hold says "%s": the party is %s.`, line, party_words(h.set)[2:])
		}
	}
	if h.tick == 0 do say(h, "A boat with %s dwarves stands %.0f m off the shore, to the %s, and pulls for the landing.", count_words(len(h.dwarves)), math.hypot(h.boat_from.x - h.boat_to.x, h.boat_from.y - h.boat_to.y), compass(h.landed.out.x, h.landed.out.y))
	if h.tick == h.boat_ticks do say(h, "The boat grounds at %d, %d, on %s.", h.landed.at.x, h.landed.at.z, ground_words(h.landed.at)[4:])
	h.looked, h.cared = 0, false
	day_tick(h)
	for &d, i in h.dwarves {
		if d.doing == .Dead do continue
		if ashore(d) {   // its needs: thirst, hunger and sleep (needs.odin)
			needs_tick(h, i)
			if d.doing == .Dead do continue
		}
		if d.takes == 0 && stands(d) do if o, ok := h.held[d.cell]; !ok do h.held[d.cell] = i   // come to rest: the floor is its own,
		else if o != i {                                                                       // or another's, and it moves to the nearest that is free
			h.walk.budget = ASKING
			if f := walk_near(&h.walk, d.cell.x, d.cell.y, d.cell.z, 4, false, &h.held); f >= 0 && !d.job && !d.haul.on && !d.caring {
				h.spots[i] = floor_block(&h.walk, f)
				d.doing, d.seek, d.wait, d.errand = .Walking, true, 0, false
			}
		}
		if d.takes == 0 && d.doing == .Working do work_tick(h, i)
		else if d.takes == 0 && (d.doing == .Drinking || d.doing == .Eating || d.doing == .Sleeping) do care_tick(h, i)
		else if d.takes == 0 && (d.doing == .Waiting || d.doing == .Stopped) && !d.adrift do idle_tick(h, i)
		if d.doing == .Aboard && h.tick >= h.boat_ticks + 20 + STEP_OUT*i {   // over the bow, one at a time
			// Onto the landing once the one before has stepped off it; if that one stands there, onto the nearest free floor.
			to, free := h.landed.at, true
			if o, taken := h.held[to]; taken {
				free = false
				h.walk.budget = ASKING
				if h.dwarves[o].doing != .Walking do if f := walk_near(&h.walk, to.x, to.y, to.z, 3, false, &h.held); f >= 0 do to, free = floor_block(&h.walk, f), true
			}
			if free {
				d.from = feet_of(h, i)
				d.doing, d.takes, d.into = .Ashore, 600, 0
				take(h, i, to)
			}
		}
		if d.takes == 0 && d.doing == .Walking {
			if d.wait > 0 do d.wait -= 1
			else {
				if d.seek do find(h, i)
				if d.doing == .Walking && d.takes == 0 && !d.seek && step_on(h, i) == .Ended do arrive(h, i)
			}
		}
		if d.takes == 0 do continue
		d.into += TICK_MS
		for d.takes > 0 && d.into >= d.takes {
			d.into -= d.takes
			d.takes, d.pass = 0, false
			if d.fall {
				d.fall = false
				h.aside = d.from.y - f64(d.cell.y) < 3   // a drop of a block or two is the log's alone
				say(h, "%s %s falls %.0f m and lands on %s.", h.party[i].given, h.party[i].byname, max(d.from.y - f64(d.cell.y), 1), ground_words(d.cell)[4:])
			}
			if d.doing == .Ashore {
				h.at = feet_on(d.cell)
				h.short = fmt.tprintf("%s %s, %s, steps ashore.", h.party[i].given, h.party[i].byname, TRADES[h.party[i].trade].name)
				say(h, "%s, steps ashore.", dwarf_name(h.party[i]))
				d.doing, d.seek, d.wait, d.errand = .Walking, true, 0, true
			}
			if d.doing != .Walking || d.seek do d.into = 0   // it stands, or looks for its way next tick
			else do switch step_on(h, i) {
			case .Stepped:
			case .Held:  d.into = 0
			case .Ended: arrive(h, i)
			}
		}
	}
	h.tick += 1
	hold_show(h)
	spent := time.since(started)
	h.work.worst_tick = max(h.work.worst_tick, spent)
	h.work.walking += spent - (h.work.finding - found)
}

// Begin the next step of a dwarf's way. At its end the dwarf has arrived; where another holds the
// floor ahead it goes round, squeezes past or waits (held_off).
Stepped :: enum u8 { Stepped, Held, Ended }
step_on :: proc(h: ^Hold, i: int) -> Stepped {
	d := &h.dwarves[i]
	if d.next >= len(d.path) {
		d.into = 0
		return .Ended
	}
	to := d.path[d.next]
	last := d.next == len(d.path) - 1
	if o, taken := h.held[to]; taken && o != i && last do return held_off(h, i, o)   // only where it means to stand: on its way it goes by whoever is there
	step_to(h, i, to, 1, last)
	d.next += 1
	return .Stepped
}

// A dwarf sets off for a floor beside its own, taking `slow` times as long as the ground asks.
step_to :: proc(h: ^Hold, i: int, to: [3]i32, slow: f32, stand := true) {
	d := &h.dwarves[i]
	h.walk.budget = ASKING
	a, b := walk_floor(&h.walk, d.cell.x, d.cell.y, d.cell.z), walk_floor(&h.walk, to.x, to.y, to.z)
	d.from = feet_on(d.cell)
	d.takes = max(i32(slow*step_seconds(&h.walk, a, b)*1000), 1) if a >= 0 && b >= 0 else i32(750*slow)
	d.stride += math.hypot(f64(to.x - d.cell.x), f64(to.z - d.cell.z))
	d.facing = f32(math.atan2(f64(to.x - d.cell.x), -f64(to.z - d.cell.z)))
	d.into, d.stuck = 0, 0
	if stand do take(h, i, to)
	else {   // passing over it: it takes up no floor until it stands
		if o, ok := h.held[d.cell]; ok && o == i do delete_key(&h.held, d.cell)
		d.cell = to
	}
}

// The floor ahead of a walker is another dwarf's. One in a step will be off it or settled on it in
// a moment, and one walking its own way is followed, for a while. Otherwise the walker goes round
// by a free floor beside it from which its way goes on; and where there is none, or the other is
// coming the opposite way, the two change floors, each keeping to its right, and both take longer.
// Where the floor is the end of its way and the other is not coming through, it ends elsewhere. So
// whoever is blocked moves within PATIENCE ticks of the other standing still: no two wait on each
// other for ever.
held_off :: proc(h: ^Hold, i, o: int) -> Stepped {
	d, b, w := &h.dwarves[i], &h.dwarves[o], &h.walk
	d.into = 0
	d.stuck += 1
	if b.takes > 0 do return .Held
	meets := b.doing == .Walking && !b.seek && b.wait == 0 && b.next < len(b.path) && b.path[b.next] == d.cell
	if b.doing == .Walking && !meets && d.stuck <= PATIENCE do return .Held
	last := d.next == len(d.path) - 1
	if last && !meets do return ends_elsewhere(h, i)
	w.budget = ASKING
	mine := walk_floor(w, d.cell.x, d.cell.y, d.cell.z)
	if !last && mine >= 0 do for way in 0..<8 {
		side := floor_step(w, mine, way)
		if side < 0 || floor_block(w, side) in h.held do continue
		for on in 0..<8 do if t := floor_step(w, side, on); t >= 0 && floor_block(w, t) == d.path[d.next + 1] {
			d.path[d.next] = floor_block(w, side)
			step_to(h, i, d.path[d.next], 1)
			d.next += 1
			h.work.round += 1
			return .Stepped
		}
	}
	// They squeeze past: each takes the other's floor.
	x, y := d.cell, b.cell
	step_to(h, i, y, SQUEEZE)
	d.next += 1
	step_to(h, o, x, SQUEEZE)
	h.held[y] = i   // the second gave up the floor the first had just taken
	d.pass, b.pass = true, true
	if meets do b.next += 1
	else if b.doing == .Walking && !b.seek && b.next >= 1 && b.next <= len(b.path) && b.path[b.next - 1] == y do b.next -= 1   // set back a floor, its way begins with the floor it gave up
	else if b.doing == .Walking {
		clear(&b.path)
		b.seek = true
	}
	h.work.squeezed += 1
	return .Stepped
}

// The floor at the end of a dwarf's way is taken: it ends on the nearest floor joined to it that no
// dwarf holds and none is bound for, or where it stands if there is none.
ends_elsewhere :: proc(h: ^Hold, i: int) -> Stepped {
	d, w := &h.dwarves[i], &h.walk
	w.budget = ASKING
	goal := d.path[len(d.path) - 1]
	f := walk_floor(w, goal.x, goal.y, goal.z)
	if f < 0 do return .Ended
	w.stamp += 1
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, f)
	w.seen[f] = w.stamp
	for k := 0; k < len(queue) && k < 400; k += 1 {
		at := floor_block(w, queue[k])
		free := at == d.cell || at not_in h.held
		if o, claimed := h.claims[at]; claimed && o != i do free = false
		for spot, j in h.spots do free &&= j == i || spot != at
		if free {
			h.spots[i] = at
			clear(&d.path)
			if at == d.cell do return .Ended
			d.seek, d.stuck = true, 0
			return .Held
		}
		for way in 0..<8 do if t := floor_step(w, queue[k], way); t >= 0 && w.seen[t] != w.stamp {
			w.seen[t] = w.stamp
			append(&queue, t)
		}
	}
	return .Ended
}

// A dwarf's floor may be gone: a block was changed in its column. If the ground went from under it,
// it falls to the first ground below, faster as it goes, and lands; a fall of any height is only a
// fall until dwarves can be hurt (plan.md, P4). If a block was laid where it stands, or the ground
// below is deep water or another dwarf's, it is moved to the nearest floor no dwarf holds. With no
// floor within ADRIFT steps it stays as it is, adrift, says why, and is settled again whenever a
// block changes or an order comes. One on an errand looks for its way again from where it comes to rest.
settle :: proc(h: ^Hold, i: int, dropped: bool) {
	d, w := &h.dwarves[i], &h.walk
	w.budget = ASKING
	name := fmt.tprintf("%s %s", h.party[i].given, h.party[i].byname)
	if walk_floor(w, d.cell.x, d.cell.y, d.cell.z) >= 0 {
		if d.adrift {
			d.adrift = false
			if d.doing == .Stopped do d.doing, d.said = .Waiting, ""
			say(h, "%s has ground under it again.", name)
		}
		return
	}
	at := feet_of(h, i)
	care_drop(h, i)   // the ground went from under it: it is awake, and its meal waits
	to := i32(-1)
	if dropped do if p := patch_at(w, d.cell.x >> CHUNK_SHIFT, d.cell.z >> CHUNK_SHIFT); p != nil {
		col := (d.cell.z & (CHUNK - 1))*CHUNK + d.cell.x & (CHUNK - 1)
		for k in p.first[col]..<p.first[col + 1] do if i32(w.floors[p.base + i32(k)].y) < d.cell.y do to = p.base + i32(k)   // the highest below
	}
	fell := to >= 0 && floor_block(w, to) not_in h.held
	if !fell {
		from := floor_block(w, to) if to >= 0 else d.cell
		to = walk_near(w, from.x, from.y, from.z, ADRIFT, false, &h.held)
	}
	clear(&d.path)
	if to < 0 {
		if !d.adrift {
			d.adrift, d.takes, d.into, d.fall, d.pass = true, 0, 0, false, false
			d.said = fmt.aprintf("there is no ground to stand on within %s steps of it", count_words(ADRIFT))
			say(h, "%s has no ground under it: %s.", name, d.said)
			job_drop(h, i, REST)
			if d.doing == .Walking || d.doing == .Waiting || d.doing == .Working {
				d.doing = .Stopped
				errand_sum(h)
			}
		}
		return
	}
	d.from = at
	take(h, i, floor_block(w, to))
	drop := at.y - f64(d.cell.y)
	d.fall, d.pass, d.into, d.stuck = fell, false, 0, 0
	d.takes = max(i32(1000*math.sqrt(2*max(drop, 0)/9.8)), 300) if fell else 800
	if fell do h.work.fell += 1
	else {
		h.aside = true   // the log's alone: it is moved a step, and nothing is asked of the player
		say(h, "%s %s, and is moved to the nearest ground.", name, "has ground near it again" if d.adrift else "is in the way of a block laid where it stood" if !dropped else "has no ground to land on below")
	}
	if d.adrift && d.doing == .Stopped do d.doing, d.said = .Waiting, ""
	d.adrift = false
	if d.doing == .Walking do d.seek, d.wait = true, 0
}

// A dwarf has come to the end of its way.
arrive :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if d.caring {   // it came to drink, to eat or to sleep (needs.odin)
		care_arrive(h, i)
		return
	}
	if d.job {   // it came to work
		work_begin(h, i)
		return
	}
	if d.haul.on {   // or to fetch or bring something
		haul_arrive(h, i)
		return
	}
	d.doing = .Waiting
	if !d.errand do return   // it only stepped aside
	d.errand, d.rest = false, REST
	if h.errand > 0 {
		h.aside = true   // the errand's end says it of all: one line, not one a dwarf
		say(h, "%s %s is there.", h.party[i].given, h.party[i].byname)
	}
	errand_sum(h)
}

// Once no dwarf is still on its way, say how the errand ended.
errand_sum :: proc(h: ^Hold) {
	all, stopped, on_way := 0, 0, 0   // one who has come and gone on to drink or to sleep is there
	for d in h.dwarves do if d.doing != .Dead {
		all += 1
		if d.doing == .Stopped do stopped += 1
		else if d.doing == .Aboard || d.doing == .Ashore || d.errand do on_way += 1
	}
	if h.summed || on_way > 0 || all == 0 do return
	there := all - stopped
	h.summed = true
	if stopped == all {
		h.short = "None of the party found a way there."
		say(h, "None of the %s found a way to %s.", count_words(all), h.place)
	} else if stopped > 0 {
		h.short = fmt.tprintf("%d are there; %d found no way.", there, stopped)
		say(h, "%d of the %s stand at %s; %d found no way.", there, count_words(all), h.place, stopped)
	} else if h.errand == 0 {
		h.short = fmt.tprintf("The %s are ashore, and wait for word.", count_words(all))
		say(h, "The %s stand on the %s, and wait for word.", count_words(all), h.place)
		larder_tell(h)
	} else {
		h.short = fmt.tprintf("All %s are there.", count_words(all))
		say(h, "All %s stand at %s.", count_words(all), h.place)
	}
}

// A way between two floors, timed and counted.
way_timed :: proc(h: ^Hold, from, to: [3]i32, out: ^[dynamic][3]i32) -> (seconds: f32, why: Found, spent: time.Duration, made: int) {
	started := time.now()
	made = h.walk.made
	seconds, why = walk_way(&h.walk, from, to, out)
	spent, made = time.since(started), h.walk.made - made
	h.work.ways += 1
	h.work.finding += spent
	h.work.patches += made
	h.work.worst_way = max(h.work.worst_way, spent)
	return
}

// A dwarf looks for its way to its place in the errand, from the floor it stands on, round the
// dwarves that stand, and sets out; or stops, and says why.
find :: proc(h: ^Hold, i: int) {
	d, w := &h.dwarves[i], &h.walk
	d.seek, d.next, d.said = false, 1, ""
	w.budget = ASKING
	if d.adrift || walk_floor(w, d.cell.x, d.cell.y, d.cell.z) < 0 {   // its floor is gone, by no order's telling
		settle(h, i, false)
		if !d.adrift do d.seek = true   // once it has come to rest
		else if d.doing == .Walking {
			d.doing = .Stopped
			say(h, "%s %s stops: %s.", h.party[i].given, h.party[i].byname, d.said)
			errand_sum(h)
		}
		return
	}
	if g := h.spots[i]; walk_floor(w, g.x, g.y, g.z) < 0 do if f := walk_near(w, g.x, g.y, g.z, 3, false, &h.held); f >= 0 do h.spots[i] = floor_block(w, f)   // its place is no longer a floor: the nearest that is
	clear(&w.shun)
	for o, j in h.dwarves do if j != i && o.doing != .Aboard && o.doing != .Walking && o.doing != .Dead do append(&w.shun, o.cell)
	_, why, _, _ := way_timed(h, d.cell, h.spots[i], &d.path)
	clear(&w.shun)
	if why != .Way && !d.errand {   // on its way to work, or stepping aside: it gives that up
		if d.caring {
			d.retry[d.care] = h.tick + RETRY
			care_drop(h, i)
		}
		haul_drop(h, i)
		if k, ok := h.marked[d.job_at]; ok && d.job do mark_waits(h, k, .No_Way)
		clear(&d.path)
		d.doing, d.rest = .Waiting, REST
		return
	}
	if why != .Way {
		clear(&d.path)
		d.doing, d.said = .Stopped, no_way(h, why)
		h.short = fmt.tprintf("%s %s stops: no way there.", h.party[i].given, h.party[i].byname)
		say(h, "%s %s stops: %s.", h.party[i].given, h.party[i].byname, d.said)
		errand_sum(h)
	}
}

// Why no way was found, in words.
no_way :: proc(h: ^Hold, why: Found) -> string {
	switch why {
	case .Way:
	case .No_Ground: return fmt.aprintf("the place it was sent to, at %s, is no longer ground to stand on", h.place)
	case .Cut_Off:   return fmt.aprintf("no way leads to %s: water too deep to wade, or a drop or a rise of more than a block, lies all round it or all round the walker", h.place)
	case .Too_Far:   return fmt.aprintf("no way to %s was found in the %d chunks of ground a search may read", h.place, BUILDS)
	}
	return ""
}

// Whether a dwarf has landed: an order is for those who have, and the rest follow as they land.
ashore :: proc(d: Dwarf) -> bool { return d.doing != .Aboard && d.doing != .Ashore && d.doing != .Dead }

// Whether a dwarf is at rest on a floor of its own: standing, at work, or seeing to itself.
stands :: proc(d: Dwarf) -> bool { return d.doing == .Waiting || d.doing == .Stopped || d.doing == .Working || d.doing == .Drinking || d.doing == .Eating || d.doing == .Sleeping }

obey :: proc(h: ^Hold, o: Order) {
	w := &h.walk
	w.budget, w.starved = ASKING, false
	switch o.kind {
	case .Block:
		walk_edit(w, {o.at.x, o.at.y, o.at.z, o.mat})
		say(h, `The hold says "block %d %d %d %v": the ground is changed there.`, o.at.x, o.at.y, o.at.z, o.mat)
		ground_changed(h, o.at, o.mat, o.frame)
	case .Dig, .Fell, .Build, .Unmark, .Gather, .Fish:
		mark_obey(h, o)
	case .Store:
		zone_obey(h, o)
	case .Go:
		at := o.at
		if o.column do at.y = i32(math.round(ground(f64(at.x - region.origin.x) + 0.5, f64(at.z - region.origin.y) + 0.5, 1).h)) - 1
		f := walk_near(w, at.x, at.y + 1, at.z, 3)
		if f < 0 {
			say(h, `The hold says "go %d %d %d": there is no ground to stand on within three steps of it, so no one sets out.`, at.x, at.y, at.z)
			return
		}
		to := floor_block(w, f)
		was := h.place
		h.place = place_say(h, to)
		// A dwarf ashore looks for a way there, which says whether the order can be obeyed and reads
		// the ground the others will cross. One shut in where it stands, as in a pit, does not speak
		// for the rest: one from each stretch of joined ground the party stands on is asked, until a
		// way is found. If there is none, the party stays as it is.
		for d, i in h.dwarves do if d.adrift && d.doing != .Dead do settle(h, i, false)
		shut := make([dynamic]i32, context.temp_allocator)   // the rooms no way leads from
		refused := Found.Way
		asking: for d in h.dwarves do if ashore(d) && !d.adrift {
			w.budget = ASKING
			room := i32(-1)
			if f := walk_floor(w, d.cell.x, d.cell.y, d.cell.z); f >= 0 do room = floor_room(w, f)
			for r in shut do if r == room do continue asking
			way := make([dynamic][3]i32, context.temp_allocator)
			seconds, why, spent, made := way_timed(h, d.cell, to, &way)
			if !h.quiet do fmt.printfln("    (a way looked for in %.1f ms, %d chunks of ground read for it; %d floors and %.0f s of walking)", time.duration_milliseconds(spent), made, len(way), seconds)
			refused = why if why == .Cut_Off || why == .Too_Far else .Way
			if why != .Cut_Off do break
			append(&shut, room)
		}
		if refused != .Way {
			h.short = "No way leads there: no one sets out."
			say(h, `The hold says "go %d %d %d": %s, so no one sets out.`, at.x, at.y, at.z, no_way(h, refused))
			h.place = was
			return
		}
		h.errand += 1
		h.summed = false
		spots_take(h, to)
		h.short = "The party is sent."
		say(h, `The hold says "go %d %d %d": the party is sent to %s.`, at.x, at.y, at.z, h.place)
		turn := 0
		for &d, i in h.dwarves do if ashore(d) {   // each looks for its own way when its turn in the file comes
			care_drop(h, i)   // the hold's word wakes a sleeper and takes a dwarf from its meal
			job_drop(h, i, 0)
			haul_drop(h, i)
			clear(&d.path)
			d.doing, d.seek, d.next, d.said, d.errand = .Walking, true, 0, "", true
			d.wait = 0
			if d.takes == 0 do d.wait, turn = turn*IN_FILE, turn + 1
		}
	}
}

// What the ground is at a floor: its plant community, or what the surface is where none grows.
ground_words :: proc(b: [3]i32) -> string {
	x, z := f64(b.x - region.origin.x) + 0.5, f64(b.z - region.origin.y) + 0.5
	p: Point
	_, _, plants := surface_at(x, z, 1, &p)
	if k, ok := plants.?; ok do return fmt.tprintf("the %s", COMMUNITIES[k].name)
	return fmt.tprintf("the %s", SURFACES[surface_row(&p)].name)
}

// A place in words: what the ground is there, and where it lies from a named place or from the
// landing. No figure is in it (foundations/interface.md, I8): the order beside it in the log has the block.
place_say :: proc(h: ^Hold, b: [3]i32) -> string {
	x, z := f64(b.x - region.origin.x) + 0.5, f64(b.z - region.origin.y) + 0.5
	what := ground_words(b)
	if i, d := place_near(x, z); i >= 0 && d < GATHER do return fmt.aprintf("%s at %s", what, places[i].name)
	dx, dz := f64(b.x - h.landed.at.x), f64(b.z - h.landed.at.z)
	d := math.hypot(dx, dz)
	if d < 25 do return fmt.aprintf("%s by the landing", what)
	return fmt.aprintf("%s %s of the landing", what, fmt.tprintf("a short walk %s", compass(dx, dz)) if d < 150 else fmt.tprintf("a long walk %s", compass(dx, dz)) if d < 800 else fmt.tprintf("far to the %s", compass(dx, dz)))
}

hold_thread :: proc(h: ^Hold) {
	bind(h.island)
	for {
		sync.lock(&h.mutex)
		for !h.quit && h.tick < h.until && h.tick >= sync.atomic_load(&h.target) do sync.cond_wait(&h.wake, &h.mutex)
		done := h.quit || h.tick >= h.until
		for o, k in h.inbox {   // an order from the frame is obeyed at the tick it is taken, and the log keeps that
			o := o
			o.tick, o.frame = h.tick, true
			inject_at(&h.orders, h.taken + k, o)
		}
		clear(&h.inbox)
		sync.unlock(&h.mutex)
		if done do return
		hold_tick(h)
		free_all(context.temp_allocator)
	}
}

// Run the hold on its own thread until a tick; the frame's clock says how fast.
hold_start :: proc(h: ^Hold, until: int) {
	h.until, h.quit = until, false
	h.runner = thread.create_and_start_with_poly_data(h, hold_thread)
}

hold_stop :: proc(h: ^Hold) {
	if h.runner == nil do return
	sync.lock(&h.mutex)
	h.quit = true
	sync.unlock(&h.mutex)
	sync.cond_signal(&h.wake)
	thread.join(h.runner)
	thread.destroy(h.runner)
	h.runner = nil
}

// Run the hold to a time as fast as it goes, with no window, and wait for it.
hold_run :: proc(h: ^Hold, seconds: f64) {
	if !h.found || seconds <= 0 do return
	until := int(seconds/TICK + 0.5)
	sync.atomic_store(&h.target, until)
	hold_start(h, until)
	thread.join(h.runner)
	thread.destroy(h.runner)
	h.runner = nil
}

log_hash :: proc(h: ^Hold) -> (v: u64) {
	v = 0xcbf29ce484222325
	for line in h.log do v = fnv.fnv64a(transmute([]u8)line, v)
	return
}

// What a run came to and what it cost.
hold_report :: proc(h: ^Hold) {
	if !h.found || h.tick == 0 do return
	fmt.printfln("the dwarves' world ran %d ticks, %d:%02d of its time: %d events, the log's hash %x", h.tick, h.tick/600, h.tick/10%60, len(h.log), log_hash(h))
	fmt.printfln("  a tick of %d dwarves took %.1f µs on average, the looking for ways apart, and %.1f ms at worst with it; %d ways looked for, %.2f ms each on average and %.1f ms at worst, %d chunks of ground read for them of %d in all",
		len(h.dwarves), time.duration_microseconds(h.work.walking)/f64(h.tick), time.duration_milliseconds(h.work.worst_tick), h.work.ways, time.duration_milliseconds(h.work.finding)/f64(max(h.work.ways, 1)),
		time.duration_milliseconds(h.work.worst_way), h.work.patches, h.walk.made)
	fmt.printfln("  dwarves went round another %d times and squeezed past one %d times; %d fell", h.work.round, h.work.squeezed, h.work.fell)
	{   // the day, and how each dwarf is (needs.odin)
		date := date_tick(h.tick)
		days, loose := food_days(h)
		fmt.printfln("  it is the %s, %02d:%02d; %d of %d alive; food in the stockpiles for %.1f days, %d things of food loose; %d places to drink known", date_words(date), int(date.hour), int(date.hour*60)%%60, living(h), len(h.dwarves), days, loose, len(h.wells))
		for d, i in h.dwarves {
			if d.doing == .Dead do fmt.printfln("    %s: dead of %s since the %s", who(h, i), WANTS[d.died].of, date_words(date_tick(d.died_on)))
			else do fmt.printfln("    %s: drink %.2f, food %.2f, sleep %.2f%s%s", who(h, i), d.want[.Drink], d.want[.Food], d.want[.Sleep], fmt.tprintf("; %v", d.doing) if d.doing >= .Drinking else "", fmt.tprintf("; finds no %v", d.lacks) if d.lacks != {} else "")
		}
	}
	if len(h.sites) > 0 {
		left := 0
		for site in h.sites do left += int(!site.over)
		fmt.printfln("  orders: %d given, %d with work left; %d blocks and trees worked, %d marks left; %d looks for work, %.2f ms each; %d counts of dwarves a change would shut in, %.2f ms each",
			len(h.sites), left, h.work.done, len(h.marks), h.work.looks, time.duration_milliseconds(h.work.looking)/f64(max(h.work.looks, 1)), h.work.counts, time.duration_milliseconds(h.work.counting)/f64(max(h.work.counts, 1)))
		if len(h.marks) > 0 {   // what the marks left wait for
			waits: [Waits]int
			for m in h.marks do waits[m.wait if m.taker < 0 else .None] += 1
			fmt.print("  the marks left:")
			for n, why in waits do if n > 0 do fmt.printf(" %d %s;", n, WAITS[why] if why != .None else "in hand or free to take")
			fmt.println()
		}
		fmt.print("  the store:")
		any := false
		for n, m in h.store do if n > 0 {
			fmt.printf("%s %d of %s", "," if any else "", n, store_words(m))
			any = true
		}
		fmt.println("" if any else " nothing")
	}
	w := &h.walk
	fmt.printfln("  the ground read: %d floors in %d rooms of %d chunks, %.1f MB kept", len(w.floors), len(w.rooms), w.made,
		f64(len(w.floors)*(size_of(Floor) + size_of(^Patch) + 20) + len(w.rooms)*size_of(Room) + w.made*size_of(Patch))/1e6)
	fmt.printfln("  the ground worked: %d blocks changed, %d chunks' blocks kept in %.1f MB; %d floors' places left behind by patches that outgrew them", len(w.edits), w.kept, f64(w.kept_bytes)/1e6, w.wasted)
}

// ---- beside the frame -------------------------------------------------------------------------

// The frame thread's own view of the hold. Everything it knows of the dwarves is in `seen`.
Watch :: struct {
	live:     bool,              // the hold runs beside the frame; a picture is of one moment
	clock:    f64,               // seconds of the dwarves' world the frames have shown: the game's clock (clock.odin), held back while the hold is behind it
	wall:     f64,               // real seconds, for how long an answer stays up
	seen:     Shown,
	feet:     [dynamic][3]f64,   // where each dwarf was last drawn
	turned:   [dynamic]f32,      // and which way, eased
	drawn:    bool,
	pending:  [dynamic]Order,    // orders not yet handed over
	selected: int,               // the dwarf selected, or -1
	send:     bool,              // an order is to be given at the pointer once a block is under it (--send)
}
watch := Watch{selected = -1}

// Whether a run was asked only to run the dwarves' world with no window, print what happened and exit.
hold_alone :: proc(opt: ^Options) -> bool {
	return opt.dwarves > 0 && opt.shot == "" && opt.play == "" && opt.bench == 0 && !opt.show && !opt.has_why && !opt.survey && opt.map_path == ""
}

// Send the party to stand on a block. The one call an order from a cursor needs.
hold_send :: proc(x, y, z: i32) {
	if hold.found do append(&watch.pending, Order{kind = .Go, at = {x, y, z}})
}

// Give the hold an order: to go, or to mark ground to dig, trees to fell or blocks to build, or to take marks back (orders.odin).
hold_order :: proc(o: Order) {
	if hold.found do append(&watch.pending, o)
}

// Tell the hold a block was changed (world_set).
hold_block :: proc(x, y, z: i32, m: Mat) {
	if hold.found do append(&watch.pending, Order{kind = .Block, at = {x, y, z}, mat = m})
}

// The window is up: put the player where the landing can be watched and the view from above over
// the landing, both facing the water the boat crosses, and set the hold going.
hold_enter :: proc(p: ^Player, above: ^Above, opt: ^Options) {
	h := &hold
	if !h.found do return
	bound(h.island)
	if !opt.has_pos {
		// The highest floor 6 to 14 m from the landing that sees it and the water the boat crosses.
		l, w := h.landed, &h.walk
		w.budget = ASKING
		best, top := -1, min(i32)
		for dz in i32(-14)..=14 do for dx in i32(-14)..=14 {
			if d := dx*dx + dz*dz; d < 36 || d > 196 do continue
			f, ok := walk_top(w, l.at.x + dx, l.at.z + dz)
			if !ok || int(w.floors[f].y) <= int(top) do continue
			eye, clear := feet_on(floor_block(w, f)) + {0, EYE, 0}, true
			for to in ([2][3]f64{feet_on(l.at) + {0, 1, 0}, {h.boat_to.x + 12*l.out.x, 0.5, h.boat_to.y + 12*l.out.y}}) do for s in 1..<24 {
				at := math.lerp(eye, to, f64(s)/24)
				if g, any := walk_top(w, i32(math.floor(at.x)), i32(math.floor(at.z))); any && f64(w.floors[g].y) > at.y do clear = false
			}
			if clear do best, top = int(f), i32(w.floors[f].y)
		}
		if best >= 0 {
			p.pos = feet_on(floor_block(w, i32(best))) + {0, 0.1, 0}
			if !opt.has_look do p.yaw, p.pitch = f32(math.atan2(h.boat_to.x + 12*l.out.x - p.pos.x, -(h.boat_to.y + 12*l.out.y - p.pos.z))), -0.12
		}
	}
	if !opt.has_over {
		above.at = (feet_on(h.landed.at) + feet_on(h.landed.camp))/2
		if !opt.has_turn do above.yaw = f32(math.atan2(h.landed.out.x, -h.landed.out.y))
	}
	shown_copy(&watch.seen, h.shown)
	watch.clock = f64(h.tick)*TICK
	watch.live = opt.shot == "" || opt.bench > 0
	watch.send = opt.send && opt.has_cursor
	if watch.live do hold_start(h, max(int))
}

hold_leave :: proc() {
	hold_stop(&hold)
	if watch.live do hold_report(&hold)
}

// First block along a ray within a reach, and how far off it is.
sight :: proc(w: ^World, origin: [3]f64, dir: [3]f32, reach: f64) -> (hit: [3]i32, far: f64, ok: bool) {
	cell := [3]i32{i32(math.floor(origin.x)), i32(math.floor(origin.y)), i32(math.floor(origin.z))}
	step: [3]i32
	next, delta: [3]f64
	for a in 0..<3 {
		d := f64(dir[a])
		if d > 0 do step[a], delta[a], next[a] = 1, 1/d, (f64(cell[a]) + 1 - origin[a])/d
		else if d < 0 do step[a], delta[a], next[a] = -1, -1/d, (f64(cell[a]) - origin[a])/d
		else do delta[a], next[a] = math.INF_F64, math.INF_F64
	}
	for {
		a := 0 if next.x < next.y && next.x < next.z else 1 if next.y < next.z else 2
		if next[a] > reach do return
		far = next[a]
		cell[a] += step[a]
		next[a] += delta[a]
		if m, known := world_block(w, cell.x, cell.y, cell.z); known && m != .Air do return cell, far, true
	}
}

// Each frame: hand over orders, take what the hold shows, move its clock on by the world's time
// that passed (clock.odin: none while paused, more at a speed), and answer the keys and the pointer.
// `ray` runs from the eye through the crosshair, or from above through the pointer; `above` is the
// view from above, or nil in first person.
//   G             send the party to the block aimed at, or under the pointer
//   right click   from above: send the party to the block under the pointer (a drag still turns the view)
// Selecting a dwarf is the interface's (play.odin): a click from above, and E in first person, a row of BINDS.
hold_frame :: proc(w: ^World, eye: [3]f64, ray: [3]f32, above: ^Above, passed, dt: f64) {
	h := &hold
	if !h.found do return
	watch.wall += dt
	// The lock is only tried, as the world's is: the hold has it for moments, but a frame must not wait on a thread held off the processor.
	if sync.try_lock(&h.mutex) {
		shown_copy(&watch.seen, h.shown)
		if watch.live {
			append(&h.inbox, ..watch.pending[:])
			clear(&watch.pending)
		}
		told := make([]Edit, len(h.out), context.temp_allocator)   // blocks an orders file changed: the world drawn changes with them
		copy(told, h.out[:])
		clear(&h.out)
		for l in h.out_laid do if l.on do bar.built[l.at] = l.plan   // what a block was laid as, for a click on it to say (bar.odin)
		else do delete_key(&bar.built, l.at)
		clear(&h.out_laid)
		sync.unlock(&h.mutex)
		for e in told do world_set(w, e.x, e.y, e.z, e.mat, false)
	}
	if watch.live {
		watch.clock = min(watch.clock + passed, f64(watch.seen.tick + 2)*TICK)   // a hold busy finding a way holds its clock back; it is not hurried after
		sync.atomic_store(&h.target, int(watch.clock/TICK))
		sync.cond_signal(&h.wake)
	}
	// The block an order would send the party to, and how far a dwarf can be picked out.
	target: [3]i32
	aimed := false
	if above == nil do target, _, aimed = sight(w, eye, ray, AIM_REACH)
	else if above.shown {
		under := above.under
		if !under.ok do under = pick_far(eye, ray, above_level(above))
		target, aimed = under.block, under.ok
	}
	if watch.send && above != nil && aimed {   // --send: the order a click would give, of the tool held if one is (bar.odin)
		if tool_marks() && above.marked do tool_give(above)
		else if !tool_marks() do hold_send(target.x, target.y, target.z)
		watch.send = tool_marks() && !above.marked
	}
}

// What a dwarf says of itself, in the shape of the card the interface shows for the thing selected
// (foundations/interface.md, I2, I3 and I8): who it is; what it is doing, and why; and what it will
// do next or what it waits for, empty when there is nothing to say. Each line leads with its point
// and keeps figures behind words. --why, the key E and a click print these lines; a panel will draw them.
Card :: struct { who, doing, next: string }

dwarf_card :: proc(s: ^Shown, i: int) -> (c: Card) {
	d := s.dwarves[i]
	c.who = fmt.tprintf("%s, who %s", dwarf_name(d.who), TRADES[d.who.trade].does)
	to := fmt.tprintf("the %s", s.place) if s.errand == 0 else s.place
	why := "where the party gathers" if s.errand == 0 else "where the hold sent the party"
	switch d.doing {
	case .Aboard:
		c.doing = "In the boat at the landing, while those ahead step ashore" if s.grounded else "In the boat, pulling for the landing"
		c.next = "Will step ashore in turn" if s.grounded else "Will step ashore when the boat grounds"
	case .Ashore:
		c.doing, c.next = "Stepping ashore over the bow", fmt.tprintf("Will walk to %s", to)
	case .Walking:
		far := "about to set out" if d.left >= d.of - 1 else "nearly there" if 4*d.left < d.of else "about half way" if 3*d.left < 2*d.of else "not long set out"
		c.doing, c.next = fmt.tprintf("Walking to %s, %s; %s", to, why, far), "Will wait there for word from the hold"
	case .Waiting:
		c.doing, c.next = fmt.tprintf("Standing %s %s, %s", "on" if s.errand == 0 else "at", to, why), "Waits for word from the hold"
	case .Stopped:
		c.doing, c.next = fmt.tprintf("Stopped where it stands: %s", d.said), "Waits for word from the hold"
	case .Working, .Drinking, .Eating, .Sleeping, .Dead:
	}
	// Its work, and the order it is for (orders.odin).
	if d.job do for site in s.sites do if site.id == d.site {
		row := WORKS[site.work]
		what := fmt.tprintf("a %s", SPECIES_OF[d.cut]) if site.work == .Fell else store_words(d.cut) if site.work == .Build && d.cut != .Air else mat_words(d.cut)
		if d.working do c.doing = fmt.tprintf("Laying %s for the %s", what, site.place) if site.work == .Build else fmt.tprintf("Felling %s, one of the %s", what, site.place) if site.work == .Fell else fmt.tprintf("Digging %s for the %s", what, site.place)
		else do c.doing = fmt.tprintf("Walking to the %s, to %s there", site.place, row.name)
		c.next = fmt.tprintf("Will take more of that work while any is left: %d of its %d %s are still to do", site.left, site.total, "trees" if site.work == .Fell else "blocks")
	}
	if !d.job && (d.doing == .Waiting || d.doing == .Stopped) && s.marks > 0 && !d.shut do c.next = "Looks for work it can reach among what is marked"
	if d.carrying > 0 do c.doing, c.next = fmt.tprintf("Carrying %d of %s to where it is wanted", d.carrying, store_words(d.carry)), "Will look for more to carry, or for marked work"
	else if d.fetching do c.doing, c.next = "Going to fetch something that lies loose", "Will carry it to a stockpile, or to a block marked to be laid"
	// Its needs (needs.odin): what it is doing for itself, and what it lacks.
	if d.caring do switch d.care {
	case .Drink: c.doing, c.next = "Drinking at fresh water" if d.doing == .Drinking else "Walking to fresh water, to drink", "Will go back to what the hold wants done"
	case .Food:  c.doing, c.next = fmt.tprintf("Eating %s", store_words(d.cut)) if d.doing == .Eating else "Walking to food, to eat", "Will go back to what the hold wants done"
	case .Sleep: c.doing, c.next = "Asleep on the ground" if d.doing == .Sleeping else "Looking for dry ground to sleep on", "Will wake when it is rested, or when thirst or hunger wake it"
	}
	if d.shut do c.doing, c.next = "Shut in: no way leads out of where it stands", "Waits for a stair to be dug or built to it"
	if d.fall do c.doing = "Falling: the ground went from under it"
	if d.doing == .Dead do c.doing, c.next = fmt.tprintf("Dead of %s since the %s; the body lies where it fell", WANTS[d.died].of, date_words(date_tick(d.died_on))), ""

	return
}


// ---- for a cursor, a row or a picture (foundations/interface.md, I2 and I4) -----------------------
// hold_send, above, gives the order. These list the dwarves, choose one and lead to it; all are the
// frame thread's, and read what the hold last showed.

// How many dwarves the hold has.
hold_count :: proc() -> int { return len(watch.seen.dwarves) }

// How many of them are alive: what the hold is.
hold_living :: proc() -> (n: int) {
	for d in watch.seen.dwarves do n += int(d.doing != .Dead)
	return
}

// Select a dwarf, or none with -1. The card of the one selected is hold_card's.
hold_select :: proc(i: int) { watch.selected = i if i >= 0 && i < hold_count() else -1 }

hold_selected :: proc() -> int { return watch.selected }

// A dwarf's card, for a panel or a row.
hold_card :: proc(i: int) -> Card { return dwarf_card(&watch.seen, i) }

// Where a dwarf's feet are, as last drawn, for the view to go to.
hold_where :: proc(i: int) -> (at: [3]f64, ok: bool) {
	if i < 0 || i >= hold_count() do return
	return watch.feet[i] if watch.drawn && i < len(watch.feet) else watch.seen.dwarves[i].at, true
}

// The dwarf a ray from the eye meets first within a reach, before any block that is drawn, or -1.
// From above the blocks over the cut are not drawn, and do not hide a dwarf.
hold_aimed :: proc(w: ^World, eye: [3]f64, ray: [3]f32, reach: f64, above: ^Above) -> (who: int) {
	who = -1
	near := reach
	for d, i in watch.seen.dwarves {   // the ray against each dwarf's box
		if i >= len(watch.feet) do break
		lo, hi := watch.feet[i] - {0.3, 0, 0.3}, watch.feet[i] + {0.3, f64(d.who.tall), 0.3}
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
		if t0 <= t1 do who, near = i, t0
	}
	if who < 0 do return
	if above == nil {
		if _, far, ok := sight(w, eye, ray, near); ok && far < near do who = -1
	} else if p := pick(w, eye, ray, above_level(above), above.bare, near); p.ok {
		b := feet_on(p.block) + {0, 0.5, 0}
		if linalg.length(b - eye) < near - 1 do who = -1
	}
	return
}

// The boat and the dwarves as boxes after the creatures', from the eye.
hold_pose :: proc(boxes: []Box, eye: [3]f64, dt: f64) -> []Box {
	h := &hold
	if !h.found do return boxes
	s := &watch.seen
	out := make([dynamic]Box, 0, len(boxes) + 16*len(s.dwarves) + 8, context.temp_allocator)
	append(&out, ..boxes)
	a := clamp((watch.clock - f64(s.tick)*TICK)/TICK, 0, 1) if watch.live else 1
	rel :: proc(p, eye: [3]f64) -> [3]f32 { return {f32(p.x - eye.x), f32(p.y - eye.y), f32(p.z - eye.z)} }
	boat := math.lerp(s.boat_was, s.boat, a)
	bob := 0.0 if s.grounded else 0.04*math.sin(watch.clock*1.7)
	boat_boxes(&out, rel({boat.x, SEA_SURFACE + 0.04 + bob, boat.y}, eye), f32(math.atan2(-h.landed.out.x, h.landed.out.y)))
	builtin.resize(&watch.feet, len(s.dwarves))
	for len(watch.turned) < len(s.dwarves) do append(&watch.turned, s.dwarves[len(watch.turned)].facing)
	for d, i in s.dwarves {
		at := math.lerp(d.was, d.at, a)
		watch.feet[i] = at
		turn := math.mod(d.facing - watch.turned[i] + 3*math.PI, math.TAU) - math.PI   // the short way round
		watch.turned[i] = d.facing if !watch.drawn || !watch.live else watch.turned[i] + turn*f32(min(10*dt, 1))
		dwarf_boxes(&out, d.who, rel(at, eye), watch.turned[i], math.lerp(d.trod, d.stride, a), d.at != d.was && !d.fall && d.doing != .Aboard, d.doing == .Aboard, f32(d.toil + (watch.clock - f64(s.tick)*TICK if watch.live else 0)) if d.working else -1, d.carry, d.carrying,
			.Dead if d.doing == .Dead else .Asleep if d.doing == .Sleeping else .Stooped if d.doing == .Drinking || d.doing == .Eating else .Up)
	}
	watch.drawn = true
	return out[:]
}

// The landing and any dwarf standing at a point, as --why and the key Y say them.
hold_words :: proc(x, z: f64) {
	h := &hold
	if !h.found || here != h.island do return
	s := &watch.seen if h.runner != nil else &h.shown   // beside a running hold, only what it last showed may be read
	wx, wz := x + f64(region.origin.x), z + f64(region.origin.y)
	l := h.landed
	if d := math.hypot(wx - f64(l.at.x) - 0.5, wz - f64(l.at.z) - 0.5); d < 60 {
		fmt.printfln("the dwarves' landing is %.0f m off:", d)
		landing_words(l)
	}
	for d, i in s.dwarves do if math.hypot(wx - d.at.x, wz - d.at.z) < 3 {
		c := dwarf_card(s, i)
		fmt.printfln("a dwarf stands here, %d:%02d after the boat stood off: %s.\n  %s.\n  %s.", s.tick/600, s.tick/10%60, c.who, c.doing, c.next)
	}
}

// ---- for the screen's top and its alerts (foundations/interface.md, I14) ---------------------------

// What is wrong with where a dwarf stands, as far as the hold can say before dwarves have needs
// (plan.md, P4): it has no ground under it; or it has stopped, and the ground it stands on is closed
// all round, a pit or a ledge it cannot leave; or it has stopped with open ground about it, and found
// no way to where it was sent. The screen makes a row of each (NEEDS, crowd.odin).
Plight  :: enum u8 { None, No_Ground, Shut_In, No_Way }
SHUT_IN :: 64   // floors of joined ground, at most, that count as being shut in

// A stopped dwarf's ground is followed out from its floor over what has been read, making no patch:
// ground that ends before SHUT_IN floors is closed. It is asked again every sixteenth tick, since a
// block laid or dug may have opened it.
plight_of :: proc(h: ^Hold, i: int) -> Plight {
	d, w := &h.dwarves[i], &h.walk
	if d.adrift do return .No_Ground
	if d.shut do return .Shut_In   // in a pit, found when it last looked to itself (idle_care, orders.odin)
	if d.doing != .Stopped do return .None
	if h.tick > 0 && i < len(h.shown.dwarves) && (h.tick + i)%16 != 0 {
		if was := h.shown.dwarves[i]; was.plight > .No_Ground && raw_data(was.said) == raw_data(d.said) do return was.plight
	}
	f := walk_floor(w, d.cell.x, d.cell.y, d.cell.z, false)
	if f < 0 do return .No_Way
	w.stamp += 1
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, f)
	w.seen[f] = w.stamp
	for k := 0; k < len(queue); k += 1 {
		if len(queue) > SHUT_IN do return .No_Way
		for way in 0..<8 {
			t := floor_step(w, queue[k], way, false)
			if t < 0 {
				if (w.floors[queue[k]].links >> u16(2*way)) & 3 != 0 do return .No_Way   // a step onto ground not yet read: it is not known to be closed
				continue
			}
			if w.seen[t] != w.stamp {
				w.seen[t] = w.stamp
				append(&queue, t)
			}
		}
	}
	return .Shut_In
}

// Where a line of the log happened, and to whom, for a message to lead there (I4): the block of the
// order it gives; or where the dwarf it begins with stands; or else where the errand leads, and
// before anyone is ashore the landing.
about :: proc(h: ^Hold, line: string) -> (at: [3]f64, who: int) {
	who = -1
	text := line
	if i := strings.index(text, "] "); i >= 0 do text = text[i + 2:]
	for f, i in h.party do if strings.has_prefix(text, f.given) && strings.has_prefix(text[len(f.given):], " ") && strings.has_prefix(text[len(f.given) + 1:], f.byname) {
		return feet_of(h, i), i
	}
	if strings.has_prefix(text, `The hold says "`) {
		words := strings.fields(text[len(`The hold says "`):], context.temp_allocator)
		v: [3]i32
		ok := len(words) >= 4
		if ok do for k in 0..<3 {
			n, good := strconv.parse_int(strings.trim_right(words[k + 1], `":`))
			v[k], ok = i32(n), ok && good
		}
		if ok do return feet_on(v), -1
	}
	for d in h.dwarves do if ashore(d) do return feet_on(h.spots[0]), -1
	return feet_on(h.landed.at), -1
}
