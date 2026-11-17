package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import sdl "vendor:sdl3"

// The world in hand, made in stages off the frame's thread (docs/foundations/interface.md, section
// 5; step I-2). The game holds one world at a time: the known world of one seed (known.odin), the
// records of the islands near its start (archipelago.odin) and whichever of them are formed
// (regions.odin). The front door and the world's screen (door.odin, chart.odin) order a world here
// and go on drawing while it is made; each frame they read how far it has come.
//
//   the plates' history       350 million years of the whole planet (plates.odin), or read from build/worlds/
//   the region round the start  its last 20 million years again on the known world's own cells; the known
//                             world read from that, and the records of the islands near the start
//   the islands near the start  the start island and those within `near` km of it, formed side by side
//   the far islands           formed on three threads of low priority, while the player looks or plays
//
// Everything a stage does is the procedure the command line runs (known_make, archipelago_make,
// gen_init), so a world made from the front door is the world `--seed=` makes, bit for bit. What is
// new is who calls them and when: a thread of its own, which the frame never waits for.
//
// Forming threads are kept here so that they can be told to stop and waited for: an island in hand
// is always finished, since forming has no place to stop inside it. A world put down leaves its
// formed islands where they lie: their land is carved from blocks no one else may free (land.odin),
// about 40 MB an island, until islands are kept as summaries (ADR 0005, consequences).

Stage :: enum u8 { Plates, Region, Near, Far }
Stage_Row :: struct { name, makes, unit: string }
STAGES := [Stage]Stage_Row{
	.Plates = {"The plates' history", "The whole planet's plates, moved through 350 million years: where the continents, the trenches and the volcanoes came to lie.", "million years"},
	.Region = {"The region round the start", "The last 20 million years again, finer, over the 1,000 km the world knows; and from it where each island stands and of what kind.", "million years"},
	.Near   = {"The islands near the start", "The start island and those a boat could reach from it, formed as land: rock, rivers, woods, animals and named places.", "islands"},
	.Far    = {"The far islands", "The rest of the islands, formed while you look or play. The mainland is known from the plates' history and is not formed as land yet.", "islands"},
}

Making :: struct {
	seed:      u32,
	near_km:   f64,
	job:       ^thread.Thread,   // the thread making it; one at a time, each waiting for the one before
	// Written by that thread, read by the frame: each a word, stored whole.
	stage:     Stage,
	records:   bool,             // the known world is read and the islands' records made: the map can be drawn and an island asked about
	working:   bool,             // a job is under way
	stopped:   bool,             // it was told to stop, and has
	kept:      bool,             // the plates' history was read from where an earlier run kept it
	fresh:     bool,             // its records are being made: a world stopped now is begun again
	began:     time.Time,        // when the stage running began
	took:      [Stage]f64,       // seconds each stage took in this run; 0 for one not run
	near, far: []int,            // the islands that must be formed before the world is entered, the start first; and the rest, nearest first
	doing:     []i32,            // for each island, 1 while a thread forms it
	// The frame's own.
	mutex:     sync.Mutex,       // guards `order` and `records` together: a job an order has overtaken shows nothing
	order:     int,              // counts the worlds ordered
	seen:      [Stage]int,       // the furthest each stage has been seen to come, so that a figure never runs back
}
making: Making

// ---- forming threads --------------------------------------------------------------------------

// Islands waiting to be formed and the threads taking them, the next first.
Pool :: struct {
	mutex:   sync.Mutex,
	list:    [dynamic]int,
	next:    int,
	late:    bool,   // beside play or the map: each thread works alone and says a line for each island
	threads: []^thread.Thread,
}
forming: struct { mutex: sync.Mutex, pools: [dynamic]^Pool, stop: bool }   // the mutex guards the list of pools

// Form the listed islands on up to `threads` threads of a priority, as islands_form does
// (regions.odin), kept so that they can be waited for and stopped.
forming_begin :: proc(list: []int, threads: int, priority: thread.Thread_Priority, late: bool) {
	if len(list) == 0 do return
	p := new(Pool)
	append(&p.list, ..list)
	p.late = late
	p.threads = make([]^thread.Thread, min(threads, len(list)))
	for &t in p.threads do t = thread.create_and_start_with_poly_data(p, former, priority = priority)
	sync.guard(&forming.mutex)
	append(&forming.pools, p)
}

former :: proc(p: ^Pool) {
	alone = p.late
	for !sync.atomic_load(&forming.stop) {
		sync.lock(&p.mutex)
		i := p.list[p.next] if p.next < len(p.list) else -1
		p.next += 1
		sync.unlock(&p.mutex)
		if i < 0 do return
		f := &formed[i]
		if i < len(making.doing) do sync.atomic_store(&making.doing[i], 1)
		quiet = f != home   // the start island says its lines, as it does formed on the main thread
		gen_init(f)
		quiet = false
		if i < len(making.doing) do sync.atomic_store(&making.doing[i], 0)
		if p.late do island_say(f, " in the background")
		free_all(context.temp_allocator)
	}
}

// Wait for every island under way, and say a line for each of the listed, in the list's order.
forming_wait :: proc(list: []int = nil) {
	sync.lock(&forming.mutex)
	pools := slice.clone(forming.pools[:], context.temp_allocator)
	clear(&forming.pools)
	sync.unlock(&forming.mutex)
	for p in pools {
		for t in p.threads {
			thread.join(t)
			thread.destroy(t)
		}
		delete(p.threads)
		delete(p.list)
		free(p)
	}
	for i in list do if is_formed(&formed[i]) do island_say(&formed[i], "")
}

// No island is begun after this; those in hand are finished and waited for.
forming_stop :: proc() {
	sync.atomic_store(&forming.stop, true)
	forming_wait()
	sync.atomic_store(&forming.stop, false)
}

// Form the islands round one first: what is still waiting is taken nearest that island first.
forming_toward :: proc(island: int) {
	if island < 0 || island >= len(formed) do return
	@(static) to: [2]i32
	to = formed[island].island.origin
	sync.guard(&forming.mutex)
	for p in forming.pools do if p.late {
		sync.guard(&p.mutex)
		if p.next >= len(p.list) do continue
		slice.sort_by(p.list[p.next:], proc(a, b: int) -> bool {
			d :: proc(i: int) -> f64 { return math.hypot(f64(formed[i].island.origin.x - to.x), f64(formed[i].island.origin.y - to.y)) }
			return d(a) < d(b)
		})
	}
}

// ---- the world in hand ------------------------------------------------------------------------

// Metres between two islands' middles.
islands_apart :: proc(a, b: int) -> f64 {
	return math.hypot(f64(archipelago[a].origin.x - archipelago[b].origin.x), f64(archipelago[a].origin.y - archipelago[b].origin.y))
}

// Whether play can begin on an island: it is formed, and so is every island within `near` km of it.
world_enterable :: proc(island := 0) -> bool {
	if !sync.atomic_load(&making.records) || island < 0 || island >= len(formed) do return false
	for &f, i in formed do if !is_formed(&f) && islands_apart(i, island) <= making.near_km*1000 do return false
	return true
}

// How far a stage has come, in its own unit: `done` of `all`, and the islands being formed now.
// For the plates' history and the region it is how far the planet's clock has run, read as the
// history writes it: a figure for the eye, which nothing else is decided by.
making_progress :: proc(s: Stage) -> (done, all: int, now: [dynamic]int) {
	m := &making
	now = make([dynamic]int, context.temp_allocator)
	switch s {
	case .Plates:
		all = int(SPAN + SPIN_UP)
		done = all if m.stage > .Plates || regional.patch else clamp(int(SPAN + SPIN_UP + planet.t), 0, all) if m.working && planet.crust != nil else 0
	case .Region:
		all = int(REGION_SPAN)
		done = all if m.stage > .Region else clamp(int(REGION_SPAN + planet.t), 0, all) if regional.patch else 0
	case .Near, .Far:
		if !sync.atomic_load(&m.records) do return
		list := m.near if s == .Near else m.far
		all = len(list)
		for i in list {
			done += int(is_formed(&formed[i]))
			if sync.atomic_load(&m.doing[i]) != 0 do append(&now, i)
		}
	}
	m.seen[s] = max(m.seen[s], done)
	return m.seen[s], all, now
}

// Which stage is running, as the frame sees it: the region begins inside the history's own call.
making_stage :: proc() -> Stage {
	s := Stage(sync.atomic_load(cast(^u8)&making.stage))
	return .Region if s == .Plates && regional.patch else s
}

// Order a world: whatever is in hand is put down, and the world of `seed` is made on a thread of
// its own. The frame's thread calls this, having let go what it kept of the old one on the GPU
// (world_gpu_drop), and reads nothing of a world until `records` is set again.
world_open :: proc(seed: u32, near_km: f64) {
	m := &making
	sync.lock(&m.mutex)
	m.order += 1
	m.records, m.working, m.seen = false, true, {}
	sync.unlock(&m.mutex)
	sync.atomic_store(&forming.stop, true)   // the job before this one, if it is still waiting on islands, ends
	Order :: struct { seed: u32, near_km: f64, before: ^thread.Thread, fresh: bool, order: int }
	o := new(Order)
	o^ = {seed, near_km, m.job, true, m.order}
	if seed == m.seed && m.stopped && !m.fresh do o.fresh = false   // the same world, stopped with its records made: go on with it
	m.job = thread.create_and_start_with_poly_data(o, proc(o: ^Order) {
		m := &making
		defer free(o)
		if o.before != nil {
			thread.join(o.before)
			thread.destroy(o.before)
		}
		forming_stop()
		chart_painter_end()
		// Show what this job has made, unless another world has been ordered since.
		show :: proc(o: ^Order, records, working: bool) -> bool {
			m := &making
			sync.guard(&m.mutex)
			if m.order != o.order do return false
			m.records, m.working = records, working
			return true
		}
		if o.fresh {
			world_drop()
			m.seed, m.near_km, m.took, m.kept, m.stopped, m.fresh = o.seed, o.near_km, {}, false, false, true
			sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Plates))
			m.began = time.now()
			world_records(o.seed)
			m.kept = known.took == 0
			m.took[.Plates], m.took[.Region] = known.took - known.regional_took, known.regional_took
			if m.kept do m.took[.Region] = time.duration_seconds(time.since(m.began))   // what reading it back and making the records took
			world_lists(0, o.near_km)
			world_note()
			m.fresh = false
		}
		m.stopped = false
		if !show(o, true, true) do return
		chart_painter_begin()
		// The islands near the start, side by side; then the rest, beside whatever the player does.
		sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Near))
		m.began = time.now()
		left := make([dynamic]int, context.temp_allocator)
		for i in m.near do if !is_formed(&formed[i]) do append(&left, i)
		forming_begin(left[:], max(os.get_processor_core_count() - 1, 1), .Normal, false)
		sync.lock(&forming.mutex)
		near := forming.pools[0].threads if len(forming.pools) > 0 else nil
		sync.unlock(&forming.mutex)
		for t in near do thread.join(t)   // waited for here; forming_wait, which lets them go, is the next order's to call
		if world_enterable(0) {
			m.took[.Near] += time.duration_seconds(time.since(m.began))
			for i in m.near[1:] do island_say(&formed[i], "")
			sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Far))
			clear(&left)
			for i in m.far do if !is_formed(&formed[i]) do append(&left, i)
			forming_begin(left[:], 3, .Low, true)
		} else {
			m.stopped = true
		}
		show(o, true, false)
		free_all(context.temp_allocator)
	})
}

// Stop making the world in hand: no island is begun after those in hand. The plates' history, if
// it is running, runs to its end, since it has no place to stop; nothing is formed after it.
making_stop :: proc() {
	sync.atomic_store(&forming.stop, true)
	making.stopped = true
}

// Whether every island of the world in hand is formed.
world_whole :: proc() -> bool {
	if !sync.atomic_load(&making.records) do return false
	for &f in formed do if !is_formed(&f) do return false
	return true
}

// The world's records from its seed, as start-up makes them (main.odin): a record at the start's
// place for the wind, the known world, the islands near the start and who reached each.
world_records :: proc(s: u32) {
	world_seed = s
	seed = world_seed
	@(static) first: Formed   // static: the bound names keep pointing at it
	first = {}
	first.island, first.region.origin = {origin = {0, 0}, size = REFERENCE, seed = world_seed}, {0, 0}
	bind(&first)
	quiet = true
	region_init("")
	quiet = false
	known_make()
	archipelago_make(false)
	arrivals_make()
	formed = make([]Formed, len(archipelago))
	for &f, i in formed do f.island = archipelago[i]
	home = &formed[0]
}

// Which islands must be formed before play begins on one, that one first, and the rest, nearest first.
world_lists :: proc(island: int, near_km: f64) {
	m := &making
	delete(m.near); delete(m.far); delete(m.doing)
	m.near_km = near_km
	m.doing = make([]i32, len(formed))
	@(static) from: int
	from = island
	others := make([dynamic]int, context.temp_allocator)
	for _, i in formed do if i != island do append(&others, i)
	slice.sort_by(others[:], proc(a, b: int) -> bool { return islands_apart(a, from) < islands_apart(b, from) })
	soon := 0
	for soon < len(others) && islands_apart(others[soon], island) <= near_km*1000 do soon += 1
	m.near = make([]int, soon + 1)
	m.near[0] = island
	copy(m.near[1:], others[:soon])
	m.far = slice.clone(others[soon:])
}

// Put the world in hand down: the known world's own arrays are freed; the islands formed stay where
// they lie (the top of this file), and so does their list, which threads that read them still point into.
world_drop :: proc() {
	k := &known
	delete(k.samples); delete(k.mass); delete(k.inland); delete(k.past)
	delete(k.vents); delete(k.hotspots); delete(k.masses); delete(k.chains)
	for &f in k.feet do delete(f)
	for &t in k.tracks do delete(t)
	k^ = {}
	formed, home = nil, nil
	clear(&archipelago)
}

// ---- the worlds this machine has made ---------------------------------------------------------

// A world kept on disk: its seed, whether its history is kept as this build of the game makes it,
// and what was written down of it when it was last made.
Kept_World :: struct {
	seed:   u32,
	fresh:  bool,       // its history can be read back; otherwise an earlier build made it, and it is run again
	says:   [dynamic]string,   // what is known of it, a sentence a line
	kept:   time.Time,  // when its history was kept
}

worlds_dir :: proc() -> string { return fmt.tprintf("%s/worlds", os.dir(os.args[0])) }
world_note_path :: proc(s: u32) -> string { return fmt.tprintf("%s/world-%d.txt", worlds_dir(), s) }

// The worlds in build/worlds/, lowest seed first: every seed with a history kept there.
worlds_kept :: proc(allocator := context.temp_allocator) -> []Kept_World {
	context.allocator = allocator
	out := make([dynamic]Kept_World)
	files, err := os.read_all_directory_by_path(worlds_dir(), allocator)
	if err != nil do return nil
	was := world_seed
	for f in files {
		name := f.name
		if !strings.has_prefix(name, "known-") || !strings.has_suffix(name, ".bin") do continue
		parts := strings.split(name[len("known-"):len(name) - len(".bin")], "-")
		if len(parts) != 2 do continue
		s, ok := strconv.parse_uint(parts[0], 10)
		if !ok do continue
		at := -1
		for w, i in out do if w.seed == u32(s) do at = i
		if at < 0 {
			append(&out, Kept_World{seed = u32(s)})
			at = len(out) - 1
		}
		world_seed = u32(s)   // known_path names the file by the world's seed
		if strings.has_suffix(known_path(), name) do out[at].fresh, out[at].kept = true, f.modification_time
		else if !out[at].fresh do out[at].kept = f.modification_time
	}
	world_seed = was
	for &w in out {
		data, bad := os.read_entire_file(world_note_path(w.seed), allocator)
		if bad != nil do continue
		text := string(data)
		for line in strings.split_lines_iterator(&text) do if line != "" do append(&w.says, line)
	}
	slice.sort_by(out[:], proc(a, b: Kept_World) -> bool { return a.seed < b.seed })
	return out[:]
}

// What is known of the world in hand once its records are made, kept beside its history so that the
// list of worlds can say it without making the world again: a sentence a line.
world_note :: proc() {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintln(&b, world_says())
	fmt.sbprintln(&b, start_says())
	_ = os.make_directory(worlds_dir())
	_ = os.write_entire_file(world_note_path(world_seed), b.buf[:])
}

// The islands near the start in a sentence: how many, and of what kinds.
world_says :: proc() -> string {
	by_kind: [len(KINDS)]int
	for is in archipelago do by_kind[is.kind] += 1
	b := strings.builder_make(context.temp_allocator)
	kinds := 0
	for n in by_kind do kinds += int(n > 0)
	said := 0
	for n, k in by_kind do if n > 0 {
		fmt.sbprintf(&b, "%s%s of %s", "" if said == 0 else " and " if said == kinds - 1 else ", ", number_words(n), kind_words(k))
		said += 1
	}
	ashore := f64(1e12)
	o := world_frame.origin
	for c in continent.coast do ashore = min(ashore, math.hypot(c.x - o.x, c.y - o.y))
	land := fmt.tprintf("off a mainland whose coast lies %.0f km away", ashore/1000) if ashore < 1.5e6 else "with no mainland in the known world"
	return fmt.tprintf("%s island%s near the start, %s: %s.", capital(number_words(len(archipelago))), "" if len(archipelago) == 1 else "s", land, strings.to_string(b))
}

// Where the party lands, in a sentence.
start_says :: proc() -> string {
	is := archipelago[0]
	return fmt.tprintf("The start is an island of %s, %.0f km across, on the %s at %.0f° N.", kind_words(is.kind), is.size/1000, SETTINGS[is.setting], world_frame.latitude)
}

// What each kind of island is, in words for a person: "an island of ...", and what made it so
// (KINDS, land.odin, whose rows these follow by name).
Kind_Said :: struct { name, of, made: string }
KINDS_SAID := [?]Kind_Said{
	{"ridge", "one long ridge", "It rose for three to four million years as one range, and the sea then rose a little way into the mouths of its valleys, leaving coves between the cliffs."},
	{"inlets", "drowned valleys", "A ridge island the sea rose more than a hundred metres into when the ice last melted: its valleys are long branching inlets between steep spurs, and the rivers have filled the head of each with a flat."},
	{"cone", "one volcano", "One vent built it out of the sea from lava and ash in a few tens of thousands of years, and the sea and its streams have cut it since into a wall of cliffs round gorges. It is the hard kind to live on."},
	{"crater", "a fallen crater", "A steep cone of lava and ash whose top fell in after a last eruption, leaving a rim round a closed floor, where a small cone has grown."},
	{"domes", "lava domes", "A vent spread a low fan of pumice and ash, and stiff pale lava then piled steep domes on it, with bays where the sea lies between them."},
	{"worn", "worn hills", "It rose as a ridge island does, then stopped rising; the sea came into its valleys, and the land has worn down since to low round hills about wide bays."},
	{"raised", "raised terraces", "The sea fell twice late in its rise and bared the platform the waves had cut, so an old cliff stands behind a terrace, and the streams have cut back into it."},
	{"reef", "raised reef", "A bank in a warm sea that rose a ring at a time while coral filled each band the sea flooded: a flight of terraces round its oldest flat. Rain sinks into the reef, so no stream crosses it."},
}
kind_said :: proc(k: int) -> Kind_Said {
	for row in KINDS_SAID do if row.name == KINDS[k].name do return row
	return {KINDS[k].name, KINDS[k].name, ""}
}
kind_words :: proc(k: int) -> string { return kind_said(k).of }

// A world made by start-up itself (main.odin) is the world in hand from here on, with the island
// start-up acts on as its start: so that play can be left for the world's screen.
world_adopt :: proc(island: int, near_km: f64) {
	m := &making
	m.seed, m.kept = world_seed, known.took == 0
	m.took[.Plates], m.took[.Region] = known.took - known.regional_took, known.regional_took
	world_lists(island, near_km)
	sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Far))
	sync.atomic_store(&m.records, true)
}

// Let go what a game held once it is left for the world's screen or the front door: every chunk's
// mesh, water and plants on the GPU, the block volumes, and the simulated water. The world's
// threads have ended (world_destroy).
game_end :: proc(w: ^World, g: ^Gpu) {
	for _, c in w.chunks {
		for b in ([3]^sdl.GPUBuffer{c.buffer, c.water, c.plant_buf}) do if b != nil do sdl.ReleaseGPUBuffer(g.dev, b)
		delete(c.plants); delete(c.blocks); delete(c.under)
		free(c)
	}
	delete(w.chunks)
	for _, e in w.edits do delete(e)
	delete(w.edits)
	wt := &w.water
	delete(wt.floor); delete(wt.depth); delete(wt.hold); delete(wt.flow_x); delete(wt.flow_z)
	delete(wt.before); delete(wt.shown); delete(wt.sea); delete(wt.still); delete(wt.roof)
	sdl.ReleaseGPUTexture(g.dev, wt.mask)
	sdl.ReleaseGPUBuffer(g.dev, wt.calm)
	clear(&g.cap_list)
	g.caps_level, g.caps_volume = min(i32), -1
	free(w)
}
