# The direction: a world that makes stories, after Dwarf Fortress

Written 2026-11-16 by Claude, on the owner's instruction of the same day: "we need to revise our plan from the ground up to fit the direction dwarf fortress goes in- look not necesarilly into the mechanics it uses to simulate its histories but the ideas that drive it and the gameplay it is used to drive".

**Superseded by `plan.md`**, written the same day after the owner answered section 6 and the sources were read. Kept as the record of the first proposal: its order of work and what is marked *(memory)* are not to be relied on.

This was a **proposal** until the owner decided section 6. It replaces the order of work in `foundations.md` section 8 from Phase 2's unbuilt steps on. Nothing built is thrown away.

Sources: `reference/zigcraft/dwarf-fortress-worldgen-research.md` and `interesting-world/notes/df-rimworld.md`, which cite Bay 12's own logs, DF Talk and the raws. What is marked *(memory)* is Claude's recollection of Tarn Adams's talks and interviews, not checked for this note.

## 1. The ideas that drive Dwarf Fortress

1. **The game is a story generator.** The Adams brothers wrote short stories of what they wanted the game to tell and asked what the game would need for such a story to happen in it *(memory)*. A system earns its place by the stories it lets happen, not by its realism or its feature count.
2. **The world has a past, and play joins it.** World generation makes geography, then peoples, then centuries of history. The player's game is the next chapter of that history, in the same record, by the same rules. Since 2014, births, deaths, successions, invasions and site foundings go on after play begins (Bay 12 log, via the research note). Prehistory and play are one thing.
3. **One world, many games.** A fortress, an adventurer and a reader of legends all meet the same places, people and consequences. A fortress that falls stays in the world as a ruin, and a later game can walk into it. The world outlives every game played in it (Bay 12's feature page, via the research note).
4. **Things are particular.** A person has a name, a body, a temperament, kin, grudges and a past. A sword has a maker, a material and a list of who it killed. An event says who, where, when and why. Stories come out because consequences pass through particular things, not through totals *(memory, and the legends record described in the research note)*.
5. **Geography comes before society.** A people settles where its land suits it, and what the land holds (stone, metal, soil, water, beasts) shapes what that people makes, trades and fights over. Tarn Adams called it a kind of geographical determinism (DF Talk, via the research note).
6. **The world refers to itself.** Engravings show events that happened, songs name the dead, a beast is known by the towns it burned. History is not a document beside the game: it is in the game's objects and people's talk *(memory)*.
7. **Rare things are singular.** Ordinary animals and plants are authored rows. Great beasts, artifacts and the dark things under the earth are made one at a time, each with its own form and its own history (the research note, "Procedural exceptional creatures").
8. **There is no winning.** The player sets the aim. A fortress ends, and how it ended is the story: "losing is fun" *(memory)*. Failure is content the world keeps.
9. **Choice with knowledge, then discovery.** Before embarking the player sees what a site offers and lacks, and chooses a hardship. After, the ground still holds what no survey showed (the research note, "Embark-site information and discovery").
10. **Realism yields to play where it must, and openly.** Scarcity is tuned so that a lack is a choice, never a dead seed. Crowns are drawn apart so trees read. The correction is made as policy on top of the natural result, never hidden in it (the research note, "where naturalism should yield").

## 2. The gameplay those ideas drive

- **Reading the world** (legends, the world map, the embark screen): a game in itself, and the way into the other two.
- **Founding and keeping a place** (fortress mode): a handful of named people with needs and tempers, set down at a chosen site, who dig, build, farm, craft, trade and defend. The land is material. The deep is a frontier whose reward and danger grow together. The world sends migrants, caravans, sieges and beasts, each from somewhere in particular.
- **Being one person in it** (adventure mode): walking the same world, meeting its people, finding its ruins, some of them the player's own.
- In all three the player is told why: everything can be looked at and asked about.

## 3. What this means for OdinCraft

**What already fits, and stays:**

| OdinCraft has | It is Dwarf Fortress's |
|---|---|
| Rules as rows on named fields; kinds as data | Raws |
| Features that carry a cause and an age; `--why` | The event record; inspection |
| One world from a seed; plates, then islands read from the history | Geography first; one world truth |
| Who reached which island, with the reason printed | Populations with ranges and causes |
| Rock stories, materials with traits | Layer stones and their properties |
| First person in a block volume that can be dug | Adventure mode's view of a fortress's ground |
| Named places from causes; the survey | The embark screen's facts |

The natural world is where OdinCraft goes past Dwarf Fortress, whose surface landforms are thin by its makers' own account (`df-rimworld.md`). The owner's rule holds: quality is never traded away. The land stays the stage, judged against real land.

**What is missing, and is the other half of the game:**

- No people, no history, nobody to be or to lead.
- No persistence: a world is formed each run and nothing play does is kept. Nothing is saved.
- Time stands still in play.
- The ground can be dug, but digging has no purpose: no materials that matter, nothing to make.
- No aim the player can set, and nothing to lose.

**What the old plan had wrong for this direction:**

- **It finished nature before starting anything else.** Phases 1 to 3 run island, archipelago, mainland, with the colony game "later". `lessons.md` records that every earlier attempt built the ground under the player last. This plan built *play* last. Dwarf Fortress grew the other way: every system thin, joined end to end, then deepened *(memory)*.
- **History as "a short pass that writes dated facts", ruins only, nobody alive** (step 29, `living-world.md` decision 4). That gives scenery. A story generator needs particular people who did particular things and whose heirs are still there.
- **"A history simulation, individual figures" deferred** until a second people; **deposits** until "digging has a purpose"; **advancing seasons** until a year length; **saves** until noticed. Each trigger is now pulled.

## 4. The revised plan

Three phases, ordered by the story loop rather than by the size of the land. Each step is still one change the owner can look at, one branch, judged by looking.

### Phase A: one thread through the whole loop (thin)

On today's archipelago, with what exists. The aim is the smallest world that has a past the player can read, join, change and leave a mark in.

| # | Change | The owner looks at |
|---|---|---|
| A1 | **The world is kept.** A world is made once, saved, and reopened; play's changes (dug blocks, the date) are stored on top of it. One event list for the world, natural and human, appended to and never rewritten | The same world twice; a hole still dug |
| A2 | **Time passes.** Days and seasons advance in play at a chosen year length | A week on the island |
| A3 | **A first people and their history.** One people arrives from the continent by boat, settles islands by what the land offers, and lives through a few centuries: named settlements, named heads of households, births and deaths, a few kinds of event the land causes (a slide, a harbour silting, a failed harvest, a feud, a move). Still inhabited at the end. Written to the event list | `--legends`: the history as text; a hamlet and its fields; an older ruin with its reason |
| A4 | **Materials that matter.** Stone, wood, clay, soil and one metal as resources with a use, placed by the rock stories and the plants. What a settlement is built of is what lies under it | A wall of the local stone; `--why` on an ore |
| A5 | **Embark.** A map of the known world with what each site offers and lacks; the player chooses a site and a small party of named people from a settlement | The map; arriving |
| A6 | **Keeping a place.** The party digs, fells, builds and stores, with a view from above beside first person. People have a few needs (food, water, shelter, rest) | A first shelter, a first winter |
| A7 | **Leaving a mark.** Abandoning or losing the place writes it into the world: its events in the list, its ruin on the ground, its name on the map. A new game in the same world can walk into it | The ruin of the last game |

### Phase B: the world deepens

The natural steps in flight land here, each now serving the loop.

| # | Change | Serves |
|---|---|---|
| B1 | Continents as land (old step 21, running) | Where peoples come from and spread; rivers of real size; the 10-minute world |
| B2 | Climate, floras, ground and water by kind (old 25 to 27; 25 and 27 running) | Where farming works, what grows, harbours, marsh, caves |
| B3 | The underground as a frontier: deposits by geology, water under the ground, caves, depth that raises both reward and danger | Digging with a purpose |
| B4 | People are particular: temperament, kin, skills, memories of events; they talk about what happened | Stories |
| B5 | The world keeps going during play: migrants, traders, quarrels and beasts arrive from places in particular, by the rules history ran on | The world as an actor |
| B6 | Animals as populations that can be hunted, herded and feared | Food, danger |
| B7 | The world refers to itself: marks, carvings, names and tales made from the event list | History met on the ground |

### Phase C: the wide world and the fantastic

- More peoples, each shaped by its land; trade, war and borders between them.
- The singular: great beasts, made things with histories, marvels, each one of a kind (old step 30, as history rather than scenery).
- The mainland and the known lands at full size (old Phase 3).
- Being one person: travel, talk, and deeds the world records.

### What happens to the old steps

| Old step | Now |
|---|---|
| 21, 25, 27 (running) | Carry on unchanged; they are B1 and B2 |
| 26 floras | B2 |
| 29 people as ruins from a short pass | Replaced by A3 and B4 |
| 30 the fantastic | Phase C, as singular things with histories |
| Phase 3 the mainland | Phase C |
| "What not to build yet": saves, advancing seasons, deposits, individual figures | Pulled forward: A1, A2, A4, A3 |

## 5. Rules carried over, and one added

- The land's quality is never traded for speed or scope. The whole world is generated within 10 minutes, staged if need be (the owner, 2026-11-16). History runs inside that budget: Bay 12 once reported about 27 minutes for 1,000 years of a medium world (the research note), so ours is abstract where nobody is looking and particular where the player will be.
- What is on an island is never a preference. People follow it too: they are where they could reach, where the land keeps them, and where the history put them.
- Rules are rows. A people, a kind of settlement, a kind of event and a material are rows.
- **Added: a system is judged by the stories it lets happen.** Each step's note says one thing that can now happen in the world that could not before.
- The world is original. Nothing is taken from Dwarf Fortress's or anyone's setting: the ideas, not the content.

## 6. Decisions for the owner

1. **Is this the direction: the world as a story generator, with founding and keeping a place as the main game, and first person as the way to be in it?** *Recommendation: yes*, as section 4 orders it.
2. **Thin thread first (Phase A), with the natural steps continuing beside it?** The other way is to finish continents, climate and floras first and start people after. *Recommendation: thin thread first.* There is still nothing to do in the world but walk it, and every earlier attempt deferred play.
3. **History with particular people, alive now.** This reverses "ruins first, nobody living" and "a short pass, not a simulation". *Recommendation: particular households and settlements over a few centuries, abstract elsewhere, still inhabited.*
4. **Who are the player's people?** The earlier notes hold dwarf concepts; the world is to be original. *Recommendation: one human-like people first, named and shaped by the islands; other peoples in Phase C.* It is the owner's to choose.
5. **Does the player lead a party from above, or act as one person among them, first?** *Recommendation: both views over one party from the start (A6), since first person exists and the view from above was built in v4.*
6. **AI agents and narration** (the first note, 2024). *Recommendation: not now. Dwarf Fortress's stories come from the simulation; a narrator could later read the event list.*
