# Na__ProfileTools__ProfilePathTracer - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================

## Profile Path Tracer - v1.6.0 - 31-Aug-2026 - Editable Insertion Point + On-Disk File Rename

### Summary
Two Edit Profile tab additions, both aimed at the same annoyance: a profile captured in a
hurry is stuck with whatever origin and whatever filename it was born with.

1. **Insertion point is now editable and saved.** The same pick-a-vertex control the Apply
   Profile tab has, but pointed at the library file rather than at one placement. Pick a
   vertex, press **Save Changes**, and that point becomes the profile's own 0,0 — for the
   Gallery, for every future placement, and for anything that reads the file. The Apply tab's
   per-placement override is untouched and still works exactly as before; this just fixes the
   profiles whose stored datum was wrong from the start, so it stops needing correcting on
   every single use.

2. **The data file can be renamed from inside the dialog.** A **Data File** field with a
   **Rename File** button, so a `TEMP__` or `Z-RENAME__` placeholder can be given its real
   library name without leaving SketchUp, and without the delete-and-re-export dance that was
   the only alternative.

### Why the insertion point is a translation, not a new field

The datum could have been stored as an offset the consumers apply at read time. It is not —
picking a vertex **subtracts that point from every stored coordinate**, exactly as the 2D
preview already does when it shows a custom datum.

That choice is what keeps the change small. Nothing gains a schema field, so the Gallery
thumbnails, the Apply preview, the placement engine and Dynamic Regeneration all pick the new
origin up with no code changes at all — they were already drawing whatever the file said. The
profile's shape and size never change; only its position relative to 0,0 does.

The equivalence that matters — *what you previewed is what got written* — is checked directly
rather than by eye: rendering the original with a pending offset and rendering the rewritten
file with no offset produce the same picture for every pickable vertex of every profile in
the library (max divergence 1.8e-14 mm, i.e. float dust).

### Coordinate map

The two geometry blocks store the same section on different axis names, so a datum move has
to touch both or they drift apart:

| Block | Field | Moved by |
|---|---|---|
| `Na__Asset__Profile2D` | `PosY_mm` / `PosZ_mm` | offset Y / offset Z |
| `Na__Asset__Mesh3D` | `PosX_mm` / `PosY_mm` | offset Y / offset Z |
| `Na__Asset__Mesh3D` | `PosZ_mm` | untouched — the section is flat |
| `Na__Asset__Mesh3D` `BoundingBox` | `MinX`/`MaxX`, `MinY`/`MaxY` | offset Y, offset Z |

Edges are stored as vertex-id **pairs** and faces as id loops, so neither needs touching — a
translation changes no connectivity, no winding and no length, and length is what edge styling
is matched on. Coordinates are rounded to 6 dp on the way out, the precision the exporter
writes: without it, subtracting a vertex from itself lands on `1.42e-14` rather than `0.0` and
the datum marker sits a hair off the vertex that was just clicked.

### Op order is load-bearing

A save can carry a datum move **and** a mirror at once, because Flip Profile now carries any
pending pick rather than silently discarding it. The datum moves **first**: the mirror is
taken about Y = 0, which *is* the datum, so moving it first mirrors about the point the user
chose. The other order would mirror about the old origin and then translate by an offset
measured before the mirror — landing the shape somewhere neither op asked for.

### What this does to geometry already in the model

Nothing immediately, and something later — which is why the panel says so, in orange, at the
moment a pick is pending rather than buried in a tooltip:

- Placed runs are baked geometry. They do not move.
- Runs with **Dynamic Regeneration** on **will** move to match the next time they rebuild,
  because `Na__RegenEngine` re-reads the library file by key.
- A run carrying its own `OriginOffset` had that datum measured in the *old* coordinate space,
  so it no longer names the same point and wants re-picking — the same caveat Flip Profile has
  always carried.

This is inherent to editing a library asset in place, not a defect of this feature. It is
stated plainly instead of being smoothed over.

### Rename: what it is and what it deliberately is not

Lifted from the Component Editor Tools' on-disk rename for `.skp` library files — same
sanitise, same collision guard, same "return the new path" contract.
*(@delegate: `Na__ComponentEditorTools__LibraryManager__Editor__.rb`)*

The profile **code** (`Na__Asset__Code`) is untouched. That is what placed traces store in
their dictionary and what Dynamic Regeneration resolves against, so **renaming the file cannot
orphan geometry already in a model** — the one thing that would have made this feature not
worth having. The panel says so under the field.

Guards, in order: the shared `Na__EditProfile__LibraryPaths` traversal check; a re-parse
confirming the file still holds the profile the dialog is showing (a mismatch means dialog and
disk have diverged and the request is stale); `File.basename` on the input, so a pasted path or
a typed `..\` lands in the library folder and nowhere else; the exporter's own character class,
so a renamed file is indistinguishable from a freshly captured one; and a collision refusal, so
a rename can never overwrite another profile. A pure re-casing of the same file is allowed
through, since Windows reports that as a collision with itself.

The sibling `.bak` travels with its profile. A rollback point left under the old name points at
a file that no longer exists, which is exactly the wrong thing to find when you go looking for
one — and if a `.bak` already exists under the new name it is left alone and reported, rather
than a recovery artefact being destroyed to tidy up a stale name.

Rename is **not** in the danger zone, and takes no confirmation gate: it changes what a file is
called, never what it contains, and it is undone by renaming back. Unlike re-capture and
delete, there is nothing to lose to a mis-click.

### Files

| File | Change |
|---|---|
| `32__System__EditProfileMode/…__DatumWriter__.rb` | **new** — the translation, and the payload reader |
| `32__System__EditProfileMode/…__FileRenamer__.rb` | **new** — sanitise, guard, rename, patch `meta.fileName` |
| `32__System__EditProfileMode/…__MetaWriter__.rb` | carries `originOffset`; datum-then-mirror order; combined status message |
| `32__System__EditProfileMode/…__UiSystem__MainUiLogic__.js` | insert-point bar, vertex picking, Data File row |
| `32__System__EditProfileMode/…__UiSystem__Bridge__.js` | rename dispatch + receive |
| `01__AppCore/…__DialogManager__.rb` | `na_profilepathtracer_rename_profile_file` callback |
| `01__AppCore/…__Main__.rb` | requires the two new modules |
| `03__Style__AppStylesheets/…__EditProfile__.css` | rename row, datum bar, pending-change warning |

Rename returns no bootstrap, unlike delete: the profile key is unchanged, so patching the one
record keeps the user in the profile they were mid-edit on instead of resetting the Gallery
selection to the library default.

# =======================================================================================

## Profile Path Tracer - v1.5.0 - 30-Aug-2026 - Profile Hot Swap (retarget a placed trace)

### Summary
A placed Profile Trace can now have its **profile swapped without being rebuilt by hand**.
Right-click any trace (or any part of one) and pick *Swap Profile...*, or use the new
**Swap Profile** button in the Gallery toolbar or the Apply Profile actions row. The dialog
binds the trace, routes to the Gallery, and the next card you click rebuilds that trace
along its existing helper path with the new profile. You land back on Apply Profile with the
trace still bound, so the insert point, rotation and mirrors can be corrected and applied
with a new **Regenerate Trace** button — the "swap the gutter, then nudge its datum" loop
in two clicks instead of delete-and-retrace.

Multi-select is supported for the swap: select several assemblies, pick once, all of them
rebuild.

### Why this was thin — the hard part was already built

Dynamic Regeneration (v1.2.0) had already made the Helpers linework the authoritative path
and given `Na__RegenEngine` the job of rebuilding the swept solid from whatever `ProfileKey`
the parent dictionary carries. A hot swap is therefore *"rewrite one dictionary value, then
regenerate"* — no new geometry code, and every existing guarantee comes along for free:
legacy path frames, multi-run chains, seam cleanup, shell orientation, fingerprint stamping
and observer re-attach.

The new `Na__SwapEngine` is a coordination layer, not a geometry engine.

### What carries over, and what deliberately does not

| Stored value | On swap | Why |
|---|---|---|
| `RotationStep`, `ToggleStates` | **kept** | Path-relative — a 90° roll and a Y-mirror still mean the same thing on a different section |
| `OriginOffset` (insert point) | **reset** | The datum was picked in the OLD profile's PosY/PosZ millimetre space. Carrying it to a different shape would silently misplace the run. Matches what the Apply tab already does when the active profile changes |
| `StartPoint`, `PathPoints`, Helpers linework | **untouched** | The path is the whole point of the swap |
| `ReverseDirection` | **not swappable** | Reverse is baked into the assembly's own transformation at build time (a Z mirror about the plane through `bounds.max.z`). Re-applying it later would mirror about a *different* plane and jump the assembly's position. The Reverse button is disabled — not hidden — while a trace is bound, with the reason in its tooltip |
| `SchemaVersion` | **never rewritten** | It is what tells `Na__RegenEngine` whether an assembly was swept with the legacy right-handed frame. Bumping it would mirror geometry already standing in a model (the v1.3.0 hazard) |

### Failure handling

The dictionary patch and the rebuild are separate model operations — the rebuild opens its
own *transparent* one, so both land as a single undo step. That leaves a window in which the
stored key could outrun the geometry, so:

- the incoming key is validated against the library **before** any assembly is touched;
- a trace whose Helpers group is missing or empty is rejected by a pre-flight check;
- a rebuild that still fails **rolls the dictionary and the group name back**, and the trace
  is reported as skipped rather than left claiming a profile it does not have.

On a multi-trace swap each assembly is handled independently: one bad trace is reported by
id and reason, the rest still swap. Freshly copied assemblies that still share a
`ProfileTraceId` (until the RegenSweep re-stamps them) would collapse to a single target,
so the bind says how many were left out instead of silently applying to one of them.

### The journey, and why it spans two tabs

`Na__ProfileTools__SwapController` owns it, because it belongs to neither tab:

1. **Bind** — Ruby reports every distinct trace the model selection touches (a descendant
   such as the SweptSolid or a face inside it resolves up to its parent, so precise
   selection is not required).
2. **Armed** — the Gallery shows a pick banner naming the bound trace and the grid takes an
   armed style. A card click now means *swap to this*, not *select this*.
3. **Bound** — the swap runs, and Apply Profile is routed to with the trace still bound.

State is addressed by `ProfileTraceId`, never by object reference, and Ruby re-resolves every
id from the model at swap time — so clicking around, changing the selection or undoing
between arming and picking cannot leave a stale binding pointing at the wrong assembly.

Bound state deliberately survives step 3: the insert point is the setting most often worth
correcting straight after seeing the new profile in place, and re-picking the trace in the
model to do it would be busywork.

### Regeneration is manual, never automatic

Moving the insert point, changing rotation or flipping a mirror while bound marks the panel
dirty ("Unapplied changes — click Regenerate Trace") and changes **nothing in the model**.
Each rebuild is a full follow-me sweep and its own undo entry, so firing one on every stray
vertex click would be both slow and destructive to the undo stack.

### Fixed along the way

**Advanced Configuration no longer snaps shut.** The controls panel is re-rendered on every
state change, and the `<details>` disclosure holding the rotation pills and mirror toggles
was collapsing under the very control the user had just clicked inside it. Its open state now
lives in UI state and is restored on every render.

**Tab modules no longer stack duplicate event subscriptions.** Gallery and Apply Profile both
subscribed to the `Na_AppContext` bus on *every* mount, so handlers accumulated one set per
tab visit. Both now guard with a one-shot flag.

### Known limitation

Undoing a swap restores the geometry, the dictionary and the fingerprint correctly (all one
operation), but the dialog's bound-trace strip is not notified and will still name the
post-swap profile until the trace is re-armed with the Swap Profile button.

### Files Touched

| Path | Change |
|---|---|
| `31__System__ApplyProfileMode/Na__ProfileTools__ProfileSwapEngine__Main__.rb` | **NEW.** `Na__SwapEngine` — selection resolution, dialog bind payload, validated swap execution with per-trace rollback, generated-name maintenance |
| `01__AppCore/Na__ProfileTools__AppCore__SwapController__.js` | **NEW.** `Na__ProfileTools__SwapController` — bind / armed / bound state machine, tab routing, dirty marking, Ruby receive handlers |
| `03__Style__AppStylesheets/Na__ProfileTools__UiFeature__Styles__ProfileSwap__.css` | **NEW.** Gallery pick banner + armed grid state, Apply Profile bound-trace strip |
| `02__AppData/Na__ProfileTools__AppData__DataSerializer__.rb` | Added `Na__DataSerializer__UpdateParentPlacement` — patches only the placement keys a swap may touch, never `SchemaVersion` / `StartPoint` / `ProfileTraceId` / `DynamicRegenEnabled` |
| `01__AppCore/Na__ProfileTools__AppCore__ContextMenuHandlers__.rb` | Multi-selection resolution; new *Swap Profile...* item (the only multi-select item — the per-assembly items stay single-selection); removed the now-unused single-parent resolver |
| `01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | `Na__Dialog__ArmProfileSwapFromSelection` (context-menu entry point, opens the dialog when closed and parks the payload for the bootstrap handshake), `Na__Dialog__Visible?`, `bind_swap_target` + `apply_profile_swap` callbacks |
| `01__AppCore/Na__ProfileTools__AppCore__Main__.rb` | Requires the swap engine |
| `01__AppCore/Na__ProfileTools__AppCore__PluginReloader__.rb` | SwapController added to the JS asset manifest |
| `30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__MainUiLogic__.js` | Swap toolbar button, pick banner, armed grid class, card-click interception, subscription guard |
| `31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js` | Bound-trace state mirror, placement adoption on mount and on result, dirty marking, swap / regenerate / unbind handlers, advanced-config open state, subscription guard |
| `31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__Events__.js` | Wiring for the bound-trace controls and the advanced-config disclosure |
| `33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js` | Bound-trace strip, armed notice, Swap Profile + Regenerate Trace buttons, Reverse disabled while bound |
| `35__System__SettingsMode/Na__ProfileTools__AppUtils__SettingsTab__UiLogic__.js` | Dynamic Regeneration description mentions Swap Profile |
| `03__Style__AppStylesheets/Na__ProfileTools__CoreUi__Styles__Index__.css` | Imports the new stylesheet |
| `Na__ProfileTools__UiLayout__.html` | Loads SwapController after ProfileStore, before the tab modules |

# =======================================================================================

## Profile Path Tracer - v1.4.0 - 28-Aug-2026 - VCB Typed Lengths (+/- arithmetic)

### Summary
The interactive path tool now takes **typed lengths through the SketchUp measurements
box**, native-Line-tool style, closing the "you can only get accurate lengths by tracing
existing geometry" gap. While tracking a direction, `2500` places the waypoint at exactly
2500; `+100` / `-100` place it at the live tracked length ± 100 (drag to the wall corner's
inference, type `+100`, get the 10.1 m gutter run). With the cursor still resting on a
point just placed, typed values act on the **last committed segment** instead — `+100`
pushes it 100 further along its own direction (click the corner first, then overshoot),
and a bare number re-lengths it, fixing a sloppy click after the fact. Repeated typing
keeps revising until the mouse makes a deliberate move. Enter on an empty box, right-click
and double-click still finish the path exactly as before.

### VCB pitfalls this had to be built around (researched, not guessed)

The routing and parsing rules were confirmed against working implementations already in
the Plugins folder — MultipleOffsetTool (same author), TIG's ExtrudeTools, Fredo's
bezierspline — before any code was written:

1. **Enter routing.** With typed text pending, SketchUp delivers `onUserText` and never
   `onReturn`; with an empty box it delivers `onReturn`. The tool previously acted on the
   raw `VK_RETURN` inside `onKeyDown`, which would have finished the path before the typed
   length ever arrived. That handler is deleted — `onReturn` alone finishes on bare Enter.
2. **Backspace collision.** Backspace is the tool's waypoint-undo, but mid-entry it is the
   user fixing a typo. `onKeyDown` sees every key (Fredo's whole shortcut system relies on
   it), so digit/operator keys arm a typing-mode flag and Backspace/Delete pass through to
   the VCB while it is set. The flag clears on Enter, click, ESC and tool resume — the
   same lifetime SketchUp gives the pending text itself.
3. **Parsing.** `String#to_l`, never `to_f` — model units, `mm`/`m`/feet-inch suffixes and
   the locale decimal separator all behave exactly as in native tools. Parse failure beeps
   with a hint instead of raising.
4. **SketchUp wipes the VCB after `onUserText`.** The refreshed value is re-pushed from a
   0.1 s `UI.start_timer` (the rearm trick lifted from MultipleOffsetTool).
5. **Stale cursor after a typed placement.** The mouse is still wherever it was left —
   usually *behind* the new waypoint. Three guards: the preview drops the rubber-band tail
   while revise mode is armed; finishing ignores the stale cursor point (no phantom
   backward segment on Enter); and a screen-pixel test (not a zoom-fragile world distance)
   decides whether the cursor defines a genuine new direction before typed input switches
   back from revise-last-segment to place-along-direction.

### Live measurements display

`SB_VCB_LABEL` reads "Length"; the value tracks the live segment length on every mouse
move, falling back to the last committed segment when idle — so the base a relative `+100`
adds to is always the number sitting in the box. This is what lets "the VCB knows the wall
is 10 m" work: snap the cursor to the far corner, read 10000, type `+100`, get 10100.

**Trade-off:** the VCB previously set the crosshair size (rarely used); typed lengths now
own the box. Crosshair stays at its 300 mm default.

### Files Touched

| Path | Change |
|---|---|
| `31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PathSelectionTool__.rb` | VCB typed-length engine: entry-key shadow tracking, Enter re-routing, `to_l` parsing with +/- arithmetic, live-direction vs revise-last-segment dispatch, revise mode with pixel-move disarm, live VCB value display + rearm timer, stale-cursor guards in preview and finish |

# =======================================================================================

## Profile Path Tracer - v1.3.0 - 28-Aug-2026 - WYSIWYG Path Frame (mirrored-build root cause fix)

### Summary
Every profile this plugin has ever swept was built as the **mirror image of what the 2D
dialog shows** — the long-standing "profiles always feel back to front, I always end up
hitting Reverse" experience. Building the pre-drag datum face (v1.2.1) exposed it: the
crosshair face matched the dialog perfectly, then the drag ghost and the committed solid
came out flipped. The sweep frame is now built with the opposite handedness so that the
**captured face, the 2D dialog, the crosshair datum face, the drag ghost and the built
solid all present the profile identically**. Legacy assemblies regenerate with the old
frame, keyed off the dictionary schema version, so nothing standing in a model mirrors
itself on its next rebuild.

### Root cause — a handedness mismatch across three conventions

| Stage | Convention | Effect |
|---|---|---|
| **Exporter capture** | `axis_y = normal × axis_z` | Looking at the captured face from its front, PosY+ runs to your **left** |
| **2D dialog (SVG)** | unconditional `flipY` display op | Draws `-PosY` to the right = shows the face **exactly as you saw it at capture**. The dialog was always right |
| **Sweep frame (old)** | `x_axis = Z × tangent` | PosY+ lands to the **left of travel** → viewed from the front cap (the natural inspection view, looking back against the sweep) the section reads **mirrored** vs the dialog |

The old frame reproduced the dialog only when viewed from *behind* the start cap, looking
through the solid along the sweep — a viewpoint nobody uses. Reverse (180° roll + Z-flip
≈ a left-right mirror about the path) happened to cancel the error, which is why it became
a reflex.

### The fix

`Na__Geometry__BuildPathFrameFromTangent` now builds `x_axis = tangent × Z` (PosY+ to the
**right** of travel). Viewed from the front cap, the placed section now reads exactly as
the dialog draws it. The frame is deliberately left-handed (det −1) — a true mirror of the
old placement; `BuildTransformedProfileFace` already normal-corrects the cap face, follow-me
is orientation-agnostic, and edge styling matches by edge length, so nothing downstream
cared.

**Rotation sign follows the frame.** The dialog renders rotation steps clockwise;
under the mirrored frame a positive roll about the tangent would read anticlockwise from
the front-cap view, so `TransformProfilePoints` negates the angle for mirrored frames.
The new `Na__Geometry__FrameMirrored?` (sign of the frame's determinant) drives both this
and the closed-loop cap frame in `BuildSweepRailPlan`, so the rotation sense and cap
handedness can never drift from whichever frame a caller built — no flags threaded
through the sweep internals.

**Datum probe back to toward-viewer.** Under the WYSIWYG frame, a probe pointing at the
viewer is what presents the crosshair face true-to-dialog (v1.2.1's away-from-viewer sign
was compensating for the old mirrored frame).

**"Are faces checking out" — post-sweep shell orientation self-check.** Follow-me chooses
the swept shell's facing by its own heuristics, and sweeping the mirrored cap section left
the whole solid inside out (back faces showing). `Na__Geometry__EnsureShellFacesOutward`
now runs inside `SweepProfileIntoGroup` after the seam cleanup: it computes the shell's
signed volume (divergence theorem — `p0 · (e1 × e2)` summed over every mesh triangle of
every face) and, when the total is negative, reverses every face in the run. Deterministic,
no per-face raycasting, and because it lives in the shared sweep helper it covers first
generation, every regeneration, and each run of a multi-run rebuild individually. Legacy
regens pass through it too — a no-op on a healthy shell.

### Legacy assemblies — dictionary schema 1.2.0

New builds stamp `SchemaVersion 1.2.0`. The RegenerationEngine reads the stored version:
anything older (or unparseable) rebuilds through `legacy_frame: true`, which reproduces
the original right-handed frame and rotation sign — so editing the path of a pre-existing
trace regenerates it exactly as it stands, mirrored compensations and all. Regeneration
never re-stamps the parent payload, so a legacy trace stays legacy for life; only newly
generated assemblies get the WYSIWYG frame.

**Practical upshot:** existing traces are untouched and keep regenerating as-built. Newly
placed profiles now come out matching the dialog — profiles that used to need Reverse no
longer will (and vice versa for any workflow that relied on the old flip).

### Files Touched

| Path | Change |
|---|---|
| `04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb` | WYSIWYG frame (+ legacy branch), `FrameMirrored?`, determinant-driven rotation sign, cap frame inherits handedness, `EnsureShellFacesOutward` signed-volume orientation check |
| `02__AppData/Na__ProfileTools__AppData__DataSerializer__.rb` | `NA_SCHEMA_VERSION` 1.1.0 → 1.2.0, compat notes |
| `31__System__ApplyProfileMode/Na__ProfileTools__RegenerationEngine__Main__.rb` | `LegacyFrameSchema?`, `legacy_frame` threaded through the rebuild |
| `31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PathSelectionTool__.rb` | Datum probe reverted to toward-viewer (true-to-dialog under the new frame) |

# =======================================================================================

## Profile Path Tracer - v1.2.1 - 28-Aug-2026 - Datum Face Preview + Live Reverse + TAB Hotkey

### Summary
Pressing **Generate Profile** used to drop a bare crosshair into the model. The profile
itself did not appear until a start point had been clicked *and* the cursor moved, so the
first time you could see which way the section was facing was after you had already
committed the start of the path — and hitting **Reverse** at that point did nothing,
because the flag was only read once, at Generate. The only fix was ESC and start again.

Three changes close that loop:

1. **The cross-section now appears on the crosshair immediately**, before the first click.
2. **Reverse is live.** The button reaches the running tool, so the preview flips in place
   at any point during a trace — before the first click or halfway through the path.
3. **TAB is now Reverse.** Rotation moves to **SHIFT+TAB**.

---

### 1. Datum face preview

Before a start point exists there is no path, and without a path there is no tangent to
build the section's frame from — which is why nothing was drawn. The tool now synthesises
a one-segment probe path through the cursor and feeds it to the *same*
`Na__Geometry__BuildPreviewGeometry` the live sweep uses, so the face, the rotation and
the reverse flip are all derived exactly as the real build derives them. Only the profile
outline is drawn from it; the probe's sweep cage is discarded, because drawing it would
imply a path direction the user has not chosen yet.

**Probe direction: snapped to the crosshair, pointing back at the viewer.** The path
direction is genuinely unknown at this moment, so the probe takes the model axis
(±red / ±green) closest to pointing out of the screen — the face always lies along a
crosshair arm instead of rotating freely with the camera, and snaps to the neighbouring
axis when an orbit crosses a 45° boundary. Under the WYSIWYG frame (v1.3.0) this presents
the section exactly as the dialog's 2D preview draws it. Reverse lands it on the other
side of the crosshair along the same arm, exactly as the build will. Falls back to
screen-up in plan views, where every vertical face is edge-on anyway.

**The flip bounds still agree with the build.** `BuildReverseFlipTransform` mirrors about
the top of the assembly bounding box; the probe path is horizontal and passes through the
datum, so its Z range matches the real assembly's for any flat path.

**The face does not blink out on the first click.** The old code drew nothing while
`@na_cache_path` was empty, which included the moment between clicking the start point and
moving the mouse. The datum face now covers that gap too, anchored on the last waypoint.

`Na__Preview__DrawProfileFace` is solid and explicitly closed, unlike the dashed
`DrawProfileGhost` that rides the cursor mid-sweep — an authored outer loop does not
repeat its first vertex, so `GL_LINE_STRIP` would otherwise leave the section visibly open.

---

### 2. Live Reverse

SketchUp exposes no way to fetch the active tool object back from the model, so
`Na__PathSelectionTool` holds a class-level reference to the instance that is running
(`unless defined?` guarded, so a hot reload mid-draw cannot orphan it). The dialog's
Reverse button now calls `na_profilepathtracer_set_reverse_direction` on every toggle,
not just at Generate; the callback finds the live tool, flips it, rebuilds the preview and
invalidates the view directly — necessary because the dialog holds focus at that moment
and no mouse move is coming to trigger a redraw.

With no interactive tool running the callback is a no-op: the dialog's own state is the
only thing that needed updating, and Generate reads it as before.

---

### 3. TAB reverses, SHIFT+TAB rotates

TAB was rotation. Reverse is the correction actually needed mid-trace, so it takes the
bare key and rotation moves to SHIFT+TAB (still reachable from the rotation pills in
Advanced Configuration). Shift is tracked via `CONSTRAIN_MODIFIER_KEY` held-state;
both held flags are cleared on `resume` so a key released while the tool was suspended
cannot leave SHIFT stuck on.

**TAB works in the dialog too.** Clicking Reverse moves focus to the dialog, so a viewport-
only hotkey would die on the first click. The dialog arms its own TAB handler — but only
while a trace is live (Ruby pushes tool activate/deactivate), and never over a text field,
so TAB keeps its normal focus-traversal job the rest of the time.

**State stays in sync both ways.** TAB in the viewport pushes back to the dialog so the
button repaints; the dialog's toggle pushes to the tool. Neither echoes the other back.

---

### Known limitation

The side of the line the section finally lands on depends on the path's travel direction
(`x_axis = Z × tangent`), and that is unknown before the first click. The datum face shows
shape, roll and reverse state exactly, locked to the crosshair axes — but once the first
segment is drawn the real tangent takes over, and a path traced in a different direction
presents the section from its corresponding side. Reverse stays live throughout, so the
correction is one TAB away either way.

Rotation changed with SHIFT+TAB is not pushed back to the dialog's rotation pills — same
as the previous TAB-rotate behaviour.

---

### Files Touched

| Path | Change |
|---|---|
| `31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PathSelectionTool__.rb` | Datum face cache + camera-derived probe tangent, live-tool class registry, public `SetReverseDirection`, TAB/SHIFT+TAB split, held-key reset on resume, status text + extents |
| `31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__3dPreviewGraphics__.rb` | `Na__Preview__DrawProfileFace` + `ClosedLoopPoints` |
| `01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | `na_profilepathtracer_set_reverse_direction` callback; `HandleReverseDirectionChange`, `PushReverseDirectionState`, `PushInteractiveToolState` |
| `31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js` | `Na__Ui__SetReverseDirection` funnel, `isInteractiveToolActive` state, TAB hotkey listener, two Ruby->JS receive handlers |
| `33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Bridge__.js` | `Bridge__SetReverseDirection` |
| `33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js` | Reverse button tooltip names the TAB hotkey |

# =======================================================================================

## Profile Path Tracer - v1.2.0 - 26-Aug-2026 - Dynamic Regeneration Rearchitecture (Fingerprint Sweep) + Open Path for Editing

### Summary
Dynamic Regeneration has been rebuilt around **state comparison instead of event
chasing**, after a dozen rounds of observer fixes kept failing the same way: extending
or moving a helper edge never rebuilt the solid, while "Regenerate Now" always worked.
Online research against the SketchUp API tracker, the official 2016 observer
changes document, and forum answers from SketchUp staff confirmed the observer layer
itself was the unfixable part — details below. The new system stores a SHA1
**fingerprint of the helper linework** on each assembly and re-compares it at cheap,
reliable trigger points; any mismatch, however caused, rebuilds the solid. A new
**Open Path for Editing** action (right-click menu + Settings button) drills straight
into the hard-to-click Helpers linework with the edges pre-selected, and closing the
group afterwards is itself the rebuild trigger — the same finish-to-rebuild loop
Profile Builder's Edit Path tool uses.

### Root Causes Found (research-confirmed)

1. **`EntitiesObserver#onElementModified` never fires for moved/stretched edges.**
   The Move tool changes *vertex positions*, not edge properties, and observers hook
   the property layer (confirmed by SketchUp staff `tt_su` on the official forums).
   The old system's primary trigger simply does not exist for the most common edit.
   Drawing/erasing edges (onElementAdded/Removed) does fire — which is why the
   feature *sometimes* appeared to work.
2. **Redo delivers no entity-modified events at all** — only
   `ModelObserver#onTransactionRedo` fires (documented API inconsistency).
3. **Copies silently orphan observers.** A copied trace shares its definition; the
   first UI edit auto-makes-unique, swapping in a fresh definition + fresh Entities
   collection. The observer stays attached to the *old* collection, permanently deaf.
   Copies also clone the `ProfileTraceId`, cross-wiring `FindParentByIdInModel`.
4. **The stored ON flag and the live observer were never reconciled.** Observers only
   attached on dialog open; undo/redo, copies, model switches and reloads all caused
   drift — hence the Settings readout "6 enabled / 4 active" and a context menu that
   said "currently ON" while nothing was attached.
5. **Hot reload wiped runtime state.** `load` re-ran `@na_registry = {}` (orphaning
   attached observers), re-ran `@na_app_observer = nil` (leaking the AppObserver),
   and re-ran `UI.add_context_menu_handler` (stacking duplicate menu sections —
   the API has no remove counterpart).

### New Architecture

| Piece | Role |
|---|---|
| `Na__RegenSweep` *(new)* | Debounced fingerprint sweep. Full sweep walks stamped assemblies, re-attaches missing observers, repairs duplicate ProfileTraceIds (make_unique + restamp), adopts baselines for legacy traces, and rebuilds any assembly whose linework hash changed. Light sweep covers registry-known assemblies only. Failure memo prevents a failing linework state from re-running until it changes again. |
| `Na__ModelObserver` *(new)* | `onActivePathChanged` (the moment a group edit closes — full sweep), `onTransactionUndo`/`Redo` (full), `onTransactionCommit` (light, catches deep edits by tools like Fredo that never open the group). Callbacks only schedule the timer — never touch the model (the documented crash vector). |
| `Na__EditPathNavigator` *(new)* | `Model#active_path=` (SU2020+) drills into the Helpers group from the parent (or any child) selection, pre-selecting the path edges. Exit = rebuild. |
| Fingerprint storage | `HelpersFingerprint` key in the parent dictionary, written **inside** the same operation as the geometry (build + every regen), so undo/redo reverts hash and geometry together and can never produce a phantom rebuild. Hash includes the Helpers group's own transformation, so scaling/moving the Helpers instance now regenerates too (the engine also bakes that transform into the rebuilt path). |
| `Na__HelpersEntitiesObserver` | Demoted to an accelerator: add/remove events (the reliable ones) just poke the sweep. Registry entries record the helpers *definition* pid so make-unique swaps are detected and re-attached. All module state is `unless defined?` guarded for hot reload. |
| Self-healing | Sweep triggers, Settings stats readout, right-click menu build, every rebuild, and plugin reload all reconcile observer attachment — the ON flag and reality can no longer drift apart (Detach All Observers now also suspends the sweep; Enable All re-arms it). Observers auto-install at SketchUp startup, no longer only on first dialog open. |

### Files Touched

| Path | Change |
|---|---|
| `01__AppCore/Na__ProfileTools__AppCore__RegenSweep__.rb` | **New** — fingerprint sweep engine |
| `01__AppCore/Na__ProfileTools__AppCore__EditPathNavigator__.rb` | **New** — Open Path for Editing |
| `01__AppCore/Na__ProfileTools__AppCore__HelpersEntitiesObserver__.rb` | Rewritten — accelerator role, reload-safe registry, definition-pid staleness detection |
| `01__AppCore/Na__ProfileTools__AppCore__Observers__.rb` | ModelObserver added, reload-safe ivars, startup auto-install |
| `01__AppCore/Na__ProfileTools__AppCore__ContextMenuHandlers__.rb` | Register-once guard, "Open Path for Editing" item, child-selection resolve, reconcile-on-build |
| `01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | Open-path callback, reconcile-before-stats, reload reinstalls observers, kill-switch suspends sweep |
| `01__AppCore/Na__ProfileTools__AppCore__Main__.rb` | Requires for the two new modules |
| `02__AppData/Na__ProfileTools__AppData__DataSerializer__.rb` | Fingerprint read/write, `ReadTraceId`, `RestampTraceId`, `ResolveTraceParentForEntity` |
| `04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb` | Baseline fingerprint stamped inside the build operation |
| `31__System__ApplyProfileMode/Na__ProfileTools__RegenerationEngine__Main__.rb` | Helpers transform baked into rebuilt path, fingerprint stamped in-operation, observer re-attach after rebuild |
| `35__System__SettingsMode/...SettingsTab__UiLogic__.js` / `...Bridge__.js` | Open Path button, updated Dynamic Regeneration copy |

### Research Sources
- SketchUp forum "Edge Change Observer" — staff confirmation onElementModified does not fire for edge moves
- SketchUp forum "Redo observer does not send on modified/on change events"
- Official "Observers & Operations SketchUp 2016 Changes and Best Practices" + SketchUp/sketchup-safe-observer-events
- Ruby API docs: ModelObserver (event queuing, onActivePathChanged), Model#active_path= (SU2020), Group#make_unique
- Profile Builder (mind.sight.studios) Edit Path Tool — rebuild-on-finish workflow

# =======================================================================================

## Profile Path Tracer - v1.1.7 - 15-Aug-2026 - Re-select Profile Geometry + Delete Profile

### Summary
Creating a profile was a one-shot capture: whatever face was selected and wherever the
origin was clicked became the library asset permanently. Miss the origin by a few
millimetres and the only remedy was to export a second profile and delete the first by
hand, losing the code, keywords and description with it. The Edit Profile tab now has a
**Rebuild & Remove** zone with two actions — re-capture the geometry in place, and delete
the profile outright — each behind its own confirmation gate.

---

### 1. Re-select Profile Geometry

Re-runs the Create Profile capture against the **existing** library file. New face, new
origin point, same asset identity.

| Kept | Replaced |
|---|---|
| `Na__Asset__Code`, name, description, keywords | `Na__Asset__Profile2D` |
| Notes, supplier fields, placement offsets, finishes | `Na__Asset__Mesh3D` |
| Any hand-added keys inside the geometry blocks | Edge colours, soft/smooth/hidden flags |

**Flow.** Confirm in the dialog → Ruby validates the live selection through the exporter's
own rules → origin picker arms → user clicks the new datum in the model → `.bak` written →
file overwritten → record re-parsed and pushed to the store. A `00__OriginPoint` helper is
dropped at the picked point, matching Create.

**Blocks are shallow-merged, not assigned.** The exporter writes every key the schema needs,
but a library file may carry hand-added keys inside those blocks and a re-capture is not a
licence to drop them.

**Selection is re-validated at the pick, not trusted from the arming call.** The user has
been back in the model since then and may have changed what is selected.

**Not in scope:** runs already placed in the model are not rebuilt. Their geometry was baked
at generate time; only Dynamic Regeneration touches those.

---

### 2. Delete Profile

Permanently removes the data file from `04__Data__ProfileLibrary`. Ruby re-parses the target
and checks its key matches the request before unlinking — a file that no longer parses, or
that holds a different profile, means the dialog and disk have diverged and the request is
stale. On success the whole bootstrap is re-sent ahead of the delete result, so the Gallery
and every key lookup rebuild from what is now on disk, and the Edit tab returns to Gallery.

Any sibling `.bak` left by an earlier save is reported in the status message rather than
silently left behind — the confirmation says the delete is permanent, so an unmentioned
recovery file on disk would be a surprise in either direction.

---

### 3. Confirmation gates

Both actions sit one stray click from Save, so neither fires on its first click. The button
opens an inline card naming exactly what is about to happen; only the second,
differently-placed click reaches Ruby. Nothing is sent, no model tool is armed and no file
is touched until that confirmation is given.

- Cancel sits first and the destructive button last, so the pointer never lands on the
  irreversible action by carrying momentum from the trigger.
- The delete card prints the full file path, wrapped rather than truncated.
- Switching to a different profile mid-gate closes the gate — a confirmation describing one
  file while the panel shows another is worse than no confirmation.
- `naButtonDanger` (red) and `naButtonWarn` (amber) are the only buttons of those colours in
  the app, so neither can be mistaken for a routine control.

---

### 4. Shared path guard

Three operations can now damage a library file — metadata overwrite, geometry re-capture and
delete — so the traversal check moved into one module all three call. It also gained a
`File::SEPARATOR` on the prefix comparison (a sibling folder such as
`04__Data__ProfileLibrary__Archive` previously passed) and now requires `File.file?` rather
than `File.exist?`.

### Files Touched

| Path | Change |
|---|---|
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__LibraryPaths__.rb` | **NEW** — single path guard shared by MetaWriter, GeometryReplacer and ProfileDeleter |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__GeometryReplacer__.rb` | **NEW** — re-capture geometry into an existing file; `.bak`, block merge, meta fold-in, re-parse |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__ProfileDeleter__.rb` | **NEW** — path-guarded, identity-checked permanent delete |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__MetaWriter__.rb` | `Na__MetaWriter__ValidateSourcePath` now delegates to LibraryPaths; local `NA_PROFILE_DATA_DIR` removed |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__MainUiLogic__.js` | Danger zone, both confirmation gates, waiting state, two result receivers; form reads hoisted to `Na__Edit__ReadFormFields` with record fallbacks |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__Bridge__.js` | Added `ReplaceGeometry` + `DeleteProfile` sends and their receive handlers |
| `02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__Exporter__.rb` | Extracted `Na__Exporter__BuildGeometryBlocks` from `BuildJsonPayload` so create and re-capture share one geometry-block shape |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | Two callbacks, replace-geometry handlers, `:replace_geometry` picker mode, pending-state |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__Main__.rb` | `require_relative` for the three new Edit Profile modules |
| `03__Style__AppStylesheets/Na__ProfileTools__CoreUi__Styles__Index__.css` | Added `.naButtonDanger`, `.naButtonWarn`, shared `[disabled]` rule |
| `03__Style__AppStylesheets/Na__ProfileTools__UiFeature__Styles__EditProfile__.css` | Danger zone panel + inline confirmation card styles |

### Architecture: Re-capture Flow
```
Edit tab trigger click        -> confirmation gate opens (nothing sent)
Confirm click                 -> Bridge__ReplaceGeometry -> HandleReplaceGeometryRequest
HandleReplaceGeometryRequest  -> path guard + selection validate -> arm OriginPointPickerTool
Model click                   -> FinalizePendingReplaceGeometry -> GeometryReplacer__Replace
GeometryReplacer__Replace     -> CollectGeometry -> BuildGeometryBlocks -> merge -> .bak -> write
                              -> ParseDataFile -> ReceiveReplaceGeometryResult
ReceiveReplaceGeometryResult  -> Store.UpdateRecord -> na_selected_changed -> panel + card redraw
ESC in model                  -> CancelPendingReplaceGeometry -> file untouched
```

# =======================================================================================

## Profile Path Tracer - v1.1.6 - 14-Aug-2026 - Dynamic Regen Fix, Insert Point Picker, Switch Controls

### Summary
Four changes: repaired the Dynamic Regeneration system (it had never fired), made the
interactive viewport preview honour Reverse, added a pickable insertion point to the 2D
preview with a constant-size datum marker, and replaced the two binary dropdowns with
segmented switches on one row.

---

### 1. Dynamic Regeneration — root cause and repair

**Root cause.** `Na__HelpersEntitiesObserver` called five of its own methods as bare
identifiers:

```ruby
def onElementModified(_entities, _element)
    Na__HelpersEntitiesObserver__Schedule    # <-- parsed as a CONSTANT, not a call
end
```

These method names start with a capital letter, so Ruby parses a receiver-less, paren-less
reference as a **constant lookup** and raises `NameError: uninitialized constant`. Every
edit to the Helpers linework raised inside the observer callback and was discarded. The
regeneration engine itself was never reached — which is why the feature looked entirely
dead rather than buggy. Fixed by adding explicit `self.` receivers, matching the
convention used everywhere else in the codebase.

**Secondary fixes found while verifying the path end to end:**

| Issue | Fix |
|---|---|
| Regen fired while the user still had the Helpers group open, so rebuilding the sibling SweptSolid silently failed | Observer now checks `model.active_path` and re-arms a 350 ms timer until the group edit is closed |
| Closed loops rebuilt with a duplicate closing point, producing a zero-length rail segment | `Na__RegenEngine__SanitizeOrderedPoints` merges coincident points and drops the repeated first/last |
| Reversed profiles regenerated un-reversed | `ReverseDirection` now persisted; regen re-applies the 180° profile roll. The flip itself lives on the parent group's own transformation, so the Helpers keep un-flipped local coordinates and must **not** be flipped again |
| Every failure returned a silent `false` | `Na__RegenEngine__ReportFailure` writes the reason to the status bar and the console |
| Parent lookup was a full model scan over Groups only | Walks up via `group.parent.instances` first; the ID scan now also recurses through ComponentInstance definitions |
| `[DynRegen]` rename ran outside any operation | Wrapped in its own transparent operation |

**Dictionary schema 1.0.0 -> 1.1.0.** Added `ReverseDirection`, `OriginOffset` and
`PathPoints` (JSON blob, following the Entity Assembly Studio Pro serializer pattern) so a
trace carries everything needed to rebuild itself. Older 1.0.0 assemblies still read back —
the new keys default to false / nil / [].

---

### 1b. Newly drawn Helpers segments now extend the moulding

Regeneration worked, but only for edits to the *existing* path. Drawing new linework into
the group did nothing, because `Na__Path__BuildSegments` demands exactly one unbranched
chain — correct for a user selection, wrong for a proxy you are meant to keep drawing into:

| What the user draws | Old result |
|---|---|
| A second, separate run | `Selection contains disconnected edge sets.` — rebuild refused |
| A spur off an existing run (T-junction) | `Branching path detected.` — rebuild refused |
| An extension at the **start** end | Swept backwards — the start vertex was chosen by `min_by(&:persistent_id)`, so a new lower/higher id at the far end flipped traversal direction |

Added `Na__Path__BuildChains`, which decomposes an arbitrary edge set into maximal
non-branching chains plus any pure closed loops. Every chain is swept, so all three cases
above now extend the moulding.

**Structure.** One chain sweeps directly into `Na__ProfileTrace__SweptSolid`, exactly as
before — no change for existing models. Multiple chains get one `Na__ProfileTrace__Run__NN`
sub-group each, so a run's closure-seam cleanup cannot erase a neighbouring run's faces.
Failed runs erase their own empty shell rather than accumulating hollow groups.

**Direction stability.** Chains are oriented and ordered against the assembly's stored
`StartPoint`. Open runs flip so their start is the end nearest that anchor; closed runs are
*rotated* to begin at the nearest vertex, which pins the follow-me seam — a loop has no
natural start, so without this the seam moved whenever the edge set changed.

**Isolation.** Each run sweeps inside its own rescue, so one bad chain is skipped and
reported rather than aborting the operation and discarding the runs that already succeeded.

**Edge styling.** Newly drawn helper edges get the helpers material applied. Only edges that
actually differ are painted — writing to an already-correct edge still fires
`onElementModified`, and a callback delivered after the commit would schedule another
rebuild, giving a loop that never settles.

**Also tightened:** the edit-context probe matched *any* trace assembly in `active_path`, so
opening one assembly set every attached observer polling. Now scoped to the observer's own
Helpers group and its owning assembly.

**Latent fix:** `Na__Path__FindNearestVertex` called `#distance` on entries that may be
`Sketchup::Vertex`, which has no such method. Unreachable today, but it would have fired the
moment anyone passed a start point into `Na__Path__OrderEdges`. Now normalises via
`#position` first.

---

### 2. Interactive preview now reflects Reverse

`Na__PathSelectionTool__RebuildPreviewCache` built its ghost and sweep cage without ever
passing `reverse_direction`, so the viewport showed the un-reversed profile while Generate
produced the reversed one.

The flip is now a shared helper, `Na__Geometry__BuildReverseFlipTransform(bounds)` — a Z
scale of -1 about the bbox centre followed by a lift of the full Z extent — called by both
the real build and the new `Na__Geometry__BuildPreviewGeometry`. The preview rebuilds the
same bounding box the build uses (sweep cage + path linework), so the two cannot drift.
The status bar also shows `| REVERSED` while the tool is live.

**Also fixed: mirror/build parity.** `Na__Geometry__TransformVertexMap` applied mirror
toggles *after* the path frame transform, i.e. reflecting about the world axes, while every
other code path mirrors in local 2D profile space *before* the transform. With any mirror
toggle on, the swept face did not match the preview, and the world mirrors displaced the
face relative to the path. Reordered to local-first, matching the documented contract in
`MirrorProfile__.rb`.

---

### 3. Insert point picker + consistent datum marker

**Datum marker.** Was a dashed cross plus dot sized in profile units, so it shrank to a
speck on large profiles. Now always a diagonal **X**, sized as a fixed fraction of the
rendered viewBox span (margin included), giving identical on-screen size for a 20 mm bead
and a 500 mm cornice. It is also drawn at the *active* insertion point rather than assumed
to sit at (0,0), so it tracks centre mirrors. Suppressed on gallery thumbnails.

**Picker.** "Set Insert Point" reveals a handle on every profile vertex; clicking one
re-datums the profile to that vertex. Mainly for scene-picked profiles, where the authored
origin is unforgiving — on a skirting you can now just click the other corner.

The offset is stored as `{ y, z }` in the profile's authored `PosY_mm` / `PosZ_mm` space,
so it survives rotation and mirroring, and is threaded through generate payload -> dialog ->
placement engine -> geometry builder -> model dictionary. It resets when the active profile
changes, since a datum picked on one profile is meaningless on another.

The 2D transform chain was refactored into an ordered op list with the mirror axes frozen
up front, so the outline and the lone datum point run through the identical transform.
Verified byte-identical to the previous chain across all 56 combinations of mirror flags x
rotation x reverse.

---

### 3b. Flip Profile — normalise library handing in place

Profiles are authored from whatever face happened to be selected, so the library has mixed
handing and the Gallery gives no reliable clue which way a profile will sweep. **Flip
Profile** in the Edit Profile tab mirrors the asset left-right about its own datum and
writes it straight back to the library JSON, so the whole library can be walked through and
normalised to one handing — and a future mis-handed export can be corrected without
re-exporting the asset.

**What gets mirrored** (`Na__EditProfile__GeometryWriter`):

| Block | Field | Action |
|---|---|---|
| `Na__Asset__Profile2D` | Vertices `PosY_mm` | negated (Y is the profile's horizontal axis) |
| | Faces `OuterLoopVertices` | reversed, keeping winding matched to the normal |
| `Na__Asset__Mesh3D` | Vertices `PosX_mm`, `Normal_X` | negated (X is the profile-width surrogate) |
| | Faces `OuterLoop_VertexIds` / `InnerLoops` | reversed |
| | Faces `Normal[0]` | negated |
| | `BoundingBox` MinX / MaxX | swapped and negated |

Edges in both blocks are **left alone** — they are stored as vertex-id pairs, not an ordered
walk, so they stay valid. Edge styling is matched by *length*
(`Na__Geometry__FindClosestStyleReference`) and a mirror preserves length, so edge colours
and soft/smooth/hidden flags survive untouched.

**Verified across the whole library:** all 24 profiles mirror cleanly and flipping twice
restores the original file exactly; edge lengths and signed loop area (including sign) are
unchanged.

**Atomicity.** The flip rides on the existing metadata save, so it cannot discard text edits
typed but not yet saved — one read, one patch, one backup, one write. Three failure modes
were closed while building it:

- Mesh3D sub-blocks now mirror **independently**. An early return on a missing vertex array
  would have left faces and the bounding box un-mirrored while Profile2D had already
  flipped — a half-mirrored file written over the only backup. The library validator does
  permit a Mesh3D block with edges but no vertices, so that shape was reachable.
- The `.bak` is now written **last**, immediately before the overwrite. Previously a bail-out
  path burned the user's rollback point without changing the file.
- `Na__EditProfile__Bridge__Save` now returns whether the call actually reached Ruby. The
  shared `na_is_saving` guard gates both buttons, so a dispatch that silently went nowhere
  left Save *and* Flip disabled for the rest of the session.

**Known consequence.** A per-run `OriginOffset` is stored in the profile's own `PosY_mm`
space, so flipping a profile invalidates the custom insert point on runs already placed from
it — the datum lands on the mirror image and the run shifts by `2 x y_mm`. Called out in the
button tooltip; re-pick the insert point on affected runs.

---

### 4. Profile Source / Path Mode switches

Both controls are binary, so a dropdown hid half the information behind a click. Replaced
with two segmented switches sharing one row: both options always visible, the live one
filled in. Recovers a full row of vertical space.

---

### Files Touched

| Path | Change |
|---|---|
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__HelpersEntitiesObserver__.rb` | **Root-cause fix** — `self.` receivers on 5 calls; edit-context deferral via `model.active_path`; documented the capital-letter parsing trap |
| `02__Src__AppModules/02__AppData/Na__ProfileTools__AppData__DataSerializer__.rb` | Schema 1.1.0: `ReverseDirection`, `OriginOffset`, `PathPoints`; `WritePathPoints`; `ContainingInstance` walk-up; component-aware traversal |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__RegenerationEngine__Main__.rb` | Point sanitisation, reverse-aware rotation, origin offset, path refresh, visible failure reporting; **multi-run sweeping** with per-run isolation, `Run__NN` sub-groups, failed-shell cleanup and helper-edge restyling |
| `02__Src__AppModules/04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__PathAnalysis__.rb` | **NEW** `Na__Path__BuildChains` / `WalkChainFrom` / `OrientChain` / `RotateLoopToAnchor` / `SortChainsByAnchor`; `FindNearestVertex` normalises Vertex vs Point3d |
| `02__Src__AppModules/04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb` | `BuildReverseFlipTransform`, `BuildPreviewGeometry`, `ApplyOriginOffset`; mirror-order parity fix; richer dictionary stamping; rename wrapped in an operation |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PathSelectionTool__.rb` | Uses the combined preview builder; carries `origin_offset`; REVERSED status flag |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PlacementEngine__.rb` | `origin_offset:` pass-through; `BuildFromSelection` now forwards rotation / reverse / offset |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__HeadlessRunner__.rb` | Headless honours `rotationStep`, `reverseDirection`, `originOffset` |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | `Na__Dialog__NormalizedOriginOffset`; offset threaded to both generate paths |
| `02__Src__AppModules/05__Viewport__2dPreviewEngine/Na__ProfileTools__Viewport__SvgGenerator__.js` | Op-list transform pipeline; `originOffset` + `showVertexHandles`; constant-scale X datum; returns `sourcePoints`; removed 4 superseded helpers |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js` | `originOffset` / `isInsertPointPickActive` state, 3 new handlers, payload field, reset-on-profile-change |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__Events__.js` | Switch wiring; insert-point buttons; delegated vertex clicks on the preview SVG |
| `02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js` | `BuildSwitchHtml` / `BuildSwitchOptions`; switch row replaces both selects; insert-point bar; removed dead `BuildOptionsHtml` |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__GeometryWriter__.rb` | **NEW** — in-place horizontal mirror of a library profile's stored geometry |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__MetaWriter__.rb` | `flipHorizontal` folded into the same atomic write; `.bak` moved to just before the overwrite; normalised doubled-CR line endings |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__MainUiLogic__.js` | Flip Profile button; shared dispatch helper that releases the busy guard when the bridge is unreachable |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__Bridge__.js` | `Bridge__Save` returns whether the call reached Ruby |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__Main__.rb` | Requires GeometryWriter ahead of MetaWriter |
| `03__Style__AppStylesheets/Na__ProfileTools__CoreUi__Styles__Index__.css` | Segmented switch styles; `.naProfileOriginCross`; `.naProfileVertexHandle`; insert-point bar; `.naButton--pickActive` |

### Known Pre-existing Issue (not addressed here)
`Na__ProfileTools__CreateNewProfile__Exporter__.rb` calls
`Na__EdgeColourManager.Na__EdgeColours__FlatLookup`, which does not exist — the guard above
it tests a different method name, so the `NoMethodError` is swallowed by a bare rescue and
edge colour IDs are never resolved for non-`MTE` material names on export.

# =======================================================================================

## Profile Path Tracer - v1.1.5 - 09-Jun-2026 - Added Reverse Profile Direction Toggle

### Summary
Added a "Reverse Direction" toggle button to the Apply Profile tab. When active, the
generated profile is swept with a +180° rotation offset then the resulting group is
Z-axis flipped and translated back to the original path line, effectively reversing the
winding direction of the profile without requiring knowledge of edge winding order.
The SVG 2D preview mirrors left-right to give immediate visual feedback.

### How It Works
1. User presses **⇄ Reverse** button (left of Generate).
2. JS sets `reverseDirection: true` in `Na__UiState` and rebuilds the generate payload.
3. Ruby receives `reverseDirection` in `generate_config`.
4. `UnifiedOverrides__` computes `effective_rotation_step = (rotation_step + 2) % 4` before the sweep.
5. After the sweep group is created, `Geom::Transformation.scaling(bounds.center, 1, 1, -1)` flips it on the world Z axis.
6. A follow-up `Geom::Transformation.translation([0, 0, z_extent])` corrects the vertical offset so the profile sits back on the original path line.
7. SVG preview applies a double `FlipAcrossYAtX(0)` (left-right mirror) to reflect the reversed orientation.

### Button UX
- Inactive: `⇄ Reverse` — `naButtonSecondary` style (white).
- Active: `⇄ Reversed` — `naButton--reverseActive` style (desaturated red `#a84444`).

### Files Touched

| Path | Change |
|---|---|
| `02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js` | Added Reverse button left of Generate; active text + red tint class |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__Events__.js` | Wired `#naBtnReverseDirection` click to `Na__Events__OnReverseDirectionToggle` |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js` | Added `reverseDirection` state, toggle handler, payload field, preview re-render on toggle, `reverseDirection` passed to SVG generator |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | Extracted `reverseDirection` from config; passed to both selection-mode and interactive-mode paths |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PathSelectionTool__.rb` | Added `reverse_direction` to `initialize`; threaded through to `Na__Engine__GenerateFromInteractivePath` |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PlacementEngine__.rb` | Added `reverse_direction:` keyword to `Na__Engine__GenerateFromInteractivePath` and `Na__Engine__GenerateFromPathData` |
| `02__Src__AppModules/04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb` | Added `reverse_direction:` to `Na__Geometry__BuildProfileAlongPath`; applied `effective_rotation_step`, Z-scale flip, and Z-translate correction |
| `02__Src__AppModules/05__Viewport__2dPreviewEngine/Na__ProfileTools__Viewport__SvgGenerator__.js` | Reads `reverseDirection` option; applies left-right flip (`FlipAcrossYAtX` twice = X mirror) when active |
| `03__Style__AppStylesheets/Na__ProfileTools__CoreUi__Styles__Index__.css` | Added `.naButton--reverseActive` desaturated red style |

# =======================================================================================

## Profile Path Tracer - v1.1.4 - 09-Jun-2026 - Added Gallery View, Edit Profile Tab & Folder Renumber

### Summary
Major UX refactor: added a live Gallery tab with SVG-thumbnail cards and keyword-prioritised
search, a new Edit Profile tab for in-place metadata editing, a shared ProfileStore as the
single source of truth for selected profile state, and a full system-module folder renumber
to match the new tab order.

### Folder Renumber Migration
| Old Path | New Path |
|---|---|
| `02__Src__AppModules/10__System__CreateNewProfile/` | `02__Src__AppModules/33__System__CreateProfileMode/` |
| `02__Src__AppModules/20__System__ApplyProfileAlongPath/` | `02__Src__AppModules/31__System__ApplyProfileMode/` |
| `02__Src__AppModules/03__AppUtils/Na__...SettingsTab__*.js` | `02__Src__AppModules/35__System__SettingsMode/` |
| (new) | `02__Src__AppModules/30__System__GalleryMode/` (existing, now live) |
| (new) | `02__Src__AppModules/32__System__EditProfileMode/` |

All `require_relative` paths in `Main__.rb`, `NA_JS_SUBFOLDER_FILES` in `PluginReloader__.rb`,
and `<script src>` paths in `UiLayout__.html` updated accordingly.

### New and Changed Files

| Path | Change |
|---|---|
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__ProfileStore__.js` | **NEW** — Shared profile map + selected-key store; dispatches `na_profiles_changed`, `na_selected_changed`, `na_profile_meta_updated` via Na_AppContext |
| `02__Src__AppModules/30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__CardRenderer__.js` | **NEW** — SVG-thumb card builder + keyword-prioritised filter/sort |
| `02__Src__AppModules/30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__MainUiLogic__.js` | **NEW** — Gallery tab: card grid, search bar, thumbnail-size cycle, card-click selection |
| `02__Src__AppModules/30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__Placeholder__.js` | **DELETED** — replaced by MainUiLogic |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__MainUiLogic__.js` | **NEW** — Edit Profile tab: live metadata form, SVG preview, store subscription |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__Bridge__.js` | **NEW** — JS→Ruby save bridge + ReceiveUpdateProfileMetaResult receive handler |
| `02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__MetaWriter__.rb` | **NEW** — Ruby: path-guard validation, .bak backup, JSON patch, file write, re-parse via ProfileLibrary |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | Added `na_profilepathtracer_update_profile_meta` callback delegating to MetaWriter |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__Main__.rb` | Updated require_relative paths (31, 33) + added require for MetaWriter (32) |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__PluginReloader__.rb` | Updated NA_JS_SUBFOLDER_FILES to all new paths + new modules |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__TabRouter__.js` | Added `edit-profile` to NA_TAB_TO_GLOBAL; default tab changed to `gallery` |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js` | Populate ProfileStore from ReceiveBootstrap; subscribe to store events; added active-profile indicator helper |
| `02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__Events__.js` | Removed naProfileSelect dropdown event wiring |
| `02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js` | Removed naProfileSelect form row; replaced with read-only active-profile indicator driven by ProfileStore |
| `Na__ProfileTools__UiLayout__.html` | Tab order: Gallery (default), Apply Profile, Edit Profile, Create Profile, Settings; added Edit Profile panel; updated all script src paths |
| `03__Style__AppStylesheets/Na__ProfileTools__UiFeature__Styles__Gallery__.css` | **NEW** — Gallery toolbar, card grid (sm/md/lg), cards, chips, empty state |
| `03__Style__AppStylesheets/Na__ProfileTools__UiFeature__Styles__EditProfile__.css` | **NEW** — Edit Profile form, geo-summary bar, active-profile indicator, empty state |
| `03__Style__AppStylesheets/Na__ProfileTools__CoreUi__Styles__Index__.css` | Added @import for Gallery and EditProfile stylesheets |

### Architecture: Shared Selection Flow
```
Ruby BuildBootstrapPayload → ReceiveBootstrap → ProfileStore.SetProfiles
ProfileStore → na_profiles_changed → Gallery renders cards
Gallery card click → ProfileStore.SetSelected → na_selected_changed
na_selected_changed → EditProfile tab reloads | Apply tab indicator refreshes
EditProfile form input → ProfileStore.ApplyMetaPatch → na_profile_meta_updated
EditProfile Save → Bridge → Ruby MetaWriter (.bak + overwrite) → UpdateRecord → na_selected_changed
```

# =======================================================================================

## Session — 09-Jun-2026 | Gallery Polish Fixes

### Changes

| Path | Change |
|---|---|
| `03__Style__AppStylesheets/Na__ProfileTools__CoreUi__Styles__Index__.css` | Added `vector-effect: non-scaling-stroke` to `.naProfileLine`, `.naAxisLine`, `.naProfileOriginLine`, `.naProfileOriginPoint` — ensures consistent stroke weight across all card sizes regardless of viewBox scale |
| `02__Src__AppModules/05__Viewport__2dPreviewEngine/Na__ProfileTools__Viewport__SvgGenerator__.js` | Added `thumbnailMode` option to `Na__Svg__GenerateProfile`: uses `includeOrigin: false` + 10% proportional margin so gallery cards show a tight, centred fit regardless of how far the profile geometry sits from its origin point. Also added `margin` override to `Na__Svg__Bounds` |
| `02__Src__AppModules/30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__CardRenderer__.js` | Pass `thumbnailMode: true` to `Na__Svg__GenerateProfile`; switched hover tooltip from `title=""` to `data-tooltip=""` for fast CSS-only reveal |
| `03__Style__AppStylesheets/Na__ProfileTools__UiFeature__Styles__Gallery__.css` | Tooltip redesigned as bottom-of-card overlay (position absolute, bottom 0) so it is never clipped by the grid's `overflow-y: auto` container; 100 ms delay, 80 ms fade |
| `02__Src__AppModules/30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__MainUiLogic__.js` | Gallery card click navigates to **Apply Profile** tab (was incorrectly set to Edit Profile) |

# =======================================================================================

# =======================================================================================
## Profile Path Tracer - v1.1.3 - 05-Jun-2026

### Fix (critical): Closed-loop sweep shrank the profile cross-section

#### Symptom

Applying any library profile along a **closed loop** (e.g. `Interactive path picking`
around a roof perimeter) produced a sweep with the **wrong cross-section size**: a
`PRF1301...w120` half-round gutter came out **~85 mm** wide instead of `120 mm`.
Straight / open-path runs were always correct. The error was **profile-agnostic** and
applied to every profile, which made the profile library effectively unusable for loops.

#### Root cause (confirmed by math)

`Sketchup::Face#followme` sweeps the start cap face **as-is** — it does not re-orient the
cap perpendicular to the path. The closed-loop start cap was being built perpendicular to
the **corner bisector** at the start vertex, while the sweep actually travelled along the
**first edge** `V0 -> V1`. An oblique cap produces an oblique prism whose true
(perpendicular) cross-section is foreshortened by `cos(theta)`, where `theta` is the angle
between the bisector and the first edge.

At a right-angle loop corner `theta = 45 deg`, so `120 mm x cos(45) = 84.85 ~ 85 mm`,
matching the report exactly. Open paths used the outgoing edge tangent for the cap (already
perpendicular to the sweep), which is why they stayed correct.

The oblique cap came from `Na__Geometry__BuildStartFrameTangent`, which returned a
**bisector** tangent for closed loops; that frame became the cap normal in
`Na__Geometry__BuildTransformedProfileFace`. Because both the initial build and the
dynamic-regeneration path share `Na__Geometry__SweepProfileIntoGroup`, **regeneration
shrank too**.

#### Fix

Two coordinated changes inside the shared sweep so both initial build and regen are fixed:

1. **Cap perpendicular to the first edge.** `Na__Geometry__BuildStartFrameTangent` now
   always returns the outgoing (first-edge) tangent. This also corrects the preview ghost
   polyline (`Na__Geometry__BuildPreviewProfilePolyline`), which used the same frame.

2. **Midpoint-start closed-loop sweep.** A new `Na__Geometry__BuildSweepRailPlan` computes
   the follow-me rail. For closed loops it starts and ends at the **midpoint `M` of the
   first segment** (`M -> V1 -> ... -> Vn -> V0 -> M`) and builds the cap at `M`
   perpendicular to `(V1 - V0)`. Starting mid-segment is the standard robust technique:
   the start and end caps are coplanar, so they merge and the closure corner miters
   cleanly. Open paths keep the corner list as the rail and cap at the first vertex.

3. **Seam removal follows the cap plane.** `Na__Geometry__RemoveClosureSeamFaces` now takes
   a `closure_plane` hash `{ origin: M, normal: (V1 - V0), ordered_points: [...] }` from the
   rail plan (origin `M`, not `ordered_points[0]`), so the now-coplanar internal seam face
   is reliably detected and erased. It returns `0` (no-op) for open paths.

The `ordered_points` corner list is still used unchanged for the Helpers polylines and the
attribute-dictionary stamping, so regeneration stays idempotent; the midpoint exists only
on the temporary follow-me rail, which is erased afterward by
`Na__Geometry__ErasePathRailEdges`.

#### Removed (DRY)

`Na__Geometry__IncomingTangentAtIndex` and `Na__Geometry__BisectorTangent` became dead code
once the bisector branch was dropped, and were deleted.

#### Files touched (modified)

| Path | Change |
|---|---|
| `02__Src__AppModules/04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb` | `BuildStartFrameTangent` -> first-edge tangent only; new `BuildSweepRailPlan` (midpoint start + cap frame + closure plane); `SweepProfileIntoGroup` uses the rail plan; `RemoveClosureSeamFaces` takes `closure_plane`; removed `IncomingTangentAtIndex` / `BisectorTangent`; header note |

#### Behaviour notes / scope

- Open-path behaviour is unchanged (was already correct).
- On **sloped open** runs the gutter stays full-width but tilts to be perpendicular to the
  run; making it sit upright on a slope is a separate enhancement, not this fix.
- Geometry-only change: no data-schema, profile-library, or UI changes.

#### Verification

Confirmed in SketchUp: closed loops (flat and sloped) produce a full `120 mm` cross-section
with clean mitered corners and no internal seam face; open/straight runs remain `120 mm`;
moving a Helpers edge regenerates at the correct size; verified across multiple profiles.

# =======================================================================================
## Profile Path Tracer - v1.1.2 - 12-May-2026

### Feature: Helper path tag, rail cleanup, and dynamic regeneration

#### Summary

Apply Profile generation now builds a **three-level assembly**: a parent group
`Na__ProfileTrace__<profileKey>`, a **Helpers** child containing the canonical path
polylines (tag `02__ProfilePathTracer_Helpers`, line style from DataLib `Tag__LineStyle__Config`,
edge paint from `Tag__EdgeMaterial__Config` via `Na__TagApplier`), and a **SweptSolid**
child for the Follow Me result. Attribute dictionaries stamp each trace for later
recognition (`Na__ProfilePathTracer__Info` on the parent, `Na__ProfilePathTracer__HelpersInfo`
on Helpers) with sequential IDs `NPT0001`, `NPT0002`, etc. (Outliner names may still
duplicate; identity is dictionary + `persistent_id`, not display name.)

After a successful sweep, **loose rail edges inside SweptSolid are erased**
(`Na__Geometry__ErasePathRailEdges`) so only the Helpers copy remains — no doubled
guideline fighting the mesh.

**Dynamic regeneration**: a `Sketchup::EntitiesObserver` on the Helpers group's
`entities` debounces edits (~150 ms) and calls `Na__RegenEngine__RegenerateFromHelpers`,
which rebuilds only the SweptSolid sub-group from the current helper edge chain.
`DynamicRegenEnabled` defaults to **true**; on first build, the code auto-attaches the
observer and appends ` [DynRegen]` to the parent group name. Context menu on a single
selected stamped parent: Enable/Disable Dynamic Regeneration, Regenerate Now. Settings tab:
Enable All / Disable All / Detach All Observers plus live stats (`na_profilepathtracer_dynregen_*`
callbacks). Observers are re-attached on model switch via existing `Na__Observers` AppObserver
walker; uninstall clears `Na__ObserverRegistry`.

Shared sweep logic lives in `Na__Geometry__SweepProfileIntoGroup` (used by initial build and
regen). Exporter tag lookup delegates to `Na__TagApplier` for DRY.

#### Files touched (new)

| Path | Role |
|---|---|
| `02__Src__AppModules/03__AppUtils/Na__ProfileTools__AppUtils__TagApplier__.rb` | DataLib-driven tag/layer + MTE edge paint |
| `02__Src__AppModules/02__AppData/Na__ProfileTools__AppData__DataSerializer__.rb` | Stamp/read profile-trace dictionaries, NPT IDs |
| `02__Src__AppModules/20__System__ApplyProfileAlongPath/Na__ProfileTools__RegenerationEngine__Main__.rb` | `Na__RegenEngine__RegenerateFromHelpers` |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__HelpersEntitiesObserver__.rb` | `Na__HelpersEntitiesObserver` + `Na__ObserverRegistry` |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__ContextMenuHandlers__.rb` | Right-click Enable/Disable / Regenerate Now |

#### Files touched (modified)

| Path | Change |
|---|---|
| `02__Src__AppModules/04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb` | Parent/Helpers/SweptSolid build, `SweepProfileIntoGroup`, stamp, auto dyn-regen attach, erase path rails |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__Main__.rb` | Requires: TagApplier, DataSerializer, RegenEngine, HelpersEntitiesObserver, ContextMenuHandlers |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__Observers__.rb` | Attach stamped helpers on install/model change; detach all on uninstall |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__DialogManager__.rb` | DynRegen stats / enable-all / disable-all / detach-all callbacks |
| `02__Src__AppModules/10__System__CreateNewProfile/Na__ProfileTools__CreateNewProfile__Exporter__.rb` | `@delegate` tag lookup → `Na__TagApplier` |
| `02__Src__AppModules/03__AppUtils/Na__ProfileTools__AppUtils__SettingsTab__UiLogic__.js` | Dynamic Regeneration section + stats row |
| `02__Src__AppModules/03__AppUtils/Na__ProfileTools__AppUtils__SettingsTab__Bridge__.js` | JS bridge for dyn-regen actions |

#### Note for older models

Traces created before this version may have `DynamicRegenEnabled` false in the dictionary
and no observer; use context menu **Enable Dynamic Regeneration** or Settings **Enable All**.

# =======================================================================================
## Profile Path Tracer - v1.1.1 - 12-May-2026

### Feature: Dedicated "Create Profile" Tab + UI Restructure

#### Summary

Introduced a dedicated **Create Profile** tab, separating profile creation from the
Apply Profile workflow. All profile-creation forms, validation actions, and save logic
are now consolidated in one place, making the UI significantly more intuitive.

Also added the missing `Na__EdgeColours__CanonicalIdForMaterial` method to the
`Na__EdgeColourManager` module, which was called by the Exporter but never implemented,
causing profile saves to fail with `undefined method`.

---

#### UI Changes

**New tab order:** Apply Profile | **Create Profile** | Gallery | Settings

The "Create Profile" tab runs a two-state workflow:

1. **Instruction state** — explains the three steps; shows a **Validate Selection** button.
   Clicking this calls `Bridge__ValidateForExport` which triggers Ruby-side geometry
   inspection. On success, the tab automatically transitions to the form state.
2. **Form state** — shows the Geometry Summary (face/edge/vertex count + SVG preview),
   then the Profile Details form (Name, Description, Keywords, Profile ID, Timestamp,
   Units). **Save Profile Data File** submits to Ruby. **Start Over** resets back to the
   instruction state.

The Apply Profile tab is now focused exclusively on generating extruded profiles —
the "Create New Profile" button and the hidden slide-in panel have been removed from it.

---

#### Ruby Fix: Missing `Na__EdgeColours__CanonicalIdForMaterial`

##### Problem

Saving a profile failed with:

```
Save failed: undefined method `Na__EdgeColours__CanonicalIdForMaterial'
for Na__ProfileTools__ProfilePathTracer::Na__EdgeColourManager:Module
```

`Na__Exporter__BuildMeshEdgeRecord` (line 443 of `Na__ProfileTools__CreateNewProfile__Exporter__.rb`)
called `Na__EdgeColourManager.Na__EdgeColours__CanonicalIdForMaterial` but this method
was never defined in the module.

##### Fix

Added `Na__EdgeColours__CanonicalIdForMaterial(material_name, _edge = nil)` to the
`Na__EdgeColourManager` module. It delegates to the existing `Na__EdgeColours__GetEntryByName`
and returns the entry's `MteKey` if the material name resolves to a Noble Architecture
standard edge material, otherwise `nil`.

```ruby
def self.Na__EdgeColours__CanonicalIdForMaterial(material_name, _edge = nil)
    return nil if material_name.to_s.strip.empty?
    entry = self.Na__EdgeColours__GetEntryByName(material_name.to_s)
    return nil unless entry
    mte_key = entry['MteKey'].to_s
    mte_key.empty? ? nil : mte_key
end
```

---

#### Files Touched

| Path | Change |
|---|---|
| `Na__ProfileTools__UiLayout__.html` | Added "Create Profile" tab button and panel; added script tag for new MainUiLogic |
| `02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__TabRouter__.js` | Added `'create-profile'` → `Na__ProfileTools__CreateNewProfile__Tab` to lookup table |
| `02__Src__AppModules/10__System__CreateNewProfile/Na__ProfileTools__CreateNewProfile__UiSystem__MainUiLogic__.js` | **NEW** — Owns full Create Profile tab lifecycle and `ReceiveExportValidation` / `ReceiveSaveProfileResult` callbacks |
| `02__Src__AppModules/10__System__CreateNewProfile/Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js` | Removed "Create New Profile" button + hidden `naCreateProfilePanel` div from Apply Profile tab body |
| `02__Src__AppModules/20__System__ApplyProfileAlongPath/Na__ProfileTools__ApplyProfile__UiSystem__Events__.js` | Removed `btnCreateProfile` event wiring |
| `02__Src__AppModules/20__System__ApplyProfileAlongPath/Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js` | Removed `ShowCreateProfilePanel`, `HideCreateProfilePanel`, `BuildUnifiedPreviewRecordFromPoints`, `OnCreateProfile` handler, `ReceiveExportValidation`, `ReceiveSaveProfileResult` — all moved to new module |
| `02__Src__AppModules/02__AppData/Na__ProfileTools__AppData__EdgeColourManager__.rb` | Added missing `Na__EdgeColours__CanonicalIdForMaterial` method |

# =======================================================================================
## Profile Path Tracer - v1.1.0 - 12-May-2026

### Fix: Scene Pick Profile Extraction — Broken Edge Colour Resolution

#### Problem

Selecting a Group/Component face via the **Scene Pick** workflow (`Profile Source → Scene Pick
(Group/Component Face)` → **Pick Scene Profile** button) always failed with:

```
Scene profile extraction failed: undefined method `Na__Exporter__ResolveEdgeColourHex'
for Na__ProfileTools__ProfilePathTracer::Na__ProfileExporter:Module
```

`Na__SceneProfileRegistry__ExtractUnifiedGeometry` was manually building mesh edge records
inline and calling `Na__ProfileExporter.Na__Exporter__ResolveEdgeColourHex` — a method that
was never defined anywhere on `Na__ProfileExporter`.

#### Root Cause

The inline edge-record block was duplicating logic that already lives in
`Na__Exporter__BuildMeshEdgeRecord` and referenced a non-existent method name (missing
`Fallback` suffix, or stale from a prior API rename). Because the exception was rescued in
`Na__SceneProfileRegistry__SetFromEntity`, every scene pick silently returned the error
string rather than the extracted profile.

#### Fix

Replaced the 15-line inline block in `Na__SceneProfileRegistry__ExtractUnifiedGeometry`
(lines 264–278) with a single delegation call to the canonical exporter helper:

```ruby
# Before (broken)
material_name = edge.material ? edge.material.display_name.to_s : ''
colour_id = Na__ProfileExporter.Na__Exporter__ResolveEdgeColourId(material_name)
colour_hex = Na__ProfileExporter.Na__Exporter__ResolveEdgeColourHex(edge, colour_id)
mesh_edges << {
    'EdgeId' => edge_id,
    ...
    'EdgeColourHex' => colour_hex
}

# After (fixed — DRY delegation)
mesh_edges << Na__ProfileExporter.Na__Exporter__BuildMeshEdgeRecord(edge, edge_id, start_vertex_id, end_vertex_id)
```

`Na__Exporter__BuildMeshEdgeRecord` applies the full colour resolution chain used by the
library export path:
1. `Na__EdgeColourManager.Na__EdgeColours__CanonicalIdForMaterial` when `Na__EdgeColourManager`
   is available (correct colour ID + hex from the centralised edge-colour library).
2. `Na__Exporter__ResolveEdgeColourHexFallback` + edge material colour when the manager is
   absent.
3. `NA_DEFAULT_EDGE_HEX` (`#666666`) as a final safe fallback.

Scene-picked profiles now carry edge colours, soft/smooth flags, and hidden/shadow state
that are byte-for-byte identical to profiles produced via the full Create Profile editor,
satisfying the single-source-of-truth requirement.

#### Files Touched

| Path | Change |
|---|---|
| `02__Src__AppModules/20__System__ApplyProfileAlongPath/Na__ProfileTools__ApplyProfile__SceneProfileRegistry__.rb` | Replaced broken inline mesh-edge block with `Na__Exporter__BuildMeshEdgeRecord` delegation |

# ===============================================================================

# END OF DEVLOG
