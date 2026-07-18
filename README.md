# ProCamera - SwiftUI Camera App

A professional-grade camera app built with SwiftUI featuring analog-style controls and a refined UI inspired by classic film cameras.

## Features

- **Analog Display Panel** - Dual dial interface with focus and exposure controls
- **Rich Metal Shutter Button** - Tactile press feedback with gradient shaders
- **Lens Ring Zoom** - Swipe-based focal length control across available lenses
- **Flash Control** - Cycle through Off/On/Auto modes with visual indicators
- **White Balance Presets** - Auto, Sunny, Cloudy, Shade, Lamp, Fluorescent
- **ISO / Shutter Controls** - Manual exposure wired to AVFoundation
- **Live Histogram** - Real luminance bins from the camera feed
- **Lens FX** - Live GPU shader effects on the camera feed: Liquid glass distortion, Chrome, Instant film, Dream glow, Fisheye, Thermal, X-Ray, VHS (chromatic aberration + scanlines), Kaleidoscope, 8-Bit, Comic, Mirror, and Negative — baked into captured photos
- **Film Simulation** - Portra, Gold, Tri-X, Velvia, CineStill live filters
- **Manual Focus** - Precise focus control with haptic feedback
- **Macro Mode** - Near-range autofocus restriction
- **RAW+HEIC Capture** - Dual capture with DNG saved alongside a viewable preview
- **Long Exposure** - Computational multi-frame capture with viewfinder progress
- **Timer Support** - 3s and 10s countdown modes
- **Grid Overlay** - Rule of thirds composition guide
- **Full-Bleed Mode** - Swipe the top dial panel up or the bottom controls down to collapse them into compact decks and give the viewfinder the screen
- **Field Book Library** - Classic Apple Books-style shelf: upright covers on physical ledges, tap a cover to open it, tap other covers on the open-book rail to flip through albums. Share a book over iCloud; invites land on a Shared With Me shelf. Inside each book: black paper pages, corner-mounted prints, silver-pen captions (ISO, shutter, EV, film, FX), contact-sheet index, page-curl turns, and a pinch-zoom lightbox. Create little books, add frames from the master roll, and pin favorites to the front

## Design System

The app uses a cohesive design system (`DS`) featuring:

- **Colors**: Layered grays (not pure black) for depth
- **Strokes**: Stacked inner/outer strokes for beveled effect
- **Typography**: SF Mono for all numeric displays
- **Radius**: Consistent 12px corners on controls
- **Margins**: 10pt page wrapper for balanced layout

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Project Structure

```
├── ContentView.swift           # Main UI and control components
├── CameraManager.swift         # AVFoundation camera interface
├── LensFXEngine.swift          # Live GPU effects processor
├── PhotoBook.swift             # Field Book gallery + library
├── AnalogGaugeView.swift       # Focus/Exposure dial components
├── FilteredCameraPreview.swift # Metal-backed filtered preview
├── CameraPreviewView.swift     # Live camera preview
├── ViewfinderOverlay.swift     # Grid, film, and FX overlays
├── ShaderViews.swift           # Metal shader integrations
├── Shaders.metal               # Custom GPU shaders
└── .swiftlint.yml              # Code style configuration
```

## Controls Reference

| Control | Interaction | Function |
|---------|-------------|----------|
| Focus Dial | Drag/Double-tap | Manual focus / Reset to center |
| Exposure Dial | Drag/Double-tap | EV compensation / Reset to 0 |
| Lens Ring | Swipe left/right | Zoom in/out |
| Shutter | Tap | Capture photo |
| Flash | Tap | Cycle Off/On/Auto |
| WB | Tap | Cycle white balance presets |
| ISO | Drag | Set ISO |
| Format | Tap | Cycle HEIC / JPG / RAW |
| Macro | Tap | Near-range AF |
| Thumbnail | Tap | Open Field Book |

## Building

1. Open `ProCamera.xcodeproj` in Xcode
2. Select your target device/simulator
3. Build and run (Cmd+R)

## License

MIT License - See LICENSE file for details.
