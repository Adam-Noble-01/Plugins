# Na__PointCloudViewer - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================

## Point Cloud Viewer - v0.14.8 - 13-Nov-2026 - Turned Clip Boxes

Status: IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027.

### Summary
Adam agreed turned clip boxes for the ortho planes ("Yes support turned clip boxes"); 0.14.7 built them for one capture
only. Asked whether to keep one in the viewer for his own viewing: "Yes, build it". A clip box can now turn to follow a
wall that is not square to the model (Kann's boundary walls run 3.76 degrees off), and is saved, drawn, rendered, edited,
kept in clip scenes and point cloud scenes, exported and read by the MCP like a level box. The engine is unchanged (ABI 9):
the cloud and the camera are folded into the box's frame, as the MCP's turned slices do. ARCHITECTURE section 37.

### Built
- **`50__System__ClipBox/Na__PointCloudViewer__ClipBox__Turned__.rb` (new):**
  - the box keeps `turned` (`origin`, `x_axis`, `y_axis`, and its own `min`/`max`, model inches); `min`/`max` beside it
    stay the LEVEL box round it, so extents, Zoom to Cloud, the filter preview's region and scene image framing work
    unchanged, and an older viewer clips to that level box instead of failing;
  - `Na__Clip__Space` gives any box in its own axes, `Na__Clip__CornersModel`, `Na__Clip__MakeTurned` (a frame along the
    model axes, or a quarter turn, gives a level box), `Na__Clip__TurnedAbout`, `Na__Clip__RenderParts` (the fold);
  - `Na__Clip__Turn` (an angle about the vertical through the box's centre, sizes kept; 0 levels it), `Na__Clip__Level`,
    `Na__Clip__TurnAlong` and its tool `Na__ClipTurnTool` (Turn to Two Points: two clicks along a wall face in plan; the
    box turns square to the line, centres on it, runs its length, keeps its depth, height and level, then Edit Clip Box
    starts). Each is ONE undo step ("Point Cloud: Turn Clip Box", "Level Clip Box", "Turn Clip Box to Two Points").
- **State:** the typed limits, the edit tool's live moves, the record, clip scenes, Copy to Other Clouds and the new
  `Na__Clip__SetClipOn` all work in the box's own axes. A stored turned box that cannot be read is dropped whole (never a
  level box in the wrong place).
- **Edit tool:** the cage, the handles, the pick and the drag work in the box's own axes, so a turned box's sides move along
  its own sides.
- **Renderer** (`ImageRenderer`, the seam's `composite`, scene image export): a turned box that clips folds that cloud and
  the camera into its frame, per cloud.
- **Crop and Cut:** its view waits while a turned box clips (its boxes are level in the model), capture refuses a turned box
  and says to Level it, and the Clean tab's clip size reads along the box's own sides with "(turned)".
- **Point cloud scenes** keep and recall a turned box; the JSON config export gives its frame, plan angle and limits.
- **Clipping tab:** a Turn row on the Clip Box card (degrees from red), Turn to Two Points, Level, and hints that say how a
  turned box's limits read.
- **MCP seam:** `state` reports `clip.turned` (frame, plan angle, its own limits) and turned clip scenes; `clip_box` takes
  `frame` with `min`/`max` in it (Na SketchUp MCP 1.0.35's `point_cloud_clip frame`); `composite` draws a saved turned box;
  `NA_FEATURES` lists `turned_clip`. `Na__McpFrame.Na__Frame__Camera` is the one camera fold, shared.

### Tested (13-Nov-2026, offline)
- `50__System__ClipBox/tests/clip_turned_unit.rb.test` (new): 20 checks on the real State, Turned and EditTool files:
  corners and level bounds of a box turned 30 degrees; aligned and quarter-turned frames come out level; thin boxes refused;
  sizes and centre kept through a turn, and back to level; Turn and Level each one undo step with the frame saved; bad
  angles refused with nothing written; Turn to Two Points on Kann's east wall (length, centre, depth, height, angle
  -86.24 degrees) and the same box clicked either way; the record round trip (a stale level box remade, an unreadable turn
  dropped); the render key; clip scenes and Copy to Other Clouds keep the turn; typed limits and the drag along the box's
  own x; picking a turned box's Top and Right sides by ray, and a ray inside the level box round it that misses; the drag
  following the mouse along the box's x; the fold (points inside test inside, outside test outside, every point keeps its
  place in the camera); nothing folded with clipping off or a level box.
- Three planted faults in a scratch copy (camera not folded, a face centre read from the level box, the turn left out of
  the record) each failed the suite.
- The seam suites unchanged: 87, 8, 18, 10 and 15 checks. 52 of 52 Ruby files compile (Ruby 3.2.2; SketchUp 2027's 3.4 DLL
  does not boot embedded); house lint clean on every folder touched; `node --check` on the clip tab's script.

### What offline cannot prove
- The picture with a turned box in SketchUp (the fold is proven numerically, not on screen), the cage and handles of a turned
  box, Turn to Two Points' clicks, and the Clipping tab's new row.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Noble 3D Tools' and Na SketchUp MCP's Reload Plugin Data. The engine is unchanged, so the
   clouds stay loaded. Close and reopen the viewer dialog for the new Turn row.
2. Clipping tab, Clip Box card: type 3.76 in Turned from the red axis and press Enter: the clouds clip to a turned box; one
   Ctrl+Z puts it back.
3. Turn to Two Points, then click the two ends of a boundary wall's face in plan: the box turns along the wall and Edit Clip
   Box starts; drag the Front and Back handles to the wall's thickness.
4. Save a clip scene, press Level, then click the scene: the turned box comes back.
5. Clean tab: Crop and Cut says the box is turned and won't capture it until it is levelled.

## Point Cloud Viewer - v0.14.7 - 13-Nov-2026 - Ortho Planes: Turned Clips and Looks for One Render, and Point Spacing

### Summary
For Na SketchUp MCP 1.0.34's `point_cloud_ortho_plane` and Noble 3D Tools' Point Cloud Ortho Plane button (0.9.48): a
scaled, square-on picture of the cloud placed in the model as a plane to draw over, Adam's route for low-quality clouds
(Kann 64562, a cloud derived from Google Earth). Kann's boundary walls run 3.76 degrees off the axes, so each wall took
four level clip boxes, four undo steps and a composite by hand. Adam: "Yes support turned clip boxes". The engine is
unchanged (ABI 9): a turned box folds the frame into the cloud's transform and the camera, as 0.14.6 does for slices.
ARCHITECTURE section 36.

### Built (`95__System__McpOperations/Na__PointCloudViewer__McpOperations__Main__.rb`)
- `composite` takes, for that render only (nothing written to any cloud's record, no look changed):
  - `clouds`: draw only these of the clouds on show;
  - `clip_frame` with `clip_min` and `clip_max`: a TURNED clip box in place of each cloud's own. The cloud's transform
    (`Na__McpFrame.Na__Frame__Fold`) and the camera (`na_camera_in_frame`) are both carried into the frame, so the
    engine's level box is level in the frame and the picture is unchanged. The Crop and Cut view is off for it (its
    boxes are level in the model), and the reply says so;
  - `look`: `point_size_px`, `opacity_percent`, `colour_mode` (rgb, black, primary), inside the viewer's own limits;
  - `dot_px`: the dot in OUTPUT pixels (1 to 64), not scaled by the viewport, so a plane's dots are sized from the
    points' spacing and its resolution.
  - The reply adds `dot_px` and `turned_clip`.
- A new read, `spacing` (framed too): an even grid of cells over the box's x and y, the median count of the cells
  holding points, `spacing` = cell / sqrt(median), and `spacing_sparse` from the sparser quarter of the cells (the 25th
  percentile). A plane sizes its dots from `spacing_sparse`, so they meet in the thin areas as well as under trees; the
  median left speckle on Kann. Refused above 4 M cells.
- `NA_FEATURES` lists 'ortho', so the MCP and the button can tell a viewer that has it.

### Tested (13-Nov-2026)
- `tests/mcp_operations_unit.rb.test`: 87 checks (6 new): the feature and the read listed; a 50 mm grid of points on a
  wall turned 30 degrees reads 50 mm seen along the frame; an empty box gives no spacing; the camera seen from the frame
  projects every point where the model camera does; the turned box arrives in the frame (nil without one); look and
  dot_px accepted inside the limits, refused outside.
- Live in a copy of Kann 64562 (its own window, closed afterwards), through the MCP tool:
  - the upper garden plan at 10 mm a pixel with the hand-made plane's dot size: pixel-identical to the hand-made picture
    (correlation 1.0, mean difference 0.0);
  - the east and west boundary walls, each one render with a turned clip, matching the four-segment composites;
  - the clouds' own clip boxes and looks as before after every capture.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Noble 3D Tools' and Na SketchUp MCP's Reload Plugin Data. The engine is unchanged, so
   the clouds stay loaded.
2. Ortho tab > Point Cloud Ortho Plane > Make Plane on a parallel view of a cloud: a white plane appears, and the cloud's
   own clip box and look are as they were.

## Point Cloud Viewer - v0.14.6 - 09-Nov-2026 - Slices at Any Angle for the MCP (frame)

### Summary
Adam asked for angled slices once the tools were triple-checked: boxes, views and sections along a wall that is not square
to the model, or along a roof's slope. The engine already tests and returns points in whatever coordinates its local ->
model transform gives, so the frame is folded into that transform and the engine works in the frame: no engine change
(ABI 9) and no reload of loaded clouds. ARCHITECTURE section 35.

### Built
- `Na__PointCloudViewer__McpOperations__Frame__.rb` (Na__McpFrame, written in 0.14.5):
  - makes a frame from an origin and an angle, or x_axis with an optional y_axis;
  - folds it into a transform;
  - converts points both ways, and a whole points file back to model mm.
- The seam (`Na__PointCloudViewer__McpRead`):
  - takes `frame` for count, histogram, image, points, density, heightmap and profile, and refuses it elsewhere;
  - wraps the measured slot (`Na__FramedSlot`, `Na__FramedCloud`) so every engine call gets the folded transform;
  - moves overlay edges into the frame and echoes the frame in the reply.
  - With a frame, min, max, the view, axis, a path and every position in and out are in the frame. A points file keeps
    model mm in `p` and adds the frame's in `f`.
  - `NA_FEATURES` lists 'frame', so the MCP can tell a viewer that has it.

### Tested (09-Nov-2026)
- `tests/mcp_operations_unit.rb.test`: 81 checks (9 new). The stand-in engine now applies the transform it is given, as
  BoxFilter.hpp does. The new checks cover a wall at 37 degrees (count against brute force, its two faces 110 mm apart,
  a front elevation, the renderer, inline points and a .npz with p and f, a heightmap reading the near face plumb), a
  roof pitched 30 degrees (a heightmap and a profile in the roof frame read flat), a model edge drawn in the frame, and
  refusals.
- `tests/mcp_frame_unit.rb.test`: 8 checks.
- The real engine DLL against numpy, a wall at 37 degrees on a cloud placed like a real scan: counts and grids equal,
  points to 1e-12 mm.
- Live in 22360, read-only through the seam:
  - The plumb wall at x 17,325, sliced in a frame turned 90 degrees, reads its face at -0.4 mm (the plain histogram: x 17,325.4), with the same 14,089 points in the peak bin and the same 41,147 in the box.
  - A 100 mm section cut at 37 degrees through the house: the density grid kept 115,014 points, all on the image, and the renderer drew all 115,014. The two pictures agree on 99.9% of pixels (0.999 correlation; flipped 0.38, mirrored 0.07).

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Na SketchUp MCP's Reload Plugin Data. The engine is unchanged, so the clouds stay loaded.

## Point Cloud Viewer - v0.14.5 - 09-Nov-2026 - The MCP Seam, Triple-Checked

### Summary
Adam asked for the point cloud tools to be triple-checked before angled slices.
- Four reviewers each read one layer cold: the engine's box queries, the seam, the maths, and the MCP handlers.
- Offline edge cases, then hostile calls through the real MCP server in the SK02 helper window (22360).
- Every finding was confirmed before it was fixed. The engine is unchanged (ABI 9). ARCHITECTURE section 34.

### Fixed
- **Faces and edges** (Main.rb):
  - Histograms and density images count points exactly on a box's faces. The engine sums a grid position in another
    order than its box test, so a low-face point could fall a hair outside the grid, and density frames on whole pixels
    put far-face points one pixel past the edge. Fix: grids start NA_EDGE_INCHES early, density reads one extra column
    and row (folded back), and heightmap cells take points a hair outside their edges.
  - Model edges on a picture's right or bottom border are drawn; grid lines no longer land a pixel early.
- **Numbers back exact**: pixel sizes, bins, mappings, the box echo and profile chart scales come back to 9 significant
  figures (`na_out_exact`); 0.1 mm rounding had put a 0.25 mm pixel at 0.2.
- **Clouds and edits**:
  - a name two clouds share is refused with their ids (it took the first);
  - an infinite box side is refused;
  - a clip scene whose write raises is a refusal, and `Na__Clip__Save` puts the clip box back in step with the model on any
    raise (ClipBox State);
  - a scene named "Full" can be picked by name.
- **Composite**: with `follow_scene` it applies the active scene's cloud look first (`Na__SceneFollow.Na__Follow__Apply`).
  Captures over NA_MAX_COMPOSITE_PIXELS (12 MP) are refused (the MCP keeps the capture, with a warning), and a translucent
  cloud over a transparent capture blends by the capture's own alpha.
- **Fit** (Fit.rb):
  - circles down to a tenth of the tolerance (the floor was twice it: a 25 mm baluster came back 40 mm across);
  - extents widened by what the percentiles trim, so lengths are full, where they were 2% short;
  - one direction rule: a line runs uphill and a normal points up, except within about 1 degree of level or plumb;
  - refinement until the inliers stop changing;
  - a circle settled from a second start, the least-squares circle of all the points, with `other_radius` when the two
    differ;
  - the box's residuals: each point's distance from its sides.
  - The seam adds hints and warnings for small circles and for two circles.
- **Check** (Check.rb):
  - at an edge or corner shared by faces, their summed normals decide the side, so a point just outside a 60 degree ridge
    reads outside;
  - a big sloping face's cells are found column by column, so its cost follows those cells, not its whole box;
  - an empty box round the model is refused (it read as rms 0).
- **Heightmaps and profiles** (Height.rb, Main.rb):
  - values ranked by nearness to the viewer in every view, so max, p98 and rgb_top are the surface seen, from the side too;
  - a profile counts each piece's box first and reads one share of every piece;
  - no zero-length last station;
  - level slopes say "level", and too fine a grid says cells.
- **Groundwork**: `Na__PointCloudViewer__McpOperations__Frame__.rb` (Na__McpFrame), the frame maths for angled slices
  (0.14.6); its suite `tests/mcp_frame_unit.rb.test` passes 8.

### Tested (09-Nov-2026)
- Suites: seam 72 (10 new), heightmaps 15, fit 18 (4 new), check 10 (2 new), frames 8; the harness main 197, boxes 84,
  hotkeys 134, multi 96.
- The real engine DLL, 600 points exactly on box faces: histograms now count all 600 (they counted 444), density images
  600 (326).
- Live in 22360 through MCP 1.0.17:
  - The stair check is unchanged (rms 16.1, mean +7.8).
  - A sampled diagonal profile reads 44.3% of every piece.
  - The bullnose settles on radius 173.4 mm at a 10 mm tolerance, as an independent least-squares fit does; 165.6 at 5 mm.
  - At 3 mm it warns of two circles (145.8 and 164.1): this bullnose is not one arc.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Na SketchUp MCP's Reload Plugin Data. The engine is unchanged, so the clouds stay loaded.

## Point Cloud Viewer - v0.14.4 - 09-Nov-2026 - Heightmaps and Profiles for the MCP (point_cloud_heightmap)

### Summary
Adam chose heightmaps next: heights per cell of a grid, and heights along a path, for ground, roofs, falls, kerbs
and rails. Pure Ruby in the seam on an even sample (`napc_box_points`), so the engine is unchanged (ABI 9) and no
window reloads its clouds. Files match the skill's terrain kit (`pc_terrain.py`'s rasters.npz). ARCHITECTURE section 33.

### Built
- `95__System__McpOperations/Na__PointCloudViewer__McpOperations__Height__.rb` (`Na__McpHeight`, no SketchUp API):
  - each point gets a cell (or a station along a path) and its value along the view's axis; a counting sort puts each
    cell's values together and each cell is sorted once;
  - percentiles by pc_terrain.py's rule: the value at rank floor(q x (n - 1)) (min is p0, max p100); rgb_top and rgb_low
    are the mean colours of a cell's highest tenth and lowest quarter, as the kit makes them;
  - the best plane through the cells (its slope and which way it falls); a picture: blue (low) to red (high), shaded
    from the top left, contours, white where empty;
  - profiles: the path cut into pieces about the corridor's width across, so a diagonal path reads its own strip, one
    box per piece; stations by chainage; the least-squares slope and the steepest metre; a picture with chainage across,
    height up (exaggerated to show falls), the points grey and each statistic a line.
- The seam's `heightmap` and `profile`: the values inline for small grids (2,500 cells) and profiles (1,000 stations),
  a `.npz` (rasters.npz layout, model mm, NaN where empty) or `.asc` (ESRI grid, from the top) for grids, `.csv` or
  `.npz` for profiles; the model's edges in magenta over a heightmap.

### Tested (09-Nov-2026)
- New `tests/mcp_height_unit.rb.test`: 15 checks. Statistics against sorting 20,000 points by hand in 300 cells; colour
  bands; the tilt of a holed grid; the picture's colours and contours; pieces and stations against points placed at
  known chainages round a bent path; slopes; the profile picture.
- `mcp_operations_unit.rb.test`: 62 checks (9 new: a 2% fall with grass on it, the .npz and .asc files, a leaning wall
  from the front, magenta edges, profiles along x and on a diagonal, refusals).
- Live in the SK02 helper window (pid 22360), read-only: the terrain kit agrees to the last digit: the same box of the SK02 GeoSLAM cloud (x 2,000 to 6,000, y 6,000 to 12,000 mm, 46,531 points, all of them) through `pc_terrain.py rasters --res 50` and through the heightmap gave the same 80 x 120 grid, the same counts, z02, z10, z50, z90 and z98 equal to 0.0 mm, and the same rgb_top and rgb_low. 1,000,000 of 37.1 M points into 90 x 148 cells of 250 mm took 2.1 s; 5,000,000 into 224 x 368 cells of 100 mm, 10.7 s. A profile up the SK02 staircase (x 16,950, y 11,800 to 15,500, a 300 mm corridor, 20 mm stations): 185 stations from 181,054 points in 0.7 s, every tread a step, the soffit of the flight above as a grey diagonal.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Na SketchUp MCP's Reload Plugin Data. The engine is unchanged, so the clouds stay loaded.

## Point Cloud Viewer - v0.14.3 - 09-Nov-2026 - Model-to-Cloud Check for the MCP (point_cloud_check)

### Summary
Adam chose the model-to-cloud check next: how far the scan sits from a built group's faces, overall, per part,
where it is worst, and as a heatmap, so an agent can grade its own work against the survey. Pure Ruby in the
seam on an even sample (`napc_box_points`), so the engine is unchanged (ABI 9). ARCHITECTURE section 32.

### Built
- `95__System__McpOperations/Na__PointCloudViewer__McpOperations__Check__.rb` (`Na__McpCheck`, no SketchUp API):
  - triangles go into a grid of cells `reach` wide; a big slanted face only into the cells its plane passes through;
  - a point looks in its own cell and the 26 round it; each triangle is measured once per point;
  - closest point on a triangle after Ericson 5.1.5. The sign comes from the face's outward normal: positive means the
    scan lies outside the face, so the model is too small there.
- The seam's `check`: near points (within reach) are measured and the rest counted as away. Returns the summary
  (rms, mean, p50, p95, max, the share within tolerance), the same per part (the worst first), the worst spots
  (points beyond tolerance gathered into 150 mm cells), warnings (few points near, a whole-model offset, parts no
  point reached), and a heatmap on request: green within tolerance, red outside, blue inside, deeper towards reach,
  pale grey away, the model's edges dark over them.
- `na_draw_line` and `na_draw_segments` take a colour (red by default, as before).

### Tested (09-Nov-2026)
- New `tests/mcp_check_unit.rb.test`: 8 checks. Closest points agree with a second method on 3,000 random cases,
  and the grid's nearest triangle agrees with measuring every triangle on 1,500 points, big slanted faces included.
  Signs inside and outside a closed box, a corner, degenerate faces, too many cells refused, summaries, spots.
- `mcp_operations_unit.rb.test`: 53 checks (4 new: near and away, per part, an offset model, the heatmap).
- Live in the SK02 helper window (pid 22360): the SK02 staircase (`Staircase__MainStair__`, 1,420 faces, 14 parts) against the GeoSLAM cloud: 8,901 of 20,000 points within 50 mm, rms 16.1 mm, 53% within 10 mm, mean +7.8 mm (the scan outside the faces). The worst spots are the lower treads at +15 to +21 mm, the carpet the survey notes as reading 10 to 15 mm proud. The worst part is the landing base rail (rms 27), the closest the landing handrail (rms 10.2). 2.7 s.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Na SketchUp MCP's Reload Plugin Data. The engine is unchanged, so the clouds stay loaded.

## Point Cloud Viewer - v0.14.2 - 09-Nov-2026 - Shape Fitting for the MCP (point_cloud_fit)

### Summary
Adam chose shape fitting as the next tool for agents: a plane, a line, a circle, a cylinder or a post's box
from the points in a box, with numbers and residuals, instead of reading histograms by eye. Pure Ruby in the
seam, on an even sample the engine already hands over (`napc_box_points`), so the engine is unchanged (ABI 9)
and no window needs Reload All for it. ARCHITECTURE section 31.

### Built
- `95__System__McpOperations/Na__PointCloudViewer__McpOperations__Fit__.rb` (`Na__McpFit`, no SketchUp API):
  RANSAC on up to 2,000 of the points finds the dominant shape, then least squares on every inlier within
  tolerance refines it, four rounds. Seeded, so the same points give the same answer.
  - plane (any, or held horizontal or vertical): normal, point, offset (the level when horizontal),
    slope_deg, azimuth_deg, extent in the plane;
  - line: direction, start, end, length, slope_deg, azimuth_deg;
  - circle (seen along x, y or z) and cylinder (plus its extent along the axis): centre, radius, the arc the
    points cover. Geometric least squares (Gauss-Newton). max_radius holds in the search and the refinement;
  - box (seen along an axis): the smallest rectangle round the points after trim percent off each side,
    turned 0 to 90 degrees (1 degree, then 0.05): width, depth, rotation_deg, centre, from, to, corners.
- The seam's `fit` action: the sample, the fit, lengths in the call's units, inlier_share, and warnings when
  under 30% of the points fit, or when a circle covers under 60 degrees or sits near max_radius.

### What real data taught it (the SK02 GeoSLAM stair, 09-Nov-2026)
- A curve that runs into a straight piece at a tangent (a bullnose step and its riser) always holds more
  points on a bigger, flatter circle: with the riser in the box the fit was 398 mm over 45 degrees. The short-arc
  warning was added for that; boxed to the curve alone, the SK02 bullnose step, boxed to the curve (z 80 to 160): r 166.4 at (16,539.5, 12,274.2), rms 1.7 mm over 96 degrees; an independent scipy fit of the same points gave r 168.5 to 171.9 at about (16,540, 12,278).
- The skill's survey table gives the bullnose carpet face as r 159 at (16,535, 12,267). The 7 to 13 mm difference
  is worth a look before either is relied on.
- A box holding a second object (the newel and something beside it) measures both: one side read 102.7 mm (the
  survey's "about 102" for the 90 mm block), the other 116.7. Box one thing.

### Tested (09-Nov-2026)
- New `tests/mcp_fit_unit.rb.test`: 14 checks on shapes made from known numbers with seeded noise and
  outliers (a tilted plane through 40% outliers within 0.3 degrees; a tread level within 0.02 in beside its
  riser; a wall at 30 degrees; a rail at 42 degrees; a 145 mm bullnose within 1.5 mm; a pipe; a newel turned 20
  degrees within 0.5 degrees and 2 mm).
- `mcp_operations_unit.rb.test`: 49 checks (6 new for the seam's fit).
- Offline on the SK02 GeoSLAM cache (37.5 M points), through SketchUp's own Ruby: the fits above, and the
  tread 5 level at 1,197.1 where its z histogram peaks.
- Live in the SK02 helper window (pid 22360), at Adam's word, after the viewer's and the MCP's reloads (its two
  clouds reloaded from cache): the same answers through point_cloud_fit, 0.1 to 0.7 s each; the wall at x 17,325
  plumb to 0.03 degrees.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Na SketchUp MCP's Reload Plugin Data. A window still on 0.13 code also
   needs Reload All for its clouds (the 0.14.0 engine).

## Point Cloud Viewer - v0.14.1 - 09-Nov-2026 - Overlays for the MCP: Model Edges on Slices, Clouds on Captures

### Summary
Adam asked what more would help agents use the point clouds, and chose the first idea: let an agent see its
model and the scan in one picture. Two pieces, both in the MCP seam (Na SketchUp MCP 1.0.13). The engine
is unchanged (ABI 9). ARCHITECTURE section 30.

### Built
- `image` and `density` take `overlay_segments` (model edges as world segments, which the MCP collects) and
  draw them in red over the slice, projected the same way; `overlay_clip` keeps only the parts inside the
  box. The picture is then an RGB PNG.
- `composite`: the clouds on show drawn over a SketchUp capture, in place, with the live overlay's own
  camera maths (`na_camera_params`), layers, looks, clip boxes, Crop and Cut view and point budget. Dot
  sizes scale with the image against the viewport. The capture is read and written back with
  `Sketchup::ImageRep` (24-bit BGR or 32-bit BGRA, rows from the top), so PNG and JPG both work.
- Measured first: SketchUp's `write_image` keeps the camera's vertical field of view for any image shape.
  Three cubes at known points, captured at 1600 x 800 and 800 x 1000, perspective and parallel, landed
  within 1.2 px of the overlay's formula. Width and height must be whole numbers: given floats,
  write_image ignores them and writes the screen's physical size.

### Decisions (Adam may want them otherwise)
- The clouds are drawn over everything, as on screen: the model's faces do not hide them.
- Overlay edges leave out soft and hidden edges, as SketchUp's own view does.
- With the overlay off, or no cloud on show and loaded, a capture comes back without clouds and says so.

### Tested (09-Nov-2026)
- `mcp_operations_unit.rb.test`: 43 checks (8 new: segment clipping, line drawing, an overlay at its
  mapped pixel, clipped overlays, the blend for BGR and BGRA captures).
- Live in the MCP__Workshop__ window with `exterior_shell.las` and a 12 x 8 x 6 m box on its walls (Na
  SketchUp MCP devlog, 1.0.13).

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Na SketchUp MCP's Reload Plugin Data. The engine is the same, so the
   clouds stay loaded.

## Point Cloud Viewer - v0.14.0 - 09-Nov-2026 - Native Box Queries (ABI 9): Points and Density for the MCP

### Summary
v0.13.1 gave the Na SketchUp MCP four point cloud tools on the engine as it was, so an agent could count
points in a box and see a nearest-point image, but could not have the points themselves or a density
image, and paid one pass over the whole cloud for every histogram bin. Adam said to do the follow-up
"here", and agreed four choices: bump the engine's ABI to 9; histograms in one pass; points back in the
reply or in a .npz; density on a log scale. ARCHITECTURE section 29.

### Built
- Two native calls (Api.h, Api.cpp), on the render pool under the render mutex, using the box filter's
  own Verdict():
  - `napc_box_points`: the first `cap` stored points the boxes keep, times a scale (1 = model inches,
    25.4 = mm), with colours. Pass 1 counts each worker's slice; pass 2 copies exactly the first N in
    stored order and stops early. The store is shuffled, so they are an even sample. No index list is held.
  - `napc_box_grid`: points per cell of a grid on a plane (column axis u, row axis v, cell sizes su and
    sv, `Na__GridIndex`), from the stored coordinates in double precision. A small grid counts into one
    array per worker; a large one into shared relaxed atomics, so memory never grows with threads.
- The Ruby bridge expects ABI 9 and wraps both (`Na__Native__BoxPoints`, `Na__Native__BoxGrid`).
- The MCP seam: `points` (up to 1,500 in the reply, up to 5,000,000 in a .npz numpy and the skill's
  pc_kit.py read), `density` (the image frame and mapping, darker = more, log or linear, clipped at the
  99.5th percentile), and `histogram` in one pass (a grid one cell wide), up to 10,000 bins. The last bin
  keeps the box's far face, so the bins add up to what `count` gives.

### Decisions (Adam may want them otherwise)
- ABI 9, not 8 with optional calls: a window still running v0.13 code refuses the new DLL once and keeps
  the engine and clouds it has (checked live in both SK02 windows). Each window takes the new engine at
  its next Reload Plugin, which then needs Reload All for its clouds. A window that has not loaded an
  engine yet cannot load one until it is reloaded.
- Points in a .npz are float64 model millimetres (`p`) and 0xAARRGGBB colours (`c`).
- No fallback for an ABI 8 engine: the new code never loads one.

### Tested (09-Nov-2026)
- New `95__System__McpOperations/tests/native_box_queries_test.py` (ctypes and numpy, any DLL path):
  39 checks. A 300,000-point cloud placed at 27 degrees with a Keep and a Cut box. Points: the first N
  kept, in stored order, to 1e-9, with colours, for five caps. Grids: every cell equal to numpy for a plan,
  a 2,000 x 2,000 view (the shared path), axes at 45 degrees and a histogram. Refusals.
- `mcp_operations_unit.rb.test`: 35 checks (12 new).
- The harness on the staged and then the live tree: main 197, boxes 84, multi 96, hotkeys 134.
- Timed on 42.7 M points: count 42 ms; a histogram 43-44 ms with 100, 1,000 or 10,000 bins; density
  500 x 350 50 ms, 2,000 x 1,400 54 ms; points 43 ms (1,500) to 95 ms (all 297,000 in the box).
- Live in the MCP__Workshop__ window with `exterior_shell.las` (imported and removed after): Na
  SketchUp MCP devlog, 1.0.12.

### Checklist for Adam (in SketchUp)
1. In each window, Reload Plugin (Settings), then Reload All for its clouds (the engine is new), then
   Extensions > Na SketchUp MCP > Reload Plugin Data.
2. Until then a window keeps working on the old engine; its status line may say once that the build on
   disk speaks ABI 9.

## Point Cloud Viewer - v0.13.1 - 09-Nov-2026 - An Agent Seam for the Na SketchUp MCP

### Summary
The SK02 stair balustrade was modelled from the GeoSLAM cloud with a kit in the modelling skill that
drove this viewer through `ruby_eval` and read its point cache with numpy. Adam asked for that kit as
proper MCP tools (`point_cloud_state`, `point_cloud_clip`, `point_cloud_view`, `point_cloud_slice`,
Na SketchUp MCP 1.0.9), with the rules here, in a seam the MCP calls, as Element Assembly Studio and
Component Editor Tools have. Nothing the dialog does changed. ARCHITECTURE section 28.

### Built
- `95__System__McpOperations/Na__PointCloudViewer__McpOperations__Main__.rb`:
  `Na__McpOperations.Na__PointCloudViewer__McpRead(action, params)` (state, count, histogram, image)
  and `...McpEdit` (clip_box, clip_on, clip_off, clip_scene, view). Refusals raise
  `Na__PointCloudViewer::Na__McpOperationsError` (code, message, hint).
- Clip changes go through the viewer's own calls, ONE undo step each, named "Point Cloud: ...". Show
  and look go through the same calls as the dialog's switches and sliders: never written to the model.
- Counting uses `napc_box_count`. Images use `napc_render_png` with a parallel camera along a model
  axis and the box as the clip box; Ruby then writes a greyscale PNG (white paper, black points, a grid
  every fifth line darker) with zlib.
- Two pieces became shared functions, so the seam uses the same rule as the tools:
  - `Na__Clip__SetEnabledOn(session, slots, enabled)` (State): clipping on or off for several clouds
    in one undo step. Clip On or Off now calls it.
  - `Na__Clip__GrowToGrid(bounds, margin)` (DrawTool): grown by the margin and rounded outwards onto
    the draw grid. Clip Box Around Selection now calls it.
- AppCore Main requires the seam; Reload Plugin finds it on its own.

### Decisions (Adam may want them otherwise)
- The DLL is unchanged (ABI 8), as Adam chose. The points themselves and density images need two new
  native calls, proposed for ABI 9: `napc_box_points` (the first N points inside the boxes in stored
  order, which is shuffled, so an even sample, in model inches with colours) and `napc_box_grid`
  (point counts per pixel of a parallel view). With them the skill's numpy kit would not be needed.
- A histogram is one count per bin, and each count is one pass over the whole cloud: 28 ms per pass on
  SK02's 42.7 M-point RealityCapture cloud, so at most 200 bins.
- An image shows the nearest point in each pixel, in one dark colour on white: shape, not density.

### Tested (09-Nov-2026)
- New `95__System__McpOperations/tests/mcp_operations_unit.rb.test`: 23 checks with SketchUp's Ruby,
  run through the MCP plugin's `RunRubyChecks` (peaks, percentiles, the grid, the PNG, refusals, and
  each view's frame against a stand-in of the engine's parallel projection).
- The harness in `D:/_ClaudeScratch/pcv_runners` on the changed tree: hotkeys 134, boxes 84, multi 96,
  main 197, all pass.
- Live in the MCP__Workshop__ window with the fixture `exterior_shell.las` (imported for the trial and
  removed after): every action through the MCP (its devlog, 1.0.9), then Clip Box Around Selection
  round a boiler (the same box as the MCP's `around`) and Clip On or Off twice.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings), then Extensions > Na SketchUp MCP > Reload Plugin Data.
2. Select a wall, then Extensions > Na__PointCloudViewer > Clip Box Around Selection: as before, 100 mm
   past it. Ctrl+Z puts the old box back.
3. Press the Clip On or Off key twice: clipping off, then on.

## Point Cloud Viewer - v0.13.0 - 26-Oct-2026 - Keyboard Shortcuts and Draw Clip Box

### Summary
Adam asked for two things. A hotkey mapper for the main things, above all one key that switches every
point cloud on and off while he models ("it's kind of a pain in the ass" to give plugins keys); and a
new form of the clipping tool that puts a clip box in the 3D space quickly, the way Noble Drawing Tools
draws a volume (drag a rectangle, then the height, on the same 5 mm voxel snapping), on a key of its
own, to move from one area to the next once the model is roughed out. ARCHITECTURE section 27.

### How keys work, and what was found
- SketchUp gives keys only to menu items, by menu path, in `SharedPreferences.json`; Ruby can read
  them (`Sketchup.get_shortcuts`) but never set them. Adam's plugins all put commands in a submenu for
  this (Noble 3D Tools' JSON command registry, Edge Util, Dev Tools, NaKeys).
- The pain: a menu built once at start up shows a command added later only after a restart. Noble Drawing
  Tools already works round it with a registry that a reload tops up; the viewer does the same.
- Adam's old Undet keys are still in SketchUp's settings (Ctrl+Alt+Shift+P was Hide/Show, Ctrl+Alt+
  Shift+B New Clipping Box By Selection, Ctrl+Shift+1 RGB colouring, Ctrl+Shift+. and , the density),
  which is why Clip Box Around Selection, the colour modes and the budget steps are commands too.

### Built
- **Extensions > Na__PointCloudViewer**: 14 commands (Open Point Cloud Viewer; Show or Hide Point
  Clouds, Show or Hide the Active Cloud, Next Point Cloud, Zoom to Point Clouds; Draw Clip Box, Clip Box
  Around Selection, Edit Clip Box, Clip On or Off; Colour Mode RGB, Monochrome, Primary Colour; Fewer
  Points, More Points), listed in the defaults JSON (`hotkeys`), each working with the window closed and
  saying what it did on the status line. Checkmarks show the switches that are on. Added once per
  session and topped up by Reload Plugin, never twice.
- **Settings > Keyboard Shortcuts**: each command with its key, a key it shares with another command,
  and Open SketchUp Shortcuts (SketchUp's own page); read again when the window gets the focus back.
- **Draw Clip Box** (`50__System__ClipBox/...DrawTool__.rb`): drag the base, pull the height, click; the
  5 mm grid in the model's axes; Ctrl and Ctrl+Shift; Tab, arrows and the right click menu for the plane
  and the grid; typed sizes as in Noble Drawing Tools, typing over the box just drawn; Backspace, Esc; the
  preview drawn over the cloud picture in screen space. The box goes to every cloud on show in ONE
  undoable step, and the tool stays on for the next area. A Draw a Clip Box card on the Clipping tab
  starts it, shows its key and holds the grid and the selection margin.
- **Clip Box Around Selection**: the box round what is selected (in an open group too), 100 mm past
  it, rounded outwards onto the grid.
- Built on top of v0.12.0 (Follow SketchUp's Scene Tabs, another session, deployed but not committed):
  merged three ways; ActionRouter, Main, ModelRegistry, the defaults JSON and the layout carry both.

### Decisions (Adam may want them otherwise)
- Draw Clip Box, Around Selection, Clip On or Off and the colour commands act on **every cloud on show**
  (the active one when none is), because they look at an area; the tabs' own switches still act on the
  active cloud. Hide a cloud to leave it out. Edit Clip Box still edits the active cloud's box.
- The grid is the MODEL's axes, not rotated drawing axes: a clip box is level in the model.
- Clip On or Off with some clouds clipping and some not turns clipping off first.
- No toolbar buttons (each would need an icon); no keys given automatically (no API).

### Tested (26-Oct-2026, on the merged tree)
- New `pcv_scenario_hotkeys.rb`: 134 checks (ARCHITECTURE 27.6).
- Main 197, boxes 84, scenes 96, clean 59, multi 96, legacy 52, follow 60: all pass.
- The new card and list in a browser with real states at 600 and 480 px.
- Not yet tried in SketchUp itself.

### Checklist for Adam (in SketchUp)
1. Reload Plugin (Settings). Extensions now has **Na__PointCloudViewer** with the 14 commands.
2. Settings > Keyboard Shortcuts > Open SketchUp Shortcuts. Type Na__PointCloudViewer in Filter, choose
   Show or Hide Point Clouds, click in Add Shortcut, press the keys (Ctrl+Alt+Shift+P was Undet's
   Hide/Show and is free now), press +, then OK. The same for Draw Clip Box (Undet's Ctrl+Alt+Shift+B,
   say). Back in the viewer, the list shows the keys.
3. Press the first key: every point cloud goes off, and on again.
4. Press the Draw Clip Box key over a modelled floor: drag a rectangle, release, pull up, click. The
   clouds on show are clipped to the box. Type `3000,3000,3000` and Enter: the box changes. Ctrl+Z puts
   it back. Esc leaves the tool.
5. Select a wall, then Extensions > Na__PointCloudViewer > Clip Box Around Selection.
6. Look for SketchUp's inference marker (the green or red dot) while drawing over the cloud; if it is
   missing, tell me (27.6).

## Point Cloud Viewer - v0.12.0 - 26-Oct-2026 - Follow SketchUp's Scene Tabs

### Summary
Adam asked for SketchUp's own scene tabs to do what Go To Scene does, so a configured scene is one
press away instead of a trip into the Scenes tab; and, before anything was added, to be sure it
could not hang SketchUp or damage a model (a scene with no match, renamed scenes, file corruption).
Researched online, measured in a scratch SketchUp 2026, then built: pressing a scene tab now gives
every cloud that scene's settings (shown or hidden, size, opacity, colour, clip box, the budget).
A SketchUp scene with no point cloud settings changes nothing. ARCHITECTURE 23.7 holds the measured
facts, the rules and the risk assessment.

### Research (26-Oct-2026)
- The hook is `Sketchup::Pages.add_frame_change_observer`: documented since SketchUp 6 and used by
  Trimble's own Dynamic Components. `PagesObserver` only says "the pages changed" (twice per scene,
  and for renames and moves too); `ViewObserver` fires on every orbit; there is no scene activated
  event (api-issue-tracker #237, open).
- Known problems, each designed out: `from_page` is nil on Windows (#862); model changes inside an
  observer can crash or corrupt (SketchUp's guidance: defer them); an empty transparent operation can
  corrupt the undo stack; a one shot timer could fire again while a modal window was open (fixed in
  2023.1); a 2025/2026 forum crash came from observers whose edits fired more edits.

### Measured in a scratch SketchUp 2026 (never Adam's)
- A real mouse click on a tab, Ruby `selected_page=` and Next Scene send the same frames, 0.0 to
  1.0; 0.0 comes inside the click, before SketchUp names the new scene; 1.0 sometimes twice.
  Transitions off: one 1.0 frame. The same tab again, and a scene without a camera: frames too.
- Opening a model sends nothing. Selecting a scene is not an undo step and does not mark the model
  modified.
- An observer that selects the scene it is told about loops for ever. A model write from a timer
  does not stop a transition or a playing slideshow. Overlays are not in `View#write_image`.

### Built
- **`90__System__Scenes/...Scenes__Follow__.rb`** (`Na__SceneFollow`): the observer only notes the
  scene and books a timer (0.1 s); the timer applies the scene through Go To Scene's own code when it
  is still the scene shown, has settings and differs from what the viewer shows. One more look when
  the transition ends catches a scene SketchUp names late and otherwise writes nothing. A newer
  press replaces a booked look. Never selects a scene, never writes a Page, never a transparent or
  empty operation; a changed clip box is one named undoable step, as with Go To Scene. Skipped while
  an import or export runs (the status line says so). Installed with the first model's overlay,
  after extensions load, once per SketchUp session; Reload Plugin keeps it.
- **Recall split:** `Na__Scenes__Recall` selects the scene, then `Na__Scenes__Apply`; following a
  tab calls Apply alone, so the two can never differ. Go To Scene tells the follow module first, so
  its own transition is not applied twice.
- **Scenes tab:** a **Follow Tabs** switch in the Point Cloud Scenes card (on by default, kept per
  computer in the user config, never in the model); the hint and How Scenes Are Kept Safe say what
  it does.

### Tested (26-Oct-2026, in a staging copy)
- Harness: new follow suite 60 checks (frames as measured, Go To Scene, the same tab, no settings,
  no camera, transitions off, quick presses, a scene no longer shown, a scene named late, the
  switch, a running job, Undo, Reload Plugin, bad frames, a timer firing twice, opening a model;
  tripwires on Page writes, scene selection and transparent operations). Main 197, scenes 96,
  clean 59, multi 96, legacy 52, boxes 84 unchanged.
- Live, in a scratch SketchUp 2026 running the staged code with a real cloud: real clicks on four
  tabs (each bound scene applied once, about 0.1 s after the press, in 3 to 5 ms; the unbound one
  and a repeat press changed nothing), Go To Scene (applied once), two quick presses (only the
  second applied), the switch from the dialog, Undo (the previous clip box back), and a slideshow
  (every bound scene applied as it came, and the slideshow carried on). Technical log clean.

### Checklist for Adam (in SketchUp)
1. Settings, Reload Plugin (no engine change).
2. Press a SketchUp scene tab that has point cloud settings: the clouds take them as the camera
   starts to move.
3. Press a scene with no settings: the clouds stay as they are.
4. Scenes tab, Follow Tabs off: tabs no longer change the clouds; Go To Scene still does.
5. As with Go To Scene, a scene whose clip box differs adds one undo step and marks the model as
   changed.

## Point Cloud Viewer - v0.11.1 - 25-Oct-2026 - Primary Colour: Red, Then Blue, Then Opposites

### Summary
Adam asked for a colour mode beside RGB and Monochrome that gives each point cloud one solid colour, to
help line clouds up: the first cloud always red, the second always blue, then on through colours as
opposite as practical, with point size and opacity still working. v0.10.0's third mode (Cloud Colour)
is now **Primary Colour**, and clouds are given their colours in that order. ARCHITECTURE 25.12.

### Built
- **The order:** red, blue, green, yellow, cyan, pink, magenta, brown, orange, violet. A model's first
  cloud is red and its second blue. After those, each next colour is the one that looks most different
  (CIEDE2000) from every colour already taken, one per colour name so each can be said aloud, readable on
  SketchUp's light backgrounds and never grey (a LAS without colour is drawn grey in RGB).
- **Primary Colour** (`colourMode` `primary`): every point of a cloud in its solid colour, at its own dot
  size and opacity; set per cloud like the other modes and saved with scenes. Chosen, the option is filled
  with the active cloud's colour (red for A, blue for B); otherwise a dot shows the colour it will use.
- **Colour names** on the palette swatches, each cloud's swatch and the option's tooltip
  ("exterior_shell in blue"). A cloud's colour can still be changed on its row.
- **Models from the first v0.10.0 build:** a cloud it coloured (orange, then its blue) reads as red, then
  blue; its record takes the new colour with its next change. A look or scene saved with that build's
  name for the mode (`cloud`) reads as Primary Colour.
- No engine change (the layered render's per-layer solid colour).

### Tested (25-Oct-2026, on the working tree with v0.11.0's Crop and Cut)
- Multi-cloud 96 checks (was 87): the order and names, a third cloud green, both clouds in Primary Colour
  drawn solid red and solid blue at 40 % with no other colour left, the old mode name in a look and a
  saved scene, the first build's colours read as red and blue, a colour change named Magenta.
- Main 197, scenes 96, clean 59, v0.9.1 upgrade 52, native layers 28 (on the ABI 8 engine). The option in
  a browser with a real state: Primary Colour filled blue for the exterior.
- Not yet tried in SketchUp itself.

### Checklist for Adam (in SketchUp)
1. Reload Plugin. With two clouds in the model, click the first cloud's chip, then Primary Colour on the
   Display card: it turns solid red. Click the second cloud's chip, then Primary Colour: solid blue.
2. Point size and opacity still change each one on its own.
3. Back to RGB or Monochrome per cloud the same way.

## Point Cloud Viewer - v0.11.0 - 25-Oct-2026 - Crop and Cut: Remove Points With Boxes

### Summary
Adam asked for a new section at the bottom of the Clean tab: capture the current clip box and use it
to remove every point outside it, and inner boxes to remove a tree or some noise; to physically clean
points out of the cloud, fast, stable and intuitive, without ever destroying the original. He also
asked whether the existing filters work on the cached cloud. ARCHITECTURE section 26 is the full
description.

### What the existing tools do to the original (checked 25-Oct-2026)
Nothing edits a file or the loaded cloud. The filter preview is a picture of the clip box. Clean &
Export reads the original LAS's own records, writes a NEW LAS (Save As, nothing overwritten, read
back and checked, published without replacing anything), loads it with its own point cache (the
original's cache is kept) and only then switches the model's link to it, in one undoable step. The
`.napc` cache is written once per file by the import and never edited. Crop and Cut uses exactly the
same path.

### Built
- **Crop and Cut card** at the bottom of the Clean tab: **Remove Outside** (the clip box becomes the
  Keep box: everything outside it goes) and **Remove Inside** (a Cut box: everything inside it goes,
  up to 20); the clip box's own line with its Clip switch and Edit Clip Box; the box list (press a
  name to put that box into the clip box, adjust it, then Update; Rename; Delete; Delete All);
  Original / Result / Differences; exact counts; **Remove Points & Export LAS**.
- **The boxes live in the cloud's own record** (`cropCut`), every change one undoable step.
- **Live preview:** Result hides what the boxes remove (and the budget counts only kept points, so
  the result is as dense as the whole cloud); Differences paints it red. Outlines in the model: the
  Keep box green, Cut boxes red, each named. Only the active cloud, only while the Clean tab shows;
  while the boxes show, the filter preview waits.
- **Engine, ABI 8:** one box test (BoxFilter.hpp) for the picture, the count and the export;
  `napc_box_count`; `napc_box_export_start` through Clean & Export's own LAS writer (records copied
  byte for byte, nothing moves). A 48-number render block (the scene export) renders as before.
- **The export:** `<name>_Cropped_01.las`; then "Point Cloud: Use Cropped LAS" switches the link,
  keeps the position and clears the boxes (the same Undo brings both back). The cloud row says "a
  cropped copy". The configuration export holds each cloud's boxes.

### Fixed on the way
- **Engine swap safety.** While building, the new ABI 8 engine was written into the live plugin
  folder while SketchUp ran v0.10.0, which expects ABI 7: the old bridge unloaded its working engine
  first and then refused the new one, so cloud loading failed (Adam's Technical Log, 15:30). The
  committed DLL was put back within minutes; loaded clouds needed Reload All. The bridge now checks
  a build's ABI before touching the running engine, keeps an engine it can use running, and tries a
  refused build once, not every frame. Development of this version moved to a staging copy.
- **Cancel just after publishing.** A Cancel that arrived after the engine had already published
  the new file reported "Nothing was written" although the file existed. The engine's last word is
  now read first: the file is kept and offered (both exports).
- **Shadow copies named by content.** The engine's shadow copy is named by a digest of the build's
  bytes, not the file's time, so an engine update can keep the old file's time: a running plugin
  sees nothing newer and keeps its engine until Reload Plugin brings the code that wants the new one.
- **Reload after an engine swap.** Found by the upgrade test: after Reload Plugin swapped the engine,
  a loaded cloud counted as loaded although its points were gone, so Reload All said "Every point
  cloud of this model is loaded already" and its row had no Reload button (only Unload, then Reload,
  brought it back; a v0.10.0 gap). It now counts as needing a reload, with its own note.
- Reload Plugin now says when it swapped the engine, and that the clouds need Reload All.

### Tested (25-Oct-2026, all passing)
- Native, `test_native_boxes.py`, 65 checks: ABI 7 and ABI 8 byte for byte (synthetic cloud and
  JW02); Result frames equal a cloud of only the kept points; Differences equals a hand-recoloured
  cloud; counts against an independent numpy verdict, faces included; real exports of the synthetic
  room, two fixtures and JW02, every kept record byte for byte; the source's SHA-256 and time
  unchanged; refusals; cancel. JW02: count 10 to 17 ms, export 3.6 s (Clean & Export: 38.6 s).
- Ruby harness, SketchUp's own Ruby 3.2 with the real DLL and LAS files: boxes 84 (new), main 197,
  scenes 96, clean 59, multi 87, legacy 52, and the upgrade test 12 (the committed v0.10.0 running,
  the new DLL installed, then the v0.11.0 files loaded on top as Reload Plugin does). 587 in all.
- The card in a browser with states dumped by the boxes suite, at 600 and 440 px wide.
- Not yet tried in SketchUp itself.

### Checklist for Adam (in SketchUp)
1. Start SketchUp (in a running one, Settings > Reload Plugin swaps the engine to ABI 8 and says
   so), open a model and Reload its clouds (View tab).
2. Clean tab, at the bottom: Crop and Cut. Press Edit Clip Box, fit the box round the part to keep,
   press Remove Outside. Turn Clip off in the card: the model shows what will be saved (Result).
   Try Differences and Original.
3. Fit the clip box round a tree and press Remove Inside: it vanishes (Result) or turns red
   (Differences). Press its name to put it back into the clip box, move a side, press Update.
   Rename it.
4. Remove Points & Export LAS: Save As suggests `<name>_Cropped_01.las`. The new file loads in the
   same position; its point count matches the card; the original LAS and its cache are untouched.
5. Edit > Undo: the model names the original again, with its boxes. Reload brings the original back.
6. Clean & Export the cropped file: fewer points, a quicker clean.

## Point Cloud Viewer - v0.10.0 - 25-Oct-2026 - Several Point Clouds in One Model

### Summary
Adam asked for several point clouds in one model: an interior GeoSLAM scan and an exterior
photogrammetry scan, registered in completely different places, aligned by hand, switched on and off
at will and saved with scenes, with every tool working on each cloud on its own and the dialog always
saying which cloud it works on; up to about ten; each cached separately; the clouds on show sharing
the point budget; and, above all, clear data separation when everything is serialised, so it is plain
which configuration belongs to which cloud for recall and for TrueVision. A model now holds up to ten
clouds, ONE record each. ARCHITECTURE section 25 is the full description.

### Built
- **One record per cloud** (`20__System__CloudSet/...Store__.rb`): the index
  `Na__PointCloudViewer__Clouds` (model id, order) and one dictionary per cloud,
  `Na__PointCloudViewer__Cloud__pc_<8 hex>`, holding its name, colour, LAS link, placement, clip box
  and clip scenes. A change to one cloud rewrites only its record; every write is one named operation.
- **Slots and the active cloud** (`...Slots__.rb`, `Na__CloudSlot` in RenderTypes): every tool works on
  the active cloud, is bound to the cloud it started on, and is ended (with a message) when another
  cloud is chosen. Clip box, clip scenes, placement, Move, Rotate, the gimbal, Clean preview and Clean
  & Export all work per cloud. With two or more clouds the Undo names and the gimbal and clip cage name
  the cloud.
- **Show / hide and the look per cloud** (size, opacity, colour mode, plus a new Cloud Colour mode in
  the cloud's own colour, for aligning): view settings, never written to the model and never an Undo
  step; remembered per cloud on this computer and saved with scenes.
- **Engine, ABI 7:** `napc_render_layers_png` draws every cloud on show into ONE frame with one depth
  buffer, each with its own transform, clip, dot size, opacity and colour, and splits ONE budget
  between them (equal shares, a small or clipped cloud passes on what it does not need). A one-cloud
  frame is byte-identical to ABI 6.
- **Scenes schema 2:** a scene holds every cloud by id (shown or hidden, its look, its clip box, which
  LAS); recall restores them all (a cloud added later is hidden there); clip changes from a recall are
  one operation; export draws the clouds the scene shows as one picture.
- **Opening a v0.9 model:** read as it is and nothing written; the first change converts every record
  inside that change's own operation (the old link id carries on as the model id, so the backup file
  carries on too); one Undo puts the v0.9 records back byte for byte.
- **Backup schema 2** (every record by its dictionary name; v1 still read), **configuration export
  schema 2** (one section per cloud), **scenes API 4** for TrueVision Sync (backward compatible;
  one-cloud revision keys unchanged; the GLB Builder needs no change).
- **Dialog:** the cloud bar under the tab strip (eye, colour, name, status per cloud; the active one
  outlined in its colour; + to add), the View tab's Point Clouds card (reorder by grip, colour palette,
  rename, Reload, Locate LAS, Zoom To, Unload, Remove; Reload All; Zoom to Clouds; backup and Restore),
  cloud tags naming the active cloud on the Display, Clip Box, Clip Scenes, Position and Preview Region
  cards, Copy to Other Clouds on the Clipping tab, cloud chips on each scene card, and an import card
  that says whether the LAS adds a cloud, loads into one, or cannot (model full).

### Found by the tests during the work
- The upgrade test ran the COMMITTED v0.9.1 code to build a real v0.9.1 model and then opened it with
  v0.10.0. It showed v0.9.1 itself keys a scene differently in the session where the cloud was turned
  than after a Reload (a `+0.0` against a stored `-0.0`): `4b861f2b82`, then `a274dc1348`, same pixels.
  v0.10.0 matches v0.9.1's after-Reload keys exactly, so TrueVision re-renders nothing it holds from a
  session after a Reload. Left as it is on purpose (ARCHITECTURE 25.8).
- In the new code, before release: unloading a cloud whose import had been undone left a row that
  could never be reloaded (it now leaves the list, with the right message); and Reload All skipped a
  loaded cloud whose record names another file, after Undo of Use Cleaned LAS (it now reloads it, and
  its row says Reload to update).
- The LAZ converter's log line had a dash; now a full stop.

### Tested (25-Oct-2026, all passing)
- Native: `test_native_layers.py` 28 checks (layers against one-layer and ABI 6 output, the budget
  split, depth across clouds, opacity and colour per layer).
- Ruby, SketchUp's own Ruby 3.2 with the real DLL and real LAS files: multi-cloud 87, v0.9.1 upgrade
  52, main 197, scenes 96, clean 59. 519 checks in all.
- The dialog in a browser with states dumped from the multi suite: empty, one cloud, two, both
  unloaded, a recalled scene; every list control sends the right action.
- Not yet tried in SketchUp itself.

### Checklist for Adam (in SketchUp)
1. **Update both computers before opening models with v0.10.0.** A model is converted to one record
   per cloud by its first change; v0.9.1 then sees no point cloud in it.
2. Settings > Reload Plugin (the engine swaps to the ABI 7 build). Open a v0.9 model: the cloud bar
   shows its one cloud; Reload brings it back where it was. Nothing is written until you change
   something; that first change is one Undo step.
3. Add Point Cloud (or + in the cloud bar): the import card says it adds cloud 2 of 10. Import the
   exterior; both draw together, the nearer points in front.
4. Click each chip in turn: the Clipping, Transform and Clean tabs name that cloud. Unlock and move
   the exterior onto the interior (Cloud Colour on the Display card helps see which is which), lock it.
5. Turn each cloud off and on with its eye: nothing appears in Edit > Undo.
6. Set a clip box on the interior only; save a SketchUp scene with the exterior hidden, and another
   with both; switch between them on the Scenes tab.
7. TrueVision Sync: export both scenes. The scene showing both clouds should hold both in one picture.

## Point Cloud Viewer - v0.9.1 - 21-Oct-2026 - LAZ Import: Lossless LAZ to LAS Converter

### Summary
Adam asked for a LAZ to LAS converter so Polycam LAZ files can be imported, with one rule above all:
nothing may affect accuracy or size. Import LAS / LAZ now accepts a .laz. It is decompressed into a
NEW LAS next to it (Save As, never overwriting), checked record by record, and that LAS's usual import
report and unit question follow. Everything after that (point cache, model link, Clean & Export)
works on the LAS exactly as before. No new dependency: the decoder is the LASzip 3.5.0 the engine
already vendored, unmodified. ARCHITECTURE section 24 is the full description.

### Built
- **Engine (ABI 6):** `LazConvert.hpp/.cpp` (the job: worker thread, progress, cancel, partial file,
  check, publish without replace) and `LazRecord.cpp` (turns each decoded point back into record bytes
  with LASzip's OWN raw item writers, `laswriteitemraw.hpp`). The header, VLRs, user data and LAS 1.4
  EVLRs are copied byte for byte; only the point format's compression bits, the LASzip VLR (so the VLR
  count and offset to points) and a 1.4 EVLR start change. Scale, offset, bounds, counts, GUID, dates
  and generating software are untouched, and the bounds are never recomputed: the points' real extent
  is measured and reported beside them. COPC index records are dropped with a note. Refused with a
  plain message: not LAZ, LASzip compatibility mode, internal waveform data, a header LASzip reads
  differently from its bytes, a damaged or cut-short LAZ.
- **Check before the file gets its name:** the new layout must read back with the LAZ's exact format,
  record length, count, scale, offset and bounds, and every other header byte equal; the record bytes
  on disk must hash to what was written; LASzip must read every record back to the same bytes again.
- **Ruby:** bridge ABI 6 (`Na__Native__Laz*`, its own live-job map destroyed first on a DLL swap);
  `40__System__LasImport/...LasImport__LazConvert__.rb` (Save As loop: `<name>.las`, else
  `<name>_FromLaz_01.las`; the job; the report rows); the Controller routes .laz (and a LAZ-compressed
  file named .las) to it and gained `Na__LasImport__Inspect(path, conversion)`.
- **UI:** the button reads Import LAS / LAZ, the picker shows both, and a converted file's report starts
  with Converted from, Conversion check and Header bounds rows. When a LAZ's header bounds disagree with
  its points, the status line is a warning that says the size shown comes from the header.

### 21-Oct-2026: what the online converter did to Adam's sample (reported to Adam)
- Adam's sample `21_10_2026.laz` (Polycam, LAS 1.2, format 2, 3,698,370 points) and the LAS an online
  converter made from it (`21_10_2026 (1).las`). The engine's conversion keeps every point; its decoded
  extent reproduces Polycam's own header bounds to the last bit.
- The online converter's LAS has the same count, scale and offset, but **not one of its 3,698,370 records
  is identical to the LAZ's**. Matched to the nearest point, its points sit 0.33e-3 file units away at
  the median, up to 1.48e-3 (0.3 mm and 1.5 mm if the file is in metres). That is about the scan's own
  point spacing (0.35e-3), so its points are not the LAZ's points moved slightly: they are effectively
  different points. Its header bounds were recomputed from those points (overall extent 2.0e-5 smaller in
  X). Do not use that file for survey work; convert the LAZ with the viewer instead.
- The sample's whole extent is 1.343 x 1.285 x 0.466 file units (1.3 m x 1.3 m x 46.6 cm if in metres),
  the same in the LAZ and both LAS files. Worth a look on import if the scan was a room.

### Tested
- Adam's LAZ through the DLL: 3,698,370 points in 1.2 s (1.0 s decode + 0.2 s check); the LAS is
  96,157,847 bytes = 227 + 3,698,370 x 26; header bytes changed from the LAZ: only 96, 97, 100, 104.
- `laz_convert.rb.test` (SketchUp's own Ruby 3.2 loading the real bridge, AsyncJobs, Controller and
  converter against the real DLL; UI and dialog doubles): 34 checks, all passing. Pick a .laz, Save As,
  convert, the import report with its rows; byte-identical to the DLL-only run; the destination rules
  and the refusal of an existing file; cancel mid-conversion (nothing left, not even a partial file); an
  uncompressed LAS and a cut-short LAZ refused with nothing written; a LAZ with deliberately wrong header
  bounds converted with the bounds kept byte for byte and the warning shown.
- All 11 point formats: a generator built against the vendored LASzip wrote the same 50,000 random
  points (every attribute, GPS time, RGB, NIR, waveform packets, 3 extra bytes on formats 1, 4, 7, 10,
  LAS 1.2 / 1.3 / 1.4, an extra VLR) as LAZ and as uncompressed LAS. Each converted LAZ's records are
  byte-identical to LASzip's own uncompressed LAS, header fields and VLRs equal; a compatibility-mode
  LAZ is refused. 40/40 Ruby files compile under SketchUp's Ruby 3.2.
- Not yet tried in SketchUp itself: the Save As dialog, the overlay during conversion, the report card,
  then importing the converted LAS.

### Checklist for Adam (in SketchUp)
1. Settings > Reload Plugin (the engine swaps to the ABI 6 build), then Import LAS / LAZ and pick the
   Polycam .laz. Save As offers `21_10_2026.las` in the same folder.
2. The overlay shows Decompressing, then Checking; Cancel deletes everything it wrote.
3. The import card opens with Converted from, Conversion check and Header bounds rows (Header bounds
   should say Match the points exactly). Check the Extent and the unit sizes, choose the units, Import.
4. Pick the converted `.las` again later: it imports directly, with no conversion.

## Point Cloud Viewer - v0.9.0 - 19-Oct-2026 - Scenes Tab: Point Cloud Scenes for TrueVision

### Summary
Adam asked for the viewer's settings to be bound to SketchUp scenes, recalled by pressing the
scene, and exported as images that TrueVision lays over its drawings for survey work. The Scenes
tab binds the clip box, point budget, point size, opacity, colour and visibility to a SketchUp
scene, found by `Page#persistent_id` and kept in the viewer's OWN model dictionary. A scene also
carries what it is for TrueVision (Plan, Site Plan, Elevation, Section, 3D View) and the scale it
will be printed at, which sets the dot size baked into its picture. TrueVision Sync (GLB Builder
2.11) renders the pictures through the public API and pushes them to R2. ARCHITECTURE section 23
is the full description.

### Built
- **Store** (`90__System__Scenes/...Scenes__Store__.rb`): dictionary `Na__PointCloudViewer__Scenes`,
  key `json`, schema 1. Found by persistent id, with the scene's name kept only as a hint. Read
  only when the record is corrupt or from a newer version, and unknown keys survive a save. Every
  change is one named operation, then the local backup. Nothing is ever written to a SketchUp
  scene (Page): no attribute, no update, no observer.
- **Recall** (`...Scenes__Recall__.rb`): moves SketchUp to the scene, then applies the saved
  settings, visibility and clip box in one operation. A missing scene changes nothing and says
  so, and Relink is the user's choice (a scene with the same name is suggested, never adopted).
- **Image export** (`...Scenes__ImageExport__.rb`): renders off screen from the scene's own camera
  (it never selects a scene, so no transition can be caught halfway). It works at 12 px per paper
  mm, in 2048 px tiles, under a 160 MP ceiling. Every dot is centred on its point within half a
  pixel. The frame record places the picture exactly in TrueVision's world. The revision key
  changes when anything that changes the picture changes.
- **Public API** (`...Scenes__PublicApi__.rb`, scenes API 1) for TrueVision Sync: scene list,
  export settings, plan, render, frame record, pixel of a model point.
- **UI** (`...Scenes__UiSystem__MainUiLogic__.js`, `...UiFeature__Styles__Scenes__.css`): the Scenes
  tab. Cards with recall, tags, warnings and relink, plus Type, Scale (presets or custom) or Image
  Width, Dot Size, Go To Scene, Update and Remove.
- Model link, local backup and restore carry the scenes record (`NA_RECORD_KEYS`).

### 19-Oct-2026: Site Plan scenes, and the scale list Adam meant
- Adam: "I put 1:2000. What I meant to put was 1:1250 and 1:2500 ... there will be site plan point
  clouds as well." The scale presets now end 1:500, 1:1250, 1:2500 (1 px dots), and a **Site Plan**
  scene type sits after Plan. It looks straight down like a plan, and TrueVision lays it on a site
  plan viewport (or a plan). The tilt warning names it: "A site plan should look straight down."

### 19-Oct-2026: Adam's first look at the Scenes tab
- **Scenes is now the second tab** (View, Scenes, Clipping, Transform, Clean, Settings).
- **Colour mode checked:** RGB or Monochrome is part of every saved scene. It is captured, recalled,
  baked into the exported picture, shown in the summary, and a colour change alone marks the scene
  Settings changed.
- **Update moved away from Go To Scene.** Adam: "The update button is too easy to fudge." Go To Scene
  now stands alone on the left; Update and Remove sit together on the right. Update goes amber
  (not blue) when the settings have changed.
- **Are you sure? dialogs on Update and Remove.** These replace the old two-click Remove. Update
  shows Saved Now against Will Become (the payload's new `currentSummary`) and warns when SketchUp
  is showing a different scene, which is the easy mistake. Remove lists what goes and that TrueVision Sync
  stops exporting the scene. Cancel has the focus; Escape and a click outside also cancel.

### 19-Oct-2026: Scenes API 2, for TrueVision Sync's Scene Sync
- Each row of `Na__PublicApi__SceneList` carries `pagePid`, the SketchUp scene's persistent id. TrueVision
  Sync's Scene Sync tab (GLB Builder 2.12) uses it to pair a point cloud scene with the synced drawing of the
  same SketchUp scene, which TrueVision then lays it on exactly. `NA_SCENES_API_VERSION` is 2, guarded for hot
  reload, so a session reloaded from API 1 still answers 1: callers test for the key itself.

### 19-Oct-2026: Drag to reorder (clip scenes and point cloud scenes)
- Adam: "Ensure these can be rearranged so you can click to drag to reorder, use a grab box symbol". Each
  clip scene row (Clipping tab) and each point cloud scene card (Scenes tab) has a six dot grip. Press it and
  the row lifts and follows the pointer, the others slide out of its way, the panel scrolls near its edges,
  and letting go drops it there. Esc puts everything back. A grip with the focus moves its row with the up
  and down arrow keys. Full Cloud has no grip and stays first. No grips while a name is being renamed, on a
  read-only record, or with only one scene.
- `01__AppCore/...UiSystem__DragReorder__.js` is the shared piece: listeners delegated to the list (so a
  state push never loses them), a repaint held back while a row is lifted, pointer capture, FLIP slides.
- Ruby: `Na__Clip__SceneReorder` and `Na__Scenes__Reorder` take every id top to bottom and save the new
  order as one undoable step ("Point Cloud: Reorder Clip Scenes" / "Point Cloud: Reorder Scenes"). A list
  that no longer matches the scenes (one added or removed meanwhile, or an id twice) changes nothing and
  says why; the same order again writes nothing. Dialog actions `clip_scene_reorder` and `scenes_reorder`.
- **Scenes API 3:** `Na__PublicApi__ReorderScenes(model, ids)`, so TrueVision Sync's Point Cloud tab (GLB
  Builder 2.13.1) drags the same record; the viewer's tab repaints when it does. Callers test respond_to?.
- TrueVision's own scene list stays alphabetical: the GLB Builder's store manifest sorts by name.

### Tested
- `pcv_scenario_scenes.rb`: 95 checks, all passing (83 plus the Update dialog's summary, colour
  mode alone marking a change, putting it back clearing it, each row's pagePid, and section 13b: the
  reorder from the tab and through API 3, the store revision, a stale list refused, Undo).
- `pcv_scenario.rb`: 189 checks, all passing (183 plus section 9b: clip scene reorder, its named step,
  the stored order, a stale or doubled list refused, the same order writing nothing, Undo).
- Drag to reorder driven in a browser with real pointer events on both lists: the lifted row, the
  live order, a state push held back mid drag, one call per drop with the full order, nothing for a
  drop in place or after Esc, Full Cloud kept first, the arrow keys keeping focus.
- The dialogs were driven in a browser with a stub state: Escape, backdrop and Cancel send nothing,
  each confirm sends exactly one call, and the dialog closes if its scene disappears.
- The original 83 cover the record, read-only and
  unknown-key cases, recall, relink and remove, and the public list (Site Plan, 1:1250 and 1:2500).
  They also cover the export: frame, tiles, dot centring for 1 to 4 px, perspective, horizontal
  fov, size limit and revision keys. Tripwires prove no SketchUp scene was ever written, updated,
  added or erased.
- Not yet tried in SketchUp itself: the scale presets' dot sizes (1:50 and 1:100 especially) want
  Adam's eye on a real scan.

## Point Cloud Viewer - v0.8.0 - 12-Oct-2026 - Clean Tab, Clean & Export to a New LAS

### Summary
Adam asked for a complete architectural point cloud cleaning system inside the viewer: a Clean
tab with three filters (Remove Noise, Refine Surfaces, Reduce Density), a live preview in the clip
box, an Original / Cleaned / Differences view, a surface check, and Clean & Export LAS that never
touches the original: a Save As every time, a new file, checked and published without replacing
anything, loaded in the same position and used by the model only when everything succeeded.
Designed, built and tested; ARCHITECTURE section 22 is the full description.

### Built
- **Engine (ABI 5):** clouds keep each point's LAS record and GPS time; LAS content key; point
  cache v2 named by the content key (v1 still read); the cleaning engine (deterministic KD-tree,
  zones and halos, preview worker per cloud with stage re-use and supersession, full-cloud tiling,
  sparse cell grid); the LAS export writer (record passthrough, header rebuilt, VLRs / EVLRs kept,
  provenance VLR, partial file, LASzip check, publish without replace).
- **Ruby:** bridge for ABI 5 (contexts and export jobs destroyed before a DLL swap);
  `80__System__Clean/` (Settings: strength to physical values; Preview: debounced requests, poll
  timer, display clouds; Export: Save As loop, checks, the job, the model association, retry);
  content keys in the import, the cache and the model link (`contentKey`, `derivedFrom`, `history`);
  placement carried over to a new local origin; Undo after "Use Cleaned LAS" leaves the loaded
  cloud in place with a note.
- **UI:** Clean tab between Transform and Settings (Preview Region, three filter cards with
  Advanced Settings, Preview Results with the display switch, legend, statistics, surface check,
  Reset to Defaults; Clean & Export with the last export's report and Load Cleaned LAS). Version
  0.8.0; config `clean` section and `render.cleanColours`.

### Found by testing today and fixed
- **False "doubled surface" at corners and trim junctions** (no doubling in those scenes). Causes,
  each measured: 60 mm of a wall in a corner block fixes its normal only to ~5 degrees (PCA on the
  true labels: 4.9 degrees), so a tilted plane read as two sheets; "thin" blocks at frame / sash
  staircases and sill edges lent planes tilted 17 to 50 degrees; the second plane of a block was
  scored on leftovers, where an edge-on frame strip fits any plane; trims fell back to the 8 mm
  default noise width; junction steps passed the footprint test; a pipe's sides passed the width
  test because 5 % of wall points inflated a standard deviation. Fixes: planes borrowed from thin
  cells, joint scoring over the whole block, a half-block test for thin cells, the noise width from
  the nearest thin cells, a mixing test for doubling, a robust width. False doubling points before
  -> after: corner 1825 -> 0 and 856 -> 0; window 618 -> 451, 1429 -> 661, 124 -> 0; blow-out 8551 ->
  3278; details 6981 -> 924 and 1695 -> 177. Real doublings still found (99.7 %, 99.9 %).
- **Exports failing with "Not enough memory" for large Advanced values or sparse clouds:** the
  per-region cell grid was dense over the whole tile plus halo (~400 MB even for 60 points). Now
  sparse (blocks allocated where points are); results identical (preview = export still bit for
  bit), memory follows the points.
- **An existing destination or the source itself** was only refused after a whole clean, with the
  message "appeared while cleaning". The engine now refuses both (and a missing folder) before
  cleaning, with the right message.
- **Undo of "Use Cleaned LAS"** could move the still-loaded cleaned cloud to its own import
  position when the original had no saved position. Now it stays where it is, with a note.
- **Previews too slow on dense scans** (a 1 m box on Cossethay took 2.5 s, over the 2 s target).
  Measured stage by stage: the 1348 mm margin is most of the work for a small box (32k points in
  the box, 1.45M gathered), and 75 % of the surface analysis was the two-sheet mixture test. The
  mixture EM now runs on fine bins (validated against the per-point EM on 499 943 real cases: the
  same decision in all but 10, each on a threshold); gather, the KD-tree build, the noise-width
  helper and the MSAC cost loop were made faster without changing a single result (checked point
  by point on 2.65M points and by test H). The same 1 m Cossethay box: 2.5 s -> 1.26 s. Not met
  everywhere: at the densest spot of each scan a 1 m box takes 0.2 s (JW02), 0.9 s (Derby Road),
  2.1 s (Cossethay) and 7.0 s (SK02, a passage the scanner went through many times: 615k points
  in one square metre, where refinement alone takes 3.1 s).
- **Whole-cloud clean slow on a site with one very dense spot** (found on SK02, Adam's Ascott
  Drive scan): one tile size for the whole site was set by its densest spot, 1181 tiles of ~2 m,
  each re-reading its 1.35 m margin. Tiles are now split only where the points are (113 tiles,
  clean 480 -> 331 s); the same flags and positions for all 66.3M points of JW02, Cossethay and
  SK02, compared point by point. The export now also fails, rather than skip a point, if the tiles
  ever miss one.

### Verified (all run today)
- Algorithms A to H 100/100; identity and cache 20/20; export integrity I 122/122 (LAS 1.2 formats
  0 to 3, LAS 1.4 formats 6 to 8, extra bytes, EVLRs, WKT); failure handling J 14/14; Ruby harness
  183/183 (existing) and 57/57 (Clean tab); performance K below, on six clouds including Adam's
  SK02 Ascott Drive GeoSLAM export (39.0M points). All suites were run again after the speed
  changes. Every real scan's SHA-256 and modified time were unchanged after its export.

### Performance (final engine, 12-Oct-2026 23:39; ARCHITECTURE 22.15)

| Cloud | Points | Load | Clean whole cloud | Write + check | Export total | Engine work peak | Process peak | Preview 1 m / first 2 m / 2 m re-used | Source unchanged (SHA-256 + time) |
|---|---|---|---|---|---|---|---|---|---|
| Synthetic room (LAS 1.2 f1 + time) | 1.16M | 1.0 s | 3.2 s (1 tile) | 0.8 s | 4.0 s | 224 MB | 564 MB | 0.44 / 1.10 / 0.17 | n/a (synthetic) |
| Synthetic 9 rooms (LAS 1.2 f1 + time) | 10.46M | 7.9 s | 42.1 s (8 tiles) | 5.3 s | 47.5 s | 959 MB | 1722 MB | 0.49 / 1.42 / 0.19 | n/a (synthetic) |
| JW02, RealityCapture (LAS f2, no time) | 10.76M | 1.1 s | 33.0 s (12 tiles) | 5.5 s | 38.6 s | 576 MB | 1027 MB | 0.05 / 0.44 / 0.01 | yes |
| Cossethay, GeoSLAM (LAS f1 + time) | 16.47M | 1.9 s | 86.6 s (25 tiles) | 8.0 s | 94.8 s | 1566 MB | 2694 MB | 1.38 / 3.51 / 0.78 | yes |
| Derby Road, GeoSLAM (LAS f1 + time) | 31.30M | 3.7 s | 149.0 s (70 tiles) | 14.9 s | 164.0 s | 947 MB | 2413 MB | 0.04 / 1.13 / 0.01 | yes |
| SK02 Ascott Drive, GeoSLAM (LAS f0, no time) | 39.03M | 3.3 s | 324.9 s (113 tiles) | 31.1 s | 356.2 s | 1814 MB | 3787 MB | 0.24 / 1.73 / 0.07 | yes |

Other processes (RealityScan) kept 0 to 3.4 cores busy during these runs. Before the speed work
and the adaptive tiles, the same evening: export total JW02 73.3 s, Cossethay 170.5 s, Derby Road
293.6 s, SK02 535.8 s.

### Limitations (see ARCHITECTURE 22.13)
- Doubled surfaces closer than ~2.5 noise widths cannot be seen without GPS time (20 mm at 10 mm
  noise: 11 %).
- Dense false reflections are kept by design; sparse blow-out only marked unless asked.
- Thin objects seen from both sides (an open door leaf, a radiator in front of its wall) are
  flagged as possible doubling and held (seen on Cossethay); real scans: 6 to 15 % of points
  flagged, not checked against a survey.
- At 10 mm noise, a ~2 noise-width band each side of a corner line is held, not refined.
- The first preview of a cloud also builds its coarse grid (0.3 to 0.4 s at 10 to 16M points,
  ~1 s at 39M).
- Not run: a destination folder without write permission; nothing was tried inside SketchUp itself.

### For Adam to test
- Reload Plugin is not enough this time: restart SketchUp (ABI 5 DLL and new Ruby).
- Load a scan, turn on the clip box round a wall and a corner, open the Clean tab: the preview
  appears; switch Original / Cleaned / Differences; drag a strength slider.
- Clean & Export LAS...: the suggested name is `<name>_Cleaned_01.las`; try choosing the original
  (refused) then a new name; when it finishes the model shows the new file in the same place; the
  original and its cache are untouched; Edit > Undo puts the model's link back.
- In Differences, magenta marks possible doubled surfaces: worth judging by eye on a real scan
  (SK02 flags 14.8 % of its points; open doors and radiators are flagged too and left as scanned).
- SK02 (39M points): a whole-cloud Clean & Export takes several minutes (see the table); check
  that SketchUp stays responsive meanwhile and that Cancel stops it with nothing written (both
  checked only in the offline harness so far).

---

## Point Cloud Viewer - v0.7.0 - 03-Oct-2026 - Faster Rendering, Point Cache, Cold-Start Crash Fixed

### Summary
Adam asked whether the optimisations promised before the clip box were ever done (they were not),
confirmed v0.6.0 persistence works ("everything's in the transformed place"), and asked for the
cache so a reload pops in without a full re-read. Then SketchUp started crashing on every start.

### Cold-start crash (fixed)
- Five crashed starts, identical: `SketchUp.exe+0x384172`, null write, Ruby interpreter on the
  stack, ~20 s after launch, `su_assistant.rb` (AI Assistant) on the stack in two dumps. A 22:02
  dump showed the same fault before most of today's changes.
- Not the native engine (not loaded in the crashed process). Bisected with real cold starts using
  a scratch template (`SketchUp.exe <file.skp>`: SketchUp 2026 loads extensions only after the
  Welcome screen, so two early "no crash" tests had proved nothing):
  plugin off -> fine; plugin loaded, bootstrap skipped -> fine; bootstrap without the model
  observer -> crash; overlay added only by the startup notification -> fine.
- Cause: the first InstallOnce added the overlay to the model while SketchUp was still loading
  extensions. Every Reload Plugin worked because SketchUp was already running; today's restarts were
  the first real cold starts. Fix: a cold start only registers the AppObserver; the startup
  notification adds the overlay (ARCHITECTURE section 18). Verified live: no crash, overlay
  registered and enabled, session bound.

### Rendering (ARCHITECTURE 7.2)
- Binned raster (per-band bins, one worker per band): 1M points 2x faster; all 10.8M 38% faster at
  full resolution. Images byte-identical to v0.6.0 in every test case.
- Screen crop (ABI 4): the image covers only the visible box's screen rectangle; nothing is
  rendered when the cloud is off screen or behind the camera. Zoomed out on JW02: 9.4 MB -> 0.8 MB
  per frame for SketchUp to decode. Live in SketchUp: 16% of the viewport rendered.
- Parallel PNG checksums (zlib combine): encode 10.5 -> 2.8 ms.
- Orbit budget: at most 5M points while moving (all 10.8M orbiting: 57 -> 23 ms native), the whole
  budget once settled.

### Point cache (ARCHITECTURE section 9)
- `.napc` v1 written by the import worker (tmp + rename), loaded on a worker thread, header CRC and
  exact length checked, LAS size + time recorded. One cache per scan.
- Reload Point Cloud and Import LAS use the cache when the LAS is unchanged (JW02: ~0.1 s), rebuild
  it when the LAS changed, fall back to the LAS when a cache is damaged, and load the cache alone
  (with a note) when the LAS cannot be found anywhere.
- Settings: cache count and size, Clear Point Caches.

### Verified
- Native: equivalence test old vs new engine (4 cases + crop), perf table, cache test (write, peek,
  0.08 s load, byte-identical render, wrong count / truncated / CRC-damaged / missing refused).
- Offline harness: **183 checks pass** (13 new): cold-start registration, crop and off-screen
  skip, orbit cap and settle, cache saved on import, Reload from cache, damaged cache falls back,
  LAS missing loads from cache, Clear Point Caches.
- Live SketchUp (scratch template, pinned to a test instance): two cold starts with the final
  code plus the bisection run that proved the cause, no crash; import + render with the crop,
  screenshot correct.

### For Adam to test
- Start SketchUp normally, open a model, open the dialog: no crash.
- Reload Point Cloud: the first time reads the LAS and saves a cache; the next Reload is near
  instant.
- Orbit with All points: smoother while moving, full density when you stop.

---

## Point Cloud Viewer - v0.6.0 - 03-Oct-2026 - Saved With the Model, Gimbal Point, All Points

### Summary
Adam, working with v0.5.0: move and rotate are "incredible". Three requests: (1) a 20 million
point budget, (2) data persistence that can never leave a model with its cloud in the wrong place
the next day, and never auto-loads (Undet once made his files unopenable), with the model as a
pointer and a second copy so two things have to fail, (3) a gimbal he can place on a vertex, like
SketchUp's Axes tool.

### Point budget
There was no computational limit: the plugin ceiling is already 50 M. The slider stops at the
loaded cloud's own point count (JW02: 10,758,745) because a higher budget cannot draw more, and
the 20 M preset looked disabled. Now presets at or above the cloud's size become one **All**
preset, the value reads "All 10,758,745", and the hint says it is the top of the scale. Display
settings are remembered per user, so the raised budget is still raised tomorrow.

### Persistence (see ARCHITECTURE section 14)
- New `Na__PointCloudViewer__ModelLink` record (link id, LAS name, last path, path relative to
  the .skp, unit, point count, fingerprint). Written on import, rewritten only when the LAS or its
  location changes.
- Local backup per link in `91__UserConfig__LocalOnly/Na__PointCloudViewer__ModelBackups/`,
  rewritten after every real point cloud change; a newer one is archived, never overwritten.
- Nothing happens on open. The View tab's **Saved With This Model** card offers Reload Point
  Cloud (header fingerprint checked first), Locate LAS..., Restore Newer Backup / Restore From
  Backup. Settings has Open Backups Folder and Remove Point Cloud Data From Model.
- Placement and clip writes now abort the operation on error and carry `updatedEpoch`.
- Placement matching ignores the file name (point count + survey origin), so a renamed copy keeps
  its position.
- Element Studio Pro was checked first: it keeps JSON in definition attribute dictionaries and
  does nothing on open, but has no copy outside the model. Its patterns (operations with abort,
  validation, defaults merge) were kept; the backup is new.

### Gimbal point
- Default moved from the base centre to the centre of the cloud's box.
- **Set Gimbal Point** (Transform tab): the next click, with SketchUp inference, places the
  gimbal; it is stored on the cloud (local coordinates) so it moves and turns with it. **Centre
  Gimbal** resets it. Both undoable, saved in the model.
- Typed X / Y / Z are now the gimbal point's model position; typed rotations turn about it.

### Verified
- Offline harness: **170 checks pass** (32 new): link written once with a relative path, backup
  mirrors every change, the "closed without saving" case end to end (older .skp reopened, backup
  shown as newer, an unrelated Undo leaves it alone, Restore writes it back in one operation,
  Reload brings that alignment back and writes nothing), unreadable link falls back to the
  backup, Locate refuses a non-matching file and can be cancelled, Remove deletes all three records
  and Undo restores them, display settings carry into a new session, gimbal pick snaps to a vertex,
  moves with the cloud in 5 mm steps, typed rotation pivots on it, Esc while picking, Centre +
  Undo.
- Dialog checked in the browser pane: link card with a newer backup, All preset, gimbal row.

### For Adam to test (Reload Plugin)
- Save the model, close SketchUp, reopen: nothing loads; the View tab card shows the LAS found;
  Reload Point Cloud brings it back in place, locked, with its clip box.
- Move the cloud, close SketchUp WITHOUT saving, reopen: the card offers Restore Newer Backup.
- Transform > Unlock > Set Gimbal Point > click a vertex; drag the arrows from there.

---

## Point Cloud Viewer - v0.5.0 - 03-Oct-2026 - Transform Tab: Move Gimbal, Rotate Protractor, Lock, Export

### Summary
Adam, after testing v0.4.0: "The clip box works absolutely perfectly... Now add the tool so we can
transform a point cloud." He asked for a gimbal like Vertex Tools (drag X / Y / Z, snap, 5 mm by
default), a SketchUp-style protractor rotation that can line the cloud up with things, a lock that
keeps the cloud untouchable until he goes back into the transform tools, typed values for fine
control, and a JSON export of the whole configuration. All of it is on a new **Transform** tab.

### Built
- **`60__System__Transform/`**: Placement (state, maths, storage, lock, typed values, snap
  prefs), MoveTool (gimbal), RotateTool (protractor), ConfigExport, Transform tab JS + CSS.
- **Placement** = rigid `R` + `t`, kept orthonormal, stored in the model dictionary
  `Na__PointCloudViewer__Placement` with the cloud's fingerprint; restored when the same LAS is
  re-imported (the import message says so). Locked by default; one undoable operation per change;
  Undo / Redo re-read it with the clip state (`Na__Registry__ReloadModelState`).
- **Move gimbal**: red / green / blue arrows at the cloud origin, fixed size on screen, hover
  highlight, drag or click-move-click, 5 mm snapping from the drag start (per-user step, can be
  turned off), typed distance, Esc, dashed axis guide.
- **Rotate protractor**: centre, start direction, rotate; SketchUp inference on the clicks so the
  cloud snaps into line with model edges and endpoints; arrow keys lock the axis; optional angle
  snap (15 degrees, off by default); typed angle during or after; Esc.
- **Typed values**: X / Y / Z of the cloud origin (survey point shown) in model units; Plan (Z),
  Tilt X, Tilt Y in degrees; Reset to Import Position (second click confirms).
- **Export Configuration...**: save panel (model's folder), one JSON file with cloud, units, local
  origin, placement (incl. matrix), clip box, scenes, display and snap settings.
- Engine untouched (ABI 3): the render matrix was already general. The image renderer's cache key
  now includes the placement, so a move re-renders; the clip box stays fixed in the model.
- A cloud imported before v0.5.0 gets a placement derived from its matrix on Reload Plugin, so no
  re-import is needed.

### Verified
- Offline harness: **138 checks pass** (59 new) with the real modules, DLL and JW02: lock refusals,
  unlock record, gimbal hover / drag / 5 mm snap / VCB re-type / Esc, snap step validation, typed
  X + Plan 90 (pure rotation, bounds swap width and depth, no scale), tilt with a unit, undo twice,
  protractor (axis keys, snapped centre, exact 90 degrees onto a model point, re-type 45, angle snap
  50 -> 45, Esc, typed -30), moving the cloud half out of a fixed clip box (48% left), lock
  deselects the tool, export file contents and cancel, a different LAS not inheriting the position,
  re-import restoring position + lock, a pre-v0.5 cloud getting a placement.
- Dialog checked in the browser pane: layout at 600 px, locked state disables tools and values,
  a state push does not wipe a half-typed value, Esc reverts, Reset needs a second click, every
  button sends the right action.

### For Adam to test (Reload Plugin; the loaded cloud keeps working)
- Transform tab > Unlock to Transform > Move: drag the arrows; watch the 5 mm steps in the VCB.
- Rotate: click a corner, click along a wall in the cloud, then click on a model edge.
- Type X / Y / Z and Plan; Undo; Lock Position (tools switch off); Export Configuration.
- Save, reopen, re-import the LAS: it comes back where you left it, locked.

---

## Point Cloud Viewer - v0.4.0 - 03-Oct-2026 - Clip Box, Clip Scenes, Test Tooling Removed

### Summary
Adam, after importing JW02: "It works incredibly... Try the clip box next... so I can get to work
drawing with it." The clip box was brought forward ahead of the `.napc` cache. The Clipping tab now
clips the cloud with six typed limits or by dragging the sides of a box in the model, and saves
clip scenes (Ground Floor, Roof, ...) in the `.skp`. All M1 test tooling and the em dashes in the
UI are gone.

### Built
- **Native (ABI 3):** clip parameters on the render call (enabled + model-space min/max); points
  are tested after local -> model, so the box stays level with the model. **Clip-aware budget:**
  with the clip on, the budget counts points INSIDE the box. The engine finds the smallest prefix
  of the (randomly ordered) point list holding N inside points, caches it per (box, placement,
  budget), and draws that prefix, so a small box is as dense as the whole cloud.
- **`50__System__ClipBox/`:** State (box, scenes, storage, every change), EditTool (cage drawing
  and the `Na__ClipBoxTool`), Clipping tab JS. See ARCHITECTURE section 10 for the behaviour.
- **Stored in the model**, dictionary `Na__PointCloudViewer__ClipState`, one named undoable
  operation per change; a `ModelObserver` per model re-reads it after undo/redo.
- **Edit tool:** square handles at the face centres, hover outline, press-drag or click / move /
  click, typed distance in the VCB (also re-types the last move), Esc cancels, clips live while
  dragging, half-resolution renders during the drag.
- **Scenes:** Full Cloud (clip off, box kept), save, switch, Update when changed, inline rename,
  delete with a confirming second click.
- **Zoom to Cloud** frames only the clipped part while clipping is on.
- **View tab:** cloud name + points + size, Unload button, drawing fault line, plain budget hint.
- **Settings tab:** Technical Log moved here; About without milestone text.
- **Removed:** synthetic cloud, benchmark runner and reports UI, Diagnostics tab, Position
  placeholder tab, live performance strip and stats polling, FrameBuilder, the Ruby point
  primitives (GL_POINTS / draw_points / line dots), `renderPrimitive` and `colourBucketLevels`
  settings, the `dev` user-config section (user config schema v3 drops it), DrawStats.
- **Wording:** no em dashes or dash punctuation anywhere the user reads (dialog, status messages,
  tool status text, LAS import messages).

### Verified
- ctypes, JW02 (10,758,745 points), box = middle ninth of the plan: 1M drawn of 1,225,267 inside
  (was ~114k before the clip-aware budget); limit search 19 ms once, then cached; budget = total
  and budget 0 behave.
- Offline harness rewritten for LAS + clip: **79 checks pass** with the real modules, the real DLL
  and the JW02 file: import, clip on at the bounds, typed limits (bare mm and "0.5m"), refusals,
  edit tool hover / drag / VCB / negative VCB / Esc / click-move-click, scenes (save, unnamed,
  reset, switch, Full Cloud, Update, rename, delete), undo of rename and delete via the
  ModelObserver, a fresh session reading the same state, corrupt JSON ignored, unload keeps the box,
  no dashes in any dialog message.
- Dialog checked in the browser pane with a pushed state: Clipping tab layout, rename survives a
  state push mid-typing, Delete confirm, Esc reverts a limit.

### For Adam to test (Reload Plugin, then re-import the LAS: the engine was rebuilt)
- Clipping tab > Clip on: whole cloud still shown, box = bounds.
- Type Top / Bottom in mm: points above / below disappear immediately.
- Edit Clip Box: orange cage, drag a square handle, type a distance, Esc mid-drag, Undo.
- Save "Ground Floor", Reset to Cloud, click Ground Floor, Full Cloud.
- Save the .skp, reopen it and re-import the LAS (no cache yet): the box and scenes are still there.

---

## Point Cloud Viewer - v0.3.0 - 03-Oct-2026 - Milestone 2a: LAS Import

### Summary
View tab > **Import LAS...** reads a `.las` through the vendored LASzip, inside the native engine,
on a worker thread. A report of the header comes first, then an explicit unit choice, then the
import with progress and Cancel. The cloud lives only in the engine and is drawn by the native
image renderer. First real file: Adam's JW02 Juggles Joint RealityCapture export.

### The test file (JW02, RealityCapture)
LAS 1.2, point format 2, 26-byte records, **10,758,745 points, 280 MB**, 16-bit RGB, no VLRs (no
coordinate system, no units), local coordinates 59.3 x 45.1 x 13.8. The `.rsInfo` says
`exportVertexColors="0"`, but the points do carry RGB.

### Built
- Engine (ABI 2): `napc_las_read_header` (facts + VLR scan: WKT 2112, GeoTIFF 34735),
  `napc_las_import_start` / `napc_job_poll` / `_error` / `_cancel` / `_take_cloud` / `_destroy`.
  The worker reads every point, stores it as float32 in the SOURCE unit relative to a local
  origin (header bounds: centre x, centre y, min z), detects 8- vs 16-bit colour from the data,
  then shuffles (deterministic Fisher-Yates) so the point budget is a uniform sample of the whole
  cloud. Progress via atomics; cancel checked every 65,536 points.
- LASzip compiled from the vendored copy with upstream's exact source list (the legacy
  `lasunzipper.cpp` / `laszipper.cpp` in the same folder are not part of it and do not compile).
- **LASzip trap:** `laszip_get_point_count` returns the number of points READ so far, not the
  file's total (0 straight after opening). The total is the header's `number_of_point_records`,
  or `extended_number_of_point_records` for LAS 1.4.
- Ruby: `40__System__LasImport/` (controller, job, panel JS). The unit question pre-selects
  nothing unless the file's WKT names a linear unit; every option previews the real size
  (Metres 59.3 m x 45.1 m x 13.8 m, Millimetres 5.9 cm x 4.5 cm x 1.4 cm). `.laz` and
  LAZ-compressed files are refused with a plain message.
- The unit factor is applied per frame on the render matrix diagonal (`local_to_model`); stored
  coordinates never change.
- Engine memory of a replaced or cleared cloud is freed immediately, not at GC.
- A LAS cloud is always drawn natively; benchmark Ruby-primitive cases skip on it.
- Async jobs accept a per-step `delay` and `quiet`, so polling the worker every 0.1 s does not
  flood the dialog.

### Verified
- Standalone (ctypes): header 0.4 ms; import 2.9 s cold (read 2.4 s, colours 23 ms, shuffle
  0.4 s); cancel stops mid-read; render at 1600 x 1000: 2M points 35 ms, all 10.8M 70 ms. The
  rendered view shows the farm buildings correctly (Z-up, metres, colours).
- Offline harness: 95 checks pass, including this file through the real dialog actions
  (import 1.1 s warm, 1M drawn in 10 ms, all 10.8M in 27 ms, memory freed on clear).

### Not yet
- No cache: an import lasts for the SketchUp session (re-import after restarting or after a
  native engine hot swap). Milestone 2b adds the `.napc` cache and model association.
- Shuffled order costs raster cache locality; the octree (M3) restores spatial order.

---

## Point Cloud Viewer - v0.2.0 - 03-Oct-2026 - Milestone 1b: Native Image Renderer

### Summary
The M1 benchmark (Adam, SketchUp 26.2.243, graphics_engine_2024, RTX 5080) ruled out drawing
points through SketchUp's View API. The cloud is now rasterised by a C++ engine into an image and
shown as ONE textured screen quad. It is the new default primitive ("Native image"). Point size,
opacity and Monochrome Black now work, and a still camera costs ~0.1 ms per redraw at any point
count. Adam, testing live: "It's actually really fast now."

### What M1 measured (full suite, 1,000,000-point synthetic house)
| Primitive | Cost per drawn point | 100k points | 1M points |
|---|---|---|---|
| GL_POINTS | ~2.3 us (draw) / ~3.0 us (frame) | 300 ms (3.3 fps) | 3,050 ms |
| draw_points | ~2.3 us | - | 3,140 ms |
| GL_LINES "line dots" | ~0.13 us per vertex | - | 310 ms, but drew NOTHING (sub-pixel segments are culled) |

- Colour-batch count barely matters (1 vs 231 calls: 2.18 vs 2.39 us/pt). The cost is SketchUp's
  per-point path, not our Ruby.
- Visual checks: GL_POINTS ignores size; draw_points honours size; no primitive honours alpha;
  nothing is hidden by model faces (overlays draw on top); point-to-point depth works.
- Ruby Point3d conversion 631 ns/pt; full GC pause 160 ms at 1.2 M live objects.
- `view.last_refresh_time` returned ~0 - removed from reports.

### Texture route probes (live SketchUp via the MCP bridge, 1909 x 1228 logical viewport)
- `view.draw2d` textured quad: 0.1 ms. `load_texture`: ~3 ns/px (6.5 ms full window).
- `ImageRep#set_data` 32-bit: ~54 ns/px (125 ms full window) - too slow. 24-bit is 3.5x faster but
  has no alpha. `ImageRep#load_file` of an UNCOMPRESSED (stored) PNG: ~16 ns/px with alpha - the
  route used. BMP drops alpha; TGA slower.
- Texture alpha composites correctly over the model.
- **UVs must be plain Arrays (or Point3d).** `Geom::Vector3d` UVs - the type the docs name - make
  SketchUp sample the texture's single average colour (the whole card showed as a flat tint). Found
  by drawing the same quadrant texture with each UV type and texture source.
- Projection: SketchUp's model-to-screen mapping reproduced from camera eye/axes/fov/height alone
  with 0.0 px error (perspective, 60 deg perspective, parallel) against `View#screen_coords`.

### Built
- **Native engine** `02__Src__NativeEngine/` (decimator layout): C ABI DLL
  `Na__PointCloudViewer__NativeEngine.dll` - thread pool (16 workers here), compute-rasterisation
  style splatting (64-bit atomic depth|colour per pixel, nearest wins, no locks), round splats from
  3 px, opacity, monochrome, stored-deflate PNG writer (slicing-by-8 CRC-32, Adler-32). Static CRT,
  no AVX2 requirement. CMake + Ninja + MSVC 14.44; build script maps a free drive letter for path
  length and unmaps it afterwards.
- **Fiddle bridge** `08__NativeEngine/...Bridge__.rb`, not a Ruby C extension: no Ruby headers or
  import library, independent of SketchUp's Ruby version, and **hot-swappable** - Ruby loads a
  shadow copy, so the build can overwrite the DLL while SketchUp runs, and Reload Plugin unloads the
  old copy and loads the new one. Native clouds are Fiddle pointers freed by GC; before a swap
  every live one is destroyed and owners re-upload.
- **Image renderer** `10__Viewport__OverlayRenderer/...ImageRenderer__.rb`: camera key + settings
  key; reuse the texture when nothing changed; half resolution while the camera moves
  (`render.nativeImage.movingScale`); one full-resolution render 0.25 s after it stops.
- Default primitive `nativeImage`, default budget 1,000,000. User config schema v2 drops the old
  `dev.renderPrimitive` so a saved Ruby primitive does not hide the new default.
- Benchmark: native cases (orbiting, camera still, forced full scale) with raster / PNG / load /
  texture medians; Ruby primitives kept at 100k as a reference.
- Dialog: 4-way primitive switch, Native column in Visual Checks, native timing columns,
  native line in the live strip, native status in Settings.

### Verified
- Standalone DLL self-test (Python ctypes): PNG valid; exact pixel placement for parallel and
  perspective; nearest point wins; 5 px round splat; 50% alpha; mono; behind-camera culled.
  Speed (random points, 16 threads, 2 px): 1M at 1909x1228 31.6 ms, 4M 57.7 ms; at 955x614 1M
  15.7 ms, 4M 31.2 ms. Raster dominates (random points thrash the cache; a cache in spatial order
  will be kinder).
- Offline harness (real modules + the real DLL via Fiddle inside SketchUp's Ruby DLL): 81 checks
  pass.
- Live: Adam ran it in SketchUp - fast.

### Still open
- Points are still not hidden by SketchUp faces (an Overlay limitation, unchanged from M1).
- Full-resolution frames after the camera settles cost ~45-75 ms - a one-off hitch, not per frame.
- Next: Milestone 2 - LAS import (LASzip) and the `.napc` cache feeding this engine directly.

---

## Point Cloud Viewer - v0.1.0 - 03-Oct-2026 - Milestone 1: Viewport Renderer Proof

### Summary
New self-contained plugin: `Na__PointCloudTools__PointCloudViewer__Loader__.rb` +
`Na__PointCloudTools__PointCloudViewer__Modules__/`. Milestone 1 proves the viewport architecture
before any LAS/cache engine is written: a persistent `Sketchup::Overlay` per model, a prepared-frame
renderer, a deterministic synthetic test cloud, and a benchmark that measures what drawing points
through SketchUp's Ruby View API really costs. Design for the whole plugin:
`85__Docs__AppDocumentation/Na__PointCloudViewer__ARCHITECTURE__.md`.

### Why the renderer comes first
SketchUp's Ruby View API has no retained GPU buffers, no per-vertex colour and no binary input.
Every redraw re-submits every drawn point as a Ruby `Geom::Point3d`, once per colour batch. That
is the single greatest risk to the product, and no amount of cache engineering helps if it is too
slow. So it is measured first.

### API facts verified (ruby.sketchup.com, Oct 2026)
- `Sketchup::Overlay` (2023.0+): `draw` and `getExtents` are "called very often"; overlays are not
  pickable or exportable; model changes from overlay events raise. `OverlaysManager#add` returns
  false for a duplicate id; a removed overlay cannot be re-added.
- `View#draw_points(points, size, style, color)`: one colour, size in logical px (2025+).
  `View#draw(GL_POINTS, points)`: colour from `drawing_color`; options are only normals / texture /
  uvs. No per-vertex colour anywhere.
- `View#line_width=` clamps to >= 1.0 as of 2026.0. Whether it sizes GL_POINTS is undocumented.
- `View#graphics_engine` (2024+), `last_refresh_time`, `refresh` (synchronous, use sparingly).
- Forum reports (not verified here): `draw_points` ignores occlusion; frame rate dropped from >60
  to 20 fps at 20-100 k points through `draw_points`.

### Built
- **Overlay + registry** - `Na__CloudOverlay`, one per model via an AppObserver
  (`expectsStartupModelNotifications`), found by id in `model.overlays` (no Ruby-side model hash,
  nothing to leak). Show switch = `overlay.enabled`, the same switch as the Overlays panel.
- **Renderer** - `Na__RenderFrame` of colour batches prepared outside `draw`; `draw` issues one
  call per batch. Three primitives for the decision: GL_POINTS, draw_points, GL_LINES sub-pixel
  "line dots". Draw faults pause drawing instead of raising every frame.
- **Render settings** - Point Budget (log slider, presets, numeric), Point Size, Point Opacity,
  RGB / Monochrome Black. None rebuild point arrays except budget/primitive/batching, which
  re-slice cached buckets.
- **Unit contract** - exact factors, no defaults, three-line unit summary in the UI.
- **Synthetic test cloud** - two-storey house with openings, inner faces, floors, roof, trees,
  ground; generated in metres, converted through the unit contract, packed as float32 blocks and
  converted to Point3d in a timed step. Position-driven colour tint so it fills colour buckets like
  real data (8 / 39 / 217 of 8 / 64 / 512) - without it only 16 of 64 buckets were used and the
  benchmark would have under-counted draw calls.
- **Benchmark** - quick and full suites (`benchmark.suites`), orbit camera, forced refresh per
  frame, median/p90 frame time, draw time, SketchUp refresh time, model-only baseline, overlay
  cost, ns per point. Camera and settings restored on finish, cancel and failure. Reports in
  `90__AppCache__PointCloudCache/00__DevBenchmarks/`.
- **Visual checks** - size / occlusion by faces / occlusion by points / opacity / orbit feel per
  primitive, saved per PC and merged into the latest report.
- **Async jobs + loading overlay** - timer-tick steps with progress and Cancel; the page paints its
  overlay before calling Ruby.
- **Settings** - hot reload (Ruby + HTML/CSS/JS + config JSON), explicit note that a native `.so`
  cannot be reloaded, native engine status, Open Cache Folder, user config folder.
- **LASzip 3.5.0** vendored (copy, not submodule), unmodified, with manifest and README.
- `.gitignore`: `**/90__AppCache__PointCloudCache/`.

### Verified offline
`D:/_ClaudeScratch/pcv_runners/` runs the real modules in SketchUp 2026's own Ruby 3.2 DLL
against API stand-ins: 62 checks pass - overlay registered once (also after repeated install and
after reload), generation progress/finish, bounds, determinism, every draw path, budget slicing,
black + opacity colour, setting clamps, draw-fault containment and recovery, user-config
persistence, benchmark report/skip/derived figures, camera + settings restore on finish and on
cancel, refused starts closing the loading overlay, observations merge, visibility, zoom, hot
reload (same overlay, no extra observer, cloud survives, new code draws), dialog reopen + notice.
All Ruby parses with SketchUp's parser; all JS passes `node --check`; the dialog was rendered in a
browser with a sample state.

### Not verified (needs SketchUp)
Every number, and every visual question: actual draw cost, whether line_width sizes GL_POINTS,
occlusion behaviour, alpha, orbit feel, real Point3d conversion cost, real GC pause.

### Known gaps
- No native code yet; the studio PC has no MSVC/CMake/Ninja and the decimator's Ruby-headers
  submodule is not checked out here.
- Clipping and Position tabs are placeholders describing their milestone.
