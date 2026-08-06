# Camera chrome layout visual regression

Run:

```bash
python3 scripts/visual_layout_regression.py
```

The script parses `CollapsedChrome` from `ContentView.swift`, models chrome across
device sizes, asserts hit-test / overlap invariants, and writes diagrams plus an
HTML gallery.

## Asserts

- **Expanded:** histogram clears the shutter deck; trailing Film/FX/Looks and
  leading Aspect/Flip/Peaking stay above the deck.
- **Collapsed (swiped-down):** no histogram; shutter dock + fade only; chrome
  columns stay above the fade band.
- **Landscape collapsed + expanded:** bottom deck may expand in landscape;
  collapsed stays hist-free; expanded keeps hist clear of shutter.
- **Film dock open:** SCENE/FILM picker must not cover the shutter center.
- **Z-order:** shutter dock stays tappable above viewfinder chrome.

## Devices

Portrait: SE · iPhone 15 · Pro Max  
Landscape: SE · iPhone 15 · Pro Max (collapsed + expanded)

## Outputs

- PNGs under `docs/visual-regression/` and `/opt/cursor/artifacts/visual-regression/`
- Canonical aliases: `expanded-layout.png`, `collapsed-layout.png`, `landscape-layout.png`
- Gallery: `index.html`
- Summary: `report.txt`
