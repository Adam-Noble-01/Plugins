# Na__ProfileTools__ProfilePathTracer - DEVLOG
# =======================================================================================
## Version History

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
