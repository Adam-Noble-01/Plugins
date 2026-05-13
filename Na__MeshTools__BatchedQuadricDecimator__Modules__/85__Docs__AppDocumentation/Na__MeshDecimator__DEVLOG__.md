# Na Batched Quadric Decimator - DEVLOG
# =============================================================================


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
