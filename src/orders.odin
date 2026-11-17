package main

import "core:fmt"
import "core:math"
import "core:strings"
import "core:sync"
import "core:time"

// Orders (plan.md, P3; docs/adr/0011): what the player asks of the hold beyond where to stand. An
// order marks blocks of the world: ground to dig, trees to fell, blocks to build. The marks are the
// hold's, and the dwarves take the work themselves: each idle dwarf chooses a marked block near it,
// walks to a floor it can work from, works for a time the material sets, and the block changes.
// Nobody is assigned by hand, and nothing counts on seven.
//
// An order is named for what the player gets, as in Dwarf Fortress (dig, stairs up and down,
// channel: df-structures, tile_dig_designation) and RimWorld (Designator_Mine), and marks by area
// on one level, as both do (DesignationDragger.DragRect keeps the level of the cell the drag began
// on). In a world of one-metre blocks, where a dwarf stands in two blocks of height and steps one:
//   dig out      every block of ground in a rectangle, from the level the drag began on down as
//                many blocks as the player set (two for a space to stand in). Into a hillside it
//                is a room under the hill; on flat ground a pit or a trench;
//   stair down   a block down for each block along, from the block the drag began on, the way it
//                was dragged, with room over each step to walk it; stair up, the same rising
//                through the ground, its steps left standing;
//   wall         one or two blocks high, standing on the ground along the line dragged, which it
//                follows where the ground steps; floor, one layer at the level the drag began on,
//                which over a space is its roof; a built stair, up a block a column.
// An order marks what the player dragged and nothing more. Blocks no floor reaches wait for a way
// to them, which is the player's to mark: a stair, or a passage from ground that is there.
//
// A dwarf works a block beside it, at its feet, its head, a block over or a block under them, or
// right over its head; and one two under or over in the next column where the block between is open,
// so the last step of a pit is dug from its rim.
//
// No dwarf is shut in by the work. Before a block is dug whose top a dwarf could stand on, and
// before any is laid, the dwarves standing in small closed ground beside it are counted (pockets);
// the change is made and they are counted again; if there are more, the change is taken back and
// the mark waits. So a pit keeps its last step until everyone is out of it, and that step is dug
// from above. A dwarf shut in by anything else says so, and a stair dug or built to it lets it out.
//
// What is dug or felled goes to the hold's store as a count by kind: rock by the kind of rock it
// is, in whatever form it lay; timber by the tree's kind; earth and sand are thrown aside. Building
// takes from the store. Timber is laid as a block of its own, sawn, which is no tree's.
//
// An orders file gives each as a line (hold.odin has the rest):
//   dig out x y z x y z               every block of ground in the box between two blocks
//   dig stair-down|stair-up x y z x y z   from the first block toward the second, as wide as the box is across (the tool gives one wide)
//   fell x y z x y z                  every tree whose trunk stands in the box's columns
//   build wall|floor|stair stone|timber x y z x y z   a wall as high as the box, on the ground of its columns
//   build fire timber x y z x y z     a fire, on the block the box begins on
//   build roof stone|timber x y z x y z   one layer over the level of the block the box begins on: begun on a wall's top, the roof that lies on the walls
//   build rack timber x y z x y z     a drying rack in each place a dwarf could stand in the box's columns (bench.odin)
//   unmark x y z x y z                take back every mark in the box's columns

Work  :: enum u8 { Dig, Fell, Build, Gather, Fish }
Plan :: enum u8 { Out, Down, Up, Wall, Floor, Stair, Fire, Roof, Rack }   // Fire: no block is laid: a fire is laid and lit in the cell (shelter.odin); Rack: nor here: a bench is built in each cell (bench.odin)
Stuff :: enum u8 { Stone, Timber }

// A kind of work is a row: what it is called, whose trade it is, and how much faster those hands are.
Work_Row :: struct {
	name, doing, done: string,
	hands:             [2]string,   // the trades whose work it is; for building, of stone and of timber
	quick:             f32,
}
// RimWorld's work speeds run from 0.04 with no skill by 0.12 a level (Stats_Pawns_WorkGeneral.xml,
// MiningSpeed): 1.0 at level 8, the common hand, and 1.48 at level 12, a trade's.
WORKS := [Work]Work_Row{
	.Dig   = {"dig", "digging", "dug", {"miner", "miner"}, 1.5},
	.Fell  = {"fell", "felling", "felled", {"woodcutter", "carpenter"}, 1.5},
	.Build = {"build", "building", "built", {"mason", "carpenter"}, 1.5},
	// What bears food and what swims (food.odin): the grower's and the cook's hands know a plant; the fisher's the water.
	.Gather = {"gather", "gathering", "gathered", {"grower", "cook"}, 1.5},
	.Fish   = {"fish", "fishing", "fished", {"fisher", "fisher"}, 1.5},
}
PLANS := [Plan]string{.Out = "out", .Down = "stair-down", .Up = "stair-up", .Wall = "wall", .Floor = "floor", .Stair = "stair", .Fire = "fire", .Roof = "roof", .Rack = "rack"}
STUFFS := [Stuff]string{.Stone = "stone", .Timber = "timber"}

// How long work takes, from RimWorld's figures at its common speed of work (JobDriver_Mine: a pick
// strikes every 100 ticks of 60 a second for 80 of a rock's hit points, sandstone's 400 to granite's
// 900 in Various_Stone.xml, so 8 to 20 s for a cell as high as two of our blocks; Plants_Bases.xml:
// a tree is 800 ticks of work, 13 s; Buildings_Structure.xml: a wall is 135 ticks times 0.7 for
// wood and 5 to 6 for stone, for a cell two of our blocks high).
TOOLS      :: 0.8    // the strongest rock the party's picks cut (MATERIALS.strength); harder waits for better tools (P5)
DIG_BASE   :: 1.5    // seconds a common hand takes over a block of earth or loose rock
DIG_ROCK   :: 11.0   // and more over solid rock, by its strength: 4.4 s for mudstone, 5.2 for breccia, 9.8 for basalt
FELL_BASE  :: 4.0    // seconds over a tree, and for each metre of its height: 13.6 s for one of 12 m
FELL_TALL  :: 0.8
LAY_STONE  :: 5.0    // seconds to lay a block of stone
LAY_TIMBER :: 1.5    // and of timber
POCKET     :: 3000   // floors of joined ground under which a place is a pit a dwarf can be shut in
BASKET_REACH :: 16   // steps within which a gatherer with food in its arms takes more of the same before it carries it in
LOOKS      :: 4      // dwarves that may look for work in one tick
TRIES      :: 24     // marks a dwarf looks at, the nearest first, before it rests
REST       :: 10     // ticks a dwarf that found no work waits before it looks again
AGAIN      :: 20     // ticks before a mark that could not be worked is looked at again
ORDER_MOST :: 8000   // blocks one order may mark

// Why a mark is not being worked, as the hold last found it.
Waits :: enum u8 { None, Front, No_Way, No_Room, Too_Hard, Rooted, No_Stuff, Loose, Stood_On, Shuts_In, Way_Out }
// (No_Stuff: the stone or timber for a block has not been brought to it; goods.odin.)
WAITS := [Waits]string{
	.None     = "",
	.Front    = "the blocks in front are dug first",
	.No_Way   = "no dwarf has a way to them",
	.No_Room  = "the places to work them from are taken",
	.Too_Hard = "their rock is too hard for the party's picks",
	.Rooted   = "a tree stands on them, and is felled first",
	.No_Stuff = "their stone or timber has not been brought",
	.Loose    = "nothing lies beside them to lay them against",
	.Stood_On = "a dwarf stands in the way",
	.Shuts_In = "the work would shut a dwarf in",
	.Way_Out  = "they are the last step out of a pit",
}

Mark :: struct {
	at:    [3]i32,      // the block; of a tree, its foot
	site:  int,
	work:  Work,
	taker: int,         // the dwarf that has taken it, or -1
	wait:  Waits,
	tried: int,         // the tick it was last found unworkable
	as_of: int,         // and, of a last step out of a pit, how many changes the ground had seen then (Hold.ground)
	by:    int,         // and by which dwarf, where the cause is that dwarf's own: no way, or its places taken. Others still try it
	tall:  i32,         // a tree's height
	tree:  Tree_Kind,
	food:  Food_Kind,   // to gather or to fish: what it gives, and how many (food.odin)
	n:     i32,
}
Got :: struct { mat: Mat, n: int }
Site :: struct {
	work:        Work,
	shape:       Plan,
	stuff:       Stuff,
	lo, hi:      [3]i32,            // the box its marks lie in
	a, b:        [3]i32,            // as it was ordered
	total, left: int,
	place, name, thing: string,
	tally:       [dynamic]int,      // what each dwarf did of it
	got:         [dynamic]Got,      // what it gave the store
	joined:      [dynamic]bool,     // who has been said to take it up
	brought:     [dynamic]Mat,      // to build: the stuff that lies at it, brought and not yet laid (goods.odin)
	coming:      int,               // and what dwarves are on their way with
	promised:    int,               // of what lies at it, what marks in hand will use
	down:        bool,              // it takes built blocks down
	steps:       int,               // blocks of it left standing, as the way out of the pit it dug
	behind:      int,               // and blocks left with them that no floor reaches while they stand
	over:        bool,
}

// What the frame may know of the orders: each one with work left and what it waits for, the boxes
// of ground still to dig, and the trees to fell and blocks to lay.
Site_Seen :: struct {
	id:          int,
	work:        Work,
	shape:       Plan,
	stuff:       Stuff,
	lo, hi:      [3]i32,
	total, left: int,
	have, coming: int,          // to build: blocks' worth of stuff that lies at it, and that is on its way
	busy:        int,           // marks a dwarf has taken
	waits:       [Waits]int,    // and the rest, by what they wait for
	place:       string,
}
Tint :: struct { lo, hi: [3]i32, site: int }
Ghost :: struct { at: [3]i32, work: Work, stuff: Stuff, tall: i32, site: int }

// ---- shapes ---------------------------------------------------------------------------------

// Where an order's blocks are asked after: the dwarves' world asks its own ground, the frame the
// world it draws. `floor` says whether a dwarf can stand with its feet in a cell today: ground under
// it, two blocks of air, and no more water than it wades.
Blocks :: struct { at: proc(data: rawptr, b: [3]i32) -> Mat, floor: proc(data: rawptr, b: [3]i32) -> bool, data: rawptr }

// A stair's run: the axis it lies along (0 east, 2 south), which way it goes from where the drag began, and its steps.
stair_run :: proc(a, b: [3]i32) -> (axis: int, way, steps: i32) {
	axis = 0 if abs(b.x - a.x) >= abs(b.z - a.z) else 2
	return axis, -1 if b[axis] < a[axis] else 1, abs(b[axis] - a[axis]) + 1
}

// The boxes an order to dig covers, as geometry: the box itself, or a stair's steps, a box each, three
// blocks high: down, the block the drag began on is the first step's; up, the step over it is.
dig_boxes :: proc(shape: Plan, a, b: [3]i32, out: ^[dynamic][2][3]i32) {
	lo, hi := box_of(a, b)
	if shape != .Down && shape != .Up {
		append(out, [2][3]i32{lo, hi})
		return
	}
	axis, way, steps := stair_run(a, b)
	for i in 0..<steps {
		l, h := lo, hi
		l[axis] = a[axis] + way*i
		h[axis] = l[axis]
		if shape == .Down do l.y, h.y = a.y - i, a.y - i + 2
		else do l.y, h.y = a.y + i + 1, a.y + i + 3
		append(out, [2][3]i32{l, h})
	}
}

// What a dwarf digs, of the blocks as they stand: ground, and no plant's.
ground_at :: proc(src: Blocks, c: [3]i32) -> bool { m := src.at(src.data, c); return m != .Air && !is(m, PLANT_BLOCKS) }

// Whether a dwarf could stand with its feet in a cell today.
stands_at :: proc(src: Blocks, c: [3]i32) -> bool { return src.floor(src.data, c) }

// The blocks an order marks, of the blocks as they stand: to dig, the ground in its boxes that is
// no plant's, and no block besides; to build, the open cells of its shape.
cells_of :: proc(work: Work, shape: Plan, a, b: [3]i32, src: Blocks, out: ^[dynamic][3]i32) {
	open :: proc(src: Blocks, c: [3]i32) -> bool { m := src.at(src.data, c); return m == .Air || is(m, LEAVES) }
	lo, hi := box_of(a, b)
	if (i64(hi.x - lo.x) + 1)*(i64(hi.z - lo.z) + 1)*(i64(hi.y - lo.y) + 3) > 8*ORDER_MOST do return
	switch work {
	case .Dig:
		boxes := make([dynamic][2][3]i32, context.temp_allocator)
		dig_boxes(shape, a, b, &boxes)
		for box in boxes do for y := box[1].y; y >= box[0].y; y -= 1 do for z in box[0].z..=box[1].z do for x in box[0].x..=box[1].x {
			if ground_at(src, {x, y, z}) do append(out, [3]i32{x, y, z})
		}
	case .Fell, .Gather, .Fish:   // trees, and what bears food and swims, are found by their own rules (trees_standing; bearing_of, food.odin)
	case .Build:
		switch shape {
		case .Out, .Down, .Up:
		case .Floor:
			for z in lo.z..=hi.z do for x in lo.x..=hi.x do if open(src, {x, a.y, z}) do append(out, [3]i32{x, a.y, z})
		case .Roof:   // the layer over the level the drag began on: over a wall's top, the roof that lies on the walls and spans what they stand round
			for z in lo.z..=hi.z do for x in lo.x..=hi.x do if open(src, {x, a.y + 1, z}) do append(out, [3]i32{x, a.y + 1, z})
		case .Wall:   // as high as the box, standing on the ground of each column near the level it began on: it follows the ground, so a mason reaches all of it
			high := hi.y - lo.y + 1
			for z in lo.z..=hi.z do for x in lo.x..=hi.x {
				foot := lo.y + 1
				for foot < lo.y + 4 && !open(src, {x, foot, z}) do foot += 1         // up over ground that stands higher
				for foot > lo.y - 3 && open(src, {x, foot - 1, z}) do foot -= 1     // down to ground that lies lower
				for y in foot..<foot + high do if open(src, {x, y, z}) do append(out, [3]i32{x, y, z})
			}
		case .Fire:   // one, in the cell over the block the drag began on, where a dwarf could stand
			if c := a + {0, 1, 0}; stands_at(src, c) do append(out, c)
		case .Rack:   // one in each place a dwarf could stand in the box's columns, near the level it began on: it follows a slope, as a stockpile does
			zone_cells(a, b, src, out)
		case .Stair:
			axis, way, steps := stair_run(a, b)
			for i in 0..<steps do for y in a.y + 1..=a.y + 1 + i do for across in lo[2 - axis]..=hi[2 - axis] {
				c := [3]i32{0, y, 0}
				c[axis], c[2 - axis] = a[axis] + way*i, across
				if open(src, c) do append(out, c)
			}
		}
	}
}

// Blocks as the fewest boxes a plain sweep finds: each block not yet in a box begins one, which
// grows east while blocks go on, then south while whole rows do, then down while whole layers do.
// What is marked is drawn as these, so a mark taken back or dug leaves its box (bar.odin).
boxes_of :: proc(cells: [][3]i32, out: ^[dynamic][2][3]i32) {
	left := make(map[[3]i32]bool, context.temp_allocator)
	for c in cells do left[c] = true
	for c in cells do if left[c] {
		lo, hi := c, c
		for left[{hi.x + 1, c.y, c.z}] do hi.x += 1
		grow_z: for {
			for x in lo.x..=hi.x do if !left[{x, c.y, hi.z + 1}] do break grow_z
			hi.z += 1
		}
		grow_y: for {
			for z in lo.z..=hi.z do for x in lo.x..=hi.x do if !left[{x, lo.y - 1, z}] do break grow_y
			lo.y -= 1
		}
		for y in lo.y..=hi.y do for z in lo.z..=hi.z do for x in lo.x..=hi.x do left[{x, y, z}] = false
		append(out, [2][3]i32{lo, hi})
	}
}

// ---- materials ------------------------------------------------------------------------------

// The kind of rock a block is, in whatever form it lies; Air for earth, sand and plants, which the store does not keep.
rock_kind :: proc(m: Mat) -> Mat {
	if MATERIALS[m].strength > 0 || m == .Timber do return m   // timber laid and taken up again is timber still
	for r in Mat do if MATERIALS[r].strength > 0 && (MATERIALS[r].loose == m || FORMS[r].broken == m || FORMS[r].gravel == m) do return r
	return .Air
}

// Seconds a common hand takes to cut a block.
dig_seconds :: proc(m: Mat) -> f32 { return DIG_BASE + DIG_ROCK*MATERIALS[m].strength }

// How a material cuts, in a word, for a card.
cut_words :: proc(m: Mat) -> string {
	s := MATERIALS[m].strength
	return "too hard for the picks" if s > TOOLS else "hard rock" if s >= 0.6 else "firm rock" if s >= 0.4 else "soft rock" if s > 0 else "loose"
}

// What the store holds of a kind, in words: "basalt", "shii timber".
store_words :: proc(m: Mat) -> string {
	if is(m, FOOD) do return FOODS[food_of(m)].name
	if is(m, bit_set[Trait]{.Bark}) do for sp in SPECIES do if sp.bark == m do return fmt.tprintf("%s timber", sp.name)
	return "timber" if m == .Timber else mat_words(m)
}

// The tree a bark is of, in words, for a card.
SPECIES_OF := #partial [Mat]string{.Wood = "tabu tree", .Shii_Bark = "shii tree", .Grey_Bark = "camellia or hisakaki", .Pine_Bark = "black pine"}

is_stuff :: proc(m: Mat, stuff: Stuff) -> bool { return is(m, bit_set[Trait]{.Bark}) || m == .Timber if stuff == .Timber else MATERIALS[m].strength > 0 }

// How much of a stuff the store holds, and the kind it holds most of.
store_of :: proc(store: ^[Mat]i32, stuff: Stuff) -> (n: int, most: Mat) {
	for count, m in store do if count > 0 && is_stuff(m, stuff) {
		n += int(count)
		if most == .Air || count > store[most] do most = m
	}
	return
}

// Whether a dwarf's trade is a kind of work's.
skilled :: proc(f: Facts, work: Work, stuff: Stuff) -> bool {
	trade, hands := TRADES[f.trade].name, WORKS[work].hands
	return trade == hands[int(stuff)] if work == .Build else trade == hands[0] || trade == hands[1]
}

// ---- the dwarves' world: marking ------------------------------------------------------------

hold_blocks :: proc(h: ^Hold) -> Blocks {
	return {proc(data: rawptr, b: [3]i32) -> Mat { m, _ := walk_block(&(cast(^Hold)data).walk, b); return m },
		proc(data: rawptr, b: [3]i32) -> bool { return walk_floor(&(cast(^Hold)data).walk, b.x, b.y, b.z) >= 0 }, h}
}

site_thing :: proc(work: Work, shape: Plan) -> string {
	return "trees" if work == .Fell else "gathering" if work == .Gather else "fishing" if work == .Fish else "stair down" if shape == .Down else "stair up" if shape == .Up else "digging" if work == .Dig else PLANS[shape]
}

// The order as an orders file and the log give it.
order_words :: proc(o: Order) -> string {
	box := fmt.tprintf("%d %d %d %d %d %d", o.at.x, o.at.y, o.at.z, o.to.x, o.to.y, o.to.z)
	#partial switch o.kind {
	case .Dig:    return fmt.tprintf("dig %s %s", PLANS[o.shape], box)
	case .Fell:   return fmt.tprintf("fell %s", box)
	case .Build:  return fmt.tprintf("build %s %s %s", PLANS[o.shape], STUFFS[o.stuff], box)
	case .Unmark: return fmt.tprintf("unmark %s", box)
	case .Store:  return fmt.tprintf("store %s %s", TAKES[o.takes], box)
	case .Sleep:  return fmt.tprintf("sleep %s", box)
	case .Tend:   return fmt.tprintf("fire %s %s", "feed" if o.on else "leave", box)
	case .Use:    return fmt.tprintf("rack %s %s", "load" if o.on else "leave", box)
	case .Unstore: return fmt.tprintf("unstore %s", box)
	case .Takes:  return fmt.tprintf("takes %s %s", TAKES[o.takes], box)
	case .Gather: return fmt.tprintf("gather %s", box)
	case .Fish:   return fmt.tprintf("fish %s", box)
	}
	return ""
}

mark_add :: proc(h: ^Hold, m: Mark) {
	h.marked[m.at] = len(h.marks)
	append(&h.marks, m)
	s := &h.sites[m.site]
	if s.total == 0 do s.lo, s.hi = m.at, m.at
	s.lo, s.hi = {min(s.lo.x, m.at.x), min(s.lo.y, m.at.y), min(s.lo.z, m.at.z)}, {max(s.hi.x, m.at.x), max(s.hi.y, m.at.y), max(s.hi.z, m.at.z)}
	s.total += 1
	s.left += 1
	h.marks_v += 1
}

// A mark is gone: done, or taken back. The last of an order ends it.
mark_remove :: proc(h: ^Hold, k: int, done: bool) {
	m := h.marks[k]
	if m.taker >= 0 do job_drop(h, m.taker, 0)
	delete_key(&h.marked, m.at)
	last := len(h.marks) - 1
	if k != last {
		h.marks[k] = h.marks[last]
		h.marked[h.marks[k].at] = k
	}
	pop(&h.marks)
	h.marks_v += 1
	s := &h.sites[m.site]
	s.left -= 1
	if s.left > 0 || s.over do return
	s.over = true
	for kind in s.brought do good_drop(h, m.at + {0, 1, 0}, kind, 1)   // what was brought and not laid lies where the order was
	clear(&s.brought)
	if !done || s.work == .Build && s.shape == .Fire do return   // a fire lit has been said
	// What was done, and by whom.
	b := strings.builder_make(context.temp_allocator)
	n := 0   // what was done of it: a mark taken back is not
	for count in s.tally do n += count
	units := work_units(s.work, n) if s.thing != "foraging" else "plant, tree or place of water" if n == 1 else "plants, trees and places of water"
	if s.work == .Build && s.shape == .Rack do units = "rack" if n == 1 else "racks"
	h.aside = s.thing == "foraging"   // the log's alone: the hungry feeding themselves is no news each time
	fmt.sbprintf(&b, "The %s %s %s: %d %s.", s.name, "are" if s.work == .Fell || s.thing == "racks" else "is", "done" if s.down || s.work == .Gather || s.work == .Fish else WORKS[s.work].done, n, units)
	verb := "built" if s.work == .Build && s.shape == .Rack else "cut" if s.work == .Dig else "felled" if s.work == .Fell else "took" if s.thing == "foraging" else "gathered from" if s.work == .Gather else "fished" if s.work == .Fish else "laid"
	first := true
	for count, i in s.tally do if count > 0 {
		fmt.sbprintf(&b, "%s %s %s %s %d", "" if first else ",", h.party[i].given, h.party[i].byname, verb, count)
		first = false
	}
	if !first do fmt.sbprint(&b, ".")
	if len(s.got) > 0 {
		fmt.sbprint(&b, " It yielded")
		for g, i in s.got do fmt.sbprintf(&b, "%s %d of %s", "" if i == 0 else " and" if i == len(s.got) - 1 else ",", g.n, store_words(g.mat))
		fmt.sbprint(&b, ".")
	}
	if s.steps > 0 do fmt.sbprintf(&b, " %d %s left standing as the step out of the pit%s: a stair dug into it would free %s.", s.steps, "block is" if s.steps == 1 else "blocks are", fmt.tprintf(", and %d behind %s that cannot be come at while %s", s.behind, "it" if s.steps == 1 else "them", "it stands" if s.steps == 1 else "they stand") if s.behind > 0 else "", "it" if s.steps + s.behind == 1 else "them")
	h.at = site_middle(s)
	short := strings.builder_make(context.temp_allocator)
	head := "Built" if s.work == .Build && s.shape == .Rack else "Felled" if s.work == .Fell else "Gathered" if s.work == .Gather else "Fished" if s.work == .Fish else "Taken down" if s.down else "Dug" if s.thing == "digging" else fmt.tprintf("%s %s", s.thing, WORKS[s.work].done)
	fmt.sbprintf(&short, "%s: %d %s", sentence(head)[:len(head)], n, units)
	for g in s.got do fmt.sbprintf(&short, ", %d %s", g.n, store_words(g.mat))
	if s.steps > 0 do fmt.sbprintf(&short, ". %d left as the step out%s", s.steps, fmt.tprintf(", %d behind it", s.behind) if s.behind > 0 else "")
	h.short = fmt.tprintf("%s.", strings.to_string(short))
	say(h, "%s", strings.to_string(b))
}

// What a kind of work counts its marks in: blocks, trees, plants, places of water.
work_units :: proc(work: Work, n: int) -> string {
	one := n == 1
	switch work {
	case .Dig, .Build: return "block" if one else "blocks"
	case .Fell:        return "tree" if one else "trees"
	case .Gather:      return "plant" if one else "plants and trees"
	case .Fish:        return "place" if one else "places"
	}
	return ""
}

// An order's marks to gather or to fish, of what a box bears (bearing_of, food.odin): a new order of
// its own, which is returned. It is the player's, or a hungry dwarf's (forage, needs.odin).
gather_site :: proc(h: ^Hold, work: Work, found: []Bearing, a, b: [3]i32, thing: string) -> (id: int) {
	lo, hi := box_of(a, b)
	middle := [3]i32{(lo.x + hi.x)/2, a.y, (lo.z + hi.z)/2}
	id = len(h.sites)
	append(&h.sites, Site{work = work, a = a, b = b, place = place_say(h, middle), thing = thing})
	for f in found {
		if f.at in h.marked do continue
		row := FOODS[f.food]
		mark_add(h, Mark{at = f.at, site = id, work = .Fish if row.from == .Fish else .Gather, taker = -1, by = -1, tall = f.tall, tree = row.tree, food = f.food, n = f.n})
	}
	s := &h.sites[id]
	s.name = fmt.aprintf("%s at %s", thing, s.place)
	if s.total == 0 do s.over = true
	for &d in h.dwarves do if !d.job do d.rest = min(d.rest, 2)
	return
}

// Whether a mark is worked from beside a tree's stem, or from beyond its leaves (in_reach).
mark_tree :: proc(m: Mark) -> bool { return m.work == .Fell || m.work == .Gather && FOODS[m.food].from == .Tree }

site_middle :: proc(s: ^Site) -> Maybe([3]f64) { return [3]f64{f64(s.lo.x + s.hi.x + 1)/2, f64(s.lo.y + s.hi.y + 1)/2, f64(s.lo.z + s.hi.z + 1)/2} }

// Obey an order to mark: to dig, to fell, to build, or to take marks back.
mark_obey :: proc(h: ^Hold, o: Order) {
	w := &h.walk
	bound(h.island)
	lo, hi := box_of(o.at, o.to)
	words := order_words(o)
	if o.kind == .Unmark {   // every mark in the box's columns is taken back, and no other: an order may be trimmed
		gone := 0
		for k := len(h.marks) - 1; k >= 0; k -= 1 do if m := h.marks[k]; m.at.x >= lo.x && m.at.x <= hi.x && m.at.z >= lo.z && m.at.z <= hi.z {
			mark_remove(h, k, false)
			gone += 1
		}
		h.at = feet_on({(lo.x + hi.x)/2, o.at.y, (lo.z + hi.z)/2})
		if gone > 0 {
			h.short = fmt.tprintf("Taken back: %d %s.", gone, "mark" if gone == 1 else "marks")
			say(h, `The hold says "%s": %d %s taken back.`, words, gone, "mark is" if gone == 1 else "marks are")
			return
		}
		// No mark there: the blocks the dwarves laid in those columns are taken down, and give their stuff back.
		down := make([dynamic][3]i32, context.temp_allocator)
		for c in h.built do if c.x >= lo.x && c.x <= hi.x && c.z >= lo.z && c.z <= hi.z do append(&down, c)
		for a in 1..<len(down) do for k := a; k > 0 && (down[k].y > down[k - 1].y || down[k].y == down[k - 1].y && (down[k].z < down[k - 1].z || down[k].z == down[k - 1].z && down[k].x < down[k - 1].x)); k -= 1 do down[k], down[k - 1] = down[k - 1], down[k]   // the highest first, and the same order twice
		if len(down) > 0 {
			id := len(h.sites)
			append(&h.sites, Site{work = .Dig, shape = .Out, a = o.at, b = o.to, down = true, thing = "taking down", place = place_say(h, down[0])})
			for c in down do if c not_in h.marked do mark_add(h, Mark{at = c, site = id, work = .Dig, taker = -1, by = -1})
			s := &h.sites[id]
			s.name = fmt.aprintf("taking down at %s", s.place)
			h.short = fmt.tprintf("Marked to take down: %d built %s.", s.total, "block" if s.total == 1 else "blocks")
			say(h, `The hold says "%s": %d built %s marked to be taken down at %s.`, words, s.total, "block is" if s.total == 1 else "blocks are", s.place)
			return
		}
		// Nor a built block: a fire there is put out and taken up.
		if fires := fires_remove(h, lo, hi); fires > 0 {
			h.short = "The fire is put out and taken up." if fires == 1 else fmt.tprintf("%d fires are put out and taken up.", fires)
			say(h, `The hold says "%s": %s put out and taken up; what timber was left lies there.`, words, "the fire there is" if fires == 1 else fmt.tprintf("%d fires there are", fires))
			return
		}
		// Nor a fire: a rack there is taken down.
		if racks := benches_remove(h, lo, hi); racks > 0 {
			h.short = "The rack is taken down." if racks == 1 else fmt.tprintf("%d racks are taken down.", racks)
			say(h, `The hold says "%s": %s taken down; what stood on %s and the timber %s of lie there.`, words, "the rack there is" if racks == 1 else fmt.tprintf("%d racks there are", racks), "it" if racks == 1 else "them", "it was" if racks == 1 else "they were")
			return
		}
		// Nor a rack: the ground there is taken out of its stockpile, or its sleeping place.
		if cells := zone_remove(h, lo, hi); cells > 0 {
			h.short = fmt.tprintf("%d %s taken out of what was marked there.", cells, "place" if cells == 1 else "places")
			say(h, `The hold says "%s": %d %s taken out of the stockpile or the sleeping place there; what lies on them lies loose.`, words, cells, "place is" if cells == 1 else "places are")
			return
		}
		h.short = "Nothing is marked there."
		say(h, `The hold says "%s": nothing is marked there.`, words)
		return
	}
	if o.kind == .Gather || o.kind == .Fish {   // what the box bears now, by the rows of FOODS (food.odin)
		work := Work.Gather if o.kind == .Gather else .Fish
		h.at = feet_on({(lo.x + hi.x)/2, o.at.y + 1, (lo.z + hi.z)/2})
		if (i64(hi.x - lo.x) + 1)*(i64(hi.z - lo.z) + 1) > ORDER_MOST {
			h.short = "Too much for one order: mark less at a time."
			say(h, `The hold says "%s": that is more ground than one order may mark, %d columns: mark less at a time.`, words, ORDER_MOST)
			return
		}
		date := date_tick(h.tick)
		found := make([dynamic]Bearing, context.temp_allocator)
		barren: Barren
		bearing_of(work, o.at, o.to, date.sun, date.day, hold_blocks(h), &h.picked, &found, &barren)
		for k := len(found) - 1; k >= 0; k -= 1 do if found[k].at in h.marked do ordered_remove(&found, k)
		if len(found) == 0 {
			why := barren_words(work, barren)
			h.short = why
			say(h, `The hold says "%s": %s so nothing is marked.`, words, fmt.tprintf("%s,", strings.to_lower(why[:len(why) - 1], context.temp_allocator)))
			return
		}
		id := gather_site(h, work, found[:], o.at, o.to, site_thing(work, .Out))
		s := &h.sites[id]
		h.at = site_middle(s)
		h.ground += 1   // idle dwarves look to themselves: one standing on what is marked steps off it
		if work == .Gather {
			h.short = fmt.tprintf("Marked to gather: %s.", bearing_words(found[:]))
			say(h, `The hold says "%s": %d %s marked to be gathered at %s, for %s.`, words, s.total, "plant or tree is" if s.total == 1 else "plants and trees are", s.place, bearing_words(found[:]))
		} else {
			h.short = fmt.tprintf("Marked to fish: %s.", bearing_words(found[:]))
			say(h, `The hold says "%s": %d %s of water %s marked to be fished at %s, for %s.`, words, s.total, "place" if s.total == 1 else "places", "is" if s.total == 1 else "are", s.place, bearing_words(found[:]))
		}
		return
	}
	work := Work.Dig if o.kind == .Dig else .Fell if o.kind == .Fell else .Build
	middle := [3]i32{(lo.x + hi.x)/2, o.at.y, (lo.z + hi.z)/2}
	site := Site{work = work, shape = o.shape, stuff = o.stuff, a = o.at, b = o.to, place = place_say(h, middle)}
	id := len(h.sites)
	append(&h.sites, site)
	hard, rooted := 0, 0
	switch work {
	case .Dig, .Build:
		cells := make([dynamic][3]i32, context.temp_allocator)
		cells_of(work, o.shape, o.at, o.to, hold_blocks(h), &cells)
		if work == .Build && (o.shape == .Fire || o.shape == .Rack) do for k := len(cells) - 1; k >= 0; k -= 1 do if cells[k] in h.burning || cells[k] in h.benched do ordered_remove(&cells, k)   // not where a fire burns or a rack stands already
		if size := (i64(hi.x - lo.x) + 1)*(i64(hi.z - lo.z) + 1)*(i64(hi.y - lo.y) + 3); len(cells) > ORDER_MOST || size > 8*ORDER_MOST {
			pop(&h.sites)
			h.short = "Too much for one order: mark less at a time."
			say(h, `The hold says "%s": that is more than one order may mark, %d blocks: mark less at a time.`, words, ORDER_MOST)
			return
		}
		box_lo, box_hi := box_of(o.at, o.to)
		if o.shape == .Down || o.shape == .Up do box_lo.y, box_hi.y = min(i32), max(i32)
		for c in cells {
			if c in h.marked do continue
			m := Mark{at = c, site = id, work = work, taker = -1, by = -1}
			if work == .Dig {
				was, _ := walk_block(w, c)
				if MATERIALS[was].strength > TOOLS do m.wait, hard = .Too_Hard, hard + 1
			}
			mark_add(h, m)
		}
		if work == .Dig && len(cells) > 0 {   // a tree standing on ground to be dug is felled with it, as RimWorld cuts the plants in a mine's way
			reach_lo, reach_hi := cells[0], cells[0]
			for c in cells do reach_lo, reach_hi = {min(reach_lo.x, c.x), 0, min(reach_lo.z, c.z)}, {max(reach_hi.x, c.x), 0, max(reach_hi.z, c.z)}
			trees := make([dynamic]Tree, context.temp_allocator)
			ox, oz := region.origin.x, region.origin.y
			trees_in(reach_lo.x - ox, reach_lo.z - oz, reach_hi.x - ox, reach_hi.z - oz, &trees, true)
			for t in trees {
				foot := [3]i32{t.x + ox, t.base, t.z + oz}
				under := false   // its foot, or the root a block or two under it, stands on a block of the order
				for down in i32(1)..=3 do under ||= foot - {0, down, 0} in h.marked
				if t.form == .Fallen || !under || foot in h.marked || ([3]i32{foot.x, FELLED, foot.z} in w.edited) do continue
				if b, _ := walk_block(w, foot); !is(b, PLANT_BLOCKS) do continue
				mark_add(h, Mark{at = foot, site = id, work = .Fell, taker = -1, by = -1, tall = t.height, tree = t.kind})
				rooted += 1
			}
		}
	case .Gather, .Fish:   // marked above
	case .Fell:
		trees := make([dynamic]Tree, context.temp_allocator)
		ox, oz := region.origin.x, region.origin.y
		trees_standing(lo.x - ox, lo.z - oz, hi.x - ox, hi.z - oz, &trees)
		for t in trees {
			foot := [3]i32{t.x + ox, t.base, t.z + oz}
			if t.form == .Fallen || foot in h.marked || ([3]i32{foot.x, FELLED, foot.z} in w.edited) do continue
			if m, _ := walk_block(w, foot); !is(m, PLANT_BLOCKS) do continue   // no stem or bush stands there
			mark_add(h, Mark{at = foot, site = id, work = .Fell, taker = -1, by = -1, tall = t.height, tree = t.kind})
		}
	}
	s := &h.sites[id]
	thing := site_thing(work, o.shape)
	if work == .Build && o.shape == .Fire do s.stuff = .Timber   // whatever was asked: a fire burns timber
	if kind, bench := bench_of(o.shape); work == .Build && bench do s.stuff = BENCHES[kind].stuff   // and a bench is built of what its row says
	if work == .Build && o.shape == .Roof do thing = "roof"
	if work == .Build && o.shape == .Rack && s.total > 1 do thing = "racks"
	if work == .Build && o.shape == .Floor {   // a roof where most of it lies over open air
		over := 0
		for m in h.marks do if m.site == id do if under, _ := walk_block(w, m.at - {0, 1, 0}); under == .Air do over += 1
		thing = "roof" if 2*over > s.total else "floor"
	}
	s.thing = thing
	s.name = fmt.aprintf("%s at %s", thing, s.place)
	h.at = site_middle(s)
	h.ground += 1   // idle dwarves look to themselves: one standing on what is marked steps off it
	if s.total == 0 {
		s.over = true
		h.short = fmt.tprintf("Nothing to %s there.", WORKS[work].name)
		say(h, `The hold says "%s": nothing there to %s, so nothing is marked.`, words, WORKS[work].name)
		return
	}
	more, less := "", ""
	if hard > 0 do more, less = fmt.tprintf("%s; %d of them are of rock too hard for the party's picks", more, hard), fmt.tprintf("%s, %d too hard for the picks", less, hard)
	if rooted > 0 do more, less = fmt.tprintf("%s; %d %s on it, and felled first", more, rooted, "tree stands" if rooted == 1 else "trees stand"), fmt.tprintf("%s, %d %s to fell first", less, rooted, "tree" if rooted == 1 else "trees")
	blocks := "block" if s.total - rooted == 1 else "blocks"
	switch work {
	case .Gather, .Fish:
	case .Dig:
		h.short = fmt.tprintf("Marked to dig: %d %s%s.", s.total - rooted, blocks, less)
		say(h, `The hold says "%s": %s is marked at %s, %d %s of it%s.`, words, "digging" if thing == "digging" else fmt.tprintf("a %s", thing), s.place, s.total - rooted, blocks, more)
	case .Fell:
		h.short = fmt.tprintf("Marked to fell: %d %s.", s.total, "tree" if s.total == 1 else "trees")
		say(h, `The hold says "%s": %d %s marked to be felled at %s.`, words, s.total, "tree is" if s.total == 1 else "trees are", s.place)
	case .Build:
		if o.shape == .Fire {
			h.short = "Marked: a fire, to be laid of timber and lit."
			say(h, `The hold says "%s": a fire is marked to be laid and lit at %s, of a log brought to it; it is fed from then on with what timber the hold has.`, words, s.place)
			break
		}
		if kind, bench := bench_of(o.shape); bench {
			row := BENCHES[kind]
			h.short = fmt.tprintf("Marked: %d %s%s, each of a log.", s.total, row.name, "" if s.total == 1 else "s")
			say(h, `The hold says "%s": %d %s%s %s marked to be built at %s, each of a log brought to it; fresh food that dries is brought to %s from then on.`, words, s.total, row.name, "" if s.total == 1 else "s", "is" if s.total == 1 else "are", s.place, "it" if s.total == 1 else "them")
			break
		}
		h.short = fmt.tprintf("Marked to build: a %s of %s, %d %s.", thing, STUFFS[o.stuff], s.total, blocks)
		say(h, `The hold says "%s": a %s is marked to be built of %s at %s, %d %s of it.`, words, thing, STUFFS[o.stuff], s.place, s.total, blocks)
	}
}

// ---- the dwarves' world: taking work ----------------------------------------------------------

// Whether a dwarf standing on a floor can work a block: beside it from a block under its feet to a
// block over its head, right over its head, or two under or over where the block between is open.
// A tree is felled from beside its stem, or, where its own leaves fill every floor beside it as a
// bush's do, from the floor beyond them: two off, with leaves or air between at the dwarf's chest.
in_reach :: proc(h: ^Hold, cell, b: [3]i32, tree := false, lay := false) -> bool {
	dx, dy, dz := b.x - cell.x, b.y - cell.y, b.z - cell.z
	if tree && max(abs(dx), abs(dz)) == 2 {
		m, _ := walk_block(&h.walk, cell + {clamp(dx, -1, 1), 1, clamp(dz, -1, 1)})
		return abs(dy) <= 2 && (m == .Air || is(m, PLANT_BLOCKS))
	}
	if abs(dx) > 1 || abs(dz) > 1 do return false
	if dx == 0 && dz == 0 do return dy == 2
	open :: proc(h: ^Hold, c: [3]i32) -> bool { m, _ := walk_block(&h.walk, c); return m == .Air || is(m, LEAVES) }
	switch dy {
	case -1, 0, 1: return true
	case -2: return open(h, b + {0, 1, 0})
	case 2:  return lay || open(h, b - {0, 1, 0})   // a block is laid on the top of a wall two high from the ground beside it, at arm's stretch
	}
	return false
}

// The floors a block can be worked from, that no other dwarf holds or is bound for: to dig, the
// highest first, so a pit is dug from its rim; to lay, the lowest, so a wall is built from the
// ground beside it and no mason is left standing on it. Then the nearest the dwarf.
stands_of :: proc(h: ^Hold, i: int, b: [3]i32, out: ^[dynamic][3]i32, low := false, tree := false) -> (any: bool) {
	w, d := &h.walk, &h.dwarves[i]
	// The floors beside it; for a tree with none, the floors beyond its leaves (in_reach).
	for r in i32(1)..=(2 if tree else 1) do for dz in -r..=r do for dx in -r..=r {
		if r == 2 && (any || max(abs(dx), abs(dz)) < 2) do continue
		x, z := b.x + dx, b.z + dz
		p := patch_at(w, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT)
		if p == nil do continue
		col := (z & (CHUNK - 1))*CHUNK + x & (CHUNK - 1)
		for k in p.first[col]..<p.first[col + 1] {
			cell := [3]i32{x, i32(w.floors[p.base + i32(k)].y), z}
			if !in_reach(h, cell, b, tree, low) do continue
			any = true
			if o, held := h.held[cell]; held && o != i {
				if b := &h.dwarves[o]; !b.job && (b.doing == .Waiting || b.doing == .Stopped) do b.rest = 0   // an idle dwarf stands where the work is done from: it looks at once, and the work is its own
				continue
			}
			if o, claimed := h.claims[cell]; claimed && o != i do continue
			append(out, cell)
		}
	}
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + abs(a.y - b.y) }
	sign := i32(-1) if low else 1
	for a in 1..<len(out) do for k := a; k > 0 && (sign*out[k].y > sign*out[k - 1].y || out[k].y == out[k - 1].y && far(out[k], d.cell) < far(out[k - 1], d.cell)); k -= 1 do out[k], out[k - 1] = out[k - 1], out[k]
	return
}

// A dwarf lets its work go, and rests so many ticks before it looks for more.
job_drop :: proc(h: ^Hold, i: int, rest: int) {
	d := &h.dwarves[i]
	if !d.job do return
	if k, ok := h.marked[d.job_at]; ok && h.marks[k].taker == i {
		h.marks[k].taker = -1
		if h.marks[k].work == .Build do h.sites[h.marks[k].site].promised -= 1
	}
	if o, ok := h.claims[d.stand]; ok && o == i do delete_key(&h.claims, d.stand)
	d.job, d.rest = false, rest
	clear(&d.path)
	if d.doing == .Working || d.doing == .Walking && d.takes == 0 do d.doing = .Waiting
	else if d.doing == .Walking {   // in a step: it stands at the step's end
		d.next = len(d.path)
		d.seek = false
	}
	h.marks_v += 1
}

// A mark could not be worked: it says why and is left a while.
mark_waits :: proc(h: ^Hold, k: int, why: Waits, by := -1) {
	m := &h.marks[k]
	if m.taker >= 0 do job_drop(h, m.taker, 5)
	if m.wait != why do h.marks_v += 1
	m.wait, m.tried, m.by, m.as_of = why, h.tick, by, h.ground
	// An order with nothing left but the last steps out of its pit, each found so as the ground now
	// stands, and the blocks no floor reaches while those steps stand, is done: they are left
	// standing, and it says so. Without this the blocks behind a step wait for it for ever.
	if why == .Way_Out {
		site := m.site
		for o in h.marks do if o.site == site && o.wait != .Front && (o.wait != .Way_Out || o.taker >= 0 || o.as_of != h.ground) do return
		for j := len(h.marks) - 1; j >= 0; j -= 1 do if h.marks[j].site == site {
			if h.marks[j].wait == .Way_Out do h.sites[site].steps += 1
			else do h.sites[site].behind += 1
			mark_remove(h, j, true)
		}
	}
}

// An idle dwarf looks for work: of the marks nobody has taken, the nearest it its trade suits
// first, it takes the first it can stand beside and has a way to. False if it found none.
work_look :: proc(h: ^Hold, i: int, basket := false) -> bool {   // basket: it has food in its arms, and takes only more to gather or fish within a few steps
	started := time.now()
	defer {
		h.work.looks += 1
		h.work.looking += time.since(started)
	}
	d, w := &h.dwarves[i], &h.walk
	w.budget = ASKING
	// The nearest few, a mark of its own trade counting as half as far.
	Near :: struct { score: f32, k: int }
	best: [TRIES]Near
	n := 0
	for m, k in h.marks {
		if m.taker >= 0 || m.wait == .Too_Hard || m.wait == .Front do continue   // rock too hard, and blocks no floor reaches, wait for the ground to change (ground_changed)
		if m.wait != .None && h.tick - m.tried < AGAIN && (m.by < 0 || m.by == i) do continue   // what one dwarf could not come at, another may
		dx, dy, dz := f32(m.at.x - d.cell.x), f32(m.at.y - d.cell.y), f32(m.at.z - d.cell.z)
		if basket && (m.work != .Gather && m.work != .Fish || FOODS[m.food].thing != d.carry || abs(dx) + abs(dz) + 2*abs(dy) > BASKET_REACH) do continue
		score := (abs(dx) + abs(dz) + 2*abs(dy))*(1 if skilled(h.party[i], m.work, h.sites[m.site].stuff) else 2)
		if (m.work == .Gather || m.work == .Fish) && d.want[.Food] < WANTS[.Food].seeks do score *= 0.1   // a hungry dwarf takes food first
		if m.work == .Build && h.sites[m.site].shape == .Fire && d.want[.Warm] < WANTS[.Warm].seeks do score *= 0.1   // and a cold one a fire to be laid
		if n == TRIES && score >= best[n - 1].score do continue
		at := min(n, TRIES - 1)
		for at > 0 && best[at - 1].score > score {
			best[at] = best[at - 1]
			at -= 1
		}
		best[at] = {score, k}
		n = min(n + 1, TRIES)
	}
	stands := make([dynamic][3]i32, context.temp_allocator)
	for near in best[:n] {
		k := near.k
		m := h.marks[k]
		s := &h.sites[m.site]
		up := m.at + {0, 1, 0}
		switch m.work {
		case .Dig:
			if o, stood := h.held[up]; stood && o != i {   // the looker's own floor is no bar: it steps off to work it
				mark_waits(h, k, .Stood_On)
				continue
			}
			if over, _ := walk_block(w, up); is(over, bit_set[Trait]{.Bark}) {   // a stem stands on it: felled first, by the mark the order gave it
				mark_waits(h, k, .Rooted)
				continue
			}
		case .Fell, .Gather, .Fish:
		case .Build:
			if len(s.brought) - s.promised <= 0 {   // its stuff is fetched by whoever has nothing more pressing (haul_look)
				mark_waits(h, k, .No_Stuff)
				continue
			}
			if trodden(h, m.at, i) || trodden(h, m.at - {0, 1, 0}, i) {   // standing there, or on its way over it
				mark_waits(h, k, .Stood_On)
				continue
			}
			against := false
			for side in ([6][3]i32{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}) {
				if b, _ := walk_block(w, m.at + side); b != .Air && !is(b, LEAVES) do against = true
			}
			if !against {
				mark_waits(h, k, .Loose)
				continue
			}
		}
		clear(&stands)
		if any := stands_of(h, i, m.at, &stands, m.work == .Build, mark_tree(m)); len(stands) == 0 {
			mark_waits(h, k, .No_Room if any else .Front, i if any else -1)
			continue
		}
		found := false
		for stand in stands[:min(len(stands), 8)] {
			if stand != d.cell {
				clear(&w.shun)
				for o, j in h.dwarves do if j != i && o.doing != .Aboard && o.doing != .Walking && o.doing != .Dead do append(&w.shun, o.cell)
				for f in h.fires do append(&w.shun, f.at)   // and round a fire, where there is room
				for b in h.benches do append(&w.shun, b.at)
				_, why, _, _ := way_timed(h, d.cell, stand, &d.path)
				clear(&w.shun)
				if why != .Way do continue
			} else do clear(&d.path)
			// One whose trade it is not leaves it once for an idle dwarf whose trade it is.
			if !skilled(h.party[i], m.work, s.stuff) && !d.gave && !((m.work == .Gather || m.work == .Fish) && d.want[.Food] < WANTS[.Food].seeks) {
				for o, j in h.dwarves do if j != i && !o.job && !o.shut && (o.doing == .Waiting || o.doing == .Stopped) && skilled(h.party[j], m.work, s.stuff) {
					d.gave = true
					h.dwarves[j].rest = 0
					clear(&d.path)
					return false
				}
			}
			d.gave = false
			// It is taken.
			h.marks[k].taker, h.marks[k].wait = i, .None
			if m.work == .Build do s.promised += 1
			d.job, d.job_at, d.stand = true, m.at, stand
			h.claims[stand] = i
			h.spots[i] = stand
			d.doing, d.seek, d.next, d.wait, d.said, d.errand = .Walking, false, 1, 0, "", false
			for len(s.joined) < len(h.dwarves) {
				append(&s.joined, false)
				append(&s.tally, 0)
			}
			if !s.joined[i] && s.thing != "foraging" {   // what the hungry mark for themselves is said once, by the one who marked it
				s.joined[i] = true
				h.aside = true
				if s.thing == WORKS[m.work].doing do say(h, "%s %s takes up the %s.", h.party[i].given, h.party[i].byname, s.name)
				else do say(h, "%s %s takes up the %s of the %s.", h.party[i].given, h.party[i].byname, WORKS[m.work].doing, s.name)
			}
			h.marks_v += 1
			found = true
			break
		}
		if found {
			d.lack = .None
			return true
		}
		mark_waits(h, k, .No_Way, i)
	}
	if basket do return false
	// It found none. If everything marked and not in hand waits for one of the things only the player
	// can mend, it says which: a way, something in store, softer rock. Work others are at, or that
	// waits its turn, is no lack.
	lacks: [Waits]int
	in_hand := false
	for m in h.marks {
		if m.taker < 0 do lacks[m.wait if m.by < 0 || m.by == i else .None] += 1
		else do in_hand = true
	}
	d.lack = .None
	if lacks[.None] + lacks[.No_Room] + lacks[.Stood_On] + lacks[.Loose] + lacks[.Rooted] + lacks[.Shuts_In] + lacks[.Way_Out] == 0 {
		// Blocks no floor reaches wait for those in front of them; with none of those in anyone's hand, nothing will bring a floor to them.
		d.lack = .No_Way if lacks[.No_Way] > 0 || !in_hand && lacks[.Front] > 0 else .No_Stuff if lacks[.No_Stuff] > 0 else .Too_Hard if lacks[.Too_Hard] > 0 else .None
	}
	return false
}

// A dwarf has come to where it works from: it begins, for as long as the material and its trade make it.
work_begin :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	k, ok := h.marked[d.job_at]
	if !ok || h.marks[k].taker != i || !in_reach(h, d.cell, d.job_at, mark_tree(h.marks[k]), h.marks[k].work == .Build) {
		job_drop(h, i, 10)
		d.doing = .Waiting
		return
	}
	m := h.marks[k]
	s := &h.sites[m.site]
	// Would the block shut a dwarf in? Asked before the work is begun, not only at its end.
	if m.work == .Dig || m.work == .Build {
		w := &h.walk
		was, _ := walk_block(w, m.at)
		if m.work == .Dig && walk_floor(w, m.at.x, m.at.y + 1, m.at.z) >= 0 && closes(h, m.at, was) {   // the last step out of a pit: left standing
			mark_waits(h, k, .Way_Out)
			d.doing = .Waiting
			return
		}
		if m.work == .Build && s.shape != .Fire && s.shape != .Rack {   // a fire is no block, nor a rack: they shut nobody in
			before, _ := pockets(h, m.at)
			walk_edit(w, {m.at.x, m.at.y, m.at.z, .Stone})
			after, who := pockets(h, m.at)
			walk_edit(w, {m.at.x, m.at.y, m.at.z, was})
			if after > before {
				mark_waits(h, k, .Shuts_In)
				make_way(h, who, i)
				d.doing = .Waiting
				return
			}
		}
	}
	seconds: f32
	switch m.work {
	case .Dig:
		was, _ := walk_block(&h.walk, m.at)
		seconds, d.cut = dig_seconds(was), was
	case .Fell:
		seconds, d.cut = FELL_BASE + FELL_TALL*f32(m.tall), SPECIES[m.tree].bark
	case .Build:
		seconds = FIRE_WORK if s.shape == .Fire else LAY_TIMBER if s.stuff == .Timber else LAY_STONE
		if kind, bench := bench_of(s.shape); bench do seconds = BENCHES[kind].build
		d.cut = s.brought[len(s.brought) - 1] if len(s.brought) > 0 else .Air
	case .Gather, .Fish:
		seconds, d.cut = FOODS[m.food].work, FOODS[m.food].thing
	}
	if skilled(h.party[i], m.work, s.stuff) do seconds /= WORKS[m.work].quick
	seconds /= 1 - slowed(d.want)   // thirst, hunger and cold that will not wait slow the hands (WANTS.slows)
	d.doing, d.work = .Working, i32(seconds*1000)
	if dx, dz := f64(m.at.x - d.cell.x), f64(m.at.z - d.cell.z); dx != 0 || dz != 0 do d.facing = f32(math.atan2(dx, -dz))
}

// A dwarf at work: a tick of it, and the block changed when the work is done.
work_tick :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	k, ok := h.marked[d.job_at]
	if !ok || h.marks[k].taker != i {
		job_drop(h, i, 0)
		d.doing = .Waiting
		return
	}
	if !in_reach(h, d.cell, d.job_at, mark_tree(h.marks[k]), h.marks[k].work == .Build) {   // moved off its place, by a fall or by one squeezing past: it goes back
		h.spots[i] = d.stand
		d.doing, d.seek, d.wait = .Walking, true, 0
		return
	}
	d.work -= TICK_MS
	d.toil += TICK
	if d.work > 0 do return
	w := &h.walk
	m := h.marks[k]
	s := &h.sites[m.site]
	up := m.at + {0, 1, 0}
	switch m.work {
	case .Dig:
		was, _ := walk_block(w, m.at)
		if was != .Air {
			if trodden(h, up, i) {
				mark_waits(h, k, .Stood_On)
				return
			}
			// If a dwarf could stand on it, it may be the last step out of a pit: then it is left standing (closes).
			if walk_floor(w, up.x, up.y, up.z) >= 0 && closes(h, m.at, was) {
				mark_waits(h, k, .Way_Out)
				return
			}
			walk_edit(w, {m.at.x, m.at.y, m.at.z, .Air})
			ground_changed(h, m.at, .Air, false)
			if kind := rock_kind(was); kind != .Air {   // it lies where it was dug (goods.odin)
				site_got(s, kind, 1)
				good_drop(h, m.at, kind, 1)
			}
			if m.at in h.built {   // a block the dwarves laid stands no longer
				delete_key(&h.built, m.at)
				sync.lock(&h.mutex)
				append(&h.out_laid, Laid_Block{m.at, .Wall, false})
				sync.unlock(&h.mutex)
			}
		}
	case .Build:
		if len(s.brought) == 0 {
			mark_waits(h, k, .No_Stuff)
			return
		}
		mat := s.brought[len(s.brought) - 1]
		if trodden(h, m.at, i) || trodden(h, m.at - {0, 1, 0}, i) {   // a dwarf stands in the block's place or on its way through it, or would have it laid on its head
			mark_waits(h, k, .Stood_On)
			return
		}
		if s.shape == .Fire {   // no block is laid: the log is the fire's first, and it burns
			pop(&s.brought)
			fire_light(h, m.at, mat)
			h.at, h.short = feet_on(m.at), fmt.tprintf("%s lights a fire.", who(h, i))
			say(h, "%s lays a fire at %s and lights it: it burns a log in eight hours, and is fed from the timber the hold has.", who(h, i), place_say(h, m.at))
			break
		}
		if kind, bench := bench_of(s.shape); bench {   // nor here: a bench stands in the cell from now
			pop(&s.brought)
			bench_make(h, m.at, kind, mat)
			break
		}
		was, _ := walk_block(w, m.at)
		before, _ := pockets(h, m.at)
		laid := Mat.Timber if s.stuff == .Timber else mat   // timber is laid sawn, a block of its own that is no tree's
		walk_edit(w, {m.at.x, m.at.y, m.at.z, laid})
		if after, who := pockets(h, m.at); after > before {
			walk_edit(w, {m.at.x, m.at.y, m.at.z, was})
			mark_waits(h, k, .Shuts_In)
			make_way(h, who, i)
			return
		}
		ground_changed(h, m.at, laid, false)
		pop(&s.brought)
		h.built[m.at] = s.shape   // it remembers it was built, and as what
		sync.lock(&h.mutex)
		append(&h.out_laid, Laid_Block{m.at, s.shape, true})
		sync.unlock(&h.mutex)
	case .Fell:
		grain := GRAIN
		bark := SPECIES[m.tree].bark
		walk_edit(w, {m.at.x, FELLED, m.at.z, grain[bark][0]})   // kept apart from the block it stood on, which may be built on
		ground_changed(h, m.at, grain[bark][0], false)
		h.at, h.aside = feet_on(m.at), true   // the order's end says how many: one line, not one a tree
		if m.tree == .Scrub do say(h, "%s %s clears a bush of scrub.", h.party[i].given, h.party[i].byname)   // brush: no timber in it
		else {
			timber := max(int(m.tall)/2, 1)
			site_got(s, bark, timber)
			good_drop(h, m.at, bark, i32(timber))   // its logs lie where it stood
			say(h, "%s %s fells a %s tree %d m tall: %d logs lie where it stood.", h.party[i].given, h.party[i].byname, SPECIES[m.tree].name, m.tall, timber)
		}
	case .Gather, .Fish:   // the plant, the tree or the water is taken for its time (food.odin), and what it gave is in the dwarf's arms
		row := FOODS[m.food]
		h.picked[{m.at.x, m.at.z}] = date_tick(h.tick).day
		h.picked_v += 1
		site_got(s, row.thing, int(m.n))
		// A gatherer keeps what it takes, an armful of one kind, and carries it in when its arms are full or nothing
		// more is near (basket_home). What the hungry take for themselves lies at their feet, to be eaten there.
		if s.thing == "foraging" || d.want[.Food] < WANTS[.Food].seeks || d.carrying > 0 && d.carry != row.thing {
			haul_drop(h, i)
			good_drop(h, d.cell, row.thing, m.n)
		} else {
			d.haul.age = d.haul.age*f32(d.carrying)/f32(d.carrying + m.n)
			d.carry, d.carrying = row.thing, d.carrying + m.n
			h.goods_v += 1
		}
	}
	s.tally[i] += 1
	h.work.done += 1
	job_drop(h, i, 0)
	d.doing = .Waiting
	if k2, still := h.marked[m.at]; still do mark_remove(h, k2, true)
	if d.carrying > 0 && !d.haul.on {   // food in its arms: more of it from close by while it has room, then in with it
		if d.carrying < armful_of(d.carry) && !care_calls(h, i) && work_look(h, i, true) do return
		basket_home(h, i)
		return
	}
	// It looks for the next at once, before any that stand idle: the one at the face goes on at the face.
	if len(h.marks) > 0 && !care_calls(h, i) && !fire_first(h, i) && !work_look(h, i) do d.rest = 5   // unless thirst, hunger or the night call it away (needs.odin), or a fire is about to go out
}

// What an order's work yielded, for its end to say.
site_got :: proc(s: ^Site, m: Mat, n: int) {
	for &g in s.got do if g.mat == m {
		g.n += n
		return
	}
	append(&s.got, Got{m, n})
}

// A block of the hold's ground has changed, by a dwarf's work or the player's hand: the frame is
// told what a dwarf did, a dwarf whose floor went is settled, and ways laid past it are looked for again.
ground_changed :: proc(h: ^Hold, at: [3]i32, mat: Mat, frame: bool) {
	h.ground += 1
	if !frame {
		sync.lock(&h.mutex)
		append(&h.out, Edit{at.x, FELLED if is(mat, RINGS) else at.y, at.z, mat})
		sync.unlock(&h.mutex)
	}
	felled := is(mat, RINGS)
	r := i32(TREE_REACH + 1) if felled else 0
	for &d, i in h.dwarves do if d.doing == .Dead {   // a body comes down with the ground it lay on
		if d.cell.x == at.x && d.cell.z == at.z && mat == .Air && at.y == d.cell.y - 1 do for _ in 0..<64 {
			if under, _ := walk_block(&h.walk, d.cell - {0, 1, 0}); under != .Air && !is(under, LEAVES) do break
			d.cell.y -= 1
		}
	} else if d.doing != .Aboard && (d.adrift || abs(d.cell.x - at.x) <= r && abs(d.cell.z - at.z) <= r) do settle(h, i, felled || mat == .Air && at.y < d.cell.y)
	// A way laid over the old ground may not hold: each dwarf whose way still passes the block
	// stops at the end of its step and looks again, one a tick.
	turn := 0
	for &d in h.dwarves do if d.doing == .Walking && !d.seek {
		for b in d.path[min(d.next, len(d.path)):] do if abs(b.x - at.x) <= r + 1 && abs(b.z - at.z) <= r + 1 && (felled || abs(b.y - at.y) <= 2) {
			clear(&d.path)
			d.seek, d.wait = true, turn
			turn += 1
			break
		}
	}
	goods_settle(h, at, mat)   // a pile on a block dug away falls with it; one where a block was laid is moved out
	fires_settle(h, at, mat)   // and so a fire
	benches_settle(h, at, mat)   // and a rack
	if len(h.zones) > 0 do h.goods_v += 1   // a sleeping place's roof may have come or gone: it is shown again
	// The marks beside it may be workable now, and a dwarf resting for want of work looks again soon.
	for dy in i32(-2)..=2 do for dz in i32(-1)..=1 do for dx in i32(-1)..=1 do if k, ok := h.marked[at + {dx, dy, dz}]; ok && h.marks[k].wait != .Too_Hard && h.marks[k].taker < 0 {
		h.marks[k].wait, h.marks[k].tried, h.marks[k].by = .None, 0, -1
	}
	for &d in h.dwarves do if !d.job do d.rest = min(d.rest, 2)
	// A mark on a block the player's own hand dug or laid is done.
	if k, ok := h.marked[at]; ok && frame && (h.marks[k].work == .Dig) == (mat == .Air) && h.marks[k].work != .Fell do mark_remove(h, k, true)
}

// ---- no dwarf is shut in ----------------------------------------------------------------------

// The floors joined to one, up to POCKET of them, stamped with the walk's stamp; whether they are all there are.
flood :: proc(w: ^Walk, from: i32, first: u32, queue: ^[dynamic]i32) -> (closed: bool) {
	w.stamp += 1
	clear(queue)
	append(queue, from)
	w.seen[from] = w.stamp
	for n := 0; n < len(queue); n += 1 {
		if len(queue) >= POCKET do return false
		for way in 0..<8 do if t := floor_step(w, queue[n], way); t >= 0 && w.seen[t] != w.stamp {
			if w.seen[t] >= first do return false   // ground an earlier flood of this count found open
			w.seen[t] = w.stamp
			append(queue, t)
		}
	}
	return true
}

// How many dwarves stand in small closed ground beside a block, and one of them: ground of fewer
// than POCKET floors with no step out of it, a pit. Counted before and after a change, it says
// whether the change would shut a dwarf in.
pockets :: proc(h: ^Hold, at: [3]i32) -> (count: int, who: int) {
	started := time.now()
	defer {
		h.work.counts += 1
		h.work.counting += time.since(started)
	}
	w := &h.walk
	who = -1
	w.budget = ASKING
	first := w.stamp + 1
	queue := make([dynamic]i32, context.temp_allocator)
	for dz in i32(-1)..=1 do for dx in i32(-1)..=1 {
		x, z := at.x + dx, at.z + dz
		p := patch_at(w, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT)
		if p == nil do continue
		col := (z & (CHUNK - 1))*CHUNK + x & (CHUNK - 1)
		for k in p.first[col]..<p.first[col + 1] {
			seed := p.base + i32(k)
			if w.seen[seed] >= first || !flood(w, seed, first, &queue) do continue
			for d, i in h.dwarves do if d.doing != .Aboard && d.doing != .Dead {
				if f := walk_floor(w, d.cell.x, d.cell.y, d.cell.z, false); f >= 0 && w.seen[f] == w.stamp do count, who = count + 1, i
			}
		}
	}
	return
}

// The floors in the columns round a block, each with whether its ground is closed: fewer than POCKET
// floors joined by steps and no step out of them, a pit.
Beside :: struct { cell: [3]i32, closed: bool }
beside :: proc(h: ^Hold, at: [3]i32, out: ^[dynamic]Beside) {
	w := &h.walk
	w.budget = ASKING
	first := w.stamp + 1
	queue := make([dynamic]i32, context.temp_allocator)
	closed := make([dynamic]bool, context.temp_allocator)   // of each flood from `first` on
	for dz in i32(-1)..=1 do for dx in i32(-1)..=1 {
		x, z := at.x + dx, at.z + dz
		p := patch_at(w, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT)
		if p == nil do continue
		col := (z & (CHUNK - 1))*CHUNK + x & (CHUNK - 1)
		for k in p.first[col]..<p.first[col + 1] {
			seed := p.base + i32(k)
			if w.seen[seed] < first do append(&closed, flood(w, seed, first, &queue))
			append(out, Beside{floor_block(w, seed), closed[w.seen[seed] - first]})
		}
	}
}

// Whether digging a block would take the last step out of a pit: a floor beside it and no higher
// than it, with a way out today, would have none; or the floor on the block, with a way out today,
// would become one under it with none, a hole dug straight down; or a dwarf would be shut in. The
// block is taken out, the ground round it asked again, and it is put back. A ledge left on a slope
// over the block is no pit: nothing is dug from it and no dwarf comes to it.
closes :: proc(h: ^Hold, at: [3]i32, was: Mat) -> bool {
	w := &h.walk
	before := make([dynamic]Beside, context.temp_allocator)
	after := make([dynamic]Beside, context.temp_allocator)
	beside(h, at, &before)
	in_before, _ := pockets(h, at)
	walk_edit(w, {at.x, at.y, at.z, .Air})
	beside(h, at, &after)
	in_after, _ := pockets(h, at)
	walk_edit(w, {at.x, at.y, at.z, was})
	if in_after > in_before do return true
	on_it := false   // the floor on the block had a way out
	for b in before do on_it ||= !b.closed && b.cell == at + {0, 1, 0}
	for a in after do if a.closed && a.cell.y <= at.y {
		if on_it && a.cell.x == at.x && a.cell.z == at.z do return true
		for b in before do if !b.closed && b.cell == a.cell do return true
	}
	return false
}

// Whether a dwarf other than one is on a block, standing or on its way over it: the block is not
// dug from under it.
trodden :: proc(h: ^Hold, up: [3]i32, but: int) -> bool {
	for d, j in h.dwarves do if j != but && d.doing != .Aboard && d.doing != .Dead && d.cell == up do return true
	return false
}

// A dwarf with nothing to do that work would shut in walks out toward the one doing the work.
make_way :: proc(h: ^Hold, who, toward: int) {
	if who < 0 || who == toward do return
	d := &h.dwarves[who]
	if d.job || d.doing != .Waiting && d.doing != .Stopped do return
	w := &h.walk
	w.budget = ASKING
	to := h.dwarves[toward].cell
	if f := walk_near(w, to.x, to.y, to.z, 4, false, &h.held); f >= 0 {
		h.spots[who] = floor_block(w, f)
		d.doing, d.seek, d.wait, d.errand, d.rest = .Walking, true, 0, false, REST
	}
}

// An idle dwarf, when the ground has changed since it last looked: is it shut in? It says so once,
// and once more when it has a way out again. And it steps off a block that is marked.
idle_care :: proc(h: ^Hold, i: int) {
	d, w := &h.dwarves[i], &h.walk
	w.budget = ASKING
	f := walk_floor(w, d.cell.x, d.cell.y, d.cell.z)
	if f < 0 do return
	queue := make([dynamic]i32, context.temp_allocator)
	shut := flood(w, f, w.stamp + 1, &queue)
	if shut != d.shut {
		d.shut = shut
		h.at = feet_on(d.cell)
		if shut do say(h, "%s %s is shut in at %s: no way leads out of where it stands. A stair dug or built to it will let it out.", h.party[i].given, h.party[i].byname, place_say(h, d.cell))
		else do say(h, "%s %s has a way out again.", h.party[i].given, h.party[i].byname)
	}
	// Off a block marked to be dug, or out of one to be laid: to the nearest floor that is neither, and nobody's.
	if !on_mark(h, d.cell) do return
	for at in queue[:min(len(queue), 400)] {
		c := floor_block(w, at)
		if on_mark(h, c) || c in h.held || c in h.claims do continue
		h.spots[i] = c
		d.doing, d.seek, d.wait, d.errand, d.rest = .Walking, true, 0, false, REST
		return
	}
}

// Whether a dwarf standing in a cell stands on a block marked to be dug, in one to be laid, or in a stockpile.
on_mark :: proc(h: ^Hold, c: [3]i32) -> bool {   // nor does an idle dwarf stand in a stockpile, on what lies there; a sleeping place is to be stood and lain in
	if z, zoned := h.zoned[c]; zoned && !h.zones[z.zone].sleep do return true
	if c in h.benched do return true   // nor under a rack
	return c - {0, 1, 0} in h.marked || c in h.marked || c + {0, 1, 0} in h.marked
}

// A dwarf with nothing in hand: it looks for work when its rest is over, a few dwarves a tick, and
// one dwarf a tick looks to itself where the ground has changed, or where it stands on what is
// marked: one that ended its work on a marked block steps off it, or the block would wait for ever.
idle_tick :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if !h.cared && (d.checked != h.ground || (h.tick + i)%5 == 0 && on_mark(h, d.cell)) {
		h.cared, d.checked = true, h.ground
		idle_care(h, i)
		if d.doing == .Walking do return
	}
	if d.carrying > 0 && !d.haul.on {   // left standing with food in its arms, its mark taken back or its way lost: in with it
		basket_home(h, i)
		return
	}
	if care_look(h, i) do return   // thirst, hunger and sleep come before work (needs.odin)
	if d.rest > 0 {
		d.rest -= 1
		return
	}
	if h.looked >= LOOKS do return
	h.looked += 1
	if fire_first(h, i) do return   // a fire about to go out is fed, and the log one is to be laid of is brought, before any marked work
	if len(h.marks) > 0 && work_look(h, i) do return
	if len(h.fires) > 0 && fire_feed(h, i, false) do return  // nothing marked that it can take: it feeds a fire that is low,
	if len(h.goods) > 0 && haul_look(h, i) do return   // or it carries
	d.rest = REST + i%7
}

// ---- what the frame is shown ------------------------------------------------------------------

// Lay out the orders for the frame: every tick how each stands, and when a mark has come or gone
// the boxes still to dig and the trees and blocks marked. Called with the hold's mutex held.
orders_show :: proc(h: ^Hold) {
	s := &h.shown
	s.marks = len(h.marks)
	if h.shown_v == h.marks_v do return
	h.shown_v = h.marks_v
	clear(&s.sites)
	clear(&s.tints)
	clear(&s.ghosts)
	index := make([]int, len(h.sites), context.temp_allocator)
	for site, id in h.sites {
		index[id] = -1
		if site.over do continue
		index[id] = len(s.sites)
		append(&s.sites, Site_Seen{id = id, work = site.work, shape = site.shape, stuff = site.stuff, lo = site.lo, hi = site.hi, total = site.total, left = site.left, place = site.name, have = len(site.brought), coming = site.coming})
	}
	// The ground still to dig, as boxes of each order's marks, for the terrain to tint.
	digs := make([dynamic][3]i32, context.temp_allocator)
	boxes := make([dynamic][2][3]i32, context.temp_allocator)
	for site, id in h.sites do if !site.over && site.work == .Dig {
		clear(&digs)
		clear(&boxes)
		for m in h.marks do if m.site == id do append(&digs, m.at)
		boxes_of(digs[:], &boxes)
		for b in boxes do append(&s.tints, Tint{b[0], b[1], id})
	}
	for m in h.marks {
		seen := &s.sites[index[m.site]]
		if m.taker >= 0 do seen.busy += 1
		else do seen.waits[m.wait] += 1
		if m.work != .Dig do append(&s.ghosts, Ghost{m.at, m.work, h.sites[m.site].stuff, m.tall, m.site})
	}
}

// What an order waits for, in a sentence, or "" while every mark of it is in hand or free to take.
waits_words :: proc(s: Site_Seen, idle: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	n := 0
	for count, why in s.waits do if count > 0 && why != .None && why != .Front {
		fmt.sbprintf(&b, "%s%d where %s", "" if n == 0 else "; ", count, WAITS[why])
		n += 1
	}
	if n == 0 {
		if s.busy == 0 && s.waits[.None] > 0 && idle == 0 do return "Waits for a dwarf to be free"
		if s.busy == 0 && s.waits[.None] == 0 && s.waits[.Front] > 0 do return "No way in to it: dig a stair or a passage to it first"
		return ""
	}
	return fmt.tprintf("Waiting: %s", strings.to_string(b))
}
