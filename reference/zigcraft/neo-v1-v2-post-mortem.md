---
type: note
date: "2026-06-12"
zettel_id: "202606121529"
tags:
  - projects
  - zigcraft
  - voxel-engine
  - performance
  - post-mortem
  - architecture
aliases:
  - Zigcraft Neo V1-V2 Post-Mortem
---
related:: [[2026-06-12]]
source:: [[202606021245 - Zigcraft Neo V2 Implementation Plan]]

# Zigcraft Neo V1-V2 Post-Mortem
---

This note diagnoses why both `zigcraft-neo` (v1) and `zigcraft-neo-v2` failed to deliver the project vision, with code-level evidence. It exists so [[202606121535 - Zigcraft Neo V3 Implementation Plan]] can stay actionable instead of re-litigating history. The vision itself is restated in the v3 plan; the short version is a playable, smooth, Minecraft-style voxel game with realistic TerraForged-class terrain and horizon-scale view distance.

## Summary verdict

Neo v1 had the right **process** and the wrong **terrain model**. Neo v2 had the right **terrain architecture** and a fatally wrong **build order**. Neither failure was subtle, and both were visible in advance:

- V1's gated, always-playable, phase-by-phase approach produced a real windowed game at 2450–3100 FPS in near-field scenarios, and its failures were localized and diagnosable. But its generator was a taxonomy of hand-shaped noise fields — labeled "mountains" and "rivers" without geological cause — and its rivers looked terrible because they were decorative carve fields, not drainage.
- V2's plan correctly redesigned terrain around a cached regional product with real drainage. But the plan explicitly ordered the previewer before the game ("The first runnable tool is `terrain-previewer`, not the game loop") and deferred rendering, streaming, and the player to Phases 5–10. Execution never honestly got there. When a playable build was demanded, it was bolted on in violation of the plan's own contracts, and performance collapsed below v1.

The common root cause: **"the game is playable and smooth right now" was not a continuously enforced gate.** V1 enforced it early and lost it during the far-LOD phases; v2 never had it at all.

## Neo v1: what happened

Repo: `~/Programming/zigcraft-neo`. Key documents: `docs/performance-reassessment.md`, `docs/far-lod-undersampling.md`, `plans/PLAN.md`, `plans/PLAN-v2.md`, `plans/plan-v3-rewrite-foundation/completion-summary.md`.

### What worked

- **Gated incremental phases.** Window → single chunk → camera → movement → async generation → infinite coordinates → greedy meshing → batched draws. Each phase had numeric targets and a revert commit. Phase 17 reached 2450 FPS (near-grid) and 3100 FPS (streaming-stress) on the M3 Max.
- **Architecture wins worth keeping:** worker pool with backlog/in-flight split (`src/thread_pool.zig`), camera-relative rendering over i64 world coordinates, desired-vs-committed streaming center (zero sync work on movement frames), comptime-gated perf harness (`src/perf.zig`), batched `glMultiDrawElements` submission with a shared GPU arena.
- **Measurement culture**, eventually. Its internal Plan v3 added long benchmark windows, split queue metrics, convergence sentinels, and treats `na` as missing data.

### What failed

1. **Far LOD was tested in isolation, then shipped bundled.** Phases 20–23 landed as one unit; the combined scenario (player walking + near streaming + far tiles updating + boundary shifting) was never a gate. Result: `hole_frames=4` on streaming scenarios and a long tail of seam bugs.
2. **Gates measured FPS and little else.** `mesh_throughput_ratio` hit 0.0 with 12 hole frames on `ground-sprint` in Phase 18 and never blocked. Convergence time reported `na` across all runs — and `na` passed.
3. **Short windows measured warmup transients.** Phase 25's `walk-with-horizon` "1254 FPS" was a 40-frame artifact; a 200-frame steady-state window measured 318 FPS. The phase gate never actually passed.
4. **The terrain model was wrong at the root.** `src/worldgen.zig` samples each column from local fields: continent mask, hashed terrain-family weights, hand-shaped sin/cos terrain functions, bounded tile-local river segments with a global sinusoidal outlet. Coverage metrics said "rivers exist"; the rivers visibly did not drain anywhere. See [[202606021223 - Voxel Engine Foundation Synthesis]] for the full diagnosis: *realism comes from causal structure, not from naming more noise layers.* The quality gap was not subtle: despite realistic generation being the repeatedly stated top priority, the shipped terrain read worse than basic Minecraft clones — and no gate could say so, because the executing agent was allowed to self-certify visual quality.
5. **Benchmarks drifted from real play (user-reported, 2026-06-12).** Later-phase scenarios were short synthetic paths. Actual long-horizon gameplay — generating thousands of chunks over a prolonged session, moving back and forth between new terrain and previously visited terrain — was never a scenario class. Sustained churn, revisit costs, eviction behavior, and long-run degradation were invisible to every gate, so measured performance diverged from felt performance and the code lost contact with reality.

## Neo v2: what happened

Repo: `~/Programming/zigcraft-neo-v2`. Plan: [[202606021245 - Zigcraft Neo V2 Implementation Plan]]. Key evidence: `docs/v1-v2-performance-comparison.md`, `src/terrain/region_cache.zig`, `src/game/playable.zig`, `src/perf/benchmark.zig`.

### The plan's philosophical error

The plan got the terrain architecture right (RegionTile product, drainage-derived rivers, one terrain truth for near and far, async state machine, the source-video optimization checklist). But it inverted the build order:

- Non-goal: "Do not start with a full in-game renderer before the terrain product looks plausible in a previewer."
- Bootstrap rule: "The first runnable tool is `terrain-previewer`, not the game loop."
- The renderer arrives Phase 6, async streaming Phase 7, far LOD Phase 8, the "hard demo" Phase 10.

This made the game the *last* deliverable instead of the *standing harness*. Every claimed optimization was therefore validated only against previewer output and isolated microbenchmarks. The plan even contained the right gates (`sync_fallbacks == 0`, "no main-thread terrain generation", "every optimization tested on realistic traversal, not microbenchmarks") — but they were defined for phases that execution never reached honestly.

### The execution failures (code evidence)

When a playable 3D build was demanded, it was assembled against the plan's own rules:

1. **The region cache does not cache.** `src/terrain/region_cache.zig:13-15` — `generate()` is a pass-through that calls `RegionTile.init` every time. Every region access regenerates 8.6 MB of terrain fields, measured at ~347 ms per region, synchronously, on the main thread. The playable build holds ~12 regions resident; crossing a boundary regenerates them live.
2. **The scene is rebuilt every frame.** `src/game/playable.zig:349-359` with `release_scene_publish_interval_ticks = 1`: each frame allocates fresh vertex/index buffers and memcpys every resident chunk mesh (~1,650 chunks at runtime) into them. Per-chunk dirty meshing exists, but the full-scene rebuild swamps it.
3. **Nothing is async.** All pipeline stages run single-threaded on the main loop tick. Phase 7 (async streaming) was never reached; the playable mode shipped anyway.
4. **Benchmarks measured the fast path only.** `src/perf/benchmark.zig` tests 8 regions and 64 static chunks in isolation: 0.037 ms/chunk materialization, 0.026 ms/chunk greedy mesh, "hard-demo" frame p99 = 0.007 ms — headless, 64 chunks, no streaming, no regions crossing, no scene churn. End-to-end frame time with a moving camera and a dynamic resident set was never measured, so the collapse was invisible to every gate.

### Resolution of the "where did the order-of-magnitude go" question

It never existed end-to-end. The claimed numbers were real but for isolated subsystem throughput on toy workloads. The comparison doc itself admits it: "V2 hard-demo frame timings are useful as a CPU renderer-pipeline gate, not as a direct replacement for v1 windowed FPS." Meanwhile the actual per-region generation cost (~347 ms) was *higher* than anything v1 did synchronously, and the no-op cache plus per-frame scene rebuild put that cost directly on the frame thread. Fast parts, assembled into a slow whole, with no gate watching the whole.

## Cross-cutting lessons for v3

1. **The playable game must be the benchmark harness.** Every phase gate runs inside the windowed game on realistic terrain while moving. Microbenchmarks may justify work; only in-game scenarios may accept it.
2. **Build the engine spine first on placeholder terrain, then iterate realism behind a stable interface.** V2 proved the region-product architecture is right; v1 proved the game-first order is right. V3 does both: the streaming/render/LOD spine completes early against a trivially-simple region product, then terrain realism deepens inside the always-running game.
3. **Caching and async are testable contracts, not intentions.** Regression tests must assert cache hits (generate-twice → second is a hit) and zero main-thread generation. V2's cache was a no-op for its entire life and no test noticed.
4. **Gate on the full metric set, with long windows and medians.** p50/p95/p99, worst frame, hitch count, `hole_frames == 0`, `sync_fallbacks == 0`, `mesh_throughput_ratio >= 1.0`, queue ages, ready-latency percentiles. `na` fails. Windows ≥ 200 frames and ≥ 5 s past warmup; median of 3 runs.
5. **No phase bundling; failed gates spawn numbered fix-phases.** V1's 20A/B/C emergency spiral and the 20–23 bundle made failures impossible to isolate.
6. **Performance claims must surface in-game or be reverted.** An optimization that does not move an end-to-end metric is dead weight and probably hiding a defect elsewhere.
7. **Terrain realism gates are model-level, not coverage-level.** Rivers flow downhill through connected basins; width follows flow accumulation; confluences are topological. "A river exists" is not a gate.
8. **Benchmarks must come from play, and play must feed back into benchmarks.** Scenario suites drift from reality unless real sessions are recorded and replayed as benchmarks, long-horizon soak (sustained generation plus revisiting old terrain) is a standing scenario class with drift gates, and every divergence felt in play is converted into a permanent scripted scenario before its fix merges.
9. **Visual quality needs an external authority and a comparative floor.** An executing agent will mark its own terrain acceptable. Terrain phases require human sign-off against a fixed visual reference board, with "at least as good as vanilla Minecraft" as the explicit floor and TerraForged as the target. Ugly terrain stops the line the same way a failed performance gate does.

## References

- [[202606021223 - Voxel Engine Foundation Synthesis]] — terrain-model diagnosis and reconciled engine model.
- [[202606021245 - Zigcraft Neo V2 Implementation Plan]] — the v2 plan critiqued above.
- [[Mesh Production Bottleneck — Phase 15]], [[Zigcraft Phase F Far LOD Architecture Review]] — v1-era warning notes that proved prophetic.
- `~/Programming/zigcraft-neo/docs/performance-reassessment.md` — v1's own gate-failure audit.
- `~/Programming/zigcraft-neo-v2/docs/v1-v2-performance-comparison.md` — v2's own caveat that its numbers were not game numbers.
