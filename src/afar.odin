package main

import "core:fmt"
import "core:math"
import "core:slice"

// The land larger than a region as it is seen and measured (continents.odin forms it): land not yet
// formed drawn from the coarse stage, a map of it, and the seam's measure.

// Cells this wide and wider are drawn over a landmass's piece that is not formed, from its coarse
// stage: from about half a kilometre off, so that no ring of the view ends against land that is
// missing. Nearer, where the ground can be stood on, a chunk waits for the piece (waits, world.odin).
FAR_CELL  :: 4
FAR_LEVEL :: 2

// The ground a landmass's coarse stage holds at a point in the world, as it will stand once the sea
// has risen the last of its rise: its height, how steep it is, and whether the sea is beside it.
far_ground :: proc(m: ^Landmass, wx, wz: f64) -> (h, steep: f32, shore: bool) {
	st := &m.store
	u, v := (wx - f64(m.origin.x))/64 + f64(st.n)/2 - 0.5, (wz - f64(m.origin.y))/64 + f64(st.n)/2 - 0.5
	i, j := int(math.floor(u)), int(math.floor(v))
	tu, tv := f32(u - f64(i)), f32(v - f64(j))
	a, b, c, d := store_z(st, i, j), store_z(st, i + 1, j), store_z(st, i, j + 1), store_z(st, i + 1, j + 1)
	h = math.lerp(math.lerp(a, b, tu), math.lerp(c, d, tu), tv) - st.rise
	// The finer phases go on wearing the land, and the rebound gives back ISOSTASY of what they wear
	// (coarse.odin): at the rate the coarse stage left, the land ends lower by the rest.
	h -= (1/ISOSTASY - 1)*store_rose(st, f32(u + 0.5), f32(v + 0.5))*m.rest
	steep = math.hypot((b - a + d - c)/2, (c - a + d - b)/2)/64
	return h, steep, min(a, b, c, d) - st.rise <= 0
}

// A column over a piece of a landmass that is not formed, from far off: the coarse stage's ground,
// clothed as the plant communities' own rows clothe ground of that slope (the laurel forest; the
// valley forest on gentle ground; the strand beside the sea) and bare where soil does not hold.
far_column :: proc(m: ^Landmass, wx, wz, cell: f64, level: i32, c: ^Columns, k: int) -> f32 {
	h, steep, shore := far_ground(m, wx, wz)
	if h < SEA_SURFACE {
		h = max(h, SEA_BED)
		c.water[k], c.mat[k], c.floor[k] = SEA_SURFACE, .Sand, .Sand
		c.top[k] = min(i32(math.round(h)), SEA_LEVEL - 1)
		c.ground[k] = c.top[k]
		return h
	}
	if here != &m.frame do bind(&m.frame)
	x, z := wx - f64(m.origin.x), wz - f64(m.origin.y)
	c.under[k] = rock_base(x, z, cell)
	com := Community_Kind.Coast if shore else .Valley if steep < 0.2 else .Slope
	c.mat[k] = COMMUNITIES[com].cover if steep <= SOIL_HOLDS else rock_in(h - 0.5, c.under[k], rock_level(cell))
	c.floor[k], c.water[k] = c.mat[k], NO_WATER
	c.top[k] = i32(math.round(h))
	c.ground[k] = c.top[k]
	if steep <= SOIL_HOLDS && cell >= 8 {   // the canopy is part of the column from where it is on formed land
		r := hash(i32(math.floor(wx/cell)), i32(math.floor(wz/cell)), seed + 160 + u32(level))
		spacing, tall, _ := stand(200)
		if f32(r & 0xFFFF)/65536 < cover(com, spacing) {
			sp := SPECIES[pick_species(com, f32((r >> 16) & 0xFF)/256)]
			c.top[k] += i32(f32(sp.height[0] + i32((r >> 24) % u32(sp.height[1] - sp.height[0] + 1)))*tall) - 1
			c.mat[k] = sp.leaf
		}
	}
	return h
}


// A map of the land larger than a region as the game has it: a square `span` metres across round a
// point in the world, north up; the pieces formed at their own detail, the rest as the coarse stage
// holds it under the sea's last rise; with `cuts`, the lines between pieces drawn.
mass_map :: proc(path: string, middle: [2]f64, span: f64, cuts: bool) {
	SIZE :: 2048
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	heights := make([]f32, SIZE*SIZE)
	defer delete(heights)
	step := span/SIZE
	for py in 0..<SIZE do for px in 0..<SIZE do heights[py*SIZE + px] = height_in_world(middle.x + (f64(px) + 0.5 - SIZE/2)*step, middle.y + (f64(py) + 0.5 - SIZE/2)*step, step)
	for py in 0..<SIZE do for px in 0..<SIZE {
		c := py*SIZE + px
		h := heights[c]
		gx := heights[py*SIZE + min(px + 1, SIZE - 1)] - heights[py*SIZE + max(px - 1, 0)]
		gz := heights[min(py + 1, SIZE - 1)*SIZE + px] - heights[max(py - 1, 0)*SIZE + px]
		shade := clamp(0.75 + 0.9*f32(f64(-gx - gz)/(2*step)), 0.25, 1.3)
		col: [3]f32
		if h <= 0 do col = math.lerp([3]f32{0.35, 0.62, 0.80}, [3]f32{0.08, 0.22, 0.42}, clamp(-h/30, 0, 1))
		else {
			// Green at the sea, tan at 200 m, brown at 500 and pale only near 1,500, as the islands' maps are.
			ramp := [?][4]f32{{0, 0.36, 0.58, 0.30}, {200, 0.72, 0.66, 0.42}, {500, 0.55, 0.42, 0.30}, {1500, 0.92, 0.90, 0.88}}
			col = ramp[len(ramp) - 1].yzw
			for r, i in ramp[1:] do if h < r.x {
				col = math.lerp(ramp[i].yzw, r.yzw, (h - ramp[i].x)/(r.x - ramp[i].x))
				break
			}
			col *= shade
			wx, wz := middle.x + (f64(px) + 0.5 - SIZE/2)*step, middle.y + (f64(py) + 0.5 - SIZE/2)*step
			if m, p := mass_piece(wx, wz); m != nil {
				if cuts && !is_formed(&formed[m.first + p]) do col = math.lerp(col, [3]f32{0.6, 0.6, 0.6}, f32(0.35))   // not formed: greyed where the cuts are asked for
				if cuts {
					_, right := mass_piece(wx + step, wz)
					_, below := mass_piece(wx, wz + step)
					if right >= 0 && right != p || below >= 0 && below != p do col = {0.1, 0.1, 0.1}
				}
			}
		}
		for k in 0..<3 do pixels[c*4 + k] = u8(clamp(col[k], 0, 1)*255)
		pixels[c*4 + 3] = 255
	}
	write_png(path, pixels, SIZE, SIZE, false)
	fmt.printfln("a map of the land larger than a region, %.0f km across round %.0f, %.0f, in %s", span/1000, middle.x, middle.y, path)
}

// The seam's measure on the land as the game has it (docs/interesting-world/notes/continents-forming.md):
// in a square `span` metres across round a point, on the formed pieces' 16 m cells: the cut's length on
// land; the closed hollows over 2 m deep, within 100 m of a cut and away from one; the steps between
// neighbouring cells across a cut, and those more than 300 m from any; and how many steps across a cut
// are larger than the largest step away from one at the same slope of the coarse stage's ground.
mass_seam :: proc(middle: [2]f64, span: f64) {
	D :: LAND_CELL
	n := int(span/D)
	z, piece := make([]f32, n*n), make([]i32, n*n)
	defer { delete(z); delete(piece) }
	at :: proc(middle: [2]f64, n, c: int) -> (x, y: f64) { return middle.x + (f64(c%n) + 0.5 - f64(n)/2)*D, middle.y + (f64(c/n) + 0.5 - f64(n)/2)*D }
	unformed := 0
	over := make([dynamic]f32)   // how far the formed land stands over the coarse stage's, as the far rings draw it
	defer delete(over)
	for c in 0..<n*n {
		x, y := at(middle, n, c)
		z[c], piece[c] = height_in_world(x, y, D), -1
		if m, p := mass_piece(x, y); m != nil {
			piece[c] = i32(p)
			if !is_formed(&formed[m.first + p]) do unformed += 1
			else if h, _, _ := far_ground(m, x, y); z[c] > 0 || h > 0 do append(&over, z[c] - h)
		}
	}
	slice.sort(over[:])
	// Metres to the nearest cut on land, by two sweeps.
	far := make([]f32, n*n)
	defer delete(far)
	land_cells, cut_cells := 0, 0
	for c in 0..<n*n {
		far[c] = 1e9
		if z[c] <= 0 do continue
		land_cells += 1
		x, y := c%n, c/n
		for o in FOUR do if i, j := x + o.x, y + o.y; i >= 0 && j >= 0 && i < n && j < n && z[j*n + i] > 0 && piece[j*n + i] != piece[c] do far[c] = D/2
		if far[c] < 1e9 do cut_cells += 1
	}
	steps := [4][3]f32{{-1, 0, 1}, {0, -1, 1}, {-1, -1, math.SQRT_TWO}, {1, -1, math.SQRT_TWO}}
	for pass in 0..<2 do for i in 0..<n*n {
		c := i if pass == 0 else n*n - 1 - i
		x, y := c%n, c/n
		for s in steps {
			dx, dy := int(s.x) if pass == 0 else -int(s.x), int(s.y) if pass == 0 else -int(s.y)
			if nx, ny := x + dx, y + dy; nx >= 0 && ny >= 0 && nx < n && ny < n do far[c] = min(far[c], far[ny*n + nx] + s.z*D)
		}
	}
	// Closed hollows: the land filled from the sea and the square's edge.
	fill := make([]f32, n*n)
	defer delete(fill)
	seen := make([]bool, n*n)
	defer delete(seen)
	heap := make([dynamic]u64)
	defer delete(heap)
	for c in 0..<n*n {
		x, y := c%n, c/n
		if z[c] <= 0 || x == 0 || y == 0 || x == n - 1 || y == n - 1 {
			fill[c], seen[c] = max(z[c], 0), true
			heap64_push(&heap, u64(fkey(fill[c])) << 32 | u64(u32(c)))
		}
	}
	for len(heap) > 0 {
		c := int(u32(heap64_pop(&heap)))
		for o in OFFSETS {
			x, y := c%n + o.x, c/n + o.y
			if x < 0 || y < 0 || x >= n || y >= n || seen[y*n + x] do continue
			k := y*n + x
			seen[k], fill[k] = true, max(z[k], fill[c])
			heap64_push(&heap, u64(fkey(fill[k])) << 32 | u64(u32(k)))
		}
	}
	hollow_near, hollow_far, deepest_near, deepest_far := 0, 0, f32(0), f32(0)
	for c in 0..<n*n do if d := fill[c] - z[c]; z[c] > 0 && d > 2 {
		if far[c] <= 100 do hollow_near, deepest_near = hollow_near + 1, max(deepest_near, d)
		else do hollow_far, deepest_far = hollow_far + 1, max(deepest_far, d)
	}
	// Steps between neighbouring land cells: across a cut, and more than 300 m from any; by the slope
	// of the ground over 64 m, in bands of 0.05.
	BANDS :: 64
	largest: [BANDS]f32
	across, away := make([dynamic]f32), make([dynamic]f32)
	defer { delete(across); delete(away) }
	Step :: struct { d: f32, band: int }
	worst: struct { d: f32, a, b: int }
	crossing := make([dynamic]Step)
	defer delete(crossing)
	for c in 0..<n*n do if z[c] > 0 {
		x, y := c%n, c/n
		if x < 4 || y < 4 || x >= n - 4 || y >= n - 4 do continue
		slope := math.hypot(z[c + 2] - z[c - 2], z[c + 2*n] - z[c - 2*n])/(4*D)
		band := min(int(slope/0.05), BANDS - 1)
		for k in ([2]int{c + 1, c + n}) do if z[k] > 0 {
			d := abs(z[k] - z[c])
			if piece[k] != piece[c] {
				if d > worst.d do worst = {d, c, k}
				append(&across, d)
				append(&crossing, Step{d, band})
			} else if far[c] > 300 {
				append(&away, d)
				largest[band] = max(largest[band], d)
			}
		}
	}
	slice.sort(across[:])
	slice.sort(away[:])
	larger := 0
	for s in crossing do if s.d > largest[s.band] do larger += 1
	top: f32
	for h in z do top = max(top, h)
	pick :: proc(v: []f32, share: f64) -> f32 { return v[min(int(f64(len(v))*share), len(v) - 1)] if len(v) > 0 else 0 }
	fmt.printfln("the seam, %.0f km across round %.0f, %.0f: %.1f km² of land to %.0f m, %d cells of it on pieces not formed; cut on land %.1f km", span/1000, middle.x, middle.y, f64(land_cells)*D*D/1e6, top, unformed, f64(cut_cells)*D/2/1000)
	fmt.printfln("  closed hollows over 2 m: within 100 m of a cut %d cells, the deepest %.1f m; away from one %d cells, the deepest %.1f m", hollow_near, deepest_near, hollow_far, deepest_far)
	fmt.printfln("  steps across the cut: %d, 99th percentile %.1f m, largest %.1f m; steps more than 300 m from any cut: %d, 99th percentile %.1f m, largest %.1f m", len(across), pick(across[:], 0.99), pick(across[:], 1), len(away), pick(away[:], 0.99), pick(away[:], 1))
	fmt.printfln("  steps across the cut over the largest elsewhere at that slope: %d of %d", larger, len(crossing))
	if len(crossing) > 0 {
		x, y := at(middle, n, worst.a)
		fmt.printfln("  the largest step across the cut: %.1f m at %.0f, %.0f, between piece %d at %.1f m and piece %d at %.1f m", worst.d, x, y, piece[worst.a], z[worst.a], piece[worst.b], z[worst.b])
	}
	fmt.printfln("  the formed land over the coarse stage's as it is drawn from afar: median %.1f m, a tenth under %.1f m and a tenth over %.1f m", pick(over[:], 0.5), pick(over[:], 0.1), pick(over[:], 0.9))
}

