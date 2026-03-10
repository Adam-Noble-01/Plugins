# Na Insert Primatives - Development Log
# =============================================================================

# =============================================================================

## Version 0.4.5 - 10-Mar-2026 - Remove Imperial Units

### Update — Metric-Only VCB Input
- Removed `in`, `ft`, `yd` entries from `NA_UNIT_CONVERSIONS_TO_MM` hash.
- Simplified `NA_UNIT_SUFFIX_PATTERN` regex: `(mm|cm|m|in|ft|yd)?` → `(mm|cm|m)?`.
- Updated all comments and user-facing strings to reference `mm | cm | m` only.
- VCB label: `"Cube: single value or X,Y,Z (mm | cm | m | in | ft | yd)"` → `"Cube: single value or X,Y,Z (mm | cm | m)"`.
- Activate console output: `"Units: mm cm m in ft yd"` → `"Units: mm cm m"`.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.4 - 10-Mar-2026 - 4-Step Rotation + Tab Double-Press Fix

### Research Findings — Tab Double-Press
Using `onKeyUp` alone caused Tab to require a double press. Root cause: SketchUp's focus
management consumes the `onKeyUp` event on alternating presses for certain keys (same mechanism
documented for the Alt key in bug report SKEXT-3890). The fix is `onKeyDown` with a
`@key_tab_held` guard that prevents acting on the SKEXT-3890 double-fire and also prevents
acting on typematic repeats. `onKeyUp` is kept solely to reset the held flag.

### Update 01 — Tab Double-Press Fix
- Replaced `onKeyUp`-only handler with `onKeyDown` + `onKeyUp` key-state pattern.
- `@key_tab_held` flag: set to `true` on first `onKeyDown`, reset to `false` on `onKeyUp`.
- `onKeyDown` only acts when `@key_tab_held` is `false` (key transitioning from up → down).
- Suppresses both SKEXT-3890 double-fire and typematic repeats with no timer hacks.

### Update 02 — 4-Step Rotation Cycle
- Replaced boolean `@rotated` toggle with integer `@rotation_step` (0-3, wraps at 4).
- Each Tab press advances one step: 0° → 90° → 180° → 270° → 0°.
- `@last_rotation_state` now stores an integer step (was boolean).
- `Na__Preview__BuildCubeCorners` updated with full 4-case rotation using CCW rotation math.
- `Na__Preview__DrawCubeBox` signature updated to pass `rotation_step`.
- Status bar now shows current degree value: `"Rotation: 90° [TAB to rotate]"`.
- `NA_ROTATION_STEPS = [0, 90, 180, 270]` constant added for display lookup.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__KeyboardHandlers__.rb`**
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__3dPreviewGraphics__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.3 - 10-Mar-2026 - Keyboard Handlers Extraction

### Update — Keyboard and VCB Logic Extracted to Dedicated Mixin
- Created `Na__InsertPrimatives__KeyboardHandlers__.rb` as a Ruby mixin module (`module Na__InsertPrimatives::KeyboardHandlers`).
- Included into `PrimitiveCubeTool` via `include Na__InsertPrimatives::KeyboardHandlers`.
- Mixin has full access to the host class instance variables (`@rotated`, `@cube_size_x/y/z`, etc.) at runtime.
- Moved from `Main__.rb` into the mixin:
  - `NA_ROTATION_KEY = 9` constant
  - `onKeyUp` key handler
  - `enableVCB?` callback
  - `onUserText` VCB input handler
  - `na_key__update_status_text` private helper (renamed from `Na__Primitive__UpdateStatusText` to lowercase to avoid Ruby constant-lookup ambiguity when called without `()`)
- `activate` and `resume` in `Main__.rb` updated to call `na_key__update_status_text()`.
- Added `require_relative 'Na__InsertPrimatives__KeyboardHandlers__'` to `Main__.rb`.
- Updated MODULE ARCHITECTURE comment in `Main__.rb` header.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__KeyboardHandlers__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.2 - 10-Mar-2026 - Rotation Key: Shift → Tab

### Research Findings
Three reasons Shift rotation never worked:
1. **Wrong constant**: `COPY_MODIFIER_KEY` = Ctrl on PC, not Shift. Shift is `CONSTRAIN_MODIFIER_KEY`. The code never matched a Shift press.
2. **SKEXT-3890 double-fire regression**: `onKeyDown` fires twice per press on Windows since 23.1.340. A toggle would turn on then immediately off. Still open and unresolved as of 2026.
3. **VCB interference**: With `enableVCB?` returning `true`, pressing Shift while typing in the VCB (e.g. uppercase "2M") would trigger the rotation toggle mid-input.

### Fix Applied
- Replaced `onKeyDown` with `onKeyUp`. `onKeyUp` fires exactly once per key release and is unaffected by SKEXT-3890.
- Changed rotation key from `COPY_MODIFIER_KEY` (Ctrl) to Tab (raw key code `9`). The SketchUp Ruby API does not export `VK_TAB`, so the raw integer is used.
- Tab does not send characters to the VCB, is unassigned by default, and eliminates all three issues.
- Added `NA_ROTATION_KEY = 9` class constant inside `PrimitiveCubeTool` for readability.
- Updated all user-facing hint text: `"SHIFT to rotate"` → `"TAB to rotate"`.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.2.4 - 10-Mar-2026 - Preview Graphics Extraction + Visual Tweaks

### Update 01 — Extract Rendering to Dedicated Module
- Created `Na__InsertPrimatives__3dPreviewGraphics__.rb`.
- Moved `Na__Primitive__DrawCrosshair` → `Na__Preview__DrawCrosshair(view, cursor_pos, arm_size)` (stateless, parameters only).
- Moved `Na__Primitive__BuildCubeCorners` → `Na__Preview__BuildCubeCorners(origin, sx, sy, rotated)` (stateless, parameters only).
- Moved `Na__Primitive__DrawCubePreview` → `Na__Preview__DrawCubeBox(view, origin, sx, sy, sz, rotated)` (stateless, parameters only).
- `Na__Preview__BuildCubeCorners` is now shared by both the preview renderer and the geometry engine (`CreateCubeGeometry`, `RegenerateCube`).
- `Main__.rb` `draw` method delegates entirely to the graphics module; no rendering logic remains in the tool class.
- Added `require_relative 'Na__InsertPrimatives__3dPreviewGraphics__'` to `Main__.rb`.
- Updated module architecture comment in `Main__.rb` header.

### Update 02 — Preview Box Visual Tweaks
- Line width: `1` → `2` (thicker).
- Colour: `Color(0, 220, 255, 180)` → `Color(0, 160, 200, 210)` (darker teal, slightly more opaque).

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__3dPreviewGraphics__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.2.3 - 10-Mar-2026 - Rotation Toggle + VCB Single-Value

### Update 01 — Shift-Key 90° Z-Rotation Toggle
- Added `@rotated` and `@last_rotation_state` instance variables to `PrimitiveCubeTool`.
- Added `onKeyDown` handler: pressing Shift toggles `@rotated` between `false` (0°) and `true` (90° CCW around Z).
- Added `Na__Primitive__UpdateStatusText` private helper — keeps the status bar in sync with rotation state; called from `activate`, `resume`, and `onKeyDown`.
- Added `Na__Primitive__BuildCubeCorners(origin, rotated)` private helper — single source of truth for all corner geometry. When `rotated` is `true`, the +X axis maps to +Y and +Y maps to −X (90° CCW).
- Refactored `Na__Primitive__DrawCubePreview`, `Na__Primitive__CreateCubeGeometry`, and `Na__Primitive__RegenerateCube` to all delegate corner calculation to `Na__Primitive__BuildCubeCorners`.
- `@last_rotation_state` is stored at placement time so VCB-triggered regeneration rebuilds the cube with the same orientation it was originally placed in.
- Live preview wireframe reflects rotation in real-time as user toggles.

### Update 02 — VCB Single-Value Broadcast
- Updated `Na__VcbInput__ParseDimensions` to accept 1 token or 3 tokens.
  - 1 token: value is broadcast to all three dimensions (e.g. `"1m"` → 1000mm × 1000mm × 1000mm).
  - 3 tokens: unchanged X,Y,Z behaviour.
  - Any other count raises `ArgumentError` with a clear message.
- Updated VCB label to `"Cube: single value or X,Y,Z (mm | cm | m | in | ft | yd)"`.
- Updated file header comment in `VcbFunctions__.rb` to document single-value mode.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**

### Status: IMPLEMENTED

# =============================================================================
## Version 0.2.2 - 10-Mar-2026 - Preview + VCB Multi-Unit Support

### Update 01 — 3D Ghost Cube Preview
- Added `Na__Primitive__DrawCubePreview` private method to `PrimitiveCubeTool`.
- Draws a dashed cyan wireframe box at the snapped cursor position in real-time using `view.draw(GL_LINES, edge_points)`.
- Preview dimensions reflect the current `@cube_size_x/y/z` stored in the tool, updating immediately after VCB input.
- Crosshair drawing extracted into `Na__Primitive__DrawCrosshair` private method to keep `draw` clean.

### Update 02 — VCB Multi-Unit Input Module
- Created `Na__InsertPrimatives__UserInput__VcbFunctions__.rb` loaded via `require_relative` from `Main__.rb`.
- Unit conversion constants: `NA_UNIT_CONVERSIONS_TO_MM` (mm, cm, m, in, ft, yd).
- `Na__VcbInput__ParseSingleDimension(str)` — parses a single token with optional unit suffix; bare numbers default to mm.
- `Na__VcbInput__ParseDimensions(text)` — splits comma-separated input, delegates each token to `ParseSingleDimension`, returns `[x, y, z]` in SketchUp internal lengths.
- `Na__VcbInput__UpdateDisplay(x, y, z)` — sets VCB value and updates label to `"Cube X,Y,Z (mm | cm | m | in | ft | yd)"`.
- `onUserText` in `PrimitiveCubeTool` refactored to call `Na__VcbInput__ParseDimensions`; error messages surface the `ArgumentError` message directly.
- `update_vcb_display` instance method removed; all display calls now go through `Na__VcbInput__UpdateDisplay`.
- Private geometry helpers renamed to `Na__Primitive__*` convention: `Na__Primitive__CreateCubeGeometry`, `Na__Primitive__RegenerateCube`.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================
## Version 0.2.0 - 10-Mar-2026 - Plugin Modularisation

### Update 01 - Restructure into Loader + Modules Pattern
- Migrated from a single flat file to a loader + modules subdirectory architecture.
- Pattern mirrors the `Na__WindowConfiguratorTool` structure for consistency.
- The plugins root now contains only the loader; all logic lives under the modules folder.
- Future features can be added as individual `.rb` files inside the modules folder and loaded via `require_relative` in `Main__.rb`.

### Files Added:
1. **`Na__InsertPrimatives__Loader__.rb`** (plugins root)
   - Handles path setup, `require` of `Main__.rb`, `UI::Command` creation, and Plugins menu registration.
   - Guards against double-loading with `file_loaded?` / `file_loaded`.
2. **`Na__InsertPrimatives__Modules__\Na__InsertPrimatives__Main__.rb`**
   - Contains `Na__InsertPrimatives` module, `PrimitiveCubeTool` class, grid-snapping helper, and `Na__InsertPrimatives__InsertCube` entry point.
   - No startup wiring — all UI registration delegated to the loader.

### Files Removed:
1. **`Na__InsertPrimatives__Main__.rb`** (plugins root)
   - Deleted; replaced by the loader + modules structure above.

### Status: IMPLEMENTED

# =============================================================================
