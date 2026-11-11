---
type: note
date: "2026-06-02"
zettel_id: "202606021223"
tags:
  - projects
  - zigcraft
  - voxel-engine
  - performance
  - terrain-generation
  - architecture
aliases:
  - Voxel Engine Foundation Synthesis
  - Zigcraft Voxel Engine Foundation
---
related:: [[2026-06-02]]

# Voxel Engine Foundation Synthesis
---

This note reconciles six voxel / terrain development videos into a foundation for a future Zigcraft engine. The target is not a toy renderer. The target is a highly performant voxel engine with very large view distance, no unwarranted hitches, realistic terrain generation as a core requirement, and an architecture that does not collapse when near rendering, far rendering, generation, meshing, editing, and streaming interact.

## Source Set

- [[My game is 262,000 times faster than Minecraft I'll show you how|My game is 262,000 times faster than Minecraft. I'll show you how.]]
- [[I Remade Minecraft But It's Optimized]]
- [[Coding Adventure Hydraulic Erosion]]
- [[500 million voxels per second - Voxel engine optimizations]]
- [[When Your Game Is Bad But Your Optimisation Is Genius]]
- [[I Spent 5 Years Building a Voxel Survival Game Where the World Is a Planet]]

Related Zigcraft context:

- [[Zigcraft Voxel Game Refactoring Plan]]
- [[202411011802 - terrain generation|Zigcraft terrain generation]]
- [[Mesh Production Bottleneck — Phase 15]]
- [[Zigcraft Phase F Far LOD Architecture Review]]
- [[Dwarf World Game Concept]]

Related implementation:

- `~/Programming/zigcraft-neo`
- `~/Programming/zigcraft-neo/src/worldgen.zig`
- `~/Programming/zigcraft-neo/plans/realistic-worldgen-refactor-plan/`
- `~/Programming/zigcraft-neo/plans/plan-v3-rewrite-foundation/completion-summary.md`
- `~/Programming/zigcraft-neo/docs/performance-reassessment.md`

Related reference repos:

- `~/Programming/zigcraft-neo/old-repo/resources/clones/TerraForged`
- `~/Programming/zigcraft-neo/old-repo/resources/clones/ReTerraForged`
- `~/Programming/zigcraft-neo/old-repo/resources/clones/Realistic-Terrain-Generation`

## Zigcraft-Neo Reality Check

The important correction from Zigcraft-Neo is not "the terrain plan lacked enough proof." The stronger diagnosis is that the generator model itself was pointed at the wrong target.

Zigcraft-Neo proved that the engine can become much faster. Plan v3 recovered large performance headroom in horizon and streaming scenarios, added better benchmark telemetry, split misleading queue metrics, and hardened near/far readiness measurement. The current repo test suite also remains healthy: `zig build test --summary all` passed with 126 tests and 1 skipped test on 2026-06-02.

But the terrain generator still reads as artificial because it is mostly a taxonomy of local scalar fields, not a landform system. In `src/worldgen.zig`, the core pipeline is:

- continent mask
- hashed terrain-family weights
- hand-shaped terrain functions for plains, hills, mountains, plateau, dunes, and steppe
- bounded tile-local river segments plus a global sinusoidal outlet path
- climate fields and surface-block rules layered after the height result

That can generate a map with "mountains," "rivers," "dunes," "badlands," and "swamps" as labels, while still failing to create terrain that looks like it was shaped by geology, drainage, erosion, deposition, soil formation, and ecology. The code has a `Column` oracle, but the column is still mostly a bundle of sampled fields rather than a record of a coherent regional process.

The screenshots show the consequence: regular contour bands, plate-like shelves, visibly synthetic stripes, noisy surface speckling, water shapes that do not read as drainage basins, and terrain-family regions that look classified rather than formed. User-observed river quality was especially bad: the Zigcraft-Neo rivers looked completely terrible and unrealistic. That matters because rivers are one of the fastest ways to reveal whether terrain has a real drainage model or only a decorative carve field. The problem is not just missing visual gates. The problem is that coverage metrics can say "rivers exist" and "mountains exist" even when the river is a carved distance field and the mountain is a warped ridged trig shape.

The foundational terrain lesson is:

> Realism comes from causal structure, not from naming more noise layers.

For the next foundation, terrain generation should start from a region product rather than from independent per-column recipes. A convincing region should have:

- uplift / base relief
- landmass and coastline structure
- drainage basins and flow direction
- flow accumulation and stream order
- river paths that run downhill and join because of basin topology
- erosion and deposition fields derived from slope and flow
- valley bottoms, ridgelines, shoulders, alluvial flats, cliffs, and terraces as consequences of those fields
- material strata and soil depth tied to slope, altitude, moisture, and erosion
- biome candidates derived from climate plus landform position

The hot path can still be fast. The expensive region product can be generated asynchronously, cached, simplified for far LOD, and sampled cheaply by near chunks. But the conceptual unit cannot be "sample a block column and then decide what named terrain type it is." It needs to be "sample from a regional terrain model whose large-scale structure already makes sense."

## TerraForged and RTG Reference Findings

The TerraForged lineage confirms the diagnosis. TerraForged/ReTerraForged are not merely "better noise constants." They organize worldgen around regional products and multi-field samples.

ReTerraForged's core record is `Cell`. It carries height, gradient, local erosion, sediment, continent edge, terrain-region ID, terrain-region edge, river distance, river-carved terrain, climate, biome type, weirdness, moisture, temperature, and terrain category. The important point is not the Java object; it is that one terrain sample contains multiple mutually-explaining fields. Surface, biome, feature placement, rivers, beaches, and filters can all consult the same cell.

ReTerraForged's `TileGenerator` creates a tile of cells, applies continent, river map, terrain, and climate over the tile, then applies `WorldFilters`. Those filters include droplet erosion, smoothing, steepness, beach detection, and post-processing. This is a regional heightfield product with borders, pooling, async generation, and cached filters. It is much closer to what Zigcraft needs than a pure per-column oracle.

The river architecture is especially important:

- ReTerraForged uses `Rivermap`, `Network`, `River`, `RiverPopulator`, `LakePopulator`, and `WetlandPopulator`.
- A river network has roots, child forks, lakes, wetlands, bounds, overlap checks, and warp.
- Rivers carve valley, banks, bed, river distance, and terrain tags into cells.
- Simple continents generate rivers from inland directions toward ocean distance.
- Fancy continents generate river roots from island segments and coast-facing directions.
- Original TerraForged connects continent cells by lower-neighbor relationships, then carves river/lake nodes into `NoiseSample`.

This is the missing shape in Zigcraft-Neo. Its current river field is a bounded per-tile recipe, not a drainage network. Even if it has confluences by metric, it does not have the reason rivers are supposed to exist: water moving from higher land through connected basins toward lower/ocean cells.

The user-visible failure mode was not subtle: rivers looked wrong. The successor terrain plan should therefore treat river realism as its own acceptance gate before full terrain integration. A passable river system needs at least downhill continuity, branch hierarchy, plausible valley width by river order, beds and banks that agree with terrain height, lake/wetland attachment where appropriate, and coast/ocean termination that does not feel like an arbitrary outlet hack.

TerraForged also separates terrain region selection from terrain shape. `TerrainBlender` / `RegionSelector` choose terrain modules from warped cell regions, then blend the output of neighboring terrain functions. ReTerraForged's `RegionLerper` blends height, erosion, and weirdness across region boundaries. Zigcraft-Neo blended terrain-family weights, but the shapes themselves remained simple hand-authored sin/cos fields. The reference repos blend richer terrain modules and carry the blended secondary fields forward.

RTG is a different, older model but still useful. It keeps Minecraft's biome map, then generates a `ChunkLandscape` with weighted neighboring biome terrain functions. Each realistic biome owns terrain and surface behavior, and chunk terrain is a blend of nearby biome contributions over a stencil. Rivers/lakes are not only labels; they lower and flatten terrain inside the biome noise path through `riverized`, lake pressure, and surface replacement. RTG is less global and less causal than TerraForged, but it reinforces the same rule: biome identity alone is insufficient; every biome needs a terrain shape and surface model that interacts with rivers and neighboring biomes.

The reference-derived architecture for Zigcraft should be:

1. **Region tile product.** Generate a tile/region with border cells, not only independent columns. Store height, base height, gradient, river distance, drainage metadata, erosion/deposition, terrain type, biome candidate, climate, surface class, and material hints.
2. **Continent / landmass graph.** Build landmass cells or region centers with continent edge, nearest center, distance-to-ocean, and coastline bands. This gives rivers and biomes spatial context.
3. **Drainage network.** Generate river roots and forks from the landmass graph or a flow field. Rivers must have continuity, hierarchy, size, beds, banks, valleys, lakes, and wetlands.
4. **Terrain module library.** Plains, hills, plateaus, badlands, dunes, mountains, coast, ocean, wetlands, and rivers should be modules that write height plus semantic fields, not one-off shape functions.
5. **Regional filters.** Run erosion, smoothing, steepness, beach/coast detection, and post-processing over the tile. Store resulting gradient, erosion, sediment/deposition, and surface hints.
6. **Chunk materialization.** Near chunks sample the finished region product and convert it to voxels. Far LOD samples the same product at lower resolution.
7. **Surface and feature placement.** Surface blocks, trees, rocks, snow, scree, roads, and structures read the cell fields. They do not resample unrelated noise as their main source of truth.

The implementation constraint is that Zigcraft should copy the shape of this architecture, not the Java machinery. No `CellPopulator` hierarchy is required. A Zig version can be data-oriented:

- `RegionTile` arrays of `TerrainCell`
- stage functions that mutate arrays in order
- pooled scratch buffers
- deterministic region cache keyed by region coordinate and seed
- async generation jobs
- cheap column queries into cached region products
- far LOD built from the same cells

The next worldgen attempt should therefore start with a standalone region previewer, not in-game chunks. If the 2D/heightfield product does not already read like TerraForged/RTG-inspired terrain before voxelization, the voxel engine will only make the wrong model faster.

## Core Thesis

A high-performance voxel engine is not mainly a faster-loop problem. It is a scale-management problem.

The engine must avoid doing high-detail work at the wrong distance, avoid storing redundant data, avoid meshing invisible faces, avoid recomputing identical terrain inputs, avoid issuing thousands of unnecessary draw calls, and avoid letting generation work block the frame. The common rule across all five notes is:

> Do not generate, store, mesh, upload, draw, or simulate detail until the current gameplay scale actually needs it.

The second rule is specific to Zigcraft:

> Realistic terrain generation is not a cosmetic post-process. It is part of the engine's data model.

If terrain realism is core, then terrain generation cannot be bolted on after chunk streaming and LOD. The world generator must produce reusable summaries, deterministic fields, biome and hydrology context, erosion-informed surfaces, and voxel materialization rules that the renderer, streamer, LOD system, and gameplay queries can all consume.

## Non-Negotiable Goals

- Very large view distance.
- Realistic terrain generation, not only noise hills.
- Stable near/far transition during normal gameplay.
- No main-thread generation or meshing hitches.
- Compact runtime memory for large resident worlds.
- Deterministic base generation so multiplayer and persistence can store seeds plus deltas instead of whole worlds.
- Incremental benchmark gates that test whole gameplay scenarios, not only isolated microbenchmarks.
- A representation that can eventually support caves, overhangs, water, lighting, edits, surface features, and AI/world-state generation.

## Reconciled Engine Model

The notes point toward a layered engine, where each layer is allowed to use a different representation:

1. **World intent layer** - seed, macro geography, climate, biome regions, rivers, erosion basins, world history hooks, and high-level feature placement.
2. **Terrain field layer** - queryable height, density, material, moisture, temperature, biome, and cave fields. This is where noise, domain warping, erosion, and cached shared parameters live.
3. **Chunk data layer** - materialized voxel data only where needed. Storage should be compact and variant-based: uniform chunks, layer-compressed chunks, palette/dense chunks, and run-length encoded chunks are all valid depending on local data shape.
4. **Near mesh layer** - high-detail meshes for nearby chunks, generated from voxel data using hidden-face removal, greedy meshing where appropriate, compact vertex formats, and careful rebuild budgets.
5. **Far terrain layer** - lower-resolution summaries and LOD tiles, not full near meshes. This layer should be hierarchical, readiness-aware, and explicitly tested for near/far continuity.
6. **Renderer layer** - culling, batching, GPU upload, LOD draw policy, and transition handling.
7. **Gameplay query layer** - raycasts, collision, block edits, surface placement, water checks, and AI/world-state queries over the same world data model.

The old failure mode was treating these as separable phases that could be joined later. The new foundation should define the contracts between them before implementation starts.

## Terrain Generation Foundation

Realistic terrain needs a staged pipeline:

1. **Macro terrain first.** Generate large-scale structure before local detail: continents or regions, mountain chains, valleys, drainage basins, climate bands, biome regions, and major water paths. Pure layered noise is acceptable only as a temporary scaffold; it is not the target.
2. **Causal field graph.** Terrain should be represented as a graph of reusable fields with causal meaning: uplift, base height, slope, flow direction, flow accumulation, erosion, sediment/deposition, moisture, temperature, biome mask, cave density, material strata, and feature masks.
3. **Noise reuse and caching.** Shared low-frequency and medium-frequency fields should be computed once and reused across biome shapers and chunk layers. [[Noise caching]] is especially important at biome borders.
4. **Upsample where quality permits.** [[Noise upsampling]] should be a default option for expensive fields. Far terrain and low-frequency fields should not sample every voxel.
5. **Bounded generation.** The terrain graph should expose min/max bounds or conservative bounds so generation can skip impossible work through [[Extremity-bound checking]].
6. **Erosion as a real pass.** [[Coding Adventure Hydraulic Erosion]] shows that erosion gives terrain the channels, ridges, and depositional flats that raw noise lacks. Zigcraft-Neo's proxy erosion field is not enough. Erosion must alter the terrain product or at least derive from slope and flow accumulation, not merely paint surface materials after a height has already been chosen.
7. **Materialization late.** The engine should avoid converting the whole terrain field into full voxel data. Far terrain can use summaries. Near terrain can materialize voxels only when needed for mesh generation, editing, collision, or interaction.
8. **Surface features from structure.** Trees, rocks, roads, settlements, NPC spawn points, and AI-generated world objects should depend on stable surface-feature queries, not ad hoc random placement. [[Runtime run-length encoding for voxel data]] may help surface detection because run transitions expose block changes.

The key design move is to separate "terrain exists" from "every voxel has been generated." A realistic world can exist as deterministic fields and summaries long before it becomes dense editable voxel data.

The second key move is to separate "terrain has labels" from "terrain has causes." A generator can produce all required biome names and still miss realism if rivers, valleys, ridges, soil, and vegetation do not explain each other.

## Chunk and Storage Strategy

The video notes disagree on exact chunk shapes, and that is useful. [[I Remade Minecraft But It's Optimized]] reports a Java prototype where `32 x 32 x 32` performed better than `16 x 16 x 16`. [[500 million voxels per second - Voxel engine optimizations]] argues for `32 x 256 x 32` chunks when runtime run-length encoding makes tall chunks cheap and improves vertical noise reuse.

The reconciled decision is: do not hard-code one chunk shape as a dogma. Benchmark chunk shapes against realistic generation and gameplay.

Candidate representations:

- `16 x 16 x 16` - smaller rebuilds, more chunk-management overhead.
- `32 x 32 x 32` - fewer chunks and draw objects, heavier rebuilds.
- `32 x 64 x 32` or `32 x 128 x 32` - possible middle ground for terrain with meaningful vertical range.
- `32 x 256 x 32` - attractive for tall natural terrain, vertical noise reuse, and RLE-like storage, but risky for edits and rebuild granularity.

The likely foundation is a hybrid:

- Use column or region summaries for generation and far LOD.
- Use compact near chunks for editing and high-detail meshing.
- Allow storage variants per chunk or subchunk:
  - uniform air / stone / water / material
  - layer-compressed data
  - palette-backed dense data
  - run-length encoded data for large natural spans
  - edited dense fallback when local modifications make compression inefficient

This matches the source notes better than choosing either "always dense array" or "always RLE." Dense arrays are excellent for random access and edits. RLE is excellent for natural spans, disk/network persistence, huge render distances, tall chunks, large writes, and surface scanning. A performant engine should be able to use both.

[[I Spent 5 Years Building a Voxel Survival Game Where the World Is a Planet]] adds a concrete palette-backed workload. PlanetSmith's 16 by 16 by 512 chunks formerly used two bytes for every one of more than five billion resident block positions. A local palette plus four-, eight-, or twelve-bit indices, with no array for empty chunks, reportedly reduced average block-memory use by about 91%. This supports the existing storage-variant decision: benchmark uniform, palette, RLE, and dense layouts against local diversity and edit patterns instead of choosing one universal compression scheme.

The source also shows the cost of changing representation late. The palette migration broke nearly every dependent system, while an aging mesher was already blocking workers. Zigcraft's chunk API should keep storage encoding behind stable access and iteration contracts so meshing, lighting, physics, persistence, and gameplay do not depend directly on one bit layout.

## Near Mesh Foundation

Near rendering should start from the boring voxel-specific wins before advanced effects:

- Blocks are data, not objects.
- Meshes are chunk outputs, not per-block objects.
- Hidden faces are never emitted.
- Greedy meshing is introduced only after hidden-face meshing is benchmarked and stable.
- Mesh rebuild work is budgeted and asynchronous.
- Vertex formats are compact. Do not store derivable or unnecessary attributes.
- Grid-aligned coordinates can often be packed or reconstructed.
- Normals, UVs, material IDs, lighting, and ambient-occlusion data should have explicit size budgets.
- Mesh production time is tracked as a first-class metric because [[Mesh Production Bottleneck — Phase 15]] shows it can become the bottleneck after earlier rendering wins.

[[When Your Game Is Bad But Your Optimisation Is Genius]] broadens the lesson beyond voxels: vertex memory bandwidth can dominate before shader arithmetic does. The near mesh path should therefore measure bytes uploaded, vertex count, index count, draw count, mesh build time, upload time, and p95/p99 frame impact.

## Far View Distance and LOD

Long view distance comes from generating less detail, not from generating the same detail faster.

The far system should not be an afterthought. [[Zigcraft Phase F Far LOD Architecture Review]] already identifies the failure mode: a fixed coarse overlay is not the same thing as a hierarchical, readiness-aware far runtime. The source videos point toward a stronger model:

- Far terrain should use summaries, not near meshes.
- LOD should be hierarchical or ringed.
- Far data should have explicit readiness states.
- Parent/child continuity must be designed, not guessed.
- Near/far seams must be a gameplay benchmark gate.
- Far terrain should use coarser terrain fields and upsampled/cached generation.
- Far meshes can be terrain-like, height-field-like, or reduced voxel surfaces depending on distance and biome.
- LOD transitions need a visual policy: snap, blend, geomorph, hide behind fog/foliage, or rise/sink terrain. The policy must be benchmarked, because transition quality killed the old plan.

For Zigcraft, the far terrain layer should likely be generated from the same macro terrain and field graph as near voxels. That keeps distant mountains, rivers, valleys, and biome boundaries consistent with what the player eventually reaches.

## Culling and Draw Submission

The source notes stack culling in layers:

- **Face culling:** do not emit hidden block faces.
- **Chunk frustum culling:** skip chunks outside the camera view.
- **Region broad-phase culling:** group chunks into regions so a whole outside region avoids thousands of chunk checks.
- **Occlusion culling:** precompute or query whether neighboring chunks can see each other, then traverse visible chunks from the camera.
- **LOD culling:** skip or reduce detail by distance.
- **Underground / hidden LOD skipping:** if transition strategy hides low-detail terrain below the surface, do not draw fully hidden meshes.

Draw submission needs the same hierarchy. Thousands of chunks cannot each become an expensive CPU draw call. The renderer should plan for batching or multi-draw style submission, with per-draw or per-instance data stored in GPU buffers when the backend supports it.

## Generation and Streaming Runtime

Generation must be async, budgeted, and staged:

1. Determine desired near chunks, far tiles, and region summaries from camera/player movement.
2. Prioritize visible and soon-visible work.
3. Generate macro summaries before near detail.
4. Generate or retrieve terrain fields.
5. Materialize near voxel data only when required.
6. Mesh near chunks and far tiles on worker threads.
7. Upload within frame budgets.
8. Swap readiness states only when visual continuity is safe.

Main-thread chunk generation is disallowed as an architectural rule. [[My game is 262,000 times faster than Minecraft I'll show you how|My game is 262,000 times faster than Minecraft. I'll show you how.]] shows why: once generation moves onto the frame thread, the player experiences hitches even if average FPS looks fine.

The runtime should track each unit of world work as a state machine:

- absent
- summary requested
- summary ready
- field requested
- voxel data ready
- mesh requested
- mesh ready
- GPU upload pending
- resident
- visible
- retiring

This avoids "present in cache equals ready" mistakes.

## Benchmarks and Acceptance Gates

The previous Zigcraft plan failed partly because benchmarks did not protect normal gameplay. The new benchmark suite needs both narrow and integrated tests.

Required metrics:

- average, p95, and p99 frame time
- hitch count over a traversal path
- main-thread time
- generation queue depth
- mesh queue depth
- GPU upload queue depth
- near chunks resident / visible / rebuilding
- far tiles resident / visible / substituting near
- bytes of voxel data resident
- bytes of mesh data resident
- bytes uploaded per second
- draw count
- triangle count
- vertex count
- memory use and VRAM use
- terrain generation time per chunk or tile by stage
- near/far seam error or visible transition failures

Required scenarios:

- Flat baseline world.
- Realistic terrain world with mountains, valleys, water basins, and biome transitions.
- Fast flight over new terrain.
- Standing still while far terrain finishes.
- Crossing near/far boundaries repeatedly.
- Turning the camera quickly at high view distance.
- Editing blocks in natural terrain.
- Surface-feature placement pass.
- Worst-case tall terrain.
- Worst-case caves / overhangs once density terrain exists.
- A deliberately underpowered-machine or throttled-worker run that verifies queues recover instead of entering a backpressure cascade.

PlanetSmith reportedly ran above 200 FPS on the developer's machine while public testers experienced severe stuttering at minimum settings. Once one task class fell behind, it blocked other systems and amplified the delay. Zigcraft's gates therefore need queue age, worker utilization, oldest-job latency, and recovery after overload—not only steady-state throughput on the development machine.

Every major feature needs a before/after benchmark on at least one realistic traversal scenario. A microbenchmark can justify an optimization, but it cannot accept a phase.

## Terrain Realism Acceptance Gates

Because realistic terrain is core, performance cannot be accepted only on flat or toy worlds.

A terrain build is not acceptable unless it can show:

- large-scale terrain coherence across long view distances
- mountains that read at far LOD and still resolve into believable near terrain
- valleys, drainage, or erosion-like structure
- biome transitions that do not require duplicate expensive generation at every border
- deterministic regeneration from seed
- stable surface-feature locations
- no obvious near/far mismatch in ridgelines or water paths
- reasonable generation time under fast traversal

It also needs model-level gates, not only coverage gates:

- rivers flow downhill through connected drainage basins
- flow accumulation predicts river size
- valleys align with river and erosion fields
- river beds, banks, branch hierarchy, lakes/wetlands, and ocean exits look plausible from normal gameplay camera angles
- ridgelines and mountain chains have directional continuity
- slope, curvature, altitude, and material distributions are plausible
- coastline, beach, shelf, and inland transitions have legible structure
- biomes follow climate and landform constraints rather than arbitrary cell labels
- screenshots are compared against named references before the plan can call the result realistic

Hydraulic erosion can start as an offline or chunk-generation-time macro pass, but the engine should not depend on running expensive droplet simulation for every near chunk at runtime. The likely path is cached regional terrain products: generate or load region-scale height/erosion summaries, then derive chunk-level fields and voxel materialization from those summaries.

PlanetSmith demonstrates a cheap hybrid for local volumetric detail: keep a 2D height-map base, evaluate 3D noise only near the surface, and derive cave footprints in 2D before placing them at depth. This is relevant to Zigcraft's performance model, but it does not satisfy the causal-terrain contract by itself. It can become a late materialization technique only after the canonical atlas has already established geology, drainage, climate, caves, and landform meaning.

## Initial Build Order

For a fresh foundation, the first version should be intentionally narrow but architecturally honest:

1. **Region terrain previewer.** Build a standalone 2D/heightfield previewer for `RegionTile` output before in-game chunks. It should show continent, terrain, rivers, lakes, wetlands, erosion, gradient, biome candidates, and surface hints.
2. **World query API.** Define deterministic queries over the accepted region product: height, density/material hints, biome, moisture, gradient, river distance, drainage, and feature masks.
3. **Performance harness.** Add terrain-product timings and gameplay traversal benchmarks before optimizing renderer details.
4. **Minimal near chunks.** Data-only chunks, hidden-face mesh generation, compact block IDs, and simple frustum culling.
5. **Async generation and meshing.** No main-thread chunk generation. Region tiles, voxel materialization, meshing, and upload all have explicit readiness states.
6. **Storage variants.** Add uniform/layer/palette storage before RLE. Add RLE only once natural-terrain benchmarks show the payoff.
7. **Far summaries.** Add far terrain from the same region cells, not from downsampled near meshes or a separate height function.
8. **Near/far seam benchmark.** Do not proceed until traversal across near/far boundaries is visually and temporally stable.
9. **Greedy meshing and compact vertices.** Optimize near mesh production once the baseline bottleneck is measured.
10. **Region culling and occlusion planning.** Add broad-phase culling before fine-grained chunk checks explode.
11. **Erosion pass.** Add region-scale erosion products and verify terrain quality under far LOD.
12. **Surface features.** Add trees/rocks/roads/settlements as stable queries, not random chunk-local noise.

For Zigcraft-Neo specifically, the next terrain step should not be more constants or more named terrain families. It should be a terrain-model reset:

1. Keep the Plan v3 measurement stack and streaming runtime improvements.
2. Freeze the current generator as a diagnostic baseline, not as the realism foundation.
3. Build a small region-terrain prototype outside the hot path: heightmap, drainage, erosion/deposition, and material strata.
4. Compare it visually against ReTerraForged/TerraForged-style references before integrating it.
5. Only then wire the accepted region product into near chunks and far LOD.

## Architectural Commitments

- One terrain graph feeds near chunks, far LOD, collision, feature placement, and multiplayer base generation.
- Far LOD is not a lower-quality copy of near rendering. It is its own representation with its own readiness and continuity rules.
- Near chunks are optimized for interaction and rebuild granularity.
- Far tiles are optimized for view distance and stable silhouettes.
- Dense arrays, palettes, layer compression, and RLE are storage options, not ideology.
- Terrain generation is deterministic and summary-friendly.
- Terrain is first a cached regional product; independent per-column sampling is only a query interface over that product.
- Erosion and realism are part of the generator contract.
- Benchmarks must include player movement through realistic terrain.
- The engine must be allowed to say "not ready yet" rather than showing mismatched near/far terrain.

## Open Design Questions

- What chunk size wins under realistic terrain, not flat terrain?
- Should edited chunks permanently fall back to dense/palette storage while untouched chunks remain compressed?
- How much of hydraulic erosion should run offline, region-generation-time, or chunk-generation-time?
- Can a height-map macro layer coexist cleanly with voxel caves and overhangs, or should the core field be density-first from the start?
- What is the simplest near/far transition policy that looks acceptable without expensive transparency?
- How should water paths be represented so far terrain, near voxels, and gameplay agree?
- What is the minimum drainage / erosion model that creates good-looking terrain without destroying chunk-generation performance?
- Should terrain regions be generated as cached region products before chunk materialization, rather than sampled as independent columns?
- What visual references define "realistic" and "good" for Zigcraft: ReTerraForged, TerraForged, real DEMs, Minecraft mod packs, or a custom stylized target?
- How much generation metadata should be stored per region to support AI/world-history systems from [[Dwarf World Game Concept]]?

## Working Principle

The foundation should optimize for one hard demo before feature expansion:

> Fast flight through a large, realistic, mountainous voxel world with far terrain visible for kilometers, no main-thread hitches, stable near/far transitions, and deterministic terrain that can later support editing, water, caves, lighting, and surface features.

If a subsystem does not help that demo, it is probably not part of the foundation.
