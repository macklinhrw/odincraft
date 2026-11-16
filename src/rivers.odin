package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

// Rivers. The simulation says where water runs and how much; this file turns that into
// channels a person can stand beside. Each stream is traced down the drainage network,
// smoothed and given a slight wander. Its width comes from the land it drains, and its
// bank level comes from the filled surface the water ran down, so it only ever falls
// toward the sea. The generator cuts bed, banks and a strip of valley floor along the
// line. Near the player the water in the channel is simulated (water.odin); beyond that
// it is a ribbon drawn at the true water level. Where the
// channel turns, the outside bank is cut steep and the inside builds a gravel bar. Where
// the ground is steep, the stream drops from pool to pool, and where it is steeper still across a
// strong bed, it falls (`falls_make`).

FREEBOARD   :: 0.4   // metres from the water up to the bank top
MOUTH_BANK  :: -1    // bank level where a channel runs on under the sea
RIVER_REACH :: 96    // metres from a channel beyond which the ground is never touched
BUCKET      :: 64    // metres; segments are filed by the squares they can affect
RUNOFF      :: 2.0   // metres of the year's rain that runs off: some 3 m falls on the Izu islands and about 1 m goes back to the air (a guess)
FLOOD       :: 20    // how many times the mean flow a flood that scours a plunge pool carries (a guess)
FALL_STEEP  :: 0.3   // a stream steeper than this over 30 m falls where a strong bed holds a lip
FALL_AREA   :: 120_000   // m² a stream must drain to wear a fall back into a gorge; a smaller one hangs and runs down the face (Crosby & Whipple 2006: knickpoints stall at 0.1 to 1 km²)
// m² of land that must drain through a cell before a stream runs there. On Japan's humid forested
// hills a stream with water in it drains a hectare or less (a first-order catchment of 0.84 ha at
// Hitachi Ohta, Sidle et al. 2000; a second-order one of 2.3 ha on granite, Fujimoto et al. 2016),
// finer than the 16 m land shows: on real islands and ours alike, at 0.01 to 0.03 km² half or more
// of the cells a stream would run in lie in a hollow across its flow, and below 0.01 fewer than half
// (interesting-world/notes/real-hydrology.md). So streams begin at 0.02 km². CHANNEL_AREA stays the
// land's valleys, as the real islands were measured.
HEAD_AREA   :: 20_000
SPRING_AREA :: 5_000    // m² of land above a contact that feeds a spring, a quarter of what starts a stream (a guess)
// The rocks that pass water, through their pores or joints, have this trait in TRAITS (gen.odin);
// the others hold it (after the ranges in Freeze and Cherry, Groundwater, 1979, from memory):
// sandstone and grit, jointed limestone, lava flows broken by their joints and the cinders and
// pumice between them. Mudstone and siltstone hold it, as does stiff lava.
PASSES :: bit_set[Trait]{.Passes}
FALL_MIN    :: 2.5   // metres: a drop taller than this is a fall with water of its own; a step pool's steps of a block or two are not

River_Point :: struct {
	p:    [2]f32,   // x, z
	bank: f32,      // elevation of the bank top
	area: f32,      // land draining through here, m²
}

Segment :: struct {
	a, b:           [2]f32,
	bank_a, bank_b: f32,
	half_a, half_b: f32,   // half the channel width
	bed_a, bed_b:   f32,   // half the width of the bed of stones the floods keep bare, the channel in it
	bend_a, bend_b: f32,   // how sharply the channel turns: -1 hard right to 1 hard left, looking downstream
	drop:           f32,   // how far the water drops at the downstream end
	pool:           f32,   // how much deeper than the channel a fall has scoured the bed at the upstream end
	gorge:          bool,  // it runs in the gorge a fall cut, whose walls rise from the water
}

// A place on a river bank, for choosing where to start.
Spot :: struct {
	p:    [3]f32,
	yaw:  f32,   // facing downstream
	area: f32,
}

Drop :: struct { lip, dir: [2]f32, top, foot, half, speed: f32 }   // where the water leaves the lip, which way and how fast, and the levels it falls between

Rivers :: struct {
	segments: [dynamic]Segment,
	buckets:  [][dynamic]i32,   // `side` to a side of the region
	side:     int,
	ribbon:   [dynamic][4]f32,   // the water surface as one triangle strip: x, y, z relative to the region's middle, and -1 to 1 across the channel
	spots:    [dynamic]Spot,
	falls:    [dynamic]Water_Quad,   // the falling water, relative to the region's middle, drawn near and far
	drops:    [dynamic]Drop,         // each fall, for the spray it throws
}


// The mean flow, m³/s, of the rain that runs off the land drained (water.md, D3).
discharge :: proc(area: f32) -> f32 {
	return RUNOFF*area/3.156e7
}

// A channel's width grows as the root of its flow and its depth as the flow to the power 0.4
// (Leopold and Maddock): a brook a block wide and a hand deep where a stream starts, to be stepped
// over; a stream 3.5 m wide and knee deep at 1 km², to be waded; 9 m and chest deep at 7 km².
river_half :: proc(area: f32) -> f32 {
	return 0.5*clamp(14*math.sqrt(discharge(area)), 1, 28)
}

river_depth :: proc(half: f32) -> f32 {
	return 2.1*math.pow(2*half/14, 0.8)
}

// The water runs in a bed of bare stones that the floods keep clear of trees, wider than the water
// on most days: a mountain river's width follows its flood, about 2.5 times the root of the mean
// yearly highest flow on 34 Japanese mountain rivers (Sakurai, Miyawaki and Hakoishi, PWRI, 2012),
// and a small stream's floods are larger for its land than a large one's. Half the bed's width:
// 6.4 m across at 1 km², growing as the land drained to the power 0.35 (bedrock and alluvial
// channels grow as 0.3 to 0.5, Montgomery and Gran 2001; those 34 rivers as 0.28): 1.6 m where a
// stream starts, 3 m at 0.12 km², 13 m at 7 km² and 31 m at 90 km², as the beds of Yakushima's
// rivers measure on the Geospatial Information Authority's photographs (10 to 16 m at 7.6 km², 15
// to 30 at 20, 30 to 55 at 38 and 30 to 45 at 65 to 83), and as wide as the channel at least.
river_bed :: proc(area: f32) -> f32 {
	return max(0.5*min(6.4*math.pow(area/1e6, 0.35), 56), river_half(area))
}

rivers_trace :: proc() {
	g := land.grid
	n := g.n
	rivers.side = int(region.size)/BUCKET
	rivers.buckets = make([][dynamic]i32, rivers.side*rivers.side)
	point :: proc(g: ^Grid, c: i32) -> River_Point {
		p := [2]f32{f32(int(c)%g.n) + 0.5, f32(int(c)/g.n) + 0.5} + g.jitter[c]
		return {p*g.d - f32(region.size/2), g.fill[c], g.area[c]}
	}

	// A stream runs where enough land drains, unless its water sinks into a crater floor
	// before it gathers: there the ground stays dry. It ends at a lake, and a new one leaves
	// from the lake's outlet.
	stream, feeders := make([]bool, n*n), make([]u8, n*n)
	defer { delete(stream); delete(feeders) }
	for c in g.order {
		r := g.next[c]
		stream[c] = g.area[c] >= HEAD_AREA && land.lake[c] == 0 && (r == -1 || (r >= 0 && (stream[r] || land.lake[r] > 0)))
		if stream[c] && r >= 0 do feeders[r] += 1
	}
	// Springs (foundations/water.md, D6). Rain soaks down through a bed that passes water until
	// it meets one that does not, and comes out along the contact. Where the contact crosses a
	// valley side in a hollow, with enough land above to feed it, a brook starts there and runs
	// down to the stream below; on dry ground nearby the same hollow carries no water.
	springs := 0
	for c in g.order do if r := g.next[c]; r >= 0 && !stream[c] && g.area[c] >= SPRING_AREA && land.lake[c] == 0 && land.slope[c] > 0.15 && land.hump[c] < -2 {
		over, under := rock_in(g.z[c] + 3, grid_under(g, int(c)), ROCK_SIM), rock_in(g.z[c] - 2, grid_under(g, int(c)), ROCK_SIM)
		if !is(over, PASSES) || is(under, PASSES) do continue
		near := false   // one spring to a stretch of the contact: the water seeps along it to the lowest point
		for f in region.features[len(region.features) - springs:] do near ||= math.hypot(f.at.x - middle_of(g, int(c)).x, f.at.y - middle_of(g, int(c)).y) < 150
		if near do continue
		append(&region.features, Feature{kind = .Spring, at = middle_of(g, int(c)), size = discharge(g.area[c]), level = g.z[c], cause = -1,
			measured = {{"km² of land above it feeding it", g.area[c]/1e6}, {"strength of the bed it rises from", MATERIALS[under].strength}, {}}})
		springs += 1
		for k := int(c); k >= 0 && !stream[k] && land.lake[k] == 0; k = int(g.next[k]) {
			stream[k] = true
			if g.next[k] >= 0 do feeders[g.next[k]] += 1
		}
	}
	fmt.printfln("springs: %d, where a bed that passes water lies on one that holds it, in a hollow on a valley side", springs)
	points: [dynamic]River_Point
	defer delete(points)
	for c in g.order {
		if !stream[c] || feeders[c] == 1 do continue   // a reach begins at a spring or below a confluence
		clear(&points)
		at, under := c, f32(1e6)   // the outlet stream of a lake keeps its water under the lake's
		for o in OFFSETS do if k := int(c) + o.y*n + o.x; land.lake[k] > 0 && g.next[k] == c do under = region.features[land.lake[k] - 1].level + FREEBOARD - 0.2
		for {
			append(&points, point(g, at))
			r := g.next[at]
			if r >= 0 && land.lake[r] > 0 {   // into a lake, at its level
				append(&points, River_Point{point(g, r).p, min(g.fill[r], region.features[land.lake[r] - 1].level + FREEBOARD), g.area[r]})
				break
			}
			if r < 0 {
				// The mouth. The first sea cell is often only ankle deep, so carry on down
				// the sea bed to properly deep water, with the banks under the surface. The
				// channel is cut through the shallows and the sea fills it.
				cell := int(at)
				for _ in 0..<16 {
					lowest := -1
					for o in OFFSETS {
						x, y := cell%n + o.x, cell/n + o.y
						if x < 0 || y < 0 || x >= n || y >= n || !g.sea[y*n + x] do continue
						if lowest < 0 || g.z[y*n + x] < g.z[lowest] do lowest = y*n + x
					}
					if lowest < 0 || (cell != int(at) && g.z[lowest] >= g.z[cell]) do break
					cell = lowest
					append(&points, River_Point{([2]f32{f32(cell%n), f32(cell/n)} + 0.5)*g.d - f32(region.size/2), MOUTH_BANK, g.area[at]})
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
		for &q in points do q.bank = min(q.bank, under)
		if len(points) >= 2 do reach_build(points[:], u32(c))
	}
	lakes_draw()
	mouths_make()
	heights, tallest := [4]int{}, -1
	for f, i in region.features do if f.kind == .Fall {
		h := f.measured[0].value
		heights[0 if h < 5 else 1 if h < 10 else 2 if h < 30 else 3] += 1
		if tallest < 0 || h > region.features[tallest].measured[0].value do tallest = i
	}
	if tallest >= 0 {
		f := region.features[tallest]
		fmt.printfln("falls: %d of 2.5 to 5 m, %d of 5 to 10, %d of 10 to 30, %d over 30; the tallest %.0f m, at %.0f, %.0f over %v",
			heights[0], heights[1], heights[2], heights[3], f.measured[0].value, f.at.x + f64(region.origin.x), f.at.y + f64(region.origin.y), fall_rock(f))
	} else do fmt.println("falls: none")
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
		swing, _, _ := noise(f64(along[i]/(22*half)), f64(id%977), seed + 200)
		taper := clamp(min(along[i], along[last] - along[i])/(6*half), 0, 1)
		pts[i].p += [2]f32{-flow[i].y, flow[i].x}*min(2.4*half, 6)*(swing*2 - 1)*taper
	}
	directions(pts, flow)

	// Width follows the land drained, swelling and narrowing along the way. The bend is the
	// channel's curvature measured against its width, smoothed so bars and cut banks are
	// a few widths long.
	half, stones := make([]f32, len(pts), context.temp_allocator), make([]f32, len(pts), context.temp_allocator)
	bend := make([]f32, len(pts), context.temp_allocator)
	for i in 0..=last {
		swell, _, _ := noise(f64(along[i]/45), f64(id%977) + 31, seed + 201)
		half[i] = river_half(pts[i].area)*(0.8 + 0.45*swell)
		spread, _, _ := noise(f64(along[i]/90), f64(id%977) + 57, seed + 202)   // the bed widens and narrows over a few of its widths
		stones[i] = max(river_bed(pts[i].area)*(0.85 + 0.4*spread), half[i])
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
	// Steeper than FALL_STEEP it cannot hold pools, and runs down the land as a cascade.
	// A pool sits at or below the land's own level, never above it, and both ends of the
	// reach keep the land's level so that reaches meet.
	from := make([]f32, last, context.temp_allocator)
	to := make([]f32, last, context.temp_allocator)
	slope := make([]f32, last, context.temp_allocator)
	level := pts[0].bank
	for i in 0..<last {
		up, down := max(i - 3, 0), min(i + 4, last)
		fall := (pts[up].bank - pts[down].bank)/max(along[down] - along[up], 1)
		slope[i] = fall
		if fall > 0.045 && fall <= FALL_STEEP && min(along[i], along[last] - along[i + 1]) > 12 {
			pool := max(math.floor(pts[i + 1].bank - 0.55) + 0.55, pts[last].bank)   // so the water stands a little over a block top
			from[i] = min(pool, level)
			to[i] = from[i]
		} else {
			from[i] = min(pts[i].bank, level)
			to[i] = min(pts[i + 1].bank, from[i])
		}
		level = to[i]
	}
	gorge := make([]bool, last, context.temp_allocator)
	falls_make(pts[:], along, slope, half, from, to, flow, gorge)

	// The water surface: a pair of points across the channel at each end of each stretch.
	// Where the level drops between stretches the two pairs stand one above the other and
	// the strip between them is a sheet of falling water. Where the river comes down to
	// the sea its surface ends, at the line where the two meet: from there on the channel
	// lies under the sea, which fills it.
	MEETS :: SEA_SURFACE + 0.01
	// The water is drawn wider than the channel, and wider still over a bar, so that it
	// always reaches into its banks and nothing below its level is left uncovered. `wide`
	// is the reach to the right and to the left of the flow.
	across :: proc(p, flow: [2]f32, wide: [2]f32, water: f32) -> (r, l: [4]f32) {
		left := [2]f32{-flow.y, flow.x}
		return {p.x - left.x*wide[0], water, p.y - left.y*wide[0], -1}, {p.x + left.x*wide[1], water, p.y + left.y*wide[1], 1}
	}
	wide := make([][2]f32, len(pts), context.temp_allocator)
	for i in 0..=last do wide[i] = half[i]*(1.3 + 0.45*[2]f32{max(-bend[i], 0), max(bend[i], 0)}) + 0.3   // the bar is on the side the channel turns toward
	if len(rivers.ribbon) > 0 {   // join to the strip so far with a zero-area bridge
		l, _ := across(pts[0].p, flow[0], wide[0], max(from[0] - FREEBOARD, MEETS))
		append(&rivers.ribbon, rivers.ribbon[len(rivers.ribbon) - 1], l)
	}
	at_sea := false
	for i in 0..=last {
		if i > 0 && !at_sea {
			before, water := from[i - 1] - FREEBOARD, to[i - 1] - FREEBOARD
			if water > MEETS {
				append(&rivers.ribbon, across(pts[i].p, flow[i], wide[i], water))
			} else {
				t := clamp((before - MEETS)/max(before - water, 0.001), 0, 1)
				append(&rivers.ribbon, across(math.lerp(pts[i - 1].p, pts[i].p, t), flow[i], math.lerp(wide[i - 1], wide[i], t), MEETS))
				at_sea = true
			}
		}
		if i < last && !at_sea && (i == 0 || from[i] < to[i - 1] - 0.01) {
			water := from[i] - FREEBOARD
			if i > 0 && to[i - 1] - from[i] > FALL_MIN {   // a fall: the strip breaks, and the fall draws the water between
				l, _ := across(pts[i].p, flow[i], wide[i], max(water, MEETS))
				append(&rivers.ribbon, rivers.ribbon[len(rivers.ribbon) - 1], l)
			}
			append(&rivers.ribbon, across(pts[i].p, flow[i], wide[i], max(water, MEETS)))
			at_sea = water <= MEETS
		}
		if i == last do break

		a, b := pts[i], pts[i + 1]
		if i%8 == 4 && slope[i] <= FALL_STEEP && !gorge[i] {   // a bank to start on, but not by a fall or a cascade
			bank := a.p + [2]f32{-flow[i].y, flow[i].x}*(half[i]*1.3 + 5)
			append(&rivers.spots, Spot{{bank.x, from[i], bank.y}, math.atan2(flow[i].x, -flow[i].y), a.area})
		}
		index := i32(len(rivers.segments))
		drop := to[i] - from[i + 1] if i + 1 < last else 0
		pool := to[i - 1] - from[i] if i > 0 else 0
		pool = plunge(pool, a.area, half[i]) - river_depth(half[i]) if pool > FALL_MIN else 0
		append(&rivers.segments, Segment{a.p, b.p, from[i], to[i], half[i] + 0.5*pool, half[i + 1], max(stones[i], half[i] + 0.5*pool), stones[i + 1], bend[i], bend[i + 1], drop, max(pool, 0), gorge[i]})
		lo := linalg.min(a.p, b.p) - RIVER_REACH + f32(region.size/2)
		hi := linalg.max(a.p, b.p) + RIVER_REACH + f32(region.size/2)
		for bz in max(int(lo.y)/BUCKET, 0)..=min(int(hi.y)/BUCKET, rivers.side - 1) {
			for bx in max(int(lo.x)/BUCKET, 0)..=min(int(hi.x)/BUCKET, rivers.side - 1) {
				append(&rivers.buckets[bz*rivers.side + bx], index)
			}
		}
	}
	free_all(context.temp_allocator)
}

// How deep a fall scours the pool under it, metres of water: Veronese's rule for the scour under
// a falling jet, 1.9 H^0.225 q^0.54, with q the flow of a flood over each metre of the lip.
plunge :: proc(height, area, half: f32) -> f32 {
	return 1.9*math.pow(height, 0.225)*math.pow(FLOOD*discharge(area)/(2*half), 0.54)
}

// The rock a fall's lip is made of.
fall_rock :: proc(f: Feature) -> Mat {
	return rock_in(f.level - 0.6, rock_base(f.at.x, f.at.y, 1), 0)
}

// Falls (foundations/water.md, section 5). A stream steeper than FALL_STEEP cannot hold a bed of
// pools. Where it runs so across a strong bed, that bed holds a lip on its top, and the weaker rock
// under it is worn back by the water falling on it; so the stream falls in one drop from the strong
// bed's top to the next strong bed's top or the foot of the steep ground, and below the fall runs at
// that level in the gorge the fall cut as it wore back. Every drop taller than FALL_MIN, these and
// the steps of a steep stream alike, is then a feature with water of its own: a sheet that leaves
// the lip at the speed the water crosses it, falls freely to the pool, and churns it white.
falls_make :: proc(pts: []River_Point, along, slope, half, from, to: []f32, flow: [][2]f32, gorge: []bool) {
	last := len(pts) - 1
	bed :: proc(q: River_Point, level: f32) -> (strong: bool, n: u16) {
		y := level - 1
		n = rocks.bed[clamp(int(y - stack_base(y, rock_base(f64(q.p.x), f64(q.p.y), 1)) - STACK_LO), 0, STACK_LEN - 1)]
		return MATERIALS[rocks.beds[n].kind].strength >= 0.5, n
	}
	for k := 1; k < last - 1; {
		if slope[k] <= FALL_STEEP {
			k += 1
			continue
		}
		end := k
		for end < last - 1 && slope[end] > FALL_STEEP do end += 1
		lips := make([dynamic]int, context.temp_allocator)   // the first stretch of the run in each strong bed
		for m in k..<end {
			strong, n := bed(pts[m], from[m])
			_, above := bed(pts[m - 1], from[m - 1])
			if strong && (m == k || n != above) do append(&lips, m)
		}
		for m, j in lips {
			if pts[m].area < FALL_AREA do continue
			next := lips[j + 1] if j + 1 < len(lips) else end
			cliff := from[next] < 0.5 && land.grid.face[land_cell(f64(pts[m].p.x), f64(pts[m].p.y))] > 1.3   // it falls from the lowest strong bed over a cliff the waves undercut
			_, n := bed(pts[m], from[m])
			if _, below := bed(pts[next], from[next]); below == n && !cliff do continue   // it runs down the bed, as on a lava flow's back, and never falls past it
			// It wears back only the weak rock under its own bed, so it falls no further than the top
			// of the next strong bed beneath its lip; below that the stream steps down as before.
			under := int(n) - 1
			for under > 0 && MATERIALS[rocks.beds[under].kind].strength < 0.5 do under -= 1
			if floor := rocks.floor[under + 1] + bed_base(under + 1, rock_base(f64(pts[m].p.x), f64(pts[m].p.y), 1)) + STACK_LO; !cliff {
				for s in m + 1..<next do if from[s] <= floor {
					next = s
					break
				}
			}
			for s in m + 1..<next {
				from[s], to[s] = from[next], from[next]
				gorge[s] = pts[s].bank - from[next] > 6*half[s]   // walls several channel widths high
			}
		}
		k = end
	}
	for i in 0..<last - 1 {
		h := to[i] - from[i + 1]
		if h <= FALL_MIN do continue
		top, foot := to[i] - FREEBOARD, max(from[i + 1] - FREEBOARD, SEA_SURFACE)
		gorge := i + 1
		for gorge < last && pts[gorge].bank > from[i + 1] + 2 do gorge += 1
		q := discharge(pts[i].area)
		append(&region.features, Feature{kind = .Fall, at = {f64(pts[i + 1].p.x), f64(pts[i + 1].p.y)}, reach = along[gorge] - along[i + 1], size = q, level = top, cause = -1,
			measured = {{"its height, metres", h}, {"km² draining over it", pts[i].area/1e6}, {"metres of water in the pool it scoured", plunge(h, pts[i].area, half[i + 1])}}})
		v := max(math.cbrt(9.8*q/(2*half[i])), 0.4)
		fall := math.sqrt(2*(top - foot)/9.8)
		dir := flow[i + 1]
		side := [2]f32{-dir.y, dir.x}
		start := pts[i + 1].p + dir*0.6
		ROWS :: 14
		more := [4]f32{dir.x*v, dir.y*v, 1, -4}   // flow, depth, and -4 for a falling sheet (-2 to -3 for the white water under it): below zero, as the simulated water's own values are not (vs_pool)
		append(&rivers.drops, Drop{start, dir, top, foot, half[i], v})
		// The sheet is as wide as the stream that feeds it and begins on that stream, a stride back
		// from the lip, so the two are one water; then it falls freely.
		wide := max(half[i], 0.5) + 0.15
		back := start - dir*1.6
		before := [2][3]f32{{back.x - side.x*wide, top + 0.05, back.y - side.y*wide}, {back.x + side.x*wide, top + 0.05, back.y + side.y*wide}}
		for r in 0..=ROWS {
			t := fall*f32(r)/ROWS
			c, y := start + dir*v*t, top + 0.05 - 4.9*t*t
			w := wide + min(0.04*(top - y), half[i] + 0.5)   // it spreads as it falls
			row := [2][3]f32{{c.x - side.x*w, y, c.y - side.y*w}, {c.x + side.x*w, y, c.y + side.y*w}}
			append(&rivers.falls, Water_Quad{{before[0], before[1], row[0], row[1]}, more})
			before = row
		}
		// White water where it lands, fading out over a few metres.
		at, spread := start + dir*v*fall, 1.2*half[i] + 0.6 + 0.08*h
		for q in 0..<4 {
			corner :: proc(at, dir, side: [2]f32, spread, y: f32, u, v: int) -> [3]f32 {
				p := at + (dir*f32(u - 1) + side*f32(v - 1))*spread
				return {p.x, y, p.y}
			}
			u, v := q & 1, q >> 1
			quad: Water_Quad
			for k in 0..<4 {
				cu, cv := u + (k & 1), v + (k >> 1)
				quad.p[k] = corner(at, dir, side, spread, foot + 0.06, cu, cv)
				quad.more[k] = {dir.x, dir.y, 1, -3 if cu == 1 && cv == 1 else -2}
			}
			append(&rivers.falls, quad)
		}
	}
}

River_Near :: struct {
	d:      f32,   // distance from the centre line
	half:   f32,   // half the channel width there
	bank:   f32,   // bank level there
	inside: f32,   // 1 on the inside of a sharp bend, -1 on the outside, 0 on a straight
	lip:    bool,  // just above a drop
	fall:   bool,  // and the drop is a fall, whose lip is rock
	pool:   f32,   // how much deeper a fall has scoured the bed here
	gorge:  bool,  // in a fall's gorge
	bed:    f32,   // half the width of the bed of stones round the channel
}

// The nearest river to a point, judged from the water's edge, if one is within reach.
river_near :: proc(x, z: f32) -> (r: River_Near, ok: bool) {
	rim := f32(region.size/2)
	bx, bz := int(x + rim)/BUCKET, int(z + rim)/BUCKET
	if x < -rim || z < -rim || bx >= rivers.side || bz >= rivers.side do return
	p := [2]f32{x, z}
	nearest: f32 = RIVER_REACH
	for id in rivers.buckets[bz*rivers.side + bx] {
		s := rivers.segments[id]
		ab, ap := s.b - s.a, p - s.a
		t := clamp(linalg.dot(ap, ab)/linalg.dot(ab, ab), 0, 1)
		d := linalg.length(ap - ab*t)
		half := math.lerp(s.half_a, s.half_b, t)
		if d - half < nearest {
			nearest = d - half
			side: f32 = 1 if ab.x*ap.y - ab.y*ap.x > 0 else -1   // left or right of the flow
			lip := s.drop > 0.01 && (1 - t)*linalg.length(ab) < 1.6
			pool := s.pool*smoothstep(s.half_a*1.5, 0, t*linalg.length(ab))
			r, ok = {d, half, math.lerp(s.bank_a, s.bank_b, t), side*math.lerp(s.bend_a, s.bend_b, t), lip, lip && s.drop > FALL_MIN, pool, s.gorge, math.lerp(s.bed_a, s.bed_b, t)}, true
		}
	}
	return
}

// Cut a river into the ground at a point: a bed, banks rising to the bank top, the bed of stones
// at the bank top's level that the floods keep bare, then a strip of valley floor that eases back
// into the hillside. On the outside of a bend the bank is
// steep; on the inside the bed ramps up into a bar. Just above a drop the bed rises to a
// lip that holds the pool back. `gravel` is true where the ground is river bed or bar,
// and `water` is the river's level within the channel. At a coarse cell size the cut is
// widened by the cell, so a far-off column that a stream crosses is always lowered
// beneath the water drawn over it; past COARSE a stream is under a pixel wide and cuts nothing.
river_cut :: proc(h: f32, x, z, cell: f64) -> (cut: f32, gravel: bool, water: f32) {
	r, ok := river_near(f32(x), f32(z))
	if !ok || cell > COARSE do return h, false, NO_WATER
	d := r.d
	if cell > 1 {
		d = max(d - 0.71*f32(cell), 0)
	} else {
		d = max(d + 0.22*r.half*fbm(x, z, 9, 1, 2, seed + 210), 0)   // a ragged water's edge
	}
	bar, undercut := max(r.inside, 0), max(-r.inside, 0)
	edge := r.half*(1.2 + 0.6*bar)   // where the bank top is reached
	stones := edge if r.gorge else max(r.bed*(1 + 0.3*bar), edge)   // the bed of stones, at the bank top's level, out to here; a gorge's walls rise from the water
	top := stones + (0.3 if r.gorge else 1.5)   // the bank top is level this far, which keeps the water's edge in its banks
	floor := top + (max(1.5, 0.3*(h - r.bank)) if r.gorge else r.half*2 + 5)   // and a gorge's walls rise from it, leaning back a little
	if d >= floor do return h, false, NO_WATER
	level := r.bank - FREEBOARD
	bed := level - (0.15 if r.lip else river_depth(r.half) + r.pool)
	// The bank top is a whole block that stands at least 30 cm clear of the water. Ground
	// is cut into whole blocks, and a bank that rounded down would let the river out.
	crest := math.ceil(level + 0.3)
	if d < edge {
		steep := bed + (crest - bed)*smoothstep(r.half*(0.55 + 0.3*undercut), r.half*1.2, d)
		ramp := bed + (crest - bed)*d/edge
		cut = math.lerp(steep, ramp, bar)
		return cut, !r.fall && (bar > 0.35 || math.round(cut) < level - 0.05), level   // gravel on a bar, or where the block's top is under water; a fall's lip is rock
	}
	if d < stones do return crest, true, NO_WATER
	return math.lerp(crest, h, smoothstep(top, floor, d)), false, NO_WATER
}

// Spray: drops thrown up where a fall lands and shed down its length, as small white boxes posed
// each frame from the fall, the drop's number and the clock, as the creatures are (creatures.odin).
// `e` is the eye from the region's middle.
SPRAY_FAR :: 220
spray :: proc(out: ^[dynamic]Box, e: [3]f64, clock: f64) {
	WHITE :: f32(0xe4ecf2)
	for d, n in rivers.drops {
		if math.hypot(f64(d.lip.x) - e.x, f64(d.lip.y) - e.z) > SPRAY_FAR do continue
		h := d.top - d.foot
		fall := math.sqrt(2*h/9.8)
		land, side := d.lip + d.dir*d.speed*fall, [2]f32{-d.dir.y, d.dir.x}
		for k in 0..<int(clamp(8 + h/2 + 8*d.half, 10, 60)) {
			r: [6]f32
			for &v, j in r do v = hash01(i32(n), i32(k), seed + 900 + u32(j))
			p: [2]f32
			y, size: f32
			if k%3 == 0 {   // shed from the sheet's edge on the way down
				t := fall*f32(math.mod(clock/f64(fall) + f64(r[1]), 1))
				p = d.lip + d.dir*(d.speed*t + 0.3*r[0]) + side*(d.half + 0.3 + 0.4*r[3])*(1 if r[4] < 0.5 else -1)
				y, size = d.top - 4.9*t*t, 0.05
			} else {   // thrown up from where it lands, farther by a taller fall
				life := 0.5 + 0.7*r[0]
				t := life*f32(math.mod(clock/f64(life) + f64(r[1]), 1))
				bearing := math.TAU*r[4]
				p = land + side*(2*r[5] - 1)*(d.half + 0.3) + ([2]f32{math.cos(bearing), math.sin(bearing)}*(0.4 + 1.4*r[3]) + 0.8*d.dir)*t
				y, size = d.foot + (1.5 + 3*r[2])*min(math.sqrt(h/12), 1.3)*t - 4.9*t*t, (0.04 + 0.05*r[2])*(1 - 0.5*t/life)
				if y < d.foot do continue
			}
			append(out, Box{{f32(f64(p.x) - e.x), f32(f64(y) - e.y), f32(f64(p.y) - e.z)}, WHITE, {size, 0, 0}, WHITE, {0, size, 0}, 0, {0, 0, size}, 0})
		}
	}
}

// River mouths (foundations/water.md, section 4: mouths by kind). What a stream brings to the sea is
// as coarse as its bed is steep where it ends. Japan's rivers lay blocks of every size where they fall
// more than 1 in 60, gravel down to 1 in 400, sand down to 1 in 5,000 and silt below that (Yamamoto's
// segments, 1994, as the Ministry of Land, Infrastructure, Transport and Tourism gives them); on
// Yakushima's south coast short steep streams roll blocks of granite to the very mouth and the beach
// beside it, while longer ones leave theirs on the way down (Shimazu, JpGU 2022 and 2023). Each mouth
// is a feature, measured by its last MOUTH_RUN metres down to the sea, and the ground round it is its
// fan, out to a reach that grows with the root of the land it drains: what the stream lays there is
// read by the rows of SURFACES (the fields fan and grade).
BLOCKS_GRADE :: 1.0/60
SAND_GRADE   :: 1.0/400
MOUTH_RUN    :: 300
FAN          :: [2]f32{30, 200}   // metres a fan reaches, and more for each root of a km² drained (a guess)

mouths_make :: proc() {
	g := land.grid
	n := g.n
	// Down each stream: the mouth it reaches, how far off, and the farthest point of its main stem (the
	// cells draining at least half what its mouth does) within MOUTH_RUN of it.
	mouth, run := make([]i32, n*n, context.temp_allocator), make([]f32, n*n, context.temp_allocator)
	far, top := make([]f32, n*n, context.temp_allocator), make([]f32, n*n, context.temp_allocator)
	for ci in g.order {
		c, r := int(ci), int(g.next[ci])
		mouth[c] = i32(c) if r == -1 else mouth[r] if r >= 0 else -1
		if mouth[c] < 0 do continue
		if r >= 0 do run[c] = run[r] + span(g, c, r)
		m := int(mouth[c])
		if run[c] <= MOUTH_RUN && g.area[c] >= g.area[m]/2 && run[c] >= far[m] do far[m], top[m] = run[c], g.z[c]
	}
	delete(land.mouth)
	land.mouth = make([]u16, n*n)
	near := make([]f32, n*n, context.temp_allocator)
	kinds, largest: [3]int   // how many of each grade of load, and the largest of each
	largest = -1
	for ci in g.order do if g.next[ci] == -1 && g.area[ci] >= HEAD_AREA && land.lake[ci] == 0 {
		c := int(ci)
		grade := max(top[c], 0)/(far[c] + g.d/2)   // the fall to the sea, from the middle of its last cell
		reach := FAN[0] + FAN[1]*math.sqrt(g.area[c]/1e6)
		at := middle_of(g, c)
		append(&region.features, Feature{kind = .Mouth, at = at, reach = reach, size = discharge(g.area[c]), cause = -1,
			measured = {{"km² draining to it", g.area[c]/1e6}, {"its fall in a metre over its last 300 m", grade}, {"how open its shore is to the swell", land.swell[c]}}})
		k := 0 if grade > BLOCKS_GRADE else 1 if grade > SAND_GRADE else 2
		kinds[k] += 1
		if largest[k] < 0 || g.area[c] > region.features[largest[k]].measured[0].value*1e6 do largest[k] = len(region.features) - 1
		r := int(reach/g.d) + 1
		for y in max(c/n - r, 0)..=min(c/n + r, n - 1) do for x in max(c%n - r, 0)..=min(c%n + r, n - 1) {
			k := y*n + x
			if d := 1 - f32(math.hypot(middle_of(g, k).x - at.x, middle_of(g, k).y - at.y))/reach; d > near[k] do near[k], land.mouth[k] = d, u16(len(region.features))
		}
	}
	fmt.printf("mouths: %d streams reach the sea; %d falling more than 1 in 60 over their last 300 m bring blocks, %d gravel, %d sand and silt", kinds[0] + kinds[1] + kinds[2], kinds[0], kinds[1], kinds[2])
	LOADS := [3]string{"bringing blocks", "bringing gravel", "bringing sand"}
	for f, k in largest do if f >= 0 {
		m := region.features[f]
		fmt.printf("; the largest %s at %.0f, %.0f, draining %.2f km²", LOADS[k], m.at.x + f64(region.origin.x), m.at.y + f64(region.origin.y), m.measured[0].value)
	}
	fmt.println()
}

// The rock a stream's blocks and gravel are of: the rock upstream, where that was read, or else the
// strongest bed in the 40 m it cuts down through at its mouth, since a weak one breaks to sand.
mouth_rock :: proc(f: Feature) -> (m: Mat) {
	c := land_cell(f.at.x, f.at.y)
	if len(land.pebble) > 0 && land.pebble[c] != .Air do return land.pebble[c]
	for d := f32(0.5); d < 40; d += 4 {
		if k := rock_in(land.grid.z[c] - d, grid_under(land.grid, c), ROCK_SIM); d == 0.5 || MATERIALS[k].strength > MATERIALS[m].strength do m = k
	}
	return
}

// The stream mouth whose fan a point lies on, if any, and how near its mouth: 1 there, 0 at the fan's edge.
fan_at :: proc(x, z: f64) -> (f: ^Feature, near: f32) {
	k := land.mouth[land_cell(x, z)]
	if k == 0 do return nil, 0
	f = &region.features[k - 1]
	return f, max(1 - f32(math.hypot(x - f.at.x, z - f.at.y))/f.reach, 0)
}
