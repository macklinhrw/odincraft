package main

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

// What start-up prints about the formed land, measured as the real islands were
// (docs/interesting-world/notes/real-islands.md), and --map=, the picture of it from above.

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
		kinds[rock_in(g.z[c] - 0.5, grid_under(g, c), ROCK_SIM)] += 1
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
	at :: proc(g: ^Grid, c: int) -> [3]f32 { return {(f32(c%g.n) + 0.5)*g.d - f32(region.size/2), g.z[c], (f32(c/g.n) + 0.5)*g.d - f32(region.size/2)} }
	fmt.printfln("steeper than 45°: %.1f%% of land; median slope %.0f°; tallest face %.0f m, from %.0f to %.0f",
		100*f32(steep)/f32(len(slopes)), math.to_degrees(math.atan(middle(slopes[:]))), face, at(g, top), at(g, foot))
	fmt.print("rock at the surface:")
	for k, m in kinds do if k > 0 do fmt.printf(" %v %.0f%%", m, 100*f32(k)/f32(len(g.order)))
	fmt.println()
	land_figures(g)
	free_all(context.temp_allocator)
}

// The figures the real islands were measured by (interesting-world/notes/real-islands.md),
// taken the same way, with the real high islands' range beside each. Slope is by central
// differences on land whose eight neighbours are land; a crest is such a cell steeper than 5°
// that nothing drains into; a shore cell is land beside the sea.
land_figures :: proc(g: ^Grid) {
	n := g.n
	coast := make([]bool, n*n, context.temp_allocator)   // within 100 m of the sea
	lists: [5][dynamic]f32   // height within 100 m of a shore cell, slope near the sea, crest fall, height above the stream, within 50 m of a shore cell
	for &l in lists do l = make([dynamic]f32, context.temp_allocator)
	for y in 8..<n - 8 {
		for x in 8..<n - 8 {
			c := y*n + x
			beside := false
			for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x] != g.sea[c]
			if !beside do continue
			top: [2]f32
			for dy in -6..=6 do for dx in -6..=6 {
				d := dx*dx + dy*dy
				k := c + dy*n + dx
				if g.sea[c] && d <= 39 do coast[k] = true
				if !g.sea[c] && !g.sea[k] && d <= 36 do top = {max(top[0], g.z[k]), max(top[1], g.z[k] if d <= 9 else 0)}
			}
			if !g.sea[c] {
				append(&lists[0], top[0])
				append(&lists[4], top[1])
			}
		}
	}
	// Crests and the height above the nearest stream as the real islands were measured, every cell's
	// rain counted: where some sinks into the rock, by the valleys it would run in if none did.
	area, above := g.area, land.above
	if rocks.sinks {
		area, above = make([]f32, n*n, context.temp_allocator), make([]f32, n*n, context.temp_allocator)
		for ci in g.order do area[ci] = g.d*g.d
		#reverse for ci in g.order do if r := g.next[ci]; r >= 0 do area[r] += area[ci]
		for ci in g.order {
			c, r := int(ci), g.next[ci]
			above[c] = 0 if area[c] >= CHANNEL_AREA || r == SINK else g.z[c] if r < 0 else g.z[c] - g.z[r] + above[r]
		}
	}
	low, steep, inner := 0, 0, 0
	for ci in g.order {
		c := int(ci)
		append(&lists[3], above[c])
		if g.z[c] < 50 do low += 1
		sea := false
		for o in OFFSETS do sea ||= g.sea[c + o.y*n + o.x]
		if sea do continue
		inner += 1
		if land.slope[c] > math.tan(math.to_radians(f32(60))) do steep += 1
		if coast[c] do append(&lists[1], land.slope[c])
		if area[c] <= g.d*g.d*1.01 && land.slope[c] > math.tan(math.to_radians(f32(5))) do append(&lists[2], g.z[c] - (g.z[c - 1] + g.z[c + 1] + g.z[c - n] + g.z[c + n])/4)
	}
	median :: proc(l: [dynamic]f32) -> f32 { return middle(l[:]) }
	rising := 0
	for h in lists[4] do if h > 30 do rising += 1
	fmt.print("against")
	names, by_story := judged_by()
	for name, i in names do fmt.printf("%s %s", "" if i == 0 else " and", name)
	if len(names) == 0 do fmt.print(" no real island, this kind having none in the set")
	else if by_story do fmt.printf(", the real island%s its rock's story stands for, not its kind's", "s" if len(names) > 1 else "")
	fmt.printfln(": shore height within 100 m %s m; shore rising 30 m in 50 m %s%%; slope in the first 100 m %s°",
		against(0, median(lists[0]), "%.0f", 8), against(1, 100*f32(rising)/f32(max(len(lists[4]), 1)), "%.0f", 10), against(2, math.to_degrees(math.atan(median(lists[1]))), "%.0f", 3))
	fmt.printfln("  land under 50 m %s%%; over 60° %s%%; fall at a crest %s m; height above the nearest stream %s m",
		against(3, 100*f32(low)/f32(len(g.order)), "%.0f", 5), against(4, 100*f32(steep)/f32(max(inner, 1)), "%.1f", 0.5), against(5, median(lists[2]), "%.2f", 0.15), against(6, median(lists[3]), "%.0f", 10))

	// A sheltered landing is shore under 5 m where the sea fills less than a third of the
	// square a kilometre across around it, with livable ground within 100 m; shore of that kind
	// less than 50 m apart is one landing.
	live, landing := make([]bool, n*n, context.temp_allocator), make([]bool, n*n, context.temp_allocator)
	livable: int
	for c in 0..<n*n do live[c], livable = land.live[c] > 0, livable + int(land.live[c] > 0)
	_, patch := patches(n, live, 1)
	open := sea_table(g)
	for y in 16..<n - 16 {
		for x in 16..<n - 16 {
			c := y*n + x
			if g.sea[c] || g.z[c] >= 5 || share(open, n, x, y, int(500/g.d)) >= 1.0/3 do continue
			beside, behind := false, false
			for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x]
			for dy in -6..=6 do for dx in -6..=6 do behind ||= dx*dx + dy*dy <= 36 && live[c + dy*n + dx]
			landing[c] = beside && behind
		}
	}
	_, landings := patches(n, landing, 3)

	// The deepest closed hollow, as the real islands were measured: how deep water would stand
	// in it if none sank into a crater's floor.
	// The grid was routed last on the land as it stands, so with no crater whose water sinks its
	// hollows are filled already; with one, they are filled again for this and the routing put back.
	hollow: f32
	sinks := false
	for v in region.vents do sinks ||= v.fallen
	if !sinks do for c in g.order do hollow = max(hollow, g.fill[c] - g.z[c])
	else {
		fill, next, area, order := slice.clone(g.fill, context.temp_allocator), slice.clone(g.next, context.temp_allocator), slice.clone(g.area, context.temp_allocator), slice.clone(g.order[:], context.temp_allocator)
		for &v in region.vents do v.fallen = false
		route(g)
		for c in g.order do hollow = max(hollow, g.fill[c] - g.z[c])
		for &v in region.vents do v.fallen = v.crater > 0
		copy(g.fill, fill); copy(g.next, next); copy(g.area, area); copy(g.order[:], order)
	}
	// The streams as the real islands' were measured: every cell draining CHANNEL_AREA or more, each
	// step down a cell or a diagonal long, and the largest basin whose water reaches the sea.
	stream, basin: f32
	for ci in g.order {
		c, r := int(ci), int(g.next[ci])
		if r == -1 do basin = max(basin, area[c])
		if area[c] < CHANNEL_AREA do continue
		stream += g.d*(math.SQRT_TWO if r >= 0 && r%n != c%n && r/n != c/n else 1)
	}
	streams := fmt.tprintf("  streams draining over %.2f km² %s km per km²; the largest basin at the sea %s km²", f32(CHANNEL_AREA)/1e6,
		against(8, stream/1000/(f32(len(g.order))*g.d*g.d/1e6), "%.2f", 0.2), against(9, basin/1e6, "%.1f", 1))
	fmt.printfln("  livable %.0f%% of land, the largest patch %.0f ha (15-46, 63-417); sheltered landings %d, %.1f in 10 km of shore (0 on the cones, 7-14 and 1.3-1.9, 80 and 3.6 on Tsushima); deepest closed hollow %s m",
		100*f32(livable)/f32(len(g.order)), f32(slice.max(patch[:]) if len(patch) > 0 else 0)*g.d*g.d/10_000, len(landings), f32(len(landings))*10_000/(f32(len(lists[0]))*g.d), against(7, hollow, "%.0f", 8))
	fmt.println(streams)
}

// A material's colour as the map shows it.
map_colour :: proc(m: Mat) -> [3]f32 {
	c := MATERIALS[m].colour
	c = {math.sqrt(c.r), math.sqrt(c.g), math.sqrt(c.b)}*1.2
	grey := (c.r + c.g + c.b)/3
	return grey + (c - grey)*3   // hues told apart more easily than on the ground
}

// A field's value as the colour the map paints it, and a lens over the world (play.odin).
field_paint :: proc(paint: ^Field_Info, v: f32, x, z: f64) -> (col: [3]f32) {
	switch paint.paint {
	case .Kinds: col = map_colour(Mat(v))
	case .Soils: col = SOILS[int(v)].colour
	case .Plants: col = COMMUNITIES[Community_Kind(v)].colour
	case .Zones: col = ZONES[int(v)].colour
	case .Wheel:
		a := math.to_radians(v)
		col = math.lerp([3]f32{0.6, 0.6, 0.6}, 0.55 + 0.4*[3]f32{math.cos(a), math.cos(a - 2.1), math.cos(a + 2.1)}, clamp(land_at(land.slope, land.n, x, z)/0.2, 0, 1))
	case .Log:  col = math.lerp(paint.from_colour, paint.to_colour, clamp((math.log10(v) - paint.lo)/(paint.hi - paint.lo), 0, 1))
	case .Ramp: col = math.lerp(paint.from_colour, paint.to_colour, clamp((v - paint.lo)/(paint.hi - paint.lo), 0, 1))
	}
	return
}

// The land's colour at a point of the island in hand as its map shows it, and its height there:
// relief shaded from the north-west, the sea by its depth, the rivers and lakes, and the shore as
// the ground has it. With a field, the land is painted by it; with `marks`, the animals' trails and
// fords are drawn. --map and the world's screen (chart.odin) both draw the land with this.
map_at :: proc(x, z: f64, paint: ^Field_Info, field: Field, marks: bool) -> (col: [3]f32, h: f32) {
	h = land_at(land.z[0], land.n, x, z)
	gx := land_at(land.z[0], land.n, x + 8, z) - land_at(land.z[0], land.n, x - 8, z)
	gz := land_at(land.z[0], land.n, x, z + 8) - land_at(land.z[0], land.n, x, z - 8)
	shade := clamp(0.75 + 0.9*(-gx - gz)/16, 0.25, 1.3)
	if h <= 0 {
		col = math.lerp([3]f32{0.35, 0.62, 0.80}, [3]f32{0.08, 0.22, 0.42}, clamp(-h/30, 0, 1))
	} else {
		if paint != nil {
			p := point_at(x, z, 8) if field in GROUND_FIELDS else Point{x = x, z = z, cell = 8}
			col = field_paint(paint, paint.at(&p), x, z)*shade
		} else {
			// Green at the sea, tan at 200 m, brown at 500 and pale only near 1,000, so that
			// the height of a high island still reads.
			t := math.sqrt(clamp(h/1000, 0, 1))
			col = math.lerp(math.lerp([3]f32{0.42, 0.60, 0.30}, [3]f32{0.66, 0.58, 0.38}, clamp(t*2.2, 0, 1)), [3]f32{0.52, 0.42, 0.34}, clamp(t*3.3 - 1.45, 0, 1))
			col = math.lerp(col, [3]f32{0.90, 0.89, 0.86}, clamp(t*4 - 3, 0, 1))*shade
			// Rock shows where the ground is too steep to hold soil, as on the ground.
			bed := rock(x, f64(h) - 0.5, z, 8)
			bare := smoothstep(0.85, 1.15, land_at(land.slope, land.n, x, z)/SOIL_HOLDS)
			col = math.lerp(col, map_colour(bed)*shade, 0.8*bare)
			// A slide's debris is tinted ochre and its scar pale.
			if s := land_at(land.slid, land.n, x, z); abs(s) > 0.5 do col = math.lerp(col, ([3]f32{0.80, 0.50, 0.20} if s > 0 else {0.90, 0.88, 0.84})*shade, f32(0.5))
			// A reed marsh is tinted the colour of reeds.
			if land.community[land_cell(x, z)] == u8(Community_Kind.Marsh) do col = math.lerp(col, [3]f32{0.70, 0.72, 0.40}*shade, f32(0.6))
		}
		if r, near := river_near(f32(x), f32(z)); near && r.d < max(r.half, 4) do col = {0.10, 0.30, 0.75}
		else if near && r.d < r.bed do col = [3]f32{0.78, 0.76, 0.70}*shade   // the bed of stones round the water
		if level, inside, _ := lake_near(x, z); inside && h < level do col = {0.10, 0.30, 0.75}
		if marks && trail_near(x, z) < 4.5 do col = {0.65, 0.10, 0.05}
		if k := trails.ford[land_cell(x, z)]; marks && k > 0 && math.hypot(x - region.features[k - 1].at.x, z - region.features[k - 1].at.y) < 14 do col = {1, 1, 1}
	}
	// The shore as the ground has it (waters_edge, gen.odin): sand, stones and the rock
	// platform in their own colours where they stand over the sea, and the stacks.
	if _, fan := fan_at(x, z); paint == nil && (land_at(land.surf, land.n, x, z) > 0.01 || fan > 0) {
		p := point_at(x, z, 8)
		if w := SURFACES[surface_row(&p)].host; p.h > 0 && len(w) > 0 && (w[0].field == .Beach || w[0].field == .Surf || w[0].field == .Fan) || p.steep == 3 {
			_, m, _ := surface_at(x, z, 8)
			col = map_colour(m)*shade
		}
	}
	return
}

// A picture of the land from above, eight metres to the pixel: relief shaded from the
// north-west, sea by depth, and the rivers. With an overlay, the land is painted by that
// field instead.
land_map :: proc(path, overlay: string) {
	SIZE :: 1024
	paint: ^Field_Info
	field: Field
	for &f, k in FIELDS do if f.name == overlay do paint, field = &f, k
	if overlay != "" && paint == nil {
		fmt.eprint("no field named", overlay, "; there are:")
		for f in FIELDS do fmt.eprint("", f.name)
		fmt.eprintln()
		return
	}
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	for py in 0..<SIZE {
		for px in 0..<SIZE {
			x, z := (f64(px) + 0.5)*region.size/SIZE - region.size/2, (f64(py) + 0.5)*region.size/SIZE - region.size/2
			col, _ := map_at(x, z, paint, field, true)
			for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
		}
	}
	// A key to a field painted on a ramp, its name and span from one colour to the other, and the wind.
	if paint != nil && (paint.paint == .Ramp || paint.paint == .Log) {
		for py in SIZE - 36..<SIZE - 24 do for px in 20..<276 {
			col := math.lerp(paint.from_colour, paint.to_colour, f32(px - 20)/255)
			for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
		}
		lo, hi := paint.lo, paint.hi
		if paint.paint == .Log do lo, hi = math.pow(10, lo), math.pow(10, hi)
		write(pixels, SIZE, 20, SIZE - 54, strings.to_upper(fmt.tprintf("%s %.4g to %.4g%s. the wind from %.0f", paint.name, lo, hi, paint.unit, region.shape.swell), context.temp_allocator), 2, {255, 255, 255})
	}
	// Each roofed place and stack (events.odin) is ringed, in orange for a notch, white for a shelter, red for a sea cave and yellow for a stack.
	for f in region.features do if f.kind >= .Notch && f.kind <= .Cave || f.kind == .Stack {
		cx, cy := int((f.at.x + region.size/2)*SIZE/region.size), int((f.at.y + region.size/2)*SIZE/region.size)
		for dy in -6..=6 do for dx in -6..=6 do if r := dx*dx + dy*dy; r >= 16 && r <= 36 && cx + dx >= 0 && cy + dy >= 0 && cx + dx < SIZE && cy + dy < SIZE {
			ring := #partial [Feature_Kind][3]u8{.Notch = {255, 140, 0}, .Shelter = {255, 255, 255}, .Cave = {230, 20, 20}, .Stack = {255, 230, 0}}
			for k in 0..<3 do pixels[((cy + dy)*SIZE + cx + dx)*4 + k] = ring[f.kind][k]
		}
	}
	// Each fall a white dot, larger the taller it is, and each spring a small cyan one, ringed in black.
	for f in region.features do if f.kind == .Fall || f.kind == .Spring {
		px, py := int((f.at.x + region.size/2)*SIZE/region.size), int((f.at.y + region.size/2)*SIZE/region.size)
		fall := f.kind == .Fall
		r, colour := 1.5 + f.measured[0].value/30 if fall else 1, [3]u8{255, 255, 255} if fall else {90, 230, 255}
		for dy in -4..=4 do for dx in -4..=4 do if d := math.hypot(f32(dx), f32(dy)); d <= r + 1 && px + dx >= 0 && py + dy >= 0 && px + dx < SIZE && py + dy < SIZE {
			for k in 0..<3 do pixels[((py + dy)*SIZE + px + dx)*4 + k] = colour[k] if d <= r else 0
		}
	}
	creatures_mark(pixels, SIZE)
	places_mark(pixels, SIZE)
	write_png(path, pixels, SIZE, SIZE, false)
}
