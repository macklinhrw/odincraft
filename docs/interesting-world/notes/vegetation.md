# Vegetation for a small cool-temperate island: variety, causes, structure, placement

Research notes, 2026-11-11. Every factual claim carries its source. Lines marked **(inference)** are my reasoning, not a source's.

## Key takeaways

1. **Few tree species per stand.** At 50° latitude a hectare holds about 4 tree species on average (https://www.labmanager.com/complete-world-map-of-tree-diversity-2510), and a 2 ha temperate plot in Michigan holds 10 to 15 (https://www.livescience.com/42394-why-one-hectare-of-rainforest-grows-more-tree-species-than-us.html). Japan Sea beech forest is close to a single-species canopy (https://springerlink.bibliotecabuap.elogim.com/content/pdf/10.1007/BF02805212.pdf). Variety at walking scale comes from structure and from the changes between communities, not from the number of species.
2. **Shirakami has one canopy tree, beech (*Fagus crenata*), above a dense evergreen dwarf bamboo, *Sasa kurilensis*.** The whole site has more than 500 plant species (https://www.thesalmons.org/lynn/wh-wcmc/Japan%20-%20Shirakami-Sanchi.pdf). Valleys, ridges, landslides and the edges of water carry other trees.
3. **The ridge-to-valley gradient is the main sorter at a scale of 100 m.** In one Japanese basin, wingnut, katsura and ash (*Pterocarya*, *Cercidiphyllum*, *Fraxinus*) fill the valley floor, beech the side slopes and hemlock (*Tsuga*) the ridge (https://link.springer.com/chapter/10.1007/978-981-15-3009-8_4). The fields the generator already has (wetness, slope, convexity) express this directly.
4. **On an oceanic island a few hundred metres high, exposure sets the tree limit, not temperature.** Treelines are lower near coasts and on small mountain masses (https://epub.uni-bayreuth.de/7260/1/Global%20Ecology%20and%20Biogeography%20-%202023%20-%20Kienle%20-%20Mass%20elevation%20effect%20and%20continentality%20have%20a%20stronger%20impact%20on%20global.pdf). In the Faroes, wind and salt spray limit woody plants (https://ojs.setur.fo/index.php/frit/article/download/756/829).
5. **Old forest is patchy.** Gaps cover 13 to 16 % of old beech forest (https://jfs.agriculturejournals.cz/pdfs/jfs/2005/10/02.pdf; https://link.springer.com/chapter/10.1007/978-981-15-3009-8_3). Gaps under 500 m² drive most of its change (https://dlib.si/stream/URN:NBN:SI:DOC-VLMSE8A9/7ca3ec42-fade-4c18-a308-9b38b086efed/PDF). Rare large disturbances such as landslides and floods reset patches to pioneer trees.
6. **Dead wood is a large, visible part of an old wood.** European beech reserves average 130 m³/ha of dead wood, with a range up to 550 m³/ha, and more of it lies on the ground than stands (https://www.erdorezervatum.hu/sites/default/files/Christensen_etal_2005.pdf). Root-plate mounds can stay more than 1 m tall for 50 years (https://harvardforest2.fas.harvard.edu/asp/hf/php/reu/reu_abstract_view.php?id=416).
7. **Stem density falls about twentyfold with age.** About 1,480 stems/ha in a young stand become about 490 at 50 years and about 75 in old growth (https://bio.libretexts.org/Bookshelves/Botany/Forest_Measurements_-_An_Applied_Approach_(DeYoung)/05%3A_Stand_Characteristics/05.5%3A_Stand_Growth_and_Development_Over_Time, converted from per acre). One fixed spacing everywhere is the main reason a wood looks uniform **(inference)**.
8. **Shipped games place each plant layer from a density map.** Horizon Zero Dawn builds layers from 2D world maps (flow, deposition, cavity, painted masks), turns density into positions with dither patterns scaled to each plant's footprint, and resolves overlaps between layers with a two-sided threshold. That covers 500+ asset types (https://www.guerrilla-games.com/media/News/Files/GDC2017_VanMuijden_GPUBasedProceduralPlacementInHorizonZeroDawn.pdf).
9. **A data-driven branching trunk generator is enough for 1 m blocks.** Vintage Story defines every species from about a dozen numbers per branch level: width loss, vertical angle and its change per step, gravity drag, branch start, spacing, count, angle and width ratio. Width thresholds pick log, branchy leaf or leaf blocks (https://wiki.vintagestory.at/index.php/Modding:Trees).
10. **Proposed cast (inference):** 6 to 8 canopy trees, 3 to 4 understory trees, 4 to 6 shrubs, 5 to 7 ground-layer types, 4 to 5 wetland plants, arranged in about 11 communities (table at the end).

---

## 1. How many kinds

**Stand (1 ha).** A global model gives about 98 species/ha at the equator, falling to about 4 species/ha at 50° N and S (https://www.labmanager.com/complete-world-map-of-tree-diversity-2510). The richest temperate forests, in south-central Chile, reach up to 50/ha (same source). A 2 ha Michigan plot holds 10 to 15 species (https://www.livescience.com/42394-why-one-hectare-of-rainforest-grows-more-tree-species-than-us.html).

**Japan Sea beech forest.** Beech dominates, so species richness is lower than in Pacific-side beech forest. Shimano's review lists *Acer shirasawanum*, *Stewartia pseudocamellia*, *Symplocos coreana* and *Acer palmatum* var. *amoenum* as characteristic of this type (https://springerlink.bibliotecabuap.elogim.com/content/pdf/10.1007/BF02805212.pdf).

**Shirakami-Sanchi.** The protected area runs from 300 to 1,243 m and is mostly granite. More than half of it is deep valleys with slopes over 30°. Snow is heavy. It holds more than 500 plant species. *Clethra barbinervis* and *Magnolia salicifolia* are common understory trees (https://www.thesalmons.org/lynn/wh-wcmc/Japan%20-%20Shirakami-Sanchi.pdf). The Ministry of the Environment names *Sasa kurilensis* as the ground vegetation that reflects the snow (https://www.env.go.jp/nature/isan/worldheritage/en/shirakami/uiversal/index.html). Other species reported for the region:

- Understory trees: *Magnolia obovata*, *Betula grossa* (https://link.springer.com/article/10.1007/BF02762528).
- Shrubs and small trees: *Hamamelis japonica*, *Viburnum furcatum*, *Weigela hortensis*.
- Herbs: *Petasites japonicus* (giant butterbur), *Lysimachia clethroides*, *Paris tetraphylla*, *Disporum smilacinum*, *Impatiens textorii* (https://nature.hirosaki-u.ac.jp/shirakami/english/study/plants.html).

At the comparable Daisen beech forest, *Quercus crispula* and *Acer pictum* subsp. *mono* grow with the beech, above shrubs of *Lindera umbellata*, *Acer rufinerve* and *Viburnum furcatum* (https://www.kyoto-u.ac.jp/cutting-edge/environment/page12.html). An old map legend for the area also lists *Pinus parviflora*–*P. densiflora* forest, *Thuja standishii* communities and a *Sasa*–*Betula ermanii* community (https://www.frontiersin.org/api/v4/articles/1306062/file/Data_Sheet_2.docx/1306062_supplementary-materials_datasheets_2_docx/1). I could not verify where these sit in the terrain. They are very likely ridge and rock communities **(inference)**.

**Juniko.** The 33 lakes and marshes sit in beech forest. Radiocarbon dating of drowned snags shows that large landslides dammed valleys before 1704. The 1704 earthquake then reactivated the slide (https://nature.hirosaki-u.ac.jp/wp-content/uploads/2023/04/A4_leaflet.pdf; https://confit.atlas.jp/guide/event/jpgu2022/subject/HDS07-P02/date). The reference place is a landslide landscape: hummocks, dammed hollows and drowned trees.

**Yakushima: zonation on one island.** The island rises to 1,936 m and gets about 4,000 mm of rain a year on the plains and about 10,000 mm in the mountains (https://www.env.go.jp/nature/isan/worldheritage/english/yakushima/about.html). Its vegetation runs from the coast through evergreen broadleaf forest, Japanese cedar forest and cold-temperate bamboo grassland with high moor, to subalpine scrub (https://www.env.go.jp/nature/isan/worldheritage/pamph_en10.pdf).

**Rank-abundance and island totals.** I found no direct source giving rank-abundance curves for temperate stands, or total tree species counts for a small cool-temperate island of a few km². Both are unverified. The pattern of one dominant plus a few associates holds in the Japanese beech sources above.

**Minimal cast (inference).** Most of the island is one dominant canopy tree. Four to six other canopy trees each own one terrain niche: valley floor, ridge or rock, pioneer patches, coast, wetland edge, and an upper exposed belt. Add a few understory trees and shrubs, and a ground layer that is mostly one thing (dwarf bamboo or bracken) with herbs in damp places.

## 2. What decides which community grows where

Each driver below is followed by a rule the generator could evaluate. All the rules are **inference** built on the cited pattern.

**Topographic moisture (catena).** Whittaker's Smoky Mountains work found that the combination of elevation, topographic shape and aspect determines the vegetation (https://webharvest.gov/peth04/20041024045353/http://www.srs.fs.usda.gov/pubs/rpc/1999-12/rpc_99dec_03.pdf). At Coweeta, oaks and pitch pine belong to the convex upper slopes and ridges (same source). In Japan, the valley floor carries *Fraxinus platypoda*, *Cercidiphyllum japonicum* and *Pterocarya rhoifolia*, the side slopes beech and the ridges *Tsuga sieboldii*. *Pterocarya* takes alluvial fans and *Cercidiphyllum* V-shaped valleys (https://link.springer.com/chapter/10.1007/978-981-15-3009-8_4). On the snowy Japan Sea side, *Aesculus turbinata* joins *Pterocarya* in riparian forest (https://www.jstage.jst.go.jp/article/vegsci/18/2/18_KJ00006916481/_article/-char/en).
*Rule:* combine the wetness index (log of drainage area over slope) with plan curvature. Use the top decile and low slope for the valley floor, the middle for slope forest, and the bottom decile with convexity for ridge.

**Aspect.** Far Cry 5 grew denser forest where soil moisture is shaded from direct sun, on north sides (https://blog.playstation.com/2018/03/22/the-procedural-world-generation-of-far-cry-5/). Whittaker included aspect in his gradient (source above).
*Rule:* effective dryness = slope × cos(aspect − sun azimuth). Treat south-facing steep ground as one wetness class drier.

**Elevation and exposure.** Treeline rises with mountain mass and distance from the coast, because inland mountains have less cloud and more sun (Kienle et al. 2023, link above). In the Faroes, wind and the salt spray it carries are main factors shaping vegetation (https://ojs.setur.fo/index.php/frit/article/download/756/829). The Wikipedia summary says small isolated peaks and islands have lower vegetation belts than large ranges (https://en.wikipedia.org/wiki/Massenerhebung_effect). Wind as a direct cause there is unverified.
*Rule:* exposure = elevation/H + convexity + 1/(distance to sea) + facing the prevailing wind. Above a threshold, forest becomes low scrub, then heath or grass. The threshold falls toward the coast and on isolated summits.

**Soil and rock.** Serpentine soils are low in calcium and high in magnesium. Trees that grow tall elsewhere become dwarfed shrubs on them (https://www.fs.usda.gov/wildflowers/beauty/serpentines/adaptations.shtml). On the Outer Hebrides, natural woodland survives mainly on crags and on islands in lochs, out of reach of grazing (https://core.ac.uk/download/146448501.pdf).
*Rule:* treat hard rock with steep slope as thin soil, giving open rocky ground with stunted pine or juniper. Treat soft rock on gentle slopes as deep soil, giving tall forest. I could not verify a limestone-versus-acid contrast to cite.

**Riparian and floodplain.** Valley-bottom species need the large openings that rare floods and debris flows make (https://link.springer.com/chapter/10.1007/978-981-15-3009-8_6). The valley floor is a mosaic of debris-flow terraces, alluvial fans and talus (https://link.springer.com/chapter/10.1007/978-981-15-3009-8_3).
*Rule:* use distance to river under about 2 to 3 channel widths, together with height above the channel under about 2 m. Make the bands narrow and ragged.

**Wetlands and lake edges.** Vegetation forms zones by water depth around a lake. A gently shelving edge has wide, complex zones; a steep edge has narrow ones (https://conservationhandbooks.com/waterways-wetlands-introduction/waterway-and-wetland-ecology/the-productivity-scale/). The sequence runs from open water with floating-leaved plants, through reedswamp, then fen with sedges, to carr of alder and willow (https://en.wikipedia.org/wiki/Hydrosere; https://en.wikipedia.org/wiki/Carr_(landform)).
*Rule:* use water depth or height above the lake level. Below about −1.5 m is open water; −1.5 to −0.5 m floating leaves; −0.5 to +0.2 m reeds; +0.2 to +0.6 m sedge fen; +0.6 to +1.5 m alder or willow carr. The band width follows from the shore slope, so it comes for free. The depth thresholds are my estimates; I did not verify them.

**Coast.** Hokkaido dunes run from beach plants (*Mertensia*) through a foredune of *Elymus mollis* and a *Rosa rugosa* meadow to forest (https://eprints.lib.hokudai.ac.jp/repo/huscap/all/37090/1_75-109.pdf). On Japanese dunes, tree height, age and basal area rise with distance from the shore, and *Pinus thunbergii* forms the first tree belt (https://www.jstage.jst.go.jp/article/jale/28/1-2/28_13/_article/-char/en).
*Rule:* use distance to sea and height above sea. Below about 30 m inland, bare strand. From 30 to 100 m, dune grass and rose scrub. From 100 to 300 m, wind-cut pine whose height rises with distance. Cliffs get thrift-grass heath instead.

**Disturbance and succession.** Landslides involve larger areas than treefall gaps and can reduce the dominance of beech. Early-successional *Alnus hirsuta* has been used to date landslide stands (https://researchmap.jp/read0166249/published_papers/34609758/attachment_file.pdf). Hokkaido mudflow surfaces became near-pure stands of *Betula ermanii* and *Picea glehnii* (https://eprints.lib.hokudai.ac.jp/repo/huscap/all/21436/55(1)_P216-228.pdf).
*Rule:* paint disturbance patches with a 'years since disturbance' value. Under about 30 years: pioneers (alder, birch, willow). From 30 to 150 years: mixed. Older: the late dominant. Put landslide patches on steep slopes below scarps, and make them elongated downslope.

**Edges and ecotones.** At clearcut edges in old Douglas-fir forest, solar radiation reaches interior levels within 30 to 60 m, while humidity effects can extend beyond 240 m (https://idfg.idaho.gov/species/node/1495821).
*Rule (inference):* a visual boundary between communities should blend over 10 to 50 m, with noise in it, never as a sharp line. Forest edges get a 5 to 15 m band of shrubs and low branches.

## 3. Forest structure at eye level

**Layers.** Oliver and Larson give four stages of stand development: stand initiation, stem exclusion (very dense, dark, little understory), understory reinitiation, and old growth, in which herbs, shrubs and advance regeneration return (https://www.sfasilviculture.com/index.php/textbook/2-3-stand-dynamics-stand-structure).

**Density.**
- About 1,480 stems/ha as seedlings, about 490 at 50 years, about 75 in old growth (DeYoung text, link in takeaway 7).
- About 1,000 trees/ha at 30 to 50 years after disturbance (https://andrewsforest.oregonstate.edu/sites/default/files/lter/pubs/pdf/pub2329.pdf).
- Old Douglas-fir stands are far sparser than young ones (same source).

I could not verify stems/ha for *Fagus crenata* old growth.
*At block scale (inference):* mature canopy trees about 8 to 15 m apart (100 to 150 per ha) with saplings in the gaps; a young thicket at 3 to 4 m spacing.

**Gaps.**
- 16 % of Havešová and 14.6 % of Kyjov is gap, counting openings above two-thirds of stand height (https://jfs.agriculturejournals.cz/pdfs/jfs/2005/10/02.pdf).
- Old Japanese beech stands have larger and more gaps than developing ones (https://link.springer.com/article/10.1023/A:1009713002039).
- Gaps under 500 m² dominate (Slovenian study, link in takeaway 5).
-

*Rule (inference):* aim for about 15 % gap, with gap sizes drawn from an exponential distribution, mostly 50 to 500 m² (one or two fallen crowns). Fill gaps with Sasa or saplings.

**Crown shapes and shyness.** Crown shyness is the gap between neighbouring crowns of similar height. Wind abrasion explains part of it, light competition is another proposed cause, and there is no consensus (https://repository.si.edu/bitstream/handle/10088/17792/serc_Putz_etal_1984_AmMidlNat_112_24_28.pdf; https://daily.jstor.org/the-mysteries-of-crown-shyness). I did not find sources on open-grown versus forest-grown form or on trees leaning toward water. From general knowledge (unverified): open-grown trees keep low branches and wide crowns; forest-grown trees have long clear stems and small high crowns; edge and bank trees lean and grow asymmetric crowns toward light.

**Deadwood and the ground surface.**
- 130 m³/ha of dead wood on average, with a range to 550, and more lying than standing (https://www.erdorezervatum.hu/sites/default/files/Christensen_etal_2005.pdf).
- Unmanaged forest holds 10 to 20 times the dead wood of managed forest (same source).
- 11 % of mounds stayed over 1 m tall 50 years after a blowdown (https://harvardforest2.fas.harvard.edu/asp/hf/php/symposium/symposium_abstract_view.php?id=4053).

*Block scale (inference):* about 10 to 30 fallen logs per ha, some with a root plate and a pit beside it, plus 5 to 10 snags per ha.

**Open ground.** I found no source on bracken, heath or grassland types. On these islands, mire is the dominant land cover where trees are absent (https://www.oneearth.org/ecoregions/north-atlantic-moist-mixed-forests). Yakushima has bamboo grassland and moor above the forest (pamphlet above).

**What makes each 100 m different (inference):** a change of wetness class along the slope, a gap or log cluster every few hundred metres, patches of different age, rock outcrops on hard rock, a gully with different trees, Sasa continuous or broken. One scatter rule with one spacing removes all six.

## 4. Tree architecture for block trees

**Hallé–Oldeman.** There are 23 architectural models, though one 2010 count gives 22. Each is an abstraction of a tree's genetic ground plan, and real trees form a continuum between them (https://harvardforest1.fas.harvard.edu/publications/pdfs/Tomlinson_AmScientist_1983.pdf; https://greenlab.cirad.fr/GLUVED/html/P1_Prelim/Bota/Bota_typo_018.html). I did not verify the definitions of individual models. From memory, unverified:
- **Rauh:** a monopodial trunk with upright branches that repeat its form (oaks, pines).
- **Massart:** an upright trunk with tiers of horizontal branches (firs).
- **Troll:** every axis horizontal, with the trunk built from stacked arched segments (beech, elm). This explains beech's layered, arching silhouette.
- **Leeuwenberg:** forks repeatedly after each terminal shoot.

For silhouettes the useful split is excurrent (central leader: spruce, fir, cedar, young pine) versus decurrent (leader lost into a broad dome: beech, oak, old pine, willow). In the self-organizing tree model, the strength of apical control moves form between those two (https://cgg.mff.cuni.cz/%7Ejaroslav/teaching/2011-pg3/prezentace/HavlicekHencz%20-%20self-organizing_tree_models_pdf.pdf).

**Procedural methods.**
- **Space colonization:** branches grow toward attraction points scattered inside an envelope, so competition for space, not a recursion rule, sets the form. (https://algorithmicbotany.org/papers/colonization.egwnp2007.html).
- **Self-organizing trees:** buds compete for light, and an extended Borchert–Honda or priority model allocates resources (https://www.algorithmicbotany.org/papers/selforg.sig2009.html).

*For blocks (inference):* space colonization inside a species envelope (sphere, cone, flat disk, drooping dome), voxelized, gives distinct crowns cheaply. It also responds to neighbours if their occupied cells are removed from the attraction points, which yields one-sided crowns at edges and leaning toward gaps.

**Voxel games.**
- **Vintage Story:** each tree is defined by trunk parameters and one entry per branch level: `widthLoss`, `angleVert`/`angleVertEvolve`, `gravityDrag`, `dieAt`, `branchStart`, `branchSpacing`, `branchQuantity`, `branchHorizontalAngle`, `branchWidthMultiplier`. Width ≥ 0.3 places a log, 0.1 to 0.3 a branchy leaf, below 0.1 a leaf. Every branch is 1 block wide. Moss and vine chances are per tree (https://wiki.vintagestory.at/index.php/Modding:Trees).
- **TerraFirmaCraft:** forests place trees from structure templates, chosen by min/max rain and temperature. They add per-forest tree and groundcover counts, bushes, an old-growth chance (default 1 in 6), dead trees (1 in 75) and fallen logs (1 in 14 chunks) (https://terrafirmacraft.github.io/Documentation/1.18.x/worldgen/features/trees).
- **Dwarf Fortress:** tree tokens include `TRUNK_PERIOD` (years per z-level of growth), `TRUNK_BRANCHING` (0 gives a straight trunk) and branch and root radii. For example, oak uses `TRUNK_BRANCHING 2` and cedar 0 (https://dwarffortresswiki.org/index.php/DF2014:Plant_token; https://dwarffortresswiki.org/Oak).

**Minimum parameter set (inference):** height range; trunk lean and wander; clear-bole height; branches per whorl and spacing; branch angle (rising, flat, drooping, with gravity); leader kept or lost; crown envelope and width-to-height ratio; leaf blob radius and holes; trunk 1 block, 2×2 past an age; bark and leaf colours; fork chance; dead-top chance.

Silhouettes this produces (general botanical knowledge, unverified): beech, grey trunk forking low under a broad layered dome; oak, crooked wide limbs; birch, thin white stem under a narrow sparse crown; willow, leaning trunk with drooping curtain; pine, clear bole and flat top; spruce/fir, spire of tiers; cedar, spire of upturned plates; alder, straight stem and narrow cone.

## 5. Procedural ecosystem placement

- **Deussen et al. 1998.** Plants are circles. When two circles intersect, the plant with the lower competitive ability is dominated and may die, and plants that reach their maximum size die of old age. Shade tolerance and a preference for wet or dry ground decide the outcome, so species segregate along wetness by themselves and the population follows a self-thinning curve (https://algorithmicbotany.org/papers/ecosys.sig98.html, PDF section 4).
- **EcoBrush (Gain et al. 2017).** Short sandbox simulations sample the range of abiotic conditions (temperature, sunlight, soil moisture, slope). The results are stored as distributions of positions, sizes and canopies and indexed by those conditions. The world is then filled by looking up its conditions in that database. It works interactively up to 5×5 km and reproduces succession, self-thinning and underbrush (https://people.cs.uct.ac.za/~Jgain/wp-content/papercite-data/pdf/gain2017.pdf).
- **Cordonnier et al. 2017.** Couples vegetation and erosion both ways over centuries; relevant because the generator already erodes (https://www.cs.purdue.edu/homes/bbenes/papers/Cordonnier17ToG.pdf). **Makowski et al. 2019** builds up to 90K plants from reusable branch modules (https://research.google/pubs/synthetic-silviculture-multi-scale-modeling-of-plant-ecosystems/).
- **Kapp et al. 2020.** Not verified; my search did not find the paper.
- **Horizon Zero Dawn (Jaap van Muijden, GDC 2017).** The brief names de Carpentier as the speaker, but the speaker was van Muijden. The method:
  - Placement density is decoded from painted and generated maps at 0.5 to 2 m resolution: erosion flow, deposition, terrain cavity, water and road distance.
  - One painted value maps to sparse trees, edge forest and inner forest along a curve.
  - Each layer is discretized by a dither pattern that maximizes 2D distance, scaled to the asset's footprint.
  - Layers with the same footprint share one dither through a two-sided threshold, so trees and clearing plants exclude each other.

  (https://www.guerrilla-games.com/media/News/Files/GDC2017_VanMuijden_GPUBasedProceduralPlacementInHorizonZeroDawn.pdf)
- **Far Cry 5.** Per-species "biome recipes" react to terrain: species compete for ground, grass shows humidity, forest is denser where shaded, grassland sits on exposed hills (https://blog.playstation.com/2018/03/22/the-procedural-world-generation-of-far-cry-5/).
- **Ghost of Tsushima.** I found only the grass talk (https://gdcvault.com/play/1027214/contactUs). Its tree placement is unverified.

**Cheapest approach that gives clumping, gaps, age and mosaics (inference).** It runs once at generation, on the existing 16 m grid plus a finer grid.

1. Compute a community per cell from the rules in section 2, with blended edges.
2. Overlay a patch field from low-frequency noise plus disturbance events (landslides below scarps, a windthrow cluster every few hectares). It gives each patch an age class and a gap mask.
3. Per community, set a target density and footprint by age: young 3 m, mature 8 to 12 m, old 12 m plus saplings in gaps.
4. Place points with a jittered blue-noise or dither pattern at that footprint, and thin by density. Then run one cheap Deussen-style pass: the larger circle wins, and losers become saplings, snags or logs.
5. Pick species within the community by weighted choice, modulated by a second noise so neighbours of the same species cluster.
6. Shrubs and ground layer are separate layers with their own footprints, and their density is inverse to canopy cover.

## 6. How games count (calibration)

- **Minecraft:** about 10 overworld tree kinds (oak, spruce, birch, jungle, acacia, dark oak, mangrove, cherry, azalea, pale oak) (https://wiki.ronlab.site/content/minecraftwiki_en_all_maxi_2025-11/Tree).
- **Vintage Story:** 16 tree types including 2 bamboos, each with temperature, rain and forestation ranges (https://wiki.vintagestory.at/index.php/Tree/en).
- **Valheim:** about 8 tree kinds; Meadows have beech, birch and oak, Black Forest has fir and pine (https://valheim.fandom.com/wiki/Trees).
- **TerraFirmaCraft:** the total number of wood types was not verified; each tree is chosen by climate ranges (link above).
- **Dwarf Fortress:** several dozen tree species; the exact count was not verified.
- **RimWorld:** the temperate forest flora lists oak, with poplar also mentioned (https://rimworldwiki.com/wiki/Temperate_forest).

I found no source on what players notice. My reading **(inference)**: a world reads as varied through a few strongly different silhouettes per place and visible changes between places, not through species counts.



---

## Proposed communities (inference)

Fields: W = wetness index percentile, S = slope, C = convexity (positive is a ridge), E = elevation, X = exposure (section 2), dR/dS = distance to river/sea, H = rock hardness, A = sun-facing factor, Hw = height above water.

| # | Community | Trigger | Species / forms | Structure | In blocks |
|---|---|---|---|---|---|
| 1 | Beech slope forest (matrix) | W 25–80, X low, E < ~250 | Beech; understory magnolia, maple; shrub viburnum; ground Sasa | Old: ~120 canopy/ha at 25–30 m in reality; 15 % gaps; logs | 12–20 m trees, broad layered domes on 1-block, later 2×2, grey trunks; continuous knee-high Sasa broken in gaps; mossy logs |
| 2 | Valley-floor riparian forest | W > 85, S < 10°, dR < ~30 m | Wingnut, katsura, horse chestnut; ground butterbur, ferns | Fewer, larger trees; lush herbs; patchy (flood-reset) | Big leaning trunks over water; huge-leaf herb blocks; gravel bars bare or with willow |
| 3 | Willow/alder carr | Hw 0.6–1.5 m by lake, mire or slow river | Alder, willow; sedge | Dense, multi-stem, 6–12 m | Clumped multi-trunk small trees, dark wet floor, standing water between |
| 4 | Reed and sedge fen | Hw −0.5 to +0.6 m | Reed, sedge, cattail; floating-leaved plants offshore | Tall herb 1–3 m, no trees | 2-block reed columns in a band whose width follows shore slope; lily-pad slabs on water |
| 5 | Pioneer birch/alder patch | Disturbance age < 30 y (landslide tongue, scarp foot, windthrow) | Birch, alder, willow; ground bracken, grass | Even-aged, dense (3–4 m spacing), 6–10 m | Thin white stems in thickets; elongated downslope patches with fallen old trunks inside |
| 6 | Ridge and rock pine/hemlock | W < 15 and C > 0, or H high and S > 35° | Pine, hemlock, *Thuja*; ground rhododendron, moss | Open, 10–15 m, rock showing | Flat-topped pines and dark spires on bare stone; sparse; boulders |
| 7 | Sun-slope oak (drier) | A high, W 15–40 | Oak, chestnut, sakura-like flowering tree; grass, bracken | More open crowns, grassy floor | Crooked wide oaks, gaps of grass and bracken |
| 8 | Exposed wind scrub | X above threshold (summits, windward shoulders) | Wind-cut beech/oak scrub, rowan, dwarf birch; Sasa | 1–4 m, dense, sheared | Crowns 2–4 blocks tall leaning downwind and wedge-shaped; trees thicken to forest leeward |
| 9 | Heath and moor | X high, W low (heath) or W high on flat summits (moor/blanket bog) | Heather, crowberry, bilberry; sphagnum, cotton-grass | No trees; < 0.5 m | Purple/brown low-cover blocks; boggy pools on flat tops |
| 10 | Coastal dune and pine belt | dS < ~300 m, low Hw | Dune grass, beach rose; black pine | Height rising inland | Bare sand, then grass tufts and rose shrubs, then wind-bent pines growing taller inland |
| 11 | Sea-cliff grassland | dS < ~100 m, S > 40° | Thrift, salt-tolerant grass, sea campion | Turf, no trees | Short grass and flower cover on cliff tops, bare rock faces |

Cast in this table: about 8 canopy forms (beech, wingnut/katsura, alder, willow, birch, pine, hemlock/cedar, oak), about 4 understory trees, about 5 shrubs, about 6 ground types and about 4 wetland plants.

## Could not verify

Rank-abundance curves for temperate stands; total tree species counts for small cool-temperate islands; stems/ha and gap sizes for *Fagus crenata* old growth; where conifers sit on ridges and rock at Shirakami; wind as a direct cause of low island treelines; limestone-versus-acid floras; definitions of individual Hallé–Oldeman models; open-grown versus forest-grown crown form, and leaning toward water; Kapp et al. 2020; Ghost of Tsushima tree placement; wood type counts for TerraFirmaCraft and Dwarf Fortress; what players notice; the depth thresholds for lake-edge zones and the block-scale densities, which are my estimates.
