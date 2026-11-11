package main

import "core:math"
import "core:math/linalg"
import "core:slice"

// Rivers. The simulation says where water runs and how much; this file turns that into
// channels a person can stand beside. Each stream is traced down the drainage network,
// smoothed and given a slight wander. Its width comes from the land it drains, and its
// bank level comes from the filled surface the water ran down, so it only ever falls
// toward the sea. The generator cuts bed, banks and a strip of valley floor along the
// line, and the water itself is a ribbon drawn at the true water level. Where the
// channel turns, the outside bank is cut steep and the inside builds a gravel bar. Where
// the ground is steep, the stream drops from pool to pool.

FREEBOARD   :: 0.4   // metres from the water up to the bank top
MOUTH_BANK  :: -1    // bank level where a channel runs on under the sea
RIVER_REACH :: 96    // metres from a channel beyond which the ground is never touched
BUCKET      :: 64    // metres; segments are filed by the squares they can affect
BUCKETS     :: LAND_SIZE/BUCKET

River_Point :: struct {
	p:    [2]f32,   // x, z
	bank: f32,      // elevation of the bank top
	area: f32,      // land draining through here, m²
}

Segment :: struct {
	a, b:           [2]f32,
	bank_a, bank_b: f32,
	half_a, half_b: f32,   // half the channel width
	bend_a, bend_b: f32,   // how sharply the channel turns: -1 hard right to 1 hard left, looking downstream
}

// A place on a river bank, for choosing where to start.
Spot :: struct {
	p:    [3]f32,
	yaw:  f32,   // facing downstream
	area: f32,
}

Rivers :: struct {
	segments: [dynamic]Segment,
	buckets:  [][dynamic]i32,
	ribbon:   [dynamic][4]f32,   // the water surface as one triangle strip: x, y, z, and -1 to 1 across the channel
	spots:    [dynamic]Spot,
}

rivers: Rivers

// Channel width grows with the land drained: about 2 m at a spring, 9 m for 15 km².
river_half :: proc(area: f32) -> f32 {
	return 0.5*clamp(1.6 + 2.3*math.pow(area/1e6, 0.45), 2, 14)
}

river_depth :: proc(half: f32) -> f32 {
	return 0.8 + 0.2*half
}

rivers_trace :: proc() {
	g := land.grid
	n := g.n
	rivers.buckets = make([][dynamic]i32, BUCKETS*BUCKETS)
	stream :: proc(g: ^Grid, c: i32) -> bool { return g.area[c] >= CHANNEL_AREA }
	point :: proc(g: ^Grid, c: i32) -> River_Point {
		p := [2]f32{f32(int(c)%g.n) + 0.5, f32(int(c)/g.n) + 0.5} + g.jitter[c]
		return {p*g.d - LAND_SIZE/2, g.fill[c], g.area[c]}
	}

	feeders := make([]u8, n*n)
	defer delete(feeders)
	for c in g.order {
		if r := g.next[c]; stream(g, c) && r >= 0 do feeders[r] += 1
	}
	points: [dynamic]River_Point
	defer delete(points)
	for c in g.order {
		if !stream(g, c) || feeders[c] == 1 do continue   // a reach begins at a spring or below a confluence
		clear(&points)
		at := c
		for {
			append(&points, point(g, at))
			r := g.next[at]
			if r < 0 {
				// The mouth. The first sea cell is often only ankle deep, so carry on down
				// the sea bed to properly deep water, with the banks under the surface. The
				// channel is cut through the shallows and the sea fills it.
				cell := int(at)
				for _ in 0..<16 {
					lowest := -1
					for o in OFFSETS {
						x, y := cell%n + o.x, cell/n + o.y
						if x < 0 || y < 0 || x >= n || y >= n || g.uplift[y*n + x] != 0 do continue
						if lowest < 0 || g.z[y*n + x] < g.z[lowest] do lowest = y*n + x
					}
					if lowest < 0 || (cell != int(at) && g.z[lowest] >= g.z[cell]) do break
					cell = lowest
					append(&points, River_Point{([2]f32{f32(cell%n), f32(cell/n)} + 0.5)*g.d - LAND_SIZE/2, MOUTH_BANK, g.area[at]})
					if g.z[cell] < -2.5 do break
				}
				break
			}
			at = r
			if feeders[at] != 1 {
				append(&points, point(g, at))
				break
			}
		}
		if len(points) >= 2 do reach_build(points[:], u32(c))
	}
}

// One reach, from a spring or confluence down to the next confluence or the sea.
reach_build :: proc(traced: []River_Point, id: u32) {
	// Round the corners of the cell-to-cell path. Every new point lies between two old
	// ones, so bank levels still only fall.
	pts := slice.clone(traced, context.temp_allocator)
	for _ in 0..<2 {
		out := make([dynamic]River_Point, 0, len(pts)*2, context.temp_allocator)
		append(&out, pts[0])
		for i in 0..<len(pts) - 1 {
			a, b := pts[i], pts[i + 1]
			append(&out, River_Point{math.lerp(a.p, b.p, f32(0.25)), math.lerp(a.bank, b.bank, f32(0.25)), math.lerp(a.area, b.area, f32(0.25))})
			append(&out, River_Point{math.lerp(a.p, b.p, f32(0.75)), math.lerp(a.bank, b.bank, f32(0.75)), math.lerp(a.area, b.area, f32(0.75))})
		}
		append(&out, pts[len(pts) - 1])
		pts = out[:]
	}
	last := len(pts) - 1

	// Direction of flow at each point, and distance along the reach.
	flow := make([][2]f32, len(pts), context.temp_allocator)
	along := make([]f32, len(pts), context.temp_allocator)
	directions :: proc(pts: []River_Point, flow: [][2]f32) {
		last := len(pts) - 1
		for i in 0..=last do flow[i] = linalg.normalize0(pts[min(i + 1, last)].p - pts[max(i - 1, 0)].p)
	}
	directions(pts, flow)
	for i in 1..=last do along[i] = along[i - 1] + linalg.length(pts[i].p - pts[i - 1].p)
	// A wander from side to side, a couple of channel widths at most and fading to nothing
	// at both ends so reaches still meet.
	for i in 1..<last {
		half := river_half(pts[i].area)
		swing, _, _ := noise(f64(along[i]/(22*half)), f64(id%977), SEED + 200)
		taper := clamp(min(along[i], along[last] - along[i])/(6*half), 0, 1)
		pts[i].p += [2]f32{-flow[i].y, flow[i].x}*min(2.4*half, 6)*(swing*2 - 1)*taper
	}
	directions(pts, flow)

	// Width follows the land drained, swelling and narrowing along the way. The bend is the
	// channel's curvature measured against its width, smoothed so bars and cut banks are
	// a few widths long.
	half := make([]f32, len(pts), context.temp_allocator)
	bend := make([]f32, len(pts), context.temp_allocator)
	for i in 0..=last {
		swell, _, _ := noise(f64(along[i]/45), f64(id%977) + 31, SEED + 201)
		half[i] = river_half(pts[i].area)*(0.8 + 0.45*swell)
	}
	for i in 1..<last {
		turn := flow[i - 1].x*flow[i + 1].y - flow[i - 1].y*flow[i + 1].x
		bend[i] = clamp(5*half[i]*turn/(along[i + 1] - along[i - 1]), -1, 1)
	}
	for _ in 0..<3 {
		before := bend[0]
		for i in 1..<last {
			here := bend[i]
			bend[i] = (before + 2*here + bend[i + 1])/4
			before = here
		}
	}

	// Bank level at the two ends of each stretch between points. On gentle ground it
	// follows the land. On steep ground the stream falls in steps: level pools with a
	// sheer drop between them, which is what steep streams do and what blocks can show.
	// A pool sits at or below the land's own level, never above it, and both ends of the
	// reach keep the land's level so that reaches meet.
	from := make([]f32, last, context.temp_allocator)
	to := make([]f32, last, context.temp_allocator)
	level := pts[0].bank
	for i in 0..<last {
		up, down := max(i - 3, 0), min(i + 4, last)
		fall := (pts[up].bank - pts[down].bank)/max(along[down] - along[up], 1)
		if fall > 0.045 && min(along[i], along[last] - along[i + 1]) > 12 {
			pool := max(math.floor(pts[i + 1].bank - 0.9) + 0.9, pts[last].bank)   // just under a whole metre, so blocks round cleanly
			from[i] = min(pool, level)
			to[i] = from[i]
		} else {
			from[i] = min(pts[i].bank, level)
			to[i] = min(pts[i + 1].bank, from[i])
		}
		level = to[i]
	}

	// The water surface: a pair of points across the channel at each end of each stretch.
	// Where the level drops between stretches the two pairs stand one above the other and
	// the strip between them is a sheet of falling water.
	RIBBON :: 1.25   // drawn this much wider than the channel, so the water always reaches into its banks
	across :: proc(p: River_Point, flow: [2]f32, half, bank: f32) -> (l, r: [4]f32) {
		edge := [2]f32{-flow.y, flow.x}*(half*RIBBON + 0.3)
		return {p.p.x - edge.x, bank - FREEBOARD, p.p.y - edge.y, -1}, {p.p.x + edge.x, bank - FREEBOARD, p.p.y + edge.y, 1}
	}
	if len(rivers.ribbon) > 0 {   // join to the strip so far with a zero-area bridge
		l, _ := across(pts[0], flow[0], half[0], from[0])
		append(&rivers.ribbon, rivers.ribbon[len(rivers.ribbon) - 1], l)
	}
	for i in 0..=last {
		if i > 0 do append(&rivers.ribbon, across(pts[i], flow[i], half[i], to[i - 1]))
		if i < last && (i == 0 || from[i] < to[i - 1] - 0.01) do append(&rivers.ribbon, across(pts[i], flow[i], half[i], from[i]))
		if i == last do break

		a, b := pts[i], pts[i + 1]
		if i%8 == 4 {
			bank := a.p + [2]f32{-flow[i].y, flow[i].x}*(half[i]*1.3 + 5)
			append(&rivers.spots, Spot{{bank.x, from[i], bank.y}, math.atan2(flow[i].x, -flow[i].y), a.area})
		}
		index := i32(len(rivers.segments))
		append(&rivers.segments, Segment{a.p, b.p, from[i], to[i], half[i], half[i + 1], bend[i], bend[i + 1]})
		lo := linalg.min(a.p, b.p) - RIVER_REACH + LAND_SIZE/2
		hi := linalg.max(a.p, b.p) + RIVER_REACH + LAND_SIZE/2
		for bz in max(int(lo.y)/BUCKET, 0)..=min(int(hi.y)/BUCKET, BUCKETS - 1) {
			for bx in max(int(lo.x)/BUCKET, 0)..=min(int(hi.x)/BUCKET, BUCKETS - 1) {
				append(&rivers.buckets[bz*BUCKETS + bx], index)
			}
		}
	}
	free_all(context.temp_allocator)
}

River_Near :: struct {
	d:      f32,   // distance from the centre line
	half:   f32,   // half the channel width there
	bank:   f32,   // bank level there
	inside: f32,   // 1 on the inside of a sharp bend, -1 on the outside, 0 on a straight
}

// The nearest river to a point, judged from the water's edge, if one is within reach.
river_near :: proc(x, z: f32) -> (r: River_Near, ok: bool) {
	bx, bz := int(x + LAND_SIZE/2)/BUCKET, int(z + LAND_SIZE/2)/BUCKET
	if x < -LAND_SIZE/2 || z < -LAND_SIZE/2 || bx >= BUCKETS || bz >= BUCKETS do return
	p := [2]f32{x, z}
	nearest: f32 = RIVER_REACH
	for id in rivers.buckets[bz*BUCKETS + bx] {
		s := rivers.segments[id]
		ab, ap := s.b - s.a, p - s.a
		t := clamp(linalg.dot(ap, ab)/linalg.dot(ab, ab), 0, 1)
		d := linalg.length(ap - ab*t)
		half := math.lerp(s.half_a, s.half_b, t)
		if d - half < nearest {
			nearest = d - half
			side: f32 = 1 if ab.x*ap.y - ab.y*ap.x > 0 else -1   // left or right of the flow
			r, ok = {d, half, math.lerp(s.bank_a, s.bank_b, t), side*math.lerp(s.bend_a, s.bend_b, t)}, true
		}
	}
	return
}

// Cut a river into the ground at a point: a bed, banks rising to the bank top, then a strip
// of valley floor that eases back into the hillside. On the outside of a bend the bank is
// steep; on the inside the bed ramps up into a bar. `gravel` is true where the ground is
// river bed or bar. At a coarse cell size the cut is widened by the cell, so a far-off
// column that a stream crosses is always lowered beneath the water drawn over it.
river_cut :: proc(h: f32, x, z, cell: f64) -> (cut: f32, gravel: bool) {
	r, ok := river_near(f32(x), f32(z))
	if !ok do return h, false
	d := r.d
	if cell > 1 {
		d = max(d - 0.71*f32(cell), 0)
	} else {
		d = max(d + 0.22*r.half*fbm(x, z, 9, 1, 2, SEED + 210), 0)   // a ragged water's edge
	}
	bar, undercut := max(r.inside, 0), max(-r.inside, 0)
	edge := r.half*(1.2 + 0.6*bar)   // where the bank top is reached
	top := edge + 1.5                // the bank top is level this far, which keeps the water's edge in its banks
	floor := top + r.half*2 + 5
	if d >= floor do return h, false
	bed := r.bank - FREEBOARD - river_depth(r.half)
	if d < edge {
		steep := bed + (r.bank - bed)*smoothstep(r.half*(0.55 + 0.3*undercut), r.half*1.2, d)
		ramp := bed + (r.bank - bed)*d/edge
		cut = math.lerp(steep, ramp, bar)
		return cut, bar > 0.35 || math.round(cut) < r.bank - FREEBOARD - 0.05   // a bar, or a block whose top is under water
	}
	return math.lerp(r.bank, h, smoothstep(top, floor, d)), false
}
