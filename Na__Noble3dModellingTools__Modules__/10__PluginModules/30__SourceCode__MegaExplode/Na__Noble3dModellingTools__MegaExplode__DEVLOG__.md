# Na Noble3d Modelling Tools - Mega Explode - Development Log
# =============================================================================
# Module : 30__SourceCode__MegaExplode
# Plugin : Na Noble3d Modelling Tools
# Tab    : Entity Utils > Explode Tools

## Overview

Recursively explodes every group and component in the current selection, at
every nested level. Mixed sibling stacks (Group -> Component -> Group, Component
-> Group -> Group, Group -> Geometry, and any combination of those as siblings)
all use the same explode queue.

The dedicated HtmlDialog reports live selection stats, holds cleanup toggles
(all off by default), and shows an in-dialog confirm modal before the explode
runs. The whole run is one SketchUp Undo step.

Parent entry: main devlog **Version 0.8.5** (09-Sep-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================


## Version 1.0.1 - 09-Sep-2026 - Hang Fixes With Cleanup Toggles On

### Update 01 - All Toggles On Looked Frozen
- Not expected cost. Four bugs stacked: `all_connected` on every remaining
  entity after explode, surface flood treating hidden edges as joins and
  enqueueing neighbours without a seen-check, one-by-one `selection.add`, and
  the live selection observer walking stats on every explode mutation.

### Update 02 - Fixes
- Hidden delete only inspects remaining ents and each remaining face's edges.
- Surface walk uses soft/smooth only, marks faces seen before enqueue, and
  caps at 250,000 faces.
- Remaining entities and queued containers are deduped by `entityID`.
- Reselect adds survivors in batches of 500.
- Dialog detaches the selection observer for the explode, then reattaches.

### Status
**Reload Plugin Data, then retest a nested selection with every cleanup toggle on.**

# =============================================================================

## Version 1.0.0 - 09-Sep-2026 - First Release

### Update 01 - Recursive Explode Queue
- Breadth-first explode of `Sketchup::Group` and `Sketchup::ComponentInstance`.
- Nested children returned by `#explode` are queued until only loose drawing
  elements remain.
- Directly selected faces and edges stay in place.
- Locked containers are skipped unless **Unlock locked containers first** is on.
- Exploding an instance does not change other placements of that definition.

### Update 02 - HtmlDialog With Live Stats
- Selection observer keeps the stats in step with the model.
- Counts groups, components, depth, faces, edges, locked containers, tagged
  entities, unique tags, unique materials, and other placements of the same
  definitions.
- Preview walk stops at 50,000 entities so a huge selection cannot stall the
  dialog. The explode itself is never capped.

### Update 03 - Cleanup Toggles, All Off by Default
- **Move all geometry to Untagged** assigns remaining entities to Layer0
  (`model.layers[0]`). SketchUp 2020+ shows Layer0 as Untagged.
- **Strip all materials to Default** sets `material` / `back_material` to `nil`.
  Images are left alone.
- **Unlock locked containers first** unlocks then explodes.
- **Purge unused after explode** runs `definitions.purge_unused`,
  `materials.purge_unused`, and `layers.purge_unused` in the same undo step.

### Update 04 - In-Dialog Confirm Modal
- The primary button opens an overlay modal, not a native `UI.messagebox`.
- Confirm copy restates container count, depth, locked behaviour, and any
  cleanup options that are on.
- Cancel / Escape / backdrop click dismisses the modal without exploding.

### Validation Checklist
- [x] Registry JSON includes command, button, and hotkey binding.
- [x] Module loader slot 30, router handler, reload-manager dialog reset.
- [x] UiBridge.js passes `node --check`.
- [x] Registry JSON parses.
- [ ] Dialog opens from Entity Utils > Explode Tools.
- [ ] Search for "explode" finds Mega Explode.
- [ ] Nested Group -> Component -> Group explodes to loose geometry in one undo.
- [ ] Sibling mixed stacks explode together.
- [ ] Locked containers skipped unless unlock is on.
- [ ] Untagged / strip / purge options stay off until ticked, then apply.

### Status
**Written and statically verified; not yet exercised in SketchUp.**

# =============================================================================
# END OF FILE
# =============================================================================
