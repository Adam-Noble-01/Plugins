# Na Noble3d Modelling Tools - Select Similar Filter - Development Log
# =============================================================================

## Version 0.6.0 - 10-Jul-2026 - Groups & Components Mode

### Update 01 - New Mode: Groups & Components
- Added a second dialog mode alongside Geometry: a `Geometry | Groups & Components` toggle row switches the dialog body between the existing Faces/Edges panel and a new Groups/Components panel, sharing one dialog shell, header, status banner, and Close/Run footer (Run button label and reference-line wording switch with the active mode).
- New file `Na__Noble3dModellingTools__SelectSimilarFilter__ContainerMatcher__.rb` holds all group/component matching and promotion logic, following the same one-file-per-concern split as `SimilarityMatcher__.rb`.

### Update 02 - Matching Strategy (Same Definition / Bounding Box, Independently Toggleable)
- Two independently toggleable match criteria, exactly like Geometry mode's Faces/Edges: **Same definition** (default on) matches repeated placements of the same component, or copies of the same group; **Bounding box** (default off) additionally matches differently-defined groups/components whose size falls within an mm threshold (default `0` — exact match; raised only to make matching more forgiving). Either or both can be active; at least one is required to run.
- The bounding-box signature uses each container's own *definition* bounds (its local, unrotated coordinate system, per the Ruby API's `Drawingelement#bounds` docs) scaled by the instance's axis scale factors — not the instance's parent-space bounds — then sorted into an `[a, b, c]` triple, so a rotated duplicate of the same group/component still produces an identical signature. This mirrors the sorted-edge-length approach already used for face matching.
- Axis scale is extracted by transforming the world unit axes (`X_AXIS`, `Y_AXIS`, `Z_AXIS`) through the instance's transformation and measuring the resulting vector lengths, rather than reading `Transformation#xaxis/yaxis/zaxis` directly — community references disagree on whether those are pre-normalized, so the unit-vector-transform approach is used since it is unambiguous.

### Update 03 - Deep Nested: Promote-to-Current-Level ("Cut and Paste in Place" at Depth)
- Added a **Deep Nested** toggle, Groups & Components mode only, default off. When enabled, the search additionally recurses into every nested group/component below the current editing level. Any nested match is promoted: a new instance of its definition is added directly to `model.active_entities` at the same current-level-relative transform it already occupied (so it does not visually move), its tag/material/shadow/name attributes are copied across, and the original nested placement is erased — the functional equivalent of cut-then-paste-in-place, applied at whatever depth the match was found.
- This is what lets the tool cumulatively select entities nested at different depths in a single pass, which native SketchUp selection cannot do (selection is always scoped to one open editing context at a time).
- The whole promotion pass runs inside one `model.start_operation`/`commit_operation` (aborting cleanly on error), so it is a single Undo step regardless of how many nested entities were promoted.
- Since the Ruby API has no `ComponentInstance#to_group` counterpart to the existing `Group#to_component`, a promoted Group is reconstructed via the standard workaround: add an instance of its definition, `explode` that single instance, and re-wrap the result in a new group — preserving Group-ness rather than silently turning promoted groups into components.
- If a promoted entity's immediate parent is a component definition used elsewhere in the model (`definition.instances.length > 1`), the result banner surfaces a note that the change applies to every placement of that component, exactly as manually editing into it and deleting something would — this is standard SketchUp behaviour, not a bug, but worth calling out since it is easy to miss.
- The currently open editing path (`model.active_path`) is explicitly excluded from the nested walk so the tool never tries to promote or erase an ancestor the user has open for editing.

### Update 04 - Live Reference Readout Extended to Both Modes
- `Na__SelectSimilarFilter__ReceiveReferenceSummary` now always carries both geometry counts (`face_count`, `edge_count`) and container counts (`group_count`, `component_count`) in one payload; the dialog's JS decides which line to render based on the active mode, so switching modes updates the reference line instantly without waiting for a new SketchUp selection event.

### Update 05 - Bug Fix: Groups Never Matched (Sibling-Class Trap)
- First build filtered candidates and reference seeds with `entity.is_a?(Sketchup::ComponentInstance)`, which silently excluded every `Sketchup::Group`. In the Ruby API `Sketchup::Group` is NOT a subclass of `Sketchup::ComponentInstance` — both are sibling subclasses of `Sketchup::Drawingelement` — so selecting groups (e.g. three identical solid-group cubes) produced "No similar groups/components found" every time, even with Bounding box enabled.
- Fixed with a single `na_container?(entity)` predicate (`is_a?(Sketchup::Group) || is_a?(Sketchup::ComponentInstance)`) used at every candidate/seed/nested-walk site. Both classes expose `#definition` and `#transformation`, which is all the matcher relies on.
- Note on "Same definition" with groups: separately drawn groups each get their own unique definition, so they only cross-match under **Bounding box**. Copies of one group (which share a definition until made unique) also match under Same definition.

### Validation Checklist
- [ ] Mode toggle switches the visible panel, subtitle, reference-line wording, and Run button label without closing/reopening the dialog.
- [ ] Groups & Components mode defaults: Same definition checked, Bounding box unchecked (threshold input disabled and reads `0`), Deep Nested unchecked.
- [ ] Selecting one instance of a component and clicking Select Similar (Same definition only) selects every other placement of that component at the current level.
- [ ] Two unique (differently-defined) groups of equal size are NOT selected together until Bounding box is enabled; raising the bounding-box threshold above `0` catches groups with slightly different sizes.
- [ ] A rotated duplicate of a matched group/component is still matched under Bounding box (rotation must not change the size signature).
- [ ] With Deep Nested off, matches nested inside sub-groups/components are never found or altered.
- [ ] With Deep Nested on, a match nested several levels deep is promoted to the current level, keeps its visual position, keeps its tag/material/shadow/name, and ends up selected alongside current-level matches — all as one Undo step.
- [ ] Promoting a nested Group produces a Group (not a Component) at the current level.
- [ ] Promoting a nested instance of a component used elsewhere in the model shows the "used elsewhere" note in the result banner.
- [ ] Hidden entities and entities on hidden tags are never matched, promoted, or selected, at any depth.
- [ ] Reload Plugin Data still closes an open Select Similar dialog cleanly and the tool re-opens correctly afterward.

## Version 0.5.8 - 08-Jul-2026 - Initial Build

### Update 01 - New Tool: Select Similar Filter
- New Pattern B sub-dialog tool for fast "select an array" workflows: select one or more reference faces/edges, open the dialog, and click **Select Similar** to select every other face/edge at the current editing level that matches shape and size within a configurable mm threshold.
- 5-file module split following the `UntagSpecificInSelection` pattern:
  - `Na__Noble3dModellingTools__SelectSimilarFilter__Loader__.rb`
  - `Na__Noble3dModellingTools__SelectSimilarFilter__SimilarityMatcher__.rb`
  - `Na__Noble3dModellingTools__SelectSimilarFilter__SelectionObserver__.rb`
  - `Na__Noble3dModellingTools__SelectSimilarFilter__DialogManager__.rb`
  - `Na__Noble3dModellingTools__SelectSimilarFilter__Run__.rb`

### Update 02 - Matching Strategy (Shape Signature, Not Area-Only)
- Faces are matched by an orientation-invariant shape signature: outer-loop vertex count, loop/hole count, sorted outer-edge lengths (each compared to the reference within the mm threshold), and a relative-area shear guard (`NA_AREA_RELATIVE_TOLERANCE = 0.15`) that rejects a sheared parallelogram sharing a rectangle's edge lengths.
- This intentionally replaces a simpler `sqrt(area)`-only comparison: area alone would incorrectly match same-area/different-shape faces (e.g. a `50x30` vs `75x20` face) and could miss genuinely similar panels that vary slightly in both width and height.
- Curved faces (circles/arcs, detected via `edge.curve` on the outer loop) fall back to an equivalent-side-length (`sqrt(area)`) compare, since edge-count comparison is not meaningful for tessellated curves.
- Edges are matched directly on `edge.length`, which is already orientation-invariant.
- Reference entities always match themselves trivially, so the entity the user selected as a seed is always included in the result.

### Update 03 - Local-Scope Only (No Cross-Container Leakage)
- Candidates are sourced exclusively from `model.active_entities`, which SketchUp already scopes to the entities of whichever group/component is currently open for editing (or the model root if nothing is open). No manual path-walking or recursion is needed — this guarantees the tool only ever searches and selects at the same nesting level as the reference selection.

### Update 04 - Live Reference Readout and Visibility Filtering
- A `Sketchup::SelectionObserver` subclass pushes a live "Reference: N face(s), M edge(s) selected" line to the dialog on every selection change, so the user can see what will be used as the match seed before clicking the button.
- Hidden entities and entities on hidden tags are excluded from candidates so results always match what is visible in the model.

### Update 05 - Hot-Reload Support
- Registered a `Na__SelectSimilarFilter__DialogManager__ResetDialog` hook in the shared `Na__ReloadManager` (mirroring the existing `Na__ImageCarousel__DialogManager__ResetDialog` precedent) so every **Reload Plugin Data** click closes any open Select Similar dialog and detaches its selection observer before the module files are reloaded — guaranteeing a clean dialog on the next open rather than a stale window bound to superseded Ruby closures.
- The existing `Na__ReloadManager` already globs and reloads every `.rb` file under the modules root, so iterating on the matching logic in `SimilarityMatcher__.rb` only requires a source edit and a Reload Plugin Data click — no SketchUp restart needed after the tool's first load.

### Validation Checklist
- [ ] Dialog opens from the Selection Tools tab, Extensions menu, and hotkey.
- [ ] Faces and Edges checkboxes default to checked; threshold input defaults to 10mm.
- [ ] Selecting one small rectangular panel and clicking Select Similar selects all same-size panels in an array, tolerant of small (~threshold) size variation.
- [ ] A face with the same area but a different aspect ratio is NOT selected.
- [ ] Running the tool while inside an open group/component only searches and selects within that container, never inside nested sub-groups/components or outside the container.
- [ ] Hidden entities and entities on hidden tags are never added to the result.
- [ ] Reference line updates live as the SketchUp selection changes while the dialog is open.
- [ ] Reload Plugin Data closes an open Select Similar dialog cleanly and the tool re-opens correctly afterward.
