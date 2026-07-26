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
- **Collapsed:** bottom gradient covers the shutter; histogram clears the deck by
  `histDeckGap`; chrome columns stay above the fade band.
- **Landscape collapsed + expanded:** bottom deck may expand in landscape; both
  modes keep hist clear of shutter and a usable viewfinder height.
- **Film dock open:** SCENE/FILM picker must not cover the shutter center.
- **Z-order:** shutter dock sits above the histogram (tap priority).

## Devices

Portrait: SE · iPhone 15 · Pro Max  
Landscape: SE · iPhone 15 · Pro Max (collapsed + expanded)

## Outputs

- PNGs under `docs/visual-regression/` and `/opt/cursor/artifacts/visual-regression/`
- Canonical aliases: `expanded-layout.png`, `collapsed-layout.png`, `landscape-layout.png`
- Gallery: `index.html`
- Summary: `report.txt`
