#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Film Grain Shader
// Creates realistic analog film grain effect

float random(float2 st) {
    return fract(sin(dot(st.xy, float2(12.9898, 78.233))) * 43758.5453123);
}

float noise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);

    float a = random(i);
    float b = random(i + float2(1.0, 0.0));
    float c = random(i + float2(0.0, 1.0));
    float d = random(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

[[ stitchable ]] half4 filmGrain(
    float2 position,
    half4 color,
    float time,
    float intensity,
    float size
) {
    float2 uv = position / size;

    // Multi-octave noise for more realistic grain
    float grain = 0.0;
    grain += noise(uv * 100.0 + time * 10.0) * 0.5;
    grain += noise(uv * 200.0 - time * 15.0) * 0.3;
    grain += noise(uv * 400.0 + time * 20.0) * 0.2;

    // Normalize and apply intensity
    grain = (grain - 0.5) * intensity;

    // Add grain to color
    half3 result = color.rgb + half3(grain);

    return half4(result, color.a);
}

// MARK: - Frosted Glass Shader
// Creates realistic frosted glass blur effect

[[ stitchable ]] half4 frostedGlass(
    float2 position,
    SwiftUI::Layer layer,
    float radius,
    float time
) {
    half4 color = half4(0.0);
    float total = 0.0;

    // Sample in a circular pattern for blur
    for (float angle = 0.0; angle < 6.28318; angle += 0.5) {
        for (float r = 1.0; r <= radius; r += 1.0) {
            float2 offset = float2(cos(angle), sin(angle)) * r;
            // Add slight noise to offset for frosted effect
            offset += float2(
                random(position + float2(angle, r) + time) - 0.5,
                random(position + float2(r, angle) - time) - 0.5
            ) * 2.0;

            color += layer.sample(position + offset);
            total += 1.0;
        }
    }

    color /= total;

    // Add subtle noise for glass texture
    float n = noise(position * 0.5 + time) * 0.03;
    color.rgb += half3(n);

    return color;
}

// MARK: - Vignette Shader
[[ stitchable ]] half4 vignette(
    float2 position,
    half4 color,
    float2 size,
    float intensity,
    float radius
) {
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float dist = distance(uv, center);

    float vignette = smoothstep(radius, radius - 0.3, dist);
    vignette = mix(1.0 - intensity, 1.0, vignette);

    return half4(color.rgb * vignette, color.a);
}

// MARK: - Chromatic Aberration
[[ stitchable ]] half4 chromaticAberration(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float intensity
) {
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float2 dir = uv - center;

    float2 offsetR = position + dir * intensity;
    float2 offsetB = position - dir * intensity;

    half4 colorR = layer.sample(offsetR);
    half4 colorG = layer.sample(position);
    half4 colorB = layer.sample(offsetB);

    return half4(colorR.r, colorG.g, colorB.b, colorG.a);
}

// MARK: - Metallic Surface Shader
[[ stitchable ]] half4 metallicSurface(
    float2 position,
    half4 color,
    float2 size,
    float roughness,
    float2 lightPos
) {
    float2 uv = position / size;

    // Brushed metal texture
    float brushed = noise(float2(uv.x * 200.0, uv.y * 20.0)) * roughness;

    // Specular highlight
    float2 lightDir = normalize(lightPos - uv);
    float specular = pow(max(dot(lightDir, float2(0.0, 1.0)), 0.0), 32.0);

    // Fresnel effect at edges
    float fresnel = pow(1.0 - abs(uv.x - 0.5) * 2.0, 2.0) * 0.3;

    half3 result = color.rgb;
    result += half3(brushed * 0.1);
    result += half3(specular * 0.4);
    result += half3(fresnel);

    return half4(result, color.a);
}

// MARK: - Scanline Effect (CRT style)
[[ stitchable ]] half4 scanlines(
    float2 position,
    half4 color,
    float lineWidth,
    float intensity
) {
    float scanline = sin(position.y * lineWidth) * 0.5 + 0.5;
    scanline = pow(scanline, 2.0) * intensity + (1.0 - intensity);

    return half4(color.rgb * scanline, color.a);
}

// MARK: - Leica Vulcanite Texture Shader
// Creates realistic diamond/crosshatch pattern like Leica M camera body grip
[[ stitchable ]] half4 vulcaniteTexture(
    float2 position,
    half4 color,
    float scale,
    float intensity
) {
    // Scale UV for diamond pattern size (smaller scale = larger diamonds)
    float2 uv = position / scale;

    // Create diamond grid pattern
    // Rotate 45 degrees to get diamond orientation
    float2 rotated = float2(uv.x + uv.y, uv.x - uv.y) * 0.707;

    // Create repeating diamond cells
    float2 cell = fract(rotated * 8.0);  // 8.0 controls diamond density

    // Distance from center of each diamond cell creates the raised pyramid effect
    float2 centered = cell - 0.5;
    float diamond = 1.0 - (abs(centered.x) + abs(centered.y)) * 2.0;
    diamond = clamp(diamond, 0.0, 1.0);

    // Create the beveled edge effect (light on top-left, shadow on bottom-right)
    float highlight = smoothstep(0.3, 0.5, cell.x + cell.y);
    float shadow = smoothstep(0.3, 0.5, 2.0 - cell.x - cell.y);
    float bevel = (highlight - shadow) * 0.5;

    // Combine diamond shape with bevel for 3D effect
    float pattern = diamond * 0.3 + bevel * 0.7;

    // Add very subtle micro-texture for realism
    float microTexture = noise(uv * 200.0) * 0.1;

    // Apply pattern with intensity control
    float combined = (pattern + microTexture) * intensity;

    // Apply as visible light/shadow on the base color
    half3 result = color.rgb + half3(combined * 0.15);

    return half4(result, color.a);
}
