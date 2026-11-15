package main

import "core:math"

// Trees: species, stands with ages and storm gaps, which trees stand in a rectangle (trees_in), and
// the grower that turns one into blocks (grow). See docs/foundations/vegetation.md and
// docs/interesting-world/notes/real-vegetation.md.

Tree :: struct {
	x, z:   i32,   // block the trunk stands on
	base:   i32,   // elevation of the ground there
	height: i32,   // to the crown's top, over the base; of a fallen trunk, its length
	radius: i32,   // of the crown
	kind:   Tree_Kind,
	form:   Tree_Form,
	fall:   [2]f32,   // a fallen trunk: the way it lies from its stump
	open:   [2]f32,   // how far the crown's middle stands off the trunk, toward the light and downwind, metres
	wind:   [2]f32,   // downwind, times how open the tree's place is to the wind
}
// Its place in the stand. Only canopy trees and the trees between them are drawn far off; small
// trees under the canopy, standing dead trunks and fallen ones are drawn only near by.
Tree_Form :: enum u8 { Canopy, Between, Under, Dead, Fallen }

TREE_GRID   :: 3     // at most one tree stands in a square of this many metres
TREE_REACH  :: 6     // the farthest a crown reaches from its trunk
CROWNS_MEET :: 0.75 // a crown's radius is at most this share of the spacing, so neighbours' crowns interlock
FALLEN     :: 8    // the longest fallen trunk, and its stump

// How storms age the woods (foundations/vegetation.md, D3 and D6). The land's grid is cut into
// stands round middles `across` metres apart, the reach of each drawn from the seed, and each has
// the years since a typhoon last threw its canopy, drawn from the seed with the storms coming more
// often to ground open to the wind: young stands gather on windward slopes and crests, old ones in
// sheltered valleys. Ground a slide laid bare is as old as the slide. A young stand is many thin
// trees close together; as it ages the trees grow and the fastest shade out their neighbours, until
// the canopy trees stand `spacing[1]` apart with smaller trees between and beneath them, and gaps
// open where one or a group was thrown, with the trunks lying the way the wind blew.
// The figures are from interesting-world/notes/real-vegetation.md, "Stands".
Stand_Rule :: struct {
	across:   f64,      // metres between the middles of neighbouring stands
	interval: [2]f32,   // mean years between storms that throw a stand's canopy, on sheltered ground and on ground fully exposed
	spacing:  [2]f32,   // metres between canopy trees in a stand just thrown and in an old one
	grows:    f32,      // years for a stand's trees to grow most of the way to their full height
	thins:    f32,      // years for its canopy to thin most of the way to the old spacing
	gaps:     f32,      // share of an old stand's ground in gaps, each where a tree or a group fell
	gap:      [2]f32,   // radius of a gap, metres
	refill:   f32,      // years a gap stays open before its young growth closes it
	between:  f32,      // share of the places between the canopy trees where a smaller tree stands
	snags:    f32,      // share of an old stand's canopy trees standing dead, as broken stubs
	young:    f32,      // share of the places in a gap where young growth has come up
	fallen:   f32,      // share of the canopy trees thrown in a gap whose trunk still lies, and as many again stand as stubs; the rest have rotted away
}
STANDS := Stand_Rule{across = 140, interval = {2000, 40}, spacing = {3.5, 7.5}, grows = 40, thins = 150, gaps = 0.2, gap = {4, 11}, refill = 50, between = 0.25, snags = 0.015, young = 0.2, fallen = 0.1}

// The land's cell a tree or a far cell reads its stand and community from: its own, with the
// edges dithered over 24 m by the hash `r`, so that two stands or communities mix along their edge.
dithered :: proc(x, z: f64, r: u32) -> int {
	return land_cell(x + f64(r & 0xFF)/10.6 - 12, z + f64((r >> 8) & 0xFF)/10.6 - 12)
}

// Which stand a point of the land's grid lies in, and its age: the stand whose middle is nearest
// for its reach, read a little way off by noise so the edges wander. A slide's ground is as old as
// the slide.
stand_draw :: proc(x, z: f64, c: int) -> f32 {
	x, z := x + 30*f64(fbm(x, z, 80, LAND_CELL, 2, seed + 622)), z + 30*f64(fbm(x, z, 80, LAND_CELL, 2, seed + 623))
	D := STANDS.across
	best, age := f64(1e9), f32(0)
	for j in i32(math.floor(z/D)) - 2..=i32(math.floor(z/D)) + 2 do for i in i32(math.floor(x/D)) - 2..=i32(math.floor(x/D)) + 2 {
		r := hash(i, j, seed + 620)
		mx, mz := (f64(i) + f64(r & 0xFF)/256)*D, (f64(j) + f64((r >> 8) & 0xFF)/256)*D
		if d := math.hypot(x - mx, z - mz)/(0.4 + 1.2*f64(r >> 24)/255); d < best {
			mc := land_cell(mx, mz)
			wind := land.exposed[mc if !land.grid.sea[mc] else c]
			best, age = d, -math.lerp(STANDS.interval[0], STANDS.interval[1], wind)*math.ln(max(hash01(i, j, seed + 621), 1e-4))
		}
	}
	if abs(land.slid[c]) > 0.5 do age = min(age, region.features[landslide.feature].age)
	return age
}

// What a stand of an age grows: metres between its canopy trees, the share of their full height
// they have reached, and how far it is from new to old, 0 to 1.
stand :: proc(age: f32) -> (spacing, tall, old: f32) {
	old = 1 - math.exp(-age/STANDS.thins)
	return math.lerp(STANDS.spacing[0], STANDS.spacing[1], old), 0.35 + 0.65*(1 - math.exp(-age/STANDS.grows)), old
}

// The gap a point lies in, if any: one may open in each 24 m square, the likelier the older the
// stand, so that gaps take `gaps` of an old stand's ground and a young one has none. It is where
// a canopy tree or a group fell the way the storm blew, `ago` years since.
GAP_TILE :: 24
gap_at :: proc(x, z: f64, old: f32) -> (inside: bool, fall: [2]f32, ago: f32) {
	a, b := STANDS.gap[0], STANDS.gap[1]
	chance := old*old*STANDS.gaps*GAP_TILE*GAP_TILE/(math.PI*(a*a + a*b + b*b)/3)
	gx, gz := i32(math.floor(x/GAP_TILE)), i32(math.floor(z/GAP_TILE))
	for j in gz - 1..=gz + 1 do for i in gx - 1..=gx + 1 {
		r := hash(i, j, seed + 630)
		if f32(r & 0xFF)/256 >= chance do continue
		mx, mz := (f64(i) + f64((r >> 8) & 0xFF)/256)*GAP_TILE, (f64(j) + f64((r >> 16) & 0xFF)/256)*GAP_TILE
		if math.hypot(x - mx, z - mz) < f64(math.lerp(a, b, f32(r >> 24)/255)) {
			bearing := math.to_radians(f32(region.shape.swell)) + 1.2*(hash01(i, j, seed + 631) - 0.5)   // downwind, give or take 35°
			return true, {-math.sin(bearing), math.cos(bearing)}, STANDS.refill*hash01(i, j, seed + 632)
		}
	}
	return
}

// The share of a community's ground its crowns cover at a canopy spacing, which is how much of the
// far canopy is leaf.
cover :: proc(k: Community_Kind, spacing: f32) -> f32 {
	r := min(crowns[k], CROWNS_MEET*spacing) + 0.5
	return min(COMMUNITIES[k].density*math.PI*r*r/(spacing*spacing)*(1 + 0.5*STANDS.between), 1)
}

// The share of the community's trees each species has, picked by a number in 0..1.
pick_species :: proc(k: Community_Kind, u: f32) -> Tree_Kind {
	u := u
	for share, s in COMMUNITIES[k].trees {
		u -= share
		if u < 0 do return Tree_Kind(s)
	}
	return .Shii
}

// Every tree whose trunk stands in a rectangle of blocks, and `near`, the small, dead and fallen as
// well, with the fallen whose trunks reach into it. The same tree is found whichever chunk or level
// of detail asks. Each 3 m square holds a candidate with a vigour; of the candidates whose crowns
// would meet at the stand's spacing, the most vigorous takes the canopy (after Deussen et al.
// 1998). One shaded only from beyond half that reach may stand between the canopy trees, smaller;
// one shaded from nearer is beneath them, a small tree or a bush if anything. In a gap the canopy
// trees lie fallen or stand dead and the rest is young growth.
trees_in :: proc(x0, z0, x1, z1: i32, out: ^[dynamic]Tree, near := false) {
	floor_div :: proc(a, b: i32) -> i32 { return (a - a %% b)/b }
	m := i32(FALLEN) if near else 0
	for gz in floor_div(z0 - m, TREE_GRID)..=floor_div(z1 + m, TREE_GRID) {
		for gx in floor_div(x0 - m, TREE_GRID)..=floor_div(x1 + m, TREE_GRID) {
			r := hash(gx, gz, seed + 140)
			x, z := gx*TREE_GRID + i32(r % TREE_GRID), gz*TREE_GRID + i32((r >> 4) % TREE_GRID)
			inside := x >= x0 && x <= x1 && z >= z0 && z <= z1
			if !inside && (x < x0 - m || x > x1 + m || z < z0 - m || z > z1 + m) || trail_near(f64(x) + 0.5, f64(z) + 0.5) < 2.5 do continue   // nothing grows within a stride of a trail
			fx, fz := f64(x) + 0.5, f64(z) + 0.5
			cell := dithered(fx, fz, r >> 8)
			if land.community[cell] == 255 do continue
			spacing, tall, old := stand(land.age[cell])
			gap, fall, ago := gap_at(fx, fz, old)
			if !inside && !gap do continue   // from beyond the rectangle only a fallen trunk reaches into it
			reach, v, shade := 0.56*spacing, hash01(gx, gz, seed + 141), f32(0)   // canopy trees `spacing` apart on average
			k := i32(math.ceil(reach/TREE_GRID))
			for j in gz - k..=gz + k do for i in gx - k..=gx + k do if hash01(i, j, seed + 141) > v {
				q := hash(i, j, seed + 140)
				dx, dz := f32(i*TREE_GRID + i32(q % TREE_GRID) - x), f32(j*TREE_GRID + i32((q >> 4) % TREE_GRID) - z)
				shade = max(shade, 1 - math.sqrt(dx*dx + dz*dz)/reach)
			}
			u := hash(gx, gz, seed + 142)
			form: Tree_Form
			switch {
			case shade == 0 && gap: form = .Fallen if f32(u%1000)/1000 < STANDS.fallen else .Dead if f32(u%1000)/1000 < 2*STANDS.fallen else .Under
			case shade == 0:        form = .Dead if f32(u%1000)/1000 < old*STANDS.snags else .Canopy
			case gap:               form = .Under
			case shade < 0.5:       form = .Between if f32(u%1000)/1000 < STANDS.between else .Under
			case:                   form = .Under
			}
			if !near && form > .Between || !inside && form != .Fallen do continue
			com := Community_Kind(land.community[cell])
			c := COMMUNITIES[com]
			if f32((u >> 10) & 0xFF)/255 >= (c.density if form != .Under else STANDS.young if gap else c.bushes) do continue
			p := point_at(fx, fz, 1)
			soil, g := surface_row(&p) == len(SURFACES) - 1, p.g
			t := Tree{x = x, z = z, base = i32(math.round(g.h)), form = form}
			// A young lake still has the trunks of the trees it drowned standing in it.
			if level, under, _ := lake_near(fx, fz); under && g.h < level && form <= .Between && region.features[landslide.feature].age < DROWNED {
				if (u >> 24)&1 == 0 do continue   // half have fallen
				t.height, t.kind, t.form = 5 + i32((u >> 16)%6), .Shii, .Dead
				append(out, t)
				continue
			}
			if !soil do continue
			t.kind = pick_species(com, hash01(gx, gz, seed + 143))
			if form == .Under && !gap && (u >> 18)&1 == 0 do t.kind = .Scrub   // a bush, or a sapling of the canopy's own trees
			sp, w := SPECIES[t.kind], hash(gx, gz, seed + 144)
			full := f32(sp.height[0] + i32(w % u32(sp.height[1] - sp.height[0] + 1)))*tall
			t.radius = clamp(i32(CROWNS_MEET*spacing + 0.5), 1, sp.radius[0] + i32((w >> 8) % u32(sp.radius[1] - sp.radius[0] + 1)))
			switch form {
			case .Canopy:  t.height = max(i32(full), 3)
			case .Between: t.height, t.radius = max(i32(0.65*full), 3), clamp(t.radius - 1, 1, 2)
			case .Under:   t.height, t.radius = clamp(i32(4 + ago/6) if gap else (1 + i32((w >> 16)%2) if t.kind == .Scrub else 4 + i32((w >> 16)%3)), 1, max(i32(full), 2)), 1   // a bush a walker sees over, or a sapling whose leaves begin over his head
			case .Dead:    t.height = clamp(i32(0.3*full), 2, 6)   // broken off by the storm that killed it
			case .Fallen:
				// In blocks a trunk lies along the grid, or it is a row of steps: a stump, a stride of
				// clear ground, and the trunk for as far as the ground stays level under it.
				t.fall = {math.round(fall.x), 0} if abs(fall.x) > abs(fall.y) else {0, math.round(fall.y)}
				for t.height < 4 + i32((w >> 16)%4) && i32(math.round(ground(fx + f64(t.fall.x)*f64(t.height + 2), fz + f64(t.fall.y)*f64(t.height + 2), 1).h)) == t.base do t.height += 1
				if t.height < 3 do t.height = 0
			}
			// Which way the crown reaches: away from stronger neighbours out to twice the reach of a
			// crown, toward a gap beside it, down the slope, where the light comes from, and downwind
			// as far as the place is open to the wind.
			if form <= .Between {
				push: [2]f32
				for j in gz - 2*k..=gz + 2*k do for i in gx - 2*k..=gx + 2*k do if hash01(i, j, seed + 141) > v {
					q := hash(i, j, seed + 140)
					d := [2]f32{f32(i*TREE_GRID + i32(q % TREE_GRID) - x), f32(j*TREE_GRID + i32((q >> 4) % TREE_GRID) - z)}
					if l := math.sqrt(d.x*d.x + d.y*d.y); l < 2*reach do push -= d/l*(1 - l/(2*reach))
				}
				for a in 0..<4 {
					d := [2]f32{f32(1 - a%2*2)*f32(a/2), f32(1 - a%2*2)*f32(1 - a/2)}
					if in_gap, _, _ := gap_at(fx + f64(d.x)*8, fz + f64(d.y)*8, old); in_gap do push += 1.5*d
				}
				bearing := math.to_radians(land.facing[cell])
				push += 0.8*min(land.slope[cell], 1)*[2]f32{math.sin(bearing), -math.cos(bearing)}
				if l := math.sqrt(push.x*push.x + push.y*push.y); l > 1 do push /= l
				swell := math.to_radians(f32(region.shape.swell))
				t.wind = land.exposed[cell]*[2]f32{-math.sin(swell), math.cos(swell)}
				if sp.crown != .Bush do t.open = (sp.lean*push + sp.wind*t.wind)*f32(t.height)   // a bush grows from its root, and the wind only cuts it
				if l, most := math.sqrt(t.open.x*t.open.x + t.open.y*t.open.y), f32(TREE_REACH - t.radius); l > most do t.open *= most/l
			}
			append(out, t)
		}
	}
}

// A tree's crown, as the height of its underside and its top over the tree's base, at a
// distance from the crown's middle (the trunk moved by `open`); the underside lies over the top
// outside it. The grower keeps a tree's leaves inside it, and the far crowns draw it.
envelope :: proc(t: Tree, d: f32) -> (under, over: f32) {
	r := f32(t.radius) + 0.5
	if d >= r do return 1, 0
	top, q := f32(t.height), math.sqrt(1 - d*d/(r*r))
	clear := min(3, top - 1)   // a tree's leaves begin over a walker's head, as its lower branches die in the shade
	switch SPECIES[t.kind].crown {
	case .Broad: return max(top - r*(1.9 - 0.4*q), clear), top - r*0.5*(1 - q)
	case .Dome:  return max(top - r*(1 + q), clear), top - r*0.8*(1 - q)
	case .Oval:  return max(top - r*1.2*(1 + q), clear), top - r*1.2*(1 - q)
	case .Flat:  return max(top - 0.45*top*q, clear), top - 1.5*(1 - q)
	case .Bush:  return 0, top*q
	}
	return 1, 0
}

// The crown's middle, from which the envelope is measured.
crown_at :: proc(t: Tree) -> [2]f32 {
	return {f32(t.x) + 0.5 + t.open.x, f32(t.z) + 0.5 + t.open.y}
}

// The tree grower (foundations/vegetation.md, D4 and section 5). One procedure grows every
// species from its row: each stem leans with the crown toward the open and wanders as the
// species does, then gives out into limbs, or goes on to the top as a leader and the limbs leave
// it in tiers. Each limb runs out to a lobe of leaves set inside the envelope, so the crown is a
// cluster of lobes whose lumps and gaps are the species' own, and the far crown is the same
// tree. Downwind the limbs are longer, and the wind cuts the windward side lower. Everything
// is drawn from the tree's own hash and its place, so every chunk grows the same tree.
// Blocks go into a volume whose block (0, 0, 0) is the world block `o`, over the ground in `c`.
grow :: proc(blocks: []Mat, t: Tree, o: [3]i32, c: ^Columns) {
	layers := i32(len(blocks)/(P*P))
	put :: proc(blocks: []Mat, layers: i32, p: [3]i32, m: Mat, replace: bool) {
		if p.x < 0 || p.x >= P || p.z < 0 || p.z >= P || p.y < 0 || p.y >= layers do return   // below y is this chunk's solid ground: a tree at a cliff's foot
		k := int(p.x) + int(p.z)*P + int(p.y)*P*P
		if replace || blocks[k] == .Air do blocks[k] = m
	}
	// A line of bark half a metre at a time, so it joins face to face where it runs aslant;
	// `thick` makes it two blocks across.
	line :: proc(blocks: []Mat, layers: i32, o: [3]i32, a, b: [3]f32, m: Mat, thick: bool, replace: bool) {
		n := i32(2*max(abs(b.x - a.x), abs(b.y - a.y), abs(b.z - a.z))) + 1
		for s in 0..=n {
			f := f32(s)/f32(n)
			p := a + (b - a)*f
			at := [3]i32{i32(math.floor(p.x)), i32(math.floor(p.y)), i32(math.floor(p.z))} - o
			for k in 0..<(4 if thick else 1) do put(blocks, layers, at + {i32(k%2), 0, i32(k/2)}, m, replace)
		}
	}
	sp := SPECIES[t.kind]
	h := hash(t.x, t.z, seed + 150)
	draw :: proc(h: ^u32) -> f32 {   // the tree's own stream of numbers in 0..1
		h^ = h^*0x2C1B3C6D + 0x297A2D39
		return f32(h^ >> 8)/16777216
	}
	H, r := f32(t.height), f32(t.radius) + 0.5
	foot := [3]f32{f32(t.x) + 0.5, f32(t.base), f32(t.z) + 0.5}
	mid := crown_at(t)
	middle := [3]f32{mid.x, foot.y, mid.y}
	big := t.height >= 18 && t.form == .Canopy   // the tallest trees stand on a trunk two blocks across
	small := t.form >= .Between || t.height < 6   // crowns too small to carry limbs that show, and a dead stub
	stems := 1 if small else sp.stems[0] + i32(draw(&h)*f32(sp.stems[1] - sp.stems[0] + 1))
	limbs := 0 if small else sp.limbs[0] + i32(draw(&h)*f32(sp.limbs[1] - sp.limbs[0] + 1))
	clear := 0 if sp.crown == .Bush else min(f32(3), H - 1)
	turn := 2*math.PI*draw(&h)

	Lobe :: struct { at: [3]f32, a, b: f32 }
	lobes: [24]Lobe
	n := 0
	ends: [24][3]f32   // where each stem and limb gives out: leaves close over it whatever the wind has cut
	e := 0
	for s in 0..<stems {
		spread := [3]f32{math.cos(turn + 2*math.PI*f32(s)/f32(stems)), 0, math.sin(turn + 2*math.PI*f32(s)/f32(stems))}
		base := foot + (0.5*spread if s > 0 else 0) - {0, 1, 0}
		// Where the stem gives out, or for a leader its top. Stems of a clump splay apart.
		fork := max(sp.fork*H, min(4, H - 2)) if !sp.leader else H - 2
		if small do fork = max(H - 2, 1)   // under its crown's top
		end := foot + (middle - foot)*(fork/H) + {0, fork, 0}
		if stems > 1 do end += 0.35*r*spread
		// The stem in three lengths, each kinked aside by up to the species' crook.
		knee: [4][3]f32 = {base, 0, 0, end}
		for i in 1..=2 {   // the lean is taken low, so a leaning bole turns upright toward the crown
			f := f32(i)/3
			knee[i] = base + (end - base)*f + [3]f32{(end - base).x, 0, (end - base).z}*(math.sqrt(f) - f) + [3]f32{draw(&h) - 0.5, 0, draw(&h) - 0.5}*2*sp.crook*(0 if small || i == 1 else 1)   // straight where a walker passes
		}
		along :: proc(knee: [4][3]f32, f: f32) -> [3]f32 {   // the point a share f of the way up the stem
			i := clamp(int(f*3), 0, 2)
			return knee[i] + (knee[i + 1] - knee[i])*(f*3 - f32(i))
		}
		if sp.crown != .Bush do for i in 0..<3 do line(blocks, layers, o, knee[i], knee[i + 1], sp.bark, big && s == 0, true)
		if small || sp.leader {
			ends[e] = end
			e += 1
		}
		if small || sp.crown == .Bush {
			// One crown, as wide as the room it has over the clear bole is deep; a bush is a dome from
			// the ground, low at its edge.
			deep := (H - clear)/2 + 0.5
			if n < len(lobes) do lobes[n] = {middle + {0, clear + deep - 0.5, 0}, min(r - 0.3, deep + 0.5), deep} if sp.crown != .Bush else {middle, r - 0.3, H + 0.5}
			n += 1
			continue
		}
		// The limbs: from the fork, or from the leader in tiers up it.
		for l in 0..<limbs {
			az := turn + math.PI/f32(stems) + 2*math.PI*(f32(l) + 0.6*draw(&h))/f32(limbs)
			if stems > 1 do az = turn + 2*math.PI*f32(s)/f32(stems) + 0.9*math.PI*(draw(&h) - 0.5)   // each stem of a clump carries its own side of the crown
			dir := [3]f32{math.cos(az), 0, math.sin(az)}
			out := sp.reach*r*(0.75 + 0.5*draw(&h))*(1 + 0.6*(dir.x*t.wind.x + dir.z*t.wind.y))   // longer downwind
			a := sp.lobe*r*(0.8 + 0.4*draw(&h))
			b := a*sp.squash
			tip := middle + min(out, r - 0.9*a)*dir   // the lobe's middle stays well inside the envelope
			from := along(knee, 1 - 1.5*draw(&h)/fork)   // limbs leave over the stem's top metre and a half
			if sp.leader {
				f := (f32(l) + 0.5*draw(&h))/f32(limbs)
				from = along(knee, (sp.fork*H + (H - 2.5 - sp.fork*H)*f)/H)
				tip.y = from.y + 0.25*out
			} else {
				// Anywhere in the depth of the envelope at its distance, so the lobes stand at
				// different heights and the crown is lumpy and deep.
				d := math.sqrt((tip.x - mid.x)*(tip.x - mid.x) + (tip.z - mid.y)*(tip.z - mid.y))
				under, over := envelope(t, d)
				tip.y = foot.y + max(math.lerp(min(under + b, over - b), over - b, draw(&h)), clear + 0.7*b)   // and rounded underneath, over the clear bole
			}
			line(blocks, layers, o, from, tip - {0, 0.5*b, 0}, sp.bark, false, false)
			if e < len(ends) do ends[e] = tip - {0, 0.5*b, 0}
			e = min(e + 1, len(ends))
			if n < len(lobes) do lobes[n] = {tip, a, b}
			n += 1
			// The limb forks once near its end, and the twig carries a smaller lobe beside the first.
			if sp.leader do continue
			side := az + (0.5*math.PI if l%2 == 0 else -0.5*math.PI)*(0.6 + 0.6*draw(&h))
			twig := tip + 0.9*a*[3]f32{math.cos(side), (draw(&h) - 0.4)*sp.squash, math.sin(side)}
			if n < len(lobes) do lobes[n] = {twig, 0.75*a, 0.75*b}
			n += 1
		}
		// The top of the crown over the fork, or the leader's top plate.
		a := sp.lobe*r*(1.1 if sp.leader else 0.9)
		if n < len(lobes) do lobes[n] = {{mid.x, foot.y + H - a*sp.squash, mid.y}, a, a*sp.squash}
		n += 1
	}
	if t.form == .Dead || sp.crown == .Bush do e = 0
	for p in ends[:e] {
		at := [3]i32{i32(math.floor(p.x)), i32(math.floor(p.y)), i32(math.floor(p.z))} - o
		for d in ([5][3]i32{{0, 1, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}) do put(blocks, layers, at + d, sp.leaf, false)
	}
	if t.form == .Dead do return
	// The leaves: every lobe, its edge a little uneven, inside the envelope and over the clear
	// bole, and cut lower on the windward side.
	for lb in lobes[:min(n, len(lobes))] {
		lo := [3]i32{i32(math.floor(lb.at.x - lb.a)), i32(math.floor(max(lb.at.y - lb.b, foot.y + clear))), i32(math.floor(lb.at.z - lb.a))}
		hi := [3]i32{i32(math.ceil(lb.at.x + lb.a)), i32(math.ceil(min(lb.at.y + lb.b, foot.y + H))), i32(math.ceil(lb.at.z + lb.a))}
		if hi.x < o.x || lo.x >= o.x + P || hi.z < o.z || lo.z >= o.z + P do continue
		for y in lo.y..<hi.y do for z in lo.z..<hi.z do for x in lo.x..<hi.x {
			p := [3]f32{f32(x), f32(y), f32(z)} + 0.5
			d := (p - lb.at)/{lb.a, lb.b, lb.a}
			e := 1.02 - 0.08*hash01(x + y*57, z, seed + 180)
			if d.x*d.x + d.y*d.y + d.z*d.z > e*e do continue
			if (p.x - mid.x)*(p.x - mid.x) + (p.z - mid.y)*(p.z - mid.y) > r*r do continue   // inside the envelope, and so within reach of every chunk that grows the tree
			u := (p.x - mid.x)*t.wind.x + (p.z - mid.y)*t.wind.y   // metres downwind of the middle, times how exposed
			if p.y > foot.y + H - sp.wind*H*max(-u/r, 0) do continue
			if k := (z - o.z)*P + x - o.x; z >= o.z && z < o.z + P && x >= o.x && x < o.x + P && f32(y - c.top[k]) < clear do continue   // over a walker's head on the ground beneath as well
			put(blocks, layers, {x, y, z} - o, sp.leaf, false)
		}
	}
}
