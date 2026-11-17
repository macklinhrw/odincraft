package main

import "core:fmt"
import "core:math"
import "core:math/linalg"

// The racks as the frame shows them (docs/foundations/interface.md, section 20): each drawn where it
// stands with what is on it, taken in the hand by a click, and its card. All of it is the frame
// thread's, and reads the hold only through what it shows (Shown.benches).

// The racks, as boxes after the frame's: four posts, two rails and a bed of poles, and on the bed
// what is drying, in its own colour, turning to the colour of what it becomes as it comes on.
benches_view :: proc(boxes: []Box, eye, middle: [3]f64) -> []Box {
	s := &watch.seen
	if len(s.benches) == 0 do return boxes
	out := make([dynamic]Box, 0, len(boxes) + 12*len(s.benches), context.temp_allocator)
	append(&out, ..boxes)
	wood, pale := f32(mat_rgb(.Wood)), f32(mat_rgb(.Timber))
	for b in s.benches {
		if len(out) >= BOX_MAX - 16 do break
		if abs(f64(b.at.x) - middle.x) > PILES_FAR || abs(f64(b.at.z) - middle.z) > PILES_FAR do continue
		base := [3]f32{f32(f64(b.at.x) + 0.5 - eye.x), f32(f64(b.at.y) - eye.y), f32(f64(b.at.z) + 0.5 - eye.z)}
		feet := base.y - 1e-3
		for k in 0..<4 {   // the posts
			at := base + {(f32(k%2) - 0.5)*0.76, 0.42, (f32(k/2) - 0.5)*0.76}
			append(&out, Box{at, wood, {0.045, 0, 0}, wood, {0, 0.42, 0}, 0, {0, 0, 0.045}, feet})
		}
		for k in 0..<2 {   // the rails
			at := base + {0, 0.86, (f32(k) - 0.5)*0.76}
			append(&out, Box{at, pale, {0.46, 0, 0}, wood, {0, 0.04, 0}, 0, {0, 0, 0.04}, feet})
		}
		append(&out, Box{base + {0, 0.9, 0}, wood, {0.42, 0, 0}, wood, {0, 0.015, 0}, 0, {0, 0, 0.42}, feet})   // the bed, dark, so that what lies on it shows
		if b.make < 0 || b.n <= 0 do continue
		row := MAKES[b.make]
		share := 1.0 if b.done else clamp(b.share, 0, 1)
		colour := math.lerp(MATERIALS[row.of].colour, MATERIALS[row.gives].colour, f32(share))
		rgb :: proc(c: [3]f32, by: f32) -> f32 {
			c := c*by
			return f32(u32(clamp(math.pow(c.r, 1/2.2), 0, 1)*255) << 16 | u32(clamp(math.pow(c.g, 1/2.2), 0, 1)*255) << 8 | u32(clamp(math.pow(c.b, 1/2.2), 0, 1)*255))
		}
		rows := clamp(int(b.n + 5)/6, 1, 4)   // a row of it for each six things
		for k in 0..<rows {
			at := base + {0, 0.945, (f32(k) - f32(rows - 1)/2)*0.19}
			append(&out, Box{at, rgb(colour, 1.6), {0.36, 0, 0}, rgb(colour, 1.0), {0, 0.03, 0}, 0, {0, 0, 0.065}, feet})
		}
	}
	return out[:]
}

// The rack a ray from the eye meets, of those the hold last showed, where it stands before the
// block picked behind it; or -1.
bench_aimed :: proc(eye: [3]f64, ray: [3]f32, behind: Pick) -> (which: int) {
	which = -1
	near := f64(1e9)
	if behind.ok do near = linalg.length([3]f64{f64(behind.block.x) + 0.5, f64(behind.block.y) + 0.5, f64(behind.block.z) + 0.5} - eye) + 0.9
	for b, k in watch.seen.benches {
		lo := [3]f64{f64(b.at.x) + 0.05, f64(b.at.y), f64(b.at.z) + 0.05}
		hi := lo + {0.9, 1.0, 0.9}
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
		if behind.ok && (behind.block == b.at || behind.block == b.at - {0, 1, 0}) do which = k   // or the block it stands on was clicked
	}
	return
}

// The rack in the hand: what is on it and how long until it is done, as a length; how it stands,
// which is what speeds or stops it; what it lacks, if anything; and the three things done to one:
// go to it, leave it empty or keep it loaded, and remove it. It follows the fire's card and the
// stockpile's (fire_card, zone_card). RimWorld's fermenting barrel says what it holds, how far it
// has come and when it will be done, and that it is out of its ideal temperature
// (Building_FermentingBarrel.GetInspectString; colony-sim-reference.md, section 16).
bench_card :: proc() {
	u, L := &play, &LOOK
	b := watch.seen.benches[bar.bench]
	row := &BENCHES[b.kind]
	u.area = .Hand
	w := px(L.hand_wide)
	inner := w - 2*px(L.pad.x)
	x := px(L.margin)
	empty := b.make < 0 || b.n == 0
	pace := bench_pace(row, b.by_fire, b.rained)
	state := bench_words(b)
	holds := fmt.tprintf("%d of %d places", b.n, row.holds) if b.done || empty else fmt.tprintf("%d of %d places; %s dry in %s", b.n, row.holds, store_words(MAKES[b.make].of), days_words(MAKES[b.make].days))
	stands := "By a fire: what is on it dries twice as fast, rain or none." if b.by_fire && !b.rained else
		"By a fire, in the rain: it dries on, at the pace of a dry day." if b.by_fire else
		"Under a roof: it dries in the air, out of the rain." if b.roof else
		"In the open: it dries in sun and wind, and not in rain."
	// What it lacks: food to dry, dry weather, a place for what is done.
	fresh, stores := false, false
	for p in watch.seen.piles do fresh ||= make_of(p.kind, b.kind) >= 0
	for z in watch.seen.zones do stores ||= !z.sleep && (z.takes == .All || z.takes == .Food)
	lacks := "Rain is falling on it: nothing dries. A fire beside it would keep it drying." if b.rained && !b.by_fire && !empty && !b.done else
		"No stockpile takes food: what is dried is laid at its foot." if b.done && !stores else
		"Nothing fresh lies anywhere to dry: gather shoots or catch fish." if empty && b.used && !fresh else ""
	line := line_of(.Body)
	high := 2*px(L.pad.y) + line_of(.Title) + text_high(.Body, state, inner) + px(1.5) + px(1.25) + px(2) + line_of(.Small) + px(2) + text_high(.Body, stands, inner) + (text_high(.Body, lacks, inner) if lacks != "" else 0) + px(3) + px(L.button)
	_ = line
	rect := Rect{x, screen.h - px(L.hand_foot) - high, w, high}
	part(.Panel, rect, id = "hand")
	cx, y := x + px(L.pad.x), rect.y + px(L.pad.y)
	down := button_wide("Put down", key_for(.Escape), .Small, L.chip_pad.x)
	part(.Chip, {cx + inner - down, y, down, line_of(.Small) + 2*px(L.chip_pad.y)}, "Put down", .Small, {}, {}, .Drop, 0, key_for(.Escape), "rack.drop", "Put the rack down: it dries on.")
	y += words(cx, y, capital(row.name), .Title, id = "rack.title")
	stalled := !empty && !b.done && pace <= 0
	y += words(cx, y, state, .Body, L.ash if empty else L.brass if stalled else L.chalk, "rack.state", inner) + px(1.5)
	part(.Fill, {cx, y, inner, px(1.25)}, colour = L.pit)   // how far what is on it has come, as a length
	part(.Fill, {cx, y, math.round(inner*clamp(1 if b.done else b.share if !empty else 0, 0, 1)), px(1.25)}, colour = L.brass if stalled else L.verdigris)
	y += px(1.25) + px(2)
	y += words(cx, y, holds, .Small, L.ash, "rack.holds") + px(2)
	y += words(cx, y, stands, .Body, L.ash, "rack.stands", inner)
	if lacks != "" do y += words(cx, y, lacks, .Body, L.brass, "rack.lacks", inner)
	y += px(3)
	gw := button_wide("Go there", key_for(.Go))
	button({cx, y, gw, px(L.button)}, "Go there", .Go, 0, false, "rack.go", "Put the view over it.")
	use := "Leave it empty" if b.used else "Keep it loaded"
	uw := button_wide(use, "")
	button({cx + gw + px(L.gap), y, uw, px(L.button)}, use, .Use, 0 if b.used else 1, false, "rack.use",
		"Nothing more is brought to it: what is on it is finished and taken off, and it stands empty." if b.used else "Fresh food that dries is brought to it again, what will spoil soonest first.")
	button({cx + gw + uw + 2*px(L.gap), y, button_wide("Remove", ""), px(L.button)}, "Remove", .Rack_Remove, 0, false, "rack.remove", "Take it down. What is on it, and the timber it is of, lie there.")
}
