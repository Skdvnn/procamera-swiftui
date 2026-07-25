# Natural capture — minimize Apple processing

Build **29** · Branch `cursor/natural-capture-landscape-1a29`

## Thesis
iPhone stills get heavy computational photography (Smart HDR / Deep Fusion / tone fusion). Shutter’s default is **natural**: deliver something closer to what the sensor saw.

There is **no public API** to disable Deep Fusion by name. The real levers:

| Lever | Natural (default) | Polished |
|---|---|---|
| `maxPhotoQualityPrioritization` | `.speed` | `.quality` |
| Per-capture `photoQualityPrioritization` | `.speed` | `.quality` |
| `isAppleProRAWEnabled` | `false` | allowed |
| RAW pixel format | Bayer preferred | first available |
| Virtual device fusion | off | off |
| Auto red-eye | off | off |

**Film / Lens FX always bake** into the processed HEIC/JPEG when selected (WYSIWYG). Natural only reduces Apple’s ISP fusion — it does not strip looks. RAW DNG stays clean.

## Effects safety (build 29)
- Thread-safe bake gate so live FX doesn’t fight still bake on the GPU
- Film still render uses the same downscale + software CIContext retries as Lens FX
- MTKView size-guards before `currentDrawable`; explicit `drawableSize` on layout
- Comic/Toon has a posterize+edges fallback if `CIComicEffect` is missing
- Live preview FX runs in an autoreleasepool with extent guards

## Product
- Settings → **Image honesty** → Natural capture (default ON)
- Info bar shows **NAT** when natural is active
- Format pill still chooses HEIC / JPEG / RAW; RAW uses Bayer when the device exposes it

## Also in this pass
- Expanded shutter hit-testing fixed (swipe only in gaps; higher drag threshold; ButtonStyle press)
- Landscape left/right enabled; compact chrome in landscape
- Curved ƒ edge readout while scrubbing the deck down into fullscreen
