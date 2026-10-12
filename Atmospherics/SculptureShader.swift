import Foundation

/// The sculpture's Metal shader, compiled when the app first draws it (the system compiles Metal
/// at run time, so the project builds without Xcode's separate Metal toolchain).
enum SculptureShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// The soundscape as a sculpture: a soft body of light for each sound, merging where they meet,
// lit like frosted glass with light inside. Seen through the same camera as Layers (see
// `SculptureCamera` in Sculpture.swift), so labels drawn over it line up. Optionally it stands on
// a ground disc with contour footprints, soft shadows and the rim where sounds fall silent.

struct Blob {
    float4 sphere;   // center xyz, radius
    float4 color;    // linear rgb, w unused
};

struct Uniforms {
    float4 bounds;       // a sphere around every blob and its glow
    float2 size;         // drawable, pixels
    float2 center;       // where the camera looks, pixels
    float focal;         // pixels
    float distance;
    float yaw;
    float pitch;
    float smoothness;    // how readily blobs merge
    float glow;          // halo strength around the body
    float ground;        // 1 draws the ground
    float time;
    int count;
    float exposure;      // a lightning flash brightens everything
    float wobble;        // how much the surface ripples, slowly
    float pad1;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut sculptureVertex(uint vid [[vertex_id]]) {
    // One triangle covering the screen.
    float2 p = float2((vid << 1) & 2, vid & 2);
    VertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

/// Camera space (x right, y up, z into the screen) to the world, the inverse of the turn and
/// tilt in SculptureCamera.project.
static float3 toWorld(float3 v, float yaw, float pitch) {
    float y = v.y * cos(pitch) - v.z * sin(pitch);
    float z1 = v.y * sin(pitch) + v.z * cos(pitch);
    return float3(v.x * cos(yaw) + z1 * sin(yaw), y, -v.x * sin(yaw) + z1 * cos(yaw));
}

static float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// The surface ripples slowly, like something alive (only on the home screen).
constant float rippleSpeed = 0.6;

static float body(float3 p, constant Blob *b, int n, float k, float wobble = 0.0, float t = 0.0) {
    float d = 1e4;
    for (int i = 0; i < n; i++) {
        d = smin(d, length(p - b[i].sphere.xyz) - b[i].sphere.w, k);
    }
    if (wobble > 0.0) {
        float s = t * rippleSpeed;
        d += wobble * 0.014 * sin(p.x * 7.0 + s) * sin(p.y * 6.0 - s * 0.8) * sin(p.z * 8.0 + s * 0.7);
    }
    return d;
}

/// The color at a point: each sound's, weighted by how near its surface is.
static float3 tint(float3 p, constant Blob *b, int n) {
    float3 c = float3(0.0);
    float w = 0.0;
    for (int i = 0; i < n; i++) {
        float d = max(length(p - b[i].sphere.xyz) - b[i].sphere.w, 0.0);
        float wi = exp(-d * 10.0) * (0.25 + b[i].sphere.w);
        c += b[i].color.rgb * wi;
        w += wi;
    }
    return c / max(w, 1e-4);
}

static float3 normalAt(float3 p, constant Blob *b, int n, float k, float w, float t) {
    const float e = 0.0025;
    const float2 h = float2(1.0, -1.0);
    return normalize(h.xyy * body(p + h.xyy * e, b, n, k, w, t) + h.yyx * body(p + h.yyx * e, b, n, k, w, t)
                     + h.yxy * body(p + h.yxy * e, b, n, k, w, t) + h.xxx * body(p + h.xxx * e, b, n, k, w, t));
}

/// How much light reaches a point on the ground past the body (soft-edged shadows).
static float shadow(float3 p, float3 l, constant Blob *b, int n, float k) {
    float s = 1.0, t = 0.02;
    for (int i = 0; i < 24 && t < 3.0; i++) {
        float d = body(p + l * t, b, n, k);
        s = min(s, 10.0 * d / t);
        if (s < 0.02) break;
        t += clamp(d, 0.02, 0.25);
    }
    return clamp(s, 0.0, 1.0);
}

/// The ground's own relief under the sounds, for contour footprints: a rise under each, as
/// high as the sound is loud.
static float relief(float2 q, constant Blob *b, int n) {
    float h = 0.0;
    for (int i = 0; i < n; i++) {
        float2 d = q - b[i].sphere.xz;
        h += (b[i].sphere.y + b[i].sphere.w) * exp(-dot(d, d) / 0.09);
    }
    return h;
}

fragment float4 sculptureFragment(VertexOut in [[stage_in]],
                                  constant Uniforms &u [[buffer(0)]],
                                  constant Blob *blobs [[buffer(1)]]) {
    float2 px = in.uv * u.size;
    float3 rd = normalize(toWorld(float3((px.x - u.center.x) / u.focal, -(px.y - u.center.y) / u.focal, 1.0), u.yaw, u.pitch));
    float3 ro = toWorld(float3(0.0, 0.0, -u.distance), u.yaw, u.pitch);
    // Light from the upper left of the view, so the form is always well lit as it turns.
    float3 light = normalize(toWorld(float3(-0.5, 0.8, -0.45), u.yaw, u.pitch));
    int n = u.count;
    float k = u.smoothness;

    // The ground, if any: where the ray meets y = 0 inside the disc.
    float tGround = 1e4;
    float3 g = float3(0.0);
    if (u.ground > 0.5 && rd.y < -1e-4) {
        float t = -ro.y / rd.y;
        float3 q = ro + rd * t;
        if (length(q.xz) < 1.2) { tGround = t; g = q; }
    }

    // The body: march only inside the sphere that holds everything.
    float3 oc = ro - u.bounds.xyz;
    float bq = dot(oc, rd);
    float disc = bq * bq - (dot(oc, oc) - u.bounds.w * u.bounds.w);
    float tHit = 1e4, minD = 1e4;
    float3 nearest = ro;
    if (n > 0 && disc > 0.0) {
        float s = sqrt(disc);
        float t = max(0.0, -bq - s), tEnd = min(-bq + s, tGround);
        for (int i = 0; i < 72 && t < tEnd; i++) {
            float3 p = ro + rd * t;
            float d = body(p, blobs, n, k, u.wobble, u.time);
            if (d < minD) { minD = d; nearest = p; }
            if (d < 0.0015) { tHit = t; break; }
            t += d * 0.92;
        }
    }

    // Premultiplied: `light` is what reaches the eye, `alpha` how much it covers what's behind.
    float3 lightOut = float3(0.0);
    float alpha = 0.0;
    float bodyCover = 0.0;

    if (tHit < 1e4) {
        float3 p = ro + rd * tHit;
        float3 nrm = normalAt(p, blobs, n, k, u.wobble, u.time);
        float3 base = tint(p, blobs, n);
        float3 v = -rd;
        float wrap = clamp((dot(nrm, light) + 0.55) / 1.55, 0.0, 1.0);
        float facing = clamp(dot(nrm, v), 0.0, 1.0);
        float fres = pow(1.0 - facing, 2.6);
        float spec = pow(clamp(dot(nrm, normalize(light + v)), 0.0, 1.0), 80.0);
        // Folds where lobes meet are darker.
        float ao = clamp(body(p + nrm * 0.09, blobs, n, k) / 0.09, 0.55, 1.0);
        // Light inside: the body glows from within, brightest at its thin edges.
        lightOut = base * (0.28 + 0.62 * wrap) * mix(0.8, 1.0, ao)
                 + base * 0.22
                 + mix(base, float3(1.0), 0.6) * fres * 0.9
                 + float3(1.0) * spec * 0.28;
        alpha = 1.0;
        bodyCover = 1.0;
    } else if (tGround < 1e4) {
        // The ground: faint, lit by the sounds above it, with their shadows and contour lines.
        float r = length(g.xz);
        float fade = smoothstep(1.2, 0.9, r);
        float3 spill = n > 0 ? tint(g, blobs, n) : float3(0.5);
        float near = n > 0 ? exp(-max(body(g, blobs, n, k), 0.0) * 3.5) : 0.0;
        float lit = n > 0 ? shadow(g + float3(0.0, 0.01, 0.0), light, blobs, n, k) : 1.0;
        float cover = 0.5 * fade;
        lightOut = (float3(0.012, 0.016, 0.022) + spill * (0.05 + 0.3 * near) * mix(0.65, 1.0, lit)) * cover;
        alpha = cover;

        // Contour lines of the relief, brighter near the sounds.
        float h = relief(g.xz, blobs, n) * 9.0;
        float fw = max(fwidth(h), 1e-4);
        float line = (1.0 - smoothstep(0.0, fw * 1.4, abs(fract(h + 0.5) - 0.5))) * fade;
        float strength = 0.08 + 0.45 * clamp(h / 9.0, 0.0, 1.0);
        lightOut += spill * line * strength;
        alpha = max(alpha, line * strength);

        // The rim, dashed, where a sound falls silent; and you, a small ring at the middle.
        float rimLine = exp(-pow((r - 1.0) / 0.004, 2.0)) * step(0.55, fract(atan2(g.z, g.x) * 24.0 / M_PI_F)) * 0.3;
        float you = min(1.0, exp(-pow((r - 0.075) / 0.005, 2.0)) + exp(-pow(r / 0.013, 2.0))) * 0.85;
        lightOut += float3(0.55) * rimLine + float3(0.92) * you;
        alpha = max(alpha, max(rimLine, you));
    }

    // A halo of the sounds' own light around the body, gone well before the edge of what's drawn.
    if (n > 0 && minD < 1e3) {
        float reach = max(minD, 0.0);
        float glow = exp(-reach * 9.0) * smoothstep(0.42, 0.18, reach) * u.glow * (1.0 - bodyCover);
        float2 e = min(in.uv, 1.0 - in.uv);
        glow *= smoothstep(0.0, 0.12, min(e.x, e.y));
        lightOut += tint(nearest, blobs, n) * glow;
        alpha = max(alpha, glow * 0.85);
    }

    lightOut *= u.exposure;
    if (alpha <= 0.0) return float4(0.0);
    // To display: un-premultiply, encode, premultiply again.
    float3 straight = min(lightOut / alpha, float3(4.0));
    return float4(pow(straight, 1.0 / 2.2) * alpha, alpha);
}
"""#
}
