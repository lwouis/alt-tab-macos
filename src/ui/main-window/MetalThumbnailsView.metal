#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut thumbnailVertex(
    uint vid [[vertex_id]],
    const device float4 *verts [[buffer(0)]]
) {
    VertexOut out;
    float4 v = verts[vid];
    out.position = float4(v.xy, 0.0, 1.0);
    out.uv = v.zw;
    return out;
}

fragment float4 thumbnailFragment(
    VertexOut in [[stage_in]],
    texture2d<float> yTex [[texture(0)]],
    texture2d<float> cbcrTex [[texture(1)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float y = yTex.sample(s, in.uv).r;
    float2 cbcr = cbcrTex.sample(s, in.uv).rg - float2(0.5, 0.5);

    float r = y + 1.402 * cbcr.y;
    float g = y - 0.344136 * cbcr.x - 0.714136 * cbcr.y;
    float b = y + 1.772 * cbcr.x;

    return float4(r, g, b, 1.0);
}
