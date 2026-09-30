# AGENTS.md - Na SketchUp MCP

These are instructions for AI coding agents working **on** this plugin: Codex / GPT, Claude Code, Cursor, Gemini, Copilot and others.
**To model in SketchUp through the server, read `85__Docs__AgentReference/Na__SketchUpMcp__AgentGuide__.md` instead.** The server also serves it as the MCP resource `sketchup://guide/agent`.

## What This Is

A local MCP server that lets any MCP client inspect and edit the model open in SketchUp 2026 on Windows. It has 44 tools, and every SketchUp API call it makes is checked against the official API index.

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

## Live Testing Without Leaving a Trace

- The user's SketchUp is live and may hold paid work. Only read, or use **zero-trace batches**. Never save, open or close their models.
- **Zero-trace batch.**
  - Send an atomic `batch_execute` whose last step always fails, e.g. `{"tool": "entity_get", "arguments": {"ids": [987654321]}}`.
  - Every step runs and its result comes back in `error.details.steps`, then the whole batch is rolled back.
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
