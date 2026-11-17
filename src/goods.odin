package main

import "base:builtin"
import "core:fmt"
import "core:math"
import "core:strings"

// Goods (plan.md, "Goods you can see", 2026-11-16; docs/adr/0012): what the dwarves' work yields is
// a thing that lies in the world, where it was dug or felled, and is seen and clicked. The player
// marks ground for it, a stockpile, and the dwarves carry it there; what the hold has is what lies
// in its stockpiles. Building takes real things from where they lie.
//
// It is done as the games this is measured by do it (interesting-world/notes/colony-sim-reference.md,
// sections 6 and 7). A thing lies in a cell, things of one kind together up to a stack, as
// RimWorld's stackCount and Ingnomia's StackSize. A stockpile is cells of ground the player dragged
// over, with what it takes (RimWorld's Zone_Stockpile and its filter). Carrying arises from things
// not lying in a stockpile that takes them (ListerHaulables): a dwarf with no more pressing work
// takes the nearest such pile to the nearest place for it (StoreUtility), a few at a time. A block
// marked to be laid waits for its stuff to be brought (a blueprint), then holds it (a frame), then
// is laid: the nearest of the stuff is fetched wherever it lies, stored or loose
// (WorkGiver_ConstructDeliverResources).
//
// An orders file gives a stockpile as a line (hold.odin has the rest):
//   store all|stone|timber x y z x y z   the ground of the box's columns, at the level of its first block
//   unstore x y z x y z                  the whole stockpile whose ground the first block is, is removed
//   takes all|stone|timber x y z x y z   and from now it takes this
// and `unmark` over a stockpile with no mark and no built block in its columns takes that ground out of it.

HEAP :: 8   // things of one kind that lie in one cell: RimWorld stacks 75 of a resource and one chunk of stone, Ingnomia ten stones; eight are a heap a dwarf's cell holds and the eye counts
ARMFUL :: 4   // and that a dwarf carries at once
BASKET :: 24   // of food, which is small: a heap of it in a cell, and a third of that carried (RimWorld stacks 75 berries and 10 meals)

// How many things of a kind lie in one cell, and how many of it a dwarf carries at once.
heap_of :: proc(m: Mat) -> i32 { return BASKET if is(m, FOOD) else HEAP }
armful_of :: proc(m: Mat) -> i32 { return BASKET/3 if is(m, FOOD) else ARMFUL }

Takes :: enum u8 { All, Stone, Timber, Food }
TAKES := [Takes]string{.All = "all", .Stone = "stone", .Timber = "timber", .Food = "food"}
TAKES_SAYS := [Takes]string{.All = "everything", .Stone = "stone", .Timber = "timber", .Food = "food"}

Good :: struct {
	at:   [3]i32,   // the cell it lies in: the one a dwarf's feet would be in
	kind: Mat,      // rock by its kind; timber by its tree's bark, or sawn
	n:    i32,
	held: i32,      // of them, promised to dwarves on their way to fetch them
	// Of food that spoils (goods_spoil):
	age:  f32,      // days it has lain, counted as days of mild air
	left: f32,      // days it has left as it lies now
	walled: bool,   // it lies indoors, where the air is nearer the year's mean,
	read: int,      // as the ground stood when that was last asked (Hold.ground), from 1
	tried: int,     // the tick a dwarf last found no way to it for a rack: it is left a while
}
Stockpile :: struct { takes: Takes, cells: int, sleep: bool }   // sleep: it is no stockpile but a place to sleep, marked and kept as one is (shelter.odin)
Zone_Cell :: struct { zone: int, coming: i32 }   // coming: things on their way to it
Laid_Block :: struct { at: [3]i32, plan: Plan, on: bool }   // a block the dwarves laid, and as what; or one that stands no longer
Haul :: struct {
	on:       bool,
	bringing: bool,     // it has the things, and walks to where they go
	from, to: [3]i32,
	kind:     Mat,
	n:        i32,
	site:     int,      // the order to build they are for, or -1 for a stockpile
	fire:     bool,     // they are timber for a fire,
	hearth:   [3]i32,   // which burns in this cell (shelter.odin); or the cell of the bench they are for
	bench:    bool,     // they are for a bench to make something of (bench.odin),
	off:      bool,     // or are what it made, taken off it
	age:      f32,      // of food: how long it had lain (Good.age)
}

// Whether a dwarf standing in a cell of the hold's ground has a roof over it (shelter.odin).
roofed_at :: proc(h: ^Hold, c: [3]i32) -> bool { return roofed(hold_blocks(h), c) }

// What the frame may know of the goods: every pile, and the stockpiles as boxes of their ground.
Pile_Seen :: struct { at: [3]i32, kind: Mat, n: i32, stored: bool, left: f32 }   // left: days before it spoils as it lies; under nothing for what does not
Zone_Seen :: struct { id: int, takes: Takes, cells, full: int, sleep: bool, roofed, walled: int }   // of a sleeping place: how many of its places are under a roof, and how many of those indoors

takes_kind :: proc(t: Takes, m: Mat) -> bool {
	return t == .All || t == .Stone && is_stuff(m, .Stone) || t == .Timber && is_stuff(m, .Timber) || t == .Food && is(m, FOOD)
}

// Whether a pile lies where the hold counts it: in a stockpile that takes its kind.
stored :: proc(h: ^Hold, g: Good) -> bool {
	c, ok := h.zoned[g.at]
	return ok && !h.zones[c.zone].sleep && takes_kind(h.zones[c.zone].takes, g.kind)
}

// ---- things lying ---------------------------------------------------------------------------

// Put things into a cell: onto a pile of their kind there while it has room, and the rest into the
// nearest cells that a dwarf could stand in and that hold none or the same, spreading as a heap
// does. Where no such cell lies within three steps they stay in the first, over the stack.
good_put :: proc(h: ^Hold, at: [3]i32, kind: Mat, n: i32, age: f32 = 0) {
	if n <= 0 do return
	w := &h.walk
	left := n
	h.goods_v += 1
	fill :: proc(h: ^Hold, c: [3]i32, kind: Mat, left: ^i32, age: f32, over := false) {
		if k, ok := h.lying[c]; ok {
			g := &h.goods[k]
			if g.kind != kind do return
			room := left^ if over else min(left^, heap_of(kind) - g.n)
			if room <= 0 do return
			g.age = (g.age*f32(g.n) + age*f32(room))/f32(g.n + room)   // a heap is as old as its things together: RimWorld's stack takes the mean of the two (CompRottable.PreAbsorbStack)
			g.n += room
			left^ -= room
			return
		}
		if !over && (c in h.burning || c in h.benched) do return   // nothing is laid in a fire or under a rack, while there is room beside it
		room := left^ if over else min(left^, heap_of(kind))
		h.lying[c] = len(h.goods)
		append(&h.goods, Good{at = c, kind = kind, n = room, age = age, left = keeps_left(kind, age, 1)})
		left^ -= room
	}
	fill(h, at, kind, &left, age)
	for r in i32(1)..=3 {
		if left == 0 do return
		for dz in -r..=r do for dx in -r..=r do if max(abs(dx), abs(dz)) == r do for dy in ([3]i32{0, -1, 1}) {
			c := at + {dx, dy, dz}
			if left > 0 && walk_floor(w, c.x, c.y, c.z) >= 0 && (c in h.zoned) == (at in h.zoned) do fill(h, c, kind, &left, age)   // a heap spreads within its stockpile, or outside every one
		}
	}
	if left > 0 do fill(h, at, kind, &left, age, true)
}

// Things come to lie where a block was: in its cell if there is ground under it, and else on the
// first ground below.
good_drop :: proc(h: ^Hold, at: [3]i32, kind: Mat, n: i32, age: f32 = 0) {
	w := &h.walk
	c := at
	for _ in 0..<64 {
		under, _ := walk_block(w, c - {0, 1, 0})
		if under != .Air && !is(under, LEAVES) do break
		c.y -= 1
	}
	good_put(h, c, kind, n, age)
}

// Take things from a pile; the pile is gone with its last.
good_take :: proc(h: ^Hold, k: int, n: i32) {
	g := &h.goods[k]
	g.n -= n
	h.goods_v += 1
	if g.n > 0 do return
	delete_key(&h.lying, g.at)
	last := len(h.goods) - 1
	if k != last {
		h.goods[k] = h.goods[last]
		h.lying[h.goods[k].at] = k
	}
	pop(&h.goods)
}

// A block changed: a pile lying on a block dug away falls with the ground, and one in a cell where
// a block was laid is moved out of it.
goods_settle :: proc(h: ^Hold, at: [3]i32, mat: Mat) {
	c := at + {0, 1, 0} if mat == .Air else at
	k, ok := h.lying[c]
	if !ok do return
	g := h.goods[k]
	good_take(h, k, g.n)
	if mat == .Air do good_drop(h, c, g.kind, g.n, g.age)
	else do good_put(h, at + {0, 1, 0}, g.kind, g.n, g.age)
}

// ---- stockpiles -----------------------------------------------------------------------------

// The cells a stockpile's order covers: in each column of its box, the place a dwarf can stand
// nearest the level over the block the drag began on, within two blocks: it follows a slope.
zone_cells :: proc(a, b: [3]i32, src: Blocks, out: ^[dynamic][3]i32) {
	lo, hi := box_of(a, b)
	if (i64(hi.x - lo.x) + 1)*(i64(hi.z - lo.z) + 1) > ORDER_MOST do return
	for z in lo.z..=hi.z do for x in lo.x..=hi.x do for dy in ([5]i32{0, 1, -1, 2, -2}) {
		if c := ([3]i32{x, a.y + 1 + dy, z}); stands_at(src, c) {
			append(out, c)
			break
		}
	}
}

// Obey an order for a stockpile: the ground is its own, joined to a stockpile beside it that takes
// the same, and one that took something else gives the ground up.
zone_obey :: proc(h: ^Hold, o: Order) {
	cells := make([dynamic][3]i32, context.temp_allocator)
	zone_cells(o.at, o.to, hold_blocks(h), &cells)
	words := order_words(o)
	h.at = feet_on({(o.at.x + o.to.x)/2, o.at.y + 1, (o.at.z + o.to.z)/2})
	if len(cells) == 0 {
		h.short = "No ground to store on there."
		say(h, `The hold says "%s": no ground a dwarf could stand on lies there, so no stockpile is marked.`, words)
		return
	}
	id := -1
	for c in cells do for side in ([5][3]i32{{0, 0, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}) do for dy in i32(-1)..=1 {
		if n, ok := h.zoned[c + side + {0, dy, 0}]; ok && id < 0 && h.zones[n.zone].takes == o.takes && h.zones[n.zone].sleep == (o.kind == .Sleep) do id = n.zone
	}
	joined := id >= 0
	if !joined {
		id = len(h.zones)
		append(&h.zones, Stockpile{takes = o.takes, sleep = o.kind == .Sleep})
	}
	added := 0
	for c in cells {
		if was, ok := h.zoned[c]; ok {
			if was.zone == id do continue
			h.zones[was.zone].cells -= 1
		}
		h.zoned[c] = {zone = id}
		h.zones[id].cells += 1
		added += 1
	}
	h.goods_v += 1
	for &d in h.dwarves do if !d.job && !d.haul.on do d.rest = min(d.rest, 2)
	if o.kind == .Sleep {   // a place to sleep: how much of it has a roof is said, since that is what it is for
		roofed := 0
		for c in cells do roofed += int(roofed_at(h, c))
		under := "all under a roof" if roofed == len(cells) else "none of them under a roof" if roofed == 0 else fmt.tprintf("%d of them under a roof", roofed)
		h.short = fmt.tprintf("Sleeping place: %d places%s, %s.", h.zones[id].cells, fmt.tprintf(", %d of them new", added) if joined else "", under)
		say(h, `The hold says "%s": %d places are marked to sleep in, %s, %s. The dwarves lie down there at night, under its roof first.`, words, added, under, "joined to the sleeping place beside them" if joined else "a new sleeping place")
		return
	}
	h.short = fmt.tprintf("Stockpile for %s: %d places%s.", TAKES_SAYS[o.takes], h.zones[id].cells, fmt.tprintf(", %d of them new", added) if joined else "")
	say(h, `The hold says "%s": %d places are marked to store %s, %s.`, words, added, TAKES_SAYS[o.takes], "joined to the stockpile beside them" if joined else "a new stockpile")
}

// A stockpile taken in the hand and changed as a whole, as RimWorld's zone is deleted or its filter
// set from the zone selected, and Dwarf Fortress's stockpile from its own panel: removed, with what
// lay in it left lying loose; or told to take something else, after which what it no longer takes is
// loose and is carried to a place that does.
zone_change :: proc(h: ^Hold, o: Order) {
	words := order_words(o)
	cell, ok := h.zoned[o.at + {0, 1, 0}]
	h.at = feet_on(o.at + {0, 1, 0})
	if !ok {
		h.short = "No stockpile there."
		say(h, `The hold says "%s": no stockpile's ground is there.`, words)
		return
	}
	id := cell.zone
	if h.zones[id].sleep {   // a sleeping place takes nothing, and is removed as a stockpile is
		if o.kind == .Takes {
			h.short = "A sleeping place takes nothing."
			say(h, `The hold says "%s": that ground is a place to sleep, and takes nothing.`, words)
			return
		}
		cells := make([dynamic][3]i32, context.temp_allocator)
		for c, z in h.zoned do if z.zone == id do append(&cells, c)
		for c in cells do delete_key(&h.zoned, c)
		h.zones[id].cells = 0
		h.goods_v += 1
		h.short = fmt.tprintf("Sleeping place removed: %d places.", len(cells))
		say(h, `The hold says "%s": the sleeping place is removed, %d places of it.`, words, len(cells))
		return
	}
	if o.kind == .Takes {
		h.zones[id].takes = o.takes
		h.short = fmt.tprintf("The stockpile takes %s from now.", TAKES_SAYS[o.takes])
		say(h, `The hold says "%s": the stockpile of %d places takes %s from now.`, words, h.zones[id].cells, TAKES_SAYS[o.takes])
	} else {
		cells := make([dynamic][3]i32, context.temp_allocator)
		lying := 0
		for c, z in h.zoned do if z.zone == id {
			append(&cells, c)
			for g in h.goods do if g.at == c do lying += int(g.n)
		}
		for c in cells do delete_key(&h.zoned, c)
		h.zones[id].cells = 0
		h.short = fmt.tprintf("Stockpile removed: %d places%s.", len(cells), fmt.tprintf("; %d things lie loose", lying) if lying > 0 else "")
		say(h, `The hold says "%s": the stockpile for %s is removed, %d places of it; %d things that lay in it lie loose.`, words, TAKES_SAYS[h.zones[id].takes], len(cells), lying)
	}
	h.goods_v += 1
	for &d in h.dwarves do if !d.job && !d.haul.on do d.rest = min(d.rest, 2)
}

// Take the ground of a box's columns out of every stockpile: how many places went. What lies there stays, loose.
zone_remove :: proc(h: ^Hold, lo, hi: [3]i32) -> (gone: int) {
	cells := make([dynamic][3]i32, context.temp_allocator)
	for c in h.zoned do if c.x >= lo.x && c.x <= hi.x && c.z >= lo.z && c.z <= hi.z do append(&cells, c)
	for c in cells {
		h.zones[h.zoned[c].zone].cells -= 1
		delete_key(&h.zoned, c)
	}
	if len(cells) > 0 do h.goods_v += 1
	return len(cells)
}

// ---- carrying -------------------------------------------------------------------------------

// The best place for a pile's things: the cell of a stockpile that takes them, with room, nearest
// the pile. RimWorld takes the nearest good cell of the best stockpile; here every stockpile is as good.
store_cell :: proc(h: ^Hold, g: Good) -> (to: [3]i32, room: i32, ok: bool) {
	best := max(i32)
	for c, cell in h.zoned {
		if h.zones[cell.zone].sleep || !takes_kind(h.zones[cell.zone].takes, g.kind) || c == g.at do continue
		free := heap_of(g.kind) - cell.coming
		if k, lies := h.lying[c]; lies {
			if h.goods[k].kind != g.kind do continue
			free -= h.goods[k].n
		}
		if free <= 0 do continue
		d := abs(c.x - g.at.x) + abs(c.z - g.at.z) + 2*abs(c.y - g.at.y)
		if d < best || d == best && (c.x < to.x || c.x == to.x && (c.z < to.z || c.z == to.z && c.y < to.y)) do best, to, room, ok = d, c, free, true   // the same answer whatever order the map gives its cells in
	}
	return
}

// What the stockpiles have room for: an empty place, by what its stockpile takes, and more of the
// kind of a heap that is not full; and whether any stockpile takes a class of things at all.
Store_Room :: struct { empty: [Takes]i32, partly: [dynamic]Mat, takes: [Takes]bool }
room_read :: proc(h: ^Hold) -> (r: Store_Room) {
	for &e in r.empty do e = max(i32)
	r.partly = make([dynamic]Mat, context.temp_allocator)
	for z in h.zones do if !z.sleep && z.cells > 0 do r.takes[z.takes] = true
	for c, cell in h.zoned {
		z := h.zones[cell.zone]
		if z.sleep do continue
		if k, lies := h.lying[c]; !lies do r.empty[z.takes] = min(r.empty[z.takes], cell.coming)
		else if g := h.goods[k]; takes_kind(z.takes, g.kind) && g.n + cell.coming < heap_of(g.kind) do append(&r.partly, g.kind)
	}
	return
}
room_fits :: proc(r: ^Store_Room, kind: Mat) -> bool {
	for coming, t in r.empty do if coming < heap_of(kind) && takes_kind(t, kind) do return true
	for m in r.partly do if m == kind do return true
	return false
}
// The class of a thing, as a stockpile takes it: stone, timber or food.
takes_of :: proc(m: Mat) -> Takes { return .Food if is(m, FOOD) else .Timber if is_stuff(m, .Timber) else .Stone }

// How many blocks an order to build still wants brought: those marked, less what lies at it and what is coming.
site_wants :: proc(h: ^Hold, id: int) -> int {
	s := &h.sites[id]
	if s.over || s.work != .Build do return 0
	return s.left - len(s.brought) - s.coming
}

// A dwarf fetches stuff for an order to build that still wants some: the nearest of it, wherever it
// lies, to a floor one of the order's blocks can be laid from. False if the order wants none, none
// lies anywhere, or no way leads.
site_haul :: proc(h: ^Hold, i: int, id: int) -> bool {
	d, w := &h.dwarves[i], &h.walk
	w.budget = ASKING
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + 2*abs(a.y - b.y) }
	s := &h.sites[id]
	want := site_wants(h, id)
	if want <= 0 do return false
	// A floor one of its blocks can be laid from, that the dwarf has a way to: the stuff is brought where a mason
	// will stand. (A floor merely near a block may be the top of a wall two high, which nobody comes to.)
	to, found := [3]i32{}, false
	stands := make([dynamic][3]i32, context.temp_allocator)
	way := make([dynamic][3]i32, context.temp_allocator)
	tried := 0
	for m in h.marks do if m.site == id && !found && tried < 6 {
		clear(&stands)
		stands_of(h, i, m.at, &stands, true)
		for stand in stands[:min(len(stands), 2)] {
			tried += 1
			if stand != d.cell do if _, why, _, _ := way_timed(h, d.cell, stand, &way); why != .Way do continue
			to, found = stand, true
			break
		}
	}
	if !found do return false
	best, pick := max(i32), -1
	for g, k in h.goods do if is_stuff(g.kind, s.stuff) && g.n - g.held > 0 {
		if f := far(g.at, to); f < best || f == best && k < pick do best, pick = f, k
	}
	if pick < 0 do return false
	g := &h.goods[pick]
	n := min(i32(want), ARMFUL, g.n - g.held)
	if !haul_set(h, i, {on = true, from = g.at, to = to, kind = g.kind, n = n, site = id}) do return false
	g.held += n
	s.coming += int(n)
	return true
}

// A dwarf with no marked work it can take looks for something to carry: stuff for a block marked
// to be laid first, from the nearest pile of it wherever it lies; then a pile lying loose, to the
// stockpile that takes it. False if there is nothing to carry.
haul_look :: proc(h: ^Hold, i: int) -> bool {
	d, w := &h.dwarves[i], &h.walk
	w.budget = ASKING
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + 2*abs(a.y - b.y) }
	// For building.
	for _, id in h.sites do if site_haul(h, i, id) do return true
	// To a bench that has room for what it makes something of, and from one that has made it (bench.odin).
	if len(h.benches) > 0 && (bench_load(h, i) || bench_unload(h, i)) do return true
	// To a stockpile: the nearest pile that lies loose, or in a stockpile that does not take it.
	stores := false
	for z in h.zones do stores ||= !z.sleep && z.cells > 0
	if !stores do return false
	// A heap nothing has room for is no try: with the food stockpiles full the six nearest heaps were all food, and
	// timber farther off lay loose for a year beside an empty stockpile (plan.md, "A first year").
	room := room_read(h)
	Near :: struct { far: i32, k: int }
	tries: [6]Near
	count := 0
	for g, k in h.goods do if g.n - g.held > 0 && !stored(h, g) && room_fits(&room, g.kind) {
		f := far(g.at, d.cell)
		at := min(count, len(tries) - 1)
		if count == len(tries) && f >= tries[at].far do continue
		for at > 0 && tries[at - 1].far > f {
			tries[at] = tries[at - 1]
			at -= 1
		}
		tries[at] = {f, k}
		count = min(count + 1, len(tries))
	}
	for t in tries[:count] {
		g := &h.goods[t.k]
		to, room, ok := store_cell(h, g^)
		if !ok do continue
		n := min(room, armful_of(g.kind), g.n - g.held)
		if !haul_set(h, i, {on = true, from = g.at, to = to, kind = g.kind, n = n, site = -1}) do continue
		g.held += n
		cell := &h.zoned[to]
		cell.coming += n
		return true
	}
	return false
}

// A dwarf sets out to fetch: true if a way leads to the pile.
haul_set :: proc(h: ^Hold, i: int, haul: Haul) -> bool {
	d, w := &h.dwarves[i], &h.walk
	from := haul.from
	if walk_floor(w, from.x, from.y, from.z) < 0 {
		f := walk_near(w, from.x, from.y, from.z, 2)
		if f < 0 do return false
		from = floor_block(w, f)
	}
	if from != d.cell {
		clear(&w.shun)
		_, why, _, _ := way_timed(h, d.cell, from, &d.path)
		if why != .Way do return false
	} else do clear(&d.path)
	d.haul = haul
	h.spots[i] = from
	d.doing, d.seek, d.next, d.wait, d.said, d.errand = .Walking, false, 1, 0, "", false
	return true
}

// A dwarf carrying has come to the end of its way: at the pile it takes the things up and sets out
// with them; where they go it lays them down, or hands them to the order they are for.
haul_arrive :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	haul := d.haul
	if !haul.bringing {
		k, ok := h.lying[haul.from]
		got := i32(0)
		if haul.bench && haul.off do got = bench_take(h, haul.hearth, haul.n)   // off the bench, not from a pile
		else if ok && h.goods[k].kind == haul.kind {
			g := &h.goods[k]
			g.held = max(g.held - haul.n, 0)
			got = min(haul.n, g.n)
			d.haul.age = g.age
			good_take(h, k, got)
		}
		if got < haul.n {   // fewer were there than it came for
			if haul.fire {
				if k, burns := h.burning[haul.hearth]; burns do h.fires[k].coming = max(h.fires[k].coming - (haul.n - got), 0)
			} else if haul.bench && !haul.off do bench_unpromise(h, haul.hearth, haul.n - got)
			else if haul.site >= 0 do h.sites[haul.site].coming -= int(haul.n - got)
			else if c, zoned := &h.zoned[haul.to]; zoned do c.coming -= haul.n - got
		}
		if got == 0 {
			d.haul = {}
			d.doing, d.rest = .Waiting, 0
			return
		}
		d.carry, d.carrying = haul.kind, got
		d.haul.n, d.haul.bringing = got, true
		h.spots[i] = haul.to
		d.doing, d.seek, d.wait = .Walking, true, 0
		h.goods_v += 1
		return
	}
	d.haul = {}
	d.doing, d.rest = .Waiting, 0
	n := d.carrying
	d.carrying = 0
	h.goods_v += 1
	if haul.fire {   // onto the fire; or, if it is gone, down where the dwarf stands
		if !fire_fed(h, i, haul.hearth, haul.kind, n) do good_put(h, d.cell, haul.kind, n)
		return
	}
	if haul.bench && !haul.off {   // onto the bench; and what it has no room for, or all if it is gone, down where the dwarf stands
		if took := bench_put(h, haul.hearth, haul.kind, n); took < n do good_put(h, d.cell, haul.kind, n - took, haul.age)
		return
	}
	if haul.site >= 0 && !h.sites[haul.site].over {
		s := &h.sites[haul.site]
		s.coming -= int(n)
		for _ in 0..<n do append(&s.brought, haul.kind)
		h.marks_v += 1
		for &m in h.marks do if m.site == haul.site && m.wait == .No_Stuff do m.wait, m.tried, m.by = .None, 0, -1
		return
	}
	if c, zoned := &h.zoned[haul.to]; zoned && haul.site < 0 do c.coming = max(c.coming - n, 0)
	good_put(h, d.cell if haul.site >= 0 else haul.to, haul.kind, n, haul.age)
}

// A gatherer or a fisher with food in its arms carries it in: to a rack that makes something of it
// and has room, the nearest; or to the nearest place of a stockpile that takes it; and with neither,
// it lays it down where it stands. Both games drop a harvest where it was cut and leave it to the
// haulers (RimWorld's JobDriver_PlantHarvest places the yield near the plant; Dwarf Fortress's fish
// lie on the bank until hauled). Played so here, with carrying the last thing a dwarf does, a
// spring's gathering lay in the field and spoiled there: so the one who took it brings it.
basket_home :: proc(h: ^Hold, i: int) {
	d, w := &h.dwarves[i], &h.walk
	kind, n, age := d.carry, d.carrying, d.haul.age
	haul := Haul{on = true, bringing = true, from = d.cell, kind = kind, n = n, site = -1, age = age}
	found := false
	best := max(i32)
	for b in h.benches {   // a rack first: what will spoil is dried
		k := make_of(kind, b.kind)
		if !b.used || b.done || k < 0 || b.make >= 0 && k != b.make || BENCHES[b.kind].holds - b.n - b.coming <= 0 do continue
		if far := far_of(b.at, d.cell) + (0 if b.n + b.coming > 0 else 1000); far < best {   // one that holds some of it already before an empty one: a rack is filled before the next is begun
			w.budget = ASKING
			if stand := walk_near(w, b.at.x, b.at.y, b.at.z, 2, false, &h.benched); stand >= 0 do best, found, haul.bench, haul.hearth, haul.to = far, true, true, b.at, floor_block(w, stand)
		}
	}
	if !found do if to, _, ok := store_cell(h, Good{at = d.cell, kind = kind}); ok do found, haul.to = true, to
	if found && haul.to != d.cell {
		clear(&w.shun)
		if _, why, _, _ := way_timed(h, d.cell, haul.to, &d.path); why != .Way do found = false
	}
	if !found {   // nowhere to take it, or no way there: it lies where the dwarf stands
		d.carrying, d.haul = 0, {}
		good_drop(h, d.cell, kind, n, age)
		d.doing, d.rest = .Waiting, 0
		return
	}
	if haul.bench {
		b := &h.benches[h.benched[haul.hearth]]
		b.coming += n
		b.make = make_of(kind, b.kind)
	} else {
		cell := &h.zoned[haul.to]
		cell.coming += n
	}
	d.haul = haul
	h.spots[i] = haul.to
	if haul.to == d.cell {
		haul_arrive(h, i)
		return
	}
	d.doing, d.seek, d.next, d.wait, d.said, d.errand = .Walking, false, 1, 0, "", false
}

// A dwarf lets go of what it was carrying or fetching: the things it holds lie where it stands.
haul_drop :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if !d.haul.on && d.carrying == 0 do return
	haul := d.haul
	if haul.on {
		taking := haul.bench && haul.off   // what a bench made, to be taken off it: no pile is promised
		if !haul.bringing && !taking do if k, ok := h.lying[haul.from]; ok do h.goods[k].held = max(h.goods[k].held - haul.n, 0)
		if !haul.bringing && taking do bench_unpromise(h, haul.hearth, haul.n, true)
		if haul.fire {
			if k, burns := h.burning[haul.hearth]; burns do h.fires[k].coming = max(h.fires[k].coming - haul.n, 0)
		} else if haul.bench && !haul.off do bench_unpromise(h, haul.hearth, haul.n)
		else if haul.site >= 0 do h.sites[haul.site].coming = max(h.sites[haul.site].coming - int(haul.n), 0)
		else if c, zoned := &h.zoned[haul.to]; zoned do c.coming = max(c.coming - haul.n, 0)
	}
	if d.carrying > 0 do good_drop(h, d.cell, d.carry, d.carrying, haul.age)
	d.carrying, d.haul = 0, {}
	h.goods_v += 1
}

// ---- what the frame is shown ------------------------------------------------------------------

// Lay out the goods for the frame when anything of them has changed: the piles, the stockpiles'
// ground as boxes, and the count of what is stored and of what lies loose. Called with the hold's mutex held.
goods_show :: proc(h: ^Hold) {
	s := &h.shown
	if h.goods_shown == h.goods_v do return
	h.goods_shown = h.goods_v
	builtin.resize(&s.piles, len(h.goods))
	s.store, s.loose, s.unhoused, s.untaken = {}, {}, {}, {}
	h.store = {}
	room := room_read(h)
	for g, k in h.goods {
		in_store := stored(h, g)
		s.piles[k] = {g.at, g.kind, g.n, in_store, g.left}
		if in_store {
			s.store[g.kind] += g.n
			h.store[g.kind] += g.n
		} else {
			s.loose[g.kind] += g.n
			if !room_fits(&room, g.kind) {   // loose, and no stockpile has room for it: the stores say so, by its class
				class := takes_of(g.kind)
				s.unhoused[class] += g.n
				s.untaken[class] = !room.takes[class] && !room.takes[.All]
			}
		}
	}
	clear(&s.zones)
	clear(&s.zone_boxes)
	cells := make([dynamic][3]i32, context.temp_allocator)
	boxes := make([dynamic][2][3]i32, context.temp_allocator)
	for zone, id in h.zones do if zone.cells > 0 {
		clear(&cells)
		clear(&boxes)
		full, roofed, walled := 0, 0, 0
		for c, cell in h.zoned do if cell.zone == id {
			append(&cells, c - {0, 1, 0})   // the block of ground it lies on, which is what is tinted
			full += int(c in h.lying)
			if zone.sleep {
				s := shelter_of(hold_blocks(h), c)
				roofed, walled = roofed + int(s.roof), walled + int(indoors(s))
			}
		}
		for a in 1..<len(cells) do for k := a; k > 0 && less(cells[k], cells[k - 1]); k -= 1 do cells[k], cells[k - 1] = cells[k - 1], cells[k]   // a map gives its cells in no order: the boxes must be the same twice
		boxes_of(cells[:], &boxes)
		for b in boxes do append(&s.zone_boxes, Tint{b[0], b[1], id})
		append(&s.zones, Zone_Seen{id, zone.takes, zone.cells, full, zone.sleep, roofed, walled})
	}
	less :: proc(a, b: [3]i32) -> bool { return a.y < b.y || a.y == b.y && (a.z < b.z || a.z == b.z && a.x < b.x) }
}

// ---- spoiling ---------------------------------------------------------------------------------

// Food spoils (plan.md, "Winter's food"). Each kind lies good for its row's days (FOODS.keeps) in
// air of MILD degrees; warmer air spoils it faster and colder slower, twice or half as fast for each
// ten degrees, and at freezing not at all. RimWorld's food rots at its full pace from 10 °C up, more
// slowly down to 0 °C and not at all under it (GenTemperature.RotRateAtTemperature); on this island,
// whose winter is 7 to 14 °C, that rule would hardly slow anything, so the pace here follows the
// warmth all the way (a doubling for ten degrees is the common figure for what spoils food, from
// memory). The air is the weather's where the heap lies, and indoors halfway to the year's mean, as
// a dwarf feels it there (feel_at): a room under ground is cool in summer.
//
// A heap is as old as its things together. When its days are up it is gone, and the hold says what
// went and where. Nothing is eaten spoiled.
MILD        :: 20.0   // °C at which a food's row says how long it keeps
SPOIL_EVERY :: 100    // ticks between two looks at what lies: ten seconds, 120 times a day
SOON        :: 1.0    // days left under which food is said to be about to spoil
SPOIL_SAID  :: 500    // ticks from the first thing spoiled to the line that says it: an hour

spoil_rate :: proc(air: f32) -> f32 { return 0 if air <= 0 else math.pow(2, (air - MILD)/10) }

// Days a heap of a kind and an age has left, lying where what spoils goes at a pace: under nothing for what does not spoil.
keeps_left :: proc(kind: Mat, age, rate: f32) -> f32 {
	if !is(kind, FOOD) do return -1
	keeps := FOODS[food_of(kind)].keeps
	return -1 if keeps <= 0 else 99 if rate <= 0 else min(max(keeps - age, 0)/rate, 99)
}

// Whether a food is one a hold lays up for a lean season: it does not spoil, or keeps a season or more.
keeps_well :: proc(kind: Mat) -> bool {
	keeps := FOODS[food_of(kind)].keeps
	return keeps <= 0 || keeps >= SEASON_DAYS
}

// The air a thing lying in a cell lies in, from the air at the sea's level at that moment: the
// weather's air differs from place to place by the height alone (weather.odin), so a tick's heaps
// ask the weather once between them.
air_at :: proc(sea: f32, c: [3]i32, walled: bool) -> f32 {
	air := sea + -LAPSE*f32(max(c.y, 0))
	return math.lerp(air, region.climate.mean - LAPSE*f32(max(c.y, 0)), f32(WALLED)) if walled else air
}

// Every SPOIL_EVERY ticks: each heap of food that spoils ages by the air it lies in, and one whose
// days are up is gone. What went is said in one line, the stockpiles' apart from what lay loose.
goods_spoil :: proc(h: ^Hold) {
	if h.tick%SPOIL_EVERY != 0 || len(h.goods) == 0 && h.gone == {} do return
	blocks := hold_blocks(h)
	sea, asked := f32(0), false   // the air at the sea's level, asked once for all the heaps (air_at)
	for k := len(h.goods) - 1; k >= 0; k -= 1 {
		g := &h.goods[k]
		if !is(g.kind, FOOD) || FOODS[food_of(g.kind)].keeps <= 0 do continue
		if g.read != h.ground + 1 do g.walled, g.read = indoors(shelter_of(blocks, g.at)), h.ground + 1
		if !asked do sea, asked = weather(f64(h.tick)*TICK, Stand{0, region.climate.rain, 1}).air, true
		rate := spoil_rate(air_at(sea, g.at, g.walled))
		g.age += rate*SPOIL_EVERY*TICK/DAY
		left := keeps_left(g.kind, g.age, rate)
		if (left < SOON) != (g.left < SOON) || abs(left - g.left) >= 0.25 do h.goods_v += 1   // shown again when it has changed enough to be said otherwise
		g.left = left
		if g.age < FOODS[food_of(g.kind)].keeps do continue
		loose := int(!stored(h, g^))
		if h.gone[loose] == {} do h.gone_at[loose], h.gone_since[loose] = g.at, h.tick
		h.gone[loose][food_of(g.kind)] += int(g.n)
		good_take(h, k, g.n)
	}
	// What went is said an hour after the first of it, all of the hour together: heaps gathered over a morning spoil over a morning.
	for loose in 0..<2 do if h.gone[loose] != {} && h.tick - h.gone_since[loose] >= SPOIL_SAID {
		b := strings.builder_make(context.temp_allocator)
		kinds, said, n := 0, 0, 0
		for count in h.gone[loose] do kinds += int(count > 0)
		for count, food in h.gone[loose] do if count > 0 {
			fmt.sbprintf(&b, "%s%d of %s", "" if said == 0 else " and " if said == kinds - 1 else ", ", count, FOODS[food].name)
			said, n = said + 1, n + count
		}
		today := date_tick(h.tick).day
		h.at = feet_on(h.gone_at[loose])
		h.aside = h.spoilt[loose] && h.spoilt_on[loose] == today   // on the screen once a day: after that the log has it, and the dawn says the day's sum
		h.spoilt[loose], h.spoilt_on[loose] = true, today
		h.spoiled += n
		h.short = fmt.tprintf("Spoiled in the stockpiles: %s.", strings.to_string(b)) if loose == 0 else fmt.tprintf("Spoiled where it lay: %s.", strings.to_string(b))
		if loose == 0 do say(h, "Food has spoiled in the stockpiles, at %s: %s. Fresh food keeps a few days, less in the heat; what is to be kept is dried on a rack (Build, then Rack).", place_say(h, h.gone_at[loose]), strings.to_string(b))
		else do say(h, "Food left lying has spoiled, at %s: %s.", place_say(h, h.gone_at[loose]), strings.to_string(b))
		h.gone[loose] = {}
	}
}
