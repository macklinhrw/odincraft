# Interest at walking scale: why realistic worlds bore, and what to check

November 11, 2026. Web research only; no repository changes. Extends `reference/odincraft-v4/exploration-diversity-research.md` (landform families, connected basin/outlet places, Minecraft 1.18 river cuts and saddles) and the zigcraft "Procedural game-design research beyond Dwarf Fortress" section (expressive range, quality-diversity, Caves of Qud, RimWorld). Those points are not repeated here.

## Key takeaways

1. **Uniqueness is not the target; recognisability is.** Compton: mathematically unique output still reads as "a lot of oatmeal"; most content can be background, as long as a few "characterful" things stand out, and people like seeing "evidence of process and forces" ([Compton, "So you want to build a generator"](https://www.tumblr.com/galaxykate0/139774965871/so-you-want-to-build-a-generator)).
2. **Nintendo built BotW's field from shapes that hide and reveal.** Large triangles are landmarks, medium ones block the view, small ones set the tempo; landmarks of different visibility pull players in different directions ([translation of the CEDEC 2017 talk](https://gist.github.com/idbrii/e39fe96279aa1670319bfa521d907399)). The central idea is occlusion, not density.
3. **Players remember landmarks and edges, not districts or paths.** A small 2025 study of *A Short Hike* and *Sable* found only those two of Lynch's five elements came up in what players recalled ([Boakye et al.](https://cs.wellesley.edu/~pmwh/mvmap/papers/open_world_elements/open_world_elements.html)). The sample was 3 people, so this is weak evidence.
4. **"Mystery" (a view that promises more if you go on) is the best-supported of the Kaplans' predictors, with a catch.** Van der Jagt et al. found it had the strongest link to beauty ([2014](https://eprints.whiterose.ac.uk/99427/)). But in dense forest with poor sightlines, mystery predicts *lower* preference ([same paper, citing Herzog & Kropscott 2004](https://eprints.whiterose.ac.uk/99427/)). Partial occlusion with open sightlines works; a wall of trunks does not.
5. **The evidence for the theories is moderate and mixed.** Stamps' meta-analysis says the preference matrix "has not generated reproducible results" (quoted in [van der Jagt et al.](https://eprints.whiterose.ac.uk/99427/)). Prospect-refuge has mixed quantitative support ([Dosen & Ostwald 2016](https://link.springer.com/article/10.1186/s40410-016-0033-1)). The strongest single finding is water: effect sizes "consistently large" ([White et al. 2010](https://researchportal.plymouth.ac.uk/en/publications/blue-space-the-importance-of-water-for-preference-affect-and-rest/)).
6. **What is near the walker counts most.** In an alpine photo study, the near zone carried ~64% of perceived beauty, the middle 22% and the far 14% (Schirpke et al. 2013, *Sustainability* 5(3):1080, [link](https://www.mdpi.com/2071-1050/5/3/1080); figures from search-index excerpts, as the page refused my fetch). Distant relief alone cannot rescue a walk.
7. **Trail designers route between "control points" and call a good trail "a sequence of events".** Positive control points are views, waterfalls, lakes and outcrops; negative ones are wet flats and unstable slopes ([American Trails/BLM](https://www.americantrails.org/resources/criteria-for-trail-placement-control-points-and-layout), [Vermont trail guide](https://fpr.vermont.gov/sites/fpr/files/doc_library/FPR-VT-Town-Forest-trail-design-guide.pdf)). A walk is interesting when the ground offers control points close together.
8. **Juniko is one disturbance, not a park of landmarks.** Landslides blocked a valley and left a cluster of 33 ponds in beech forest, each different, next to a bare eroded cliff ([Aomori tourism](https://aomori-tourism.com/en/spot/detail_73.html), [Hirosaki University leaflet](https://nature.hirosaki-u.ac.jp/wp-content/uploads/2023/04/A4_leaflet.pdf)). The variety comes from one cause with many small, legible outcomes.
9. **First-party pacing numbers are scarce.** Sucker Punch: content every "three minutes – that's too long", every 10 seconds too much ([Game Informer 2021](https://www.gameinformer.com/2021/05/20/more-than-just-dots-on-a-map-the-challenges-behind-open-world-game-creation)). The widely quoted "40-second rule" has no first-party source I could find; treat it as folklore.
10. **No published metric of terrain interest exists.** Evaluation of terrain generators "remains an open issue" ([Santamaría-Ibirika et al., cited via search](https://link.springer.com/article/10.1007/s00371-013-0909-y)). The best route is to adapt GIS viewshed tools and expressive-range plots to walking routes, and to check them against the owner's own walks.

## 1. The oatmeal problem and procedural sameness

**Compton.** The full passage, from the original post ([tumblr](https://www.tumblr.com/galaxykate0/139774965871/so-you-want-to-build-a-generator)): "The most common way that generators fail is that they produce content that fails to be interesting." A generator may make 18 quintillion planets, but "will they be perceived as different?" Perceptual *differentiation* means "this piece of content is not identical to the last", like a line of trees that are not clones. Perceptual *uniqueness* is "the difference between … a face in a crowd scene and a character that is memorable." She says not everything should be memorable: "many artifacts can [be] drab background noise, highlighting the few characterful artifacts." Characterful objects show "evidence of process and forces, like the pushed up soil at the base of a tree", and she points to Lynch's *Image of the City* as a model of what makes places memorable.
- *Check:* split the island's content into *background* (should only be differentiated) and *characters* (must be individually memorable). Count the characters and check that each one can be named from a screenshot.

**No Man's Sky.** I found no first-party post-mortem in which Hello Games says the planets felt samey. Their update notes describe the fixes. Origins (3.0, 2020): "mountains four times larger than anything previously possible", and "planetary colour diversity" and "lighting diversity" both "significantly increased" ([Origins notes](https://www.nomanssky.com/origins-update/)). Worlds Part I (5.0, 2024): new biomes and creatures, new water, clouds and weather, "Planets have wind patterns", and "The level of variety we are achieving is far beyond what was possible before" ([Worlds Part I](https://nomanssky.com/2024/07/no-mans-sky-worlds-part-i)). *Inference:* the fixes were more extreme relief, more palette contrast and *moving* atmosphere (weather, wind, water), not more noise octaves. Sean Murray's GDC 2017 talk "Building Worlds Using Math(s)" ([Vault](https://gdcvault.com/play/1024514/Building-Worlds-Using)) was not readable to me; I could not verify what he said about sameness.

**Minecraft 1.18 (Kniberg).** Kniberg's own video description says the goal was "interesting, beautiful, and dramatic terrain" ([YouTube](https://www.youtube.com/watch?v=CSa5O6knuwI)). His playtest video has chapters on "Challenges of microbiomes, no minimum biome size", "Peaks & Valleys and Saddle Valley generation" and "5D noise + unpredictability" ([YouTube](https://www.youtube.com/watch?v=TycBrFKEteU)). I could not get transcripts, so I have no quotes from inside the videos. The changelog evidence is in the v4 note.

**Short & Adams, *Procedural Generation in Game Design* (2017).** The publisher lists a chapter "Managing Output: Boredom versus Chaos" and Liam Welton's "Aesthetics in Procedural Generation" ([Routledge](https://www.routledge.com/Procedural-Generation-in-Game-Design/Short-Adams/p/book/9781498799195)). I could not read the text; not verified. Emily Short and Joris Dormans: nothing directly about landscape sameness found; skipped.

## 2. Designing a landscape that pulls a walker through it

**Breath of the Wild, CEDEC 2017 field talk (Fujibayashi, Yonezu).** The source is Matt Walker's English translation of tweets about the Japanese talk, reformatted by a third party ([gist](https://gist.github.com/idbrii/e39fe96279aa1670319bfa521d907399)). It is a translation and a summary, not a transcript.
- *Triangle rule:* triangles give "a choice as to whether to go straight over the triangle, or around", and they "obscure the player's view" so players wonder what lies beyond.
- *Three scales:* the largest are "landmarks that serve as visual markers", medium ones "obstruct the player's view", and the smallest "serve the tempo" by changing what the player does.
- *Rectangles* are used for "completely hiding something from sight".
- *Layered reveal:* a hill hides a structure, which hides a tower; each step leads to the next.
- *Gravity:* structures of different visibility pull players in different directions and let them get sidetracked, and the order of attractions varies with play style.
- *Heat maps:* playtest traces first showed players on a few concentrated paths, the game felt "too linear", and after the redesign the traces were better spread.
- Robert Yang's reading ([Radiator Blog](https://www.blog.radiator.debacle.us/2017/10/open-world-level-design-spatial.html), secondary) adds the "bowls / funnels" image and "You should not be able to see entire landmarks from point A to point B." He flags the three-bucket idea as possibly his own interpretation.
- *Kyoto:* Fujibayashi told The Verge he "took a map of Kyoto and overlaid it on the game world" to judge size ([via Zelda Dungeon](https://www.zeldadungeon.net/breath-of-the-wilds-huge-map-takes-inspiration-from-kyoto/); [Verge](http://www.theverge.com/2017/3/6/14827832/the-legend-of-zelda-breath-of-the-wild-map-kyoto-japan)). The talk gives no distances or density numbers.
- *Checks:* on any 300 m stretch, is the next attraction hidden by a mid-scale rise? Is there a choice to go over it or around? Do simulated walkers spread out, or bunch onto one route?

**Other games, first-party where available.**
- *Elden Ring:* Miyazaki wanted players to "discover the simple joy of exploration" and balanced "the tempo and pacing" of progress ([PlayStation Blog, 2022](https://blog.playstation.com/?p=359935)). I found no first-party statement about landmark sight distance.
- *Firewatch:* objects were scaled by "what felt right, not accurate", with 23 hand-made tree models ([80.lv, secondary summary of Jane Ng's talk](https://80.lv/articles/creating-the-world-of-firewatch)).
- *A Short Hike:* the 2020 GDC postmortem, "Crafting A Tiny Open World" ([Vault](https://gdcvault.com/play/1026613/Independent-Games-Summit-Crafting-A)), has a level design and player guidance section, but I could not read its content. Robinson-Yu credits BotW's "Where's Waldo" moments ([GamesRadar](https://www.gamesradar.com/games/open-world/a-short-hike-dev-says-wheres-waldo-moments-like-zelda-breath-of-the-wilds-korok-seeds-help-to-stop-you-getting-too-bored-when-traveling-around-in-open-world-games)).
- *Death Stranding:* the world was based on scouted Iceland ([505 Q&A](https://deathstrandingpc.505games.com/ru/?p=7760)). A GDC 2021 AI talk says the terrain was as hard for NPCs to cross as for players ([Game Developer](https://gamedeveloper.com/programming/in-i-death-stranding-i-navigating-the-world-was-harder-for-npcs-than-players)). I found no first-party design statement on traversal as challenge.
- *Valheim:* Iron Gate uses a fixed "blueprint for the way a biome works" (boss, key items, gear) ([PCGamesN](https://www.pcgamesn.com/valheim/indie-game-works-chapter)). That gives biomes a strong identity through rules, not just looks.
- Dear Esther, Proteus, Subnautica and Shadow of the Colossus: I found no first-party landscape-design sources.

## 3. Environmental psychology: what is solid and what is not

| Claim | Source | Strength |
|---|---|---|
| Water raises preference, positive mood and restoration ratings; built scenes with water rated about as well as green space | [White et al. 2010, J. Env. Psych. 30(4)](https://researchportal.plymouth.ac.uk/en/publications/blue-space-the-importance-of-water-for-preference-affect-and-rest/) | Strong: two experiments, effect sizes "consistently large" (abstract) |
| Mystery predicts beauty; best fit is cubic, with the biggest effect at the low and high ends | [van der Jagt et al. 2014, LUP 124](https://eprints.whiterose.ac.uk/99427/) | Moderate; mystery had the best reliability (α 0.76) of the four predictors |
| In forest with low visual access, mystery can *lower* preference (danger) | Herzog & Kutzli 2002, Herzog & Kropscott 2004, Herzog & Kirk 2005, as cited by van der Jagt | Moderate |
| The preference matrix as a whole "has not generated reproducible results" | Stamps 2004 meta-analysis, quoted by van der Jagt | It is the critique that is strong |
| Prospect-refuge: evidence in natural settings for both prospect and refuge, plus studies against and null results; mystery mostly neutral or contrary in architecture | [Dosen & Ostwald 2016](https://link.springer.com/article/10.1186/s40410-016-0033-1) (abstract via [ProQuest](https://www.proquest.com/docview/1786640263)) | Weak to moderate |
| Preference rises with the number of land types, the number of patches and land-type diversity measured from maps | [Dramstad et al. 2006, LUP 78](https://doi.org/10.1016/j.landurbplan.2005.12.006) (abstract only) | Moderate; varies between groups of people |
| Near zone ~64% of perceived beauty; naturalness and diversity raise it | Schirpke et al. 2013 (see takeaway 6) | Moderate, one region |
| Nine visual-character concepts, including complexity, coherence, imageability, visual scale and ephemera, can be measured with indicators | [Tveit, Ode & Fry 2006](https://doi.org/10.1080/01426390600783269); [Ode et al. 2008](https://doi.org/10.1080/01426390701773854) | Framework, not an effect size |
| Large virtual worlds need structure to be navigable; cues change search strategy | [Darken & Sibert, CHI 1996](https://doi.org/10.1145/238386.238459) (abstract) | Moderate. A later citation reports small landmark effects, so the details are contested |

*Practical reading:* the Kaplans' terms remain useful vocabulary for a reviewer ("legible", "mystery") but should not be optimised as scores. Two findings are robust enough to act on: water, and partial occlusion with open sightlines.

## 4. Real hiking landscapes

**Trail design practice.**
- *Control points:* positive ones are "scenic overlooks, historic sites, waterfalls, and lakes"; basic ones are trail ends, junctions and drainage crossings; negative ones are "low-lying wet areas, flat ground, extremely steep cross slopes or cliffs, unstable soils" ([American Trails/BLM Kremmling](https://www.americantrails.org/resources/criteria-for-trail-placement-control-points-and-layout)).
- *Grade:* the Forest Service routes along contours between control points, keeping grades under 10% ([USFS via FHWA](https://www.fhwa.dot.gov/environment/recreational_trails/publications/fs_publications/07232806/page03.cfm)). Control points tend to give "a pleasing nonlinearity" ([Rec Management](https://recmanagement.com/articles/154799/miles-smiles)).
- *Sequence of events:* the Vermont guide, which reuses Forest Service material, has a section "Successful Trails are a Sequence of Events". Its survey checklist names "high points, low points, rock outcroppings, features of topographic and/or geologic interest" and "Views". Its "rolling grade" pattern is "a series of dips, crests, climbs, drainage crossings, and edge buffers". Its layout step: flag "a sequence of events that will make the trail interesting" ([Vermont guide](https://fpr.vermont.gov/sites/fpr/files/doc_library/FPR-VT-Town-Forest-trail-design-guide.pdf)).
- "Anchors", "gateways" and "edges" as trail-planning terms: I did not find them in a Forest Service or NPS guide. The closest was "major site anchors such as lakes and rivers" in the Vermont guide.
- *Check:* run an automatic trail router between generated positive control points. If it cannot find a sequence of positive points spaced along a contour route, the walk will be dull whatever the screenshots look like.

**Juniko.** Thirty-three lakes and ponds; only twelve are visible from the summit of Mt. Okuzure, hence the name ([Aomori tourism](https://aomori-tourism.com/en/spot/detail_73.html)).
- *Origin:* landslides blocked rivers between 1440 and 1660, dated by radiocarbon in drowned trees, and the 1704 earthquake reactivated the slide ([Hirosaki University](https://nature.hirosaki-u.ac.jp/wp-content/uploads/2023/04/A4_leaflet.pdf)).
- *Ponds:* Aoike's cobalt water holds drowned beech trunks. The Aoike–Wakitsubo loop takes about 45 minutes, about 10 minutes from the car park to Aoike and 15 more to Wakitsubo ([Visit Shirakami](https://visitshirakami.com/things_to_do/juniko-lakes/)).
- *Nihon Canyon:* bare walls of "colorful brown and grey rock" next to the lakes, linked by trail ([japan-guide](https://www.japan-guide.com/e/e3790.html)).
- *Count:* none of these sources gives the route length, so I could not count features per kilometre reliably. A rough reading of the loop is three named ponds, the beech forest and the boardwalks in roughly 2 km. Treat that figure as unverified.

**Lake District and Yakushima.** I found no reliable source that lists the features along a specific 3–5 km route. I do not give a count.

## 5. Measuring it

- **Expressive range** ([Smith & Whitehead 2010](https://www.pcgworkshop.com/archive/smith2010analyzing.pdf)): plot many seeds on two or more metric axes, and look for gaps and clusters. Later work recommends corner plots for more than two dimensions (Summerville, via [Withington et al. 2024](https://arxiv.org/abs/2404.18657)). Withington, Cook and Tokarchuk sorted 86 papers and found "consensus … is currently limited" on how to evaluate generators ([arXiv 2404.18657](https://arxiv.org/abs/2404.18657)).
- **Quality-diversity:** MAP-Elites keeps the best example in each cell of a behaviour grid ([Mouret & Clune 2015](https://arxiv.org/abs/1504.04909)). For OdinCraft it is useful offline, to see which valley types the generator *can* make; it is not needed at runtime.
- **Terrain-specific metrics found:**
  - Perceived realism scored with geomorphons ([PTRM, arXiv 1909.04610](https://arxiv.org/pdf/1909.04610)).
  - Accessibility and obstacle-edge-length fitness for evolved terrain ([Frade et al.](https://www.researchgate.net/publication/257432457_Automatic_evolution_of_programs_for_procedural_generation_of_terrains_for_video_games_Accessibility_and_edge_length_constraints)).
  - Isovist area and visibility/accessibility mismatch from space syntax, applied to a game level ([Nottingham](https://nottingham-repository.worktribe.com/OutputFile/722033)).
  - Path-visibility-based content placement ([Tremblay et al.](https://www.sable.mcgill.ca/~clump/papers/tremblay-15-algorithmic.pdf)).
- **Not found:** any published, validated measure of how interesting terrain is to explore on foot, and any first-party game tool for viewshed-driven field design.

*Proposed walking-scale metrics (inference).* Compute them along simulated walks: random pairs of points, routed along the cheapest walkable path, sampled every 10 m at eye height 1.6 m.
- **Viewshed area** within 1 km, and the *variance* of its logarithm along the walk. Alternating enclosure and openness, rather than a high average, is the target.
- **Reveal events:** where a landmark's visible fraction jumps from below 10% to above 50% within 30 m.
- **Distinct landform classes** within a 150 m radius, using geomorphons (peak, ridge, shoulder, spur, slope, hollow, footslope, valley, pit, flat) plus water and bare rock.
- **Edges crossed:** forest/open, rock/soil, water's edge, and slope breaks over 20°.
- **Local relief:** within 100 m, and within 1 km.
- **Event distance:** the distance between consecutive positive control points.
- **Landmark visibility:** the share of samples from which at least one named landmark is visible.

## 6. Variety budgets

- **Sucker Punch:** "it couldn't be every three minutes – that's too long", and not "Every 10 seconds there's something happening"; rewards for "that minute or two or 30 seconds" ([Game Informer 2021](https://www.gameinformer.com/2021/05/20/more-than-just-dots-on-a-map-the-challenges-behind-open-world-game-creation)).
- **Ubisoft:** the Valhalla team checks that the straight line between quests passes "greatest hits" (same source).
- **Insomniac:** "for every two swings, we want him to pass one large building" (same source).
- **Miles Tost, CD Projekt Red:** density is "a very meticulous process" (same source).
- **The "40-second rule"** (Witcher 3 or Skyrim): only secondary and forum sources ([The Nerd Stash](https://thenerdstash.com/starfield-breaks-the-40-second-rule), [ResetEra](https://resetera.com/threads/40-second-rule-of-open-world-games.142132)). Folklore.
- **BotW and Elden Ring:** no first-party spacing numbers found.
- **Minecraft villages:** the game's own structure set uses spacing 34 and separation 8 chunks, at most one attempt per 544 × 544 block cell. Neighbouring attempts can be up to 2×34−8 = 60 chunks (960 blocks) apart, and the biome must allow it (game data via [Minecraft Wiki mirror](https://wiki.ronlab.site/content/minecraftwiki_en_all_maxi_2025-11/Structure_set); terms per [Microsoft docs](https://learn.microsoft.com/en-us/minecraft/creator/reference/content/worldgenreference/examples/jigsawstructuresets)).
- **Walking-speed conversion (inference):** at OdinCraft walking pace of ~4–5 m/s, Sucker Punch's band of under 3 minutes and over 10 seconds is roughly one event every 50–700 m.
- **Rarity and quiet:** Compton's background versus characters, and Miyazaki's "romanticism in solitude" (secondary: [Famitsu translation via search](https://s.famitsu.com/en/news/202201/27249109.html)), both argue for quiet stretches as a deliberate part of the design. The v4/zigcraft notes already ask for "controlled frequencies so rarity retains meaning."

## Why realistic terrain is boring, and what to do about it

*Everything in this section is my inference from the sources above, not a finding of theirs.*

**Mechanisms.**
1. **Statistical self-similarity.** Stream-power erosion under one uplift rate and one rock makes valleys with the same width-to-depth ratio and the same branching at every scale. Each valley is mathematically unique and perceptually the same: Compton's oatmeal, in landform. Real relief statistics prove realism, not difference.
2. **No contrast in materials.** In real places a change of rock gives a cliff, a ledge, a waterfall or a bare scar: Nihon Canyon, the resistant outlet lip. With one rock, every slope is the same soil-covered curve, and nothing exposes the "evidence of process" that Compton says people read.
3. **No strong edges.** Smooth fields blend into each other. Lynch-style edges (forest boundary, cliff line, shore, slope break) are the elements players actually recall (Boakye et al.), and uniform conditions produce none.
4. **No disturbance, so no unique places.** Juniko, gorges and lake chains come from *events*: a landslide, a glacier, a lava flow, rock-controlled knickpoints. Equilibrium erosion erases events. Unique places need a few deliberate, physically caused departures from equilibrium.
5. **Nothing visible from afar that differs when reached.** If summits look alike and arriving shows the same ground as leaving, there is no gravity in the BotW sense and no reveal: the distant view makes no promise. Mystery needs a promise that is kept.
6. **Uniform canopy hides relief.** Closed forest over every slope removes the mid-distance (the 22% band) and turns mystery into threat (Herzog). The land's structure becomes invisible exactly where the walker is, and the near zone carries most of the impression.
7. **Scale mismatch.** Realistic proportions at 1 m per block make valley walls hundreds of metres apart and slopes gentle. BotW, Firewatch and the Kyoto overlay all compress or exaggerate on purpose, sizing by how far a person walks.

**Checklist for a 6 km island.** Thresholds are starting proposals for the owner to tune by walking. Metrics are as defined in §5.

1. **A landmark is always in sight.** From at least 90% of walkable samples, at least one *named* landmark (summit, tower-like rock, waterfall, lake, lone tree, coast stack) is visible within 1.5 km. No walkable spot is more than 400 m from a place where one is visible.
2. **There is something to head for.** From at least 70% of samples, a landmark within 600 m is partly hidden by nearer ground, so there is a mid-scale occluder between the walker and the goal.
3. **Something new turns up regularly.** Along any simulated walk, the distance between consecutive positive control points (view, water feature, rock exposure, clearing, unique place) has a median of 150–400 m and never exceeds 700 m.
4. **Openness alternates.** Every 500 m of walk crosses at least one edge: forest/open, rock/soil, shore, or a slope break over 20°. The log of viewshed area swings by a factor of at least 10 at least once per kilometre.
5. **There are 5 to 8 districts, recognisable without colour.** Each is identifiable from a greyscale screenshot by landform and texture alone (for example: lake basin, gorge country, rounded wooded hills, exposed ridge, coast, wetland flats). Test with blind sorting of 20 greyscale shots.
6. **Neighbouring valleys differ.** Every valley differs from each neighbour in at least one of: floor width (narrow at most 30 m vs open at least 100 m), wall (rock vs soil), floor (water body, meadow, forest), and stream form (falls or cascades vs meanders).
7. **Exposed rock is reachable.** At least 10% of the land surface is bare rock or scree. Every 1 km² cell contains some, and some of it can be reached on foot.
8. **Water is close.** At least 60% of walkable samples are within 300 m of visible water, whether stream, lake or sea.
9. **There are a few unique places, caused by events.** At least 3 one-off places, such as a landslide-dammed pond cluster, a gorge through a resistant band or a waterfall step, each traceable to a cause. None of them is repeated anywhere on the island.
10. **High ground pays off.** At least 5 reachable viewpoints with a 360° viewshed over 4 km², each with a route to it. Each overlooks at least one feature from items 6 to 9.
11. **The canopy has gaps.** Forest covers 40–70% of land, never as a closed sheet more than 600 m across without a gap. At least 30% of forest edge faces a view.
12. **Routes branch.** Between two control points there are often several reasonable routes: in the BotW sense, simulated walkers spread rather than bunching onto a single corridor.
13. **There are quiet stretches.** At least 20% of walk length has no positive control point within 150 m. These quiet stretches separate events; they are not dead zones.
14. **The terrain is read the same way at any distance.** Districts and landmarks keep their silhouette in far terrain, so a distant view promises what arrival delivers.
15. **The variety survives across seeds.** Items 1–13 hold on at least 9 of 10 seeds, shown with expressive-range plots, so a good result is not one lucky island.

**Not verified.**
- Sean Murray's and Kniberg's own words on sameness (talks not readable).
- The content of the A Short Hike talk and of Short & Adams's book.
- Any first-party pacing number for BotW, Elden Ring, Skyrim or Witcher 3.
- Feature counts per kilometre for Juniko, the Lake District or Yakushima.
- The full texts of Stamps 2004, Dramstad 2006 and Schirpke 2013 (abstract or quoted figures only).
- Firewatch and Death Stranding landscape-design statements in the designers' own words.
