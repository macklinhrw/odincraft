# The plan

Written 2026-11-16 by Claude, after the owner set the direction and answered its questions the same day (`open-decisions.md`, "2026-11-16, by the owner"). It replaces the order of work in `foundations.md` section 8 from here on, and the first proposal in `direction.md`. What is built stays described in `foundations.md`.

The research behind it is in `interesting-world/notes/df-rimworld-ideas.md`, with every source.

## 1. What the game is

A generated world with a past, in which the player founds and keeps a hold of dwarves, and which keeps what happened there. The natural world is the foundation: land, rock, water and living things formed from causes and judged against real land. On it a history of peoples runs, and the player's game is the next part of that history. A hold that falls stays in the world as a ruin, and the next game can walk into it.

Dwarf Fortress is the first source of the ideas and RimWorld the second. The content is our own: dwarves, humans and beasts are common fantasy stock, and no name, creature, text or picture is taken from either game or from anyone's setting.

## 2. Decided by the owner

1. The world is a story generator, and founding and keeping a place is the main game.
2. A thin thread of play comes first. **The natural world's generation is the foundation and must not lack effort or attention**: play is built in one worktree while the natural world carries on in its own thread.
3. History has particular people, and they are alive now.
4. The player's people are dwarves. Humans can exist. Enemies, fantastic creatures among them, are very important.
5. The party is led from above, and that is the primary camera. Controlling one dwarf by hand ("mind control") is a later feature. A first-person camera must exist.
6. No AI agents or narration now.
7. Dwarf Fortress is always the primary inspiration; RimWorld is the second.

Standing from before: the land's quality is never traded away; the whole world is generated within 10 minutes, staged if need be; the default island may change as much as a change needs.

## 3. What checking the first proposal changed

`direction.md` was written from memory and the project's earlier notes. Reading the makers' own words, and a survey of games that tried this on the ground, changed ten things.

1. **Play before the kept world and before history.** The proposal began with saving the world and a first people's history. Tarn Adams's first principle is "get something running as soon as you can and then work from there", and RimWorld first sold with no stockpiles, no animation and no traders who walk. So the thread now begins with dwarves the owner can order about, and each later step adds one thing to a game already being played.
2. **History runs on the coarse world.** Dwarf Fortress raises settlements, routes and wars on its world map, and makes a site in tiles only where the player goes *(the second half from memory)*. Ours runs on the known world's map, which exists, and forms a settlement in blocks only where it is seen. So history does not wait for continents to be formed as land, and it fits the 10 minutes and the staging the owner set.
3. **The underground moves to the front of the natural track.** Dwarves live in the rock. Today the rock has stories, faults and intrusions, and almost nothing to find: no ore to speak of, no water under the ground, few caves. That is now the natural track's next new work after what is running.
4. **The land is an actor.** Our land was formed by things happening for reasons: streams sized by their floods, a slope that slid, a dam that held or failed, vents with dates, weather through a year. In play the same rules can make events: a flood, a slide, an eruption, each with a cause the player can ask about. This is what the foundation gives the direction, and where we can go past both games, whose land is thin by comparison (`df-rimworld.md`).
5. **Trouble comes from the world, and a pacing rule says when.** In Dwarf Fortress trouble has a source in the world: a neighbour, a beast with a past. In RimWorld a storyteller keeps "a rising and falling pacing curve". We take both: who comes and why is the world's; when, among what the world makes possible, follows a pacing rule the player can choose.
6. **Few dwarves, known well, and nothing hidden.** "Anything in the Game Model that doesn't copy into the Player Model is worthless." A party of seven. Every dwarf can be asked what it is doing and why, as every rock can now. A new system works "at the level of what the player sees or one layer below".
7. **Stories are written first.** Bay 12 wrote stories and took the low-hanging fruit from them. Section 4 holds ours. A step is chosen because a story needs it, and its note says what can now happen.
8. **First person is a view of the hold, not yet a game of its own.** Dwarf Fortress's maker says its adventure mode has "never been good", because the player does not feel they changed the world. So first person is how the owner stands in their own halls and walks into a ruin. Being one person in the world gets its own design later, with mind control. Bay 12's own answer is to make finding things out the task, which suits a world where everything can be asked why.
9. **The simulation runs without a window.** The dwarves' world advances from a seed and a list of orders, with no window, the same every time. Agents may not open a window, and the stories in section 4 become tests.
10. **History is met as things.** Caves of Qud's makers wanted "players' engagement with history as an artifact": it sits on shrines and in relics that lead somewhere, and a journal keeps what was found. So our history is not a text beside the game. It is a grave, a carved lintel, a ruin, what a trader says, each pointing at a place, and the player's own hold goes into the same record.

Two things the proposal had right were confirmed: the ruin is where Dwarf Fortress began ("you'd bring an adventurer to find the ruins of this civilization"), and its persistent world comes from the wish to meet your last game in your next one.

## 4. The stories the plan is for

Six stories of the game as it should be able to go. They are ours, and each names what it needs.

1. **The first storm.** Seven dwarves land in autumn below a volcano and set their stores by the stream, where the ground is flat. The season's first typhoon raises the stream over its stony bed. One dwarf goes back for the seed and is not seen again. *Orders, needs, the year, weather that acts.*
2. **The hall under the cap.** They dig in under the lava cap, where the mudstone cuts easily and the cap holds the roof. Water comes through the sandstone bed. Where a dike crosses the beds they find the ore. *Rock that matters; the underground.*
3. **The ruin.** Years later another party lands on the same shore. The player walks into the old hall on foot: the fallen roof, the stores, the name of the drowned dwarf cut over the door. *The kept world; first person.*
4. **What slept in the crater.** The humans across the strait tell of a harbour burned two centuries ago. The miners break into a cave under the old vent. *History; a singular beast; caves.*
5. **The mason's wall.** A mason whose brother the stream took will not leave the sea wall she is raising against it. She works through hunger. She finishes a work the hold is named for, or dies at it. *Temper and memory.*
6. **The traders who did not come.** The hold the party left was besieged in the spring. No traders come in autumn. Three families arrive instead, with the news. *A world that goes on.*

## 5. The work, in two tracks

Each step is one change on one branch that the owner can look at, as before. The tracks run side by side and meet where the table says.

### The natural world (the foundation)

| # | Step | State | Play needs it for |
|---|---|---|---|
| N1 | Continents as land, with no seam, inside the 10 minutes (old step 21) | Running | Rivers of real size; peoples' homelands seen on foot |
| N2 | Climate per island (old 25): temperature by season, rain on the wind, six zones | Built | Farming; the storm |
| N3 | Ground and water by kind (old 27). River mouths, bay-head flats and reed marsh are built. Caves are left: a lava tube on a cone island, a solution cave in limestone | Half built | Harbours; lairs |
| N4 | **The underground.** Deposits placed by the rock's story (ore where a dike or pluton baked the beds, clay, coal, salt); water under the ground and where it comes out; caves that connect; heat under a volcano | New, next | Digging with a purpose; story 2 |
| N5 | Floras by climate (old 26) | After N2 | Timber, food, the look of a homeland |
| N6 | **The land acts in play.** Flood, slide, dam failure, eruption and storm as dated events during play, by the rules that formed the land | New | Stories 1 and 5 |
| N7 | The land's open questions (`open-decisions.md`): the crater and raised kinds, granite as gentle as Yakushima's, rain that grows with height, dry channels, vents on old centres | Open | The foundation's quality |
| N8 | The mainland and the known lands at full size (old Phase 3) | Later | The wide world |

### Play

| # | Step | The owner does | Story |
|---|---|---|---|
| P1 | **The view from above.** The primary camera: over the land, cut at a chosen level so the ground under trees and inside hills shows; a cursor on blocks; pause and speed. First person stays, a key away | Looks down on the default island and into a hillside | |
| P2 | **Seven dwarves.** Named, drawn simply, walking the block ground by a path they find. Any one can be asked who it is and what it is doing | Watches them come ashore and follow where they are sent | |
| P3 | **Orders.** Mark ground to dig, trees to fell, blocks to build. Dwarves take the work themselves. Goods go to a store without being carried at first, as RimWorld's first version did; carrying follows in P5, since Bellwright's makers found that work done in the abstract "didn't feel inspiring" | Has a first room dug and roofed | 2 |
| P4 | **Needs and the year.** Food, drink, sleep, shelter, warmth. Days and seasons pass. A dwarf can die. What each feels is shown | Gets through a first season, or does not | 1 |
| P5 | **Materials and making.** What the rock and the woods give is what can be built and made: stone by its kind, timber, clay, a first metal. Goods are carried and stored. A workshop | Builds from the island's own stone | 2 |
| P6 | **The world is kept.** A world is saved and reopened with what was dug and built. Leaving or losing a hold writes it into the world. A new party can land in the same world and walk into it | Finds the last game's hall | 3 |
| P7 | **Trouble.** Dangerous animals, then a hostile band, then one great beast with a lair. Fighting and wounds. The pacing rule | Loses a dwarf to something with a name | 4 |
| P8 | **Temper.** Each dwarf's nature, ties, grudges and memories of what happened, and what they do at the end of their rope | Watches a dwarf do something stubborn | 5 |
| P9 | **Peoples and their history.** On the known world's map: dwarven holds and human settlements placed by the land, a few centuries of particular people and events, kept abstract. It is met on the ground as graves, carvings and ruins that point at places, and gathered in a journal | Follows a carving to the place it tells of | 4, 6 |
| P10 | **Embark.** The world's map with what each site offers and lacks. The player chooses a home hold, a party and a site | Chooses a hard site on purpose | |
| P11 | **The world goes on.** Migrants, traders by season, news, and attacks from real neighbours, by the rules history ran on | Waits for traders | 6 |
| P12 | **Mind control.** Take one dwarf and act through it, in first person | Fights a beast by hand | |

After these, deepened by what the stories ask for: singular beasts and made things with histories, more peoples, trade and law, magic, being one person in the world.

### Where the tracks meet

- P5 reads the rock stories (built) and is deepened by N4.
- P4's farming reads N2. Until N2 lands, food is gathered and fished.
- P7's lair wants N3's caves.
- P9 reads the known world's map (built) and N2's climate at that scale. It does not wait for N1.
- N6 needs P4's passing time.

## 6. Rules

Carried over:

- The land is judged against real land, by its figures and by the owner looking. Nothing here lowers that bar.
- What is on an island is never a preference. Dwarves and humans follow it: a people is where it could reach, where the land keeps it, and where history put it.
- Rules are rows on named fields. A people, a need, a job, a kind of event and a material are rows.
- Everything can be asked why.
- One step per branch, merged with what changed for the player and how it was checked. The owner runs `./build.sh run` in `~/Programming/odincraft-v5` on `main`.
- Never open a window unless asked.

New:

- **Stories decide.** Where simulation and story pull apart, the story wins, as RimWorld's maker settles it. It never wins by making the land less real: a correction for play is a rule laid over the natural result, in the open.
- **Thin, then deeper.** A step ships the least that lets its story happen. Bay 12's warning is the rabbit hole: taverns became instruments, music, poetry and dance.
- **Play is judged by playing.** The owner plays each step. The benches still hold: no frame of our own work over 12.5 ms, with dwarves on screen.
- **The dwarves' world is deterministic**, as forming is: the same seed and orders give the same events, on a thread of its own, with or without a window.
- **Numbers stay behind words** where a word will do. "Numbers usually make for poor stories."

## 7. Risks

- **Play could starve the land, or the land play.** The owner named this. Each report covers both tracks.
- **Many walkers in a block world.** Dwarf Fortress's maker says they are "at the edge of what we can currently support in terms of agents and map complexity", on one thread, with a check that a path exists before searching for it. We begin with seven and measure before promising more.
- **A site is small beside an island.** The ground kept as true blocks is 256 m round the camera. A hold's ground has to stay real when the camera leaves. How large a site can be is measured in P3.
- **Drowning in complexity**, the genre's "characteristic design danger". The answer is rule 6 of section 3 and the stories.
- **The engine overshadowing the game.** Stonehearth's makers named "technical things" crowding out the game's systems, and their own engine, when it ended short of its goals. Bay 12's 3D predecessor "was floundering under its own weight". We have our own engine and a deep natural simulation. The play track exists so that the game is never the part that waits.
- **The view from above in real relief.** An island rises 500 m under forest. Dwarf Fortress cuts its world one level at a time. v4 built such a view; this engine has none.
- **History's cost.** Bay 12 once reported about 27 minutes for 1,000 years of a medium world. Ours is short and abstract first, measured against the 10 minutes.
- **The essay on what makes a story** (Adams, "Characterization and Emergent Narrative in Dwarf Fortress") was not read, only summarised second-hand. It should be read before P8.

## 8. Decisions ahead for the owner

None blocks P1. Each has a recommendation and is asked when its step is reached.

1. **How long a day and a year last in play** (P4). *Recommendation: a day of about 20 minutes at normal speed and a year of 48 days, with faster speeds.* It is a guess to be changed by playing.
2. **How tall a dwarf is in metre blocks** (P2), which sets how high a tunnel must be. *Recommendation: under one and a half blocks, so a tunnel two blocks high is roomy and one block high is a crawl.*
3. **Where the first hold stands** (P2). *Recommendation: the default island, until embark (P10) chooses.*
4. **What the first great beast is** (P7). The owner called fantastic creatures very important, so its nature is the owner's.

## 9. What became of the old plan

| Old | Now |
|---|---|
| Steps 21, 25, 27 | N1, N2, N3, unchanged and running |
| Step 26, floras | N5 |
| Step 29, people as ruins from a short pass | P9, with living people, and P6 for ruins the player makes |
| Step 30, the fantastic | P7 first, then deepened |
| Phase 3, the mainland | N8 |
| "What not to build yet": saves, seasons that advance, deposits, individual figures | P6, P4, N4, P9 |
| "First person" as the only view | P1 leads; first person stays |

## 10. Play, as built

What each play step built, what was tried and dropped, what it costs and where it is weak, as `foundations.md` section 8 does for the land.

### P1, as built: the view from above (2026-11-16)

**What can now happen that could not before:** the owner looks down on the island, cuts a hillside open at any level and reads its beds, marks a box of blocks in it, asks why, pauses the world, and walks into the same place on foot.

**What was built**

- **The camera** (`above.odin`). It looks down on a point of the ground and pans, turns, tilts and zooms about it, from 24 m across to 24 km: a hold's ground to the island whole and beyond. Tilted 50° at the start, through a lens of 30°, in perspective. The game starts in it, over the start, facing downstream.
- **The cut** (`adr/0007`). Nothing from the level up is drawn. Where it passes through solid blocks the cut face is the blocks' own material: soil at the rim, then the broken rock, then the beds, ruled block by block; a trunk shows its rings. The level moves a block or eight at a time, or holds 3 blocks over the ground under the view's middle as the view moves. What is cut away casts no shadow, and a room under a roof is lit as if open.
- **Leaves left out**: the ground under the whole wood, with the stems standing on it, at any scale.
- **The cursor**: the block under the pointer, picked through the cut, outlined; a box of blocks marked by dragging, tinted and outlined, and said in the terminal. `pick`, `pick_far` and `box_of` are what later steps mark ground through. Asking why prints the block and what `--why=` says of its ground.
- **The clock** (`adr/0008`, `clock.odin`): pause and three speeds, read by the water, the animals, the clouds' drift, the ripples and the wind in the plants.
- **First person a key away**: Tab puts the player at the place under the view's middle, on the cut where the world is cut there, and Tab again lifts the view from where the player stands.
- **Without a window**: `--over`, `--span`, `--tilt`, `--turn`, `--cut`, `--bare`, `--cursor`, `--why` and `--pace` with `--shot`, and `--bench` with `--over` (`AGENTS.md`).
- **For the interface** (I-1): the view's state is one record (`Above`), the clock another, and each key sets a field or calls a procedure a panel can call (`cut_set`, `cut_move`, `cut_follow`, `mark_begin`, `mark_end`, `mark_box`, `walk_down`, `walk_up`, `why_words`). `over_world` is the one place that says whether the pointer is over the world, and every click, drag and turn of the wheel asks it. It answers yes everywhere until panels exist.

**Keys.** From above: arrows pan (Shift faster), middle drag pans, right drag turns and tilts, Q E turn, Page Up and Page Down tilt, the wheel and = - zoom, R F raise and lower the cut (Shift by eight), C cuts or not, H holds the cut to the ground, V leaves, Space pauses, 1 2 3 set the speed, left click and drag mark. In either view: Tab changes view, P pauses, Y asks why, [ ] turn the hour, backslash saves a picture, Escape puts down a mark, then quits. First person is as it was.

**What was tried and dropped**

- **Straight down, a wide lens, and orthographic** (`interesting-world/real/above-camera-alternatives.jpg`, taken with an option for the lens that was then taken out; top row straight down, bottom row tilted 50°, lenses of 70°, 30° and 5° from the left). See `open-decisions.md`.
- **A hatched tone for the far cut.** At some scales the hatching beat against the pixels. It is plain.
- **The cloud's shade on the ground from above.** With no cloud drawn it read as stains on the land and the sea.
- **A wider block volume**, measured and not kept (below).
- **A marked box tinted strongly.** It hid the rock it marked.

**The cut beyond the block volume.** The far rings are columns with no inside. A column over the level is lowered to it and its top drawn in one plain dark tone; a canopy over the level gives way to the ground's own material. So at any scale everything above the level is gone, and the island cut at 150 m is the plan of its ground at 150 m (`above-island-cut.jpg`), but only the block volume shows what the ground is made of.

**How far the block volume has to reach.** At the usual tilt everything in the picture lies within 0.8 of its width from the middle (0.57 straight down, 1.16 at the lowest tilt). The volume reaches 256 m, so a hold's ground is shown cut in blocks, whole, while the picture is under about 320 m across. Measured on the forest flank, the cut following the ground, 200 m across, other agents loading the machine (8 to 13):

| Reach | Chunks | Blocks kept | Faces meshed | To a first picture | Our work, still | Panned at 120 m/s | Frames over 12.5 ms in 15 s |
|---|---|---|---|---|---|---|---|
| 256 m (kept) | 289 to 306 | 24 to 29 MB | 3.7 to 4.2 M | 2.0 s | 0.9 ms median | 1.7 ms median | 0 |
| 384 m | 625 to 650 | 56 to 67 MB | 8.1 to 8.7 M | 2.4 s | 1.2 ms | 4.5 ms | 28 |
| 448 m | 841 to 870 | 78 to 88 MB | 10.6 to 11.7 M | 2.8 s | 2.1 ms | 5.2 ms | 90 |

The water's window is 32 chunks wide, so 448 m is the widest that could be tried. The cost is the chunks coming in at the edge as the view moves, and it grows with the reach's length. A hold a kilometre across shown whole in blocks would need about nine times the chunks. So the reach stays, and a wide hold is seen in blocks only round the view's middle. How large a site can be kept real when the view leaves is P3's to measure.

**Costs**

- Moving the level remakes the caps: one pass over a layer of the volume, about 0.7 ms a frame while it moves every frame (median 1.5 ms of our work against 0.8 uncut), 2.8 ms at worst in a quiet run.
- Each nearest-level chunk keeps 18 KB more, 5 MB in all.
- From above about 230,000 faces are drawn a frame at a hold's scale, against 1.26 million in first person on the same ground: the picture is narrow.
- Benches, alternating with the parent, three times: twice with the machine's load at 8 to 12 from other agents, and once at 6.5 to 9. Our work in ms, median / 99% / worst, and frames over 12.5 ms:

| Bench | Parent | This step |
|---|---|---|
| Forest flank, first person | 1.25 / 4.6 / 16.0 (2), 1.19 / 3.7 / 6.1 (0); quieter 1.17 / 3.7 / 7.1 (0) | 1.26 / 4.1 / 15.3 (1), 1.13 / 4.4 / 10.3 (0); quieter 1.18 / 3.7 / 5.3 (0) |
| Down through cloud, first person | 1.29 / 3.9 / 6.4 (0), 1.03 / 4.4 / 12.3 (0); quieter 1.13 / 4.0 / 8.6 (0) | 1.36 / 4.3 / 12.4 (0), 1.21 / 5.1 / 16.1 (1); quieter 1.05 / 3.1 / 6.7 (0) |
| From above, cut following the ground | | 1.69 / 6.0 / 17.5 (5), 1.60 / 5.0 / 9.9 (0); quieter 1.64 / 4.4 / 12.3 (0) |

  Under the heavier load both builds lose a frame now and then; a timer round each part of the frame showed the late frames late in every part at once, the input handling among them, which is the machine and not the work. Of twelve runs of the new bench, eight had no frame over 12.5 ms; its worst frame in those ran from 5.3 to 12.3 ms, so it has less room than first person and should be run again on a quiet machine.
- The clock, over the bay head at 300 m across: paused, the world's clock ran 0.0 s in 10 and our work was 0.85 ms median, 1.8 at the 99th hundredth; at 4 times it ran 40.0 s in 10, at 0.78 median, 2.7 at the 99th, 7.4 worst.
- `odin check src -vet-unused` passes; `./build.sh test` passes with `GOLDEN` unchanged; the start island's map is the parent's byte for byte.

**Weak points**

- **The far cut shows no rock** (asked, `open-decisions.md`).
- **Ground within a tree's height under the level stands level with the cut beyond the volume**, a shelf up to 35 m wide on a 30° slope, since a canopy that is part of a column cannot be lifted off it.
- **A wood without leaves is a thicket of stems and limbs.** It reads, and it is not handsome. Stems cut to a stump everywhere would need each stem's foot.
- **Ground plants look thinner from above than on foot** (`above-bay-head.jpg` against `above-bay-head-on-foot.jpg`): each is two upright pictures, and from above the silt shows between them.
- **Seen from above for the first time:** the bay-head flats have straight sides and square corners at the scale of the land's 16 m cells, and where calm sea lies over a shelving flat the simulated water is drawn deep, with a straight edge at the chunk's side. Both are the natural track's and the water's, not this step's.
- **The view's middle follows the generated ground**, not what has been dug or built there.
- **Why prints in the terminal** until the interface has a hand to show it in.
- **Pause and speed are checked by the bench's count of the world's time** (`--pace`), not by looking: a picture's animals are posed from `--after`, and nobody has watched the world stop.
- **The window was never opened**: no key or mouse path has been tried by hand. The owner's first minutes will find what is wrong with them.

**For the interface's design** (`foundations/interface.md`)

- **The middle the view needs clear.** The view turns, tilts and zooms about the picture's exact middle; the cut follows the ground there and the walk lands there. A small mark stands on it. It needs the middle third of the width and the middle half of the height clear, which the four regions leave. A list a third of the screen wide leaves the middle visible but off the centre of what is left of the world; if that feels wrong in play, the view's middle should move to the middle of the uncovered world, which is one offset in `above_camera`.
- **The tilt puts distance at the top.** The far ground is under the top strip and the alerts, the near ground under the orders bar. Nothing the player marks is likely to be at the very top; the alerts cover the least useful corner.
- **The level in the design reads "+31 m".** The level here is a height over the sea, and can hold to the ground; the panel can show either, and wants a third control beside up and down: hold to the ground.
- **Leaves left out is a lens** in the design's sense, how the world is seen, and belongs under L with the fields.
- **D and S are orders**, so the pan is not under the left hand (asked, `open-decisions.md`).
- **A drag that leaves the world**: a box being marked keeps its last block while the pointer is off the world, and ends where the button is let go.
