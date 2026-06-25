# ValeVision Cloud Sync — Development Log

## Version 0.1.5 — 25-Jun-2026

### Fixed
- "Python produced no JSON report (exit code: 0)" with **empty** stdout *and* stderr, even with a verified real interpreter: the orchestrator was spawning the external `python.exe` with SketchUp's inherited environment. SketchUp 2026 ships its own embedded CPython and exports `PYTHONHOME`/`PYTHONPATH` into the process environment; those are inherited by the child and poison the real interpreter (it tries to use SketchUp's stdlib), producing no usable output. `na_execute_python` now launches Python with a **sanitized environment** — `PYTHONHOME`, `PYTHONPATH`, `PYTHONSTARTUP`, `PYTHONEXECUTABLE`, `PYTHONNOUSERSITE` and `__PYVENV_LAUNCHER__` are stripped, and `PYTHONUTF8=1`, `PYTHONIOENCODING=utf-8`, `PYTHONUNBUFFERED=1` are forced. The PATH-launcher probe uses the same sanitized env.

### Added
- The Python run log (`99__Logs/Na__ValeVisionCloudSync__PythonRun__<timestamp>.log`) now records the inherited `PYTHON*` variables that were present (and sanitized) before launch, so any future environment poisoning is immediately visible.

# =============================================================================


## Version 0.1.4 — 25-Jun-2026

### Fixed
- "No JSON from Python (python). Output: (empty)" persisting inside SketchUp: the previous probe-based resolution could still fall through to the Windows Store `python` stub when SketchUp's child-process environment differed from a normal shell. `na_resolve_python_executable` now resolves an **absolute** `python.exe` straight from disk via `File.exist?` (newest `Python3*` first, under `%LOCALAPPDATA%\Programs\Python`, `C:\Python3*`, and the `Program Files` install dirs) and uses it directly — no PATH lookup, no child-process probe (which itself can misbehave under SketchUp), and never the WindowsApps stub. PATH launchers (`py -3`/`python3`/`python`) remain a probed fallback; bare `python` is the explicit last resort.
- Camera scene data + image list now propagate to Whitecardopedia/R2: the Python orchestrator rebuilds `project.json.images` from the IMG## PNGs actually cloned into the web folder (so newly added scenes like `IMG02` appear and stale dated filenames are dropped) before thumbnails/upload/camera merge.

### Added
- Much clearer dialog reporting for the R2/Whitecardopedia step:
  - A dedicated **Python Interpreter** report line shows exactly which interpreter was chosen (and is flagged ERR if it had to fall back to an untrusted one).
  - On any non-JSON outcome the report now shows a multi-line diagnostic — exit code, the full command, stdout/stderr tails, and the path to a full run log written to `99__Logs/Na__ValeVisionCloudSync__PythonRun__<timestamp>.log` — plus an explicit hint to set `python_executable` when output is empty (the Store-stub signature).
  - The dialog renders multi-line step messages (newline → `<br>`) and wraps long paths/commands.

# =============================================================================


## Version 0.1.3 — 25-Jun-2026

### Fixed
- Camera capture "ProjectData JSON not found" and GLB "no new GLB files detected": Ruby `Dir.glob` treats `\` as an escape character, so backslash Windows paths silently matched nothing. Resolved project paths are now normalised to forward slashes at the source in `ProjectPathMapper` (`DeriveProjectRoot`, override read, `MapProjectSubfolders`, `ResolveEditionFolder`) and defensively at every `Dir.glob` call site (`ProjectDataWriter`, `GlbExportBridge`, `GlbArchiver`, `SceneImageExporter`, `ReloadManager`).
- GLB export success detection no longer relies on a brittle before/after count (the builder overwrites in place). It now treats any `*.glb` or `GlbBuilder__ExportLog__*.txt` written at/after the export start as proof of a fresh export.
- Python interpreter resolution hardened: `na_resolve_python_executable` now probes absolute-path candidates first (config override, `%LOCALAPPDATA%\Programs\Python\Launcher\py.exe -3`, `Python3*\python.exe` globs, `C:\Python3*`, `C:\Program Files\Python3*`) before PATH launchers, and rejects any candidate whose `sys.executable` resolves under `WindowsApps` (the Store stub).
- Added optional `python_executable` key to the AppConfig `python` block as an SSOT override.

# =============================================================================


## Version 0.1.2 — 25-Jun-2026

### Fixed
- Sync action buttons `Sync Project`, `Update GLB Models`, and `Update Camera Data` no longer fail with "Unknown sync scope": orchestrator `SYNC_SCOPE_*` constants now match the UI action IDs (`sync_project`, `update_glb_models`, `update_camera_data`).
- "No JSON report from Python orchestrator": SketchUp's bare `python` could resolve to the Windows Store app-execution stub (exits 0, prints no JSON). Added `na_resolve_python_executable` which prefers the `py -3` launcher (with `python3`/`python` fallbacks and a `python_executable` config override) and probes each candidate before use.
- Python shell-out failures now surface the captured stdout/stderr tail in the report instead of a generic message, making diagnosis possible from the dialog.

# =============================================================================


## Version 0.1.0 — 25-Jun-2026

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
