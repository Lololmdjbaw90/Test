#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Dyes a piece of clothing the picked colour (see BunnyDye.swift).
// Coloured pixels take the dye's own colour, keeping the drawing's light and
// shade: a pixel as light as the piece's typical colour (`anchor`) becomes
// exactly the dye, darker ones a darker dye, lighter ones fade towards white.
// White, grey and the dark outline (pixels with little colour) stay as drawn.
[[ stitchable ]] half4 bunnyDye(float2 position, half4 color, half4 dye, float anchor) {
    if (color.a <= 0.0h) { return color; }
    half3 rgb = color.rgb / color.a;
    half hi = max(rgb.r, max(rgb.g, rgb.b));
    half lo = min(rgb.r, min(rgb.g, rgb.b));
    half colourful = hi > 0.001h ? (hi - lo) / hi : 0.0h;
    half light = dot(rgb, half3(0.299h, 0.587h, 0.114h));
    half a = half(clamp(anchor, 0.15, 0.85));
    half3 dyed = light <= a
        ? dye.rgb * (light / a)
        : mix(dye.rgb, half3(1.0h), (light - a) / (1.0h - a));
    half amount = smoothstep(0.10h, 0.28h, colourful);
    half3 result = mix(rgb, dyed, amount);
    return half4(result * color.a, color.a);
}
