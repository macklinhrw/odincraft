# Large-scale relief against California and Japan

September 27, 2026. Four revision-14 worlds (seeds 555, 534, 193, 543) compared with real elevation at the same scale, rendering and metrics. Research only; no generator change.

## Method

- Real data: AWS Terrain Tiles (Terrarium encoding; sources include SRTM, GMTED2010 and ETOPO1), resampled to a local metric grid. 1000 × 1000 km windows at 1 km centred on California (37.3°N, 119.3°W) and central Japan (36.3°N, 137.8°E); 100 × 100 km windows at 100 m over Yosemite/Sierra Nevada and the Hida mountains.
- Ours: whole worlds at 1 km, and the most mountainous 100 km window of three worlds at 100 m, each cell averaging 4×4 (1 km) or 2×2 (100 m) production point samples with lab options off.
- Same colour ramp, light and exaggeration for every panel. Tools: `experiments/relief-compare/` (`fetch.py`, `render.py`, `metrics.py`, `fastscape.odin`) and `lab grid` / `lab formation` in `experiments/landform/main.odin`.

![1000 km overview](overview.png)

![100 km mountains](mountains.png)

## Measurements (1000 km windows, 1 km cells)

| | California | Japan | 555 | 534 | 193 | 543 |
|---|---|---|---|---|---|---|
| One dominant grain (0 varied … 1 single direction) | 0.44 | 0.47 | 0.96 | 0.90 | 0.92 | 0.90 |
| Lineation coherence at ~15 km | 0.30 | 0.17 | 0.61 | 0.56 | 0.57 | 0.53 |
| Flat lowland (<300 m, <1°), % of land | 9.7 | 18.4 | 13.6 | 3.6 | 5.0 | 7.6 |
| Relief within 10 km, median m | 491 | 559 | 375 | 667 | 271 | 377 |
| Relief within 50 km, median m | 1,381 | 1,605 | 1,071 | 2,871 | 442 | 749 |
| Slopes over 10° at 1 km, % of land | 6.6 | 8.7 | 12.4 | 18.9 | 8.6 | 10.5 |

Full values: [metrics.json](metrics.json). Drainage rows are omitted here: these exports counted lakes as sea (see the correction below).

## What is missing

1. **Mountains are placed, not formed.** The formation stage runs 100,000 model years with at most a few metres of uplift (0.23 m per unit of crust strain over the whole run, `model.odin`). Comparing each saved land site with its declared prior (`mesh_relief`), the median change is 8–13 m and 90% of land moves less than ~85 m. Almost all relief is the noise prior plus sub-mesh filters. At 100 km our mountains are isolated elongated ridges standing on a lake-dotted plateau; real mountains are continuous branching valley networks in which every ridge connects and every slope drains.
2. **One structural grain per world.** `mesh_relief` uses one orogenic strike for the whole world, so ridges everywhere run parallel (grain 0.90–0.96 against 0.44–0.47). Real regions combine several belts, arcs and orientations.
3. ~~**No large river systems.**~~ **Correction:** this finding was a measurement error. The first exports marked lakes and wide rivers as sea, which cut river basins apart. With only the ocean as base level, revision-14 worlds reach 19,000–22,000 km² catchments, comparable to Japan (13,000 km²).
4. **Coastlines are smooth contours of an 8 km crust grid.** The land mask is a bilinear contour of the 8 km crust model and the valley prior fades out at sea level, so coasts are smooth arcs without bays, drowned valleys, headlands or offshore islands, and sea floors are smooth ramps without shelves.
5. **No basin-and-range structure.** Real regions pair uplifted ranges with sediment-filled basins and plains (Central Valley, Owens Valley, the Matsumoto basin, Kantō plain). Ours has a noisy plateau between ridges instead.

Local slopes are already steeper than real at 1 km (8.6–18.9% of land over 10° against 6.6–8.7%); the problem is organization, not roughness.

## Proof of mechanism: uplift + erosion on our own broad shape

`fastscape.odin` is a minimal implicit stream-power and hillslope-diffusion model (after Braun & Willett 2013) on a 200 m grid. Starting from seed 534's smoothed mountain window with uplift proportional to its broad height, 3 million model years produce branching valley networks, connected ridges and spurs (250,000 cells, ~6 s). Near balance (10 Myr) the relief is lower and grid-aligned channels show; the model is a demonstration, not a candidate.

![Uplift and erosion proof](erosion-poc.png)

The production formation already uses the same implicit stream-power scheme on the 1 km mesh (`landform_step_implicit`). What is missing is the forcing and duration: uplift fields from the tectonic model and millions rather than one hundred thousand model years.

## Recommended engine changes

1. **Form the large scale by uplift and erosion.** Derive an uplift field from the crust model's convergence/strain (belts, arcs, extension) and run the existing implicit formation for several million model years at large time steps. Measure against these metrics before tuning.
2. **Tectonic variety.** Several belts with their own orientation and curvature per world, plus extensional fault-block ranges and subsiding basins where sediment accumulates into plains.
3. **Let sea level cut the formed surface.** Coastlines then follow drowned valleys and ridges; add shelves from sediment and wave planation.
4. **Keep the small scale designed.** Below ~1 km the landform styles, habitats and river planform from `experiments/landform` remain the right layer; the evolved surface supplies their context.

Known risks: the 240 s creation budget (formation currently ~12 s for 32 steps), resolution dependence recorded in `plans/terrain-reconstruction/mountain-development.md`, and compatibility with saved worlds (a new recipe revision).

## Revision 15: tectonic formation (implemented)

New worlds (revision 15, `src/terrain/tectonic_formation.odin`) are formed rather than declared:

- **Uplift field from the crust model.** Collision belts (crust strain relative to the world's deformed crust) carry ranges aligned with the belt's own strike, blended from six fixed orientations so no coordinate is rotated by a position-dependent angle. Thick crust lifts faster; interiors away from belts can carry tilted fault blocks (basin-and-range); the coastline is perturbed at 20–90 km.
- **Six million model years of uplift and erosion** on the 1 km mesh: priority-flood routing, implicit stream power to sea level, threshold hillslopes (0.6), hillslope diffusion, and eroded rock filling closed basins. The existing 100 kyr ledger formation then continues with the same uplift.
- Existing saves keep their recipes; only new worlds use revision 15.

Measured on full worlds (seed 555, 534), same sampling as the game, ocean-only base level:

| | California | Japan | r14 555 | r15 555 | r14 534 | r15 534 |
|---|---|---|---|---|---|---|
| One dominant grain | 0.44 | 0.47 | 0.96 | 0.63 | 0.90 | 0.29 |
| Lineation coherence | 0.30 | 0.17 | 0.61 | 0.28 | 0.56 | 0.23 |
| Relief within 10 km, median / p90 m | 491 / 1,040 | 559 / 1,070 | 420 / 1,620 | 440 / 1,343 | 673 / 2,003 | 483 / 1,179 |
| Relief within 50 km, median m | 1,381 | 1,605 | 1,710 | 1,458 | 2,416 | 1,384 |
| Slopes over 10°, % | 6.6 | 8.7 | 12.3 | 10.4 | 18.8 | 10.2 |
| Coastline complexity | 6.4 | 16.1 | 7.6 | 15.5 | 5.1 | 11.8 |
| Largest drainage area, km² | 177,700 | 12,964 | 18,814 | 15,153 | 21,637 | 23,333 |
| Closed depressions >5 m, % land | 12.2 | 6.2 | 8.5 | 2.8 | 10.9 | 2.7 |

Full values: [metrics-r15.json](metrics-r15.json).

![Revision 14 vs 15 at 1000 km](r15-overview.png)

![Mountains at 100 km](r15-mountains.png)

![In-game views](r15-native.png)

**Cost.** Complete creation: seed 555 89.3 s (was 97 s), seed 534 76.7 s. The tectonic phase takes 13–16 s (200 steps; routing ~50 ms per step after seeding the flood only from coastal base-level sites). Peak creation memory about 2.1 GB. All 193 tests pass; point/region agreement is exact.

**Remaining.**
- Fewer closed basins and lakes than revision 14 (lakes 1.8–1.9% of land versus 2.4–2.7%): sediment fills basins completely. Retaining some basins, and glacial overdeepening in high mountains, are the next water steps.
- Steep formed slopes lose soil under the existing slope rule and read as bare grey rock; soil and vegetation on mountain slopes need a pass.
- Sea floors are still smooth ramps from the 8 km crust; no shelves or submarine canyons.
- Runoff is uniform; wet and dry mountains erode alike.

## Revision 15 follow-up: sea floor, hillslopes, lakes and climate

September 27, 2026. Every target is a real measurement; tooling in `experiments/relief-compare/` (`evaluate.sh` runs all checks on a world). Final full creations: seed 555 109.5 s, seed 534 93.9 s (tectonic phase 15–18 s). All 193 tests pass; point/region agreement is exact. Raw outputs: [eval-555.txt](eval-555.txt), [eval-534.txt](eval-534.txt).

References: AWS Terrain Tiles (California, central Japan, US East Coast, European Alps, San Gabriel Mountains, Hida mountains, Lake Tahoe); WorldClim 2.1 BIO12 annual precipitation (10′); HydroLAKES (Messager et al. 2016: lakes ≥10 ha cover 1.8% of global land); Verpoorter et al. 2014 (all lakes ≥0.002 km², 3.7% of non-glaciated land); DiBiase et al. 2010 (catchment-mean hillslopes 10–38°, threshold ~35°) and 2012 (little bedrock exposure below 30° mean slope, rising strongly above; modal slopes near 37°).

### Sea floor
Continental margins from distance to the coast: a concave shelf to a break at 72–112 m, narrow at deforming margins and wide at quiet ones, a ~35 m/km slope with canyons, abyssal hills and seamounts.

| | California | Japan | US East | 555 | 534 |
|---|---|---|---|---|---|
| Shelf width (shelf area / coastal cells) | 6.7 km | 9.7 km | 15.8 km | 11.6 | 14.5 |
| Shelf gradient | 6.2 | 5.1 | 1.1 m/km | 6.1 | 6.0 |
| Floor roughness (10–150 km offshore) | 314 | 331 | 178 m | 174 | 208 |
| Continental slope gradient | 40.1 | 34.9 | 66.9 m/km | 42.4 | 52.4 |

Depth by distance offshore falls between the real coasts in every band out to 200 km.

### Hillslopes and bare rock (10 m sampling, 500 m blocks)
The sub-mesh relief envelope is capped (relief 800 m, gain 0.8) so gullies cannot steepen hillslopes past the threshold; soil holds to ~42° local slope; habitat stability reads mesh slope ×0.65.

| | San Gabriel | Hida | 555 most rugged | 534 most rugged |
|---|---|---|---|---|
| Block mean slope p50 / p90 / max | 30.4 / 36.0 / 45.2° | 32.4 / 38.7 / 49.3° | 30.9 / 34.9 / 44.0° | 32.6 / 37.0 / 45.7° |
| Modal slope in steep blocks | 34.5° | 33.5° | 33.5° | 35.5° |
| Share steeper than 45° | 5.0% | 13.8% | 8.6% | 11.1% |

Bare rock: 0–2% below 30° block-mean slope, 3–4% at 30–35°, 7% at 35–40°, 18–21% above 40°. Typical (90th-percentile) mountain windows are gentler (p50 ~23°).

### Climate and erosion
Moisture now arrives with westerlies in the north and a monsoon easterly in the south, ascent is smoothed over ~18 km upwind and 40% of rain is recycled. The tectonic phase recomputes this climate every 0.6 Myr and erodes with its accumulated runoff (discharge), not uniform runoff.

| Annual precipitation on land | p10 | p50 | p90 | p90/p10 | Contrast within 200 km (median / max) |
|---|---|---|---|---|---|
| California | 137 | 291 | 958 mm | 7.0 | 2.1 / 7.2 |
| Japan | 1306 | 1658 | 2151 | 1.6 | 1.3 / 1.6 |
| US East | 1000 | 1124 | 1260 | 1.3 | 1.1 / 1.2 |
| 555 | 798 | 1385 | 1890 | 2.4 | 2.0 / 2.2 |
| 534 | 688 | 931 | 1613 | 2.3 | 1.7 / 2.3 |

### Lakes (400 km of land at 100 m, lakes ≥10 ha)
Real lakes were detected as connected, exactly flat DEM water surfaces (Lake Tahoe checks correctly). Hollows smaller than 3 km² or shallower than 8 m are opened from every low point on the 256 m drainage grid; certified lake groups under 1.5 km² (fragments of hollows whose level fell to a lower metre-scale rim) are dropped; fault-block basins subside slowly, so some keep large lakes.

| | Cover | Lakes /1000 km² | 0.1–1 | 1–10 | 10–100 | >100 km² | Area in ≥1 km² |
|---|---|---|---|---|---|---|---|
| California | 0.73% | 2.31 | 1.58 | 0.62 | 0.10 | 0.01 | 93% |
| US East | 0.14% | 1.21 | 1.05 | 0.13 | 0.03 | 0.00 | 82% |
| 555 | 0.28% | 1.52 | 1.09 | 0.39 | 0.04 | 0.00 | 77% |
| 534 | 0.80% | 2.36 | 1.71 | 0.53 | 0.10 | 0.01 | 89% |

The earlier revision-15 world had 43 lakes per 1000 km², almost all tiny ponds (5% of area in lakes ≥1 km²).

### Relief after coupling (1000 km windows)
Thick crust now forms plateaus in the initial surface; rapid uplift is confined to active belts. The European Alps were added as a mountain reference.

| | California | Japan | Alps | 555 | 534 |
|---|---|---|---|---|---|
| Relief 10 km median / p90 | 491 / 1040 | 559 / 1070 | 271 / 1373 | 460 / 1068 | 598 / 1066 |
| Relief 50 km median / p90 | 1381 / 2244 | 1605 / 2402 | 801 / 2520 | 1207 / 2159 | 1444 / 2256 |
| Slopes >10° | 6.6% | 8.7% | 12.8% | 9.8% | 11.7% |
| Flat lowland | 9.7% | 18.4% | 19.4% | 14.6% | 7.8% |
| Grain / coherence | 0.44 / 0.30 | 0.47 / 0.17 | 0.20 / 0.18 | 0.28 / 0.17 | 0.16 / 0.21 |
| Coastline complexity | 6.4 | 16.1 | 9.9 | 8.2 | 5.3 |

(Steep-land share depends on the window: the central 400 km of California and Japan have 10.5% and 13.5%.)

![Final in-game views](r15-final-native.png)

### Outside the real range
- Seed 534 is more mountainous than any reference: 10 km median relief +7%, flat lowland 7.8% (min 9.7%), grain 0.16 (min 0.20), coastline 5.3 (min 6.4), lake cover 0.80% (max 0.73%).
- Seed 555: 50 km relief p90 −4%; area in lakes ≥1 km² 77% (min 82%).
- Closed depressions at 1 km remain 3–4% (real 6–12%); the lake statistics at 100 m, which describe actual water, match.
- The bare-rock rise above 30° is present but modest (to ~20% above 40°); DiBiase et al. report only the trend.
- Default (non-lab) rivers still leave 0.5–2 m water faces on the steepest slopes; the lab river rebuild removes them.
