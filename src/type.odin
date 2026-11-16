package main

import "core:math"

// A typeface read from its file, and its glyphs drawn at a pixel size (docs/adr/0010). The little
// of TrueType the interface needs, written here so that the game builds with nothing but Odin and
// SDL: which glyph a character has (the `cmap` table, format 4), how far the pen moves after it
// (`hmtx`), its outline (`glyf`: lines and quadratic curves, and glyphs made of others, as the
// accented letters are), and how much closer or farther two glyphs stand as a pair (`GPOS`, pair
// adjustment). A glyph is drawn by adding up, for every pixel, the share of it the outline covers,
// which is exact for straight edges. The face's own instructions for fitting it to the pixels are
// not run: text is sharp because each glyph is drawn at the size it is shown at and set on whole
// pixels (ui.odin).

Font :: struct {
	data:    []u8,
	units:   f32,           // of the face to its em
	ascent, descent: f32,   // over the baseline and under it, in its units
	glyf, loca, hmtx, cmap: int,
	wide_loca: bool,
	metrics, count: int,    // glyphs with an advance of their own, and glyphs in all
	pairs:   [dynamic]int,  // where each table of pair adjustments begins
}

be16 :: #force_inline proc(d: []u8, at: int) -> int { return int(d[at]) << 8 | int(d[at + 1]) }
bi16 :: #force_inline proc(d: []u8, at: int) -> int { return int(i16(u16(d[at]) << 8 | u16(d[at + 1]))) }
be32 :: #force_inline proc(d: []u8, at: int) -> int { return int(d[at]) << 24 | int(d[at + 1]) << 16 | int(d[at + 2]) << 8 | int(d[at + 3]) }

font_open :: proc(data: []u8) -> (f: Font) {
	f.data = data
	d := data
	gpos := 0
	for i in 0..<be16(d, 4) {
		at := 12 + 16*i
		off := be32(d, at + 8)
		switch string(d[at:at + 4]) {
		case "head": f.units, f.wide_loca = f32(be16(d, off + 18)), be16(d, off + 50) != 0
		case "hhea": f.ascent, f.descent, f.metrics = f32(bi16(d, off + 4)), f32(-bi16(d, off + 6)), be16(d, off + 34)
		case "maxp": f.count = be16(d, off + 4)
		case "glyf": f.glyf = off
		case "loca": f.loca = off
		case "hmtx": f.hmtx = off
		case "GPOS": gpos = off
		case "cmap":
			for k in 0..<be16(d, off + 2) {   // the Unicode table of 16 bits
				sub := off + be32(d, off + 8 + 8*k)
				if p, e := be16(d, off + 4 + 8*k), be16(d, off + 6 + 8*k); (p == 3 && e == 1 || p == 0) && be16(d, sub) == 4 do f.cmap = sub
			}
		}
	}
	// The pair adjustments of the feature `kern`: its lookups' tables, through an extension where one stands in the way.
	if gpos != 0 {
		features, lookups := gpos + be16(d, gpos + 6), gpos + be16(d, gpos + 8)
		for i in 0..<be16(d, features) do if string(d[features + 2 + 6*i:][:4]) == "kern" {
			feature := features + be16(d, features + 6 + 6*i)
			for k in 0..<be16(d, feature + 2) {
				lookup := lookups + be16(d, lookups + 2 + 2*be16(d, feature + 4 + 2*k))
				kind := be16(d, lookup)
				for s in 0..<be16(d, lookup + 4) {
					table := lookup + be16(d, lookup + 6 + 2*s)
					if kind == 9 && be16(d, table + 2) == 2 do table += be32(d, table + 4)
					else if kind != 2 do continue
					append(&f.pairs, table)
				}
			}
		}
	}
	return
}

// The glyph of a character, or 0, the face's mark for one it has not.
font_glyph :: proc(f: ^Font, r: rune) -> int {
	d, c := f.data, int(r)
	if f.cmap == 0 || c > 0xFFFF do return 0
	n := be16(d, f.cmap + 6)/2
	ends := f.cmap + 14
	starts, deltas, ranges := ends + 2*n + 2, ends + 4*n + 2, ends + 6*n + 2
	for i in 0..<n do if c <= be16(d, ends + 2*i) {
		start := be16(d, starts + 2*i)
		if c < start do return 0
		if off := be16(d, ranges + 2*i); off != 0 {
			g := be16(d, ranges + 2*i + off + 2*(c - start))
			return (g + be16(d, deltas + 2*i)) & 0xFFFF if g != 0 else 0
		}
		return (c + be16(d, deltas + 2*i)) & 0xFFFF
	}
	return 0
}

// How far the pen moves after a glyph, in the face's units.
font_advance :: proc(f: ^Font, g: int) -> f32 { return f32(be16(f.data, f.hmtx + 4*min(g, f.metrics - 1))) }

// How much closer (under 0) or farther two glyphs stand as a pair than apart, in the face's units.
font_kern :: proc(f: ^Font, a, b: int) -> f32 {
	d := f.data
	covered :: proc(d: []u8, at, g: int) -> int {   // a glyph's place in a coverage table, or -1
		n := be16(d, at + 2)
		if be16(d, at) == 1 {
			for i in 0..<n do if be16(d, at + 4 + 2*i) == g do return i
		} else do for i in 0..<n {
			if r := at + 4 + 6*i; g >= be16(d, r) && g <= be16(d, r + 2) do return be16(d, r + 4) + g - be16(d, r)
		}
		return -1
	}
	class :: proc(d: []u8, at, g: int) -> int {
		if be16(d, at) == 1 {
			first := be16(d, at + 2)
			return be16(d, at + 6 + 2*(g - first)) if g >= first && g < first + be16(d, at + 4) else 0
		}
		for i in 0..<be16(d, at + 2) do if r := at + 4 + 6*i; g >= be16(d, r) && g <= be16(d, r + 2) do return be16(d, r + 4)
		return 0
	}
	bits :: proc(v: int) -> (n: int) {
		for v := v; v != 0; v >>= 1 do n += v & 1
		return
	}
	for t in f.pairs {
		at := covered(d, t + be16(d, t + 2), a)
		if at < 0 do continue
		v1, v2 := be16(d, t + 4), be16(d, t + 6)
		if v1 & 4 == 0 do continue   // it moves no pen
		before := 2*bits(v1 & 3)     // what stands before the advance in the first glyph's record
		size := 2*(bits(v1) + bits(v2))
		if be16(d, t) == 1 {
			set := t + be16(d, t + 10 + 2*at)
			for i in 0..<be16(d, set) do if r := set + 2 + (2 + size)*i; be16(d, r) == b do return f32(bi16(d, r + 2 + before))
		} else {
			c1, c2 := class(d, t + be16(d, t + 8), a), class(d, t + be16(d, t + 10), b)
			return f32(bi16(d, t + 16 + (c1*be16(d, t + 14) + c2)*size + before))
		}
	}
	return 0
}

// A glyph's outline as straight lines in pixels, y down from the baseline, each curve cut into as
// many as keep it within a tenth of a pixel. `m` turns the glyph's own units into the face's: a
// glyph made of others places each by its own.
font_outline :: proc(f: ^Font, g: int, scale: f32, out: ^[dynamic][2][2]f32, m := [6]f32{1, 0, 0, 1, 0, 0}, depth := 0) {
	d := f.data
	place :: proc(f: ^Font, g: int) -> int { return f.glyf + (be32(f.data, f.loca + 4*g) if f.wide_loca else 2*be16(f.data, f.loca + 2*g)) }
	if g < 0 || g >= f.count || depth > 4 do return
	at := place(f, g)
	if at == place(f, g + 1) do return   // it has no outline: a space
	contours := bi16(d, at)
	at += 10
	if contours < 0 {
		for {
			flags, part := be16(d, at), be16(d, at + 2)
			at += 4
			t := [6]f32{1, 0, 0, 1, 0, 0}
			if flags & 1 != 0 do t[4], t[5], at = f32(bi16(d, at)), f32(bi16(d, at + 2)), at + 4
			else do t[4], t[5], at = f32(i8(d[at])), f32(i8(d[at + 1])), at + 2
			if flags & 8 != 0 do t[0], t[3], at = f32(bi16(d, at))/16384, f32(bi16(d, at))/16384, at + 2
			else if flags & 0x40 != 0 do t[0], t[3], at = f32(bi16(d, at))/16384, f32(bi16(d, at + 2))/16384, at + 4
			else if flags & 0x80 != 0 do t[0], t[1], t[2], t[3], at = f32(bi16(d, at))/16384, f32(bi16(d, at + 2))/16384, f32(bi16(d, at + 4))/16384, f32(bi16(d, at + 6))/16384, at + 8
			// The part's own units into this glyph's, then this glyph's into the face's.
			font_outline(f, part, scale, out, {
				m[0]*t[0] + m[2]*t[1], m[1]*t[0] + m[3]*t[1], m[0]*t[2] + m[2]*t[3], m[1]*t[2] + m[3]*t[3],
				m[0]*t[4] + m[2]*t[5] + m[4], m[1]*t[4] + m[3]*t[5] + m[5],
			}, depth + 1)
			if flags & 0x20 == 0 do break
		}
		return
	}
	ends := at
	n := be16(d, ends + 2*(contours - 1)) + 1
	at += 2*contours
	at += 2 + be16(d, at)   // the instructions, not run
	Dot :: struct { p: [2]f32, on: bool }
	dots := make([]Dot, n, context.temp_allocator)
	flags := make([]u8, n, context.temp_allocator)
	for i := 0; i < n; i += 1 {
		flags[i] = d[at]
		at += 1
		if flags[i] & 8 != 0 {
			for _ in 0..<int(d[at]) {
				i += 1
				flags[i] = flags[i - 1]
			}
			at += 1
		}
	}
	for axis in 0..<2 {
		short, same := u8(2) << uint(axis), u8(16) << uint(axis)
		v := 0
		for i in 0..<n {
			if flags[i] & short != 0 {
				v += int(d[at]) if flags[i] & same != 0 else -int(d[at])
				at += 1
			} else if flags[i] & same == 0 {
				v += bi16(d, at)
				at += 2
			}
			dots[i].p[axis] = f32(v)
		}
	}
	for &q, i in dots {
		q.on = flags[i] & 1 != 0
		q.p = {(m[0]*q.p.x + m[2]*q.p.y + m[4])*scale, -(m[1]*q.p.x + m[3]*q.p.y + m[5])*scale}
	}
	curve :: proc(out: ^[dynamic][2][2]f32, a, c, b: [2]f32) {
		bend := a - 2*c + b
		steps := 1 + int(math.sqrt(math.sqrt(bend.x*bend.x + bend.y*bend.y)*2.5))
		last := a
		for i in 1..=steps {
			t := f32(i)/f32(steps)
			p := a*(1 - t)*(1 - t) + c*2*t*(1 - t) + b*t*t
			append(out, [2][2]f32{last, p})
			last = p
		}
	}
	first := 0
	for k in 0..<contours {
		last := be16(d, ends + 2*k)
		c := dots[first:last + 1]
		first = last + 1
		if len(c) < 2 do continue
		// A contour begins on a point of the outline: its first, its last, or half way between two that only pull at it.
		start, from, to := c[0].p, 1, len(c)
		if !c[0].on {
			if c[len(c) - 1].on do start, from, to = c[len(c) - 1].p, 0, len(c) - 1
			else do start, from = (c[0].p + c[len(c) - 1].p)/2, 0
		}
		at, pull, pulled := start, [2]f32{}, false
		for q in c[from:to] {
			if q.on {
				if pulled do curve(out, at, pull, q.p)
				else do append(out, [2][2]f32{at, q.p})
				at, pulled = q.p, false
			} else {
				if pulled {
					mid := (pull + q.p)/2
					curve(out, at, pull, mid)
					at = mid
				}
				pull, pulled = q.p, true
			}
		}
		if pulled do curve(out, at, pull, start)
		else do append(out, [2][2]f32{at, start})
	}
}

// Draw an outline into a rectangle of coverage, 0 to 255 a pixel, `w` by `h` with rows `stride`
// apart, its top left at `origin` in the outline's pixels. Each line adds to the pixels it crosses
// the share of each that lies to its right, signed by which way it runs; summed along a row, that
// is how much of each pixel the outline covers (after Raph Levien's font-rs).
font_draw :: proc(lines: [][2][2]f32, origin: [2]f32, out: []u8, w, h, stride: int) {
	acc := make([]f32, w*h + 4, context.temp_allocator)
	for l in lines {
		p0, p1 := l[0] - origin, l[1] - origin
		if p0.y == p1.y do continue
		dir := f32(1)
		if p0.y > p1.y do p0, p1, dir = p1, p0, -1
		dxdy := (p1.x - p0.x)/(p1.y - p0.y)
		x := p0.x
		if p0.y < 0 do x -= p0.y*dxdy
		for y in max(0, int(p0.y))..<min(h, int(math.ceil(p1.y))) {
			row := y*w
			dy := min(f32(y + 1), p1.y) - max(f32(y), p0.y)
			next := x + dxdy*dy
			d := dy*dir
			x0, x1 := min(x, next), max(x, next)
			x0f, x1c := math.floor(x0), math.ceil(x1)
			i0, i1 := clamp(int(x0f), 0, w), clamp(int(x1c), 0, w)
			if i1 <= i0 + 1 {
				mid := 0.5*(x + next) - x0f
				acc[row + i0] += d - d*mid
				acc[row + i0 + 1] += d*mid
			} else {
				s := 1/(x1 - x0)
				a := x0 - x0f
				a0 := 0.5*s*(1 - a)*(1 - a)
				b := x1 - x1c + 1
				am := 0.5*s*b*b
				acc[row + i0] += d*a0
				if i1 == i0 + 2 {
					acc[row + i0 + 1] += d*(1 - a0 - am)
				} else {
					a1 := s*(1.5 - a)
					acc[row + i0 + 1] += d*(a1 - a0)
					for i in i0 + 2..<i1 - 1 do acc[row + i] += d*s
					acc[row + i1 - 1] += d*(1 - a1 - f32(i1 - i0 - 3)*s - am)
				}
				acc[row + i1] += d*am
			}
			x = next
		}
	}
	sum := f32(0)
	for y in 0..<h do for x in 0..<w {
		sum += acc[y*w + x]
		out[y*stride + x] = u8(min(abs(sum), 1)*255 + 0.5)
	}
}
