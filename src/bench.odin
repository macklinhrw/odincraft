package main

import "base:builtin"
import "core:fmt"
import "core:strings"

// Making one thing of another (plan.md, "Winter's food"; docs/adr/0016). It is two tables.
//
//   MAKES    what is made of what: a row names what goes in, what comes of it, how many of the one
//            make how many of the other, the bench it is made at, and how long it stands there.
//   BENCHES  the things something is made at: a row names how one is ordered and built, how much
//            it holds, and what speeds or stops what stands on it.
//
// A bench is a thing in a cell, as a fire is (shelter.odin): the player places it with Build, a
// dwarf builds it of what is brought, and from then on dwarves with nothing more pressing bring it
// what it makes something of, the nearest of what will spoil soonest, and take off what it has
// made, to a stockpile that takes it or, with none, to the bench's foot. Nothing is counted while
// it stands on a bench: the hold has what lies in its stockpiles (docs/adr/0012).
//
// The first bench is the drying rack, and the first things made are food that keeps: fish and
// shoots dried in sun and wind, or over the smoke of a fire that burns beside the rack, which is
// twice as fast and goes on in the rain. That is the oldest way there is, and the way of the islands
// the flora is taken from: small fish are dried whole on raised racks, river fish are grilled and
// dried over the hearth (yakiboshi), and mountain shoots are boiled, dried in the sun and kept for
// the winter (colony-sim-reference.md, section 16, with what that rests on). A nut needs no rack.
//
// RimWorld's nearest thing is its fermenting barrel (Building_FermentingBarrel): 25 wort are
// brought to it by haulers without being asked, it stands six days, slower under 7 °C, and the beer
// is taken out; and its pemmican, a meal that keeps 70 days, made at a stove by a bill. Ingnomia
// smokes fish in its kitchen, a fish and a log for a smoked fish (table Crafts). Dwarf Fortress
// keeps food by where it lies: in a stockpile and a barrel it does not rot.
//
// P5's workshops are more rows of both tables: a bench a dwarf stands at, and a row of MAKES that
// takes its hands' seconds instead of days of standing.
//
// An orders file gives one as a line (hold.odin has the rest):
//   build rack timber x y z x y z   a rack in each place a dwarf could stand in the box's columns
//   rack load|leave x y z x y z     the rack on that block is kept loaded, or left to stand empty
// and `unmark` over a rack takes it down.

Bench_Kind :: enum u8 { Rack }
Bench_Row :: struct {
	name:  string,
	plan:  Plan,     // the choice of Build that orders it
	stuff: Stuff,    // what it is built of: one thing
	build: f32,      // seconds a common hand takes to build it
	holds: i32,      // things that stand on it at once
	sun:   bool,     // it works by sun and wind: rain falling on it stops it
	fire:  f32,      // and it goes so many times as fast where a fire burns beside it, rain or none
	says:  string,
}
// RimWorld's barrel is 30 wood and 10 steel and ten seconds of work, and holds 25. A rack here is a
// log split into poles, as a fire is a log, and holds a basket: what one cell holds of food lying.
BENCHES := [Bench_Kind]Bench_Row{
	.Rack = {"drying rack", .Rack, .Timber, 8, BASKET, true, 2,
		"A rack of poles. Fresh fish and shoots are brought to it and dry on it in sun and wind; over the smoke of a fire beside it they dry twice as fast, and in the rain. What is dried does not spoil."},
}

Make :: struct {
	of, gives: Mat,
	n:         [2]i32,       // so many of what goes in make so many of what comes of it
	at:        Bench_Kind,
	days:      f32,          // days it stands there, at the bench's own pace
}
// A small fish dries in a day or two of sun, a larger one opened in two or three, and boiled shoots
// in two to four with turning (from memory; the sources read give the way and not the days). The
// thick shoots of bamboo take longest. One thing dried is one thing kept: it feeds as it did.
MAKES := [?]Make{
	{.Goby,           .Dried_Goby,      {1, 1}, .Rack, 1.5},
	{.Ayu,            .Dried_Ayu,       {1, 1}, .Rack, 2},
	{.Bracken_Shoots, .Dried_Bracken,   {1, 1}, .Rack, 2},
	{.Itadori_Shoots, .Dried_Itadori,   {1, 1}, .Rack, 2},
	{.Bamboo_Shoots,  .Dried_Bamboo,    {1, 1}, .Rack, 3},
	{.Wild_Rice,      .Dried_Wild_Rice, {1, 1}, .Rack, 2},
}
BENCH_EVERY :: 100   // ticks between two looks at what stands on the benches

Bench :: struct {
	at:     [3]i32,   // the cell it stands in: the one a dwarf's feet would be in
	kind:   Bench_Kind,
	of:     Mat,      // what it was built of, which lies there when it is taken down
	make:   int,      // the row of MAKES in hand, or -1 with nothing on it and nothing coming
	n:      i32,      // things on it: of what goes in or, once done, of what came of it
	done:   bool,
	share:  f32,      // how far what is on it has come, from 0 to 1
	used:   bool,     // it is kept loaded: the player may let it stand empty
	coming: i32,      // things on their way to it,
	going:  i32,      // and of what it has made, things dwarves are on their way to take off
	roof, by_fire, rained: bool,   // as it stood when last looked at
}
Bench_Seen :: struct {
	at:    [3]i32,
	kind:  Bench_Kind,
	make:  int,
	n:     i32,
	done, used, roof, by_fire, rained: bool,
	share: f32,
}

// The row of MAKES that makes something of a kind at a bench, or -1.
make_of :: proc(kind: Mat, at: Bench_Kind) -> int {
	for row, k in MAKES do if row.of == kind && row.at == at do return k
	return -1
}

// The bench a choice of Build orders.
bench_of :: proc(plan: Plan) -> (kind: Bench_Kind, ok: bool) {
	for row, k in BENCHES do if row.plan == plan do return k, true
	return
}

// How fast what stands on a bench comes on, of its row's own pace.
bench_pace :: proc(row: ^Bench_Row, by_fire, rained: bool) -> f32 {
	if by_fire && row.fire > 0 do return 1 if rained else row.fire
	return 0 if rained && row.sun else 1
}

// A bench is built in a cell, of the thing brought to it.
bench_make :: proc(h: ^Hold, at: [3]i32, kind: Bench_Kind, of: Mat) {
	h.benched[at] = len(h.benches)
	append(&h.benches, Bench{at = at, kind = kind, of = of, make = -1, used = true})
	bench_look(h, len(h.benches) - 1)
	h.benches_v += 1
	for &d in h.dwarves do if !d.job && !d.haul.on do d.rest = min(d.rest, 2)
}

// What stands over a bench, falls on it and burns beside it.
bench_look :: proc(h: ^Hold, k: int) {
	b := &h.benches[k]
	was := [3]bool{b.roof, b.by_fire, b.rained}
	b.roof = roofed(hold_blocks(h), b.at)
	b.rained = !b.roof && weather(f64(h.tick)*TICK, stand_of(b.at)).rain > 0
	b.by_fire = fire_near(h, b.at) >= 0
	if was != ([3]bool{b.roof, b.by_fire, b.rained}) do h.benches_v += 1
}

// Every BENCH_EVERY ticks: what stands on each bench comes on at the bench's pace, and what is done
// is said, all that came done together in one line.
benches_tick :: proc(h: ^Hold) {
	if h.tick%BENCH_EVERY != 0 || len(h.benches) == 0 do return
	done: [len(MAKES)]int
	benches, at := 0, [3]i32{}
	for &b, k in h.benches {
		bench_look(h, k)
		if b.make < 0 || b.done || b.n <= 0 do continue
		row, make := &BENCHES[b.kind], MAKES[b.make]
		b.share += bench_pace(row, b.by_fire, b.rained)*BENCH_EVERY*TICK/DAY/make.days
		h.benches_v += 1
		if b.share < 1 do continue
		b.share, b.done = 1, true
		b.n = b.n*make.n[1]/make.n[0]
		done[b.make] += int(b.n)
		benches, at = benches + 1, b.at
	}
	if benches == 0 do return
	text := strings.builder_make(context.temp_allocator)
	kinds, said := 0, 0
	for count in done do kinds += int(count > 0)
	for count, k in done do if count > 0 {
		fmt.sbprintf(&text, "%s%d of %s", "" if said == 0 else " and " if said == kinds - 1 else ", ", count, store_words(MAKES[k].of))
		said += 1
	}
	h.at = feet_on(at)
	name := BENCHES[h.benches[h.benched[at]].kind].name
	today := date_tick(h.tick).day
	h.aside = h.dried && h.dried_on == today   // on the screen once a day: after that the log has it, and the racks show what is done
	h.dried, h.dried_on = true, today
	h.short = fmt.tprintf("Dried on the racks: %s. They will keep.", strings.to_string(text))
	say(h, "%s at %s %s done: %s are dried, and will keep. They are taken off to a stockpile that takes food.", fmt.tprintf("The %s", name) if benches == 1 else fmt.tprintf("%s %ss", capital(count_words(benches)), name), place_say(h, at),
		"is" if benches == 1 else "are", strings.to_string(text))
	for &d in h.dwarves do if !d.job && !d.haul.on do d.rest = min(d.rest, 2)
}

// A dwarf with nothing more pressing brings a bench what it makes something of: an armful of the
// heap that will spoil soonest, the nearer the bench of two as near their end, wherever it lies.
// A bench with something on it takes only more of the same. False if no bench has room, nothing
// lies that one takes, or no way leads.
bench_load :: proc(h: ^Hold, i: int) -> bool {
	w := &h.walk
	for &b in h.benches {
		row := &BENCHES[b.kind]
		room := row.holds - b.n - b.coming
		if !b.used || b.done || room <= 0 do continue
		best, pick, make := f32(1e9), -1, -1
		for g, j in h.goods do if g.n - g.held > 0 && (g.tried == 0 || h.tick - g.tried >= RETRY) {
			k := make_of(g.kind, b.kind)
			if k < 0 || b.make >= 0 && k != b.make do continue
			if score := max(g.left, 0)*40 + f32(far_of(g.at, b.at)); score < best do best, pick, make = score, j, k
		}
		if pick < 0 do continue
		w.budget = ASKING
		stand := walk_near(w, b.at.x, b.at.y, b.at.z, 2, false, &h.benched)
		if stand < 0 do continue
		g := &h.goods[pick]
		n := min(room, armful_of(g.kind), g.n - g.held)
		if !haul_set(h, i, {on = true, from = g.at, to = floor_block(w, stand), kind = g.kind, n = n, site = -1, bench = true, hearth = b.at}) {
			g.tried = h.tick   // no way to it: it is left a while, as a mark is that no dwarf found a way to
			return false
		}
		g.held += n
		b.coming += n
		b.make = make
		return true
	}
	return false
}

// A dwarf with nothing more pressing takes off a bench what it has made: an armful, to the nearest
// place of a stockpile that takes it or, with none, down at the bench's foot.
bench_unload :: proc(h: ^Hold, i: int) -> bool {
	w := &h.walk
	for &b in h.benches {
		if !b.done || b.n - b.going <= 0 do continue
		kind := MAKES[b.make].gives
		w.budget = ASKING
		stand := walk_near(w, b.at.x, b.at.y, b.at.z, 2, false, &h.benched)
		if stand < 0 do continue
		from := floor_block(w, stand)
		n := min(b.n - b.going, armful_of(kind))
		to, room, stores := store_cell(h, Good{at = b.at, kind = kind})
		if stores do n = min(n, room)
		else do to = from
		if !haul_set(h, i, {on = true, from = from, to = to, kind = kind, n = n, site = -1, bench = true, off = true, hearth = b.at}) do continue
		b.going += n
		if stores {
			cell := &h.zoned[to]
			cell.coming += n
		}
		return true
	}
	return false
}

// A dwarf has come to a bench with what it makes something of: it is laid on. What is half done
// goes back by the share of the new things among all, as RimWorld's barrel does when wort is added
// (Building_FermentingBarrel.AddWort). It takes what it has room for, and none if it is gone, is
// done, or holds something else: how many it took.
bench_put :: proc(h: ^Hold, at: [3]i32, kind: Mat, n: i32) -> (took: i32) {
	k, ok := h.benched[at]
	if !ok do return
	b := &h.benches[k]
	b.coming = max(b.coming - n, 0)
	make := make_of(kind, b.kind)
	took = min(n, BENCHES[b.kind].holds - b.n)
	if b.done || make < 0 || b.n > 0 && make != b.make || took <= 0 {
		if b.n == 0 && b.coming == 0 do b.make = -1
		return 0
	}
	b.share = b.share*f32(b.n)/f32(b.n + took)
	b.n, b.make = b.n + took, make
	h.benches_v += 1
	return
}

// A dwarf has come to a bench to take off what it made: how many it took. The bench is empty with its last.
bench_take :: proc(h: ^Hold, at: [3]i32, n: i32) -> (got: i32) {
	k, ok := h.benched[at]
	if !ok do return
	b := &h.benches[k]
	b.going = max(b.going - n, 0)
	if !b.done do return
	got = min(n, b.n)
	b.n -= got
	if b.n == 0 do b.done, b.share, b.make = false, 0, -1
	h.benches_v += 1
	return
}

// Things promised to a bench, or of it to a dwarf, are promised no longer.
bench_unpromise :: proc(h: ^Hold, at: [3]i32, n: i32, off := false) {
	k, ok := h.benched[at]
	if !ok do return
	b := &h.benches[k]
	if off do b.going = max(b.going - n, 0)
	else {
		b.coming = max(b.coming - n, 0)
		if b.n == 0 && b.coming == 0 do b.make = -1
	}
}

// A bench is to be kept loaded, or left to stand empty.
bench_tend :: proc(h: ^Hold, o: Order) {
	at := o.at + {0, 1, 0}
	h.at = feet_on(at)
	k, ok := h.benched[at]
	if !ok {
		h.short = "No rack there."
		say(h, `The hold says "%s": no rack stands there.`, order_words(o))
		return
	}
	b := &h.benches[k]
	b.used = o.on
	h.benches_v += 1
	name := BENCHES[b.kind].name
	h.short = fmt.tprintf("The %s is kept loaded.", name) if o.on else fmt.tprintf("The %s is left to stand empty.", name)
	say(h, `The hold says "%s": the %s at %s is %s.`, order_words(o), name, place_say(h, at), "kept loaded from now" if o.on else "loaded no more: what is on it is finished and taken off, and nothing more is brought")
	for &d in h.dwarves do if !d.job && !d.haul.on do d.rest = min(d.rest, 2)
}

// The benches in a box's columns are taken down: how many went. What stood on each, and what it was built of, lie there.
benches_remove :: proc(h: ^Hold, lo, hi: [3]i32) -> (gone: int) {
	for k := len(h.benches) - 1; k >= 0; k -= 1 do if b := h.benches[k]; b.at.x >= lo.x && b.at.x <= hi.x && b.at.z >= lo.z && b.at.z <= hi.z {
		delete_key(&h.benched, b.at)
		last := len(h.benches) - 1
		if k != last {
			h.benches[k] = h.benches[last]
			h.benched[h.benches[k].at] = k
		}
		pop(&h.benches)
		if b.n > 0 do good_put(h, b.at, MAKES[b.make].gives if b.done else MAKES[b.make].of, b.n)
		good_put(h, b.at, b.of, 1)
		gone += 1
	}
	if gone > 0 do h.benches_v += 1
	return
}

// A block changed: a bench whose ground was dug away comes down with it, and one a block was laid in is taken down.
benches_settle :: proc(h: ^Hold, at: [3]i32, mat: Mat) {
	c := at + {0, 1, 0} if mat == .Air else at
	k, ok := h.benched[c]
	if !ok do return
	if mat != .Air {
		benches_remove(h, c, c)
		return
	}
	b := &h.benches[k]
	delete_key(&h.benched, c)
	for _ in 0..<64 {
		if under, _ := walk_block(&h.walk, b.at - {0, 1, 0}); under != .Air && !is(under, LEAVES) do break
		b.at.y -= 1
	}
	h.benched[b.at] = k
	h.benches_v += 1
}

// Lay out the benches for the frame. Called with the hold's mutex held.
benches_show :: proc(h: ^Hold) {
	s := &h.shown
	if h.benches_shown == h.benches_v && len(s.benches) == len(h.benches) do return
	h.benches_shown = h.benches_v
	builtin.resize(&s.benches, len(h.benches))
	for b, k in h.benches do s.benches[k] = {b.at, b.kind, b.make, b.n, b.done, b.used, b.roof, b.by_fire, b.rained, b.share}
}

// How a bench stands, in a sentence for its card and the run's summary: what is on it and how long until it is done.
bench_words :: proc(b: Bench_Seen) -> string {
	row := &BENCHES[b.kind]
	if b.make < 0 || b.n == 0 do return "Empty." if b.used else "Empty: it is left to stand so."
	make := MAKES[b.make]
	if b.done do return fmt.tprintf("Done: %d %s, to be taken off.", b.n, store_words(make.gives))
	pace := bench_pace(row, b.by_fire, b.rained)
	if pace <= 0 do return fmt.tprintf("%d %s, %d%% dry: standing still in the rain.", b.n, store_words(make.of), int(b.share*100))
	return fmt.tprintf("%d %s, drying: done in %s.", b.n, store_words(make.of), fuel_days_words((1 - b.share)*make.days/pace))
}

// A length of time in words, to the hour under half a day: "about five hours", "a day and a half".
fuel_days_words :: proc(days: f32) -> string {
	return "under an hour" if days < 1.0/24 else fmt.tprintf("about %s hours", count_words(int(days*24 + 0.5))) if days < 0.45 else days_words(days)
}
