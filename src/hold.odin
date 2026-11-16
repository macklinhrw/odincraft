package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import sdl "vendor:sdl3"

// The dwarves' world (plan.md, P2; docs/adr/0007). It is a simulation of its own beside the frame:
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
PARTY     :: 7
ROWING    :: 1.4     // metres a second the boat comes in
STEP_OUT  :: 15      // ticks between one dwarf stepping ashore and the next
IN_FILE   :: 8       // ticks between one dwarf setting out and the next, so the party walks in file
ASKING    :: 64      // patches the hold may make to answer one order, before any way is looked for
AIM_REACH :: 160.0   // metres off a block can be aimed at to send the party to it, or a dwarf asked

Doing :: enum u8 { Aboard, Ashore, Walking, Waiting, Stopped }
Dwarf :: struct {
	doing:       Doing,
	cell:        [3]i32,              // the floor it stands on, or is stepping onto
	from:        [3]f64,              // where its feet were when the step began
	into, takes: i32,                 // milliseconds into the step, and how many it takes; none when it stands
	path:        [dynamic][3]i32,     // the floors of its way
	next:        int,                 // the one it steps to next
	wait:        int,                 // ticks before it sets out
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

// What the frame may know: where everyone stood at a tick and at the tick before, and what each was doing.
Seen :: struct {
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
	dwarves:   [PARTY]Seen,
}

Hold :: struct {
	island:   ^Formed,
	walk:     Walk,
	party:    [PARTY]Facts,   // drawn when the hold is made and not changed after, so any thread may read it
	landed:   Landed,
	found:    bool,           // the island has a landing
	boat_from, boat_to: [2]f64,
	boat_ticks: int,
	quiet:    bool,           // say nothing: a test
	// Its own, touched by the thread running it alone.
	tick:     int,
	dwarves:  [PARTY]Dwarf,
	spots:    [PARTY][3]i32,  // where each stands when the errand is done
	errand:   int,            // orders to go obeyed so far; none while the party gathers above the landing
	place:    string,         // where the errand leads, in words
	summed:   bool,           // its end has been said
	orders:   [dynamic]Order, // by tick
	taken:    int,
	log:      [dynamic]string,
	work:     struct { ways, patches: int, walking, finding, worst_tick, worst_way: time.Duration },
	// Shared with the frame thread, under the mutex.
	mutex:    sync.Mutex,
	wake:     sync.Cond,
	inbox:    [dynamic]Order,
	shown:    Shown,
	target:   int,            // the tick the frame's clock has reached (atomic)
	until:    int,            // the tick to stop at
	quit:     bool,
	runner:   ^thread.Thread,
}
hold: Hold   // the player's hold

// ---- making it ------------------------------------------------------------------------------

// Make the hold on an island: draw the party, choose the landing and say both, and read the orders.
hold_make :: proc(h: ^Hold, island: ^Formed, orders: string) {
	started := time.now()
	bound(island)
	h.island = island
	walk_init(&h.walk, island)
	h.party = party_draw(world_seed)
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
	fmt.printfln("the hold: seven dwarves come by boat, their landing chosen in %.0f ms:", time.duration_milliseconds(time.since(started)))
	landing_words(l)
	m := middle_of(land.grid, l.cell)
	c := land_cell(m.x, m.y)
	fmt.printfln("  the boat comes in %.0f m from the %s and grounds at %d, %d, %d; the party gathers at %d, %d, %d, %.0f m from the boat and %.0f m from fresh water",
		math.hypot(h.boat_from.x - h.boat_to.x, h.boat_from.y - h.boat_to.y), compass(l.out.x, l.out.y), l.at.x, l.at.y, l.at.z, l.camp.x, l.camp.y, l.camp.z,
		math.hypot(f64(l.camp.x - l.at.x), f64(l.camp.z - l.at.z)), fresh_water(c))
	fmt.print("  the seven:")
	for f, i in h.party do fmt.printf("%s %s", "" if i == 0 else ";", dwarf_name(f))
	fmt.println()
}

// The party's standing places round a floor.
spots_take :: proc(h: ^Hold, at: [3]i32) {
	h.walk.budget = ASKING
	n := 0
	if f := walk_floor(&h.walk, at.x, at.y, at.z); f >= 0 do n = walk_spots(&h.walk, f, h.spots[:])
	for i in n..<PARTY do h.spots[i] = at   // no room to spread: they crowd
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
		b, out := boat_at(h, h.tick), h.landed.out
		p := b - out*SEATS[i].y + [2]f64{out.y, -out.x}*SEATS[i].x
		return {p.x, SEA_SURFACE + 0.1, p.y}
	}
	if d.takes == 0 do return feet_on(d.cell)
	return math.lerp(d.from, feet_on(d.cell), f64(d.into)/f64(d.takes))
}

// Lay out what the frame may see of the tick in hand.
hold_show :: proc(h: ^Hold) {
	s: Shown
	s.tick, s.errand, s.place, s.grounded = h.tick, h.errand, h.place, h.tick >= h.boat_ticks
	s.boat_was, s.boat = h.shown.boat, boat_at(h, h.tick)
	for &d, i in h.dwarves {
		was := h.shown.dwarves[i]
		s.dwarves[i] = {was = was.at, at = feet_of(h, i), trod = was.stride, stride = d.stride, facing = d.facing, doing = d.doing, left = len(d.path) - d.next, of = len(d.path), said = d.said}
	}
	if h.tick == 0 {
		s.boat_was = s.boat
		for &d in s.dwarves do d.was = d.at
	}
	sync.lock(&h.mutex)
	h.shown = s
	sync.unlock(&h.mutex)
}

// One tick: obey the orders due, bring the boat in, land the party and move every dwarf.
hold_tick :: proc(h: ^Hold) {
	bound(h.island)
	started := time.now()
	found := h.work.finding
	for h.taken < len(h.orders) && h.orders[h.taken].tick <= h.tick {
		obey(h, h.orders[h.taken])
		h.taken += 1
	}
	if h.tick == 0 do say(h, "A boat with seven dwarves stands %.0f m off the shore, to the %s, and pulls for the landing.", math.hypot(h.boat_from.x - h.boat_to.x, h.boat_from.y - h.boat_to.y), compass(h.landed.out.x, h.landed.out.y))
	if h.tick == h.boat_ticks do say(h, "The boat grounds at %d, %d, on %s.", h.landed.at.x, h.landed.at.z, ground_words(h.landed.at)[4:])
	for &d, i in h.dwarves {
		if d.doing == .Aboard && h.tick >= h.boat_ticks + 20 + STEP_OUT*i {   // over the bow, one at a time
			d.from = feet_of(h, i)
			d.doing, d.cell, d.takes, d.into = .Ashore, h.landed.at, 1500, 0
		}
		if d.takes == 0 && d.doing == .Walking {
			if d.wait > 0 do d.wait -= 1
			else if !step_on(h, &d) do arrive(h, i)
		}
		if d.takes == 0 do continue
		d.into += TICK_MS
		for d.takes > 0 && d.into >= d.takes {
			d.into -= d.takes
			d.takes = 0
			if d.doing == .Ashore {
				say(h, "%s, steps ashore.", dwarf_name(h.party[i]))
				send(h, i)
				d.wait = 0
			}
			if d.doing != .Walking do d.into = 0
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
	if h.summed || there + stopped < PARTY do return
	h.summed = true
	if stopped == PARTY do say(h, "None of the seven found a way to %s.", h.place)
	else if stopped > 0 do say(h, "%d of the seven stand at %s; %d found no way.", there, h.place, stopped)
	else if h.errand == 0 do say(h, "The seven stand on the %s, and wait for word.", h.place)
	else do say(h, "All seven stand at %s.", h.place)
}

// Find a dwarf its way to its place in the errand, from the floor it stands on or is stepping
// onto, and set it walking; or say why there is none. With `ask`, a dwarf that finds none is left as it was.
send :: proc(h: ^Hold, i: int, ask := false) -> (seconds: f32, why: Found) {
	d := &h.dwarves[i]
	started := time.now()
	made := h.walk.made
	way := make([dynamic][3]i32, context.temp_allocator)
	seconds, why = walk_way(&h.walk, d.cell, h.spots[i], &way)
	spent := time.since(started)
	h.work.ways += 1
	h.work.finding += spent
	h.work.patches += h.walk.made - made
	h.work.worst_way = max(h.work.worst_way, spent)
	if why == .Way {
		clear(&d.path)
		append(&d.path, ..way[:])
		d.next, d.said, d.doing, d.wait = 1, "", .Walking, i*IN_FILE if d.takes == 0 else 0
	} else if !ask {
		clear(&d.path)
		d.doing, d.said = .Stopped, no_way(h, why)
		say(h, "%s %s stops: %s.", h.party[i].given, h.party[i].byname, d.said)
		errand_sum(h)
	}
	return
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

obey :: proc(h: ^Hold, o: Order) {
	w := &h.walk
	w.budget, w.starved = ASKING, false
	switch o.kind {
	case .Block:
		walk_edit(w, {o.at.x, o.at.y, o.at.z, o.mat})
		say(h, `The hold says "block %d %d %d %v": the ground is changed there.`, o.at.x, o.at.y, o.at.z, o.mat)
		for &d, i in h.dwarves do if d.doing == .Walking do send(h, i)   // a way laid over the old ground may not hold
	case .Go:
		at := o.at
		if o.column do at.y = i32(math.round(ground(f64(at.x - region.origin.x) + 0.5, f64(at.z - region.origin.y) + 0.5, 1).h)) - 1
		f := walk_near(w, at.x, at.y + 1, at.z, 3)
		if f < 0 {
			say(h, `The hold says "go %d %d %d": there is no ground to stand on within three steps of it, so no one sets out.`, at.x, at.y, at.z)
			return
		}
		was_spots, was_place := h.spots, h.place
		to := floor_block(w, f)
		spots_take(h, to)
		h.place = place_say(h, to)
		// Each dwarf ashore looks for its way; those still in the boat follow as they land. If none
		// finds one, the party stays where it is and the order is let go.
		started, made := time.now(), w.made
		sent, floors, longest, last := 0, 0, f32(0), Found.Way
		for &d, i in h.dwarves do if d.doing != .Aboard && d.doing != .Ashore {
			seconds, why := send(h, i, true)
			if why == .Way do sent, floors, longest = sent + 1, max(floors, len(d.path)), max(longest, seconds)
			else do last = why
		}
		if !h.quiet do fmt.printfln("    (%d ways found in %.1f ms, %d patches of ground read for them; the longest %d floors and %.0f s of walking)", sent, time.duration_milliseconds(time.since(started)), w.made - made, floors, longest)
		if sent == 0 && last != .Way {
			say(h, `The hold says "go %d %d %d": %s, so no one sets out.`, at.x, at.y, at.z, no_way(h, last))
			h.spots, h.place = was_spots, was_place
			return
		}
		h.errand += 1
		h.summed = false
		say(h, `The hold says "go %d %d %d": the party is sent to %s.`, at.x, at.y, at.z, h.place)
		for &d, i in h.dwarves do if d.doing != .Aboard && d.doing != .Ashore && (d.doing != .Walking || len(d.path) == 0 || d.path[len(d.path) - 1] != h.spots[i]) {
			d.doing, d.said = .Stopped, no_way(h, last)
			clear(&d.path)
			say(h, "%s %s stops: %s.", h.party[i].given, h.party[i].byname, d.said)
		}
		errand_sum(h)
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
	fmt.printfln("  a tick of seven dwarves took %.1f µs on average and %.1f ms at worst, an order's ways among them; %d ways found, %.2f ms each on average and %.1f ms at worst, %d patches of ground read for them of %d in all",
		time.duration_microseconds(h.work.walking)/f64(h.tick), time.duration_milliseconds(h.work.worst_tick), h.work.ways, time.duration_milliseconds(h.work.finding)/f64(max(h.work.ways, 1)),
		time.duration_milliseconds(h.work.worst_way), h.work.patches, h.walk.made)
	w := &h.walk
	fmt.printfln("  the ground read: %d floors in %d rooms of %d chunks, %.1f MB kept", len(w.floors), len(w.rooms), w.made,
		f64(len(w.floors)*(size_of(Floor) + size_of(^Patch) + 16) + len(w.rooms)*size_of(Room) + w.made*size_of(Patch))/1e6)
}

// ---- beside the frame -------------------------------------------------------------------------

// The frame thread's own view of the hold.
Watch :: struct {
	live:    bool,              // the hold runs beside the frame; a picture is of one moment
	clock:   f64,               // seconds of the dwarves' world the frames have shown
	wall:    f64,
	seen:    Shown,
	feet:    [PARTY][3]f64,     // where each dwarf was last drawn
	turned:  [PARTY]f32,        // and which way, eased
	drawn:   bool,
	pending: [dynamic]Order,    // orders not yet handed over
	keys:    [2]bool,
	selected: int,              // the dwarf selected, or -1
	answer:  string,            // what a dwarf last said of itself
	until:   f64,
}
watch := Watch{selected = -1}

// Whether a run was asked only to run the dwarves' world with no window, print what happened and exit.
hold_alone :: proc(opt: ^Options) -> bool {
	return opt.dwarves > 0 && opt.shot == "" && opt.bench == 0 && !opt.show && !opt.has_why && !opt.survey && opt.map_path == ""
}

// Send the party to stand on a block. The one call an order from a cursor needs.
hold_send :: proc(x, y, z: i32) {
	append(&watch.pending, Order{kind = .Go, at = {x, y, z}})
}

// Tell the hold a block was changed (world_set).
hold_block :: proc(x, y, z: i32, m: Mat) {
	if hold.found do append(&watch.pending, Order{kind = .Block, at = {x, y, z}, mat = m})
}

// The window is up: put the player where the landing can be watched, and set the hold going.
hold_enter :: proc(p: ^Player, opt: ^Options) {
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
	watch.seen, watch.clock = h.shown, f64(h.tick)*TICK
	watch.live = opt.shot == "" || opt.bench > 0
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

// Each frame: hand over orders, take what the hold shows, move its clock on, and answer the keys.
// G sends the party to the block aimed at; E selects the dwarf aimed at, which says who it is and what it is doing.
hold_frame :: proc(w: ^World, eye: [3]f64, look: [3]f32, dt: f64) {
	h := &hold
	if !h.found do return
	watch.wall += dt
	// The lock is only tried, as the world's is: the hold has it for moments, but a frame must not wait on a thread held off the processor.
	if sync.try_lock(&h.mutex) {
		watch.seen = h.shown
		if watch.live {
			append(&h.inbox, ..watch.pending[:])
			clear(&watch.pending)
		}
		sync.unlock(&h.mutex)
	}
	if watch.live {
		watch.clock = min(watch.clock + dt, f64(watch.seen.tick + 2)*TICK)   // a hold busy finding a way holds its clock back; it is not hurried after
		sync.atomic_store(&h.target, int(watch.clock/TICK))
		sync.cond_signal(&h.wake)
	}
	keys := sdl.GetKeyboardState(nil)
	down := [2]bool{keys[int(sdl.Scancode.G)], keys[int(sdl.Scancode.E)]}
	if down[0] && !watch.keys[0] {
		if hit, _, ok := sight(w, eye, look, AIM_REACH); ok do hold_send(hit.x, hit.y, hit.z)
		else do fmt.printfln("no block within %.0f m to send the party to", AIM_REACH)
	}
	if down[1] && !watch.keys[1] {
		hold_select(hold_aimed(w, eye, look, AIM_REACH))
		if who := hold_selected(); who >= 0 {
			watch.answer, watch.until = dwarf_words(h, who, watch.seen), watch.wall + 8
			fmt.println(watch.answer)
		} else do fmt.println("no dwarf is aimed at")
	}
	watch.keys = down
}

// What a dwarf last said of itself, for the window's title, while it is fresh.
hold_said :: proc() -> string {
	return watch.answer if watch.wall < watch.until else ""
}

// What a dwarf says of itself, in the shape of the card the interface shows for the thing selected
// (foundations/interface.md, I2, I3 and I8): who it is; what it is doing, and why; and what it will
// do next or what it waits for, empty when there is nothing to say. Each line leads with its point
// and keeps figures behind words. --why and the key E print these lines; a panel will draw them.
Card :: struct { who, doing, next: string }

dwarf_card :: proc(h: ^Hold, i: int, s: Shown) -> (c: Card) {
	f, d := h.party[i], s.dwarves[i]
	c.who = fmt.tprintf("%s, who %s", dwarf_name(f), TRADES[f.trade].does)
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
dwarf_words :: proc(h: ^Hold, i: int, s: Shown) -> string {
	c := dwarf_card(h, i, s)
	return fmt.aprintf("%s. %s. %s.", c.who, c.doing, c.next)
}

// ---- for a cursor, a row or a picture (foundations/interface.md, I2 and I4) -----------------------
// hold_send, above, gives the order. These choose a dwarf and lead to it; all are the frame thread's.

// Select a dwarf, or none with -1. The card of the one selected is hold_card's.
hold_select :: proc(i: int) { watch.selected = i if i >= 0 && i < PARTY && hold.found else -1 }

hold_selected :: proc() -> int { return watch.selected }

// A dwarf's card, from what the hold last showed.
hold_card :: proc(i: int) -> Card { return dwarf_card(&hold, i, watch.seen) }

// Where a dwarf's feet are, as last drawn, for the view to go to.
hold_where :: proc(i: int) -> (at: [3]f64, ok: bool) {
	if !hold.found || i < 0 || i >= PARTY do return
	return watch.feet[i] if watch.drawn else watch.seen.dwarves[i].at, true
}

// The dwarf a ray from the eye meets first within a reach, before any block, or -1.
hold_aimed :: proc(w: ^World, eye: [3]f64, look: [3]f32, reach: f64) -> (who: int) {
	who = -1
	near := reach
	for f, i in hold.party {   // the ray against each dwarf's box
		lo, hi := watch.feet[i] - {0.3, 0, 0.3}, watch.feet[i] + {0.3, f64(f.tall), 0.3}
		t0, t1 := 0.0, near
		for a in 0..<3 {
			d := f64(look[a])
			if abs(d) < 1e-9 {
				if eye[a] < lo[a] || eye[a] > hi[a] do t1 = -1
				continue
			}
			a0, a1 := (lo[a] - eye[a])/d, (hi[a] - eye[a])/d
			t0, t1 = max(t0, min(a0, a1)), min(t1, max(a0, a1))
		}
		if t0 <= t1 do who, near = i, t0
	}
	if _, far, ok := sight(w, eye, look, near); ok && far < near do who = -1   // behind a block
	return
}

// The boat and the dwarves as boxes after the creatures', from the eye.
hold_pose :: proc(boxes: []Box, eye: [3]f64, dt: f64) -> []Box {
	h := &hold
	if !h.found do return boxes
	out := make([dynamic]Box, 0, len(boxes) + 16*PARTY, context.temp_allocator)
	append(&out, ..boxes)
	s := watch.seen
	a := clamp((watch.clock - f64(s.tick)*TICK)/TICK, 0, 1) if watch.live else 1
	rel :: proc(p, eye: [3]f64) -> [3]f32 { return {f32(p.x - eye.x), f32(p.y - eye.y), f32(p.z - eye.z)} }
	boat := math.lerp(s.boat_was, s.boat, a)
	toward := f32(math.atan2(-h.landed.out.x, h.landed.out.y))
	if math.hypot(boat.x - eye.x, boat.y - eye.z) < 1500 {
		bob := 0.0 if s.grounded else 0.04*math.sin(watch.wall*1.7)
		boat_boxes(&out, rel({boat.x, SEA_SURFACE + 0.04 + bob, boat.y}, eye), toward)
	}
	for f, i in h.party {
		d := s.dwarves[i]
		at := math.lerp(d.was, d.at, a)
		watch.feet[i] = at
		turn := math.mod(d.facing - watch.turned[i] + 3*math.PI, math.TAU) - math.PI   // the short way round
		watch.turned[i] = d.facing if !watch.drawn || !watch.live else watch.turned[i] + turn*f32(min(10*dt, 1))
		if math.hypot(at.x - eye.x, at.z - eye.z) > 1500 do continue
		dwarf_boxes(&out, f, rel(at, eye), watch.turned[i], math.lerp(d.trod, d.stride, a), d.doing == .Walking && d.at != d.was, d.doing == .Aboard)
	}
	watch.drawn = true
	return out[:]
}

// The landing and any dwarf standing at a point, as --why says them.
hold_words :: proc(x, z: f64) {
	h := &hold
	if !h.found || here != h.island do return
	wx, wz := x + f64(region.origin.x), z + f64(region.origin.y)
	l := h.landed
	if d := math.hypot(wx - f64(l.at.x) - 0.5, wz - f64(l.at.z) - 0.5); d < 60 {
		fmt.printfln("the dwarves' landing is %.0f m off:", d)
		landing_words(l)
	}
	for _, i in h.party do if at := h.shown.dwarves[i].at; math.hypot(wx - at.x, wz - at.z) < 3 {
		c := dwarf_card(h, i, h.shown)
		fmt.printfln("a dwarf stands here, %d:%02d after the boat stood off: %s.\n  %s.\n  %s.", h.tick/600, h.tick/10%60, c.who, c.doing, c.next)
	}
}
