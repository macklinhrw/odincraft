package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

// Food (plan.md, P4): what a dwarf eats is what the island bears. Nothing here is made for the
// screen: a food is a row that names a ground plant of GROUND_PLANTS, a tree of SPECIES or a fish of
// CREATURES, and it is found where that plant stands, that tree grows and that fish lives, by the
// rules that put them there. The row adds what a person takes of it, in which days of the sun's year
// it can be taken, how much one plant, tree or catch gives, how far that goes, how long the taking
// is, and how long before the same plant or water gives again.
//
// The flora is the warm-temperate wood of southern Japan (interesting-world/notes/real-vegetation.md),
// and what is eaten of it is what people there gather: the young shoots of bracken (warabi), of
// itadori and of dwarf bamboo in spring, the stems of wild rice (makomo) in autumn, and the nuts of
// the shii, which were a staple before rice. The seasons are from memory of those calendars, to be
// checked against a source when the floras are (plan.md, N5). The fish are the two the streams have:
// ayu, which run from April to November, and the goby, which is small and there all year.
// What grows here and is not eaten has no row: the tabu's fruit is the birds', manryō's berries are
// not food, and the camellia's seed gives oil, which is P5's.
//
// Food spoils (plan.md, "Winter's food"): each kind lies good for its row's days in mild air, longer
// in the cold and less in the heat (spoil_rate), and then is gone. What is to be eaten in a lean
// season is dried on a rack (MAKES, bench.odin), or is a nut, which keeps as it is.
//
// A thing gathered or caught is a thing lying in a cell (goods.odin): its kind is a material that is
// no block's (.Food), so it is carried, stored and counted as stone and timber are.

Food_Kind :: enum u8 { Bracken, Itadori, Bamboo, Wild_Rice, Shii_Nuts, Ayu, Goby, Provisions, Dried_Bracken, Dried_Itadori, Dried_Bamboo, Dried_Wild_Rice, Dried_Ayu, Dried_Goby }
Source :: enum u8 { Plant, Tree, Fish, Brought, Made }   // Brought: what the party came with (PROVISIONS), which no land bears; Made: what the hold makes of another food, by a row of MAKES (bench.odin)
Food :: struct {
	name:   string,       // as the stores say it
	one:    string,       // what one taking is: "a bracken's shoots"
	thing:  Mat,
	from:   Source,
	plant:  Plant_Kind,
	tree:   Tree_Kind,
	fish:   string,       // its row of CREATURES, by name
	season: [2]f32,       // the days of the sun's year it is taken in; a fish's are its own row's
	gives:  [2]i32,       // things one plant or one catch gives; of a tree, the fewest and the most, by its height
	feeds:  f32,          // the share of a day's hunger one thing stills (WANTS)
	work:   f32,          // seconds a common hand takes over one plant, one tree or one catch
	again:  int,          // days before the same plant, tree or water gives again
	keeps:  f32,          // days it lies before it spoils, in mild air (MILD); none for what does not spoil
	comes:  string,       // its season in words
	why:    string,
}
// RimWorld's berry bush gives 10 berries of 0.05 nutrition for 250 ticks of work, four seconds, and
// bears again in about four days (Plants_Wild_Temperate.xml, Plant_Berry: harvestYield 10, harvestWork
// 250, growDays 6 from 0.3); a pawn uses 1.6 nutrition a day (Need_Food.BaseFoodFallPerTick), so a bush
// is a third of a day. Here a plant's shoots are a tenth of a day and a wood's floor has a plant on
// one column in three, so a drag of ten by ten feeds a dwarf two or three days. A shii of 16 m drops
// eight handfuls, a day and a third. Shoots and nuts come once a year: a plant taken bears next year.
// A catch takes twenty seconds; fished water holds fish again in four days, as others move in.
//
// How long each keeps (colony-sim-reference.md, section 16). RimWorld's raw meat and fish rot in 2
// days of its 60 in a year, its berries in 14, its potatoes in 30, rice in 40 and corn in 60, a
// cooked meal in 4, and pemmican in 70 (CompProperties_Rottable.daysToRotStart in each ThingDef).
// Here, of a year of 48 days: a fish caught is good for two days, shoots and stems for five, and
// nuts, which keep in their shells, for thirty; what was dried, and what the party brought dried and
// salted, does not spoil. So a spring's shoots are not eaten in winter unless they were dried.
FOODS := [Food_Kind]Food{
	.Bracken   = {"bracken shoots", "a bracken's shoots", .Bracken_Shoots, .Plant, .Bracken, .Tabu, "", {75, 140}, {1, 1}, 0.1, 4, YEAR_DAYS, 5, "spring",
		"the young shoots of bracken, picked before they open and eaten when the bitterness is soaked out of them"},
	.Itadori   = {"itadori shoots", "an itadori's shoots", .Itadori_Shoots, .Plant, .Knotweed, .Tabu, "", {70, 125}, {1, 1}, 0.1, 4, YEAR_DAYS, 5, "spring",
		"the thick young shoots of itadori, sour and full of water, snapped off as they come up on raw ground"},
	.Bamboo    = {"bamboo shoots", "a bamboo's shoots", .Bamboo_Shoots, .Plant, .Bamboo, .Tabu, "", {115, 175}, {1, 1}, 0.15, 5, YEAR_DAYS, 5, "late spring",
		"the shoots of dwarf bamboo, dug where they break the ground at the edge of its patches"},
	.Wild_Rice = {"wild rice stems", "a wild rice's stems", .Wild_Rice, .Plant, .Sedge, .Tabu, "", {245, 310}, {1, 1}, 0.12, 5, YEAR_DAYS, 5, "autumn",
		"the swollen stems of wild rice, cut in the wet ground above the reeds"},
	.Shii_Nuts = {"shii nuts", "a shii's nuts", .Shii_Nuts, .Tree, .Reed, .Shii, "", {275, 345}, {3, 9}, 0.2, 30, YEAR_DAYS, 30, "autumn",
		"the small sweet nuts the shii drops, gathered from under it and eaten as they are; in their shells they keep through a winter"},
	.Ayu       = {"ayu", "an ayu", .Ayu, .Fish, .Reed, .Tabu, "ayu", {}, {1, 1}, 0.4, 20, 4, 2, "spring to autumn",
		"a fish as long as a hand, taken with a net where it holds over the stones"},
	.Goby      = {"gobies", "a handful of gobies", .Goby, .Fish, .Reed, .Tabu, "yoshinobori", {}, {2, 2}, 0.05, 20, 4, 2, "all year",
		"small gobies picked off the bed: poor eating, and there when nothing else is"},
	.Provisions = {"provisions", "a sack of provisions", .Provisions, .Brought, .Reed, .Tabu, "", {-1, -1}, {1, 1}, 0.5, 0, 0, 0, "",
		"dried and salted food the party brought in the boat: a sack is half a day's eating for one"},
	// What is made of them to keep (MAKES, bench.odin): each feeds as what it was made of.
	.Dried_Bracken   = {"dried bracken", "", .Dried_Bracken, .Made, .Reed, .Tabu, "", {-1, -1}, {1, 1}, 0.1, 0, 0, 0, "",
		"bracken shoots dried on a rack until they are dark and hard, to be soaked again and eaten in a lean season"},
	.Dried_Itadori   = {"dried itadori", "", .Dried_Itadori, .Made, .Reed, .Tabu, "", {-1, -1}, {1, 1}, 0.1, 0, 0, 0, "",
		"itadori shoots split and dried on a rack"},
	.Dried_Bamboo    = {"dried bamboo shoots", "", .Dried_Bamboo, .Made, .Reed, .Tabu, "", {-1, -1}, {1, 1}, 0.15, 0, 0, 0, "",
		"bamboo shoots sliced and dried on a rack"},
	.Dried_Wild_Rice = {"dried wild rice stems", "", .Dried_Wild_Rice, .Made, .Reed, .Tabu, "", {-1, -1}, {1, 1}, 0.12, 0, 0, 0, "",
		"the stems of wild rice sliced and dried on a rack"},
	.Dried_Ayu       = {"dried ayu", "", .Dried_Ayu, .Made, .Reed, .Tabu, "", {-1, -1}, {1, 1}, 0.4, 0, 0, 0, "",
		"ayu opened and dried hard on a rack, over the smoke of a fire where one burns by it"},
	.Dried_Goby      = {"dried gobies", "", .Dried_Goby, .Made, .Reed, .Tabu, "", {-1, -1}, {1, 1}, 0.05, 0, 0, 0, "",
		"small gobies dried whole on a rack"},
}
FOOD :: bit_set[Trait]{.Food}

food_of :: proc(m: Mat) -> Food_Kind {
	for row, k in FOODS do if row.thing == m do return k
	return .Bracken
}

// A fish food's row of CREATURES, or -1.
food_fish :: proc(row: ^Food) -> int {
	for c, k in CREATURES do if c.name == row.fish do return k
	return -1
}

// The days of the sun's year a food is taken in.
food_season :: proc(row: ^Food) -> [2]f32 {
	if row.from == .Fish do if k := food_fish(row); k >= 0 do return CREATURES[k].season
	return row.season
}

// Whether a food is taken on a day of the sun's year. A season may run over the year's end.
in_season :: proc(row: ^Food, sun: f32) -> bool {
	s := food_season(row)
	return sun >= s[0] && sun <= s[1] if s[0] <= s[1] else sun >= s[0] || sun <= s[1]
}

// ---- what a column bears --------------------------------------------------------------------------

// One thing an order to gather or to fish marks: the food, the cell the mark is on (a plant's own
// cell over its ground, a tree's foot, the cell the water's top is in), and what taking it gives.
Bearing :: struct { food: Food_Kind, at: [3]i32, n: i32, tall: i32 }
// Why a box bears nothing, or less than stands in it: what bears in another season, and what was taken already.
Barren :: struct { later: [Food_Kind]int, taken: int, water, fishless: int }

// The fish in the water at a point of the island bound: the kinds as bits by their rows of CREATURES,
// whether it is the pool under a fall, where they crowd, and whether the point is in a stream's
// channel or a lake at all.
water_fish :: proc(x, z: f64) -> (bits: u8, pool, ok: bool) {
	if r, in_reach := river_near(f32(x), f32(z)); in_reach && r.d <= r.half + 1 {
		o := land_corner()
		near, by := -1, f32(1e9)
		for id in rivers.buckets[int(z - o.y)/BUCKET*rivers.side + int(x - o.x)/BUCKET] {
			s := rivers.segments[id]
			ab, ap := s.b - s.a, [2]f32{f32(x), f32(z)} - s.a
			if d := linalg.length(ap - ab*clamp(linalg.dot(ap, ab)/max(linalg.dot(ab, ab), 1e-6), 0, 1)); d < by do near, by = int(id), d
		}
		if near >= 0 do return fauna.fish[near], rivers.segments[near].pool > 0, true
	}
	if l := int(land.lake[land_cell(x, z)]); l > 0 do return fauna.lakes[l - 1] or_else 0, false, true
	return
}

// What an order to gather (plants and trees) or to fish (water) would mark in the columns of a box,
// on a day of the sun's year: every ground plant and tree there that a row of FOODS takes in that
// season, or every square metre of fresh water a fish of a row stands in, that was not taken within
// the row's days and whose ground stands as the generator made it. This is the one rule: the hold
// asks it of its own blocks and the frame of the blocks it draws, so what is shown under the pointer
// is what will be marked. The island is bound.
bearing_of :: proc(work: Work, a, b: [3]i32, sun: f32, today: int, src: Blocks, taken: ^map[[2]i32]int, out: ^[dynamic]Bearing, barren: ^Barren = nil) {
	lo, hi := box_of(a, b)
	if (i64(hi.x - lo.x) + 1)*(i64(hi.z - lo.z) + 1) > ORDER_MOST do return
	ox, oz := region.origin.x, region.origin.y
	fresh_since :: proc(taken: ^map[[2]i32]int, col: [2]i32, today: int, row: ^Food) -> bool {
		day, ok := taken[col]
		return !ok || today - day >= row.again
	}
	if work == .Fish {
		for z in lo.z..=hi.z do for x in lo.x..=hi.x {
			fx, fz := f64(x - ox) + 0.5, f64(z - oz) + 0.5
			g := ground(fx, fz, 1)
			if g.water <= g.h + 0.05 || g.water <= SEA_SURFACE + 0.05 do continue   // dry, or the sea's own water
			if barren != nil do barren.water += 1
			bits, pool, ok := water_fish(fx, fz)
			if !ok || bits == 0 {
				if barren != nil do barren.fishless += 1
				continue
			}
			for &row, kind in FOODS do if row.from == .Fish {
				k := food_fish(&row)
				if k < 0 || bits >> uint(k) & 1 == 0 || hash01(x, z, seed + 840 + u32(k)) >= CREATURES[k].number[0]*(3 if pool else 1) do continue
				if !in_season(&row, sun) {
					if barren != nil do barren.later[kind] += 1
					continue
				}
				if !fresh_since(taken, {x, z}, today, &row) {
					if barren != nil do barren.taken += 1
					break
				}
				append(out, Bearing{kind, {x, max(i32(math.round(g.h)), i32(math.floor(g.water - 0.001))), z}, row.gives[0], 0})
				break
			}
		}
		return
	}
	for z in lo.z..=hi.z do for x in lo.x..=hi.x {
		fx, fz := f64(x - ox) + 0.5, f64(z - oz) + 0.5
		p: Point
		g, m, plants := surface_at(fx, fz, 1, &p)
		kind, ok := plant_at(&p, m, plants)
		if !ok || g.water - g.h > GROUND_PLANTS[kind].wet do continue
		for &row, food in FOODS do if row.from == .Plant && row.plant == kind {
			cell := [3]i32{x, i32(math.round(g.h)), z}
			if src.at(src.data, cell) != .Air || !ground_at(src, cell - {0, 1, 0}) do break   // dug away, or built over
			if !in_season(&row, sun) {
				if barren != nil do barren.later[food] += 1
				break
			}
			if !fresh_since(taken, {x, z}, today, &row) {
				if barren != nil do barren.taken += 1
				break
			}
			append(out, Bearing{food, cell, row.gives[0], 0})
			break
		}
	}
	trees := make([dynamic]Tree, context.temp_allocator)
	trees_standing(lo.x - ox, lo.z - oz, hi.x - ox, hi.z - oz, &trees)
	for t in trees do for &row, food in FOODS do if row.from == .Tree && row.tree == t.kind && (t.form == .Canopy || t.form == .Between) {   // a grown tree: the small ones under the canopy bear nothing yet
		foot := [3]i32{t.x + ox, t.base, t.z + oz}
		if !is(src.at(src.data, foot), PLANT_BLOCKS) do break   // felled
		if !in_season(&row, sun) {
			if barren != nil do barren.later[food] += 1
			break
		}
		if !fresh_since(taken, {foot.x, foot.z}, today, &row) {
			if barren != nil do barren.taken += 1
			break
		}
		append(out, Bearing{food, foot, clamp(t.height/2, row.gives[0], row.gives[1]), t.height})
		break
	}
}

// What a box bears, counted by kind, in words: "9 bracken shoots and 3 itadori shoots".
bearing_words :: proc(found: []Bearing, things := true) -> string {
	n: [Food_Kind]int
	for f in found do n[f.food] += int(f.n) if things else 1
	b := strings.builder_make(context.temp_allocator)
	kinds, said := 0, 0
	for count in n do kinds += int(count > 0)
	for count, food in n do if count > 0 {
		fmt.sbprintf(&b, "%s%d %s", "" if said == 0 else " and " if said == kinds - 1 else ", ", count, FOODS[food].name)
		said += 1
	}
	return strings.to_string(b)
}

// Why a box bears nothing now, in a sentence for the tool's line and the log.
barren_words :: proc(work: Work, barren: Barren) -> string {
	later, most := 0, Food_Kind.Bracken
	for n, food in barren.later {
		later += n
		if n > barren.later[most] do most = food
	}
	if later > 0 do return fmt.tprintf("Nothing to %s here now: %s %s in %s.", "catch" if work == .Fish else "gather", FOODS[most].name, "run" if FOODS[most].from == .Fish else "come", FOODS[most].comes)
	if barren.taken > 0 do return "What was here has been taken: it bears again in its time." if work != .Fish else "This water was fished: it holds fish again in a few days."
	if work == .Fish do return "No fresh water here to fish." if barren.water == 0 else "No fish live in this water." if barren.fishless == barren.water else "No fish stand in this stretch: mark more of the stream."
	return "Nothing here bears food a dwarf eats."
}

// ---- what the land round a place bears through the year ---------------------------------------------

// What the ground within FORAGE of a land cell and its water bear in each season, as the days one
// dwarf could eat of it, and which foods: read from the cells' communities, their ground and their
// streams by the rows that put the plants, trees and fish there. It is the measure a landing's card
// and the hold's first word are read from (SHORE, landing.odin; larder_words).
FORAGE   :: 300    // metres a dwarf walks for food without being sent: a short walk (WALK, landing.odin)
LIVES_ON :: 21.0   // days of one dwarf's eating a season must bear for a party to live on it: seven for three days, the rest being stored or walked farther for
Larder :: struct { days: [4]f32, foods: [4]bit_set[Food_Kind] }

@(thread_local) larder_for: struct { island: ^Formed, cell: int, larder: Larder }   // the last one asked, since a card asks the same cell several times

larder_round :: proc(c: int) -> (l: Larder) {
	if larder_for.island == here && larder_for.cell == c && here != nil do return larder_for.larder
	n, g := land.n, land.grid
	r := FORAGE/LAND_CELL
	eats := f32(WANTS[.Food].falls)
	MIDS := [4][3]f32{{95, 125, 155}, {185, 215, 245}, {275, 305, 335}, {5, 35, 65}}   // days of the sun's year early, in the middle and late in each season
	for dy in -r..=r do for dx in -r..=r {
		x, y := c%n + dx, c/n + dy
		if x < 0 || y < 0 || x >= n || y >= n || dx*dx + dy*dy > r*r || g.sea[y*n + x] do continue
		things := cell_bears(y*n + x)
		for &row, food in FOODS do if things[food] > 0 do for mids, s in MIDS {
			share := f32(0)
			for day in mids do share += 1.0/3 if in_season(&row, day) else 0
			if share > 0 {
				l.days[s] += things[food]*row.feeds*share/eats*(f32(SEASON_DAYS)/f32(row.again) if row.again < SEASON_DAYS else 1)   // fished water fills again within the season
				l.foods[s] += {food}
			}
		}
	}
	larder_for = {here, c, l}
	return
}

// How many things of each food a cell of the land bears when it is in season, as the rows that put
// the plants, the trees and the fish there say: the measure of a place, and where a hungry dwarf looks.
cell_bears :: proc(k: int) -> (things: [Food_Kind]f32) {
	m := middle_of(land.grid, k)
	p := Point{x = m.x, z = m.y, cell = LAND_CELL}
	_, cover, plants := surface_at(m.x, m.y, LAND_CELL, &p)
	com, grows := plants.?
	bits := u8(0)
	if fresh(k) do bits, _, _ = water_fish_near(m.x, m.y)
	for &row, food in FOODS do switch row.from {
	case .Plant:
		gp := GROUND_PLANTS[row.plant]
		if !is(cover, gp.on) || card(gp.within) > 0 && (!grows || com not_in gp.within) do continue
		things[food] = gp.share*0.8*host(gp.host, &p)*LAND_CELL*LAND_CELL*f32(row.gives[0])   // 0.8: the share its clumps leave it (plant_at)
	case .Tree:
		if !grows do continue
		squares := f32(LAND_CELL*LAND_CELL)/36
		things[food] = squares*COMMUNITIES[com].density*COMMUNITIES[com].trees[row.tree]*0.5*f32(row.gives[0] + row.gives[1])/2   // half of them grown enough to bear
	case .Brought, .Made:   // no land bears it
	case .Fish:
		f := food_fish(&row)
		if f < 0 || bits >> uint(f) & 1 == 0 do continue
		things[food] = CREATURES[f].number[0]*LAND_CELL*3*f32(row.gives[0])   // a stream's channel, three metres wide, across the cell
	}
	return
}

// The fish of the stream nearest a point within a land cell of it, as water_fish gives them.
water_fish_near :: proc(x, z: f64) -> (bits: u8, pool, ok: bool) {
	if l := int(land.lake[land_cell(x, z)]); l > 0 do return fauna.lakes[l - 1] or_else 0, false, true
	o := land_corner()
	bx, bz := int(x - o.x)/BUCKET, int(z - o.y)/BUCKET
	if x < o.x || z < o.y || bx >= rivers.side || bz >= rivers.side do return
	near, by := -1, f32(1.5*LAND_CELL)
	for id in rivers.buckets[bz*rivers.side + bx] {
		s := rivers.segments[id]
		ab, ap := s.b - s.a, [2]f32{f32(x), f32(z)} - s.a
		if d := linalg.length(ap - ab*clamp(linalg.dot(ap, ab)/max(linalg.dot(ab, ab), 1e-6), 0, 1)); d < by do near, by = int(id), d
	}
	if near < 0 do return
	return fauna.fish[near], rivers.segments[near].pool > 0, true
}

// How many of the four seasons the land within a walk of a cell bears food a party could live on.
food_seasons :: proc(c: int) -> (n: int) {
	l := larder_round(c)
	for days in l.days do n += int(days >= LIVES_ON)
	return
}

// A larder in a line for a card: the seasons that bear enough, and the lean ones.
larder_says :: proc(l: Larder) -> string {
	good := make([dynamic]string, context.temp_allocator)
	for days, s in l.days do if days >= LIVES_ON do append(&good, SEASONS[s])
	switch len(good) {
	case 0: return "none a party could live on"
	case 4: return "through the year"
	}
	b := strings.builder_make(context.temp_allocator)
	for s, i in good do fmt.sbprintf(&b, "%s%s", "" if i == 0 else " and " if i == len(good) - 1 else ", ", s)
	return fmt.tprintf("in %s", strings.to_string(b))
}

// A larder in sentences, season by season, for the hold's first word and a card's why.
larder_words :: proc(l: Larder) -> string {
	b := strings.builder_make(context.temp_allocator)
	for days, s in l.days {
		if s > 0 do fmt.sbprint(&b, " ")
		if card(l.foods[s]) == 0 {
			fmt.sbprintf(&b, "In %s nothing.", SEASONS[s])
			continue
		}
		fmt.sbprintf(&b, "In %s ", SEASONS[s])
		said, kinds := 0, card(l.foods[s])
		for food in Food_Kind do if food in l.foods[s] {
			fmt.sbprintf(&b, "%s%s", "" if said == 0 else " and " if said == kinds - 1 else ", ", FOODS[food].name)
			said += 1
		}
		fmt.sbprintf(&b, ": %s.", "plenty" if days >= 10*LIVES_ON else "enough for a party" if days >= LIVES_ON else "too little to live on")
	}
	return strings.to_string(b)
}
