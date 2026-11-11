# Water

Two measurements on today's island (a scratch copy with prints after the final `route` in `land_form`) set the starting point:

- **The land forming leaves no hollows.** After the sea rises, three hollows are 0.3 m deep or more. Each is one 16 m cell and under 1 m deep. *(measured)* `erode` clamps every cell above the cell it drains to, so each pit fills as it forms. Keeping the fill level, as `interesting-world.md` proposes, would add no lakes; a lake needs an event acting on the land after it forms.
- **There is almost no flat wet ground.** The largest catchment is 6.7 km², 32 streams reach the sea, and flat wet ground (slope under 3%, wetness over 0.5) is 0.06% of the land. Low flat ground at the coast is 0.22%. *(measured)* With no deposition term, floodplains, fans, deltas and beaches have no source.

## 1. What it gives the player

On foot: water you hear before you see, and can follow. A stream begins at a spring line under a crag, steps down pools, drops into a gorge and runs out across a gravel floodplain. Lakes have a cause you can walk to: the slide that dammed them, the hard lip of rock that holds them, the meander they were cut off from. Each kind of lake has its own colour and edge of reed and alder; ground turns dark where water seeps from rock; coasts are cliffs where the swell hits and beaches where it doesn't. For the colony game, water becomes the first map a player reads: where to drink and dig a well, what floods in spring, where a wheel can turn, what can carry a boat, and which dam will hold.

## 2. Questions it answers

| Provides | To whom |
|---|---|
| **Fields:** water surface (the level of standing or flowing water at a point, or none); discharge; distance to river, lake and sea; water table; wetness; salinity; flood height above the river | engine, plants, soil, the coast, caves, colony |
| **Features:** river reach (with discharge, style and fall profile), lake (level, depth, outlet, cause, age), wetland, spring, sink, waterfall, coast stretch (exposure, mouth kind) | inspection, named places, plants, colony |
| **Near the player:** a depth in every column, its flow, and where it is supplied | player, plants at the edge, colony |

| Needs | From |
|---|---|
| Elevation, slope, drainage area and the single-receiver graph | land forming (region rung) |
| Rock: whether water passes through it, whether it dissolves, strength, the contacts between beds | rock system |
| Rain, temperature and prevailing wind; later the month | climate |
| Landslide and other events that edit the land after it forms | rock and land system (the slide is shared) |
| Soil kind, including peat | soil system |
| How regions are cut and in what order they form | world frame |

Added to the shared vocabulary. Fields: **discharge** (m³/s, the yearly mean), **water surface**, **salinity** (0 fresh to 1 sea), **sediment supply** (how much loose material a reach carries), **flood height** (height above the nearest river's level), and **snowpack** (reserved). Feature: **sink** (where a stream goes underground).

## 3. Foundational decisions

**D1. Every body of water is a feature with an id and a level; the water surface is derived from them.**
- *Recommendation:* rivers, lakes, the sea, standing wetlands and falls are rows in one table: id, cause, level (flat for a lake, falling along a reach), the body downstream, the outlet. `ground()` asks it for the water surface, as it already asks the rivers.
- *Alternatives:* a 16 m raster of water level (Neo v3, v4); water at a wetness threshold.
- *Why expensive later:* inspection, named places, dams, water rights and region seams all need to know which body a column belongs to. A raster cannot say (recorded failure: "lakes stored as coarse ownership cells").

**D2. A lake is made by an event acting on finished land; the routing keeps it as one node with one outlet.**
- *Recommendation:* after forming, events edit elevation: a landslide, lava or moraine dam, a fault sag, a sinkhole, a meander cutoff, a spit across a bay. A final `route` finds each hollow, sets its level to its lowest spill (not per-cell `fill`, whose 0.001-per-metre trace would tilt a 1 km lake by 1 m), and drains it as one node. An event may mark a lake **seeping**: no surface outlet, drained through the dam, as Aoike at Jūniko.
- *Alternatives:* relax the erosion clamp (causeless pits that erosion erases again); Fill–Spill–Merge with a water balance (only needed when lakes rise and fall).
- *Why expensive later:* the cause is the lake's kind; colour, shore and plants hang on it, and every catchment downstream counts through the node.

**D3. Rivers are sized by discharge, and each reach carries a style.**
- *Recommendation:* discharge = runoff × area + springs − sinks. Runoff is uniform today, so widths do not change. Width ∝ Q^0.5 (hydraulic geometry, Leopold & Maddock, cited in `zigcraft/future-phases-research.md`). Style, from slope, discharge, bank strength and sediment supply: cascade, step-pool, pool-riffle, gorge, meandering, wandering, braided, anabranching, distributary. Meander against braid follows Leopold & Wolman: S ≈ 0.06 Q^-0.44 in ft³/s ([USGS PP 282-B](https://pubs.usgs.gov/publication/pp282B), as quoted by [Métivier et al.](https://esurf.copernicus.org/preprints/esurf-2016-47/esurf-2016-47.pdf)), about 0.0125 Q^-0.44 in m³/s *(my conversion)*.
- *Alternatives:* keep `river_half(area)` with special cases.
- *Why expensive later:* climate, springs, sinks, seasons, wheels and boats all speak in discharge; changing the unit later retunes every width and threshold.

**D4. A river changes representation at about two cells (32 m) wide.**
- *Recommendation:* narrower, it is a **line**: traced, cut by design (`adr/0003` unchanged), a ribbon far away. Wider, it is a **belt**: a corridor of region cells whose ground is bed and whose surface is the reach's level, drawn far away as water columns. Design draws the planform inside the belt by style: meanders, bars, islands, braids, oxbows, levees. Delta distributaries are designed inside the delta feature; the simulation keeps one trunk and one receiver per cell.
- *Alternatives:* widen lines without limit (ribbons float over multi-cell floors); metre-scale channels (rejected in `adr/0003`).
- *Why expensive later:* it decides what the region simulation and the far drawing must know.

**D5. Regions are cut along drainage divides; a river crossing a boundary is handed downstream as a record.**
- *Recommendation:* in the archipelago the sea is the only seam. On a landmass the world rung routes at about 1 km and cuts along divides. A trunk crosses only at a node, carrying point, discharge, level and sediment supply; upstream regions form first. Region order belongs to the world-frame designer; this is water's constraint on it.
- *Alternatives:* square tiles with halos, which truncate catchments and change spill decisions (`zigcraft/future-phases-research.md`).
- *Why expensive later:* independent patches disagree at divides by hundreds of metres (`lessons.md`). Where regions are cut is the hardest thing to reverse.

**D6. The water table is a derived field, not a groundwater simulation.**
- *Recommendation:* depth to water table = flood height × a permeability factor from rock and soil, clamped. A **spring** is a feature where the rock system's contact (a bed that passes water on one that does not) crosses a valley side below the table. A **sink** is where a reach crosses onto rock that passes or dissolves water with the table below its bed; the reach loses discharge or ends. Sinks and springs are the end points of the cave system's karst graph (Paris 2021, `notes/procedural-techniques.md`).
- *Alternatives:* a steady groundwater solve at 16 m; nothing.
- *Why expensive later:* wells, flooded caves (below the table is flooded unless an event drains it), wetlands and stream heads all read it.

**D7. Near the player, water stays a depth per column, but rivers are supplied at the rim of what is loaded instead of held everywhere.**
- *Recommendation:* today every river column is topped up to the design level, so a dam can never raise water. Hold river water only at the upstream rim and at springs, with inflow capped at the reach's discharge; inside, it flows freely to the downstream rim and the sea. Keep the state of edited chunks with the edits once saves exist. Water under a roof (up to three spans of floor, ceiling and depth per column) waits until caves reach the water table.
- *Alternatives:* water blocks; full conservation; a 3D fluid.
- *Why expensive later:* the colony's dams, irrigation and floods are built on the supply rule.

## 4. The kinds

**Axes this system owns, with distinguishable states:**

| Axis | States | What a walker sees |
|---|---|---|
| River size by discharge | 5: spring brook, stream, creek, river, large river | Width, sound, whether you can step or wade across |
| River style | 9 (D3) | Steps, pools, bars, braids, loops, a slot gorge |
| Lake cause | 12 | The dam, rim or shore that holds it, and its shape |
| Lake age | 3: open, fringed, infilling | Clear edge; reed belt; a quaking fen closing in |
| Water colour | 4: groundwater blue, peat brown, green, glacial milk | Surface colour and clarity |
| Wetland | 9 | Plants, standing water, the ground underfoot |
| Fall form | 7 | Plunge, horsetail, cascade, tiers, curtain, hanging valley, onto the shore |
| Coast exposure × mouth | 4 exposures × 6 mouths (ria, estuary, delta, lagoon, fan, beach-blocked) | Cliffs or beach; how a river meets the sea |
| Season and state | 4 later: low, high, flood, frozen | Exposed bars, brown flood, ice |

**Target counts of distinct kinds:**

| Stage | Water kinds | Benchmark |
|---|---|---|
| Today's island | 1 river (with pools), the sea | |
| Stage 0 | about 8: three styles, dammed lake, debris ponds, seeping lake, a lake edge, the sea | |
| Archipelago | about 35 | RimWorld: 4 river sizes, 8 inland-water landmarks, plus delta, confluence, headwater and river-island variants (`notes/df-rimworld.md`) |
| Wide world | about 70 | Dwarf Fortress: 21 water biomes and 9 wetlands, all on temperature × salinity (`notes/df-rimworld.md`). Minecraft: about 15 water and shore biomes *(from memory)* |

**Two kinds differ** when a walker tells them apart within 30 seconds by shape, edge, colour or sound, *and* their hosts differ. Most of Dwarf Fortress's water kinds vary only by temperature and salinity and fail the first test.

**Example rows.** Every threshold is a guess to be set by looking, unless a source is given.

| Kind | Host conditions | What the player sees |
|---|---|---|
| Spring brook | A spring, or a channel head where drainage area × slope² passes a threshold (Montgomery & Dietrich 1988, *from memory*) | A wet trickle with moss, no banks, rising from a seep line |
| Step-pool and pool-riffle | Slope above or below 0.045 (today's rule) | Pools with metre drops; bars and cut banks (built today) |
| Bedrock gorge | Style gorge: a reach on strong rock below a fall | Walls several channel widths high, no floor beside the water |
| Meandering river | Below the Leopold–Wolman slope, strong banks, belt > 2 cells | Loops, a point bar inside each bend, oxbows on the floodplain |
| Braided river | Above the slope threshold, weak banks, high sediment supply | Many shallow threads over a wide grey gravel bed |
| Landslide-dammed lake | A landslide feature crossing a valley with drainage area > 0.5 km² | A long lake with drowned trees, a hummocky dam, an outlet gorge or a seep |
| Debris pond cluster | Hollows inside landslide debris | 5 to 30 ponds among hummocks in beech forest (Jūniko) |
| Seeping blue pool | Lake marked seeping, fed by groundwater | No inflow stream, vivid clear blue (Aoike) |
| Hard-rock basin lake | A strong-rock sill across a valley that past ice overdeepened (needs a glacial history) | A rocky shore with bare slabs at the outlet |
| Oxbow lake | A cutoff in a meandering belt | A crescent of still water, reed-choked, beside the river |
| Coastal lagoon | A bay with a spit across it, and longshore drift | Brackish water behind a sand barrier |
| Doline pond | Soluble rock, a sinkhole with a sealed floor | A round pond in a funnel |
| Bog pool | A raised or blanket bog | Black pools between sphagnum hummocks |
| Marsh | Flood height < 0.5 m, mineral soil, slope < 2% | Reeds two blocks tall, mud, open water channels |
| Fen | Water table at the surface, fed by springs, peat | Sedge lawn and low birch, firm then quaking |
| Raised or blanket bog | High rain, cool, flat or gentle, impermeable ground | Brown-red moss dome or upland sheet with pools |
| Salt marsh | Between the tides, sheltered, temperate | Creeks winding through low grey-green turf |
| Plunge fall | A strong bed over a weak bed in a reach's path, drainage area 0.1 to 1 km² ([Crosby & Whipple 2006](https://core.ac.uk/download/4403051.pdf)) | A free-falling jet, a deep round pool, an amphitheatre |
| Ria | A drowned valley mouth (today's `DROWN`) | A long branching inlet, wooded to the water |
| Delta | High sediment supply, sheltered sea | Spreading channels, reed islands |

## 5. How it works

**World rung (1 km).** Priority-flood and route about a million cells, under a second *(guess)*: divides, region order, inflow records. Runoff from rain and evaporation; salinity and tidal range per sea; glacial lake kinds only where a past snowline lay below the land.

**Region rung (16 m).**
1. *Form the land* as today, plus a deposition term for floodplains, fans and beaches: Yuan et al. 2019, implicit, 1 to 20 extra iterations (`notes/procedural-techniques.md`). Perhaps 2 to 4 s instead of 0.9 s *(guess)*; needed only for islands over about 10 km.
2. *Events* (D2) edit elevation; the landslide is shared with the rock system.
3. *Final route.* Lakes become nodes with levels and outlets (Cordonnier et al. 2019; Veloren's exact fill). Discharge accumulates with springs and sinks. Reaches get styles; belts are rasterised.
4. *Derived fields:* flood height (HAND, Nobre et al.), water table, salinity, distances, and coast exposure as fetch in 16 directions weighted by wind. Each is a 1 MB array, together under 50 ms *(guess)*.
5. *Wetlands* classify over these fields; one becomes a feature only where it holds standing water.
6. *Falls* are features wherever the designed bed drops more than 1.5 m: lip line, height, discharge, receiving pool.

**Place rung (1 m, within 256 m).**
- *Rivers:* `river_cut` for lines; a planform designer per style for belts.
- *Lakes:* a column is lake where its 1 m ground is below the level inside the 16 m footprint grown by one cell. At the footprint's edge, ground below the level is raised to a crest 0.3 m above it, the river-bank rule, so there are no water walls. Shores shelve with the land, so plant bands come free (`notes/vegetation.md`).
- *Falls:* a lip of whole blocks, a face from the rock's beds, a plunge pool about half the fall's height deep *(guess; Lamb & Dietrich 2009 tie pool depth to retreat)*. The water above and below are separate bodies joined by a link in the simulation. The fall is its own mesh: a sheet on a ballistic path from the lip, white or in strands by discharge per metre of lip, mist at the foot. Never columns from bed to surface. `water_surface`'s side sheets stay for drops under 1.5 m.
- *Springs* are supplied columns; a *seep line* is a wet band in a face, with moss below.
- *The sea* stays a held level; tides would make it one time-varying level, ranged per coast stretch.

**Far away.** One ribbon per region for lines; lakes and belts as flat surfaces at their levels, under today's mask rule.

**What it gives the colony game.** All read from the same features: *drinking* from any fresh body, or a well wherever it reaches the water table; spring water clean, bog water brown. *Irrigation* draws from a reach's discharge upstream of the field (needs D7). *Power* is ρgQH: 0.5 m³/s over a 3 m fall is about 15 kW before losses *(arithmetic)*, so falls and step-pool reaches are mill sites. *Transport* where a reach is deeper than about 1 m, wider than about 10 m and free of falls *(guesses)*. *Flood risk* is flood height against the reach's seasonal high flow.

## 6. Growth path

**Stage 0: the first lakes, on today's island** (about 150 lines; `land.odin`, `rivers.odin`, `gen.odin`, a little of `render.odin`).
- `land.odin`: one landslide, about 60 lines, sited by relief alone for now: a valley draining 0.5 to 5 km² below more than 80 m of relief within 300 m *(guesses)*. Lower the scar, raise a hummocky lobe across the valley, re-route, keep each hollow as a lake at its lowest spill (about 30 lines).
- `rivers.odin`: reaches end at the shore and restart at the outlet (about 20 lines). `gen.odin`: the lake rule of section 5. `water.odin` needs no change: it already holds a column at whatever level the generator reports. Far lakes as flat quads (about 30 lines).
- *The owner looks at:* the map (lake, scar, ponds), then a screenshot from the dam up the lake. When rock lands, the slide moves to its real host, a strong bed over a weak one.

**Stage 0b**, each a separate change, in this order: discharge and style per reach (no visible change today, about 20 lines); the water table and springs once rock has beds (about 60 lines); falls with their own mesh once rivers cross hard beds (about 120 lines); lake-edge bands with the plant system.

**Stage 1: the archipelago.** Each island a region with its own climate and runoff; water ids carry the island id. Add deposition (islands over about 10 km, where belts appear), wetland classification, coast exposure and mouth kinds, and the D7 supply change.

**Stage 2: the wide world.** World-rung drainage, regions on divides, inflow records, belts hundreds of metres wide, deltas and estuaries, tides, glacial lakes where history allows, seasonal discharge.

**Not yet, and what starts each:**
- *Tides:* start when a stage-1 coast has salt marsh or tidal flats to show.
- *Seasons, snowpack, ice, floods:* when climate has months. Reserved now: discharge is a yearly mean a monthly factor multiplies; a water column can carry an ice flag (ice is walkable, depth unchanged).
- *Water under a roof:* start when the first cave reaches below the water table.
- *Persisting water state:* start when saves exist.
- *Meander migration, lake infilling over time, Fill–Spill–Merge:* start only if the owner rejects designed planforms on sight.
- *Simulated water beyond 256 m:* not planned.

## 7. Risks and known failures

| Failure | Where it comes from | How this design avoids it |
|---|---|---|
| Rivers as ribbons on the land, or canals dug into it | `lessons.md`, every attempt | Lines stay traced from the drainage. Belts are part of the land forming. Lakes come from events that the routing then sees. |
| Lakes as coarse cells make water walls | `lessons.md` | The level is exact, the footprint is grown by one cell, and a crest is built at its edge. |
| Waterfalls drawn as walls of water | `lessons.md` | Falls are features with their own mesh and a link in the simulation. |
| Generic pits read as diagrams | The research | Every lake has a cause that can be inspected. No noise makes hollows. |
| River disagreements at region seams | `lessons.md`, Neo v3 | Seams follow divides; inflow is a record (D5). |
| Thresholds fixed before measuring | `lessons.md` | Every number here is marked a guess, and the owner sets it by looking. |
| Landslide dams fail early: about half within 10 days in 73 cases | Costa & Schuster, `notes/real-geology.md` | Only wide or seeping dams are kept, and that is what makes the seeping-pool kind. |
| The water step's 2 ms on the frame thread grows | `adr/0004` | Move the step to a worker before spans or larger windows are added. |

## 8. Decisions for the owner

1. **Lakes before rock?** Stage 0 places the slide by relief alone so it can be seen on today's island, and moves it onto rock later. *Recommendation: yes.* Jūniko is the owner's own reference, and the 0-hollow measurement shows lakes will not appear any other way.
2. **The belt threshold at about 32 m.** *Recommendation: accept it as a starting value*, and look again at the first river that reaches it.
3. **Tides.** *Recommendation: none until the archipelago has a sheltered coast to show them.* Then a small range: tides change a coast a lot for little cost.
4. **Should player dams raise water (D7)?** *Recommendation: yes, at stage 1.* The colony game depends on it, and the change is small.
5. **Lake colour by cause** (blue groundwater pools, brown bog water). *Recommendation: yes.* It is cheap variety tied to an inspectable cause.
6. **Glacial and volcanic lakes** need an ice-age or volcanic history, which the cool-temperate oceanic recommendation rules out for one island. *Recommendation: leave them to islands in the archipelago that have that history.*

## 9. Not verified

- The Leopold–Wolman coefficient: the 0.06 (ft³/s) form comes from a secondary source, and the m³/s value is my conversion. Montgomery & Dietrich's channel-head rule and Leopold & Maddock's exponent are from memory.
- Every threshold in sections 4 to 6 (slide site, belt width, fall height, plunge-pool depth, wetland bands, blanket-bog rain) is a guess.
- The cost of deposition and of the world-rung routing is estimated, not measured.
- Whether a free-flowing river inside the loaded window (D7) settles at the designed level without spilling its banks. It needs a probe across a river once built.
- The Minecraft count is from memory.
- The measurements cover seed 7 only.
- The hollow count was taken after the sea rises and before any event. The rock experiment's island may have more hollows, which was not checked.
