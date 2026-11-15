# The fantasy world, and what it asks of the foundations

Tenth design, added after the owner said on 2026-11-11: "the end vision is a fantasy world grounded in realism, something in the same vein as lord of the rings." The world is original: no name, people, place or map is taken from Tolkien. Numbers are marked *(measured)*, *(sourced)* or *(guess)*.

## The vein, in one table

What makes such a world feel real and deep, and who can make it.

| Property | Source | Generator or author |
|---|---|---|
| A geography that comes before the story, kept consistent | Tolkien: "I wisely started with a map, and made the story fit (generally with meticulous care for distances)" (Letter 144, 1954, quoted in [Fonstad, *Tolkien Studies* 3](https://muse.jhu.edu/article/197457)) | Generator. This is what v5 already is. |
| The inner consistency of reality: the marvellous obeys the laws of its own world | "On Fairy-Stories" (1947): a Secondary World is one where what is told "accords with the laws of that world"; making one in which "the green sun will be credible" takes "labour and thought" (quoted from memory, not re-checked) | Generator, if the fantastic is a cause inside the same fields (decision 1) |
| Long journeys across lands that differ | About 2,860 km Shire to the Mountain over about 185 days, distances worked out from Fonstad's maps ([fan calculation](https://recoveringhopper.blogspot.com/2021/03/458-miles-to-rivendell.html)); Hobbiton to the southern city "600 miles south" (Letter 294, [Tolkien Gateway](https://www.tolkiengateway.net/wiki/Letter_294)) | Generator for the lands. The road between them is composed (decision 3). |
| The land reads as a real land | Fonstad's atlas closes with maps of landforms, climate and vegetation, and suggests geology for the formations ([Wikipedia](https://en.wikipedia.org/wiki/The_Atlas_of_Middle-earth)). The books survive being read as geography. | Generator: geology, climate and plant designs |
| Deep time, ruin over ruin | Watchtowers, barrows, old roads, the drowned West | Generator: a few ages written as features (decision 5) |
| Peoples shaped by their land | Peoples under stone, in forest, on the horse plains, by the sea | Generator places them; their manner needs authoring |
| Nature as a presence | Forests, mountains and rivers with a character and sometimes a will | Mostly the natural systems; a will is an influence |
| The marvellous is rare, placed and explained | Magic is seldom seen and has a cost. Le Guin's Earthsea runs on names and balance: "To light a candle is to cast a shadow" (*A Wizard of Earthsea*, from memory) | Generator with a rarity budget (decision 6) |
| Restraint, and quiet land between | Days of plain walking between the great places | Generator rule (section 4) |
| The map goes on past the edge | Tolkien's map covers only one corner of his world. Le Guin drew Earthsea's map, hundreds of islands, before she wrote ([Hyperallergic](https://hyperallergic.com/take-a-trip-through-ursula-k-le-guin-conjured-worlds)) | Generator: far lands that are real, but that the story never reaches |

Plot, meaning and languages need authorship; the rest can be generated if the foundations allow it.

## 1. What it gives the player

On foot: a long road through lands with their own rock, climate, forest and people; a mountain wall seen for hours before it is crossed at its one pass; and, rarely, a place where the natural rules bend for a reason that can be learned. Every great place is first a real landform, and its name, ruin and strangeness rest on it. Quiet country lies between. In the colony game, a people's hold sits where its kind of land is, in honest rock, among the ruins and the old influences of earlier ages, and those set the hold's dangers and its stories.

## 2. Questions it answers

| Provides | To |
|---|---|
| Feature **landmark**: archetype, prominence, name, the cause behind it | Inspection, names, settlements, the map |
| Feature **influence**: kind, source, reach, age, strength over time | Every natural system, as a change to the fields |
| Field **influence strength**: which influences reach a point, and how strongly | Climate, plants, animals, water, inspection |
| Feature **ruin** and the record of the **ages**: who built it, when, how it ended | Inspection, settlements, the underground |
| **Rarity budget**: the number of marvels per region | Everyone who places something rare |

What I need from each of the other nine:

- **World frame:** the seam between two regions can be a range crest or a drainage divide as well as the sea; a coarse world grid; sea level and climate that can vary with the age of the world; stable feature ids taken from the seed and the place, never from the order things are made in.
- **Geology:** strength, crack spacing and permeability at depth, so that halls, mines and delvings sit in honest rock; a way for an influence to change the rock (hollowed, glassed, stained); a volcano story as an option.
- **Landform processes:** fields for prominence, isolation and saddles (passes); a landslide record and a lake record, each with its cause and age; a set of land drowned when the sea rose.
- **Water:** a great river with known discharge and a falls where a hard bed crosses it; marsh and still water as features; a field for water quality that an influence can spoil.
- **Climate:** temperature, rain, cloud and light computed as a base plus terms an influence can add; a far cold north and a hot south on the world grid.
- **Vegetation:** plant community rules with an age axis and a size ceiling that an influence can lift (an elder wood) or kill (a blight); great trees with trunks three to five blocks thick.
- **Ground and underground:** structures far larger than the 256 m volume, with an outline that can be seen far off; underground halls with no height limit; worked stone as a kind of material.
- **Living world:** each people declares the land it is bound to as a rule over fields; history written as features carrying an age; animal ranges that can read the influence field.
- **Kinds, places and inspection:** every "why" walks a chain of causes, and a step in the chain can be fantastic; what inspection reveals can depend on what the player knows.

## 3. Foundational decisions

**1. The fantastic is a cause inside the same fields, never a separate layer.** *Recommendation:* an influence is a feature with a source (a point, a line or an area), a reach, an age and a short list of terms it adds to named fields. A fantastic kind (a blighted heath, an elder wood) is an ordinary kind whose host condition includes an influence. *Alternatives:* fantasy biomes from their own noise, or magic run over the finished world. *Why it is expensive later:* if fields are computed as closed formulas with constants inside them, every influence later needs a special case in every system. Allowing a "base plus terms" shape now costs nothing.

**2. Every feature records its cause and its age.** *Recommendation:* every feature carries a cause (a process, an event or another feature's id) and an age in years. Inspection walks that chain, and the fantastic is one more link in it. *Why it is expensive later:* a lake that does not know a landslide made it cannot later learn that the landslide came from the breaking of a delving.

**3. The world is composed at the scale of a journey.** Walking is 4.4 m/s, 3.8 minutes a kilometre; sprinting 7.5 m/s *(measured, `player.odin`)*. At true scale the books' 2,860 km road is 180 hours of walking. The fan estimate that LOTRO is about 40 times smaller than the books gives about 4.5 hours *(sourced, [Tobold](https://tobolds.blogspot.com/2007/04/how-big-is-middle-earth.html), weak)*. For comparison: Skyrim is about 37 km² and Kenshi about 870 km² *(sourced, secondary, [GamingBolt](https://gamingbolt.com/the-50-biggest-maps-in-video-games-of-all-time/50), [Steam](https://steamcommunity.com/app/233860/discussions/0/6929409304783194859))*. Daggerfall's roughly 161,600 km² is remembered as empty. A Dwarf Fortress world is 32 to 481 km across ([DF wiki](https://dwarffortresswiki.org/index.php/DF2014:World_gen)). *Recommendation:* keep 1 m blocks and true landform proportions. Compress distance by composition, not by shrinking the land. A realm is 20 to 60 km across. The long road between two realms is 40 to 120 km, or 3 to 8 hours on foot, less by road, boat or horse. The known lands are about 300 × 300 km inside the accepted 1,000 km world, and the rest is far lands that are real but rarely reached *(all guesses, to be judged by walking)*. *Alternatives:* fill all 1,000 km, or exaggerate heights. *Why it is expensive later:* realm sizes set the region size, the length of a pass and how far a range must be seen.

**4. Regions may be joined by land.** The vein needs a continent with a long road, a mountain wall and a great river. An archipelago (Earthsea) is honest and is in the vein, but it has no wall and no long road. *Recommendation:* keep the archipelago as stage 1, framed as the islands off a mainland whose range can be seen on their horizon. Require now that the seam between regions may be a crest or a divide, so the mainland can follow. *Alternative:* islands only, which makes an Earthsea world and gives up the long road. *What would change my mind:* if the world frame shows that land seams cannot be made seamless within budget.

**5. The world has ages, and sea level and climate are functions of the age.** *Recommendation:* three ages (elder, kingdoms, present) *(guess)*. Land forms under the sea level of the first age and is then partly drowned, giving rias, drowned valleys and drowned ruins. Each later age writes features: roads, holds, mines, borders, battlefields, influences. *Alternative:* a constant sea level, with history painted on afterwards. *Why it is expensive later:* drowned land must be formed above the water. `land.odin` taking its sea level as a parameter rather than a fixed 0 is the whole reservation.

**6. Rarity is chosen in a separate pass, from candidates nature found.** This is Dwarf Fortress's three layers (`dwarf-fortress-worldgen-research.md`, "where naturalism should yield"): the natural generator proposes, a playability pass chooses under a budget, and nothing is hidden inside the physics. *Recommendation:* a landmark finder ranks natural candidates for each archetype. A small selection pass promotes the top ones, at most one marvel per region, to named landmarks or influence sources. *Alternative:* chance per cell, which scatters marvels.

**7. Names derive from the feature, not from a list.** *Recommendation:* every named place gets a descriptive English name from its archetype and its most distinctive measured property ("the Grey Tooth", "Ninefold Falls"). Later, each people gets a name in its own sound pattern from small tables of syllables. *Why decide now:* names need stable ids (decision 2 and the world frame) and a "most distinctive property" for each feature, and both are cheap to keep from the start.

## 4. The kinds

Axes owned: **mythic archetype** (about 17 states), **influence kind** (7), **people-land bond** (6), **age of the world** (3). Two kinds differ when a walker on foot can tell them apart and each has its own host condition.

| | Today's island | Archipelago | Wide world | Benchmark |
|---|---|---|---|---|
| Archetypes found | 4 to 6 | 12 | 17 | RimWorld's 41 landmarks, none fantastic |
| Influence kinds | 0, reserved | 1 to 2 | 7 | DF's procedural evils: many, placed without cause |
| People-land bonds | 0 | 2 | 6 | DF's peoples weighted by biome (entity raws) |

### Mythic landmark archetypes

| Archetype | Natural cause the generator can find | What makes it mythic |
|---|---|---|
| Lone mountain | Highest isolation together with high prominence: a resistant plug or a remnant of a volcano | Seen from every quarter, a lair or a hold in it |
| Fire mountain in a ring of ranges | A volcano inside a caldera or an enclosed basin | A hidden plain, ash, a closed country |
| The gap in the wall | The lowest saddle on a range crest over a long run | The only road, guarded, ruined fortifications |
| Falls on the great river | A hard bed across a high-discharge reach | A portage, stairs cut in the rock, a border |
| Gorge or gate of stone | A river cutting a hard ridge | Statues, a gate, a toll |
| Ancient forest | The oldest plant age and the least disturbance, on a wet valley floor | Great trees, darkness, a people, an influence |
| Dead marsh | A wide, flat, poorly drained lowland | Old dead, will-o'-wisps, a battlefield beneath |
| Hidden valley | A deep enclosed valley reached by one narrow way | Refuge, a lost people |
| Tor or tooth on a ridge | A massive outcrop with wide cracks, high exposure | Watchtower ruin, beacon |
| Barrow downs | Rounded chalk or soft hills, open grass | Graves of the first age |
| Lake under a mountain | A landslide or moraine dam below a big catchment | A town on piles, a drowned old town |
| Great rock wall or scarp | A long scarp of a cap bed | A border, the edge of a realm |
| Sea stack, arch, headland | A crack or soft bed on an exposed coast | A lighthouse, the gate of the sea |
| Waste | Rain shadow and thin soil | Old ruin, mirage, nothing |
| Spring of a great river | A high spring or lake at the head of the largest drainage | Sacred, the source |
| Drowned land | Land under water of the elder sea level | Towers in the shallows, legends |
| Cave or delving door | A cliff in strong, unjointed rock | A door, a hold, a dark |

The finder ranks candidates by how extreme they are; only the most extreme in a region gets a name and a history. The rest stay ordinary ground.

### Influences

Each influence has a source, a reach, an age, a strength over time (rising, then fading), and terms it adds to fields.

| Influence | Source | Effects |
|---|---|---|
| Blight | A battlefield or an old fire | Plant community reset to dead and stunted, soil poisoned, water spoiled, animals absent |
| Elder wood | A grove that predates the age | Plant age and size ceilings lifted, light lowered, a will (paths shift) |
| Delving | A hollowed mountain | Rock hollowed, spoil heaps, springs diverted, the mountain hollow-sounding |
| Shadow | A tower or a pit | Light lowered, cloud cover raised, plants pale |
| Weather with a will | A peak | Storm and snow held over the peak beyond what climate gives |
| Hallowed ground | A spring or a stone | Water always clear, decay slowed, blight cannot cross it |
| The sunk land | A cataclysm | Sea level raised for one area, the coast drowned |

Inspection answers from the record, revealing only what the player knows: "These beeches are older and larger than any wood in this climate. Something older keeps them" until learned, then "the elder wood of X, source the grove at Y, 9,000 years". Natural causes are told at once. The fantastic is told by its signs, and its cause is learned later.

### People-land bonds

| Bond | Land it needs | Building in blocks | Marks on the land |
|---|---|---|---|
| Under stone | Massive strong rock with wide cracks and dry beds, ore | Carved halls, stairs, carved gates | Spoil, mine adits, roads to the gate |
| Old forest | Ancient forest, great trees, rivers | Timber platforms, very little stone | Nothing cleared. Paths. |
| Horse plain | Wide grassland in a rain shadow | Timber halls on mounds, earthworks | Dikes, burial mounds, horse tracks |
| Sea | Rias and drowned valleys, timber | Stone quays, towers, ships | Harbours, lighthouses |
| River and field | Floodplain, the great river | Brick and stone towns, bridges | Fields, roads, walls |
| Fen | Marsh and wetland | Stilt houses, causeways | Dikes, cut peat |

Their demands on the foundations: halls need honest rock. The largest built cavern open to the public, at Gjøvik in gneiss, spans about 61 m *(sourced from memory, unverified)*, so great halls belong in massive rock and widely spaced cracks, never in jointed or water-carrying beds. Great trees need trunks three to five blocks thick and heights of 60 m and more, beyond the real cool-temperate cast. A city or a hold spans 0.5 to 2 km, beyond the 256 m volume, so structures need far columns the way trees have them (`adr/0001`).

### Rules of restraint

1. At most one marvel (an influence source or a named great landmark) per region of 20 to 60 km.
2. Influences cover no more than 5% of the land in total *(guess)*.
3. At least two thirds of any long road crosses quiet land that is natural, inhabited or ruined, with nothing fantastic *(guess)*.
4. No fantastic kind exists without an influence host.
5. Singular creatures: at most a handful in the world, each named, each with a lair and a history.
6. No theme-park borders: an influence fades over its reach, by the same 10 to 50 m blending ragged edges that plant communities use.

## 5. How it works

- **World rung (kilometre cells):** compose the realms. Place the ranges with passes as the lowest saddles on a crest graph, the great river from the largest drainage, the cold north and the hot south. Write the ages as 50 to 200 events *(guess)*, not simulated centuries: Dwarf Fortress spends about 27 minutes on 1,000 years ([dev log 2022](https://www.bay12games.com/dwarves/), via the DF research note). Cost: under 10 s *(guess)*.
- **Region rung (16 m cells):** a landmark finder over the formed land. Prominence by union-find over cells sorted by height takes O(n log n), about 0.1 s for 262,000 cells *(guess)*. Isolation is the distance to higher ground. Saddles and falls come from the river and divide graphs. Influences are applied as field terms before plants and animals are decided.
- **Place rung (1 m blocks):** structures and ruins as designed pieces chosen by their context (people, age, rock), the method of `interesting-world.md` section 5. A ruin is a structure of the previous age with decay applied, by age and material.

## 6. Growth path

**Stage 0, on today's island:** a landmark finder in `land.odin`, about 80 lines. It computes prominence, isolation, the lowest saddles and the largest drops on the rivers, and ranks the top 4 to 6 archetype candidates. `--map` marks each one with its descriptive name. The owner looks at the map, then at each landmark with `--shot --above=` from 1 to 2 km away and asks: does it read as a place worth a name? Nothing fantastic yet. Also reserve the sea level as a parameter, and cause and age on features.

**Stage 1, the archipelago:** landmarks on every island, the elder sea level and drowned coasts, ruins of one earlier age, one or two people-land bonds. The first fantastic element arrives here, at the earliest after plant communities with ages and the tree grower exist (`interesting-world.md` steps 3 and 6): one elder wood on one island. It is the cheapest honest marvel, because it only lifts a ceiling on age and size in an existing community, and it can be inspected. The mainland range is seen on the horizon.

**Stage 2, the wide world:** realms, the long road, all the influences, languages.

**Not yet:** a magic system, a creature generator, a history simulation, languages, quests and narration, a catalogue of fantasy biomes. Each would be designed against nothing. *Triggers:* languages when the second people exists; creatures when the animal ranges exist; history when ruins of two ages are needed in one place.

## 7. Risks and known failures

- **Stamped marvels read as diagrams** (`lessons.md`): every marvel is found and has a host, never placed by chance.
- **Scale fixed before it was worth scaling:** stage 0 runs on the island, and realm sizes stay guesses until walked.
- **A plan heavier than the change:** stage 0 is 80 lines, and everything else here is reserved, not built.
- **Copying Middle-earth:** archetypes are generic landforms, influences are named by effect, names come from measured properties.
- **Too many marvels:** the rarity budget is a single pass that can be read and checked.

## 8. Decisions for the owner

1. **Mainland or archipelago as the end shape?** *Recommendation:* the archipelago first, framed as the coast of a mainland; a mainland later for the long road. *Decided by the owner on 2026-11-15:* one cohesive simulated world with continents and islands where the simulation makes them.
2. **How compressed are journeys?** *Recommendation:* the long road between two realms is 3 to 8 hours on foot, to be judged by walking.
3. **Does inspection tell the cause of a fantastic thing outright?** *Recommendation:* no. Signs first, and the cause once learned.
4. **How many ages?** *Recommendation:* three.
5. **The first marvel:** *Recommendation:* an elder wood, after the tree grower exists.
6. **Names in English or in invented tongues?** *Recommendation:* descriptive English first.

## 9. Not verified

The On Fairy-Stories and Earthsea quotations (from memory); the Gjøvik cavern span; the distances calculated from Fonstad, which are fan work; game sizes from secondary sources; the claim that LOTRO is 40 times smaller (one blog); the moon-phase care in the Letters (not checked, so not used); every realm size, budget and cost marked as a guess.
