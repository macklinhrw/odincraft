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
		testing.expect(t, played.work.squeezed > squeezed, "dwarves squeezed past each other in the passage")
		fmt.printfln("the passage runs east from %d, %d, %d: %d stood in it, and they squeezed past each other %d times on the way back", at.x, at.y, at.z, inside, played.work.squeezed - squeezed)
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
		for d in h.dwarves do if d.job do return false
		for m in h.marks do if m.wait == .None do return false
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
		run_until(played, &now, 6000, idle)
		for m in played.marks do testing.expectf(t, m.work == .Fell, "every block of the room is dug: %v is left, waiting because %s", m.at, WAITS[m.wait])
		stone, _ := store_of(&played.store, .Stone)
		timber, _ := store_of(&played.store, .Timber)
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
		fmt.printfln("the room: %d, %d, %d to %d, %d, %d, its floor at %d; %d blocks of its roof were laid of %s; the store was left %d of stone and %d of timber; done %d:%02d in",
			lo.x, floor, lo.z, hi.x, floor + 1, hi.z, floor, len(open), STUFFS[roof], stone, timber, now/60, now%60)
	}
	SECONDS := now + 60
	hold_run(played, f64(SECONDS))
	for d, i in played.dwarves {
		w.budget = 64
		testing.expectf(t, d.doing == .Waiting, "%s stands at the end, having found its way", played.party[i].given)
		testing.expectf(t, walk_floor(w, d.cell.x, d.cell.y, d.cell.z) >= 0, "%s stands on a floor", played.party[i].given)
		for o in played.dwarves[:i] do testing.expectf(t, o.cell != d.cell, "%s has a floor of its own", played.party[i].given)
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
