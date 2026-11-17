package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

// The orders bar and the tool in the hand (docs/foundations/interface.md, section 4 and "With P3";
// plan.md, P3). The bar stands at the bottom left, under the hand: Dig, Fell, Build, Send, Remove,
// each an act with a row in BINDS, so its key is written on it. Taking one puts a tool in the hand.
//
// A tool marks by area, on one level, as Dwarf Fortress and RimWorld do
// (interesting-world/notes/colony-sim-reference.md, section 1). The press takes the block under the
// pointer, through any leaf or limb over it; from there the drag is a rectangle on that block's
// level, its far corner where the pointer's ray comes down on the level, so it never grows upward.
// Felling takes the ground under the pointer at both corners, and a click on any part of a tree is
// that tree. A stair and a wall are lines.
// What the order would mark is worked out by the rule the hold marks by (cells_of, orders.odin) and
// shown every frame, under the pointer before the press and through the drag; letting go gives it.
//
// The tool's card is its name, its few choices and one live line: what lies under the pointer, or
// what the drag would do. Nothing on it moves. What is marked shows on the land until it is done:
// ground to dig is tinted, a tree to fell wears a band, a block to lay stands as a small block of
// what it will be. A click on any of them puts the order's card in the hand.
//
// Everything here is the frame thread's, and reads the hold only through what it shows (Shown).

Tool :: enum u8 { None, Dig, Fell, Build, Store, Send, Remove }
Tool_Row :: struct { name, says, id: string }
TOOL_ROWS := [Tool]Tool_Row{
	.None   = {},
	.Dig    = {"Dig", "Mark ground to be dug.", "orders.dig"},
	.Fell   = {"Fell", "Mark trees to be felled for timber.", "orders.fell"},
	.Build  = {"Build", "Mark blocks to be laid. Their stone or timber is brought to them.", "orders.build"},
	.Store  = {"Store", "Mark ground as a stockpile: what is dug and felled is carried there, and counted.", "orders.store"},
	.Send   = {"Send", "Send the party to stand somewhere.", "orders.send"},
	.Remove = {"Remove", "Take marks back; or take built blocks down; or take ground out of a stockpile.", "orders.remove"},
}
Choice :: struct { plan: Plan, name, says: string, line: bool }   // line: it is dragged as a line, not a rectangle
DIG_CHOICES := [?]Choice{
	{.Out, "Dig out", "Every block of ground in the rectangle, from this level down as deep as set.", false},
	{.Down, "Stair down", "Steps down into the ground, a block down for each block along the drag.", true},
	{.Up, "Stair up", "Steps up through the ground, a block up for each block along the drag.", true},
}
BUILD_CHOICES := [?]Choice{
	{.Wall, "Wall", "A wall along the drag, one or two blocks high, standing on this level.", true},
	{.Floor, "Floor", "One layer at this level wherever it is open: over a space it is the roof.", false},
	{.Stair, "Stair up", "Steps built up from this level, a block up for each block along the drag.", true},
}
DEEPEST :: 4   // blocks deep a dig, or high a wall, may be set

Bar :: struct {
	tool:     Tool,
	dig:      Plan,
	build:    Plan,
	stuff:    Stuff,
	takes:    Takes,        // what a stockpile marked now takes
	deep:     i32,          // blocks an order to dig out goes down
	high:     i32,          // blocks a wall stands
	job:      int,          // the order whose card is in the hand, or -1
	for_hand: [3]i32,       // the block of the thing that was looked up
	posed:    bool,         // a run with no window holds the mark's box as if the button were down
	aim:      Pick,         // the block the tool would begin on: the ground under the pointer, through any tree over it
	press:    Pick,         // what was under the pointer when the button went down, leaf and limb and all
	press_at: [2]f32,       // and where the pointer was
	dragged:  bool,         // it has moved since
	seen:     Preview_Key,  // what the preview was last worked out for
	order:    Order,        // the order letting go now would give, or a click here
	ready:    bool,
	cells:    [dynamic][3]i32,      // the blocks it would mark
	boxes:    [dynamic][2][3]i32,   // and those to dig, as boxes
	trees:    [dynamic]Tree,
	way:      int,          // with Remove: how many marks, built blocks or places it would take
	built:    map[[3]i32]Plan,   // the blocks the dwarves laid that stand, and what each was laid as: told by the hold as they are laid and dug
	undo:     enum u8 { Marks, Built, Zone },   // what Remove would take away here
	said:     [3]string,    // the alerts as last raised
}
Preview_Key :: struct { tool: Tool, dig, build: Plan, stuff: Stuff, takes: Takes, deep, high: i32, a, b: [3]i32, press: [3]i32, dragged, pressed: bool, volume: int, marks: int }
bar := Bar{dig = .Out, build = .Wall, deep = 2, high = 2, job = -1}

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

// Whether the tool held is dragged as a line.
tool_line :: proc() -> bool {
	if bar.tool == .Dig do for c in DIG_CHOICES do if c.plan == bar.dig do return c.line
	if bar.tool == .Build do for c in BUILD_CHOICES do if c.plan == bar.build do return c.line
	return false
}

// The pointer has moved with a tool held: the block the tool would begin on, and, while the button
// is down, the far corner of its mark. The far corner lies on the level the drag began on, where
// the pointer's ray comes down on it: a drag over a hillside or a wood stays flat.
tool_point :: proc(a: ^Above, w: ^World, eye: [3]f64, ray: [3]f32) {
	bar.aim = a.under
	if w.finest == 0 do bar.aim = pick(w, eye, ray, above_level(a), true, 4*linalg.length(a.at - eye) + 600, true)   // through leaf and limb, to the ground: no order is given to a crown
	if !a.marking || !a.shown do return
	o := a.mark[0]
	b := a.mark[1]
	switch {
	case bar.tool == .Fell || bar.tool == .Send || bar.tool == .Remove:   // the column under the pointer, whatever stands in it: a wall is taken down by dragging along its top
		if bar.aim.ok do b = bar.aim.block
	case ray.y < -1e-3:
		t := (f64(o.y) + 0.5 - eye.y)/f64(ray.y)
		b = {i32(math.floor(eye.x + f64(ray.x)*t)), o.y, i32(math.floor(eye.z + f64(ray.z)*t))}
	}
	for k in ([2]int{0, 2}) do b[k] = clamp(b[k], o[k] - 199, o[k] + 199)
	if tool_line() {   // along the way it was dragged farther
		if abs(b.x - o.x) >= abs(b.z - o.z) do b.z = o.z
		else do b.x = o.x
	}
	if linalg.length((a.pointer - bar.press_at)*[2]f32{screen.w, screen.h}) > 6*max(play.ratio, 1) do bar.dragged = true
	a.mark[1] = b if bar.dragged else o   // a click is the block it took: a hand's tremble marks no second
}

// The button goes down on the world with a tool held.
tool_begin :: proc(a: ^Above) {
	if !a.shown || !bar.aim.ok do return
	a.mark, a.marking, a.marked = {bar.aim.block, bar.aim.block}, true, true
	bar.press, bar.press_at, bar.dragged = a.under, a.pointer, false
}

// The way the picture's top faces, to the nearest of the four ways a stair can run.
ahead :: proc(a: ^Above) -> [3]i32 {
	x, z := math.sin(a.yaw), -math.cos(a.yaw)
	return {1 if x > 0 else -1, 0, 0} if abs(x) > abs(z) else {0, 0, 1 if z > 0 else -1}
}

// The order the tool would give for a mark from one block to another. A click with a stair is
// three steps the way the view faces: a stair is something to walk, and one step is not.
tool_order :: proc(a: ^Above, m0, m1: [3]i32, press: Pick, dragged: bool) -> (o: Order, ok: bool) {
	far := m1
	switch bar.tool {
	case .None:
	case .Dig:
		if bar.dig == .Out do return {kind = .Dig, shape = .Out, at = m0, to = {m1.x, m0.y - bar.deep + 1, m1.z}}, true
		if far == m0 do far = m0 + ahead(a)*2
		return {kind = .Dig, shape = bar.dig, at = m0, to = far}, true
	case .Fell:
		if !dragged && press.ok do if t := thing_at(play.w, press); t.kind == .Tree && t.tree.form != .Fallen && t.island != nil {   // a click on any part of a tree is that tree
			foot := [3]i32{t.tree.x + t.island.region.origin.x, t.tree.base, t.tree.z + t.island.region.origin.y}
			return {kind = .Fell, at = foot, to = foot}, true
		}
		return {kind = .Fell, at = m0, to = m1}, true
	case .Build:
		switch bar.build {
		case .Out, .Down, .Up:
		case .Wall:  return {kind = .Build, shape = .Wall, stuff = bar.stuff, at = m0, to = {m1.x, m0.y + bar.high - 1, m1.z}}, true
		case .Floor: return {kind = .Build, shape = .Floor, stuff = bar.stuff, at = m0, to = m1}, true
		case .Stair:
			if far == m0 do far = m0 + ahead(a)*2
			return {kind = .Build, shape = .Stair, stuff = bar.stuff, at = m0, to = far}, true
		}
	case .Store:  return {kind = .Store, at = m0, to = m1, takes = bar.takes}, true
	case .Send:   return {kind = .Go, at = m1}, true
	case .Remove: return {kind = .Unmark, at = m0, to = m1}, true
	}
	return
}

// The button is let go on the world with a tool in the hand: the order is given.
tool_give :: proc(a: ^Above) {
	if !a.marked do return
	if o, ok := tool_order(a, a.mark[0], a.mark[1], bar.press, bar.dragged); ok do hold_order(o)
	mark_clear(a)
	if bar.tool == .Send do bar.tool = .None   // one place is one order
}

// The world's blocks as the frame has them, for an order's shape to be shown before it is given.
world_blocks :: proc(w: ^World) -> Blocks {
	return {proc(data: rawptr, b: [3]i32) -> Mat { return block_made(cast(^World)data, b) },
		proc(data: rawptr, b: [3]i32) -> bool {
			w := cast(^World)data
			under := block_made(w, b - {0, 1, 0})
			if block_made(w, b) != .Air || block_made(w, b + {0, 1, 0}) != .Air || under == .Air || is(under, PLANT_BLOCKS) do return false
			f := island_at(f64(b.x) + 0.5, f64(b.z) + 0.5)
			if f == nil || !is_formed(f) do return false
			was := here
			defer bind(was)
			bind(f)
			g := ground(f64(b.x - region.origin.x) + 0.5, f64(b.z - region.origin.y) + 0.5, 1)   // the water the land stands there, which a dwarf wades half a metre of
			return f32(b.y) > g.h + 0.5 || g.water - f32(b.y) <= WADE
		}, w}
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

// Each frame, before the screen is listed: which order the hand's thing belongs to, what the tool
// would mark, and the alerts.
bar_frame :: proc() {
	u := &play
	if u.hand.kind == .None do bar.job = -1
	else if u.hand.block != bar.for_hand {
		bar.for_hand = u.hand.block
		bar.job = job_of(u.hand)
	}
	if _, ok := site_seen(bar.job); !ok do bar.job = -1
	preview()
	alerts_keep()
}

// What the tool would mark: the box being dragged, or a click where the pointer is. Worked out by
// the hold's own rule over the blocks the frame has, and again only when something it reads changes.
preview :: proc() {
	u, a := &play, play.a
	pressed := (a.marking || bar.posed) && a.marked
	if !tool_marks() || !pressed && !(a.shown && bar.aim.ok) {
		clear(&bar.cells); clear(&bar.boxes); clear(&bar.trees)
		bar.ready, bar.way, bar.seen = false, 0, {}
		return
	}
	m0, m1 := bar.aim.block, bar.aim.block
	press, dragged := a.under, false
	if pressed do m0, m1, press, dragged = a.mark[0], a.mark[1], bar.press, bar.dragged || bar.posed
	key := Preview_Key{bar.tool, bar.dig, bar.build, bar.stuff, bar.takes, bar.deep, bar.high, m0, m1, press.block, dragged, pressed, u.w.volume, watch.seen.marks}
	if key == bar.seen do return
	bar.seen = key
	clear(&bar.cells); clear(&bar.boxes); clear(&bar.trees)
	bar.way = 0
	bar.order, bar.ready = tool_order(a, m0, m1, press, dragged)
	if !bar.ready do return
	o := bar.order
	lo, hi := box_of(o.at, o.to)
	#partial switch o.kind {
	case .Dig:
		cells_of(.Dig, o.shape, o.at, o.to, world_blocks(u.w), &bar.cells)
		boxes_of(bar.cells[:], &bar.boxes)
	case .Build:
		cells_of(.Build, o.shape, o.at, o.to, world_blocks(u.w), &bar.cells)
	case .Fell:
		if f := island_at(f64(lo.x) + 0.5, f64(lo.z) + 0.5); f != nil && is_formed(f) {
			bound(f)
			trees_standing(lo.x - region.origin.x, lo.z - region.origin.y, hi.x - region.origin.x, hi.z - region.origin.y, &bar.trees)
			for i := len(bar.trees) - 1; i >= 0; i -= 1 {
				t := bar.trees[i]
				foot := [3]i32{t.x + region.origin.x, t.base, t.z + region.origin.y}
				if t.form == .Fallen || !is(block_made(u.w, foot), PLANT_BLOCKS) do unordered_remove(&bar.trees, i)   // fallen, or felled already
			}
			bound(here)
		}
		if dragged do append(&bar.boxes, [2][3]i32{{lo.x, -500, lo.z}, {hi.x, 3000, hi.z}})   // the ground dragged over, whatever its height
	case .Store:   // the ground a dwarf can stand on in the rectangle, near the level it began on
		zone_cells(o.at, o.to, world_blocks(u.w), &bar.cells)
		floor := make([dynamic][3]i32, context.temp_allocator)
		for c in bar.cells do append(&floor, c - {0, 1, 0})
		boxes_of(floor[:], &bar.boxes)
	case .Unmark:   // marks first; with none, built blocks; with none, a stockpile's ground: what the hold will do (mark_obey)
		append(&bar.boxes, [2][3]i32{{lo.x, -500, lo.z}, {hi.x, 3000, hi.z}})
		overlap :: proc(t: Tint, lo, hi: [3]i32) -> int {
			if t.lo.x > hi.x || t.hi.x < lo.x || t.lo.z > hi.z || t.hi.z < lo.z do return 0
			return int(min(t.hi.x, hi.x) - max(t.lo.x, lo.x) + 1)*int(min(t.hi.z, hi.z) - max(t.lo.z, lo.z) + 1)*int(t.hi.y - t.lo.y + 1)
		}
		bar.undo = .Marks
		for t in watch.seen.tints do bar.way += overlap(t, lo, hi)
		for g in watch.seen.ghosts do bar.way += int(g.at.x >= lo.x && g.at.x <= hi.x && g.at.z >= lo.z && g.at.z <= hi.z)
		if bar.way == 0 {
			bar.undo = .Built
			for c in bar.built do bar.way += int(c.x >= lo.x && c.x <= hi.x && c.z >= lo.z && c.z <= hi.z)
		}
		if bar.way == 0 {
			bar.undo = .Zone
			for t in watch.seen.zone_boxes do bar.way += overlap(t, lo, hi)
		}
	}
}

// What an order is, in a word or two: the head of its name, which goes on to say where.
site_word :: proc(site: Site_Seen) -> string {
	if at := strings.index(site.place, " at "); at > 0 do return site.place[:at]
	return site.place
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
	moving := false   // some order has work in hand or free to take: ground may yet be opened toward one that has none
	for site in s.sites do moving ||= site.busy > 0 || site.waits[.None] > 0
	for site in s.sites {
		if site.busy == 0 && site.left > 0 && site.waits[.Front] + site.waits[.No_Way] + site.waits[.No_Room] == site.left && (!moving || site.waits[.No_Way] + site.waits[.No_Room] > 0) {   // nothing of it in hand or free to take, and none of it within any floor's reach
			if reach == 0 do first[0] = site
			reach += 1
		}
		if site.waits[.No_Stuff] > 0 && site.busy == 0 && site.have + site.coming == 0 && stuff_lying(site.stuff) == 0 {   // none to be had anywhere: what is only waiting to be brought is no trouble
			if stuff == 0 do first[1] = site
			stuff += 1
		}
		if site.waits[.Too_Hard] == site.left && site.left > 0 {
			if hard == 0 do first[2] = site
			hard += 1
		}
	}
	middle :: proc(site: Site_Seen) -> [3]f64 { return {f64(site.lo.x + site.hi.x + 1)/2, f64(site.hi.y), f64(site.lo.z + site.hi.z + 1)/2} }
	if reach == 1 do texts[0] = fmt.tprintf("No dwarf has a way to the %s.", site_word(first[0]))
	else if reach > 1 do texts[0] = fmt.tprintf("No dwarf has a way to %s orders.", count_words(reach))
	if stuff >= 1 do texts[1] = fmt.tprintf("No %s anywhere for the %s: %s.", STUFFS[first[1].stuff], site_word(first[1]), "dig rock" if first[1].stuff == .Stone else "fell trees")
	if hard >= 1 do texts[1] = fmt.tprintf("%s%sRock too hard for the picks.", texts[1], " " if texts[1] != "" else "")
	places[0], places[1] = middle(first[0]), middle(first[1] if stuff > 0 else first[2])
	ids := [3]string{"orders.reach", "orders.store", ""}   // a dwarf shut in is the dwarves' own alert (NEEDS, crowd.odin)
	for text, i in texts do if text != bar.said[i] && ids[i] != "" {
		delete(bar.said[i])
		bar.said[i] = strings.clone(text)
		if text == "" do alert_clear(ids[i])
		else do alert_raise(ids[i], text, .Trouble if i != 1 else .Caution, places[i])
	}
}

// What is marked, for the picture: the boxes of ground to dig, which the terrain tints, what the
// tool would mark among them, brighter; and after the frame's boxes a band on each tree to fell
// and a small block for each block to lay.
marks_view :: proc(v: ^View, boxes: []Box, eye: [3]f64) -> []Box {
	s, a := &watch.seen, play.a
	boxes := piles_view(boxes, eye, a.at if !play.afoot^ else eye)
	if play.afoot^ && len(s.ghosts) == 0 do return boxes
	n := 0
	put :: proc(v: ^View, n: ^int, lo, hi: [3]i32, kind: f32, eye: [3]f64) {
		if n^ >= len(v.tints) do return
		v.tints[n^] = {f32(f64(lo.x) - eye.x), f32(f64(lo.y) - eye.y), f32(f64(lo.z) - eye.z), kind}
		v.tint_sizes[n^] = {f32(hi.x - lo.x + 1), f32(hi.y - lo.y + 1), f32(hi.z - lo.z + 1), 0}
		n^ += 1
	}
	far :: proc(lo, hi: [3]i32, at: [3]f64) -> f64 { return abs(f64(lo.x + hi.x)/2 - at.x) + abs(f64(lo.z + hi.z)/2 - at.z) }
	if tool_marks() && bar.ready {
		v.has_mark = bar.tool == .Send
		for b in bar.boxes[:min(len(bar.boxes), TINTS/2)] do put(v, &n, b[0], b[1], 3 if bar.tool == .Remove else 2, eye)
		if bar.tool == .Dig && len(bar.boxes) > 0 && a.marked && (a.marking || bar.posed) {   // and, through a drag, its outline on the ground over it, so a box under a hillside shows where it lies; with nothing pressed only the blocks themselves are lit
			lo, hi := bar.boxes[0][0], bar.boxes[0][1]
			for b in bar.boxes do lo, hi = {min(lo.x, b[0].x), min(lo.y, b[0].y), min(lo.z, b[0].z)}, {max(hi.x, b[1].x), max(hi.y, b[1].y), max(hi.z, b[1].z)}
			put(v, &n, {lo.x, hi.y + 1, lo.z}, {hi.x, 3000, hi.z}, 5, eye)
		}
	} else do v.has_mark = v.has_mark && !tool_marks()
	// The nearest the view's middle first, where there are more than the picture takes.
	near := make([dynamic]Tint, context.temp_allocator)
	for t in s.tints do append(&near, t)
	if len(near) > TINTS - n do for i in 1..<len(near) do for k := i; k > 0 && far(near[k].lo, near[k].hi, a.at) < far(near[k - 1].lo, near[k - 1].hi, a.at); k -= 1 do near[k], near[k - 1] = near[k - 1], near[k]
	for t in near do put(v, &n, t.lo, t.hi, 4 if t.site == bar.job else 1, eye)
	for site in s.sites do if site.work == .Dig do put(v, &n, {site.lo.x, site.hi.y + 1, site.lo.z}, {site.hi.x, 3000, site.hi.z}, 6, eye)   // faintly, the ground over each
	for t in s.zone_boxes do put(v, &n, t.lo, t.hi, 7, eye)   // the stockpiles' ground, in the colour of what is well
	v.tint_count = n

	out := make([dynamic]Box, 0, len(boxes) + len(s.ghosts) + len(bar.cells) + len(bar.trees), context.temp_allocator)
	append(&out, ..boxes)
	rel :: proc(p, eye: [3]f64) -> [3]f32 { return {f32(p.x - eye.x), f32(p.y - eye.y), f32(p.z - eye.z)} }
	cube :: proc(out: ^[dynamic]Box, at: [3]f32, half: [3]f32, upper, under: u32) {
		append(out, Box{at, f32(upper), {half.x, 0, 0}, f32(under), {0, half.y, 0}, 0, {0, 0, half.z}, at.y - half.y - 1e-3})   // drawn whole or not at all by the cut, as a dwarf is
	}
	rgb :: proc(c: Colour) -> u32 { return u32(c.r) << 16 | u32(c.g) << 8 | u32(c.b) }
	stuff_colour :: proc(stuff: Stuff, store: ^[Mat]i32) -> u32 {
		_, most := store_of(store, stuff)
		if stuff == .Timber do most = .Timber
		else if most == .Air do most = .Basalt
		c := MATERIALS[most].colour
		return u32(math.pow(c.r, 1/2.2)*255) << 16 | u32(math.pow(c.g, 1/2.2)*255) << 8 | u32(math.pow(c.b, 1/2.2)*255)
	}
	brass := rgb(LOOK.brass)
	framed := make(map[int]int, context.temp_allocator)   // of each order to build, the blocks drawn as holding their stuff
	for g in s.ghosts {
		if len(out) >= BOX_MAX - 64 do break
		at := rel({f64(g.at.x) + 0.5, f64(g.at.y) + 0.5, f64(g.at.z) + 0.5}, eye)
		chosen := g.site == bar.job
		switch g.work {
		case .Fell:   // a band round the stem, at a dwarf's shoulder, and a cap on the crown, which is what shows from above
			cube(&out, at + {0, 0.6, 0}, {0.62, 0.14 if chosen else 0.09, 0.62}, brass, brass)
			cube(&out, at + {0, f32(g.tall) + 0.1, 0}, {0.6, 0.14, 0.6} if chosen else {0.5, 0.1, 0.5}, brass, brass)
		case .Build:   // a small block while its stuff is still to be brought, and nearly whole once it lies at the order: marked, brought, and then built
			site, _ := site_seen(g.site)
			brought := framed[g.site] < site.have
			framed[g.site] += 1
			half := [3]f32{0.42, 0.42, 0.42} if brought else {0.3, 0.3, 0.3} if chosen else {0.2, 0.2, 0.2}
			cube(&out, at, half, stuff_colour(g.stuff, &s.store), stuff_colour(g.stuff, &s.store) if brought else brass)
		case .Dig:
		}
	}
	// And what the tool would lay or fell.
	if !tool_marks() || !bar.ready do return out[:]
	if bar.tool == .Build do for c in bar.cells[:min(len(bar.cells), 2000)] do cube(&out, rel({f64(c.x) + 0.5, f64(c.y) + 0.5, f64(c.z) + 0.5}, eye), {0.34, 0.34, 0.34}, stuff_colour(bar.stuff, &s.store), brass)
	if f := island_at(a.at.x, a.at.z); f != nil do for t in bar.trees {   // a band at the foot and a cap on the crown, so a tree marked shows from above and under leaves
		foot := [3]f64{f64(t.x + f.region.origin.x) + 0.5, f64(t.base), f64(t.z + f.region.origin.y) + 0.5}
		cube(&out, rel(foot + {0, 1.1, 0}, eye), {0.66, 0.16, 0.66}, brass, brass)
		cube(&out, rel(foot + {0, f64(t.height) + 0.6, 0}, eye), {0.7, 0.16, 0.7}, brass, brass)
	}
	return out[:]
}

// ---- words ----------------------------------------------------------------------------------

// The tool's live line: what the drag would do, or what a click where the pointer is would.
tool_says :: proc() -> string {
	a := play.a
	if !bar.ready do return "Point at the land." if !a.shown || !bar.aim.ok else ""
	pressed := (a.marking || bar.posed) && a.marked
	o := bar.order
	lo, hi := box_of(o.at, o.to)
	wide, long := hi.x - lo.x + 1, hi.z - lo.z + 1
	n := len(bar.cells)
	blocks := "block" if n == 1 else "blocks"
	COMPASS := [4]string{"east", "west", "south", "north"}
	heading :: proc(o: Order) -> int { axis, way, _ := stair_run(o.at, o.to); return (0 if axis == 0 else 2) + (0 if way > 0 else 1) }
	under := block_made(play.w, bar.aim.block) if bar.aim.ok else Mat.Air
	name := sentence(mat_words(under))[:len(mat_words(under))]
	switch bar.tool {
	case .None:
	case .Dig:
		if n == 0 do return "Nothing to dig here: a tree's wood is felled, not dug." if is(under, PLANT_BLOCKS) else "Nothing to dig here."
		hard := 0
		for c in bar.cells do hard += int(MATERIALS[block_made(play.w, c)].strength > TOOLS)
		more := fmt.tprintf(" %d too hard for the picks.", hard) if hard > 0 else ""
		if o.shape != .Out {
			_, _, steps := stair_run(o.at, o.to)
			return fmt.tprintf("%d steps %s, heading %s: %d %s.%s", steps, "down" if o.shape == .Down else "up", COMPASS[heading(o)], n, blocks, more)
		}
		if !pressed do return fmt.tprintf("%s: %s, %.0f s a block. Here: %d %s.%s", name, cut_words(under), dig_seconds(under), n, blocks, more)
		return fmt.tprintf("%d by %d, %d deep: %d %s.%s", wide, long, hi.y - lo.y + 1, n, blocks, more)
	case .Fell:
		k := len(bar.trees)
		if k == 0 do return "No tree here." if !pressed || !bar.dragged else fmt.tprintf("%d by %d: no tree stands in it.", wide, long)
		timber := 0
		for t in bar.trees do timber += max(int(t.height)/2, 1) if t.kind != .Scrub else 0
		if k == 1 {
			t := bar.trees[0]
			if t.kind == .Scrub do return "A bush of scrub: cleared, no timber."
			return fmt.tprintf("%s tree, %d m: %d timber.", sentence(SPECIES[t.kind].name)[:len(SPECIES[t.kind].name)], t.height, timber)
		}
		return fmt.tprintf("%d trees: %d timber.", k, timber)
	case .Build:
		have := stuff_lying(bar.stuff)
		short := "" if have >= n else fmt.tprintf(" %d to be had: the rest waits.", have)
		if n == 0 do return "Nothing to lay here: a floor fills what is open at this level." if o.shape == .Floor else "Nothing to lay here."
		switch o.shape {
		case .Out, .Down, .Up:
		case .Wall:  return fmt.tprintf("Wall %d long, %d high: %d %s of %s.%s", max(wide, long), bar.high, n, blocks, STUFFS[bar.stuff], short)
		case .Floor: return fmt.tprintf("Floor %d by %d: %d %s of %s.%s", wide, long, n, blocks, STUFFS[bar.stuff], short)
		case .Stair:
			_, _, steps := stair_run(o.at, o.to)
			return fmt.tprintf("%d steps up, heading %s: %d %s of %s.%s", steps, COMPASS[heading(o)], n, blocks, STUFFS[bar.stuff], short)
		}
	case .Store:
		if !pressed do if z, on := zone_under(bar.aim.block + {0, 1, 0}); on do return fmt.tprintf("A stockpile for %s: %d of %d places hold something. Drag beside it to make it larger.", TAKES_SAYS[z.takes], z.full, z.cells)
		if n == 0 do return "No ground to store on here."
		return fmt.tprintf("%d by %d: %d %s for %s.", wide, long, n, "place" if n == 1 else "places", TAKES_SAYS[bar.takes])
	case .Send:
		return "Click where the party should stand."
	case .Remove:
		if bar.way == 0 do return "Nothing here to take back, take down or take out of a stockpile."
		switch bar.undo {
		case .Marks: return fmt.tprintf("%d %s taken back.", bar.way, "mark" if bar.way == 1 else "marks")
		case .Built: return fmt.tprintf("%d built %s taken down; what they are of lies there.", bar.way, "block" if bar.way == 1 else "blocks")
		case .Zone:  return fmt.tprintf("%d %s taken out of the stockpile.", bar.way, "place" if bar.way == 1 else "places")
		}
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
	if !ok || u.card_open || u.hand.kind == .None do return false   // asked for more, the thing's own card
	u.area = .Hand
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	title := sentence(site_word(site))[:len(site_word(site))]
	unit := "trees" if site.work == .Fell else "blocks"
	hands := "no dwarf at it" if site.busy == 0 else "one dwarf at it" if site.busy == 1 else fmt.tprintf("%s dwarves at it", count_words(site.busy))
	line := fmt.tprintf("%d of %d %s left, %s.", site.left, site.total, unit, hands)
	idle := 0
	for d in watch.seen.dwarves do idle += int(!d.job && (d.doing == .Waiting || d.doing == .Stopped) && !d.shut)
	next := waits_words(site, idle)
	if next != "" do next = fmt.tprintf("%s.", next)
	high := 2*px(L.pad.y) + line_of(.Title) + text_high(.Body, line, inner) + (px(1) + text_high(.Body, next, inner) if next != "" else 0) + px(3) + px(L.button)
	r := Rect{x, screen.h - px(L.hand_foot) - high, w, high}
	part(.Panel, r, id = "hand")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	y += words(cx, y, title, .Title, id = "job.title")
	y += words(cx, y, line, .Body, {}, "job.line", inner)
	if next != "" do y += px(1) + words(cx, y, next, .Body, L.brass if strings.has_prefix(next, "Wait") else L.ash, "job.waits", inner)
	y += px(3)
	gw := button_wide("Go there", key_for(.Go))
	button({cx, y, gw, px(L.button)}, "Go there", .Go, 0, false, "job.go", "Put the view over it.")
	bw := button_wide("Take it back", "")
	button({cx + gw + px(L.gap), y, bw, px(L.button)}, "Take it back", .Take_Back, 0, false, "job.back", "Take this order back: nothing more of it is done.")
	button({cx + gw + bw + 2*px(L.gap), y, button_wide("More", key_for(.More)), px(L.button)}, "More", .More, 0, false, "hand.more", "What the ground under the mark is, and why.")
	return true
}

// A row of the tool's card: a few choices, one of them chosen.
chips :: proc(x, y: f32, label: string, names: []string, chosen: int, act: Act, args: []int, id: string, tips: []string = nil) {
	L := &LOOK
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	tx := x
	if label != "" {
		words(tx, y + px(L.chip_pad.y), label, .Body, L.ash, fmt.tprintf("%s.label", id))
		tx += text_wide(.Body, label) + px(3)
	}
	for name, i in names {
		cw := text_wide(.Body, name) + 2*px(L.chip_pad.x)
		part(.Chip, {tx, y, cw, chip}, name, .Body, {}, {.Chosen} if i == chosen else {}, act, args[i], id = id, tip = tips[i] if tips != nil else "")
		tx += cw + px(L.gap)
	}
}

// The tool's card: its name, its few choices as buttons, and one live line saying what the drag
// will do. It is as high whatever it says, so nothing on it moves under the pointer.
tool_card :: proc() {
	u, L := &play, &LOOK
	u.area = .Hand
	row := TOOL_ROWS[bar.tool]
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	chip := line_of(.Body) + 2*px(L.chip_pad.y)
	rows := 2 if bar.tool == .Dig else 3 if bar.tool == .Build else 1 if bar.tool == .Store else 0
	high := 2*px(L.pad.y) + line_of(.Title) + f32(rows)*(chip + px(1.5)) + px(1.5) + 2*line_of(.Body)
	r := Rect{x, screen.h - px(L.hand_foot) - high, w, high}
	part(.Panel, r, id = "hand")
	cx, y := x + px(L.pad.x), r.y + px(L.pad.y)
	words(cx, y, row.name, .Title, L.brass, "tool.title")
	down := button_wide("Put down", key_for(.Escape), .Small, L.chip_pad.x)
	part(.Chip, {cx + inner - down, y, down, line_of(.Small) + 2*px(L.chip_pad.y)}, "Put down", .Small, {}, {}, .Order, int(bar.tool), key_for(.Escape), "tool.drop", "Put the tool down.")
	y += line_of(.Title) + px(1.5)
	numbers := [DEEPEST]string{"1", "2", "3", "4"}
	args := [DEEPEST]int{1, 2, 3, 4}
	#partial switch bar.tool {
	case .Store:
		names := [Takes]string{.All = "Everything", .Stone = "Stone", .Timber = "Timber"}
		takes := [len(Takes)]int{int(Takes.All), int(Takes.Stone), int(Takes.Timber)}
		chips(cx, y, "Takes", ([]string{names[.All], names[.Stone], names[.Timber]}), int(bar.takes), .Takes, takes[:], "tool.takes")
		y += chip + px(1.5)
	case .Dig:
		names, tips: [len(DIG_CHOICES)]string
		plans: [len(DIG_CHOICES)]int
		chosen := 0
		for c, i in DIG_CHOICES {
			names[i], plans[i], tips[i] = c.name, int(c.plan), c.says
			if c.plan == bar.dig do chosen = i
		}
		chips(cx, y, "", names[:], chosen, .Plan, plans[:], "tool.choice", tips[:])
		y += chip + px(1.5)
		if bar.dig == .Out do chips(cx, y, "Deep", numbers[:], int(bar.deep) - 1, .Deep, args[:], "tool.deep")
		y += chip + px(1.5)
	case .Build:
		names, tips: [len(BUILD_CHOICES)]string
		plans: [len(BUILD_CHOICES)]int
		chosen := 0
		for c, i in BUILD_CHOICES {
			names[i], plans[i], tips[i] = c.name, int(c.plan), c.says
			if c.plan == bar.build do chosen = i
		}
		chips(cx, y, "", names[:], chosen, .Plan, plans[:], "tool.choice", tips[:])
		y += chip + px(1.5)
		stuffs: [len(Stuff)]string
		stuff_args: [len(Stuff)]int
		for name, stuff in STUFFS {
			stuffs[int(stuff)], stuff_args[int(stuff)] = fmt.tprintf("%s %d", sentence(name)[:len(name)], stuff_lying(stuff)), int(stuff)
		}
		chips(cx, y, "Of", stuffs[:], int(bar.stuff), .Stuff, stuff_args[:], "tool.stuff")
		y += chip + px(1.5)
		if bar.build == .Wall do chips(cx, y, "High", numbers[:2], int(bar.high) - 1, .High, args[:2], "tool.high")   // as high as a mason reaches from the ground: higher waits for scaffolds
		y += chip + px(1.5)
	}
	y += px(1.5)
	says := tool_says()
	pressed := (play.a.marking || bar.posed) && play.a.marked
	u.clip = {cx, y, inner, 2*line_of(.Body)}
	words(cx, y, says, .Body, L.brass if pressed else L.chalk, "tool.says", inner)
	u.clip = {}
}

// The stockpile a cell of ground belongs to, as the hold last showed it.
zone_under :: proc(c: [3]i32) -> (z: Zone_Seen, on: bool) {
	s := &watch.seen
	b := c - {0, 1, 0}
	for t in s.zone_boxes do if b.x >= t.lo.x && b.x <= t.hi.x && b.y >= t.lo.y && b.y <= t.hi.y && b.z >= t.lo.z && b.z <= t.hi.z {
		for zone in s.zones do if zone.id == t.site do return zone, true
	}
	return
}

// A material's colour as the boxes take it, lighter or darker by a share.
shaded :: proc(m: Mat, by: f32) -> u32 {
	c := MATERIALS[m].colour*by
	return u32(clamp(math.pow(c.r, 1/2.2), 0, 1)*255) << 16 | u32(clamp(math.pow(c.g, 1/2.2), 0, 1)*255) << 8 | u32(clamp(math.pow(c.b, 1/2.2), 0, 1)*255)
}

// A material's colour as the boxes take it.
mat_rgb :: proc(m: Mat) -> u32 {
	c := MATERIALS[m].colour
	return u32(math.pow(c.r, 1/2.2)*255) << 16 | u32(math.pow(c.g, 1/2.2)*255) << 8 | u32(math.pow(c.b, 1/2.2)*255)
}

// The things that lie in the world, as boxes after the frame's: stone as a heap of small blocks,
// two by two a layer; timber as logs laid side by side, three a layer, each layer across the one
// under it. A pile is drawn whole or not at all by the cut, as a dwarf is.
PILES_FAR :: 160   // metres from the view's middle past which a pile is not drawn
piles_view :: proc(boxes: []Box, eye, middle: [3]f64) -> []Box {
	s := &watch.seen
	if len(s.piles) == 0 do return boxes
	out := make([dynamic]Box, 0, len(boxes) + 8*len(s.piles), context.temp_allocator)
	append(&out, ..boxes)
	for p in s.piles {
		if len(out) >= BOX_MAX - 512 do break
		if abs(f64(p.at.x) - middle.x) > PILES_FAR || abs(f64(p.at.z) - middle.z) > PILES_FAR do continue
		base := [3]f32{f32(f64(p.at.x) + 0.5 - eye.x), f32(f64(p.at.y) - eye.y), f32(f64(p.at.z) + 0.5 - eye.z)}
		feet := base.y - 1e-3
		n := int(min(p.n, HEAP))
		if is_stuff(p.kind, .Timber) {
			bark, wood := mat_rgb(p.kind if p.kind != .Timber else .Wood), mat_rgb(.Timber)
			for k in 0..<n {
				layer, slot := k/3, f32(k%3) - 1
				along := layer%2 == 0
				at := base + {0 if along else slot*0.3, 0.14 + f32(layer)*0.28, slot*0.3 if along else 0}
				half := [3]f32{0.46, 0.13, 0.13} if along else {0.13, 0.13, 0.46}
				append(&out, Box{at, f32(bark), {half.x, 0, 0}, f32(wood if k == n - 1 else bark), {0, half.y, 0}, 0, {0, 0, half.z}, feet})
			}
			continue
		}
		for k in 0..<n {   // stones a little apart and no two of one shade, so a heap reads as stones and not as a block
			layer, slot := k/4, k%4
			jog := f32((p.at.x*7 + p.at.z*13 + i32(k)*5)%%5 - 2)*0.03
			size := f32(0.13) + 0.014*f32((p.at.x + p.at.z*3 + i32(k)*7)%%4)
			at := base + {(f32(slot%2) - 0.5)*0.5 + jog, size + f32(layer)*0.31, (f32(slot/2) - 0.5)*0.5 - jog}
			shade := f32(1.0) + 0.22*f32((i32(k)*3 + p.at.x)%%4)   // fresh broken rock is paler than the weathered face it lay under
			append(&out, Box{at, f32(shaded(p.kind, shade*1.45)), {size, 0, 0}, f32(shaded(p.kind, shade)), {0, size, 0}, 0, {0, 0, size}, feet})
		}
	}
	return out[:]
}

// How much of a stuff lies anywhere, stored or loose: what a block marked to be laid can be built of.
stuff_lying :: proc(stuff: Stuff) -> (n: int) {
	s := &watch.seen
	for count, m in s.store do if is_stuff(m, stuff) do n += int(count)
	for count, m in s.loose do if is_stuff(m, stuff) do n += int(count)
	return
}

// A stair the tool would mark says how deep it goes: a figure on the ground over each step, the
// blocks it lies under the level the drag began on, or over it.
stair_marks :: proc() {
	L := &LOOK
	if !tool_marks() || !bar.ready || bar.order.kind != .Dig || bar.order.shape == .Out do return
	o := bar.order
	axis, way, steps := stair_run(o.at, o.to)
	for i in 0..<steps {
		c := o.at
		c[axis] += way*i
		at, ok := project({f64(c.x) + 0.5, f64(o.at.y) + 1.05, f64(c.z) + 0.5})
		if !ok do continue
		text := fmt.tprintf("%s%d", "-" if o.shape == .Down else "+", i + 1)
		w := text_wide(.Small_Bold, text)
		r := Rect{math.round(at.x - w/2), math.round(at.y - line_of(.Small_Bold)/2), w, line_of(.Small_Bold)}
		part(.Fill, {r.x - px(1), r.y, r.w + px(2), r.h}, colour = L.basalt)
		part(.Text, r, text, .Small_Bold, L.brass, id = "tool.step")
	}
}
