# Natural capture — minimize Apple processing

Build **125** · Branch `cursor/collapsed-hide-hist-keep-shutter-67bc`

## Thesis
iPhone stills get heavy computational photography (Smart HDR / Deep Fusion / tone fusion). Shutter’s default is **natural**: deliver something closer to what the sensor saw.

There is **no public API** to disable Deep Fusion by name. The real levers:

| Lever | Natural (default) | Polished |
|---|---|---|
| `maxPhotoQualityPrioritization` | `.speed` | `.quality` |
| Per-capture `photoQualityPrioritization` | `.speed` | `.quality` |
| Max photo dimensions | ≤ ~12MP | largest supported |
| Auto deferred photo delivery | off | off |
| Zero shutter lag | off | off |
| `isAppleProRAWEnabled` | `false` | allowed |
| RAW pixel format | Bayer preferred | first available |
| Virtual device fusion | off | off |
| Auto red-eye | off | off |
| Content-aware distortion | off | device default |
| Still-image stabilization | off | device default |
| Active color space | forced sRGB / SDR | device default |
| Low-light video boost | off | device default |
| Responsive capture | off | device default |

`.speed` = WYSIWYG stills with light noise reduction only (WWDC21).
Capping at ~12MP avoids the 24/48MP deferred / heavy-ISP path that produced
crunchy halos and blown highlights with Film/FX off (Build 123). Build 125
also forces sRGB/SDR, disables digital still stabilization, low-light video
boost, and responsive capture.

## Public API boundary
Apple does **not** offer a public switch to turn off all ISP operations in
HEIC/JPEG. `Natural capture` uses every supported control above, but it remains
a lightly processed WYSIWYG still. For a sensor-first deliverable, select
**RAW**: Shutter prefers Bayer DNG and writes that clean DNG as a sibling in
Photos; the companion HEIC remains for the in-app Field Book.

## Honest save path (Build 122–123)
Clean captures (no film / Lens FX bake, FULL aspect, upright) keep the **original AVFoundation HEIC/JPEG bitstream** and write it to Photos via `PHAssetResourceType.photo`.

Portrait stills that arrive sideways (photo-connection rotation missed) are repaired to upright SDR pixels and re-encoded — never left EXIF-dependent.

When looks bake or aspect crop rewrites pixels, Photos gets a fresh HEIC @ 0.95 (JPEG @ 0.97 fallback). In-app gallery archives at JPEG 0.97 after an SDR redraw (`preferredRange = .standard`) so HDR gain maps cannot tone-map into crunchy halos.

CI bake / preview working space is **Display P3**.

**Film / Lens FX still bake** into the processed companion when selected (WYSIWYG). Natural only reduces Apple’s ISP fusion — it does not strip looks. RAW DNG stays clean.

## Product
- Settings → **Image honesty** → Natural capture (default ON)
- Info bar shows **NAT** when natural is active
- Format pill still chooses HEIC / JPEG / RAW; RAW uses Bayer when the device exposes it
