# ProCamera - SwiftUI Camera App

A professional-grade camera app built with SwiftUI featuring analog-style controls and a refined UI inspired by classic film cameras.

## Features

- **Analog Display Panel** - Dual dial interface with focus and exposure controls
- **Rich Metal Shutter Button** - Tactile press feedback with gradient shaders
- **Aperture Dial** - Rotary f-stop selector (f/2.8 - f/16)
- **Lens Ring Zoom** - Swipe-based focal length control (24-105mm)
- **Flash Control** - Cycle through Off/On/Auto modes with visual indicators
- **White Balance Presets** - Auto, Sunny, Cloudy, Shade, Lamp, Fluorescent
- **ISO Control** - Quick-tap cycling through common values (100-3200)
- **Live Histogram** - Real-time exposure feedback in glass container
- **Manual Focus** - Precise focus control with haptic feedback
- **Timer Support** - 3s and 10s countdown modes
- **Grid Overlay** - Rule of thirds composition guide

## Design System

The app uses a cohesive design system (`DS`) featuring:

- **Colors**: Layered grays (not pure black) for depth
- **Strokes**: Stacked inner/outer strokes for beveled effect
- **Typography**: SF Mono for all numeric displays
- **Radius**: Consistent 12px corners on controls
- **Margins**: 20px page wrapper for balanced layout

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Project Structure

```
SwiftUI/
├── ContentView.swift       # Main UI and all control components
├── CameraManager.swift     # AVFoundation camera interface
├── AnalogGaugeView.swift   # Focus/Exposure dial components
├── CameraPreviewView.swift # Live camera preview
├── ViewfinderOverlay.swift # Grid and vignette overlays
├── ShaderViews.swift       # Metal shader integrations
├── Shaders.metal           # Custom GPU shaders
├── UIValidation.swift      # Debug validation tests
└── .swiftlint.yml          # Code style configuration
```

## Controls Reference

| Control | Interaction | Function |
|---------|-------------|----------|
| Focus Dial | Drag/Double-tap | Manual focus / Reset to center |
| Exposure Dial | Drag/Double-tap | EV compensation / Reset to 0 |
| Aperture Dial | Drag/Tap | Select f-stop |
| Lens Ring | Swipe left/right | Zoom in/out |
| Shutter | Tap | Capture photo |
| Flash | Tap | Cycle Off/On/Auto |
| WB | Tap | Cycle white balance presets |
| ISO | Tap | Cycle ISO values |
| Thumbnail | Tap | View last captured photo |

## Building

1. Open `ProCamera.xcodeproj` in Xcode
2. Select your target device/simulator
3. Build and run (Cmd+R)

## License

MIT License - See LICENSE file for details.
