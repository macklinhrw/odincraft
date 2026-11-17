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
//   the large lands           every land mass larger than a region (continents.odin): the coarse stage of
//                             each, the whole of it on 64 m cells, formed once and kept in build/worlds/.
//                             One that is kept is read back; one that is not is formed if it lies within
//                             reach of the start, and else stays as the history has it
//   the islands near the start  the start island and those within `near` km of it, formed side by side, and
//                             the large lands' pieces within reach of it
//   the far islands           formed on three threads of low priority, while the player looks or plays, and
//                             the large lands' pieces within reach of the view kept formed on one more
//
// Everything a stage does is the procedure the command line runs (known_make, archipelago_make,
// gen_init), so a world made from the front door is the world `--seed=` makes, bit for bit. What is
// new is who calls them and when: a thread of its own, which the frame never waits for.
//
// Forming threads are kept here so that they can be told to stop and waited for: an island in hand
// is always finished, since forming has no place to stop inside it. A world put down leaves its
// formed islands where they lie: their land is carved from blocks no one else may free (land.odin),
// about 40 MB an island, until islands are kept as summaries (ADR 0005, consequences).

Stage :: enum u8 { Plates, Region, Mainland, Near, Far }
Stage_Row :: struct { name, makes, unit: string }
STAGES := [Stage]Stage_Row{
	.Plates = {"The plates' history", "The whole planet's plates, moved through 350 million years: where the continents, the trenches and the volcanoes came to lie.", "million years"},
	.Region = {"The region round the start", "The last 20 million years again, finer, over the 1,000 km the world knows; and from it where each island stands and of what kind.", "million years"},
	.Mainland = {"The mainland", "The land larger than an island that lies within reach of the start, the whole of it on cells 64 m across: its ranges, its valleys and where its rivers run. It is made once for a world and kept. Large lands farther off stay as the plates' history has them.", "steps"},
	.Near   = {"The islands near the start", "The start island and those a boat could reach from it, formed as land: rock, rivers, woods, animals and named places.", "islands"},
	.Far    = {"The far islands", "The rest of the islands, formed while you look or play, and the mainland's land near the view.", "islands"},
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
	massed:    bool,             // the large lands' stage has been gone through, whatever it came to
	continent: int,              // which large lands are formed as land (--continent): -1 those within reach of the start, 1 every one, 0 none
	waiting:   bool,             // a world is ordered and the one before it is still being put down: the stages are not yet its own
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

// Islands waiting to be formed and the threads taking them, the next first. The large lands' pieces,
// whose places in `formed` come after the islands', are formed by their own rule, each after the
// pieces it waits on (mass_form, masses_keep, continents.odin), and told to stop by the same word.
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

// No island or piece is begun after this; those in hand are finished and waited for.
forming_stop :: proc() {
	sync.atomic_store(&forming.stop, true)
	forming_wait()
	masses_end()
	sync.atomic_store(&forming.stop, false)
}

// Form the islands round one first: what is still waiting is taken nearest that island first.
forming_toward :: proc(island: int) {
	if island < 0 || island >= islands_count() do return
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

// The world's regions (regions.odin): one for each island near the start, in a list with room after
// them for the large lands' pieces, and then those of each large land whose coarse stage is at hand
// already. Called once for a world, before anything of it is formed or read.
regions_make :: proc() -> (pieces: int) {
	regions_begin(len(archipelago))
	for &f, i in formed do f.island = archipelago[i]
	home = &formed[0]
	for &m in lands do if m.ready do pieces += regions_add(&m)
	return
}

// A large land's pieces are regions from here on, after those the list holds: its coarse stage has cut
// them (mass_pass). It can be called by any thread while islands and pieces are formed and read and
// frames are drawn, since the list grows in place (regions.odin): each record is made whole before
// the list's length is stored, and the land is `listed` only after that, which is what says a point
// is one of its pieces' (mass_piece). Returns how many were added.
regions_add :: proc(m: ^Landmass) -> int {
	sync.guard(&regions_mutex)
	if mass_listed(m) || !m.ready do return 0
	count := len(m.cut.size)
	m.first = len(formed)
	for &f, p in regions_room(count) {
		o, size := piece_square(m, i32(p))
		f.island = {id = m.first + p, origin = o, size = size, kind = mass_kind(), seed = m.seed, setting = .Continent}
		f.mass = m
	}
	regions_show(count)
	sync.atomic_store_explicit(&m.listed, true, .Release)
	if m.landing_piece >= 0 do fmt.printfln("land mass %d: its %d pieces are regions; it is come ashore at %.0f, %.0f, on piece %d", m.mass, count, m.landing.x, m.landing.y, m.landing_piece)
	return count
}

// ---- the world in hand ------------------------------------------------------------------------

// Metres between two islands' middles.
islands_apart :: proc(a, b: int) -> f64 {
	return math.hypot(f64(archipelago[a].origin.x - archipelago[b].origin.x), f64(archipelago[a].origin.y - archipelago[b].origin.y))
}

// Whether play can begin on an island: it is formed, and so are every island within `near` km of it
// and every piece of the large lands within reach of it, once their stage has been gone through.
world_enterable :: proc(island := 0) -> bool {
	if !sync.atomic_load(&making.records) || !sync.atomic_load(&making.massed) do return false
	if li := land_of(island); li >= 0 {   // a large land, walked: its pieces round where it is come ashore are formed
		m := &lands[li]
		return mass_listed(m) && m.landing_piece >= 0 && masses_near(m.landing, WALK_REACH) == 0
	}
	if island < 0 || island >= islands_count() do return false
	for &f, i in formed[:islands_count()] do if !is_formed(&f) && islands_apart(i, island) <= making.near_km*1000 do return false
	o := archipelago[island].origin
	return masses_near({f64(o.x), f64(o.y)}, min(making.near_km*1000, NEAR_REACH)) == 0
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
		// The planet's clock stands at nought before its history is begun and when it is done: only a time before today is read.
		done = all if m.stage > .Plates || regional.patch else clamp(int(SPAN + SPIN_UP + planet.t), 0, all) if m.working && planet.crust != nil && planet.t < -0.01 else 0
	case .Region:
		all = int(REGION_SPAN)
		done = all if m.stage > .Region else clamp(int(REGION_SPAN + planet.t), 0, all) if regional.patch && planet.t < -0.01 else 0
	case .Mainland:   // the steps of the coarse stages being formed; none where every large land is read back or left as the history has it
		all = int(sync.atomic_load(&lands_state.steps))
		done = min(int(sync.atomic_load(&lands_state.step)), all)
		return
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
world_open :: proc(seed: u32, near_km: f64, continent: int) {
	m := &making
	m.continent = continent
	sync.lock(&m.mutex)
	m.order += 1
	m.records, m.working, m.seen = false, true, {}
	sync.unlock(&m.mutex)
	sync.atomic_store(&forming.stop, true)   // the job before this one, if it is still waiting on islands, ends
	Order :: struct { seed: u32, near_km: f64, before: ^thread.Thread, fresh: bool, order: int }
	o := new(Order)
	o^ = {seed, near_km, m.job, true, m.order}
	if seed == m.seed && m.stopped && !m.fresh do o.fresh = false   // the same world, stopped with its records made: go on with it
	if o.fresh {   // the world asked for is the one spoken of from now on, though nothing of it is known yet
		m.seed = seed
		sync.atomic_store(&m.massed, false)
		sync.atomic_store(&m.waiting, true)
	}
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
			sync.atomic_store(&m.massed, false)
			m.seed, m.near_km, m.took, m.kept, m.stopped, m.fresh = o.seed, o.near_km, {}, false, false, true
			sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Plates))
			m.began = time.now()
			sync.atomic_store(&m.waiting, false)   // from here the stages told are this world's
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
		// The large lands: the coarse stage of each that is kept, read back, and of each within reach of
		// the start, formed, which is long the first time. Their pieces are then regions after the
		// islands', added to the list where it stands (regions_add), and the map's painter is begun
		// again for their pictures.
		if !sync.atomic_load(&m.massed) {
			sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Mainland))
			m.began = time.now()
			sync.atomic_store(&lands_state.leave, false)
			if lands_pass(nil, m.continent == 1, m.continent == 0) > 0 {
				chart_painter_end()
				for &l in lands do regions_add(&l)
				chart_painter_begin()
			}
			m.took[.Mainland] = time.duration_seconds(time.since(m.began))
			sync.atomic_store(&m.massed, true)
		}
		// The islands near the start, side by side, and the large lands' pieces within reach of it; then
		// the rest, beside whatever the player does.
		sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Near))
		m.began = time.now()
		left := make([dynamic]int, context.temp_allocator)
		for i in m.near do if !is_formed(&formed[i]) do append(&left, i)
		forming_begin(left[:], max(os.get_processor_core_count() - 1, 1), .Normal, false)
		sync.lock(&forming.mutex)
		near := forming.pools[0].threads if len(forming.pools) > 0 else nil
		sync.unlock(&forming.mutex)
		for t in near do thread.join(t)   // waited for here; forming_wait, which lets them go, is the next order's to call
		start := [2]f64{f64(archipelago[0].origin.x), f64(archipelago[0].origin.y)}
		if !sync.atomic_load(&forming.stop) do masses_form(start, min(m.near_km*1000, NEAR_REACH))
		if world_enterable(0) {
			m.took[.Near] += time.duration_seconds(time.since(m.began))
			for i in m.near[1:] do island_say(&formed[i], "")
			sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Far))
			clear(&left)
			for i in m.far do if !is_formed(&formed[i]) do append(&left, i)
			forming_begin(left[:], 3, .Low, false)
			mass_focus = start
			masses_keep()
		} else {
			m.took[.Near] += time.duration_seconds(time.since(m.began))
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

// Whether every island of the world in hand is formed, and the large lands' stage gone through.
world_whole :: proc() -> bool {
	if !sync.atomic_load(&making.records) || !sync.atomic_load(&making.massed) do return false
	for &f in formed[:islands_count()] do if !is_formed(&f) do return false
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
	names_make()
	lands_make()   // the large lands' records; their coarse stages are a stage of their own
	regions_make()
}

// Which islands must be formed before play begins on one, that one first, and the rest, nearest first.
world_lists :: proc(island: int, near_km: f64) {
	m := &making
	delete(m.near); delete(m.far); delete(m.doing)
	m.near_km = near_km
	m.doing = make([]i32, len(archipelago))
	@(static) from: int
	from = island
	others := make([dynamic]int, context.temp_allocator)
	for _, i in archipelago do if i != island do append(&others, i)
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
	lands_drop()
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
	is := archipelago[0]
	ashore := f64(1e12)
	for c in continent.coast do ashore = min(ashore, math.hypot(c.x - world_frame.origin.x, c.y - world_frame.origin.y))
	fmt.sbprintfln(&b, "Start: %s, %s at %.0f° N", isle_name(0), kind_said(is.kind).one, world_frame.latitude)
	fmt.sbprintfln(&b, "Islands: %s near the start", number_words(len(archipelago)))
	if ashore < 1.5e6 do fmt.sbprintfln(&b, "Mainland: %.0f km off", ashore/1000)
	else do fmt.sbprintln(&b, "Mainland: none in the known world")
	_ = os.make_directory(worlds_dir())
	_ = os.write_entire_file(world_note_path(world_seed), b.buf[:])
}

// Where the party lands, in a sentence.
start_says :: proc() -> string {
	is := archipelago[0]
	return fmt.tprintf("The start is %s, %s %.0f km across, on the %s at %.0f° N.", isle_name(0), kind_said(is.kind).one, is.size/1000, SETTINGS[is.setting], world_frame.latitude)
}

// What each kind of island is, in words for a person: one of them, several, the word under it on
// the map, and what made it so (KINDS, land.odin, whose rows these follow by name).
Kind_Said :: struct { name, one, many, short, made: string }
KINDS_SAID := [?]Kind_Said{
	{"ridge", "a ridge island", "ridge islands", "ridge", "It rose for three to four million years as one long range, and the sea then rose a little way into the mouths of its valleys, leaving coves between the cliffs."},
	{"inlets", "an island of drowned valleys", "islands of drowned valleys", "drowned valleys", "A ridge island the sea rose more than a hundred metres into when the ice last melted: its valleys are long branching inlets between steep spurs, and the rivers have filled the head of each with a flat."},
	{"cone", "a volcano island", "volcano islands", "volcano", "One vent built it out of the sea from lava and ash in a few tens of thousands of years, and the sea and its streams have cut it since into a wall of cliffs round gorges. It is the hard kind to live on."},
	{"crater", "a crater island", "crater islands", "crater", "A steep cone of lava and ash whose top fell in after a last eruption, leaving a rim round a closed floor, where a small cone has grown."},
	{"domes", "an island of lava domes", "islands of lava domes", "lava domes", "A vent spread a low fan of pumice and ash, and stiff pale lava then piled steep domes on it, with bays where the sea lies between them."},
	{"worn", "a worn island", "worn islands", "worn hills", "It rose as a ridge island does, then stopped rising; the sea came into its valleys, and the land has worn down since to low round hills about wide bays."},
	{"raised", "a terraced island", "terraced islands", "terraces", "The sea fell twice late in its rise and bared the platform the waves had cut, so an old cliff stands behind a terrace, and the streams have cut back into it."},
	{"reef", "a reef island", "reef islands", "raised reef", "A bank in a warm sea that rose a ring at a time while coral filled each band the sea flooded: a flight of terraces round its oldest flat. Rain sinks into the reef, so no stream crosses it."},
}
kind_said :: proc(k: int) -> Kind_Said {
	for row in KINDS_SAID do if row.name == KINDS[k].name do return row
	n := KINDS[k].name
	return {n, n, n, n, ""}
}

// ---- names ------------------------------------------------------------------------------------

// An island's name, by the rule the places on an island are named by (places.odin): a word drawn
// from a cause, then a word of its own kind, each drawn by the island's own key, and no word used by
// two islands near one start. The causes are what the world knows of an island before it is formed,
// so it has its name on the map from the first: an animal that reached it, where it lies among the
// others and toward the wind, its size among them, the age of its land, and the colour of the rock
// its kind is built of.
ISLE_WORDS := [?]struct { kind: string, words: []string }{
	{"ridge", {"Ridge", "Back", "Rigg", "Spine"}}, {"inlets", {"Sounds", "Havens", "Firths", "Arms"}}, {"cone", {"Cone", "Pike", "Mount"}},
	{"crater", {"Cauldron", "Ring", "Bowl"}}, {"domes", {"Domes", "Knolls", "Humps"}}, {"worn", {"Downs", "Wolds", "Hills"}},
	{"raised", {"Steps", "Benches", "Terraces", "Shelves"}}, {"reef", {"Reef", "Cay", "Key"}},
}
isle_names: [dynamic]string   // by island, made once with a world's records and read only after

names_make :: proc() {
	for n in isle_names do delete(n)
	clear(&isle_names)
	n := len(archipelago)
	if n == 0 do return
	middle: [2]f64
	sizes, ages := make([]f64, n, context.temp_allocator), make([]f32, n, context.temp_allocator)
	for is, i in archipelago {
		middle += [2]f64{f64(is.origin.x), f64(is.origin.y)}/f64(n)
		sizes[i], ages[i] = is.size, is.age
	}
	slice.sort(sizes)
	slice.sort(ages)
	Word :: struct { w: string, weight: f32 }
	for is, i in archipelago {
		words := make([dynamic]Word, context.temp_allocator)
		for row, d in DISPERSAL do if a := arrivals[i][d]; a.reached {   // an animal names an island the more, the fewer islands it reached
			with := 0
			for _, j in archipelago do with += int(arrivals[j][d].reached)
			if row.way == .Drifted do continue   // a fish in its streams names no island: a sailor names what is seen from the sea
			name, _, last := strings.partition(row.name, " ")
			append(&words, Word{capital(last if last != "" else name), 3 if with*3 <= n else 0.4})
		}
		off := [2]f64{f64(is.origin.x), f64(is.origin.y)} - middle
		if far := math.hypot(off.x, off.y); far <= 12_000 do append(&words, Word{"Middle", 2})
		else {
			bearing := math.mod(math.to_degrees(math.atan2(off.x, -off.y)) + 360, 360)
			quarters := [4]string{"North", "East", "South", "West"}
			append(&words, Word{quarters[int(bearing + 45)/90%4], 1})
			toward := abs(math.mod(bearing - world_frame.wind + 540, 360) - 180)   // degrees between where it lies and where the wind comes from
			if toward < 40 do append(&words, Word{"Weather", 1})
			if toward > 140 do append(&words, Word{"Lee", 1})
		}
		if n >= 3 {
			if is.size > 1.3*sizes[n/2] do append(&words, Word{"Great", 2})
			if is.size < 0.75*sizes[n/2] do append(&words, Word{"Little", 1.5})
			if is.age == ages[0] && is.age < 1 do append(&words, Word{"New", 2})
			if is.age == ages[n - 1] && ages[n - 1] > 1.5*ages[n/2] do append(&words, Word{"Old", 1.5})
		}
		switch KINDS[is.kind].name {
		case "domes": append(&words, Word{"Pale", 1.5})
		case "reef":  append(&words, Word{"White", 1.5})
		case "cone", "crater": append(&words, Word{"Black", 1})
		}
		own := []string{"Isle"}
		for row in ISLE_WORDS do if row.kind == KINDS[is.kind].name do own = row.words
		// Drop the words an island before it has taken, unless none is left, then draw one by its weight.
		total: f32
		for &w in words {
			for name in isle_names do if strings.has_prefix(name, fmt.tprintf("%s ", w.w)) do w.weight = -w.weight
			total += max(w.weight, 0)
		}
		if total == 0 do for &w in words do w.weight, total = abs(w.weight), total + abs(w.weight)
		key := hash(i32(is.origin.x), i32(is.origin.y), world_seed + 4711)
		u, word := f32(key >> 8)/16777216*total, ""
		for w in words do if w.weight > 0 && word == "" {
			if u < w.weight do word = w.w
			u -= w.weight
		}
		name := ""
		for k in 0..<len(own) {
			name = fmt.tprintf("%s %s", word, own[(int(key%7) + k)%len(own)]) if word != "" else own[(int(key%7) + k)%len(own)]
			taken := false
			for other in isle_names do taken ||= other == name
			if !taken do break
		}
		append(&isle_names, strings.clone(name))
	}
}

// An island's name, or its kind's where no name has been made (a world a test put together).
isle_name :: proc(i: int) -> string {
	if i >= 0 && i < len(isle_names) do return isle_names[i]
	return capital(kind_said(archipelago[i].kind).short) if i >= 0 && i < len(archipelago) else ""
}

// A world made by start-up itself (main.odin) is the world in hand from here on, with the island
// start-up acts on as its start: so that play can be left for the world's screen.
world_adopt :: proc(island: int, near_km: f64, continent := -1) {
	m := &making
	m.seed, m.kept, m.continent = world_seed, known.took == 0, continent
	m.took[.Plates], m.took[.Region] = known.took - known.regional_took, known.regional_took
	world_lists(island, near_km)
	sync.atomic_store(cast(^u8)&m.stage, u8(Stage.Far))
	sync.atomic_store(&m.massed, true)
	sync.atomic_store(&m.records, true)
}

// Let go what a game held once it is left for the world's screen or the front door: every chunk's
// mesh, water and plants on the GPU, the block volumes, and the simulated water. The world's
// threads have ended (world_destroy).
game_end :: proc(w: ^World, g: ^Gpu) {
	clear(&bar.map_boxes)   // nothing of this game is marked in the next one's picture
	for _, c in w.chunks {
		for b in ([3]^sdl.GPUBuffer{c.buffer, c.water, c.plant_buf}) do if b != nil do sdl.ReleaseGPUBuffer(g.dev, b)
		delete(c.plants); delete(c.blocks); delete(c.under)
		free(c)
	}
	delete(w.chunks)
	for _, e in w.edits do delete(e)
	delete(w.edits)
	delete(w.felled)
	wt := &w.water
	delete(wt.floor); delete(wt.depth); delete(wt.hold); delete(wt.flow_x); delete(wt.flow_z)
	delete(wt.before); delete(wt.shown); delete(wt.sea); delete(wt.still); delete(wt.roof)
	sdl.ReleaseGPUTexture(g.dev, wt.mask)
	sdl.ReleaseGPUBuffer(g.dev, wt.calm)
	clear(&g.cap_list)
	g.caps_level, g.caps_volume = min(i32), -1
	free(w)
}
