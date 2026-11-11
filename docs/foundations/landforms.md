# Landform processes: design

The forming simulation at the region rung: its processes, their order, the history they run over, and the events that mark the land. Geology supplies `rock(x, z, y)`: erodibility, slope limit, strength, solubility, permeability and bed index at any point.

Numbers are marked **(measured)**, **(sourced)** or **(guess)**. Citations marked *(memory)* were not opened in this session.

## 1. What it gives the player

On foot, the country changes when its cause changes: a young gorge with falls at its tributary mouths, an old valley with a flat floor and deep soil, a drowned coast of inlets, a landslide's bare scar above a clutch of ponds. Each is a different history run through the same few processes. Inspection names cause and age ("debris of a slide about 3,000 years ago"). In the colony game the same records decide where flat land, deep soil, flood risk and dammed water are.

## 2. Questions it answers

| Provides (per 16 m cell unless noted) | Read by |
|---|---|
| elevation at 16, 32, 64 m (exists) | engine, everything |
| **water surface**: the level water stands at, separate from the ground | water, lakes, plants |
| drainage direction and drainage area (exist) | rivers, water, plants |
| slope, facing, hollow-or-humped | place rung, plants |
| **at limit**: slope as a fraction of the rock's slope limit | place rung (faces), plants, caves |
| **deposit** kind and thickness: soil, alluvium, fan gravel, talus, lake mud, beach sand, dune sand, slide debris, till, lava, ash | place rung, soil, plants, digging |
| **disturbance age** from landform events | plants, inspection |
| **exposure** to waves (coast cells, per stretch) | coast pieces, plants |
| Features: lake (bed, level, outlet pass), landslide, flood, lava flow, cone, cirque, moraine, sink, knickpoint, coast stretch, cliff band | rivers, water, place rung, plants, names |

| Needs | From |
|---|---|
| `rock(x, z, y)`, and the right to add an event's body (a lava sheet, a debris mass) to it | geology |
| a history: phases with uplift pattern, sea level, rain, snowline, wind; the events allowed | world frame |
| the region's seam: sea, or fixed inflow points and divides | world frame |
| rain per phase (uniform until it exists) | climate |

Added to the vocabulary: fields **water surface**, **at limit**, **deposit**; terms **history**, **phase**, **response time**; features knickpoint, flood, lava flow, cone, cirque, moraine, sink.

## 3. Foundational decisions

**D1. Ground and water surface are two fields; hollows are kept and only sediment fills them.**
Recommend: `route` keeps the filled surface as the water surface; `erode` stops raising the ground to it. A hollow fills only with sediment, so a lake lives as long as its catchment takes to fill it. Alternatives: fill every hollow (today; v4 revision 15 lost most lakes this way, *sourced*), or carve every hollow open. Expensive later because lakes, dams, deltas, wetlands, water supply and plant zones all read the gap between the two.

**D2. One loop, a fixed handful of process terms; every rate comes from the rock function and the current phase.**
Recommend: uplift, stream cutting, slope limit, creep, deposition, coast retreat; ice and dissolution only when a phase asks. No landscape type has its own algorithm. Alternatives: a generator per landscape family (v4's analytic catalogue, rejected on sight), or stamped shapes. Expensive later because every kind in section 4 is defined as "this history through this loop".

**D3. A region's history is data: a short list of phases and events, and the land is left unfinished.**
Recommend: a phase is one row: years, uplift pattern and rate, sea-level change, rain factor, snowline, wind direction. The last phase runs for a fraction of the **response time**, the time a knickpoint takes to climb from the sea to the heads of the main valleys (Whipple & Tucker 1999 *(memory)*), computed on the grid as the sum of `span / (K·√A)` along each flow path. Under about 0.5 of it, knickpoints and hanging tributaries are mid-climb; past about 2 the land is worn near balance *(guess)*. Alternatives: today's fixed `SCHEDULE`; running to balance, which erases events. Expensive later because kinds and the archipelago's variety are keyed on history rows.

**D4. An event is a feature with an identity, chosen by host score, applied inside the simulation, and written to a per-cell event map.**
Recommend: after its phase, score candidate cells over the host conditions, take the best few by rank (not a threshold), change ground, rock and deposit, then settle briefly (hundreds to thousands of years, *guess*) so the land adjusts without erasing it. Record `{kind, id, origin, extent, age, magnitude}` and stamp the id into a 16-bit map. Alternatives: events stamped on finished land. Expensive later because plants, water, inspection and the colony key on event id and age.

**D5. Every cell knows what its surface is made of, and the place rung expresses it by that, never by generic noise.**
Recommend: one deposit kind and thickness per cell, over the rock. The kind picks the metre-scale shape: talus is a planar 34° fan, alluvium is flat with bars, slide debris is hummocks sized by the slide's blocks, till is ridges along the recorded ice front, bare rock is beds and joints from the rock function. Alternative: material by slope bands (today; ReTerraForged). Expensive later because soil, plants and digging are built on these kinds.

**D6. The hand-off contract to the place rung is a fixed set of 16 m fields with monotone interpolation.**
Recommend: elevation, water surface, drainage direction and area, at limit, deposit kind and thickness, event id, wave exposure; interpolated with a monotone cubic (Steffen 1990, as Veloren does, *sourced, procedural-techniques*) instead of today's Catmull-Rom, which overshoots at cliff edges and banks. Expensive later because every place piece is written against these names.

**D7. A region is formed as a pure function of seed and boundary conditions, on its own grid.**
Recommend: the seam is the sea, or for inland regions fixed inflow points and divide heights from the world rung. Same inputs, same land, in any order, on any core. Alternatives: one global grid (does not fit memory at 16 m); blended overlapping tiles (they disagree at divides by hundreds of metres, *sourced, lessons*). Expensive later because the archipelago and wide world rest on it, and it decides whether a region can be formed on demand.

## 4. The kinds

**Axes this system owns**

| Axis | States: today / archipelago / wide world | What a walker sees |
|---|---|---|
| History (relief style) | 1 / 6 to 8 / 10 to 12 | valley cross-section, how much is bare, knickpoints, terraces |
| Event | 3 / 6 / 9 | one-off places: scars, hummocks, ponds, dammed lakes, flows, cones |
| Deposit | 6 / 10 / 13 | what you walk on and dig into; flat against hummocky against ridged |
| Coast | 3 / 6 / 8 | cliff, platform, beach, inlet, delta, fjord |

Rock (geology's axis) multiplies these: one young history gives scarps over tilted beds and tors over granite.

**Against the benchmarks.** TerraFirmaCraft's 125 landforms are noise shapes chosen by rule; Dwarf Fortress erodes cliffs away. Target: about 30 landscape kinds on the archipelago, 80 to 100 in the wide world *(guess)*, each a history and rock pairing that passes this test:

Two kinds differ when (a) their hosts differ in a field or a phase, not only in a magnitude, and (b) the owner can tell them apart in a grey screenshot from within 200 m by one of: valley cross-section, what the slopes are made of, standing water, or the kind of edge.

**Examples.** P is a process outcome at the region rung, E an event, D a designed piece at the place rung that this system hosts.

| Kind | Host | What the walker sees |
|---|---|---|
| Young gorge country (P) | fast uplift; last phase under 0.5 response times | V valleys at the slope limit, inner gorges below knickpoints, falls where tributaries hang |
| Old worn hills (P) | long last phase with no uplift, over 2 response times | broad floors, deep soil, almost no bare rock, slow winding streams |
| Scarp and vale (P) | hard bed dipping under 20° over soft | long dip slope, a scarp with a scree apron, a river along its foot |
| Ridge and vale (P) | hard beds dipping steeply | parallel ridges, streams in the soft strips, gaps where one cuts through |
| Plateau and canyon (P) | level hard cap, a late uplift pulse, dry | flat tableland, canyons cutting back from the sea, mesas and buttes at the edge |
| Drowned coast (P) | sea rises 30 m or more in the last phase | branching inlets, hill islands, mud at the inlet heads |
| Raised coast (P) | sea falls in steps | flights of flat terraces behind old cliff lines, gorges at every mouth |
| Exposed cliffed coast (P) | high wave exposure, strong rock | sheer face, rock platform at the tide line; stacks and caves (D) |
| Sheltered sand coast (P) | low exposure, sediment from rivers or cliffs | wide beach, a dune belt (D), a spit (D) |
| Floodplain valley (P) | deposition where the slope eases | flat floor, abandoned channels, a low terrace edge |
| Rock-basin lake (P) | a hollow kept in hard rock | lake with a bare rock rim, outlet over a lip |
| Slide complex with ponds (E) | strong cap over weak bed, undercut, at limit, dip toward the valley | bare scar, hummocks, ponds between blocks (Jūniko) |
| Slide-dammed lake (E) | slide debris crossing a valley floor | lake upstream with drowned trunks, outlet seeping or cutting the debris |
| Breach gorge and boulder bar (E) | a dam with a large lake behind it | notch through the debris, a fan of boulders downstream, an old shoreline above the lake |
| Glacial trough (P) | glacial phase | U-shaped valley, hanging side valleys with falls, a chain of lakes |
| Cinder cones (E) | young basaltic vent | cones with craters, black ash slopes |
| Lava flow (E) | vent upslope of a valley | rough lobe with a steep front, side valleys dammed into lakes; tubes (D) |
| Old volcanic island (P) | volcanic history, long erosion | radial ridges, amphitheatre-headed valleys, plugs standing as stacks |
| Doline karst (P) | soluble rock and rain | pocked ground, dry valleys, streams sinking, springs at valley feet |
| Dune field (D) | sand deposit, exposure, little vegetation | crests across the wind, slip faces, hollows |

**The earlier catalogue.** `landscape-crafting.md` names ten reviewed candidates and about a hundred studies by family; the full list of about 200 is not in `reference/`. By class:

- **From processes (about a third, guess):** mesa country, butte field, cuesta, hogback ridges, canyons, stepped valleys, floodplains, fans, deltas, rias, fjords, troughs, cirques, moraine lakes, terraces, landslide complexes, dammed lakes, karst plains and dry valleys, volcanic shields and cone fields. Never built as shapes: if the history and rock exist, they appear.
- **Designed pieces at the place rung (about a third, guess):** rock fins, arches, stacks, hoodoos, tors, yardangs, the four dune forms (one dune piece with forms chosen by wind regime and sand supply), spits, tombolos, waterfall amphitheatres, slots, plunge pools, columnar faces, dike walls, rock shelters, sea caves, lava tubes, sinkholes, drumlins, eskers.
- **Drop:** names that differ from a neighbour only by a parameter or a palette; anything needing a process not modelled (live glaciers, ice sheets, salt domes, impact craters, geysers); and continental forms no walker perceives.

## 5. How it works

**Order inside one step:** route; uplift; cutting with `K` from the rock at current height; deposition; slope limit; creep; coast retreat; then ice and dissolution if the phase asks. Events run between phases.

| Process | Method | Kind | Cost against today's 1.0 s (measured) |
|---|---|---|---|
| Cutting with rock | implicit stream power, `K` from the rock (Cordonnier 2018, *sourced*) | continuous | +0.5 s measured; about +0.1 s if each column caches its bed offset (*guess*) |
| Slope limit | today's clamp, 30° weak to 50° hard (*sourced*) | continuous | none |
| Kept lakes | erode to the lake level, never fill (Cordonnier 2019, *sourced*) | rule | none |
| Deposition | sediment summed down the order, excess over capacity `A^m·s` dropped (after Yuan 2019, Schott, *sourced*); all of it drops in lakes | continuous | +0.15 s (*guess*) |
| Soil | production `P0·exp(-h/h0)` (Heimsath 1997 *(memory)*); creep moves soil only; bare where removal outruns it | last phase | +0.03 s (*guess*) |
| Coast | wave exposure from fetch in 16 directions at 64 m; shore cells retreat by exposure over strength to a platform 2 m down; sand drifts toward low exposure | shore cells | +0.03 s (*guess*) |
| Landslide | Culmann failure at limit over a weak bed (HyLands, Campforts 2020, *sourced*); debris runs out as hummocks | event | <10 ms (*guess*) |
| Dam breach | seeded draw biased to failure (half of 73 dams failed within ten days, Costa & Schuster, *sourced*); notch and boulder bar | event | trivial |
| Volcanic | cone 0.18 and crater 0.40 of base (Porter 1972, *sourced*); flows poured down the drainage to a thickness; both add a rock body, then erode for their age | event | trivial |
| Glaciation | ice flux from accumulation above the snowline carried down the drainage; erosion by ice flux spread across the ice width (U shapes, after Harbor 1992 *(memory)*), allowed below the receiver so basins overdeepen; till at the front. Cordonnier 2023 is too heavy (*sourced*) | phase, 64 and 32 m only | +0.3 s for a glacial history (*guess*) |
| Karst | on soluble rock a share of the water sinks: less cutting (dry valleys), dissolution lowers ground with no receiver bound (closed hollows); sinks become features | phase | +0.05 s (*guess*) |
| Dunes | a dune-sand deposit where beach sand meets exposure and dryness; shaped at the place rung | designed | none |

**Choosing events.** Each event kind is a row: a host score (for a slide: at limit, weak bed near, undercut by river or sea, dip toward the valley), a count per region (one to three on this island, *interesting-world.md*), a spacing and a phase. Top scores win; ties break by seed hash. An early event is worn by what follows: an old slide is a soft amphitheatre with infilled ponds, a fresh one a bare scar.

**The fine end.** The place rung reads the D6 fields and asks the rock function for beds and joints. At limit above about 0.9 on hard rock *(guess)*: a face from beds and joints, a talus fan below sized by its height. Soil below the limit: gullies from a gradient-aligned erosion filter steered by the stored flow direction and faded by drainage area (Johansen 2026, *sourced*). Debris: hummocks sized by the event's blocks. Alluvium: flat to the river design.

**Speed.** Today's forming is about 13.8 million cell-steps in 1.0 s *(measured time; cell-steps counted from `SCHEDULE`)*, so roughly 70 ns per cell-step, most of it in `route`'s priority flood *(guess, not profiled)*.

- Coarse (64, 32 m): most years, glaciation, early events, wave exposure. At 16 m: the last phase, soil, deposits, settling, at limit.
- Parallel: creep, slope, soil and coast passes by rows on 12 cores; routing and cutting by drainage basin, which is exact (Braun & Willett 2013, *sourced*); regions one per core.
- Totals *(guess)*: this island with every process 1.3 to 1.6 s serial, near 1 s in parallel; 20 such islands about 3 s on 12 cores; a 50 km region (70 times the area) several seconds, most phases at 32 m.
- Each process prints its own time.

## 6. Growth path

**Stage 0: today's island, three changes, one at a time, all in `land.odin`.**

- **0a. History as rows** (about 40 lines). Replace `SCHEDULE` and `DROWN` with a phase list, print the response time, and end with a short phase in which the sea falls 20 m, then rises 8 m as today *(guess)*. The owner looks at the map and from the air: gorges climbing from each mouth, a raised shore step, inlets. Nothing else changes.
- **0b. Kept hollows and deposition** (about 60 lines, plus about 10 in `gen.odin` to report lake level as water). Lakes where the land holds a hollow, flat lower valley floors, fans at valley mouths. Needs the water design to take a lake level as supply. Few hollows survive before rock and slides exist; that is expected.
- **0c. One landslide** (about 80 lines), once the rock function exists: scar, hummocks with ponds, a dammed lake if it crosses a valley. The owner walks it: the Jūniko piece.

**Stage 1: the archipelago.** Each island a region on its own grid (D7) with its own history: young and old, drowned and raised, one or two volcanic, one with limestone. Add coast retreat and the other events.

**Stage 2: the wide world.** Inland regions seamed by inflow points and divide heights; long phases at 32 or 64 m; glacial and karst phases as ordinary rows.

**Not yet**, with triggers: glaciation (the owner allows a glacial history); karst (an island has limestone); volcanic events (the archipelago); dunes, arches, stacks, tubes (their place pieces are built); parallel routing (a region takes over 2 s); inland seams (a landmass bigger than one region).

## 7. Risks and known failures

- **Running to balance erases events and knickpoints.** The last phase is sized by the response time, and events get a short settling.
- **Stamped shapes read as diagrams.** Events are applied inside the simulation and eroded for their age.
- **Sediment fills every basin**, as in v4 revision 15. Infill is a rate that slides and rock outpace; count lakes after 0b and 0c.
- **The gap between 16 m and 1 m filled with noise.** D5 and D6: each metre-scale shape is chosen by deposit kind and at limit.
- **Thresholds set before measuring.** Events go by rank; the face cut and response-time fractions are starting guesses, set by looking.
- **Accretion.** Each process is one term of 20 to 80 lines; a term the owner cannot see is removed.
- **Measurements passing while the eye rejects.** Every stage ends on the map and in the game; counts can reject, never accept.
- **Tiny four-connected lakes**, a recorded mistake: routing stays eight-connected and a lake needs a minimum depth and area.

## 8. Decisions for the owner

1. **The island's history.** *Recommendation:* young and rising, after Shirakami, drowned at the end, with one large slide.
2. **How many one-off events per island.** *Recommendation:* one to three large ones (slide, dammed lake, breach), plus uncounted small rockfalls.
3. **Do slide dams fail?** *Recommendation:* yes, most do, as in the record; one survives on the first island so the owner sees both.
4. **Glacial history anywhere.** *Recommendation:* not on the first island; allow it on high-latitude islands of the archipelago.
5. **Volcanic islands in the archipelago.** *Recommendation:* yes, one young and one old, since they share all code with the slide and the coast.
6. **Should inspection show history and ages?** *Recommendation:* yes; the records exist anyway.

## 9. Not verified

- Every cost marked *guess*; the claim that `route` dominates today's forming time has not been profiled.
- The response-time rule and its fractions (0.5, 2) have not been tried on this island.
- Whipple & Tucker 1999, Heimsath 1997, Harbor 1992 and Barnes 2016 are cited from memory; Yuan 2019 and Braun & Willett 2013 from abstracts and secondary documentation (per `procedural-techniques.md`).
- The ice-flux proxy, the lava pour and the coast retreat rule are proposals with no published game or paper behind them in this form.
- The full v4 list of about 200 landform names is not in `reference/`; the thirds in section 4 are estimates from its families and first ten.
- Whether 16 m cells resolve cirques, small cones and coastal platforms well enough to read from the ground.
