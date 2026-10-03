# Na Point Cloud Viewer - ARCHITECTURE

Status: **v0.6.0: native image renderer, LAS import, the clip box with clip scenes, the
Transform tab (move gimbal with a settable gimbal point, rotate protractor, lock, typed values,
JSON export) and model persistence (LAS link + local backup, explicit Reload) are built;
everything marked _Designed_ is not yet code.** Written 03-Oct-2026. Keep this file true: when a design
decision changes, change it here and say why in the DEVLOG.

**The decisive finding (M1):** SketchUp's View API costs ~2.3 us per drawn point (100k points =
3 fps). So points are never handed to SketchUp. The C++ engine rasterises them into an image and
SketchUp draws one textured quad (sections 7 and 8).

---

## 1. What the product is (and is not)

A **locked visual reference**: a coloured LAS point cloud drawn in the SketchUp viewport while
the user models with ordinary SketchUp tools. Point budget, point size, opacity, RGB / black,
clip box, saved clip scenes, safe positioning, lock.

It is **not** SketchUp geometry. No vertices, construction points, groups, edges or faces are
created for points. Points are not pickable, not snappable, not inferred, not exported. Explicitly
out of scope: snapping, picking, measuring to points, meshing, plane/wall detection,
registration/ICP, any scaling, editing/deleting/recolouring points, any format but `.las`.

---

## 2. Data flow

```
 .las (never modified)
   |  LASzip (vendored 3.5.0) - native, worker thread                      [Designed: M2]
   v
 Import pass: header -> point records -> octree build -> palette -> .napc.tmp -> verify -> .napc
   |
   v
 .napc cache (90__AppCache__PointCloudCache/<cacheId>/cloud.napc, per PC)
   |  open + validate (fingerprint, version, CRCs)                          [Designed: M2]
   v
 Native engine memory: selected octree nodes (never Ruby objects)          [Designed: M2/M3]
   |
   v
 Overlay#draw  (camera / settings / viewport changed?)                     [BUILT: M1b]
   |  no  -> draw the existing texture (one draw2d quad, ~0.5 ms)
   |  yes -> native render for this camera (multi-threaded splatting)
   |         -> stored PNG -> ImageRep#load_file -> View#load_texture
   v
 view.draw2d(GL_QUADS, viewport quad, texture:, uvs: Arrays)               [BUILT: M1b]
```

Until the M2b cache exists, an import goes straight from LASzip into engine memory and lasts
for the SketchUp session. The synthetic test cloud, the benchmark and the Ruby point primitives
(GL_POINTS, draw_points, line dots) did their job in M1 and were removed in v0.4.0.

---

## 3. Ruby / native boundary

| Ruby (main thread, SketchUp API) | C++ DLL (plain C ABI, no Ruby, no SketchUp API) |
|---|---|
| Plugin lifecycle, menus, toolbar, HtmlDialog | LAS parsing via LASzip [BUILT] |
| `Sketchup::Overlay` registration and `draw` | Scale/offset -> source coordinates -> local origin [BUILT] |
| Camera -> projection parameters (exact, verified) | Point store; projection; depth-tested splat raster [BUILT] |
| ImageRep#load_file, load_texture, draw2d quad | Opacity, monochrome, round splats; stored-PNG writer [BUILT] |
| Model attribute dictionaries, JSON config | Octree build, sampling, cache write/read, CRCs [M2] |
| Unit choice and display (Na__UnitContract) | Node selection: frustum, screen size, budget, clip rejection [M3] |
| Clip box, clip scenes, clip edit tool; transform/lock state [M4] | Per-point clip test, clip-aware budget [BUILT] |
| Async job ticks, progress polling | Import worker thread with atomic progress + cancel [BUILT] |

**Bridge = Fiddle, not a Ruby C extension** (`08__NativeEngine/...Bridge__.rb`). Ruby passes
packed binary Strings and a numeric parameter array; the DLL returns status codes and fills a
stats array. Because the DLL never sees a Ruby object it needs no Ruby headers or import library,
does not care which Ruby SketchUp ships, and can be **hot-swapped** (section 18). The C API is the
whole boundary: `01__CppSource/Na__PointCloudViewer__NativeEngine__Api__.h`, versioned by
`NAPC_ABI_VERSION`; the bridge refuses a DLL with an unknown ABI.

Rule: the C++ never calls Ruby or SketchUp, and copies every input buffer before returning.

Native layout follows the Batched Quadric Decimator precedent:
`02__Src__NativeEngine/{01__CppSource, 02__BuildSystem, 03__BuildScripts, 04__Bin__WindowsSketchUp2026}`;
the build tree lives in %TEMP%. Only the DLL is committed (like the decimator's `.so`).

---

## 4. LAS dependency

LASzip 3.5.0, commit `fa089bd8b2b4ca5631e199d257374c32a125f73f`, Apache-2.0, vendored unmodified
in `01__ExternalDependencies__VersionLocked/02__LASzip__Pinned__v3.5.0/` (see the manifest and
README there). It is a *copy*, not a submodule, so the repo alone reproduces the build. Only the
C API is used: `laszip_create`, `laszip_open_reader`, `laszip_get_header_pointer`,
`laszip_get_point_pointer`, `laszip_read_point`, `laszip_close_reader`, `laszip_destroy`,
`laszip_get_error`. LAZ decoding exists in the library but no LAZ import is offered.

Reported at import: LAS version, point data record format, point count (legacy + 1.4 extended),
X/Y/Z scale and offset, bounds, RGB present (formats 2, 3, 5, 7, 8, 10) and RGB bit depth,
coordinate-system VLRs present (GeoTIFF keys 34735 / OGC WKT 2112) with the WKT text when present.
No RGB -> neutral grey fallback (`render.noRgbFallbackRgb`), never a failure.

---

## 5. Units (core constraint)

Implemented in `03__AppUtils/Na__PointCloudViewer__AppUtils__UnitContract__.rb`.

- SketchUp stores **inches**. Everything handed to the SketchUp API is inches.
- LAS coordinates are in the **source unit**. LAS rarely states it reliably (a WKT may name a
  linear unit; nothing else does), so **the user chooses it at import**: metres, centimetres,
  millimetres, feet, inches. A WKT-declared unit is shown as a *suggestion* and the user still
  confirms. Nothing defaults silently.
- Conversion factors are exact (1 in = 25.4 mm): m 1000/25.4, cm 10/25.4, mm 1/25.4, ft 12, in 1.
  An unknown unit key raises - it never falls back.
- The model's display unit (Model Info) is shown for orientation only and never affects
  conversion.
- Every tab shows: **SketchUp model units** / **Point cloud source units** / **Internal SketchUp
  storage: Inches**.

Interfaces and their units:

| Interface | Units |
|---|---|
| LAS file | integer counts x scale + offset = source units |
| `.napc` positions | source units, f32 relative to node centre; node centres f64 relative to local origin |
| C++ -> Ruby Point3d | model inches (unit factor and user transform already applied) |
| Instance config translation | inches |
| UI | model display unit (lengths), metres for cloud size |

---

## 6. Coordinate transforms

```
LAS integer X,Y,Z (i32)
  -> source  = X * scale + offset                      (f64, source units, survey/world)
  -> local   = source - localOrigin                     (f64; cached as nodeCentre(f64) + f32 delta)
  -> inches  = local * k_unit                           (exact factor from the unit contract)
  -> model   = R * inches + t                           (USER RIGID TRANSFORM: rotation + translation)
```

Stored separately, never folded together:

1. **Source metadata** - LAS scale/offset/bounds/CRS VLRs (cache header + import report).
2. **Local origin** - default `(bbox centre x, bbox centre y, bbox min z)` in source units, so the
   cloud lands centred on the model origin with its lowest point on the ground plane. Huge survey
   coordinates never reach SketchUp; f32 deltas stay tiny.
3. **Unit conversion** - one unit key; the factor is looked up, never stored as a number.
4. **User rigid transform** - rotation `R` (orthonormal, det +1) and translation `t` (inches).

Moving or rotating changes only (4). The cache is never rewritten. Each edit composes a delta and
re-orthonormalises `R` (Gram-Schmidt) so repeated edits cannot drift into a scale or shear. A
stored `R` is re-orthonormalised when it is read, so it is never used as is; a degenerate one is
rejected and logged.
The survey relationship is always recoverable:
`source = localOrigin + R^-1 (model - t) / k_unit`.

---

## 7. Overlay rendering (BUILT)

`10__Viewport__OverlayRenderer/`:

- **Na__CloudOverlay** (`Sketchup::Overlay`, SU 2023+): one per model, id
  `noble_architecture.point_cloud_viewer.cloud`. Thin - delegates to module functions.
  Overlays draw in every tool, are not pickable, not inferred, not exported. "Show" in the dialog
  is the overlay's `enabled` flag - the same switch as SketchUp's Overlays panel; `start`/`stop`
  resync the dialog.
- **getExtents** returns the cloud's cached `Geom::BoundingBox` (no allocation) so near/far planes
  include the cloud.
- **Na__CloudSession**: per-model render settings, the loaded cloud, the clip box and scenes
  (read from the model), the image renderer's state, and the cached extents.
- **Na__RenderController.Na__Render__Draw**: draws the cloud image, then the clip box cage while
  it is being edited. A raising draw sets `session.fault` and stops drawing until a setting
  changes, so there is no exception per frame; the View tab shows the fault.
- **Na__ImageRenderer**: the only way points are drawn (see 7.2).

### 7.1 Why not draw points through SketchUp (M1 measurements)

| Primitive | Cost per drawn point | Size | Alpha | Hidden by faces | Verdict |
|---|---|---|---|---|---|
| `view.draw(GL_POINTS)` | ~2.3 us | no | no | no | 100k = 3 fps |
| `view.draw_points` | ~2.3 us | yes | no | no | same path, same cost |
| `GL_LINES` sub-pixel dots | ~0.13 us / vertex | - | - | - | renders nothing |

The View API has one colour per call, no retained GPU buffers and no binary input; the cost is
SketchUp's per-point path (batch count barely matters). These primitives were removed in v0.4.0.

### 7.2 The native image renderer (BUILT in M1b)

Per draw: build a camera key (eye, target, up, projection, viewport) and a settings key (size,
opacity, colour mode, budget, cloud, clip box). If both match the last render, draw the existing texture.
Otherwise the engine renders the cloud for this camera into a stored PNG,
`ImageRep#load_file` + `View#load_texture` turn it into a texture, and `view.draw2d(GL_QUADS)`
covers the viewport with it. Facts this relies on, all verified live:

- Projection from `camera.eye/xaxis/yaxis/zaxis`, `fov` (+ `fov_is_height?`, `aspect_ratio`) or
  `height` reproduces `View#screen_coords` with 0.0 px error, perspective and parallel.
- Texture alpha composites over the model, so empty pixels are transparent.
- **UVs must be Arrays** (`[u, v, 0]`); `Geom::Vector3d` UVs make SketchUp show the texture's
  average colour. Image row 0 = top = v 1.
- Stored PNG through `load_file` is the fastest alpha route (~16-28 ns/px); `set_data` 32-bit
  is ~54 ns/px.

Resolution policy (`render.nativeImage`): while the camera moves, render at `movingScale` (0.5);
0.25 s after it stops, one render at `fullScale` (1.0, logical pixels). Point size is scaled
with the image so dots keep their on-screen size.

Live quick benchmark, 1M points, 1909 x 1228 viewport (v0.2.0):

| Case | Frame | fps | Where the time goes |
|---|---|---|---|
| Model only (baseline) | 16.6 ms | 60 | - |
| Camera still (every modelling redraw) | 16.5 ms | 60 | draw 0.5 ms - texture reused |
| Orbiting, half resolution | 31.8 ms | 31.5 | native 11.2 (raster 6.2) + load_file 16.4 + texture 2.0 |
| Orbiting, forced full resolution | 72.6 ms | 13.8 | native 26.8 (raster 9.6, PNG 15.5) + load_file 39.3 + texture 4.1 |
| GL_POINTS, 100k (reference) | 313.6 ms | 3.2 | - |

Next optimisations, in order of payoff: `load_file` dominates orbiting (SketchUp-side, per
pixel), so crop the image to the screen rectangle the cloud covers and test a 256-colour palette
PNG (1 byte/px); parallel CRC/Adler for the settled frame; points stored in spatial order (M2
cache) for raster cache locality.

Not solvable from the overlay: points are drawn over SketchUp faces (no depth from the model).

---

## 8. Point budget and LOD (_Designed: M3_)

"Point budget" = approximate maximum points the engine rasterises per frame. Default 1,000,000
(`render.defaults.pointBudget`, set from the M1b numbers: 1M orbits at ~31 fps); presets Low /
Medium / High / Very High plus free value; hard ceiling 20 M (`render.limits`). The budget only
costs anything when the image is re-rendered, never on a still camera.

**Octree with subsampled internal nodes** (Potree-style):
- Build: each node keeps at most one point per cell of a 128^3 grid over its bounds; points not
  kept fall to the children. Node capacity ~20-60 k points. Selection of the kept point per cell
  is by a fixed hash of the point index, so the cache is byte-identical for the same input.
- Selection (C++, after the camera settles - debounced `onViewChanged`, never inside draw):
  frustum cull; clip-box cull; priority = projected node size (radius / distance x viewport
  scale); take nodes in priority order (ties by node id) until the budget is spent. Deterministic,
  so the cloud is stable while orbiting. Small hysteresis prevents popping at boundaries.
- Loading: nodes live in engine memory only (read from the `.napc` file, LRU-limited); Ruby
  never holds points. Selection runs inside the render call, so off-screen nodes are skipped
  before any point is projected.

Off-screen and clipped regions consume no budget by construction.

**Top of the scale (v0.6.0):** the slider and presets stop at the loaded cloud's own point count,
shown as an **All** preset (a budget above it cannot draw more). The plugin ceiling is
`render.limits.pointBudgetMax` = 50 M for larger scans. The display settings (budget, size,
opacity, colour) are remembered per user (`render.lastSettings` in the user config), so a new
session starts where the last one finished.

**Built now (v0.4.0), before the octree:** points are stored in a uniform random order, so the
first N points are an even sample. With the clip on, the engine finds the smallest prefix that
holds N points INSIDE the box (parallel count over 256 chunks, then one chunk scanned), caches it
per (box, placement, budget), and renders that prefix. A small box is therefore drawn as densely as
the whole cloud would be. JW02, box = middle ninth of the plan: 8.8M of 10.8M points walked to
find 1M inside; 19 ms once, then cached.

---

## 9. Cache format `.napc` v1 (_Designed: M2_)

Location: `90__AppCache__PointCloudCache/<cacheId>/cloud.napc` (git-ignored, per PC).
`cacheId` = first 16 hex chars of SHA-256(fingerprint). Little-endian throughout.

```
HEADER (256 bytes)
  0    char[8]   "NAPCLOUD"
  8    u32       formatVersion = 1          (mismatch -> "created by an older version, rebuild")
  12   u32       headerBytes = 256
  16   u64       pointCount
  24   u32       nodeCount
  28   u32       paletteCount (<= 256)
  32   u8[32]    sourceFingerprint (SHA-256, see below)
  64   u64       sourceFileBytes
  72   i64       sourceModifiedUnix
  80   f64[3]    lasScale
  104  f64[3]    lasOffset
  128  f64[3]    localOrigin (source units)
  152  f64[6]    bounds relative to localOrigin (min xyz, max xyz)
  200  u8        hasRgb
  201  u8        rgbSourceBits (8 | 16)
  202  u8, u8    lasVersionMajor, lasVersionMinor
  204  u8        pointDataFormat
  205  ...       reserved (zero)
  248  u32       headerCrc32 (bytes 0-247)
PALETTE          paletteCount x RGB8, padded to 8 bytes
NODE TABLE       nodeCount x 64 bytes:
                 u32 nodeKey (level + octant path), u8 level, u8 childMask, u16 pad,
                 f64[3] centre (rel. localOrigin), f32 halfSize, f32 spacing,
                 u64 blockOffset, u32 pointCount, u32 blockCrc32, u8[8] reserved
POINT BLOCKS     per node, 16-byte aligned, points sorted by palette index:
                 f32[3] x n  position relative to node centre (source units)
                 u8[3]  x n  RGB (8-bit; 16-bit LAS RGB downshifted after detection)
                 u8     x n  palette index
                 u32[2] x r  palette runs (index, count) - draw-batch boundaries without scanning
FOOTER           "NAPCEND\0", u32 nodeTableCrc32
```

- **Fingerprint** = SHA-256 over: file size, LAS header + VLR bytes, 64 evenly spaced 64 KiB
  samples of the point data, the last 64 KiB. Validating on model open reads ~4 MB, not the file.
- **Transactional write**: `cloud.napc.tmp` -> full read-back verify (header CRC, node table CRC,
  every block CRC) -> rename. Failure or cancel deletes the `.tmp`; a half-written cache can never
  be opened because only renamed files are considered.
- **Invalidation**: version mismatch, fingerprint mismatch (LAS changed), or CRC failure -> clear
  message and an explicit Rebuild button. Never a silent re-import.
- XYZ precision: f32 relative to the node centre -> sub-micron at leaf level, ~0.1 mm worst case at
  the root of a 1 km cloud; f64 centres keep the global relationship exact.
- Very large clouds: the importer streams points; the octree is built in chunks spilled to temp
  files under the cache folder (PotreeConverter 2 approach) when the cloud exceeds the in-memory
  cap. Ruby never holds the cloud - only the selected nodes' arrays.

---

## 10. Clip box and clip scenes (BUILT in v0.4.0)

`50__System__ClipBox/` (State, EditTool, Clipping tab JS).

- **Clip box** = axis-aligned box in **model** inches (left/right = x, front/back = y,
  bottom/top = z), so storeys and elevations stay level whatever the cloud's placement. The engine
  tests each point after local -> model (`M p + t`); points outside are not drawn. Nothing is
  removed from the LAS or the engine's copy.
- **Where it lives:** JSON in the model's attribute dictionary `Na__PointCloudViewer__ClipState`
  (key `json`, schema `Na__PointCloudViewer__ClipState` v1): `{ clip: {enabled, min, max},
  scenes: [{id, name, min, max}], activeScene }`. A few hundred bytes, no point data, and it travels
  with the `.skp` to the other computer. A corrupt value is ignored with a log line.
- **Undo:** every committed change is ONE named operation (`Point Cloud: Clip On`, `Point Cloud:
  Move Clip Top`, `Point Cloud: Save Clip Scene`, ...). A `ModelObserver` per model re-reads the
  dictionary on undo/redo, deferred by `UI.start_timer` (observers must not touch the model).
- **Clip on with no box yet** starts the box at the cloud's bounds. **Reset to Cloud** does the
  same at any time.
- **Typed limits** (Clipping tab): in the model's display unit; a bare number is that unit,
  anything else ("2.4m", "8'") goes through SketchUp's own length parser. A side must stay 0.5 in
  short of its opposite.
- **Edit tool** (`Na__ClipBoxTool`, a `Sketchup::Tool`): Edit Clip Box selects it; Finish Editing
  or any other tool ends it. The overlay draws the cage (12 edges, 6 square handles at the face
  centres, the hovered/dragged side outlined) after the cloud image, so the picture never covers
  it. Pick a handle (14 px) or the face under the cursor (ray vs box). Press-drag, or click / move /
  click. The side follows the point on its axis line closest to the mouse ray, so it tracks the
  cursor from any view angle. The VCB shows and takes a distance (outward positive), during a move
  or straight after one (re-types it, like Push/Pull). Esc cancels. Grabbing a side clips live even
  if Clip was off; the commit turns Clip on. The tool creates no geometry and never snaps.
- **While dragging** the image renders at the moving scale (as when orbiting) and the extents
  include the box, so near/far planes never cut the cage.
- **Clip scenes:** Save Current Clip (name optional, "Clip scene N" by default), click a name to
  switch, Update (shown when the box has changed since the scene was switched to), Rename inline,
  Delete with a second click to confirm. **Full Cloud** turns clipping off but keeps the box and the
  scene it came from, so Clip on returns to them. A scene always clips when switched to.
- **Zoom to Cloud** frames only the clipped part while clipping is on.
- Unloading the cloud keeps the box and scenes (they belong to the model).

**Later (M3):** with the octree, nodes outside the box are skipped before any point is tested and
nodes fully inside need no per-point test.

---

## 11. Threads and concurrency

- **Main thread only** for Ruby and the SketchUp API (Overlay, View, Model, HtmlDialog).
- Long work runs as **Na__AsyncJobs** (`01__AppCore/...AsyncJobs__.rb`): a chain of short steps,
  one `UI.start_timer` tick each. Between ticks SketchUp pumps messages, so the dialog paints the
  loading overlay, progress arrives, and Cancel works. The LAS import uses it.
- The dialog raises its full loading overlay and waits for a paint (`requestAnimationFrame` +
  40 ms) **before** calling Ruby, so a long step never starts behind a blank window.
- **Rendering** (BUILT M1b) runs inside `Overlay#draw` on the main thread; the engine fans the
  work out to its own pool of worker threads and joins them before returning. Workers touch only
  engine memory. The pool is heap-allocated and destroyed only by `napc_shutdown` (never a static
  destructor - joining threads under the DLL loader lock at process exit can deadlock).
- **LAS import** (M2a) runs on one `std::thread` that touches only plain C++ data: the LASzip
  reader and the point buffers. It publishes `std::atomic` phase / done / total and reads an atomic
  cancel flag; an error string sits behind a mutex. A Ruby job step **polls** those counters each
  tick. The worker never sees Ruby. The job handle is a Fiddle pointer whose free function cancels
  and joins, so GC or a closed model cannot leave a thread writing into freed memory.

---

## 12. Why there is no scale control

A survey cloud is measurement. A cloud that is 2 % too big looks perfectly plausible and silently
puts every wall you trace in the wrong place. So:

- The user transform is **rigid**: rotation + translation, enforced orthonormal (section 6).
- No X/Y/Z scale, no uniform scale, no scale-tool proxy (the cloud is never an entity the native
  Scale tool can grab), no "fit between two picked points".
- The **only** scale-like step is the explicit source-unit choice at import, which maps to an exact
  factor. It is stored as a unit key, separate from the rigid transform, and changing it after
  import is behind an unlock plus a warning that states the size change ("this makes the cloud
  25.4x larger").

---

## 13. Config layers

| Layer | Where | Holds |
|---|---|---|
| Plugin defaults | `02__AppData/...AppConfig__Defaults__.json` (committed, read-only) | limits, presets, defaults, image render scales, overlay id, paths |
| User config | `91__UserConfig__LocalOnly/Na__PointCloudViewer__UserConfig__.json` (git-ignored, per PC, schema v3) | last tab, last LAS folder, move and angle snap, last display settings |
| Model: clip | the `.skp`, dictionary `Na__PointCloudViewer__ClipState` - BUILT v0.4.0 | clip box, clip scenes, active scene (section 10) |
| Model: placement | the `.skp`, dictionary `Na__PointCloudViewer__Placement` - BUILT v0.5.0 | cloud fingerprint, rotation, translation, gimbal point, locked (section 15) |
| Model: LAS link | the `.skp`, dictionary `Na__PointCloudViewer__ModelLink` - BUILT v0.6.0 | link id, file name, last path, path relative to the .skp, unit key, point count, fingerprint (section 14) |
| Local backup | `91__UserConfig__LocalOnly/Na__PointCloudViewer__ModelBackups/<linkId>.json` (per PC) - BUILT v0.6.0 | a copy of the three model records, model path and title (section 14) |

All JSON carries `schema` + `schemaVersion`. No point data is ever stored in JSON or in the model.

**Decision (clip state built this way in v0.4.0; confirm the rest with Adam for M4):** instance
state (transform, units, clip scenes) lives *in the .skp*, not in a per-PC JSON, because models move between the studio PC and the other computer
and a per-PC file would lose the transform and clip scenes on the second machine. It is a few KB.
The cache stays per PC and is rebuilt from the LAS if missing.

---

## 14. Model association and recovery (BUILT in v0.6.0, cache still M2b)

`70__System__Persistence/` (ModelLink, LocalBackup, link card JS).

**Why it is careful:** Adam saw Undet's point cloud links make SketchUp files unopenable. So:

- **What the model holds:** three model-level attribute dictionaries, each ONE JSON string of a
  few hundred bytes (`Na__PointCloudViewer__ModelLink`, `..._Placement`, `..._ClipState`). No
  entities, components, materials, images or file references that SketchUp itself follows. With
  or without this plugin, with or without the LAS, the model opens exactly as it would anyway.
- **Nothing on open.** `onOpenModel` only gives the model an overlay (an in-memory object, never
  saved). No file is touched, nothing loads. The View tab shows a **Saved With This Model** card;
  the cloud comes back only when the user presses **Reload Point Cloud**.
- **Every write** is one named operation, aborted on error (Element Studio Pro's pattern), so it
  can be undone and never half-applies. JSON records carry `schema`, `schemaVersion` and
  `updatedAt` / `updatedEpoch`; reads validate and fall back rather than raise.

**The link record** (`Na__PointCloudViewer__ModelLink`): `linkId` (`PCV-<date>-<time>-<hex>`,
our own id: SketchUp's model GUID changes on every save), `createdAt`, `updatedAt`, and the cloud:
`fileName`, `lastPath`, `relativePath` (from the .skp's folder, so a project folder can move
between the two computers), `sourceUnit`, `pointCount`, `fingerprint` (point count + survey origin
from the LAS header, file name excluded). Written when a LAS is imported, rewritten only when the
cloud or its location changes; a plain reload writes nothing.

**Reload Point Cloud** looks for the LAS in order: last path, relative to the .skp, beside the
.skp, the path in this computer's backup, the last import folder. For each it reads only the
header (under 1 ms) and accepts it only if the fingerprint matches; then the normal import runs
with the stored unit (no question), and the placement and clip box come back from the model.
**Locate LAS...** applies the same check to a file the user picks (renamed or moved copies match).

**Two things have to fail** (Adam's rule): every change also writes the same three records to a
local backup file named by the link id. On the link card:
- the model's copy is older than the backup and differs (SketchUp closed or crashed without
  saving) -> **Restore Newer Backup** writes the backup into the model (one operation);
- the model's link is missing or unreadable but a backup exists for a model at this path ->
  **Restore From Backup**.
The backup is only rewritten after a real point cloud change, or an Undo / Redo that changed our
records (a snapshot comparison), never by opening, reloading or an unrelated Undo. A backup that
holds later changes than the ones replacing it is first kept as `<linkId>__superseded__<time>.json`
(newest five).

**Escape hatch:** Settings > **Remove Point Cloud Data From Model** deletes all three records in
one undoable operation; the local backup is kept.

**Element Studio Pro comparison (03-Oct-2026):** ESP stores JSON strings in attribute
dictionaries on component definitions with an ID record on the instance, merges saved data over
defaults, wraps writes in operations with abort, and does nothing on open. It keeps no copy
outside the model; the local backup here is new.

Still M2b: the `.napc` cache, so Reload does not re-read the whole LAS.

---

## 15. Position, orientation, lock (BUILT in v0.5.0)

`60__System__Transform/` (Placement, MoveTool, RotateTool, ConfigExport, Transform tab JS).

- **Placement** = rotation `R` (row-major 3x3, orthonormal) + translation `t` (model inches) +
  gimbal point + `locked`. The engine matrix is `local_to_model = R * k` then `t`, rebuilt on every change; the
  cloud's model bounds are the box of its 8 transformed corners. Nothing in the engine or the
  points changes.
- **Stored** in the model dictionary `Na__PointCloudViewer__Placement` (schema v1:
  `{ key, file, rotation[9], translation[3], locked }`), one named operation per change: Unlock /
  Lock Position, Move Along Red / Green / Blue, Rotate, Position Values, Reset Position. A placement
  for a different cloud is left alone; the new cloud starts at its import position with a note.
- **Locked by default** after every import. Locked: Move, Rotate, the typed values and Reset are
  disabled; Lock while a tool is active deselects it; an Undo that re-locks deselects it too. Unlock
  is a deliberate button on the Transform tab; the tools are only on that tab.
- **Gimbal point (v0.6.0):** a point ON the cloud, stored in local coordinates (source units), so
  it moves and turns with the cloud like a component's axes. Default: the centre of the cloud's
  box. **Set Gimbal Point** turns the Move tool into a one-click picker with SketchUp inference
  (vertices, edges), `g = R^T (p - t) / k`; **Centre Gimbal** returns to the default. The typed
  X / Y / Z are the gimbal point's model position, and typed rotations turn the cloud about it
  (`t = target - R k g`).
- **Move (gimbal):** three arrows (red X, green Y, blue Z) at the gimbal point, a fixed 90 px on
  screen, drawn by the overlay after the cloud. Hover to highlight; press-drag or click / move /
  click; the arrow follows the point on its axis closest to the mouse ray. Moves snap in steps
  from where the drag started (5 mm by default, per-user, Transform tab). Typed distance in the VCB
  (also re-types the last move, unsnapped). Esc cancels. A dashed guide shows the axis and the start.
- **Rotate (protractor):** SketchUp's language. Click the centre, click a starting direction, move
  and click. Clicks 1 and 3 use `Sketchup::InputPoint` inference, so the cloud lines up with model
  endpoints and edges (an inferred point is dropped onto the protractor plane); otherwise the mouse
  ray meets the plane. Default axis blue (plan); arrow keys lock red / green / blue. Optional angle
  snap (off, 15 degrees). Typed angle during or straight after a rotation. Esc cancels.
  `R' = Q R`, `t' = c + Q (t - c)`.
- **Typed values:** X, Y, Z of the gimbal point (its survey coordinates shown) in model units;
  rotation as Plan (Z), Tilt X, Tilt Y degrees with `R = Rz * Ry * Rx`, about the gimbal point.
  Reset to Import Position needs a second click.
- **While moving or rotating** the image renders at the moving scale and the clip limit cache is
  recomputed per frame; the clip box stays fixed in the model (it is model geometry, the cloud
  moves through it).
- **Export Configuration:** one JSON file (`Na__PointCloudViewer__ConfigExport` v1) with the
  cloud file, unit, local origin, placement (position, rotation, matrix, lock), clip box, scenes,
  display settings and snap preferences, plus the survey relationship in words. No point data.

Not built (from the original design): two-point "align direction to X / Y" and "set point as
origin". The protractor's inference covers most alignment; they can follow if needed.

---

## 16. Multiple clouds

V1 = one cloud per model. The boundary is `Na__CloudSession`: a session holding a list of clouds
(each with its own transform, cache handle and frame) is the only change needed; the overlay, the
draw loop (iterate clouds) and the dialog's state payload are the touch points.

---

## 17. Build process (BUILT)

Same toolchain as the decimator: Visual Studio Build Tools 2022 (MSVC v143, 14.44 on the studio
PC since 03-Oct-2026), CMake and Ninja (pip-installed into Python 3.12 `Scripts`, on PATH). No
Ruby headers: the DLL is plain C ABI.

`powershell -ExecutionPolicy Bypass -File 02__Src__NativeEngine/03__BuildScripts/Na__PointCloudViewer__NativeEngine__BuildWindows__.ps1`

The script maps the modules folder to a FREE drive letter for MSVC's path limits and unmaps it
afterwards (the decimator leaves `X:` mapped, so that letter is never reused). Build tree in
%TEMP%. Static CRT (`/MT`, no redistributable needed), no `/arch:AVX2` (an illegal instruction
would take SketchUp down). LASzip compiles from the vendored folder into the same DLL. Output:
`02__Src__NativeEngine/04__Bin__WindowsSketchUp2026/Na__PointCloudViewer__NativeEngine.dll`.

---

## 18. Hot reload

Settings > Reload Plugin: re-`load`s every `.rb` under `02__Src__AppModules`, clears the cached
config JSON, re-runs `Na__Registry__InstallOnce`, then closes and reopens the dialog (HTML/CSS/JS).
State that must survive is `unless defined?`-guarded. The overlay class is reopened in place, so
no overlay is removed or added; the AppObserver is added once per SketchUp session.

The native DLL is loaded from a **shadow copy** (`90__AppCache__PointCloudCache/00__NativeShadowCopies/`),
so the build can overwrite the original while SketchUp runs. When the original is newer, reload
destroys every live native cloud (clearing their GC free functions first), calls `napc_shutdown`,
unloads the old copy and loads the new one; sessions see the generation change and upload again.
Clouds that exist only in the engine (LAS imports before the M2b cache) must be re-imported after
a swap.

---

## 19. Diagnostics

Settings > Technical Log: the last 30 log lines (warnings and errors coloured), the details behind
any status-bar message. Settings also shows the native engine's status (threads, build time,
newer build waiting). The View tab shows a drawing fault in plain English.

The M1 test tooling (synthetic cloud, benchmark, Diagnostics tab, live performance strip) was
removed in v0.4.0. Development checks now run outside SketchUp: a ctypes test of the DLL and an
offline harness that runs the real Ruby modules in SketchUp's own Ruby against API stubs with the
real engine and a real LAS (79 checks for v0.4.0).

---

## 20. Risk register

1. ~~Per-frame re-submission through the Ruby View API~~ - **confirmed (2.3 us/point) and
   designed out**: points never go through the View API; one textured quad per frame (section 7).
2. ~~Point size / alpha~~ - solved by the native renderer. **Open: points are drawn over model
   faces** (an Overlay has no model depth). Accepted for V1; worth asking Trimble about.
3. ~~Ruby GC with millions of Point3d~~ - gone: Ruby holds no points.
4. Image upload per re-render (`load_file` ~16 ms at half resolution) now bounds orbit frame
   rate - see the optimisation list in 7.2.
5. Native thread lifetime vs model close / GC / hot swap (sections 11, 18).
6. ~~Toolchain missing on the studio PC~~ - installed 03-Oct-2026.

---

## 21. Milestones

| | Scope | Gate |
|---|---|---|
| **M1** (built) | Plugin shell, overlay per model, renderer + frame builder, synthetic cloud, benchmark, diagnostics, settings + hot reload, unit contract, LASzip vendored | Benchmark + visual checks pick the primitive and a realistic budget ceiling - **result: Ruby primitives rejected** |
| **M1b** (built) | Native engine DLL (Fiddle, hot-swappable), multi-threaded splat rasteriser, stored-PNG texture path, image renderer with moving/settled resolution | 1M points: 31 fps orbiting, free when still - **passed live** |
| **M2a** (built) | LAS import via LASzip on a worker thread (progress, cancel), header report, explicit unit choice, uniform shuffle for the budget | Adam's 10.8M-point RealityCapture LAS displays - **passed live** |
| **Clip** (built, v0.4.0) | Clip box (typed limits + cage edit tool), clip-aware budget, clip scenes, stored in the model with undo; test tooling removed | Brought forward at Adam's request so he can draw against the clipped cloud |
| M2b | `.napc` cache (build, validate, reopen), fingerprint, rebuild flow | Reopens fast, survives cancel/failure |
| M3 | LOD selection (octree), node-level clip culling, navigation budget if needed | Stable LOD while orbiting |
| **Transform** (built, v0.5.0) | Transform tab: lock / unlock, move gimbal with snapping, rotate protractor with inference, typed position and rotation, placement stored in the model with undo and restored on re-import, configuration JSON export | Adam: "add the tool so we can transform a point cloud" |
| **Persistence** (built, v0.6.0) | LAS link in the model, local backup, explicit Reload / Locate / Restore / Remove, settable gimbal point, All budget preset, display settings per user | Adam: "positions all messed up the next day" must never happen |
| M4 | Two-point align, set origin, round trip across both computers | Round trip across both computers |
| M5 | Large-cloud hardening, error wording, docs | |
