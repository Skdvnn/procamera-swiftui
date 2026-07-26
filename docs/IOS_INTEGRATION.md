# Phase 3 — Deep iOS integration (build 48)

## Shipped
- [x] URL schemes `shuttercam://` / `procamera://` (camera, capture, darkroom, fieldbook, look, timer, peaking, flip)
- [x] App Intents + App Shortcuts (Open / Capture / Darkroom / Field Book / Apply Look / Timer)
- [x] Apply Look film + Timer use `AppEnum` pickers (not free-text)
- [x] Home Screen quick actions (Capture, Darkroom, Timer 3s)
- [x] Hardware shutter via `AVCaptureEventInteraction` (Camera Control / volume events)
- [x] Volume-button shutter (phase 2) kept
- [x] `ShutterCameraCaptureIntent` + `ShutterCaptureContext` (iOS 18 Camera Control / Lock Screen)
- [x] Widget extension: Home small/medium launch, Looks grid, Lock Screen circular + rectangular
- [x] `WidgetCenter.reloadAllTimelines()` after look/context sync
- [x] Control Center control widget (iOS 18)
- [x] Locked Camera Capture extension (iOS 18 Lock Screen / Action Button / Control)
- [x] App Group `group.com.skylardann.filmcam` for widget ↔ app context
- [x] Soft Auto Night assist (opt-in chip when AUTO is dark)
- [x] Hold-to-burst (up to 6 sequential stills)

## Setup on device / ASC (TestFlight widgets + Lock Screen)
1. In [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) enable App Group **`group.com.skylardann.filmcam`** on:
   - `com.skylardann.filmcam` (main app)
   - `com.skylardann.filmcam.widgets` (widget extension)
   - `com.skylardann.filmcam.capture` (Locked Camera Capture extension)
2. Archive a **Release** / TestFlight build (Debug entitlements are intentionally empty — Cmd+R will not exercise widgets or Lock capture).
3. Settings → Control Center → add **Shutter Cam**; Action Button / Camera Control can target the control.
4. Long-press Home Screen → Widgets → Shutter Cam / Shutter Looks.
5. Shortcuts app → search Shutter Cam intents (Open Field Book, Apply Look film picker, Timer enum).

## Still not 1:1 with Camera.app (honest gaps)
- Cannot become the *system default* Camera icon replacement (Apple reserved).
- Video / cinematic / spatial / ProRAW controls not in this pass.
- Lock Screen capture extension uses a slim picker UI; “FULL APP” jumps to the real Shutter UI.
- Live Photos / system burst API / computational Apple Night Mode — not yet (hold-to-burst + soft Night assist only).

## Deep link cheatsheet
- `shuttercam://camera`
- `shuttercam://capture`
- `shuttercam://darkroom`
- `shuttercam://fieldbook`
- `shuttercam://look?film=Portra%20400&fx=Dream`
- `shuttercam://timer?seconds=3`
