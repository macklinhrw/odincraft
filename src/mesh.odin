package main

import "core:math"

// Meshing. Every visible face is one Quad, drawn as an instanced four-vertex strip, so a
// face costs 20 bytes. Coordinates are metres from the chunk origin.

Quad :: struct {
	x, y, z: i16,   // corner the quad grows from
	a:       i16,   // extent along the face's U axis
	b:       u16,   // extent along the face's V axis
	ao:      u16,   // light reaching each corner, four bits each, corner = u + 2v
	info:    u16,   // face (3 bits), turned diagonal (1 bit), the sky it sees (4 bits); the high byte is spare
	slope:   [2]u8, // smooth ground normal for lighting, or zero to light by the face alone
	mat:     Mat,   // what it is made of: its tiles in the atlas
	_:       u16,   // spare: the GPU reads a quad in steps of four bytes
}
#assert(size_of(Quad) == 20 && size_of(Mat) == 2)   // as the shader reads it (QuadIn, shaders.metal; make_pipeline, render.odin)

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
	return {i16(x), i16(y), i16(z), i16(a), u16(b), ao, u16(face) | u16(flip) << 3, slope, m, 0}
}

// A chunk's quads are stored by the way they face, +X to -Z, and within that by part: the quarters
// of a far chunk, or at the nearest level the solid faces, the crowns' outer faces and the faces
// within them. A draw can then leave out every face turned from the eye, or from the sun, before
// any is shaded. `parts` is where each part lies in `quads` as meshed; the result says where each
// part of each facing lies once sorted, in place.
by_face :: proc(quads: []Quad, parts: [4][2]u32) -> (ranges: [6][4][2]u32) {
	at := u32(0)
	for p in 0..<4 do for q in quads[parts[p][0]:][:parts[p][1]] do ranges[q.info & 7][p][1] += 1
	for f in 0..<6 do for p in 0..<4 {
		ranges[f][p][0] = at
		at += ranges[f][p][1]
	}
	meshed := make([]Quad, len(quads), context.temp_allocator)
	copy(meshed, quads)
	next := ranges
	for p in 0..<4 do for q in meshed[parts[p][0]:][:parts[p][1]] {
		f := q.info & 7
		quads[next[f][p][0]] = q
		next[f][p][0] += 1
	}
	return
}

// ---- near: a true block volume ------------------------------------------------------------

// Blocks are stored for the chunk and its border, in layers from the bottom up. Below the
// stored layers everything is solid and above them everything is air.
solid :: #force_inline proc(blocks: []Mat, h, x, y, z: i32) -> bool {
	if y < 0 do return true
	if y >= h do return false
	return blocks[(x + 1) + (z + 1)*P + y*P*P] != .Air
}

// The share of the sky a block of air under a roof sees (ground-and-underground.md, D4): of
// thirteen rays across the sky, weighted toward the way a face looks, those that come out above
// the ground before they meet rock, the low ones bringing the light of the lit world outside.
// The eye takes it as brighter than that share, so the face is lit by its square root. Beyond the chunk a hollow's outline answers, and elsewhere
// a ray is taken to have come out. `at` is the block (0, 0, 0) relative to the region's middle.
SKY_RAYS :: [13][3]f32{{0.99, 0.14, 0}, {0.70, 0.14, 0.70}, {0, 0.14, 0.99}, {-0.70, 0.14, 0.70}, {-0.99, 0.14, 0}, {-0.70, 0.14, -0.70}, {0, 0.14, -0.99}, {0.70, 0.14, -0.70},
	{0.45, 0.77, 0.45}, {-0.45, 0.77, 0.45}, {-0.45, 0.77, -0.45}, {0.45, 0.77, -0.45}, {0, 1, 0}}
sky_seen :: proc(blocks: []Mat, h: i32, cover: ^[P*P]i32, at: [3]i32, x, y, z: i32, n: [3]i32) -> f32 {
	seen, all: f32
	for d in SKY_RAYS {
		w := max(d.x*f32(n.x) + d.y*f32(n.y) + d.z*f32(n.z), 0) + 0.1
		all += w
		for i in 1..=40 {
			p := [3]f32{f32(x) + 0.5, f32(y) + 0.5, f32(z) + 0.5} + d*f32(i)*0.75
			u, v, t := i32(math.floor(p.x)), i32(math.floor(p.y)), i32(math.floor(p.z))
			if u >= -1 && t >= -1 && u <= CHUNK && t <= CHUNK {
				if v > cover[(u + 1) + (t + 1)*P] { seen += w; break }
				if solid(blocks, h, u, v, t) && !is(blocks[(u + 1) + (t + 1)*P + v*P*P], PLANT_BLOCKS) do break
			} else if rock, known := hollow_rock(at.x + u, at.y + v, at.z + t); rock do break
			else if !known { seen += w; break }
		}
	}
	return seen/all
}

// Bark has a grain, and which way it runs is read from the blocks round it, so a trunk the player
// cuts or lays shows it as one the world grew does. A standing trunk shows its rings on top where
// it is cut across, unless a limb leaves it there. A block of bark on the ground
// with none of its own over it lies: its ends show the rings, its sides the bark turned to run
// along it and its top the moss a fallen trunk wears; one alone is a stump. Limbs in the air are
// bark all round.
GRAIN := #partial [Mat][2]Mat{.Wood = {.Wood_End, .Wood_Across}, .Shii_Bark = {.Shii_End, .Shii_Across}, .Grey_Bark = {.Grey_End, .Grey_Across}, .Pine_Bark = {.Pine_End, .Pine_Across}}
grain :: proc(blocks: []Mat, h, x, y, z: i32, n: [3]i32, m: Mat) -> Mat {
	same :: proc(blocks: []Mat, h, x, y, z: i32, m: Mat) -> bool {
		return y >= 0 && y < h && x >= -1 && x <= CHUNK && z >= -1 && z <= CHUNK && blocks[(x + 1) + (z + 1)*P + y*P*P] == m
	}
	beside :: proc(blocks: []Mat, h, x, y, z: i32, m: Mat) -> bool {
		return same(blocks, h, x + 1, y, z, m) || same(blocks, h, x - 1, y, z, m) || same(blocks, h, x, y, z + 1, m) || same(blocks, h, x, y, z - 1, m)
	}
	below, above, joined := same(blocks, h, x, y - 1, z, m), same(blocks, h, x, y + 1, z, m), beside(blocks, h, x, y, z, m)
	lying := !above && solid(blocks, h, x, y - 1, z) && !is(blocks[(x + 1) + (z + 1)*P + max(y - 1, 0)*P*P], PLANT_BLOCKS)   // on the ground with none of its own over it
	switch {
	case n.y > 0 && lying:                    return .Grass if joined else GRAIN[m][0]   // moss on a lying trunk, the rings of a stump
	case n.y > 0:                             return GRAIN[m][0] if below && !joined && !(y + 1 < h && is(blocks[(x + 1) + (z + 1)*P + (y + 1)*P*P], LEAVES)) else m   // not under leaves, where the stem goes on as twigs
	case n.y < 0:                             return m   // a limb's underside, far more often than a trunk cut from beneath
	case !lying:                              return m
	case same(blocks, h, x - n.x, y, z - n.z, m): return GRAIN[m][0]
	case same(blocks, h, x + n.z, y, z + n.x, m) || same(blocks, h, x - n.z, y, z - n.x, m): return GRAIN[m][1]
	}
	return m
}

// A column's ground plant (plants.odin) stands on the top face of its ground where that block is
// still the one the plant grows on and air is over it, so digging, building or a tree takes it away.
// Leaves are seen through: the gaps in their tiles are clear (fs_terrain), and each block of
// leaves shows behind the one in front, with the limbs among them. A crown's outer faces come
// after the solid faces in `out`, and after those the faces where two blocks of leaves meet, one
// for each pair, seen from both sides and dim, as the inside of a crown is; how many of each is
// returned, for the renderer to draw them apart.
mesh_volume :: proc(blocks: []Mat, h: i32, c: ^Columns, out, plants: ^[dynamic]Quad, at: [3]i32) -> (outer, inner: u32) {
	leaf :: proc(blocks: []Mat, h, x, y, z: i32) -> bool { return y >= 0 && y < h && is(blocks[(x + 1) + (z + 1)*P + y*P*P], LEAVES) }
	leaves, within := make([dynamic]Quad, context.temp_allocator), make([dynamic]Quad, context.temp_allocator)
	cover: [P*P]i32   // the highest block in each column that is not part of a plant
	for k in 0..<P*P {
		cover[k] = h - 1
		for cover[k] >= 0 && (blocks[k + int(cover[k])*P*P] == .Air || is(blocks[k + int(cover[k])*P*P], PLANT_BLOCKS)) do cover[k] -= 1
	}
	for y in 0..<h {
		for z in 0..<i32(CHUNK) {
			for x in 0..<i32(CHUNK) {
				m := blocks[(x + 1) + (z + 1)*P + y*P*P]
				if m == .Air do continue
				slope := c.slope[(z + 1)*P + x + 1] if !is(m, PLANT_BLOCKS) else {}
				if is(m, LEAVES) do for f in ([3]int{0, 2, 4}) {
					n := FACE_N[f]
					if leaf(blocks, h, x + n.x, y + n.y, z + n.z) do append(&within, quad(x + n.x, y + n.y, z + n.z, 1, 1, f, m, {6, 6, 6, 6}, {}))
				}
				for f in 0..<6 {
					n := FACE_N[f]
					nx, ny, nz := x + n.x, y + n.y, z + n.z
					if solid(blocks, h, nx, ny, nz) && (is(m, LEAVES) || !leaf(blocks, h, nx, ny, nz)) {   // a limb shows through the leaves round it
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
					// Under a roof a face is lit by its own direction and by the share of the sky it sees.
					closed: u16
					if !solid(blocks, h, nx, ny, nz) && ny < cover[(nx + 1) + (nz + 1)*P] {
						closed = u16(math.round(13*(1 - math.sqrt(sky_seen(blocks, h, &cover, at, nx, ny, nz, n)))))   // light the walls throw keeps the deepest from black
						slope = {}
					}
					q := quad(x + max(n.x, 0), y + max(n.y, 0), z + max(n.z, 0), 1, 1, f, grain(blocks, h, x, y, z, n, m) if GRAIN[m] != {} else m, corners, slope)
					q.info |= closed << 4
					append(&leaves if is(m, LEAVES) else out, q)
					if k := (z + 1)*P + x + 1; f == 2 && c.plant[k] > 0 && at.y + y == c.top[k] - 1 {
						row := GROUND_PLANTS[Plant_Kind(c.plant[k] - 1)]
						if is(m, row.on) && (!row.tall || !solid(blocks, h, x, y + 2, z)) {
							append(plants, plant_quad(x, y + 1, z, Plant_Kind(c.plant[k] - 1), at.x + x, at.z + z, (corners[0] + corners[1] + corners[2] + corners[3])/4 | closed << 4, slope))
						}
					}
				}
			}
		}
	}
	append(out, ..leaves[:])
	append(out, ..within[:])
	return u32(len(leaves)), u32(len(within))
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
			last := -1   // the top before this one in the row
			for i in x0..<x0 + HALF {
				t := top(c, i, j)
				m := c.mat[(j + 1)*P + i + 1]
				slope := c.slope[(j + 1)*P + i + 1]
				if s > COARSE && t < SEA_LEVEL do continue   // that far off nothing shows through the sea (fs_water), so open sea is no faces at all

				// A top level with the one before it, of the same stuff, slope and full light, lengthens that
				// one, which draws the same: open sea floor and flat ground cost a face a row, not one a cell.
				q := quad(i*s, t - y_base, j*s, s, s, 2, m, corners(c, i, j, t, s, false), slope)
				if l := last; l >= 0 && q.ao == 0xFFFF && out[l].ao == q.ao && out[l].y == q.y && out[l].info == q.info && out[l].mat == q.mat && out[l].slope == q.slope {
					out[l].b += u16(s)
				} else {
					last = len(out)
					append(out, q)
				}

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
							wall_of, drop = rock_in(f32(at) + 0.5, c.under[(j + 1)*P + i + 1], level), 1
							for at + drop < ground && rock_in(f32(at + drop) + 0.5, c.under[(j + 1)*P + i + 1], level) == wall_of do drop += 1
						}
						// A hollow's mouth on the face is drawn dark from afar (events.odin).
						mouth := c.hollow[(j + 1)*P + i + 1]
						if mouth[1] > mouth[0] && at < mouth[1] do drop = min(drop, mouth[0] - at if at < mouth[0] else mouth[1] - at)
						wall(out, i*s, j*s, s, at - y_base, drop, int(side.z), wall_of, slope)
						if mouth[1] > mouth[0] && at >= mouth[0] && at < mouth[1] do out[len(out) - 1].info |= 11 << 4
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
				tree := SPECIES[c.kind[k]]
				if c.stem[k] > 0 && under > t {
					for face in ([4]int{0, 1, 4, 5}) do wall(out, i*s + i32(c.stem[k] - 1)%4, j*s + i32(c.stem[k] - 1)/4, 1, t - y_base, under - t, face, tree.bark, {})
				}
				append(out, quad(i*s, over - y_base, j*s, s, s, 2, tree.leaf, corners(c, i, j, over, s, true), {}))
				if under > t do append(out, quad(i*s, under - y_base, j*s, s, s, 3, tree.leaf, OPEN, {}))
				for side in sides {
					beside := c.crown[(j + side.y + 1)*P + i + side.x + 1]
					edge := (side.x == 1 && i == x0 + HALF - 1) || (side.x == -1 && i == x0) ||
					        (side.y == 1 && j == z0 + HALF - 1) || (side.y == -1 && j == z0)
					if edge || beside[1] <= beside[0] do beside = {over, over}   // nothing beside it covers it
					if low := min(beside[0], over); low > under do wall(out, i*s, j*s, s, under - y_base, low - under, int(side.z), tree.leaf, {})
					if high := max(beside[1], under); high < over do wall(out, i*s, j*s, s, high - y_base, over - high, int(side.z), tree.leaf, {})
				}
			}
		}
		ranges[q] = {start, u32(len(out)) - start}
	}
}
