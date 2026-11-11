package main

import "core:fmt"
import "core:math"
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

LAND_N    :: 512                 // cells along a side of the finished land
LAND_CELL :: 16                  // metres
LAND_SIZE :: LAND_N*LAND_CELL    // the region, centred on the origin; its rim is always sea

UPLIFT :: 0.0006    // m/yr at the heart of the island
ERODE  :: 1.3e-5    // how fast water cuts: per year, times root of drainage area, times slope
CREEP  :: 0.012     // m²/yr of soil creep, which rounds hilltops, on the weakest rock
DROWN  :: 8         // metres the sea rises at the end, flooding the valley mouths into inlets

CHANNEL_AREA :: 120_000   // m² of land that must drain through a cell before it carries a stream

// Steps and years per step at each grid size, coarsest first.
SCHEDULE :: [3][2]f32{{160, 20000}, {50, 6000}, {30, 3000}}

Grid :: struct {
	n:      int,
	d:      f32,            // cell size, metres
	z:      []f32,          // ground elevation
	fill:   []f32,          // elevation once hollows are filled: the surface water runs down
	next:   []i32,          // the cell each land cell drains into, or -1 for the sea
	area:   []f32,          // land draining through each cell, m²
	uplift: []f32,          // m/yr; zero marks sea
	soft:   []f32,          // how easily the rock erodes, around 1, from one outcrop to the next
	base:   []f32,          // height of the rock stack's base under each cell (rock.odin)
	jitter: [][2]f32,       // where each cell's node sits in its square, so flow has no favourite compass direction
	seen:   []bool,
	order:  [dynamic]i32,   // land cells from the shore upward
	heap:   [dynamic]Heap_Item,
}

// The finished land, read by the generator.
Land :: struct {
	z:     [3][]f32,   // elevation at 16, 32 and 64 m cells
	slope: []f32,      // steepness
	wet:   []f32,      // 0 on ridges to 1 in valley floors
	grid:  ^Grid,      // the finest grid, kept for the river network
}

land: Land

// Positive inland, negative at sea.
shore :: proc(x, z: f64) -> f32 {
	r := f32(math.sqrt(x*x*0.8 + z*z*1.25 + x*z*0.5))/(0.40*LAND_SIZE)
	edge := f32(max(abs(x), abs(z)))/(0.5*LAND_SIZE)
	return 1 - r*(1 + 0.42*fbm(x, z, 3000, 1, 4, seed + 1)) - 4*smoothstep(0.86, 1, edge)
}

grid_make :: proc(n: int) -> ^Grid {
	g := new(Grid)
	g.n, g.d = n, f32(LAND_SIZE)/f32(n)
	g.z, g.fill, g.area = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	g.uplift, g.soft, g.base = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	g.next, g.jitter, g.seen = make([]i32, n*n), make([][2]f32, n*n), make([]bool, n*n)
	for c in 0..<n*n {
		x, z := (f64(c%n) + 0.5)*f64(g.d) - LAND_SIZE/2, (f64(c/n) + 0.5)*f64(g.d) - LAND_SIZE/2
		s := shore(x, z)
		ix, iz := i32(c%n), i32(c/n)
		g.jitter[c] = [2]f32{hash01(ix, iz, seed + 7 + u32(n)) - 0.5, hash01(ix, iz, seed + 8 + u32(n)) - 0.5}*0.9
		// The beds decide how the rock wears; it also varies a little from one outcrop to the
		// next, which keeps streams from running in straight lines along the grid.
		g.soft[c] = math.exp(0.8*(hash01(ix, iz, seed + 6 + u32(n)) - 0.5))
		g.base[c] = rock_base(x, z, LAND_CELL)
		if s <= 0 {
			g.z[c] = -1 - 45*smoothstep(0, 0.35, -s)   // sea bed
		} else {
			// The island rises fastest along a range that runs its length north of centre, so
			// the south side is a long slope with room for rivers. The coast barely rises.
			axis := -900 + 450*math.sin(x/1700) + 350*f64(fbm(x, 0, 2500, 1, 2, seed + 2))
			range := f32(math.exp(-math.pow((z - axis)/1000, 2)))
			g.uplift[c] = UPLIFT*smoothstep(0, 0.3, s)*(0.30 + 0.95*range)*(1 + 0.4*fbm(x, z, 2200, 1, 3, seed + 3))
			g.z[c] = 0.5 + 30*s + 25*(1 + fbm(x, z, 900, 1, 3, seed + 9))
		}
	}
	return g
}

grid_free :: proc(g: ^Grid) {
	delete(g.z); delete(g.fill); delete(g.area); delete(g.uplift); delete(g.soft); delete(g.base)
	delete(g.next); delete(g.jitter); delete(g.seen); delete(g.order); delete(g.heap)
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
		g.seen[c] = g.uplift[c] == 0
		g.next[c] = -1
		g.fill[c] = g.z[c]
	}
	for c in 0..<n*n {
		if g.uplift[c] == 0 do continue
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n || g.uplift[y*n + x] == 0 {
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
			sea := g.uplift[nb] == 0
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
// finished world, once the uplift still to come (`left` years of it) and the sea's rise
// have moved it, so the beds cut here are the beds the blocks show.
wear :: #force_inline proc(g: ^Grid, c: int, z, left: f32) -> Rock_Law {
	return rocks.law[rock_in(z + g.uplift[c]*left - DROWN, g.base[c], ROCK_SIM)]
}

// One step of uplift and cutting, worked from the shore upward so each cell knows where
// the cell below it has ended up. Solving for the new height rather than stepping toward
// it keeps the result steady however long the step. Weak rock is cut faster and holds a
// gentler slope.
erode :: proc(g: ^Grid, dt, left: f32) {
	for ci in g.order {
		c := int(ci)
		below, run: f32 = 0, g.d
		if r := g.next[c]; r >= 0 do below, run = g.z[r], span(g, c, int(r))
		law := wear(g, c, g.z[c], left)
		f := ERODE*g.soft[c]*law.erodes*math.sqrt(g.area[c])*dt/run
		z := (g.fill[c] + g.uplift[c]*dt + f*below)/(1 + f)
		g.z[c] = clamp(z, below + 0.001*run, below + law.limit*run)
	}
}

creep :: proc(g: ^Grid, dt, left: f32) {
	n := g.n
	rounds := int(math.ceil(CREEP*dt/(0.2*g.d*g.d)))
	k := CREEP*dt/(f32(rounds)*g.d*g.d)
	old := g.fill   // free to use: route rebuilds it
	for _ in 0..<rounds {
		for c in 0..<n*n do old[c] = max(g.z[c], 0)
		for y in 1..<n - 1 {
			for x in 1..<n - 1 {
				c := y*n + x
				if g.uplift[c] == 0 do continue
				g.z[c] = max(old[c] + k*wear(g, c, old[c], left).creep*(old[c - 1] + old[c + 1] + old[c - n] + old[c + n] - 4*old[c]), 0.02)
			}
		}
	}
}

// The same land at twice the detail.
refine :: proc(coarse: ^Grid) -> ^Grid {
	g := grid_make(coarse.n*2)
	n, m := g.n, coarse.n
	for c in 0..<n*n {
		if g.uplift[c] == 0 do continue
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
	g := grid_make(LAND_N/4)
	schedule := SCHEDULE
	left: f32   // years still to run
	for stage in schedule do left += stage[0]*stage[1]
	for stage, level in schedule {
		for _ in 0..<int(stage[0]) {
			route(g)
			erode(g, stage[1], left)
			creep(g, stage[1], left)
			left -= stage[1]
		}
		if level < len(schedule) - 1 do g = refine(g)
	}
	// The sea rises. Whatever is below it now is sea bed, and valley mouths become inlets.
	for c in 0..<g.n*g.n {
		g.z[c] -= DROWN
		if g.z[c] <= 0 do g.uplift[c] = 0
	}
	route(g)
	n := g.n

	land.grid, land.z[0] = g, g.z
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
			if g.uplift[c] > 0 do land.wet[c] = clamp((math.log10(g.area[c]) - 2.6)/2.4, 0, 1)
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
	at :: proc(g: ^Grid, c: int) -> [3]f32 { return {(f32(c%g.n) + 0.5)*g.d - LAND_SIZE/2, g.z[c], (f32(c/g.n) + 0.5)*g.d - LAND_SIZE/2} }
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
	d := f64(LAND_SIZE)/f64(n)
	u, w := (x + LAND_SIZE/2)/d - 0.5, (z + LAND_SIZE/2)/d - 0.5
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
	return clamp(int((z + LAND_SIZE/2)/LAND_CELL), 0, LAND_N - 1)*LAND_N + clamp(int((x + LAND_SIZE/2)/LAND_CELL), 0, LAND_N - 1)
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
	{"wetness", proc(x, z: f64) -> f32 { return land_at(land.wet, LAND_N, x, z) }, {0.90, 0.80, 0.50}, {0.05, 0.45, 0.40}, false},
	{"slope", proc(x, z: f64) -> f32 { return land_at(land.slope, LAND_N, x, z)/1.2 }, {0.95, 0.95, 0.90}, {0.65, 0.05, 0.05}, false},
	{"drainage", proc(x, z: f64) -> f32 { return (math.log10(land.grid.area[land_cell(x, z)]) - 2.4)/5 }, {0.95, 0.95, 0.90}, {0.05, 0.10, 0.45}, false},
	{"uplift", proc(x, z: f64) -> f32 { return land.grid.uplift[land_cell(x, z)]/(1.3*UPLIFT) }, {0.20, 0.25, 0.45}, {0.95, 0.85, 0.30}, false},
	{"rock", proc(x, z: f64) -> f32 { return f32(rock(x, f64(land_at(land.z[0], LAND_N, x, z)) - 0.5, z, 8)) }, {}, {}, true},
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
			x, z := (f64(px) + 0.5)*LAND_SIZE/SIZE - LAND_SIZE/2, (f64(py) + 0.5)*LAND_SIZE/SIZE - LAND_SIZE/2
			h := land_at(land.z[0], LAND_N, x, z)
			gx := land_at(land.z[0], LAND_N, x + 8, z) - land_at(land.z[0], LAND_N, x - 8, z)
			gz := land_at(land.z[0], LAND_N, x, z + 8) - land_at(land.z[0], LAND_N, x, z - 8)
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
					bare := smoothstep(0.6, 0.8, land_at(land.slope, LAND_N, x, z)/rocks.law[bed].limit)
					col = math.lerp(col, map_colour(bed)*shade, 0.8*bare)
				}
				if r, near := river_near(f32(x), f32(z)); near && r.d < max(r.half, 4) do col = {0.10, 0.30, 0.75}
			}
			for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
		}
	}
	write_png(path, pixels, SIZE, SIZE, false)
}
