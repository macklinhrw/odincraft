#include <metal_stdlib>
using namespace metal;

// Every position in here is relative to the camera, so precision does not depend on where
// in the world the player stands.

struct Frame {
    float4x4 view_proj;
    float4x4 shadow_vp[4];
    float4 cascade_r;   // radius of each shadow cascade, metres
    float4 sun;         // xyz: direction to the sun, w: seconds
    float4 cam;         // xyz: camera world position (x and z wrapped), w: sea level
    float4 target;      // xyz: aimed block, camera-relative, w: 1 when there is one
    float4 cam_r;       // camera right * tan(half horizontal fov)
    float4 cam_u;       // camera up * tan(half vertical fov)
    float4 cam_f;       // camera forward
    float4 screen;      // xy: size in pixels
    float4 cloud;       // xy: camera in the drifting cloud field, zw: camera from the region's corner
    float4 weather;     // x: cover 0..1, y: cloud base, z: depth of the deck, w: region size, metres
    float4 focus;       // xyz: the point the shadows and the ground plants are centred on, from the eye; w: 1 in the view from above
    float4 cut;         // x: the level above which nothing is drawn, from the eye (far above everything for none); y: 1 where leaves are not drawn
    float4 mark;        // xyz: the low corner of the marked box of blocks, from the eye; w: 1 when there is one
    float4 mark_size;   // xyz: its size in blocks
    float4 lens;        // xy: the eye from the corner of the island a lens is painted over, z: one over that island's side, w: 1 while a lens is on (play.odin)
    float4 marked;      // xyz: the eye from the low corner of the map of marked blocks, w: 1 while anything is on it (bar.odin)
    float4 tint[48];    // boxes of ground over a mark (bar.odin): xyz the low corner from the eye; w: 0 none, 5 the ground over what is being dragged, 6 over what is marked
    float4 tint_size[48];
    float4 live;        // the interface's brass and its cinnabar, lit
    float4 wrong;
    float4 rain;        // x: how hard rain falls over the view, 0 to 1, under 0 for snow; y: how wet the ground is; z: how far the wind leans it; w: seconds, for it to fall by
    float4 kinds[4];    // the colours of ground marked to sleep on, of ground under a roof and of ground indoors, lit (bar.odin)
    float4 fire[8];     // the fires that burn: xyz from the eye, w: how far its light reaches, 0 for none (shelter_view.odin)
};

struct Draw { float4 origin; };   // xyz: chunk origin, w: cell size in metres

constant float SHADOW_RES = 2048.0;
constant float LEAF_FAR = 72.0;   // as in render.odin
constant float DARK = 150.0;      // metres under the sea past which the ground is black (fs_terrain); as in render.odin
constant float EARTH = 7.4e6;     // metres: the Earth's radius lengthened for ordinary refraction, the surveyors' figure; as in render.odin

// Where a point at `rel` from the eye is drawn on a round world: lower by the square of its distance
// over twice the radius, 15 m at 15 km and 280 m at 64 km, so the sea has a horizon and far land sinks
// under it. Only where things are drawn changes: every shader lights, shades, textures and hazes
// them where they stand on the flat world, so the shadow maps are drawn flat and nothing near moves.
static float4 drawn(float3 rel, constant Frame &f) {
    return f.view_proj * float4(rel.x, rel.y - dot(rel.xz, rel.xz) / (2.0 * EARTH), rel.z, 1.0);
}

constant float3 FACE_N[6] = { float3(1,0,0), float3(-1,0,0), float3(0,1,0), float3(0,-1,0), float3(0,0,1), float3(0,0,-1) };
constant float3 FACE_U[6] = { float3(0,1,0), float3(0,0,1), float3(0,0,1), float3(1,0,0), float3(1,0,0), float3(0,1,0) };
constant float3 FACE_V[6] = { float3(0,0,1), float3(0,1,0), float3(1,0,0), float3(0,0,1), float3(0,1,0), float3(1,0,0) };

// ---- shared -----------------------------------------------------------------------------

static float hash21(float2 p) {
    float3 q = fract(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

static float vnoise(float2 p) {
    float2 i = floor(p), t = fract(p);
    t = t * t * (3.0 - 2.0 * t);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), t.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), t.x), t.y);
}

static float daylight(float3 sun) { return smoothstep(-0.12, 0.2, sun.y); }

// How much of the sun's own light comes through: under rain the land is lit by its sky alone.
static float through_rain(constant Frame &f) { return 1.0 - 0.85 * saturate(f.kinds[3].x * 2.5); }

// The light of the fires on a face: warm, falling away to nothing at each fire's reach, and all
// but drowned by the day.
static float3 fire_glow(float3 rel, float3 N, constant Frame &f) {
    float3 sum = float3(0.0);
    for (int i = 0; i < 8; i++) {
        float4 fire = f.fire[i];
        if (fire.w <= 0.0) break;
        float3 d = fire.xyz - rel;
        float far = length(d);
        if (far >= fire.w) continue;
        float fall = 1.0 - far / fire.w;
        float flicker = 0.86 + 0.14 * sin(f.sun.w * 9.0 + float(i) * 2.3) * sin(f.sun.w * 5.3 + 1.7);
        sum += float3(1.0, 0.52, 0.2) * (fall * fall * (0.3 + 0.7 * saturate(dot(N, d / max(far, 0.01)))) * flicker);
    }
    return sum * (1.5 - 1.25 * daylight(f.sun.xyz));
}

static float3 sun_light(float3 sun) {
    float3 c = mix(float3(1.0, 0.42, 0.18), float3(1.0, 0.95, 0.88), smoothstep(0.0, 0.4, sun.y));
    return c * 1.7 * smoothstep(-0.04, 0.12, sun.y);
}

// Sky radiance in direction d. Directions below the horizon return the horizon, which is
// also what distant terrain fades into. Under cloud it greys.
static float3 sky_color(float3 d, float3 sun, float cover) {
    float day = daylight(sun);
    float3 zenith = mix(float3(0.004, 0.006, 0.016), float3(0.09, 0.24, 0.60), day);
    float3 warm = mix(float3(0.85, 0.42, 0.22), float3(0.44, 0.60, 0.84), smoothstep(-0.02, 0.38, sun.y));
    float3 horizon = mix(float3(0.012, 0.018, 0.035), warm, day);
    float up = saturate(d.y);
    float3 c = mix(horizon, zenith, 1.0 - pow(1.0 - up, 4.0));
    float toward = saturate(dot(normalize(float3(d.x, up, d.z)), sun));
    c += sun_light(sun) * (0.05 * pow(toward, 6.0) + 0.25 * pow(toward, 96.0));
    return mix(c, dot(c, float3(0.3, 0.5, 0.2)) * float3(1.0, 1.03, 1.08), 0.6 * cover);
}

static float3 sky_ambient(float3 N, float3 sun, float cover) {
    float day = daylight(sun);
    // At night the land is lit as by a full moon, far brighter than a true one against the day: a hold
    // is kept through the night, and the player must see it (plan.md, P4). RimWorld's night keeps about
    // a third of the day's light.
    float3 sky = mix(float3(0.18, 0.22, 0.32), mix(float3(0.44, 0.55, 0.76), float3(0.62, 0.64, 0.68), cover), day);
    float3 ground = mix(float3(0.07, 0.085, 0.12), float3(0.27, 0.25, 0.20), day);
    return mix(ground, sky, N.y * 0.5 + 0.5);
}

// Haze that thins with altitude, integrated along the view ray: how much of the sky's colour
// there is in what lies at `rel`. Past a few kilometres it thickens more slowly than near by, as
// if the air out over the sea were clearer than the island's own (CLEAR), so land 30 to 60 km off
// still shows its skyline on a clear day; within 2 km it is as it was.
constant float CLEAR = 10000.0;
static float haze(float3 rel, constant Frame &f) {
    float dist = length(rel);
    float falloff = 0.0011;
    float t = falloff * rel.y;
    float through = abs(t) < 1e-3 ? 1.0 : (1.0 - exp(-t)) / t;
    return 1.0 - exp(-0.00006 * exp(-falloff * max(f.cam.y - f.cam.w, 0.0)) * CLEAR * log(1.0 + dist / CLEAR) * through);
}

// ---- clouds -------------------------------------------------------------------------------

// How far the cloud over a point stands above the cloud base, in metres, 0 where there is none.
// The deck is noise drifting on the wind over as much of the sky as the weather's cover. The cap
// is where the wind off the sea has been lifted past the cloud base by the ground it crossed.
static float cloud_top(float2 rel, constant Frame &f, texture2d<float> lifted, sampler smp, float fine) {
    float2 q = (rel + f.cloud.xy) / 1200.0;
    float c = f.weather.x - 0.5;   // the noise passes this level over a share `cover` of the sky
    float level = 0.5 - 0.36 * c - 0.5 * c * c * c - 0.3 * smoothstep(0.9, 1.0, f.weather.x) + 0.5 * (1.0 - smoothstep(0.0, 0.03, f.weather.x));
    float rise = lifted.sample(smp, (rel + f.cloud.zw) / f.weather.w).r - f.weather.y;
    // Where no cap can stand, the deck is all there is, and where the noise stays under its level
    // even if every octave still to come added all it could, there is none: those octaves are not
    // worked out. Most of the steps through a fair sky end here.
    float more = fine > 0.0 ? 0.125 * fine : 0.0;   // the most the fine octaves can add
    bool deck_only = rise <= -30.0;
    float n = 0.5 * vnoise(q);
    if (deck_only && n + 0.25 + 0.125 + more <= level) return 0.0;
    n += 0.25 * vnoise(q * 2.03 + 7.1);
    if (deck_only && n + 0.125 + more <= level) return 0.0;
    n += (fine > 0.0 ? fine * (0.15 * vnoise(q * 4.1 + 3.7) + 0.1 * vnoise(q * 8.3 + 1.3) - 0.125) : 0.0) + 0.125;   // the fine octaves fade out with distance, where steps would alias them
    return max(f.weather.z * smoothstep(0.0, 0.35, n - level), saturate((rise + 30.0) / 60.0) * (rise + 150.0) * (0.5 + n));
}

// The share of the sun's light that reaches a point through the cloud over where its ray
// crosses the deck.
static float cloud_shade(float3 rel, constant Frame &f, texture2d<float> lifted, sampler smp) {
    if (f.focus.w > 0.5) return 1.0;   // from above the clouds are not drawn, and a shade with nothing to cast it reads as a stain on the ground
    float up = max(f.weather.y + 100.0 - f.cam.y - rel.y, 0.0) / max(f.sun.y, 0.05);
    return 1.0 - 0.85 * smoothstep(0.0, 60.0, cloud_top(rel.xz + f.sun.xz * up, f, lifted, smp, 0.0));
}

// Where a ray from the camera enters and leaves the layer the clouds can fill, 0 and 0 if it never does.
// The layer is round as the world is (drawn): a ray's height over the eye's level is a t² + b t, the
// bend lifting it off the layer as it goes, so a ray along the horizon meets the cloud base at last.
static float2 cloud_span(float3 rd, constant Frame &f) {
    float lo = f.weather.y - f.cam.y, hi = lo + 300.0;
    float a = max(dot(rd.xz, rd.xz), 1e-6) / (2.0 * EARTH), b = rd.y;
    float dlo = b * b + 4.0 * a * lo, dhi = b * b + 4.0 * a * hi;   // under 0 where the ray never comes down to that height
    float t0 = 0.0, t1;
    if (lo > 0.0) {   // from under the layer, rising into it
        t0 = 2.0 * lo / (b + sqrt(dlo));
        t1 = 2.0 * hi / (b + sqrt(dhi));
    } else {
        if (hi < 0.0) {   // from over it, coming down into it
            if (b >= 0.0 || dhi < 0.0) return float2(0.0);
            t0 = 2.0 * hi / (b - sqrt(dhi));
        }
        t1 = b < 0.0 && dlo >= 0.0 ? 2.0 * lo / (b - sqrt(dlo)) : hi >= 0.0 ? 2.0 * hi / (b + sqrt(dhi)) : (sqrt(dhi) - b) / (2.0 * a);   // out through the base, or the top
    }
    return t0 > 60000.0 ? float2(0.0) : float2(t0, min(t1, t0 + 20000.0));
}

// The cloud along a ray from the camera out to `far`, a few steps through the layer it can fill:
// its colour, hazed by its distance, and in w how much of what lies beyond still shows. The steps
// `steps` of them, starting `start` of a step in, which differs from pixel to pixel.
static float4 clouds(float3 rd, float far, int steps, float start, constant Frame &f, texture2d<float> lifted, sampler smp) {
    if (f.focus.w > 0.5) return float4(0, 0, 0, 1);   // the view from above looks through the cloud layer at the ground
    float2 span = cloud_span(rd, f);
    float lo = f.weather.y - f.cam.y, t0 = span.x, t1 = min(span.y, far);
    if (t1 <= t0) return float4(0, 0, 0, 1);
    float3 lit = sun_light(f.sun.xyz), sky = sky_ambient(float3(0, 1, 0), f.sun.xyz, f.weather.x);
    float dt = (t1 - t0) / float(steps), trans = 1.0, first = -1.0, t = t0 + dt * start;
    float bend = dot(rd.xz, rd.xz) / (2.0 * EARTH);   // the layer is round (cloud_span)
    float3 col = float3(0.0);
    for (int i = 0; i < steps && trans > 0.03; i++, t += dt) {
        float h = (rd.y + bend * t) * t - lo, top = cloud_top(rd.xz * t, f, lifted, smp, saturate(2.0 - t / 4000.0));
        float a = 1.0 - exp(-saturate((top - h) / max(abs(rd.y + 2.0 * bend * t) * dt, 20.0) + 0.5) * min(dt, 80.0) * 0.02);   // the share of the step inside; a long step is not let make the cloud opaque alone, or far cloud sparkles
        if (a <= 0.0 || top <= 0.0) continue;
        float3 light = lit * exp(-0.012 * (top - h)) * mix(0.55, 1.0, saturate(top / 250.0)) + sky * (0.45 + 0.35 * saturate(h / max(top, 1.0)));   // the sun dims through the cloud above, and the low tops lie in the high ones' shade
        col += trans * a * light;
        trans *= 1.0 - a;
        if (first < 0.0) first = t;
    }
    if (first > 0.0) col = mix(col, sky_color(float3(rd.x, max(rd.y, 0.0), rd.z), f.sun.xyz, f.weather.x) * (1.0 - trans), haze(rd * first, f));
    return float4(col, trans);
}

// The cloud layer along the line of sight through a pixel, from `seen`, where fs_clouds drew it
// at half size: four readings a pixel apart, which cancel the pattern its steps started in.
static float4 clouds_seen(float2 pixel, constant Frame &f, texture2d<float> seen, sampler smp) {
    float4 c = float4(0.0);
    for (int i = 0; i < 4; i++) c += 0.25 * seen.sample(smp, (pixel + float2(i & 1, i >> 1) * 2.0 - 1.0) / f.screen.xy);
    return c;
}

// What lies at `rel`, seen through the haze and the clouds between it and the camera. What lies
// beyond the whole cloud layer reads the layer from `seen`; only what stands inside the layer has
// its own cloud counted.
static float3 apply_fog(float3 col, float3 rel, float2 pixel, constant Frame &f, texture2d<float> lifted, sampler smp, texture2d<float> seen) {
    float dist = length(rel);
    float3 rd = rel / max(dist, 1e-4);
    col = mix(col, sky_color(float3(rd.x, max(rd.y, 0.0), rd.z), f.sun.xyz, f.weather.x), haze(rel, f));
    if (f.focus.w > 0.5) return col;
    float2 span = cloud_span(rd, f);
    if (dist <= span.x || span.y <= span.x) return col;
    float4 c = dist < span.y ? clouds(rd, dist, 16, hash21(pixel + 17.0), f, lifted, smp) : clouds_seen(pixel, f, seen, smp);
    return col * c.w + c.rgb;
}

// Tone map, encode for the display and break up banding.
static float4 finish(float3 c, float2 pixel, float alpha) {
    c = saturate((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14));   // filmic curve (Narkowicz ACES fit)
    c = pow(c, float3(1.0 / 2.2));
    c += (hash21(pixel) - 0.5) / 255.0;
    return float4(c, alpha);
}

// ---- terrain ----------------------------------------------------------------------------

struct QuadIn {
    short4  a [[attribute(0)]];   // origin x, y, z and extent along U
    ushort4 b [[attribute(1)]];   // extent along V, corner occlusion, face | flip | sky, ground slope
    ushort2 m [[attribute(2)]];   // material, and a spare
};

struct Corner { float3 pos; float ao; };

// One quad per instance; the four strip vertices are its corners. Bit 3 of the info word
// turns the diagonal so occlusion interpolates the same way on every face.
static Corner quad_corner(QuadIn q, uint vid) {
    uint info = q.b.z;
    uint face = info & 7u;
    uint c = vid;
    if ((info & 8u) != 0u) { c = vid == 0u ? 1u : vid == 1u ? 3u : vid == 2u ? 0u : 2u; }
    Corner r;
    r.pos = float3(q.a.xyz) + FACE_U[face] * (float(c & 1u) * float(q.a.w)) + FACE_V[face] * (float(c >> 1u) * float(q.b.x));
    r.ao = float((uint(q.b.y) >> (4u * c)) & 15u) / 15.0;
    return r;
}

// The cut (above.odin, docs/adr/0007): nothing above its level is drawn. A face of the block volume
// is clipped at the level, and where that opens solid ground a cap closes it (caps_make,
// render.odin). Beyond the volume the ground is columns, which have no inside to show: a column
// that stands over the level is lowered to it, and its top is marked as cut (1). A canopy that is
// part of a column (mesh_columns) cannot be lifted off it: where the cut passes through the
// canopy, or leaves are not drawn, the column takes the ground's material in place of the leaf's
// (2). A crown hung over the columns, and its trunk, is clipped as a block is.
constant uint HUNG = 0x4000u;   // in a quad's info, as in mesh.odin
constant uint CAP = 0x8000u;

struct Cut { float y; float clip; uint mark; };

static Cut cut_corner(QuadIn q, float y, float base, float cell, float4 cut) {
    uint info = q.b.z, face = info & 7u, canopy = (info >> 8u) & 63u;
    Cut o;
    o.y = y;
    o.mark = (info & CAP) != 0u ? 4u : 0u;
    o.clip = cut.x - y + 0.002;   // a face lying in the level itself is kept
    if (cell < 1.5) return o;
    if ((info & HUNG) != 0u) {
        if (canopy != 0u && cut.y > 0.5) o.clip = -1.0;
        return o;
    }
    o.clip = 1.0;
    o.y = min(y, cut.x);
    float top = base + float(q.a.y) + FACE_U[face].y * float(q.a.w) + FACE_V[face].y * float(q.b.x);   // the quad's upper edge
    if (canopy != 0u && (cut.y > 0.5 || top > cut.x)) o.mark = face == 2u && top - float(canopy) >= cut.x ? 1u : 2u;
    else if (face == 2u && top > cut.x) o.mark = 1u;
    return o;
}

struct TerrainV {
    float4 position [[position]];
    float3 rel;
    float ao;
    float cell [[flat]];
    uint info [[flat]];     // face | flip | sky in the low byte (QuadIn), the material over it, and over that what the cut made of it (cut_corner)
    float3 soft [[flat]];   // direction the light treats this face as pointing
    float clip [[clip_distance]];
};

vertex TerrainV vs_terrain(QuadIn q [[stage_in]], uint vid [[vertex_id]],
                           constant Frame &f [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    Corner c = quad_corner(q, vid);
    TerrainV o;
    o.rel = d.origin.xyz + c.pos;
    Cut k = cut_corner(q, o.rel.y, d.origin.y, d.origin.w, f.cut);
    o.rel.y = k.y;
    o.clip = k.clip;
    o.position = drawn(o.rel, f);
    o.ao = c.ao;
    o.cell = d.origin.w;
    o.info = (uint(q.b.z) & 255u) | uint(k.mark == 2u ? q.m.y : q.m.x) << 8u | k.mark << 24u;
    // Light a face partly by the slope of the hill it is cut from: half its own direction,
    // half the smooth ground's. Faces with no ground slope (trees) keep their own.
    float3 N = FACE_N[q.b.z & 7u];
    uint packed = q.b.w;
    float2 g = (float2(packed & 255u, packed >> 8u) - 128.0) / 127.0;
    o.soft = packed == 0u || k.mark == 1u ? N : normalize(N + float3(g.x, sqrt(max(1.0 - dot(g, g), 0.0)), g.y));
    return o;
}

struct ShadowU { float4x4 vp; float4 cut; };
struct ShadowV { float4 position [[position]]; float clip [[clip_distance]]; };

// Drawn flat, not lowered as the view is (drawn): every shader looks shadows up where a thing stands on the flat world.
// What the cut takes away casts no shadow.
vertex ShadowV vs_shadow(QuadIn q [[stage_in]], uint vid [[vertex_id]],
                         constant ShadowU &s [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    float3 rel = d.origin.xyz + quad_corner(q, vid).pos;
    Cut k = cut_corner(q, rel.y, d.origin.y, d.origin.w, s.cut);
    ShadowV o;
    o.position = s.vp * float4(rel.x, k.y, rel.z, 1.0);
    o.clip = k.clip;
    return o;
}

fragment void fs_shadow() {}

static float shadow_at(float3 rel, float3 N, constant Frame &f, depth2d_array<float> map, sampler smp) {
    float dist = length(rel - f.focus.xyz);   // the maps are centred on the eye, or from above on the ground under the view's middle
    uint c = dist < f.cascade_r.x * 0.9 ? 0u : dist < f.cascade_r.y * 0.9 ? 1u : dist < f.cascade_r.z * 0.9 ? 2u : 3u;
    float r = f.cascade_r[c];
    if (dist > r * 0.9) return 1.0;
    float texel = 2.0 * r / SHADOW_RES;
    float4 lp = f.shadow_vp[c] * float4(rel + N * texel * 1.5, 1.0);
    float2 uv = float2(lp.x * 0.5 + 0.5, 0.5 - lp.y * 0.5);
    float lit = 0.0;
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++)
            lit += map.sample_compare(smp, uv + float2(x, y) / SHADOW_RES, c, lp.z - 0.0006);
    lit /= 9.0;
    return c == 3u ? mix(lit, 1.0, smoothstep(0.75, 0.9, dist / r)) : lit;
}

// A block's texel of the map of marked blocks. Its low three bits say what it is marked as: 0 not,
// 1 to be dug, 2 what the tool would mark, 3 what it would take back, 4 the order in the hand, 5 a
// stockpile's ground, 6 the stockpile in the hand, 7 a sleeping place's ground, 8 the sleeping place
// in the hand, 9 ground under a roof and 10 ground indoors (the shelter lens). The second byte's
// five bits say which of the blocks beside it are open air: east, west, south, north, and over it.
static uint marked_as(texture3d<float> marks, float3 cell) {
    if (any(cell < 0.0) || cell.x >= 256.0 || cell.y >= 64.0 || cell.z >= 256.0) return 0u;
    float2 t = marks.read(uint3(cell)).rg;
    return uint(round(t.r * 255.0)) | (uint(round(t.g * 255.0)) << 8u);
}

// The colour a kind of marked ground is lined and tinted with, and how strongly it is tinted.
static float4 marked_look(uint kind, constant Frame &f) {
    if (kind == 3u) return float4(f.wrong.rgb, 0.22);
    if (kind < 5u) return float4(f.live.rgb, kind == 1u ? 0.09 : 0.22);
    if (kind < 7u) return float4(0.42, 1.25, 1.0, kind == 5u ? 0.2 : 0.42);
    if (kind < 9u) return float4(f.kinds[0].rgb, kind == 7u ? 0.22 : 0.45);
    return float4(f.kinds[kind == 9u ? 1 : 2].rgb, kind == 9u ? 0.3 : 0.38);
}

// A marked block's face: tinted, and lined along a side only where the mark ends there. Across a
// side the face goes on as the block's own next face, where the block beside it is open air; as
// the face of the block beside it, level with it; or as the face of the block that stands in front
// of that one, at the foot of a step. Where the one it goes on as is marked the same there is no
// line, so marks side by side are one shape, whatever boxes they were given as and however the
// ground under them steps.
static float3 marked_face(float3 col, float3 rel, float3 N, float cell_size, constant Frame &f, texture3d<float> marks) {
    float3 p = rel + f.marked.xyz;            // in the map's blocks
    float3 cell = floor(p - N * 0.5);
    uint here = marked_as(marks, cell);
    uint kind = here & 255u;
    if (cell_size > 1.5) {                    // far ground stands on cells of two metres and more: the block under or over it may be the one marked
        kind = max(kind, max(marked_as(marks, cell - N) & 255u, marked_as(marks, cell + N) & 255u));
        if (kind == 0u) return col;
        float4 far_look = marked_look(kind, f);
        return mix(col, far_look.rgb, max(far_look.a, 0.14) + 0.02);
    }
    if (kind == 0u || (kind >= 5u && N.y < 0.5)) return col;   // a stockpile, a sleeping place and sheltered ground are their floor: the faces that look up
    float4 look = marked_look(kind, f);
    float3 line = look.rgb;
    float tint = look.a;
    float3 a = abs(N.x) > 0.5 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);   // the two ways along the face
    float3 b = abs(N.z) > 0.5 ? float3(0.0, 1.0, 0.0) : float3(0.0, 0.0, 1.0);
    float3 in_cell = p - cell;
    float2 at = float2(dot(in_cell, a), dot(in_cell, b));
    float2 w = max(1.5 * fwidth(at), 0.03);
    float edge = 0.0;
    for (int i = 0; i < 4; i++) {
        float3 side = (i < 2 ? a : b) * ((i & 1) == 0 ? -1.0 : 1.0);
        uint bit = side.x > 0.5 ? 1u : side.x < -0.5 ? 2u : side.z > 0.5 ? 4u : side.z < -0.5 ? 8u : side.y > 0.5 ? 16u : 0u;
        if (((here >> 8u) & bit) != 0u) continue;                         // open air beside it: the face goes on round the block's own corner
        if ((marked_as(marks, cell + side) & 255u) == kind) continue;      // the block beside it is marked the same
        if ((marked_as(marks, cell + side + N) & 255u) == kind) continue;  // or the one standing in front of that, at the foot of a step
        float e = i < 2 ? ((i & 1) == 0 ? at.x : 1.0 - at.x) : ((i & 1) == 0 ? at.y : 1.0 - at.y);
        float wide = i < 2 ? w.x : w.y;
        edge = max(edge, 1.0 - smoothstep(0.6 * wide, wide, e));
    }
    return mix(col, line, max(tint, 0.85 * edge));
}

// A box of blocks shown on the faces of the blocks inside it: tinted, and lined where they meet
// the box's sides, the line no thinner than a pixel and a half.
static float3 outlined(float3 col, float3 rel, float3 N, float4 box, float3 size, float3 line, float tint) {
    if (box.w < 0.5) return col;
    float3 local = rel - N * 0.5 - box.xyz;
    if (any(local < -0.001) || any(local > size + 0.001)) return col;
    float3 p = rel - box.xyz, e = min(p, size - p);   // how far from the box's sides
    float3 w = max(1.5 * fwidth(p), 0.03);
    float3 near = 1.0 - smoothstep(0.6 * w, w, e);
    float edge = abs(N.x) > 0.5 ? max(near.y, near.z) : abs(N.y) > 0.5 ? max(near.x, near.z) : max(near.x, near.y);
    return mix(col, line, max(tint, 0.85 * edge));
}

fragment float4 fs_terrain(TerrainV in [[stage_in]], constant Frame &f [[buffer(0)]],
                           depth2d_array<float> shadow_map [[texture(0)]], sampler shadow_smp [[sampler(0)]],
                           texture2d_array<float> blocks [[texture(1)]], sampler block_smp [[sampler(1)]],
                           texture2d<float> lifted [[texture(2)]], sampler smp [[sampler(2)]], texture2d<float> seen [[texture(3)]],
                           texture2d<float> lens [[texture(4)]], sampler lens_smp [[sampler(4)]],
                           texture3d<float> marks [[texture(5)]], sampler marks_smp [[sampler(5)]],
                           bool outside [[front_facing]]) {
    uint face = in.info & 7u;
    uint mat = (in.info >> 8u) & 0xFFFFu;
    uint made = in.info >> 24u;   // what the cut made of this face (cut_corner)
    float3 N = FACE_N[face];
    float dist = length(in.rel);
    float3 world = in.rel + f.cam.xyz;
    float3 inside = world - N * (0.5 * in.cell);   // a point safely inside the cell this face belongs to
    // Ground this deep under the sea is black: the water takes all its light (below), so none of it is worked out.
    if (f.cam.w - world.y > DARK) return finish(apply_fog(float3(0.0), in.rel, in.position.xy, f, lifted, smp, seen), in.position.xy, 1.0);

    // Colour: the material's tile, a metre to a tile, its top on a face that looks up or down
    // and its side on the rest. A top is turned a quarter, a half or three quarters by the block
    // it is on, so a field of one material does not repeat. Then broad patches and a tint per block.
    float2 uv = face < 2u ? float2(world.z, -world.y) : face < 4u ? world.xz : float2(world.x, -world.y);
    float2 dx = dfdx(uv), dy = dfdy(uv);
    float block = hash21(floor(inside.xz / in.cell) + floor(inside.y / in.cell) * 31.0);
    if (face == 2u || face == 3u) {
        float2 turned = fract(uv) - 0.5;
        uint quarter = uint(hash21(floor(world.xz - N.xz * 0.01) + 3.0) * 4.0);
        uv = (quarter == 1u ? float2(-turned.y, turned.x) : quarter == 2u ? -turned : quarter == 3u ? float2(turned.y, -turned.x) : turned) + 0.5;
    }
    float4 tile = blocks.sample(block_smp, uv, mat * 2u + (face == 2u || face == 3u ? 0u : 1u), gradient2d(dx, dy));
    float3 albedo = tile.rgb;
    // Only a leaf's tile has clear gaps, and only the pipeline that draws the near leaves reads this.
    // The edge is kept sharp at any size, so far off, where a tile is a pixel, a leaf is whole.
    float cut = max(saturate((tile.a - 0.5) / max(fwidth(tile.a), 1e-4) + 0.5), smoothstep(0.6 * LEAF_FAR, LEAF_FAR, dist));   // and whole by where the far leaves are drawn whole
    float patches = vnoise(inside.xz / 41.0) * 0.6 + vnoise(inside.xz / 11.0) * 0.4;
    albedo *= 1.0 + (patches - 0.5) * 0.24 + (block - 0.5) * 0.10 * saturate(1.0 - dist / (in.cell * 200.0));
    // A lens: one of the land's fields painted over the ground and the woods, in the field's colour
    // with the ground's own light and dark kept, so the relief still reads. The faces the cut makes
    // are the inside of the ground and keep their own rock.
    if (f.lens.w > 0.5 && (made & 5u) == 0u) {
        float2 at = (in.rel.xz + f.lens.xy) * f.lens.z;
        if (all(at > 0.0) && all(at < 1.0)) {
            float4 l = lens.sample(lens_smp, at);
            float grain = dot(albedo, float3(0.3333)) / max(dot(blocks.sample(block_smp, float2(0.5), mat * 2u, level(4.0)).rgb, float3(0.3333)), 1e-3);
            albedo = mix(albedo, l.rgb * 0.26 * mix(1.0, clamp(grain, 0.6, 1.4), 0.5), 0.9 * l.a);
        }
    }
    // Where the cut passes through solid blocks, the face it makes is ruled block by block while a
    // block is a few pixels wide, so it reads as a cut and its blocks can be counted. Beyond the block
    // volume the ground is columns, whose rock at the level is not known: the cut there is one plain
    // dark tone.
    float px = max(fwidth(world.x), fwidth(world.z));   // metres to a pixel
    if ((made & 4u) != 0u) {
        float2 e = min(fract(world.xz), 1.0 - fract(world.xz));
        albedo *= 1.0 - 0.22 * (1.0 - smoothstep(0.4 * px, 1.2 * px, min(e.x, e.y))) * saturate(1.5 - 10.0 * px);
    }
    if ((made & 1u) != 0u) albedo = float3(0.062, 0.060, 0.058);

    float3 sun = f.sun.xyz;
    // A face turned from the sun on a sunlit slope is an accident of cutting the slope into
    // blocks. It is shadowed as the slope is: sampled a little way out along the slope's
    // direction, clear of its own block.
    float ndl = saturate(dot(in.soft, sun));
    bool turned = dot(N, sun) <= 0.0;
    float3 probe = turned ? in.rel + in.soft * (1.5 * in.cell) : in.rel;
    float shade = cloud_shade(in.rel, f, lifted, smp);   // under a cloud the sky round the sun is dimmed too
    float lit = ndl > 0.0 && outside ? shadow_at(probe, turned ? in.soft : N, f, shadow_map, shadow_smp) * shade * through_rain(f) : 0.0;   // only a leaf is seen from inside, and the inside of a crown is in its own shade
    float ao = mix(0.5, 1.0, in.ao);
    float sky = 1.0 - float((in.info >> 4u) & 15u) / 15.0;   // the share of the sky a face under a roof sees (mesh.odin); far off, of the sunlight too
    albedo *= 1.0 - 0.34 * f.rain.y * sky * saturate(N.y + 0.55);   // wet ground is darker, where the sky is over it: under a roof it is dry
    if (f.cut.x < 1e8) sky = 1.0;   // the cut has taken the roof off, for the light as well
    float3 col = albedo * (sun_light(sun) * ndl * lit * mix(1.0, ao, 0.45) * (in.cell > 1.0 ? sky : 1.0) + sky_ambient(in.soft, sun, f.weather.x) * ao * sky * mix(0.7, 1.0, shade));
    if (f.fire[0].w > 0.0) col += albedo * fire_glow(in.rel, N, f);

    // Light lost on the way down through water.
    float depth = f.cam.w - world.y;
    if (depth > 0.0) col *= exp(-depth * float3(0.30, 0.11, 0.08));

    // The block aimed at or under the pointer, outlined: dark in first person, bright from above,
    // where it must show from far off. Then the box of blocks marked, tinted and outlined.
    if (in.cell < 1.5) {
        col = outlined(col, in.rel, N, f.target, float3(1.0), f.target.w > 1.5 ? float3(2.2, 2.0, 1.2) : float3(0.0), 0.0);
        col = outlined(col, in.rel, N, f.mark, f.mark_size.xyz, float3(1.9, 1.2, 0.25), 0.12);
        if (N.y > 0.5) for (int i = 0; i < 48 && f.tint[i].w > 0.5; i++) {   // the ground over a mark: on the faces that look up, and no block's side, which would read as a block marked
            if (f.tint[i].w > 5.5) {   // over an order's marks: a faint wash and no line, which would box each order by itself
                float3 local = in.rel - N * 0.5 - f.tint[i].xyz;
                if (all(local > -0.001) && all(local < f.tint_size[i].xyz + 0.001)) col = mix(col, f.live.rgb, 0.035);
            } else col = outlined(col, in.rel, N, float4(f.tint[i].xyz, 1.0), f.tint_size[i].xyz, f.live.rgb, 0.13);
        }
    }
    if (f.marked.w > 0.5) col = marked_face(col, in.rel, N, in.cell, f, marks);   // the blocks marked, at any distance

    return finish(apply_fog(col, in.rel, in.position.xy, f, lifted, smp, seen), in.position.xy, cut);
}

// ---- ground plants ------------------------------------------------------------------------

// Two pictures crossed in an X over a column (plants.odin), set off its middle, turned and sized
// by its hash. They thin out from PLANT_NEAR to PLANT_FAR, each sinking into the ground as it
// reaches its own distance, so the edge of where they are drawn is never a line.
constant float PLANT_NEAR = 70.0, PLANT_FAR = 190.0, PLANT_ABOVE = 256.0;   // render.odin skips chunks beyond PLANT_FAR, or from above PLANT_ABOVE

struct PlantV {
    float4 position [[position]];
    float3 rel;
    float2 uv;            // across the picture, and up the plant in pictures
    float up;             // metres over the ground
    float ao;
    uint layer [[flat]];  // the lower picture; the upper one follows it
    uint info [[flat]];
    float3 soft [[flat]]; // the ground's normal, by which the plant is lit as the ground is
    float2 facing [[flat]]; // the picture's own normal across the ground, either way
    float clip [[clip_distance]];
};

vertex PlantV vs_plant(QuadIn q [[stage_in]], uint vid [[vertex_id]],
                       constant Frame &f [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    uint v = vid < 4u ? vid : vid < 6u ? 3u : vid - 2u;   // ten vertices: one picture, two that join nothing, the other
    uint plane = vid < 5u ? 0u : 1u, c = vid == 5u ? 0u : v & 3u;
    uint kind = uint(ushort(q.a.w)), h = q.b.x;
    float pictures = (kind >> 8u) != 0u ? 2.0 : 1.0;
    float r0 = float(h & 255u) / 255.0, r1 = float(h >> 8u) / 255.0;
    float3 foot = d.origin.xyz + float3(q.a.xyz) + float3(0.2 + 0.6 * r0, 0.0, 0.2 + 0.6 * r1);
    float reach = f.focus.w > 0.5 ? mix(PLANT_FAR, PLANT_ABOVE, fract(r0 * 13.7 + r1 * 5.3)) : mix(PLANT_NEAR, PLANT_FAR, fract(r0 * 13.7 + r1 * 5.3));   // from above they are part of reading the ground: all of them, to the block volume's edge
    float size = float(q.b.y) / 100.0 * (1.0 - smoothstep(0.8 * reach, reach, length(foot - f.focus.xyz)));
    float turn = float(plane) * 1.571 + fract(r0 * 7.1 + r1 * 3.3) * 1.571;   // any turn: an X repeats every quarter
    float across = float(c & 1u) * 2.0 - 1.0, rise = float(c >> 1u) * pictures * size;
    float3 p = foot + float3(cos(turn), 0.0, sin(turn)) * (0.7071 * size * across) + float3(0.0, rise, 0.0);
    float3 world = foot + f.cam.xyz;
    p.xz += rise * 0.03 * sin(f.sun.w * 1.6 + world.x * 0.35 + world.z * 0.27) * float2(0.8, 0.6);   // the wind stirs the tops
    PlantV o;
    o.rel = p;
    o.position = drawn(p, f);
    o.clip = f.cut.x - foot.y + 0.002;   // a plant stands or is gone with the block it stands on
    o.uv = float2(float(c & 1u), float(c >> 1u) * pictures);
    o.up = rise;
    o.ao = float(q.b.z & 15u) / 15.0;
    o.layer = (kind & 255u) * 2u;
    o.facing = float2(-sin(turn), cos(turn));
    o.info = q.b.z;
    uint packed = q.b.w;
    float2 g = (float2(packed & 255u, packed >> 8u) - 128.0) / 127.0;
    o.soft = packed == 0u ? float3(0, 1, 0) : normalize(float3(0, 1, 0) + float3(g.x, sqrt(max(1.0 - dot(g, g), 0.0)), g.y));
    return o;
}

fragment float4 fs_plant(PlantV in [[stage_in]], constant Frame &f [[buffer(0)]],
                         depth2d_array<float> shadow_map [[texture(0)]], sampler shadow_smp [[sampler(0)]],
                         texture2d_array<float> pictures [[texture(1)]], sampler pic_smp [[sampler(1)]],
                         texture2d<float> lifted [[texture(2)]], sampler smp [[sampler(2)]], texture2d<float> seen [[texture(3)]]) {
    uint upper = in.uv.y >= 1.0 ? 1u : 0u;
    float2 uv = float2(in.uv.x, 1.0 - (in.uv.y - float(upper)));
    float2 dx = dfdx(in.uv), dy = dfdy(in.uv);   // from the whole plant, so the seam between its pictures is not a jump
    float4 tex = pictures.sample(pic_smp, uv, in.layer + upper, gradient2d(dx, dy));
    // The smaller copies average the cut-out away, so far plants would thin and vanish: keep their
    // coverage, then turn the edge into a sharp one a pixel wide (after Ben Golus, 2017).
    float lod = max(log2(max(length(dx), length(dy)) * 16.0), 0.0);
    float a = tex.a * (1.0 + 0.25 * lod);
    a = saturate((a - 0.5) / max(fwidth(a), 1e-4) + 0.5);

    float3 sun = f.sun.xyz;
    float ndl = saturate(dot(in.soft, sun)) * mix(0.55, 1.15, abs(dot(in.facing, normalize(sun.xz + 1e-4))));   // a picture turned to the sun takes more of it, as a block's faces do
    float shade = cloud_shade(in.rel, f, lifted, smp);
    float lit = ndl > 0.0 ? shadow_at(in.rel, in.soft, f, shadow_map, shadow_smp) * shade * through_rain(f) : 0.0;
    float ao = mix(0.5, 1.0, in.ao) * mix(0.6, 1.0, saturate(in.up / 0.6));   // darker toward the root, in the plant's own shade
    float sky = 1.0 - float((in.info >> 4u) & 15u) / 15.0;
    float3 col = tex.rgb * (sun_light(sun) * ndl * lit * mix(1.0, ao, 0.45) + sky_ambient(in.soft, sun, f.weather.x) * ao * sky * mix(0.7, 1.0, shade));
    if (f.fire[0].w > 0.0) col += tex.rgb * fire_glow(in.rel, float3(0.0, 1.0, 0.0), f);
    return finish(apply_fog(col, in.rel, in.position.xy, f, lifted, smp, seen), in.position.xy, a);
}

// ---- creatures ----------------------------------------------------------------------------

// A box of a creature's body (creatures.odin): its middle from the eye and its three half axes,
// with its colour above and beneath and the depth of water over it in the spare places. The
// fourteen corners of a strip that wraps a cube are read from three words of bits.
struct BoxIn {
    float4 c [[attribute(0)]];   // middle, colour of its top face as 0xRRGGBB
    float4 x [[attribute(1)]];   // half axes; colour of its other faces
    float4 y [[attribute(2)]];   //            water over it, metres
    float4 z [[attribute(3)]];   //            where the body it is of stands, from the eye's height, or 0 for a box cut where the cut falls
};

struct BoxV {
    float4 position [[position]];
    float3 rel;
    float3 local;               // -1 to 1 across the box
    float3 upper [[flat]];
    float3 under [[flat]];
    float wet [[flat]];
    float clip [[clip_distance]];
};

static float3 unpack_rgb(float c) {
    uint u = uint(c);
    return pow(float3((u >> 16u) & 255u, (u >> 8u) & 255u, u & 255u) / 255.0, 2.2);
}

vertex BoxV vs_box(BoxIn b [[stage_in]], uint vid [[vertex_id]], constant Frame &f [[buffer(0)]]) {
    float3 s = float3((0x287au >> vid) & 1u, (0x02afu >> vid) & 1u, (0x31e3u >> vid) & 1u) * 2.0 - 1.0;
    BoxV o;
    o.rel = b.c.xyz + b.x.xyz * s.x + b.y.xyz * s.y + b.z.xyz * s.z;
    o.position = drawn(o.rel, f);
    // A body is drawn whole or not at all (ADR 0007): where the box says how high its feet stand, the
    // cut asks that, so one standing under the level keeps its head and one standing over it is gone.
    o.clip = b.z.w != 0.0 ? f.cut.x - b.z.w - 0.01 : f.cut.x - o.rel.y;
    o.local = s;
    o.upper = unpack_rgb(b.c.w);
    o.under = unpack_rgb(b.x.w);
    o.wet = b.y.w;
    return o;
}

fragment float4 fs_box(BoxV in [[stage_in]], constant Frame &f [[buffer(0)]],
                       depth2d_array<float> shadow_map [[texture(0)]], sampler shadow_smp [[sampler(0)]],
                       texture2d<float> lifted [[texture(1)]], sampler smp [[sampler(1)]], texture2d<float> seen [[texture(2)]]) {
    float3 N = normalize(cross(dfdx(in.rel), dfdy(in.rel)));
    if (dot(N, in.rel) > 0.0) N = -N;
    float3 albedo = in.local.y >= max(abs(in.local.x), abs(in.local.z)) ? in.upper : in.under;   // the back, and the flanks and belly
    float3 sun = f.sun.xyz;
    float ndl = saturate(dot(N, sun));
    float shade = cloud_shade(in.rel, f, lifted, smp);
    float lit = ndl > 0.0 ? shadow_at(in.rel, N, f, shadow_map, shadow_smp) * shade * through_rain(f) : 0.0;
    float3 col = albedo * (sun_light(sun) * ndl * lit + sky_ambient(N, sun, f.weather.x) * mix(0.7, 1.0, shade));
    if (f.fire[0].w > 0.0) col += albedo * fire_glow(in.rel, N, f);
    if (in.wet < 0.0) col = albedo * -in.wet;   // a flame: it shines by itself, so much
    col *= exp(-max(in.wet, 0.0) * float3(0.30, 0.11, 0.08));   // light lost on the way down through water
    return finish(apply_fog(col, in.rel, in.position.xy, f, lifted, smp, seen), in.position.xy, 1.0);
}

// ---- sky, water, present ------------------------------------------------------------------

struct ScreenV {
    float4 position [[position]];
    float2 uv;
};

vertex ScreenV vs_screen(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1u) & 2u, vid & 2u);
    ScreenV o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

fragment float4 fs_sky(ScreenV in [[stage_in]], constant Frame &f [[buffer(0)]],
                       texture2d<float> seen [[texture(0)]], sampler smp [[sampler(0)]]) {
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float3 d = normalize(f.cam_f.xyz + f.cam_r.xyz * ndc.x + f.cam_u.xyz * ndc.y);
    float3 col = sky_color(d, f.sun.xyz, f.weather.x);
    col += sun_light(f.sun.xyz) * 6.0 * smoothstep(0.99955, 0.9998, dot(d, f.sun.xyz)) * step(0.0, d.y);
    float4 c = clouds_seen(in.position.xy, f, seen, smp);
    return finish(col * c.w + c.rgb, in.position.xy, 1.0);
}

// The clouds along each line of sight through the whole layer, drawn once a frame at half size
// for the sky and for everything seen through the layer. Counting them at each face of the ground
// instead cost three frames in four from over the clouds. The steps start at four depths in a
// pattern two pixels square, which the four readings of clouds_seen average away, each shifted a
// little by chance so the steps do not show as terraces.
fragment float4 fs_clouds(ScreenV in [[stage_in]], constant Frame &f [[buffer(0)]],
                          texture2d<float> lifted [[texture(0)]], sampler smp [[sampler(0)]]) {
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    uint2 p = uint2(in.position.xy) & 1u;
    return clouds(normalize(f.cam_f.xyz + f.cam_r.xyz * ndc.x + f.cam_u.xyz * ndc.y), 1e6, 24, (float(p.x ^ p.y) * 2.0 + float(p.y) + hash21(in.position.xy + 17.0)) / 4.0, f, lifted, smp);
}

struct WaterV {
    float4 position [[position]];
    float3 rel;
    float2 river;   // x: -1 to 1 across a river ribbon, y: 1 for river water down to 0 for the sea
    float2 flow;    // metres a second, where the water is simulated
    float3 kind;    // x: 1 for simulated water, y: 0 for level water to 1 for falling, z: depth
    float roof;     // the share of it under a roof of rock
    float clip [[clip_distance]];
};

// The sea beyond the simulated water: a sheet at sea level round the eye, as a grid of SEA_GRID
// squared quads (one an instance) that widen with distance, so it bends with the world out to past
// the horizon.
constant uint SEA_GRID = 64;   // as in render.odin
vertex WaterV vs_water(uint vid [[vertex_id]], uint cell [[instance_id]], constant Frame &f [[buffer(0)]]) {
    float reach = max(80000.0, 1.3 * sqrt(2.0 * EARTH * max(f.cam.y - f.cam.w, 1.0)));
    float2 u = float2(cell % SEA_GRID + (vid & 1u), cell / SEA_GRID + (vid >> 1u)) / float(SEA_GRID) * 2.0 - 1.0;
    float2 c = sign(u) * u * u * reach;
    WaterV o;
    o.rel = float3(c.x, f.cam.w - f.cam.y, c.y);
    o.river = float2(0.0);
    o.flow = float2(0.0);
    o.kind = float3(0.0, 0.0, 10.0);
    o.roof = 0.0;
    o.position = drawn(o.rel, f);
    o.clip = f.cut.x - o.rel.y + 0.002;
    return o;
}

// Rivers beyond the simulated water: a strip of positions relative to the region's middle,
// with where each lies across the channel.
struct RiverIn { float4 p [[attribute(0)]]; };

vertex WaterV vs_river(RiverIn in [[stage_in]], constant Frame &f [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    WaterV o;
    o.rel = in.p.xyz + d.origin.xyz;
    bool lake = in.p.w > 1.5;   // a lake's far surface rides in the same strip, marked so
    o.river = float2(lake ? 0.0 : in.p.w, smoothstep(0.0, 1.2, in.p.y - f.cam.w));   // near sea level a river takes on the sea's look
    o.flow = float2(0.0);
    o.kind = float3(0.0, 0.0, lake ? 10.0 : 1.5);
    o.roof = 0.0;
    o.position = drawn(o.rel, f);
    o.clip = f.cut.x - o.rel.y + 0.002;
    return o;
}

// Simulated water: one quad for each instance, as built in water.odin.
struct PoolIn {
    float3 p0 [[attribute(0)]];
    float3 p1 [[attribute(1)]];
    float3 p2 [[attribute(2)]];
    float3 p3 [[attribute(3)]];
    float4 m0 [[attribute(4)]];   // at each corner: flow x, flow z, depth, falling
    float4 m1 [[attribute(5)]];
    float4 m2 [[attribute(6)]];
    float4 m3 [[attribute(7)]];
};

vertex WaterV vs_pool(PoolIn in [[stage_in]], uint vid [[vertex_id]], constant Frame &f [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    float3 p = vid == 0u ? in.p0 : vid == 1u ? in.p1 : vid == 2u ? in.p2 : in.p3;
    float4 m = vid == 0u ? in.m0 : vid == 1u ? in.m1 : vid == 2u ? in.m2 : in.m3;
    WaterV o;
    o.rel = p + d.origin.xyz;
    o.river = float2(0.0, smoothstep(0.0, 1.2, p.y - f.cam.w));
    o.flow = m.xy;
    float quarters = max(floor(m.w * 0.5), 0.0);   // water.odin packs the share under a roof in whole twos over the falling
    if (m.w < 0.0) m.w = -m.w;   // a fall's own water (falls_make, rivers.odin) is under no roof, and says what it is below zero
    o.kind = float3(1.0, m.w - 2.0 * quarters, m.z);
    o.roof = quarters * 0.25;
    o.position = drawn(o.rel, f);
    o.clip = f.cut.x - o.rel.y + 0.002;
    return o;
}

// Slope of a field of small ripples at a point.
static float2 ripples(float2 p) {
    float e = 0.12;
    return float2(vnoise(p + float2(e, 0.0)) - vnoise(p - float2(e, 0.0)),
                  vnoise(p + float2(0.0, e)) - vnoise(p - float2(0.0, e))) / (2.0 * e);
}

fragment float4 fs_water(WaterV in [[stage_in]], constant Frame &f [[buffer(0)]],
                         texture2d<float> simulated [[texture(0)]], sampler unused [[sampler(0)]],
                         texture2d<float> lifted [[texture(1)]], sampler smp [[sampler(1)]], texture2d<float> seen [[texture(2)]]) {
    float dist = length(in.rel);
    float3 rd = in.rel / dist;
    float2 w = in.rel.xz + f.cam.xz;
    float t = f.sun.w;

    // Drawn water gives way to simulated water, chunk by chunk. The record of which chunks
    // are simulated wraps around every 32 chunks, so only the 32 around the camera count.
    if (in.kind.x < 0.5) {
        int2 chunk = int2(floor(w / 32.0));
        int2 away = chunk - int2(floor(f.cam.xz / 32.0));
        if (all(abs(away) < 16) && simulated.read(uint2(chunk & 31)).r > 0.5) discard_fragment();
    }

    // Still water: a few crossing ripples.
    float2 slope = float2(0.0);
    slope += float2(0.8, 0.6) * cos(dot(w, float2(0.8, 0.6)) * 0.9 + t * 1.3) * 0.030;
    slope += float2(-0.5, 0.86) * cos(dot(w, float2(-0.5, 0.86)) * 1.7 - t * 1.9) * 0.022;
    slope += float2(0.2, -0.98) * cos(dot(w, float2(0.2, -0.98)) * 3.1 + t * 2.6) * 0.014;

    // Moving water carries a pattern with it. A carried pattern stretches without limit, so
    // there are two copies, each started afresh in turn while the other is at full strength.
    float speed = length(in.flow);
    float running = saturate(speed / 1.0);
    float2 turn = float2(fract(t / 1.8), fract(t / 1.8 + 0.5));
    float2 weight = 1.0 - abs(2.0 * turn - 1.0);
    float2 q0 = w - in.flow * (turn.x - 0.5) * 1.8;
    float2 q1 = w - in.flow * (turn.y - 0.5) * 1.8 + 37.0;
    slope += (ripples(q0 * 1.9) * weight.x + ripples(q1 * 1.9) * weight.y) * 0.16 * running;
    float carried = vnoise(q0 * 2.3) * weight.x + vnoise(q1 * 2.3) * weight.y;   // 0..1, drifting downstream

    slope /= 1.0 + dist * 0.03;   // flatter with distance, so it never shimmers
    float3 N = normalize(float3(-slope.x, 1.0, -slope.y));
    if (rd.y > 0.0) N = -N;   // seen from below

    float3 sun = f.sun.xyz;
    float3 r = reflect(rd, N);
    // Far out the ripples are flattened, but the sea is not a mirror there: the faces of its waves turned
    // to the eye show less sky, and sky from higher up, so it stays darker than the sky over its horizon.
    float rough = 0.08 * smoothstep(2000.0, 8000.0, dist) * (1.0 - in.river.y);
    float fresnel = 0.02 + 0.98 * pow(1.0 - max(saturate(dot(-rd, N)), rough), 5.0);
    // A river is shallower and clearer than the sea, and thins to nothing at its edges.
    float3 body = mix(float3(0.010, 0.045, 0.060), float3(0.022, 0.070, 0.058), in.river.y);
    float3 mirrored = sky_color(float3(r.x, max(abs(r.y), 2.0 * rough), r.z), sun, f.weather.x) * (1.0 - 0.35 * in.river.y);   // banks and trees dim a river's sky
    float above = (f.weather.y - f.cam.y - in.rel.y) / max(abs(r.y), 0.02);   // the cloud base over the reflected ray
    if (above > 0.0) mirrored = mix(mirrored, sky_ambient(float3(0, 1, 0), sun, f.weather.x) * 0.9 + sun_light(sun) * 0.3,
                                    0.7 * smoothstep(0.0, 200.0, cloud_top(in.rel.xz + r.xz * above, f, lifted, smp, 0.0)) * (1.0 - haze(r * above, f)));
    mirrored *= 1.0 - 0.9 * in.roof;   // under a roof it mirrors the dark rock
    float shade = cloud_shade(in.rel, f, lifted, smp);
    float3 col = mix(body * (0.15 + 0.85 * daylight(sun)) * (0.5 + 0.5 * shade) * (1.0 - 0.7 * in.roof), mirrored, fresnel);
    col += sun_light(sun) * 2.5 * shade * pow(saturate(dot(r, sun)), 600.0) * (1.0 - in.roof);
    float alpha = mix(mix(0.80, 0.62, in.river.y), 1.0, max(fresnel, smoothstep(8000.0, 16000.0, dist) * (1.0 - in.river.y)));   // nothing shows through the sea past 16 km, where the rings coarser than COARSE draw no sea floor
    alpha = mix(alpha, 0.96, in.river.y * smoothstep(1.5, 7.0, in.kind.z));   // deep fresh water is dark: a lake hides its bed, a stream shows it
    alpha *= 1.0 - 0.8 * in.river.y * smoothstep(0.35, 0.85, abs(in.river.x));
    alpha *= 0.25 + 0.75 * smoothstep(0.0, 0.35, in.kind.z);

    float3 geometric = normalize(cross(dfdx(in.rel), dfdy(in.rel)));
    float3 whitish = float3(0.55, 0.62, 0.68) * (sun_light(sun) * 0.3 * shade + sky_ambient(float3(0, 1, 0), sun, f.weather.x));
    // A fall's own water (falls_make, rivers.odin): strands streaming down, nearly solid where
    // much water crosses the lip, with gaps where little does; and where it lands, foam carried
    // off by the flow, thinning away from the fall.
    if (in.kind.y > 1.5) {
        float y = in.rel.y + f.cam.y;
        float u = dot(w, normalize(float2(-geometric.z, geometric.x) + 1e-4));
        float strands = 0.6 * vnoise(float2(u * 2.5, y * 0.15 + t * 1.8)) + 0.4 * vnoise(float2(u * 8.0, y * 0.5 + t * 5.0));
        float solid = smoothstep(0.4, 1.3, speed);
        float a = in.kind.y > 3.5 ? mix(smoothstep(0.3, 0.65, strands), 0.6 + 0.4 * strands, solid)
                                  : smoothstep(0.2, 0.5, carried - 0.6 + 0.8 * (in.kind.y - 2.0)) * (in.kind.y - 2.0);
        float3 sky = sky_ambient(float3(0, 1, 0), sun, f.weather.x);   // broken water is white: it takes the sky's light, not its colour
        float3 white = float3(0.86, 0.89, 0.91) * (sun_light(sun) * 0.35 * shade + mix(sky, float3(dot(sky, float3(0.333))), 0.6));
        return finish(apply_fog(white * (0.75 + 0.35 * strands), in.rel, in.position.xy, f, lifted, smp, seen), in.position.xy, 0.92 * a);
    }

    // White water. On a fall it runs down in streaks. On the level it is foam carried by
    // the flow: none in slow water, patches as it quickens, nearly solid below a fall.
    float sheet = smoothstep(0.5, 0.9, 1.0 - abs(geometric.y));
    float streaks = vnoise(float2((w.x + w.y) * 7.0, (in.rel.y + f.cam.y) * 0.7 + t * 3.5));
    float churn = max(smoothstep(1.3, 3.2, speed), in.kind.y);
    float foam = smoothstep(0.0, 0.3, carried - (1.05 - 0.8 * churn));   // never solid: churning water is foam in patches, carried off
    float white = mix(foam * 0.85, in.kind.y * 0.6 * smoothstep(0.45, 0.8, streaks), sheet);   // a step's sheet is the stream's own water with thin white streaks running down it, not a white slab
    col = mix(col, whitish * (0.75 + 0.35 * carried), white);
    alpha = mix(alpha, 0.9, max(white, 0.8 * sheet * saturate(in.kind.y)));
    return finish(apply_fog(col, in.rel, in.position.xy, f, lifted, smp, seen), in.position.xy, alpha);
}

// Rain falling over the view, or snow: streaks in three depths, leaning with the wind, the more of
// them the harder it falls. It is laid over the finished picture of the world, under the interface:
// what a roof keeps off is said by the ground under it staying dry.
fragment float4 fs_rain(ScreenV in [[stage_in]], constant Frame &f [[buffer(0)]]) {
    float fall = abs(f.rain.x);
    bool snow = f.rain.x < 0.0;
    float2 at = in.position.xy / f.screen.y;
    float streaks = 0.0;
    for (int l = 0; l < 3; l++) {
        float across = (snow ? 46.0 : 34.0) + 24.0 * float(l);   // columns to a screen's height
        float2 q = float2(at.x + at.y * f.rain.z, at.y);
        float column = floor(q.x * across);
        float h = hash21(float2(column, 17.0 * float(l) + 3.0));
        if (h > 0.25 + 0.75 * fall) continue;
        float speed = snow ? 0.22 + 0.1 * h : 1.9 + 0.8 * float(l) + 0.7 * h;
        float along = fract(q.y * (snow ? 3.0 : 1.3 + h) - f.rain.w * speed + 9.0 * h);
        float len = snow ? 0.035 : 0.16 + 0.14 * h;
        float across_it = abs(fract(q.x * across) - 0.5);
        streaks = max(streaks, smoothstep(0.0, len, along) * step(along, len) * (1.0 - smoothstep(snow ? 0.12 : 0.04, snow ? 0.3 : 0.11, across_it)) * (1.0 - 0.25 * float(l)));
    }
    return float4(snow ? float3(0.93, 0.95, 0.97) : float3(0.74, 0.8, 0.88), streaks * (snow ? 0.75 : 0.42) * (0.55 + 0.45 * fall));
}

fragment float4 fs_present(ScreenV in [[stage_in]], constant Frame &f [[buffer(0)]],
                           texture2d<float> scene [[texture(0)]], sampler smp [[sampler(0)]]) {
    float4 c = scene.sample(smp, in.uv);
    // Crosshair: a small cross that inverts what is behind it.
    float2 p = abs(in.position.xy - f.screen.xy * 0.5);
    float arm = f.screen.y / 90.0, thick = max(1.0, f.screen.y / 720.0);
    if (f.screen.z > 0.5 && ((p.x < arm && p.y < thick) || (p.y < arm && p.x < thick))) c.rgb = 1.0 - c.rgb;
    return float4(c.rgb, 1.0);
}
