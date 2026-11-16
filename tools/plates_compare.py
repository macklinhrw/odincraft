#!/usr/bin/env python3
"""Measure the world's plate history against the real Earth's through time, and draw both.

    build/odincraft --plates=OURS
    python tools/plates_compare.py OURS DATA OUT
    python tools/plates_compare.py --summary OUT... [--before OUT...]

The second form prints, as a Markdown table, the median and range over several seeds' OUT folders
(each one seed's run of the first form) beside the real Earth's figures, with the median of another
set as "ours before" when one is given: one seed's history is chaotic, and a figure from one seed is
not a figure.

OURS holds the frame-NNN.raw grids --plates writes. DATA is where the real reference is fetched on
the first run, outside the repository: the plate model of Müller et al. 2019 (Tectonics 38, 1884-1907)
with its ocean-floor age grids, and the PALEOMAP PaleoDEMs of Scotese & Wright 2018, all under CC BY
4.0 (docs/interesting-world/notes/real-plates.md). OUT gets measures.csv, a sheet for each frame
(sheet-NNN.jpg: ours on the left, the real Earth on the right, the figures beside them) and
measures.png, the figures through time. The same code measures both, on the same half-degree grid.

Needs pygplates, plate-model-manager, numpy, netCDF4, Pillow and matplotlib.
"""
import csv, glob, math, os, re, sys, urllib.request, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 360                       # half-degree cells, from the north pole and the date line
R = 6371.0
LAT = 90 - (np.arange(H) + 0.5) * 0.5
LON = (np.arange(W) + 0.5) * 0.5 - 180
CELL = (math.radians(0.5) * R) ** 2 * np.cos(np.radians(LAT))[:, None] * np.ones((1, W))   # km²
TIMES = list(range(250, -1, -10))
AGES = "https://www.earthbyte.org/webdav/ftp/Data_Collections/Muller_etal_2019_Tectonics/Muller_etal_2019_Agegrids/Muller_etal_2019_Tectonics_v2.0_netCDF/Muller_etal_2019_Tectonics_v2.0_AgeGrid-{}.nc"
DEMS = "https://www.earthbyte.org/webdav/ftp/Data_Collections/Scotese_Wright_2018_PaleoDEM/Scotese_Wright_2018_Maps_1-88_1degX1deg_PaleoDEMS_nc.zip"


def fetch(url, path):
    """Download url to path. EarthByte refuses urllib's own user agent (403), so the tool names itself."""
    request = urllib.request.Request(url, headers={"User-Agent": "odincraft-plates-compare"})
    with urllib.request.urlopen(request) as response, open(path + ".part", "wb") as out:
        while block := response.read(1 << 20):
            out.write(block)
    os.replace(path + ".part", path)


def ours(folder, t):
    """Our frame t Myr ago, as the grids the measures read."""
    raw = np.fromfile(os.path.join(folder, "frame-%03d.raw" % t), dtype=np.uint8).reshape(H, W, 9)
    s16 = lambda k: raw[:, :, k:k + 2].copy().view("<i2")[:, :, 0].astype(float)
    kind = raw[:, :, 1]
    return dict(plate=raw[:, :, 0].astype(int), cont=kind == 1, arc=kind == 2, age=raw[:, :, 2].astype(float),
                height=s16(3), ve=s16(5), vn=s16(7), land=s16(3) > 0)


class Real:
    """The real Earth at a time: Müller et al. 2019's plates, continents and ocean floor's ages, and the
    land of the PaleoDEMs (in their own frame, so used for figures, not drawn)."""

    def __init__(self, data):
        import pygplates
        from plate_model_manager import PlateModelManager
        self.pg = pygplates
        model = PlateModelManager().get_model("muller2019", data_dir=os.path.join(data, "models"))
        self.rotations = pygplates.RotationModel(model.get_rotation_model())
        self.topologies = [pygplates.FeatureCollection(f) for f in model.get_layer("Topologies")]
        self.continents = [pygplates.FeatureCollection(f) for f in model.get_layer("ContinentalPolygons")]
        self.coasts = [pygplates.FeatureCollection(f) for f in model.get_layer("Coastlines")]
        self.hotspots = [pygplates.FeatureCollection(f) for f in model.get_layer("Hotspots")]
        self.data = data
        dems = os.path.join(data, "paleodem")
        if not glob.glob(os.path.join(dems, "**", "*.nc"), recursive=True):
            os.makedirs(dems, exist_ok=True)
            path = os.path.join(dems, "dems.zip")
            fetch(DEMS, path)
            zipfile.ZipFile(path).extractall(dems)
        found = [(re.search(r"_([0-9.]+)Ma\.nc$", f), f) for f in glob.glob(os.path.join(dems, "**", "*Ma.nc"), recursive=True)]
        self.dems = {float(m.group(1)): f for m, f in found if m}

    def fill(self, geometries, values):
        """Rasterise polygons on the sphere, each to its value, on the half-degree grid."""
        image = Image.new("I", (W, H), 0)
        draw = ImageDraw.Draw(image)
        wrapper = self.pg.DateLineWrapper(0.0)
        for geometry, value in zip(geometries, values):
            for part in wrapper.wrap(geometry, 1.0):
                points = [((p.get_longitude() + 180) * 2, (90 - p.get_latitude()) * 2) for p in part.get_exterior_points()]
                if len(points) > 2:
                    draw.polygon(points, fill=int(value))
        return np.array(image, dtype=np.int64)

    def at(self, t):
        pg = self.pg
        resolved = []
        pg.resolve_topologies(self.topologies, self.rotations, resolved, float(t))
        rigid = [r for r in resolved if isinstance(r, pg.ResolvedTopologicalBoundary)]
        rigid.sort(key=lambda r: -r.get_resolved_boundary().get_area())
        ids = [r.get_feature().get_reconstruction_plate_id() for r in rigid]
        plate = self.fill([r.get_resolved_boundary() for r in rigid], range(1, len(rigid) + 1))
        # Each plate's motion from a Myr before, in the mantle frame (taken out in main).
        x = np.stack([np.cos(np.radians(LAT))[:, None] * np.cos(np.radians(LON))[None, :],
                      np.cos(np.radians(LAT))[:, None] * np.sin(np.radians(LON))[None, :],
                      np.sin(np.radians(LAT))[:, None] * np.ones((1, W))], -1)
        spin = np.zeros((len(rigid) + 1, 3))
        for k, pid in enumerate(ids, 1):
            before, after = (float(t) + 1, float(t)) if t < 250 else (float(t), float(t) - 1)   # the model starts at 250 Ma
            pole, angle = self.rotations.get_rotation(after, pid, before).get_euler_pole_and_angle()
            spin[k] = np.array(pole.to_xyz()) * angle
        v = np.cross(spin[plate], x) * R
        east = np.stack([-np.sin(np.radians(LON))[None, :] * np.ones((H, 1)), np.cos(np.radians(LON))[None, :] * np.ones((H, 1)), np.zeros((H, W))], -1)
        north = np.cross(x, east)
        def reconstructed(collections):
            out = []
            pg.reconstruct(collections, self.rotations, out, float(t))
            return [r.get_reconstructed_geometry() for r in out if isinstance(r.get_reconstructed_geometry(), pg.PolygonOnSphere)]
        cont = self.fill(reconstructed(self.continents), [1] * 100000) > 0
        coast = self.fill(reconstructed(self.coasts), [1] * 100000) > 0
        path = os.path.join(self.data, "ages", "age-%d.nc" % t)
        if not os.path.exists(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            fetch(AGES.format(t), path)
        import netCDF4
        grid = netCDF4.Dataset(path)
        z = np.array(grid.variables["z"][:], dtype=float)
        z[np.abs(z) > 1e5] = np.nan
        glat, glon = np.array(grid.variables["lat"][:]), np.array(grid.variables["lon"][:])
        i = np.clip(np.round((LAT - glat[0]) / (glat[1] - glat[0])).astype(int), 0, len(glat) - 1)
        j = np.clip(np.round((LON - glon[0]) / (glon[1] - glon[0])).astype(int), 0, len(glon) - 1)
        age = z[i][:, j]
        dem = netCDF4.Dataset(self.dems[min(self.dems, key=lambda k: abs(k - t))])
        height = np.array(dem.variables["z"][:], dtype=float)   # 1° nodes from -90 and -180
        hotspots = []
        for collection in self.hotspots:
            for feature in collection:
                for g in feature.get_geometries():
                    for p in (g.get_points() if hasattr(g, "get_points") else [g]):
                        hotspots.append(p.to_lat_lon())
        return dict(plate=plate, cont=cont, arc=np.zeros((H, W), bool), age=np.where(np.isnan(age), 255, age),
                    ve=(v * east).sum(-1), vn=(v * north).sum(-1), land=coast, dem=height, hotspots=hotspots)


def without_net_rotation(g):
    """The motion with the whole surface's net rotation taken out: the turning that best fits every
    cell's motion, weighted by area. Ours has none by construction; the real Earth's mantle frame has
    some, so both are measured in the same frame."""
    lat, lon = np.radians(LAT)[:, None] * np.ones((1, W)), np.radians(LON)[None, :] * np.ones((H, 1))
    x = np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)], -1)
    east = np.stack([-np.sin(lon), np.cos(lon), np.zeros_like(lon)], -1)
    north = np.cross(x, east)
    v = g["ve"][:, :, None] * east + g["vn"][:, :, None] * north
    weight = CELL * (g["plate"] > 0) if "dem" in g else CELL   # the real Earth's cells outside every plate's outline move with none
    net = np.linalg.solve((weight[:, :, None, None] * (np.eye(3) - x[:, :, :, None] * x[:, :, None, :])).sum((0, 1)), (weight[:, :, None] * np.cross(x, v)).sum((0, 1)))
    v = v - np.cross(net, x)
    return dict(g, ve=(v * east).sum(-1), vn=(v * north).sum(-1))


def ocean_depth(age):   # GDH1, Stein & Stein 1992
    a = np.maximum(age, 0)
    return np.where(a < 20, 2600 + 365 * np.sqrt(a), 5651 - 2473 * np.exp(-0.0278 * a))


def masses(land):
    """Areas of land masses on a 1° grid, joined across the date line."""
    h, w = land.shape
    area = (math.radians(1) * R) ** 2 * np.cos(np.radians(90 - (np.arange(h) + 0.5)))
    seen = np.zeros_like(land, bool)
    out = []
    for y0 in range(h):
        for x0 in range(w):
            if not land[y0, x0] or seen[y0, x0]:
                continue
            total, stack = 0.0, [(y0, x0)]
            seen[y0, x0] = True
            while stack:
                y, x = stack.pop()
                total += area[y]
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, (x + dx) % w
                    if 0 <= ny < h and land[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            out.append(total)
    return sorted(out, reverse=True)


def boundaries(g):
    """Lengths of boundary, km, converging, spreading and sliding, from how the plates move across it."""
    out = np.zeros(4)
    edge_ns = math.radians(0.5) * R
    for axis, edge in ((1, edge_ns * np.cos(np.radians(LAT))[:, None]), (0, edge_ns * np.ones((H, 1)))):
        if axis == 1:
            a, b = g["plate"], np.roll(g["plate"], -1, 1)
            rel = (g["ve"] - np.roll(g["ve"], -1, 1), g["vn"] - np.roll(g["vn"], -1, 1))
            closing = rel[0]          # toward the east neighbour
            length = np.broadcast_to(edge_ns, (H, W))
        else:
            a, b = g["plate"][:-1], g["plate"][1:]
            rel = (g["ve"][:-1] - g["ve"][1:], g["vn"][:-1] - g["vn"][1:])
            closing = -rel[1]         # toward the south neighbour
            length = np.broadcast_to(edge_ns * np.cos(np.radians(LAT[:-1] - 0.25))[:, None], a.shape)
        speed = np.hypot(*rel)
        differ = (a != b) & (a > 0) & (b > 0)
        kind = np.where(speed < 3, 0, np.where(closing > 0.5 * speed, 1, np.where(closing < -0.5 * speed, 2, 3)))
        for k in (1, 2, 3):
            out[k] += length[differ & (kind == k)].sum()
    return out[1:]


def measure(g, dem=None):
    m = {}
    whole = CELL.sum()
    speed = np.hypot(g["ve"], g["vn"])
    plates = []
    for pid in np.unique(g["plate"]):
        if pid == 0 and "dem" in g:
            continue
        mask = g["plate"] == pid
        area = CELL[mask].sum()
        plates.append((area, (CELL[mask] * speed[mask]).sum() / area, CELL[mask & g["cont"]].sum() / area))
    areas = np.array(sorted(p[0] for p in plates))[::-1]
    m["plates"] = len(areas)
    m["plates over 1 Mkm²"] = int((areas >= 1e6).sum())
    m["largest plate %"] = 100 * areas[0] / whole
    big = areas[(areas >= 1e5)]
    m["plate size slope"] = np.polyfit(np.log10(big), np.log10(np.arange(1, len(big) + 1)), 1)[0] if len(big) > 3 else float("nan")
    m["rms speed mm/yr"] = math.sqrt((CELL * speed ** 2).sum() / whole)
    oceanic = [p[1] for p in plates if p[2] < 0.2 and p[0] > 1e6]
    continental = [p[1] for p in plates if p[2] >= 0.5 and p[0] > 1e6]
    m["ocean plates mm/yr"] = float(np.median(oceanic)) if oceanic else float("nan")
    m["continent plates mm/yr"] = float(np.median(continental)) if continental else float("nan")
    conv, div, slide = boundaries(g)
    m["converging km"], m["spreading km"], m["sliding km"] = conv, div, slide
    ocean = (~g["cont"]) & (g["age"] < 255)
    a = g["age"][ocean]
    w = CELL[ocean]
    m["ocean mean age Myr"] = (a * w).sum() / w.sum()
    order = np.argsort(a)
    m["ocean age 95% Myr"] = a[order][np.searchsorted(np.cumsum(w[order]), 0.95 * w.sum())]
    for lo, hi in ((0, 30), (30, 60), (60, 120), (120, 999)):
        m["ocean %d-%s Myr %%" % (lo, hi if hi < 999 else "")] = 100 * w[(a >= lo) & (a < hi)].sum() / w.sum()
    m["ocean depth from age m"] = (ocean_depth(a) * w).sum() / w.sum()
    m["continental crust %"] = 100 * CELL[g["cont"]].sum() / whole
    # Land on 1° cells: ours from its heights, the real Earth's from the PaleoDEM.
    if dem is not None:
        height = dem[:-1, :-1][::-1]   # nodes from -90 to 89, -180 to 179, turned north up
    else:
        height = g["height"].reshape(180, 2, 360, 2).mean((1, 3))
    lat1 = 90 - (np.arange(180) + 0.5)
    cell1 = np.cos(np.radians(lat1))[:, None] * np.ones((1, 360))
    land = height > 0
    m["land %"] = 100 * cell1[land].sum() / cell1.sum()
    m["land over 1 km %"] = 100 * cell1[height > 1000].sum() / cell1.sum()
    m["median land m"] = float(np.median(height[land])) if land.any() else float("nan")
    m["median sea floor m"] = float(np.median(height[~land]))
    sizes = masses(land)
    m["land masses over 1 Mkm²"] = sum(1 for s in sizes if s >= 1e6)
    m["largest land Mkm²"] = sizes[0] / 1e6 if sizes else 0
    m["islands 10k-1M km²"] = sum(1 for s in sizes if 1e4 <= s < 1e6)
    return m


def colour_plate(pid):
    a = pid * 2.39996
    return np.stack([0.62 + 0.25 * np.cos(a), 0.62 + 0.25 * np.cos(a - 2.1), 0.62 + 0.25 * np.cos(a + 2.1)], -1)


def draw(g, real):
    """The two maps of a world at a time, as --plates draws ours: plates and boundaries; crust and land."""
    top = colour_plate(g["plate"].astype(float)) * np.where(g["cont"], 0.72, 1.0)[:, :, None]
    if real:
        top[g["plate"] == 0] = 0.35
    rel_e = g["ve"] - np.roll(g["ve"], -1, 1)
    rel_n = g["vn"] - np.roll(g["vn"], 1, 0)
    for a, b, closing, rel in ((g["plate"], np.roll(g["plate"], -1, 1), rel_e, np.hypot(rel_e, g["vn"] - np.roll(g["vn"], -1, 1))),
                               (g["plate"], np.roll(g["plate"], -1, 0), -(g["vn"] - np.roll(g["vn"], -1, 0)), np.hypot(g["ve"] - np.roll(g["ve"], -1, 0), g["vn"] - np.roll(g["vn"], -1, 0)))):
        edge = a != b
        kind = np.where(rel < 3, 0, np.where(closing > 0.5 * rel, 1, np.where(closing < -0.5 * rel, 2, 3)))
        for k, c in ((0, (0.3, 0.3, 0.3)), (1, (0.85, 0.1, 0.1)), (2, (1, 0.85, 0.1)), (3, (1, 1, 1))):
            top[edge & (kind == k)] = c
    low = np.sqrt(np.clip(g["age"] / 180, 0, 1))[:, :, None]
    bottom = np.array([0.55, 0.78, 0.95]) * (1 - low) + np.array([0.04, 0.12, 0.38]) * low
    bottom[g["cont"]] = (0.55, 0.68, 0.74)
    bottom[g["arc"]] = bottom[g["arc"]] * 0.4 + np.array([0.55, 0.35, 0.75]) * 0.6
    bottom[g["land"]] = (0.36, 0.56, 0.26)
    image = np.concatenate([top, bottom], 0)
    return Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8))


def main():
    ours_dir, data, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    real = Real(data)
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 15)
    bold = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 17)
    rows = []
    for t in TIMES:
        g, r = without_net_rotation(ours(ours_dir, t)), without_net_rotation(real.at(t))
        mo, mr = measure(g), measure(r, r["dem"])
        rows += [dict(myr_ago=t, world="ours", **mo), dict(myr_ago=t, world="real", **mr)]
        sheet = Image.new("RGB", (2 * W + 440, 2 * H + 40), (252, 252, 251))
        sheet.paste(draw(g, False), (0, 40))
        sheet.paste(draw(r, True), (W, 40))
        d = ImageDraw.Draw(sheet)
        d.text((10, 10), "Ours, %d Myr ago" % t, fill=(11, 11, 11), font=bold)
        d.text((W + 10, 10), "The real Earth, %d Ma (Müller et al. 2019)" % t, fill=(11, 11, 11), font=bold)
        x0 = 2 * W + 16
        d.text((x0, 10), "figure", fill=(82, 81, 78), font=bold)
        d.text((x0 + 250, 10), "ours", fill=(82, 81, 78), font=bold)
        d.text((x0 + 340, 10), "real", fill=(82, 81, 78), font=bold)
        for i, k in enumerate(mo):
            y = 44 + i * 23
            fmt = (lambda v: "%.0f" % v if abs(v) >= 100 else "%.1f" % v if abs(v) >= 1 else "%.2f" % v)
            d.text((x0, y), k, fill=(11, 11, 11), font=font)
            d.text((x0 + 250, y), fmt(mo[k]), fill=(11, 11, 11), font=font)
            d.text((x0 + 340, y), fmt(mr[k]), fill=(11, 11, 11), font=font)
        d.text((x0, 2 * H + 10), "Real land is today's coast carried back; its figures are the PaleoDEMs'.", fill=(82, 81, 78), font=font)
        sheet.save(os.path.join(out, "sheet-%03d.jpg" % t), quality=88)
        print("frame", t, "done")
    keys = list(rows[0].keys())
    with open(os.path.join(out, "measures.csv"), "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)
    chart(rows, os.path.join(out, "measures.png"))


def chart(rows, path):
    """The figures through time, ours against the real Earth's, one small chart each."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    keys = ["plates", "largest plate %", "rms speed mm/yr", "converging km", "spreading km", "sliding km",
            "ocean mean age Myr", "ocean age 95% Myr", "ocean depth from age m", "continental crust %", "land %", "islands 10k-1M km²"]
    fig, axes = plt.subplots(3, 4, figsize=(16, 10), facecolor="#fcfcfb")
    for ax, k in zip(axes.flat, keys):
        for world, colour, style in (("real", "#2a78d6", "-"), ("ours", "#eb6834", "--")):
            pts = [(r["myr_ago"], r[k]) for r in rows if r["world"] == world]
            ax.plot([p[0] for p in pts], [p[1] for p in pts], style, color=colour, linewidth=2, label="real Earth" if world == "real" else "ours")
        ax.set_title(k, fontsize=11, color="#0b0b0b", loc="left")
        ax.invert_xaxis()
        ax.set_facecolor("#fcfcfb")
        ax.grid(True, color="#e1e0d9", linewidth=0.6)
        for side in ("top", "right"):
            ax.spines[side].set_visible(False)
        for side in ("left", "bottom"):
            ax.spines[side].set_color("#c3c2b7")
        ax.tick_params(colors="#898781", labelsize=9)
        ax.set_ylim(bottom=0)
    axes.flat[0].legend(frameon=False, fontsize=10)
    fig.supxlabel("Myr ago", color="#52514e")
    fig.tight_layout()
    fig.savefig(path, dpi=110)


SUMMARY = [("Plates", "plates", 1, "%d"), ("Largest plate, %", "largest plate %", 1, "%d"), ("Plate size slope", "plate size slope", 1, "%.2f"),
           ("RMS speed, mm/yr", "rms speed mm/yr", 1, "%d"), ("Continent plates, mm/yr", "continent plates mm/yr", 1, "%d"),
           ("Converging km (thousands)", "converging km", 1000, "%d"), ("Spreading km (thousands)", "spreading km", 1000, "%d"),
           ("Ocean floor, mean age Myr", "ocean mean age Myr", 1, "%d"), ("Ocean floor older than 120 Myr, %", "ocean 120- Myr %", 1, "%d"),
           ("Continental crust, %", "continental crust %", 1, "%d"), ("Land, %", "land %", 1, "%d"), ("Land over 1 km, % of the planet", "land over 1 km %", 1, "%.1f"),
           ("Land masses over a million km²", "land masses over 1 Mkm²", 1, "%d"), ("Largest land mass, million km²", "largest land Mkm²", 1, "%d"),
           ("Land masses of 10,000 km² to a million", "islands 10k-1M km²", 1, "%d")]


def summary(args):
    """The median and range over several seeds' measures.csv, beside the real Earth's, as Markdown."""
    import statistics
    now, before = (args[:args.index("--before")], args[args.index("--before") + 1:]) if "--before" in args else (args, [])
    load = lambda d: {(int(float(r["myr_ago"])), r["world"]): r for r in csv.DictReader(open(os.path.join(d, "measures.csv")))}
    runs, olds = [load(d) for d in now], [load(d) for d in before]
    times = [250, 200, 150, 100, 50, 0]
    show = lambda fmt, x: "{:,}".format(int(round(x))) if fmt == "%d" else (fmt % x).replace("-", "−")
    print("| Figure | | 250 Ma | 200 | 150 | 100 | 50 | today |\n|---|---|---|---|---|---|---|---|")
    for name, k, div, fmt in SUMMARY:
        values = lambda sets, t: [float(s[(t, "ours")][k]) / div for s in sets if not math.isnan(float(s[(t, "ours")][k]))]
        print("| %s | real | %s |" % (name, " | ".join(show(fmt, float(runs[0][(t, "real")][k]) / div) for t in times)))
        cells = [(lambda xs: "%s (%s–%s)" % (show(fmt, statistics.median(xs)), show(fmt, min(xs)), show(fmt, max(xs))) if xs else "–")(values(runs, t)) for t in times]
        print("| | ours | %s |" % " | ".join(cells))
        if olds:
            print("| | ours before | %s |" % " | ".join(show(fmt, statistics.median(values(olds, t))) for t in times))


if __name__ == "__main__":
    summary(sys.argv[2:]) if sys.argv[1:2] == ["--summary"] else main()
