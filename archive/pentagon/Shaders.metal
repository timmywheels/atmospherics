#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Corner colors in Field.layout order: white, blue, green, brown, pink.
constant float3 cornerColors[5] = {
    float3(0.93, 0.93, 0.95),
    float3(0.36, 0.55, 0.98),
    float3(0.40, 0.80, 0.45),
    float3(0.78, 0.50, 0.28),
    float3(0.96, 0.55, 0.68),
};

static float2 corner(int i) {
    float a = -M_PI_F / 2 + float(i) * 2 * M_PI_F / 5;
    return float2(cos(a), sin(a));
}

static float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash(i), b = hash(i + float2(1, 0));
    float c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
    float2 u = f * f * (3 - 2 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0, amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * vnoise(p);
        p = p * 2.03 + float2(1.7, 9.2);
        amp *= 0.5;
    }
    return v;
}

/// The blended color a dot shows, matching Mixer.mixColor.
static float3 tintAt(float2 p) {
    float3 tint = 0;
    float total = 0;
    for (int i = 0; i < 5; i++) {
        float2 d = p - corner(i);
        float g = exp(-dot(d, d) / 0.5);
        tint += cornerColors[i] * g;
        total += g;
    }
    return tint / total;
}

/// Fills the pentagon with domain-warped, aurora-like color. Each corner's color
/// swells with its noise level; dots glow, merge like liquid, and emit sound rings.
/// Coordinates match `Field`: unit space centered on the view, corners at radius 1.
[[ stitchable ]] half4 soundField(float2 position, half4 color,
                                  float2 size, float radius, float time,
                                  device const float *levels, int levelCount,
                                  device const float *dots, int dotValueCount,
                                  float playing) {
    float2 uv = (position - size * 0.5) / radius;
    float t = time;

    // Two layers of domain warping give the slow, smoky swirl.
    float2 q = float2(fbm(uv * 1.4 + float2(0.0, t * 0.05)),
                      fbm(uv * 1.4 + float2(5.2, -t * 0.04)));
    float2 r = float2(fbm(uv * 1.6 + 3.0 * q + float2(1.7, 9.2) + t * 0.06),
                      fbm(uv * 1.6 + 3.0 * q + float2(8.3, 2.8) - t * 0.05));
    float2 warped = uv + (r - 0.5) * 0.45;

    float3 col = 0;
    for (int i = 0; i < 5 && i < levelCount; i++) {
        float2 d = warped - corner(i);
        float g = exp(-dot(d, d) / 0.45);
        col += cornerColors[i] * g * (0.10 + 1.1 * levels[i]);
    }
    float pattern = fbm(uv * 2.5 + 2.5 * r + t * 0.08);
    col *= 0.35 + 1.1 * pattern;

    // Dots: metaball glow (nearby dots melt together) plus rippling sound rings.
    float field = 0;
    float3 glow = 0;
    for (int j = 0; j < dotValueCount / 2; j++) {
        float2 p = float2(dots[2 * j], dots[2 * j + 1]);
        float2 d = uv - p;
        float d2 = dot(d, d);
        float dist = sqrt(d2);
        float3 tint = tintAt(p);

        float k = 0.003 / (d2 + 0.0008);
        field += k;
        glow += tint * k;

        float wobble = fbm(d * 3.0 + t * 0.3) * 0.08;
        float ring = pow(0.5 + 0.5 * sin((dist + wobble) * 38.0 - t * 4.0), 10.0);
        col += tint * ring * exp(-dist * 3.5) * playing * 0.35;
    }
    if (field > 0) {
        col += (glow / field) * smoothstep(0.0, 3.0, field) * 0.9;
    }

    col *= 0.7 + 0.3 * playing;
    col += (hash(position + fract(t) * 100.0) - 0.5) * 0.035;   // film grain
    return half4(half3(col), 1);
}

/// Full-screen backdrop: near-black with a faint nebula tinted by the current mix.
[[ stitchable ]] half4 backdrop(float2 position, half4 color, float2 size, float time, half4 tint) {
    float2 uv = position / size.y;
    float n = fbm(uv * 2.0 + float2(time * 0.02, -time * 0.015));
    float n2 = fbm(uv * 4.0 + n * 2.0 - time * 0.03);
    float fromCenter = distance(position, float2(size.x * 0.5, size.y * 0.42)) / size.y;
    float glow = smoothstep(0.75, 0.0, fromCenter);

    float3 col = float3(0.022, 0.026, 0.045);
    col += float3(tint.rgb) * (0.04 + 0.16 * n2) * glow;
    col += (hash(position) - 0.5) * 0.02;
    return half4(half3(col), 1);
}
