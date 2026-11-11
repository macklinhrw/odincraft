# Terrain worth exploring: diversity research

September 13, 2026. Research and recommendations only; no generator changes. Code observations refer to the current working tree based on `b590eb0`, including existing uncommitted work. This is a source/code audit, not a new playtest or performance measurement.

Follow-up: the [first playable landscape experiment](../../reports/terrain/exploration/README.md) now records matched native views, water/persistence checks and an actual 2.3 km walking replay. It remains a selected-site comparison, not a production generator change.

## Recommendation

Build **recognizable landscape families and connected places**, then measure whether ordinary walking routes encounter them. The highest-value first experiment is a wooded valley with a lake basin, a rock-controlled outlet gorge and a reachable overlook, compared with today's terrain at the same location.

This develops the existing [natural-world diversity requirement](../natural-world-diversity.md). Its definition of success—an interesting continuous 2–5 km hike inside one broad biome—is still the right target. More species, greater peak altitude and higher roughness alone cannot establish that result.

## What the current implementation suggests

| Observation | Likely exploration consequence |
|---|---|
| New worlds use revision 11 and, by default, a 1 km formation mesh. [model.odin](../../src/terrain/model.odin) | Fine geographic identity must come from a representation below the formation mesh. |
| `relief_field` supplies the same crest/gully, rounded-hill and fine-grain fields everywhere; `relief_gains` varies their amplitudes using elevation and local relief. [relief.odin](../../src/terrain/relief.odin) | Different regions can have different steepness while sharing the same vocabulary of shapes. This is a plausible cause of sameness, not a measured player-experience result. |
| `mesh_relief` uses one orogenic strike per world, with warped range belts. | Regional orientation is limited. Changing it needs a continuous local coordinate construction: the previous position-dependent rotation produced spikes, as recorded in [mountain development](mountain-development.md). |
| Geology changes coarse erosion resistance and underground materials, but is not an input to the local relief fields. [geology.odin](../../src/terrain/geology.odin), [model.odin](../../src/terrain/model.odin) | Limestone, layered sedimentary country and crystalline uplands have limited opportunity to develop different local silhouettes. Geology already affects terrain; the missing link is specifically local morphology. |
| Landslide basin patches are 1,024 m across, capped at 32, with at most 64 candidate attempts. [basins.odin](../../src/terrain/basins.odin) | At the cap, their combined square footprints cover only about 33.6 km² of a 1,000,000 km² world, or 0.00336%. This is a footprint upper bound, not encounter probability or total lake coverage; ordinary compiled lakes are separate. Rare fine features can be practically invisible during ordinary travel. |
| Procedural gallery carving requires more than eight metres of cover below the local surface. [geology.odin](../../src/terrain/geology.odin) | This rule preserves a surface shell instead of creating natural walk-in entrances. Underground content needs an explicit surface connection to become an exploration destination; mining access is already separate. |

The [revision-nine measurements](../../reports/terrain/relief/README.md) already improved mountain roughness substantially, and [revision-ten work](../../reports/terrain/biomes/README.md) improved mountain occurrence. Repeating those fixes is unlikely to address the entire remaining complaint. Saved worlds retain older terrain revisions, so a future audit must record the actual save revision before comparing terrain quality.

## What the research supports

### Separate ecological variety from landform variety

Minecraft's first-party 1.18 release notes describe terrain shape and elevation varying independently of biome, and merging redundant shape-based biome variants. This is a useful precedent for allowing one forest to span several landforms. It does not imply ignoring climate or geology, and OdinCraft already partly separates these concerns. The useful next step here is richer landform controls. [Mojang release notes](https://feedback.minecraft.net/hc/en-us/articles/4415128577293-Minecraft-Java-Edition-1-18).

Proposed initial families:

| Family | Recognizable geometry | Exploration opportunities | Relative scope |
|---|---|---|---|
| Soil-covered hill country | Rounded divides, open valley bottoms, occasional exposed shoulders | Gentle approaches, woodland enclosure, meadow openings and views | Smallest extension of existing relief |
| Layered rock country | Resistant ledges, escarpments, narrow cuts and talus below faces | Follow a ledge, find a pass, descend into a gorge | Medium; couple strata to geometry |
| Dissected mountain country | Connected spurs, tributary valleys, saddles and contrasting ridge/flank shapes | Follow a valley, cross a saddle, orient by a summit | Medium; improve regional control and connectivity |
| Formerly glaciated uplands | Broad troughs, cirques, sharp dividing ridges and hanging tributaries | Basin lake, high traverse, waterfall overlook | Larger; needs inherited glacial history or a bounded process |
| Karst country | Sinkholes, cave mouths and connected subsurface passages | Visible entrances and alternative routes underground | Larger; geometry, water, collision and rendering must agree |

These are proposed families, not a request to implement all five at once. NPS describes joint-guided erosion producing fins and narrow canyons, with resistance differences changing the remaining rock. This supports geology-conditioned shapes rather than surface color alone. It does not establish that our coarse geology already resolves individual joints. [NPS: walls and narrows](https://www.nps.gov/brca/learn/nature/wallandnarrows.htm).

NPS describes glacial troughs, hanging valleys, cirques, sharp ridges and chains of lakes as related products of glaciation. The useful design inference is that one formative history can produce an entire family of connected discoveries. Present-day snow alone is insufficient evidence for past glaciation. [NPS: glacial geology](https://www.nps.gov/glac/learn/nature/glacial-geology.htm).

### Give features relationships and approaches

LayerProcGen's author documentation identifies surface-connected caves and reachable cliffs as relationships that purely local sampling cannot establish by itself. Its example uses a regional layer to plan connections and destinations, then smaller areas generate against those specifications. This supports a regional feature/connection representation; its demonstrated platformer is not proof of OdinCraft's hydrology or 3D traversal. Start with one local place before designing a world-wide planning framework. [LayerProcGen: Planning at Scale](https://runevision.github.io/LayerProcGen/md_PlanningAtScale.html).

Proposed example: sheltered woodland → irregular lakeshore → resistant outlet lip → gorge → shoulder with a view back across the basin. Each feature should connect through the actual ground and water state. Some outlets should be gentle; some valleys should remain quiet. Do not place this exact sequence at every lake.

The generator should expose parameters with visible consequences: valley-floor width, ridge spacing and orientation, cliff persistence, degree of dissection, and frequency of local disturbances. Blend regional controls coherently. Averaging unrelated finished heightfields everywhere risks smoothing away the distinctive forms we want.

A landscape can look varied from above and still offer no sensible ground route. Treat saddles, traversable banks and approaches to viewpoints as review criteria alongside silhouettes. This is a design hypothesis to test through walking, not a published guarantee of engagement.

Mojang's experimental terrain changelog explicitly describes river cuts and saddle valleys through mountains as improvements for walking and boating. It also documents reducing fragmented microbiomes and restoring some variation to overly flat areas. That is practical evidence for evaluating connectivity and quiet terrain together with spectacular peaks. [Mojang's terrain iteration notes](https://www.minecraft.net/en-us/article/new-world-generation-java-available-testing).

### Make some destinations genuinely three-dimensional

Ryan Geiss's GPU Gems chapter demonstrates terrain defined by a 3D density function, including caves, overhangs and controlled flatter areas. A heightfield cannot represent all these shapes. OdinCraft already has voxel material queries, so the research supports adding selective surface-connected geometry to the existing representation, not automatically replacing the renderer. The chapter's historical DirectX pipeline supplies no current Metal performance estimate. [GPU Gems 3, chapter 1](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-1-generating-complex-procedural-terrains-using-gpu).

### Use intermediate detail selectively

Schott et al.'s multiscale erosion work combines thermal erosion, stream-power erosion and deposition at different scales to amplify low-resolution terrain with coherent detail. It supports investigating the missing intermediate scales rather than adding only fine grain. It does not establish an affordable million-square-kilometre Odin/Metal implementation. [Author project and paper links](https://h-schott.github.io/p/mserosion/).

The repo has already investigated expensive catchment refinement and found unresolved shared-boundary and world-budget limits. Retain that evidence: [existing research](research.md), [mountain experiments](mountain-development.md). Start with bounded geographic domains, preserve divides and inlet/outlet constraints, and compile persistent results. Do not rerun erosion independently inside render tiles.

## Recommended order

1. **Audit ordinary encounters.** On three recorded seeds/revisions, review both representative starts and selected feature-rich locations. Walk fixed 2–5 km routes in woodland/lake, river/gorge and mountain settings. This separates absent features from rare features, poor starting locations and inaccessible features.
2. **Prototype two contrasting local shape families.** Start with rounded hill country and rock-controlled escarpment/gorge terrain under comparable climate. Use real geological eligibility, continuous controls and the shared geographic query. Include the current field as the control. Require a difference recognizable without biome colors.
3. **Build one connected basin/outlet landscape.** Extend an eligible existing basin rather than placing disconnected decorations. Resolve its bed, spill, supported outlet, receiving channel, exposed rock and rooting soil together. A waterfall needs a real drop and receiving water geometry; metre-stepped water alone does not establish one.
4. **Improve discoverability from measured results.** Index actual interesting sites for atlas discovery or optional scenic starts. Adjust regional feature occurrence only after measuring distances and cost. Raising `BASIN_LIMIT` alone cannot establish good placement or geometry.
5. **Add surface-connected volumetric features.** A cave mouth or rock shelter offers a qualitatively new route. Scope this after the surface prototype because near/far meshes, collision, water and save/reopen must all represent the opening.

## How to judge the experiment

Record route distance and elapsed time, elevation gain, traversable continuity, distinct landform transitions, visible/reachable destinations, and longest stretches with no meaningful change. Review eye-level captures at matched route positions; include quiet terrain and failing controls. Report route results individually as well as aggregates so a spectacular selected site cannot hide repetitive ordinary starts.

Use the existing metre queries for final walkability: coarse slope alone cannot prove that a block staircase, cliff or bank is passable. Evaluate enclosure and visibility from the player's actual camera. The question is whether the landscape gives the player recognizable choices and reasons to continue walking.

Retain the existing 240-second complete-creation and 120-second terrain targets, measured storage and dense-scene rendering costs. The earlier proposed extra formation allowances are ceilings to test, not available budget to assume. Verify determinism, save/reopen, shared point/region results, near/far silhouettes, supported water and connected outlets before production integration.

No new performance or gameplay results are claimed here. The recommended next deliverable is one controlled, playable landscape comparison, with a short route review and measured costs.
