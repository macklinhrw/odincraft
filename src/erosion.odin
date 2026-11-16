package main

import "base:intrinsics"
import "core:math"
import "core:slice"

// The forming's simulation on one grid (land_form in land.odin runs it coarse to fine): where
// water goes from each cell (route), uplift and the cutting of rivers through rock of each strength
// (erode), creep on slopes, the sea cutting the coast back and coral building reef up to it
// (coast), and the step to a finer grid (refine). See docs/adr/0003 and docs/foundations/landforms.md.

OFFSETS :: [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

// Distance between the nodes of a cell and a neighbour: every caller's is the cell it drains to or
// the next on a path. The neighbour's row is told from how far on it lies, as a grid is at least
// three cells across, which is faster than dividing for it.
span :: #force_inline proc(g: ^Grid, a, b: int) -> f32 {
	y := int(b - a > 1) - int(b - a < -1)
	return step(g, a, {b - a - y*g.n, y})
}

// The same to the neighbour an offset away, which the grid holds.
step :: #force_inline proc(g: ^Grid, a: int, o: [2]int) -> f32 #no_bounds_check {
	b := a + o.y*g.n + o.x
	dx := f32(o.x) + g.jitter[b].x - g.jitter[a].x
	dz := f32(o.y) + g.jitter[b].y - g.jitter[a].y
	return g.d*math.sqrt(dx*dx + dz*dz)
}

// Whether a cell off the grid's edge has the sea beside it.
beside_sea :: #force_inline proc(sea: []bool, c, n: int) -> bool #no_bounds_check {
	return bool(u8(sea[c - n - 1]) | u8(sea[c - n]) | u8(sea[c - n + 1]) | u8(sea[c - 1]) | u8(sea[c + 1]) | u8(sea[c + n - 1]) | u8(sea[c + n]) | u8(sea[c + n + 1]))
}

// A binary heap of cells, the lowest first: the flood's, the tracer's and the distance to the sea's.
// The items are kept from 1 to n, so a node's children share a pair of slots, and the slot after
// the last holds HIGHEST, so a missing right child is never the smaller. Every height and cost put
// in is a float no lower than +0, and such floats stand in the order of their bits read as
// integers, which are compared faster: the heap pops what comparing them as floats did.
Heap_Item :: struct { h: f32, c: i32 }
Heap :: struct { items: [dynamic]Heap_Item, n: int }
HIGHEST :: Heap_Item{max(f32), -1}

@(private="file")
bits :: #force_inline proc(h: f32) -> u32 { return transmute(u32)h }

heap_clear :: proc(heap: ^Heap) { heap.n = 0 }

heap_push :: proc(heap: ^Heap, item: Heap_Item) #no_bounds_check {
	heap.n += 1
	for len(heap.items) < heap.n + 2 do append(&heap.items, HIGHEST)
	h := heap.items[:]
	h[heap.n + 1] = HIGHEST
	i := heap.n
	for i > 1 {
		parent := i/2
		if bits(h[parent].h) <= bits(item.h) do break
		h[i] = h[parent]
		i = parent
	}
	h[i] = item
}

// The lowest item out. The hole it leaves is passed down the smaller child, the left on a tie, to
// the bottom, and the last item is put back up that path past every item no lower than it: the
// heap comes out as sifting the last item down from the top would leave it, item for item, which
// the order of the land's cells depends on, with no branch on which child is smaller.
heap_pop :: proc(heap: ^Heap) -> Heap_Item #no_bounds_check {
	h := heap.items[:]
	top, last := h[1], h[heap.n]
	h[heap.n] = HIGHEST
	heap.n -= 1
	n := heap.n
	if n == 0 do return top
	i := 1
	for child := 2; child <= n; child = 2*i {
		child += int(bits(h[child + 1].h) < bits(h[child].h))
		h[i] = h[child]
		i = child
	}
	for i > 1 && bits(h[i/2].h) >= bits(last.h) {
		h[i] = h[i/2]
		i = i/2
	}
	h[i] = last
	return top
}

// Decide where water goes. The land is flooded from the shore upward, lowest ground
// first, so every cell is reached along a path that never climbs and hollows fill to
// their rims. The one exception is a fallen crater: its floor is broken rock and ash that
// the water sinks into, as on Aogashima's, so the flood starts again from its lowest point
// and the crater stays a closed, dry hollow. Then each cell drains to its steepest lower
// neighbour, and the land above each cell is added up.
SINK :: -2   // in `next`: the water sinks into the ground here
route :: proc(g: ^Grid) #no_bounds_check {
	n := g.n
	clear(&g.order)
	heap_clear(&g.heap)
	copy(g.seen, g.sea)
	slice.fill(g.next, -1)
	copy(g.fill, g.z)
	// The flood starts from the land beside the sea or the grid's edge, row by row. Away from the edge
	// eight cells are read at once, a byte each in one word, so open sea and the land away from the
	// shore are passed eight at a time.
	seed :: #force_inline proc(g: ^Grid, c: int) {
		g.fill[c] = max(g.z[c], 0.05)
		g.seen[c] = true
		heap_push(&g.heap, {g.fill[c], i32(c)})
	}
	eight :: #force_inline proc(sea: []bool, c: int) -> u64 #no_bounds_check { return intrinsics.unaligned_load((^u64)(&sea[c])) }
	for y in 0..<n {
		for x := 0; x < n; {
			c := y*n + x
			if y > 0 && y < n - 1 && x > 0 && x + 9 <= n {
				shore := ~eight(g.sea, c) & 0x0101010101010101 & (eight(g.sea, c - n - 1) | eight(g.sea, c - n) | eight(g.sea, c - n + 1) | eight(g.sea, c - 1) |
					eight(g.sea, c + 1) | eight(g.sea, c + n - 1) | eight(g.sea, c + n) | eight(g.sea, c + n + 1))
				for ; shore != 0; shore &= shore - 1 do seed(g, c + int(intrinsics.count_trailing_zeros(shore))/8)
				x += 8
				continue
			}
			if !g.sea[c] && (x == 0 || y == 0 || x == n - 1 || y == n - 1 || beside_sea(g.sea, c, n)) do seed(g, c)
			x += 1
		}
	}
	sinks: [dynamic]i32
	defer delete(sinks)
	for v in region.vents do if v.fallen {
		lowest := -1
		x0, y0, r := int((v.at.x + region.size/2)/f64(g.d)), int((v.at.y + region.size/2)/f64(g.d)), int(v.crater/g.d)
		for y in max(y0 - r, 0)..=min(y0 + r, n - 1) do for x in max(x0 - r, 0)..=min(x0 + r, n - 1) {
			if c := y*n + x; (x - x0)*(x - x0) + (y - y0)*(y - y0) <= r*r && !g.seen[c] && (lowest < 0 || g.z[c] < g.z[lowest]) do lowest = c
		}
		if lowest < 0 do continue
		g.seen[lowest] = true
		heap_push(&g.heap, {g.fill[lowest], i32(lowest)})
		append(&sinks, i32(lowest))
	}
	offsets, ahead := OFFSETS, [8]int{}
	for o, k in offsets do ahead[k] = o.y*n + o.x
	for g.heap.n > 0 {
		item := heap_pop(&g.heap)
		c := int(item.c)
		append(&g.order, item.c)
		// The neighbours not yet reached, a bit each in the order of OFFSETS, read before any is
		// marked (none is another's), so the loop over them branches once for each it reaches.
		y := c/n
		x := c - y*n
		open: u32
		if x > 0 && y > 0 && x < n - 1 && y < n - 1 {
			for k in 0..<8 do open |= u32(!g.seen[c + ahead[k]]) << u32(k)
		} else {
			for o, k in offsets do if x + o.x >= 0 && y + o.y >= 0 && x + o.x < n && y + o.y < n do open |= u32(!g.seen[c + ahead[k]]) << u32(k)
		}
		for ; open != 0; open &= open - 1 {
			k := intrinsics.count_trailing_zeros(open)
			nb := c + ahead[k]
			g.seen[nb] = true
			g.fill[nb] = max(g.z[nb], item.h + 0.001*step(g, c, offsets[k]))   // a filled hollow keeps a trace of slope
			g.next[nb] = item.c
			heap_push(&g.heap, {g.fill[nb], i32(nb)})
		}
	}
	// Every cell flooded is land, and each finds its own way down, whatever the order.
	shared(n, rows(n), g, proc(g: ^Grid, lo, hi: int) {
		n := g.n
		#no_bounds_check for y in lo..<hi do for x in 0..<n {
			c := y*n + x
			if g.sea[c] do continue
			best := g.next[c]
			steepest := g.fill[c]/g.d if best < 0 else (g.fill[c] - g.fill[best])/span(g, c, int(best))
			for o in OFFSETS {
				if x + o.x < 0 || y + o.y < 0 || x + o.x >= n || y + o.y >= n do continue
				nb := c + o.y*n + o.x
				sea := g.sea[nb]
				s := (g.fill[c] - (0 if sea else g.fill[nb]))/step(g, c, o)
				if s > steepest do steepest, best = s, (-1 if sea else i32(nb))
			}
			g.next[c] = best
			g.area[c] = g.d*g.d*(wear(g, c, g.z[c] - 0.5).runs if rocks.sinks else 1)   // what sinks into the rock runs on under the ground, and cuts nothing
		}
	})
	for c in sinks do if g.next[c] < 0 do g.next[c] = SINK
	#reverse for c in g.order {
		if r := g.next[c]; r >= 0 do g.area[r] += g.area[c]
	}
}

// How the rock at height z in a cell wears. The rock is read where it will stand in the
// finished world, once the uplift still to come and the sea's rise have moved it, so the
// beds cut here are the beds the blocks show.
wear :: #force_inline proc(g: ^Grid, c: int, z: f32) -> Rock_Law {
	law := rocks.law[rock_in(z + g.uplift[c]*g.left - g.rise, grid_under(g, c), ROCK_SIM)]
	if g.keep && land.slid[c] > 0.5 do law.erodes, law.creep = landslide.law.erodes, landslide.law.creep   // the debris wears as its blocks do
	return law
}

// One step of uplift and cutting, worked from the shore upward so each cell knows where
// the cell below it has ended up. Solving for the new height rather than stepping toward
// it keeps the result steady however long the step. Weak rock is cut faster and holds a
// gentler slope.
erode :: proc(g: ^Grid, dt: f32) #no_bounds_check {
	for ci in g.order {
		c := int(ci)
		below, run: f32 = 0, g.d
		if g.next[c] == SINK || (g.keep && g.fill[c] > g.z[c] + 0.01) {   // nothing runs on from a sink to cut it, and a lake's floor is still
			g.z[c] += g.uplift[c]*g.lift*dt
			g.load[c] = 0
			continue
		}
		if r := g.next[c]; r >= 0 {
			below, run = g.z[r], span(g, c, int(r))
			if g.face[r] != 1 do g.face[c] = 1 + (g.face[r] - 1)*math.exp(-run/100)   // a cliff the sea undercuts eases over 100 m inland
			else do g.face[c] = 1   // as that gives where it has eased to nothing, without the exp
		}
		law := wear(g, c, g.z[c])
		f := ERODE*g.soft[c]*law.erodes*math.sqrt(g.area[c])*dt/run
		z := (g.fill[c] + g.uplift[c]*g.lift*dt + f*below)/(1 + f)
		was := g.z[c] + g.uplift[c]*g.lift*dt
		g.z[c] = clamp(z, below + 0.001*run, below + law.limit*run*g.face[c])
		g.load[c] = max(was - g.z[c], 0)*g.d*g.d
	}
	#reverse for c in g.order do if r := g.next[c]; r >= 0 do g.load[r] += g.load[c]
}

creep :: proc(g: ^Grid, dt: f32) {
	Creep :: struct { g: ^Grid, k: f32 }
	rounds := int(math.ceil(CREEP*dt/(0.2*g.d*g.d)))
	cr := Creep{g, CREEP*dt/(f32(rounds)*g.d*g.d)}
	for _ in 0..<rounds {
		// g.fill holds the ground as it stood: free to use, since route rebuilds it.
		shared(g.n, rows(g.n), g, proc(g: ^Grid, lo, hi: int) { for c in lo*g.n..<hi*g.n do g.fill[c] = max(g.z[c], 0) })
		shared(g.n, rows(g.n), &cr, proc(cr: ^Creep, lo, hi: int) {
			g, n, old := cr.g, cr.g.n, cr.g.fill
			for y in max(lo, 1)..<min(hi, n - 1) {
				for x in 1..<n - 1 {
					c := y*n + x
					if g.sea[c] do continue
					// A mantle of ash creeps wherever it can lie, which is not on a face.
					rate := wear(g, c, old[c]).creep
					if m := region.story.mantle; m > rate do rate = math.lerp(m, rate, smoothstep(0.7, 1.2, math.hypot(old[c + 1] - old[c - 1], old[c + n] - old[c - n])/(2*g.d)))
					g.z[c] = max(old[c] + cr.k*rate*(old[c - 1] + old[c + 1] + old[c - n] + old[c + n] - 4*old[c]), 0.02)
				}
			}
		})
	}
}

// The sea cuts its shore back to a platform just under the water, and the land behind, which
// goes on rising, stands over it as a cliff at the steepest its rock holds. The waves wear away
// rock by how much open sea lies around a shore and toward the swell, so headlands and shores
// facing the swell give way, bays and lee shores are spared, and weak rock gives way faster
// than strong. What they wear away is the whole cliff, so a low shore is cut back quickly and a
// high one slowly; and they break on the platform they leave, so a coast that has cut a wide
// shallow one retreats only as fast as the platform is worn deeper.
WAVES     :: 0.3    // m² of a rock that erodes at 1 worn from each metre of shore a year, open to the swell all round
FETCH     :: 500    // metres around a shore cell, and toward the swell, over which the sea is counted
PLATFORM  :: 2      // metres under the sea that a cut shore is left,
ABRADE    :: 1e-5   // and m/yr the waves wear it lower, slowing to nothing at
WAVE_BASE :: 20     // this depth, so a platform deepens away from its cliff
SHELTER   :: 0.07   // exposure below which the waves neither undercut a shore nor carry silt off
// What a stream brings settles out of the still water of a sheltered bay up to its surface, and the
// tides and floods lay it a little higher by the mouth: a flat of silt that falls gently away from
// the mouth under the water to a foot, under which its front falls steeply to the bay's floor. (Every
// figure a guess; mud flats fall about 1 in 1,000 on wide tidal coasts, more steeply in a small bay.)
FLAT      :: 1      // metres over the sea it is built to by the mouth,
FLAT_FALL :: 0.005  // falling this many metres for each metre out from the mouth,
FLAT_FOOT :: -1.5   // to this far under the sea at most
REEF_DEPTH :: 30    // metres: coral grows up toward the sea from water no deeper than this,
REEF_TOP   :: 1.5   // and to this far under it: the reef's flat, just under the lowest tides

// The sea cells above and to the left of each corner of the grid, so that the share of sea in
// any square is four reads.
sea_table :: proc(g: ^Grid, allocator := context.temp_allocator, into: []i32 = nil) -> []i32 #no_bounds_check {
	n := g.n
	open := into if into != nil else make([]i32, (n + 1)*(n + 1), allocator)
	for y in 0..<n {
		row: i32
		for x in 0..<n {
			row += i32(g.sea[y*n + x])
			open[(y + 1)*(n + 1) + x + 1] = open[y*(n + 1) + x + 1] + row
		}
	}
	return open
}

// The share of sea in a square r cells either side of a cell.
share :: proc(open: []i32, n, x, y, r: int) -> f32 {
	x0, y0, x1, y1 := clamp(x - r, 0, n), clamp(y - r, 0, n), clamp(x + r + 1, 0, n), clamp(y + r + 1, 0, n)
	w := n + 1
	return f32(open[y1*w + x1] - open[y0*w + x1] - open[y1*w + x0] + open[y0*w + x0])/f32(max((x1 - x0)*(y1 - y0), 1))
}

coast :: proc(g: ^Grid, dt: f32) {
	n := g.n
	if g.open == nil do g.open = make([]i32, (n + 1)*(n + 1))
	// Where the sea floor rises with the island, and in a warm sea coral builds a reef up from it to
	// just under the sea wherever the water is shallow enough, which grows out as a flat at the sea's
	// level while the sea stands, so that each stand of the sea leaves a terrace as the island rises.
	if sh := region.shape; sh.bank > 0 || sh.reef > 0 do for c in 0..<n*n do if g.sea[c] {
		g.z[c] += f32(sh.bank)*g.uplift[c]*g.lift*dt
		if g.z[c] > -REEF_DEPTH && g.z[c] < -REEF_TOP do g.z[c] = min(g.z[c] + f32(sh.reef)*dt, -REEF_TOP)
		if g.z[c] > 0 do g.sea[c], g.cut[c] = false, 0
	}
	open := sea_table(g, into = g.open)
	// Each cell on its own, shared among threads: the platform wears deeper, and each land cell beside
	// the sea is marked in `seen`, which is free to use, since route rebuilds it.
	Wear :: struct { g: ^Grid, dt: f32 }
	w := Wear{g, dt}
	shared(n, rows(n), &w, proc(w: ^Wear, lo, hi: int) {
		g, n := w.g, w.g.n
		for c in lo*n..<hi*n {
			if g.sea[c] && g.z[c] > -WAVE_BASE do g.z[c] -= ABRADE*w.dt*(1 + g.z[c]/WAVE_BASE)
			if g.sea[c] do continue
			beside := false
			for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x]
			g.seen[c] = beside
		}
	})
	r := max(int(FETCH/g.d), 2)
	bearing := math.to_radians(f32(region.shape.swell))
	ahead := [2]int{int(math.round(math.sin(bearing)*f32(r))), int(math.round(-math.cos(bearing)*f32(r)))}
	back := max(int(100/g.d), 1)   // the cliff is the highest ground this many cells inland
	for ci in g.order {
		c := int(ci)
		if !g.seen[c] do continue
		x, y := c%n, c/n
		cliff, deep: f32   // the highest ground and the deepest water within 100 m
		for j in max(y - back, 0)..=min(y + back, n - 1) do for i in max(x - back, 0)..=min(x + back, n - 1) do cliff, deep = max(cliff, g.z[j*n + i]), max(deep, -g.z[j*n + i])
		exposed := exposure(open, n, x, y, r, ahead)
		law := wear(g, c, 0.5)
		if exposed >= SHELTER do g.cut[c] += WAVES*dt*exposed*law.erodes*min(deep/WAVE_BASE, 1)/(cliff + PLATFORM)
		if g.cut[c] >= g.d {
			g.z[c], g.sea[c] = -PLATFORM, true
			for o in OFFSETS do g.seen[c + o.y*n + o.x] = true   // the cells after it beside it now lie beside the sea
		}
		// A face the waves undercut stands steeper than the rock holds on a hillside: up to twice
		// as steep where the shore is open, and no steeper than a hillside where it is sheltered.
		g.face[c] = 1 + smoothstep(SHELTER, 0.2, exposed)
	}

	// What the streams carry down settles where the sea is sheltered. Off each mouth it fills the
	// water nearest first to just over the sea, so a flat grows out from the head of a bay until
	// the silt runs out or the water grows open, where the waves carry the rest away.
	if region.shape.silt == 0 do return
	if g.reached == nil do g.reached = make([]i32, n*n)
	queue := make([dynamic][2]i32)   // a cell, and how many cells out from the mouth it lies
	defer delete(queue)
	for ci in g.order {
		if g.next[ci] >= 0 || g.area[ci] < CHANNEL_AREA do continue
		g.mouths += 1
		left := g.load[ci]*f32(region.shape.silt)
		clear(&queue)
		append(&queue, [2]i32{ci, 0})
		for head := 0; head < len(queue) && left > 0; head += 1 {
			k, out := int(queue[head].x), queue[head].y + 1
			top := max(FLAT - FLAT_FALL*g.d*f32(out), FLAT_FOOT)
			for o in OFFSETS {
				x, y := k%n + o.x, k/n + o.y
				c := y*n + x
				if x < 0 || y < 0 || x >= n || y >= n || !g.sea[c] || g.reached[c] == g.mouths do continue
				g.reached[c] = g.mouths
				if exposure(open, n, x, y, r, ahead) >= SHELTER do continue
				need := max(top - g.z[c], 0)*g.d*g.d
				if left < need {
					g.z[c] += left/(g.d*g.d)
					left = 0
					break
				}
				g.z[c] = max(g.z[c], top)
				if g.z[c] > 0 do g.sea[c] = false
				append(&queue, [2]i32{i32(c), out})
			}
		}
	}
}

// How open a shore is to the waves: the share of open sea around it, squared, and more where
// the sea toward the swell is open too.
exposure :: proc(open: []i32, n, x, y, r: int, ahead: [2]int) -> f32 {
	around := share(open, n, x, y, r)
	return around*around*(0.3 + 0.7*share(open, n, x + ahead.x, y + ahead.y, r))
}

// The same land and sea bed at twice the detail: land and sea are where the coarse grid has
// them, with the coast the waves cut and the sea bed they wore.
refine :: proc(coarse: ^Grid) -> ^Grid {
	g := grid_make(coarse.n*2)
	g.left = coarse.left
	grids := [2]^Grid{g, coarse}
	shared(g.n, rows(g.n), &grids, proc(grids: ^[2]^Grid, lo, hi: int) {
		g, coarse := grids[0], grids[1]
		n, m := g.n, coarse.n
		for c in lo*n..<hi*n {
			// Read the coarse land through a gentle warp, so a valley that ran straight along the
			// coarse grid comes out winding. The steps that follow settle it.
			wx, _, _ := noise(f64(c%n)/9, f64(c/n)/9, seed + 11 + u32(n))
			wz, _, _ := noise(f64(c%n)/9, f64(c/n)/9, seed + 12 + u32(n))
			u, v := (f32(c%n) + 0.5)/2 - 0.5 + 1.6*(wx - 0.5), (f32(c/n) + 0.5)/2 - 0.5 + 1.6*(wz - 0.5)
			x0, y0 := clamp(int(math.floor(u)), 0, m - 2), clamp(int(math.floor(v)), 0, m - 2)
			tu, tv := clamp(u - f32(x0), 0, 1), clamp(v - f32(y0), 0, 1)
			k := y0*m + x0
			z := math.lerp(math.lerp(coarse.z[k], coarse.z[k + 1], tu), math.lerp(coarse.z[k + m], coarse.z[k + m + 1], tu), tv)
			g.sea[c] = z <= 0
			if g.sea[c] {
				g.z[c] = z
				continue
			}
			g.face[c] = coarse.face[k]
			// A little roughness, so the finer streams have something to start from.
			g.z[c] = max(z, 0.3) + 0.03*g.d*(hash01(i32(c%n), i32(c/n), seed + 10) - 0.5)
		}
	})
	grid_free(coarse)
	return g
}
