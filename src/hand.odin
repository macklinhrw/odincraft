package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"

// The hand (interface.md, I2 and I3): what a click on the world picks up, and what its card says.
// Anything can be picked up: a block of ground, a tree, a stream, a lake, the sea, a named place,
// an animal, a dwarf or several, or a box of blocks marked by dragging. A dwarf's card is the hold's own
// (hold_card, hold.odin; dwarf_says, crowd.odin), read afresh each frame, since a dwarf goes on with its day. A card leads with what the thing is in a line
// and why in the next, in sentences written for it here from the land's own records; the rest of
// what `--why` says of its ground is a tab away, in its own words, and under a block of ground
// stands the column of rock it lies in.

Thing_Kind :: enum u8 { None, Ground, Tree, Stream, Lake, Sea, Place, Animal, Box, Dwarf, Dwarves, Pile, Zone }   // Dwarves: several of them, as a group (Play.several); Pile: things lying in a cell; Zone: a stockpile's ground (goods.odin)
Thing :: struct {
	kind:     Thing_Kind,
	island:   ^Formed,
	block:    [3]i32,   // the block clicked, in the world
	lo, hi:   [3]i32,   // the blocks it marks, in the world
	mat:      Mat,      // what the block is made of
	tree:     Tree,
	feature:  int,      // a lake's or pond's, or -1
	place:    int,      // a candidate for a place on its island; named where another has not taken it in
	creature: int,      // its row in CREATURES
	dwarf:    int,      // which of the hold's dwarves (hold.odin)
	nest:     bool,     // and it is that animal's nest
}

// The depths of a card: its own, then what --why says of the ground it stands on, by part.
// A dwarf's are its trade and what it knows of itself (dwarf_says, crowd.odin).
Depth :: enum u8 { Own, Rock, Ground, Plants, Near, World, Self }
DEPTHS := [Depth]string{.Own = "", .Rock = "Rock", .Ground = "Ground", .Plants = "Plants", .Near = "Near", .World = "World", .Self = "Self"}
OWN := [Thing_Kind]string{.None = "", .Ground = "", .Tree = "Tree", .Stream = "Stream", .Lake = "Water", .Sea = "Sea", .Place = "Place", .Animal = "Animal", .Box = "Blocks", .Dwarf = "Trade", .Dwarves = "", .Pile = "", .Zone = ""}

Hand_Card :: struct {
	title, sub, line: string,
	mat:    Mat,              // shown as a block of itself at the card's head; Air for none
	tint:   Colour,           // or a plain square of this
	says:   [Depth]string,    // each depth's words; empty where it has none
	column: bool,             // the column of rock stands under Rock
	x, z:   i32,              // the column it stands on, in the world
	level:  i32,              // and the block marked on that column
}

card_free :: proc(c: ^Hand_Card) {
	delete(c.title); delete(c.sub); delete(c.line)
	for s in c.says do delete(s)
	c^ = {}
}

// ---- words ----------------------------------------------------------------------------------

// A material in words.
mat_words :: proc(m: Mat) -> string {
	named := #partial [Mat]string{.Air = "open", .Dirt = "earth", .Stone = "rock", .Litter = "leaf litter", .Susuki = "susuki grass", .Dune = "dune grass",
		.Wood = "tabu wood", .Leaves = "tabu leaves", .Shii_Bark = "shii wood", .Grey_Bark = "pale wood", .Pine_Bark = "pine wood", .Pine_Needles = "pine needles",
		.Black_Sand = "black sand", .Black_Shingle = "black shingle", .Red_Clay = "red clay", .Ash = "ash soil", .Red_Sandstone = "red sandstone"}
	if named[m] != "" do return named[m]
	name := strings.to_lower(fmt.tprintf("%v", m), context.temp_allocator)
	name, _ = strings.replace_all(name, "_", " ", context.temp_allocator)
	for form in ([3][2]string{{" scree", "scree of "}, {" broken", "broken "}, {" gravel", "gravel of "}}) do if strings.has_suffix(name, form[0]) {
		return fmt.tprintf("%s%s", form[1], strings.trim_suffix(name, form[0]))
	}
	return name
}

// What each rock is, in a sentence: how it was made and how it stands.
ROCK_SAYS := #partial [Mat]string{
	.Mudstone = "Mud laid in still water and pressed to a dark soft rock. It crumbles into flakes and never holds a face",
	.Siltstone = "Silt pressed into grey-brown flags that stand as thin ledges",
	.Sandstone = "Sand pressed into warm buff rock that breaks in square blocks. Water passes through it",
	.Grit = "A coarse pebbly rock, hard enough to cap the hills, that breaks in huge blocks",
	.Limestone = "The shells and mud of an old sea floor, pale grey. Water passes through its cracks",
	.Basalt = "A flow of lava, black-grey and hard, jointed into columns as it cooled",
	.Scoria = "Red-brown cinders and ash thrown out between the flows. It crumbles",
	.Rhyolite = "Stiff pale lava that stands in sheeted crags",
	.Tuff = "Cream pumice and ash, soft enough to crumble",
	.Reef = "Coral, shells and their sand, raised from the sea: rough, hard and full of holes. The rain sinks into it",
	.Red_Sandstone = "Sand laid in a dry past, in red square blocks",
	.Chalk = "White and crumbly, the ooze of a warm sea. Its cliffs fall as they are cut",
	.Coal = "A black seam a metre or two thick, old forest pressed between the beds",
	.Breccia = "Lava that shattered as it met the sea, set in its own ash: green-grey, lumpy and weak",
	.Dolerite = "The dark hard rock that fed a volcano, standing in the crack it rose through",
	.Granite = "Coarse pink-grey rock that cooled deep under the ground, its cracks wide apart",
	.Slate = "Mudstone squeezed in a fold belt until it split into blue-grey sheets standing on edge",
	.Schist = "Rock squeezed and heated into glittering wavy bands that part in slabs",
	.Gneiss = "Banded grey and pink, the deepest and oldest rock here, standing in knobs",
	.Quartzite = "Sandstone baked or squeezed hard: white and sharp-edged, the strongest rock there is",
	.Hornfels = "Mudstone baked beside a body of molten rock: dark, hard and splintery",
	.Marble = "Limestone baked beside a body of molten rock: white and crystalline",
}

// A sentence as a card shows it: begun with a capital, ended with a stop, with no name written as
// the code writes it.
sentence :: proc(s: string) -> string {
	t := strings.trim_space(s)
	if t == "" do return ""
	b := strings.builder_make(0, len(t) + 1, context.temp_allocator)
	begins := true   // a sentence begins here
	for i := 0; i < len(t); i += 1 {
		c := t[i]
		switch {
		case c == '_': c = ' '
		case begins && c >= 'a' && c <= 'z': c -= 32
		case !begins && c >= 'A' && c <= 'Z' && i > 0 && t[i - 1] == ' ':   // a material's name, written as the code names it
			for m in Mat do if says := ROCK_SAYS[m]; says != "" {
				if name := fmt.tprintf("%v", m); strings.has_prefix(t[i:], name) && (i + len(name) == len(t) || t[i + len(name)] < 'a' || t[i + len(name)] > 'z') do c += 32
			}
		}
		if c != ' ' do begins = (c == '.' || c == '?' || c == '!') && i + 1 < len(t) && t[i + 1] == ' '
		strings.write_byte(&b, c)
	}
	last := t[len(t) - 1]
	if last != '.' && last != '?' && last != '!' do strings.write_byte(&b, '.')
	return strings.to_string(b)
}

// A distance as a person says it.
far_words :: proc(d: f64) -> string { return fmt.tprintf("%.0f m", math.round(d/10)*10) if d < 1000 else fmt.tprintf("%.1f km", d/1000) }

// What --why says of the ground at a point in the world, cut into a card's depths. The parts are
// marked as why_at says them (why_part, fields.odin).
why_parts :: proc(f: ^Formed, wx, wz: f64) -> (parts: [Depth]string) {
	bound(f)
	hear_begin(true)
	why_at(wx, wz)
	heard := hear_end()
	b: [Depth]strings.Builder
	for &d in b do d = strings.builder_make(context.temp_allocator)
	at := Depth.Ground
	for line in strings.split_lines_iterator(&heard) {
		l := line
		for len(l) >= 2 && l[0] == 0x1f {
			at = Depth(l[1] - '0')
			l = l[2:]
		}
		if strings.trim_space(l) == "" do continue
		if strings.builder_len(b[at]) > 0 do strings.write_string(&b[at], "\n")
		strings.write_string(&b[at], sentence(l))
	}
	for &d, k in b do parts[k] = strings.clone(strings.to_string(d))
	return
}

// What a card says of the rock, rewritten to lead with the point: --why's first line is of the rock
// at the ground's top, and its second gives the island's story with every window it was read through.
rock_says :: proc(heard: string) -> string {
	LAID := [Laid]string{.Plates = "The plates laid it before and as the island rose", .Runny_Lava = "Its vents poured it out as runny lava", .Stiff_Lava = "Its vents pushed it up as stiff lava", .Coral = "Coral built it as the island rose"}
	b := strings.builder_make(context.temp_allocator)
	rest := heard
	for line in strings.split_lines_iterator(&rest) {
		l := line
		if strings.has_prefix(l, "The rock under the ground is") do l = fmt.tprintf("Under the soil here the rock is%s", strings.trim_prefix(l, "The rock under the ground is"))
		if strings.has_prefix(l, "The rock tells the story") {
			after, _ := strings.replace_all(region.story.after, "; ", " and ", context.temp_allocator)
			l = fmt.tprintf("The island's rock tells this story: %s, as at %s. %s.", region.story.name, after, LAID[laid_by(&KINDS[here.island.kind])])
		}
		fmt.sbprintf(&b, "%s%s", "\n" if strings.builder_len(b) > 0 else "", l)
	}
	return strings.to_string(b)
}

// ---- what is under a click ------------------------------------------------------------------

// The thing a picked block belongs to, as a person would name what they clicked: the tree it is
// part of, the water standing over it, or the block of ground itself.
thing_at :: proc(w: ^World, pick: Pick) -> (t: Thing) {
	b := pick.block
	t.block, t.lo, t.hi, t.feature = b, b, b, -1
	t.island = island_at(f64(b.x) + 0.5, f64(b.z) + 0.5)
	if t.island == nil || !is_formed(t.island) {
		t.kind, t.island = .Sea, nil
		return
	}
	t.mat = block_made(w, b)
	bound(t.island)
	x, z := f64(b.x) - f64(region.origin.x) + 0.5, f64(b.z) - f64(region.origin.y) + 0.5
	if is(t.mat, PLANT_BLOCKS) {   // the tree whose trunk stands nearest, of those whose crown reaches the block
		trees := make([dynamic]Tree, context.temp_allocator)
		trees_in(i32(math.floor(x)) - 10, i32(math.floor(z)) - 10, i32(math.floor(x)) + 10, i32(math.floor(z)) + 10, &trees, true)
		by := f32(1e9)
		for o in trees {
			d := math.hypot(f32(o.x) + 0.5 - f32(x), f32(o.z) + 0.5 - f32(z))
			reach := f32(max(o.radius, o.height) if o.form == .Fallen else o.radius) + 2
			if d < by && d <= reach && b.y >= o.base - 1 && b.y <= o.base + o.height + 2 do t.tree, by = o, d
		}
		if by < 1e9 {
			o, r := t.tree, t.tree.radius + 1
			if o.form == .Fallen do r = o.height
			at := [3]i32{o.x + region.origin.x, o.base, o.z + region.origin.y}
			t.kind, t.lo, t.hi = .Tree, at - {r, 0, r}, at + {r, max(o.height, 1) if o.form != .Fallen else 2, r}
			return
		}
	}
	g := ground(x, z, 1)
	if f32(b.y) + 1 >= g.h - 1.5 && g.water > f32(b.y) + 1 {   // the ground's top, with water standing over it
		t.lo, t.hi = b + {-1, 1, -1}, b + {1, 1, 1}
		if level, in_lake, _ := lake_near(x, z); in_lake && level > g.h {
			t.kind, t.feature = .Lake, int(land.lake[land_cell(x, z)]) - 1
			if t.feature < 0 do for o, i in region.features do if (o.kind == .Lake || o.kind == .Pond) && o.level == level do t.feature = i
		} else if r, near := river_near(f32(x), f32(z)); near && r.d < r.half + 1 {
			t.kind = .Stream
		} else {
			t.kind = .Sea if g.h < SEA_LEVEL + 0.5 else .Stream
		}
		return
	}
	t.kind = .Ground
	return
}

// The animal a ray from the eye meets first, of the frame's boxes: its row, where it is, and
// whether it is the row's nest. An animal is told by the colours of its parts, which no two share.
animal_under :: proc(boxes: []Box, eye: [3]f64, dir: [3]f32, slack: f32) -> (row: int, at: [3]f64, nest, ok: bool) {
	nearest := f32(1e9)
	for b in boxes {
		t0, t1 := f32(0), f32(1e9)
		for h in ([3][3]f32{b.x, b.y, b.z}) {
			l := linalg.length(h)
			if l == 0 do continue
			n := h/l
			o, d, half := -linalg.dot(b.centre, n), linalg.dot(dir, n), l + slack*linalg.length(b.centre)
			if abs(d) < 1e-6 {
				if abs(o) > half do t1 = -1
				continue
			}
			a, c := (-half - o)/d, (half - o)/d
			t0, t1 = max(t0, min(a, c)), min(t1, max(a, c))
		}
		if t0 > t1 || t0 >= nearest do continue
		for c, k in CREATURES do for p in c.parts do if f32(p.upper) == b.upper && f32(p.under) == b.under {
			row, nest, ok, nearest = k, false, true, t0
			at = eye + {f64(b.centre.x), f64(b.centre.y), f64(b.centre.z)}
		}
		if b.upper == f32(0x6e5f4a) || b.upper == f32(0x5c4e3a) do row, nest, ok, nearest, at = 1, true, true, t0, eye + {f64(b.centre.x), f64(b.centre.y), f64(b.centre.z)}   // the sticks of the osprey's nest (island_pose)
	}
	return
}

// ---- the column -----------------------------------------------------------------------------

// A run of one material down a column of the world: from `top` down to `foot`, the foot not in it.
Run :: struct { mat: Mat, top, foot: i32, sea: bool }

SOILS_OF :: bit_set[Trait]{.Cover, .Sand, .Silt}
soil_like :: proc(m: Mat) -> bool { return is(m, SOILS_OF) || m == .Loam || m == .Dirt || m == .Red_Clay || m == .Ash || m == .Black_Sand }

// The blocks of the column at a place in the world, from `top` down to `foot`, as runs of one
// material: the block volume's where it is loaded, with what has been dug and built, and the
// generator's ground elsewhere. Over the ground the sea is a run; the air is none.
column_runs :: proc(w: ^World, x, z, top, foot: i32) -> []Run {
	runs := make([dynamic]Run, context.temp_allocator)
	f := island_at(f64(x) + 0.5, f64(z) + 0.5)
	if f != nil && !is_formed(f) do f = nil
	was := here
	defer bind(was)
	if f != nil do bind(f)
	c: ^Chunk
	if w != nil do c = w.chunks[Key{0, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT}] or_else nil   // before play there is no block volume: the generator's ground
	if c != nil && !c.ready do c = nil
	k := int(x & (CHUNK - 1) + 1) + int(z & (CHUNK - 1) + 1)*P
	surface, bed_top, under := Mat.Sand, i32(SEA_BED), Under{}
	if c == nil && f != nil {
		g, m, _ := surface_at(f64(x) - f64(region.origin.x) + 0.5, f64(z) - f64(region.origin.y) + 0.5, 1)
		surface, bed_top, under = m, i32(math.round(g.h)), g.under
	}
	ground := ground_top(f64(x) + 0.5, f64(z) + 0.5)
	for y := min(top, ground) - 1; y >= foot; y -= 1 {
		m: Mat
		if c != nil {
			ly := y - c.y_base
			m = .Air if ly >= c.h else c.blocks[k + int(ly)*P*P] if ly >= 0 else under_rock(c, k, y, f == nil)
		} else {
			m = .Air if y >= bed_top else surface if y == bed_top - 1 || f == nil else crushed(rock_in(f32(y) + 0.5, under, 0), under)
		}
		if is(m, PLANT_BLOCKS) do m = .Air   // a root or a fallen trunk is not the ground
		sea := m == .Air && y < SEA_LEVEL && ground <= SEA_LEVEL
		if n := len(runs); n > 0 && runs[n - 1].mat == m && runs[n - 1].sea == sea do runs[n - 1].foot = y
		else do append(&runs, Run{m, y + 1, y, sea})
	}
	return runs[:]
}

// How much of the ground a column shows: the least of these metres that holds the ground's top,
// a little air over it, and the level asked for with some rock under it.
SPANS :: [6]i32{120, 240, 480, 960, 1920, 3840}
column_fit :: proc(ground, level: i32) -> (top, span: i32) {
	spans := SPANS
	for s in spans {
		top, span = ground + s/15, s
		if level - s/5 >= top - s do break
	}
	return
}

// ---- cards ----------------------------------------------------------------------------------

// What the hand says of a thing. Its strings are the card's own, freed when the thing is put down.
card_make :: proc(w: ^World, t: Thing) -> (c: Hand_Card) {
	title, sub, line, own: string
	c.x, c.z, c.level = t.block.x, t.block.z, t.block.y
	c.tint = LOOK.slab
	if t.island == nil {
		c.title, c.sub = strings.clone("The open sea"), strings.clone("off every island's ground")
		c.line = strings.clone("No island's ground reaches here. The sea floor lies 200 m down.")
		c.tint = LOOK.water
		return
	}
	bound(t.island)
	x, z := f64(t.block.x) - f64(region.origin.x) + 0.5, f64(t.block.z) - f64(region.origin.y) + 0.5
	p := point_at(x, z, 1)
	top := i32(math.round(p.h))
	cell := land_cell(x, z)
	c.mat = t.mat
	switch t.kind {
	case .None, .Dwarf, .Dwarves:
	case .Pile:   // things lying in a cell: what, how many, and whether the hold counts them
		title = store_words(t.mat)
		in_store := false
		for p in watch.seen.piles do if p.at == t.block do in_store = p.stored
		sub = fmt.tprintf("%d, in a stockpile", t.feature) if in_store else fmt.tprintf("%d, lying loose: not counted", t.feature)
		what := "Timber, felled and lying where the tree stood" if is_stuff(t.mat, .Timber) else "Stone, lying where it was dug"
		line = fmt.tprintf("%s. It is counted at the top right, and a wall or floor marked near it is built of it", what) if in_store else fmt.tprintf("%s. A dwarf with nothing more pressing carries it to a stockpile that takes it; Store (S) marks one", what)
		c.title, c.sub, c.line = strings.clone(sentence(title)[:len(sentence(title)) - 1]), strings.clone(sub), strings.clone(sentence(line))
		return
	case .Zone:   // a stockpile's ground
		z, _ := zone_under(t.block + {0, 1, 0})
		title = "stockpile"
		sub = fmt.tprintf("%s; %d of %d full", TAKES_SAYS[z.takes], z.full, z.cells)
		line = "What lies in it is what the hold has, counted at the top right. Dwarves carry what lies loose to the nearest place that takes it. Store (S) beside it makes it larger; Remove (X) takes ground out of it, and what lies there then lies loose"
		c.mat, c.tint = .Air, LOOK.verdigris
		c.title, c.sub, c.line = strings.clone(sentence(title)[:len(sentence(title)) - 1]), strings.clone(sub), strings.clone(sentence(line))
		return
	case .Ground:
		title = mat_words(t.mat)
		under := top - 1 - t.block.y
		sub = fmt.tprintf("%d m under the ground, %d m over the sea", under, t.block.y) if under > 0 else fmt.tprintf("at the ground's top, %d m over the sea", t.block.y) if under == 0 else fmt.tprintf("%d m over the ground, %d m over the sea", -under, t.block.y)
		y := f32(t.block.y) + 0.5
		u := p.under
		solid := rock_in(y, u, 0)
		row, depth := soil_at(&p)
		switch {
		case t.mat == .Air:
			title, line = "open air", "Nothing stands here."
		case MATERIALS[t.mat].strength > 0 || t.mat == crushed(solid, u) && solid != t.mat:   // a rock of the stack, or a body
			line = ROCK_SAYS[solid]
			switch {
			case y < u.roof && u.roof >= ROOF_ALL: line = fmt.tprintf("%s. Here it stands as a dike or a plug that cuts across the beds", line)
			case y < u.roof: line = fmt.tprintf("%s. This is the body itself, which rose under the beds and baked them", line)
			case y < u.roof + AUREOLE && FORMS[rock_in(y, {base = u.base, cover = u.cover, roof = NO_ROOF}, 0)].baked != .Air: line = fmt.tprintf("%s. The body %.0f m under it baked it from the bed that lay here", line, y - u.roof)
			case bed_at(y, u) >= 0: line = fmt.tprintf("%s. This bed is %.0f m thick", line, rocks.beds[bed_at(y, u)].thick)
			}
			if u.crush do line = fmt.tprintf("%s. A fault has crushed it here", line)
		case is(t.mat, bit_set[Trait]{.Rubble}):
			line = "Rock fallen from the face above, lying at its angle of rest" if strings.has_prefix(mat_words(t.mat), "scree") else "The rock broken in place under the soil, where roots and water have opened its cracks"
		case is(t.mat, PEBBLES):
			line = "A river rounded these stones and laid them on its bed and its bars"
		case under == 0:   // the ground's top: what covers it, and why
			r := SURFACES[surface_row(&p)]
			line = r.why
			if k, _ := community_at(x, z, 1); len(r.host) == 0 do title, line = COMMUNITIES[k].name, COMMUNITIES[k].why
		case:
			line = fmt.tprintf("The soil here is %s, %.1f m deep: %s", SOILS[row].name, depth, SOILS[row].why)
		}
		if plan, laid := bar.built[t.block]; laid {   // a block the dwarves laid remembers it: a wall, not a rock
			of := "timber" if t.mat == .Timber else mat_words(t.mat)
			title = fmt.tprintf("%s of %s", PLANS[plan], of)
			sub = "built by the hold"
			line = fmt.tprintf("The dwarves laid it, of %s brought to it. Remove (X) takes it down, and the %s lies where it stood", "timber" if t.mat == .Timber else "stone", of)
		}
		c.column = true
	case .Tree:
		o := t.tree
		FORM := [Tree_Form]string{.Canopy = "in the canopy", .Between = "between the canopy trees", .Under = "under a taller tree", .Dead = "standing dead", .Fallen = "fallen"}
		WHY := [Tree_Form]string{.Canopy = "No stronger tree stands within reach of its crown, so it took the light", .Between = "A stronger tree stands beside it, so it stays the smaller", .Under = "It grows in the shade of the trees over it", .Dead = "It died standing, and what is left is its broken trunk", .Fallen = "A storm threw it. Its root mound and the pit it left lie at its foot"}
		title = fmt.tprintf("%s%s", SPECIES[o.kind].name, "" if o.kind == .Scrub else " tree")
		sub = fmt.tprintf("%d m %s, %s", o.height, "long" if o.form == .Fallen else "tall", FORM[o.form])
		age := land.age[land_cell(f64(o.x), f64(o.z))]
		why := fmt.tprintf("the slide laid its ground bare") if abs(land.slid[cell]) > 0.5 && age == region.features[landslide.feature].age else fmt.tprintf("a typhoon threw the canopy then")
		line = fmt.tprintf("%s. Its stand is about %s years old: %s", WHY[o.form], years(max(age, 1)), why)
		k, _ := community_at(x, z, 1)
		own = fmt.tprintf("It stands in %s: %s.", COMMUNITIES[k].name, COMMUNITIES[k].why)
		c.mat = SPECIES[o.kind].leaf if o.form < .Dead else SPECIES[o.kind].bark
		c.x, c.z, c.level = o.x + region.origin.x, o.z + region.origin.y, o.base - 1
	case .Stream:
		area := land.grid.area[cell]
		r, _ := river_near(f32(x), f32(z))
		title = "stream" if r.half < 4 else "river"
		sub = fmt.tprintf("%.0f m wide, draining %.2f km²", max(2*r.half, 1), area/1e6)
		line = fmt.tprintf("The rain that runs off the land above gathers here: %.3f m³ a second on a mean day%s", discharge(area), ". Here it falls over a lip of rock" if r.fall else ". Here it runs in the gorge a fall cut as it wore back" if r.gorge else "")
		c.mat, c.tint = .Air, LOOK.water
		hear_begin()
		creature_words(x, z)
		own = sentence(hear_end())
	case .Lake:
		f := region.features[t.feature]
		pond := f.kind == .Pond
		title = "pond" if pond else "lake"
		sub = fmt.tprintf("%.1f ha, its water at %.0f m over the sea", f.size/1e4, f.level)
		ago := years(region.features[landslide.feature].age)
		line = fmt.tprintf("A slide left this hollow among its debris about %s years ago. No stream leaves it; it seeps away", ago) if pond else fmt.tprintf("A slide dammed the stream here about %s years ago. The water leaves over the lowest point of the debris, which it has cut", ago)
		c.mat, c.tint = .Air, LOOK.water
		hear_begin()
		creature_words(x, z)
		own = sentence(hear_end())
	case .Sea:
		title, sub = "the sea", fmt.tprintf("%.0f m deep here", max(-p.h, 0))
		line = fmt.tprintf("The swell comes from %.0f°. This shore is %s to it", region.shape.swell, "open" if land.surf[cell] > 0.25 else "half open" if land.surf[cell] > 0.1 else "sheltered")
		c.mat, c.tint = .Air, LOOK.water
	case .Place:
		k := candidates[t.place]
		named := -1
		for q, i in places do if q.c == t.place do named = i
		title = places[named].name if named >= 0 else PLACE_ROWS[k.kind].what
		sub = fmt.tprintf("a %s, place %d of %d named on the island", PLACE_ROWS[k.kind].what, named + 1, len(places)) if named >= 0 else "not named: a greater thing stands near it, or it is not seen from far enough"
		line = k.why
		with := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&with, "It is seen from %.0f%% of the ground 1 to 2 km round.", 100*k.seen)
		if named >= 0 {
			fmt.sbprintf(&with, " It was named for being the most remarkable thing within %d m.", APART)
			for o in candidates do if o.place == named && o.why != k.why do fmt.sbprintf(&with, "\n%s", sentence(fmt.tprintf("With it: %s", o.why)))
		}
		own = strings.to_string(with)
		c.mat = k.rock
	case .Animal:
		row := CREATURES[t.creature]
		title = fmt.tprintf("%s's nest", row.name) if t.nest else row.name
		line = row.why
		sub = "a heap of sticks with a rim" if t.nest else "a bird" if row.home != .Water else "a fish"
		for h in fauna.haunts do if h.row == t.creature && math.hypot(h.at.x - x, h.at.y - z) < f64(h.a) + 400 do sub = fmt.tprintf("%d live at this %s", h.n, "stack" if row.home == .Stack else "face")
		own = sentence(arrival_words(row.name))
		u := row.parts[0].upper
		c.mat, c.tint = .Air, {u8(u >> 16), u8(u >> 8), u8(u), 255}
	case .Box:
		size := t.hi - t.lo + 1
		blocks := int(size.x)*int(size.y)*int(size.z)
		title = fmt.tprintf("%d blocks", blocks)
		sub = fmt.tprintf("%d by %d, %d deep", size.x, size.z, size.y)
		counts: [Mat]int
		step := max(1, i32(math.ceil(math.pow(f64(blocks)/4096, 1.0/3))))   // a large box is read every few blocks
		for bx := t.lo.x; bx <= t.hi.x; bx += step do for by := t.lo.y; by <= t.hi.y; by += step do for bz := t.lo.z; bz <= t.hi.z; bz += step do counts[block_made(w, {bx, by, bz})] += int(step*step*step)
		bound(t.island)   // block_made binds as it goes
		most := [3]Mat{}
		for n, m in counts do if m != .Air {
			if n > counts[most[0]] || most[0] == .Air do most = {m, most[0], most[1]}
			else if n > counts[most[1]] || most[1] == .Air do most = {most[0], m, most[1]}
			else if n > counts[most[2]] || most[2] == .Air do most[2] = m
		}
		words := strings.builder_make(context.temp_allocator)
		for m, i in most do if m != .Air && counts[m] > 0 do fmt.sbprintf(&words, "%s%s%d of %s", "" if i == 0 else ", ", "about " if step > 1 && i == 0 else "", min(counts[m], blocks), mat_words(m))
		line = fmt.tprintf("It holds %s%s", strings.to_string(words), fmt.tprintf(", and %d of open air", min(counts[.Air], blocks)) if counts[.Air] > 0 else "") if strings.builder_len(words) > 0 else "It holds only open air"
		c.mat = most[0]
		c.column = true
	}
	c.title, c.sub, c.line = strings.clone(sentence(title)[:len(sentence(title)) - 1]), strings.clone(sub), strings.clone(sentence(line))
	c.says = why_parts(t.island, f64(c.x) + 0.5, f64(c.z) + 0.5)
	c.says[.Own] = strings.clone(own)
	rock := c.says[.Rock]
	c.says[.Rock] = strings.clone(rock_says(rock))
	delete(rock)
	return
}
