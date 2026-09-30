---
name: sketchup-modelling
description: Model, inspect, edit, paint, tag, present and capture the live SketchUp model through the Na SketchUp MCP server (tools named sketchup_status, entity_query, geometry_create_solid, batch_execute, view_capture and similar). Use whenever the user asks to look at, build, change, measure or tidy something in SketchUp, or to make scenes and images of their model.
---

# SketchUp Modelling Through Na SketchUp MCP

These tools drive the SketchUp 2026 window open on the user's PC. The user sees each change happen, and each change is one undo step named `MCP: ...`.

## Always

1. **Start with `sketchup_status`.**
   - If more than one SketchUp window is listed under `instances`, pick the right one with `select_pid`.
   - If it says not connected, tell the user how to fix it; do not retry in a loop.
2. **Units and ids.** Lengths are mm unless you pass `units`. Angles are degrees. Ids are persistent ids that the tools return.
3. **Coordinates are world coordinates everywhere**, including inside nested, rotated, scaled or open groups. Never convert them yourself.
4. **Look before and after.**
   - Before a change, inspect with `outliner_tree`, `entity_query` and `view_capture`.
   - After it, verify with `geometry_measure` and `view_capture`.
   - Describe only what you have seen.
5. **Batch multi-step builds** with `batch_execute`: one round trip and one undo step. Use `"$0.id"` to reference an earlier step's result.
6. **Name everything you create.** Pass `name` on every create call, using what the user would call it and the naming style already in the model's Outliner. It is how they find your work. The bridge only falls back to kind and size ("Box 1200 x 600 x 150").
7. **Only change what was asked.**
   - Never overwrite files, discard unsaved work, purge, explode or delete unless the user asked.
   - Read-only mode and a disabled Ruby eval are the user's choice: report them, don't work round them.
8. **Errors say what to fix.** Change the call as the hint says rather than repeating it. After a timeout, check the model before trying again.

## Choosing Tools

| To... | Use |
|---|---|
| Find things | `entity_query` (filters: types, name, tag, material, attribute; paged), `outliner_tree`, `collection_list` |
| Read details | `entity_get`, `geometry_measure` (bounds, area, volume, length, ray tests) |
| Make solids | `geometry_create_solid`: box, cylinder, cone, sphere, hemisphere, prism, pyramid, tube, torus |
| Draw | `geometry_draw` (line, polyline, rectangle, circle, arc, polygon, face with holes, optional extrude); `geometry_create_mesh`; `geometry_extrude` (push/pull, Follow Me) |
| Move or copy | `entity_transform` (translate, move_to, rotate, scale, mirror; `copies` for arrays) |
| Cut or join | `solid_boolean`, which needs Pro. `subtract` keeps `target_id` and removes `tool_ids`; the result has a new id |
| Organise | `group_create`, `component_place`, `component_manage`, `entity_set_properties`, `tag_manage`, `attributes_set` |
| Paint | `material_manage` (colours, textures, PBR), `material_apply` (`"#RRGGBB"` works directly) |
| Present | `scene_manage`, `view_set`, `section_plane`, `annotation_create`, `view_capture` |
| Component library | `asset_library` (overview, browse, get, next_code, check_name, audit) and `asset_library_edit` (save, rename, move, update, archive, apply_plan, revert). They need Na Noble3d Modelling Tools. Agree names with the user, and never call them inside a batch |
| Anything else | `ruby_api_lookup` first (never invent API), then `ruby_eval`. Inside eval, lengths are inches (`1200.mm`) and angles radians (`45.degrees`) |

## Pitfalls

- **Shared components.** Editing a component's contents changes every copy. Use `make_unique` when only one should change.
- **Face direction.** Points counter-clockwise from above give an up-facing face, so a positive extrude goes up.
- **Open groups.** `selection_set` and `group_create` only work on entities in the active context: the open group, or the model root when no group is open. Use `context_set` to open and close groups. Other tools take ids at any depth.
- **Captures cost tokens.** Use about 800×500 for checks and larger only for final images.

## Full Reference

Read the MCP resource `sketchup://guide/agent` for the full guide: recipes, the complete tool map, error codes and Ruby rules. On the user's PC it is at `%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins\Na__SketchUpMcp__Modules__\85__Docs__AgentReference\Na__SketchUpMcp__AgentGuide__.md`.
