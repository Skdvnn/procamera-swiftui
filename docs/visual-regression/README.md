# Camera chrome layout visual regression

Run:

```bash
python3 scripts/visual_layout_regression.py
```

Asserts:

- **Expanded:** histogram sits inside the viewfinder and does not overlap the shutter deck (gap ≥ 5pt + 14pt pad).
- **Collapsed:** bottom gradient underlay covers the shutter deck; histogram clears the deck by 8pt; film / lens-FX hit targets stay in the top-trailing chrome clear of bottom layers.

Diagrams: `expanded-layout.png`, `collapsed-layout.png`.
