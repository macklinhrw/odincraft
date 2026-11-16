package main

import "core:fmt"
import "core:math"
import "core:slice"

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
}

// Choose the bound island's landing. The walk is asked for the floors there.
landing_choose :: proc(w: ^Walk) -> (l: Landed, ok: bool) {
	g, n := land.grid, land.n
	shore := make([dynamic]int, context.temp_allocator)
	for ci in g.order {
		c := int(ci)
		if c%n < 1 || c/n < 1 || c%n >= n - 1 || c/n >= n - 1 do continue
		beside := false
		for o in OFFSETS do beside ||= g.sea[c + o.y*n + o.x]
		if beside do append(&shore, c)
	}
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
			if at, out, run, found := landing_floor(w, cand.c); found {
				l.row, l.cell, l.held, l.score, l.at, l.out, l.run = r, cand.c, len(held), cand.s, at, out, run
				l.camp = at
				if _, live := cell_near(cand.c, 16, livable); live >= 0 {
					m := middle_of(g, live)
					x, z := i32(math.floor(m.x)), i32(math.floor(m.y))
					y := i32(math.round(ground(m.x, m.y, 1).h))
					f := walk_near(w, x + region.origin.x, y, z + region.origin.y, 12, true)   // on soil, off the shore's stones, if any is near
					if f < 0 do f = walk_near(w, x + region.origin.x, y, z + region.origin.y, 6)
					if f >= 0 do l.camp = floor_block(w, f)
				}
				return l, true
			}
		}
		l.misses[r] = nearest if len(held) == 0 else fmt.aprintf("it holds on %d cells of shore, but a boat can come in to none of them", len(held))
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
	for r in 0..<l.row do fmt.printfln("  no %s on this island: %s", LANDINGS[r].name, l.misses[r])
	fmt.printf("  %s, at %d, %d: %s. It holds on %d of the island's %d cells of shore, and best here", row.name, l.at.x, l.at.z, row.why, l.held, l.shores)
	for win in row.host {
		words, _ := window_words(win, &p)
		fmt.printf("; %s", words)
	}
	said: bit_set[Field]
	for win in row.host do said += {win.field}
	for win in row.likes do if f := FIELDS[win.field]; win.field not_in said do fmt.printf("; %s is %.2f%s (%s)", f.name, f.at(&p), f.unit, f.from)
	fmt.println(".")
}
