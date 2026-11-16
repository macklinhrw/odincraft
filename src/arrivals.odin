package main

import "core:fmt"
import fnv "core:hash"
import "core:math"
import "core:strings"
import "core:time"

// Who reached which island (foundations/living-world.md, the world rung; step 28). Every kind of
// animal the islands have lives on the continent, a guess while the continent is not formed. An
// island has a kind only if the kind could get there from land that has it: by walking over the
// land the sea bared when it stood lowest, or across open sea by swimming, flying or drifting as
// larvae, from the continent or from an island it reached first. A strait no wider than a kind's
// `sure` is crossed in time; one wider than its `most` never; between them the chance falls
// evenly, and the world's seed draws it once for each island and kind. It is decided once, at world
// creation, from the islands' records, the continent's coast and the world's field `depth`, so an
// island has the same animals formed alone or beside others. Whether the island can keep what
// reached it is the region's to say: DEER (trails.odin) and CREATURES (creatures.odin).
//
// The figures are the real islands' (interesting-world/notes/real-animals.md and real-creatures.md):
// of the reference islands only Tsushima, on a shelf joined to the continent while the sea stood
// low, has deer; the Izu and Ogasawara islands, never joined, have birds, gobies and what drifted.
Way :: enum u8 { Walked, Swam, Flew, Drifted }
WAYS   := [Way]string{.Walked = "walked", .Swam = "swam", .Flew = "flew", .Drifted = "drifted as larvae"}
ACROSS := [Way]string{.Walked = "walks", .Swam = "swims", .Flew = "flies", .Drifted = "drifts as a larva"}
Dispersal :: struct {
	name:       string,
	walks:      bool,   // over land the sea bared when it stood lowest
	way:        Way,    // how it crosses open sea
	sure, most: f32,    // km of open sea it crosses in time, and the most it crosses by any chance
	why:        string, // where the figures come from
}
DISPERSAL := [?]Dispersal{
	{"sika deer", true, .Swam, 4, 12, "deer move between the Tomogashima islets and the Kii peninsula, 4 km from Awaji's; 12 km is the farthest a sika deer is reported to swim, off Okinoshima and across a bay to Vladivostok (real-animals.md)"},
	{"black kite", false, .Flew, 100, 1000, "a guess: it soars over land and coast and seldom crosses open sea; none breeds on the Ogasawara islands, 1,000 km out (from memory)"},
	{"osprey", false, .Flew, 1000, 3000, "it migrates over the sea and breeds on the Izu islands, and on Ogasawara (from memory)"},
	{"ayu", false, .Drifted, 10, 50, "a guess: its larvae keep to brackish and coastal water near their river for four months (Hirano 2022; Kishino and Shinomiya 2005); it lives on seven of eight islands of the Tsushima current, all joined to larger land when the sea stood low (Sawashi 1998), and on none of the Izu islands (from memory)"},
	{"yoshinobori", false, .Drifted, 100, 1000, "a guess: its larvae drift at sea, and gobies of its kind live in the streams of every high island looked at, Yakushima's and, 1,000 km out, the Ogasawara islands' (from memory)"},
}

// How a kind came to an island, or the nearest it came: the land it came from or the nearest that
// has it, the strait between, and the chance.
Arrival :: struct {
	reached:      bool,
	way:          Way,
	from:         int,    // the island it came from, or -1: the continent
	gap, open:    f32,    // km between the shores today, and of it the sea that stood open when the sea was lowest over the island
	deepest:      f32,    // m, the strait's deepest sounding today
	chance, draw: f32,
}
arrivals: [][len(DISPERSAL)]Arrival   // for each island of the archipelago, by arrivals_make; read only once made
ASHORE :: 0.25   // an island's shore lies about this share of its region's side from its middle: 0.14 to 0.17 on cones and craters, 0.23 to 0.39 on the rest (79 islands of seeds 1, 3, 5 and 7)

// Metres the sea has risen over an island since it stood lowest, from its kind's history as its
// seed draws it and its record reads it: risen() of the island once formed, read before.
risen_on :: proc(is: Island) -> f32 {
	key := i32(fnv.fnv32a(transmute([]u8)KINDS[is.kind].name))
	plan := make([]Phase(f32), len(KINDS[is.kind].history), context.temp_allocator)
	for p, i in KINDS[is.kind].history do plan[i] = phase_draw(p, i, key, is.seed)
	if is.id != 0 {   // as region_init reads it
		record, shape := record_of(is), Shape(f64){}
		record_phases(&KINDS[is.kind], &record, plan, &shape)
	}
	sea, low: f32
	for p in plan {
		sea += p.sea
		low = min(low, sea)
	}
	return sea - low
}

Strait :: struct { gap, deepest: f32, open: [2]f32 }

// The strait between two shores, sounded every 500 m on the world's `depth`: how wide, how deep at
// its deepest, and how much of it stood open sea with the sea `low[0]` or `low[1]` metres lower.
sound :: proc(a, b: [2]f64, low: [2]f32) -> (s: Strait) {
	l := math.hypot(b.x - a.x, b.y - a.y)
	n := max(int(math.ceil(l/500)), 1)
	s.gap = f32(l/1000)
	for k in 0..<n {
		p := a + (b - a)*(f64(k) + 0.5)/f64(n)
		d := world_at(p.x, p.y).depth
		s.deepest = max(s.deepest, d)
		for r, j in low do if d > r do s.open[j] += s.gap/f32(n)
	}
	return
}

// Decide which kinds reached each island of the archipelago: in rounds, from the continent and then
// from the islands reached in rounds before, each island taking the source with the best chance.
arrivals_make :: proc() {
	started := time.now()
	n := len(archipelago)
	for row in CREATURES do assert(dispersal_of(row.name) >= 0, row.name)
	assert(dispersal_of(DEER.name) >= 0)
	delete(arrivals)
	arrivals = make([][len(DISPERSAL)]Arrival, n)
	middle :: proc(i: int) -> [2]f64 { return {f64(archipelago[i].origin.x), f64(archipelago[i].origin.y)} }
	low := make([]f32, n, context.temp_allocator)
	for is, i in archipelago do low[i] = risen_on(is)
	// Each island's strait to the continent's nearest coast, and to each other island, shore to shore.
	coast, straits := make([]Strait, n, context.temp_allocator), make([]Strait, n*n, context.temp_allocator)
	for i in 0..<n {
		o, near := middle(i), continent.coast[0]
		for c in continent.coast[:len(continent.coast) - 1] do if math.hypot(c.x - o.x, c.y - o.y) < math.hypot(near.x - o.x, near.y - o.y) do near = c
		l := math.hypot(near.x - o.x, near.y - o.y)
		coast[i] = sound(o + (near - o)*min(ASHORE*archipelago[i].size/l, 1), near, {low[i], low[i]})
		for j in i + 1..<n {
			d := math.hypot(middle(j).x - o.x, middle(j).y - o.y)
			a, b := ASHORE*archipelago[i].size, ASHORE*archipelago[j].size
			s := Strait{} if a + b >= d else sound(o + (middle(j) - o)*a/d, middle(j) - (middle(j) - o)*b/d, {low[i], low[j]})
			straits[i*n + j], straits[j*n + i] = s, {s.gap, s.deepest, {s.open[1], s.open[0]}}
		}
	}
	try :: proc(best: ^Arrival, k: Dispersal, from: int, s: Strait) {
		c := Arrival{way = .Walked if k.walks && s.open[0] == 0 else k.way, from = from, gap = s.gap, open = s.open[0], deepest = s.deepest}
		c.chance = 1 if c.way == .Walked else clamp((k.most - c.open)/(k.most - k.sure), 0, 1)
		if c.chance > best.chance || c.chance == best.chance && c.open < best.open do best^ = c
	}
	for k, kind in DISPERSAL {
		round := make([]int, n, context.temp_allocator)   // the round it reached each island in, or 0
		for r := 1; ; r += 1 {
			more := false
			for i in 0..<n do if round[i] == 0 {
				best := Arrival{chance = -1}
				try(&best, k, -1, coast[i])
				for j in 0..<n do if round[j] > 0 && round[j] < r do try(&best, k, j, straits[i*n + j])
				best.draw = hash01(i32(i), i32(fnv.fnv32a(transmute([]u8)k.name)), world_seed + 1800)   // keyed by the row's name, so a new row changes only its own draws
				best.reached = best.chance >= 1 || best.draw < best.chance
				arrivals[i][kind] = best
				if best.reached do round[i], more = r, true
			}
			if !more do break
		}
	}
	fmt.printf("who reached which island, decided in %.1f ms:", time.duration_milliseconds(time.since(started)))
	for k, kind in DISPERSAL {
		on := strings.builder_make(context.temp_allocator)
		off := strings.builder_make(context.temp_allocator)
		for a, i in arrivals {
			if a[kind].reached do fmt.sbprintf(&on, "%s%d%s", "" if strings.builder_len(on) == 0 else ", ", i, fmt.tprintf(" %s", WAYS[a[kind].way]) if k.walks else "")
			else do fmt.sbprintf(&off, "%s%d", "" if strings.builder_len(off) == 0 else ", ", i)
		}
		fmt.printf("%s %s on %s", ";" if kind > 0 else "", k.name, "none" if strings.builder_len(on) == 0 else fmt.tprintf("all %d", n) if strings.builder_len(off) == 0 else
			fmt.tprintf("all but %s", strings.to_string(off)) if k.walks == false && strings.builder_len(off) < strings.builder_len(on) else strings.to_string(on))
	}
	fmt.println()
}

dispersal_of :: proc(name: string) -> int {
	for k, i in DISPERSAL do if k.name == name do return i
	return -1
}

// Whether a kind reached the island in hand, and how.
came :: proc(name: string) -> Arrival { return arrivals[here.island.id][dispersal_of(name)] }

// How a kind came to the island in hand, or, if it did not, why not, in words.
arrival_words :: proc(name: string) -> string {
	k, a := DISPERSAL[dispersal_of(name)], came(name)
	km :: proc(v: f32) -> string { return fmt.tprintf("%.1f", v) if v < 10 else fmt.tprintf("%.0f", v) }
	from := "the continent" if a.from < 0 else fmt.tprintf("island %d (%s)", a.from, KINDS[archipelago[a.from].kind].name)
	sea := fmt.tprintf("%s km of sea", km(a.open)) if a.open > a.gap - 0.5 else fmt.tprintf("%s km of sea (%s km today)", km(a.open), km(a.gap))
	if a.reached && a.way == .Walked do return fmt.tprintf("the %s walked from %s when the sea stood %.0f m lower and bared the %s km between, %.0f m deep at most today", k.name, from, risen(), km(a.gap), a.deepest)
	if a.reached && a.open == 0 do return fmt.tprintf("the %s %s from %s, %s km off and joined to the island when the sea stood %.0f m lower", k.name, WAYS[a.way], from, km(a.gap), risen())
	if a.reached && a.chance >= 1 do return fmt.tprintf("the %s %s from %s across %s", k.name, WAYS[a.way], from, sea)
	if a.reached do return fmt.tprintf("the %s %s from %s across %s, more than the %s km it crosses in time: the chance was %.2f and the seed drew %.2f", k.name, WAYS[a.way], from, sea, km(k.sure), a.chance, a.draw)
	s := fmt.tprintf("the nearest land with it, %s, lies across %s", from, sea)
	if k.walks do s = fmt.tprintf("%s up to %.0f m deep, which the sea, %.0f m lower at its lowest, never bared", s, a.deepest, risen())
	if a.chance > 0 do return fmt.tprintf("%s; it %s %s km in time and %s at most, so the chance was %.2f, and the seed drew %.2f", s, ACROSS[k.way], km(k.sure), km(k.most), a.chance, a.draw)
	return fmt.tprintf("%s, and it %s %s km at most", s, ACROSS[k.way], km(k.most))
}

// The start-up line: what reached the island in hand, and what did not.
arrivals_say :: proc() {
	fmt.printf("who reached it, over the straits as they stood when the sea was lowest, %.0f m under today's:", risen())
	missed, said := strings.builder_make(context.temp_allocator), 0
	for k in DISPERSAL do if a := came(k.name); a.reached {
		fmt.printf("%s %s", "" if said == 0 else ";", arrival_words(k.name))
		said += 1
	} else do fmt.sbprintf(&missed, "%s the %s", "" if strings.builder_len(missed) == 0 else ",", k.name)
	if strings.builder_len(missed) > 0 do fmt.printf("; not%s, whose lines below say why", strings.to_string(missed))
	fmt.println()
}

// Whether the island in hand keeps a kind that reached it: deer that lay trails, birds with a home,
// fish in a stream or lake.
kept :: proc(name: string) -> bool {
	if name == DEER.name do return len(trails.segments) > 0
	for row, k in CREATURES do if row.name == name {
		for h in fauna.haunts do if h.row == k do return true
		for bits in fauna.fish do if bits >> uint(k) & 1 != 0 do return true
		for _, bits in fauna.lakes do if bits >> uint(k) & 1 != 0 do return true
	}
	return false
}

// What lives on the island in hand, of what reached it, as --archipelago prints it: a kind not kept in brackets.
lives_words :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	for k in DISPERSAL do if came(k.name).reached do fmt.sbprintf(&b, "%s%s", "" if strings.builder_len(b) == 0 else ", ", k.name if kept(k.name) else fmt.tprintf("(%s)", k.name))
	return strings.to_string(b)
}

// Who reached the island and why, and whether it keeps them, as --why prints it.
arrivals_why :: proc() {
	is := here.island
	fmt.printfln("who reached island %d, %s on the %s: the straits to its neighbours and the continent as they stood when the sea was lowest over it, %.0f m under today's (risen), against how far each animal crosses the sea (DISPERSAL, arrivals.odin)", is.id, KINDS[is.kind].name, SETTINGS[is.setting], risen())
	for k in DISPERSAL {
		a := came(k.name)
		if a.reached do fmt.printfln("  %s; %s. [%s]", arrival_words(k.name), "it lives here" if kept(k.name) else "but the island cannot keep it, as its start-up line says", k.why)
		else do fmt.printfln("  no %s: %s. [%s]", k.name, arrival_words(k.name), k.why)
	}
}
