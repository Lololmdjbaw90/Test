#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The frosted-glass texture (see `frostGrain` in Theme.swift): a fine, still
// grain of light and dark specks, like sugar frost on a window. Each speck is
// one point wide and never moves, so it costs next to nothing to draw.
static float frostHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

[[ stitchable ]] half4 frostGrain(float2 position, float strength) {
    float n = frostHash(floor(position)) - 0.5;
    // A few brighter flecks on top of the fine grain, for a frosty sparkle.
    float fleck = step(0.985, frostHash(floor(position * 0.5) + 17.0)) * 0.6;
    float light = max(n, 0.0) * 2.0 * strength + fleck * strength;
    float shade = max(-n, 0.0) * 2.0 * strength * 0.6;
    // Premultiplied: white specks add light, dark specks add a little shade.
    half a = half(clamp(light + shade, 0.0, 1.0));
    half white = half(clamp(light, 0.0, 1.0));
    return half4(white, white, white, a);
}
