# Na Noble3d - Face Pattern Generator - Development Log
# =============================================================================
# Module : 20__SourceCode__FacePatternGenerator
# Plugin : Na Noble3d Modelling Tools
# Tab    : Geometry Tools > Surface Pattern Tools

## Overview

Unified parametric surface pattern generator that reads a single selected
SketchUp face, previews seven architectural pattern types in an SVG HtmlDialog,
and applies the generated linework back onto the face plane.

# =============================================================================
# VERSION HISTORY
# =============================================================================


# Na Noble3d Modelling Tools
## Version 0.6.2 - 31-Aug-2026 - Floor Tiling Setting-Out Offset (Slider + Typed Box)

### Update 01 - New Field Type: Slider
- `Na__FacePattern__DynamicUI__.js` gains a third control type, `slider`: a range input and a number box side by side, both driving one value. The box carries the field id so `na_getValues` and the `applies` preset mechanism keep working unchanged; the range takes `<id>_slider`. Dragging the range writes the box then fires the shared change handler, and typing in the box writes the range back.
- `slider_min` / `slider_max` set the range travel independently of the box's own `min` / `max`, so the slider can stay usable while the box still accepts a value beyond its travel.
- New `na_isNumericField` covers `number` and `slider` everywhere a value is read or coerced. `na_applyPresetValues` also syncs a paired range, so a preset writing into a slider field moves both halves.
- New `.naFacePat__SliderRow`, `.naFacePat__Slider` and `.naFacePat__Input--withSlider` styles; the range picks up `--na-accent-blue` through `accent-color`.

### Update 02 - Offset X / Offset Y on Floor Tiling
- Two `slider` fields sitting with **Setting Out**, which is what they modify: range travel +/-1500mm, box accepting +/-20000mm, 1mm steps, default 0. Either sign, so a layout can be pulled toward a corner from any direction.
- Applied in **pattern space**, inside `na_layoutOrigin`, so a rotated layout nudges along its own grid rather than across it. At the default 0 degree rotation, pattern space and face space coincide and X / Y read exactly as they look.
- Every builder derives its row, column and lattice ranges from that origin, so shifting it only changes which indices are visited — coverage stays complete at any offset, with no change to the extent padding.
- The status line names the offset when either value is non-zero.

### Validation
- Offsets move every vertex by exactly the amount asked (checked against a one-to-one match of whole units after an equal shift, at six offsets including fractional and negative).
- Gapless at six offsets across all seven bond options: 100% area, zero overlaps, zero uncovered sample points.
- Offset is periodic on the layout's own lattice — one tile pitch for the grid bonds, `u = (Lj+Wj, Lj-Wj)` and `v = (-Wj, Wj)` for herringbone, one block for basketweave — each reproducing the base layout exactly.
- A 45 degree layout nudged 100mm in pattern X lands on the predicted `(100/root2, 100/root2)` face-space position.
- `undefined`, `null`, `''`, `'abc'`, `NaN` and `Infinity` all fall back to 0 rather than emptying the preview.
- Slider and box stay in step in both directions; the box still reports a Number, not a string; size presets still write correctly with slider fields present.

---
# Na Noble3d Modelling Tools
## Version 0.6.1 - 31-Aug-2026 - Face Basis Cannot Collapse Silently

### Update 01 - Reported Symptom
- After 0.6.0 the dialog showed **Face bounds: 0.0mm × 0.0mm** with an empty preview and the status line "Face refreshed from current selection." — a face was accepted but arrived with no size.

### Update 02 - Where It Is Not
- The dialog JavaScript was cleared. The assembled script blob (built exactly as `DialogManager.na_render_html` builds it) was run against a DOM stub and handed a healthy face payload: the meta line read back `Face bounds: 5745.0mm × 6500.0mm` and all seven patterns rendered, the new one included. Feeding the same harness a payload whose outer ring collapses to `[0, 0]` reproduces the reported readout **exactly**.
- So the payload reaches the dialog and the dialog consumes it correctly; the outline itself arrives collapsed. Nothing in 0.6.0 touches `FaceData__.rb`, which is what builds it.

### Update 03 - The Failure Mode in na_build_basis
- `Geom::Vector3d#normalize!` leaves a zero-length vector **unchanged** rather than raising. Every axis in `na_build_basis` was normalised with a bare `normalize!`, so a degenerate seed propagated silently: `x_axis` and `y_axis` end up zero, `vector.dot(zero)` is 0 for every vertex, all of `outer` becomes `[0, 0]`, and bounds come out 0 × 0. The dialog has no way to tell that from a real face.
- Every axis now goes through `na_unit_vector`, which returns nil rather than a zero vector, and the finished frame is checked by `na_axes_are_orthonormal?` before it is handed back. A basis that cannot be built is now a refusal with a message, never a silent zero.

### Update 04 - Horizontal Faces Get Fallback Seeds
- The horizontal branch had a single seed — the longest outer edge — and no recovery if it came back unusable. It now tries the longest edge, then world X, then world Y, re-squaring X against the chosen Y each time, so a horizontal slab always yields a valid frame. This is the branch every floor takes, and the floor pattern is what sends people to it.
- `NA_UP_SLOPE_MIN` keeps the original 0.001 branch point between pitched and horizontal deliberately: a slab with only a construction tolerance of fall must still align to its longest edge rather than to a direction made of floating point noise. **Verified across 20,041 face orientations** — including exactly horizontal, exactly vertical, and a sweep through the shallow band either side of the branch point — that the new derivation returns axes identical to the old one in every case where the old one was valid, and recovers in the two degenerate cases where it returned nil.

### Update 05 - Zero-Extent Guard
- `BuildSelectionPayload` now rejects a payload whose projected outline is smaller than 0.001mm in both directions, with a message naming the likely causes, rather than passing a 0 × 0 face to the dialog.

### Still Open
- **The root cause on the specific face is not yet confirmed.** The synthetic sweep never made the old code collapse — it returned nil instead — so the collapse depends on something only the live model shows: SketchUp's own `normalize!` on a near-zero vector, a `Length` comparison, or an edge whose endpoints coincide. `fpg_face_diagnostic.rb` prints the normal, the branch taken, the derived axes and the resulting bounds for the selected face and will name it in one run.

---
# Na Noble3d Modelling Tools
## Version 0.6.0 - 31-Aug-2026 - Floor Tiling Pattern (Slabs, Bonds, Herringbone)

### Update 01 - New Pattern Type: Floor Tiling
- Seventh pattern type `flooring` ("Floor Tiling"), sat directly under Patio in the pattern selector. Patio is a *random* greedy packer of six weighted module sizes; this is the deterministic counterpart — one tile size, one named bond, drawn as a hatch across the face.
- New JS preview generator `02__PatternGenerators/Na__FacePattern__FloorTilingGenerator__.js` (`window.Na__FacePattern__FloorTilingGenerator`). No Ruby builder: the units are plain polylines, so Apply goes through the existing generic `GeometryBuilder.ApplyPolylines` path and the Ruby `RectClip` mirror is untouched.

### Update 02 - Tile Size: Presets Plus Free Length and Width
- `Tile Size Preset` select writes `tile_length_mm` / `tile_width_mm` through the existing `applies` mechanism, and editing either number flips the select to Custom — the same behaviour slate and rosemary already have.
- Presets: 300x300, 450x450, 600x600, **600x400**, 900x600, 1000x500, 1200x600, 1200x200 plank, 600x100 and 280x70 parquet blocks, 200x100 paver, Custom. Default is 600 x 400.

### Update 03 - Bond / Layout
- `Bond / Layout` select: Stack (grid, straight in line), Running / Brick 1/2, Running 1/3, Running 1/4, Diagonal Grid 45°, Herringbone square to face, Herringbone 45°, Basketweave.
- Each option presets `offset_pct` and `rotation_deg`, both of which stay editable — the named bonds are one-click standards, not a closed list. Any course offset from 0 to 100% and any rotation from -180° to 180° is reachable by hand.
- The course offset **accumulates** rather than alternating, so 1/3 runs 0, 1/3, 2/3 before repeating (correct third bond); 1/2 degenerates to the familiar alternating brick bond.
- Basketweave blocks must be square to interlock. The block side is the tile length, the course count is `round(length / width)`, and the course width is fitted to divide the block exactly — the status line reports the fitted width whenever it differs from the value typed in.

### Update 04 - Joint Defaults to Zero (Gapless Hatch)
- `Joint / Gap (mm)` defaults to **0**: neighbouring tiles share an edge and the result reads as a hatch, which is what a plan-scale floor finish wants. Raising it insets every unit inside its lattice cell so all gaps read the same width, for detail-stage drawings.
- `Setting Out` select — **Centred on face** (default) puts a whole tile on the middle of the face so the perimeter cuts balance, the way a floor is actually set out; From face corner starts the first whole tile at the bounding box corner.

### Update 05 - General Herringbone Lattice
- Herringbone is generated from the lattice `u = (Lj + Wj, Lj - Wj)`, `v = (-Wj, Wj)` over cell sizes `Lj = length + joint`, `Wj = width + joint`, each lattice point carrying one lying tile and one standing tile against its right-hand end. The determinant is exactly `2 x Lj x Wj` — the pair's own area — so the tiling is gapless **at any tile proportion**, not only the classic 2:1. Verified at 600x300, 600x400, 600x100, 280x70, 1000x500, 1200x200, 450x450 and 900x250: 100.000% area coverage, zero overlapped sample points, zero uncovered sample points.
- The naive lattice `u = (L + W, W)` that works for 2:1 tiles overlaps for every other ratio; the `L - W` term in `u` is what generalises it.

### Update 06 - Rotation via a Pattern Space Frame
- Every layout is built in a rotated pattern space whose origin sits at the face bounding-box centre, then each unit's four corners are mapped back into face-local millimetres before clipping. Rotation is therefore free and exact for all three families — Diagonal Grid and Herringbone 45° are simply the named bonds with `rotation_deg` preset to 45.
- The pattern-space extent comes from the four face bounding-box corners mapped through the inverse rotation; the map is linear, so those corners bound the region.

### Update 07 - RectClip Generalised to Convex Units
- Rotated and herringbone units are convex quads, not axis-aligned rectangles, so `01__SharedJs/Na__FacePattern__RectClip__.js` gains `na_clipRingToConvex`, `na_clipUnitPolygon` and `na_unitPolygonPolylines` alongside the rectangle entry points.
- The window / opening-subtraction / full-cover logic is now shared by both in `na_clipUnitWindow`, which takes a clip function and a thunk for the untrimmed ring, so the whole-unit outline is only built on the path that returns it. **Verified byte-identical output** against the committed version for patio, brickwork, stonework, slate and rosemary across rectangular, L-shaped, hipped and holed faces with trim on and off — 40 combinations, no regression.

### Update 08 - Conditional Fields in DynamicUI
- `Na__FacePattern__DynamicUI__.js` gains a `showWhen: { source_field_id: ['allowed', 'values'] }` descriptor: a field's control group is hidden until every named source control holds one of its listed values. Used to drop `Course Offset (%)` for herringbone and basketweave, where it means nothing.
- Hidden groups keep their inputs in the DOM, so `na_getValues` still reports them and no generator has to care. No existing pattern uses `showWhen`, so all six other panels render exactly as before.

### Update 09 - Guard Rail
- A cell-count estimate runs before any unit is built. Past 24,000 units the generator returns no geometry and a status line naming the count and the limit, rather than locking the dialog up — reachable by typing a 5mm tile onto a large floor.

### Validation
- `node --check` clean; blob assembled exactly as `DialogManager.na_render_html` builds it, evaluated without error, and driven through a DOM stub: preset writes, custom flip-back, bond presets, and `showWhen` show/hide all behave.
- Coverage and overlap measured by point sampling on a plain rectangle, a concave L-shape and a face with a rectangular opening: **100.000% area, zero overlaps, zero gaps** on all eight bonds; rotations 0, 15, 30, 45, 60, 90, -37 and 180 all likewise. With a 10mm joint the covered fraction lands within 0.02 of the analytic tile-area / cell-area figure for every family.
- Not yet exercised inside SketchUp — Apply uses the already-proven generic polyline path, but the live round trip is unverified.

---
# Na Noble3d Modelling Tools
## Version 0.5.0 - 25-Aug-2026 - Trim to Face Edges (Overshoot and Cut Back)

### Update 01 - The Problem
- Every tiling pattern only ever placed units that fitted **wholly** inside the face, so anything meeting a hip, valley, verge or eaves left a ragged untiled band. On a hipped slate roof that band swallowed whole courses at the top of the hip and a wedge along each hip rake — the pattern visibly stopped short of the face perimeter.
- Slate and rosemary used an all-four-corners `face.classify_point` test on Apply and an all-four-corners point-in-polygon test in the preview; patio, brickwork and stonework used a centroid test plus `PolygonClip.na_clipPolyline`, which only gathered inside vertices and outer-ring crossings and could not produce a correctly ordered trimmed outline on a concave face.

### Update 02 - New Shared Clipper (JS + Ruby Mirror)
- New `01__SharedJs/Na__FacePattern__RectClip__.js` (`window.Na__FacePattern__RectClip`) and its Ruby mirror `...__FacePatternGenerator__RectClip__.rb` (`Na__FacePatternGenerator__RectClip`). Both must stay in step so the SVG preview and the applied SketchUp geometry agree.
- Sutherland-Hodgman clips the **face ring against the unit rectangle's four half-planes**, not the other way round. The clip window is the tile rectangle, which is always convex, so the subject ring may be concave — hips, valleys and dormer cheeks all clip correctly. Verified exact against hand-computed areas: a 300x200 tile straddling a 2:3 hip rake returns 23333.33mm² against an expected 23333.33mm², and every emitted vertex sits at distance 0.000mm from the face perimeter.
- Holes are subtracted with a convex half-plane decomposition (peel the outside slice off each hole edge in turn) whenever the hole footprint inside the unit is convex — window and door openings, the common case. A concave footprint falls back to dropping units centred in the opening, which is the pre-existing behaviour.
- `na_clipUnitRect` returns `{ polylines, full }`; `full` flags a unit that survived whole so it can stay a clean rectangle — and, in Ruby, stay a component instance rather than becoming loose edges.
- `na_clipSegment` clips a straight run to the face and returns the inside sub-segments, used for the rosemary base-thickness line on trimmed tiles.

### Update 03 - New Parameter: Trim to Face Edges
- New `trim_to_face` select on patio, brickwork, stonework, slate and rosemary — **default Yes**. Yes runs the pattern past the face perimeter and cuts it back to the face edges; No places only whole, untrimmed units (the old behaviour, kept because clean uncut modules are sometimes what you want).
- Shrub is deliberately excluded: it is a single organic outline rather than a tiling grid and keeps its own inside test.
- `AppCore__.js` normalises the value to a real boolean alongside `stagger` and carries `trim_to_face` into the slate and rosemary apply payloads. `DialogManager__.rb` inlines the new shared JS; `Loader__.rb` requires the Ruby clipper ahead of the builders.

### Update 04 - Generators Now Overshoot Before Trimming
- Slate and rosemary already ran the course grid one step past the bounding box, so only the fit test changed. Brickwork, stonework and patio previously laid out **inside** the bounding box, so a trim alone would have had nothing to cut: each now grows its layout box by one unit on every side (`na_expandBounds`, one spare module ring for patio) and drops the old `na_clipRectToBounds` pre-clip, which used to truncate units at the bounding box rather than at the real face edge.
- Stonework's uncoursed skyline packer had a fixed 6000-iteration safety valve that the enlarged layout box could exhaust, leaving the top of a large wall bare. The cap now scales with the layout area (`min(40000, max(6000, cells + 500))`).
- Status lines now count *units* rather than polylines (a trimmed unit can emit more than one piece) and say which mode produced them.
- Measured on a 15532 x 3411mm trapezoidal hip slope: slate 507 -> 586 units, 92.1% -> 100.0% coverage; patio 80.1% -> 96.5%; rosemary 97.6% -> 100.0%. Brick and stone land at 83% / 86% because their mortar joints are real gaps.

### Update 05 - Ruby Apply: Instances for Whole Units, Edges for Trimmed Ones
- `SlateBuilder__.rb` and `RosemaryBuilder__.rb` keep the fast path — a unit passing the `face.classify_point` corner test is still a component instance, so instance counts stay high on a large roof. Only units that fail the corner test go through the 2D clipper, and one that comes back `full` (a numerical edge case) is placed as an instance anyway.
- Genuinely trimmed units are drawn as closed loose edges in the same group, so Apply is still a single undo step. Rosemary additionally clips its base-thickness line to the face, since a trimmed tile has no component definition to carry it.
- `na_populate_face` now takes an options hash instead of nine positional arguments and returns `{ instances:, trimmed:, total: }`; the status message reports both counts.
- New `na_flag` helper reads boolean payload keys. `!!payload_hash.fetch('stagger', true)` was already unsafe for a JSON string `"false"` (truthy in Ruby); `na_flag` treats `false` and `"false"` alike, and both `stagger` and `trim_to_face` now use it.

### Update 06 - Closed Rings Now Render and Export Closed
- `SvgPreview__.js` drew every ring with `<polyline>`, which does not close the shape — each rectangle was missing its fourth side in the preview, and the face outline and hole overlays were missing their closing edge too. Rings of three or more points now use `<polygon>`; two-point runs (the rosemary base line) stay `<polyline>`.
- `DxfExport__.js` had the same gap: an *n*-point ring wrote only *n-1* LINE entities. It now appends the closing segment for rings of three or more points, skipping it when the first and last points already coincide. This mattered little for plain rectangles and matters a lot for trimmed offcuts, whose closing edge is the trim line itself.

### Known Limitation
- A concave hole footprint inside a single unit falls back to the centroid test rather than being carved out. Real openings are convex at tile scale, so this is a corner case; the fallback is no worse than the previous behaviour.

---
# Na Noble3d Modelling Tools
## Version 0.4.1 - 28-Jul-2026 - Rosemary Base Thickness Line + Side Gap Default 0

### Update 01 - Base Thickness Field (Visible Tile End)
- New `Base Thickness (mm)` field on the rosemary pattern (default 10, min 0, max 30): draws the visible tile end as a second horizontal line above the bottom edge of every course rectangle, matching how the tile thickness reads in elevation. Set 0 to disable; values >= the visible gauge are ignored rather than drawn above the course.
- `RosemaryRoofGenerator__.js` emits the base line per fully-inside tile (status message now counts tiles, not polylines); `RosemaryBuilder__.rb` draws the same line inside the component definition, whose name now carries the base value (`...__<width>x<gauge>b<base>`) so differing settings never reuse a stale definition. DXF export writes each base line as a single LINE entity.

### Update 02 - Side Gap Default 0
- Rosemary `Side Gap / Shunt (mm)` default changed from 1.5 to 0; the hint now reads "Set 1.5 for Rosemary 166.5mm linear cover (165 tile + 1.5 shunt)."

---
# Na Noble3d Modelling Tools
## Version 0.4.0 - 28-Jul-2026 - Face Canvas Rotation (Rotate 90° Toolbar Button)

### Update 01 - Rotate 90° Button in the Dialog Toolbar
- New `⟳ Rotate 90°` button (`naFacePat_btnRotateFace`) beside **Refresh Face** in `UiLayout__.html`, wired via `UiBridge__.js` to `AppCore.na_rotateFace90`. Each press rotates the face canvas 90° clockwise and regenerates the pattern to suit — for faces where the derived up-slope axis runs the wrong way for the coursing.
- `AppCore__.js` rotates the loaded face payload in place: outline and hole points map (x, y) → (y, −x), bounds are recomputed, and the payload basis follows as x′ = y, y′ = −x, so world positions are unchanged and the frame stays right-handed (no mirrored components). `rotationSteps` (0–3) tracks the cumulative state and resets to 0 whenever Ruby pushes a fresh face payload (Refresh Face / dialog open).
- Polyline patterns (patio, brickwork, stonework, shrub) need no Ruby changes: Apply round-trips the rotated basis through `GeometryBuilder`, so the applied linework matches the rotated preview.

### Update 02 - rotation_steps Plumbed into the Roof Builders
- Apply payload now carries `rotation_steps`. `SlateBuilder__.rb` and `RosemaryBuilder__.rb` — which rebuild their own basis from the live face rather than trusting the payload — apply the same clockwise rule N times via a new `na_rotate_basis_clockwise!` helper (x′ = y, y′ = −x per step), so slate and rosemary component courses land exactly where the rotated preview shows them.

---
# Na Noble3d Modelling Tools
## Version 0.3.0 - 28-Jul-2026 - Rosemary Plain Tile Roof Pattern

### Update 01 - New Pattern Type: Rosemary Tile Roof (British Plain Tiles)
- Added a sixth pattern type `rosemary` for British plain tile (Rosemary style) roofs, reusing the proven slate course-tiling maths: visible gauge = (tile length − headlap) / 2, half-bond stagger on alternate courses.
- New JS preview generator `02__PatternGenerators/Na__FacePattern__RosemaryRoofGenerator__.js` (`window.Na__FacePattern__RosemaryRoofGenerator`) with UK plain tile presets: 265x165 at 65mm headlap (100mm gauge, default), 75mm headlap (95mm gauge), 85mm headlap (90mm gauge), plus Custom.
- New Ruby builder `...__RosemaryBuilder__.rb` (`Na__FacePatternGenerator__RosemaryBuilder`) placing `Na__FacePattern__RosemaryTile__<width>x<gauge>` component instances in a `Na Face Pattern - Rosemary` group; regenerates from the live selection via `face.classify_point`, matching the SlateBuilder pattern.
- Default Side Gap / Shunt is 1.5mm so the horizontal module matches the Redland Rosemary 166.5mm linear cover (165mm tile + 1.5mm shunt); headlap hint cites the BS 5534 65mm minimum for double-lap plain tiling.

### Update 02 - Wiring
- `UiConfig__.js` — `rosemary` field descriptor block (preset select, tile length/width, headlap, side gap with 0.5mm step, stagger, lift).
- `AppCore__.js` — generator dispatch for `rosemary` and apply-payload block (`tile_length_mm` / `tile_width_mm` / `headlap_mm` / `side_gap_mm` / `stagger`).
- `DialogManager__.rb` — RosemaryRoofGenerator added to the inlined script list; `na_handle_apply_pattern` dispatches `rosemary` to the RosemaryBuilder.
- `Loader__.rb` — requires the RosemaryBuilder before DialogManager.
- `UiLayout__.html` hint and `UiCommandRegistry__.json` tooltip / tool-group description updated to mention rosemary tiles.

### Update 03 - Review Fixes: Live Preset Selects and Apply Safety Guards
- `01__SharedJs/Na__FacePattern__DynamicUI__.js` — select fields now support a generic `applies` map: choosing a preset writes its values into the linked number inputs, and manually editing a linked input flips the select back to `custom`. Previously preset selects were inert (number-field defaults always won), so the rosemary 75/85 headlap presets silently produced 65mm headlap output.
- `UiConfig__.js` — `applies` maps added to both the rosemary and slate preset selects, so all named presets in both roof patterns now drive their dimension fields.
- `RosemaryBuilder__.rb` / `SlateBuilder__.rb` — `na_read_options` clamps `side_gap_mm` to >= 0 and the entry points reject a non-positive tile/slate width, guaranteeing a positive x-step. A hand-typed negative side gap (below the field min, which HTML only enforces on the spinner) could previously drive the course loop into an infinite loop inside an open operation, hard-hanging SketchUp.

---
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
