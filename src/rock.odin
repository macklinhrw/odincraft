package main

import "core:fmt"
import "core:math"

// The rock under the island: one function of a point, fixed in the finished world. The
// land forming reads it shifted by the uplift still to come, so the beds the erosion cut
// are the beds the blocks show; the surface, the blocks and the map read it as it is.
// Nothing is stored per block.
//
// The rock is drawn from the seed within the ranges of a story: a stack of beds, tilted
// and gently folded, or laid over the forms the island's vents built, so that a volcano's
// flows and ash lie parallel to its slopes and dip away from its vent. A point's place in the
// stack is its height less the height of the stack's base under it, and the bed there is read
// from a table, one entry a metre.

// A kind a story draws its beds from: how often, and between which places in the stack
// (metres above the base, which is about the height above sea level under the island's
// middle).
Story_Kind :: struct {
	kind:   Mat,
	weight: f32,
	at:     [2]f32,
}

Story :: struct {
	name:  string,
	kinds: [6]Story_Kind,
	thick: [2]f32,   // bed thickness, metres
	hard:  f32,      // share of beds drawn from the hard kinds, those of strength 0.5 or more
	gap:   f32,      // the most soft rock between two hard beds, metres
	tilt:  [2]f32,   // dip of the beds, degrees
	fold:  [2]f32,   // height of the folds, metres
	wave:  [2]f32,   // their wavelength, metres
	drape: bool,     // the beds lie over the ground the vents built (land.odin), rather than level
	mantle: f32,     // the least a hillside of it creeps where soil holds: ash and cinders mantle a volcano's lava and creep whatever lies under them
}

ANYWHERE :: [2]f32{-1e5, 1e5}

// The island's kind names its story (land.odin); the seed draws everything else within its ranges.
STORIES := [?]Story{
	{
		name = "layered, gently tilted",
		// Grit gathers high in the stack and caps the hills; limestone is rare and low, so it
		// shows only in the deepest valleys.
		kinds = {
			{.Mudstone, 3, ANYWHERE}, {.Siltstone, 2, ANYWHERE}, {.Sandstone, 2, ANYWHERE},
			{.Grit, 0.4, {-1e5, 50}}, {.Grit, 3, {50, 1e5}}, {.Limestone, 1.2, {-1e5, -20}},
		},
		thick = {12, 50}, hard = 0.3, gap = 110, tilt = {3, 8}, fold = {20, 70}, wave = {1800, 4500},
	},
	{
		// Runny lava: black flows of basalt between beds of red cinders and ash, after the
		// sea cliffs of Toshima and Mikurajima.
		name = "lava and ash",
		kinds = {0 = {.Basalt, 1, ANYWHERE}, 1 = {.Scoria, 1, ANYWHERE}},
		thick = {12, 40}, hard = 0.4, gap = 40, fold = {30, 70}, wave = {400, 1000}, drape = true, mantle = 0.35,
	},
	{
		// Stiff lava: pale domes and thick flows of rhyolite in sheets of pumice and ash, after
		// Kōzushima.
		name = "pale lava and pumice",
		kinds = {0 = {.Rhyolite, 1, ANYWHERE}, 1 = {.Tuff, 1, ANYWHERE}},
		thick = {10, 50}, hard = 0.5, gap = 60, fold = {15, 40}, wave = {600, 1500}, drape = true, mantle = 0.35,
	},
}

STACK_LO    :: -2048   // the table covers this far below the base
STACK_LEN   :: 8192    // and this far up: enough for the uplift still to come when the forming starts
ROCK_LEVELS :: 5       // tables with the beds thinner than 1 to 16 m merged
ROCK_SIM    :: 4       // the table the 16 m land forming reads

// How a rock wears, from its strength: D4 in docs/foundations/geology.md, with erosion
// (0.4/strength)² rather than (0.5/strength)², which keeps the island near its old height.
// Slopes run from 35° on the weakest rock to 60° on the strongest, rising most steeply at the
// strong end, so that a strong bed stands as a face and the weak ones as steep hillsides, and
// creep falls with the square of weakness, so crests in strong rock stay sharp.
Rock_Law :: struct {
	erodes: f32,   // how fast running water cuts it, around 1
	limit:  f32,   // the steepest slope it holds, rise over run
	creep:  f32,   // how fast its hillsides creep, at most 1
}

Bed :: struct { kind: Mat, thick: f32 }

Rocks :: struct {
	dip:   [2]f64,   // rise of the stack's base per metre east and south
	fold:  f32,
	wave:  f64,
	table: [ROCK_LEVELS][STACK_LEN]Mat,
	law:   [Mat]Rock_Law,
	beds:  [dynamic]Bed,       // the stack from the bottom up, as a one-metre cell sees it
	bed:   [STACK_LEN]u16,     // which of them each metre lies in
	floor: [dynamic]f32,       // where each begins, metres from the table's start
	drape: []f32,              // the ground the vents built, on a grid of DRAPE m, where the story lays its beds over it
}


DRAPE :: 32

rock_init :: proc() {
	story := region.story
	draw :: proc(r: [2]f32, k: i32) -> f32 { return math.lerp(r[0], r[1], hash01(k, 0, seed + 301)) }
	dip, turn := math.tan(math.to_radians(f64(draw(story.tilt, 0)))), 2*math.PI*f64(hash01(1, 0, seed + 301))
	rocks.dip = {dip*math.cos(turn), dip*math.sin(turn)}
	rocks.fold, rocks.wave = draw(story.fold, 2), f64(draw(story.wave, 3))
	if story.drape {
		n := int(region.size)/DRAPE + 1
		rocks.drape = make([]f32, n*n)
		for c in 0..<n*n do rocks.drape[c] = built(f64(c%n*DRAPE) - region.size/2, f64(c/n*DRAPE) - region.size/2)
		fmt.printfln("rock: %s, laid over the forms the vents built; folds %.0f m high every %.1f km", story.name, rocks.fold, rocks.wave/1000)
	} else {
		fmt.printfln("rock: %s; beds dip %.1f° toward %.0f° (0 is north, 90 east), folds %.0f m high every %.1f km",
			story.name, draw(story.tilt, 0), math.mod(math.to_degrees(math.atan2(-math.cos(turn), math.sin(turn))) + 360, 360), rocks.fold, rocks.wave/1000)
	}
	for m in Mat {
		s := MATERIALS[m].strength
		if s == 0 do continue
		rocks.law[m] = {clamp(0.16/(s*s), 0.2, 5), math.tan(math.to_radians(35 + 25*math.pow((s - 0.2)/0.6, 1.5))), (1 - s)*(1 - s)/0.5625}
	}

	// The beds, from the bottom of the stack up.
	beds: [dynamic]Bed
	defer delete(beds)
	soft: f32   // metres of soft rock since the last hard bed
	for at, i := f32(STACK_LO), i32(0); at < STACK_LO + STACK_LEN; i += 1 {
		hard := hash01(i, 1, seed + 302) < story.hard || soft > story.gap
		total: [2]f32   // weight of the soft and the hard kinds that may lie here
		for k in story.kinds do if at >= k.at[0] && at < k.at[1] do total[int(MATERIALS[k.kind].strength >= 0.5)] += k.weight
		if total[int(hard)] == 0 do hard = !hard
		pick := hash01(i, 2, seed + 302)*total[int(hard)]
		bed := Bed{thick = draw(story.thick, i + 10)}
		for k in story.kinds {
			if at < k.at[0] || at >= k.at[1] || (MATERIALS[k.kind].strength >= 0.5) != hard do continue
			bed.kind = k.kind
			pick -= k.weight
			if pick < 0 do break
		}
		if hard do bed.thick = max(bed.thick, 20)   // so the 16 m land forming holds it
		append(&beds, bed)
		at += bed.thick
		soft = 0 if hard else soft + bed.thick
	}

	// Each table holds the stack with the beds thinner than its size merged into their
	// thicker neighbour. The land forming reads the one at its cell size, which is all it can
	// hold; what is drawn reads a finer one (rock_level).
	for level in 0..<ROCK_LEVELS {
		cell := f32(i32(1) << uint(level))
		for len(beds) > 1 {
			thin := -1
			for b, i in beds do if b.thick < cell && (thin < 0 || b.thick < beds[thin].thick) do thin = i
			if thin < 0 do break
			into := thin + 1
			if thin == len(beds) - 1 || (thin > 0 && beds[thin - 1].thick > beds[thin + 1].thick) do into = thin - 1
			beds[into].thick += beds[thin].thick
			ordered_remove(&beds, thin)
		}
		i, top := 0, f32(0)
		for b, n in beds {
			if level == 0 {
				append(&rocks.beds, b)
				append(&rocks.floor, top)
			}
			top += b.thick
			for ; i < STACK_LEN && f32(i) < top; i += 1 {
				rocks.table[level][i] = b.kind
				if level == 0 do rocks.bed[i] = u16(n)
			}
		}
	}
}

// Height of the stack's base under a point: the tilt, the folds, and the ground the vents built
// where the beds lie over it.
rock_base :: proc(x, z, cell: f64) -> f32 {
	return f32(rocks.dip.x*x + rocks.dip.y*z) + rocks.fold*fbm(x, z, rocks.wave, cell, 2, seed + 303) + drape_at(x, z)
}

drape_at :: proc(x, z: f64) -> f32 {
	if len(rocks.drape) == 0 do return 0
	n := int(region.size)/DRAPE + 1
	u, v := clamp((x + region.size/2)/DRAPE, 0, f64(n) - 1.001), clamp((z + region.size/2)/DRAPE, 0, f64(n) - 1.001)
	i, j := int(u), int(v)
	tu, tv := f32(u - f64(i)), f32(v - f64(j))
	k := j*n + i
	return math.lerp(math.lerp(rocks.drape[k], rocks.drape[k + 1], tu), math.lerp(rocks.drape[k + n], rocks.drape[k + n + 1], tu), tv)
}

// Which way the beds run level at a point, across the slope of the stack's base.
rock_strike :: proc(x, z: f64) -> [2]f64 {
	d := rocks.dip + [2]f64{f64(drape_at(x + 8, z) - drape_at(x - 8, z)), f64(drape_at(x, z + 8) - drape_at(x, z - 8))}/16
	l := math.hypot(d.x, d.y)
	return [2]f64{-d.y, d.x}/l if l > 1e-6 else {1, 0}
}

// The rock at height y over a point whose stack base is `base`, from one level's table.
rock_in :: #force_inline proc(y, base: f32, level: int) -> Mat {
	return rocks.table[level][clamp(int(y - base - STACK_LO), 0, STACK_LEN - 1)]
}

// Which table a cell size is drawn from. A far face is drawn in whole metres however wide its
// cells are, so its beds are merged only once they are thinner than a quarter of a cell, about
// two pixels where that cell is in use; merged at the cell's own size, every face beyond 4 km
// lost its upper beds and beyond 9 km was one rock.
rock_level :: proc(cell: f64) -> int {
	return clamp(int(math.log2(cell)) - 2, 0, ROCK_LEVELS - 1)
}

// The rock at a point, as seen at a cell size.
rock :: proc(x, y, z, cell: f64) -> Mat {
	return rock_in(f32(y), rock_base(x, z, cell), rock_level(cell))
}
