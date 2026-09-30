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

- Every SketchUp window on Windows is a separate process with its own bridge. `sketchup_status` lists them all in `instances` (pid, model title, path). Pass `select_pid` once and every later call goes to that window.
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
  - `model_file` and nested batches are not allowed. `context_set` is only allowed when `atomic` is false.
- **Read-only mode.** Model-changing tools return `Error (read_only)`. `view_capture` and the query tools still work.
- **Eval switched off.** `ruby_eval` returns `Error (eval_disabled)`. The user controls both switches in the status dialog.
- **Timeouts are reported, never retried.** A timeout or dropped connection means *status unknown*: the change may or may not have happened.
  - Check with `entity_query` or `sketchup_status` before trying again.
  - Some clients stop waiting after about 60 s, Claude Desktop for example.
  - Split very large jobs into several calls, for example 20 batches of 100 components rather than one of 2,000.
- **Modal dialogs cannot block you.** During `ruby_eval`, message boxes and file pickers are answered automatically. File tools switch summary dialogs off.

## 5. Tool Map

The server has 44 tools. Clients with tool limits can start it with `--toolset core`, which keeps the 22 tools marked ★.

| Family | Tools | Use for |
|---|---|---|
| Status | `sketchup_status`★, `model_info`★ | Connection, versions, licence, edit context, model statistics, units, tags, scenes |
| Model | `model_settings`, `model_file`, `model_purge` | Units and precision, description and location; save, save_as, save_copy, open, new, export, import; purging unused items |
| Inspect | `entity_query`★, `entity_get`★, `outliner_tree`★, `collection_list`, `geometry_measure` | Finding ids; full detail (placement, geometry, attributes); the hierarchy; listing materials, tags, scenes, definitions, styles and environments; bounds, area, volume, length, counts and ray tests |
| Selection | `selection_get`★, `selection_set`★, `context_set`★ | Reading and changing the user's selection; opening and closing groups for editing |
| Create | `geometry_draw`★, `geometry_create_solid`★, `geometry_create_mesh`, `geometry_extrude`★ | Lines, rectangles, circles, arcs, polygons and faces with holes; nine manifold primitives; meshes of any size; push/pull and Follow Me |
| Edit | `geometry_edit`, `solid_boolean`, `entity_transform`★, `entity_delete`★, `entity_set_properties` | Soften, harden, hide, reverse, intersect and merge faces; solid tools; move, rotate, scale, mirror and arrays; deleting; name, tag, hidden, locked, shadows |
| Organise | `group_create`★, `component_place`★, `component_manage`, `attributes_get`, `attributes_set` | Grouping; placing definitions or .skp files; make_unique, replace, explode, rename, save; custom data |
| Look | `material_manage`, `material_apply`★, `tag_manage`, `scene_manage` | Colours, textures and PBR maps; painting; tags and tag folders; scenes |
| Annotate | `annotation_create`, `image_place`, `section_plane` | Text, 3D text, dimensions and guides; images and textured faces; section cuts |
| View | `view_get`, `view_set`★, `view_capture`★ | Camera, standard views, face style, x-ray, shadows, rendering options, styles; images of the model returned to you |
| Escape hatches | `model_undo`★, `sketchup_send_action`, `ruby_eval`★, `ruby_api_lookup`★, `batch_execute`★ | Undo and redo; native commands (deprecated in SketchUp 2026.2, so prefer the tools); Ruby; the official API index; batches |
| Library | `asset_library`, `asset_library_edit` | Adam's component library through his Component Editor Tools (Na Noble3d Modelling Tools): overview, browse, get, next free code, naming checks and audits; save, rename, move, update, archive, create folders, and apply or revert whole tidy plans |

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
