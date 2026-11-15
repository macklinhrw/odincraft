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
	ready:      bool,   // formed: set once, by the thread that formed it, and read atomically (is_formed)
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

// The island whose region's square holds a point in the world, or nil: the open sea.
island_at :: proc(x, z: f64) -> ^Formed {
	for &f in formed {
		o, h := [2]f64{f64(f.island.origin.x), f64(f.island.origin.y)}, f.island.size/2
		if x >= o.x - h && x < o.x + h && z >= o.y - h && z < o.y + h do return &f
	}
	return nil
}

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
	if f == nil || !is_formed(f) do return SEA_BED
	bound(f)
	return height_at(x - f64(region.origin.x), z - f64(region.origin.y), cell)
}

// Islands waiting to be formed, nearest the start first, the next one to take, and whether play has begun.
Forming :: struct { list: []int, next: int, late: bool }

// Form the listed islands on up to `threads` threads of a priority, each saying one line as it is
// done; with `wait`, return when all are formed.
islands_form :: proc(list: []int, threads: int, priority: thread.Thread_Priority, wait: bool) {
	if len(list) == 0 do return
	q := new(Forming)
	q.list, q.late = list, !wait
	former :: proc(q: ^Forming) {
		for {
			i := sync.atomic_add(&q.next, 1)
			if i >= len(q.list) do return
			f := &formed[q.list[i]]
			quiet = true
			gen_init(f)
			quiet = false
			fmt.printfln("island %d: %s, its middle at %d, %d, %.1f km from the start; formed in %.2f s%s", f.island.id, f.region.kind, f.island.origin.x, f.island.origin.y,
				math.hypot(f64(f.island.origin.x - home.island.origin.x), f64(f.island.origin.y - home.island.origin.y))/1000, f.seconds, " in the background" if q.late else "")
			free_all(context.temp_allocator)
		}
	}
	pool := make([]^thread.Thread, min(threads, len(list)), context.temp_allocator)
	for &t in pool do t = thread.create_and_start_with_poly_data(q, former, priority = priority, self_cleanup = !wait)
	if wait do for t in pool do thread.join(t)
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
