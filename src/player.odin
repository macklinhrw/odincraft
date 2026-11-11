package main

import "core:math"

// The player: a box that walks on blocks or flies through them.

Player :: struct {
	pos:      [3]f64,   // centre of the feet
	vel:      [3]f64,
	yaw:      f32,      // radians; 0 looks along -Z, positive turns right
	pitch:    f32,
	fly:      bool,
	grounded: bool,
	eye:      f64,      // eye height above the feet, eased so steps do not jolt the view
}

HALF_WIDTH :: 0.3
BODY       :: 1.8
EYE        :: 1.62
REACH      :: 7.0

look_dir :: proc(yaw, pitch: f32) -> [3]f32 {
	return {math.cos(pitch)*math.sin(yaw), math.sin(pitch), -math.cos(pitch)*math.cos(yaw)}
}

// What the player's box overlaps at a position: a solid block, or ground not loaded yet.
overlap :: proc(w: ^World, p: [3]f64) -> (solid, unloaded: bool) {
	x0, x1 := i32(math.floor(p.x - HALF_WIDTH)), i32(math.floor(p.x + HALF_WIDTH))
	y0, y1 := i32(math.floor(p.y)), i32(math.floor(p.y + BODY))
	z0, z1 := i32(math.floor(p.z - HALF_WIDTH)), i32(math.floor(p.z + HALF_WIDTH))
	for y in y0..=y1 {
		for z in z0..=z1 {
			for x in x0..=x1 {
				m, known := world_block(w, x, y, z)
				if !known do unloaded = true
				if known && m != .Air do solid = true
			}
		}
	}
	return
}

// Unloaded ground stops movement like a wall, so the player cannot walk off the world.
blocked :: proc(w: ^World, p: [3]f64) -> bool {
	solid, unloaded := overlap(w, p)
	return solid || unloaded
}

// Move along one axis in small steps and stop at the first block.
slide :: proc(p: ^Player, w: ^World, axis: int, distance: f64) -> (hit: bool) {
	steps := int(abs(distance)/0.05) + 1
	step := distance/f64(steps)
	for _ in 0..<steps {
		p.pos[axis] += step
		if blocked(w, p.pos) {
			p.pos[axis] -= step
			return true
		}
	}
	return false
}

// wish: x strafes right, y rises (flight only), z goes forward.
player_update :: proc(p: ^Player, w: ^World, dt: f64, wish: [3]f32, jump, fast: bool) {
	forward := [3]f64{f64(math.sin(p.yaw)), 0, f64(-math.cos(p.yaw))}
	right := [3]f64{f64(math.cos(p.yaw)), 0, f64(math.sin(p.yaw))}

	if p.fly {
		speed := 300.0 if fast else 24.0
		p.pos += (right*f64(wish.x) + forward*f64(wish.z) + [3]f64{0, f64(wish.y), 0})*speed*dt
		p.vel = 0
		p.eye = EYE
		return
	}
	// Inside something solid, after landing from flight in a hill or having a block placed
	// on us: rise to the first free space. Wait while the ground here is still loading.
	for _ in 0..<1024 {
		solid, unloaded := overlap(w, p.pos)
		if unloaded do return
		if !solid do break
		p.pos.y = math.floor(p.pos.y) + 1
		p.vel.y = 0
	}

	speed := 7.5 if fast else 4.4
	move := (right*f64(wish.x) + forward*f64(wish.z))*speed*dt
	p.vel.y -= 28*dt
	if jump && p.grounded do p.vel.y = 8.6

	for axis in ([2]int{0, 2}) {
		start := p.pos
		if !slide(p, w, axis, move[axis]) || !p.grounded do continue
		// Blocked while walking: climb the block if there is room on top of it.
		p.pos = start
		p.pos.y += 1.02
		if blocked(w, p.pos) || slide(p, w, axis, move[axis]) {
			p.pos = start
		} else {
			p.eye -= 1.02   // the feet moved at once; the eyes catch up below
		}
	}
	p.grounded = false
	if slide(p, w, 1, p.vel.y*dt) {
		p.grounded = p.vel.y < 0
		p.vel.y = 0
	}
	p.eye += (EYE - p.eye)*min(1, 12*dt)
}

// First block along a ray: the block hit and the empty cell in front of it.
raycast :: proc(w: ^World, origin: [3]f64, dir: [3]f32) -> (hit, before: [3]i32, ok: bool) {
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
	before = cell
	for {
		a := 0 if next.x < next.y && next.x < next.z else 1 if next.y < next.z else 2
		if next[a] > REACH do return
		before = cell
		cell[a] += step[a]
		next[a] += delta[a]
		if m, known := world_block(w, cell.x, cell.y, cell.z); known && m != .Air do return cell, before, true
	}
}
