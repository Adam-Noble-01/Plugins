# Na Noble3d Modelling Tools - Orient Faces Toward Camera - Development Log
# =============================================================================
# Module : 33__SourceCode__OrientFacesTowardCamera
# Plugin : Na Noble3d Modelling Tools
# Tab    : Geometry Tools > Face Orientation

## Overview

One-click command that reverses every selected face whose front currently points
away from the active camera. Directly selected faces, groups, and component
instances are accepted. Nested containers are walked, shared definitions are
uniquified only when a reverse is required, and locked containers are skipped.

Parent entry: main devlog **Version 0.9.1** (15-Sep-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================


## Version 1.0.0 - 15-Sep-2026 - Initial Build

### Update 01 - Module Structure
- New Pattern A one-shot module at `10__PluginModules/33__SourceCode__OrientFacesTowardCamera/` with a 4-file split:
  - `Na__Noble3dModellingTools__OrientFacesTowardCamera__Loader__.rb` — requires siblings in dependency order.
  - `Na__Noble3dModellingTools__OrientFacesTowardCamera__Orient__.rb` — world-normal transform, camera alignment, `Face#reverse!`.
  - `Na__Noble3dModellingTools__OrientFacesTowardCamera__Traversal__.rb` — recursive selection walk with accumulated world transforms, locked-container skipping, bounded depth/cycle guards, mutation preflight, and active-edit-context isolation.
  - `Na__Noble3dModellingTools__OrientFacesTowardCamera__Run__.rb` — public entrypoint, one undoable operation, status text, and result messaging.

### Update 02 - Camera Alignment Rule
- Parallel projection uses the reverse of `Camera#direction` so a 2D elevation/plan view orients every front toward the screen.
- Perspective uses the vector from a face vertex toward `Camera#eye`, so wide-FOV views reverse only faces that actually turn their back on the eye.
- Faces already facing the camera are left alone. Faces edge-on to the view (dot product near zero) are left alone and counted separately.

### Update 03 - Safe Nested Container Editing
- Locked groups/components are skipped and counted rather than aborting the whole command.
- Containers are uniquified with `make_unique` only when their branch actually has a face pointing away from the camera.
- Recursive walks cap at `NA_MAX_RECURSION_DEPTH = 64` and track definition identity to avoid cyclic-definition loops.
- World normals are derived by transforming a local point and a point offset along `Face#normal`, which stays correct under non-uniform scale and mirrored instances.

### Update 04 - Active Edit Context Isolation
- When the user is editing inside an open group/component (`model.active_path`), the active path is uniquified before mutation so changes do not leak to other placements of the same shared definition.
- Selected active-level entities are remapped after uniquification using short-lived attribute tokens on a feature-specific temporary dictionary.

### Validation Checklist
- [ ] Reload Plugin Data, then Geometry Tools > Face Orientation shows **Orient Faces Toward Camera**.
- [ ] Selecting the reversed (red) elevation faces in a parallel view turns them to the camera in one undo step.
- [ ] Selecting a group/component orients every nested face; unselected copies of a shared component stay unchanged.
- [ ] Faces already facing the camera are not reversed.
- [ ] Locked nested containers are skipped and reported.
- [ ] Editing inside an open group does not mutate other placements of the same definition.
- [ ] No-op runs abort cleanly without leaving an undo entry.
