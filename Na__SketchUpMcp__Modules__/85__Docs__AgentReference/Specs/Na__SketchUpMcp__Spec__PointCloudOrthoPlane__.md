# Spec: `point_cloud_ortho_plane` (Na SketchUp MCP 1.0.34, Na Point Cloud Viewer 0.14.7)

Status: **agreed with Adam, 13-Nov-2026; BUILT the same day** (Na SketchUp MCP 1.0.34, Na Point Cloud Viewer 0.14.7, Noble 3D Tools 0.9.48; their devlogs have the tests). Built differently from this text: the dots are sized directly (`dot_px` = ceil(1.3 x spacing_sparse / resolution)) rather than by widening the field (5.3); the turned clip is passed as `clip_frame` / `clip_min` / `clip_max` for each capture only, and a viewer older than 0.14.7 is refused rather than given level segments (6); the core's entry is `Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Make` (13). A turned clip box kept in the viewer for Adam's own viewing (6) followed the same day (viewer 0.14.8, MCP 1.0.35, Noble 3D Tools 0.9.49: the Clipping tab's Turn row and Turn to Two Points; the button's and the tool's `clip` source). Not built yet: the button's plan rectangle drag and the slab drawn live (13; the button squares to the current view, or the clip box, instead). Written by Claude after the Kann 64562 upper garden job. Adam's four decisions are in section 12 and are folded through the spec: textured face on a white background, placed in front of the geometry, turned clip boxes in the viewer, and a button on the Ortho tab.

## 1. Why

Adam, Kann 64562, 13-Nov-2026, on a cloud derived from Google Earth:

> "Pointcloud -> Scaled 2D Image -> 2D Linework -> (Eventually 3D)" for low-quality clouds.
> "inserting the image plane worked EXCELLENTLY for me to in model reference and check your workings ...
> keeping image based planes helps me and other agents work in the model and validate."
> "ensure you ALWAYS use a parallel projection (2D Camera)".

On that job an agent made four of these planes by hand (one plan, two wall elevations of four segments each). It took about 25 tool calls each:
- hide the model in a rollback batch;
- set a clip box (one undo step each);
- pick a camera and widen the field so the dots meet;
- capture with `view_capture include_point_cloud`;
- prove the pixel map with temporary crosses;
- composite the segments and make the white transparent;
- save to the job folder;
- place it with `ruby_eval` (`image_place` is broken, section 9).

This tool does all of that in one call, with the same result every time.

## 2. What It Does

One call (or one button on the Ortho tab, section 13) makes one **scaled, square-on picture of the point cloud** and places it in the model as a `REF__DrawingPlane__` image plane:
- square to the plane the agent names: a level for a plan, or a wall's face for an elevation;
- placed **in front of the model's geometry** along the view, so nothing hides it (it is switched off by its tag when not wanted);
- at a known mm per pixel;
- with only the slice of cloud the agent asked for;
- on a **white background** (Adam: easier to work with than transparent);
- saved as a PNG in the job folder.

The model is otherwise unchanged. The plane is drawn over afterwards (geometry_create_lines, the 2D drafting kit), with the linework 5 mm in front of the plane, and Adam checks the linework against it in place.

**The camera is always parallel.** The tool has no perspective option.

## 3. Reuse, Not Rewrite

| Piece | From | Change needed |
|---|---|---|
| Parallel camera frame, width from height and aspect, view label | Noble 3D Tools `34__SourceCode__ToScaleOrthoTextureMaker`, `CameraFrame` | None: build the frame from the tool's own camera instead of the viewport's |
| White-background capture | `ProjectionEngine__CaptureViewportImage` with `background_mode: :white` (it already sets background, sky and ground white, turns horizon and ground off, and restores them) | Must be followed by the viewer's `composite`: **`write_image` never contains the cloud** (the overlay is not exported) |
| Drawing the clouds over the capture | Viewer seam `composite` (`95__System__McpOperations`, v0.14.1) | Transient clip and look (section 6) |
| True-scale plane and its metadata | `PlaneBuilder` (textured face, `Na__Ortho__Capture` dictionary: `mm_width`, `mm_height`, `pixel_width`, `pixel_height`) | Place it on the requested plane, not at the camera target; name and tag it to Adam's standard |
| PNG export with the mm size in the file name | `TextureExporter` | None: planes made here carry the same dictionary, so its Export button works on them |

The plane is a **textured face** (PlaneBuilder's route), not a `Sketchup::Image` (Adam, 13-Nov-2026):
- the Ortho tab exports it;
- `na_read_sheets` in the 2D drafting kit reads textured faces and Images alike.

The Kann planes were Images, with transparent backgrounds, only because `image_place` failed. New planes are textured faces on white.

## 4. Parameters

Lengths are in the call's `units` (default mm), world coordinates, and every schema has `additionalProperties: false`.

| Key | Type | Meaning |
|---|---|---|
| `view` | `top` \| `bottom` \| `front` \| `back` \| `left` \| `right` \| `wall` \| `frame` | `top`... `right` look along a model axis. `wall`: square to a wall line in plan. `frame`: any plane given by `frame` |
| `wall` | `{a: [x,y], b: [x,y], face_side: "left"\|"right"}` | `view: wall`. The wall face's line in plan, `a` to `b`; the camera looks at the face from `face_side` (walking a to b). Image right is a to b unless `flip` |
| `frame` | `{origin, x_axis, y_axis}` | `view: frame`. The plane's origin and its in-plane axes; the camera looks along -(x × y). The same frame object as `point_cloud_slice` |
| `extent` | `{u: [min, max], v: [min, max]}` | The picture's area in the plane's own axes, from the origin: plan x/y, or along the wall and z |
| `depth` | `[behind, front]` | The slab of cloud kept: how far behind the plane and how far in front (toward the camera). Default `[1000, 1000]`. A plan's slab is z: e.g. `[1000, 15000]` keeps everything from 1 m below the plane to 15 m above |
| `resolution` | number | Model length per pixel (default 10 mm). Refused if the picture would exceed 16 MP or the composite limit; the reply suggests a resolution that fits |
| `look` | `{point_size_px, opacity_percent, colour_mode}` | For this capture only: the clouds' saved look is put back afterwards |
| `fill` | boolean, default `true` | Widen the field until the dots meet at this resolution (section 5.3), capture larger, crop back |
| `plane` | `{at: "front" \| "frame", offset}` | Where the image plane is placed (section 5.4). `front` (default): in front of the model's geometry along the view. `frame`: on the frame's own plane. `offset` moves it further toward the camera (default 0) |
| `background` | `"white"` \| `"transparent"` | Default `"white"` (Adam, 13-Nov-2026). `transparent` only when asked |
| `place` | boolean, default `true` | `false`: write the PNG and return the pixel map only |
| `name` | string | Tail of the Outliner name (section 7) |
| `tag` | string | Default `06__Drawings` |
| `save_path` | string | Default `<job>/01__ReferenceFiles/12__PointCloud__Orthos/<Client>__PointCloudOrtho__NN__<View>__<Name>__<res>mmPx__<dd-Mon-yyyy>.png`, next free NN. Never overwrites |
| `clouds` | ids or names | Default every cloud on show |
| `hide` | `"model"` \| `"none"` \| ids | Default `"model"`: everything but the clouds is hidden for the capture (zero trace) |
| `segments` | number | Only with viewers before 0.14.7: the slab is cut into this many axis-aligned clip boxes along u (section 6) |

## 5. Behaviour

### 5.1 Frame and camera
- `top`: origin `[0, 0, z]`, u = +x, v = +y; the camera looks down -z.
- `wall`:
  - u runs a to b, level; v = +z; the normal points to `face_side`.
  - The origin is `a` at z 0, so u is the distance along the wall and v the height.
- Camera:
  - eye = the centre of `extent` on the plane, plus the normal times (the far edge of `depth` + 50 m); target = that centre;
  - up = v, `perspective = false`;
  - `height` = the v span (times the fill factor, section 5.3).
- **Refuse a perspective camera.** No parameter makes one.

### 5.2 Capture with zero trace
1. Note the user's camera, the clouds' looks and their clip scenes.
2. Hide the model (`hide`) inside an operation that is always aborted.
3. `write_image` on white (ProjectionEngine's `background_mode: :white`), or `transparent: true` when asked.
4. Call the seam's `composite` with the transient clip and look (section 6).
5. Abort the operation, then put the camera and looks back.

Nothing in the model, its undo stack or the cloud records changes.

### 5.3 Dot coverage (measured on Kann)
`composite` draws each point at `pointSizePx × (capture width ÷ viewport width)` pixels. So a dot's size in **mm** is set by the camera's field width ÷ viewport width, not by the resolution:
- an 11.5 m field covered 55% of the pixels;
- a 23 m field at size 10 covered all of them.

With `fill: true`:
1. Estimate the point spacing in the slab (from `napc_box_count` ÷ its area).
2. Widen the field by the factor k that makes the dot at least 1.3 × that spacing.
3. Capture at k × the pixels.
4. Crop the centre back to `extent`.

Report `fill_factor`, `dot_mm` and `coverage_percent` (the share of pixels inside the cloud's footprint that the dots cover). Warn below 95%.

### 5.4 Output and placement
- A PNG on a white background (RGBA only for `background: "transparent"`).
- Placed as a textured face, square to the view, its UVs exact to the pixel map.
- **Where (Adam: "context dependent, leave them in front of the geometry ... they can be switched off if needed"):**
  - `plane.at: "front"` (default): take every shown model entity whose bounds fall inside the extent's footprint, find the one nearest the camera along the view, and place the plane 100 mm in front of it, rounded out onto the 5 mm grid. Kann's plan: above the TERRAIN, the road block and the CAD sheets (it sat at z 11000).
  - `plane.at: "frame"`: on the frame's own plane, for a face not modelled yet.
  - `plane.offset`: further toward the camera.
- Linework drawn over a plane goes 5 mm in front of it, so the white face never hides it and its depth stays on the 5 mm grid.
- Two dictionaries on the group:
  - **`Na__Ortho__Capture`**: PlaneBuilder's keys plus `view`, `resolution_mm`, `frame` (origin and axes in world mm), `extent`, `depth`, `cloud_ids`, `source_png`, `fill_factor`, `coverage_percent`.
  - **`Na__DrawingPlane`**: the same pixel map in the form `na_read_sheets` uses. A later agent can then measure on it without the original call.

### 5.5 Pixel map in the reply
`u = u0 + (col + 0.5) × res`, `v = v1 − (row + 0.5) × res`, with `world = origin + u·x_axis + v·y_axis`.

The handler proves it before replying:
1. Draw two temporary cross marks inside the aborted operation.
2. Capture them without the cloud.
3. Find their pixels; any error over 0.5 px refuses with `operation_failed`.

On Kann the hand-made check landed every cross on its predicted pixel edge.

## 6. Viewer Seam Changes (0.14.7)

`composite` today always draws each cloud with its own saved clip box (`Na__ClipBox.Na__Clip__RenderParams(slot)`) and look. Add to its params, for that render only:
- `clip_override`: an **oriented box** `{origin, x_axis, y_axis, min: [u, v, w], max: [u, v, w]}` in model inches. The engine already takes a clip box per layer. Pass it in the frame by folding the frame into the transform, as `frame` does for slices (`...McpOperations__Frame__.rb`). If the engine's clip test is axis-aligned only, extend `napc` to accept a 4 × 4 clip transform.
- `look_override`: `point_size_px`, `opacity_percent`, `colour_mode`.
- List `ortho` in `NA_FEATURES`.

Why oriented: Kann's boundary walls run 3.76° off the model axes, so each one took four axis-aligned clip boxes, four undo steps and a composite. An oriented slab is one render. Adam agreed the viewer change on 13-Nov-2026 ("Yes support turned clip boxes"). The same oriented box should become a normal clip box in the viewer too (drawn and edited like today's, saved in the cloud's record), so the Ortho tab button and Adam's own viewing can use it.

Until 0.14.7 is loaded the handler falls back to `segments` axis-aligned boxes. Each segment's box encloses its stretch of the slab, so it holds a little more cloud than the slab itself. The handler sets the box through the seam's clip in its own aborted operation, never the user's record.

## 7. Naming, Tag, Undo

- Name: `REF__DrawingPlane__<View>__PointCloudOrtho__<name>`, where `<View>` is Adam's prefix word:
  - `PlanView` for top;
  - `FrontElevation`, `BackElevation`, `LeftElevation` or `RightElevation` for walls and frames, by the face the plane looks at (a plane facing -X is Left).
  - Kann: `REF__DrawingPlane__LeftElevation__PointCloudOrtho__BoundaryWall01__East`.
- Tag `06__Drawings`, at the model root, pinned to identity (`Na__Coordinates`).
- Undo: one router step, `MCP: Point Cloud Ortho Plane (<name>)`, holding only the plane. The capture's own operation is aborted, so the tool is `mutates: true`, `operation: false` (it opens and commits its placement step itself after the aborted capture). It is in `NA_BATCH_FORBIDDEN` like `point_cloud_clip`.

## 8. Reply

```json
{
  "id": 29035267, "name": "REF__DrawingPlane__LeftElevation__PointCloudOrtho__BoundaryWall01__East",
  "png": ".../12__PointCloud__Orthos/Kann__PointCloudOrtho__03__...png", "pixels": [2900, 1500],
  "resolution": 10, "frame": {"origin": [...], "x_axis": [...], "y_axis": [...], "normal": [...]},
  "map": {"u0": -1000, "v1": 11500, "rule": "u = u0 + (col + 0.5) * res; v = v1 - (row + 0.5) * res"},
  "camera": {"parallel": true, "ortho_height": 15000, "eye": [...], "target": [...]},
  "background": "white", "plane_at": "front", "plane_point": [...], "in_front_of": ["TERRAIN"],
  "fill_factor": 2.0, "dot_mm": 126, "coverage_percent": 99.1, "points_drawn": 32460,
  "calibration_px": 0.0, "clip": "oriented (viewer 0.14.7)", "warnings": []
}
```

## 9. Fix in the Same Release: `image_place`

`Na__Handlers__Annotations__ImagePlace` passes `params` (whose `path` is the image file) to `Na__Creation__Prepare`. That reads `path` as an instance path and refuses: `'path' must be an array, got String`, both alone and in a batch.

Fix it the way `image_rectify` does: hand `Prepare` the params without `path`, i.e. `params.reject { |key, _| key == 'path' }.merge('wrap_in' => 'none')`. Do the same for `ApplyCommonProperties`. Also add a schema-level test that every tool whose `path` is a file never reaches `Na__Creation__Prepare` with it.

## 10. Tests

- **Offline (`Tests__BridgeCore`):**
  - frame maths for top, wall (both `face_side`s, `flip`) and frame;
  - the pixel map round trip;
  - the fill factor from a given spacing;
  - file naming with the next free NN;
  - the oriented-box fold into the cloud transform.
- **Viewer suite (`tests/mcp_operations_unit.rb.test`):** `composite` with `clip_override` and `look_override` draws only the slab and puts nothing in the slot's record.
- **Live, in a copy of Kann 64562** (`sketchup_open_window copy_to`), reproducing the hand-made planes:
  - plan `top` z 11000, extent x 2500..17000, y −10500..8500, 10 mm/px, slab z −1000..20000: pixel-for-pixel within 1 px of `Kann__PointCloudOrtho__01`, coverage ≥ 98%;
  - east wall `wall` a (12861.6, 19227.1), b (13642.1, 7344.9), face_side left, extent u −1000..28000, v −3500..11500, depth [900, 700]: one render matching the four-segment composite `...03`;
  - the coordinate matrix: a plane requested on a face inside a moved, rotated group nested three deep lands on that face in world;
  - undo: one Ctrl+Z removes the plane and leaves the cloud records, looks, camera and scene unchanged;
  - `place: false` writes the PNG only;
  - the background is white and the plane lands in front of the TERRAIN (plan) and of any wall geometry (elevation), on the 5 mm grid;
  - the Ortho tab button (section 13) makes the same plane as the MCP call for the same inputs (same PNG bytes, same placement).

## 11. The Agent's Route Afterwards (for the skills)

1. Ask the cloud's source and quality.
2. `point_cloud_ortho_plane` for each view (plan; one per wall).
3. Draw over the planes, 5 mm in front of them: the 2D drafting kit or `geometry_create_lines`. Use Adam's markup as intent, registered to world through model lines in his screenshot.
4. Run the grid check, capture square-on through the same frame, and leave the planes in the model.

Point the 3D skill's `references/point-clouds.md` and the 2D drafting skill's `reading-the-drawing.md` here once it is built.

## 12. Decisions (Adam, 13-Nov-2026)

| Question | Answer | Where it lands |
|---|---|---|
| Textured face or `Sketchup::Image`? | Textured face, **on a white background rather than transparent**: "it makes them easier to work with" | Sections 2, 3, 4 (`background`), 5.2, 5.4 |
| Where does the plane sit? | "Context dependent, leave them in front of the geometry. Currently they can be switched off if needed" | Section 5.4 (`plane.at: "front"`), linework 5 mm in front of the plane |
| Turned clip boxes in the viewer? | "Yes support turned clip boxes" | Section 6, viewer 0.14.7 |
| A button on the Ortho tab? | "Yes add button" | Section 13 |

## 13. The Ortho Tab Button and One Build Path

**One build path, two front doors.** The capture and placement code lives once, in Noble 3D Tools' Ortho module (`34__SourceCode__ToScaleOrthoTextureMaker`), as a new `PointCloudOrtho` file with an MCP entry point (`Na__ToScaleOrthoTextureMaker__McpOperations`). This copies the Component Editor Tools and Element Assembly Studio seams:
- the button calls it directly;
- the MCP handler is thin: it reads lengths and ids, then forwards (AGENTS.md "Adding or Changing a Tool");
- it calls the viewer through its public seam (`Na__PointCloudViewer::Na__McpOperations.Na__PointCloudViewer__McpRead('composite', ...)`). It refuses `unsupported` when the viewer or its `ortho` feature is missing, and the button greys out.

**The button.** On the Ortho tab (Misc Utils > Ortho Reference Planes): **Point Cloud Ortho Plane**, beside the existing capture.
- **Mode:**
  - Plan: drag a rectangle on the ground, or take the current top view;
  - Wall: click two points along the face, then click the side to look from;
  - Face: hover and click a face, reusing `Na__OrthoViewFace`'s align tool and its green highlight.
- **Slab:** behind and in front (mm). The turned clip box is drawn live while these are set, so Adam sees what is kept.
- **Resolution** (mm per pixel), **Fill dots** (on), **Background** (white), **Placement** (in front of geometry / on the face, plus offset).
- **Name:** the tail of `REF__DrawingPlane__<View>__PointCloudOrtho__...`; the view word is filled in from the mode.
- **Make Plane** runs the same code as the MCP call and reports the PNG path, coverage and the plane's name in the dialog's status line.
- **Export**, the existing button, works on these planes unchanged, because they carry the `Na__Ortho__Capture` dictionary.

**Undo and reload.** One "Point Cloud Ortho Plane" step from either door. A change to the shared code needs Noble 3D Tools' Reload Plugin Data as well as this plugin's.

---
END OF FILE
