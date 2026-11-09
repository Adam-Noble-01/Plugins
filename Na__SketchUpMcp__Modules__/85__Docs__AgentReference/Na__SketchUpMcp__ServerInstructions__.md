Live SketchUp 2026 model. Start with sketchup_status. Lengths are mm unless a call passes units; angles degrees; ids are persistent ids (entity_query, outliner_tree, selection_get). Positions are world coordinates at any nesting depth. Each model change is one undo step "MCP: ..." (model_undo reverts it). Check modelling with view_capture.

Inspect -> plan -> act -> verify (geometry_measure, view_capture). Multi-step builds: batch_execute, one undo step, "$0.id" references.
Name what you create as the user would ("Wall - North", in the model's style): they find work by name in the Outliner. New geometry gets its own group. Face normals follow the right-hand rule; a positive extrude goes along the normal.
Editing inside a component changes every copy: make_unique first if only one should change.
solid_boolean: SketchUp Pro, manifold groups with one parent; subtract keeps target_id.
Before ruby_eval, check every method with ruby_api_lookup; never invent API. In ruby_eval lengths are inches (2400.mm), angles radians.
Point clouds show in view_capture only with include_point_cloud: true; nothing snaps to them. Measure with point_cloud_slice, point_cloud_fit, point_cloud_heightmap; grade with point_cloud_check. point_cloud_clip changes the model: clip only when asked, then restore the user's clip scene.
Other models: sketchup_open_window (copy_to: a copy), then sketchup_close_window. entity_reparent moves objects into groups. TrueVision: truevision_structure (the model as exported), truevision_export (GLB Builder state, jobs); truevision_publish goes live: only when asked.
Library (asset_library, asset_library_edit): check next_code and check_name; agree names with the user before saving; revert undoes journaled changes.
Never overwrite files, discard unsaved work or delete what the user did not ask for. Read-only bridge: report it, never work round it.
Errors say what to fix: read the hint, change the call. A timed-out change is never retried: check with entity_query first.
Guide: resource sketchup://guide/agent.
