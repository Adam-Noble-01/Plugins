# HANDOFF: ValeVision Cloud Sync -> Projects Master Library + Server Push

> **STATUS: IMPLEMENTED 06-Oct-2026 in plugin v0.5.0. Do not re-implement from this file.**
> The work was done by the session that wrote it, at Adam's request. It changes one thing
> from the plan below: the plugin shells out to the Server Manager's sync **engine**
> (`collect` / `push projects --scope ValeProjects__<yyyy>/<id>`, engine 0.6.0) instead of
> calling the Manager app's HTTP API. The Manager app need not be running; the engine
> shares its lock and guards. See `Na__ValeVisionCloudSync__DEVLOG__.md` (Version 0.5.0)
> for what was built and tested. This file is kept as the background and the rules.
>
> **Superseded on 07-Oct-2026 (plugin 0.5.1, Server Manager 0.6.2):** GLBs are no longer
> additive on the server. Every GLB sync zips the previous set into the GLB bucket's
> `00__Archive` and prunes the server's GLB bucket to the PC's (`--prune`). The local archive
> folder is now `ValeVision__GlbFileSync/00__Archive`. Sections 3a and 3d are stale on both points.

**Written:** 06-Oct-2026, by the session that moved ValeVision 3D onto Vale's own server.
**For:** the agent who updates this SketchUp plugin (`Na__ValeVisionCloudSync__Modules__`).
**Owner:** Adam Noble. Ask him before anything touches the live server.

Read this whole file before changing code. Then load the `vgh-app-server` skill
(`D:\08__Cloud__Repo__AgentSkills__Private\61-vgh-app-server\vgh-app-server\SKILL.md`). It holds the server
rules, and they are strict (fail2ban has locked Adam out before).

---

## 1. The Job in One Paragraph

Today the plugin exports images, camera data and GLBs into the SketchUp project folder. It then shells out to a
Python script in the retired Gallery folder, which uploads everything to **Cloudflare R2** and copies it into the
legacy web folder. **R2, the Cloudflare Workers and GitHub Pages are gone.** Every Vale web app now runs on one
server (`app.valegardenhouses.com`, an OVH VPS: nginx + Flask). That server is an exact mirror of a folder on
Adam's PC. The plugin must now:

1. Export to the SketchUp project folder (unchanged).
2. **Publish** into the PC's **Projects Master Library**, the new local location: the right files in the right
   `Content__*` buckets and the record (`ProjectData__<id>__.json`) updated.
3. **Push** that project to the server through the **Vale Virtual Server Manager's local API**
   (`http://127.0.0.1:8020`). The Manager is the only sanctioned way files reach the server.

No R2, no boto3, no CDN URLs, no master index, no build manifest.

---

## 2. Why: One Server Replaces R2, Workers and GitHub Pages

| Removed | Replaced by |
|---|---|
| GitHub Pages hosting the apps | nginx on the VPS serves the apps from `/srv/vale` |
| Cloudflare R2 (`cdn.noble-architecture.com/VaApps/...`, bucket `noble-architecture-cdn`) holding models, images and `project.json` | The **Projects Master Library** at `/srv/vale/Vale__Projects__MasterLibrary`, an exact copy of the PC's |
| Workers (the editor API, email) | One Flask API per app, behind nginx, on the same origin |
| The R2 master index, the build-version manifest, the master config on R2 | Nothing. The apps list the library through their APIs; nginx sends `no-cache` with ETags, so a pushed file is fresh on the next load |
| Uploading from the PC with R2 keys | **Push** from the PC with the Vale Virtual Server Manager (SSH, one connection, staged, backed up, undoable) |

The principle: **the PC is the source of heavy content** (models, renders). It lands in the PC mirror, then goes up
by Push. User data made on the server (drawings, comments) comes down by Collect. The project record syncs both
ways, newer wins.

```
SketchUp model
   |  (1) export  - unchanged
   v
C:\01__ValeProjects\ValeProjects__<yyyy>\<code>__<Name>__<Type>\        <- the SketchUp working folder (unchanged)
   |  (2) publish - NEW: copy + rename + thumbnails + record merge
   v
D:\10_CoreLib__ValeCodebase\WebApps\Vale__VirtualServer\Vale__Projects__MasterLibrary\ValeProjects__<yyyy>\<id>\
   |  (3) push    - NEW: Server Manager local API, mapping "projects"
   v
valevps:/srv/vale/Vale__Projects__MasterLibrary/...   ->  https://app.valegardenhouses.com/valevision/?project=<id>
                                                          https://app.valegardenhouses.com/project-gallery/?id=<id>
```

---

## 3. Old File Structure vs New

### 3a. What does NOT change

The SketchUp working folder and everything the plugin writes into it stay exactly as they are:

```
C:\01__ValeProjects\ValeProjects__2026\64135__Washington__Whitecard\
├── 00__ProjectData\64135__Washington__ProjectData__.json      local record: a JSON ARRAY of keyed objects
│                                                              (camera data lives here first; ProjectDataWriter)
├── 02__SketchUp\01__MainModel\<model>.skp
└── 10__ContentDelivered__Local\
    ├── VisDpt__Whitecard__FirstEdition__<date>\               rendered IMG## PNGs (SceneImageExporter)
    ├── VisDpt__Whitecard__SecondEdition__<date>\              (latest edition = newest mtime)
    └── ValeVision__GlbFileSync\                               fresh GLBs (GlbExportBridge -> GLB Builder)
        └── 00__ArchivedModels\                                zipped previous GLBs (GlbArchiver) - stay local
```

### 3b. What is retired (never write to these again)

| Old location | Status |
|---|---|
| `D:\10_CoreLib__ValeCodebase\WebApps\Whitecardopedia\Projects\<yyyy>\<folder>\project.json` + images | **Retired.** The legacy Gallery folder is frozen until it is archived. The Gallery app is now "ValeVision Gallery"; never use the old name in anything new |
| `...\Whitecardopedia\Tools__DevUtils\AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py` (and `AutomationUtil__R2Common__Lib__.py`, `AutomationUtil__FetchLocalProjects__...`, `API__Cloudflare\Token__CloudflareAPI.env`) | **Retired.** Port the logic you need (section 7); do not call these scripts or read their R2 credentials |
| R2 keys `VaApps/Projects/<yyyy>/<folder>/...` | **Retired.** Never upload |
| R2 `VaApps/Index/Na__MasterIndex__ProjectLocations__.json`, `Na__BuildVersion__Manifest__.json`, the master config | **Retired, with no replacement** |

### 3c. The new home: the Projects Master Library (one folder per project, shared by every app)

```
D:\10_CoreLib__ValeCodebase\WebApps\Vale__VirtualServer\Vale__Projects__MasterLibrary\
└── ValeProjects__2026\
    └── 64135__Washington\                                         <- THE PROJECT ID ("library id") = this folder name
        ├── ProjectData__64135__Washington__.json                  the ONE project record (a JSON OBJECT), all apps
        ├── ProjectData__Revisions\                                kept by the server APIs on every write (user data)
        ├── ValeVision3D\
        │   ├── Content__3dModel__GlbFiles\                        GLBs                      <- YOU WRITE
        │   ├── Content__3dModel__AppGenerated\                    (app-made, not yours)
        │   ├── Content__AnimationScenes__Thumbnails\              524p WebP per IMG##       <- YOU WRITE
        │   └── UserData__*\                                       drawings, configs: NEVER touch (server-made)
        ├── ValeVisionGallery\
        │   ├── Content__GalleryImages__FullQuality__VariantImages\  full IMG## PNGs         <- YOU WRITE
        │   ├── Content__GalleryImages__524p__VariantImages\         524p JPG                <- YOU WRITE
        │   └── Content__GalleryImages__Thumbnail__VariantImages\    524p WebP               <- YOU WRITE
        └── LanternDesigner\
```

### 3d. Artefact by artefact

| Artefact | Old: where it went | New: where it goes |
|---|---|---|
| Project record | `project.json` on R2 **and** in `Whitecardopedia\Projects\...` (both merged by Python) | `<library>\ValeProjects__<yyyy>\<id>\ProjectData__<id>__.json` (merge only your keys, section 5) |
| Full renders `IMG##__...__WhitecardImage__<date>.png` (latest per IMG## slot, latest edition) | Copied to the legacy folder, uploaded to R2 | `ValeVisionGallery\Content__GalleryImages__FullQuality__VariantImages\` |
| 524p JPG `<stem>__Thumbnail__524p__.jpg` (long edge 524 px, JPEG q88, progressive) | Generated in the legacy folder, uploaded | `ValeVisionGallery\Content__GalleryImages__524p__VariantImages\` |
| 524p WebP `<stem>__Thumbnail__524p__.webp` (long edge 524 px, WebP q82, method 6) | Same | **Both** `ValeVisionGallery\Content__GalleryImages__Thumbnail__VariantImages\` **and** `ValeVision3D\Content__AnimationScenes__Thumbnails\` |
| GLBs (top level of `ValeVision__GlbFileSync`, `__NaModel__` renamed `__ValeVision__`) | Uploaded to R2; stale R2 GLBs deleted | `ValeVision3D\Content__3dModel__GlbFiles\` (same rename) |
| `valeVision_ModelUrls` | Full CDN URLs `https://cdn.noble-architecture.com/VaApps/Projects/<yyyy>/<folder>/<file>.glb` | **Bare file names**, sorted: `["Washington__01__OrbitHelperCube__MeshModel__.glb", ...]`. ValeVision 3D resolves them inside the project's GLB bucket |
| Camera data `ValeVison3D__SketchUpCameraData` (one "i": the web app's key) | Merged into local and R2 `project.json` | Merged into the library record (copied from the local ProjectData array) |
| Image lists `images`, `allImages`, `displayImages`, `thumbnailImage` | Rebuilt in `project.json` | Rebuilt in the library record (bare file names) |
| Scene thumbnails inside `PresentationMode__SavedCameraScenes` | Re-pointed at the current edition | Same re-point rule (section 5), in the library record |
| Master index, build manifest, master config | Rewritten and uploaded | **Delete the step** |
| Stale images and GLBs | Purged locally and deleted on R2 | Purge in the **PC library folder** only. Push never deletes content on the server (by design), so old files stay there, unlisted and harmless |

---

## 4. Project Identity: Which Library Folder Is This Model?

- **The library id is the folder name**, e.g. `64135__Washington`. It is unique across years. Every app links
  with it: `/valevision/?project=64135__Washington`, `/project-gallery/?id=64135__Washington`.
- **Default mapping** from the SketchUp project root `C:\01__ValeProjects\ValeProjects__<yyyy>\<folder>`:
  strip a trailing `__Whitecard`, `__Blockout` or `__MaxModel`, and turn spaces into `__`. The year comes from
  the `ValeProjects__<yyyy>` parent. This is the legacy `generate_destination_folder_name` rule
  (`...Tools__DevUtils\AutomationUtil__FetchLocalProjects__BuildWhitecardopediaProject__Main__.py:405`).
- **It is not always right.** The 06-Oct migration kept legacy names: `59494__Weeks` once called itself
  `WK-3007__Weeks`, and both `64135__Washington` and `64135__Holt` exist. So:
  - look the derived id up in the PC library, across every `ValeProjects__<yyyy>`;
  - show the result in the Settings tab;
  - let Adam override it, persisted in the model dictionary beside `project_path_override` (for example a
    `library_project_id` key in the `ValeVision__CloudExport` dictionary).
- **A new project** (no library folder yet):
  - create `ValeProjects__<yyyy>\<id>\` with the empty buckets above (the reference layout is
    `ValeProjects__2026\12345__ExampleProject__Schema`, but do not copy its JSON: it is wrongly named);
  - write a fresh `ProjectData__<id>__.json` with at least `projectCode`, `projectName`, `displayName`,
    `enabled: true`, `ProjectType` ("Whitecard" / "Blockout" / "MaxModel"), `productionData` and `scheduleData`
    in the shape the existing records use, plus your own keys;
  - copy the shape from a real record such as `64135__Washington`;
  - **ask Adam to confirm the id before the first push**: ids are permanent once anything links to them.

---

## 5. Rules for Writing the Project Record (Read Twice)

The library record is **shared by every app** and syncs **both ways, newest file wins**. Edits made on the server,
by the ValeVision 3D Dev menus or the Gallery editor, are newer than the PC copy until a Collect brings them down.

1. **Collect before you write.**
   - Before touching `ProjectData__<id>__.json`, bring the server's copy down through the Manager:
     `compare` then `collect` for mapping `projects` (section 6).
   - If you write first, your PC copy becomes the newest and the next push overwrites a colleague's edits on the
     server. The server keeps a backup, but nobody notices.
   - If the Manager is not running, write nothing to the record and say so in the dialog. Files in the content
     buckets are safe to write without it.
2. **Merge only the keys this plugin owns. Leave every other key byte-for-byte as it is.**

   | Owned by the sync (yours) | Never touch |
   |---|---|
   | `ValeVison3D__SketchUpCameraData` | Everything else, including ValeVision 3D's editor-owned keys: `PresentationMode__SavedCameraScenes` (except the thumbnail re-point below), `LayoutEditor__DrawingsData`, `LayoutEditor__DrawingRegister`, `CrossSection__SceneData`, `CrossSection__Config` and the rest of the list in `Vale__ValeVision3D\02__Src__AppModules\02__AppData\Na__AppConfig__Main.json` -> `ProjectData__EditorOwnedKeys` |
   | `valeVision_ModelUrls` (bare names) | The Gallery's keys: `productionData`, `scheduleData`, `enabled`, `displayName`, `projectNameAlias`, `artPairsMap`, `variantData` |
   | `images`, `allImages`, `displayImages`, `thumbnailImage` | `_rev`: keep whatever the file holds (the server APIs bump it) |
   | `projectCode`, `projectName`: on creation only | `FogPlane__Config`, `Camera__DefaultPosition`, `OrbitHelperCube__Position`, `Navmode__*`, `RenderEngine__Config`, `VideoStudio__Config`: Dev-menu settings saved from the web |

   - **Scene thumbnail re-point** (port it exactly from the legacy `na_repoint_presentation_thumbnails`, Python
     orchestrator around line 384):
     - in `PresentationMode__SavedCameraScenes.PresentationMode__SavedCameraScenes__Scenes[*]`, change only
       `PresentationMode__Scene__ThumbnailUrl`;
     - change it only when its value starts with an `IMG##` slot token;
     - point it at `<current source PNG stem>__Thumbnail__524p__.webp` for the same slot;
     - never overwrite a hand-authored path (e.g. `PresentationMode/Thumbnails/...`).
   - **Image lists** (legacy `na_update_project_json_images` / `na_rebuild_derived_image_lists`):
     - `images` and `allImages` = the current IMG## PNG names, sorted;
     - `displayImages` = the same without `IMG##_ART##` variants;
     - `thumbnailImage` = the 524p WebP name of the first image.
3. **Format:**
   - write with `json.dumps(obj, indent=4, ensure_ascii=False)`, keeping the file's own trailing-newline state;
   - write through a temp file plus `os.replace`;
   - keep key order: load into a dict and write it back; never sort keys.
4. **Do not confuse the two records.** The local `00__ProjectData\*__ProjectData__.json` is an **array** of keyed
   objects (`Na__ProjectDataWriter`); the library record is a single **object**. Copy the camera object out of
   the array into the record's `ValeVison3D__SketchUpCameraData` key.
5. **Never write into `UserData__*` folders or `ProjectData__Revisions`.** Those belong to the server.

---

## 6. Pushing: the Vale Virtual Server Manager's Local API

The Manager is Adam's app (`D:\10_CoreLib__ValeCodebase\WebApps\Vale__VirtualServerManager`). Start it from the
Start menu ("Vale Virtual Server") or with `Start__VirtualServerManager__Localhost__8020__.bat`. Its local server
holds the machine-wide SSH lock, the key-agent preflight, the cooldown and the session log.

**Never SSH, scp or rsync yourself.** fail2ban bans the PC after 5 failed logins in 10 minutes.

| Call | Body | Answer |
|---|---|---|
| `GET  http://127.0.0.1:8020/api/state` | | Is the Manager up? Busy? (use as a health check) |
| `POST http://127.0.0.1:8020/api/op/compare` | `{"ids": ["projects"]}` | `{ok, plans: {projects: {...counts and file lists...}}}`. One SSH session |
| `POST http://127.0.0.1:8020/api/op/collect` | `{"ids": ["projects"]}` | Brings server-newer project data and user data down. Needs a fresh compare first. One session |
| `POST http://127.0.0.1:8020/api/op/push` | `{"ids": ["projects"]}` | Pushes PC-newer content and records. Needs a fresh compare first. One session |
| any `/api/op/*` | | `{"ok": false, "error": "busy: ..."}` while another job runs: wait and retry, never hammer it |

- **Read before you build on it.** Exact behaviour and plan shapes: `VirtualServerManager__LocalServer__.py`
  (`Na__Server__Operate`, about line 373; `Na__Server__FreshPlans`) and `VirtualServerManager__SyncEngine__.py`
  (`Na__Engine__Compare`, `Na__Engine__Push`, `Na__Engine__Collect`, `Na__Parity__Verdict`). The lanes:
  - `Content__*` = push, additive, newer wins;
  - `ProjectData__*.json` = both ways, newer wins;
  - `UserData__*` = collect only.

  A content file that is **newer on the server** is reported as a conflict and skipped unless forced. Never pass
  `force_content`.
- **Sequence for a sync:**
  1. compare + collect `projects` (protects the record);
  2. publish into the PC library (section 3d, section 5);
  3. compare `projects`, and show the plan in the dialog: "n files to push";
  4. push on Adam's click.

  Clicking Sync in SketchUp is Adam asking for it, but show the counts, and stop if the plan holds anything
  unexpected (deletes, conflicts, other projects' files).
- **Scope limit today:** compare and push work on the **whole `projects` mapping**, so a push also sends any other
  project's pending PC changes. Two options:
  - propose to Adam a small engine change: an optional `paths` filter (e.g.
    `["ValeProjects__2026/64135__Washington"]`) on compare/push/collect, threaded through `Na__Server__Operate`;
  - or show the full plan and let him decide.

  **The Manager is Adam's code: ask before changing it.** Follow its rules: `Prefix__Kind__Name__` style, region
  headers, a DEVLOG entry, bump `NA__SERVER__VERSION` and `Vsm.PageVersion` together.
- **Manager not running:** do steps 1-2 that need no server (write content buckets, and the record only if a
  collect has happened), then tell Adam "Published locally; start Vale Virtual Server to push".

**Why not upload through a web API?** Cloudflare caps a request at 100 MB, and server-side uploads would make the
server copy newer than the PC's, which the content lane treats as a conflict. Heavy content goes PC -> library ->
Push. The Manager's local API *is* the API for this job.

---

## 7. What to Change in This Plugin

| File | Change |
|---|---|
| `02__Plugin__CoreAppData\Na__ValeVisionCloudSync__CoreAppData__AppConfig__.json` | Replace the `python` block's Gallery paths and delete the `cdn` block. Add a `library` block: `mirror_root` (`D:/10_CoreLib__ValeCodebase/WebApps/Vale__VirtualServer`), `library_dir` (`Vale__Projects__MasterLibrary`), `manager_api` (`http://127.0.0.1:8020`), the bucket names from section 3c, the thumbnail spec, `push_after_publish` (true/false). Make `mirror_root` overridable so tests can point at a copy |
| `04__Plugin__SyncFeatures\07__SyncOrchestrator\...SyncOrchestrator__.rb` | Keep the four buttons. Replace `na_run_python_orchestrator` (the R2 script) with **Publish** (section 3d, section 5) then **Push** (section 6). New step labels: "Publish to Project Library", "Push to app.valegardenhouses.com". Keep the robust Python launching (interpreter discovery, sanitized env, report file) if you keep a Python helper |
| New: `04__Plugin__SyncFeatures\08__LibraryPublisher\` | The publish logic. Suggested: a small Python helper beside the plugin (Pillow is needed for WebP; SketchUp's Ruby cannot write WebP), called through the existing shell-out with `--library-id --project-root --scope all/images/glb/cameras --report-file`. It also calls the Manager API (`urllib`). Port only what you need from the legacy script and the 524p thumbnail generator (`...Tools__DevUtils\AutomationUtil__GenerateGalleryThumbnails__524p__Main__.py`): clone latest-edition images (dedupe by slot, newest mtime), thumbnails, GLB copy (rename `__NaModel__` -> `__ValeVision__`), record merge |
| `04__Plugin__SyncFeatures\05__ProjectPathMapper\...ProjectPathMapper__.rb` | Add library-id resolution and override (section 4), and expose it to the dialog |
| `03__Plugin__CoreAppLogic\...DialogManager__.rb`, `05__Plugin__UserInterface\*` | Settings tab: the library id (editable), the library folder path, the Manager status (`GET /api/state`). Report panel: the push plan counts. Replace every "R2", "Cloudflare", "CDN" and the retired Gallery name in the UI and messages with "Project Library" / "server" / "ValeVision Gallery" |
| `...SceneImageExporter`, `...CameraDataCapture` (+ section planes, tag visibility), `...GlbExportBridge`, `...GlbArchiver`, `...ProjectDataWriter` | No change: they write the SketchUp working folder, which stays as it is |
| `Na__ValeVisionCloudSync__DEVLOG__.md` | A version entry for the change |

**The four scopes after the change:**

| Button | Steps |
|---|---|
| Sync Project | export images -> capture cameras -> export GLBs -> collect -> publish all -> compare -> push |
| Update Images | export images -> collect -> publish images (buckets + image lists + thumbnail re-point) -> compare -> push |
| Update GLB Models | export GLBs -> collect -> publish GLBs (bucket + `valeVision_ModelUrls`) -> compare -> push |
| Update Camera Data | capture cameras -> collect -> publish camera key -> compare -> push |

**Delete:** boto3 and R2 credentials, R2 uploads and purges, the master index, the build manifest, the master
config upload, every `Whitecardopedia\Projects` write, and the legacy scaffold step ("Build New ... Project",
"Register Project In Master Config"; the library folder **is** the registration).

---

## 8. Testing (Nothing Touches the Live Server Until Adam Says So)

1. **Dry run first:** a `--dry-run` that lists every copy, rename, thumbnail and record key it would change.
2. **Against a copy:** point `mirror_root` at a scratch copy of `Vale__VirtualServer` (copy only one or two
   projects plus `Vale__ValeVision3D`, `Vale__ValeVisionGallery`, `AppAssets__CommonApplicationAssets`,
   `Server__Api`). Then:
   - run `python Server__DeveloperTools\ValeDev__LocalServer__.py` **from that copy**; it serves the mirror the
     way nginx does and mounts every app API;
   - open `http://127.0.0.1:8030/valevision/?project=<id>` and `http://127.0.0.1:8030/project-gallery/?id=<id>`;
   - models, scene thumbnails and gallery cards must all show.
3. **Round trip:** sync a test model twice, the second time with one GLB and one image changed. The record must
   name only the new files, every other key must be byte-identical, and the old files must be purged from the PC
   library folder.
4. **Push:** only with Adam watching. Run `compare` first; check that the plan holds just this project's files;
   then push. Verify over HTTPS without SSH: `python "<skill>\scripts\vps.py" web /Vale__Projects__MasterLibrary/...`.

**Note (06-Oct-2026):** ValeVision 3D's API (`/valevision/api/`) is written and on the server but **not enabled
yet** (go-live waits on Adam). Pushed content is served by nginx regardless, but `/valevision/?project=` only
opens projects once that API is live. The Gallery API is live.

## 9. Done When

- A Sync from SketchUp ends with the project's files in the right library buckets on the PC and the server.
- The record lists bare model names and current images; scene thumbnails are re-pointed; nothing else in the
  record has changed.
- No code path reads R2 credentials, imports boto3, writes the legacy Gallery folder, or names a
  `cdn.noble-architecture.com` / `github.io` URL.
- The dialog shows Manager status, the push plan and the result, with clear words when the Manager is not running.
- The DEVLOG has the entry, and the `vgh-app-server` skill's migration file
  (`references/migration/MIGRATION__TEMPORARY__.md`) has a line saying the SketchUp sync writes the library.

## 10. References

| What | Where |
|---|---|
| Server rules, lanes, Manager commands | `D:\08__Cloud__Repo__AgentSkills__Private\61-vgh-app-server\vgh-app-server\SKILL.md`, `references\architecture.md` (sections 4-5), `references\operations.md` |
| Migration status, ValeVision 3D port, go-live | `...\references\migration\MIGRATION__TEMPORARY__.md` |
| Legacy folder -> library map for all 155 projects | `...\references\migration\Manifest__GalleryProjects__LegacyToLibrary__.json` |
| The scripts that did the 06-Oct moves (GLBs off R2, model names, stale keys) | `...\scripts\migration\migrate_vv3d.py`, `migrate_legacy.py` |
| Legacy R2 sync (logic to port, then forget) | `D:\10_CoreLib__ValeCodebase\WebApps\Whitecardopedia\Tools__DevUtils\AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py`, `...GenerateGalleryThumbnails__524p__Main__.py` |
| A complete library project | `...\Vale__Projects__MasterLibrary\ValeProjects__2026\64135__Washington\` |
| Editor-owned keys list | `...\Vale__ValeVision3D\02__Src__AppModules\02__AppData\Na__AppConfig__Main.json` -> `ProjectData__EditorOwnedKeys` |
| How the apps read the library | `Server__Api\Api__Shared\ValeShared__Library__.py`, `Server__Api\Api__ValeVision3D\ValeVision3D__Api__Projects__.py` |
| Server Manager | `D:\10_CoreLib__ValeCodebase\WebApps\Vale__VirtualServerManager\` (README, DEVLOG, `...LocalServer__.py`, `...SyncEngine__.py`) |
