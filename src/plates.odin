package main

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// The world's history: plates moving over a whole planet the size of the Earth for 250 million
// years, which makes its continents, island arcs, hotspot chains and shelves. The known world,
// 1,000 km across, is a window on it, chosen at the end where a continent's margin meets the sea
// over a sinking slab or a hotspot; each island in it is read from what happened at its place.
// The planet is the Earth's size so that the history can be measured against the real Earth's
// (docs/foundations/plates.md, docs/interesting-world/notes/real-plates.md).
//
// The sphere is cut into the six faces of a cube, GLOBE_N cells along each edge, about 39 km a
// cell. Each plate turns rigidly about a pole through the planet's middle. Each step every cell
// asks which plates' crust has moved onto it: none is a gap, filled with new ocean floor, the
// ridge; two is a convergence, where the older, denser ocean sinks under the younger or under a
// continent, or two floating crusts collide and stack. A plate's turning comes from the forces on
// its edges: slabs sinking pull it, ridges push it, collisions and the continental keels under it
// hold it. Where a slab sinks, the plate over it grows an arc of volcanoes; hotspots fixed in
// the mantle build volcanoes on whatever plate passes over them. The ground stands where its crust
// floats, and the sea lies wherever a fixed volume of water fills the hollows up to.

GLOBE_N     :: 256
GLOBE_CELLS :: 6*GLOBE_N*GLOBE_N
GLOBE_B     :: 8                                // cells along a block's edge, for finding the plates that can reach a cell
GLOBE_BN    :: GLOBE_N/GLOBE_B
PLANET      :: 6371.0                           // km
CELL_KM     :: f32(PLANET*3.5449077/(2.4494897*GLOBE_N))   // km, a cell's side on average
MAX_PLATES  :: 128
DT          :: f32(2)                           // Myr a step
SPAN        :: f32(250)                         // Myr of recorded history, ending today
SPIN_UP     :: f32(100)                         // Myr run before it, while the first continent holds together, so the ocean floor has ages
FRAME_EVERY :: 10                               // Myr between frames
WATER       :: 1.335e9                          // km³ of sea, the Earth's (Charette & Smith 2010)
BUOYANT     :: f32(18)                          // km: crust this thick floats and is not subducted
FLOATS      :: f32(31)                          // km: continental crust this thick stands at the datum
WINDOW      :: 1000.0                           // km: the known world's side

// What makes a plate split, as rows. A row's host is the plate's size, how much of it is
// continent and how long since it last split, and for an arc the length and age of the slab under
// its trench, for a margin the age of the ocean beside its continent. Once the host holds, the
// plate splits with the row's chance a Myr; the halves start moving apart at `open`.
Split_Line :: enum u8 {
	Across,   // a wandering line through the plate's continent: a rift that becomes an ocean
	Arc,      // along the back of its volcanic arc: the arc and what lies before it move off toward the trench
	Margin,   // along the edge of its continent: the old ocean beside it begins to sink under it
	Founder,  // round its oldest ocean floor, which begins to sink under the younger
}
Split :: struct {
	name:   string,
	line:   Split_Line,
	area:   f32,      // km², at least
	cont:   [2]f32,   // the continent's share of the plate, within this range
	slab:   f32,      // km of trench over sinking ocean, at least (an arc)
	old:    f32,      // Myr: the sinking slab's age (an arc), or the ocean beside the continent (a margin), at least
	rest:   f32,      // Myr since the plate last split or formed
	chance: f32,      // a Myr
	open:   f32,      // mm/yr
	lasting: f32,     // Myr a regional history's small plate moves off the one it split from, slowing to a stop
}
SPLITS := [?]Split{
	{name = "a continent rifts", line = .Across, area = 2e7, cont = {0.3, 1}, rest = 40, chance = 1.0/45, open = 30},
	{name = "an arc rifts off the plate behind it", line = .Arc, area = 4e6, cont = {0, 1}, slab = 1500, old = 50, rest = 30, chance = 1.0/80, open = 25},
	{name = "old ocean starts to sink under its continent", line = .Margin, area = 1.5e7, cont = {0.1, 0.75}, old = 100, rest = 40, chance = 1.0/80, open = 40},
	{name = "old ocean floor founders under the younger", line = .Founder, area = 3e7, cont = {0, 0.1}, old = 110, rest = 40, chance = 1.0/30, open = 30},
}

// How a plate moves: force a km of sinking slab pulls with, a km of ridge pushes with, and a km of
// colliding edge resists with at 50 mm/yr of closing; the mantle drags on continent 1 + `KEEL` times
// as hard as on ocean floor; the turning follows the forces with a lag of `LAG` Myr.
SLAB, RIDGE, COLLIDE, KEEL, LAG, TOP_SPEED :: f32(32), f32(30), f32(500), f32(0.5), f32(8), f32(160)
// The plate over a trench is drawn toward it, as the sinking slab rolls back, with SUCTION a km.
SUCTION :: f32(15)
// Where two floating crusts collide, the one under is stacked onto the one over, all but a tenth
// of it; ocean floor that arcs and the sea's sediment have thickened past MATURE km is continent.
STACK, MATURE :: f32(0.9), f32(28)
// A rifting continent is thinned within STRETCH km of the rift, to under half at the rift itself.
// The rift wanders off a great circle by RIFT_WANDER of the planet's radius (about 380 km at most)
// over waves of RIFT_WAVE km.
STRETCH, RIFT_WANDER, RIFT_WAVE :: f32(300), f32(0.06), f32(2000)
// Two plates that collide along MERGE_LENGTH km, and along MERGE_SHARE or more of the boundary they
// share, for MERGE_AFTER Myr are sutured into one: the collision has stopped the boundary, not an arc
// or a scrap of continent come to a trench that goes on swallowing ocean along the rest of it.
MERGE_LENGTH, MERGE_SHARE, MERGE_AFTER :: f32(800), f32(0.5), f32(40)
// Two plates whose shared boundary has barely moved (under 4 mm/yr along 90% of 500 km or more) for STILL_AFTER Myr are one.
STILL_AFTER :: f32(20)

// Hotspots: how many, how much each builds a Myr over its vent, how far apart its volcanoes stand.
HOTSPOT_COUNT, HOTSPOT_BUILD, HOTSPOT_SPACING, HOTSPOT_TOP :: [2]int{30, 40}, [2]f32{2500, 6000}, f32(60), [2]f32{4000, 9000}
// Arcs: how far the volcanic front lies from the trench (Syracuse et al. 2010: 240 ± 62 km), how much
// crust the arc adds a Myr over its width, and how fast and how high a vent builds over the arc.
ARC_FRONT, ARC_HALF, ARC_GROWS, ARC_BUILD, ARC_TOP :: [2]f32{170, 260}, f32(45), f32(0.35), f32(1500), [2]f32{1500, 3500}
// Volcanoes wear down where they stand over the sea, by this share of their height every Myr;
// land wears so that its crust thins by its height over the sea in `WEAR` Myr.
VOLCANO_WEAR, WEAR :: f32(0.3), f32(70)
// Land wears only down toward LOWLAND m over the sea: a plain with no relief left wears very slowly.
LOWLAND :: f32(300)
// Continental crust thicker than its neighbour on the same plate by more than SLUMP km spreads into
// it under its own weight, FLOW of the excess a step: a collision raises a belt and a plateau
// hundreds of km across, not a wall one cell wide.
SLUMP, FLOW :: f32(5), f32(0.2)
// The first continent holds together until HOLD Myr before the history begins, so its plates are
// already moving when it does.
HOLD :: f32(20)

Crust :: struct {
	q:     quaternion128,   // the turning the crust has had since it formed, or since the history began: it was then at conj(q)·x
	thick: f32,             // km
	born:  f32,             // Myr ago, as a negative time
	lift:  f32,             // m the regional history's forearc high has raised it over where it floats
	plate: u8,
	cont:  bool,            // continental: it floats, and never sinks
	went:  u16,             // a regional history: km of slab gone down under its edge, where it rides over a trench
}

Plate :: struct {
	alive:       bool,
	serial:      int,               // its number through the history
	born, split: f32,               // when it formed, and last split
	spin:        [3]f32,            // rad/Myr about the planet's middle
	turn, back:  matrix[3, 3]f32,   // this step's turning, and its undoing
	quat:        quaternion128,
	area, cont:  f32,               // km², of it and of its continent
	centre:      [3]f32,            // its area's mean position, not normalised
	cont_centre: [3]f32,
	drag:        matrix[3, 3]f32,
	torque:      [3]f32,
	slab:        f32,               // km of trench where it overrides sinking ocean
	slab_age:    f32,               // the oldest ocean sinking under it, Myr
	old_margin:  f32,               // the oldest ocean of its own beside its continent, Myr
	parent:      int,               // serial of the plate it split from, or -1
	into:        int,               // the plate it joined, once it has
	from:        int,               // a regional history's small plate: the plate it split from,
	push:        [3]f32,            // the turning it moves off it by,
	until:       f32,               // until when, fading
}

Volcano :: struct {
	at:    [3]f32,
	plate: u8,
	arc:   bool,     // over a sinking slab; otherwise over a hotspot
	spot:  i16,
	born:  f32,      // Myr, as a negative time
	last:  f32,      // when it last erupted
	built: f32,      // m it stands over the ground it was built on, less what has worn away
	most:  f32,      // m it may build
	top:   f32,      // m its top stands over the sea
	gone:  bool,     // sunk with its slab
}

Hotspot :: struct {
	at:          [3]f32,
	build:       f32,   // m a Myr
	from, until: f32,
	last:        int,   // its newest volcano, or -1
	most:        f32,
}

Plate_Event :: struct {
	t:     f32,
	what:  string,
	a, b:  int,      // serials
	at:    [3]f32,
}

// Where a place stands on its plate, as ordered rows: the first whose range holds names it.
// The fields are km to the nearest boundary of a kind, measured on the same plate, and the
// crust's kind; the same names step 17's world fields use.
Globe_Field :: enum u8 { Slab, Front, Ridge, Smash, Slip, Spot, Margin, Height }
Plate_Setting :: struct {
	name:   string,
	field:  Globe_Field,
	lo, hi: f32,
	crust:  i8,    // 1 continental only, -1 oceanic only, 0 either
}
PLATE_SETTINGS := [?]Plate_Setting{
	{"trench", .Slab, 0, 120, 0},
	{"forearc", .Front, -1e6, -ARC_HALF, 0},
	{"volcanic arc", .Front, -ARC_HALF, ARC_HALF, 0},
	{"back-arc", .Front, ARC_HALF, 400, 0},
	{"collision belt", .Smash, 0, 350, 0},
	{"rift", .Ridge, 0, 200, 1},
	{"spreading ridge", .Ridge, 0, 120, -1},
	{"hotspot", .Spot, 0, 300, 0},
	{"transform fault", .Slip, 0, 80, 0},
	{"passive margin", .Margin, 0, 250, 1},
	{"continental interior", .Height, -1e6, 1e6, 1},
	{"ocean basin", .Height, -1e6, 1e6, -1},
}

Globe :: struct {
	patch:   bool,           // a regional history's square of the planet, not the whole sphere (regional_init)
	dt:      f32,            // Myr a step
	cell_km: f32,            // km, a cell's side
	centre:  [][3]f32,
	area:    []f32,          // km²
	nbr:     [][8]i32,       // east, west, north, south in the face's frame, then the diagonals
	block:   []i32,
	near:    [][9]i32,       // the blocks around each block
	crust, next: []Crust,
	h:       []f32,          // m over the datum, the level the sea would have with today's Earth's water and hypsometry
	sank:    []u8,           // the plate whose crust sank under a cell this step, or 255
	src:     []i32,          // the cell whose crust moved onto a cell this step, or -1 for new ocean floor
	before:  []f32,          // each cell's height over the sea before the last step, which tells how fast it rises (known_read)
	setback: []f32,          // km from a trench at this cell back to its volcanic front (arc_front)
	bound:   []u8,           // 0, or the boundary a cell lies on: 1 converging, 2 spreading, 3 sliding
	collide: []bool,
	dist:    [Globe_Field][]f32,
	from:    [Globe_Field][]i32,
	fresh:   []u8,           // the pass in which a gap cell was filled, 0 for none
	worn:    []f32,          // km of crust worn off a cell this step
	flow:    []f32,          // km of crust flowing into a cell this step
	masks:   [][2]u64,
	reach:   [2]u64,         // a regional history: the plates that can reach any of its cells this step
	incoming: []f32,         // a regional history: at a trench, the age of the slab going down under it
	rose:    []f32,          // a regional history: m a Myr the crust in each cell rose over the step, rock not surface
	plates:  [MAX_PLATES]Plate,
	polarity: [MAX_PLATES][MAX_PLATES]i8,   // for i < j, 1 where i overrides j, -1 where j overrides i, 0 not yet met
	tally:   [MAX_PLATES][MAX_PLATES]f32,   // this step's evidence for it, and Myr since they last converged
	apart:   [MAX_PLATES][MAX_PLATES]f32,
	contact: [MAX_PLATES][MAX_PLATES]f32,   // km two plates collide along this step
	border, quiet: [MAX_PLATES][MAX_PLATES]f32,   // km they share, and km of it barely moving
	stilled: [MAX_PLATES][MAX_PLATES]f32,   // Myr their shared boundary has barely moved
	smashed: [MAX_PLATES][MAX_PLATES]f32,   // Myr they have collided along at least 400 km
	volcanoes: [dynamic]Volcano,
	hotspots:  [dynamic]Hotspot,
	events:    [dynamic]Plate_Event,
	sea:     f32,            // m over the datum
	t:       f32,
	serials: int,
	splits, merges: int,
	window:  [3]f32,         // the known world's middle
	east, north: [3]f32,
}

// A place followed through the history, for --plates-why: from when its crust formed, where it is.
// It runs the history twice: first keeping, for every step, the cell each cell's crust came from
// (`recording`), from which the cells the crust now at the place lay in are walked back
// (`trace_path`, one a step, -1 before it formed); then following it along them (`tracing`).
recording, tracing: bool
trace_steps: [dynamic][]i32
trace_path: []i32
followed: [3]f32
trace_from: f32

planet:   Globe   // the whole planet
regional: Globe   // the regional history of the known world and the sea round it (regional_history)
globe := &planet  // the one a step works on

// A crew of threads for the passes over every cell: each takes a fixed share of the cells, and
// sums into its own accounts, which are added in order, so the history is the same on any machine.
CREW :: 10
Account :: struct {
	area, cont, slab, slab_age, old_margin: [MAX_PLATES]f32,
	centre, cont_centre, torque:            [MAX_PLATES][3]f32,
	drag:                                   [MAX_PLATES]matrix[3, 3]f32,
	tally, contact, border, quiet:          [MAX_PLATES][MAX_PLATES]f32,
	seeds:                                  [Globe_Field][dynamic]i32,
	gaps:                                   [dynamic]i32,
}
crew: struct {
	job:         proc(id, lo, hi: int),
	n:           int,
	start, done: sync.Barrier,
	threads:     [CREW - 1]^thread.Thread,
	quit:        bool,
	accounts:    [CREW]Account,
}
crew_init :: proc() {
	crew.quit = false
	sync.barrier_init(&crew.start, CREW)
	sync.barrier_init(&crew.done, CREW)
	for i in 1..<CREW do crew.threads[i - 1] = thread.create_and_start_with_poly_data(i, proc(id: int) {
		for {
			sync.barrier_wait(&crew.start)
			if crew.quit do return
			crew.job(id, crew.n*id/CREW, crew.n*(id + 1)/CREW)
			sync.barrier_wait(&crew.done)
		}
	})
}
crew_end :: proc() {
	crew.quit = true
	sync.barrier_wait(&crew.start)
	for t in crew.threads do thread.destroy(t)
	for &a in crew.accounts {
		for f in Globe_Field do delete(a.seeds[f])
		delete(a.gaps)
		a = {}
	}
}
crew_run :: proc(n: int, job: proc(id, lo, hi: int)) {
	crew.job, crew.n = job, n
	sync.barrier_wait(&crew.start)
	job(0, 0, n/CREW)
	sync.barrier_wait(&crew.done)
}
IDENTITY :: matrix[3, 3]f32{1, 0, 0, 0, 1, 0, 0, 0, 1}

// The cube-sphere: a point's cell, and each cell's middle. Coordinates along a face are stretched
// so cells near its corners are about as large as at its middle.
WARP :: f32(0.273)
warp :: proc(u: f32) -> f32 { return u*(1 + WARP*(1 - abs(u))) }
unwarp :: proc(g: f32) -> f32 {
	a := abs(g)
	u := ((1 + WARP) - math.sqrt((1 + WARP)*(1 + WARP) - 4*WARP*a))/(2*WARP)
	return u if g >= 0 else -u
}
face_point :: proc(f: int, u, v: f32) -> [3]f32 {
	p: [3]f32
	d := f/2
	p[d] = 1 if f%2 == 0 else -1
	p[(d + 1)%3], p[(d + 2)%3] = u, v
	return linalg.normalize(p)
}
// The cell a point lies in, and its place in the face's grid, in cells.
globe_at :: proc(p: [3]f32) -> (cell: int, gi, gj: f32) {
	a := [3]f32{abs(p.x), abs(p.y), abs(p.z)}
	d := 0 if a.x >= a.y && a.x >= a.z else 1 if a.y >= a.z else 2
	f := 2*d + (0 if p[d] > 0 else 1)
	gi = (warp(p[(d + 1)%3]/a[d]) + 1)*0.5*GLOBE_N
	gj = (warp(p[(d + 2)%3]/a[d]) + 1)*0.5*GLOBE_N
	i, j := clamp(int(gi), 0, GLOBE_N - 1), clamp(int(gj), 0, GLOBE_N - 1)
	return (f*GLOBE_N + j)*GLOBE_N + i, gi, gj
}
cell_of :: proc(p: [3]f32) -> int { return patch_cell(p) if globe.patch else cube_cell(p) }
cube_cell :: proc(p: [3]f32) -> int { c, _, _ := globe_at(p); return c }
km :: proc(a, b: [3]f32) -> f32 { return linalg.length(a - b)*PLANET }

// Smooth noise on the sphere, -1 to 1, over waves of `wave` km and shorter.
noise3 :: proc(p: [3]f32, wave: f32, octaves: int, s: u32) -> f32 {
	sum, amp, total: f32 = 0, 1, 0
	q := p*PLANET/wave
	for o in 0..<octaves {
		f := [3]f32{math.floor(q.x), math.floor(q.y), math.floor(q.z)}
		t := q - f
		t = t*t*(3 - 2*t)
		v: f32
		for corner in 0..<8 {
			dx, dy, dz := i32(corner & 1), i32((corner >> 1) & 1), i32(corner >> 2)
			w := (t.x if dx == 1 else 1 - t.x)*(t.y if dy == 1 else 1 - t.y)*(t.z if dz == 1 else 1 - t.z)
			v += w*hash01(i32(f.x) + dx + 7919*(i32(f.z) + dz), i32(f.y) + dy, s + u32(o))
		}
		sum += amp*(2*v - 1)
		total += amp
		amp *= 0.5
		q = q*2.03 + 17.1
	}
	return sum/total
}

ocean_depth :: proc(age: f32) -> f32 {   // m, of ocean floor this many Myr old (GDH1, Stein & Stein 1992)
	a := max(age, 0)
	return 2600 + 365*math.sqrt(a) if a < 20 else 5651 - 2473*math.exp(-0.0278*a)
}
// Height of crust over the datum, floating as its thickness and, for ocean floor, its age say.
float_height :: proc(c: Crust, t: f32) -> f32 {
	if c.cont do return (c.thick - FLOATS)*(152 if c.thick > FLOATS else 217)
	return -ocean_depth(t - c.born) + (c.thick - 7)*217
}
floats :: proc(c: Crust) -> bool { return c.cont || c.thick > BUOYANT }
// Whether crust a overrides crust b where they meet: the floating one; else, between two plates,
// the plate the pair's boundary has settled on, so a whole trench sinks the same way; else the
// younger ocean, or the thicker of two floating crusts.
overrides :: proc(a, b: Crust) -> bool {
	if floats(a) != floats(b) do return floats(a)
	if a.plate != b.plate {
		i, j := min(a.plate, b.plate), max(a.plate, b.plate)
		if pol := globe.polarity[i][j]; pol != 0 do return (pol > 0) == (a.plate == i)
	}
	if !floats(a) do return a.born > b.born
	return a.thick >= b.thick
}

// Whether floating crust that is not continent, carried on the plate that goes down where two plates
// meet, is scraped off onto the plate over it, as arcs and plateaus are, rather than ploughing on
// through it as a stray piece of the plate going down.
accretes :: proc(floating, sinking: Crust) -> bool {
	if !floats(floating) || floats(sinking) || floating.cont || floating.plate == sinking.plate do return false
	i, j := min(floating.plate, sinking.plate), max(floating.plate, sinking.plate)
	pol := globe.polarity[i][j]
	return pol != 0 && (pol > 0) == (sinking.plate == i)
}

turning :: proc(spin: [3]f32, years: f32) -> quaternion128 {
	angle := linalg.length(spin)*years
	if angle < 1e-9 do return quaternion128(1)
	return linalg.quaternion_angle_axis_f32(angle, spin/linalg.length(spin))
}
velocity :: proc(p: int, x: [3]f32) -> [3]f32 { return linalg.cross(globe.plates[p].spin, x)*PLANET }   // km/Myr, which is mm/yr

// A new plate in a free slot: the planet's below MICRO, a regional history's own small plates above it.
plate_new :: proc(spin: [3]f32, parent: int) -> int {
	for k in 0..<MAX_PLATES {
		i := MAX_PLATES - 1 - k if globe.patch else k
		if (i >= MICRO) != globe.patch do break
		if p := &globe.plates[i]; !p.alive {
			p^ = {alive = true, serial = globe.serials, born = globe.t, split = globe.t, spin = spin, parent = parent}
			globe.serials += 1
			return i
		}
	}
	return -1
}

globe_init :: proc() {
	globe = &planet
	g := globe
	g^ = {dt = DT, cell_km = CELL_KM}
	g.centre, g.area, g.nbr, g.block = make([][3]f32, GLOBE_CELLS), make([]f32, GLOBE_CELLS), make([][8]i32, GLOBE_CELLS), make([]i32, GLOBE_CELLS)
	g.crust, g.next, g.h = make([]Crust, GLOBE_CELLS), make([]Crust, GLOBE_CELLS), make([]f32, GLOBE_CELLS)
	g.sank, g.bound, g.collide, g.fresh, g.worn, g.src = make([]u8, GLOBE_CELLS), make([]u8, GLOBE_CELLS), make([]bool, GLOBE_CELLS), make([]u8, GLOBE_CELLS), make([]f32, GLOBE_CELLS), make([]i32, GLOBE_CELLS)
	for f in Globe_Field do g.dist[f], g.from[f] = make([]f32, GLOBE_CELLS), make([]i32, GLOBE_CELLS)
	g.near, g.masks = make([][9]i32, 6*GLOBE_BN*GLOBE_BN), make([][2]u64, 6*GLOBE_BN*GLOBE_BN)
	at :: proc(f, i, j: int) -> [3]f32 { return face_point(f, unwarp(2*(f32(i) + 0.5)/GLOBE_N - 1), unwarp(2*(f32(j) + 0.5)/GLOBE_N - 1)) }
	total: f32
	for f in 0..<6 do for j in 0..<GLOBE_N do for i in 0..<GLOBE_N {
		c := (f*GLOBE_N + j)*GLOBE_N + i
		g.centre[c] = at(f, i, j)
		corner :: proc(f: int, i, j: f32) -> [3]f32 { return face_point(f, unwarp(2*i/GLOBE_N - 1), unwarp(2*j/GLOBE_N - 1)) }
		a, b := corner(f, f32(i + 1), f32(j + 1)) - corner(f, f32(i), f32(j)), corner(f, f32(i), f32(j + 1)) - corner(f, f32(i + 1), f32(j))
		g.area[c] = 0.5*linalg.length(linalg.cross(a, b))
		total += g.area[c]
		g.block[c] = i32((f*GLOBE_BN + j/GLOBE_B)*GLOBE_BN + i/GLOBE_B)
	}
	for &a in g.area do a *= f32(4*math.PI*PLANET*PLANET)/total
	g.setback, g.flow = make([]f32, GLOBE_CELLS), make([]f32, GLOBE_CELLS)
	for c in 0..<GLOBE_CELLS do g.setback[c] = math.lerp(ARC_FRONT[0], ARC_FRONT[1], clamp(0.5 + 0.8*noise3(g.centre[c], 1200, 2, world_seed + 77), 0, 1))
	// Neighbours, found by stepping from a cell's middle along its face's grid, which carries across a face's edge.
	for f in 0..<6 do for j in 0..<GLOBE_N do for i in 0..<GLOBE_N {
		c := (f*GLOBE_N + j)*GLOBE_N + i
		eu := (at(f, min(i + 1, GLOBE_N - 1), j) - at(f, max(i - 1, 0), j))/f32(min(i + 1, GLOBE_N - 1) - max(i - 1, 0))
		ev := (at(f, i, min(j + 1, GLOBE_N - 1)) - at(f, i, max(j - 1, 0)))/f32(min(j + 1, GLOBE_N - 1) - max(j - 1, 0))
		steps := [8][2]f32{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}
		for s, k in steps do g.nbr[c][k] = i32(cell_of(linalg.normalize(g.centre[c] + s.x*eu + s.y*ev)))
	}
	for b in 0..<len(g.near) {
		g.near[b] = -1
		g.near[b][0] = i32(b)
		f, bj, bi := b/(GLOBE_BN*GLOBE_BN), (b/GLOBE_BN)%GLOBE_BN, b%GLOBE_BN
		count := 1
		for j in bj*GLOBE_B..<(bj + 1)*GLOBE_B do for i in bi*GLOBE_B..<(bi + 1)*GLOBE_B {
			if i != bi*GLOBE_B && j != bj*GLOBE_B && i != (bi + 1)*GLOBE_B - 1 && j != (bj + 1)*GLOBE_B - 1 do continue
			for n in g.nbr[(f*GLOBE_N + j)*GLOBE_N + i] {
				nb := g.block[n]
				if !slice.contains(g.near[b][:count], nb) && count < 9 { g.near[b][count] = nb; count += 1 }
			}
		}
	}

	// The first continent: one mass round a middle drawn from the seed, ragged, 38% of the planet's
	// surface as the Earth's continental crust is 41% (Cogley 1984), thinning toward its edges.
	s := world_seed + 9000
	mid := linalg.normalize([3]f32{hash01(1, 0, s) - 0.5, hash01(2, 0, s) - 0.5, hash01(3, 0, s) - 0.5})
	shape := make([]f32, GLOBE_CELLS, context.temp_allocator)
	for c in 0..<GLOBE_CELLS {
		x := g.centre[c]
		shape[c] = linalg.dot(x, mid) + 0.45*noise3(x, 5000, 2, s + 1) + 0.18*noise3(x, 1200, 3, s + 2)
	}
	sorted := slice.clone(shape, context.temp_allocator)
	slice.sort(sorted)
	edge := sorted[GLOBE_CELLS*62/100]
	g.t = -(SPAN + SPIN_UP)
	// Plates: a few large ones cut as warped cells round points drawn from the seed.
	count := 12 + int(4*hash01(4, 0, s))
	seeds := make([][3]f32, count, context.temp_allocator)
	for &p, k in seeds {
		p = linalg.normalize([3]f32{hash01(i32(k), 1, s) - 0.5, hash01(i32(k), 2, s) - 0.5, hash01(i32(k), 3, s) - 0.5})
		axis := linalg.normalize([3]f32{hash01(i32(k), 4, s) - 0.5, hash01(i32(k), 5, s) - 0.5, hash01(i32(k), 6, s) - 0.5})
		plate_new(axis*(20 + 40*hash01(i32(k), 7, s))/PLANET, -1)
	}
	for c in 0..<GLOBE_CELLS {
		x := g.centre[c]
		w := linalg.normalize(x + 0.12*[3]f32{noise3(x, 3000, 2, s + 3), noise3(x, 3000, 2, s + 4), noise3(x, 3000, 2, s + 5)})
		best, owner := f32(-2), 0
		for p, k in seeds do if d := linalg.dot(w, p); d > best do best, owner = d, k
		cr := &g.crust[c]
		cr.q, cr.plate = quaternion128(1), u8(owner)
		if shape[c] > edge {
			cr.cont, cr.born = true, g.t
			cr.thick = 28 + 10*smoothstep(0, 0.12, shape[c] - edge) + 2.5*noise3(x, 600, 3, s + 6)
		} else {
			cr.thick, cr.born = 7, g.t - (40 + 60*(0.5 + 0.5*noise3(x, 4000, 2, s + 7)))
		}
	}
	// Hotspots, fixed in the mantle, each alive for a stretch of the history.
	n := HOTSPOT_COUNT[0] + int(f32(HOTSPOT_COUNT[1] - HOTSPOT_COUNT[0])*hash01(5, 0, s))
	for k in 0..<n {
		at := linalg.normalize([3]f32{hash01(i32(k), 11, s) - 0.5, hash01(i32(k), 12, s) - 0.5, hash01(i32(k), 13, s) - 0.5})
		from := g.t + (SPAN + SPIN_UP)*0.8*hash01(i32(k), 14, s)
		life := 60 + 260*hash01(i32(k), 15, s)
		mix := hash01(i32(k), 16, s)
		append(&g.hotspots, Hotspot{at = at, build = math.lerp(HOTSPOT_BUILD[0], HOTSPOT_BUILD[1], mix), from = from, until = from + life, last = -1, most = math.lerp(HOTSPOT_TOP[0], HOTSPOT_TOP[1], mix)})
	}
	for f in Globe_Field do slice.fill(g.dist[f], 1e9)
	globe_measure()
	g.sea = sea_level()
}

// Each step's measure of the plates: their areas, continents, middles and the drag on them.
globe_measure :: proc() {
	g := globe
	crew_run(len(g.crust), proc(id, lo, hi: int) {
		g := globe
		a := &crew.accounts[id]
		a.area, a.cont, a.centre, a.cont_centre, a.drag = {}, {}, {}, {}, {}
		for c in lo..<hi {
			cr := g.crust[c]
			x, s := g.centre[c], g.area[c]
			a.area[cr.plate] += s
			a.centre[cr.plate] += x*s
			if cr.cont { a.cont[cr.plate] += s; a.cont_centre[cr.plate] += x*s }
			a.drag[cr.plate] += s*(1 + KEEL*f32(int(cr.cont)))*(1.05*IDENTITY - linalg.outer_product(x, x))
		}
	})
	for &p, i in g.plates {
		p.area, p.cont, p.centre, p.cont_centre, p.drag, p.torque, p.slab, p.slab_age, p.old_margin = 0, 0, 0, 0, 0, 0, 0, 0, 0
		for &a in crew.accounts {
			p.area += a.area[i]; p.cont += a.cont[i]; p.centre += a.centre[i]; p.cont_centre += a.cont_centre[i]; p.drag += a.drag[i]
		}
		if p.alive && p.area == 0 && !g.patch do p.alive = false   // a regional history's plates may lie outside it a while
	}
}

// The sea's level over the datum: where the planet's water fills the ground up to.
sea_level :: proc() -> f32 {
	g := globe
	BIN :: 20
	LO :: -12000
	bins: [1200]f64
	for c in 0..<len(g.crust) do bins[clamp(int((g.h[c] - LO)/BIN), 0, len(bins) - 1)] += f64(g.area[c])
	below, volume: f64
	for b in 0..<len(bins) {
		level := f64(LO + b*BIN)
		if volume + below*BIN/1000 >= WATER {
			return f32(level - BIN + (WATER - volume)/max(below, 1)*1000)
		}
		volume += below*BIN/1000
		below += bins[b]
	}
	return 0
}

// One step of the history.
globe_step :: proc() {
	g := globe
	t := g.t + g.dt
	for &p in g.plates do if p.alive {
		p.quat = turning(p.spin, g.dt)
		p.turn = linalg.matrix3_from_quaternion_f32(p.quat)
	}
	if !g.patch do clear(&changes)
	// Volcanoes, hotspot tracks and the followed place ride the plate of the ground under them;
	// those carried out of a regional history leave it.
	for &v in g.volcanoes do if !v.gone {
		v.at = g.plates[g.crust[cell_of(v.at)].plate].turn*v.at
		v.gone = cell_of(v.at) < 0
	}

	// Which plates can reach each block, from where their cells move to; a regional history's
	// few plates are all tried everywhere (g.reach).
	if !g.patch {
		for &m in g.masks do m = {}
		crew_run(len(g.crust), proc(id, lo, hi: int) {
			g := globe
			for c in lo..<hi {
				p := g.crust[c].plate
				b := g.block[cell_of(g.plates[p].turn*g.centre[c])]
				intrinsics.atomic_or(&g.masks[b][p/64], 1 << (p%64))
			}
		})
	}
	// Each cell takes the crust that moved onto it.
	for &p in g.plates do p.back = linalg.transpose(p.turn)
	slice.fill(g.sank, 255)
	slice.fill(g.collide, false)
	crew_run(len(g.crust), proc(id, lo, hi: int) {
		g := globe
		gaps := &crew.accounts[id].gaps
		clear(gaps)
		for c in lo..<hi {
			reach := g.reach
			if !g.patch do for b in g.near[g.block[c]] do if b >= 0 do reach |= g.masks[b]
			won, has, from := Crust{}, false, i32(-1)
			// Crust stacks only where the boundary was converging: elsewhere two claims are the grid's noise.
			closing := g.bound[c] == 1
			for n in g.nbr[c][:4] do closing ||= g.bound[n] == 1
			stack := STACK if closing else 0
			for half in 0..<2 do for bits := reach[half]; bits != 0; bits &= bits - 1 {
				p := half*64 + int(intrinsics.count_trailing_zeros(bits))
				k := cell_of(g.plates[p].back*g.centre[c])
				cr: Crust
				if k >= 0 {
					if int(g.crust[k].plate) != p do continue
					cr = g.crust[k]
					cr.q = g.plates[p].quat*cr.q
				} else {   // into a regional history from the planet round it, as the planet stood when the planet's step began
					if p >= MICRO do continue
					ok: bool
					if cr, ok = planet_crust(inflow[p].back*g.centre[c], p); !ok do continue
					cr.q = inflow[p].q*cr.q
					k = -2
				}
				if !has {
					won, has, from = cr, true, i32(k)
				} else if overrides(cr, won) {
					if floats(won) { g.collide[c] = true } else { g.sank[c] = won.plate }
					if accretes(cr, won) do cr.plate = won.plate
					if floats(won) do cr.thick = min(cr.thick + stack*won.thick, 75)
					won, from = cr, i32(k)
				} else {
					if floats(cr) { g.collide[c] = true } else { g.sank[c] = cr.plate }
					if accretes(won, cr) do won.plate = cr.plate
					if floats(cr) do won.thick = min(won.thick + stack*cr.thick, 75)
				}
			}
			g.next[c], g.src[c] = won, from
			g.fresh[c] = 0
			if !has {
				g.next[c].plate, g.fresh[c] = 255, 255
				append(gaps, i32(c))
			}
		}
	})
	gaps := make([dynamic]i32, context.temp_allocator)
	for a in crew.accounts do append(&gaps, ..a.gaps[:])
	// Gaps fill with new ocean floor, from their edges inward, taking the plate most of their
	// neighbours have; the last filled, in the middle, is the ridge, and youngest. A gap of one cell
	// away from a spreading boundary is a hole the grid left, and takes its neighbour's crust.
	for pass in 1..<32 {
		left := false
		for c in gaps do if g.fresh[c] == 255 {
			votes: [8]u8
			counts: [8]int
			n := 0
			for k in g.nbr[c][:4] do if g.fresh[k] < u8(pass) {
				p := g.next[k].plate
				found := false
				for i in 0..<n do if votes[i] == p { counts[i] += 1; found = true }
				if !found { votes[n], counts[n] = p, 1; n += 1 }
			}
			if n == 0 { left = true; continue }
			best := 0
			for i in 1..<n do if counts[i] > counts[best] || counts[i] == counts[best] && votes[i] < votes[best] do best = i
			g.next[c] = {q = quaternion128(1), thick = 7, born = t - g.dt*max(0.1, 1 - 0.25*f32(pass - 1)), plate = votes[best]}
			g.fresh[c] = u8(pass)
			spreading := pass > 1 || g.bound[c] == 2
			for n in g.nbr[c] do spreading ||= g.bound[n] == 2
			if !spreading do for k in g.nbr[c][:4] do if g.fresh[k] == 0 && g.next[k].plate == votes[best] {
				g.next[c], g.src[c] = g.next[k], g.src[k]
				break
			}
		}
		if !left do break
	}
	// A cell whose neighbours nearly all ride another plate joins it: the grid's ragged edges and
	// stray single cells would otherwise lengthen every boundary.
	crew_run(len(g.crust), proc(id, lo, hi: int) {
		g := globe
		for c in lo..<hi {
			g.fresh[c] = g.next[c].plate
			if g.patch {   // a regional history's finer cells, by the plates within 18 km
				g.fresh[c] = rounded(c)
				continue
			}
			own := 0
			for n in g.nbr[c] do own += int(g.next[n].plate == g.next[c].plate)
			if own > 3 do continue
			for n in g.nbr[c][:4] {
				q, same := g.next[n].plate, 0
				for m in g.nbr[c] do same += int(g.next[m].plate == q)
				if same >= 5 { g.fresh[c] = q; break }
			}
		}
	})
	for c in 0..<len(g.crust) do g.next[c].plate = g.fresh[c]
	g.crust, g.next = g.next, g.crust
	g.t = t
	// --plates-why: keep where each cell's crust came from, or follow the crust along what was kept.
	if recording do append(&trace_steps, slice.clone(g.src))
	if tracing {
		append(&trace_steps, nil)
		if c := trace_path[len(trace_steps)]; c >= 0 do followed = g.centre[c]
	}
	for &v in g.volcanoes do if !v.gone {
		c := cell_of(v.at)
		if g.sank[c] == v.plate { v.gone = true } else { v.plate = g.crust[c].plate }
	}
	globe_measure()
	if !g.patch do plates_tidy()

	// Boundaries, by how the plates move across them, and the forces on each plate's edges.
	for f in Globe_Field do slice.fill(g.dist[f], 1e9)
	if g.patch do slice.fill(g.incoming, 1e4)
	crew_run(len(g.crust), proc(id, lo, hi: int) {
		g := globe
		t := g.t
		acc := &crew.accounts[id]
		acc.torque, acc.slab, acc.slab_age, acc.old_margin, acc.tally, acc.contact, acc.border, acc.quiet = {}, {}, {}, {}, {}, {}, {}, {}
		for f in Globe_Field do clear(&acc.seeds[f])
		edge := g.cell_km
		for c in lo..<hi {
			a := g.crust[c]
			x := g.centre[c]
			was := g.bound[c] if g.patch else 0   // a regional history's converging boundary stays so while it closes at all, so that its front holds still
			down: f32                             // and how fast its slab goes down under it
			g.bound[c] = 0
			for n in g.nbr[c][:4] {
				b := g.crust[n]
				if b.plate == a.plate do continue
				dir := toward(c, b.plate) if g.patch else g.centre[n] - x
				dir = linalg.normalize(dir - linalg.dot(dir, x)*x)
				rel := velocity(int(a.plate), x) - velocity(int(b.plate), x)
				speed := linalg.length(rel)
				closing := linalg.dot(rel, dir)
				kind: u8 = 0 if speed < 3 else 1 if closing > (0.2 if was == 1 else 0.5)*speed else 2 if closing < -0.5*speed else 3
				if kind != 0 && (g.bound[c] == 0 || kind < g.bound[c]) do g.bound[c] = kind
				if a.plate < b.plate {
					acc.border[a.plate][b.plate] += edge
					if speed < 4 do acc.quiet[a.plate][b.plate] += edge
				}
				force: [3]f32
				if kind == 1 && floats(a) == floats(b) && a.plate < b.plate {
					acc.tally[a.plate][b.plate] += (1 if a.born > b.born else -1) if !floats(a) else (1 if a.thick >= b.thick else -1)
				}
				switch kind {
				case 1:
					if floats(a) && floats(b) {
						force = -COLLIDE*edge*closing/50*dir
						append(&acc.seeds[.Smash], i32(c))
						if a.plate < b.plate do acc.contact[a.plate][b.plate] += edge
					} else if overrides(b, a) {
						force = SLAB*min(1, (t - a.born + 5)/50)*edge*dir   // the sinking slab pulls, the more the older it is
						append(&acc.seeds[.Slab], i32(c))
					} else {
						if g.patch {   // a trench a regional history's arc grows over once its slab has gone down (below)
							g.incoming[c], down = min(g.incoming[c], t - b.born), max(down, closing)
						} else do append(&acc.seeds[.Front], i32(c))   // the trench, seen from the plate that overrides it
						force = SUCTION*edge*dir
						acc.slab[a.plate] += edge
						acc.slab_age[a.plate] = max(acc.slab_age[a.plate], t - b.born)
					}
				case 2:
					force = RIDGE*edge*-dir
					append(&acc.seeds[.Ridge], i32(c))
				case 3:
					append(&acc.seeds[.Slip], i32(c))
				}
				acc.torque[a.plate] += linalg.cross(x, force)
			}
			if g.patch {
				went := &g.crust[c].went
				went^ = u16(clamp(f32(went^) + (down if down > 0 else -SLAB_GOES)*g.dt, 0, 60000))
				if down > 0 && f32(went^) >= g.setback[c] do append(&acc.seeds[.Front], i32(c))
			}
			if a.cont do for n in g.nbr[c][:4] {
				b := g.crust[n]
				if b.plate == a.plate && !b.cont {
					append(&acc.seeds[.Margin], i32(c))
					acc.old_margin[a.plate] = max(acc.old_margin[a.plate], t - b.born)
					break
				}
			}
		}
	})
	seeds: [Globe_Field][dynamic]i32
	for f in Globe_Field do seeds[f] = make([dynamic]i32, context.temp_allocator)
	for &acc in crew.accounts {
		for &p, i in g.plates {
			p.torque += acc.torque[i]
			p.slab += acc.slab[i]
			p.slab_age, p.old_margin = max(p.slab_age, acc.slab_age[i]), max(p.old_margin, acc.old_margin[i])
		}
		for i in 0..<MAX_PLATES do for j in i + 1..<MAX_PLATES {
			g.tally[i][j], g.contact[i][j] = g.tally[i][j] + acc.tally[i][j], g.contact[i][j] + acc.contact[i][j]
			g.border[i][j], g.quiet[i][j] = g.border[i][j] + acc.border[i][j], g.quiet[i][j] + acc.quiet[i][j]
		}
		for f in Globe_Field do append(&seeds[f], ..acc.seeds[f][:])
	}
	// Collisions that last become sutures: the smaller plate joins the larger.
	for i in 0..<MAX_PLATES do for j in i + 1..<MAX_PLATES {
		if g.tally[i][j] != 0 {
			if g.polarity[i][j] == 0 do g.polarity[i][j] = 1 if g.tally[i][j] > 0 else -1
			g.apart[i][j] = 0
		} else if g.apart[i][j] += g.dt; g.apart[i][j] >= 10 {
			g.polarity[i][j] = 0
		}
		g.tally[i][j] = 0
		if g.patch do continue   // a regional history's plates join only as the planet's do
		g.smashed[i][j] = g.smashed[i][j] + g.dt if g.contact[i][j] >= MERGE_LENGTH && g.contact[i][j] >= MERGE_SHARE*g.border[i][j] else 0
		g.stilled[i][j] = g.stilled[i][j] + g.dt if g.border[i][j] >= 500 && g.quiet[i][j] >= 0.9*g.border[i][j] else 0
		g.contact[i][j], g.border[i][j], g.quiet[i][j] = 0, 0, 0
		if g.stilled[i][j] >= STILL_AFTER && g.plates[i].alive && g.plates[j].alive {
			if g.plates[i].area >= g.plates[j].area { plate_merge(j, i, "a boundary stops moving and two plates become one") } else { plate_merge(i, j, "a boundary stops moving and two plates become one") }
			continue
		}
		if g.smashed[i][j] >= MERGE_AFTER && g.plates[i].alive && g.plates[j].alive {
			if g.plates[i].area >= g.plates[j].area { plate_merge(j, i, "two plates collide and join") } else { plate_merge(i, j, "two plates collide and join") }
		}
	}
	// The fields every step needs, and at a frame the rest, which only name settings.
	framed := t > -g.dt/2 if g.patch else int(math.round(-t))%FRAME_EVERY == 0 || tracing
	reach := [Globe_Field]f32{.Slab = 150, .Front = 700 if framed else ARC_FRONT[1] + ARC_HALF + 20, .Ridge = 250, .Smash = 400, .Slip = 100, .Spot = 400, .Margin = 300, .Height = 0}
	for h in g.hotspots do if t >= h.from && t < h.until do if c := cell_of(h.at); c >= 0 do append(&seeds[.Spot], i32(c))
	spread_seeds, spread_reach, spread_all = seeds, reach, framed
	crew_run(CREW, proc(id, lo, hi: int) {
		for f in Globe_Field do if int(f) >= lo && int(f) < hi && f != .Height && (spread_all || f == .Slab || f == .Front || f == .Spot) do spread(f, spread_seeds[f][:], spread_reach[f])
	})

	// Arcs: the plate over a sinking slab thickens along its volcanic front, which lies a distance
	// from the trench drawn for each stretch of it, and vents open along the front.
	active := make([]bool, len(g.crust), context.temp_allocator)
	live := make([dynamic][3]f32, context.temp_allocator)   // a regional history's live vents, which keep the next at a distance
	for v in g.volcanoes do if v.arc && !v.gone && t - v.last < 2*g.dt {
		active[cell_of(v.at)] = true
		append(&live, v.at)
	}
	for c in 0..<len(g.crust) {
		d := g.dist[.Front][c]
		if d > 1e8 do continue
		front := arc_front(g.from[.Front][c])
		off := d - front
		g.dist[.Front][c] = off   // the Front field is km past the volcanic front, toward the back-arc
		if abs(off) < ARC_HALF do g.crust[c].thick = min(g.crust[c].thick + ARC_GROWS*g.dt, 45 if g.crust[c].cont else 32)
		if abs(off) < 0.6*g.cell_km {
			near := active[c]
			if g.patch {
				apart := math.lerp(VENT_APART[0], VENT_APART[1], hash01(i32(c), 4, world_seed + 78))
				for v in live do near ||= km(v, g.centre[c]) < apart
			} else do for n in g.nbr[c] do near ||= active[n]
			if !near {
				jitter := linalg.normalize(g.centre[c] + (g.cell_km/PLANET)*0.4*[3]f32{hash01(i32(c), 1, world_seed) - 0.5, hash01(i32(c), 2, world_seed) - 0.5, hash01(i32(c), 3, world_seed) - 0.5})
				append(&g.volcanoes, Volcano{at = jitter, plate = g.crust[c].plate, arc = true, spot = -1, born = t, last = t, most = math.lerp(ARC_TOP[0], ARC_TOP[1], hash01(i32(c), i32(t), world_seed + 41))})
				active[c] = true
				append(&live, jitter)
			}
		}
	}
	for &v in g.volcanoes do if v.arc && !v.gone {
		c := cell_of(v.at)
		if g.patch && t - v.born > math.lerp(VENT_LIFE[0], VENT_LIFE[1], (v.most - ARC_TOP[0])/(ARC_TOP[1] - ARC_TOP[0])) do continue   // its life is over
		if off := g.dist[.Front][c]; abs(off) < ARC_HALF + 0.5*g.cell_km && g.crust[c].plate == v.plate {
			v.last = t
			v.built = min(v.built + (v.most/REGION_DT if g.patch else ARC_BUILD)*g.dt, v.most)   // a regional history's vent builds to its height in its first step, as the cone kind does in tens of thousands of years
		}
	}
	// Hotspots build a volcano wherever the plate over them has carried the last one a spacing away.
	for &h, k in g.hotspots do if t >= h.from && t < h.until {
		if h.last >= 0 && !g.volcanoes[h.last].gone && km(g.volcanoes[h.last].at, h.at) < HOTSPOT_SPACING {
			v := &g.volcanoes[h.last]
			v.built, v.last = min(v.built + h.build*g.dt, v.most), t
			continue
		}
		c := cell_of(h.at)
		if c < 0 do continue   // outside a regional history
		p := g.crust[c].plate
		path := km(g.plates[p].turn*h.at, h.at)
		n := clamp(int(path/HOTSPOT_SPACING), 1, 6)
		for i in 0..<n {   // spaced along the path the plate moved over it this step, the oldest carried farthest
			share := f32(n - i)/f32(n)
			at := linalg.normalize(linalg.lerp(h.at, g.plates[p].turn*h.at, share))
			append(&g.volcanoes, Volcano{at = at, plate = p, spot = i16(k), born = t - g.dt*share, last = t, built = min(h.build*g.dt/f32(n), h.most), most = h.most})
		}
		h.last = len(g.volcanoes) - 1
	}

	// The ground: crust floating, a trench pressed down before each overriding plate, a swell over
	// each hotspot; land above the sea wears away into the sea beside it.
	crew_run(len(g.crust), proc(id, lo, hi: int) {
		g := globe
		for c in lo..<hi {
			if g.crust[c].thick > MATURE do g.crust[c].cont = true
			h := float_height(g.crust[c], g.t)
			if d := g.dist[.Slab][c]; d < 150 do h -= 2500*(1 - d/150)
			if d := g.dist[.Spot][c]; d < 400 do h += 900*(1 - d/400)
			g.h[c] = outer_lift(c, h) if g.patch else h
		}
	})
	if !g.patch do g.sea = sea_level()   // a regional history's is the planet's
	// Each cell over the sea loses what wears off it, high ground fast and low plains hardly at all,
	// and each cell under the sea takes its share of what its neighbours lost; thickened continent
	// spreads into its thinner neighbours.
	crew_run(len(g.crust), proc(id, lo, hi: int) {
		g := globe
		for c in lo..<hi {
			g.worn[c] = 0
			if over := g.h[c] - g.sea; over > 0 do g.worn[c] = min(max(over - LOWLAND, 0)/152*g.dt/WEAR*min(1, over/1500), g.crust[c].thick - 7)
			g.flow[c] = flow(c)
		}
	})
	crew_run(len(g.crust), proc(id, lo, hi: int) {
		g := globe
		for c in lo..<hi {
			g.crust[c].thick += g.flow[c] - g.worn[c]
			if g.h[c] >= g.sea do continue
			for k in g.nbr[c][:4] do if g.worn[k] > 0 {
				lows := 0
				for n in g.nbr[k][:4] do lows += int(g.h[n] < g.sea)
				g.crust[c].thick += g.worn[k]*g.area[k]/g.area[c]/f32(lows)
			}
		}
	})
	// A regional history's finer cells spread thickened crust as often as it takes to spread it as far.
	if g.patch do for _ in 1..<int(math.round(CELL_KM*CELL_KM/DT/(g.cell_km*g.cell_km/g.dt))) {
		crew_run(len(g.crust), proc(id, lo, hi: int) { for c in lo..<hi do globe.flow[c] = flow(c) })
		crew_run(len(g.crust), proc(id, lo, hi: int) { for c in lo..<hi do globe.crust[c].thick += globe.flow[c] })
	}
	crew_run(len(g.volcanoes), proc(id, lo, hi: int) {
		g := globe
		for &v in g.volcanoes[lo:hi] do if !v.gone {
			base := g.h[cell_of(v.at)] - g.sea
			if top := base + v.built; top > 0 do v.built -= min(top, max(top*VOLCANO_WEAR, 40)*g.dt)   // the waves plane it to the sea
			v.top = base + v.built
		}
	})

	if g.patch {   // a regional history's plates turn as the planet's do, or move off them (regional_spins)
		for c in 0..<len(g.crust) do g.before[c] = g.h[c] - g.crust[c].lift - g.sea
		plates_split()
		if int(math.round(-t))%FRAME_EVERY == 0 do volcanoes_compact()
		return
	}
	// Each plate turns as the forces on it say, lagging, with no net turning of the whole surface.
	whole: matrix[3, 3]f32
	net: [3]f32
	for &p in g.plates do if p.alive {
		target := linalg.inverse(p.drag)*p.torque
		if s := linalg.length(target)*PLANET; s > TOP_SPEED do target *= TOP_SPEED/s
		p.spin += (target - p.spin)*(1 - math.exp(-g.dt/LAG))
		if t <= -SPAN - HOLD && p.cont > 0.3*p.area do p.spin *= 0.5   // the first continent holds together
		whole += p.drag
		net += p.drag*p.spin
	}
	net = linalg.inverse(whole)*net
	for &p in g.plates do if p.alive do p.spin -= net

	plates_split()
	if int(math.round(-t))%FRAME_EVERY == 0 do volcanoes_compact()
}

// Continental crust thicker than its neighbour on the same plate by more than SLUMP km over a cell of
// the planet's size spreads into it, FLOW of the excess a step: km it takes from its neighbours.
flow :: proc(c: int) -> (f: f32) {
	g := globe
	a := g.crust[c]
	if !a.cont do return
	slump := SLUMP*g.cell_km/CELL_KM
	for n in g.nbr[c][:4] {
		b := g.crust[n]
		if d := b.thick - a.thick; b.plate == a.plate && b.cont && abs(d) > slump do f += FLOW*(d - math.sign(d)*slump)
	}
	return
}

// The plate a boundary cell of a regional history takes: the one most of the cells within 18 km
// ride, where they are three in five and its own fewer than two in five, which rounds the steps of
// the planet's cells it came in with.
rounded :: proc(c: int) -> u8 {
	g := globe
	own := g.next[c].plate
	edge := false
	for n in g.nbr[c] do edge ||= g.next[n].plate != own
	if !edge do return own
	R :: AROUND
	counts: [MAX_PLATES + 1]u16   // and the gaps not yet filled
	i, j, n := c%REGION_N, c/REGION_N, 0
	for y in max(j - R, 0)..=min(j + R, REGION_N - 1) do for x in max(i - R, 0)..=min(i + R, REGION_N - 1) {
		if (x - i)*(x - i) + (y - j)*(y - j) > R*R + R do continue   // round, so as not to square the boundaries
		counts[min(int(g.next[y*REGION_N + x].plate), MAX_PLATES)] += 1
		n += 1
	}
	best := 0
	for k in 1..<MAX_PLATES do if counts[k] > counts[best] do best = k
	return u8(best) if 5*int(counts[best]) >= 3*n && 5*int(counts[own]) < 2*n else own
}

// Volcanoes sunk with their slab, or worn to nothing, are dropped.
volcanoes_compact :: proc() {
	g := globe
	keep := 0
	remap := make([]int, len(g.volcanoes), context.temp_allocator)
	for v, i in g.volcanoes {
		remap[i] = -1
		if v.gone || v.built < 50 && globe.t - v.last > 10 do continue
		remap[i] = keep
		g.volcanoes[keep] = v
		keep += 1
	}
	resize_dynamic_array(&g.volcanoes, keep)
	for &h in g.hotspots do if h.last >= 0 do h.last = remap[h.last]
}

spread_seeds: [Globe_Field][dynamic]i32
spread_reach: [Globe_Field]f32
spread_all: bool

// Km to the nearest seed cell of a field over the same plate, out to `reach`: each cell takes the
// nearest seed of its neighbours', visited nearest first in buckets 10 km wide.
spread_buckets: [Globe_Field][64][dynamic]i32
spread :: proc(f: Globe_Field, seeds: []i32, reach: f32) {
	g := globe
	buckets := &spread_buckets[f]
	for &b in buckets do clear(&b)
	for s in seeds { g.dist[f][s], g.from[f][s] = 0, s; append(&buckets[0], s) }
	for b in 0..<len(buckets) do for i := 0; i < len(buckets[b]); i += 1 {
		c := buckets[b][i]
		if int(g.dist[f][c]/10) < b do continue
		src := g.from[f][c]
		for n in g.nbr[c] {
			if g.crust[n].plate != g.crust[c].plate do continue
			if d := km(g.centre[n], g.centre[src]); d < g.dist[f][n] && d < reach {
				g.dist[f][n], g.from[f][n] = d, src
				append(&buckets[clamp(int(d/10), b, len(buckets) - 1)], n)
			}
		}
	}
}

// How far behind a trench cell its volcanic front lies, varying smoothly along the trench over a
// few hundred kilometres, as it does between real arcs (Syracuse et al. 2010).
arc_front :: proc(c: i32) -> f32 { return globe.setback[c] }

plate_merge :: proc(small, big: int, why: string) {
	g := globe
	for &cr in g.crust do if int(cr.plate) == small do cr.plate = u8(big)
	for &v in g.volcanoes do if int(v.plate) == small do v.plate = u8(big)
	append(&g.events, Plate_Event{t = g.t, what = why, a = g.plates[small].serial, b = g.plates[big].serial, at = linalg.normalize(g.plates[small].centre)})
	g.plates[big].area += g.plates[small].area
	g.plates[small].alive = false
	append(&changes, Change{true, small, big})
	for k in 0..<MAX_PLATES do g.smashed[min(k, small)][max(k, small)], g.polarity[min(k, small)][max(k, small)], g.stilled[min(k, small)][max(k, small)] = 0, 0, 0
	g.merges += 1
}

// Slivers left by the grid join the neighbour they share the most edge with.
plates_tidy :: proc() {
	g := globe
	for &p, i in g.plates do if p.alive && p.area < 30*g.area[0] {
		shared: [MAX_PLATES]int
		for c in 0..<len(g.crust) do if int(g.crust[c].plate) == i do for n in g.nbr[c][:4] do if k := g.crust[n].plate; int(k) != i do shared[k] += 1
		best := 0
		for k in 1..<MAX_PLATES do if shared[k] > shared[best] do best = k
		if shared[best] > 0 do plate_merge(i, best, "a sliver of plate joins its neighbour")
	}
}

// The rows of SPLITS, tried on every plate.
plates_split :: proc() {
	g := globe
	t := g.t
	step := i32((t + SPAN + SPIN_UP)/g.dt)
	for i in 0..<MAX_PLATES do if g.plates[i].alive do for row, r in (REGION_SPLITS[:] if g.patch else SPLITS[:]) {
		p := &g.plates[i]
		if t <= -SPAN && row.line == .Across do continue
		share := p.cont/max(p.area, 1)
		if p.area < row.area || share < row.cont[0] || share > row.cont[1] || t - p.split < row.rest do continue
		if row.line == .Arc && (p.slab < row.slab || p.slab_age < row.old) do continue
		if row.line == .Margin && p.old_margin < row.old do continue
		if hash01(i32(p.serial), step*8 + i32(r), world_seed + (610 if g.patch else 600)) >= row.chance*g.dt do continue
		side := make([]bool, len(g.crust), context.temp_allocator)
		mid: [3]f32
		toward: [3]f32
		switch row.line {
		case .Across:
			c := linalg.normalize(p.cont_centre)
			e1 := linalg.normalize(linalg.cross(c, [3]f32{0.3, 0.5, 0.8}))
			e2 := linalg.cross(c, e1)
			best: f32 = 2e9
			wander := make([]f32, len(g.crust), context.temp_allocator)   // the rift's wandering, the same for every way tried
			for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i do wander[k] = RIFT_WANDER*noise3(g.centre[k], RIFT_WAVE, 3, world_seed + 602 + u32(step))
			// Of the ways tried that leave a quarter of the continent or more on each side, the one
			// that cuts the least of it: the shortest rift is the easiest to break.
			for try in 0..<6 {
				a := 2*math.PI*hash01(i32(p.serial), step*8 + i32(try), world_seed + 601)
				n := math.cos(a)*e1 + math.sin(a)*e2
				left, cut: f32
				for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i && g.crust[k].cont {
					across := linalg.dot(g.centre[k], n) + wander[k]
					if across > 0 do left += g.area[k]
					if abs(across) < 0.5*g.cell_km/PLANET do cut += g.area[k]
				}
				if abs(left/p.cont - 0.5) < 0.25 && cut < best do best, toward = cut, n
			}
			if best > 1e9 do continue
			for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i {
				across := linalg.dot(g.centre[k], toward) + wander[k]
				side[k] = across > 0
				// The continent is stretched thin either side of the rift: its margins sink to shelves.
				if d := abs(across)*PLANET; g.crust[k].cont && d < STRETCH do g.crust[k].thick = 7 + (g.crust[k].thick - 7)*(0.45 + 0.55*d/STRETCH)
			}
			mid = c
		case .Arc:
			for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i && g.dist[.Front][k] < 25 && g.dist[.Front][k] > -1e8 {
				side[k] = true
				mid += g.centre[k]
				toward += g.centre[g.from[.Front][k]] - g.centre[k]
			}
		case .Margin:
			// The ocean on the side of the continent where its margin is oldest, as a real margin
			// turns active along one stretch, not round the whole continent.
			cc := linalg.normalize(p.cont_centre)
			oldest: f32 = -1
			at: [3]f32
			for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i && g.crust[k].cont do for n in g.nbr[k][:4] {
				if b := g.crust[n]; int(b.plate) == i && !b.cont && t - b.born > oldest do oldest, at = t - b.born, g.centre[n]
			}
			for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i && !floats(g.crust[k]) && linalg.dot(g.centre[k] - cc, at - cc) > 0 {
				side[k] = true
				mid += g.centre[k]
			}
			toward = linalg.normalize(p.cont_centre) - linalg.normalize(mid)
		case .Founder:
			rest: [3]f32
			oldest: f32
			for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i do oldest = max(oldest, t - g.crust[k].born)
			if oldest < row.old do continue
			for k in 0..<len(g.crust) do if int(g.crust[k].plate) == i {
				side[k] = !floats(g.crust[k]) && t - g.crust[k].born > 0.75*row.old
				if side[k] { mid += g.centre[k] } else { rest += g.centre[k] }
			}
			toward = linalg.normalize(rest) - linalg.normalize(mid)
		}
		moved: f32
		for k in 0..<len(g.crust) do if side[k] do moved += g.area[k]
		if keep := f32(0.1 if g.patch else 0.15); moved < keep*p.area || moved > (1 - keep)*p.area do continue
		mid = linalg.normalize(mid)
		toward = linalg.normalize(toward - linalg.dot(toward, mid)*mid)
		push := linalg.cross(mid, toward)*row.open/PLANET   // turns the moved part toward `toward` at `open`
		k := plate_new(p.spin + push*(0.5 if row.line == .Across else 1), p.serial)
		if k < 0 do continue
		if row.line == .Across do p.spin -= push*0.5
		if g.patch do g.plates[k].from, g.plates[k].push, g.plates[k].until = i, push, t + row.lasting
		else do append(&changes, Change{false, i, k})
		for c in 0..<len(g.crust) do if side[c] do g.crust[c].plate = u8(k)
		for &v in g.volcanoes do if c := cell_of(v.at); c >= 0 && side[c] do v.plate = u8(k)
		p.split = t
		append(&g.events, Plate_Event{t = t, what = row.name, a = p.serial, b = g.plates[k].serial, at = mid})
		g.splits += 1
		globe_measure()
		break
	}
}

// The setting of a cell: the first row of PLATE_SETTINGS whose range holds.
setting_of :: proc(c: int) -> string { return PLATE_SETTINGS[setting_row(c)].name }
setting_row :: proc(c: int) -> int {
	g := globe
	for s, i in PLATE_SETTINGS {
		if s.crust == 1 && !g.crust[c].cont || s.crust == -1 && g.crust[c].cont do continue
		v := g.dist[s.field][c] if s.field != .Height else g.h[c]
		if s.field == .Front && g.dist[.Front][c] > 1e8 do continue
		if v >= s.lo && v < s.hi do return i
	}
	return len(PLATE_SETTINGS) - 1
}

// The directions east and north along the ground at a point on the planet.
east_north :: proc(p: [3]f32) -> (e, n: [3]f32) {
	e = linalg.normalize(linalg.cross([3]f32{0, 0, 1}, p) + [3]f32{1e-6, 0, 0})
	return e, linalg.cross(p, e)
}

// A point of the known world, km east and south of its middle, on the planet.
window_point :: proc(east, south: f32) -> [3]f32 {
	g := globe
	return linalg.normalize(g.window + (east*g.east - south*g.north)/PLANET)
}

// The ground at a point at a finer scale than the cells: the cells' heights blended, relief that
// moves with the crust, and the volcanoes standing on it. Metres over the sea.
Cone :: struct { at: [3]f32, built, radius: f32 }
fine_height :: proc(p: [3]f32, cones: []Cone) -> f32 {
	g := globe
	// Each of the four cells round the point gives its height and its relief, read where its crust
	// formed so the relief moves with it, and the four are blended.
	cells, share := corners(warped(p))
	h := -g.sea
	for k, i in cells {
		cr := g.crust[k]
		amp: f32 = 350 if cr.cont else 260 if cr.thick > 12 else 150
		h += share[i]*(g.h[k] + amp*noise3(linalg.quaternion_mul_vector3(conj(cr.q), p), 160, 6, world_seed + 31))
	}
	for v in cones do if r := km(p, v.at); r < v.radius do h += v.built*math.pow(1 - r/v.radius, 1.4)
	return h
}
// A point moved up to 40 km, so coasts and ranges read at it do not follow the cells' edges.
warped :: proc(p: [3]f32) -> [3]f32 {
	return linalg.normalize(p + 40/PLANET*[3]f32{noise3(p, 300, 3, world_seed + 32), noise3(p, 300, 3, world_seed + 33), noise3(p, 300, 3, world_seed + 34)})
}
// The four cells round a point and their shares, blended smoothly so that slopes do not change at
// the cells' edges. Neighbours carry across a face's edge.
corners :: proc(p: [3]f32, linear := false) -> (cells: [4]i32, share: [4]f32) {
	c, gi, gj := globe_at(p)
	dx, dy := gi - math.floor(gi) - 0.5, gj - math.floor(gj) - 0.5
	n := planet.nbr[c]
	fx, fy := smoothstep(0, 1, abs(dx)), smoothstep(0, 1, abs(dy))
	if linear do fx, fy = abs(dx), abs(dy)   // so that a contour does not follow the cells' edges
	return {i32(c), n[0] if dx > 0 else n[1], n[2] if dy > 0 else n[3], n[4 + int(dx <= 0) + 2*int(dy <= 0)]}, {(1 - fx)*(1 - fy), fx*(1 - fy), (1 - fx)*fy, fx*fy}
}

// Choose the known world: a window 1,000 km across between 20° and 40° north, where land is
// about a third of it, a continent reaches into it, and islands stand off its coast over a
// sinking slab or a hotspot.
window_choose :: proc() {
	g := globe
	best: f32 = -1e9
	tops := make([dynamic][3]f32, context.temp_allocator)
	for v in g.volcanoes do if !v.gone && v.top > 0 do append(&tops, v.at)
	for c := 0; c < GLOBE_CELLS; c += 3 {
		x := g.centre[c]
		lat := math.to_degrees(math.asin(x.z))
		if lat < 20 || lat > 40 do continue
		e, n := east_north(x)
		land, cont, arc, spot: f32
		for j in 0..<7 do for i in 0..<7 {
			p := linalg.normalize(x + ((f32(i) - 3)*e - (f32(j) - 3)*n)*f32(WINDOW/6/PLANET))
			k := cell_of(p)
			if g.h[k] > g.sea do land += 1.0/49
			if g.crust[k].cont do cont += 1.0/49
			if abs(g.dist[.Front][k]) < 100 do arc = 1
			if g.dist[.Spot][k] < 300 do spot = 1
		}
		islands: f32
		for v in tops do if km(v, x) < WINDOW/2 do islands += 1
		score := -4*abs(land - 0.3) + min(islands, 20)/4 + 2*arc + 0.5*spot + (1 if cont > 0.1 else 0)
		if score > best do best, g.window = score, x
	}
	g.east, g.north = east_north(g.window)
}

// The history, from the first continent to today: frames kept every FRAME_EVERY Myr, and a line
// of figures for each in history.csv.
plates_history :: proc(snaps: ^[dynamic]Snap, raw_dir: string) -> f64 {
	started := time.now()
	globe_init()
	table := strings.builder_make()
	defer strings.builder_destroy(&table)
	strings.write_string(&table, "myr_ago,plates,continental_crust,land,sea_m,splits,joins,volcanoes\n")
	for globe.t < -0.01 {
		if regional_wanted && abs(globe.t + REGION_SPAN) < 0.01 do planet_save()
		if globe.t > -DT - 0.01 {
			globe.before = make([]f32, GLOBE_CELLS)
			for c in 0..<GLOBE_CELLS do globe.before[c] = globe.h[c] - globe.sea
		}
		globe_step()
		free_all(context.temp_allocator)
		if snaps != nil && globe.t >= -SPAN - 0.01 && int(math.round(-globe.t))%FRAME_EVERY == 0 {
			if raw_dir != "" do raw_write(fmt.tprintf("%s/frame-%03d.raw", raw_dir, int(math.round(-globe.t))))
			append(snaps, snap_take())
			g := globe
			alive: int
			cont, land: f32
			for p in g.plates do if p.alive { alive += 1; cont += p.cont }
			for c in 0..<GLOBE_CELLS do if g.h[c] > g.sea do land += g.area[c]
			whole := f32(4*math.PI*PLANET*PLANET)
			fmt.sbprintf(&table, "%.0f,%d,%.4f,%.4f,%.0f,%d,%d,%d\n", -g.t, alive, cont/whole, land/whole, g.sea, g.splits, g.merges, len(g.volcanoes))
		}
		if tracing do trace_note()
	}
	if raw_dir != "" do _ = os.write_entire_file(fmt.tprintf("%s/history.csv", raw_dir), transmute([]u8)strings.to_string(table))
	return time.duration_seconds(time.since(started))
}

// The regional history (step 32's second half; foundations/plates.md, D1's alternative (c)): the
// planet's last REGION_SPAN Myr run again, and beside it, a square of the planet round the known
// world on cells of REGION_KM and steps of REGION_DT, worked by the same steps (`patch`). Its plates
// are the planet's, turning as the planet's turn and joining and splitting as theirs do, and crust
// comes into it from the planet round it; its own are the small plates rows split off them
// (REGION_SPLITS), each moving off the one it split from for a while. It holds what 36 km cells and
// 2 Myr steps cannot: an arc's front a few km wide with each vent living its life, a basin opening
// behind an arc, and a forearc's outer high rising.
REGION_N    :: 200
REGION_KM   :: f32(6)
REGION_SIDE :: f32(REGION_N)*REGION_KM   // km: the known world and 100 km round it
REGION_SPAN :: f32(20)                   // Myr
REGION_DT   :: f32(0.5)                  // Myr
MICRO       :: 112                       // plates in this slot and above are a regional history's own
AROUND      :: 3                         // cells, 18 km: how far a regional history's cell looks to tell which way a boundary runs
PAST        :: 8                         // a regional history's steps each place keeps of how fast its crust rose: its last 4 Myr

REGION_SPLITS := [?]Split{
	// Behind 400 km or more of trench over slab 60 Myr old or more, as the Japan Sea opened behind
	// Japan in about 10 Myr, and the Shikoku and Parece Vela basins behind the Izu-Bonin arc in 10 to
	// 15 (from memory); the Mariana trough opens at 15 to 45 mm/yr today (from memory).
	{name = "an arc rifts off the plate behind it, and a basin opens between", line = .Arc, area = 1e5, cont = {0, 1}, slab = 400, old = 60, rest = 15, chance = 1.0/20, open = 40, lasting = 10},
}

// The forearc's outer high, OUTER.at of the way back from the trench to the volcanic front, rises
// over a young slab, which is light and pushes against the plate over it, and stands still over an
// old one, which sinks steeply and rolls back (Uyeda & Kanamori 1979, from memory): OUTER.rise m a
// Myr at most, as Kikaijima's 2.1 to 2.3 mm/yr (IUGS), fading from slabs OUTER.young Myr old to
// OUTER.old. What it lifts nearer the sea than OUTER.top m, the waves plane as fast as it rises: its
// islands, regions of their own, stand on a bank that goes on rising under them, and the straits
// between them are deeper than any kind's sea ever fell (115 to 120 m), as the reading's guessed high
// kept them (open-decisions.md, 2026-11-16).
OUTER :: struct { at, width, rise, young, old, top: f32 }{at = 0.4, width = 0.2, rise = 2300, young = 20, old = 100, top = -200}

// On a regional history's front a vent opens where no live vent stands within 20 to 60 km (the Izu
// arc's volcanic islands stand 10 to 75 km apart; real arcs have a centre every 40 km, Syracuse &
// Abers 2006) and erupts for 0.3 to 2 Myr, the longer the higher it may build (a guess: an arc's
// stratovolcanoes live some hundreds of thousands of years, from memory), then dies where it stands.
VENT_APART, VENT_LIFE :: [2]f32{20, 60}, [2]f32{0.3, 2}
// A regional history's arc grows over a trench once as much slab has gone down under it as the
// volcanic front lies behind it, so that it reaches the depth where it melts (about 100 km, at a dip
// of about 30°, from memory), not over a step of a boundary that happens to close; where the slab
// stops going down it breaks off at SLAB_GOES km a Myr (a guess) and the arc dies.
SLAB_GOES :: f32(40)

// What a step of the planet did to its plates that a regional history follows: a plate joined
// another (a into b), or split (b off a).
Change :: struct { joined: bool, a, b: int }
changes: [dynamic]Change
regional_wanted: bool             // keep the planet at the regional history's start (planet_save)
saved: Globe
inflow: [MAX_PLATES]struct { q: quaternion128, back: matrix[3, 3]f32 }   // each of the planet's plates' turning since its step began
past_src: [PAST][]i32             // a regional history's last steps, newest first: where each cell's crust came from,
past_rose: [PAST][]f32            // and m a Myr it rose

// From a cell of a regional history toward a plate beside it: the way to the plate's cells within
// 16 km, so that a boundary is told by the way it runs over 36 km, not by the steps of its cells.
toward :: proc(c: int, plate: u8) -> (d: [3]f32) {
	g := globe
	i, j := c%REGION_N, c/REGION_N
	R :: AROUND
	for y in max(j - R, 0)..=min(j + R, REGION_N - 1) do for x in max(i - R, 0)..=min(i + R, REGION_N - 1) {
		if (x - i)*(x - i) + (y - j)*(y - j) > R*R + R do continue
		if k := y*REGION_N + x; g.crust[k].plate == plate do d += g.centre[k] - g.centre[c]
	}
	return
}

// The cell of a regional history's square a point lies in, or -1 outside it.
patch_cell :: proc(p: [3]f32) -> int {
	g := globe
	d := linalg.dot(p, g.window)
	if d <= 0 do return -1
	q := p/d - g.window
	i := int(math.floor((linalg.dot(q, g.east)*PLANET + REGION_SIDE/2)/REGION_KM))
	j := int(math.floor((-linalg.dot(q, g.north)*PLANET + REGION_SIDE/2)/REGION_KM))
	return j*REGION_N + i if i >= 0 && j >= 0 && i < REGION_N && j < REGION_N else -1
}

// The forearc's outer high (OUTER) in a cell of a regional history this step: how fast it lifts the
// crust, which goes into how fast the crust rose (`rose`), and the ground the crust stands at, `h`
// being where it floats.
outer_lift :: proc(c: int, h: f32) -> f32 {
	g := globe
	cr := &g.crust[c]
	rate: f32
	if off := g.dist[.Front][c]; off < 0 {
		trench := g.from[.Front][c]
		back := arc_front(trench)
		rate = OUTER.rise*math.exp(-math.pow(((off + back)/back - OUTER.at)/OUTER.width, 2))*smoothstep(OUTER.old, OUTER.young, g.incoming[trench])
	}
	cr.lift += rate*g.dt
	if over := h + cr.lift - g.sea - OUTER.top; over > 0 do cr.lift = max(cr.lift - over, 0)
	s := g.src[c]
	g.rose[c] = rate + ((h - g.sea - g.before[s])/g.dt if s >= 0 else 0)
	return h + cr.lift
}

// The planet's crust at a point, of plate p if p is not -1 (or false): of the plate most of the four
// cells round the point ride, by their shares, and of its crust the kind most of them have
// (continent, ocean floor that floats, ocean floor that sinks), its thickness and age blended over
// those cells. So a regional history takes on smooth boundaries and coasts, not the planet's cells'.
planet_crust :: proc(at: [3]f32, p := -1) -> (cr: Crust, ok: bool) {
	cells, share := corners(at, true)
	kind :: proc(c: Crust) -> int { return 0 if c.cont else 1 if floats(c) else 2 }
	by: [4]f32   // each cell's plate's share, then its plate's and kind's
	for a, i in cells do for b, j in cells do if planet.crust[a].plate == planet.crust[b].plate do by[i] += share[j]
	most := 0
	for i in 1..<4 do if by[i] > by[most] do most = i
	if p >= 0 && int(planet.crust[cells[most]].plate) != p do return planet.crust[cells[most]], false
	by = {}
	for a, i in cells do for b, j in cells do if x, y := planet.crust[a], planet.crust[b]; x.plate == planet.crust[cells[most]].plate && x.plate == y.plate && kind(x) == kind(y) do by[i] += share[j]
	for i in 0..<4 do if by[i] > by[most] do most = i
	cr = planet.crust[cells[most]]
	thick, born, total: f32
	for k, n in cells do if o := planet.crust[k]; o.plate == cr.plate && kind(o) == kind(cr) {
		thick, born, total = thick + share[n]*o.thick, born + share[n]*o.born, total + share[n]
	}
	cr.thick, cr.born = thick/total, born/total
	return cr, true
}

// Keep the planet as it stands, to run it again from here with the regional history beside it.
planet_save :: proc() {
	saved = planet
	saved.crust, saved.h, saved.bound = slice.clone(planet.crust), slice.clone(planet.h), slice.clone(planet.bound)
	saved.volcanoes, saved.hotspots, saved.events = slice.clone_to_dynamic(planet.volcanoes[:]), slice.clone_to_dynamic(planet.hotspots[:]), slice.clone_to_dynamic(planet.events[:])
}
planet_restore :: proc() {
	crust, next, h, bound := planet.crust, planet.next, planet.h, planet.bound
	window, east, north := planet.window, planet.east, planet.north   // chosen at the end
	delete(planet.volcanoes); delete(planet.hotspots); delete(planet.events); delete(planet.before)
	planet = saved
	planet.window, planet.east, planet.north = window, east, north
	copy(crust, saved.crust); copy(h, saved.h); copy(bound, saved.bound)
	delete(saved.crust); delete(saved.h); delete(saved.bound)
	planet.crust, planet.next, planet.h, planet.bound = crust, next, h, bound
	saved = {}
}

// The regional history's square at its start: the planet's crust there, its thickness blended over
// the four cells round each point as the known world's map reads it, the planet's plates, and its
// volcanoes and hotspots.
regional_init :: proc() {
	N :: REGION_N*REGION_N
	r := &regional
	r^ = {patch = true, dt = REGION_DT, cell_km = REGION_KM, t = planet.t, sea = planet.sea, window = planet.window, east = planet.east, north = planet.north, serials = 1_000_000, plates = planet.plates, polarity = planet.polarity, apart = planet.apart}
	r.centre, r.area, r.nbr, r.setback = make([][3]f32, N), make([]f32, N), make([][8]i32, N), make([]f32, N)
	r.crust, r.next, r.h, r.before, r.rose, r.incoming = make([]Crust, N), make([]Crust, N), make([]f32, N), make([]f32, N), make([]f32, N), make([]f32, N)
	r.sank, r.bound, r.fresh, r.collide, r.src, r.worn, r.flow = make([]u8, N), make([]u8, N), make([]u8, N), make([]bool, N), make([]i32, N), make([]f32, N), make([]f32, N)
	for f in Globe_Field { r.dist[f], r.from[f] = make([]f32, N), make([]i32, N); slice.fill(r.dist[f], 1e9) }
	steps := [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}}
	for c in 0..<N {
		i, j := c%REGION_N, c/REGION_N
		p := window_point((f32(i) + 0.5)*REGION_KM - REGION_SIDE/2, (f32(j) + 0.5)*REGION_KM - REGION_SIDE/2)
		r.centre[c], r.area[c] = p, REGION_KM*REGION_KM*math.pow(linalg.dot(p, r.window), 3)
		for s, k in steps do r.nbr[c][k] = i32(clamp(j + s.y, 0, REGION_N - 1)*REGION_N + clamp(i + s.x, 0, REGION_N - 1))   // at the edge, itself
		r.setback[c] = math.lerp(ARC_FRONT[0], ARC_FRONT[1], clamp(0.5 + 0.8*noise3(p, 1200, 2, world_seed + 77), 0, 1))
		r.crust[c], _ = planet_crust(p)
		k := cube_cell(p)
		r.bound[c] = planet.bound[k]
		near := planet.bound[k] == 1   // beside a trench at work on the planet, the slab has long gone down
		for n in planet.nbr[k] do near ||= planet.bound[n] == 1
		if near do r.crust[c].went = 1000
		r.h[c] = float_height(r.crust[c], r.t)
		r.before[c] = r.h[c] - r.sea
	}
	globe = r
	remap := make([]int, len(planet.volcanoes), context.temp_allocator)
	for v, i in planet.volcanoes {
		remap[i] = -1
		if !v.gone && patch_cell(v.at) >= 0 { remap[i] = len(r.volcanoes); append(&r.volcanoes, v) }
	}
	r.hotspots = slice.clone_to_dynamic(planet.hotspots[:])
	for &h in r.hotspots do h.last = remap[h.last] if h.last >= 0 else -1
	globe_measure()
	globe = &planet
}

// Before a step of the planet: the regional history's plates that are the planet's turn as they do,
// and every plate whose crust lies near enough the square to reach it in the step may.
regional_before :: proc() {
	r := &regional
	for i in 0..<MICRO {
		p, q := planet.plates[i], &r.plates[i]
		q.alive, q.serial, q.born, q.parent, q.spin = p.alive, p.serial, p.born, p.parent, p.spin
	}
	r.reach = {}
	near := math.cos((REGION_SIDE*0.71 + TOP_SPEED*DT)/PLANET)
	for c in 0..<GLOBE_CELLS do if linalg.dot(planet.centre[c], r.window) > near do r.reach[planet.crust[c].plate/64] |= 1 << (planet.crust[c].plate%64)
	for cr in r.crust do r.reach[cr.plate/64] |= 1 << (cr.plate%64)
}

// Before each of its steps: its own plates move off the ones they split from, slowing to a stop,
// and each plate of the planet's has turned so far since the planet's step began.
regional_spins :: proc(sub: int) {
	r := &regional
	for k in 0..<MAX_PLATES - MICRO {   // the oldest first, so a plate's parent has turned before it
		p := &r.plates[MAX_PLATES - 1 - k]
		if !p.alive do continue
		p.spin = r.plates[p.from].spin + p.push*clamp((p.until - r.t)/(p.until - p.split), 0, 1)
		r.reach[1] |= 1 << u64(MAX_PLATES - 1 - k - 64)
	}
	for p, i in planet.plates[:MICRO] do if p.alive {
		q := turning(p.spin, f32(sub + 1)*REGION_DT)
		inflow[i] = {q, linalg.transpose(linalg.matrix3_from_quaternion_f32(q))}
	}
	r.sea = planet.sea
}

// After a step of the planet: what joined or split there joins or splits in the square, and the
// volcanoes of the planet's hotspots its plates carried into the square come with them.
regional_after :: proc() {
	r := &regional
	for ch in changes {
		if ch.joined {
			for &cr in r.crust do if int(cr.plate) == ch.a do cr.plate = u8(ch.b)
			for &v in r.volcanoes do if int(v.plate) == ch.a do v.plate = u8(ch.b)
			for &p in r.plates[MICRO:] do if p.alive && p.from == ch.a do p.from = ch.b
		} else {
			for &cr, c in r.crust do if int(cr.plate) == ch.a && int(planet.crust[cube_cell(r.centre[c])].plate) == ch.b do cr.plate = u8(ch.b)
			for &v in r.volcanoes do if !v.gone && int(v.plate) == ch.a && int(planet.crust[cube_cell(v.at)].plate) == ch.b do v.plate = u8(ch.b)
			r.plates[ch.b].serial = planet.plates[ch.b].serial
		}
	}
	// A plate the planet lost without a join, its last cells gone under another, may linger in the
	// square's finer cells: they take the planet's plate under them.
	stale: [MICRO]bool
	for p, i in planet.plates[:MICRO] do stale[i] = !p.alive || p.serial != r.plates[i].serial
	for &cr, c in r.crust do if int(cr.plate) < MICRO && stale[cr.plate] do cr.plate = planet.crust[cube_cell(r.centre[c])].plate
	for &v in r.volcanoes do if !v.gone && int(v.plate) < MICRO && stale[v.plate] do v.plate = planet.crust[cube_cell(v.at)].plate
	for &p in r.plates[MICRO:] do if p.alive && stale[p.from] do p.from = int(planet.crust[cube_cell(linalg.normalize(p.centre))].plate)
	globe = r
	for v in planet.volcanoes do if !v.gone && !v.arc && patch_cell(v.at) >= 0 && patch_cell(linalg.transpose(planet.plates[v.plate].turn)*v.at) < 0 do append(&r.volcanoes, v)
	globe = &planet
}

// The regional history: the planet run again from where it was kept (planet_save), and its square
// beside it, DT/REGION_DT steps for each of the planet's. Seconds it took.
regional_history :: proc() -> f64 {
	started := time.now()
	planet_restore()
	regional_init()
	for planet.t < -0.01 {
		regional_before()
		for sub in 0..<int(math.round(DT/REGION_DT)) {
			regional_spins(sub)
			globe = &regional
			globe_step()
			if n := int(math.round(-regional.t/REGION_DT)); n < PAST do past_src[n], past_rose[n] = slice.clone(regional.src), slice.clone(regional.rose)
			globe = &planet
			free_all(context.temp_allocator)
		}
		globe_step()
		regional_after()
		free_all(context.temp_allocator)
	}
	return time.duration_seconds(time.since(started))
}

// How fast the crust now in each cell of the regional history rose over each of its last PAST
// steps, newest first, followed back along where it came from; mm/yr. Before crust was new, or came
// in from the planet round the square, the oldest rate known.
regional_past :: proc() -> [][PAST]f32 {
	r := &regional
	out := make([][PAST]f32, len(r.crust))
	for c in 0..<len(r.crust) {
		k := i32(c)
		for n in 0..<PAST {
			out[c][n] = past_rose[n][k]/1000 if k >= 0 else out[c][n - 1]
			if k >= 0 do k = past_src[n][k]
		}
	}
	for n in 0..<PAST { delete(past_src[n]); delete(past_rose[n]); past_src[n], past_rose[n] = nil, nil }
	return out
}


// What the regional history made in the known world, as its first run says: its plates, the
// length of their boundaries against the planet's in the same square (each a count of the edges
// between cells of two plates, times a cell and π/4 for lines at any angle), and the basins opened.
regional_say :: proc() {
	r := &regional
	inside :: proc(p: [3]f32) -> bool { w := window_of(p); return abs(w.x) < WINDOW/2 && abs(w.y) < WINDOW/2 }
	plates: [MAX_PLATES]bool
	edges, coarse: int
	for c in 0..<len(r.crust) do if inside(r.centre[c]) {
		plates[r.crust[c].plate] = true
		for n in ([2]i32{r.nbr[c][0], r.nbr[c][2]}) do edges += int(r.crust[n].plate != r.crust[c].plate)   // east and south
	}
	for c in 0..<GLOBE_CELLS do if inside(planet.centre[c]) do for n in ([2]i32{planet.nbr[c][0], planet.nbr[c][2]}) do coarse += int(planet.crust[n].plate != planet.crust[c].plate)
	n, own := 0, 0
	for p, i in plates do if p { n += 1; own += int(i >= MICRO) }
	fmt.printfln("the regional history: %d plates in the known world, %d of them its own; %.0f km of boundary between them, against %.0f km on the planet's cells; %d basins opened behind arcs in %.0f Myr",
		n, own, f32(edges)*REGION_KM*math.PI/4, f32(coarse)*CELL_KM*math.PI/4, r.splits, REGION_SPAN)
}
