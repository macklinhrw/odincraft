package main

import "core:fmt"
import "core:hash"
import "core:slice"
import "core:testing"
import "core:thread"

// Forming is deterministic (ADR 0005): an island comes out bit for bit the same from its record and
// seed alone, on any thread, alone or beside others. These tests form the default world's start
// island and its nearest neighbour and hash what forming leaves. A change that alters the land on
// purpose updates GOLDEN, and says so in its commit; any other change must leave it as it is.

GOLDEN :: [2]u64{0xf48f867a7a20ab61, 0x87a402412babddc0}   // seed 7: the start island, island 1 (since step 32's history an inlets island, its rock read from its setting since step 24: layered on the forearc since step 24 met that history)

@(private="file")
land_hash :: proc() -> u64 {
	h := hash.fnv64a(slice.to_bytes(land.z[0]))
	h ~= hash.fnv64a(slice.to_bytes(land.wet))
	h ~= hash.fnv64a(slice.to_bytes(land.age))
	h ~= hash.fnv64a(land.community)
	return h
}

@(private="file")
world_make :: proc() {
	world_seed = 7
	seed = world_seed
	@(static) first: Formed
	first.island, first.region.origin = {origin = {0, 0}, size = REFERENCE, seed = world_seed}, {0, 0}
	bind(&first)
	region_init("")
	known_make()   // the plates' history, which places the islands near the start
	archipelago_make(false)
	arrivals_make()
	formed = make([]Formed, len(archipelago))
	for &f, i in formed do f.island = archipelago[i]
	home = &formed[0]
}

@(test)
forming_is_deterministic :: proc(t: ^testing.T) {
	world_make()
	// The start island, formed on this thread.
	gen_init(home)
	bind(home)
	start := land_hash()
	// Its neighbour, formed on another thread and then again here: the same both times.
	pool := islands_form([]int{1}, 1, .Normal, false)
	thread.join_multiple(..pool)
	bind(&formed[1])
	there := land_hash()
	@(static) again: Formed   // static: the bound names keep pointing at it after the test
	again.island = formed[1].island
	gen_init(&again)
	bind(&again)
	here := land_hash()
	fmt.printfln("land hashes: start %x, island 1 %x (another thread) %x (this thread)", start, there, here)
	testing.expect_value(t, here, there)
	testing.expect_value(t, [2]u64{start, there}, GOLDEN)
}
