# Na PainterlyNPR Assets - DEVLOG

The SketchUp side of PainterlyNPR's asset library (`Na__PainterlyNPR\12__Data__AssetLibrary`): a catalogue of every
asset with its pictures, placing an asset in the model, authoring a selected component as a new asset, and
PainterlyNPR's own validator in the dialog. Since 0.2.0 also PainterlyNPR's drawing of the model inside SketchUp (the
NPR Viewport and NPR Parameters windows); since 0.3.0 its look and export settings kept in the model, and NPR Export;
since 0.4.0 the engine's Assets drawer and art direction in the NPR Viewport, everything they do kept in the model.
Newest entry first.

Module `Na__PainterlyAssets`, files `Na__PainterlyAssets__*`, loader `Na__PainterlyNPR__AssetLibrary__Loader__.rb`,
menu Extensions > Na PainterlyNPR Assets.

---

## Version 0.4.0 - 03-Nov-2026 - Assets, Materials and Art Control Points in the NPR Viewport

### Asked For

Adam, 03-Nov-2026: *"Add art control points system and a in engine assets / materials system in the SketchUp Plugin"*;
*"Collapsed by default to keep the SketchUp NPR Viewer clean and lightweight but you can pop each side open and resize the
menus if needed"*; *"Works the same as the NPR Standalone, drag + drop assets and materials"*; *"Materials toggle for per
object / per face material assingment"*; *"Assets need to sync with the SketchUp Model, so when a new material is dragged
and assigned it updates the corresponding SketchUp Model, same with dragging in a asset like a plant etc."*; *"DO NOT
REINVENT THE WHEEL ... never duplicate code"*; *"Load the system and parameter mapping from the main project do not create
any new files if possible always call and cache the repo"*.

Asked what three things should mean, he chose: Object paints **the group under the pointer**; **one set of points per
scene**, his rule in AURA; a dropped asset lands on **the surface under the pointer**.

### What It Does

| Where | What |
|---|---|
| NPR Viewport, left | The engine's own Assets drawer: its Objects and Materials tabs, search, categories and filters, cards dragged onto the drawing, the Give to Object / Face toggle, the brush, its right-click menu and the Move Tool (M). Folded to a small tab whenever the window opens |
| NPR Viewport, right | The engine's own Art direction section: every point type, the point on the sheet with its sliders, the list, groups, copy and paste, Show influence. Folded to a small tab whenever the window opens |
| Both | Folded, a column takes no room, so the drawing is as large as before. Open, the engine's own drag handle sizes it and the engine remembers the width |
| The drawing | Still SketchUp's camera: a drag never orbits (the engine's own view lock), and the lock's, camera and work mode keys are kept from it. Ctrl + Z, Ctrl + Y and the right-click menu's Undo and Redo are SketchUp's |

| Done in the viewport | What happens in the SketchUp model (one named undo step a batch) |
|---|---|
| A card dropped, or clicked then the sheet clicked | The asset's proxy at the model's root, on the proxy tag `04__AuraRender__NprAssetProxies`, standing on the face under the pointer when it faces upward, else on the ground. The shape the drop grew is kept on the instance |
| A plop moved, turned, sized, swapped, copied or taken out; Grow a New Shape | That proxy moved, turned, sized, given the other definition, added or erased; the new shape kept on the instance |
| A swatch on an object, Object | Every face in the innermost group or component under the pointer takes the swatch's `MAT000E__Npr__<Class>`, by the Materials tab's own rules: glass kept, locked left alone, every copy of a component changing, the status line saying how many. Loose geometry: its connected faces |
| A swatch on an object, Face | The face under the pointer, and any joined to it across a soft or hidden edge |
| A swatch on a placed plant or pot | Kept on the instance (`Materials`), drawn by the engine. The proxy's faces are never painted: Write SKP would save the paint |
| A point placed, moved or changed | The model's NPR settings record, in that scene's set. A run of changes is one undo step, as the look's is |

### How It Works, and Why

- **No engine code here, and no change to the engine.** `...HostEditing__.mjs` runs after the engine's own Init in the
  engine's own page and calls only what it exports: `SetFold`, `SetAssetDrawer`, `ToggleViewLock`, `OnAssetsChanged`,
  `AssetsChanged`, `PickAt`, `Select`, `Give`, `SettingsObject`, `ApplySettingsJson`, `SceneEdit__Wire({ History })`, and
  `Ui.Status` as a stand-in. Every control, label, range and parameter mapping is the repo's: a point type or a slider
  added there shows here at the next Reload Remote Plugin Files. The stylesheet only lays out and hides.
- **New files, and why:** the points needed none of their own. Two were needed for the model: `...HostEditing__.mjs`
  (`HostViewport` would have passed 800 lines) and `...ModelEdits__.rb`.
- **The model is the truth; the engine's draw is the preview.** The drawer's every change reaches `OnAssetsChanged`,
  whoever made it. The page compares the engine's lists with what the model last held and sends what moved as one batch
  (Add, Pose, Remove, PlopMaterials, Paint). The next scene from the model replaces the preview. Each scene says which
  batches it shows (`EditsThrough`), so one still on its way is never lost from the drawing, and a scene with nothing new
  in it is not drawn again.
- **A new plop takes its proxy's persistent id at once.** Its strokes are seeded by its Uid, so the page renames it as soon
  as Ruby answers: the rebuild then is the one that lasts, and the scene that follows changes nothing.
- **A material given to the model's geometry is painted, and the assignment dropped.** The engine reads the paint from the
  GLB (v0.8.19), so the assignment is only a preview until the scene arrives. A paint's ray is the engine's own pick, which
  starts just short of the surface, or from a menu a point on what it was given to. Rays pass through proxies, edges, and
  what the GLB builder leaves out.
- **The cache grew by the asset library's `.webp`** (the drawer's card pictures; AURA's pin already has them). The cache's
  state now records its patterns, and a window tops up a cache with other patterns once, by itself.
- **The server, the record and NPR Export:** the server needed nothing. The record's new block is `points` (`sets` by
  scene persistent id or `working`, `sheet`, the engine's version), carried untouched by an older plugin. NPR Export draws
  each ticked scene with its own points, and the sheet's own come back after; the current view draws with the sheet's.
- **A proxy on the proxy tag is drawn even when the tag is hidden:** the tag is hidden scene by scene to keep proxies out of
  the whitecard pictures, not out of the drawing.

### Measured

- Ruby: 11 changed files compile under SketchUp 2027's Ruby 3.4.9; `su_lint.py` 0 errors, 0 warnings. `node --check` on the
  five host modules; the fetch script parses; the AppConfig parses. API names checked with `ruby_api_lookup`; in the live
  model (read only), a `raytest` path ends in its Face: `[Group, Group, Face]`.
- **The page, in headless Edge with real pointer events:** the plugin's own server on a test port, engine from the working
  tree, Thrower's real cache, Ruby stood in for by a recording stub. 36 steps of the second run, 0 errors; nothing in the
  console but the worker that is never served. All of these were checked in that run or the one before it, which stopped
  at a time limit once it had covered its own steps:
  - Collapsed: the sheet 1273 px wide in a 1500 px window, two small tabs. Open: the drawer's 28 cards with their pictures,
    no factory sections, the panel showing Art direction alone. Its width dragged from 300 to 370 px. Folded again: the
    points' layer hidden, the section closed, the sheet back to 1273 px.
  - A drag on the sheet left the camera's yaw as it was; L and P never reached the engine; Ctrl + Z asked for SketchUp's undo;
    the menu reads Undo in SketchUp and Redo in SketchUp.
  - A Focus point placed on the model: selected, kept under its set with all its values and the sheet. Sets swapped both ways
    with no save caused.
  - A card dropped: an Add with its ray, shape and pose. On the answer it took the proxy's Uid and height, and the model's next
    scene caused no rebuild. Turn sent a Pose 45 degrees on; Remove sent a Remove.
  - A swatch on Object and on Face: a Paint each, each with its ray. A scene showing that batch dropped the previews.
  - A failed paint's and a failed proxy's message came up as a warning; the proxy's asked for a Refresh.
  Looked at: collapsed, both open with a point on the sheet, the Materials tab, all as designed.
- **Not run by the build:** anything in SketchUp itself. Every Ruby path that changes a model (placing, moving, painting, the
  record's new block, the per-scene export) was compiled and linted, then left to Adam's test in SketchUp. Nor was NPR
  Export's per-scene drawing run in the page, or a status line held after a batch (added after those runs, checked by
  `node --check` only).

### Not Yet

- **Taking a painted material off** from the viewport: the assignment has gone once the paint is in the model, so its Take
  Off does nothing there. Undo in SketchUp, or paint another.
- **A move of a proxy inside an open group** follows the coordinate rule but has not been measured.
- **Reusing a set of points across scenes** is by the engine's Ctrl + C and Ctrl + V, one point at a time.
- **A point's anchored object** is held by the scene file's Id, which is per PC: on the other PC, after edits there, a point
  may anchor to another object until it is placed again.
- **A scene's hidden tags** are still not applied to the drawing.

### Files

- New: `02__Src__AppModules/80__System__NprViewport/Na__PainterlyAssets__NprViewport__HostEditing__.mjs`,
  `.../Na__PainterlyAssets__NprViewport__ModelEdits__.rb`.
- Changed: HostViewport, HostExport, LiveSync, Windows, RemoteEngine, RemoteFetch; `85` AssetProxies; `87` Store, Settings;
  `88` Jobs; `70` Palette, Painter; AppCore Main; the AppConfig (0.4.0, the `.webp` pattern, `live.editSeconds`,
  `assets.proxyTag`, `assets.landUpwardZ`); the NprViewport stylesheet.

### Testing

- [ ] **Restart SketchUp** (or Reload Plugin Data), then open the NPR Viewport: two small tabs, and the drawing as large as
      before. On the GitHub cache it downloads once more for the card pictures.
- [ ] Open each side, drag its edge wider, close it, close and reopen the window: folded, the width kept.
- [ ] Drag a tree onto a lawn, and a pot onto a raised patio: a proxy in the Outliner on the proxy tag, standing on the
      surface; one Ctrl + Z takes it out of both.
- [ ] Move it in SketchUp: the drawing follows. Turn and move it in the drawer: SketchUp follows. Try one nested in a moved,
      rotated group three deep, and one in a scaled group.
- [ ] Materials, Object: drop Brick on a wall in a group: that group's faces paint, its glass stays. Face: one face. A loose
      wall. A component with copies (the status says how many).
- [ ] A swatch on a placed plant: the drawing changes, the proxy does not; reopen the model and it stays.
- [ ] Place points with scene A selected, then select scene B: its own set. Back to A: A's. Save, reopen: both there.
- [ ] Ctrl + Z in the viewport undoes a run of point changes as one.
- [ ] NPR Export, two ticked scenes: each picture with its own points.

**Status:** TESTED BY ADAM IN SKETCHUP. Adam, 03-Nov-2026, after trying it: *"Works, commit it"*.

---

## Version 0.3.1 - 03-Nov-2026 - A Painted Part Keeps Its Id

### Asked For

Adam, 03-Nov-2026: *"When I paint materials in sketchUp the viewer isnt loading / reloading them, even if they are
materials from the library"*.

### What It Does

- **The fix for what was reported is the engine's**, not this plugin's: PainterlyNPR v0.8.27 (built as v0.8.19) reads a painted swatch's class
  from the node's name and draws that. The paint was already reaching the viewport: each paint exported, the GLB gained
  a `<tag>::MAT000E__Npr__<Class>` node, and the scene gave it an object of the file's rule class, which is why a cube
  painted Lavender stayed Brick. `Object__Material` stays the file's rule, a part's starting class. Nothing of the engine's
  rule is copied here, and ValeVision AURA gets the same reading.
- **A part painted away and back keeps its Id** (`Na__SceneFile`, `na_objects`). A bucket that empties goes Missing; before
  this its return took a new Id, so each repaint added another object and the same part came back with a different wash.
  Now the same file and node take their old Id again. An Id is still never given to another node.
- **A Stonework swatch in the Materials tab** (Adam: *"Add the swatch"*): `MAT228__Npr__Stonework` in the Materials SSOT's
  series (`Na__Common__DataLib__CoreSuEntityStandards`, 1.9.1), for PainterlyNPR v0.8.25's new class (built as v0.8.20). SketchUpName
  `MAT000E__Npr__Stonework`, BaseColor the class's Albedo, group Walls. The tab reads the SSOT from disk, so no code changed.

### Measured

- The palette in the running plugin: 28 swatches, 28 pictures, Stonework last under Walls.
- See PainterlyNPR's DEVLOG, v0.8.27 and v0.8.25.

### Not Yet

- **A closed group or component painted with SketchUp's Paint Bucket** paints the instance, not its faces. The GLB builder
  reads faces only, on purpose (its `Na__GlbEngine__ResolveEffectiveFaceMaterial`), so that paint exports as Default and
  the drawing does not change. Use the Materials tab with the group selected, or paint inside the open group. Adam to say
  whether a swatch on a whole group should count.
- **Inside an open group** a paint reaches the drawing when the group closes, as every edit does (`Na__GlbBridge`).
- **A material outside the library** keeps its node, but the engine has only its own classes, so the part keeps its
  file's class.

---

## Version 0.3.0 - 01-Nov-2026 - NPR Export, NPR Settings Kept in the Model and Reset to Defaults

### Asked For

Adam, 01-Nov-2026: *"In the SketchUp plugin, create a new button for exporting that opens up a new menu that's got all
of the export options you would expect. With the SketchUp plugin, make sure parameters and options for everything we've
got are correctly serialised to a model dictionary ... A good plugin to look at is my Point Cloud plugin for how this is
done, because that has a really robust system for this kind of thing. This is so we can have model-persistent styles,
but then we also will need a button to reset parameters back to the default from the GitHub library. This should also
serialise and cover things like the export settings, etc., though, because it would be really annoying having to keep
reconfiguring those, as well as all the various menu parameters"*.

### What It Does

| Where | What |
|---|---|
| Toolbar and menu: **NPR Export** | A window with every export setting: the current SketchUp view or ticked SketchUp scenes; PNG (prints true to size), JPEG (quality) or a true-size PDF; the resolution (127, 150, 200, 254, 300, 400, 600 dpi or any from 50 to 1200, with the pixel size on the engine's A3 sheet); the folder (beside the model, or one chosen); the file name from tokens (`{model}` `{view}` `{dpi}` `{date}` `{time}` `{seed}`); Add a Number or Replace; open the folder or each picture after; Export, Cancel and a report. Also the look saved as, and loaded from, the engine's settings `.json`, and PainterlyNPR's pen calibration sheet |
| NPR Parameters | **Reset to Defaults** (click twice): every parameter back to the GitHub engine's own starting values. A line saying whether the look is kept in this model (and its revision); **Restore** when this PC kept later settings than the model; an **Export** button |
| The model | Its NPR look (every parameter of NPR Parameters, its sliders and its menus) and NPR Export's settings, kept in the `.skp`: a model opened later, or on the other PC, looks and exports as it was left |

### How It Works, and Why

- **The record** (`87__System__ModelPersistence`), the Point Cloud Viewer's way: one JSON string in the model's own
  attribute dictionary `Na__PainterlyAssets__NprSettings` (key `json`; past 16,000 characters in parts `json__000`...
  with `chunks`), schema `Na__PainterlyAssets__NprSettings` 1, its own `storeId` (`npst_` and 16 hex: `Model#guid`
  changes on every save), `revision`, `updatedAt`, `updatedEpoch`, `pluginVersion`, and two blocks: `look` (the engine's
  settings object, the drawing's part: Seed, Sun, Style, Paper, Composition, as the engine serialises it, with the
  engine version and commit that made it) and `export`. Every control of NPR Parameters lands in those five keys (its 89
  sliders and its menus: pen widths, ink family, outline hand, leaf marks, cloud type, sheet), so a parameter added to
  PainterlyNPR is kept with nothing changed here. The camera stays SketchUp's; the art direction points and placed
  assets stay the viewport's and the model's.
- **Never clobbered:** nothing is read or written as a model opens (only when an NPR window opens or asks); unchanged
  data writes nothing; keys this version does not know, at the top or inside a block, are carried through every write; a
  record from a newer version is used but never rewritten, an unreadable one left exactly as it is, and the windows say
  why. The new keys are written before the old ones are removed, so the record reads whole at every moment.
- **Undo:** every write is one named step (`PainterlyNPR Assets: NPR Look`, `... NPR Export Settings`, `... Reset NPR
  Look`, `... Load NPR Look`, `... Reset NPR Export Settings`, `... Restore NPR Settings`). A change right after our own
  change of the same block, with nothing else done to the model in between, joins that step (a transparent operation),
  so a minute at the sliders is one Ctrl+Z; any other step ends the run. While an NPR window is open the model is
  watched: an Undo or Redo that moved the record is read back and handed to both NPR windows (the look returns in the
  drawing), and the live sync is told it need not check the geometry. Inside NPR Parameters the engine's own undo still
  steps through single changes.
- **The second copy:** after every write this PC keeps the record in
  `91__UserConfig__LocalOnly/Na__PainterlyAssets__ModelBackups/<storeId>.json` (a copy holding later changes than the
  one written over it is kept as `__superseded__`). When the model holds no record but this PC kept one from a model at
  the same path, or this PC's copy is later than the model's (closed without saving), NPR Parameters and NPR Export offer
  **Restore** (never automatic, one undo step).
- **From 0.2.0:** a model with no record still gets the look 0.2.0 kept for its project on this PC (read only); its
  first change puts the look in the model.
- **Reset to Defaults** asks the engine itself: its `DefaultState` (a fresh starting state from its own
  `Na__AppState__Config.json`, the GitHub commit in the cache) is put in its State for one synchronous moment so its own
  `SettingsObject` serialises it, every value is put back, then the defaults are applied with its `ApplySettingsJson`
  like any look. No default is copied into the plugin; Reload Remote Plugin Files brings the latest.
- **NPR Export** (`88__System__NprExport`, its own window, the Asset Library's look): every change is kept in the model.
  The pictures are drawn by **the engine's own still export** (`PainterlyNPR__Export__Png`: `dpi:300`, `pdf:300`,
  `calibration:pdf:300`) in the NPR Viewport's engine, with its scene and its look, so the viewport opens when it is not
  open and the job waits until it has the model. Each picture's camera is taken when Export is pressed (a snapshot of
  SketchUp's view, or each scene's own camera; a scene that keeps no camera uses the view's) and never by selecting a
  scene: SketchUp's view never moves. While a job runs the viewport holds still (no camera, no new scene), then follows
  SketchUp again.
- **The engine ends in a browser download, which SketchUp's browser cannot make:** for the one call the page catches
  the engine's `<a download>` click and keeps its blob and the engine's own file name
  (`...NprViewport__HostExport__.mjs`). A JPEG is made from the engine's PNG by the browser, its resolution written in the
  JFIF header. Each file goes to the plugin's server (`POST /__na/export` with the session's token, written whole into
  `90__AppCache__TempFilesCache/Na__PainterlyAssets__NprExport__Outbox`), and Ruby moves it to its name: Adam's
  `{model}__{view}__PainterlyNPR__{dpi}dpi__` by default, `__02` added when a name is taken (Replace writes over it), a
  name past SketchUp's 259 characters refused at Export with the reason. A chosen folder is kept relative to the model's
  folder when it is on the same drive, so it resolves on either PC; one not on this PC is said, never made.
- **The server is 1.1.0:** the export route; a refused request's body is read before the answer, so the page hears why;
  the port is its own (see below). A 1.0.0 server still running from before is restarted onto 1.1.0 the next time a
  window needs it.

### Verified Offline (01-Nov-2026)

- 43 Ruby files compile under SketchUp 2026's Ruby 3.2.2; `su_lint.py` 0 errors, 0 warnings, 0 info; `node --check` on the
  four host modules and the window's script; the server parses; the AppConfig parses; no CRLF, no dash punctuation in UI
  text, no stray non-ASCII.
- **The record** (58 checks): nothing written by a read; a look written whole as one named step; only the look's keys
  kept; a run of changes joined, ended by another step; Undo and Redo of a look step read back and handed on (the
  geometry not checked), of another step checked; Reset, Load and Restore steps of their own; unknown keys carried; a
  newer record used and never rewritten; unreadable, foreign and non-UTF-8 records left alone; a record in parts written
  and read back, shrunk back to one key, a missing part refused; a failed write aborted whole, a failed joined write
  committed and the record still whole; the export settings coerced over the defaults; the backup, its offer, Restore
  (and from a model at the same path), the superseded copy; the watch following a model change and letting go.
- **NPR Export** (66 checks): the folder (beside the model, relative, absent, unsaved), names and tokens, numbering and
  Replace, the sheet from the cached engine's own config (A3) and its pixels; a whole job (the viewport opened, the
  scene asked for once, the job sent with each camera in the engine's world, the viewport held, the picture moved from
  the outbox, the hold let go, the folder opened); scenes by persistent id or by name in the model's order, an
  orthographic plan, a scene without a camera; a file arriving at its name meanwhile; a foreign file refused; the pen
  calibration sheet under the engine's name; Cancel before and during; the viewport closing; both timeouts; an old
  server restarted; the window (its state, a change kept in the model, Choose Folder kept relative, Reset Export
  Settings, Save and Load a Look, a file that is not a look, the report).
- **The wiring** (42 checks, 28 before): as 0.2.0, with the look now in the model, two look changes one step, the same
  look writing nothing, our own writes starting no sync, Undo bringing the look back to both windows without a geometry
  check, an undone edit checked, Reset a step of its own, the export hold. **The processes** 18 checks (on a test port),
  **the server** 45 checks (the export route: the token, the name, the length, a 5 MB picture written whole, a PDF,
  replace, no outbox) and a 1.0.0 server holding a port: the 1.1.0 server takes another.
- 41 of 41 deliberate faults caught (29 new: a failed joined write aborted, a newer record written over, unknown keys
  dropped, parts never counted, old keys removed first, no run joined, a run never ended, an undone look unnoticed, the
  same look written again, every key kept, Reset joined, Restore never offered, the watch never letting go, names never
  numbered, a chosen folder kept whole, underscores not collapsed, the hold never let go, any outbox file taken, a scene
  without a camera, scenes in tick order, a late file written over, the length unchecked, Cancel never sent, a page
  change not kept, a loaded look keeping every key, the camera sent while held, our own writes syncing, an undone look
  checking the geometry, the look not kept in the model; and 0.2.0's 12).
- **In a browser, the real engine** (the desktop app's Chromium, PainterlyNPR 0.8.17 at 306332a from the GitHub cache,
  the staged server on a test port, NP03 as a project cache): the viewport drew NP03 (62 objects, 15 model files) and
  exported, through the new route, a 127 dpi PNG (2100 x 1485, the engine's pHYs of 127 dpi and its print-size comment),
  a 150 dpi JPEG of an orthographic front elevation from its own camera (2480 x 1754, JFIF 150 dpi) and a true-size PDF
  (an A3 page, 1190.55 x 841.89 pt), 6.6 s for the three; looked at, both pictures are the drawing, from the right
  cameras. Cancel stopped after the picture being drawn; a scene sent mid-export waited and loaded after; a wrong token
  was refused with the reason. NPR Parameters: Reset to Defaults armed on the first click, and on the second sent the
  engine's DefaultState (seed 20261029, Cartridge, painted area 70% and edge irregularity 10%, every pen, wash and sky
  value), its State objects kept, its 89 controls showing the defaults; the record line, Restore and Not Now. NPR
  Export: the page at its window's size, every control sending one settings message with an unknown key carried back.

### Found and Fixed on the Way

- **Two SketchUps shared port 8147.** On this PC both open SketchUp 2026s (SK02 AssetOptimisation and SK02 AscottGardens)
  each ran a 1.0.0 NPR server on 127.0.0.1:8147: Python's HTTP server sets `SO_REUSEADDR`, which on Windows lets a second
  socket bind a port already listened on, and then either server answers either SketchUp's windows. Harmless while both
  served the same files; fatal for exports (each server has its own token). 1.1.0 binds with `SO_EXCLUSIVEADDRUSE`, so
  a second SketchUp's server takes another port. While finding it, the 0.2.0 process suite started a third server on
  8147 for a few seconds; every test now uses its own port.
- A refused upload was answered before its body was read, and Windows reset the connection: the page saw a failed fetch,
  not the reason. Refused bodies (up to 64 MB) are now read first.
- The record's write removed the old keys before writing the new: a failure in between, inside a joined step (which is
  committed), could have left no record. New keys first now.
- The undo read-back called `model.valid?` unguarded.

### What Offline Cannot Prove

- **In SketchUp:** that a joined (transparent) operation merges into our previous step as documented, and how the Edit
  menu names the steps; the export window's native panels (Choose Folder, Save and Load a Look); the engine's export at
  300 and 600 dpi on this PC's graphics card inside SketchUp's browser (127 and 150 dpi were drawn in the desktop app's
  Chromium); the download caught inside SketchUp's browser (the same Chromium family).
- Whether one undo step a run of look changes is the right size for Adam.

### Provisional (for Adam to correct)

- The export defaults: a 300 dpi PNG in `PainterlyNPR__Exports` beside the model, `{model}__{view}__PainterlyNPR__{dpi}dpi__`,
  Add a Number, the folder opened after; JPEG quality 92; the resolution buttons; 300 s to get the viewport ready and 600 s
  a picture.
- A scene gives its camera only: its hidden tags and objects are not applied (the GLB cache is the whole model).
- Live on or off is not kept in the model (it is how you work, not how the model looks): the viewport's user config
  still decides whether it starts live.

### Files

- New: `02__Src__AppModules/87__System__ModelPersistence/` (Store, LocalBackup, Settings);
  `02__Src__AppModules/88__System__NprExport/` (Naming, Jobs, Window, and the window's `UiSystem__MainUiLogic__.js`);
  `Na__PainterlyAssets__NprExport__UiLayout__.html`; `80__System__NprViewport/Na__PainterlyAssets__NprViewport__HostExport__.mjs`;
  `03__Style__AppStylesheets/Na__PainterlyAssets__UiFeature__Styles__NprExport__.css`;
  `01__AppAssets__PainterlyAssets/Na__PainterlyAssets__Toolbar__NprExport__.svg` (PainterlyNPR's own Export section symbol
  from the vector library, in the toolbar's colour).
- Changed: the loader (NPR Export: command, menu, toolbar); AppCore Main (requires, `Na__PublicApi__OpenNprExport`); the
  AppConfig (`nprExport`, version 0.3.0); LiveSync, Windows, CameraSync (snapshots), LocalServer `.rb` and `.py`,
  HostParameters, HostViewport; the NprParameters and CoreUi Index stylesheets.

### Testing

- [ ] **Restart SketchUp** (the NPR Export button registers at start-up). With both SketchUps open, the second's NPR
      windows still open (its server takes another port).
- [ ] NPR Parameters: move a few sliders, save the model, close and reopen it (or open it on the other PC): the NPR
      Viewport shows the same look, and the line under the buttons says it is kept in this model.
- [ ] After a run of slider changes, Ctrl+Z in SketchUp: the look steps back (one step for the run) in both NPR windows.
- [ ] Reset to Defaults (two clicks): GitHub PainterlyNPR's starting look; Ctrl+Z puts yours back.
- [ ] NPR Export with its defaults: a 300 dpi PNG beside the model in `PainterlyNPR__Exports`, and the folder opens.
- [ ] Tick two scenes, JPEG, 150 dpi: two pictures, each from its scene's camera; SketchUp's view does not move.
- [ ] A PDF prints at A3 true size at 100%.
- [ ] Close and reopen the model: NPR Export's settings are as you left them.
- [ ] Save the Look As .json, change the look, Load a Look From .json: it comes back.

**Status:** IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP

---

## Version 0.2.0 - 01-Nov-2026 - NPR Viewport, NPR Parameters and Live NPR Updates

### Asked For

Adam, 01-Nov-2026: *"create a second window that creates a live preview window, and then a third window ... The asset
manager that opens in one window with one button. An NPR render window that shows a window with nothing else but just
the viewport in. A third button that opens a menu with all of the different parameters"*; *"Use a symbol that shows
real time or not ... We need a way to be able to toggle real-time rendering on or off, so the viewport doesn't just
continually update whilst you're making edits. It should be live by default when you open it"*; *"create a user config
folder and data file, and a user projects cache folder. The projects cache folder should cache assets as needed ...
Create an intelligent system for this, so every frame doesn't have to fetch literally everything and render
everything ... When you flip that back on, it will go cycle through and say, Hey, this asset's changed"*; *"another
module as well, which borrows all of the conversion logic that we added to ValeVision 3D Cloud Sync ... that same
process, but to a local cache folder"*. Then, mid-build: *"Call the modules required from the GitHub repo ... load all
of the modules and cache them, and create a "Reload Remote Plugin Files" button that reloads and recaches them. Do
not, under any circumstance, copy the core render engine code into the SketchUp plugin ... This SketchUp plugin is
effectively just a wrapper that calls all of that code from that repo"*.

### What It Does

| Toolbar button | What |
|---|---|
| Open Asset Library | As before |
| NPR Viewport | PainterlyNPR's pen and wash drawing of the model, nothing else in the window, looking from SketchUp's camera |
| NPR Parameters | Every parameter of PainterlyNPR's own panel (Paper and finish, Light, Pen, Wash, Sky, presets, seed, undo), moving the NPR Viewport's drawing; with Live, Refresh, Viewport and Reload Remote Plugin Files above it |
| Live NPR Updates | Pressed while live: the viewport follows SketchUp's camera and every change; off, it holds still and nothing in the model is watched. On by default when the viewport opens |

Menu (Extensions > Na PainterlyNPR Assets): the same three, and **Reload Remote Plugin Files** (also a button in NPR
Parameters).

### How It Works, and Why

- **The engine is PainterlyNPR's, from GitHub, never the plugin's.** `Na__PainterlyAssets__NprViewport__RemoteFetch__.py`
  (pythonw, git with this PC's own GitHub credentials, no token in the plugin) makes a shallow, blob-less, sparse clone of
  `github.com/Adam-Noble-01/Na__PainterlyNPR` `main` into `93__RemoteCache__CoreEngine/PainterlyNPR__<commit>`: only the
  files the engine reads when it runs (ValeVision AURA's pin selection: the modules, the stylesheets, the material
  recipes' `.json` and `.webp`, the asset library's `.json`) plus the app page and its icons. 362 files, 3.4 MB, 7 s.
  It downloads the first time a window opens and on Reload Remote Plugin Files (forced), into staging first, so a
  failed download never touches the cache in use; the previous commit's folder is kept until the next one. A local
  PainterlyNPR folder can stand in while the engine itself is being worked on (`engine.localOverrideFolder` in the
  viewport's user config, served as commit `local`).
- **The windows run the engine's own page.** `Na__PainterlyAssets__NprViewport__LocalServer__.py` (threaded Python on
  127.0.0.1:8147, the system's choice when that is taken) serves `PainterlyNPR__App__.html` from the cache with three
  lines added: an import map (`PainterlyNPR/` is the engine's modules, as AURA's), the window's stylesheet, and, after
  the app's own Init module (module scripts run in order), the window's host module. The engine boots exactly as it
  does in its own app; the hosts only call its exported functions (`SetBase`, `GlbBase`, `GlbRead`, `Reload`, `Bump`,
  `Request`, `SetProxy`, `SetControl`, `SettingsObject`, `ApplySettingsJson`, `LoadCatalogue`, `MakePlacement`). Nothing
  of the engine is copied: a control added to PainterlyNPR shows in NPR Parameters at the next Reload Remote Plugin
  Files. The service worker is never served (it would pin a stale engine in SketchUp's browser). The viewport is on
  127.0.0.1 and the parameters on localhost: two origins, two browser storages.
- **NPR Viewport** (`...HostViewport__.mjs`): only the sheet shows, sized to the window; it takes no mouse or keys (the
  drawing follows SketchUp). The scene is handed over as AURA's host hands its project's scene: the scene file's
  objects in Id order, each GLB read with the engine's `GlbRead`, each mesh file paired with its linework twin, then
  `SetBase(GlbBase(source))` and `Reload`. A GLB is fetched only when its version moved. SketchUp's camera becomes the
  engine's orbit camera (yaw, pitch, distance, target), the field of view (or ortho height) widened when SketchUp's
  view is wider than the engine's A3 sheet, so all of it shows.
- **NPR Parameters** (`...HostParameters__.mjs`): the engine's own panel under the plugin's header; Camera, Art direction
  and Export are hidden (they act on a drawing this window does not show). Its own engine is kept quiet (Proxy work
  mode, a fifth-size sheet). A slider's move goes to the viewport at once as that control (the engine's `SetControl`
  there, only its inputs bumped); after any change the look (seed, sun, style, paper, composition) goes too, when it
  moved, and Ruby keeps it with the project (`Na__PainterlyAssets__ProjectCache__Settings__.json`).
- **The project cache** (`92__UserProjects__ProjectCache/<title 12>__<8 hex of the path>`, short so every GLB path stays
  under SketchUp's 260): the GLBs, a manifest (each export unit's fingerprint, each file's SHA-256 and version), the
  scene file and the look. An index keeps the 12 most recently opened projects (never the one open); the GLB
  builder's logs keep their newest 3.
- **Only what changed is exported** (`85__System__ProjectCache`): the GLB bridge is Cloud Sync's route (its
  GlbExportBridge): TrueVision's GLB builder, whitecard plus MAT000E__ exempt materials, quiet, the builder's own mode
  put back after. The plan is the builder's own (its tag groups, storeys and file names). Each unit (a tag group, or a
  storey's element) is fingerprinted: every face's corners, tag, materials and hidden flag, every edge's ends and
  flags, every instance's transformation, tag, material, name and persistent id, to the last nested definition.
  Definitions are digested once and kept between syncs; a change forgets only what it can have touched (the open
  context's definitions, or the selection's contents, and every definition holding them); undo, redo, a material
  edit, Refresh and live turned back on forget them all (the "cycle through"). Only stale units are exported: for that
  one export the builder's per-file selection (`Na__ExportSelection__DeselectedSet`) answers "deselected" for every
  other file, then is put back (the model's own selection is never read or written). A file rewritten byte for byte
  keeps its version, so the viewport never fetches it again. A unit takes its new fingerprint only when every one of its
  files was written. Linetype linework is not exported (no mesh twin: the engine never reads it).
- **The scene file** (`...SceneFile__.rb`) is the local twin of AURA's scene import (scene API 1.2.0): a file's part,
  use and role from its name by AURA's rule table (in the AppConfig, plus rows for the builder's storey files); objects
  from mesh nodes with Ids that never move (by file, node and which of its name's nodes it is, then by persistent id;
  a gone node stays as Missing); the focal footprint centred on the engine's origin, kept unless the building moves
  more than 25 m.
- **Placed library assets** (this plugin's proxies, at any depth) are drawn as PainterlyNPR draws them: the engine's
  own `MakePlacement` from the asset's record in the cached library, then SketchUp's position, turn and scale (Cloud
  Sync's pose: inches to glTF metres `(x, z, -y)`, a turn about +Z is the same angle about +Y), the seed from the
  proxy's persistent id. An asset not in the library on GitHub yet is named in the status line.
- **Live** (`...LiveSync__.rb`): observers only note and schedule; one sync runs once the model has been still for 1 s.
  Nothing is exported with a group open (the builder exports the model, and an open context reports world
  coordinates): the windows say so, and the change goes when the group closes. The camera is sent at most every 80 ms.
- **The user config data file**: `91__UserConfig__LocalOnly/Na__PainterlyAssets__UserConfig__NprViewport__.json`
  (`live.onWhenOpened`, `engine.localOverrideFolder`), written with its defaults the first time.
- **Icons** from the vector library: the ValeVision 3D render engine (NPR Viewport), AURA's panel parameters (NPR
  Parameters), and the read-aloud Play and Pause (live and paused; the toolbar shows Play, pressed while live).

### Verified Offline (01-Nov-2026)

- 37 Ruby files compile under SketchUp 2026's Ruby 3.2.2; `su_lint.py` 0 errors, 0 warnings; `node --check` on the three
  host modules; the two Python scripts parse; the AppConfig parses; no CRLF, no dash punctuation in UI text.
- **The cache** (65 checks, the harness doubles): the scene file on a real GLB builder export (NP03, 31 files, storey
  mode): parts, rules, twins, 62 objects, the focal placement, Ids kept across a re-build in a set that repeats node
  names; fingerprints kept until forgotten and forgetting climbing to every holder of a shared component; a sync against
  a stand-in GLB builder: everything the first time, nothing when nothing changed, only a moved roof's two files, a
  byte-identical re-export keeping its version, a half-written unit retried, a gone unit's files deleted and its object
  Missing, an open group waiting, logs trimmed, the index kept; proxy poses at the root and in a turned group; the
  camera in the engine's world (perspective, width-based FOV, ortho, a scene's own aspect).
- **The wiring** (28 checks): both windows on a stand-in HtmlDialog with a hand-run timer queue: the waiting page, the
  first download, the engine page's URL (viewport on 127.0.0.1, parameters on localhost), nothing sent before ready,
  live on by default, the first scene then the camera, a root commit exporting only its unit, three camera moves sending
  one message, an open group waiting then going when closed, a control and the whole look reaching the viewport, the
  look kept and given back to a reloaded viewport, live off watching nothing, Refresh exporting anyway, Reload Remote
  Plugin Files forcing the download and reloading both windows onto the new commit, closing the viewport turning live
  off.
- **The real processes** (16 checks): the download from GitHub through pythonw and git (a second request waits for the
  first), an up-to-date cache downloading nothing, no `.skp` or `.glb` in the cache, the override folder; the server
  spawned, found by its ready file, serving the engine page with the host added, reused, then stopped. The server alone
  (26 checks): MIME types, the injected page, immutable engine files, the service worker refused, `/api` 404, every
  traversal refused, the token-guarded shutdown, its exit when stopped.
- 12 of 12 deliberate faults caught (a proxy's y not negated, forgetting not climbing, a half-written unit taking its
  fingerprint, Ids by name only, the builder's selection never put back, the camera's y and z swapped, Cloud Sync's
  2 s written window, live off still watching, the parameters on 127.0.0.1, a commit noting nothing, a window never
  ready, the look never kept).
- **In a browser, the real engine** (Chromium in the desktop app's browser pane, PainterlyNPR 0.8.16 from the GitHub
  cache, the plugin's server, NP03's GLBs as a project cache): the viewport booted with only the sheet showing, drew
  NP03 in pen and wash (62 objects from 15 model files in 0.7 s) and a front elevation from an ortho camera; three
  proxies became the engine's own plops through MakePlacement (an oak, a bench and a potted standard; the oak and the
  bench plainly visible in the drawing), an unknown asset named, not drawn; a version moved on one roof file fetched
  only it and its twin. NPR Parameters showed the engine's panel (5 sections, 89 sliders) under the
  header; a wash slider reached the viewport as one control (its wash visibly deeper) and an ink change as the look
  (camera kept).

### Found and Fixed on the Way

- Cloud Sync's success test (a file written in the last 2 s) counts the previous sync's file when two exports run
  back to back, as live updates can: written now means its modified time moved during this export.
- A GLB repeats node names (a tag's buckets, a component placed twice), so matching by name alone renumbered the
  repeats on a re-build: the k-th node of a name keeps the k-th's Id, as the engine's GlbBase takes them.
- The engine's page scrolls below 1100 px wide (its panel drops under the sheet); both windows put their own layout back.

### What Offline Cannot Prove

- **That SketchUp's browser runs it**: an HtmlDialog on `http://127.0.0.1` with its Ruby callbacks, WebGL 2 with float
  targets in SketchUp 2026's Chromium 137, and its speed there. If WebGL 2 is missing, the engine's own card says so in
  the viewport.
- The real GLB builder under the bridge (the plan, the per-file selection, the material mode), in a real model and in
  a storey model; the observers' timing in a real session; the toolbar's pressed look.

### Provisional (config values for Adam to correct)

- The scene rules (AURA's provisional table plus the storey rows), the 25 m re-centring, `idleSeconds` 1.0,
  `cameraSeconds` 0.08, port 8147, `keepProjects` 12, whitecard material mode, the icons.
- Changes made inside an open group reach the drawing when the group is closed.

### Files

- New: `02__Src__AppModules/80__System__NprViewport/` (UserConfig, RemoteEngine, LocalServer `.rb` and `.py`,
  RemoteFetch `.py`, CameraSync, LiveSync, Windows, HostShared, HostViewport, HostParameters `.mjs`, Waiting `.html`);
  `02__Src__AppModules/85__System__ProjectCache/` (Store, SceneFile, Fingerprint, GlbBridge, AssetProxies, Sync);
  `03__Style__AppStylesheets/Na__PainterlyAssets__UiFeature__Styles__NprViewport__.css`, `...__NprParameters__.css`;
  `01__AppAssets__PainterlyAssets/Na__PainterlyAssets__Toolbar__Npr{Viewport,Parameters,LiveOn,LiveOff}__.svg`.
- Changed: `Na__PainterlyNPR__AssetLibrary__Loader__.rb` (commands, menu, toolbar), AppCore Main (paths, requires,
  public API), PluginReloader, the AppConfig (`nprViewport`, version 0.2.0), the Plugins repo's `.gitignore`
  (`92__UserProjects__ProjectCache`, `93__RemoteCache__CoreEngine`).

### Testing

- [x] **Restart SketchUp** (new toolbar buttons and menu items register at start-up), with a model on the standard tags
      (or a storey model).
- [ ] NPR Viewport: the window says it is downloading PainterlyNPR (the first time only), then shows the model in pen and
      wash from SketchUp's camera; orbit in SketchUp and the drawing follows (a quick preview, then the pen and wash).
- [ ] Move or paint a group: about a second later only its part redraws (the NPR Parameters status line names it).
      Edit inside a group: the change shows when you close it.
- [ ] Live NPR Updates off (the toolbar button or the Live button): the drawing holds still; edit; turn it on again: the
      edit appears. Refresh does the same without turning live on.
- [ ] NPR Parameters: Wash, Pen, Paper and Sky sliders move the viewport's drawing; close and reopen the viewport: the
      look is kept for this model.
- [ ] Place a library tree with the Asset Library: it appears as PainterlyNPR's tree.
- [ ] Reload Remote Plugin Files: both windows reload onto GitHub's latest PainterlyNPR.

### Verified in SketchUp (01-Nov-2026)

- Adam, after restarting SketchUp 2026 with 0.2.0: *"Restarted, it works"*.
- What the first run left on disk, read afterwards: PainterlyNPR 0.8.16 (main at b9e0363) downloaded inside SketchUp
  (362 files, the cache's state file); the server on 127.0.0.1:8147 for SketchUp's process; one project cache
  (`SK02__Modeli__a9b81724`) with the real GLB builder's export through the bridge (2 units, 4 files, the builder's log,
  the scene file, manifest revision 1); a look saved from NPR Parameters (the project's settings file); the viewport's
  user config written with its defaults. So the HtmlDialog callbacks on an `http://127.0.0.1` page, the engine's ES
  modules and WebGL in SketchUp 2026's browser, and the bridge's partial export all ran.
- Not reported one by one yet: the camera following an orbit, live re-exports after an edit (every file is still at
  version 1), Refresh, Live off and on, a placed library tree, Reload Remote Plugin Files.

**Status:** VERIFIED IN SKETCHUP 2026 BY ADAM (the first open; the rest of the checklist not yet reported)

---

## Version 0.1.3 - 30-Oct-2026 - Materials Tab: NPR Swatches Painted Onto Faces

### Asked For

Adam: "The sketchup plugin needs updating with swatches for materrials so you can paint faces ort objkects in sketchup
for downstresam recognition". Host: this plugin. Materials: "Build a new section in the SSOT materials, especially for
NPR materials for this render engine ... it deserves exemptions". Swatches: "Literally all of the materials for the NPR
system that we have". Objects: paint the faces inside and keep glass.

### What Changed

- **Materials SSOT 1.9.0** (`Na__Common__DataLib__CoreSuEntityStandards`): new `MAT200__PainterlyNprSeries__`, one entry
  per class in PainterlyNPR's material library register (27; the sky is not a material). Key `MAT2` + class Id
  (`MAT202__Npr__Brick`), SketchUpName `MAT000E__Npr__<ClassKey>` (exempt: exported in every mode with its own colour,
  the class in the GLB node name `<tag>::<material>`), BaseColor the class Albedo, Glass at opacity 0.30 (provisional),
  plus NprClassKey, NprClassId, NprClassLabel, NprGroup. Meta `nprSeriesNote` explains the series.
- **Materials tab** (`70__System__Materials`): the swatches in the register's groups with their RND pictures. A click:
  selected faces take it; a selected group or component takes it on every face inside at every depth, glass kept
  (named like glass or under 0.95 opaque, PainterlyNPR's own rule); nothing selected arms SketchUp's Paint Bucket.
  Opaque paints the front and clears the back, see-through paints both (Paint Deep Nested Faces' rule). Locked objects
  and PainterlyNPR assets (AssetId stamp) are left alone; shared components change on every copy and the status says so.
  The material is stamped in `Na__PainterlyAssets__Material` (MaterialClass, Label, Swatch), as proxies are.
- Why faces: TrueVision's GLB builder reads only a face's own material; a painted group exports as Default.
- AppConfig `materials` section; `plugin.version` 0.1.3.

### Verified

- 24 Ruby files compile; `su_lint.py` 0 errors, 0 warnings; `node --check` on the tab script; the AppConfig and SSOT parse.
- The palette on SketchUp 2026's Ruby against the real SSOT and register: 27 swatches in 6 groups, 27 pictures; the
  glass test passes MAT000E__Npr__Glass, MAT101 glass and a 30% material, refuses "Glasshouse" and WindowPaint.
- Adam, 30-Oct-2026, in SketchUp: "It works great."

### Not Yet

- PainterlyNPR v0.8.16 recognises only Glass by these names (WindowPaint and Joinery by the Windows/Doors tags). For the
  other classes it needs one rule: a material `MAT000E__Npr__<ClassKey>` is that class.
- Noble 3D Tools' "Load All Noble Architecture Materials" now also loads the 27 NPR swatches.

### Files

- `02__Src__AppModules/70__System__Materials/` Palette, Painter, UiSystem MainUiLogic (new)
- `03__Style__AppStylesheets/Na__PainterlyAssets__UiFeature__Styles__Materials__.css` (new), CoreUi Index (import)
- AppCore Main, ActionRouter (`paintMaterial`), StatePayload (`materials`); UiLayout (tab, panel, script); AppConfig
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json` (1.9.0)

---

## Version 0.1.2 - 30-Oct-2026 - Author Writes AutoRotate and AutoScale

### Asked For

PainterlyNPR v0.8.16 (at Adam's word, in the PainterlyNPR session) adds two optional booleans to a DAT's Placement:
`AutoRotate` (on: each plop turned by Facing; off: it lands as authored, as SketchUp inserts it) and `AutoScale` (on: its
size varies by ScaleJitter; off: always its own size). Left out, both count as on. That session asked for the Author form
to offer and write them, so a pot or a piece of furniture authored in SketchUp can be set to off.

### What Changed

- **Author form, Each Plop card:** Auto rotate and Auto scale checkboxes, beside Facing and Scale jitter. A collection or
  type fills them from its defaults row, as it fills Facing.
- **Defaults** (`author.defaults` in the AppConfig): on for the 07 planting rows (trees, conifers, shrubs, topiary,
  perennials, grasses), off for clipped hedges, planters and pots and every other collection, as the library's 28 DATs
  now say. The potted standards are 07 Topiary, whose row is on (box balls and cones): untick both for a potted one.
- **The plan** (`Na__Author__NormaliseForm`) reads a missing flag as on, as the engine does; **the DAT**
  (`Na__Dat__BuildNew`) writes them in the library's key order: Snap, AutoRotate, Facing, AutoScale, ScaleJitter,
  NewShapeEachPlop, MinSpacingM.
- `plugin.version` 0.1.2.

### Verified Offline

- 6 checks on SketchUp 2026's Ruby: off, `"false"` and left-out (on) read correctly; a built DAT carries off and on in
  the library's key order. The built DAT validates against PainterlyNPR's AssetData contract (0 errors).
- 22 Ruby files compile; `su_lint.py` 0 errors, 0 warnings; `node --check` on the Author page script; the AppConfig
  parses (25 defaults rows).

### Files

- `Na__PainterlyAssets__UiLayout__.html`, `02__Src__AppModules/40__System__Author/Na__PainterlyAssets__Author__UiSystem__MainUiLogic__.js`,
  `.../Na__PainterlyAssets__Author__Plan__.rb`, `02__Src__AppModules/10__System__Library/Na__PainterlyAssets__Library__DatRecord__.rb`,
  `02__Src__AppModules/02__AppData/Na__PainterlyAssets__AppData__AppConfig__Defaults__.json`.

### Testing

- [ ] Close the dialog, Reload Plugin Data, reopen it: Author shows Auto rotate and Auto scale; choosing 25 Planters And
      Pots unticks both, 07 Trees ticks both.
- [ ] Check, then Author a test pot with both off: its DAT's Placement says `"AutoRotate": false` and `"AutoScale": false`.

**Status:** IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027

---

## Version 0.1.1 - 30-Oct-2026 - Moved Into the Plugins Repo (SketchUp 2027), and a Definition Call for Sync Aura

### Asked For

*"This plugin was incorrectly created in SketchUp 2026. This is not the repo. The repo is SketchUp 2027. Migrate that
app from 2026 to version 2027"* (Adam, 30-Oct-2026). His call on the old copy: remove it.

### What Changed

- **Where it lives:** `%APPDATA%\SketchUp\SketchUp 2027\SketchUp\Plugins` (the Plugins repo,
  `github.com/Adam-Noble-01/Plugins`). The loader and all 39 files of `Na__PainterlyNPR__AssetLibrary__Modules__` were
  copied byte for byte (SHA-256 of every file compared), then the untracked 2026 copy was deleted, so a later pull into
  the 2026 clone does not trip over it. Nothing in the plugin named its SketchUp version or its Plugins folder, so no
  code changed for the move. The two local-only folders (`90__AppCache__TempFilesCache`, `91__UserConfig__LocalOnly`)
  came along and stay git-ignored.
- **`Na__PainterlyAssets.Na__PublicApi__DefinitionForAsset(model, asset_id, in_operation:)`** (AppCore Main): the
  definition Place in Model uses (in the model, else its SKP, else a proxy from its MOD), for other plugins.
  ValeVision Cloud Sync 0.5.2's Sync Aura tab places ValeVision AURA's plops with it. An asset filed since the last
  catalogue read is found by one rescan; anything else raises with a plain reason.
- `plugin.version` 0.1.1.

### Verified Offline

- All 23 Ruby files compile (`su_ruby.py syntax`, SketchUp 2026's Ruby 3.2.2; 2027's 3.4 DLL does not embed offline);
  `su_lint.py` 0 errors, 0 warnings (its checks include the Ruby 3.4 traps).

### What Offline Cannot Prove

- That it loads in SketchUp 2027 (Ruby 3.4.9): the first launch of 2027 with it is that test.
- The MCP: Adam's `sketchup` MCP server runs from the 2026 Plugins folder, so agents driving 2026 through it can no
  longer reach this plugin there.

### Files

- Moved: `Na__PainterlyNPR__AssetLibrary__Loader__.rb`, `Na__PainterlyNPR__AssetLibrary__Modules__\` (whole).
- Changed: `02__Src__AppModules/01__AppCore/Na__PainterlyAssets__AppCore__Main__.rb`,
  `02__Src__AppModules/02__AppData/Na__PainterlyAssets__AppData__AppConfig__Defaults__.json`.

### Testing

- [ ] Restart SketchUp 2027 (a new plugin: its menu and toolbar register at start-up), then Extensions > Na
      PainterlyNPR Assets > Open Asset Library: the catalogue lists the library.
- [ ] Place in Model from a card, as in 2026.
- [ ] With ValeVision Cloud Sync's Sync Aura, an AURA plop arrives as this plugin's component.

**Status:** IMPLEMENTED - NOT YET VERIFIED IN SKETCHUP 2027

---

## Version 0.1.0 - 30-Oct-2026 - The SketchUp Catalogue and Authoring Tool

### Asked For

*"After that we will build a sketchup side catalogue and authoring tool for adding new assets to the library and
validatring them etc."* (Adam, 30-Oct-2026, after asking for the asset library; built from the PainterlyNPR session's
brief: catalogue with search, filters and a Rendered / Proxy toggle as the app's Assets drawer has; place an asset,
its SKP or a proxy from its MOD; author a selected component with the next free Id; validate and index; SKPs written
by SketchUp and marked Present in the DAT.)

### What It Does

| Tab | What |
|---|---|
| Catalogue | Every asset as a card (its RND picture, or its PXY with the Proxy toggle), searched with the app's own rule (every word somewhere in the Id, names, type, collection, variant, description, botanical name, keywords), filtered by collection chips and type chips with counts. A card's details: its five files present or pending, how PainterlyNPR draws it, size, botanical name, keywords; Place in Model, Write SKP, Open Folder. Double-click a card to place it. Write Missing SKPs does every asset with a MOD and no SKP, after an in-dialog confirm |
| Author | The selected component (size, where its origin sits against the centre of its base, scale, copies); the form (collection, type, family, Name, Var; display name, description, keywords, season, botanical, status; generator, organic kind, material class, role; facing, scale jitter, min spacing, new shape each plop); Check (a dry run: the Id, the folder, the five file names, every path length, every error and warning); Author Asset |
| Validate | PainterlyNPR's `validate` then `index`, every error and warning on its own line with an ERR or WARN badge |
| Settings | The PainterlyNPR folder and how it was found, the Python used, this PC's overrides for both, Reload Plugin Data, the technical log |

### How It Works, and Why

- **It reads; PainterlyNPR decides.** The register is read, never written. Every Id comes from
  `PainterlyNPR__BuildUtil__AssetLibrary__.py next CC Type [--family FFF]` and every verdict from its `validate`, so
  one set of rules holds whoever writes an asset. Author asks for the Id once at Check and again just before writing,
  as another session may file an asset in between.
- **The catalogue scans the DATs, not the index**, the same reading the utility's index makes (an AssetId and a
  Folder, Retired hidden, a file's presence from the disk), so an asset filed a moment ago shows at once. A DAT whose
  Files.Folder disagrees with where it sits is listed as a problem, never followed.
- **JSON in Python's own form.** Ruby's `JSON.pretty_generate` opens an empty object over two lines, so 8 of the 26
  seeded DATs came back different (measured on SketchUp 2026's Ruby). `Na__SafeFileWriter.Na__Json__Python`
  reproduces `json.dumps(indent=4, ensure_ascii=False)`: all 26 DATs and the index round-trip byte for byte, so a DAT
  this plugin touches diffs only where it changed. Writes go to `.part`, then a rename.
- **Placing uses SketchUp's own component placement tool** (`Model#place_component`), as the Components panel does:
  the copy lands in the active context where Adam clicks, inside open, moved, rotated and nested groups alike. The
  plugin computes no transformation of its own, so there is nothing to convert twice. Which definition: one already in
  the model under the asset's SKP name, else its SKP loaded, else a proxy built from its MOD, else a plain message
  (the factory has not rendered it).
- **A MOD becomes a component** (`Na__GlbReader`, `Na__ProxyBuilder`): the GLB's node tree with matrices or
  translation, rotation and scale, triangles welded by position, slivers left out, coplanar triangles merged, edges
  softened under 45 degrees for organic assets (a Kind in the recipe) and 25 for objects. Axes: library (x, y, z)
  metres, +Y up, front +Z becomes SketchUp (x, -z, y) / 0.0254, a rotation (never a reflection), so the asset's front
  faces SketchUp's front (-green) and its origin is the centre of its base. A mirroring node has its winding
  reversed. Materials are `NPR__<MaterialClass>` (a client model's own Timber is never taken over), coloured from the
  GLB's linear baseColorFactor back in sRGB (the bench's Timber is 170, 155, 135), with the class in an attribute.
  Several materials become part groups named by the factory's labels (a tree: Bark, Tree canopy).
- **Author is one operation with file rollback.** Group to component, re-seat, rename, marks: one undo step
  ("PainterlyNPR Assets: Author NPR_75_0001"). Everything checkable is checked before it opens. A failure aborts it
  and removes the files and folder that run wrote, so the asset exists whole or not at all.
- **The re-seat keeps every copy in place in every context.** The definition's entities move by the base centre read
  from its local bounds; every instance then takes `T * translation(centre)`: a right-multiplication in the
  definition's own space, right for a copy in the open context (whose transformation reads and writes as world) and
  for one inside a closed component alike. No edit_transform, no inverse. A definition that is itself open is
  refused: its entities would report world.
- **An authored asset is a Package.** `Painterly.Source` is Package (the slot the register keeps for SketchUp-authored
  geometry), with the chosen generator as the stand-in PainterlyNPR draws until it can draw a Package from its own
  geometry. Factory starts Pending; the factory renders MOD, PXY and RND and fills in Geometry and Factory.
- **The component is named exactly like its SKP file** (`NPR_75_0001__SKP__Ornament__Urns__StoneUrn__Var-01__`), the
  convention of Adam's component library: the same name in every model it is placed into.
- **Python runs isolated and out of sight.** An absolute python.exe found on disk (never the Store stub), run as
  pythonw.exe beside it (no console window), `-I -X utf8`, a cleaned environment (SketchUp 2026's embedded Python
  exports PYTHONHOME / PYTHONPATH), output straight into a run log (never a pipe), polled by a 0.1 s timer so
  SketchUp never waits on it. One run at a time; a hung run is stopped after `timeoutSeconds`.
- **The page is a set_file page**, so the library's pictures load from their own file:/// URIs (as the Gallery's
  thumbnails do), versioned by their last render so a re-rendered picture shows, and the Noble logo comes from
  `Na__Common__PluginDependencies`.
- **Built in the SketchUp 2026 clone**, as the brief asked. The 2027 clone has none of it until it is committed and
  pulled there; the code runs on both (Ruby 3.2 and 3.4: no `it`, no moved stdlib gems).

### Provisional (config values for Adam to correct)

- The Author defaults for collections that hold no asset yet (05, 15, 20, 30, 35, 40, 45, 50, 55, 60, 65, 75): the
  nearest stand-in generator, a material class and a role, guessed. The 07, 10 and 25 rows are the seeded assets'
  own recipes.
- Soften angles 45 (organic) and 25 (objects), the `NPR__` material prefix, the toolbar icon (a plain line tree and
  crate in #172b3a).

### Verified Offline (30-Oct-2026)

- 23 Ruby files compile under SketchUp 2026's Ruby 3.2.2; `su_lint` 0 errors, 0 warnings; 6 JS files pass
  `node --check`; the config parses; every one of the 25 Author default rows uses a generator, material class, role,
  facing, season and kind PainterlyNPR's validator accepts.
- Suite A, the real library read-only (59 checks): all 26 DATs and the index written back byte for byte; Python's
  float and escape forms; the axes and the bench's Bounds (Min, Max, Size, RadiusM 0.627 as its DAT); the bench and
  oak MODs read (72 triangles; Bark and Tree canopy); a synthetic GLB (a node turned 90 degrees and moved, a mirrored
  copy, an interleaved buffer, uint16 indices, a required extension refused); the catalogue (26 assets, 17
  collections, counts, every picture a file URI); the Author lists (11 generators, 28 material classes); the utility
  (`next` gives NPR_07_0051, NPR_07_0022 in the oak family, NPR_25_0011; `validate` 26 assets, 0 errors, 0 warnings;
  an async run, a run refused while busy, a chain in order).
- Suite B, a sandbox copy of the library (37 checks): the bench built from its MOD (36 faces from 72 triangles,
  NPR__Timber both sides, base centre at the origin, its backrest at +green so its front faces -green); placing from
  inside an open, moved and rotated group (SketchUp's tool given the definition, no operation of ours); the reeds
  softened as a mass, the bench's arrises kept; Write SKP (file written, the DAT's SKP Present, nothing else in the
  DAT changed, a second write refused, the sandbox validator 26 assets, 0 errors, 0 warnings); a DAT write that fails
  takes the SKP out again; inside a caller's operation no operation of its own.
- Suite C, the sandbox (50 checks): a component three deep in moved and rotated open groups, with copies at the root
  and inside a scaled group: its size and origin offset read, the plan (NPR_75_0001, the stem, folder and file names,
  path lengths, warnings), bad forms refused on every count, Author (SKP and DAT, one operation, the component named
  like its file, origin at the base centre with every copy where it was, the DAT in Python's form), PainterlyNPR's
  validator 27 assets, 0 errors, 0 warnings; a failed save leaves no folder and the model as it was; a group authored
  as a component (28 assets, 0 errors); undo takes each author back.
- 8 of 8 deliberate faults caught: the re-seat compensated in the wrong space (caught only by the rotated copy in the
  open context: a translation-only copy hid it), a double conversion through edit_transform, the front flipped,
  empty objects over two lines, a mirrored node keeping its winding, coplanar triangles never merged, an SKP kept
  after a failed DAT write, files left after a failed author.
- The page rendered headless in Chrome 156 with the real payloads: no script error; 26 cards with their pictures, the
  oak's details, search, chips, the Proxy toggle, the Author lists, a plan, the validation report.

### Verified Live (30-Oct-2026, at Adam's word: "Yes, run them")

Run through the Na SketchUp MCP bridge in a throwaway Untitled model; nothing of Adam's was opened.

- **Loads.** SketchUp 2026 (26.2.243, Ruby 3.2.2) loaded it at startup: `[+] Na PainterlyNPR Assets loaded
  successfully`, version 0.1.0. SketchUp 2027 (27.0.267, Ruby 3.4.9) loaded it too, from the 2026 folder, for that
  session only.
- **Catalogue, with pictures.** 26 assets, no problems, 26 with both pictures. In the dialog (2026: Chromium 137;
  2027: Chromium 149): 26 cards, 26 pictures decoded, 0 broken; chips All 26, Vegetation 23, Boundaries 1, Garden
  furniture 2; search "lav" leaves 2; Proxy shows all 26 proxy pictures; the oak's details with its 512 px picture;
  the Noble logo; the Author lists filled (17 collections, 11 generators).
- **Place in a moved and rotated group.** The bench, built from its MOD (36 faces, NPR__Timber), put into an open
  group three deep (G1 moved 5 m, 3 m and turned 30 degrees, G2 turned -50, G3 tipped 10 degrees about red) as
  SketchUp's tool puts a copy (at the click point, aligned with the open context's axes): on the point to 0.0 mm,
  aligned with G3 to 0 degrees, a pure translation in G3's own space, its base on the face to 0.0 mm, its backrest
  on G3's +green side (front to -green). Unchanged once the groups were closed; moved exactly 1000 mm with G1. Place
  hands the definition to SketchUp's own `ComponentTool`; Adam's own placements through the dialog in the same
  session (two ash trees, the planter, the ornamental grass, the catmint) landed where he clicked.
- **An organic proxy.** The oak built in 0.38 s: Bark (14 faces) and Tree canopy (5593 faces, 8233 of 8554 edges
  soft and smooth), 9002 mm high, its base 6 mm below the ground as its DAT's Bounds say.
- **Author into the real library**, from inside the open, tipped group, a component with copies in that group, in a
  closed scaled group and at the root: NPR_75_0001 from the build utility; its folder with the DAT and the SKP; the
  component renamed `NPR_75_0001__SKP__Ornament__Urns__TestUrn__Var-01__` and marked; its origin moved to the
  centre of its base (bounds -150 to 150 mm, 0 to 600 mm) with all three copies unmoved; PainterlyNPR's validator
  27 assets, 0 errors, 0 warnings and the index written (0.33 s, pythonw.exe). The name stored inside the SKP
  (read headlessly through the C API) is its file stem; saved by 26.2.243.
- **Removed again.** One Undo restored the name, the mark and the origin with every copy in place; the asset's
  folder deleted; Validate: 26 assets, 0 errors, 0 warnings, the index rewritten byte for byte (git shows nothing
  changed in 12__Data__AssetLibrary).
- **Write Missing SKPs on the real library**, at Adam's word (*"Yes, write them"*): all 26 seeded assets' SKPs
  written in 2.8 s, one operation (20 proxies built from their MODs, 6 saved from proxies already in the model, each
  checked to hold only the builder's parts and NPR__ materials); every stored component name equal to its file stem
  (C API, headless); each DAT changed in exactly two lines (Files.SKP Status Present, its Note), in PainterlyNPR's
  own JSON form; Validate 26 assets, 0 errors, 0 warnings; the index rewritten. Uncommitted in the Na__PainterlyNPR
  repo (26 DATs, the index, 26 new SKP files). The largest SKP is the oak's, 558 KB.

### Not Yet Exercised Live

- Place loading an asset from its SKP (every asset was already in the test model by then, so Place reused it).
- The Settings panels (Choose Folder, Choose python.exe) and Reload Plugin Data from the dialog.
- A reserved name after an aborted author (the plan refuses before writing; reported in plain words if it happens).

### Files

- `Plugins\Na__PainterlyNPR__AssetLibrary__Loader__.rb`
- `Na__PainterlyNPR__AssetLibrary__Modules__\`
  - `Na__PainterlyAssets__UiLayout__.html`, `01__AppAssets__PainterlyAssets\Na__PainterlyAssets__Brand__ToolbarIcon__.svg`
  - `02__Src__AppModules\01__AppCore\` Main, DialogManager, ActionRouter, StatePayload, PluginReloader (`.rb`); UiSystem BridgeBase, MainShell (`.js`)
  - `02__Src__AppModules\02__AppData\` AppConfig Defaults (`.json`), ConfigLoader, UserConfigStore
  - `02__Src__AppModules\03__AppUtils\` DebugTools, SafeFileWriter, Units, PathResolver
  - `02__Src__AppModules\10__System__Library\` Register, Catalogue, DatRecord, BuildUtil
  - `02__Src__AppModules\20__System__Catalogue\` Catalogue UiSystem MainUiLogic (`.js`)
  - `02__Src__AppModules\30__System__Place\` GlbReader, ProxyBuilder, Placement
  - `02__Src__AppModules\40__System__Author\` Selection, Plan, Commit; Author UiSystem MainUiLogic (`.js`)
  - `02__Src__AppModules\50__System__Validate\` Runner; Validate UiSystem MainUiLogic (`.js`)
  - `02__Src__AppModules\60__System__Settings\` Settings UiSystem MainUiLogic (`.js`)
  - `03__Style__AppStylesheets\` CoreUi Index, UiFeature Shell, Catalogue, Author (`.css`)
  - `85__Docs__AppDocumentation\Na__PainterlyAssets__DEVLOG__.md`
- Written at run time, git-ignored: `91__UserConfig__LocalOnly\` (this PC's overrides), `90__AppCache__TempFilesCache\`
  (the last Python run's log).

### Testing Notes

- [ ] Restart SketchUp 2026 (a new plugin: its menu and toolbar appear only after a restart). Extensions > Na
      PainterlyNPR Assets > Open Asset Library.
- [ ] Catalogue: 26 cards with pictures; Proxy shows the proxies; search "lav" leaves the two lavenders; Garden
      furniture shows the bench and the planter, with type chips; click the oak for its details.
- [ ] In a new, empty model: draw a box, group it, move it and rotate it about blue, open it. Place the garden bench
      (built from its MOD) and click on the box's top: it lands inside the group, its base on the face, aligned with
      the group's axes, its backrest on the group's +green side (its front faces -green, as in the Front view).
      Repeat three groups deep and inside a scaled group.
- [ ] Place the oak: two parts, Bark and Tree canopy, the canopy soft and smooth.
- [ ] Author: draw a small component off its base centre, select it, Author tab, Use Selection, choose 75 Ornament,
      Urns, Name TestUrn, Check (NPR_75_0001), Author Asset. The component is renamed
      NPR_75_0001__SKP__Ornament__Urns__TestUrn__Var-01__, its origin at the centre of its base, and Validate shows
      27 assets, 0 errors, 0 warnings. Then remove the test asset: Undo once in the model, delete its folder
      `12__Data__AssetLibrary\75__Ornament\NPR_75_0001__Urns__TestUrn__Var-01__`, and Validate again (26 assets, the
      index rewritten).
- [ ] Settings: the library folder found in the default places; Python found, windowless; Choose Folder and Use the
      Default; Reload Plugin Data reopens the window.
- [ ] Write SKP only when the library should gain SKPs: it writes into the PainterlyNPR repo (each SKP and its DAT).

**Status: VERIFIED IN SKETCHUP 2026 (load, catalogue, place, author, validate, remove, Write Missing SKPs;
30-Oct-2026). Placing from an SKP and the Settings panels not yet exercised live.**
