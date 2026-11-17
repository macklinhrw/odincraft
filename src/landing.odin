package main

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

// Where a party comes ashore (plan.md, P2). A landing is a row, as everything else is: a host on
// the land's fields, read at each cell of land beside the sea, and the cell where it holds best is
// the landing. The rows stand in order and the first that holds anywhere on the island decides, so
// an island with no shut-in bay still gets a landing, and start-up says which row and why. Three
// fields were made for it (fields.odin), each what a people looks for round a point: how much of
// the kilometre round it is sea, how far fresh water is, and how far ground to live on. They are
// read from the land's cells round the point when asked, and kept nowhere.
//
// The figures are those the land is already measured by (land_report.odin, after real-islands.md):
// a sheltered landing is shore under 5 m where the sea fills less than a third of the square a
// kilometre across, with livable ground within 100 m. Fresh water within 300 m is this step's own
// (a guess: a walk of a few minutes with a full pail).
//
// An expedition may choose its own shore (plan.md, E-1). The boat is then brought in at the low shore
// nearest the place asked for that a boat can come in to (landing_near), by the rule the game's own
// choice is tried by, so the screen that offers the choice and the hold that lands there agree. What
// a place on the shore offers a founder, and lacks, is rows too (SHORE): each a thing, the fields it
// is read from round the place, where they hold well and where they are lacking, and the word for it.

Landing :: struct {
	name, why: string,
	host:      []Window,   // where a boat can land at all
	likes:     []Window,   // and of those cells, the one these hold best on is the landing
}
LIKES := []Window{{.Fresh_Water, -ANY, 0, 600}, {.Sea_Round, -ANY, 0, 1}, {.Swell, -ANY, SHELTER, 0.4}, {.Slope, -ANY, 0.1, 0.5}}   // the nearest the water, the most shut in, the least swell, the gentlest shore
LANDINGS := [?]Landing{
	{"a sheltered landing by fresh water", "the land shuts the sea in there, so a boat can be drawn up out of the swell, with ground to live on beside it and a stream that runs all year a short walk off",
		{{.Height, -ANY, 5, 0}, {.Sea_Round, -ANY, 1.0/3, 0}, {.Livable_Near, -ANY, 100, 0}, {.Fresh_Water, -ANY, 300, 0}}, LIKES},
	{"a sheltered landing", "the land shuts the sea in there, so a boat can be drawn up out of the swell, with ground to live on beside it; water is a longer walk",
		{{.Height, -ANY, 5, 0}, {.Sea_Round, -ANY, 1.0/3, 0}, {.Livable_Near, -ANY, 100, 0}}, {{.Fresh_Water, -ANY, 0, 2e4}, {.Sea_Round, -ANY, 0, 1}, {.Swell, -ANY, SHELTER, 0.4}, {.Slope, -ANY, 0.1, 0.5}}},
	{"the least open shore", "no shore of the island is shut in by land with ground to live on beside it, so the boat takes the low shore the swell reaches least",
		{{.Height, -ANY, 5, 0}}, {{.Swell, -ANY, 0, 1.5}, {.Sea_Round, -ANY, 0, 2}, {.Slope, -ANY, 0.1, 2}}},
}
REACH_IN :: 30   // metres of open water a boat needs to come in along
FAR :: 1e4   // a field's value where what it measures to is out of its reach

// Metres from a land cell to the nearest within `reach` cells that something holds on, and that cell.
cell_near :: proc(c, reach: int, holds: proc(c: int) -> bool) -> (d: f32, at: int) {
	n := land.n
	at = -1
	least := max(int)
	for r in 0..=reach {
		if r*r > least do break
		for dy in -r..=r do for dx in -r..=r do if max(abs(dx), abs(dy)) == r {
			x, y := c%n + dx, c/n + dy
			if s := dx*dx + dy*dy; x >= 0 && y >= 0 && x < n && y < n && s < least && holds(y*n + x) do least, at = s, y*n + x
		}
	}
	return LAND_CELL*math.sqrt(f32(least)) if at >= 0 else FAR, at
}

// A stream that runs all year (one draining what makes a valley a stream's, CHANNEL_AREA), a lake or a pond.
fresh :: proc(c: int) -> bool { return !land.grid.sea[c] && (land.lake[c] > 0 || trails.wade[c] > 0 && land.grid.area[c] >= CHANNEL_AREA) }
fresh_water :: proc(c: int) -> f32 { d, _ := cell_near(c, 40, fresh); return d }
livable :: proc(c: int) -> bool { return land.live[c] > 0 }
livable_near :: proc(c: int) -> f32 { d, _ := cell_near(c, 16, livable); return d }

// The share of the land's cells within 500 m either way of a cell that are sea.
sea_round :: proc(c: int) -> f32 {
	n, g := land.n, land.grid
	r := int(500/LAND_CELL)
	sea, all := 0, 0
	for y in max(c/n - r, 0)..=min(c/n + r, n - 1) do for x in max(c%n - r, 0)..=min(c%n + r, n - 1) {
		sea += int(g.sea[y*n + x])
		all += 1
	}
	return f32(sea)/f32(all)
}

// The land's cells that lie beside the sea, in the order the land's cells are kept.
shore_cells :: proc() -> []int {
	g, n := land.grid, land.n
	shore := make([dynamic]int, context.temp_allocator)
	for ci in g.order {
		c := int(ci)
		if c%n < 1 || c/n < 1 || c%n >= n - 1 || c/n >= n - 1 do continue
		beside := false
		for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x]
		if beside do append(&shore, c)
	}
	return shore[:]
}

// The first of the landing's rows that holds at a cell of shore, or -1 where none does: the shore
// stands too high over the sea for a boat to be drawn up on it.
landing_row :: proc(c: int) -> int {
	m := middle_of(land.grid, c)
	p := point_at(m.x, m.y, LAND_CELL)
	for row, r in LANDINGS do if host(row.host, &p) > 0 do return r
	return -1
}

// Hectares of ground a person could live on within 300 m of a cell.
livable_round :: proc(c: int) -> f32 {
	n, r := land.n, int(300/LAND_CELL)
	live := 0
	for y in max(c/n - r, 0)..=min(c/n + r, n - 1) do for x in max(c%n - r, 0)..=min(c%n + r, n - 1) do if dx, dy := x - c%n, y - c/n; dx*dx + dy*dy <= r*r {
		live += int(land.live[y*n + x] > 0)
	}
	return f32(live)*LAND_CELL*LAND_CELL/1e4
}

// The mean steepness of the land within 150 m of a cell.
slope_round :: proc(c: int) -> f32 {
	n, g, r := land.n, land.grid, int(150/LAND_CELL)
	sum, cells := f32(0), 0
	for y in max(c/n - r, 0)..=min(c/n + r, n - 1) do for x in max(c%n - r, 0)..=min(c%n + r, n - 1) do if dx, dy := x - c%n, y - c/n; dx*dx + dy*dy <= r*r && !g.sea[y*n + x] {
		sum += land.slope[y*n + x]
		cells += 1
	}
	return sum/f32(max(cells, 1))
}

// The share of the places in the canopy, on the land within 300 m of a cell, that a tree a log can
// be cut from takes, as the plant communities there set it; and the two kinds there are most of. A
// bush of scrub gives no timber (orders.odin).
timber_round :: proc(c: int) -> (share: f32, most: [2]Tree_Kind) {
	n, g, r := land.n, land.grid, int(300/LAND_CELL)
	kinds: [Tree_Kind]f32
	cells := 0
	for y in max(c/n - r, 0)..=min(c/n + r, n - 1) do for x in max(c%n - r, 0)..=min(c%n + r, n - 1) do if dx, dy := x - c%n, y - c/n; dx*dx + dy*dy <= r*r && !g.sea[y*n + x] {
		cells += 1
		k := land.community[y*n + x]
		if k == 255 do continue
		com := COMMUNITIES[Community_Kind(k)]
		for part, t in com.trees do if Tree_Kind(t) != .Scrub do kinds[Tree_Kind(t)] += com.density*part
	}
	best := [2]f32{0, 0}
	most = {.Scrub, .Scrub}   // scrub: none
	for v, k in kinds {
		share += v
		if v > best[0] do most, best = {k, most[0]}, {v, best[0]}
		else if v > best[1] do most[1], best[1] = k, v
	}
	return share/f32(max(cells, 1)), most
}

// Metres from a cell to the stream that runs down to the sea from a lake a slide dammed, and that
// lake's feature; FAR where none passes within 640 m.
dam_below :: proc(c: int) -> (d: f32, lake: int) {
	g, n := land.grid, land.n
	d, lake = FAR, -1
	at := middle_of(g, c)
	for f, i in region.features do if f.kind == .Lake && f.cause >= 0 && region.features[f.cause].kind == .Slide {
		k := grid_cell(g, f.at.x, f.at.y)
		for steps := 0; k >= 0 && steps < n*n; steps += 1 {
			if land.lake[k] != u8(i + 1) {   // below its dam
				m := middle_of(g, k)
				if e := f32(math.hypot(m.x - at.x, m.y - at.y)); e < d && e <= 640 do d, lake = e, i
			}
			k = int(g.next[k])
		}
	}
	return
}

// What a place on the shore offers a founder and what it lacks (plan.md, E-1), as rows: a thing,
// the fields it is read from, where they hold well and where they are lacking, the word or figure
// for it, and what it is called among the cautions an expedition is shown before it sets out. The
// rows marked `may` are what the land may do there: they stand only where their fields hold, and the
// `grave` among them are marked as trouble.
// Every figure is one of the land's fields round the place (fields.odin), read when asked.
Shore_Row :: struct {
	thing:  string,
	camp:   bool,        // read on the ground the party would gather on, not on the shore
	well:   []Window,    // where these hold, the place offers it
	lacks:  []Window,    // and where these do, it lacks it
	may:    bool,
	grave:  bool,
	named:  string,      // among the cautions
	says:   proc(p: ^Point) -> string,
	why:    string,
}
WALK  :: 300   // metres to fresh water that are a short walk (LANDINGS)
STEEP :: 0.7   // the mean rise over run round a place, 35°, over which its ground is called steep (a guess: ground a walker takes with its hands)
SHORE := [?]Shore_Row{
	{"Shelter", false, {{.Sea_Round, -ANY, 1.0/3, 0}}, {{.Sea_Round, 1.0/3, ANY, 0}, {.Swell, SHELTER, ANY, 0}}, false, false, "Open to the swell",
		proc(p: ^Point) -> string {
			if FIELDS[.Sea_Round].at(p) <= 1.0/3 do return "shut in by land"
			return "open to the swell" if FIELDS[.Swell].at(p) > SHELTER else "open, in the island's lee"
		}, "A boat drawn up lies out of the waves where the land shuts the sea in: where the sea fills under a third of the kilometre round."},
	{"Fresh water", false, {{.Fresh_Water, -ANY, WALK, 0}}, {{.Fresh_Water, WALK, ANY, 0}}, false, false, "No fresh water within a walk",
		proc(p: ^Point) -> string {
			d, at := cell_near(land_cell(p.x, p.z), 40, fresh)
			if at < 0 do return "none within 640 m"
			what := "a stream"
			if l := land.lake[at]; l > 0 do what = "a lake" if region.features[l - 1].kind == .Lake else "a pond"
			return fmt.tprintf("%s, beside it", what) if d < LAND_CELL else fmt.tprintf("%s, %.0f m", what, math.round(d/10)*10)
		}, "A stream that runs all year, a lake or a pond. A short walk is 300 m: a few minutes with a full pail."},
	{"Ground to live on", false, {{.Livable_Near, -ANY, 100, 0}}, {{.Livable_Near, 100, ANY, 0}}, false, false, "No ground to live on beside it",
		proc(p: ^Point) -> string {
			d := FIELDS[.Livable_Near].at(p)
			if d >= FAR do return "none within 250 m"
			ha := FIELDS[.Livable_Round].at(p)
			return fmt.tprintf("%.1f ha, beside it", ha) if d <= LAND_CELL else fmt.tprintf("%.1f ha, %.0f m off", ha, math.round(d/10)*10)
		}, "Ground under 20°, 2 m or more over the sea, a hectare or more together: how much of it lies within 300 m, and how far the nearest is."},
	{"Slope", false, {{.Slope_Round, -ANY, 0.18, 0}}, {{.Slope_Round, STEEP, ANY, 0}}, false, false, "Steep ground",
		proc(p: ^Point) -> string {
			s := FIELDS[.Slope_Round].at(p)
			return fmt.tprintf("%s, %.0f°", "gentle" if s <= 0.18 else "rolling" if s <= LIVABLE else "hilly" if s <= STEEP else "steep", math.to_degrees(math.atan(s)))
		}, "The mean of the land within 150 m: gentle to 10°, rolling to 20°, which is the steepest ground lived on, hilly to 35°, and steep over that."},
	{"Timber", false, {{.Timber_Round, 0.3, ANY, 0}}, {{.Timber_Round, -ANY, 0.05, 0}}, false, false, "No timber near",
		proc(p: ^Point) -> string {
			share, most := timber_round(land_cell(p.x, p.z))
			if share <= 0.05 do return "none within 300 m"
			kinds := SPECIES[most[0]].name if most[1] == .Scrub else fmt.tprintf("%s and %s", SPECIES[most[0]].name, SPECIES[most[1]].name)
			return fmt.tprintf("%s, %s", kinds, "thick" if share >= 0.5 else "open" if share >= 0.3 else "thin")
		}, "The trees a log can be cut from, on the land within 300 m, by the woods that grow there."},
	{"Rock", true, {}, {{.Strength, TOOLS, ANY, 0}}, false, false, "Rock too hard for the picks",
		proc(p: ^Point) -> string {
			m := Mat(int(FIELDS[.Rock].at(p)))
			return fmt.tprintf("%s, %s", mat_words(m), cut_words(m))
		}, "The bed at the surface, under the soil, where the party would gather."},
	{"Slide's lake", false, {}, {{.Dam_Below, -ANY, 200, 0}}, true, true, "A slide's lake above",
		proc(p: ^Point) -> string {
			d, _ := dam_below(land_cell(p.x, p.z))
			return fmt.tprintf("its stream %.0f m off", math.round(d/10)*10) if d >= LAND_CELL else "on its stream"
		}, "A slide dammed a stream, and a lake stands behind its debris. The stream below the dam runs past here: were the dam to fail, this is where the water would come."},
	{"Slid ground", true, {}, {{.Disturbed, -ANY, 9e4, 0}}, true, false, "Ground that slid",
		proc(p: ^Point) -> string { return fmt.tprintf("%s years ago", years(FIELDS[.Disturbed].at(p))) },
		"A slide's scar or its debris: the ground the party would gather on came down, or was laid bare."},
	{"Stream's fan", true, {}, {{.Fan, 0.3, ANY, 0}}, true, false, "On a stream's fan",
		proc(p: ^Point) -> string { return "laid by its floods" },
		"The flat at a stream's mouth is what the stream laid there in flood."},
}

// What a card says of the place at a cell of shore: a row for each row of SHORE, and one for the
// rock under the surface bed. `rows` are the card's own (card_row). The island is bound.
site_write :: proc(k: ^[dynamic]Card_Row, c: int) {
	g := land.grid
	camp := c
	if _, live := cell_near(c, 16, livable); live >= 0 do camp = live
	byte :: proc(v: [3]f32) -> Colour { return {u8(clamp(v.r, 0, 1)*255), u8(clamp(v.g, 0, 1)*255), u8(clamp(v.b, 0, 1)*255), 255} }
	dangers := 0
	for row in SHORE {
		m := middle_of(g, camp if row.camp else c)
		p := point_at(m.x, m.y, LAND_CELL)
		well, lacks := len(row.well) > 0 && host(row.well, &p) > 0, host(row.lacks, &p) > 0
		if row.may && !lacks do continue
		dangers += int(row.may)
		figures := strings.builder_make(context.temp_allocator)   // the fields it is read from, with their figures, after the why
		seen: bit_set[Field]
		if !row.may do for windows in ([2][]Window{row.well, row.lacks}) do for w in windows do if f := FIELDS[w.field]; w.field not_in seen {   // what the land may do says its figure in its words
			seen += {w.field}
			name, _ := strings.replace_all(f.name, "-", " ", context.temp_allocator)
			fmt.sbprintf(&figures, "%s%s %.3g%s", " Here: " if strings.builder_len(figures) == 0 else "; ", name, f.at(&p), f.unit)
		}
		block := Colour{}
		if row.thing == "Rock" do block = byte(map_colour(Mat(int(FIELDS[.Rock].at(&p)))))
		append(k, Card_Row{strings.clone(row.thing), strings.clone(row.says(&p)), fmt.aprintf("%s%s%s", row.why, strings.to_string(figures), "." if strings.builder_len(figures) > 0 else ""), .Trouble if lacks && row.grave else .Caution if lacks else .Well if well else .None, block, false, strings.clone(row.named) if lacks else ""})
		if row.thing == "Rock" {   // and the bed under it, down to where a first hall would be dug
			m0 := Mat(int(FIELDS[.Rock].at(&p)))
			h := f64(land_at(land.z[0], land.n, p.x, p.z))
			under, deep := m0, 0
			for d := 2; d <= 40; d += 1 do if r := rock(p.x, h - f64(d) - 0.5, p.z, LAND_CELL); r != m0 {
				under, deep = r, d
				break
			}
			hard := MATERIALS[under].strength > TOOLS
			says := fmt.tprintf("%s, %d m down", mat_words(under), deep) if deep > 0 else "the same, 40 m and more"
			append(k, Card_Row{strings.clone("Under it"), strings.clone(says), fmt.aprintf("The next bed down under the surface bed, within 40 m: %s.", cut_words(under)), .Caution if hard else .None, byte(map_colour(under)) if deep > 0 else Colour{}, deep == 0, strings.clone("Rock too hard for the picks, under the surface") if hard else ""})
		}
	}
	if dangers == 0 do append(k, Card_Row{strings.clone("Dangers"), strings.clone("none the land shows"), strings.clone("No slide's lake stands above it, its ground has not slid, and it is no stream's fan."), .None, {}, true, ""})
}

// The landing chosen for an island, and how the boat comes to it.
Landed :: struct {
	row, cell:  int,       // the row that decided and the land cell it chose
	held:       int,       // shore cells the row holds on, of `shore` in all
	shores:     int,
	score:      f32,
	at:         [3]i32,    // the floor the party steps onto, in the world
	out:        [2]f64,    // the way the boat came from, a unit
	run:        f32,       // metres of open water along it
	camp:       [3]i32,    // the floor on ground to live on that the party gathers at
	misses:     [len(LANDINGS)]string,   // for each row before it, why it holds nowhere
	chosen:     bool,      // the expedition chose it, and not the rows (landing_near)
	asked:      [2]i32,    // the column of the world it asked for,
	off:        f32,       // and how far from it the boat could be brought in, metres
	shut:       bool,      // ground to live on lies near, and no way leads to it from the shore
}

// Choose the bound island's landing. The walk is asked for the floors there.
landing_choose :: proc(w: ^Walk) -> (l: Landed, ok: bool) {
	g := land.grid
	shore := shore_cells()
	l.shores = len(shore)
	Scored :: struct { s: f32, c: int }
	for row, r in LANDINGS {
		held := make([dynamic]Scored, context.temp_allocator)
		nearest, by := "", f32(-ANY)
		for c in shore {
			m := middle_of(g, c)
			p := point_at(m.x, m.y, LAND_CELL)
			if host(row.host, &p) > 0 do append(&held, Scored{host(row.likes, &p), c})
			else if len(held) == 0 do if words, b := edges(row.host, &p); b > by {
				nearest, by = fmt.aprintf("the nearest to it, at %.0f, %.0f: %s", m.x + f64(region.origin.x), m.y + f64(region.origin.y), words[0]), b
			}
		}
		slice.sort_by(held[:], proc(a, b: Scored) -> bool { return a.s > b.s || a.s == b.s && a.c < b.c })
		for cand, i in held {
			if i >= 60 do break
			if landing_take(w, &l, cand.c) {
				l.row, l.held, l.score = r, len(held), cand.s
				return l, true
			}
		}
		l.misses[r] = nearest if len(held) == 0 else fmt.aprintf("it holds on %d cells of shore, but a boat can come in to none of them", len(held))
	}
	return
}

// A landing at a cell of shore, if a boat can come in to it: the floor the party steps onto, the way
// the boat comes, and the floor on ground to live on beside it that the party gathers at.
landing_take :: proc(w: ^Walk, l: ^Landed, c: int) -> bool {
	at, out, run := landing_floor(w, c) or_return
	l.cell, l.at, l.out, l.run, l.camp = c, at, out, run, at
	if _, live := cell_near(c, 16, livable); live >= 0 {
		m := middle_of(land.grid, live)
		x, z := i32(math.floor(m.x)), i32(math.floor(m.y))
		y := i32(math.round(ground(m.x, m.y, 1).h))
		f := walk_near(w, x + region.origin.x, y, z + region.origin.y, 12, true)   // on soil, off the shore's stones, if any is near
		if f < 0 do f = walk_near(w, x + region.origin.x, y, z + region.origin.y, 6)
		if f >= 0 do l.camp = floor_block(w, f)
		// Where no way leads up to it from the shore, the party gathers where it stepped out.
		if f >= 0 && l.camp != at {
			way := make([dynamic][3]i32, context.temp_allocator)
			if _, why := walk_way(w, at, l.camp, &way, CAMP_BUILDS); why != .Way do l.camp, l.shut = at, true
			w.budget = ASKING
		}
	}
	return true
}
CAMP_BUILDS :: 48   // chunks of ground read to find the way from a landing to the ground beside it, before it is taken to have none

NEAR_SHORE :: 60   // cells of low shore, the nearest first, tried for one a boat can come in to

// The landing an expedition chose (E-1): the low shore nearest a column of the world that a boat
// can be brought in to. It is the cell asked for wherever a boat can come in there, which is nearly
// everywhere on a low shore; in a creek too narrow for it the boat lands at the creek's mouth.
landing_near :: proc(w: ^Walk, asked: [2]i32) -> (l: Landed, ok: bool) {
	g := land.grid
	x, z := f64(asked.x) + 0.5 - f64(region.origin.x), f64(asked.y) + 0.5 - f64(region.origin.y)
	Near :: struct { d: f64, c: int }
	near := make([dynamic]Near, context.temp_allocator)
	shore := shore_cells()
	for c in shore {
		m := middle_of(g, c)
		append(&near, Near{math.hypot(m.x - x, m.y - z), c})
	}
	slice.sort_by(near[:], proc(a, b: Near) -> bool { return a.d < b.d || a.d == b.d && a.c < b.c })
	tried := 0
	for n in near {
		if tried >= NEAR_SHORE do break
		row := landing_row(n.c)
		if row < 0 do continue
		tried += 1
		if landing_take(w, &l, n.c) {
			l.row, l.shores, l.chosen, l.asked = row, len(shore), true, asked
			l.off = f32(math.hypot(f64(l.at.x - asked.x), f64(l.at.z - asked.y)))
			return l, true
		}
	}
	return
}

// The floor a boat can be brought to in a shore cell: dry, beside the sea, the nearest the cell's
// middle that REACH_IN metres or more of open water lead to, with the way out along that water.
landing_floor :: proc(w: ^Walk, c: int) -> (at: [3]i32, out: [2]f64, run: f32, ok: bool) {
	m, o := middle_of(land.grid, c), region.origin
	wet :: proc(x, z: f64) -> bool { return ground(x, z, 1).h < SEA_SURFACE }
	Spot :: struct { d: i32, x, z: i32 }
	spots := make([dynamic]Spot, context.temp_allocator)
	for dz in i32(-10)..=10 do for dx in i32(-10)..=10 {
		x, z := i32(math.floor(m.x)) + dx, i32(math.floor(m.y)) + dz
		fx, fz := f64(x) + 0.5, f64(z) + 0.5
		if wet(fx, fz) || !(wet(fx + 1, fz) || wet(fx - 1, fz) || wet(fx, fz + 1) || wet(fx, fz - 1)) do continue
		append(&spots, Spot{dx*dx + dz*dz, x, z})
	}
	slice.sort_by(spots[:], proc(a, b: Spot) -> bool { return a.d < b.d || a.d == b.d && (a.z < b.z || a.z == b.z && a.x < b.x) })
	for s in spots {
		fx, fz := f64(s.x) + 0.5, f64(s.z) + 0.5
		f := walk_floor(w, s.x + o.x, i32(math.round(ground(fx, fz, 1).h)), s.z + o.y)
		if f < 0 || w.floors[f].wet > 0 do continue
		for b in 0..<16 {
			dir := [2]f64{math.sin(f64(b)*math.PI/8), -math.cos(f64(b)*math.PI/8)}
			clear := f32(0)
			for clear < 70 && wet(fx + dir.x*f64(clear + 1), fz + dir.y*f64(clear + 1)) do clear += 1
			if clear > run do out, run = dir, clear
		}
		if run >= REACH_IN do return floor_block(w, f), out, run, true
		run = 0
	}
	return
}

// The landing in sentences: which row decided and what it found there, as start-up and --why say it.
landing_words :: proc(l: Landed) {
	row := LANDINGS[l.row]
	m := middle_of(land.grid, l.cell)
	p := point_at(m.x, m.y, LAND_CELL)
	if l.chosen {
		fmt.printf("  the shore the expedition chose, at %d, %d", l.at.x, l.at.z)
		if l.off > 1.5*LAND_CELL do fmt.printf(", %.0f m from the %d, %d it asked for, the nearest a boat can be brought in to", l.off, l.asked.x, l.asked.y)
		fmt.printf(": %s", row.name if l.row < len(LANDINGS) - 1 else "an open shore, which no land shuts in with ground to live on beside it")
	} else {
		for r in 0..<l.row do fmt.printfln("  no %s on this island: %s", LANDINGS[r].name, l.misses[r])
		fmt.printf("  %s, at %d, %d: %s. It holds on %d of the island's %d cells of shore, and best here", row.name, l.at.x, l.at.z, row.why, l.held, l.shores)
	}
	for win in row.host {
		words, _ := window_words(win, &p)
		fmt.printf("; %s", words)
	}
	said: bit_set[Field]
	for win in row.host do said += {win.field}
	for win in row.likes do if f := FIELDS[win.field]; win.field not_in said do fmt.printf("; %s is %.2f%s (%s)", f.name, f.at(&p), f.unit, f.from)
	fmt.println(".")
}
