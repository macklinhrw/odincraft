package main

import "base:builtin"
import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:slice"
import "core:strings"
import "core:time"

// Landmarks, places and names (foundations/kinds-and-places.md, section 5; fantasy.md, decision 6;
// foundations.md, decision 15). Nature has made what is remarkable, so nothing here is placed: a
// finder gathers candidates from the land's grid and the features, each with how extreme it is
// and how much of the ground 1 to 2 km round sees it, and a small pass names the best of them,
// each the most remarkable thing within `APART`, taking in what lies close by. Its name is drawn
// from what made it, in plain English. And a survey counts what the island holds.

Place_Kind :: enum u8 { Summit, Pass, Face, Fall, Lake, Slide, Crater, Head, Cave, Shelter, Notch, Wood, Spring }
Place_Row :: struct {
	what:       string,
	worth:      f32,        // the measure at which a candidate seen from all round earns a name
	eye:        f32,        // metres over the ground or sea a viewpoint stands to look at it
	own:        f32,        // metres round it that are part of it, and may hide its middle; or half its breadth
	skyline:    bool,       // it is seen only where it stands against the sky
	words:      []string,   // its own words; "the " keeps the article, "~" joins a short word before it
	big, small: string,     // for one far past its worth, or barely past it
}
PLACE_ROWS := [Place_Kind]Place_Row{
	.Summit  = {"summit", 150, 25, 400, true, {"Pike", "Top", "Peak", "Hill", "~top"}, "High", "Little"},
	.Pass    = {"pass", 60, 25, 200, true, {"Gap", "the Gap", "Col", "Saddle", "Neck", "~gap"}, "Deep", ""},
	.Face    = {"face", 60, 25, 100, false, {"Scar", "Crag", "Wall", "Edge", "~scar"}, "Great", "Little"},
	.Fall    = {"fall", 25, 25, 32, false, {"Falls", "Force", "Spout", "Falls"}, "High", "Little"},
	.Lake    = {"lake", 2, 300, 32, false, {"Tarn", "Water", "Mere", "Pool", "~mere"}, "Broad", "Little"},
	.Slide   = {"slide", 0.5, 300, 150, false, {"the Slip", "Slip", "the Tumble"}, "Great", "Little"},
	.Crater  = {"crater", 20, 500, 300, false, {"the Bowl", "the Cauldron", "the Pit"}, "Deep", ""},
	.Head    = {"headland", 40, 25, 100, false, {"Head", "Point", "Ness", "Nab", "~head"}, "Great", "Little"},
	.Cave    = {"sea cave", 25, 10, 32, false, {"Cave", "Hole", "~hole"}, "Long", "Little"},
	.Shelter = {"rock shelter", 40, 25, 32, false, {"Hollow", "Overhang", "Shelter"}, "Long", "Little"},
	.Notch   = {"sea notch", 150, 10, 32, false, {"Notch", "Undercut"}, "Long", ""},
	.Wood    = {"old wood", 1000, 100, 100, false, {"Wood", "Grove", "Holt"}, "", ""},
	.Spring  = {"spring", 0.01, 25, 32, false, {"Well", "Spring", "~well"}, "", ""},
}
APART  :: 900    // metres between two places at the least
GATHER :: 400    // what lies this near a place is part of it
MOST   :: 12     // places on an island at most
OF_A_KIND :: 3   // and of one kind, so the island is not eight falls on one stream
SEEN_SIZE :: 40   // metres a thing must stand, up or across, to be known 1.5 km off, where it spans 1.5°
ON_TOP :: bit_set[Place_Kind]{.Summit, .Pass, .Head, .Wood, .Slide, .Crater, .Lake}   // looked at over the woods on it
ON_FOOT :: bit_set[Place_Kind]{.Fall, .Cave, .Shelter, .Notch, .Wood, .Spring}   // a place a person comes upon, known when reached and not from a kilometre off

Candidate :: struct {
	kind:        Place_Kind,
	at:          [2]f64,   // relative to the region's middle
	top:         f32,      // the height a viewpoint looks at
	m:           f32,      // how extreme it is, in the unit of its row's worth
	size:        f32,      // metres of it a viewer sees, up or across
	why:         string,
	feature:     int,      // the feature it is, or -1 for one found on the land's grid
	rock:        Mat,
	seen, score: f32,      // the share of viewpoints 1 to 2 km off that see it; its rank
	view:        [3]f64,   // the best of them, relative to the region's middle
	place:       int,      // the place that took it in, or -1
}
Place :: struct { name: string, c, feature: int }

Survey :: struct {
	land:       f32,   // km²
	squares:    u64,   // the 1 km squares with a quarter or more of land, one bit each
	plants:     [Community_Kind]Tally,
	rocks:      [Mat]Tally,
	soils:      [len(SOILS)]Tally,
	features:   [Feature_Kind]int,
	river:      f32,   // the longest river's length, from its head cell to the sea
	head:       int,
	top:        int,   // the highest cell
	middle:     [2]f64,
}
Tally :: struct { cells: int, squares: u64 }

places_make :: proc() {
	started := time.now()
	g, n := land.grid, land.n
	add :: proc(k: Place_Kind, at: [2]f64, top, m, size: f32, f: int, rock: Mat, why: string) {
		append(candidates, Candidate{kind = k, at = at, top = top, m = m, size = size, feature = f, rock = rock, why = why, place = -1})
	}
	rock_at :: proc(c: int, y: f32) -> Mat { return rock_in(y, land.grid.base[c], ROCK_SIM) }

	// The survey: each community, rock and soil, its share of the land and the squares it is in.
	for ci in g.order {
		c := int(ci)
		sq := u64(1) << uint(min(c/n*int(g.d)/1024, 7)*8 + min(c%n*int(g.d)/1024, 7))   // 8 km of squares; a larger region folds its edge in
		p := Point{x = middle_of(g, c).x, z = middle_of(g, c).y, cell = LAND_CELL}
		soil, _ := soil_at(&p)
		for t in ([]^Tally{&survey.plants[Community_Kind(land.community[c])], &survey.rocks[rock_at(c, g.z[c] - 0.5)], &survey.soils[soil]}) do t.cells, t.squares = t.cells + 1, t.squares | sq
		survey.middle += middle_of(g, c)/f64(len(g.order))
		if g.z[c] > g.z[survey.top] do survey.top = c
	}
	for y in 0..<8 do for x in 0..<8 {
		cells := 0
		for j in 0..<1024/int(g.d) do for i in 0..<1024/int(g.d) do cells += int(!g.sea[(y*1024/int(g.d) + j)*n + x*1024/int(g.d) + i])
		if cells*4 >= (1024/int(g.d))*(1024/int(g.d)) do survey.squares |= 1 << uint(y*8 + x)
	}
	survey.land = f32(len(g.order))*g.d*g.d/1e6
	for f in region.features do survey.features[f.kind] += 1
	long := make([]f32, n*n, context.temp_allocator)   // the river's length from each stream cell to the sea
	for ci in g.order do if c := int(ci); g.area[c] >= CHANNEL_AREA && g.next[c] != SINK {
		long[c] = (long[g.next[c]] if g.next[c] >= 0 else 0) + (span(g, c, int(g.next[c])) if g.next[c] >= 0 else 0)
		if long[c] > survey.river do survey.river, survey.head = long[c], c
	}

	// Summits and the passes between them. Cells are taken from the highest down, each joining the
	// ground it touches that is already taken, whose highest cell is its summit; where two such
	// grounds meet, the cell is the pass between them, and the lower summit's prominence is its
	// height over that pass.
	cells := slice.clone(g.order[:], context.temp_allocator)
	slice.sort_by(cells, proc(a, b: i32) -> bool { return land.grid.z[a] > land.grid.z[b] })
	up, col := make([]i32, n*n, context.temp_allocator), make([]i32, n*n, context.temp_allocator)
	slice.fill(up, -1)
	find :: proc(up: []i32, c: i32) -> i32 {
		r := c
		for up[r] != r do r = up[r]
		for k := c; k != r; k, up[k] = up[k], r {}
		return r
	}
	for c in cells {
		up[c], col[c] = c, -1
		for o in OFFSETS do if k := c + i32(o.y*n + o.x); up[k] >= 0 {
			a, b := find(up, c), find(up, k)
			if a == b do continue
			if g.z[a] < g.z[b] do a, b = b, a
			up[b], col[b] = a, c
		}
	}
	for c in cells {
		prominence := g.z[c] - g.z[col[c]] if col[c] >= 0 else g.z[c]
		if prominence < 30 do continue
		ring: f32
		for a in 0..<24 do ring += max(land_at(land.z[0], n, middle_of(g, int(c)).x + 800*math.cos(f64(a)*math.PI/12), middle_of(g, int(c)).y + 800*math.sin(f64(a)*math.PI/12)), 0)/24
		relief := max(g.z[c] - ring, 0)   // it stands out by the lesser of this and its prominence
		add(.Summit, middle_of(g, int(c)), g.z[c] + 2, min(prominence, relief), relief, -1, rock_at(int(c), g.z[c] - 2),
			fmt.aprintf("a summit %.0f m high, %.0f m over the ground 800 m round it, %.0f m over the pass to any higher ground", g.z[c], relief, prominence))
		if col[c] >= 0 && prominence >= 40 do add(.Pass, middle_of(g, int(col[c])), g.z[col[c]] + 2, prominence, prominence, -1, rock_at(int(col[c]), g.z[col[c]] - 2),
			fmt.aprintf("a pass at %.0f m, %.0f m under the summit on its lower side", g.z[col[c]], prominence))
	}

	// Faces: from each cell the drop down the drainage while the ground stays steeper than 45°, as
	// land_stats finds the tallest, and the tallest of them 400 m apart.
	drop, foot := make([]f32, n*n, context.temp_allocator), make([]i32, n*n, context.temp_allocator)
	tops := make([dynamic]i32, context.temp_allocator)
	for ci in g.order {
		c, r := int(ci), g.next[ci]
		foot[c] = ci
		if r >= 0 && (g.z[c] - g.z[r])/span(g, c, int(r)) >= 1 do drop[c], foot[c] = drop[r] + g.z[c] - g.z[r], foot[r]
		if drop[c] >= 25 do append(&tops, ci)
	}
	faces := make([dynamic]int, context.temp_allocator)
	for len(faces) < 16 {
		best := -1
		next: for t in tops {
			c := int(t)
			for f in faces do if math.hypot(middle_of(g, f).x - middle_of(g, c).x, middle_of(g, f).y - middle_of(g, c).y) < 400 do continue next
			if best < 0 || drop[c] > drop[best] do best = c
		}
		if best < 0 do break
		append(&faces, best)
		mid := (g.z[best] + g.z[foot[best]])/2
		add(.Face, (middle_of(g, best) + middle_of(g, int(foot[best])))/2, mid, drop[best], drop[best], -1, rock_at(best, mid),
			fmt.aprintf("a face %.0f m tall, from %.0f m down to %.0f m", drop[best], g.z[best], g.z[foot[best]]))
	}

	// What the events and the water left, each a feature already.
	for f, i in region.features do #partial switch f.kind {
	case .Fall:
		h, area := f.measured[0].value, f.measured[1].value
		add(.Fall, f.at, f.level + 1, h*math.sqrt(river_half(area*1e6)/2), math.sqrt(h*2*river_half(area*1e6)), i, fall_rock(f), fmt.aprintf("a fall %.0f m high over %v, draining %.2f km² (%.2f m³/s)%s", h, fall_rock(f), area, f.size,
			fmt.tprintf(", into a gorge %.0f m long", f.reach) if f.reach > 30 else ""))
	case .Lake:
		add(.Lake, f.at, f.level + 1, f.size/1e4, math.sqrt(f.size), i, landslide.rock, fmt.aprintf("a lake of %.1f ha, %.0f m deep, dammed %s years ago", f.size/1e4, f.measured[0].value, years(f.age)))
	case .Slide:
		add(.Slide, f.at, land_at(land.z[0], n, f.at.x, f.at.y), f.size/1e6, f.reach*clamp(1 - f.age/500, 0.05, 1), i, landslide.rock, fmt.aprintf("a slide %s years ago that took %.1f million m³ of %v from the hillside", years(f.age), f.size/1e6, landslide.rock))
	case .Cave, .Notch:   // looked at from the sea before its mouth
		at, by := f.at, f64(1e9)
		for dy in -6..=6 do for dx in -6..=6 do if c := land_cell(f.at.x, f.at.y) + dy*n + dx; g.sea[c] && math.hypot(f64(dx), f64(dy)) < by do at, by = middle_of(g, c), math.hypot(f64(dx), f64(dy))
		add(.Cave if f.kind == .Cave else .Notch, at, 3, f.reach, 10 if f.kind == .Cave else 3, i, rock_at(land_cell(f.at.x, f.at.y), 2), fmt.aprintf("a %s %.0f m long, cut by the swell", PLACE_ROWS[.Cave if f.kind == .Cave else .Notch].what, f.reach))
	case .Shelter:
		add(.Shelter, f.at, f.level, f.reach, 3, i, rock_at(land_cell(f.at.x, f.at.y), f.level + 1), fmt.aprintf("a rock shelter %.0f m long under %v", f.reach, rock_at(land_cell(f.at.x, f.at.y), f.level + 1)))
	case .Spring:
		add(.Spring, f.at, f.level, f.size, 1, i, rock_at(land_cell(f.at.x, f.at.y), f.level + 3), fmt.aprintf("a spring of %.1f l/s out of %v", 1000*f.size, rock_at(land_cell(f.at.x, f.at.y), f.level + 3)))
	}
	for v in region.vents do if v.fallen {
		add(.Crater, v.at, v.floor + v.deep, v.deep, 2*v.crater, -1, rock_at(land_cell(v.at.x, v.at.y), v.floor + v.deep), fmt.aprintf("a crater %.1f km across, its floor %.0f m under its rim", 2*v.crater/1000, v.deep))
	}
	// Headlands, by their height and how open they are to the swell, 600 m apart; and the oldest wood.
	heads := make([dynamic]int, context.temp_allocator)
	oldest := -1
	for ci in g.order {
		c := int(ci)
		k := Community_Kind(land.community[c])
		if (k == .Valley || k == .Slope) && (oldest < 0 || land.age[c] > land.age[oldest]) do oldest = c
		if headland(c) < 0.55 do continue
		for &h in heads do if math.hypot(middle_of(g, h).x - middle_of(g, c).x, middle_of(g, h).y - middle_of(g, c).y) < 600 {
			if g.z[c]*(1 + 2*land.swell[c]) > g.z[h]*(1 + 2*land.swell[h]) do h = c
			c = -1
			break
		}
		if c >= 0 do append(&heads, c)
	}
	for h in heads do add(.Head, middle_of(g, h), g.z[h] + 2, g.z[h]*(1 + 2*land.swell[h]), g.z[h], -1, rock_at(h, g.z[h] - 2),
		fmt.aprintf("a headland %.0f m high with the sea on %.0f%% of the ground round it, %.2f open to the swell", g.z[h], 100*headland(h), land.swell[h]))
	if oldest >= 0 do add(.Wood, middle_of(g, oldest), g.z[oldest] + 15, min(land.age[oldest], 1000), 5, -1, rock_at(oldest, g.z[oldest] - 2),
		fmt.aprintf("the oldest stand of %s, about %s years since a storm last threw its canopy", COMMUNITIES[Community_Kind(land.community[oldest])].name, years(land.age[oldest])))

	// How much of the ground 1 to 2 km round sees each: from 24 bearings at five distances, the eye
	// at its row's height over the ground or sea, the line to it clearing the ground and the woods
	// on it by 3 m, or a lake's water, outside what is part of it; for a summit or a pass, with sky
	// behind it too. What stands on the ground is looked at over its woods, a fall at its lip. A
	// thing seen from half the ring is seen as well as it can be, since a face or a fall has one
	// front. Of the viewpoints that see it, --place= stands at the one whose line clears the ground
	// by the most, up to 100 m and less a metre for each 25 m it lies nearer or farther than 1.5 km:
	// a view across water or a valley rather than over a near ridge, never hard by a face.
	// Its score: how far past what earns a name, on a log scale, over the root of how many of its
	// kind on the island are nearly as extreme, since a face among fifteen like it is the island's
	// wall and not a landmark (kinds-and-places.md: "rare for its region"). A summit's prominence
	// already says it stands apart from the rest, so seven domes are seven landmarks.
	for &c in candidates {
		alike := 0
		for o in candidates do alike += int(o.kind == c.kind && o.m >= 0.85*c.m && (c.kind != .Summit || o.m == c.m))
		c.score = math.log2(1 + c.m/PLACE_ROWS[c.kind].worth)/math.sqrt(f32(alike))
	}
	slice.sort_by(candidates[:], proc(a, b: Candidate) -> bool { return a.score > b.score })
	builtin.resize(candidates, min(len(candidates), 48))
	screen :: proc(x, z: f64) -> f32 {
		c := land_cell(x, z)
		if land.lake[c] > 0 do return region.features[land.lake[c] - 1].level
		return max(land.z[0][c], 0) + (15*COMMUNITIES[Community_Kind(land.community[c])].density if land.community[c] != 255 && land.slope[c] < SOIL_HOLDS else 0)
	}
	sight :: proc(e, t: [3]f64, own: f64, skyline: bool) -> (clear: f64) {   // the least the line clears by, under 3 m if it does not
		d := t - e
		long := math.hypot(d.x, d.z)
		clear = 1e9
		for s := f64(LAND_CELL); ; s += LAND_CELL {
			if s > long - own && s < long + 32 do continue   // the place itself
			if s >= long + 32 && !skyline do return
			q := e + d*s/long
			if max(abs(q.x), abs(q.z)) > region.size/2 - LAND_CELL do return
			clear = min(clear, q.y - f64(screen(q.x, q.z)))
			if clear < 3 do return
		}
	}
	for &c in candidates {
		row := PLACE_ROWS[c.kind]
		if c.kind in ON_TOP do c.top = max(c.top, screen(c.at.x, c.at.y) + 2)
		t := [3]f64{c.at.x, f64(c.top), c.at.y}
		best := f64(1e9)   // none yet
		for a in 0..<24 do for r in 0..<5 {
			bearing, d := f64(a)*math.PI/12, 1000 + 250*f64(r)
			x, z := c.at.x + d*math.sin(bearing), c.at.y - d*math.cos(bearing)
			if max(abs(x), abs(z)) > region.size/2 - 64 do continue
			e := [3]f64{x, f64(max(land.z[0][land_cell(x, z)], 0) + row.eye), z}
			clear := sight(e, t, f64(max(row.own, c.size/2)), row.skyline)
			if clear < 3 do continue
			c.seen += 1.0/120
			if v := min(clear, 100) - abs(d - 1500)/25; clear >= 15 && land.slope[land_cell(x, z)] < 0.3 && (v > best || best == 1e9) do c.view, best = e, v
		}
		// A place no far viewpoint sees clear, as one in a gorge, is looked at from near by: from the
		// lowest ground 150 m off, which is down its valley, at the tree tops.
		if best == 1e9 do for a in 0..<24 {
			bearing := f64(a)*math.PI/12
			x, z := c.at.x + 150*math.sin(bearing), c.at.y - 150*math.cos(bearing)
			if h := f64(max(land.z[0][land_cell(x, z)], 0)); h < best do c.view, best = {x, h + 30, z}, h
		}
		if c.kind not_in ON_FOOT do c.score *= min(0.3 + 1.4*c.seen, 1)*min(c.size/SEEN_SIZE, 1)
	}
	slice.sort_by(candidates[:], proc(a, b: Candidate) -> bool { return a.score > b.score })

	// The places: best first, each at least APART from the last, taking in what lies within GATHER.
	kinds: [Place_Kind]int
	next_place: for &c, i in candidates {
		if c.place >= 0 || c.score < 1 || len(places) == MOST || kinds[c.kind] == OF_A_KIND do continue
		for p in places do if math.hypot(candidates[p.c].at.x - c.at.x, candidates[p.c].at.y - c.at.y) < APART do continue next_place
		for &o in candidates do if o.place < 0 && math.hypot(o.at.x - c.at.x, o.at.y - c.at.y) < GATHER do o.place = len(places)
		kinds[c.kind] += 1
		append(&region.features, Feature{kind = .Place, at = c.at, reach = GATHER, size = c.score, level = c.top, cause = c.feature,
			measured = {{"how extreme it is, against what earns a name", c.m/PLACE_ROWS[c.kind].worth}, {"the share of viewpoints 1 to 2 km off that see it", c.seen}, {}}})
		append(places, Place{c = i, feature = len(region.features) - 1})
	}
	for &p, i in places do p.name = place_name(i)
	fmt.printfln("places in %.0f ms: %d named from %d candidates", time.duration_milliseconds(time.since(started)), len(places), len(candidates))
	for p, i in places {
		c := candidates[p.c]
		fmt.printf("  %d %s, at %.0f, %.0f: %s; seen from %.0f%% of the ground 1 to 2 km round", i + 1, p.name, c.at.x + f64(region.origin.x), c.at.y + f64(region.origin.y), c.why, 100*c.seen)
		for o in candidates do if o.place == i && o.why != c.why do fmt.printf("; with %s", o.why)
		fmt.println()
	}
}

// A place's name, from what made it (kinds-and-places.md, "Places"): a word drawn from its cause
// (its rock's colour, the tree of its wood, its size, what happened there, the wind, where it lies
// on the island) and then its own word, each drawn by the place's own key, and none used twice.
COLOURS := #partial [Mat]string{.Mudstone = "Grey", .Siltstone = "Brown", .Sandstone = "Yellow", .Grit = "Red", .Limestone = "White", .Basalt = "Black", .Scoria = "Red", .Rhyolite = "Pale", .Tuff = "White"}
TREE_WORDS := [Tree_Kind]string{.Tabu = "Tabu", .Shii = "Shii", .Camellia = "Camellia", .Hisakaki = "", .Pine = "Pine", .Scrub = "", .Alder = "Alder"}   // a small tree with a long name, and bushes of no one kind, name nothing
COUNTS := [?]string{"", "", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"}
JOINS :: " Grey White Pale Wind Slip Pine Old New High "   // words that join the one after them: Greytop, Windgap, from Windy; never Redhead or Blacktop

place_name :: proc(i: int) -> string {
	c := candidates[places[i].c]
	row, cell := PLACE_ROWS[c.kind], land_cell(c.at.x, c.at.y)
	key := hash(i32(cell), i32(c.kind), seed + fnv.fnv32a(transmute([]u8)string("names")))
	Word :: struct { w: string, weight: f32 }
	words := make([dynamic]Word, context.temp_allocator)
	falls, ponds, slid := 0, 0, abs(land.slid[cell]) > 0.5
	for o in candidates do if o.place == i do falls += int(o.kind == .Fall)
	for f in region.features do ponds += int(f.kind == .Pond && math.hypot(f.at.x - c.at.x, f.at.y - c.at.y) < GATHER)
	for o in candidates do slid ||= o.place == i && (o.kind == .Slide || o.kind == .Lake)
	if c.kind == .Fall && falls >= 3 do return fmt.aprintf("%s Falls", COUNTS[min(falls, 10)])
	if c.kind == .Slide && ponds >= 3 do return fmt.aprintf("the %s Ponds", COUNTS[min(ponds, 10)])
	append(&words, Word{COLOURS[c.rock], 1.5})
	if k := land.community[cell]; k != 255 && c.kind != .Crater {
		share, tree := f32(0), 0
		for s, t in COMMUNITIES[Community_Kind(k)].trees do if s > share do share, tree = s, t
		append(&words, Word{TREE_WORDS[Tree_Kind(tree)], 3 if c.kind == .Wood else 1})
	}
	r := c.m/row.worth
	if r >= 4 do append(&words, Word{row.big, 2})
	else if r < 1.5 do append(&words, Word{row.small, 0.7})
	if land.exposed[cell] >= 0.8 do append(&words, Word{"Windy", 1})
	if slid && c.kind != .Slide do append(&words, Word{"Slip", 3})
	if c.kind == .Slide && region.features[landslide.feature].age < 100 do append(&words, Word{"New", 2})
	if c.kind == .Fall do append(&words, Word{"White", 1})
	if c.kind == .Wood do append(&words, Word{"Old", 2})
	if c.kind == .Cave || (c.kind == .Fall && region.features[c.feature].reach > 40) do append(&words, Word{"Dark", 1})
	bearing := math.mod(math.to_degrees(math.atan2(c.at.x - survey.middle.x, survey.middle.y - c.at.y)) + 360, 360)
	quarters := [4]string{"North", "East", "South", "West"}
	if math.hypot(c.at.x - survey.middle.x, c.at.y - survey.middle.y) > 1000 do append(&words, Word{quarters[int(bearing + 45)/90%4], 0.8 if c.kind == .Head || c.kind == .Face || c.kind == .Summit else 0.2})
	// Drop the words another place has taken, unless none is left, then draw one by its weight.
	total: f32
	for &w in words {
		if w.w == "" do w.weight = 0
		for p in places[:i] do if strings.contains(fmt.tprintf(" %s ", p.name), fmt.tprintf(" %s", w.w)) do w.weight = -w.weight
		total += max(w.weight, 0)
	}
	if total == 0 do for &w in words do w.weight, total = abs(w.weight), total + abs(w.weight)
	u, word := f32(key >> 8)/16777216*total, ""
	for w in words do if w.weight > 0 && word == "" {
		if u < w.weight do word = w.w
		u -= w.weight
	}
	join := "Wind" if word == "Windy" else word
	for k in 0..<len(row.words) {
		g := row.words[(int(key%7) + k)%len(row.words)]
		name: string
		switch {
		case word == "":                  name = strings.trim_prefix(g, "~")
		case strings.has_prefix(g, "the "): name = fmt.tprintf("the %s %s", word, g[4:])
		case g[0] == '~' && strings.contains(JOINS, fmt.tprintf(" %s ", join)): name = fmt.tprintf("%s%s", join, g[1:])
		case g[0] == '~':                 name = fmt.tprintf("%s %s%s", word, strings.to_upper(g[1:2], context.temp_allocator), g[2:])
		case:                             name = fmt.tprintf("%s %s", word, g)
		}
		taken := false
		for p in places[:i] do taken ||= p.name == name
		if !taken do return strings.clone(name)
	}
	return fmt.aprintf("%s %s", word, row.words[0])
}

// The place a point lies in or nearest it, as the window's title and --why give it.
place_near :: proc(x, z: f64) -> (i: int, d: f64) {
	i, d = -1, 1e9
	for p, k in places do if e := math.hypot(candidates[p.c].at.x - x, candidates[p.c].at.y - z); e < d do i, d = k, e
	return
}

named_words :: proc(x, z: f64) {
	i, d := place_near(x, z)
	if i < 0 do return
	c := candidates[places[i].c]
	if d < GATHER do fmt.printfln("at %s, place %d of %d named on the island: %s, seen from %.0f%% of the ground 1 to 2 km round. It was named for being the most remarkable thing within %d m.", places[i].name, i + 1, len(places), c.why, 100*c.seen, APART)
	else do fmt.printfln("the nearest named place is %s, %.1f km off toward %.0f°: %s.", places[i].name, d/1000, math.mod(math.to_degrees(math.atan2(c.at.x - x, z - c.at.y)) + 360, 360), c.why)
}

// Each place on the map: a yellow disc ringed in black, and its number beside it.
places_mark :: proc(pixels: []u8, size: int) {
	DIGITS :: [10]u16{0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9, 0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF}   // 3 by 5, the top row in the high bits
	digits := DIGITS
	for p, i in places {
		c := candidates[p.c]
		px, py := int((c.at.x + region.size/2)*f64(size)/region.size), int((c.at.y + region.size/2)*f64(size)/region.size)
		label := fmt.tprintf("%d", i + 1)
		for dy in -9..=9 do for dx in -7..=8 + 12*len(label) do if x, y := px + dx, py + dy; x >= 0 && y >= 0 && x < size && y < size {
			r, ink := dx*dx + dy*dy, -1
			if r <= 49 do ink = 255 if r <= 25 else 0
			if k, u, v := (dx - 9)/12, (dx - 9)%12, dy + 8; dx >= 9 && v >= 0 && v < 17 && k < len(label) {
				bit := u >= 1 && u < 10 && v >= 1 && v < 16 && digits[label[k] - '0'] >> uint(14 - ((v - 1)/3)*3 - (u - 1)/3) & 1 == 1
				ink = 255 if bit else 0
			}
			if ink >= 0 do for k in 0..<3 do pixels[(y*size + x)*4 + k] = u8(ink) if k < 2 else 0
		}
	}
}

// What the island holds, for --survey: the share of the land each community, rock and soil
// takes and how many of its 1 km squares it is in, absent or everywhere (in nine squares of ten);
// each kind of feature; the extremes; and the candidates for places, best first.
survey_print :: proc() {
	g := land.grid
	all := card(transmute(bit_set[0..<64; u64])survey.squares)
	spread :: proc(t: Tally, all: int) -> string {
		if t.cells == 0 do return "absent"
		within := card(transmute(bit_set[0..<64; u64])(t.squares & survey.squares))
		return fmt.tprintf("%.0f%%, %s", 100*f32(t.cells)/f32(len(land.grid.order)), "everywhere" if within*10 >= all*9 else fmt.tprintf("in %d squares", within))
	}
	at :: proc(c: int) -> [2]f64 { return middle_of(land.grid, c) + {f64(region.origin.x), f64(region.origin.y)} }
	fmt.printfln("survey of the %s island on seed %d: %.1f km² of land, %d squares of 1 km with a quarter of it or more", region.kind, seed, survey.land, all)
	fmt.printfln("  highest point %.0f m at %.0f, %.0f; longest river %.1f km, from its head at %.0f, %.0f", g.z[survey.top], at(survey.top).x, at(survey.top).y, survey.river/1000, at(survey.head).x, at(survey.head).y)
	fmt.print("  plants:")
	for t, k in survey.plants do fmt.printf("%s %s %s", "" if k == .Valley else ";", COMMUNITIES[k].name, spread(t, all))
	fmt.print("\n  rock at the surface:")
	for t, m in survey.rocks do if MATERIALS[m].strength > 0 do fmt.printf(" %v %s;", m, spread(t, all))
	fmt.print("\n  soil:")
	for t, k in survey.soils do fmt.printf(" %s %s;", SOILS[k].name, spread(t, all))
	fmt.print("\n  features:")
	for count, k in survey.features do if k != .Place && k != .Haunt do fmt.printf(" %v %d;", k, count)
	largest, tallest := -1, -1
	for f, i in region.features {
		if f.kind == .Lake && (largest < 0 || f.size > region.features[largest].size) do largest = i
		if f.kind == .Fall && (tallest < 0 || f.measured[0].value > region.features[tallest].measured[0].value) do tallest = i
	}
	if largest >= 0 do fmt.printf(" the largest lake %.1f ha;", region.features[largest].size/1e4)
	if tallest >= 0 do fmt.printf(" the tallest fall %.0f m", region.features[tallest].measured[0].value)
	fmt.println("\n  candidates, best first; 1 or more earns a name: how far past its row's worth on a log scale, over the root of how many alike, times 0.3 + 1.4 of the share seen 1 to 2 km off (at most 1) and its size over 40 m (at most 1)")
	for c, i in candidates do fmt.printfln("  %2d %-12s %.2f  %s, at %.0f, %.0f; seen %.0f%%%s", i + 1, PLACE_ROWS[c.kind].what, c.score, c.why, c.at.x + f64(region.origin.x), c.at.y + f64(region.origin.y), 100*c.seen,
		fmt.tprintf("; place %d, %s", c.place + 1, places[c.place].name) if c.place >= 0 else "")
}
