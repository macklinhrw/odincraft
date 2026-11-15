# Foundations plan: shared brief

You are one of nine designers. Each of you designs ONE system of a game's world; a coordinator will join the nine designs into one plan. This brief is the frame all nine share. Read it fully, then read the project files it names, then design your system.

## The game

OdinCraft v5 lives in this repository. It is a first-person block game (one block is one metre) written in Odin, about 2,800 lines in `src/`. Read these before anything else:

- `CLAUDE.md`, `docs/ideas.md` (the destination), `docs/lessons.md` (why eight earlier attempts stalled), `docs/open-decisions.md`, `docs/adr/` (four short records).
- `docs/interesting-world.md`: research finished today on why the current world is dull and what the pieces of an interesting one are. Its notes in `docs/interesting-world/notes/` carry the sources.

The destination, from `ideas.md`: a block world that feels like a real place, formed by geology, water, climate and living things; explored on foot; understood through inspection as deep as Dwarf Fortress; later the stage for a colony game with Dwarf Fortress depth and RimWorld readability; later still an original Tolkien-like fantasy world. The long-term scale the owner accepted: a finite world about 1,000 km wide made before you enter it, about 10 km of visible terrain, 120 FPS, world creation within four minutes.

Today the world is one island about 6 km across. It is formed in about one second by an erosion simulation on 16 m cells (`src/land.odin`); rivers are traced from its drainage and their channels designed (`src/rivers.odin`); the engine asks the generator one question, "what is the ground at (x, z) seen at this cell size", from 1 m near the player to 64 m at the horizon (`src/gen.odin`, `adr/0001`). The nearest 256 m is a true block volume; beyond it the ground is one height and one material per column. Water near the player is a simulated depth per column (`adr/0004`). There is one tree, no rock structure, no lakes, no caves.

## What the owner asked for

A comprehensive plan for the systems that become the foundation of the future game, beyond the current island: a wider world with variety that matches or exceeds Dwarf Fortress, RimWorld and similar games. Each system gets its own careful design. That is your job for one system.

"Foundation" has a precise meaning here: **the decisions that are cheap to make now and expensive to change later**, and the smallest thing that must exist for the rest to grow on. It does not mean building the whole system now.

## The frame (assume it; say so if your system breaks it)

**1. Three kinds of thing.**
- A **field** has a value at every point and can be asked at a cell size: elevation, the rock at a point in the ground, wetness, temperature.
- A **feature** is a record with an identity and an extent: a river reach, a lake, a landslide, a cave, a stand of trees, a settlement, a named place.
- A **kind** is a catalogue entry: a rock type, a tree species, a landform piece, an animal. It is a row of data that states the conditions under which it occurs, written over fields and features.

Systems talk to each other only through fields and features. Variety grows by adding kinds, which should mostly be rows of data, not code.

**2. Context picks a designed piece.** Simulation answers why something is here; a designed kind answers what it looks like. Every kind names its host: the reason in the rock, water, climate or history for being where it is. Shapes stamped onto finished land read as diagrams (recorded failure). Every shipped game that solved sameness works this way: TerraFirmaCraft chooses among 125 landforms from measured context; RimWorld's Odyssey gates 41 landmarks by biome, hilliness, coast and river, then stacks modifiers.

**3. A ladder of scales, one question at every rung.**
- **World**: hundreds of kilometres, cells of a kilometre or more. Plates and crust, sea level, climate, which rock story each part has.
- **Region**: one landmass or drainage unit, roughly 5 to 50 km, on 16 m cells. Land formed by simulation as the island is today, with its boundary conditions (uplift, rock, climate, sea level) handed down from the world.
- **Place**: one-metre blocks, a true volume within 256 m of the player. Designed expression of what the region simulation produced.

A finer rung never contradicts a coarser one. The working hypothesis for growth is: one island now, then an archipelago in which each island is a region formed on its own with the sea as the seam and its own rock and climate, then larger landmasses divided into regions along coasts and drainage divides. The designer of the world frame will test this hypothesis; the rest of you should design so that your system works for one island first and does not assume the whole world fits in memory at 16 m.

**4. Variety comes from independent axes multiplying.** Rock province, rock structure, relief and process history, climate, exposure, water, disturbance, the age of a plant community, and later peoples and history. A long list on one axis does not make places feel different: Dwarf Fortress has 72 tree species in about six shapes. Say which axes your system owns, how many distinguishable states each has, and what a player on foot sees for each.

**5. Shared vocabulary.** Use these names; add to them only by listing what you add.
- Fields: elevation, slope, facing (which way the ground faces), hollow-or-humped (curvature), drainage area, wetness, distance to river, distance to sea, rock (kind, strength, tilt, crack spacing and direction, whether water passes through it, whether it dissolves), soil depth, soil kind, temperature, rain, exposure (wind and salt), sunlight, disturbance age, water table, plant community.
- Features: river reach, lake, wetland, spring, waterfall, coast stretch, cliff band, landslide, cave, stand, settlement, road, place.

## Benchmarks to match or exceed

Counts from the games' own data (see `docs/interesting-world/notes/df-rimworld.md` and `minecraft-family.md`):

| Game | Counts |
|---|---|
| Dwarf Fortress 53.17 | 51 biomes (27 land); 225 plants, 72 of them trees in about 6 shapes; 25 layer stones in a fixed stack; 21 soils; 58 minerals; 127 gems; 3 cavern layers; cliffs eroded away by default |
| RimWorld 1.6 + Odyssey | 17 biomes with 0 to 4 tree species each; 5 stones, 2 or 3 per map; 41 landmarks; about 70 map features that stack |
| Minecraft (current data) | 57 overworld biomes; 299 placed features; 10 tree species in 19 shapes; 3 noise cave types |
| TerraFirmaCraft | 125 landforms chosen by rule; 20 rocks; 20 trees; about 158 plants; 8 soils |

Exceeding them should not mean longer lists. It means every kind is perceptibly different on foot and tied to a cause a player can inspect.

## Constraints

- **Small code.** A foundation here is a rule, a function or a table. Prefer changing a rule to adding a system, and data rows to code. Do not invent module names, frameworks, version schemes or file formats beyond what your design needs.
- **Budgets.** The island forms in about a second and that speed is how the owner iterates. 120 FPS at 2560 × 1440. No generation work on the frame thread.
- **The same seed always makes the same world.** The world is finite and made before the player enters.
- **The four ADRs stand** unless you argue otherwise: one generator sampled at a cell size; faces lit by the slope they are cut from; rivers traced from the simulation and cut by design; water near the player as a depth per column.
- **Recorded failures** (`docs/lessons.md`): the ground under the player built last; rivers fitted to finished land; measurements passing while the owner's eyes rejected; scale fixed before anything was worth scaling; a gap between a coarse simulation and one-metre blocks filled with generic noise; projects that accreted; plans heavier than the change they describe; thresholds set before anything was measured.
- **The owner judges everything visual by looking.** One change at a time, each ending in something the owner can run in under a minute. Your first stage must be visible on today's island.
- Nothing is kept compatible yet. Saves, menus and the atlas are deferred on purpose.

## What to write

One Markdown file, at most about 3,000 words, in plain language, with these sections in this order:

1. **What it gives the player.** On foot first, the colony game second. Three to six sentences.
2. **Questions it answers.** The fields and features it provides to the other systems, and what it needs from them. A short table.
3. **Foundational decisions.** At most seven. For each: the decision, your recommendation, the alternatives, and why it is expensive to change later. This is the most important section.
4. **The kinds.** The axes of variety your system owns. Target counts at three stages (today's island; an archipelago of roughly 10 to 30 islands; the wide world), set against the benchmarks. Then 15 to 40 example rows that show the range: name, host conditions written over the shared fields, what the player sees. Say what makes two kinds count as different.
5. **How it works.** The method at each rung of the ladder, with rough costs. Cite the research notes or a web source for each method you rely on.
6. **Growth path.** Stage 0: the first slice on today's island (which existing file changes, a rough line count, what the owner looks at). Stage 1: the archipelago. Stage 2: the wide world. Then what NOT to build yet, and the trigger that would start each deferred part.
7. **Risks and known failures.** From `lessons.md` and the research, and how your design avoids each.
8. **Decisions for the owner.** At most six, each with your recommendation.
9. **Not verified.**

Rules:
- Design from the research already done; search the web only to settle a specific question, and cite what you use.
- Mark every number as measured, sourced or a guess.
- Be concrete and take positions. Where two designs are close, pick one and say what would change your mind.
- Do not modify the repository. Do not spawn subagents. Your only output is your one file, written to the path your task gives you. Your final message is that path and a five-line summary.
