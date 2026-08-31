# Na Noble3d Modelling Tools - Paint Deep Nested Faces - Development Log
# =============================================================================
# Module : 29__SourceCode__PaintDeepNestedFaces
# Plugin : Na Noble3d Modelling Tools
# Tab    : Material Utils > Face Painting

## Overview

The face counterpart to the standalone **Na Edge Util - Paint Deep Nested Edges**
plugin. Paints every face inside the current selection with the material held in
the SketchUp Materials tray, at any nesting depth, and never touches an edge.

Where the edge tool reads a fixed MTE palette out of the Noble SSOT DataLib, this
first iteration deliberately reads nothing but `Sketchup::Materials#current` — the
swatch the user last clicked. Library mode comes later (see *Planned*).

Parent entry: main devlog **Version 0.8.0** (30-Aug-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================


## Version 1.1.0 - 30-Aug-2026 - Default Material Strip Mode + Library Material Crash Guard

### Update 01 - The Default Material Is nil, Not a Named Material
Researched against the SketchUp Ruby API docs and the community threads. Findings:

- **SketchUp has no Material object and no name string for the Default swatch.**
  The API represents it as `nil` throughout: `Materials#current` returns `nil`
  when Default is picked, and `face.material = nil` *is* how the default gets
  applied. There is no `"[Default]"` lookup and nothing to fetch from
  `model.materials`.
- The bracketed-name quirk that looks like an under-the-hood default name is a
  different thing: library materials carry names such as `[Color A01]` in `#name`
  while `#display_name` strips the brackets. Unrelated to the default material.

So v1.0.0 was wrong to treat a nil current material as "nothing selected". It is
a first class choice, and it now arms the tool in **strip mode**.

### Update 02 - Strip Mode
- Default selected -> both sides cleared: `face.material = nil` and
  `face.back_material = nil`, through the same traversal and the same painter.
  Stripping deep nested faces is a mode, not a second tool.
- `back_face_rule` gains a third value, `strip_both`, alongside `paint_both` and
  `front_only`.
- The whole dialog switches verb with it: badge reads **Default**, the stat reads
  "faces to strip", the button reads "Strip 4,539 Faces", the status line reads
  "Stripping...", and the result reads "Stripped 4,539 faces back to the default
  material (front and back both cleared)."
- The Default swatch is drawn the way SketchUp draws it - the front face colour
  split diagonally against the back face colour, both read live from
  `model.rendering_options['FaceFrontColor']` and `['FaceBackColor']`, so it
  tracks the model style rather than being hardcoded white and blue-grey.

### Update 03 - Library Material Crash Guard (found during this research)
- `Materials#current` returns a material that is **not in the model** when the
  user clicks a swatch in a material library rather than In Model. Reading it is
  safe; **applying it to an entity BugSplats SketchUp.** v1.0.0 would have hit
  this the first time a library swatch was used.
- `MaterialProbe__IsInModel` now tests with `model.materials.include?`, with a
  name-lookup fallback, and the result rides in the payload as `in_model` so the
  dialog can say so before you press the button.
- `Run__.na_resolve_paintable_material` resolves inside the undo operation:
  in-model material used as is; same-named model material reused if present;
  otherwise the library material is copied into the model (name, colour, alpha,
  texture, and the texture resized back to the library size so scale survives).
  This is what SketchUp itself does when you paint with a library swatch.
- If the copy cannot be made — built-in textures can return a bare filename with
  no path — nothing is painted and the message says to paint one face with the
  Paint Bucket first, then run again. A clean refusal, never a silent
  colour-only approximation of a textured material.

### Validation Checklist
- [x] Ruby files pass the block-balance check; `UiBridge__.js` passes `node --check`.
- [x] Every payload key the JS reads is produced by the probe.
- [x] `Texture#size=` confirmed to accept `[width, height]` against the API docs.
- [ ] Default swatch selected shows the two-tone preview and "Strip N Faces".
- [ ] Stripping clears front *and* back on nested faces, in one undo step.
- [ ] Default swatch preview tracks a change to the model's face colours in styles.
- [ ] Clicking a library swatch shows the "not in the model yet" note.
- [ ] Painting with a library swatch copies it into In Model and does not crash.
- [ ] Library swatch whose texture cannot be found refuses cleanly with guidance.

### Status
**Written and statically verified; not yet exercised in SketchUp.** The API
behaviour above is from the official docs and community sources, not from a live
run on this machine.

## -----------------------------------------------------------------------------

## Version 1.0.0 - 30-Aug-2026 - Initial Build

### Update 01 - Module Structure
Pattern B dialog module at `10__PluginModules/29__SourceCode__PaintDeepNestedFaces/`,
split so no file approaches the 600 line ceiling:

| File | Lines | Responsibility |
|---|---:|---|
| `..._Loader__.rb` | 22 | Requires siblings in dependency order |
| `..._MaterialProbe__.rb` | 269 | Reads the active material, describes colour / opacity / name |
| `..._FaceCollector__.rb` | 296 | Selection walk, nesting rules, safety guards, statistics |
| `..._Painter__.rb` | 160 | Applies one material under the front / back face standard |
| `..._Observers__.rb` | 111 | MaterialsObserver + SelectionObserver |
| `..._DialogManager__.rb` | 463 | HtmlDialog, callbacks, observer lifecycle, payload push |
| `..._Run__.rb` | 262 | Public entrypoints, undo operation, result messaging |
| `..._UiLayout__.html` | 168 | Dialog shell |
| `..._Styles__.css` | 467 | Noble light theme |
| `..._UiBridge__.js` | 479 | Rendering and event wiring |

### Update 02 - Live Material Preview From the Materials Tray
- `Sketchup::Materials#current` is the single source of truth for "the material the
  user last selected in the Materials window".
- A `Sketchup::MaterialsObserver` keeps the preview live. `onMaterialSetCurrent`
  covers picking a new swatch; `onMaterialChange` covers editing the colour or
  opacity of the swatch already held, so dragging the opacity slider in the tray
  updates the dialog and its back face rule immediately.
- The docs warn that the `materials` argument of `onMaterialSetCurrent` can be nil
  when a swatch is picked straight from a library and is not yet in the model, and
  that the material handed to `onMaterialRemove` must not be touched. Both
  callbacks therefore ignore their arguments entirely and re-read from the model.
- Only colour, opacity and name are read. Textured materials report the flag and
  the texture filename, and the swatch shows the average texture colour with an
  honest caption rather than pretending to be a texture preview.
- The swatch is drawn over a checkerboard so alpha reads at a glance.

### Update 03 - Nesting Rules
- **Deep Nesting on (default)** — every face at every level below the selection.
- **Deep Nesting off** — the faces one level inside each selected container only.
  Nested containers below that are left completely alone and counted.
- Directly selected faces are always painted, in either mode.
- Edges are never routed anywhere near the painter, at any depth. That is the
  entire point of the tool and it is enforced by the `case` in `na_walk_entity`
  rather than by a filter that could be bypassed.

### Update 04 - Front and Back Face Standard
Driven by `Material#use_alpha?`, the API's own transparency test:

- **Opaque** — `face.material = mat`, `face.back_material = nil`. A clean back face
  keeps section fills, exports and renderers predictable, and leaves reversed
  geometry visible rather than hidden.
- **Transparent** — both sides painted, so glass reads correctly from either side.

The painter asks the MaterialProbe for the verdict, so the rule applied can never
drift from the rule previewed in the dialog.

### Update 05 - Safety and Honest Reporting
- Locked containers are skipped and counted, never raised on.
- Recursion caps at `NA_MAX_RECURSION_DEPTH = 64` with definition-identity cycle
  tracking.
- Faces are de-duplicated by `entityID`, so a definition reached through two
  instances is counted and painted once.
- **Shared definitions are reported before you press the button.** Painting inside
  a component with five placements changes all five — the dialog says so, with the
  count of other placements affected. Optional `Isolate shared components first`
  calls `make_unique` before descending; off by default, matching how SketchUp
  paints natively.
- The live preview walk is capped at `NA_PREVIEW_FACE_LIMIT = 25,000` faces so a
  select-all in a heavy model cannot stall the dialog. The cap is stated in the UI
  ("25,000+", plus a note) and applies only to the preview — painting is never
  capped.
- Observer callbacks never work inline. They set a flag and a zero-delay
  `UI.start_timer` picks the work up on the next main loop pass, which keeps the
  traversal out of the SketchUp observer stack and collapses a burst of
  `onSelectionAdded` calls into one update.
- The whole paint is a single `start_operation` / `commit_operation` pair with
  `abort_operation` on failure, so it is one undo step.

### Update 06 - Noble 3D Tools Integration
- Two commands and two Material Utils buttons (`Face Painting`, tool_group_order 30)
  in `Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json`:
  - `paint_deep_nested_faces` — opens the dialog.
  - `paint_deep_nested_faces_repeat` — one-click repeat with no dialog, using the
    active tray material and the saved nesting toggles. Bind this to a shortcut.
- Handlers wired in `Na__Noble3dModellingTools__PublicAPI__CommandRouter__.rb`.
- Loader registered in `Na__Noble3dModellingTools__ModuleLoaders__Main__.rb` as slot 29.
- `Na__PaintDeepNestedFaces__ResetDialog` registered in the ReloadManager, so a hot
  reload detaches both observers instead of orphaning them.
- Toggle state persists via `Sketchup.write_default`, so the dialog and the
  one-click command always agree.

### Namespace Note
An unrelated interactive click-to-paint prototype sits at the Plugins root as
`Na__PaintDeepNestedFaces__Main__.rb` (top-level `Na__PaintDeepNestedFaces`
module, March 2026). This module is `Na__Noble3dModellingTools::Na__PaintDeepNestedFaces`,
so the two do not collide — but the similar name is worth remembering.

### Validation Checklist
- [x] All Ruby files pass a block-balance check.
- [x] `UiBridge__.js` passes `node --check`.
- [x] Registry JSON parses; every button and hotkey binding resolves to a command.
- [x] Dialog HTML composes with both placeholders replaced.
- [ ] Dialog opens from Material Utils > Face Painting and previews the tray material.
- [ ] Swatch and back face rule follow a material change in the Materials tray live.
- [ ] Opaque material paints the front and strips the back on a nested selection.
- [ ] Transparent material paints both sides.
- [ ] Deep Nesting off paints one level only; nested containers counted as skipped.
- [ ] Edges are untouched at every depth.
- [ ] Locked containers are skipped and reported.
- [ ] Shared component warning matches the real placement count.
- [ ] `Isolate shared components first` leaves other placements unchanged.
- [ ] One undo step reverses the whole paint.
- [ ] `Paint Faces With Active Material` works from a keyboard shortcut.
- [ ] Reload Plugin Data closes the dialog and leaves no observers attached.

### Status
**Written and statically verified; not yet exercised in SketchUp.** No Ruby
interpreter is available on this machine, so the Ruby was checked structurally
rather than executed. Every unticked item above is in-SketchUp confirmation
still to do.


# =============================================================================
# PLANNED
# =============================================================================

## Library Mode (v1.1 candidate)
The architecture keeps the material source behind one seam: `MaterialProbe`
returns a payload, and nothing downstream knows where the material came from.
Library mode adds a second source alongside `Sketchup::Materials#current` — the
Noble SSOT palette, loaded the way the edge painter loads MTE colours via
`Na__DataLib__CacheData.Na__Cache__LoadData`. The dialog gains a source toggle and
a swatch grid; the collector, painter and back face standard are untouched.

## Other Candidates
- `Material#write_thumbnail` into a base64 data URI for a true textured preview.
- Strip-to-default mode, reusing the same traversal to clear nested face materials.
- Back-face-only and swap-front-and-back operations for fixing reversed geometry.
