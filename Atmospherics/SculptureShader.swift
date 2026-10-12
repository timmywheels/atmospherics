import Foundation

/// The sculpture's Metal shader, compiled when the app first draws it (the system compiles Metal
/// at run time, so the project builds without Xcode's separate Metal toolchain).
enum SculptureShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// The soundscape as a glass ghost: one form made of a soft body for each sound (bigger and
// higher the louder it is), merged where sounds are near, and seen through like colored glass:
// a faint glow inside, thicker where there's more of it, and a glowing edge where you look along
// its surface, with the far side's edge showing through. Seen through the same camera as Layers
// (`SculptureCamera` in Sculpture.swift), so labels drawn over it line up. In Layers it stands
// on a ground with the sounds' light pooled on it, contour footprints, the rim and you.

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
    float glow;          // halo strength around the form
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

/// The merged distance to the form and its color at a point, in one pass over the sounds. On
/// the home screen the surface ripples slowly, like something alive.
static float field(float3 p, constant Blob *b, int n, float k, float wobble, float time, thread float3 &color) {
    float d = 1e4, w = 0.0;
    float3 c = float3(0.0);
    for (int i = 0; i < n; i++) {
        float di = length(p - b[i].sphere.xyz) - b[i].sphere.w;
        d = smin(d, di, k);
        float wi = exp(-max(di, 0.0) * 10.0) * (0.25 + b[i].sphere.w);
        c += b[i].color.rgb * wi;
        w += wi;
    }
    color = c / max(w, 1e-4);
    if (wobble > 0.0) {
        float s = time * 0.6;
        d += wobble * 0.009 * sin(p.x * 7.0 + s) * sin(p.y * 6.0 - s * 0.8) * sin(p.z * 8.0 + s * 0.7);
    }
    return d;
}

static float3 fieldNormal(float3 p, constant Blob *b, int n, float k, float wobble, float time) {
    const float e = 0.0015;
    const float2 h = float2(1.0, -1.0);
    float3 c;
    return normalize(h.xyy * field(p + h.xyy * e, b, n, k, wobble, time, c) + h.yyx * field(p + h.yyx * e, b, n, k, wobble, time, c)
                     + h.yxy * field(p + h.yxy * e, b, n, k, wobble, time, c) + h.xxx * field(p + h.xxx * e, b, n, k, wobble, time, c));
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
    // Light from the upper left of the view, so the form is always lit the same way as it turns.
    float3 light = normalize(toWorld(float3(-0.5, 0.8, -0.45), u.yaw, u.pitch));
    int n = u.count;
    float k = u.smoothness, wob = u.wobble, time = u.time;

    // The ground, if any: where the ray meets y = 0 inside the disc.
    float tGround = 1e4;
    float3 g = float3(0.0);
    if (u.ground > 0.5 && rd.y < -1e-4) {
        float t = -ro.y / rd.y;
        float3 q = ro + rd * t;
        if (length(q.xz) < 1.2) { tGround = t; g = q; }
    }

    // Light from the form (premultiplied) and how much of what's behind still shows through.
    float3 lightOut = float3(0.0);
    float through = 1.0;
    float minD = 1e4;
    float3 nearest = ro;
    float3 oc = ro - u.bounds.xyz;
    float bq = dot(oc, rd);
    float disc = bq * bq - (dot(oc, oc) - u.bounds.w * u.bounds.w);
    if (n > 0 && disc > 0.0) {
        float s = sqrt(disc);
        float t = max(0.0, -bq - s), tEnd = min(-bq + s, tGround);
        // In: march to the surface.
        bool hit = false;
        float3 c;
        for (int i = 0; i < 120 && t < tEnd; i++) {
            float d = field(ro + rd * t, blobs, n, k, wob, time, c);
            if (d < minD) { minD = d; nearest = ro + rd * t; }
            if (d < 0.0006 + 0.0003 * t) { hit = true; t += d; break; }
            t += max(d * 0.9, 0.0008);
        }
        if (hit) {
            float3 pIn = ro + rd * t;
            float3 cIn;
            field(pIn, blobs, n, k, wob, time, cIn);
            float3 nIn = fieldNormal(pIn, blobs, n, k, wob, time);
            // Through: march inside to where it comes out, for its thickness and far edge.
            float tIn = t;
            t += 0.004;
            for (int i = 0; i < 80 && t < tEnd + 1.0; i++) {
                float d = field(ro + rd * t, blobs, n, k, wob, time, c);
                if (d > -(0.0006 + 0.0003 * t)) break;
                t += max(-d * 0.9, 0.0015);
            }
            float thick = t - tIn;
            float3 pOut = ro + rd * t;
            float3 nOut = fieldNormal(pOut, blobs, n, k, wob, time);
            float3 cOut;
            field(pOut, blobs, n, k, wob, time, cOut);

            float facingIn = clamp(dot(nIn, -rd), 0.0, 1.0);
            float facingOut = clamp(dot(nOut, rd), 0.0, 1.0);
            float edgeIn = pow(1.0 - facingIn, 2.6);
            float edgeOut = pow(1.0 - facingOut, 2.6);
            float body = 1.0 - exp(-thick * 2.0);
            float shade = 0.7 + 0.3 * clamp((dot(nIn, light) + 0.5) / 1.5, 0.0, 1.0);
            lightOut = cIn * (0.06 + 0.3 * body) * shade
                     + mix(cIn, float3(1.0), 0.15) * edgeIn * 0.75
                     + cOut * edgeOut * 0.4;
            through = 1.0 - clamp(0.05 + 0.15 * body, 0.0, 0.9);
        }
    }

    if (tGround < 1e4) {
        // The ground under it: faint, lit by the sounds above, with their contour footprints.
        float r = length(g.xz);
        float fade = smoothstep(1.2, 0.9, r);
        float3 spill = float3(0.0);
        for (int i = 0; i < n; i++) {
            float d = max(length(g - blobs[i].sphere.xyz) - blobs[i].sphere.w, 0.0);
            spill += blobs[i].color.rgb * exp(-d * 3.2);
        }
        float cover = 0.5 * fade;
        float3 groundLight = (float3(0.012, 0.016, 0.022) + spill * 0.22) * cover;
        float h = relief(g.xz, blobs, n) * 9.0;
        float fw = max(fwidth(h), 1e-4);
        float line = (1.0 - smoothstep(0.0, fw * 1.4, abs(fract(h + 0.5) - 0.5))) * fade;
        float strength = 0.08 + 0.45 * clamp(h / 9.0, 0.0, 1.0);
        float3 lineColor = spill / max(max(spill.r, max(spill.g, spill.b)), 0.2);
        groundLight += lineColor * line * strength * 0.5;
        cover = max(cover, line * strength);
        float rimLine = exp(-pow((r - 1.0) / 0.004, 2.0)) * step(0.55, fract(atan2(g.z, g.x) * 24.0 / M_PI_F)) * 0.3;
        float you = min(1.0, exp(-pow((r - 0.075) / 0.005, 2.0)) + exp(-pow(r / 0.013, 2.0))) * 0.85;
        groundLight += float3(0.55) * rimLine + float3(0.92) * you;
        cover = max(cover, max(rimLine, you));
        // Seen through the form.
        lightOut += groundLight * through;
        through *= 1.0 - cover;
    }
    float alpha = 1.0 - through;

    // A soft halo of each sound's own light around it (each its own, so colors blend without a
    // seam), gone well before the edge of what's drawn.
    if (n > 0) {
        float3 halo = float3(0.0);
        for (int i = 0; i < n; i++) {
            float3 c = blobs[i].sphere.xyz;
            float r = max(blobs[i].sphere.w, 1e-3);
            float3 o = ro - c;
            float b = dot(o, rd);
            if (b > 0.0) continue;
            float closest = sqrt(max(dot(o, o) - b * b, 0.0));
            float outside = max(closest - r, 0.0) / r;
            // Fainter over the form itself, so the glass stays clear; no edge where that changes.
            halo += blobs[i].color.rgb * exp(-outside * outside * 2.4) * smoothstep(1.9, 0.6, outside)
                  * mix(0.3, 1.0, smoothstep(0.0, 0.3, outside));
        }
        float2 e = min(in.uv, 1.0 - in.uv);
        float strength = u.glow * 0.32 * smoothstep(0.0, 0.12, min(e.x, e.y));
        lightOut += halo * strength * through;
        float m = max(halo.r, max(halo.g, halo.b));
        alpha = max(alpha, min(m, 1.0) * strength * 0.5);
    }

    lightOut *= u.exposure;
    // Soften the brightest light so it glows rather than burns to white.
    lightOut = 1.0 - exp(-lightOut * 1.1);
    return float4(pow(max(lightOut, 0.0), 1.0 / 2.2), clamp(alpha, 0.0, 1.0));
}
"""#
}
