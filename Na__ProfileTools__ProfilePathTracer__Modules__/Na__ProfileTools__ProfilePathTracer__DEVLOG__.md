# Na__ProfileTools__ProfilePathTracer - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================
## ProfileTools Version 0.3.5 - 11-May-2026

### Deterministic World-Up Local Frame For Profile Preview And Export

- Root cause of the rotated balustrade preview (and identically-rotated JSON coordinates) was that the local frame's horizontal axis was seeded from the **direction of the first edge of the face's outer loop**. SketchUp's loop iteration order is not deterministic from the user's perspective, so complex profiles whose first loop edge was diagonal or curved were rotated by that arbitrary angle.
- Reworked `Na__Exporter__BuildLocalFrame` in `Na__ProfileTools__ProfilePathTracer__ProfileExporter__.rb` to derive the frame from `face.normal` + a world reference vector, independent of edge order:
  - World "up" reference is `Z_AXIS` by default, falling back to `Y_AXIS` for plan-flat faces (where the normal is parallel to `Z_AXIS`).
  - Local `axis_z` (profile-vertical) is that reference projected onto the face plane.
  - Local `axis_y` (profile-horizontal) is `normal x axis_z` (right-hand rule).
  - Removed the edge-order-dependent `Na__Exporter__SeedAxisY` helper.
  - Added small helpers `Na__Exporter__DeriveFaceNormal`, `Na__Exporter__FindLongestEdgeVector`, `Na__Exporter__ProjectVectorOntoPlane` for one-responsibility-per-function.
- Removed the compensating sign-flip on `z_mm` in `Na__Exporter__ProjectPointToLocalYZ`. The new frame already produces a world-up-aligned local Z, so the explicit negation that was masking the rotation bug is no longer needed (and would now mirror the profile vertically).
- Applied the same world-up frame logic in `Na__ProfileTools__ProfilePathTracer__SceneProfileRegistry__.rb` (`Na__SceneProfileRegistry__ExtractUnifiedGeometry`), which independently had the identical edge-order bug. Scene-picked components/groups now project face vertices into a deterministic frame; origin remains at the first vertex of the outer loop.
- Removed `Na__Svg__ApplyDefaultPreviewAxisFlip` and its call site in `Na__ProfileTools__ProfilePathTracer__Viewport__SvgGenerator__.js`. That hard-coded mirror was compensating for the rotation bug; with the deterministic frame it would now mirror the preview horizontally. User-driven flip toggles (`flipXCenter`, `flipYCenter`, `flipXWorld`, `flipYWorld`) and the rotate-90 step are retained for intentional reorientation.
- Net effect: balustrade and other complex profiles preview upright with no rotation, and the saved `PosY_mm` / `PosZ_mm` values match what the user sees in the preview (world-up maps to profile-up).

# =======================================================================================
## ProfileTools Version 0.3.4 - 11-May-2026

### Per-Edge Dihedral Smoothing + Winding-Flip For Selection Mode

- Replaced over-smoothing logic in `Na__Geometry__ApplyUnifiedEdgeStates`:
  - Previously, `BuildRunStyleDefaults` used `any?` to force ALL run edges to soft+smooth if any profile mesh edge was IsSoft/IsSmooth. Cause of the "heavy smoothing on entire object" symptom that persisted across first-load and reload.
  - New `Na__Geometry__ShouldSoftenRunEdgeByAngle?` decides per edge using the dihedral angle between adjacent faces (threshold 20 deg, matching SketchUp's built-in soften default).
  - New `Na__Geometry__DihedralAngleBetween` and `Na__Geometry__BuildPerEdgeStylePayload` keep each function single-responsibility.
  - Removed dead helpers `BuildRunStyleDefaults`, `BuildPathDirectionVectors`, `EdgeParallelToPath?` (no longer referenced).
- Flipped closed-loop winding normalisation in `Na__Path__NormaliseClosedLoopWinding`:
  - Selection-mode loops are now normalised to CW from the dominant plane axis (was CCW). This matches the typical interactive convention where the profile lands on the exterior of the loop (picture-frame trim around a perimeter).
- Net effect: first-time generation now produces correct edge smoothing without requiring `Reload Plugin`, and selection mode generates the profile on the same side as interactive mode.

# =======================================================================================
## ProfileTools Version 0.3.3 - 11-May-2026

### Closed-Loop Miter, Duplicate-Builder Purge, Selection/Interactive Parity

- Removed legacy `Na__ProfileTools__ProfilePathTracer__GeometryBuilders__.rb`:
  - File contained `Na__GeometryBuilders` redefined 5 times with 5 mismatched signatures of `BuildProfileAlongPath`, `ApplyUnifiedEdgeStates`, `BuildPathFrame`, `BuildPreviewSweepSegments` and related methods.
  - Removal eliminates the root cause of first-run vs post-reload behavioural drift (correct edge smoothing without manual reload).
  - `Na__ProfileTools__ProfilePathTracer__PluginReloader__.rb` now exposes an empty exclude list; nothing to skip.
- Added Profile Builder-style closed-loop miter in `GeometryBuilders__UnifiedOverrides__.rb`:
  - `Na__Geometry__BuildPathFrame` now rotates the start profile face onto the bisector plane at the closure corner for closed loops.
  - New helpers `Na__Geometry__BuildStartFrameTangent`, `OutgoingTangentAtIndex`, `IncomingTangentAtIndex`, `BisectorTangent` make the maths explicit and one-responsibility-per-function.
  - `Na__Geometry__RemoveClosureSeamFaces` defensively erases the implicit end-cap face SketchUp leaves on the bisector plane after `followme`, so the result is a clean continuous loop.
- Added closed-loop winding normalisation in `Na__ProfileTools__ProfilePathTracer__PathAnalysis__.rb`:
  - `Na__Path__OrderEdges` now normalises closed-loop chirality via signed-area in the loop's dominant plane (XY/XZ/YZ chosen by best-fit normal).
  - Selection-mode profile now lands on the same side of the path as interactive mode for the same loop.
  - Open paths are not modified; user-picked direction is preserved.
- Cleaned up the per-generation runtime guard in `ProfilePlacementEngine__.rb`:
  - `Na__Engine__GenerateFromPathData` no longer force-`load`s unified overrides every click (no longer compensating for a deleted file).
  - `Na__Engine__LogActiveBuilderRuntimeOnce` continues to log the active geometry builder source for diagnostics.

# =======================================================================================
## ProfileTools Version 0.3.2 - 11-May-2026

### First-Run Edge-State Timing Fix (No Manual Reload Required)

- Updated geometry runtime sync in `Main__.rb`:
  - `Na__Runtime__EnsureUnifiedGeometryBuilders` now force-loads unified geometry builder overrides on generation-time sync.
  - This removes stale first-launch method drift and aligns first-run behaviour with post-reload behaviour.
- Updated edge classification in `GeometryBuilders__UnifiedOverrides__.rb`:
  - connector/run edges now use topology-first classification (`edge.faces.length >= 2`) after path/cap exclusion.
  - end-cap/perimeter profile edges remain hard.
- Updated generation diagnostics in `ProfilePlacementEngine__.rb`:
  - one-time console log reports active geometry builder source file.
  - generation status now includes styled edge count for immediate runtime verification.

# =======================================================================================
## ProfileTools Version 0.3.1 - 11-May-2026

### Smoothing Runtime Determinism + Connector-Only Soft/Smooth Inference

- Canonicalized geometry runtime activation:
  - Added runtime source-location validation in `Main__.rb`.
  - Added runtime self-heal (`load` unified overrides file) when stale geometry builder implementation is detected.
  - Generation now blocks with explicit status if unified runtime cannot be asserted.
- Stabilized reload determinism:
  - `PluginReloader` now forces `GeometryBuilders__UnifiedOverrides__.rb` and `Main__.rb` to reload last.
  - `DialogManager` now validates unified geometry runtime after reload before reopening status handoff.
- Reworked unified edge styling classification:
  - Style pass now excludes path edges and end-cap plane edges.
  - Added path-direction parallel filter so only connector/run extrusion edges are style candidates.
  - Soft/smooth defaults now infer from source profile edge-state presence and are applied only to connector/run edges.
- Confirmed both generation entry modes converge on the same build/style path:
  - Selection-mode generate and interactive finish both route through `ProfilePlacementEngine.Na__Engine__GenerateFromPathData`.

# =======================================================================================
## ProfileTools Version 0.3.0 - 11-May-2026

### Unified Schema Migration + Origin UCS Save Workflow

- Replaced ProfilePathTracer save/load/profile-source contract with unified schema only:
  - `meta`
  - `Na__Asset__Metadata`
  - `Na__Asset__Profile2D`
  - `Na__Asset__Mesh3D`
- Exporter now captures edge state fidelity in mesh edges:
  - `IsSoft`, `IsSmooth`, `IsHidden`, `CastsShadows`
  - `EdgeMaterialName`, `EdgeColourId`, `EdgeColourHex`
- Added cursor-picked origin workflow before file save:
  - User clicks viewport point to define local UCS origin.
  - Export creates persistent `00__OriginPoint` helper at that location.
  - Helper tag: `02__DoorHelpers__RotationPivots`.
  - Helper edge colour: `MTE201__LineColour__Red`.
- Scene profile registry now emits unified schema payloads instead of `polyline2d`.
- Profile library parser is now strict unified-schema-only and rejects legacy file roots.
- Added `GeometryBuilders` unified override module for deterministic runtime behaviour:
  - `Na__ProfileTools__ProfilePathTracer__GeometryBuilders__UnifiedOverrides__.rb`
  - Generation path now uses unified schema and reapplies hidden/soft/smooth/edge-colour states.
- Updated dependency bootstrap to preload `:edge_materials` from DataLib.
- Updated SVG preview/UI bridge to read unified `Na__Asset__Profile2D` records only.
- Added roundtrip validation API:
  - `Na__PublicApi__RunRoundtripValidation(profile_key, selected_entities = nil)`
  - Reports source edge stats, generated edge stats, and deltas for soft/smooth/hidden/colour counts.
- Updated plugin reload flow to exclude legacy `GeometryBuilders__.rb` from hot-reload execution and use unified override module.
- Updated architecture/readme docs to reflect unified schema contract and legacy removal.

# =======================================================================================
## ProfileTools Version 0.2.0 - 11-May-2026

### Interactive Profile Builder Rewrite (Array-Style Live Drawing)

- Added new modules:
  - `Na__ProfileTools__ProfilePathTracer__AxisLockMixin__.rb`
  - `Na__ProfileTools__ProfilePathTracer__SceneProfileRegistry__.rb`
  - `Na__ProfileTools__ProfilePathTracer__SceneProfilePicker__.rb`

- Rebuilt `Na__ProfileTools__ProfilePathTracer__PathSelectionTool__.rb`:
  - Switched from click-vertex-on-preselected-path flow to waypoint free-draw flow.
  - Added Enter/right-click/double-click finish gestures.
  - Added Backspace/Delete undo and ESC cancel handling.
  - Added per-frame preview cache for path length and sweep preview data.
  - Added TAB profile rotation parity inside interactive draw loop.

- Added arrow-key axis locking support (ported interaction pattern from Array Builder):
  - Right/Left/Up/Down locks for X/Y/Z/parallel inference modes.
  - Uses SketchUp native `view.lock_inference` for projection + visual feedback.
  - Lock re-anchors after each committed waypoint.

- Added scene profile source workflow:
  - New scene picker tool for top-level Group/Component selection.
  - Strict extraction rule: exactly one top-level planar face, no inner loops.
  - Extracted scene profile stored in registry as `polyline2d` profile payload.

- Updated generation pipeline:
  - `ProfilePlacementEngine` now resolves profile source mode (`library` or `scene`).
  - Added interactive path generation entrypoint from waypoint arrays.
  - Kept selection-mode generation path for backward compatibility.

- Updated geometry/preview modules:
  - `GeometryBuilders` now builds sweep wireframe preview segments across path frames.
  - `3dPreviewGraphics` now renders waypoint markers and sweep segment previews.

- Updated dialog/UI/bridge integration:
  - Added profile source mode control (`library` vs `scene`).
  - Added scene source controls (`Pick Scene Profile`, `Clear`).
  - Added bridge callbacks for scene pick/clear/status.
  - Bootstrap now carries scene profile status + profile source defaults.
  - Default path mode updated to interactive in config/bootstrap fallbacks.

- Updated observers and lifecycle:
  - Replaced observer scaffold with app + definitions observers.
  - Scene profile registry now auto-clears on model switch or picked definition removal.
  - `PublicApi` now installs observers before opening dialog.

- Updated docs:
  - Architecture dependency graph and runtime flow now reflect interactive draw and scene-source modules.
  - README now reflects non-scaffold feature state.

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
