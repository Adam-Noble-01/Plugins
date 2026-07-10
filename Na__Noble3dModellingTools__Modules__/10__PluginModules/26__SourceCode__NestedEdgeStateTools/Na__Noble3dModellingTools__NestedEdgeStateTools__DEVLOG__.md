# Na Noble3d Modelling Tools - Nested Edge State Tools - Development Log
# =============================================================================
# Module : 26__SourceCode__NestedEdgeStateTools
# Plugin : Na Noble3d Modelling Tools
# Tab    : Geometry Tools > Nested Edge State

## Overview

Four one-click commands that recursively update SketchUp edge properties inside the
current selection: **Hide**, **Unhide**, **Unsmooth**, and **Unsoften**. Each command
accepts directly selected edges, groups, and component instances, walks nested
containers, and reports changed/unchanged/skipped counts through the standard Noble
3D Tools `{ success:, message: }` result contract.

Parent entry: main devlog **Version 0.6.1** (10-Jul-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================


## Version 1.0.0 - 10-Jul-2026 - Initial Build

### Update 01 - Module Structure
- New Pattern A one-shot module at `10__PluginModules/26__SourceCode__NestedEdgeStateTools/` with a 4-file split:
  - `Na__Noble3dModellingTools__NestedEdgeStateTools__Loader__.rb` — requires siblings in dependency order.
  - `Na__Noble3dModellingTools__NestedEdgeStateTools__Mutator__.rb` — single responsibility: apply one requested edge property (`hidden=`, `smooth=`, `soft=`) and report `:changed` / `:unchanged`.
  - `Na__Noble3dModellingTools__NestedEdgeStateTools__Traversal__.rb` — recursive selection walk, locked-container skipping, bounded depth/cycle guards, mutation preflight, and active-edit-context isolation.
  - `Na__Noble3dModellingTools__NestedEdgeStateTools__Run__.rb` — four public entrypoints, one undoable operation per command, status text, and result messaging.

### Update 02 - Four Independent Edge Properties
- Refactored the original prototype script into four separate commands, each changing exactly one SketchUp edge property:
  - **Hide Nested Edges** — `edge.hidden = true`
  - **Unhide Nested Edges** — `edge.hidden = false`
  - **Unsmooth Nested Edges** — `edge.smooth = false`
  - **Unsoften Nested Edges** — `edge.soft = false`
- Soft, Smooth, and Hidden are treated as independent API properties (matching Entity Info and the SketchUp Ruby API docs), so unsmoothing does not implicitly unsoften and vice versa.

### Update 03 - Safe Nested Container Editing
- Locked groups/components are skipped and counted in the result message rather than aborting the whole command.
- Containers are uniquified with `make_unique` only when their branch actually requires a state change, preventing unnecessary definition splits.
- Recursive walks cap at `NA_MAX_RECURSION_DEPTH = 64` and track definition identity to avoid cyclic-definition loops.
- Unsupported top-level selection types (faces, dimensions, etc.) are ignored and reported without failing the command.

### Update 04 - Active Edit Context Isolation
- When the user is editing inside an open group/component (`model.active_path`), the active path is uniquified before mutation so changes do not leak to other placements of the same shared definition.
- Selected active-level entities are remapped after uniquification using short-lived attribute tokens on a feature-specific temporary dictionary; the dictionary is fully removed from both original and copied entities before the operation completes.

### Update 05 - Noble 3D Tools Integration
- Registered four commands, four Geometry Tools buttons (`Nested Edge State`, tool_group_order 45), and hotkey bindings in `Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`:
  - `hide_nested_edges`
  - `unhide_nested_edges`
  - `unsmooth_nested_edges`
  - `unsoften_nested_edges`
- Wired handlers in `Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`.
- Registered loader in `Na__Noble3dModellingTools__ModuleLoaders__Main__.rb` as slot 26.

### Validation Checklist
- [x] All four commands appear in Noble 3D Tools dialog under Geometry Tools > Nested Edge State.
- [x] All four commands appear in Extensions > Na__Noble3dModellingTools menu and are hotkey-bindable.
- [x] Selecting a group/component hides/unhides/unsmooths/unsoftens every nested edge inside it.
- [x] Directly selected edges are updated without requiring a container selection.
- [x] Locked nested containers are skipped and reported in the result message.
- [x] Copied/shared component instances outside the selected hierarchy are not changed.
- [x] Editing inside an open group/component does not mutate other placements of the same definition.
- [x] Each successful command is one Undo step; no-op runs abort cleanly without leaving an undo entry.
- [x] Reload Plugin Data loads the module without errors.
