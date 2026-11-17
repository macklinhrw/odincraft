package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math"
import "core:os"
import "core:sync"
import "core:thread"
import sdl "vendor:sdl3"

// Many islands in one world. Everything formed for an island's region is held in one record,
// `Formed`, one for each island of the archipelago. Each system still reads its own part under
// its own name, `region`, `land`, `rivers` and the rest, as when there was one island: each is a
// pointer that a thread binds to the region in hand (`bind`) when it forms an island, builds a
// chunk (column by column, where a chunk spans two regions or the open sea), poses an island's
// creatures or answers --why. An island is formed on any thread from its record and seed alone,
// so it comes out the same alone or beside others (foundations/world-frame.md, D3). Between the
// regions lies the open sea, its floor level with every region's rim (SEA_BED).
Formed :: struct {
	island:     Island,
	region:     Region,
	land:       Land,
	rocks:      Rocks,
	rivers:     Rivers,
	landslide:  Slide,
	hollows:    [dynamic]Hollow,
	pillars:    [dynamic]Pillar,
	trails:     Trails,
	fauna:      Fauna,
	candidates: [dynamic]Candidate,
	places:     [dynamic]Place,
	survey:     Survey,
	seconds:    f64,    // how long it took to form
	ready:      bool,   // formed: set by the thread that formed it, and read atomically (is_formed)
	mass:       ^Landmass,   // a piece of a landmass: the landmass (continents.odin); nil on an island
	drawn:      bool,   // a piece: the frame has seen it formed, and built again what was drawn of it from far off
	// Put on the GPU by the frame thread once formed (islands_upload, render.odin).
	ribbon, falls:             ^sdl.GPUBuffer,   // its rivers' water surface, and its falling water
	ribbon_count, falls_count: u32,
	lifted:                    ^sdl.GPUTexture,  // the field `lifted`, for the cloud cap
}
formed: []Formed   // one for each island, in the archipelago's order
home:   ^Formed    // the start island, which the frame thread reads unless it binds another
world_seed := u32(7)   // the world's seed (--seed=), from which the archipelago is made; the weather reads it

@(thread_local) here:       ^Formed
@(thread_local) region:     ^Region
@(thread_local) land:       ^Land
@(thread_local) rocks:      ^Rocks
@(thread_local) rivers:     ^Rivers
@(thread_local) landslide:  ^Slide
@(thread_local) hollows:    ^[dynamic]Hollow
@(thread_local) pillars:    ^[dynamic]Pillar
@(thread_local) trails:     ^Trails
@(thread_local) fauna:      ^Fauna
@(thread_local) candidates: ^[dynamic]Candidate
@(thread_local) places:     ^[dynamic]Place
@(thread_local) survey:     ^Survey

// Read island `f` on this thread from now on; returns the island read before.
bind :: proc(f: ^Formed) -> (was: ^Formed) {
	was, here = here, f
	if f == nil do return
	region, land, rocks, rivers, landslide = &f.region, &f.land, &f.rocks, &f.rivers, &f.landslide
	hollows, pillars, trails, fauna = &f.hollows, &f.pillars, &f.trails, &f.fauna
	candidates, places, survey, seed = &f.candidates, &f.places, &f.survey, f.island.seed
	return
}

// Read island `f` until the end of the caller's scope.
@(deferred_out=bind)
bound :: proc(f: ^Formed) -> ^Formed { return bind(f) }

is_formed :: proc(f: ^Formed) -> bool { return sync.atomic_load_explicit(&f.ready, .Acquire) }

// The island whose region's square holds a point in the world, or the piece of the landmass whose
// land does (continents.odin), or nil: the open sea.
island_at :: proc(x, z: f64) -> ^Formed {
	for &f in formed[:islands_count()] {
		o, h := [2]f64{f64(f.island.origin.x), f64(f.island.origin.y)}, f.island.size/2
		if x >= o.x - h && x < o.x + h && z >= o.y - h && z < o.y + h do return &f
	}
	if m, p := mass_piece(x, z); m != nil do return &formed[m.first + p]
	return nil
}

// The islands' records in `formed`, before the landmass's pieces, whose squares overlap.
islands_count :: #force_inline proc() -> int { return len(archipelago) }

// Bind the island under a point in the world; false at the open sea, where the binding is left.
bind_at :: proc(x, z: f64) -> bool {
	f := island_at(x, z)
	if f != nil && f != here do bind(f)
	return f != nil
}

// Metres from a point in the world to an island's region, 0 inside it.
off_island :: proc(f: ^Formed, x, z: f64) -> f64 {
	o, h := [2]f64{f64(f.island.origin.x), f64(f.island.origin.y)}, f.island.size/2
	return math.hypot(max(abs(x - o.x) - h, 0), max(abs(z - o.y) - h, 0))
}

// The formed island whose region is nearest a point in the world.
island_near :: proc(x, z: f64) -> (near: ^Formed) {
	for &f in formed do if is_formed(&f) && (near == nil || off_island(&f, x, z) < off_island(near, x, z)) do near = &f
	return
}

// The ground's height at a point in the world as seen at a cell size: the island's whose region
// holds it, or the open sea's floor where none does or it is not yet formed.
height_in_world :: proc(x, z, cell: f64) -> f32 {
	f := island_at(x, z)
	if f != nil && !is_formed(f) && f.mass != nil {
		h, _, _ := far_ground(f.mass, x, z)
		return max(h, SEA_BED)
	}
	if f == nil || !is_formed(f) do return SEA_BED
	bound(f)
	return height_at(x - f64(region.origin.x), z - f64(region.origin.y), cell)
}

// Islands waiting to be formed, nearest the start first, the next one to take, and whether play has begun.
Forming :: struct { list: []int, next: int, late: bool }

// Form the listed islands on up to `threads` threads of a priority. Those formed beside play
// (`late`) work alone and each say one line when done; the rest are waited for by `islands_done`,
// which says theirs.
islands_form :: proc(list: []int, threads: int, priority: thread.Thread_Priority, late: bool) -> (pool: []^thread.Thread) {
	if len(list) == 0 do return
	q := new(Forming)
	q.list, q.late = list, late
	former :: proc(q: ^Forming) {
		alone = q.late
		for {
			i := sync.atomic_add(&q.next, 1)
			if i >= len(q.list) do return
			f := &formed[q.list[i]]
			quiet = true
			gen_init(f)
			quiet = false
			if q.late do island_say(f, " in the background")
			free_all(context.temp_allocator)
		}
	}
	pool = make([]^thread.Thread, min(threads, len(list)))
	for &t in pool do t = thread.create_and_start_with_poly_data(q, former, priority = priority, self_cleanup = late)
	if late {
		delete(pool)
		pool = nil
	}
	return
}

// Wait for islands being formed, and say a line for each, in the list's order.
islands_done :: proc(pool: []^thread.Thread, list: []int) {
	for t in pool do thread.join(t)
	for i in list do island_say(&formed[i], "")
	delete(pool)
}

island_say :: proc(f: ^Formed, how: string) {
	fmt.printfln("island %d: %s, its middle at %d, %d, %.1f km from the start; formed in %.2f s%s", f.island.id, f.region.kind, f.island.origin.x, f.island.origin.y,
		math.hypot(f64(f.island.origin.x - home.island.origin.x), f64(f.island.origin.y - home.island.origin.y))/1000, f.seconds, how)
}

// Work inside one island, shared among threads. A loop whose every pass writes only its own cells
// is cut into parts; the thread forming the island works through the parts, and so does every
// helper with nothing else to do, each reading the same island. A part comes out the same
// whichever thread works it, so an island comes out the same alone, beside others and on any
// number of threads. An island formed beside play is worked by its own thread alone, so that play
// keeps its cores.
Share :: struct {
	work:       proc(data: rawptr, lo, hi: int),
	data:       rawptr,
	island:     ^Formed,
	n, part:    int,
	next, done: int,   // parts taken and parts finished
	users:      int,   // helpers holding it
}
helping: struct { mutex: sync.Mutex, wake: sync.Cond, shares: [dynamic]^Share, helpers: int }
@(thread_local) alone: bool

// Run `work` over 0..<n in parts of `part`, on this thread and any helper free.
shared :: proc(n, part: int, data: ^$T, work: proc(data: ^T, lo, hi: int)) {
	if alone || n <= part {
		work(data, 0, n)
		return
	}
	s := Share{work = transmute(proc(rawptr, int, int))work, data = data, island = here, n = n, part = part}
	sync.lock(&helping.mutex)
	if helping.helpers == 0 {
		helping.helpers = max(os.get_processor_core_count() - 1, 1)
		for _ in 0..<helping.helpers do thread.create_and_start(helper, self_cleanup = true)
	}
	append(&helping.shares, &s)
	sync.unlock(&helping.mutex)
	sync.cond_broadcast(&helping.wake)
	parts_work(&s)
	unshare(&s)
	for sync.atomic_load(&s.done) < (n + part - 1)/part || sync.atomic_load(&s.users) > 0 do thread.yield()
}

parts_work :: proc(s: ^Share) {
	for {
		i := sync.atomic_add(&s.next, 1)
		if i*s.part >= s.n do return
		s.work(s.data, i*s.part, min(i*s.part + s.part, s.n))
		sync.atomic_add(&s.done, 1)
	}
}

// No more parts to take.
unshare :: proc(s: ^Share) {
	sync.lock(&helping.mutex)
	for t, i in helping.shares do if t == s {
		ordered_remove(&helping.shares, i)
		break
	}
	sync.unlock(&helping.mutex)
}

helper :: proc() {
	for {
		sync.lock(&helping.mutex)
		for len(helping.shares) == 0 do sync.cond_wait(&helping.wake, &helping.mutex)
		s := helping.shares[0]
		sync.atomic_add(&s.users, 1)
		sync.unlock(&helping.mutex)
		bind(s.island)
		parts_work(s)
		unshare(s)
		sync.atomic_sub(&s.users, 1)
	}
}

// A thread forming an island beside another or beside play prints none of its start-up lines:
// standard output passes on what every other thread writes and drops what a quiet one does.
@(thread_local) quiet: bool
stdout_real:  ^os.File
stdout_quiet: os.File
quiet_init :: proc() {
	stdout_real = os.stdout
	stdout_quiet = stdout_real^
	stdout_quiet.stream.procedure = proc(_: rawptr, mode: os.File_Stream_Mode, p: []byte, offset: i64, whence: io.Seek_From, a: runtime.Allocator) -> (i64, os.Error) {
		if quiet && mode == .Write do return i64(len(p)), nil
		return stdout_real.stream.procedure(stdout_real, mode, p, offset, whence, a)
	}
	os.stdout = &stdout_quiet
}
