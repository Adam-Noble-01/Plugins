# Na Noble3d Modelling Tools - Development Log
# =============================================================================

## Version History

## Na Noble3d Modelling Tools | Version 0.5.0 - 16-Jun-2026 - Face Pattern Generator (Geometry Tools)

### Update 01 - Face Pattern Generator Feature Module
- Added a new Geometry Tools feature module that reads one selected SketchUp face, projects it to local 2D millimetre coordinates, previews a chosen architectural surface pattern inside an HtmlDialog SVG viewport, then applies the generated linework back onto the face in a grouped undo-safe operation.
- Five pattern types in one unified dialog: Patio, Brickwork, Stonework, Shrub, and Slate Roof. All use direct SVG polyline rendering with no external library dependency (MakerJS removed).
- New module folder `10__PluginModules/20__SourceCode__FacePatternGenerator`:
  - `Na__Noble3dModellingTools__FacePatternGenerator__Loader__.rb`
  - `Na__Noble3dModellingTools__FacePatternGenerator__Run__.rb`
  - `Na__Noble3dModellingTools__FacePatternGenerator__FaceData__.rb`
  - `Na__Noble3dModellingTools__FacePatternGenerator__DialogManager__.rb`
  - `Na__Noble3dModellingTools__FacePatternGenerator__GeometryBuilder__.rb`
  - `Na__Noble3dModellingTools__FacePatternGenerator__SlateBuilder__.rb`
  - `Na__Noble3dModellingTools__FacePatternGenerator__UiLayout__.html`
  - `Na__Noble3dModellingTools__FacePatternGenerator__Styles__.css`
  - `Na__Noble3dModellingTools__FacePatternGenerator__UiBridge__.js`
  - `Na__Noble3dModellingTools__FacePatternGenerator__UiConfig__.js`
  - `Na__Noble3dModellingTools__FacePatternGenerator__SvgPreview__.js`
  - `Na__Noble3dModellingTools__FacePatternGenerator__AppCore__.js`
  - `01__SharedJs/Na__FacePattern__DynamicUI__.js`
  - `01__SharedJs/Na__FacePattern__Viewport__.js`
  - `01__SharedJs/Na__FacePattern__Noise__.js`
  - `01__SharedJs/Na__FacePattern__RectGeometry__.js`
  - `01__SharedJs/Na__FacePattern__PolygonClip__.js`
  - `01__SharedJs/Na__FacePattern__DxfExport__.js`
  - `02__PatternGenerators/Na__FacePattern__PatioGenerator__.js`
  - `02__PatternGenerators/Na__FacePattern__BrickworkGenerator__.js`
  - `02__PatternGenerators/Na__FacePattern__StoneworkGenerator__.js`
  - `02__PatternGenerators/Na__FacePattern__ShrubGenerator__.js`
  - `02__PatternGenerators/Na__FacePattern__SlateRoofGenerator__.js`
- Sub-devlog: `10__PluginModules/20__SourceCode__FacePatternGenerator/Na__Noble3dModellingTools__FacePatternGenerator__DEVLOG__.md`

### Update 02 - Single-Face Selection and Local 2D Projection (Ruby)
- `FaceData__.rb` enforces a strict single-face constraint (`selection.grep(Sketchup::Face)`, validates exactly one valid face). Opens a messagebox if 0 or more than 1 faces are selected — multi-face selection deferred to a future version.
- Builds an orthonormal local basis per face: slope-first strategy for pitched surfaces (up-slope → Y axis → cross-product X axis), longest-outer-edge fallback for near-horizontal faces. Normal is always flipped to the visible/positive-Z side.
- Projects the outer loop and all inner loops (holes) from world `Geom::Point3d` inches into local `[x_mm, y_mm]` float pairs using `vector.dot(axis) / 1.mm`.
- Serialises `{ outer, holes, bounds, basis }` to JSON and pushes to the dialog via `execute_script` using the standard PNG-to-Linework handshake: JS fires `na_dialog_ready`, Ruby pushes `Na__FacePattern__SetFaceData(payload)`.
- A **Refresh Face** button lets the user re-pick from SketchUp without closing the dialog.

### Update 03 - Unified HtmlDialog SVG Preview (No External Library)
- Dialog follows the PNG To Linework shell: inline `{{STYLESHEET_CONTENT}}` + `{{SCRIPTS_CONTENT}}` substitution via `DialogManager__.rb`. No CDN; all scripts are local files bundled at open time.
- `SvgPreview__.js` renders a two-layer SVG: a dashed grey boundary polyline for the face outline/holes, and solid dark lines for pattern geometry. Y-axis is negated from model Y-up to SVG Y-down during point formatting.
- `Viewport__.js` provides cursor-anchored wheel zoom and drag-pan on the SVG viewBox state, matching the PngToLinework SvgPreview pattern.
- Pattern type dropdown drives `AppCore__.js → UiConfig__.js` to rebuild the dynamic control panel via `DynamicUI__.js` (per-field `<input type="number">` and `<select>` elements), then immediately regenerates the preview.
- Live preview regenerates on every control change without a Ruby round-trip; `Apply to Face` serialises the current polylines and face basis, then sends to Ruby via `sketchup.na_apply_pattern`.

### Update 04 - Shared JS Infrastructure Modules
- `Na__FacePattern__Noise__.js` — Mulberry32 seeded random + bilinear 2D value noise + 3-octave FBM. Consolidates the identical noise functions that were duplicated across the Brickwork and Stonework prototype HTML files.
- `Na__FacePattern__RectGeometry__.js` — `na_makeRectPolyline(x,y,w,h)` (closed `[x,y]` array), `na_clipRectToBounds(...)` (axis-aligned clip returning null on empty result). Replaces the 4-`M.paths.Line` rectangle pattern from the prototypes.
- `Na__FacePattern__PolygonClip__.js` — point-in-polygon ray-cast (`na_pointInFace`), segment-against-ring intersection, polyline clip (`na_clipPolyline`), and centroid-inside-face keeper (`na_keepWhenCentroidInside`). Enables accurate face-polygon clipping without a geometry library.
- `Na__FacePattern__DxfExport__.js` — writes minimal DXF LINE entities to a `Blob` and triggers a filename download. Does not depend on MakerJS.
- `Na__FacePattern__DynamicUI__.js` — JSON-config-driven control panel builder (`na_mount`, `na_setFields`, `na_getValues`). Select and number fields. Fires `onChange` on every input/change event.

### Update 05 - Pattern Generators (JS)
- All generators share the same call signature `na_generate({ faceData, params })` → `{ polylines, status }`.
- Each generates raw rectangles or point arrays over the face bounding box, then clips to the face polygon via `PolygonClip` before returning.
- **Patio** — grid-based greedy tile packer with six weighted tile types (module units 1×1 to 3×2). Centroid-inside-face filter discards tiles outside the boundary.
- **Brickwork** — Stretcher / Flemish / English bond courses generated from face bounds height; Imperial (215×65mm) and Metric (230×76mm) unit systems. Artistic render mode uses FBM noise density masking to scatter missing bricks.
- **Stonework** — Coursed (random-height rows) and Uncoursed/Snecked (skyline packer) stone placement. Three size presets. Tumbled-corner radius and edge roughness parameters (numeric only in preview; Ruby builder handles 3D geometry).
- **Shrub** — Single closed silhouette (Round/Wild/Topiary ellipse base shape) scaled to a user-defined width/height, centred within the face. An interior-point sampler finds a usable centroid for non-rectangular faces (e.g. L-shapes) before attempting up to 5 scaled-down fits.
- **Slate Roof** — Course-array tiling (visible gauge = `(slate_length − headlap) / 2`), half-bond stagger option, six UK presets matching the original Ruby slate script. Preview uses all-corners-inside check; Apply delegates to `SlateBuilder__.rb` for component-instance creation, reusing the battle-tested face-clip logic from the prototype.
- Smoke-tested in Node against rectangular (3000×2000mm) and L-shaped (3000×2000mm notched) faces: all five generators return non-empty polyline arrays.

### Update 06 - SketchUp Apply Pipeline (Ruby)
- `GeometryBuilder__.rb` — receives `{ polylines, basis, lift_mm, close_paths, group_name }` JSON from the dialog. Transforms each local `[x_mm, y_mm]` point to world space via `origin.offset(x_axis, x_mm.mm).offset(y_axis, y_mm.mm).offset(z_axis, lift_mm.mm)`. Builds edges with `entities.add_line` inside a named group wrapped in a single `start_operation`/`commit_operation`. Aborts cleanly if no edges are produced.
- `SlateBuilder__.rb` — receives slate parameters, re-reads the single currently selected face, and runs the same face-basis + populate-with-instances logic as the original `Na__SlateRoofPatternGenerator__V2.rb`. Uses `add_instance` with a cached component definition per unique `width × visible_gauge` combination. All instances placed on one undo step.
- `DialogManager__.rb` routes `na_apply_pattern` callback: `pattern_type == 'slate'` dispatches to `SlateBuilder`, all others to `GeometryBuilder`. Status result is pushed back to the dialog status bar via `Na__FacePattern__SetStatus`.

### Update 07 - Registry, Router, and Loader Wiring
- Registered command, button (Geometry Tools > Surface Pattern Tools, tool_group_order 55), and hotkey binding in the JSON-driven UI registry:
  - `face_pattern_generator` / `Face Pattern Generator`
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Wired handler and module load paths through:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`

### Update 08 - MakerJS Dependency Removed
- Initial implementation attempted to vendor a MakerJS browser-compat shim, but path resolution of the relative `../../01__ExternalDependencies__VersionLocked/…` path failed in the SketchUp Ruby `File.join` / `__dir__` context.
- MakerJS was not actually used: all generators produce raw `[x,y]` polyline arrays that render directly as SVG `<polyline>` elements. The shim and its folder were deleted.
- `DialogManager__.rb` now loads only the local shared JS modules and pattern generators — no external libraries required.

### Validation Checklist
- [x] JSON registry parses; JS files pass `node --check`; IDE lints clean.
- [x] Generator smoke tests pass on rectangular and L-shaped faces for all five pattern types.
- [x] No MakerJS references remain in the Face Pattern Generator module.
- [ ] In-SketchUp: button appears under `Geometry Tools > Surface Pattern Tools`.
- [ ] In-SketchUp: selecting one face and clicking the button opens the dialog with face dimensions shown in the toolbar and the face boundary drawn in the SVG viewport.
- [ ] In-SketchUp: switching pattern type rebuilds controls and live-previews the new pattern.
- [ ] In-SketchUp: `Apply to Face` creates a named group of edges on the face plane; single undo reverts it.
- [ ] In-SketchUp: `Refresh Face` re-reads the current selection without closing the dialog.
- [ ] In-SketchUp: `Download DXF` saves the current polylines as a `.dxf` file.
- [ ] In-SketchUp: `Slate Roof` apply creates component instances with the correct visible gauge, not edge polylines.
- [ ] In-SketchUp: selecting 0 faces or 2+ faces shows a messagebox and does not open the dialog.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.9 - 12-Jun-2026 - PNG To Linework (Import Tools)

### Update 01 - PNG To Linework Feature Module
- Added a new Import Tools feature module that traces transparent-background PNG linework drawings (trees, plants, people, organic shapes) into SketchUp segmented edge components via an interactive HtmlDialog with a live SVG preview. Pipeline: PNG -> SVG preview -> SketchUp model.
- New module folder `10__PluginModules/19__SourceCode__PngToLinework`:
  - `Na__Noble3dModellingTools__PngToLinework__Loader__.rb`
  - `Na__Noble3dModellingTools__PngToLinework__Run__.rb`
  - `Na__Noble3dModellingTools__PngToLinework__DialogManager__.rb`
  - `Na__Noble3dModellingTools__PngToLinework__GeometryBuilder__.rb`
  - `Na__Noble3dModellingTools__PngToLinework__PlacementTool__.rb`
  - `Na__Noble3dModellingTools__PngToLinework__UiLayout__.html`
  - `Na__Noble3dModellingTools__PngToLinework__Styles__.css`
  - `Na__Noble3dModellingTools__PngToLinework__TraceEngine__.js`
  - `Na__Noble3dModellingTools__PngToLinework__SvgPreview__.js`
  - `Na__Noble3dModellingTools__PngToLinework__UiBridge__.js`

### Update 02 - PNG Selection and Alpha-Channel Validation (Ruby)
- `Run__.rb` opens the OS file picker (`UI.openpanel`, PNG filter, last-directory persistence via `Sketchup.read_default`/`write_default`), then validates BEFORE any processing:
  - PNG signature + IHDR header parse (width/height/colour type read directly from the byte stream).
  - Proper alpha-channel check: colour type 4 (grey+alpha) or 6 (RGBA), or a `tRNS` chunk for palette/grey/RGB images. Files without alpha are rejected with an explanatory message box.
  - 25MB file-size guard against oversized base64 data-URI pushes.
- SketchUp Ruby has no PNG decoder, so the raster work runs in the dialog's Chromium canvas: Ruby base64-encodes the file bytes and pushes a `data:image/png;base64,...` URI to JS (data URIs avoid canvas tainting so `getImageData` always works). A second full alpha-variation check runs in JS on the decoded pixels - a fully opaque PNG is rejected even if its header claims alpha.

### Update 03 - Raster-To-Vector Trace Engine (JavaScript)
- `TraceEngine__.js` pipeline, all in millimetres with model Y-up:
  1. Decode to canvas `ImageData`, downscaling to max 2048px dimension (UI-lockup guard).
  2. Binarise on a user alpha threshold (default 128).
  3. Trace mode (dropdown):
     - **Centerline** (default) - Zhang-Suen thinning to a 1px skeleton, then junction/endpoint-aware path walking (union of node-to-node walks + pure-cycle recovery). One edge run per drawn pen line.
     - **Outline** - marching-squares contour extraction with endpoint-hash segment chaining into closed loops. Best for filled silhouettes.
  4. Scale px -> mm from the user's typed real-world image width (e.g. 12000 for a 12m tree row); mm/px and derived output size shown live for tangible scale.
  5. Ramer-Douglas-Peucker simplification + minimum-segment spacing filter (default 5mm) - the primary edge-count control.
  6. Detail Cull - drops whole paths shorter than a total mm length (thins dense foliage confetti; 0 = off).
  7. Centre all polylines on their bounding-box centre (component origin = drawing centre).
  8. FINAL vertex merge (weld) pass - see Update 07.
- Edge-count crash guards: Create button disabled above 50,000 edges (mirrored as a hard limit in the Ruby GeometryBuilder), amber warning above 20,000.

### Update 04 - Live SVG Preview Dialog
- `SvgPreview__.js` reuses the Element Assembly Studio viewBox-state viewport pattern as a standalone copy (no cross-plugin dependency): cursor-anchored wheel zoom, drag pan with 5px click threshold, Reset View fit with 10% padding and wrapper-aspect correction.
- Polylines render as `<polyline>` strings with `vector-effect="non-scaling-stroke"`; SVG Y is negated from model Y-up at render time. Optional source-image underlay (`<image>` at 0.22 opacity, positioned in the same centred mm frame) for trace verification, plus an origin marker.
- Control rows (slider + number-input pairs, `naPngTrace__*` class prefix, light `--na-*` Vale palette) re-trace on a 150ms debounce so scrubbing stays fast and forgiving. Live stats: paths / vertices / edges / scale / output size.

### Update 05 - Geometry Build and Crosshair Placement (Ruby)
- `GeometryBuilder__.rb` converts mm polylines to inch `Geom::Point3d`s on the chosen plane - Vertical X-Z (elevations: trees, people) or Ground X-Y (plans) - and builds a `ComponentDefinition` of plain segmented edges via `entities.add_edges` (no curves), named `Na__PngLinework__<file>__<HHMMSS>`.
- Creation happens inside an OPEN `start_operation`; the placement tool commits on click so create-and-place is ONE undo step, and ESC aborts the operation erasing the component cleanly.
- `PlacementTool__.rb` follows the Insert Primitives placement pattern: `Sketchup::InputPoint` pick, 5mm grid snap (mm-converted rounding), six-arm blue crosshair drawn in `draw`, live instance repositioning via `move!` (records no undo steps), selection + tool pop on click.

### Update 06 - Registry, Router, and Loader Wiring
- Registered command, button, and hotkey binding in the JSON-driven UI registry under a new `Import Tools > Raster Tracing` group (tool_group_order 20, after Vector Import):
  - `png_to_linework` / `PNG To Linework`
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Wired handler and module load paths through:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`
- Fixed a capitalized-method dispatch NameError on first in-SketchUp run (`uninitialized constant ...PickAndValidatePng`): bare capitalized identifiers parse as constants in Ruby, so the same-module call in `Run__.rb` now uses an explicit `self.` receiver (same fix class as v0.2.0 Update 04).

### Update 07 - Final Vertex Merge (Weld) Pass for Junction Tessellation
- Skeleton junctions in centerline mode leave small diamond/box tessellation clusters (visible when zoomed into trunk/branch intersections). Added a vertex weld as the FINAL pipeline step - after tracing, simplification, detail cull, and centring - so it cannot interfere with any earlier step.
- `na_mergeVertices` in `TraceEngine__.js`: union-find clustering over a spatial hash grid (O(n), path-halving), every vertex snapped to its cluster centroid, zero-length segments and fully collapsed polylines dropped. Welding is transitive (chained clusters), which is exactly what collapses junction tessellation chains into single clean nodes.
- New `Vertex Merge Distance (mm)` control (slider 0-100, default 0 = off) in the Linework Complexity group, wired through `UiBridge__.js` (`vertexMergeMm` trace option).
- Browser-harness verification with `PineTrees__BackroundRemvoed__.png` (2172x724 RGBA) at 12000mm / 5mm min segment: weld off = 24,184 edges; weld 8mm = 4,992 edges with tree structure intact and junction diamonds collapsed; weld 20mm = 1,068 edges (aggressive canopy collapse - user-controlled trade-off).

### Update 08 - Aspect-Locked Width / Height Inputs (12m Default Height)
- Added an `Image Height (mm)` input beside `Image Width (mm)` in the Real World Scale group; the pair is aspect-locked to the loaded image's pixel aspect, so editing either dimension updates the other in unison (`na_syncAspectLockedPair` in `UiBridge__.js`, aspect captured from the PNG IHDR pixel dimensions on image load).
- On image load the height now defaults to 12,000mm (12m) and the width is derived from the image aspect (e.g. the 2172x724 pine-tree row loads as 36,000 x 12,000mm).
- The trace engine continues to consume `realWidthMm` only; height is always the derived counterpart, so no pipeline behaviour changed.
- Browser-harness verified: load defaults 36000/12000; width edit 12000 -> height 4000; height edit 6000 -> width 18000; output-size stat tracks.

### Validation Checklist
- [x] JSON registry parses; JS files pass `node --check`; IDE lints clean (Ruby syntax check skipped - `ruby` not on PATH; logic reviewed manually).
- [x] Browser harness (exact DialogManager template substitution + real PNG payload): alpha check passes for RGBA, fully-opaque rejection path works, centerline and outline modes both trace the three pine trees correctly.
- [x] Controls re-trace live on a 150ms debounce; stats and edge-count guards update; Create disabled above 50,000 edges.
- [x] Wheel zoom / drag pan / Reset View verified; Create payload (plane, fileName, centred mm polylines) verified via mocked `sketchup` bridge.
- [x] Vertex merge verified as final pass: junction tessellation collapses, earlier pipeline steps unaffected at 0mm.
- [ ] In-SketchUp: button under `Import Tools > Raster Tracing` opens picker -> dialog -> Create & Place places with crosshair + 5mm snap; ESC cancels and erases; single undo reverts a placement.
- [ ] In-SketchUp: non-alpha PNG is rejected with the explanatory message box before the dialog opens.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.8 - 09-Jun-2026 - Multiple Offset Tool Edge Stickiness Fix

### Update 01 - Offset Edges Now Properly Integrate With Coplanar Faces
- Fixed a geometry stickiness bug in `commit_offset` where the committed offset loop had no face-topology connection to the outer face it sat on. Edges appeared in the correct position but SketchUp never registered them as part of the face, so the parent face was never split and no inner face was created — the same symptom as the native SketchUp `Entities#add_edges` documented limitation ("if the points form a closed loop, the first and last vertex will not merge").
- Root cause: `Entities#add_edges` intentionally creates free-floating edges with no face integration. It does not merge the first/last vertex into a closed ring, and it does not create faces from closed loops. Both `Edge#find_faces` and `Entities#intersect_with` were investigated as fix candidates but are inapplicable here (`find_faces` requires a closed topological ring at the vertex level; `intersect_with` finds intersections between crossing faces, not a polygon sitting inside another face).
- Fix: Replaced `add_edges` with `Entities#add_face(world_points)` — the officially supported SketchUp API method for creating geometry that integrates with existing coplanar topology. `add_face` creates the inner face directly (returned as the result), registers all new edges with the surrounding outer face, and causes SketchUp to punch a proper inner-loop hole in it. This is the same stickiness behaviour produced by the native Offset tool.
- Added a `face.reverse!` guard after `add_face` to realign the face normal to match the outer face direction, preventing inverted front/back on the committed offset face.
- Removed the now-redundant `na_find_inner_face` helper method (previously used to search for an inner face that `add_edges` might create; `add_face` returns the inner face directly).
- File edited: `10__PluginModules/18__SourceCode__MultipleOffsetTool/Na__Noble3dModellingTools__MultipleOffsetTool__Tool__.rb`
- Constants index updated: `na_find_inner_face` removed from `tool_class > core` method index in `Na__Noble3dModellingTools__MultipleOffsetTool__Constants__.rb`.

### Validation Checklist
- [ ] Committing an offset on a flat face produces a border-frame face and a fully filled inner face (no floating/unattached edges).
- [ ] The inner face normal matches the outer face normal (same front/back facing).
- [ ] The surrounding outer face is correctly split into a frame with an inner-loop hole.
- [ ] Offset works at model root and inside an open group/component.
- [ ] Single undo reverts the committed offset cleanly.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.7 - 07-Jun-2026 - Entity Tree Reporter V3 (Folding, Type & Solid Badges)

### Update 01 - Identical Instance Folding (Feature 1)
- Any group of 4 or more sibling container entities that share the same `ComponentDefinition` GUID is now collapsed into a single **Grouped Identical Instances** fold node in the tree, preventing the UI from becoming un-navigatable when a component with thousands of instances (e.g. a leaf) is present.
- The fold node records `instance_count`, `definition_name`, `entity_type_label`, and `is_solid` so all context is visible without expanding.
- All individual child entity nodes are pre-built at report-time and embedded inside the fold node's `children` array — expansion is handled entirely by the browser's native `<details>/<summary>` mechanism with no additional Ruby round-trip.
- Threshold constant `NA_GROUPING_THRESHOLD = 4` added to `TreeData__.rb`; groups of 1–3 identical definitions continue to render as individual cards.
- New Ruby helpers: `na_grouped_container_children` (groups by definition key, dispatches to fold or individual path), `na_grouped_instances_node` (builds the wrapper node hash).
- Both `na_entity_node` (for recursive child containers) and `na_sibling_context_node` now route through `na_grouped_container_children`.

### Update 02 - Group / Component Type Badge (Feature 2)
- Every container entity node now carries an `entity_type_label` field (`'Group'` or `'Component'`) sourced from `EntityText__.rb` via the new `Na__SelectedHierarchyTagReporter__EntityText__EntityTypeLabel` helper.
- The UI renders this as a coloured badge: green for Group, indigo for Component.
- The Markdown clipboard export and Ruby Console report also include the type label.

### Update 03 - Solid / Non-Solid Badge (Feature 3)
- Every container entity node now carries an `is_solid` boolean (or `nil` if indeterminate) sourced from `entity.definition.manifold?` via the new `Na__SelectedHierarchyTagReporter__EntityText__IsSolid` helper.
- Uses the non-deprecated `Sketchup::ComponentDefinition#manifold?` API; the deprecated `Group#manifold?` and `ComponentInstance#manifold?` are intentionally avoided.
- The UI renders this as a coloured badge: green "Solid" or amber "Non-Solid". No badge is shown when the result is `nil` (non-container entities).
- Solid/Non-Solid state is also shown on grouped-instances fold nodes (derived from the first instance's definition).

### Update 04 - CSS Badge Variants And Grouped Instances Styles
- New badge modifiers in `Styles__.css`: `--group` (green), `--component` (indigo), `--solid` (teal-green), `--non-solid` (amber), `--grouped` (purple) for the instance-count badge.
- New `<details>` layout classes: `.naEntityTree__GroupedInstances` (left border purple, shadow), `.naEntityTree__GroupedSummary` (hover highlight, hidden default marker), `.naEntityTree__Children--grouped` (tinted background for expanded content).

### Validation Checklist
- [ ] A component with 4+ instances of the same definition renders as a single collapsed fold card showing count, type, and solid state.
- [ ] Expanding the fold card reveals all individual instance cards.
- [ ] Components of 1–3 identical instances still render as individual cards (no fold).
- [ ] Every Group card shows a green "Group" badge.
- [ ] Every Component Instance card shows an indigo "Component" badge.
- [ ] A closed watertight geometry container shows a green "Solid" badge.
- [ ] A non-manifold or nested-content container shows an amber "Non-Solid" badge.
- [ ] Console report and Markdown clipboard copy both include type and solid info.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.6 - 05-Jun-2026 - Cross-Tab Search Feature (UI)

### Update 01 - Persistent Search Bar
- Added a full-width search input row (`naNoble3d__SearchBar`) rendered directly in `Na__Noble3dModellingTools__UiLayout__.html`, positioned between the tab navigation and the main content area so it is always visible regardless of the active tab.
- Input is `type="search"` (browser-native clear button included), wired via an `input` event listener added in `DOMContentLoaded` in `Na__Noble3dModellingTools__UiBridge__.js`.

### Update 02 - Dedicated Search Results Tab Panel
- `na_build_tab_content_html` in `Na__Noble3dModellingTools__CoreAppLogic__DialogManager__.rb` now prepends a static `<section id="tab-search">` panel before all regular tab panels. The panel contains `#naNoble3dSearchResults` (`naNoble3d__SearchResultsGrid`), which starts empty and is populated entirely at runtime by JavaScript.
- A **Search** tab button (`naNoble3d__TabButton--search`) is appended last in `na_build_tab_buttons_html`, wired to `Na__Noble3d__ShowSearchTab(this)` which switches to the search panel and focuses the input in a single call.

### Update 03 - Real-Time Client-Side Filtering (`Na__Noble3d__SearchTools`)
- All tool cards are server-rendered into the DOM at dialog open (hidden per-tab via CSS). Search works entirely client-side with no Ruby round-trip.
- `Na__Noble3d__SearchTools(query)` in `UiBridge__.js` iterates every `.naNoble3d__ToolCard` element across all non-search panels, lowercases and matches the query against `.naNoble3d__ToolTitle` and `.naNoble3d__ToolDescription` text content, clones each hit via `cloneNode(true)` (preserving the original `onclick` handler), appends a `naNoble3d__SearchResultTab` badge span (reads `data-tab-name`), and renders results into `#naNoble3dSearchResults`. A "No tools found" empty state is shown when no matches exist.
- `na_build_button_cards_html` in `DialogManager__.rb` now adds `data-tab-name="..."` to every rendered card button so the cloned result cards always carry their source tab name.

### Update 04 - Tab State Tracking And Restore
- `naSearchState { lastTabId, lastTabButton }` in `UiBridge__.js` tracks the last active non-search tab.
- `Na__Noble3d__ShowTab` extended: on switching to any non-search tab it records that tab to `naSearchState` and programmatically clears the search input (programmatic `.value = ''` does not fire the `input` event, preventing re-entrancy).
- Clearing the search input (empty query) calls `na__Noble3d__RestorePreviousTab`, which re-activates the last recorded tab. Clicking any regular tab button while search is active clears the input and restores that tab.

### Update 05 - Search UI Styles
- New CSS regions added to `Na__Noble3dModellingTools__Styles__.css`:
  - `naNoble3d__SearchBar` — full-width row, same background and border-bottom as the tab bar.
  - `naNoble3d__SearchInput` — inherits font, accent border + subtle focus ring on focus, muted placeholder text.
  - `naNoble3d__TabButton--search` — dashed accent border, right-aligned via `margin-left: auto`; solid accent fill when active.
  - `naNoble3d__SearchResultsGrid` — same `auto-fit minmax(220px,1fr)` grid as `naNoble3d__ToolGrid`.
  - `naNoble3d__SearchResultTab` — small uppercase accent-coloured badge at the bottom of each result card showing the source tab name.

### Validation Checklist
- [ ] Search bar appears between the tab row and content on every tab; **Search** button is last in the tab bar.
- [ ] Typing a partial name (e.g. "offset") immediately switches to the Search Results tab and shows all matching cards from every tab, each with a source-tab badge.
- [ ] Matching is case-insensitive and searches both title and description text.
- [ ] Clicking a result card executes its command identically to clicking the card on its original tab.
- [ ] Clearing the search input (backspace or the native ✕ button) restores the previously active tab.
- [ ] Clicking any regular tab while search is active clears the search input and switches to that tab.
- [ ] Clicking the Search tab button focuses the search input.
- [ ] No tools found state shows the "No tools found for …" message instead of an empty grid.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.5 - 05-Jun-2026 - Multiple Offset Tool (Geometry Tools)

### Update 01 - Multiple Offset Tool Feature Module
- Added an interactive tool that offsets the outer perimeter of many selected faces at once, each computed in its OWN plane, so non-coplanar selections (e.g. the five faces of a bay window) all inset/expand correctly in a single gesture. SketchUp's native Offset is limited to one face/loop at a time.
- New module folder `10__PluginModules/18__SourceCode__MultipleOffsetTool` (mirrors the OrthoMirrorTool interactive-tool pattern: Constants -> Helpers -> Tool -> Run):
  - `Na__Noble3dModellingTools__MultipleOffsetTool__Loader__.rb`
  - `Na__Noble3dModellingTools__MultipleOffsetTool__Constants__.rb`
  - `Na__Noble3dModellingTools__MultipleOffsetTool__Helpers__.rb`
  - `Na__Noble3dModellingTools__MultipleOffsetTool__Tool__.rb`
  - `Na__Noble3dModellingTools__MultipleOffsetTool__Run__.rb`

### Update 02 - Per-Face Offset Geometry (Helpers)
- Each face gets a local 2D frame derived from its own loop points via a Newell-method normal (`na_build_face_plane_frame`, `na_newell_normal`, `na_first_edge_direction`) rather than a transformed `face.normal`, then offset in that plane.
- Signed perpendicular miter offset (`na_inward_offset_polygon`): positive distance insets inward, negative expands outward; sign is winding-aware via shoelace area (`na_signed_area_2d`).
- Validity guard (`na_offset_polygon_valid?` + `na_point_in_polygon_2d?`): inward results must shrink and stay inside the source; outward must grow. This rejects the "exploded miter" loops that previously shot off to huge sizes.
- Per-face inscribed radius bounds the shared distance (`recompute_max_offset` + `clamp_distance`) so a single value can never blow up the smallest face.

### Update 03 - Coordinate-Space and Units Correctness
- Geometry is read and built in WORLD space: while a group/component is open for editing SketchUp already reports `vertex.position` in world coordinates, so the tool reads vertices directly and adds the loop with `entities.add_edges` in world space (no double `edit_transform`). This fixed the giant/displaced preview seen when working inside groups.
- Internal maths stays in inches (SketchUp's internal unit); user text is parsed via `String#to_l` (honours model units/locale); the stored last-used distance is persisted as a raw inch value and read back with `Float#to_l` to avoid unit-format ambiguity (`...__Run__` `Na__MultipleOffsetTool__StoredDistance` / `__StoreDistance`).

### Update 04 - Fluid Preview / Commit Interaction (Fredo-style)
- Reworked to a preview-then-commit model after researching the SketchUp 2026 VCB regression (API issue #1076 / focus loss): committing inside `onUserText` breaks the next Enter. The tool now NEVER commits on the preview path.
  - Mouse drives a live orange preview (cursor inside a face = inward, outside the perimeter = outward) via `view.pickray` + `Geom.intersect_line_plane`.
  - Typing a value locks the preview to that exact size and overrides the mouse (`@typed`); re-typing freely just updates the preview. A genuine mouse move (beyond `MOUSE_MOVE_TOLERANCE_PX`) releases the lock; stray sub-pixel events are ignored.
  - Commit happens on a left-click OR a double-Enter within `DOUBLE_ENTER_SECONDS` (handled in both `onUserText` and `onReturn`). After commit the tool re-arms on the new inner faces for the next offset; Esc finishes.
- `rearm_vcb_and_focus` re-asserts the VCB label/value and calls `Sketchup.focus` (guarded, deferred via `UI.start_timer`) on activate and after each commit, so typed values register without first clicking the viewport.

### Update 05 - Registry, Router, and Loader Wiring
- Registered command, button, and hotkey binding in the JSON-driven UI registry under a new `Geometry Tools > Offset Tools` group (tool_group_order 35, between Lattice Generation and Edge Cleanup):
  - `multiple_offset_tool` / `Multiple Offset Tool`
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Wired handler and module load paths through:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`
- Shortened the button description to match the concise style of the other tool cards.

### Validation Checklist
- [ ] `Multiple Offset Tool` appears under `Geometry Tools > Offset Tools`; menu item and hotkey binding register.
- [ ] Selecting the five non-coplanar bay-window faces shows a synchronised orange inset preview on all of them; cursor inside insets inward, outside the perimeter expands outward.
- [ ] Typing a value (e.g. 25, then 50, then -15) updates the preview each time and overrides the mouse; a genuine mouse move resumes cursor control.
- [ ] Left-click applies; double-Enter (two Enters within ~1s) applies; each face becomes a border frame + inner face; inner faces are re-selected; single undo reverts a commit.
- [ ] Works at model root and inside an open group/component without displaced/oversized geometry.
- [ ] IDE diagnostics report no linter errors for the module; JSON registry parses.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.4 - 03-Jun-2026 - Flatten 3D To 2D Refinements (Visibility + Entity Utils)

### Update 01 - Camera-Visible Hidden-Line Removal (Flatten 3D To Group)
- `Flatten 3D To Group` now omits edges that are not visible to the camera, so back and occluded linework is no longer projected into the flattened group.
- Added module `Na__Noble3dModellingTools__Flatten3dTo2d__VisibilityFilter__.rb`:
  - A point is visible when a ray cast from just in front of it toward the camera hits no face (`model.raytest`, wysiwyg = respect shown geometry).
  - Each edge is sampled along its length; consecutive visible samples are merged into single sub-segments, giving clean cuts at occlusion boundaries. Per-edge sample count is adaptive (capped) and edge soft/smooth/hidden flags are carried onto every emitted sub-segment.
- `Flatten 3D To Silhouette` is unchanged: its outline is the union of all projected face areas, which is independent of inter-surface occlusion.

### Update 02 - World-Space Projection Pipeline
- Refactored the projection pipeline to work in world space (so `model.raytest` and the camera direction align), converting finished points back into the active edit context via `model.edit_transform.inverse` only at creation time. At the top level this is a no-op.
- `GeometryCollector` now accepts a `base_transform` (passed `model.edit_transform`) so collected coordinates are world-space; builders take an `edit_inverse` and map each projected point to the active context before adding.

### Update 03 - Moved to Entity Utils
- Relocated the `Group / Component to 2D` tool group from `Geometry Tools` to `Entity Utils` (tool_group_order 30, after Component Containers and Hierarchy Reporting):
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`

### Validation Checklist
- [ ] Both Flatten buttons now appear under `Entity Utils > Group / Component to 2D`.
- [ ] In a head-on Parallel Projection view, `Flatten 3D To Group` shows only the front/visible linework; back and occluded edges are gone.
- [ ] Partially occluded edges are cut at the occlusion boundary rather than dropped or kept whole.
- [ ] `Flatten 3D To Silhouette` still produces the union outline with interior holes; originals untouched; single undo reverts either tool.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.3 - 03-Jun-2026 - Flatten 3D To 2D (Geometry Tools)

### Update 01 - Flatten 3D To 2D Feature Module
- Added a new geometry feature module that projects the selected groups/components onto a camera-facing plane while the view is in Parallel Projection, producing a single new flat 2D group. The original 3D geometry is never modified.
- Two public entrypoints / tools:
  - `Flatten 3D To Group` - all linework projected and rebuilt as a 2D group (soft/smooth/hidden edge flags preserved; auto-created faces stripped).
  - `Flatten 3D To Silhouette` - outer face loops projected and merged, interior edges removed, fill stripped, leaving the union outline with interior holes preserved (true stencil). Good for outlines and stencils.
- New module folder `10__PluginModules/15__SourceCode__Flatten3dTo2d`:
  - `Na__Noble3dModellingTools__Flatten3dTo2d__Loader__.rb`
  - `Na__Noble3dModellingTools__Flatten3dTo2d__ViewProjection__.rb`
  - `Na__Noble3dModellingTools__Flatten3dTo2d__GeometryCollector__.rb`
  - `Na__Noble3dModellingTools__Flatten3dTo2d__FlattenBuilder__.rb`
  - `Na__Noble3dModellingTools__Flatten3dTo2d__SilhouetteBuilder__.rb`
  - `Na__Noble3dModellingTools__Flatten3dTo2d__Run__.rb`

### Update 02 - Behaviour and View Handling
- Requires Parallel Projection. In Perspective the tool offers a YES/NO prompt to switch the active view to Parallel Projection (`camera.perspective = false`) and continue, or cancels.
- Projects along the current camera direction (any ortho angle, not just standard Front/Top/etc).
- Geometry is collected in the active drawing context's coordinate space (recursive transform baking), and the world camera direction is mapped into that context via `model.edit_transform`, so the tool is correct at top level and inside nested containers.
- The new 2D group is placed at the front-most extent of the selection (closest to camera) so it stays tight to the originals rather than sitting far back when returning to a 3D view.
- All work is wrapped in a single undoable `start_operation`/`commit_operation`; the new group is selected on success.

### Update 03 - Registry, Router, and Loader Wiring
- Registered commands, buttons, and hotkey bindings in the JSON-driven UI command registry under `Geometry Tools > Group / Component to 2D` (tool_group_order 60):
  - `flatten_3d_to_group` / `Flatten 3D To Group`
  - `flatten_3d_to_silhouette` / `Flatten 3D To Silhouette`
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Wired handlers and module load paths through:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`

### Validation Checklist
- [ ] Both buttons appear under `Geometry Tools > Group / Component to 2D`; both menu items and hotkey bindings register.
- [ ] In a head-on Parallel Projection view, selecting the two window groups and running each tool yields a flat group facing the camera, sitting at the front of the originals; originals untouched; result is selected; single undo reverts it.
- [ ] Perspective view triggers the switch-to-parallel prompt.
- [ ] Silhouette keeps the gap between the window frames as a hole; Flatten To Group keeps full internal linework.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.2 - 02-Jun-2026 - Image Viewer Migration (Misc Utils)

### Update 01 - Image Carousel Module Migration from Vale Design Suite
- Migrated the Vale Design Suite image carousel viewer into Noble3d Modelling Tools as module `14__SourceCode__ImageCarousel`.
- Source reference:
  - `ValeDesignSuite/Utils__NotesAppAndImageViewer/Util__SketchUpModel__InBuiltImageViewingCaraselApp__HtmlDialogue.rb`
- Added dedicated standalone HtmlDialog feature module:
  - `10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__Loader__.rb`
  - `10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__Run__.rb`
  - `10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__DialogManager__.rb`
  - `10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__FolderScanner__.rb`
  - `10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__UiLayout__.html`
  - `10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__Styles__.css`
  - `10__PluginModules/14__SourceCode__ImageCarousel/Na__Noble3dModellingTools__ImageCarousel__UiBridge__.js`
- Split monolithic Vale heredoc into modular Ruby + external HTML/CSS/JS assets, matching the Entity Tree Reporter pattern.

### Update 02 - Misc Utils Tab + Registry, Router, and Loader Wiring
- Added new `Misc Utils` tab (order 60) to the JSON-driven UI command registry.
- Registered command, button, and hotkey binding:
  - `image_carousel` / `Image Viewer`
  - `Misc Utils > Image Tools > Image Viewer`
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Wired handler and module load paths through:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`

### Update 03 - Rebrand, Feature Trim, and Folder Scan Rules
- Removed Vale branding and Vale CSS tokens; replaced with Noble3d `--naImageViewer__*` design tokens and Segoe UI styling.
- Removed slideshow animation feature (Play/Pause button, timer, and Space shortcut).
- Added recursive folder scanner with archive ignore rules:
  - Skips any image whose relative path passes through `00__Archive` or `00__Ignore` at any nesting level.
- Normalised Windows scan paths to forward slashes before `Dir.glob` to avoid backslash glob failures.

### Update 04 - HtmlDialog Bridge and Reload Hardening
- Select Folder uses SketchUp action URL bridge on the button:
  - `onclick="window.location='skp:choose_folder@'; return false;"`
- Ruby folder results are pushed back via `window.SKP_onFolderChosen(...)`.
- Added lightweight HTML bootstrap callback before injected bridge script so Ruby always has a stable JS entry point even if the larger bridge initialises later.
- Fixed older CEF parser issue by avoiding raw backslash regex literals in JS path conversion (`String.fromCharCode(92)`).
- Added `Na__ImageCarousel__DialogManager__ResetDialog` and wired it into reload flow so `Reload Plugin Data` closes stale viewer windows and forces fresh HTML/CSS/JS injection on next open:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ReloadManager__.rb`
- Guarded scanner constants with `const_defined?` to avoid reload warnings during repeated `load`.

### Update 05 - Copy Path Clipboard Fix (SketchUp 2026 API Gap)
- Replaced unavailable `UI.copy_text_to_clipboard` call (not present in this SketchUp Ruby build) with OS clipboard commands:
  - Windows: `clip`
  - macOS fallback: `pbcopy`
- JS-side `document.execCommand('copy')` fallback retained for HtmlDialog clipboard behaviour.
- Ruby callback logs successful copy path to console for verification.

### Validation Checklist
- [x] `Misc Utils` tab appears in the main HtmlDialog.
- [x] `Image Viewer` button opens standalone viewer HtmlDialog from registry command routing.
- [x] `Select Folder` opens native OS folder picker and loads images from selected folder and child folders.
- [x] Images inside `00__Archive` / `00__Ignore` subfolders are excluded from scan results.
- [x] Thumbnail sidebar and main canvas viewer render loaded images correctly.
- [x] Slideshow/play animation controls are removed.
- [x] `Copy Path` copies current image native file path to clipboard without Ruby API error.
- [x] `Reload Plugin Data` resets Image Viewer dialog state and reloads updated viewer assets.
- [x] JavaScript bridge passes `node --check`.
- [x] IDE diagnostics report no linter errors for edited Image Carousel files.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.1 - 25-May-2026 - Entity Tree Reporter Dialog

### Update 01 - Entity Utils Hierarchy Reporter Module
- Added a new Entity Utils feature module for read-only hierarchy and tag inspection:
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__Loader__.rb`
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__Run__.rb`
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__TreeData__.rb`
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__EntityText__.rb`
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__ConsoleReport__.rb`
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__DialogManager__.rb`
- Refactored the original selected hierarchy/tag console reporter into small single-purpose modules for data collection, entity text formatting, console output, dialog lifecycle, and command entry.
- Tree data builder now reports:
  - active model root and active edit context path,
  - selected object or multi-selection roots,
  - nested group/component children,
  - lowest-level loose geometry type/tag summaries,
  - recursive component-definition skip notices.

### Update 02 - Dedicated HtmlDialog Tree Viewer
- Added a self-contained HtmlDialog UI for visual tree traversal:
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__UiLayout__.html`
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__Styles__.css`
  - `10__PluginModules/11__SourceCode__SelectedHierarchyTagReporter/Na__Noble3dModellingTools__SelectedHierarchyTagReporter__UiBridge__.js`
- Added `Selected Only` versus `Include siblings at selected level` reporting mode.
- Added `Refresh Tree`, `Print Console Report`, and `Copy Tree Markdown` actions.
- Clipboard export builds Markdown from the current tree data and uses a fallback copy path for older HtmlDialog clipboard behaviour.
- Reworked coloured UI surfaces to a blue/dark-blue palette.
- Updated report timestamps to display as `25-May-2026 - 10:55am`.

### Update 03 - Registry, Router, and Loader Wiring
- Registered the new tool in the JSON-driven UI command registry:
  - `selected_hierarchy_tag_reporter`
  - `Entity Utils > Hierarchy Reporting > Entity Tree Reporter`
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Routed the handler through:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`

### Validation Checklist
- [x] JSON command registry parses successfully after adding command/button/hotkey entries.
- [x] JavaScript bridge passes `node --check`.
- [x] `git diff --check` passes for touched files.
- [x] IDE diagnostics report no linter errors for the edited reporter UI and data files.
- [x] Ruby syntax check was skipped because `ruby` is not available on PATH in the current shell.

## -----------------------------------------------------------------------------
# =============================================================================

## Na Noble3d Modelling Tools | Version 0.4.0 - 15-May-2026 - SSOT Materials/Tags Pipeline + Web Status + Reload Diagnostics

### Update 01 - Standard Data Cache Wrapper + Reload Purge/Prime
- Added shared standard data cache wrapper:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__StandardDataCache__.rb`
- Cache wrapper primes and exposes common SSOT keys used by the plugin:
  - `:materials`, `:edge_materials`, `:tags`, `:components`
- Core app entry points now prime cache before UI/menu/command execution:
  - `02__Plugin__CoreAppData/01__CoreAppLoaders/Na__Noble3dModellingTools__CoreAppLoaders__Main__.rb`
- Reload flow now purges and force-reloads SSOT cache before Ruby reload and reports per-key cache source summary:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ReloadManager__.rb`

### Update 02 - Material Utils Tab + Command Surface + Module Wiring
- Added full Material Utils module:
  - `10__PluginModules/08__SourceCode__MaterialUtils/Na__Noble3dModellingTools__MaterialUtils__Loader__.rb`
  - `10__PluginModules/08__SourceCode__MaterialUtils/Na__Noble3dModellingTools__MaterialUtils__Run__.rb`
- Added Material Utils tab and command/button wiring in the JSON-driven UI registry:
  - `Load Modelling Utility Materials`
  - `Load TrueVision Materials Palette`
  - `Load All Noble Architecture Materials`
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Routed new handler keys through command router and module loader:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`

### Update 03 - Material Builder Reliability Pass (Root Cause Fix + Fallback Paths)
- Fixed default-template inheritance issue that incorrectly propagated `IsDefault=true` and reserved `SketchUpName` into real material entries.
- Changed skip logic to evaluate raw material entries only, preventing false skips.
- Hardened series resolution with:
  - exact-key match,
  - numeric-prefix fallback,
  - force-reload retry,
  - local SSOT fallback when web payload is stale.
- Added detailed diagnostics in command result text (requested/matched series, source, strategy, reload attempt, skip/failure reasons).

### Update 04 - SketchUp Material Translation Expansion (PBR + Texture + Metadata)
- Expanded material application from basic colour/alpha into broader SketchUp 2026 PBR setter coverage:
  - `roughness_factor=`, `metallic_factor=`, `normal_scale=`, `ao_strength=`
  - enable flags where supported (`roughness_enabled=`, `metalness_enabled=`, `normal_enabled=`, `ao_enabled=`)
- Added texture-map setter translation and safe texture path handling (local resolve + remote download cache).
- Added attribute-dictionary metadata persistence per material for SSOT traceability (material ID, series ID, source/version, raw/resolved payload, renderer-only payload, warning summary).

### Update 05 - SSOT Materials JSON Developer Mapping
- Added explicit developer/agent mapping block in materials SSOT meta section:
  - `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json`
  - `meta.Na__DataLib__SketchUpApiMapping`
- Mapping documents:
  - identity/control fields,
  - core material fields,
  - PBR factor fields,
  - texture-map fields,
  - metadata-only renderer fields.

### Update 06 - Tag Utils Tab + Multi-Set Tag Loaders (with Line Style/Colour Translation)
- Added full Tag Utils module:
  - `10__PluginModules/09__SourceCode__TagUtils/Na__Noble3dModellingTools__TagUtils__Loader__.rb`
  - `10__PluginModules/09__SourceCode__TagUtils/Na__Noble3dModellingTools__TagUtils__Run__.rb`
- Expanded tag loading into five command entry points:
  - `Load All Tags`
  - `Load Modeling Helper Tags`
  - `Load Line Thickness Tags`
  - `Load TrueVision Minimal Tags`
  - `Load TrueVision All Tags`
- Implemented robust tag filtering strategies (`:all`, group-key subsets, explicit tag-name subsets).
- Added line-style and colour translation pipeline:
  - line style assignment from SSOT (`dash`, `short dash`, etc.) with case-insensitive lookup,
  - direct RGB application where supplied,
  - edge-material-driven fallback colour mapping via `Na__DataLib__CoreIndex__EdgeMaterials__.json`.

### Update 07 - Settings Web Status Tool (Live SSOT Reachability Check)
- Added Web Status module:
  - `10__PluginModules/10__SourceCode__WebStatus/Na__Noble3dModellingTools__WebStatus__Loader__.rb`
  - `10__PluginModules/10__SourceCode__WebStatus/Na__Noble3dModellingTools__WebStatus__Run__.rb`
- Added `Check Web Data Status` command/button in Settings tab.
- Tool now iterates registered DataLib file keys from `Na__DataLib__UrlGenerator`, performs HTTP fetch, validates JSON parse, and returns per-file status summaries for live-data diagnostics.

### Update 08 - Loader/Path Error Fixes During Integration
- Fixed StandardDataCache `require_relative` depth so DataLib cache loader resolves correctly from Plugins root.
- Fixed ComponentEditorTools path resolution/require path issue that was breaking thumbnail tools load:
  - `Na__ComponentEditorTools__AppCore__PathResolver__.rb`
  - `Na__ComponentEditorTools__AppCore__Main__.rb`
- Added safer absolute-path resolution and existence checks for the failing module require path.

### Validation Checklist
- [x] Material Utils tab, commands, buttons, and hotkey entries appear and execute.
- [x] `Load Modelling Utility Materials` no longer fails due to false default inheritance skips.
- [x] Material loader reports source/series diagnostics and handles stale-web fallback paths.
- [x] Tag Utils tab, five tag-loader buttons, and routing paths are fully wired and executable.
- [x] Tag loader applies line style and colour metadata from SSOT/edge-material mappings.
- [x] Settings `Check Web Data Status` reports per-file live availability/JSON validity.
- [x] Reload flow purges/reloads standard cache and reports SSOT source map in summary.
- [x] Edited Ruby/JSON files validated with no introduced lint issues.

## -----------------------------------------------------------------------------
# =============================================================================
## Version 0.3.2 - 14-May-2026 - Entity Utils + Data-Driven Tool Cards

### Update 01 - Convert Components To Groups Module
- Added new Entity Utility module for converting selected SketchUp component instances into groups:
  - `10__PluginModules/05__SourceCode__ConvertComponentsToGroups/Na__Noble3dModellingTools__ConvertComponentsToGroups__Loader__.rb`
  - `10__PluginModules/05__SourceCode__ConvertComponentsToGroups/Na__Noble3dModellingTools__ConvertComponentsToGroups__EntityUtils__.rb`
  - `10__PluginModules/05__SourceCode__ConvertComponentsToGroups/Na__Noble3dModellingTools__ConvertComponentsToGroups__ComponentProps__.rb`
  - `10__PluginModules/05__SourceCode__ConvertComponentsToGroups/Na__Noble3dModellingTools__ConvertComponentsToGroups__Converter__.rb`
  - `10__PluginModules/05__SourceCode__ConvertComponentsToGroups/Na__Noble3dModellingTools__ConvertComponentsToGroups__Run__.rb`
- Refactored the original AI draft into project naming, region blocks, result-hash UI reporting, and small single-purpose helper modules.
- Preserves component instance transform, name, definition fallback name, layer/tag, material, hidden state, shadow settings, and attribute dictionaries where SketchUp allows.
- Recursively converts nested component instances inside selected components while skipping locked entities and existing groups.
- Restores SketchUp selection to the newly converted groups and reports success/failure through the dialog status footer.

### Update 02 - Insert Component In Place Module
- Added new Entity Utility module for Xref-style insertion of external `.skp` component files:
  - `10__PluginModules/06__SourceCode__InsertComponentInPlace/Na__Noble3dModellingTools__InsertComponentInPlace__Loader__.rb`
  - `10__PluginModules/06__SourceCode__InsertComponentInPlace/Na__Noble3dModellingTools__InsertComponentInPlace__Run__.rb`
- Opens a SketchUp file picker, loads the chosen `.skp` into `model.definitions`, and inserts the component at identity transform in root model entities.
- Selects the inserted instance after placement and reports cancel/load/error states through the shared result/status path.

### Update 03 - Entity Utils Tab + Command Registry Wiring
- Added a new `Entity Utils` tab for container/entity tools that are not raw geometry generation tools:
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ConfigLoader__.rb`
- Registered new commands, buttons, and hotkey bindings:
  - `convert_components_to_groups`
  - `insert_component_in_place`
- Wired both tools through:
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
- Mirrored live JSON registry additions into `NA_DEFAULT_CONFIG` so fallback config remains complete.

### Update 04 - Data-Driven Tool Group Sections
- Added data-driven tool grouping metadata to button registry entries:
  - `tool_group_name`
  - `tool_group_description`
  - `tool_group_order`
  - `button_order`
- Updated `Na__ConfigLoader` normalization and tab button sorting to preserve group/order fields from config.
- Updated `Na__DialogManager` to render generic tool group sections from registry data instead of hardcoded UI layout.
- Added visual group separation in `Na__Noble3dModellingTools__Styles__.css`.
- Reordered Geometry Tools groups through config so `Geometry Grouping` appears before `Lattice Generation`.

### Update 05 - Full-Card Interaction UI
- Removed the inner blue action buttons from tool cards.
- Refactored each tool card into the actual interactive button:
  - Tool title at the top.
  - Description text underneath.
  - Whole-card click target for clearer interaction.
- Added generic hover/active/focus feedback:
  - Hover lift.
  - Border highlight.
  - Subtle shadow.
  - Pressed scale animation.
  - Keyboard focus outline.
- Removed stale `naNoble3d__ActionButton` styling and references.

### Update 06 - Config-First Documentation Notes
- Added config-first design notes to the main plugin scripts so future tool tabs, groups, ordering, labels, command IDs, and hotkey exposure remain registry-driven:
  - `Na__Noble3dModellingTools__Loader__.rb`
  - `02__Plugin__CoreAppData/01__CoreAppLoaders/Na__Noble3dModellingTools__CoreAppLoaders__Main__.rb`
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
  - `02__Plugin__CoreAppData/04__PluginHotkeyManager/Na__Noble3dModellingTools__HotkeyManager__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ConfigLoader__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__DialogManager__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__PathResolver__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ReloadManager__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ToolbarIconLoader__.rb`
  - `05__Plugin__UserInterface/Na__Noble3dModellingTools__UiLayout__.html`
  - `05__Plugin__UserInterface/Na__Noble3dModellingTools__Styles__.css`
  - `05__Plugin__UserInterface/Na__Noble3dModellingTools__UiBridge__.js`

### Validation Checklist
- [x] `Entity Utils` tab appears in the HtmlDialog.
- [x] `Convert Components To Groups` appears under `Entity Utils > Component Containers`.
- [x] `Insert Component In Place` appears under `Entity Utils > Component Containers`.
- [x] Geometry Tools group order is `Geometry Grouping` then `Lattice Generation`.
- [x] Tool group sections render from config metadata, not hardcoded per-command UI.
- [x] Tool cards are full-card buttons with title, description, hover, active, and focus feedback.
- [x] JSON registry parses successfully after all command, tab, group, and button additions.
- [x] IDE lints report no errors for edited Ruby, JSON, HTML, CSS, and JS files.

## -----------------------------------------------------------------------------
# =============================================================================
## Version 0.3.1 - 08-May-2026 - Brand Header + Toolbar Icon

### Update 01 - Brand Header (NA Logo Left, Plugin Title Right)
- Replaced plain `naNoble3d__Header` block in HTML layout with ArchTools-style brand header:
  - `05__Plugin__UserInterface/Na__Noble3dModellingTools__UiLayout__.html`
  - Logo on left via `{{LOGO_FILE_URI}}` placeholder; "3D Modelling Tools" title right-aligned.
- Replaced old `naNoble3d__Header / __Title / __Subtitle` CSS rules with `na-brand-header` block:
  - `05__Plugin__UserInterface/Na__Noble3dModellingTools__Styles__.css`
  - Matches ArchTools `BrandHeader.css` — flex row, 36px logo, 18px/600 right-aligned title.

### Update 02 - Shared Assets Path Resolution
- Added `Na__Common__PluginDependencies` paths to PathResolver:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__PathResolver__.rb`
  - `Na__Noble3dModellingTools__SharedAssetsDirectory` — sibling `Na__Common__PluginDependencies` folder.
  - `Na__Noble3dModellingTools__NaLogoFilePath` — `IMG01__PNG__NaCompanyLogo.png`.
  - `Na__Noble3dModellingTools__NaIconFilePath` — `IMG02__ICN__NaCompanyIcon.png`.

### Update 03 - Logo URI Injection in DialogManager
- Added `{{LOGO_FILE_URI}}` gsub step to `na_render_dialog_html`:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__DialogManager__.rb`
- Added `na_resolve_logo_file_uri` helper — converts Windows path to `file:///...` URI with `%20` space encoding (required because `set_html` has no base URL for relative paths).

### Update 04 - SketchUp Toolbar Button
- Created new ToolbarIconLoader module:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ToolbarIconLoader__.rb`
  - `Na__Noble3dModellingTools::Na__ToolbarIconLoader`
  - Creates `UI::Toolbar` named "3D Modelling Tools" with `IMG02__ICN__NaCompanyIcon.png`.
  - Calls `UI::Toolbar#restore` to respect user-saved toolbar visibility.
  - Guarded with `return if @na_toolbar` to prevent duplicate toolbars on reload.
- Wired into bootstrap:
  - `02__Plugin__CoreAppData/01__CoreAppLoaders/Na__Noble3dModellingTools__CoreAppLoaders__Main__.rb`
  - `require_relative` added; `Na__ToolbarIconLoader.Na__Noble3dModellingTools__CreateToolbar` called inside `Na__Noble3dModellingTools__RegisterHotkeysAndMenu`.

### Validation Checklist
- [x] Dialog header shows NA logo left + "3D Modelling Tools" right.
- [x] Logo resolves from `Na__Common__PluginDependencies` (shared, not copied).
- [x] `file:///` URI encodes spaces — works with `set_html` (no base URL).
- [x] SketchUp toolbar "3D Modelling Tools" appears with NA company icon.
- [x] Toolbar visibility state persists across sessions via `restore`.

## -----------------------------------------------------------------------------
# =============================================================================
## Version 0.3.0 - 08-May-2026 - Auto Group Utility & Auto Group Face Islands Migration

### Update 01 - AutoGroupUtility Module (03__SourceCode__AutoGroupUtility)
- Migrated standalone `Na_AutoGroup.rb` (NaTools::Tools::AutoGroupSolidIslands) into the suite.
- Carved monolithic `self.run` into two focused files:
  - `10__PluginModules/03__SourceCode__AutoGroupUtility/Na__Noble3dModellingTools__AutoGroupUtility__IslandDetector__.rb`
    — `Na__AutoGroupUtility__ExtractRawGeometry` (grep edges + faces, uniq)
    — `Na__AutoGroupUtility__DetectIslands` (all_connected flood-fill loop)
  - `10__PluginModules/03__SourceCode__AutoGroupUtility/Na__Noble3dModellingTools__AutoGroupUtility__Run__.rb`
    — `Na__AutoGroupUtility__Run` public entry point
    — `na_group_island`, `na_validate_manifold`, `na_report_non_solids` private helpers
  - `10__PluginModules/03__SourceCode__AutoGroupUtility/Na__Noble3dModellingTools__AutoGroupUtility__Loader__.rb`

### Update 02 - AutoGroupFaceIslands Module (04__SourceCode__AutoGroupFaceIslands)
- Migrated standalone `Na_AutoGroup_ByIslands.rb` (NaTools::Tools::AutoGroupByIslands) into the suite.
- Re-namespaced four existing helper methods into a dedicated helper file:
  - `10__PluginModules/04__SourceCode__AutoGroupFaceIslands/Na__Noble3dModellingTools__AutoGroupFaceIslands__FaceGrouper__.rb`
    — `Na__AutoGroupFaceIslands__FilterToFacesOnly`
    — `Na__AutoGroupFaceIslands__CreateFaceGroup` (sequential FaceIsland_NNN naming)
    — `Na__AutoGroupFaceIslands__ValidateManifold`
    — `Na__AutoGroupFaceIslands__ApplySelectionDisplayFix` (SketchUp display bug workaround)
  - `10__PluginModules/04__SourceCode__AutoGroupFaceIslands/Na__Noble3dModellingTools__AutoGroupFaceIslands__Run__.rb`
    — `Na__AutoGroupFaceIslands__Run` public entry point
  - `10__PluginModules/04__SourceCode__AutoGroupFaceIslands/Na__Noble3dModellingTools__AutoGroupFaceIslands__Loader__.rb`

### Update 03 - UI + Hotkey Wiring
- Added both commands to command router with handler key dispatch:
  - `02__Plugin__CoreAppData/03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`
- Added both modules to feature module loader:
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`
- Registered both commands, Geometry Tools tab buttons, and hotkey_bindings in JSON registry:
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Mirrored both commands, buttons, and hotkey_bindings into NA_DEFAULT_CONFIG Ruby fallback:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ConfigLoader__.rb`
- Both commands exposed with `expose_to_hotkeys: true` — appear in SketchUp Shortcuts panel as:
  - `Na Noble3d - Auto Group Utility`
  - `Na Noble3d - Auto Group Face Islands`

### Update 04 - Old Standalone Plugin Deletion
- Deleted superseded standalone plugin files (4 files):
  - `Plugins/Na_AutoGroup.rb`
  - `Plugins/Na_AutoGroup_ByIslands.rb`
  - `Plugins/ValeDesignSuite/04_Dev_SimpleGeomProcessingScripts/Na_AutoGroup.rb`
  - `Plugins/ValeDesignSuite/04_Dev_SimpleGeomProcessingScripts/Na_AutoGroup_ByIslands.rb`

### Validation Checklist
- [x] Both new module folders present under `10__PluginModules`.
- [x] Both feature loaders registered in `ModuleLoaders__Main__`.
- [x] Both handler keys wired in `CommandRouter__`.
- [x] Both commands in JSON `commands[]` with `expose_to_hotkeys: true`.
- [x] Both buttons registered on `Geometry Tools` tab in JSON and `NA_DEFAULT_CONFIG`.
- [x] Both hotkey_bindings entries in JSON and `NA_DEFAULT_CONFIG`.
- [x] Old standalone files deleted from Plugins root and ValeDesignSuite.

## -----------------------------------------------------------------------------
# =============================================================================
## Version 0.2.0 - 08-May-2026 - Menu/Hotkey Recovery + UI Command Execution Fix

### Update 01 - Command Registration Resilience
- Hardened config normalization flow to prevent empty command registry from collapsing menu/hotkey exposure:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ConfigLoader__.rb`
- Added fallback behavior to default command set when runtime command normalization returns zero valid commands.
- Added startup diagnostics for:
  - resolved config path
  - total normalized command count
  - hotkey-visible command count

### Update 02 - Hotkey Manager Stability and Open Dialog Guarantee
- Refactored hotkey registration path:
  - `02__Plugin__CoreAppData/04__PluginHotkeyManager/Na__Noble3dModellingTools__HotkeyManager__.rb`
- Guaranteed `open_main_dialog` is always registered first (fallback command entry when config is incomplete).
- Added per-command registration logging (`Registered` / `Skipped` + reason).
- Routed UI command execution through top-level API to keep module-load behavior consistent.

### Update 03 - Startup Order + Module Loader Error Clarity
- Changed core bootstrap order to register menu/hotkeys before feature module loads:
  - `02__Plugin__CoreAppData/01__CoreAppLoaders/Na__Noble3dModellingTools__CoreAppLoaders__Main__.rb`
- Expanded module loader error reporting with explicit handling for file-level load failures:
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`

### Update 04 - Ruby Singleton Dispatch Fix (Capitalized Method Calls)
- Resolved NameError class of failures caused by Ruby interpreting bare capitalized identifiers as constants.
- Applied `self.` receiver dispatch for same-module singleton calls across core + feature modules.
- Files updated:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ConfigLoader__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__PathResolver__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__DialogManager__.rb`
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ReloadManager__.rb`
  - `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Run__.rb`
  - `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Topology__.rb`
  - `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Traversal__.rb`
  - `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Strategy__.rb`
  - `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__Run__.rb`
  - `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__Input__.rb`
  - `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__PlaneMath__.rb`
  - `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__SolidOps__.rb`

### Update 05 - HtmlDialog Button Click Execution Repair
- Fixed invalid inline onclick quoting that prevented tab/button JS handlers from firing:
  - `03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__DialogManager__.rb`
- Updated dialog callback command execution to use module-load aware run path before routing command results to status footer.

### Validation Checklist
- [x] `Extensions > Na__Noble3dModellingTools` submenu renders command items.
- [x] `Window > Preferences > Shortcuts` shows Noble3d shortcut-bindable commands.
- [x] `Open Noble3d Modelling Tools` shortcut command is exposed and bindable.
- [x] HtmlDialog tab buttons and action buttons execute commands.
- [x] Startup no longer fails with `Na__ConfigLoader::Na__Noble3dModellingTools__Commands` NameError.

## -----------------------------------------------------------------------------
## Version 0.1.0 - 08-May-2026 - Wiring Validation + Style Alignment Pass

### Update 01 - Full Wiring and Exposure Validation
- Confirmed Plugins-root loader exists and points to core loader:
  - `Na__Noble3dModellingTools__Loader__.rb`
- Revalidated `require_relative` resolution across all Ruby files under `Na__Noble3dModellingTools__Modules__`.
- Revalidated command exposure chain:
  - JSON `commands[].handler_key` values
  - Router `when '<handler_key>'` mappings
  - Button `command_id` references
  - Hotkey binding `command_id` references

### Update 02 - Root-Relative Path Corrections
- Corrected core loader `require_relative` depth for core logic modules:
  - `02__Plugin__CoreAppData/01__CoreAppLoaders/Na__Noble3dModellingTools__CoreAppLoaders__Main__.rb`
- Corrected module loader `require_relative` depth for feature module loaders:
  - `02__Plugin__CoreAppData/02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__.rb`
- Corrected path resolver root math:
  - `Na__Noble3dModellingTools__CoreAppLogic__PathResolver__.rb`
  - `ModulesRoot` now resolves to plugin `__Modules__` root
  - `PluginRoot` now resolves to SketchUp `Plugins` root

### Update 03 - JSON Formatting Alignment
- Reformatted UI command registry JSON to aligned-colon spacing style:
  - `02__Plugin__CoreAppData/Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`
- Kept all schema data and command wiring unchanged (formatting-only pass).

### Update 04 - CSS Formatting Alignment
- Refactored stylesheet with region blocks and aligned property/value spacing:
  - `05__Plugin__UserInterface/Na__Noble3dModellingTools__Styles__.css`
- Preserved existing class names and visual behavior.

### Update 05 - Ruby Style Normalization for Feature Modules
- Added full metadata header blocks (`FILE`, `NAMESPACE`, `PURPOSE`, `CREATED`) to all refactor files.
- Added explicit `REGION` / `# endregion` blocks to every feature file (including small loaders).
- Added `END OF FILE` banners consistently.

**SelectQuadFaceRings files updated:**
- `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Loader__.rb`
- `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Selection__.rb`
- `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Topology__.rb`
- `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Traversal__.rb`
- `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Strategy__.rb`
- `10__PluginModules/01__SourceCode__SelectQuadFaceRings/Na__Noble3dModellingTools__SelectQuadFaceRings__Run__.rb`

**LatticeMaker files updated:**
- `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__Loader__.rb`
- `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__Input__.rb`
- `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__PlaneMath__.rb`
- `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__SolidOps__.rb`
- `10__PluginModules/02__SourceCode__LatticeMaker/Na__Noble3dModellingTools__LatticeMaker__Run__.rb`

### Validation Checklist
- [x] Root loader present in main Plugins root.
- [x] Root loader points to core app loader.
- [x] All `require_relative` targets resolve.
- [x] JSON handlers are fully implemented in router.
- [x] Button command IDs map to defined commands.
- [x] Hotkey binding command IDs map to defined commands.
- [x] SelectQuadFaceRings files include regions + end-of-file markers.
- [x] LatticeMaker files include regions + end-of-file markers.
- [x] JSON spacing aligned to project style.
- [x] CSS spacing and region formatting aligned to project style.

# =============================================================================
