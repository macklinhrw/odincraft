package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:time"

// Creatures (foundations/living-world.md, stage 0b; interesting-world/notes/real-creatures.md). A
// kind is a row: where it lives, a host on the fields there, how many, in what season, its body as
// a few boxes and how it moves. Where each lives is chosen once, after the places: a bird's home is
// a feature (.Haunt), at a face the wind meets or on a stack; a fish lives in each stretch of stream
// and each lake its host holds in. The animals themselves are not kept: each frame every one near
// enough to be seen is posed from its kind, its home, its number and the clock, so the same seed and
// hour show the same birds in the same places. Only a startled fish remembers, for a few seconds,
// how far it has fled.

Home   :: enum u8 { Face, Stack, Water }
Motion :: enum u8 { Soar, Hover, Hold, Perch }
Hinge  :: enum u8 { Body, Tail, Fin, Pair, Wing, Tip, Leg }   // from Pair on, a part is drawn on both sides
// A box of the body: its middle and half its size in metres at full length (x right, y up, z
// forward), what it turns on, and its colour on top and on its other faces (flanks and belly), as 0xRRGGBB.
Part :: struct { at, half: [3]f32, hinge: Hinge, upper, under: u32 }
Creature :: struct {
	name, why: string,
	home:      Home,
	motion:    Motion,
	host:      []Window,
	most:      int,       // homes on an island at most, `apart` metres apart
	apart:     f32,
	number:    [2]f32,    // a bird: how many at a home; a fish: how many to a square metre of water
	deep:      [2]f32,    // a fish: the water it holds in, metres deep
	lakes:     bool,      // a fish: it lives in lakes as well as streams
	season:    [2]f32,    // the days of the year it is here
	climb:     f32,       // a fish: the tallest fall it gets past on its way up from the sea
	reached:   f32,       // and the share of streams above a taller fall it got up before and lives on in
	length:    [2]f32,    // metres, when it comes and once grown
	drawn:     f32,       // how many times larger than life it is drawn, so that it reads at all (see real-creatures.md)
	speed:     f32,       // metres a second it flies at
	beat:      f32,       // wing or tail beats a second
	shy, dart: f32,       // a fish: metres off a person it darts from, and how far
	parts:     []Part,
}
CREATURES := [?]Creature{
	{"black kite", "it soars on the wind the face turns upward, scanning the shore below", .Face, .Soar, {{.Lift, 1, ANY, 0.5}}, 3, 500, {2, 5}, {}, false, {0, 366}, 0, 0, {0.6, 0.6}, 1, 7, 2.5, 0, 0, {
		{{0, 0, 0.02}, {0.065, 0.055, 0.17}, .Body, 0x5a412c, 0x6b4a32},
		{{0, 0.02, 0.22}, {0.05, 0.045, 0.06}, .Body, 0x8a7560, 0x7a6550},
		{{0, -0.005, -0.28}, {0.09, 0.008, 0.13}, .Tail, 0x5f4530, 0x7a5c40},
		{{0.25, 0, 0.04}, {0.19, 0.012, 0.12}, .Wing, 0x4e3826, 0x5e4632},
		{{0.61, 0, 0}, {0.18, 0.01, 0.09}, .Tip, 0x2e231b, 0x9a9080},
	}},
	{"osprey", "a pair nests on the stack's top, out of reach, and fishes the sea round it", .Stack, .Hover, {{.Height, 8, ANY, 4}}, 1, 0, {2, 2}, {}, false, {0, 366}, 0, 0, {0.57, 0.57}, 1, 9, 2.6, 0, 0, {
		{{0, 0, 0.02}, {0.07, 0.06, 0.16}, .Body, 0x3b2a1e, 0xe8e6e0},
		{{0, 0.02, 0.21}, {0.05, 0.05, 0.06}, .Body, 0xe6e2d8, 0xe6e2d8},
		{{0.051, 0.025, 0.21}, {0.004, 0.012, 0.045}, .Pair, 0x2a2018, 0x2a2018},
		{{0, -0.005, -0.25}, {0.07, 0.008, 0.1}, .Tail, 0x4a3828, 0xcfc8bc},
		{{0.24, 0, 0.03}, {0.18, 0.012, 0.11}, .Wing, 0x3b2a1e, 0xd8d4cc},
		{{0.6, 0, 0}, {0.2, 0.01, 0.085}, .Tip, 0x2b2018, 0x8a8070},
		{{0.035, -0.12, 0.03}, {0.012, 0.06, 0.012}, .Leg, 0xb8bcc0, 0xb8bcc0},
	}},
	{"ayu", "it comes up from the sea in April, holds facing the current over the stones it grazes, spawns low in the stream in November and dies", .Water, .Hold, {{.Discharge, 0.05, ANY, 0}}, 0, 0, {0.1, 0.1}, {0.3, 3}, false, {90, 324}, 2.5, 0, {0.08, 0.2}, 2, 0, 2.5, 3.5, 3, {
		{{0, 0, 0}, {0.02, 0.022, 0.07}, .Body, 0x7a7448, 0xc0c4b4},
		{{0, -0.002, 0.09}, {0.016, 0.017, 0.022}, .Body, 0x6a6648, 0xc0c4bc},
		{{0, 0, -0.092}, {0.004, 0.02, 0.022}, .Fin, 0x6a6040, 0x8a8a70},
	}},
	{"yoshinobori", "a small goby, it rests on the bed of pool and lake on its sucker of fins and climbs falls that turn back every other fish", .Water, .Perch, {}, 0, 0, {0.3, 0.3}, {0.1, 2.5}, true, {0, 366}, 5, 0.25, {0.07, 0.07}, 2.5, 0, 3, 2, 1, {
		{{0, 0, 0}, {0.011, 0.008, 0.026}, .Body, 0x6b5a40, 0x8a7a5c},
		{{0, 0.001, 0.03}, {0.012, 0.008, 0.012}, .Body, 0x5e4e38, 0x7a6a50},
		{{0, 0, -0.035}, {0.002, 0.006, 0.01}, .Fin, 0x6b5a40, 0x6b5a40},
	}},
}
BIRD_FAR :: 3000   // metres off beyond which no bird is drawn: past about 1 km one is a pixel or less
FISH_FAR :: 40     // and no fish, which under water shows little past 20

// One box as the GPU takes it (vs_box, shaders.metal): its middle from the eye and its three half
// axes, with the colours and the depth of water over it in the spare places.
Box :: struct { centre: [3]f32, upper: f32, x: [3]f32, under: f32, y: [3]f32, wet: f32, z: [3]f32, _: f32 }
Haunt :: struct { row, feature, n: int, at, out: [2]f64, a, b, y, nest: f32 }   // a bird's home: where it circles, how wide and high, and a nest
Fauna :: struct {
	barrier: []f32, over: []i32,   // on each land cell: the tallest fall between it and the sea, and that fall
	haunts:  [dynamic]Haunt,
	fish:    []u8,                 // the kinds of fish in each segment of stream, a bit each
	lakes:   map[int]u8,           // and in each lake, by its feature
	fled:    map[u64][3]f32,       // how far each startled fish near the player has fled, 0 to 1, and which way
}
fauna: Fauna

// Where the animals live, and the start-up lines that say so.
creatures_make :: proc() {
	started := time.now()
	g, n := land.grid, land.n
	fauna.barrier, fauna.over = make([]f32, n*n), make([]i32, n*n)
	tall, foot := make([]f32, n*n, context.temp_allocator), make([]i32, n*n, context.temp_allocator)
	for f, i in region.features do if c := land_cell(f.at.x, f.at.y); f.kind == .Fall && f.measured[0].value > tall[c] do tall[c], foot[c] = f.measured[0].value, i32(i)
	for ci in g.order {   // from the shore up, so the cell below is done first
		c, r := int(ci), int(g.next[ci])
		fauna.over[c] = -1
		if r == SINK do fauna.barrier[c] = 1e4   // a crater floor: no stream joins it to the sea
		if r < 0 do continue
		fauna.barrier[c], fauna.over[c] = fauna.barrier[r], fauna.over[r]
		if tall[r] > fauna.barrier[c] do fauna.barrier[c], fauna.over[c] = tall[r], foot[r]
	}
	lives :: proc(k: int, x, z: f64) -> bool {   // whether a fish of row k lives in the stream or lake at a point
		row, c := CREATURES[k], land_cell(x, z)
		p := Point{x = x, z = z, cell = LAND_CELL}
		return host(row.host, &p) > 0 && (fauna.barrier[c] <= row.climb || fauna.over[c] >= 0 && fauna.barrier[c] < 1e4 && hash01(fauna.over[c], i32(k), seed + 801) < row.reached)
	}
	fauna.fish = make([]u8, len(rivers.segments))
	metres: [len(CREATURES)]f32
	for s, id in rivers.segments do for row, k in CREATURES do if row.home == .Water {
		mid := (s.a + s.b)/2
		if land.lake[land_cell(f64(mid.x), f64(mid.y))] == 0 && lives(k, f64(mid.x), f64(mid.y)) do fauna.fish[id], metres[k] = fauna.fish[id] | 1 << uint(k), metres[k] + linalg.length(s.b - s.a)
	}
	ponds: int
	for f, i in region.features {
		ponds += int(f.kind == .Pond)
		if f.kind == .Lake do for row, k in CREATURES do if row.lakes && lives(k, f.at.x, f.at.y) do fauna.lakes[i] |= 1 << uint(k)
	}

	fmt.printf("creatures in %.0f ms on the %s island:", time.duration_milliseconds(time.since(started)), region.kind)
	for row, k in CREATURES {
		first := len(fauna.haunts)
		switch row.home {
		case .Face, .Stack:   // the best homes the host holds at, `apart` metres apart
			Spot :: struct { s: f32, at: [2]f64, top: f32, cause: int }
			spots := make([dynamic]Spot, context.temp_allocator)
			if row.home == .Face do for c in candidates do if c.kind == .Face {
				p := Point{x = c.at.x, z = c.at.y, cell = LAND_CELL}
				if s := host(row.host, &p); s > 0 do append(&spots, Spot{s*c.m, c.at, c.top + c.m/2, -1})
			}
			if row.home == .Stack do for pl in pillars do if pl.top == region.features[pl.feature].level {
				p := point_at(pl.at.x, pl.at.y, 1)
				if s := host(row.host, &p); s > 0 do append(&spots, Spot{s*p.h, pl.at, p.h, pl.feature})
			}
			slice.sort_by(spots[:], proc(a, b: Spot) -> bool { return a.s > b.s })
			next: for sp in spots {
				if len(fauna.haunts) - first >= row.most do break
				for h in fauna.haunts[first:] do if math.hypot(h.at.x - sp.at.x, h.at.y - sp.at.y) < f64(row.apart) do continue next
				haunt_make(k, sp.at, sp.top, sp.cause)
			}
			if len(fauna.haunts) == first do fmt.printf("\n  no %s: %s", row.name, "no face 25 m tall turns the wind up at 1 m/s or more" if row.home == .Face else "no sea stack stands 8 m or more over the waves to nest on")
			else {
				fmt.printf("\n  %ss: %s; at", row.name, row.why)
				for h, i in fauna.haunts[first:] do fmt.printf("%s %.0f, %.0f (%d, %.0f m up)", "," if i > 0 else "", h.at.x + f64(region.origin.x), h.at.y + f64(region.origin.y), h.n, h.nest if row.home == .Stack else h.y)
			}
		case .Water:
			in_lakes: int
			for _, bits in fauna.lakes do in_lakes += int(bits >> uint(k) & 1)
			if metres[k] == 0 && in_lakes == 0 do fmt.printf("\n  no %s: no stream big enough for it reaches the sea without a fall over %.1f m", row.name, row.climb)
			else do fmt.printf("\n  %s: %s; in %s of stream%s", row.name, row.why, fmt.tprintf("%.0f m", metres[k]) if metres[k] < 1000 else fmt.tprintf("%.1f km", metres[k]/1000), fmt.tprintf(" and %d lake%s", in_lakes, "" if in_lakes == 1 else "s") if row.lakes else "")
			if row.season[0] > 0 do fmt.printf(", from day %.0f to %.0f", row.season[0], row.season[1])
			fmt.printf(". Not above a fall over %.1f m%s", row.climb, fmt.tprintf(", but in %.0f%% of the streams over one it got up first", 100*row.reached) if row.reached > 0 else "")
			for w in row.host do if w.field == .Discharge do fmt.printf(", nor where the stream runs under %.2f m³/s", w.lo)
		}
	}
	best := -1   // the pool under the tallest fall that has fish in it
	for f, i in region.features do if f.kind == .Fall && f.level - f.measured[0].value > SEA_SURFACE + 0.5 && (best < 0 || f.measured[0].value > region.features[best].measured[0].value) {
		for row, k in CREATURES do if row.home == .Water && lives(k, f.at.x, f.at.y) {
			best = i
			break
		}
	}
	if best >= 0 {
		f := region.features[best]
		fmt.printf("\n  the best pool: under the %.0f m fall at %.0f, %.0f, %.1f m deep, with", f.measured[0].value, f.at.x + f64(region.origin.x), f.at.y + f64(region.origin.y), f.measured[2].value)
		for row, k in CREATURES do if row.home == .Water && lives(k, f.at.x, f.at.y) do fmt.printf(" %s", row.name)
	}
	if ponds > 0 do fmt.printf("\n  no fish in the %d pond%s: no stream joins %s to the sea", ponds, "" if ponds == 1 else "s", "it" if ponds == 1 else "them")
	fmt.printfln("\n  no gulls, no shearwaters and no fish in the rock pools: see interesting-world/notes/real-creatures.md")
}

// A bird's home: where it circles, kept clear of the ground and the trees on it.
haunt_make :: proc(k: int, at: [2]f64, top: f32, cause: int) {
	row, i := CREATURES[k], i32(len(fauna.haunts))
	h := Haunt{row = k, feature = len(region.features), at = at, n = int(math.round(math.lerp(row.number[0], row.number[1], hash01(i, 0, seed + 802))))}
	clear_of :: proc(h: ^Haunt, margin: f32) {   // raise the circle over the highest ground under it
		along := [2]f64{-h.out.y, h.out.x}
		for t in 0..<48 {
			a := f64(t)*math.PI/24
			p := h.at + h.out*f64(h.b)*math.sin(a) + along*f64(h.a)*math.cos(a)
			h.y = max(h.y, ground(p.x, p.y, 4).h + margin)
		}
	}
	if row.home == .Face {   // a long loop along the face, out toward the wind and over its top
		b := math.to_radians(f64(land.facing[land_cell(at.x, at.y)]))
		h.out = {math.sin(b), -math.cos(b)}
		h.at += h.out*40
		h.a, h.b, h.y = math.lerp(f32(70), 140, hash01(i, 1, seed + 802)), math.lerp(f32(20), 40, hash01(i, 2, seed + 802)), top + math.lerp(f32(15), 40, hash01(i, 3, seed + 802))
		clear_of(&h, 36)   // trees, and the loop's rise and fall
	} else {   // a circle over the deepest water round the stack, the nest on its top
		deepest := f32(1e9)
		for t in 0..<8 {
			d := [2]f64{math.cos(f64(t)*math.PI/4), math.sin(f64(t)*math.PI/4)}
			if sea := ground(at.x + 80*d.x, at.y + 80*d.y, 4).h; sea < deepest do h.out, deepest = d, sea
		}
		h.nest, h.at = top, at + h.out*75
		h.a, h.b, h.y = 40, 40, 25
		clear_of(&h, 12)
		h.at = at   // the home is the stack; the circle is reckoned from it again when posed
	}
	append(&fauna.haunts, h)
	p := Point{x = at.x, z = at.y, cell = LAND_CELL}
	append(&region.features, Feature{kind = .Haunt, at = at, reach = h.a, size = f32(h.n), level = h.y, cause = cause,
		measured = {{fmt.aprintf("%ss living here", row.name), f32(h.n)}, {"wind turned up the face, m/s", FIELDS[.Lift].at(&p)} if row.home == .Face else {"how open its shore is to the swell", region.features[cause].measured[0].value}, {"height of what it is on, m", top}}})
}

// Metres of water over the ground in the simulated column at a point in the world, and that ground.
water_at :: proc(wt: ^Water, x, z: f64) -> (floor, depth: f32, ok: bool) {
	i := water_cell(i32(math.floor(x)), i32(math.floor(z)))
	return wt.floor[i], wt.depth[i], wt.floor[i] < WALL/2
}

// The boxes of every animal near enough to see, posed for the clock, from the eye.
creatures_pose :: proc(eye: [3]f64, clock: f64, dt, hour, day: f32, wt: ^Water) -> []Box {
	out := make([dynamic]Box, 0, 512, context.temp_allocator)
	o := [2]f64{f64(region.origin.x), f64(region.origin.y)}
	e := [3]f64{eye.x - o.x, eye.y, eye.z - o.y}
	rel :: proc(p: [2]f64, y: f32, e: [3]f64) -> [3]f32 { return {f32(p.x - e.x), f32(f64(y) - e.y), f32(p.y - e.z)} }
	wave :: proc(t, hz, phase: f64) -> f32 { return f32(math.sin(math.mod(t*hz, 1)*math.TAU + phase)) }
	day_lit := sun_dir(hour, day).y > 0
	wind := math.to_radians(f32(region.shape.swell))
	for h, i in fauna.haunts {
		row := CREATURES[h.row]
		if math.hypot(h.at.x - e.x, h.at.y - e.z) > BIRD_FAR do continue
		along := [2]f64{-h.out.y, h.out.x}
		if row.home == .Stack {   // the nest: a heap of sticks with a rim
			at := rel(h.at, h.nest, e)
			append(&out, Box{at + {0, 0.12, 0}, f32(0x6e5f4a), {0.65, 0, 0}, f32(0x6e5f4a), {0, 0.12, 0}, 0, {0, 0, 0.6}, 0})
			for s in ([4][2]f32{{0.55, 0}, {-0.55, 0}, {0, 0.5}, {0, -0.5}}) do append(&out, Box{at + {s.x, 0.3, s.y}, f32(0x5c4e3a), {0.12 + 0.55*abs(s.y), 0, 0}, f32(0x5c4e3a), {0, 0.1, 0}, 0, {0, 0, 0.12 + 0.6*abs(s.x)}, 0})
		}
		for k in 0..<h.n {
			r := draws(i32(i), i32(k))
			if row.motion == .Soar && !day_lit do break   // at night it roosts in the woods
			if row.motion == .Hover && (k == 0 || !day_lit) {   // on the nest, upright, facing the wind
				body(&out, row, {at = rel(h.at + along*(0.5*f64(k)), h.nest + 0.62, e), bearing = wind + 0.4*r[0], pitch = 0.7, flap = -1.4, sweep = 1.45, tail = -0.5, scale = 1, stand = true})
				continue
			}
			phase := f64(r[0])*math.TAU
			p, v: [2]f64
			y, bank, pitch, flap, bend: f32
			if row.motion == .Soar {   // to and fro on the lift, each at its own pace and height
				dir := 1 if r[1] < 0.5 else -1.0
				w := f64(row.speed)/f64(h.a + h.b)*2*(0.85 + 0.3*f64(r[2]))
				th := math.mod(phase + dir*w*clock, math.TAU)
				p = h.at + along*f64(h.a)*math.cos(th) + h.out*f64(h.b)*math.sin(th)
				v = (along*-f64(h.a)*math.sin(th) + h.out*f64(h.b)*math.cos(th))*dir*w
				turn := (h.a*h.b)/f32(math.pow(f64(h.a*h.a)*math.sin(th)*math.sin(th) + f64(h.b*h.b)*math.cos(th)*math.cos(th), 1.5))   // the curvature of the loop
				y, bank = h.y + 15*r[3] + 5*wave(clock, 0.02, phase), -f32(dir)*math.atan(f32(linalg.length(v)*linalg.length(v))*turn/9.8)
				flap, bend = 0.08, -0.06
				if hash01(i32(i*64 + k), i32(clock/6), seed + 803) > 0.8 do flap, bend = 0.08 + 0.45*wave(clock, f64(row.beat), phase), 0.2*wave(clock, f64(row.beat), phase - 0.8)
			} else {   // round the sea off the stack, slowing now and then to hang over the water on beating wings
				w, slow := f64(row.speed)/f64(h.a)/2, 0.07 + 0.03*f64(r[2])
				th := phase + w*(clock - math.sin(math.mod(slow*clock, math.TAU))/slow)
				centre := h.at + h.out*75
				p = centre + along*f64(h.a)*math.cos(th) + h.out*f64(h.b)*math.sin(th)
				v = (along*-f64(h.a)*math.sin(th) + h.out*f64(h.b)*math.cos(th))*w*(1 - math.cos(math.mod(slow*clock, math.TAU)))
				hover := smoothstep(2, 0.5, f32(linalg.length(v)))
				y, bank, pitch = h.y + 8*r[3], -0.35*(1 - hover), 0.5*hover
				flap, bend = 0.1 + (0.35 + 0.25*hover)*wave(clock, f64(row.beat*(1 + hover)), phase), 0.25*wave(clock, f64(row.beat*(1 + hover)), phase - 0.8)
			}
			bearing := f32(math.atan2(v.x, -v.y))
			body(&out, row, {at = rel(p, y, e), bearing = bearing, bank = bank, pitch = pitch, flap = flap, bend = bend, sweep = 0.12, tail = -0.05 - 0.3*pitch, scale = 1})
		}
	}
	// Fish in the streams and lakes round the eye.
	rim := region.size/2
	bx, bz := int(e.x + rim)/BUCKET, int(e.z + rim)/BUCKET
	if bx < 0 || bz < 0 || bx >= rivers.side || bz >= rivers.side do return out[:]
	for id in rivers.buckets[bz*rivers.side + bx] do if bits := fauna.fish[id]; bits != 0 {
		s := rivers.segments[id]
		ab, ae := s.b - s.a, [2]f32{f32(e.x), f32(e.z)} - s.a
		if linalg.length(ae - ab*clamp(linalg.dot(ae, ab)/linalg.dot(ab, ab), 0, 1)) > FISH_FAR do continue
		flow, side := linalg.normalize0([2]f64{f64(ab.x), f64(ab.y)}), [2]f64{-f64(ab.y), f64(ab.x)}/max(f64(linalg.length(ab)), 1e-3)
		for k in 0..<len(CREATURES) do if bits >> uint(k) & 1 != 0 {
			row := CREATURES[k]
			many := linalg.length(ab)*(s.half_a + s.half_b)*row.number[0]*(3 if s.pool > 0 else 1)
			for j in 0..<int(many + hash01(i32(id), i32(k), seed + 804)) {
				r := draws(i32(id), i32(j) + 1000*i32(k))
				u := r[0]*r[0] if s.pool > 0 else r[0]   // crowded into a fall's pool, at the segment's head
				at := [2]f64{f64(s.a.x + ab.x*u), f64(s.a.y + ab.y*u)} + side*f64((r[1] - 0.5)*1.4*math.lerp(s.half_a, s.half_b, u))
				fish(&out, k, u64(id) << 24 | u64(j) << 4 | u64(k), at, flow, e, o, clock, dt, day, wt)
			}
		}
	}
	c0, n := land_cell(e.x, e.z), land.n
	for dy in -3..=3 do for dx in -3..=3 do if c := c0 + dy*n + dx; c >= 0 && c < n*n && land.lake[c] > 0 && linalg.length(middle_of(land.grid, c) - e.xz) < FISH_FAR + 12 {
		bits := fauna.lakes[int(land.lake[c]) - 1] or_else 0
		for k in 0..<len(CREATURES) do if bits >> uint(k) & 1 != 0 do for j in 0..<int(LAND_CELL*LAND_CELL*CREATURES[k].number[0]) {
			r := draws(i32(c), i32(j) + 1000*i32(k))
			fish(&out, k, u64(c) << 24 | u64(j) << 4 | u64(k) | 1 << 63, middle_of(land.grid, c) + {f64(r[0] - 0.5), f64(r[1] - 0.5)}*LAND_CELL, {}, e, o, clock, dt, day, wt)
		}
	}
	return out[:]
}

// Four draws in 0..1 for an animal.
draws :: proc(a, b: i32) -> [4]f32 { return {hash01(a, b, seed + 805), hash01(a, b, seed + 806), hash01(a, b, seed + 807), hash01(a, b, seed + 808)} }

// One fish at rest in the water at `at`, facing into the current `flow` (none in a lake), if the water
// is there, darting away from a person come near and drifting back. Water that is not deep enough, or
// is not yet simulated, has none.
fish :: proc(out: ^[dynamic]Box, k: int, key: u64, at, flow: [2]f64, e: [3]f64, o: [2]f64, clock: f64, dt, day: f32, wt: ^Water) {
	row := CREATURES[k]
	if day < row.season[0] || day > row.season[1] || math.hypot(at.x - e.x, at.y - e.z) > FISH_FAR do return
	ok_at :: proc(row: Creature, wt: ^Water, p: [2]f64) -> (floor, depth: f32, ok: bool) {
		floor, depth, ok = water_at(wt, p.x, p.y)
		return floor, depth, ok && depth >= row.deep[0] && depth <= row.deep[1]
	}
	floor, depth, ok := ok_at(row, wt, at + o)
	if !ok do return
	r := draws(i32(key >> 4), i32(key & 0xF) + 77)
	phase := f64(r[0])*math.TAU
	t := clock + 50*f64(r[1])
	p, heading := at, f32(math.atan2(-flow.x, flow.y)) if flow != {} else r[2]*math.TAU
	if row.motion == .Hold {   // it drifts and sways a hand or two, swinging a little off the current
		p += flow*0.25*f64(math.sin(0.5*t + phase)) + [2]f64{-flow.y, flow.x}*0.12*f64(math.sin(0.37*t + 2*phase))
		heading += 0.25*f32(math.sin(0.3*t + phase))
	} else do heading += 1.2*f32(math.floor(t/(5 + 4*f64(r[3]))))   // it rests, and turns now and then
	// Startled: it darts off quickly when a person comes near, and drifts back over a few seconds.
	d := p - e.xz
	near := linalg.length(d) < f64(row.shy) && f32(e.y) - (floor + depth) < row.shy
	was := fauna.fled[key] or_else {}
	fled := clamp(was.x + (dt/0.3 if near else -dt/8), 0, 1)
	away := [2]f64{f64(was.y), f64(was.z)} if was.x > 0 else linalg.normalize0(d) if linalg.length(d) > 0.1 else flow   // the way it first fled
	if fled > 0 do fauna.fled[key] = {fled, f32(away.x), f32(away.y)}
	else do delete_key(&fauna.fled, key)
	beat := row.beat
	if fled > 0 {
		for s in ([3]f64{1, 0.6, 0.3}) {   // as far as the water lets it
			q := p + away*f64(row.dart*smoothstep(0, 1, fled))*s
			if fl, dp, ok := ok_at(row, wt, q + o); ok {
				p, floor, depth = q, fl, dp
				break
			}
		}
		heading, beat = f32(math.atan2(away.x, -away.y)), beat*(1 + 3*fled)
	}
	grown := clamp((day - row.season[0])/90, 0, 1)
	scale := row.drawn*math.lerp(row.length[0], row.length[1], grown)/row.length[1]
	y := floor + 0.008*scale if row.motion == .Perch else floor + clamp(0.4*depth, 0.1, depth - 0.12)
	tail := (0.15 + 0.3*fled)*f32(math.sin(math.mod(clock*f64(beat), 1)*math.TAU + phase))
	body(out, row, {at = {f32(p.x - e.x), f32(f64(y) - e.y), f32(p.y - e.z)}, bearing = heading, tail = tail if row.motion == .Hold || fled > 0 else 0, scale = scale, wet = floor + depth - y})
}

// How an animal is held: where it is from the eye, which way it heads (radians from north), its
// pitch and bank, its wings lifted by `flap` at the shoulder and `bend` at the wrist and swept back by
// `sweep`, its tail turned, its size against full grown, and whether it stands.
Pose :: struct { at: [3]f32, bearing, pitch, bank, flap, bend, sweep, tail, scale, wet: f32, stand: bool }
body :: proc(out: ^[dynamic]Box, row: Creature, q: Pose) {
	f, r, u := [3]f32{math.sin(q.bearing), 0, -math.cos(q.bearing)}, [3]f32{math.cos(q.bearing), 0, math.sin(q.bearing)}, [3]f32{0, 1, 0}
	f, u = f*math.cos(q.pitch) + u*math.sin(q.pitch), u*math.cos(q.pitch) - f*math.sin(q.pitch)
	r, u = r*math.cos(q.bank) - u*math.sin(q.bank), u*math.cos(q.bank) + r*math.sin(q.bank)
	r, u, f = r*q.scale, u*q.scale, f*q.scale
	R := matrix[3, 3]f32{r.x, u.x, f.x, r.y, u.y, f.y, r.z, u.z, f.z}
	turn :: proc(c: [3]f32, m: matrix[3, 3]f32, pivot: [3]f32, axis: int, a: f32) -> ([3]f32, matrix[3, 3]f32) {
		axes := [3][3]f32{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
		t := linalg.matrix3_rotate_f32(a, axes[axis])
		return pivot + t*(c - pivot), t*m
	}
	shoulder: f32
	for p in row.parts do if p.hinge == .Wing do shoulder = p.at.x - p.half.x
	for p in row.parts {
		if p.hinge == .Leg && !q.stand || p.hinge == .Tip && q.stand do continue
		for side in ([2]f32{1, -1}) {
			if side < 0 && p.hinge < .Pair do break
			c, m := p.at*{side, 1, 1}, linalg.MATRIX3F32_IDENTITY
			#partial switch p.hinge {
			case .Tail: c, m = turn(c, m, {0, 0, p.at.z + p.half.z}, 0, q.tail)
			case .Fin:  c, m = turn(c, m, {0, 0, p.at.z + p.half.z}, 1, q.tail)
			case .Tip, .Wing:
				if p.hinge == .Tip do c, m = turn(c, m, {side*(p.at.x - p.half.x), 0, 0}, 2, side*q.bend)
				c, m = turn(c, m, {side*shoulder, 0, 0}, 1, side*q.sweep)
				c, m = turn(c, m, {side*shoulder, 0, 0}, 2, side*q.flap)
			}
			a := R*m
			append(out, Box{q.at + R*c, f32(p.upper), a*[3]f32{p.half.x, 0, 0}, f32(p.under), a*[3]f32{0, p.half.y, 0}, q.wet, a*[3]f32{0, 0, p.half.z}, 0})
		}
	}
}

// What lives at a point and why, or why not, as --why prints it.
creature_words :: proc(x, z: f64) {
	for h in fauna.haunts do if d := math.hypot(h.at.x - x, h.at.y - z); d < f64(h.a) + 150 {
		row, f := CREATURES[h.row], region.features[h.feature]
		fmt.printfln("%d %ss live here, %.0f m off: %s. Measured when it was chosen: %s %.1f; %s %.0f.", h.n, row.name, d, row.why, f.measured[1].what, f.measured[1].value, f.measured[2].what, f.measured[2].value)
	}
	c := land_cell(x, z)
	near, by := -1, f32(30)
	if r, ok := river_near(f32(x), f32(z)); ok && r.d - r.half < 20 {
		rim := region.size/2
		for id in rivers.buckets[int(z + rim)/BUCKET*rivers.side + int(x + rim)/BUCKET] {
			s := rivers.segments[id]
			ab, ap := s.b - s.a, [2]f32{f32(x), f32(z)} - s.a
			if d := linalg.length(ap - ab*clamp(linalg.dot(ap, ab)/linalg.dot(ab, ab), 0, 1)); d < by do near, by = int(id), d
		}
	}
	lake := int(land.lake[c]) - 1
	if near < 0 && lake < 0 do return
	bits, what := u8(0), "stream"
	if near >= 0 do bits = fauna.fish[near]
	else do bits, what = fauna.lakes[lake] or_else 0, "lake" if region.features[lake].kind == .Lake else "pond"
	fmt.printf("in the %s here, the tallest fall between it and the sea is %.0f m (barrier)", what, fauna.barrier[c])
	for row, k in CREATURES do if row.home == .Water {
		if bits >> uint(k) & 1 != 0 do fmt.printf("; %s live in it%s: %s", row.name, fmt.tprintf(" from day %.0f to %.0f", row.season[0], row.season[1]) if row.season[0] > 0 else "", row.why)
		else if what == "pond" do fmt.printf("; no %s: no stream joins the pond to the sea", row.name)
		else if what == "lake" && !row.lakes do fmt.printf("; no %s: it lives in running water", row.name)
		else if fauna.barrier[c] > row.climb do fmt.printf("; no %s: it gets past no fall over %.1f m%s", row.name, row.climb, ", and did not get up this stream first" if row.reached > 0 else "")
		else do fmt.printf("; no %s: the stream runs %.3f m³/s, under what it needs", row.name, discharge(land.valley[c]))
	}
	fmt.println(".")
}

// Each bird's home on the map, ringed in pale blue, and each stretch of stream with fish dotted green.
creatures_mark :: proc(pixels: []u8, size: int) {
	put :: proc(pixels: []u8, size: int, at: [2]f64, r0, r1: int, colour: [3]u8) {
		cx, cy := int((at.x + region.size/2)*f64(size)/region.size), int((at.y + region.size/2)*f64(size)/region.size)
		for dy in -r1..=r1 do for dx in -r1..=r1 do if d := dx*dx + dy*dy; d >= r0*r0 && d <= r1*r1 && cx + dx >= 0 && cy + dy >= 0 && cx + dx < size && cy + dy < size {
			for k in 0..<3 do pixels[((cy + dy)*size + cx + dx)*4 + k] = colour[k]
		}
	}
	for s, id in rivers.segments do if fauna.fish[id] != 0 do put(pixels, size, {f64(s.a.x), f64(s.a.y)}, 0, 0, {60, 220, 90} if fauna.fish[id] & 0b100 != 0 else {170, 240, 120})
	for h in fauna.haunts do put(pixels, size, h.at, 5, 7, {150, 210, 255})
}
