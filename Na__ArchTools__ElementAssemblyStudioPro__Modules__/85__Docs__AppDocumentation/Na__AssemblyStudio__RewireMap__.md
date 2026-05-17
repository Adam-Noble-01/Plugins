# Element Assembly Studio Pro - Rewire Map

This document is the post-refactor map of how every module talks to every other module. Use it as the single reference when adding a new system, fixing a wiring bug, or reviewing the impact of a require/import path change.

## High-level flow

```
SketchUp loads Plugins/Na__ElementAssemblyStudioPro__Loader.rb
  └─ require 02__Src__AppModules/01__AppCore/Na__AssemblyStudio__AppCore__Main__.rb
        ├─ require AppUtils/DebugTools     (logger; everyone uses it)
        ├─ require AppUtils/TagManager
        ├─ require AppData/ConfigLoader    (AppConfig single source of truth)
        ├─ require AppData/MaterialManager
        ├─ require AppData/SerializerBase  (parameterised - each system subclasses)
        ├─ require GeometryHelpers/Box, Units, Fuse__Shared
        ├─ require AppCore/UiBridge        (JSON+execute_script helpers)
        ├─ require AppCore/DialogManager   (generic chrome only)
        ├─ require AppCore/SelectionCoordinator
        ├─ require Tools/MeasurementTools/{TwoPoint, ThreePoint}
        ├─ require Tools/PlacementTools/WindowPlacementTool
        ├─ require WindowSystem/Init                   (registers callbacks + selection handler)
        ├─ require ExteriorSingleDoorSystem/Init       (registers PanelInterface)
        ├─ require ExteriorSlidingDoorSystem/Init      (Phase-1 scaffold: selection handler stub registered)
        ├─ require ExteriorMultiFoldingDoorSystem/Init (Phase-1 scaffold: selection handler stub registered)
        └─ require InteriorDoorSystem/Init             (registers callbacks + selection handler)

User clicks toolbar button -> Na__AssemblyStudio.na_init
  ├─ load AppConfig
  ├─ MaterialManager.na_initialize_standard_materials
  ├─ <System>.Na__Init.na_init for each system (callbacks + handlers register)
  ├─ SelectionCoordinator.na_attach (one observer for everyone)
  └─ DialogManager.na_show_dialog (HTML + per-system Init hooks fire)
```

## Ruby require graph

```
                 +------------------+
                 |  Loader (root)   |
                 +---------+--------+
                           |
                  +--------v---------+
                  |  AppCore::Main   |
                  +-+-----+-----+-+-+
                    |     |     |  |
       +------------+     |     |  +-------------+
       |                  |     |                |
+------v------+   +-------v--+ +v--------+ +-----v---------+
| AppUtils    |   | AppData  | | Geometry| | Tools (06+07) |
| Debug, Tag  |   | Config,  | | Helpers | | TwoPt, 3Pt,   |
|             |   | Material,|         | | Placement     |
|             |   | Serializer|        | |               |
+-----+-------+   +----+-----+ +---+--+-+ +-------+-------+
      |                |          |              |
      +-------+--------+----------+              |
              |                                  |
        +-----v-----+   +-----------------+   +-------v-----+
        | WindowSys |-->| ExtSingleDoor   |<--| InteriorDoor|
        | (20s)     |   | (31s) [+32 +33] |   |    (40s)    |
        +-----+-----+   +-----------------+   +-----+-------+
              |              ^                       |
              | calls        | called by             |
              v              | Window's              v
         WindowSystem::      | FuseParts +           InteriorDoorSystem::
         DialogCallbacks    Geom (PanelInterface)    DialogRouter
              |                                    |
              +----- shared --------+--------------+
                                    v
                          AppCore::UiBridge
                       (one Ruby<->JS helper set)
```

## Inter-system contract: WindowSystem <-> ExteriorSingleDoorSystem

`Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::PanelInterface` is the only door-panel touchpoint that WindowSystem references. It exposes:

```
DoorPanelContext = Struct.new(
    :entities, :panel_id,
    :panel_x, :panel_z, :panel_width, :panel_height,
    :casement_depth, :frame_wall_inset, :casement_inset,
    :params, :frame_material
)

PanelInterface.na_build_panel(context) -> Sketchup::Group | nil
PanelInterface.na_fuse_panel_steps(entities) -> { fused, failed, skipped }
```

WindowSystem `GeometryEngine.na_render_door_casement_geometry` builds a `DoorPanelContext` and calls `PanelInterface.na_build_panel`. WindowSystem `FuseParts.na_fuse_window_parts` step 5/6 calls `PanelInterface.na_fuse_panel_steps`. ExteriorSingleDoorSystem owns the actual builder and fuse implementations behind the interface.

Note on file naming: the folder is `31__System__ExteriorSingleDoorSystem` and the Ruby module name is `Na__ExteriorSingleDoorSystem`, but the filenames inside use the abbreviated segment `ExtSingleDoor__` (e.g. `Na__AssemblyStudio__ExtSingleDoor__PanelInterface__.rb`) so the absolute Windows path stays under the 260-char `MAX_PATH` limit that SketchUp's Ruby `require_relative` enforces. This mirrors the pre-existing `PanelStyle__` precedent for the `Na__PanelDesignStyles__*` modules in `40__System__InteriorDoorSystem`.

## SelectionCoordinator handler registry

Each system registers a handler descriptor:

```
{
    :tab_id      => 'windows' | 'doors',
    :resolve_id  => proc { |instance| <id_string_or_nil> },
    :on_selected => proc { |instance, id| ... },
    :on_cleared  => proc { ... }
}
```

`AppCore::SelectionCoordinator` walks the registry on every selection change. Adding a new system never edits AppCore.

## DialogManager system init hook registry

Each system Init registers an init hook with `DialogManager.na_register_system_init_hook`. When the dialog opens, `DialogManager.na_invoke_system_init_hooks` fires every hook with the live dialog as the argument. The hook then registers its own callbacks via `UiBridge.na_register_callbacks(dialog, registry_hash)`.

This pattern means:
- AppCore::DialogManager carries no window/door knowledge.
- Adding a new system = write Init that registers a hook + a handler descriptor.

## JS load order (UiLayout.html)

```
01__AppCore JS              - BridgeBase, MainShell, UiSystem Controls/Events
                              (Controls/Events now expose binary_toggle case)
20__WindowSystem JS         - UiSystem Config (window schema)
31__ExtSingleDoor JS        - UiSystem Config (door-panel schema for door_mode)
32__ExtSlide JS             - UiSystem Config (sliding-door schema)            [Phase-1 scaffold]
33__ExtFold JS              - UiSystem Config (multi-fold schema)              [Phase-1 scaffold]
05__Viewport JS             - SvgHelpers, Validation, Controls, Instance
20__WindowSystem JS         - SvgGenerator, Export Dxf
32__ExtSlide JS             - Viewport Elevation+Plan generators              [Phase-1 scaffold]
33__ExtFold JS              - Viewport Elevation+Plan generators              [Phase-1 scaffold]
20__WindowSystem JS         - MainUiLogic, Bridge
32__ExtSlide JS             - MainUiLogic, Bridge                              [Phase-1 scaffold]
33__ExtFold JS              - MainUiLogic, Bridge                              [Phase-1 scaffold]
01__AppCore JS              - TabRouter, AppContext (must load AFTER tab modules)
03__AppUtils JS             - SettingsTab UiLogic, SettingsTab Bridge
40__InteriorDoorSystem      - UiSystem Config, Plan/Elev generators, MainUiLogic, Bridge
```

The TabRouter resolves tab modules by global name (`Na_DynamicUI`, `Na_DoorUI`, `Na_SettingsUI`) and via the `data-na-tab-id` attribute on tab buttons. Adding a new tab = add a button with `data-na-tab-id="newTab"` plus a JS module that exposes `Na_NewtabUI` (or `Na_<TabId>UI`).

## JS <-> Ruby callback table

| JS call                              | Ruby handler                                                              |
|--------------------------------------|---------------------------------------------------------------------------|
| sketchup.na_setActiveTab(id)         | AppCore::DialogManager core registry                                       |
| sketchup.na_jsLog(msg)               | AppCore::DialogManager core registry                                       |
| sketchup.na_reloadScripts            | AppCore::DialogManager core registry                                       |
| sketchup.na_settingsExport2D         | AppCore::DialogManager core registry                                       |
| sketchup.na_settingsExport3D         | AppCore::DialogManager core registry                                       |
| sketchup.na_createWindow(json)       | WindowSystem::DialogCallbacks                                              |
| sketchup.na_updateWindow(json)       | WindowSystem::DialogCallbacks                                              |
| sketchup.na_exportDxf(json)          | WindowSystem::DialogCallbacks                                              |
| sketchup.na_liveUpdate(json)         | WindowSystem::DialogCallbacks                                              |
| sketchup.na_requestConfig            | WindowSystem::DialogCallbacks                                              |
| sketchup.na_measureOpening           | WindowSystem::DialogCallbacks (activates TwoPointOpeningTool)              |
| sketchup.na_keyboard_tab             | WindowSystem::DialogCallbacks (forwards to active PlacementTool)           |
| sketchup.na_createDoor               | InteriorDoorSystem::DialogRouter                                           |
| sketchup.na_updateDoor               | InteriorDoorSystem::DialogRouter                                           |
| sketchup.na_liveUpdateDoor           | InteriorDoorSystem::DialogRouter                                           |
| sketchup.na_measureDoorOpening       | InteriorDoorSystem::DialogRouter (activates ThreePointOpeningTool)         |

| Ruby->JS function                    | Description                                                               |
|--------------------------------------|---------------------------------------------------------------------------|
| window.na_setInitialConfig(json)     | Push window config into the dialog                                         |
| window.na_clearCurrentWindow()       | Tell window UI to clear edit-mode state                                    |
| window.na_setInitialDoorConfig(json) | Push door config into the dialog                                           |
| window.na_clearCurrentDoor()         | Tell door UI to clear edit-mode state                                      |
| window.na_showStatus(type, msg)      | Update the status bar                                                      |
| window.na_receiveMeasurement(w,h,...) | Push 2-point measurement back to UI                                       |
| window.na_receiveDoorMeasurement(...)| Push 3-point measurement back to UI                                       |
| window.na_setPlacementActive(bool)   | Enable/disable the Tab key forwarder while placing a window                |
| window.na_measureCancelled()         | Clear measure-active styling on the button                                 |

All `Ruby -> JS` calls go through `AppCore::UiBridge.na_execute_json_function` / `na_execute_numeric_function` / `na_send_status` / `na_invoke`. No direct `dialog.execute_script("window.na_X(...)")` should appear anywhere outside `UiBridge`.

## InteriorDoor handle behavior

- Interior single-door handle behavior is driven by swing-side orientation.
- The explicit handle-side selector has been removed from the runtime UI schema.
- Legacy payloads carrying the retired handle-side key are pruned in both the JS UI payload builder and the Ruby dialog router before save/update paths.

## Fast navigation map (top-level folders)

- `01__AppAssets__ElementAssemblyStudio` - branding and toolbar assets.
- `02__Src__AppModules/01__AppCore` - shared dialog shell, tab routing, bridge base, selection coordinator.
- `02__Src__AppModules/02__AppData` - app config, material manager, serializer base.
- `02__Src__AppModules/03__AppUtils` - debug tools, tag manager, settings tab helpers.
- `02__Src__AppModules/04__GeometryHelpers` - shared geometry primitives and units.
- `02__Src__AppModules/05__Viewport__2dPreviewEngine` - generic SVG viewport engine.
- `02__Src__AppModules/06__Tools__MeasurementTools` - 2-point / 3-point opening tools.
- `02__Src__AppModules/07__Tools__PlacementTools` - placement tools.
- `02__Src__AppModules/20__System__WindowSystem` - window subsystem.
- `02__Src__AppModules/31__System__ExteriorSingleDoorSystem` - single exterior door subsystem (filenames use `ExtSingleDoor__` for MAX_PATH).
- `02__Src__AppModules/32__System__ExteriorSlidingDoorSystem` - two-panel sliding exterior door subsystem (Phase-1 scaffold; filenames use the very short `ExtSlide__` segment because the longer folder name pushes deeper filenames past the 260-char `MAX_PATH` limit).
- `02__Src__AppModules/33__System__ExteriorMultiFoldingDoorSystem` - multi-panel bifolding exterior door subsystem (Phase-1 scaffold; filenames use the very short `ExtFold__` segment for MAX_PATH; per-layout sub-files use `Layout__<Algorithm>__`, e.g. `Layout__EqualEqual__`, `Layout__AllOneWay__`, `Layout__MasterSlaves__`).
- `02__Src__AppModules/40__System__InteriorDoorSystem` - interior door subsystem.
- `03__Style__AppStylesheets` - app stylesheets.
- `04__Data__AssetLibrary` - handle/architrave/hinge asset JSON.
- `65__Dev__DevTools` - dev-only exporters and utilities.
- `85__Docs__AppDocumentation` - architecture, rewire map, devlog, tasks.
