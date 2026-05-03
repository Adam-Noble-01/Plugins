# Element Assembly Studio Pro - DEVLOG

## v1.0.1 - Refactor & Rebrand (Window Configurator Tool -> Element Assembly Studio Pro)

### USER-SIDE INSTALL STEP (do this once when SketchUp is closed)

When SketchUp is fully closed:
1. Delete the OLD plugin folder `Plugins\Na__ArchTools__3dWindowConfigTool__Modules__\` (it is now superseded by the v2 sibling folder created during this refactor and is no longer required at runtime).
2. Delete the OLD loader `Plugins\Na__WindowConfiguratorTool__Loader.rb`.
3. Confirm the NEW loader `Plugins\Na__ElementAssemblyStudioPro__Loader.rb` is present.
4. Confirm the NEW modules folder `Plugins\Na__ArchTools__ElementAssemblyStudioPro__Modules__\` is present.
5. Restart SketchUp. The "Element Assembly Studio Pro" toolbar/menu item replaces the old "Na Window Configurator" entry.

The folder rename was attempted during the refactor but blocked because SketchUp had file handles open inside the old folder. A pre-refactor git tag (`v1.0.1-pre-EASP-refactor`) is in place if rollback is needed.

### Headline changes
- **Rebrand** to "Element Assembly Studio Pro by Noble Architecture".
- **Top bar** now shows the Noble Architecture logo on the left and the EASP wordmark + "by Noble Architecture" subline on the right. The Live Mode + Measure Opening buttons moved out of the top bar onto the tab strip line, right-aligned.
- **Loader rewritten**: new file name, new folder/file paths, new icon (Custom toolbar icon typo fixed), new command + toolbar names, new boot log lines.
- **Single source of truth `AppConfig`**: `02__AppData/Na__AssemblyStudio__AppConfig__Main.json` consolidates DXF layers, window default mm, theme colours, attribute dictionaries, measurement callback names, asset URLs, debug flags. `Na__ConfigLoader` exposes `na_get`.
- **AppCore extracted from the 1037-line DialogManager**: generic chrome (`AppCore::DialogManager`) is now ~400 lines; window CRUD/DXF/live/measure-host moved to `WindowSystem::DialogCallbacks`; JSON-escape + execute_script boilerplate replaced by `AppCore::UiBridge.na_execute_json_function` / `na_execute_numeric_function` / `na_send_status` / `na_register_callbacks`.
- **SelectionCoordinator** replaces the old multi-system observer with a registry pattern. Each system registers a `{tab_id, resolve_id, on_selected, on_cleared}` descriptor; AppCore knows nothing window- or door-specific.
- **WindowSystem <-> ExteriorDoorSystem PanelInterface contract**: door-panel construction is no longer hard-coded inside the window engine. WindowSystem builds a `DoorPanelContext` struct and calls `PanelInterface.na_build_panel`. Door-panel + door-trim fuse steps moved out of window FuseParts into `ExteriorDoorSystem::Na__FuseParts__DoorPanel`.
- **InteriorDoorSystem renamed** from `Na__InteriorDoorConfigurator` to `Na__AssemblyStudio::Na__InteriorDoorSystem`. New `Na__Init` partial registers door callbacks + door selection handler against AppCore.
- **DebugTools merged** as a feature-superset (kept window's file logging / toggle / timing / selection / window-data summary; added door's per-channel prefixes). Sole logger across the codebase.
- **TagManager lifted** out of door system into `03__AppUtils` so any system can tag entities.
- **MaterialManager rebranded**, dead `na_cleanup_old_materials` removed, all `puts` routed through DebugTools.
- **SerializerBase parameterised**: window + door serializers subclass it (parameterised on dictionary names, key strings, ID regex, ID format, definition prefix). Door also gains JSON export/import parity it previously lacked.
- **GeometryHelpers per-method split**: only `na_create_grouped_box` (with optional material) and `na_mm_to_inch` are shared. All system-specific helpers stay in `<System>::Na__GeometryHelpers`.
- **Fuse__Shared** unifies `na_sequential_outer_shell` with window-strict default; door's tolerant behaviour available via `on_nil: :continue` opt-in.
- **Generic viewport** (SvgHelpers, Validation, Controls, Instance factory) lives in `05__Viewport__2dPreviewEngine`. SvgHelpers is the sole owner of `na_num`/`na_bool`/`na_make_svg`.
- **Measurement tools** moved to `06__Tools__MeasurementTools`. ThreePoint constructor now accepts callback names + status label as constructor parameters instead of hard-coding "Measure Door Opening" + `na_send_door_measurement_to_dialog`.
- **PlacementTool** moved to `07__Tools__PlacementTools` with explicit `require_relative` to AppCore::DialogManager (was relying on load order).
- **AppCore JS** owns `Na__Ui__Controls` and `Na__Ui__Events` (lifted from the window tool) so InteriorDoor stops reimplementing `na_build_slider_control` etc. - both systems now consume the shared engine.
- **TabRouter bug fix**: it called `na_get_active_config` but the IIFE only exposed `na_getConfig`. The new TabRouter falls back to `na_getConfig` when `na_get_active_config` is missing, so neither rename was forced.
- **CSS split** into a master index hub (`03__Style__AppStylesheets/Na__AssemblyStudio__CoreUi__Styles__Index__.css`) that imports the new `BrandHeader` and `TabStrip` stylesheets plus the legacy combined stylesheet. Per-system CSS files are a planned follow-up.
- **HTML rewritten** with the new top bar, the moved buttons, the new ordered `<script>` list reflecting the new file paths. Dropped the unused `bezier.js` + `browser.maker.js` script tags.
- **DEAD CODE removed / flagged**:
  - `na_cleanup_old_materials` deleted from MaterialManager.
  - `na_delete_window_data`, `na_has_window_data?`, `na_export_window_data_json`, `na_import_window_data_json`, `na_delete_door_data`, `na_has_door_data?` left as-is in the new SerializerBase-backed serializers because the parameterised base now exposes them as `na_delete` / `na_has_data?` / `na_export_json` / `na_import_json` for any system that needs them.
- **Convoluted-pass items applied**:
  - `Pathname#relative_path_from` replaces manual `tr/string-concat` in DialogManager reload formatter.
  - `JSON.generate + gsub + execute_script` boilerplate replaced by UiBridge helpers (4+ duplications collapsed).
  - All raw `puts` outside the loader routed through DebugTools.
  - `add_action_callback` registration is now table-driven via `UiBridge.na_register_callbacks(dialog, registry_hash)`.
- **Stale dev artefacts deleted** from the modules folder: `.cursor/rules/*.--BAK`, `.cursor/debug.log`, `.code-workspace` referencing the previous developer's path, the `ZZ__` Loader copy.
- **Brand assets** moved to `01__AppAssets__ElementAssemblyStudio/`. The icon filename typo `Cutom -> Custom` was fixed.
- **Dev tools** moved to root `65__Dev__DevTools/` (Vale convention).
- **Asset library** moved to root `04__Data__AssetLibrary/` with new `AssetIndex.json`. The hardcoded `raw.githubusercontent.com/Adam-Noble-01/...` URL inside the shipped JSON is now superseded by `AppConfig.assetLibrary.remoteBaseUrl`; the JSON files retain the old URL string as harmless metadata.

### Pre-refactor snapshot
- Git tag: `v1.0.1-pre-EASP-refactor`.

### Known follow-ups (not blocking v2.0.0 release)
1. Per-system CSS files: split `Na__AssemblyStudio__Styles__Combined__.css` into `20__/30__/40__/03__AppUtils` per-system stylesheets and update the master index `@import` list.
2. GeometryEngine `if/elsif` mode tree -> `{mode => builder_lambda}` registry refactor (file is functional today but the tree is still procedural).
3. Frame thickness helpers (`na_getEffectiveFrameThicknesses`, `na_resolveFrameSideThickness`) currently live in three places. Single owner planned in `20__System__WindowSystem/...Viewport__FrameThicknessHelpers__.js`.
4. Window-specific `OpeningIndexParse` (`Integer(...) rescue ArgumentError, TypeError`) extraction. Currently still inline in GeometryEngine + DxfExporter.
5. Glazebar key predicates (`na_get_glazebar_key`, `na_glazebar_removed?`) still duplicated between DxfExporter and GeometryBuilders. Extraction planned in `20__System__WindowSystem/...Glazebar__Shared__.rb`.
6. Convergence of InteriorDoor `na_build_slider_control` / `na_build_select_control` / `na_build_checkbox_control` to use the shared `Na__Ui__Controls` engine. The shared engine is in place; the InteriorDoor MainUiLogic still uses its private builders for now.
7. AppContext + TabRouter still hardcode the three tab IDs (`windows`, `doors`, `settings`). Driving them from `AppConfig.tabs` is a small follow-up.
8. The asset JSON's `Data__URL` GitHub path is now metadata - actual loading should read `AppConfig.assetLibrary.remoteBaseUrl`. Migration of any code that still reads the field directly is a small follow-up.

## v1.0.1 - 01-May-2026 (pre-rebrand)
Major overhaul - Interior Door Configurator integrated into a new tab.
