---
name: relief-revision-nine
description: "Sept 11 2026 mountain/hill relief pass (world revision 9), its tooling, tuning knobs and known limits"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8e695a7f-9bef-4dd7-8c23-8c7a6e6fb433
  modified: 2026-09-11T21:48:17.352Z
---

On 2026-09-11 the owner asked for real mountains, ranges and hills. World revision 9 adds two declared priors in `src/terrain/relief.odin`: `mesh_relief` (valley network cut below a compressed crust envelope before formation) and a relief-scaled three-band sub-mesh field replacing the old 24 m noise. Also fixed: f32 priority key in `graph_route`, and the reversal dt limiter in `landform_step` (submerged sites exempt, drops <2 m treated as 2 m).

**Why:** Prior mountain work (Japan comparison, catchment experiments) concluded fine erosion is unaffordable world-wide, so structure must come from priors at generation time; the owner wanted visible results, not another sweep.

**How to apply:** Tooling lives in `experiments/relief/` (`main.odin` form/mesh/window/region/trace/prior modes, `review.py` hillshade+metrics, `native.py` GPU frames). Evidence in `reports/terrain/relief/README.md`. Tuning knobs: `relief_gains` (0.5→0.2 of two-ring relief, grain 0.015), `mesh_relief` depth cap 2,400 m and 26 km base wavelength. Never rotate noise coordinates by a position-dependent angle (lever-arm bug produced km spikes). Use `/usr/local/bin/python3` for numpy/PIL/matplotlib. Formation budget: ~90 s terrain for seed 137; watch step counts via `relief-review trace`. Uncommitted work: the owner keeps large diffs uncommitted; do not commit unless asked. Related: [[odincraft-terrain-pipeline]].

**Rivers (same day, second pass):** revision-9 channel compile in `channel.odin` now does snap + sinuosity → provisional segments → hydraulic sizing → migration → junction-aware cut (`channel_cut_path`, floor_bed) → backwater → simplify; `channel_refine` is legacy-only (<9). Sub-mesh relief fades inside valley zones via `channel_suppression`/`region_claims`. `breach_depressions` (mesh.odin, 300 m cap) runs before formation. Pale "river" lines in owner screenshots were quartz veins on top faces (nature.odin). Basin patches (landslide lakes) can look like flooded valleys in maps; check `m.basins` before blaming channels. World-open channel cost ~5.5 s (migration dominates).

**Lakes (Sept 12):** `breach_depressions` keeps compact bodies (≥8 interior sites, ≥30 m) after pass 0, fill cap 150 m, boundary outlets lowered. `model_relief` computes `m.lake` (relief-fade claim) and `m.lake_level` per site; `model_sample`/`model_region` add water wherever ground < lake_level in a lake's facets. Review tooling: `experiments/relief/lakes.py inventory|shore`. Count lake bodies with 8-connectivity; 4-connected labels split bays into fake "tiny lakes".

**Hanging-water lesson (Sept 12):** any lateral stage rule must never wet ground more than a skin below the stage outside the wetted channel; reaches must not swing sideways on slopes; depth floors must be capped. Channels recompile at world open, so river fixes reach existing revision-9 saves after an app rebuild; lake/breach changes need a new world. Verify with `relief-review hanging <world>` before claiming rivers fixed.
