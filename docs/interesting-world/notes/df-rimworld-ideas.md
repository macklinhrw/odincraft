# The ideas that drive Dwarf Fortress and RimWorld, and the play they drive

Research notes for OdinCraft v5, 2026-11-16, for the plan in `../../plan.md`. The owner set the direction that day: Dwarf Fortress first, RimWorld second, "not necesarilly ... the mechanics it uses to simulate its histories but the ideas that drive it and the gameplay it is used to drive".

It complements two earlier notes and repeats neither: `df-rimworld.md` (what each game's sites hold, from the raws and defs) and `reference/zigcraft/dwarf-fortress-worldgen-research.md` (Dwarf Fortress's world generation pipeline).

Every claim has its source. *(Memory)* marks what Claude recalls and did not check. Quotations are short, and each was checked against the page's own text unless it says otherwise. Section 5 is from a research agent's survey, checked by Claude where it says so.

## Key takeaways

1. **Both games call themselves story generators, and their makers decide by that.** Bay 12 writes stories first and asks what would let them happen. Tynan Sylvester settles "every design conflict between 'game' and 'story generator' directions in favour of the latter".
2. **Dwarf Fortress began as a way to leave a ruin.** A colony that dies, and then an adventurer who walks into what is left. Its persistent world comes from Hack's bones files: your last game is in your next one.
3. **Adams's own four principles: do not overplan; break the system into its elements; do not overcomplicate; base it on real-world analogs.** "Get something running as soon as you can." "Operate at the level of what the player sees or one layer below."
4. **Stories need three things together: description, mechanics and the player's hand.** A detail with no mechanical tie made no stories.
5. **The player is "the official will of the fort". The dwarves own their lives.** Autonomy is where the stories come from.
6. **A simulation is worth what the player can see of it.** "Anything in the Game Model that doesn't copy into the Player Model is worthless." The characteristic danger is "drowning in your own complexity".
7. **Loss is the story.** "Losing is fun" began as a line in the manual. Sylvester: "losing things is good story".
8. **You care about few people known well.** A colony sim lets the player watch named people for a long time.
9. **Where they differ.** Dwarf Fortress simulates a world and lets trouble come from it. RimWorld has a thin world and a storyteller that paces trouble. Dwarf Fortress is deep and hard to read; RimWorld is shallow by choice and easy to read.
10. **First release was thin.** RimWorld sold in 2013 with no character animation, no stockpiles and no traders who walk. Dwarf Fortress's adventure mode shipped in 2006 and, by its maker, "has never been good".
11. **History is felt when it is met as a thing.** Caves of Qud puts its history on shrines and in relics that lead somewhere, with a journal. The player's own deeds go into the same record.
12. **From the ground, orders become menus.** Games that keep the player on foot manage their people through tabs and placed blocks. The view from above exists "because the player is required to build things".

## 1. What Bay 12 says drives Dwarf Fortress

- **The goal.** "The long-term goal is to create a fantasy world simulator in which it is possible to take part in a rich history" ([Bay 12 development page](https://bay12games.com/dwarves/dev.html)).
- **Stories first.** The brothers wrote stories of things they would like to have happen in the game's world, a chapter each in turn: "Then we'd look over it and decide on some low-hanging fruit". The method is to "create actors with motivations, and let them go" ([Gamasutra, "The Making of Dwarf Fortress", 2008](https://gamedeveloper.com/design/interview-the-making-of-dwarf-fortress)). Eleven years on an interviewer put it to Tarn Adams that Zach Adams ("Threetoe") "writes stories that you then try to create a game engine in which they could occur" ([Gamasutra Q&A, 2019](https://www.gamedeveloper.com/design/q-a-dissecting-the-development-of-i-dwarf-fortress-i-with-creator-tarn-adams)). Narrative leads realism: "our own feel of how the game should do narratives or how the game should play overall that's gonna drive the considerations, more than just realism" ([PC Gamer, 2016, page 3](https://www.pcgamer.com/dwarf-fortress-creator-on-how-hes-42-towards-simulating-existence/3/)).
- **The first idea was the ruin.** "You'd make a dwarf colony ... and then they die in some spectacular fashion ... and then you'd bring an adventurer to find the ruins of this civilization." The fortress set the highest score possible and the adventurer earned it ([PC Gamer, 2016, page 2](https://www.pcgamer.com/dwarf-fortress-creator-on-how-hes-42-towards-simulating-existence/2/)). The adventurer would "come into the fortress after you lose and find the goblets you've made" ([Gamasutra, 2008](https://gamedeveloper.com/design/interview-the-making-of-dwarf-fortress)).
- **Persistence comes from Hack.** Of Hack's bones files: "you die and then you have in your subsequent playthrough, something about your previous character, more than a score ... You can trace that directly to Dwarf Fortress persistent worlds" ([PC Gamer, 2016, page 3](https://www.pcgamer.com/dwarf-fortress-creator-on-how-hes-42-towards-simulating-existence/3/)).
- **Play the world.** Adams wants players to think of "playing the world, not the fortress"; "Losing is fun!" was a throwaway line in the manual, kept because "reloading every time you fail will really hamstring you" ([Gamasutra, 2008](https://gamedeveloper.com/design/interview-the-making-of-dwarf-fortress)).
- **World generation is a canvas for history.** Fields first (elevation, temperature, rainfall, drainage), from which biomes "arise"; then regions, names and populations, which "gives you a canvas for world history" (the same interview). Then "the simulation of civilization begins ... settlements are raised, trade routes are formed, and wars are waged. At a designated point in time, the simulation stops and the player begins the game in a unique living world" ([Adams, *Game AI Pro 2*, chapter 41, 2015](http://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter41_Simulation_Principles_from_Dwarf_Fortress.pdf), read in full).
- **The four principles** (the same chapter, its headings):
  1. "Don't Overplan Your Model": "get something running as soon as you can and then work from there"; "build it up through iteration".
  2. "Break Down and Understand the System": handle the fields separately and let their interplay decide, and "certain problems solve themselves".
  3. "Don't Overcomplicate": "Operate at the level of what the player sees or one layer below. Don't get carried away and create a lot of worthless noise."
  4. "Base Your Model on Real-World Analogs": rain shadows and drainage fixed the maps. "We know the real world works."
- **Who the player is.** "It's important at some point to have a conception of what the player 'is'. For us, it's the 'official will of the fort' ... while the dwarves are in control of their own lives, and can even decide to disobey orders in extreme cases" ([PC Gamer, the colony sim](https://www.pcgamer.com/games/strategy/the-challenges-of-developing-the-colony-sim-from-dungeon-keeper-to-dwarf-fortress-and-beyond/)). Autonomy "allows them to be actors in their own stories, which is a large part of where emergent narrative comes from" ([Gamasutra Q&A, 2019](https://www.gamedeveloper.com/design/q-a-dissecting-the-development-of-i-dwarf-fortress-i-with-creator-tarn-adams)).
- **Why a colony.** "You watch more named non-player creatures interacting with each other over a longer period of time in a colony sim ... It gives you a chance to really get to know the characters" (PC Gamer, the colony sim).
- **Why dwarves.** They are "more human than human": "They're allowed to embody bigger emotions. They're allowed to make bigger mistakes. They're allowed to be stubborn." The community's word is "dwarfy" ([PC Gamer, GDC 2025](https://www.pcgamer.com/games/sim/dwarf-fortress-dwarves-are-more-human-than-human-creator-says-theyre-allowed-to-embody-bigger-emotions-theyre-allowed-to-make-bigger-mistakes-theyre-allowed-to-do-anything)).
- **What makes a story.** Adams's essay "Characterization and Emergent Narrative in Dwarf Fortress" argues that description, mechanics and the player's agency together make emergent narrative, and that flavour with no mechanical tie, such as a habit of tapping a foot, made none. *Claude did not get the essay's text; this is a search engine's summary of it.*
- **Numbers make poor stories.** "Being as anti-numeric as possible is ideal, since numbers usually make for poor stories" ([Gamasutra Q&A, 2019](https://www.gamedeveloper.com/design/q-a-dissecting-the-development-of-i-dwarf-fortress-i-with-creator-tarn-adams)).
- **Its makers' own verdicts.**
  - Adventure mode: "It's never been good", because "you don't feel like you're inhabiting a person with an overarching life path or quest path", nor that "you've changed the world" (PC Gamer, 2016, page 2).
  - Motives: "Character motivations and goal-setting ... continue to lag far behind what they do in stories" (Gamasutra Q&A, 2019).
  - A system that failed: a quartermaster dwarf was "too slow and fiddly and prone to confusion" (the same).
  - Limits: "We are certainly at the edge of what we can currently support in terms of agents and map complexity"; pathfinding is A* with connected components, so a dwarf knows before searching whether a path exists; the game uses one thread ([Stack Overflow blog, 2021](https://stackoverflow.blog/2021/07/28/700000-lines-of-code-20-years-and-one-developer-how-dwarf-fortress-is-built/)).
  - Rabbit holes: taverns led to instruments, then music, then poetic forms and dances (PC Gamer, the colony sim).

## 2. What Ludeon says drives RimWorld

- **A story generator, by decision.** "RimWorld is designed at every level to generate story ... I deliberately decide every design conflict between 'game' and 'story generator' directions in favour of the latter" (Sylvester, in PC Gamer, the colony sim).
- **It came from Dwarf Fortress's stories.** "Dwarf Fortress amazed me because of the stories people wrote from it ... I wanted to push that even further - and to do it in a way that's approachable" ([Gamasutra, "How RimWorld fleshes out the Dwarf Fortress formula"](https://www.gamedeveloper.com/design/how-i-rimworld-i-fleshes-out-the-i-dwarf-fortress-i-formula)).
- **The player's model is all that counts.** "The whole value of a game is in the mental model of itself it projects into the player's mind", so "anything in the Game Model that doesn't copy into the Player Model is worthless". Ultima Online's ecology and others were never noticed ([Sylvester, "The Simulation Dream", 2013](https://www.gamedeveloper.com/design/the-simulation-dream)).
- **The player's mind does the telling.** People read intent into simple events (apophenia), so the simulation is "a co-author of stories with the player". On whether the game should tell its stories: "my approach to that on RimWorld is just to not do it", because the player "can unconsciously do that better than the game" ([GDC 2017 talk](https://gdcvault.com/play/1024686/-RimWorld-Contrarian-Ridiculous-and), from a transcript).
- **Choose the least that carries the story.** Story-richness is "the percentage of interactions in a game that are interesting to the player". Keep human values at stake (life and death, together and alone, wealth and want), not logistics. Cheap flavour that feeds nothing back ("hair complexity") is allowed because it costs little ("The Simulation Dream").
- **Success is not assumed.** "Stories can end in success or failure and still be great stories." "Losing things is good story. Losing things is emotional, it's powerful, it sets up the stakes for later on." You care "because you've gotten to know them" (GDC 2017 talk).
- **A story is events, not pictures.** "The story is not a sequence of images, it's a sequence of events", so characters need not be detailed or realistic (the same talk).
- **Trouble is paced.** The storyteller "attempts to match a rising and falling pacing curve, and not to over-brutally murder struggling players", though "in extreme challenge lies the greatest drama" (PC Gamer, the colony sim). The player chooses the storyteller.
- **The first version was thin.** It sold in 2013 without character animation, without stockpiles (hauled goods vanished into a store) and without traders who walk in (GDC 2017 talk).
- **The danger.** "The characteristic design danger in this genre is drowning in your own complexity" (PC Gamer, the colony sim).
- **Its frame, as critics read it.** A site chosen in a made world, three people with fixed traits and pasts, half-control (the player sets work and priority; mood, wounds and temper decide what happens), and events whose consequences last and chain ([Gamasutra, "RimWorld, Dwarf Fortress, and procedurally generated story telling"](https://www.gamedeveloper.com/design/rimworld-dwarf-fortress-and-procedurally-generated-story-telling)).

## 3. What research on emergent narrative adds

- **Why these stories please** (James Ryan, *Curating Simulated Storyworlds*, 2018, as reviewed by [Emily Short](https://emshort.blog/2019/05/21/curating-simulated-storyworlds-james-ryan/)): they "actually happen"; they are the player's own; they are uncovered by looking; the improbable stands out; the world is vast.
- **Raw events are not a story.** A simulation's trace "will almost always lack story structure", so someone has to pick the story out. Ryan calls it story sifting. Dwarf Fortress counts as good because players retell it.
- **The two makers disagree with each other here.** Sylvester leaves the telling to the player's mind. Dwarf Fortress keeps every event in legends and leaves the sifting to the player. Neither narrates.

## 4. The play these ideas drive

*(Memory, for Dwarf Fortress's and RimWorld's particulars; the sources above for the frame.)*

| | Dwarf Fortress | RimWorld |
|---|---|---|
| Start | Choose a site on the world map knowing its rock, water, trees and neighbours; seven dwarves and a wagon | Choose a site; three people with traits and pasts |
| Orders | Designations (dig, fell, build), work assigned, stockpiles; dwarves choose their jobs | Work priorities and direct orders in a fight |
| What people are | Needs, temper, likes, kin, skills, memories, wounds by body part | Needs, mood, traits, relationships, health by body part |
| Trouble | From the world: sieges by a real neighbour, great beasts with pasts, things in the deep, the fort's own tempers | From the storyteller: raids, weather, sickness, breakdowns, paced |
| Growth | Migrants, caravans by season, nobles and their demands | Recruits, traders, quests on the world map |
| The ground | Dug into: layers, ore, water under the ground, caverns, magma, deeper and worse | A flat map; mountains to dig into |
| The end | The fort falls or is left; it stays in the world; another game can find it | The colony falls or leaves; the world is not kept between games |
| Reading it | Legends, the embark screen, every thing can be looked at | The log, the history graph, tooltips everywhere |

## 5. First person, three dimensions, and history met in play

From a research agent's survey of 2026-11-16, which fetched each page. Claude checked nine of its quotations against their pages and found eight; the rest are as the agent reported them. What it could not verify is left out.

**Being one person in the world**

- Dwarf Fortress's adventure mode, by its maker in 2017: "The Adventure mode isn't even a good game." "There's no real feel of a game loop at all." "You never quite feel like you've changed the world" ([PC Gamer](https://www.pcgamer.com/the-creator-of-dwarf-fortress-doesnt-really-like-to-play-games-like-dwarf-fortress/)). Bay 12's answer since: "The concept of investigation is kind of central to what we want to do with Adventure mode" ([PC Gamer, 2023](https://www.pcgamer.com/dwarf-fortress-devs-on-big-adventure-mode-plans-this-is-just-gonna-blow-everyones-mind/)).
- Kenshi, a squad and a base seen from above: "You are not the chosen one" ([its store page](https://store.steampowered.com/app/233860/Kenshi/)).

**Giving orders from the ground**

- Games that keep the player on the ground give orders through menus or placed blocks. Medieval Dynasty: "It's great that I can see and manage my village from a management tab, but it's obtuse" ([a review](https://gamingtrend.com/reviews/medieval-dynasty-review-a-tale-of-many-buckets/)). MineColonies queues work in each hut's screen ([its guide](https://minecolonies.com/wiki/tutorials/getting-started/)).
- Shadows of Doubt's maker: overhead cameras exist "because the player is required to build things" ([Cole Jefferies](https://colepowered.com/?p=34010)).
- Bellwright keeps the player on the ground as a leader among followers: "you are never looking at things from a top-down perspective". Its villagers do each action step by step, because production done in the abstract "worked, but it didn't feel inspiring". Over 1,000 people are simulated out of sight, and the cost was memory ([80 Level](https://80.lv/articles/how-bellwright-simulates-a-living-medieval-world-with-thousands-of-npcs)).

**History met in play**

- Caves of Qud generates five sultans' lives and puts them on shrines, paintings, engravings and in people's talk, met in any order, with a journal that gathers them. The history also places sites and named relics: "historical knowledge acts as a vector for players to find and engage with the material remnants". "We were primarily interested in players' engagement with history as an artifact" ([Grinblat and Bucklew, 2017](https://pcgworkshop.com/archive/grinblat2017subverting.pdf)).
- Shadows of Doubt gives every citizen a job, a home and a routine, and they matter because they are the evidence the player searches ([Jefferies, 2018](https://colepowered.com/?p=34142)).
- So history is felt when it sits in a thing, a place or a person; when it leads somewhere; when a journal keeps what was found; and when the player's own deeds go into the same record.

**What went wrong for others**

- Paths on ground that changes: Dwarf Fortress found higher structures "take too long to maintain" and tracks connected walkable ground to "cut almost all failed A* calls" ([Stack Overflow blog](https://stackoverflow.blog/2021/12/31/700000-lines-of-code-20-years-and-one-developer-how-dwarf-fortress-is-built/)). Shadows of Doubt plans each citizen's day ahead: "I've chosen not to handle it in real-time".
- Scope: Bay 12's own 3D predecessor "was floundering under its own weight" ([Gamasutra, 2008](https://gamedeveloper.com/design/interview-the-making-of-dwarf-fortress)). Stonehearth, a voxel colony game, ended in 2018 short of its goals; its makers named a small team, "technical things" overshadowing the game's systems, and their own engine ([PC Gamer](https://www.pcgamer.com/stonehearths-development-will-end-this-month-without-meeting-all-its-kickstarter-goals/)). Timber and Stone and Towns stopped when money did.
- Vintage Story, a serious voxel survival world with no colony: its lead says finishing it "would take 10 to 20 years more, if ever" ([its forum](https://www.vintagestory.at/forums/topic/16342-vintage-story-adventure-mode/)).
