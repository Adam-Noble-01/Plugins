# Na__ProfileTools__ProfilePathTracer - DEVLOG
# =======================================================================================
## Version History

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

# =======================================================================================

# END OF DEVLOG
