# Procedural places: shape and context together

The references call for **new, substantial landform geometry whose rock, water and vegetation belong together**. The woodland experiment demonstrated the right local integration; it was not a request to restrict future work to small dry-ground edits. Conversely, the analytic catalogue demonstrated distinct silhouettes without establishing why those silhouettes belonged at their locations. Both lessons should shape the next implementation.

This audit inspected all three supplied images, the terrain query and geology code, channel realization, persistent edits, surface meshing and local habitats. It proposes three contrasting families, each with deliberately different internal arrangements. These are design alternatives for review, not newly counted implemented landforms.

## What the images ask the world to express

**Image 1: waterfall amphitheatre.** The central plunge is tall relative to its narrow upstream opening. A substantial cliff wraps behind it, with an intermediate ledge and several smaller side curtains. Two unequal green shoulders and loose rock converge toward a visibly connected boulder-strewn outlet. Vegetation follows rooting surfaces and wet niches; it does not cover all exposed cliff faces equally. The place has a high rim, a middle ledge, a lower basin and a downstream reveal, all legible from one view. Its exact identity is not assumed from the photograph. Kegon is a useful related real example: Japan's tourism agency describes the Daiya River leaving Lake Chūzenji and dropping97 m into its gorge, which supplies a real upstream/downstream relationship rather than an arbitrary water emitter. [Japan Tourism Agency, Lake Chūzenji](https://www.mlit.go.jp/tagengo-db/en/R2-00024.html)

**Images 2–3: narrow columnar gorge and sidefall.** These show the same kind of place from above and from water level, so a convincing implementation must hold up in both views. Tall opposing walls nearly enclose the sky. Their lower columns differ from upper broken bands, and some rock visibly projects over lower recesses. A tributary drops from one rim into the longitudinal river; it is not the main river inexplicably falling sideways. The gorge bends or constricts beyond the fall, giving partial visibility of what comes next. Canopy roots on the rim, mossy/fern-like cover follows damp ledges, and large bare jointed faces remain readable. The open water level and vertical wall proportions are essential. Neither a hiking path nor a dry crossing is required by the reference.

Columnar geometry does not imply basalt. For Takachiho specifically, the official Gokase river description identifies river erosion of the Aso welded-tuff plateau, and Miyazaki's official description links its joints to Aso pyroclastic flows. Use welded tuff/ignimbrite if claiming that analogue; a separate basalt analogue is also legitimate when generated geology actually supports basalt. [MLIT Gokase River plan, p. 3](https://www.qsr.mlit.go.jp/nobeoka/pdf/news/240524.pdf), [Miyazaki Prefecture](https://www.kanko-miyazaki.jp/en/highlights/sobokatamukiokue_takachiho)

The important common property is a **connected three-dimensional place**, with several related things to discover at different elevations and viewpoints. More terrain noise, a biome name, or a repeating column texture does not provide it.

## Current expression and exact limits

| Representation | Useful capability now | What prevents faithful reference scenes |
|---|---|---|
| `Model.land`, geology, climate and receiver graph | Broad regions, uplift/erosion context, catchment flow, spill relations, geology and ecological supply. | Roughly1km formation mesh cannot resolve a cliff lip, tributary hanging mouth or narrow enclosed gorge. A local scene needs an explicit finer reconstruction tied to its catchment and rock body. |
| `Sample.height`,8 m relief/edit controls, metre surface | Continuous local relief; block cliffs, shelves, floor and canyon planform; deterministic shared terrain queries. | One top height per x/z cannot express an undercut wall or a ledge over an empty recess.8 m interpolation also rounds narrow lips and1–5 m columns. A pure height edit cannot fix this. |
| `column_material` and resident cave voxels | Real solid/material queries and subsurface voids already exist. | Natural cave carving requires depth > 8, so it deliberately leaves an intact near-surface roof. Surface terrain is meshed from height columns. Local surface-connected undercuts need a shared3D solid query consumed by visible surface geometry, collision, mining and distant representation. |
| `Geology` / `Rock` | Finite sediment cover, repeated beds, basement, dip/strike/fracture/permeability, resistance. | No welded-tuff material/body, cooling-unit boundaries, column-joint field, mapped fold/fault trace or explicit permeable contact spring. A scalar fracture amount is not a wall structure. |
| Compiled `Channel_Segment` and `channel_profile_zone` | Connected supplied reaches, bed/stage/depth, pools, lateral valley carving and receiving-water constraints. | Profiles are planar paths with interpolated bed and stage. There is no explicit free-fall reach with top lip, trajectory, impact and receiving pool. A sidefall needs two real water paths and different elevations, not a high head on the main channel. |
| `Surface.water` and water mesher | One standing/flowing column stage; top faces and exposed vertical boundary faces. | Exposed water sides close volume from bed to surface. That is not a detached falling sheet with air behind it; it can look like an unsupported water wall. Spray, impact foam and air-separated falling water need their own connected representation. |
| Groundwater/environment | Recharge, storage, baseflow and an approximate local water-table height. | A groundwater value cannot justify arbitrary visible springs. Side seep curtains require an exposed permeable contact and allocated supplied discharge connected to receiving water. |
| Habitat/vegetation | Cover and soil respond to climate, groundwater and slope; several local woodland communities and surface details. | Current slope rules remove soil/forest on steep terrain, appropriately. They do not establish moisture on vertical rock, mist exposure, crevice rooting or shelf-specific shade. Wall moss should be a face habitat, not trees rooted on impossible slopes. Some current boulders/logs are visual only and cannot serve as traversable geomorphic blocks. |
| `Terrain_Edit` | Persistent bounded dry-ground displacement, zero edge changes, balanced local solids, indexed lookup. Ideal for woodland shoulders, banks and mantles. | Current contract preserves water, stores only height delta and caps local displacement. It cannot become an amphitheatre/fall/undercut compiler simply by increasing amplitude. Keep it as the finishing operation, or add a separate explicit scene transaction. |

These are bounded engineering needs, not a demand for full fluid simulation or geological time stepping. An authored inherited rock body and a steady supplied waterfall are acceptable if accurately described and consistently queried.

## Architecture: one place record with shared relationships

**1. Find a regional opportunity.** Search a receiver corridor, bedrock contact, lake outlet or valley confluence. Record real incoming/outgoing flow and stage constraints, existing regional gradient, host rock thickness and neighboring habitat. If the desired family requires a rock structure absent from the model, introduce a coherent inherited rock-body prior during formation rather than labeling a random finished hill. Its extent should outlive the individual scene.

**2. Plan the place as a small graph.** Nodes describe upstream approach, lip/contact, cliff or gorge reach, impact pool, downstream outlet, tributary mouth, rock shoulder, talus pocket and rooting ledge. Edges describe water connectivity, shared rock boundary, slope continuation and visual adjacency. A planner chooses a coherent arrangement and fits its dimensions to actual available height and catchment supply. The graph is not an automatic trail network: route difficulty and even access may remain uncontrolled.

**3. Compile jointly at appropriate scales.** Use a local heightfield for valley envelope, floor, shoulders and talus. Add sparse 3D solid modifiers only at cliff undercuts, overhangs, projecting blocks and important joints. Derive rock material and joint directions from the same saved body/contact parameters. Build a hydraulic graph with explicit channel, fall and receiving-pool edges; a fall consumes supplied flow and contributes it to its receiver. A rim source that cannot be traced to runoff, an upstream water body or a modeled discharge allocation must be rejected.

**4. Finish the contextual ecology.** Compute soil/deposit thickness, stable rooting ledges, shaded/exposed aspects and distance/exposure to supplied wet faces and impact zones. Apply existing regional species to those niches. The woodland edit approach fits here: expose a shoulder, redistribute mantle, create an irregular forest opening as a consequence. Broad forest character should continue outside the scene.

**5. Persist one accepted result.** Save the scene's stable identity/version, host-body references, boundary constraints, graph, local solid controls, water controls and material/habitat modifiers. All query paths use the same record. Candidate failure leaves the world unchanged. Do not allow later catalogue expansion to move or reinterpret an existing place.

Two transaction modes are needed. The existing dry-ground edit keeps its strong unchanged-water guarantees. A new formation-time scene compiler may legitimately change a local river bed and routing **inside** the scene, but must validate boundary inflow/outflow, stages, basin containment, solid accounting and downstream continuity. Where excavation exceeds local depositional capacity, either account for transported sediment at a real downstream sink or reject the candidate; balancing a huge canyon by creating an equally huge nearby mound is not natural integration.

## Three contrasting place families

### 1. Forested waterfall amphitheatres

Host: a supplied stream or lake outlet crosses a resistant lip over a more erodible or fractured unit, with sufficient existing height difference and an open downstream receiver. The headwall wraps around the stream head, weaker material permits recesses, resistant beds retain ledges, and rockfall/talus occupies the foot where water has not removed it. This structural control is consistent with NPS explanations of steep waterfalls at stronger-over-weaker rock contacts. [NPS waterfall geology](https://www.nps.gov/dewa/learn/nature/waterfalls.htm)

Individually considered arrangements:

- **Single plunge and open talus throat.** One narrow lip fronts a broad asymmetric headwall; the impact pool opens directly into a blocky outlet, with an exposed shoulder on one side and deep rooted woodland on the other. Its identity is the large vertical reveal above an open lower approach. Needs one supplied fall edge and a contained impact pool; an overhang can be deferred for the first version.
- **Main plunge and contact-fed side curtains.** A lower permeable contact crosses one wall, supplying a discontinuous curtain below the main fall and a lush wet ledge. This is the first image's richest relationship. It is accepted only with a contact/discharge model; copying side water lines from the photograph without supply is not a legitimate variation.
- **Offset two-stage chamber.** An upper fall reaches a perched pool behind a resistant shelf, then an offset lower spill opens to the downstream valley. The shelf occludes part of the upper chamber from below, so viewpoints reveal different parts. Needs two pools/stages and a connected second fall; its topology and visual discovery differ from one fall made taller.

Prerequisites: explicit fall hydraulics/rendering, local lip and pool controls, actual resistant-unit relation, local material/soil response. Side curtains add contact discharge. Recesses/overhangs add sparse 3D solid support. Forest height or season are contextual choices, not separately counted landforms.

### 2. Jointed rock gorges with tributary falls

Host: a river cuts a coherent resistant rock body whose joint structure permits steep faces, while at least one supplied tributary or contact-fed stream enters above the main river. Gorge floor and main water surface remain longitudinally continuous. The rock body may be welded tuff, basalt or another suitable jointed unit; those distinctions must be real material/body parameters, not an automatic name multiplier.

Individually considered arrangements:

- **Narrow elbow with a hanging tributary.** The main channel bends behind a projecting wall; one tributary plunges beside that projection. Approaching by rim or water level reveals the fall at different times. Columns change orientation coherently with their cooling body and wall exposure. This most directly targets images 2–3.
- **Joint-controlled constriction and deep pocket.** Two offset resistant buttresses narrow a wider gorge into one deep slot; a tributary enters a sheltered receiving pocket just upstream of the throat. The signature is alternating enclosure and release, with short sightlines and distinct high/low water surfaces. Requires a real receiving pocket, not a circular pool stamped beside a river.
- **Recessed lower wall and retained high ledge.** Differentially weathered units leave a pronounced lower alcove beneath a projecting upper band, while a narrow sidefall passes in front. The visible air gap and layered wall are essential; without 3D support this must remain unaccepted rather than approximated as a sloping wall and relabeled.

Prerequisites: host-body thickness and cooling-joint coordinates, local three-dimensional cliff realization for projections, two connected water paths, metre-scale wall detail shared with collision, stable near/far rendering of narrow gorge depth. Moss/ferns occupy moisture-retaining cracks and ledges; canopy roots above the rim. Do not distribute columns as evenly spaced freestanding cylinders or coat every vertical face green.

### 3. Woodland rock-and-water valley junctions

Host: existing smaller streams, exposed bedrock shoulders, variable soil and woodland cover. These are less monumental than the first two families and build directly on the successful integrated woodland prototype. They provide frequent meaningful places between rarer dramatic gorges, without pretending that every place needs a waterfall.

Individually considered arrangements:

- **Confluence below a weathered shoulder.** Two streams meet below a thin-mantled rock projection. A gravelly inside pocket and denser rooted outer bank respond to real deposition and moisture. The shoulder frames both tributaries; the player can see a branching choice in the landscape even when neither route is easy.
- **Bedrock narrows opening into a fern basin.** One stream squeezes between unequal exposed ribs, then broadens into a sheltered low basin with woodland margins. A wet exposed face and a dry upper shoulder create different niches within tens of metres. Requires coherent channel capacity/stage and local soil redistribution; it can start without detached falling water or overhangs.
- **Lake-outlet shoulder and wooded back inlet.** A real lake outlet leaves beneath a rock shoulder while a quiet side inlet supports denser low vegetation. Open rock provides a distant view; the enclosed inlet gives a close, shaded one. The lake and outlet are authoritative, and no new water is inferred merely from green vegetation.

Prerequisites: existing edit transaction plus context-based bank/shoulder planning, native-query agreement, soil/deposit accounting and supplied water protection. This family can progress sooner, but completing it does not substitute for the new cliff and waterfall capabilities above.

## What to build and verify first

Use one supplied real-world-like opportunity for each of the three families as a review target; do not expand the catalogue during this proof. For the first dramatic scene, prefer the single-plunge amphitheatre: one water path and one impact pool isolate the missing waterfall representation. In parallel retain one woodland junction to prove that the surrounding ecology remains integrated. Then add the gorge sidefall, which exercises two water paths, narrow geometry and views from below.

For every accepted place, render a contextual wide view, rim/approach view and low/inside view at identical before/after camera coordinates. Show an extent at least twice the scene width so a mismatched host cannot hide outside the crop. Record the incoming and outgoing water paths, material section, exposed/vegetated surfaces and what distinguishes the place from the other variants. A place need not be walkable; validate collision and visibility from intended observation locations, and report actual access instead of making a compulsory hiking loop.

Acceptance is relational: the lip belongs to the cliff; the fall reaches its receiver; the tributary really arrives above the main stream; joints belong to the same rock body across both walls; talus lies below its source; trees have rooting surfaces; the gorge continues beyond the staged view. Silhouette correlation and topographic plots remain useful diagnostics, but cannot certify these relationships.

## Implementation status of this audit

No scene architecture or new place family was implemented here. The bounded code fix replaces three unused lower-range bindings in `landscape_arid_test.odin` with `_`. `odin check src/terrain -no-entry-point -vet -strict-style` passes, and both arid landmark-signature tests pass with `-vet -strict-style`. The proposed architecture and prerequisites are deliberately separated from the currently implemented dry-ground edit work.
