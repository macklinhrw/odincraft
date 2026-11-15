package main

import fnv "core:hash"
import "core:math"

// One island of the archipelago: what the world knows of it before it is formed.
Island :: struct {
	id:      int,      // 0 is the start island, today's island at the origin
	origin:  [2]i32,   // where its region's middle lies in the world, metres (Region.origin)
	size:    f64,      // its region's side, metres (Region.size)
	kind:    int,      // its row in KINDS
	seed:    u32,      // the seed its region is formed from: the start island's is the world's seed, the others the world's seed hashed with id
}
archipelago: [dynamic]Island   // made by archipelago_make(), from the world's seed

// A stand-in until step 17 places the islands: today's island at the origin, of the kind the
// world's seed draws (as region_init draws it), a cone 14 km east and the inlets kind 16 km south.
archipelago_make :: proc() {
	drawn, cone, inlets, best := 0, 0, 0, f32(-1)
	for k, i in KINDS {
		if h := math.pow(hash01(i32(fnv.fnv32a(transmute([]u8)k.name)), 0, seed + 500), 1/k.weight); h > best do drawn, best = i, h
		if k.name == "cone" do cone = i
		if k.name == "inlets" do inlets = i
	}
	append(&archipelago, Island{0, {0, 0}, REFERENCE, drawn, seed}, Island{1, {14000, -3000}, REFERENCE, cone, hash(1, 0, seed)}, Island{2, {-6000, 15000}, REFERENCE, inlets, hash(2, 0, seed)})
}
