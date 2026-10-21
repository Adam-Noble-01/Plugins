# Na__PointCloudViewer - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================

## Point Cloud Viewer - v0.9.1 - 21-Oct-2026 - LAZ Import: Lossless LAZ to LAS Converter

### Summary
Adam asked for a LAZ to LAS converter so Polycam LAZ files can be imported, with one rule above all:
nothing may affect accuracy or size. Import LAS / LAZ now accepts a .laz. It is decompressed into a
NEW LAS next to it (Save As, never overwriting), checked record by record, and that LAS's usual import
report and unit question follow. Everything after that (point cache, model link, Clean & Export)
works on the LAS exactly as before. No new dependency: the decoder is the LASzip 3.5.0 the engine
already vendored, unmodified. ARCHITECTURE section 24 is the full description.

### Built
- **Engine (ABI 6):** `LazConvert.hpp/.cpp` (the job: worker thread, progress, cancel, partial file,
  check, publish without replace) and `LazRecord.cpp` (turns each decoded point back into record bytes
  with LASzip's OWN raw item writers, `laswriteitemraw.hpp`). The header, VLRs, user data and LAS 1.4
  EVLRs are copied byte for byte; only the point format's compression bits, the LASzip VLR (so the VLR
  count and offset to points) and a 1.4 EVLR start change. Scale, offset, bounds, counts, GUID, dates
  and generating software are untouched, and the bounds are never recomputed: the points' real extent
  is measured and reported beside them. COPC index records are dropped with a note. Refused with a
  plain message: not LAZ, LASzip compatibility mode, internal waveform data, a header LASzip reads
  differently from its bytes, a damaged or cut-short LAZ.
- **Check before the file gets its name:** the new layout must read back with the LAZ's exact format,
  record length, count, scale, offset and bounds, and every other header byte equal; the record bytes
  on disk must hash to what was written; LASzip must read every record back to the same bytes again.
- **Ruby:** bridge ABI 6 (`Na__Native__Laz*`, its own live-job map destroyed first on a DLL swap);
  `40__System__LasImport/...LasImport__LazConvert__.rb` (Save As loop: `<name>.las`, else
  `<name>_FromLaz_01.las`; the job; the report rows); the Controller routes .laz (and a LAZ-compressed
  file named .las) to it and gained `Na__LasImport__Inspect(path, conversion)`.
- **UI:** the button reads Import LAS / LAZ, the picker shows both, and a converted file's report starts
  with Converted from, Conversion check and Header bounds rows. When a LAZ's header bounds disagree with
  its points, the status line is a warning that says the size shown comes from the header.

### 21-Oct-2026: what the online converter did to Adam's sample (reported to Adam)
- Adam's sample `21_10_2026.laz` (Polycam, LAS 1.2, format 2, 3,698,370 points) and the LAS an online
  converter made from it (`21_10_2026 (1).las`). The engine's conversion keeps every point; its decoded
  extent reproduces Polycam's own header bounds to the last bit.
- The online converter's LAS has the same count, scale and offset, but **not one of its 3,698,370 records
  is identical to the LAZ's**. Matched to the nearest point, its points sit 0.33e-3 file units away at
  the median, up to 1.48e-3 (0.3 mm and 1.5 mm if the file is in metres). That is about the scan's own
  point spacing (0.35e-3), so its points are not the LAZ's points moved slightly: they are effectively
  different points. Its header bounds were recomputed from those points (overall extent 2.0e-5 smaller in
  X). Do not use that file for survey work; convert the LAZ with the viewer instead.
- The sample's whole extent is 1.343 x 1.285 x 0.466 file units (1.3 m x 1.3 m x 46.6 cm if in metres),
  the same in the LAZ and both LAS files. Worth a look on import if the scan was a room.

### Tested
- Adam's LAZ through the DLL: 3,698,370 points in 1.2 s (1.0 s decode + 0.2 s check); the LAS is
  96,157,847 bytes = 227 + 3,698,370 x 26; header bytes changed from the LAZ: only 96, 97, 100, 104.
- `laz_convert.rb.test` (SketchUp's own Ruby 3.2 loading the real bridge, AsyncJobs, Controller and
  converter against the real DLL; UI and dialog doubles): 34 checks, all passing. Pick a .laz, Save As,
  convert, the import report with its rows; byte-identical to the DLL-only run; the destination rules
  and the refusal of an existing file; cancel mid-conversion (nothing left, not even a partial file); an
  uncompressed LAS and a cut-short LAZ refused with nothing written; a LAZ with deliberately wrong header
  bounds converted with the bounds kept byte for byte and the warning shown.
- All 11 point formats: a generator built against the vendored LASzip wrote the same 50,000 random
  points (every attribute, GPS time, RGB, NIR, waveform packets, 3 extra bytes on formats 1, 4, 7, 10,
  LAS 1.2 / 1.3 / 1.4, an extra VLR) as LAZ and as uncompressed LAS. Each converted LAZ's records are
  byte-identical to LASzip's own uncompressed LAS, header fields and VLRs equal; a compatibility-mode
  LAZ is refused. 40/40 Ruby files compile under SketchUp's Ruby 3.2.
- Not yet tried in SketchUp itself: the Save As dialog, the overlay during conversion, the report card,
  then importing the converted LAS.

### Checklist for Adam (in SketchUp)
1. Settings > Reload Plugin (the engine swaps to the ABI 6 build), then Import LAS / LAZ and pick the
   Polycam .laz. Save As offers `21_10_2026.las` in the same folder.
2. The overlay shows Decompressing, then Checking; Cancel deletes everything it wrote.
3. The import card opens with Converted from, Conversion check and Header bounds rows (Header bounds
   should say Match the points exactly). Check the Extent and the unit sizes, choose the units, Import.
4. Pick the converted `.las` again later: it imports directly, with no conversion.

## Point Cloud Viewer - v0.9.0 - 19-Oct-2026 - Scenes Tab: Point Cloud Scenes for TrueVision

### Summary
Adam asked for the viewer's settings to be bound to SketchUp scenes, recalled by pressing the
scene, and exported as images that TrueVision lays over its drawings for survey work. The Scenes
tab binds the clip box, point budget, point size, opacity, colour and visibility to a SketchUp
scene, found by `Page#persistent_id` and kept in the viewer's OWN model dictionary. A scene also
carries what it is for TrueVision (Plan, Site Plan, Elevation, Section, 3D View) and the scale it
will be printed at, which sets the dot size baked into its picture. TrueVision Sync (GLB Builder
2.11) renders the pictures through the public API and pushes them to R2. ARCHITECTURE section 23
is the full description.

### Built
- **Store** (`90__System__Scenes/...Scenes__Store__.rb`): dictionary `Na__PointCloudViewer__Scenes`,
  key `json`, schema 1. Found by persistent id, with the scene's name kept only as a hint. Read
  only when the record is corrupt or from a newer version, and unknown keys survive a save. Every
  change is one named operation, then the local backup. Nothing is ever written to a SketchUp
  scene (Page): no attribute, no update, no observer.
- **Recall** (`...Scenes__Recall__.rb`): moves SketchUp to the scene, then applies the saved
  settings, visibility and clip box in one operation. A missing scene changes nothing and says
  so, and Relink is the user's choice (a scene with the same name is suggested, never adopted).
- **Image export** (`...Scenes__ImageExport__.rb`): renders off screen from the scene's own camera
  (it never selects a scene, so no transition can be caught halfway). It works at 12 px per paper
  mm, in 2048 px tiles, under a 160 MP ceiling. Every dot is centred on its point within half a
  pixel. The frame record places the picture exactly in TrueVision's world. The revision key
  changes when anything that changes the picture changes.
- **Public API** (`...Scenes__PublicApi__.rb`, scenes API 1) for TrueVision Sync: scene list,
  export settings, plan, render, frame record, pixel of a model point.
- **UI** (`...Scenes__UiSystem__MainUiLogic__.js`, `...UiFeature__Styles__Scenes__.css`): the Scenes
  tab. Cards with recall, tags, warnings and relink, plus Type, Scale (presets or custom) or Image
  Width, Dot Size, Go To Scene, Update and Remove.
- Model link, local backup and restore carry the scenes record (`NA_RECORD_KEYS`).

### 19-Oct-2026: Site Plan scenes, and the scale list Adam meant
- Adam: "I put 1:2000. What I meant to put was 1:1250 and 1:2500 ... there will be site plan point
  clouds as well." The scale presets now end 1:500, 1:1250, 1:2500 (1 px dots), and a **Site Plan**
  scene type sits after Plan. It looks straight down like a plan, and TrueVision lays it on a site
  plan viewport (or a plan). The tilt warning names it: "A site plan should look straight down."

### 19-Oct-2026: Adam's first look at the Scenes tab
- **Scenes is now the second tab** (View, Scenes, Clipping, Transform, Clean, Settings).
- **Colour mode checked:** RGB or Monochrome is part of every saved scene. It is captured, recalled,
  baked into the exported picture, shown in the summary, and a colour change alone marks the scene
  Settings changed.
- **Update moved away from Go To Scene.** Adam: "The update button is too easy to fudge." Go To Scene
  now stands alone on the left; Update and Remove sit together on the right. Update goes amber
  (not blue) when the settings have changed.
- **Are you sure? dialogs on Update and Remove.** These replace the old two-click Remove. Update
  shows Saved Now against Will Become (the payload's new `currentSummary`) and warns when SketchUp
  is showing a different scene, which is the easy mistake. Remove lists what goes and that TrueVision Sync
  stops exporting the scene. Cancel has the focus; Escape and a click outside also cancel.

### 19-Oct-2026: Scenes API 2, for TrueVision Sync's Scene Sync
- Each row of `Na__PublicApi__SceneList` carries `pagePid`, the SketchUp scene's persistent id. TrueVision
  Sync's Scene Sync tab (GLB Builder 2.12) uses it to pair a point cloud scene with the synced drawing of the
  same SketchUp scene, which TrueVision then lays it on exactly. `NA_SCENES_API_VERSION` is 2, guarded for hot
  reload, so a session reloaded from API 1 still answers 1: callers test for the key itself.

### 19-Oct-2026: Drag to reorder (clip scenes and point cloud scenes)
- Adam: "Ensure these can be rearranged so you can click to drag to reorder, use a grab box symbol". Each
  clip scene row (Clipping tab) and each point cloud scene card (Scenes tab) has a six dot grip. Press it and
  the row lifts and follows the pointer, the others slide out of its way, the panel scrolls near its edges,
  and letting go drops it there. Esc puts everything back. A grip with the focus moves its row with the up
  and down arrow keys. Full Cloud has no grip and stays first. No grips while a name is being renamed, on a
  read-only record, or with only one scene.
- `01__AppCore/...UiSystem__DragReorder__.js` is the shared piece: listeners delegated to the list (so a
  state push never loses them), a repaint held back while a row is lifted, pointer capture, FLIP slides.
- Ruby: `Na__Clip__SceneReorder` and `Na__Scenes__Reorder` take every id top to bottom and save the new
  order as one undoable step ("Point Cloud: Reorder Clip Scenes" / "Point Cloud: Reorder Scenes"). A list
  that no longer matches the scenes (one added or removed meanwhile, or an id twice) changes nothing and
  says why; the same order again writes nothing. Dialog actions `clip_scene_reorder` and `scenes_reorder`.
- **Scenes API 3:** `Na__PublicApi__ReorderScenes(model, ids)`, so TrueVision Sync's Point Cloud tab (GLB
  Builder 2.13.1) drags the same record; the viewer's tab repaints when it does. Callers test respond_to?.
- TrueVision's own scene list stays alphabetical: the GLB Builder's store manifest sorts by name.

### Tested
- `pcv_scenario_scenes.rb`: 95 checks, all passing (83 plus the Update dialog's summary, colour
  mode alone marking a change, putting it back clearing it, each row's pagePid, and section 13b: the
  reorder from the tab and through API 3, the store revision, a stale list refused, Undo).
- `pcv_scenario.rb`: 189 checks, all passing (183 plus section 9b: clip scene reorder, its named step,
  the stored order, a stale or doubled list refused, the same order writing nothing, Undo).
- Drag to reorder driven in a browser with real pointer events on both lists: the lifted row, the
  live order, a state push held back mid drag, one call per drop with the full order, nothing for a
  drop in place or after Esc, Full Cloud kept first, the arrow keys keeping focus.
- The dialogs were driven in a browser with a stub state: Escape, backdrop and Cancel send nothing,
  each confirm sends exactly one call, and the dialog closes if its scene disappears.
- The original 83 cover the record, read-only and
  unknown-key cases, recall, relink and remove, and the public list (Site Plan, 1:1250 and 1:2500).
  They also cover the export: frame, tiles, dot centring for 1 to 4 px, perspective, horizontal
  fov, size limit and revision keys. Tripwires prove no SketchUp scene was ever written, updated,
  added or erased.
- Not yet tried in SketchUp itself: the scale presets' dot sizes (1:50 and 1:100 especially) want
  Adam's eye on a real scan.

## Point Cloud Viewer - v0.8.0 - 12-Oct-2026 - Clean Tab, Clean & Export to a New LAS

### Summary
Adam asked for a complete architectural point cloud cleaning system inside the viewer: a Clean
tab with three filters (Remove Noise, Refine Surfaces, Reduce Density), a live preview in the clip
box, an Original / Cleaned / Differences view, a surface check, and Clean & Export LAS that never
touches the original: a Save As every time, a new file, checked and published without replacing
anything, loaded in the same position and used by the model only when everything succeeded.
Designed, built and tested; ARCHITECTURE section 22 is the full description.

### Built
- **Engine (ABI 5):** clouds keep each point's LAS record and GPS time; LAS content key; point
  cache v2 named by the content key (v1 still read); the cleaning engine (deterministic KD-tree,
  zones and halos, preview worker per cloud with stage re-use and supersession, full-cloud tiling,
  sparse cell grid); the LAS export writer (record passthrough, header rebuilt, VLRs / EVLRs kept,
  provenance VLR, partial file, LASzip check, publish without replace).
- **Ruby:** bridge for ABI 5 (contexts and export jobs destroyed before a DLL swap);
  `80__System__Clean/` (Settings: strength to physical values; Preview: debounced requests, poll
  timer, display clouds; Export: Save As loop, checks, the job, the model association, retry);
  content keys in the import, the cache and the model link (`contentKey`, `derivedFrom`, `history`);
  placement carried over to a new local origin; Undo after "Use Cleaned LAS" leaves the loaded
  cloud in place with a note.
- **UI:** Clean tab between Transform and Settings (Preview Region, three filter cards with
  Advanced Settings, Preview Results with the display switch, legend, statistics, surface check,
  Reset to Defaults; Clean & Export with the last export's report and Load Cleaned LAS). Version
  0.8.0; config `clean` section and `render.cleanColours`.

### Found by testing today and fixed
- **False "doubled surface" at corners and trim junctions** (no doubling in those scenes). Causes,
  each measured: 60 mm of a wall in a corner block fixes its normal only to ~5 degrees (PCA on the
  true labels: 4.9 degrees), so a tilted plane read as two sheets; "thin" blocks at frame / sash
  staircases and sill edges lent planes tilted 17 to 50 degrees; the second plane of a block was
  scored on leftovers, where an edge-on frame strip fits any plane; trims fell back to the 8 mm
  default noise width; junction steps passed the footprint test; a pipe's sides passed the width
  test because 5 % of wall points inflated a standard deviation. Fixes: planes borrowed from thin
  cells, joint scoring over the whole block, a half-block test for thin cells, the noise width from
  the nearest thin cells, a mixing test for doubling, a robust width. False doubling points before
  -> after: corner 1825 -> 0 and 856 -> 0; window 618 -> 451, 1429 -> 661, 124 -> 0; blow-out 8551 ->
  3278; details 6981 -> 924 and 1695 -> 177. Real doublings still found (99.7 %, 99.9 %).
- **Exports failing with "Not enough memory" for large Advanced values or sparse clouds:** the
  per-region cell grid was dense over the whole tile plus halo (~400 MB even for 60 points). Now
  sparse (blocks allocated where points are); results identical (preview = export still bit for
  bit), memory follows the points.
- **An existing destination or the source itself** was only refused after a whole clean, with the
  message "appeared while cleaning". The engine now refuses both (and a missing folder) before
  cleaning, with the right message.
- **Undo of "Use Cleaned LAS"** could move the still-loaded cleaned cloud to its own import
  position when the original had no saved position. Now it stays where it is, with a note.
- **Previews too slow on dense scans** (a 1 m box on Cossethay took 2.5 s, over the 2 s target).
  Measured stage by stage: the 1348 mm margin is most of the work for a small box (32k points in
  the box, 1.45M gathered), and 75 % of the surface analysis was the two-sheet mixture test. The
  mixture EM now runs on fine bins (validated against the per-point EM on 499 943 real cases: the
  same decision in all but 10, each on a threshold); gather, the KD-tree build, the noise-width
  helper and the MSAC cost loop were made faster without changing a single result (checked point
  by point on 2.65M points and by test H). The same 1 m Cossethay box: 2.5 s -> 1.26 s. Not met
  everywhere: at the densest spot of each scan a 1 m box takes 0.2 s (JW02), 0.9 s (Derby Road),
  2.1 s (Cossethay) and 7.0 s (SK02, a passage the scanner went through many times: 615k points
  in one square metre, where refinement alone takes 3.1 s).
- **Whole-cloud clean slow on a site with one very dense spot** (found on SK02, Adam's Ascott
  Drive scan): one tile size for the whole site was set by its densest spot, 1181 tiles of ~2 m,
  each re-reading its 1.35 m margin. Tiles are now split only where the points are (113 tiles,
  clean 480 -> 331 s); the same flags and positions for all 66.3M points of JW02, Cossethay and
  SK02, compared point by point. The export now also fails, rather than skip a point, if the tiles
  ever miss one.

### Verified (all run today)
- Algorithms A to H 100/100; identity and cache 20/20; export integrity I 122/122 (LAS 1.2 formats
  0 to 3, LAS 1.4 formats 6 to 8, extra bytes, EVLRs, WKT); failure handling J 14/14; Ruby harness
  183/183 (existing) and 57/57 (Clean tab); performance K below, on six clouds including Adam's
  SK02 Ascott Drive GeoSLAM export (39.0M points). All suites were run again after the speed
  changes. Every real scan's SHA-256 and modified time were unchanged after its export.

### Performance (final engine, 12-Oct-2026 23:39; ARCHITECTURE 22.15)

| Cloud | Points | Load | Clean whole cloud | Write + check | Export total | Engine work peak | Process peak | Preview 1 m / first 2 m / 2 m re-used | Source unchanged (SHA-256 + time) |
|---|---|---|---|---|---|---|---|---|---|
| Synthetic room (LAS 1.2 f1 + time) | 1.16M | 1.0 s | 3.2 s (1 tile) | 0.8 s | 4.0 s | 224 MB | 564 MB | 0.44 / 1.10 / 0.17 | n/a (synthetic) |
| Synthetic 9 rooms (LAS 1.2 f1 + time) | 10.46M | 7.9 s | 42.1 s (8 tiles) | 5.3 s | 47.5 s | 959 MB | 1722 MB | 0.49 / 1.42 / 0.19 | n/a (synthetic) |
| JW02, RealityCapture (LAS f2, no time) | 10.76M | 1.1 s | 33.0 s (12 tiles) | 5.5 s | 38.6 s | 576 MB | 1027 MB | 0.05 / 0.44 / 0.01 | yes |
| Cossethay, GeoSLAM (LAS f1 + time) | 16.47M | 1.9 s | 86.6 s (25 tiles) | 8.0 s | 94.8 s | 1566 MB | 2694 MB | 1.38 / 3.51 / 0.78 | yes |
| Derby Road, GeoSLAM (LAS f1 + time) | 31.30M | 3.7 s | 149.0 s (70 tiles) | 14.9 s | 164.0 s | 947 MB | 2413 MB | 0.04 / 1.13 / 0.01 | yes |
| SK02 Ascott Drive, GeoSLAM (LAS f0, no time) | 39.03M | 3.3 s | 324.9 s (113 tiles) | 31.1 s | 356.2 s | 1814 MB | 3787 MB | 0.24 / 1.73 / 0.07 | yes |

Other processes (RealityScan) kept 0 to 3.4 cores busy during these runs. Before the speed work
and the adaptive tiles, the same evening: export total JW02 73.3 s, Cossethay 170.5 s, Derby Road
293.6 s, SK02 535.8 s.

### Limitations (see ARCHITECTURE 22.13)
- Doubled surfaces closer than ~2.5 noise widths cannot be seen without GPS time (20 mm at 10 mm
  noise: 11 %).
- Dense false reflections are kept by design; sparse blow-out only marked unless asked.
- Thin objects seen from both sides (an open door leaf, a radiator in front of its wall) are
  flagged as possible doubling and held (seen on Cossethay); real scans: 6 to 15 % of points
  flagged, not checked against a survey.
- At 10 mm noise, a ~2 noise-width band each side of a corner line is held, not refined.
- The first preview of a cloud also builds its coarse grid (0.3 to 0.4 s at 10 to 16M points,
  ~1 s at 39M).
- Not run: a destination folder without write permission; nothing was tried inside SketchUp itself.

### For Adam to test
- Reload Plugin is not enough this time: restart SketchUp (ABI 5 DLL and new Ruby).
- Load a scan, turn on the clip box round a wall and a corner, open the Clean tab: the preview
  appears; switch Original / Cleaned / Differences; drag a strength slider.
- Clean & Export LAS...: the suggested name is `<name>_Cleaned_01.las`; try choosing the original
  (refused) then a new name; when it finishes the model shows the new file in the same place; the
  original and its cache are untouched; Edit > Undo puts the model's link back.
- In Differences, magenta marks possible doubled surfaces: worth judging by eye on a real scan
  (SK02 flags 14.8 % of its points; open doors and radiators are flagged too and left as scanned).
- SK02 (39M points): a whole-cloud Clean & Export takes several minutes (see the table); check
  that SketchUp stays responsive meanwhile and that Cancel stops it with nothing written (both
  checked only in the offline harness so far).

---

## Point Cloud Viewer - v0.7.0 - 03-Oct-2026 - Faster Rendering, Point Cache, Cold-Start Crash Fixed

### Summary
Adam asked whether the optimisations promised before the clip box were ever done (they were not),
confirmed v0.6.0 persistence works ("everything's in the transformed place"), and asked for the
cache so a reload pops in without a full re-read. Then SketchUp started crashing on every start.

### Cold-start crash (fixed)
- Five crashed starts, identical: `SketchUp.exe+0x384172`, null write, Ruby interpreter on the
  stack, ~20 s after launch, `su_assistant.rb` (AI Assistant) on the stack in two dumps. A 22:02
  dump showed the same fault before most of today's changes.
- Not the native engine (not loaded in the crashed process). Bisected with real cold starts using
  a scratch template (`SketchUp.exe <file.skp>`: SketchUp 2026 loads extensions only after the
  Welcome screen, so two early "no crash" tests had proved nothing):
  plugin off -> fine; plugin loaded, bootstrap skipped -> fine; bootstrap without the model
  observer -> crash; overlay added only by the startup notification -> fine.
- Cause: the first InstallOnce added the overlay to the model while SketchUp was still loading
  extensions. Every Reload Plugin worked because SketchUp was already running; today's restarts were
  the first real cold starts. Fix: a cold start only registers the AppObserver; the startup
  notification adds the overlay (ARCHITECTURE section 18). Verified live: no crash, overlay
  registered and enabled, session bound.

### Rendering (ARCHITECTURE 7.2)
- Binned raster (per-band bins, one worker per band): 1M points 2x faster; all 10.8M 38% faster at
  full resolution. Images byte-identical to v0.6.0 in every test case.
- Screen crop (ABI 4): the image covers only the visible box's screen rectangle; nothing is
  rendered when the cloud is off screen or behind the camera. Zoomed out on JW02: 9.4 MB -> 0.8 MB
  per frame for SketchUp to decode. Live in SketchUp: 16% of the viewport rendered.
- Parallel PNG checksums (zlib combine): encode 10.5 -> 2.8 ms.
- Orbit budget: at most 5M points while moving (all 10.8M orbiting: 57 -> 23 ms native), the whole
  budget once settled.

### Point cache (ARCHITECTURE section 9)
- `.napc` v1 written by the import worker (tmp + rename), loaded on a worker thread, header CRC and
  exact length checked, LAS size + time recorded. One cache per scan.
- Reload Point Cloud and Import LAS use the cache when the LAS is unchanged (JW02: ~0.1 s), rebuild
  it when the LAS changed, fall back to the LAS when a cache is damaged, and load the cache alone
  (with a note) when the LAS cannot be found anywhere.
- Settings: cache count and size, Clear Point Caches.

### Verified
- Native: equivalence test old vs new engine (4 cases + crop), perf table, cache test (write, peek,
  0.08 s load, byte-identical render, wrong count / truncated / CRC-damaged / missing refused).
- Offline harness: **183 checks pass** (13 new): cold-start registration, crop and off-screen
  skip, orbit cap and settle, cache saved on import, Reload from cache, damaged cache falls back,
  LAS missing loads from cache, Clear Point Caches.
- Live SketchUp (scratch template, pinned to a test instance): two cold starts with the final
  code plus the bisection run that proved the cause, no crash; import + render with the crop,
  screenshot correct.

### For Adam to test
- Start SketchUp normally, open a model, open the dialog: no crash.
- Reload Point Cloud: the first time reads the LAS and saves a cache; the next Reload is near
  instant.
- Orbit with All points: smoother while moving, full density when you stop.

---

## Point Cloud Viewer - v0.6.0 - 03-Oct-2026 - Saved With the Model, Gimbal Point, All Points

### Summary
Adam, working with v0.5.0: move and rotate are "incredible". Three requests: (1) a 20 million
point budget, (2) data persistence that can never leave a model with its cloud in the wrong place
the next day, and never auto-loads (Undet once made his files unopenable), with the model as a
pointer and a second copy so two things have to fail, (3) a gimbal he can place on a vertex, like
SketchUp's Axes tool.

### Point budget
There was no computational limit: the plugin ceiling is already 50 M. The slider stops at the
loaded cloud's own point count (JW02: 10,758,745) because a higher budget cannot draw more, and
the 20 M preset looked disabled. Now presets at or above the cloud's size become one **All**
preset, the value reads "All 10,758,745", and the hint says it is the top of the scale. Display
settings are remembered per user, so the raised budget is still raised tomorrow.

### Persistence (see ARCHITECTURE section 14)
- New `Na__PointCloudViewer__ModelLink` record (link id, LAS name, last path, path relative to
  the .skp, unit, point count, fingerprint). Written on import, rewritten only when the LAS or its
  location changes.
- Local backup per link in `91__UserConfig__LocalOnly/Na__PointCloudViewer__ModelBackups/`,
  rewritten after every real point cloud change; a newer one is archived, never overwritten.
- Nothing happens on open. The View tab's **Saved With This Model** card offers Reload Point
  Cloud (header fingerprint checked first), Locate LAS..., Restore Newer Backup / Restore From
  Backup. Settings has Open Backups Folder and Remove Point Cloud Data From Model.
- Placement and clip writes now abort the operation on error and carry `updatedEpoch`.
- Placement matching ignores the file name (point count + survey origin), so a renamed copy keeps
  its position.
- Element Studio Pro was checked first: it keeps JSON in definition attribute dictionaries and
  does nothing on open, but has no copy outside the model. Its patterns (operations with abort,
  validation, defaults merge) were kept; the backup is new.

### Gimbal point
- Default moved from the base centre to the centre of the cloud's box.
- **Set Gimbal Point** (Transform tab): the next click, with SketchUp inference, places the
  gimbal; it is stored on the cloud (local coordinates) so it moves and turns with it. **Centre
  Gimbal** resets it. Both undoable, saved in the model.
- Typed X / Y / Z are now the gimbal point's model position; typed rotations turn about it.

### Verified
- Offline harness: **170 checks pass** (32 new): link written once with a relative path, backup
  mirrors every change, the "closed without saving" case end to end (older .skp reopened, backup
  shown as newer, an unrelated Undo leaves it alone, Restore writes it back in one operation,
  Reload brings that alignment back and writes nothing), unreadable link falls back to the
  backup, Locate refuses a non-matching file and can be cancelled, Remove deletes all three records
  and Undo restores them, display settings carry into a new session, gimbal pick snaps to a vertex,
  moves with the cloud in 5 mm steps, typed rotation pivots on it, Esc while picking, Centre +
  Undo.
- Dialog checked in the browser pane: link card with a newer backup, All preset, gimbal row.

### For Adam to test (Reload Plugin)
- Save the model, close SketchUp, reopen: nothing loads; the View tab card shows the LAS found;
  Reload Point Cloud brings it back in place, locked, with its clip box.
- Move the cloud, close SketchUp WITHOUT saving, reopen: the card offers Restore Newer Backup.
- Transform > Unlock > Set Gimbal Point > click a vertex; drag the arrows from there.

---

## Point Cloud Viewer - v0.5.0 - 03-Oct-2026 - Transform Tab: Move Gimbal, Rotate Protractor, Lock, Export

### Summary
Adam, after testing v0.4.0: "The clip box works absolutely perfectly... Now add the tool so we can
transform a point cloud." He asked for a gimbal like Vertex Tools (drag X / Y / Z, snap, 5 mm by
default), a SketchUp-style protractor rotation that can line the cloud up with things, a lock that
keeps the cloud untouchable until he goes back into the transform tools, typed values for fine
control, and a JSON export of the whole configuration. All of it is on a new **Transform** tab.

### Built
- **`60__System__Transform/`**: Placement (state, maths, storage, lock, typed values, snap
  prefs), MoveTool (gimbal), RotateTool (protractor), ConfigExport, Transform tab JS + CSS.
- **Placement** = rigid `R` + `t`, kept orthonormal, stored in the model dictionary
  `Na__PointCloudViewer__Placement` with the cloud's fingerprint; restored when the same LAS is
  re-imported (the import message says so). Locked by default; one undoable operation per change;
  Undo / Redo re-read it with the clip state (`Na__Registry__ReloadModelState`).
- **Move gimbal**: red / green / blue arrows at the cloud origin, fixed size on screen, hover
  highlight, drag or click-move-click, 5 mm snapping from the drag start (per-user step, can be
  turned off), typed distance, Esc, dashed axis guide.
- **Rotate protractor**: centre, start direction, rotate; SketchUp inference on the clicks so the
  cloud snaps into line with model edges and endpoints; arrow keys lock the axis; optional angle
  snap (15 degrees, off by default); typed angle during or after; Esc.
- **Typed values**: X / Y / Z of the cloud origin (survey point shown) in model units; Plan (Z),
  Tilt X, Tilt Y in degrees; Reset to Import Position (second click confirms).
- **Export Configuration...**: save panel (model's folder), one JSON file with cloud, units, local
  origin, placement (incl. matrix), clip box, scenes, display and snap settings.
- Engine untouched (ABI 3): the render matrix was already general. The image renderer's cache key
  now includes the placement, so a move re-renders; the clip box stays fixed in the model.
- A cloud imported before v0.5.0 gets a placement derived from its matrix on Reload Plugin, so no
  re-import is needed.

### Verified
- Offline harness: **138 checks pass** (59 new) with the real modules, DLL and JW02: lock refusals,
  unlock record, gimbal hover / drag / 5 mm snap / VCB re-type / Esc, snap step validation, typed
  X + Plan 90 (pure rotation, bounds swap width and depth, no scale), tilt with a unit, undo twice,
  protractor (axis keys, snapped centre, exact 90 degrees onto a model point, re-type 45, angle snap
  50 -> 45, Esc, typed -30), moving the cloud half out of a fixed clip box (48% left), lock
  deselects the tool, export file contents and cancel, a different LAS not inheriting the position,
  re-import restoring position + lock, a pre-v0.5 cloud getting a placement.
- Dialog checked in the browser pane: layout at 600 px, locked state disables tools and values,
  a state push does not wipe a half-typed value, Esc reverts, Reset needs a second click, every
  button sends the right action.

### For Adam to test (Reload Plugin; the loaded cloud keeps working)
- Transform tab > Unlock to Transform > Move: drag the arrows; watch the 5 mm steps in the VCB.
- Rotate: click a corner, click along a wall in the cloud, then click on a model edge.
- Type X / Y / Z and Plan; Undo; Lock Position (tools switch off); Export Configuration.
- Save, reopen, re-import the LAS: it comes back where you left it, locked.

---

## Point Cloud Viewer - v0.4.0 - 03-Oct-2026 - Clip Box, Clip Scenes, Test Tooling Removed

### Summary
Adam, after importing JW02: "It works incredibly... Try the clip box next... so I can get to work
drawing with it." The clip box was brought forward ahead of the `.napc` cache. The Clipping tab now
clips the cloud with six typed limits or by dragging the sides of a box in the model, and saves
clip scenes (Ground Floor, Roof, ...) in the `.skp`. All M1 test tooling and the em dashes in the
UI are gone.

### Built
- **Native (ABI 3):** clip parameters on the render call (enabled + model-space min/max); points
  are tested after local -> model, so the box stays level with the model. **Clip-aware budget:**
  with the clip on, the budget counts points INSIDE the box. The engine finds the smallest prefix
  of the (randomly ordered) point list holding N inside points, caches it per (box, placement,
  budget), and draws that prefix, so a small box is as dense as the whole cloud.
- **`50__System__ClipBox/`:** State (box, scenes, storage, every change), EditTool (cage drawing
  and the `Na__ClipBoxTool`), Clipping tab JS. See ARCHITECTURE section 10 for the behaviour.
- **Stored in the model**, dictionary `Na__PointCloudViewer__ClipState`, one named undoable
  operation per change; a `ModelObserver` per model re-reads it after undo/redo.
- **Edit tool:** square handles at the face centres, hover outline, press-drag or click / move /
  click, typed distance in the VCB (also re-types the last move), Esc cancels, clips live while
  dragging, half-resolution renders during the drag.
- **Scenes:** Full Cloud (clip off, box kept), save, switch, Update when changed, inline rename,
  delete with a confirming second click.
- **Zoom to Cloud** frames only the clipped part while clipping is on.
- **View tab:** cloud name + points + size, Unload button, drawing fault line, plain budget hint.
- **Settings tab:** Technical Log moved here; About without milestone text.
- **Removed:** synthetic cloud, benchmark runner and reports UI, Diagnostics tab, Position
  placeholder tab, live performance strip and stats polling, FrameBuilder, the Ruby point
  primitives (GL_POINTS / draw_points / line dots), `renderPrimitive` and `colourBucketLevels`
  settings, the `dev` user-config section (user config schema v3 drops it), DrawStats.
- **Wording:** no em dashes or dash punctuation anywhere the user reads (dialog, status messages,
  tool status text, LAS import messages).

### Verified
- ctypes, JW02 (10,758,745 points), box = middle ninth of the plan: 1M drawn of 1,225,267 inside
  (was ~114k before the clip-aware budget); limit search 19 ms once, then cached; budget = total
  and budget 0 behave.
- Offline harness rewritten for LAS + clip: **79 checks pass** with the real modules, the real DLL
  and the JW02 file: import, clip on at the bounds, typed limits (bare mm and "0.5m"), refusals,
  edit tool hover / drag / VCB / negative VCB / Esc / click-move-click, scenes (save, unnamed,
  reset, switch, Full Cloud, Update, rename, delete), undo of rename and delete via the
  ModelObserver, a fresh session reading the same state, corrupt JSON ignored, unload keeps the box,
  no dashes in any dialog message.
- Dialog checked in the browser pane with a pushed state: Clipping tab layout, rename survives a
  state push mid-typing, Delete confirm, Esc reverts a limit.

### For Adam to test (Reload Plugin, then re-import the LAS: the engine was rebuilt)
- Clipping tab > Clip on: whole cloud still shown, box = bounds.
- Type Top / Bottom in mm: points above / below disappear immediately.
- Edit Clip Box: orange cage, drag a square handle, type a distance, Esc mid-drag, Undo.
- Save "Ground Floor", Reset to Cloud, click Ground Floor, Full Cloud.
- Save the .skp, reopen it and re-import the LAS (no cache yet): the box and scenes are still there.

---

## Point Cloud Viewer - v0.3.0 - 03-Oct-2026 - Milestone 2a: LAS Import

### Summary
View tab > **Import LAS...** reads a `.las` through the vendored LASzip, inside the native engine,
on a worker thread. A report of the header comes first, then an explicit unit choice, then the
import with progress and Cancel. The cloud lives only in the engine and is drawn by the native
image renderer. First real file: Adam's JW02 Juggles Joint RealityCapture export.

### The test file (JW02, RealityCapture)
LAS 1.2, point format 2, 26-byte records, **10,758,745 points, 280 MB**, 16-bit RGB, no VLRs (no
coordinate system, no units), local coordinates 59.3 x 45.1 x 13.8. The `.rsInfo` says
`exportVertexColors="0"`, but the points do carry RGB.

### Built
- Engine (ABI 2): `napc_las_read_header` (facts + VLR scan: WKT 2112, GeoTIFF 34735),
  `napc_las_import_start` / `napc_job_poll` / `_error` / `_cancel` / `_take_cloud` / `_destroy`.
  The worker reads every point, stores it as float32 in the SOURCE unit relative to a local
  origin (header bounds: centre x, centre y, min z), detects 8- vs 16-bit colour from the data,
  then shuffles (deterministic Fisher-Yates) so the point budget is a uniform sample of the whole
  cloud. Progress via atomics; cancel checked every 65,536 points.
- LASzip compiled from the vendored copy with upstream's exact source list (the legacy
  `lasunzipper.cpp` / `laszipper.cpp` in the same folder are not part of it and do not compile).
- **LASzip trap:** `laszip_get_point_count` returns the number of points READ so far, not the
  file's total (0 straight after opening). The total is the header's `number_of_point_records`,
  or `extended_number_of_point_records` for LAS 1.4.
- Ruby: `40__System__LasImport/` (controller, job, panel JS). The unit question pre-selects
  nothing unless the file's WKT names a linear unit; every option previews the real size
  (Metres 59.3 m x 45.1 m x 13.8 m, Millimetres 5.9 cm x 4.5 cm x 1.4 cm). `.laz` and
  LAZ-compressed files are refused with a plain message.
- The unit factor is applied per frame on the render matrix diagonal (`local_to_model`); stored
  coordinates never change.
- Engine memory of a replaced or cleared cloud is freed immediately, not at GC.
- A LAS cloud is always drawn natively; benchmark Ruby-primitive cases skip on it.
- Async jobs accept a per-step `delay` and `quiet`, so polling the worker every 0.1 s does not
  flood the dialog.

### Verified
- Standalone (ctypes): header 0.4 ms; import 2.9 s cold (read 2.4 s, colours 23 ms, shuffle
  0.4 s); cancel stops mid-read; render at 1600 x 1000: 2M points 35 ms, all 10.8M 70 ms. The
  rendered view shows the farm buildings correctly (Z-up, metres, colours).
- Offline harness: 95 checks pass, including this file through the real dialog actions
  (import 1.1 s warm, 1M drawn in 10 ms, all 10.8M in 27 ms, memory freed on clear).

### Not yet
- No cache: an import lasts for the SketchUp session (re-import after restarting or after a
  native engine hot swap). Milestone 2b adds the `.napc` cache and model association.
- Shuffled order costs raster cache locality; the octree (M3) restores spatial order.

---

## Point Cloud Viewer - v0.2.0 - 03-Oct-2026 - Milestone 1b: Native Image Renderer

### Summary
The M1 benchmark (Adam, SketchUp 26.2.243, graphics_engine_2024, RTX 5080) ruled out drawing
points through SketchUp's View API. The cloud is now rasterised by a C++ engine into an image and
shown as ONE textured screen quad. It is the new default primitive ("Native image"). Point size,
opacity and Monochrome Black now work, and a still camera costs ~0.1 ms per redraw at any point
count. Adam, testing live: "It's actually really fast now."

### What M1 measured (full suite, 1,000,000-point synthetic house)
| Primitive | Cost per drawn point | 100k points | 1M points |
|---|---|---|---|
| GL_POINTS | ~2.3 us (draw) / ~3.0 us (frame) | 300 ms (3.3 fps) | 3,050 ms |
| draw_points | ~2.3 us | - | 3,140 ms |
| GL_LINES "line dots" | ~0.13 us per vertex | - | 310 ms, but drew NOTHING (sub-pixel segments are culled) |

- Colour-batch count barely matters (1 vs 231 calls: 2.18 vs 2.39 us/pt). The cost is SketchUp's
  per-point path, not our Ruby.
- Visual checks: GL_POINTS ignores size; draw_points honours size; no primitive honours alpha;
  nothing is hidden by model faces (overlays draw on top); point-to-point depth works.
- Ruby Point3d conversion 631 ns/pt; full GC pause 160 ms at 1.2 M live objects.
- `view.last_refresh_time` returned ~0 - removed from reports.

### Texture route probes (live SketchUp via the MCP bridge, 1909 x 1228 logical viewport)
- `view.draw2d` textured quad: 0.1 ms. `load_texture`: ~3 ns/px (6.5 ms full window).
- `ImageRep#set_data` 32-bit: ~54 ns/px (125 ms full window) - too slow. 24-bit is 3.5x faster but
  has no alpha. `ImageRep#load_file` of an UNCOMPRESSED (stored) PNG: ~16 ns/px with alpha - the
  route used. BMP drops alpha; TGA slower.
- Texture alpha composites correctly over the model.
- **UVs must be plain Arrays (or Point3d).** `Geom::Vector3d` UVs - the type the docs name - make
  SketchUp sample the texture's single average colour (the whole card showed as a flat tint). Found
  by drawing the same quadrant texture with each UV type and texture source.
- Projection: SketchUp's model-to-screen mapping reproduced from camera eye/axes/fov/height alone
  with 0.0 px error (perspective, 60 deg perspective, parallel) against `View#screen_coords`.

### Built
- **Native engine** `02__Src__NativeEngine/` (decimator layout): C ABI DLL
  `Na__PointCloudViewer__NativeEngine.dll` - thread pool (16 workers here), compute-rasterisation
  style splatting (64-bit atomic depth|colour per pixel, nearest wins, no locks), round splats from
  3 px, opacity, monochrome, stored-deflate PNG writer (slicing-by-8 CRC-32, Adler-32). Static CRT,
  no AVX2 requirement. CMake + Ninja + MSVC 14.44; build script maps a free drive letter for path
  length and unmaps it afterwards.
- **Fiddle bridge** `08__NativeEngine/...Bridge__.rb`, not a Ruby C extension: no Ruby headers or
  import library, independent of SketchUp's Ruby version, and **hot-swappable** - Ruby loads a
  shadow copy, so the build can overwrite the DLL while SketchUp runs, and Reload Plugin unloads the
  old copy and loads the new one. Native clouds are Fiddle pointers freed by GC; before a swap
  every live one is destroyed and owners re-upload.
- **Image renderer** `10__Viewport__OverlayRenderer/...ImageRenderer__.rb`: camera key + settings
  key; reuse the texture when nothing changed; half resolution while the camera moves
  (`render.nativeImage.movingScale`); one full-resolution render 0.25 s after it stops.
- Default primitive `nativeImage`, default budget 1,000,000. User config schema v2 drops the old
  `dev.renderPrimitive` so a saved Ruby primitive does not hide the new default.
- Benchmark: native cases (orbiting, camera still, forced full scale) with raster / PNG / load /
  texture medians; Ruby primitives kept at 100k as a reference.
- Dialog: 4-way primitive switch, Native column in Visual Checks, native timing columns,
  native line in the live strip, native status in Settings.

### Verified
- Standalone DLL self-test (Python ctypes): PNG valid; exact pixel placement for parallel and
  perspective; nearest point wins; 5 px round splat; 50% alpha; mono; behind-camera culled.
  Speed (random points, 16 threads, 2 px): 1M at 1909x1228 31.6 ms, 4M 57.7 ms; at 955x614 1M
  15.7 ms, 4M 31.2 ms. Raster dominates (random points thrash the cache; a cache in spatial order
  will be kinder).
- Offline harness (real modules + the real DLL via Fiddle inside SketchUp's Ruby DLL): 81 checks
  pass.
- Live: Adam ran it in SketchUp - fast.

### Still open
- Points are still not hidden by SketchUp faces (an Overlay limitation, unchanged from M1).
- Full-resolution frames after the camera settles cost ~45-75 ms - a one-off hitch, not per frame.
- Next: Milestone 2 - LAS import (LASzip) and the `.napc` cache feeding this engine directly.

---

## Point Cloud Viewer - v0.1.0 - 03-Oct-2026 - Milestone 1: Viewport Renderer Proof

### Summary
New self-contained plugin: `Na__PointCloudTools__PointCloudViewer__Loader__.rb` +
`Na__PointCloudTools__PointCloudViewer__Modules__/`. Milestone 1 proves the viewport architecture
before any LAS/cache engine is written: a persistent `Sketchup::Overlay` per model, a prepared-frame
renderer, a deterministic synthetic test cloud, and a benchmark that measures what drawing points
through SketchUp's Ruby View API really costs. Design for the whole plugin:
`85__Docs__AppDocumentation/Na__PointCloudViewer__ARCHITECTURE__.md`.

### Why the renderer comes first
SketchUp's Ruby View API has no retained GPU buffers, no per-vertex colour and no binary input.
Every redraw re-submits every drawn point as a Ruby `Geom::Point3d`, once per colour batch. That
is the single greatest risk to the product, and no amount of cache engineering helps if it is too
slow. So it is measured first.

### API facts verified (ruby.sketchup.com, Oct 2026)
- `Sketchup::Overlay` (2023.0+): `draw` and `getExtents` are "called very often"; overlays are not
  pickable or exportable; model changes from overlay events raise. `OverlaysManager#add` returns
  false for a duplicate id; a removed overlay cannot be re-added.
- `View#draw_points(points, size, style, color)`: one colour, size in logical px (2025+).
  `View#draw(GL_POINTS, points)`: colour from `drawing_color`; options are only normals / texture /
  uvs. No per-vertex colour anywhere.
- `View#line_width=` clamps to >= 1.0 as of 2026.0. Whether it sizes GL_POINTS is undocumented.
- `View#graphics_engine` (2024+), `last_refresh_time`, `refresh` (synchronous, use sparingly).
- Forum reports (not verified here): `draw_points` ignores occlusion; frame rate dropped from >60
  to 20 fps at 20-100 k points through `draw_points`.

### Built
- **Overlay + registry** - `Na__CloudOverlay`, one per model via an AppObserver
  (`expectsStartupModelNotifications`), found by id in `model.overlays` (no Ruby-side model hash,
  nothing to leak). Show switch = `overlay.enabled`, the same switch as the Overlays panel.
- **Renderer** - `Na__RenderFrame` of colour batches prepared outside `draw`; `draw` issues one
  call per batch. Three primitives for the decision: GL_POINTS, draw_points, GL_LINES sub-pixel
  "line dots". Draw faults pause drawing instead of raising every frame.
- **Render settings** - Point Budget (log slider, presets, numeric), Point Size, Point Opacity,
  RGB / Monochrome Black. None rebuild point arrays except budget/primitive/batching, which
  re-slice cached buckets.
- **Unit contract** - exact factors, no defaults, three-line unit summary in the UI.
- **Synthetic test cloud** - two-storey house with openings, inner faces, floors, roof, trees,
  ground; generated in metres, converted through the unit contract, packed as float32 blocks and
  converted to Point3d in a timed step. Position-driven colour tint so it fills colour buckets like
  real data (8 / 39 / 217 of 8 / 64 / 512) - without it only 16 of 64 buckets were used and the
  benchmark would have under-counted draw calls.
- **Benchmark** - quick and full suites (`benchmark.suites`), orbit camera, forced refresh per
  frame, median/p90 frame time, draw time, SketchUp refresh time, model-only baseline, overlay
  cost, ns per point. Camera and settings restored on finish, cancel and failure. Reports in
  `90__AppCache__PointCloudCache/00__DevBenchmarks/`.
- **Visual checks** - size / occlusion by faces / occlusion by points / opacity / orbit feel per
  primitive, saved per PC and merged into the latest report.
- **Async jobs + loading overlay** - timer-tick steps with progress and Cancel; the page paints its
  overlay before calling Ruby.
- **Settings** - hot reload (Ruby + HTML/CSS/JS + config JSON), explicit note that a native `.so`
  cannot be reloaded, native engine status, Open Cache Folder, user config folder.
- **LASzip 3.5.0** vendored (copy, not submodule), unmodified, with manifest and README.
- `.gitignore`: `**/90__AppCache__PointCloudCache/`.

### Verified offline
`D:/_ClaudeScratch/pcv_runners/` runs the real modules in SketchUp 2026's own Ruby 3.2 DLL
against API stand-ins: 62 checks pass - overlay registered once (also after repeated install and
after reload), generation progress/finish, bounds, determinism, every draw path, budget slicing,
black + opacity colour, setting clamps, draw-fault containment and recovery, user-config
persistence, benchmark report/skip/derived figures, camera + settings restore on finish and on
cancel, refused starts closing the loading overlay, observations merge, visibility, zoom, hot
reload (same overlay, no extra observer, cloud survives, new code draws), dialog reopen + notice.
All Ruby parses with SketchUp's parser; all JS passes `node --check`; the dialog was rendered in a
browser with a sample state.

### Not verified (needs SketchUp)
Every number, and every visual question: actual draw cost, whether line_width sizes GL_POINTS,
occlusion behaviour, alpha, orbit feel, real Point3d conversion cost, real GC pause.

### Known gaps
- No native code yet; the studio PC has no MSVC/CMake/Ninja and the decimator's Ruby-headers
  submodule is not checked out here.
- Clipping and Position tabs are placeholders describing their milestone.
