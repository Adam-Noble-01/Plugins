# Na__ArrayBuilderTools - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================
## Array Builder Version 0.0.8 - 01-May-2026

### New Feature: Fixed Start/End Inset Distribution Mode

A third distribution strategy where the first and last unit on every
path segment land at a user-configurable distance ("inset") from the
segment endpoints, and the intermediate units are evenly distributed
at as close to the target spacing as possible. Off by default; mode is
selected from a new 3-way segmented selector that replaces the
existing single Normalise toggle.

#### New Distribution Selector

- **Fixed Step** (default) - walks the path with a constant
  `unit_width + spacing` step. Behaviour unchanged from prior versions.
- **Normalise** - existing per-segment normalisation; units land at
  both ends of each wall.
- **Fixed Inset** - new mode. Each segment places one unit at
  `seg_start + inset`, one at `seg_end - inset - unit_width`, and as
  many evenly-spaced intermediates as fit at ~target spacing. Default
  inset = 200mm (matches the supplied reference drawings).

Edge cases:
- Segment too short for two-with-insets (`seg_len < 2*inset + unit_width`)
  -> single best-effort centred unit.
- Segment exactly at the threshold -> one unit at `first_leading`.

#### New File

- `Na__ArrayBuilder__InsetDistribution__.rb` - pure stateless math
  module. Public methods (all `self.`):
  `Na__InsetDistribution__CalculatePositions(path_points, unit_width, spacing, inset)`
  and `Na__InsetDistribution__CalculateActualSpacingMm(path_points, unit_width, spacing, inset)`,
  plus internal `Na__InsetDistribution__SegmentPositions` and
  `Na__InsetDistribution__LeadingToLeadingSpan` helpers. No SketchUp
  tool callbacks, no module state, all capital-letter calls use
  parens or `self.` per the codebase convention.

#### Module Audit (No Duplication)

| Concern | Lives where | Touched? |
|---|---|---|
| Fixed-step distribution | `Na__ArrayBuilder__PathTool__.rb` `na_calculate_fixed_positions` | No |
| Normalised distribution | `Na__ArrayBuilder__PathTool__.rb` `na_calculate_normalised_positions` | No |
| Fixed-inset distribution | NEW `Na__ArrayBuilder__InsetDistribution__.rb` | New file |
| Distribution router | `Na__ArrayBuilder__PathTool__.rb` `na_calculate_preview_positions` | Yes (3-way `case`) |
| Average actual spacing | `Na__ArrayBuilder__PathTool__.rb` `na_calculate_actual_spacing_mm` | Yes (extra branch + extracted normalised helper) |
| Info-text overlay label | `Na__ArrayBuilder__PathTool__.rb` `na_draw_info_text` | Yes (3-way `case`) |
| Distribution selector UI | `Na__ArrayBuilder__UiLayout__.html` | Yes (replaced toggle with 3-way buttons) |
| Distribution config payload | `Na__ArrayBuilder__UiBridge__.js` | Yes (`distribution` string + `inset_mm`) |

The new module's algorithm is structurally similar to
`na_calculate_normalised_positions` (per-segment iteration, n_gaps +
actual_step) but the boundary conditions differ (`first_pt` offset by
`inset`, `last_pt` offset by `inset + unit_width`). Consolidating
would have obscured both, so the two existing strategies stay where
they are.

#### Modified Files

- `Na__ArrayBuilder__Main__.rb` - bump version to `0.0.8`,
  `require_relative` the new module.
- `Na__ArrayBuilder__PathTool__.rb`:
  - `initialize` reads `@distribution` (string: `fixed` / `normalise`
    / `inset`) and `@inset` (Length) from config. Legacy
    `normalise_distance` boolean still honoured as a fallback.
  - `na_calculate_preview_positions` -> 3-way `case` dispatch.
  - `na_calculate_actual_spacing_mm` -> 3-way dispatch; the existing
    normalised-mode body is moved into a new
    `na_calculate_normalised_actual_spacing_mm` helper so the public
    router stays a thin switch.
  - `na_draw_info_text` -> 3-way `case` for the overlay label;
    inset mode shows `Inset: Nmm | Actual: Mmm (target: Tmm)`.
- `Na__ArrayBuilder__UiLayout__.html` - replaced the Normalise toggle
  row with three buttons styled via the existing `.na-type-selector`
  / `.na-type-btn` rules; added a hidden `na-inset-row` input and a
  shared hint paragraph that swaps text per mode.
- `Na__ArrayBuilder__UiBridge__.js`:
  - Added `na_currentDistribution = 'fixed'` state and
    `NA_DIST_HINTS` lookup table.
  - New `na_selectDistribution(mode)` toggles button active classes,
    shows / hides the inset input, and refreshes the hint text.
  - `na_buildBoxConfig` and `na_buildObjectConfig` now emit
    `distribution` + `inset_mm` instead of `normalise_distance`.
  - `na_startPlacement` no longer reads the now-deleted
    `na-normalise` checkbox.

#### API Verification

No new SketchUp Ruby API surface. The new module uses
`Geom::Vector3d#%` (dot product), `Geom::Point3d#offset(vector, distance)`,
and the standard `length=` mutator - all already used by the existing
distribution methods.

# =======================================================================================
## Session Retrospective - 01-May-2026 (v0.0.3 -> v0.0.7)

A single working session took the Array Builder from "dentil + dog-tooth
courses only, Ctrl+Click-to-extend path model, no observers, no axis
lock" to a Profile-Builder-class tool with custom-object support,
arrow-key axis locking via the canonical SketchUp API, model-aware
observers, batched per-frame rendering, and intuitive path controls.
The journey was iterative and not all paths worked the first time -
this retrospective captures both the destination and the lessons.

### Final Feature Surface

- **Three array types**: dentil (axis-aligned box), dog-tooth (45-deg
  rotated box), and **Custom Object** - any picked
  `Sketchup::Group` or `Sketchup::ComponentInstance`, anchored either
  by its local axis (default, supports asymmetric set-out) or its
  bounding-box centre.
- **Profile-Builder-style path tool**: every click adds a waypoint,
  Enter / right-click / double-click finishes, Backspace undoes,
  ESC cancels.
- **Arrow-key axis lock** during path placement (Right=red, Left=green,
  Up=blue, Down=parallel-to-last-segment), built on
  `Sketchup::View#lock_inference` so SketchUp draws the dashed
  inference line natively and projects the cursor automatically.
- **Cross-model safety**: `Sketchup::AppObserver` +
  `Sketchup::DefinitionsObserver` clear the picked-object registry
  when the active model changes or the picked component is deleted.
- **Smooth viewport** even on long paths: per-frame preview cache
  (computed once, consumed by status-text formatter and draw),
  JS-bridge throttle on the dialog preview-info push, and a single
  batched `view.draw(GL_LINES, segments)` call for all preview-unit
  wireframes.
- **Quiet console** by default: a `NA_DEBUG_LOG` constant gates all
  non-fatal puts so SketchUp's Ruby Console window cannot stutter the
  viewport.

### Version Arc

- **v0.0.3** - Custom Object array mode. New `Na__ArrayBuilder__ObjectRegistry__.rb`
  + `Na__ArrayBuilder__ObjectPicker__.rb`. Branch in `GeometryBuilder`
  routes to `na_create_array_from_definition` for object mode. PathTool
  reads bbox dims from registry. UI gains the third Array Type button
  plus the Object Source section.
- **v0.0.4 (attempt 1, rolled back)** - Tried hand-rolled axis-lock
  with manual cursor projection and a coloured rubber-band overlay.
  Rolled back when SketchUp crashed and the cursor jumped away from
  the mouse with no visual cue. Three root causes identified:
  `view.draw_text` ignores `drawing_color`; `view.draw_text` is fragile
  mid-3D-pass; manual projection of `@cursor_pos` broke the
  cursor-follows-mouse expectation.
- **v0.0.4 (attempt 2)** - Rewrote on top of `Sketchup::View#lock_inference`
  per Eneroth's reference example
  ([API issue #374](https://github.com/SketchUp/api-issue-tracker/issues/374)).
  Half the code, no custom drawing, no custom projection. SketchUp
  itself handles the dashed inference line and the cursor projection.
- **v0.0.5** - Three perf wins plus correctness via observers:
  1. Model observers (`AppObserver` + `DefinitionsObserver`) keep the
     ObjectRegistry honest across model switches and component deletion.
  2. Per-frame preview cache eliminates the double-compute that was
     happening because both `na_update_status_text` and `draw` were
     recomputing positions.
  3. JS-bridge throttle on `na_send_preview_info` removes a per-frame
     IPC hop into the embedded WebView when nothing has changed.
  4. Wireframe batching: `view.draw(GL_LINES, segments)` once per frame
     instead of `view.draw_line` 12 times per unit.
- **v0.0.6** - Three more wins plus the critical arrow-key fix:
  1. Status-text memoisation skips identical writes.
  2. `NA_DEBUG_LOG` constant + `na_debug_log` helper gate every
     non-fatal puts so the Ruby Console can stay quiet.
  3. **Arrow-key bugfix**: discovered that `@ip.pick(view, x, y, @ip_prev)`
     (4-arg form) shadows `view.lock_inference` because the previous
     InputPoint takes inference priority. Switched to the 3-arg form
     `@ip.pick(view, x, y)` whenever a lock is active.
  4. **Mid-session NameError firefight**: discovered that
     capital-letter method names called bare (without parens or `self.`)
     are parsed as constant lookup, not method calls. This had been
     silently breaking observer install + spamming the Ruby Console
     thousands of times per second from `na_update_status_text`. Fixed
     across PathTool, AxisLockMixin, ObjectPicker and ModelObservers.
- **v0.0.7** - Profile-Builder-style controls. Click adds waypoint,
  Enter / right-click / double-click finishes, Backspace undoes back
  to `:picking_start`, empty `getMenu` suppresses the right-click
  context menu. Keyboard-handler `super`-chain delegates arrow keys
  to the existing `Na__ArrayBuilder__AxisLockMixin#onKeyDown`.

### Lessons That Will Outlive This Plugin

1. **Use SketchUp's canonical APIs even when you don't think you need
   to.** `view.lock_inference(ip1, ip2)` did everything we tried to
   build by hand and did it without the crash and the UX glitch.
2. **Ruby's bareword-to-constant rule applies to `Foo` even when a
   method `Foo` exists on `self`.** Always call capital-letter methods
   with `()` or `self.` prefix. The existing keyboard mixins in the
   codebase use `self.MethodName` for exactly this reason; new code
   should follow the same convention.
3. **`@ip.pick(view, x, y, @ip_prev)` is NOT a drop-in upgrade of the
   3-arg form when a view-level lock is active.** The previous
   InputPoint takes inference priority and shadows the lock.
4. **Per-frame work compounds.** A single `execute_script` JS-bridge
   hop per frame, a single status-bar repaint per frame, or 12*N
   `draw_line` calls per frame all individually look harmless but
   produce visible stutter together.
5. **The SketchUp Ruby Console window stutters the viewport** even
   from non-plugin output when it is visible. Don't write to `puts`
   on the hot path. Don't write to it casually at all.
6. **Observers are a correctness tool, not a perf tool.** Without
   them, references to model objects can outlive the model itself
   and produce confusing UI states.
7. **Iterating with the user is faster than over-engineering up front.**
   The v0.0.4 rollback hurt in the moment but the second attempt was
   half the code and worked correctly because the failure mode taught
   us where the documented API was hiding.

### What's Parked (deliberate scope decisions)

- Two-stage / three-stage ESC.
- Numerical input via the VCB to set segment length.
- Snap-to-existing-waypoint to auto-close a loop.
- User-selectable forward axis for object mode (locked to local +X).
- Shift-arrow modifier for "perpendicular to last segment" lock.
- Persisting the picked object across SketchUp sessions.

# =======================================================================================
## Array Builder Version 0.0.7 - 01-May-2026

### UX: Profile-Builder-Style Path Tool Controls

Replaced the old Ctrl+Click-to-extend / Click-to-finish path-tool model
with a more intuitive flow that mirrors Profile Builder and
SketchUp's native drawing tools.

#### New Control Mapping

- Left-click (state `:picking_start`) -> set start point.
- Left-click (state `:picking_path`) -> add waypoint. Always. No Ctrl
  modifier required - this was the biggest cognitive cost in the
  previous design.
- **Enter** (`onReturn`) -> finish the path.
- **Right-click** (`onRButtonDown`) -> finish the path. SketchUp's
  default context menu is suppressed via an empty `getMenu` so the
  right-click acts as a clean "finish" gesture.
- **Double-click** (`onLButtonDoubleClick`) -> finish the path.
- **Backspace** (and Mac Forward Delete via `VK_DELETE`) -> undo the
  most recent waypoint. Repeats; once the path collapses to empty the
  tool returns to `:picking_start` so the user can re-pick the origin
  rather than being kicked out.
- **ESC** -> cancel the tool entirely (per user-confirmed decision; no
  staged ESC).
- Arrow keys -> axis lock (unchanged).

#### Modified Files

- `Na__ArrayBuilder__PathTool__.rb`:
  - New constant `NA_VK_BACKSPACE = 8` (Backspace has no `VK_*` in the
    SketchUp Ruby API).
  - `onLButtonDown` simplified - one branch for first click, one for
    subsequent clicks; no more Ctrl-modifier check.
  - New callbacks: `onReturn`, `onRButtonDown`, `onLButtonDoubleClick`
    all delegate to `na_finish_path_if_ready`.
  - New `getMenu(menu, *args)` that returns nothing so right-click no
    longer pops up SketchUp's context menu.
  - `onKeyDown` overridden in PathTool to intercept Backspace /
    VK_DELETE and delegate the rest to `Na__ArrayBuilder__AxisLockMixin`
    via `super` (preserving the arrow-key axis lock).
  - New private helper `na_finish_path_if_ready(view)`. Stays in the
    tool with a "Add at least one more waypoint before finishing"
    warning when the user tries to finish too early - prevents a stray
    Enter from kicking the user out.
  - New private helper `na_undo_last_waypoint(view)`. Pops, manages the
    `:picking_start` <-> `:picking_path` state transition, resets
    `@ip_prev` to a fresh `Sketchup::InputPoint`, re-anchors the axis
    lock to the new last waypoint, rebuilds the preview cache.
  - `na_update_status_text` rewritten to teach all new gestures in one
    line: "Click to add waypoint | Enter / Right-click / Double-click
    to finish | Backspace to undo | ESC to cancel | <n> units | <len>mm".

#### API Verification (SU 2026)

All new Tool callbacks cross-checked against
[https://ruby.sketchup.com/Sketchup/Tool.html](https://ruby.sketchup.com/Sketchup/Tool.html):

- `onReturn(view)` - standard, broken in SU 2025 but fixed in SU 2026
  per [API issue #1076](https://github.com/SketchUp/api-issue-tracker/issues/1076).
- `onRButtonDown(flags, x, y, view)` - standard.
- `onLButtonDoubleClick(flags, x, y, view)` - standard.
- `getMenu(menu, ...)` - implementing it (even empty) replaces
  SketchUp's default context menu per the docs.
- Backspace key code 8 reaches `onKeyDown` as the `key` parameter
  cross-platform.

# =======================================================================================
## Array Builder Version 0.0.6 - 01-May-2026

### Bugfix: Arrow-Key Axis Lock Now Actually Affects the Preview

The v0.0.4 axis-lock implementation was technically correct but the
preview cursor was still tracking the raw mouse position whenever a
lock was active. Root cause: in `onMouseMove` the path tool was using
the 4-argument `@ip.pick(view, x, y, @ip_prev)` form during
`:picking_path`. That form gives the previous InputPoint priority for
"additional inferences", which in practice shadowed
`view.lock_inference` so the cursor never snapped to the locked line.

Fix: when a lock is active, fall back to the 3-arg
`@ip.pick(view, x, y)` form so SketchUp's view-level inference lock is
the dominant constraint - matching Eneroth's reference example for
this API.

#### Modified Files (Bugfix)

- `Na__ArrayBuilder__AxisLockMixin__.rb` - new public predicate
  `Na__AxisLock__Active?` for the path tool to query.
- `Na__ArrayBuilder__PathTool__.rb` - `onMouseMove` selects pick form
  based on `Na__AxisLock__Active?`.

### Performance: Status-Text Memo + Quiet Console

Two more wins after the v0.0.5 round:

1. **Memoised `Sketchup.status_text=`**. Setting status text on every
   mouse move was triggering a status-bar repaint per frame even when
   the text was unchanged. The path tool now builds the status string,
   compares it to `@na_last_status_text`, and only writes when it
   genuinely changed. Reset on tool activate.

2. **Quiet Ruby Console by default**. SketchUp's Ruby Console window
   is well known to stutter the whole viewport when even small amounts
   of console output are written while the window is visible. The
   plugin previously emitted "loaded successfully" + per-array
   "Created N units" + several `WARN:` lines - all benign, but enough
   to interact with the console window. v0.0.6 adds a
   `NA_DEBUG_LOG` constant on `Na__ArrayBuilderTools` and a
   `na_debug_log(message)` helper that no-ops when the flag is false
   (the default). All non-fatal info / warning puts now route through
   the helper. Real errors (load-fatal, geometry-build exceptions,
   missing HTML file) still go straight to `puts` because they need to
   be visible without changing a flag.

#### Modified Files (Performance / Logging)

- `Na__ArrayBuilder__Main__.rb` - `NA_DEBUG_LOG` constant + the
  `Na__ArrayBuilderTools.na_debug_log` helper.
- `Na__ArrayBuilder__PathTool__.rb` - status-text memoisation
  (`@na_last_status_text`).
- `Na__ArrayBuilder__GeometryBuilder__.rb` - "Created N units" puts
  routed through `na_debug_log`.
- `Na__ArrayBuilder__ModelObservers__.rb` - all observer-rescue puts
  routed through `na_debug_log`.
- `Na__ArrayBuilder__DialogManager__.rb` - `na_jsLog` action callback
  + start-array rescue routed through `na_debug_log`.
- `Na__ArrayBuilderTools__Loader.rb` - load-success puts removed;
  observer + icon install warnings routed through `na_debug_log`.

To re-enable diagnostic logging, set
`Na__ArrayBuilderTools::NA_DEBUG_LOG = true` in the Ruby Console
before reloading the plugin.

# =======================================================================================
## Array Builder Version 0.0.5 - 01-May-2026

### Correctness: SketchUp Observers for Cross-Model Consistency

`Na__ArrayBuilder__ObjectRegistry` holds a `Sketchup::ComponentDefinition`
reference for the user-picked source object. Without observers, that
reference could go stale across model switches and after the picked
component was deleted - the dialog kept displaying the old name and
bounding box, and Start Placement only failed at validation time. Two
canonical SketchUp observer types now keep the registry honest:

- `Na__ArrayBuilder__AppObserver < Sketchup::AppObserver` watches
  `onNewModel`, `onOpenModel`, `onActivateModel`. On any model change
  the registry is cleared, the dialog gets a `na_objectCleared` push,
  and the definitions observer is re-attached to the new active
  model's `model.definitions`.
- `Na__ArrayBuilder__DefinitionsObserver < Sketchup::DefinitionsObserver`
  watches `onComponentRemoved`. Clears the registry only when the
  removed definition matches the currently-stored one.

Installation entry point `Na__Observers__InstallOnce` is idempotent
(detaches any prior observers first) so the existing `file_loaded?`
guard in the loader is safe to leave in place.

### New Files

- `Na__ArrayBuilder__ModelObservers__.rb` - both observer classes plus
  the `Na__Observers__InstallOnce` / `AttachDefinitionsObserver` /
  `DetachDefinitionsObserver` / `ClearRegistryAndNotifyDialog` helpers.

### Modified Files

- `Na__ArrayBuilderTools__Loader.rb` - one new block that requires the
  observers module and calls `Na__Observers__InstallOnce`. Wrapped in
  `begin/rescue` so observer install failure never blocks the rest of
  the plugin from loading.

### Performance: Eliminate Viewport Jank During Path Placement

Three concrete wins for the per-frame work the path tool was doing:

1. **JS-bridge throttle in `na_send_preview_info`**. The path tool
   called `@dialog.execute_script("window.na_updatePreviewInfo(...)")`
   on every viewport refresh. SketchUp invalidates frequently during
   mouse moves and orbit, so this was a per-frame IPC hop into the
   embedded WebView. The dialog manager now memoises the last sent
   `(count, length, spacing)` triplet and short-circuits the
   `execute_script` call when nothing has changed. Reset on tool
   activate via `na_reset_preview_info_memo` so the next placement
   always pushes a fresh value.

2. **Per-frame preview cache in PathTool**. `onMouseMove` was indirectly
   calling `na_calculate_preview_positions` twice (once via
   `na_update_status_text`, once via `draw`) because both paths
   recomputed the same per-segment positions/lengths. A new
   `na_rebuild_preview_cache` builds the data once per move and stores
   it on `@na_cache_path / @na_cache_positions / @na_cache_total_mm /
   @na_cache_actual_mm`. Both consumers now read from the cache.
   `na_reset_preview_cache` clears it on activate / when the path
   transitions back to picking-start. The cache is also rebuilt after
   each waypoint commit so the next draw frame starts from fresh data.

3. **Batched preview wireframe draw**. The old code called
   `view.draw_line` 12 times per preview unit, so N units cost 12*N
   GL calls per frame. `na_draw_preview_units` now collects every
   wireframe segment into a single flat array and emits one
   `view.draw(GL_LINES, segments)` call. The dead helper
   `na_draw_wireframe_box` was removed.

Combined, the three changes drop the per-frame work from
`O(units)` GL calls + 1 JS bridge hop + double position computation
to roughly `O(1)` GL calls + 0 JS bridge hops (when stable) + single
position computation.

#### Modified Files (Performance)

- `Na__ArrayBuilder__DialogManager__.rb` - throttle in
  `na_send_preview_info`; new `na_reset_preview_info_memo` helper.
- `Na__ArrayBuilder__PathTool__.rb` - cache fields and
  `na_rebuild_preview_cache` / `na_reset_preview_cache`; `draw` and
  `na_update_status_text` read from the cache; `onLButtonDown`
  rebuilds the cache after each waypoint commit; preview-unit drawing
  refactored into `na_collect_preview_unit_segments` +
  `na_collect_wireframe_box_segments` plus the single batched
  `view.draw(GL_LINES, segments)` call.

### API Verification (SU 2026)

All Ruby API surface cross-checked against
[ruby.sketchup.com](https://ruby.sketchup.com/):
- `Sketchup.add_observer` / `Sketchup.remove_observer`
- `Sketchup::AppObserver#onNewModel` / `#onOpenModel` / `#onActivateModel`
- `Sketchup::DefinitionsObserver#onComponentRemoved`
- `Sketchup::Entities#add_observer` / `#remove_observer` (for the
  `model.definitions` collection)
- `Sketchup::View#draw(GL_LINES, points)` - documented batched draw.

# =======================================================================================
## Array Builder Version 0.0.4 - 01-May-2026

### New Feature: Profile-Builder-Style Arrow-Key Axis Lock

While the path tool is active, the user can lock the next path segment
to a world axis (or parallel to the previous segment) using the arrow
keys. The lock persists across waypoint commits until the user toggles
it off (repeat the same arrow) or swaps to a different axis.

#### Key Bindings

- Right Arrow -> red (X) axis
- Left  Arrow -> green (Y) axis
- Up    Arrow -> blue (Z) axis
- Down  Arrow -> parallel to the previous committed segment
- ESC unchanged (cancels the tool); to clear a lock without cancelling,
  press the same arrow again.

#### Implementation Strategy

This feature is built on the canonical SketchUp API
`Sketchup::View#lock_inference(ip_anchor, ip_axis_end)` so that
SketchUp itself does both the projection and the dashed inference-line
rendering. We do NO manual cursor projection and NO custom drawing.
This delegates all the visual details (line stipple, axis colours,
cursor snapping) to SketchUp's native inference engine, matching the
behaviour of native tools.

Research sources cross-referenced when designing this implementation:

- [API issue #374](https://github.com/SketchUp/api-issue-tracker/issues/374) -
  Eneroth (SU Sage) documents the canonical two-InputPoint pattern for
  locking inference to a line.
- [Forum thread "View#lock_inference example?"](https://forums.sketchup.com/t/view-lock-inference-example/34999/5) -
  Confirms the same pattern with worked examples.
- [API issue #607](https://github.com/SketchUp/api-issue-tracker/issues/607) -
  Confirms arrow keys reach `Tool#onKeyDown` (they are reserved by
  SketchUp and cannot be assigned as user shortcuts).
- [API issue #926](https://github.com/SketchUp/api-issue-tracker/issues/926) -
  SKEXT-3890 onKeyDown double-fire regression on Windows 23.1.340+;
  mitigated here with the same per-key held-flag guard pattern used in
  `Na__InsertPrimatives__KeyboardHandlers__.rb`.

#### Why a Previous Attempt Was Rolled Back

An earlier 0.0.4 attempt manually projected the cursor and drew its
own coloured rubber-band line. That approach was rolled back because:

- `view.draw_text` ignores `drawing_color` and uses the model's
  foreground edge colour ([API issue #437](https://github.com/SketchUp/api-issue-tracker/issues/437)),
  so axis-coloured labels never rendered correctly.
- `view.draw_text` is fragile when called mid-3D-pass (drawing-order
  issues per the [Sketchucation thread](https://community.sketchucation.com/topic/134480/view-draw_text-invisible)).
- Manual projection of `@cursor_pos` made the crosshair jump away from
  the mouse with no visual cue, which felt wrong.

The current design avoids all three by deleting the responsibility
entirely - SketchUp handles projection AND visualisation.

#### New Files

- `Na__ArrayBuilder__AxisLockMixin__.rb` - single mixin module
  `include`d into `Na__ArrayBuilder__PathTool`. Owns the runtime state
  (`@na_active_lock`, `@na_arrow_held`) and the SketchUp `onKeyDown` /
  `onKeyUp` callbacks. Public hooks for the host tool:
  `Na__AxisLock__InitState`, `Na__AxisLock__ClearOnDeactivate(view)`,
  `Na__AxisLock__ReanchorAfterCommit(view)`,
  `Na__AxisLock__BuildStatusFragment`. Internally dispatches via
  `Na__AxisLock__ApplyLockToView(view)` which is the single place that
  calls `view.lock_inference`.

#### Modified Files

- `Na__ArrayBuilder__PathTool__.rb` - six small surgical edits, none
  touching `onMouseMove` or `draw`:
  1. requires + `include Na__ArrayBuilder__AxisLockMixin`
  2. `activate` calls `Na__AxisLock__InitState`
  3. `deactivate` calls `Na__AxisLock__ClearOnDeactivate(view)` so the
     lock cannot leak into the next tool
  4. `onCancel` also calls `Na__AxisLock__ClearOnDeactivate(view)`
  5. `onLButtonDown` calls `Na__AxisLock__ReanchorAfterCommit(view)`
     after each waypoint commit (start-point branch and Ctrl+Click
     branch) so the dashed inference line follows the new anchor
  6. `na_update_status_text` appends
     `Na__AxisLock__BuildStatusFragment` to both state-branch lines
- `Na__ArrayBuilder__DEVLOG__.md` - this entry.

#### API Verification (SU 2026)

All Ruby API methods cross-checked against
[ruby.sketchup.com](https://ruby.sketchup.com/):
- `Sketchup::View#lock_inference()` / `(ip)` / `(ip1, ip2)` - documented.
- `Sketchup::InputPoint.new(point3d)` - documented.
- `Sketchup::Tool#onKeyDown` / `onKeyUp` - standard tool callbacks.
- `VK_LEFT`, `VK_RIGHT`, `VK_UP`, `VK_DOWN` - top-level namespace.
- `Geom::Point3d#offset(vector, distance)` - already used in path tool.

# =======================================================================================
## Array Builder Version 0.0.3 - 01-May-2026

### New Feature: Custom Object Array Mode

A third array type (`'object'`) lets the user pick any `Sketchup::Group`,
solid Group, or `Sketchup::ComponentInstance` from the model and array
that as the unit along the existing path-based workflow. Spacing,
normalised-distance distribution, and the path tool's preview pipeline
are all reused unchanged.

#### New Files

- `Na__ArrayBuilder__ObjectRegistry__.rb` - small in-memory store that
  holds the picked `Sketchup::ComponentDefinition` and exposes derived
  bounding-box dimensions in millimetres (`Na__Registry__SetDefinition`,
  `Na__Registry__Clear`, `Na__Registry__GetDefinition`,
  `Na__Registry__GetDisplayName`, `Na__Registry__IsValid?`,
  `Na__Registry__GetBoundsMm`).
- `Na__ArrayBuilder__ObjectPicker__.rb` - modal `Sketchup::Tool` that
  validates the click target is a Group or ComponentInstance (rejecting
  faces / edges / sections), normalises Groups via `Group#definition`
  (SU 2018+), draws a hover bounding-box highlight, and reports back to
  the dialog through `na_send_object_picked`.

#### Modified Files

- `Na__ArrayBuilder__Main__.rb` - bumped version to `0.0.3`, added
  `NA_OBJECT_DEFAULTS`, `require_relative` for the two new modules.
- `Na__ArrayBuilder__DialogManager__.rb` - added action callbacks
  `na_pickObject`, `na_clearObject`; added push helpers
  `na_send_object_picked` and `na_send_object_cleared`; added
  `na_validate_object_source_or_warn` short-circuit in
  `na_handle_start_array` for `type == 'object'`.
- `Na__ArrayBuilder__GeometryBuilder__.rb` - public `na_create_array`
  now routes to `na_create_array_from_box` (existing dentil/dogtooth
  logic, unchanged behaviour) or the new
  `na_create_array_from_definition`, which adds component instances of
  the registered source definition with an axis-aware transform
  (`local +X` -> path forward, `local +Z` -> up). Anchor offset is
  built via `Geom::Transformation.translation(bounds.center).inverse`
  for centre mode (always invertible under SU 2026 strict rules).
- `Na__ArrayBuilder__PathTool__.rb` - `initialize` now resolves
  `unit_*_mm` from `Na__Registry__GetBoundsMm` when in object mode so
  the existing positioning maths is reused untouched. Preview drawing
  honours the new `anchor_mode` (centre vs local axis).
- `Na__ArrayBuilder__UiLayout__.html` - added third Array Type button
  (Custom Object), new Object Source section with Pick / Clear, picked
  object info card (name + W/D/H), spacing input, and a Local Axis /
  Centre anchor selector.
- `Na__ArrayBuilder__UiBridge__.js` - added `'object'` defaults,
  `na_toggleSourceSections`, `na_pickObject`, `na_clearObject`,
  `na_setAnchorMode`, `na_buildObjectConfig`, plus `na_objectPicked` /
  `na_objectCleared` Ruby->JS receivers.
- `Na__ArrayBuilder__UiStyle__.css` - added `.na-object-row`,
  `.na-btn-secondary`, `.na-object-info`, `.na-object-name` styling.

#### API Verification (SU 2026)

All Ruby API methods cross-checked against
[ruby.sketchup.com](https://ruby.sketchup.com/). Two notes captured in
the geometry builder:
- `Geom::BoundingBox` method names are counter-intuitive:
  `width = X`, `height = Y`, `depth = Z`. The official docs explicitly
  call out that `bounds.height` is "depth in SketchUp's coordinate
  system" and `bounds.depth` is "height".
- `Geom::Transformation#inverse` is stricter in SU 2026 (raises on
  non-invertible). Pure translations are always invertible, so the
  centre-anchor offset is safe.

# =======================================================================================
## Array Builder Version 0.0.2 - 02-Apr-2026

### Branding + Toolbar Icon (Profile Path Tracer parity)

- Added `Na__ArrayBuilder__AssetResolver__.rb`:
  - Resolves the main toolbar icon using the same rules as Profile Path Tracer: optional local override in `02__PluginImageAssets/Na__ArrayBuilder__Icon__.png`, otherwise `Na__Common__PluginDependencies/IMG02__ICN__NaCompanyIcon.png`.

- Updated `Na__ArrayBuilderTools__Loader.rb`:
  - Command `small_icon` / `large_icon` assigned from `Na__ArrayBuilder__AssetResolver.Na__Assets__MainIconPath` when the file exists.

- Updated `Na__ArrayBuilder__Main__.rb`:
  - Declared `NA_PLUGIN_VERSION` as `0.0.2`.
  - Added `require_relative` for `Na__ArrayBuilder__AssetResolver__`.

- Updated `Na__ArrayBuilder__UiLayout__.html`:
  - Header shows the shared NA company icon beside the title (same asset as Profile Path Tracer toolbar branding).

- Updated `Na__ArrayBuilder__UiStyle__.css`:
  - Added `.na-header-brand` and `.na-header-icon` for icon + title layout.

- Updated module headers (`Na__ArrayBuilder__DialogManager__`, `Na__ArrayBuilder__GeometryBuilder__`, `Na__ArrayBuilder__PathTool__`) to document version `0.0.2`.

# =======================================================================================
## Array Builder Version 0.0.1 - Initial

### Core workflow

- HtmlDialog configuration UI (dentil / dog-tooth presets, dimensions, normalise spacing).
- Path placement tool with preview and geometry build pipeline.
- Plugins menu + **NA Array Tools** toolbar entry.

# =======================================================================================
# END OF DEVLOG
# =======================================================================================
