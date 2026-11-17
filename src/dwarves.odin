package main

import "base:builtin"
import "core:fmt"
import "core:math"
import "core:math/linalg"

// The dwarves (plan.md, P2): who each one is, how it is drawn and what it says of itself. What
// they do is the hold's (hold.odin).
//
// Dwarves are common fantasy stock; these are our own. A dwarf stands under one and a half blocks,
// so a passage two blocks high is roomy (open-decisions.md, 2026-11-16). It comes of age at 25 and
// is old past 100 (a guess, to be settled when age first matters). Its name is made by a rule and
// taken from no one's setting: a given name of a stem and an ending, and a byname as a workmate
// would give it, an earth or a rock and a part of the body or of what is worn. Its trade is a row.
// A party is drawn from the world's seed, no trade twice until every trade has come.

Trade :: struct {
	name, does: string,
	weight:     f32,   // how often a party sent to found a hold brings one
	cloth:      u32,   // its tunic, as 0xRRGGBB
}
TRADES := [?]Trade{
	{"miner", "digs rock and follows a seam", 3, 0x6b5a48},
	{"mason", "cuts and lays stone", 3, 0x7d7f86},
	{"woodcutter", "fells and splits timber", 3, 0x4f6b3a},
	{"grower", "tends seed and field", 3, 0x9a8a3a},
	{"carpenter", "joins timber", 2, 0x8a5a2b},
	{"fisher", "takes fish from stream and shore", 2, 0x3f6f8a},
	{"smith", "works metal at the fire", 2, 0x5a2e22},
	{"cook", "keeps the pot and the stores", 2, 0x9c8e74},
	{"brewer", "makes drink of what grows", 2, 0x7a3f5a},
	{"herder", "keeps beasts", 1, 0x8a6a4a},
	{"weaver", "spins and weaves", 1, 0x6e4a5e},
	{"healer", "sets bones and dresses wounds", 1, 0xa8a898},
}
STEMS  := [?]string{"Bram", "Dorr", "Fenn", "Hild", "Jorr", "Kelv", "Marr", "Nesk", "Odd", "Rusk", "Sild", "Ulv", "Vesk", "Wend", "Brek", "Stav", "Grett", "Holm", "Mund", "Ard", "Esk", "Tov", "Yrs"}
ENDS   := [?]string{"a", "e", "en", "et", "ik", "o", "um", "ar", "an", "is", "or"}
EARTHS := [?]string{"Slate", "Marl", "Grit", "Chalk", "Ash", "Cinder", "Shale", "Salt", "Peat", "Coal", "Tuff", "Clay", "Soot", "Ochre"}
WORN   := [?]string{"thumb", "knuckle", "brow", "sleeve", "apron", "shank", "back", "tongue", "elbow", "heel", "cap", "boot"}
SKINS  := [?]u32{0xc89a7a, 0xb07a58, 0x8a5c40}
BEARDS := [?]u32{0x2a2018, 0x5a3a20, 0x8a4a22, 0xb89858}   // black, brown, russet, sandy; all grey with age
HOODS  := [?]u32{0x3a3a44, 0x4a3a2a, 0x2f4030, 0x5a2a2a}
AGES   :: [2]f32{25, 115}   // the youngest and oldest a party takes
TALL   :: [2]f32{1.25, 1.45}

// Who a dwarf is: drawn once, and not changed in this step.
Facts :: struct {
	given, byname: string,
	age, trade:    int,
	tall:          f32,
	skin, beard, hood: u32,
}

// The party of a world's seed, of so many: no trade twice until every trade has come. A party can
// be drawn again (plan.md, E-1): `draws` is how often the whole of it has been, and `again` which of
// its dwarves were then drawn again one at a time, from 0, in the order they were. The same seed,
// count and draws give the same party, so a party chosen before play can be drawn again by the hold
// and by anyone who plays its log again.
party_draw :: proc(s: u32, count: int, party: ^[dynamic]Facts, draws := 0, again: []int = nil) {
	s := s if draws == 0 else hash(i32(draws), 0, s + 899)
	// Trades by the weighted draw the plants' race uses: each row's key is a draw to the power one
	// over its weight, and the highest not yet taken comes next.
	builtin.resize(party, count)
	taken: [len(TRADES)]bool
	for &f, i in party {
		f = {}
		if i%len(TRADES) == 0 do taken = {}
		best := f32(-1)
		for row, k in TRADES do if key := math.pow(hash01(i32(k), i32(i/len(TRADES)), s + 900), 1/row.weight); !taken[k] && key > best do f.trade, best = k, key
		taken[f.trade] = true
		facts_draw(&f, i, s, party[:i])
	}
	// One drawn again is another dwarf in the same seat: a name, an age and a look of its own, and the
	// trade its own draw puts first of those no other of its dozen has. No one else is changed by it.
	for i, k in again do if i >= 0 && i < count {
		own := hash(i32(k + 1), i32(i), s + 898)
		taken = {}
		for o, j in party do if j != i && j/len(TRADES) == i/len(TRADES) do taken[o.trade] = true
		f := Facts{trade = party[i].trade}
		best := f32(-1)
		for row, t in TRADES do if key := math.pow(hash01(i32(t), i32(i), own + 900), 1/row.weight); !taken[t] && key > best do f.trade, best = t, key
		party[i] = {}   // its name is free for the one who takes its seat, and for nobody to share
		facts_draw(&f, i, own, party[:])
		party[i] = f
	}
}

// Who a dwarf is besides its trade, the `i`th of a party, drawn from `s`: no two of a party share a given name.
facts_draw :: proc(f: ^Facts, i: int, s: u32, others: []Facts) {
	for try in i32(0)..<64 {
		f.given = fmt.aprintf("%s%s", STEMS[hash(i32(i), try, s + 901)%len(STEMS)], ENDS[hash(i32(i), try, s + 902)%len(ENDS)])
		same := false
		for o in others do same ||= o.given == f.given
		if !same do break
	}
	f.byname = fmt.aprintf("%s%s", EARTHS[hash(i32(i), 0, s + 903)%len(EARTHS)], WORN[hash(i32(i), 0, s + 904)%len(WORN)])
	u := hash01(i32(i), 0, s + 905)
	f.age = int(math.lerp(AGES[0], AGES[1], u*u))   // more of them young
	f.tall = math.lerp(TALL[0], TALL[1], hash01(i32(i), 0, s + 906))
	f.skin, f.hood = SKINS[hash(i32(i), 0, s + 907)%len(SKINS)], HOODS[hash(i32(i), 0, s + 908)%len(HOODS)]
	grey := smoothstep(55, 100, f32(f.age))
	dark := BEARDS[hash(i32(i), 0, s + 909)%len(BEARDS)]
	f.beard = 0
	for shift in ([3]u32{16, 8, 0}) do f.beard |= u32(math.lerp(f32(dark >> shift & 255), f32(u32(0xb8b8b0) >> shift & 255), grey)) << shift
}

// A dwarf in a sentence: "Dorra Slatethumb, a mason of 61 years".
dwarf_name :: proc(f: Facts) -> string {
	return fmt.tprintf("%s %s, a %s of %d years", f.given, f.byname, TRADES[f.trade].name, f.age)
}

// One box of a body, turned about a pivot by `swing` round the axis across the body, as a leg or an arm swings.
limb :: proc(out: ^[dynamic]Box, feet: [3]f32, R: matrix[3, 3]f32, at, half: [3]f32, upper, under: u32, pivot: [3]f32 = {}, swing: f32 = 0, whole := true) {
	c, m := at, linalg.MATRIX3F32_IDENTITY
	if swing != 0 {
		m = linalg.matrix3_rotate_f32(swing, [3]f32{1, 0, 0})
		c = pivot + m*(at - pivot)
	}
	a := R*m
	append(out, Box{feet + R*c, f32(upper), a*[3]f32{half.x, 0, 0}, f32(under), a*[3]f32{0, half.y, 0}, 0, a*[3]f32{0, 0, half.z}, feet.y if whole else 0})
}

// The axes of a body heading `bearing` (radians from north), `scale` times its drawn size: right, up and forward.
heading :: proc(bearing, scale: f32) -> matrix[3, 3]f32 {
	r, u, f := [3]f32{math.cos(bearing), 0, math.sin(bearing)}*scale, [3]f32{0, scale, 0}, [3]f32{math.sin(bearing), 0, -math.cos(bearing)}*scale
	return matrix[3, 3]f32{r.x, u.x, f.x, r.y, u.y, f.y, r.z, u.z, f.z}
}

// A dwarf as sixteen boxes, its feet at `feet` from the eye: boots and legs, a broad tunic with a
// belt, arms and hands, a head with a hood, a nose, eyes and a beard. `stride` is the metres it has walked,
// which swing its legs and arms; seated, its legs lie forward.
dwarf_boxes :: proc(out: ^[dynamic]Box, f: Facts, feet: [3]f32, bearing: f32, stride: f64, moving, seated: bool, toil: f32 = -1, carry := Mat.Air, carrying: i32 = 0) {
	R := heading(bearing, f.tall/1.36)
	swing := 0.7*f32(math.sin(math.mod(stride, 1.3)/1.3*math.TAU)) if moving else 0
	strike := 1.3 + 0.9*math.sin(toil*5.5) if toil >= 0 else 0   // at work, both arms are raised and brought down
	if carrying > 0 do strike = 2.75   // and held up under what it carries
	cloth, at := TRADES[f.trade].cloth, feet
	if seated do at.y -= 0.22*f.tall/1.36
	for side in ([2]f32{-1, 1}) {
		leg := 1.45 if seated else side*swing
		limb(out, at, R, {side*0.11, 0.22, 0}, {0.095, 0.22, 0.11}, 0x3a3028, 0x3a3028, {0, 0.44, 0}, leg)
		limb(out, at, R, {side*0.11, 0.07, 0.03}, {0.105, 0.07, 0.15}, 0x2a2018, 0x2a2018, {0, 0.44, 0}, leg)   // the boot
		limb(out, at, R, {side*0.33, 0.72, 0}, {0.075, 0.2, 0.085}, cloth, cloth, {0, 0.92, 0}, strike - side*swing*0.8)
		limb(out, at, R, {side*0.33, 0.47, 0}, {0.06, 0.055, 0.07}, f.skin, f.skin, {0, 0.92, 0}, strike - side*swing*0.8)   // the hand
		limb(out, at, R, {side*0.065, 1.16, 0.165}, {0.025, 0.022, 0.01}, 0x18120e, 0x18120e)   // an eye
	}
	limb(out, at, R, {0, 0.70, 0}, {0.25, 0.27, 0.16}, cloth, cloth)
	limb(out, at, R, {0, 0.50, 0}, {0.26, 0.04, 0.17}, 0x2a2018, 0x2a2018)   // the belt
	limb(out, at, R, {0, 1.11, 0.01}, {0.15, 0.14, 0.15}, f.skin, f.skin)
	limb(out, at, R, {0, 1.21, -0.03}, {0.17, 0.15, 0.15}, f.hood, f.hood)   // the hood, over the crown and down the back of the head
	limb(out, at, R, {0, 1.10, 0.18}, {0.03, 0.035, 0.03}, f.skin, f.skin)
	limb(out, at, R, {0, 0.93, 0.15}, {0.13, 0.14, 0.05}, f.beard, f.beard)
	if carrying > 0 {   // what it carries, on its head and hands: a block of the stone, or a log, and a second over it for a full load
		rgb := mat_rgb(carry)
		timber := is_stuff(carry, .Timber)
		for k in 0..<min(carrying, 2) {
			half := [3]f32{0.42, 0.11, 0.11} if timber else {0.19, 0.17, 0.19}
			limb(out, at, R, {0, 1.5 + 2*half.y*f32(k) + half.y, 0.04}, half, mat_rgb(.Timber) if timber && k == min(carrying, 2) - 1 else rgb, rgb)
		}
	}
}

// The boat as boxes, its middle at `at` from the eye on the water, its bow toward `bearing`: a
// floor, two sides, a bow and a stern, and three thwarts.
boat_boxes :: proc(out: ^[dynamic]Box, at: [3]f32, bearing: f32) {
	R := heading(bearing, 1)
	tar, wood: u32 = 0x2e2218, 0x6b4f33
	limb(out, at, R, {0, 0, 0}, {0.8, 0.06, 2.9}, wood, tar)   // its boards, a hand over the water: the sea is not drawn out of a hull
	for side in ([2]f32{-1, 1}) do limb(out, at, R, {side*0.82, 0.2, 0}, {0.06, 0.36, 2.9}, wood, tar)
	limb(out, at, R, {0, 0.3, 3.05}, {0.55, 0.46, 0.25}, wood, tar)
	limb(out, at, R, {0, 0.24, -2.95}, {0.8, 0.4, 0.08}, wood, tar)
	for z in ([3]f32{1.6, 0.6, -0.4}) do limb(out, at, R, {0, 0.34, z}, {0.78, 0.03, 0.12}, wood, wood)
}

// Where a dwarf sits in the boat: metres to the right of its middle and toward its bow.
SEATS := [LANDING][2]f64{{-0.38, 1.25}, {0.38, 1.25}, {-0.38, 0.25}, {0.38, 0.25}, {-0.38, -0.75}, {0.38, -0.75}, {0, -1.8}}

// A point of the compass in words, from a way east and south.
compass :: proc(dx, dz: f64) -> string {
	names := [8]string{"north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"}
	return names[int(math.round(math.mod(math.to_degrees(math.atan2(dx, -dz)) + 360, 360)/45))%8]
}
