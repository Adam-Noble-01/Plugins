# Na__ArrayBuilderTools - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================
## Array Builder Version 0.0.2 - 02-Apr-2026

### Branding + Toolbar Icon (Profile Path Tracer parity)

- Added `Na__ArrayBuilder__AssetResolver__.rb`:
  - Resolves the main toolbar icon using the same rules as Profile Path Tracer: optional local override in `02__PluginImageAssets/Na__ArrayBuilder__Icon__.png`, otherwise `Na__Common__PluginDependencies/IMG02__ICN__NaCompanyIcon.png`.

- Updated `Na__ArrayBuilderTools__Loader.rb`:
  - Command `small_icon` / `large_icon` assigned from `Na__ArrayBuilder__AssetResolver.Na__Assets__MainIconPath` when the file exists.

- Updated `Na__ArrayBuilder__Main__.rb`:
  - Declared `NA_PLUGIN_VERSION` as `0.0.2`.
  - Added `require_relative` for `Na__ArrayBuilder__AssetResolver__`.

- Updated `Na__ArrayBuilder__UiLayout__.html`:
  - Header shows the shared NA company icon beside the title (same asset as Profile Path Tracer toolbar branding).

- Updated `Na__ArrayBuilder__UiStyle__.css`:
  - Added `.na-header-brand` and `.na-header-icon` for icon + title layout.

- Updated module headers (`Na__ArrayBuilder__DialogManager__`, `Na__ArrayBuilder__GeometryBuilder__`, `Na__ArrayBuilder__PathTool__`) to document version `0.0.2`.

# =======================================================================================
## Array Builder Version 0.0.1 - Initial

### Core workflow

- HtmlDialog configuration UI (dentil / dog-tooth presets, dimensions, normalise spacing).
- Path placement tool with preview and geometry build pipeline.
- Plugins menu + **NA Array Tools** toolbar entry.

# =======================================================================================
# END OF DEVLOG
# =======================================================================================
