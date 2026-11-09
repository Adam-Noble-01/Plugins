# Na SketchUp MCP - Agent Guide
# =============================================================================

How to drive a live SketchUp 2026 model through this server. It is written for any model and any MCP client: Claude, GPT (Codex), Gemini, Cursor and others. The server's short instructions summarise it. Read this page (resource `sketchup://guide/agent`) before a long modelling session.

## 1. The Seven Rules

1. **Start with `sketchup_status`.** It tells you whether SketchUp is connected and which model is open. It also reports the open group (edit context), the licence (solid tools need Pro), read-only mode, whether Ruby eval is allowed, and which tools this SketchUp cannot run.
2. **Everything is world coordinates, in mm, degrees and persistent ids.** This holds at every nesting depth, inside open groups too. You never apply transformations yourself.
3. **One call is one undo step.** Each model change is named `MCP: <Tool Title>`. A failed call changes nothing. `batch_execute` makes many calls into one step.
4. **Look, act, look again.** Inspect first (`outliner_tree`, `entity_query`, `view_capture`). Verify afterwards with `geometry_measure` and `view_capture`, and describe only what you have seen.
5. **Never invent SketchUp API.** The tools cover normal modelling. For anything else, confirm each method with `ruby_api_lookup`, then use `ruby_eval`.
6. **Name everything you create.** Pass `name` on every call that makes a group, component, 3D text or section plane. Use what the user would call it, in the naming style the model already uses (read `outliner_tree` first). The user finds your work by name in the Outliner. Without a name, the bridge falls back to kind and size ("Box 1200 x 600 x 150") and warns you.
7. **Only change what the user asked for.** Never overwrite files, discard unsaved work, delete, purge or explode unless asked. If the bridge is read-only, say so; do not look for a way round it.

## 2. Connecting

- Every SketchUp window on Windows is a separate process with its own bridge. `sketchup_status` lists them all in `instances` (pid, the model open now, path), with `selected: true` on the one in use. With none chosen, the server takes the newest window when it first needs one and stays on it: a window opened later never takes over. Pass `select_pid` once and every later call goes to that window. If the window in use closes, every call is refused and names the windows still open, until you pass `select_pid`.
- If SketchUp is not connected, `sketchup_status` returns `connected: false` and tells you how to fix it: start SketchUp, or tick **Extensions > Na SketchUp MCP > Bridge Running**. Other tools return `Error (not_connected)`. Tell the user; do not retry in a loop.
- The bridge only listens on 127.0.0.1 and needs a per-session token that the server reads from a local file. No setup is needed from you.
- The user can see what you do. SketchUp's status bar shows each call. **Extensions > Na SketchUp MCP > Status Dialog** lists the recent calls and has the safety switches.

## 3. Units, Ids and Coordinates

### Units
- Lengths default to **mm**. Every tool with lengths accepts `units`: `mm`, `cm`, `m`, `in`, `ft`, `yd`, or `model` (the model's own display unit). It applies to that call's input and its output.
- Length values may also be strings with their own unit: `"2400mm"`, `"2.4m"`, `"96in"`, `"8'6\""`.
- Angles are **degrees**. Areas and volumes come back in the call's unit squared or cubed. Each result says which unit it used.

### Ids
- Ids are SketchUp **persistent ids**: integers that survive save and reopen. Get them from `entity_query`, `outliner_tree`, `selection_get` or `collection_list`. Every create call returns the new `id`.
- Some operations make **new** entities, which have new ids. Use the ids they return:
  - `solid_boolean` results;
  - `explode` (it returns the released ids);
  - `make_unique`, which gives an instance a new definition;
  - copies from `entity_transform`.
- Most tools take `ids` as a list: at most 2,000 per call. Faces and edges have ids too, which `entity_query` with `types` returns.
- `path` (ids from the root down) is only needed when a component is used several times and you mean one particular copy.

### The coordinate rule
- **Every point you send and every point you get back is in world coordinates.** This holds at any depth, in open or closed groups, and in groups that are rotated, mirrored or scaled. The bridge does the conversion, following SketchUp's own rule about the open context. You never multiply by `transformation` or `edit_transform`.
- Boxes come back as `bounds: {min, max, size}`. That is the world-axis-aligned box of the true geometry, so a rotated or scaled parent does not inflate it.
- `coords: "local"` is available when you want to give points in the parent's own axes. You rarely need it.
- Where new geometry goes (`parent_id`):
  - omitted: the active context, which is the open group if there is one, otherwise the model root;
  - `0`: the model root;
  - an id: inside that group's or component's definition. Every copy of a shared component gets it, and the reply warns you.
- Local axes follow the solid. `geometry_create_solid` and `component_place` set the new group's own axes along its orientation, so later rotate and scale edits behave naturally.
- Inside `ruby_eval` none of this applies, because you are writing raw SketchUp Ruby:
  - lengths are inches (`2400.mm`, `x.to_mm`) and angles are radians (`90.degrees`);
  - in the open context and all its parents, `Vertex#position`, `Face#normal` and instance `transformation` are world;
  - everywhere else they are local to their definition.

## 4. Undo, Safety and Timeouts

- **One call, one undo step.** A failed call is rolled back. `model_undo {action: "undo", steps: n}` undoes the user's steps too, so only undo what you did.
- **`batch_execute`** runs up to 200 steps in one round trip and one undo step.
  - `atomic: true` is the default. If any step fails, the bridge undoes every step and returns each step's outcome in `error.details.steps`.
  - With `atomic: false`, the steps that worked are kept. `stop_on_error` (default true) decides whether the batch carries on.
  - `rollback: true` makes the batch a zero-trace trial (bridge 1.0.5+): every step runs and reports, then everything is undone and no undo step is left. Captures saved during it stay on disk. The activity log shows `Trial: ...`, not FAILED. Camera moves and scene activation are not undone, so note the view first.
  - `model_file` and nested batches are not allowed. `context_set` is only allowed when `atomic` is false.
- **Read-only mode.** Model-changing tools return `Error (read_only)`. `view_capture` and the query tools still work.
- **Eval switched off.** `ruby_eval` returns `Error (eval_disabled)`. The user controls both switches in the status dialog.
- **Timeouts are reported, never retried.** A timeout or dropped connection means *status unknown*: the change may or may not have happened.
  - Check with `entity_query` or `sketchup_status` before trying again.
  - Some clients stop waiting after about 60 s, Claude Desktop for example.
  - Split very large jobs into several calls, for example 20 batches of 100 components rather than one of 2,000.
- **Modal dialogs cannot block you.** During `ruby_eval`, message boxes and file pickers are answered automatically. File tools switch summary dialogs off.

## 5. Tool Map

The server has 63 tools. Clients with tool limits can start it with `--toolset core`, which keeps the 22 tools marked ★.

| Family | Tools | Use for |
|---|---|---|
| Status | `sketchup_status`★, `model_info`★ | Connection, versions, licence, edit context, model statistics, units, tags, scenes |
| Model | `model_settings`, `model_file`, `model_purge`, `sketchup_open_window`, `sketchup_close_window` | Units and precision, description and location; save, save_as, save_copy, open, new, export, import; purging unused items; another model in its own window (or a copy of it), and closing that window again |
| Inspect | `entity_query`★, `entity_get`★, `outliner_tree`★, `collection_list`, `geometry_measure` | Finding ids; full detail (placement, geometry, attributes); the hierarchy; listing materials, tags, scenes, definitions, styles and environments; bounds, area, volume, length, counts and ray tests |
| Selection | `selection_get`★, `selection_set`★, `context_set`★ | Reading and changing the user's selection; opening and closing groups for editing |
| Create | `geometry_draw`★, `geometry_create_solid`★, `geometry_create_mesh`, `geometry_extrude`★ | Lines, rectangles, circles, arcs, polygons and faces with holes; nine manifold primitives; meshes of any size; push/pull and Follow Me |
| Edit | `geometry_edit`, `solid_boolean`, `entity_transform`★, `entity_delete`★, `entity_set_properties`, `entity_reparent` | Soften, harden, hide, reverse, intersect and merge faces; solid tools; move, rotate, scale, mirror and arrays; deleting; name, tag, hidden, locked, shadows; moving groups and components into another group or a new one, in place |
| Organise | `group_create`★, `component_place`★, `component_manage`, `attributes_get`, `attributes_set` | Grouping; placing definitions or .skp files; make_unique, replace, explode, rename, save; custom data |
| Look | `material_manage`, `material_apply`★, `tag_manage`, `scene_manage` | Colours, textures and PBR maps; painting; tags (Adam's Tags SSOT tags with `create_standard`) and tag folders; scenes |
| TrueVision | `truevision_structure`, `truevision_export`, `truevision_export_edit`, `truevision_publish` | How the TrueVision GLB Builder reads the model: storey containers, element groups by tag, the GLB files, and everything it skips with the reason; every object listed for classifying, with face orientation and floor levels. Adam's GLB Builder itself (2.14.0): its status, export manifest, Project tab, site plan, scenes, point clouds, jobs, R2 inventory and logs; exports into a folder or the linked project, the project link, scheme folders, site plan stores, Scene Sync and point cloud settings; and, only when the user asks, pushes to the live site (R2) and the R2 purge, each with `confirm` = the project code |
| Annotate | `annotation_create`, `image_place`, `section_plane` | Text, 3D text, dimensions and guides; images and textured faces; section cuts |
| View | `view_get`, `view_set`★, `view_capture`★ | Camera, standard views, face style, x-ray, shadows, rendering options, styles; images of the model returned to you |
| Escape hatches | `model_undo`★, `sketchup_send_action`, `ruby_eval`★, `ruby_api_lookup`★, `batch_execute`★ | Undo and redo; native commands (deprecated in SketchUp 2026.2, so prefer the tools); Ruby; the official API index; batches |
| Library | `asset_library`, `asset_library_edit` | Adam's component library through his Component Editor Tools (Na Noble3d Modelling Tools): overview, browse, get, next free code, naming checks and audits; save, rename, move, update, archive, create folders, and apply or revert whole tidy plans |
| Point clouds | `point_cloud_state`, `point_cloud_clip`, `point_cloud_view`, `point_cloud_slice`, `point_cloud_fit`, `point_cloud_check`, `point_cloud_heightmap` | Adam's Na Point Cloud Viewer (`view_capture` shows the clouds only with `include_point_cloud`): which clouds, their look, clip boxes and clip scenes, cache path; a clip box in mm, round entities or from a clip scene, one undo step; show, dot size, opacity, colour; exact counts, histograms with peaks and parallel images inside a box; slices, heightmaps and profiles at any angle (`frame`) |
| Windows and doors | `entity_studio`, `entity_studio_edit` | Adam's Element Assembly Studio Pro (Entity Studio Pro): presets, handle assets, and a placed element's parts with each fielded panel's solid check; build and update exterior single and double doors from a preset and config values, save presets, redraw a preset's gallery picture, open the dialog, reload its code |

## 6. Recipes

Arguments are shown as JSON. Lengths are mm.

**Survey a model before changing it**
```json
{"tool": "outliner_tree", "arguments": {"max_depth": 2, "include_bounds": true}}
{"tool": "view_capture", "arguments": {"standard_view": "iso", "zoom": "extents", "width": 1024, "height": 640}}
```
Then use `entity_query` with filters to find things by name, tag, material, type or attribute. Results come in pages: follow `next_offset` until it is null.

**A box, moved and painted, as one undo step**
```json
{"tool": "batch_execute", "arguments": {"operation_name": "Plinth", "steps": [
  {"tool": "geometry_create_solid", "arguments": {"shape": "box", "size": [1200, 600, 150], "position": [0, 0, 0], "name": "Plinth", "tag": "Joinery"}},
  {"tool": "entity_transform", "arguments": {"ids": ["$0.id"], "operations": [{"type": "rotate", "angle": 15}, {"type": "translate", "vector": [2000, 500, 0]}]}},
  {"tool": "material_apply", "arguments": {"ids": ["$0.id"], "material": "#D9CBB0"}}
]}}
```
`"$0.id"` is replaced by step 0's `id`. Any value in an earlier step's result can be referenced, e.g. `"$2.ids.0"`. Step 1 rotates about the box's own centre (the default), then moves it.

**Nest objects into a storey container for TrueVision**
```json
{"tool": "truevision_structure", "arguments": {"analyse_faces": true, "save_path": "C:/Temp/Model__TrueVisionStructure.json"}}
{"tool": "batch_execute", "arguments": {"operation_name": "TrueVision tags and storeys", "steps": [
  {"tool": "tag_manage", "arguments": {"action": "create_standard", "names": ["90__Storey__GroundFloor", "21__ProposedBuilding__Walls"]}},
  {"tool": "entity_set_properties", "arguments": {"ids": [1201, 1202], "tag": "21__ProposedBuilding__Walls"}},
  {"tool": "entity_reparent", "arguments": {"ids": [1201, 1202], "new_group": {"name": "Ground Floor", "tag": "90__Storey__GroundFloor"}}}
]}}
```
Tag first, then move: the tag travels with each object, and moved objects get new ids (`$2.ids`). Run `truevision_structure` again to see the files TrueVision will get.

**Export a model into its TrueVision project, then publish it (only when the user asks)**
```json
{"tool": "truevision_export", "arguments": {"action": "status"}}
{"tool": "truevision_export_edit", "arguments": {"action": "link_project", "project_code": "RB05"}}
{"tool": "truevision_export_edit", "arguments": {"action": "export_project"}}
{"tool": "truevision_publish", "arguments": {"action": "push_dry_run"}}
{"tool": "truevision_export", "arguments": {"action": "job"}}
{"tool": "truevision_publish", "arguments": {"action": "push", "confirm": "RB05"}}
```
`status` says whether the model is linked and where exports go; `link_project` makes the target the project's latest scheme (`set_target`, `create_scheme` choose another). `export_project` zips the previous export into `00__Archive` first. A push, the dry run, R2 fetches and point cloud renders run as the GLB Builder's job: the call answers at once, and `job` (about every 10 s) reports progress, then the report. A push uploads what changed AND deletes GLBs that are no longer in the project folder; `confirm` is the project code, passed only when the user has asked for that push. The GLB Builder's dialog, when open, shows everything the tools do.

**A wall with a window opening (Pro)**
```json
{"tool": "batch_execute", "arguments": {"steps": [
  {"tool": "geometry_create_solid", "arguments": {"shape": "box", "size": [4000, 215, 2400], "position": [0, 0, 0], "name": "Wall"}},
  {"tool": "geometry_create_solid", "arguments": {"shape": "box", "size": [1200, 400, 1200], "position": [1400, -100, 900], "name": "Window opening W01"}},
  {"tool": "solid_boolean", "arguments": {"operation": "subtract", "target_id": "$0.id", "tool_ids": ["$1.id"]}}
]}}
```
`subtract` keeps `target_id` and cuts the tools out of it. The result is a new group with a new id (`$2.id`), and it keeps the wall's name, tag and material. The tools must overlap the target.

**Draw a footprint and extrude it**
```json
{"tool": "geometry_draw", "arguments": {"kind": "face", "points": [[0,0,0],[6000,0,0],[6000,4000,0],[3000,6000,0],[0,4000,0]], "extrude": 2700, "name": "Massing"}}
```
Points go counter-clockwise seen from above, so the face points up and `extrude` goes up. Add `holes` for courtyards. `rectangle`, `circle`, `polygon` and `arc` take `normal` to stand on any plane.

**Edit inside an existing group**
- Most tools don't need the group opened. Pass `parent_id` to create inside it, and `ids` to change things at any depth.
- Only `selection_set` and `group_create` need the entities in the **active** context. Call `context_set {action: "open", id}` first, and `context_set {action: "close_all"}` when finished.
- Changing a component's contents changes every copy of it. Pass `make_unique: true` on `material_apply` or `geometry_edit`, or call `component_manage {action: "make_unique"}` first, when only one copy should change.

**Arrays**
```json
{"tool": "entity_transform", "arguments": {"ids": [812], "copies": 9, "operations": [{"type": "translate", "vector": [600, 0, 0]}]}}
{"tool": "entity_transform", "arguments": {"ids": [913], "copies": 11, "operations": [{"type": "rotate", "angle": 30, "center": [0, 0, 0]}]}}
```
The first makes a row of 10: the original plus 9 copies, each 600 further along. The second makes a ring of 12 about the origin.

**Save a component to Adam's library** (needs Na Noble3d Modelling Tools)
```json
{"tool": "asset_library", "arguments": {"action": "overview"}}
{"tool": "asset_library", "arguments": {"action": "next_code", "series": "13_5000"}}
{"tool": "asset_library", "arguments": {"action": "check_name", "folder": "13__Building__Roof/13_5000__RidgeCrestings", "name": "13_5002__Roof__RidgeFinial__FleurDeLis__Type-02__"}}
{"tool": "asset_library_edit", "arguments": {"action": "save", "instance_id": 16633180, "series": "13_5000", "name": "Roof__RidgeFinial__FleurDeLis__Type-02", "library_data": {"gallery_name": "Fleur-de-lis Ridge Finial 02"}}}
```
- The library is the Component Editor Tools library folder. Its sets are the top folders (`Na__CoreLib__3dAssets` by default).
- Names follow `NN_NNNN__Series__Item__Descriptor__Type-01__Size__.skp`. `NN` is the category folder number, which mirrors the SSOT tag numbers. The code sits in its series folder's thousand. The component inside the file is named exactly like the file.
- Agree the folder, code and name with the user before `save`. Omit `code` to take the next free one.
- Every edit is journaled with byte copies of what it rewrites, and `asset_library_edit {"action": "revert", "journal": "<id>"}` puts it back. Archiving zips a file into the set's `00__Archive` as `<name>__30-Sep-2026.zip`.
- To tidy many files, send a whole plan to `apply_plan`. It runs as a dry run first (the default); then pass `dry_run: false`.

**Measure from a point cloud**
```json
{"tool": "point_cloud_state", "arguments": {}}
{"tool": "point_cloud_slice", "arguments": {"action": "histogram", "cloud": "pc_264338fa", "axis": "z", "bin": 50, "min": [16100, 12300, 0], "max": [16300, 14000, 3500]}}
{"tool": "point_cloud_slice", "arguments": {"action": "histogram", "cloud": "pc_264338fa", "axis": "z", "bin": 2, "min": [16100, 12300, 150], "max": [16300, 14000, 250]}}
{"tool": "point_cloud_slice", "arguments": {"action": "density", "view": "right", "resolution": 5, "grid": 100, "overlay_ids": [912345], "min": [16000, 12000, 0], "max": [16600, 15000, 3800]}}
{"tool": "view_capture", "arguments": {"scene": "STAIRS-POINTCLOUD", "include_point_cloud": true, "width": 1280, "height": 800}}
{"tool": "point_cloud_fit", "arguments": {"shape": "plane", "orientation": "horizontal", "min": [16550, 13240, 1150], "max": [17200, 13390, 1260]}}
{"tool": "point_cloud_fit", "arguments": {"shape": "circle", "axis": "z", "max_radius": 250, "min": [16300, 12040, 80], "max": [16540, 12300, 160]}}
{"tool": "point_cloud_check", "arguments": {"ids": [912345], "view": "right", "resolution": 5, "grid": 100}}
{"tool": "point_cloud_heightmap", "arguments": {"min": [14500, 10500, -500], "max": [19000, 17000, 1500], "resolution": 50, "stats": ["p2", "p50", "p98"], "save_path": "D:/scan/ground.npz"}}
{"tool": "point_cloud_heightmap", "arguments": {"action": "profile", "path": [[15000, 11000], [15000, 16000]], "width": 200, "stats": ["p10", "p50"]}}
{"tool": "point_cloud_slice", "arguments": {"action": "histogram", "axis": "y", "bin": 2, "frame": {"origin": [16000, 12000, 0], "angle": 37}, "min": [0, -150, 0], "max": [3000, 260, 2400]}}
{"tool": "point_cloud_slice", "arguments": {"action": "points", "limit": 2000000, "save_path": "C:/Temp/stair.npz", "min": [16000, 12000, 0], "max": [16600, 15000, 3800]}}
```
- No cloud point can be picked or snapped to, and `view_capture` shows the clouds only with `include_point_cloud: true`: measure with `point_cloud_slice`. `density` shows where the points are thick (planes, edges, a row of spindles); `image` shows the nearest point in each pixel.
- Histograms find planes: z for treads, floors and rail tops; x or y for walls, risers and post faces; along a run for repeats such as spindles. Go coarse first (50 mm bins over the whole height), then fine (1 to 5 mm) round each peak. `peaks[].at` is finer than a bin.
- A histogram is one pass over the whole cloud whatever the bins (up to 10,000), about 30 ms per 43 M points.
- `points` are an even sample of the box (the viewer stores clouds shuffled): up to 1,500 in the reply, or up to 5,000,000 in a `.npz` (`p` model mm, `c` colour) for numpy or the skill's `pc_kit.py --pts`.
- Images map exactly: model value at a pixel centre = `at_left_edge + (column + 0.5) * per_px`, the same for rows with `v`. `right` looks along -X with +Y to the right.
- Check your model against the scan two ways: `overlay_ids` draws a group's edges in red on a slice (`overlay_clip: true` keeps only what is inside the box), and `view_capture include_point_cloud: true` draws the clouds on show over any capture, where they sit on screen.
- `point_cloud_fit` turns a box of points into numbers: a level or wall plane, a rail line, a circle or cylinder, a post's box, each with rms, p95 and `inlier_share`. Box one thing tightly (look with `density` first). Where a curve runs into a straight piece at a tangent, end the box where the curve ends, or the circle comes out bigger.
- After building, `point_cloud_check` says how well the model sits on the scan: rms and the share within tolerance overall and per part (worst first), the worst spots, and a heatmap (red: the scan is outside the faces, the model too small; blue: inside, the model proud). Fix the worst part first and check again.
- A wall or a roof not square to the model: give `point_cloud_slice` or `point_cloud_heightmap` a `frame` (an origin and an `angle`, or `x_axis` and `y_axis`, or a group's `id`). The box, the view, `axis` and every position are then the frame's: a histogram along the frame's `y` finds a turned wall's faces, a `front` density is its elevation, a heightmap in a roof's frame reads its sag.
- Fit directions (1.0.17): a line runs uphill (start is the low end) and a plane's normal points up, a wall's with its larger horizontal part positive; `azimuth_deg` is the way a line rises or a plane falls (a wall: the way it faces). Fitted lengths are full length. If a circle fit warns of two circles, the curve is not one arc: tighten the box and compare tolerances (3, 5 and 10 mm).
- For ground, roofs, falls and kerbs, `point_cloud_heightmap`: per cell, p2 is the ground under grass and p98 the tops; its slope says which way a surface falls. A profile along a road, path or rail gives the rise, the gradient and the steepest metre. Save a `.npz` for the terrain kit (`pc_terrain.py`'s rasters layout).
- `point_cloud_clip` changes the model (one "Point Cloud: ..." undo step): clip only when the user asked to work the cloud, and put their clip scene back (`action: "scene"`) when done. Slicing never needs a clip box.

**Present the model**
```json
{"tool": "scene_manage", "arguments": {"action": "create", "name": "01 Street View", "camera": {"eye": [-8000, -12000, 1600], "target": [3000, 2000, 1500]}}}
{"tool": "view_capture", "arguments": {"scene": "01 Street View", "width": 1600, "height": 1000}}
```
`view_capture` changes the camera for the shot and then restores the user's view. Activating a `scene` leaves that scene active. Pass `save_path` to also write the image to disk.

## 7. Results and Errors

- Results are compact JSON.
- Entity summaries hold `id`, `type`, `name` / `definition`, `tag`, `material` and world `bounds`, plus `path` when nested. `detailed` adds placement (origin, axes, rotation, scale), size, volume and counts.
- `warnings` lists anything worth reading, for example that a painted definition is used more than once, so every copy changed.
- `undo_step` names the undo entry the call created.
- Each error reads `Error (<code>): <message>` followed by `Fix: <hint>`. Read the hint and change the call; repeating the same call gives the same error.

| Code | Meaning | What to do |
|---|---|---|
| `invalid_params` | Missing, wrong type or out of range. Values are refused, never clamped. | Fix the argument the message names |
| `not_found` | No such id, name, file or definition. For material and component names, the hint lists close matches. | Re-query ids; they change after booleans, explode and make_unique |
| `wrong_type` | The entity exists but is the wrong kind, e.g. a Face where a group is needed | Follow the hint, e.g. `group_create` first |
| `context_error` | The open group blocks the request | `context_set` open or close as the hint says |
| `unsupported` | This SketchUp build or licence lacks the feature, e.g. solid tools on Make | Tell the user; use another approach |
| `read_only` / `eval_disabled` | The user's safety switches | Tell the user; do not work round them |
| `operation_failed` | SketchUp refused or produced nothing, e.g. a boolean of non-solids, or points in a line | Check inputs: `geometry_measure` with `volume` lists `not_manifold_ids`. For a failed batch, read `details.steps` |
| `file_error` | A file could not be read or written | Check the path; never overwrite unless the user asked |
| `eval_error` | Your Ruby raised an exception; the model was rolled back | Fix the code (message and line are given) |
| `not_connected`, `timeout`, `connection_lost` | Transport problems | See §2 and §4; after a timeout, check before repeating |

## 8. Ruby Eval, Done Properly

1. First look up every method you plan to use, e.g. `ruby_api_lookup {"query": "Sketchup::Face#pushpull"}` or `{"query": "section plane"}`. Pass `{"code": "..."}` to check a whole snippet. `live: true` also asks the running SketchUp whether each method exists.
2. Write short code. The ready locals are `model`, `entities` (active), `selection` and `view`. The last expression is the result. Plain JSON data also comes back as `value`. Anything printed with `puts` comes back too.
3. By default the code runs as one undo step and is rolled back on any error. `transaction: false` is for code that manages its own operations, and for code that only changes the view.
4. Lengths are inches internally: write `1200.mm` and read with `.to_mm`. Angles are radians: `45.degrees`. Use `persistent_id` to hand ids back to the other tools.
5. Code cannot be interrupted, so avoid unbounded loops over huge models, and prefer `entity_query` paging.
6. The code is linted against the official API index. Calls to unknown methods come back as `warnings`; treat those as bugs.

## 9. Pitfalls That Catch Agents

- **Unnamed objects.** A group without a name shows as "Group" in the Outliner, so the user can't find it. Name everything (rule 6). Copies keep their source's name, boolean results keep the target's name, and `entity_set_properties` renames things later.
- **Shared components.** Editing inside a definition changes every copy; `make_unique` first.
- **Face direction.** A face's normal follows the right-hand rule of its points. If extrusions go the wrong way, give the points in the other order or pass `normal`. `geometry_edit reverse_faces` flips existing faces.
- **Loose geometry merges.** Geometry drawn unwrapped (`wrap_in: "none"`) merges with touching geometry. Keep the default group wrapper unless you mean to split faces.
- **Solid tools** need SketchUp Pro and manifold groups or components in the same parent. The result replaces the target under a new id.
  - Pass all the tools in one call (`tool_ids`), not one call per tool.
  - Let cutters pass 1 mm beyond the faces they cut. Faces lying exactly on each other make SketchUp's engine fail.
  - Dense curved meshes (thousands of faces) can take 30 s or more and may fail or leave holes. Keep segment counts modest, and cut simple blanks before adding detail.
  - The bridge checks the operands first. It explains a non-solid (open edges, internal faces), refuses an inside-out one, and skips tools that do not reach the target. It also warns when a result is not a solid: undo that result at once (`model_undo`), because the next boolean on it will be refused.
- **Meshes.** `geometry_create_mesh` fixes face winding itself. Closed shells come out as solids facing outward, and the result reports any open shells, which solid tools will refuse.
- **Scaled groups.** Push/pull distances and sizes you pass are world distances; the bridge corrects for the scale.
- **Tags hide things.** Hidden tags or `hidden: true` entities do not appear in captures. `entity_query visibility: "hidden"` finds them.
- **`sketchup_send_action`** runs asynchronously after the call returns and is deprecated in 2026.2. Prefer `view_set`, `model_undo` and the other tools. It is fine for picking a native tool for the user, e.g. `selectPushPullTool:`.
- **Captures cost tokens.** 1280×800 is the default. Use 800×500 for quick checks and larger only for final presentation.
- **Big models.** `outliner_tree` is capped by `max_depth` and `max_children`. Use `entity_query` filters and paging rather than asking for everything at once.
- **Library tools stand alone.** `asset_library` and `asset_library_edit` open library files in their own operation, which is always rolled back, so they are refused inside `batch_execute`. Call them on their own. They refuse a file whose component is placed in the open model unless you pass `allow_in_use`.

## 10. Resources and Prompts

| URI | What |
|---|---|
| `sketchup://guide/agent` | This guide |
| `sketchup://guide/instructions` | The short server instructions |
| `sketchup://api/summary` | API index facts and every class name |
| `sketchup://api/class/{name}` | One API class: methods, constants and docs link, e.g. `sketchup://api/class/Sketchup::Face` |
| `sketchup://model/summary`, `sketchup://model/selection`, `sketchup://model/outliner` | Live model info, selection and a two-level outliner |
| `sketchup://entity/{id}` | Live detail for one persistent id |

Prompts: `sketchup_survey_model`, `sketchup_build_from_brief`, `sketchup_whitecard_massing`, `sketchup_tidy_model` and `sketchup_scene_set`. Each is a ready-made plan for a common job.

## 11. Client Notes

- The instructions and every tool description are under 2,048 characters, so Claude Code does not cut them.
- Text results are capped at 45,000 characters, below the point where Claude Code saves big results to a file. Ask for less with `limit` or `response_format: "concise"` rather than more.
- The server speaks MCP protocol 2024-11-05 through 2025-11-25, and the 2026-07-28 revision (`server/discover`).
- It needs only Python 3.9+ and has no packages to install.
- Setup for each client (Claude Code, Claude Desktop, Codex, Cursor, VS Code, Gemini CLI) is in `85__Docs__AgentReference/Na__SketchUpMcp__ClientSetup__.md`.
