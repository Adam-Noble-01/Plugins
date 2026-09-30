# Na SketchUp MCP - Development Log
# =============================================================================

## Version History

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
  - It uses the stacked-local-axes rule from Insert Primitives 5.1.2. `06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Coordinates__.rb` holds the one formula. New groups are pinned to identity, and push/pull distances are divided by the scale along the normal.
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
