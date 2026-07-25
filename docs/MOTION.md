# Shutter motion

Build **44** · `ShutterMotion` in `ContentView.swift`

Camera chrome uses **timing curves**, not bouncy springs. Cull/Darkroom keeps its own `CullMotion` system.

## Rules
1. Never attach `.animation` to a container that owns `FilteredCameraPreview`.
2. Freeze the live preview with `.transaction { $0.animation = nil }`.
3. Film / FX / recipe menus toggle with `disablesAnimations`; entrance motion is local (`PickerEntrance` opacity/offset only).
4. Deck expand/collapse commits via `withAnimation(ShutterMotion.deck)` on chrome state only.
5. Shutter press travel / busy rings / timer digits are SwiftUI-only — Metal `metallicSurface` args stay constant.

## Curves
| Token | Use |
|---|---|
| `deck` | Top/bottom deck collapse |
| `chrome` | Info bar / LE overlay |
| `reticleIn` / `reticleOut` | Focus box |
| `flash` | Capture wash |
| `tick` | Timer digits |
| `picker` | Local dock entrance |
| `scrub` | Ticker / dial settle |
| `press` | Button press |
