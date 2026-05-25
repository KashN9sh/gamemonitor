#include <metal_stdlib>
using namespace metal;

// Полноэкранный треугольник, охватывающий весь экран без vertex buffer.
// uv: (0,0) — левый верх, (1,1) — правый низ.
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut yuvVertex(uint vid [[vertex_id]]) {
    const float2 verts[3] = {
        float2(-1.0, -3.0),
        float2(-1.0,  1.0),
        float2( 3.0,  1.0)
    };
    const float2 uvs[3] = {
        float2(0.0, 2.0),
        float2(0.0, 0.0),
        float2(2.0, 0.0)
    };

    VertexOut out;
    out.position = float4(verts[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

// rgb = colorMatrix * (yuv - bias). Bias переносит Y/UV в нулевой диапазон.
// colorMatrix включает в себя поправку видео/полного диапазона.
struct YUVUniforms {
    float4 row0;
    float4 row1;
    float4 row2;
    float4 bias;
};

fragment float4 yuvFragment(VertexOut in [[stage_in]],
                            texture2d<float> yPlane [[texture(0)]],
                            texture2d<float> cbcrPlane [[texture(1)]],
                            constant YUVUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float y = yPlane.sample(s, in.uv).r;
    float2 cbcr = cbcrPlane.sample(s, in.uv).rg;

    float3 yuv = float3(y, cbcr.x, cbcr.y) - u.bias.xyz;
    float3 rgb = float3(
        dot(u.row0.xyz, yuv),
        dot(u.row1.xyz, yuv),
        dot(u.row2.xyz, yuv)
    );

    return float4(saturate(rgb), 1.0);
}

// Сэмпл из RGBA текстуры (после YUV→RGB или после MetalFX) в drawable.
// Используется при scaleMode = letterbox или для прямого вывода без апскейла.
struct BlitVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct BlitUniforms {
    float2 dstScale; // как растянуть треугольник
    float2 dstOffset; // смещение в clip space (для letterbox)
};

vertex BlitVertexOut blitVertex(uint vid [[vertex_id]],
                                constant BlitUniforms &u [[buffer(0)]]) {
    const float2 verts[3] = {
        float2(-1.0, -3.0),
        float2(-1.0,  1.0),
        float2( 3.0,  1.0)
    };
    const float2 uvs[3] = {
        float2(0.0, 2.0),
        float2(0.0, 0.0),
        float2(2.0, 0.0)
    };

    BlitVertexOut out;
    float2 v = verts[vid] * u.dstScale + u.dstOffset;
    out.position = float4(v, 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

fragment float4 blitFragment(BlitVertexOut in [[stage_in]],
                             texture2d<float> source [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return source.sample(s, in.uv);
}
