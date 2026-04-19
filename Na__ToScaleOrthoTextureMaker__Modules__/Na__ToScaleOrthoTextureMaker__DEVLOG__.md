# Na__ToScaleOrthoTextureMaker - DEVLOG
# =========================================================

# ---------------------------------------------------------
## 19-Apr-2026 - Version 1.2.4
- Added a Background mode selector to the Main tab with two options: `Transparent (default)` and `Solid White`. Transparent preserves legacy behaviour via `:transparent => true` on `Sketchup::View#write_image`; white forces a clean solid-white background ideal for print / downstream compositing.
- White background is implemented safely in `Na__ToScaleOrthoTextureMaker__ProjectionEngine__.rb` via the new `Na__Projection__ApplyWhiteBackground` / `Na__Projection__RestoreRenderingOptions` helpers, which snapshot and restore `BackgroundColor`, `SkyColor`, `GroundColor`, `DrawHorizon`, `DrawGround`, `DrawUnderground` around the capture. The user's style settings are left untouched after the call.
- Wired `background_mode` end-to-end: JS payload -> DialogManager -> `Na__Projection__RunFromUi` -> `Na__Projection__CaptureViewportImage`. Defaults to `:transparent` if the key is missing.
- Added a new module `Na__ToScaleOrthoTextureMaker__TextureExporter__.rb` dedicated to pushing captured textures to disk. It reads the `Na__Ortho__Capture` attribute dictionary to produce a self-describing filename like `Na__Ortho__Top__W24359mm_H14744mm__4096x2480px__20260419T154530.png`, so downstream software (Photoshop, Rhino, Blender, Layout, etc.) can be told the exact scale factor.
- Export uses `Sketchup::Texture#image_rep` + `Sketchup::ImageRep#save_file`, so it bypasses `write_image` entirely and writes the raw baked pixels.
- Export resolves the source group in this order: the first `Na__Ortho__Capture`-stamped group in the current selection, then the most recent `Na__Ortho__Capture`-stamped group anywhere in the model (by ISO capture time). If neither exists it fails with a clear message asking the user to run Capture Viewport first.
- `Na__ToScaleOrthoTextureMaker__PlaneBuilder__.rb` now stamps a full `Na__Ortho__Capture` attribute dictionary on the group (`label`, `mm_width`, `mm_height`, `pixel_width`, `pixel_height`, `background_mode`, `capture_time_iso`, `plugin_version`). The dictionary survives save / reload and is the single source of truth for the exporter.
- Added UI: Background dropdown above the Capture button, an `Export Texture` secondary button + dedicated export status line below, a thin divider and subheading between the Capture and Export sections. Added CSS styling for the secondary button variant, divider and subheading.
- Added `na_exportTexture` action_callback and `Na__Ui__PushExportStatus` in `Na__ToScaleOrthoTextureMaker__DialogManager__.rb` plus a `na_setExportStatus` / `na_setExportBusy` pair on the JS side so the Export button gets its own busy spinner and status line, identical in feel to the existing Capture flow.
- The JS `na_setExportStatus` always clears the export busy state, so any Ruby-side completion (success, error or cancelled) auto-re-enables the Export button.
# ---------------------------------------------------------

# ---------------------------------------------------------
## 19-Apr-2026 - Version 1.2.3
- Success status now reports the true-scale plane size in millimetres (converted from SketchUp's internal inches) alongside pixel dimensions, so captures can be re-scaled precisely in external software.
- Added `6144 px` and `8192 px (8K)` options to the capture resolution dropdown, with inline guidance that above 4096 is GPU-dependent.
- Added a soft warning pushed to the status line when the requested resolution exceeds 4096 px, since `Sketchup::View#write_image` can fail at high resolutions on low-VRAM systems.
- Added a `Na__Projection__ClampResolution` helper in `Na__ToScaleOrthoTextureMaker__Main__.rb` that hard-caps the requested output at 8192 px and floors missing values at 2048 px.
- Added a "Capturing..." busy state on the UI: the Capture Viewport button is disabled and a spinner status line appears before the Ruby call is issued, preventing double-clicks and signalling that SketchUp may briefly appear frozen during high-resolution captures.
- Added `na-status-busy` styling + spinner keyframes to `Na__ToScaleOrthoTextureMaker__Styles__.css`.
- The JS `na_setStatus` now always releases the busy state so any Ruby-side completion (success or error) re-enables the button automatically.
- No true percentage progress bar was added: `Sketchup::View#write_image` is synchronous and blocks the Ruby thread, so there is no supported API hook for mid-render progress. The spinner + button-lock covers the UX gap without the complexity (and risk) of a background render shim.
# ---------------------------------------------------------

# ---------------------------------------------------------
## 19-Apr-2026 - Version 1.2.2
- Rewrote the capture pipeline around the active viewport camera; no face, container or selection is required anymore.
- Deleted `Na__ToScaleOrthoTextureMaker__SelectionResolver__.rb`; all selection-driven code paths removed.
- Added `Na__ToScaleOrthoTextureMaker__CameraFrame__.rb` to resolve an ortho camera frame from a chosen scene or `Current View`, forcing Parallel Projection when needed and deriving an ortho height from FOV when converting from perspective.
- Added `Na__ToScaleOrthoTextureMaker__ViewClassifier__.rb` to label the captured frame as Top / Bottom / Front / Back / Left / Right / CustomView via direction dot-product tolerance checks.
- Added `Na__ToScaleOrthoTextureMaker__PlaneBuilder__.rb` which builds the output group and quad face centred on `camera.target`, sized by `width_world x height_world`, and oriented by the camera's own `right` and `up` vectors.
- Simplified `Na__ToScaleOrthoTextureMaker__ProjectionEngine__.rb` to pure viewport capture using `Sketchup::View#write_image`; active Styles, Section Planes and Fog are respected automatically.
- Simplified `Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__.rb` to a thin helper that applies a texture + corner-locked UV map to a prebuilt face.
- Rewired `Na__ToScaleOrthoTextureMaker__Main__.rb` to run `CameraFrame -> ViewClassifier -> ProjectionEngine -> PlaneBuilder` under one `start_operation` / `commit_operation` block.
- Added non-blocking warnings surfaced on the dialog status line when `Current View` is captured from Perspective or from a non-standard ortho plane.
- Updated UI copy (`UiLayout.html` help text, button label `Capture Viewport`, `MenuAndCommand` status bar text, `DialogManager` ready status) to reflect the viewport-based workflow.
- Updated Architecture.md to describe the new modules and the skew elimination contract.
# ---------------------------------------------------------

# ---------------------------------------------------------
## 19-Apr-2026 - Version 1.2.1
- Fixed Settings tab refresh status hang where UI remained on `Refreshing scripts...`.
- Updated refresh callback to capture a stable dialog handle before Ruby reload begins.
- Decoupled post-reload status writes from `@na_dialog` by adding explicit dialog-targeted status helper.
- Added reload summary console output for clearer refresh diagnostics.
# ---------------------------------------------------------

# ---------------------------------------------------------
## 19-Apr-2026 - Version 1.2.0
- Added tabbed dialog layout matching Edge Tools structure (`Main` and `Settings` tabs).
- Added Settings tab with `Refresh Scripts` button for in-session plugin reload.
- Added Ruby callback `na_refreshScripts` and module hot-reload utility in DialogManager.
- Added dedicated settings status feedback channel (`na_setSettingsStatus`) in JS bridge.
- Updated architecture documentation for new callback flow and settings reload behavior.
# ---------------------------------------------------------

# ---------------------------------------------------------
## 19-Apr-2026 - Version 1.1.0
- Refactored plugin from monolithic single-file implementation to modular architecture.
- Added root loader: `Na__ToScaleOrthoTextureMaker__Loader__.rb`.
- Converted root main to compatibility shim that delegates to loader.
- Added module orchestrator and split responsibilities into:
  - menu/command registration
  - hotkey binder
  - dialog manager
  - selection resolver
  - projection engine
  - material/UV builder
- Added HtmlDialog foundation with dedicated HTML/CSS/JS bridge files.
- Added robust projection cleanup in `ensure` block for camera and visibility state recovery.
- Added architecture documentation file for module load order and runtime flow.
# ---------------------------------------------------------

# =========================================================
##### END OF FILE ######
