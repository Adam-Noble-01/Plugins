# Na Insert Primatives - Development Log
# =============================================================================

# =============================================================================

## Version 0.4.20 - 03-Sep-2026 - Push Undoes in One Ctrl+Z

### Confirmed in Testing
v0.4.19's caveat was real: a push took **three** Ctrl+Z to unwind — restore-context, push,
enter-context — with the middle press teleporting the user back inside the group.

### The Fix
Checked against the Model docs first: `start_operation(op_name, disable_ui,
next_transparent, transparent)`. `transparent` merges an operation backwards into the
previous undo entry; `next_transparent` pulls the following entry forwards into it. When a
context was entered, the push op now starts as `('Deep Push Pull', true, true, true)` —
merging backwards into the enter step and pulling the restore step in behind it, so
enter-push-restore undoes as one action.

- `next_transparent` is deprecated and dangerous when a user action can slip in behind it.
  None can here: the restore runs synchronously in the same call before control returns.
- **Strictly conditional.** Without a context change those flags would merge the push into
  whatever the user did last, making their next Ctrl+Z silently eat two unrelated actions —
  so the plain two-arg form is kept for the no-entry path.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — conditional transparent chaining in `execute_push`

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.19 - 02-Sep-2026 - Root Cause: Outside-Context Edits Never Repaint

### The Clue That Cracked It
"If I hit escape it completes though?" — ESC at idle exits the tool, and a tool switch
forces SketchUp to regenerate the display. So the push was landing in the model at click
time all along; only the **render** was stale. Every symptom re-reads correctly under that:

- "Preview shows it but doesn't build it" — it did build; the screen didn't update.
- "Delays a second then builds it" — some other event forced a repaint.
- "Selecting invisible faces" — picks found the REAL (moved) geometry; the drawn box was
  the stale one. The v0.4.16 screenshot showed the highlight bigger than the box — that was
  read backwards at the time. The highlight was the truth; the box was the lie.

### Root Cause
`Face#pushpull` on entities inside a group/component **from outside its editing context**
changes the model but does not rebuild that instance's display cache. `invalidate_bounds`
(v0.4.15) refreshes only the bounding box, and `view.refresh` does not rebuild instance
caches either — which is why both earlier attempts changed nothing. The create tools never
hit this because they build into `active_entities`, the open context, which SketchUp always
repaints. Community guidance is blunt about outside-context edits: unsupported, artifact-prone.

### The Fix — Do What a User Does: Enter, Push, Leave
`na_drawn__execute_push` now opens the face's own context with `model.active_path=`
(SketchUp 2020+) before the operation, pushes, commits, then restores whatever context the
user was in (root or otherwise), falling back to root rather than ever stranding them
inside a group the tool opened. `active_path=` refuses to run inside an open transaction,
so the order is strict: enter → start_operation → pushpull → commit → restore. If entering
fails (old version, dead path), it falls back to the outside-context edit plus
`invalidate_bounds`, same as before.

### Caveat to Verify in Testing
Programmatic context changes may record their own undo steps around the push — check
whether undoing a push takes one Ctrl+Z or three. If three, the follow-up is operation
chaining, not a redesign.

### Retained
Every earlier fix in the saga was real and stays: `onReturn`/double-click existing at all
(0.4.15), the status-bar throttle (0.4.16), no InputPoint fallback mid-drag (0.4.17), state
containment + trace switch (0.4.18). They were necessary layers — this one was the cause of
the headline symptom.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — context-managed push (`execute_push` / `same_context?` / `restore_context`)

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.18 - 02-Sep-2026 - Push/Pull State Limbo (Audit, Not Guesswork)

### Method
Three rounds of fixes had been reasoned from screenshots and had not landed. This round
audited the code mechanically instead: nesting depth of every method, which Tool callbacks
the class actually owns versus inherits, and which states each callback can produce.

That found the limbo immediately.

### The Bug — a State the Tool Cannot Service
The audit showed **15 behavioural Tool callbacks still coming from `DrawnToolShared`**, a
mixin built around a three-stage machine: `:idle` > `:picking_b` > `:picking_depth`. The
shape tools sweep a rectangle before extruding; push/pull has no rectangle stage and **no
`:picking_b` branch anywhere in it**.

The inherited BKSP/DEL handler calls `na_drawn__step_back`, which demotes `:picking_depth`
to `:picking_b`. In that state push/pull is dead:

- `onLButtonDown` — `case @na_state` matches no branch, so clicks do nothing
- `onReturn` / double click — routed to `advance_from_b`, which is a stub returning false
- `onMouseMove` — the cursor override bails out, so the distance never updates
- `draw` — still not idle, so it keeps painting the push preview

Everything except ESC is inert, while the preview stays on screen. That is exactly the
reported "stuck in a weird limbo where you can effectively select invisible faces" — the
preview overlay persisting over geometry that is no longer being driven.

### The Fix — Contain the State Machine
- `na_drawn__ensure_known_state` snaps any state that is not `:idle` or `:picking_depth`
  straight back to `:idle`, and is called at every mouse and key entry point. Rather than
  audit every inherited path for respecting a state this tool lacks, the tool now refuses to
  sit in one.
- `na_drawn__step_back` is overridden: Backspace releases the grabbed face and returns to
  idle. A push either has a face or it does not — there is no half-retreat.
- `onReturn` and `onLButtonDoubleClick` are overridden so neither can be routed at a stage
  this tool does not have.
- Verified mechanically: nothing in the file sets `:picking_b`, the guard sits at 5 entry
  points, and all 51 methods are at class-body depth so every override genuinely wins over
  the mixin.

### Trace Switch
Diagnosing this from screenshots cost three wrong guesses. There is now a console trace:

```ruby
Na__InsertPrimatives.Na__PushPull__SetTrace(true)
```

Every grab, placement, refusal and state recovery prints with the state, distance, face id,
CTRL and axis lock it saw. The next question about this tool gets answered from a log.

### Retained from Earlier Rounds
`onReturn`/`onLButtonDoubleClick` existing at all (0.4.15), the status-bar throttle (0.4.16)
and removing the InputPoint fallback from the push cursor (0.4.17) are all still correct and
still in. None of them was the limbo.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — state containment, step_back / onReturn / double-click overrides, trace switch

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.17 - 02-Sep-2026 - The Actual Push/Pull Bug

### Read the Docs First This Time
Three rounds of fixes had not touched the cause. The Tool API documentation was read
properly before this one, and it both named the bug and turned up two facts worth recording.

### The Bug — an InputPoint Pick Hiding in a Fallback
`DrawnToolShared#na_drawn__update_cursor` ends with:

```ruby
resolved ||= na_drawn__input_point_position(view, x, y)
```

For the shape tools that line is harmless — the InputPoint is their normal cursor source
anyway. For push/pull it is the whole problem. Any frame where the ray-to-line solve returns
nil (a near-parallel view, the behind-camera guard tripping) silently **re-picks against
whatever face is under the cursor** and turns its inferred point into a push distance.

That is precisely the reported symptom: "the face selection remains active the whole time,
even when you're dragging, so you're accidentally selecting other faces." And because the
solve only fails on *some* frames, it read as intermittent stickiness rather than a
straightforward bug — which is what sent the previous three attempts chasing rendering and
caching instead.

Why the drawing tools felt perfect while this one did not now has a concrete answer, rather
than the guesses in v0.4.15 and v0.4.16.

### The Fix
The push tool now owns its cursor tracking outright:
- Once a face is grabbed, **nothing is picked again** unless CTRL explicitly asks for vertex
  inference.
- The distance is pure ray-to-line maths against the stored push direction.
- A frame that cannot be solved **keeps the previous distance** rather than inventing a new
  one from a stray pick.

Which is what the brief asked for: grab the face, follow the drag, place it where the user
stops. No intermediate picking.

### Two Facts from the Documentation Worth Keeping
1. **`onMouseMove`** — "Try to make this method as efficient as possible because this method
   is called often." Confirms the v0.4.16 status-bar throttle was worth doing on its own
   merits, even though it was not the cause here.
2. **`onKeyDown` has a known Return/Enter regression in SketchUp 2026.0 on Windows, fixed in
   2026.1** — and `onReturn` had its own regression in 2025.0, fixed in 2026.0. Enter is
   handled through `onReturn`, which is the path that works on 2026.0 and later. Worth
   knowing if Enter ever misbehaves again: check the point release before the code.
3. Screen coordinates changed from Integer to **Float** in SketchUp 2025.0. Nothing in this
   plugin depends on them being whole numbers, but it is worth knowing they are not.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — dedicated `na_drawn__update_cursor` with no pick fallback

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.16 - 02-Sep-2026 - Push/Pull Stickiness (v0.4.15 Follow-Up)

### What the Screenshot Settled
A hover highlight reported 27.97 m² and was drawn larger than, and offset from, the box it
belonged to — while the box itself rendered cleanly, with correct shading and a shadow.

That rules out the v0.4.15 theory. The **render was fine**; the **highlight** was wrong. Two
of the three fixes in v0.4.15 were aimed at a stale viewport that was not the problem, and
one of them actively made things worse.

### Bug 01 — The Cache Guard Could Not See a Moved Face
v0.4.15 added a hover cache keyed on `entityID` plus the transformation. But `pushpull`
**moves a face and keeps its id**, and the group transformation never changes — so after a
push the guard said "same face" and happily reused triangles cached from before it moved.
That is the offset blue overlay, exactly.

The fingerprint now includes a vertex position and the vertex count alongside the id and
transformation, so a face that has moved reads as different. Reading one vertex costs
nothing next to re-triangulating a mesh, so the performance win is kept.

### Bug 02 — Re-Picking Inside the Commit
v0.4.15 also re-hovered immediately after committing, to refresh the highlight without
waiting for a mouse move. That picks geometry SketchUp has not finished settling, in the
same event as the change, and caches a highlight of the old shape. Removed — the next mouse
move re-picks cleanly and is instant in practice.

### Bug 03 — view.refresh
Also from v0.4.15, and also removed. Forcing a full synchronous repaint from inside a click
handler costs more than it buys, and it was aimed at the render problem that turned out not
to exist. `invalidate` and `invalidate_bounds` stay — `invalidate_bounds` is cheap and still
correct for nested edits.

### Bug 04 — The Actual Stickiness
`na_drawn__update_status_text` called `Sketchup::set_status_text` **unconditionally on every
mouse-move event**, in every tool. That is a native UI call at mouse-move rate, composing and
pushing an identical string hundreds of times a second. It is now only sent when the composed
line actually differs.

This is the one that should be felt across the whole plugin, not just push/pull.

Side benefit: a transient warning is no longer wiped by the very next mouse move, because an
unchanged composed line is not re-sent over the top of it.

### Retained from v0.4.15
`onReturn` and `onLButtonDoubleClick` were genuinely missing and stay fixed.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — status text only sent on change
2. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — position-aware fingerprint, re-pick and refresh removed

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.15 - 02-Sep-2026 - Push/Pull Commit Bugs

### Reported
"Sometimes a second delay. Other times Enter or double-click doesn't close it at all. It
renders the preview of the extruded bit but doesn't build it, then delays and builds it.
When it gets stuck you end up in limbo selecting invisible faces."

Four separate defects, not one.

### Bug 01 — Enter Did Literally Nothing
SketchUp only routes Enter to `onUserText` when text is pending in the measurements box.
With an **empty** box it calls `onReturn` instead — and `onReturn` was implemented nowhere
in this plugin. So "drag, then press Enter" had no handler at all.

Galling detail: this exact routing rule is written up in the Profile Path Tracer devlog,
researched at the time, and then not applied here. `onReturn` now confirms the current
stage, which fixes Enter across **all six** tools, not just push/pull.

### Bug 02 — Double-Click Was Unhandled
`onLButtonDoubleClick` did not exist either. A double click delivers Down, Up, DoubleClick,
Up, so the first Down usually placed the shape already — but "usually" is what made it feel
random. It is now handled explicitly and is a no-op once the tool is back to idle.

### Bug 03 — The Invisible Faces
The push **was** working. A component definition caches its bounding box, and editing its
entities from outside its editing context does not reliably dirty that cache, so the model
held the new geometry while the viewport carried on drawing the old shape. Hovering then
picked geometry that was genuinely there but not being rendered — the "invisible faces",
and the "delay, then it appears" once something else forced a repaint.

Three fixes, all cheap and none with a downside for a single push:
- `Na__DeepPick__InvalidateDefinitions` walks the instance path innermost-first and calls
  `invalidate_bounds` on each definition. Innermost first because an outer definition's
  bounds depend on the inner ones already having been recomputed.
- The push operation no longer passes `disable_ui`. The create tools can afford it because
  they add to `active_entities`, which dirties the model on its own; suppressing the UI
  through a nested-definition edit is what leaves the viewport stale.
- `view.refresh` after commit, since `invalidate` only marks the view dirty and leaves the
  actual repaint until the next event.

### Bug 04 — The Stutter
Hover called `adopt_target` on every mouse move, and that triangulated the face through its
`PolygonMesh`, transformed every vertex to world and re-measured its area — all at
mouse-move rate. On any reasonably dense face that is exactly the "lagging a beat behind the
cursor" feel. The cache is now rebuilt only when the picked face actually changes, compared
on `entityID` plus the transformation.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — `onReturn` and `onLButtonDoubleClick`, benefiting every tool
2. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** — `InvalidateDefinitions`
3. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — hover cache guard, operation flags, forced redraw, re-hover after commit

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.14 - 02-Sep-2026 - Menu Registration Survives a Reload

### The Problem
Deep Push/Pull did not appear in Preferences → Shortcuts. Not a typo in the wiring — the
command was built and added correctly. The menu block sat inside
`unless file_loaded?(__FILE__)`, which means it only ever runs at SketchUp startup, and the
reloader only ever touched the modules folder. So a tool added mid-session had no menu
entry, and SketchUp keys shortcuts to the menu path — no entry, no shortcut.

That is a design flaw rather than an oversight: v0.4.10 added a hot reloader and then left
the one thing that most needs refreshing outside its reach. Every future tool would have
hit the same wall.

### Update 01 — Keyed, Idempotent Menu Registration
- The `file_loaded?` guard is gone. Each menu entry and separator now carries a permanent
  key in a registry held in a global — a global specifically because it has to survive this
  file being re-loaded, which a constant on the plugin module would not.
- Running the block again therefore adds only what is genuinely new and never duplicates,
  which matters because SketchUp cannot remove a menu item once added.
- Simulated the double-run: a second pass adds nothing, a pass carrying a new tool adds
  exactly one entry, and the submenu is created exactly once.
- **Caveat, stated rather than hidden:** an entry registered by a reload appends to the end
  of the submenu, since the API has no insert-at-position. It lands in its designed place on
  the next restart. Available immediately beats perfectly ordered.
- Keys are the permanent identity of an entry. Renaming one would make a reload add a
  duplicate alongside the original, so the comment in the loader says so.

### Update 02 — The Reloader Now Refreshes the Menu
- `Na__Reload__RootLoader` loads the root loader after the modules and reports how many new
  entries appeared, in both the console and the status bar.
- A `$na_insert_primatives_reloading` flag stops the loader re-requiring every module on the
  way through — the reloader has just done that — and stops it reloading the reloader from
  inside the reloader, which is a reentrancy knot with nothing to gain.

### Update 03 — Slash Removed from the Menu Text
`menu_text` was `"Deep Push / Pull"`. SketchUp builds the shortcut path with `/` as the
separator, so that would have read as two extra path levels in the shortcuts dialog. Now
`"Deep Push Pull"`. The status bar title and the popup button keep the slash — neither is a
menu path.

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — keyed menu registry, guard removed, reload-aware skips, menu text fix
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__PluginReloader__.rb`** — reloads the root loader and reports new menu entries

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.13 - 02-Sep-2026 - Deep Push/Pull + Arrow Key Axis Locking

### Summary
A sixth tool, in a new **Modify** section of the right-click menu: **Deep Push/Pull** works
on any face at any nesting depth, without opening the group or component first. And arrow
keys now lock an axis across every tool, drawing SketchUp's red / green / blue ray.

### Update 01 — Reaching Into Nested Geometry
- Native Push/Pull only sees faces in the current editing context: a face inside a group
  means double-clicking down to it first. `PickHelper#leaf_at` with `#transformation_at`
  hands back the deepest face under the cursor plus the accumulated transformation, which
  is everything needed to work on it in place.
- Hover highlights the face, click grabs it, drag pushes, click places. Press-drag-release
  works too.
- **The scale trap.** `Face#pushpull` takes a distance in the face's own local space, while
  the drag is measured in world. Inside a scaled component those disagree, and a push would
  overshoot by exactly the scale factor. Transforming the unit local normal gives a vector
  whose *length* is the scale along that direction, so `local = world / scale` corrects it.
  Verified numerically against uniform, non-uniform, mirrored and rotated-then-scaled
  transformations with tilted normals — all land within 1e-9 of the requested world travel.
- Faces inside locked groups are refused. Pushing a face in a definition placed more than
  once changes every copy, which is correct SketchUp behaviour rather than something to work
  around silently — so the instance count is counted on pick and called out in the status bar
  and the console.

### Update 02 — Distance Is Snapped, Not the Point
Every other tool rounds the cursor point onto the lattice. That is wrong here: a face normal
is rarely axis-aligned, so rounding a point on it gives ragged distances. The travel along
the push direction is snapped instead, which keeps clean 5mm pushes at any face angle. CTRL
still suspends it, and because the cursor then comes from the InputPoint, the push distance
becomes the projection of an inferred vertex onto the push axis — push a face until it is
flush with an existing corner.

### Update 03 — Arrow Key Axis Locking, Everywhere
- Right / Left / Up lock X / Y / Z following SketchUp's own colour mapping; the same arrow
  again releases, and Down always releases.
- A full-width coloured ray is drawn along the locked axis. Its span comes from
  `pixels_to_model` rather than a fixed model length — a fixed one would vanish to a dot on
  a site plan and shoot past the horizon on a detail.
- Each tool maps the arrows onto **its own** axis decision, so the key always means "this
  axis" without ever meaning nothing:
  - Shape tools — the axis names the plane it is normal to, so Up (blue Z) draws on plan.
  - Roofs — the axis is the ridge direction. Up is refused with a note, since a ridge
    cannot stand vertical.
  - Push/Pull — the axis is what the drag measures along.
- **What a lock means for push/pull.** `pushpull` only ever extrudes along the face normal,
  so a lock cannot redirect it. Instead it changes what the drag measures: lock to Z, drag
  1000, and the face is pushed far enough along its own normal to end up 1000 higher.
  Raising a sloped plane by a known vertical is a real gap in the native tool and this
  closes it. A face edge-on to the locked axis cannot travel along it at all, so the lock is
  refused rather than dividing by something close to zero.

### Update 04 — Preview
- The hover and push previews use the face's own `PolygonMesh` triangles rather than its
  outer loop, so concave faces and faces with holes shade correctly instead of being filled
  straight over.
- World-space triangles and loop are cached on pick rather than re-transformed every frame,
  which matters on a dense face during a drag.
- Original outline stays visible in blue while the pushed result draws in amber with
  connectors between them, and the distance label carries the axis colour when locked.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnDeepPick__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPushPullTool__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — Deep Push/Pull command and menu item, reload list
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — requires
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__PluginReloader__.rb`** — reload order
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`** — axis keys, labels, axis-to-plane map
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — axis colours and ray, triangle and loop drawing
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`** — arrow key handling, axis lock state, ray drawing, push/pull activation
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofTools__.rb`** — arrows drive the ridge direction
8. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — Modify section

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.12 - 02-Sep-2026 - Axis Pinning + CTRL Vertex Override

### Summary
Two changes to how the drag tools take input. A typed value now **pins one axis** and
leaves the rest on the mouse, instead of being broadcast to all of them. And holding
**CTRL** suspends the voxel grid for as long as it is down, handing the cursor over to
SketchUp's own inference so a drag can land on an existing vertex, midpoint or endpoint.

### Update 01 — Typed Values Pin One Axis
- Typing `350` used to broadcast to a 350 square. It now sets the width, **pins** it so the
  drag stops moving it, and leaves the height under the mouse. A second bare value pins the
  height and places the shape; a click places it with the height as dragged.
- `Na__DrawnVcb__ResolveAgainst` is strictly positional now — the single-token broadcast is
  gone. The click-to-place Cube and Plane modes keep their own broadcast parsers, so
  `1m` still makes a cube there. Only the drag tools changed.
- A comma makes an entry positional, which is what lets a specific axis be named:
  `,1610` pins the height and leaves the width dragging, `350,` does the reverse.
- **A bare value addresses the first axis still on the drag, not slot zero.** Caught while
  tracing the flow: with the width already pinned, a second `1610` would otherwise have
  landed back on the width and quietly overwritten the pin, so `350` then `1610` could never
  have pinned both. `na_drawn__align_single_token` shifts a comma-free entry to the first
  unpinned slot.
- Pins are shown two ways at once, because colour alone is easy to miss mid-drag: a pinned
  dimension is drawn in burnt orange **and** wrapped in brackets, `[350]`, in both the
  viewport labels and the status bar.
- **BKSP releases the newest pin** before it steps back a stage, so a mistyped lock does not
  mean abandoning the drag.
- Applies across all five drag tools: plane W/H, volume W/L/D, cylinder radius and height,
  roof plan sides and rise.
- Revise mode (typing straight after a shape is drawn) clears pins and stays strictly
  positional. There is no drag there, so "the axis still under the mouse" would mean nothing.

### Update 02 — CTRL Suspends the Grid for Vertex Snapping
- Held CTRL bypasses `Na__DrawnGrid__SnapPoint` entirely and routes the cursor through the
  InputPoint, so whatever SketchUp infers — a vertex, a midpoint, an endpoint inside a
  nested group or component — survives instead of being rounded onto the lattice. Release
  it and the 5mm grid is back. The grid remains the default and is never turned off.
- It applies to **every** pick: the anchor click, the second corner, the extrusion, and the
  cylinder radius. So a drag can start on one existing corner and finish on another at,
  say, 2.5 / 2.5 / 5.
- CTRL also overrides the locked-plane and depth pick-ray paths. Those are more predictable
  for free dragging, but they have no vertex inference to offer, which is the entire point
  of holding the key.
- Read from two sources: the mouse-event flags (authoritative during a drag) and
  `COPY_MODIFIER_KEY` in the key callbacks (catches a press or release while the mouse is
  still). The SKEXT-3890 double-fire that broke Tab rotation cannot bite here — this is a
  held flag, not a toggle. `activate` and `resume` clear it so a key-up missed while the
  window was away cannot leave it stuck on.
- The status bar swaps `Grid 5mm` for `Grid OFF — CTRL vertex snap` while it is held, and
  the InputPoint indicators are drawn so the inference being snapped to is visible.

### Verification
The token pipeline was simulated end to end before shipping, since none of this can be
exercised without SketchUp: pin-then-drag, second-value-moves-to-next-axis, `,1610` naming
an axis explicitly, relative pinning, BKSP release, and confirmation that a bare `350` no
longer touches the other axis. One JS-port artifact surfaced and was dismissed — Ruby's
`tokens[1]` past the end is `nil` and `ApplyToken` returns the live value for it, which JS
does not mirror.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — positional resolution, `NamedSlots`
2. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — pin state and helpers, single-token alignment, CTRL tracking and snap bypass, BKSP release, status text
3. **`Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — locked dimension colour and bracket rendering
4. **`Na__InsertPrimatives__DrawnPlaneTool__.rb`** — pin on type, hold for the second axis
5. **`Na__InsertPrimatives__DrawnVolumeTool__.rb`** — same across W/L/D
6. **`Na__InsertPrimatives__DrawnCylinderTool__.rb`** — pin radius and height, CTRL-aware radius snapping
7. **`Na__InsertPrimatives__DrawnRoofTools__.rb`** — pin plan sides and rise

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.11 - 02-Sep-2026 - Longer Segment Suffixes

### Update — "seg" Accepted Alongside "s" for Circle Segments
- `NA_DRAWN_VCB_SEGMENT_PATTERN` widened from `s` only to `(?:segments|segs|seg|s)`, so
  `24s`, `24seg`, `24segs` and `24segments` all set the cylinder segment count.
- Alternation is deliberately longest-first. With `s` leading, `24seg` would match the `s`
  branch and then fail on the leftover `eg` rather than falling through to the longer one.
- Hint text and the file header updated so both forms are discoverable from the tool itself.

### No Change Needed — "d" for Degrees on Roofs
Already supported since v0.4.9: `NA_DRAWN_VCB_ANGLE_PATTERN` is `(?:deg|d|°)`, so `35d`,
`35deg`, `35°`, `+5d`, `-2.5d`, `35 d` and `35D` all read as a pitch. The tool hint text
only advertised `35deg`, which is presumably why it looked missing — the hints and header
now show `35d` first.

### Token Routing Verified
All three token patterns were checked against each other to confirm nothing is swallowed by
the wrong reader: dimensions (`2400`, `2.4m`, `600cm`, `+100`, `-50`) match neither the
segment nor the angle pattern, `24`/`d600`/`600,300` fall through segment matching to
dimension parsing, and `2000mm` is never mistaken for an angle.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — widened segment suffix pattern
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnCylinderTool__.rb`** — hint and header text
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofTools__.rb`** — hint and header text

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.10 - 02-Sep-2026 - Self-Sizing Popup, Extensions Submenu, Hot Reload

### Summary
Housekeeping pass. The right-click popup now sizes itself to its own content, the six
loose Extensions entries collapse into one `Na__InsertPrimitives` submenu, and a
Reload Plugin Data item sits at the bottom of it.

### Update 01 — Popup Sizes Itself
- The dialog height had been a hand-maintained number, and adding the Roof section pushed
  Plane Faces and Exit Primitive Tool off the bottom of the window.
- Rather than bump the number again, the page now measures `document.body.scrollHeight` on
  load and hands it back through a `reportContentHeight` callback, and Ruby calls
  `set_size`. The window ends up exactly as tall as its buttons need plus clear space at
  the base, and it cannot silently clip again the next time an entry is added.
- Opens at a generous fallback height first so there is no clipped flash before the resize
  lands, and body bottom padding went from 12px to 18px.

### Update 02 — One Submenu Instead of Six Loose Entries
- All six tools moved into an `Na__InsertPrimitives` submenu under Extensions, grouped with
  separators: Insert Cube / the three drag tools / the two roofs / the reloader.
- Menu texts shortened now that the submenu carries the namespace — `Drawn Plane` rather
  than `Na__InsertPrimitives__DrawnPlane`.
- Registration switched from `UI.menu('Plugins')` to `UI.menu('Extensions')`, matching the
  house style used by Na__DevTools, Na__EdgeUtil and Noble3d Modelling Tools.

**SHORTCUTS NEED RE-BINDING.** SketchUp keys shortcuts to the menu path, so moving these
entries clears whatever was bound to the old top-level items. The bindings that were in
place before this change:

| Tool | Was |
|---|---|
| Insert Cube | `Ctrl+Alt+O` |
| Drawn Plane | `Ctrl+Alt+P` |
| Drawn Volume | `Ctrl+Alt+V` |

Re-assign once in Preferences → Shortcuts against `Extensions/Na__InsertPrimitives/...`.

### Update 03 — Hot Reload
- New `Na__InsertPrimatives__PluginReloader__.rb`, modelled on the reload managers in
  Noble3d Modelling Tools and Profile Path Tracer: `load` every module file, count what
  worked, report what did not.
- **Loaded separately from the main script, on purpose.** It requires nothing else in the
  plugin, so a module that fails to parse leaves the reloader intact — which is the one
  moment it is actually needed. Loading it through `Main__.rb` would have taken it down
  with everything else.
- `$VERBOSE` is nil-ed around each `load`. These modules define a lot of constants and Ruby
  warns on every redefinition, which would bury the real errors in the report.
- Files load in an explicit priority order, then anything unlisted alphabetically after it,
  so a newly added module still reloads even if nobody remembers to list it. Order matters
  less than it looks — reopening a class or module mutates the object already in memory, so
  an earlier file holding a reference to a later one still ends up with the fresh methods.
- A running tool holds a reference to the class object it was built from, so the reloader
  drops the active tool before reloading — but only when the active tool name marks it as
  one of ours, so an unrelated tool is never stolen.
- Quiet on success (status bar plus console summary), loud on failure (messagebox listing
  each file and error).

### Note — Dead File Found
`Na__InsertPrimatives__ContextMenu__.rb` is a deprecated no-op shim from v0.4.6. Nothing
requires it and the loader never listed it, so it has not been loaded since. It is skipped
by the reloader rather than being counted as a reloaded file. Safe to delete whenever.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__PluginReloader__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — Extensions submenu, shortened menu texts, reload command, separate reloader load
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — content-measured self sizing and extra base padding

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.9 - 02-Sep-2026 - Pitched and Hipped Roof Primitives

### Summary
Two roof tools join the drag family. Drag the plan rectangle on X,Y, then pull up in Z —
or type the pitch in degrees instead of a rise. **Pitched Roof** builds a gable, **Hipped
Roof** builds a hip; both come out as closed solids sitting on the shared voxel grid.

### Update 01 — Plan-Pinned Footprint, TAB Freed for the Ridge
- A roof has no plane decision to make, so the footprint is pinned to plan and the drag
  never infers a plane. The mixin's plane resolution moved behind an overridable
  `na_drawn__resolve_plane_key`; the roof base returns `:xy` and that is the whole change.
- The plane lock stays `:auto`, which matters: it keeps the InputPoint driving the cursor,
  so the footprint corners still snap to existing wall corners and edges rather than being
  projected blindly onto a drawing plane.
- That frees **TAB** for the decision that does matter on a roof — which way the ridge runs.
  Auto puts it along the longer side (right nine times in ten); TAB forces X or Y. The
  status-bar hint is now supplied by `na_drawn__tab_hint` so it tells the truth per tool.

### Update 02 — Ridge and Pitch Maths
- A gable ridge spans the full length at mid-span. A hip pulls each ridge end in by the same
  distance the roof rises over, which is what gives all four planes one pitch; ridge length
  comes out as `along - across`.
- A square plan collapses the two ridge ends onto one apex. Rather than special-casing the
  pyramid, coincident points are deduped out of each face loop, so one set of face
  definitions covers both — the trapezoids simply become triangles.
- Capping the inset at half the length keeps a ridge **forced onto the short side** from
  inverting; it degenerates to a rectangular pyramid instead, and both the status bar and
  the console say so rather than quietly handing back a different roof.

### Update 03 — Pitch Reporting Bug Caught Before Shipping
The maths was checked numerically (a JS port of the ridge, face, pitch and volume
functions) rather than trusted, since there is no Ruby CLI here to exercise it. Planarity,
per-face pitch, negative drags and volume all verified against independent formulas — the
pyramid case reproduces `base × h / 3` exactly, and a 35° round trip through
rise-and-back returns 35.00°.

That check found a real defect. The pitch run was originally `min(across, along) / 2` for
hips, which is correct for every normal hip but reports the **wrong pitch** on the
degenerate short-side case: it quoted 34.99° for a roof whose two large faces were actually
at 25.02°, and a typed `35deg` would have set those faces to 25°. The run is now
`across / 2` for both forms — the main slopes rise over exactly that distance whatever the
inset does, so the reported number always describes the faces you can see. As a bonus the
gable and hip branches collapsed into one line.

### Update 04 — Degrees in the Measurements Box
- A trailing `deg`, `d` or `°` makes a token an angle: `35deg`, `35°`, `35d`. Matched before
  the dimension pattern, which would reject the suffix rather than misread it.
- Relative angles work too — `+5deg` means five degrees steeper than what is on screen,
  because an angle token resolves against the live pitch while a length token resolves
  against the live rise. `+100` and `+5deg` therefore both mean what they look like.
- `6000,4000,35deg` at the plan stage goes straight to a finished roof. The footprint is
  applied before the angle is read, because a pitch is meaningless until the span it is
  measured over is settled.
- Typed pitches clamp to 0.5°–89.5°.

### Update 05 — Preview
- The preview draws the **same face loops the builder will use**, so what is on screen is
  what lands in the model — no second implementation to drift.
- Shaded roof planes in amber over the dashed plan footprint, the ridge picked out as a
  heavy line with the pitch labelled on it, and a summary card carrying plan size, rise,
  pitch and roof-mass volume.
- Roofs are built as closed solids (slopes, ends and a base face). Both forms are convex
  polyhedra, which is what makes the centroid test in `OrientFacesOutward` a correct way to
  turn every face the right way out without an adjacency walk.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofGeometry__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofTools__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — reload list, pitched and hipped roof commands and menu items
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — requires and architecture notes
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`** — `na_drawn__resolve_plane_key` and `na_drawn__tab_hint` hooks, roof mode switching
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — angle tokens
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — convex polygon fill, ridge line, roof summary card
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`** — degrees formatter
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — Roof section with both tools

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.8 - 01-Sep-2026 - Drawn Cylinder (Centre-Anchored)

### Summary
A third drag tool joins Drawn Plane and Drawn Volume. **Drawn Cylinder** takes the same
two-gesture shape as the volume tool — drag the radius, then drag the height — but the
anchor is the **circle centre** rather than a corner, so a column always stands on a
rounded voxel coordinate with the circle growing symmetrically about it.

### Update 01 — Centre Anchoring and Radius Snapping
- The anchor click snaps to the shared voxel lattice exactly as the other tools do; the
  circle is then built around it rather than away from it
  (`Na__DrawnGrid__BuildCirclePoints`).
- **The radius has to be snapped in its own right.** Snapping the cursor to the lattice is
  not enough: the radius is the diagonal between two lattice points, and a diagonal is not
  itself a grid multiple — a 5,5 travel is a 7.07 radius. It goes through
  `Na__DrawnGrid__SnapDistance`, so dragging gives clean 5mm steps and the VCB gives
  anything else.
- Base plane inference, TAB plane locking, step-back and revise-in-place all come free from
  the shared mixin — dragging on the ground gives an upright column, dragging on a wall
  gives one lying on its side.

### Update 02 — One Hook in the Shared Mixin
- `na_drawn__recalculate_sizes` previously wrote width and height inline. The last four
  lines moved into an overridable `na_drawn__apply_planar_travel(u, v)`, which is the only
  change the corner-anchored tools needed.
- The cylinder overrides it to read the same drag travel as a radius, and mirrors that
  radius back into the u/v sizes so every shared validity and extents helper keeps working
  untouched. `na_drawn__preview_points` is overridden too, so the draw extents cover the
  whole circle instead of one quadrant of its bounding box.
- `Na__DrawnGrid__OffsetRectPoints` renamed to `Na__DrawnGrid__OffsetPointsAlongNormal` —
  it now builds the far cap of a cylinder as well as a box, and the old name claimed it
  only handled four rectangle corners.

### Update 03 — Segments
- Circle segment count is a persisted setting (default 24, matching native SketchUp),
  clamped to 3–360, cycled 8/12/16/24/32/48/64/96 from a **Circle Sides** button that
  updates in place in the right-click popup.
- The measurements box takes `24s` as a whole entry at any stage, the way the native Circle
  tool takes a sides count. It is matched before dimension parsing so the trailing `s` is
  never mistaken for a unit suffix. Typed mid-drag the preview re-tessellates live; typed
  after a cylinder is drawn it rebuilds that cylinder.
- Geometry uses `entities.add_circle` rather than a hand-rolled polygon, so the result
  carries real curve metadata — the extrusion comes out softened and smoothed and stays
  editable as a circle rather than as loose segments.

### Update 04 — Radius / Diameter in the VCB
- A bare number is a **radius**, matching the native Circle tool so typed muscle memory
  carries over. A `d` prefix makes it a **diameter** — `d1200` for a 1200 dia column.
- The two compose with the relative arithmetic: `d+100` widens the live *diameter* by 100
  (so the radius moves 50), because with `d` in play the live value a relative entry acts on
  is the diameter. This is why the radius token is resolved by hand rather than through
  `ResolveAgainst`.
- `600,300` at the radius stage goes straight to a finished cylinder, mirroring the volume
  tool's `2400,1200,300`.
- The preview card always shows radius **and** diameter, so there is never any doubt about
  which number the box is holding.

### Update 05 — Cylinder Preview
- Filled circle via a triangle fan from the centre (rather than `GL_POLYGON`, so the fill is
  correct at any segment count), filled walls via a quad strip, blue for the circle stage and
  amber for the extrusion to match the volume tool.
- A dotted radius leader runs centre-to-perimeter with an `R###` label on it; the summary
  card carries dia × H, volume in m³ and the live segment count.
- Only the quarter-point verticals are drawn on the wall. One line per segment would be a
  thicket of 24-plus edges over the live model for no extra information.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnCylinderTool__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — reload list, `Na__InsertPrimitives__DrawnCylinder` command and menu item
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — require and architecture note
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`** — segment settings, circle point builder, circle area / cylinder volume formatters, offset helper rename
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — `24s` segment entries and the `d` diameter prefix
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — filled circle, filled cylinder, circle and cylinder summary cards
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGeometry__.rb`** — `CreateCylinder` / `RebuildCylinder` / `AddExtrudedCylinder`
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`** — `na_drawn__apply_planar_travel` hook, cylinder mode switching, segment cycling
8. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — Drawn Cylinder entry and Circle Sides cycle

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.7 - 01-Sep-2026 - Drawn Plane + Drawn Volume Click-and-Drag Tools

### Summary
Two new tools sit alongside the existing click-to-place Cube and Plane modes:
**Drawn Plane** sweeps out a rectangle, **Drawn Volume** sweeps out a rectangle and then
its extrusion. Both are Blender-style grid drawing — every pick lands on the shared
voxel lattice, so an anchor corner is always on a rounded grid coordinate and dragged
dimensions are always grid multiples. Shaded coloured previews with live dimension
labels follow the drag, and the measurements box overrides the dragged size at any point
with absolute values or `+`/`-` arithmetic.

### Update 01 — One Voxel Lattice for Every Tool
- New `Na__InsertPrimatives__DrawnGridSnap__.rb` owns the snap lattice, plane-axis maths
  and the settings that persist through `Sketchup.read_default` / `write_default`.
- `round_point_to_nearest_5mm` in `Main__.rb` now **delegates** to `Na__DrawnGrid__SnapPoint`
  rather than keeping its own copy of the rounding maths. A second copy would have drifted
  the moment the snap step or the drawing axes changed, and the whole point of the feature
  is that all four modes share one grid.
- Snapping is now expressed in the **model drawing-axes frame** (the approach already used
  by the EASP measurement tools), so a rotated axes tripod aligned to an angled wall gets a
  grid that follows the wall. With the default axes and a 5mm step the result is bit-for-bit
  what the old world-space rounding produced.
- Snap step is no longer hard-coded: 1 / 5 / 10 / 25 / 50 / 100 mm, cycled from the
  right-click menu, default 5mm, remembered between sessions.

### Update 02 — Drag State Machine (`DrawnToolShared__.rb`)
- `:idle` → `:picking_b` → (`:picking_depth`) with **both** gestures supported, matching the
  native Rectangle tool: a press that travels more than 6px before release completes the
  stage; anything shorter is treated as a click and leaves the stage open for a second click.
- The drawing plane is **inferred from the drag** — the axis the cursor travels least along
  becomes the plane normal. Dragging across a wall gives a vertical plane, dragging across
  the ground gives a horizontal one. A 0.6 ratio hysteresis stops a near-diagonal drag
  flapping between planes.
- TAB cycles an explicit lock: Auto → XY → XZ → YZ. Backspace steps back one stage,
  ESC clears the drag then leaves the tool on a second press.
- Three different cursor sources, each the most predictable one for its stage:
  InputPoint while inferring (with the anchor passed as a reference so axis inference from
  the anchor works in open space), pick-ray-to-plane intersection on a locked plane, and
  pick-ray-projected-onto-the-extrusion-axis for depth. The last one is what keeps depth
  dragging smooth over busy geometry instead of chasing whatever surface is under the cursor.

### Update 03 — Shaded Previews (`DrawnPreviewGraphics__.rb`)
- Built on the EASP measurement overlays: translucent filled face, solid border, green
  crosshair on the anchor.
- Blue for the 2D rectangle, amber for the extruded prism, so the two stages of the volume
  tool read differently at a glance.
- Dimension text sits **beside the shape** — a number on each edge it measures, plus a
  summary card at the far corner carrying W×H and area in m², or W×H×D and volume in m³.
- Labels are drawn with a one-pixel halo so they stay readable against both the white sky
  and dark geometry. Costs 5 `draw_text` calls per line; tune `NA_DRAWN_TEXT_HALO_OFFSETS`
  if that ever shows up in frame times.

### Update 04 — VCB Override with Arithmetic (`DrawnVcbArithmetic__.rb`)
- Absolute `2400`, relative `+100` / `-50`, and empty tokens that keep a dimension:
  `2400,1200` `+100,-50` `1200,` `2.4m,600mm`.
- A **single absolute** value broadcasts to every dimension (square / cube). A **single
  relative** value is applied to each dimension in turn instead, which grows the shape
  without squaring it off — `+100` on a 2400×1200 gives 2500×1300, not a 2500 square.
- Sign always stays with the drag, never with the typed number, so a typed size extends the
  way the drag was already heading.
- The anchor corner is untouched by any of this: it stays on the rounded voxel coordinate
  while the dimensions go wherever they are told. That split is the whole point.
- Parsing deliberately does **not** use `String#to_l`. `to_l` follows model units, so a bare
  `2400` in an imperial model would become 2400 inches; every other input path in this plugin
  documents bare numbers as millimetres and shares `NA_UNIT_CONVERSIONS_TO_MM`, so that
  contract is kept.
- Typing straight after a shape is drawn **corrects that shape in place** rather than leaving
  a wrong one behind (`RebuildPlane` / `RebuildVolume`). Revise mode disarms after 8px of
  deliberate mouse travel — the pixel test rather than a world distance so it is not
  zoom-fragile. Pattern lifted from the Profile Path Tracer VCB engine.
- SketchUp wipes the measurements box once `onUserText` has been handled, so the refreshed
  value is re-pushed from a 0.1s `UI.start_timer`.
- Digit and operator keys arm a typing flag so Backspace mid-entry is a typo fix rather than
  a stage step-back — the same collision the Path Tracer had to solve.

### Update 05 — Four-Mode Right-Click Menu and Mappable Hotkeys
- The popup now covers Cube / Plane / Drawn Plane / Drawn Volume with the running mode
  highlighted, and switches the active SketchUp tool where needed. All tool classes now
  include `Na__InsertPrimatives::PrimitiveModeSwitching` so the popup speaks one interface
  regardless of which tool raised it.
- Snap grid cycles **in place** without closing the popup, so 5mm → 100mm does not need four
  passes through right-click.
- Plane-face preference moved to module level so it survives switching tools and sessions.
- Two new top-level Plugins entries — `Na__InsertPrimitives__DrawnPlane` and
  `Na__InsertPrimitives__DrawnVolume` — each independently mappable in
  Preferences → Shortcuts. The original `Na__InsertPrimitives` entry keeps its exact menu
  text so any shortcut already bound to it still resolves.
- **Menu registration is guarded by `file_loaded?`, so the two new entries only appear after
  a SketchUp restart.** Until then the new tools are reachable from the right-click menu or
  from `Na__InsertPrimatives.Na__InsertPrimatives__DrawPlane` / `__DrawVolume`.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`**
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`**
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGeometry__.rb`**
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`**
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPlaneTool__.rb`**
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVolumeTool__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — reload list, two new commands and menu items
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — requires, snap delegation, shared plane-face preference, mode-switch mixin
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — four-mode menu, grid cycle, active-mode highlight

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.6 - 06-May-2026 - HtmlDialog Primitive Right-Click Menu

### Update — HtmlDialog-Only Right-Click Menu
- Replaced the native/global SketchUp context-menu approach with a dedicated `UI::HtmlDialog` popup triggered from the active primitive tool's right-click callbacks.
- Deprecated `Na__InsertPrimatives__ContextMenu__.rb` as a no-op shim because `UI.add_context_menu_handler` is unreliable for empty viewport space and clutters SketchUp's normal context menu.
- Removed `getMenu`/native menu wiring from `PrimitiveCubeTool`; right-click now uses the popup as the single source of truth for primitive options.
- Popup actions cover cube mode, plane mode, plane face enable/disable, and exiting the tool.

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`**
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__ContextMenu__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.5 - 10-Mar-2026 - Remove Imperial Units

### Update — Metric-Only VCB Input
- Removed `in`, `ft`, `yd` entries from `NA_UNIT_CONVERSIONS_TO_MM` hash.
- Simplified `NA_UNIT_SUFFIX_PATTERN` regex: `(mm|cm|m|in|ft|yd)?` → `(mm|cm|m)?`.
- Updated all comments and user-facing strings to reference `mm | cm | m` only.
- VCB label: `"Cube: single value or X,Y,Z (mm | cm | m | in | ft | yd)"` → `"Cube: single value or X,Y,Z (mm | cm | m)"`.
- Activate console output: `"Units: mm cm m in ft yd"` → `"Units: mm cm m"`.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.4 - 10-Mar-2026 - 4-Step Rotation + Tab Double-Press Fix

### Research Findings — Tab Double-Press
Using `onKeyUp` alone caused Tab to require a double press. Root cause: SketchUp's focus
management consumes the `onKeyUp` event on alternating presses for certain keys (same mechanism
documented for the Alt key in bug report SKEXT-3890). The fix is `onKeyDown` with a
`@key_tab_held` guard that prevents acting on the SKEXT-3890 double-fire and also prevents
acting on typematic repeats. `onKeyUp` is kept solely to reset the held flag.

### Update 01 — Tab Double-Press Fix
- Replaced `onKeyUp`-only handler with `onKeyDown` + `onKeyUp` key-state pattern.
- `@key_tab_held` flag: set to `true` on first `onKeyDown`, reset to `false` on `onKeyUp`.
- `onKeyDown` only acts when `@key_tab_held` is `false` (key transitioning from up → down).
- Suppresses both SKEXT-3890 double-fire and typematic repeats with no timer hacks.

### Update 02 — 4-Step Rotation Cycle
- Replaced boolean `@rotated` toggle with integer `@rotation_step` (0-3, wraps at 4).
- Each Tab press advances one step: 0° → 90° → 180° → 270° → 0°.
- `@last_rotation_state` now stores an integer step (was boolean).
- `Na__Preview__BuildCubeCorners` updated with full 4-case rotation using CCW rotation math.
- `Na__Preview__DrawCubeBox` signature updated to pass `rotation_step`.
- Status bar now shows current degree value: `"Rotation: 90° [TAB to rotate]"`.
- `NA_ROTATION_STEPS = [0, 90, 180, 270]` constant added for display lookup.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__KeyboardHandlers__.rb`**
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__3dPreviewGraphics__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.3 - 10-Mar-2026 - Keyboard Handlers Extraction

### Update — Keyboard and VCB Logic Extracted to Dedicated Mixin
- Created `Na__InsertPrimatives__KeyboardHandlers__.rb` as a Ruby mixin module (`module Na__InsertPrimatives::KeyboardHandlers`).
- Included into `PrimitiveCubeTool` via `include Na__InsertPrimatives::KeyboardHandlers`.
- Mixin has full access to the host class instance variables (`@rotated`, `@cube_size_x/y/z`, etc.) at runtime.
- Moved from `Main__.rb` into the mixin:
  - `NA_ROTATION_KEY = 9` constant
  - `onKeyUp` key handler
  - `enableVCB?` callback
  - `onUserText` VCB input handler
  - `na_key__update_status_text` private helper (renamed from `Na__Primitive__UpdateStatusText` to lowercase to avoid Ruby constant-lookup ambiguity when called without `()`)
- `activate` and `resume` in `Main__.rb` updated to call `na_key__update_status_text()`.
- Added `require_relative 'Na__InsertPrimatives__KeyboardHandlers__'` to `Main__.rb`.
- Updated MODULE ARCHITECTURE comment in `Main__.rb` header.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__KeyboardHandlers__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.2 - 10-Mar-2026 - Rotation Key: Shift → Tab

### Research Findings
Three reasons Shift rotation never worked:
1. **Wrong constant**: `COPY_MODIFIER_KEY` = Ctrl on PC, not Shift. Shift is `CONSTRAIN_MODIFIER_KEY`. The code never matched a Shift press.
2. **SKEXT-3890 double-fire regression**: `onKeyDown` fires twice per press on Windows since 23.1.340. A toggle would turn on then immediately off. Still open and unresolved as of 2026.
3. **VCB interference**: With `enableVCB?` returning `true`, pressing Shift while typing in the VCB (e.g. uppercase "2M") would trigger the rotation toggle mid-input.

### Fix Applied
- Replaced `onKeyDown` with `onKeyUp`. `onKeyUp` fires exactly once per key release and is unaffected by SKEXT-3890.
- Changed rotation key from `COPY_MODIFIER_KEY` (Ctrl) to Tab (raw key code `9`). The SketchUp Ruby API does not export `VK_TAB`, so the raw integer is used.
- Tab does not send characters to the VCB, is unassigned by default, and eliminates all three issues.
- Added `NA_ROTATION_KEY = 9` class constant inside `PrimitiveCubeTool` for readability.
- Updated all user-facing hint text: `"SHIFT to rotate"` → `"TAB to rotate"`.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.2.4 - 10-Mar-2026 - Preview Graphics Extraction + Visual Tweaks

### Update 01 — Extract Rendering to Dedicated Module
- Created `Na__InsertPrimatives__3dPreviewGraphics__.rb`.
- Moved `Na__Primitive__DrawCrosshair` → `Na__Preview__DrawCrosshair(view, cursor_pos, arm_size)` (stateless, parameters only).
- Moved `Na__Primitive__BuildCubeCorners` → `Na__Preview__BuildCubeCorners(origin, sx, sy, rotated)` (stateless, parameters only).
- Moved `Na__Primitive__DrawCubePreview` → `Na__Preview__DrawCubeBox(view, origin, sx, sy, sz, rotated)` (stateless, parameters only).
- `Na__Preview__BuildCubeCorners` is now shared by both the preview renderer and the geometry engine (`CreateCubeGeometry`, `RegenerateCube`).
- `Main__.rb` `draw` method delegates entirely to the graphics module; no rendering logic remains in the tool class.
- Added `require_relative 'Na__InsertPrimatives__3dPreviewGraphics__'` to `Main__.rb`.
- Updated module architecture comment in `Main__.rb` header.

### Update 02 — Preview Box Visual Tweaks
- Line width: `1` → `2` (thicker).
- Colour: `Color(0, 220, 255, 180)` → `Color(0, 160, 200, 210)` (darker teal, slightly more opaque).

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__3dPreviewGraphics__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.2.3 - 10-Mar-2026 - Rotation Toggle + VCB Single-Value

### Update 01 — Shift-Key 90° Z-Rotation Toggle
- Added `@rotated` and `@last_rotation_state` instance variables to `PrimitiveCubeTool`.
- Added `onKeyDown` handler: pressing Shift toggles `@rotated` between `false` (0°) and `true` (90° CCW around Z).
- Added `Na__Primitive__UpdateStatusText` private helper — keeps the status bar in sync with rotation state; called from `activate`, `resume`, and `onKeyDown`.
- Added `Na__Primitive__BuildCubeCorners(origin, rotated)` private helper — single source of truth for all corner geometry. When `rotated` is `true`, the +X axis maps to +Y and +Y maps to −X (90° CCW).
- Refactored `Na__Primitive__DrawCubePreview`, `Na__Primitive__CreateCubeGeometry`, and `Na__Primitive__RegenerateCube` to all delegate corner calculation to `Na__Primitive__BuildCubeCorners`.
- `@last_rotation_state` is stored at placement time so VCB-triggered regeneration rebuilds the cube with the same orientation it was originally placed in.
- Live preview wireframe reflects rotation in real-time as user toggles.

### Update 02 — VCB Single-Value Broadcast
- Updated `Na__VcbInput__ParseDimensions` to accept 1 token or 3 tokens.
  - 1 token: value is broadcast to all three dimensions (e.g. `"1m"` → 1000mm × 1000mm × 1000mm).
  - 3 tokens: unchanged X,Y,Z behaviour.
  - Any other count raises `ArgumentError` with a clear message.
- Updated VCB label to `"Cube: single value or X,Y,Z (mm | cm | m | in | ft | yd)"`.
- Updated file header comment in `VcbFunctions__.rb` to document single-value mode.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**

### Status: IMPLEMENTED

# =============================================================================
## Version 0.2.2 - 10-Mar-2026 - Preview + VCB Multi-Unit Support

### Update 01 — 3D Ghost Cube Preview
- Added `Na__Primitive__DrawCubePreview` private method to `PrimitiveCubeTool`.
- Draws a dashed cyan wireframe box at the snapped cursor position in real-time using `view.draw(GL_LINES, edge_points)`.
- Preview dimensions reflect the current `@cube_size_x/y/z` stored in the tool, updating immediately after VCB input.
- Crosshair drawing extracted into `Na__Primitive__DrawCrosshair` private method to keep `draw` clean.

### Update 02 — VCB Multi-Unit Input Module
- Created `Na__InsertPrimatives__UserInput__VcbFunctions__.rb` loaded via `require_relative` from `Main__.rb`.
- Unit conversion constants: `NA_UNIT_CONVERSIONS_TO_MM` (mm, cm, m, in, ft, yd).
- `Na__VcbInput__ParseSingleDimension(str)` — parses a single token with optional unit suffix; bare numbers default to mm.
- `Na__VcbInput__ParseDimensions(text)` — splits comma-separated input, delegates each token to `ParseSingleDimension`, returns `[x, y, z]` in SketchUp internal lengths.
- `Na__VcbInput__UpdateDisplay(x, y, z)` — sets VCB value and updates label to `"Cube X,Y,Z (mm | cm | m | in | ft | yd)"`.
- `onUserText` in `PrimitiveCubeTool` refactored to call `Na__VcbInput__ParseDimensions`; error messages surface the `ArgumentError` message directly.
- `update_vcb_display` instance method removed; all display calls now go through `Na__VcbInput__UpdateDisplay`.
- Private geometry helpers renamed to `Na__Primitive__*` convention: `Na__Primitive__CreateCubeGeometry`, `Na__Primitive__RegenerateCube`.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================
## Version 0.2.0 - 10-Mar-2026 - Plugin Modularisation

### Update 01 - Restructure into Loader + Modules Pattern
- Migrated from a single flat file to a loader + modules subdirectory architecture.
- Pattern mirrors the `Na__WindowConfiguratorTool` structure for consistency.
- The plugins root now contains only the loader; all logic lives under the modules folder.
- Future features can be added as individual `.rb` files inside the modules folder and loaded via `require_relative` in `Main__.rb`.

### Files Added:
1. **`Na__InsertPrimatives__Loader__.rb`** (plugins root)
   - Handles path setup, `require` of `Main__.rb`, `UI::Command` creation, and Plugins menu registration.
   - Guards against double-loading with `file_loaded?` / `file_loaded`.
2. **`Na__InsertPrimatives__Modules__\Na__InsertPrimatives__Main__.rb`**
   - Contains `Na__InsertPrimatives` module, `PrimitiveCubeTool` class, grid-snapping helper, and `Na__InsertPrimatives__InsertCube` entry point.
   - No startup wiring — all UI registration delegated to the loader.

### Files Removed:
1. **`Na__InsertPrimatives__Main__.rb`** (plugins root)
   - Deleted; replaced by the loader + modules structure above.

### Status: IMPLEMENTED

# =============================================================================
