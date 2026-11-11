---
name: relief-compare-findings
description: Sept 27 2026 comparison of generated worlds with real California/Japan relief — what the large-scale engine lacks, tools and numbers
metadata:
  type: project
---

On 2026-09-27 the owner asked to compare large-scale relief with real California and Japan relief maps. Report: `reports/terrain/relief-compare/README.md`; tools in `experiments/relief-compare/` (fetch.py downloads AWS Terrarium tiles, render.py, metrics.py, fastscape.odin toy uplift+stream-power model) plus `lab grid` / `lab formation`.

Key findings: formation runs 100 kyr with ~0 uplift, so terrain is almost entirely the `mesh_relief` noise prior (median formed-vs-prior change 8–13 m); one orogenic strike per world (grain 0.90–0.96 vs real 0.45); coasts are smooth contours of the 8 km crust grid; no basin-and-range / sediment plains. A 3 Myr uplift+erosion toy run on our own broad shape gives real dendritic valley networks in ~6 s at 250k cells.

Correction: the 'no large rivers' finding was a metric bug (lakes counted as sea); r14 catchments are 19–22k km². Revision 15 (`tectonic_formation.odin`, same day) implemented: uplift from crust strain/envelope with strike-aligned ranges, 6 Myr implicit stream power + threshold hillslopes + basin fill before the old 100 kyr formation; creation 77–89 s; grain 0.29–0.63, relief/slopes near real; fewer lakes and bare-rock slopes remain. Flood must seed only coastal fixed sites (sea sites in the heap cost 4×); erode to sea level not the sea floor.

Follow-up (same day): sea floor, hillslopes, lakes, climate fixed against real data (see README section 'Revision 15 follow-up'); evaluate.sh runs everything. Lessons: slope-share metrics depend on window content; lakes must be measured as components ≥10 ha (flat DEM surfaces for real); tiny lakes came from certification fragments (drop groups <24 cells) and 256 m hollows (breach <48 cells/<8 m); coupling climate runoff needs K rescale; waterless bodies must keep sediment (implicit_transport assert).

**Why:** owner wants more interesting, realistic large-scale terrain.
**How to apply:** recommended next step is driving the existing `landform_step_implicit` with tectonic uplift for millions of years (forcing/duration, not a new solver), measured with metrics.py against the real windows. Watch the 240 s creation budget. Related: [[landform-styles-direction]], [[relief-revision-nine]].
