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

// Beyond the nearest ring the ground is drawn as columns: wide cells with heights still in
// whole metres, so a far hillside keeps the same share of tops and risers as a near one
// and takes the light the same way. Quads are grouped by quarter of the chunk, because a
// quarter is hidden when the finer chunk covering it is ready.
mesh_columns :: proc(c: ^Columns, s, y_base: i32, out: ^[dynamic]Quad, ranges: ^[4][2]u32) {
	HALF :: CHUNK/2
	top :: #force_inline proc(c: ^Columns, i, j: i32) -> i32 { return c.top[(j + 1)*P + i + 1] }
	level := 0   // which merging of the beds this cell size reads
	for i32(1) << uint(level) < s do level += 1

	for q in 0..<4 {
		x0, z0 := i32(q & 1)*HALF, i32(q >> 1)*HALF
		start := u32(len(out))
		for j in z0..<z0 + HALF {
			for i in x0..<x0 + HALF {
				t := top(c, i, j)
				m := c.mat[(j + 1)*P + i + 1]
				slope := c.slope[(j + 1)*P + i + 1]

				// Top face. Higher neighbours shade the corner they stand at, in proportion
				// to how far they rise, which matches the block rule at one metre.
				corners: [4]u16
				for k in 0..<4 {
					dz: i32 = 1 if k & 1 == 1 else -1
					dx: i32 = 1 if k >= 2 else -1
					rise := clamp(f32(top(c, i, j + dz) - t)/f32(s), 0, 1) +
					        clamp(f32(top(c, i + dx, j) - t)/f32(s), 0, 1) +
					        clamp(f32(top(c, i + dx, j + dz) - t)/f32(s), 0, 1)
					corners[k] = u16(15*(1 - rise/3) + 0.5)
				}
				append(out, quad(i*s, t - y_base, j*s, s, s, 2, m, corners, slope))

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
					// their heights, as the blocks of a face do near by.
					bare := m != .Leaves && (t - n > s + s/4 || MATERIALS[m].strength > 0)
					for at := bottom; at < t; {
						wall, drop := m, t - at
						if bare {
							wall, drop = rock_in(f32(at) + 0.5, c.base[(j + 1)*P + i + 1], level), 1
							for at + drop < t && rock_in(f32(at + drop) + 0.5, c.base[(j + 1)*P + i + 1], level) == wall do drop += 1
						}
						y := at - y_base
						switch side.z {
						case 0: append(out, quad((i + 1)*s, y, j*s, drop, s, 0, wall, OPEN, slope))
						case 1: append(out, quad(i*s, y, j*s, s, drop, 1, wall, OPEN, slope))
						case 4: append(out, quad(i*s, y, (j + 1)*s, s, drop, 4, wall, OPEN, slope))
						case 5: append(out, quad(i*s, y, j*s, drop, s, 5, wall, OPEN, slope))
						}
						at += drop
					}
				}
			}
		}
		ranges[q] = {start, u32(len(out)) - start}
	}
}
