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
      30__System__ExteriorDoorSystem/                  door panel + PanelInterface contract
      40__System__InteriorDoorSystem/                  interior door tab
    03__Style__AppStylesheets/                         master CSS hub + brand/tab-strip stylesheets
    04__Data__AssetLibrary/                            interior-door asset JSON (architraves, handles, hinges)
    65__Dev__DevTools/                                 JSON exporters (2D/3D)
    85__Docs__AppDocumentation/                        Architecture, DEVLOG, RewireMap, Tasks
```

## Module conventions
- Ruby outer namespace: `module Na__AssemblyStudio`.
- Ruby per-system namespaces: `Na__AppCore`, `Na__AppData`, `Na__AppUtils`, `Na__GeometryHelpers`, `Na__MeasurementTools`, `Na__PlacementTools`, `Na__WindowSystem`, `Na__ExteriorDoorSystem`, `Na__InteriorDoorSystem`, `Na__DevTools`.
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
- `assetLibrary` - root folder + remote URL + interior door bucket names
- `windowSystem.defaults` - window schema mm defaults
- `dxf.layers` - DXF layer names
- `theme.previewColors` - SVG preview hex colours

## Inter-system contracts
- `Na__ExteriorDoorSystem::PanelInterface.na_build_panel(context)` - WindowSystem builds a `DoorPanelContext` struct and hands it over to construct door-panel-in-casement geometry.
- `Na__ExteriorDoorSystem::PanelInterface.na_fuse_panel_steps(entities)` - WindowSystem's FuseParts step 5/6 delegates here.
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
