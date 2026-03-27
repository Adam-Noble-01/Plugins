# Na__ProfileTools__ProfilePathTracer - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================
## ProfileTools Version 0.1.4 - 26-Mar-2026

### Reload Completion Fix + Header Relocation

- Updated `Na__ProfileTools__ProfilePathTracer__DialogManager__.rb`:
  - Reload callback now captures a stable dialog reference before `load` cycle begins.
  - Added deterministic reload-completion path that closes the previous dialog, reopens the tool dialog, and posts final status to the reopened UI.
  - Added reload status payload normalization so failure states include clearer diagnostics and first issue context.

- Updated `Na__ProfileTools__ProfilePathTracer__UiLayout__.html`:
  - Moved **Reload Plugin** button from Controls section to header-level developer controls (aligned with Window Config Tool UX pattern).

- Updated `Na__ProfileTools__ProfilePathTracer__Ui__Controls__.js`:
  - Removed in-panel reload button from controls action row.

- Updated `Na__ProfileTools__ProfilePathTracer__Ui__Events__.js`:
  - Added one-time header event binding (`Na__Ui__AttachHeaderEvents`) to prevent duplicate click handlers on persistent header controls.

- Updated `Na__ProfileTools__ProfilePathTracer__UiLogic__.js`:
  - Centralized event handler map for reuse across render cycles.
  - Header reload binding now runs once on DOM ready while controls bindings remain rerender-safe.

- Updated `Na__ProfileTools__ProfilePathTracer__Styles__.css`:
  - Added header layout and header controls styling for relocated reload action.

- Updated `Na__ProfileTools__ProfilePathTracer__Architecture__.md`:
  - Corrected control placement documentation (header reload + user controls split).
  - Documented robust post-reload status flow.

# =======================================================================================
## ProfileTools Version 0.1.3 - 26-Mar-2026

### UI Cleanup + True Plugin Hot Reload

- Added `Na__ProfileTools__ProfilePathTracer__PluginReloader__.rb`:
  - New dedicated reload module for development-time hot reload.
  - Reloads all Ruby modules in `Na__ProfileTools__ProfilePathTracer__Modules__` via `load`.
  - Validates expected JS UI assets and returns structured reload status.
  - Triggers `UI.refresh_inspectors` when available.

- Updated `Na__ProfileTools__ProfilePathTracer__Main__.rb`:
  - Added `require_relative` for `PluginReloader__`.

- Updated `Na__ProfileTools__ProfilePathTracer__DialogManager__.rb`:
  - Added `na_profilepathtracer_reload_plugin` callback.
  - Added `Na__Dialog__HandleReloadCompletion` to close/reopen dialog after reload so JS/CSS/HTML refresh without SketchUp restart.
  - Removed redundant `na_profilepathtracer_activate_preview_tool` callback (duplicate of generate behavior).

- Updated UI controls and event wiring:
  - `Na__ProfileTools__ProfilePathTracer__Ui__Controls__.js`:
    - Replaced **Reload Bootstrap** with **Reload Plugin**.
    - Removed **Pick Path** button.
    - Removed **Run Headless** button.
  - `Na__ProfileTools__ProfilePathTracer__Ui__Events__.js`:
    - Removed pick-path/headless/bootstrap button hooks.
    - Added reload-plugin hook.
  - `Na__ProfileTools__ProfilePathTracer__UiLogic__.js`:
    - Removed duplicate pick-path action path.
    - Removed UI-triggered headless action.
    - Added reload-plugin action binding.
  - `Na__ProfileTools__ProfilePathTracer__UiEventToRubyApiBridge__.js`:
    - Added `Na__ProfilePathTracer__Bridge__ReloadPlugin`.
    - Removed obsolete UI bridge methods for pick-path activation and run-headless.

- Updated `Na__ProfileTools__ProfilePathTracer__PublicApi__.rb`:
  - Added `Na__PublicApi__ReloadPluginFiles` for external/scriptable reload entrypoint.

- Updated architecture documentation:
  - Added `PluginReloader__` module and developer hot reload flow.
  - Documented simplified user control intent (Generate + Reload Plugin + Create New Profile, with headless API-only).

# =======================================================================================
## ProfileTools Version 0.1.2 - 24-Mar-2026

### Profile Flip Toggles (Center + World Origin)

- Updated `Na__ProfileTools__ProfilePathTracer__Config__.json`:
  - Replaced ambiguous flip keys with explicit toggles:
    - `flipXCenter`
    - `flipYCenter`
    - `flipXWorld`
    - `flipYWorld`
  - Added labels/descriptions for all four toggles.

- Added `Na__ProfileTools__ProfilePathTracer__MirrorProfile__.rb`:
  - Implemented deterministic mirror pipeline for profile local points.
  - Supports center-axis mirrors (profile bounds center) and world-origin mirrors (`X=0` / `Y=0`).
  - Exposes one public apply method reused across preview/build flows.

- Updated `Na__ProfileTools__ProfilePathTracer__Main__.rb`:
  - Added `require_relative` for `MirrorProfile__`.
  - Added config JSON load helpers and toggle default extraction helpers.
  - Default run config now includes config-driven `toggleStates`.

- Updated `Na__ProfileTools__ProfilePathTracer__DialogManager__.rb`:
  - Bootstrap payload now includes `toggleDefinitions` and `toggleStates`.
  - Generate flow now normalizes/passes toggle states into `PathSelectionTool`.

- Updated generation pipeline:
  - `Na__ProfileTools__ProfilePathTracer__PathSelectionTool__.rb` now stores/passes `toggleStates` for ghost preview and click-to-build.
  - `Na__ProfileTools__ProfilePathTracer__ProfilePlacementEngine__.rb` now accepts/passes `toggle_states`.
  - `Na__ProfileTools__ProfilePathTracer__HeadlessRunner__.rb` now forwards `toggleStates`.
  - `Na__ProfileTools__ProfilePathTracer__GeometryBuilders__.rb` now applies mirror transforms before path frame/rotation for both polyline and rich-geometry branches.

- Updated UI + preview parity:
  - `Na__ProfileTools__ProfilePathTracer__UiLogic__.js` now tracks toggle defs/states, includes toggles in generate payload, and re-renders preview on toggle change.
  - `Na__ProfileTools__ProfilePathTracer__Ui__Controls__.js` now renders toggle controls dynamically from config metadata.
  - `Na__ProfileTools__ProfilePathTracer__Ui__Events__.js` now binds toggle change events.
  - `Na__ProfileTools__ProfilePathTracer__UiEventToRubyApiBridge__.js` bootstrap fallback now includes toggle fields.
  - `Na__ProfileTools__ProfilePathTracer__Viewport__SvgGenerator__.js` now applies the same four mirror transforms, matching Ruby generation behavior.

- Updated `Na__ProfileTools__ProfilePathTracer__Architecture__.md`:
  - Added `MirrorProfile__` module and toggle-aware runtime flow.

# =======================================================================================
## ProfileTools Version 0.1.1 - 24-Mar-2026

### Create New Profile / Rich JSON Export Feature

- Added `Na__ProfileTools__ProfilePathTracer__ProfileExporter__.rb`:
  - Validates current SketchUp selection (faces, edges, loose geometry).
  - Collects geometry relative to model origin in millimetres.
  - Builds rich JSON payload with `meta`, `vertices`, `edges`, `faces` sections.
  - Prompts user with OS save dialog (default: `01__ProfileDataFiles/`).
  - Writes formatted JSON matching the standardised profile data schema.

- Modified `Na__ProfileTools__ProfilePathTracer__ProfileLibrary__.rb`:
  - Added `NA_PROFILE_DATA_DIR` constant pointing to `01__ProfileDataFiles/`.
  - Added `Na__ProfileLibrary__ScanDataFiles` to recursively glob `*.json` from data dir.
  - Added `Na__ProfileLibrary__ParseDataFile` to convert rich JSON files to internal profile format with `profileData.type = "rich_geometry"`.
  - `Na__ProfileLibrary__Load` now merges library profiles with scanned data-file profiles.

- Modified `Na__ProfileTools__ProfilePathTracer__GeometryBuilders__.rb`:
  - Added `Na__Geometry__ProfileType` for format detection.
  - Added `Na__Geometry__BuildLocalPointsFromRichData` to extract face outer-loop vertices from rich data.
  - Added `Na__Geometry__BuildRichProfileAlongPath` for full rich geometry `followme` build with inner loop (hole) support.
  - Added `Na__Geometry__RichDataPreviewPoints` for 2D SVG preview extraction.
  - `BuildProfileAlongPath` and `BuildLocalProfilePoints` now branch on `profileData.type`.

- Modified `Na__ProfileTools__ProfilePathTracer__DialogManager__.rb`:
  - Added `na_profilepathtracer_validate_for_export` callback.
  - Added `na_profilepathtracer_save_profile` callback.
  - Added `Na__Dialog__HandleSaveProfileRequest` which runs export, then reloads bootstrap on success.

- Modified UI layer:
  - Added "Create New Profile" button (purple) to controls panel.
  - Added hidden `#naCreateProfilePanel` section with form root.
  - Added meta form renderer: Profile Name, Description, Keywords, Profile ID, auto-filled Timestamp and Units.
  - Added "Save Profile Data File" (green) and "Cancel" buttons on form.
  - Added export validation and save profile bridge calls.
  - Updated `Viewport__SvgGenerator` to render `rich_geometry` profiles in 2D SVG preview.
  - Added CSS styles for create profile form, validation summary, success/secondary buttons.

- Updated `Na__ProfileTools__ProfilePathTracer__Main__.rb`:
  - Added `require_relative` for `ProfileExporter__`.

- Updated Architecture and DEVLOG documentation.

# =======================================================================================
## ProfileTools Version 0.1.0 - 18-Mar-2026

### First Stable Foundation Release

- Confirmed first stable baseline release after runtime testing in SketchUp.
- Core/minimal feature set is working end-to-end:
  - Dialog opens reliably.
  - Bootstrap flow responds and basic UI controls are operational.
  - Generate / preview tool flow runs without the earlier constant-resolution startup/runtime blockers.
- This remains an intentionally basic implementation and still needs substantial iteration, refinement, and feature depth.
- The project now has a strong modular foundation for the next development phases.
- Team note: great work on getting this to a stable starting point.

# =======================================================================================
## ProfileToolsVersion 0.0.4 - 18-Mar-2026

### Full Plugin Dispatch + Bootstrap Hardening

- Audited all plugin scripts and hardened Ruby same-scope internal `Na__...` calls to explicit dispatch (`self.Na__...`) in:
  - `Na__ProfileTools__ProfilePathTracer__AssetResolver__.rb`
  - `Na__ProfileTools__ProfilePathTracer__DependencyBootstrap__.rb`
  - `Na__ProfileTools__ProfilePathTracer__DialogManager__.rb`
  - `Na__ProfileTools__ProfilePathTracer__GeometryBuilders__.rb`
  - `Na__ProfileTools__ProfilePathTracer__KeyboardHandlers__.rb`
  - `Na__ProfileTools__ProfilePathTracer__PathAnalysis__.rb`
  - `Na__ProfileTools__ProfilePathTracer__PathSelectionTool__.rb`
  - `Na__ProfileTools__ProfilePathTracer__ProfilePlacementEngine__.rb`
- Added bootstrap callback rescue in `DialogManager` and returned an explicit bootstrap error payload to UI when Ruby bootstrap fails.
- Hardened JS bridge bootstrap handling:
  - Added bridge-availability retry loop before fallback response.
  - Added UI-visible bridge status updates while retrying.
- Updated `UiLogic` bootstrap receive handling to show explicit failure/no-profile status instead of always reporting `Bootstrap loaded.`.

# =======================================================================================
## ProfileTools Version 0.0.3 - 18-Mar-2026

### Generate Runtime Hotfix

- Fixed `Generate failed: uninitialized constant ... Na__ProfileLibrary__Load`.
- Updated `ProfileLibrary` internal calls to use explicit `self.` method dispatch (e.g. `self.Na__ProfileLibrary__Load`) so Ruby does not resolve them as constants.

## Version 0.2.1 - 18-Mar-2026

### Startup Crash Hotfix

- Fixed dialog startup failure caused by Ruby constant lookup on a bare uppercase token.
- Updated `DialogManager` to call `self.Na__Dialog__Options` when constructing `UI::HtmlDialog`, ensuring method dispatch instead of constant resolution.

# =======================================================================================
## ProfileTools Version 0.0.2 - 18-Mar-2026

### Reuse-First UI + Preview System Implementation

- Adapted the **Window Config Tool** architecture pattern for this plugin:
  - Bootstrap payload now includes enabled profile options and profile map from `ProfileLibrary__.json`.
  - New 2D SVG renderer module added:
    - `Na__ProfileTools__ProfilePathTracer__Viewport__SvgGenerator__.js`
  - UI now renders selected profile as 2D SVG in dialog viewport.
  - Added Generate action flow in UI + JS bridge + Ruby dialog callbacks.

- Adapted the **InsertPrimatives** preview-tool pattern:
  - Added keyboard mixin with debounce-safe TAB rotation cycle:
    - `Na__ProfileTools__ProfilePathTracer__KeyboardHandlers__.rb`
  - Added viewport preview graphics helper:
    - `Na__ProfileTools__ProfilePathTracer__3dPreviewGraphics__.rb`
  - Rebuilt `PathSelectionTool` for:
    - red crosshair
    - path visualization
    - nearest-vertex targeting
    - TAB rotation
    - click-to-place start point

- Implemented profile/path-specific generation logic:
  - `PathAnalysis` now enforces strict non-branching path validation.
  - Supports:
    - single open chain
    - closed loop
  - Rejects branch conditions and disconnected sets.
  - Added path reordering by clicked start vertex:
    - open path: start must be one of endpoints
    - closed loop: rotated sequence from selected start vertex
  - `ProfilePlacementEngine` now validates selection for preview and commits generation.
  - `GeometryBuilders` now:
    - builds local profile points from JSON
    - computes placement frame from path tangent
    - applies TAB rotation
    - generates geometry along path in group operation

# =======================================================================================
## ProfileTools Version 0.0.1 - 18-Mar-2026

### Scaffold Initialization

- Created root loader:
  - `Na__ProfileTools__ProfilePathTracer__Loader__.rb`
- Created modular Ruby architecture shells:
  - Main orchestrator, public API, dependency bootstrap, asset resolver, dialog manager, path/profile engine stubs, observers, debug tools.
- Created HtmlDialog shell:
  - Layout, styles, modular UI files, JS->Ruby bridge placeholders.
- Added placeholder config/data JSON files:
  - `Na__ProfileTools__ProfilePathTracer__Config__.json`
  - `Na__ProfileTools__ProfilePathTracer__ProfileLibrary__.json`
- Added docs:
  - README, DEVLOG, Architecture.
- Added image-assets placeholder folder content:
  - `02__PluginImageAssets/README__AssetPlaceholders__.md`

### Dependency Alignment

- Added DataLib integration point via:
  - `Na__DataLib__CacheData.Na__Cache__LoadData(:tags)`
  - `Na__DataLib__CacheData.Na__Cache__LoadData(:materials)`
- Added shared asset resolution pathing to:
  - `../Na__Common__PluginDependencies`

### Validation Checklist (Scaffold Stage)

- [x] Loader points to modules main file.
- [x] Main orchestrator requires module shells.
- [x] HtmlDialog file references existing JS/CSS scaffold.
- [x] DataLib bootstrap require path included.
- [x] Shared asset resolver path included.
- [x] Implement real path picking and ordered segment solving.
- [x] Implement profile orientation rules and rotation step handling.
- [x] Implement initial geometry generation along validated path.
- [ ] Add runtime tests inside SketchUp with real model selections.
