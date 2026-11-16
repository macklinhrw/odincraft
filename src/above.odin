package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"

// The view from above (docs/adr/0007): the camera the hold is seen and ordered through. It looks
// down on a point of the ground, `at`, from as far off as puts `span` metres of ground across the
// picture, and pans, turns, tilts and zooms about that point, from one hold's ground out to the
// whole island. The world can be cut at a level, above which nothing is drawn, so the ground under
// the trees and the inside of a hill show; the level is set by hand or follows the ground under
// the view's middle. The block under the pointer is picked through the same cut (pick).
//
// What the keys do, a panel can do: the view's state is this record, and each key below sets a
// field of it or calls a procedure here (cut_set, cut_move, cut_follow, walk_down, walk_up, the
// marks, why_words). The interface (docs/foundations/interface.md) is to draw panels over the
// picture's edges and share the pointer with them, so whatever the pointer does to the world asks
// over_world first.
//
// Controls (the keys shared with first person are in main.odin). The letters D, T, G, B, S, X and L
// and the function keys are left for the interface's orders, lenses and lists.
//   arrows           pan                      Shift    faster, or the level by eight
//   middle drag      pan                      right drag   turn and tilt
//   Q E              turn                     Page Up, Page Down   tilt: more from above, more from the side
//   the wheel, = -   zoom in and out
//   R F              raise the cut a block, lower it; held, it goes on moving
//   C                cut the world, or not    H        the cut holds to the ground under the middle
//   V                leaves drawn, or not
//   Space            pause the world          1 2 3    run it at its three speeds (clock.odin)
//   left click       mark a block; drag to mark a box of them

ABOVE_FOV :: 30.0   // vertical, degrees: narrow, so that upright things stand upright across the picture
HEADROOM  :: 3      // blocks the cut stands over the ground it follows: room for what stands on that ground
SPAN_MIN  :: 24.0   // metres across the picture at the nearest
SPAN_MAX  :: 24000.0
TILT_MIN  :: 0.6    // radians: lower than this the picture's top reaches the horizon

Above :: struct {
	at:      [3]f64,   // the point under the view's middle: on the ground, or on the cut where that is lower
	yaw:     f32,      // which way the picture's top faces, as the player's: 0 north (-Z), turning east
	tilt:    f32,      // radians the view looks down; a quarter turn is straight down
	span:    f64,      // metres of ground across the picture's width, at its middle
	cut:     bool,     // the world is cut at `level`
	level:   i32,      // nothing of the world from this height up is drawn
	follow:  bool,     // the level keeps HEADROOM over the ground under the middle
	bare:    bool,     // leaves are not drawn
	settled: bool,     // `at` has been put on the ground once; from then it eases after it
	mark:    [2][3]i32,   // the box of blocks marked: where it was begun, and where the pointer has taken it
	marking, marked: bool,
	pointer: [2]f32,   // where the pointer is in the picture, from 0, 0 at its top left to 1, 1
	shown:   bool,     // it is over the world (over_world), so the block under it is marked on screen
	under:   Pick,     // the block under it, picked through the cut (above_point)
	}

	// Whether a point of the picture is over the world, where a click, a drag or the wheel is the
	// world's. Nothing is drawn over the world yet, so every point in the picture is; the interface's
	// panels are to answer here, once, for everything the pointer does.
	over_world :: proc(p: [2]f32) -> bool { return p.x >= 0 && p.x < 1 && p.y >= 0 && p.y < 1 }

	// Cut the world at the ground under the view's middle, or not at all.
	cut_set :: proc(a: ^Above, on: bool) {
	if on && !a.cut do a.level = ground_top(a.at.x, a.at.z) + HEADROOM
	a.cut = on
	}

	// Move the cut's level by so many blocks, from the ground under the middle if the world was not
	// cut. The level is then the player's, and no longer follows the ground.
	cut_move :: proc(a: ^Above, blocks: i32) {
	cut_set(a, true)
	a.follow = false
	a.level += blocks
	}

	// The cut holds HEADROOM over the ground under the view's middle as the view moves, or stays where it is.
	cut_follow :: proc(a: ^Above, on: bool) {
	a.follow = on
	if on do a.cut = true
	}

	// The pointer has moved, or the view under it: pick the block it is on. A box being marked follows it.
	above_point :: proc(a: ^Above, w: ^World, eye: [3]f64, pitch, aspect: f32, pointer: [2]f32) {
	a.pointer, a.shown = pointer, over_world(pointer)
	a.under = {}
	if w.finest == 0 do a.under = pick(w, eye, view_ray(a.yaw, pitch, ABOVE_FOV, aspect, pointer), above_level(a), a.bare, 4*linalg.length(a.at - eye) + 600)   // from too far off for the block volume there is no block to pick (pick_far)
	if a.marking && a.shown && a.under.ok do a.mark[1] = a.under.block
	}

	// Begin marking a box of blocks at the block under the pointer; mark_end leaves it marked, and
	// mark_box says what it holds. A click marks one block.
	mark_begin :: proc(a: ^Above) {
	if a.shown && a.under.ok do a.mark, a.marking, a.marked = {a.under.block, a.under.block}, true, true
	}
	mark_end :: proc(a: ^Above) { a.marking = false }
	mark_clear :: proc(a: ^Above) { a.marking, a.marked = false, false }
	mark_box :: proc(a: ^Above) -> (lo, hi: [3]i32, blocks: int, ok: bool) {
	lo, hi = box_of(a.mark[0], a.mark[1])
	return lo, hi, int(hi.x - lo.x + 1)*int(hi.y - lo.y + 1)*int(hi.z - lo.z + 1), a.marked
	}

	// Down to first person: the player is put at the place under the view's middle, on the cut where the
	// world is cut there, facing the way the picture's top did. Inside rock, the player rises to the
	// first free space (player_update).
	walk_down :: proc(a: ^Above, w: ^World, p: ^Player, aspect: f32) {
	eye, pitch, _ := above_camera(a, aspect)
	under := pick(w, eye, look_dir(a.yaw, pitch), above_level(a), true, 4*linalg.length(a.at - eye) + 600)
	p.pos = {a.at.x, f64(ground_top(a.at.x, a.at.z)) + 0.1, a.at.z}
	if a.cut && under.ok do p.pos = {f64(under.block.x) + 0.5, f64(under.block.y) + 1.1, f64(under.block.z) + 0.5}
	p.yaw, p.pitch, p.vel, p.fly, p.eye = a.yaw, 0, 0, false, EYE
	}

	// Back up from first person: the view from above, over where the player stands, facing the same way.
	walk_up :: proc(a: ^Above, p: ^Player) {
	a.at, a.yaw = p.pos, p.yaw
	mark_clear(a)
	}

// The cut's level as the renderer and the pick take it.
above_level :: proc(a: ^Above) -> f64 { return f64(a.level) if a.cut else NO_CUT }

// The ground or the sea under a point, in whole blocks: its top.
ground_top :: proc(x, z: f64) -> i32 { return max(i32(math.round(height_in_world(x, z, 1))), SEA_LEVEL) }

// Move the view by what is asked of it this frame: `pan` across the picture and up it, `turn`,
// `tilt` and `zoom` as rates. Then the level follows the ground, and the view's middle the level.
above_update :: proc(a: ^Above, dt: f64, pan: [2]f32, turn, tilt, zoom: f32, fast: bool) {
	forward := [2]f64{f64(math.sin(a.yaw)), f64(-math.cos(a.yaw))}
	right := [2]f64{f64(math.cos(a.yaw)), f64(math.sin(a.yaw))}
	a.at.xz += (right*f64(pan.x) + forward*f64(pan.y))*a.span*(2.4 if fast else 0.8)*dt
	a.yaw += turn*1.6*f32(dt)
	a.tilt = clamp(a.tilt + tilt*1.2*f32(dt), TILT_MIN, math.PI/2)
	a.span = clamp(a.span*math.exp(f64(zoom)*1.8*dt), SPAN_MIN, SPAN_MAX)
	ground := ground_top(a.at.x, a.at.z)
	if a.follow do a.level = ground + HEADROOM
	y := f64(min(ground, a.level) if a.cut else ground)
	a.at.y = y if !a.settled else a.at.y + (y - a.at.y)*min(1, 10*dt)   // eased, so a cliff under the middle does not throw the view
	a.settled = true
}

// Where the view is seen from: the eye and its pitch, and the point the world streams round. The
// rings of chunks reach as far as they do because a cell is then a few pixels wide from the eye in
// first person; this lens is narrower, so the eye stands farther off for the same picture, and the
// rings are centred over the view's middle as high as an eye in first person would see it as large.
above_camera :: proc(a: ^Above, aspect: f32) -> (eye: [3]f64, pitch: f32, centre: [3]f64) {
	tan_y := math.tan(math.to_radians(f32(ABOVE_FOV))/2)
	off := a.span/2/f64(tan_y*aspect)
	back := look_dir(a.yaw, -a.tilt)
	eye = a.at - [3]f64{f64(back.x), f64(back.y), f64(back.z)}*off
	centre = a.at + {0, off*f64(tan_y/math.tan(math.to_radians(f32(FOV))/2)), 0}
	return eye, -a.tilt, centre
}

// The ray from the eye through a point of the picture, which runs from 0, 0 at its top left to 1, 1.
view_ray :: proc(yaw, pitch, fov, aspect: f32, p: [2]f32) -> [3]f32 {
	forward := look_dir(yaw, pitch)
	right := [3]f32{math.cos(yaw), 0, math.sin(yaw)}
	up := linalg.cross(right, forward)
	tan_y := math.tan(math.to_radians(fov)/2)
	return linalg.normalize(forward + right*((2*p.x - 1)*tan_y*aspect) + up*((1 - 2*p.y)*tan_y))
}

// A block picked: the block, the empty cell the ray came to it through, and whether it is a block
// of the volume (`exact`) or the top of a column of the ground beyond it.
Pick :: struct {
	block, before: [3]i32,
	ok, exact:     bool,
}

// The block under a ray, as the view shows it: the first block of the volume along the ray that
// is drawn. What is above the cut's level is not there, so a ray from over it begins where it
// comes down through the level, and a block it meets there is picked on its cut face. With `bare`
// it passes through leaves. Later steps mark ground to dig and build through this.
pick :: proc(w: ^World, eye: [3]f64, dir: [3]f32, level: f64, bare: bool, reach: f64) -> (p: Pick) {
	from := 0.0
	if eye.y > level {
		if dir.y >= 0 do return
		from = (eye.y - level)/f64(-dir.y) + 1e-3
	}
	origin := eye + [3]f64{f64(dir.x), f64(dir.y), f64(dir.z)}*from
	cell := [3]i32{i32(math.floor(origin.x)), i32(math.floor(origin.y)), i32(math.floor(origin.z))}
	step: [3]i32
	next, delta: [3]f64   // distance along the ray to the next cell wall, and between walls
	for a in 0..<3 {
		d := f64(dir[a])
		if d > 0 {
			step[a], delta[a], next[a] = 1, 1/d, (f64(cell[a]) + 1 - origin[a])/d
		} else if d < 0 {
			step[a], delta[a], next[a] = -1, -1/d, (f64(cell[a]) - origin[a])/d
		} else {
			delta[a], next[a] = math.INF_F64, math.INF_F64
		}
	}
	p.before = cell + {0, 1, 0}   // over the cut face, if the first cell is the one
	chunk: ^Chunk
	held := [2]i32{max(i32), max(i32)}
	for {
		at := [2]i32{cell.x >> CHUNK_SHIFT, cell.z >> CHUNK_SHIFT}
		if at != held {
			held = at
			chunk = w.chunks[Key{0, at.x, at.y}] or_else nil
			if chunk != nil && !chunk.ready do chunk = nil
		}
		if chunk != nil {
			m := Mat.Air
			if ly := cell.y - chunk.y_base; ly < 0 do m = .Stone   // under the layers kept all is solid
			else if ly < chunk.h do m = chunk.blocks[int(cell.x & (CHUNK - 1) + 1) + int(cell.z & (CHUNK - 1) + 1)*P + int(ly)*P*P]
			if m != .Air && !(bare && is(m, LEAVES)) {
				p.block, p.ok, p.exact = cell, true, true
				return
			}
		}
		a := 0 if next.x < next.y && next.x < next.z else 1 if next.y < next.z else 2
		if next[a] > reach do return
		p.before = cell
		cell[a] += step[a]
		next[a] += delta[a]
	}
}

// Beyond the block volume the ground is the generator's columns: the top block of the column a ray
// comes down in, or of the cut where the ground stands over it. It asks the generator along the
// ray, so it is for a question now and then, not for every frame.
pick_far :: proc(eye: [3]f64, dir: [3]f32, level: f64) -> (p: Pick) {
	if dir.y >= 0 do return
	d := [3]f64{f64(dir.x), f64(dir.y), f64(dir.z)}
	t := max((eye.y - min(level, 1500))/-d.y, 0)   // no ground stands higher than that
	for ; t < 120000; t += max(1, 0.01*t) {
		at := eye + d*t
		top := min(f64(math.round(height_in_world(at.x, at.z, 1))), level)
		if at.y > top do continue
		p.block = {i32(math.floor(at.x)), i32(top) - 1, i32(math.floor(at.z))}
		p.before, p.ok = p.block + {0, 1, 0}, true
		return
	}
	return
}

// The box of blocks between two picked, as its low corner and its high one.
box_of :: proc(a, b: [3]i32) -> (lo, hi: [3]i32) {
	return {min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)}, {max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)}
}

// What a block of the world is made of: the volume's where it is loaded, edits and all, and
// otherwise the generator's ground, which knows no caves or trees.
block_made :: proc(w: ^World, b: [3]i32) -> Mat {
	f := island_at(f64(b.x) + 0.5, f64(b.z) + 0.5)
	was := here
	defer bind(was)
	if f != nil && is_formed(f) do bind(f)
	if c := w.chunks[Key{0, b.x >> CHUNK_SHIFT, b.z >> CHUNK_SHIFT}] or_else nil; c != nil && c.ready {
		ly := b.y - c.y_base
		k := int(b.x & (CHUNK - 1) + 1) + int(b.z & (CHUNK - 1) + 1)*P
		return .Air if ly >= c.h else c.blocks[k + int(ly)*P*P] if ly >= 0 else under_rock(c, k, b.y, f == nil)
	}
	if f == nil || !is_formed(f) do return .Sand if b.y < SEA_BED else .Air
	x, z := f64(b.x) - f64(region.origin.x) + 0.5, f64(b.z) - f64(region.origin.y) + 0.5
	g, m, _ := surface_at(x, z, 1)
	top := i32(math.round(g.h))
	return .Air if b.y >= top else m if b.y == top - 1 else crushed(rock_in(f32(b.y) + 0.5, g.under, 0), g.under)
}

// What why_block says of a block, as words for a panel to show: its lines are caught on their way to
// standard output. The first line is the block; the rest is what `--why=` prints.
@(thread_local) hearing: ^strings.Builder
stdout_before: ^os.File
stdout_heard:  os.File
why_words :: proc(w: ^World, b: [3]i32) -> string {
	if stdout_before == nil {
		stdout_before = os.stdout
		stdout_heard = stdout_before^
		stdout_heard.stream.procedure = proc(_: rawptr, mode: os.File_Stream_Mode, p: []byte, offset: i64, whence: io.Seek_From, a: runtime.Allocator) -> (i64, os.Error) {
			if hearing != nil && mode == .Write {
				strings.write_bytes(hearing, p)
				return i64(len(p)), nil
			}
			return stdout_before.stream.procedure(stdout_before.stream.data, mode, p, offset, whence, a)
		}
		os.stdout = &stdout_heard
	}
	words := strings.builder_make(context.temp_allocator)
	hearing = &words
	why_block(w, b)
	hearing = nil
	return strings.to_string(words)
}

// What a block is and why the ground it lies in is as it is: the block, then what `--why=` says of
// its column.
why_block :: proc(w: ^World, b: [3]i32) {
	f := island_at(f64(b.x) + 0.5, f64(b.z) + 0.5)
	if f == nil || !is_formed(f) {
		fmt.printfln("the block at %d, %d, %d m over the sea, lies in the open sea, off every island's ground", b.x, b.z, b.y)
		return
	}
	bound(f)
	m := block_made(w, b)
	top := i32(math.round(height_at(f64(b.x) - f64(region.origin.x) + 0.5, f64(b.z) - f64(region.origin.y) + 0.5, 1)))
	fmt.printf("the block at %d, %d, %d m over the sea, is %v", b.x, b.z, b.y, m)
	if b.y < top - 1 do fmt.printf(", %d m under the ground", top - 1 - b.y)
	else if b.y >= top do fmt.printf(", %d m over the ground", b.y - top + 1)
	fmt.println()
	why_at(f64(b.x), f64(b.z))
}
