package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

// The interface's ground (docs/adr/0010, docs/foundations/interface.md): how anything is put on
// the screen over the world. A screen is data: a list of parts, each a rectangle of the picture
// with what it says, what it looks like and what a click on it does. Whoever makes a screen (the
// play screen, play.odin) lists its parts each frame; this file measures and draws them, says which
// one the pointer is on, and can say the whole screen in words, so a picture or a test can ask what
// a screen says with no window.
//
// Everything is laid out in modules. A module is 4 pixels at the standard scale on a picture 1,440
// pixels high, and a whole number of pixels at every scale: 3 at 75%, 4, 5, 6, 7, and 8 at 200%
// (I9). Text is drawn from an atlas made for the scale in use, each glyph at the exact pixel size
// it is shown at and set on whole pixels, so it is sharp at every scale.
//
// Every colour, typeface, size and spacing is in LOOK below, and nowhere else.

Colour :: [4]u8
Face   :: enum u8 { Name, Text, Bold }
Style  :: enum u8 { Body, Bold, Small, Small_Bold, Key, Name, Title, Great, Figure, Door }
Type   :: struct { face: Face, size, line: f32 }   // in modules: the size of its em, and of a line of it

Look :: struct {
	// Stone, chalk and one metal (I10).
	basalt, slab, edge: Colour,   // a panel, a thing on it that can be pressed, and their one fine edge
	chalk, ash:         Colour,   // text, and quieter text
	brass:              Colour,   // what is live: the thing selected, the tool held, the cut
	verdigris:          Colour,   // what is well
	cinnabar:           Colour,   // what is wrong
	deep, pit:          Colour,   // a key's tab and a field to type in; a tooltip, and the line round a column
	held:               Colour,   // behind brass, on a thing in use
	lit:                Colour,   // a thing the pointer is on
	on_brass:           Colour,   // text on the one main action
	rule:               Colour,   // the hairline between rows
	shadow:             Colour,   // under a panel
	said:               Colour,   // behind the messages, fading to nothing toward their right
	dim:                Colour,   // over the world, behind a screen that takes all of it
	water:              Colour,   // the sea or a stream, where a thing has no block to show
	niche, eye:         Colour,   // behind a dwarf's picture, and its eyes
	kinds:              [8]Colour, // a lens that paints kinds of rock: the island's first, second and so on, told apart at a glance
	faces:              [Face][]u8,
	type:               [Style]Type,
	few:                bit_set[Style],   // the styles made of letters alone: too large for every glyph to have room in the atlas
	// Spacing and sizes, in modules.
	margin:             f32,      // from the picture's edge to a panel
	pad:                [2]f32,   // inside a panel, across and down
	gap:                f32,      // between two things in a row or a stack
	space:              f32,      // between two groups of things in a panel
	button:             f32,      // a button's height
	button_pad:         f32,
	key_min, key_pad, key_high, key_gap: f32,   // the tab a key is written on: its least width, the space beside its letter, its height, and how far it stands from the word
	know_pad:           f32,      // beside the word of a list's button
	row_pad:            [2]f32,   // inside a list's row
	tab_gap:            f32,      // between two tabs
	chip_pad:           [2]f32,   // inside a choice among a few
	block, block_large: f32,      // a material shown as a block of itself, small and at the head of a card
	sign:               f32,      // a diamond, a triangle or a disc
	bust:               f32,      // a dwarf's picture at the top of the screen and in a row; at the head of its card it is block_large
	crowd:              int,      // the most pictures the top of the screen shows: it is as wide at seventy dwarves as at seven (I14)
	bar:                f32,      // the brass line on a thing chosen, and the cut's mark
	shadow_fall, shadow_blur: f32,
	// Where the play screen's parts land (interface.md, section 4).
	hand_wide:          f32,
	hand_foot:          f32,      // from the picture's foot to the hand: the orders bar's place lies under it
	card_high:          [2]f32,   // the least and the most of a card's depth: what its tab says
	list_wide:          f32,
	ground_wide:        f32,
	ground_top:         f32,      // from the picture's top to the ground's panel, where there is room
	column_wide:        f32,
	beds_high:          [2]f32,   // the column's least height and its most
	wrong_wide:         f32,      // the stores and what is wrong, top right
	said_top, said_wide: f32,     // the messages
	wrong_least:        f32,      // the narrowest the alerts go to leave the dwarves their place at the top
	menu_wide:          f32,
	// Before play (interface.md, section 5): the front door, a world being made, and the world's screen.
	shade:              Colour,   // the dark behind the front door's words, clearing toward the picture's right
	shade_from:         f32,      // the share of its width from which it clears
	door_left, door_top: f32,     // where the front door's title stands
	door_wide:          f32,      // how wide its words run, and the panels that take their place
	choice:             f32,      // a choice's height
	choice_pad:         f32,      // from the brass line on the one in focus to its words
	making_wide:        f32,      // a world being made: its stages
	meter:              f32,      // how thick the line is that says how far a stage has come
	seas:               [2]Colour, // the world's map: the sea where it is shallow and where it is deepest
	unformed:           Colour,   // and what its land that is known and not yet formed is mixed toward
	isle:               f32,      // the least an island's mark is across on the map
	isles_wide:         f32,      // the islands' list, and the lenses under it
	isle_row:           f32,      // a row of it
	thumb:              f32,      // an island's picture in its row
	drift:              f32,      // modules a second the front door's picture of the world moves
	// Expedition planning (interface.md, section 16).
	shelter:            Colour,   // a shore the land shuts in, with fresh water a longer walk off; with it near, the shore is verdigris
	plan_row:           f32,      // a landing's row
	who_row, who_bust:  f32,      // a dwarf's, and its picture there
	site_beds:          f32,      // the room the beds' names take beside the column on a place's card
}

LOOK := Look {
	basalt = {0x22, 0x2a, 0x31, 255}, slab = {0x2d, 0x36, 0x3e, 255}, edge = {0x46, 0x52, 0x5c, 255},
	chalk = {0xed, 0xe8, 0xdd, 255}, ash = {0x9f, 0xa8, 0xad, 255},
	brass = {0xcd, 0xa8, 0x5f, 255}, verdigris = {0x6d, 0xb3, 0xa2, 255}, cinnabar = {0xd4, 0x51, 0x3b, 255},
	deep = {0x1a, 0x20, 0x26, 255}, pit = {0x14, 0x18, 0x1c, 255}, held = {0x3a, 0x34, 0x24, 255}, lit = {0x38, 0x43, 0x4d, 255},
	on_brass = {0x1d, 0x1a, 0x12, 255}, rule = {255, 255, 255, 18}, shadow = {0, 0, 0, 110}, said = {20, 24, 28, 184}, dim = {12, 15, 18, 150}, water = {0x2f, 0x62, 0x82, 255},
	niche = {0x3b, 0x45, 0x4e, 255}, eye = {0x1b, 0x17, 0x14, 255},
	kinds = {{0xcd, 0xa8, 0x5f, 255}, {0x6d, 0xb3, 0xa2, 255}, {0xc4, 0x6a, 0x4e, 255}, {0x7f, 0x93, 0xc9, 255}, {0xe6, 0xe0, 0xd0, 255}, {0x9a, 0x6f, 0xa8, 255}, {0x8f, 0xa8, 0x5a, 255}, {0x8a, 0x8f, 0x94, 255}},
	faces = {
		.Name = #load("../assets/fonts/Marcellus-Regular.ttf"),
		.Text = #load("../assets/fonts/AtkinsonHyperlegible-Regular.ttf"),
		.Bold = #load("../assets/fonts/AtkinsonHyperlegible-Bold.ttf"),
	},
	type = {
		.Body = {.Text, 6, 8}, .Bold = {.Bold, 6, 8},         // 24 pixels at the standard scale: the least body text may be (I9)
		.Small = {.Text, 5, 7}, .Small_Bold = {.Bold, 5, 7},
		.Key = {.Text, 4.5, 6.5},
		.Name = {.Name, 6.5, 8}, .Title = {.Name, 7.5, 9}, .Great = {.Name, 10, 11},
		.Figure = {.Text, 8, 9},                              // a count that stands for a list: the inscription face's figures are too like letters; and a choice at the front door
		.Door = {.Name, 22, 24},                              // the game's name at its front door
	},
	few = {.Door},
	margin = 4, pad = {5, 4}, gap = 1.5, space = 3.5,
	button = 11, button_pad = 4,
	key_min = 7, key_pad = 1.5, key_high = 6.5, key_gap = 2,
	know_pad = 3.5, row_pad = {5, 2}, tab_gap = 6, chip_pad = {3, 1},
	block = 5.5, block_large = 18, sign = 4, bar = 0.75, bust = 13, crowd = 10,
	shadow_fall = 1, shadow_blur = 6,
	hand_wide = 150, hand_foot = 21, card_high = {24, 56},
	list_wide = 200,
	ground_wide = 78, ground_top = 104, column_wide = 9, beds_high = {40, 120},
	wrong_wide = 172,
	said_top = 50, said_wide = 150, wrong_least = 96,
	menu_wide = 150,
	shade = {0x10, 0x15, 0x1a, 236}, shade_from = 0.22,
	door_left = 40, door_top = 62, door_wide = 190, choice = 16, choice_pad = 6,
	making_wide = 190, meter = 1, isle = 5, isles_wide = 112, isle_row = 16, thumb = 12, drift = 1.5,
	seas = {{0x3d, 0x74, 0x9e, 255}, {0x10, 0x25, 0x4c, 255}}, unformed = {0x7b, 0x86, 0x8c, 255},
	shelter = {0xed, 0xe8, 0xdd, 150}, plan_row = 15.5, who_row = 17.5, who_bust = 15, site_beds = 27,
}

// ---- text -----------------------------------------------------------------------------------

ATLAS  :: 2048   // pixels along the atlas's side: every glyph of every style at the largest scale
EXTRAS :: [?]rune{'–', '—', '‘', '’', '“', '”', '…', '•', '≈'}
GLYPH_COUNT :: 95 + 96 + len(EXTRAS)   // ASCII, Latin-1 (° ² ³ × · and the accents), and those

Glyph :: struct {
	x, y, w, h: u16,    // in the atlas
	off:        [2]i16, // from the pen on the baseline to its top left
	advance:    f32,
}
Baked :: struct {
	glyphs:          [GLYPH_COUNT]Glyph,
	scale:           f32,   // pixels to a unit of the face
	ascent, descent: f32,   // pixels over the baseline and under it
	line:            f32,   // pixels a line of it takes
}

Rect :: struct { x, y, w, h: f32 }   // pixels of the picture, from its top left

// One rectangle as the GPU takes it (vs_ui, ui.metal).
Ui_Quad :: struct { rect, uv, colour, extra: [4]f32 }

Ui :: struct {
	module: int,                 // pixels to a module at the scale in use; 0 before any is baked
	fonts:  [Face]Font,
	kern:   [Face][95][95]i16,   // between two ASCII glyphs, in the face's units
	baked:  [Style]Baked,
	pixels: []u8,                // the atlas: a glyph's coverage in each pixel, and a white square at its corner
	fresh:  bool,                // the atlas was made again and the GPU has not got it
	filled: int,                 // rows of the atlas the glyphs take
	quads:  [dynamic]Ui_Quad,    // the frame's rectangles
	clip:   Rect,                // nothing is drawn outside this while it has a width
	// On the GPU.
	pipe:            ^sdl.GPUGraphicsPipeline,
	atlas:           ^sdl.GPUTexture,
	atlas_staging:   ^sdl.GPUTransferBuffer,
	nearest, tiled:  ^sdl.GPUSampler,
	buffer:          ^sdl.GPUBuffer,
	staging:         ^sdl.GPUTransferBuffer,
	room:            int,
	// Pictures of the world's map (chart.odin): the known world, and a layer for each island.
	known:           ^sdl.GPUTexture,
	isles:           ^sdl.GPUTexture,
	layers:          int,
	smooth:          ^sdl.GPUSampler,
}
ui: Ui   // the frame thread's

// The scale a picture this high is shown at when none is asked for: the standard on 1,440 pixels,
// in steps of a quarter, from 75% to 200%.
scale_for :: proc(high: f32) -> int { return clamp(int(math.round(high/1440*4)), 3, 8) }

// Pixels in so many modules, whole.
px :: proc(modules: f32) -> f32 { return math.round(modules*f32(ui.module)) }

glyph_of :: proc(r: rune) -> int {
	if r >= 32 && r < 127 do return int(r) - 32
	if r >= 160 && r < 256 do return 95 + int(r) - 160
	for e, i in EXTRAS do if e == r do return 95 + 96 + i
	return '?' - 32
}

// Make the atlas for a scale: every glyph of every style, drawn at the pixel size the style has there.
ui_bake :: proc(module: int) {
	if ui.module == module do return
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if ui.pixels == nil {
		ui.pixels = make([]u8, ATLAS*ATLAS)
		for &font, face in ui.fonts {
			font = font_open(LOOK.faces[face])
			for a in 0..<95 do for b in 0..<95 do ui.kern[face][a][b] = i16(font_kern(&font, font_glyph(&font, rune(a + 32)), font_glyph(&font, rune(b + 32))))
		}
	}
	ui.module, ui.fresh = module, true
	for &p in ui.pixels do p = 0
	for y in 0..<4 do for x in 0..<4 do ui.pixels[y*ATLAS + x] = 255
	extras := EXTRAS
	lines := make([dynamic][2][2]f32, context.temp_allocator)
	x, y, row := 6, 1, 0   // where the next glyph goes, and the tallest in its row
	for t, style in LOOK.type {
		font, b := &ui.fonts[t.face], &ui.baked[style]
		b.scale = math.round(t.size*f32(module))/font.units
		b.ascent, b.descent, b.line = font.ascent*b.scale, font.descent*b.scale, math.round(t.line*f32(module))
		for i in 0..<GLYPH_COUNT {
			r := rune(i + 32) if i < 95 else rune(i - 95 + 160) if i < 95 + 96 else extras[i - 95 - 96]
			if style in LOOK.few && !(r == ' ' || r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z') do continue
			g := font_glyph(font, r)
			clear(&lines)
			font_outline(font, g, b.scale, &lines)
			lo, hi := [2]f32{1e9, 1e9}, [2]f32{-1e9, -1e9}
			for l in lines do for p in l do lo, hi = {min(lo.x, p.x), min(lo.y, p.y)}, {max(hi.x, p.x), max(hi.y, p.y)}
			b.glyphs[i] = {advance = font_advance(font, g)*b.scale}
			if len(lines) == 0 do continue
			x0, y0 := int(math.floor(lo.x)), int(math.floor(lo.y))
			w, h := int(math.ceil(hi.x)) - x0 + 1, int(math.ceil(hi.y)) - y0
			if x + w + 1 > ATLAS do x, y, row = 1, y + row + 1, 0
			if y + h + 1 > ATLAS do break   // no room: the glyph is left out, which a larger atlas mends
			font_draw(lines[:], {f32(x0), f32(y0)}, ui.pixels[y*ATLAS + x:], w, h, ATLAS)
			b.glyphs[i] = {u16(x), u16(y), u16(w), u16(h), {i16(x0), i16(y0)}, b.glyphs[i].advance}
			x, row = x + w + 1, max(row, h)
		}
	}
	ui.filled = y + row
}

// How wide a line of text is, in pixels.
text_wide :: proc(style: Style, s: string) -> (w: f32) {
	b, face := &ui.baked[style], LOOK.type[style].face
	last := -1
	for r in s {
		g := glyph_of(r)
		if last >= 0 && last < 95 && g < 95 do w += f32(ui.kern[face][last][g])*b.scale
		w += b.glyphs[g].advance
		last = g
	}
	return
}

// A text broken into lines no wider than `wide` pixels, at its spaces; a new line in it begins one.
text_lines :: proc(style: Style, s: string, wide: f32) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	b, face := &ui.baked[style], LOOK.type[style].face
	rest := s
	for para in strings.split_lines_iterator(&rest) {
		from, space, last := 0, -1, -1   // where the line begins, its last space, and the glyph before this one
		w, to_space := f32(0), f32(0)    // the line's width so far, and its width through that space
		for r, i in para {
			g := glyph_of(r)
			if last >= 0 && last < 95 && g < 95 do w += f32(ui.kern[face][last][g])*b.scale
			w += b.glyphs[g].advance
			if r == ' ' do space, to_space = i, w
			else if w > wide + 0.5 && space > from {
				append(&lines, para[from:space])
				from, w, space = space + 1, w - to_space, -1
			}
			last = g
		}
		append(&lines, para[from:])
	}
	return lines[:]
}

// How high a text stands once broken to a width, in pixels.
text_high :: proc(style: Style, s: string, wide: f32) -> f32 {
	return f32(len(text_lines(style, s, wide)))*ui.baked[style].line
}

// ---- rectangles -----------------------------------------------------------------------------

WHITE :: [4]f32{1, 1, 2, 2}   // the atlas's white square

quad_put :: proc(r: Rect, c: Colour, uv := WHITE, extra := [4]f32{}) {
	r, uv := r, uv
	if ui.clip.w > 0 {
		x0, y0 := max(r.x, ui.clip.x), max(r.y, ui.clip.y)
		x1, y1 := min(r.x + r.w, ui.clip.x + ui.clip.w), min(r.y + r.h, ui.clip.y + ui.clip.h)
		if x1 <= x0 || y1 <= y0 do return
		if extra.y != 0 && (x1 - x0 < r.w || y1 - y0 < r.h) do return   // a sign is whole or not there
		su, sv := (uv[2] - uv[0])/r.w, (uv[3] - uv[1])/r.h
		uv = {uv[0] + (x0 - r.x)*su, uv[1] + (y0 - r.y)*sv, uv[0] + (x1 - r.x)*su, uv[1] + (y1 - r.y)*sv}
		r = {x0, y0, x1 - x0, y1 - y0}
	}
	if r.w <= 0 || r.h <= 0 do return
	append(&ui.quads, Ui_Quad{{r.x, r.y, r.w, r.h}, uv, {f32(c.r)/255, f32(c.g)/255, f32(c.b)/255, f32(c.a)/255}, extra})
}

// A rectangle filled, with a line round it inside its edge where `line` has any colour.
box_put :: proc(r: Rect, fill: Colour, line := Colour{}, thick: f32 = 1, foot: f32 = 0) {
	if line.a == 0 {
		quad_put(r, fill)
		return
	}
	quad_put(r, line)
	quad_put({r.x + thick, r.y + thick, r.w - 2*thick, r.h - 2*thick - foot}, fill)
}

// A line of text with its line's top left at x, y. Each glyph is set on whole pixels.
text_put :: proc(style: Style, s: string, x, y: f32, c: Colour) {
	b, face := &ui.baked[style], LOOK.type[style].face
	base := math.round(y + (b.line - b.ascent - b.descent)/2 + b.ascent)
	pen, last := x, -1
	for r in s {
		i := glyph_of(r)
		if last >= 0 && last < 95 && i < 95 do pen += f32(ui.kern[face][last][i])*b.scale
		g := b.glyphs[i]
		if g.w > 0 do quad_put({math.round(pen) + f32(g.off.x), base + f32(g.off.y), f32(g.w), f32(g.h)}, c, {f32(g.x), f32(g.y), f32(g.x + g.w), f32(g.y + g.h)})
		pen += g.advance
		last = i
	}
}

// A block of a material, as the world shows its side: the tile itself, a texel to `texel` pixels,
// repeated to fill the rectangle from its top left.
tile_put :: proc(r: Rect, m: Mat, texel: f32, tint := Colour{255, 255, 255, 255}) {
	if int(m) >= BLOCK_MATS {   // a thing that is no block has no tile: its own colour (FOODS, food.odin)
		c := mat_rgb(m)
		quad_put(r, {u8(c >> 16), u8(c >> 8), u8(c), tint.a})
		return
	}
	quad_put(r, tint, {0, 0, r.w/(TILE*texel), r.h/(TILE*texel)}, {f32(int(m)*2 + 1) + 1, 0, 0, 0})
}

// ---- a screen -------------------------------------------------------------------------------

// What a part of a screen is, which sets how it is drawn.
Part_Kind :: enum u8 {
	Panel,    // a slab of stone: what stands on it is read against it, and it keeps the pointer from the world
	Text,     // words
	Button,   // a thing done, with its key written on it
	Know,     // a list's button: a word, and a brass line under it while its list is open
	Tab,      // one of a card's depths
	Chip,     // one choice among a few
	Row,      // a row of a list, which leads to its place
	Head,     // the head of a group of rows, with its count: it folds
	Rule,     // a hairline
	Fill,     // a plain rectangle of its colour
	Block,    // a material shown as a block of itself
	Niche,    // the ground a dwarf's picture stands on, with its one edge: brass where that dwarf is in the hand
	Bed,      // a bed of the column, in its own material
	Sign,     // a diamond for trouble, a triangle for caution, a disc for well
	Tip,      // a few words beside the pointer or beside a thing
	Band,     // the ground messages are read against
	Field,    // a line to type in
	Mark,     // the cut's level on the column
	Thumb,    // how far a scrolled thing has been scrolled
	Veil,     // the whole picture dimmed, behind a screen that takes all of it
	Choice,   // a choice at the front door: the one in focus is brass, with a brass line beside it and its key after its words
	Picture,  // a picture of the world's map: the known world, or an island
	Fade,     // a dark that clears toward its right, behind words that stand over a picture
	Ring,     // an island's mark on the map
}
State :: enum u8 { Held, Main, Open, Chosen, Wrap, Right, Centre, Faint, Solid, Shadow }
Sign  :: enum u8 { None, Well, Trouble, Caution }   // the shape numbers of ui.metal

// The places of the play screen (interface.md, I1), and what stands over the world itself.
Area :: enum u8 { Place, Dwarves, Wrong, Said, Hand, Orders, Ground, Lenses, Lists, List, Menu, World, Lesson, Door, Making, Chart }

Screen_Part :: struct {
	part:   Part_Kind,
	area:   Area,
	id:     string,       // what it is, for a test and for --say: "clock.pause", "hand.title"
	rect:   Rect,
	clip:   Rect,
	text:   string,
	key:    string,       // the key written on it
	tip:    string,       // said beside the pointer when it rests on it
	style:  Style,
	colour: Colour,
	state:  bit_set[State],
	act:    Act,          // what a click on it does (play.odin), and with what
	arg:    int,
	mat:    Mat,
	sign:   Sign,
	uv:     [4]f32,       // a picture: the part of it shown, from its top left to its bottom right, each from 0 to 1
}

Screen :: struct {
	items:   [dynamic]Screen_Part,
	w, h:    f32,        // the picture, in pixels
	pointer: [2]f32,     // in pixels
	hot:     int,        // the part the pointer is on that a click would press, or -1
}
screen: Screen   // the frame's, made by play_frame and drawn by ui_render; the frame thread's

inside :: proc(r: Rect, p: [2]f32) -> bool { return p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h }

// Which part a point of the picture is on. The parts lie in the order they were listed, later over
// earlier: the topmost that can be pressed or that is solid decides. `hot` is the part a click
// would press, or -1; `on` the topmost part there that takes the pointer at all, or -1; `solid`
// says the point is the interface's and not the world's.
screen_over :: proc(s: ^Screen, p: [2]f32) -> (hot: int, solid: bool, on: int) {
	hot, on = -1, -1
	#reverse for it, i in s.items {
		if !inside(it.rect, p) || it.clip.w > 0 && !inside(it.clip, p) do continue
		if it.act != .None do return i, true, i
		if it.part == .Panel || it.part == .Veil || .Solid in it.state do return -1, true, i
	}
	return
}

// The first part with an id, for a test to read or to press.
screen_find :: proc(s: ^Screen, id: string) -> ^Screen_Part {
	for &it in s.items do if it.id == id do return &it
	return nil
}

// What an area of the screen says, a part to a line: its words, the key written on it in square
// brackets, and a star where it is held, open or chosen.
screen_says :: proc(s: ^Screen, area: Area) -> string {
	b := strings.builder_make(context.temp_allocator)
	for it in s.items do if it.area == area && (it.text != "" || it.part == .Bed || it.part == .Block) {
		words := it.text if it.text != "" else mat_words(it.mat)
		fmt.sbprintf(&b, "%s%s%s%s\n", "* " if it.state & {.Held, .Open, .Chosen} != {} else "", words, fmt.tprintf(" [%s]", it.key) if it.key != "" else "", fmt.tprintf("  (%s)", it.id) if it.id != "" else "")
	}
	return strings.to_string(b)
}

// How wide a button is for its word and its key.
button_wide :: proc(text, key: string, style := Style.Body, pad := LOOK.button_pad) -> f32 {
	w := 2*px(pad) + text_wide(style, text)
	if key != "" do w += px(LOOK.key_gap) + key_wide(key)
	return w
}
key_wide :: proc(key: string) -> f32 { return max(px(LOOK.key_min), text_wide(.Key, key) + 2*px(LOOK.key_pad)) }

// A key's tab, its right edge at x, standing in the middle of a row.
key_put :: proc(key: string, right: f32, row: Rect) {
	w, h := key_wide(key), px(LOOK.key_high)
	r := Rect{right - w, row.y + math.round((row.h - h)/2), w, h}
	box_put(r, LOOK.deep, LOOK.edge, 1, 1)
	text_put(.Key, key, r.x + math.round((w - text_wide(.Key, key))/2), r.y, LOOK.ash)
}

// The frame's rectangles from its parts.
screen_draw :: proc(s: ^Screen) {
	clear(&ui.quads)
	L := &LOOK
	for it, i in s.items {
		r := it.rect
		ui.clip = it.clip
		hot := i == s.hot
		edge := max(1, math.round(f32(ui.module)/4))
		#partial switch it.part {
		case .Veil:
			quad_put(r, L.dim)
		case .Panel:
			b := px(L.shadow_blur)
			quad_put({r.x - b, r.y - b + px(L.shadow_fall), r.w + 2*b, r.h + 2*b}, L.shadow, WHITE, {0, 0, 2*b, 0})
			box_put(r, L.basalt, L.edge, edge)
		case .Band:
			quad_put(r, L.said, WHITE, {0, 0, 0, 0.35})
		case .Fill:
			quad_put(r, it.colour)
		case .Rule:
			quad_put({r.x, r.y, r.w, 1}, it.colour if it.colour.a > 0 else L.rule)
		case .Text:
			c := it.colour if it.colour.a > 0 else L.chalk
			if hot && it.act != .None do c = {L.brass.r, L.brass.g, L.brass.b, c.a}   // words that lead somewhere, under the pointer
			if .Shadow in it.state {   // words over the world itself
				for o in ([4][2]f32{{-1, 0}, {1, 0}, {0, 1}, {0, 2}}) do text_block(it, r.x + o.x*edge, r.y + o.y*edge, {0, 0, 0, u8(150*int(c.a)/255)})   // the shadow fades with its words, or a fading line turns black
			}
			text_block(it, r.x, r.y, c)
		case .Button:
			held, main := .Held in it.state, .Main in it.state
			fill := L.brass if main else L.held if held else L.lit if hot else L.slab
			box_put(r, fill, L.brass if held || main else L.edge, edge)
			c := L.on_brass if main else L.brass if held else L.ash if .Faint in it.state else L.chalk
			text_put(.Bold if main else it.style, it.text, r.x + px(L.button_pad), r.y + math.round((r.h - ui.baked[it.style].line)/2), c)
			if it.key != "" do key_put(it.key, r.x + r.w - px(L.button_pad), r)
		case .Know:
			open := .Open in it.state
			text_put(it.style, it.text, r.x + px(L.know_pad), r.y + math.round((r.h - ui.baked[it.style].line)/2), L.chalk if open || hot else L.ash)
			if it.key != "" do key_put(it.key, r.x + r.w - px(L.know_pad), r)
			if open do quad_put({r.x, r.y + r.h - px(L.bar) - edge, r.w, px(L.bar)}, L.brass)
		case .Tab:
			on := .Chosen in it.state
			text_put(it.style, it.text, r.x, r.y, L.chalk if on || hot else L.ash)
			if on do quad_put({r.x, r.y + r.h - 1, r.w, 2*edge}, L.brass)
		case .Chip:
			on, quiet := .Chosen in it.state, .Faint in it.state   // quiet: one of many alike in a list, so its being chosen is said by its word alone
			box_put(r, L.held if on && !quiet else L.lit if hot else L.basalt, L.brass if on && !quiet else L.edge, edge)
			text_put(it.style, it.text, r.x + px(L.chip_pad.x), r.y + math.round((r.h - ui.baked[it.style].line)/2), L.brass if on else L.chalk if hot else L.ash)
			if it.key != "" do key_put(it.key, r.x + r.w - px(L.chip_pad.x), r)
		case .Row:
			if .Chosen in it.state {
				quad_put(r, L.slab)
				quad_put({r.x, r.y, px(1), r.h}, L.brass)
			} else if hot {
				quad_put(r, {L.slab.r, L.slab.g, L.slab.b, 150})
			}
			quad_put({r.x, r.y, r.w, 1}, L.rule)
		case .Head:
			if hot do quad_put(r, {L.slab.r, L.slab.g, L.slab.b, 110})
		case .Block:
			texel := max(1, math.floor(r.w/TILE))
			tile_put(r, it.mat, r.w/TILE if r.w < TILE else texel)
			b := max(1, math.round(r.w/6)) if r.w < px(L.block_large) else edge   // the small ones are bevelled, to read as blocks at their size
			if r.w < px(L.block_large) {
				quad_put({r.x, r.y, r.w, b}, {255, 255, 255, 56}); quad_put({r.x, r.y + b, b, r.h - b}, {255, 255, 255, 56})
				quad_put({r.x, r.y + r.h - b, r.w, b}, {0, 0, 0, 72}); quad_put({r.x + r.w - b, r.y, b, r.h - b}, {0, 0, 0, 72})
			} else {
				for k in ([4]Rect{{r.x, r.y, r.w, b}, {r.x, r.y + r.h - b, r.w, b}, {r.x, r.y, b, r.h}, {r.x + r.w - b, r.y, b, r.h}}) do quad_put(k, L.brass if .Chosen in it.state else L.edge)
			}
		case .Niche:
			on := .Chosen in it.state
			box_put(r, L.niche, L.brass if on else L.chalk if hot else L.edge, 2*edge if on || hot else edge)
		case .Bed:
			tile_put(r, it.mat, max(1, math.round(f32(ui.module)/2)), it.colour if it.colour.a > 0 else Colour{255, 255, 255, 255})
			quad_put({r.x, r.y, r.w, 1}, {0, 0, 0, 90})
		case .Sign:
			c := it.colour if it.colour.a > 0 else L.cinnabar if it.sign == .Trouble else L.brass if it.sign == .Caution else L.verdigris
			quad_put(r, c, WHITE, {0, f32(it.sign), 0, 0})
		case .Tip:
			box_put(r, L.pit, L.brass, edge)
			inner := it
			inner.rect.w -= 2*px(L.chip_pad.x)
			text_block(inner, r.x + px(L.chip_pad.x), r.y + px(L.chip_pad.y), L.chalk)
		case .Field:
			box_put(r, L.deep, L.brass if .Held in it.state else L.edge, edge)
			text_put(it.style, it.text, r.x + px(L.chip_pad.x), r.y + math.round((r.h - ui.baked[it.style].line)/2), L.ash if .Faint in it.state else L.chalk)
			if .Held in it.state do quad_put({r.x + px(L.chip_pad.x) + (0 if .Faint in it.state else text_wide(it.style, it.text)) + 1, r.y + px(1.5), edge, r.h - px(3)}, L.brass)
		case .Mark:
			quad_put(r, L.brass)
		case .Thumb:
			quad_put(r, L.edge if !hot else L.ash)
		case .Choice:
			on := .Chosen in it.state
			c := L.brass if on else L.ash if .Faint in it.state else L.chalk
			if on do quad_put({r.x, r.y, px(L.bar), r.h}, L.brass)
			x, y := r.x + px(L.choice_pad), r.y + math.round((r.h - ui.baked[it.style].line)/2)
			text_put(it.style, it.text, x, y, c)
			if on && it.key != "" do key_put(it.key, x + text_wide(it.style, it.text) + px(L.key_gap) + px(1) + key_wide(it.key), r)
		case .Picture:
			quad_put(r, it.colour if it.colour.a > 0 else Colour{255, 255, 255, 255}, it.uv, {-(f32(it.arg) + 1 + (0.5 if .Faint in it.state else 0)), 0, 0, 0})
		case .Fade:
			quad_put(r, it.colour if it.colour.a > 0 else L.shade, WHITE, {0, 0, 0, L.shade_from})
		case .Ring:
			quad_put(r, it.colour if it.colour.a > 0 else L.chalk, WHITE, {0, 4, 0, 0})
		}
	}
	ui.clip = {}
}

// A part's words in its rectangle: broken to its width where it wraps, set to its right or its middle where it asks.
text_block :: proc(it: Screen_Part, x, y: f32, c: Colour) {
	line := ui.baked[it.style].line
	lines := text_lines(it.style, it.text, it.rect.w) if .Wrap in it.state else []string{it.text}
	for l, i in lines {
		at := x
		if .Right in it.state do at = x + it.rect.w - text_wide(it.style, l)
		if .Centre in it.state do at = x + math.round((it.rect.w - text_wide(it.style, l))/2)
		text_put(it.style, l, at, y + f32(i)*line, c)
	}
}

// ---- on the GPU -----------------------------------------------------------------------------

UI_SHADERS :: #load("ui.metal", string)

// Draw the frame's rectangles over the finished picture of the world, before it goes to the window
// or to a file. Called by render once the scene is drawn.
ui_render :: proc(g: ^Gpu, cmd: ^sdl.GPUCommandBuffer) {
	n := len(ui.quads)
	if n == 0 || ui.pixels == nil do return
	if ui.pipe == nil {
		world := g.source   // the interface's shaders are a file of their own
		g.source = strings.clone_to_cstring(UI_SHADERS)
		ui.pipe = make_pipeline(g, {vs = "vs_ui", fs = "fs_ui", vs_uniforms = 1, fs_samplers = 4, boxes = true, cull = .NONE, color = g.format, samples = ._1, blend = true})
		g.source = world
		#assert(size_of(Ui_Quad) == size_of(Box))   // both are four vectors of four, which that pipeline's vertices are read as
		ui.atlas = sdl.CreateGPUTexture(g.dev, {type = .D2, format = .R8_UNORM, usage = {.SAMPLER}, width = ATLAS, height = ATLAS, layer_count_or_depth = 1, num_levels = 1})
		ui.atlas_staging = sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = ATLAS*ATLAS})
		ui.nearest = sdl.CreateGPUSampler(g.dev, {min_filter = .NEAREST, mag_filter = .NEAREST, address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE})
		ui.tiled = sdl.CreateGPUSampler(g.dev, {min_filter = .NEAREST, mag_filter = .NEAREST, address_mode_u = .REPEAT, address_mode_v = .REPEAT, address_mode_w = .REPEAT})
		ui.smooth = sdl.CreateGPUSampler(g.dev, {min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_mode = .LINEAR, address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE})
	}
	if n > ui.room {
		if ui.buffer != nil {
			sdl.ReleaseGPUBuffer(g.dev, ui.buffer)
			sdl.ReleaseGPUTransferBuffer(g.dev, ui.staging)
		}
		for ui.room = 4096; ui.room < n; ui.room *= 2 {}
		ui.buffer = sdl.CreateGPUBuffer(g.dev, {usage = {.VERTEX}, size = u32(ui.room*size_of(Ui_Quad))})
		ui.staging = sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = u32(ui.room*size_of(Ui_Quad))})
	}
	copy((cast([^]Ui_Quad)sdl.MapGPUTransferBuffer(g.dev, ui.staging, true))[:n], ui.quads[:])
	sdl.UnmapGPUTransferBuffer(g.dev, ui.staging)
	if ui.fresh {
		copy((cast([^]u8)sdl.MapGPUTransferBuffer(g.dev, ui.atlas_staging, true))[:ATLAS*ATLAS], ui.pixels)
		sdl.UnmapGPUTransferBuffer(g.dev, ui.atlas_staging)
	}
	copies := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUBuffer(copies, {ui.staging, 0}, {ui.buffer, 0, u32(n*size_of(Ui_Quad))}, true)
	if ui.fresh do sdl.UploadToGPUTexture(copies, {transfer_buffer = ui.atlas_staging}, {texture = ui.atlas, w = ATLAS, h = ATLAS, d = 1}, true)
	sdl.EndGPUCopyPass(copies)
	ui.fresh = false

	over := sdl.GPUColorTargetInfo{texture = g.scene, load_op = .LOAD, store_op = .STORE}
	pass := sdl.BeginGPURenderPass(cmd, &over, 1, nil)
	sdl.BindGPUGraphicsPipeline(pass, ui.pipe)
	size := [4]f32{f32(g.w), f32(g.h), 0, 0}
	sdl.PushGPUVertexUniformData(cmd, 0, &size, size_of(size))
	// Where no picture of the world has been made, the atlas and the blocks stand in their places, unread.
	bindings := [4]sdl.GPUTextureSamplerBinding{{ui.atlas, ui.nearest}, {g.blocks, ui.tiled}, {ui.known if ui.known != nil else ui.atlas, ui.smooth}, {ui.isles if ui.isles != nil else g.blocks, ui.smooth}}
	sdl.BindGPUFragmentSamplers(pass, 0, &bindings[0], 4)
	binding := sdl.GPUBufferBinding{buffer = ui.buffer}
	sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
	sdl.DrawGPUPrimitives(pass, 4, u32(n), 0, 0)
	sdl.EndGPURenderPass(pass)
}

// The runes of a string typed so far, less its last.
without_last :: proc(s: string) -> string {
	_, n := utf8.decode_last_rune_in_string(s)
	return s[:len(s) - n]
}

// ---- pictures -------------------------------------------------------------------------------

PICTURE_KNOWN :: 2048   // pixels along a side of the known world's picture: half a kilometre to a pixel
PICTURE_ISLE  :: 1024   // and of an island's: its land's own cells where it is 16 km across

// Put a picture of the world on the GPU: the known world's (layer -1), or an island's, with smaller
// copies of itself for where it is drawn small. The islands' pictures are made again where the world
// in hand has more islands than they have layers. `pixels` are four bytes each, as the display takes them.
picture_put :: proc(g: ^Gpu, layer, layers: int, pixels: []u8) {
	size := u32(PICTURE_KNOWN if layer < 0 else PICTURE_ISLE)
	levels :: proc(size: u32) -> u32 { n := u32(1); for s := size; s > 1; s /= 2 do n += 1; return n }
	if layer < 0 && ui.known == nil {
		ui.known = sdl.CreateGPUTexture(g.dev, {type = .D2, format = .R8G8B8A8_UNORM, usage = {.SAMPLER, .COLOR_TARGET}, width = size, height = size, layer_count_or_depth = 1, num_levels = levels(size)})
	}
	if layer >= 0 && ui.layers < layers {
		if ui.isles != nil do sdl.ReleaseGPUTexture(g.dev, ui.isles)
		ui.layers = max(layers, 2)   // an array has two layers or more
		ui.isles = sdl.CreateGPUTexture(g.dev, {type = .D2_ARRAY, format = .R8G8B8A8_UNORM, usage = {.SAMPLER, .COLOR_TARGET}, width = size, height = size, layer_count_or_depth = u32(ui.layers), num_levels = levels(size)})
	}
	staging := sdl.CreateGPUTransferBuffer(g.dev, {usage = .UPLOAD, size = size*size*4})
	copy((cast([^]u8)sdl.MapGPUTransferBuffer(g.dev, staging, false))[:size*size*4], pixels)
	sdl.UnmapGPUTransferBuffer(g.dev, staging)
	cmd := sdl.AcquireGPUCommandBuffer(g.dev)
	pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(pass, {transfer_buffer = staging}, {texture = ui.known if layer < 0 else ui.isles, layer = u32(max(layer, 0)), w = size, h = size, d = 1}, false)
	sdl.EndGPUCopyPass(pass)
	sdl.GenerateMipmapsForGPUTexture(cmd, ui.known if layer < 0 else ui.isles)
	_ = sdl.SubmitGPUCommandBuffer(cmd)
	sdl.ReleaseGPUTransferBuffer(g.dev, staging)
}
