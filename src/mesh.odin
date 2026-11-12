package main

// Meshing. Every visible face is one Quad, drawn as an instanced four-vertex strip, so a
// face costs 16 bytes. Coordinates are metres from the chunk origin.

Quad :: struct {
	x, y, z: i16,   // corner the quad grows from
	a:       i16,   // extent along the face's U axis
	b:       u16,   // extent along the face's V axis
	ao:      u16,   // light reaching each corner, four bits each, corner = u + 2v
	info:    u16,   // face (3 bits), turned diagonal (1 bit), material (high byte)
	slope:   [2]u8, // smooth ground normal for lighting, or zero to light by the face alone
}
#assert(size_of(Quad) == 16)

// Faces in the order +X -X +Y -Y +Z -Z, with axes chosen so that U x V points outward.
// The shader holds the same tables.
FACE_N := [6][3]i32{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}
FACE_U := [6][3]i32{{0, 1, 0}, {0, 0, 1}, {0, 0, 1}, {1, 0, 0}, {1, 0, 0}, {0, 1, 0}}
FACE_V := [6][3]i32{{0, 0, 1}, {0, 1, 0}, {1, 0, 0}, {0, 0, 1}, {0, 1, 0}, {1, 0, 0}}

OPEN :: [4]u16{15, 15, 15, 15}   // all four corners fully lit

quad :: proc(x, y, z, a, b: i32, face: int, m: Mat, corners: [4]u16, slope: [2]u8) -> Quad {
	// Split along the diagonal that joins the two brighter corners, or a single dark
	// corner smears across the whole face.
	flip := corners[1] + corners[2] < corners[0] + corners[3]
	ao := corners[0] | corners[1] << 4 | corners[2] << 8 | corners[3] << 12
	return {i16(x), i16(y), i16(z), i16(a), u16(b), ao, u16(face) | u16(flip) << 3 | u16(m) << 8, slope}
}

// ---- near: a true block volume ------------------------------------------------------------

// Blocks are stored for the chunk and its border, in layers from the bottom up. Below the
// stored layers everything is solid and above them everything is air.
solid :: #force_inline proc(blocks: []u8, h, x, y, z: i32) -> bool {
	if y < 0 do return true
	if y >= h do return false
	return blocks[(x + 1) + (z + 1)*P + y*P*P] != 0
}

mesh_volume :: proc(blocks: []u8, h: i32, c: ^Columns, out: ^[dynamic]Quad) {
	for y in 0..<h {
		for z in 0..<i32(CHUNK) {
			for x in 0..<i32(CHUNK) {
				m := Mat(blocks[(x + 1) + (z + 1)*P + y*P*P])
				if m == .Air do continue
				slope := c.slope[(z + 1)*P + x + 1] if m != .Wood && m != .Leaves else {}
				for f in 0..<6 {
					n := FACE_N[f]
					nx, ny, nz := x + n.x, y + n.y, z + n.z
					if solid(blocks, h, nx, ny, nz) {
						// A buried face on the chunk's rim is kept for four blocks below the
						// surface. The neighbour may be drawn at a coarser level whose ground
						// sits a little lower, and this closes the gap.
						rim := (f == 0 && x == CHUNK - 1) || (f == 1 && x == 0) || (f == 4 && z == CHUNK - 1) || (f == 5 && z == 0)
						if !rim || solid(blocks, h, nx, ny + 4, nz) do continue
					}
					// Corner light: count the blocks crowding each corner of the face.
					u, v := FACE_U[f], FACE_V[f]
					corners: [4]u16
					for c in 0..<4 {
						du: i32 = 1 if c & 1 == 1 else -1
						dv: i32 = 1 if c >= 2 else -1
						s1 := solid(blocks, h, nx + u.x*du, ny + u.y*du, nz + u.z*du)
						s2 := solid(blocks, h, nx + v.x*dv, ny + v.y*dv, nz + v.z*dv)
						sc := solid(blocks, h, nx + u.x*du + v.x*dv, ny + u.y*du + v.y*dv, nz + u.z*du + v.z*dv)
						corners[c] = 0 if s1 && s2 else u16(3 - int(s1) - int(s2) - int(sc))*5
					}
					append(out, quad(x + max(n.x, 0), y + max(n.y, 0), z + max(n.z, 0), 1, 1, f, m, corners, slope))
				}
			}
		}
	}
}

// ---- far: block columns -------------------------------------------------------------------

// One side of a box standing on a square w across with its corner at x, z: from y up h.
wall :: proc(out: ^[dynamic]Quad, x, z, w, y, h: i32, face: int, m: Mat, slope: [2]u8) {
	switch face {
	case 0: append(out, quad(x + w, y, z, h, w, 0, m, OPEN, slope))
	case 1: append(out, quad(x, y, z, w, h, 1, m, OPEN, slope))
	case 4: append(out, quad(x, y, z + w, w, h, 4, m, OPEN, slope))
	case 5: append(out, quad(x, y, z, h, w, 5, m, OPEN, slope))
	}
}

// Beyond the nearest ring the ground is drawn as columns: wide cells with heights still in
// whole metres, so a far hillside keeps the same share of tops and risers as a near one
// and takes the light the same way. Quads are grouped by quarter of the chunk, because a
// quarter is hidden when the finer chunk covering it is ready.
mesh_columns :: proc(c: ^Columns, s, y_base: i32, out: ^[dynamic]Quad, ranges: ^[4][2]u32) {
	HALF :: CHUNK/2
	top :: #force_inline proc(c: ^Columns, i, j: i32) -> i32 { return c.top[(j + 1)*P + i + 1] }
	// Light at the corners of a top face at height t: higher neighbours shade the corner they
	// stand at, in proportion to how far they rise, which matches the block rule at one metre.
	corners :: proc(c: ^Columns, i, j, t, s: i32, crowns: bool) -> (out: [4]u16) {
		at :: #force_inline proc(c: ^Columns, i, j: i32, crowns: bool) -> i32 { return c.crown[(j + 1)*P + i + 1][1] if crowns else c.top[(j + 1)*P + i + 1] }
		for k in 0..<4 {
			dz: i32 = 1 if k & 1 == 1 else -1
			dx: i32 = 1 if k >= 2 else -1
			rise := clamp(f32(at(c, i, j + dz, crowns) - t)/f32(s), 0, 1) +
			        clamp(f32(at(c, i + dx, j, crowns) - t)/f32(s), 0, 1) +
			        clamp(f32(at(c, i + dx, j + dz, crowns) - t)/f32(s), 0, 1)
			out[k] = u16(15*(1 - rise/3) + 0.5)
		}
		return
	}
	level := rock_level(f64(s))   // which merging of the beds this cell size reads

	for q in 0..<4 {
		x0, z0 := i32(q & 1)*HALF, i32(q >> 1)*HALF
		start := u32(len(out))
		for j in z0..<z0 + HALF {
			for i in x0..<x0 + HALF {
				t := top(c, i, j)
				m := c.mat[(j + 1)*P + i + 1]
				slope := c.slope[(j + 1)*P + i + 1]

				append(out, quad(i*s, t - y_base, j*s, s, s, 2, m, corners(c, i, j, t, s, false), slope))

				// Risers down to each lower neighbour. On the edge of a quarter the riser runs
				// to two cells below the ground, because what lies beyond may be drawn at another
				// level: lower ground, or open air around a trunk where this level has a
				// solid crown.
				sides := [4][3]i32{{1, 0, 0}, {-1, 0, 1}, {0, 1, 4}, {0, -1, 5}}
				for side in sides {
					n := top(c, i + side.x, j + side.y)
					bottom := n
					edge := (side.x == 1 && i == x0 + HALF - 1) || (side.x == -1 && i == x0) ||
					        (side.y == 1 && j == z0 + HALF - 1) || (side.y == -1 && j == z0)
					if edge do bottom = min(c.ground[(j + side.y + 1)*P + i + side.x + 1], c.ground[(j + 1)*P + i + 1]) - 2*s
					// A riser too steep to hold soil, or cut in bare rock, shows the beds at
					// their heights, as the blocks of a face do near by. Under a canopy that is
					// the riser of the ground it stands on: a face below a wood is rock, not leaves.
					ground := c.ground[(j + 1)*P + i + 1]
					bare := ground - c.ground[(j + side.y + 1)*P + i + side.x + 1] > s + s/4 || MATERIALS[m].strength > 0
					for at := bottom; at < t; {
						wall_of, drop := m, t - at
						if bare && at < ground {
							wall_of, drop = rock_in(f32(at) + 0.5, c.base[(j + 1)*P + i + 1], level), 1
							for at + drop < ground && rock_in(f32(at + drop) + 0.5, c.base[(j + 1)*P + i + 1], level) == wall_of do drop += 1
						}
						wall(out, i*s, j*s, s, at - y_base, drop, int(side.z), wall_of, slope)
						at += drop
					}
				}

				// A single tree's crown hangs over the ground as a box of leaves, open to the air
				// beneath it, on a trunk a metre wide. Its sides show wherever the crown beside it
				// does not cover them, and whole on the edge of a quarter, where what lies beyond
				// may be drawn at another level.
				k := (j + 1)*P + i + 1
				under, over := c.crown[k][0], c.crown[k][1]
				if over <= under do continue
				if c.stem[k] > 0 && under > t {
					for face in ([4]int{0, 1, 4, 5}) do wall(out, i*s + i32(c.stem[k] - 1)%4, j*s + i32(c.stem[k] - 1)/4, 1, t - y_base, under - t, face, .Wood, {})
				}
				append(out, quad(i*s, over - y_base, j*s, s, s, 2, .Leaves, corners(c, i, j, over, s, true), {}))
				if under > t do append(out, quad(i*s, under - y_base, j*s, s, s, 3, .Leaves, OPEN, {}))
				for side in sides {
					beside := c.crown[(j + side.y + 1)*P + i + side.x + 1]
					edge := (side.x == 1 && i == x0 + HALF - 1) || (side.x == -1 && i == x0) ||
					        (side.y == 1 && j == z0 + HALF - 1) || (side.y == -1 && j == z0)
					if edge || beside[1] <= beside[0] do beside = {over, over}   // nothing beside it covers it
					if low := min(beside[0], over); low > under do wall(out, i*s, j*s, s, under - y_base, low - under, int(side.z), .Leaves, {})
					if high := max(beside[1], under); high < over do wall(out, i*s, j*s, s, high - y_base, over - high, int(side.z), .Leaves, {})
				}
			}
		}
		ranges[q] = {start, u32(len(out)) - start}
	}
}
