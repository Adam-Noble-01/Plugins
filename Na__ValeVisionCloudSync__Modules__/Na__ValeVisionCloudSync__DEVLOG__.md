# ValeVision Cloud Sync — Development Log

## Version 1.0.0 — 25-Jun-2026

### Added
- Full plugin shell matching Na__Noble3dModellingTools architecture.
- Root loader `Na__ValeVisionCloudSync__Loader__.rb` in Plugins root.
- `02__Plugin__CoreAppData/`: UiCommandRegistry JSON, AppConfig JSON, CoreAppLoaders Main, ModuleLoaders Main, CommandRouter, HotkeyManager.
- `03__Plugin__CoreAppLogic/`: PathResolver, ConfigLoader, DialogManager, ReloadManager, ToolbarIconLoader.
- `05__Plugin__UserInterface/`: UiLayout HTML (Export + Settings tabs), Styles CSS (Vale navy branding), UiBridge JS.
- `06__Assets/`: Vale_Icon16px.png / Vale_Icon32px.png (copied from ValeDesignSuite).
- Export tab: project status card (model name, resolved root, IMG## count) + 4 sync action buttons + last sync report panel.
- Settings tab: project path override text field + Save/Clear buttons + Reload Plugin action card.
- Dialog callbacks: `run_command`, `na_vvcs_run_sync_action`, `na_vvcs_save_path_override`, `na_vvcs_clear_path_override`, `na_vvcs_dialog_ready`.
- Ruby push methods: `PushStatus`, `PushReport`, `PushProjectPathStatus` on `Na__DialogManager`.
- JS receivers: `Na__Vvcs__ReceiveReport`, `Na__Vvcs__ReceivePathStatus`.
- Hot reload via `Na__ReloadManager` (globs all *.rb, invalidates config cache, refreshes dialog).
- Vale icon toolbar button via `Na__ToolbarIconLoader`.
- Model dictionary persistence via `ValeVision__CloudExport` attribute dictionary.
- `Na__ModuleLoaders` safe-requires all 04__Plugin__SyncFeatures sub-modules; missing files warn and continue.

### Pending (subsequent todos)
- `04__Plugin__SyncFeatures/05__ProjectPathMapper` — derive project root from model path.
- `04__Plugin__SyncFeatures/01__SceneImageExporter` — port from ValeDesignSuite.
- `04__Plugin__SyncFeatures/02__CameraDataCapture` — IMG## page camera extraction.
- `04__Plugin__SyncFeatures/03__GlbExportBridge` + `04__GlbArchiver` — GLB export bridge.
- `04__Plugin__SyncFeatures/07__SyncOrchestrator` — shell out to Python orchestrator.
- Python `AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py`.
- ValeVision3D R2-first loading + `69__System` camera conversion utilities.
- Whitecardopedia R2-first loading.
