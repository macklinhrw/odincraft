# Individually crafted terrain integration

The acceptance target is **at least 200 distinct, individually designed terrain types discoverable in generated worlds**. The user explicitly rejected bulk feature creation, label variants, and a catalogue filled by multiplying base shapes by presets. This target remains open until the criteria below are satisfied.

Each counted type needs its own recognition goal, characteristic geometry, exploration experience, ecological/geological placement, individual visual review at real proportions, and an observed location in production generation. Shared math and placement code are infrastructure; reusing them does not establish a distinct identity. A named entry, differing noise seed, amplitude, palette, or instance does not count as a new terrain type.

## Design direction confirmed by the user

The target includes both dramatic new landforms and the quieter, integrated woodland changes of the approved first experiment. The Japanese waterfall and gorge references express connected places: a supplied upper stream, a resistant lip, a cliff, falling water, a receiving pool, an outlet, wooded shoulders, and exposed or moist wall faces. Their relationships matter as much as each part's shape. A natural exploration route may contain an impassable cliff or deep gorge; do not manufacture a hiking trail or make every place walkable.

The user's review of the isolated group images exposed a problem with free-standing analytic stamps. Regional placement by climate and rock class alone does not establish a natural setting. Catalogue expansion is paused while linked place formation is proved in actual worlds. Analytic studies remain useful geometry candidates, not accepted production terrain. The architecture and reference analysis are in [Explorable places](../../reports/terrain/EXPLORABLE-PLACES-DESIGN.md).

## Review gates

1. **Designed:** an individual signature, traversal intention, host requirements, and concrete acceptance criteria exist.
2. **Shape reviewed:** monochrome plan, section, and physical-proportion views show the intended geometry; continuity, deterministic evaluation, and morphology checks pass. Inspect each sheet individually and record revisions. Correlation checks catch some duplicates but cannot establish uniqueness alone.
3. **Integrated:** the actual sampler, materials, habitat, rivers, near voxels, and distant surface realize the design together. Context-dependent features must receive their context; an inland ridge does not count as a barrier island.
4. **World reviewed:** inspect a naturally selected occurrence in the native renderer from its surroundings, rim and interior where applicable. Verify actual access, collision and sightlines, including natural obstacles. Record coordinates, seed, evidence, and any shortcomings.
5. **Accepted:** the previous gates pass and the design is distinguishable from its nearest catalogue neighbors. Only this status counts toward 200.

Rejected and unfinished candidates remain visible in the ledger. Do not increase the count by weakening these gates.

## Current implementation

Revision 14 combines the faster implicit regional erosion, directional fine relief and 256 m drainage network from `evaluate-faster-erosion` with the local habitat vocabulary and persistent contextual place records. Both development branches' incompatible revision-12 recipes are identified from their saved payloads; their terrain and companions remain distinct. Revision 13 retains its imported hydrology recipe. Earlier revision-14 event snapshots also retain their original place recipe, verified against the unmodified merge-checkpoint binary. The analytic district catalogue remains disabled in normal generation.

Dry finishing records share an indexed 8 m control lattice, preserve wet metre columns and water stages, and balance cut and deposition. Waterfall records link a supplied source, clear airborne sheet, local cliff/pool excavation and the existing curved receiving channel. Excavation/export is measured, saved and validated along actual downstream topology. The fine network uses channel provenance; older worlds retain their coarse catchment provenance. A bounded river-regrade record can fit a supplied channel through a local rise without removing the global incision cap or suppressing unrelated tributaries.

The manual 51.5 m waterfall in seed 543 passes composition, ribbon clearance, support and persistence checks. Native rendering now includes the detached water sheet, impact treatment, localized wet rock and inherited joint-oriented cliff faces. The remaining smooth bowl and regular cliff bands prevent declaring the morphology finished. The general planner finds more valid occurrences by considering feasible alternatives within each cell; these are instances of one arrangement, not extra accepted types.

Fresh woodland review rejected the generalized seed-543 lookout: a long bare shelf looked artificial and intervening ground obscured the lake. Its wet-column and storage checks pass, but that is insufficient visual acceptance. New fine-drainage formation has no coarse Basin_Patch at the tested seed; future woodland selection must use actual resolved shorelines and standing-height sightlines. Post-drainage scenery must use separate Terrain_Edit records so rebuilding drainage sees the same immutable input. The old basin-mutating scenic operation is retained for its diagnostic/legacy studies and is not applied automatically to new revision-14 worlds.

Three full combined worlds now form and reopen correctly: seed 543 takes 100.86 s / 1.52 s, seed 137 takes 103.87 s / 1.47 s, and seed 193 takes 129.01 s / 1.84 s. Their fine networks contain 1,040,082, 961,907 and 1,543,045 channel segments respectively. Seed 193 has two formed basin patches; the others have none. These are generation/integrity measurements, not completion of the individually crafted 200-type target.

The current woodland shoulder opens along the measured downhill slope, follows unequal geological joint faces, and retains a rooted flank. It rejects closed pockets and checks the actual final eye against terrain and canonical trees. Native review accepts the seed-137 occurrence as natural local granite detail at an existing lake prospect; the seed-543 limestone detail still fails as an overlook because the lake is screened by crowns. Both preserve the complete drainage/habitat state and more than one million reopened metre columns. This is one carefully refined ground-detail arrangement, not two new destinations. Production distribution remains disabled while canonical worker-safe visibility and useful occurrence density are verified.

Fine waterfall formation now retains the existing valley ground, chooses an outlet join at or below the receiving stage, distinguishes real lake inundation from dry lake-index coverage, and preserves source water across numerical rounding at the lip plane. Lake sediment is an explicit saved one-metre submerged deposit with exact column-volume accounting, owner identity, entry-connected water, retained stage and capacity checks. Waterfalls and local river repairs share this implementation and roll back excavation and deposition together. Both have successful synthetic transaction/save/reopen proofs. Two actual receivers remain too small: 1,820 m³ versus a 63,338 m³ waterfall cut, and 85 m³ versus a 1,310 m³ river repair. These candidates remain rejected; transport through lakes is not implemented or assumed.

A separate actual seed-137 candidate at span 625956 passes the complete physical transaction: a supplied 25.197 m fall, zero imported ground, and all 42,246 m³ of excavation deposited in its actual receiving lake. Saved and reopened records, caches, 45,796 waterfall-region columns and 1,048,576 deposit-region columns agree exactly, including point/metre queries. The existing two-sided gorge context gate rejects this open setting as `Unconfined`. Native amphitheatre review also rejects its current morphology: a long uniform outlet trench, continuous shelves, regular pool steps and a tall planar cut wall read as an excavation. The falling sheet visibly reaches the real pool, but this candidate is not counted or distributed as an accepted place. [The saved-world proof](../../reports/terrain/fine-waterfall-fitting/amphitheatre-137-625956-proof.md) establishes physical correctness; [the native interior](../../reports/terrain/amphitheatre-native/after/inside.png) records the separate shape failure.

The current actual-world habitat survey fixes starts by geographic dry-continental criteria before observing diversity. Eight 10 km polylines in the three combined worlds have 119 local transitions versus two with the old regional-profile comparison on the same unchanged terrain. Longest unchanged runs are 1.0–2.3 km versus 6.325–10 km; each route encounters three to five local communities. One geographic stratum has no eligible start and is reported absent. Most routes remain treeless arid country, and several cross steep or wet barriers; these are sampled landscape encounters, not controller-verified walking routes. With a 1,000 × 1,000 km world, a handful of curated landmarks cannot address walking-distance variety. Contextual destination density remains unproven.

The distinct tributary-into-main-river arrangement now has an actual contextual lead: seed 137, tributary 655584 into receiver 657581 beside retained main 656749. A partial-channel probe has 17.39 m head only 12.39 m from the main, exposed gneiss and two enclosing banks. The current whole-endpoint builder cannot express that lip. The next bounded proof must inspect metre profiles and the unmodified native scene before designing fractional ownership; it must preserve the retained main rather than create another long tributary outlet trench. The strongest humid example in seed 193 is actually lake-backed and is not relabeled as a flowing main-river gorge. [Branching-gorge survey](../../reports/terrain/hanging-valley-survey/README.md).

## Initial landform ledger

| Type | Individual distinguishing intent | Current gate | Remaining |
| --- | --- | --- | --- |
| Mesa country | Broad irregular skyline tables and scarp-foot routes | Shape reviewed | Natural placement, flat crown under regional slope, native traversal |
| Butte field | Finite unequal crowns separated by open low ground | Shape reviewed | Natural placement and native traversal |
| Cuesta slopes | Long dip slope opposite a short scarp | Shape reviewed | Natural placement and native traversal |
| Hogback ridges | Narrow two-sided resistant crests and low cols | Shape reviewed | Natural placement and native traversal |
| Rock fins | Thin blades broken by passable transverse gaps | Shape reviewed | Natural placement and native traversal |
| Transverse dunes | Asymmetric winding wave fronts | Shape reviewed | Sand realization, natural placement and native traversal |
| Longitudinal dunes | Tapering smooth crests and continuous troughs | Shape reviewed | Sand realization, natural placement and native traversal |
| Crescent dunes | Open crescents with unequal thinning horns | Shape reviewed | Sand realization, natural placement and native traversal |
| Star dunes | Unequal curved arms meeting in central peaks | Shape reviewed | Sand realization, natural placement and native traversal |
| Yardang ridges | Blunt stone heads with tapered tails and wind-aligned lanes | Shape reviewed | Natural placement and native traversal |

The initial ten have individual review sheets and deterministic, bounded, continuous shape tests. Dune amplitudes were reduced after reviewing physical proportions and slopes. They are **ten candidates, zero fully accepted production types** at this checkpoint. Twelve additional authored habitat communities are undergoing separate native palette reviews; habitats are not added to the terrain-type count.

## Analytic studies retained for further integration

- Arid, structural, coastal: 30 additional named identities, reviewed independently. Coastal candidates require shore alignment and sea-level composition before they can be integrated.
- Alpine, glacial, granitic, periglacial: approximately 35 individually justified candidates; exclude synonyms and weak variations.
- Fluvial, lacustrine, interior wetland, karst: approximately 35 individually justified candidates. Terrain geometry alone cannot invent supplied rivers or standing water.
- Seven igneous studies have geometry; further named placeholders remain disabled and do not count as authored features.
- Further batches wait for connected-place integration and individual naturalness reviews. These studies are not completion counts and do not satisfy the acceptance target.

## Current evidence

- [Merged recipes and existing-world compatibility](../../reports/terrain/merge/README.md): genuine two-parent merge `e9fb464`, distinct revision-12 payloads and preserved existing saves.
- [Current woodland shoulder](../../reports/terrain/woodland-shores/README.md): individual morphology refinement, native before/after views, actual vegetation screening and two independent whole-patch save proofs.
- [Actual dry-country routes](../../reports/terrain/local-routes/README.md): fixed geographic selection, unchanged revision-14 terrain, observed habitat transitions and explicit slope/water barriers.
- [Fine waterfall fitting](../../reports/terrain/fine-waterfall-fitting/README.md), [actual receiver repair](../../reports/terrain/fine-receiver/README.md), and [receiving sediment](../../reports/terrain/channel-sediment-actual/README.md): concrete physical improvements and measured remaining constraints.
- [Generalized woodland native review](../../reports/terrain/woodland-generalized/review.md): actual forest, shoreline and ravine context; 37,160 wet columns unchanged.
- [Real drainage opportunity survey](../../reports/terrain/place-survey/README.md): five candidates in three existing worlds, with exact hydraulic profiles, exposed geology and blockers.
- [Waterfall rendering diagnostic](../../reports/terrain/waterfall-render/review.md): synthetic GPU seam verification only; never counted as natural placement.
- [Arid context audit](../../reports/terrain/landforms/arid/CONTEXT-AUDIT.md): placement and morphology blockers remain explicit instead of being hidden by a catalogue total.

## Whole-world acceptance

Use at least three representative newly formed worlds and ordinary starting routes, including dry continental terrain like the user's screenshot. Report terrain/habitat encounters, longest unchanged stretches, visibility, traversability, and actual coverage of each type. Do not use curated camera sites as the only evidence of discoverability. Preserve hydrology, save/reopen determinism, metre/region agreement, streaming behavior, and generation budgets; measure performance rather than inferring it from unit tests.
