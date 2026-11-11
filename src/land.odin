package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:os"
import "core:slice"
import "core:time"

// The land is formed before play. An island is pushed up out of the sea for about four
// million years while running water cuts it down and hillsides slump to the steepest
// angle they can hold. Valleys, ridges and the river network come out of that together,
// which is the point: a river here is the reason its valley exists.
//
// The work runs coarse to fine. Most of the time passes on a 64 m grid, where a step is
// cheap; each refinement doubles the detail and runs long enough for the next size of
// valley to cut in.

LAND_CELL :: 16          // metres, on the finest grid
ERODE     :: 1.3e-5      // how fast water cuts: per year, times root of drainage area, times slope
CREEP     :: 0.012       // m²/yr of soil creep, which rounds hilltops, on the weakest rock

CHANNEL_AREA :: 120_000   // m² of land that must drain through a cell before it carries a stream

// What kind of island this is lives in one record, drawn from the seed within the ranges of
// a kind's row. Forming reads nothing else, so a seed and a record make the same land
// wherever the region lies. Lengths in a row are metres on a region 8,192 m across and
// stretch with the region; heights, rates and years are true.
REFERENCE :: 8192

// The island's outline, and the pattern it rises in.
Shape :: struct($T: typeid) {
	radius:              T,   // of the island, as a share of the region's side
	xx, zz, xz:          T,   // how the outline is stretched and turned
	ragged, ragged_wave: T,   // the coast wanders in and out by this share of the radius, over this distance
	rate:                T,   // uplift at the heart of the island, m/yr
	coast:               T,   // the uplift grows from nothing at the shore over this share of the way inland
	floor:               T,   // the share of it found everywhere inland,
	ridge:               T,   // and more along a range
	axis:                T,   // that runs east to west this far south of the middle,
	bend, bend_wave:     T,   // swinging this far north and south over this distance,
	wander, wander_wave: T,   // wandering this far besides,
	width:               T,   // and this wide;
	peak, peak_width:    T,   // and more toward the middle, falling away over this share of the way to the coast.
	lumps, lumps_wave:   T,   // The uplift varies by this share over this distance.
}

// A stretch of the island's history: steps of so many years on cells of a size, with the
// island rising at a share of the shape's rate, begun by the sea rising (or, below zero,
// falling) so many metres. Cells halve from one phase to the next or stay.
Phase :: struct($T: typeid) {
	cell:  int,
	years: f32,   // per step
	steps, uplift, sea: T,
}

Kind :: struct {
	name:    string,
	shape:   Shape([2]f64),
	history: []Phase([2]f32),
}

KINDS := [?]Kind{
	{
		// A range north of the middle and a long south slope with room for rivers. It rises
		// for 3 to 4 million years, and the sea then floods the valley mouths into inlets.
		name = "ridge",
		shape = {
			radius = {0.29, 0.33}, xx = {0.85, 1.0}, zz = {1.15, 1.35}, xz = {-0.4, 0.4}, ragged = {0.35, 0.45}, ragged_wave = {2500, 3500},
			rate = {0.00055, 0.0007}, coast = {0.25, 0.35}, floor = {0.25, 0.35}, ridge = {0.8, 1.1},
			axis = {-1100, -600}, bend = {250, 550}, bend_wave = {1400, 2200}, wander = {250, 450}, wander_wave = {2000, 3000}, width = {850, 1200},
			lumps = {0.3, 0.45}, lumps_wave = {1800, 2600},
		},
		history = {
			{cell = 64, years = 20000, steps = {140, 175}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {40, 60}, uplift = {1, 1}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {1, 1}},
			{cell = 16, sea = {5, 10}},   // too lately for anything to wear
		},
	},
	{
		// A young cone: round, rising fast in the middle for under a million years, so its
		// gullies run out from the summit and have not yet cut far in.
		name = "cone",
		shape = {
			radius = {0.26, 0.32}, xx = {0.9, 1.1}, zz = {0.9, 1.1}, xz = {-0.2, 0.2}, ragged = {0.15, 0.25}, ragged_wave = {2500, 3500},
			rate = {0.0015, 0.0025}, coast = {0.1, 0.2}, floor = {0.05, 0.1}, peak = {1.5, 2}, peak_width = {0.35, 0.5},
			lumps = {0.15, 0.25}, lumps_wave = {2000, 3000},
		},
		history = {
			{cell = 64, years = 20000, steps = {30, 45}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {50, 50}, uplift = {1, 1}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {1, 1}},
			{cell = 16, sea = {3, 8}},
		},
	},
	{
		// Worn down: it rose as the ridge island does, then the uplift stopped some 400,000 years
		// ago and the land has been wearing away since: low rounded hills, the sea in its valleys.
		// Much longer at rest and it wears down to the sea.
		name = "worn",
		shape = {
			radius = {0.31, 0.36}, xx = {0.85, 1.15}, zz = {0.85, 1.2}, xz = {-0.5, 0.5}, ragged = {0.35, 0.5}, ragged_wave = {2500, 3500},
			rate = {0.0005, 0.0007}, coast = {0.2, 0.3}, floor = {0.3, 0.5}, ridge = {0.6, 0.95},
			axis = {-900, 900}, bend = {200, 500}, bend_wave = {1500, 2500}, wander = {200, 400}, wander_wave = {2500, 2500}, width = {1000, 1400},
			lumps = {0.3, 0.5}, lumps_wave = {2000, 3000},
		},
		history = {
			{cell = 64, years = 20000, steps = {150, 170}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {40, 60}, uplift = {0, 0}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {0, 0}},
			{cell = 16, sea = {4, 8}},
		},
	},
	{
		// Raised: the sea fell twice late in the island's rise and uncovered the shelf around it.
		// The shelf does not rise with the island, so the first coast stands as one step above
		// it, and the streams crossing it cut back into it, the larger faster, until a last small
		// rise floods their mouths. A step for each fall waits for the sea to cut its own shore.
		name = "raised",
		shape = {
			radius = {0.26, 0.30}, xx = {0.8, 1.2}, zz = {0.8, 1.25}, xz = {-0.5, 0.5}, ragged = {0.3, 0.45}, ragged_wave = {2500, 3500},
			rate = {0.0005, 0.0007}, coast = {0.15, 0.3}, floor = {0.3, 0.5}, ridge = {0.6, 0.95},
			axis = {-900, 900}, bend = {200, 500}, bend_wave = {1500, 2500}, wander = {200, 400}, wander_wave = {2500, 2500}, width = {1000, 1400},
			lumps = {0.3, 0.5}, lumps_wave = {2000, 3000},
		},
		history = {
			{cell = 64, years = 20000, steps = {150, 170}, uplift = {1, 1}},
			{cell = 32, years = 6000, steps = {40, 50}, uplift = {1, 1}, sea = {-8, -12}},
			{cell = 16, years = 3000, steps = {30, 30}, uplift = {1, 1}, sea = {-8, -12}},
			{cell = 16, sea = {3, 6}},
		},
	},
}

Region :: struct {
	kind:    string,
	size:    f64,      // metres along a side; the region's rim is always sea
	origin:  [2]i32,   // where its middle lies in the world; everything in it is stored relative to that
	shape:   Shape(f64),
	story:   ^Story,
	history: []Phase(f32),
}

region: Region

// Draw the region's record from the seed, of the named kind or, with none named, of the kind
// the seed picks: each row draws a number keyed by its name and the highest wins, so a new row
// changes only the seeds it wins. False if no kind has the name.
region_init :: proc(name: string) -> bool {
	kind: ^Kind
	best: f32 = -1
	for &k in KINDS {
		if h := hash01(i32(fnv.fnv32a(transmute([]u8)k.name)), 0, seed + 500); (name == "" && h > best) || k.name == name do kind, best = &k, h
	}
	if kind == nil do return false
	key := i32(fnv.fnv32a(transmute([]u8)kind.name))
	N :: size_of(Shape(f64))/size_of(f64)
	ranges, drawn := transmute([N][2]f64)kind.shape, [N]f64{}
	for r, i in ranges do drawn[i] = r[0] + (r[1] - r[0])*f64(hash01(i32(i), key, seed + 520))
	draw :: proc(r: [2]f32, i, key: i32) -> f32 { return r[0] + (r[1] - r[0])*hash01(i, key, seed + 521) }
	region.kind, region.size, region.shape = kind.name, REFERENCE, transmute(Shape(f64))drawn
	region.story = &STORIES[hash(0, 0, seed + 300) % len(STORIES)]
	region.history = make([]Phase(f32), len(kind.history))
	for p, i in kind.history {
		k := i32(3*i)
		region.history[i] = {p.cell, p.years, math.round(draw(p.steps, k, key)), draw(p.uplift, k + 1, key), draw(p.sea, k + 2, key)}
	}
	fmt.printf("island: %s, %.1f km across", region.kind, region.size/1000)
	for p in region.history {
		if p.sea != 0 do fmt.printf("; the sea %s %.0f m", "rises" if p.sea > 0 else "falls", abs(p.sea))
		rising := fmt.tprintf("rising %.2f mm/yr", p.uplift*f32(region.shape.rate)*1000) if p.uplift > 0 else "at rest"
		if p.steps > 0 do fmt.printf("; %.0f kyr %s on %d m cells", p.steps*p.years/1000, rising, p.cell)
	}
	fmt.println()
	return true
}

Grid :: struct {
	n:      int,
	d:      f32,            // cell size, metres
	z:      []f32,          // ground elevation, over the sea as it stands now
	fill:   []f32,          // elevation once hollows are filled: the surface water runs down
	next:   []i32,          // the cell each land cell drains into, or -1 for the sea
	area:   []f32,          // land draining through each cell, m²
	uplift: []f32,          // m/yr at the shape's full rate
	sea:    []bool,
	soft:   []f32,          // how easily the rock erodes, around 1, from one outcrop to the next
	base:   []f32,          // height of the rock stack's base under each cell (rock.odin)
	jitter: [][2]f32,       // where each cell's node sits in its square, so flow has no favourite compass direction
	seen:   []bool,
	order:  [dynamic]i32,   // land cells from the shore upward
	heap:   [dynamic]Heap_Item,
	lift:   f32,            // the share of the uplift in this phase
	left:   f32,            // years of full uplift still to come
	rise:   f32,            // metres the sea has still to rise
}

// The finished land, read by the generator.
Land :: struct {
	n:     int,        // cells along a side at 16 m
	z:     [3][]f32,   // elevation at 16, 32 and 64 m cells
	slope: []f32,      // steepness
	wet:   []f32,      // 0 on ridges to 1 in valley floors
	grid:  ^Grid,      // the finest grid, kept for the river network
}

land: Land

// Positive inland, negative at sea, at a point relative to the region's middle.
shore :: proc(x, z: f64) -> f32 {
	sh, k := region.shape, REFERENCE/region.size
	r := f32(math.sqrt(x*x*sh.xx + z*z*sh.zz + x*z*sh.xz))/f32(sh.radius*region.size)
	edge := f32(max(abs(x), abs(z)))/f32(0.5*region.size)
	return 1 - r*(1 + f32(sh.ragged)*fbm(x*k, z*k, sh.ragged_wave, 1, 4, seed + 1)) - 4*smoothstep(0.86, 1, edge)
}

// A grid over the region with the sea `sea` metres above where it stood at the start.
grid_make :: proc(n: int, sea: f32) -> ^Grid {
	g := new(Grid)
	g.n, g.d = n, f32(region.size)/f32(n)
	g.z, g.fill, g.area = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	g.uplift, g.soft, g.base = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	g.next, g.jitter, g.seen, g.sea = make([]i32, n*n), make([][2]f32, n*n), make([]bool, n*n), make([]bool, n*n)
	sh, k := region.shape, REFERENCE/region.size
	for c in 0..<n*n {
		x, z := (f64(c%n) + 0.5)*f64(g.d) - region.size/2, (f64(c/n) + 0.5)*f64(g.d) - region.size/2
		s := shore(x, z)
		ix, iz := i32(c%n), i32(c/n)
		g.jitter[c] = [2]f32{hash01(ix, iz, seed + 7 + u32(n)) - 0.5, hash01(ix, iz, seed + 8 + u32(n)) - 0.5}*0.9
		// The beds decide how the rock wears; it also varies a little from one outcrop to the
		// next, which keeps streams from running in straight lines along the grid.
		g.soft[c] = math.exp(0.8*(hash01(ix, iz, seed + 6 + u32(n)) - 0.5))
		g.base[c] = rock_base(x, z, LAND_CELL)
		g.z[c] = -1 - 45*smoothstep(0, 0.35, -s) - sea   // sea bed, uncovered where the sea has fallen far enough
		g.sea[c] = s <= 0 && g.z[c] <= 0
		if s > 0 {
			// The coast barely rises.
			ridge, peak: f32
			if sh.ridge > 0 {
				axis := sh.axis + sh.bend*math.sin(x*k/sh.bend_wave) + sh.wander*f64(fbm(x*k, 0, sh.wander_wave, 1, 2, seed + 2))
				ridge = f32(sh.ridge)*f32(math.exp(-math.pow((z*k - axis)/sh.width, 2)))
			}
			if sh.peak > 0 do peak = f32(sh.peak)*math.exp(-math.pow((1 - s)/f32(sh.peak_width), 2))
			g.uplift[c] = f32(sh.rate)*smoothstep(0, f32(sh.coast), s)*(f32(sh.floor) + ridge + peak)*(1 + f32(sh.lumps)*fbm(x*k, z*k, sh.lumps_wave, 1, 3, seed + 3))
			g.z[c] = 0.5 + 30*s + 25*(1 + fbm(x*k, z*k, 900, 1, 3, seed + 9))
		}
	}
	return g
}

grid_free :: proc(g: ^Grid) {
	delete(g.z); delete(g.fill); delete(g.area); delete(g.uplift); delete(g.soft); delete(g.base)
	delete(g.next); delete(g.jitter); delete(g.seen); delete(g.sea); delete(g.order); delete(g.heap)
	free(g)
}

OFFSETS :: [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

// Distance between the nodes of two cells.
span :: #force_inline proc(g: ^Grid, a, b: int) -> f32 {
	dx := f32(b%g.n - a%g.n) + g.jitter[b].x - g.jitter[a].x
	dz := f32(b/g.n - a/g.n) + g.jitter[b].y - g.jitter[a].y
	return g.d*math.sqrt(dx*dx + dz*dz)
}

Heap_Item :: struct { h: f32, c: i32 }

heap_push :: proc(heap: ^[dynamic]Heap_Item, item: Heap_Item) {
	append(heap, item)
	i := len(heap) - 1
	for i > 0 {
		parent := (i - 1)/2
		if heap[parent].h <= item.h do break
		heap[i] = heap[parent]
		i = parent
	}
	heap[i] = item
}

heap_pop :: proc(heap: ^[dynamic]Heap_Item) -> Heap_Item {
	top := heap[0]
	last := pop(heap)
	n := len(heap)
	if n == 0 do return top
	i := 0
	for {
		child := 2*i + 1
		if child >= n do break
		if child + 1 < n && heap[child + 1].h < heap[child].h do child += 1
		if heap[child].h >= last.h do break
		heap[i] = heap[child]
		i = child
	}
	heap[i] = last
	return top
}

// Decide where water goes. The land is flooded from the shore upward, lowest ground
// first, so every cell is reached along a path that never climbs and hollows fill to
// their rims. Then each cell drains to its steepest lower neighbour, and the land above
// each cell is added up.
route :: proc(g: ^Grid) {
	n := g.n
	clear(&g.order)
	clear(&g.heap)
	for c in 0..<n*n {
		g.seen[c] = g.sea[c]
		g.next[c] = -1
		g.fill[c] = g.z[c]
	}
	for c in 0..<n*n {
		if g.sea[c] do continue
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n || g.sea[y*n + x] {
				g.fill[c] = max(g.z[c], 0.05)
				g.seen[c] = true
				heap_push(&g.heap, {g.fill[c], i32(c)})
				break
			}
		}
	}
	for len(g.heap) > 0 {
		item := heap_pop(&g.heap)
		c := int(item.c)
		append(&g.order, item.c)
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n do continue
			nb := y*n + x
			if g.seen[nb] do continue
			g.seen[nb] = true
			g.fill[nb] = max(g.z[nb], item.h + 0.001*span(g, c, nb))   // a filled hollow keeps a trace of slope
			g.next[nb] = item.c
			heap_push(&g.heap, {g.fill[nb], i32(nb)})
		}
	}
	for ci in g.order {
		c := int(ci)
		best := g.next[c]
		steepest := g.fill[c]/g.d if best < 0 else (g.fill[c] - g.fill[best])/span(g, c, int(best))
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n do continue
			nb := y*n + x
			sea := g.sea[nb]
			s := (g.fill[c] - (0 if sea else g.fill[nb]))/span(g, c, nb)
			if s > steepest do steepest, best = s, (-1 if sea else i32(nb))
		}
		g.next[c] = best
	}
	for c in g.order do g.area[c] = g.d*g.d
	#reverse for c in g.order {
		if r := g.next[c]; r >= 0 do g.area[r] += g.area[c]
	}
}

// How the rock at height z in a cell wears. The rock is read where it will stand in the
// finished world, once the uplift still to come and the sea's rise have moved it, so the
// beds cut here are the beds the blocks show.
wear :: #force_inline proc(g: ^Grid, c: int, z: f32) -> Rock_Law {
	return rocks.law[rock_in(z + g.uplift[c]*g.left - g.rise, g.base[c], ROCK_SIM)]
}

// One step of uplift and cutting, worked from the shore upward so each cell knows where
// the cell below it has ended up. Solving for the new height rather than stepping toward
// it keeps the result steady however long the step. Weak rock is cut faster and holds a
// gentler slope.
erode :: proc(g: ^Grid, dt: f32) {
	for ci in g.order {
		c := int(ci)
		below, run: f32 = 0, g.d
		if r := g.next[c]; r >= 0 do below, run = g.z[r], span(g, c, int(r))
		law := wear(g, c, g.z[c])
		f := ERODE*g.soft[c]*law.erodes*math.sqrt(g.area[c])*dt/run
		z := (g.fill[c] + g.uplift[c]*g.lift*dt + f*below)/(1 + f)
		g.z[c] = clamp(z, below + 0.001*run, below + law.limit*run)
	}
}

creep :: proc(g: ^Grid, dt: f32) {
	n := g.n
	rounds := int(math.ceil(CREEP*dt/(0.2*g.d*g.d)))
	k := CREEP*dt/(f32(rounds)*g.d*g.d)
	old := g.fill   // free to use: route rebuilds it
	for _ in 0..<rounds {
		for c in 0..<n*n do old[c] = max(g.z[c], 0)
		for y in 1..<n - 1 {
			for x in 1..<n - 1 {
				c := y*n + x
				if g.sea[c] do continue
				g.z[c] = max(old[c] + k*wear(g, c, old[c]).creep*(old[c - 1] + old[c + 1] + old[c - n] + old[c + n] - 4*old[c]), 0.02)
			}
		}
	}
}

// The same land at twice the detail. Sea bed the sea has uncovered is land, but land a risen
// sea has covered is not yet drowned again: a history raises the sea only after its last
// refinement.
refine :: proc(coarse: ^Grid, sea: f32) -> ^Grid {
	g := grid_make(coarse.n*2, sea)
	g.left = coarse.left
	n, m := g.n, coarse.n
	for c in 0..<n*n {
		if g.sea[c] do continue
		// Read the coarse land through a gentle warp, so a valley that ran straight along the
		// coarse grid comes out winding. The steps that follow settle it.
		wx, _, _ := noise(f64(c%n)/9, f64(c/n)/9, seed + 11 + u32(n))
		wz, _, _ := noise(f64(c%n)/9, f64(c/n)/9, seed + 12 + u32(n))
		u, v := (f32(c%n) + 0.5)/2 - 0.5 + 1.6*(wx - 0.5), (f32(c/n) + 0.5)/2 - 0.5 + 1.6*(wz - 0.5)
		x0, y0 := clamp(int(math.floor(u)), 0, m - 2), clamp(int(math.floor(v)), 0, m - 2)
		tu, tv := clamp(u - f32(x0), 0, 1), clamp(v - f32(y0), 0, 1)
		k := y0*m + x0
		z := math.lerp(math.lerp(coarse.z[k], coarse.z[k + 1], tu), math.lerp(coarse.z[k + m], coarse.z[k + m + 1], tu), tv)
		// A little roughness, so the finer streams have something to start from.
		g.z[c] = max(z, 0.3) + 0.03*g.d*(hash01(i32(c%n), i32(c/n), seed + 10) - 0.5)
	}
	grid_free(coarse)
	return g
}

land_form :: proc() {
	started := time.now()
	history := region.history
	sea, rise: f32   // metres the sea has risen so far, and will in all
	for p in history do rise += p.sea
	g := grid_make(int(region.size)/history[0].cell, 0)
	for p in history do g.left += p.steps*p.years*p.uplift
	for p in history {
		for g.d > f32(p.cell) do g = refine(g, sea)
		// Where the sea moves, what lies below it now is sea bed and what it leaves is land: a
		// rise floods the valley mouths into inlets.
		if p.sea != 0 {
			for c in 0..<g.n*g.n {
				g.z[c] -= p.sea
				g.sea[c] = g.z[c] <= 0
			}
			sea += p.sea
		}
		g.lift, g.rise = p.uplift, rise - sea
		for _ in 0..<int(p.steps) {
			route(g)
			erode(g, p.years)
			creep(g, p.years)
			g.left -= p.years*p.uplift
		}
	}
	route(g)
	n := g.n
	if len(g.order) == 0 {
		fmt.eprintfln("no land: the %s island's history wore it away below the sea", region.kind)
		os.exit(1)
	}

	// How long a step cut at the coast takes to climb to the head of the farthest stream
	// (landforms.md, D3): against it, the length of the last phase says how finished the land is.
	climb := make([]f32, n*n, context.temp_allocator)
	response: f32
	for ci in g.order {
		c := int(ci)
		if r := g.next[c]; r >= 0 do climb[c] = climb[r] + span(g, c, int(r))/(ERODE*g.soft[c]*wear(g, c, g.z[c]).erodes*math.sqrt(g.area[c]))
		if g.area[c] >= CHANNEL_AREA do response = max(response, climb[c])
	}
	last: Phase(f32)
	for p in history do if p.steps > 0 do last = p

	land.n, land.grid, land.z[0] = n, g, g.z
	for level in 1..<3 {
		m := n >> uint(level)
		fine := land.z[level - 1]
		land.z[level] = make([]f32, m*m)
		for c in 0..<m*m {
			k := (c/m)*2*(m*2) + (c%m)*2
			land.z[level][c] = (fine[k] + fine[k + 1] + fine[k + m*2] + fine[k + m*2 + 1])/4
		}
	}
	land.slope, land.wet = make([]f32, n*n), make([]f32, n*n)
	highest: f32
	for y in 1..<n - 1 {
		for x in 1..<n - 1 {
			c := y*n + x
			dx, dz := g.z[c + 1] - g.z[c - 1], g.z[c + n] - g.z[c - n]
			land.slope[c] = math.sqrt(dx*dx + dz*dz)/(2*g.d)
			// Wetness follows the land draining to a place: none on a ridge, full in a valley floor.
			if !g.sea[c] do land.wet[c] = clamp((math.log10(g.area[c]) - 2.6)/2.4, 0, 1)
			highest = max(highest, g.z[c])
		}
	}
	// Spread wetness out from the channels into the ground beside them.
	scratch := make([]f32, n*n)
	defer delete(scratch)
	for _ in 0..<3 {
		copy(scratch, land.wet)
		for y in 1..<n - 1 {
			for x in 1..<n - 1 {
				c := y*n + x
				land.wet[c] = (scratch[c]*2 + scratch[c - 1] + scratch[c + 1] + scratch[c - n] + scratch[c + n])/6
			}
		}
	}
	fmt.printfln("land formed in %.2f s: %d land cells, highest point %.0f m", time.duration_seconds(time.since(started)), len(g.order), highest)
	fmt.printfln("a step cut at the coast climbs to the farthest stream head in %.0f kyr; the last phase ran %.0f kyr, %.2f of that", response/1000, last.steps*last.years/1000, last.steps*last.years/response)
	land_stats(g)
}

// How steep the land came out: the share of land steeper than 45° and the median slope,
// each cell taken by its steepest neighbour, and the tallest face, followed down the
// drainage while it stays steeper than 45°.
land_stats :: proc(g: ^Grid) {
	n := g.n
	slopes := make([dynamic]f32, context.temp_allocator)
	face, top, foot, steep := f32(0), 0, 0, 0
	kinds: [Mat]int
	for ci in g.order {
		c := int(ci)
		kinds[rock_in(g.z[c] - 0.5, g.base[c], ROCK_SIM)] += 1
		if c%n == 0 || c/n == 0 || c%n == n - 1 || c/n == n - 1 do continue
		most: f32
		for o in OFFSETS do most = max(most, (g.z[c] - max(g.z[c + o.y*n + o.x], 0))/(g.d*math.sqrt(f32(o.x*o.x + o.y*o.y))))
		append(&slopes, most)
		if most > 1 do steep += 1
		drop, at := f32(0), c
		for ; g.next[at] >= 0 && (g.z[at] - g.z[g.next[at]])/span(g, at, int(g.next[at])) >= 1; at = int(g.next[at]) {
			drop += g.z[at] - g.z[g.next[at]]
		}
		if drop > face do face, top, foot = drop, c, at
	}
	slice.sort(slopes[:])
	at :: proc(g: ^Grid, c: int) -> [3]f32 { return {(f32(c%g.n) + 0.5)*g.d - f32(region.size/2), g.z[c], (f32(c/g.n) + 0.5)*g.d - f32(region.size/2)} }
	fmt.printfln("steeper than 45°: %.1f%% of land; median slope %.0f°; tallest face %.0f m, from %.0f to %.0f",
		100*f32(steep)/f32(len(slopes)), math.to_degrees(math.atan(slopes[len(slopes)/2])), face, at(g, top), at(g, foot))
	fmt.print("rock at the surface:")
	for k, m in kinds do if k > 0 do fmt.printf(" %v %.0f%%", m, 100*f32(k)/f32(len(g.order)))
	fmt.println()
	free_all(context.temp_allocator)
}

// Smooth value of one of the land's grids at a point in the world. The curve through each
// four values never rises past its neighbours (Steffen 1990), so the edge of a face does not
// bulge above the face's top.
land_at :: proc(v: []f32, n: int, x, z: f64) -> f32 {
	d := region.size/f64(n)
	u, w := (x + region.size/2)/d - 0.5, (z + region.size/2)/d - 0.5
	fu, fw := math.floor(u), math.floor(w)
	iu, iw := int(fu), int(fw)
	curve :: #force_inline proc(p: [4]f32, t: f32) -> f32 {
		slope :: #force_inline proc(a, b: f32) -> f32 {   // at a point between rises a and b
			if a*b <= 0 do return 0
			return math.sign(a)*min(abs(a), abs(b), 0.25*abs(a + b))*2
		}
		s0, s1, s2 := p[1] - p[0], p[2] - p[1], p[3] - p[2]
		m1, m2 := slope(s0, s1), slope(s1, s2)
		return p[1] + t*(m1 + t*(3*s1 - 2*m1 - m2 + t*(m1 + m2 - 2*s1)))
	}
	rows: [4]f32
	for j in 0..<4 {
		row := clamp(iw + j - 1, 0, n - 1)*n
		p: [4]f32
		for i in 0..<4 do p[i] = v[row + clamp(iu + i - 1, 0, n - 1)]
		rows[j] = curve(p, f32(u - fu))
	}
	return curve(rows, f32(w - fw))
}

// The finest grid's cell under a point.
land_cell :: proc(x, z: f64) -> int {
	return clamp(int((z + region.size/2)/LAND_CELL), 0, land.n - 1)*land.n + clamp(int((x + region.size/2)/LAND_CELL), 0, land.n - 1)
}

// Fields the map can paint over the relief, by name (--overlay=): the value at a point,
// 0 to 1, and the colours at its two ends; or a material, painted in its own colour.
Overlay :: struct {
	name:   string,
	at:     proc(x, z: f64) -> f32,
	lo, hi: [3]f32,
	kinds:  bool,
}

OVERLAYS := [?]Overlay{
	{"wetness", proc(x, z: f64) -> f32 { return land_at(land.wet, land.n, x, z) }, {0.90, 0.80, 0.50}, {0.05, 0.45, 0.40}, false},
	{"slope", proc(x, z: f64) -> f32 { return land_at(land.slope, land.n, x, z)/1.2 }, {0.95, 0.95, 0.90}, {0.65, 0.05, 0.05}, false},
	{"drainage", proc(x, z: f64) -> f32 { return (math.log10(land.grid.area[land_cell(x, z)]) - 2.4)/5 }, {0.95, 0.95, 0.90}, {0.05, 0.10, 0.45}, false},
	{"uplift", proc(x, z: f64) -> f32 { return land.grid.uplift[land_cell(x, z)]/f32(1.3*region.shape.rate) }, {0.20, 0.25, 0.45}, {0.95, 0.85, 0.30}, false},
	{"rock", proc(x, z: f64) -> f32 { return f32(rock(x, f64(land_at(land.z[0], land.n, x, z)) - 0.5, z, 8)) }, {}, {}, true},
}

// A material's colour as the map shows it.
map_colour :: proc(m: Mat) -> [3]f32 {
	c := MATERIALS[m].colour
	c = {math.sqrt(c.r), math.sqrt(c.g), math.sqrt(c.b)}*1.2
	grey := (c.r + c.g + c.b)/3
	return grey + (c - grey)*3   // hues told apart more easily than on the ground
}

// A picture of the land from above, eight metres to the pixel: relief shaded from the
// north-west, sea by depth, and the rivers. With an overlay, the land is painted by that
// field instead.
land_map :: proc(path, overlay: string) {
	SIZE :: 1024
	paint: ^Overlay
	for &o in OVERLAYS do if o.name == overlay do paint = &o
	if overlay != "" && paint == nil {
		fmt.eprint("no overlay named", overlay, "; there are:")
		for o in OVERLAYS do fmt.eprint("", o.name)
		fmt.eprintln()
		return
	}
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	for py in 0..<SIZE {
		for px in 0..<SIZE {
			x, z := (f64(px) + 0.5)*region.size/SIZE - region.size/2, (f64(py) + 0.5)*region.size/SIZE - region.size/2
			h := land_at(land.z[0], land.n, x, z)
			gx := land_at(land.z[0], land.n, x + 8, z) - land_at(land.z[0], land.n, x - 8, z)
			gz := land_at(land.z[0], land.n, x, z + 8) - land_at(land.z[0], land.n, x, z - 8)
			shade := clamp(0.75 + 0.9*(-gx - gz)/16, 0.25, 1.3)
			col: [3]f32
			if h <= 0 {
				col = math.lerp([3]f32{0.35, 0.62, 0.80}, [3]f32{0.08, 0.22, 0.42}, clamp(-h/30, 0, 1))
			} else {
				if paint != nil && paint.kinds {
					col = map_colour(Mat(paint.at(x, z)))*shade
				} else if paint != nil {
					col = math.lerp(paint.lo, paint.hi, clamp(paint.at(x, z), 0, 1))*shade
				} else {
					t := clamp(h/450, 0, 1)
					col = math.lerp(math.lerp([3]f32{0.42, 0.60, 0.30}, [3]f32{0.62, 0.56, 0.38}, clamp(t*2, 0, 1)), [3]f32{0.92, 0.92, 0.90}, clamp(t*2 - 1, 0, 1))*shade
					// Rock shows where the ground is near the steepest its rock holds, as on the ground.
					bed := rock(x, f64(h) - 0.5, z, 8)
					bare := smoothstep(0.6, 0.8, land_at(land.slope, land.n, x, z)/rocks.law[bed].limit)
					col = math.lerp(col, map_colour(bed)*shade, 0.8*bare)
				}
				if r, near := river_near(f32(x), f32(z)); near && r.d < max(r.half, 4) do col = {0.10, 0.30, 0.75}
			}
			for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
		}
	}
	write_png(path, pixels, SIZE, SIZE, false)
}
