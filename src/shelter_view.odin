package main

import "core:fmt"
import "core:math"
import "core:math/linalg"

// Shelter and fire as the frame shows them (docs/foundations/interface.md, section 19): the shelter
// lens, the fires drawn and lit, and the cards of a sleeping place and of a fire. All of it is the
// frame thread's, and reads the hold only through what it shows (Shown). What is sheltered is asked
// of the blocks the frame draws by the rule the hold asks its own ground by (shelter_of).

// The shelter lens: the ground under a roof within LENS_REACH of the view's middle, each block of
// it on the map of marked blocks (marks_bind, bar.odin) as under a roof or as indoors. It is read
// again when the view has moved a few blocks, when a block has changed, and no more than a few
// times a second.
LENS_REACH :: 44
shelter_scan :: proc() {
	u, a := &play, play.a
	if u.lens < 0 || !LENSES[u.lens].blocks || u.afoot^ || u.w == nil {
		clear(&bar.lens_boxes)
		bar.lens_key = 0
		return
	}
	snap :: proc(x: f64, by: i32) -> i32 { return i32(math.floor(x/f64(by)))*by }
	mid := [3]i32{snap(a.at.x, 8) + 4, snap(a.at.y, 16) + 8, snap(a.at.z, 8) + 4}
	key := (u64(u32(mid.x))*0x9e3779b1 ~ u64(u32(mid.z)))*0x100000001b3 ~ u64(u32(mid.y)) ~ u64(u.w.volume) << 40 | 1
	if key == bar.lens_key || !u.still && u.now - bar.lens_at < 0.25 do return
	bar.lens_key, bar.lens_at = key, u.now
	clear(&bar.lens_boxes)
	src := world_blocks(u.w)
	for z in mid.z - LENS_REACH..=mid.z + LENS_REACH do for x in mid.x - LENS_REACH..=mid.x + LENS_REACH {
		c := u.w.chunks[Key{0, x >> CHUNK_SHIFT, z >> CHUNK_SHIFT}] or_else nil
		if c == nil || !c.ready || len(c.blocks) == 0 do continue
		k := int(x & (CHUNK - 1) + 1) + int(z & (CHUNK - 1) + 1)*P
		over := false   // something that shelters stands over the layer in hand
		for ly := c.h - 1; ly >= 0; ly -= 1 {
			if !shelters(c.blocks[k + int(ly)*P*P]) do continue
			y := ly + c.y_base
			open := ly + 1 >= c.h || c.blocks[k + int(ly + 1)*P*P] == .Air && (ly + 2 >= c.h || c.blocks[k + int(ly + 2)*P*P] == .Air)
			if over && open && abs(y - mid.y) < MAP_HIGH/2 - 2 {   // a floor with something over it: the rule says whether that is a roof, and whether walls stand round
				if s := shelter_of(src, {x, y + 1, z}); s.roof do append(&bar.lens_boxes, Map_Box{{x, y, z}, {x, y, z}, 10 if indoors(s) else 9})
			}
			over = true
		}
	}
}

// The fires, as boxes after the frame's: three logs laid across each other, and over a fire that
// burns its flames, which give their own light; one that is out is its logs, burnt black.
fires_view :: proc(boxes: []Box, eye: [3]f64) -> []Box {
	s := &watch.seen
	if len(s.fires) == 0 do return boxes
	out := make([dynamic]Box, 0, len(boxes) + 8*len(s.fires), context.temp_allocator)
	append(&out, ..boxes)
	rgb :: proc(c: Colour) -> f32 { return f32(u32(c.r) << 16 | u32(c.g) << 8 | u32(c.b)) }
	L := &LOOK
	for f, k in s.fires {
		if len(out) >= BOX_MAX - 16 do break
		base := [3]f32{f32(f64(f.at.x) + 0.5 - eye.x), f32(f64(f.at.y) - eye.y), f32(f64(f.at.z) + 0.5 - eye.z)}
		feet := base.y - 1e-3
		bark := f32(mat_rgb(.Wood)) if f.lit else rgb(L.char)
		for j in 0..<3 {   // the logs, across each other
			along := j != 1
			at := base + {0, 0.09 + 0.12*f32(j), (f32(j) - 1)*0.16 if along else 0}
			half := [3]f32{0.34, 0.08, 0.08} if along else {0.08, 0.08, 0.34}
			append(&out, Box{at, bark, {half.x, 0, 0}, bark if f.lit else rgb(L.char), {0, half.y, 0}, 0, {0, 0, half.z}, feet})
		}
		if !f.lit do continue
		low := f.fuel < FIRE_DYING   // a fire about to go out burns small
		t := watch.clock if watch.live else 0
		for j in 0..<3 {   // the flames: three tongues that rise and fall, and shine by themselves (a box wet under nothing is lit by itself, shaders.metal)
			tall := (0.34 if low else 0.6)*(0.75 + 0.25*f32(math.sin(t*(9 + 2*f64(j)) + f64(j)*2.1 + f64(k))))*(1 - 0.25*f32(j))
			wide := 0.17 - 0.035*f32(j)
			at := base + {(f32(j) - 1)*0.09, 0.3 + tall, (f32(j%2) - 0.5)*0.1}
			c := rgb(L.flame) if j == 0 else rgb(L.ember)
			append(&out, Box{at, c, {wide, 0, 0}, c, {0, tall, 0}, -2.4 if j == 0 else -1.7, {0, 0, wide}, feet})
		}
	}
	return out[:]
}

// The fires that light the frame's picture, the nearest the view's middle first: each its place
// from the eye and how far its light reaches. Called by render.
fires_light :: proc(eye, middle: [3]f64, out: ^[8][4]f32) {
	s := &watch.seen
	n := 0
	for f in s.fires do if f.lit && n < len(out) && abs(f64(f.at.x) - middle.x) < 200 && abs(f64(f.at.z) - middle.z) < 200 {
		out[n] = {f32(f64(f.at.x) + 0.5 - eye.x), f32(f64(f.at.y) + 0.7 - eye.y), f32(f64(f.at.z) + 0.5 - eye.z), FIRE_LIGHT*(0.6 if f.fuel < FIRE_DYING else 1)}
		n += 1
	}
}

// The fire a ray from the eye meets, of those the hold last showed, where it stands before the
// block picked behind it; or -1.
fire_aimed :: proc(eye: [3]f64, ray: [3]f32, behind: Pick) -> (which: int) {
	which = -1
	near := f64(1e9)
	if behind.ok do near = linalg.length([3]f64{f64(behind.block.x) + 0.5, f64(behind.block.y) + 0.5, f64(behind.block.z) + 0.5} - eye) + 0.9
	for f, k in watch.seen.fires {
		lo := [3]f64{f64(f.at.x) + 0.05, f64(f.at.y), f64(f.at.z) + 0.05}
		hi := lo + {0.9, 1.1 if f.lit else 0.4, 0.9}
		t0, t1 := 0.0, near
		for a in 0..<3 {
			v := f64(ray[a])
			if abs(v) < 1e-9 {
				if eye[a] < lo[a] || eye[a] > hi[a] do t1 = -1
				continue
			}
			a0, a1 := (lo[a] - eye[a])/v, (hi[a] - eye[a])/v
			t0, t1 = max(t0, min(a0, a1)), min(t1, max(a0, a1))
		}
		if t0 <= t1 do which, near = k, t0
		if behind.ok && (behind.block == f.at || behind.block == f.at - {0, 1, 0}) do which = k   // or the block it stands on was clicked
	}
	return
}

// The fire in the hand: whether it burns and how long its timber lasts, where it stands and what
// that makes of its warmth, who is by it, and the three things done to one: go to it, let it go
// out or keep it fed, and remove it. RimWorld's campfire says its fuel and gives a toggle to stop
// its being fed (colony-sim-reference.md, section 15).
fire_card :: proc() {
	u, L := &play, &LOOK
	f := watch.seen.fires[bar.fire]
	u.area = .Hand
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	reach := FIRE_REACH
	state := fmt.tprintf("Burning: timber for %s.", fuel_words(f.fuel, f.rained)) if f.lit else "Out: it was let go out." if !f.fed else "Out: no timber was brought to it in time."
	low := f.lit && f.fuel < FIRE_DYING
	stands := fmt.tprintf("Indoors: it warms %d steps round it.", reach[1]) if f.roof && f.walled else
		fmt.tprintf("Under a roof with no walls: it warms %d steps round it.", reach[0]) if f.roof else
		fmt.tprintf("In the open: it warms %d steps round it, and burns three times as fast in rain.", reach[0])
	by := 0
	r := reach[1] if f.roof && f.walled else reach[0]
	for d in watch.seen.dwarves do if d.doing != .Dead && d.doing != .Aboard {
		c := [3]i32{i32(math.floor(d.at.x)), i32(math.floor(d.at.y)), i32(math.floor(d.at.z))}
		by += int(f.lit && abs(c.x - f.at.x) <= r && abs(c.z - f.at.z) <= r && abs(c.y - f.at.y) <= 2)
	}
	who := "Nobody is by it." if by == 0 else "One dwarf is by it." if by == 1 else fmt.tprintf("%s dwarves are by it.", capital(number_words(by)))
	rain := "Rain is falling on it." if f.rained && f.lit else ""
	line := line_of(.Body)
	high := 2*px(L.pad.y) + line_of(.Title) + text_high(.Body, state, inner) + px(1.5) + px(1.25) + px(2) + line_of(.Small) + px(2) + text_high(.Body, stands, inner) + (line if rain != "" else 0) + line + px(3) + px(L.button)
	rect := Rect{x, screen.h - px(L.hand_foot) - high, w, high}
	part(.Panel, rect, id = "hand")
	cx, y := x + px(L.pad.x), rect.y + px(L.pad.y)
	down := button_wide("Put down", key_for(.Escape), .Small, L.chip_pad.x)
	part(.Chip, {cx + inner - down, y, down, line_of(.Small) + 2*px(L.chip_pad.y)}, "Put down", .Small, {}, {}, .Drop, 0, key_for(.Escape), "fire.drop", "Put the fire down: it burns on.")
	y += words(cx, y, "Fire", .Title, id = "fire.title")
	y += words(cx, y, state, .Body, L.cinnabar if !f.lit && f.fed else L.brass if low else L.chalk if f.lit else L.ash, "fire.state", inner) + px(1.5)
	part(.Fill, {cx, y, inner, px(1.25)}, colour = L.pit)   // its timber, as a length
	part(.Fill, {cx, y, math.round(inner*clamp(f.fuel/FIRE_HOLDS, 0, 1)), px(1.25)}, colour = L.cinnabar if !f.lit else L.brass if low else L.verdigris)
	y += px(1.25) + px(2)
	y += words(cx, y, fmt.tprintf("%.0f of %.0f logs; it burns %.0f a day", math.ceil(f.fuel - 0.01), f32(FIRE_HOLDS), f32(FIRE_BURNS)), .Small, L.ash, "fire.logs") + px(2)
	y += words(cx, y, stands, .Body, L.ash, "fire.stands", inner)
	if rain != "" do y += words(cx, y, rain, .Body, L.brass, "fire.rain")
	y += words(cx, y, who, .Body, L.ash, "fire.who") + px(3)
	gw := button_wide("Go there", key_for(.Go))
	button({cx, y, gw, px(L.button)}, "Go there", .Go, 0, false, "fire.go", "Put the view over it.")
	feed := "Let it go out" if f.fed else "Keep it fed"
	fw := button_wide(feed, "")
	button({cx + gw + px(L.gap), y, fw, px(L.button)}, feed, .Tend, 0 if f.fed else 1, false, "fire.tend",
		"No more timber is brought to it: it burns what it has and goes out." if f.fed else "Timber is brought to it again from what the hold has, and it is lit again.")
	button({cx + gw + fw + 2*px(L.gap), y, button_wide("Remove", ""), px(L.button)}, "Remove", .Fire_Remove, 0, false, "fire.remove", "Put it out and take it up. What timber is left lies there.")
}

// The sleeping place in the hand, as a whole: how many places it has and how they are sheltered,
// who lies in it, and the three things done to one: go to it, make it larger, remove it. It stands
// where a stockpile's card does, since it is marked, taken and removed as one is.
sleep_card :: proc() {
	u, L := &play, &LOOK
	z, _ := zone_seen(bar.zone)
	u.area = .Hand
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	open := z.cells - z.roofed
	size := fmt.tprintf("%d %s", z.cells, "place" if z.cells == 1 else "places")
	Row :: struct { name: string, n: int, colour: Colour }
	rows := [3]Row{{"Indoors: dry and out of the wind", z.walled, L.indoors}, {"Under a roof: dry", z.roofed - z.walled, L.roofed}, {"Open to the sky", open, L.ash}}
	asleep := 0
	for d in watch.seen.dwarves do if d.doing == .Sleeping {
		c := [3]i32{i32(math.floor(d.at.x)), i32(math.floor(d.at.y + 0.5)), i32(math.floor(d.at.z))}
		if in_zone, on := zone_under(c); on && in_zone.id == z.id do asleep += 1
	}
	lying := "Nobody lies here now." if asleep == 0 else "One dwarf is asleep here." if asleep == 1 else fmt.tprintf("%s dwarves are asleep here.", capital(number_words(asleep)))
	short := ""
	if living := hold_living(); z.cells < living do short = fmt.tprintf("Fewer places than dwarves: %s will lie down elsewhere.", number_words(living - z.cells))
	else if open == z.cells do short = "No place here has a roof: they will lie in the weather."
	line := line_of(.Body)
	shown := 0
	for r in rows do shown += int(r.n > 0)
	high := 2*px(L.pad.y) + line_of(.Title) + line + px(2) + f32(shown)*line + px(2) + line + (text_high(.Small, short, inner) if short != "" else 0) + px(3) + px(L.button)
	rect := Rect{x, screen.h - px(L.hand_foot) - high, w, high}
	part(.Panel, rect, id = "hand")
	cx, y := x + px(L.pad.x), rect.y + px(L.pad.y)
	down := button_wide("Put down", key_for(.Escape), .Small, L.chip_pad.x)
	part(.Chip, {cx + inner - down, y, down, line_of(.Small) + 2*px(L.chip_pad.y)}, "Put down", .Small, {}, {}, .Drop, 0, key_for(.Escape), "zone.drop", "Put the sleeping place down.")
	y += words(cx, y, "Sleeping place", .Title, id = "zone.title")
	y += words(cx, y, size, .Body, L.ash, "zone.size", inner) + px(2)
	for r in rows do if r.n > 0 {
		part(.Fill, {cx, y + math.round((line - px(L.block))/2), px(L.block), px(L.block)}, colour = r.colour)
		words(cx + px(L.block) + px(2.5), y, r.name, .Body, {}, "zone.kind")
		count := fmt.tprint(r.n)
		words(cx + inner - text_wide(.Figure, count), y, count, .Figure, {}, "zone.count")
		y += line
	}
	y += px(2)
	y += words(cx, y, lying, .Body, L.ash, "zone.asleep")
	if short != "" do y += words(cx, y, short, .Small, L.brass, "zone.short", inner)
	y += px(3)
	gw := button_wide("Go there", key_for(.Go))
	button({cx, y, gw, px(L.button)}, "Go there", .Go, 0, false, "zone.go", "Put the view over it.")
	lw := button_wide("Make larger", "")
	button({cx + gw + px(L.gap), y, lw, px(L.button)}, "Make larger", .Zone_Grow, 0, false, "zone.grow", "Take up Sleep: drag beside it and the ground joins it.")
	button({cx + gw + lw + 2*px(L.gap), y, button_wide("Remove", ""), px(L.button)}, "Remove", .Zone_Remove, 0, false, "zone.remove", "Remove this sleeping place, all of it. The dwarves lie down where they find a roof, or where they are.")
}

// What the shelter lens's colours mean, under its name: two rows.
shelter_legend :: proc(x, y, wide: f32, says: string) -> f32 {
	L := &LOOK
	from, y := y, y
	y += words(x, y, says, .Small, L.ash, "lens.says", wide) + px(2)
	for r in ([2]struct { c: Colour, name: string }{{L.roofed, "under a roof: dry"}, {L.indoors, "indoors: dry, out of the wind"}}) {
		part(.Fill, {x, y + px(0.75), px(L.block), px(L.block)}, colour = r.c)
		words(x + px(L.block) + px(2), y, r.name, .Small, {}, "lens.kind")
		y += line_of(.Small)
	}
	return y - from
}

// What the hand says of ground a dwarf could stand on: its shelter, by the rule the hold feels by.
shelter_says :: proc(w: ^World, block: [3]i32) -> string {
	src := world_blocks(w)
	c := block + {0, 1, 0}
	if !stands_at(src, c) do return ""
	return fmt.tprintf("A dwarf standing on it is %s", shelter_words(shelter_of(src, c)))
}
