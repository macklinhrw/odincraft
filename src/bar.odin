package main

import "core:fmt"
import "core:math"
import "core:strings"

// The orders bar and the tool in the hand (docs/foundations/interface.md, section 4 and "With P3";
// plan.md, P3). The bar stands at the bottom left, under the hand: Dig, Fell, Build, Send, Remove,
// each an act with a row in BINDS, so its key is written on it. Taking one puts a tool in the hand:
// its card holds the tool's choices (what kind of digging; what to build and from what), what the
// land says of the ground under the pointer, and, while a box is dragged, the mark's size in words.
// Letting the button go gives the order to the hold (hold_order): the dwarves take it from there.
//
// What is marked shows on the land until it is done: ground to dig is tinted, a tree to fell wears
// a band, a block to lay stands as a small block of what it will be. A click on any of them puts the
// order's card in the hand: what is left of it, who is at it, and what it waits for.
//
// Everything here is the frame thread's, and reads the hold only through what it shows (Shown).

Tool :: enum u8 { None, Dig, Fell, Build, Send, Remove }
Tool_Row :: struct { name, says, id: string }
TOOL_ROWS := [Tool]Tool_Row{
	.None   = {},
	.Dig    = {"Dig", "Drag over ground to mark it to be dug. The dwarves take the work themselves.", "orders.dig"},
	.Fell   = {"Fell", "Drag over trees to mark them to be felled. Their timber goes to the store.", "orders.fell"},
	.Build  = {"Build", "Drag to mark blocks to be laid, of what is in store.", "orders.build"},
	.Send   = {"Send", "Click a place for the party to go and stand there.", "orders.send"},
	.Remove = {"Remove", "Click or drag over marked ground to take its order back.", "orders.remove"},
}
Choice :: struct { plan: Plan, name, says: string }
DIG_CHOICES := [?]Choice{
	{.Room, "A room", "Two blocks high: the block marked and the one under it, so a dwarf can stand in it."},
	{.Stair, "A stair down", "Down a block a step from where the drag begins, with room over each step."},
}
BUILD_CHOICES := [?]Choice{
	{.Wall, "A wall", "Two blocks high over the block the drag begins on, and down to the ground."},
	{.Floor, "A floor or roof", "One layer at the level of the block the drag begins on. Over a room it is the roof."},
	{.Stair, "A stair up", "Up a block a step from where the drag begins: the way out of a pit."},
}

Bar :: struct {
	tool:     Tool,
	dig:      Plan,
	build:    Plan,
	stuff:    Stuff,
	job:      int,          // the order whose card is in the hand, or -1
	plain:    bool,         // the hand's thing shows its own card though it is marked
	for_hand: [3]i32,       // the block of the thing that was looked up
	posed:    bool,         // a run with no window holds the mark's box as if the button were down
	cells:    [dynamic][3]i32,   // the blocks the box being dragged would mark
	trees:    [dynamic]Tree,
	said:     [3]string,    // the alerts as last raised
}
bar := Bar{dig = .Room, build = .Wall, job = -1}

// Take a tool in the hand, or put it down; the same tool again puts it down. In first person Send
// sends the party to the block aimed at.
tool_take :: proc(t: Tool) {
	u := &play
	if t == .Send && u.afoot^ {
		if u.aim.ok do hold_send(u.aim.block.x, u.aim.block.y, u.aim.block.z)
		return
	}
	bar.tool = .None if t == bar.tool else t
	if bar.tool != .None do hand_drop()
	mark_clear(u.a)
}

// Whether the pointer's box is a tool's, and not the hand's.
tool_marks :: proc() -> bool { return bar.tool != .None && !play.afoot^ }

// The order a tool would give for a box from one block to another.
tool_order :: proc(a, b: [3]i32) -> (o: Order, ok: bool) {
	switch bar.tool {
	case .None:
	case .Dig:    return {kind = .Dig, at = a, to = b, shape = bar.dig}, true
	case .Fell:   return {kind = .Fell, at = a, to = b}, true
	case .Build:  return {kind = .Build, at = a, to = b, shape = bar.build, stuff = bar.stuff}, true
	case .Send:   return {kind = .Go, at = b}, true
	case .Remove: return {kind = .Unmark, at = a, to = b}, true
	}
	return
}

// The button is let go on the world with a tool in the hand: the order is given.
tool_give :: proc(a: ^Above) {
	if !a.marked do return
	if o, ok := tool_order(a.mark[0], a.mark[1]); ok do hold_order(o)
	mark_clear(a)
	if bar.tool == .Send do bar.tool = .None   // one place is one order
}

// The world's blocks as the frame has them, for an order's shape to be shown before it is given.
world_blocks :: proc(w: ^World) -> Blocks {
	return {proc(data: rawptr, b: [3]i32) -> Mat { return block_made(cast(^World)data, b) }, w}
}

// The order in the hand's thing, if it lies in marked ground: the order's place among those shown, or -1.
job_of :: proc(t: Thing) -> int {
	s := &watch.seen
	if t.kind != .Ground && t.kind != .Tree && t.kind != .Box do return -1
	b := t.block
	for tint in s.tints do if b.x >= tint.lo.x && b.x <= tint.hi.x && b.y >= tint.lo.y && b.y <= tint.hi.y && b.z >= tint.lo.z && b.z <= tint.hi.z do return tint.site
	for g in s.ghosts {
		if g.work == .Fell && t.kind == .Tree && t.island != nil && g.at.x == t.tree.x + t.island.region.origin.x && g.at.z == t.tree.z + t.island.region.origin.y do return g.site
		if g.work == .Build && abs(g.at.x - b.x) + abs(g.at.y - b.y) + abs(g.at.z - b.z) <= 1 do return g.site
	}
	return -1
}

site_seen :: proc(id: int) -> (s: Site_Seen, ok: bool) {
	for site in watch.seen.sites do if site.id == id do return site, true
	return
}

// Each frame, before the screen is listed: which order the hand's thing belongs to, what the box
// being dragged would mark, and the alerts.
bar_frame :: proc() {
	u, a := &play, play.a
	if u.hand.kind == .None do bar.job, bar.plain = -1, false
	else if u.hand.block != bar.for_hand {
		bar.for_hand, bar.plain = u.hand.block, false
		bar.job = job_of(u.hand)
	}
	if _, ok := site_seen(bar.job); !ok do bar.job = -1
	// The mark as it would be given.
	clear(&bar.cells)
	clear(&bar.trees)
	if tool_marks() && (a.marking || bar.posed) && a.marked {
		#partial switch bar.tool {
		case .Dig:   cells_of(.Dig, bar.dig, a.mark[0], a.mark[1], world_blocks(u.w), &bar.cells)
		case .Build: cells_of(.Build, bar.build, a.mark[0], a.mark[1], world_blocks(u.w), &bar.cells)
		case .Fell:
			lo, hi := box_of(a.mark[0], a.mark[1])
			if f := island_at(f64(lo.x) + 0.5, f64(lo.z) + 0.5); f != nil && is_formed(f) {
				bound(f)
				trees_in(lo.x - region.origin.x, lo.z - region.origin.y, hi.x - region.origin.x, hi.z - region.origin.y, &bar.trees)
				for i := len(bar.trees) - 1; i >= 0; i -= 1 do if bar.trees[i].form == .Fallen do unordered_remove(&bar.trees, i)
			}
		}
	}
	alerts_keep()
}

// The standing problems of the orders, each one alert that counts (I5, I14): work no dwarf can
// reach, building with nothing in store, and rock too hard for the picks. A dwarf shut in, or idle
// because of one of these, is marked among the dwarves (NEEDS, crowd.odin).
alerts_keep :: proc() {
	s := &watch.seen
	texts: [3]string
	places: [3][3]f64
	reach, stuff, hard := 0, 0, 0
	first: [3]Site_Seen
	for site in s.sites {
		if site.busy == 0 && site.waits[.None] == 0 && site.waits[.No_Way] + site.waits[.No_Room] > 0 && site.waits[.Front] + site.waits[.No_Way] + site.waits[.No_Room] == site.left {
			if reach == 0 do first[0] = site
			reach += 1
		}
		if site.waits[.No_Stuff] > 0 && site.busy == 0 {
			if stuff == 0 do first[1] = site
			stuff += 1
		}
		if site.waits[.Too_Hard] == site.left && site.left > 0 {
			if hard == 0 do first[2] = site
			hard += 1
		}
	}
	middle :: proc(site: Site_Seen) -> [3]f64 { return {f64(site.lo.x + site.hi.x + 1)/2, f64(site.hi.y), f64(site.lo.z + site.hi.z + 1)/2} }
	if reach == 1 do texts[0] = fmt.tprintf("No dwarf can reach the %s.", first[0].place)
	else if reach > 1 do texts[0] = fmt.tprintf("No dwarf can reach %s orders: the %s and %s.", count_words(reach), first[0].place, "one more" if reach == 2 else fmt.tprintf("%s more", count_words(reach - 1)))
	if stuff >= 1 do texts[1] = fmt.tprintf("The %s waits for %s: none is in store.%s", first[1].place, STUFFS[first[1].stuff], "" if stuff == 1 else fmt.tprintf(" So do %s more.", count_words(stuff - 1)))
	if hard >= 1 do texts[1] = fmt.tprintf("%s%sThe %s is left in rock too hard for the party's picks.", texts[1], " " if texts[1] != "" else "", first[2].place)
	places[0], places[1] = middle(first[0]), middle(first[1] if stuff > 0 else first[2])
	ids := [3]string{"orders.reach", "orders.store", ""}   // a dwarf shut in is the dwarves' own alert (NEEDS, crowd.odin)
	for text, i in texts do if text != bar.said[i] && ids[i] != "" {
		delete(bar.said[i])
		bar.said[i] = strings.clone(text)
		if text == "" do alert_clear(ids[i])
		else do alert_raise(ids[i], text, .Trouble if i != 1 else .Caution, places[i])
	}
}

// What is marked, for the picture: the boxes of ground to dig, which the terrain tints, the box
// being dragged among them, brighter; and after the frame's boxes a band on each tree to fell and
// a small block for each block to lay.
marks_view :: proc(v: ^View, boxes: []Box, eye: [3]f64) -> []Box {
	s, a := &watch.seen, play.a
	if play.afoot^ && len(s.ghosts) == 0 do return boxes
	n := 0
	put :: proc(v: ^View, n: ^int, lo, hi: [3]i32, kind: f32, eye: [3]f64) {
		if n^ >= len(v.tints) do return
		v.tints[n^] = {f32(f64(lo.x) - eye.x), f32(f64(lo.y) - eye.y), f32(f64(lo.z) - eye.z), kind}
		v.tint_sizes[n^] = {f32(hi.x - lo.x + 1), f32(hi.y - lo.y + 1), f32(hi.z - lo.z + 1), 0}
		n^ += 1
	}
	dragging := tool_marks() && (a.marking || bar.posed) && a.marked
	if dragging {
		v.has_mark = bar.tool == .Send
		pieces := make([dynamic][2][3]i32, context.temp_allocator)
		#partial switch bar.tool {
		case .Dig:    dig_boxes(bar.dig, a.mark[0], a.mark[1], &pieces)
		case .Remove, .Fell:
			lo, hi := box_of(a.mark[0], a.mark[1])
			append(&pieces, [2][3]i32{lo, hi})
		}
		for p in pieces do put(v, &n, p[0], p[1], 3 if bar.tool == .Remove else 2, eye)
	}
	// The nearest the view's middle first, where there are more than the picture takes.
	near := make([dynamic]Tint, context.temp_allocator)
	for t in s.tints do append(&near, t)
	far :: proc(t: Tint, at: [3]f64) -> f64 { return abs(f64(t.lo.x + t.hi.x)/2 - at.x) + abs(f64(t.lo.z + t.hi.z)/2 - at.z) }
	for i in 1..<len(near) do for k := i; k > 0 && far(near[k], a.at) < far(near[k - 1], a.at); k -= 1 do near[k], near[k - 1] = near[k - 1], near[k]
	for t in near do put(v, &n, t.lo, t.hi, 4 if t.site == bar.job else 1, eye)
	v.tint_count = n

	out := make([dynamic]Box, 0, len(boxes) + len(s.ghosts) + len(bar.cells) + len(bar.trees), context.temp_allocator)
	append(&out, ..boxes)
	rel :: proc(p, eye: [3]f64) -> [3]f32 { return {f32(p.x - eye.x), f32(p.y - eye.y), f32(p.z - eye.z)} }
	cube :: proc(out: ^[dynamic]Box, at: [3]f32, half: [3]f32, upper, under: u32) {
		append(out, Box{at, f32(upper), {half.x, 0, 0}, f32(under), {0, half.y, 0}, 0, {0, 0, half.z}, 0})
	}
	rgb :: proc(c: Colour) -> u32 { return u32(c.r) << 16 | u32(c.g) << 8 | u32(c.b) }
	stuff_colour :: proc(stuff: Stuff, store: ^[Mat]i32) -> u32 {
		_, most := store_of(store, stuff)
		if most == .Air do most = .Basalt if stuff == .Stone else .Wood_End
		else if stuff == .Timber do most = GRAIN[most][0]
		c := MATERIALS[most].colour
		return u32(math.pow(c.r, 1/2.2)*255) << 16 | u32(math.pow(c.g, 1/2.2)*255) << 8 | u32(math.pow(c.b, 1/2.2)*255)
	}
	brass := rgb(LOOK.brass)
	for g in s.ghosts {
		if len(out) >= BOX_MAX - 64 do break
		at := rel({f64(g.at.x) + 0.5, f64(g.at.y) + 0.5, f64(g.at.z) + 0.5}, eye)
		chosen := g.site == bar.job
		switch g.work {
		case .Fell:  cube(&out, at + {0, 0.6, 0}, {0.62, 0.14 if chosen else 0.09, 0.62}, brass, brass)   // a band round the stem, at a dwarf's shoulder
		case .Build: cube(&out, at, {0.3, 0.3, 0.3} if chosen else {0.24, 0.24, 0.24}, stuff_colour(g.stuff, &s.store), brass)
		case .Dig:
		}
	}
	// And what the box being dragged would lay or fell.
	if bar.tool == .Build do for c in bar.cells[:min(len(bar.cells), 2000)] do cube(&out, rel({f64(c.x) + 0.5, f64(c.y) + 0.5, f64(c.z) + 0.5}, eye), {0.34, 0.34, 0.34}, stuff_colour(bar.stuff, &s.store), brass)
	if f := island_at(a.at.x, a.at.z); f != nil do for t in bar.trees {
		cube(&out, rel({f64(t.x + f.region.origin.x) + 0.5, f64(t.base) + 1.1, f64(t.z + f.region.origin.y) + 0.5}, eye), {0.66, 0.16, 0.66}, brass, brass)
	}
	return out[:]
}

// ---- words ----------------------------------------------------------------------------------

// What the land says of the ground under the pointer, for the tool held: what it is, how it cuts,
// and what lies over it.
ground_says :: proc() -> string {
	u, a := &play, play.a
	if !a.shown || !a.under.ok do return "Point at the land to read the ground there."
	b := a.under.block
	m := block_made(u.w, b)
	over := ground_top(f64(b.x) + 0.5, f64(b.z) + 0.5) - 1 - b.y
	lies := "It lies at the ground's top." if over <= 0 else fmt.tprintf("%d m of ground lie over it%s.", over, ": enough to hold a roof" if over >= 2 else "")
	name := sentence(mat_words(m))[:len(mat_words(m))]
	switch bar.tool {
	case .None, .Send, .Remove:
	case .Dig:
		if is(m, PLANT_BLOCKS) do return fmt.tprintf("%s: a tree's. Fell it first; ground a tree stands on waits for the felling.", name)
		kind := rock_kind(m)
		yield := "Nothing of it is kept." if kind == .Air else fmt.tprintf("Each block dug is a block of %s for the store.", mat_words(kind))
		if MATERIALS[m].strength > TOOLS do return fmt.tprintf("%s: too hard for the party's picks. It will be marked and left. %s", name, lies)
		return fmt.tprintf("%s: %s. A miner cuts a block in about %.0f seconds, other hands in twice that. %s %s", name, cut_words(m), dig_seconds(m), yield, lies)
	case .Fell:
		t := thing_at(u.w, a.under)
		if t.kind != .Tree do return "No tree stands under the pointer."
		if t.tree.kind == .Scrub do return "A bush of scrub: it is cleared, and gives no timber."
		return fmt.tprintf("A %s tree, %d m tall: %d of timber for the store.", SPECIES[t.tree.kind].name, t.tree.height, max(int(t.tree.height)/2, 1))
	case .Build:
		return fmt.tprintf("%s. A block is laid against one beside it, by a dwarf standing next to it or under it.", name)
	}
	return ""
}

// What is in store of a stuff, in words.
store_says :: proc(stuff: Stuff) -> string {
	b := strings.builder_make(context.temp_allocator)
	n := 0
	for count, m in watch.seen.store do if count > 0 && is_stuff(m, stuff) {
		fmt.sbprintf(&b, "%s%d of %s", "" if n == 0 else ", ", count, store_words(m))
		n += 1
	}
	if n == 0 do return "none in store: dig rock for it" if stuff == .Stone else "none in store: fell trees for it"
	return strings.to_string(b)
}

// The box being dragged, in words: its size and what it would mark.
mark_says :: proc() -> string {
	a := play.a
	if !(a.marking || bar.posed) || !a.marked do return ""
	lo, hi := box_of(a.mark[0], a.mark[1])
	wide, long := hi.x - lo.x + 1, hi.z - lo.z + 1
	n := len(bar.cells)
	switch bar.tool {
	case .None, .Send:
	case .Dig:
		if bar.dig == .Stair {
			_, _, steps := stair_run(a.mark[0], a.mark[1])
			return fmt.tprintf("A stair of %d steps down, %d wide: %d blocks to dig.", steps, min(wide, long), n)
		}
		high := max(hi.y - lo.y + 1, 2)
		return fmt.tprintf("A room %d by %d, %s blocks high: %d blocks to dig.", wide, long, count_words(int(high)), n)
	case .Fell:
		return fmt.tprintf("%d by %d m of ground: %s to fell.", wide, long, "no tree" if len(bar.trees) == 0 else "one tree" if len(bar.trees) == 1 else fmt.tprintf("%d trees", len(bar.trees)))
	case .Build:
		have, _ := store_of(&watch.seen.store, bar.stuff)
		what := "A wall" if bar.build == .Wall else "A stair" if bar.build == .Stair else "A floor"
		short := "" if have >= n else fmt.tprintf(" The store has %d of %s: the rest will wait.", have, STUFFS[bar.stuff])
		return fmt.tprintf("%s %d by %d: %d blocks of %s to lay.%s", what, wide, long, n, STUFFS[bar.stuff], short)
	case .Remove:
		return fmt.tprintf("Every order with a mark in these %d by %d blocks is taken back.", wide, long)
	}
	return ""
}

// ---- parts ----------------------------------------------------------------------------------

// Bottom left, under the hand: the orders.
bar_build :: proc() {
	u, L := &play, &LOOK
	if u.afoot^ do return
	u.area = .Orders
	x, y := px(L.margin), screen.h - px(L.margin) - px(L.button)
	wide := f32(0)
	for t in Tool do if t != .None do wide += button_wide(TOOL_ROWS[t].name, key_for(.Order, int(t))) + px(L.gap)
	part(.Panel, {x, y, wide - px(L.gap), px(L.button)}, id = "orders")
	for t in Tool do if t != .None {
		row := TOOL_ROWS[t]
		w := button_wide(row.name, key_for(.Order, int(t)))
		button({x, y, w, px(L.button)}, row.name, .Order, int(t), bar.tool == t, row.id, row.says)
		x += w + px(L.gap)
	}
}

// The hand, when a tool is held or the thing in it is marked: true if it drew the card.
bar_hand :: proc() -> bool {
	u, L := &play, &LOOK
	if tool_marks() {
		tool_card()
		return true
	}
	site, ok := site_seen(bar.job)
	if !ok || bar.plain || u.hand.kind == .None do return false
	u.area = .Hand
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	thing := "Trees to fell" if site.work == .Fell else "Ground to dig" if site.work == .Dig else "Blocks to lay"
	title := sentence(site.place)
	if at := strings.index(title, " at "); at > 0 do title = title[:at]
	sub := site.place[strings.index(site.place, " at ") + 1:] if strings.contains(site.place, " at ") else ""
	unit := "trees" if site.work == .Fell else "blocks"
	hands := "No dwarf is at it" if site.busy == 0 else "One dwarf is at it" if site.busy == 1 else fmt.tprintf("%s dwarves are at it", sentence(count_words(site.busy))[:len(count_words(site.busy))])
	line := fmt.tprintf("%s: %d of its %d %s are left. %s.", thing, site.left, site.total, unit, hands)
	idle := 0
	for d in watch.seen.dwarves do idle += int(!d.job && (d.doing == .Waiting || d.doing == .Stopped) && !d.shut)
	next := waits_words(site, idle)
	if next != "" do next = fmt.tprintf("%s.", next)
	if site.work == .Build do next = fmt.tprintf("%sOf %s: %s.", fmt.tprintf("%s ", next) if next != "" else "", STUFFS[site.stuff], store_says(site.stuff))
	high := 2*px(L.pad.y) + line_of(.Title) + text_high(.Body, sub, inner) + px(L.space) + text_high(.Body, line, inner) + (px(1) + text_high(.Body, next, inner) if next != "" else 0) + px(4) + 2*px(L.button) + px(L.gap)
	r := Rect{x, screen.h - px(L.hand_foot) - high, w, high}
	part(.Panel, r, id = "hand")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(cx, y, title, .Title, id = "job.title")
	y += words(cx, y, sub, .Body, L.ash, "job.sub", inner) + px(L.space)
	y += words(cx, y, line, .Body, {}, "job.line", inner)
	if next != "" do y += px(1) + words(cx, y, next, .Body, L.brass if strings.has_prefix(next, "Wait") else L.ash, "job.waits", inner)
	y += px(4)
	gw := button_wide("Go there", key_for(.Go))
	button({cx, y, gw, px(L.button)}, "Go there", .Go, 0, false, "job.go", "Put the view over it.")
	button({cx + gw + px(L.gap), y, button_wide("Take it back", ""), px(L.button)}, "Take it back", .Take_Back, 0, false, "job.back", "Take this order back: nothing more of it is done.")
	y += px(L.button) + px(L.gap)
	pw := button_wide("The ground itself", "")
	button({cx, y, pw, px(L.button)}, "The ground itself", .Plain, 0, false, "job.plain", "What the ground under the mark is, and why.")
	button({cx + pw + px(L.gap), y, button_wide("Put it down", key_for(.Escape)), px(L.button)}, "Put it down", .Drop, 0, false, "hand.drop", "Empty the hand.")
	screen.items[len(screen.items) - 1].key = key_for(.Escape)
	return true
}

// The tool's card: what it does, its choices, the ground under the pointer, the mark, and how to put it down.
tool_card :: proc() {
	u, L := &play, &LOOK
	u.area = .Hand
	row := TOOL_ROWS[bar.tool]
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	choices := DIG_CHOICES[:] if bar.tool == .Dig else BUILD_CHOICES[:] if bar.tool == .Build else nil
	chosen := bar.dig if bar.tool == .Dig else bar.build
	says := ground_says() if bar.tool != .Send && bar.tool != .Remove else ""
	mark := mark_says()
	choice_says := ""
	for c in choices do if c.plan == chosen do choice_says = c.says
	high := 2*px(L.pad.y) + line_of(.Title) + text_high(.Body, row.says, inner)
	if len(choices) > 0 do high += px(L.space) + chip + px(1.5) + text_high(.Small, choice_says, inner)
	if bar.tool == .Build do high += px(L.space) + 2*(chip + px(1)) + px(1)
	if says != "" do high += px(L.space) + line_of(.Small) + text_high(.Body, says, inner)
	if mark != "" do high += px(L.space) + text_high(.Body, mark, inner)
	high += px(4) + px(L.button)
	r := Rect{x, screen.h - px(L.hand_foot) - high, w, high}
	part(.Panel, r, id = "hand")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(cx, y, row.name, .Title, L.brass, "tool.title")
	y += words(cx, y, row.says, .Body, L.ash, "tool.says", inner)
	if len(choices) > 0 {
		y += px(L.space)
		tx := cx
		for c in choices {
			cw := text_wide(.Body, c.name) + 2*px(L.chip_pad.x)
			part(.Chip, {tx, y, cw, chip}, c.name, .Body, {}, {.Chosen} if c.plan == chosen else {}, .Plan, int(c.plan), id = "tool.choice", tip = c.says)
			tx += cw + px(L.gap)
		}
		y += chip + px(1.5)
		y += words(cx, y, choice_says, .Small, L.ash, "tool.choice.says", inner)
	}
	if bar.tool == .Build {   // what it is built of, with what is in store of each
		y += px(L.space)
		for name, stuff in STUFFS {
			have, _ := store_of(&watch.seen.store, stuff)
			label := fmt.tprintf("Of %s", name)
			cw := text_wide(.Body, label) + 2*px(L.chip_pad.x)
			part(.Chip, {cx, y, cw, chip}, label, .Body, {}, {.Chosen} if bar.stuff == stuff else {}, .Stuff, int(stuff), id = "tool.stuff", tip = "What the blocks are laid of.")
			words(cx + cw + px(3), y + px(L.chip_pad.y), store_says(stuff), .Small, L.ash if have > 0 else L.cinnabar, "tool.store")
			y += chip + px(1)
		}
		y += px(1)
	}
	if says != "" {
		y += px(L.space)
		y += words(cx, y, "The ground under the pointer", .Small, L.ash, "tool.ground.title")
		y += words(cx, y, says, .Body, {}, "tool.ground", inner)
	}
	if mark != "" {
		y += px(L.space)
		y += words(cx, y, mark, .Body, L.brass, "tool.mark", inner)
	}
	y += px(4)
	button({cx, y, button_wide("Put it down", key_for(.Escape)), px(L.button)}, "Put it down", .Order, int(bar.tool), false, "tool.drop", "Put the tool down.")
	screen.items[len(screen.items) - 1].key = key_for(.Escape)
}
