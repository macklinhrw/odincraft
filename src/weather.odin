package main

import "core:fmt"
import "core:math"

// The weather (plan.md, P4, second half; docs/adr/0015). The air's warmth, the rain, the wind and
// the sky at a place and a moment are one rule, a function of the island's climate (climate.odin),
// the place and the seconds since the boat stood off. Nothing is kept and nothing is drawn for the
// screen: the dwarves' world asks it of its own tick for where each dwarf stands, and the frame of
// the same count for the ground under the view, so what is drawn falling is what a dwarf is wet by.
//
//   the air     the island's mean for the year at the sea's level, the season's share of its swing
//               (warmest about 1 August, coldest about 30 January, as on Japan's islands), the hour's
//               share of the day's swing, less under cloud, and 0.65 °C colder each 100 m up
//   the sky     a spell of cloud two days long, drawn round the month's mean cover (SKY, render.odin),
//               passing into the next
//   the rain    falls in showers of three hours, the likelier the heavier the spell's cloud, for
//               the share of the year's hours that the place's own rain (land.rain) makes at
//               WET_HOUR mm an hour: so it rains more in the rainy months, more on ground rising
//               into the wind than in its lee, and whenever it rains in the lee it rains on the height
//   the wind    comes from the island's own bearing (region.shape.swell), stronger under a heavy
//               sky, stronger on ground that faces it and half as strong under a close wood
//   snow        is rain that falls through air of 1 °C or colder
//
// The party lands on the first fair morning from the equinox on, so the spells are counted from
// that day: the same for the same seed.

SHOWER   :: 3.0      // hours a shower's draw holds
WET_HOUR :: 1.8      // mm that fall in an hour of rain, taken over the year: Tanegashima's 2,400 mm fall in about 1,300 hours (from memory: JMA's hours of rain are not in the normals read for climate.odin)
DAILY    :: 3.5      // °C from the day's mean to its warmest hour under a clear sky: island stations swing 5 to 7 °C between a day's low and its high (from memory); RimWorld's is 7 either way, a continent's
CLOUDED  :: 0.6      // the share of that swing an overcast sky takes away
WARMEST  :: 212.0    // the day of the sun's year the air is warmest on, 0 on 1 January: about six weeks after the solstice, the sea's lag
WARM_HOUR :: 14.0    // the hour it is warmest at
SNOWS    :: 1.0      // °C at and under which what falls is snow
DRIES    :: 6.0      // hours the ground stays wet after rain
GUSTY    :: [3]f32{0.35, 0.6, 0.7}   // the wind of a spell, of SKY.wind: so much always, so much more under a full cover, and so much by the spell's own draw

Weather :: struct {
	cover, base: f32,   // the sky: cover 0 clear to 1 overcast, and the cloud base in metres
	rain:  f32,         // 0 for none, up to 1 for the heaviest
	snow:  bool,        // and it falls as snow
	air:   f32,         // °C
	wind:  f32,         // m/s, as this ground feels it
	wet:   f32,         // the ground: 0 dry to 1 wet, from the rain of the hours before
	// Why: the parts the air is made of, and the share of the year's hours rain falls here.
	season, hour, lapse, share, open: f32,
}

// What the weather reads of a place: its height, the rain that falls there in a year, and how
// open it lies to the wind. The air's mean and swing are the island's (region.climate).
Stand :: struct { height, rain, exposed: f32 }

// A spot of the island bound, at a point of its region and a height.
stand_at :: proc(x, z: f64, height: f32) -> (p: Stand) {
	p.height = max(height, 0)
	c := land_cell(x, z)
	if land.grid.sea[c] do return {p.height, region.climate.rain, 1}
	p.rain = land_at(land.rain, land.n >> 2, x, z)
	s := land.slope[c]
	toward := s/math.sqrt(1 + s*s)*math.cos(math.to_radians(land.facing[c] - f32(region.shape.swell)))   // 1 on a face square to the wind, -1 in its lee
	p.exposed = clamp(1 + 0.5*toward, 0.5, 1.5)
	if k := land.community[c]; k != 255 do p.exposed *= 1 - 0.5*COMMUNITIES[Community_Kind(k)].density   // a wood breaks the wind
	return
}

// The spot a block of the world is, on the island bound.
stand_of :: proc(b: [3]i32) -> Stand {
	return stand_at(f64(b.x - region.origin.x) + 0.5, f64(b.z - region.origin.y) + 0.5, f32(b.y))
}

// The share of the year's hours that rain falls where so much falls in a year.
rain_share :: proc(mm: f32) -> f32 { return clamp(mm/(WET_HOUR*8766), 0.03, 0.5) }

// A spell's draw: its cover round the month's mean, its cloud base, lower under a heavier cover,
// and its wind.
spell_draw :: proc(k: i32, month: int) -> (cover, base, wind: f32) {
	mean := SKY.cover[month %% 12]
	cover = math.pow(hash01(k, 0, world_seed + 700), 1/mean - 1)   // a draw whose mean is `mean`
	base = SKY.base[0] + (SKY.base[1] - SKY.base[0])*hash01(k, 1, world_seed + 700)*(1 - 0.5*cover)
	gusty := GUSTY
	wind = SKY.wind*(gusty[0] + gusty[1]*cover + gusty[2]*hash01(k, 3, world_seed + 700))
	return
}

// The day the spells are counted from: the first from the equinox on whose morning, at the hour
// the boat stands off, is fair.
weather_origin :: proc() -> f32 {
	for day in 0..<60 {
		t := (f32(day) + LANDS_AT/24)/SKY.spell
		k, w := i32(math.floor(t)), smoothstep(0, 1, t - math.floor(t))
		a, _, _ := spell_draw(k, 2)
		b, _, _ := spell_draw(k + 1, 2)
		if math.lerp(a, b, w) < FAIR do return f32(day)
	}
	return 0
}

// How much likelier rain is under a cover: hardly any falls from a broken sky.
heavy :: proc(cover: f32) -> f32 { return cover*cover*cover*cover }

// The sky at a moment: the spell's cover, base and wind, each passing into the next spell's.
sky_at :: proc(seconds: f64, from: f32 = -1) -> (cover, base, wind: f32) {
	origin := from if from >= 0 else weather_origin()
	t := (f64(origin) + seconds/DAY + LANDS_AT/24)/f64(SKY.spell)
	k, w := i32(math.floor(t)), smoothstep(0, 1, f32(t - math.floor(t)))
	for i in i32(0)..=1 {
		middle := ((f64(k + i) + 0.5)*f64(SKY.spell) - f64(origin) - LANDS_AT/24)*DAY   // the spell's middle, in seconds: its month is the sun's then
		c, b, v := spell_draw(k + i, int(date_at(max(middle, 0)).sun/365*12))
		share := w if i == 1 else 1 - w
		cover, base, wind = cover + c*share, base + b*share, wind + v*share
	}
	return
}

// The rain of a shower, 0 for none: it falls where the shower's draw is under the place's chance,
// and the heavier the further under. One draw is the whole island's, so the wetter place has the
// rain whenever the drier has, and heavier.
shower :: proc(p: i32, share, origin: f32) -> f32 {
	u := hash01(p, 2, world_seed + 700)
	if u >= 0.95 do return 0
	sum: f32   // the year's mean of `heavy`, by which the share is kept the year's
	for mean in SKY.cover do sum += 1/(4*(1/mean - 1) + 1)/12
	cover, _, _ := sky_at(((f64(p) + 0.5)*SHOWER/24 - f64(origin) - LANDS_AT/24)*DAY, origin)
	chance := min(share*heavy(cover)/sum, 0.95)
	return 0.3 + 0.7*(1 - u/chance) if u < chance else 0
}

// The weather at a place, so many seconds of the world's time after the boat stood off.
weather :: proc(seconds: f64, at: Stand) -> (w: Weather) {
	date := date_at(seconds)
	origin := weather_origin()
	w.cover, w.base, w.wind = sky_at(seconds, origin)
	w.open = at.exposed
	w.wind *= at.exposed
	// The rain: this shower's, coming on and going off over its first and last tenth.
	w.share = rain_share(at.rain)
	t := (f64(origin) + seconds/DAY + LANDS_AT/24)*24/SHOWER
	p, f := i32(math.floor(t)), f32(t - math.floor(t))
	now := shower(p, w.share, origin)
	w.rain = now
	if f < 0.1 do w.rain = math.lerp(shower(p - 1, w.share, origin), now, 0.5 + 5*f)
	else if f > 0.9 do w.rain = math.lerp(now, shower(p + 1, w.share, origin), 5*(f - 0.9))
	w.wet = min(1.5*w.rain, 1)
	for j in i32(1)..=2 do w.wet = max(w.wet, min(1.5*shower(p - j, w.share, origin), 1)*clamp(1 - (f + f32(j) - 1)*SHOWER/DRIES, 0, 1))
	// The air.
	c := region.climate
	w.season = c.swing*math.cos(math.TAU*(date.sun - WARMEST)/365)
	w.hour = DAILY*(1 - CLOUDED*w.cover)*math.cos(math.TAU*(date.hour - WARM_HOUR)/24)
	w.lapse = -LAPSE*at.height
	w.air = c.mean + w.season + w.hour + w.lapse
	w.snow = w.rain > 0 && w.air <= SNOWS
	return
}

// ---- words ----------------------------------------------------------------------------------------

// The sky and what falls from it, in a word or two: "Rain", "Fair", "Light snow".
weather_name :: proc(w: Weather) -> string {
	if w.rain > 0 {
		what := "snow" if w.snow else "rain"
		return fmt.tprintf("Light %s", what) if w.rain < 0.45 else fmt.tprintf("Heavy %s", what) if w.rain > 0.8 else capital(what)
	}
	return "Clear" if w.cover < 0.12 else "Fair" if w.cover < FAIR else "Cloudy" if w.cover < 0.7 else "Overcast"
}

// The wind in a word, and where it comes from; "" when the air is still.
wind_name :: proc(w: Weather) -> string {
	if w.wind < 2 do return ""
	b := math.to_radians(f64(region.shape.swell))
	return fmt.tprintf("%s from the %s", "a breeze" if w.wind < 5 else "wind" if w.wind < 9 else "strong wind", compass(math.sin(b), -math.cos(b)))
}

// The weather in a line, as the screen says it under the date: "Rain, 9 °C, wind from the east".
weather_line :: proc(w: Weather) -> string {
	wind := wind_name(w)
	return fmt.tprintf("%s, %.0f °C%s%s", weather_name(w), math.round(w.air), ", " if wind != "" else "", wind)
}

// Why the weather is what it is here, as --why prints it and the screen says beside the pointer.
weather_why :: proc(w: Weather, at: Stand, date: Date) -> string {
	c := region.climate
	open := "open ground" if w.open > 0.85 && w.open < 1.15 else "ground that faces the wind" if w.open >= 1.15 else "ground in the lee, or under trees"
	return fmt.tprintf("%.1f °C: the island's %.1f a year at the sea's level, %+.1f for the %s, %+.1f for the hour under a sky %.0f%% covered, %+.1f for %.0f m of height. Rain falls here %.0f%% of the year's hours, where %.0f mm fall a year; it falls in showers under a heavy sky. The wind is %.0f m/s on %s. The ground is %s.",
		w.air, c.mean, w.season, date_words(date), w.hour, 100*w.cover, w.lapse, at.height, 100*w.share, at.rain, w.wind, open,
		"dry" if w.wet < 0.15 else "drying" if w.rain == 0 else "wet")
}

// A day's weather at a place, for the hold's word at dawn and a run's summary: the coldest and the
// warmest hour's air, the hours it rained, whether any of it was snow, and the strongest wind.
Day_Weather :: struct { low, high, wind: f32, rained: int, snowed: bool }
weather_day :: proc(day: int, at: Stand) -> (d: Day_Weather) {
	d.low, d.high = 1e9, -1e9
	for h in 0..<24 {
		w := weather((f64(day) + (f64(h) + 0.5 - LANDS_AT)/24)*DAY, at)
		d.low, d.high, d.wind = min(d.low, w.air), max(d.high, w.air), max(d.wind, w.wind)
		d.rained += int(w.rain > 0)
		d.snowed ||= w.snow
	}
	return
}

// A day's weather in words, after "The day": "had nine hours of rain, 6 to 11 °C".
day_weather_words :: proc(d: Day_Weather) -> string {
	what := "snow" if d.snowed else "rain"
	fell := "was dry" if d.rained == 0 else fmt.tprintf("had an hour of %s", what) if d.rained == 1 else fmt.tprintf("had %s hours of %s", count_words(d.rained), what) if d.rained < 20 else fmt.tprintf("had %s all day", what)
	return fmt.tprintf("%s, %.0f to %.0f °C%s", fell, math.round(d.low), math.round(d.high), ", and a strong wind" if d.wind >= 9 else "")
}

// The year's weather at a place, season by season, as start-up prints it: what a party has to live through.
weather_say :: proc(at: Stand, where_: string) {
	if quiet do return
	fmt.printfln("weather %s, by the island's climate (%.1f °C a year at the sea, %.1f either way by the month; %.0f mm of rain a year here, so rain %.0f%% of the hours; the wind from %.0f°, felt %.0f%% here):",
		where_, region.climate.mean, region.climate.swing, at.rain, 100*rain_share(at.rain), region.shape.swell, 100*at.exposed)
	for season, s in SEASONS {
		low, high, rained, snowed, nights := f32(1e9), f32(-1e9), 0, 0, f32(0)
		for n in 0..<SEASON_DAYS {
			d := weather_day(s*SEASON_DAYS + n, at)
			low, high = min(low, d.low), max(high, d.high)
			rained += d.rained
			snowed += int(d.snowed)
			nights += d.low/SEASON_DAYS
		}
		fmt.printfln("  %s: %.0f to %.0f °C, the nights' coldest hour %.1f on average; rain %d of its %d hours%s", season, low, high, nights, rained, 24*SEASON_DAYS, fmt.tprintf("; snow on %d days", snowed) if snowed > 0 else "")
	}
	fmt.print("  the first rains:")   // when, for whoever would see one
	said := 0
	for day := 0; day < YEAR_DAYS && said < 4; day += 1 do for h := 0; h < 24 && said < 4; h += 1 {
		wet := proc(day, h: int, at: Stand) -> bool { return weather((f64(day) + (f64(h) + 0.5 - LANDS_AT)/24)*DAY, at).rain > 0 }
		if !wet(day, h, at) || h > 0 && wet(day, h - 1, at) do continue
		until := h
		for until < 24 && wet(day, until, at) do until += 1
		fmt.printf("%s the %s from %02d:00 to %02d:00", "" if said == 0 else ";", date_words(date_at((f64(day) + 0.5)*DAY)), h, until)
		said += 1
	}
	fmt.println()
}

// The weather over a point of the world, for the frame: on the island nearest, at the ground's
// height there, or at the eye's where the player walks.
weather_over :: proc(at: [3]f64, seconds: f64, afoot: bool) -> (w: Weather, place: Stand) {
	f := island_near(at.x, at.z)
	if f == nil do return
	height := f32(at.y) if afoot else f32(ground_top(at.x, at.z))
	was := bound(f)
	place = stand_at(at.x - f64(region.origin.x), at.z - f64(region.origin.y), height)
	w = weather(seconds, place)
	bound(was)
	return
}
