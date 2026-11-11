# The ground in blocks, and the underground

Design for the place rung: how the 16 m land becomes one-metre blocks, and what lies under them. Numbers are tagged *(measured)* from this repository, *(sourced)* from the research notes, or *(guess)*.

## 1. What it gives the player

At the foot of a scarp you see the face the map promised: bare rock banded by the beds you crossed on the way up, a ledge on each hard bed, blocks broken along cracks that run one way across the whole hillside, and an apron of loose rock and fallen blocks below. Soil slopes carry gullies that join downhill instead of random bumps. Within 256 m, soft beds recede under hard ones into shelters and sea notches, and caves open in faces, banks and sea cliffs where the rock allows. Dig anywhere and you find the rock the face shows, at the height it shows it. For the colony game this is the map of what can be quarried, where water seeps in, what stands unsupported and where ore lies, each with a cause the inspector can name.

## 2. Questions it answers

| Provides | To whom |
|---|---|
| **Ground at (x, z, cell)**: elevation after pieces, surface material | Engine columns, plants, water |
| **Block at (x, y, z)**, near or deep | Near volume, collision, digging, inspection |
| **Surface cover** (added field): bare rock, loose rock, soil, sand, gravel, peat, snow | Plants, inspection |
| **Cave** features with a kind (solution, lava tube, sea cave, shelter, talus cave, fissure); **ore body** (added feature) | Water, colony, inspection, naming |
| Sky openness of near faces under a roof | Renderer |

| Needs | From |
|---|---|
| **Rock** at (x, y, z): kind, strength, tilt, crack spacing and direction, permeable, soluble; plus a column form returning the runs of beds between two heights | Geology |
| Elevation, slope, drainage area, hollow-or-humped, the land's talus rule | Land forming |
| Cliff band, landslide (scar, slipped blocks), coast stretch with exposure | Landform processes |
| River reach (`river_cut` stays last on the bed), lake level, water table | Rivers, hydrology |
| Soil depth and kind (stand-in until then: slope against strength) | Soils |

## 3. Foundational decisions

**D1. One block function; the column derives from it.** *Recommendation:* `block_at(x, y, z)` is a pure function of seed and point: surface from `ground(x, z, 1)`, soil to the soil depth, then the rock function, then any declared volume feature. The level-0 column top is that same `ground` call, so the surface seen and the block dug agree in every chunk and load order. Player edits stay a list on top. *Alternatives:* a 3D density everywhere, as in Minecraft (far rings cannot see it, every column needs a vertical search); a stored underground (memory, a second truth). *Expensive later because* the mesher, collision, digging, saved edits and inspection all assume it.

**D2. A piece is a kind with one of five operations, in a fixed order.** *Recommendation:* a landform piece is a row (host test over fields, parameters) naming a shape procedure that does exactly one thing: *reshape* (bounded remap of height), *break* (offset by crack cell, bare rock only), *add* (higher of ground and a deposit surface), *cut* (lower of ground and a designed bed), or *volume* (add or remove blocks in a declared box, near only). Order follows the processes: structure, drainage detail, breakage, deposits, river and shore cuts, volume. A piece reads fields, rock and the height handed to it, never another piece's parameters. Overlap is settled by masks that partition: drainage detail weighs (1 − bareness), structure and breakage weigh bareness. *Alternatives:* free stacking (Terralith; pieces fight and get tuned in pairs); a priority list (edges show where one wins). *Expensive later because* every row is written against this contract, and reordering changes every cliff foot and bank.

**D3. No detail without a cause.** *Recommendation:* every amplitude below 16 m is a product of fields: bareness, drainage area, bed thickness, crack spacing, distance to river or sea. Today's isotropic `fbm` bump survives only under 0.5 m *(guess)* on soil. Every term fades with `band()`, so coarse is the average of fine (`adr/0001`). Elevation uses monotone interpolation (Steffen) instead of today's Catmull-Rom *(measured)*, which overshoots at faces and banks. *Alternative:* tuned noise per district, the recorded failure. *Expensive later because* looks accepted on noise change everywhere when it is removed.

**D4. Volume features are declared records with a 2D outline.** *Recommendation:* every overhang, shelter, notch, arch, cave and ore body is a feature: identity, kind, bounding box, a carve or fill procedure, and an outline for the far rings, namely the roof height (an arch's top is its column top) and a darkened rock material on the column's face where an opening is, so a shelter reads as a dark band from afar. Features are made at world creation, filed in 64 m buckets like river segments, stored per region. At the near ring's edge a passage is closed with an unlit face, so nobody looks out of a cave into the far rings. Faces under a roof need sky openness: a quad's `info` has four free bits (4 to 7) *(measured)*, filled at mesh time by spreading sky light from open columns within chunk and border. *Alternative:* a 3D noise term throughout the near volume (overhangs wherever noise says, popping in at 256 m). *Expensive later because* inspection, water, the colony and saves address features by identity; noise voids have none.

**D5. A material byte is its kind.** *Recommendation:* one byte indexing a table: colour, surface pattern (plain, bedded, speckled, clastic), and play properties (hardness, loose, permeable). Each rock kind is a material, and loose rock of each kind its own row. 256 rows covers the wide world (§4). The shader masks 4 bits (`& 15u`) *(measured)*; the quad already carries 8. *Alternative:* kind plus variant in two bytes, doubling volume memory for nothing visible yet. *Expensive later because* edits, saves and every rule branch on it.

**D6. Water under a roof belongs to its feature and stands still.** *Recommendation:* `adr/0004` stands. A cave records a water level from the water table at its lowest point; blocks inside it below that level are still water with a flat surface. Most caves are made above the water table, where real passages are dry *(sourced, Palmer, `real-geology.md`)*. A column dug open to the sky below the water table is supplied at that level: honest seepage in one rule. *Alternatives:* 3D water (a new system); dry caves only (sumps and flooded sea caves vanish). *Expensive later because* cave shapes and entrances get tuned to whatever water rule exists.

**D7. The underground is a function to any depth, designed to about −256 m.** *Recommendation:* no stored floor and no world bottom; `y` is 32-bit and the rock function answers anywhere. Beds, intrusions, caves, ores and water table are designed to −256 m *(guess; relief is 407 m, measured)*; below lies basement rock with nothing in it. Underground rows carry a depth range, so a later fantasy layer adds rows below without touching what is above. *Alternatives:* Dwarf Fortress's fixed stack with caverns at set levels (dishonest here); a hard floor (nobody needs it yet). *Expensive later because* every underground row and feature datum depends on it.

## 4. The kinds

| Axis owned | What a walker sees | Today | Archipelago | Wide world |
|---|---|---|---|---|
| Landform piece | shape of a face, bank, shore or slope at 1 to 50 m | 2 | 14 | 30 |
| Fine texture | gullied, stepped, blocky, smooth deposit | 1 | 4 | 5 |
| Ground material | colour and pattern of a block | 9, one rock | 22 | 45 |
| Underground void | kind of cave or shelter | 0 | 5 | 8 |
| Underground deposit | ore or useful bed | 0 | 4 | 15 |

Dwarf Fortress has 25 stones, 21 soils and 58 minerals, but in a fixed stack with ores by rock class, so fortresses differ by list more than by sight; TerraFirmaCraft has 125 landforms at region scale. This design aims lower in count and higher in cause: a piece takes its dimensions from the rock, so a ledged face on 8 m sandstone beds and on 30 m basalt flows are different walks from one row. **Two kinds differ** only if someone 20 m away tells them apart within ten seconds by silhouette or material, and their hosts differ. A new parameter value, colour or seed does not count; v4 aimed at 200 terrain types counted that way and accepted none *(sourced, `reference/odincraft-v4/landscape-crafting.md`)*. A row counts once the owner accepts it in the game.

"Bare" below means slope above the rock's standing angle.

| Kind | Op | Host | What the player sees |
|---|---|---|---|
| Ledged face | reshape | bare; beds of unequal strength | Risers on hard beds, 1 to 5 m ledges *(sourced)*, beds converging along strike |
| Stepped valley side | reshape | near-level beds cut by a valley | Benches 10 to 30 m apart *(sourced)*, grass on treads, rock on risers |
| Jointed face | break | bare; cracks 1 to 5 m apart | Prisms set back 0 to 2 m, one grain across the hill |
| Columnar face | break | bare; columnar basalt or welded tuff | Clustered 1 m columns *(real ones ~0.5 m, sourced)*, a chaotic band above |
| Talus apron | add | below a face over 3 m *(guess)* | Loose rock of the face's own kind at 33 to 35° *(sourced)* |
| Fallen blocks | volume | below a face; size from bed thickness | Blocks 1 to 5 m *(sourced)*, some stacked, gaps between |
| Tor | volume | humped summit; massive rock, cracks over 3 m | Stacked blocks 5 to 15 m high *(sourced)* over loose blocks |
| Boulder field | add | massive rock, soil stripped, gentle | Single 1 to 3 m blocks in grass |
| Gullied slope | reshape | soil; moderate slope; below channel size | Rills joining downhill, sharp spurs |
| Rock gully | cut | bare; small drainage | A slot down the face along one crack set |
| Dike wall / trench | reshape | thin intrusion stronger / weaker than host | A straight wall 1 to 3 m wide and up to 30 m high, or a slot *(sourced)* |
| Cut bank and bar | cut | river reach (exists) | Steep outside bank, gravel inside |
| Bedrock channel | cut | river over hard rock | Bare-rock bed stepping at each hard bed |
| Gravel / sand beach | add | sheltered coast; river gravel, or soft rock behind | Steep shingle berm, or a wide shallow slope and dunes |
| Platform and notch | cut + volume | exposed coast | Flat rock at sea level, a 1 to 3 m notch at the foot *(sourced)* |
| Rock shelter | volume | soft or seeping bed under a hard one at a face foot | A dry recess 2 to 20 m deep *(sourced)* |
| Sea cave / arch | volume | crack or soft bed at an exposed headland | A slot cave along one crack; light through a narrow headland |
| Solution cave | volume | soluble bed; stream sinking onto it; lower outcrop | Tubes on bedding, canyons on cracks, a spring where it leaves |
| Lava tube | volume | young flow below a vent | A tunnel 3 to 5 m high *(sourced)* under the surface, skylights |
| Talus cave / fissure | volume | big fallen blocks; slipped landslide block | Crawls among blocks; a 1 to 3 m crack behind the block |
| Mineral vein | volume | hard rock near an intrusion, along a crack set | A 0.3 to 2 m *(guess)* quartz sheet with ore in a face |
| Coal seam | rock bed | sedimentary stack | A black band among the beds |
| Placer gravel | add | river gravel downstream of a vein host | Heavy gravel at the base of a bar |
| Bog iron / flint | add / volume | peat over wet ground; chalk beds | Rusty lumps under peat; dark nodules strung along a bed |

## 5. How it works

**Region rung, once at world creation.** Three passes over the land, rivers and landform features:
- *Bareness* per 16 m cell: slope against the rock's standing angle, soil below about 30°, loose rock at 33 to 35° *(sourced, DiBiase 2012, Francou & Manté)*. One rock call per cell over 262,144 cells *(measured)*: milliseconds *(guess)*.
- *Caves by host.* Solution caves by Paris et al. 2021: Poisson samples dense on bedding contacts and the water table, 32 neighbours, A* from sinks (streams crossing onto soluble rock) to springs (the bed's lowest outcrop on a valley wall), cost weighing distance to bedding, alignment with cracks and permeability; the graph builds in under a second *(sourced, `procedural-techniques.md` §3)*. Because sinks and springs lie in banks and valley walls, entrances open in faces, not pits; a doline is allowed only over a passage with a thin roof. Lava tubes: a polyline down a flow at 3 to 8 m depth *(guess)*, skylights where the roof thins. Sea caves: a capsule chain inland along the crack direction. Output: capsules (segment, radius, kind) in 64 m buckets.
- *Ore bodies* by row, placed only where the host passes: a slab along a crack set (vein), a bed (seam, from geology), a scatter in a bed (nodules), a layer under alluvium (placer).

**Place rung, per column, `ground(x, z, cell)`**, in D2's order:
1. Elevation by monotone interpolation of the 16 m land (Steffen 1990, as Veloren does). Same 16 taps as today.
2. *Structure*: find the bed at that height from the rock's column form; push height toward the top of a hard bed and the base of the soft bed above, weighted by slope over standing angle times strength contrast (`procedural-techniques.md` §5.1). Ledges appear only where the simulation already made the ground steep, and bed thickness is never periodic. That is the difference from v4's banding and Veloren's altitude modulo 200. About 10 operations plus the lookup *(sourced estimate)*. Kept at all cell sizes, so 10 to 30 m risers read from afar.
3. *Drainage detail*: the gradient-aligned erosion filter (runevision, March 2026, MPL-2.0), two or three octaves along the simulated gradient, faded by log drainage area, weighted by (1 − bareness). About 9 lookups per octave *(guess)*. Gone by 8 m cells.
4. *Breakage*: on bare rock, a two-family Worley pattern aligned with the crack directions and spaced by crack spacing; each cell's face set back 0 to 2 m by hash. About 9 hashes. Gone by 4 m cells.
5. *Deposits*: the apron is the land's own repose slope in loose material; boulder and beach rows take the higher surface.
6. *Cuts*: `river_cut` unchanged, then the shore.

About 1 to 2 µs a column *(guess)*, about 2 ms per 34 × 34 chunk on one worker; checked with `--bench` against no frame over 12.5 ms.

**Per block, `gen_volume`.** Each column fills downward: soil to its depth, then rock runs from the column form, one walk per column rather than a rock call per block. Then each feature in the chunk's buckets carves or fills inside its box. Shelters and notches use Paris 2019's undercut depth, `U·(1 − strength)·stress`, confined to a band at a soft bed at a face foot or at sea level, declared along the face base rather than applied everywhere. About 100,000 blocks a chunk at a few nanoseconds each *(guess)*.

**Meshing and light.** Far columns take a riser's material from the rock at its mid-height, not a fixed Stone *(measured, `mesh_columns`)*, and split tall risers at bed boundaries so far scarps show bands (a few percent more far quads, *guess*). Near faces under a roof use the sky-openness bits (D4).

**Digging.** By D1 a dug block is `block_at` there: the face's bed at the face's height, ore where the feature list says, soil exactly as deep as the column showed. `build_volume` already widens the volume to reach edits *(measured)*, so digging deeper calls the same function deeper. A pit open to the sky below the water table is supplied (D6).

## 6. Growth path

**Stage 0, on today's island.** Uses geology's rock function, or the 20-line `rock_hard` from `interesting-world.md` §6 as a stand-in. Two separate changes:
- *0a, ledged faces and rock in blocks.* Monotone elevation in `land_at`; structure and bareness in `ground` and `surface_at`; rock kinds in `block_below`; a 256-row palette and 8-bit mask in `shaders.metal`; far risers coloured by rock in `mesh.odin`. About 100 lines *(guess)*. The owner compares `--shot` before and after, same camera, at the foot of the tallest face and from 1 km across its valley.
- *0b, broken faces and aprons.* Crack cells, loose-rock materials, fallen blocks as volume solids. About 60 lines in `gen.odin` *(guess)*. The owner walks up an apron to a face.

**Stage 1, archipelago.** Features filed per region. Shelters and sea notches with sky openness; the erosion filter on soil; sea caves and arches; solution caves on a limestone island and lava tubes on a young volcanic one; still water in caves; seepage into pits; four deposit rows; about 22 materials.

**Stage 2, wide world.** Features and ore bodies stream with their region, never held for the whole world; materials and pieces grow by rock province to about 45 and 30; fantasy rows below −256 m if chosen.

**Not yet.** Ores, until an inventory or colony uses them. Solution caves, until the owner decides on limestone. Anything below −256 m, until the fantasy deep is designed. Arches, until a formed coast has a jointed headland. Place graphs, sediment ledgers and scene transactions: v4 built them and they did not make places look right.

## 7. Risks and known failures

- **Stamped diagrams** (`lessons.md`). A piece never picks its own place or size: the host test places it, rock and drainage size it, and its weight fades to zero at the host's edge.
- **Artificial banding** (v4, Veloren). Bands come from the rock function the simulation eroded, at irregular thicknesses, raised only where the simulation made ground steep.
- **Generic noise in the 16 m gap.** D3: every amplitude is a product of fields.
- **Overhangs popping in at 256 m** (`adr/0001`). Volume exists only in declared features with a far outline.
- **Caves lit as open sky.** The engine has no sky light under roofs today; D4's four bits.
- **Seeing out of a passage into the far rings.** Unlit closing face at the ring edge.
- **Water under roofs** (`adr/0004`). D6.
- **Accretion of kinds** (v4: 200 targeted, none accepted). A row counts only when accepted on sight; at most two new rows per change.
- **Frame pacing.** Fades bound per-column work; `--bench` after each stage.
- **A plan heavier than its change.** Stage 0 is about 160 lines in four existing files, no new module.

## 8. Decisions for the owner

1. **True bed thickness or exaggerated ledges?** *Recommendation:* true first; judge at a face.
2. **Flat colour with four patterns, or drawn textures?** *Recommendation:* flat colour plus patterns; revisit after stage 0.
3. **Do caves hold still water?** *Recommendation:* yes, owned by the cave, from stage 1.
4. **Do pits dug below the water table fill?** *Recommendation:* yes, from stage 1.
5. **What lies below −256 m?** *Recommendation:* plain basement until the fantasy world is designed; no world floor.
6. **Is there limestone?** The only honest route to long caves. *Recommendation:* follow geology's island stack; this design works either way.

## 9. Not verified

- All per-column, per-block and per-chunk costs are guesses; nothing was run. The erosion filter's cost is the note's estimate, not its author's.
- Whether Paris 2021's graph stays under a second with several soluble beds.
- Whether filling sky openness at mesh time fits the build budget and looks right at mouths, and whether split far risers fit the frame budget.
- Read from code, not run: the 4-bit material mask, the four free `info` bits, Catmull-Rom in `land_at`, `build_volume` widening for edits.
- The −256 m depth, the 0.5 m bump limit and every host threshold are guesses to be set by looking.
