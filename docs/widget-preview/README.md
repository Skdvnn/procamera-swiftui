# Widget face previews

Approximate renders of the Home Screen and Lock Screen widgets, drawn by
[`scripts/widget_layout_preview.py`](../../scripts/widget_layout_preview.py) from
the geometry parsed out of `ShutterWidgets/ShutterWidgetsBundle.swift`.

These are not screenshots. They exist so widget density can be reviewed without
a Release build on a device, and so a padding or bar-height edit shows up as a
visible diff. Sizes are the iPhone SE content rects (155×155, 329×155, 329×345),
which is where the stacks are tightest.

| File | Face |
| --- | --- |
| `launch-small.png` | Home small — day count, recent stack, sparkline |
| `launch-medium.png` | Home medium — week chart, exposure, shoot capsule, 2×2 sheet |
| `launch-large.png` | Home large — 3×2 contact sheet, labelled week, stat row |
| `looks-medium.png` | Looks medium — armed look, four chips, recents strip |
| `looks-large.png` | Looks large — chips, contact sheet, week + counts |
| `lock-accessories.png` | Circular roll gauge, rectangular, inline |
| `widget-preview.png` | All faces on one board |

Regenerate with `python3 scripts/widget_layout_preview.py`; the stress suite
runs it and fails if a face stops rendering.
