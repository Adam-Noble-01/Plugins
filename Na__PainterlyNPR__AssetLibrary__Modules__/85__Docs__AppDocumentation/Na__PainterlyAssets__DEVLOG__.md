# Na PainterlyNPR Assets - DEVLOG

The SketchUp side of PainterlyNPR's asset library (`Na__PainterlyNPR\12__Data__AssetLibrary`): a catalogue of every
asset with its pictures, placing an asset in the model, authoring a selected component as a new asset, and
PainterlyNPR's own validator in the dialog. Newest entry first.

Module `Na__PainterlyAssets`, files `Na__PainterlyAssets__*`, loader `Na__PainterlyNPR__AssetLibrary__Loader__.rb`,
menu Extensions > Na PainterlyNPR Assets.

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
