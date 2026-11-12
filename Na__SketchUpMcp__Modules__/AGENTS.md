# AGENTS.md - Na SketchUp MCP

These are instructions for AI coding agents working **on** this plugin: Codex / GPT, Claude Code, Cursor, Gemini, Copilot and others.
**To model in SketchUp through the server, read `85__Docs__AgentReference/Na__SketchUpMcp__AgentGuide__.md` instead.** The server also serves it as the MCP resource `sketchup://guide/agent`.

## What This Is

A local MCP server that lets any MCP client inspect and edit the model open in SketchUp 2026 on Windows. It has 75 tools, and every SketchUp API call it makes is checked against the official API index.

```
MCP client --stdio--> Python server (30__McpServer__Python, stdlib only)
           --TCP 127.0.0.1:8385..8394, one JSON object per line, session token-->
           Ruby bridge inside SketchUp (04__ + 06__ + 10__, UI.start_timer pump)
           --> SketchUp Ruby API (main thread only)
```

Each SketchUp window is its own process with its own bridge. It writes `91__UserConfig__LocalOnly/Connections/Na__SketchUpMcp__Connection__<pid>.json` (port and token); the Python server reads those files to find it.

## Layout

| Path | Holds |
|---|---|
| `../Na__SketchUpMcp__Loader__.rb` | The file SketchUp boots. It requires `02__Plugin__CoreAppData/01__CoreAppLoaders/Na__SketchUpMcp__CoreAppLoaders__Main__.rb` (menu, toolbar, observers, auto-start) |
| `02__Plugin__CoreAppData/` | `AppConfig` (defaults and limits); **`ToolRegistry` (the single source of truth for every tool)**; the generated `SketchUpApiIndex` and `RubyCoreNames` (never edit these by hand) |
| `03__Plugin__CoreAppLogic/` | PathResolver, ConfigLoader (AppConfig + user settings), ActivityLog, DialogManager (status dialog), ReloadManager |
| `04__Plugin__BridgeCore/` | SocketServer (non-blocking pump), ConnectionFile, CommandRouter (routes, undo wrapping, batches), McpError, ApiSelfTest |
| `05__Plugin__UserInterface/` | Status dialog HTML, CSS and JS |
| `06__Plugin__BridgeHelpers/` | Params, Units, LinearMath, **Coordinates**, EntityResolver, Traversal, Serializer, Creation |
| `10__BridgeHandlers/` | One file per tool family. Each public method is `Na__Handlers__X__Y(params, ctx)` and returns a Hash |
| `30__McpServer__Python/` | The MCP server: protocol, registry, schema validation, tool runner, bridge client, API index and lint, resources and prompts |
| `40__Tests__Validation/` | Validators and test suites (below) |
| `80__DevTools__ApiIndexBuilder/` | Rebuilds the API index from SketchUp's `ruby-api-stubs`, and the Ruby core names from SketchUp's own Ruby |
| `85__Docs__AgentReference/` | Server instructions, agent guide, client setup, the modelling skill, third-party notices |
| `91__UserConfig__LocalOnly/` | Created at runtime: connection files, captures, user settings. Git-ignored |

## Commands

Run these from this folder. There is no system Ruby: the Ruby checks use SketchUp's bundled Ruby 3.2 DLL. All five must pass before you hand work back.

```bash
python 40__Tests__Validation/Na__SketchUpMcp__Tests__ValidateApiUsage__.py
python 40__Tests__Validation/Na__SketchUpMcp__Tests__RunRubyChecks__.py
python -B 40__Tests__Validation/Na__SketchUpMcp__Tests__PythonServer__.py
python 30__McpServer__Python/Na__SketchUpMcp__Server__Main__.py --check
node --check 05__Plugin__UserInterface/Na__SketchUpMcp__UiBridge__.js
```

- **`ValidateApiUsage`: "no invented API".** It checks that:
  - every registry `api` dependency exists in the index;
  - every `.method` call in the bridge is SketchUp API, Ruby 3.2 core or stdlib, or defined here;
  - every `Sketchup::`/`Geom::`/`UI::` constant, top-level constant and `Length::` unit exists;
  - every tool has a route, and every route has a method.
- **`RunRubyChecks`** compiles every `.rb` file, then runs the `*.rb.test` suites. The `.rb.test` extension keeps Reload Plugin Data from ever loading a test into SketchUp.
- **`PythonServer`** covers MCP protocol behaviour against a fake bridge: both protocol eras, validation, errors, images, resources and prompts.

## Hard Rules

1. **Never invent SketchUp API.** Look up each class and method with `ruby_api_lookup` or in `02__Plugin__CoreAppData/Na__SketchUpMcp__CoreAppData__SketchUpApiIndex__.json` before you use it. Add every method a tool cannot work without to that tool's registry `api` list; the live self-test probes them when the bridge starts. Anything newer than the index (SketchUp 2026.2 additions) must be checked live with `ruby_api_lookup {live: true}`.
2. **The coordinate rule.**
   - Every public coordinate is world space. SketchUp's rule: "In the active drawing context and all its parent coordinate systems all coordinates are global. In all other coordinate systems they are local."
   - Use only `Na__Coordinates` / `Na__Creation` / `Na__Serializer` for conversions, and never write transformation maths inside a handler.
   - A new group inside an open context must be pinned to identity before world points go in (`Na__Coordinates__PinGroupToIdentity`).
   - Test changes in the matrix under Live Testing below: a wrong conversion is invisible at the origin, and two opposite errors cancel in translation-only groups.
3. **Undo.** Handlers never call `start_operation`. The router wraps each mutating call in one `start_operation("MCP: <title>", true)` and aborts it on any exception. Tools that manage undo themselves have `"operation": false` in the registry.
4. **Refuse, don't guess.** Raise `Na__McpError.new(code, message, hint)` with a hint that names the fix. Refuse out-of-range values; never clamp them silently. The codes are listed in `04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__McpError__.rb`.
5. **Main thread, never blocking.** No threads, blocking reads or `sleep` in the bridge, and no modal UI (`UI.messagebox` and the like) in handlers. The timer pump must return quickly on every tick.
6. **Python is stdlib only, 3.9+.** stdout is the MCP channel, so never `print`: log to stderr through the logger.
7. **The registry is the contract.**
   - Descriptions stay at or under 2,048 characters (currently at most about 950).
   - Every `input_schema` has `additionalProperties: false`, and reuses `common_schemas` through `{"$use": "name"}`.
   - Tool names match `[a-z][a-z0-9_]*`.
8. **Naming and style (the Na__ plugin conventions).**
   - Files are `Na__SketchUpMcp__<Area>__<Purpose>__.<ext>`, and modules `Na__SketchUpMcp::Na__<Name>`.
   - Public methods are `Na__<Module>__<Action>`. Always call them with an explicit receiver (`self.` or the module): a capitalised bare call parses as a constant and raises NameError.
   - Private helpers are `na_snake_case`.
   - Indent 4 spaces. Every file has the header block, `REGION | ...` / `endregion` blocks and the `END OF FILE` footer. Match the density of the surrounding comments.
9. **Edit the live Plugins folder**, never a git worktree: SketchUp only loads the live folder.
10. **Reload Plugin Data uses `load`.** Methods and constants deleted from the source survive until SketchUp restarts. Replace an override explicitly, or ask the user to restart.
11. **CRLF files.** Some files may have Windows line endings, which break exact-match edit tools. Patch those with a small Python script (read, `replace`, write), never a shell heredoc.
12. **Keep the user's models safe.** Don't commit, push, or change the user's MCP client configs unless asked.

## Adding or Changing a Tool

1. Registry (`02__Plugin__CoreAppData/Na__SketchUpMcp__CoreAppData__ToolRegistry__.json`): add name, title, `runs_on`, `handler_key`, `mutates`, `operation`, `timeout_s`, annotations, the `api` list, description and `input_schema`. Add it to `toolsets.core` only if a small client really needs it.
2. Handler: add a public `Na__Handlers__<Family>__<Action>(params, ctx)` in `10__BridgeHandlers/`.
   - Read parameters only through `Na__Params`, lengths through `Na__Units`, ids through `Na__EntityResolver`, and parents through `Na__Creation__Prepare` or `Na__Coordinates__ResolveContainer`.
   - Return world coordinates in `ctx[:unit]`.
   - Push notes for the agent onto `ctx[:warnings]`.
3. Route: add it to `NA_HANDLER_ROUTES` in `04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__CommandRouter__.rb`. A new file also needs its `require_relative` in the CoreAppLoaders main file.
4. Run the five commands above.
5. In SketchUp use **Extensions > Na SketchUp MCP > Reload Plugin Data**, then restart the MCP server. A running server notices a changed registry file and sends `notifications/tools/list_changed`.
6. Live test (below), then add a devlog entry.

## The Component Library Seam (asset_library, asset_library_edit)

- **Where the rules live.** Both tools are thin. `10__BridgeHandlers/Na__SketchUpMcp__Handlers__AssetLibrary__.rb` resolves the component to save and forwards everything else to Adam's Component Editor Tools. That module is `../Na__Noble3dModellingTools__Modules__/10__PluginModules/21__SourceCode__ComponentEditorTools/12__McpOperations`, and its entry point is `Na__ComponentEditorTools::Na__McpOperations.Na__ComponentEditorTools__McpRead` / `...McpEdit`.
- **Its refusals.** `Na__McpOperationsError` carries a code, message, hint and details, and the handler turns it into `Na__McpError`. If that plugin is not loaded, both tools refuse with `unsupported`.
- **The convention** (names, codes, taxonomy defaults, the archive date suffix) lives in `07__UserData/Na__ComponentEditorTools__LibraryConvention__.json`, not in code.
- **Undo.** The library code opens files inside its own operation, which it always aborts. So `asset_library` does not mutate, `asset_library_edit` has `"operation": false`, and both are in `NA_BATCH_FORBIDDEN`.
- **Validation.** `ValidateApiUsage` counts every def in that module as defined, and checks the `12__McpOperations` files and the library SafeLoad like the bridge itself. The seam's own suite runs with SketchUp's Ruby:
  ```bash
  python 40__Tests__Validation/Na__SketchUpMcp__Tests__RunRubyChecks__.py ../Na__Noble3dModellingTools__Modules__/10__PluginModules/21__SourceCode__ComponentEditorTools/tests/mcp_operations_unit.rb.test
  ```
- **Reloading.** A change to the seam needs Reload Plugin Data in Na Noble3d Modelling Tools (the Component Editor dialog's Settings, or the main plugin), as well as in this plugin.

## The Element Assembly Studio Seam (entity_studio, entity_studio_edit)

- **Where the rules live.** Both tools are thin, like the library seam. `10__BridgeHandlers/Na__SketchUpMcp__Handlers__EntityStudio__.rb` resolves what the call names (`instance_id`, a wall by `wall_id` / `path` with its reported-to-world transform, `opening`, `run`, `position`, `direction`, `outside`) and forwards to Adam's Element Assembly Studio Pro 2.6.0 (also called Entity Studio Pro): `../Na__ArchTools__ElementAssemblyStudioPro__Modules__/02__Src__AppModules/60__System__McpOperations` (7 files: Main, Catalogue, Validation, SideEffects, Openings, Elements, Presets), entry points `Na__AssemblyStudio::Na__McpOperations.Na__AssemblyStudio__McpRead` / `...McpEdit`. It returns a placed element as `instance_object`; the handler swaps it for its id and world bounds.
- **One build path.** The seam calls the plugin's shared pipelines (`na_pipeline_*` in the WindowSystem DialogCallbacks, the InteriorDoorSystem and Cabinetry DialogRouters), which the dialog's own handlers call too. Never build through an engine directly from here: the pipeline adds the fuse, edge colour, name and save steps.
- **Settings.** Generated from the dialog's own control files into `02__AppData/Na__AssemblyStudio__ParameterCatalogue__.json` (`65__Dev__DevTools/...ParameterCatalogue__.js`, `--check`). Values are refused, never clamped. The dialog's JS-only rules have Ruby twins in the seam that name the JS they mirror.
- **Its refusals.** `Na__AssemblyStudio::Na__McpOperationsError` (code, message, hint, details) becomes `Na__McpError`. Without the plugin, both tools refuse with `unsupported`.
- **Undo.** The pipelines open and commit their own operation with the dialog's names, so `entity_studio_edit` has `"operation": false` and is in `NA_BATCH_FORBIDDEN`. `build` refuses inside an open group (a `dry_run` does not).
- **Test model.** `../Na__ArchTools__ElementAssemblyStudioPro__Modules__/65__Dev__DevTools/TestModels/Na__AssemblyStudio__McpTestbed__.skp`: open it in its own window (`sketchup_open_window`), never test in Adam's models.
- **Validation.** `ValidateApiUsage` counts every def under `02__Src__AppModules` as defined, and checks the `60__System__McpOperations` files like the bridge.
- **Reloading.** A change to the seam needs Element Assembly Studio's Reload Scripts (or `entity_studio_edit {action: "reload"}`) as well as this plugin's Reload Plugin Data.

## The Point Cloud Viewer Seam (point_cloud_state, point_cloud_clip, point_cloud_view, point_cloud_slice, point_cloud_fit, point_cloud_check, point_cloud_heightmap)

- **Where the rules live.** Every point cloud tool is thin. `10__BridgeHandlers/Na__SketchUpMcp__Handlers__PointCloud__.rb` reads the call's lengths into inches, turns `ids` into world bounds for `around`, picks the capture path for images and passes `per_inch`. Everything else is in Adam's Na Point Cloud Viewer: `../Na__PointCloudTools__PointCloudViewer__Modules__/02__Src__AppModules/95__System__McpOperations`, entry points `Na__PointCloudViewer::Na__McpOperations.Na__PointCloudViewer__McpRead` / `...McpEdit`. It multiplies every length it returns by `per_inch`, so results are in the call's units.
- **Its refusals.** `Na__PointCloudViewer::Na__McpOperationsError` (code, message, hint, details) becomes `Na__McpError`. Without the viewer (0.13.1 or newer), every one refuses with `unsupported`.
- **Undo.** The viewer writes a clip box in its own operation ("Point Cloud: ..."), so `point_cloud_clip` has `"operation": false`, reports `undo_step`, and is in `NA_BATCH_FORBIDDEN`. `point_cloud_view` changes view settings only (no model change, not undone by a rollback). `point_cloud_state` and `point_cloud_slice` do not mutate.
- **The engine.** Counts use `napc_box_count`, images `napc_render_png`; histograms, density images and points use the ABI 9 calls `napc_box_grid` and `napc_box_points` (viewer 0.14.0, ARCHITECTURE section 29), one pass over the cloud whatever the bins or pixels. With a viewer before 0.14.0, `points` and `density` refuse with `unsupported`.
- **Overlays (1.0.13, viewer 0.14.1).** `point_cloud_slice overlay_ids`: the handler collects world edge segments (through `Na__Serializer` / `Na__Coordinates`, soft and hidden edges left out) and the seam draws them in red. `view_capture include_point_cloud`: after `write_image`, with the capture's camera still set, the seam's `composite` draws the clouds on show over the file in place (the live overlay's camera maths; SketchUp keeps the vertical field of view for any image shape). A composite problem is a warning, never a failed capture.
- **Fitting (1.0.14, viewer 0.14.2).** `point_cloud_fit` reads lengths here and calls the seam's `fit`, which takes an even sample of the box from `napc_box_points` and fits it in pure Ruby (`95__System__McpOperations/Na__PointCloudViewer__McpOperations__Fit__.rb`: RANSAC, then least squares on the inliers). Its own suite: `tests/mcp_fit_unit.rb.test`.
- **Checking (1.0.15, viewer 0.14.3).** `point_cloud_check` turns every visible face under `ids` into world triangles (`Face#mesh`, `Na__Serializer__ToWorld`, the face's world normal), each labelled with its part (a group or component directly inside an id), and the seam's `check` measures an even sample of the cloud against them (`...McpOperations__Check__.rb`: a grid of cells `reach` wide; suite `tests/mcp_check_unit.rb.test`).
- **Heights (1.0.16, viewer 0.14.4).** `point_cloud_heightmap` reads lengths, the path and file names here (`na_save_path`, `na_image_path`; a grid-only key on a profile, or the reverse, is refused before the viewer is asked) and calls the seam's `heightmap` or `profile`, which bin an even sample of the box (a profile reads one box per piece of its path) in pure Ruby (`...McpOperations__Height__.rb`: a counting sort, percentiles by pc_terrain.py's rank rule, its rasters.npz layout for files; suite `tests/mcp_height_unit.rb.test`).
- **A parameter added to an existing tool (1.0.19).** List it in the registry's top-level `property_since` (`"tool.parameter": "x.y.z"`, the bridge version that reads it). A window not yet reloaded would ignore it and answer as if it were not there; the server pings that window's bridge before such a call and refuses it with the fix (Reload Plugin Data).
- **Angled slices (1.0.19, viewer 0.14.6).** `frame` on `point_cloud_slice` and `point_cloud_heightmap`: `na_frame` turns the origin into inches and an `id` into that group's world origin and axes (`Na__Serializer__ToWorld`); the seam folds the frame into the cloud's transform (`...McpOperations__Frame__.rb`), so the engine needs no change. It refuses `unsupported` unless the viewer lists 'frame' in `NA_FEATURES`.
- **Review rules (1.0.17, viewer 0.14.5).**
  - A key sent as `null` is not given: read presence with `Na__Params__Has`, never `params.key?`.
  - What the check and the overlays measure or draw is what SketchUp shows (`na_shown?`: not hidden, tag and tag folders on; `na_walk_shown` never enters a hidden group).
  - A capture's `save_path` must carry the image's extension (`na_capture_path`).
  - The composite follows a scene the call activated only outside an MCP operation (`ctx[:in_operation]`).
- **Validation.** `ValidateApiUsage` counts every def and `attr_*` accessor in the viewer's modules as defined, and checks the seam like the bridge. The seam's own suite runs with SketchUp's Ruby:
  ```bash
  python 40__Tests__Validation/Na__SketchUpMcp__Tests__RunRubyChecks__.py ../Na__PointCloudTools__PointCloudViewer__Modules__/02__Src__AppModules/95__System__McpOperations/tests/mcp_operations_unit.rb.test
  ```
- **Reloading.** A change to the seam needs the viewer's Reload Plugin (Settings) as well as this plugin's Reload Plugin Data.

## The TrueVision GLB Builder Seam (truevision_export, truevision_export_edit, truevision_publish)

- **Where the rules live.** All three tools are thin. `10__BridgeHandlers/Na__SketchUpMcp__Handlers__TrueVisionExport__.rb` checks the action, drops keys sent as `null` and forwards to Adam's TrueVision GLB Builder: `../Na__TrueVision__GlbBuilderUtility__Modules__/07__Plugin__McpOperations` (2.14.0), entry points `TrueVision3D::GlbBuilderUtility::Na__McpOperations.Na__GlbBuilder__McpRead` / `...McpEdit` / `...McpPublish`, and `Na__GlbBuilder__McpActions` for the action lists. The registry's `action` enums, the handler's constants and that list must stay the same, one for one (a BridgeCore check compares all three).
- **Its refusals.** `TrueVision3D::GlbBuilderUtility::Na__McpOperationsError` (code, message, hint, details) becomes `Na__McpError`. Without the GLB Builder 2.14.0, every one refuses with `unsupported`.
- **The split is the safety.** `truevision_export` only reads (`fetch_r2` starts a job that lists R2 and changes nothing there). `truevision_export_edit` changes this model and this computer's files. `truevision_publish` reaches the live site: every action but `push_dry_run` needs `confirm` = the linked project's code, and so does every deletion in the edit tool. Never pass `confirm` unless the user asked for exactly that push, purge or deletion.
- **What it reuses.** The tab actions run the dialog's own handlers, handed `Na__McpDialog`, which records the status lines, reports and R2 reports they push and passes every script on to the real dialog when it is open. So a rule changed in the GLB Builder changes here too.
- **Undo.** Edit and publish have `"operation": false`: the seam opens one "TrueVision: ..." step per model setting (aborted when the handler ends on an error or warning), and the Scene Sync and point cloud settings open their own. Both tools are in `NA_BATCH_FORBIDDEN`.
- **Jobs.** Pushes, the dry run, R2 fetch and purge, and point cloud renders run as the GLB Builder's CloudJob, a Fiber resumed by a UI timer. The call answers at once; `truevision_export {action: "job"}` follows it. Never block inside SketchUp waiting for one: the bridge runs on the same thread, so the job would never move.
- **No message boxes.** A modal stops the bridge. The seam takes folders as parameters and calls three keywords added for it, each defaulting to the dialog's behaviour: `Na__UserInterface__BuildModelStatus(prune:)`, `Na__SitePlan__Write(on_stale:)` and `Na__DynamicReloader__ReloadAllScripts(quiet:)`.
- **Child processes.** Inside SketchUp 2026 a child's stdout never arrives (`Open3.capture3` or a file redirect), so anything that must read a child's answer has the child write a file (the seam's `python` check does).
- **Validation.** `ValidateApiUsage` counts every def in the GLB Builder (its `00__ArchivedVersions` left out) as defined, and checks the `07__Plugin__McpOperations` files like the bridge. BridgeCore loads the real seam beside this plugin for its checks.
- **Reloading.** A change to the seam needs the GLB Builder's Reload Scripts (or `truevision_export_edit {action: "reload"}`) as well as this plugin's Reload Plugin Data.

## The Agent Outliner Seam (agent_outliner, agent_outliner_edit)

- **Where the rules live.** Both tools are thin. `10__BridgeHandlers/Na__SketchUpMcp__Handlers__AgentOutliner__.rb` checks the action, drops keys sent as `null`, hands over the open model (`model_object`) and forwards to Adam's Agent Outliner (Na Noble3d Modelling Tools): `../Na__Noble3dModellingTools__Modules__/10__PluginModules/36__SourceCode__AgentOutliner/06__McpOperations`, entry points `Na__AgentOutliner::Na__McpOperations.Na__AgentOutliner__McpRead` / `...McpEdit`, and `Na__AgentOutliner__McpActions` for the action lists. The registry's `action` enums, the handler's constants and that list must stay the same, one for one (BridgeCore compares all three).
- **Its refusals.** `Na__AgentOutliner::Na__McpOperationsError` (code, message, hint, details) becomes `Na__McpError`. Without the Agent Outliner both tools refuse with `unsupported`.
- **What it reads.** Flags and comment threads live on each object in the dictionary `Na__AgentOutliner__Notes` (and on the model for its own thread); change history and what has been read live beside the model on this PC (`91__UserConfig__LocalOnly/ModelHistory`), never in it. The Outliner tells an agent's changes from Adam's by this plugin's files on the Ruby call stack (`engine.agent_stack_markers` in its AppConfig): keep request handling synchronous, or the change reads as Adam's.
- **Undo.** `agent_outliner_edit` has `"operation": false`: the seam opens one "MCP: Agent Outliner Edit" step only when it writes the model (a comment, flag, status, name or strip) and reports it as `undo`; `acknowledge` writes nothing into the model. The edit tool is in `NA_BATCH_FORBIDDEN`, and like every `mutates` tool it is refused in read-only mode, `acknowledge` included.
- **Validation.** `ValidateApiUsage` counts every def in the Agent Outliner as defined and checks its `06__McpOperations` files like the bridge. The Agent Outliner's own offline suite (doubles, mutation runner) is described in its DEVLOG.
- **Reloading.** A change to the seam needs the Agent Outliner's Reload Plugin Data (its Settings tab) or Noble 3D Tools' own, as well as this plugin's. The seam's action lists are replaced on every load (`remove_const`, then assign): never guard them with `unless defined?`, or a reload keeps the old list until a restart.
- **The waiting notice (1.0.28, Agent Outliner 0.1.9).** It is not a tool. `CommandRouter.na_with_notice` asks `Na__Handlers__AgentOutliner__Notice(model)` after every tool, error paths included, and never for `ping` or `api_probe`. That forwards to the seam's `Na__AgentOutliner__McpNotice`, and the answer goes on the response as `outliner`. The ToolRunner puts it first in the result JSON, or as an error's last line `Outliner: {...}`.
  - The seam caches it per model against `Na__Notes__Revision` (moved by every note write, an acknowledge, undo, redo, an abort, the standards saved), the tracker's notes digests and the counted objects' `valid?`. A call costs microseconds; never add a scan to it.
  - nil when nothing waits, when the seam is older than 0.1.9, or on any fault. A notice must never fail a call.
  - **Older servers (1.0.29).** A server before 1.0.28 drops the `outliner` key. So the server says it shows the notice itself, with `features: ["outliner"]` in every request (`BridgeClient`). For a request without it, the router also adds `Na__Handlers__AgentOutliner__NoticeLine` to `warnings` (or the notice to an error's `details`). Sessions started before an update then hear Adam as soon as the window's bridge is reloaded. Keep the `features` key on every request.
  - **Idle sessions** are not reached by any of this: an MCP server cannot wake a session that is not calling it. The 3D skill's `scripts/outliner_watch.py`, left running in the background, is what wakes them. It keeps `ModelHistory/Watch__<pid>.json` heartbeats, which the Agent Outliner's Send line counts.
- **Agents' pictures (1.0.28, Agent Outliner 0.1.9).** `images` on comment / reply are copied into `91__UserConfig__LocalOnly/ChatFromAgents` as `agt_...`, apart from Adam's pasted `ChatCache/img_...`. `Na__Chat__Path` picks the folder by the prefix.
- **A new action is a new value, not a new parameter** (1.0.23: `flags`, `threads`, `strip`). Add it to the registry enum, the handler's list and the seam's list, and to `property_since` as `"agent_outliner.action=<value>"`, so a window that has not reloaded is refused with "Reload Plugin Data" instead of a bare "unknown action".
- **Paths on Windows.** The Agent Outliner's local data sits about 195 characters deep, and SketchUp's Ruby cannot open a path of 260 or more (`Errno::ENOENT`). Keep any file name it writes short (its history files are `History__<20 characters>__<crc>.json`).

## The Profile Path Tracer Seam (profile_tracer, profile_tracer_edit, profile_tracer_library)

- **Where the rules live.** All three tools are thin. `10__BridgeHandlers/Na__SketchUpMcp__Handlers__ProfileTracer__.rb` checks the action, drops keys sent as `null`, resolves `path` (world points, one run or several), `path_edge_ids` (world segments; a curve's edge brings the whole curve, a group its own edges), `parent_id` (`Na__Coordinates__ResolveContainer`), `wrapper.origin` and `profile_face_id`, and hands over the model, `per_inch` and two resolvers, `world_of` (an instance's definition coordinates to world) and `path_of`. Everything else is in Adam's Na Profile Path Tracer (1.6.17): `../Na__ProfileTools__ProfilePathTracer__Modules__/02__Src__AppModules/60__System__McpOperations`, entry points `Na__ProfileTools__ProfilePathTracer::Na__McpOperations.Na__ProfileTracer__McpRead` / `...McpEdit` / `...McpLibrary`, and `Na__ProfileTracer__McpActions` for the action lists (read, edit, library, edit_no_undo). The registry's enums, the handler's constants and that list must stay the same, one for one (BridgeCore compares all three).
- **Its refusals.** `Na__ProfileTools__ProfilePathTracer::Na__McpOperationsError` (code, message, hint, details) becomes `Na__McpError`. Without the tracer every tool refuses with `unsupported`.
- **Undo, and batches.** `profile_tracer_edit` has `"operation": false` and opens "MCP: Profile Tracer Edit (<action>)" itself with `Na__CommandRouter__WithOperation`, so inside `batch_execute` it joins the batch's step. That works because the tracer's engines take `wrap_in_operation: false` (1.6.17: the build, the rebuild, the swap, the local-profile writers) and the seam never opens an operation. `open_dialog` and `reload` change no model and open no step; `reload` is refused inside a batch. `profile_tracer_library` writes files, not the model: it is in `NA_BATCH_FORBIDDEN`, and `overwrite` / `delete` need `confirm` = the key.
- **The coordinate rule.** A trace's parent space is world space as built. Built into a closed container it is pinned with that container's reported-to-world inverted (`parent_transformation:`), so it is what the dialog would make with the container open; reverse puts the flip on top of the pin. Read back, world = `world_of(trace)` x stored point.
- **Edge colours.** The sweep paints Adam's MTE edge materials from the tracer's registry, which used to load only when its dialog opened. The seam calls `Na__EdgeColours__EnsureLoaded` (the local DataLib cache, no download) before every sweep; without it the sweep falls back to raw `Na__ProfileEdge__<hex>` materials.
- **Validation.** `ValidateApiUsage` counts every def under the tracer's `02__Src__AppModules` as defined and checks the `60__System__McpOperations` files like the bridge. BridgeCore loads the real seam and runs its pure maths (edge chaining, stretch, scale).
- **Reloading.** A change to the seam needs the tracer's Reload Plugin Files (Settings tab, or `profile_tracer_edit {action: "reload"}`) as well as this plugin's Reload Plugin Data. Its action lists are replaced on every load (`remove_const`, then assign).

## The Sketch and Site Tools (1.0.30: sketch_read, input_pick, proposal_preview, geometry_offset_band, model_snapshot, model_diff, image_rectify)

- **Why.** Corrett 64610 (12-Nov-2026): an agent turned a drone photo into a planting bed in three rounds; Adam redrew it in twelve minutes as plain parallel offsets of his terrace edge. These tools let him give intent fast and let an agent build a rule in one call. The rule they serve: precise inputs (CAD, drawings, orthophotos, scans, the model) are matched exactly; a site photo is only a reference, and the agent asks.
- **Where the rules live.** All plan maths is pure Ruby on plain arrays in `06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__PlanGeometry__.rb` (`Na__PlanGeometry`): chaining, line and arc fitting (with Adam's segment budget), parallel offsets (mitred, radial on arcs), end caps and insets, band outlines, a Hartley-normalised homography, polygon clipping, footprint overlap by scanline and outline distance. It has no SketchUp API, so `Tests__BridgeCore` checks it offline. The handlers are `Handlers__SketchIntake` (sketch_read, input_pick, proposal_preview), `Handlers__OffsetBand`, `Handlers__ModelDiff` and `Handlers__PhotoReference`.
- **Coordinates.** Edges are read to world through `Na__Serializer__ToWorld`; bands, proposals and photos go in through `Na__Creation` (world to reported) or at the root, pinned to the identity. Live 12-Nov-2026: the same bands built at the root and inside a moved, rotated, non-uniformly scaled group three deep had identical world vertices (404 of 404, 0.0 mm); a proposal drawn with a rotated group open landed on its world points. `Group#volume` is in the parent's units, so a band's reported volume is scaled by the container's determinant.
- **Waiting for Adam happens in the Python server.** `input_pick` and `proposal_preview` with `action: "wait"` are polled by `ToolRunner.na_wait` (short `result` / `status` calls every 0.5 s / 2 s) until he finishes, cancels or answers, an Agent Outliner notice arrives, or `wait_s` runs out. Never block in the bridge. The pick tool (`Na__PickTool`) is a plain SketchUp tool: InputPoint picks, red rubber band, Backspace, Enter or double-click, Esc; switching tools cancels it.
- **Undo.** sketch_read, input_pick, model_snapshot and model_diff never change the model. geometry_offset_band and image_rectify are one router step each. proposal_preview has `"operation": false`: its drawing and clearing open their own "MCP: Proposal Preview" step, and its question is the Agent Outliner's own step, so it cannot sit inside a batch. input_pick and proposal_preview are in `NA_BATCH_FORBIDDEN` (Ruby and Python).
- **image_rectify.** The photo becomes a material; `Face#position_material` with four pins gives SketchUp's projective mapping, checked live against the fit through a `UVHelper` (`mapping_check_px` 0.0 on the Corrett drone photo, 12 pairs). The face covers the image's footprint, kept clear of the horizon and cut to `region`. `path` is the image here, so it is kept away from `Na__Creation__Prepare` (which reads `path` as an instance path).
- **Test windows.** Live tests ran in copies opened with `sketchup_open_window copy_to` (a Corrett copy and a blank template) and closed afterwards. A question posted from a proposal copies its picture into the Agent Outliner's `ChatFromAgents`: test the `ask` route in a blank model and delete the test picture.

## Live Testing Without Leaving a Trace
- The user's SketchUp is live and may hold paid work. Only read, or use **zero-trace batches**. Never save, open or close their models.
- **Zero-trace batch.**
  - Send `batch_execute` with `rollback: true` (bridge 1.0.5+). Every step runs and its result comes back in `result.steps`, then the whole batch is rolled back. The activity log records it as `ok - Trial: ...`, so the user does not read it as an error.
  - Bridges before 1.0.5 ignore `rollback`, and the batch would be kept. Check `bridge_version` with `ping` first. For an older bridge, end the atomic batch with a step that always fails, e.g. `{"tool": "entity_get", "arguments": {"ids": [987654321]}}`; the results then come back in `error.details.steps`, and the log shows FAILED.
  - Camera changes and scene activation are **not** undone: note the view first and restore it.
- **A trial's abort can catch someone else's change** (1.0.24, Brown 60795). `abort_operation` ends whatever SketchUp has open, so a trial run while Adam is mid-edit, or straight after another session's `transaction: false` Ruby, may take their change with it: the Agent Outliner logged a trial's abort against lantern parts it never touched. Before a trial in a window others are using, check `agent_outliner {action: "changes"}` for the last minutes; prefer a throwaway window.
- **Coordinate test matrix.** A box inside a group that is moved **and** rotated, nested three deep, plus one non-uniformly scaled group. Compare the reported world positions and volumes against hand calculations.
- **Hand it over.** Final in-app checks go to the user as a short checklist in the devlog entry. Don't spend long verifying inside SketchUp yourself.

## Devlog

`Na__SketchUpMcp__DEVLOG__.md`: newest entry first. Each entry's heading is `## Na SketchUp MCP | Version x.y.z - DD-Mon-YYYY - Title`, followed by bullets, then a `### Validation Checklist`.
- Bump the **patch** number only (`1.0.1`, `1.0.2`, ...), and keep `bridge_version` in AppConfig and `server.version` in the registry in step.
- Read the top of the devlog and `git status` immediately before adding a version, because another session may have added one.

## Reference

- SketchUp Ruby API: https://ruby.sketchup.com (index source: https://github.com/SketchUp/ruby-api-stubs, MIT).
- To rebuild the API index after a SketchUp release: `git clone --depth 1 https://github.com/SketchUp/ruby-api-stubs.git <dir>`, then `python 80__DevTools__ApiIndexBuilder/Na__SketchUpMcp__ApiIndexBuilder__.py --stubs <dir>`, then rerun `ValidateApiUsage`.
- MCP specification: https://modelcontextprotocol.io/specification. The server supports 2024-11-05 to 2025-11-25 and 2026-07-28.
