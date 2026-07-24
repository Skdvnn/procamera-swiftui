# Overnight pro-pass goals (cursor/overnight-pro-pass-1a29)

Autonomous goal loops — ship what’s reasonable without diluting the Shutter / Darkroom / Field Book spine.

## Phase 1 — Truth / lock / monitors / flip (build 23)
- [x] Stop advertising fake controllable aperture (ƒ readout only when hardware reports it)
- [x] Info bar shows real aspect ratio (not hard-coded 1:1)
- [x] Aspect mask crops capture to match framing
- [x] Remove unused P·A·T mode state
- [x] RAW: bake graded companion to match preview (DNG stays clean)
- [x] Visible AE/AF lock (`L` on info bar)
- [x] One-tap return to auto (`A` on info bar)
- [x] Focus peaking toggle (viewfinder chrome)
- [x] Horizon / level indicator
- [x] Zebra highlight warning (deck mode icon)
- [x] Front/back camera switch
- [x] Persist grid / peaking / zebra / level via `@AppStorage`

## Phase 2 — Looks / compare / shutter / LE honesty (build 24)
- [x] Saved film+FX look recipes (bookmark menu + SAVE LOOK)
- [x] Hold-to-compare clean preview (long-press viewfinder)
- [x] Volume-button shutter
- [x] Long-exposure path label (HARDWARE vs STACKED)

## Out of scope (still)
- Video product, more Lens FX, Halide-grade scopes, social feed, fake aperture hardware
- Full proof PDF export / session map (next candidate)
