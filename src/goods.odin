package main

import "base:builtin"
import "core:fmt"

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
	hearth:   [3]i32,   // which burns in this cell (shelter.odin)
}

// Whether a dwarf standing in a cell of the hold's ground has a roof over it (shelter.odin).
roofed_at :: proc(h: ^Hold, c: [3]i32) -> bool { return roofed(hold_blocks(h), c) }

// What the frame may know of the goods: every pile, and the stockpiles as boxes of their ground.
Pile_Seen :: struct { at: [3]i32, kind: Mat, n: i32, stored: bool }
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
good_put :: proc(h: ^Hold, at: [3]i32, kind: Mat, n: i32) {
	if n <= 0 do return
	w := &h.walk
	left := n
	h.goods_v += 1
	fill :: proc(h: ^Hold, c: [3]i32, kind: Mat, left: ^i32, over := false) {
		if k, ok := h.lying[c]; ok {
			g := &h.goods[k]
			if g.kind != kind do return
			room := left^ if over else min(left^, heap_of(kind) - g.n)
			if room <= 0 do return
			g.n += room
			left^ -= room
			return
		}
		room := left^ if over else min(left^, heap_of(kind))
		h.lying[c] = len(h.goods)
		append(&h.goods, Good{at = c, kind = kind, n = room})
		left^ -= room
	}
	fill(h, at, kind, &left)
	for r in i32(1)..=3 {
		if left == 0 do return
		for dz in -r..=r do for dx in -r..=r do if max(abs(dx), abs(dz)) == r do for dy in ([3]i32{0, -1, 1}) {
			c := at + {dx, dy, dz}
			if left > 0 && walk_floor(w, c.x, c.y, c.z) >= 0 && (c in h.zoned) == (at in h.zoned) do fill(h, c, kind, &left)   // a heap spreads within its stockpile, or outside every one
		}
	}
	if left > 0 do fill(h, at, kind, &left, true)
}

// Things come to lie where a block was: in its cell if there is ground under it, and else on the
// first ground below.
good_drop :: proc(h: ^Hold, at: [3]i32, kind: Mat, n: i32) {
	w := &h.walk
	c := at
	for _ in 0..<64 {
		under, _ := walk_block(w, c - {0, 1, 0})
		if under != .Air && !is(under, LEAVES) do break
		c.y -= 1
	}
	good_put(h, c, kind, n)
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
	if mat == .Air do good_drop(h, c, g.kind, g.n)
	else do good_put(h, at + {0, 1, 0}, g.kind, g.n)
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

// How many blocks an order to build still wants brought: those marked, less what lies at it and what is coming.
site_wants :: proc(h: ^Hold, id: int) -> int {
	s := &h.sites[id]
	if s.over || s.work != .Build do return 0
	return s.left - len(s.brought) - s.coming
}

// A dwarf with no marked work it can take looks for something to carry: stuff for a block marked
// to be laid first, from the nearest pile of it wherever it lies; then a pile lying loose, to the
// stockpile that takes it. False if there is nothing to carry.
haul_look :: proc(h: ^Hold, i: int) -> bool {
	d, w := &h.dwarves[i], &h.walk
	w.budget = ASKING
	far :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + 2*abs(a.y - b.y) }
	// For building.
	for &s, id in h.sites {
		want := site_wants(h, id)
		if want <= 0 do continue
		to, found := [3]i32{}, false
		for m in h.marks do if m.site == id && !found {   // a floor beside one of its blocks, to bring it to
			if f := walk_near(w, m.at.x, m.at.y, m.at.z, 2); f >= 0 do to, found = floor_block(w, f), true
		}
		if !found do continue
		best, pick := max(i32), -1
		for g, k in h.goods do if is_stuff(g.kind, s.stuff) && g.n - g.held > 0 {
			if f := far(g.at, to); f < best || f == best && k < pick do best, pick = f, k
		}
		if pick < 0 do continue
		g := &h.goods[pick]
		n := min(i32(want), ARMFUL, g.n - g.held)
		if !haul_set(h, i, {on = true, from = g.at, to = to, kind = g.kind, n = n, site = id}) do continue
		g.held += n
		s.coming += int(n)
		return true
	}
	// To a stockpile: the nearest pile that lies loose, or in a stockpile that does not take it.
	stores := false
	for z in h.zones do stores ||= !z.sleep && z.cells > 0
	if !stores do return false
	Near :: struct { far: i32, k: int }
	tries: [6]Near
	count := 0
	for g, k in h.goods do if g.n - g.held > 0 && !stored(h, g) {
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
		if ok && h.goods[k].kind == haul.kind {
			g := &h.goods[k]
			g.held = max(g.held - haul.n, 0)
			got = min(haul.n, g.n)
			good_take(h, k, got)
		}
		if got < haul.n {   // fewer were there than it came for
			if haul.fire {
				if k, burns := h.burning[haul.hearth]; burns do h.fires[k].coming = max(h.fires[k].coming - (haul.n - got), 0)
			} else if haul.site >= 0 do h.sites[haul.site].coming -= int(haul.n - got)
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
	if haul.site >= 0 && !h.sites[haul.site].over {
		s := &h.sites[haul.site]
		s.coming -= int(n)
		for _ in 0..<n do append(&s.brought, haul.kind)
		h.marks_v += 1
		for &m in h.marks do if m.site == haul.site && m.wait == .No_Stuff do m.wait, m.tried, m.by = .None, 0, -1
		return
	}
	if c, zoned := &h.zoned[haul.to]; zoned && haul.site < 0 do c.coming = max(c.coming - n, 0)
	good_put(h, d.cell if haul.site >= 0 else haul.to, haul.kind, n)
}

// A dwarf lets go of what it was carrying or fetching: the things it holds lie where it stands.
haul_drop :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if !d.haul.on && d.carrying == 0 do return
	haul := d.haul
	if haul.on {
		if !haul.bringing do if k, ok := h.lying[haul.from]; ok do h.goods[k].held = max(h.goods[k].held - haul.n, 0)
		if haul.fire {
			if k, burns := h.burning[haul.hearth]; burns do h.fires[k].coming = max(h.fires[k].coming - haul.n, 0)
		} else if haul.site >= 0 do h.sites[haul.site].coming = max(h.sites[haul.site].coming - int(haul.n), 0)
		else if c, zoned := &h.zoned[haul.to]; zoned do c.coming = max(c.coming - haul.n, 0)
	}
	if d.carrying > 0 do good_drop(h, d.cell, d.carry, d.carrying)
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
	s.store, s.loose = {}, {}
	h.store = {}
	for g, k in h.goods {
		in_store := stored(h, g)
		s.piles[k] = {g.at, g.kind, g.n, in_store}
		if in_store {
			s.store[g.kind] += g.n
			h.store[g.kind] += g.n
		} else do s.loose[g.kind] += g.n
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
