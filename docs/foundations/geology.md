# Geology: the rock of the world

Designer's draft for the foundations plan, 2026-11-11. Numbers are marked *(measured)*, *(sourced)* with the note that carries the source, or *(guess)*.

## 1. What it gives the player

On foot, rock makes one valley differ from the next: a grey grit cap standing bare over a soft mudstone slope, a ledge where the stream drops, red gravel because red sandstone crops out upstream, a granite summit of stacked blocks, a dark dolerite wall crossing a hillside. Aim at a block and the game says which bed it is, how thick, which way it tilts, and that the gravel below came from it. Digging passes soil, broken rock, then beds that match the bands in the nearest cliff. For the colony game the same function decides building stone, flux, where water seeps into a cellar, and which ores can exist in this ground and why.

## 2. Questions it answers

| Provides | To | Form |
|---|---|---|
| `rock(x, y, z, cell)`: kind, body, strength, erodibility factor, threshold slope, bed tilt, crack spacing and direction (up to 3 sets), whether water passes through, whether it dissolves | land forming (per cell per step), surface, blocks, cliffs and caves, soil, water | field |
| Surface rock: the rock at the ground | soil, plants, map, inspection | field (derived once from the above on the 16 m grid) |
| Sediment source mix: what fraction of the load at each point came from which rock kind | river design (gravel colour and size), coast (beach sand), resources (placers) | field on the 16 m grid, accumulated down the drainage |
| Rock bodies: beds, faults, intrusions, lava flows, each with an identity, a name, an extent | inspection, caves (soluble beds, cave levels), water (springs at contacts), coast (weak lines) | features |
| Deposits: a mineral in a host, with genesis and shape | colony game, inspection | features (foundation only) |

| Needs | From |
|---|---|
| A rock story, its parameters and a seed; the region's frame in world coordinates | world rung |
| Uplift per cell and how much is still to come at each step; sea-level change at the end | land forming |
| Drainage order and receivers on the finished grid | land forming |
| Rain and temperature (how fast rock weathers; whether limestone dissolves enough to matter) | climate |

**Added to the shared vocabulary:** features *rock body* (bed, fault, intrusion, flow) and *deposit*; field *sediment source mix*. Everything else uses the brief's names.

## 3. Foundational decisions

**D1. The rock is fixed in the finished world's frame, and the land forming reads it shifted by the uplift still to come.**
Recommendation: define the rock in final coordinates. With time T − t left, a cell at simulated height z reads `rock(x, z + uplift[c]·(T − t) − DROWN, ...)`, so the rock the simulation cut is exactly the rock the blocks show, and the bands in a cliff are its cause.
Alternatives: current simulated height, as the experiment did (the beds cut early then lie up to ~2.4 km from where the blocks put them: 0.0006 m/yr over ~4 Myr, *measured from `land.odin`*); Cordonnier's original height h₀ (a stored value per cell that breaks when cells refine).
Expensive later: changing the frame moves every cliff relative to its rock.

**D2. A region's geology is a short list of bodies over one or more stacked sequences, evaluated as one function, with no voxel storage.**
Recommendation: up to three *packages* (basement, main, cover) separated by surfaces such as an unconformity or the base of a lava pile. Each is a *sequence* of beds (kind, thickness, name) under a *deformation*: planar tilt, folds as a warp, or radial tilt for a cone or dome. Across them cut *faults* (a plane with a throw and a weakened crushed zone) and *intrusions* (dike slabs, plugs, a pluton dome; sills are beds). A query computes `s = y − tilt·(x,z) − fold(x,z) − Σ throw`, looks the bed up in a table, and tests the few intrusions whose bounds hold the point. Folds never overturn, so the horizontal part of `s` can be cached per column.
Alternatives: Paris 2019's construction tree (~1 M queries/s, *sourced, `procedural-techniques.md`*, too slow for 14 M lookups); a stored 3D grid; DF's fixed stack (cannot make a cuesta).
Expensive later: caves, deposits and inspection all address rock through these bodies.

**D3. The answer at a cell size is the band-limited sequence, built once per level.**
Recommendation: for each level (1 to 64 m, and the 16 m simulation) precompute each sequence with beds under half a cell merged into their thicker neighbour, plus prefix sums of strength so the mean over any vertical window is exact. Dikes narrower than half a cell drop out, as `band` does for noise. Far columns show the dominant bed, never a flickering stripe.
Alternatives: point-sampling (stripes on far hills); averaged colours (mud-coloured mountains).
Expensive later: ADR 0001 rests on coarse answers averaging fine ones; breaking that brings back far-field seams.

**D4. Strength is one number per kind, rock-mass strength, from which erosion and slope limit are derived.**
Recommendation: strength 0..1 combines intact strength and crack spacing (Selby, *sourced, `real-geology.md`*). Erodibility = (0.5/strength)², clamped 0.2..5 (incision ∝ tensile strength², Stock 2005, *sourced*). Threshold slope 30° at 0.2 to 55° at 0.9 *(guess; the experiment used 39°/50°, Cordonnier 30°/50°)*. Creep scales with 1 − strength. Vertical faces exist only at the place rung, where cracks decide them.
Alternatives: separate erodibility and slope per kind (twice the tuning); strength classes (cannot be averaged).
Expensive later: every tuned landform depends on this mapping.

**D5. Every stone block carries its rock kind, including loose stone.**
Recommendation: `Mat` stays one byte: 0–63 everything else; 64–191 up to 32 rock kinds × 4 forms (solid, broken rock under soil, rubble and scree, gravel); 192–255 minerals. River gravel is gravel *of* the kinds upstream; scree is rubble *of* the face above.
Alternatives: generic Stone with a tint field (lost on digging and editing); two bytes now (doubles chunk memory early).
Expensive later: block identity reaches saves, the colour table and every edit.

**D6. A rock story is a row of data handed down from the world rung; the region derives everything else from it and a seed.**
Recommendation: a story names a kind pool per package, thickness and strength ranges, the hard fraction, deformation type and ranges, and counts of faults and intrusions. Bodies are placed in world coordinates, so regions sharing a province agree at their seam; province edges are faults or coasts, as terrane edges are.
Alternatives: hand-designed geology per region (does not grow); a tectonic simulation (v4; heavy, and still "declared priors").
Expensive later: the world rung and every region contract on it.

**D7. Resources are rows with a host and a genesis, realised from deposit features attached to rock bodies, and placers ride the sediment source mix.**
Recommendation: fix the mineral row's columns now (genesis, host, shape, appearance) and that a deposit hangs off a fault, contact, bed or intrusion, never free noise. The sediment source mix gives gravel colour in stage 1 and placers free.
Alternatives: DF's host-class ore blobs (no cause on the map); deferring all of it (deposits arrive later as noise).
Expensive later: a deposit added after the world is fixed contradicts it (`reference/zigcraft` DF research).

## 4. The kinds

**Axes this system owns.**

| Axis | States | What a walker sees |
|---|---|---|
| Rock story (district) | 1 → 8 → 12 | The shape of the country: scarps, ridge-and-vale, flat-topped hills, tors, lava steps |
| Rock kind at the surface | 5 → 20 → 28 | Colour and break form of faces, boulders and river gravel; the soil and plants it carries |
| Structure state (tilt × crack style) | ~3 tilts × 5 crack styles | Benches vs. tilted slabs vs. vertical fins; blocky, slabby, columnar, platy or rounded faces |
| Cross-cutting bodies | 0 → 4 types → 6 | Walls, trenches, plugs, a fault valley with a change of rock across it |
| Resources | 0 → ~12 → ~45 | Coloured veins and stained rock at faults and contacts, seams in cut faces, heavy gravel |

**Against the benchmarks.** DF's 25 layer stones include look-alikes (rhyolite, dacite, andesite; siltstone, mudstone, claystone); RimWorld has 5, TerraFirmaCraft 20, Vintage Story about 20 in 6 provinces. Match DF's families with about 28 kinds; exceed everyone in what a kind does, since each changes landform, face, gravel and soil. Leave out obsidian as a layer, DF's 127 gems (keep ~10 families), and rocks needing a history the world lacks (suevite, kimberlite).

**Two kinds count as different** only if they differ on foot in at least two of: colour or value in a face; break form (slabs, blocks, columns, plates, rounded corestones, rubble); strength class (landform); the soil and gravel they leave. Otherwise merge them.

**Rock kinds.** Strengths, spacings and colours are *guesses*, to be tuned by looking.

| Kind | Host (story or body) | Str. | Cracks | Water | Seen on foot | Colony |
|---|---|---|---|---|---|---|
| Mudstone / shale | layered, folded, under lava caps | 0.2 | thin platy, 0.1 m | tight | dark grey crumbly slopes, never a face; slips; grey clay soil | clay, poor stone |
| Siltstone | layered | 0.4 | flaggy, 0.3 m | tight | grey-brown thin ledges | flagstones |
| Sandstone, grey | layered, folded | 0.6 | blocky, 1–2 m | passes | buff-grey faces of rectangular blocks; sandy acid soil | best dressed stone |
| Sandstone, red | layered (arid-past variant) | 0.55 | blocky, 1–3 m | passes | red faces, red gravel and beaches | dressed stone |
| Grit / conglomerate | layered caps | 0.8 | massive, 3–5 m | passes | pale cliffs of pebbly rock, huge fallen blocks | rubble, millstones |
| Limestone | platform; one bed in layered | 0.65 | blocky + bedding, 1 m | dissolves | pale grey stepped scars, pavements, sinks; rich soil, distinct plants | flux, lime, stone |
| Chalk | soft-coast variant | 0.35 | crumbly, flints | passes, dissolves slowly | white cliffs, rounded downs, flint gravel | lime, flint |
| Coal seam | bed in layered (thin) | 0.15 | platy | tight | black band 0.5–2 m in cuts | fuel |
| Basalt (flow) | lava plateau, cap, volcanic | 0.75 | columnar 0.5 m, rubbly tops | fractured | black-grey stepped faces, columns, red interbeds | rubble, aggregate |
| Red tuff / bole | interbeds in lava | 0.25 | crumbly | tight | thin red bands under each lava step; springs | clay |
| Dolerite | dikes, sills, plugs | 0.9 | blocky-columnar, 0.5–1 m | tight | dark wall across country; sill ledge, waterfall lip | hard stone |
| Andesite / rhyolite (merged as "pale lava") | volcanic island | 0.7 | platy, 0.3 m | fractured | pale grey-pink sheeted crags | aggregate |
| Granite | pluton, granite upland | 0.85 | widely spaced 3–8 m, sheeting | fractured | tors of stacked rounded blocks, boulder fields, coarse pink-grey sand | ashlar, best |
| Gabbro | deep plutons, shield | 0.9 | massive | tight | very dark rough crags | hard stone |
| Quartzite | metamorphosed sandstone; ridges in shield | 0.95 | blocky, sharp, 1 m | fractured | white ridges, sharp scree, poor heath soil | hard stone |
| Slate | folded belt | 0.6 | cleaved, 0.02 m sheets | tight | blue-grey knife-edge outcrops | roofing |
| Schist | shield, belt cores | 0.5 | foliated, wavy | tight | glittering wavy bands, slabby slips | rubble |
| Gneiss | shield basement | 0.85 | banded, massive | fractured | striped grey-pink knobs, lakes in hollows | stone |
| Marble | limestone near a pluton | 0.6 | massive | dissolves | white crystalline faces, caves | carving, flux |
| Hornfels | mudstone near a pluton | 0.85 | blocky, splintery | tight | dark ring of steep ground round granite | hard rubble |

Twenty rows; rock salt, gypsum and serpentinite join with the wide world's stories, to about 28.

**Rock stories.** Two regions with one story differ by the seed's bed sequence, tilt direction and amount, fold wavelength, fault and intrusion positions, and how deep the land forming has cut.

| Story | Recipe | Country it makes (*sourced* in `real-geology.md`) |
|---|---|---|
| Layered, gently tilted | 25–50 beds, 30% hard, 5–20 m beds, tilt 2–8° | Cuesta scarps, dip slopes, rivers along scarp feet (the experiment) |
| Hard cap over weak rock | lava or grit cover 50–150 m on 200 m mudstone, near-flat | Long scarp, rotated slide blocks, ponds (Trotternish, Jūniko) |
| Flat-bedded | as layered, tilt < 2° | Stepped valley sides, benches, flat-topped hills |
| Folded belt | sandstone–slate alternation, folds 1–3 km, tilts 20–70° | Parallel ridges and vales, headland-bay coast |
| Granite against sediments | pluton dome + layered across one fault, hornfels/marble aureole | Two districts on one island (Arran) |
| Lava plateau | 15–40 flows of 10–25 m with red interbeds, < 3° | Staircase hills, columns, sea caves (Faroes, Staffa) |
| Limestone platform | thick limestone, shale partings, flat | Pavements, sinks, dry valleys, springs, caves |
| Metamorphic shield | gneiss basement, steep foliation, quartzite ridges | Knobby ground, many small lakes in hard hollows |
| Granite massif | one pluton, sheeting joints | Tors, domes, boulder rivers, slabby falls (Yakushima) |
| Young volcanic island | radial tilt off a vent, plugs, flows | Cone, radial valleys, plug stacks, lava tubes |
| Soft coast | chalk or clay over sand | White cliffs, rounded downs, landslipped coast |
| Evaporite basin | salt and red beds | Collapse hollows, salt flats (arid regions only) |

**Resources** (foundation rows; host written over the rock bodies):

| Mineral | Genesis and host | Seen |
|---|---|---|
| Galena (lead, silver) | veins in a fault's crushed zone through limestone or sandstone | grey metallic streak in a fault gully |
| Hematite (iron) | beds in red sandstone; veins at faults | red-black band; rust-stained spring |
| Copper ore | at granite contacts in hornfels and marble | green-stained rock round the pluton |
| Tin (cassiterite) | veins in granite roof; placers downstream | heavy dark grains in granite-river gravel |
| Gold | quartz veins in schist and slate; placers | specks in river gravel below them |
| Coal | seam beds in layered stories | black band in cuts and stream banks |
| Clay | weathered mudstone, lake beds | grey-blue sticky banks |
| Salt | evaporite beds; sea-shore pans | white crust |

Peat and beach sand belong to the water and plant systems; geology supplies only what they are made from.

## 5. How it works

**World rung.** Each region gets a story row, a seed and a few world-frame parameters (tilt direction of its province, the position of its bounding fault). Plate setting picks the story: converging edges give folded belts and plutons, diverging edges and hot spots lava, stable interiors platforms and shields, as TerraFirmaCraft and Vintage Story key rock to plate setting and province (*sourced, `minecraft-family.md`*). Cost: nothing measurable.

**Region rung, building the geology.** From story and seed: draw each package's beds (hard beds at least 20 m so the simulation holds them, *guess* from the experiment's 30 m beds), place bent fault traces and intrusions (dike swarms share a direction; plugs and plutons are warped round bodies), name each body, and build D3's tables. A few hundred records, under a millisecond *(guess)*.

Metamorphism is a remap: near a pluton, mudstone reads as hornfels, limestone as marble, sandstone as quartzite, which makes the ring round a granite visible and hosts the copper row.

**Region rung, inside the land forming.** Once per grid size, cache each cell's horizontal part of `s` and the vertical bounds of any intrusion over it. A step is then a subtraction and a table lookup: about 14 M lookups over the schedule *(counted from `SCHEDULE`)*, ~10 ns each *(guess)*, so ~0.15 s on today's 1.0 s; the experiment, with an fbm per lookup, cost 0.5 s *(measured)*. The rule is Cordonnier 2018's, erodibility and slope limit from the layer the surface has reached (*sourced, `procedural-techniques.md`*), with D1 and D4. A small random part of today's `soft` stays, so streams do not follow the grid.

After forming, one pass down the drainage (as `area` is summed) derives the surface rock and the sediment source mix, carrying each cell's mixture to its receiver *(guess: < 50 ms)*.

**Place rung.** Compute the horizontal part once per column, then walk down through the sequence, one increment per block. Each body has up to three crack sets; a block is in a gap when its jittered distance to a set's nearest plane is under the gap width, and basalt columns use a hexagonal cell hash. The cliff, cave and surface designs decide what gaps and weak beds become (ledges, undercuts, Paris 2019's density subtraction, *sourced*); geology only answers, and inspection reads body names from the query.

**Realism against cost.**

| Simulated at 16 m | Designed at the place rung, from the same function | Texture only |
|---|---|---|
| Beds ≥ 20 m, tilt, folds of km, faults that offset and juxtapose, plutons, plugs ≥ 50 m, lava piles, contact aureoles | Beds under 20 m, cracks and their spacing, columns, sills, dikes 1–3 m, veins, the broken zone under soil, slide blocks | Grain, crystals, laminations under 1 m, weathering rind, lichen, staining below springs and veins |

Not simulated: tectonic history, metamorphic grade, magma chemistry. The story is their designed answer.

## 6. Growth path

**Stage 0: tilted beds on today's island.** A new file `rock.odin`, about 150 lines *(guess)*: five kind rows (mudstone, siltstone, grey sandstone, grit, and limestone if the owner agrees), one story (layered, gently tilted, grit cap high in the sequence), the sequence builder, band-limited tables, `rock(x, y, z, cell)`. `land.odin` (~30 lines): per-cell cache, erodibility and threshold slope per step with the uplift shift, creep by strength. `gen.odin` (~25 lines): `surface_at` bares rock by slope against the surface rock's threshold; `block_below` returns the rock kind at depth. Five colours in the material table; the map tints surface rock; `CLAUDE.md` names the fourth file. The owner looks at `--map` (districts and scarps), a `--shot` from the air, and a `--shot` at the foot of a face where the bands in the blocks match the scarp. Gate: forming stays under 1.3 s; `--bench=8` still reaches about 57 m.

**Stage 1: the archipelago.** *Built as step 24 (`foundations.md`, section 8, "Step 24, as built"), but for the sediment source mix beyond gravel, deposits and inspection by body names; granite and gneiss there are 0.65 and 0.7, not the table's 0.85.* All twelve story rows written, eight in use; faults, intrusions, lava packages, contact remap; about 20 kinds with four block forms each; the sediment source mix and gravel of upstream rock; deposit features for the first rows (coal, iron, clay, galena), visible only in cut faces and gravel; inspection text from body names. Each island reads its story from a table.

**Stage 2: the wide world.** Story chosen from plate setting; provinces in world coordinates with fault boundaries crossing region seams; the full mineral table; gems as ~10 families nested in host rows.

**Not yet, and what starts each.**
- Deposits beyond a few rows: when the colony game has a use for metal.
- Cave networks: when the owner decides limestone is present and the cave design starts; geology already supplies soluble beds and contacts.
- Mineral blocks in the volume: when digging rewards anything.
- A second byte for `Mat`: when kinds × forms plus minerals pass ~190 ids.
- Overturned folds and thrusts: never, unless a story cannot be made without them.

## 7. Risks and known failures

- **Artificial banding** (v4), noise cliffs (Veloren). Bands come only from the function the simulation eroded; sub-cell beds show only where it made ground steep.
- **Ruled lines on the map.** The experiment's straight walls and round plugs read as diagrams (*measured, `interesting-world.md` §6*). Faults bend, dikes are short overlapping segments of varying width, plugs are warped; each is judged on the map before it ships.
- **Thresholds before measurement.** All strengths and angles start as guesses with two strength classes in use, and are tuned by looking.
- **The map changes and the walk does not** (*measured, §6*). Stage 0 is paired with the cliff step in the plan; geology alone is not offered as finished.
- **Layer-cake stripes.** Real beds differ more in break form and value than in hue. Colours stay natural; the difference shows through cracks, ledges and what falls from a face.
- **Cost creep in the land forming.** The per-cell cache keeps the step a lookup; any body that needs work per step must say so.
- **Accretion.** Kinds, stories and minerals are rows; the code is one query, one builder, one drainage pass.

## 8. Decisions for the owner

1. **The island's story for stage 0.** *Recommend layered, gently tilted, with a hard grit cap*, which the experiment already showed working. Alternatives: granite against sediments; lava plateau.
2. **One limestone bed?** *Recommend yes, low in the sequence*, so it crops out only in the deepest valleys and leaves the door open to springs and caves without making the island karst.
3. **How strong a colour contrast between beds?** *Recommend natural hues with value contrast raised a little*, judged in a screenshot of a face.
4. **Catalogue target.** *Recommend about 20 kinds in the archipelago and no more than 28*, merging DF's look-alikes.
5. **Minimum hard-bed thickness in the simulation.** *Recommend 20 m*; thinner beds become detail at the place rung only.
6. **Fantasy rocks and minerals.** *Recommend none reserved now*; they will be rows later.

## 9. Not verified

- The ~10 ns lookup and the 0.15 s forming cost are estimates; only the experiment's 0.5 s for an fbm per lookup was measured.
- The strength–erodibility square law rests on one field study (Stock 2005, read in a note); the slope range 30° to 55° is a guess between the experiment and Cordonnier.
- Whether the uplift shift (D1) changes the experiment's landforms visibly was not tested.
- Whether the band-limited sequence removes far-field stripes without making distant scarps vanish needs a look at the 64 m level.
- Rock colours, crack spacings other than the Giant's Causeway columns (0.4–0.5 m, *sourced*), and the story recipes' ranges are guesses.
- That 32 kinds × 4 forms, minerals and future plant blocks fit in one byte was counted roughly.
