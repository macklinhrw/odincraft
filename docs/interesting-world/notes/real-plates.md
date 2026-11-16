# The real Earth's plates, and what a plate story must match

Research notes for OdinCraft v5, 2026-11-15, written for step 22 (`foundations.md` section 8; the design is `foundations/plates.md`). The owner's goal of the same day is that every island and continent comes out of one history of moving plates, and that the history be measured against the real Earth's through time so the simulation's faults can be seen and fixed. This note says what the real Earth does at the sizes and rates that matter, what real history can honestly be compared against and under what licence, how others have simulated plates cheaply, and what the first comparison found. Sources are linked inline; "memory" marks what I could not check against a source this session. Every figure in the tables of "Through time" was computed by one script on the same grid for the real Earth and for ours.

## Key takeaways

1. **There is a real reference through time, and it is open.** Müller et al. 2019's plate model (plates, their boundaries and motions from 250 Ma to today in a mantle frame) and its ocean-floor age grids at every Myr are under CC BY 4.0, as are Scotese & Wright 2018's PaleoDEMs (land and sea floor at 1° every 5 Myr back to 540 Ma) and Merdith et al. 2021's model back to 1 Ga. `pygplates` reconstructs the plates at any time in 0.1 s. Nothing of it is kept in the repository; the figures computed from it are.
2. **Real plates are large, few and unequal**, which a 1,000 km world cannot hold. Today's 52 plates (Bird 2003) range from 18,000 km² to 100 million km²; the largest takes a fifth of the surface; 18 of them exceed a million km². Plates move 20 to 100 mm/yr, so over 250 Myr a plate travels 5,000 to 25,000 km. A plate story that makes continents needs the whole planet: the known world is a window on it (`foundations/plates.md`, D1).
3. **Plates that pull slabs are fast; continents are slow.** Real ocean plates move a median 40 to 85 mm/yr, plates mostly of continent 22 to 30 (Müller 2019, measured here). A plate model driven by slab pull with drag on continental keels reproduces that ordering (ours: 47 to 80 and 15 to 20 since step 32, the real 40 to 79 and 19 to 36 measured the same way; 5 to 20 for continents before it).
4. **The ocean floor is young, and its age has a shape.** The mean age of today's ocean crust is 64.2 Myr (Seton et al. 2020); its area falls off roughly linearly with age to about 180 Myr (the "triangular" distribution, Parsons 1982, Cogné & Humler 2004). Its age sets its depth (GDH1) and so the sea's level: young ocean floor stands high and floods the continents, as in the Cretaceous.
5. **The reference islands sit in four settings the story must produce**: a young intra-oceanic arc whose subduction began 51–52 Ma (the Izu islands; Chichijima and Hahajima on its oldest forearc, boninites 46–48 Ma), a forearc rising 1.5–2.3 mm/yr (Kikaijima on the Ryukyu arc), continental crust in a strait between a back-arc basin and an older continent (Tsushima, sediments of 17.9–15.9 Ma folded about 15 Ma as the Japan Sea opened), and hotspot chains whose volcanoes age with distance at the plate's speed (57 km/Myr along the central Hawaiian chain).
6. **Measured the same way, our first history was close on half the figures and far on the rest.** Close: plate speeds, the largest plate's share, the slope of plate sizes, ocean depth from age, the number and size of land masses today (seed 7: 84.5, 31.4, 16.5, 6.1 million km² against 85, 42, 14, 7.7), islands of 10,000 km² to a million. Far: boundaries twice to three times as long, the oldest ocean floor surviving too long early on, continental crust shrinking where the real grows, continents too slow, too little high land, and on some seeds one plate over half the planet. Step 32's first half (2026-11-16, "Through time" below) closed the giant plate, the late breakup, most of the missing high land and the slow continents, and halved the old ocean's excess; boundaries are still two to three times too long, now because our plates are many, mid-sized and lobed.

## Sizes and rates

**Plates.** Bird's PB2002 has 52 plates: 14 large, whose motions come from NUVEL-1A, and 38 small ones, outlined by 6,048 points in 229 boundary segments; their cumulative number against area follows a power law between 0.002 and 1 steradian ([Bird 2003, G³ 4(3) 1027](https://doi.org/10.1029/2001GC000252)). At the Earth's radius that range is about 81,000 km² to 41 million km² (`zigcraft-neo-v3` notes, arithmetic). Sornette & Pisarenko 2003 read the same data as one power law cut off by the planet's size. MORVEL gives the motion of 25 plates covering 97% of the surface ([DeMets, Gordon & Argus 2010, GJI 181, 1–80](https://doi.org/10.1111/j.1365-246X.2009.04491.x)); NNR-MORVEL56 adds Bird's other 31 in a frame with no net rotation ([Argus, Gordon & DeMets 2011](https://www.eps.mcgill.ca/~courses/c350/ProbSets/Argus_2011_G3.pdf)). Measured here on Müller 2019 at half a degree: 51 plates today, 18 of them over a million km², the largest 20% of the surface, and the cumulative count falls as area to the power −0.42; 11 plates at 250 Ma, 14 at 200, 32 at 150. More plates in recent times is partly real and partly that young boundaries are better known.

**Speeds.** Area-weighted root-mean-square speed of the surface in Müller 2019's mantle frame: 44 mm/yr today, 50 to 74 between 250 and 50 Ma (measured here). That slab pull is the main driving force, and that plates attached to long slabs are fastest, is Forsyth & Uyeda 1975 (memory).

**Boundaries.** By the relative motion across them, classed the same way as ours (converging where more than half the motion closes, spreading where more than half opens, else sliding), Müller 2019 has today about 60,000 km converging, 84,000 spreading and 63,000 sliding, on the half-degree grid (measured here; a stepped raster lengthens any line by up to 4/π, and does so for both worlds). Syracuse & Abers 2006 count 839 volcanic centres along about 33,000 km of active arc ([G³](https://doi.org/10.1029/2005GC001045)), a centre every 40 km.

**Arcs.** The slab lies a global average of 105 km under the volcanic front, 72 to 173 km by arc segment (Syracuse & Abers 2006). The front lies a mean 240 km from the trench, standard deviation 62 km (Syracuse et al. 2010, as cited by Perrin et al. 2018). Arcs grow their crust by some 20 to 40 km³ for each km of arc every Myr (Reymer & Schubert 1984, memory); the Izu-Bonin arc's crust is about 20 km thick after 50 Myr (memory). Volcano spacing along arcs is fairly uniform and larger than lithospheric flexure predicts ([ten Brink 1991, via USGS](https://pubs.usgs.gov/publication/70190668)).

**The ocean floor.** Mean age 64.2 Myr today; slow (20–55 mm/yr) and fast (75–180 mm/yr) spreading made 33% and 39% of the preserved crust, intermediate 20%, ultraslow 5%, superfast 3% ([Seton et al. 2020, G³ 21](https://doi.org/10.1029/2020GC009214)). Area per unit age falls roughly linearly, C₀(1 − t/t_m), with production about 2.7–3 km²/yr and t_m about 180 Myr ([Becker et al. 2009, summarising Parsons 1982, Rowley 2002, Cogné & Humler 2004 and 2006](https://www-udc.ig.utexas.edu/external/becker/preprints/bcbm08.pdf)); Coltice et al. 2013 argue the shape is a passing state that follows ridge length. Depth from age: 2,600 + 365√t m to 20 Myr, then 5,651 − 2,473e^(−0.0278t) (GDH1, Stein & Stein 1992, memory). Today's oldest crust is about 180–200 Myr (memory); in Müller 2019's age grid 95% of the ocean floor is younger than 147 Myr (measured here).

**Continents, land and margins.** Continental crust, with its drowned margins, covers 210.4 million km², 41% of the surface, as 14 continental masses ([Cogley 1984, Rev. Geophys. 22](https://doi.org/10.1029/RG022i002p00101)); land above the sea is 29.2% ([Britannica](https://www.britannica.com/science/hypsometric-curve)), so about a third of continental crust is under the sea. The 0–200 m band covers about 5.4% of the planet, roughly the shelves (Britannica). Shelves average 88 km wide on passive margins and 31 km on active ones, slopes 46 and 36 km ([Harris et al. 2014, Marine Geology 352](https://doi.org/10.1016/j.margeo.2014.01.011)). The ocean holds about 1.335 billion km³ of water (Charette & Smith 2010, memory). In the PaleoDEMs land is 27.5% today and 22 to 37% since 250 Ma, lowest near 80 Ma (measured here).

**Islands.** Island areas follow Korčák's power law, its exponent about 0.65 and 0.5 to 0.75 by region (Mandelbrot, as cited in [arXiv 1303.1610](https://arxiv.org/pdf/1303.1610)). Depraetere's database holds 1,085 islands of 100 km² to a million (IRD record; the exponent was not reached). On the 1° PaleoDEM grid, land masses of 10,000 km² to a million number 107 today and 13 to 157 since 250 Ma (measured here).

**Cycles.** Supercontinents gather and break up every 400–600 Myr (the Wilson cycle, memory); Pangaea was whole about 300–200 Ma and the central Atlantic opened about 180 Ma (memory); India met Asia about 50 Ma (memory). In Müller 2019 the plates number 11 at 250 Ma and 51 today.

## The reference islands' settings

| Island | Setting | Dates and rates | Source |
|---|---|---|---|
| Toshima, Mikurajima, Aogashima, Kōzushima | Volcanic front of the Izu arc, an intra-oceanic arc where the Pacific plate sinks under the Philippine Sea plate | Subduction began 51–52 Ma; forearc basalts 51.9–51.3 Ma, boninites from 51.3 Ma; the forearc spreading lasted under 2 Myr | [IODP Expedition 352 prospectus](https://publications.iodp.org/scientific_prospectus/352/352sp_6.htm), [a 2021 Nature Communications paper](https://www.nature.com/articles/s41467-021-21980-0) |
| Chichijima, Hahajima | The Bonin ridge: the arc's first, Eocene forearc, now an outer high 200 km before the front | Boninites on Chichijima 46–48 Ma (Ishizuka et al. 2006), 44–45 Ma for the youngest | IODP 352 prospectus |
| Kikaijima | Forearc of the Ryukyu arc, over the subducting Amami Plateau | Rising 1.5–2.0 mm/yr over 130 kyr (Nakata et al. 1978), 2.1–2.3 over 100 kyr (Inagaki & Omura 2006), about 1.8 from the last interglacial terrace; coseismic steps of 1–2 m every 1,500–2,000 years (Sugihara et al. 2003) | [IUGS geoheritage](https://iugs-geoheritage.org/geoheritage_sites/holocene-coral-reef-terraces-of-kikaijima-island/), [CiNii](https://cir.nii.ac.jp/crid/1390001204334661504?lang=en), JpGU 2025 abstracts |
| Tsushima | Continental crust in the Korea Strait, between the Japan Sea back-arc basin and the Eurasian margin | Taishu Group deposited 17.9–15.9 Ma (SHRIMP U–Pb) in a pull-apart graben, folded and intruded by granite about 15 Ma as the Japan Sea opened and southwest Japan turned clockwise | [Curtin record of the 2014 dating](https://espace.curtin.edu.au/handle/20.500.11937/7991), [Kyoto University repository](https://repository.kulib.kyoto-u.ac.jp/dspace/bitstream/2433/265523/1/iar.12392.pdf) |
| (Hawaii, for the chains) | Hotspot under the Pacific plate | 57 ± 2 km/Myr along the central chain 57–25 Ma, faster since about 15–27 Ma; the bend began ≥47.5 Ma | [O'Connor et al. 2013, G³](https://epic.awi.de/id/eprint/35519/) |

What follows for the story *(inference)*: an intra-oceanic arc needs subduction to begin inside an ocean (old ocean floor foundering, or at a transform), not only at continents; a forearc island needs the ground between trench and front to rise, which our story does not yet do; a Tsushima needs a back-arc basin to open behind an arc on a continent's margin, leaving thinned continent in the strait; a chain's islands must age at the plate's speed and sink as the plate cools.

## What can be compared, and its licence

| Reference | What it gives through time | Span and step | Licence | Used |
|---|---|---|---|---|
| Müller et al. 2019, plate model ([EarthByte](https://www.earthbyte.org/muller-et-al-2019-deforming-plate-reconstruction-and-seafloor-age-grids-tectonics/), [paper](https://doi.org/10.1029/2018TC005462)) | Plate polygons, boundaries by type, rotations (so velocities), continental polygons, coastlines, hotspots, deforming zones | 250 Ma to today, any time | CC BY 4.0 (`License.txt` in its data folder) | Yes: plates, boundaries, speeds, continental crust |
| Its ocean-floor age grids | Age of the ocean floor at 0.1° | Every Myr, 250 Ma to today, 7.6 MB each | CC BY 4.0 | Yes, every 10 Myr |
| Scotese & Wright 2018 PaleoDEMs ([EarthByte](https://www.earthbyte.org/paleodem-resource-scotese-and-wright-2018/)) | Land and sea-floor heights at 1° | 540 Ma to today, about every 5 Myr, 8.9 MB in all | CC BY 4.0 (`License.txt`) | Yes: land, hypsometry, land masses. Its frame (PALEOMAP) is not Müller's, so it is measured, not drawn |
| Merdith et al. 2021 ([Zenodo 4320873](https://zenodo.org/records/4320873)) | Plate model to 1 Ga | 1,000 Ma to today | CC BY 4.0 | Downloaded; for a longer comparison later |
| Seton et al. 2020 age grid | Today's ocean-floor age and spreading rates | Today | Open (G³) | Its figures, quoted |
| PB2002, MORVEL | Today's plates and motions | Today | As published | Figures quoted |

The tool (`tools/plates_compare.py`) fetches these into a folder outside the repository on its first run through `plate-model-manager` and the EarthByte server. Attribution: Müller, R.D. et al. 2019, Tectonics 38, 1884–1907; Scotese, C.R. & Wright, N. 2018, PALEOMAP Paleodigital Elevation Models for the Phanerozoic. Only figures computed from them are kept here.

## How others simulate plates cheaply

- **Cortial, Peytavie, Galin & Guérin 2019, "Procedural Tectonic Planets"** ([CGF 38](https://doi.org/10.1111/cgf.13614)): crust samples on a sphere carried by rigid plates, with subduction, collision and rifting written as procedures rather than physics, and the coarse result amplified with procedural or real elevation. The user steers the plates. Its timings were not reached this session.
- **Viitanen 2012, PlaTec** ([plate-tectonics fork](https://github.com/Mindwerks/plate-tectonics), LGPL): a flat wrapped map split into plates moved across it; colliding continents fold into ranges, subducting ocean makes coastal ranges or island chains. The basis of WorldEngine.
- **Tectonics.js** ([blog](https://davidson16807.github.io/tectonics.js/blog)): a 3D sphere; plates are found by segmenting the velocity field.
- **v4 (`../odincraft-v4/src/terrain/crust.odin`)**: an Eulerian crust grid carrying area, continental and oceanic volume, age and strain per plate, with the rifting of one plate. Its record: the crust model gave the relief its cause, but walking-scale ground came from noise, and one orogenic strike ran across the world (`reference/odincraft-v4/relief-compare-findings.md`).
- **zigcraft-neo-v3's research** ranked a finite, precomputed coarse tectonic history "best large-scale history among practical graphics methods, only after a deliberate finite-world decision", and warned against shrinking plates to fit a small world (`../zigcraft-neo-v3/docs/worldgen-landmass-tectonics-research.md`).

## Through time: the real Earth and ours, measured the same way

`build/odincraft --plates=DIR` writes each frame on half-degree cells; `tools/plates_compare.py` builds the same cells for the real Earth from the references above, measures both with one function and draws them side by side. Ours here is the history as built in step 32's first half (`foundations.md` section 8), which closed what the comparison of step 22 showed far; the pictures are seed 7, the game's default, and the table eleven seeds (1 to 10 and 12), each run on its own and compared, since one seed's history is chaotic and a figure from one seed is not a figure. Run 2026-11-16.

![Today: ours (seed 7) on the left, the real Earth on the right; plates and their boundaries above (red converging, yellow spreading, white sliding), crust and land below](../real/plates-today.jpg)

![The figures through time, the real Earth solid blue, ours (seed 7) dashed orange](../real/plates-measures.jpg)

![Seed 7 at 150 Ma and today, before step 32 (left) and after (right): plates and their motion above, crust and land below. Before, one plate holds the continent and the ocean round most of the world, and the first continent is still whole at 150 Ma](../real/plates-step32-seed7.jpg)

"Ours" is the median of the eleven seeds with their range; "ours before" is the median of the same seeds with the history of step 22 as built (commit `a15e1ac`), measured again with today's script. Speeds in both worlds are now measured with the whole surface's net rotation taken out, as ours is made; this moves the real figures by a few mm/yr at most (continental plates 36, 28, 19, 30, 23, 27 against 30, 28, 22, 30, 25, 27 in the mantle frame), so Müller's frame has little net rotation.

| Figure | | 250 Ma | 200 | 150 | 100 | 50 | today |
|---|---|---|---|---|---|---|---|
| Plates | real | 11 | 14 | 32 | 36 | 35 | 51 |
| | ours | 17 (15–20) | 19 (14–25) | 22 (18–28) | 27 (23–36) | 36 (26–43) | 40 (29–52) |
| | ours before | 11 | 14 | 15 | 16 | 15 | 20 |
| Largest plate, % | real | 36 | 16 | 16 | 12 | 23 | 20 |
| | ours | 17 (11–37) | 16 (12–38) | 12 (8–27) | 13 (7–22) | 12 (10–24) | 10 (7–23) |
| | ours before | 41 | 26 | 32 | 31 | 27 | 27 |
| Plate size slope | real | −0.37 | −0.27 | −0.43 | −0.39 | −0.43 | −0.42 |
| | ours | −0.65 (−0.98–−0.32) | −0.60 (−0.68–−0.42) | −0.66 (−0.95–−0.36) | −0.63 (−1.22–−0.51) | −0.80 (−1.00–−0.53) | −0.74 (−0.96–−0.48) |
| | ours before | −0.67 | −0.59 | −0.49 | −0.47 | −0.50 | −0.58 |
| RMS speed, mm/yr | real | 73 | 59 | 67 | 64 | 50 | 44 |
| | ours | 52 (40–61) | 43 (37–60) | 46 (39–52) | 39 (32–51) | 41 (36–45) | 39 (32–46) |
| | ours before | 51 | 49 | 47 | 50 | 42 | 51 |
| Continent plates, mm/yr | real | 36 | 28 | 19 | 30 | 23 | 27 |
| | ours | 15 (11–23) | 19 (17–27) | 19 (15–23) | 19 (15–25) | 19 (13–25) | 20 (16–22) |
| | ours before | 5 | 15 | 19 | 18 | 18 | 19 |
| Converging km (thousands) | real | 66 | 51 | 70 | 67 | 65 | 60 |
| | ours | 109 (68–121) | 97 (81–188) | 123 (95–177) | 142 (129–187) | 180 (120–203) | 200 (124–217) |
| | ours before | 78 | 105 | 114 | 120 | 145 | 120 |
| Spreading km (thousands) | real | 68 | 49 | 96 | 93 | 89 | 84 |
| | ours | 105 (79–125) | 100 (72–189) | 119 (102–154) | 149 (121–178) | 178 (107–211) | 194 (138–220) |
| | ours before | 82 | 110 | 119 | 124 | 131 | 127 |
| Ocean floor, mean age Myr | real | 50 | 49 | 49 | 33 | 45 | 62 |
| | ours | 66 (49–76) | 61 (40–84) | 49 (39–56) | 53 (45–71) | 53 (46–62) | 53 (45–64) |
| | ours before | 82 | 65 | 45 | 50 | 52 | 44 |
| Ocean floor older than 120 Myr, % | real | 5 | 2 | 1 | 1 | 1 | 13 |
| | ours | 25 (14–32) | 13 (7–25) | 7 (4–12) | 8 (6–19) | 11 (7–16) | 11 (8–18) |
| | ours before | 37 | 19 | 6 | 11 | 9 | 8 |
| Continental crust, % | real | 35 | 35 | 37 | 38 | 40 | 42 |
| | ours | 38 (37–38) | 38 (37–38) | 37 (36–38) | 37 (36–38) | 37 (36–38) | 37 (35–38) |
| | ours before | 38 | 38 | 38 | 38 | 38 | 38 |
| Land, % | real | 29 | 35 | 31 | 27 | 26 | 28 |
| | ours | 36 (35–37) | 35 (33–36) | 33 (32–34) | 32 (31–34) | 31 (30–33) | 31 (29–32) |
| | ours before | 37 | 35 | 34 | 33 | 32 | 31 |
| Land over 1 km, % of the planet | real | 1.2 | 3.2 | 3.3 | 4.8 | 3.5 | 5.7 |
| | ours | 1.0 (0.8–1.5) | 1.9 (1.1–2.5) | 2.4 (1.2–3.2) | 3.3 (1.7–4.2) | 3.5 (2.3–4.7) | 4.3 (2.9–5.4) |
| | ours before | 1.0 | 0.9 | 1.1 | 1.5 | 1.7 | 1.6 |
| Land masses over a million km² | real | 1 | 1 | 4 | 8 | 7 | 6 |
| | ours | 3 (1–5) | 4 (2–8) | 6 (3–8) | 7 (3–9) | 9 (5–12) | 11 (5–17) |
| | ours before | 2 | 3 | 3 | 4 | 5 | 6 |
| Largest land mass, million km² | real | 147 | 177 | 78 | 60 | 44 | 78 |
| | ours | 172 (123–180) | 152 (90–173) | 81 (55–154) | 79 (32–152) | 53 (36–111) | 57 (26–80) |
| | ours before | 180 | 170 | 147 | 89 | 82 | 85 |
| Land masses of 10,000 km² to a million | real | 13 | 36 | 78 | 70 | 157 | 107 |
| | ours | 30 (19–47) | 59 (41–78) | 101 (71–129) | 136 (116–169) | 168 (154–213) | 233 (173–250) |
| | ours before | 30 | 48 | 83 | 99 | 132 | 149 |

What the comparison says, and what it does not:

- **One plate no longer takes half the planet.** The largest today is 7 to 23% of it over the eleven seeds (median 10%, real 20%); before, 14 to 55%, seed 7's 55%. Traced on seed 7 before: the giant grew by joins, not by spreading. Two plates of 160 million km² each "collided and joined" at 64 Ma because 800 km of their boundary had collided for 40 Myr while the rest of it went on spreading and subducting; ocean plates split off as old ocean began to sink under a continent rejoined it 40 Myr later the same way; and the first continent's two halves rejoined 46 Myr after rifting. Plates now join only where the collision holds half the boundary they share.
- **Plates: 40 today against 51, and 22 at 150 Ma against 32.** Before, 20 and 15. But too many of ours are large: 39 of them over a million km² against the real 18, the real Earth's other 33 being microplates our 36 km cells barely hold. So boundaries are longer, not shorter: converging 200 thousand km today against 60 (120 before), spreading 194 against 84. Measured plate by plate, the excess is the plates' shapes, not stray cells: a plate's outline is 2.0 to 2.2 times a circle's of its area (stepped as the grid steps it), the real plates' 1.3 to 1.5, ours before 2.5 to 2.9. Stray pieces of one plate inside another are mostly gone (on seed 3 today, 29 pieces under 60,000 km², from 304): they were floating crust, mostly arcs, carried by a plate going down at a trench, which could not sink and ploughed on into the plate over it; it is now scraped off onto that plate. The real boundaries are a little undercounted: today 6% of the real Earth lies outside every rigid plate (its deforming zones), and filling those pixels from their neighbours raises its converging boundary from 60 to 77 thousand km; at 100 and 200 Ma by under 10%.
- **The supercontinent breaks up in time.** Its largest land mass at 150 Ma is 81 million km² (55 to 154) against the real 78, from 147. Rifts no longer wander 700 km off their line over 900 km, which cut continents into interleaved fingers that collided and rejoined, and a continent breaks along the shortest line that halves it, not along any line through its middle, which cut long continents into parallel strips. Today it has broken further than the real one: 11 land masses over a million km² against 6, the largest 57 million km² against 78.
- **High land, 1.0 to 4.3% of the planet over 1 km from 250 Ma to today, against 1.2 to 5.7.** Before, 1.0 to 1.6, with no rise through time. Collisions go on longer, and thickened continent now spreads under its own weight into a belt hundreds of km wide where it stood as a wall one cell wide and lost what passed 75 km. Still under the real figure at 200 and 100 Ma (1.9 and 3.3 against 3.2 and 4.8).
- **The first ocean floor goes sooner, but not soon enough.** Older than 120 Myr: 25% at 250 Ma against 5 (37 before), 13% at 200 against 2 (19); after that 7 to 11% against 1, and 11% today against 13. Mean age at 250 Ma 66 Myr against 50 (82 before). The old floor lay in the middle of large ocean plates and on continental plates' passive margins, not behind trenches (only 7 to 9% of it at 250 Ma); which plate sinks where two ocean floors meet was right two times in three. Old ocean now founders from 110 Myr, not 140, about every 30 Myr, not 60.
- **Continents still hold level: 37 to 38% against 35 to 42.** Over the history collisions consume 55 to 59 million km² of continent and arcs make 18 to 22 (measured on seeds 7, 3 and 1), and the grid's own filling of holes adds about 16. Stronger resistance to collision (500 for 400) keeps the continents from shrinking now that collisions are not ended by joins; making arcs faster drowned the land instead (below).
- **Continental plates move: 15 mm/yr at 250 Ma against 36 (5 before), 19 to 20 after against 19 to 30.** The first continent's plates are released 20 Myr before the history begins, and the mantle drags on continent 1.5 times as hard as on ocean floor, not twice. The whole surface is slower: RMS speed 39 to 52 mm/yr against 44 to 73 (42 to 51 before), today 39 against 44.
- **Too many small land masses**: 233 of 10,000 km² to a million today against 107 (149 before), as continents break further and arcs build more.
- **Close as before**: ocean depth from age, land's share (31% today against 28%), the sea's level.
- **Real land is the PaleoDEMs'** in another reconstruction's frame; it measures the land and its heights but is not drawn on Müller's plates. The real map's green is today's coastlines carried back, which is not the land of the time.
- The real model's plate count rises toward today partly because recent plates are better known *(inference)*; our count is the history's own.

How the table was made: for each seed, `build/odincraft --seed=N --plates=DIR` and `tools/plates_compare.py DIR DATA OUT`; then `tools/plates_compare.py --summary OUT... --before OUT...` over the eleven seeds' outputs. "Ours before" is commit `a15e1ac`.

## Not verified

- Forsyth & Uyeda 1975, Reymer & Schubert 1984, GDH1's constants, Charette & Smith's ocean volume, the Wilson cycle's length, Pangaea's dates and the Izu arc's crustal thickness are from memory.
- Cortial et al.'s timings, Depraetere's exponent and MORVEL's global speed were not reached.
- Kikaijima's rates and Tsushima's dates come from abstracts and repository records, not the papers.
- The comparison's boundary lengths are raster lengths on a half-degree grid, lengthened by up to 4/π for both worlds alike; its velocities are each plate's motion over the Myr before the frame (after it, at 250 Ma, where the model begins).
