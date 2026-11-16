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
| N2 | Climate per island (old 25) | Running | Farming; the storm |
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
