# ValeVision Cloud Sync — Development Log

## Version 0.5.1 — 07-Oct-2026 — GLB Syncs Purge the Previous Set (Archived), on the PC and on the Server

### Overview
**Asked by Adam:** resyncing GLB models did not purge the previous ones. Duplicates kept being
added, and a tag removed in SketchUp left its old model in the folder. After every GLB sync the
GLB folder must hold only that sync's GLBs. The previous set is zipped into `00__Archive` as
`ProjectName__ArchivedGlbFiles__DD-MMM-YYYY__.zip`, and the older archive zip is deleted.

**Why stale models appeared (two causes):**
1. **SketchUp export folder.** The GLB builder overwrites in place and never removes a file.
   The archiver zipped the old GLBs but left them in `ValeVision__GlbFileSync`, so the
   publisher picked up every GLB there, old ones included, and listed them all in the record.
   Live example: `64135__Holt` had 42 models published on 07-Oct, its own 21 plus 21 stale
   `Washington__…` copies from before the model was renamed.
2. **Server.** The push never deletes content (by design), so every GLB ever pushed stayed in
   the server's GLB folder.

### Changed
- **Each sync, in each GLB folder:**
  1. make `00__Archive`;
  2. zip the previous GLBs into it and read the zip back (every entry, every CRC);
  3. delete the older archive zip;
  4. write the new GLBs, with no older GLB left in the folder.

  It is applied at all three places the models live:

  | Where | Who | Archive name |
  |---|---|---|
  | SketchUp project: `10__ContentDelivered__Local/ValeVision__GlbFileSync/` | `Na__GlbArchiver` 1.0.1, before the builder exports | `<SketchUp project folder>__ArchivedGlbFiles__DD-MMM-YYYY__.zip` |
  | Project Library on the PC: `<id>/ValeVision3D/Content__3dModel__GlbFiles/` | `LibraryPublisher` 1.0.1, new step "Archive Previous GLBs" | `<library id>__ArchivedGlbFiles__DD-MMM-YYYY__.zip` |
  | Server: the same folder under `/srv/vale/…` | the push, with the engine's new `--prune` (Server Manager 0.6.2) | the PC's zip, pushed |

- **Server:**
  - every GLB sync (Sync Project, Update GLB Models) runs
    `push projects --scope <year>/<id> --prune <year>/<id>/ValeVision3D/Content__3dModel__GlbFiles`;
  - the server's GLB folder ends up an exact copy of the PC's: superseded GLBs and the older
    archive zip are deleted there;
  - each deleted file is backed up in `/srv/vale-sync/backups/<stamp>/` first, so
    `engine undo projects` puts them back;
  - the Push step reports "n superseded file(s) removed from the server's GLB folder";
  - nothing outside that one folder can be deleted.
- **Unchanged set:** if a sync's GLBs are byte-identical to the last set, the archive is kept
  (SKIP). Re-zipping the same set would throw away the real previous one.
- **Same day:** a second sync on the same day replaces that day's zip.
- **Empty export** (e.g. a failed export): the publisher stops at Check Exported Files, as
  before, and the engine refuses to prune a folder that is empty on the PC. A bad export can
  never empty the server's GLB folder.
- **Verify Library** also fails on a GLB in the bucket that the record does not list.
- **The local zip writer is fixed.** Every `00__ArchivedModels` zip written since 25-Jun-2026
  is unreadable: the local file header was 2 bytes short (a field missing from the `pack`
  format) and the data was zlib-wrapped. Python and Windows could not open them. The data is
  still there (488 of the 521 models in the 50 zips checked on 07-Oct), so a repair script
  could recover them. The new writer uses raw deflate, a full 30-byte header and UTF-8 names,
  and reads each zip back before any GLB is deleted.
- **Old folders:** the old `00__ArchivedModels` folders are left as they are. The new archive
  is `00__Archive`, and the AppConfig `glb_archives` path follows.

### Needs
- Vale Virtual Server Manager **0.6.2** or later (`--prune`). An older engine stops the push
  with "the engine is older than 0.6.2 (no --prune)"; the library is still published.

### Tested (sandbox; no real server, library or SketchUp folder touched)
- **The real publisher and engine end to end:** a fake ssh runs the server agent against a
  folder, with an isolated gateway state, ledger and sync map. 38 checks pass:
  - **Run 1** (A changed, B the same, C new; stale W on both sides, S1 on the server only, an
    older archive):
    - the PC and the server each hold exactly A, B and C, plus one byte-identical zip of the
      previous A (old bytes), B and W;
    - W, S1, the old zip and the replaced A are in the server backup;
    - the record lists A, B and C, with `_rev` and other keys kept;
    - another project's server-only GLB and the user data are untouched.
  - **Run 2** (no change): the archive step is SKIP, the zip is unchanged, nothing is removed.
  - **Run 3** (C's tag deleted): C is gone from the server, and today's zip is replaced with A,
    B and C.
  - **Undo:** `undo projects` brings C back.
  - **Refused, with no session opened:** `--prune` without `--scope`, the whole scope, a shared
    or user-data folder, a folder outside the scope, `..`, and an empty PC folder.
  - **Empty export:** stops before anything moves.
- **The server agent alone** refuses crafted plans that prune a record, another project's GLB
  or a user-data file.
- **The Ruby archiver, in SketchUp's own Ruby 3.2.2 (bundled DLL, no SketchUp):**
  - all 19 plugin `.rb` files compile;
  - 17 archiver checks pass: archive and clear, the older zip removed, the log kept, an empty
    folder keeps its archive, a same-day replacement, a corrupt zip caught by the read-back, a
    failed read-back deleting nothing and leaving no temp file;
  - its zips open with Python `zipfile` (`testzip` clean) and with Windows `Expand-Archive`,
    including a non-ASCII name.
- **Not run:** a sync inside SketchUp and a push to the live server. That is Adam's first
  Update GLB Models.

### Files Changed
- `04__Plugin__SyncFeatures/04__GlbArchiver/Na__ValeVisionCloudSync__GlbArchiver__.rb` (1.0.1)
- `04__Plugin__SyncFeatures/03__GlbExportBridge/Na__ValeVisionCloudSync__GlbExportBridge__.rb` (1.2.1)
- `04__Plugin__SyncFeatures/08__LibraryPublisher/Na__ValeVisionCloudSync__LibraryPublisher__.py` (1.0.1)
- `02__Plugin__CoreAppData/Na__ValeVisionCloudSync__CoreAppData__AppConfig__.json`,
  `03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__ConfigLoader__.rb` (`glb_archives` path)
- Companion: Vale Virtual Server Manager 0.6.2 (`VirtualServerManager__SyncEngine__.py`: `--prune`).

# =============================================================================


## Version 0.5.0 — 06-Oct-2026 — Publish to the Project Library, Push This Project to app.valegardenhouses.com (R2 Retired)

### Overview
Cloudflare R2, the Cloudflare Workers and GitHub Pages are gone: every Vale web app now
runs on one server (app.valegardenhouses.com), which is an exact copy of
`WebApps/Vale__VirtualServer` on Adam's PC. The last step of every sync button no
longer runs the retired Gallery-folder script (`Whitecardopedia/Tools__DevUtils/
AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py`). It now:
1. collects the exports into the **Vale Projects Master Library** on this PC
   (`Vale__Projects__MasterLibrary/ValeProjects__<yyyy>/<id>/`) and checks them;
2. runs the **Vale Virtual Server Manager's sync engine for this one project folder**
   (`push projects --scope ValeProjects__<yyyy>/<id>`), the same SSH sync Adam's app
   uses, with its lock, backups, journal and undo.

The SketchUp exports themselves (images, cameras, GLBs, archives) are unchanged and still
land in the SketchUp project folder (`C:/01__ValeProjects/...`).

### Added
- **`08__LibraryPublisher/Na__ValeVisionCloudSync__LibraryPublisher__.py`** (1.0.0): the
  new last step, one launch per button, all-or-nothing on the library side:
  - **Resolve:** finds `ValeProjects__<yyyy>/<id>` in the library, which it reads from the
    engine's own sync map, so it publishes exactly where the push reads from.
  - **Check Exported Files:** before anything moves. PNGs complete (signature, IHDR, IEND),
    GLBs complete (glTF 2 header, declared length = file size, JSON chunk), camera data
    present, no two GLBs colliding after the rename. A bad export stops the sync with
    nothing published and no server session.
  - **Fetch Server Copy:** `collect projects --scope <project>` first, so web edits to the
    record (Dev menus, Gallery editor) are merged into, never overwritten. If the server
    cannot be reached, **nothing** is published.
  - **Publish:**
    - full PNGs go to `ValeVisionGallery/Content__GalleryImages__FullQuality__VariantImages`;
    - 524p WebP goes to `…Thumbnail__VariantImages` and
      `ValeVision3D/Content__AnimationScenes__Thumbnails`;
    - 524p JPG goes to `…524p__VariantImages`;
    - GLBs go to `ValeVision3D/Content__3dModel__GlbFiles`.

    Identical files are left alone, so nothing is pushed needlessly. Only this pipeline's
    old files are removed from the buckets: other images (e.g. hand-added photomatch
    renders) are never touched.
  - **Update Project Record:** only the sync's own keys in `ProjectData__<id>__.json`:
    - `images` / `allImages` / `displayImages` (hand-added images kept);
    - `thumbnailImage`;
    - `valeVision_ModelUrls` (bare, sorted file names);
    - `ValeVison3D__SketchUpCameraData`;
    - the Views-bar `PresentationMode__Scene__ThumbnailUrl` re-point.

    Every other key, `_rev` included, is unchanged. The file keeps the library style
    (4-space JSON, own newline state), and its time is always set later than the server
    copy it was merged into, so a server clock that runs ahead cannot block the push.
  - **Verify Library:** every name the record lists must be in its bucket.
  - **Push To Server:** this project folder only. Files newer on the server are left alone
    and reported.
  - **New projects:** the library folder and a fresh record are created (code, name,
    ProjectType from the folder suffix, MaxEngine block for MaxModel, designer / concept
    artist from the local `Project__MetaData`).
- **Library Project** (`ProjectPathMapper` 1.2.0): the id is the SketchUp folder name
  without `__Whitecard` / `__Blockout` / `__MaxModel` (the old Gallery rule), or the
  `library_project_id` override saved in the model (Settings tab).
  - A model whose library project does not exist yet asks before the sync creates it: the
    id is permanent once it is on the server.
  - An id found in two year folders stops with a message.
- **Dialog:**
  - The Export tab shows the Library Project (existing / NEW / problem) and the Server mode.
  - Settings has a Project Library group: the folder, Save Library Project, Use Folder Name.
  - Skipped steps show SKIP.

### Changed
- **`SyncOrchestrator` 2.0.0:**
  - every button's last step runs the publisher;
  - the library project is resolved before the slow exports;
  - a failed export step means nothing is published or pushed;
  - the final message carries the publisher's own result ("Synced 64135__Holt to
    app.valegardenhouses.com." / "Published to the Project Library (not pushed).").
- **AppConfig:** the `python` block keeps only `python_executable`. The `cdn` block (R2 and
  GitHub URLs) is gone. A new `library` block holds:
  - `publisher_script`;
  - the Server Manager's `manager_root`, `engine_script` and `sync_map` (absolute paths are
    allowed, e.g. a sandbox sync map);
  - `mapping_id`;
  - `push_to_server` (false = publish locally only);
  - `site_base_url`.
- **Wording:** every R2 / Cloudflare / retired Gallery name is gone from the dialog,
  tooltips and run logs.

### Needs
- The Vale Virtual Server Manager **0.6.0** or later (the engine's `--scope` and
  `--report-file`).
- Pillow in the Python the plugin finds (thumbnails). The run stops with the pip command if
  it is missing.
- A key in the Windows ssh-agent, as for any Manager push.

### Tested (sandbox; no real server, library or SketchUp folder touched)
- A copy of `64135__Holt` and `64135__Holt__MaxModel`, a fake server folder, and the real
  engine over a fake ssh. All 30 checks pass:
  - a web edit and `_rev` on the server survive the sync;
  - a new IMG09 appears in all four buckets with a 524 px thumbnail;
  - only the changed GLB is pushed (6 files, 2.9 MB);
  - another project's unpushed PC change is **not** pushed;
  - a second run has nothing to push;
  - a truncated GLB stops the sync with nothing moved;
  - a server refusal (cooldown) publishes nothing;
  - local-only opens no session;
  - a new project is refused without the user's OK, then created and pushed;
  - all of the above also hold with the server clock 120 s ahead.
- The record rules against the retired script's own functions on all 11 library records
  with Views-bar scenes (same edition, newer edition, a dropped slot): 33 cases, identical.
- The dialog HTML and JS were checked in a browser (both tabs, NEW / existing / SKIP).
- **The Ruby was not run.** There is no Ruby on the PC outside SketchUp, so the first run
  in SketchUp is the Ruby test (Reload Plugin, then Settings, then one sync).

### Files Changed
- `04__Plugin__SyncFeatures/08__LibraryPublisher/Na__ValeVisionCloudSync__LibraryPublisher__.py` (new)
- `04__Plugin__SyncFeatures/07__SyncOrchestrator/Na__ValeVisionCloudSync__SyncOrchestrator__.rb`
- `04__Plugin__SyncFeatures/05__ProjectPathMapper/Na__ValeVisionCloudSync__ProjectPathMapper__.rb`
- `03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__ConfigLoader__.rb`
- `03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__DialogManager__.rb`
- `02__Plugin__CoreAppData/Na__ValeVisionCloudSync__CoreAppData__AppConfig__.json`
- `02__Plugin__CoreAppData/Na__ValeVisionCloudSync__CoreAppData__UiCommandRegistry__.json`
- `05__Plugin__UserInterface/` (UiLayout, UiBridge 1.2.0, Styles)
- Companion: Vale Virtual Server Manager 0.6.0 (`VirtualServerManager__SyncEngine__.py`).

# =============================================================================


## Version 0.4.1 — 16-Jul-2026 — MAT000E__ Exempt Materials Always Export (Whitecard)

### Overview
Whitecard / Blockout Cloud Sync still uses `:no_materials` for sanitised
massing GLBs, but `MAT000E__` ("Material Exempt") materials now always write
into the GLB — colour + embedded texture — matching TrueVision's exempt
exception. One-off throwaway detail textures (e.g. `MAT000E__CorbelLeafFake`)
survive Whitecard sync without converting the project to MaxModel. MaxModel
`:indexed_only` behaviour is unchanged (already included exempt materials).

### Changed
- **TrueVision GLB Builder `MaterialHandling` v3.1.0** — `:no_materials` no
  longer early-returns before the exempt gate; `PrepareMaterialsForExport`
  and `ResolveMaterialIndexForGroup` register `MAT000E__` materials in every
  mode. Cloud Sync Whitecard exports inherit this automatically.
- **`Na__GlbExportBridge`** — report message notes `MAT000E__ exempt` for
  both Whitecard and MaxModel syncs; docs updated.

### Files Changed
- `Na__TrueVision__GlbBuilderUtility__Modules__/Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__.rb`
- `Na__TrueVision__GlbBuilderUtility__Modules__/Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__.rb`
- `Na__TrueVision__GlbBuilderUtility__Modules__/Na__TrueVision__GlbBuilder__Doc__ReadMe__.md`
- `04__Plugin__SyncFeatures/03__GlbExportBridge/Na__ValeVisionCloudSync__GlbExportBridge__.rb`

# =============================================================================


## Version 0.4.0 — 15-Jul-2026 — Per-Scene SketchUp Section Plane Capture

### Overview
Camera capture now also records each IMG## scene's active SketchUp section
plane(s), so ValeVision3D can auto-create matching live cross sections per
scene ("porting" the SketchUp section, including cap fills, clean profile
lines and image-export support on the web side). Uses the SketchUp 2026+
`Sketchup::Page#active_section_planes` API — no page switching required.
Pages that don't store the section-plane property (Scenes dialog "Active
Section Planes" unticked) emit `nil`, which tells ValeVision to leave its
own per-scene section bindings untouched for that scene; scenes WITH a
SketchUp section always win over ValeVision-authored bindings.

### Added
- **`Na__ValeVisionCloudSync__SectionPlaneCapture__.rb`** (new,
  `04__Plugin__SyncFeatures/02__CameraDataCapture`) — converts
  `SectionPlane#get_plane` `[a,b,c,d]` (inches) to a unit normal (Z-up) +
  `position_mm` along the normal. SketchUp keeps geometry in FRONT of the
  plane (normal side) — the same convention as three.js clipping, so the
  web app consumes the values directly after its standard
  `Three = (x, z, -y)` axis swap. Model-level planes only; planes nested in
  groups/components are skipped with a console note (transform chain out of
  scope for v1). Degrades to `nil` on pre-2026 SketchUp or any error.
- **`section_planes` key** on every scene entry inside
  `ValeVison3D__SketchUpCameraData` (array of plane hashes, or `nil` when
  the scene has no section state). Flows through Full Sync and Update
  Camera Data unchanged — no orchestrator or writer changes needed.

### Files Changed
- `04__Plugin__SyncFeatures/02__CameraDataCapture/Na__ValeVisionCloudSync__SectionPlaneCapture__.rb` (new)
- `04__Plugin__SyncFeatures/02__CameraDataCapture/Na__ValeVisionCloudSync__CameraDataCapture__.rb`
- `02__Plugin__CoreAppData/02__ModuleLoaders/Na__ValeVisionCloudSync__ModuleLoaders__Main__.rb`
- Companion web-side change: ValeVision3D v2.12.0 (SketchUp section import + per-scene apply).

# =============================================================================


## Version 0.3.0 — 09-Jul-2026 — MaxModel Projects Export SSOT Indexed Materials

### Overview
Projects whose local root folder ends in `__MaxModel` now sync with their SSOT indexed materials intact. The GLB export bridge detects the suffix and switches `TrueVision3D::GlbBuilderUtility` into `:indexed_only` material mode for the export (matching the old TrueVision Exporter's indexed option), so the exported GLBs keep their `MAT###__` material names and ValeVision3D MaxEngine can swap them from the DataLib materials index (`Na__DataLib__CoreIndex__Materials`). Whitecard/Blockout syncs are unchanged — and now deterministic: the bridge explicitly sets `:no_materials` for them, so a material mode left selected in the TrueVision Exporter UI can no longer leak into a sync. The builder's prior mode is restored after every export.

### Added
- **`na_max_model_project?`** in `Na__GlbExportBridge` — detects the `__MaxModel` suffix (case-insensitive) on the resolved project root.
- **`na_set_material_export_mode`** in `Na__GlbExportBridge` — sets the builder's material export mode via `Na__MaterialEngine__SetExportMode`, returning the prior mode for restore; no-op on builder versions without the material engine API.
- GLB report step message now states which material mode was used (`SSOT indexed materials (MaxModel)` vs `whitecard, no materials`).

### Notes
- No Ruby changes were needed anywhere else: `ProjectPathMapper` is suffix-agnostic and `ProjectDataWriter` already strips `__MaxModel`. The Python orchestrator already detects `__MaxModel` folders on first sync and writes `ProjectType: "MaxModel"` + `RenderEngine__Config: MaxEngine` into project.json, which drives the Whitecardopedia "Max Models" tab and ValeVision3D's automatic MaxEngine boot.
- The Vale Project Structure Builder (`Py_WinUtil__BuildValeProjectStructure__Main__.py` v1.5.0) gained a "MaxModel" project type in the same change, so `__MaxModel` folders can now be created from the dropdown instead of by hand-renaming.

### Files Changed
- `04__Plugin__SyncFeatures/03__GlbExportBridge/Na__ValeVisionCloudSync__GlbExportBridge__.rb`
- `Root_GeneralDeveloperTools/02_Python/10__Python__WinFileSystemTools/Py_WinUtil__BuildValeProjectStructure/Py_WinUtil__BuildValeProjectStructure__Main__.py` (companion change)

# =============================================================================


## Operational Note — 07-Jul-2026 — Whitecardopedia Web Editor Can Now Rename Live Projects

### No code changes in this plugin — documentation only
Whitecardopedia's Project Editor (the web-based tool, not this plugin) gained a "rename project folder" capability: editing Project Code/Name and saving can now move a project's entire live folder on Cloudflare R2 (e.g. `2026/63592__Bressard-Kayode` -> `2026/63592__Bressard-Kayode Scheme-01`), rewriting `valeVision_ModelUrls` and updating the master index/masterConfig so ValeVision3D keeps working with zero code changes on that side.

**This plugin is completely unaffected and unaware of that rename**, because it never reads the master index or R2 state — every sync (`Na__ValeVisionCloudSync__SyncOrchestrator` -> `AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py`) re-derives its target `folderId` purely from the **local SketchUp project folder's name on disk** (`{code}__{Name}__Whitecard` -> strips the type suffix -> `{code}__{Name}`).

**Practical implication for branching schemes (e.g. Scheme-01 / Scheme-02):**
- If you rename a project via the Whitecardopedia web editor and intend to **sync that same scheme again later**, you must also rename the **local** SketchUp project folder on disk to match (e.g. `63592__Bressard-Kayode__Whitecard` -> `63592__Bressard-Kayode Scheme-01__Whitecard`). Otherwise the next sync will recompute the OLD folder name and recreate/repopulate it on R2, orphaned from the renamed web copy.
- Creating a genuinely **new** scheme (e.g. `63592__Bressard-Kayode-Scheme-02__Whitecard`) as a separate local folder and syncing it is entirely safe and untouched by any web-side rename — this remains the supported way to branch a project, exactly as before.
- There is still no rename/duplicate feature in this plugin itself — every sync's target folder is 100% derived from the current local folder name, with no override besides the existing Settings -> "Project path override" (which still must point at a folder physically named the way you want it to sync as).

# =============================================================================


## Version 0.2.3 — 01-Jul-2026 — Per-Scene Tag/Layer Visibility Capture

### Overview
Each captured IMG## scene now also records which of the toggle-relevant SketchUp tags (Existing Building, Design Proposal, Site Boundaries, Landscape, etc.) are visible on that scene, so ValeVision3D can automatically show/hide the matching "Model Parts List" categories when the camera tour switches scenes — e.g. hiding Site Boundaries for a shot framed inside a hedge.

### Added
- **`Na__TagVisibilityCapture`** (`04__Plugin__SyncFeatures/02__CameraDataCapture/Na__ValeVisionCloudSync__TagVisibilityCapture__.rb`) — reads the shared `Na__DataLib__CoreIndex__Tags__.json` SSOT (same file `TrueVision3D::GlbBuilderUtility` uses), flattens it into `{ Tag__SketchUpName => Glb__ExportFileNameStem }`, and for a given scene computes true per-tag visibility without switching pages, using the confirmed `page.layers` override-XOR algorithm (see module header for the SketchUp API source citations). Groups results into `{ "ValeVision__<Category>" => true/false }`, matching ValeVision3D's model-toggle category keys 1:1.
- **`Na__PathResolver.Na__ValeVisionCloudSync__TagsDataLibFilePath`** — resolves the shared DataLib Tags JSON path.
- `na_extract_scene_camera` in `Na__CameraDataCapture` now adds a `model_layer_visibility` key alongside `camera` for every captured scene.

### Notes
- No changes were needed to `Na__ProjectDataWriter`, `Na__SyncOrchestrator`, or the Python sync orchestrator — `model_layer_visibility` rides inside the existing `ValeVison3D__SketchUpCameraData` object, which both "Full Sync" and "Update Camera Data" already merge into local `project.json` and R2 wholesale.
- Fails soft: a missing/invalid Tags DataLib JSON yields `{}` per scene rather than aborting camera capture.

### Files Changed
- `04__Plugin__SyncFeatures/02__CameraDataCapture/Na__ValeVisionCloudSync__TagVisibilityCapture__.rb` (new)
- `04__Plugin__SyncFeatures/02__CameraDataCapture/Na__ValeVisionCloudSync__CameraDataCapture__.rb`
- `03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__PathResolver__.rb`
- `02__Plugin__CoreAppData/02__ModuleLoaders/Na__ValeVisionCloudSync__ModuleLoaders__Main__.rb`

# =============================================================================


## Version 0.2.2 — 26-Jun-2026 — Auto-Init ProjectData Directory

### Fixed
- Camera capture "ProjectData JSON not found" on projects that pre-date the plugin:
  `FindProjectDataFile` now calls `FileUtils.mkdir_p` to create the `00__ProjectData/`
  directory when absent and returns a derived filename (`{ProjectFolder}__ProjectData__.json`)
  when no `*__ProjectData__.json` exists yet. The file is created on first write by the
  existing `WriteProjectDataArray` logic. Projects that already have an initialised
  `00__ProjectData/` folder are completely unaffected.

### Files Changed
- `04__Plugin__SyncFeatures/06__ProjectDataWriter/Na__ValeVisionCloudSync__ProjectDataWriter__.rb`

# =============================================================================


## Version 0.2.1 — 25-Jun-2026 — First-Sync Scaffold + Context-Aware Update Buttons

### Overview
A brand-new Vale project can now be synced to Whitecardopedia and R2 on the first button press without a pre-existing web folder or `project.json`. The dialog greys out the three Update action cards until a full sync has succeeded at least once for the active model, giving immediate feedback that the project has (or has not) been pushed live.

### Added
- **`Na__ValeVisionCloudSync__ReadFirstSyncComplete(model)`** / **`Na__ValeVisionCloudSync__MarkFirstSyncComplete(model)`** in ProjectPathMapper — persists `first_sync_complete` in the model attribute dictionary (`ValeVision__CloudExport` dict).
- **`first_sync_complete` in path display payload** — DialogManager pushes the flag to the HtmlDialog on open and after every successful sync.
- **Update card lock state (UiBridge)** — `data-na-requires-sync="true"` on the three Update cards; `na__vvcs__applyButtonLockState()` disables them when `firstSyncComplete` is false; `Na__Vvcs__RunSyncAction` blocks Update actions until unlocked.
- **Python scaffold gate** — orchestrator `na_ensure_wcp_project_scaffold()` (see Whitecardopedia v0.6.2) creates folder + `project.json` + masterConfig entry before image/R2 stages when missing.

### Changed
- Successful full sync marks `first_sync_complete` and re-pushes path status so Update cards unlock immediately.
- Disabled Update cards use matching hover/active suppression in Styles CSS.

### Files Changed
- `04__Plugin__SyncFeatures/05__ProjectPathMapper/Na__ValeVisionCloudSync__ProjectPathMapper__.rb`
- `03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__DialogManager__.rb`
- `05__Plugin__UserInterface/Na__ValeVisionCloudSync__UiLayout__.html`
- `05__Plugin__UserInterface/Na__ValeVisionCloudSync__UiBridge__.js`
- `05__Plugin__UserInterface/Na__ValeVisionCloudSync__Styles__.css`
- `Whitecardopedia/Tools__DevUtils/AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py`

# =============================================================================


## Version 0.2.0 — 25-Jun-2026 — End-to-End Cloud Sync Production Release

### Overview
Milestone release completing the SketchUp → local Vale project → Whitecardopedia working copy → Cloudflare R2 → ValeVision3D pipeline. All sync features listed as pending in v0.1.0 are now implemented and stable. Python orchestration, R2 GLB upload, and robust reporting round out the production workflow. See also Whitecardopedia v0.5.0 and ValeVision3D v2.8.0 for the web-side consumers of this pipeline.

### Added
- **`04__Plugin__SyncFeatures/05__ProjectPathMapper`** — derives project root from active model path (`C:\01__ValeProjects\...`); forward-slash path normalisation for reliable `Dir.glob` on Windows.
- **`04__Plugin__SyncFeatures/01__SceneImageExporter`** — exports IMG## scene images via `view.write_image` into the edition content folder.
- **`04__Plugin__SyncFeatures/02__CameraDataCapture`** — captures `page.description` as `scene_description` and SketchUp camera data (mm, Z-up) into `ValeVison3D__SketchUpCameraData` via ProjectDataWriter merge.
- **`04__Plugin__SyncFeatures/03__GlbExportBridge`** + **`04__GlbArchiver`** — GLB export bridge to GlbBuilderUtility (`quiet: true` suppresses Explorer reveal and modal dialog); archives stale GLBs before refresh.
- **`04__Plugin__SyncFeatures/06__ProjectDataWriter`** — key-scoped merge into local `*__ProjectData__.json` array (no full overwrite).
- **`04__Plugin__SyncFeatures/07__SyncOrchestrator`** — shells out to `AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py` with `--report-file` JSON channel.
- **Python orchestrator integration** — clone images, generate 524p thumbnails, upload R2, rebuild `project.json.images[]`, merge camera key, upsert master index (Whitecardopedia `Tools__DevUtils/`).
- **R2 GLB upload** — Python uploads top-level `*.glb` files and purges stale R2 GLBs so CDN mirrors local export set.
- **Report file channel** — `--report-file` writes JSON report to disk (stdout unreliable in SketchUp GUI host); orchestrator reads file first, stdout second.
- **Full run logs** — `99__Logs/Na__ValeVisionCloudSync__PythonRun__<timestamp>.log` and structured JSON reports per sync.

### Fixed
- **Thumbnail generation** — corrected Pillow CLI arguments for multi-image 524p thumbnail batch.
- **GLB export UX** — `quiet: true` on GlbBuilderUtility bridge prevents Explorer auto-open and blocking message boxes mid-sync (TrueVision `GlbBuilder__Main/CoreExport` updated).
- **Unicode console output** — Python orchestrator forces UTF-8 streams (`na_force_utf8_streams`) to avoid Windows cp1252 encode errors on special characters.

### Changed
- Sync workflow now produces a per-step trail in the dialog report panel (OK/ERR per step with descriptive messages).
- `update_glb_models` scope chains local GLB export + Python R2 GLB upload in one action.

### Files Changed
- `04__Plugin__SyncFeatures/01__SceneImageExporter/Na__ValeVisionCloudSync__SceneImageExporter__.rb`
- `04__Plugin__SyncFeatures/02__CameraDataCapture/Na__ValeVisionCloudSync__CameraDataCapture__.rb`
- `04__Plugin__SyncFeatures/03__GlbExportBridge/Na__ValeVisionCloudSync__GlbExportBridge__.rb`
- `04__Plugin__SyncFeatures/04__GlbArchiver/Na__ValeVisionCloudSync__GlbArchiver__.rb`
- `04__Plugin__SyncFeatures/05__ProjectPathMapper/Na__ValeVisionCloudSync__ProjectPathMapper__.rb`
- `04__Plugin__SyncFeatures/06__ProjectDataWriter/Na__ValeVisionCloudSync__ProjectDataWriter__.rb`
- `04__Plugin__SyncFeatures/07__SyncOrchestrator/Na__ValeVisionCloudSync__SyncOrchestrator__.rb`
- `Na__TrueVision__GlbBuilderUtility__Modules__/Na__TrueVision__GlbBuilder__Main__.rb` (quiet API)
- `Na__TrueVision__GlbBuilderUtility__Modules__/Na__TrueVision__GlbBuilder__CoreExport__.rb` (quiet API)
- `Whitecardopedia/Tools__DevUtils/AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py`

# =============================================================================


## Version 0.1.6 — 25-Jun-2026

### Changed
- Dialog brand header now uses the Vale Garden Houses logo (copied from ValeDesignSuite into `06__Assets/Na__ValeVisionCloudSync__BrandLogo__Horizontal__.png`) instead of the Noble Architecture logo.
- Top bar styling aligned with Noble 3D Modelling Tools: white background, 36px logo, 18px/600 title — removed navy background, logo invert filter, and "SketchUp → ValeVision 3D" subtitle.

# =============================================================================


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

# =============================================================================
