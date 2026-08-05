# Na Noble3d - Component Editor Tools - Development Log
# =============================================================================
# Module : 21__SourceCode__ComponentEditorTools
# Plugin : Na Noble3d Modelling Tools
# Tab    : Entity Utils > Component Inspection

## Overview

HtmlDialog tool for inspecting and editing the selected SketchUp component
instance/definition (Overview, Attributes, Thumbnail tabs), plus a disk-backed
**Component Library Manager** (Gallery + Index tabs) that scans a configured
`.skp` library folder, caches extracted metadata and thumbnails, supports
inline classification and metadata edits written back to each component file,
and places library components into the active model via a drawing-axis tool.

Per-component library metadata lives in the `Na__ComponentLibrary` attribute
dictionary on each definition (code, gallery_name, notes, category, type, and
user custom fields). Category → Type taxonomy is user-editable in Settings and
seedable from the shared SSOT Tags standards file.

Parent migration entry: main devlog **Version 0.5.1** (16-Jun-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================


# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.6.1 - 05-Aug-2026 - Export Tab: Multi-View Asset JSON Exporter

### Overview
New **Export** tab (between Thumbnail and Settings) that generates the unified Na asset JSON for the selected component: three fixed-axis 2D projections (Front / Right / Top), full 3D mesh with per-vertex normals, and the nested object hierarchy. Four live SVG viewports render directly from the generated JSON payload, so the preview is exactly the data that exports. Workflow: Monitor Selection capture, Generate Preview, visual check, Export JSON File (savepanel, remembered directory).

### Update 01 - New Module: 09__ExportTools
- `Na__ComponentEditorTools__ExportTools__Main__.rb` — capture engine and serializer, namespace `Na__ComponentEditorTools::Na__ExportTools`.
- Geometry read from the definition entities in definition space; local 0,0,0 from a nested `00__OriginPoint` group (bounding box bottom centre fallback with warning).
- 2D projection: silhouette + camera-facing hard edge classification, raytest hidden-edge cull (endpoint sampling along the view direction; origin-marker and foreign hits recast past, any other nearer hit occludes, faces and edges alike, since revolved parts share seam planes and seam rays only ever meet edge hits), exact ArcCurve paths, least squares circle refit of tessellated chains (Kasa fit, min 10 points, 0.02mm residual), collinear merge.
- 3D capture mirrors the Element Assembly Studio unified exporter: `face.mesh(7)` per-vertex normals, real edge records with soft/smooth flags, `Na__Asset__ObjectHierarchy3D` with local/world matrices.
- Product code = leading digit block of the component name (e.g. `50_1001`), written to `Na__Asset__Metadata__Id` and `Na__Asset__ValeSpec__ProductCode`. Output filename mirrors the component name with the Na double underscore suffix.
- Column-aligned Na JSON serializer (three-stage style) with inline matrix rows.

### Update 02 - Dialog Wiring
- `AppCore__Main` — requires the new module.
- `DialogManager` — callbacks `na_componenteditortools_export_generate_preview` and `na_componenteditortools_export_write_json`; `PushExportPreview` pushes `Na__ComponentEditorTools__ReceiveExportPreview` (preview document has mesh faces stripped, viewports only need vertices and edges; the export writes the full held document).

### Update 03 - UI
- `UiLayout` — Export tab button, tab panel (capture overlay, action row, four viewport cards, Export Summary and Warnings panels), script include.
- `Tab__Export__.js` — SVG renderers: 2D paths (lines/arcs/circles/polygons, y negated, CCW arcs drawn with sweep-flag 0, non-scaling strokes, origin crosshair) and fixed isometric 3D wireframe (hard edges solid, soft light, soft skipped above 30k edges). Fresh selection payloads invalidate the held preview and disable the export button.
- `TabRouter` — `export` registered as an auditing tab; `UiBridge.js` — outgoing calls, receive handlers, render fan-out; `Styles.css` — viewport grid, stroke classes, warning chips, disabled button state.

### Update 04 - Fixed: Arc Winding and Occlusion Stragglers
Two bugs found auditing the first real export (`50_1001__Finial__Ball__`) against the live SketchUp model, both fixed and re-verified on a second, more complex asset (`50_2001__Finial__Spire__` — 157/159 elevation lines, clean single-circle top plan, 3576 mesh edges).
- **Arc winding was reversed on screen.** `Tab__Export__.js` negates world Y to draw in SVG's y-down space; that reflection also reverses the direction an arc travels, so a path authored as sweep-flag 1 for a CCW world arc drew backwards after the flip. Fixed to sweep-flag 0.
- **Occlusion let seam-aligned rays leak through.** The original cull recast past every edge hit on the theory that an edge isn't a face and shouldn't occlude. But on lathe-turned assets every revolved part shares the same segment count, so a ray descending through a shared seam plane meets *only* edge hits all the way down — sphere top, sphere bottom, collar, neck — burns the whole recast budget, and fails open to "visible". Fixed: any nearer hit occludes, edge or face alike; only origin-marker hits and hits outside the selected instance are recast past. Recast budget raised 6 → 16 to keep those legitimate skip-chains resolving. `ExportTools__Main__.rb` `OcclusionCullEdges` / `SamplePointVisible`.

### Overview
Added a persistent **TrueVision Valid** boolean flag to every component in the library. The flag is stored in the `Na__ComponentLibrary` attribute dictionary on the `.skp` file — alongside the existing `code`, `gallery_name`, `notes`, `category`, and `type` core keys — and survives the full load → edit → save_as → re-extract round-trip. A toggle checkbox column in the Index table and a white-circle `✓` badge overlaid on thumbnails in both the Gallery and Index provide the visual interface.

### Update 01 - Serializer: `truevision_valid` Core Key
- `Na__ComponentLibrary` core-keys constant extended: `NA_CORE_KEYS = %w[code gallery_name notes category type truevision_valid]`.
- `ReadFromDefinition` — reads `dict['truevision_valid'].to_s` (yields `'true'`, `'false'`, or `''`); included in returned hash as `'truevision_valid'`.
- `WriteToDefinition` — writes `data_hash['truevision_valid'].to_s` to `dict['truevision_valid']`.
- `WriteSingleField` — already handles any non-`code` key generically; no change required.
- Error-fallback hash updated with `'truevision_valid' => ''`.

### Update 02 - Extractor: Forward Flag into Result Hash
- **Root cause fix:** `ExtractFromFile` assembled the result hash from `library_data` but never included `'truevision_valid'`. After a single-field save the component was re-extracted and the `updated_entry` pushed to JS lacked the key, so `entry.truevision_valid` was `undefined` and the checkbox re-rendered unchecked.
- `'truevision_valid' => library_data['truevision_valid']` added to the `ExtractFromFile` result hash.
- `ErrorResult` fallback hash also gets `'truevision_valid' => ''` for consistency.

### Update 03 - Editor: Route `truevision_valid` Through `UpdateField`
- `NA_FIELD_LABELS` extended: `'truevision_valid' => 'TrueVision Valid'`.
- `UpdateField` `when` clause extended: `when 'code', 'gallery_name', 'notes', 'category', 'type', 'truevision_valid'` — routes single-field checkbox saves through the existing `WriteSingleField` → `LoadEditSaveRemove` → `save_as` path.

### Update 04 - Index Tab: TrueVision Valid Column & Thumbnail Badge
- New `na_build_tv_badge()` helper — creates a `.naComponentEditor__TvValidBadge` `<span>` containing `✓`.
- `na_build_thumbnail_cell` — appends the badge when `entry.truevision_valid === 'true'`.
- New `na_build_truevision_cell(entry)` — builds a `<td class="naComponentEditor__IndexTd--tvValid">` containing a 16 px checkbox (`accent-color: #1f7a42`). `change` event: immediately updates `entry.truevision_valid` in memory, updates `checkbox.title`, and calls `na_save_field(entry, 'truevision_valid', 'true'/'false')` → `UpdateField` → disk write → re-extract → `ReceiveEntryUpdate`.
- `na_build_main_row` — new cell inserted between Description and Actions.
- Edit-row `colSpan` updated from `10` → `11`.
- `na_save_library_data` payload extended with `truevision_valid: entry.truevision_valid || ''` so the drill-down **Save Library Data** button also persists the flag.

### Update 05 - Gallery Tab: TrueVision Thumbnail Badge
- `na_build_card` — after appending the `<img>` to `thumb_wrap`, if `entry.truevision_valid === 'true'` a `.naComponentEditor__TvValidBadge` `<span>` is appended to `thumb_wrap` as an absolute overlay.

### Update 06 - HTML: TrueVision Valid Column Header
- New `<th class="naComponentEditor__IndexTh naComponentEditor__IndexTh--tvValid">TrueVision Valid</th>` inserted between Description and Actions in the Index `<thead>`.

### Update 07 - CSS: Badge & Column Styles
- `position: relative` added to `.naComponentEditor__GalleryThumbWrap` — enables absolute badge placement over gallery thumbnails.
- `position: relative` added to `.naComponentEditor__IndexTd--thumb` — same for index thumbnail cells.
- New `#region | TrueVision Valid Badge`:
  - `.naComponentEditor__TvValidBadge` — `position: absolute; top: 4px; right: 4px; z-index: 10; width/height: 18px; border-radius: 50%; background: rgba(255,255,255,0.88); color: #1f7a42; font-size: 12px; font-weight: 700; pointer-events: none; box-shadow: 0 1px 3px rgba(0,0,0,0.18)`.
- `.naComponentEditor__IndexTh--tvValid` — 90 px wide, centred.
- `.naComponentEditor__IndexTd--tvValid` — 90 px wide, centred, `padding: 4px 6px`.
- `.naComponentEditor__IndexTvCheckbox` — 16 px checkbox, `accent-color: #1f7a42`.

### Validation Checklist
- [ ] Checking a TrueVision Valid checkbox persists across a library reload (the `.skp` dict is written correctly).
- [ ] Unchecking removes the badge from both thumbnail and gallery card on next render.
- [ ] Badge appears top-right on gallery card thumbnails when `truevision_valid: 'true'`.
- [ ] Badge appears top-right on index table thumbnail cells when `truevision_valid: 'true'`.
- [ ] Components with no prior `Na__ComponentLibrary` dict show the checkbox unchecked (no crash).
- [ ] "Save Library Data" in the drill-down panel also persists the current checkbox state.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.6.0 - 19-Jun-2026 - Component Geometry Audit Panel & Monitor Selection Toggle

### Overview
Added a full recursive **Component Geometry** audit panel to the Overview tab, a one-shot **Monitor Selection** toggle that gates the expensive geometry traversal, and per-panel capture overlays across the three selection-dependent auditing tabs. A new **Copy Stats** feature serialises all geometry stats to columnised plain text for quick reference.

### Update 01 - Geometry Auditor (`Na__ComponentEditorTools__SelectionInspector__GeometryAudit__.rb`)
- New module `Na__ComponentEditorTools::Na__GeometryAudit` in `02__SelectionInspector/`.
- `Na__ComponentEditorTools__BuildGeometryStats(instance)` performs a single-pass `case/when is_a?` recursive traversal of the entire component/group hierarchy (`definition.entities`, descending into nested `Group` and `ComponentInstance`).
- Collected stats: `faces`, `edges`, `triangles` (`face.mesh.count_polygons` flag 0), `quads` (4-vertex outer loop), `soft_edges`, `smooth_edges`, `hidden_edges`, `non_manifold_edges`, `nested_groups`, `nested_components`, `unique_definitions`, `construction_lines`, `construction_points`, `texts`, `dimensions`, `images`, `section_planes`, `attribute_dicts`, `attribute_keys`, `total_face_area`, `is_solid` (`definition.manifold?`).
- Material lists (`face_materials`, `edge_materials`): unique entries deduped by display name, each carrying `{name, textured, texture_file}` from `Material#materialType` / `Material#texture`.
- `tags`: unique `entity.layer.display_name` values collected at every level.
- All entity classifiers wrapped in individual `rescue` so a corrupt entity never crashes the panel. Full entry-point also rescue-wrapped.
- `AppCore__Main__.rb` — `require_relative` for the new file inserted before `SelectionInspector__Main__`.

### Update 02 - SelectionInspector Payload: `include_geometry` / `captured`
- `Na__ComponentEditorTools__BuildPayload` gains optional keyword arg `include_geometry: false`.
- When `true` and `Na__GeometryAudit` is defined, `geometry:` key is added to the payload by calling `Na__GeometryAudit.Na__ComponentEditorTools__BuildGeometryStats`.
- Payload always includes `captured: bool` (mirrors `include_geometry`). The JS uses this to toggle the `naComponentEditor--awaitingCapture` body class driving capture overlays.

### Update 03 - DialogManager: Monitor Selection State & Gated Observer
- Added `@na_monitoring_enabled = false` module-level state.
- `Na__ComponentEditorTools__HandleSelectionChanged` now returns immediately unless monitoring is armed. When armed and a new valid instance is detected: builds full payload with `include_geometry: true`, pushes it, sets `@na_monitoring_enabled = false` (auto-disarm), updates selection key, pushes monitoring state to JS. Wrapped in `rescue` for observer robustness.
- `Na__ComponentEditorTools__BuildAndPushPayload(include_geometry: false)` — default open/request stays geometry-free; edit result re-pushes pass `include_geometry: true` (via `HandleActionResult`) to keep the geometry panel alive after edits.
- `Na__ComponentEditorTools__SetMonitoring(enabled)` + `Na__ComponentEditorTools__PushMonitoringState` — toggles state, pushes "Click a component in the model…" status when arming, calls JS `Na__ComponentEditorTools__ReceiveMonitoringState({enabled})`.
- New callback `na_componenteditortools_set_monitoring` registered in `BindCallbacks`.
- `ShowDialog` now calls `PushMonitoringState` to initialise the button on load.

### Update 04 - HTML: Monitor Toggle, Moved Update Component, Geometry Panel, Capture Overlays
- **Header:** "Update Component" replaced with `#na-component-btn-monitor-selection` (`naComponentEditor__MonitorBtn naComponentEditor__MonitorBtn--off`).
- **Overview Editable Fields:** "Update Component" button added alongside "Apply Edits" (functionality unchanged via same `na_componenteditortools_update_component` callback).
- **Overview tab:** New **Component Geometry** panel placed at the top (before Editable Fields), containing: a flex header row with title/subheading and a **Copy Stats** button (`#na-component-btn-copy-stats`), two 2-column grids (Polygon Stats / Edge Stats; Nested Entities / Misc & Topology), Face Materials list, Edge Materials list, Tags Used list.
- **Capture overlays:** Semi-transparent sticky overlay with "Enable Monitor Selection" CTA button added inside Overview, Attributes, and Thumbnail tab panels — shown/hidden by CSS body-class gating.
- New `<script src="Na__ComponentEditorTools__GeometryClipboard__.js">` added before the Overview tab script.

### Update 05 - UiBridge JS: Monitoring Integration
- `Na__ComponentEditorTools__State` gains `monitoringEnabled` field.
- `Na__ComponentEditorTools__SetMonitoring(enabled)` — outgoing call to `na_componenteditortools_set_monitoring`.
- `Na__ComponentEditorTools__ReceiveMonitoringState({enabled})` — updates button label + `--on`/`--off` classes.
- `Na__ComponentEditorTools__ReceivePayload` — toggles `naComponentEditor--awaitingCapture` body class based on `payload.captured !== true`.
- DOMContentLoaded: binds monitor toggle button click (toggle state → `SetMonitoring`); delegates all `naComponentEditor__CaptureOverlayBtn` clicks to `SetMonitoring(true)`.
- Both new functions exported on `window`.

### Update 06 - Overview Tab JS: Geometry Panel Renderer
- New private helpers in `Tab__Overview__.js`: `na_geom_stat_row`, `na_material_chip`, `na_tag_chip`, `na_render_material_list`, `na_render_tag_list`.
- New `na_render_geometry_panel(geometry)` function populates all six geometry sub-containers (counts, edges, nested, misc, face materials, edge materials, tags). Clears gracefully to prompt text when `geometry` is `null`.
- `Na__ComponentEditorTools__Render` calls `na_render_geometry_panel(payload.geometry || null)` at end of both the ok and not-ok branches.

### Update 07 - Geometry Clipboard (`Na__ComponentEditorTools__GeometryClipboard__.js`)
- New standalone module for plain-text clipboard serialisation.
- `na_build_plain_text(geometry, component_name)` formats all stats into `### Section\nKey                  =  Value` blocks, with a 20-character padded key column — matching the plain-text spec in the brief (see example below).
- Each section: Polygon Stats, Edge Stats, Nested Entities, Misc & Topology, Face Materials, Edge Materials, Tags Used.
- `Na__ComponentEditorTools__CopyGeometryStats()` reads `window.Na__ComponentEditorTools__CurrentPayload()`, builds the plain text, writes via `navigator.clipboard.writeText` with `document.execCommand('copy')` fallback for SketchUp's older WebView.
- Button briefly shows green `✓ Copied!` or red `✗ Failed` then resets to original label.
- DOMContentLoaded binds `#na-component-btn-copy-stats` → `CopyGeometryStats`.

**Example clipboard output:**
```
Component: _Kreslas+Domo+prekyba
---------------------------------

### Polygon Stats
Faces                =  312
Triangles            =  628
Quads                =  0
Total Face Area      =  45231.2mm²
Solid?               =  No

### Edge Stats
Edges                =  29436
Soft                 =  28162
Smooth               =  28162
Hidden               =  0
Non-manifold         =  0
```

### Update 08 - CSS Additions
- **Monitor button:** `naComponentEditor__MonitorBtn--off` (muted grey) / `--on` (green accent with pulsing `box-shadow` keyframe animation).
- **Capture overlay:** `naComponentEditor__CaptureOverlay` — sticky dark frosted-glass banner (`backdrop-filter: blur(4px)`); shown only when `body.naComponentEditor--awaitingCapture` is set AND the relevant tab panel carries `--active`. Message text with highlighted keyword.
- **Geometry panel header:** `naComponentEditor__GeomPanelHeader` flex row (heading/subheading left, Copy Stats button right).
- **Copy button states:** `naComponentEditor__GeomCopyBtn--success` (green) / `--fail` (red) transient feedback.
- **Geometry chips:** `naComponentEditor__GeomSubheading`, `naComponentEditor__MetaValue--stat` (tabular-nums), `naComponentEditor__GeomChip`, `naComponentEditor__GeomTagChip`, `naComponentEditor__GeomList`, `naComponentEditor__GeomTagList`.

### Validation Checklist
- [ ] Dialog opens with Monitor Selection: Off and all three auditing tabs show capture overlays.
- [ ] Clicking the header toggle arms monitoring (button turns green with pulse); status bar says "Click a component…".
- [ ] Selecting a component fires geometry audit, populates all geometry sub-panels, hides overlays, auto-disarms toggle.
- [ ] Clicking any overlay's "Enable Monitor Selection" button also arms monitoring.
- [ ] After a monitored capture, Apply Edits / Update Component re-pushes payload with geometry (panel stays populated).
- [ ] Copy Stats copies correctly columnified plain text; button flashes green "✓ Copied!".
- [ ] Geometry panel is first visible section in Overview tab.
- [ ] Monitor Selection: Off renders in muted grey; On renders in green with animation.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.5.4 - 17-Jun-2026 - Copy Path & Folder Edit Bug Fix

### Update 01 - Copy File Path: Index Tab Actions Button
- New **Copy Path** button added as the 4th action in each Index row's Actions cell (after Open).
- Clicking copies the full `.skp` file path (native Windows backslash format) to the clipboard and shows a `'File path copied to clipboard'` success toast in the status bar (auto-clears after 3 s).
- Clipboard write uses a hidden `<textarea>` + `document.execCommand('copy')` for the HtmlDialog context, with a Ruby `IO.popen('clip')` / `pbcopy` fallback bridge call.
- `Tab__Index__.js` — three new helpers in a *Clipboard & Toast Helpers* region: `na_extract_dir_from_path` (retained for future use), `na_copy_text_via_dom`, `na_show_copy_toast`. `na_build_actions_cell` extended with `copy_btn`.
- `UiBridge__.js` — `Na__ComponentEditorTools__CopyComponentPath(component_path)` outgoing bridge fires `na_componenteditortools_copy_component_path`; exported on `window`.
- `DialogManager__.rb` — `na_componenteditortools_copy_component_path` callback; private `Na__ComponentEditorTools__CopyPathToClipboard(path)` helper: normalises to native path, writes via `IO.popen('clip')` on Windows / `pbcopy` on macOS, `puts` on success, `UI.messagebox` on error.
- `Styles__.css` — `.naComponentEditor__IndexTh--actions` widened from `110px` to `160px` to accommodate 4 buttons.

### Update 02 - Copy File Path: Gallery Right-Click Context Menu
- Right-clicking any Gallery card suppresses the native browser context menu and shows a custom floating menu with one item: **Copy File Path**.
- Clicking the item copies the full `.skp` file path and shows the same toast as the Index button.
- `Tab__Gallery__.js` — *Clipboard & Toast Helpers* region (same `na_copy_text_via_dom` / `na_show_copy_toast` pattern). *Context Menu* region: `na_context_menu_el` singleton, `na_get_context_menu` (lazy-creates a `<div id="na-gallery-context-menu">` appended to body), `na_show_context_menu` (positions menu at cursor, prevents overflow beyond viewport), `na_hide_context_menu`. `na_build_card` gains a `contextmenu` listener. `na_bind_events_once` registers a document-level `click` listener that dismisses the menu.
- `Styles__.css` — new `#region | Gallery - Right-Click Context Menu`: `.naComponentEditor__ContextMenu` (fixed, z-index 9999, border + shadow, hidden by default), `.naComponentEditor__ContextMenuItem` (hover accent).

### Update 03 - Bug Fix: relative_dir Edit Creates Duplicate Table Row
- **Root cause:** `RefreshSingleCacheEntry` compared paths with a strict forward-slash exact match. On Windows, drive-letter case differences between `UI.select_directory` output (e.g. `c:/`) and `Dir.glob` output (`C:/`) caused the lookup to return `nil`, so the new entry was appended to `@na_library_cache['entries']` without removing the old one. A subsequent `HandleGetIndex` then pushed both entries to JS, rendering the component twice. A parallel exact-match failure in `ApplyEntryUpdate` also caused an immediate in-table duplicate.
- `DialogManager__.rb` — `RefreshSingleCacheEntry`: after the exact-match `index` search fails, a second case-insensitive pass is attempted. If still `nil`, `entries.reject!` purges any stale entry matching either the old or new path (case-insensitive) before appending — guaranteeing no duplicate survives in the cache.
- `Tab__Index__.js` — `ApplyEntryUpdate`: same two-stage lookup (exact then case-insensitive) before concluding `index === -1`. When genuinely not found, filters out stale old/new path variants before pushing. Also calls `na_populate_index_folder_filter()` before `na_rebuild_table()` so the folder filter dropdown updates immediately to reflect the post-move folder structure (removes emptied folders, adds the new one).

### Validation Checklist
- [x] Index tab: Copy Path button appears as 4th action; clicking copies full .skp path in backslash format; toast appears and auto-clears.
- [x] Gallery tab: Right-click on card shows context menu; "Copy File Path" copies full path; toast appears; clicking outside dismisses menu.
- [x] Both clipboard paths include filename (e.g. `D:\Library\Folder\Component.skp`), not just directory.
- [x] Editing `relative_dir` inline moves file on disk and updates the single row in place — no duplicate row appears.
- [x] Folder filter dropdown updates immediately after a `relative_dir` edit (emptied source folder drops; new folder appears).
- [x] Other field edits (code, gallery_name, def_name, file_name, description) unaffected.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.5.3 - 17-Jun-2026 - Settings UX Refinements & Gallery Cleanup

### Update 01 - Settings Tab: Collapsible Library Exclusions Panel
- Replaced the standalone **Blocked Folder Names** panel with a collapsible **Library Exclusions** section using native `<details>/<summary>` (collapsed by default, positioned after Plugin Maintenance).
- Two nested subsection cards inside the disclosure: **Folder Exclusions** (existing `blocked_folder_names` behaviour; UI label only) and new **File Exclusions** (`blocked_file_names` list).
- File exclusions use exact `File.basename` match anywhere in the library tree — mirrors the folder segment-match approach.
- `UiLayout__.html` — old blocked panel removed; `naComponentEditor__SettingsDisclosure` parent added with two `naComponentEditor__ExclusionSubsection` children; distinct element IDs for folder and file list/input/button.
- `Styles__.css` — new `#region | Settings - Library Exclusions Disclosure`: chevron `::before` rotates 90° when open; `SettingsDisclosureBody` top-border separator; `ExclusionSubsection` nested card; reuses all existing chip classes.
- `Tab__Settings__.js` — `na_render_blocked_list` replaced by shared `na_render_exclusion_list(list_el, names, empty_message, on_remove)`; `na_render_config` drives both lists; file input + Add button wired with Enter key support.
- `UiBridge__.js` — `Na__ComponentEditorTools__AddBlockedFile` / `RemoveBlockedFile` added and exported on `window`.
- `UserConfig__.rb` — `blocked_file_names: []` added to defaults (auto-merges for existing configs); `BlockedFiles`, `AddBlockedFile`, `RemoveBlockedFile` accessors added.
- `DialogManager__.rb` — `na_componenteditortools_add_blocked_file` and `na_componenteditortools_remove_blocked_file` callbacks registered; push config + status on success.
- `Scanner__.rb` — `BlockedFile?` predicate added; `CollectSkpFiles` and `FolderList` both apply file exclusions; folders that become empty after file exclusions automatically drop from the Gallery folder filter.

### Update 02 - Settings Tab: Component Categories & Types Now Collapsible
- Wrapped the **Component Categories & Types** panel body in the same `naComponentEditor__SettingsDisclosure` pattern (collapsed by default). No JS or CSS changes required — reuses disclosure styles from Update 01.
- `UiLayout__.html` — `<details>/<summary>` wrapper added; description paragraph and all taxonomy controls moved inside `naComponentEditor__SettingsDisclosureBody`.

### Update 03 - Gallery Tab: Header Panel Removed & Button Repurposed
- Removed the redundant **Component Gallery** panel (heading, status message, Load/Reload button) from the top of the Gallery tab. Grid now displays immediately with no preceding panel.
- **Reload Selection** header button repurposed as **Reload Library** — triggers `RefreshLibrary()` guarded by `window.confirm` ("This will re-scan and re-extract all component files and may take a moment").
- **Update Component** header button also guarded with a `window.confirm` prompt to prevent accidental triggers from its proximity to Reload Library.
- `UiLayout__.html` — gallery panel block removed; button label updated to "Reload Library".
- `Tab__Gallery__.js` — `na_gallery_message()` DOM helper removed; `msg_el` update in `na_render_gallery` removed; `na-gallery-btn-load` click listener removed. Auto-load via `OnTabActivate → GetGallery()` unchanged.
- `UiBridge__.js` — `na-component-btn-header-refresh` click handler rewired from `RequestSelection` to `RefreshLibrary` with confirm; `na-component-btn-update-component` wrapped in confirm.

### Validation Checklist
- [x] Library Exclusions disclosure collapsed on open; expands to reveal both subsection cards.
- [x] Folder exclusion add/remove and persistence unchanged.
- [x] File exclusion chips appear, persist, and excluded files disappear from Gallery/Index after Refresh Library.
- [x] Existing configs without `blocked_file_names` load cleanly with an empty file list.
- [x] Component Categories & Types collapses/expands cleanly; taxonomy CRUD unaffected.
- [x] Gallery tab opens directly to grid; auto-load on tab activate still fires.
- [x] Reload Library confirm appears; cancel aborts; confirm triggers full re-scan.
- [x] Update Component confirm appears; cancel aborts; confirm writes changes.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.5.2 - 17-Jun-2026 - Index UX: Filter Bar, Panel Cleanup, Open File Action

### Update 01 - Index Tab Filter Bar
- Added a Gallery-style 4-control filter bar (Folder, Category, Type, Search) to the Index tab, shown in the tab action bar whenever Index is active.
- `TabRouter__.js` — `na_apply_tab_classes` now also toggles `naComponentEditor__TabBar--indexActive` class; CSS uses this to show/hide the Index filter bar.
- `UiLayout__.html` — `naComponentEditor__IndexFilters` div inserted in the tab bar `<nav>` (sibling to `GalleryFilters`); text input (`na-index-filter`) moved from the panel toolbar into this bar.
- `Styles__.css` — new `#region | Tab Bar - Index Filters` block; display/flex rules, select min-widths (140 px), search width (160 px).
- `Tab__Index__.js` additions:
  - **DOM helpers:** `na_index_folder_filter`, `na_index_category_filter`, `na_index_type_filter`.
  - **Taxonomy helpers:** `na_index_category_names`, `na_index_types_for`, `na_index_all_types`.
  - **Populate functions:** `na_populate_index_folder_filter` (derives unique `relative_dir` values from loaded entries), `na_populate_index_category_filter`, `na_populate_index_type_filter` (scoped to selected category, preserves selection).
  - `na_render_index` — calls all three populate functions after `na_all_entries` is set.
  - `na_rebuild_table` — extended to read and apply folder/category/type values on top of the existing text filter.
  - `na_bind_events_once` — change listeners on all three new selects; category change cascades type repopulate.
  - `Na__ComponentEditorTools__SetTaxonomy` — repopulates index category and type filters when taxonomy arrives.

### Update 02 - Index Panel Header Removed
- Removed the `naComponentEditor__Panel` section (heading "Component Index", subheading, Load/Reload + Collapse All toolbar) from the top of the Index tab body — was wasting a significant amount of vertical space.
- Load/Reload (`na-index-btn-load`) and Collapse All (`na-index-btn-collapse-all`) buttons relocated into the tab action bar.
- `na-index-message` retained as a hidden `<span>` so existing JS null-check in `na_render_index` continues to work without errors.

### Update 03 - Open Component File Row Action
- New **Open** button added to each Index row's Actions cell (after Insert), allowing the `.skp` file to be opened in a new SketchUp instance directly from the Index.
- `Tab__Index__.js` — `na_build_actions_cell` appends an Open button that calls `window.Na__ComponentEditorTools__OpenComponentFile(entry.path)`.
- `UiBridge__.js` — `Na__ComponentEditorTools__OpenComponentFile(component_path)` outgoing bridge function fires `na_componenteditortools_open_component_file`; exported on `window`.
- `DialogManager__.rb` — `na_componenteditortools_open_component_file` callback: validates file exists, pushes status message, defers OS shell call via `UI.start_timer(0.0, false)` (`start "" "path"` on Windows, `open "path"` on macOS). No blocking of the HtmlDialog callback thread.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.5.1 - 17-Jun-2026 - Index Tab Toolbar Polish

### Update 01 - Tab Button Squishing Fix
- Root cause: `.naComponentEditor__TabButton` and `.naComponentEditor__TabDivider` had no `flex-shrink: 0`. When Index mode activated, `.naComponentEditor__IndexFilters` appeared as a wide sibling flex item in the same row (~700 px across 3 selects + search), and the flex algorithm compressed the tab buttons to make room.
- Fix: added `flex-shrink: 0` and `white-space: nowrap` to `.naComponentEditor__TabButton`; `flex-shrink: 0` to `.naComponentEditor__TabDivider` (`Styles__.css`).

### Update 02 - Load / Reload & Collapse All Moved to Right Header
- "Load / Reload" and "Collapse All" were crammed into `.naComponentEditor__IndexFilters` alongside the 3 filter selects and search input, causing visual clutter and layout pressure.
- Moved both buttons into `.naComponentEditor__HeaderActions` inside a new `.naComponentEditor__IndexActions` wrapper div. The existing auditing-tab buttons ("Update Component", "Reload Library") are wrapped in a new `.naComponentEditor__AuditingActions` div.
- `TabRouter__.js` — `na_apply_tab_classes` updated: `HeaderActions` is now shown for both auditing tabs and the Index tab; `AuditingActions` vs `IndexActions` inline display is toggled to show only the relevant group per active tab.
- `Styles__.css` — `.naComponentEditor__AuditingActions` and `.naComponentEditor__IndexActions` flex wrapper rules added; `flex-shrink: 0` added to `HeaderActions`; orphaned `.naComponentEditor__IndexFiltersDivider` rule removed.
- `UiLayout__.html` — `IndexFilters` now contains only the 3 filter selects and search input; `IndexActions` div in `HeaderActions` holds the two action buttons.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.5.0 - 17-Jun-2026 - Category & Type Taxonomy

### Update 01 - Taxonomy Module and Persistence
- New `01__AppCore/Na__ComponentEditorTools__AppCore__Taxonomy__.rb` — manages the editable Category → Type hierarchy persisted to `07__UserData/Na__ComponentEditorTools__CategoryTaxonomy__.json`.
- Default baked categories: **Building**, **Fixtures**, **Furniture**, **Interior Furnishings**, **Vale Orangery**, **Vale Conservatory**, **Environment** — each with a contextual type list so dropdowns stay short (e.g. Furniture → Lounge / Dining Room / Bedroom; Vale Orangery → Door Handle / Roof Lantern / Finial).
- **Populate from Standards** reads local `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json`, derives **Building** types from `{Existing,Proposed}Building__{X}` tag names and **Environment** types from site/landscape/vegetation tags, then merges with bespoke Furniture/Vale defaults.
- `PathResolver__.rb` — added `CategoryTaxonomyFilePath` and `DataLibTagsFilePath`.
- `AppCore__Main__.rb` — requires Taxonomy module after UserConfig.

### Update 02 - Serializer, Extractor, and Single-Field Editor Routes
- `Na__ComponentLibrary` core keys extended: `category`, `type` (alongside `code`, `gallery_name`, `notes`).
- `LibraryManager__Serializer__.rb` — read/write for category and type; `WriteSingleField` supports surgical single-key writes without clobbering other dictionary keys.
- `LibraryManager__Extractor__.rb` — merges `category` and `type` into every cache entry.
- `LibraryManager__Editor__.rb` — `UpdateField` routes `category` and `type` through serializer single-field write + `save_as`.

### Update 03 - Index Category & Type Dropdown Columns
- `Tab__Index__.js` — two new columns after Gallery Name: **Category** and **Type** as cascading `<select>` dropdowns populated from taxonomy. Changing category auto-clears type when it no longer belongs to the new category. Saves via `UpdateField` → disk → single-entry re-extract.
- `UiLayout__.html` — sortable Category and Type column headers; edit-row `colSpan` increased to 9.
- `Styles__.css` — `IndexSelect`, column widths, select-cell padding.

### Update 04 - Gallery Category & Type Filters
- `Tab__Gallery__.js` — **All Categories** and **All Types** filter dropdowns in toolbar; type list cascades from selected category (or shows union of all types when no category selected). Filters combine with existing search and folder filter.
- `UiLayout__.html` — category and type `<select>` elements in gallery toolbar.
- `Styles__.css` — gallery filter min-widths.

### Update 05 - Settings Taxonomy Management UI
- `UiLayout__.html` — new **Component Categories & Types** panel: Populate from Standards button, per-category type chip list with remove, Add Type row, Add Category row.
- `Tab__Settings__.js` — `RenderTaxonomy` builds category blocks with type chips and CRUD inputs.
- `DialogManager__.rb` — callbacks: `get_taxonomy`, `add_category`, `remove_category`, `add_type`, `remove_type`, `seed_taxonomy`; pushes taxonomy on dialog open via `PushTaxonomy`.
- `UiBridge__.js` — `ReceiveTaxonomy` fans out to Settings, Index, and Gallery; outgoing `GetTaxonomy`, `AddCategory`, `RemoveCategory`, `AddType`, `RemoveType`, `SeedTaxonomy`.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.4.0 - 17-Jun-2026 - Index Double-Click Inline Editing

### Update 01 - Double-Click Editable Table Cells
- Replaced always-on inline `<input>` cells (which lost focus on full table re-render) with **double-click-to-edit** pattern for all data columns: Code, Gallery Name, Definition Name, File Name, Folder, Description.
- Enter commits; Escape or blur-without-Enter cancels. Description uses `<textarea>` (Shift+Enter for newline).
- `na_editing_active` guard prevents full table rebuild from clobbering an in-progress edit.

### Update 02 - Single-Field Save Router (`UpdateField`)
- New `LibraryManager__Editor__.rb` method `Na__ComponentEditorTools__UpdateField` — routes one field at a time:
  - `code`, `gallery_name`, `notes`, `category`, `type` → serializer single-field write to `Na__ComponentLibrary` dict.
  - `def_name` → `definition.name`.
  - `description` → `definition.description`.
  - `file_name` → rename `.skp` on disk (sanitised, auto `.skp` suffix, refuse overwrite).
  - `relative_dir` → move file under library root (creates dirs, refuse overwrite).
- `DialogManager__.rb` — `na_componenteditortools_update_field` callback; `HandleUpdateField` always re-extracts the component from disk and pushes `ReceiveEntryUpdate` (success or failure reverts cell from "Saving…" state).
- `UiBridge__.js` — `UpdateField` outgoing, `ReceiveEntryUpdate` incoming; Index `ApplyEntryUpdate` patches one row in `na_all_entries` without full reload.

### Update 03 - Bug Fix: `TypeError: no implicit conversion of true into String`
- Root cause: `UpdateLibraryData` block implicitly returned `true` from `WriteToDefinition`; `LoadEditSaveRemove` treated that as `new_save_path` → `definition.save_as(true)`.
- Fix: explicit `nil` return at end of `UpdateLibraryData` block (same pattern as `UpdateMetadata`).

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.3.0 - 17-Jun-2026 - Per-Component Library Data (DC Dictionary)

### Update 01 - `Na__ComponentLibrary` Serializer
- New `08__LibraryManager/Na__ComponentEditorTools__LibraryManager__Serializer__.rb`.
- Dictionary: `Na__ComponentLibrary` on component **definition**.
- Core keys: `code`, `gallery_name`, `notes` (+ later `category`, `type`). Any other key = custom field.
- `Na__ComponentEditorTools__DeriveCode(name)` — regex extracts prefix like `03_11__`, `27_4003__`, `90_9031__` from definition name.
- `ReadFromDefinition` — read-only; display `code` = stored override OR derived.
- `WriteToDefinition` — writes core + custom; `deleted_custom_keys` array removes custom keys.

### Update 02 - Extractor and Editor Integration
- `LibraryManager__Extractor__.rb` — merges `code`, `code_stored`, `code_derived`, `gallery_name`, `notes`, `custom` into each cache entry (read-only extraction).
- `LibraryManager__Editor__.rb` — `UpdateLibraryData` via LoadEditSaveRemove → serializer write → `save_as` → remove temp definition; Live Component guard.

### Update 03 - Index Tab: Code, Gallery Name, Notes, Custom Fields
- `Tab__Index__.js` — Code (col 1) and Gallery Name (col 2) columns; default sort by `code`; drill-down edit panel for Notes + Custom Fields (add/delete); separate **Save Library Data** vs **Save Definition & Description** buttons.
- `DialogManager__.rb` — `na_componenteditortools_update_library_data` callback.
- `Styles__.css` — inline inputs, custom field rows, code badge.

### Update 04 - Gallery Display Overrides
- `Tab__Gallery__.js` — `gallery_name` overrides card title when set; code badge; search includes code/gallery_name.

### Cache Policy (confirmed)
- Cache key: `"#{path}::#{mtime}"` (mtime only).
- Extraction is read-only — reload cannot wipe bespoke DC data.
- Only explicit edits or file mtime change trigger re-extraction.
- **Refresh Library** purges cache and rebuilds.

---

# Na Noble3d Modelling Tools — Component Editor Tools
## Version 0.2.0 - 17-Jun-2026 - Component Library Manager (Phase 1)

### Update 01 - User Config and Settings Tab Extensions
- New `07__UserData/Na__ComponentEditorTools__UserConfig__.json` — `components_library_path`, `blocked_folder_names`, `blocked_file_names`.
- New `01__AppCore/Na__ComponentEditorTools__AppCore__UserConfig__.rb` — read/write user config with defaults (`00__Archive` blocked by default).
- Settings tab: library folder browse, **Refresh Library**, folder/file exclusion lists (disclosure panel).

### Update 02 - Library Manager Ruby Subsystem (`08__LibraryManager/`)
- **Scanner** — recursive `.skp` discovery honouring blocked folder/file lists; per-file meta (`path`, `file_name`, `relative_dir`, `mtime`, `cache_key`).
- **Extractor** — load definition temporarily, read name/description/attributes/thumbnail, remove definition; mtime-keyed extract cache + disk `LibraryCache__.json`.
- **Editor** — LoadEditSaveRemove pattern: load → yield edits → `save_as` → remove from model definitions.
- **PlacementTool** — click-to-place library component with drawing-axis placement.
- **Serializer** — (added in 0.3.0; see above).

### Update 03 - Gallery and Index Tabs
- `UiLayout__.html` — Gallery and Index tabs after Settings divider; tab action bar unchanged for selection-based tabs.
- `Tab__Gallery__.js` — searchable thumbnail grid, folder filter, click card → placement tool.
- `Tab__Index__.js` — sortable/filterable table, Edit drill-down panel, Insert action.
- `DialogManager__.rb` — scan/refresh/get_gallery/get_index/insert/rename/update_metadata callbacks; in-memory `@na_library_cache` + disk `LibraryLastResult__.json`; tab activate serves cache instead of full re-scan.

### Update 04 - Windows HtmlDialog and Path Fixes
- `UI.start_timer(0.0, false)` after `UI.select_directory` — fixes "Selecting library folder…" stuck status on Windows HtmlDialog.
- Cancel branch resets status to "Ready."
- Scanner path normalisation: `tr('\\', '/')` before `Dir.glob` and relative path logic — fixes subfolders not found on Windows.

### Update 05 - AppCore Wiring
- `AppCore__Main__.rb` — requires Scanner, Serializer, Extractor, Editor, PlacementTool in order.
- `PathResolver__.rb` — library cache, thumbnail cache, last-result JSON paths under `Sketchup.temp_dir/Na__ComponentEditorTools__LibraryCache/`.
- `UiBridge__.js` — gallery/index/config push handlers and Ruby callback wrappers.

---

# Module File Map (current)

#### AppCore (`01__AppCore/`)

| File | Responsibility |
|------|---------------|
| `...__Main__.rb` | Module constants, require chain, public `OpenDialog` / `ReloadPluginData` |
| `...__PathResolver__.rb` | UI, user data, library cache, DataLib SSOT paths |
| `...__UiBridge__.rb` | Ruby ↔ JS JSON execute helpers, callback registration |
| `...__UserConfig__.rb` | Persistent library path and exclusion lists |
| `...__Taxonomy__.rb` | Category → Type hierarchy load/save/CRUD/SSOT seed |
| `...__DialogManager__.rb` | HtmlDialog lifecycle, all JS callbacks, monitoring toggle, library cache push |
| `...__PluginReloader__.rb` | Hot reload all module `*.rb` files |
| `...__SelectionObserver__.rb` | Selection-changed → payload push (gated by monitoring state) |

#### Selection Inspector (`02__SelectionInspector/`)

| File | Responsibility |
|------|---------------|
| `...__Main__.rb` | Selection queries, payload builder (`include_geometry` / `captured`) |
| `...__GeometryAudit__.rb` | Recursive geometry stats traversal — faces, edges, materials, tags, solid |

#### Library Manager (`08__LibraryManager/`)

| File | Responsibility |
|------|---------------|
| `...__Scanner__.rb` | Discover `.skp` files, build entry meta + folder list |
| `...__Extractor__.rb` | Temp-load definitions, extract metadata/thumbnails, cache |
| `...__Serializer__.rb` | Read/write `Na__ComponentLibrary` attribute dictionary |
| `...__Editor__.rb` | On-disk edits: rename, metadata, library data, single-field updates |
| `...__PlacementTool__.rb` | Interactive library component insertion |

#### User Interface (`05__UserInterface/`)

| File | Responsibility |
|------|---------------|
| `...__UiLayout__.html` | Tab shell: Overview, Attributes, Thumbnail, Settings \| Gallery, Index |
| `...__Styles__.css` | Full dialog styling including index table, gallery grid, taxonomy manager, geometry panel, TrueVision badge |
| `...__UiBridge__.js` | Global state, incoming handlers, outgoing SketchUp callbacks, monitoring toggle |
| `...__TabRouter__.js` | Tab activation and Gallery/Index on-activate data fetch |
| `...__Tab__Overview__.js` | Selection-based instance/definition field editor + geometry panel renderer |
| `...__GeometryClipboard__.js` | Plain-text clipboard serialiser for geometry stats |
| `...__Tab__Attributes__.js` | Attribute dictionary read/write UI |
| `...__Tab__Thumbnail__.js` | Viewport render and thumbnail export |
| `...__Tab__Settings__.js` | Library path, exclusions, taxonomy CRUD, plugin reload |
| `...__Tab__Gallery__.js` | Thumbnail grid with search + category/type/folder filters + TrueVision badge overlay |
| `...__Tab__Index__.js` | Sortable table, double-click edit, category/type dropdowns, TrueVision Valid checkbox column + thumbnail badge |

#### User Data (`07__UserData/`)

| File | Purpose |
|------|---------|
| `Na__ComponentEditorTools__UserConfig__.json` | Library path, blocked folders/files |
| `Na__ComponentEditorTools__CategoryTaxonomy__.json` | Category → Type lists (auto-created on first run) |

# =============================================================================
# END OF FILE
# =============================================================================
