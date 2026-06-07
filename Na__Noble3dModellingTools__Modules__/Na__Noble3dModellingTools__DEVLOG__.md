# Na Noble3d Modelling Tools - Development Log
# =============================================================================

## Version History

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
