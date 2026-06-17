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
| `...__DialogManager__.rb` | HtmlDialog lifecycle, all JS callbacks, library cache push |
| `...__PluginReloader__.rb` | Hot reload all module `*.rb` files |
| `...__SelectionObserver__.rb` | Selection-changed → payload push |

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
| `...__Styles__.css` | Full dialog styling including index table, gallery grid, taxonomy manager |
| `...__UiBridge__.js` | Global state, incoming handlers, outgoing SketchUp callbacks |
| `...__TabRouter__.js` | Tab activation and Gallery/Index on-activate data fetch |
| `...__Tab__Overview__.js` | Selection-based instance/definition field editor |
| `...__Tab__Attributes__.js` | Attribute dictionary read/write UI |
| `...__Tab__Thumbnail__.js` | Viewport render and thumbnail export |
| `...__Tab__Settings__.js` | Library path, exclusions, taxonomy CRUD, plugin reload |
| `...__Tab__Gallery__.js` | Thumbnail grid with search + category/type/folder filters |
| `...__Tab__Index__.js` | Sortable table, double-click edit, category/type dropdowns |

#### User Data (`07__UserData/`)

| File | Purpose |
|------|---------|
| `Na__ComponentEditorTools__UserConfig__.json` | Library path, blocked folders/files |
| `Na__ComponentEditorTools__CategoryTaxonomy__.json` | Category → Type lists (auto-created on first run) |

# =============================================================================
# END OF FILE
# =============================================================================
