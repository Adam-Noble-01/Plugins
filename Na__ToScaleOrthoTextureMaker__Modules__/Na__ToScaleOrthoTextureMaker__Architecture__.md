# Na__ToScaleOrthoTextureMaker - Architecture

## Purpose

`Na__ToScaleOrthoTextureMaker` captures the active SketchUp viewport as a
perfectly flat 2D texture and places it on a new in-model plane that exactly
matches what the viewport showed. Intended for flattening dense LiDAR /
photogrammetry scans into draw-over-able 2D reference planes for plans,
sections and elevations.

## Load Order

1. `Na__ToScaleOrthoTextureMaker__Main__.rb` (root shim)
2. `Na__ToScaleOrthoTextureMaker__Loader__.rb` (root loader)
3. `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__Main__.rb` (orchestrator)
4. Orchestrator `require_relative` modules (menu/command, hotkey, dialog,
   camera frame, view classifier, projection engine, material/UV, plane builder).

## Folder Structure

- `Na__ToScaleOrthoTextureMaker__Loader__.rb`
- `Na__ToScaleOrthoTextureMaker__Main__.rb` (legacy compatibility shim)
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__Main__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__MenuAndCommand__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__HotkeyBinder__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__DialogManager__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__CameraFrame__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__ViewClassifier__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__ProjectionEngine__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__PlaneBuilder__.rb`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__UiLayout__.html`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__Styles__.css`
- `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__UiEventToRubyApiBridge__.js`

## Module Responsibilities

- `Na__ToScaleOrthoTextureMaker__Main__.rb`
  - Public API entry points (`Na__Bootstrap__RegisterPluginUi`, `Na__Ui__ShowMainDialog`, `Na__Projection__RunFromUi`).
  - Orchestrates `CameraFrame -> ViewClassifier -> ProjectionEngine -> PlaneBuilder`.
  - Wraps the entire pipeline in a single `start_operation` / `commit_operation` block for undo safety.

- `Na__ToScaleOrthoTextureMaker__MenuAndCommand__.rb`
  - Creates Extensions menu command.
  - Routes command to dialog entry.

- `Na__ToScaleOrthoTextureMaker__HotkeyBinder__.rb`
  - Binds keyboard shortcut to the same command path.

- `Na__ToScaleOrthoTextureMaker__DialogManager__.rb`
  - Creates and manages `UI::HtmlDialog`.
  - Registers callbacks (`na_requestScenes`, `na_runProjection`, `na_refreshScripts`, `na_jsLog`).
  - Pushes scene options and status back to JS, and appends any capture warnings to the main status line.
  - Provides hot-reload utility for in-session Ruby script refresh.

- `Na__ToScaleOrthoTextureMaker__CameraFrame__.rb`
  - Resolves the requested scene (or Current View) camera onto the active view.
  - Forces Parallel Projection by rebuilding the camera with `perspective = false`; if the source was perspective, the ortho height is derived from `fov` and eye-to-target distance.
  - Returns a frame hash containing `eye`, `target`, `up`, `right`, `direction`, `height_world`, `width_world`, `aspect`, viewport pixel sizes, the scene page (if any) and a `warnings` array.

- `Na__ToScaleOrthoTextureMaker__ViewClassifier__.rb`
  - Classifies a camera direction vector as one of `Top`, `Bottom`, `Front`, `Back`, `Left`, `Right` or `CustomView` using a strict dot-product tolerance.
  - Used to label the output group and to surface a CustomView warning when the user captures from a non-standard angle.

- `Na__ToScaleOrthoTextureMaker__ProjectionEngine__.rb`
  - Pure viewport capture. Calls `Sketchup::View#write_image` with the requested resolution and the viewport aspect, and returns the temporary PNG path.
  - No geometry analysis, no visibility hacks - active Styles, Section Planes and Fog are respected automatically because SketchUp renders the view as-is.

- `Na__ToScaleOrthoTextureMaker__PlaneBuilder__.rb`
  - Builds the output group and a single quad face centred on `camera.target`, sized to `width_world x height_world`, oriented by the camera's own `right` and `up` vectors.
  - Names the group with the resolved label (scene name if chosen, otherwise the `ViewClassifier` result).
  - Delegates texture/UV application to `Na__MaterialUvBuilder`.

- `Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__.rb`
  - Thin helper: creates a material from the temporary PNG and applies an axis-locked UV map to the provided face using the same four corner points used when the face was built.

- UI files (`UiLayout`, `Styles`, `UiEventToRubyApiBridge`)
  - Tabbed UI (`Main`, `Settings`) with scene and resolution controls.
  - Sends capture payload `{ scene_name, capture_resolution }` to the Ruby bridge.
  - Settings tab triggers the Ruby hot-reload path and displays refresh status.

## Runtime Data Flow

1. User opens the command from the Extensions menu or the assigned hotkey.
2. Dialog loads, requests scene names and renders the Main tab.
3. User picks a scene (or `Current View`) and clicks `Capture Viewport`.
4. Main tab posts `{ scene_name, capture_resolution }` JSON to `sketchup.na_runProjection`.
5. `Na__DialogManager` calls `Na__ToScaleOrthoTextureMaker.Na__Projection__RunFromUi`.
6. Main orchestrator:
   1. Calls `Na__CameraFrame.Na__Camera__ResolveFrame` to apply/normalise the camera and build the frame.
   2. Appends a CustomView warning when appropriate via `Na__ViewClassifier`.
   3. Calls `Na__ProjectionEngine.Na__Projection__CaptureViewportImage` to write the temp PNG.
   4. Calls `Na__PlaneBuilder.Na__Plane__BuildViewportPlane` to construct the textured group.
7. Success / error status plus any warnings are returned to the dialog.
8. Settings tab can trigger Ruby hot-reload via `sketchup.na_refreshScripts` at any time.

## Skew Elimination Contract

- The image capture frame (`write_image` with aspect-preserving dimensions)
  and the plane geometry frame (`camera.right`, `camera.up`, `camera.height`,
  `aspect`) are built from the exact same camera state.
- The plane is centred at `camera.target` with normal equal to the reverse of
  `camera.direction`; in ortho mode this guarantees every texel projects
  straight down onto the plane with zero parallax, zero rotation, zero skew.
- No dependency on any user-picked face, container or selection.

## Output Convention

- A new top-level `Group` named `Na__Ortho__<ViewLabel>`, where `<ViewLabel>` is
  the scene name (sanitised) when a scene was chosen, otherwise the standard
  view label (`Top`, `Bottom`, `Front`, `Back`, `Left`, `Right`) or
  `CustomView` for off-axis captures.
- The group contains one flat quad face carrying a material named
  `Na__OrthoProjected__<timestamp>` whose texture is the captured PNG.
