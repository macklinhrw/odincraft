package main

import "core:fmt"
import fnv "core:hash"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"

// The dwarves' world is deterministic (docs/adr/0009): the same seed and orders give the same log,
// run alone or beside a thread that reads it and moves its clock as the frame does. The test plays
// a game on the default world a stretch at a time, giving each order from what the hold has come to,
// as a player does; then plays the orders it gave again from a file, alone and beside a reader, and
// compares the three logs. It keeps no golden hash: what the dwarves do follows the land, which
// changes on purpose.
//
// The game played is the one the blocks can spoil (plan.md, "P2, as built", the two faults): the
// ground is taken from under a dwarf that stands and from under one that walks, a block is laid
// where one stands, and the seven are sent to the far end of a passage one block wide and then to
// its mouth, so that those deepest in must pass the rest. Every dwarf must still stand on a floor of
// its own and obey. The orders are left in build/hold_test_orders.txt, and run with no window by
//   build/odincraft --dwarves=3600 --orders=build/hold_test_orders.txt
// The last stage is the orders' (plan.md, P3): a room is dug into the nearest hillside, roofed and
// walled, and the party sent in under the roof; the blocks the dwarves changed and the store must
// come out the same each time, as the log does.

// Called by the forming test once the start island is formed and bound.
dwarves_world_is_deterministic :: proc(t: ^testing.T) {
	played, alone, beside := new(Hold), new(Hold), new(Hold)
	played.quiet, alone.quiet, beside.quiet = true, true, true
	hold_make(played, home, "")
	if !testing.expect(t, played.found, "the default island has a landing") do return
	w := &played.walk
	text := strings.builder_make()
	strings.write_string(&text, "# written by hold_test.odin\n")
	order :: proc(t: ^testing.T, h: ^Hold, text: ^strings.Builder, seconds: int, format: string, args: ..any) {
		line := fmt.tprintf("%d %s", seconds, fmt.tprintf(format, ..args))
		fmt.sbprintln(text, line)
		testing.expect(t, order_read(h, line), line)
	}
	said :: proc(h: ^Hold, part: string) -> (n: int) {
		for line in h.log do n += int(strings.contains(line, part))
		return
	}

	// The ground goes from under a dwarf that stands, three blocks of it, and a block is laid where another stands.
	hold_run(played, 130)
	stood, filled := played.dwarves[0].cell, played.dwarves[1].cell
	for down in ([3]i32{3, 2, 1}) do order(t, played, &text, 130, "block %d %d %d Air", stood.x, stood.y - down, stood.z)
	order(t, played, &text, 135, "block %d %d %d Sandstone", filled.x, filled.y, filled.z)
	// The party is sent a few steps off, and the ground goes from under the last to set out as it walks.
	camp := played.landed.camp
	order(t, played, &text, 150, "go %d %d", camp.x + 12, camp.z + 9)
	hold_run(played, 158)
	testing.expect_value(t, played.dwarves[0].cell, [3]i32{stood.x, stood.y - 3, stood.z})
	testing.expect(t, played.dwarves[1].cell != filled, "a dwarf is moved out of a block laid where it stood")
	walker := -1
	for d, i in played.dwarves do if d.doing == .Walking && d.takes > 0 do walker = i
	under: [3]i32
	if testing.expect(t, walker >= 0, "a dwarf is walking 8 s after the order") {
		under = played.dwarves[walker].cell
		for down in ([2]i32{2, 1}) do order(t, played, &text, 158, "block %d %d %d Air", under.x, under.y - down, under.z)
	}
	// To the open sea, which has no ground: no one sets out. The two in their pits take the order and say they have no way.
	out := [2]i32{i32(played.landed.out.x*300), i32(played.landed.out.y*300)}
	order(t, played, &text, 240, "go %d %d", camp.x + out.x, camp.z + out.y)
	hold_run(played, 245)
	testing.expect_value(t, said(played, "falls"), 2)
	testing.expect_value(t, said(played, "stops: no way leads"), 2)
	testing.expect_value(t, said(played, "5 of the seven stand"), 1)
	// The pits are filled again under them, which lifts each out a block at a time.
	for down in ([3]i32{3, 2, 1}) do order(t, played, &text, 245, "block %d %d %d Sandstone", stood.x, stood.y - down, stood.z)
	for down in ([2]i32{2, 1}) do order(t, played, &text, 245, "block %d %d %d Sandstone", under.x, under.y - down, under.z)
	hold_run(played, 250)
	testing.expect_value(t, said(played, "is in the way of a block"), 6)

	// A passage one block wide and nine long, shut at its east end, walled with blocks on the nearest
	// level ground: the seven are sent to its end, and then to its mouth.
	LONG :: 9
	top :: proc(w: ^Walk, x, z: i32) -> (y: i32, ok: bool) {   // the one floor of a column of open, dry ground
		f := walk_top(w, x, z) or_return
		p := w.owner[f]
		col := (z & (CHUNK - 1))*CHUNK + x & (CHUNK - 1)
		return i32(w.floors[f].y), p.first[col + 1] - p.first[col] == 1 && w.floors[f].wet == 0
	}
	at: [3]i32
	found := false
	w.budget = 64
	search: for r in i32(4)..<40 do for dz in -r..=r do for dx in -r..=r {
		if max(abs(dx), abs(dz)) != r do continue
		x0, z := camp.x + dx, camp.z + dz
		lo, hi, good := max(i32), min(i32), true
		for k in i32(-2)..=LONG do for side in i32(-1)..=1 {
			y, ok := top(w, x0 + k, z + side)
			good &&= ok
			lo, hi = min(lo, y), max(hi, y)
		}
		for d in played.dwarves do good &&= abs(d.cell.x - x0 - LONG/2) > LONG || abs(d.cell.z - z) > 3
		if good && hi - lo <= 1 {
			at, found = {x0, hi, z}, true
			break search
		}
	}
	if testing.expect(t, found, "level open ground for a passage lies within 40 m of the camp") {
		wall :: proc(t: ^testing.T, h: ^Hold, text: ^strings.Builder, x, z, upto: i32) {
			y, _ := top(&h.walk, x, z)
			for b in y..=upto do order(t, h, text, 250, "block %d %d %d Sandstone", x, b, z)
		}
		for k in i32(0)..<LONG do for side in ([2]i32{-1, 1}) do wall(t, played, &text, at.x + k, at.z + side, at.y + 1)
		for side in i32(-1)..=1 do wall(t, played, &text, at.x + LONG, at.z + side, at.y + 1)
		end, _ := top(w, at.x + LONG - 1, at.z)
		mouth, _ := top(w, at.x, at.z)
		order(t, played, &text, 260, "go %d %d %d", at.x + LONG - 1, end - 1, at.z)
		seconds := 270
		for hold_run(played, f64(seconds)); seconds < 600 && !played.summed; {
			seconds += 10
			hold_run(played, f64(seconds))
		}
		inside := 0
		for d in played.dwarves do inside += int(d.cell.z == at.z && d.cell.x >= at.x && d.cell.x < at.x + LONG)
		testing.expect(t, inside >= 4, "at least four of the seven stand in the passage")
		squeezed := played.work.squeezed
		order(t, played, &text, seconds, "go %d %d %d", at.x, mouth - 1, at.z)
		seconds += 10
		for hold_run(played, f64(seconds)); seconds < 900 && !played.summed; {
			seconds += 10
			hold_run(played, f64(seconds))
		}
		testing.expect(t, played.work.squeezed == squeezed, "dwarves held each other up in the passage, where they should go by")
		fmt.printfln("the passage runs east from %d, %d, %d: %d stood in it, and they went by each other on the way back", at.x, at.y, at.z, inside)
	}
	hold_run(played, 900)
	testing.expect(t, played.summed, "the last errand ends")

	// Orders (plan.md, P3): a room dug into the nearest hillside, its trees felled first, then roofed
	// where it lies open and walled across its front but for a door, of what the work put in store.
	now := 900
	run_until :: proc(h: ^Hold, now: ^int, limit: int, done: proc(h: ^Hold) -> bool) {
		for {
			now^ += 20
			hold_run(h, f64(now^))
			if now^ >= limit || done(h) do break
		}
	}
	idle :: proc(h: ^Hold) -> bool {   // every order is done, or waits on something no dwarf is doing
		for d in h.dwarves do if d.job || d.haul.on do return false
		for m in h.marks do if m.wait == .None || m.wait == .No_Stuff do return false   // a block whose stuff is still to be brought is not done with
		for id in 0..<len(h.sites) do if h.sites[id].coming > 0 do return false
		return true
	}
	if room, ok := hillside(played); testing.expect(t, ok, "a hillside to dig a room into lies within 120 m of the camp") {
		lo, hi, floor := room.lo, room.hi, room.floor
		order(t, played, &text, now, "fell %d %d %d %d %d %d", lo.x - 2, floor, lo.z - 2, hi.x + 2, floor, hi.z + 2)
		// And the trees of the nearest wood, for timber.
		trees := make([dynamic]Tree, context.temp_allocator)
		ox, oz := region.origin.x, region.origin.y
		trees_in(lo.x - 40 - ox, lo.z - 40 - oz, hi.x + 40 - ox, hi.z + 40 - oz, &trees)
		wood, far := Tree{}, max(i32)
		for tree in trees do if d := abs(tree.x + ox - lo.x) + abs(tree.z + oz - lo.z); tree.form == .Canopy && tree.kind != .Scrub && tree.height >= 8 && d < far do wood, far = tree, d
		if testing.expect(t, far < max(i32), "a tree of the canopy stands within 40 m of the room") {
			order(t, played, &text, now, "fell %d %d %d %d %d %d", wood.x + ox - 8, wood.base, wood.z + oz - 8, wood.x + ox + 8, wood.base, wood.z + oz + 8)
		}
		order(t, played, &text, now, "dig out %d %d %d %d %d %d", lo.x, floor, lo.z, hi.x, floor + 1, hi.z)
		// A stockpile on the open ground before the door: what is dug is carried to it, and counted.
		yard := [2][2]i32{room.front - room.into*4 - room.across, room.front - room.into*2 + room.across*5}
		order(t, played, &text, now, "store all %d %d %d %d %d %d", yard[0].x, floor - 1, yard[0].y, yard[1].x, floor - 1, yard[1].y)
		run_until(played, &now, 6000, idle)
		kept := 0
		for n in played.store do kept += int(n)
		testing.expectf(t, len(played.zoned) >= 12 && kept >= 16, "a stockpile of %d places holds %d things carried to it", len(played.zoned), kept)
		for m in played.marks do testing.expectf(t, m.work == .Fell, "every block of the room is dug: %v is left, waiting because %s", m.at, WAITS[m.wait])
		stone, timber := 0, 0   // what lies anywhere, loose or stored: a block marked to be laid is built of the nearest
		for g in played.goods {
			stone += int(g.n) if is_stuff(g.kind, .Stone) else 0
			timber += int(g.n) if is_stuff(g.kind, .Timber) else 0
		}
		// The roof: one layer over the whole room, laid wherever the hill is not there already.
		open := make([dynamic][3]i32, context.temp_allocator)
		cells_of(.Build, .Floor, {lo.x, floor + 2, lo.z}, {hi.x, floor + 2, hi.z}, hold_blocks(played), &open)
		roof := Stuff.Timber if timber >= len(open) else .Stone
		wall := Stuff.Stone if stone - (len(open) if roof == .Stone else 0) >= 8 else .Timber
		testing.expectf(t, len(open) > 0 && stone + timber >= len(open) + 8 && max(stone, timber) >= len(open), "the room lies open over %d blocks, and the store has %d of stone and %d of timber to roof and wall it", len(open), stone, timber)
		order(t, played, &text, now, "build floor %s %d %d %d %d %d %d", STUFFS[roof], lo.x, floor + 2, lo.z, hi.x, floor + 2, hi.z)
		// The wall across the front, a door left in its middle.
		door := room.front + room.across*2
		for side in ([2][2]i32{{0, 1}, {3, 4}}) {
			a, b := room.front + room.across*side[0], room.front + room.across*side[1]
			order(t, played, &text, now, "build wall %s %d %d %d %d %d %d", STUFFS[wall], a.x, floor - 1, a.y, b.x, floor, b.y)
		}
		run_until(played, &now, 9000, idle)
		for m in played.marks do testing.expectf(t, m.work == .Fell, "the roof and the walls are built: %v is left, waiting because %s", m.at, WAITS[m.wait])
		for c in open {
			m, _ := walk_block(w, c)
			testing.expectf(t, m != .Air, "the roof is laid at %v", c)
		}
		// The party is sent in by the door, and stands under the roof.
		order(t, played, &text, now, "go %d %d %d", door.x + room.into.x*2, floor - 1, door.y + room.into.y*2)
		run_until(played, &now, 10000, proc(h: ^Hold) -> bool { return h.summed })
		inside := 0
		for d in played.dwarves do inside += int(d.cell.x >= lo.x && d.cell.x <= hi.x && d.cell.z >= lo.z && d.cell.z <= hi.z && d.cell.y == floor)
		testing.expectf(t, inside >= 4, "most of the party stands in the room, under its roof: %d do", inside)
		// Shelter (shelter.odin): the room is marked to sleep in, and a fire is laid in its middle. By the
		// rule its floor is indoors, and the ground the party gathered on is open to the sky.
		order(t, played, &text, now, "sleep %d %d %d %d %d %d", lo.x, floor - 1, lo.z, hi.x, floor - 1, hi.z)
		middle := [3]i32{(lo.x + hi.x)/2, floor, (lo.z + hi.z)/2}
		order(t, played, &text, now, "build fire timber %d %d %d %d %d %d", middle.x, floor - 1, middle.z, middle.x, floor - 1, middle.z)
		run_until(played, &now, now + 400, proc(h: ^Hold) -> bool { return len(h.fires) > 0 })
		testing.expect(t, len(played.fires) == 1 && played.fires[0].lit && played.fires[0].roof && played.fires[0].walled, "a fire is laid and lit in the room, under its roof and inside its walls")
		testing.expect(t, !shelter_of(hold_blocks(played), played.landed.camp).roof, "where the party gathered is open to the sky")
		sleeping, roofed_, walled := 0, 0, 0   // a place in line with the door, or beside a gap in the hill's side, is under the roof and not indoors
		for c, cell in played.zoned do if played.zones[cell.zone].sleep {
			sh := shelter_of(hold_blocks(played), c)
			sleeping, roofed_, walled = sleeping + 1, roofed_ + int(sh.roof), walled + int(indoors(sh))
		}
		testing.expectf(t, sleeping >= 20 && roofed_ == sleeping && 2*walled > sleeping, "the room's floor is a place to sleep, all of it under the roof and most of it indoors: %d places, %d roofed, %d indoors", sleeping, roofed_, walled)
		fmt.printfln("the room: %d, %d, %d to %d, %d, %d, its floor at %d; %d blocks of its roof were laid of %s; the store was left %d of stone and %d of timber; done %d:%02d in",
			lo.x, floor, lo.z, hi.x, floor + 1, hi.z, floor, len(open), STUFFS[roof], stone, timber, now/60, now%60)
	}
	// Needs (needs.odin): what bears food round the camp is marked to be gathered and its water to be
	// fished, a stockpile is marked for the food, and the party is left to itself into the second
	// day. Every dwarf has drunk at water it found for itself, eaten, and is alive.
	order(t, played, &text, now, "gather %d %d %d %d %d %d", camp.x - 30, camp.y, camp.z - 30, camp.x + 30, camp.y, camp.z + 30)
	order(t, played, &text, now, "fish %d %d %d %d %d %d", camp.x - 30, camp.y, camp.z - 30, camp.x + 30, camp.y, camp.z + 30)
	order(t, played, &text, now, "store food %d %d %d %d %d %d", camp.x - 3, camp.y - 1, camp.z - 3, camp.x + 3, camp.y - 1, camp.z + 3)
	// Winter's food (bench.odin): drying racks are ordered beside the camp, of the timber felled; what is gathered and
	// caught is carried in by those who took it, to the racks first, and what the racks dry is taken to the stockpile.
	order(t, played, &text, now, "build rack timber %d %d %d %d %d %d", camp.x + 4, camp.y - 1, camp.z - 2, camp.x + 6, camp.y - 1, camp.z + 1)
	now = max(now + 600, 2400)   // past the second day's dawn, which is 1,100 s in, and its noon
	hold_run(played, f64(now))
	testing.expect_value(t, said(played, "The 2nd of spring."), 1)
	{   // An order given while the clock stands is obeyed at once, at the tick in hand, and no tick passes (hold_heed):
		// the world paused is a place to give orders in. The log played again from the file, further down, must agree.
		zones, tick := len(played.zones), played.tick
		order(t, played, &text, now, "sleep %d %d %d %d %d %d", camp.x - 2, camp.y - 1, camp.z + 5, camp.x + 2, camp.y - 1, camp.z + 7)
		hold_heed(played)
		testing.expectf(t, played.tick == tick && len(played.zones) == zones + 1 && said(played, `The hold says "sleep`) == 2, "an order given while paused is obeyed at once: %d zones where %d were, tick %d from %d", len(played.zones), zones, played.tick, tick)
		order(t, played, &text, now, "unstore %d %d %d %d %d %d", camp.x, camp.y - 1, camp.z + 6, camp.x, camp.y - 1, camp.z + 6)
		hold_heed(played)
	}
	// The night was spent in the room marked to sleep in, by its fire, and nobody is the colder for it; the fire was fed from the timber felled.
	testing.expectf(t, said(played, "slept indoors") >= 1, "the dawn says the party slept indoors: %d times", said(played, "slept indoors"))
	testing.expectf(t, len(played.fires) == 1 && played.fires[0].lit && said(played, "on the fire at") >= 1, "the fire still burns, and was fed: %d fires, fed %d times", len(played.fires), said(played, "on the fire at"))
	for d, i in played.dwarves do testing.expectf(t, d.want[.Warm] > 0.5, "%s is warm on the second day: %.2f", played.party[i].given, d.want[.Warm])
	{   // the weather is a function of the tick and the place: asked twice it is the same, colder by night and higher up
		at := stand_of(played.landed.camp)
		day, night_ := weather(0.25*DAY, at), weather(0.75*DAY, at)
		testing.expect(t, weather(0.25*DAY, at) == day && day.air > night_.air, "the weather is not a function of the time, or the night is not colder than the day")
		high := at
		high.height += 400
		testing.expect(t, abs(weather(0.25*DAY, high).air - (day.air - 400*LAPSE)) < 0.01, "the air is not colder with height")
	}
	testing.expect(t, said(played, `The hold says "gather`) == 1 && said(played, `The hold says "fish`) == 1, "the orders to gather and to fish were obeyed")
	testing.expectf(t, len(played.wells) >= 1, "the party found fresh water to drink at: %d places known", len(played.wells))
	testing.expectf(t, len(played.picked) > 0, "plants were gathered or water fished: %d columns taken", len(played.picked))
	for d, i in played.dwarves {
		testing.expectf(t, d.doing != .Dead && d.want[.Drink] > 0 && d.want[.Food] > 0, "%s is alive on the second day, and neither parched nor starving: drink %.2f, food %.2f", played.party[i].given, d.want[.Drink], d.want[.Food])
		for w in Want do testing.expectf(t, d.want[w] >= 0 && d.want[w] <= 1, "%s's %s is a share of the whole: %.2f", played.party[i].given, WANTS[w].name, d.want[w])
	}
	{
		days, _, loose := food_days(played)
		fmt.printfln("needs: on the %s the seven are alive; food for %.1f days lies in the stockpile and %d things loose; %d columns gathered or fished; %d places to drink known", date_words(date_tick(played.tick)), days, loose, len(played.picked), len(played.wells))
	}
	// On to the fifth day's afternoon: the racks stand and have dried what was laid on them; nothing lies past its days;
	// the dawn has said the lean season ahead, by the island's own food rows; and the party is alive.
	now = int(4.3*DAY)
	hold_run(played, f64(now))
	{
		on_racks, dried := 0, 0
		for b in played.benches do on_racks += int(b.n)
		for g in played.goods {
			row := FOODS[food_of(g.kind)]
			if is(g.kind, FOOD) && row.from == .Made do dried += int(g.n)
			if is(g.kind, FOOD) && row.keeps > 0 do testing.expectf(t, g.age < row.keeps && g.left >= 0, "%d of %s lie past their days: %.1f of %.0f", g.n, row.name, g.age, row.keeps)
			testing.expectf(t, g.at not_in played.benched && g.n > 0, "a heap of %v lies under a rack, or is empty", g.kind)
		}
		ate := said(played, "of dried")   // a dawn that says dried food was eaten
		testing.expectf(t, len(played.benches) >= 1 && said(played, "build rack timber") == 1, "a rack ordered is built: %d stand", len(played.benches))
		testing.expectf(t, said(played, "are dried, and will keep") >= 1 && (on_racks + dried > 0 || ate > 0), "the racks have dried something: %d things on them, %d dried lying, eaten at %d dawns", on_racks, dried, ate)
		lean := lean_of(played)
		testing.expectf(t, lean.on && lean.season == 1 && lean.off == SEASON_DAYS - date_tick(played.tick).nth + 1 && lean.days == SEASON_DAYS && said(played, "Summer is") >= 1, "the lean season ahead is summer, said at dawn: %v", lean)
		for d, i in played.dwarves do testing.expectf(t, d.doing != .Dead && d.carrying >= 0 && (d.carrying == 0 || d.haul.on || d.job), "%s is alive on the fifth day, and carries nothing it is not taking somewhere", played.party[i].given)
		fmt.printfln("winter's food: on the %s %d racks stand with %d things on them; %d things dried lie; %s", date_words(date_tick(played.tick)), len(played.benches), on_racks, dried, lean_words(lean))
	}
	// The fifth night, at 23:30: those asleep in the room lie apart, none beside another, while it has places to spare
	// (sleep_find); and no plant, water or tree is left marked that every try found no way to (work_look).
	now = 4*int(DAY) + int((23.5 - LANDS_AT)*DAY/24)
	hold_run(played, f64(now))
	{
		asleep, beside := 0, 0
		for d, i in played.dwarves do if d.doing == .Sleeping {
			asleep += 1
			for o in played.dwarves[:i] do if o.doing == .Sleeping && abs(o.cell.x - d.cell.x) <= 1 && abs(o.cell.z - d.cell.z) <= 1 && abs(o.cell.y - d.cell.y) <= 1 do beside += 1
		}
		testing.expectf(t, asleep >= 4 && beside == 0, "the sleepers lie apart in the room: %d asleep, %d pairs side by side", asleep, beside)
		able: u64
		for d, i in played.dwarves do if ashore(d) && !d.shut && !d.adrift do able |= 1 << u64(i%64)
		for m in played.marks do testing.expectf(t, m.work == .Dig || m.work == .Build || m.wait != .No_Way || m.who & able != able, "a mark at %v that no dwarf has a way to is still marked", m.at)
	}
	SECONDS := now + 60
	hold_run(played, f64(SECONDS))
	for d, i in played.dwarves {
		w.budget = 64
		testing.expectf(t, d.doing != .Stopped && d.doing != .Dead && !d.adrift && !d.shut, "%s is alive at the end, with ground under it and a way from where it stands", played.party[i].given)
		testing.expectf(t, walk_floor(w, d.cell.x, d.cell.y, d.cell.z) >= 0, "%s stands on a floor", played.party[i].given)
		for o in played.dwarves[:i] do testing.expectf(t, o.cell != d.cell || !(stands(o) && o.takes == 0 && stands(d) && d.takes == 0), "%s has a floor of its own where it stands", played.party[i].given)   // a walker goes by one who stands
	}

	// The same orders from the file: alone, and on a thread of its own at a clock another thread
	// moves on in fits, reading what it shows meanwhile.
	path := "build/hold_test_orders.txt"
	testing.expect(t, os.write_entire_file(path, transmute([]u8)strings.to_string(text)) == nil, "the orders file is written")
	hold_make(alone, home, path)
	hold_run(alone, f64(SECONDS))
	hold_make(beside, home, path)
	hold_start(beside, SECONDS*10)
	Frames :: struct { h: ^Hold, stop: bool, read: int }
	frames := Frames{h = beside}
	reader := thread.create_and_start_with_poly_data(&frames, proc(f: ^Frames) {
		for !sync.atomic_load(&f.stop) {
			if sync.try_lock(&f.h.mutex) {
				tick := f.h.shown.tick
				sync.unlock(&f.h.mutex)
				f.read += int(tick >= 0)
			}
			sync.atomic_add(&f.h.target, 1 + f.read%7)
			sync.cond_signal(&f.h.wake)
			thread.yield()
		}
	})
	thread.join(beside.runner)
	sync.atomic_store(&frames.stop, true)
	thread.join(reader)

	fmt.printfln("the dwarves' logs: %d events, hash %x as played, %x from its orders alone and %x beside a reader that read %d times", len(played.log), log_hash(played), log_hash(alone), log_hash(beside), frames.read)
	fmt.printfln("the hold's ground: %d blocks changed, hash %x as played, %x alone and %x beside the reader", len(played.walk.edits), ground_hash(played), ground_hash(alone), ground_hash(beside))
	testing.expect_value(t, ground_hash(alone), ground_hash(played))
	testing.expect_value(t, ground_hash(beside), ground_hash(played))
	testing.expect_value(t, said(alone, "steps ashore."), LANDING)
	testing.expect_value(t, said(alone, "so no one sets out"), 1)
	testing.expect_value(t, alone.tick, SECONDS*10)
	testing.expect_value(t, len(alone.log), len(played.log))
	testing.expect_value(t, log_hash(alone), log_hash(played))
	testing.expect_value(t, log_hash(beside), log_hash(played))
}

// The blocks the hold has changed, in the order it changed them, and its store, as one figure.
ground_hash :: proc(h: ^Hold) -> (v: u64) {
	v = 0xcbf29ce484222325
	for &e in h.walk.edits do v = fnv.fnv64a(([^]u8)(&e)[:size_of(Edit)], v)
	for &n in h.store do v = fnv.fnv64a(([^]u8)(&n)[:size_of(i32)], v)
	return
}

// Where a first room can be dug: the hillside nearest the camp that a box five wide and six deep
// goes into level from its foot, the ground over its back standing three blocks or more over the
// floor, so the hill roofs it there, and its front lying open, to be roofed by hand; with open
// level ground before its door, and half of it or more in rock the party's picks cut.
Room_Site :: struct {
	lo, hi:  [3]i32,   // its box, two blocks high
	floor:   i32,      // the level of the cells stood in
	front:   [2]i32,   // the first column of its front row, x and z
	across:  [2]i32,   // the way along that row
	into:    [2]i32,   // and the way into the hill
}
hillside :: proc(h: ^Hold) -> (r: Room_Site, ok: bool) {
	w := &h.walk
	ground :: proc(w: ^Walk, x, z: i32) -> (y: i32, ok: bool) {   // the ground's top as the land made it, where it is dry and no block of it has been changed
		y = ground_top(f64(x) + 0.5, f64(z) + 0.5)
		for e in w.edits do if abs(e.x - x) <= 1 && abs(e.z - z) <= 1 do return
		w.budget = 64
		f := walk_floor(w, x, y, z)
		return y, f >= 0 && w.floors[f].wet == 0
	}
	camp := h.landed.camp
	for reach in i32(6)..<120 do for dz in -reach..=reach do for dx in -reach..=reach {
		if max(abs(dx), abs(dz)) != reach do continue
		for into in ([4][2]i32{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			across := [2]i32{-into.y, into.x}
			door := [2]i32{camp.x + dx, camp.z + dz}
			floor, dry := ground(w, door.x, door.y)
			if !dry do continue
			good, open, back := true, 0, max(i32)
			for k in i32(1)..=6 do for a in i32(-2)..=2 {
				c := door + into*k + across*a
				y, any := ground(w, c.x, c.y)
				good &&= any && y >= floor && y <= floor + 8 && (k > 1 || y <= floor + 1)
				open += int(y <= floor + 2)
				if k == 6 do back = min(back, y)
			}
			for k in i32(1)..=3 do for a in i32(-1)..=1 {   // open, level ground before the door
				c := door - into*k + across*a
				y, any := ground(w, c.x, c.y)
				good &&= any && abs(y - floor) <= 1
			}
			if !good || open < 6 || open > 20 || back < floor + 3 do continue
			a, b := door + into - across*2, door + into*6 + across*2
			r.lo, r.hi = box_of({a.x, floor, a.y}, {b.x, floor + 1, b.y})
			rock := 0   // enough of it in rock the picks cut to roof and wall it from
			for y in r.lo.y..=r.hi.y do for z in r.lo.z..=r.hi.z do for x in r.lo.x..=r.hi.x {
				m, _ := walk_block(w, {x, y, z})
				if kind := rock_kind(m); kind != .Air && MATERIALS[m].strength <= TOOLS do rock += 1
				else if MATERIALS[m].strength > TOOLS do rock -= 100
			}
			if rock < 32 do continue
			r.floor, r.front, r.across, r.into = floor, a, across, into
			return r, true
		}
	}
	return
}
