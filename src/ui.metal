#include <metal_stdlib>
using namespace metal;

// The interface's one shader (ui.odin, docs/adr/0010): every part of every screen is a rectangle
// in the picture's pixels. A rectangle is a piece of the text atlas in one colour (a glyph, or its
// one white texel for a plain fill), a tile of a block as the world shows it, or one of the three
// signs. It is drawn over the finished picture, which is already encoded for the display, so the
// colours here are the display's own and blend as a browser blends them.

struct UiU { float4 screen; };   // xy: the picture's size in pixels

struct UiIn {
    float4 rect   [[attribute(0)]];   // x, y, width, height in pixels, from the picture's top left
    float4 uv     [[attribute(1)]];   // the atlas from its top left to its bottom right, in texels; or how many times the tile repeats
    float4 colour [[attribute(2)]];
    float4 extra  [[attribute(3)]];   // x: 1 + the layer of a block's tile, or 0; y: the shape; z: pixels its edge fades over; w: where it begins to fade toward its right, 0 for never
};

struct UiV {
    float4 position [[position]];
    float2 uv;
    float2 local;                 // 0, 0 at its top left to 1, 1
    float4 colour [[flat]];
    float4 extra [[flat]];
    float2 size [[flat]];
};

vertex UiV vs_ui(UiIn q [[stage_in]], uint vid [[vertex_id]], constant UiU &u [[buffer(0)]]) {
    float2 c = float2(vid & 1u, vid >> 1u);
    float2 p = q.rect.xy + c * q.rect.zw;
    UiV o;
    o.position = float4(p.x / u.screen.x * 2.0 - 1.0, 1.0 - p.y / u.screen.y * 2.0, 0.0, 1.0);
    o.uv = mix(q.uv.xy, q.uv.zw, c);
    o.local = c;
    o.colour = q.colour;
    o.extra = q.extra;
    o.size = q.rect.zw;
    return o;
}

fragment float4 fs_ui(UiV in [[stage_in]],
                      texture2d<float> atlas [[texture(0)]], sampler smp [[sampler(0)]],
                      texture2d_array<float> blocks [[texture(1)]], sampler block_smp [[sampler(1)]]) {
    float4 c = in.colour;
    int shape = int(in.extra.y + 0.5);
    if (in.extra.x > 0.5) {
        // A block's tile, lit as the noon sun lights it and encoded as the world's picture is (finish, shaders.metal).
        float3 t = blocks.sample(block_smp, in.uv, uint(in.extra.x - 0.5), level(0.0)).rgb * 2.0;
        t = saturate((t * (2.51 * t + 0.03)) / (t * (2.43 * t + 0.59) + 0.14));
        c.rgb *= pow(t, float3(1.0 / 2.2));
    } else if (shape == 0) {
        c.a *= atlas.sample(smp, in.uv / float2(atlas.get_width(), atlas.get_height())).r;
    }
    // The signs: a disc, a diamond and a triangle, each with an edge a pixel soft.
    float2 p = (in.local - 0.5) * in.size;   // pixels from its middle
    float reach = 0.5 * min(in.size.x, in.size.y);
    if (shape == 1) c.a *= saturate(reach - length(p) + 0.5);
    if (shape == 2) c.a *= saturate((reach - abs(p.x) - abs(p.y)) * 0.7071 + 0.5);
    if (shape == 3) c.a *= saturate(min(reach - p.y, (p.y + reach - 2.0 * abs(p.x)) * 0.4472) + 0.5);   // its point up
    if (in.extra.z > 0.0) {   // a shadow: it fades toward every edge
        float2 e = min(in.local, 1.0 - in.local) * in.size / in.extra.z;
        c.a *= smoothstep(0.0, 1.0, saturate(e.x)) * smoothstep(0.0, 1.0, saturate(e.y));
    }
    if (in.extra.w > 0.0) c.a *= 1.0 - smoothstep(in.extra.w, 1.0, in.local.x);
    return c;
}
