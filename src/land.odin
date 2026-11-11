package main

import "core:fmt"
import "core:math"
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
CREEP  :: 0.012     // m²/yr of soil creep, which rounds hilltops
REPOSE :: 0.80      // the steepest slope a hillside holds
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
	soft:   []f32,          // how easily the rock erodes, around 1
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
	return 1 - r*(1 + 0.42*fbm(x, z, 3000, 1, 4, SEED + 1)) - 4*smoothstep(0.86, 1, edge)
}

grid_make :: proc(n: int) -> ^Grid {
	g := new(Grid)
	g.n, g.d = n, f32(LAND_SIZE)/f32(n)
	g.z, g.fill, g.area = make([]f32, n*n), make([]f32, n*n), make([]f32, n*n)
	g.uplift, g.soft = make([]f32, n*n), make([]f32, n*n)
	g.next, g.jitter, g.seen = make([]i32, n*n), make([][2]f32, n*n), make([]bool, n*n)
	for c in 0..<n*n {
		x, z := (f64(c%n) + 0.5)*f64(g.d) - LAND_SIZE/2, (f64(c/n) + 0.5)*f64(g.d) - LAND_SIZE/2
		s := shore(x, z)
		ix, iz := i32(c%n), i32(c/n)
		g.jitter[c] = [2]f32{hash01(ix, iz, SEED + 7 + u32(n)) - 0.5, hash01(ix, iz, SEED + 8 + u32(n)) - 0.5}*0.9
		// Rock varies in broad bands and from one outcrop to the next. The fine variation is
		// what keeps streams from running in straight lines along the grid.
		g.soft[c] = math.exp(0.45*fbm(x, z, 1100, 1, 3, SEED + 5) + 1.4*(hash01(ix, iz, SEED + 6 + u32(n)) - 0.5))
		if s <= 0 {
			g.z[c] = -1 - 45*smoothstep(0, 0.35, -s)   // sea bed
		} else {
			// The island rises fastest along a range that runs its length north of centre, so
			// the south side is a long slope with room for rivers. The coast barely rises.
			axis := -900 + 450*math.sin(x/1700) + 350*f64(fbm(x, 0, 2500, 1, 2, SEED + 2))
			range := f32(math.exp(-math.pow((z - axis)/1000, 2)))
			g.uplift[c] = UPLIFT*smoothstep(0, 0.3, s)*(0.30 + 0.95*range)*(1 + 0.4*fbm(x, z, 2200, 1, 3, SEED + 3))
			g.z[c] = 0.5 + 30*s + 25*(1 + fbm(x, z, 900, 1, 3, SEED + 9))
		}
	}
	return g
}

grid_free :: proc(g: ^Grid) {
	delete(g.z); delete(g.fill); delete(g.area); delete(g.uplift); delete(g.soft)
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

// One step of uplift and cutting, worked from the shore upward so each cell knows where
// the cell below it has ended up. Solving for the new height rather than stepping toward
// it keeps the result steady however long the step.
erode :: proc(g: ^Grid, dt: f32) {
	for ci in g.order {
		c := int(ci)
		below, run: f32 = 0, g.d
		if r := g.next[c]; r >= 0 do below, run = g.z[r], span(g, c, int(r))
		f := ERODE*g.soft[c]*math.sqrt(g.area[c])*dt/run
		z := (g.fill[c] + g.uplift[c]*dt + f*below)/(1 + f)
		g.z[c] = clamp(z, below + 0.001*run, below + REPOSE*run)
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
				if g.uplift[c] == 0 do continue
				g.z[c] = max(old[c] + k*(old[c - 1] + old[c + 1] + old[c - n] + old[c + n] - 4*old[c]), 0.02)
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
		wx, _, _ := noise(f64(c%n)/9, f64(c/n)/9, SEED + 11 + u32(n))
		wz, _, _ := noise(f64(c%n)/9, f64(c/n)/9, SEED + 12 + u32(n))
		u, v := (f32(c%n) + 0.5)/2 - 0.5 + 1.6*(wx - 0.5), (f32(c/n) + 0.5)/2 - 0.5 + 1.6*(wz - 0.5)
		x0, y0 := clamp(int(math.floor(u)), 0, m - 2), clamp(int(math.floor(v)), 0, m - 2)
		tu, tv := clamp(u - f32(x0), 0, 1), clamp(v - f32(y0), 0, 1)
		k := y0*m + x0
		z := math.lerp(math.lerp(coarse.z[k], coarse.z[k + 1], tu), math.lerp(coarse.z[k + m], coarse.z[k + m + 1], tu), tv)
		// A little roughness, so the finer streams have something to start from.
		g.z[c] = max(z, 0.3) + 0.03*g.d*(hash01(i32(c%n), i32(c/n), SEED + 10) - 0.5)
	}
	grid_free(coarse)
	return g
}

land_form :: proc() {
	started := time.now()
	g := grid_make(LAND_N/4)
	schedule := SCHEDULE
	for stage, level in schedule {
		for _ in 0..<int(stage[0]) {
			route(g)
			erode(g, stage[1])
			creep(g, stage[1])
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
	fmt.printfln("land formed in %.1f s: %d land cells, highest point %.0f m", time.duration_seconds(time.since(started)), len(g.order), highest)
}

// Smooth value of one of the land's grids at a point in the world.
land_at :: proc(v: []f32, n: int, x, z: f64) -> f32 {
	d := f64(LAND_SIZE)/f64(n)
	u, w := (x + LAND_SIZE/2)/d - 0.5, (z + LAND_SIZE/2)/d - 0.5
	fu, fw := math.floor(u), math.floor(w)
	iu, iw := int(fu), int(fw)
	weights :: proc(t: f32) -> [4]f32 {
		t2, t3 := t*t, t*t*t
		return {-0.5*t3 + t2 - 0.5*t, 1.5*t3 - 2.5*t2 + 1, -1.5*t3 + 2*t2 + 0.5*t, 0.5*t3 - 0.5*t2}
	}
	a, b := weights(f32(u - fu)), weights(f32(w - fw))
	sum: f32
	for j in 0..<4 {
		row := clamp(iw + j - 1, 0, n - 1)*n
		r: f32
		for i in 0..<4 do r += a[i]*v[row + clamp(iu + i - 1, 0, n - 1)]
		sum += b[j]*r
	}
	return sum
}

// A picture of the land from above, eight metres to the pixel: relief shaded from the
// north-west, sea by depth, and the rivers.
land_map :: proc(path: string) {
	SIZE :: 1024
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
				t := clamp(h/450, 0, 1)
				col = math.lerp(math.lerp([3]f32{0.42, 0.60, 0.30}, [3]f32{0.62, 0.56, 0.38}, clamp(t*2, 0, 1)), [3]f32{0.92, 0.92, 0.90}, clamp(t*2 - 1, 0, 1))*shade
				if r, near := river_near(f32(x), f32(z)); near && r.d < max(r.half, 4) do col = {0.10, 0.30, 0.75}
			}
			for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
		}
	}
	write_png(path, pixels, SIZE, SIZE, false)
}
