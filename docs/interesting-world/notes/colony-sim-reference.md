# How real colony games do it: marking, digging, hauling, speed

The material is five folders under `~/reference-games/`, read on 2026-11-16 and not run. `RimWorld1.5.4409Decompiled/` is RimWorld 1.5 decompiled to C#: its README says "only personal use allowed" and "most of the code is under full copyright by Ludeon Studios", and its `Licenses.txt` covers only third-party parts (LibNoise.Unity, LGPL). It is copyrighted by its maker and was read only to understand it. `Rimworld_Data/` is RimWorld's shipped Defs, of version 1.6 (it holds Odyssey), so data and code are one version apart; it has no licence file. `Ingnomia/LICENSE` is the GNU Affero General Public License version 3. `dwarfcorp/LICENSE.txt` is a "Modified MIT License" (Completely Fair Games, 2015) that keeps images, models, sounds and music proprietary. `df-structures/` and `scripts/` are DFHack's description of Dwarf Fortress's memory and its Lua scripts; neither folder holds a licence file. No code from any of them is copied into OdinCraft; this note describes mechanisms and figures only.

Paths are shortened: `RW/` = `RimWorld1.5.4409Decompiled/Assembly-CSharp/`, `RD/` = `Rimworld_Data/Core/Defs/`, `DF/` = `df-structures/`, `DH/` = `scripts/`, `IG/` = `Ingnomia/`, `DC/` = `dwarfcorp/DwarfCorp/`, `DCC/` = `dwarfcorp/DwarfCorpContent/`. "(inference)" marks what was reasoned and not read.

## Key takeaways

1. **Work that cannot be reached is never handed out.** RimWorld offers a mine cell only if one of its 8 neighbours is walkable and the pawn can reach it (`RW/RimWorld/WorkGiver_Miner.cs`); Ingnomia asks whether the worker's region connects to a work position (`IG/src/game/jobmanager.cpp`, `isReachable`); dwarfcorp calls a dig infeasible when the voxel is "completely surrounded" (`KillVoxelTask.ComputeFeasible`). The mark stays and is tried again.
2. **A worker stands beside the cell, never in it.** RimWorld: any of 8 neighbours, a diagonal only if one of the two cells between is walkable (`RW/Verse/AI/TouchPathEndModeUtility.cs`). Ingnomia: the 4 cardinal neighbours on the same level (`WorkPosition` `'-1 0 0|0 -1 0|1 0 0|0 1 0'` in table `Jobs`). dwarfcorp: within radius 2.0.
3. **Walkers cross a cell in about a quarter of a second.** RimWorld human 4.6 cells/s, Ingnomia 4.4, dwarfcorp 3.75 (section 5).
4. **A block of rock takes 6 to 20 seconds, soil a third of that.** RimWorld granite 20 s, sandstone 8.3 s at skill 8; Ingnomia wall 11.9 s falling to 6.25 s; dwarfcorp dirt 3 swings against stone's 10.
5. **An idle worker looks again within about 3 seconds, and at once on finishing a job.** RimWorld's idle wait lasts 125 to 200 ticks (`RW/RimWorld/JobGiver_WanderColony.cs`); Ingnomia waits 100 ticks, 2.5 s, after a search that found nothing (`IG/src/game/gnomeactions.cpp:669`).
6. **A mark is data on the cell, apart from the job.** DF keeps 3 bits per tile (`dig` in `tile_designation`); RimWorld a `Designation` per cell or thing; Ingnomia tile flags `TF_JOB_WALL`, `TF_JOB_FLOOR`. Workers scan the marks.
7. **A drag is a rectangle on one level, tested cell by cell by the same rule that later commits it.** Cells that fail are left out without complaint; one message appears only if none passed (`RW/Verse/Designator.cs`, `Finalize`).
8. **Digging down always makes the way out.** Ingnomia's hole builds ramps in the hole and its 4 neighbours; DF pairs stair shapes level by level.
9. **Cancel is a tool of its own, first in every menu**, dragged like any other (`Designator_Cancel` heads all twelve lists in `RD/Misc/Designations/DesignationCategories.xml`).
10. **Each dig kind is a row of tile requirements**, not code: Ingnomia's `Actions_Tiles` gives, per offset, what is `Required`, what is `Forbidden` and the preview sprite.
11. **Goods are things lying in cells; a stockpile is a dragged zone with a filter and a priority; hauling arises from goods not in their best storage.** RimWorld's readout counts only what lies in storage.
12. **Building has three states**: a blueprint that needs nothing, a frame that holds delivered materials, the built thing. Delivering is one job, finishing another.
13. **A built block remembers it was built**: DF keeps the item and `original_tile`; Ingnomia sets `WT_CONSTRUCTED`; dwarfcorp `IsPlayerBuilt`.
14. **A click selects a thing, never the ground.** RimWorld shows the ground under the pointer as text at the bottom left with no click.
15. **Workers pass through one another.** RimWorld pawns collide only when hostiles are near; Ingnomia gnomes are blocked only by monsters.

## 1. Marking work by dragging

| Game | A drag | Levels | Shown | Cancel |
|---|---|---|---|---|
| RimWorld | Press, hold, release. Rectangle from start cell to mouse cell (`DesignationDragger.DragRect`); `DraggableDimensions` 0 = click only, 1 = line, 2 = rectangle | one | While held: a highlight on each accepted cell, an outline (RGBA 109,139,79,100), side lengths from 3 cells, the count from 5×5. After: the designation's icon on each cell (`Designation.DesignationDraw`, textures `Designations/Mine` ...) | Right click or the cancel key drops the tool and the drag (`DesignatorManager.ProcessInputEvents`) |
| Dwarf Fortress | Two corners; `dig` holds `No, Default, UpDownStair, Channel, Ramp, DownStair, UpStair` (`DF/df.d_basics.xml:11026`) | The second corner may be on another level and the shape repeats on each between (`DH/gui/design.lua:1412`) | Marker-only bit `dig_marked`; priority 1 to 7, default 4, per tile (`DF/df.block.xml:207`, `DH/internal/quickfort/dig.lua:598,627`). How the game draws marks: not found | `x` clears the bits (`do_remove_designation`) |
| Ingnomia | Two clicks, not a hold. Second click's level is forced to the first's (`IG/src/base/selection.cpp:213`) | Only actions with `MultiZ` (FellTree, Forage, HarvestTree, BuildScaffold) span the levels between | Every cell carries valid or not (`testTileForJobSelection`); size text "W x H"; Ctrl gives the outline only | Right click drops the first corner, again drops the tool |
| dwarfcorp | Hold from the first voxel under the pointer to the current one, found by a screen ray of 150 (`DC/Player/VoxelSelector.cs`) | Box between the two voxels; Alt+wheel grows it up or down | Box drawn; voxels with no visible face are dropped unless Alt is held | Right drag with the same tool cancels (`DigTool`) |

A RimWorld click with a rectangle tool is a 1×1 drag. dwarfcorp caps dig marks at `MaxVoxelDesignations` and says "Too many dig designations!".

**For OdinCraft.** Drag a rectangle on the cut level and keep the level of the first corner. Run the commit rule every frame for the preview and skip failing cells silently. Make cancel a dragged tool.

## 2. The kinds of digging and what each leaves

Dwarf Fortress (job types `DF/df.job.xml:121-160`; where each applies, `DH/internal/quickfort/dig.lua:171-300`):

| Mark | Job | Applies to | Leaves |
|---|---|---|---|
| Default | `Dig` | wall | floor; walkable (shape attributes, `tiletype_shape`) |
| Channel | `DigChannel` | wall, floor, ramp, down stair | open space here (inference: and a ramp below) |
| UpStair | `CarveUpwardStaircase` | wall | `STAIR_UP`: `walkable_up` |
| DownStair | `CarveDownwardStaircase` | wall or floor | `STAIR_DOWN`: `passable_low` |
| UpDownStair | `CarveUpDownStaircase` | wall, up stair | both |
| Ramp | `CarveRamp` | wall | `RAMP`, `walkable_up` (inference: opens the tile above as `RAMP_TOP`) |
| Default on ramp or stair | `RemoveStairs` | ramp, stair | floor |
| smooth 1, 2 | `SmoothWall`/`SmoothFloor`, `DetailWall`/`DetailFloor` | hard natural rock | smoothed, engraved |

Also `CarveFortification`, `CarveTrack`. A stair column is up stair at the bottom, up/down between, down stair on top (`DH/gui/design.lua:1345-1375`).

Ingnomia (tables `Actions`, `Actions_Tiles`, `Jobs_Tasks`; code `IG/src/game/canwork.cpp:715-1050`): `Mine` removes the wall and keeps the floor; `DigHole` removes the floor, mines the wall below and makes ramps there and in its 4 neighbours; `MineStairsUp` clears wall and floor above and builds stairs here from the mined material; `DigStairsDown` and `DigRampDown` do the same one level down; `RemoveFloor`, `RemoveRamp`; `ExplorativeMine` follows ore. `DigHole`, `RemoveFloor` and `BuildWall` jobs are taken fewest walkable neighbours first and skipped when "enclosed by same type"; a job flagged `MayTrapGnome` is worked from the position with the most walkable neighbours (`jobmanager.cpp:558`, `gnomeactions.cpp:575`). dwarfcorp has one kind: the voxel goes; its dwarves climb out by jumping one voxel up or by ladder.

**For OdinCraft.** A level here is two blocks of air over a floor, so "mine" removes two blocks and "channel" three. Offer mine, dig down with a ramp or stair, stair up; never a bare pit.

## 3. Felling and gathering

- RimWorld: trees are things; drag selects the plants in the cells (`RW/RimWorld/Designator_Plants.cs`). `harvestWork` 800 (base tree, poplar), 710 (pine), 1400 (oak); yield 25 to 27 wood, oak 46 (`RD/ThingDefs_Plants/`). Work per tick is `PlantWorkSpeed` × 1 at full growth: 13.3 s, 11.8 s, 23.3 s at skill 8. Wood drops by the worker as one stack.
- Ingnomia: `FellTree` needs `Floor|Tree`, duration 10 (2.4 s); one `RawWood` per cell of the tree's layout, dropped under that cell, plus 1 to 3 seeds (`IG/src/game/plant.cpp:452`).
- Dwarf Fortress: the Default mark on the trunk; job `FellTree`, skill `WOODCUTTING`, item `WOOD`. Count and time: not found.
- dwarfcorp: trees are entities picked by a screen rectangle; health 100 × size, 2 × size wood (`DC/Entities/Plants/Tree.cs`); up to 3 choppers.

**For OdinCraft.** Mark the tree, not its blocks: any trunk block in the dragged rectangle marks the whole tree. Yield follows trunk blocks.

## 4. How work is found and taken

- RimWorld: each pawn orders its work givers by its priority 1 to 4, then by the type's `naturalPriority` (Construction 900, Mining 600, PlantCutting 500, Hauling 300; `RD/WorkTypeDefs/WorkTypes.xml`, `RW/RimWorld/Pawn_WorkSettings.cs:198`). `JobGiver_Work` takes the first giver with a target and, within it, the closest reachable one. `Reserve` gives a target to one pawn (`ReservationManager`).
- Ingnomia: one list. The gnome passes its skills in order; the manager walks priority 9 to 0 and nearest first, checks tool, items and region, and returns a job. Failed jobs sit in `m_returnedJobQueue` and are re-tested every tick within 3 ms.
- Dwarf Fortress: a linked list of `job` with `job_postingst` and `job_applicationst`; some 177 entries in `unit_labor` (`MINE`, `CUTWOOD`, `HAUL_STONE` ...). A haul job with no worker counts `expire_timer` up once per 50 ticks and is deleted at 20 (`DF/df.job.xml:1749`). Adjacency: not found.
- dwarfcorp: highest priority, then least cost; dig cost is distance² + 10 × depth below the top, so digging goes top down; `MaxAssignable = 3`.

**For OdinCraft.** Filter by reach before handing out, and print why a mark is waiting. Work positions are the 4 neighbours on the floor beside or one step above or below (inference).

## 5. Speed, in real numbers

RimWorld runs 60 ticks/s; speeds ×1, ×3, ×6 (`RW/Verse/TickManager.cs:58`). A day is 60,000 ticks, 16.7 minutes.

| Thing | Figures | Seconds at ×1 |
|---|---|---|
| Walk | `MoveSpeed` 4.6 c/s: 13 ticks a cell, ×1.414 diagonal, + terrain `pathCost` (soil 2, sand 4, mud 14) | 0.25 a cell on soil |
| Mine | a hit every 100 ticks ÷ `MiningSpeed`; 80 damage to natural rock; speed 0.04 + 0.12 × skill (`RW/Verse/AI/JobDriver_Mine.cs`). Hit points: sandstone 400, slate 500, limestone 700, granite 900, ore 1500 | skill 8: 8.3, 11.7, 15, 20, 31.7 |
| Wall | `WorkToBuild` 135, 5 of a material; wood ×0.7; stone blocks ×6 + 140; 1.7 work a tick × `ConstructionSpeed` (0.3 + 0.0875 × skill) | wood 0.9; granite 9.3 |
| Wood floor | 85 work, 3 wood | 0.8 |

Stone drops a chunk 1 time in 4 (`mineableDropChance` 0.25); ore 40.

Ingnomia runs 40 ticks/s (25 ms; fast 5 ms). Duration × 10 ticks, less 5 % per skill level, kept within 10 to 1000 (`gnomeactions.cpp:1829`): mine 50 = 11.9 s, hole 20 = 4.75 s, wall 50, floor 20, stairs 30 = 7.1 s. A cell takes 9 ticks at the lowest speed 30 (delay 250): 4.4 cells/s.

dwarfcorp: walk 0.75 × Dexterity 5 = 3.75 voxels/s, climb half. Voxel health dirt and sand 30, stone 100, granite 300; a swing does 1 + Strength 5 + Size 5 = 11. Seconds a swing: not found. Placing a block: 1.0 s. Dwarf Fortress: not found.

**For OdinCraft.** Walk 4 m/s. A soil block 2 s, a rock block 4 to 6 s, since each cell is two blocks. Give the clock ×1, ×3, ×6.

## 6. Goods and stockpiles

- RimWorld: an item is a `Thing` with `stackCount` in a cell; `stackLimit` 75 for resources, 1 for chunks; a pawn carries 75. `Designator_ZoneAddStockpile` drags a zone over standable cells. Settings are a filter and a priority (`Low, Normal, Preferred, Important, Critical`; default Normal). `ListerHaulables` holds items not in their best storage; haulers take the closest and `StoreUtility` picks the nearest cell in the highest priority zone. `ResourceCounter` sums storage only, every 204 ticks. Chunks need a haul mark.
- Dwarf Fortress: `stockpile_settings` has 17 group flags (animals, food, furniture, corpses, refuse, stone, ammo, coins, bars_blocks, gems, finished_goods, leather, cloth, wood, weapons, armor, sheet); `max_barrels`, `max_bins`, `max_wheelbarrows`; links `give_to_pile`, `take_from_pile` (`DF/df.building.xml:303,948-996`).
- Ingnomia: each item is one object; a stockpile cell holds `StackSize` of them (RawWood 1, RawStone 10, RawSoil 20). The stockpile makes its own haul jobs, 50 items a look (`IG/src/game/stockpile.cpp:348`).
- dwarfcorp: a zone holding 32 resources a voxel, with tag white and black lists.

**For OdinCraft.** Dug blocks become goods on the floor. One stockpile tool, filter by kind, and a count of what is stored.

## 7. Building

RimWorld: a `Blueprint`; `WorkGiver_ConstructDeliverResourcesToBlueprints` hauls to it and it becomes a `Frame`; `WorkGiver_ConstructFinishFrames` works it. Walls drag as lines, floors as rectangles (draw styles `Default1D` and `Default2D`, `RD/DrawStyleCategoryDefs/`). Ingnomia: phases `PENDING`, `HAULING`, `READY`; one item a block (`StoneWall` 1 RawStone, `PlankFloor` 1 Plank, `Scaffold` 2 Plank), so a mined wall builds a wall. `BuildStairs` needs a floor here and nothing above. Dwarf Fortress: `construction_type` FORTIFICATION, WALL, FLOOR, STAIR_UP, STAIR_DOWN, STAIR_UPDOWN, RAMP, tracks; a `construction` record keeps the item and `original_tile` (`DF/df.event.xml:191`). dwarfcorp: one resource a voxel, lowest first.

**For OdinCraft.** One good a block. Show the unbuilt block as a ghost that says what it waits for. Keep built blocks in the list of edits with their origin.

## 8. What a click selects and shows

RimWorld selects things flagged `selectable` (pawns, buildings, items, trees, natural rock) and zones under the pointer, never bare terrain (`RW/RimWorld/Selector.cs:325`). Shift adds; double click takes all alike on screen; at most 200. The inspect pane is 432 × 165 px at the bottom left, with tabs 72 × 30, and opens only when something is selected. Terrain shows with no click: lines 19 px apart from (15, 65) at the bottom left, giving light, terrain with walk speed, zone, things, roof (`RW/Verse/MouseoverReadout.cs`); it hides while any main tab is open, the inspect pane included. Ingnomia's tile info lists wall, floor, embedded, plant, water, items, creatures and the job with worker, priority, required tool and whether it exists (`IG/src/gui/aggregatortileinfo.h`). dwarfcorp shows the voxel's type name on hover.

**For OdinCraft.** Hover reads the block; a click takes a dwarf, good or mark. A marked block's card says who has it or why nobody does.

## 9. The orders menu's structure

RimWorld's categories by `order`: "orders" 900, "zone" 800, "structure" 700, "production", "furniture", "power", "security", "misc", "floors", "recreation", "ship", "temperature". Orders holds Cancel, Deconstruct, Mine, PlantsHarvestWood, PlantsCut, PlantsHarvest, Hunt, Slaughter, Tame, Haul, Unforbid, Forbid, Claim, SmoothSurface, paint and plan tools. Zone holds the two stockpiles, growing zone, ZoneDelete, home, allowed, roof and snow areas. Labels and descriptions of designators: not found (keyed strings are not in the material). The menu is 200 px wide with 32 px buttons.

Ingnomia (`IG/content/JSON/menusettings.json`): Terrain (Mine: "Wall" "Remove wall", "Stairs Up" "Mine the wall into stairs going up"; Dig: "Hole" "Remove floor and section below", "Stairs Down", "Ramp Down"; "Remove Floor", "Remove Ramp"), Agriculture ("Fell Trees" "Cut trees down"), Build, Designate Area ("Stockpile" "Store items"), Job (Suspend, Resume, Cancel, Raise priority, Lower priority). dwarfcorp tools: Dig, Chop, Gather, BuildWall, BuildZone, PlaceObject, CancelTasks.

**For OdinCraft.** Name tools by the verb and the result, each with one line saying what is left behind.

## 10. Walkers in a voxel world with levels

Ingnomia (`IG/src/game/worldgetters.cpp:691`): a cell is a floor with or without a wall and a walker is one cell tall. Moves: 4 neighbours; a diagonal only when both cells between are walkable; a stair or scaffold wall goes straight up and its top straight down; a ramp reaches the 4 neighbours of the cell above. Every tile change updates a region map; the path-finder answers "no connection" from regions before searching. A blocked next step clears the path. dwarfcorp (`DC/Components/AI/CreatureMovement.cs`): the dwarf fills one voxel over a solid one; walks to 4 empty neighbours, diagonals only in the open; jumps one up when the voxel over its head is empty; falls (cost 30); climbs things tagged `Climbable`. Plans stop at 10,000 expansions. RimWorld checks the next 20 path cells each step and plans again.

**For OdinCraft.** Standing needs a floor and two blocks of air; a step up needs three over the start. Keep regions so reach is a lookup.

## 11. Needs, briefly

- RimWorld: `RD/NeedDefs/`, `RW/RimWorld/Need_Food.cs`, `Need_Rest.cs`; Mood, Food, Rest, Joy, Beauty, Comfort, Outdoors.
- Ingnomia: tables `Needs`, `Needs_States`; Hunger, Thirst, Sleep, Happiness, with thresholds 30, 15, 0.
- Dwarf Fortress: `hunger_timer`, `thirst_timer`, `sleepiness_timer` (`DF/df.unit.xml:2945`); `need_type` and `stress` (`DF/df.personality.xml:1374,1503`).
- dwarfcorp: `DC/Components/AI/CreatureStats-Status.cs`; Hunger, Energy, Happiness, Boredom.

## 12. Before play: the main menu, making a world, the world's map, choosing a site

Read on 2026-11-16 for step I-2 (the front door and the world's screen), before any of it was changed. What a player of the two games expects of these screens, with where it was read. Lines marked "(as played)" are from the games as played and their wikis, since `df-structures` holds the screens' fields and not their drawing.

### What a player expects

1. **The menu is usable at once and is a short list.** RimWorld draws its list over a still picture, with nothing to wait for: in the entry scene it is Tutorial, New colony, Load game, Options, Mods, Credits, Quit (`RW/RimWorld/MainMenuDrawer.cs:114-210`, a `List<ListableOption>`). The same procedure is the menu in play, with Save, Review scenario, Quit to main menu in the list instead. Dwarf Fortress's title has modes `MAIN_MENU`, `CONTINUE_INACTIVE`, `CONTINUE_ACTIVE_WORLD`, `CONTINUE_ACTIVE`, `ABOUT` (`DF/df.d_interface.xml:6334`): **Continue is its own state, first, and names the game it goes on with**, and the worlds are a list of headers with a name each (`region_headerst`, `DF/df.region.xml:485`: `name`, `display_name`), sortable by name, folder or how lately played (`save_game_sort_type`).
2. **A world has a name of its own, and so has every place in it.** DF names the world, each region (`world_region.name`, a `language_name`, `DF/df.region.xml:328`), each site and each civilisation; the embark screen's first line of a biome is the region's name, "The Hills of Ringing", and its kind, "Temperate conifer forest", is the second (as played). RimWorld names the planet (`WITab_Planet`, `Find.World.info.name`), and titles a tile by its biome because a tile is one of thousands and is not a place anyone goes back to; a settlement, which is, has a name.
3. **Making a world asks little, says how long, and can be watched.** RimWorld: one page, a seed as words with Randomize, how much of the planet (30% by default; choosing 100% raises a caution about performance, `RW/RimWorld/Page_CreateWorldParams.cs:112-131`), and three sliders, rain, temperature, population; then Generate. DF's simple page is seven choices of a few steps each: world size, history, number of civilisations, site cap, beasts, savagery, minerals (`viewscreen_new_regionst`, `simple_world_size` to `simple_minerals`, `DF/df.d_interface.xml:6090`), with the seed and every figure behind an advanced page. While it runs DF draws the map as it is made and counts the years of history, and the making can be stopped and the world used as far as it came (`abort_world_gen_dialogue`); a world that fails its own tests is rejected and begun again with a reason (`reject_dialogue_type`).
4. **Choosing a site opens on land that can be chosen, with one already in the hand.** RimWorld's page chooses a random valid tile on opening and jumps the camera to it (`RW/RimWorld/Page_SelectStartingSite.cs:47-50`, `ChooseRandomStartingTile`; "Select random site" does it again and `JumpTo`s the tile, line 213). The camera starts at 550 of 125 to 1,100 (`RW/RimWorld/Planet/WorldCameraDriver.cs:40-48`), about half way in: a tile is large enough to read. DF opens on three maps at once, the world, the region and the local square, the cursor on a place (as played).
5. **The wheel zooms by a share of how far out you are, the drag and the arrows move.** RimWorld: each notch changes the altitude by `zoomSpeed * altitude / 12` (`WorldCameraDriver.cs:140`), clamped to the range; four dolly keys and the screen's edges move. DF: the map is dragged with the mouse (`mouse_scrolling_map` and its anchors, `DF/df.d_interface.xml:6668`) and `zoomed_in` toggles the nearer view.
6. **What is said of a site is rows: a thing on the left, a word or a figure on the right, the why on hovering.** RimWorld's Terrain tab is a title (the biome), one sentence, and then `LabelDouble(left, right, tip)` rows between rules (`RW/RimWorld/Planet/WITab_Terrain.cs:38-120`): Terrain (hilliness), Road, River, Movement difficulty (the tip is the sum explained), Stone types here, Elevation; then Average temperature, Growing period, Rainfall, Forageability, Animals can graze now; then Disease frequency, Time zone, Special features (coast, caves). The pane itself, bottom left, says in one line each: latitude and longitude, hilliness, road, river, movement difficulty, average temperature (`RW/RimWorld/Planet/WorldInspectPane.cs:88-125`). No row is a sentence.
7. **DF says of a site, by tab** (`choose_start_site_view_mode`, `DF/df.d_interface.xml:6624`): Biome (each biome of the rectangle by F-key: its region's name, its kind, temperature, trees, other vegetation, surroundings; then the site's aquifer, soil, clay, sand, flux stone, shallow and deep metals as present or not, and the rock layers), Neighbors (each civilisation, how far, at war or not: `def_candidate`, `def_candidate_mindist`, `embark_neighbor_state_type`), Civilization, Elevation, Cliffs, Reclaim, Find, Notes. Each line is a noun and a word ("Trees: Heavily forested"; as played).
8. **It warns before you commit, by cause.** DF's `warn_flag` (`DF/df.d_interface.xml:6645`): water table, heavy water table, salt water, large, small, dead civilisation, savage, evil, undead; the player sees them as a list on pressing Embark and may go on (as played). RimWorld refuses with one line of why (`TileFinder.IsValidTileForNewSettlement`: cannot land on this biome, impassable mountains, tile occupied, a faction base adjacent) and Next does nothing more.
9. **A site can be searched for by what it has.** DF's finder takes a wish for each of `embark_finder_option` (`DF/df.region.xml:2`): size, savagery, evil, elevation, temperature, rain, drainage, flux stone, aquifer, river, underground river, pool, magma pool and pipe, chasm, pit, soil, clay, sand; and marks what matched wholly or in part (`find_results`: none, partial, suitable).
10. **The button says what happens next, and the next thing is preparing, not playing.** RimWorld's is Next, to choosing colonists; DF's is Embark, to "Prepare for the journey carefully" or "Play now" (`viewscreen_setupdwarfgamest`). Neither lands anyone from the map.
11. **The world's own facts are one small tab.** RimWorld's Planet tab is the name, the seed and the coverage, three lines (`RW/RimWorld/Planet/WITab_Planet.cs`).

### For OdinCraft

- **The front door**: a short list over a picture that is there from the first frame, the first choice the game to go on with, named. Nothing may stand between the player and the list.
- **Names.** An island is a place a hold is founded on and gone back to, as a DF region or site is: it wants a name of its own, first, and its kind second. A world wants one too; a seed is its number, as RimWorld's Planet tab has both.
- **The world's screen opens on the land there is to choose from**, with the start in the hand, near enough that an island reads as land. The wheel zooms by a share; a drag and the arrows move.
- **An island's card is rows**, a thing, then a figure or a word, with the why on asking; ordered as the Terrain tab is, by what a founder asks first: how much land and how steep, water, stone, climate, who lives there, then what is special.
- **A caution before a door is taken** belongs on the card as rows that say why, in DF's manner: no landing, no stream, no large animal.
- **The door's words say what happens**: with no expedition to prepare (E-1), the honest words are those of what is done today.
- **Making a world**: one field, the seed, with a way to draw one; each stage named with how far it has come, the map drawn as it is known; a way to stop. Where a stage is long it says how long and can be left.
- **A finder** (9) is not built: eleven islands can be read one by one. It belongs with E-1, once a world has more places than can be looked through.

## 13. Before play: choosing the ground and the party

Read on 2026-11-16 for step E-1 (expedition planning), before any of it was built. What a player of the two games expects of the screen that stands between the world's map and the first moment of play, with where it was read. Lines marked "(as played)" are from the games as played and their wikis.

### What a player expects

1. **A place is already chosen, and a party is already drawn.** RimWorld's site page chooses a valid tile as it opens (`RW/RimWorld/Page_SelectStartingSite.cs:52`, `ChooseRandomStartingTile`), and its colonists are generated before their page is shown (`RW/Verse/StartingPawnUtility.cs`, `NewGeneratedStartingPawn`). DF's preparation begins with a choice between "Play now" and preparing carefully (`initial_selection`, `DF/df.d_interface.xml:6812`), and its seven are there either way. A player who only wants to begin presses one button.
2. **The ground is chosen on the map itself, and what is said of it follows the pointer.** DF moves a rectangle over the local map (`embark_dx`, `embark_dy`, `viewscreen_choose_start_sitest`, `DF/df.d_interface.xml:6700`) and the site's lines change as it moves (as played). RimWorld's selected tile is whatever was clicked, read each frame (`Page_SelectStartingSite.DoWindowContents`, line 127), and the inspect pane says the tile. Neither makes the player open anything to read a place.
3. **The game offers, the player overrules.** RimWorld has "Select random site" beside Next (line 215), which jumps the view to the tile it chose. DF has the finder, which marks what matched (section 12, item 9). Both leave every other place a click away.
4. **A hard site is allowed, and warned of by cause.** DF's `warn_flag` (`DF/df.d_interface.xml:6645`: water table, heavy water table, salt water, large, small, dead civilisation, savage, evil, undead) is shown as a list when Embark is pressed, and the player may go on (as played). RimWorld refuses only what cannot be done at all, with one line of why (`RW/RimWorld/Planet/TileFinder.cs:51`, `IsValidTileForNewSettlement`: the biome cannot be landed on, impassable mountains, the tile is occupied, a faction's base is adjacent). The difference is the rule: what is impossible is refused with its reason, what is merely bad is said and allowed.
5. **The party is a list down one side, and one of them is looked at.** RimWorld: a column 140 wide of entries 60 high, each a faint portrait, a name and a title, under the heading "selected" (`RW/RimWorld/Page_ConfigureStartingPawns.cs:150-213`, `PawnEntryHeight`); the one clicked fills the rest of the page with its card: name, age, the two backstories, traits, what it cannot do, its skills (`RW/RimWorld/CharacterCardUtility.cs`, `DrawCharacterCard`). DF: the seven as rows, name and profession, with a skills pane by tab for the one in focus (`dwarf_info`, `embark_skills` by `embark_skill_tab_type`: crucial, labor, combat, other; `DF/df.d_interface.xml:6781-6804`).
6. **One of them can be drawn again, as often as wanted.** RimWorld's Randomize is a button 200 wide at the top right of the card of the one in focus (`CharacterCardUtility.cs:42`, `:143`), and does that one alone (`StartingPawnUtility.RandomizePawn`, line 195). It has no button for all of them. DF has neither: its dwarves' names and persons are given, and what the player changes is their skills, by points (`skill_picks_left`, `points_remaining`).
7. **The party is summed for what it can do.** RimWorld draws "Team skills" under the card, four columns of every skill with the level of the best of the party at it and that one's name (`StartingPawnUtility.DrawSkillSummaries`, line 145; `FindBestSkillOwner`). It stops Next where a kind of work nobody can do is required, in the tutorial, and elsewhere asks once and lets the player go on (`Page_ConfigureStartingPawns.cs:313`, `CheckWarnRequiredWorkTypesDisabledForEveryone`). DF lists its objections before leaving (`objection`, `viewing_objections`, line 6823).
8. **The last button says what happens, and it happens.** RimWorld's is "Start" (`DoBottomButtons(rect, "Start".Translate())`, line 120); DF's is Embark, with a last confirmation (`embark_confirmation`). Back is the other button, at the other end of the same row, and Escape does it (`KeyBindingDefOf.Cancel`, `Page_SelectStartingSite.cs:206`).
9. **Going back loses nothing.** RimWorld's pages are a chain: Back from the colonists returns to the site with the tile still selected, and forward again finds the same colonists (`Find.GameInitData` holds both until the game starts). DF keeps an embark profile by name (`embark_profile`, `saving_profile`).
10. **What they bring is its own long list, after who.** DF: items by category, bought with the points left from skills, and animals (`s_item` by `entity_sell_category`, `chosen_pet_index`). RimWorld: fixed by the scenario, shown as possessions on each card. Not this step's (P5).

### For OdinCraft

- **The screen opens with the landing the game would choose in the hand and the seed's party drawn**, so Enter alone sets out. Everything else is a wish to do better or worse than that.
- **The ground is the island's shore, chosen on the island's own picture.** Our unit of choice is where a boat comes in: the shore, a land cell at a time, with the camp beside it. The site card follows the pointer along the shore and returns to what is chosen when the pointer leaves the map; a click chooses. The landings the island has are marked on its shore and listed, the game's first.
- **The site card is rows**, as the island's is: a thing, a word or a figure, a sign, the why on asking. In a founder's order: can a boat lie there, is there water, is there ground to live on and how steep, is there timber, what is the rock. Then what the world knows that may harm, by name, in a place of its own.
- **Refuse only what cannot be done, and say why.** A shore that stands as a cliff takes no boat, and the pointer on it says so. An open shore, a dry one, a steep one, one with no tree in sight is chosen like any other and lands the party there, with its cautions named beside the button.
- **The party is rows down the side that says what is chosen**, each a picture, a name, a trade and an age, and each with its own way to be drawn again; and one way to draw them all, which RimWorld lacks and seven rows of buttons ask for. A dwarf has a trade and no skills yet, so there is no card to fill the middle with: the row is the card.
- **The party is summed by the kinds of work there are** (`WORKS`): who digs, who fells, who builds, by name, and "no one's trade" where it is so. It is what "Team skills" is for: the reason to draw again.
- **Set out is one button, bottom right, with its key; Back is at the other end with Escape.** What was chosen is kept when the player goes back and comes in again.
- **No list of what they bring, no home hold, no finder**: P5, P9, and a world with more places than can be read.

## 14. Needs and the year: hunger, thirst, sleep, gathering, fishing, the calendar

Read on 2026-11-16 for step P4's first half, before it was built. Every figure has its file; "(from memory)" marks what is not in these folders.

### The calendar

| | A day | A year | Real time of a day | Real time of a year |
|---|---|---|---|---|
| RimWorld | 60,000 ticks, 2,500 an hour (`RW/RimWorld/GenDate.cs:16,28`) | 60 days, four quadrums of 15 (`GenDate.cs:25,27`) | 16:40 at normal speed, 5:33 at 3 times, 2:47 at 6 (60 ticks a second times `TickRateMultiplier` 1, 3, 6, or 12 when nothing is happening: `RW/Verse/TickManager.cs:58-90`) | 16.7 hours at normal, 2.8 at 6 times |
| Dwarf Fortress | 1,200 ticks (`DH/docs/set-timeskip-duration.rst:57`) | 403,200 ticks: 12 months of 28 days, 336 days (`:59-60`) | 12 s at the default 100 ticks a second (the cap from memory) | 67 minutes |
| Ingnomia | 14,400 ticks, 10 a game minute (`IG/src/base/util.h:96-99`) | 48 days, four seasons of 12 (`util.h:100`) | 12 minutes at its slow 50 ms a tick, 72 s at its fast 5 ms (`IG/src/game/game.h:134-135`) | 9.6 hours slow |

RimWorld's pawns and Ingnomia's gnomes live by the hour: they work by day and sleep by night. Dwarf Fortress's day is too short to live by: a dwarf sleeps about once a month and eats twice a season, and the season is what the player feels. RimWorld's default timetable sleeps from 22:00 to 06:00 (`RW/RimWorld/Pawn_TimetableTracker.cs:31`: `index <= 5 || index > 21`).

### Hunger

- **RimWorld** (`RW/RimWorld/Need_Food.cs`, `HungerLevelUtility.cs`, `JobGiver_GetFood.cs`; `RW/Verse/RaceProperties.cs:150-170`). A person's food holds 1.0 and falls 2.6667e-5 a tick, 1.6 a day: full to nothing in 15 hours. It falls at half that once hungry, a quarter once urgently hungry, and not at all at nothing (`HungerMultiplier`: 1, 0.5, 0.25, 0). A pawn looks for food under 0.3 (`FoodLevelPercentageWantEat` for an omnivore; `GetPriority` 9.5, over rest's 8), is "hungry" under 0.24 and "urgently hungry" under 0.12. A new colonist starts at 0.8. Eating takes 500 ticks, 8 s (`IngestibleProperties.baseIngestTicks`); a simple meal is 0.9 (`RD/ThingDefs_Items/Items_Food.xml`), so a pawn eats a little under twice a day. At nothing, malnutrition grows 0.453 a day, a fifth more or less by the pawn, and kills at 1 (`BaseMalnutritionSeverityPerDay`; `RD/HediffDefs/Hediffs_Global_Needs.xml`: stages at 0.2, 0.4, 0.6, 0.8, `lethalSeverity` 1): 2.2 days. From a full belly to death is about 3.1 days, 52 minutes at normal speed and under 9 at 6 times.
- **Dwarf Fortress** (`DF/df.unit.xml:2945-2953`; `DH/internal/notify/notifications.lua:93-95`). `hunger_timer` counts up every tick and eating sets it back. DFHack calls a unit in dire need over 75,000, which is the game's "starving": 62 days. Hungry is 50,000 (from memory). Death comes only when `stored_fat` is gone ("hunger leads to death only when 0"). The status flags are drowsy, very drowsy, dehydrated and starving (`DF/df.d_interface.xml:7241-7245`).
- **Ingnomia** (`IG/content/db/ingnomia.db.sql:10582-10585,10596`). Hunger holds 100 and loses 0.025 a game minute, 36 a day: hungry at 30 (1.9 days), very hungry at 15, starving at 0 (2.8 days: "EatClosest"), dead at -100 (5.6 days).

### Thirst

- **RimWorld has none.**
- **Dwarf Fortress**: `thirst_timer`; dire over 50,000 ("dehydrated", 42 days), thirsty at 25,000 (from memory): thirst runs twice as fast as hunger, so a dwarf drinks about twice for each meal. The job is `Drink`, "from drink area", or `DrinkItem` from a container (`DF/df.job.xml:205-217`): a dwarf with no drink in store walks to water and drinks there.
- **Ingnomia** (`:10586-10589,10597`): the same figures as hunger.

### Sleep

- **RimWorld** (`RW/RimWorld/Need_Rest.cs:20-28,42-55,94`; `JobGiver_GetRest.cs:28-58`). Rest holds 1.0 and falls 1.5833e-5 a tick, 0.95 a day: full to tired (0.28) in 18 hours, very tired at 0.14. Asleep it gains 3.8095e-5 a tick times the bed's worth, a full sleep in 10.5 hours. A pawn lies down under 0.3 at any hour, and whatever its rest in the hours its timetable gives to sleep, where it falls asleep under 0.75 (`DefaultFallAsleepMaxLevel`) and wakes at 1.0. At nothing it falls asleep where it stands, on average within a quarter of a day. With no bed it sleeps on the ground where it is.
- **Dwarf Fortress**: `sleepiness_timer`; dire over 150,000 ("very drowsy"); drowsy at 57,600 (from memory), 48 days.
- **Ingnomia** (`:10580-10581,10595`): loses 0.03 a minute, 43 a day; very sleepy at 25, asleep on the spot at 0; sleep gives 0.35 a minute.

### Gathering and fishing

- **RimWorld**: plants are harvested by a designation dragged over them, one mark a plant, done once. A wild berry bush gives 10 berries of 0.05, half a nutrition, for 250 ticks of work, four seconds, and bears again 4.2 days later (`RD/ThingDefs_Plants/Plants_Wild_Temperate.xml`, `Plant_Berry`: `harvestYield` 10, `harvestWork` 250, `growDays` 6, `harvestAfterGrowth` 0.30; `Items_Resource_RawPlant.xml`). Rice gives 6 in 3 days, potatoes 11 in 5.8, corn 22 in 11.3 (`Plants_Cultivated_Farm.xml`). A hungry pawn with no meal eats from a bush itself. Fishing came with Odyssey (data only here, 1.6): water holds a population by its biome and size (`maxFishPopulation` 480 to 600, `Rimworld_Data/Odyssey/Defs/BiomeDefs/`), fish are 0.05 to 0.5 nutrition (`Items_Resource_Fish.xml`), and "larger ponds yield more fish per catch" (`TipSetDefs/Tips.xml`); it is marked as a zone on water (inference from its work type and stats).
- **Dwarf Fortress**: `GatherPlants` and `Fish` are jobs (`DF/df.job.xml:167,235`); plants are designated by dragging (`DesignateGatherPlants`, `DF/df.plotinfo.xml:131`) and there are zones for gathering and for fishing (`PlantGathering`, `FishingArea`, `DF/df.d_basics.xml:139,145`). A fisher fishes any water it can reach.

### What a player expects

- **Dwarves look after themselves.** Nobody is told to eat, drink or sleep. A thirsty dwarf walks to water; a hungry one to food; a tired one lies down, at night for choice.
- **Work waits, and the screen says why.** A pawn that left a wall to eat is "eating", and the wall's card does not say "waiting for a dwarf".
- **Food is a count at the top, with how long it lasts.** RimWorld's resource readout and Dwarf Fortress's "Food" and "Drink" figures are the first thing looked at each morning.
- **Gathering is a drag across the bushes**, and what would be taken shows before the button is let go. A bush with nothing on it is not marked.
- **Needs are words and bars on the pawn's card**, worst first, and a list of the colony sorts by them. "Hungry", "starving", "drowsy" are words a player learns in a minute.
- **Death is not sudden.** There is a stage with a name before it, an alert that stays, and time to act; and the death itself is a message nobody can miss, with the body left where it fell.
- **Time can be hurried**, and a night at the fastest speed is under a minute.

### For OdinCraft (as built, `plan.md`, "P4, first half, as built")

- **A day of 20 minutes and a year of 48 days.** RimWorld's day and a fifth: a dwarf here walks to a stream to drink and over pathless slopes to its work. The year is Ingnomia's, four seasons of twelve days, and takes 16 hours at the clock's own pace where RimWorld's takes 16.7.
- **Needs are rows** (`WANTS`, `src/needs.odin`): thirst falls two wholes a day, so a dwarf drinks about three times; hunger 1.2, two meals of two or three things; sleep 1.05 awake and mends 2.1 asleep, eight hours for sixteen. A dwarf sees to a need under about half when it has nothing in hand, and leaves its work for one under a fifth.
- **Death takes a day and a half of thirst after running dry and three days of hunger**: longer than RimWorld's 2.2, because the remedy here may be a walk and an order away, and the first of it is said when the need reaches nothing.
- **Gather and Fish are marks dragged like any order**, done once: a plant bears again next year, fished water holds fish again in four days. A hungry dwarf with no food lying anywhere marks the nearest for itself, as RimWorld's eats from a bush.
- **A plant's shoots are a tenth of a day, a shii's nuts a day and a third, an ayu two fifths of a day**: one drag of ten by ten on a wood's floor feeds a dwarf two or three days, where RimWorld's bush is a third of one.
