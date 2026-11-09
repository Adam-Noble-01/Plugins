# AGENTS.md - Na SketchUp MCP

These are instructions for AI coding agents working **on** this plugin: Codex / GPT, Claude Code, Cursor, Gemini, Copilot and others.
**To model in SketchUp through the server, read `85__Docs__AgentReference/Na__SketchUpMcp__AgentGuide__.md` instead.** The server also serves it as the MCP resource `sketchup://guide/agent`.

## What This Is

A local MCP server that lets any MCP client inspect and edit the model open in SketchUp 2026 on Windows. It has 63 tools, and every SketchUp API call it makes is checked against the official API index.

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

- **Where the rules live.** Both tools are thin, like the library seam. `10__BridgeHandlers/Na__SketchUpMcp__Handlers__EntityStudio__.rb` resolves `instance_id` and `position` and forwards to Adam's Element Assembly Studio Pro (also called Entity Studio Pro): `../Na__ArchTools__ElementAssemblyStudioPro__Modules__/02__Src__AppModules/60__System__McpOperations`, entry points `Na__AssemblyStudio::Na__McpOperations.Na__AssemblyStudio__McpRead` / `...McpEdit`. It returns a placed element as `instance_object`; the handler swaps it for its id and world bounds.
- **Its refusals.** `Na__AssemblyStudio::Na__McpOperationsError` (code, message, hint, details) becomes `Na__McpError`. Without the plugin, both tools refuse with `unsupported`.
- **Undo.** The exterior door engines open and commit their own operation, so `entity_studio_edit` has `"operation": false` and is in `NA_BATCH_FORBIDDEN`. `build` refuses inside an open group, because the engines place at the model root.
- **What it reuses.** Builds go through each system's own `GeometryEngine`; presets through the Presets Store; gallery pictures through the open dialog's own SvgCapture and its existing `na_presetsUpdateConfig` callback.
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

## Live Testing Without Leaving a Trace

- The user's SketchUp is live and may hold paid work. Only read, or use **zero-trace batches**. Never save, open or close their models.
- **Zero-trace batch.**
  - Send `batch_execute` with `rollback: true` (bridge 1.0.5+). Every step runs and its result comes back in `result.steps`, then the whole batch is rolled back. The activity log records it as `ok - Trial: ...`, so the user does not read it as an error.
  - Bridges before 1.0.5 ignore `rollback`, and the batch would be kept. Check `bridge_version` with `ping` first. For an older bridge, end the atomic batch with a step that always fails, e.g. `{"tool": "entity_get", "arguments": {"ids": [987654321]}}`; the results then come back in `error.details.steps`, and the log shows FAILED.
  - Camera changes and scene activation are **not** undone: note the view first and restore it.
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
