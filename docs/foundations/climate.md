# Climate, seasons and weather

Numbers are marked *(measured)*, *(sourced)* or *(guess)*. "From memory" means a standard figure not re-read for this design; section 9 lists them.

## 1. What it gives the player

On foot: the shaded side of a valley keeps its snow a week longer than the sunny side; the windward shoulder is bent scrub and the lee is tall forest; morning fog lies in the valley floor and burns off by ten; cloud shadows cross the hills ahead of a front; a walk over a range ends in drier, clearer country. The year shows in low winter sun, a snow line climbing in spring, autumn colour and high rivers in the thaw. From a high point the air tells you where you are: blue-grey maritime haze, the clarity of a dry interior, cloud capping a windward range. In the colony game climate is the economy: growing season, frost, winter stores, floods.

## 2. Questions it answers

| Provides | Read by |
|---|---|
| **temperature** (°C, annual mean), **seasonal swing**\*, **growing-season temperature**\* | plants, water (ice), soil, colony |
| **rain** (mm/yr) and **rain seasonality**\* (amplitude, month of peak) | water, plants, soil |
| **wind**\* (direction and strength, summer and winter) | exposure, weather, plants (lean), coast |
| **exposure** (wind and salt), **sunlight** (yearly insolation relative to flat ground) | plants, soil, snow |
| **cold pool**\* (metres of cold air ponding above the valley floor) | frost, fog, plants |
| **fog frequency**\*, **snow days**\* | plants, water (melt), renderer |
| **date**\* (one world clock) | everything seasonal |
| **weather front**\* (feature: a moving band of cloud and rain with a track, speed and life) | renderer, water, colony |
| **past climate**\* per region (past snow line, past sea level) | land forming |

\* added to the shared vocabulary.

Needs: elevation, slope, facing, hollow-or-humped, distance to sea, land and sea (land); the drainage tree and lake extent (rivers, water); latitude and ocean basins (world frame).

## 3. Foundational decisions

**D1. Climate is a handful of yearly numbers in real units.**
*Recommend:* each world cell stores annual mean temperature, seasonal swing, daily range, annual rain, rain seasonality, and summer and winter wind. Each seasonal value is a cosine through the year. Units are °C, mm and m/s.
*Alternatives:* 0–1 indices, as Minecraft and most noise generators use; or 12 monthly normals, as v4 did.
*Why expensive later:* every kind in every system writes its host in these units. Real units let thresholds come from ecology (trees stop near a growing-season mean of 6.4 °C, Körner & Paulsen 2004, from memory; Köppen tundra is a warmest month under 10 °C, [Beck et al. 2018](https://doi.org/10.1038/sdata.2018.214)) rather than from tuning an abstract scale.

**D2. Latitude is one declared function of z, and the sun reads it.**
*Recommend:* the island declares about 40° N (Shirakami is 40.5° N, `notes/vegetation.md`). Sun path, day length and base temperature all read the same latitude, so sky and plants never disagree. For the wide world, one constant sets degrees per 1,000 km (question 2).
*Alternatives:* today's fixed sun (60° at noon every day, `render.odin:229`); or no latitude, as the zigcraft research advised for an infinite world, which this is not.
*Why expensive later:* wind belts, ocean warmth and the sun all key off it; changing it re-zones every region.

**D3. Rain is moisture carried along the prevailing wind.**
*Recommend:* one sweep along the wind per season: air takes up moisture over sea (more over warm sea), drops it where ground rises into the wind, and loses it slowly inland. A cheap stand-in for Smith & Barstad's linear orographic model ([2004](https://doi.org/10.1175/1520-0469(2004)061%3C1377:ALTOOP%3E2.0.CO;2)), which the zigcraft research also recommends.
*Alternatives:* rain from noise (no rain shadows; the recorded Neo failure); a full Smith–Barstad solve (better lee physics, more code).
*Why expensive later:* rain sets river size, forest and desert. Once regions are formed with it, changing the method changes every river.

**D4. Base climate on the world grid; local climate derived from the land.**
*Recommend:* the world grid (about 4 km cells, *guess*) holds D1's numbers. Lapse with height, sun-facing, exposure, cold pools and fog are computed per region at 16 m from the land's own fields and stored beside wetness. The place rung interpolates them like elevation (`adr/0001`).
*Alternatives:* 16 m everywhere (does not fit 1,000 km in memory); coarse only (loses the sun slope and frost hollow a walker sees).
*Why expensive later:* it fixes what a region receives as boundary conditions and what it computes itself, the same split as land forming.

**D5. One world clock; season is continuous and local.**
*Recommend:* time is days since the start, plus the hour. Season is never a global switch: the date gives each place its own temperature, so spring reaches the coast weeks before the summit. `YEAR_DAYS` is independent of day length.
*Alternatives:* a global season enum; no year.
*Why expensive later:* plants, water, saves and the colony calendar key off it.

**D6. Weather is a pure function of place and time.**
*Recommend:* fronts are features drawn from the seed (track along the wind, start, speed, width, intensity). Cloud, rain, fog and wind at any (x, z, t) come from the fronts in reach plus local terms from the climate fields. Same seed, date and hour, same sky.
*Alternative:* a coarse atmosphere stepped in time: richer, but it must be saved and it diverges.
*Why expensive later:* saves and colony harvests assume one or the other, and the owner's screenshots need repeatable skies now.

**D7. Season and weather are drawn by the renderer, never baked into chunks.**
*Recommend:* snow, leaf tint, wet ground, cloud shadow and fog are shader terms from per-frame uniforms and, from the archipelago on, a small camera-centred climate texture. The generator's columns stay season-free.
*Alternative:* bake snow and leaf state into materials; a season change then re-streams 10 km of terrain.
*Why expensive later:* it decides the vertex format and what streaming redoes, and gives every level of detail one snow line.

## 4. The kinds

| Axis this system owns | States | Seen on foot as |
|---|---|---|
| Thermal belt | 7: tropical, subtropical, warm temperate, cool temperate, boreal, subalpine, alpine or polar | tree form, evergreen or deciduous, length of snow season |
| Moisture regime | 5: arid to perhumid | ground bare or covered, moss, haze, river size |
| Seasonality | 4: oceanic, continental, monsoon, Mediterranean | how the land changes through the year |
| Local climate | 7: sun slope, shade slope, cold pool, exposed shoulder, salt coast, cloud cap, sheltered | aspect contrasts, bent trees, fog lines, frost |
| Weather | 9: clear, broken cloud, overcast, rain, showers, fog, snow, storm, wind or dust | sky, light, shadows, wetness |
| Season state | 6: bud, summer, colour, bare, snow, thaw | leaves, snow, river stage, ice |

**Zones are names over continuous fields**, chosen as RimWorld's biome workers do: score each zone from temperature, rain and seasonality and name the winner (`notes/df-rimworld.md`). Two zones count as different only if a walker sees a difference in at least two of: plant form, ground cover, snow or ice, the air. Otherwise they merge.

| Targets *(guess)* | Island | Archipelago | Wide world | DF / RimWorld |
|---|---|---|---|---|
| Base zones | 1 | 3–6 | 14–17 | 27 land biomes / 17 biomes |
| Local climates | 5 | 7 | 7 | none / none |
| Weather states | 5 | 7 | 9 | a few / about 10 (from memory) |
| Season states | 4 | 6 | 6 | seasonal growths / 4 quadrums |

DF's 27 fold in drainage and landform; these are the climate axis alone. On foot a player can likely tell 8–10 base climates apart and meets 2–3 in a session; from a high point, cloud deck, haze and snow line separate zones tens of kilometres off *(guess)*.

**Example rows.** T annual mean °C, S seasonal swing, R rain mm/yr, Rs seasonality (+ summer peak, − winter peak), Gs growing-season temperature, X exposure, F fog frequency, Cp cold pool, A sunlight, dS distance to the upwind sea.

| Name | Host | What the player sees |
|---|---|---|
| Oceanic cool temperate (the island) | T 8–12, S < 8, R > 1,200, dS < 50 km | Beech, moss, mild grey winters, blue-grey haze |
| Snowy maritime | T 6–11, winter wind off sea, Rs − | Two metres of snow, trunks bent at the foot, dwarf bamboo |
| Warm-temperate rainforest | T 14–19, R > 2,000, frost rare | Glossy evergreen broadleaf, ferns, steady drizzle |
| Continental temperate | S > 13, dS > 300 km | Hot summers, hard winters, the brightest autumn |
| Mediterranean | T 13–18, Rs strongly − | Gold summer grass, dark evergreen oak and scrub, clear air |
| Steppe | lee of a range, R 250–500 | Grass to the horizon, trees only along rivers, dust |
| Hot desert | T > 18, R < 200 | Dunes, bare rock, dry riverbeds, yellow haze |
| Coastal fog desert | hot desert by a cold sea | Daily fog, lichen and fog-fed shrubs on coastal hills |
| Savanna | T > 20, Rs strongly +, R 600–1,200 | Grass and flat-topped trees, green then brown, fire scars |
| Tropical rainforest | T > 24, R > 2,000 | Tall layered evergreen forest, afternoon storms |
| Cloud forest | windward slope in the cloud belt, F > 0.5 | Stunted mossy trees dripping in mist |
| Boreal | T −5 to 3, Gs > 6.4 | Dark spruce spires, long snow, frozen lakes |
| Alpine or tundra | Gs < 6.4 | No trees, cushion plants, frost-sorted stones |
| Sun slope *(local)* | A > 1.2 | Drier, earlier melt, oak and grass beside beech |
| Shade slope *(local)* | A < 0.8 | Moss and ferns, the last spring snow |
| Cold pool *(local)* | Cp > 20 m | Dawn frost and fog, open grass under a wooded rim |
| Exposed shoulder *(local)* | X > 0.6 | Scrub leaning downwind, scoured snow, forest in the lee |
| Salt coast *(local)* | dS < 1 km, windward | Turf and thrift, salt-burnt crowns behind |
| Cloud cap *(local)* | windward summit above the cloud base | Cloud on the top most mornings, wet moss heath |

## 5. How it works

**World rung** (about 250 × 250 cells for 1,000 km; under a second, *guess*):
1. Base temperature from latitude by a table of real zonal means (about 26 °C at the equator, 20 at 30°, 11 at 45°, 1 at 60°, from memory), at sea level.
2. Wind belts: trades below 30°, westerlies to 60°, polar easterlies beyond, shifting poleward in summer (the three-cell picture, from memory).
3. Ocean warmth as a rule over coast direction and latitude: subtropical coasts under the trade-wind outflow are cold (fog deserts), high-latitude coasts downwind of the westerlies are warm.
4. The moisture sweep (D3) for summer and winter wind gives annual rain and seasonality.
5. Seasonal swing grows with latitude and distance from the upwind sea.

**Region rung** (16 m from the land's fields; on today's 512² grid about 20–50 ms on top of one second, *guess*):
- *Temperature:* base − 6.5 K per km ([US Standard Atmosphere 1976](https://ntrs.nasa.gov/citations/19770009539), a physical anchor). A 3 km range spans 20 K, about 30° of latitude, so on foot altitude is the main thermal axis and latitude is what travel changes.
- *Sunlight:* clear-sky yearly insolation from facing, steepness and latitude; the vegetation note's "dryness = slope × cos(aspect − sun azimuth)" is its simple form (`notes/vegetation.md`, after Far Cry 5). Horizon shading deferred.
- *Exposure:* the largest upwind rise within about 300 m (Winstral's maximum-upwind-slope index, from memory), plus humped ground, plus salt decaying over about 1 km from the windward sea *(guess)*. One sweep, about 20 samples a cell.
- *Cold pool:* height above the channel a cell drains to (HAND, Rennó et al. 2008, from memory), following the drainage tree `land.odin` already builds (`next`). Cold air fills the lowest 30–100 m on clear calm nights *(guess)*.
- *Fog frequency:* cold pool plus nearby water (valley fog); cold sea and season (sea fog); windward ground above a cloud base of about 125 m per °C of dewpoint depression (Espy's rule, from memory).
- *Rain:* the world value plus a windward term. **On a 6 km island 400 m high this is weak** *(guess)*: the island's contrasts come from sun, exposure and cold pools.
- *Snow days:* from when the temperature at that height crosses 0 °C, winter rain, and degree-day melt of about 3–8 mm of water per °C per day (Hock 2003, from memory), shorter on sun slopes.

**Place rung:** nothing is simulated; snow lies deeper in lee hollows and trees lean downwind, read from these fields.

**Day and year.** Declination 23.44° × sin(2π(d − 80)/365), scaled to `YEAR_DAYS` (Cooper 1969), with latitude and hour angle. At 40° N the noon sun stands about 27° in midwinter and 73° at midsummer; days run about 9.3 to 15 hours (computed). Temperature is mean + swing × cosine, peaking four to six weeks after the solstice, later on coasts (from memory). Leaves come out as the daily mean passes about 8 °C and colour and fall below 10 and 5 °C *(guess)*. Climate gives the water system a monthly supply factor (rain minus evaporation, plus a melt pulse) for river stage; lakes and slow rivers freeze past a threshold of freezing degree-days.

**Weather** (D6). Each region draws fronts from the seed: one every 3–7 days in the westerlies, fewer under subtropical highs, crossing at 30–50 km/h *(guess)*. One front covers the whole island; across an archipelago they arrive visibly from upwind. Local terms: cloud caps moist windward summits; summer afternoons build showers over high ground; clear calm nights fill cold pools with fog to their depth until mid-morning.

Drawing, under 0.5 ms a frame in all *(guess, to bench)*: overcast and wetness are uniforms that soften shadows, grey the sky and darken wet ground. One cloud layer at the cloud base in the sky shader, two or three noise octaves drifting with the wind, and **cloud shadows on the terrain from the same noise**, one lookup a pixel. That pair is the cheapest moving atmosphere, and it shows the wind across a whole view. Fog is the existing `apply_fog` haze with a density and a top height from the weather. Rain and snow are a few thousand instanced streaks round the camera. No volumetric clouds.

No Man's Sky's later variety came partly from "clouds and weather" and "wind patterns" (`notes/interest-design.md`); RimWorld stacks fog on 30% of wetland maps (`notes/df-rimworld.md`).

**Light and colour.** What the renderer needs from climate: haze density and tint (humid maritime blue-grey, dry interior clear, desert dust yellow), cloud cover, snow line, and a season phase per zone for leaf and grass tints. The fixed `0.00006` in `apply_fog` becomes a visibility in kilometres from humidity. The colours themselves are the owner's.

**Deep time.** Each region gets a past snow line (today's lowered by a glacial cooling of about 5–7 K through the lapse rate) and a past sea level (about −120 m at the last glacial maximum), both from memory. Ground above the past snow line licenses cirques, U-shaped valleys and moraine lakes; a past low sea licenses drowned valleys, which `land.odin` already makes with `DROWN`. Today's island at 40° N and 407 m stays unglaciated.

## 6. Growth path

**Stage 0: today's island**, four steps, each judged in under a minute:
1. *Sun from latitude and date.* `sun_dir` in `render.odin` reads a latitude and day; `main.odin` gets `--day=`. About 20 lines. Look: one view at `--day=172` and `--day=355`, same hour.
2. *Snow line from date in the shader*, lowered on shade-facing slopes from the slope normal the terrain shader already has (`in.soft`). About 25 lines in `shaders.metal` and `render.odin`. Look: the island from the air in January and March. Caveat: with a base of 9 °C and a 7 K swing, midwinter at sea level is 2 °C and the snow line about 300 m up at 0 °C, so only the top 100 m whitens *(computed)*; a Shirakami-like winter needs a colder base (question 1).
3. *Local climate fields:* sunlight, exposure with salt, cold pool, temperature, in `land.odin` beside `wet`, shown on `--map`. About 90 lines. Look: do windward shoulders and frost hollows fall where expected? The plant system's first communities then read them.
4. *Cloud layer and cloud shadows* from one deterministic front sequence, with `--weather=` to force a state. About 80 lines, mostly shader. Look: a hillside under drifting shadows; then the frame-pacing bench.

About 215 lines *(guess)*, with no change to the vertex format, streaming or generator output.

**Stage 1: archipelago.** A world grid over the archipelago gives each island base climate and wind. The sweep wets or dries a high island's lee. Fronts cross islands in sequence. A camera-centred climate texture (about 512² at 64 m, *guess*) carries zone and snow to the shader for far islands. Target 3–6 zones.

**Stage 2: wide world.** Latitude scale, wind belts, ocean warmth, continentality, two-season sweeps, past climate. Zones become a table the plant system reads.

**Not yet**, with triggers: a monthly water balance (the colony needs drought); weather that changes the land, such as floods or fire (chosen as an event); seasons advancing during a walk (a year length is chosen); horizon shading (deep shade slopes look wrong); volumetric clouds and lightning (the owner asks); a second yearly harmonic (a Mediterranean or monsoon zone exists).

## 7. Risks and known failures

- **Zones as noise paint** (Neo's "taxonomy of hand-shaped noise fields"): every field derives from latitude, wind, sea and land; noise only dithers edges.
- **Thresholds before measurement:** thresholds come from ecology in real units, and stage 0 shows each field on the map before anything reads it.
- **Measurements passing while the eye rejects:** each stage ends in a screenshot pair; pure-function weather makes them repeatable.
- **A coarse-to-fine gap filled with noise; clean Minecraft-like belts:** the local tier is computed at 16 m from the land, and altitude, aspect and rain shadow cut across the belts.
- **Season changes re-streaming terrain, or near and far snow lines disagreeing:** D7, one shader function for every level of detail.
- **Frame pacing:** weather is shader terms plus a few thousand particles; bench after each stage.
- **Weather hiding the land** (`ideas.md` pillar 6): `--weather=clear` for judging land; see question 4.

## 8. Decisions for the owner

1. **The island's climate and latitude.** *Recommend: cool-temperate oceanic (already recommended, question 7) at 40° N.*
2. **How the world gets from cold to hot.** (a) A true slice of about 9° (1,000 km ÷ 111 km): as varied as Kyushu to Hokkaido or Galicia to Almería, through altitude, rain shadow and ocean side, but no tropics or lowland tundra. (b) Compressed: 1,000 km stands for 25–40°, desert to boreal in one world, with latitude changing implausibly fast on a long journey. (c) A band of a larger globe, variety from mountains only. *Recommend (b) at 30°, from 30° N to 60° N.* Needed by stage 2; stage 0 needs only the island's latitude.
3. **Does the year run during a walk?** A fixed date per session; a slow year (say 48 days of 24 minutes, a season every five hours of play, *guess*); or colony-game ratios (RimWorld 60 days, Dwarf Fortress 336, from memory). *Recommend: a fixed date per session, set with `--day` or a key, until the colony game.*
4. **How much weather may hide the land.** *Recommend: clear or broken cloud about two days in three on the island (guess), fog only in cold pools and on caps, rain as an event.*
5. **Seasonal colour now or later.** It needs per-species leaf tints. *Recommend: after the first plant communities exist.*
6. **Ice-age history in cold regions of the wide world.** *Recommend: yes, as boundary conditions that license glacial landforms; no ice on the island.*

## 9. Not verified

- Stated from memory, not re-read: treeline at a growing-season mean of about 6.4 °C (Körner & Paulsen 2004), zonal mean temperatures, the wind belts and their shift, Winstral's exposure index, HAND (Rennó et al. 2008), Espy's cloud-base rule, degree-day melt factors (Hock 2003), glacial cooling and the −120 m sea level, the solstice lag, RimWorld and Dwarf Fortress year lengths and weather counts.
- That a 400 m island shows little rain shadow is an inference.
- All costs (world sweep, region fields, the frame budget for clouds and rain) are guesses until benched; so are the phenology temperatures, fog depths, front frequency and speed, salt reach and the stage 0 line counts.
- How many climates players tell apart on foot: no source; 8–10 is an inference.
