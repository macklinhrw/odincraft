package main

import "core:c"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sys/posix"

// A landmass's coarse stage as it is kept and read (step 21, second part): its file in
// build/worlds/, mapped into memory, so that the game holds of it only what it reads. The lattice
// is kept by squares of SQUARE cells: those with land in them or within KEPT_RING of one. The
// open sea beyond is kept nowhere, and reads as the shelf's floor. With the cells, the cut: each
// cell's piece, and what is known of each piece (continents.odin).

KEPT_MAGIC   :: 0x4b434f31   // "1OCK"
KEPT_VERSION :: 4
KEPT_RING    :: 2            // squares kept round any with land: 8 km, past a piece's margin
KEPT_CELLS   :: SQUARE*SQUARE
NEXT_NONE    :: 255          // a land cell that drains into the sea,
NEXT_SEA     :: 254          // and a cell of the sea; else the way a land cell drains, as its place in OFFSETS

Kept_Head :: struct { magic, version: u32, n, m, squares, shores, pieces, pairs: i32, left, lift, rise: f32, pad: i32 }
Kept_Piece :: struct { down, depth, rank, size: i32, box: [4]i32, window: [3]i32, pad: i32 }

Store :: struct {
	n, m:   int,
	file:   []u8,                  // the file, mapped
	slot:   []i32,                 // each square's place among those kept, or -1: open sea
	shore:  []i32,                 // each square's place among those whose shore the sea has cut, or -1: no cell cut, every face 1
	z, area, load: [][KEPT_CELLS]f32,
	next:   [][KEPT_CELLS]u8,
	owner:  [][KEPT_CELLS]i16,     // each cell's piece, or -1
	cut, face: [][KEPT_CELLS]f32,
	now:    [][KEPT_CELLS]f32,     // the ground as the coarse stage run on to today leaves it, over today's sea (coarse_today)
	pieces: []Kept_Piece,
	pairs:  [][2]i32,              // the pieces beside each other
	left, lift, rise: f32,         // the grid's, as the coarse stage left them
}

// Write a coarse stage's grid and its cut, as the pieces take it up: all of it but the ground as it
// stands today, which store_today adds once the grid has been run on, and which makes the file whole.
// `own` is each cell's piece and 1, or 0. Returns where it is being written, or "" if it could not be.
store_write :: proc(path: string, g: ^Grid, cut: ^Cut, own: []i32) -> (temp: string) {
	n, m := g.n, g.n/SQUARE
	has := make([]bool, m*m)
	defer delete(has)
	Has :: struct { g: ^Grid, has: []bool }
	hs := Has{g, has}
	over(g, &hs, proc(hs: ^Has, g: ^Grid, ty, y, x0, x1: int) {
		#no_bounds_check for x in x0..<x1 do if !g.sea[y*g.n + x] do hs.has[ty*(g.n/SQUARE) + x/SQUARE] = true
	})
	slot, shore := make([]i32, m*m), make([]i32, m*m)
	defer { delete(slot); delete(shore) }
	squares := make([dynamic]i32)
	shores := make([dynamic]i32)
	defer { delete(squares); delete(shores) }
	for t in 0..<m*m {
		slot[t], shore[t] = -1, -1
		near := false
		for j in max(t/m - KEPT_RING, 0)..=min(t/m + KEPT_RING, m - 1) do for i in max(t%m - KEPT_RING, 0)..=min(t%m + KEPT_RING, m - 1) do near ||= has[j*m + i]
		if !near do continue
		slot[t] = i32(len(squares))
		append(&squares, i32(t))
		cut_here := false
		#no_bounds_check for j in 0..<SQUARE do for i in 0..<SQUARE {
			k := (t/m*SQUARE + j)*n + t%m*SQUARE + i
			cut_here ||= g.cut[k] != 0 || g.face[k] != 1
		}
		if cut_here {
			shore[t] = i32(len(shores))
			append(&shores, i32(t))
		}
	}
	pairs := make([dynamic][2]i32)
	defer delete(pairs)
	for l, p in cut.near do for q in l do if i32(p) < q do append(&pairs, [2]i32{i32(p), q})
	head := Kept_Head{magic = KEPT_MAGIC, version = KEPT_VERSION, n = i32(n), m = i32(m), squares = i32(len(squares)), shores = i32(len(shores)), pieces = i32(len(cut.size)), pairs = i32(len(pairs)), left = g.left, lift = g.lift, rise = g.rise}
	temp = fmt.aprintf("%s.%d", path, posix.getpid())
	fd := posix.open(strings.clone_to_cstring(temp, context.temp_allocator), {.WRONLY, .CREAT, .TRUNC}, transmute(posix.mode_t)posix.mode_t{.IRUSR, .IWUSR, .IRGRP, .IROTH})
	if fd < 0 do return ""
	ok := true
	put(fd, mem.ptr_to_bytes(&head), &ok)
	put(fd, slice.to_bytes(slot), &ok)
	put(fd, slice.to_bytes(shore), &ok)
	for p in 0..<len(cut.size) {
		w := cut.window[p]
		kp := Kept_Piece{down = cut.down[p], depth = cut.depth[p], rank = cut.rank[p], size = cut.size[p], box = cut.box[p], window = w}
		put(fd, mem.ptr_to_bytes(&kp), &ok)
	}
	put(fd, slice.to_bytes(pairs[:]), &ok)
	// Each kind of value, square after square.
	Plane :: enum { Z, Area, Load, Next, Owner, Cut, Face }
	buf := make([]u8, KEPT_CELLS*4)
	defer delete(buf)
	ways := OFFSETS
	for plane in Plane {
		list := shores[:] if plane == .Cut || plane == .Face else squares[:]
		for t in list {
			f := slice.reinterpret([]f32, buf)
			#no_bounds_check for j in 0..<SQUARE do for i in 0..<SQUARE {
				k, q := (int(t)/m*SQUARE + j)*n + int(t)%m*SQUARE + i, j*SQUARE + i
				started := g.coarse == nil || g.coarse.ready[t]
				switch plane {
				case .Z:     f[q] = g.z[k] if started else MASS_SHELF
				case .Area:  f[q] = g.area[k] if started && !g.sea[k] else 0
				case .Load:  f[q] = g.load[k] if started && !g.sea[k] else 0
				case .Cut:   f[q] = g.cut[k]
				case .Face:  f[q] = g.face[k]
				case .Owner: slice.reinterpret([]i16, buf)[q] = i16(own[k] - 1) if started else -1
				case .Next:
					code := u8(NEXT_SEA)
					if started && !g.sea[k] {
						code = NEXT_NONE
						if r := int(g.next[k]); r >= 0 do for o, w in ways do if k + o.y*n + o.x == r do code = u8(w)
					}
					buf[q] = code
				}
			}
			put(fd, buf[:KEPT_CELLS*(1 if plane == .Next else 2 if plane == .Owner else 4)], &ok)
		}
	}
	posix.close(fd)
	if !ok {
		posix.unlink(strings.clone_to_cstring(temp, context.temp_allocator))
		return ""
	}
	return
}

@(private="file")
put :: proc(fd: posix.FD, data: []u8, ok: ^bool) {
	data := data
	for len(data) > 0 && ok^ {
		wrote := posix.write(fd, raw_data(data), c.size_t(min(len(data), 1 << 28)))
		if wrote <= 0 {
			ok^ = false
			return
		}
		data = data[wrote:]
	}
}

// Add the ground as it stands today to a coarse stage being written (store_write), the grid having
// been run on to today, and put the file in its place. With `g` nil the file is let go instead.
store_today :: proc(temp, path: string, g: ^Grid) -> bool {
	name := strings.clone_to_cstring(temp, context.temp_allocator)
	defer delete(temp)
	if g == nil {
		posix.unlink(name)
		return false
	}
	// The squares kept, in the order the file has them.
	fd := posix.open(name, {})
	if fd < 0 do return false
	head: Kept_Head
	m := g.n/SQUARE
	slot := make([]i32, m*m)
	defer delete(slot)
	ok := posix.read(fd, ([^]u8)(&head), size_of(head)) == size_of(head) && posix.read(fd, ([^]u8)(raw_data(slot)), c.size_t(m*m*4)) == m*m*4
	posix.close(fd)
	if !ok do return false
	squares := make([]i32, head.squares)
	defer delete(squares)
	for at, t in slot do if at >= 0 do squares[at] = i32(t)
	fd = posix.open(name, {.WRONLY, .APPEND})
	if fd < 0 do return false
	buf := make([]f32, KEPT_CELLS)
	defer delete(buf)
	for t in squares {
		started := g.coarse == nil || g.coarse.ready[t]
		#no_bounds_check for j in 0..<SQUARE do for i in 0..<SQUARE do buf[j*SQUARE + i] = g.z[(int(t)/m*SQUARE + j)*g.n + int(t)%m*SQUARE + i] if started else MASS_SHELF
		put(fd, slice.to_bytes(buf), &ok)
	}
	posix.close(fd)
	if ok do ok = posix.rename(name, strings.clone_to_cstring(path, context.temp_allocator)) == 0
	if !ok do posix.unlink(name)
	return ok
}

// Map a kept coarse stage; false if there is none that fits a lattice of n cells.
store_open :: proc(st: ^Store, path: string, n: int) -> bool {
	fd := posix.open(strings.clone_to_cstring(path, context.temp_allocator), {})
	if fd < 0 do return false
	defer posix.close(fd)
	info: posix.stat_t
	if posix.fstat(fd, &info) != .OK || info.st_size < size_of(Kept_Head) do return false
	at := posix.mmap(nil, c.size_t(info.st_size), {.READ}, {.PRIVATE}, fd, 0)
	if at == posix.MAP_FAILED do return false
	file := slice.from_ptr((^u8)(at), int(info.st_size))
	head := (^Kept_Head)(at)^
	m := int(head.m)
	size := size_of(Kept_Head) + 2*m*m*4 + int(head.pieces)*size_of(Kept_Piece) + int(head.pairs)*8 + int(head.squares)*KEPT_CELLS*(4*4 + 1 + 2) + int(head.shores)*KEPT_CELLS*8
	if head.magic != KEPT_MAGIC || head.version != KEPT_VERSION || int(head.n) != n || size != len(file) {
		posix.munmap(at, c.size_t(info.st_size))
		return false
	}
	st^ = {n = n, m = m, file = file, left = head.left, lift = head.lift, rise = head.rise}
	k := size_of(Kept_Head)
	take :: proc(file: []u8, k: ^int, $T: typeid, count: int) -> []T {
		defer k^ += count*size_of(T)
		return slice.from_ptr((^T)(&file[k^]) if count > 0 else nil, count)
	}
	st.slot, st.shore = take(file, &k, i32, m*m), take(file, &k, i32, m*m)
	st.pieces, st.pairs = take(file, &k, Kept_Piece, int(head.pieces)), take(file, &k, [2]i32, int(head.pairs))
	s := int(head.squares)
	st.z, st.area, st.load = take(file, &k, [KEPT_CELLS]f32, s), take(file, &k, [KEPT_CELLS]f32, s), take(file, &k, [KEPT_CELLS]f32, s)
	st.next, st.owner = take(file, &k, [KEPT_CELLS]u8, s), take(file, &k, [KEPT_CELLS]i16, s)
	st.cut, st.face = take(file, &k, [KEPT_CELLS]f32, int(head.shores)), take(file, &k, [KEPT_CELLS]f32, int(head.shores))
	st.now = take(file, &k, [KEPT_CELLS]f32, s)
	return true
}

// Let go of a coarse stage that was opened: the file is no longer mapped.
store_close :: proc(st: ^Store) {
	if len(st.file) > 0 do posix.munmap(raw_data(st.file), c.size_t(len(st.file)))
	st^ = {}
}

// A cell's square among those kept, or -1, and its place in the square.
store_at :: #force_inline proc(st: ^Store, i, j: int) -> (slot, k: int) #no_bounds_check {
	if i < 0 || j < 0 || i >= st.n || j >= st.n do return -1, 0
	return int(st.slot[j/SQUARE*st.m + i/SQUARE]), j%SQUARE*SQUARE + i%SQUARE
}

// The coarse stage's ground at a cell of its lattice; the shelf's floor in the open sea off it.
store_z :: proc(st: ^Store, i, j: int) -> f32 #no_bounds_check {
	slot, k := store_at(st, i, j)
	return st.z[slot][k] if slot >= 0 else MASS_SHELF
}

// The land a cell of the coarse stage drains, m²; none in the sea.
store_area :: proc(st: ^Store, i, j: int) -> f32 #no_bounds_check {
	slot, k := store_at(st, i, j)
	return st.area[slot][k] if slot >= 0 && st.next[slot][k] != NEXT_SEA else 0
}

// The piece a cell is of, or -1.
store_owner :: proc(st: ^Store, i, j: int) -> int #no_bounds_check {
	slot, k := store_at(st, i, j)
	return int(st.owner[slot][k]) if slot >= 0 else -1
}

// A window of the coarse stage as a grid of its own, as the pieces read it: the ground, the sea, the
// shore's cut and faces, the rock carried, the land drained and where each cell drains, with each
// cell's piece. Its region is bound.
store_window :: proc(st: ^Store, lo: [2]int, side: int) -> (g: ^Grid, owner: []i32) {
	g = grid_make_empty(side, {lo.x, lo.y, st.n})
	owner = make([]i32, side*side)
	ways := OFFSETS
	#no_bounds_check for j in 0..<side do for i in 0..<side {
		q := j*side + i
		slot, k := store_at(st, lo.x + i, lo.y + j)
		g.face[q], g.next[q], owner[q] = 1, -1, -1
		if slot < 0 {
			g.z[q], g.sea[q] = MASS_SHELF, true
			continue
		}
		g.z[q], g.area[q], g.load[q], owner[q] = st.z[slot][k], st.area[slot][k], st.load[slot][k], i32(st.owner[slot][k])
		code := st.next[slot][k]
		g.sea[q] = code == NEXT_SEA
		if code < 8 do if x, y := i + ways[code].x, j + ways[code].y; x >= 0 && y >= 0 && x < side && y < side do g.next[q] = i32(y*side + x)
		if sh := st.shore[(lo.y + j)/SQUARE*st.m + (lo.x + i)/SQUARE]; sh >= 0 do g.cut[q], g.face[q] = st.cut[sh][k], st.face[sh][k]
	}
	g.left, g.lift, g.rise = st.left, st.lift, st.rise
	return
}

// The ground at a cell of the lattice as the coarse stage run on to today leaves it, over today's sea;
// the shelf's floor in the open sea off it.
store_now :: proc(st: ^Store, i, j: int) -> f32 #no_bounds_check {
	slot, k := store_at(st, i, j)
	return st.now[slot][k] if slot >= 0 else MASS_SHELF
}
