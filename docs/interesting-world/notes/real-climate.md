# The real islands' climate

What step 25's climate is fitted to and judged against: the 1991–2020 normals of Japanese island stations, the rain by height and side on six islands, and the zones their forests make. Measured 2026-11-16 by Claude. The code is `src/climate.odin`; the step is in `foundations.md` section 8, "Step 25, as built".

## Sources

- **JMA's normals, 1991–2020.** Each station's page of monthly and yearly normals, `https://www.data.jma.go.jp/stats/etrn/view/nml_sfc_ym.php?prec_no=P&block_no=B` (staffed stations) or `nml_amd_ym.php` (AMeDAS). The yearly tables, `annually_s.php`, give each year's largest day of rain.
- **GSI's elevation tiles** (DEM10B, `dem_png`, zoom 12, about 33 m to the pixel), decoded as in `real-islands.md`, averaged to 66 m. Credit: 国土地理院 (GSI) elevation tiles, resampled and processed for this note. 64 tiles, kept outside the repository.
- **Yakushima's rain by side and height**: RIHN's Ichikawa project page on Yaku Island ([chikyu.ac.jp](https://www.chikyu.ac.jp/ichikawa-pro/English/pages/Yaku.html)): "approximately 6,000–10,000 mm" at high altitude, "4,200–5,500 mm" in the eastern lowland and "2,400–3,600 mm" in the western lowland. The same page gives its belts: broad-leaved forest under 1,000 m, mixed with conifers to 1,800 m, dwarf bamboo above. A JpGU 2023 abstract (ACG30-P09) reports 10,048 and 9,139 mm a year at Yakusugi Land and the Yodogawa trailhead. That figure was read only in a search summary, since the abstract's page was down.
- **Soils**: red and yellow soils form today only in the subtropical Ryukyus; the warm-temperate belt has yellow-brown and brown forest soils ([Britannica, "Japan: Soils"](https://www.britannica.com/place/Japan/Soils); Matsui 1964, as cited in a search summary). Red clay further north is a relic of warmer interglacials.
- **Kira's warmth index** (Kira 1945, 1977): the sum of the months' means above 5 °C. Japan's evergreen broadleaf forest holds from 85 to 180, subtropical forest over 180, beech from 45 to 85, subalpine conifers from 15 to 45. From memory.
- **Holdridge's life zones** (Holdridge 1967): potential evapotranspiration is 58.93 mm a year for each degree of biotemperature, and its ratio to the rain is under 0.25 in rain forest, 0.25 to 0.5 in wet forest, 0.5 to 1 in moist forest and 1 to 2 in dry forest. From memory.
- **Orographic rain**: Smith (1979) and Smith and Barstad (2004), the upslope model with condensed water carried on and falling out downwind. From memory.

## The stations

At each station's own height. "Sea level" adds 0.65 °C for each 100 m (`LAPSE`). "Fit" is what `sea_mean` and `sea_swing` give at the station's latitude and its distance from land larger than about 250 km² (Kyushu, Honshu, Korea, Taiwan, Okinawa). Swing is half the gap from the coldest month's mean to the warmest's. The largest day is the mean of each year's largest day of rain, 1991–2020.

| Station | ° N | m | Year °C | Coldest | Warmest | Sea level (fit) | Swing (fit) | Warmth (fit) | Rain mm | Largest day |
|---|---|---|---|---|---|---|---|---|---|---|
| Minamitorishima | 24.3 | 7 | 25.8 | 21.8 | 28.5 | 25.8 (25.2) | 3.3 (4.9) | 249 (242) | 1,053 | 96 |
| Ishigaki | 24.3 | 6 | 24.5 | 18.9 | 29.6 | 24.6 (25.2) | 5.4 (5.3) | 234 (242) | 2,096 | 204 |
| Minamidaitō | 25.8 | 15 | 23.5 | 18.0 | 28.7 | 23.6 (24.0) | 5.3 (5.4) | 222 (226) | 1,639 | 161 |
| Naha | 26.2 | 28 | 23.3 | 17.3 | 29.1 | 23.5 (23.6) | 5.9 (5.5) | 220 (221) | 2,161 | 197 |
| Chichijima | 27.1 | 3 | 23.4 | 18.1 | 28.0 | 23.4 (22.9) | 4.9 (5.7) | 221 (215) | 1,296 | 123 |
| Okinoerabu | 27.4 | 27 | 22.6 | 16.5 | 28.6 | 22.8 (22.6) | 6.1 (5.9) | 211 (209) | 1,857 | 156 |
| Kikaijima | 28.3 | 5 | 22.1 | 15.6 | 28.6 | 22.1 (21.9) | 6.5 (6.3) | 205 (202) | 1,893 | |
| Naze (Amami) | 28.4 | 3 | 21.8 | 15.0 | 28.8 | 21.8 (21.8) | 6.9 (6.3) | 202 (202) | 2,936 | 223 |
| Nakanoshima (Tokara) | 29.8 | 220 | 18.9 | 11.1 | 26.7 | 20.4 (20.6) | 7.8 (7.3) | 167 (170) | 3,627 | |
| Yakushima, Onoaida (S) | 30.2 | 60 | 20.4 | 12.7 | 27.9 | 20.7 (20.3) | 7.6 (8.0) | 184 (179) | 3,399 | |
| Yakushima, Koseda (NE) | 30.4 | 37 | 19.6 | 11.8 | 27.5 | 19.9 (20.1) | 7.8 (8.1) | 176 (179) | 4,652 | 277 |
| Tanegashima, Kaminaka | 30.4 | 150 | 18.8 | 10.7 | 26.9 | 19.8 (20.1) | 8.1 (8.4) | 166 (170) | 3,138 | |
| Tanegashima, Nakatane | 30.6 | 234 | 18.0 | 9.5 | 26.5 | 19.5 (20.0) | 8.5 (8.4) | 156 (161) | 2,989 | |
| Tanegashima | 30.7 | 25 | 19.8 | 11.7 | 28.1 | 20.0 (19.9) | 8.2 (8.5) | 178 (176) | 2,532 | 207 |
| Fukue (Gotō) | 32.7 | 25 | 17.0 | 7.6 | 27.3 | 17.2 (18.2) | 9.9 (8.6) | 144 (157) | 2,339 | 172 |
| Hachijōjima | 33.1 | 151 | 18.0 | 10.1 | 26.5 | 19.0 (17.9) | 8.2 (7.8) | 156 (143) | 3,307 | 195 |
| Miyakejima | 34.1 | 38 | 18.0 | 9.9 | 26.6 | 18.2 (17.0) | 8.4 (8.8) | 156 (141) | 3,025 | 205 |
| Izuhara (Tsushima) | 34.2 | 5 | 16.0 | 6.0 | 26.8 | 16.0 (17.0) | 10.4 (9.4) | 132 (143) | 2,303 | 165 |
| Ōshima | 34.8 | 74 | 16.4 | 7.5 | 26.0 | 16.9 (16.5) | 9.2 (9.8) | 137 (132) | 2,859 | 210 |
| Saigō (Oki) | 36.2 | 27 | 14.5 | 4.5 | 26.1 | 14.7 (15.3) | 10.8 (9.9) | 115 (121) | 1,816 | 128 |
| Aikawa (Sado) | 38.0 | 6 | 14.1 | 4.0 | 26.0 | 14.2 (13.8) | 11.0 (10.6) | 112 (108) | 1,572 | 94 |
| Tobishima | 39.2 | 58 | 12.5 | 2.1 | 24.4 | 12.8 (12.8) | 11.1 (10.9) | 95 (96) | 1,429 | |
| Okushiri | 42.2 | 5 | 10.3 | −0.4 | 22.5 | 10.3 (10.2) | 11.4 (12.0) | 80 (82) | 920 | |
| Rishiri, Kutsugata | 45.2 | 14 | 7.4 | −4.0 | 19.9 | 7.5 (7.8) | 11.9 (12.9) | 60 (66) | 916 | |

Also used: Nagasaki (32.7° N, 27 m: 17.4 °C, 1,895 mm, largest day 133) under Unzendake (678 m: 13.0 °C, 2,927 mm, 208); Wakkanai (45.4° N, 1,109 mm, 74); Ōshima's Kitanoyama on its north coast (2,127 mm); Tsushima's Waniura at its north tip (1,435 mm).

## What was fitted

- **The year's mean at the sea's level**, from 24 island stations: 20.5 − 0.84 °C for each degree north of 30°. Root mean square error 0.55 °C, worst 1.2 °C (Hachijōjima and Miyakejima, which the Kuroshio warms, and Fukue and Izuhara, in the lee of Asia's winter). A second-order curve did no better. South of 22° it is held at 27 °C, as the tropical Pacific's islands are (from memory).
- **The swing**: 6.6 + 0.29 °C for each degree north of 30°, plus 2.2 °C × e^(−km to land larger than a region / 150). RMS error 0.64 °C against 0.79 without the land term. The worst fit is Minamitorishima, 1,800 km from any such land: 3.3 °C against 4.9.
- **Warmth from these**, by the months as a cosine through the year: within 15 of every station's own.
- **The lapse**: Unzendake is 0.68 °C a 100 m under Nagasaki, and Fuji's summit (−5.9 °C at 3,775 m) about 0.60 under the coast. The game uses 0.65, the US Standard Atmosphere's.
- **The rain on the sea, by latitude** (`RAINS`):

  | Latitude | Rain | From |
  |---|---|---|
  | 24 | 1,900 | Ishigaki, Naha, Minamidaitō |
  | 28 | 1,900 | Kikaijima, Okinoerabu |
  | 31 | 2,400 | Tanegashima |
  | 34 | 2,400 | the Izu islands and Tsushima |
  | 36 | 1,750 | Saigō |
  | 39 | 1,450 | Tobishima |
  | 42 | 950 | Okushiri |
  | 45 | 900 | Rishiri, Wakkanai |

  The rows come from low islands, or from high ones with their own lift taken out by the rain model below.

  Two kinds of station were left out: Chichijima and Minamitorishima, far out in the subtropical high (1,296 and 1,053 mm), and Naze, under Amami's mountains.
- **The year's largest day grows as the year's rain to the power 0.81** (19 stations, r = 0.90). The beds of stones narrow by it (`river_bed`).

## The rain model on real relief

The game's rain is the sea's, more by 1.0 for each km of height up to 1,000 m, and by 1.5 for each km the ground stands over the ground upwind. The ground upwind is weighted e^(−d/5 km). Rain never falls under 0.3 of the sea's.

The same sweep was run on GSI's model of each island at 132 m, with the wind from the bearing that best fits its stations. The sea's rain is taken from the stations, since this tests the shape, not the base:

| Island | Height | Wind | Sea's rain fitted | Stations: real (model) |
|---|---|---|---|---|
| Yakushima | 1,929 m | from 45° | 4,215 | Koseda 4,652 (4,616), Onoaida 3,399 (3,425); west lowland median 2,976 (2,400 to 3,600), east 4,844 (4,200 to 5,500), over 1,000 m 10,773 (6,000 to 10,000) |
| Tanegashima | 280 m | from 345° | 2,436 | coast 2,532 (2,587), Kaminaka 3,138 (2,946), Nakatane 2,989 (3,117) |
| Ōshima | 751 m | from 150° | 3,220 | Motomachi 2,859 (2,762), Kitanoyama 2,127 (2,202) |
| Tsushima | 647 m | from 165° | 1,841 | Izuhara 2,303 (1,834), Waniura 1,435 (1,802) |
| Miyakejima | 765 m | — | 2,767 | one station |
| Hachijōjima | 849 m | — | 2,812 | one station |
| Nakanoshima | 974 m | — | 3,010 | one station |

- A grid search over the height term (0.7 to 1.3 a km), the lee term (0.6 to 3 a km) and the distance (2 to 20 km) is flat from 1.5 to 3 a km over 2 to 5 km. The middle was taken.
- Tsushima's north tip is dry for some other reason than its relief.
- **Yakushima needs a sea's rain of 4,200 mm, where Tanegashima, 20 km off, needs 2,400.** Its coasts are wetter than this model makes any island from a common sea. Smoothing the height over 2 to 4 km does not close the gap (4,450 to 5,000). The cause is not traced. The candidates are a 1,900 m mountain's reach upwind, which a 5 km sweep cannot see, and the Kuroshio's main stream.
- **The model's mean over Yakushima's land is 7,200 mm.** The beds of stones fitted to Yakushima (step 34) are scaled from it.
