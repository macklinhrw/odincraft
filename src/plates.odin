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
}
SPLITS := [?]Split{
	{name = "a continent rifts", line = .Across, area = 2e7, cont = {0.3, 1}, rest = 40, chance = 1.0/45, open = 30},
	{name = "an arc rifts off the plate behind it", line = .Arc, area = 4e6, cont = {0, 1}, slab = 1500, old = 50, rest = 30, chance = 1.0/80, open = 25},
	{name = "old ocean starts to sink under its continent", line = .Margin, area = 1.5e7, cont = {0.1, 0.75}, old = 100, rest = 40, chance = 1.0/80, open = 40},
	{name = "old ocean floor founders under the younger", line = .Founder, area = 3e7, cont = {0, 0.1}, old = 140, rest = 40, chance = 1.0/60, open = 30},
}

// How a plate moves: force a km of sinking slab pulls with, a km of ridge pushes with, and a km of
// colliding edge resists with at 50 mm/yr of closing; continental keels drag `KEEL` times as hard as
// ocean floor; the turning follows the forces with a lag of `LAG` Myr.
SLAB, RIDGE, COLLIDE, KEEL, LAG, TOP_SPEED :: f32(32), f32(30), f32(400), f32(1), f32(8), f32(160)
// The plate over a trench is drawn toward it, as the sinking slab rolls back, with SUCTION a km.
SUCTION :: f32(15)
// Where two floating crusts collide, the one under is stacked onto the one over, all but a tenth
// of it; ocean floor that arcs and the sea's sediment have thickened past MATURE km is continent.
STACK, MATURE :: f32(0.9), f32(28)
// A rifting continent is thinned within STRETCH km of the rift, to under half at the rift itself.
STRETCH :: f32(300)
// Two plates that collide along MERGE_LENGTH km for MERGE_AFTER Myr are sutured into one.
MERGE_LENGTH, MERGE_AFTER :: f32(800), f32(40)
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

Crust :: struct {
	q:     quaternion128,   // the turning the crust has had since it formed, or since the history began: it was then at conj(q)·x
	thick: f32,             // km
	born:  f32,             // Myr ago, as a negative time
	plate: u8,
	cont:  bool,            // continental: it floats, and never sinks
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
	centre:  [][3]f32,
	area:    []f32,          // km²
	nbr:     [][8]i32,       // east, west, north, south in the face's frame, then the diagonals
	block:   []i32,
	near:    [][9]i32,       // the blocks around each block
	crust, next: []Crust,
	h:       []f32,          // m over the datum, the level the sea would have with today's Earth's water and hypsometry
	sank:    []u8,           // the plate whose crust sank under a cell this step, or 255
	bound:   []u8,           // 0, or the boundary a cell lies on: 1 converging, 2 spreading, 3 sliding
	collide: []bool,
	dist:    [Globe_Field][]f32,
	from:    [Globe_Field][]i32,
	fresh:   []u8,           // the pass in which a gap cell was filled, 0 for none
	worn:    []f32,          // km of crust worn off a cell this step
	masks:   [][2]u64,
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
tracing: bool
followed: [3]f32
trace_from: f32

globe: Globe

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
cell_of :: proc(p: [3]f32) -> int { c, _, _ := globe_at(p); return c }
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

turning :: proc(spin: [3]f32, years: f32) -> quaternion128 {
	angle := linalg.length(spin)*years
	if angle < 1e-9 do return quaternion128(1)
	return linalg.quaternion_angle_axis_f32(angle, spin/linalg.length(spin))
}
velocity :: proc(p: int, x: [3]f32) -> [3]f32 { return linalg.cross(globe.plates[p].spin, x)*PLANET }   // km/Myr, which is mm/yr

plate_new :: proc(spin: [3]f32, parent: int) -> int {
	for &p, i in globe.plates do if !p.alive {
		p = {alive = true, serial = globe.serials, born = globe.t, split = globe.t, spin = spin, parent = parent}
		globe.serials += 1
		return i
	}
	return -1
}

globe_init :: proc() {
	g := &globe
	g^ = {}
	g.centre, g.area, g.nbr, g.block = make([][3]f32, GLOBE_CELLS), make([]f32, GLOBE_CELLS), make([][8]i32, GLOBE_CELLS), make([]i32, GLOBE_CELLS)
	g.crust, g.next, g.h = make([]Crust, GLOBE_CELLS), make([]Crust, GLOBE_CELLS), make([]f32, GLOBE_CELLS)
	g.sank, g.bound, g.collide, g.fresh, g.worn = make([]u8, GLOBE_CELLS), make([]u8, GLOBE_CELLS), make([]bool, GLOBE_CELLS), make([]u8, GLOBE_CELLS), make([]f32, GLOBE_CELLS)
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
	g := &globe
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
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
		if p.alive && p.area == 0 do p.alive = false
	}
}

// The sea's level over the datum: where the planet's water fills the ground up to.
sea_level :: proc() -> f32 {
	g := &globe
	BIN :: 20
	LO :: -12000
	bins: [1200]f64
	for c in 0..<GLOBE_CELLS do bins[clamp(int((g.h[c] - LO)/BIN), 0, len(bins) - 1)] += f64(g.area[c])
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
	g := &globe
	t := g.t + DT
	for &p in g.plates do if p.alive {
		p.quat = turning(p.spin, DT)
		p.turn = linalg.matrix3_from_quaternion_f32(p.quat)
	}
	// Volcanoes, hotspot tracks and the followed place ride the plate of the ground under them.
	for &v in g.volcanoes do if !v.gone do v.at = g.plates[g.crust[cell_of(v.at)].plate].turn*v.at
	if tracing && t > trace_from do followed = g.plates[g.crust[cell_of(followed)].plate].turn*followed

	// Which plates can reach each block, from where their cells move to.
	for &m in g.masks do m = {}
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
		for c in lo..<hi {
			p := g.crust[c].plate
			b := g.block[cell_of(g.plates[p].turn*g.centre[c])]
			intrinsics.atomic_or(&g.masks[b][p/64], 1 << (p%64))
		}
	})
	// Each cell takes the crust that moved onto it.
	for &p in g.plates do p.back = linalg.transpose(p.turn)
	slice.fill(g.sank, 255)
	slice.fill(g.collide, false)
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
		gaps := &crew.accounts[id].gaps
		clear(gaps)
		for c in lo..<hi {
			reach: [2]u64
			for b in g.near[g.block[c]] do if b >= 0 do reach |= g.masks[b]
			won, has := Crust{}, false
			// Crust stacks only where the boundary was converging: elsewhere two claims are the grid's noise.
			closing := g.bound[c] == 1
			for n in g.nbr[c][:4] do closing ||= g.bound[n] == 1
			stack := STACK if closing else 0
			for half in 0..<2 do for bits := reach[half]; bits != 0; bits &= bits - 1 {
				p := half*64 + int(intrinsics.count_trailing_zeros(bits))
				k := cell_of(g.plates[p].back*g.centre[c])
				if int(g.crust[k].plate) != p do continue
				cr := g.crust[k]
				cr.q = g.plates[p].quat*cr.q
				if !has {
					won, has = cr, true
				} else if overrides(cr, won) {
					if floats(won) { g.collide[c] = true } else { g.sank[c] = won.plate }
					if floats(won) do cr.thick = min(cr.thick + stack*won.thick, 75)
					won = cr
				} else {
					if floats(cr) { g.collide[c] = true } else { g.sank[c] = cr.plate }
					if floats(cr) do won.thick = min(won.thick + stack*cr.thick, 75)
				}
			}
			g.next[c] = won
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
			g.next[c] = {q = quaternion128(1), thick = 7, born = t - DT*max(0.1, 1 - 0.25*f32(pass - 1)), plate = votes[best]}
			g.fresh[c] = u8(pass)
			spreading := pass > 1 || g.bound[c] == 2
			for n in g.nbr[c] do spreading ||= g.bound[n] == 2
			if !spreading do for k in g.nbr[c][:4] do if g.fresh[k] == 0 && g.next[k].plate == votes[best] {
				g.next[c] = g.next[k]
				break
			}
		}
		if !left do break
	}
	// A cell whose neighbours nearly all ride another plate joins it: the grid's ragged edges and
	// stray single cells would otherwise lengthen every boundary.
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
		for c in lo..<hi {
			g.fresh[c] = g.next[c].plate
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
	for c in 0..<GLOBE_CELLS do g.next[c].plate = g.fresh[c]
	g.crust, g.next = g.next, g.crust
	g.t = t
	for &v in g.volcanoes do if !v.gone {
		c := cell_of(v.at)
		if g.sank[c] == v.plate { v.gone = true } else { v.plate = g.crust[c].plate }
	}
	globe_measure()
	plates_tidy()

	// Boundaries, by how the plates move across them, and the forces on each plate's edges.
	for f in Globe_Field do slice.fill(g.dist[f], 1e9)
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
		t := g.t
		acc := &crew.accounts[id]
		acc.torque, acc.slab, acc.slab_age, acc.old_margin, acc.tally, acc.contact, acc.border, acc.quiet = {}, {}, {}, {}, {}, {}, {}, {}
		for f in Globe_Field do clear(&acc.seeds[f])
		edge := CELL_KM
		for c in lo..<hi {
			a := g.crust[c]
			x := g.centre[c]
			g.bound[c] = 0
			for n in g.nbr[c][:4] {
				b := g.crust[n]
				if b.plate == a.plate do continue
				dir := g.centre[n] - x
				dir = linalg.normalize(dir - linalg.dot(dir, x)*x)
				rel := velocity(int(a.plate), x) - velocity(int(b.plate), x)
				speed := linalg.length(rel)
				closing := linalg.dot(rel, dir)
				kind: u8 = 0 if speed < 3 else 1 if closing > 0.5*speed else 2 if closing < -0.5*speed else 3
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
						append(&acc.seeds[.Front], i32(c))   // the trench, seen from the plate that overrides it
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
		} else if g.apart[i][j] += DT; g.apart[i][j] >= 10 {
			g.polarity[i][j] = 0
		}
		g.tally[i][j] = 0
		g.smashed[i][j] = g.smashed[i][j] + DT if g.contact[i][j] >= MERGE_LENGTH else 0
		g.stilled[i][j] = g.stilled[i][j] + DT if g.border[i][j] >= 500 && g.quiet[i][j] >= 0.9*g.border[i][j] else 0
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
	framed := int(math.round(-t))%FRAME_EVERY == 0 || tracing
	reach := [Globe_Field]f32{.Slab = 150, .Front = 700 if framed else ARC_FRONT[1] + ARC_HALF + 20, .Ridge = 250, .Smash = 400, .Slip = 100, .Spot = 400, .Margin = 300, .Height = 0}
	for h in g.hotspots do if t >= h.from && t < h.until do append(&seeds[.Spot], i32(cell_of(h.at)))
	spread_seeds, spread_reach, spread_all = seeds, reach, framed
	crew_run(CREW, proc(id, lo, hi: int) {
		for f in Globe_Field do if int(f) >= lo && int(f) < hi && f != .Height && (spread_all || f == .Slab || f == .Front || f == .Spot) do spread(f, spread_seeds[f][:], spread_reach[f])
	})

	// Arcs: the plate over a sinking slab thickens along its volcanic front, which lies a distance
	// from the trench drawn for each stretch of it, and vents open along the front.
	active := make([]bool, GLOBE_CELLS, context.temp_allocator)
	for v in g.volcanoes do if v.arc && !v.gone && t - v.last < 2*DT do active[cell_of(v.at)] = true
	for c in 0..<GLOBE_CELLS {
		d := g.dist[.Front][c]
		if d > 1e8 do continue
		front := arc_front(g.from[.Front][c])
		off := d - front
		g.dist[.Front][c] = off   // the Front field is km past the volcanic front, toward the back-arc
		if abs(off) < ARC_HALF do g.crust[c].thick = min(g.crust[c].thick + ARC_GROWS*DT, 45 if g.crust[c].cont else 32)
		if abs(off) < 0.6*CELL_KM {
			near := active[c]
			for n in g.nbr[c] do near ||= active[n]
			if !near {
				jitter := linalg.normalize(g.centre[c] + (CELL_KM/PLANET)*0.4*[3]f32{hash01(i32(c), 1, world_seed) - 0.5, hash01(i32(c), 2, world_seed) - 0.5, hash01(i32(c), 3, world_seed) - 0.5})
				append(&g.volcanoes, Volcano{at = jitter, plate = g.crust[c].plate, arc = true, spot = -1, born = t, last = t, most = math.lerp(ARC_TOP[0], ARC_TOP[1], hash01(i32(c), i32(t), world_seed + 41))})
				active[c] = true
			}
		}
	}
	for &v in g.volcanoes do if v.arc && !v.gone {
		c := cell_of(v.at)
		if off := g.dist[.Front][c]; abs(off) < ARC_HALF + 0.5*CELL_KM && g.crust[c].plate == v.plate {
			v.last = t
			v.built = min(v.built + ARC_BUILD*DT, v.most)
		}
	}
	// Hotspots build a volcano wherever the plate over them has carried the last one a spacing away.
	for &h, k in g.hotspots do if t >= h.from && t < h.until {
		if h.last >= 0 && !g.volcanoes[h.last].gone && km(g.volcanoes[h.last].at, h.at) < HOTSPOT_SPACING {
			v := &g.volcanoes[h.last]
			v.built, v.last = min(v.built + h.build*DT, v.most), t
			continue
		}
		c := cell_of(h.at)
		p := g.crust[c].plate
		path := km(g.plates[p].turn*h.at, h.at)
		n := clamp(int(path/HOTSPOT_SPACING), 1, 6)
		for i in 0..<n {   // spaced along the path the plate moved over it this step, the oldest carried farthest
			share := f32(n - i)/f32(n)
			at := linalg.normalize(linalg.lerp(h.at, g.plates[p].turn*h.at, share))
			append(&g.volcanoes, Volcano{at = at, plate = p, spot = i16(k), born = t - DT*share, last = t, built = min(h.build*DT/f32(n), h.most), most = h.most})
		}
		h.last = len(g.volcanoes) - 1
	}

	// The ground: crust floating, a trench pressed down before each overriding plate, a swell over
	// each hotspot; land above the sea wears away into the sea beside it.
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
		for c in lo..<hi {
			if g.crust[c].thick > MATURE do g.crust[c].cont = true
			h := float_height(g.crust[c], g.t)
			if d := g.dist[.Slab][c]; d < 150 do h -= 2500*(1 - d/150)
			if d := g.dist[.Spot][c]; d < 400 do h += 900*(1 - d/400)
			g.h[c] = h
		}
	})
	g.sea = sea_level()
	// Each cell over the sea loses what wears off it, high ground fast and low plains hardly at all,
	// and each cell under the sea takes its share of what its neighbours lost.
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
		for c in lo..<hi {
			g.worn[c] = 0
			if over := g.h[c] - g.sea; over > 0 do g.worn[c] = min(max(over - LOWLAND, 0)/152*DT/WEAR*min(1, over/1500), g.crust[c].thick - 7)
		}
	})
	crew_run(GLOBE_CELLS, proc(id, lo, hi: int) {
		g := &globe
		for c in lo..<hi {
			g.crust[c].thick -= g.worn[c]
			if g.h[c] >= g.sea do continue
			for k in g.nbr[c][:4] do if g.worn[k] > 0 {
				lows := 0
				for n in g.nbr[k][:4] do lows += int(g.h[n] < g.sea)
				g.crust[c].thick += g.worn[k]*g.area[k]/g.area[c]/f32(lows)
			}
		}
	})
	crew_run(len(g.volcanoes), proc(id, lo, hi: int) {
		g := &globe
		for &v in g.volcanoes[lo:hi] do if !v.gone {
			base := g.h[cell_of(v.at)] - g.sea
			if top := base + v.built; top > 0 do v.built -= min(top, max(top*VOLCANO_WEAR, 40)*DT)   // the waves plane it to the sea
			v.top = base + v.built
		}
	})

	// Each plate turns as the forces on it say, lagging, with no net turning of the whole surface.
	whole: matrix[3, 3]f32
	net: [3]f32
	for &p in g.plates do if p.alive {
		target := linalg.inverse(p.drag)*p.torque
		if s := linalg.length(target)*PLANET; s > TOP_SPEED do target *= TOP_SPEED/s
		p.spin += (target - p.spin)*(1 - math.exp(-DT/LAG))
		if t <= -SPAN && p.cont > 0.3*p.area do p.spin *= 0.5   // the first continent holds together until the history begins
		whole += p.drag
		net += p.drag*p.spin
	}
	net = linalg.inverse(whole)*net
	for &p in g.plates do if p.alive do p.spin -= net

	plates_split()
	if int(math.round(-t))%FRAME_EVERY == 0 do volcanoes_compact()
}

// Volcanoes sunk with their slab, or worn to nothing, are dropped.
volcanoes_compact :: proc() {
	g := &globe
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
	g := &globe
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

arc_front :: proc(c: i32) -> f32 { return math.lerp(ARC_FRONT[0], ARC_FRONT[1], hash01(c/97, 0, world_seed + 77)) }

plate_merge :: proc(small, big: int, why: string) {
	g := &globe
	for &cr in g.crust do if int(cr.plate) == small do cr.plate = u8(big)
	for &v in g.volcanoes do if int(v.plate) == small do v.plate = u8(big)
	append(&g.events, Plate_Event{t = g.t, what = why, a = g.plates[small].serial, b = g.plates[big].serial, at = linalg.normalize(g.plates[small].centre)})
	g.plates[big].area += g.plates[small].area
	g.plates[small].alive = false
	for k in 0..<MAX_PLATES do g.smashed[min(k, small)][max(k, small)], g.polarity[min(k, small)][max(k, small)], g.stilled[min(k, small)][max(k, small)] = 0, 0, 0
	g.merges += 1
}

// Slivers left by the grid join the neighbour they share the most edge with.
plates_tidy :: proc() {
	g := &globe
	for &p, i in g.plates do if p.alive && p.area < 30*g.area[0] {
		shared: [MAX_PLATES]int
		for c in 0..<GLOBE_CELLS do if int(g.crust[c].plate) == i do for n in g.nbr[c][:4] do if k := g.crust[n].plate; int(k) != i do shared[k] += 1
		best := 0
		for k in 1..<MAX_PLATES do if shared[k] > shared[best] do best = k
		if shared[best] > 0 do plate_merge(i, best, "a sliver of plate joins its neighbour")
	}
}

// The rows of SPLITS, tried on every plate.
plates_split :: proc() {
	g := &globe
	t := g.t
	step := i32((t + SPAN + SPIN_UP)/DT)
	for i in 0..<MAX_PLATES do if g.plates[i].alive do for row, r in SPLITS {
		p := &g.plates[i]
		if t <= -SPAN && row.line == .Across do continue
		share := p.cont/max(p.area, 1)
		if p.area < row.area || share < row.cont[0] || share > row.cont[1] || t - p.split < row.rest do continue
		if row.line == .Arc && (p.slab < row.slab || p.slab_age < row.old) do continue
		if row.line == .Margin && p.old_margin < row.old do continue
		if hash01(i32(p.serial), step*8 + i32(r), world_seed + 600) >= row.chance*DT do continue
		side := make([]bool, GLOBE_CELLS, context.temp_allocator)
		mid: [3]f32
		toward: [3]f32
		switch row.line {
		case .Across:
			c := linalg.normalize(p.cont_centre)
			e1 := linalg.normalize(linalg.cross(c, [3]f32{0.3, 0.5, 0.8}))
			e2 := linalg.cross(c, e1)
			best: f32 = 2
			for try in 0..<6 {
				a := 2*math.PI*hash01(i32(p.serial), step*8 + i32(try), world_seed + 601)
				n := math.cos(a)*e1 + math.sin(a)*e2
				left: f32
				for k in 0..<GLOBE_CELLS do if int(g.crust[k].plate) == i && g.crust[k].cont && linalg.dot(g.centre[k], n) + 0.12*noise3(g.centre[k], 900, 3, world_seed + 602 + u32(step)) > 0 do left += g.area[k]
				if balance := abs(left/p.cont - 0.5); balance < best do best, toward = balance, n
			}
			if best > 0.3 do continue
			for k in 0..<GLOBE_CELLS do if int(g.crust[k].plate) == i {
				across := linalg.dot(g.centre[k], toward) + 0.12*noise3(g.centre[k], 900, 3, world_seed + 602 + u32(step))
				side[k] = across > 0
				// The continent is stretched thin either side of the rift: its margins sink to shelves.
				if d := abs(across)*PLANET; g.crust[k].cont && d < STRETCH do g.crust[k].thick = 7 + (g.crust[k].thick - 7)*(0.45 + 0.55*d/STRETCH)
			}
			mid = c
		case .Arc:
			for k in 0..<GLOBE_CELLS do if int(g.crust[k].plate) == i && g.dist[.Front][k] < 25 && g.dist[.Front][k] > -1e8 {
				side[k] = true
				mid += g.centre[k]
				toward += g.centre[g.from[.Front][k]] - g.centre[k]
			}
		case .Margin:
			for k in 0..<GLOBE_CELLS do if int(g.crust[k].plate) == i && !floats(g.crust[k]) {
				side[k] = true
				mid += g.centre[k]
			}
			toward = linalg.normalize(p.cont_centre) - linalg.normalize(mid)
		case .Founder:
			rest: [3]f32
			oldest: f32
			for k in 0..<GLOBE_CELLS do if int(g.crust[k].plate) == i do oldest = max(oldest, t - g.crust[k].born)
			if oldest < row.old do continue
			for k in 0..<GLOBE_CELLS do if int(g.crust[k].plate) == i {
				side[k] = !floats(g.crust[k]) && t - g.crust[k].born > 0.75*row.old
				if side[k] { mid += g.centre[k] } else { rest += g.centre[k] }
			}
			toward = linalg.normalize(rest) - linalg.normalize(mid)
		}
		moved: f32
		for k in 0..<GLOBE_CELLS do if side[k] do moved += g.area[k]
		if moved < 0.15*p.area || moved > 0.85*p.area do continue
		mid = linalg.normalize(mid)
		toward = linalg.normalize(toward - linalg.dot(toward, mid)*mid)
		push := linalg.cross(mid, toward)*row.open/PLANET   // turns the moved part toward `toward` at `open`
		k := plate_new(p.spin + push*(0.5 if row.line == .Across else 1), p.serial)
		if k < 0 do continue
		if row.line == .Across do p.spin -= push*0.5
		for c in 0..<GLOBE_CELLS do if side[c] do g.crust[c].plate = u8(k)
		for &v in g.volcanoes do if side[cell_of(v.at)] do v.plate = u8(k)
		p.split = t
		append(&g.events, Plate_Event{t = t, what = row.name, a = p.serial, b = g.plates[k].serial, at = mid})
		g.splits += 1
		globe_measure()
		break
	}
}

// The setting of a cell: the first row of PLATE_SETTINGS whose range holds.
setting_of :: proc(c: int) -> string {
	g := &globe
	for s in PLATE_SETTINGS {
		if s.crust == 1 && !g.crust[c].cont || s.crust == -1 && g.crust[c].cont do continue
		v := g.dist[s.field][c] if s.field != .Height else g.h[c]
		if s.field == .Front && g.dist[.Front][c] > 1e8 do continue
		if v >= s.lo && v < s.hi do return s.name
	}
	return "ocean basin"
}

// What is kept of each frame through the history, to draw once the known world is chosen.
Snap_Cell :: struct { plate, bound, age, kind: u8, h: i16 }   // kind: 0 ocean, 1 continent, 2 ocean floor an arc has built on
Snap :: struct {
	t:         f32,
	cells:     []Snap_Cell,
	spins:     [MAX_PLATES][3]f32,
	serials:   [MAX_PLATES]int,
	volcanoes: [dynamic][4]f32,   // where, and its height over the sea, negative for an arc vent's, which are drawn apart
	hotspots:  [dynamic][3]f32,
}

snap_take :: proc() -> Snap {
	g := &globe
	s := Snap{t = g.t, cells = make([]Snap_Cell, GLOBE_CELLS)}
	for c in 0..<GLOBE_CELLS {
		cr := g.crust[c]
		kind: u8 = 1 if cr.cont else 2 if cr.thick > 12 else 0
		s.cells[c] = {plate = cr.plate, bound = g.bound[c], age = u8(clamp(g.t - cr.born, 0, 255)), kind = kind, h = i16(clamp(g.h[c] - g.sea, -12000, 9000))}
	}
	for p, i in g.plates do s.spins[i], s.serials[i] = p.spin, p.serial
	for v in g.volcanoes do if !v.gone && g.t - v.last < 2*DT || v.top > 0 && !v.gone {
		append(&s.volcanoes, [4]f32{v.at.x, v.at.y, v.at.z, v.top if !v.arc else -1 - max(v.top, 0)})
	}
	for h in g.hotspots do if g.t >= h.from && g.t < h.until do append(&s.hotspots, h.at)
	return s
}

sphere_point :: proc(lon, lat: f32) -> [3]f32 { return {math.cos(lat)*math.cos(lon), math.cos(lat)*math.sin(lon), math.sin(lat)} }
east_north :: proc(p: [3]f32) -> (e, n: [3]f32) {
	e = linalg.normalize(linalg.cross([3]f32{0, 0, 1}, p) + [3]f32{1e-6, 0, 0})
	return e, linalg.cross(p, e)
}
hue :: proc(serial: int) -> [3]f32 {
	a := f32(serial)*2.39996
	return 0.62 + 0.25*[3]f32{math.cos(a), math.cos(a - 2.1), math.cos(a + 2.1)}
}
land_colour :: proc(h: f32) -> [3]f32 {
	t := clamp(h/4000, 0, 1)
	return linalg.lerp(linalg.lerp([3]f32{0.36, 0.56, 0.26}, [3]f32{0.70, 0.62, 0.40}, clamp(t*3, 0, 1)), [3]f32{0.95, 0.94, 0.92}, clamp(t*2 - 1, 0, 1))
}

// A frame: above, the plates, their motion and their boundaries (red converging, yellow spreading,
// white sliding), hotspots ringed; below, the crust (ocean floor pale where young, dark where old,
// continent under the sea grey-blue, ocean floor arcs built on violet), land by height, volcanoes
// standing over the sea as dots, active arc vents red. The known world is boxed in magenta.
FW, FH :: 1200, 600
frame_draw :: proc(s: ^Snap, path: string) {
	pixels := make([]u8, FW*FH*2*4)
	defer delete(pixels)
	put :: proc(pixels: []u8, x, y: int, c: [3]f32) {
		if x < 0 || y < 0 || x >= FW || y >= 2*FH do return
		for k in 0..<3 do pixels[(y*FW + x)*4 + k] = u8(clamp(c[k], 0, 1)*255)
	}
	cells := make([]int, FW*FH, context.temp_allocator)
	for py in 0..<FH do for px in 0..<FW do cells[py*FW + px] = cell_of(sphere_point((f32(px) + 0.5)/FW*2*math.PI - math.PI, math.PI/2 - (f32(py) + 0.5)/FH*math.PI))
	for py in 0..<FH do for px in 0..<FW {
		c := s.cells[cells[py*FW + px]]
		right, below := s.cells[cells[py*FW + (px + 1)%FW]], s.cells[cells[min(py + 1, FH - 1)*FW + px]]
		col := hue(s.serials[c.plate])*(0.72 if c.kind == 1 else 1)
		if right.plate != c.plate || below.plate != c.plate {
			b := max(c.bound, right.bound if right.plate != c.plate else 0)
			lines := [4][3]f32{{0.3, 0.3, 0.3}, {0.85, 0.1, 0.1}, {1, 0.85, 0.1}, {1, 1, 1}}
			col = lines[b]
		}
		put(pixels, px, py, col)
		h := f32(c.h)
		low := clamp(f32(c.age)/180, 0, 1)
		col = linalg.lerp([3]f32{0.55, 0.78, 0.95}, [3]f32{0.04, 0.12, 0.38}, math.sqrt(low))
		if c.kind == 1 do col = [3]f32{0.55, 0.68, 0.74}
		if c.kind == 2 do col = linalg.lerp(col, [3]f32{0.55, 0.35, 0.75}, 0.6)
		if h > 0 do col = land_colour(h)
		put(pixels, px, FH + py, col)
	}
	to_pixel :: proc(p: [3]f32) -> (int, int) {
		lon, lat := math.atan2(p.y, p.x), math.asin(clamp(p.z, -1, 1))
		return int((lon + math.PI)/(2*math.PI)*FW), int((math.PI/2 - lat)/math.PI*FH)
	}
	// Arrows of motion, a pixel for each 4 mm/yr, from points 30 pixels apart.
	for py := 15; py < FH; py += 30 do for px := 15; px < FW; px += 30 {
		lat := math.PI/2 - (f32(py) + 0.5)/FH*math.PI
		lon := (f32(px) + 0.5)/FW*2*math.PI - math.PI
		p := sphere_point(lon, lat)
		c := s.cells[cell_of(p)]
		v := linalg.cross(s.spins[c.plate], p)*PLANET
		e, n := east_north(p)
		ve, vn := linalg.dot(v, e), linalg.dot(v, n)
		for k in 0..<int(math.hypot(ve, vn)/4) {
			f := f32(k)/max(math.hypot(ve, vn)/4, 1)
			put(pixels, px + int(ve/4*f/max(math.cos(lat), 0.5)), py - int(vn/4*f), {0.1, 0.1, 0.1})
		}
		put(pixels, px, py, {0, 0, 0})
	}
	for h in s.hotspots {
		x, y := to_pixel(h)
		for a in 0..<24 do for row in 0..<2 do put(pixels, x + int(5*math.cos(f32(a)*0.2618)), y + row*FH + int(5*math.sin(f32(a)*0.2618)), {1, 1, 1})
	}
	for v in s.volcanoes {
		x, y := to_pixel(v.xyz)
		col := [3]f32{0.95, 0.25, 0.1} if v.w < 0 else [3]f32{1, 1, 0.6}
		if v.w < 0 && v.w > -1.5 do col = {0.65, 0.2, 0.1}   // an arc vent under the sea
		for dy in 0..=1 do for dx in 0..=1 do put(pixels, x + dx, FH + y + dy, col)
	}
	if globe.window != {} do for row in 0..<2 {
		for i in 0..<400 {
			a := f32(i)/400*WINDOW - WINDOW/2
			for side in 0..<4 {
				u, v := [4]f32{a, a, -WINDOW/2, WINDOW/2}[side], [4]f32{-WINDOW/2, WINDOW/2, a, a}[side]
				x, y := to_pixel(window_point(u, v))
				put(pixels, x, y + row*FH, {1, 0.2, 0.9})
			}
		}
	}
	write_png(path, pixels, FW, 2*FH, false)
}

// A point of the known world, km east and south of its middle, on the planet.
window_point :: proc(east, south: f32) -> [3]f32 {
	g := &globe
	return linalg.normalize(g.window + (east*g.east - south*g.north)/PLANET)
}

// The ground at a point at a finer scale than the cells: the cells' heights blended, relief that
// moves with the crust, and the volcanoes standing on it. Metres over the sea.
Cone :: struct { at: [3]f32, built, radius: f32 }
fine_height :: proc(p: [3]f32, cones: []Cone) -> f32 {
	g := &globe
	// The cells are read at a point moved up to 40 km, so coasts and ranges do not follow their edges,
	// and blended smoothly, so their slopes do not change at the edges either.
	warped := linalg.normalize(p + 40/PLANET*[3]f32{noise3(p, 300, 3, world_seed + 32), noise3(p, 300, 3, world_seed + 33), noise3(p, 300, 3, world_seed + 34)})
	c, gi, gj := globe_at(warped)
	dx, dy := gi - math.floor(gi) - 0.5, gj - math.floor(gj) - 0.5
	// Each of the four cells round the point gives its height and its relief, read where its crust
	// formed so the relief moves with it, and the four are blended. Neighbours carry across a face's edge.
	at :: proc(k: i32, p: [3]f32) -> f32 {
		cr := globe.crust[k]
		amp: f32 = 350 if cr.cont else 260 if cr.thick > 12 else 150
		return globe.h[k] + amp*noise3(linalg.quaternion_mul_vector3(conj(cr.q), p), 160, 6, world_seed + 31)
	}
	n := g.nbr[c]
	across, up := n[0] if dx > 0 else n[1], n[2] if dy > 0 else n[3]
	corner := n[4 + int(dx <= 0) + 2*int(dy <= 0)]
	fx, fy := smoothstep(0, 1, abs(dx)), smoothstep(0, 1, abs(dy))
	h := math.lerp(math.lerp(at(i32(c), p), at(across, p), fx), math.lerp(at(up, p), at(corner, p), fx), fy) - g.sea
	for v in cones do if r := km(p, v.at); r < v.radius do h += v.built*math.pow(1 - r/v.radius, 1.4)
	return h
}

// Choose the known world: a window 1,000 km across between 20° and 40° north, where land is
// about a third of it, a continent reaches into it, and islands stand off its coast over a
// sinking slab or a hotspot.
window_choose :: proc() {
	g := &globe
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

// The known world today at 1 km a pixel, -z (north) at the top, and its islands counted.
world_draw :: proc(path: string) {
	g := &globe
	SIZE :: 1000
	cones := make([dynamic]Cone)
	defer delete(cones)
	for v in g.volcanoes do if !v.gone && v.built > 0 && km(v.at, g.window) < WINDOW {
		append(&cones, Cone{at = v.at, built = v.built, radius = v.built/(1000*(0.2 if v.arc else 0.09))})
	}
	height := make([]f32, SIZE*SIZE)
	defer delete(height)
	local := make([dynamic]Cone)
	defer delete(local)
	for py in 0..<SIZE do for px in 0..<SIZE {
		p := window_point(f32(px) + 0.5 - SIZE/2, f32(py) + 0.5 - SIZE/2)
		clear(&local)
		for v in cones do if km(p, v.at) < v.radius do append(&local, v)
		height[py*SIZE + px] = fine_height(p, local[:])
	}
	pixels := make([]u8, SIZE*SIZE*4)
	defer delete(pixels)
	for py in 0..<SIZE do for px in 0..<SIZE {
		h := height[py*SIZE + px]
		gx := height[py*SIZE + min(px + 1, SIZE - 1)] - height[py*SIZE + max(px - 1, 0)]
		gy := height[min(py + 1, SIZE - 1)*SIZE + px] - height[max(py - 1, 0)*SIZE + px]
		shade := clamp(0.8 + (-gx - gy)/600, 0.4, 1.25)
		col := land_colour(h)*shade if h > 0 else linalg.lerp([3]f32{0.45, 0.70, 0.88}, [3]f32{0.05, 0.14, 0.38}, clamp(-h/5000, 0, 1))
		for k in 0..<3 do pixels[(py*SIZE + px)*4 + k] = u8(clamp(col[k], 0, 1)*255)
	}
	// Each land mass, by flood fill: what is cut by the window's edge is the continent's.
	group := make([]i32, SIZE*SIZE)
	defer delete(group)
	sizes, edges := make([dynamic]int, context.temp_allocator), make([dynamic]bool, context.temp_allocator)
	stack := make([dynamic]int, context.temp_allocator)
	for start in 0..<SIZE*SIZE do if height[start] > 0 && group[start] == 0 {
		append(&sizes, 0); append(&edges, false)
		id := i32(len(sizes))
		group[start] = id
		append(&stack, start)
		for len(stack) > 0 {
			c := pop(&stack)
			sizes[id - 1] += 1
			x, y := c%SIZE, c/SIZE
			if x == 0 || y == 0 || x == SIZE - 1 || y == SIZE - 1 do edges[id - 1] = true
			for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
				nx, ny := x + d.x, y + d.y
				if nx < 0 || ny < 0 || nx >= SIZE || ny >= SIZE do continue
				if n := ny*SIZE + nx; height[n] > 0 && group[n] == 0 { group[n] = id; append(&stack, n) }
			}
		}
	}
	write_png(path, pixels, SIZE, SIZE, false)
	islands := make([dynamic]int, context.temp_allocator)
	mainland := 0
	for s, i in sizes { if edges[i] && s >= 5000 { mainland += s } else { append(&islands, s) } }
	slice.reverse_sort(islands[:])
	fmt.printf("the known world, 1,000 km across at %.1f° N: %d km² of continent cut by its edges and %d islands of 1 km² or more", math.to_degrees(math.asin(g.window.z)), mainland, len(islands))
	if len(islands) > 0 do fmt.printf(", the largest %d km²", islands[0])
	over := [3]int{}
	for s in islands do for b, k in ([3]int{10, 100, 1000}) do if s >= b do over[k] += 1
	fmt.printfln("; %d over 10 km², %d over 100, %d over 1,000", over[0], over[1], over[2])
	// The islands by what made the ground under their middle.
	kinds := make(map[string]int, context.temp_allocator)
	middles := make([][2]int, len(sizes), context.temp_allocator)
	counts := make([]int, len(sizes), context.temp_allocator)
	for c in 0..<SIZE*SIZE do if id := group[c]; id > 0 { middles[id - 1] += {c%SIZE, c/SIZE}; counts[id - 1] += 1 }
	for s, i in sizes do if !(edges[i] && s >= 5000) {
		m := middles[i]/counts[i]
		kinds[setting_of(cell_of(window_point(f32(m.x) - SIZE/2, f32(m.y) - SIZE/2)))] += 1
	}
	fmt.print("  islands by setting:")
	for k, n in kinds do fmt.printf(" %s %d,", k, n)
	fmt.println()
}

// The comparison grids (tools/plates_compare.py): each frame on half-degree cells of latitude and
// longitude, from the north pole and the date line: plate, crust (0 ocean, 1 continent, 2 arc-built
// ocean floor), ocean floor's age in Myr, ground over the sea in m, motion east and north in mm/yr.
raw_write :: proc(path: string) {
	g := &globe
	W, H :: 720, 360
	out := make([dynamic]u8, 0, W*H*9)
	defer delete(out)
	for y in 0..<H do for x in 0..<W {
		p := sphere_point((f32(x) + 0.5)/W*2*math.PI - math.PI, math.PI/2 - (f32(y) + 0.5)/H*math.PI)
		c := cell_of(p)
		cr := g.crust[c]
		v := velocity(int(cr.plate), p)
		e, n := east_north(p)
		kind: u8 = 1 if cr.cont else 2 if cr.thick > 12 else 0
		h := i16(clamp(g.h[c] - g.sea, -12000, 9000))
		ve, vn := i16(clamp(linalg.dot(v, e), -3000, 3000)), i16(clamp(linalg.dot(v, n), -3000, 3000))
		append(&out, cr.plate, kind, u8(clamp(g.t - cr.born, 0, 255)), u8(h), u8(u16(h) >> 8), u8(ve), u8(u16(ve) >> 8), u8(vn), u8(u16(vn) >> 8))
	}
	_ = os.write_entire_file(path, out[:])
}

// The history, from the first continent to today: frames kept every FRAME_EVERY Myr, and a line
// of figures for each in history.csv.
plates_history :: proc(snaps: ^[dynamic]Snap, raw_dir: string) -> f64 {
	started := time.now()
	crew_init()
	defer crew_end()
	globe_init()
	table := strings.builder_make()
	defer strings.builder_destroy(&table)
	strings.write_string(&table, "myr_ago,plates,continental_crust,land,sea_m,splits,joins,volcanoes\n")
	for globe.t < -0.01 {
		globe_step()
		free_all(context.temp_allocator)
		if snaps != nil && globe.t >= -SPAN - 0.01 && int(math.round(-globe.t))%FRAME_EVERY == 0 {
			if raw_dir != "" do raw_write(fmt.tprintf("%s/frame-%03d.raw", raw_dir, int(math.round(-globe.t))))
			append(snaps, snap_take())
			g := &globe
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

// --plates=dir: run the history, write its frames and the known world's map, and say what it made.
plates_main :: proc(dir: string) {
	os.make_directory(dir)
	snaps: [dynamic]Snap
	took := plates_history(&snaps, dir)
	g := &globe
	window_choose()
	drawing := time.now()
	for &s in snaps do frame_draw(&s, fmt.tprintf("%s/frame-%03d.png", dir, int(math.round(-s.t))))
	world_draw(fmt.tprintf("%s/world.png", dir))
	fmt.printfln("the plates' history: %.0f Myr in %.0f steps of %.0f Myr on %d cells of about %.0f km, in %.2f s; drawing took %.2f s", SPAN + SPIN_UP, (SPAN + SPIN_UP)/DT, DT, GLOBE_CELLS, math.sqrt(f64(4*math.PI*PLANET*PLANET/GLOBE_CELLS)), took, time.duration_seconds(time.since(drawing)))
	alive, largest := 0, f32(0)
	for p in g.plates do if p.alive { alive += 1; largest = max(largest, p.area) }
	fmt.printfln("%d plates today, the largest %.0f million km²; %d splits and %d joins over the history; the sea %.0f m over the datum", alive, largest/1e6, g.splits, g.merges, g.sea)
	// Land masses on the planet, by flood fill over the cells: continents of a million km² or more.
	group := make([]i32, GLOBE_CELLS)
	defer delete(group)
	masses := make([dynamic]f32)
	defer delete(masses)
	stack := make([dynamic]int)
	defer delete(stack)
	land, cont: f32
	for c in 0..<GLOBE_CELLS {
		if g.crust[c].cont do cont += g.area[c]
		if g.h[c] <= g.sea || group[c] != 0 do continue
		append(&masses, 0)
		group[c] = i32(len(masses))
		append(&stack, c)
		for len(stack) > 0 {
			k := pop(&stack)
			masses[len(masses) - 1] += g.area[k]
			land += g.area[k]
			for n in g.nbr[k][:4] do if g.h[n] > g.sea && group[n] == 0 { group[n] = i32(len(masses)); append(&stack, int(n)) }
		}
	}
	slice.reverse_sort(masses[:])
	whole := f32(4*math.PI*PLANET*PLANET)
	continents, large := 0, 0
	for m in masses { if m >= 1e6 { continents += 1 } else if m >= 1e4 { large += 1 } }
	fmt.printf("land %.1f%% of the planet and continental crust %.1f%%: %d continents of a million km² or more (", 100*land/whole, 100*cont/whole, continents)
	for m, i in masses[:continents] do fmt.printf("%s%.1f", ", " if i > 0 else "", m/1e6)
	islands := 0
	for v in g.volcanoes do if !v.gone && v.top > 0 && g.h[cell_of(v.at)] <= g.sea do islands += 1
	fmt.printfln(" million km²), %d islands of 10,000 km² to a million, and %d volcanoes standing as islands of their own", large, islands)
	// How fast each hotspot's chain ages along its length: the plate's speed over it.
	rates := make([dynamic]f32)
	defer delete(rates)
	for h, k in g.hotspots do if g.t < h.until && g.t >= h.from + 10 {
		sx, sy, sxx, sxy, n: f32
		for v in g.volcanoes do if !v.gone && int(v.spot) == k && !v.arc && g.t - v.born < 40 {
			d, age := km(v.at, h.at), g.t - v.born
			sx += age; sy += d; sxx += age*age; sxy += age*d; n += 1
		}
		if n >= 4 do append(&rates, (n*sxy - sx*sy)/(n*sxx - sx*sx))
	}
	slice.sort(rates[:])
	if len(rates) > 0 do fmt.printfln("%d hotspot chains with volcanoes over the last 40 Myr age along their length at %.0f to %.0f km/Myr (median %.0f)", len(rates), rates[0], rates[len(rates) - 1], rates[len(rates)/2])
	fmt.printfln("frames in %s: frame-250.png (the first continent) to frame-000.png (today), world.png (the known world)", dir)
	for &s in snaps { delete(s.cells); delete(s.volcanoes); delete(s.hotspots) }
	delete(snaps)
}

// --plates-why=x,z: what happened to the ground now at this point of the known world (metres east
// and south of its middle) through the history. The history runs once to find which crust is
// there and where it formed, and again following that crust from then on.
trace_last: string
plates_why :: proc(x, z: f64) {
	g := &globe
	plates_history(nil, "")
	window_choose()
	here := window_point(f32(x/1000), f32(z/1000))
	c := cell_of(here)
	cr := g.crust[c]
	window, east, north := g.window, g.east, g.north
	start := max(cr.born, -(SPAN + SPIN_UP))
	fmt.printfln("%.0f km east and %.0f km south of the known world's middle, at %.1f° N %.1f° E of the planet; %s crust %.0f km thick, formed %s", x/1000, z/1000, math.to_degrees(math.asin(here.z)), math.to_degrees(math.atan2(here.y, here.x)), "continental" if cr.cont else "oceanic", cr.thick, fmt.tprintf("%.0f Myr ago", -cr.born) if cr.born > -(SPAN + SPIN_UP) else "before the history began")
	origin := linalg.quaternion_mul_vector3(conj(cr.q), here)
	fmt.println("  Myr ago  plate  crust                          ground      setting")
	tracing, followed, trace_from = true, origin, start
	trace_last = ""
	plates_history(nil, "")
	g.window, g.east, g.north = window, east, north
	fmt.printfln("  the crust followed through the history ends %.0f km from the place asked about", km(followed, here))
	for e in g.events do if km(e.at, here) < 1500 && e.t >= start do fmt.printfln("  %.0f Myr ago, %.0f km off: %s (plate %d, %d)", -e.t, km(e.at, here), e.what, e.a, e.b)
	vents := 0
	for v in g.volcanoes do if !v.gone && km(v.at, here) < 60 {
		vents += 1
		if vents <= 8 do fmt.printfln("  %s vent %.0f km off, built from %.0f to %.0f Myr ago, its top %.0f m %s the sea", "an arc" if v.arc else "a hotspot", km(v.at, here), -v.born, -v.last, abs(v.top), "over" if v.top > 0 else "under")
	}
	fmt.printfln("  today: %s", setting_of(c))
}

trace_note :: proc() {
	g := &globe
	if g.t < trace_from do return
	c := cell_of(followed)
	cr := g.crust[c]
	set := setting_of(c)
	if int(math.round(-g.t))%FRAME_EVERY != 0 && set == trace_last do return
	trace_last = set
	crust := fmt.tprintf("%s %.0f km%s", "continent" if cr.cont else "ocean floor", cr.thick, fmt.tprintf(", %.0f Myr old", g.t - cr.born) if !cr.cont else "")
	fmt.printfln("  %-8s %-6s %-30s %-11s %s", fmt.tprintf("%.0f", max(-g.t, 0)), fmt.tprintf("%d", g.plates[cr.plate].serial), crust, fmt.tprintf("%.0f m", g.h[c] - g.sea), set)
}
