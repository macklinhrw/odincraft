package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"

// The land larger than a region as it is seen and measured (continents.odin forms it): land not yet
// formed drawn from the coarse stage, a map of it, and the seam's measure.

// Cells this wide and wider are drawn over a landmass's piece that is not formed, from its coarse
// stage: from about half a kilometre off, so that no ring of the view ends against land that is
// missing. Nearer, where the ground can be stood on, a chunk waits for the piece (waits, world.odin).
FAR_CELL  :: 4
FAR_LEVEL :: 2

// The ground a land mass's coarse stage holds at a point in the world as it stands today, the coarse
// stage having been run on through the years of the finer phases (coarse_today): its height, how
// steep it is, and whether the sea is beside it.
far_ground :: proc(m: ^Landmass, wx, wz: f64) -> (h, steep: f32, shore: bool) {
	st := &m.store
	u, v := (wx - f64(m.origin.x))/64 + f64(st.n)/2 - 0.5, (wz - f64(m.origin.y))/64 + f64(st.n)/2 - 0.5
	i, j := int(math.floor(u)), int(math.floor(v))
	tu, tv := f32(u - f64(i)), f32(v - f64(j))
	a, b, c, d := store_now(st, i, j), store_now(st, i + 1, j), store_now(st, i, j + 1), store_now(st, i + 1, j + 1)
	h = math.lerp(math.lerp(a, b, tu), math.lerp(c, d, tu), tv)
	steep = math.hypot((b - a + d - c)/2, (c - a + d - b)/2)/64
	return h, steep, min(a, b, c, d) <= 0
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


// Where a large land is stood on when it is walked: the formed ground nearest where it is come ashore
// (mass_landing) that stands a little over the sea with no tree within three strides, on the piece
// that is, and a bearing that looks inland, away from the start. The piece is formed.
mass_stand :: proc(m: ^Landmass) -> (pos: [3]f64, yaw: f32, ok: bool) {
	f := &formed[m.first + int(m.landing_piece)]
	if !is_formed(f) do return
	bound(f)
	g := land.grid
	o := [2]f64{f64(region.origin.x), f64(region.origin.y)}
	Spot :: struct { far: f64, c: i32 }
	spots := make([dynamic]Spot, context.temp_allocator)
	for ci in g.order do if c := int(ci); g.z[c] >= 2 {
		at := middle_of(g, c)
		append(&spots, Spot{math.hypot(at.x + o.x - m.landing.x, at.y + o.y - m.landing.y), ci})
	}
	slice.sort_by(spots[:], proc(a, b: Spot) -> bool { return a.far < b.far || a.far == b.far && a.c < b.c })
	trees := make([dynamic]Tree, context.temp_allocator)
	for s, i in spots {
		at := middle_of(g, int(s.c))
		x, z := math.floor(at.x) + 0.5, math.floor(at.y) + 0.5
		clear(&trees)
		trees_in(i32(x) - 6, i32(z) - 6, i32(x) + 6, i32(z) + 6, &trees, true)
		near := false
		for t in trees do near ||= max(abs(f64(t.x) + 0.5 - x), abs(f64(t.z) + 0.5 - z)) <= 3
		if near && i < 4000 do continue   // under a tree: the next nearest
		if ground(x, z, 1).water > ground(x, z, 1).h do continue
		pos, ok = {x + o.x, math.round(f64(height_at(x, z, 1))) + 0.1, z + o.y}, true
		break
	}
	d := m.landing - world_frame.origin
	return pos, f32(math.to_degrees(math.atan2(d.x, -d.y))), ok
}

// A map of the land larger than a region as the game has it: a square `span` metres across round a
// point in the world, north up; the pieces formed at their own detail, the rest as the coarse stage
// holds it today; with `cuts`, the lines between pieces drawn; with `afar`, every piece as the coarse
// stage holds it, formed or not, which is how it is drawn before it is formed.
mass_map :: proc(path: string, middle: [2]f64, span: f64, cuts, afar: bool) {
	SIZE :: 2048
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	heights := make([]f32, SIZE*SIZE)
	defer delete(heights)
	step := span/SIZE
	for py in 0..<SIZE do for px in 0..<SIZE {
		x, z := middle.x + (f64(px) + 0.5 - SIZE/2)*step, middle.y + (f64(py) + 0.5 - SIZE/2)*step
		heights[py*SIZE + px] = height_in_world(x, z, step)
		if afar do if m, _ := mass_piece(x, z); m != nil {
			h, _, _ := far_ground(m, x, z)
			heights[py*SIZE + px] = max(h, SEA_BED)
		}
	}
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
mass_seam :: proc(middle: [2]f64, span: f64, window := "") {
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
	if window != "" {   // the square as a real coast is kept: row 0 north, the sea -1, and the rim a window cuts -2
		out := make([]f32, n*n)
		defer delete(out)
		rim := 160/D
		for c in 0..<n*n {
			x, y := c%n, c/n
			out[c] = max(z[c], 0.2) if z[c] > 0 else -1
			if (x < rim || y < rim || x >= n - rim || y >= n - rim) && z[c] > 0 do out[c] = -2
		}
		if err := os.write_entire_file(window, slice.to_bytes(out)); err != nil do fmt.eprintln("could not write", window)
	}
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
	deepest := -1
	for c in 0..<n*n do if d := fill[c] - z[c]; z[c] > 0 && d > 2 {
		if far[c] <= 100 do hollow_near, deepest_near = hollow_near + 1, max(deepest_near, d)
		else do hollow_far, deepest_far = hollow_far + 1, max(deepest_far, d)
		if deepest < 0 || d > fill[deepest] - z[deepest] do deepest = c
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
	if deepest >= 0 {
		x, y := at(middle, n, deepest)
		fmt.printfln("  the deepest closed hollow: %.1f m at %.0f, %.0f, its floor at %.1f m and its water at %.1f m", fill[deepest] - z[deepest], x, y, z[deepest], fill[deepest])
	}
	fmt.printfln("  steps across the cut: %d, 99th percentile %.1f m, largest %.1f m; steps more than 300 m from any cut: %d, 99th percentile %.1f m, largest %.1f m", len(across), pick(across[:], 0.99), pick(across[:], 1), len(away), pick(away[:], 0.99), pick(away[:], 1))
	fmt.printfln("  steps across the cut over the largest elsewhere at that slope: %d of %d", larger, len(crossing))
	if len(crossing) > 0 {
		x, y := at(middle, n, worst.a)
		fmt.printfln("  the largest step across the cut: %.1f m at %.0f, %.0f, between piece %d at %.1f m and piece %d at %.1f m", worst.d, x, y, piece[worst.a], z[worst.a], piece[worst.b], z[worst.b])
	}
	fmt.printfln("  the formed land over the coarse stage's as it is drawn from afar: median %.1f m, a tenth under %.1f m and a tenth over %.1f m", pick(over[:], 0.5), pick(over[:], 0.1), pick(over[:], 0.9))
	mass_likeness(middle, span)
}

// How like the land drawn from afar is to the land it becomes, at the cells it is seen at when a
// piece is formed on approach: in a square round a point, the formed land's mean over each cell of
// `wide` metres less the coarse stage's as it is drawn there, both from the sea's level up, on the
// cells that are land in either. Said for the coarse stage's own cells and for cells four times as
// wide, and for the 64 m cells apart where a strong bed caps weaker rock down the face to the cell
// below (a bed that holds a third more slope than the weakest rock within 110 m under it).
mass_likeness :: proc(middle: [2]f64, span: f64) {
	pick :: proc(v: []f32, share: f64) -> f32 { return v[min(int(f64(len(v))*share), len(v) - 1)] if len(v) > 0 else 0 }
	say :: proc(what: string, v: ^[dynamic]f32) {
		slice.sort(v[:])
		mean: f64
		for d in v do mean += f64(abs(d))/f64(max(len(v), 1))
		fmt.printfln("  formed less far-drawn, %s: %d cells; median %.1f m, a tenth under %.1f m, a tenth over %.1f m, a hundredth under %.1f m and over %.1f m; mean difference %.1f m", what, len(v), pick(v[:], 0.5), pick(v[:], 0.1), pick(v[:], 0.9), pick(v[:], 0.01), pick(v[:], 0.99), mean)
	}
	was := here
	defer bind(was)
	for wide in ([2]f64{64, 256}) {
		parts: [4]f64
		all, capped, plain := make([dynamic]f32), make([dynamic]f32), make([dynamic]f32)
		defer { delete(all); delete(capped); delete(plain) }
		n := int(span/wide)
		for c in 0..<n*n {
			x, y := middle.x + (f64(c%n) + 0.5 - f64(n)/2)*wide, middle.y + (f64(c/n) + 0.5 - f64(n)/2)*wide
			// The cell on the land mass's own lattice that holds this point.
			m, p := mass_piece(x, y)
			if m == nil || !is_formed(&formed[m.first + p]) do continue
			x, y = math.floor((x - f64(m.origin.x))/wide)*wide + wide/2 + f64(m.origin.x), math.floor((y - f64(m.origin.y))/wide)*wide + wide/2 + f64(m.origin.y)
			near, far: f32
			whole := true
			k := int(wide/LAND_CELL)
			for j in 0..<k do for i in 0..<k {
				px, py := x + (f64(i) + 0.5 - f64(k)/2)*LAND_CELL, y + (f64(j) + 0.5 - f64(k)/2)*LAND_CELL
				if mm, pp := mass_piece(px, py); mm != m || !is_formed(&formed[m.first + pp]) do whole = false
				h, _, _ := far_ground(m, px, py)
				near, far = near + max(height_in_world(px, py, LAND_CELL), 0)/f32(k*k), far + max(h, 0)/f32(k*k)
			}
			if !whole || near <= 0 && far <= 0 do continue
			append(&all, near - far)
			if wide == 64 {   // the parts of the difference, where both stand over the sea
				st := &m.store
				u, v := (x - f64(m.origin.x))/64 + f64(st.n)/2, (y - f64(m.origin.y))/64 + f64(st.n)/2
				raw := store_z(st, int(math.floor(u)), int(math.floor(v))) - st.rise
				if near > 0 && far > 0 do parts += {f64(near), f64(raw), f64(far), 1}
			}
			if wide != 64 do continue
			// The rock at the coarse cell's surface and down its face, where the finished world has it.
			bind(&m.frame)
			st := &m.store
			rx, ry := x - f64(m.origin.x), y - f64(m.origin.y)
			_, uplift, _ := mass_ground(rx, ry)
			top := store_z(st, int(math.floor(rx/64 + f64(st.n)/2)), int(math.floor(ry/64 + f64(st.n)/2))) + uplift*st.left - st.rise
			under := rock_base(rx, ry, LAND_CELL)
			holds, least := rocks.law[rock_in(top, under, ROCK_SIM)].limit, f32(1e9)
			for d := f32(8); d <= 110; d += 8 do least = min(least, rocks.law[rock_in(top - d, under, ROCK_SIM)].limit)
			append(&capped if holds > 1.33*least else &plain, near - far)
		}
		say(fmt.tprintf("on cells of %.0f m", wide), &all)
		if wide == 64 {
			if parts[3] > 0 do fmt.printfln("  where both stand over the sea, %.0f cells of 64 m: the formed land a mean %.1f m; the coarse stage's as the pieces took it up, under the sea's last rise, %.1f m, and run on to today %.1f m", parts[3], parts[0]/parts[3], parts[1]/parts[3], parts[2]/parts[3])
			say("where a strong bed caps weaker rock", &capped)
			say("elsewhere", &plain)
		}
	}
}

