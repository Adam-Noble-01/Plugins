# Na Noble3d - Untag Specific In Selection - Development Log
# =============================================================================
# Module : 22__SourceCode__UntagSpecificInSelection
# Plugin : Na Noble3d Modelling Tools
# Tab    : Tag Utils > Tag Operations

## Overview

Selectively removes specific tags from the current SketchUp selection while
preserving all other tag assignments. Scans recursively through all groups,
component instances, and nested geometry at any depth. Presents a live
checklist dialog of found tags with entity counts, then moves matching
entities to the default Untagged layer in a single undoable operation.

A `Sketchup::SelectionObserver` keeps the checklist updated whenever the
SketchUp selection changes while the dialog is open — the dialog behaves
as a live inspector rather than a one-shot snapshot.

Parent migration entry: main devlog **Version 0.5.6** (24-Jun-2026).

# =============================================================================
# VERSION HISTORY
# =============================================================================


# Na Noble3d Modelling Tools — Untag Specific In Selection
## Version 1.0.0 - 24-Jun-2026 - Initial Migration from Standalone Plugin

### Overview
Migrated and refactored the standalone single-file `Na__UntagSpecificInSelection__Main__.rb`
(Plugins root, 487 lines) into Noble 3D Modelling Tools as a fully modular sub-dialog feature
module. The migration split the monolith into five single-responsibility Ruby files plus a
selection observer, fixed two bugs present in the original, and added live selection
synchronisation via a `Sketchup::SelectionObserver`.

### Update 01 - Module Structure
- Standalone file replaced by 6-file module folder at `10__PluginModules/22__SourceCode__UntagSpecificInSelection/`:
  - `__Loader__` — requires the five siblings in dependency order.
  - `__TagCollector__` — single responsibility: collect unique tags from a set of entities recursively, returning a hash of tag names with entity counts.
  - `__Untagger__` — single responsibility: move entities matching chosen tag names to the untagged layer recursively.
  - `__SelectionObserver__` — `Sketchup::SelectionObserver` subclass; forwards all four selection-change events to the DialogManager.
  - `__DialogManager__` — owns dialog lifecycle, observer attach/detach, live JS push helpers, action callbacks, and inline HTML/CSS/JS generation.
  - `__Run__` — public Noble 3D Tools entrypoint; validates preconditions and delegates; returns `{ success:, message: }`.

### Update 02 - Bug Fix: Layer0 Hardcode (SketchUp Version Compatibility)
- Original code compared `entity.layer.name == "Layer0"` to identify and skip the default untagged layer. In SketchUp 2020+, the default layer is named `"Untagged"`, not `"Layer0"`. The original plugin was therefore treating `"Untagged"` as an ordinary removable tag and presenting it in the checklist.
- Fixed: comparison now uses `entity.layer == model.layers[0]` (object identity). This is version-agnostic and does not rely on the layer's display name.

### Update 03 - Bug Fix: Recursive Scan Depth (Untagged Container Skip)
- Original code and first migration draft placed the recursion call after a `next` guard that fired when an entity was on the untagged layer. This meant groups and components sitting on the Untagged layer were exited early — all of their tagged children and grandchildren were never reached.
- Fixed: tag recording (`na_record_entity_tag`) and container recursion (`na_recurse_into_container`) are called as two independent, unconditional steps for every entity in the main loop. Untagged containers are still skipped for recording but are always descended into.

### Update 04 - HtmlDialog Bridge Modernisation
- Original JS used `window.location = 'skp:callback@value'` URL interception for Ruby callbacks. Replaced with `window.sketchup.callback(value)` throughout — the current recommended bridge approach for `UI::HtmlDialog` in SketchUp 2017+. The `skp:` URL scheme is legacy and has known reliability edge cases in newer CEF builds.

### Update 05 - Live Selection Observer
- `Na__UntagSpecificInSelection__SelectionObserver` subclasses `Sketchup::SelectionObserver` and observes all four selection-change hooks: `onSelectionAdded`, `onSelectionBulkChange`, `onSelectionCleared`, `onSelectionRemoved`. All four delegate to `Na__UntagSpecificInSelection__DialogManager__HandleSelectionChanged`.
- Observer is attached to `model.selection` at dialog open time and removed in `set_on_closed`, ensuring no stale callbacks after the dialog closes.
- `HandleSelectionChanged` guards on `@na_dialog.visible?`, re-collects tags from the current selection, and pushes one of three state payloads to the dialog via `execute_script`:
  - `normal` — a rebuilt tag checklist with new counts.
  - `empty_selection` — a status banner informing the user no entities are selected.
  - `no_tags` — a status banner informing the user all entities are already untagged.
- The dialog JS exposes `Na__UntagSpecificInSelection__ReceiveTagsData(payload)` which rebuilds the checklist in-place, resets the Select All toggle, shows or hides the status banner, and gates the Untag Selected button — all without closing or reloading the dialog.

### Update 06 - Noble 3D Tools Integration
- Registered in `UiCommandRegistry__.json` under the new `Tag Operations` tool group (tool_group_order 20) in the existing `Tag Utils` tab.
- Wired in `CommandRouter__.rb` under `when 'untag_specific_in_selection'` and in `ModuleLoaders__Main__.rb` as slot 22.

### Update 07 - Old Plugin Removal
- Standalone `Na__UntagSpecificInSelection__Main__.rb` deleted from Plugins root after successful testing. No companion loader or modules folder existed for the old plugin.

### Validation Checklist
- [x] Tag checklist shows all tags found at any nesting depth, including inside containers that are themselves on the Untagged layer.
- [x] Default untagged layer (model.layers[0]) never appears in the checklist regardless of SketchUp version.
- [x] Selecting/deselecting entities in SketchUp while the dialog is open updates the checklist live.
- [x] Empty selection shows an informational status banner; dialog remains open and usable.
- [x] All selected entities already untagged shows an informational status banner; dialog remains open.
- [x] Untag operation wraps in a single undoable step; abort fires cleanly on error.
- [x] Select All / Deselect All toggle resets correctly after a live checklist update.
- [x] Standalone plugin file removed from Plugins root.

## -----------------------------------------------------------------------------
