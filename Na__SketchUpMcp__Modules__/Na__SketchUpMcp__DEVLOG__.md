# Na SketchUp MCP - Development Log
# =============================================================================

## Version History

## Na SketchUp MCP | Version 1.0.35 - 13-Nov-2026 - Turned Clip Boxes (point_cloud_clip frame); Ortho Planes From the Clip Box

- **What Adam asked for.** After 1.0.34's ortho planes (turned clips for one capture only), asked whether to build a turned clip box kept in the Point Cloud Viewer for his own viewing: "Yes, build it". Viewer 0.14.8 keeps one (the Clipping tab's Turn row, Turn to Two Points, Level); this release lets agents read, set and use it.
- **`point_cloud_clip` takes `frame`** (action box only): `min` and `max` are then in the frame (origin with angle, x_axis and y_axis, or a group's id, read as a slice's frame), giving a TURNED clip box saved in each cloud's record, ONE undo step as before. A frame along the model axes gives a level box. Refused `unsupported` without the viewer's `turned_clip` feature (0.14.8), and refused with any other action. `point_cloud_state` reports a turned box under `clip.turned` (origin, unit axes, plan angle, its own min, max and size) beside the level box round it; clip scenes the same.
- **`point_cloud_ortho_plane` view `clip`:** the active cloud's clip box (or `clouds[0]`'s), level or turned: the picture square to its front face (its own -y side, looking along its own +y), its width and height the extent and its depth the slab, unless `extent` or `depth` say otherwise. A box turned to a wall in the viewer gives that wall's elevation in one call. Needs Noble 3D Tools 0.9.49 (`__FrameClip`), refused `unsupported` without it.
- **Where.** `Handlers__PointCloud` (`na_clip_frame`; the Clip handler refuses `frame` off action box; `NA_ORTHO_VIEWS` gains clip; the Ortho Plane handler's `from_clip`); the registry (`point_cloud_clip`: `frame`, description 1225 characters; `point_cloud_ortho_plane`: view clip, description 2033 characters); `property_since` `point_cloud_clip.frame` and `point_cloud_ortho_plane.view=clip` at 1.0.35; AGENTS.md; the agent guide.
- **Versions.** `bridge_version` and `server.version` are `1.0.35`. 77 tools.
- **Verified offline:** ValidateApiUsage passed (77 tools; the Ortho module checked as a partner root); RunRubyChecks 55/55 files compile, BridgeCore 190 of 190; PythonServer 65 OK; `--check` 77 tools on 1.0.35; `node --check`. The viewer's turned clip box suite 20 of 20 and seam suite 87 of 87 (0.14.8); the ortho core 21 of 21 (two new checks: a box turned along Kann's east wall gives that wall's elevation frame, slab and extent; a level box gives a Front elevation; no box or an unknown cloud refused).
- **Not yet verified:** any of it live (no SketchUp was driven: Adam tests in SketchUp); the seam's `clip_box` with a frame and `view: clip` are proven by compile, the API check and their parts' suites, not called end to end.

### Validation Checklist
- [ ] Reload Plugin in the Point Cloud Viewer, Reload in Noble 3D Tools, then Reload Plugin Data in Na SketchUp MCP (or restart SketchUp): the MCP status dialog shows bridge 1.0.35.
- [ ] Restart the MCP client, then ask an agent to "turn the clip box along the east boundary wall": `point_cloud_clip {action: box, frame: {...}}` turns it; the Clipping tab shows the angle.
- [ ] Ask for "an ortho plane of the clip box": `point_cloud_ortho_plane {view: clip}` places the wall's elevation in front of the model.

## Na SketchUp MCP | Version 1.0.34 - 13-Nov-2026 - Point Cloud Ortho Planes (point_cloud_ortho_plane); image_place Fixed

- **What Adam asked for.** On Kann 64562 (the upper garden and its two boundary walls, a cloud derived from Google Earth) the route that worked was "Pointcloud -> Scaled 2D Image -> 2D Linework -> (Eventually 3D)": an aligned parallel camera, clip boxes, bigger and opaque points, a picture placed in the model as a plane, linework drawn over it. Image planes in the model "worked EXCELLENTLY for me to in model reference and check your workings". He agreed a tool for it (spec `85__Docs__AgentReference/Specs/Na__SketchUpMcp__Spec__PointCloudOrthoPlane__.md`) and decided: a textured face on white, in front of the geometry, turned clip boxes in the viewer, and a button on the Ortho tab. Then: "Build point_cloud_ortho_plane tool and Ortho button".
- **`point_cloud_ortho_plane` (new tool; 77 tools).** One call makes the scaled, square-on picture and places it:
  - **what it is square to:** `view` (top, bottom, front, back, left, right, through `origin`), `wall` (`a` and `b` along the face in plan and `look_from` on your side: the picture runs left to right as seen from there, `v` is the model's z) or `frame` (`origin`, `x_axis` = picture right, `y_axis` = picture up);
  - **`extent {u, v}`** from the origin (a wall's default: its length plus 500 each end, and as high as the cloud reaches, from a histogram's 1st and 99th percentiles plus 500), **`depth [behind, front]`**, the slab kept, as a turned clip box for this capture only (default 1000 each), **`resolution`** (default 10 mm a pixel);
  - **`fill`** (default true) sizes the dots so they meet: `ceil(1.3 x spacing / resolution)` pixels, the spacing read from the sparse quarter of the slab (the 25th percentile of points in 250 mm cells, so thin areas don't speckle); `dot_px` sets them by hand; `look` sets size, opacity and colour for this capture;
  - **zero trace:** the model is hidden inside an undo operation that is aborted, the camera is put back, the clouds' looks and clip boxes are never touched, and two crosses drawn on white prove the pixel map (`calibration_px`, refused above 1.0 px);
  - **the PNG** goes in the job's `01__ReferenceFiles/12__PointCloud__Orthos` (the first `NNNNN__` folder above the saved model; beside a loose model in `PointCloudOrthos`; the temp folder, with a warning, for an unsaved one) as `<Client>__PointCloudOrtho__NN__<View>__<name>__<res>mmPx__<dd-Mon-yyyy>.png`, never over a file (`save_path` to choose);
  - **the plane:** a textured face on white (`background: transparent` on request), edges hidden, facing the camera, in front of the model's geometry along the view (24 x 24 ray tests from the slab's front, existing `REF__DrawingPlane__` planes skipped, 100 mm clear, its depth rounded out to a whole 5 mm from the model origin), or on the frame itself (`plane {at: frame}`), plus `offset`; named `REF__DrawingPlane__<View>__PointCloudOrtho__<name>` (PlanView, UnderView, Front/Back/Left/RightElevation; Left faces -X) on `06__Drawings`, carrying the Ortho tab's `Na__Ortho__Capture` data, so its Export works on it; ONE undo step, "Point Cloud Ortho Plane". `place: false` writes the PNG only.
  - **reply:** the PNG, pixels, frame, the pixel map rule, camera, dot size, spacing, points drawn, pixels covered, `calibration_px`, `turned_clip`, the plane's name, depth and what it sits in front of.
- **One build path, two front doors.** The capture and placement live once, in Noble 3D Tools' Ortho module (`34__SourceCode__ToScaleOrthoTextureMaker/..._PointCloudOrtho__.rb`, `Na__ToScaleOrthoTextureMaker__PointCloudOrtho__Make`); the handler only reads lengths and forwards, and the Ortho tab's new Point Cloud Ortho Plane button (Noble 3D Tools 0.9.48) calls the same code. It needs Na Point Cloud Viewer 0.14.7 (`ortho` in its features: per-render turned clips and looks, and `spacing`), and refuses `unsupported` naming the version without it.
- **`image_place` fixed.** It handed its params, whose `path` is the image file, to `Na__Creation__Prepare`, which read `path` as an instance path and refused (`'path' must be an array, got String`), alone and in a batch. It now passes them without `path` to `Prepare` and `ApplyCommonProperties`, as `image_rectify` does. Found on Kann, where the wall planes had to be placed by `ruby_eval`.
- **Where.** `Handlers__PointCloud` (new region Ortho Plane: `Na__Handlers__PointCloud__OrthoPlane`, `na_ortho_*`; `NA_ORTHO_VIEWS`, `NA_ORTHO_DEPTH_MM`, `NA_ORTHO_WALL_MARGIN_MM`); `Handlers__Annotations` (`image_place`); the router and `NA_BATCH_FORBIDDEN` (Ruby and Python: the capture's aborted operation can't nest in a batch); the registry (description 1887 characters); ValidateApiUsage (`NA_ORTHO_ROOT`, the Ortho module checked as a partner root); the Python server test (77 tools); AGENTS.md; the agent guide; the spec.
- **Versions.** `bridge_version` and `server.version` are `1.0.34`. 77 tools. A new tool, so no `property_since` keys.
- **Verified offline:** ValidateApiUsage passed (77 tools, 286 dependencies; 2 Ortho module files checked, 12 defining); RunRubyChecks 55/55 files compile, BridgeCore 190 of 190; PythonServer 65 OK; `--check` 77 tools; `node --check`. The shared core's own suite 19 of 19 (Noble 3D Tools 0.9.48) and the viewer seam 87 of 87 (0.14.7).
- **Verified live** (a copy of Kann 64562 in its own window, the plugins reloaded there, closed afterwards):
  - **plan**, the hand-made upper garden plane's extent at 10 mm a pixel with its dot size (12.59 px): 1450 x 1900 px, pixel-identical to the hand-made `Kann__PointCloudOrtho__01` (correlation 1.0, mean difference 0.0); calibration 0.0 px;
  - **the east and west boundary walls** (`wall`, 3.76 degrees off the axes, depth [900, 700]): one render each, with a turned clip, matching the four-segment composites made by hand; Left and Right elevations named as Adam's face words; calibration 0.0 px;
  - **zero trace:** after four planes, the camera, scene, clip boxes and looks as before and no root left hidden; one Ctrl+Z removed only the last plane;
  - **the planes:** on `06__Drawings`, edges hidden, the texture 2900 x 1500 for 29 x 15 m, the `Na__Ortho__Capture` data read by the Ortho tab's Export;
  - **the 5 mm grid:** a plan plane first landed at z 16905.6 (rounded from the slab, not the model origin); fixed and rerun: z 16905.0.
- **Not yet verified:** Adam's window still runs bridge 1.0.33 until Reload Plugin Data; a fresh agent session's tool list (a running server keeps the list it started with); `image_place` live after the fix; a plane made with a group open.

### Validation Checklist
- [ ] Reload Plugin Data in Na Point Cloud Viewer, Noble 3D Tools and Na SketchUp MCP (or restart SketchUp): the MCP status dialog shows bridge 1.0.34.
- [ ] Restart the MCP client: `point_cloud_ortho_plane` is listed (77 tools).
- [ ] Ask an agent for a plan ortho of a cloud: `REF__DrawingPlane__PlanView__PointCloudOrtho__<name>` appears on `06__Drawings`, white, in front of the terrain, its PNG in the job's `01__ReferenceFiles\12__PointCloud__Orthos`.
- [ ] One Ctrl+Z removes the plane ("Point Cloud Ortho Plane") and nothing else; the clouds' clip boxes and looks are as they were.
- [ ] `image_place` places a PNG without the "'path' must be an array" refusal.

## Na SketchUp MCP | Version 1.0.33 - 12-Nov-2026 - Flatten a Photo onto a Rectangle (image_flatten)

- **What Adam asked for.** On Kann 64562 an agent began scaling a door off a site photo by eye, to find where its bottom was (the CAD elevation stops on a sloping cut). Adam stopped it: "build a MCP tool that allows you to flatten out images, so you know the width of the window opening so you can draw a rough theoretical rectangle, warp the window to suit and create a image mapped to a rectangle to draw over, similar to sketchups texture markers".
- **`image_flatten` (new tool; 76 tools).** SketchUp's free-pin Position Texture then Make Unique Texture, done by a tool:
  - `corners`: the rectangle's four corners in the photo (the texture pins), as viewers show it; `rectangle`: where they go (the origin corner, `x_axis`, `y_axis`, the known `width`, and `height` when known);
  - without `height`, it is solved from `points` (known positions with their pixels: `at` from the origin corner, or `world`) by least squares; with no points it is estimated from the corners' perspective (Zhang and He, 2007) and flagged as rough;
  - the photo's pixels are warped through the fitted homography into a new square-on PNG (`Na__PlanGeometry__WarpPixels`: bilinear, alpha 0 outside the photo), never written over: `save_path`, else the job folder's `01__ReferenceFiles/11__Photos__Flattened` (the first `NNNNN__` folder above the saved model), else `91__UserConfig__LocalOnly/PhotoPlanes`; named `<name>__<dd-Mon-yyyy>.png`;
  - placed as `REF__PhotoPlane__<name>`: one face over the rectangle plus `margin`, mapped plainly (front and back, four pins), its edges hidden, opacity 0.75, and the rectangle's outline in a group of its own (`Rectangle__<w>x<h>`); the image is never mirrored against the photo, and the face's front looks back at the camera;
  - reports the fit at every pin and point in pixels and on the plane, the height and where it came from (the perspective estimate and its focal length beside it), the output's pixel size and coverage, and SketchUp's own mapping read back through a UVHelper; the source, pins, rectangle and fit are kept on the group (`Na__SketchUpMcp__PhotoPlane`).
- **SketchUp facts found building it (2027, live):** `Sketchup::ImageRep#data` is top row first, BGR(A) on Windows; `load_file` reads PNG and JPEG but refuses WebP ("failed to load image"); it ignores a JPEG's EXIF orientation (a portrait phone photo loads 4000 x 3000), so the tool reads the orientation itself (`Na__PlanGeometry__JpegOrientation`) and turns upright pins back to raw pixels (`__UprightToRaw`); a pure-Ruby bilinear warp runs at about 1.4 s a megapixel, so the output is capped at 4 MP by default (`max_pixels`, up to 16 MP).
- **Where.** `Na__PlanGeometry` (new region Photo Flattening: `RectangleAspect`, `SolveRectangleHeight`, `JpegOrientation`, `UprightToRaw`, `WarpPixels`; `na_dot3`, `na_cross3`); `Handlers__PhotoReference` (`Na__Handlers__PhotoReference__Flatten` and its `na_flat_*` helpers); the registry; the router; the agent guide; AGENTS.md.
- **Versions.** `bridge_version` and `server.version` are `1.0.33`. 76 tools. A new tool, so no `property_since` keys.
- **Verified offline:** ValidateApiUsage passed (76 tools, 280 dependencies); RunRubyChecks 55/55 files compile, BridgeCore 190 of 190 (11 new: a rectangle's proportions in perspective recovered to 1e-6 with its focal length; a square-on view keeps the side ratio; crossed corners caught; an unknown height solved to under 0.01 from four points; an identity warp copies, a warp off the photo is transparent, half a pixel blends two; EXIF orientation in both byte orders, none, and upright-to-raw for orientations 3, 6 and 8); PythonServer 65 OK (tool count 76); `--check` 76 tools.
- **Verified live** (a copy of Kann 64562 in its own window, zero-trace trials, closed afterwards): the rear door under the oriel from the 4000 x 3000 site photo (ultra-wide, the door near its edge), 4 corners and 12 glazing bar crossings from the CAD: height solved 2765.8 (threshold 2725.2), fit 0.94 px rms, worst 7.1 mm on the plane; output 396 x 905 px at 3.4 mm a pixel; SketchUp's mapping 0.0 px off; the CAD's yellow linework sits on the photo's bars. Given height (2765) and perspective only (2468.1, 11 % short: weak perspective on a narrow door near the edge of an ultra-wide photo); the default folder with no job folder; WebP, crossed corners and an existing `save_path` refused with the fix named. Coordinate matrix: built inside a group moved and rotated, nested three deep with a non-uniform scale, the face and outline land on the same world corners as at the root (to 0.01 mm).
- **Verified live in Kann itself** (after Reload Plugin Data in Adam's window, one batch, one undo step "Door under the oriel: flattened photo and remainder linework"): from the original JPEG (EXIF orientation 6, handled) the same fit as the trial (height 2765.8, 0.94 px rms, mapping 0.0 px); the PNG written to `64562__Kann__Whitecard/01__ReferenceFiles/11__Photos__Flattened/Front__DoorUnderOriel__12-Nov-2026.png`; the door's remainder drawn over it in red (`SUB__LineworkDetailing__Front__DoorUnderOriel`, 30 edges meeting the CAD's lines where its cut stops). After the run the saved path's slashes were made consistent (`na_flat_job_folder`), live at the next reload.
- **Not yet verified:** a fresh agent session's tool list (a running server keeps the list it started with; `su_bridge.py call image_flatten` reaches the bridge meanwhile).

### Validation Checklist
- [ ] Extensions > Na SketchUp MCP > Reload Plugin Data: the status dialog shows bridge 1.0.33.
- [ ] Restart the MCP client: `image_flatten` is listed (76 tools).
- [ ] In Kann, `REF__PhotoPlane__Front__DoorUnderOriel` shows the door square-on behind the yellow CAD lines; its PNG is in `01__ReferenceFiles\11__Photos__Flattened`.
- [ ] Right-click the photo plane > Texture > Position: the four pins sit on the image's corners (a plain mapping, not distorted).
- [ ] One Ctrl+Z removes the photo plane ("MCP: Flatten Photo onto a Rectangle").

## Na SketchUp MCP | Version 1.0.32 - 12-Nov-2026 - Agent Outliner: Group by Category for Agents (agent_outliner category_tree)

- **What Adam asked for.** After the Agent Outliner's new Group by Category view ("Create a group by category that appears the same as the group by tag so coloured regions"), asked whether agents should read it too: "Yes, add it".
- **`agent_outliner` gains `category_tree`** (Agent Outliner 0.1.18 does the work in its seam, `Na__Payloads.Na__Payload__CategoryTree`):
  - the view's structure: each naming category from Adam's Configure tab holds its prefixes, both in his Configure order; each prefix a card of the objects whose names start with it, as trees; No Standard Name last; a prefix no longer in Configure under Other; Elevation Faces never (a face is a segment, not a prefix);
  - Tree by Tag's rules with the prefix in place of the tag: an object heads its prefix's card unless something above it carries the same prefix; No Standard Name lists only top-level unnamed objects; a child with another prefix carries its own `prefix` and heads that card too;
  - each card: prefix, label, category, colour, meaning, `objects_named`, `top_objects`, `items`; each object as in `tag_tree`;
  - `prefix` reads one card (any case, a trailing `__` allowed, "No Standard Name" for the unnamed card), `depth` 0 to 8 (default 1, or 3 with `prefix`), `limit`.
- **Where.** The registry (`agent_outliner`: the action, `prefix`, `depth` now says both views; a description clause, 2015 characters), `property_since` (`agent_outliner.action=category_tree`, `.prefix` at 1.0.32), the handler's `NA_READ_ACTIONS`, the agent guide.
- **Versions.** `bridge_version` and `server.version` are `1.0.32`. 75 tools.
- **Verified offline:** BridgeCore 179 of 179 (the registry offers exactly the handler's actions); PythonServer 65 OK (the action, `prefix`, the description length asserted); ValidateApiUsage passed; the Agent Outliner suite's 9 `category_tree` checks and 4 deliberate faults (its own devlog, 0.1.18).
- **Not yet verified live.** Reload Plugin Data in Noble 3D Tools and in the MCP, then a fresh agent session (a running server keeps the tool list it started with).

## Na SketchUp MCP | Version 1.0.31 - 12-Nov-2026 - Agent Outliner: Tree by Tag for Agents (agent_outliner tag_tree)

- **What Adam asked for.** With a screenshot of the Agent Outliner's new Tree by Tag view on Corrett 1.0.1: "Update the MCP tools and the 3D Modeling expert skill to ensure agents can also reference and see this and this structure as i belove this is a powerful way to categorise and group things".
- **`agent_outliner` gains `tag_tree`** (Agent Outliner 0.1.17 does the work in its seam, `Na__Payloads.Na__Payload__TagTree`):
  - the same structure as the view: tag folders (nested ones nest), then tags, then each tag's objects as trees; levels by name, Untagged first, tags with no objects left out;
  - an object heads its tag's card unless something above it carries the same tag; Untagged lists only top-level untagged objects (an untagged part of a tagged group is listed inside that group); a child on another tag carries its own `tag` and heads that tag's card too;
  - each card: tag, label, colour, shown, folder, `objects_on_tag`, `top_objects`, `items`; each object: id, name, type, `tag` (only when on another tag), `hidden`, `within` (where a card's top object sits), `children`, `inside` (a count past `depth`), `more`;
  - `tag` reads one card (any case; Untagged for the untagged card), `depth` 0 to 8 (default 1, or 3 with `tag`), `limit` objects in all (default 300); `listed` and `truncated` say what was cut.
- **Where.** The registry (`agent_outliner`: the action, `tag` and `depth`, a shorter description line for tags and pictures to stay under 2048 characters), `property_since` (`agent_outliner.action=tag_tree`, `.tag`, `.depth` at 1.0.31), the handler's `NA_READ_ACTIONS`, the agent guide (the table and "Start a job from Adam's notes").
- **Versions.** `bridge_version` and `server.version` are `1.0.31`. 75 tools.
- **Verified offline:** BridgeCore 179 of 179 (the registry offers exactly the handler's actions); PythonServer 65 OK (the action, `tag` and `depth` asserted in `test_agent_outliner_tools`); ValidateApiUsage passed; the Agent Outliner suite's 10 `tag_tree` checks and 4 deliberate faults (its own devlog, 0.1.17).
- **Not yet verified live.** Reload Plugin Data in Noble 3D Tools and in the MCP, then a fresh agent session (a running server keeps the tool list it started with).

## Na SketchUp MCP | Version 1.0.30 - 12-Nov-2026 - Sketch and Site Tools: Seven New Tools So a Site Photo Never Becomes a Spec

- **What Adam asked for.** After the Corrett 64610 planting bed failed ("You failed, and badly": an agent spent three rounds turning a drone photo into a bed, and he redrew it himself in twelve minutes as plain parallel offsets of his terrace edge): "Build all of the Proposed MCP Tools and update your skills to intercept earlier on. Precision IS need on CAD / SketchUp Reference Geom given / Photoplanes etc but if I give a site photo its just a reference and the agent must ask for more early on rather than trying to be too surgical on a site photograph." The six tools came from the job's audit (the 3D skill's `learning/retrospectives/2026-11-12__Corrett-64610__PlantingBed__Failure.md`).
- **The seven tools (68 -> 75):**
  - `sketch_read`: Adam draws rough lines and notes and selects them; the agent gets them as world polylines split into straight runs and fitted arcs, a `clean_path` resampled to his segment budget, and the numbers in his notes ("1100", "1.1m", "150 wall") with the line each sits beside. Groups are read into at any depth.
  - `input_pick`: Adam clicks points in SketchUp with full inference (a plain SketchUp tool: red rubber band, Backspace, Enter or double-click, Esc); `round_to` snaps to his 5 mm grid. `wait` is polled by the server.
  - `proposal_preview`: the gate. A red 2D proposal (`PROPOSAL__<name>` at the root, labels for the numbers, `z` to lift it above the paving), a top-view picture, the question posted beside it in his Agent Outliner with the picture, `wait` until he answers there, `status`, `clear`, `list`.
  - `geometry_offset_band`: a rule into geometry in one call. Bands at parallel offsets from a path (`path_points`, or `path_ids` for one drawn line): solids (`hollow` ring walls, `end_inset`), or lines (`line_only`); ends square or on `start_line` / `end_line`; arcs offset radially so bands stay concentric; softened, edge-painted, and every solid manifold or nothing is built.
  - `model_snapshot` / `model_diff`: record objects (bounds, volume, counts, edge and face material tallies, plan footprint by level, children) and measure two versions against each other: plan overlap (IoU), outline distance, bounds moved, volume, which edge colours changed; children paired by name, then by overlap. Live or from a saved snapshot of another window or moment.
  - `image_rectify`: a site photo laid flat on the ground (or any plane) by a homography from four or more pixel/model pairs, for context only, with the fit in pixels and in ground distance.
- **Where the code is.**
  - `06__Plugin__BridgeHelpers/...PlanGeometry__.rb` (`Na__PlanGeometry`): all plan maths, pure Ruby on plain arrays, so the offline suite checks it.
  - `10__BridgeHandlers/...SketchIntake__.rb`, `...OffsetBand__.rb`, `...ModelDiff__.rb`, `...PhotoReference__.rb`; routes and `NA_BATCH_FORBIDDEN` (input_pick, proposal_preview) in the CommandRouter; requires in CoreAppLoaders.
  - `ToolRunner.na_wait`: `input_pick` / `proposal_preview` `wait` polls the bridge every 0.5 s / 2 s until done, an Agent Outliner notice, or `wait_s`. Never inside SketchUp.
- **Found and fixed while testing.**
  - Whole-number input fell into Ruby integer division (a 1,000 square read as 0.8 m2): every vector helper returns floats.
  - A split could leave an arc's last facet plus the tangent line after it as one 17.8 m arc within 15 mm: an arc must now have even spacing (no segment over three times the median). A regression check bites when the rule is removed.
  - Rounded `clean_path` points 0.1 mm apart made SketchUp refuse the face ("Duplicate points"): paths and outlines drop points closer than 0.5 mm / 0.05 mm.
  - `Group#volume` is in the parent's units: a band inside a scaled group now reports world volume.
- **Versions.** `bridge_version` and `server.version` are `1.0.30`. 75 tools. New tools, not new parameters, so no `property_since` keys.
- **Verified offline:**
  - ValidateApiUsage passed (75 tools, 273 dependencies, 55 Ruby files).
  - BridgeCore 179 of 179 (30 new Plan Geometry checks: chaining and snap, circle and run fitting, the budget, clean paths, mitred and radial offsets, caps, insets, slanted and far end lines, refusals, rings, self-crossing, homography and inverse, clipping, footprint overlap with holes, outline distance).
  - PythonServer 65 OK (4 new: the pick wait polls with `result` until done and never sends `wait_s` to SketchUp; it gives up at `wait_s`; the proposal wait returns on Adam's answer; both are refused in a batch). `--check` 75 tools. `node --check` passed.
- **Verified live (a copy of Corrett 1.0.1 and a blank template, each in its own window, closed after):**
  - `geometry_offset_band` along Adam's terrace edge, ends on y 19438 and x 11790, wall `0-1270 hollow 150`, bed `150-1120 end_inset 150`, lawn line at 2300, rebuilt his redraw: wall 531 L (his 524), bed 874.4 L (his 873.5); `model_diff` plan overlap 98 %, outlines median 2 mm apart (132 mm at most, where his ring narrows at the east end).
  - The same bands built at the root and inside a moved, rotated, non-uniformly scaled group three deep: identical world vertices (404 of 404, 0.0 mm) and volumes.
  - `sketch_read` of lines drawn inside that group: arc centre (20000, 5000), radius 3000.0, sweep 90.0, then the 2,000 straight; a freehand arc drawn at 4,500 +/- 6 read as 4,498.6; the note "lawn 1100 beyond" gave 1100 and its nearest line; a dimension gave its world length 1100 (its text, measured in the scaled group, says 608).
  - `proposal_preview` with a rotated group open landed on its world points; `ask` posted the question and picture in the Agent Outliner; a reply written through the Outliner's own `Na__Notes__Comment` (by: user) was picked up by the server's real `na_wait` 4.2 s later.
  - `input_pick`: two clicks through the tool's own InputPoint picking at real screen positions, Enter: points back, rounded to 5, Select tool restored; Esc: "cancelled".
  - `image_rectify` of the Corrett drone photo on the terrace plane (12 pairs projected through the camera fitted for the job): fit 0.0 px, SketchUp's mapping read back through a UVHelper 0.0 px off: four pins give a true perspective mapping. The photo's bed and bridge sit under Adam's ring.
  - Refusals read right: two lines given as `path_ids`, `hollow` on a closed path, an offset folding inside a tight curve.
- **What offline cannot prove:** Adam's real clicking and typing in `input_pick` (simulated through the tool's own callbacks), and his Agent Outliner reply typed in the dialog (simulated through its note writer).

### Validation Checklist

- [ ] In each SketchUp window: Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.30), then restart the MCP server in Claude (the new wait loop is server code).
- [ ] Draw a rough line and a note ("1100 bed") anywhere, select both, ask an agent to `sketch_read` them: it should say the line's runs and 1100 back to you.
- [ ] Ask an agent to `input_pick` two points: click them (Backspace, Enter, Esc all work), and it should have them.
- [ ] Ask an agent for a `proposal_preview` with a question: answer it beside the PROPOSAL__ object in the Agent Outliner, and the agent should carry on.

## Na SketchUp MCP | Version 1.0.29 - 11-Nov-2026 - Agent Outliner: Sessions Started Before the Update Hear Adam Too

- **What happened.** At 13:58 Adam reloaded Telfer-Smith (bridge 1.0.28, Agent Outliner 0.1.9), wrote "Can you see now? if so send screenshot" and pressed Send. The status line said "Sent: agents working in this window see it on their next SketchUp call. Last agent call 13:57:24", but nobody answered. "Nope nothing". Two causes:
  - **No agent was calling SketchUp.** The notice rides on an agent's next call, and an MCP server cannot wake an idle Claude session. The "last agent call" was the bridge starting (`bridge_start`). The fix is in the Agent Outliner (0.1.10) and the 3D skill's watcher.
  - **Every running session had the old server.** A Claude session started before 1.0.28 runs the old ToolRunner, which drops the `outliner` key. A busy agent would not have seen it either until its client restarted.
- **The fix here: a copy for older servers.** From 1.0.29 the server says in every request that it shows the notice itself (`features: ["outliner"]`, `BridgeClient`).
  - For a request without that, the router (`na_with_notice(response, command, ctx, request)`) also adds the notice as one warning line, which every server already passes on. On an error it goes into the error's details.
  - The line comes from `Na__Handlers__AgentOutliner__NoticeLine`, e.g. `Adam WROTE TO YOU in the Agent Outliner (3 waiting, model chat, 2 min): "Can you see now? ..." Read it before your next change: agent_outliner {action: "inbox"}; then reply or acknowledge.`
  - So once a window's bridge is reloaded, every session working there hears him on its next call, with no client restart. A 1.0.29 server gets it once, first in the JSON, as before.
- **Answered in Telfer.** A read-only check of Telfer (pid 856288, bridge 1.0.28) showed the notice on the raw response: 3 waiting, his 13:58 message first. A screenshot of his current view went to his Model Chat as a `comment` (not `reply`, so his 13:31 lantern instruction stays unread for the orangery session).
- **Versions.** `bridge_version` and `server.version` are `1.0.29`. Still 68 tools.
- **Validation:**
  - ValidateApiUsage passed.
  - BridgeCore 149 of 149 (3 new: the warning line and error details for a request without features; once only for one with them; the line's wording).
  - PythonServer 61 OK (1 new: requests carry `features: ["outliner"]`).
  - `--check` 68 tools; `node --check` passed.
  - The Agent Outliner's suite 254 of 254, and 18 of 18 deliberate faults caught.
- **Live, in a throwaway template window (pid 863908, closed after):**
  - a watcher (`outliner_watch.py --who "Claude (wake test)"`) was running when a message was sent through the dialog's route. Send said "Sent: the agent working here sees it on its next SketchUp call (last call 14:05:08); 1 waiting agent (Claude (wake test)) wakes now.", and the watcher ended, re-invoking this session;
  - **this session's own MCP server, still 1.0.27,** showed it in `sketchup_status` as `"warnings": ["Adam WROTE TO YOU in the Agent Outliner (1 waiting, model chat, just now): \"Wake test: can you see this?\" ..."]`;
  - the 1.0.29 server had it first in the JSON and no warning copy;
  - `acknowledge` cleared it.

### Validation Checklist

- [ ] In each SketchUp window: Noble 3D Tools > Reload Plugin Data (Agent Outliner 0.1.10), then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.29). Agents already running then hear you on their next call; no client restart is needed.
- [ ] Send while no agent is working: the line says "no agent is working here ... or watching" (amber), so you know to prod one in Claude.
- [ ] Ask an agent to leave its inbox watcher running when it stops, then Send. The line says "1 waiting agent (Claude (...)) wakes now", and the agent answers.

## Na SketchUp MCP | Version 1.0.28 - 11-Nov-2026 - Agent Outliner: Send Reaches the Agents Working in the Window

- **What Adam asked for.** "Should the Send button in the plugin not do that?", after his 13:15 model chat message on Telfer-Smith 64481 waited unread while the agent made about 15 SketchUp calls. The chat was pull-only: an agent heard him only when it thought to call `agent_outliner`. Then: "Add the ability for Claude to share images back to me ... may require a second cache folder for incoming images". The dialog's side is Agent Outliner 0.1.9 (Noble 3D Tools 0.9.41).
- **The waiting notice.** While anything in the Agent Outliner waits for an agent (Adam's comment, a For Agent / Question / Check This flag), every tool result carries `outliner`:
  - `waiting` (how many), `from`, `at`, `ago`, `where` ("model chat" or "<name> (id N)"), `text` (the latest message, first 120 characters), `pictures` and `threads` when there are any, `kind` for a flag;
  - `read`: `agent_outliner {action: "inbox"}`, and a `note` saying to read it before the next change, then reply or acknowledge.
  - It goes **first** in the result's JSON, so an agent reads it before the result and the 45,000 character cap never cuts it; on an error it is the last line, `Outliner: {...}`. `sketchup_status` and `batch_execute` carry it too.
  - **Silent when nothing waits**, and never on `ping` or `api_probe`. A reply or `acknowledge` ends it at once (the edit's own result already has none). So does undo of his message.
- **Cheap.** The Agent Outliner works it out (`Na__AgentOutliner__McpNotice`, cached per model) only when a note is written, an agent acknowledges, undo, redo or an abort happens, the standards are saved, or an object it counted is gone. Measured live: 8 microseconds a call from the cache; 1.7 ms to work it out again in a model of 3,001 objects.
- **Where:**
  - `Handlers__AgentOutliner`: `Na__Handlers__AgentOutliner__Notice(model)` forwards to the seam. nil without the Agent Outliner, with one older than 0.1.9, or on any fault: no notice, never an error;
  - `CommandRouter`: `na_with_notice` puts it on every response, the two error paths included;
  - `ToolRunner`: `na_with_notice` / `na_notice` put it first, and `na_error_result(notice:)` as the last line.
  - **Both directions stay compatible:** a bridge before 1.0.28 sends no `outliner`, so nothing is added; a server before 1.0.28 ignores the key.
- **Pictures back to Adam.** `agent_outliner_edit comment` / `reply` with `images` (since 1.0.26) now copy into their own folder, `ChatFromAgents`, named `agt_...`, beside his `ChatCache`. The description says to save a `view_capture` with `save_path` first: the server deletes an unsaved capture once it is inlined.
- **Versions.** `bridge_version` and `server.version` are `1.0.28`. Still 68 tools; no new parameter, so no `property_since` key.
- **Validation:**
  - `ValidateApiUsage` passed (the Agent Outliner seam checked).
  - `RunRubyChecks`: 50 of 50 compile. BridgeCore 146 of 146, 8 new: no Agent Outliner, no notice; the seam's answer passed on; an empty answer, a fault or a seam without `McpNotice` (0.1.8) gives none; `na_with_notice` on a tool but not on ping or api_probe; an error response through `Dispatch` carries it, ping does not.
  - PythonServer: 60 OK, 4 new: the notice leads entity_query, sketchup_status and batch_execute results; it ends an error; it survives the text cap; an older bridge gives none and no error.
  - `--check`: 68 tools at 1.0.28. `node --check` passed.
  - The Agent Outliner's suite: 249 of 249, and 16 of 16 deliberate faults caught.
- **Live, in a throwaway window** (a copy of the Simple template, pid 754708, opened and closed by the session; never Adam's models):
  - both Reload Plugin Data;
  - an empty model: no notice;
  - a message sent through the dialog's own `comment` route: Send said "Sent: agents working in this window see it on their next SketchUp call. Last agent call 13:49:44." The next `model_info` led with the notice, and an `entity_get` error ended with it;
  - `outliner_watch.py` woke on it;
  - a `view_capture` sent back with `reply`: it landed as `ChatFromAgents/agt_20261111_135145_5413.png`, and the reply cleared the notice;
  - `acknowledge` cleared a second message; `model_undo` cleared a third.
  - All through this folder's 1.0.28 server over stdio.
- **Seen, not caused by this change:** that `view_capture` of a 640 x 400 view took 70.0 s inside SketchUp (its own log line: a new window drawn in the background). The next connection was reset once (`connection_lost` during the `property_since` ping), then every call worked.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) in each session, so its server is 1.0.28 (`sketchup_status` shows `"version":"1.0.28"`).
- [ ] In each SketchUp window: Noble 3D Tools > Reload Plugin Data (Agent Outliner 0.1.9), then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.28). The Telfer window is still on 1.0.24.
- [ ] Type in the Model Chat while an agent is modelling, and press Send. The status reads "Sent: agents working in this window see it on their next SketchUp call", and the agent should mention your message within a call or two.
- [ ] Ask an agent for a screenshot in the chat: the picture appears in the Chat tab, and Settings lists the "Pictures agents sent" folder.

## Na SketchUp MCP | Version 1.0.27 - 11-Nov-2026 - Entity Studio: Every Window, Door and Cabinet

- **What Adam asked for:** "the ultimate MCP to allow agents to interface with the tool and to create, edit and maintain parametric external doors, windows, cabinets etc using the tools available ... making sure everything in the plugin is exposed to agents". The plugin side is Element Assembly Studio Pro 2.6.0: its dialog and this MCP now share one build pipeline per system.
- **entity_studio (read).** New actions:
  - `parameters` (type: every setting the dialog shows, with range, options, start value, section and what it needs; generated from the dialog's own control files);
  - `elements` (every placed element at any depth);
  - `openings` (wall_id: every opening in a wall, left to right seen from outside, with the points the opening tools would pick; `outside` / `outside_point`, `path`);
  - `assets` (handles, architraves, hinges, cabinet handles and legs, sash horns, window boards, finishes, edge colours).
  - `inspect` covers every product and shows the values that differ from a new one; `list_presets` takes `type` and `archived`.
- **entity_studio_edit.** Covers windows (casement, sash), all four exterior doors, interior doors and cabinets (base, drawers, wall, tall, wardrobe).
  - **build:** `type` and/or `preset`, into `opening` {wall_id, index} or {point_a, point_b, point_d}, sized as Measure Opening would (`fit`); or at `position` + `direction`; cabinets on a `run` + `run_offset`. Also `name` and `dry_run`.
  - **update:** values, preset with the size kept, `reset`, refit to an opening; returns the changed values.
  - **New actions:** `rename`, `export_dxf` (`file`, `overwrite`), `update_preset`, `archive_preset`, `restore_preset`. `open_dialog` takes `instance_id`.
  - **Values:** checked against the dialog's own ranges, options and build rules, refused (never clamped) with every problem named.
- **The handler** resolves the wall with `Na__Coordinates__ReportedToWorld` (container path + the wall), so moved, rotated, nested, scaled and open walls all read true. It also converts points and `run_offset` from the call's units.
- **Where:**
  - `ToolRegistry` (both tools rewritten; 32 `property_since` keys at 1.0.27);
  - `Handlers__EntityStudio`;
  - `PythonServer` tests (2 new: an older bridge is refused the additions with the fix, the current one takes them);
  - `AGENTS.md` and `AgentGuide`.
  - The rules live in the plugin's seam (`60__System__McpOperations`, now 7 files). Still 68 tools.
- **Versions.** `bridge_version` and `server.version` are `1.0.27`.
- **Validation:**
  - ValidateApiUsage passed: 7 Element Assembly Studio seam files, 137 defining.
  - RunRubyChecks: 50 of 50 compile; BridgeCore 138 of 138.
  - PythonServer: 56 OK.
  - `--check`: 68 tools at 1.0.27.
  - Live, on the plugin's testbed through `su_bridge.py`: every product built into its opening, updated, renamed and inspected, presets in a sandbox, DXF, refusals. See the plugin's V2.6.0 devlog.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server knows the new actions and parameters.
- [ ] In SketchUp: Element Assembly Studio Reload Scripts (close and reopen its dialog), then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.27).
- [ ] Ask an agent to list a wall's openings (`entity_studio openings`) and put a casement into one; one Ctrl+Z removes it.
- [ ] Ask it to change a setting on a placed door (`entity_studio_edit update`) and open the dialog on it (`open_dialog`, instance_id).

## Na SketchUp MCP | Version 1.0.26 - 11-Nov-2026 - Agent Outliner: Pictures in the Chat

- **What Adam asked for:** "Add a dedicated Chat Tab which charts the ongoing conversation in a typical chatbot interface and shows all active agents chats associated with the current model. ensure pasting images is possible". The dialog's side is Agent Outliner 0.1.6 (Noble 3D Tools 0.9.38).
- **Reading:** a thread entry may carry `images`: each with `file`, `w`, `h`, `bytes`, `name`, and for agents `path` (his chat folder on this PC) and `exists`. An agent opens the path with its own image reader to see the screenshot he pasted. `threads` lines count `images` and list the `agents` who wrote.
- **Writing:** `agent_outliner_edit comment` / `reply` take `images`, absolute paths of picture files (PNG, JPEG, GIF or WebP; 15 MB each; 8 at most). They are checked and copied into the chat folder before anything is written, so a bad file refuses the call and leaves the model alone. `text` may be left out when pictures are given.
- **Sign every entry** (`author`): the Chat tab lists each agent by that name, with its chats and when it last wrote.
- **Where:** `ToolRegistry` (`images`, one `property_since` key, both descriptions), `AgentGuide` (an example and the map row). The work is in the seam (`Na__ChatCache`, `na_import_images`). Still 68 tools.
- **Versions.** `bridge_version` and `server.version` are `1.0.26`.
- **Validation.** BridgeCore 138 of 138 (1 new: `images` in the schema and `property_since`); PythonServer 54 OK; ValidateApiUsage passed; `--check` 68 tools at 1.0.26. The seam's suite: 197 of 197, with an agent's picture copied and its bad files refused. Not yet called live.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server knows `images`.
- [ ] In SketchUp: Noble 3D Tools Reload Plugin Data, then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.26).
- [ ] Paste a screenshot into the Model Chat and ask an agent what it shows (it reads the path through `agent_outliner thread` with `model: true`).
- [ ] Ask an agent to reply with a `view_capture` picture: it appears in the chat.

## Na SketchUp MCP | Version 1.0.25 - 11-Nov-2026 - Agent Outliner: Every Tag, and Putting Objects on One

- **What Adam asked for:** "Create an effective efficient system for changing the tag of a item or a selection of items and ensure tagging is easily exposed to agents too." The dialog's side is Agent Outliner 0.1.5 (Noble 3D Tools 0.9.37): a Tag picker.
- **For agents:**
  - `agent_outliner tags` lists every tag: name, colour, shown (its folders too), folder path, and how many groups, components, images and section planes are on it, plus the untagged count.
  - `agent_outliner_edit tag` puts objects on one tag (`ids`, `tag`; "Untagged" or "" for none) as one "MCP: Agent Outliner Edit" step. A missing tag is refused `not_found` with the model's tags named; `create: true` makes it in the same step. Already there: no undo step.
- **Where:** `ToolRegistry` (two enum values, `tag` and `create`, four `property_since` keys at 1.0.25, two `api` entries), the handler's action lists, `AgentGuide` (map row, two example calls). The work is in the seam (`06__McpOperations`, `EntityActions.Na__Actions__SetTag`). Still 68 tools.
- **Versions.** `bridge_version` and `server.version` are `1.0.25`.
- **Validation.** BridgeCore 137 of 137 (1 new: the four `property_since` keys and the two parameters); PythonServer 54 OK (the new enum values and parameters asserted); ValidateApiUsage passed (the Agent Outliner seam's 2 files, 17 defining); `--check` 68 tools at 1.0.25. The seam's own suite: 171 of 171. Not yet called live.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server knows `tags` and `tag`.
- [ ] In SketchUp: Noble 3D Tools Reload Plugin Data, then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.25).
- [ ] Ask an agent "which tags are in the model?" (`agent_outliner tags`), then to move two objects onto a tag; one Ctrl+Z takes the move back.

## Na SketchUp MCP | Version 1.0.24 - 11-Nov-2026 - Profile Path Tracer: Read, Edit and Library Tools

- **What Adam asked for** (Brown 60795, after the masonry orangery): "ALWAYS use [Na Profile Path Tracer] for elements like entabeture extrusion, wall cappings, cornices, covings, skirtings, windowboards, and anything else requiring a standardised profile ... create a new MCP subfolder in the plugin with ALL TOOLS POSSIBLE to allow you to interface with the plugin and to create, edit, make new profile presets etc." The tracer paints and smooths the edges itself, keeps the path and the profile on the trace, and lets him refine either in its editors. Use the closest library profile; he decides case by case what goes into the library.
- **The seam lives in the tracer** (1.6.17, `02__Src__AppModules/60__System__McpOperations`, four files), entry points `Na__ProfileTools__ProfilePathTracer::Na__McpOperations.Na__ProfileTracer__McpRead` / `McpEdit` / `McpLibrary`, and `Na__ProfileTracer__McpActions` for the action lists. The new handler (`Handlers__ProfileTracer__.rb`) checks the action, drops `null` keys and resolves only what the MCP can: `path` into world points, `path_edge_ids` into world segments (a curve's edge brings the whole curve, a group its own edges), `parent_id` into the container (entities and reported-to-world), `wrapper.origin`, `profile_face_id`; and it hands the seam two resolvers, `world_of` and `path_of`, built on `Na__Coordinates`. Without the tracer every tool refuses and names the fix.
- **Three tools, split by risk** (68 tools):
  - `profile_tracer` (read-only): `status`, `profiles` (query; `near {width, height}` ranks the closest sizes), `profile` (outline [[y, z]], arcs, edge colours, JSON; `profile_edit` previews a reshape), `traces`, `trace` (the world path as Edit Path draws it), `check_path`.
  - `profile_tracer_edit`: `create` (profile from `profile_key`, `profile_from` a trace, `profile_outline`, `profile_json` or `profile_face_id`; `profile_edit` scale / size / stretch / flip / datum into a local profile; `reverse`, `rotation_step`, `toggles`, `origin_offset`, offsets; `parent_id`; `wrapper` makes Adam's `SUB__...` group with the reference path edges, `reference_path_material` paints them), `set_path`, `set_placement`, `swap_profile`, `set_local_profile`, `revert_local`, `regenerate`, `recreate` (the only way to change reverse), `rename`, `delete`, `open_dialog`, `reload`.
  - `profile_tracer_library` (files only): `save_new`, `overwrite`, `set_meta`, `rename_file`, `redatum`, `flip`, `delete`. `overwrite` and `delete` need `confirm` = the key; `delete` sets the file aside as `.deleted__<time>` unless `permanent: true`.
- **One undo step, and batchable.** `profile_tracer_edit` has `"operation": false` and opens "MCP: Profile Tracer Edit (<action>)" itself through `Na__CommandRouter__WithOperation`, so inside `batch_execute` it joins the batch's step. That needed the tracer's engines to stop opening their own operations: `wrap_in_operation:` keywords (1.6.17) on the build, the rebuild, the swap and the local-profile writers, each defaulting to the dialog's behaviour. `open_dialog` and `reload` open no step; `reload` is refused inside a batch. `profile_tracer_library` is in `NA_BATCH_FORBIDDEN`.
- **Where the work is done.** `10__BridgeHandlers/Na__SketchUpMcp__Handlers__ProfileTracer__.rb` (new); `CommandRouter` (three routes, one batch refusal); `CoreAppLoaders` (one require); `ToolRegistry` (three tools, `server.version`); `AppConfig` (`bridge_version`); `ValidateApiUsage` (the tracer as a checked partner); `BridgeCore` and `PythonServer` tests; AGENTS.md (the seam); the Agent Guide (tool map).
- **Versions.** `bridge_version` and `server.version` are `1.0.24`. 68 tools.
- **Validation.**
  - `ValidateApiUsage` passes: 68 tools, 245 API dependencies; 4 tracer seam files checked like the bridge, 46 defining.
  - `RunRubyChecks`: 50 of 50 compile; `BridgeCore` 136 (15 new: the refusal without the tracer, actions refused before the seam, world points from one run or several, routes and the batch rule, the registry's lists equal to the handler's and the real seam's, read-only mode, `reload` refused in a batch, a seam refusal carried through, and the seam's own edge chaining, branch splitting, stretch and scale maths).
  - `PythonServer` 54 (1 new); `--check` 68 tools; `node --check` passes.
  - **Live in Brown (pid 549572)**, after both reloads: every read action; a zero-trace trial of 14 edit steps (create into the live walls with a wrapper and Adam's local profile, then set_placement, set_local_profile with a stretch, set_path, revert_local, swap_profile, regenerate, recreate with reverse off, rename, traces, delete), all rolled back; every library action on a throwaway profile, then removed. The real build: one batch, one undo step "MCP: Brown Scheme-3: parapet capping by Profile Path Tracer", 0.52 s. The capping is identical to Adam's REFERENCE CAPPING HERE trace, 10 m lower: bounds, 0.8989339 m3, 159 faces, 369 edges, 71 L20 + 298 L40.
  - **Found and fixed live:** a library code ending in `__` slipped past the "already in the library" check (the plugin's cleaner trims it), and wrote a second file beside the profile it copied (removed). New codes now clash with any key that cleans to the same code.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server lists 68 tools.
- [ ] In each SketchUp window: the Profile Path Tracer's Reload Plugin Files (Settings tab), then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.24). A restart does both.
- [ ] Select a trace, open the tracer, Draw Profile > From Model: Live is on straight away (the tracer's own 1.6.17 change).
- [ ] Ask an agent for a skirting along a few edges: it should pick a library profile with `profile_tracer profiles`, build it with `profile_tracer_edit create`, and one Ctrl+Z should take it away.

## Na SketchUp MCP | Version 1.0.23 - 10-Nov-2026 - Agent Outliner: Every Flag, Every Thread, Strip, and a History That Saves

- **What was asked.** From the Brown 60795 session: investigate Adam's Agent Outliner, build every MCP tool it still needs (read: summary, flags, threads, names; write: flags, threads, standard names), each write one undo step and refused in read-only mode, and prove each one in a test model.
- **What 1.0.22 already had** (built earlier the same day, not yet run inside SketchUp): `agent_outliner` with summary, inbox, changes, thread, prefixes, find; `agent_outliner_edit` with comment, reply, resolve, reopen, flag, unflag, acknowledge, name. Three gaps:
  - no way to list **every flagged object**: `inbox` shows only For Agent, Question and Check This, so an agent never saw Adam's Do Not Touch or Reference flags;
  - no list of **every thread** with who it waits on: an agent could not find its own unanswered questions;
  - no **Strip**, the Outliner's button that takes a standard prefix off again.
- **New actions**, all in the Agent Outliner's seam (0.1.1), the handler forwarding as before:
  - `agent_outliner {action: "flags"}`: every flagged object grouped by flag type, in the standards' order, each type with its meaning and count (empty ones too, so "no Do Not Touch objects" is an answer); each object with id, path and who set the flag; a flag type since dropped from the standards still shows. `flag` (an id or label) and `by` (user or agent) narrow it.
  - `agent_outliner {action: "threads"}`: every thread on one line (the model's too): open or resolved, `waiting_on` agent (Adam's comments or flag no agent has acknowledged) or user (open, and the last comment is an agent's), counts, flag, and the last word cut to 240 characters. Sorted: on an agent, on Adam, other open, resolved; newest first. `status` and `waiting_on` narrow it.
  - `agent_outliner_edit {action: "strip"}`: any standard prefix taken off (`REF__Wall` becomes `Wall`), one "MCP: Agent Outliner Edit" undo step, none when nothing changes. A name that was exactly a label (CAD__FrontElevation) is left empty, as the button does, and a warning says which.
- **An older window is refused with the fix.** `property_since` now also takes values: `"agent_outliner.action=flags"`. Before a call, the server pings the window's bridge and refuses a 1.0.22 window with "Reload Plugin Data" instead of the bridge's bare "unknown action". Listed: the three new actions and the new parameters `status`, `waiting_on`, `flag` (`ToolRunner.na_too_old`).
- **Found live and fixed in the Agent Outliner (0.1.1)**, both from 0.1.0:
  - **No history was ever saved.** The ModelHistory folder is about 195 characters deep, and 0.1.0's file names took the path to 274 to 292 characters. SketchUp's Ruby cannot open 260 or more on Windows (`Errno::ENOENT`, proved in the test window: a 276 character path refused, a 238 character one written). So Adam's change marks and an agent's acknowledgements were lost at every restart. Files are now `History__<20 character stem>__<crc>.json` (about 243 with `.tmp`), and a key held over a reload is cut to the same name.
  - **A plain Do Not Touch, Reference or Done flag waited for an agent.** Configure says only the ticked types ("waits for an agent") go to the inbox; the flag's thread entry ignored that. Now a flag entry waits only for an inbox type, or when Adam typed his own note with it.
- **Reload safe.** The seam's action lists were guarded constants, so Reload Plugin Data would have kept 0.1.0's lists until a restart. They are now replaced on every load.
- **Where the work is done.** `Handlers__AgentOutliner__.rb` (action lists); `ToolRegistry` (enums, `status`, `waiting_on`, `flag`, descriptions, `property_since`, `server.version`); `AppConfig` (`bridge_version`); `ToolRunner` (values in `property_since`); `BridgeCore` and `PythonServer` tests; Agent Guide; AGENTS.md. In the Agent Outliner: `McpOperations__Main`, `McpOperations__Payloads`, `Naming` (`Strip` takes `operation_name:`), `Notes` (inbox flags), `HistoryStore` (short names), version 0.1.1; see its DEVLOG.
- **Versions.** `bridge_version` and `server.version` are `1.0.23`. 65 tools (unchanged: new actions, not new tools).
- **Validation.**
  - Offline: `ValidateApiUsage` passes (65 tools, 234 API dependencies, the seam checked); `RunRubyChecks` 49 of 49 compile, `BridgeCore` 121 (3 new: read-only refuses every edit action before the seam and lets reads through; every `property_since` key names a real tool, parameter and value at or below this bridge; the new actions are listed; and a stale 0.1.0 action list is replaced when the seam loads); `PythonServer` 53 (2 new: a 1.0.22 bridge refused `flags`, `threads` and `strip` with "needs 1.0.23" and "Reload Plugin Data", nothing sent, while `summary` still goes; a 1.0.23 bridge served); `--check` 65 tools.
  - The Agent Outliner's suite: 135 of 135 (36 new) and 12 of 12 deliberate faults caught (6 new).
  - **Live, in a throwaway window** (a copy of SketchUp's Simple template in the session scratchpad, pid 596180; Adam's window untouched): bridge 1.0.23, Agent Outliner 0.1.1, `api_self_test` 234 with none unavailable; both Reload Plugin Data commands from `ruby_eval` (47 and 17 files, no errors, the action lists equal in the seam and the handler). Four test groups, Adam-side notes written as `by: user`, then: `threads` (3, all waiting on an agent; after the fix the plain Do Not Touch waits on nobody), `threads waiting_on agent`, `flags`, `flags flag: "Do Not Touch"` (by label), `inbox` (the Do Not Touch no longer in it), `prefixes` (the REF box), `summary` (history file `History__AoTrial__AgentOutlin__e7a426a9.json`, 239 characters, saved); `reply` (acknowledged 2, the thread then waiting on Adam, one `model_undo` took it out); `strip` on `REF__AO Trial - Survey Box` (renamed, undo named "MCP: Agent Outliner Edit", one `model_undo` put it back); `strip` on a plain name (no step); `name` CAD__FrontElevation then `strip` (empty name and the warning; two undos restored "AO Trial - Wordy"); read-only mode (an in-memory switch that ended by itself after 25 s): `strip` and `acknowledge` refused `read_only`, `flags` answered; refusals for `status: "closed"` and `flag: "urgent"` with their hints. Then every step undone: one component left, no `Na__AgentOutliner__Notes` anywhere; the copy saved in the scratchpad, the window closed, its history file deleted.
  - Not run live: the version refusal against a real 1.0.22 window (proved with a fake bridge), and anything in Adam's own window.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server is 1.0.23 (the tool list is still 65; the new actions appear in `agent_outliner` and `agent_outliner_edit`).
- [ ] In each SketchUp window: Noble 3D Tools' Reload Plugin Data (or the Agent Outliner's Settings > Reload Plugin Data), then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.23). A restart does both.
- [ ] Flag a group Do Not Touch in the Agent Outliner: it is not in the agent inbox, and an agent's `agent_outliner flags` lists it.
- [ ] After a restart, the New and Updated marks of the last session are still there (the history now saves: look for `History__<model>__<crc>.json` in the Agent Outliner's `91__UserConfig__LocalOnly/ModelHistory`).

## Na SketchUp MCP | Version 1.0.22 - 10-Nov-2026 - The Agent Outliner: Adam's Flags, Threads and Change History for Agents

- **What Adam asked for.** An outliner "tailored for helping me working with Claude MCP Agents": flags and a two way comment system, "so agent -> user and user -> agent", New / Recent / Updated marks for what he or an agent changed, standard names such as CAD__FrontElevation, "and build robust MCP handling".
- **The seam lives in the Agent Outliner** (Na Noble3d Modelling Tools 0.9.25, `10__PluginModules/36__SourceCode__AgentOutliner/06__McpOperations`), as the Component Editor Tools', Point Cloud Viewer's and GLB Builder's do. The new handler (`Handlers__AgentOutliner__.rb`) only checks the action, drops keys sent as `null`, passes the open model, moves warnings onto the response and turns the seam's refusals into `Na__McpError`. Without the Agent Outliner both tools refuse and name the fix.
- **Two tools, split by risk:**
  - `agent_outliner` (read-only, the 64th): `summary` (start here), `inbox` (what Adam flagged or asked, with each object's id, path, tag, size, standard name meaning and whole thread), `changes` (made, changed or erased, by whom and which fields, since the agent's last acknowledge or a cursor; `by: "user"` gives Adam's own corrections), `thread`, `prefixes` (what each standard name means and which objects carry it), `find` (the Outliner's search language).
  - `agent_outliner_edit` (the 65th): `comment`, `reply`, `resolve`, `reopen`, `flag`, `unflag`, `acknowledge` (this PC only, no undo step), `name` (standard names only, never tags).
- **Who did it.** The Agent Outliner reads the Ruby call stack inside each observer callback: this plugin's folder on the stack means an agent's request is running (ruby_eval included), so every object an agent makes or changes is marked as the agent's, with the handler's name (`Primitives__CreateSolid`). Nothing in this plugin had to change for it.
- **Server instructions unchanged**: they are at 2,045 of their 2,048 characters. The tool descriptions and a new Agent Guide recipe ("Start a job from Adam's notes") carry the advice instead.
- **Where the work is done.** `10__BridgeHandlers/Na__SketchUpMcp__Handlers__AgentOutliner__.rb` (new); `CommandRouter` (two routes, one batch refusal); `CoreAppLoaders` (one require); `ToolRegistry` (two tools, `server.version`); `AppConfig` (`bridge_version`); `ValidateApiUsage` (the Agent Outliner as a checked partner); `BridgeCore` and `PythonServer` tests; the Agent Guide (tool map, recipe) and AGENTS.md (the seam).
- **Versions.** `bridge_version` and `server.version` are `1.0.22`. 65 tools.
- **Validation.**
  - `ValidateApiUsage` passes: 65 tools, 234 API dependencies; 2 Agent Outliner seam files checked like the bridge, 17 defining.
  - `RunRubyChecks`: 49 of 49 compile; `BridgeCore` passes 118, 10 of them new: the refusal without the Agent Outliner, actions refused before the seam is asked, `null` keys dropped and the model passed, routes and the batch refusal, the registry's action lists equal to the handler's and to the real seam's, a seam refusal carried through with its code, hint and details.
  - `PythonServer`: 51 tests pass (65 tools; one new test for the pair's schemas and hints). `--check`: 65 tools, and it pinged the running SketchUp 2027 (bridge still 1.0.21 until reloaded). `node --check` passes.
  - The Agent Outliner's own suite: 99 checks, and 6 of 6 deliberate faults caught (its DEVLOG, 0.1.0).
- **Not yet tested inside SketchUp.**

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server lists 65 tools.
- [ ] In SketchUp 2027, Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.22), and Noble 3D Tools' Reload Plugin Data (Agent Outliner 0.1.0; a restart adds its menu item).
- [ ] Flag a group For Agent in the Agent Outliner with a comment; ask an agent to "check the outliner inbox" and reply.
- [ ] The reply shows in the Outliner's thread, in the agent colour, marked New; the group is no longer waiting.
- [ ] Ask the agent to build a box: it shows NEW, by agent, in the Outliner. Rename it yourself: UPDATED, by you; `agent_outliner changes by: "user"` lists the rename.

## Na SketchUp MCP | Version 1.0.21 - 09-Nov-2026 - The TrueVision GLB Builder, From Status To Push

- **What Adam asked for.** "It might be worth you building some MCP tools for TrueVision GLB Exporter, my plugin. Look in the plugins folder and build out an MCP folder in there with all of the MCP tools, so agents can access absolutely all of the tools available for pushing, handling, and checking statuses, etc."
- **The seam lives in the GLB Builder** (2.14.0, its new `07__Plugin__McpOperations` folder), as Element Assembly Studio's and the Point Cloud Viewer's do. The new handler (`Handlers__TrueVisionExport__.rb`) only checks the action, drops keys sent as `null`, moves the seam's warnings onto the response and turns its refusals (`TrueVision3D::GlbBuilderUtility::Na__McpOperationsError`) into `Na__McpError`. Without the GLB Builder 2.14.0 all three tools refuse and name the fix.
- **Three tools, split by risk, so a client's permissions can be set per tool:**
  - `truevision_export` (read-only, the 61st): `status` (start here), `manifest`, `project`, `site_plan`, `scenes`, `point_clouds`, `job`, `r2_inventory`, `fetch_r2` (a job that lists the project's GLBs in R2; changes nothing there), `logs`, `python`, `config`.
  - `truevision_export_edit` (the 62nd, 26 actions): this model and this computer only. Exports into any folder or into the linked project (the previous export archived first), file toggles, the project link and portal root, scheme folders (set, create, duplicate, delete), site plan stores and the site plan export, Scene Sync and point cloud settings and renders, `open_dialog`, `reload`.
  - `truevision_publish` (the 63rd): `push_dry_run`, `push`, `export_and_push`, `write_scenes_and_push`, `export_point_clouds_and_push`, `purge_r2_folder`, `open_pipeline`.
- **The dialog's own code and gates.** The tab actions run the dialog's handlers, handed a recording stand-in for the dialog (it reads their status lines and reports, and passes every script on to the real dialog when it is open). Every publish action but the dry run, and every deletion, needs `confirm` = the linked project's code, as the dialog's modals ask. Exports refuse while a group is open; anything that starts a job or writes into the project refuses while a job runs.
- **Jobs.** R2 work and point cloud renders run as the GLB Builder's CloudJob (a Fiber on a UI timer). The call answers at once; `truevision_export {action: "job"}` follows the job to its report. Nothing waits inside a call: the bridge and the job share SketchUp's one thread.
- **Undo and batches.** Edit and publish have `"operation": false`: the seam writes model settings as one "TrueVision: ..." step each, and the Scene Sync and point cloud settings open their own, so both tools are in `NA_BATCH_FORBIDDEN`.
- **Fixed: `truevision_structure` was one file short** wherever a model has linetype linework (`02__Linetype__` tags with edges): SK02 showed 37 where the GLB Builder writes 38. With the GLB Builder loaded it now lists those files from the GLB Builder's own plan; without it, a model with such tags gets a warning naming `truevision_export manifest`.
- **Fixed: `entity_reparent`'s summary** read "into inside ..." for a destination inside a group; it now reads "into ...".
- **Found in the GLB Builder, not fixed (its owner's call).** Inside SketchUp 2026 a child process's stdout never reaches Ruby (`Open3.capture3` and a file redirect alike: `print("hello")` came back empty with exit 0). So the Point Cloud tab's Check Python button says "Python cannot write WebP yet" while Pillow writes WebP fine. `truevision_export python` has Python write its own answer file.
- **Where the work is done.** `10__BridgeHandlers/Na__SketchUpMcp__Handlers__TrueVisionExport__.rb` (new); `CommandRouter` (three routes, two batch refusals); `CoreAppLoaders` (one require); `ToolRegistry` (three tools, `server.version`); `AppConfig` (`bridge_version`); `Handlers__TrueVision__.rb` (linetype files); `ValidateApiUsage` (the GLB Builder as a checked partner, its archived versions left out). In the GLB Builder: the seam folder, and three keywords with the old behaviour as default (`BuildModelStatus prune:`, `Na__SitePlan__Write on_stale:`, `ReloadAllScripts quiet:`); see its DevLog, 2.14.0.
- **Versions.** `bridge_version` and `server.version` are `1.0.21`. 63 tools.
- **Validation.**
  - `ValidateApiUsage` passes: 63 tools; 4 GLB Builder seam files checked like the bridge. It caught the edit tool's first description at 2,182 characters (now 2,039) and a regex read as a method call.
  - `RunRubyChecks`: 48 of 48 compile; `BridgeCore` passes 109, 12 of them new: the refusal without the GLB Builder, actions refused before the seam is asked, `null` keys dropped, warnings moved, routes and batch refusals, the registry's action lists equal to the handler's AND to the real seam's, a seam refusal carried through with its hint and details, a fault inside the GLB Builder answered as `glb_builder_error`, and an unconfirmed push refused before anything runs.
  - `PythonServer` passes 50, 1 new: the three tools listed under 2,048 characters, scenes by name or id together, and the schemas refusing a bad type, an action of another tool and a stray key.
  - The seam's own offline suite (SketchUp's Ruby, session scratchpad): 50 checks.
  - Live on SK02 (pid 20528; the seam loaded with `ruby_eval load`, then Reload Plugin Data; calls through `su_bridge.py`, since this session's server predates the tools): every read action; a self-test CloudJob followed through `job` (1 s); `export_folder` wrote 38 GLBs and the log into a scratch folder in 9.8 s; `select_files` switched one file off as one undo step, and `model_undo` left no trace; ten refusals. SK02 is not linked to a project, so link, schemes, the site plan export, scene writes, point cloud renders, pushes and the purge were not run: each would change Adam's model, his project folders or the live site.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server lists 63 tools.
- [ ] In each SketchUp window, Reload Plugin Data (1.0.21), and the GLB Builder's Reload Scripts (2.14.0).
- [ ] Ask an agent for "the TrueVision status" of a linked project model.
- [ ] Ask for a dry run of that project's push: `job` reports what would be uploaded and deleted, and nothing is.
- [ ] Ask for the R2 inventory (`fetch_r2`, then `r2_inventory`) and compare it with the Project tab.

## Na SketchUp MCP | Version 1.0.20 - 09-Nov-2026 - `view_set` and `view_capture`: a Key Sent as null Is Not Given

- **What Adam asked for.** "Yes, fix both": the two faults the point cloud review found outside its own tools.
- **The fault.** A key a client sends as `null` passes the schema check. The view handlers then read it as given and false:
  - `view_set {xray: null}` switched X-ray off, and `show_hidden_geometry: null` hid hidden geometry;
  - `section_display {planes: null}` hid section planes;
  - `null` values in `rendering_options` or `shadows` were written into SketchUp as false (a `null` shadow `time` failed to parse);
  - `camera: null` counted as a camera request, so `view_set` reported a camera change and `view_capture` took the restore path.
- **The fix** (`Handlers__View__.rb`): presence is read with `Na__Params__Has`, nested keys included. `na_set_options` drops `null` values, and `na_shadow_changes` skips them. No `params.key?` is left in the View handler.
- **Versions.** `bridge_version` and `server.version` are `1.0.20`. The tool count is unchanged (60).
- **Validation.** `RunRubyChecks`: 47 of 47 compile; `BridgeCore` passes 97, with 1 new check covering:
  - the camera check;
  - `xray` and `show_hidden_geometry`;
  - `section_display`'s keys;
  - shadows with a `null` time;
  - `na_set_options` leaving a setting untouched.
  `ValidateApiUsage`, `PythonServer` (49), `--check` and `node --check` pass.

### Validation Checklist

- [ ] In each SketchUp window, Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.20).

## Na SketchUp MCP | Version 1.0.19 - 09-Nov-2026 - Point Cloud Slices at Any Angle (`frame`)

- **What Adam asked for.** Angled slices, once the point cloud tools were triple-checked (1.0.17).
- **`frame`** on `point_cloud_slice` (every action) and `point_cloud_heightmap` (grid and profile), a new common schema:
  - `origin` (a model point, default the model origin), then `angle` (degrees anticlockwise from +x about the vertical) or `x_axis` with an optional `y_axis`; or `id` alone, whose group or component gives its world origin and axes.
  - With a frame, `min`, `max`, the view, `axis`, `path` and every position in and out are in the frame. `top` looks down the frame's z and `front` along its +y. The reply echoes the frame: origin, unit axes, and the rule back to the model.
  - Uses: walls not square to the model (a histogram across a wall at 37 degrees finds its two faces); sections along or across such a wall; a roof's slope (a heightmap in the roof's frame reads its sag).
  - A points `.npz` keeps model mm in `p` (the kit) and adds the frame's in `f`. `overlay_ids` edges are moved into the frame.
- **Where the work is done.** The handler converts the origin's units and resolves `id` (`Na__Serializer__ToWorld`). Point Cloud Viewer 0.14.6 makes the frame and folds it into the cloud's local -> model transform, so the engine works in the frame unchanged. An older viewer refuses `frame` with `unsupported`, naming 0.14.6.
- **A window not yet reloaded refuses `frame` instead of ignoring it.**
  - Found live: the SK02 helper reopened as pid 49160 on bridge 1.0.18, which took a framed `point_cloud_slice`, ignored the frame and counted the box at the model origin: 0 points, no warning. Any parameter added to an existing tool had this hazard.
  - Now the registry's top-level `property_since` lists each parameter added later and the bridge version it needs; for now `point_cloud_slice.frame` and `point_cloud_heightmap.frame`, both 1.0.19. Before a call that uses one, the server pings the window's bridge (the live version: a data reload never rewrote the connection file, and now does), and refuses an older bridge with the fix: Reload Plugin Data. Batch steps are checked the same way.
  - Live on 49160 before its reload: refused, nothing sent.
- **Versions.** `bridge_version` and `server.version` are `1.0.19`. The tool count is unchanged (60 with the TrueVision session's 1.0.18).
- **Validation.**
  - Offline: `ValidateApiUsage`, `RunRubyChecks` (`BridgeCore` with 2 new checks: an older viewer refused, units and id rules), `PythonServer`, `--check`, `node --check`. The viewer's seam suite has 9 frame checks against a stand-in engine that applies the transform as the real one does; its frame suite has 8.
  - The real engine DLL against numpy (a wall at 37 degrees): counts and grids equal, points to 1e-12 mm.
  - Offline after the guard: `PythonServer` 49 (2 new: an older bridge refused a frame, in a call and in a batch step, with nothing sent; a current one served), `BridgeCore` 96, 47 of 47 compile, `ValidateApiUsage`, `--check` (60 tools).
  - Live, read-only:
    - through the seam in 22360:
      - the plumb wall at x 17,325 in a frame turned 90 degrees reads its face at -0.4 mm, with the same counts as the plain histogram;
      - a 100 mm section at 37 degrees through the house: the renderer and the density grid agree on 99.9% of pixels.
    - through the real server in 49160 after its reload:
      - the same wall at -0.4 mm, 14,089 points in the peak bin;
      - the 37 degree section returned inline (115,014 points);
      - a heightmap in a turned frame;
      - a points `.npz` with `p` (model, x averaging 17,324.8) and `f` (frame, y averaging 0.2);
      - `frame {id}` from a group;
      - a frame on `point_cloud_fit`, and an angle given with axes, both refused.

### Validation Checklist

- [ ] In each other window, run the viewer's Reload Plugin, then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.19). 22360 is done.
- [ ] In SK02, ask for `point_cloud_slice {action: "density", view: "front", resolution: 10, frame: {origin: [15000, 14000, 0], angle: 37}, min: [0, -50, 0], max: [6000, 50, 3000]}`: a section cut at 37 degrees through the house.

## Na SketchUp MCP | Version 1.0.18 - 09-Nov-2026 - TrueVision Structure, Moving Into Groups, Windows Opened and Closed

- **What Adam asked for.** A skill job that takes any model he is working on, classifies every object, tags it and nests it the way TrueVision reads a model, learned from the latest RB05, EB03 and NP03 models: "Physically open those models ... Build any MCP tools that are missing." Then: close the models once the data is in, because each open SketchUp uses a lot of memory.
- **`sketchup_open_window`** (server-side, the 57th tool): opens a .skp in a NEW SketchUp window, so every window already open keeps its model and unsaved work (`model_file open` replaces the model in the window in use). `copy_to` (a folder or a .skp path) copies the file first and opens the copy, so the original is never open. It waits until that process's bridge answers with the model open, then selects it (`select: false` stays). A file already open in a window is used as it is. A copy over an existing file needs `overwrite`; a copy that is open in a window is refused. SketchUp.exe is the version whose Plugins folder the server runs from. Inside a Windows job the process breaks away when allowed.
- **`sketchup_close_window`** (server-side, the 58th): closes a window the way File > Exit does: its own bridge runs `Sketchup.quit` on a timer, and the tool waits for the process to end. Unsaved changes are refused; `discard_unsaved_changes` (only with the user's agreement) runs `Model#close(true)` first.
- **`truevision_structure`** (read-only, the 59th): reads the model as the TrueVision GLB Builder exports it. It reports:
  - the storey containers (root groups on the 90-93 tags) and their element groups by tag;
  - the flat files, and the GLB file names with the project prefix;
  - everything TrueVision will never see, with the reason: untagged, skip-range or excluded tags at the root; children of a storey that are untagged or on a non-element tag; loose faces and edges directly in a storey (the exporter skips them silently);
  - category tags nested inside exported elements (they export with the element);
  - storeys split across containers with different transforms (the exporter uses the first one's);
  - the files toggled off in the model's export selection.

  The rules come from the GLB Builder's own `Na__ExportConfig__*` readers when it has loaded them (no network call is ever started from the bridge), else from the Tags SSOT file, read the way the exporter reads it. `include_objects` lists every object for classifying (name, definition, library code, ADR/AWN assembly, tag, storey, world bounds, faces, children, dictionaries). `analyse_faces` adds face area by orientation (up, down, vertical, sloped), the heights of upward faces (a stair's treads, `median_rise_mm`), the commonest materials, and the model's floor levels. `save_path` writes it all to JSON.
- **`entity_reparent`** (the 60th): moves groups and components into another group or component, or a `new_group {name, tag}`, keeping each exactly where it is. SketchUp cannot move entities between contexts, so each is placed again from its definition (name, tag, material, hidden, locked, shadow flags and instance attributes copied) and the original erased; new ids come back in order.
  - Measured on NP03: a group comes back as a `Group` carrying its definition's attribute dictionaries; a component keeps its definition; shift 0.0 mm.
  - Refused: loose geometry, anything open, an id inside another id, a source inside a component used more than once (it would leave every copy), a destination inside what moves, a shared destination.
  - It warns when a moved object was glued to a face (any opening it cut closes).
- **`tag_manage action: "create_standard"`**: tags from the Tags SSOT, made by Adam's TagUtils (`na_create_or_update_tag`: SSOT line style, colour and TagUtils metadata), fed from the local SSOT files. A name not in the SSOT is refused with the SSOT tags of that number. Existing tags are left alone unless `update_existing`. Without TagUtils it applies the SSOT line style and colour and says so.
- **Fixed: closed windows listed as live.** Five closed SK02 and JW02 windows showed `live: true` because their connection files named port 8385, which a running window had taken. Where several files claim one port, a file whose process has gone is live only when the bridge answering on that port is that process, checked by ping with the file's own token. Stale files are removed.
- **Fixed: the server instructions were cut short.** At 2,390 characters they were truncated to 2,048, so clients lost the closing rules, from "discard unsaved work" on. Rewritten at 2,012 characters with every rule kept, plus one line for the new tools.
- **Where the work is done.**
  - `30__McpServer__Python/Na__SketchUpMcp__Server__WindowLauncher__.py`: open and close, with a CLI the skill can use before the server is restarted.
  - `10__BridgeHandlers/Na__SketchUpMcp__Handlers__TrueVision__.rb`: the structure.
  - `Handlers__EntityEdit__.rb`: reparent. `Handlers__Tags__.rb`: create_standard.
  - `ValidateApiUsage` counts TagUtils' definitions as a partner seam.
- **First runs on Adam's models** (copies in a scratch folder, opened with the new launcher, then closed with the new close):
  - RB05 main house 0.9.8 (28 MB): 3 storeys, 25 element groups, 55 files, 1,635 objects, 4.7 s.
  - EB03 proposed: 37 element groups, 77 files, 10 s.
  - EB03 existing: its ground floor is split over two storey containers with different transforms, so the greenhouse exports with the first container's transform. One existing door sits at the root and exports outside every storey.
  - NP03 planning model: 53 files, 4.8 s.
- **Versions.** `bridge_version` and `server.version` are `1.0.18`. 60 tools; AGENTS.md and the agent guide say so (guide table, and a recipe for nesting into a storey container).
- **Validation.**
  - `ValidateApiUsage` passes: 60 tools, TagUtils partner.
  - `RunRubyChecks`: 47 of 47 files compile, and `BridgeCore` passes 94, 14 of them new: the export rules from the SSOT, reasons at the root and inside a storey, the file prefix and names, save_path checks.
  - `PythonServer` passes 47, 10 of them new: tool count 60; the stale file on a taken port; open_window refusing a non-.skp, a missing file, an open copy and an existing copy, and using the window that already has the file; close_window refusing an unknown pid and unsaved changes, quitting a saved window through its own bridge, and discarding only when told. `--check` passes.
  - Live through the real server and bridge (NP03 copy, rolled back): `create_standard` made `93__Storey__ThirdFloor`; `entity_reparent` moved a wall group and a window into a new storey group with 0.0 mm shift; `truevision_structure` then listed `Storey__ThirdFloor` with both elements and four more files. The model was unchanged after.
  - The open and close code paths ran on four real windows through the launcher's CLI. The server-side tool route goes live when the MCP server restarts.

### Validation Checklist

- [ ] Restart the MCP client (Claude Code) so the server loads 1.0.18: `sketchup_open_window` and `sketchup_close_window` answer on the server side.
- [ ] In each SketchUp window, Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.18).
- [ ] Ask "open a copy of NP03's planning model": a second window opens with the copy, and your own window keeps its model. Then ask to close it.
- [ ] Ask for `truevision_structure` on a project model, and compare its file list with the last TrueVision export.
- [ ] In a scratch copy, `entity_reparent` a wall into a new group: it should not move by a millimetre.

## Na SketchUp MCP | Version 1.0.17 - 09-Nov-2026 - The Point Cloud Tools, Triple-Checked

- **What Adam asked for.** "Triple-check the tools you've made already, and then, once happy they are robust enough, move on to angle slices."
- **How they were checked.**
  - Four reviewers read the code cold, each one layer: the engine's box queries and their bindings, the viewer's seam, the fitting, check and heightmap maths, and these handlers with their schemas and docs.
  - Offline edge cases: units (mm, m, in, ft), empty and one-point boxes, all five views, paths that double back or are shorter than a step.
  - Hostile live calls through the real server in the SK02 helper window (22360), read-only: about 20 bad calls, a 3 M-cell heightmap from 5 M points (18.6 s), a 50-point zigzag profile (4.4 s), the stair check on 100,000 points (9.8 s).
  - The cloud drawn into a capture was checked the right way up against a density image of the same box: 0.57 correlation as drawn, 0.03 flipped.
- **What this plugin fixes.**
  - A key sent as `null` is not given: `point_cloud_view {shown: null}` no longer hides every cloud, and a `null` `save_path` or `image_path` no longer keeps a temp capture.
  - Capture paths (`view_capture`, `point_cloud_slice` image and density, the check's heatmap) refuse a `save_path` whose extension is not the image's: `write_image` chose the encoder from the extension, so `shot.jpg` held JPEG bytes labelled PNG.
  - `point_cloud_check` and the overlays leave out hidden groups, hidden faces and edges, and anything on a hidden tag or in a closed tag folder, as SketchUp draws them (`na_shown?`, `na_walk_shown`). An id that is itself hidden is measured, with a warning.
  - The check's heatmap no longer refuses the whole check when its group has no visible edges, or too many; the edges are left off with a warning, naming `ids`, not `overlay_ids`.
  - `view_capture include_point_cloud`:
    - any error while drawing the clouds is a warning, never a lost capture;
    - with `scene`, the viewer applies that scene's cloud look before drawing (its own timer ran 0.1 s too late), except inside `batch_execute`, where SketchUp cannot nest the viewer's undo step (a warning says so);
    - captures over 12 MP keep no clouds, with a warning (the blend runs in Ruby).
  - Registry: `point_cloud_fit`, `point_cloud_check`, `point_cloud_heightmap` and `view_capture` describe the new rules. Stale "view_capture never shows a cloud" lines are corrected in ServerInstructions, AgentGuide, AGENTS.md and the `point_cloud_state` description.
- **What the viewer fixes (0.14.5).** Its DEVLOG has the detail:
  - points on a box's faces counted by histograms and density images;
  - model edges on a picture's right or bottom border drawn;
  - per-pixel sizes, bins and chart scales returned exact;
  - grid lines on the right pixel;
  - two clouds with the same name refused;
  - a transparent capture blended properly;
  - an empty model check refused;
  - fitted lengths full length (they were 2% short);
  - one rule for line and plane directions;
  - small circles fitted;
  - fits refined until they stop changing, with a warning when a curve settles on two circles;
  - the box fit's residuals;
  - the right sign at sharp ridges;
  - big sloping faces indexed fast;
  - profiles sampled at one rate with the right number of stations;
  - side views ranked by nearness;
  - a failed clip scene write kept in step.
- **Not fixed here (follow-ups):**
  - the engine's `napc_cloud_destroy` does not take the render mutex: latent, needs a second Ruby thread, which nothing starts; it needs an engine build;
  - `view_set` still treats `xray: null` and `show_hidden_geometry: null` as false (a base tool, out of this job);
  - the skill's SKILL.md still says captures never show the cloud (lines 269 and 448).
- **Versions.** `bridge_version` and `server.version` are `1.0.17`. Still 56 tools.
- **Validation.**
  - `ValidateApiUsage` passes (5 viewer seam files). `RunRubyChecks`: 46 of 46 compile; `BridgeCore` 80 (6 new: visibility walk, capture extensions, null keys, the check's edges, save and image paths). `PythonServer` 37, `--check` and `node --check` pass.
  - The viewer's suites: seam 72, heightmaps 15, fit 18, check 10, frames 8; its harness main 197, boxes 84, hotkeys 134, multi 96.
  - On the real engine DLL, 600 points exactly on box faces: the histogram now counts 600 (it counted 444), density images 600 (326).
  - Live in 22360 after both reloads, the clouds staying loaded: the hostile calls again; the stair check unchanged (rms 16.1, mean +7.8); a sampled diagonal profile reads one 44.3% share of every piece. The bullnose settles on 173.4 mm at a 10 mm tolerance, the same as an independent least-squares fit; at 3 mm it settles on two circles (145.8 and 164.1 mm) and says so.

### Validation Checklist

- [ ] In each other window, run the viewer's Reload Plugin, then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.17). 22360 is done.
- [ ] Ask for `point_cloud_fit {shape: "circle", axis: "z", tolerance: 3, max_radius: 250, min: [16300, 12040, 80], max: [16540, 12300, 160]}` in SK02: the reply warns that the bullnose settles on two circles.

## Na SketchUp MCP | Version 1.0.16 - 09-Nov-2026 - `point_cloud_heightmap`: Heights per Cell and Along a Path

- **What Adam asked for.** "Heightmaps next", the next tool on the list.
- **`point_cloud_heightmap`** (read-only, the 56th tool):
  - `action: "grid"` (default): the box `min`, `max` in cells `resolution` wide (default 50 mm), seen along `view` (default top). Each cell gets the `stats` asked for: min, max, mean, median or p<percent> (default p2, p50, p98; p2 finds the ground under grass, p98 the tops).
  - Returns each statistic's range, the best plane's slope (percent, 1 in N, the way it falls, and from the top its azimuth), the cell mapping, the shown statistic inline up to 2,500 cells, and a picture: blue (low) to red (high), shaded, contoured, white where empty, `overlay_ids` in magenta.
  - `save_path`: a `.npz` in the terrain kit's rasters.npz layout (the terrain session asked for it: x0, y1, res, W, H, count, z02 ... in model mm, NaN where empty; `colours` adds rgb_top and rgb_low), or from the top an `.asc` ESRI grid.
  - `action: "profile"`: heights along `path` (2 to 50 points) in a corridor `width` wide (default 100 mm), stations `step` long (default 50 mm): start, end and rise, the least-squares slope, the steepest metre, the stations inline up to 1,000, and a picture (chainage across, height up, exaggerated to show falls). `save_path`: `.csv` or `.npz`.
  - `image_path` keeps the picture. A grid-only key on a profile, or the reverse, is refused before the viewer is asked.
- **Where the work is done.** The handler reads lengths, the path and file names (`na_save_path`, `na_image_path`). The rest is in Point Cloud Viewer 0.14.4 (`Na__McpHeight`, pure Ruby: a counting sort on an even sample, percentiles by pc_terrain.py's rank rule). The engine is unchanged. An older viewer refuses with `unsupported`.
- **Checked against the kit.** The terrain kit agrees to the last digit: the same box of the SK02 GeoSLAM cloud (x 2,000 to 6,000, y 6,000 to 12,000 mm, 46,531 points, all of them) through `pc_terrain.py rasters --res 50` and through the heightmap gave the same 80 x 120 grid, the same counts, z02, z10, z50, z90 and z98 equal to 0.0 mm, and the same rgb_top and rgb_low.
- **Versions.** `bridge_version` and `server.version` are `1.0.16`. 56 tools; AGENTS.md and the agent guide say so.
- **Validation.**
  - `ValidateApiUsage` passes (4 viewer seam files). `RunRubyChecks`: 46 of 46 files compile, and `BridgeCore` passes 77 (3 new: the other action's keys refused, save and image paths, an older viewer refused). `PythonServer` 37 (count 56), `--check` and `node --check` pass.
  - The viewer's suites: heights 15, seam 62, fit 14, check 8; its harness main 197 and boxes 84.
  - Live in the SK02 helper window (pid 22360), read-only, after both reloads, with the clouds staying loaded: 1,000,000 of 37.1 M points into 90 x 148 cells of 250 mm took 2.1 s; 5,000,000 into 224 x 368 cells of 100 mm, 10.7 s; a profile up the SK02 staircase (x 16,950, y 11,800 to 15,500, a 300 mm corridor, 20 mm stations): 185 stations from 181,054 points in 0.7 s, every tread a step, the soffit of the flight above as a grey diagonal; through the real server over stdio, 56 tools, a heightmap and a profile with their pictures inline, and a resolution on a profile refused.

### Validation Checklist

- [ ] In each other window, run the viewer's Reload Plugin, then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.16). 22360 is done.
- [ ] Ask for `point_cloud_heightmap {min: [1600, -3900, -1800], max: [24000, 32900, 8700], resolution: 100}` in SK02 with the GeoSLAM cloud: the house, the cars on the drive and the garden falling west should read at a glance.
- [ ] Ask for `point_cloud_heightmap {action: "profile", path: [[16950, 11800], [16950, 15500]], width: 300, step: 20, stats: ["p10", "p50", "p98"]}`: every tread should show as a step.

## Na SketchUp MCP | Version 1.0.15 - 09-Nov-2026 - `point_cloud_check`: How Well the Model Sits on the Scan

- **What Adam asked for.** "Model-to-cloud check", the next tool on the list.
- **`point_cloud_check`** (read-only, the 55th tool):
  - Measures an even sample of the cloud round the groups, components or faces in `ids` against their faces. The box is their world bounds plus `margin` (default 100 mm), or `min` and `max`.
  - Points within `reach` (default 50 mm) are measured; farther ones count as away.
  - Returns overall rms, mean, p50, p95, max and the share within `tolerance` (default 10 mm); the same per part (each group or component directly inside an id, the worst first); the worst spots; and warnings.
  - Sign: positive means the scan lies outside the faces (the model is too small there), negative inside (the model is proud).
  - With `view` and `resolution` it adds a heatmap (green within tolerance, red outside, blue inside, pale grey away) with the model's edges, returned inline.
- **Where the work is done.** The handler turns the faces into world triangles (`Face#mesh` through `Na__Serializer__ToWorld` and the face's world normal), labelled by part. The rest is in Point Cloud Viewer 0.14.3 (`Na__McpCheck`, pure Ruby: a grid of cells `reach` wide, exact nearest triangle). The engine is unchanged. An older viewer refuses with `unsupported`.
- **First real run.** the SK02 staircase (`Staircase__MainStair__`, 1,420 faces, 14 parts) against the GeoSLAM cloud: 8,901 of 20,000 points within 50 mm, rms 16.1 mm, 53% within 10 mm, mean +7.8 mm (the scan outside the faces). The worst spots are the lower treads at +15 to +21 mm, the carpet the survey notes as reading 10 to 15 mm proud. The worst part is the landing base rail (rms 27), the closest the landing handrail (rms 10.2). 2.7 s.
- **Versions.** `bridge_version` and `server.version` are `1.0.15`. 55 tools; AGENTS.md and the agent guide say so.
- **Validation.**
  - `ValidateApiUsage` passes (3 viewer seam files). It caught my registry dependency named `Sketchup::PolygonMesh`; that is `Geom::PolygonMesh#polygons`.
  - `RunRubyChecks`: 46 of 46 files compile, and `BridgeCore` passes 74 (1 new: an older viewer refuses the tool). `PythonServer` 37 (count 55), `--check` and `node --check` pass.
  - The viewer's suites: check 8, seam 53.
  - Live in the SK02 helper window (pid 22360), read-only, after both reloads, with the clouds staying loaded:
    - the staircase check above, and its heatmap looking along the stair;
    - through the real server over stdio: 55 tools, a check with its heatmap inline, and a reach under tolerance refused;
    - 5,000 points gave rms 15.9 and mean +7.6, against 16.1 and +7.8 at 20,000.

### Validation Checklist

- [ ] In each other window, run the viewer's Reload Plugin, then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.15). 22360 is done.
- [ ] Ask for `point_cloud_check {ids: [<staircase id>], view: "right", resolution: 8}` in SK02. The lower treads should read red (the carpet), and the landing base rail is the part to look at first.

## Na SketchUp MCP | Version 1.0.14 - 09-Nov-2026 - `point_cloud_fit`: Shapes From the Points

- **What Adam asked for.** "Shape fitting next", the second tool on the list after the overlays.
- **`point_cloud_fit`** (read-only, the 54th tool): a plane (any, or held horizontal or vertical), a line, a circle or a cylinder along x, y or z, or a box turned about an axis (a post's width, depth and turn), fitted to the points of a box.
  - Each comes with rms, p95 and `inlier_share`, in the call's units.
  - Warnings when under 30% of the points fit, and when a circle covers under 60 degrees or sits near `max_radius`. Its default `max_radius` is the box's larger side.
  - The rules and the maths are in Point Cloud Viewer 0.14.2 (`Na__McpFit`, pure Ruby, on an even sample from `napc_box_points`), so the engine is unchanged.
  - A viewer before 0.14.2 refuses with `unsupported`.
- **Checked on real data before shipping.** The SK02 GeoSLAM stair, offline through SketchUp's Ruby and then live:
  - tread 5 level 1,197.1, where its histogram peaks;
  - riser 5 at y 13,200.3;
  - the wall plumb to 0.03 degrees;
  - the bullnose, boxed to its curve: r 166.4 at (16,539.5, 12,274.2), rms 1.7. An independent scipy fit gave r 168.5 to 171.9.
  - With its straight riser in the box the circle came out 398 mm over 45 degrees, so that case now warns. The skill's survey table says r 159 at (16,535, 12,267): worth a look.
- **Docs.** AGENTS.md and the agent guide said 51 tools since 1.0.9; they now say 54.
- **Versions.** `bridge_version` and `server.version` are `1.0.14`.
- **Validation.**
  - `ValidateApiUsage` passes (2 viewer seam files checked). `RunRubyChecks`: 46 of 46 files compile, and `BridgeCore` passes 73 (2 new: an older viewer refuses the tool, and an unknown shape is refused first). `PythonServer` 37 (count 54), `--check` (54 tools) and `node --check` pass.
  - The viewer's suites: fitting 14, seam 49.
  - Live in the SK02 helper window (pid 22360), at Adam's word, read-only. The MCP__Workshop__ test window had been closed. I reloaded the viewer (its clouds came back from cache within seconds) and then the MCP:
    - six fits, 0.1 to 0.7 s each, equal to the offline ones;
    - the tangent warning fired on the box with the riser and stayed quiet on the curve alone;
    - through the real server over stdio: 54 tools, a fit, an unknown shape refused by the schema, and a fit inside a rollback trial.
  - Nothing in the model changed, and its look and clip box are as they were.

### Validation Checklist

- [ ] In each other SketchUp window, run the viewer's Reload Plugin (Settings), then Extensions > Na SketchUp MCP > Reload Plugin Data. A window still on viewer 0.13 code also needs Reload All for its clouds. The SK02 helper (22360) is done.
- [ ] Ask an agent for `point_cloud_fit {shape: "plane", orientation: "horizontal", min, max}` on a floor you know the level of. It should agree within a few millimetres.
- [ ] Look at the bullnose radius: the scan says 166 to 172 mm on the carpet face, the survey table 159.

## Na SketchUp MCP | Version 1.0.13 - 09-Nov-2026 - The Model and the Point Cloud in One Picture

- **What Adam asked for.** Asked which tools would help agents most with the point clouds, he chose the first on the list: "Yes, overlay first". Until now an agent could not see the cloud and its model together, so every check against the scan went through the skill's `pc_kit.py` composites.
- **`view_capture include_point_cloud: true`.** After `write_image`, while the capture's camera is still set, the Point Cloud Viewer's seam (0.14.1) draws the clouds on show over the file in place. It uses the live overlay's camera maths and each cloud's own look, clip box and point budget, so the clouds sit on the model exactly as on screen. Works for png and jpg, and for transparent captures. The result's `point_cloud` says what was drawn (clouds, points, pixels covered, ms).
  - **Measured before relying on it.** SketchUp's `write_image` keeps the camera's vertical field of view for any image shape: three cubes captured at 1600 x 800 and 800 x 1000, perspective and parallel, landed within 1.2 px of the formula. Given float sizes, write_image ignores them and writes the screen's physical size. This handler always passes whole numbers.
  - **A problem never costs the capture.** An older viewer, the overlay switched off, no cloud loaded or an engine error each come back as a warning, with the plain capture.
- **`point_cloud_slice overlay_ids`** (image and density): every visible edge of those entities, at any depth, drawn in red over the slice, projected the same way. Soft and hidden edges are left out, and the coordinate rule stays in `Na__Serializer` / `Na__Coordinates`. `overlay_clip: true` keeps only the parts inside the box. The result's `overlay` says how many edges reached the picture. `overlay_ids` with count, histogram or points is refused, and so is a viewer before 0.14.1.
- **Versions.** `bridge_version` and `server.version` are `1.0.13`. Still 53 tools. The viewer is 0.14.1, its engine unchanged.
- **Validation.**
  - `ValidateApiUsage` passes. `RunRubyChecks`: 46 of 46 files compile, and `BridgeCore` passes 71 (1 new: `overlay_ids` refused on count and by an older viewer). The stand-in `Geom::Point3d` in that suite gained `to_a`, which the real class has. `PythonServer` 37 and `--check` (53 tools) pass. The viewer seam's suite passes 43.
  - Live in `MCP__Workshop__` (pid 23284) after both reloads, with `exterior_shell.las` imported and removed after. One rollback trial (7 steps, model unchanged) made a 12 x 8 x 6 m box on the fixture's walls:
    - composites in perspective (1280 x 800) and parallel front (900 x 900), as png, jpg and transparent png. In the front view the cloud fills rows 150 to 750 and the box's edges are at rows 149 and 750;
    - density, top, with the box's edges: the red rectangle sits on the walls, within the one pixel their noise spans at 20 mm a pixel; an image of the front wall slab with `overlay_clip` drew 8 of the 12 edges.
    - Overlay off: the capture came back with the note and a warning. The real server over stdio: both options in the schemas, the composite returned inline, and `overlay_ids` on count refused.
  - Not run: windows other than the workshop (each needs both reloads).

### Validation Checklist

- [ ] In each SketchUp window, run Point Cloud Viewer > Settings > Reload Plugin, then Extensions > Na SketchUp MCP > Reload Plugin Data (1.0.13). A window still on 0.13 code needs Reload All for its clouds too (the 0.14.0 engine is new to it).
- [ ] In SK02, `view_capture {scene: "STAIRS-POINTCLOUD", include_point_cloud: true}` should show the stair and the GeoSLAM points together, as on your screen.
- [ ] `point_cloud_slice {action: "density", view: "right", resolution: 5, overlay_ids: [<balustrade id>], min, max}` should draw the balustrade's edges in red on the stair's density.

## Na SketchUp MCP | Version 1.0.12 - 09-Nov-2026 - `point_cloud_slice`: Points, Density and One-Pass Histograms

- **What Adam asked for.** The follow-up 1.0.9 proposed, "Point cloud viewer: native box points and density grid", done "here". He agreed: the viewer's engine moves to ABI 9; histograms in one pass; points in the reply or in a `.npz`; density on a log scale.
- **The engine (Na Point Cloud Viewer 0.14.0).** Two native calls, `napc_box_points` and `napc_box_grid`, and the seam that uses them. The viewer's devlog and ARCHITECTURE section 29 have the details.
- **`point_cloud_slice`, three changes:**
  - `points`: `limit` points (default 1,000), an even sample of the box because the viewer stores clouds shuffled. Up to 1,500 come back in the reply, in the call's units (1,500 is about 36,000 characters, under the server's 45,000). With `save_path`, up to 5,000,000 go to a `.npz` (`p`: x, y, z in model mm, float64; `c`: colour) that numpy and the skill's `pc_kit.py --pts` read. `save_path` must be a `.npz` in a folder that exists, and is never replaced without `overwrite`.
  - `density`: the same frame, grid and pixel-to-mm mapping as `image`, but each pixel counts the points behind it, darker = more. Log scale by default (`scale: "linear"` otherwise), clipped at the 99.5th percentile. It reports `max_per_pixel` and `p99_5_per_pixel`, and comes back inline like `image`.
  - `histogram`: one pass over the cloud whatever the bins, up to 10,000 (was 200 at one pass per bin). The last bin keeps the box's far face, so the bins add up to what `count` gives.
- **An older viewer.** With a viewer before 0.14.0, `points` and `density` refuse with `unsupported` and name the version to install. With 0.13.1 (the first seam) `count`, `histogram` (one pass per bin, at most 200) and `image` still work, as in 1.0.9.
- **Versions.** `bridge_version` and `server.version` are `1.0.12`. Still 53 tools.
- **Validation.**
  - `ValidateApiUsage` passes. `RunRubyChecks`: 46 of 46 files compile, `BridgeCore` passes 70 (2 new: the `.npz` path rules, and the refusal from an older viewer). One 1.0.9 check took `points` as its example of an unknown action; it now uses `cut`. `PythonServer` 37 and `--check` (53 tools) pass.
  - The viewer's suites: native 39, seam 35, harness main 197, boxes 84, multi 96, hotkeys 134.
  - Live in `MCP__Workshop__` (pid 23284) after both reloads, with `exterior_shell.las` imported and removed after:
    - histograms: the same peaks and counts as 1.0.9's per-bin ones (walls at -5,993.1 and +6,007.7 with 1,426 and 1,462 points on 100 mm bins; 724 at +6,000.9 on 2 mm bins). 10,000 bins in one call add up to 240,000, the box's count; before the far-face fix they were 21 short, the points exactly on the box's top face;
    - points: 5 inline; 2,000 inline refused, naming `save_path`; all 120,027 of the box to a `.npz`, equal to `pc_kit.py extract` from the same cache (same points, same order, within 0.0002 mm, same colours), and `pc_kit.py hist` reads it;
    - density, top and front: the walls black where every point falls, the face-on walls a light speckle;
    - the real server over stdio: the new enum and schema, the density PNG inline, 1,500 points in 35,829 characters, `limit` 5,000,001 and `scale` "cube" refused by the schema, a missing folder refused, and both new actions inside a rollback trial.
  - Both SK02 windows (pids 13892 and 22360), still on viewer 0.13 code, refused the new DLL once and kept their engines and both clouds (checked read-only).
  - Left behind: the workshop (not saved) still holds the empty viewer index record from 1.0.9. Nothing else.

### Validation Checklist

- [ ] In each SketchUp window, run Point Cloud Viewer > Settings > Reload Plugin, then Reload All for its clouds (the engine is new), then Extensions > Na SketchUp MCP > Reload Plugin Data. The status dialog should read 1.0.12.
- [ ] In SK02, `point_cloud_slice {action: "density", view: "right", resolution: 5, grid: 100, min, max}` round the stair should show the treads, risers and spindle row darker than the walls behind.
- [ ] `point_cloud_slice {action: "points", limit: 2000000, save_path: "<folder>/stair.npz", min, max}` writes a file that `pc_kit.py render --pts` draws.
- [ ] When you're happy, commit the Plugins repo, including the rebuilt DLL, and pull it on the 2027 machine.

## Na SketchUp MCP | Version 1.0.11 - 09-Nov-2026 - `geometry_create_lines`, `geometry_drape`, and Quad Edges

- **What Adam asked for.** After the first SK02 terrain (regions cut into the mesh): "create a surface that's correctly contoured and smoother. Then create a separate group and drape edges (basically, project edges down), so we can create nice arcs and smooth Bezier's ... using soft black, dark grey, and mid grey, pick out the different features and actually draw them in 2D. Then project that onto the surface, but keep everything in a proper SketchUp group so everything doesn't stick to each other." He also asked for "a nice quadrilateral mesh", built as a solid block.
- **`geometry_create_lines` (new).** Many polylines in one call. Each is welded into one curve by default (`Entities#add_curve`), painted with its own material (the SSOT edge greys), and put in a new group so nothing merges or splits. `geometry_draw` could only draw one unwelded polyline per call, and painted faces only.
- **`geometry_drape` (new).** It projects edges straight down onto a surface, like Sandbox Drape, but writes new edges into their own group and imprints nothing.
  - The surface is every upward face of `surface_ids`, at any depth, through `Face#mesh` in world space. Where faces overlap in plan the highest wins, so a solid's top is used and its bottom ignored.
  - Each source segment is cut at every plan crossing with a triangle edge, and each piece takes the plane of its triangle, so it lies exactly on the surface.
  - Each source curve, or chain of loose edges, becomes one welded curve and keeps its material. Source z is ignored, and parts off the surface are measured and left out.
  - The plan maths is three pure functions (`SegmentCross`, `Barycentric`, `PlaneZ`), now checked offline.
- **`geometry_create_mesh`: `smooth_edges` and `quad_edges`.** `smooth_edges` are drawn but shade smooth (soft off, smooth on): a visible quad grid on a smooth surface. `quad_edges` are QuadFace Tools' dividing edges (soft, smooth, `casts_shadows` false, per `TT_QuadFaceTools/entities.rb` `divider_props?`), so two triangles read as one quad there. Order of application: hard, smooth, soft, quad.
- **Versions.** `bridge_version` and `server.version` are `1.0.11`. 53 tools.
- **Validation.**
  - `ValidateApiUsage` passes. `RunRubyChecks`: 46 of 46 files compile, BridgeCore 68 passed (6 new: segment crossing, barycentric weights, plane height, a run split across two triangles, a run partly off the surface, the two routes). `PythonServer`: 37 tests OK (tool count 53). `--check`: 53 tools.
  - Live in MCP__Workshop__ (pid 23284), after Reload Plugin Data, as zero-trace trials:
    - a 4 x 4 bumpy quad grid with both lists: 16 quad dividers and 40 smooth visible grid edges, and QuadFace Tools recognised all 32 triangles;
    - 3 polylines (1 welded curve, 1 unwelded, 1 two-point), draped onto the grid: 3 pieces, 16 edges, materials carried, every draped vertex on the surface (raytest 0.000 mm), and the 600 mm off the surface reported;
    - a capture of hard and smooth-visible grids side by side: the second shades smoothly with its grid still drawn.

### Validation Checklist

- [ ] Reload Plugin Data in each open window: the status dialog should read 1.0.11.
- [ ] New Claude session: `geometry_create_lines` and `geometry_drape` are listed.
- [ ] Draw a few 2D lines over a terrain with `geometry_create_lines`, then `geometry_drape` them onto it: the draped group sits on the surface, and moving it shows the terrain untouched underneath.

## Na SketchUp MCP | Version 1.0.10 - 09-Nov-2026 - `geometry_create_mesh` Softens and Hardens Single Edges

- **What Adam asked for.** "Utilise MCP tools as much as possible, if any tools that you need at your disposal are missing. Build them", while asking for a sandbox-style terrain from his point clouds (SK02 Ascott Gardens). A sandbox terrain hides each grid square's triangle diagonal and keeps the grid lines. `smooth` / `smooth_angle` can't do that: on near-flat ground the diagonals and the grid lines meet at the same tiny angles.
- **Two optional parameters.** `soft_edges` and `hard_edges` are lists of `[i, j]` vertex-index pairs. After `smooth`, `hard_edges` set soft and smooth off, then `soft_edges` set both on. Edges are matched by their end positions in the build frame, the same points the polygons were built from, so it works at any nesting and in world or local coords. `result.mesh` reports `hard_set`, `soft_set` and `pairs_not_found`. A pair that is not a polygon side (or whose faces were skipped) is counted, never guessed, and named in a warning.
- **It also serves furniture.** Lesson L141 (pillows: "harden the seam ring and soften every other edge explicitly") needed exactly this: until now it took a separate `ruby_eval`.
- **Where.** `Na__SketchUpMcp__Handlers__Geometry__.rb` (`na_edge_flags`), and the registry's description and schema (each list up to 400,000 pairs).
- **Versions.** `bridge_version` and `server.version` are `1.0.10`. Still 51 tools.
- **Validation.**
  - `ValidateApiUsage` passes. `RunRubyChecks`: 46 of 46 files compile, BridgeCore 62 passed. `PythonServer`: 37 tests OK. `--check` passes.
  - Live in the MCP__Workshop__ window (pid 23284), after Reload Plugin Data (bridge 1.0.10): a zero-trace trial of a 2 x 2 sandbox grid with `smooth` 30 and both lists. Of 16 edges, `smooth` softened 8. `hard_edges` put one interior grid line back to hard, so 7 were soft, 4 of them the diagonals. A pair that is not an edge was counted and warned.
  - The skill's terrain kit (`learning/generators/terrain/pc_terrain.py build --soften param`) writes these lists. For a bridge before 1.0.10 it uses `--soften ruby`: a rule-based `ruby_eval` step in the same batch, which is how SK02's terrain was built in the 0.4.2 window (bridge 1.0.7).

### Validation Checklist

- [ ] Reload Plugin Data in each open window: the status dialog should read 1.0.10.
- [ ] Start a new Claude session: `sketchup_status` reports server 1.0.10, and `geometry_create_mesh` lists `soft_edges` and `hard_edges`.
- [ ] Build a 2 x 2 grid with its 4 diagonals in `soft_edges`: with hidden geometry off, the grid lines show and the diagonals don't.

## Na SketchUp MCP | Version 1.0.9 - 09-Nov-2026 - Point Cloud Tools: `point_cloud_state`, `point_cloud_clip`, `point_cloud_view`, `point_cloud_slice`

- **What Adam asked for.** On the SK02 stair balustrade: "build MCP tools as you might require for manipulating the point cloud, clipping boxes, and what point is visible". That session built a kit in the modelling skill (`na_pc_kit.rb` through `ruby_eval`, `pc_kit.py` reading the viewer's `.napc` cache with numpy) and proved it live. This version turns it into four MCP tools, so any session can read the clouds, set clip boxes and measure without scripts of its own. Adam agreed the names and shape: four tools, the rules in the viewer, the viewer's DLL as it is.
- **A thin seam, like the library and Element Assembly Studio.** The rules live in Na Point Cloud Viewer 0.13.1 (`02__Src__AppModules/95__System__McpOperations`, entry points `Na__PointCloudViewer__McpRead` and `...McpEdit`, refusals `Na__McpOperationsError`). `Na__SketchUpMcp__Handlers__PointCloud__.rb` reads lengths in the call's units, turns `ids` into world bounds, picks the capture path and passes `per_inch`, so results come back in the call's units. Without the viewer, every tool refuses with `unsupported` and names the version to install.
- **`point_cloud_state`** (read-only): per cloud its id, name, colour, shown, loaded, points, file, source unit, look, bounds, clip box, the clip scene showing (and whether its box was changed since) and every clip scene. Also `cache` (the `.napc` path and whether it exists) and `local_to_model` (12 numbers, inches) for the skill's offline numpy kit; the terrain session asked for these two. Plus the overlay, the point budget and the active cloud.
- **`point_cloud_clip`** (`"operation": false`, not allowed in `batch_execute`):
  - `box`, `around` (entity ids, grown by the viewer's selection margin and rounded outwards onto its 5 mm grid, exactly as Clip Box Around Selection), `on`, `off`, and `scene` (a clip scene by id or name, or `full`).
  - Each is ONE undo step of the viewer's own ("Point Cloud: MCP Clip Box", "Point Cloud: Clip On" and so on), reported as `undo_step`. A call that changes nothing leaves none.
  - `box` and `around` switch those clouds and the overlay on, as Draw Clip Box does.
- **`point_cloud_view`** (view settings only, no undo step): shown, point_size_px, opacity_percent, colour_mode, point_budget, overlay, and `reload` (the viewer's own Reload of the clouds that are not loaded). Values outside the viewer's limits are refused, not clamped.
- **`point_cloud_slice`** (read-only), on the viewer's native engine as it is:
  - `count`: every point in a box, exact (`napc_box_count`).
  - `histogram`: points per bin along x, y or z; peaks with a weighted centre finer than a bin; percentiles p1 to p99. Each bin is one pass over the cloud: 28 ms a pass, measured read-only on SK02's 42.7 M-point RealityCapture cloud (pid 13892). So at most 200 bins, about 6 s on that cloud.
  - `image`: the viewer's renderer (`napc_render_png`), parallel along a model axis, the box as its clip box, written as a greyscale PNG (white paper, black points, a grid with every fifth line darker), with `u` and `v` mappings from pixel to model. It comes back inline, as `view_capture` does. The nearest point wins each pixel, so it shows shape, not density.
  - Not yet: the points themselves and density images. They need two native calls in the viewer's DLL (proposed: `napc_box_points`, `napc_box_grid`, ABI 9).
- **Validation knows the viewer.** `ValidateApiUsage` counts every def in the viewer's modules as defined and checks its seam like the bridge. It now also counts `attr_accessor`, `attr_reader` and `attr_writer` names as defined, because the viewer's slots are plain attributes.
- **Versions.** `bridge_version` and `server.version` are `1.0.9`. The registry has 51 tools. The viewer is 0.13.1 (its own devlog).
- **Validation.**
  - `ValidateApiUsage` passes: 51 tools, 195 API dependencies; 1 viewer seam file checked, 47 defining. `RunRubyChecks`: 46 of 46 files compile, and `BridgeCore` passes 62 (5 new: the refusal without the viewer, unknown actions, `per_inch`, the routes, the batch rule). `PythonServer` passes 37 (the tool count is now 51). `--check` and `node --check` pass.
  - The viewer seam's own suite (`95__System__McpOperations/tests/mcp_operations_unit.rb.test`) passes 23. The viewer's harness passes on the changed tree: hotkeys 134, boxes 84, multi 96, main 197.
  - Live in the `MCP__Workshop__` window (pid 23284, SketchUp 26.2.243) after both reloads. The viewer's fixture `exterior_shell.las` (240,000 points, 12 x 8 x 6 m) was imported for the trial and removed after:
    - state on an empty model and on a loaded one; count: all 240,000, and 120,027 in one half;
    - histogram along x: walls at -5,993 and +6,008 on 100 mm bins, and +6,000.9 on 2 mm bins (the fixture's wall is at 6,000);
    - images, top and left: the walls fall on the pixels the mapping gives (x -6,000 at column 10 of a box from -6,200 at 20 mm a pixel);
    - box; off; off again (no undo step); on; scene by name, by id, `full`, `full` again (no undo step); around with a 50 mm margin, the default and in metres. Three undos and three redos each restored the viewer's state. Refused as they should be: too thin a box, an unknown cloud, an unknown scene, and point_cloud_clip in a batch;
    - view: look, shown, budget, overlay and reload changed; out-of-range values refused; the look put back;
    - the real server over stdio: 51 tools, schemas expanded, point_size_px 11 refused by the schema, the image returned inline, and the read tools inside a rollback trial.
  - Left behind by the trial: the workshop (not saved) holds an empty viewer index record (`Na__PointCloudViewer__Clouds`, no clouds). The fixture's point cache (4.8 MB) and the workshop's local backups are in the viewer's git-ignored folders. No project model was changed.
  - Not run: a fresh Claude session listing the tools (a running server must restart), and the SketchUp 2027 copy (on the other machine: it gets this through git).

### Validation Checklist

- [ ] In each open SketchUp window, run the Point Cloud Viewer's Reload Plugin (Settings), then Extensions > Na SketchUp MCP > Reload Plugin Data. The status dialog should read 1.0.9.
- [ ] Start a new Claude session in an SK02 model. `point_cloud_state` should list the GeoSLAM and RealityCapture clouds with your clip scenes.
- [ ] `point_cloud_clip {action: "box", min: [...], max: [...]}` should clip the clouds on show, and one Ctrl+Z should put your box back. `point_cloud_clip {action: "scene", scene: "<your scene>"}` returns to your clip scene.
- [ ] `point_cloud_slice {action: "image", view: "right", resolution: 5, grid: 100, min, max}` round the stair should match your STAIRS-POINTCLOUD scene.
- [ ] When you're happy, commit the Plugins repo and pull it on the 2027 machine.

## Na SketchUp MCP | Version 1.0.8 - 09-Nov-2026 - `entity_studio` and `entity_studio_edit`: Element Assembly Studio Pro From an Agent

- **What Adam asked for.** "You will need to build MCP tools to be able to orchestrate the SketchUp plugin Entity Studio Pro", to make a preset for a common British front door and fix its fielded panels.
- **Two tools, one thin seam,** the way `asset_library` reaches Component Editor Tools. The rules stay in Element Assembly Studio Pro 2.5.3 (`02__Src__AppModules/60__System__McpOperations`); `Na__SketchUpMcp__Handlers__EntityStudio__.rb` resolves `instance_id` and `position`, calls `Na__AssemblyStudio::Na__McpOperations`, swaps the instance it returns for its id and world bounds, and turns `Na__McpOperationsError` into `Na__McpError`. Without the plugin both tools refuse with `unsupported` and name the fix.
- **`entity_studio`** (read-only): `status`, `list_presets` (filter family or text), `get_preset` (values, narrowed by `keys` or `prefix`), `list_handles` (asset keys as the dropdowns show them), `inspect` (every MOD part and every fielded panel cell of a placed element: solid, volume_mm3, faces, nested_groups; containers flagged).
- **`entity_studio_edit`** (`"operation": false`, not allowed in `batch_execute`):
  - `build` and `update`: exterior single and double doors from a preset and/or flat config `values`, through the door engines, which open and commit their own undo operation ("Create Exterior Single Door"), so `model_undo` steps 1 removes a build. `build` refuses inside an open group: the engines place at the model root.
  - `save_preset`: through the Presets Store (next EASnnn code, file name, pretty writer).
  - `refresh_preview`: the open dialog draws the gallery picture with its own SvgCapture and stores it through its existing `na_presetsUpdateConfig` callback. It lands a moment after the call; `get_preset` `has_preview` confirms it.
  - `open_dialog`, `reload` (Adam's Reload Scripts). `reload` closes an open dialog first and opens a fresh one, because the dialog Reload Scripts reopens sent no callbacks back.
  - `build` and `update` load the plugin's material library first. Without it every finish resolved to nothing, and the first EAS012 built this way had blank glass.
  - Windows, sliding, bifold and interior doors are refused by build and update: their creation steps live in the dialog's callbacks.
- **Validation also checks the new partner.** `ValidateApiUsage` counts every def in Element Assembly Studio's modules as defined and checks its seam like the bridge.
- **Versions.** `bridge_version` and `server.version` are `1.0.8`. The registry has 47 tools.
- **Validation.**
  - `ValidateApiUsage` passes: 47 tools, 187 API dependencies; 1 Element Assembly Studio seam file checked, 131 defining. `RunRubyChecks`: 45 of 45 files compile, `BridgeCore` passes 57. `PythonServer`: 37 pass (the tool count assertion is now 47). `--check` and `node --check` pass.
  - Live in the SketchUp 2026 workshop window, bridge reloaded, every action called through the bridge: `status`, `list_presets`, `get_preset`, `inspect`, `build` (ADR003, 4 of 4 fielded panels solid), `update`, `reload`, `save_preset` (EAS012), `open_dialog`, `refresh_preview` (picture stored, `has_preview` true).
  - Not run: a fresh client session listing the two tools. A running server must restart before its client sees them.

### Validation Checklist

- [ ] Run Extensions > Na SketchUp MCP > Reload Plugin Data (and Element Assembly Studio's Reload Scripts) in each open window. The status dialog should read 1.0.8.
- [ ] Start a new Claude session: `sketchup_status` reports server 1.0.8, and `entity_studio {action: "status"}` names Element Assembly Studio Pro 2.5.3.
- [ ] `entity_studio_edit {action: "build", preset: "EAS012", position: [0, 0, 0]}` places the British front door; one Ctrl+Z removes it.

## Na SketchUp MCP | Version 1.0.7 - 05-Nov-2026 - The Server Stays on Its Window

- **What Adam asked for.** "Do this task here: Stop the MCP following the newest SketchUp window."
- **The fault.** With no pid selected, `Na__BridgeClient__Target` returned the newest live window on every call, so opening a second SketchUp window silently moved every later call to it. While filing the entourage people, opening the SK02 workshop sent seven library saves to the wrong window. They were refused only because the component was not there; a model edit would have landed in the wrong model.
- **The fix.** When it first needs a window, the server takes the newest live one and stays on it until `select_pid` changes it. Opening another window never moves it.
- **When that window closes, it refuses.** It does not pick another, because the next call could be an edit meant for the window that closed. The message names what is open: "The SketchUp window this server was using (pid N) is no longer running its bridge, so nothing was sent. Open now: pid N (Title), pid N (Title)."
  - A bridge restarting in the same window, as Reload Plugin Data does, is still reached, because the pid is the same.
  - After SketchUp is closed and reopened, the first call is refused until `select_pid`. That is one extra step, and it means someone has said which model they mean.
- **`sketchup_status` says which window, from the first call.**
  - `selected: true` and `selected_pid` mark the window in use, not only after `select_pid`.
  - Titles are the model open now, read with a ping limited to one second. The connection file can be out of date: McpTemp showed a blank title all morning on 05-Nov-2026. A window too busy to answer keeps what its file says. Each status call adds a `ping` row to every open window's activity log.
  - `windows_note` appears when more than one window is open.
- **Each client session has its own server, so its own window.** Two sessions can work in two windows. A server that is already running keeps the old behaviour until it is restarted.
- **Also.** The "not connected" hint no longer names SketchUp 2026. The `sketchup_status` description, the agent guide and the header comments say how this works now.
- **Versions.** `bridge_version` and `server.version` are `1.0.7`. All the code is in the Python server; on the Ruby side only a comment changed.
- **Validation.**
  - `ValidateApiUsage` passes: 45 tools, 182 API dependencies. `RunRubyChecks`: 44 of 44 files compile, and `BridgeCore` passes 57. `--check` and `node --check` pass.
  - `PythonServer`: 37 tests pass, 13 of them new. On the old code 10 of the new ones failed, the first with `['ping'] != ['ping', 'geometry_create_solid']`: the create call had gone to the new window. The other 3 guard what must not change: `select_pid`, a restarted bridge and `NA_SKETCHUP_MCP_PID`.
  - Live, 15 of 15 checks: the real server over stdio, real bridges at 1.0.7 and two throwaway windows, with read-only calls. The second window was sent no work. When the window in use closed, the call was refused and named the windows open, and `select_pid` recovered. The window already open was left alone.
  - Not run: the 2026 Plugins folder, which is an older copy at 1.0.4 and does not have this fix.

### Validation Checklist

- [ ] Start a new Claude session, or reconnect the server. `sketchup_status` should report server 1.0.7.
- [ ] With one model open, call `sketchup_status`, then open a second SketchUp window. The next call should still report the first model.
- [ ] Close the first window. The next call should be refused and name the second window, and `select_pid` should bring it back.

## Na SketchUp MCP | Version 1.0.6 - 05-Nov-2026 - `entity_get` Answers for Definitions, Materials and Tags

- **What Adam asked for.** Filing the Northway columns (10_2601, 10_2602) turned up two plugin faults, and he said "Yes, fix them". This version is the first. The second, `asset_library_edit save` with `rename_in_model`, is in Component Editor Tools 0.6.8 (Na Noble3d Modelling Tools 0.9.24).
- **The crash.** `entity_get` on a definition id raised `NoMethodError: undefined method 'instances' for an instance of Sketchup::DefinitionList`, and the whole call failed, whichever other ids were in it. Materials and tags had the same fault, through `Sketchup::Materials` and `Sketchup::Layers`, though the tool's description lists all three.
- **The cause.** `Na__Coordinates__ContainerPathForEntity` treated any parent other than the model as a definition. Measured live on 27.0.267, these three have a collection as their parent. Older SketchUp versions were not checked.
- **The fix.** Only a parent that is a `ComponentDefinition` has a container. Anything else has an empty path, as a root entity does, so no coordinates change.
- **A second fault, found by the live test.** With the crash gone, a definition came back with no `name`. The API makes `ComponentDefinition` a `Drawingelement`, and `na_add_names` skips those. It now names a definition.
- **Versions.** `bridge_version` and `server.version` are `1.0.6`.
- **Validation.**
  - `ValidateApiUsage` passes: 45 tools, 182 API dependencies. `RunRubyChecks`: 44 of 44 files compile. `PythonServer`: 24 tests. `--check` and `node --check` pass.
  - `BridgeCore`: 57 pass, 7 of them new. On the old code 3 of the new ones failed, with the same `NoMethodError` Adam's call raised. The other 4 guard what must not change.
  - Live, 27 of 27 checks in a throwaway SketchUp 27.0.267 window that booted bridge 1.0.6:
    - definition, material and tag ids in one call, with the definition's name, size and `parent: model root`;
    - a face in a group moved and rotated, nested three deep: bounds 900..1000, 2010..2050, z 300 and area 4000 mm2, as worked by hand;
    - a face in a group scaled 2 x 3: bounds -500..-300, 0..300 and area 60000 mm2, as worked by hand.

### Validation Checklist

- [ ] Run Extensions > Na SketchUp MCP > Reload Plugin Data in each window that was already open. A new window has the fix already. The status dialog should read 1.0.6.
- [ ] Restart the MCP client if `sketchup_status` still reports server 1.0.5.

## Na SketchUp MCP | Version 1.0.5 - 01-Nov-2026 - Zero-Trace Trials Without FAILED Rows (`batch_execute` rollback)

- **What Adam asked for.** "Check the MCP plugin in my SketchUp folders itself and make sure any of these errors listed here are corrected." His activity log from the bed range session (`SK02__ModelingHelper__AssetOptimisation__`) had six FAILED rows:
  - four `batch_execute ... FAILED - Batch step N (entity_get) failed: No entity for ids: 987654321. Every step was undone (atomic batch).`, at 13:03:55, 13:29:09, 13:35:33 and 13:38:39;
  - 13:03:35 `FAILED - Batch step 0 (ruby_eval) failed: TypeError: reference to deleted Group`;
  - 13:00:36 `FAILED - Batch step 0 (ruby_eval) failed: ArgumentError: cannot remove an instance in the active editing path`.
- **The four `987654321` rows were zero-trace trials, not faults.** The skill's `su_bridge.py trial` ended every trial with `entity_get [987654321]`, a step that always fails, so that SketchUp would undo the batch. The log could only record that as FAILED.
- **`batch_execute rollback: true` makes the trial a feature** (CommandRouter `na_run_batch`, new `na_with_rollback`):
  - every step runs inside one operation that is always aborted, so no undo step is left;
  - the results come back in `result.steps`, with `rolled_back: true`;
  - the log reads `ok - Trial: N step(s) ran, then every step was undone; the model is unchanged.`;
  - a step that really fails inside a trial is logged as `FAILED - Trial step N (...) failed: ... Nothing was changed (trial).`;
  - `rollback` with `atomic: false` is refused, since a trial keeps nothing;
  - camera moves and scene activation are still not undone, as before.
  - The registry has `rollback` in the schema and one sentence in the description.
- **The two `ruby_eval` rows were the agent's own code**, fixed in the skill's generators rather than the plugin:
  - names are now read before `erase_entities`, because a deleted entity raises on access;
  - the rebuild step stops with a plain message when the asset is open for editing (`model.active_path`), instead of SketchUp's ArgumentError.
- **Skill side.**
  - `su_bridge.py trial` sends `rollback: true` to bridge 1.0.5 and newer. It checks `bridge_version` with `ping` first, because an older bridge would ignore the flag and keep the batch.
  - Older bridges keep the sentinel step.
- **Docs.** AGENTS.md (Live Testing Without Leaving a Trace) and the agent guide (Undo, Safety and Timeouts).
- **Versions.** `bridge_version` and `server.version` are `1.0.5`.
- **Validation.**
  - `ValidateApiUsage` passes: 45 tools, 182 API dependencies, 4,372 method calls, 214 constants and 45 routes, with 7 partner files checked.
  - All 44 Ruby files compile. BridgeCore passes 50 of 50. PythonServer passes 24 of 24: `test_batch_validation` now also sends a rollback batch, and one with `rollback: "yes"`, which is refused. `--check` and `node --check` pass.
  - **Live** in `SK02__ModelingHelper__AssetOptimisation__1.2.0__` (pid 31588), after Reload Plugin Data (42 files, 0 errors):
    - a two-step trial came back rolled back and logged `ok - Trial: 2 step(s) ran...`;
    - a trial with a failing step logged `FAILED - Trial step 1 ... Nothing was changed (trial).`;
    - `rollback` with `atomic: false` was refused;
    - the definitions (309) and root entities (33) were unchanged, with no trial geometry left.

### Validation Checklist
- [ ] Restart the MCP server or client, so it reports 1.0.5 and shows `rollback` on `batch_execute`.
- [ ] Use Extensions > Na SketchUp MCP > Reload Plugin Data in every other open SketchUp window. Only the asset optimisation workshop was reloaded.
- [ ] Ask an agent for a zero-trace trial. The status dialog shows `ok - Trial: ...`, not FAILED.
- [ ] The two FAILED rows at about 15:32 in the workshop's log were the deliberate negative tests above, not faults.

## -----------------------------------------------------------------------------

## Na SketchUp MCP | Version 1.0.4 - 26-Oct-2026 - `list_entities` Tool Alias & Multi-Machine Component Library Path Fallback

- **What Adam asked for.**
  - Activity log showed `08:52:17 list_entities 0 FAILED - Unknown bridge command 'list_entities'.` because agents frequently guess `list_entities` when querying entities in the active context (`entity_query`).
  - Activity log showed `08:52:54 asset_library 2 FAILED - The library folder does not exist: D:/06_CoreLib__Web3D/SketchUp__SourceFiles/10__SketchUp__CoreComponentLib` when working on his second studio machine where the library is at `D:\30__Weblib__3dAssets\SketchUp__SourceFiles\10__SketchUp__CoreComponentLib`.
- **`list_entities` added as a first-class bridge tool (45 tools in all).**
  - Registered `list_entities` in `02__Plugin__CoreAppData/Na__SketchUpMcp__CoreAppData__ToolRegistry__.json` with the full `entity_query` input schema and API dependency list.
  - Routed `'list_entities' => [:Na__Handlers__Query, :Na__Handlers__Query__EntityQuery]` in `04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__CommandRouter__.rb`.
- **Multi-machine library root resolution in Component Editor Tools (`0.6.5`).**
  - `Na__UserConfig.Na__ComponentEditorTools__LibraryPath` in `01__AppCore/Na__ComponentEditorTools__AppCore__UserConfig__.rb` now checks whether `components_library_path` exists on disk, and if not, automatically falls back across `components_library_fallback_paths` (`D:/06_CoreLib__Web3D/SketchUp__SourceFiles/10__SketchUp__CoreComponentLib` and `D:/30__Weblib__3dAssets/SketchUp__SourceFiles/10__SketchUp__CoreComponentLib`).
- **Versions.** `bridge_version` and `server.version` are `1.0.4`.
- **Validation.**
  - `ValidateApiUsage` passes: 45 tools, 182 API dependencies, 4,365 method calls, 214 constants and 45 routes, with 7 partner files checked.
  - All 44 Ruby files compile. BridgeCore passes 50 of 50, PythonServer passes 24 of 24, and `mcp_operations_unit.rb.test` passes 76 of 76.

### Validation Checklist
- [x] Reload Plugin Data in SketchUp (`pid 7668`) and call `list_entities` via `su_bridge.py`.
- [x] Call `asset_library {"action": "overview"}` on Machine B (`D:/30__Weblib__3dAssets/...`) and verify it resolves automatically.

## -----------------------------------------------------------------------------

## Na SketchUp MCP | Version 1.0.3 - 30-Sep-2026 - Component Library Tools (asset_library, asset_library_edit)

- **What Adam asked for.** Agents should be able to use his component library through his own Component Editor Tools (Gallery, Index, renaming), and save new assets into it with the right number, folder and name.
- **Two new tools, 44 in all.**
  - `asset_library` (read-only) has these actions:
    - `overview`: sets, category and series folders, counts, the next free code per series, the tag and taxonomy maps, and recent journals.
    - `browse`: filtered, paged, and uses the Gallery's extract cache.
    - `get`: definition name, size, library data, a naming check and, optionally, the Gallery thumbnail as an image.
    - `next_code`, `check_name` and `audit`.
  - `asset_library_edit` has `save`, `rename`, `move`, `update`, `archive`, `create_folder`, `apply_plan`, `revert` and `refresh`.
- **A thin seam.** `10__BridgeHandlers/Na__SketchUpMcp__Handlers__AssetLibrary__.rb` resolves the component to save (definition, definition_id or instance_id) and forwards everything else to Component Editor Tools 0.6.4 (`12__McpOperations`, Na Noble3d Modelling Tools 0.9.13). Its `Na__McpOperationsError` becomes an ordinary `Na__McpError`. Without that plugin, both tools refuse with `unsupported` and name the fix.
- **Undo and batches.**
  - The library code opens files inside its own operation, which it always aborts. So `asset_library` is non-mutating, `asset_library_edit` has `"operation": false`, and both are in `NA_BATCH_FORBIDDEN` with the reason.
  - `apply_plan` stops itself after `time_budget_s` (default 45 s) and marks the call as already explained, so the router's slow-call warning does not fire twice.
- **Validator.**
  - `ValidateApiUsage` now counts every def in the Component Editor Tools module as defined.
  - It also checks the 7 files the library tools run inside SketchUp (`12__McpOperations`, and the new library SafeLoad) just like the bridge.
  - `NA_ALLOWLIST` became a reasoned dict. Its only entries are the three stdlib zlib calls used for archive zips (`crc32`, `deflate`, `inflate`).
- **Docs.** The agent guide has a Library row in the tool map, a "Save a component to Adam's library" recipe and a pitfall (library tools stand alone). The server instructions carry one line, AGENTS.md has a seam section, and the README counts are updated.
- **Versions.** `bridge_version` and `server.version` are 1.0.3.
- **Validation.**
  - `ValidateApiUsage` passes: 44 tools, 176 API dependencies, 4,361 method calls, 214 constants and 44 routes, with 7 partner files checked.
  - All 44 Ruby files compile. BridgeCore passes 50 of 50, and the Python server passes 24 of 24.
  - The seam's own suite, `mcp_operations_unit.rb.test` in the Component Editor Tools tests folder, passes 76 of 76.
  - **Live** in `02__BespokeFinialTest` after Reload Plugin Data in both plugins:
    - the live API self-test found 176 of 176 dependencies;
    - `overview` and `audit` read the real library;
    - a 67-step tidy of `Na__CoreLib__3dAssets` passed its dry run and was applied (journal `20260930-142039__Na-CoreLib-3dAssets-tidy-30-Sep-2026`);
    - the audit afterwards found 0 of 58 components breaking the convention.

### Validation Checklist
- [ ] Restart the MCP server or client, so it lists 44 tools and reports 1.0.3.
- [ ] Ask an agent for "the next free code for a ridge finial". It calls `asset_library next_code` (series 13_5000) and gets 13_5002.
- [ ] Ask it to save a placed component to the library. It checks the name, agrees it with you, saves, and the Gallery shows the new file after you switch tabs.
- [ ] `asset_library_edit revert` with that save's journal moves the new file into the journal's `removed/` folder.

## -----------------------------------------------------------------------------

## Na SketchUp MCP | Version 1.0.2 - 30-Sep-2026 - Booleans Fail Fast and Explain; Meshes Always Face Out

- **What the activity log showed** (Adam's `MCP__Testing__`, an agent building a 3,863-face scroll corbel):
  - A `solid_boolean` subtract ran 29.4 s, then failed with "produced nothing", which wrongly blamed overlap.
  - Another subtract ran 29.7 s and left a result with holes. The next union refused it with a bare "Not a solid (manifold): id 16732341".
  - A `view_capture` took 30.8 s.
  - The agent also made 7 separate union calls where one call with 7 `tool_ids` would do.
- **Checked live, read-only.** Neither timelapse plugin was running, so the ~30 s calls are SketchUp itself: its solid engine on dense curved meshes, and one slow render. The corbel and the other remaining solids measured as sound, with positive volumes.
- **`solid_boolean` now checks before SketchUp's engine runs:**
  - A non-solid operand is described in counts by the new `Na__SolidHealth` (`06__.../Na__SketchUpMcp__BridgeHelpers__SolidHealth__.rb`), e.g. "id 17075860 (Trial open box) has 4 open edges (holes)". The fix is in the hint.
  - An inside-out operand (signed volume ≤ 0) is refused, with the `reverse_faces` call that fixes it.
  - For subtract, trim, intersect and split, a tool whose world box does not reach the target is skipped with a warning. When it is the only tool, the call is refused at once with both boxes, instead of after a 30 s engine run.
  - Operands over 2,000 faces get a warning that the engine is slow.
- **After the engine:**
  - A failure names the tool it failed on, the seconds taken and the face count, plus the usual causes. These are coplanar faces (let cutters pass 1 mm beyond), tiny edges and dense curves.
  - A result that is not a solid is reported in the same call: "The result is NOT a solid: ... Undo this step". The summary says so too.
  - Every call returns `seconds`, and a warning is added over 10 s.
- **`geometry_create_mesh` fixes winding.**
  - Each shell is made consistent: a shared edge must run opposite ways in its two faces (`Edge#reversed_in?`), SketchUp's own Orient Faces rule.
  - Closed shells are turned outward (signed volume Σ d·area/3 > 0).
  - The result reports `shells`, `closed_shells`, `faces_flipped` and `shells_turned_outward`, and warns about open shells.
- **Slow calls.**
  - `view_capture` reports `render_seconds` and a readable summary ("Captured 1280 x 800 png (245 KB) in 0.4 s", instead of a list of keys in the activity log). It warns with advice over 10 s.
  - The router warns on any call over 15 s that its handler hasn't already explained.
- **Batches.** Each step keeps its own `warnings`, so they survive when an atomic batch fails.
- **Activity log text.** `entity_query` reads "12 matches, 12 returned.", and `entity_delete` says "1 entity" / "2 entities" instead of "entit(ies)".
- **Docs.**
  - The `solid_boolean` description asks for all tools in one call and explains the checks and the density limits.
  - The `geometry_create_mesh` description explains the orientation fix.
  - The agent guide's pitfalls cover cutters passing 1 mm beyond, dense meshes, undoing a non-solid result at once, and meshes.
- **Versions.** `bridge_version` and `server.version` are 1.0.2.
- **Validation.**
  - All 43 Ruby files compile. BridgeCore passes 50 of 50, including 5 new orientation checks on a cube of doubles: outward, two wrong faces, inside out, wrong first face, open box.
  - `ValidateApiUsage` passes (3,361 calls). The Python server passes 24 of 24.
  - **Live in `MCP__Testing__` after Reload Plugin Data**, three zero-trace trials that SketchUp rolled back completely:
    - an inside-out cube mesh was turned outward, and a cube with two wrong faces had those two flipped; both measured +8,000,000,000 mm³;
    - unnamed solids were named "Box 1000 x 1000 x 1000", "Cylinder 600 x 600 x 900" and "Extruded rectangle 1200 x 600 x 300";
    - a subtract kept the target's name and gave the exact volume, 840,000,000 mm³;
    - a cutter 19 m away was refused instantly with both boxes;
    - an open box was refused as "has 4 open edges (holes)".

### Validation Checklist
- [ ] Restart the MCP server or client, so agents see the new tool descriptions. SketchUp already reloaded 1.0.2 in `MCP__Testing__`; other windows need Reload Plugin Data.
- [ ] Ask an agent to cut a cylinder out of a box whose top face lies exactly on the cylinder's top. The error names the tool and suggests extending it 1 mm. Extended, the subtract works.
- [ ] Rebuild the scroll corbel. Any boolean result with holes is flagged in the same call, and the agent undoes it rather than hitting "Not a solid" on the next step.
- [ ] `view_capture` shows "Captured ... in N s" in the activity log.

## -----------------------------------------------------------------------------

## Na SketchUp MCP | Version 1.0.1 - 30-Sep-2026 - Every Object Gets an Outliner Name

- **The problem.** Agent-made objects showed in the Outliner as a column of plain "Group" entries (Adam's `MCP__Testing__` model), so nothing could be found by name. A group was only named when the agent passed `name`.
- **The fix, in the bridge.** Every group or component it creates now gets a name.
  - The agent's `name` always wins.
  - Without one, `Na__Creation__EnsureName` (in `06__.../Na__SketchUpMcp__BridgeHelpers__Creation__.rb`) names it from its kind and world size in the call's unit, and adds a warning telling the agent to pass `name` next time. Examples:
    - `Box 1200 x 600 x 150`
    - `Extruded rectangle 6000 x 4000 x 2700`
    - `Mesh 3000 x 2000 x 450`
    - `3D text "NOBLE"`
    - `Group 4000 x 215 x 2400` for `group_create`
    - `Cut solid ...` / `Union ...` for a boolean whose target had no name
  - A component gets the name on its definition, so the Outliner shows `<Box 1200 x 600 x 150>` the way it shows any component. One named only through `definition_name` is left alone.
  - SketchUp 2026 already names new section planes (`Section 1`, `Section 2`...), which a live trial confirmed. That name is kept. Only a section left blank would get `Plan section at 1200` / `Section at x = 3000`.
- **Copies keep their name.** `entity_transform` copies and arrays of groups now set the source's name, tag, material, shadow flags and attributes explicitly, as component copies already did. `Group#copy`'s documentation doesn't promise them.
- **Agents are told to name.**
  - The `name` parameter's description, five creation tools, `result_name` and `section_plane` now say the name is how the user finds the object in the Outliner.
  - It is in the server instructions (1,794 of 2,048 characters), the agent guide (now "The Seven Rules", plus a pitfall) and the bundled `sketchup-modelling` skill.
  - Agents are asked to follow the naming style already in the model's Outliner.
- **Versions.** `bridge_version` and the registry `server.version` are now 1.0.1.
- **Validation.**
  - SketchUp's Ruby compiles all 42 files.
  - BridgeCore passes 45 of 45, including 10 new naming checks: sizes in mm and m, flat faces dropping the zero axis, rounding noise, plan and vertical section names, and oblique sections.
  - `ValidateApiUsage` passes (3,261 calls, 209 constants).
  - The Python server passes 24 of 24.
  - Not yet run in SketchUp: see the checklist.

### Validation Checklist
- [ ] **Reload Plugin Data** in SketchUp, then restart the MCP server or client so it picks up the new descriptions.
- [ ] Ask an agent for a box without naming it. The Outliner shows `Box 1200 x 600 x 150`, and the tool result carries the "No name was given" warning.
- [ ] Ask for "a wall called Wall - North". The Outliner shows exactly that.
- [ ] Copy a named group 3 times with `entity_transform copies: 3`. All four show the same name.
- [ ] Subtract an unnamed cutter from an unnamed box. The result shows `Cut solid ...`; with a named target it keeps the target's name.

## -----------------------------------------------------------------------------

## Na SketchUp MCP | Version 1.0.0 - 30-Sep-2026 - First Release: A Local MCP Server for SketchUp 2026

- **New plugin.** It lets any MCP client inspect, model and present the SketchUp model open on this PC: Claude Code, Claude Desktop, Codex (GPT-6 Astra), Cursor, VS Code and Gemini CLI. `Na__SketchUpMcp__Loader__.rb` boots `Na__SketchUpMcp__Modules__/`, laid out like Noble 3D Tools: `02__` data, `03__` core logic, `04__` bridge core, `05__` UI, `06__` helpers, `10__` handlers, `30__` Python server, `40__` tests, `80__` dev tools, `85__` docs, `91__` local config.
- **Architecture.**
  - A Python MCP server (stdlib only, Python 3.9+) talks stdio to the client and TCP to a Ruby bridge inside SketchUp.
  - The TCP link is 127.0.0.1 on port 8385, or the next free port of 10. Each request and reply is one JSON line and carries a per-session token.
  - The bridge is a non-blocking `UI.start_timer(0.05)` pump with a re-entrancy guard. It uses no threads and never blocks a read, so an idle or slow client can't freeze SketchUp.
  - Each SketchUp window (a separate process on Windows) writes `91__UserConfig__LocalOnly/Connections/Na__SketchUpMcp__Connection__<pid>.json`. `sketchup_status` lists every window and `select_pid` chooses one.
- **42 tools**, defined in one registry, `02__Plugin__CoreAppData/Na__SketchUpMcp__CoreAppData__ToolRegistry__.json`:
  - status and model info;
  - model settings, file operations and purge;
  - query, get, outliner and collections;
  - selection and edit context;
  - measuring and ray tests;
  - drawing, nine manifold primitives, EntitiesBuilder meshes, push/pull and Follow Me;
  - geometry edits and solid booleans;
  - annotations, images and section planes;
  - groups and components;
  - transforms, delete and properties;
  - attributes, materials (including PBR), tags and scenes;
  - view get, set and capture (images returned to the agent);
  - undo and redo, send_action, Ruby eval, API lookup, and atomic batches with `"$0.id"` references.

  `--toolset core` keeps the 22 essentials for clients that limit tool counts.
- **Units and coordinates.**
  - Everything is world coordinates in mm (or `units`), degrees and persistent ids, at every nesting depth, inside open, rotated, mirrored and scaled groups.
  - It uses the stacked-local-axes rule from Noble Drawing Tools 5.1.2. `06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Coordinates__.rb` holds the one formula. New groups are pinned to identity, and push/pull distances are divided by the scale along the normal.
- **Undo and safety.**
  - Each model change is one `start_operation("MCP: <Tool>", true)`, aborted on any error.
  - Batches are atomic by default.
  - The status dialog and Extensions menu have **Read-Only Mode** and **Allow Ruby Eval** switches.
  - File tools never overwrite or discard unless told to explicitly. Exporter and importer summary dialogs are forced off, and modal dialogs are answered automatically during eval.
  - A connection whose first line isn't JSON is dropped, which blocks browser attacks.
- **"No invented API", enforced in four layers.**
  - `02__.../..SketchUpApiIndex__.json` is generated from SketchUp's MIT `ruby-api-stubs`: 156 classes, 2,087 methods, up to 2026.1.
  - `40__Tests__Validation/Na__SketchUpMcp__Tests__ValidateApiUsage__.py` fails on any unknown method, constant, `Length::` unit, `SnapTo_*` / `PAGE_USE_*` name or route. A deliberately planted invented method, class and constant were all caught.
  - `ruby_eval` code is linted against the index.
  - When the bridge starts, it probes every tool's `api` list in the live SketchUp and refuses any tool whose dependency is missing.
- **Agent files for every model.**
  - `AGENTS.md` for coding agents, and `CLAUDE.md`, which imports it.
  - `85__Docs__AgentReference/`:
    - `Na__SketchUpMcp__ServerInstructions__.md`, which the server sends to every client;
    - `Na__SketchUpMcp__AgentGuide__.md` (also the resource `sketchup://guide/agent`);
    - `Na__SketchUpMcp__ClientSetup__.md`;
    - `Skills/sketchup-modelling/SKILL.md`, an open-format Agent Skill for Claude Code and Codex.
  - `../.mcp.json` registers the server for Claude Code sessions opened in the Plugins folder.
- **Prior-art survey** of about 40 GitHub projects, Trimble's connector, and the Blender and Rhino bridges:
  - **Trimble.** The official "SketchUp connector for Claude" (28-Apr-2026) is remote and works on cloud models only. There is no official local MCP.
  - **mhyrr/sketchup-mcp** (472★) is the template nearly everyone copied, and it was rejected:
    - no licence file;
    - a blocking `client.gets` on the UI thread, which freezes SketchUp;
    - Python and Ruby out of step on connections;
    - booleans that call `Entities#subtract`, which doesn't exist;
    - no undo operations;
    - results thrown away.
  - **zinin/sketchup-mcp2** (MIT) is the best-engineered one. It still had eval on by default with no auth, wasn't coordinate-safe inside open groups, and used deprecated `send_action` for undo.
  - Ideas were adopted from zinin, Ringophilia and dcc-mcp (all MIT), plus the forks' timer-reentry and modal-guard fixes. **No third-party code was copied.** Notices are in `85__.../Na__SketchUpMcp__ThirdPartyNotices__.md`.
  - **Port 9876** is used by Blender MCP and most SketchUp bridges, and a fixed port collides when a second SketchUp window opens. So this bridge uses 8385 with a port search and per-process discovery.
- **Bugs found by live testing and fixed:**
  - Spheres were not manifold (`Math.sin(π)` is not exactly 0); the poles are now exact.
  - World bounds were inflated inside rotated or scaled parents; they now use the tight bounds of the real geometry.
  - Text reported a material.
  - A 2-point rectangle ignored `normal`.
  - The live checks also caught an invented `copy_with_parent_safety` call and an undocumented `material.texture = nil`. Both were removed before release.
- **Validation.**
  - `ValidateApiUsage` passed: 42 tools, 167 API dependencies, 41 Ruby files, 3,210 method calls, 207 constants and 42 routes.
  - SketchUp's bundled Ruby 3.2.2 compiled all 42 `.rb` files. `Na__SketchUpMcp__Tests__BridgeCore__.rb.test` passed 35 of 35: linear maths, units, params, and the socket server over real TCP (token, HTTP drop, idle client, api_probe).
  - `Na__SketchUpMcp__Tests__PythonServer__.py` passed 24 of 24 MCP protocol tests against a fake bridge. `--check` reached the live bridge.
  - The live self-test in SketchUp Pro 26.2.243 found all 167 dependencies.
  - **Live, zero-trace.** Each check was an atomic batch whose last step fails, so SketchUp rolled everything back:
    - primitive volumes matched their formulas exactly;
    - a box placed at a world point inside a 45°-rotated group, inside a 30°-rotated, moved, 2×1.5×1-scaled group, landed exactly there;
    - booleans, `move_to` and extrusion direction were correct;
    - `view_capture` returned an inline PNG and restored the camera;
    - Reload Plugin Data reloaded 40 files with 0 errors.
  - The Untitled template window was checked afterwards: its geometry, materials, tags and scenes were unchanged, and its camera and active scene were restored.
- **Known limits.**
  - Push/pull *inside an open, non-uniformly scaled group* follows the scale-along-normal rule but has not been measured live (see the checklist).
  - The API index stops at SketchUp 2026.1. For 2026.2 additions, confirm with `ruby_api_lookup {live: true}`.
  - Windows only (tested); the code has no Mac-specific paths, but Mac is untested.
  - `sketchup_send_action` is kept for picking native tools. SketchUp 2026.2 deprecates `send_action`.
  - Models opened before this plugin was installed have no bridge until SketchUp restarts.

### Validation Checklist
- [ ] Restart SketchUp. **Extensions > Na SketchUp MCP** shows **Bridge Running** ticked. The Status Dialog shows the port, and the API self-test reports 0 unavailable.
- [ ] Claude Code: approve `.mcp.json` when asked, or run the `claude mcp add` line from the Status Dialog. `claude mcp list` shows `sketchup` connected. Ask "What's in my SketchUp model?"; it calls `sketchup_status` and `outliner_tree`, then shows a capture.
- [ ] Open a second model. `sketchup_status` lists two instances, and `select_pid` switches between them.
- [ ] In a scratch model, make a group that is moved and rotated, nested three deep. Ask the agent for a 500 mm box at a world point you chose, inside the innermost group. Check it with the Tape Measure.
- [ ] **Unmeasured case.** Double-click into a non-uniformly scaled group (e.g. scale 2 in X only). Ask the agent to push/pull a face inside by 500 mm along X. The Tape Measure should read exactly 500.
- [ ] Each agent change is one Ctrl+Z step named `MCP: ...`. A failed batch leaves nothing behind.
- [ ] With **Read-Only Mode** on, a create call is refused as `read_only` and `view_capture` still works. With **Allow Ruby Eval** off, `ruby_eval` is refused.
- [ ] Codex (GPT-6 Astra): `codex mcp add ...` plus the timeouts from `Na__SketchUpMcp__ClientSetup__.md`. Ask it for `sketchup_status`.
- [ ] Quit SketchUp. Its `Na__SketchUpMcp__Connection__<pid>.json` disappears from `91__UserConfig__LocalOnly/Connections`.
- [ ] `git status` does not list `91__UserConfig__LocalOnly` or `__pycache__`.

## -----------------------------------------------------------------------------
