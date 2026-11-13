# To Scale Ortho Texture Maker
# =============================================================================
# Module : 34__SourceCode__ToScaleOrthoTextureMaker
# Plugin : Na Noble3d Modelling Tools
# Tab    : Misc Utils > Ortho Reference Planes

## Overview

Captures the active parallel-projection viewport as a flat textured plane that
matches the view, then can export that texture as a PNG whose filename carries
the true-scale millimetre size.

Group prefix `Na__Ortho__` and attribute dictionary `Na__Ortho__Capture` are
unchanged, so groups captured by the standalone plugin still export.

Parent entry: main devlog **Version 0.9.5** (24-Sep-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================

## Version 3.1.1 - 13-Nov-2026 - Point Cloud Ortho Plane From the Clip Box

Parent entry: main devlog **Version 0.9.49**. Status: IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027.

- **Asked for.** Adam, asked whether to keep a turned clip box in the Point Cloud Viewer: "Yes, build it". The agreed spec
  (Na SketchUp MCP's `Specs/Na__SketchUpMcp__Spec__PointCloudOrthoPlane__.md`, section 6) wanted it usable by this tab's
  button as well as for his own viewing.
- **Core:** `Na__ToScaleOrthoTextureMaker__PointCloudOrtho__FrameClip(cloud = nil)` reads the viewer's `state` (the active
  cloud, or the one named) and returns the frame square to its clip box's FRONT face (the box's own -y side, looking along
  its own +y; picture up the box's own z), the box's width and height as the extent, and its depth as the slab
  ([depth, 0] from the front face). A level box gives a Front elevation.
- **Button:** a fourth mode, "The clip box (its front face)": the slab fields grey out (the box sets them) and the plane is
  named after the cloud (`<Cloud>ClipBox`) unless a name is typed.
- **Tests.** `tests/point_cloud_ortho_unit.rb.test`: 21 checks (2 new, against a stand-in for the viewer's state read): a
  box turned along Kann's east wall gives that wall's elevation (axes, front-face origin, extent, slab, cloud name); a level
  box gives a Front elevation; no box and an unknown cloud are refused.
- **What offline cannot prove:** the mode in SketchUp with a real turned box.

### Checklist for Adam
- [ ] Reload the Point Cloud Viewer (0.14.8) and Noble 3D Tools; in the viewer, Turn to Two Points along a wall and push the box's Front and Back to the wall.
- [ ] Misc Utils > Ortho Reference Planes > Point Cloud Ortho Plane, Square To "The clip box (its front face)", Make Plane: the wall's elevation appears in front of the model, named `REF__DrawingPlane__...__PointCloudOrtho__<Cloud>ClipBox`.

## Version 3.1.0 - 13-Nov-2026 - Point Cloud Ortho Plane

Parent entry: main devlog **Version 0.9.48**. Spec: Na SketchUp MCP's
`85__Docs__AgentReference/Specs/Na__SketchUpMcp__Spec__PointCloudOrthoPlane__.md`, sections 12 and 13.

- **What Adam asked for.** After the Kann 64562 upper garden job (a cloud derived from Google Earth: point cloud ->
  scaled 2D image -> 2D linework -> 3D), a tool that makes the scaled picture and places it as a plane to draw over,
  "a textured face ... add a white background rather than transparent it makes them easier to work with", placed
  "infront of the geomtry", and "Yes add button".
- **The shared core** (`Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__PointCloudOrtho__.rb`, new):
  - `Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Make(spec)` (inches): frame, u, v, depth, resolution, fill, dot_px,
    look, background, placement, offset, name, view word, tag, save path, clouds, place, hide, calibrate. Errors are
    `Na__PointCloudOrthoError` with a code and a hint.
  - Frames: `__FrameStandard` (top ... right), `__FrameWall` (two ends and the side you look from; the picture runs
    left to right as seen from there), `__FrameCamera` (the current view; a perspective camera is refused),
    `__FrameFace` (a face's points and normal, turned to face the camera), `__AutoV` (how high the cloud reaches along
    a wall), `__ViewWord` (PlanView, UnderView, Front/Back/Left/RightElevation).
  - Capture with zero trace: the model is hidden inside an undo operation that is aborted; the camera is parallel, 5 m
    beyond the slab, and put back after; the clouds are drawn through the viewer's `composite` with a turned clip box,
    look and dot size for that render only; two crosses captured on white prove the pixel map (refused above 1.0 px).
  - Dots: from the viewer's `spacing` (the sparse quarter of 250 mm cells), ceil(1.3 x spacing / resolution) px.
  - The PNG: the job's `01__ReferenceFiles/12__PointCloud__Orthos`, `<Client>__PointCloudOrtho__NN__<View>__<name>__<res>mmPx__<dd-Mon-yyyy>.png`,
    never over a file.
  - The plane: a textured face on white through `MaterialUvBuilder` (four pins on its corners), edges hidden, facing the
    camera, in front of the model's geometry along the view (24 x 24 ray tests, existing drawing planes skipped, depth
    rounded to a whole 5 mm from the model origin), `REF__DrawingPlane__<View>__PointCloudOrtho__<name>` on
    `06__Drawings`, stamped with `Na__Ortho__Capture` (`source: point_cloud`, `background_mode`, size, calibration), so
    Export works on it. One undo step, "Point Cloud Ortho Plane".
- **The button** (`..._PointCloudOrthoButton__.rb`, new; `UiLayout`, `UiBridge`, `Styles`, `DialogManager`, `Loader`):
  - modes: the current view (Parallel Projection), a face (a pick tool through `PickHelper#transformation_at`, so nested
    faces read in world), a wall (three clicks with `InputPoint`, the wall drawn red and the side line blue; Esc starts
    again, then cancels);
  - the slab defaults change with the mode (view 50,000 / 50,000; face 1,000 / 1,000; wall 900 / 700 mm);
  - the status line reports the plane, its pixel size, dot size, coverage, how far out it sits and what it is in front
    of, the calibration and the PNG's name; the button greys out with the reason when the viewer lacks the `ortho`
    feature.
- **Not built from the spec:** dragging a plan rectangle (the view mode takes the current view instead), the slab drawn
  live while it is set, and a turned clip box kept in the viewer for Adam's own viewing (the turned clip is for each
  capture only).
- **Tests.** `tests/point_cloud_ortho_unit.rb.test`, 19 checks (frames and view words, Kann's east and west walls,
  faces seen from either side, refusals, names, resolution and date text, the job folder, numbering past what is
  there, Windows backslashes, never writing over a file). Run it with
  `python <Plugins>/Na__SketchUpMcp__Modules__/40__Tests__Validation/Na__SketchUpMcp__Tests__RunRubyChecks__.py <this folder>/tests/point_cloud_ortho_unit.rb.test`.
- **Live** (a copy of Kann 64562): the view mode on the PC__Topdown scene at 60 mm a pixel made
  `REF__DrawingPlane__PlanView__PointCloudOrtho__ButtonTest__PCTopdown` (calibration 0.0 px; its depth then rounded to
  the grid, z 16905.0); at a finer resolution it refused the 5963 x 3718 px picture (over 12 MP) and named 55 mm a pixel
  as the size that fits. Export read the MCP tool's planes (label, millimetre size, pixels, white background).

### Checklist for Adam
- [ ] Reload Noble 3D Tools (and the Point Cloud Viewer, then Na SketchUp MCP), open Misc Utils > Ortho Reference Planes: the Point Cloud Ortho Plane section says "Ready".
- [ ] Current view on PC__Topdown, Make Plane: a white `REF__DrawingPlane__PlanView__PointCloudOrtho__...` appears in front of the model; one Ctrl+Z removes it.
- [ ] A wall: Square To "A wall", Make Plane, click the two ends of a boundary wall's face in plan, then a point in the garden: a Left or Right elevation of the wall.
- [ ] A face: Square To "A face", click a face inside a group: the plane is square to it.
- [ ] Export Texture with a point cloud plane selected writes its PNG with the millimetre size in the name.

## Version 3.0.0 - 24-Sep-2026 - Ported into Noble 3D Tools

- Moved out of the standalone `Na__ToScaleOrthoTextureMaker` plugin.
- Menu and hotkey registration now come from the Noble command registry.
- Capture, plane, material, and export responsibilities stay in separate files.
- Dialog styling follows the Noble light theme.
