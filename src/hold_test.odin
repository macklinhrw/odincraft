package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"

// The dwarves' world is deterministic (docs/adr/0007): the same seed and orders give the same log,
// run alone or beside a thread that reads it and moves its clock as the frame does. The test lands
// the default world's party and sends it to two places by an orders file, twice, and compares the
// logs. It keeps no golden hash: what the dwarves do follows the land, which changes on purpose.

// Called by the forming test once the start island is formed and bound.
dwarves_world_is_deterministic :: proc(t: ^testing.T) {
	alone, beside := new(Hold), new(Hold)
	alone.quiet, beside.quiet = true, true
	hold_make(alone, home, "")
	if !testing.expect(t, alone.found, "the default island has a landing") do return
	// Orders to ground near the camp, to ground 150 m off, and to the open sea, which has none.
	camp := alone.landed.camp
	out := [2]i32{i32(alone.landed.out.x*300), i32(alone.landed.out.y*300)}
	path := "build/hold_test_orders.txt"
	orders := fmt.tprintf("# written by hold_test.odin\n150 go %d %d\n2:50.0 go %d %d\n[5:00.0] go %d %d\n", camp.x + 12, camp.z + 9, camp.x + out.x, camp.z + out.y, camp.x - out.x/2, camp.z - out.y/2)
	testing.expect(t, os.write_entire_file(path, transmute([]u8)orders) == nil, "the orders file is written")
	SECONDS :: 900
	orders_read(alone, path)
	hold_run(alone, SECONDS)

	// Again, on its own thread at a clock another thread moves on in fits, reading what it shows meanwhile.
	hold_make(beside, home, path)
	hold_start(beside, SECONDS*10)
	Frames :: struct { h: ^Hold, stop: bool, read: int }
	frames := Frames{h = beside}
	reader := thread.create_and_start_with_poly_data(&frames, proc(f: ^Frames) {
		for !sync.atomic_load(&f.stop) {
			if sync.try_lock(&f.h.mutex) {
				seen := f.h.shown
				sync.unlock(&f.h.mutex)
				f.read += int(seen.tick >= 0)
			}
			sync.atomic_add(&f.h.target, 1 + f.read%7)
			sync.cond_signal(&f.h.wake)
			thread.yield()
		}
	})
	thread.join(beside.runner)
	sync.atomic_store(&frames.stop, true)
	thread.join(reader)

	ashore, obeyed := 0, 0
	for line in alone.log {
		ashore += int(strings.has_suffix(line, "steps ashore."))
		obeyed += int(strings.contains(line, "The hold says"))
	}
	fmt.printfln("the dwarves' logs: %d events, hash %x alone and %x beside a reader that read %d times", len(alone.log), log_hash(alone), log_hash(beside), frames.read)
	testing.expect_value(t, ashore, PARTY)
	testing.expect_value(t, obeyed, 3)
	testing.expect_value(t, alone.tick, SECONDS*10)
	testing.expect_value(t, len(beside.log), len(alone.log))
	testing.expect_value(t, log_hash(beside), log_hash(alone))
}
