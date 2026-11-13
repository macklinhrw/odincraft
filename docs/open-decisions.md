# Design decisions

What has been decided for v5 and what is still open. The owner decides direction; on 2026-11-10 the owner delegated the engineering choices for the first build to Claude, and those are marked "Claude's call" so the owner can overturn any of them. A decision that is hard to reverse, surprising, and a real trade-off also has a record in `docs/adr/`.

Background: `ideas.md` (the destination) and `lessons.md` (why earlier attempts stalled).

## Decided

**2026-11-10, by the owner**

- **Fresh repository, ideas only.** Earlier projects' idea documents are in `reference/`. Earlier code may be read to learn what a feature did; implementations are designed fresh.
- **Start with a small working game to test directions in.** A basic, minimal implementation with level of detail, lighting and anti-aliasing done properly, used to try directions for world generation, look and gameplay. This replaced the earlier plan of settling every decision on paper first.
- **Keep the code small.** Not too much code, not too long to write.
- **The world is a simulated island with designed rivers.** The owner chose this from the options below on the day the first build was playable. An island about 6 km across is formed before play by uplift and erosion on a grid, in about a second, and rivers are traced from its drainage and cut by design. See `adr/0003`. The noise generator the first build started with is gone.

- **Water flows.** It runs downhill, fills what is dug, shows its movement and never lies in overlapping sheets. See `adr/0004`.

**2026-11-11, by the owner**

- **The end vision is a fantasy world grounded in realism, in the vein of The Lord of the Rings.** `ideas.md` lists the fantasy world as the last horizon; the owner has named it the destination. The natural world is what makes it believable, so foundations are judged by whether they can carry it. The world is original: nothing is taken from Middle-earth.
- **Plan the foundations for a wider world, beyond the island**, with variety that matches or exceeds Dwarf Fortress and RimWorld. The plan is `foundations.md`, with one design per system in `foundations/`; nothing in it is a commitment until recorded here.

- **Start Phase 1 of `foundations.md`**: the sixteen changes on one island, in its section 8, beginning with the seed and overlays (step 0) and rock beds in the land forming (step 1).

- **What a place is made of and what happened to it are drawn from the seed, never chosen by hand.** The rock story, the bed sequence, the tilt, the history and where an event such as a landslide falls all come from the seed, within the ranges of a catalogue row. The owner's choices are which rows exist and in what order they are built. This corrects `foundations.md` section 9, items 1 and 2, and question 7 below, which read as if the island's rock and history were picked once.

- **Steps 0 and 1 accepted on sight**: the seed, the overlays and the rock beds. The owner looked at the game and found the bare mountain faces fine as parts of the mountains. Step 2 (cliffs in blocks) follows, and with it the designed rule for what is bare: rock at its own slope limit stays bare, weak rock below it takes soil, and loose rock lies at the foot of a face.

- **Step 2 accepted**: ledges on hard beds, cracked faces, loose rock below a face, far faces coloured bed by bed. Fallen blocks were taken out on Claude's suggestion: single cubes, rare and never stacked, did not read as rockfall. They return when they can be done properly.

- **The default island need not stay the same.** It can and should change as the generation changes, until saves exist and a seed has to keep its world. No step has to preserve the seed 7 map, the start or the bench distances; `CLAUDE.md` is updated when they move.

- **Real Japanese islands are the north star for the land, and not the only reference.** The owner finds their terrain far more interesting than anything generated so far, and does not accept that realism and interest are separate problems here. Generated islands are judged against real elevation data for islands of the same size, on the map, in figures and in the game.
- **Lean toward livable real islands as references, and keep the inhospitable kind as a rarer draw.** Having seen the comparison, the owner noted that an island like Mikurajima, all cliff and flank, leaves nowhere to live. Most generated islands should have the real islands' drama and also ground a person could settle, well balanced; the variance should still allow an island that is all cliff. The findings and what follows from them are in `interesting-world/notes/real-islands.md`.

- **A land-forming step goes next, ahead of step 4.** The sea cuts the coast inside the forming, so exposed shores stand as cliffs; the uplift no longer falls to nothing at the shore; strong rock holds steeper faces and creeps less; and livable ground is kept where it has a cause (a bay head, a valley floor, a terrace). The targets are the real figures in `foundations.md` section 11. This answers the first five items of question 9.
- **The same step adds an inlet-coast kind and a vent.** The inlet coast is a history that ends in a sea rise of about 120 m, tested the same day. A vent builds rock and can collapse, so a volcanic island is built and not drawn as a bump of uplift. This takes question 10 in the direction of kinds as histories, one kind at a time.

**2026-11-12, by the owner**

- **The three questions the land-forming step left are Claude's to settle**: whether to commit it, what to do about the default island having no landing, and whether the swelling of a cone stands as the cause of its sea cliffs. The owner asked for them to be analysed and the best course taken. The answers are below as Claude's call, and the owner has still not looked at the step.

- **Try to fix the shortfall in landings.** Asked after seeing that the ridge and raised kinds were below the real counts and that the ice-age history had failed. What was tried and what was kept is in the ridge and raised entry below and in `foundations.md` section 11.

- **Fix three faults before step 5**: rows of chunks flashing pale over water while moving fast, distant trees drawn as columns of leaves down to the ground, and rock on a far mountain face showing the wrong colour until one comes close. Of the last the owner said that the far colour being wrong is the point that matters.

- **Move on to step 5**, soil and the five plant communities. The three decisions the plan lists before it (the island's climate, true tree heights, small plants as cubes) were not put to the owner: one flora row exists, tree heights wait for step 8 and small plants for step 9.

- **The plants should match the real islands, and the blocks need real textures.** Having seen the first communities, the owner asked how they compare with the makeup of the real reference islands, found the purple ground odd, and asked for colour, tree shapes and how thickly trees and bushes stand to be done properly. The blocks read as one flat tone each; the owner asked for a texture atlas as other block games have, with attention given to each texture, and rejected patterns made from noise in the shader as looking like a skin condition.
- **The textures are still too noisy, contrasty and gritty**: compare them with Minecraft's own, which are very good now, and with the best texture packs.
- **Block textures start from an artist-made pack with an open licence**, adapted to our species and rocks. The owner judged the tiles drawn by code better than at the start but still very bad overall, and chose this over Claude drawing each tile by hand or leaving them.
- **Continue with step 6 of the plan**, the landslide and its lake. Said while Claude was giving the rocks and soils their own tiles, which was not what "the next step" had meant; that work was finished off and left as it stood.
- **Fix the landslide's weak points**, all of them, Claude to do it and not hand it on.
- **Commit steps 5 and 6, the flora and the textures, and go on to step 7**, stands with ages.
- **Continue**: said when asked whether to commit step 7, with step 8 named as next. Taken as both, as with the steps before it.
- **Run the steps that nothing blocks in parallel, each with its own subagent**, and keep their test runs out of the way: no windows, no taking the mouse or the focus, since open windows disturb each other and the owner.
- **Small plants are drawn as crossed planes**, two flat cut-out pictures standing in an X, as Minecraft draws grass, ferns and reeds, using the artist's plant pictures from the same pack. Chosen over the plan's leaf cubes when asked before step 9. This answers item 6 of `foundations.md` section 9.
- **The creatures of step 16 are models built of blocks**: a bird or a fish is a few small boxes, as a Minecraft animal is, and not a flat picture or a smooth model. Said when asked before step 16.

**2026-11-12, Claude's call**

- **What a shore is made of follows the swell and the rivers** (step 15). Sand only where a river's mouth supplies more than the swell carries off; shingle where it does not; boulders and wave-washed rock where the swell breaks. The sand line that laid pale sand round every shore is gone. On the default island about an eighth of the shore is sand, a third shingle and a third bare washed rock.
- **Black sand on basalt and scoria, pale sand on every other rock**, beach and shore soil alike, after Miyakejima and Ōshima against Kōzushima's rhyolite and Kikaijima's coral. One new material, black sand, takes the artist's sand tile in dark grey.
- **The platform the forming cut 2 m under the sea is raised to the sea's level near an open shore**, so it can be seen and walked on, with gullies and pools along the strike of the beds. With no tide, a platform under the water would never show. This is a choice of look as much as a cause.
- **Shingle and boulders are the island's own broken rock** (the rock's loose block), so they are dark on basalt and buff on sandstone, and they lie only in heaps along the foot of what stands behind the platform, never scattered one by one, which the owner rejected in step 2.
- **Stacks are features ranked by host as notches are**: a headland open to the swell, in rock of strength 0.5 or more, at a cliff. Each stands 5 to 40 m off the cliff's foot, at 40 to 90% of the cliff's height, with up to three skerries, and its sides step at its beds. Every island so far gets two.
- **No surf.** White water at the shore was left out: the sea shader is being changed by another step, and nothing tried in this one looked right.

- **Ground plants are drawn only within about 190 m**, thinning from 70 m, and the ground's tile stands in beyond. Drawing them farther cost more than it showed.
- **Plants cast no shadow and are lit as the ground they stand on**, a little brighter where a picture faces the sun. Shadows from grass would speckle at the resolution of the near shadow map.
- **Fifteen ground plants from the warm islands' flora**, each matched to the nearest picture in the pack: ferns, bracken, susuki, dwarf bamboo, evergreen shrubs, manryō, forest grass, short grass, reeds, sedges, itadori and its dead stems, kōbōmugi, hamagō and nigana. Itadori and the evergreen shrubs are berry bushes recoloured, a weak likeness.
- **Susuki stands 1.3 to 1.6 m, not the 2 m it can reach**, so a walker sees over most of it.
- **Reeds stand from 0.8 m of water to 0.4 m above it, and sedges above them**: a band as wide as the shore is gentle. Along streams only where the ground is gentler than 1 in 5, as slow water.
- **No floating leaves.** The pack's water lily is credited to another author than the pack's, and no other picture looks like one.
- **The plants are the same all year**: no plumes in autumn and the spring daisies always in flower, as the rest of the island has no season.
- **Places get plain English names drawn from what made them** (step 13): a word from the place's cause (its rock's colour, its wood's main tree, its size, a slide beside it, the wind, its quarter of the island), then the place's own word (Top, Pike, Gap, Scar, Tarn, Slip, Bowl, Head and the like), drawn by a key from the seed and the place, never two alike on an island. "Tabu Tarn", "the Black Bowl", "Windgap". No made-up tongue, nothing from Middle-earth or real places. The word table is in `places.odin` and could be swapped for a language later.
- **A place must be one a person could know from 1 to 2 km away**, not only the most extreme of its kind. Its score is how far past its row's worth it is (on a log scale), shared out among the others of its kind nearly as extreme (fifteen like faces of one cliff band are the island's wall, not fifteen landmarks), times how much of the ground 1 to 2 km round sees it and how large it stands. Summits are not shared out, since prominence already says each stands apart.
- **A place is named only at a score of 1 or more**, set by looking at the candidates on three islands from their viewpoints. That names 0 to 5 places on an island, mostly 1 or 2, not the plan's 8 to 12: the default island has one, Tabu Tarn. Lowering the line (`c.score < 1` in `places_make`) to about 0.6 names three to six more on most islands, chiefly headlands, lesser tops and faces of a cliff band; the pictures say a person would not know most of them from 1.5 km.
- **Places stand 900 m apart at least, and take in what lies within 400 m** (a lake with the slide that dammed it is one place); at most three of a kind.
- **Falls, caves, shelters, notches, springs and the oldest wood are candidates but are not named on their own** as things stand: from 1.5 km a fall draining a fraction of a km² is a thread a block or two wide, a cave mouth is a few pixels, and an old wood looks like any other once its trees are grown. They are named when they lie in a place, in its lines, and the ranked list shows them.
- **The survey prints only with `--survey`**, since start-up already gives the shares of plants, soil and rock; start-up adds only the places.

- **Roofed places are three features with hosts, carved into the blocks** (step 14): sea notches, rock shelters and sea caves, a few of each on an island, each where its host ranks best, as the slide is. The default island has four shelters and no notch or cave, because its shore is low mudstone and sand; the cones, the ridge and the domes have all three.
- **A sea cave asks for rock of strength 0.5 or more and a real face.** In mudstone it came out as an open cleft, since its roof fell in. Real sea caves at Dogashima are cut in a soft tuff, so this may be too strict.
- **A face under a roof is lit by the square root of the share of sky it sees, and never below 2 of 15.** Taken straight, a cave was black a metre in. It is a choice of look, not a measure.
- **The sea runs in under a roof and is drawn dark there**: water stands on the floor under the roof where the sea's level reaches, not on the roof, and does not mirror the sky.
- **From afar a roofed place is a dark band on the far faces**, out to cells of 8 m (about 2 km), at about a quarter of the light. The near ring's edge is not closed with an unlit face, since no cave is longer than 40 m.

- **Only islands once joined to larger land have deer, so the default island has no trails.** Of the reference islands only Tsushima has a large wild animal of its own; the oceanic ones have only what people brought (`interesting-world/notes/real-animals.md`). The rule is the sea having risen 100 m or more over the island since it stood lowest, which today only the inlets kind meets. To put deer on every island, lower the one number in the `DEER` row.
- **The animal is the sika deer**, not goats or boar: goats came with people and the first island is wild; boar root the ground rather than tread lines.
- **Crossing ground costs what a person's walk would**: Tobler's hiking function on the grade, a wall past 45°, slower in thick plants (three times in susuki), much slower through a deep stream, faster on a worn trail. Animals, and later people, share it.
- **A ford is on a river's lip**, where it runs a hand deep above a drop, since everywhere else the channel is two blocks deep and a walker cannot climb out. Where no lip is in reach, deer swim; `--why` says so.
- **About 2.5 km of trail in each km²**: a bed in each 500 m square, with routes to water, to open ground and to one neighbour. Two neighbours made a road map. No real figure was found to hold it to.
- **A trail is a line of bare earth a block wide, with nothing growing within 2.5 m**, drawn out to about 512 m and as a red line on the map. Its height is the ground's: no cut steps.
- **The island stays at 30° N, and has no snow line** (step 10). The plants are those of islands at 27 to 34° N, so the sun now reads the same latitude as the plants. At Tanegashima (30.7° N, 25 m) January averages 11.7 °C; with 6.5 °C less for each kilometre up, the default island's 347 m top averages 9.4 °C in January, and the freezing level stands near 1,800 m. The coldest night at Yakushima since 1937, 0.7 °C, would be about −1.6 °C up there: a flake at most, never lying snow. The plan's snow line was written for 40° N and is not built.
- **The default day is 80, the March equinox**, so the sun stands where it always has unless `--day=` moves it. The year does not run during play.
- **The weather follows the real sunshine, not the plan's guess.** Each month's mean cloud cover is the share of its daylight without sunshine at Tanegashima: 0.73 in June's rainy season, 0.45 to 0.48 in July and August, about 0.6 the rest of the year. That makes a clear or broken sky a little under half the time, where the climate design suggested two days in three. The default start falls on a cloudy morning (cover 0.77, base 347 m). `--weather=0` clears it for judging the land.
- **Weather comes in spells of two days**, each drawing its cover around its month's mean and a cloud base of 250 to 1,000 m, lower under heavier cover, and passing smoothly into the next. Fronts with tracks, rain, fog and typhoons are not built.
- **A cap of cloud forms where the sea wind is lifted past the cloud base** by the ground it has crossed in the last 400 m, sinking a metre for every four after a crest (the field `lifted`). On the default island, at 347 m, a cap needs a base under about 330 m, which a spell draws about one time in six; the cone on seed 7, at 692 m, wears one under four skies in five.
- **Clouds are one layer 300 m deep, marched in 16 steps**, with the light dimmed by the cloud above each step, so bases are grey and tops white. No volumetric clouds and no rain. Their edges are grainy close to, which is the price of the few steps.
- **Cloud shadows dim the sun by 85% and the sky light by 30%**, on land and water alike, and the sea reflects the clouds.
- **The clouds drift at 8 m/s from the swell's bearing** (a guess), so the wind, the swell, the exposure and the clouds agree.
- **No seasonal colour.** The susuki of these islands' windy ground, Hachijō susuki, is reported to keep green leaves through winter, and turning grass straw would need a tile the atlas does not have; its plumes would need a plant shape (step 9). The light's colour already follows the sun's height, and no source gave a seasonal tint for this coast.
- **A shadow map not redrawn in a frame keeps the sun it was drawn with.** Before, any move of the sun redrew all four maps every frame, and a running clock put every frame of the forest flight over 12.5 ms.

- **Falls are made at a strong bed across steep ground** (steeper than 0.3 over 30 m): the stream drops in one fall from that bed's top to the next strong bed or the foot of the steep ground, and runs below in the gorge the fall wore back through. Without a strong bed it cascades down the land. Drops of a block or two stay pools; every drop over 2.5 m is a fall with water of its own.
- **Falls are one mesh drawn the same near and far**, a sheet leaving the lip at the speed water crosses it and falling freely to churned white water on its pool. The simulated water keeps out of it rather than handing over at a distance.
- **River water near the player is held at its level both ways**, not only topped up, so water over a lip leaves through the fall and does not run down a gorge's walls. A dammed river cannot rise until the supply rule of water.md D7 is built.
- **Rivers are sized by discharge**, with 2 m of the year's rain running off (a guess): streams start a block wide, can be waded at 1 km² and are chest deep at 7 km². They are narrower at their heads than before.
- **The rocks that pass water are a set** (`PASSES`): sandstone, grit, limestone, basalt, scoria and tuff. A spring is where one lies on a rock that holds water, in a hollow on a valley side, one in 150 m. A permeability field on the rock rows waits until the water table needs it.
- **A fall's pool is as deep as Veronese's scour rule gives** for a flood twenty times the mean flow (a guess): 1 to 2.7 m of water.
- **The start moved** to a bank in valley forest near 527, -1,061, since narrower streams brought the old bank within 6 m of a tree.
- **The land-forming step is committed** as built, so that what follows can be told apart from it and undone alone.
- **The ridge and raised islands get their landings from a larger last rise of the sea**, which floods the mouths of their valleys into coves: 40 to 60 m on the ridge (from 5 to 10) and 10 to 20 m on the raised island (from 3 to 6). The ridge row is also about a tenth larger and a third longer than it is wide, since landings follow the length of the shore. These are numbers in two rows and no new code. Twelve ridge seeds have 2 to 12 landings, median 5, where the kind had none; its coast is less steep for it (60 m within 100 m of the shore, 64% cliffed, 25% of land under 50 m against the real 5 to 16). Six of twelve raised seeds have a landing. The truer cause, valleys cut to an ice-age low sea and then flooded, works only with the island at rest through the low stand, and then gives no more landings, less cliff and twice the forming time (`foundations.md` section 11).
- **The game prints landings for every 10 km of shore beside the count**, since a count alone compares a 20 km shore with a 75 km one. The real ranges beside it (1.3 to 1.9, 3.6 on Tsushima) use the counts from the first comparison over shore lengths measured by a script on the same grids.
- **A distant single tree is a crown hung over the ground on a trunk**, at the two levels of detail that show single trees (about 270 m to 1.1 km). Beyond that the canopy stays a solid layer on the columns: a trunk band under it would stripe every steep wooded hillside. It draws about a sixth more faces in a wooded view.
- **A far face shows its rock under a wood.** Beyond 1.1 km a wooded cell at a cliff's edge drew leaves all the way down the face, so a cliff seen from afar was hung with green strips that vanished on approach. The riser below the wood's own ground now shows the beds, as it does for open ground.
- **Beds are merged for drawing only when thinner than a quarter of a cell.** They were merged at the cell's own size, which the land forming needs but a drawn face does not, since its risers are in whole metres: beyond 4.4 km a face lost its thinner beds and beyond 8.7 km every face was one rock. The land forming still reads its own table, so no island changed.
- **The far sea and rivers stay drawn over a newly loaded chunk until its own water has been drawn.** They used to give way as soon as the chunk loaded, which left a row of chunks without water for a frame or more at speed.
- **The flora is that of the warm islands of southern Japan**, since that is what the eight reference islands are (`interesting-world/notes/real-vegetation.md`): laurel forest of shii and tabu with camellia beneath, valley forest of tall tabu, a low ridge wood, susuki grass and scrub where it is windy, and black pine over dune grass in a belt 50 m deep behind the shore. Beech, katsura, red pine, heather and podzol are gone. This sets aside the plan's cool-temperate setting, which matched none of the reference islands.
- **The forest is closed and has bushes under it.** Trees stand in 95% of the 6 m squares on the slopes, and a third of the squares have a bush beneath, drawn only near by. Crowns are 5 to 7 m across: wider ones closed the canopy better but drew half as many faces again.
- **Soils are those of southern Japan**: brown forest soil, red soil on old dry ground, black ash soil on the volcanic islands, with river silt, shore sand and stony wash as before.
- **Block faces come from an atlas**, `assets/blocks.png`, built by `tools/blocks.py` and compiled into the game. A tile is 16 pixels to the metre; a top face is turned by the block it lies on so a field does not repeat; far off the game shows the tile's average, so a hillside keeps its colour as it is approached. The owner can paint over any tile.
- **The pack is Pixel Perfection by XSSheep, CC BY-SA 4.0**, taken as the open-source game Mineclonia ships it, whose legal file states the licence; the pack's own page was not checked. Thirty tiles are in `assets/pixel-perfection/`, and `tools/blocks.py` recolours one to each material, so the atlas is an adaptation under the same licence (`assets/LICENSE.md`). Each rock, soil and grass now has a tile of its own from the same source (two, for mud, are by another author under CC0); only the broken forms of the rocks share two between them. The pack's own sandstone side is cut masonry and was not used.
- **Faces are a little brighter and richer than the colours in `MATERIALS`** (12% and 18%), since the first tiles read dark beside Minecraft's.
- **Picture and bench runs draw unseen.** With `--shot` or `--bench` the game opens no window and takes no focus; a bench waits for each frame to be drawn and then for the next refresh of a 120 Hz display, so a slow frame is late as it would be on screen. `--show` opens the window for the owner to watch.
- **A session opens on the first fair day from the March equinox on**, unless `--day=` names one. Step 10 drew the weather from the seed for day 80, which on the default island is a low grey deck; the owner judges the land by looking, and pictures from different days of work have to be comparable, so Claude changed the default when merging. The default island opens on day 95 under a fifth of cloud.
- **Steps 10, 12 and 14 were built side by side in their own checkouts and merged**; where two added to the same list both were kept. Step 12's deer live only on an island the sea has drowned by 100 m or more, so the default island has no trails.
- **A fall is as tall as the weak rock under its lip, and only a real stream makes one.** Step 11 let a fall drop to the foot of the steep ground, which on the domes kind gave 65 falls over 30 m, one of 322 m, and slot gorges sawn down every dome flank by spring brooks. Claude changed two things when merging: a fall stops at the top of the next strong bed beneath its lip, and a stream must drain 0.12 km² to wear one back (knickpoints stall below 0.1 to 1 km², Crosby & Whipple 2006). The domes island now has 10 falls over 30 m, the tallest 60 m; the default island keeps 9, the tallest 97 m. Smaller brooks step down the face as before.
- **A place a person comes upon earns its name without being seen from afar.** Step 13 scored every candidate by how much of the ground 1 to 2 km round sees it, which left the default island one named place and gave no fall, cave or old wood a name anywhere. Claude changed it when merging: falls, sea caves, shelters, notches, old woods and springs are judged by how extreme they are alone. Islands now have one to four places, where the plan hoped for eight to twelve; the default island has Tabu Tarn and Three Falls.
- **Seed 7 stays a raised island.** It is the most livable kind and now has one landing. The ground bench from its start now covers 53 m, where it covered 60.
- **The swelling stands as the cause of volcanic sea cliffs** until the owner looks and says otherwise. It reuses the uplift and adds nothing, its figures fall inside the real ranges, and the only other cause tried gave shores of 17 to 43 m. It is a stand-in: real cones are cut back by waves through many stands of the sea, and no way to drop it has been found: a cliff that keeps its face once the sea has left it was tried on the ridge kind and added little.
- **Left for the owner's eye, not tuned by figures**: craters and domes that may read as drawn, and volcanic crests two to three times sharper than their references. Step 4 follows.
- **Step 4's six local fields are built** (`foundations.md` section 8, "Step 4, as built"), and the choices in them are these:
- **The wind blows from the swell's bearing.** The swell is raised by the wind, so the shores the sea cuts into cliffs are the ones salt and wind scour. A separate draw could put heath on a sheltered, uncut shore. When the archipelago brings a world wind, the swell should follow from it.
- **The island lies at 30° N**, held in the region record. That is where today's sun already stands (60° high at noon on an equinox), and the sun now reads it, so nothing on screen moved. The climate design recommends 40° N, which is step 10's to choose; it would move sky and sunlight together.
- **Hollow or humped is measured against the ground in a square about 200 m across.** Smaller shows only gullies; 400 m makes whole valley sides hollows. At 200 m each valley floor and each spur between streams reads, about the size of a stand of trees.
- **Units**: facing in degrees from north, hump in metres, distance to the sea in metres, sunlight against flat ground (0.15 to 1.11), exposure from 0 to 1, cold pool in metres over the stream or sea a cell drains to. The `cold` overlay paints a pool 50 m deep, within the 30 to 100 m the climate design guesses for a still night.
- **Exposure adds the hump and salt to the upwind rise by guessed weights**: half from flat ground, minus twice the steepest rise toward the wind, plus a quarter for every 10 m of hump, and salt combined as a second chance of exposure. They were set by looking at three maps, not from any measurement.
- **The first half of step 5 is built**: the rules that exist written as rows, nothing visible changed, and `--why=` (`foundations.md` section 8, "Step 5, first half, as built"). The choices in it are these:
- **What covers the ground is an ordered list, not a race.** The first row whose conditions hold wins (river gravel, sand, loose rock, bare rock, grass), as the old code chose. The weighted race in `kinds-and-places.md` is left for the plant communities, whose rows truly compete for the same ground.
- **The sand line and the steepness soil holds are fields** (`beach`, `too-steep`), each with its patchy noise inside, so a row stays a plain range on a named field.
- **The forest density stays a formula** until the plant communities replace it. It is a sum, which windows that multiply cannot express; `--why` reports its terms and the map paints it as `woods`.
- **Fields and overlays are one table.** Every field can be painted, and the old overlays keep their names. Three of their maps differ from before by one colour level in at most four values of three million.
- **`--why` reads the block under the point**, at the 1 m cells the game draws beside the player, and names a nearest miss only within the field's usual span: a sand line 170 m below a cliff top is not a near miss.
- **The second half of step 5 is built**: soil, five plant communities and four species (`foundations.md` section 8, "Step 5, second half, as built"). The choices in it are these:
- **Five communities, each a row that competes for ground**: valley floor wood, slope forest, ridge pine, scrub and heath, coast strand. Each has a weight, a patch size and hosts, and brings a tree density, its species' shares and a ground cover. The slope forest has no host and takes whatever the others do not win.
- **Their edges come from the race and a small shift**, not from a majority filter: the community is read up to about 24 m off by noise, so a boundary wanders over 10 to 50 m. The maps on seven kinds showed no confetti and no edges along contour lines.
- **A weight is a chance.** A community whose conditions fully hold still loses some of its ground to the slope forest in patches, so crests are part pine and part beech.
- **Heath and scrub where exposure is over 0.8.** That gives 11 to 17% of the land on every kind, under the fifth Claude set as the most it should take on a livable kind, and the exposure field is unchanged.
- **Four species**: katsura (broad, light green), beech (round, mid green, grey trunk), pine (flat top on a red bole, dark blue-green), and a low olive scrub. Colours are true hues pushed apart so a community's edge reads from a ridge.
- **Tree sizes stay near the old 8 to 14 m** (scrub 2 to 4 m) until the tree grower in step 8 brings true heights. *Overtaken in step 7: canopy trees now have their real heights.*
- **Soil depth is a field of its own** from the hump, wetness, slope, how weak the rock is and nearness to a stream, at least 0.3 m on humps. **Soil kind is an ordered list**: river silt over gravel, shore sand, stony wash on slopes over 33°, podzol on dry humps, brown earth elsewhere. Under the cover lies a block for each metre or part of one, so most banks show one or two blocks of soil over the rock.
- **No soil reads the rock's chemistry yet**, so the volcanic islands' crests have podzol where real ones have dark ash soils.
- **A field asked at the grid's own cell size reads the cell's value**, which made the race three times faster and changed nothing else drawn.
- **The start moved** from the east side to a river bank on the south coast terrace, since the old bank now has a tree within 6 m; the ground bench covers 59 m.
- **Step 6, the landslide and its lake, is built** (`foundations.md` section 8, "Step 6, as built"). The choices in it are these:
- **One slide an island, where its host holds best**: a slope at 0.9 or more of the steepest its rock holds, a bed at least 0.3 stronger over a weaker one within 50 m of the surface, a valley below draining 0.5 to 5 km², and 60 m or more of relief above that valley's stream, each fading over a margin. The seed only breaks near ties. On 21 islands (seven kinds, three seeds) 20 have a host.
- **The slide happens after the history ends, then the land wears for its age** in three steps, with the water behind the debris kept as a lake. Inside the history the erosion fills every hollow at once, and keeping hollows for the whole forming would change every island. The wear stands the scar's head back to what its rock holds and lets the stream cut its outlet. What streams carry into the lake is not yet laid in it.
- **Its age is drawn between 50 and 3,000 years**, evenly in its logarithm, so a bit under half the islands have a slide young enough to show raw rock and pioneer plants. Each seed draws the same age on every kind.
- **The scar runs from the host down toward the valley's stream, 200 to 600 m long**: a spoon as deep as the cap and the weak bed under it, steep at its head and sides. Only ground nearly as steep as at its head gives way, and nothing goes below the valley floor. Three other shapes were tried and dropped: centred on the host cell, it cut through the crest behind; reaching the valley floor everywhere, it dug pits in the gentle valley side; on a plane from under the head to the valley floor (Culmann), it took almost nothing from concave slopes.
- **The debris comes to rest under a surface falling 8 to 14 cm a metre from the scar's foot**, three times faster back toward the scar and half again across its path. It holds what slid, swollen by 15 to 30%. Hummocks are twice as wide as the slab was thick and up to its thickness high, scattered beyond the front as well. On the 16 m grid nothing smaller than about 50 m shows.
- **A lake is water a stream runs into, and it spills; a pond has no stream, and it seeps.** Whether the water lies over the debris does not decide it: that first rule called the dammed lakes ponds. The level sits at a block's top just under the lowest spill, as a river's pools do. The stream leaving a lake starts at its outlet with its water below the lake's.
- **Near the player, a lake's water stands over its own 16 m cells and the cells beside them**, wherever the ground is below the level. Beyond those, ground that would let it out is raised into a bank a block above the water, falling away at about 35°. A flat crest one cell out drew straight shelves along the grid, and so did a raised ring a cell wider.
- **Far away a lake is a quad at its level over the same cells**, added to the rivers' strip, with its bed drawn flat a metre under it on coarse cells.
- **Only hollows the slide made hold water, and none on a fallen crater's floor**, where the forming already sinks it.
- **Pioneers on ground the slide laid bare**: susuki grass alone under about 30 years, alder scrub to about 150, and the forest back by about 300 years, through two community rows on the field `disturbed`. The alder is a new species that reuses the camellia's grey bark and the scrub's leaves, so no tile was added. The scar is bare rock until 0.15 m of soil has weathered on it, at 0.4 m a thousand years (a guess). Debris starts with 0.3 m of soil.
- **The slide after the fixes** (`foundations.md` section 8, "Step 6, as built", first list): a breached lake drains; hollows that share a shore are one lake; the scar is wider and the debris runs out further, so 17 of 20 slides dam a lake; blocks of the cap lie on the debris; ages are 30 to 1,000 years and each kind of island draws its own; a young wood of tabu follows the alder to about 400 years; a lake under 100 years old has the trunks of its drowned trees; deep fresh water is dark and the far lake matches the near.
- **The start is never on a bank a lake has drowned.** The slide first moved the start to a spot under 1.5 m of water in the small lake below its dam; the start now skips such spots and is back on the east side (near 2,580, -250), where the ground bench covers 55 m.
- **Step 7, stands with ages, is built** (`foundations.md` section 8, "Step 7, as built"). The choices in it are these:
- **Typhoons set a stand's age, and they come more often to ground open to the wind.** Each stand draws the years since its canopy was last thrown, as a waiting time whose mean runs from 2,000 years on fully sheltered ground to 40 on fully exposed ground. Ground a slide laid bare takes the slide's age. The default island comes out 11% young (under 50 years), 19% middle-aged and 70% old (200 years and more); the other kinds are 6 to 24% young.
- **Stands are patches round middles about 140 m apart**, each reaching as far as its own draw says, with edges that wander up to 30 m. Half the land lies in stands larger than 2.7 ha, and the largest is about 6 ha. Trees read their stand from up to 12 m away, so two stands mix along their edge.
- **Canopy trees stand 2.5 m apart in a new stand and 6.5 m in an old one**, not 10 to 12 m as the vegetation design said. Old shii forest has some 200 to 300 canopy trees a hectare, and with crowns no wider than 9 blocks, trees 10 m apart would leave the canopy open.
- **Trees grow on a 3 m grid and the strongest wins.** Of the trees whose crowns would meet at the stand's spacing, the most vigorous takes the canopy; one shaded only from the side may stand between, smaller; the rest are small trees or bushes under the canopy, as often as the community's bushes, or nothing. Vigour is a draw, not height, so now and then a camellia holds a place in the canopy beside taller shii.
- **Trees grow with their stand**: about 35% of full height when new, 60% at 20 years and nearly full by 100. Trees between the canopy reach two-thirds of that. Canopy trees 18 m and taller stand on trunks two blocks across.
- **Gaps take 15% of an old stand**, each 3 to 8 m in radius, where the trees fell downwind (the swell's bearing, give or take 35°). Three in four canopy trees in a gap lie fallen and one stands dead; everything else in it is young growth 2 to 10 m tall. Young stands have no gaps.
- **A fallen trunk is a line of bark blocks one high**, as long as the tree was tall, with its root plate as a wall of earth three blocks wide beside a one-block pit.
- **Small trees, dead trunks and fallen trunks are drawn only near by.** Canopy trees and those between them are drawn out to 1.1 km; beyond that the canopy's height and cover follow the stand's age, and gaps are bare.
- **Canopy trees have their real heights, on crowns no wider**: shii 13 to 19 m, tabu 14 to 20, black pine 10 to 15. A tree's leaves begin at least 3 m up, a sapling's over a walker's head, and bushes are 1 to 2 m. Claude made this change on review: with trees held under 15 m the old wood was cluttered under a ceiling at head height. It takes the heights out of step 8, which keeps the tree forms.
- **Beyond half a kilometre only canopy trees are drawn singly, and the second and third shadow cascades take turns**, to pay for the denser woods: the forest flight's frame had gone from 9.3 to 16.4 ms and is back at 8.6.
- **The start**: no canopy tree within 6 m and no small one within 2 m, or within 3 m where every bank is wooded closer than 6. The default start did not move (east coast, near 2,640, -254), but the ground bench now walks into a bush after 26 m, where it covered 55. The worn island had no bank clear of trees and started at its middle; it now starts on a bank.
- **Step 8, the tree grower, is built** (`foundations.md` section 8, "Step 8, as built"). The choices in it are these:
- **Every tree is grown by one procedure from its species' row**: stems, a fork into limbs (or a pine's leader with level tiers), a lobe of leaves at each limb's end. A species is changed by its row, never by its own code.
- **A crown is a cluster of lobes inside the species' envelope**, and the far crowns are that envelope. The near tree is lumpier than the far box, but the same size and in the same place.
- **Crowns reach toward the open**: away from stronger neighbours, toward a gap, down the slope, and downwind where exposed. A pine on the windward shore leans and carries its plates downwind; bushes do not lean, and the wind only cuts them lower on the windward side.
- **A crown's radius is up to 0.75 of the stand's spacing**, 5 m in an old stand (it was 4), and tabu always takes the widest. Real crowns reach 15 m across; wider ones cost more faces than the step could pay for.
- **Trees between the canopy trees are one crown on a stem, and shii and tabu have three to five limbs**, to keep the faces drawn within 15% of before. Grown limbs on the smaller trees, and four to six on the big ones, were dropped for that.
- **Leaves stay 3 m over the ground under them, and a stem is straight for its lowest third**, so the woods stay walkable when a crown leans out over lower ground or a clump splays.
- **Small trees are taller, toward their real sizes**: camellia 5 to 9 m (was 5 to 7), hisakaki 4 to 8 (4 to 7), alder 6 to 10 (5 to 8). With leaves starting 3 m up, a 6 m tree had too little crown to look like a tree. The alder's crown is rounded, as the sources describe, not narrow.
- **Bark shows bark on every face.** The bark blocks' top and bottom now use the artist's bark tile in place of the log's cut end, which showed on every step of a slanting limb and on top of every fallen trunk.
- **The ground bench from the start covers about 20 m**, where it covered 26: it ends in the same kind of bush, which is a little fuller now.

**2026-11-11, Claude's call**

- **The first rock story row to be written is "layered, gently tilted"**: five kinds (mudstone, siltstone, grey sandstone, grit, limestone), with the sequence, tilt and folds drawn from the seed. It is the row the experiment already showed working. More rows follow in Phase 2, and the seed then picks among them.
- **Rock is built before lakes.** This is an order of work: the first landslide waits for step 6, so it falls where a strong bed lies over a weak one.
- **The history rows wait for step 3.** Until then every seed has today's one history.
- **Step 3 built four island kinds (ridge, cone, worn, raised), and the seed draws among them** with a plain key, so the default seed 7 is now a cone island. Every row has ranges. The owner has not yet said whether "raised" stays.
- **The sea cuts each shore by how much open sea lies round it and toward a swell whose bearing the seed draws**; sheltered shores are not cut. Strong rock stands to 60° and creeps less. Soil and trees hold to about 45° on any rock, and only steeper faces are bare.
- **Livable ground is ground no steeper than 20°, at least 2 m above the sea, in a patch of a hectare or more**, set from the OpenStreetMap buildings on the eight real islands' grids: 20° holds 85 to 93% of the buildings on six of them and 57% on Mikurajima, whose village stands at a median 17° and 107 m. Height, distance from the sea and distance from a stream did not tell the villages from the rest of the land. A sheltered landing is shore under 5 m where the sea fills less than a third of the square a kilometre across around it, with livable ground within 100 m. Both print at start-up beside the real islands' figures.
- **What the streams carry down settles where the sea is sheltered** and builds a flat 4 m over the sea out from the mouth; each row has a range for the share that stays (`silt`), and every history now ends with the last rise of the sea followed by 5,000 to 8,000 years in which the bay heads fill.
- **A fifth kind, "inlets"**: the ridge island, larger and rising more slowly, drowned by a 115 to 120 m rise of the sea, after Tsushima and Chichijima.
- **Kinds are drawn by weight**: ridge 3, inlets 3, worn 2, raised 2, domes 2, cone 1, crater 1, so the inhospitable cone and crater are each drawn about one time in fourteen. Seed 7 draws a raised island.
- **Volcanic islands are histories of vents.** A vent builds rock over a phase (a cone of runny lava and ash, or a dome of stiff lava, by the row's `form`), its top can fall in to leave a closed crater, and magma swells it from inside. The cone row is rewritten this way, and two kinds are new: "crater" after Aogashima and "domes" after Kōzushima.
- **The swelling is what gives a volcanic island its sea cliffs.** A vent that builds and then rests got none in this forming: the waves break on the platform they cut and the streams grade the coast down as fast as it retreats. The swelling reuses the uplift. The owner may prefer another cause.
- **A crater floor drinks its water** at its lowest point, so it is dry closed ground with no lake and no stream over the rim. A floor that ends below the sea becomes sea.
- **The kind names its rock story**, and there are three: the layered one, "lava and ash" (basalt and scoria) and "pale lava and pumice" (rhyolite and tuff). The volcanic beds lie over what the vents built.
- **The open sea floor is 200 m down** beyond a shelf about 500 m wide, so vents build from a real floor.

**2026-11-10, Claude's call**

- **SDL3 with its GPU API, shaders written in Metal's language and compiled at start-up.** It is the least code and needs no shader build step. Measured: 120 FPS at 2560 × 1440 with about 2 ms of our own work per frame. If frame pacing cannot be held or diagnosed, the fallback is Metal directly.
- **The world is sampled at a cell size.** See `adr/0001`.
- **Volume near, columns far.** The nearest 256 m is a true block volume, so digging, building and overhangs work. Beyond that the ground is columns.
- **Water is a depth in each column**, standing at its true level in fractions of a metre, not a block.
- **Faces are lit by the slope they are cut from.** See `adr/0002`.
- **Leaves and trunks are solid blocks.**

## Assumed unless the owner objects

- Odin, on Apple Silicon macOS.
- First person.
- One block is one metre, and the surface stays blocky.
- The same seed always makes the same world.

## Open

These are the directions the first build exists to test. Each is the owner's to decide after looking.

### 1. How real is "real"?

- **A. Natural truth first**: everything has a simulated cause.
- **B. Simulate the why, design the what**: simulation where it produces the look, designed landforms below that, chosen by the simulated context.
- **C. Designed throughout**, as ReTerraForged is.

The island as built is B: valleys, drainage, wetness and rock hardness are simulated; channels, bars, pools and trees are designed from them. *Recommendation: confirm B*, and use it for what comes next: rock outcrops and cliffs where the simulation says the slope is steep and the rock hard, lakes where it leaves a hollow.

### 2. What is missing from the land?

The simulation makes valleys and rivers. It does not yet make the other things in `ideas.md`:

- **Lakes.** Hollows are filled as the land forms, so every river runs to the sea.
- **Rock.** Steep ground is painted as stone, but there are no cliffs, ledges or outcrops, and ridges are rounded.
- **Waterfalls taller than a metre**, gorges, and anything with an overhang.
- **Forest structure.** One kind of tree, thick where the ground is wet.

*Recommendation: rock next.* It is what the mountains most lack, and cliffs along a river make the first gorge.

Research on 2026-11-11 (`interesting-world.md`) supports this and sharpens it: the land forming needs beds of hard and soft rock, which an experiment showed producing scarps, ridges and a varied coast; cliffs then have to be expressed in blocks, and the forest has to vary with the ground, or the change shows on the map and not on a walk. Its section 8 proposes an order of ten steps.

### 3. What should it look like?

The first build has a look: flat-coloured blocks with fine grain, hard sun shadows, soft corner shading, haze. Open choices include how saturated and how contrasty, drawn textures or none, softer shadows, clouds, and how trees are shaped. The owner's references are in `reference/visual/`.

### 4. What does the player do?

Walking, flying, breaking and placing blocks exist. Open: whether climbing a one-block step automatically feels right, swimming, what "inspecting causes" looks like, and when the top-down view arrives.

### 5. What status do the old scale targets have?

1,000 km world, 10 km views, 120 FPS at 2560 × 1440, creation within four minutes. The game draws to about 16 km and holds 120 FPS. The world is one island in an 8 km square, formed in about a second.

*Recommendation: treat 120 FPS and the long view as standing requirements now that they hold. Grow the world only when one island is good to walk across; the simulation's cost grows with area, so a 30 km island at this detail would take about fifteen seconds, and 1,000 km needs coarser cells far from the player.*

### 6. How do we work?

Proposed, each line answering a recorded failure:

- The owner judges everything visual by looking at the running game. Claude shows and asks.
- One change at a time, ending in something the owner can run in under a minute.
- Accepted work is committed the same day.
- Nothing is kept compatible until the owner declares a world worth keeping.
- An experiment is a separate program that is folded into the game or deleted. The game has one way of generating the world at any time.
- Tests cover logic that breaks silently, and never stand in for looking.

### 7. What is the island made of, and where is it?

Raised by `interesting-world.md`, section 9. The answers decide which landforms, caves and plants are honest.

- **Rock.** Layered rock with a hard cap over soft beds (scarps, benches, landslide lakes); two domains split by a fault; or lava flows (columns, sea caves, stepped hillsides). *Recommendation: layered rock first, a second domain later.*
- **Limestone.** It is the only honest route to long caves, sinkholes and springs. Without it, caves are sea caves, rock shelters and gaps among fallen blocks.
- **Climate.** *Recommendation: cool-temperate and oceanic, after Shirakami and Jūniko*: beech forest, about eight tree forms in eleven plant communities, no ice-age landforms.
- **Exaggeration.** Whether to steepen or compress the land beyond true proportions. *Recommendation: decide after rock, cliffs and the first plant communities have been walked.*

### 8. The wider world

Raised by `foundations.md`, section 9, which lists twelve decisions with a recommendation each. The ones that shape the most:

- **The fifteen foundational decisions** in its section 3 (kinds as rows of data, one rock function, a region's recipe as a record, features that record cause and age, fields as a base plus terms, and the rest). *Recommendation: adopt them as each first becomes real in a step, and record each here then.*
- **The end shape of the world.** An ocean of islands, or a mainland with islands off its coast inside known lands about 300 km across. *Recommendation: the mainland, which the fantasy vision needs, if an early test shows that regions can join along a drainage divide without a visible seam.*
- **Cold to hot.** A true slice of about nine degrees of latitude, or 1,000 km standing for about thirty. *Recommendation: thirty.*
- **Rock before lakes.** *Recommendation: yes*, so the first landslide sits on its real host.
- **People and the fantastic.** *Recommendation: the first island is wild; people arrive with the archipelago, first as ruins; the fantastic enters only as a cause with a source, a reach and an age, at most one marvel per region.*
- **The order of work.** Phase 1 is sixteen changes on one island (`foundations.md`, section 8). It replaces the ten steps in `interesting-world.md` section 8, which it contains.

### 9. Closing the gap to real islands

*The first five items were built on 2026-11-11 as the land-forming step (`foundations.md`, section 8, "The land-forming step, as built"). Still open below: kinds named after real islands, people sooner, larger regions, and the comparison tool. New from the step: the ridge and raised islands had no sheltered landing, and whether the swelling of a cone is the right cause for its sea cliffs; both were settled as Claude's call on 2026-11-12 (above) and are the owner's to overturn.*

Raised by `interesting-world/notes/real-islands.md` (2026-11-11), which compared eight real Japanese islands with 32 generated ones on the game's own grid and renderer. The generated land is not close. In order of how much shows:

- **The coast.** Real islands meet the sea in cliffs (a median 60 to 117 m high within 100 m of the shore) and are steepest at the sea; ours meet it on a low apron and are gentlest there. The plan builds the coast in step 15, in blocks, on land already formed. *Recommendation: move coast retreat into the land forming and do it next.*
- **The island's mass.** Real islands have 5 to 16% of their land under 50 m; ours 31 to 58%. *Recommendation: change the uplift shape in the kind rows in the same step.*
- **Steepness.** Nothing formed is steeper than about 52°; real volcanic islands have 0.8 to 2.9% of their land over 60°.
- **Ridges and valleys.** Real crests are two to four times sharper and valleys about twice as deep.
- **Livable ground.** Decided in principle above; open in detail. The steep real islands have almost none (0.0 to 3.9% of land under 3°), Kikaijima has 55%, and our kinds have 1 to 16% spread as a ring round the shore. *Recommendation: when the coast is cut into cliffs, keep gentle ground gathered where it has a cause (a bay head, a valley floor, a river-mouth flat, a terrace, a plateau top), give each kind row a range for how much, weight the draw of kinds toward the livable ones, and add livable ground and sheltered landings to the printed figures.* The thresholds and the weights are the owner's to set by looking.
- **Kinds after real islands.** Our four kinds match none of the real ones closely, and the real set has kinds we lack: a dome-and-bay volcanic island, a crater island, a coast of long inlets, a terrace island that is mostly flat. *Recommendation: each kind row names the real islands it stands for, their figures are its targets, and the next comparison adds livable islands of this size.*
- **What is bare.** A real island loaded into the game turns to bare rock where it is really forest, because ground steeper than about 36° is stripped. The plan fixes this in step 5. *Recommendation: fix it with the land-forming step, since steeper land without it will look like a quarry.*
- **People sooner?** The plan keeps the first island wild. One landing and hamlet placed by the livable-ground field would test that field. *Recommendation: decide after the coast and the livable-ground figure exist.*
- **Larger regions for some kinds?** Most livable real islands are larger than 8 km. A 16 km region forms in 4.8 s. *Recommendation: try one kind at 16 km when the kinds are reshaped.*
- **Keep the comparison as a tool?** A `--real=` option that loads a real island in place of a formed one exists in a scratch build. *Recommendation: fold it in, with the figures, since real islands are now the yardstick.*

### 10. Is a kind a shape or a history?

*Taken up on 2026-11-11: the inlets kind and the vent are built, and the three volcanic kinds are histories of events. The layered kinds still have shape fields. Sediment is in, as silt at bay heads.*

Raised by the owner (2026-11-11): what stops a tectonics simulator from producing the kinds, so that none is written by hand? The answer and one test are in `foundations.md` section 11, "A kind as a history, not a shape".

- **What a kind row says.** Today a row describes the result (a peak, a range's axis and bend). *Recommendation: a row becomes a list of events over general processes, and the shape fields mostly go. Do it one kind at a time, as each process arrives.*
- **Which processes to add.** The four real kinds we lack need two: the sea cutting the coast, and a vent that builds rock and collapses. *Recommendation: the sea first, as already proposed in question 9; the vent after it, ahead of step 4, if the owner wants volcanic islands to look built.* That two are enough is untested.
- **The inlet coast.** It needs no new process. Raising the sea 116 m at the end of the ridge island's history took the sea inside its outline from 4% to 34% (Tsushima 60%), and cost two thirds of its land. The test was not kept. *Recommendation: put it in as its own row with a larger outline, and try that row at 16 km.* The owner has not seen it in the game.
- **A plate simulation.** It would choose and place kinds, which the stand-in in `foundations/world-frame.md` D4 already does. *Recommendation: keep it deferred until the stand-in makes a contradiction the owner can see.*
- **Sediment.** A real inlet's head is a flat of river sediment, and that is where its village stands. The forming deposits nothing, and the plan leaves deposition to Phase 2. *Recommendation: decide when the livable-ground figure exists and shows what the inlet heads lack.*

## Deferred on purpose

Saves and world formats, the atlas, menus and interface, final world size, the plant and biome catalogue, seasons and weather, underground structure, inventory, and everything in the living-world and colony horizons.
