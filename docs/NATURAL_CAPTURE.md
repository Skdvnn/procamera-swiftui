# Natural capture — minimize Apple processing

Build **28** · Branch `cursor/natural-capture-landscape-1a29`

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
| Bake film/FX into JPEG | off (preview only) | on |

## Product
- Settings → **Image honesty** → Natural capture (default ON)
- Optional: **Bake film/FX into JPEG** when you want looks on the saved twin
- Info bar shows **NAT** when natural is active
- Format pill still chooses HEIC / JPEG / RAW; RAW uses Bayer when the device exposes it

## Also in this pass
- Expanded shutter hit-testing fixed (swipe only in gaps; higher drag threshold; ButtonStyle press)
- Landscape left/right enabled; compact chrome in landscape
- Curved ƒ edge readout while scrubbing the deck down into fullscreen
