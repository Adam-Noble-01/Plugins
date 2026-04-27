# Na Window Configurator Tool - Architecture Diagram

## Overview

This document provides a comprehensive diagram of how the Window Configurator Tool works, including data flow, file relationships, and the planned feature additions.

## Feature Addendum - Per-Panel Casement Toggle (v0.10.4)

### Concept

`removed_casements` was previously an array of bare opening indices (e.g. `[0, 2]`) and a single click target spanned each opening's full inner height. This blocked toggling individual casements within transom-divided cells or `casements_per_opening > 1` openings.

The system now tracks removal at the **panel** level, matching the pattern already used by transom segments and individual glaze bars.

### New Key Format

`removed_casements` entries are now strings of the form:

```
"<openingIndex>:<cellIndex>:<panelIndex>"
```

- `openingIndex` -- mullion-bounded opening (left-to-right).
- `cellIndex` -- transom-bounded cell within that opening (bottom-to-top).
- `panelIndex` -- casement panel within that cell (`0..casements_per_opening - 1`).

Sliding-sash sashes inside one panel share the same key, so toggling a panel removes both top and bottom sashes together (consistent with how `casements_per_opening` already groups rails/glass into discrete panels).

### Click Target Layering

| Class | Identity | Storage Array |
|-------|----------|---------------|
| `na-opening-click-target` | `openingIndex:cellIndex:panelIndex` | `removed_casements` |
| `na-transom-click-target` | `openingIndex:transomIndex` | `removed_transom_segments` |
| `na-glazebar-click-target` | `openingIndex:cellIndex:panelIndex:sashIndex:orientation:barIndex` | `removed_glazebars` |

The casement click target is now emitted **inside** the per-cell, per-panel SVG loop in `na_generateOpeningCellSvg` (one rect per panel), so any framework-bound region -- between mullions, between transoms, or within a multi-panel opening -- can be toggled independently. The red dashed "removed casement" indicator likewise renders per panel.

### Data Flow Touchpoints

- **`Viewport__SvgGenerator__.js`** -- new helpers `na_getCasementKey`, `na_getRemovedCasementSet`, `na_isPanelCasementRemoved`. Per-panel click rects and per-panel removed-indicator rects are generated inside the cell/panel loop. `na_collectValidGlazebarKeys` now uses the per-panel removal check so removing one panel's casement no longer invalidates other panels' glaze bar keys.
- **`Viewport__Controls__.js`** -- `na-opening-click-target` reads `data-cell-index` and `data-panel-index` and forwards `(openingIndex, cellIndex, panelIndex)` to the click callback.
- **`UiLogic__.js`** -- `na_toggleCasementRemoval(openingIndex, cellIndex, panelIndex)` toggles the new keyed entry. `na_onConfigChange` migrates legacy bare-integer entries (see below) and prunes stale keys against `na_getValidCasementKeySet()`.
- **`GeometryEngine__.rb`** -- new `na_panel_casement_removed?` helper (legacy-aware). `na_create_multi_casement_opening` and `na_create_sliding_sash_opening` compute `panel_has_casement` per panel.
- **`DxfExporterLogic__.rb`** -- mirrors the per-panel check inside the cells loop.
- **`Export__Dxf__.js`** -- mirrors the per-panel check using helpers exposed by `Na__Viewport__SvgGenerator`.

### Legacy Migration (Backward Compatibility)

Saved configurations using the old bare-integer format (e.g. `removed_casements: [0, 2]`) still render correctly:

- **JS render path:** `na_getRemovedCasementSet` separates legacy bare integers into a `legacyOpenings` Set. `na_isPanelCasementRemoved` returns `true` if the panel's opening is in that Set, so every cell/panel of that opening reads as removed.
- **Ruby render path:** `na_panel_casement_removed?` accepts both string keys and legacy integers (or stringified integers) and produces the same per-panel decision.
- **Migration on load:** the next `na_onConfigChange` cycle expands every legacy bare integer to per-panel `"i:c:p"` keys for every current cell/panel of that opening, then writes the migrated array back to `_config.removed_casements`. From that point on the array saves and loads cleanly in the new format.

`removed_transom_segments` and `removed_glazebars` are unaffected by this change.

---

## Feature Addendum - Door Mode Casement Integration (v0.10.1)

### Concept

Door Mode converts the window into a door. Each casement becomes a full-height door with the panel integrated inside:
- **Upper glazed zone** -- glass + glaze bars sit above a mid-rail
- **Lower solid panel zone** -- configurable grid of recessed panels with optional trim/moulding sits below the mid-rail
- The casement stiles span the full height; top rail, mid-rail, and bottom rail divide the zones
- No separate transom-like divider -- the panel is part of the casement group
- Multi-casement openings produce independent doors, each with their own panel

### New Config Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `door_mode` | boolean | `false` | Master toggle for door mode |
| `door_panel_height_mm` | number | `400` | Height of the solid lower panel section |
| `door_panel_columns` | integer | `2` | Number of panel columns (1--4) |
| `door_panel_rows` | integer | `1` | Number of panel rows (1--3) |
| `door_panel_rail_width_mm` | number | `30` | Width of horizontal dividers between rows |
| `door_panel_stile_width_mm` | number | `30` | Width of vertical dividers between columns |
| `door_panel_margin_mm` | number | `30` | Margin from casement/frame edge to panel grid |
| `door_panel_recess_depth_mm` | number | `8` | How deep each panel is recessed |
| `door_panel_trim_width_mm` | number | `5` | Trim/moulding border width |
| `door_panel_trim_depth_mm` | number | `3` | Trim protrusion depth |
| `door_panel_moulding_inset_mm` | number | `5` | Pushes moulding back from casement front face |

### Data Flow

`door_mode toggle (Options)` -> `Na_DynamicUI._config` -> `na_updateDoorPanelVisibility()` shows/hides Door Panel section -> `UiEventToRubyApiBridge` passes config -> `GeometryEngine.na_parse_config` extracts door params -> `na_render_opening_panel_geometry` routes to `na_render_door_casement_geometry` -> builds full-height casement (stiles + top/bottom/mid rails) + glass in upper zone + `DoorPanelBuilder.na_create_door_panel_section` fills lower zone with grid dividers, recessed panels, and trim.

### New Files

1. **`Na__WindowConfiguratorTool__DoorPanel__Config__.js`** -- `NA_DOOR_PANEL_CONFIG` array with all door panel UI control descriptors
2. **`Na__WindowConfiguratorTool__DoorPanel__GeometryBuilder__.rb`** -- `Na__DoorPanelGeometryBuilder` module with panel section geometry creation

### Modified Files

1. **`Na__WindowConfiguratorTool__Ui__Config__.js`** -- `door_mode` toggle in `NA_OPTIONS_CONFIG`
2. **`Na__WindowConfiguratorTool__UiLayout__.html`** -- Door Panel section container + script include
3. **`Na__WindowConfiguratorTool__UiLogic__.js`** -- builds door panel controls, defaults, visibility management
4. **`Na__WindowConfiguratorTool__GeometryEngine__.rb`** -- parses door config, splits height, calls door panel builder, creates divider
5. **`Na__WindowConfiguratorTool__Main__.rb`** -- requires new module, adds door panel defaults
6. **`Na__WindowConfiguratorTool__Viewport__SvgGenerator__.js`** -- renders door panel area and divider in 2D preview

### Geometry Detail

For each casement panel in door mode, `na_render_door_casement_geometry` builds:
1. **Full-height casement stiles** -- left and right stiles spanning the entire panel height
2. **Top rail** -- at the top of the casement
3. **Bottom rail** -- at the bottom of the casement
4. **Mid-rail** -- horizontal member at the glass/panel junction (casement bottom rail thickness)
5. **Glass + glaze bars** -- placed in the upper zone (between mid-rail and top rail)
6. **Door panel content** -- `DoorPanelBuilder.na_create_door_panel_section` fills the lower zone with grid dividers, recessed panels, and trim/moulding

### FuseParts Integration

- **Casement fusion** (`Na_Casement_{panel_id}_*`): stiles, top rail, bottom rail, and mid-rail all fuse into one solid per panel
- **Door panel fusion** (`Na_DoorPanel_{panel_id}_*`): grid stiles, rails, and recessed panels fuse per panel
- **Door trim fusion** (`Na_DoorTrim_{panel_id}_*`): all trim strips fuse per panel
- Two new steps in `na_fuse_window_parts`: `na_fuse_door_panels` and `na_fuse_door_trim`

### Integration

- **Mullions + door mode**: each opening gets independent doors; mullions span full height
- **Transoms + door mode**: transoms apply to the full opening height
- **Cill**: automatically disabled when door mode is on
- **Multi-casement**: each casement panel independently contains its own lower panel section

---

## Feature Addendum - Header Reload Icon (v0.9.12d)

### UI

- The main dialog header reload action is an icon-only button (`na-btn-icon`, Unicode `U+21BB`) with `title="Reload Scripts"`, matching the compact control used in Na Array Builder.
- Click handling remains `na_reloadScripts()` in the HTML layout, which delegates to `sketchup.na_reloadScripts()` via `Na__WindowConfiguratorTool__UiEventToRubyApiBridge__.js`.
- If `Na__WindowConfiguratorTool__UiLayout__.html` is missing, fallback HTML in `Na__WindowConfiguratorTool__DialogManager__.rb` exposes the same glyph with class `na-fallback-reload`.

### Files

- `Na__WindowConfiguratorTool__UiLayout__.html` — reload control markup
- `Na__WindowConfiguratorTool__Styles__.css` — `.na-btn-icon`
- `Na__WindowConfiguratorTool__DialogManager__.rb` — fallback reload control

## Feature Addendum - FuseParts Per-Panel Fusion Fix (v0.9.12c)

### Bug Fix

- `FuseParts__.rb` previously grouped casement and glaze bar parts by the first numeric segment of the group name (the opening index). This caused all casement panels within the same opening to be merged into a single solid when `fuse_parts` was enabled with `casements_per_opening > 1`.

### Changes

- Replaced `na_find_unique_indices` with `na_find_unique_panel_ids` which uses suffix-aware regex parsing to extract full panel identifiers (e.g. `0_0_P0`, `0_0_P1`) from group names.
- Casement fusion now produces one solid per panel: `Na_Casement_{panel_id}_Fused` instead of one solid per opening.
- Glaze bar fusion now produces one solid per panel: `Na_GlazeBar_{panel_id}_Fused`.
- Glass trimming now correctly matches each panel's glass pane (`Na_Glass_{panel_id}`) to its corresponding fused glaze bar solid.
- Replaced `na_extract_index_from_fused_name` with `na_extract_panel_id_from_fused_name` which extracts the full panel_id from between the prefix and `_Fused` suffix.
- Frame fusion (`na_fuse_frame`) is unchanged -- frame, mullion, and transom groups are still correctly fused into one structural solid.

### Affected Files

1. **`Na__WindowConfiguratorTool__FuseParts__.rb`** -- all changes in this file only

---

## Feature Addendum - Reset Hidden Elements Action (v0.9.12b)

### UI / State Notes

- The 2D preview toolbar now includes a `Reset Elements` button next to the viewport actions.
- The button clears all current hidden-element state in one action by resetting:
  - `removed_casements`
  - `removed_transom_segments`
  - `removed_glazebars`
- The button is disabled when there are no hidden elements to restore.
- Resetting flows through the normal `UiLogic _config -> render -> live update` path, so the preview, live SketchUp model, saved config, and DXF exports all return to the fully visible state together.

## Feature Addendum - Individual Glaze Bar Toggles (v0.9.12a)

### New Shared Config Fields

The glaze bar system now supports per-visible-bar removal keys in addition to the existing global horizontal and vertical bar counts:

- `removed_glazebars` - array of `"openingIndex:cellIndex:panelIndex:sashIndex:orientation:barIndex"` keys for individual bars that should be suppressed

This value now flows through the same shared configuration path as the existing removal systems:

`UiLogic _config` -> `Viewport__SvgGenerator__` / `Viewport__Controls__` -> `UiEventToRubyApiBridge__` -> `DialogManager__.rb` -> `GeometryEngine__.rb` / `GeometryBuilders__.rb` -> `DxfExporterLogic__.rb` / `Export__Dxf__.js`

### Layout / Identity Behaviour

- `openingIndex` identifies the mullion span.
- `cellIndex` identifies the transom-aware stacked cell inside that span.
- `panelIndex` identifies the horizontal panel when `casements_per_opening > 1`.
- `sashIndex` distinguishes top vs bottom sash in sliding sash mode.
- `orientation` is either `horizontal` or `vertical`.
- `barIndex` stays `1`-based to match the existing bar-spacing loops in both JavaScript and Ruby.

### UI / Preview Notes

- Individual glaze bars are now toggleable directly from the SVG preview.
- Each bar position has a dedicated transparent click rectangle rendered above the opening/transom overlays so bar clicks win reliably inside the SketchUp HtmlDialog renderer.
- Click rectangles remain active even when the visible bar has been removed, allowing the same location to be clicked again to restore the bar.
- `UiLogic__.js` now cleans stale `removed_glazebars` keys whenever the current opening/cell/panel/sash layout changes.

### Geometry / Export Notes

- `GeometryEngine__.rb` now carries opening, cell, panel, and sash identity through to the glaze bar builder.
- `GeometryBuilders__.rb` now skips only the specific keyed bars that were removed instead of suppressing whole bar rows/columns globally.
- `DxfExporterLogic__.rb` and `Export__Dxf__.js` now skip the same keyed bars so exported drawings stay aligned with the preview and live 3D model.

## Feature Addendum - Advanced Frame Controls (v0.9.12)

### New Shared Config Fields

The frame system now supports an optional per-side override layer on top of the existing uniform frame thickness:

- `advanced_frame_controls` - enables per-side frame thickness overrides when `true`
- `frame_top_thickness_mm`
- `frame_bottom_thickness_mm`
- `frame_left_thickness_mm`
- `frame_right_thickness_mm`

These values now flow through the same full-config path used by the other advanced override systems:

`Ui__Config__` -> `UiLogic _config` -> `Viewport__Validation__` / `Viewport__SvgGenerator__` -> `UiEventToRubyApiBridge__` -> `DialogManager__.rb` -> `GeometryEngine__.rb` / `DxfExporterLogic__.rb`

### Behaviour Notes

- `frame_thickness_mm` remains the base slider and backward-compatible fallback for saved windows.
- When `advanced_frame_controls` is `false`, all four effective frame sides use `frame_thickness_mm`.
- When `advanced_frame_controls` is `true`, the top/bottom/left/right override sliders drive the effective inner opening rectangle.
- Asymmetric frames now shift the opening origin and inner clear size:
  - `inner_width = width - left_frame - right_frame`
  - `inner_height = height - top_frame - bottom_frame`
- Cills and opening-measurement deductions now depend on the effective bottom frame thickness instead of assuming one uniform frame member all round.

### Geometry / Export Notes

- `GeometryBuilders__.rb` now builds the outer frame from separate left/right stile widths and top/bottom rail heights.
- `GeometryEngine__.rb`, `Viewport__SvgGenerator__.js`, `Viewport__Validation__.js`, and both DXF exporters all use the same effective per-side frame logic.
- A `0mm` side value now creates a frameless edge on that side only; the other sides can still render normally.

## Feature Addendum - Transom System (v0.9.11)

### New Shared Config Fields

The transom system extends the shared `windowConfiguration` contract with:

- `transoms` - number of active transom levels (`0-3`)
- `transom_width_mm` - transom member height/thickness in the 2D/3D layouts
- `transom_1_y_mm`
- `transom_2_y_mm`
- `transom_3_y_mm`
- `removed_transom_segments` - array of `"openingIndex:transomIndex"` keys for spans where a transom segment is intentionally suppressed

These values now flow through the same full-config path used by mullions:

`Ui__Config__` -> `UiLogic _config` -> `Viewport__Validation__` / `Viewport__SvgGenerator__` -> `UiEventToRubyApiBridge__` -> `DialogManager__.rb` -> `GeometryEngine__.rb` / `DxfExporterLogic__.rb`

### Layout Behaviour

- Mullions still split the window horizontally into opening spans.
- Transoms now split each opening span vertically into stacked cells.
- Transom levels are shared globally by slider value, but each span can suppress an individual transom segment via `removed_transom_segments`.
- When a transom segment is removed in one span, the adjacent cells merge in that span only.
- Casements, direct glazing, glaze bars, sliding sash rendering, 3D geometry, and DXF output are all generated from these merged cells rather than from one full-height opening rectangle.
- As of v0.10.4, individual casements inside transom-bound cells (and inside multi-panel openings) are toggleable directly from the SVG preview -- see "Feature Addendum - Per-Panel Casement Toggle".

### UI / Preview Notes

- The new transom controls live in `Na__WindowConfiguratorTool__Ui__Config__.js` after the mullion controls.
- `UiLogic__.js` now handles:
  - visibility of transom width / height sliders
  - ordering and clamping of active transom heights
  - one-transom default seeding at roughly one-third of the inner frame height when first enabled
  - flipped UI coordinate conversion so transom sliders are shown in top-origin terms while the internal config stays bottom-origin
  - cleanup of stale `removed_transom_segments`
- `Viewport__Controls__.js` now routes both opening click targets and transom-segment click targets.
- Transom click targets use a minimally painted overlay in the SVG so segment toggling remains reliable inside the SketchUp HtmlDialog renderer.

### Geometry / Export Notes

- `GeometryHelpers__.rb` and `GeometryBuilders__.rb` now include a dedicated transom primitive/builder.
- `GeometryEngine__.rb` now builds per-opening transom segments first, then renders merged opening cells.
- `FuseParts__.rb` now includes `Na_Transom_*` groups in the frame fusion pass so transoms are fused with the rest of the frame assembly.
- `DxfExporterLogic__.rb` and `Export__Dxf__.js` now mirror the same transom-aware cell layout.
- DXF now includes a dedicated `NA_TRANSOM` layer for horizontal transom members.

### Related Slider Limit Update

- `horizontal_glaze_bars` max increased from `6` to `8`
- `vertical_glaze_bars` max increased from `6` to `8`

---

## File Structure Diagram (Version 0.6.0 - Modular Architecture)

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                         ProtoType__3dWindowConfigTool/                                 │
├───────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  ┌───────────────────────────────────────┐   ┌───────────────────────────────────────┐│
│  │      RUBY BACKEND (SketchUp)          │   │       JAVASCRIPT FRONTEND              ││
│  ├───────────────────────────────────────┤   ├───────────────────────────────────────┤│
│  │  MAIN ORCHESTRATOR                    │   │  UI LAYER (Ui__)                       ││
│  │  Na__...__Main__.rb (220 lines)       │   │  Na__...__Ui__Config__.js              ││
│  │  ├─ Entry point (na_init)             │   │  └─ Configuration constants            ││
│  │  ├─ Module requires                   │   │  Na__...__Ui__Controls__.js            ││
│  │  └─ Constants                         │   │  └─ HTML generation                    ││
│  │                                       │   │  Na__...__Ui__Events__.js              ││
│  │  DIALOG MANAGEMENT                    │   │  └─ Event handler attachment           ││
│  │  Na__...__DialogManager__.rb (609)    │   │                                        ││
│  │  ├─ HtmlDialog lifecycle              │   │  VIEWPORT LAYER (Viewport__)           ││
│  │  ├─ Ruby ↔ JS callbacks              │   │  Na__...__Viewport__Validation__.js    ││
│  │  ├─ Live mode handling                │   │  └─ Config validation & errors         ││
│  │  └─ DXF export coordination           │   │  Na__...__Viewport__SvgGenerator__.js  ││
│  │                                       │   │  └─ SVG markup generation              ││
│  │  GEOMETRY SYSTEM                      │   │  Na__...__Viewport__Controls__.js      ││
│  │  Na__...__GeometryEngine__.rb (469)   │   │  └─ Pan/zoom/click interaction         ││
│  │  ├─ Create/update orchestration      │   │                                        ││
│  │  ├─ Opening calculations             │   │  EXPORT LAYER (Export__)               ││
│  │  ├─ Config parsing                    │   │  Na__...__Export__Dxf__.js             ││
│  │  └─ Removed casements handling        │   │  └─ DXF generation (browser fallback)  ││
│  │                                       │   │                                        ││
│  │  Na__...__GeometryBuilders__.rb (309) │   │  MAIN ORCHESTRATOR                     ││
│  │  ├─ na_create_frame()                 │   │  Na__...__UiLogic__.js (526 lines)     ││
│  │  ├─ na_create_mullion()               │   │  ├─ Na_DynamicUI module                ││
│  │  ├─ na_create_casement()              │   │  │   ├─ State management               ││
│  │  ├─ na_create_glass()                 │   │  │   ├─ Config updates                 ││
│  │  └─ na_create_cill()                  │   │  │   └─ Button state sync              ││
│  │                                       │   │  └─ Na_Viewport module                 ││
│  │  Na__...__GeometryHelpers__.rb (231)  │   │      ├─ Viewport init                  ││
│  │  ├─ na_create_grouped_box()           │   │      ├─ Render coordination            ││
│  │  ├─ na_create_frame_stile()           │   │      └─ View reset                     ││
│  │  ├─ na_create_frame_rail()            │   │                                        ││
│  │  ├─ na_create_casement_stile()        │   │  BRIDGE                                ││
│  │  ├─ na_create_casement_rail()         │   │  Na__...__UiEventToRubyApiBridge__.js  ││
│  │  ├─ na_create_glaze_bar_*()           │   │  ├─ na_createWindow()                  ││
│  │  └─ Coordinate utilities              │   │  ├─ na_updateWindow()                  ││
│  │                                       │   │  ├─ na_liveUpdate()                    ││
│  │  TOOLS & OBSERVERS                    │   │  ├─ na_showStatus()                    ││
│  │  Na__...__PlacementTool__.rb (272)    │   │  └─ Live mode debouncing (100ms)       ││
│  │  ├─ Crosshair cursor                  │   │                                        ││
│  │  ├─ Grid snapping                     │   └───────────────────────────────────────┘│
│  │  ├─ Rotation (TAB, 4-step 0/90/180/270°) │                                             │
│  │  └─ Preview feedback                  │   ┌───────────────────────────────────────┐│
│  │                                       │   │       HTML / CSS                        ││
│  │  Na__...__MeasureOpeningTool__.rb     │   ├───────────────────────────────────────┤│
│  │  ├─ Two-click measurement             │   │                                        ││
│  │  ├─ Blue overlay rectangle (GL_QUADS) │   │                                        ││
│  │  ├─ Plane detection (XZ/YZ)           │   │                                        ││
│  │  └─ Sends dims to dialog              │   │                                        ││
│  │                                       │   │                                        ││
│  │  Na__...__Observers__.rb (82)         │   │                                        ││
│  │  └─ SelectionObserver for Live Mode   │   │  Na__...__UiLayout__.html (237)        ││
│  │                                       │   │  ├─ Header (Reload/Live/Measure btns)  ││
│  │  DATA & UTILITIES                     │   │  ├─ Status bar                         ││
│  │  Na__...__MaterialManager__.rb (380)  │   │  ├─ 2D Viewport section                ││
│  │  ├─ Material library loading          │   │  ├─ Dimensions section                 ││
│  │  ├─ Standard material creation        │   │  ├─ Glaze Bars section                 ││
│  │  └─ Material lookup & caching         │   │  ├─ Cill & Frame section               ││
│  │                                       │   │  ├─ Options + Material Cards            ││
│  │  Na__...__DataSerializer__.rb (447)   │   │  ├─ Actions (Create + Update btns)     ││
│  │  ├─ Save/load window data             │   │  ├─ Window Info (ID, Desc, Dates)      ││
│  │  ├─ Generate window IDs (AWNxxx)      │   │  └─ Script includes (9 files)          ││
│  │  └─ Attribute management              │   │                                        ││
│  │                                       │   │  Na__...__Styles__.css                 ││
│  │  Na__...__DebugTools__.rb (317)       │   │  ├─ CSS Variables                      ││
│  │  └─ Debug logging & tracing           │   │  ├─ Control styles                     ││
│  │                                       │   │  ├─ Layout styles                      ││
│  │  CONFIGURATION                        │   │  └─ Viewport styles                    ││
│  │  Na__AppConfig__MaterialsLibrary.json │   │                                        ││
│  │  └─ Material definitions & properties │   │                                        ││
│  │                                       │   │  └─ Script includes (9 files)          ││
│  │                                       │   │                                        ││
│  │  Na__...__DxfExporterLogic__.rb (489) │   │  Na__...__Styles__.css                 ││
│  │  ├─ Full DXF generation               │   │  ├─ CSS Variables                      ││
│  │  ├─ Layer management                  │   │  ├─ Control styles                     ││
│  │  └─ 2D CAD geometry export            │   │  ├─ Layout styles                      ││
│  │                                       │   │  └─ Viewport styles                    ││
│  │  POST-PROCESSING                      │   │                                        ││
│  │  Na__...__FuseParts__.rb              │   │                                        ││
│  │  ├─ Sequential outer_shell fusion     │   │                                        ││
│  │  ├─ Frame/casement/glaze bar fusing   │   │                                        ││
│  │  ├─ Glass panel trimming              │   │                                        ││
│  │  └─ Only on Create/Update (not Live)  │   │                                        ││
│  │                                       │   │                                        ││
│  └───────────────────────────────────────┘   └───────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────────────────┘

MODULE DEPENDENCIES:
Ruby: Main → requires all → MaterialManager, DialogManager, GeometryEngine, PlacementTool, MeasureOpeningTool, Observers, FuseParts
      Main → MaterialManager (initializes on startup)
      GeometryEngine → MaterialManager (material lookups)
      GeometryEngine → GeometryBuilders → GeometryHelpers
      DialogManager → FuseParts (post-processing, Create/Update only)
JavaScript: Config → Controls, Events → UiLogic → Viewport modules → Export → Bridge
```

---

## Data Flow Diagram (Version 0.6.0 - Modular Architecture)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER INTERACTION                                  │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        HTML DIALOG (UI)                                     │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  SLIDERS / TOGGLES / COLOR PICKERS                                   │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │   │
│  │  │ Width       │ │ Height      │ │ Frame       │ │ Casement    │     │   │
│  │  │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │     │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘     │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │   │
│  │  │ Mullions    │ │ Mullion W   │ │ H Bars      │ │ V Bars      │     │   │
│  │  │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │     │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘     │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │   │
│  │  │ Cill Height │ │ Cill Protr  │ │ Frame Depth │ │ Wall Inset  │     │   │
│  │  │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │     │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘     │   │
│  │  ┌─────────────────────────────┐ ┌─────────────────────────────┐     │   │
│  │  │ Show Casements      [●]    │ │ Include Cill         [●]    │     │   │
│  │  └─────────────────────────────┘ └─────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
            ▼                       ▼                       ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────────────┐
│  Na__Ui__Events   │   │ Na__Viewport__    │   │  Na_DynamicUI (Main)      │
│  ┌─────────────┐  │   │   SvgGenerator    │   │  ┌─────────────────────┐  │
│  │ Slider evt  │  │   │  ┌─────────────┐  │   │  │ _config = {         │  │
│  │   onChange  │──┼───┼──▶ Generate    │  │   │  │  width_mm: 2670     │  │
│  │             │  │   │  │ Window SVG  │  │   │  │  height_mm: 1200    │  │
│  └─────────────┘  │   │  │             │  │   │  │  mullions: 3        │  │
│                   │   │  └─────────────┘  │   │  │  removed_casements  │  │
└───────────────────┘   │         │         │   │  │  ...                │  │
                        │         ▼         │   │  └─────────────────────┘  │
                        │  ┌─────────────┐  │   │           │               │
                        │  │ Na__Viewport│  │   │           ▼               │
                        │  │ __Validation│  │   │    na_onConfigChange()    │
                        │  │             │  │   └───────────────────────────┘
                        │  │  Validate   │  │              │
                        │  │   Config    │  │              │
                        │  └──────┬──────┘  │              │
                        │         │         │              │
                        │    SVG Valid?     │              │
                        │         │         │              │
                        └─────────┼─────────┘              │
                                  ▼                        │
                              ┌───────┐                    │
                              │  YES  │────────────────────┘
                              └───────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                     Bridge.js (na_sendLiveUpdate)                          │
│                     Debounced 100ms → sketchup.na_liveUpdate(configJson)   │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      RUBY BACKEND - DialogManager                           │
│                      na_handle_live_update()                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  1. Parse JSON config                                               │    │
│  │  2. Find target window component (from SelectionObserver)           │    │
│  │  3. Start SketchUp operation                                        │    │
│  │  4. Call GeometryEngine.na_update_window_geometry()                 │    │
│  │  5. Save data via DataSerializer                                    │    │
│  │  6. Commit operation                                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GeometryEngine.na_update_window_geometry()               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Clear existing geometry in component definition                    │    │
│  │  ┌────────────────────────────────────────────────────────────────┐ │    │
│  │  │ Calculate dimensions from config:                              │ │    │
│  │  │  • num_openings = mullions + 1                                 │ │    │
│  │  │  • inner_width = width - left_frame - right_frame              │ │    │
│  │  │  • inner_height = height - top_frame - bottom_frame            │ │    │
│  │  │  • opening_width = available_width / num_openings              │ │    │
│  │  │  • Multi-casement: panel_width = opening_width / panels_count  │ │    │
│  │  └────────────────────────────────────────────────────────────────┘ │    │
│  │                                                                     │    │
│  │  Create geometry via GeometryBuilders:                              │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │ Outer Frame  │  │   Mullions   │  │  Casements   │               │    │
│  │  │ (4 pieces)   │  │ (0-6 pieces) │  │ (per opening)│               │    │
│  │  │              │  │              │  │ 1-6 per      │               │    │
│  │  │ Left Stile   │  │  Mullion_1   │  │ opening      │               │    │
│  │  │ Right Stile  │  │  Mullion_2   │  │ (4 pieces ea)│               │    │
│  │  │ Bottom Rail  │  │  ...         │  │ Individual   │               │    │
│  │  │ Top Rail     │  │              │  │ rail sizes   │               │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │    Glass     │  │  Glaze Bars  │  │     Cill     │               │    │
│  │  │ (per casemt) │  │ (H & V bars) │  │  (optional)  │               │    │
│  │  │ Direct glzd  │  │ Per opening  │  │ Configurable │               │    │
│  │  │ if removed   │  │ or casement  │  │ height/depth │               │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## JavaScript Module Dependency Graph

```
┌────────────────────────────────────────────────────────────────┐
│                     HTML DIALOG LOADS:                         │
└────────────────────────────────┬───────────────────────────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 │               │               │
                 ▼               ▼               ▼
         ┌──────────┐    ┌──────────┐    ┌──────────┐
         │  Ui__    │    │ Viewport_│    │ Export__ │
         │  Config  │    │   _*     │    │   Dxf    │
         └────┬─────┘    └────┬─────┘    └────┬─────┘
              │               │               │
              └───────┬───────┴───────┬───────┘
                      │               │
              ┌───────┴───────┐       │
              ▼               ▼       │
         ┌──────────┐    ┌──────────┐│
         │  Ui__    │    │  Ui__    ││
         │ Controls │    │  Events  ││
         └────┬─────┘    └────┬─────┘│
              │               │      │
              └───────┬───────┘      │
                      │              │
                      ▼              ▼
              ┌───────────────────────┐
              │   UiLogic (Main)      │
              │   ├─ Na_DynamicUI     │
              │   └─ Na_Viewport      │
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  UiEventToRubyApiBridge│
              │  ├─ sketchup.* calls  │
              │  └─ window.na_* funcs │
              └───────────────────────┘
```

## Ruby Module Dependency Graph

```
┌────────────────────────────────────────────────────────────────┐
│                      Main__.rb (Entry)                         │
│                      require_relative all:                     │
└────────────────────────────────┬───────────────────────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ▼                        ▼                        ▼
┌───────────────┐     ┌────────────────┐      ┌──────────────────┐
│ DialogManager │     │ GeometryEngine │      │  PlacementTool   │
│  ├─ Bridge    │     │  ├─ Create     │      │  └─ DebugTools   │
│  ├─ Callbacks │     │  ├─ Update     │      └──────────────────┘
│  ├─ DxfExport │     │  └─ Builders   │
│  └─ FuseParts │     └────────┬───────┘      ┌──────────────────┐
└───────┬───────┘              │              │   Observers      │
        │                      ▼              │  └─ DataSerial   │
        │              ┌───────────────┐      └──────────────────┘
        │              │GeometryBuilder│
        │              │ └─ Helpers    │      ┌──────────────────┐
        │              └───────┬───────┘      │   FuseParts      │
        │                      │              │  ├─ outer_shell   │
        │                      ▼              │  ├─ trim          │
        │              ┌───────────────┐      │  └─ DebugTools   │
        └──────────────│GeometryHelpers│      └──────────────────┘
                       │  (Primitives) │
                       └───────────────┘
                               │
                               ▼
                       ┌───────────────┐
                       │DataSerializer │
                       │  (Shared)     │
                       └───────────────┘
```

---

## Current Configuration Schema (v0.6.0)

```javascript
// Window Metadata (new in v0.6.0)
windowMetadata: [{
    WindowUniqueId: "AWN001",           // Auto-generated unique ID (AWNxxx format)
    WindowName: "Na Window",            // Window name
    WindowDescription: "",              // User description suffix (e.g., "GroundFloor__Lounge")
    WindowNotes: "...",                 // Notes
    CreatedDate: "2026-02-16 10:44:49", // ISO creation date
    LastModified: "2026-02-16 10:44:49" // ISO last modified date
}]

// Component Naming Convention (v0.6.0):
// Instance Name:   AWN001__Window__  or  AWN001__Window__GroundFloor__Lounge
// Definition Name: AWN001__Window__  or  AWN001__Window__GroundFloor__Lounge

windowConfiguration: {
    // Primary Dimensions
    width_mm: 900,              // Overall window width
    height_mm: 1200,            // Overall window height (300-2600mm in UI)
    frame_thickness_mm: 50,     // Base outer frame member thickness fallback
    advanced_frame_controls: false, // Toggle for per-side frame thickness overrides
    frame_top_thickness_mm: 50, // Top frame thickness when advanced override is enabled
    frame_bottom_thickness_mm: 50, // Bottom frame thickness when advanced override is enabled
    frame_left_thickness_mm: 50, // Left frame thickness when advanced override is enabled
    frame_right_thickness_mm: 50, // Right frame thickness when advanced override is enabled
    
    // Casement
    casement_width_mm: 65,      // Default casement profile width (all sides)
    casement_sizes_individual: false, // Toggle for individual sizing
    casement_top_rail_mm: 65,   // Top rail width (when individual)
    casement_bottom_rail_mm: 65,// Bottom rail width (when individual, 20-500mm in UI)
    casement_left_stile_mm: 65, // Left stile width (when individual)
    casement_right_stile_mm: 65,// Right stile width (when individual)
    casement_depth_mm: 55,      // Casement profile depth (Y direction, 40-100mm)
    casement_inset_mm: 10,      // Casement inset from frame face (0=flush, 0-100mm)
    casements_per_opening: 1,   // Casement panels per opening (1-6, for bifold/concertina systems)
    sliding_sash_overlap_mm: 20,// Extra height added to lower sash in sliding mode (0-60mm)
    removed_casements: [],      // Array of "openingIndex:cellIndex:panelIndex" keys (per-panel; legacy bare integers auto-migrate)
    
    // Mullions (vertical dividers)
    mullions: 0,                // Number of mullions (0-6)
    mullion_width_mm: 40,       // Mullion member width
    
    // Glass
    glass_thickness_mm: 20,     // Glazing panel thickness (5-35mm, centered on casement)
    
    // Glaze Bars
    horizontal_glaze_bars: 0,   // Horizontal bars per opening
    vertical_glaze_bars: 0,     // Vertical bars per opening
    glaze_bar_width_mm: 25,     // Glaze bar width
    glazebar_inset_mm: 10,      // Glaze bar inset from casement face (0-20mm, dynamic max)
    
    // Cill & Frame
    has_cill: true,             // Include cill
    cill_depth_mm: 50,          // Cill projection from frame
    cill_height_mm: 50,         // Cill profile height
    frame_depth_mm: 70,         // Frame depth (Y direction)
    frame_wall_inset_mm: 0,     // Frame inset into wall reveal (-50 to 150mm)
    
    // Display Options
    show_dimensions: true,         // Show dimension annotations
    show_casements: true,          // Show casement frames
    sliding_sash_window: false,    // Sliding sash mode: two stacked casements per panel, lower sash set back in 3D
    
    // Material Selection (v0.9.0)
    frame_material_id: "MAT120__GenericWood",  // Frame finish from MaterialsLibrary
    paint_cill: false,                          // Paint cill same as frame (default: Sapele timber)
    
    // Post-Processing (v0.8.0)
    fuse_parts: false              // Fuse individual parts into simplified solids (heavy operation)
}

// Available Frame Materials (v0.9.0):
// MAT120__GenericWood:                         Generic Wood (#D2B48C)
// MAT301__Paint__FarrowAndBall__Ammonite:      Ammonite (F&B 274) (#DDD8CF)
// MAT302__Paint__FarrowAndBall__Wevet:         Wevet (F&B 273) (#EEE9E7)
// MAT303__Paint__FarrowAndBall__Mizzle:        Mizzle (F&B 266) (#C0C2B3)
// MAT304__Paint__FarrowAndBall__DownPipe:      Down Pipe (F&B 026) (#626664)

// Standard Materials Created:
// Glass:  MAT101__Glass__ClearDefault (all glass panels)
// Cill:   MAT541__Timber__Sapele (when paint_cill is false)
//         OR same as frame_material_id (when paint_cill is true)
```

---

## IMPLEMENTED FEATURE: Sliding Sash Window Mode

### Concept

```
STANDARD CASEMENT MODE (sliding_sash_window = false):
Each horizontal panel in an opening has one full-height casement.

SLIDING SASH MODE (sliding_sash_window = true):
Each horizontal panel in an opening has:
  - Top sash casement
  - Bottom sash casement
Bottom sash is set back by casement_depth in 3D to simulate real sash overlap.
```

### Behavior Summary

- Uses existing `casements_per_opening` horizontal panelization (1-6) and applies sash stacking inside each panel.
- 2D preview draws two stacked casements per panel, with a 20% black shade over the lower sash for depth cue.
- 3D geometry creates two casements per panel; lower sash uses `frame_wall_inset + casement_depth`.
- Glaze bars are generated per sash via existing casement glass/bar pipeline (no duplicate bar logic).
- Backward compatibility is maintained: missing `sliding_sash_window` defaults to `false`.

---

## PROPOSED FEATURE 1: Per-Casement Element Size Adjustment

### UI Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Casement Width                                               65mm          │
│  ═══════════════════●═══════════════════════════════        ┌──────┐       │
│                                                              │  65  │       │
│  ┌─────────────────────────────────────────────────────┐    └──────┘       │
│  │ ▼ Individual Casement Sizes                         │ ← Expandable      │
│  └─────────────────────────────────────────────────────┘   Toggle/Arrow    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐
│  │  (Expanded Panel - shows when toggle is clicked)                        │
│  │                                                                         │
│  │  Top Rail                                                    65mm       │
│  │  ═══════════════════●═══════════════════════════════       ┌──────┐    │
│  │                                                             │  65  │    │
│  │                                                             └──────┘    │
│  │  Bottom Rail                                                 220mm      │
│  │  ═══════════════════════════════════════●═══════════       ┌──────┐    │
│  │                                                             │ 220  │    │
│  │                                                             └──────┘    │
│  │  Left Stile                                                  65mm       │
│  │  ═══════════════════●═══════════════════════════════       ┌──────┐    │
│  │                                                             │  65  │    │
│  │                                                             └──────┘    │
│  │  Right Stile                                                 95mm       │
│  │  ═══════════════════════●═══════════════════════════       ┌──────┐    │
│  │                                                             │  95  │    │
│  │                                                             └──────┘    │
│  └─────────────────────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────────────────────┘
```

### New Config Fields

```javascript
// NEW FIELDS:
casement_sizes_individual: false,    // Toggle for individual sizing
casement_top_rail_mm: 65,            // Top rail width
casement_bottom_rail_mm: 65,         // Bottom rail width (e.g., 220 for doors)
casement_left_stile_mm: 65,          // Left stile width
casement_right_stile_mm: 65,         // Right stile width
```

### Geometry Impact

```
CURRENT (casement_width_mm = 65):        PROPOSED (individual sizes):
┌──────────────────────────┐             ┌──────────────────────────┐
│ ┌──────────────────────┐ │             │ ┌──────────────────────┐ │
│ │  65   ┌────────┐ 65  │ │             │ │  65   ┌────────┐ 95  │ │  ← Different
│ │ ══════│ GLASS  │═════│ │             │ │ ══════│ GLASS  │═════│ │    stiles
│ │ ║     │        │    ║│ │             │ │ ║     │        │    ║│ │
│ │ ║     │        │    ║│ │             │ │ ║     │        │    ║│ │
│ │ ║ 65  │        │ 65 ║│ │             │ │ ║ 65  │        │ 65 ║│ │
│ │ ║     │        │    ║│ │             │ │ ║     │        │    ║│ │
│ │ ══════│        │═════│ │             │ │ ══════│        │═════│ │
│ │  65   └────────┘ 65  │ │             │ │  65   └────────┘ 220 │ │  ← Wide
│ └──────────────────────┘ │             │ └──────────────────────┘ │    bottom
└──────────────────────────┘             └──────────────────────────┘    rail
        Same all around                      Different per side
```

---

## IMPLEMENTED FEATURE: Casements Per Opening (Multi-Panel Support)

### Concept

```
1 CASEMENT PER OPENING (Default):

    Frame Opening
┌─────────────────────────┐
│ ┌─────────────────────┐ │
│ │                     │ │
│ │   Single Casement   │ │
│ │                     │ │
│ │   ┌─────────────┐   │ │
│ │   │             │   │ │
│ │   │    GLASS    │   │ │
│ │   │             │   │ │
│ │   └─────────────┘   │ │
│ │                     │ │
│ └─────────────────────┘ │
└─────────────────────────┘

2 CASEMENTS PER OPENING (Double Doors / French Doors):

    Frame Opening
┌─────────────────────────┐
│ ┌──────────┐┌──────────┐│
│ │          ││          ││
│ │  Panel A ││ Panel B  ││
│ │ ┌──────┐ ││ ┌──────┐ ││
│ │ │GLASS │ ││ │GLASS │ ││
│ │ └──────┘ ││ └──────┘ ││
│ └──────────┘└──────────┘│
└─────────────────────────┘
    No mullion between!

4 CASEMENTS PER OPENING (Bifold / Concertina):

    Frame Opening
┌──────────────────────────────────────────┐
│ ┌────────┐┌────────┐┌────────┐┌────────┐│
│ │ Panel  ││ Panel  ││ Panel  ││ Panel  ││
│ │   A    ││   B    ││   C    ││   D    ││
│ │┌──────┐││┌──────┐││┌──────┐││┌──────┐││
│ ││GLASS │││|GLASS │││|GLASS │││|GLASS │││
│ │└──────┘││└──────┘││└──────┘││└──────┘││
│ └────────┘└────────┘└────────┘└────────┘│
└──────────────────────────────────────────┘
```

### Use Cases

```
DOUBLE DOORS (No Mullions, 2 Casements Per Opening):

┌─────────────────────────────────────────┐
│ ┌─────────────────┐┌─────────────────┐  │
│ │    LEFT DOOR    ││   RIGHT DOOR    │  │
│ │   ┌─────────┐   ││   ┌─────────┐   │  │
│ │   │  GLASS  │   ││   │  GLASS  │   │  │
│ │   └─────────┘   ││   └─────────┘   │  │
│ │   ═══════════   ││   ═══════════   │  │  ← Wide bottom rails (220mm)
│ └─────────────────┘└─────────────────┘  │
└─────────────────────────────────────────┘


QUAD BIFOLD (No Mullions, 4 Casements Per Opening):

┌──────────────────────────────────────────────────────────┐
│ ┌────────────┐┌────────────┐┌────────────┐┌────────────┐│
│ │  Panel 1   ││  Panel 2   ││  Panel 3   ││  Panel 4   ││
│ │ ┌────────┐ ││ ┌────────┐ ││ ┌────────┐ ││ ┌────────┐ ││
│ │ │ GLASS  │ ││ │ GLASS  │ ││ │ GLASS  │ ││ │ GLASS  │ ││
│ │ └────────┘ ││ └────────┘ ││ └────────┘ ││ └────────┘ ││
│ └────────────┘└────────────┘└────────────┘└────────────┘│
└──────────────────────────────────────────────────────────┘
```

### Config Field

```javascript
casements_per_opening: 1,    // 1-6 casement panels per opening (slider in Advanced Casement Controls)
```

### Geometry Calculation

```ruby
num_openings = num_mullions + 1
casements_per_opening = config["casements_per_opening"].clamp(1, 6)
opening_width = available_width / num_openings
panel_width = opening_width / casements_per_opening

# Each panel gets equal width within the opening
(0...casements_per_opening).each do |p|
    panel_x = opening_x + (p * panel_width)
    # Create casement frame, glass, and glaze bars at panel_x
end
```

---

## Current File Structure (Version 0.8.0)

### Ruby Backend Modules (12 files)

| File | Lines | Purpose |
|------|-------|---------|
| `Na__...__Main__.rb` | 240 | Entry point, module loader, constants |
| `Na__...__DialogManager__.rb` | 720 | HtmlDialog lifecycle, Ruby ↔ JS bridge, stale-update guard, fuse integration |
| `Na__...__GeometryEngine__.rb` | 508 | Geometry orchestration, opening calculations |
| `Na__...__GeometryBuilders__.rb` | 312 | High-level element builders (frame, casement, glass, cill) |
| `Na__...__GeometryHelpers__.rb` | 231 | Low-level geometry primitives |
| `Na__...__FuseParts__.rb` | 507 | Post-processing: per-panel boolean fusion (outer_shell) and glass trimming |
| `Na__...__PlacementTool__.rb` | 278 | Interactive placement with crosshair, TAB rotates 0/90/180/270° |
| `Na__...__MeasureOpeningTool__.rb` | 280 | Two-click opening measurement with blue overlay |
| `Na__...__Observers__.rb` | 82 | SelectionObserver for Live Mode |
| `Na__...__DataSerializer__.rb` | 517 | Save/load window data, ID generation, direct instance loader |
| `Na__...__DebugTools__.rb` | 317 | Debug logging utilities |
| `Na__...__DxfExporterLogic__.rb` | 489 | Full DXF CAD export |

### JavaScript Frontend Modules (9 files)

| File | Lines | Purpose |
|------|-------|---------|
| **UI Layer (Ui__)** | | |
| `Na__...__Ui__Config__.js` | 293 | Configuration constants for all controls |
| `Na__...__Ui__Controls__.js` | 175 | HTML generation (slider, toggle, color, expandable) |
| `Na__...__Ui__Events__.js` | 180 | Event handler attachment with callbacks |
| **Viewport Layer (Viewport__)** | | |
| `Na__...__Viewport__Validation__.js` | 137 | Config validation, error display |
| `Na__...__Viewport__SvgGenerator__.js` | 348 | SVG markup generation, rendering engine |
| `Na__...__Viewport__Controls__.js` | 195 | Pan/zoom/click interaction |
| **Export Layer (Export__)** | | |
| `Na__...__Export__Dxf__.js` | 93 | Browser-side DXF generation (fallback) |
| **Main & Bridge** | | |
| `Na__...__UiLogic__.js` | 526 | Main orchestrator, state management |
| `Na__...__UiEventToRubyApiBridge__.js` | 566 | Ruby ↔ JS communication, Live Mode, metadata cache |

### HTML & CSS

| File | Purpose |
|------|---------|
| `Na__...__UiLayout__.html` | Dialog structure, dynamic control containers |
| `Na__...__Styles__.css` | UI styling, layout, control styles |

### Modification Guide for New Features

| Feature | Files to Modify |
|---------|-----------------|
| **New UI Control** | `Ui__Config__.js` (add config), `Ui__Controls__.js` (add HTML generator) |
| **New Control Type** | `Ui__Controls__.js` (generator), `Ui__Events__.js` (handler) |
| **Change Validation** | `Viewport__Validation__.js` |
| **Change SVG Rendering** | `Viewport__SvgGenerator__.js` |
| **New Export Format** | Create new `Export__[Format]__.js` module |
| **Ruby Geometry Logic** | `GeometryEngine__.rb` and/or `GeometryBuilders__.rb` |
| **New Geometry Primitive** | `GeometryHelpers__.rb` |
| **New Viewport Tool** | Create new `[ToolName]Tool__.rb`, add callback in `DialogManager__.rb`, add JS bridge function |
| **Post-Processing** | `FuseParts__.rb` (modify fusion/trim logic), `DialogManager__.rb` (integration point) |

---

## Implementation Guide (Modular Architecture)

### Adding New UI Controls

1. **`Ui__Config__.js`** - Add config object to appropriate array
2. **`Ui__Controls__.js`** - Add HTML generator if new control type
3. **`Ui__Events__.js`** - Add event handler if new control type
4. **`Styles__.css`** - Add styles for new control (if needed)
5. **Test** - Verify control appears and responds

### Adding New Validation Rules

1. **`Viewport__Validation__.js`** - Add validation logic to `na_validateConfig()`
2. **Test** - Verify errors display in status bar

### Modifying SVG Rendering

1. **`Viewport__SvgGenerator__.js`** - Update `na_generateWindowSvg()` or related functions
2. **Test** - Verify preview renders correctly

### Modifying Ruby Geometry

1. **`GeometryEngine__.rb`** - Update orchestration logic if needed
2. **`GeometryBuilders__.rb`** - Update high-level builders
3. **`GeometryHelpers__.rb`** - Update primitives if needed
4. **Test** - Verify 3D geometry matches 2D preview

### Adding Export Formats

1. Create new **`Export__[Format]__.js`** module (copy DXF as template)
2. Add to **`UiLayout__.html`** script includes
3. Update **`UiLogic__.js`** to expose export function
4. Add button in HTML and call via bridge
5. **Test** - Verify export generates correctly

---

## Modular Architecture Benefits (Version 0.5.0+, Updated v0.6.0)

### JavaScript Modularization
- **Single Responsibility:** Each module has one clear purpose (Config, Controls, Events, Validation, Rendering, etc.)
- **Maintainability:** Average module size 227 lines vs. 1,408-line monolith
- **Testability:** Pure functions can be unit tested independently
- **Scalability:** Easy to add new control types, validation rules, or export formats
- **Load Order:** Modules load in dependency order via HTML script tags
- **Global Namespace:** IIFE pattern with `window` exports for SketchUp compatibility

### Ruby Modularization  
- **Separation of Concerns:** Dialog, Geometry, Tools, Observers clearly separated
- **Reusability:** GeometryBuilders can be reused for door configurator, curtain walls
- **Maintainability:** Main.rb reduced from 1,504 → 232 lines (85% reduction)
- **Testing:** Individual modules can be tested in isolation
- **Clear Dependencies:** Explicit `require_relative` with namespace references

### Inter-Module Communication
- **JavaScript:** Global `window` object exports (e.g., `window.Na__Ui__Controls`)
- **Ruby:** Module methods accessed via namespace (e.g., `DialogManager.na_show_dialog`)
- **JS ↔ Ruby Bridge:** HtmlDialog callbacks (`sketchup.na_*`) and execute_script (`window.na_*`)

---

*Document created: February 3, 2026*
*Last updated: April 27, 2026 (v0.10.4 - Per-panel casement toggle)*
*Author: Noble Architecture*
