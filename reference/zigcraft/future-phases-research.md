# Future Phases Research Foundation

Research and execution guidance for Zigcraft Neo V3 Phases 6–10.

**Research snapshot:** 2026-07-09, after Phase 5d hardening commit `3a1626f`.

This document prepares the remaining foundation phases before implementation
starts. The vault implementation plan and [`docs/gates.md`](gates.md) remain
normative. This document fills in the missing algorithms, ownership seams, data
contracts, measurements, failure modes, and primary-source rationale needed to
execute those phases without repeating the V1/V2 mistakes.

## 2026-07-11 addendum: Dwarf Fortress living-world foundation

The Dwarf Fortress north star now has a dedicated, confidence-labeled research
synthesis:
[`dwarf-fortress-worldgen-ecology-resources-research.md`](dwarf-fortress-worldgen-ecology-resources-research.md).
It combines first-party Bay 12 pipeline/data evidence with primary natural-
systems and procedural-game-design research. The authoritative implementation
contract is the revised [`world-creation-plan.md`](world-creation-plan.md).

The transferable DF lesson is a persistent hierarchy, not literal biome tables
or three repeated cavern layers:

```text
geologic history and material provenance
  -> strata, structures, primary mineralization, hydrologic substrate
  -> terrain, sediment, surface/subsurface water
  -> seasonal climate, soil, vegetation, ecoregions/ecotones
  -> habitat patches, species ranges, aggregate populations
  -> viable sites, transport, resources
  -> later settlements, economies, civilizations, and history
  -> expedition and mutable runtime continuation
```

Biomes are derived summaries. Mineralization is stored as sparse genetic 3D
`DepositRecord`s whose host/event/process permits them, not noise blobs. Soils
derive from climate, organisms, relief, parent material/provenance, and time.
Caves/aquifers follow geology, recharge, chemistry, structure, and named
surface connections; underground habitats also require water, temperature,
chemistry, space, and energy. Fauna truth is a connected habitat/range plus
aggregate stock, not independent chunk spawn rolls. Local one-metre voxels,
plants, and animals realize these persisted parents only where needed.

This changes the foundation boundaries without placing centuries of history or
every creature into Phase 6:

- **6R1a** establishes stable typed causal IDs/provenance and product versioning,
  but writes no empty speculative ecology/history layers.
- **6R2** expands to `GeologyAtlas`: ordered events/provinces, narrow
  lithostratigraphy/structures, provenance, hydrologic substrate/aquifer and
  karst eligibility with stable hydrogeologic-parent IDs later aquifer units
  refine, plus tagged protected primary mineralization envelopes with stable
  IDs and conserved quantity/grade bounds.
- **6R3** must route using coarse permeability, regolith/soil-water capacity,
  vegetation/ET, recharge/loss, and any basin-changing groundwater transfer.
  It cannot freeze substrate-blind rivers and let Phase 7 silently contradict
  them. 6R4 persists final typed recharge (`RechargeZoneId`), reach/lake-loss,
  parent-transfer, and discharge-to-real-surface-receiver records, with any
  spring carrying stable ID/location/receiver, in `HydroGraph`; later
  `SubsurfaceAtlas` only references/refines them.
- **6R4** adds surficial sediment and persists permitted placer/weathering
  descendants as tagged derived `DepositRecord.parent` envelopes only where
  source geology plus final transport/deposition permit them. Bodies wait for
  7C.
- **6R5b** certifies an internal nonshipping physical prefix, preserves the
  unused Phase 7/reserve envelopes, and keeps normal profile selection disabled.
- **Phase 7** becomes five gated slices: 7A complete atmospheric
  `ClimateAtlas`; 7B soils/vegetation/actual-ET reconciliation and `EcoAtlas`;
  7C causal resource bodies, aquifers/caves and `SubsurfaceAtlas`; 7D
  `HabitatAtlas`, Limited-prefix world-design validation and the complete site
  portfolio/index; 7E exact-enabled-binary certification and first normal
  profile exposure.
- **Phase 10** block edits and minimal idempotent natural-source extraction/
  depletion bookkeeping consume persisted strata/deposit/cave truth atomically.
  Full mining tools/yields/economy remain post-10. Discovery, depletion,
  succession, population/entity changes, and edits live in `WorldSave`, never
  in the immutable root.

Naturalism and game design are deliberately separate stages. One literal full
canonical input (seed, topology/extent/scale, base/content recipe and ordered
profile layers) produces one accepted world. `NaturalPotential` creates the
causal candidate; a bounded, deterministic, versioned `WorldDesignPass`
guarantees a dispersed portfolio of viable and non-dominated site choices,
records every candidate selection/repair plus its write-set descendant
recomputation in the Limited common prefix before hashing, and preserves local scarcity and
regional strategy. `PresentationPolicy` may simplify or exaggerate for beauty
and legibility. Whole-atlas rerolls, seed allowlists, elapsed-time search, pity
resources/fauna after site selection, and omniscient hidden-resource maps are
forbidden.

Each hard-repair class either commits a candidate before affected descendants
are generated or caps repair count and cumulative recomputation. Every repeated
operation charges its original geology/water/landscape/ecology/validation row;
the initial build plus worst case must fit each row and total profile cap.

All profiles share the same viability and causal floor. Limited owns protected
parent deposits, underground topology, ecological capacity, and later major-
history identity. Detailed reproduces Limited before one canonical layer; Deep
reproduces both before its own layer. They may subdivide/refine, but cannot add
unrelated wealth, biomass, or a contradictory past. The provisional stage
budget is consequently rebalanced in the canonical plan: 25% geology/resource
parents, 20% Phase 6 surface/subsurface water, 20% landscape/sediment
descendants, 5% Phase 7 coupled climate/soil/cover water, 10% hydrology-
independent living-world/design/complete-site work, 10% validation/persistence/
map indexing including Phase 6 `SiteIndex.physical`, and 10%
reserve. 6R5b cannot borrow the unimplemented Phase 7/reserve envelopes. These
shares remain measured; the 4/10/15-minute totals do not.

After Phase 10 the planned dependency order is living ecology/resource play →
settlement/economy/transport → bounded civilization/world history with physical
evidence → colony-simulation continuation. Pre-embark history is generated-root
truth; post-embark history uses the same semantic events in `WorldSave`. The
future 25–30-minute profile is a candidate for deeper bounded history only once
those readers exist.

## 2026-07-11 supersession: offline finite-world creation

**The original Phase 6 execution path below is historical research, not the
current roadmap.** The game now begins with mandatory creation of a massive
finite world, persists an immutable atlas, presents an expedition-selection
map, and only then prepares and enters the selected one-metre play area. The
selected generation profiles have hard upper bounds of 4 minutes (limited),
10 minutes (detailed), and 15 minutes (deep); a possible 25–30 minute profile
is deferred. The current plan and product contracts live in
[`world-creation-plan.md`](world-creation-plan.md), with algorithm evidence in
[`offline-worldgen-hydrology-research.md`](offline-worldgen-hydrology-research.md)
and the finite-atlas geology decision recorded in
[`worldgen-landmass-tectonics-research.md`](worldgen-landmass-tectonics-research.md).

The visible Phase 6 hydrology result is a **human visual FAIL**. Its loose
drainage topology is useful prototype evidence, but one- or two-block ribbons
placed on top of terrain are not acceptable rivers. A production river is a
coupled valley, floodplain, bankfull channel, bed, water surface, sediment, and
material product whose width and depth respond to accumulated discharge. The
prototype must not be tagged or treated as Phase 6 completion.

Persistence is now also a foundation contract. Generation automatically
persists an immutable `GeneratedWorldRoot`; embark creates a separately
versioned, restart-loadable `WorldSave` containing only current site/player
state at first. Future break/place state is a sparse durable voxel-delta layer,
and future entities use a separate versioned layer without rewriting the root.
Consequently, the historical Phase 10 statements below that defer all disk
persistence are superseded: session editing may not ship if it vanishes on
process exit.

The finite-atlas decision removes the need to discover and close a basin from
an arbitrary runtime coordinate. It permits connected-ocean and landmass IDs,
whole-atlas depression handling, drainage and climate forcing, stable basin and
reach identities, and a global topology that can be validated before play.
It still does not justify a global one-metre raster: macro geology and climate
remain coarse, drainage uses a bounded raster, hydrology is persisted as a
compact reach graph, and one-metre terrain/channel evaluation is adaptive to
selected and streamed play regions. Each detail profile runs a deterministic,
fixed-work recipe; higher profiles refine one protected macro world rather than
silently generating unrelated topology. Concretely, Detailed is the byte-
identical Limited prefix plus one canonical layer; Deep reproduces both before
appending its own layer. All layers enter `WorldBuildId`.

The replacement Phase 6 sequence is:

- **6R0 — direction reset and research:** ratify finite world creation, detail
  profiles, budgets, persisted products, and river-quality criteria.
- **6R1a — finite container and generation coordinator:** add the rectangular
  ocean-apron root, Home/New World/Generation Progress shell, fresh visible
  collision-checked default seed, nested profile/identity schema, request
  deduplication, worker progress/cancel, a basic pause/return-Home state,
  versioned staging, verified unlisted root finalization, and a minimal atlas
  around the current terrain product.
- **6R1b — atlas/expedition/load vertical slice:** validate the interactive map,
  atomically no-clobber catalog its root, activate Continue/Worlds, create a
  fresh minimal atomic `WorldSave` v1, select a site, complete Pause Save/Save
  & Return Home/Save & Quit, prove return/quit/process-restart/Continue/load,
  prepare a bounded local spawn, and enter/reload first-person runtime.
- **6R2 — macro geology and topobathymetry:** generate explicit connected
  oceans, landmasses, event/province/lithostratigraphic context, structures,
  provenance, hydrologic substrate/aquifer classes with stable hydrogeologic
  parent IDs, protected primary resource parents, and compare analytic causal
  versus finite evolutionary approximations under profile budgets.
- **6R3 — whole-world hydrology skeleton and preliminary runoff:** compute
  depression/lake/endorheic policy, protected basins/outlets, preliminary flow
  and exact accumulation, and `HydroClimate0` from coarse climate, substrate,
  cover/ET, recharge/loss and protected groundwater transfers for erosion.
- **6R4 — landscape evolution, canonical graph, and river geomorphology:**
  couple bounded erosion/deposition, compute final-relief `HydroClimate1`,
  pass a bounded forcing-residual/correction gate for every profile-effective
  terrain, reroute/reaccumulate, publish one terminating reach/lake DAG, then
  build vector centerlines and voxel valleys, floodplains, banks, beds, and water.
- **6R5a — profile and expedition integration:** enable the already-landed
  detailed/deep child refinements only in internal acceptance builds and finish
  site/map/query/migration semantics; normal player selection remains disabled.
- **6R5b — physical-prefix acceptance and closeout:** freeze internal recipes/
  resource/load caps, rerun deterministic timing, persistence, topology,
  groundwater, lake/river, full-flow and human visual gates, preserve the
  Phase 7/reserve envelopes, and tag Phase 6 without normal profile exposure.

Where later sections assume an infinite signed grid, seed-only macro keys,
runtime frontier closure, immediate playable spawn, or the old Phase 6 closeout
path, this dated section supersedes them. Their measurements and failure-mode
analysis remain inputs to the redesign. Later numbered phases resume only after
6R5b, with the five-slice living-world Phase 7 conditioned to reproduce frozen
`HydroClimate1` surface-water/recharge budgets and transfer topology; a material
mismatch rejects the development recipe and requires a cold versioned Phase 6
rebuild/acceptance rerun—not an unbudgeted shipping-world retry. Phase 7E alone
enables and certifies normal profile exposure,
then measured generation/runtime optimization, view distance, and the hard
gameplay demo.

## Legacy body status

Everything below this banner is the frozen 2026-07-09 infinite-world research
snapshot unless a paragraph explicitly says otherwise. Its measurements,
sources, fixtures, and failure analysis remain useful, but its active-sounding
"Executive decisions," phase ownership, pipeline, and gate tables are **not the
current handoff**. Do not execute them directly. The dated supersession above
and `world-creation-plan.md` win every conflict.

It is intentionally not an implementation spec with every constant frozen.
Future work should treat statements according to this legend:

- **Lock:** an architectural constraint or correctness contract that should not
  be rediscovered during the phase.
- **Default:** the smallest researched starting point. Replace it only when a
  gate or measurement demonstrates a better choice.
- **Measure:** a value or technique that must be selected from real V3 data.
- **Defer:** explicitly outside the foundation unless the default fails a gate.

## Historical 2026-07-09 executive decisions (superseded)

| Phase | Decision to carry forward | Why it matters |
|---|---|---|
| 6 | Hydrology must be a canonical cross-region drainage product, not an independent `RegionTile` filter. | A 256-cell core plus 32-cell halo cannot know basin-wide accumulation, spill elevations, or stable outlets. |
| 7 | Regenerate one causal product in the order hydro → erosion/deposition → hydro reconciliation → climate → biome → surface. | Patching already-final tiles creates seams and lets derived fields disagree with changed terrain. |
| 8 | Fix measurement truth and bounded residency first; then optimize only the measured leader. | Current memory reporting omits major CPU and GPU pools, so later budgets would otherwise be fiction. |
| 9 | Before implementation, ratify what “10 km visible” means. This research recommends a conservative camera-to-edge **radius**, with radius and span emitted separately, then budgets radius 40. | Current `visible_km` is an edge-to-edge span; reaching a 10 km span is only about a 5 km view radius. |
| 10 | Make edits a revisioned sparse overlay over deterministic base truth, and build a real translucent water pass. | Current zero-index mesh handling can misclassify occluded solid chunks as air, and water is submitted without blending/depth-write control. |

The smallest coherent product pipeline is:

```text
pure point base landform
        ↓
canonical macro drainage product (Phase 6)
        ↓
regional fine carve + lake/wetland semantics
        ↓
canonical erosion/deposition + final drainage reconciliation (Phase 7)
        ↓
ground derivatives → climate → biome → surface material
        ↓
immutable final RegionTile → conservative FarSummary → chunks/meshes
        ↓
session edit overlay (Phase 10; base product remains immutable)
```

## Current foundation audit

### Existing truth worth preserving

- `RegionTile` is the immutable one-truth product. It stores a 256×256 core
  plus a 32-cell border, or 320×320 cells total.
- The current cell product already separates visible `height` from solid
  `floor`; that is exactly the seam rivers and lakes need. Dry land has
  `floor == height`; water can use `floor = bed` and `height = water surface`.
- Existing semantic fields include gradient/slope, material, land,
  continentalness, uplift, plateau, and ocean context. There are not yet honest
  hydrology, climate, or biome fields.
- The current `distance_to_ocean` is explicitly a continentalness-derived coast
  proxy, not a distance field. Phase 6/7 must replace it with a canonical
  seam-consistent distance transform before any outlet or climate rule treats
  the value as physical distance.
- Region generation, chunk materialization, and near/far meshing run on workers.
  OpenGL upload and drawing still run on the frame thread. Keep the
  no-frame-thread **generation/materialization/meshing** contract without
  mislabeling rendering itself as asynchronous.
- Far and near geometry already derive from the same region product. Future
  summaries must remain conservative reductions of that truth.
- Corner ambient occlusion already exists in `src/mesh.zig` using three-neighbor
  corner tests and diagonal selection. Phase 10 must extend lighting only where
  evidence says it is missing, not reimplement AO.

### Quantified memory reality

The current accounting is incomplete. These sizes are derived from the actual
types and capacities in the Phase 5d code:

| Item | Exact/current size | Consequence |
|---|---:|---|
| One `RegionTile` field payload | 3,891,200 B = 3.711 MiB | Radius-2 field payload (25 tiles) is about 92.77 MiB. Struct/map/allocation overhead is additional. |
| One `FarCell` | 20 B | The type has three padding bytes that may hold compact flags, but not an unconstrained set of new floats. |
| One `FarSummary` array payload | 87,360 B = 85.31 KiB | The stale ~44 KiB comment is wrong. Struct/map/allocation overhead is additional. |
| 1,225 summaries | about 102.06 MiB | This approximate radius-17 retention is omitted from the current memory gate. |
| One dense chunk payload | 32 KiB | Every chunk pays this inline cost even when uniform or air. |
| 6,848 chunk payloads | about 214 MiB | This explains much of the current CPU chunk footprint. |
| `GpuVertex` | 68 B | It repeats a 12-byte chunk offset per vertex. |
| Fixed scene arena capacity | 836,000,000 B = 797.3 MiB | 5M near + 6M far vertices and 10M + 12M `u32` indices are reserved. |

The reported approximately 771 MB `mem_peak` samples only
`world.residentBytes() + scene.resident_bytes`. It does **not** include every
`RegionTile`, `FarSummary`, queued/far CPU mesh, process overhead, atlas, GPU
capacity/fragmentation, or future hydro/edit caches. It is not an RSS or total
resident-memory measurement.

Other current accounting gaps:

- Upload bytes use the 56-byte CPU `mesh.Vertex`, while OpenGL receives the
  68-byte `GpuVertex`.
- Far upload statistics are discarded rather than included in the total.
- A Phase 5 capture held about 556.59 MiB of live mesh data and 214.63 MiB of
  chunks, with roughly 479 logical draws, while CPU draw encoding was only
  about 0.2 ms in the soak and 0.6 ms in a quick probe. That evidence argues
  against making batching the first Phase 8 optimization.
- `FarSummary` retains far4, far16, and far64 for every horizon region. Far4 is
  81,920 of the 87,360 bytes; removing only far64 saves just 320 bytes.
- The region cache's fixed 40-coordinate eviction scratch can leave far more
  state resident than intended and does not enforce `max_resident_regions = 32`.
  One acceptance artifact reported `reg_res=369`.

**Lock:** this is a Phase 5 closeout condition, not Phase 8 debt. The definitive
post-5d soak was still pending at this research snapshot. It must enforce the
declared region limit and include RegionTile/FarSummary field payloads in its
memory/plateau result. If that cannot land in 5d, open an explicit 5e rather
than carrying the known `reg_res=369`/omitted-pool failure into Phase 6. Phase 8
then completes the deeper RSS/GL/scratch audit before optimizing.

### Gate runner and normative docs must agree

`docs/gates.md` is declared normative, but current runner semantics contain
unrecorded differences: soak acceptance uses work p99 rather than enforcing
worst frame for the whole soak; drift uses a fifth-decile baseline plus a 1 ms
floor rather than first 10% vs last 10%; throughput acceptance uses settled,
canceled, and tail work rather than exactly the printed ratio; and queue ages
are reported without a runnable bounded-growth gate.

Before the Phase 5 closeout and certainly before adding Phase 6 macro queues,
either restore the documented contracts or amend `docs/gates.md` with the
intentional semantics and rationale. Define bounded queue age as an executable
late-window plateau/slope check plus a declared numeric cap where appropriate.
No future report may claim “all floor gates” while relying on a hidden code-only
exception.

### Correctness seams that later phases expose

- `worldgen.column()` and point `blockAt` are currently treated as a final
  oracle. Regional hydrology makes them base-landform queries only. Final tests
  must move to RegionTile determinism, schedule independence, overlap identity,
  and final-query agreement.
- `previewer.zig` directly samples the point generator. After Phase 6, that
  would silently omit rivers, erosion, climate, and biome. Debug views must
  consume the final/canonical products.
- `densityAt` uses visible height, so water can look like positive solid
  density. Phase 6 must distinguish solid occupancy (`floor`) from fluid
  occupancy.
- Spawn and screenshot placement use base `surfaceHeight`. After regional
  carving, wait for final truth. Walking/gameplay spawn must choose a
  deterministic dry, collision-safe location on the final solid floor (search
  a fixed coordinate order if the requested column is open water); only
  fly-mode cameras/screenshots may intentionally use the visible water surface.
- A macro product cannot be built by one bounded worker waiting on another job
  in the same bounded pool. Express prerequisite readiness as a job DAG/state
  transition or use a separately bounded macro-product pool.
- End-to-end throughput, not only isolated region latency, is the relevant
  horizon gate. The current cold far fill of 1,089 regions takes roughly 40 s;
  a historic 350 ms per-region budget would take about 191 s on two workers.

## Cross-phase product and ownership contract

### Canonical keys and versions

Every cached macro product should be keyed by all inputs that change its bytes:

```text
literal world seed
canonical macro-domain coordinate / drainage-domain identity
base generator version
hydrology version
erosion/climate version when applicable
```

Do not include request order, worker identity, process-random hash order, or the
requesting RegionTile in the key. A version bump must invalidate both near and
far products together.

Nonlocal Phase 7 products must also key any fixed climate forcing (for example,
the prevailing-wind regime) and algorithm coefficients that are not already
covered by the version.

### Ownership rules

1. Point world generation owns only the pre-round base landform.
2. The drainage domain owns receiver topology, accumulation, depression/spill
   classification, and stable reach identities.
3. The regional post-process owns fine carving and final semantic rasters, but
   it crops from canonical products rather than solving its own independent
   basin.
4. `RegionTile` owns final gameplay-visible, collision-visible immutable truth.
5. `FarSummary` owns conservative reductions, never an alternate terrain path.
6. The Phase 10 edit store owns sparse deltas over base truth and survives
   chunk/region eviction for the session.

### Persist only fields with readers

Working algorithms may use receiver, indegree, raw accumulation, conditioned
elevation, depression labels, basin IDs, sediment load, temperature, and
moisture. That does not mean all belong in every RegionTile.

An added `f32` raster costs 409,600 bytes per RegionTile and about 9.77 MiB
across 25 tiles. Prefer compact enums and quantized strengths. Keep scratch
fields in the macro product or generation workspace unless collision, meshing,
far aggregation, debug inspection, or a committed future feature reads them.

## Phase 6 — Drainage, rivers, lakes, and wetlands

### Entry checklist

Before implementing visible rivers:

- Verify the Phase 5 closeout already made region-cache residency genuinely
  bounded and included RegionTile/FarSummary payloads in metrics.
- Verify the runnable runner and normative gate semantics—including bounded
  queue age—are aligned before adding a macro-product queue.
- Expose pre-round/sub-block base ground elevation to the regional pipeline.
- Derive real ocean/coast distance from the canonical land/ocean product (or
  use the land/ocean mask directly for outlets); do not route against the
  current continentalness proxy as though it were metric distance.
- Define solid-ground, visible-surface, and fluid query semantics.
- Add a dependency-aware macro-product readiness path that never blocks a
  region worker on the same bounded pool.
- Add the promised `river-valley` benchmark scenario and reserve its fixed
  seed/start/path for the Phase 10 hard demo.
- Add the roadmap's promised `inspect-river` tool, not only visual overlays.
- Replace final point-oracle tests with final-product determinism and overlap
  contracts where appropriate.

### Lock: hydrology is larger than a RegionTile

Independent D8/depression filling inside each 320×320 stored tile is invalid.
The 32-cell halo truncates upstream contributing area, changes basin spill
decisions, and lets two overlapping requests choose different outlets.

Use a separately cached deterministic drainage product. A larger arbitrary
tile and halo by itself is still insufficient: either one canonical owner
solves a complete drainage/watershed domain, or neighboring subdivisions
exchange and merge a coarse boundary/spill graph before final depression fill
and accumulation. Parallel tiled Priority-Flood and distributed D8
accumulation provide the relevant precedent
([Barnes 2016](https://doi.org/10.1016/j.cageo.2016.07.001),
[Barnes 2016 D8](https://arxiv.org/abs/1605.05773)).

Treat that choice as a Phase 6a blocker: no visible carving begins until the
chosen ownership/reconciliation scheme passes the catchment fixture across a
drainage-domain subdivision. If the current continent construction exposes a
finite ocean-bounded landmass identity, solving that canonical landmass is the
simplest owner. Otherwise implement the boundary/spill-graph reconciliation;
never substitute an arbitrary open macro-tile edge.

#### Implemented ownership decision and closure certificate (2026-07-10)

The current infinite warped-fBm land mask has no finite stable landmass ID, so
Phase 6 uses boundary/spill-graph reconciliation. Local perimeter seeds are
dependencies, never outlets; only explicit ocean-surface links seed global
conditioning. The two-subdivision fixture and varied oracle comparisons pass.

Ocean connection in a finite loaded graph is not by itself immutable. For a
target basin, compute minimax distance `d(b)` over loaded basin edges and the
best loaded real-ocean path `U`. Every loaded-to-unloaded seam exposes a lower
bound `q = max(d(inside_basin), exit_lower_bound)`. Scalar conditioning is
closed exactly when `U` is finite and every frontier `q >= U`; otherwise load
the outside subdivision of the smallest `q`, with target-centered expansion
shell before stable subdivision/seam ties, and recompute. Shell-first ordering
is required for fairness on the infinite signed grid. Equality is sufficient
only for scalar height. Receiver/outlet
identity must later expand every `q <= U` edge or define an equally rigorous
finite tie rule. Frontier expansion is resumable in the main-thread
coordinator. Resource-policy pressure is a typed non-ready product, never an
edge outlet; retrying it requires a backend/cache with a larger policy. A full
target-admission table returns an explicit redemand-required error so the wait
is not hidden from metrics.

With one seed per perimeter cell, its local filled height is already a valid
exit lower bound. Closure derives the complete cut and outside owners by
scanning every perimeter cell of complete canonical scalar summaries; it never
accepts a loose caller-supplied frontier slice. Runtime summaries must retain
enough perimeter data to perform that derivation before cache publication.

The implemented compact product stores original/fill/local-seed rasters in
12 bytes per cell plus a packed ocean bit, reduces D8-connected ocean to one
component seed, and stores only 8-byte perimeter and 16-byte reduced-spill
records. Durable output and fixed scratch arenas are separate; spill and ocean
component counts have explicit operational caps. The production path samples
worldgen directly into the durable raster, so the 48.5 MB 2000² base product
is not doubled by a fixture staging array.

Runtime scalar closure is evaluated for the whole target subdivision, not one
arbitrarily chosen basin. Multi-source minimax passes compute each basin's
best ocean cost `U` and best frontier lower bound `F`; every target-owned basin
must satisfy finite `U` and `F >= U`. A threshold-component pass resolves the
stable frontier label only after numeric `F` is known; this avoids losing the
preferred equal-key exit when a higher edge equalizes paths after a merge.
Main-thread orchestration consumes an intermediate expansion result, evicts
that attempt, grows the canonical dependency set dynamically, and redemands.
There is no compiled 32-subdivision horizon. Cache-owned dependency and
in-flight pin arrays have a separate metadata-byte cap. Configured
build/reconciliation pressure remains a typed non-ready result and never
publishes a partial product; same-cache automatic resumption is not claimed.

The refreshed bounded ReleaseFast compact probe measured 2000² local builds at
1.36–1.91 s. Authenticating and reducing a dense local product took
86.28–96.88 ms, but the durable scalar result is only 148,716–236,000 bytes
instead of 48.68–48.79 MB. Single-summary scalar frontier decisions took
2.40–4.09 ms in an exactly estimator-sized 20.49–22.59 MB fixed arena. Every
full-scale row expanded, so the matrix does not measure closed-target rebuild
or distinct-cache residency. This still rejects cold 500 ms readiness without
prefetch/smaller subdivisions/
reviewed concurrency, but removes dense dependency residency and does not
choose the 8/16/32 m scale; topology and common-window fidelity still do.

#### Implemented receiver-only checkpoint (2026-07-10)

The first half of researched steps 4–5 is now executable in
`src/drainage_d8.zig`. A closed target uses one dense conditioned-height raster
and packed ocean mask; dependencies contribute only a one-cell halo and sparse
flat extensions. Strict descent compares normalized D8 slope and global z/x
ties. Each exact-height connected flat chooses one canonical lower outlet and
receives an acyclic breadth-first tree toward it. Target cells store one `u8`
receiver code; cross-subdivision receivers also emit sorted global-cell portal
identities.

Sparse closure is explicit. If any neighbor of a target-reachable flat
component is absent, receiver publication stops and returns the exact missing
global cell together with its owning subdivision. Selection is stable by
target shell, owner z/x, then cell z/x. This exact-cell contract is necessary:
returning only an owner would stop making progress after a flat had already
entered that owner through sparse support.

The 2000² ReleaseFast exact-arena probe used an 8,004-cell halo. Dense target,
mask, and support input are 16,692,096 bytes; receiver scratch is 69,216,660
bytes; maximum receiver/portal output is 4,255,872 bytes. Including the pinned
50,180,352-byte compact-product reservation gives a conservative simultaneous
peak of 140,344,980 bytes under the 384 MiB job ceiling. Both fixed arenas
reclaimed to zero. The refreshed 20.54 ms all-ocean observation isolates
allocation and terminal-cell traversal and must not be used as representative
land/flat performance. Evidence: `docs/acceptance-06/d8-receiver-probe.txt`.
The peak assumes halo values are staged sequentially and full neighbor compact
interiors are released before routing; holding the target plus eight complete
neighbor pins would break the ceiling, so the eventual coordinator must enforce
that lifetime boundary.

The receiver-only boundary did **not** implement researched step 6. A closed
downstream receiver cut says nothing about unseen upstream contributors, so
missing upstream tiles cannot be interpreted as zero inflow. The finite-cut
algebra checkpoint below solves the recurrence; deterministic reverse upstream
closure is implemented by the later checkpoint below and remains required
before publication.

Local or portal cycles are hard errors; `u64` addition is checked rather than
saturated. Policy pressure is a typed non-ready result, allocator exhaustion is
an unexpected job failure, and no partial accumulation becomes ready.

#### Implemented finite-cut flow algebra checkpoint (2026-07-10)

`src/drainage_accumulation.zig` implements the Barnes-style local-variable /
global-solve / target-finalize seam for non-divergent D8 flow. A subdivision
summary stores `C(p)`, the tile-owned land runoff reaching each first outgoing
portal, and `g(e)`, the first outgoing portal or ocean sink reached from every
canonical perimeter entry cell. The global portal recurrence is:

`Y(p) = C(p) + sum(Y(u) where u enters at e and g(e) = p)`.

Because D8 merges but never splits, each incoming variable has coefficient one
and one terminal portal. The complete transfer is therefore O(perimeter): at
2000² its maximum is 159,920 bytes. Builder-owned immutable summaries use a
private content binding; target finalization independently checks that every
target portal source equals its solved portal amount.

The finite solver uses portal nodes, never subdivision nodes. This preserves a
valid A→B→A→B path through distinct cells and portals. It injects all resolved
entries at exact target cells and runs local Kahn accumulation with land runoff
one, ocean runoff zero, checked `u64` addition, and hard local/portal cycle
errors. The differential suite includes cardinal and diagonal confluences,
leave/re-enter, reversed summary order, malformed/stale algebra, and an eager
global-cell oracle.

Worst-address 2000² summary scratch is 20,000,003 bytes. The initial finite-cut
policy caps at 512 summaries / 4,093,952 portals: summary pins are 81,879,040
bytes, solve scratch is 81,955,303 bytes, dense target output is 32,000,000
bytes, and the conservative peak including compact/receiver state is
250,270,567 bytes. A 1,024-summary arithmetic peak is 414,040,935 bytes and is
rejected above the 384 MiB job ceiling.

The ReleaseFast probe builds the 2000² maximum 7,996-portal summary and solves
a synthetic 500-summary / 3,310,344-node cut twice in reversed order. The
66,218,887-byte solve arena is exact, hashes match, and all arenas reclaim. Its
shared portal/boundary templates make the ~100 ms result reservation evidence,
not a distinct cache-residency benchmark. Evidence:
`docs/acceptance-06/accumulation-probe.txt`.

`FiniteCutAccumulation` is intentionally provisional and currently requires a
portal-closed supplied cut. That requirement cannot drive runtime discovery:
an irrelevant ring probe may drain outward forever. The following checkpoint
supplies the required layer: it builds a predecessor-closed set of only portals
that can enter the target (including leave/re-enter chains), requires the
eight-neighbor summary ring for each newly relevant owner, and ignores missing
successors of irrelevant portals. Only its closed result may carry the target's
checked `u64` bytes forward.

#### Implemented reverse upstream closure checkpoint (2026-07-10)

`accumulateUpstreamClosedWithAllocators` now performs that proof. Loaded
summaries are canonicalized, every portal entering the target seeds a reverse
predecessor walk, and only the resulting target-relevant portal set is solved.
The complete eight-neighbor summary ring is required around the target and
every relevant portal owner. An absent required neighbor returns one
deterministic expansion by target Chebyshev shell then z/x; an absent successor
of an irrelevant outward portal is ignored. Leave/re-enter chains remain
portal-level dependencies rather than false tile cycles.

Closed output has a distinct `ClosedTargetAccumulation` type and checked exact
`u64` cell values. Expansion allocates no output. Hidden cardinal/diagonal
contributors, guard growth, irrelevant outflow/cycles, relevant cycles,
reversed order, eager-oracle agreement, exact fixed arenas, and typed resource
caps are test-pinned. The exact 512-summary / 4,093,952-portal scratch bound is
82,467,047 bytes; including compact/receiver state, summary pins, and dense
output gives a 250,782,311-byte conservative peak. The 1,024-summary case is
415,064,423 bytes and remains rejected above 384 MiB.

The ReleaseFast probe scans 509 summaries containing 3,310,344 deliberately
irrelevant portals twice in reversed order. Exact scratch is 66,632,903 bytes,
the 32 MB output and scratch arenas reclaim to zero, both hashes match the
all-ocean finite-cut baseline, and the measured conservative peak is
222,314,487 bytes.
Evidence: `docs/acceptance-06/accumulation-probe.txt`.

#### Implemented scalar conditioning residency checkpoint (2026-07-10)

The production compact backend now reduces each authenticated dense local
product to an owning immutable conditioning summary before it enters the
cache. Perimeter, reduced spills, ocean roots/surface, and a content binding
remain; the approximately 48.7 MB dense dependency is released. A closed
attempt rebuilds only the target dense product, verifies its reduced binding,
and transfers target ownership into the product without retaining a summary
pin. The refreshed 2000² matrix observes 148,716–236,000-byte summaries and
2.40–4.09 ms one-summary scalar frontier decisions. All full-scale rows expand;
a mixed-coast regression separately proves byte-identical closed target rebuild
with reversed summary order. Evidence:
`docs/acceptance-06/compact-local-probe.txt`.

The readiness cache now admits the entire simultaneous working set under one
ceiling: backend-live bytes, pending output reservations, scratch, dependency
metadata, and reconciliation pins, including the worker-completion overlap.
Intrinsic excess is typed policy pressure; transient occupancy waits. With the
candidate 20,000-spill/4,096-ocean-component/192 MiB-frontier arithmetic policy,
384 MiB admits 256 maximum-size scalar summaries and rejects 512 before work.
The exact current-cut frontier estimator may reject earlier.

This discharges pipeline step 6 algorithmically for one reverse-closed target
and removes dense scalar-closure residency as the immediate coordinator
blocker. Common-window scale/topology/fidelity selection, production expansion
across scalar summaries, D8/support and upstream cache orchestration, stream
topology, classification, carving, and rendering remain separate checkpoints.

#### Implemented production scalar-closure probe (2026-07-10)

The production one-worker cache now closes real worldgen conditioning cuts
through the monotone `Expansion` driver. Under one shared 284 MiB frontier /
384 MiB combined policy, seed 1 closes at 8, 16, and 32 m in 21.02–21.13,
13.25, and 14.53 seconds. The cuts contain 13, 7, and 7 scalar summaries and
reach target shells 2, 1, and 1 respectively. Every run has zero cap hits and
worker failures; the 8 m repeat reproduces expansion, dependency-cut, and
closed-product hashes.

The 8 m static admission requirement is 399,957,816 bytes, only 2,695,368 below
the hard ceiling. The 256-entry table therefore has only a 21-summary effective
maximum-reservation cut under the final policy. The shared 284 MiB reservation
makes every scale appear similarly close to the ceiling and does not establish
scale-specific minimum scratch. The polled accounted gauge is not RSS or a
guaranteed peak; static admission is the cap proof. Evidence:
`docs/acceptance-06/scalar-closure-probe.txt`.

This is real scalar conditioning closure and cache-residency evidence, but it
does not yet build the D8 support cut, flow summaries, or reverse-upstream
product for the same target. It also does not compare the three scales over a
common physical window. Coverage is seed 1 / target `(0,0)`, serial cold work,
two 8 m samples, and one 16/32 m sample—not a p95. Those gaps remain blocking
before scale selection.

#### Implemented production-shaped D8/support probe (2026-07-10)

The production-shaped D8 probe now closes the eight one-cell-halo owners
serially, copies only exact conditioned support, releases each dense neighbor,
and routes one closed target through fixed scratch/output arenas. Missing
target-reachable flats request an owner, exact cell, and exact component height;
the coordinator stages the matching owner-local component plus its one-cell
ring. Unequal requests use a bounded 256-cell band/box of real conditioned
samples. That physical overfetch varies with candidate cell size and remains a
probe coordinator policy, not an accepted production prefetch rule.

With a 192 MiB reconciliation arena leaving room for retained D8 output, the
seed 1 target `(0,0)` reaches receiver-ready at 16 m in 219.68 seconds and at
32 m in 241.45 seconds. The rows stage 3,073,435 and 3,899,395 support cells;
peak conditioning-static-plus-retained bytes are 391,491,912 and 395,150,800,
and peak support-patch working bytes are 248,856,108 and 242,695,488. Every
explicit payload/reservation lifetime stays under 402,653,184 bytes. This is
logical internal accounting rather than an RSS measurement. The 8 m candidate
returns a typed 204,956,183-byte reconciliation-scratch requirement before D8,
above this policy's 201,326,592-byte arena.

The common window is exactly `[4096,12288)` metres on both axes. Current
counters establish its mapping and normalized ocean/cardinal/diagonal/flat-edge
direction statistics for the ready 16/32 m rows only. They do not establish
spatial agreement, stream topology, exact contributing area, or scale fitness.
The built target `FlowSummary` proves a local acyclic receiver transfer product;
at this checkpoint real reverse-upstream closure still needed neighbor
receiver/flow summaries. Each ready scale has one final serial cold observation,
not a p50/p95 or repeatability result. Evidence:
`docs/acceptance-06/d8-worldgen-probe.txt`.

#### Implemented real-worldgen reverse-upstream probe (2026-07-10)

The next probe now drives the existing reverse-closure kernel over real
conditioned worldgen and real D8 summaries. One persistent scalar cache routes
only the owners requested by `.expand`; each dense receiver is reduced to an
immutable `FlowSummary` and released. Exact conditioned boundary/raster and
target-receiver records are cold-spooled under session-unique exclusive paths,
bound on read, preflighted against live memory, and removed on cleanup. This is
probe orchestration rather than RegionCache architecture.

Seed 1 target `(0,0)` closes at 16 and 32 m in 351.80 and 379.16 seconds under a
10-minute cold-probe deadline. Both rows request the same 22-owner frontier and
finish with 23 summaries; portal totals are 38,534 and 38,552. Their exact
target accumulation hashes reproduce across an earlier observation. Maximum
accounted conditioning plus retained bytes are 393,991,083 and 385,549,771,
below 402,653,184. Temporary disk high-water is about 698.6 MB at either scale,
separate from the logical-memory cap; filesystem page cache, allocator overhead,
and RSS remain outside that contract.

The `[4096,12288)` m common window reports physical contributing-area mean,
maximum, and land-sample threshold incidence. These normalized diagnostics
avoid comparing raw sample counts, but they are not spatial agreement or stream
topology. The per-sample area sum double-counts upstream land along downstream
paths and is not catchment area. Channel extraction, multiple fixed seeds,
visual comparison, and scale selection remain blocking. The 8 m candidate is
still typed-capped only under the separate retained-output policy. Evidence:
`docs/acceptance-06/upstream-worldgen-probe.txt`.

#### Implemented multi-seed scale-comparison probe (2026-07-10)

The next offline seam preserves each exact 16/32 m target as a bound snapshot:
the fixed `[4032,12352)^2` m footprint contains receiver bytes plus exact `u64`
accumulation, while `[4096,12288)^2` m is the uncensored analysis core. Export
streams through a fixed buffer, verifies the complete temporary artifact before
same-directory replacement, and binds the source product fingerprints, key,
window, schema, and body. This is process-level atomic replacement, not a
power-loss durability claim.

Comparison maps every 32 m footprint to its exact four 16 m cells. Channel
presence is OR, never summed accumulation; only all-land/all-ocean footprints
enter agreement, and coast disagreement remains explicit. Fixed exploratory
thresholds are 0.1/0.25/0.5/1.0 km². Exact masks, symmetric 32/64 m L-infinity
support, censored distance summaries, eight-direction graph counts, physical
length/density, crop terminals, confluences, Kahn cycles, monotonicity, and D8
X crossings are emitted. Interior confluences use deterministic
maximum-cardinality/minimum-total-displacement correspondence; receiver chains
then compare the next matched confluence or compatible ocean/crop terminal.
This relation quotient deliberately skips unmatched intermediate confluences
and does not substitute for global Strahler/reach extraction.

Seeds 1/2/3 all close serially below the 600 s deadline and 384 MiB logical
ceiling at both scales. Across 24 native threshold/scale graph rows there are
zero cycles, downstream accumulation decreases, or unresolved X crossings.
Cross-scale fidelity is mixed: exact IoU spans 0.382775–0.641025, <=64 m
fine-to-coarse support spans 0.549222–1.0, and coarse-to-fine support spans
0.833333–1.0. At 0.1 km², only 50–57% of fine interior confluences match; the
conditional downstream relation agrees for 4/4, 15/20, and 11/18 matched pairs.
Higher thresholds have smaller, still mixed samples.

Therefore this checkpoint closes the missing measurement/multi-seed/visual
counterexample seam but does **not** freeze a scale. Three fixed seeds are not a
distribution, no numerical convergence criterion was ratified before looking,
and the categorical four-panel sheets are not carved or rendered river
fidelity. The next scale decision must declare a topology/fidelity criterion,
calibrate against useful external proxy distributions, and include the required
in-game mountain-to-sea evidence. Evidence:
`docs/acceptance-06/scale-comparison-probe.txt` and
`docs/acceptance-06/scale-comparison-seed{1,2,3}.{txt,png}`.

#### Implemented locked scale gate and compact-support repair (2026-07-10)

Protocol 6e9-v1 froze the decision rules before evaluating the final comparator:
native D8 graph accounting must be exact, 32 m must preserve the 16 m network at
the fixed 0.5/1.0 km² support and length gates, conditional 0.1 km² topology must
agree, and 16 m must pass a separate human visual review. Development seeds
1/2/3 rejected 32 m without opening a 32 m holdout. The categorical surveys were
terrain-backed and cryptographically committed; their A/B mappings stayed
unrevealed until the human ratings were recorded and committed.

The first 16 m holdout sequence then exposed a valid resource counterexample:
seed 11 closed and screened eligible, while seed 29 exceeded the 384 MiB logical
ceiling with 4,923,393 sparse support cells. The numbered 6e9a-v2 fix changed
only D8 scratch representation, replacing a duplicated 24-byte
`SupportIndex { CellId, u32 }` record with a sorted `u32` order into the retained
support slice. Exact scratch at the counterexample fell from 270,907,689 to
172,439,829 bytes, a 98,467,860-byte reduction; receiver semantics, terrain,
scales, and decision gates did not change.

The new unseen sequence stopped after two eligible rows as preregistered. Seed
47 closed in 342.27 s and passed with 315 >=1 km² channel footprints; seed 71
closed in 356.97 s but was excluded because 63 channel footprints is below the
fixed 128-footprint eligibility floor; seed 101 closed in 343.95 s and passed
with 546. Both eligible rows have zero graph-accounting failures and repeatable
fine-only transcripts. This made the repaired 16 m **automated** holdout gate
green inside the five-to-ten-minute feedback policy.

Human ratings were committed before the explicit reveal. The mapping showed
four decisive development preferences for 16 m, one for 32 m, and one unclear
row. Preference could not rescue 32 m's automated rejection. More importantly,
the labeled 16 m holdout at seed 101 failed absolute fidelity at 1.0 km², while
seed 47 passed both displayed thresholds. The locked conjunctive rule therefore
selects neither candidate: `outcome=reopen_scale_or_model` and
`scale_selected=false`.

The review also exposed a concrete coastal seam. The survey has no coastline
overlay, but it paints `surfaceHeight <= sea_level` as ocean while worldgen
defines `floor >= sea_level` as land, so sea-level beach land is visually
misclassified. Ocean samples cannot originate channel lines, and a single
ocean endpoint at a valid mouth is intentional; neither fact explains the long
coastline traces. A numbered follow-up must fix the evidence land/ocean
predicate and then address the one-outlet flat rule:
each equal-height non-ocean component currently chooses one canonical outlet
and routes every member toward it, which funnels wide sea-level flats laterally
along the shore even when many cells touch ocean. The follow-up must preserve
acyclic accumulation while allowing physically coherent coastal discharge;
the current protocol may not be rerun or reinterpreted after its valid failure.
Final carved/in-game mountain-to-sea acceptance remains later work. Evidence:
`docs/phase-06-scale-decision.md`,
`docs/phase-06-scale-decision-fix.md`, and
`docs/acceptance-06/scale-decision-probe.txt`.

#### Coastal-flat and truthful-survey repair (2026-07-10)

Protocol 6e9b-v3 repairs both diagnosed causes without reopening 32 m or
changing the numerical gate. Survey v2 shades ocean from the canonical
`worldgen.column(...).land` bit while retaining the same surface relief. For an
ocean-connected equal-height flat, every member with a valid adjacent ocean
receiver becomes a deterministic distance-zero root; breadth-first distance
then routes interior members to the nearest root. Components without an ocean
root retain the previous single lower-land outlet behavior. The implementation
adds no scratch arrays, keeps the exact resource formula, and advances
`hydrology_version` to 2 so old artifacts cannot be current evidence.

The exact 3x3 arena and cross-owner seams prove multiple local mouths, acyclic
termination, sorted/bounded portals, byte-identical output under reversed
input, and full reclamation. Debug/ReleaseFast focused and repository tests,
the ReleaseFast game build, formatting/diff gates, and independent reviews are
green.

Disclosed development seed 101 closes under hydrology v2 in 340.10 seconds with
23 summaries and 38,417 portals. Maximum static/accounted admission is
391,612,321/383,220,829 bytes beneath the unchanged 402,653,184-byte ceiling.
All graph invariants pass; the row remains eligible with 321 >=1 km2 channel
footprints and six ocean terminals; and repeated analysis is byte-identical.
The truthful survey-v2 human result is pass/pass at 0.5/1.0 km2: “both PASS to
me.” This clears only the disclosed development regression. The fixed unseen
order 131, 173, 211, 257, 307 remains blocking until two eligible rows also
pass repeatability and both human panels; `scale_selected=false`. Evidence:
`docs/phase-06-coastal-routing-repair.md` and
`docs/acceptance-06/coastal-repair-probe.txt`.

The unseen application stops before scale selection. Seed 131 closes cleanly
but its 824,157 ppm land share is above the locked eligibility maximum, so it
receives no survey. Seed 173 closes in 343.77 seconds below the logical ceiling,
passes every automated gate with 908 >=1 km2 channel footprints and 11 ocean
terminals, and reproduces byte-identically. Its human result is fail/pass at
0.5/1.0 km2.

The failure is narrower than “too many rivers.” The reviewer prefers the left
panel's greater river count, but rejects one double/parallel-looking segment.
Artifact-level inspection shows a distinct tributary, not duplicated drawing:
it carries 0.50–0.60 km2 and follows a 31-edge run whose first 30 edges point
northeast and whose first 26 sit exactly eight cells beside an 11.78+ km2 main
path; it joins at a 15.13 km2 downstream cell. The higher threshold correctly
removes it. Both panels store identical pixels for the main segment, and the
boolean survey mask makes overdraw incapable of changing width. This reveals a
remaining receiver-topology/fidelity target:
long grid-straight near-parallel tributaries, not river abundance itself.

Because one required unseen panel fails, 6e9b-v3 terminates with
`outcome=reopen_scale_or_model` and `scale_selected=false`. Seeds 211, 257, and
307 remain unopened. Any next attempt needs a new numbered protocol and fresh
unseen order; it must improve the topology rather than clip sub-1 km2 channels
out of the evidence.

#### Selected runtime product and spool-free exact builder (2026-07-11)

The later 6e9c/6e9d work resolves the near-parallel-flat defect with the frozen
hydrology-v3 receiver model and selects 16 m after automated and human gates.
The user explicitly retires further seed sampling: the result is one general
world-generation model, not a set of preferred worlds. Phase 6f1 then adds a
nonblocking scalar-prefetch seam; 6f2a defines the only immutable exact product
and ticketed publication states.

Phase 6f2b now implements the missing real builder. It serially closes scalar
owners, stages a canonical one-cell halo, discovers only missing support on
target-reachable external flats, batches at most 4,096 exact requests in
canonical owner order, routes D8 only after that sparse frontier is complete,
reduces non-target receivers to flow summaries, closes reverse upstream
dependencies, and re-stages final terrain for atomic `TargetProduct`
publication. The production builder has no probe disk spools, deadline loop,
blocking sleep/wait, artifact writer, or worker-side polling; monotonic
queue-age telemetry remains.

The support discovery is the production replacement for the probe-only
256-cell band/box heuristic described above. Its frontier traversal scales with
sparse support plus the target boundary while canonical finite-height
validation still scans the dense target input. Its buffer makes bounded
monotone progress, and `discovery.complete` is proven to exclude a later D8
`.expand`. At side 2000 and a canonical 8,004-cell halo, discovery scratch is
104,807 bytes and the maximum 4,096-request reservation is 229,383 bytes.

Cold real-worldgen closure is READY in 494.20 s for the seed-1 acceptance sample and
460.95 s for the already-disclosed seed-101 compatibility oracle. Peaks are
359,932,696 and 359,602,672 bytes beneath the 402,653,184-byte ceiling. Seed
101 exactly reproduces the frozen final-model receiver and accumulation hashes
`f97e71d405fe802f` / `e0c322a120fe83d6`. The next architecture seam is no
longer exact macro generation; it is RegionCache admission and already-ready
pin transfer into RegionJob. Classification, carving, far hydro, and visible
river acceptance remain later Phase 6 work. Evidence:
`docs/phase-06-exact-builder.md` and
`docs/acceptance-06/exact-builder-probe.txt`.

### Default drainage pipeline

1. **Sample canonical base terrain.** Work in floating/sub-block ground height,
   not already rounded voxel columns. Benchmark approximately equal-cell macro
   candidates—8 m cells over 16 km, 16 m over 32 km, and 32 m over 64 km—and
   choose the smallest domain that passes topology, visual, time, and memory
   gates.
2. **Condition depressions.** Run Priority-Flood from real ocean cells and
   designated canonical outlets, retaining both original and conditioned
   elevations. Priority-Flood produces a drainable DEM in O(n) for suitable
   integer elevations or O(n log n) for floating data
   ([Barnes, Lehman & Mulla](https://doi.org/10.1016/j.cageo.2013.04.024)).
3. **Classify visible lakes.** Connected components of
   `conditioned - original` provide candidate depressions. Use scale-aware
   area/depth thresholds: meaningful basins become level lakes at their spill;
   small pits are routing repairs only. A full nested depression hierarchy is a
   fallback if simple spill labeling fails real cases
   ([hierarchy construction](https://doi.org/10.5194/esurf-8-431-2020)).
   Fill–Spill–Merge runoff-volume routing is a further deferral unless the
   static lake model later needs changing water levels
   ([routing model](https://doi.org/10.5194/esurf-9-105-2021)).
4. **Resolve flats deterministically.** Apply an outlet-aware gradient away
   from higher terrain and toward lower outlets before assigning receivers
   ([Barnes et al.](https://doi.org/10.1016/j.cageo.2013.01.009)). Contract each
   classified lake/flat component to one accumulation supernode with one spill
   edge, or build an acyclic internal receiver tree to that outlet; never pass
   a cyclic flat component into topological accumulation.
5. **Build one receiver per cell.** Start with D8 steepest descent and a fixed
   tie order based on global cell coordinates. D8 makes a simple acyclic merge
   graph and topological confluences
   ([O'Callaghan & Mark](https://doi.org/10.1016/S0734-189X(84)80011-0)). Use
   D-infinity only if measurements show objectionable grid bias
   ([Tarboton](https://doi.org/10.1029/96WR03137)).
6. **Accumulate runoff topologically.** Use indegrees/Kahn order, not capped
   iterative relaxation: `A(v) = local_runoff + sum(A(upstream))`. Phase 6 uses
   uniform runoff. Accumulate contributing cells/area exactly in `u64` across
   the canonical graph, then convert to floating point only for calibrated
   width/depth laws. Threshold streams by contributing **area in m²**, not by a
   resolution-dependent cell count. Climate-weighted runoff is a later,
   separately toleranced product.
7. **Extract real stream topology.** Compute Strahler order from the receiver
   graph, trace segments between source/merge/outlet nodes, and allow crossings
   only when they are the same graph node
   ([Strahler](https://doi.org/10.1029/TR038i006p00913)).
   D8 can create two geometrically crossing opposite diagonals in one 2×2 even
   when receivers are otherwise valid. Scan thresholded channel edges for that
   X case, replace both with one explicit confluence/reach node, select its
   single downstream branch by lower routing potential plus stable global tie,
   and recompute affected stream accumulation/order before sizing or carving.
8. **Scale and carve.** Width, depth, and valley extent are monotone calibrated
   power laws of contributing area/discharge; they are not universal constants
   ([Leopold & Maddock](https://doi.org/10.3133/pp252)). Rasterize each reach
   once at fine resolution, then carve valley, banks, and bed.
9. **Attach wetlands.** Default to low slope plus high topographic wetness
   `ln(a / tan(beta))`, clamping the slope denominator, with river/lake context.
   Here `a` is **specific** contributing area—upstream area per unit contour
   width, with units of length—not the total m² accumulation used for stream
   thresholds. Compute it in physical units so wetland thresholds do not change
   merely with macro resolution
   ([TOPMODEL](https://doi.org/10.1080/02626667909491834)). HAND is an optional
   floodplain field if that default is insufficient
   ([Nobre et al.](https://doi.org/10.1016/j.jhydrol.2011.03.051)).
10. **Finalize surfaces.** Ocean, river, and lake cells use `floor = bed` and
    `height = water_surface`. Recompute ground/visible derivatives deliberately,
    assign materials, and only then build far summaries.

Do not smooth river centerlines in a way that changes topology or creates an
uphill segment. If visual smoothing is required, constrain it to the traced
reach and revalidate the downstream profile.

### Minimal data contract

Default persistent RegionTile additions:

- `hydro_kind: u8` or packed enum: none, ocean, river, lake, wetland.
- A packed `has_open_water`/water-surface-valid bit. It is true for ocean,
  river, and lake; the default wetland is saturated terrain without a fluid
  surface. A deliberately flooded wetland must set the bit explicitly.
- `stream_order: u8` for actual Strahler order.
- One quantized signed river/bank distance **or** compact river strength used by
  carving, materials, and inspection.

Keep `land` as continental/landmass classification. Do not overload it with
hydrology. `material_hint` continues to describe the solid bed/top material
rather than the transparent fluid. Only `has_open_water` cells interpret
`height` as a water surface and `floor` as a bed; dry wetlands keep
`floor == height`.

Default scratch/macro fields:

- original and conditioned elevation;
- D8 receiver and indegree;
- accumulation/contributing area;
- depression, basin, lake, and reach IDs;
- spill elevation and reach graph.

Persist one of these only after naming its runtime reader and byte cost.

### Far-summary contract

Center-sampled material is not enough for a narrow river. For every far cell,
conservatively reduce:

- whether open water, wetland, river, and lake/ocean are present;
- maximum stream order/strength;
- representative water-surface height;
- connectivity through the cell's four edges.

A river present in near truth must remain present in its containing far cell,
and edge connectivity must agree across far cells, RegionTiles, and LODs.

The default 20-byte `FarCell` pack consumes its current three tail-padding bytes:

- `hydro_flags: u8`: four outer-edge connectivity bits plus open-water,
  wetland-present, river-present, and lake-or-ocean-present bits;
- `hydro_meta: u16`: 10-bit integer representative water height (0–1023, the
  current world-height contract) plus 6-bit maximum Strahler order (0–63).

When several surfaces share a cell, choose the representative height by a fixed
rule—max-order river first, otherwise dominant lake/ocean with a stable tie
order. The flags remain conservative even when the representative is singular.
Default coverage is deliberately dropped at this tier. Add compile-time size/
offset assertions, pack/unpack round trips, height/order range checks, and LOD
edge-reduction fixtures.

If exact kind multiplicity, coverage, or a larger height range becomes a real
reader requirement, grow to an explicit 24-byte cell and recalculate every
horizon budget; the current radius-40 retention projection would rise from
about 573.94 MiB to 688.73 MiB before overhead. Add a separate major-reach
ribbon product only if the tested cell pack cannot meet the visual gate.

### Required `inspect-river` tool

For a selected final world cell, print enough canonical state to diagnose a
failed river without opening a debugger:

- literal seed and every product version/key/domain coordinate;
- base, conditioned, carved-bed, and visible-water elevations;
- `hydro_kind`, open-water validity, lake/reach ID, specific and total
  contributing area, receiver, Strahler order, width/depth strength;
- RegionTile and drainage-subdivision boundary crossings;
- the downstream receiver chain through lake spill/outlet to ocean, with a
  visited-set cycle error and a bounded diagnostic limit.

The tool must query the same cached canonical/final products as gameplay. Give
each synthetic fixture an `inspect-river` invocation/snapshot so the output
format remains useful and deterministic; overlays can link the selected cell
to that textual record.

### Determinism and model gates

Required synthetic fixtures:

- bowl with one spill: one level lake and correct outlet;
- flat with one outlet: deterministic routing without cycles;
- two tributaries: one confluence, conserved accumulation, no crossing;
- a 2×2 opposite-diagonal X: deterministically becomes one confluence and one
  downstream branch with recomputed accumulation/order;
- closed depression: one deterministic spill-connected lake; true terminal
  endorheic water bodies are deferred;
- coast: reaches terminate in the ocean rather than stopping near it;
- a catchment/river crossing a RegionTile boundary;
- a catchment/river crossing a drainage-domain subdivision boundary.

Required contracts:

- Identical seed/version/domain bytes across request orders, runs, and worker
  counts. Hash-map iteration must never select a tie.
- The graph passed to accumulation is acyclic everywhere. Each classified
  flat-water component is a single DAG supernode or has an acyclic internal
  receiver tree, and drains through one canonical spill/outlet. Every channel
  has exactly one downstream path to ocean.
- The unquantized routing potential strictly decreases outside classified flat
  water. Final integer bed/water elevations are non-increasing downstream;
  quantization plateaus are allowed only when the canonical receiver topology
  still drains them. Beds stay below water surfaces.
- Confluence accumulation satisfies the recurrence. Downstream accumulation,
  width, and depth do not shrink below their contributing tributaries. Strahler
  recurrence is exact.
- Adjacent RegionTile overlap bytes match. Both sides of a drainage-domain seam
  agree on receivers, topology, accumulation, and rasterized water.
- `floor <= height`; the pre-quantized lake surface equals its spill elevation,
  and both produce the same final integer surface under the one declared
  quantizer; banks and beds agree with final solid terrain.
- Far hydro is a conservative reduction of near truth and major reaches remain
  connected across region/LOD edges.

### Performance, validation, and human acceptance

Emit timing and peak scratch/resident bytes for each hydro stage, plus cold
horizon-fill and sustained traversal throughput. Report p50/p95/max, not only a
single isolated tile. Re-run every floor and soak gate.

Use external data as distribution/proxy evidence, not as an expectation that a
procedural seed reproduce Earth:

- [MERIT Hydro](https://doi.org/10.1029/2019WR024873): direction,
  accumulation, and hydrography structure.
- [GRWL V01.01](https://zenodo.org/records/1297434): Landsat-scale major-river
  masks, centerlines, widths, and simplified segment statistics. It is useful
  width evidence for large rivers, not a distribution for every headwater.
- [HydroLAKES](https://doi.org/10.1038/ncomms13603): lake area, perimeter,
  depth, volume, and spill-linked objects.
- [JRC Global Surface Water](https://doi.org/10.1038/nature20584): water extent,
  not topology truth.

Useful automated proxies include drainage density, stream-order counts,
bifurcation/length ratios, longitudinal monotonicity, and lake area/depth
distributions. They page a human; they do not accept Phase 6. The blocking gate
remains an in-game mountain-to-sea river walk/flyover with filed survey shots.

### Minimal implementation order

1. Canonical drainage-domain key, cache, readiness states, and fixtures.
2. Conditioning, flat resolution, D8 graph, and accumulation with overlays.
3. Stream/lake/wetland classification and model gates.
4. Fine carving into floor/height plus final-query migration.
5. Conservative far hydro and near/far tests.
6. `river-valley` scenario, profiling, surveys, soaks, and human sign-off.

### Measure; do not pre-freeze

- Macro cell size and canonical domain size.
- Lake area/depth thresholds and whether nested depression hierarchy is needed.
- Stream initiation area and target drainage density.
- Width/depth/valley power-law coefficients.
- Whether D8 bias requires D-infinity or only constrained raster smoothing.
- Which compact strength/distance fields have enough readers to persist.

### Defer

Dynamic fluids, rainfall/runoff seasons, floods, groundwater, hydraulic
simulation, endorheic water balance, braided rivers, deltas, meander migration,
and decorative splines independent of flow topology.

## Phase 7 — Erosion, climate, biome, and surface

### Entry checklist

- Freeze the accepted Phase 6 product, fixtures, river-valley scenario, and
  visual artifacts as a before-state.
- Retain pre-round working heights and canonical hydro topology long enough for
  erosion/deposition; do not reconstruct them from quantized blocks.
- Make the generation pipeline able to rebuild an entire final product rather
  than patching completed RegionTiles.
- Select a cited sediment-flux/deposition equation with explicit units,
  boundary transfer, timestep, and mass tolerance before promising alluvial
  output. Do not invent an uncited “capacity” scalar during implementation.
- Name the runtime reader and byte budget before adding any persistent erosion,
  temperature, moisture, biome, or surface field.

### Lock: one causal generation order

Use this order:

```text
base sub-block landform
→ preliminary canonical drainage
→ erosion/deposition on the canonical processing domain
→ final depression, flat, receiver, and accumulation recomputation
→ final channel/lake carve
→ final ground derivatives
→ adjusted climate
→ biome
→ surface class/material
→ one final voxel quantization
→ RegionTile crop
→ FarSummary
```

Every Phase 6 topology, downhill, boundary, and near/far agreement test must
re-pass after erosion. Region-local droplets have the same seam problem as
RegionTile-local hydrology. If droplets are ever justified, a canonical owner
must include a halo at least as large as maximum travel plus brush radius and
must pass exact overlap tests.

### Lock: nonlocal flux has canonical boundary conditions

Sediment moves downstream and atmospheric moisture moves downwind; neither is a
bounded local stencil. Before implementing either, a Phase 7a spike must choose
and test its ownership/exchange contract. Reuse the Phase 6 canonical-domain
ownership where possible. Either solve the complete canonical domain, or pass
deterministic sediment/moisture boundary fluxes through an explicitly ordered
domain graph until the declared convergence condition is met. A finite halo is
valid only for a filter whose maximum influence radius is actually bounded.

Add one erosion fixture whose source and depositional fan lie on opposite
domain subdivisions, and one climate ridge whose upwind moisture source and
leeward cell cross a subdivision. Both must be byte-identical across request
and worker order before the visible filters land.

### Default erosion and deposition model

Start with a small number of deterministic graph/topological passes rather than
simulated droplets:

1. Compute detachment/incision from a bounded stream-power relation
   `E = K A^m S^n`, using contributing area and slope. Cap change per pass and
   apply it to actual ground height. The Fastscape method is the appropriate
   efficient starting point for this detachment-limited term
   ([Braun & Willett](https://doi.org/10.1016/j.geomorph.2012.10.008),
   [Landlab reference](https://landlab.csdms.io/generated/api/landlab.components.stream_power.fastscape_stream_power.html)).
2. Couple that term to a cited sediment-flux balance. The default spike is the
   Davy–Lague ξ-q/linear-decline model: each node receives the sum of donor
   sediment fluxes, local erosion adds volume, deposition removes a term
   proportional to current flux over a discharge-dependent transport length
   `ξ(q)`, and the remainder becomes the receiver's outgoing flux
   ([Davy & Lague](https://doi.org/10.1029/2008JF001146)). Implement it as a
   deterministic topological sweep for a fixed receiver graph, with all terms
   expressed in compatible volume/area/timestep units. Select the stable
   discrete integration and `ξ(q)` calibration in the Phase 7a fixture; do not
   claim Fastscape alone supports deposition.
3. Track the closed budget
   `eroded = deposited + exported + retained_in_transport` within declared
   absolute and relative tolerances, and transfer outgoing boundary flux through
   the canonical domain graph.
4. Produce floodplain/valley flats and depositional fans from the modeled
   deposition field rather than unrelated noise masks. If the default cannot
   make a credible slope-break fan, evaluate the discrete transport-limited
   formulation of
   [Hergarten 2020](https://doi.org/10.5194/esurf-8-841-2020) before inventing a
   custom capacity law.
5. Add a bounded hillslope relaxation pass only if DEM statistics and fixed
   screenshots still show implausible terraces/ridges. A nonlinear flux that
   rises near a critical slope is better grounded than unlimited blur
   ([Roering et al.](https://doi.org/10.1029/1998WR900090)).
6. Protect ocean, lake, and intended channel semantics during filters, then
   recompute routing and perform the final channel/lake carve.

The full SPACE bedrock/alluvium model is a correctness ceiling, not the initial
implementation. Reach for it only if the simpler cited mass-accounted model
cannot produce credible alluvial forms
([SPACE](https://doi.org/10.5194/gmd-10-4577-2017)).

An `erosion` label without a visible, measured height change does not satisfy
Phase 7.

### Default static climate model

This is a deterministic terrain-informed climate field, not a weather system.

1. Begin with very-low-frequency exogenous base temperature/moisture forcing.
   It may vary spatially, but do not lock an infinite procedural world to a
   fake latitude topology during the foundation.
2. Apply altitude temperature adjustment **before biome classification**. Use
   −6.5 K/km as an initial physical anchor, not a universal observed constant
   ([U.S. Standard Atmosphere 1976](https://ntrs.nasa.gov/citations/19770009539)).
3. Seed moisture at the true/coarse ocean and coast. Advect it across the same
   canonical macro domain along one fixed prevailing wind. Windward uplift
   precipitates; inland transport decays; leeward terrain receives a rain
   shadow. Smith–Barstad supplies a useful physical model boundary without
   requiring a weather simulator
   ([Smith & Barstad](https://doi.org/10.1175/1520-0469(2004)061%3C1377:ALTOOP%3E2.0.CO;2)).
4. Add bounded local river/lake/wetland moisture after macro precipitation.
5. Validate the chosen scale and correlations against datasets such as
   [WorldClim 2](https://doi.org/10.1002/joc.5086), which uses elevation and
   distance-to-coast as first-order covariates.

### Biome and surface classification

Keep biome classification as a small explicit decision table over continuous
temperature/moisture plus landform/hydrology. Do not build a registry or turn
each biome into an independent terrain generator.

Default precedence:

1. water, coast, riparian, and wetland semantics;
2. extreme cold/alpine;
3. temperature × moisture class;
4. landform modifiers.

Köppen–Geiger is useful for broad climate-zone coherence, but climate classes
are not themselves biomes; its authors explicitly warn against treating them
as interchangeable
([Beck et al.](https://doi.org/10.1038/sdata.2018.214)).

Surface material is one precedence function, not several competing noise
fields:

```text
water bed / bank / wetland
→ exposed rock or scree from final slope + erosion
→ alluvium from deposition / floodplain context
→ snow from adjusted temperature + moisture
→ dry soil / topsoil / grass defaults
```

Use noise only to dither a transition at a controlled scale. Keep a compact
`SurfaceClass` separate from `Block` so multiple semantics may map to the
current palette without losing meaning.

### Data contract

Possible persistent outputs are compact `Biome`, `SurfaceClass`, hydro/erosion
protection flags, and a quantized deposition or wetness strength if an actual
reader exists. Raw `f32` temperature, moisture, incision, sediment load, and
intermediate height belong in scratch or the cached macro product by default.

Far summaries should reduce dominant biome/surface plus conservative hydro
semantics from the same final RegionTile. Never classify far terrain through a
cheaper independent climate or material function.

### Fixtures and gates

Required deterministic fixtures:

- Two points with equal base climate at different elevations: adjusted
  temperature declines by the configured lapse.
- A simple ridge under fixed wind: windward precipitation/moisture exceeds the
  lee side.
- A stream-power ramp: incision rises with contributing area and slope, while
  final beds remain downstream-monotone.
- A slope break with upstream sediment: a flatter depositional fan forms and
  the sediment budget closes.
- Surface precedence cases: no warm lowland snow, no soil/grass on a steep
  cliff, no non-water top surface over a `has_open_water` cell, a dry wetland
  receives its wetland surface class/material, and water/snow/rock/alluvium
  ordering is correct.

Required product gates:

- Byte-identical canonical erosion/climate products across request and worker
  order; exact overlap identity; finite bounded values; `floor <= height`.
- Erosion visibly changes terrain while improving or not regressing the Phase 5
  DEM relief, slope, curvature, plains, alpine, hill, mesa, and escarpment
  envelopes unless human sign-off explicitly changes an envelope.
- Climate is continuous across product boundaries and shows configured
  temperature/elevation, coast/moisture, and windward/leeward relationships at
  a broad spatial scale.
- Biome assignment is a pure function of final climate, landform, and hydro.
  Water precedence is absolute. Far dominant semantics agree with near truth.
- A connected-component/local-entropy detector flags material speckle while
  exempting deliberately narrow river/riparian classes.
- A contour-band detector flags long material boundaries explained only by an
  integer altitude threshold.

Automated proxies are tripwires. Acceptance still requires fixed before/after
flyovers and the blocking human verdict that the world is clearly better than
vanilla 1.18+ both near and at the horizon.

### Minimal implementation order

1. Preserve Phase 6 baseline artifacts and expose canonical working heights.
2. Add bounded stream-power incision and mass-accounted deposition.
3. Recompute drainage and re-pass all Phase 6 gates.
4. Add hillslope transport only if the measured/visual need remains.
5. Add macro temperature and moisture.
6. Add the small biome table and one surface classifier.
7. Add compact final fields, far reductions, version bump, overlays, surveys,
   soaks, and human sign-off.

### Measure; do not pre-freeze

- Domain/cell scale, preferably reusing the accepted Phase 6 product.
- Pass count/timestep, `K/m/n`, maximum height change, ξ/deposition parameters,
  and mass tolerances.
- Whether hillslope transport is visibly necessary.
- One fixed prevailing wind versus two broad regimes.
- Climate wavelengths, lapse calibration, and decision-table thresholds.
- Which semantic values deserve persistent bytes.

### Defer

Dynamic weather, seasons, day cycle, vegetation/trees/features, groundwater and
soil physics, a general circulation model, exact geologic-age simulation, the
full SPACE model, and droplet erosion unless the simpler measured default fails
the visual gate.

## Phase 8 — Measured optimization

### Entry checklist and acceptance rule

Before changing an algorithm, establish a reproducible ReleaseFast baseline on
the Apple M3 Max with:

- the exact seed, view configuration, scenario trace, warmup, and build commit;
- median of three complete runs;
- CPU frame p50/p95/p99/worst and stage timings;
- delayed/nonblocking GPU timer-query results;
- all queue depths/ages, production/demand, fill, upload, and draw metrics;
- bytes for every named CPU/GPU pool plus process RSS;
- fixed screenshots or hashes demonstrating identical accepted visual truth.

Then fix only the top demonstrated end-to-end bottleneck and re-run the same
workload. No end-to-end in-game win means revert, even if a microbenchmark wins.
Memory/cache/streaming changes also re-run the complete soak suite. This follows
Apple's measure → find bottleneck → change → measure guidance
([OpenGL performance guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_performance/opengl_performance.html)).

### Lock: measurement truth first

Add one reconciled memory report that includes at least:

- chunk logical metadata, uniform values, and allocated dense payloads;
- near/far CPU mesh capacities and live bytes;
- RegionTile and each summary-LOD cache;
- generation/mesh/upload queues and scratch high-water marks;
- edit and macro-product caches when present;
- exact API-requested GL buffer/texture storage bytes and live ranges. OpenGL
  4.1 does not expose driver padding or physical GPU residency, so label those
  unknown rather than calling the requested total VRAM;
- process RSS as an outside CPU/process check, not a value to add to the GL
  storage total.

Report capacity, live bytes, peak, and configured limit separately. Assertions
must prove configured residency limits are enforced. Correct upload accounting
must use 68-byte current GL vertices and include far uploads.

Use OpenGL timer queries asynchronously: issue around meaningful GPU passes,
poll availability in a later frame, and never stall acceptance frames waiting
for the result
([Khronos query objects](https://wikis.khronos.org/opengl/Query_Object)).

### Default optimization ladder

Re-profile after every accepted rung; stop or reorder if the leader changes.

1. **Re-audit bounded residency and complete truthful accounting.** Phase 5
   must already have repaired the region limit and basic tile/summary bytes;
   Phase 8 verifies that contract under its workload and adds RSS, exact
   API-requested GL storage, queues, scratch, capacities, and live ranges.
2. **Uniform plus heap-dense chunks.** Replace the inline 32 KiB payload with a
   uniform/air tag and allocate dense storage only on promotion. An inline
   tagged union still has the maximum member's size, so it does not solve the
   problem. A byte-index palette saves nothing unless indices are bit-packed;
   defer that complexity until distributions justify it. `VoxelBuffer` is a
   useful uniform/compressed precedent
   ([documentation](https://voxel-tools.readthedocs.io/en/latest/api/VoxelBuffer/)).
3. **Tiered FarSummary residency.** Retain only LOD data required at each ring
   and add a true summary-only generation path from the same canonical product.
4. **Compact the GPU vertex.** The repeated per-vertex chunk coordinate is the
   largest obvious bandwidth cost.
5. **Re-profile.** Only now decide whether mesh production, CPU submission,
   overdraw, or generation is the leader.
6. **Greedy meshing** only when vertex/mesh construction is the measured leader.
7. **OpenGL-4.1-compatible multi-draw** only when CPU submission is the leader.
8. **Broad/occlusion culling, generation upsampling, bounds, or caching** only
   with measurements proving their need and whole-game benefit.

### Candidate compact vertex

One concrete 28-byte OpenGL 4.1 encoding to benchmark—not yet a proven
conservative format—is:

| Field | Representation | Bytes |
|---|---|---:|
| local position | `[3]u16` | 6 |
| UV | `[2]u16` | 4 |
| normal | normalized `[3]i8` | 3 |
| AO / skylight | packed `u8` | 1 |
| texture layer | `u8` | 1 |
| flags | `u8` | 1 |
| mesh origin in whole blocks | `[3]i32` | 12 |
| **Total** | | **28** |

The benchmark encoding contract is:

- Feed position and UV through `glVertexAttribIPointer` as unnormalized
  integers. Decode position at 1/16 renderer-world-unit increments relative to
  the signed mesh origin:
  `world = origin_blocks * 2 + local_u16 / 16`. Each local axis spans
  0–4095.9375 renderer units with at most 1/32-unit reconstruction error
  (0.015625 m under the locked conversion).
- Choose the signed origin per mesh so every local position, including a far
  skirt below zero, is nonnegative and representable; never silently clamp.
- Decode UV at 1/16-block increments, spanning 0–4095.9375 repeating blocks
  with at most 1/32-block error. Keep texture layer in its own integer field.
- Feed normals with `glVertexAttribPointer(BYTE, normalized = true)`; feed
  AO/skylight, layer, flags, and origin with integer attributes. Pack AO level
  0–3 in two bits and direct skylight 0–15 in four bits, leaving two reserved;
  in GLSL use the existing four-value AO lookup and
  `float(sky_level) / 15.0`. Phase 8 supplies sky level 15 until Phase 10's
  direct bake exists. Do not treat an integer attribute's 0–255 value as an
  already normalized float.
- Subtract a uniform camera origin from the signed block origin in integer
  space before converting to float, and prove the `i64` world-coordinate to
  `i32` relative range.

Derive face brightness, base color, and water alpha from normal/layer/flags.
Before accepting 28 bytes, assert field offsets and `@sizeOf == 28`, range-check
every produced near/far vertex (including far skirts and the current 0.9-world-
unit depth bias), bound reconstructed position/UV error, and re-run seam,
texture-phase, and fixed-image comparisons. If any range or error gate fails,
use a wider/floating field and recalculate the projection rather than clamping.

Keep `u32` indices until every possible mesh is proven below 65,535 vertices;
make `u16` conditional rather than an implicit overflow risk.

At current arena element capacities, 28-byte vertices plus `u32` indices would
reduce fixed capacity from about 797.3 MiB to about 377.7 MiB before allocator
overhead. This is a projection to benchmark, not an accepted result. Follow the
Khronos integer/normalized attribute rules
([vertex specification](https://wikis.khronos.org/opengl/Vertex_Specification_Best_Practices)).

### OpenGL 4.1 boundary

macOS exposes an OpenGL 4.1 core ceiling and OpenGL is deprecated but still the
project's chosen foundation API
([Apple profile](https://developer.apple.com/documentation/appkit/nsopenglprofileversion4_1core?language=objc),
[Apple lifecycle note](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_intro/opengl_intro.html),
[4.1 specification](https://registry.khronos.org/OpenGL/specs/gl/glspec41.core.pdf)).

Do not design around later-core features:

- base instance (4.2);
- multi-draw indirect and SSBOs (4.3);
- separate vertex binding (4.3);
- persistent buffer storage (4.4);
- clip control/reversed-Z helper (4.5);
- `gl_DrawID` (4.6).

OpenGL 4.1 does support normalized/integer attributes, timer queries,
tessellation, and `glMultiDrawElementsBaseVertex`; the last is the proven
batching candidate
([Khronos API](https://wikis.khronos.org/opengl/GLAPI/glMultiDrawElementsBaseVertex)).

### Acceptance matrix

Each optimization report must state:

- the hypothesized bottleneck and evidence;
- before/after exact workload, median-of-three and variance;
- frame, production, queue, upload, draw, CPU-memory, RSS, and GPU-memory impact;
- cold-start, post-motion settle, steady traversal, and soak effect where
  relevant;
- visual/product equivalence evidence;
- keep/revert decision.

The Phase 8 exit comparison uses the fresh, workload-matched
[`v1-baseline.md`](v1-baseline.md). A headline FPS number from a different view,
quality configuration, warmup, or terrain product is not a valid win.

### Defer by default

RLE, palette ladders, chunk-size changes, occlusion hierarchies, speculative
noise upsampling/caching, extremity skipping, and a renderer/API migration.
Coherent hierarchical culling is a later option only if measured occlusion is
the leader ([CHC](https://doi.org/10.1111/j.1467-8659.2004.00793.x)).

## Phase 9 — View-distance push

### Blocking decision: lock the distance contract before implementation

The current `visibleSpanKm()` reports square edge-to-edge diameter, while the
roadmap does not say whether “visible terrain distance” is a radius or span.
Ratify that semantic in the roadmap/gates before implementation. This research
recommends the more conservative camera-to-guaranteed-edge radius and emitting
configuration and achieved coverage separately:

- `configured_visible_radius_km` and `configured_visible_span_km`: what the
  current policy requests;
- `covered_visible_radius_km`: minimum camera-to-edge distance of contiguous,
  no-hole, **draw-eligible** resident geometry after near/far fallback and the
  camera far clip, measured before intentional view-frustum culling. This is a
  360° turn-ready guarantee; terrain outside the current view is not treated as
  absent merely because it was culled. It is the recommended Phase 9 gate, not
  the ring flag.

With 256 m regions, current square-ring geometry is approximately. The
“midpoint radius” assumes the camera is centered in its streaming-center region;
the guaranteed radius allows the camera to be anywhere in that region:

| Region radius | Nominal active | Boundary active max | Cache envelope (r+1) | Guaranteed radius | Midpoint radius | Span |
|---:|---:|---:|---:|---:|---:|---:|
| 16 | 1,089 | 1,156 | 1,225 | 4.096 km | 4.224 km | 8.448 km |
| 20 | 1,681 | 1,764 | 1,849 | 5.120 km | 5.248 km | 10.496 km |
| 39 | 6,241 | 6,400 | 6,561 | 9.984 km | 10.112 km | 20.224 km |
| 40 | 6,561 | 6,724 | 6,889 | 10.240 km | 10.368 km | 20.736 km |

Therefore radius 20 satisfies only a 10 km **span**, and radius 39 misses a
conservative 10 km guarantee by 16 m. Under the recommended radius contract,
radius 40 is the first whole-region value that passes. Its nominal active set is
roughly six times radius 16 and would consume about 546.62 MiB in current
monolithic summaries. Exact region-boundary demand can reach 6,724 summaries
(about 560.20 MiB), while the currently configured radius+1 retention envelope
is 6,889 (about 573.94 MiB). Phase 9 must ratify the metric and budget the
retained high-water mark—not only nominal active demand—before turning the
radius knob.

### Entry checklist

- Phase 8 has accepted truthful per-pool/RSS/GPU accounting, bounded caches,
  compact storage/vertices where measured useful, and a declared memory budget.
- Hydrology/erosion/climate have a summary-only path derived from the same
  canonical macro truth; far requests do not build and retain a full 3.711 MiB
  RegionTile merely to reduce it.
- Distance metrics, world-units-to-meters conversion, and the exact guaranteed
  shape (square/circle/conservative edge) are explicit.
- Cold startup and post-motion settling are separate scenarios and budgets.
- Far holes, uncovered cells, committed center, and all relevant queues are
  observable.

### Default horizon architecture

Keep the accepted near/far readiness and fallback machinery. Extend it with:

1. LOD-specific/tiered summary residency rather than all far4/far16/far64 data
   for every coordinate.
2. A summary-only generation job that runs the same final terrain/hydro/climate/
   material kernels and reduces their outputs as they stream, or consumes a
   canonical final product containing those exact semantics, without retaining
   a full RegionTile. “Summary-only” is a storage/lifetime optimization, never
   permission for an alternate coarse generator. Contract-test it against a
   full RegionTile reduction: exact fields match where required, bounds contain
   every near value, and narrow hydro remains conservative.
3. Ring demand chosen from projected screen-space error, not distance alone.
   Each LOD product must carry a conservative geometric error in meters,
   computed as the maximum deviation of final near truth from that LOD's
   reconstructed surface. Project it with nearest tile distance, viewport
   height, and vertical field of view (equivalently,
   `error_m * viewport_px / (2 * tan(fov_y/2) * distance_m)`). Calibrate a pixel
   threshold with fixed screenshots. Use the OGC projected geometric-error
   model as the vocabulary
   ([OGC 3D Tiles SSE](https://docs.ogc.org/cs/22-025r4/22-025r4.html)).
4. Stable nested grids/readiness retention inspired by geometry clipmaps, while
   preserving voxel/far product ownership
   ([Losasso & Hoppe](https://hhoppe.com/geomclipmap.pdf)).
5. One preflight projection at radius 40 if the recommended radius contract is
   ratified, covering positions, cache bytes, CPU/GPU vertices/indices, cold
   jobs, upload traffic, and expected settle throughput.

Keep LOD16 as the outer starting point. Do not revive visibly giant LOD64 cells
only because their data exists. A new outer representation must pass fixed
visual comparisons and conservative hydro continuity first.

### Coverage readiness and quality convergence

The current near-fill ≥95% predicate is not Phase 9 convergence, and current
`far_ready` accepts a policy LOD **or a coarser fallback**. Separate two states.

**Coverage-ready** for a desired center/version means:

- committed streaming center equals desired center;
- guaranteed near coverage is 100%;
- guaranteed far coverage is 100%, allowing a valid conservative fallback;
- uncovered/hole count is zero;
- no pending readiness swap can expose a gap.

**Quality-settled** additionally means every coordinate has its current
policy/SSE-selected LOD resident—not merely `residentAtOrCoarser`—and all
generation, far-build, mesh, upload, and replacement jobs relevant to that
center/version are drained. The roadmap's <2 s stop-and-settle gate applies to
this stricter quality state.

Measure:

- `cold_coverage_ready_ms` and `cold_quality_settled_ms`;
- `post_motion_coverage_ready_ms` and
  `post_motion_quality_convergence_ms`;
- `convergence_timeout`: numeric failure, never `na`.

Cold startup gets separate declared targets. “Zero holes” means no far
uncovered geometry after warmup; a 250 ms hole tolerance is not equivalent.

### Depth, precision, and atmosphere

The current near plane is 0.1 world units. With a 10 km far range, depth
precision is concentrated unnecessarily near the camera. First test a 0.5–1.0
world-unit near plane if interaction/camera clipping permits; increasing the
near plane is the most direct OpenGL 4.1 precision improvement
([Khronos depth precision](https://wikis.khronos.org/opengl/Depth_Buffer_Precision)).
Do not assume reversed-Z via `glClipControl`, which is beyond the macOS 4.1
core boundary.

The project already defines one block as 1 m and `block_world_size = 2.0`.
Therefore lock the conversion as **0.5 m per renderer world unit** (two renderer
units per meter) and use it for camera clips, fog, atmospheric density, and
reported kilometers. The distance table above is in physical 1 m blocks. The
current 0.1-world-unit near plane is 0.05 m; the proposed 0.5–1.0 test range is
0.25–0.5 m.

Atmosphere is polish over real geometry. The minimum is exponential
transmittance/aerial perspective in physical meters, with color operations and
blending performed in the intended linear/sRGB spaces
([Khronos framebuffer color space](https://wikis.khronos.org/opengl/Framebuffer)).
Preetham's daylight model is a suitable lightweight reference
([Preetham et al.](https://doi.org/10.1145/311535.311545)); Bruneton-style
precomputed scattering is a stretch only after measured need
([Bruneton & Neyret](https://doi.org/10.1111/j.1467-8659.2008.01245.x)). Fog
must never conceal missing terrain or make a hole gate pass.

### Required Phase 9 gates

The first gate below assumes the recommended radius contract is ratified; if
the normative roadmap chooses another meaning, replace it explicitly rather
than leaving `visible_terrain_km` ambiguous.

- `covered_visible_radius_km >= 10.0` from contiguous, clipped, draw-eligible
  geometry before frustum culling under the declared conservative measurement;
  configured radius alone cannot pass.
- Fast flight holds the universal floor, including worst frame <16.6 ms,
  `hole_frames == 0`, `boundary_holes == 0`, and `sync_fallbacks == 0`.
- Post-motion **quality** convergence <2 s; coverage-ready and both cold metrics
  are numeric and within their separately declared budgets.
- Every CPU/GPU pool and process RSS remains under the Phase 8-derived budget,
  reaches a plateau, and respects configured bounds during the full soak.
- Queue ages remain bounded and production keeps up with demand at the true
  radius target.
- Near/far height, material, biome, and hydro reductions agree; narrow major
  rivers do not disappear at the outer horizon.
- Atmosphere-off debug mode proves real geometry covers the accepted horizon.

### Defer

An OpenGL/Metal renderer rewrite, LOD64 resurrection without visual evidence,
planetary curvature, full volumetric clouds, and physically complete
multi-scattering atmosphere.

## Phase 10 — Hard demo and first gameplay surface

### Entry checklist

- Phase 9's coverage-ready and policy-quality-settled predicates, ratified
  distance target, and memory bounds are green.
- Final solid/fluid queries are distinct and route through RegionTile plus any
  edit overlay.
- Replay format can carry deterministic edit events.
- A fixed mountain → river valley → coast route reuses the Phase 6 scenario and
  has accepted terrain/hydro artifacts.

### Lock: logical chunk content is not mesh visibility

`collectMeshResults` currently treats every zero-index mesh as `.air`. A fully
solid chunk surrounded by solids can legitimately have zero exposed faces;
marking it air corrupts `blockAt`, collision, and later edits. Before editing:

- store logical content state separately from renderability/mesh emptiness;
- never infer “all air” from zero opaque/translucent indices;
- keep collision and queries based on logical base+delta truth.

### Deterministic break/place targeting

Use a 3D voxel DDA from the gameplay camera in block coordinates, following
the fast grid-traversal structure of
[Amanatides & Woo](https://www.cse.yorku.ca/~amana/research/grid.pdf). The
interaction contract must state:

- configurable reach in physical blocks/meters (start by measuring a 5-block
  default), with no hit at or beyond the declared endpoint rule;
- floor-based cell selection for negative coordinates and origins exactly on a
  voxel boundary;
- one fixed axis tie order for edge/corner crossings, covered by tests;
- the first selectable occupancy stops the ray. A solid block is the break
  target; open water yields no edit and is neither breakable nor ray-transparent
  in the foundation, avoiding accidental dynamic-fluid scope;
- for a selected solid, the last traversed replaceable cell and crossed face
  define placement; open water is not replaceable;
- placement is rejected if the destination is not replaceable or its block
  AABB intersects the player AABB.

Validate and record the **resolved edit command**—tick/order, action, selected
world cell, placement face/destination, and block value—rather than asking
replay to repeat a floating-point raycast. Add fixtures for all six directions,
negative coordinates, exact face/edge/corner starts, maximum reach, water in
front of terrain, and player-overlap rejection.

### Default edit model

Full disk persistence remains beyond the foundation, but session edits must
survive eviction/revisit. Use a sparse deterministic delta store keyed by world
block coordinate or chunk coordinate plus local index:

```text
immutable generated base block
        + latest session delta
        = logical block truth
```

Every consumer must apply the overlay:

- `blockAt`, density/solid/fluid queries, collision, and selection;
- chunk materialization and storage promotion;
- neighbor snapshots for mesh/AO;
- edit-aware FarSummary reductions and far-mesh invalidation at every LOD, so
  leaving the near ring cannot make a session edit disappear;
- forced eviction and later revisit;
- replay/state hashes.

An edit immediately updates logical/collision truth and promotes the accepted
Phase 8 uniform representation to heap-dense storage. Use a palette only if
Phase 8 actually measured and accepted one. Increment a desired chunk/region
edit revision, set a dirty bit, invalidate affected summary cells/far meshes,
and request the required work.

Every asynchronous edit-aware consumer—chunk materialization, edit-aware
FarSummary reduction, near mesh, and far mesh—captures base product version,
the relevant edit revision, and all sampled-neighbor revisions. A stale
completion leaves dirty set and immediately queues the latest desired revision;
only a result matching every captured dependency may publish or clear
dirty/readiness. This prevents queue deduplication around an in-flight old job
from losing the edit and prevents an old materialization/summary from
reinstalling base truth. Keep previous valid near and far GPU meshes until their
replacement uploads so editing never creates a transient hole.

For the existing one-block-neighborhood corner AO, invalidate the unique chunks
touched by the edited block's `x±1`, `y±1`, and `z±1` footprint. At a chunk
corner this is at most eight chunks—the owner plus seven neighbors—not a blind
27-chunk cube. A future lighting model with a larger influence radius must state
its own invalidation contract.

### Replay and deterministic edit gates

The current session recorder captures tick input but no edit action. Introduce
a trace version with deterministic events containing at least tick/order,
action, world coordinate, and block/material. Replay must reproduce:

- the exact ordered edit stream;
- final logical delta hash;
- endpoint/player state hash;
- chunk revisions and stale-result discard behavior independent of worker
  completion order.

Serialize deltas in canonical lexicographic world-coordinate order before
hashing, including material/value and product version. Hash-map iteration order
must never define the replay or final-state hash.

Include boundary and corner edits, rapid edit/re-edit, forced eviction/revisit,
and edits while each asynchronous materialization, summary reduction, near
mesh, and far mesh is in flight, plus edits in a fully occluded solid chunk.

### Minimum correct water pass

Water vertices already carry alpha, but blending is not enabled and depth writes
remain enabled. Far water also travels in opaque geometry. The minimum real
renderer is:

1. Draw all opaque near and far geometry normally.
2. Draw water/translucent geometry with depth testing on and depth writes off.
3. Set blend equation `FUNC_ADD`, premultiply the shader output exactly as
   `out.rgb *= out.a`, and use source `ONE`, destination
   `ONE_MINUS_SRC_ALPHA`.
4. Sort water chunks back-to-front; keep opaque geometry unsorted.
5. Restore blend/depth state explicitly after the pass.
6. Give far summaries/meshes a distinct water-presence and water-surface path so
   distant water is not emitted as opaque terrain.

Add a render/readback fixture for alpha zero, one translucent surface over an
opaque background, and two overlapping translucent surfaces. It must also prove
that blend equation/functions and the depth-write mask are restored after the
pass.

This follows the standard depth/sorting constraint for transparency
([Khronos transparency sorting](https://wikis.khronos.org/opengl/Transparency_Sorting),
[blend state](https://wikis.khronos.org/opengl/Draw_Buffer_Blend),
[depth write mask](https://wikis.khronos.org/opengl/Write_Mask)).

For the accepted visual floor, add a Schlick Fresnel term and small procedural
normal perturbation
([Schlick](https://doi.org/10.1111/1467-8659.1330233)). Defer framebuffer
refraction and weighted OIT unless sorted alpha fails a specific scene; weighted
blended OIT is the stretch reference
([McGuire & Bavoil](https://jcgt.org/published/0002/02/09/paper.pdf)).

### Minimum remaining lighting

Corner AO already exists, but the normative Phase 10 roadmap still requires a
sky-light bake. Implement the smallest honest version: direct vertical column
skylight, baked into mesh vertices (for example 15 when open to sky and 0 when
occluded), with no lateral flood. In the foundation's heightfield world, derive
the highest opaque block per `(x,z)` from final base+delta truth instead of
allocating a speculative full light volume.

An edit that changes a column roof has vertical influence beyond the eight AO
chunks. Recompute that column and revision-invalidate every vertical chunk
whose direct-sky values changed; the same desired-revision/stale-result rules
apply. Test placing/removing a roof across a vertical chunk boundary, including
an edit while affected meshes are in flight. Direct sunlight/skylight values in
Luanti are a useful minimal precedent
([lighting model](https://docs.luanti.org/for-players/light/)).

Do not expand this into lateral flood lighting, colored lights, torch
propagation, caves, or a day/night system. Those need a separate
ownership/invalidation design and are beyond the foundation.

### Hard-demo artifact contract

Archive enough information to replay and judge the exact demo later:

- generator/product versions, literal seed, git commit, build mode, host;
- view/LOD and memory configuration;
- input trace version plus edit-event stream;
- scripted route from mountain through river valley to coast;
- before/after edit state hashes and final endpoint hash;
- complete CPU/GPU frame metrics, queue/fill/convergence metrics, per-pool
  memory and RSS, uploads, draw/vertex counts, and stale-job counters;
- screenshots/contact sheet and full recording;
- explicit human play/visual verdict.

Required gameplay cases:

- break/place in natural terrain, at chunk faces/edges/corners, and beside water;
- collision changes immediately with edits;
- old mesh remains until revision-correct replacement uploads;
- rapid edits cannot resurrect stale geometry;
- walking/flying until an edited site crosses near/far LOD boundaries preserves
  edit-aware bounds/materials and does not flash back to generated base truth;
- forced eviction/revisit restores session deltas;
- aligned two-cycle windowed explore + revisit + edit soak holds all floor, drift,
  memory-plateau, coverage-ready, and quality-convergence gates;
- mountains → river → coast route has no holes, sync fallbacks, placeholders, or
  metric `na` values.

V1/V3 comparison claims require the same route/workload and V3's default
accepted visual configuration. A stripped-quality comparison is not an exit
gate.

### Minimal implementation order

1. Separate logical content from mesh renderability and add regression tests.
2. Sparse session delta store plus all-query/near/far overlay and storage
   promotion.
3. Revision every edit-aware materialization/summary/near/far job; add dirty
   requeue, stale-result discard, and old-mesh retention.
4. Trace v2/edit events and deterministic state hashes.
5. Correct near/far water pass; minimal Fresnel/normal visual treatment.
6. Bake direct column skylight with revisioned vertical invalidation.
7. Script, run, archive, and obtain human sign-off on the hard demo/soak.

### Defer

Disk persistence, multiplayer replication, dynamic fluids, refraction, weighted
OIT unless sorted alpha fails, caves/overhangs, lateral/colored/torch lighting,
time of day, weather, vegetation, structures, and world history.

## Cross-phase gate matrix

This table is the handoff checklist to consult at each phase start.

| Contract | P6 | P7 | P8 | P9 | P10 |
|---|:---:|:---:|:---:|:---:|:---:|
| Playable game remains the harness; all floor gates | ✓ | ✓ | ✓ | ✓ | ✓ |
| Same seed/version bytes across schedule/thread order | ✓ | ✓ | regression | regression | base+delta hash |
| Region overlap and one near/far truth | hydro | all final fields | unchanged | all horizon rings | edits included |
| Cache bounds, named memory pools, plateau | prerequisite | ✓ | blocking truth | declared budget | edit soak |
| No frame-thread generation / bounded queue age | ✓ | ✓ | ✓ | ✓ | remesh too |
| Cold/post-motion and coverage/quality states separate | instrument | instrument | baseline | strict gates | strict gates |
| Fixed scenario and archived artifacts | river-valley | before/after | before/after optimization | ratified-distance flight | hard demo |
| Automated proxies page human; do not accept visuals | ✓ | ✓ | equivalence | atmosphere debug | recording |
| Human blocking sign-off | river walk | > vanilla near+horizon | only if visual contract changes | horizon polish | live demo |

## Phase-start decision register

Do not reopen the **Lock** column without contrary evidence. Resolve the
**Measure at start** column with the named fixture/benchmark, then record the
chosen value in that phase's report.

| Phase | Lock | Measure at start | Default fallback |
|---|---|---|---|
| 6 | Canonical cross-region graph; floor/water separation; conservative far truth | Macro scale, lake/stream thresholds, carve laws, compact persisted fields | Priority-Flood + deterministic D8 + Kahn accumulation + Strahler |
| 7 | Causal regenerate/reroute order; compact fields; no local droplets; canonical nonlocal flux | Incision/deposition discretization and coefficients, passes, climate scale/wind, biome thresholds | Bounded stream-power + Davy–Lague flux balance + static orographic climate |
| 8 | Whole-game before/after; no win means revert; GL 4.1 boundary | Current top bottleneck and accepted byte/latency budgets | Accounting → uniform storage → tiered summaries → compact vertex |
| 9 | Explicit distance semantics; coverage-ready + policy-quality-settled; fog over real geometry | Ratify radius vs span, then project r40 if radius; ring errors, near plane, memory and cold/warm budgets | Conservative actual coverage + LOD16 outer ring + equivalent tiered summary-only generation |
| 10 | Base+delta logical truth; revisioned jobs; real transparent pass; direct skylight bake | Edit latency budget, skylight encoding/visual level, water visual constants | Sparse session deltas + sorted premultiplied alpha water + column skylight |

## Pinned implementation precedents

These are implementation evidence, not specifications. URLs are pinned to
commits so later research does not silently change under the project.

### TerraForged (`6dd607ebfd41a3b7274e090b1f2cf565d53d1d44`)

- [Globally addressable cached river graph and lower-neighbor merges](https://github.com/TerraForged/TerraForged/blob/6dd607ebfd41a3b7274e090b1f2cf565d53d1d44/src/main/java/com/terraforged/mod/worldgen/noise/continent/river/RiverGenerator.java#L73-L215)
- [Ocean extension](https://github.com/TerraForged/TerraForged/blob/6dd607ebfd41a3b7274e090b1f2cf565d53d1d44/src/main/java/com/terraforged/mod/worldgen/noise/continent/river/RiverGenerator.java#L251-L256)
- [Noise-derived radius to avoid copying as physical accumulation](https://github.com/TerraForged/TerraForged/blob/6dd607ebfd41a3b7274e090b1f2cf565d53d1d44/src/main/java/com/terraforged/mod/worldgen/noise/continent/river/RiverGenerator.java#L295-L310)
- [Topology/carving separation](https://github.com/TerraForged/TerraForged/blob/6dd607ebfd41a3b7274e090b1f2cf565d53d1d44/src/main/java/com/terraforged/mod/worldgen/noise/continent/river/RiverCarver.java#L62-L117)
- [Asynchronous keyed terrain cache](https://github.com/TerraForged/TerraForged/blob/6dd607ebfd41a3b7274e090b1f2cf565d53d1d44/src/main/java/com/terraforged/mod/worldgen/terrain/TerrainCache.java#L91-L123)

The useful pattern is canonical topology plus a separate local carve and cache.
Its noise-derived river width/radius is not a substitute for contributing-area
accumulation.

### ReTerraForged (`98fd3a28f2ebd638319e797a9138a3418484150f`)

- [Semantic cell fields](https://github.com/racoonman2/ReTerraForged/blob/98fd3a28f2ebd638319e797a9138a3418484150f/common/src/main/java/raccoonman/reterraforged/world/worldgen/cell/Cell.java#L23-L57)
- [Staged bordered tile generation](https://github.com/racoonman2/ReTerraForged/blob/98fd3a28f2ebd638319e797a9138a3418484150f/common/src/main/java/raccoonman/reterraforged/world/worldgen/tile/TileGenerator.java#L45-L84)
- [River valley/bank/bed writes](https://github.com/racoonman2/ReTerraForged/blob/98fd3a28f2ebd638319e797a9138a3418484150f/common/src/main/java/raccoonman/reterraforged/world/worldgen/terrain/populator/RiverPopulator.java#L55-L89)
- [Deterministically seeded erosion tile work](https://github.com/racoonman2/ReTerraForged/blob/98fd3a28f2ebd638319e797a9138a3418484150f/common/src/main/java/raccoonman/reterraforged/world/worldgen/tile/filter/Erosion.java#L45-L75)
- [Erosion masks/protection](https://github.com/racoonman2/ReTerraForged/blob/98fd3a28f2ebd638319e797a9138a3418484150f/common/src/main/java/raccoonman/reterraforged/world/worldgen/tile/filter/Erosion.java#L177-L193)
- [Biome-before-altitude-adjustment order to avoid](https://github.com/racoonman2/ReTerraForged/blob/98fd3a28f2ebd638319e797a9138a3418484150f/common/src/main/java/raccoonman/reterraforged/world/worldgen/climate/BiomeNoise.java#L126-L143)

Reuse the semantic/staged shape. Treat its cached droplet erosion as a fallback,
not the V3 default, and correct the climate-to-biome ordering.

### Realistic Terrain Generation (`3ec659e69617c74b5c6304534ef1f4c81fadfb55`)

- [Propagated landscape fields](https://github.com/Team-RTG/Realistic-Terrain-Generation/blob/3ec659e69617c74b5c6304534ef1f4c81fadfb55/src/main/java/rtg/world/gen/ChunkLandscape.java#L9-L14)
- [River semantics in terrain generation](https://github.com/Team-RTG/Realistic-Terrain-Generation/blob/3ec659e69617c74b5c6304534ef1f4c81fadfb55/src/main/java/rtg/world/gen/ChunkGeneratorRTG.java#L572-L587)
- [River-aware biome replacement](https://github.com/Team-RTG/Realistic-Terrain-Generation/blob/3ec659e69617c74b5c6304534ef1f4c81fadfb55/src/main/java/rtg/world/biome/BiomeAnalyzer.java#L102-L134)
- [Scalar river flattening to avoid as a topology substitute](https://github.com/Team-RTG/Realistic-Terrain-Generation/blob/3ec659e69617c74b5c6304534ef1f4c81fadfb55/src/main/java/rtg/api/world/terrain/TerrainBase.java#L132-L145)

RTG demonstrates propagating semantic context into terrain/biome decisions, but
its scalar flattening is an anti-reference for the Phase 6 graph requirement.

## Primary source register

Core sources cited inline are collected here by the decision they support.
Prefer these primary papers/specifications and pinned code over videos or
unversioned blog summaries when implementing; phase sections contain the
additional specialized dataset and fallback citations.

### Hydrology and drainage

- Priority-Flood depression filling: [Barnes, Lehman & Mulla 2014](https://doi.org/10.1016/j.cageo.2013.04.024)
- Parallel tiled Priority-Flood: [Barnes 2016](https://doi.org/10.1016/j.cageo.2016.07.001)
- Distributed D8 upslope area: [Barnes 2016](https://arxiv.org/abs/1605.05773)
- Parallel non-divergent flow accumulation: [Barnes 2016](https://arxiv.org/abs/1608.04431)
- Flat resolution: [Barnes, Lehman & Mulla 2014](https://doi.org/10.1016/j.cageo.2013.01.009)
- D8: [O'Callaghan & Mark 1984](https://doi.org/10.1016/S0734-189X(84)80011-0)
- D-infinity comparison: [Tarboton 1997](https://doi.org/10.1029/96WR03137)
- Fill/breach hybrid alternative: [Lindsay 2016](https://jblindsay.github.io/ghrg/pubs/2016_Lindsay_HP.pdf)
- Stream order: [Strahler 1957](https://doi.org/10.1029/TR038i006p00913)
- Hydraulic geometry: [Leopold & Maddock 1953](https://doi.org/10.3133/pp252)
- Hydrography/topology validation: [HydroSHEDS technical documentation](https://data.hydrosheds.org/file/technical-documentation/HydroSHEDS_TechDoc_v1_4.pdf)

### Erosion, climate, and biome

- Detachment-limited/stream-power landscape evolution: [Howard 1994](https://doi.org/10.1029/94WR00757)
- Fastscape implicit stream-power solver: [Braun & Willett 2013](https://doi.org/10.1016/j.geomorph.2012.10.008)
- Erosion/deposition flux balance: [Davy & Lague 2009](https://doi.org/10.1029/2008JF001146)
- Discrete transport-limited alternative: [Hergarten 2020](https://doi.org/10.5194/esurf-8-841-2020)
- Large-scale uplift/fluvial terrain synthesis: [Cordonnier et al. 2016](https://www.cs.purdue.edu/cgvlab/www/publications/cordonnier2016large/)
- Terrain-informed climate surfaces: [CHELSA](https://doi.org/10.1038/sdata.2017.122) and [WorldClim 2](https://doi.org/10.1002/joc.5086)
- Orographic precipitation: [Smith & Barstad 2004](https://doi.org/10.1175/1520-0469(2004)061%3C1377:ALTOOP%3E2.0.CO;2)
- Temperature lapse anchor: [U.S. Standard Atmosphere 1976](https://ntrs.nasa.gov/citations/19770009539)
- Köppen–Geiger validation/reference limits: [Beck et al. 2018](https://doi.org/10.1038/sdata.2018.214)
- Simple climate/life-zone variables: [Holdridge life zones](https://resources.unep-wcmc.org/products/31d5e80482834f6ba6ee51a2813b82e7)

### Performance, rendering, and view distance

- Apple OpenGL measurement workflow: [Performance guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_performance/opengl_performance.html)
- Project language version: [Zig 0.15.2 reference](https://ziglang.org/documentation/0.15.2/)
- OpenGL 4.1 core boundary: [Khronos specification](https://registry.khronos.org/OpenGL/specs/gl/glspec41.core.pdf)
- Timer queries: [Khronos query objects](https://wikis.khronos.org/opengl/Query_Object)
- Vertex formats: [Khronos vertex specification](https://wikis.khronos.org/opengl/Vertex_Specification)
- Multi-draw base vertex: [Khronos API](https://wikis.khronos.org/opengl/GLAPI/glMultiDrawElementsBaseVertex)
- Geometry clipmaps: [Losasso & Hoppe 2004](https://hhoppe.com/geomclipmap.pdf)
- Depth precision: [Khronos depth-buffer precision](https://wikis.khronos.org/opengl/Depth_Buffer_Precision)
- Lightweight daylight/aerial perspective: [Preetham et al. 1999](https://doi.org/10.1145/311535.311545)

### Water, transparency, and lighting

- Voxel interaction traversal: [Amanatides & Woo 1987](https://www.cse.yorku.ca/~amana/research/grid.pdf)
- Transparency ordering: [Khronos](https://wikis.khronos.org/opengl/Transparency_Sorting)
- Blend state: [Khronos](https://wikis.khronos.org/opengl/Draw_Buffer_Blend)
- Depth/color write masks: [Khronos](https://wikis.khronos.org/opengl/Write_Mask)
- Fresnel approximation: [Schlick 1994](https://doi.org/10.1111/1467-8659.1330233)
- Weighted blended OIT stretch: [McGuire & Bavoil 2013](https://jcgt.org/published/0002/02/09/paper.pdf)
- Ambient occlusion background: [GPU Gems, Chapter 17](https://developer.nvidia.com/gpugems/gpugems/part-iii-materials/chapter-17-ambient-occlusion)
- Minimal direct skylight precedent: [Luanti lighting](https://docs.luanti.org/for-players/light/)

## When a future phase begins

1. Re-read the vision, roadmap phase, `docs/gates.md`, current status, and this
   phase section.
2. Confirm all entry-checklist items against current code; later fixes may have
   changed the audit facts or byte counts.
3. Copy the phase's **Lock** decisions and fixtures into its implementation
   issue/plan.
4. Run the named measurements and record every selected **Measure** value with
   its evidence.
5. Implement the minimal order and keep every **Defer** item out unless a named
   default fails a gate.
6. File complete metrics, screenshots, product versions, human verdict, and
   revert tag in the phase report.

That procedure is the intended output of this research: the later phases should
start from explicit contracts and evidence, while still allowing V3's actual
measurements and visual judgment to choose constants and optional techniques.
