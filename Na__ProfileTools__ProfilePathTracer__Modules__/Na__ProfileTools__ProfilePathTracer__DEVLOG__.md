# Na__ProfileTools__ProfilePathTracer - DEVLOG
# =======================================================================================
## Version History

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
