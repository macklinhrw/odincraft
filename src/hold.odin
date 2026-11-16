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
import sdl "vendor:sdl3"

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
// An orders file has a line for each: the time, in seconds or as the log prints it, then
//   go x z          send the party to the ground at that column
//   go x y z        send it to stand on that block
//   block x y z M   the block there is now the material M (Air for dug out)
// A line of the log that begins `The hold says "..."` gives the order in this form, with its time
// before it, so the log of a played game can be played again.

TICK      :: 0.1     // seconds of the dwarves' world in a tick
TICK_MS   :: 100
LANDING   :: 7       // who come in the first boat. The hold grows: nothing below counts on seven
ROWING    :: 1.4     // metres a second the boat comes in
STEP_OUT  :: 15      // ticks between one dwarf stepping ashore and the next
IN_FILE   :: 8       // ticks between one dwarf setting out and the next, so a party walks in file and looks for its ways one at a time
ASKING    :: 64      // patches the hold may make to answer one order, before any way is looked for
AIM_REACH :: 160.0   // metres off a block can be aimed at in first person to send the party to it, or a dwarf asked

Doing :: enum u8 { Aboard, Ashore, Walking, Waiting, Stopped }
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
}
Order_Kind :: enum u8 { Go, Block }
Order :: struct {
	tick:   int,
	kind:   Order_Kind,
	at:     [3]i32,
	column: bool,   // go: only the column was given, and its ground is meant
	mat:    Mat,
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
}
Shown :: struct {
	tick:      int,
	boat_was, boat: [2]f64,
	grounded:  bool,
	errand:    int,
	place:     string,
	dwarves:   [dynamic]Seen,
}

Hold :: struct {
	island:   ^Formed,
	walk:     Walk,
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
	errand:   int,            // orders to go obeyed so far; none while the party gathers above the landing
	place:    string,         // where the errand leads, in words
	summed:   bool,           // its end has been said
	orders:   [dynamic]Order, // by tick
	taken:    int,
	log:      [dynamic]string,
	showing:  [dynamic]Seen,  // the next tick's picture, as it is laid out
	work:     struct { ways, patches: int, walking, finding, worst_tick, worst_way: time.Duration },
	// Shared with the frame thread, under the mutex.
	mutex:    sync.Mutex,
	wake:     sync.Cond,
	inbox:    [dynamic]Order,
	shown:    Shown,
	target:   int,            // the tick the game's clock has reached (atomic)
	until:    int,            // the tick to stop at
	quit:     bool,
	runner:   ^thread.Thread,
}
hold: Hold   // the player's hold

// ---- making it ------------------------------------------------------------------------------

// Make the hold on an island: draw the party the boat brings, choose the landing and say both, and read the orders.
hold_make :: proc(h: ^Hold, island: ^Formed, orders: string, count := LANDING) {
	started := time.now()
	bound(island)
	h.island = island
	walk_init(&h.walk, island)
	party_draw(world_seed, count, &h.party)
	builtin.resize(&h.dwarves, count)
	builtin.resize(&h.spots, count)
	h.walk.budget = ASKING
	h.landed, h.found = landing_choose(&h.walk)
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
	h.place = "ground above the landing"
	for &d in h.dwarves do d.facing = f32(math.atan2(-l.out.x, l.out.y))
	orders_read(h, orders)
	hold_show(h)
	if h.quiet do return
	fmt.printfln("the hold: %s dwarves come by boat, their landing chosen in %.0f ms:", count_words(count), time.duration_milliseconds(time.since(started)))
	landing_words(l)
	m := middle_of(land.grid, l.cell)
	c := land_cell(m.x, m.y)
	fmt.printfln("  the boat comes in %.0f m from the %s and grounds at %d, %d, %d; the party gathers at %d, %d, %d, %.0f m from the boat and %.0f m from fresh water",
		math.hypot(h.boat_from.x - h.boat_to.x, h.boat_from.y - h.boat_to.y), compass(l.out.x, l.out.y), l.at.x, l.at.y, l.at.z, l.camp.x, l.camp.y, l.camp.z,
		math.hypot(f64(l.camp.x - l.at.x), f64(l.camp.z - l.at.z)), fresh_water(c))
	fmt.printf("  the %s:", count_words(count))
	for f, i in h.party do fmt.printf("%s %s", "" if i == 0 else ";", dwarf_name(f))
	fmt.println()
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
	for i in n..<len(h.spots) do h.spots[i] = at   // no room to spread: they crowd
}

orders_read :: proc(h: ^Hold, path: string) {
	if path == "" do return
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintln("cannot read the orders in", path)
		os.exit(2)
	}
	for line in strings.split_lines(string(data), context.temp_allocator) {
		words := strings.fields(strings.trim_space(line), context.temp_allocator)
		if len(words) == 0 || strings.has_prefix(words[0], "#") do continue
		o: Order
		when_, rest := strings.trim(words[0], "[]"), words[2:] if len(words) > 2 else nil
		seconds := 0.0
		for part in strings.split(when_, ":", context.temp_allocator) do seconds = seconds*60 + (strconv.parse_f64(part) or_else -1e9)
		v: [3]i32
		ok := seconds >= 0 && len(words) >= 4
		if ok do for i in 0..<min(len(rest), 3) {
			n, good := strconv.parse_int(rest[i])
			v[i], ok = i32(n), ok && good
		}
		if ok do switch words[1] {
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
		if !ok {
			fmt.eprintfln("bad order in %s: %s", path, line)
			os.exit(2)
		}
		o.tick = int(seconds/TICK + 0.5)
		at := len(h.orders)
		for at > 0 && h.orders[at - 1].tick > o.tick do at -= 1
		inject_at(&h.orders, at, o)
	}
}

// ---- running it -----------------------------------------------------------------------------

// A line of the log, with the time it happened.
say :: proc(h: ^Hold, format: string, args: ..any) {
	s := h.tick/10
	line := fmt.aprintf("[%d:%02d.%d] %s", s/60, s%60, h.tick%10, fmt.tprintf(format, ..args))
	append(&h.log, line)
	if !h.quiet do fmt.println(line)
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
	return math.lerp(d.from, feet_on(d.cell), f64(d.into)/f64(d.takes))
}

// Lay out what the frame may see of the tick in hand, and put it where the frame reads it.
hold_show :: proc(h: ^Hold) {
	builtin.resize(&h.showing, len(h.dwarves))
	for &d, i in h.dwarves {
		at := feet_of(h, i)
		was, trod := at, d.stride
		if h.tick > 0 && i < len(h.shown.dwarves) do was, trod = h.shown.dwarves[i].at, h.shown.dwarves[i].stride
		h.showing[i] = {who = h.party[i], was = was, at = at, trod = trod, stride = d.stride, facing = d.facing, doing = d.doing, left = len(d.path) - d.next, of = len(d.path), said = d.said}
	}
	boat := boat_at(h, h.tick)
	sync.lock(&h.mutex)
	h.shown.boat_was, h.shown.boat = h.shown.boat if h.tick > 0 else boat, boat
	h.shown.tick, h.shown.errand, h.shown.place, h.shown.grounded = h.tick, h.errand, h.place, h.tick >= h.boat_ticks
	h.shown.dwarves, h.showing = h.showing, h.shown.dwarves
	sync.unlock(&h.mutex)
}

// A copy of what the hold shows, into a picture that keeps its own room.
shown_copy :: proc(to: ^Shown, from: Shown) {
	room := to.dwarves
	to^ = from
	to.dwarves = room
	builtin.resize(&to.dwarves, len(from.dwarves))
	copy(to.dwarves[:], from.dwarves[:])
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
	if h.tick == 0 do say(h, "A boat with %s dwarves stands %.0f m off the shore, to the %s, and pulls for the landing.", count_words(len(h.dwarves)), math.hypot(h.boat_from.x - h.boat_to.x, h.boat_from.y - h.boat_to.y), compass(h.landed.out.x, h.landed.out.y))
	if h.tick == h.boat_ticks do say(h, "The boat grounds at %d, %d, on %s.", h.landed.at.x, h.landed.at.z, ground_words(h.landed.at)[4:])
	for &d, i in h.dwarves {
		if d.doing == .Aboard && h.tick >= h.boat_ticks + 20 + STEP_OUT*i {   // over the bow, one at a time
			d.from = feet_of(h, i)
			d.doing, d.cell, d.takes, d.into = .Ashore, h.landed.at, 1500, 0
		}
		if d.takes == 0 && d.doing == .Walking {
			if d.wait > 0 do d.wait -= 1
			else {
				if d.seek do find(h, i)
				if d.doing == .Walking && !step_on(h, &d) do arrive(h, i)
			}
		}
		if d.takes == 0 do continue
		d.into += TICK_MS
		for d.takes > 0 && d.into >= d.takes {
			d.into -= d.takes
			d.takes = 0
			if d.doing == .Ashore {
				say(h, "%s, steps ashore.", dwarf_name(h.party[i]))
				d.doing, d.seek, d.wait = .Walking, true, 0
			}
			if d.doing != .Walking || d.seek do d.into = 0   // it stands, or looks for its way next tick
			else if !step_on(h, &d) do arrive(h, i)
		}
	}
	h.tick += 1
	hold_show(h)
	spent := time.since(started)
	h.work.worst_tick = max(h.work.worst_tick, spent)
	h.work.walking += spent - (h.work.finding - found)
}

// Begin the next step of a dwarf's way; false at its end.
step_on :: proc(h: ^Hold, d: ^Dwarf) -> bool {
	if d.next >= len(d.path) {
		d.into = 0
		return false
	}
	to := d.path[d.next]
	h.walk.budget = ASKING
	a, b := walk_floor(&h.walk, d.cell.x, d.cell.y, d.cell.z), walk_floor(&h.walk, to.x, to.y, to.z)
	d.from = feet_on(d.cell)
	d.takes = max(i32(step_seconds(&h.walk, a, b)*1000), 1) if a >= 0 && b >= 0 else 750
	d.stride += math.hypot(f64(to.x - d.cell.x), f64(to.z - d.cell.z))
	d.facing = f32(math.atan2(f64(to.x - d.cell.x), -f64(to.z - d.cell.z)))
	d.cell = to
	d.next += 1
	return true
}

// A dwarf has come to the end of its way.
arrive :: proc(h: ^Hold, i: int) {
	h.dwarves[i].doing = .Waiting
	if h.errand > 0 do say(h, "%s %s is there.", h.party[i].given, h.party[i].byname)
	errand_sum(h)
}

// Once no dwarf is still on its way, say how the errand ended.
errand_sum :: proc(h: ^Hold) {
	there, stopped := 0, 0
	for d in h.dwarves {
		there += int(d.doing == .Waiting)
		stopped += int(d.doing == .Stopped)
	}
	all := len(h.dwarves)
	if h.summed || there + stopped < all do return
	h.summed = true
	if stopped == all do say(h, "None of the %s found a way to %s.", count_words(all), h.place)
	else if stopped > 0 do say(h, "%d of the %s stand at %s; %d found no way.", there, count_words(all), h.place, stopped)
	else if h.errand == 0 do say(h, "The %s stand on the %s, and wait for word.", count_words(all), h.place)
	else do say(h, "All %s stand at %s.", count_words(all), h.place)
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

// A dwarf looks for its way to its place in the errand, from the floor it stands on, and sets out; or stops, and says why.
find :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	d.seek, d.next, d.said = false, 1, ""
	if _, why, _, _ := way_timed(h, d.cell, h.spots[i], &d.path); why != .Way {
		clear(&d.path)
		d.doing, d.said = .Stopped, no_way(h, why)
		say(h, "%s %s stops: %s.", h.party[i].given, h.party[i].byname, d.said)
		errand_sum(h)
	}
}

// Why no way was found, in words.
no_way :: proc(h: ^Hold, why: Found) -> string {
	switch why {
	case .Way:
	case .No_Ground: return "the ground under its feet is gone"
	case .Cut_Off:   return fmt.aprintf("no way leads to %s: water too deep to wade, or a drop or a rise of more than a block, lies all round it or all round the walker", h.place)
	case .Too_Far:   return fmt.aprintf("no way to %s was found in the %d chunks of ground a search may read", h.place, BUILDS)
	}
	return ""
}

// Whether a dwarf has landed: an order is for those who have, and the rest follow as they land.
ashore :: proc(d: Dwarf) -> bool { return d.doing != .Aboard && d.doing != .Ashore }

obey :: proc(h: ^Hold, o: Order) {
	w := &h.walk
	w.budget, w.starved = ASKING, false
	switch o.kind {
	case .Block:
		walk_edit(w, {o.at.x, o.at.y, o.at.z, o.mat})
		say(h, `The hold says "block %d %d %d %v": the ground is changed there.`, o.at.x, o.at.y, o.at.z, o.mat)
		// A way laid over the old ground may not hold: each dwarf whose way still passes the block
		// stops at the end of its step and looks again, one a tick.
		turn := 0
		for &d in h.dwarves do if d.doing == .Walking && !d.seek {
			for b in d.path[min(d.next, len(d.path)):] do if abs(b.x - o.at.x) <= 1 && abs(b.z - o.at.z) <= 1 && abs(b.y - o.at.y) <= 2 {
				clear(&d.path)
				d.seek, d.wait = true, turn
				turn += 1
				break
			}
		}
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
		// The first dwarf ashore looks for a way there, which says whether the order can be obeyed
		// and reads the ground the others will cross. If there is none, the party stays as it is.
		for d in h.dwarves do if ashore(d) {
			way := make([dynamic][3]i32, context.temp_allocator)
			seconds, why, spent, made := way_timed(h, d.cell, to, &way)
			if !h.quiet do fmt.printfln("    (a way looked for in %.1f ms, %d chunks of ground read for it; %d floors and %.0f s of walking)", time.duration_milliseconds(spent), made, len(way), seconds)
			if why == .Cut_Off || why == .Too_Far {
				say(h, `The hold says "go %d %d %d": %s, so no one sets out.`, at.x, at.y, at.z, no_way(h, why))
				h.place = was
				return
			}
			break
		}
		h.errand += 1
		h.summed = false
		spots_take(h, to)
		say(h, `The hold says "go %d %d %d": the party is sent to %s.`, at.x, at.y, at.z, h.place)
		turn := 0
		for &d in h.dwarves do if ashore(d) {   // each looks for its own way when its turn in the file comes
			clear(&d.path)
			d.doing, d.seek, d.next, d.said = .Walking, true, 0, ""
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
			o.tick = h.tick
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
	w := &h.walk
	fmt.printfln("  the ground read: %d floors in %d rooms of %d chunks, %.1f MB kept", len(w.floors), len(w.rooms), w.made,
		f64(len(w.floors)*(size_of(Floor) + size_of(^Patch) + 16) + len(w.rooms)*size_of(Room) + w.made*size_of(Patch))/1e6)
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
	keys:     [2]bool,
	buttons:  [2]bool,           // the left and right buttons, last frame
	pressed:  [2]f32,            // where the right one went down
	selected: int,               // the dwarf selected, or -1
	send:     bool,              // an order is to be given at the pointer once a block is under it (--send)
	answer:   string,            // what a dwarf last said of itself
	until:    f64,
}
watch := Watch{selected = -1}

// Whether a run was asked only to run the dwarves' world with no window, print what happened and exit.
hold_alone :: proc(opt: ^Options) -> bool {
	return opt.dwarves > 0 && opt.shot == "" && opt.bench == 0 && !opt.show && !opt.has_why && !opt.survey && opt.map_path == ""
}

// Send the party to stand on a block. The one call an order from a cursor needs.
hold_send :: proc(x, y, z: i32) {
	if hold.found do append(&watch.pending, Order{kind = .Go, at = {x, y, z}})
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
//   E             in first person, select the dwarf aimed at, which says who it is
//   left click    from above, on a dwarf: select it, and it says who it is
//   right click   from above: send the party to the block under the pointer (a drag still turns the view)
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
		sync.unlock(&h.mutex)
	}
	if watch.live {
		watch.clock = min(watch.clock + passed, f64(watch.seen.tick + 2)*TICK)   // a hold busy finding a way holds its clock back; it is not hurried after
		sync.atomic_store(&h.target, int(watch.clock/TICK))
		sync.cond_signal(&h.wake)
	}
	// The block an order would send the party to, and how far a dwarf can be picked out.
	target: [3]i32
	aimed, reach := false, AIM_REACH
	if above == nil do target, _, aimed = sight(w, eye, ray, AIM_REACH)
	else if above.shown {
		reach = 4*linalg.length(above.at - eye) + 600
		under := above.under
		if !under.ok do under = pick_far(eye, ray, above_level(above))
		target, aimed = under.block, under.ok
	}
	if watch.send && above != nil && aimed {
		hold_send(target.x, target.y, target.z)
		watch.send = false
	}
	say_card :: proc(h: ^Hold, who: int) {
		hold_select(who)
		if who < 0 do return
		watch.answer, watch.until = dwarf_words(&watch.seen, who), watch.wall + 8
		fmt.println(watch.answer)
	}
	keys := sdl.GetKeyboardState(nil)
	down := [2]bool{keys[int(sdl.Scancode.G)], keys[int(sdl.Scancode.E)]}
	if down[0] && !watch.keys[0] {
		if aimed do hold_send(target.x, target.y, target.z)
		else do fmt.println("no block is aimed at to send the party to")
	}
	if above == nil && down[1] && !watch.keys[1] {
		say_card(h, hold_aimed(w, eye, ray, reach, nil))
		if hold_selected() < 0 do fmt.println("no dwarf is aimed at")
	}
	watch.keys = down
	if above != nil {
		mx, my: f32
		flags := sdl.GetMouseState(&mx, &my)
		buttons := [2]bool{flags & sdl.BUTTON_LMASK != {}, flags & sdl.BUTTON_RMASK != {}}
		if buttons[0] && !watch.buttons[0] && above.shown {
			if who := hold_aimed(w, eye, ray, reach, above); who >= 0 {   // a click on a dwarf is the dwarf's, not the block's behind it
				say_card(h, who)
				mark_clear(above)
			} else do hold_select(-1)
		}
		if buttons[1] && !watch.buttons[1] do watch.pressed = {mx, my}
		if !buttons[1] && watch.buttons[1] && above.shown && aimed && abs(mx - watch.pressed.x) + abs(my - watch.pressed.y) < 4 do hold_send(target.x, target.y, target.z)
		watch.buttons = buttons
	}
}

// What a dwarf last said of itself, for the window's title, while it is fresh.
hold_said :: proc() -> string {
	return watch.answer if watch.wall < watch.until else ""
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
	}
	return
}

// The card as sentences.
dwarf_words :: proc(s: ^Shown, i: int) -> string {
	c := dwarf_card(s, i)
	return fmt.aprintf("%s. %s. %s.", c.who, c.doing, c.next)
}

// ---- for a cursor, a row or a picture (foundations/interface.md, I2 and I4) -----------------------
// hold_send, above, gives the order. These list the dwarves, choose one and lead to it; all are the
// frame thread's, and read what the hold last showed.

// How many dwarves the hold has.
hold_count :: proc() -> int { return len(watch.seen.dwarves) }

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
		dwarf_boxes(&out, d.who, rel(at, eye), watch.turned[i], math.lerp(d.trod, d.stride, a), d.doing == .Walking && d.at != d.was, d.doing == .Aboard)
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
