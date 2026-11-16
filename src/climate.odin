package main

import "core:fmt"
import "core:math"
import "core:math/linalg"

// Climate per island (docs/foundations/climate.md; step 25). Each island has a base climate from the
// latitude its climate follows and the sea round it: the year's mean temperature at the sea's level,
// how far the months swing from it, and the rain that falls on the sea round it. The land then makes
// its own: the air cools with height, and rain falls heavier on high ground and on ground rising into
// the wind, and lighter in the lee. Zones are named over those fields as rows.
//
// The known world's 1,000 km stand for about thirty degrees of latitude (the owner, 2026-11-16): the
// plates keep the Earth's true geometry, and the latitude a place's climate follows is stretched about
// three times from the start's own. The start's climate is at its true latitude, so the islands round
// it keep their true place and only the far known world is stretched. The sun follows the same
// latitude, so the sky and what grows under it never disagree (climate.md, D2).
CLIMATE_DEGREES :: 30   // of latitude, that the known world's 1,000 km stand for

// The island's base climate (Region.climate), worked out before it is formed from its record alone.
Climate :: struct {
	mean:     f32,   // °C, the year's mean in the air at the sea's level
	swing:    f32,   // °C from the year's mean to the warmest month's mean, and down to the coldest's
	rain:     f32,   // mm a year that falls on the sea round the island
	offshore: f32,   // km to land larger than a region, which makes the year swing wider
	truly:    f32,   // degrees north the island truly stands at; its climate's latitude is Region.latitude
}

// Fitted to the 1991-2020 normals of 24 Japanese island stations from 24 to 45° N (JMA), each taken to
// the sea's level by LAPSE: the year's mean falls 0.84 °C for each degree north, within 0.55 °C (root
// mean square) of them all and 1.2 °C of the worst, Hachijōjima, which the Kuroshio warms. South of 22°
// it holds at 27 °C, as the tropical Pacific's islands do (from memory). How far the months swing grows
// northward and near land larger than a region, whose winter reaches out over the sea: within 0.64 °C of
// the same stations, the worst Minamitorishima, 1,800 km from any such land, at 3.3 °C against 4.9.
// Izuhara on Tsushima, 50 km from Korea, swings 10.4. Kira's warmth index from these is within 15 of
// every station's own (docs/interesting-world/notes/real-climate.md).
LAPSE :: 0.0065   // °C a metre up (US Standard Atmosphere 1976; Unzendake at 678 m is 0.68 °C a 100 m under Nagasaki, and Fuji's summit 0.60)
sea_mean  :: proc(latitude: f32) -> f32 { return min(20.5 - 0.84*(abs(latitude) - 30), 27.2) }
sea_swing :: proc(latitude, offshore: f32) -> f32 { return max(6.6 + 0.29*(abs(latitude) - 30) + 2.2*math.exp(-offshore/150), 1) }

// The rain that falls on the sea, by latitude, from island stations on low ground or with the island's
// own lift taken out (JMA's 1991-2020 normals; the lift as RAIN_RISE and RAIN_LEE give it on GSI's
// elevation model of the island): between rows, as far as the one to the other.
Rain_Row :: struct { latitude, rain: f32 }
RAINS := [?]Rain_Row{
	{24, 1900},   // Ishigaki 2,096 mm, Naha 2,161, Minamidaitō 1,639
	{28, 1900},   // Kikaijima 1,893 and Okinoerabu 1,857, low islands of reef
	{31, 2400},   // Tanegashima, 280 m high: 2,532 on the coast, 2,400 over the sea round it
	{34, 2400},   // round Hachijōjima 2,800, Miyakejima 2,700, Ōshima 3,200, Tsushima 1,800 with each island's lift taken out; Niijima's coast 2,225
	{36, 1750},   // Saigō on Oki 1,816
	{39, 1450},   // Tobishima, 68 m high, 1,429
	{42, 950},    // Okushiri's coast 920
	{45, 900},    // Rishiri's coast 916, Wakkanai 1,109
}
sea_rain :: proc(latitude: f32) -> f32 {
	l := abs(latitude)
	if l <= RAINS[0].latitude do return RAINS[0].rain
	for r, i in RAINS[1:] do if l <= r.latitude {
		was := RAINS[i]
		return math.lerp(was.rain, r.rain, (l - was.latitude)/(r.latitude - was.latitude))
	}
	return RAINS[len(RAINS) - 1].rain
}

// Rain over the land: the sea's, more by RAIN_RISE for each km of height up to RAIN_TOP, and by RAIN_LEE
// for each km the ground stands over the ground upwind, which counts less the further off it lies, as
// e to the minus its distance over RAIN_FALL; under it, the lee, less; never under RAIN_LEAST of the
// sea's. It is the upslope model of orographic rain whose cloud is carried on and falls out over a few
// kilometres (Smith 1979; Smith and Barstad 2004), with one wind. Fitted on GSI's elevation model of the
// four islands with more than one station (JMA's normals), the wind from each island's best bearing; the
// fit is as good from 1.5 to 3 a km over 2 to 5 km, and the middle was taken:
//   Tanegashima, 280 m high: 2,532 mm on its coast, 3,138 at 150 m and 2,989 at 234 m, within 6%
//   Yakushima: its west lowland 2,980 mm (2,400 to 3,600, RIHN's Yakushima page), its east 4,840 (4,200
//   to 5,500), over 1,000 m 10,800 (6,000 to 10,000); Koseda 4,616 (4,652) and Onoaida 3,425 (3,399)
//   Ōshima: Motomachi 2,762 (2,859), Kitanoyama 2,202 (2,127)
//   Tsushima's north tip (Waniura 1,435 against Izuhara's 2,303) it does not give: its relief is not why.
// Tanegashima, Nagasaki under Unzendake (1,895 mm at 27 m, 2,927 at 678) and Yakushima's heights each
// give rain about doubling by 1,000 m. Rain at a point at the 64 m grid (land.rain).
RAIN_RISE  :: 1.0     // the sea's rain more for each km of height,
RAIN_TOP   :: 1000    // up to this height, m (Yakushima's wettest gauges stand at 1,000 to 1,400 m)
RAIN_LEE   :: 1.5     // the sea's rain more for each km the ground stands over the ground upwind
RAIN_FALL  :: 5000    // m over which the ground upwind counts, falling away as e^(-d/RAIN_FALL)
RAIN_LEAST :: 0.3

// The latitude a point in the world's climate follows: the start's own, and north of it the true
// distance in latitude stretched so the known world's 1,000 km span CLIMATE_DEGREES.
climate_latitude :: proc(x, z: f64) -> (climate, truly: f32) {
	at := known_point(x, z)
	truly = math.to_degrees(math.asin(linalg.normalize(known.centre + (at.x*known.east - at.y*known.north)/PLANET).z))
	return world_frame.latitude + (truly - world_frame.latitude)*CLIMATE_DEGREES/math.to_degrees(f32(1000/PLANET)), truly
}

// The island's base climate, at its middle.
climate_init :: proc(is: Island) {
	o := [2]f64{f64(is.origin.x), f64(is.origin.y)}
	c := &region.climate
	latitude, truly := climate_latitude(o.x, o.y)
	region.latitude, c.truly = f64(latitude), truly
	c.offshore = max(-world_at(o.x, o.y).inland, 0)
	c.mean, c.swing, c.rain = sea_mean(latitude), sea_swing(latitude, c.offshore), sea_rain(latitude)
}

// Kira's warmth index from a year's mean and swing: the sum over the months of each month's mean above
// 5 °C, the months a cosine through the year. Japan's forests follow it (Kira 1977): evergreen broadleaf
// from 85 to 180 °C·months, subtropical over 180, beech from 45 to 85, fir and spruce from 15 to 45.
MONTHS :: [12]f32{0.966, 0.707, 0.259, -0.259, -0.707, -0.966, -0.966, -0.707, -0.259, 0.259, 0.707, 0.966}   // cos((k + 0.5)·30°), each month's share of the swing
warmth :: proc(mean, swing: f32) -> (w: f32) {
	for c in MONTHS do w += max(mean + swing*c - 5, 0)
	return
}

// Holdridge's potential evapotranspiration ratio: 58.93 mm a year for each degree of the year's
// biotemperature (the months' means held between 0 and 30 °C, averaged), over the rain (Holdridge 1967).
// Chichijima's 23.4 °C and 1,296 mm make 1.06, a dry forest, as its scrub is; Tobishima's 12.8 °C and
// 1,429 mm 0.53, moist; Yakushima's east lowland, 19.6 °C and about 4,800 mm, 0.24, a rain forest.
dryness :: proc(mean, swing, rain: f32) -> f32 {
	bio: f32
	for c in MONTHS do bio += clamp(mean + swing*c, 0, 30)/12
	return 58.93*bio/max(rain, 1)
}

// The year's mean at the ground's height at a point, which the sea's level stands in for at sea.
temperature_at :: proc(p: ^Point) -> f32 {
	return region.climate.mean - LAPSE*max(grid_at(land.z[0], p), 0)
}

rain_at :: proc(p: ^Point) -> f32 { return land_at(land.rain, land.n >> 2, p.x, p.z) }

// Rain at each cell of the 64 m grid, and its mean over the land.
land_rain :: proc() {
	n := land.n >> 2
	delete(land.rain)
	land.rain = make([]f32, n*n)
	Sweep :: struct { n: int, wind: [2]f32, weights: []f32 }
	bearing := math.to_radians(f32(region.shape.swell))
	s := Sweep{n = n, wind = {math.sin(bearing), -math.cos(bearing)}, weights = make([]f32, int(3*RAIN_FALL/64) + 1, context.temp_allocator)}   // toward where the wind comes from
	for &w, k in s.weights do w = math.exp(-f32(k)*64/RAIN_FALL)
	shared(n, rows(n), &s, proc(s: ^Sweep, lo, hi: int) {
		n, z := s.n, land.z[2]
		for c in lo*n..<hi*n {
			up, all: f32
			for w, k in s.weights {
				i, j := int(math.floor(f32(c%n) + 0.5 + s.wind.x*f32(k))), int(math.floor(f32(c/n) + 0.5 + s.wind.y*f32(k)))
				if i >= 0 && j >= 0 && i < n && j < n do up += w*max(z[j*n + i], 0)   // past the region's rim, the open sea
				all += w
			}
			h := max(z[c], 0)
			land.rain[c] = region.climate.rain*max(RAIN_LEAST, 1 + RAIN_RISE*min(h, RAIN_TOP)/1000 + RAIN_LEE*(h - up/all)/1000)
		}
	})
	sum, cells: f32
	for v, c in land.rain do if land.z[2][c] > 0 { sum += v; cells += 1 }
	land.rained = sum/max(cells, 1)
}

// The climate zones, as an ordered catalogue over the fields: the first row whose host holds. A zone
// names what grows in it in Japan's islands, which floras will read (step 26).
Zone :: struct {
	name, why: string,
	host:      []Window,
	colour:    [3]f32,   // on the map
}
ZONES := [?]Zone{
	{"subalpine", "too cool for beech: fir and dwarf bamboo, as over about 1,600 m in central Honshu (memory)", {{.Warmth, -ANY, 45, 0}}, {0.55, 0.55, 0.75}},
	{"cool-temperate", "too cool for the evergreen wood: beech and other trees that drop their leaves, as on Okushiri and Rishiri", {{.Warmth, -ANY, 85, 0}}, {0.75, 0.55, 0.20}},
	{"dry evergreen", "too dry for a tall closed wood, the warmth drawing as much water as falls: low evergreen scrub, as on Chichijima", {{.Dryness, 1, ANY, 0}}, {0.90, 0.80, 0.45}},
	{"subtropical", "warm enough all year for the subtropical evergreen wood, tree ferns and banyans, as on Amami and Okinawa", {{.Warmth, 180, ANY, 0}}, {0.85, 0.30, 0.45}},
	{"wet evergreen", "so wet for its warmth that moss hangs from the evergreen wood, Holdridge's rain forest, as on Yakushima's east side and heights", {{.Dryness, -ANY, 0.25, 0}}, {0.05, 0.60, 0.60}},
	{"warm-temperate", "the evergreen wood of shii, tabu and evergreen oaks, as on the Izu islands and Tsushima", {}, {0.25, 0.60, 0.25}},
}
zone_at :: proc(p: ^Point) -> int {
	for z, i in ZONES do if host(z.host, p) > 0 do return i
	return len(ZONES) - 1
}

// The island's climate, as start-up prints it, read on the 64 m grid the rain is worked on.
climate_say :: proc() {
	if quiet do return
	c := region.climate
	n, d := land.n >> 2, f64(region.size)/f64(land.n >> 2)
	shares: [len(ZONES)]f32
	lo, hi, cells := f32(1e9), f32(0), f32(0)
	// The lowlands, under 100 m, on the third of the region toward the wind and the third away from it,
	// as the real islands' stations on opposite coasts are compared.
	sides: [2][dynamic]f32
	sides[0], sides[1] = make([dynamic]f32, context.temp_allocator), make([dynamic]f32, context.temp_allocator)
	bearing := math.to_radians(region.shape.swell)
	for k in 0..<n*n do if h := land.z[2][k]; h > 0 {
		p := Point{x = (f64(k%n) + 0.5)*d - region.size/2, z = (f64(k/n) + 0.5)*d - region.size/2, cell = LAND_CELL}
		shares[zone_at(&p)] += 1
		cells += 1
		r := land.rain[k]
		lo, hi = min(lo, r), max(hi, r)
		if along := p.x*math.sin(bearing) - p.z*math.cos(bearing); h < 100 && abs(along) > region.size/6 do append(&sides[0 if along > 0 else 1], r)
	}
	fmt.printf("climate: of %.1f° N, where the island truly stands at %.1f° N (the known world's 1,000 km stand for %d° of latitude about the start's own); at the sea's level %.1f °C a year, %.1f in the coldest month and %.1f in the warmest (%.0f km off larger land), warmth %.0f; %.0f mm of rain on the sea round it, %.0f to %.0f on the land, %.0f on average; under 100 m %.0f on the third toward the wind from %.0f° and %.0f on the third away from it; zones:",
		region.latitude, c.truly, CLIMATE_DEGREES, c.mean, c.mean - c.swing, c.mean + c.swing, c.offshore, warmth(c.mean, c.swing), c.rain, lo, hi, land.rained, middle(sides[0][:]), region.shape.swell, middle(sides[1][:]))
	for s, i in shares do if s > 0 do fmt.printf(" %s %.0f%%", ZONES[i].name, 100*s/cells)
	fmt.println()
}

// The climate at a point, as --why prints it.
climate_words :: proc(p: ^Point) {
	z := ZONES[zone_at(p)]
	t := temperature_at(p)
	fmt.printfln("the climate: %s, %s; here %.1f °C a year (%.1f in the coldest month, %.1f in the warmest), warmth %.0f, and %.0f mm of rain, the sea's %.0f at %.1f° N and the wind from %.0f°",
		z.name, z.why, t, t - region.climate.swing, t + region.climate.swing, warmth(t, region.climate.swing), rain_at(p), region.climate.rain, region.latitude, region.shape.swell)
}
