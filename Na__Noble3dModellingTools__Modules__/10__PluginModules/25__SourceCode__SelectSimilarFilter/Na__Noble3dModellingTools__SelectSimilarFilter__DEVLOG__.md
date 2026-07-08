# Na Noble3d Modelling Tools - Select Similar Filter - Development Log
# =============================================================================

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
