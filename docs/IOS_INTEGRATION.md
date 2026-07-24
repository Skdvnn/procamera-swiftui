# Phase 3 — Deep iOS integration (build 25)

## Shipped
- [x] URL schemes `shuttercam://` / `procamera://` (camera, capture, darkroom, look, timer, peaking, flip)
- [x] App Intents + App Shortcuts (Open / Capture / Darkroom / Apply Look / Timer)
- [x] Home Screen quick actions (Capture, Darkroom, Timer 3s)
- [x] Hardware shutter via `AVCaptureEventInteraction` (Camera Control / volume events)
- [x] Volume-button shutter (phase 2) kept
- [x] `ShutterCameraCaptureIntent` + `ShutterCaptureContext` (iOS 18 Camera Control / Lock Screen)
- [x] Widget extension: Home small/medium launch, Looks grid, Lock Screen circular + rectangular
- [x] Control Center control widget (iOS 18)
- [x] Locked Camera Capture extension (iOS 18 Lock Screen / Action Button / Control)
- [x] App Group `group.com.skylardann.filmcam` for widget ↔ app context

## Setup on device / ASC
1. Enable App Group `group.com.skylardann.filmcam` for app + widgets + capture IDs in the developer portal.
2. Settings → Control Center → add **Shutter Cam**; Action Button / Camera Control can target the control.
3. Long-press Home Screen → Widgets → Shutter Cam / Shutter Looks.
4. Shortcuts app → search Shutter Cam intents.

## Still not 1:1 with Camera.app (honest gaps)
- Cannot become the *system default* Camera icon replacement (Apple reserved).
- Video / cinematic / spatial / ProRAW controls not in this pass.
- Lock Screen capture extension uses a slim picker UI; “FULL APP” jumps to the real Shutter UI.
- Burst, Live Photos, Night mode auto — not yet.

## Deep link cheatsheet
- `shuttercam://camera`
- `shuttercam://capture`
- `shuttercam://darkroom`
- `shuttercam://look?film=Portra%20400&fx=Dream`
- `shuttercam://timer?seconds=3`
