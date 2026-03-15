# Na Edge Util - Paint Deep Nested Edges - Development Log

**Main File:** [`Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb`](Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb)

---


## Version History

# ---------------------------------------------------------
### Na Edge Util - Version 1.0.2 - 15-Mar-2026
#### Advanced Tab, Line Thickness Tags, Startup Reporting & Bug Fixes

- **Advanced tab — Layout line thickness tag assignment**: New third tab "Advanced" in the dialog. Shows a mapping table of the 8 greyscale MTE edge colours to their corresponding `03__LineworkStyle__` Layout tags. Single "Apply Line Thickness Tags" button scans the entire model, assigns each greyscale-painted edge to the correct tag, and moves all other edges to Untagged (Layer0). Wrapped in a single SketchUp operation for clean undo. Status feedback shown in the dialog after execution.
- **New module: `Na__EdgeUtil__PaintDeepNestedEdges__ApplyLineThicknessTags__.rb`**: Loads Tags JSON from `Na__DataLib__CacheData` to extract the `03__LayoutDrawingLineworkTags__` section. Builds a lookup hash `{ MTE colour ID => tag name }` from the `EdgeColourID` field. Ensures all required `03__LineworkStyle__*` tags exist in the model before assignment (creates if missing). Reuses `na_collect_edges` from Main for deep-nested traversal.
- **Untagged cleanup**: Edges that don't match any greyscale MTE mapping (accent colours, non-MTE materials, unpainted edges) are moved to Untagged/Layer0 during the Apply operation, ensuring clean tag assignment across the entire model.
- **Tags JSON cross-reference**: The Advanced tab reads from both the EdgeMaterials JSON (for colour data) and the Tags JSON (for the `EdgeColourID` -> `TagName` mappings), providing belt-and-braces data integrity.
- **Startup data preload and status reporting**: Loader script now preloads `:edge_materials` and `:tags` data at SketchUp launch. `Na__DataLib__CacheData` tracks the source of each load (`:url`, `:cache`, `:local`, `:failed`) and prints a formatted startup report to the Ruby Console showing the status of each data file.
- **PaletteManager SyntaxError fix**: `Sketchup.read_default` internally uses `eval` which chokes on stored MTE key strings containing `__` after digits. Rescue handler upgraded from `rescue => e` to `rescue Exception => e` to catch `SyntaxError` (a `ScriptError` subclass, not `StandardError`). Corrupted stored palette is cleared from preferences and replaced with safe defaults. Added `na_clear_stored_palette` helper.
- **Module method call fix**: All internal method calls within `Na__ApplyLineThicknessTags` module now use explicit `self.` prefix to prevent Ruby interpreting them as constant lookups (same class of bug as the CacheData `Na__Cache__CacheDir` fix in v1.0.1).
- **Menu registration alignment**: Edge Painter now registers under `Extensions > Na__EdgeUtil` submenu (matching the GlbBuilder's `Extensions > Na__TrueVision3D` pattern) instead of the flat `Plugins` menu.

**Files Created:**
- `Na__EdgeUtil__PaintDeepNestedEdges__ApplyLineThicknessTags__.rb`

**Files Modified:**
- `Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb` (require_relative for new module, apply_line_tags callback, mapping table HTML builder, `{{MAPPING_TABLE_HTML}}` injection, `@na_mte_swatches` state variable, `na_flatten_mte_series` returns swatches array, `na_build_swatches_html` for Swatches tab, `na_build_mapping_table_html` for Advanced tab)
- `Na__EdgeUtil__PaintDeepNestedEdges__UiLayout__.html` (three-tab layout: Main, Swatches, Advanced; removed Refresh Selection button; added swatch grid, mapping table, Apply button, status area)
- `Na__EdgeUtil__PaintDeepNestedEdges__Styles__.css` (tab bar, tab content, swatch grid, swatch cell, Advanced tab mapping table, status text with success/error variants)
- `Na__EdgeUtil__PaintDeepNestedEdges__PaletteManager__.rb` (`rescue Exception` for SyntaxError, `na_clear_stored_palette`, `na_safe_default_palette_keys`)
- `Na__EdgeUtil__PaintDeepNestedEdges__HotkeyBinder__.rb` (Extensions > Na__EdgeUtil submenu)
- `Na__EdgeUtil__PaintDeepNestedEdges__EdgeConfigData__.json` (dialog size increased to 420x420)
- `Na__DataLib__CacheData__.rb` (`@na_last_source` tracking, `Na__Cache__LastSource`, `Na__Cache__PrintStartupReport`, `FILE_KEY_LABELS`)
- `Na__EdgeUtil__PaintDeepNestedEdges__Loader__.rb` (startup data preload, status report)
# ---------------------------------------------------------

# ---------------------------------------------------------
### Na Edge Util - Version 1.0.1 - 15-Mar-2026
#### Centralised MTE Data, Swatches Tab & DataLib Integration

- **MTE edge material naming convention**: Edge materials migrated from the old `00_XX__LineColour__Descriptor` format to the new `MTE{NNN}__{Category}__{Variant}` format, aligning with the MAT face-material convention. MTE = Material Type Edge. Series organised in hundreds: MTE000__ (reserved/default), MTE100__ (greyscale), MTE200__ (accent colours).
- **Centralised data loading via Na__DataLib**: Edge colour data now loaded from the centralised `Na__DataLib__CoreIndex__EdgeMaterials__.json` via the three-stage loading pipeline (URL -> temp cache -> local fallback) instead of the local `EdgeConfigData.json`. Plugin UI config (dialog size, title, menus) remains in the local JSON.
- **Three new DataLib helper scripts**: `Na__DataLib__UrlGenerator__.rb` (builds raw GitHub URLs from file keys), `Na__DataLib__CacheData__.rb` (HTTP fetch with 30-minute temp-dir cache), `Na__DataLib__LocalFallback__.rb` (local file read with one-time user notification).
- **Swatches tab**: New second tab showing a visual colour grid of all MTE colours. Each swatch displays the `SwatchName` field from the JSON (e.g. "Red" instead of "MTE201__LineColour__Red"). Clicking a swatch paints the selected edges immediately.
- **Refresh Selection button removed**: Redundant — selection observers already handle this.
- **Tabbed dialog UI**: Dialog restructured from single-page to tabbed layout (Main + Swatches). Tab switching is pure CSS + inline JS with no Ruby round-trips.
- **CacheData `self.` bug fix**: `Na__Cache__CacheFilePath` called `Na__Cache__CacheDir` without `self.`, causing Ruby to interpret it as a constant lookup. Fixed to `self.Na__Cache__CacheDir`.

**Files Created:**
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__UrlGenerator__.rb`
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__.rb`
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__LocalFallback__.rb`

**Files Modified:**
- `Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb` (require_relative DataLib, MTE data loading, series flattening, `na_colours` from MTE, `na_swatches`, `na_build_swatches_html`, `na_default_colour_key` / `na_dynamic_palette_default_key` / `na_dynamic_palette_slot_count` from `meta.uiDefaults`)
- `Na__EdgeUtil__PaintDeepNestedEdges__UiLayout__.html` (tabbed layout, Swatches tab, removed Refresh Selection)
- `Na__EdgeUtil__PaintDeepNestedEdges__Styles__.css` (tab bar, tab content, swatch grid styles)
- `Na__EdgeUtil__PaintDeepNestedEdges__EdgeConfigData__.json` (removed `colours`, `default_colour_key`, `dynamic_palette_*` keys — now sourced from MTE JSON)
# ---------------------------------------------------------

# ---------------------------------------------------------
### Na Edge Util - Version 1.0.0 - 2026
#### Initial Release

- **Deep nested edge painting**: Recursively traverses groups and component instances to collect all edges at any nesting depth. Applies a selected colour material to all collected edges in a single SketchUp operation.
- **Predefined architectural palette**: 13 linework colours loaded from external JSON config (`EdgeConfigData.json`). Greyscale series from absolute black through white, plus red, green, yellow, and purple accent colours.
- **HtmlDialog interface**: Dropdown colour selector, edge count display, Paint Edges button. Layout and styles loaded from external HTML/CSS files.
- **Dynamic quick palette**: 4-slot recently-used colour palette persisted in SketchUp preferences. Palette swatches update after each paint operation.
- **Modular architecture**: Separate files for Main orchestrator, PaletteManager, HotkeyBinder, UI layout, stylesheet, and config data.
- **SketchUp menu and shortcut registration**: Command registered under Plugins menu with tooltip and status bar text. Shortcut-discoverable command name for SketchUp Preferences > Shortcuts.
- **Colour conversion utilities**: Hex-to-RGB, HSL-to-RGB, RGB-to-hex converters for flexible colour specification in the config JSON.

**Files Created:**
- `Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb`
- `Na__EdgeUtil__PaintDeepNestedEdges__PaletteManager__.rb`
- `Na__EdgeUtil__PaintDeepNestedEdges__HotkeyBinder__.rb`
- `Na__EdgeUtil__PaintDeepNestedEdges__UiLayout__.html`
- `Na__EdgeUtil__PaintDeepNestedEdges__Styles__.css`
- `Na__EdgeUtil__PaintDeepNestedEdges__EdgeConfigData__.json`
- `Na__EdgeUtil__PaintDeepNestedEdges__Loader__.rb`
# ---------------------------------------------------------
