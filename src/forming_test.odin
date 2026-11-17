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

GOLDEN :: [2]u64{0x3f862441cd5f4a52, 0x106915c577d2dabd}   // seed 7: the start island and island 1, both read from the regional history since step 32's second half (an inlets island and a ridge island, both standing on old volcanoes); their slides' lakes fill with silt (step 35); their bays' silt falls gently under the sea and reed marsh grows (step 27); the ridge wood stands off the wettest crests (step 25)

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
	// The dwarves' world on the start island (hold_test.odin). It runs here because the runner frees
	// what a test made when the test ends, so one test forms the world for both.
	bind(home)
	dwarves_world_is_deterministic(t)
	// And the play screen over it (play_test.odin), for the same reason.
	bind(home)
	the_play_screen_says_what_is_so(t)
	bind(home)
	the_dwarves_are_on_screen(t)
	// A landmass's coarse stage formed in parallel is the serial forming's, cell for cell (coarse.odin).
	the_coarse_stage_is_the_serial_forming(t)
}

// The smallest land mass of the default world larger than a region, formed through its 64 m phases both
// ways, step by step: in parallel, and as the serial forming takes it with its flood taking of two
// cells at one level the lower index. Every stage of every step is compared.
the_coarse_stage_is_the_serial_forming :: proc(t: ^testing.T) {
	lands_make()
	// The land mass on the smallest lattice that has land when its forming starts (one whose ground the
	// history is still raising may start under the sea).
	order := slice.clone(lands)
	slice.sort_by(order, proc(a, b: Landmass) -> bool { return a.side < b.side })
	m: ^Landmass
	g: ^Grid
	upto, n := 0, 0
	for &o in order {
		for &l in lands do if l.mass == o.mass do m = &l
		mass_bind(m, &m.frame, -1, m.origin, m.side)
		upto = 0
		for p, i in region.history do if p.cell >= 64 do upto = i + 1
		n = int(m.side)/64
		g = coarse_grid(n)
		if slice.contains(g.coarse.core, true) do break
		coarse_free(g)
		grid_free(g)
		g = nil
	}
	if !testing.expect(t, g != nil, "the default world has a land mass larger than a region with land") do return
	p := grid_make(n)
	coarse_attach(p, true)
	for ph in region.history {
		g.left += ph.steps*ph.years*ph.uplift
		p.left += ph.steps*ph.years*ph.uplift
	}
	check_phases(g, p, upto)
	differ, cells := coarse_differ(g, p)
	fmt.printfln("the coarse stage of land mass %d (%.0f km², on a lattice %.0f km across), formed in parallel and as the serial forming takes it: %d of %d land cells differ after %d steps; %d steps routed plainly", m.mass, m.area, m.side/1000, differ, cells, g.coarse.steps, g.coarse.failed)
	testing.expect_value(t, differ, 0)
	testing.expect_value(t, g.coarse.failed, 0)
	testing.expect(t, cells > 10_000, "the land mass has land")
}
