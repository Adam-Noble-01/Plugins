# Na Noble3d - Face Pattern Generator - Development Log
# =============================================================================
# Module : 20__SourceCode__FacePatternGenerator
# Plugin : Na Noble3d Modelling Tools
# Tab    : Geometry Tools > Surface Pattern Tools

## Overview

Unified parametric surface pattern generator that reads a single selected
SketchUp face, previews five architectural pattern types in an SVG HtmlDialog,
and applies the generated linework back onto the face plane.

# =============================================================================
# VERSION HISTORY
# =============================================================================


# Na Noble3d Modelling Tools
## Version 0.2.0 - 16-Jun-2026 - Noble Code Style and Dialog UI Polish

### Update 01 - Noble Code Style Pass (All Module Source Files)
- Restyled every Ruby and JavaScript file in the module to match the PNG To Linework / Noble 3D Tools conventions: file headers (`FILE`, `NAMESPACE`, `AUTHOR`, `PURPOSE`, `CREATED`), `# REGION |` / `// REGION |` blocks, `# FUNCTION |` / `# HELPER FUNCTION |` comment readers, inline `# <--` / `// <--` notes, and `# END OF FILE` footers.
- Ruby files updated: `Loader__`, `Run__`, `DialogManager__`, `FaceData__`, `GeometryBuilder__`, `SlateBuilder__`. DialogManager callbacks now wrap handlers in `begin/rescue` with console logging, matching the PngToLinework dialog manager pattern.
- JavaScript files updated: all six `01__SharedJs/` modules, all five `02__PatternGenerators/` modules, plus `AppCore__`, `UiBridge__`, `SvgPreview__`, and `UiConfig__`. Shared modules converted to IIFE exports where appropriate (`window.Na__FacePattern__*`).

### Update 02 - HtmlDialog Layout Restructure (`UiLayout__.html`)
- Added a full HTML file header block documenting injection placeholders, Ruby↔JS bridge calls, and the dialog workflow.
- Restructured the controls column into card-style groups with `GroupTitle` / `ControlItem` / `ControlHint`: Pattern Selection, Pattern Parameters (dynamic mount), Export, and Apply with a centred hint.
- Moved **Reset View** from the controls column into a viewport header row (SVG Preview title + button), matching the PNG To Linework layout.
- Status bar now uses an outer `StatusBar` wrapper and inner `StatusText` element (`id="naFacePat_status"`) for consistent footer messaging.

### Update 03 - Columnified Stylesheet (`Styles__.css`)
- Rewrote the stylesheet in the columnified Noble property format (`property : value;` with aligned colons) used by `Na__Noble3dModellingTools__Styles__.css`.
- Organised into named regions: Design Tokens, Base Layout, App Shell, Controls Column, Buttons, Viewport Pane, Status Bar.
- Aligned visual treatment with PNG To Linework: button hover/disabled states, full-height viewport column with header bar, checkerboard SVG wrapper, tertiary status-bar background.
- Added flatten rule for `#naFacePat_dynamicControls` nested groups so DynamicUI-injected fields do not double-render card borders.

### Update 04 - DynamicUI Status Class Fix
- `Na__FacePattern__DynamicUI__.js` — status error styling updated from `naFacePat__StatusBar--error` to `naFacePat__StatusText--error` after the status `id` moved to the inner footer element in the layout restructure.

---
# Na Noble3d Modelling Tools
## Version 0.1.0 - 16-Jun-2026 - Initial Migration from Prototype

### Purpose
Migrate five standalone Maker.js browser prototypes
(`Prototype__PatioGenerator`, `Prototype__BrickworkGenerator`,
`Prototype__StoneworkGenerator`, `Prototype__ShrubGenerator`, and
`Na__SlateRoofPatternGenerator__V2.rb`) into one unified Noble 3D Tools
HtmlDialog feature module under the naming convention and module structure
established by the PNG To Linework tool.

# =============================================================================

### Module File Map

#### Ruby (plugin-side)

| File | Responsibility |
|------|---------------|
| `...__Loader__.rb` | `require_relative` chain in dependency order |
| `...__Run__.rb` | Public entrypoint — validates single face, calls FaceData, opens dialog |
| `...__FaceData__.rb` | Face selection guard, orthonormal basis, 2D projection, JSON payload build |
| `...__DialogManager__.rb` | HtmlDialog lifecycle, asset inlining, Ruby↔JS callbacks |
| `...__GeometryBuilder__.rb` | Converts local-mm polylines to world-space SketchUp edges in a named group |
| `...__SlateBuilder__.rb` | Places component instances for slate pattern; reuses proven Ruby tiling logic |

#### JavaScript (dialog-side)

| File | Responsibility |
|------|---------------|
| `...__UiLayout__.html` | Dialog shell — `{{STYLESHEET_CONTENT}}` + `{{SCRIPTS_CONTENT}}` |
| `...__Styles__.css` | Two-pane layout: controls aside + SVG viewport; toolbar; status bar |
| `...__UiConfig__.js` | Per-pattern field descriptors (type, label, default, min, max, options) |
| `...__SvgPreview__.js` | Two-layer SVG renderer: face boundary overlay + pattern polylines; Y-flip |
| `...__AppCore__.js` | State machine: faceData, patternKey, polylines; regenerate; apply; DXF |
| `...__UiBridge__.js` | DOMContentLoaded boot, fills pattern selector, wires all button events |

#### Shared JS (`01__SharedJs/`)

| File | Source / Purpose |
|------|-----------------|
| `Na__FacePattern__DynamicUI__.js` | Control panel builder — number inputs and selects from field-descriptor config |
| `Na__FacePattern__Viewport__.js` | SVG viewBox-state pan/zoom, `na_computeBounds`, `na_buildViewBox`, `na_attachPanZoom` |
| `Na__FacePattern__Noise__.js` | Mulberry32 seeded random, 2D value noise, 3-octave FBM — consolidated from Brick + Stone prototypes |
| `Na__FacePattern__RectGeometry__.js` | `na_makeRectPolyline`, `na_clipRectToBounds` — replaces 4-line `M.paths.Line` pattern |
| `Na__FacePattern__PolygonClip__.js` | Ray-cast point-in-polygon, segment intersection, polyline clip to face polygon |
| `Na__FacePattern__DxfExport__.js` | Writes DXF LINE entities from polylines, triggers filename Blob download |

#### Pattern Generators (`02__PatternGenerators/`)

| File | Algorithm |
|------|-----------|
| `Na__FacePattern__PatioGenerator__.js` | Greedy grid packer, 6 weighted tile types (1×1 to 3×2 module units) |
| `Na__FacePattern__BrickworkGenerator__.js` | Stretcher / Flemish / English bond courses; Imperial + Metric brick sizes; FBM artistic mode |
| `Na__FacePattern__StoneworkGenerator__.js` | Coursed (random-height rows) + Uncoursed skyline packer; size presets; FBM artistic mode |
| `Na__FacePattern__ShrubGenerator__.js` | Single closed silhouette — Round/Wild/Topiary base shapes; interior-point sampler for non-rectangular faces |
| `Na__FacePattern__SlateRoofGenerator__.js` | Course tiling preview — visible gauge, half-bond stagger, 6 UK presets; Apply delegates to Ruby SlateBuilder |

---

### Design Decisions

#### No external library
The prototypes used Maker.js (CDN). The Noble 3D Tools dialog cannot reliably
reach the CDN and `set_html` has no base URL for local file references.
All geometry is computed as `[x, y]` polyline arrays and rendered directly to
SVG `<polyline>` elements — no library required.

#### Single-face v1 constraint
Multi-face requires inter-face packing and UV-layout decisions. Deferred.
The user can run the tool multiple times on adjacent faces. The error message
says "Select one face only" to keep expectations clear.

#### Face basis strategy
- **Pitched surfaces** (normal has a slope component): Y axis = up-slope
  (world-up minus projection onto normal), X axis = Y × normal cross-product.
  This produces the natural "courses run horizontally" orientation for roofs and walls.
- **Near-horizontal surfaces** (up-slope < 0.001): fallback to the longest outer
  edge as X axis. This handles floors and horizontal slabs.
- Normal is always flipped to the positive-Z side so `lift_mm` pushes geometry
  outward toward the user.

#### Slate apply via Ruby, preview via JS
The JS slate preview uses an all-corners-inside point test (no partial tiles
shown). The Ruby `SlateBuilder` uses `face.classify_point` which handles edge
and vertex coincidence correctly. This means the preview underestimates slightly
vs the Ruby result, but avoids implementing the full classify API in JS.

#### Shrub interior-point sampling
L-shaped and irregular faces have a bounding-box centre that falls outside the
face polygon. `ShrubGenerator` samples a grid across the bounds and picks the
first point that is inside and has 10mm clearance in all four cardinal directions
before attempting to fit the silhouette there. If no fit succeeds at any of 5
scale-down attempts it falls back to a minimum 2mm triangle at the interior point.

---

### Ruby↔JS Bridge Contract

| Direction | Call | Payload |
|-----------|------|---------|
| JS → Ruby | `sketchup.na_dialog_ready('')` | (empty) |
| JS → Ruby | `sketchup.na_refresh_face('')` | (empty) |
| JS → Ruby | `sketchup.na_apply_pattern(json)` | see Apply Payload below |
| JS → Ruby | `sketchup.na_js_log(message)` | string |
| Ruby → JS | `window.Na__FacePattern__SetFaceData(payload)` | see FaceData Payload below |
| Ruby → JS | `window.Na__FacePattern__SetStatus(message, success)` | string, bool |

#### FaceData Payload
```json
{
  "outer":  [[x, y], ...],
  "holes":  [[[x, y], ...], ...],
  "bounds": { "min_x": 0, "min_y": 0, "max_x": 3000, "max_y": 2000, "width": 3000, "height": 2000 },
  "basis":  { "origin": [ix, iy, iz], "x_axis": [vx, vy, vz], "y_axis": [...], "z_axis": [...] }
}
```
All coordinates in millimetres (basis vectors are dimensionless unit vectors in
SketchUp inch space; conversion happens in GeometryBuilder via `.mm`).

#### Apply Payload (edge patterns)
```json
{
  "pattern_type": "patio",
  "polylines": [[[x, y], ...], ...],
  "basis": { ... },
  "lift_mm": 0,
  "close_paths": true,
  "group_name": "Na Face Pattern - patio"
}
```

#### Apply Payload (slate)
Same as above plus `preset_key`, `slate_length_mm`, `slate_width_mm`,
`headlap_mm`, `side_gap_mm`, `stagger` — all passed to `SlateBuilder` which
ignores `polylines` and regenerates from the selection.

---

### Known Limitations (v1)

- Single face only. Multi-face deferred.
- Nested group/component face picking not supported — face must be in the
  active context (model root or open group/component).
- Slate preview shows only fully-inside slates; partial edge-clipped slates
  appear on Apply but not in the SVG preview.
- `pRoughness` and `pTumbled` are preview-only parameters for Stonework; the
  Ruby GeometryBuilder creates straight-edge rectangles. A polygon-point
  distortion pass could be added to GeometryBuilder in a future version.
- Shrub is a single silhouette, not a repeating tile. It scales to the
  user-defined width/height and is placed at the face interior centroid.

---

### Validation Checklist

- [x] All JS files pass `node --check`.
- [x] JSON registry parses (`ConvertFrom-Json`).
- [x] No linter errors in module files.
- [x] No MakerJS references in module (`rg -i "makerjs" .` → exit 1 / no matches).
- [x] Generator smoke tests: all five patterns produce non-empty polylines on 3000×2000mm rect face.
- [x] Generator smoke tests: all five patterns produce non-empty polylines on 3000×2000mm L-shaped face.
- [ ] In-SketchUp: `Geometry Tools > Surface Pattern Tools > Face Pattern Generator` button appears.
- [ ] In-SketchUp: dialog opens with face dims in toolbar and boundary in SVG.
- [ ] In-SketchUp: all five pattern types switch correctly; live preview updates on slider change.
- [ ] In-SketchUp: `Apply to Face` creates a group on the face; single undo reverts.
- [ ] In-SketchUp: `Refresh Face` re-reads selection without closing dialog.
- [ ] In-SketchUp: `Download DXF` saves a `.dxf` file with correct LINE entities.
- [ ] In-SketchUp: Slate `Apply` places component instances (not edges).
- [ ] In-SketchUp: selecting 0 or 2+ faces shows messagebox; dialog does not open.

# =============================================================================
# END OF DEVLOG
# =============================================================================
