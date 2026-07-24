# Overnight pro-pass goals (cursor/overnight-pro-pass-1a29)

Autonomous goal loops — ship what’s reasonable without diluting the Shutter / Darkroom / Field Book spine.

## Loop 1 — Truth pass
- [x] Stop advertising fake controllable aperture (ƒ readout only when hardware reports it)
- [x] Info bar shows real aspect ratio (not hard-coded 1:1)
- [x] Aspect mask crops capture to match framing
- [x] Remove unused P·A·T mode state
- [x] RAW: bake graded JPEG/HEIC companion to match preview (DNG stays clean)

## Loop 2 — Lock + Auto
- [x] Visible AE/AF lock (`L` on info bar)
- [x] One-tap return to auto (`A` on info bar)

## Loop 3 — Pro monitors
- [x] Focus peaking toggle (viewfinder chrome)
- [x] Horizon / level indicator
- [x] Zebra highlight warning (deck mode icon)

## Loop 4 — Table stakes
- [x] Front/back camera switch
- [x] Persist grid / peaking / zebra / level via `@AppStorage`

## Out of scope (still)
- Video product, more Lens FX, Halide-grade scopes, social feed, fake aperture hardware
