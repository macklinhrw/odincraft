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
};

struct Draw { float4 origin; };   // xyz: chunk origin, w: cell size in metres

constant float SHADOW_RES = 2048.0;

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
    float3 sky = mix(float3(0.008, 0.011, 0.024), mix(float3(0.44, 0.55, 0.76), float3(0.62, 0.64, 0.68), cover), day);
    float3 ground = mix(float3(0.003, 0.004, 0.006), float3(0.27, 0.25, 0.20), day);
    return mix(ground, sky, N.y * 0.5 + 0.5);
}

// Haze that thins with altitude, integrated along the view ray: how much of the sky's colour
// there is in what lies at `rel`.
static float haze(float3 rel, constant Frame &f) {
    float dist = length(rel);
    float falloff = 0.0011;
    float t = falloff * rel.y;
    float through = abs(t) < 1e-3 ? 1.0 : (1.0 - exp(-t)) / t;
    return 1.0 - exp(-0.00006 * exp(-falloff * max(f.cam.y - f.cam.w, 0.0)) * dist * through);
}

// ---- clouds -------------------------------------------------------------------------------

// How far the cloud over a point stands above the cloud base, in metres, 0 where there is none.
// The deck is noise drifting on the wind over as much of the sky as the weather's cover. The cap
// is where the wind off the sea has been lifted past the cloud base by the ground it crossed.
static float cloud_top(float2 rel, constant Frame &f, texture2d<float> lifted, sampler smp, float fine) {
    float2 q = (rel + f.cloud.xy) / 1200.0;
    float n = 0.5 * vnoise(q) + 0.25 * vnoise(q * 2.03 + 7.1) + (fine > 0.0 ? fine * (0.15 * vnoise(q * 4.1 + 3.7) + 0.1 * vnoise(q * 8.3 + 1.3) - 0.125) : 0.0) + 0.125;   // the fine octaves fade out with distance, where steps would alias them
    float c = f.weather.x - 0.5;   // the noise passes this level over a share `cover` of the sky
    float level = 0.5 - 0.36 * c - 0.5 * c * c * c - 0.3 * smoothstep(0.9, 1.0, f.weather.x) + 0.5 * (1.0 - smoothstep(0.0, 0.03, f.weather.x));
    float rise = lifted.sample(smp, (rel + f.cloud.zw) / f.weather.w).r - f.weather.y;
    return max(f.weather.z * smoothstep(0.0, 0.35, n - level), saturate((rise + 30.0) / 60.0) * (rise + 150.0) * (0.5 + n));
}

// The share of the sun's light that reaches a point through the cloud over where its ray
// crosses the deck.
static float cloud_shade(float3 rel, constant Frame &f, texture2d<float> lifted, sampler smp) {
    float up = max(f.weather.y + 100.0 - f.cam.y - rel.y, 0.0) / max(f.sun.y, 0.05);
    return 1.0 - 0.85 * smoothstep(0.0, 60.0, cloud_top(rel.xz + f.sun.xz * up, f, lifted, smp, 0.0));
}

// The cloud along a ray from the camera out to `far`, a few steps through the layer it can fill:
// its colour, hazed by its distance, and in w how much of what lies beyond still shows.
static float4 clouds(float3 rd, float far, float2 pixel, constant Frame &f, texture2d<float> lifted, sampler smp) {
    float lo = f.weather.y - f.cam.y, hi = lo + 300.0, t0 = 0.0, t1 = far;
    if (abs(rd.y) > 1e-5) {
        t0 = max(min(lo / rd.y, hi / rd.y), 0.0);
        t1 = min(max(lo / rd.y, hi / rd.y), min(far, t0 + 20000.0));
    } else if (lo > 0.0 || hi < 0.0) return float4(0, 0, 0, 1);
    if (t1 <= t0 || t0 > 60000.0) return float4(0, 0, 0, 1);
    float3 lit = sun_light(f.sun.xyz), sky = sky_ambient(float3(0, 1, 0), f.sun.xyz, f.weather.x);
    float dt = (t1 - t0) / 16.0, trans = 1.0, first = -1.0, t = t0 + dt * hash21(pixel + 17.0);   // steps start at a different point in each pixel
    float3 col = float3(0.0);
    for (int i = 0; i < 16 && trans > 0.03; i++, t += dt) {
        float h = rd.y * t - lo, top = cloud_top(rd.xz * t, f, lifted, smp, saturate(2.0 - t / 4000.0));
        float a = 1.0 - exp(-saturate((top - h) / max(abs(rd.y) * dt, 20.0) + 0.5) * min(dt, 80.0) * 0.02);   // the share of the step inside; a long step is not let make the cloud opaque alone, or far cloud sparkles
        if (a <= 0.0 || top <= 0.0) continue;
        float3 light = lit * exp(-0.012 * (top - h)) * mix(0.55, 1.0, saturate(top / 250.0)) + sky * (0.45 + 0.35 * saturate(h / max(top, 1.0)));   // the sun dims through the cloud above, and the low tops lie in the high ones' shade
        col += trans * a * light;
        trans *= 1.0 - a;
        if (first < 0.0) first = t;
    }
    if (first > 0.0) col = mix(col, sky_color(float3(rd.x, max(rd.y, 0.0), rd.z), f.sun.xyz, f.weather.x) * (1.0 - trans), haze(rd * first, f));
    return float4(col, trans);
}

// What lies at `rel`, seen through the haze and the clouds between it and the camera.
static float3 apply_fog(float3 col, float3 rel, float2 pixel, constant Frame &f, texture2d<float> lifted, sampler smp) {
    float dist = length(rel);
    float3 rd = rel / max(dist, 1e-4);
    col = mix(col, sky_color(float3(rd.x, max(rd.y, 0.0), rd.z), f.sun.xyz, f.weather.x), haze(rel, f));
    float4 c = clouds(rd, dist, pixel, f, lifted, smp);
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
    ushort4 b [[attribute(1)]];   // extent along V, corner occlusion, face | flip | material, ground slope
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

struct TerrainV {
    float4 position [[position]];
    float3 rel;
    float ao;
    float cell [[flat]];
    uint info [[flat]];
    float3 soft [[flat]];   // direction the light treats this face as pointing
};

vertex TerrainV vs_terrain(QuadIn q [[stage_in]], uint vid [[vertex_id]],
                           constant Frame &f [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    Corner c = quad_corner(q, vid);
    TerrainV o;
    o.rel = d.origin.xyz + c.pos;
    o.position = f.view_proj * float4(o.rel, 1.0);
    o.ao = c.ao;
    o.cell = d.origin.w;
    o.info = q.b.z;
    // Light a face partly by the slope of the hill it is cut from: half its own direction,
    // half the smooth ground's. Faces with no ground slope (trees) keep their own.
    float3 N = FACE_N[q.b.z & 7u];
    uint packed = q.b.w;
    float2 g = (float2(packed & 255u, packed >> 8u) - 128.0) / 127.0;
    o.soft = packed == 0u ? N : normalize(N + float3(g.x, sqrt(max(1.0 - dot(g, g), 0.0)), g.y));
    return o;
}

struct ShadowU { float4x4 vp; };

vertex float4 vs_shadow(QuadIn q [[stage_in]], uint vid [[vertex_id]],
                        constant ShadowU &s [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    return s.vp * float4(d.origin.xyz + quad_corner(q, vid).pos, 1.0);
}

fragment void fs_shadow() {}

static float shadow_at(float3 rel, float3 N, constant Frame &f, depth2d_array<float> map, sampler smp) {
    float dist = length(rel);
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

fragment float4 fs_terrain(TerrainV in [[stage_in]], constant Frame &f [[buffer(0)]],
                           depth2d_array<float> shadow_map [[texture(0)]], sampler shadow_smp [[sampler(0)]],
                           texture2d_array<float> blocks [[texture(1)]], sampler block_smp [[sampler(1)]],
                           texture2d<float> lifted [[texture(2)]], sampler smp [[sampler(2)]]) {
    uint face = in.info & 7u;
    uint mat = (in.info >> 8u) & 255u;
    float3 N = FACE_N[face];
    float dist = length(in.rel);
    float3 world = in.rel + f.cam.xyz;
    float3 inside = world - N * (0.5 * in.cell);   // a point safely inside the cell this face belongs to

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
    float3 albedo = blocks.sample(block_smp, uv, mat * 2u + (face == 2u || face == 3u ? 0u : 1u), gradient2d(dx, dy)).rgb;
    float patches = vnoise(inside.xz / 41.0) * 0.6 + vnoise(inside.xz / 11.0) * 0.4;
    albedo *= 1.0 + (patches - 0.5) * 0.24 + (block - 0.5) * 0.10 * saturate(1.0 - dist / (in.cell * 200.0));

    float3 sun = f.sun.xyz;
    // A face turned from the sun on a sunlit slope is an accident of cutting the slope into
    // blocks. It is shadowed as the slope is: sampled a little way out along the slope's
    // direction, clear of its own block.
    float ndl = saturate(dot(in.soft, sun));
    bool turned = dot(N, sun) <= 0.0;
    float3 probe = turned ? in.rel + in.soft * (1.5 * in.cell) : in.rel;
    float shade = cloud_shade(in.rel, f, lifted, smp);   // under a cloud the sky round the sun is dimmed too
    float lit = ndl > 0.0 ? shadow_at(probe, turned ? in.soft : N, f, shadow_map, shadow_smp) * shade : 0.0;
    float ao = mix(0.5, 1.0, in.ao);
    float sky = 1.0 - float((in.info >> 4u) & 15u) / 15.0;   // the share of the sky a face under a roof sees (mesh.odin); far off, of the sunlight too
    float3 col = albedo * (sun_light(sun) * ndl * lit * mix(1.0, ao, 0.45) * (in.cell > 1.0 ? sky : 1.0) + sky_ambient(in.soft, sun, f.weather.x) * ao * sky * mix(0.7, 1.0, shade));

    // Light lost on the way down through water.
    float depth = f.cam.w - world.y;
    if (depth > 0.0) col *= exp(-depth * float3(0.30, 0.11, 0.08));

    // Outline of the block being aimed at.
    if (f.target.w > 0.5 && in.cell < 1.5) {
        float3 local = in.rel - N * 0.5 - f.target.xyz;
        if (all(local > -0.001) && all(local < 1.001)) {
            float3 e = min(fract(world), 1.0 - fract(world));
            float edge = face < 2u ? min(e.y, e.z) : face < 4u ? min(e.x, e.z) : min(e.x, e.y);
            col = mix(col, float3(0.0), 0.8 * (1.0 - smoothstep(0.02, 0.035, edge)));
        }
    }

    return finish(apply_fog(col, in.rel, in.position.xy, f, lifted, smp), in.position.xy, 1.0);
}

// ---- ground plants ------------------------------------------------------------------------

// Two pictures crossed in an X over a column (plants.odin), set off its middle, turned and sized
// by its hash. They thin out from PLANT_NEAR to PLANT_FAR, each sinking into the ground as it
// reaches its own distance, so the edge of where they are drawn is never a line.
constant float PLANT_NEAR = 70.0, PLANT_FAR = 190.0;   // render.odin skips chunks beyond PLANT_FAR

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
};

vertex PlantV vs_plant(QuadIn q [[stage_in]], uint vid [[vertex_id]],
                       constant Frame &f [[buffer(0)]], constant Draw &d [[buffer(1)]]) {
    uint v = vid < 4u ? vid : vid < 6u ? 3u : vid - 2u;   // ten vertices: one picture, two that join nothing, the other
    uint plane = vid < 5u ? 0u : 1u, c = vid == 5u ? 0u : v & 3u;
    uint kind = uint(ushort(q.a.w)), h = q.b.x;
    float pictures = (kind >> 8u) != 0u ? 2.0 : 1.0;
    float r0 = float(h & 255u) / 255.0, r1 = float(h >> 8u) / 255.0;
    float3 foot = d.origin.xyz + float3(q.a.xyz) + float3(0.2 + 0.6 * r0, 0.0, 0.2 + 0.6 * r1);
    float reach = mix(PLANT_NEAR, PLANT_FAR, fract(r0 * 13.7 + r1 * 5.3));
    float size = float(q.b.y) / 100.0 * (1.0 - smoothstep(0.8 * reach, reach, length(foot)));
    float turn = float(plane) * 1.571 + fract(r0 * 7.1 + r1 * 3.3) * 1.571;   // any turn: an X repeats every quarter
    float across = float(c & 1u) * 2.0 - 1.0, rise = float(c >> 1u) * pictures * size;
    float3 p = foot + float3(cos(turn), 0.0, sin(turn)) * (0.7071 * size * across) + float3(0.0, rise, 0.0);
    float3 world = foot + f.cam.xyz;
    p.xz += rise * 0.03 * sin(f.sun.w * 1.6 + world.x * 0.35 + world.z * 0.27) * float2(0.8, 0.6);   // the wind stirs the tops
    PlantV o;
    o.rel = p;
    o.position = f.view_proj * float4(p, 1.0);
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
                         texture2d<float> lifted [[texture(2)]], sampler smp [[sampler(2)]]) {
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
    float lit = ndl > 0.0 ? shadow_at(in.rel, in.soft, f, shadow_map, shadow_smp) * shade : 0.0;
    float ao = mix(0.5, 1.0, in.ao) * mix(0.6, 1.0, saturate(in.up / 0.6));   // darker toward the root, in the plant's own shade
    float sky = 1.0 - float((in.info >> 4u) & 15u) / 15.0;
    float3 col = tex.rgb * (sun_light(sun) * ndl * lit * mix(1.0, ao, 0.45) + sky_ambient(in.soft, sun, f.weather.x) * ao * sky * mix(0.7, 1.0, shade));
    return finish(apply_fog(col, in.rel, in.position.xy, f, lifted, smp), in.position.xy, a);
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
                       texture2d<float> lifted [[texture(0)]], sampler smp [[sampler(0)]]) {
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float3 d = normalize(f.cam_f.xyz + f.cam_r.xyz * ndc.x + f.cam_u.xyz * ndc.y);
    float3 col = sky_color(d, f.sun.xyz, f.weather.x);
    col += sun_light(f.sun.xyz) * 6.0 * smoothstep(0.99955, 0.9998, dot(d, f.sun.xyz)) * step(0.0, d.y);
    float4 c = clouds(d, 1e6, in.position.xy, f, lifted, smp);
    return finish(col * c.w + c.rgb, in.position.xy, 1.0);
}

struct WaterV {
    float4 position [[position]];
    float3 rel;
    float2 river;   // x: -1 to 1 across a river ribbon, y: 1 for river water down to 0 for the sea
    float2 flow;    // metres a second, where the water is simulated
    float3 kind;    // x: 1 for simulated water, y: 0 for level water to 1 for falling, z: depth
    float roof;     // the share of it under a roof of rock
};

// The sea beyond the simulated water: one sheet at sea level.
vertex WaterV vs_water(uint vid [[vertex_id]], constant Frame &f [[buffer(0)]]) {
    float2 c = float2(vid & 1u, vid >> 1u) * 2.0 - 1.0;
    WaterV o;
    o.rel = float3(c.x * 60000.0, f.cam.w - f.cam.y, c.y * 60000.0);
    o.river = float2(0.0);
    o.flow = float2(0.0);
    o.kind = float3(0.0, 0.0, 10.0);
    o.roof = 0.0;
    o.position = f.view_proj * float4(o.rel, 1.0);
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
    o.position = f.view_proj * float4(o.rel, 1.0);
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
    float quarters = floor(m.w * 0.5);   // water.odin packs the share under a roof in whole twos over the falling
    o.kind = float3(1.0, m.w - 2.0 * quarters, m.z);
    o.roof = quarters * 0.25;
    o.position = f.view_proj * float4(o.rel, 1.0);
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
                         texture2d<float> lifted [[texture(1)]], sampler smp [[sampler(1)]]) {
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
    float fresnel = 0.02 + 0.98 * pow(1.0 - saturate(dot(-rd, N)), 5.0);
    // A river is shallower and clearer than the sea, and thins to nothing at its edges.
    float3 body = mix(float3(0.010, 0.045, 0.060), float3(0.022, 0.070, 0.058), in.river.y);
    float3 mirrored = sky_color(float3(r.x, abs(r.y), r.z), sun, f.weather.x) * (1.0 - 0.35 * in.river.y);   // banks and trees dim a river's sky
    float above = (f.weather.y - f.cam.y - in.rel.y) / max(abs(r.y), 0.02);   // the cloud base over the reflected ray
    if (above > 0.0) mirrored = mix(mirrored, sky_ambient(float3(0, 1, 0), sun, f.weather.x) * 0.9 + sun_light(sun) * 0.3,
                                    0.7 * smoothstep(0.0, 200.0, cloud_top(in.rel.xz + r.xz * above, f, lifted, smp, 0.0)) * (1.0 - haze(r * above, f)));
    mirrored *= 1.0 - 0.9 * in.roof;   // under a roof it mirrors the dark rock
    float shade = cloud_shade(in.rel, f, lifted, smp);
    float3 col = mix(body * (0.15 + 0.85 * daylight(sun)) * (0.5 + 0.5 * shade) * (1.0 - 0.7 * in.roof), mirrored, fresnel);
    col += sun_light(sun) * 2.5 * shade * pow(saturate(dot(r, sun)), 600.0) * (1.0 - in.roof);
    float alpha = mix(mix(0.80, 0.62, in.river.y), 1.0, fresnel);
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
        return finish(apply_fog(whitish * (0.8 + 0.3 * strands), in.rel, in.position.xy, f, lifted, smp), in.position.xy, 0.92 * a);
    }

    // White water. On a fall it runs down in streaks. On the level it is foam carried by
    // the flow: none in slow water, patches as it quickens, nearly solid below a fall.
    float sheet = smoothstep(0.5, 0.9, 1.0 - abs(geometric.y));
    float streaks = vnoise(float2((w.x + w.y) * 4.0, (in.rel.y + f.cam.y) * 0.7 + t * 3.5));
    float churn = max(smoothstep(1.3, 3.2, speed), in.kind.y);
    float foam = smoothstep(0.0, 0.3, carried - (1.05 - 0.8 * churn));   // never solid: churning water is foam in patches, carried off
    float white = mix(foam * 0.85, in.kind.y * (0.25 + 0.6 * streaks), sheet);
    col = mix(col, whitish * (0.75 + 0.35 * carried), white);
    alpha = mix(alpha, 0.9, white);
    return finish(apply_fog(col, in.rel, in.position.xy, f, lifted, smp), in.position.xy, alpha);
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
