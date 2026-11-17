package main

import "base:builtin"
import "core:fmt"
import "core:math"
import "core:strings"

// Shelter and warmth (plan.md, P4, second half; docs/adr/0015): whether a place is under a roof and
// inside walls, what a dwarf standing there feels of the weather (weather.odin), the cold that
// comes of it as a need beside thirst, hunger and sleep (WANTS, needs.odin), where a dwarf lies down
// for the night, and fire.
//
// Shelter is read from the blocks, by one rule (shelter_of) that the hold asks of its own ground and
// the frame of the blocks it draws, as with every order (cells_of, orders.odin):
//   a roof   is a block of ground or a block laid, anywhere within ROOF_REACH over a dwarf's head.
//            A room dug into a hill has one; a floor laid over walls is one; a tree's crown is not.
//   a wall   shuts one of the four ways out from a place where a block stands at a dwarf's head
//            within WALL_REACH steps; under a roof, a way is also shut where the roof runs on that
//            far, and open where it ends before a wall is met.
//   indoors  is under a roof with three ways or more shut: one way may be the door.
// RimWorld keeps a roof for every cell and calls a room outdoors when a quarter of it is unroofed;
// Dwarf Fortress keeps three flags a tile, outside, light and subterranean; Ingnomia asks of a room
// only whether it is roofed and whether it is enclosed (colony-sim-reference.md, section 15). This
// rule is theirs made local: it needs no rooms kept, and a block changed changes nothing but itself.

ROOF_REACH :: 16    // blocks over a dwarf's head that a roof is looked for in: an overhang higher keeps no rain off
WALL_REACH :: 5     // steps out that a wall is looked for

Shelter :: struct { roof: bool, walls: u8 }

// Whether a block is something a roof or a wall is made of: ground or a block laid; no plant's.
shelters :: proc(m: Mat) -> bool { return m != .Air && !is(m, PLANT_BLOCKS) }

// Whether a dwarf with its feet in a cell has a roof over its head.
roofed :: proc(src: Blocks, c: [3]i32) -> bool {
	for y in c.y + 2..<c.y + 2 + ROOF_REACH do if shelters(src.at(src.data, {c.x, y, c.z})) do return true
	return false
}

// The shelter of a cell a dwarf stands in.
shelter_of :: proc(src: Blocks, c: [3]i32) -> (s: Shelter) {
	s.roof = roofed(src, c)
	for way in ([4][3]i32{{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}}) do for step in i32(1)..=WALL_REACH {
		at := c + way*step
		if shelters(src.at(src.data, at + {0, 1, 0})) {   // a wall at its head
			s.walls += 1
			break
		}
		if !s.roof do continue
		if !roofed(src, at) do break   // the roof ends before any wall: open that way
		if step == WALL_REACH do s.walls += 1   // deep under it
	}
	return
}

indoors :: proc(s: Shelter) -> bool { return s.roof && s.walls >= 3 }

// Shelter in words, for a card and a line: "indoors: under a roof and inside walls".
shelter_words :: proc(s: Shelter) -> string {
	return "indoors, under a roof and inside walls: dry, out of the wind, and as mild as the walls keep it" if indoors(s) else
		"under a roof, with no walls round it: dry, and open to the wind" if s.roof && s.walls == 0 else
		fmt.tprintf("under a roof, walled on %s: dry, and half out of the wind", "one side" if s.walls == 1 else "two sides") if s.roof else
		"in a hollow, open to the sky: out of the wind, and the rain falls in" if s.walls >= 3 else "open to the sky"
}

// ---- what a dwarf feels -----------------------------------------------------------------------------

// The figures, beside the real games' (colony-sim-reference.md, section 15). RimWorld's person with
// nothing on is comfortable from 16 °C, and clothed for the cold from far lower; ten degrees under
// that it begins to die, in a day and a third at most. It is not chilled by being wet. Dwarf
// Fortress's dwarves do not feel the weather at all. Here a dwarf is clothed as it landed and no
// more (clothes are P5's): under COMFORT it is chilled, the faster the colder, and when it has no
// warmth left and what it feels is under HARM it is harmed, and dies after WANTS[.Warm].kills days
// of that. What it feels is the air, less the wind's chill on what stands open to it, less the
// chill of being wet, which doubles the wind's: the island is mild (9.8 °C in its coldest month),
// and it is the rain and the wind of a winter night that kill there, as they do on a real hill.
COMFORT    :: 12.0   // °C felt, under which a dwarf is chilled
HARM       :: 6.0    // °C felt, under which one with no warmth left is harmed
CHILL      :: 0.4    // °C the wind takes for each m/s: the wind-chill index gives about that at 5 to 10 °C (from memory)
SOAKED     :: 5.0    // °C that being wet through takes
WETS       :: 1.0    // of wet through, in an hour of the heaviest rain with no roof
DRIES_IN   :: 3.0    // hours a wet dwarf takes to dry out of the rain: RimWorld's "soaking wet" lasts 2.4 after it
WALLED     :: 0.5    // indoors the air is so far from the air outside toward the year's mean: walls and ground keep the season's warmth. RimWorld's room under rock is drawn toward 15 °C
WARMS      :: 3.0    // of the whole, in a day, that warmth comes back where a dwarf is comfortable
FEEL_EVERY :: 10     // ticks between two looks at what a dwarf feels, while it stands

// Fire. RimWorld's campfire is built of 20 wood, which is its first fuel, holds 20 and burns 10 a
// day, 4.6 times as fast in rain with no roof over it; it warms a closed room and nothing outdoors,
// lights 10 cells, is fed from the stockpile without being asked, and the player can stop that.
// Here a tree is three to six logs, so a fire is kindled of one and holds six, two days' burning.
FIRE_HOLDS  :: 6.0    // logs a fire holds
FIRE_BURNS  :: 3.0    // logs it burns in a day
FIRE_RAIN   :: 3.0    // times as fast in rain with no roof over it
FIRE_LOW    :: 2.0    // logs under which it is fed by whoever has nothing more pressing
FIRE_DYING  :: 1.0    // and under which it is fed before any marked work
FIRE_NIGHT  :: 4.0    // and, from FIRE_EVENING on, where no roof stands over it: a night of rain burns as many, and nobody wakes to feed it
FIRE_EVENING :: 19.0  // the hour
FIRE_REACH  :: [2]i32{2, 4}   // steps round it that it warms: in the open, where the wind takes its warmth; and where it stands under a roof with walls
FIRE_FELT   :: 18.0   // °C a dwarf by it feels at the least, whatever the weather
FIRE_WARMS  :: 12.0   // of the whole, in a day, that warmth comes back by it
FIRE_DRIES  :: 0.5    // hours a wet dwarf takes to dry by it
FIRE_WORK   :: 4.0    // seconds to lay and light one (RimWorld: 200 ticks, 3.3 s)
FIRE_LIGHT  :: 9.0    // metres its light reaches at night

Fire :: struct {
	at:     [3]i32,   // the cell it burns in: the one a dwarf's feet would be in
	fuel:   f32,      // logs left
	kind:   Mat,      // the timber it was last fed
	lit:    bool,
	fed:    bool,     // it is kept fed: the player may let it go out
	coming: i32,      // logs on their way to it
	roof, walled: bool,   // as it stood when last looked at: under a roof, and inside walls
	rained: bool,     // and rain was falling on it
}
Fire_Seen :: struct { at: [3]i32, fuel: f32, lit, fed, roof, walled, rained: bool }

// How a dwarf lay down for the night, for the dawn's word.
Slept :: enum u8 { None, Open, Roof, Indoors, Fire }

// The lit fire whose warmth reaches a cell, or -1.
fire_near :: proc(h: ^Hold, c: [3]i32) -> int {
	reach := FIRE_REACH
	for f, k in h.fires do if f.lit {
		r := reach[1] if f.roof && f.walled else reach[0]
		if abs(f.at.x - c.x) <= r && abs(f.at.z - c.z) <= r && abs(f.at.y - c.y) <= 2 do return k
	}
	return -1
}

// What a dwarf feels in a cell: the air there, the wind's chill and the wet's, a fire's warmth.
// `wet` is how wet the dwarf is, 0 to 1.
Feel :: struct { felt, air, rain, wind: f32, shelter: Shelter, fire: bool }
feel_at :: proc(h: ^Hold, c: [3]i32, wet: f32, s: Shelter, w: Weather) -> (f: Feel) {
	f.shelter, f.air, f.wind = s, w.air, w.wind*(1 - f32(s.walls)/4)
	if indoors(s) {
		f.air = math.lerp(w.air, region.climate.mean - LAPSE*f32(max(c.y, 0)), f32(WALLED))
		f.wind = 0
	}
	f.rain = 0 if s.roof else w.rain*(0.5 if w.snow else 1)   // snow wets half as fast
	f.felt = f.air - CHILL*f.wind*(1 + wet) - SOAKED*wet
	if fire_near(h, c) >= 0 do f.fire, f.felt = true, max(f.felt, FIRE_FELT)
	return
}

// A dwarf's own, looked at again when it has moved, when the ground has changed, and every
// FEEL_EVERY ticks: the shelter is read again only for a new cell or changed ground.
feel :: proc(h: ^Hold, i: int) {
	d := &h.dwarves[i]
	if d.felt_cell != d.cell || d.felt_ground != h.ground || !d.felt_any {
		s := shelter_of(hold_blocks(h), d.cell)
		d.roof, d.walls, d.felt_cell, d.felt_ground, d.felt_any = s.roof, s.walls, d.cell, h.ground, true
	}
	f := feel_at(h, d.cell, d.wet, {d.roof, d.walls}, weather(f64(h.tick)*TICK, stand_of(d.cell)))
	d.felt, d.rained, d.by_fire = f.felt, f.rain, f.fire
}

// A tick of a dwarf's warmth: it gets wet in the rain and dries out of it, is chilled under COMFORT
// and warmed over it. True while it is harmed: it has no warmth left, in cold that harms.
warm_tick :: proc(h: ^Hold, i: int) -> (harmed: bool) {
	d := &h.dwarves[i]
	if (h.tick + i)%FEEL_EVERY == 0 || d.felt_cell != d.cell || !d.felt_any do feel(h, i)
	hours := f32(TICK*24/DAY)
	if d.rained > 0 do d.wet = min(d.wet + WETS*d.rained*hours, 1)
	else do d.wet = max(d.wet - hours/(FIRE_DRIES if d.by_fire else DRIES_IN), 0)
	row := WANTS[.Warm]
	if d.felt < COMFORT do d.want[.Warm] = max(d.want[.Warm] - row.falls*d.pace[.Warm]*(COMFORT - d.felt)/10*TICK/DAY, 0)
	else do d.want[.Warm] = min(d.want[.Warm] + (FIRE_WARMS if d.by_fire else WARMS)*TICK/DAY, 1)
	if d.want[.Warm] >= row.seeks do d.lacks -= {.Warm}
	return d.want[.Warm] <= 0 && d.felt < HARM
}

// ---- warming itself ---------------------------------------------------------------------------------

far_of :: proc(a, b: [3]i32) -> i32 { return abs(a.x - b.x) + abs(a.z - b.z) + 2*abs(a.y - b.y) }

// Whether a dwarf can come to rest in a cell to warm itself or to sleep: a dry floor that is no
// other's, not marked, not a stockpile's and not a fire's.
rests_well :: proc(h: ^Hold, c: [3]i32, i: int) -> bool {
	f := walk_floor(&h.walk, c.x, c.y, c.z)
	if f < 0 || h.walk.floors[f].wet > 0 || on_mark(h, c) || c in h.burning || c in h.benched do return false
	if o, held := h.held[c]; held && o != i do return false
	if o, claimed := h.claims[c]; claimed && o != i do return false
	return true
}

// A place for a cold dwarf to warm itself, with a way to it: by the nearest fire that burns; or the
// nearest place of a sleeping place, or within a short walk, where it would be comfortable dry.
warm_find :: proc(h: ^Hold, i: int) -> (to: [3]i32, ok: bool) {
	d, w := &h.dwarves[i], &h.walk
	way := make([dynamic][3]i32, context.temp_allocator)
	reaches :: proc(h: ^Hold, i: int, c: [3]i32, way: ^[dynamic][3]i32) -> bool {
		if c == h.dwarves[i].cell do return true
		h.walk.budget = ASKING
		_, why, _, _ := way_timed(h, h.dwarves[i].cell, c, way)
		return why == .Way
	}
	// By a fire, the nearest first: the free floor round it nearest the dwarf.
	reach := FIRE_REACH
	order := make([dynamic]int, context.temp_allocator)
	for f, k in h.fires do if f.lit do append(&order, k)
	for a in 1..<len(order) do for k := a; k > 0 && far_of(h.fires[order[k]].at, d.cell) < far_of(h.fires[order[k - 1]].at, d.cell); k -= 1 do order[k], order[k - 1] = order[k - 1], order[k]
	for k in order[:min(len(order), 3)] {
		f := h.fires[k]
		r := reach[1] if f.roof && f.walled else reach[0]
		best, least := [3]i32{}, max(i32)
		w.budget = ASKING
		for dz in -r..=r do for dx in -r..=r do for dy in i32(-1)..=1 {
			c := f.at + {dx, dy, dz}
			if !rests_well(h, c, i) do continue
			if far := far_of(c, d.cell) + 4*max(abs(dx), abs(dz)); far < least do best, least = c, far   // the nearer the fire the better, among those as near the dwarf
		}
		if least < max(i32) && reaches(h, i, best, &way) do return best, true
	}
	// A sleeping place's ground where it would be comfortable. The weather is that of where it stands: a short walk changes it little.
	blocks := hold_blocks(h)
	sky := weather(f64(h.tick)*TICK, stand_of(d.cell))
	cells := make([dynamic][3]i32, context.temp_allocator)
	for c, cell in h.zoned do if h.zones[cell.zone].sleep && rests_well(h, c, i) do append(&cells, c)
	for a in 1..<len(cells) do for k := a; k > 0 && nearer(cells[k], cells[k - 1], d.cell); k -= 1 do cells[k], cells[k - 1] = cells[k - 1], cells[k]
	tried := 0
	for c in cells {
		if tried >= 3 do break
		if feel_at(h, c, 0, shelter_of(blocks, c), sky).felt < COMFORT do continue
		tried += 1
		if reaches(h, i, c, &way) do return c, true
	}
	// Any floor within a short walk where it would be: a roof, walls, a hollow out of the wind.
	f := walk_floor(w, d.cell.x, d.cell.y, d.cell.z)
	if f < 0 do return
	w.budget = ASKING
	w.stamp += 1
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, f)
	w.seen[f] = w.stamp
	for k := 0; k < len(queue) && k < 500; k += 1 {
		c := floor_block(w, queue[k])
		if rests_well(h, c, i) && feel_at(h, c, 0, shelter_of(blocks, c), sky).felt >= COMFORT do return c, true   // joined to where it stands: a way leads there
		for way in 0..<8 do if t := floor_step(w, queue[k], way); t >= 0 && w.seen[t] != w.stamp {
			w.seen[t] = w.stamp
			append(&queue, t)
		}
	}
	return
}

// Whether one cell is nearer a third than another is, the same whatever order a map gave them in.
nearer :: proc(a, b, from: [3]i32) -> bool {
	fa, fb := far_of(a, from), far_of(b, from)
	return fa < fb || fa == fb && (a.x < b.x || a.x == b.x && (a.z < b.z || a.z == b.z && a.y < b.y))
}

// Where a dwarf lies down for the night: in a sleeping place the player marked, under its roof
// first; with none, or none free, under a roof or by a fire within a short walk; and with neither,
// on dry ground where it is. RimWorld's pawn takes its bed, then a sleeping spot, then the ground
// where it stands; Dwarf Fortress's its bedroom, then a dormitory, then the floor.
sleep_find :: proc(h: ^Hold, i: int) -> [3]i32 {
	d, w := &h.dwarves[i], &h.walk
	blocks := hold_blocks(h)
	rank :: proc(h: ^Hold, blocks: Blocks, c: [3]i32) -> int {
		s := shelter_of(blocks, c)
		return 3 if indoors(s) || fire_near(h, c) >= 0 && s.roof else 2 if s.roof || fire_near(h, c) >= 0 else 1
	}
	// The sleeping places: the best sheltered free place that a way leads to; of those one with nobody lying, or about
	// to lie, in the places round it; and of those the nearest. A body lies longer than a block: played, the seven lay
	// in a heap on the five places nearest the door of a room of forty (plan.md, "A first year").
	Bed :: struct { c: [3]i32, rank, crowd: int }
	beds := make([dynamic]Bed, context.temp_allocator)
	lain := make([dynamic][3]i32, context.temp_allocator)   // where the others lie, or go to lie
	for o, j in h.dwarves do if j != i && o.caring && o.care == .Sleep && o.doing != .Dead do append(&lain, o.care_at)
	for c, cell in h.zoned do if h.zones[cell.zone].sleep && rests_well(h, c, i) {
		crowd := 0
		for l in lain do crowd += int(abs(l.x - c.x) <= 1 && abs(l.z - c.z) <= 1 && abs(l.y - c.y) <= 1)
		append(&beds, Bed{c, rank(h, blocks, c), crowd})
	}
	before :: proc(a, b: Bed, from: [3]i32) -> bool { return a.rank > b.rank || a.rank == b.rank && (a.crowd < b.crowd || a.crowd == b.crowd && nearer(a.c, b.c, from)) }
	for a in 1..<len(beds) do for k := a; k > 0 && before(beds[k], beds[k - 1], d.cell); k -= 1 do beds[k], beds[k - 1] = beds[k - 1], beds[k]
	way := make([dynamic][3]i32, context.temp_allocator)
	for b in beds[:min(len(beds), 3)] {
		if b.c == d.cell do return b.c
		w.budget = ASKING
		if _, why, _, _ := way_timed(h, d.cell, b.c, &way); why == .Way do return b.c
	}
	if today := date_tick(h.tick - int(12*DAY/24/TICK)).day; len(beds) > 0 && (!h.bedless || h.bedless_on != today) {   // the night is the day's it began on   // a place is marked and free, and no way leads to it: said once a night
		h.bedless, h.bedless_on = true, today
		h.at = feet_on(beds[0].c)
		h.short = "No way leads to the sleeping place."
		say(h, "%s finds no way to the sleeping place at %s, and lies down elsewhere: something stands in the way in, or it has no door.", who(h, i), place_say(h, beds[0].c))
	}
	// No place marked, or none it can come to: the best within a short walk, where it stands if that is as good.
	f := walk_floor(w, d.cell.x, d.cell.y, d.cell.z)
	if f < 0 do return d.cell
	best, best_rank := d.cell, rank(h, blocks, d.cell) if rests_well(h, d.cell, i) else 0
	w.budget = ASKING
	w.stamp += 1
	queue := make([dynamic]i32, context.temp_allocator)
	append(&queue, f)
	w.seen[f] = w.stamp
	for k := 0; k < len(queue) && k < 600 && best_rank < 3; k += 1 {
		if c := floor_block(w, queue[k]); k > 0 && rests_well(h, c, i) do if r := rank(h, blocks, c); r > best_rank do best, best_rank = c, r
		for way in 0..<8 do if t := floor_step(w, queue[k], way); t >= 0 && w.seen[t] != w.stamp {
			w.seen[t] = w.stamp
			append(&queue, t)
		}
	}
	return best
}

// How a dwarf lying in a cell has lain down, for the dawn's word.
slept_as :: proc(h: ^Hold, c: [3]i32) -> Slept {
	s := shelter_of(hold_blocks(h), c)
	return .Indoors if indoors(s) else .Roof if s.roof else .Fire if fire_near(h, c) >= 0 else .Open
}

// ---- fire -------------------------------------------------------------------------------------------

// A fire is laid and lit in a cell, of the log brought to it.
fire_light :: proc(h: ^Hold, at: [3]i32, kind: Mat) {
	h.burning[at] = len(h.fires)
	append(&h.fires, Fire{at = at, fuel = 1, kind = kind, lit = true, fed = true})
	fire_look(h, len(h.fires) - 1)
	h.fires_v += 1
	for &d in h.dwarves do d.felt_any = false
}

// What stands over a fire and falls on it, looked at again now and then.
fire_look :: proc(h: ^Hold, k: int) {
	f := &h.fires[k]
	s := shelter_of(hold_blocks(h), f.at)
	f.roof, f.walled = s.roof, s.walls >= 3
	f.rained = !s.roof && weather(f64(h.tick)*TICK, stand_of(f.at)).rain > 0
}

// A tick of the fires: each burns its timber, faster in the rain, and goes out with its last.
fires_tick :: proc(h: ^Hold) {
	for &f, k in h.fires {
		if (h.tick + 7*k)%100 == 0 do fire_look(h, k)
		if !f.lit do continue
		f.fuel -= FIRE_BURNS*(FIRE_RAIN if f.rained else 1)*TICK/DAY
		if f.fuel > 0 do continue
		f.fuel, f.lit = 0, false
		h.fires_v += 1
		for &d in h.dwarves do d.felt_any = false
		h.at = feet_on(f.at)
		h.short = "A fire has burnt out."
		timber := false
		for g in h.goods do timber ||= !is(g.kind, FOOD) && is_stuff(g.kind, .Timber)
		say(h, "The fire at %s has burnt out: %s.", place_say(h, f.at), "it was let go out" if !f.fed else "no timber was brought to it in time" if timber else "no timber lies anywhere to feed it")
	}
}

// A fire is to be kept fed, or let go out.
fire_tend :: proc(h: ^Hold, o: Order) {
	at := o.at + {0, 1, 0}
	h.at = feet_on(at)
	k, ok := h.burning[at]
	if !ok {
		h.short = "No fire there."
		say(h, `The hold says "%s": no fire stands there.`, order_words(o))
		return
	}
	h.fires[k].fed = o.on
	h.fires_v += 1
	h.short = "The fire is kept fed." if o.on else "The fire is let go out."
	say(h, `The hold says "%s": the fire at %s is %s.`, order_words(o), place_say(h, at), "kept fed from now" if o.on else "fed no more, and goes out when its timber is burnt")
	for &d in h.dwarves do if !d.job && !d.haul.on do d.rest = min(d.rest, 2)
}

// The fires in a box's columns are put out and taken up: how many went. What timber was left in each lies there.
fires_remove :: proc(h: ^Hold, lo, hi: [3]i32) -> (gone: int) {
	for k := len(h.fires) - 1; k >= 0; k -= 1 do if f := h.fires[k]; f.at.x >= lo.x && f.at.x <= hi.x && f.at.z >= lo.z && f.at.z <= hi.z {
		delete_key(&h.burning, f.at)
		last := len(h.fires) - 1
		if k != last {
			h.fires[k] = h.fires[last]
			h.burning[h.fires[k].at] = k
		}
		pop(&h.fires)
		if left := i32(math.floor(f.fuel)); left > 0 do good_put(h, f.at, f.kind, left)
		gone += 1
	}
	if gone > 0 {
		h.fires_v += 1
		for &d in h.dwarves do d.felt_any = false
	}
	return
}

// A block changed: a fire whose ground was dug away comes down with it, and one a block was laid in is put out.
fires_settle :: proc(h: ^Hold, at: [3]i32, mat: Mat) {
	c := at + {0, 1, 0} if mat == .Air else at
	k, ok := h.burning[c]
	if !ok do return
	if mat != .Air {
		fires_remove(h, c, c)
		return
	}
	f := &h.fires[k]
	delete_key(&h.burning, c)
	for _ in 0..<64 {
		if under, _ := walk_block(&h.walk, f.at - {0, 1, 0}); under != .Air && !is(under, LEAVES) do break
		f.at.y -= 1
	}
	h.burning[f.at] = k
	h.fires_v += 1
}

// A dwarf with nothing more pressing feeds a fire that is low: an armful of the nearest timber,
// wherever it lies. With `dying`, only a fire about to go out. False if there is none to feed, or nothing to feed it.
fire_feed :: proc(h: ^Hold, i: int, dying: bool) -> bool {
	w := &h.walk
	for &f, k in h.fires {
		low: f32 = FIRE_DYING if dying else FIRE_LOW
		if !f.roof && date_tick(h.tick).hour >= FIRE_EVENING do low = FIRE_NIGHT   // made up for the night before the hold lies down: played, the fire by the racks went out on every night of rain with timber in the stockpile
		if !f.fed || f.fuel + f32(f.coming) >= low do continue
		w.budget = ASKING
		stand := walk_near(w, f.at.x, f.at.y, f.at.z, 2, false, &h.burning)
		if stand < 0 do continue
		// The piles of timber nearest the fire, a few of them: the nearest may lie where no way leads.
		Near :: struct { far: i32, j: int }
		tries: [5]Near
		count := 0
		for g, j in h.goods do if !is(g.kind, FOOD) && is_stuff(g.kind, .Timber) && g.n - g.held > 0 {
			far := far_of(g.at, f.at)
			at := min(count, len(tries) - 1)
			if count == len(tries) && far >= tries[at].far do continue
			for at > 0 && tries[at - 1].far > far {
				tries[at] = tries[at - 1]
				at -= 1
			}
			tries[at] = {far, j}
			count = min(count + 1, len(tries))
		}
		if count == 0 do return false   // no timber lies anywhere
		for t in tries[:count] {
			g := &h.goods[t.j]
			n := min(ARMFUL, i32(FIRE_HOLDS - f.fuel) - f.coming, g.n - g.held)
			if n <= 0 do break
			if !haul_set(h, i, {on = true, from = g.at, to = floor_block(w, stand), kind = g.kind, n = n, site = -1, fire = true, hearth = f.at}) do continue
			g.held += n
			f.coming += n
			return true
		}
		_ = k
	}
	return false
}

// What comes before any marked work: a fire about to go out is fed, and what a thing is to be
// built of is brought to it: the log a fire is laid of, a rack's, a wall's stone. True if the dwarf
// has set out for either. Bringing a block's stuff is part of building it, as RimWorld's builder
// delivers to a frame before it builds (WorkGiver_ConstructDeliverResources is the constructors'
// own): left to whoever had nothing else marked, racks ordered in a spring of gathering stood
// unbuilt until summer (plan.md, "Winter's food, as built").
fire_first :: proc(h: ^Hold, i: int) -> bool {
	if len(h.fires) > 0 && fire_feed(h, i, true) do return true
	for s, id in h.sites do if !s.over && s.work == .Build && site_wants(h, id) > 0 && site_haul(h, i, id) do return true
	// And a rack is seen to: what it has dried is taken off, and what will spoil is laid on while it has room. Played
	// with this left to idle hands, the racks stood done or empty through a spring of gathering while the stockpile's shoots spoiled.
	if len(h.benches) > 0 && (bench_unload(h, i) || bench_load(h, i)) do return true
	return false
}

// Whether what a dwarf has in hand is a fire's own work: laying one, bringing the log it is laid of,
// or feeding one. It is the remedy of the cold, and is not left for it.
fire_work :: proc(h: ^Hold, i: int) -> bool {
	d := &h.dwarves[i]
	if d.haul.on && (d.haul.fire || d.haul.site >= 0 && h.sites[d.haul.site].shape == .Fire) do return true
	if k, ok := h.marked[d.job_at]; ok && d.job do return h.marks[k].work == .Build && h.sites[h.marks[k].site].shape == .Fire
	return false
}

// A dwarf has come to a fire with timber: it is laid on, and a fire that was out burns again.
fire_fed :: proc(h: ^Hold, i: int, hearth: [3]i32, kind: Mat, n: i32) -> bool {
	k, ok := h.burning[hearth]
	if !ok do return false
	f := &h.fires[k]
	f.coming = max(f.coming - n, 0)
	f.fuel, f.kind = min(f.fuel + f32(n), FIRE_HOLDS), kind
	h.fires_v += 1
	if f.lit {
		h.at, h.aside = feet_on(f.at), true   // the log's alone: a fire kept fed is no news
		say(h, "%s lays %d %s on the fire at %s.", who(h, i), n, "log" if n == 1 else "logs", place_say(h, f.at))
	} else {
		f.lit = true
		for &d in h.dwarves do d.felt_any = false
		h.at = feet_on(f.at)
		h.short = fmt.tprintf("%s lights the fire again.", who(h, i))
		say(h, "%s lays %d %s on the fire at %s and lights it again.", who(h, i), n, "log" if n == 1 else "logs", place_say(h, f.at))
	}
	return true
}

// Lay out the fires for the frame. Called with the hold's mutex held.
fires_show :: proc(h: ^Hold) {
	s := &h.shown
	builtin.resize(&s.fires, len(h.fires))
	for f, k in h.fires do s.fires[k] = {f.at, f.fuel, f.lit, f.fed, f.roof, f.walled, f.rained}
}

// How long a fire's timber lasts, in words.
fuel_words :: proc(fuel: f32, rained: bool) -> string {
	days := fuel/(FIRE_BURNS*(FIRE_RAIN if rained else 1))
	return "under an hour" if days < 1.0/24 else fmt.tprintf("about %s hours", count_words(int(math.round(days*24)))) if days < 0.45 else days_words(days)
}

// ---- the day's word -----------------------------------------------------------------------------------

// What the weather was yesterday and how the party slept, for the hold's word at dawn.
night_words :: proc(h: ^Hold, day: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, " The day %s.", day_weather_words(weather_day(day, stand_of(h.landed.camp))))
	slept: [Slept]int
	for &d in h.dwarves do if d.doing != .Dead {
		slept[d.slept] += 1
		d.slept = .None
	}
	names := [Slept]string{.None = "", .Open = "in the open", .Roof = "under a roof", .Indoors = "indoors", .Fire = "by a fire"}
	said := 0
	for how in ([4]Slept{.Indoors, .Roof, .Fire, .Open}) do if n := slept[how]; n > 0 {
		fmt.sbprintf(&b, "%s%s %s", " Last night " if said == 0 else ", ", count_words(n), fmt.tprintf("slept %s", names[how]) if said == 0 else names[how])
		said += 1
	}
	if said > 0 do fmt.sbprint(&b, ".")
	return strings.to_string(b)
}
