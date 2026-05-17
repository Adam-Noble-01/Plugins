# Element Assembly Studio Pro - Architecture

## Product
Element Assembly Studio Pro by Noble Architecture is a SketchUp 2026 plugin that builds parametric architectural elements (windows, exterior doors, interior doors) inside the active model from an HtmlDialog UI.

## Top-level layout
```
Plugins/
  Na__ElementAssemblyStudioPro__Loader.rb              <-- SketchUp boots this
  Na__ArchTools__ElementAssemblyStudioPro__Modules__/  <-- everything else
    Na__AssemblyStudio__UiLayout__.html
    01__AppAssets__ElementAssemblyStudio/              brand assets
    02__Src__AppModules/                               source tree (numbered bands)
      01__AppCore/                                     dialog chrome, selection coordinator, UiBridge, shared Ui Controls/Events
      02__AppData/                                     AppConfig, ConfigLoader, MaterialManager, SerializerBase
      03__AppUtils/                                    DebugTools (unified), TagManager, SettingsTab UI
      04__GeometryHelpers/                             Box, Units, Fuse_Shared
      05__Viewport__2dPreviewEngine/                   generic SVG viewport factory
      06__Tools__MeasurementTools/                     TwoPoint + ThreePoint
      07__Tools__PlacementTools/                       WindowPlacementTool
      20__System__WindowSystem/                        window-specific code
      31__System__ExteriorSingleDoorSystem/            single exterior door panel + PanelInterface contract (filenames use ExtSingleDoor__ for MAX_PATH)
      32__System__ExteriorSlidingDoorSystem/           two-panel exterior sliding door (MVE-based translation)
      33__System__ExteriorMultiFoldingDoorSystem/      multi-panel exterior bifold door (ROT + MVE)
      40__System__InteriorDoorSystem/                  interior door tab
    03__Style__AppStylesheets/                         master CSS hub + brand/tab-strip stylesheets
    04__Data__AssetLibrary/                            interior-door asset JSON (architraves, handles, hinges)
    65__Dev__DevTools/                                 Na__ schema 2D/3D exporters + hierarchy metadata
    85__Docs__AppDocumentation/                        Architecture, DEVLOG, RewireMap, Tasks
    90__AppCache__TempFilesCache/                      plugin-local cache for live-fetched DataLib JSON
```

## Module conventions
- Ruby outer namespace: `module Na__AssemblyStudio`.
- Ruby per-system namespaces: `Na__AppCore`, `Na__AppData`, `Na__AppUtils`, `Na__GeometryHelpers`, `Na__MeasurementTools`, `Na__PlacementTools`, `Na__WindowSystem`, `Na__ExteriorSingleDoorSystem`, `Na__ExteriorSlidingDoorSystem`, `Na__ExteriorMultiFoldingDoorSystem`, `Na__InteriorDoorSystem`, `Na__DevTools`.
- File-segment shortening: where the full Ruby module name would push the absolute Windows path over the 260-char `MAX_PATH` limit, filenames use a shortened segment instead. The Ruby module name itself stays full for clarity. The shortening table is:

| Folder                                               | Ruby module                              | File segment used in filenames |
|------------------------------------------------------|------------------------------------------|--------------------------------|
| `40__System__InteriorDoorSystem`                     | `Na__InteriorDoorSystem`                 | `InteriorDoorSystem__` (full) — fits MAX_PATH |
| `40__System__InteriorDoorSystem` panel-style files   | `Na__PanelDesignStyles__*`               | `PanelStyle__*`                                |
| `31__System__ExteriorSingleDoorSystem`               | `Na__ExteriorSingleDoorSystem`           | `ExtSingleDoor__`                              |
| `32__System__ExteriorSlidingDoorSystem`              | `Na__ExteriorSlidingDoorSystem`          | `ExtSlide__`                                   |
| `33__System__ExteriorMultiFoldingDoorSystem`         | `Na__ExteriorMultiFoldingDoorSystem`     | `ExtFold__`                                    |
| `33__System__ExteriorMultiFoldingDoorSystem` layout files | n/a — sub-files                     | `Layout__<Algorithm>__` (e.g. `Layout__EqualEqual__`) |

  - Rationale: the longer folder names of the new sliding/multi-folding systems pushed `Na__AssemblyStudio__<full>__<deep-purpose>__.rb` over MAX_PATH. The very short `ExtSlide__` and `ExtFold__` segments (and `Layout__` instead of `LayoutAlgorithm__`) keep absolute paths comfortably below 260 chars. The folder names and Ruby module names stay full and self-documenting.
- File names follow `Na__AssemblyStudio__<Domain>__<Purpose>__.{rb,js,css,json,html}`.
- Method names use the `na_` prefix consistently.

## Single source of truth: AppConfig
`02__Src__AppModules/02__AppData/Na__AssemblyStudio__AppConfig__Main.json` is the single config file. The `Na__ConfigLoader` Ruby module exposes `na_get(*key_path)` for any module to read scoped defaults.

Sections:
- `metadata` - app/version
- `tabs` - registry of tabs the dialog should expose
- `debug` - debug + file-logging flags
- `attributeDictionaries` - per-system serializer parameters (used by `SerializerBase.na_config_from_app_config`)
- `measurement.callbacks` - host callback names for the measurement tools
- `devTools` - origin group name + export folder
- `assetLibrary` - root folder + remote URL + interior door bucket names (source-of-truth for AssetLibrary folder routing)
- `windowSystem.defaults` - window schema mm defaults
- `dxf.layers` - DXF layer names
- `theme.previewColors` - SVG preview hex colours

## Inter-system contracts
- `Na__ExteriorSingleDoorSystem::PanelInterface.na_build_panel(context)` - WindowSystem builds a `DoorPanelContext` struct and hands it over to construct door-panel-in-casement geometry.
- `Na__ExteriorSingleDoorSystem::PanelInterface.na_fuse_panel_steps(entities)` - WindowSystem's FuseParts step 5/6 delegates here.
- `Na__AppCore::SelectionCoordinator.na_register_handler(descriptor)` - each system registers a `{tab_id, resolve_id, on_selected, on_cleared}` descriptor; the coordinator dispatches a single observer to all systems.
- `Na__AppCore::DialogManager.na_register_system_init_hook(&block)` - each system Init registers a block that is invoked with the live dialog when the dialog opens; inside the block the system registers its callbacks via `UiBridge.na_register_callbacks(dialog, registry)`.

## Error handling policy
See `01__AppCore/Na__AssemblyStudio__AppCore__ErrorPolicy__.md`. In short:
- Narrow rescues only.
- Broad `rescue StandardError` only at the top of `add_action_callback` blocks.
- All diagnostic output through `DebugTools`; all user-visible status through `UiBridge.na_send_status`.
- No bare `rescue`, no `... rescue nil`, no `Integer(...) rescue false` (use `rescue ArgumentError, TypeError` instead).

## Loader install
The Plugins-root loader is `Na__ElementAssemblyStudioPro__Loader.rb`. SketchUp loads it on startup. The loader:
1. Resolves the modules root path.
2. Requires `02__Src__AppModules/01__AppCore/Na__AssemblyStudio__AppCore__Main__.rb`.
3. Registers a `UI::Command` that calls `Na__AssemblyStudio.na_init`.
4. Adds the command to the Plugins menu and the "Element Assembly Studio Pro" toolbar.

## Reference docs
- `RewireMap.md` - module-to-module wiring map (Ruby require graph + JS load order + JS<->Ruby callback table).
- `DEVLOG.md` - chronological refactor history.
- `01__AppCore/Na__AssemblyStudio__AppCore__ErrorPolicy__.md` - rescue policy.

## InteriorDoor handle behavior
- Interior single-door handle placement follows swing-side behavior.
- The previous dedicated handle-side selector is removed from the UI workflow.

## InteriorDoor rotation pivot helper (TrueVision3D contract)
`ROT001__RotationPoint__DoorHingeCentre` is the door's rotation pivot consumed by the downstream TrueVision3D `Na__DoorAnimation__` module, which reads `rotObject.position` (the group's local origin) as the pivot for the click-to-open animation.

- **No inner ADR wrapper**: the door's ComponentDefinition itself (`ADRnnn__InteriorDoor__`) is the ADR for TrueVision3D's prefix-matching scanner. MOD and ROT are direct siblings at the definition root - we deliberately do NOT wrap them in an inner `ADR001__InternalDoor` group because the GLB Builder collapses redundant single-child groups, which used to strip the MOD prefix and break the click-to-open animation.
- **Hierarchy placement**: the ROT group lives at the **ComponentDefinition root level** (sibling of the MOD group) so the SketchUp author can grab the pivot helper without drilling into the door panel hierarchy. A single ROT is shared between the closed and open MOD copies.
- **Pivot positioning**: the composer translates the ROT group to the hinge axis via `na_translate_rot_marker_to_hinge` and then `Na__RotationPivotBuilder.na_build_pivot_helper` populates it with visible debug geometry inside that group's local coordinate space (hinge centre = `(0, 0, 0)`).
- **Helper geometry**: a vertical hinge axis line inset 100 mm from the bottom and top of the inner jamb opening, a 50x50 mm `+` crosshair on the XY plane at each end of the line, and a quarter-circle swing-direction arc + arrowhead at the top crosshair (computed from `Na__DoorConfig__SwingSide` + `Na__DoorConfig__SwingDirection`).
- **Red colouring**: as the final build step every helper edge is painted red via `Na__EdgeColourManager.na_apply_edge_colour_to_group(rot_group, "MTE201__LineColour__Red")`. This mirrors the dark-grey edge-colour application used by `Na__PanelDesignBuilder` for door panel design linework, and ensures the helper is unambiguously red in SketchUp regardless of the active "colour by tag" display option.
- **Tag visibility control**: all helper edges are tagged on `02__DoorHelpers__RotationPivots`, which is red, dashed (`Sketchup::Layer#line_style = Sketchup.active_model.line_styles["Dash"]`), excluded from GLB export by both its `02__` numeric prefix (in `Na__DataLib__CoreIndex__Tags__.json` `meta.skipRanges`) and `Glb__FullyExcluded: true`.
- **MOD rotation direction (per swing direction)**: the moving panel group is named according to the door's `Na__DoorConfig__SwingDirection`, picked at build time by `Na__DoorAssemblyComposer.na_resolve_mod_panel_name(config)`:
    - **Outward** -> `MOD001__ROT__-90-Deg__DoorPanel` (clockwise when viewed from above in TrueVision3D)
    - **Inward** -> `MOD001__ROT__90-Deg__DoorPanel` (counterclockwise when viewed from above)
  TrueVision3D's `Na__DoorAnim__DEG_REGEX` (`/(-?\d+)-Deg/i`) parses the signed degrees from the group name to drive its click-to-open Y-axis rotation. The SketchUp open-state copy direction is computed independently from `SwingSide` + `SwingDirection` in `na_compute_open_rotation_transform` and remains visually consistent with the TV3D animation.
- **Module file** (one feature per file per workspace rules): `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__RotationPivotBuilder__.rb`.

### Tag line style configuration (Layout__LineStyleName)
Tag JSON entries gain an optional `Layout__LineStyleName` field (string) keyed off the SketchUp Ruby `Sketchup::LineStyles` collection. The list of supported names (case sensitive) is documented in the `LineStyleReference` block at the bottom of `Na__DataLib__CoreIndex__Tags__.json` along with a copy-paste tag template. `TagManager.na_get_or_create_tag` reads the field via `na_apply_line_style_for_role`, falls back to a small in-Ruby table (`NA_ROLE_DEFAULT_LINE_STYLES`), and applies via `Sketchup::Layer#line_style=` only if the active SketchUp version exposes the API.

## InteriorDoor handle asset + exporter contract
- Canonical handle contract template lives at `04__Data__AssetLibrary/InteriorDoor__Handles__/Na__StandardTemplate.json`.
- `65__Dev__DevTools/Na__AssemblyStudio__DevTools__JsonExporter2D__.rb` now emits Na__ unified roots (`meta`, `Na__Asset__Metadata`, and one of `Na__Asset__Plan2D` / `Na__Asset__Elevation2D`) rather than legacy ValeSpec keys.
- `65__Dev__DevTools/Na__AssemblyStudio__DevTools__JsonExporter3D__.rb` now exports:
  - standardized `Na__Asset__Mesh3D` vertices/faces (`VertexId`, `OuterLoop_VertexIds`) compatible with `Na__HandleBuilder3D`,
  - recursive nested Group/Component hierarchy metadata in `Na__Asset__ObjectHierarchy3D` with local+world transforms.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__.rb` resolves `handles / architraves / hinges` bucket folder names from AppConfig (`assetLibrary.interiorDoor.*`) with fallbacks.
- Current door viewport generators still render procedural 2D handle markers; they do not yet consume `Na__Asset__Plan2D` / `Na__Asset__Elevation2D` path geometry directly.

## Materials & Frame Finish Swatches (URL-first cache)

The plugin's frame-finish swatches (visible on the Window tab as "Frame Finish" and on the Interior Door tab as "Joinery Finish" + "Handle Finish") are sourced exclusively from the live materials JSON. There are NO hardcoded swatches in the JS layer.

### Data source
- Canonical file: `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json`
- Live URL: `https://raw.githubusercontent.com/Adam-Noble-01/Plugins/main/Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json`
- Two independent swatch palettes are declared inside `meta.Na__DataLib__UiDefaults`:
  - `Na__DataLib__UiDefaults__FrameFinish` -> 6 wood/paint swatches used by the Window's "Frame Finish" row AND the Door's "Joinery Finish" row (broadcasts to Lining + Panel + Architrave material IDs).
  - `Na__DataLib__UiDefaults__HandleFinish` -> 5 metal ironmongery swatches (Chrome, Brushed Steel, Satin Nickel, Unlacquered Brass, Bronze) used by the Door's "Handle Finish" row only.
- Each palette block holds three children: `...__SwatchKeys`, `...__DefaultSwatchKey`, `...__SwatchLabels`.
- Handle-finish materials live in the new `MAT600__MetalSeries__` group (IDs `MAT612` through `MAT616`), following the ValeSpec `MAT6XX__Metal__Ironmongery__*` convention. Brass + Bronze + Satin Nickel hex values are taken straight from ValeSpec's `ValeSpec__AppConfig__Main__.json`.

### Load flow on dialog open
1. `DialogManager.na_show_dialog` calls `MaterialManager.na_force_refresh_from_url`.
2. `MaterialManager` calls `Na__DataLib__CacheData.Na__Cache__LoadData(:materials, true)`.
3. The shared loader fetches the GitHub raw URL FIRST. On HTTP 200 it overwrites the cache file in `90__AppCache__TempFilesCache/`.
4. If the URL fails (offline, DNS, SSL, timeout) the loader reads the existing cache file from the same folder so the plugin keeps working with the last known good copy. **The cache file is never deleted.**
5. After the dialog HTML is loaded, the front-end fires `sketchup.na_requestFrameFinishSwatches()` which triggers `Na__FrameFinishSwatches.na_push_to_dialog` to set:
   - `window.NA_FRAME_FINISH_SWATCHES`      - array of `{id, label, hex}` (wood/paint)
   - `window.NA_FRAME_FINISH_DEFAULT_KEY`   - default ID for the frame palette
   - `window.NA_HANDLE_FINISH_SWATCHES`     - array of `{id, label, hex}` (metals)
   - `window.NA_HANDLE_FINISH_DEFAULT_KEY`  - default ID for the handle palette
   - `window.NA_MATERIALS_LOAD_STATUS`      - `'ok'` or `'failed'`
6. The push then invokes `Na_FrameFinishCards.na_render_all()` so the door's Joinery + Handle rows AND the window's Frame Finish row all populate immediately. Each row hides independently if its own palette is empty.

### Cache directory override
`Na__DataLib__CacheData` defaults to `Sketchup.temp_dir`. EASP overrides this in `na_init` via `Na__Cache__SetCacheDirOverride(NA_CACHE_DIR_PATH)` so cached files live in the plugin's own `90__AppCache__TempFilesCache/`. Other plugins (e.g. `Na__EdgeUtil__PaintDeepNestedEdges__`) do not set the override and continue using `Sketchup.temp_dir`.

### Failure UX
- If the materials JSON cannot be loaded (URL + cache + local fallback all fail), the door's Joinery Finish + Handle Finish sections and the window's Frame Finish control stay hidden -- no fallback swatches are emitted. This is intentional: empty UI = unambiguous "data missing" signal.
- A persistent toast appears in the shared `#na-status-bar` strip: "Na materials library could not be loaded from the web. Finish swatches are hidden - check internet connection." Persistent toasts are a new feature of `na_showStatus(type, message, persistent=true)` and `UiBridge.na_send_status(dialog, type, message, persistent: true)`.

### Hardcoded fallbacks (Ruby side)
Only two materials are hardcoded as a last-resort safety net so geometry can still be created when the materials library is unavailable:
- `MAT001__Default`
- `MAT101__GenericGlass`

These are created on the active model by `MaterialManager.na_ensure_safety_materials`. All other materials (timbers, paints, metals) come from the live JSON exclusively.

## Edge Colour Library (URL-first cache)

The plugin loads the Noble Architecture standard line-colour palette (MTE prefix) from the same `Na__Common__DataLib__CoreSuEntityStandards` repository that hosts face materials. The palette is consumed by the door panel design subsystem to paint generated linework with consistent dark-grey edges across every door.

### Data source
- Canonical file: `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__EdgeMaterials__.json`
- Live URL: `https://raw.githubusercontent.com/Adam-Noble-01/Plugins/main/Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__EdgeMaterials__.json`
- DataLib key: `:edge_materials` (registered alongside `:materials`, `:tags`, `:components`).
- Default panel-design colour: `MTE103__LineColour__DarkGrey__L40` (#666666).

### Load flow on dialog open
1. `DialogManager.na_show_dialog` calls `MaterialManager.na_force_refresh_from_url` AND `EdgeColourManager.na_force_refresh_from_url`.
2. `EdgeColourManager` calls `Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials, true)` (URL first, cache fallback, local plugin copy as last resort - cache file never deleted).
3. The flat `{ mte_id => entry_hash }` index is held in-memory for the session; subsequent `na_get_edge_material_by_id` calls resolve in O(1) and lazily create matching `Sketchup::Material` entries on the active model.
4. `EdgeColourManager.na_apply_edge_colour_to_group(group, mte_id)` recursively walks groups + component instances and assigns the resolved material to every `Sketchup::Edge` it finds. Used by `Na__PanelDesignBuilder` after each design build.

### Developer reload
The `Reload Scripts` flow purges the on-disk cache for both `:materials` AND `:edge_materials` and re-fetches both from the live URL before reloading any Ruby files, so the next dialog open is guaranteed to see the latest published palettes.

### Hardcoded fallback
Only one edge colour is hardcoded as a last-resort safety net: `MTE103__LineColour__DarkGrey__L40` at RGB(102, 102, 102). It is created by `EdgeColourManager.na_create_safety_dark_grey_material` if and only if the live library fails AND the canonical dark-grey id is requested. All other MTE colours come from the live JSON exclusively.

## Door Panel Design Subsystem

Decorative UK-style panel linework on the front and back faces of an interior door panel. Entirely separate from the door panel solid - never modifies the panel, never adds faces, only authors `Sketchup::Edge` instances inside a dedicated nested group.

### Group nesting hierarchy
```
ComponentDefinition: ADRnnn__InteriorDoor__       [outer ADR for TrueVision3D - ComponentDefinition itself]
  Na__Lining__Container                          [static]
  <architraves>                                  [static]
  Na__DoorSwing__2D                              [static]
  ROT001__RotationPoint__DoorHingeCentre         [origin = hinge; shared by closed + open MODs]
    <pivot helper edges>                         [tag: 02__DoorHelpers__RotationPivots, MTE201 red, dashed line style]
  MOD001__ROT__{NN}-Deg__DoorPanel (closed)      [tag: door_closed]   {NN} = -90 outward, +90 inward
    Na__DoorPanel__Solid
    <handle groups>
    Na__DoorPanel__DesignContainer
      Na__PanelDesign__FrontFace                 [edges only, Y = panel_front_y - 0.5mm]
      Na__PanelDesign__BackFace                  [edges only, Y = panel_back_y  + 0.5mm]
  MOD001__ROT__{NN}-Deg__DoorPanel (open copy)   [tag: door_open]    {NN} matches the closed MOD
    <duplicated MOD via Sketchup::Group#copy, rotated 90deg about the hinge>
```
There is NO inner `ADR001__InternalDoor` wrapper group around the MOD - the door's ComponentDefinition (`ADRnnn__InteriorDoor__`) is the ADR for TrueVision3D's prefix-matching scanner, and MOD/ROT sit as direct siblings inside it. A redundant single-child wrapper group would otherwise be flattened by the GLB Builder, stripping the MOD prefix that the click-to-open animation needs.
The container sits inside `MOD` so the linework rotates with the door. The open ADR copy is built by duplicating the closed ADR, so the design subsystem only needs to run once per build (no manual mirroring).

### Module layout (one responsibility per file)
- `02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__.rb` -> URL/cache loader for the MTE palette + per-edge material application.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__.rb` -> `na_compute_layout` resolves the inner perimeter from the four constraint sliders; `na_draw_inner_perimeter` draws the shared four-edge rectangle each style sits inside.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__VerticalNarrow__.rb` -> divides the inner perimeter into N equal panes where N = (inner_w / preferred_pane_w).round.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__ClassicalSix__.rb` -> Georgian 38/38/24% three-tier layout + central mullion = 2+2+2 panels.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__FourPanel__.rb` -> 2x2 grid (one cross-rail at mid-Z + one mullion at mid-X).
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__HorizontalThree__.rb` -> two cross-rails at 1/3 and 2/3 of inner-perimeter height (no mullion).
- Note: file segments use `PanelStyle__` rather than `PanelDesignStyles__` to keep the absolute Windows path under the 260-character `MAX_PATH` limit that SketchUp's Ruby `require_relative` enforces. The Ruby module names inside each file remain `Na__PanelDesignStyles__*` for clarity.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelDesignBuilder__.rb` -> orchestrator. Reads config, dispatches to the right style, wraps result in `Na__DoorPanel__DesignContainer`, applies edge colour.
- Geometry primitives `na_create_xz_line`, `na_create_horizontal_rail_lines`, `na_create_vertical_rail_lines` live on `Na__GeometryHelpers` so every style draws rails the same way.

### Configuration keys (Na__DoorConfiguration)
- `Na__DoorConfig__PanelDesignEnabled`              - master on/off (default `true`).
- `Na__DoorConfig__PanelDesignStyle`                - one of `None`, `VerticalNarrow`, `ClassicalSixPanel`, `FourPanel`, `HorizontalThree` (default `None`).
- `Na__DoorConfig__PanelDesignStileWidth_mm`        - side stile width, drives BOTH stiles (default `95`).
- `Na__DoorConfig__PanelDesignTopRail_mm`           - top rail height (default `100`).
- `Na__DoorConfig__PanelDesignBottomRail_mm`        - bottom rail height (default `200`).
- `Na__DoorConfig__PanelDesignInnerRailThickness_mm` - cross-rail / mullion thickness (default `70`).
- `Na__DoorConfig__PanelDesignVerticalPaneWidth_mm` - preferred pane width for VerticalNarrow only (default `90`).
- `Na__DoorConfig__PanelDesignEdgeColourId`         - MTE id for the linework (default `MTE103__LineColour__DarkGrey__L40`).

### Wiring
- `Na__DoorAssemblyComposer.na_compose_closed_assembly` calls `Na__PanelDesignBuilder.na_build_panel_design(config, mod_ents)` after `Na__HandleBuilder3D.na_build_handles`.
- `Na__InteriorDoorSystem.na_init_door_callbacks` -> `na_require_door_modules` requires all six new files (one EdgeColourManager + one Frame + four Styles + one Builder).
- The dialog UI exposes the new controls in `window.NA_DOOR_PANEL_TAB_CONFIG` (Panel & Swing tab). The Vertical Pane Width slider is hidden by `Na_DoorUI.na_sync_panel_design_visibility` for any style other than VerticalNarrow.
