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
// Anisotropic brushed steel — real metal grain + cool sheen, not plastic gloss.
[[ stitchable ]] half4 metallicSurface(
    float2 position,
    half4 color,
    float2 size,
    float roughness,
    float2 lightPos
) {
    float2 uv = position / size;

    // Softer brush — matte steel, less try-hard texture
    float brushed = noise(float2(uv.x * 280.0, uv.y * 14.0)) * roughness;
    float brushed2 = noise(float2(uv.x * 90.0, uv.y * 6.0)) * roughness * 0.65;
    float micro = (noise(uv * 420.0) - 0.5) * roughness * 0.30;

    // Anisotropic specular streak (brushed metal, not mirror chrome)
    float2 lightDir = normalize(lightPos - uv);
    float ndl = max(dot(lightDir, float2(0.18, 0.98)), 0.0);
    float soft = pow(ndl, 6.0) * 0.22;
    float streak = pow(ndl, 22.0) * 0.10;
    float specular = soft + streak;

    // Neutral rim — no cool blue cast on press
    float edge = length(uv - float2(0.5, 0.5)) * 2.0;
    float fresnel = pow(smoothstep(0.60, 1.0, edge), 1.6) * 0.14;

    half3 result = color.rgb;
    // Neutral steel cast (was cool blue — read as cyan on press)
    result = mix(result, half3(result.r * 0.94, result.g * 0.96, result.b * 1.02), half(0.28));
    result += half3((brushed * 0.14 + brushed2 * 0.11 + micro) * 0.95);
    result += half3(specular * 0.28) * half3(0.92, 0.94, 0.97);
    result += half3(fresnel) * half3(0.75, 0.78, 0.84);
    // Raised contact shadow — mixes with UI drop shadow
    result *= half(1.0 - smoothstep(0.50, 1.05, uv.y) * 0.22);

    return half4(clamp(result, 0.0h, 1.0h), color.a);
}

// MARK: - Shutter Button Metal Surface
// Photorealistic concave machined chrome shutter button
// Key insight: real turned metal grooves are MICROSCOPIC - you never see individual rings.
// What you see is the anisotropic specular reflection they produce: a bright crescent/arc
// that sweeps across the concave surface. The surface reads as smooth polished metal
// with a characteristic light band from the lathe-turned micro-texture.

float metalNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = random(i);
    float b = random(i + float2(1, 0));
    float c = random(i + float2(0, 1));
    float d = random(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

[[ stitchable ]] half4 shutterButtonMetal(
    float2 position,
    half4 color,
    float2 size,
    float pressed
) {
    float2 uv = position / size;
    float2 center = float2(0.5, 0.5);
    float2 dc = uv - center;
    float dist = length(dc);
    float r = dist * 2.0; // 0 center, 1 edge

    if (dist > 0.50) return half4(0);

    float2 radDir = dist > 0.001 ? dc / dist : float2(0);
    float angle = atan2(dc.y, dc.x);

    // ==========================================================
    // CONVEX DOME - slightly raised, like a real shutter release
    // ==========================================================
    // Gentle dome: center is highest, edges slope away.
    // When pressed, dome flattens.
    float dome = mix(0.30, 0.08, pressed); // nearly flat when fully pressed
    float height = dome * (1.0 - r * r);

    // Surface normal - dome normals tilt INWARD (toward center) at edges.
    // This means center reflects straight back (bright), edges reflect
    // away from viewer (darker, more fresnel).
    float3 N = normalize(float3(radDir * r * dome * 2.0, 1.0));

    // ==========================================================
    // LATHE TEXTURE - felt through lighting, not seen as rings
    // ==========================================================
    // High frequency so individual lines merge into texture.
    // The effect comes from how they scatter specular highlights,
    // not from seeing individual bright/dark bands.
    float gp = dist * size.x; // 0 to 32 for 64px button

    // Dense concentric grooves - many frequencies layered
    float lathe = sin(gp * 2.8) * 0.35
                + sin(gp * 3.5 + 0.7) * 0.25
                + sin(gp * 5.2) * 0.20
                + sin(gp * 8.0 + 1.3) * 0.20;

    // Circumferential noise breaks up any visible pattern
    float latheNoise = metalNoise(float2(angle * 10.0, dist * 30.0));
    lathe *= mix(0.4, 1.0, latheNoise);

    // Derivative for normal perturbation
    float latheDeriv = cos(gp * 2.8) * 0.35
                     + cos(gp * 3.5 + 0.7) * 0.25
                     + cos(gp * 5.2) * 0.20
                     + cos(gp * 8.0 + 1.3) * 0.20;
    latheDeriv *= mix(0.4, 1.0, latheNoise);

    // Additional noise-based micro grain
    float microGrain = metalNoise(float2(dist * 100.0, angle * 3.0));
    microGrain += metalNoise(float2(dist * 200.0, angle * 6.0)) * 0.5;
    microGrain = (microGrain / 1.5 - 0.5);

    float3 Ng = N;
    // Moderate normal perturbation - enough to break up specular
    Ng.xy += radDir * (latheDeriv * 0.14 + microGrain * 0.05);
    Ng = normalize(Ng);

    // ==========================================================
    // LIGHTING - simple, physically motivated
    // ==========================================================
    float3 V = float3(0, 0, 1);

    // Key light upper-left
    float3 L1 = normalize(float3(-0.4, -0.5 - pressed * 0.1, 0.8));
    // Fill light right
    float3 L2 = normalize(float3(0.5, -0.25 - pressed * 0.1, 0.65));
    // Rim from below
    float3 L3 = normalize(float3(0.0, 0.45, 0.35));

    // ==========================================================
    // SPECULAR - soft Blinn-Phong, let the geometry do the work
    // ==========================================================
    // The convex dome creates a bright center highlight that
    // fades toward edges. Soft, broad specular for natural look.

    float3 specTotal = float3(0);
    float diffTotal = 0.0;

    // Light 1 - key (warm)
    {
        float NdL = max(dot(Ng, L1), 0.0);
        float3 H = normalize(L1 + V);
        float NdH = max(dot(Ng, H), 0.0);

        // Broad glow + very tight hot peak - polished chrome throws
        // a pinpoint specular, not a soft sheen
        float soft = pow(NdH, 5.0) * 0.35;
        float tight = pow(NdH, 180.0) * 0.90;
        float spec = (soft + tight) * NdL;

        specTotal += spec * float3(1.0, 0.97, 0.92) * 1.6;
        diffTotal += NdL * 0.65;
    }

    // Light 2 - fill (cool)
    {
        float NdL = max(dot(Ng, L2), 0.0);
        float3 H = normalize(L2 + V);
        float NdH = max(dot(Ng, H), 0.0);

        float soft = pow(NdH, 5.0) * 0.35;
        float tight = pow(NdH, 180.0) * 0.75;
        float spec = (soft + tight) * NdL;

        specTotal += spec * float3(0.90, 0.93, 1.0) * 0.70;
        diffTotal += NdL * 0.25;
    }

    // Light 3 - rim
    {
        float NdL = max(dot(Ng, L3), 0.0);
        float3 H = normalize(L3 + V);
        float NdH = max(dot(Ng, H), 0.0);

        float spec = pow(NdH, 8.0) * NdL;
        specTotal += spec * float3(0.85, 0.85, 0.9) * 0.35;
        diffTotal += NdL * 0.1;
    }

    // ==========================================================
    // CHROME MATERIAL
    // ==========================================================
    float3 F0 = float3(0.85, 0.83, 0.80);
    F0 *= mix(1.0, 0.65, pressed);

    float NdV = max(dot(N, V), 0.0);
    float3 fresnel = F0 + (1.0 - F0) * pow(1.0 - NdV, 5.0);

    // Very dark base - metal reads as dark with bright reflections
    float3 chromeBase = mix(float3(0.06, 0.06, 0.07), float3(0.03, 0.03, 0.04), pressed);

    // ==========================================================
    // ENVIRONMENT REFLECTION - the key to looking real
    // ==========================================================
    // Chrome is essentially a mirror. The convex dome focuses
    // the sky reflection at center, camera body at edges.
    float3 reflDir = reflect(-V, Ng);

    // Broad sky/ground
    float skyMix = smoothstep(-0.15, 0.45, reflDir.y);
    float3 envColor = mix(
        float3(0.002, 0.002, 0.005), // near-black (camera body)
        float3(0.58, 0.58, 0.64),    // bright overhead
        skyMix
    );
    // Hard horizon band - mirrors reflect a sharp light/dark boundary,
    // and that contrast edge is what makes chrome read as chrome
    float horizon = 1.0 - smoothstep(0.0, 0.08, abs(reflDir.y - 0.12));
    envColor += float3(0.30, 0.30, 0.33) * horizon;

    // Organic variation
    float env1 = metalNoise(reflDir.xy * 2.5 + 0.7);
    float env2 = metalNoise(reflDir.xy * 5.0 + 2.3);
    envColor *= (0.80 + (env1 * 0.55 + env2 * 0.35) * 0.5);

    // Warm light source reflection
    float warmZone = smoothstep(0.8, 0.0, length(reflDir.xy - float2(-0.25, 0.35)));
    envColor += float3(0.25, 0.20, 0.14) * warmZone * warmZone;

    // ==========================================================
    // COMPOSE
    // ==========================================================
    float3 result = float3(0);

    // Ambient (nearly black for chrome - all light comes from reflections)
    result += chromeBase * 0.06;

    // Diffuse (chrome has essentially none - it's all reflection)
    result += chromeBase * diffTotal * 0.03;

    // Specular (broad, natural arcs from bowl geometry)
    result += fresnel * specTotal;

    // Environment reflection (chrome is a mirror - this dominates)
    result += fresnel * envColor * 1.05;

    // Anisotropic lathe crescents: a bright arc sweeping toward the key
    // light with a dark mirrored arc opposite - the signature look of
    // machined, lathe-turned metal
    {
        float2 keyDir = normalize(float2(-0.55, -0.60));
        float facing = dot(radDir, keyDir);
        float annulus = smoothstep(0.18, 0.45, r) * smoothstep(0.95, 0.62, r);
        float arcBright = pow(max(facing, 0.0), 2.5) * annulus;
        float arcDark = pow(max(-facing, 0.0), 2.5) * annulus;
        result += arcBright * float3(0.42, 0.41, 0.39) * (1.0 - pressed * 0.4);
        result -= arcDark * float3(0.12, 0.12, 0.13);
    }

    // Lathe texture - very subtle brightness modulation,
    // the real effect is through the normal perturbation above
    result *= (1.0 + lathe * 0.03 + microGrain * 0.015);

    // ==========================================================
    // DOME SHADING - center catches most light, edges fall off
    // ==========================================================
    // Gentle: a mirror's brightness comes from what it reflects,
    // not from surface shading
    float domeMod = 0.78 + height * 0.50;
    result *= domeMod;

    // ==========================================================
    // EDGE
    // ==========================================================
    // Machined chamfer catches light
    float rimMask = smoothstep(0.83, 0.89, r) * smoothstep(0.98, 0.91, r);
    result += rimMask * float3(0.30, 0.28, 0.26) * (diffTotal * 0.3 + 0.7);

    // Gap shadow
    float gapShadow = smoothstep(0.92, 0.99, r);
    result *= (1.0 - gapShadow * 0.75);

    // ==========================================================
    // FINAL
    // ==========================================================
    result.r *= 1.0 + metalNoise(uv * 10.0) * 0.008;
    result.b *= 1.0 - metalNoise(uv * 12.0 + 4.0) * 0.006;

    result = clamp(result, 0.0, 1.0);

    float mask = 1.0 - smoothstep(0.47, 0.50, dist);
    return half4(half3(result), mask);
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

// MARK: - Scanline Overlay (VHS viewfinder)
// Outputs alpha-varying black lines so it composites over any layer
// (including the camera preview) without needing a blend mode.
[[ stitchable ]] half4 scanlineOverlay(
    float2 position,
    half4 color,
    float lineWidth,
    float intensity
) {
    float scanline = sin(position.y * lineWidth) * 0.5 + 0.5;
    float alpha = pow(scanline, 2.0) * intensity;

    return half4(0.0, 0.0, 0.0, half(alpha) * color.a);
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
