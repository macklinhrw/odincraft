package main

import "core:fmt"
import "core:math"
import "core:strings"
import "core:sync"
import "core:time"

// Orders (plan.md, P3; docs/adr/0011): what the player asks of the hold beyond where to stand. An
// order marks blocks of the world: ground to dig, trees to fell, blocks to build. The marks are the
// hold's, and the dwarves take the work themselves: each idle dwarf chooses a marked block near it
// that its trade suits, walks to a floor it can work from, works for a time the material sets, and
// the block changes. Nobody is assigned by hand, and nothing counts on seven.
//
// What one-metre blocks make of digging. A dwarf stands under a block and a half and steps one
// block up or down, so:
//   a room or a passage is two blocks high: an order to dig a box one block high is dug two high,
//     the block marked and the one under it, so the cut that showed the mark shows the room;
//   a stair is a block to a step. Dug, it goes down a block a column from where the drag began,
//     with three blocks of room over each step; built, it goes up a block a column;
//   a wall stands two blocks over the block the drag began on, and down to the ground where that is
//     lower; a floor is one layer at the level the drag began on, and is the roof of what is under it.
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
// What is dug or felled goes to the hold's store as a count by kind, without being carried: rock by
// the kind of rock it is, in whatever form it lay; timber by the tree's kind; earth and sand are
// thrown aside. Building takes from the store.
//
// An orders file gives each as a line (hold.odin has the rest):
//   dig room|stair x y z x y z        the box between two blocks, the first where the drag began
//   fell x y z x y z                  every tree standing in the box's columns
//   build wall|floor|stair stone|timber x y z x y z
//   unmark x y z x y z                take back every order with a mark in the box

Work  :: enum u8 { Dig, Fell, Build }
Plan :: enum u8 { Room, Stair, Wall, Floor }
Stuff :: enum u8 { Stone, Timber }

// A kind of work is a row: what it is called, whose trade it is, and how much longer other hands take.
Work_Row :: struct {
	name, doing, done: string,
	hands:             [2]string,   // the trades whose work it is; for building, of stone and of timber
	slow:              f32,
}
WORKS := [Work]Work_Row{
	.Dig   = {"dig", "digging", "dug", {"miner", "miner"}, 2},
	.Fell  = {"fell", "felling", "felled", {"woodcutter", "carpenter"}, 2},
	.Build = {"build", "building", "built", {"mason", "carpenter"}, 2},
}
PLANS := [Plan]string{.Room = "room", .Stair = "stair", .Wall = "wall", .Floor = "floor"}
STUFFS := [Stuff]string{.Stone = "stone", .Timber = "timber"}

TOOLS      :: 0.8    // the strongest rock the party's picks cut (MATERIALS.strength); harder waits for better tools (P5)
DIG_BASE   :: 5.0    // seconds a miner takes over a block of earth or loose rock
DIG_ROCK   :: 60.0   // and more over solid rock, by the square of its strength: 9 s for mudstone, 39 for basalt (a guess)
FELL_BASE  :: 15.0   // seconds a woodcutter takes over a tree, and for each metre of its height
FELL_TALL  :: 3.0
LAY        :: 8.0    // seconds a mason takes to lay a block
POCKET     :: 3000   // floors of joined ground under which a place is a pit a dwarf can be shut in
LOOKS      :: 2      // dwarves that may look for work in one tick
TRIES      :: 12     // marks a dwarf looks at, the nearest first, before it rests
REST       :: 30     // ticks a dwarf that found no work waits before it looks again
AGAIN      :: 50     // ticks before a mark that could not be worked is looked at again
ORDER_MOST :: 8000   // blocks one order may mark

// Why a mark is not being worked, as the hold last found it.
Waits :: enum u8 { None, Front, No_Way, No_Room, Too_Hard, Rooted, No_Stuff, Loose, Stood_On, Shuts_In }
WAITS := [Waits]string{
	.None     = "",
	.Front    = "the blocks in front are dug first",
	.No_Way   = "no dwarf has a way to them",
	.No_Room  = "the places to work them from are taken",
	.Too_Hard = "their rock is too hard for the party's picks",
	.Rooted   = "a tree stands on them, and is felled first",
	.No_Stuff = "nothing is in store to build them from",
	.Loose    = "nothing lies beside them to lay them against",
	.Stood_On = "a dwarf stands in the way",
	.Shuts_In = "the work would shut a dwarf in",
}

Mark :: struct {
	at:    [3]i32,      // the block; of a tree, its foot
	site:  int,
	work:  Work,
	taker: int,         // the dwarf that has taken it, or -1
	wait:  Waits,
	tried: int,         // the tick it was last found unworkable
	tall:  i32,         // a tree's height
	tree:  Tree_Kind,
}
Got :: struct { mat: Mat, n: int }
Site :: struct {
	work:        Work,
	shape:       Plan,
	stuff:       Stuff,
	lo, hi:      [3]i32,            // the box its marks lie in
	a, b:        [3]i32,            // as it was ordered
	total, left: int,
	place, name: string,
	tally:       [dynamic]int,      // what each dwarf did of it
	got:         [dynamic]Got,      // what it gave the store
	joined:      [dynamic]bool,     // who has been said to take it up
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
	busy:        int,           // marks a dwarf has taken
	waits:       [Waits]int,    // and the rest, by what they wait for
	place:       string,
}
Tint :: struct { lo, hi: [3]i32, site: int }
Ghost :: struct { at: [3]i32, work: Work, stuff: Stuff, tall: i32, site: int }

// ---- shapes ---------------------------------------------------------------------------------

// Where an order's blocks are asked after: the dwarves' world asks its own ground, the frame the world it draws.
Blocks :: struct { at: proc(data: rawptr, b: [3]i32) -> Mat, data: rawptr }

// A stair's run: the axis it lies along (0 east, 2 south), which way it goes from where the drag began, and its steps.
stair_run :: proc(a, b: [3]i32) -> (axis: int, way, steps: i32) {
	axis = 0 if abs(b.x - a.x) >= abs(b.z - a.z) else 2
	return axis, -1 if b[axis] < a[axis] else 1, abs(b[axis] - a[axis]) + 1
}

// The boxes an order to dig covers, as geometry: a room's box, made two high if it is one; a stair's steps, a box each.
dig_boxes :: proc(shape: Plan, a, b: [3]i32, out: ^[dynamic][2][3]i32) {
	lo, hi := box_of(a, b)
	if shape != .Stair {
		if lo.y == hi.y do lo.y -= 1
		append(out, [2][3]i32{lo, hi})
		return
	}
	axis, way, steps := stair_run(a, b)
	for i in 0..<steps {
		l, h := lo, hi
		l[axis] = a[axis] + way*i
		h[axis] = l[axis]
		l.y, h.y = a.y - i, a.y - i + 2
		append(out, [2][3]i32{l, h})
	}
}

// The blocks an order marks, of the blocks as they stand: to dig, the solid ones of its boxes that
// are no plant's; to build, the open cells of its shape.
cells_of :: proc(work: Work, shape: Plan, a, b: [3]i32, src: Blocks, out: ^[dynamic][3]i32) {
	open :: proc(src: Blocks, c: [3]i32) -> bool { m := src.at(src.data, c); return m == .Air || is(m, LEAVES) }
	lo, hi := box_of(a, b)
	if (i64(hi.x - lo.x) + 1)*(i64(hi.z - lo.z) + 1)*(i64(hi.y - lo.y) + 3) > 8*ORDER_MOST do return
	switch work {
	case .Dig:
		boxes := make([dynamic][2][3]i32, context.temp_allocator)
		dig_boxes(shape, a, b, &boxes)
		for box in boxes do for y := box[1].y; y >= box[0].y; y -= 1 do for z in box[0].z..=box[1].z do for x in box[0].x..=box[1].x {
			if m := src.at(src.data, {x, y, z}); m != .Air && !is(m, PLANT_BLOCKS) do append(out, [3]i32{x, y, z})
		}
	case .Fell:
	case .Build:
		switch shape {
		case .Room, .Floor:
			for z in lo.z..=hi.z do for x in lo.x..=hi.x do if open(src, {x, a.y, z}) do append(out, [3]i32{x, a.y, z})
		case .Wall:
			for z in lo.z..=hi.z do for x in lo.x..=hi.x {
				foot := a.y + 3
				for foot > a.y - 5 && open(src, {x, foot - 1, z}) do foot -= 1   // down to the ground
				for y in foot..=a.y + 2 do append(out, [3]i32{x, y, z})
			}
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

// ---- materials ------------------------------------------------------------------------------

// The kind of rock a block is, in whatever form it lies; Air for earth, sand and plants, which the store does not keep.
rock_kind :: proc(m: Mat) -> Mat {
	if MATERIALS[m].strength > 0 do return m
	for r in Mat do if MATERIALS[r].strength > 0 && (MATERIALS[r].loose == m || FORMS[r].broken == m || FORMS[r].gravel == m) do return r
	return .Air
}

// Seconds a miner takes to cut a block.
dig_seconds :: proc(m: Mat) -> f32 { s := MATERIALS[m].strength; return DIG_BASE + DIG_ROCK*s*s }

// How a material cuts, in a word, for a card.
cut_words :: proc(m: Mat) -> string {
	s := MATERIALS[m].strength
	return "too hard for the party's picks" if s > TOOLS else "hard to cut" if s >= 0.6 else "firm" if s >= 0.4 else "soft rock, quick to cut" if s > 0 else "loose, quick to dig"
}

// What the store holds of a kind, in words: "basalt", "shii timber".
store_words :: proc(m: Mat) -> string {
	if is(m, bit_set[Trait]{.Bark}) do for sp in SPECIES do if sp.bark == m do return fmt.tprintf("%s timber", sp.name)
	return mat_words(m)
}

// The tree a bark is of, in words, for a card.
SPECIES_OF := #partial [Mat]string{.Wood = "tabu tree", .Shii_Bark = "shii tree", .Grey_Bark = "camellia or hisakaki", .Pine_Bark = "black pine"}

is_stuff :: proc(m: Mat, stuff: Stuff) -> bool { return is(m, bit_set[Trait]{.Bark}) if stuff == .Timber else MATERIALS[m].strength > 0 }

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
	return {proc(data: rawptr, b: [3]i32) -> Mat { m, _ := walk_block(&(cast(^Hold)data).walk, b); return m }, h}
}

site_thing :: proc(work: Work, shape: Plan) -> string {
	return "trees marked" if work == .Fell else "stair down" if work == .Dig && shape == .Stair else "room" if work == .Dig else "floor" if shape == .Floor || shape == .Room else PLANS[shape]
}

// The order as an orders file and the log give it.
order_words :: proc(o: Order) -> string {
	box := fmt.tprintf("%d %d %d %d %d %d", o.at.x, o.at.y, o.at.z, o.to.x, o.to.y, o.to.z)
	#partial switch o.kind {
	case .Dig:    return fmt.tprintf("dig %s %s", PLANS[o.shape], box)
	case .Fell:   return fmt.tprintf("fell %s", box)
	case .Build:  return fmt.tprintf("build %s %s %s", PLANS[o.shape], STUFFS[o.stuff], box)
	case .Unmark: return fmt.tprintf("unmark %s", box)
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
	if !done do return
	// What was done, and by whom.
	b := strings.builder_make(context.temp_allocator)
	n := s.total
	fmt.sbprintf(&b, "The %s %s %s: %d %s.", s.name, "are" if s.work == .Fell else "is", WORKS[s.work].done, n, "trees" if s.work == .Fell && n != 1 else "tree" if s.work == .Fell else "blocks" if n != 1 else "block")
	verb := "cut" if s.work == .Dig else "felled" if s.work == .Fell else "laid"
	first := true
	for count, i in s.tally do if count > 0 {
		fmt.sbprintf(&b, "%s %s %s %s %d", "" if first else ",", h.party[i].given, h.party[i].byname, verb, count)
		first = false
	}
	if !first do fmt.sbprint(&b, ".")
	if len(s.got) > 0 {
		fmt.sbprint(&b, " The store has gained")
		for g, i in s.got do fmt.sbprintf(&b, "%s %d of %s", "" if i == 0 else " and" if i == len(s.got) - 1 else ",", g.n, store_words(g.mat))
		fmt.sbprint(&b, ".")
	}
	h.at = site_middle(s)
	say(h, "%s", strings.to_string(b))
}

site_middle :: proc(s: ^Site) -> Maybe([3]f64) { return [3]f64{f64(s.lo.x + s.hi.x + 1)/2, f64(s.lo.y + s.hi.y + 1)/2, f64(s.lo.z + s.hi.z + 1)/2} }

// Obey an order to mark: to dig, to fell, to build, or to take marks back.
mark_obey :: proc(h: ^Hold, o: Order) {
	w := &h.walk
	bound(h.island)
	lo, hi := box_of(o.at, o.to)
	words := order_words(o)
	if o.kind == .Unmark {
		gone := make([dynamic]int, context.temp_allocator)
		for m in h.marks {
			inside := m.at.x >= lo.x && m.at.x <= hi.x && m.at.z >= lo.z && m.at.z <= hi.z && (m.work == .Fell || m.at.y >= lo.y - 1 && m.at.y <= hi.y + 1)
			known := false
			for s in gone do known ||= s == m.site
			if inside && !known do append(&gone, m.site)
		}
		for s in gone {
			h.sites[s].over = true
			for k := len(h.marks) - 1; k >= 0; k -= 1 do if h.marks[k].site == s do mark_remove(h, k, false)
		}
		b := strings.builder_make(context.temp_allocator)
		for s, i in gone do fmt.sbprintf(&b, "%s the %s", "" if i == 0 else " and" if i == len(gone) - 1 else ",", h.sites[s].name)
		if len(gone) == 0 do say(h, `The hold says "%s": nothing is marked there.`, words)
		else do say(h, `The hold says "%s": the order for%s is taken back.`, words, strings.to_string(b))
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
		if size := (i64(hi.x - lo.x) + 1)*(i64(hi.z - lo.z) + 1)*(i64(hi.y - lo.y) + 3); len(cells) > ORDER_MOST || size > 8*ORDER_MOST {
			pop(&h.sites)
			say(h, `The hold says "%s": that is more than one order may mark, %d blocks: mark less at a time.`, words, ORDER_MOST)
			return
		}
		for c in cells {
			if c in h.marked do continue
			m := Mark{at = c, site = id, work = work, taker = -1}
			if work == .Dig {
				was, _ := walk_block(w, c)
				over, _ := walk_block(w, c + {0, 1, 0})
				rooted += int(is(over, PLANT_BLOCKS))
				if MATERIALS[was].strength > TOOLS do m.wait, hard = .Too_Hard, hard + 1
			}
			mark_add(h, m)
		}
	case .Fell:
		trees := make([dynamic]Tree, context.temp_allocator)
		ox, oz := region.origin.x, region.origin.y
		trees_in(lo.x - ox, lo.z - oz, hi.x - ox, hi.z - oz, &trees)
		for t in trees {
			foot := [3]i32{t.x + ox, t.base, t.z + oz}
			if t.form == .Fallen || foot in h.marked || foot in w.edited do continue
			if m, _ := walk_block(w, foot); !is(m, PLANT_BLOCKS) do continue   // no stem or bush stands there
			mark_add(h, Mark{at = foot, site = id, work = .Fell, taker = -1, tall = t.height, tree = t.kind})
		}
	}
	s := &h.sites[id]
	thing := site_thing(work, o.shape)
	if work == .Build && o.shape == .Floor {   // a roof where most of it lies over open air
		over := 0
		for m in h.marks do if m.site == id do if under, _ := walk_block(w, m.at - {0, 1, 0}); under == .Air do over += 1
		thing = "roof" if 2*over > s.total else "floor"
	}
	s.name = fmt.aprintf("%s at %s", thing, s.place)
	h.at = site_middle(s)
	if s.total == 0 {
		s.over = true
		say(h, `The hold says "%s": nothing there to %s, so nothing is marked.`, words, WORKS[work].name)
		return
	}
	more := ""
	if hard > 0 do more = fmt.tprintf("%s; %d of them are of rock too hard for the party's picks", more, hard)
	if rooted > 0 do more = fmt.tprintf("%s; %d of them have a tree standing on them, which is felled first", more, rooted)
	switch work {
	case .Dig:   say(h, `The hold says "%s": a %s is marked to be dug at %s, %d blocks of it%s.`, words, thing, s.place, s.total, more)
	case .Fell:  say(h, `The hold says "%s": %d %s marked to be felled at %s.`, words, s.total, "tree is" if s.total == 1 else "trees are", s.place)
	case .Build: say(h, `The hold says "%s": a %s is marked to be built of %s at %s, %d blocks of it.`, words, thing, STUFFS[o.stuff], s.place, s.total)
	}
}

// ---- the dwarves' world: taking work ----------------------------------------------------------

// Whether a dwarf standing on a floor can work a block: beside it from a block under its feet to a
// block over its head, right over its head, or two under or over where the block between is open.
in_reach :: proc(h: ^Hold, cell, b: [3]i32) -> bool {
	dx, dy, dz := b.x - cell.x, b.y - cell.y, b.z - cell.z
	if abs(dx) > 1 || abs(dz) > 1 do return false
	if dx == 0 && dz == 0 do return dy == 2
	open :: proc(h: ^Hold, c: [3]i32) -> bool { m, _ := walk_block(&h.walk, c); return m == .Air || is(m, LEAVES) }
	switch dy {
	case -1, 0, 1: return true
	case -2: return open(h, b + {0, 1, 0})
	case 2:  return open(h, b - {0, 1, 0})
	}
	return false
}

// The floors a block can be worked from, the highest first, then the nearest the dwarf, that no other dwarf holds or is bound for.
stands_of :: proc(h: ^Hold, i: int, b: [3]i32, out: ^[dynamic][3]i32) -> (any: bool) {
	w, d := &h.walk, &h.dwarves[i]
	for dz in i32(-1)..=1 do for dx in i32(-1)..=1 {
		x, z := b.x + dx, b.z + dz
		p := patch_at(w, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT)
		if p == nil do continue
		col := (z & (CHUNK - 1))*CHUNK + x & (CHUNK - 1)
		for k in p.first[col]..<p.first[col + 1] {
			cell := [3]i32{x, i32(w.floors[p.base + i32(k)].y), z}
			if !in_reach(h, cell, b) do continue
			any = true
			if o, held := h.held[cell]; held && o != i do continue
			if o, claimed := h.claims[cell]; claimed && o != i do continue
			append(out, cell)
		}
	}
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + abs(a.y - b.y) }
	for a in 1..<len(out) do for k := a; k > 0 && (out[k].y > out[k - 1].y || out[k].y == out[k - 1].y && far(out[k], d.cell) < far(out[k - 1], d.cell)); k -= 1 do out[k], out[k - 1] = out[k - 1], out[k]
	return
}

// A dwarf lets its work go, and rests so many ticks before it looks for more.
job_drop :: proc(h: ^Hold, i: int, rest: int) {
	d := &h.dwarves[i]
	if !d.job do return
	if k, ok := h.marked[d.job_at]; ok && h.marks[k].taker == i {
		h.marks[k].taker = -1
		if h.marks[k].work == .Build do h.promised[h.sites[h.marks[k].site].stuff] -= 1
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
mark_waits :: proc(h: ^Hold, k: int, why: Waits) {
	m := &h.marks[k]
	if m.taker >= 0 do job_drop(h, m.taker, 10)
	if m.wait != why do h.marks_v += 1
	m.wait, m.tried = why, h.tick
}

// An idle dwarf looks for work: of the marks nobody has taken, the nearest it its trade suits
// first, it takes the first it can stand beside and has a way to. False if it found none.
work_look :: proc(h: ^Hold, i: int) -> bool {
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
		if m.taker >= 0 || m.wait == .Too_Hard || m.wait != .None && h.tick - m.tried < AGAIN do continue
		dx, dy, dz := f32(m.at.x - d.cell.x), f32(m.at.y - d.cell.y), f32(m.at.z - d.cell.z)
		score := (abs(dx) + abs(dz) + 2*abs(dy))*(1 if skilled(h.party[i], m.work, h.sites[m.site].stuff) else 2)
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
			if up in h.held {
				mark_waits(h, k, .Stood_On)
				continue
			}
			if over, _ := walk_block(w, up); is(over, PLANT_BLOCKS) {
				mark_waits(h, k, .Rooted)
				continue
			}
		case .Fell:
		case .Build:
			if have, _ := store_of(&h.store, s.stuff); have - h.promised[s.stuff] <= 0 {
				mark_waits(h, k, .No_Stuff)
				continue
			}
			if m.at in h.held || m.at - {0, 1, 0} in h.held {
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
		if any := stands_of(h, i, m.at, &stands); len(stands) == 0 {
			mark_waits(h, k, .No_Room if any else .Front)
			continue
		}
		found := false
		for stand in stands[:min(len(stands), 3)] {
			if stand != d.cell {
				clear(&w.shun)
				for o, j in h.dwarves do if j != i && o.doing != .Aboard && o.doing != .Walking do append(&w.shun, o.cell)
				_, why, _, _ := way_timed(h, d.cell, stand, &d.path)
				clear(&w.shun)
				if why != .Way do continue
			} else do clear(&d.path)
			// One whose trade it is not leaves it once for an idle dwarf whose trade it is.
			if !skilled(h.party[i], m.work, s.stuff) && !d.gave {
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
			if m.work == .Build do h.promised[s.stuff] += 1
			d.job, d.job_at, d.stand = true, m.at, stand
			h.claims[stand] = i
			h.spots[i] = stand
			d.doing, d.seek, d.next, d.wait, d.said, d.errand = .Walking, false, 1, 0, "", false
			for len(s.joined) < len(h.dwarves) {
				append(&s.joined, false)
				append(&s.tally, 0)
			}
			if !s.joined[i] {
				s.joined[i] = true
				h.aside = true
				say(h, "%s %s takes up the %s of the %s.", h.party[i].given, h.party[i].byname, WORKS[m.work].doing, s.name)
			}
			h.marks_v += 1
			found = true
			break
		}
		if found do return true
		mark_waits(h, k, .No_Way)
	}
	return false
}

// A dwarf has come to where it works from: it begins, for as long as the material and its trade make it.
work_begin :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	k, ok := h.marked[d.job_at]
	if !ok || h.marks[k].taker != i || !in_reach(h, d.cell, d.job_at) {
		job_drop(h, i, 10)
		d.doing = .Waiting
		return
	}
	m := h.marks[k]
	s := &h.sites[m.site]
	seconds: f32
	switch m.work {
	case .Dig:
		was, _ := walk_block(&h.walk, m.at)
		seconds, d.cut = dig_seconds(was), was
	case .Fell:
		seconds, d.cut = FELL_BASE + FELL_TALL*f32(m.tall), SPECIES[m.tree].bark
	case .Build:
		seconds = LAY
		_, d.cut = store_of(&h.store, s.stuff)
	}
	if !skilled(h.party[i], m.work, s.stuff) do seconds *= WORKS[m.work].slow
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
	if !in_reach(h, d.cell, d.job_at) {   // moved off its place, by a fall or by one squeezing past: it goes back
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
			if up in h.held {
				mark_waits(h, k, .Stood_On)
				return
			}
			// If a dwarf could stand on it, digging it may shut one in: counted before and after.
			stood := walk_floor(w, up.x, up.y, up.z) >= 0
			before, after, who := 0, 0, -1
			if stood do before, _ = pockets(h, m.at)
			walk_edit(w, {m.at.x, m.at.y, m.at.z, .Air})
			if stood do after, who = pockets(h, m.at)
			if after > before {
				walk_edit(w, {m.at.x, m.at.y, m.at.z, was})
				mark_waits(h, k, .Shuts_In)
				make_way(h, who, i)
				return
			}
			ground_changed(h, m.at, .Air, false)
			if kind := rock_kind(was); kind != .Air do store_add(h, s, kind, 1)
		}
	case .Build:
		have, mat := store_of(&h.store, s.stuff)
		if have == 0 {
			mark_waits(h, k, .No_Stuff)
			return
		}
		if m.at in h.held || m.at - {0, 1, 0} in h.held {
			mark_waits(h, k, .Stood_On)
			return
		}
		was, _ := walk_block(w, m.at)
		before, _ := pockets(h, m.at)
		walk_edit(w, {m.at.x, m.at.y, m.at.z, mat})
		if after, who := pockets(h, m.at); after > before {
			walk_edit(w, {m.at.x, m.at.y, m.at.z, was})
			mark_waits(h, k, .Shuts_In)
			make_way(h, who, i)
			return
		}
		ground_changed(h, m.at, mat, false)
		h.store[mat] -= 1
	case .Fell:
		grain := GRAIN
		bark := SPECIES[m.tree].bark
		walk_edit(w, {m.at.x, m.at.y, m.at.z, grain[bark][0]})
		ground_changed(h, m.at, grain[bark][0], false)
		h.at = feet_on(m.at)
		if m.tree == .Scrub do say(h, "%s %s clears a bush of scrub.", h.party[i].given, h.party[i].byname)   // brush: no timber in it
		else {
			timber := max(int(m.tall)/2, 1)
			store_add(h, s, bark, timber)
			say(h, "%s %s fells a %s tree %d m tall: %d of timber for the store.", h.party[i].given, h.party[i].byname, SPECIES[m.tree].name, m.tall, timber)
		}
	}
	s.tally[i] += 1
	h.work.done += 1
	job_drop(h, i, 0)
	d.doing = .Waiting
	if k2, still := h.marked[m.at]; still do mark_remove(h, k2, true)
	// It looks for the next at once, before any that stand idle: the one at the face goes on at the face.
	if len(h.marks) > 0 && !work_look(h, i) do d.rest = 10
}

store_add :: proc(h: ^Hold, s: ^Site, m: Mat, n: int) {
	h.store[m] += i32(n)
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
		append(&h.out, Edit{at.x, at.y, at.z, mat})
		sync.unlock(&h.mutex)
	}
	felled := is(mat, RINGS)
	r := i32(TREE_REACH + 1) if felled else 0
	for d, i in h.dwarves do if d.doing != .Aboard && (d.adrift || abs(d.cell.x - at.x) <= r && abs(d.cell.z - at.z) <= r) do settle(h, i, felled || mat == .Air && at.y < d.cell.y)
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
	// The marks beside it may be workable now, and a dwarf resting for want of work looks again soon.
	for dy in i32(-2)..=2 do for dz in i32(-1)..=1 do for dx in i32(-1)..=1 do if k, ok := h.marked[at + {dx, dy, dz}]; ok && h.marks[k].wait != .Too_Hard && h.marks[k].taker < 0 {
		h.marks[k].wait, h.marks[k].tried = .None, 0
	}
	for &d in h.dwarves do if !d.job do d.rest = min(d.rest, 5)
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
			for d, i in h.dwarves do if d.doing != .Aboard {
				if f := walk_floor(w, d.cell.x, d.cell.y, d.cell.z, false); f >= 0 && w.seen[f] == w.stamp do count, who = count + 1, i
			}
		}
	}
	return
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
	marked :: proc(h: ^Hold, c: [3]i32) -> bool { return c - {0, 1, 0} in h.marked || c in h.marked || c + {0, 1, 0} in h.marked }
	if !marked(h, d.cell) do return
	for at in queue[:min(len(queue), 400)] {
		c := floor_block(w, at)
		if marked(h, c) || c in h.held || c in h.claims do continue
		h.spots[i] = c
		d.doing, d.seek, d.wait, d.errand, d.rest = .Walking, true, 0, false, REST
		return
	}
}

// A dwarf with nothing in hand: it looks for work when its rest is over, a few dwarves a tick, and
// one dwarf a tick looks to itself where the ground has changed.
idle_tick :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if !h.cared && d.checked != h.ground {
		h.cared, d.checked = true, h.ground
		idle_care(h, i)
		if d.doing == .Walking do return
	}
	if d.rest > 0 {
		d.rest -= 1
		return
	}
	if len(h.marks) == 0 || h.looked >= LOOKS do return
	h.looked += 1
	if !work_look(h, i) do d.rest = REST + i%7
}

// ---- what the frame is shown ------------------------------------------------------------------

// Lay out the orders for the frame: every tick how each stands, and when a mark has come or gone
// the boxes still to dig and the trees and blocks marked. Called with the hold's mutex held.
orders_show :: proc(h: ^Hold) {
	s := &h.shown
	s.store = h.store
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
		append(&s.sites, Site_Seen{id = id, work = site.work, shape = site.shape, stuff = site.stuff, lo = site.lo, hi = site.hi, total = site.total, left = site.left, place = site.name})
		if site.work == .Dig {
			boxes := make([dynamic][2][3]i32, context.temp_allocator)
			dig_boxes(site.shape, site.a, site.b, &boxes)
			for b in boxes do append(&s.tints, Tint{b[0], b[1], id})
		}
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
		if s.busy == 0 && s.waits[.None] == 0 && s.waits[.Front] > 0 do return "Waits: no dwarf can come at any block of it"
		return ""
	}
	return fmt.tprintf("Waiting: %s", strings.to_string(b))
}
