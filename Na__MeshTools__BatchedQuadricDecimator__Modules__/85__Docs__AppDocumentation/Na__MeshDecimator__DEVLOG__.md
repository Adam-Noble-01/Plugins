# Na Batched Quadric Decimator - DEVLOG
# =============================================================================


# =============================================================================
## Batched Quadric Decimator | V0.0.7 - 13-May-2026 - Native engine promoted and timing stats

### Context
Native C++ decimation tested dramatically faster than the Ruby prototype. Promoted
the native engine to the primary action while keeping the Ruby path available for
comparison and regression checks.

### Changes
- `Na__MeshDecimator__UiLayout__.html`: blue primary button now runs native C++
  decimation; grey secondary button now runs `Run Legacy Ruby`.
- `Na__MeshDecimator__AppCore__UiShell__.js`: updated status/error text and
  loading-state button references for the native-primary button layout.
- Ruby and native orchestrators now add `:elapsed_seconds` to each report row.
- `Na__MeshDecimator__Statistics__UiLogic__.js`: added `Time` column immediately
  after `Engine`, formatted as `mm:ss` with sub-second runs shown as `<00:01`.
- New documentation:
  `85__Docs__AppDocumentation/Na__MeshDecimator__NativeEngine__Explanation__.md`.

---

# =============================================================================
## Batched Quadric Decimator | V0.0.6 - 13-May-2026 - Native C++ engine path

### Context
Added a separated Windows SketchUp 2026 native-engine path so the current Ruby
prototype can remain intact while the heavier QEM simplification work is tested
through a Ruby C++ extension.

### Changes

#### Native source and build scaffold
- New `02__Src__NativeEngine/` folder with C++ QEM core, Ruby extension entry
  point, CMake build file, Windows build script, output bin folder, and build
  output folder.
- New `01__ExternalDependencies__VersionLocked/` folder containing the pinned
  SketchUp Ruby C extension examples repo at commit
  `e75c6bf81c96ee25df46b33b65d8e705825af3f0`.
- `90__BuildTools__Manifest/` stores the native dependency manifest and the
  Visual Studio Build Tools bootstrapper used for the MSVC install attempt.

#### Ruby integration
- New `08__NativeEngine/Na__MeshDecimator__NativeEngine__Bridge__.rb` loads the
  optional compiled `.so` and fails closed with a clear load error.
- New `08__NativeEngine/Na__MeshDecimator__NativeEngine__EntitiesBuilderWriter__.rb`
  writes native results back through SketchUp's Ruby API using
  `Sketchup::Entities#build` where available.
- New `05__Orchestrator/Na__MeshDecimator__Orchestrator__RunNativeDecimation__.rb`
  mirrors the Ruby pipeline but calls the native simplifier and labels report
  rows as `Native C++`.
- Existing Ruby orchestrator now labels normal report rows as `Ruby`.

#### UI and statistics
- Added `Run Advanced Native` beside the existing `Run Decimation` button.
- Added `na_run_native_decimation` Ruby callback and matching JS bridge call.
- Statistics table now includes an `Engine` column so Ruby and Native C++ runs
  can be compared side by side.

#### Build status
- CMake, Ninja, Git, MSVC `cl.exe`, and the pinned Ruby C extension headers/libs
  are available.
- Build script now uses a temporary `X:` drive alias to avoid Windows/MSVC path
  length failures when compiling nested Ruby headers from the SketchUp Plugins
  folder.
- Added local Ruby header shim `02__Src__NativeEngine/01__CppSource/ruby/internal/config.h`
  because the pinned SketchUp Ruby 3.2 Windows headers expose `ruby/config.h`
  while `ruby/ruby.h` asks for `ruby/internal/config.h`.
- Native binary built successfully at
  `02__Src__NativeEngine/04__Bin__WindowsSketchUp2026/Na__MeshDecimator__NativeQemEngine.so`.
- Verified exported Ruby init symbol:
  `Init_Na__MeshDecimator__NativeQemEngine`.

---

# =============================================================================
## Batched Quadric Decimator | V0.0.5 - 13-May-2026 - White cards on all tabs, new plugin icon

### Context
Applied consistent white card treatment to all four tabs so every content
section sits on a white surface against the light grey body background —
matching the Decimation tab pattern introduced in V0.0.4. Replaced the
placeholder toolbar icon with the new branded geometric-Q icon.

### Changes

#### White cards — `Na__MeshDecimator__Styles__Combined__.css`
- `.na-options-panel` gained `display: flex; flex-direction: column; gap: 8px`
  and each section in the Decimation tab was wrapped in `<div class="na-card">`.
- `.na-card` component added: `background: #fff; border: 1px solid var(--na-border-color);
  border-radius: 6px; padding: 10px 14px; flex-shrink: 0`.
- `.na-card .na-options-panel__section-title` — removes redundant inner border-bottom.

#### About tab — CSS + HTML
- `.na-about-panel` converted to flex column with `gap: 8px`.
- `.na-about-section` styled as a card directly in CSS — all three content
  sections card automatically with no per-section HTML changes.
- `.na-about-section__title` border-bottom removed (card edge is boundary).
- Intro heading + version line wrapped in `<div class="na-card na-about-intro-card">`
  in `Na__MeshDecimator__UiLayout__.html`.

#### Settings tab — CSS only
- `.na-settings-body` converted to flex column with `gap: 8px; padding: 10px 14px`.
- `.na-settings-section` styled as a card; removed `margin-bottom`, `border-bottom`,
  and the `.na-settings-section--about` `border-top` override.

#### Statistics tab — JS + CSS
- `Na__MeshDecimator__Statistics__UiLogic__.js`: table wrapper changed from
  `na-statistics-table-wrapper` to `na-card na-statistics-card`.
- `.na-statistics-card` added: `margin: 8px 10px; overflow: auto; flex: 1; padding: 0`.

#### Toolbar icon — `Na__MeshDecimator__AppUtils__AssetResolver__.rb`
- `NA_MAIN_ICON_FILENAME` updated to `'PluginIcon__QuadraticDecimator__248px__.png'`
  — the new branded geometric-Q icon in `01__AppAssets__MeshDecimator\`.

---

# =============================================================================
## Batched Quadric Decimator | V0.0.4 - 13-May-2026 - Light theme, Statistics tab, reload fix, title rebrand

### Context
Rebrand to "Batched Quadric Decimator" (dropped "Na " prefix). Migrated the dark
UI to the Vale Design Suite light theme matching ElementAssemblyStudioPro. Fixed
the hot-reload bug where module-level instance variables were reset by `load`.
Moved decimation results out of the inline panel into a persistent Statistics
accumulator tab that collates all runs so settings can be compared as you work.

### Changes

#### Title — all files
- `Na__MeshDecimator__AppConfig__Main.json`: `"title": "Batched Quadric Decimator"`
- `Na__MeshDecimator__UiLayout__.html`: `<title>`, brand header span, About `<h2>`, version v0.0.4
- `Na__MeshDecimator__AppCore__DialogManager__.rb`: fallback HTML + config default strings updated
- `Na__MeshDecimator__Settings__UiLogic__.js`: meta info line, NA_ABOUT.lines[0], version v0.0.4

#### Light theme — `Na__MeshDecimator__Styles__Combined__.css`
- Complete rewrite to Vale Design Suite light theme.
- Introduced `:root` CSS variables (`--na-bg-*`, `--na-text-*`, `--na-accent-*`,
  `--na-border-*`) matching `Na__AssemblyStudio__Styles__Combined__.css`.
- Body: `#f0f0f0` bg / `#1e1e1e` text. Tab strip `#f5f5f5`. All panels light.
- Removed legacy inline `.na-results-panel` region; shared table styles in Region 11.
- Added `.na-btn--danger` for Purge Stats. Added Region 14 Statistics Tab layout.

#### New — `Na__MeshDecimator__UiFeature__Styles__TabStrip__.css`
- Light tab strip override CSS, imported last in `Na__MeshDecimator__CoreUi__Styles__Index__.css`.

#### Reload bug fix — `Na__MeshDecimator__AppCore__DialogManager__.rb`
- Root cause: `load file` re-executes the module body, resetting `@na_dialog` etc. to nil.
- Fix: save `saved_dialog`, `saved_html_path`, `saved_modules_root` to locals
  before the reload loop; use saved locals for close/reopen.
- Added `UI.refresh_inspectors` call after reload.

#### New — `02__Src__AppModules/07__System__Statistics/Na__MeshDecimator__Statistics__UiLogic__.js`
- Exports `window.Na_StatisticsUI` (TabRouter `Na_<TabId>UI` convention).
- `na_rows` accumulator + `na_run_counter` persist across mounts/unmounts.
- `na_add_run_result(report_array)` — appends rows from one run, re-renders.
- `na_purge()` — clears accumulator; exposed as `Na__MeshDecimator__Statistics__Purge()`.
- Table: Run | Group Name | Input Tri | Input Faces | Input Edges |
  Output Tri | Output Faces | Output Edges | Reduced % | Status (10 columns).

#### `Na__MeshDecimator__AppCore__UiShell__.js`
- `OnComplete` routes results to `Na_StatisticsUI.na_add_run_result(report)`.
- Removed: `HideResults`, `RenderResultsTable`, `RenderError`, `na_escape_html`.
- Removed `HideResults()` call from Run function.

#### `Na__MeshDecimator__UiLayout__.html`
- Tab order: Decimation | Statistics | About | Settings (4 tabs).
- Removed inline `na-results-panel` from Decimation tab.
- Added `#na-tab-statistics` panel with `#na-statistics-body`.
- Added Statistics script include before TabRouter.

---

# =============================================================================
## Na Batched Quadric Decimator | V0.0.3 - 13-May-2026 - Loader icon resolution hardening

### Context
Manual update to the root loader after initial load testing. The icon resolution
block was fragile — an unresolved `Na__AssetResolver` reference would surface as
a noisy warning in the Ruby Console. Updated to check for a future
`Na__AppUtils::Na__AssetResolver` utility module first, fall back gracefully to
the direct file path check, and wrap the entire block in `begin/rescue` so any
icon error never prevents the UI::Command from being registered.

### Changes

#### `Na__MeshTools__BatchedQuadricDecimator__Loader__.rb`
- Icon resolution block wrapped in `begin … rescue StandardError` — prevents
  icon errors from interrupting toolbar/menu registration.
- Added forward-compatible `Na__MeshDecimator::Na__AppUtils::Na__AssetResolver`
  check: if that module is loaded it is asked for the canonical icon path before
  the direct `File.exist?(icon_path)` fallback is tried.
- Removed `puts` on icon-not-found: the rescue clause now prints a warning only
  when an actual exception is raised.

---

# =============================================================================
## Na Batched Quadric Decimator | V0.0.2 - 13-May-2026 - Tab system, improved statistics, Settings reload

### Context
Added a 3-tab HtmlDialog layout (Decimation / About / Settings) mirroring the
Na__ElementAssemblyStudioPro plugin architecture. Improved the results table to
show group name and raw face/edge counts alongside the internal triangle counts.
Added Settings tab with hot-reload support so Ruby scripts can be reloaded
without restarting SketchUp.

### Changes

#### `Na__MeshDecimator__UiLayout__.html`
- Restructured from single-panel to 3-tab layout.
- Tab strip with Decimation, About, and Settings buttons.
- Decimation tab: existing options panel + action bar + new richer results table.
- About tab: static plugin description, usage guide, and tips.
- Settings tab: empty body container populated dynamically by `Na_SettingsUI`.
- Script includes updated: TabRouter loaded after tab-specific modules.

#### `Na__MeshDecimator__AppCore__TabRouter__.js` (new)
- Adapted from `Na__AssemblyStudio__AppCore__TabRouter__.js`.
- Discovers tabs from `data-na-tab-id` attributes; no hard-coded tab list.
- Dispatches `na_mount` / `na_unmount` lifecycle hooks to the matching global module.
- Resolves `Na_<TabId>UI` convention: `Na_DecimationUI`, `Na_AboutUI`, `Na_SettingsUI`.

#### `Na__MeshDecimator__AppCore__UiShell__.js`
- Results table updated: Group Name | Input Tri | Input Faces | Input Edges |
  Output Tri | Output Faces | Output Edges | Reduced % | Status.
- Exposes `Na_DecimationUI` tab module (`na_mount` triggers group count refresh,
  `na_unmount` is a no-op).

#### `Na__MeshDecimator__Settings__UiLogic__.js` (new)
- Mirrors `Na__AssemblyStudio__AppUtils__SettingsTab__UiLogic__.js` pattern.
- Builds Settings tab body dynamically from descriptor tables.
- Plugin Maintenance section: Reload Scripts button.
- About section: version, author, description.

#### `Na__MeshDecimator__Settings__Bridge__.js` (new)
- Window globals: `na_settingsReloadScripts()` → calls `sketchup.na_reload_scripts`.

#### `Na__MeshDecimator__AppCore__DialogManager__.rb`
- Added `na_reload_scripts` action callback.
- `na_handle_reload_scripts`: globs and `load`s all `.rb` files under
  `02__Src__AppModules/**/*.rb`, silences constant-redefinition warnings,
  then closes and reopens the dialog.

#### `Na__MeshDecimator__Orchestrator__RunDecimation__.rb`
- `na_extract_meshes` now captures group name, input face count, input edge
  count before extraction.
- `na_process_one_group` captures output face/edge counts from live group
  entities after `MeshWriter` completes.
- Report hash extended: `:group_name`, `:input_faces`, `:input_edges`,
  `:output_faces`, `:output_edges`.

#### `Na__MeshDecimator__Styles__Combined__.css`
- Added tab strip, tab bar, tab button, tab-active, and na-hidden rules.
- Added na-tab-panel (full-height scrollable) and na-settings-* rules.

---

# =============================================================================
## Na Batched Quadric Decimator | V0.0.1 - 13-May-2026 - Initial Release

### Context
First structured release of Na Batched Quadric Decimator as a full SketchUp
plugin. The original script was a single-file Ruby console paste that collected
user inputs via `UI.inputbox`, ran the full decimation pipeline in one flat
module, and displayed results with `UI.messagebox`.

This release refactors the entire script into a Noble Architecture modular
plugin following the same conventions as Na__ElementAssemblyStudioPro.

### Changes

#### Architecture
- Root loader `Na__MeshTools__BatchedQuadricDecimator__Loader__.rb` registers
  Extensions menu entry, toolbar button, and calls `Na__MeshDecimator.na_init`.
- 15 module files in numbered source folders under `Na__MeshTools__BatchedQuadricDecimator__Modules__`.
- `UI::HtmlDialog` with HTML/CSS/JS front end replaces `UI.inputbox` and
  `UI.messagebox`.
- All default option values sourced from `Na__MeshDecimator__AppConfig__Main.json`
  (single source of truth).

#### New Module Files
- `02__Geometry/Na__MeshDecimator__Geometry__VectorMath__.rb` — SubtractPoints,
  CrossProduct, DotProduct, VectorLength, TriangleAreaTwice.
- `02__Geometry/Na__MeshDecimator__Geometry__QuadricMath__.rb` — QEM matrix ops,
  error evaluation, Cramers-rule optimal point solver.
- `04__GroupSelection/Na__MeshDecimator__GroupSelection__Collector__.rb` —
  selection/context group collection, nested traversal, ParseBoolean.
- `03__Decimation/Na__MeshDecimator__Decimation__MeshExtractor__.rb` —
  triangulated mesh extraction with vertex welding.
- `03__Decimation/Na__MeshDecimator__Decimation__MeshCompactor__.rb` —
  compact strip + normal-flip inversion guard.
- `03__Decimation/Na__MeshDecimator__Decimation__MeshSimplifier__.rb` —
  multi-pass QEM collapse loop.
- `03__Decimation/Na__MeshDecimator__Decimation__MeshWriter__.rb` —
  writes simplified triangles back into the group.
- `05__Orchestrator/Na__MeshDecimator__Orchestrator__RunDecimation__.rb` —
  full pipeline entry point (collect → extract → simplify → write → report).
- `01__AppCore/Na__MeshDecimator__AppCore__UiBridge__.rb` — Ruby → JS helpers.
- `01__AppCore/Na__MeshDecimator__AppCore__DialogManager__.rb` — HtmlDialog
  lifecycle and callback wiring.
- `01__AppCore/Na__MeshDecimator__AppCore__Main__.rb` — require chain + na_init.
- `01__AppCore/Na__MeshDecimator__AppCore__UiShell__.js` — form reading, Run,
  OnComplete, OnError, SetLoading, status bar.
- `03__Style__AppStylesheets/Na__MeshDecimator__Styles__Combined__.css` —
  dark SketchUp-compatible theme.
- `Na__MeshDecimator__UiLayout__.html` — single-panel HTML dialogue.
- `04__Data__AppData/Na__MeshDecimator__AppConfig__Main.json` — default options.

---
