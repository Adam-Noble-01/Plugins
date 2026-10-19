# Na Point Cloud Viewer - ARCHITECTURE

Status: **v0.8.0: native image renderer (binned raster, screen crop, orbit budget), LAS import
with the `.napc` point cache (v2, named by the LAS content key), the clip box with clip scenes,
the Transform tab, model persistence (LAS link + local backup, explicit Reload) and the Clean tab
(Remove Noise, Refine Surfaces, Reduce Density; live preview in the clip box; Clean & Export LAS
to a NEW file, section 22) are built; everything marked _Designed_ is not yet code.** Written
03-Oct-2026, cleaning added 12-Oct-2026. Keep this file true: when a design decision changes,
change it here and say why in the DEVLOG.

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
out of scope: snapping, picking, measuring to points, meshing, registration/ICP, any scaling,
interactive editing or recolouring of points, any format but `.las`.

**Cleaning (v0.8.0) never edits a file.** The Clean tab previews three filters on the clip box and
Clean & Export LAS writes the whole cloud, cleaned, to a NEW LAS the user names; the original is
only ever read. Surface analysis exists inside the cleaning engine only (it finds the local
surfaces to refine towards); it is not offered as wall detection or geometry.

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
| Clean tab: settings -> physical parameters, preview requests, display switch [BUILT v0.8.0] | Cleaning engine: preview worker per cloud, full-cloud tiling, LAS export with verify + publish [BUILT v0.8.0] |
| Save As, destination checks, model association (one operation) [BUILT v0.8.0] | LAS content key, record identity and GPS time per point [BUILT v0.8.0] |

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

**Optimisations built in v0.7.0** (JW02, 1909 x 1228 viewport, all images pixel-identical to
v0.6.0, PNGs fully validated):

| Render | v0.6.0 | v0.7.0 |
|---|---|---|
| Full resolution, 1M points | 31 ms | 16 ms |
| Full resolution, all 10.8M | 124 ms | 73 ms |
| Orbiting (half res), all 10.8M | 57 ms | 23 ms (capped at 5M while moving) |
| Zoomed out: image SketchUp must decode | 9.4 MB | 0.8 MB |

- **Binned raster:** points are stored shuffled (so a budget is an even sample), which made every
  core write all over the depth buffer and fight over cache lines (~77 ns per point measured).
  Pass 1 projects a batch of 2M points into per-band bins; pass 2 gives each horizontal band to one
  worker (dynamic, 4 bands per worker), applied with plain loads and stores. Pass 1 is now bound by
  memory traffic (bins 12 bytes/point); micro-tuning (local copies, a cast instead of `floor`)
  gained nothing and was dropped to keep the output bit-exact.
- **Screen crop** (ABI 4: `FULL_WIDTH/HEIGHT`, `CROP_X/Y`): the image covers only the projected
  rectangle of the visible box (cloud, or its part inside the clip box) plus the point size; the
  whole view when only some corners are behind the camera; nothing at all when the box is off
  screen or entirely behind the camera. Every stage scales with pixels, including SketchUp's own
  `load_file` / `load_texture`, the largest cost.
- **Parallel PNG:** each worker copies and checksums its run of stored blocks; CRC-32 and Adler-32
  are joined with zlib's combine maths (byte-identical file). 10.5 ms -> 2.8 ms at full resolution.
- **Orbit budget:** while moving, at most `render.nativeImage.movingBudgetMax` (5M) points; the
  settled frame draws the whole budget.
- Not done: a 256-colour palette PNG (would posterise RGB clouds); spatially ordered storage (needs
  the octree, M3).

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

## 9. Point cache `.napc` v2 (BUILT in v0.7.0, version 2 in v0.8.0)

`01__CppSource/...PointCache__.{hpp,cpp}` (engine), `70__System__Persistence/...PointCache__.rb`.

The engine's own copy of an imported cloud: one file read straight into memory instead of decoding
and shuffling the LAS again. JW02: 215 MB (v2), Reload from cache ~0.1 s vs ~1.1 s (warm) to ~3 s
(cold) from the LAS.

```
HEADER (256 bytes, little-endian)
  0    char[8]  "NAPCv2\0\0"           ("NAPCv1\0\0" is still read)
  8    u32      headerBytes = 256
  12   u32      version = 2
  16   i64      pointCount
  24   f64[3]   localOrigin (source units)
  48   f64[3]   local box min      72  f64[3]  local box max
  96   i32      colourBits         100 u32     flags (bit 0 record index, bit 1 GPS time)
  104  f64      LAS size (bytes)   112 f64     LAS modified time (Unix seconds)
  120  u64      xyzBytes           128 u64     bgraBytes
  136  u64      recordIndexBytes   144 u64     timeBytes
  152  f64      timeBase (GPS time of the first LAS record)
  160  u64      contentKey of the LAS the cache was made from
  252  u32      CRC-32 of bytes 0..251
XYZ    f32 x 3 x count   local coordinates, shuffled order (as drawn)
BGRA   u32 x count       colours as drawn
INDEX  u32 x count       which LAS record each stored point is (v2, flag bit 0)
TIME   f32 x count       GPS time minus timeBase (v2, flag bit 1; omitted when constant)
```

- **Identity (v0.8.0): the LAS content key.** A 64-bit hash of the file size, every byte before
  the point records (header, VLRs) up to 4 MB, 64 blocks of 16 KB spread over the records (first
  and last included) and up to 1 MB after them (EVLRs). About 2 MB read (8 ms on a 33 MB file
  already in the file cache; 289 ms the first time on the 280 MB JW02 file). Two different files never share a cache, even with the same point
  count and survey position: a cleaned copy whose points only moved is a different file. Every
  Clean & Export also carries a random export id in its provenance VLR, so even two exports with
  the same settings are distinct files.
- **Where:** `90__AppCache__PointCloudCache/01__PointCaches/Na__PointCloudViewer__PointCache__k<key>.napc`,
  per computer, git-ignored.
- **Written** by the import worker thread after the shuffle (phase "Saving a point cache"), to
  `<file>.tmp` then `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`: whole or absent (a cache is
  plugin-owned and rebuildable; replacing it is fine, unlike any LAS). A failed write never fails
  the import; cancel deletes the `.tmp`.
- **Used** only when the header passes every check (magic, version, CRC, exact file length, point
  count), it records the content key asked for (the engine checks again on load, so a renamed cache
  file cannot be passed off), it knows every point's LAS record, AND the LAS, when found, has the
  recorded size and modified time (2 s slack): an in-place edit that kept every sampled byte is
  still caught. A LAS found nowhere still allows its cache (the model link records the key) with a
  note. A cache that fails while loading is deleted and the LAS read instead.
- **Migration from v1:** a v1 cache (named by point count + origin) is never used when the LAS is
  present: the LAS is read again and a v2 cache written. With the LAS missing, a v1 cache can
  still show the cloud, but it cannot be cleaned and exported (no record identity) until the LAS
  is found; the Clean tab says so.
- **Settings:** count and size, Open Cache Folder, Clear Point Caches (second click).
- **Still designed (M3):** octree nodes, palette and per-node CRCs inside the cache, so large clouds
  can be loaded and drawn by level of detail rather than whole.

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
- **Cleaning** (v0.8.0, section 22) has its own pool of hardware threads minus one (the renderer's
  pool stays free for drawing) behind a run mutex, plus one **preview worker** thread per cleaning
  context and one thread per **export job**. A preview request replaces any pending one and
  cancels the running one (every stage checks an atomic cancel flag); Ruby polls on a short timer.
  The context shares the cloud's points by `shared_ptr`, so releasing the cloud handle while a
  worker reads them is safe. Nothing heavy ever runs on SketchUp's main thread: the main thread
  only packs ~45 numbers per request and copies finished statistics.

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
| User config | `91__UserConfig__LocalOnly/Na__PointCloudViewer__UserConfig__.json` (git-ignored, per PC, schema v3) | last tab, last LAS folder, move and angle snap, last display settings, the Clean tab's filter settings (`clean.filters`) |
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
from the LAS header, file name excluded) and, from v0.8.0, `contentKey` (section 9). A cleaned copy
also records `derivedFrom` (the file it was made from: name, path, content key, point count, unit,
time), and the record keeps `history`, the earlier files this model link named (up to 20). Written
when a LAS is imported, rewritten only when the cloud or its location changes; a plain reload
writes nothing. `schemaVersion` stays 1: the new keys are optional and older versions ignore them.

**Reload Point Cloud** looks for the LAS in order: last path, relative to the .skp, beside the
.skp, the path in this computer's backup, the last import folder. For each it reads the header
(under 1 ms) and accepts it only if the fingerprint matches AND, when the link records one, the
content key matches (about 2 MB read), so an original and its cleaned copy, which can share a
point count and position, are never confused. Then the normal import runs with the stored unit
(no question), and the placement and clip box come back from the model. **Locate LAS...** applies
the same checks to a file the user picks (renamed or moved copies match). A link written before
v0.8.0 has no content key; its next load records one.

**Clean & Export LAS** (section 22.9) changes the link to the NEW file and writes the carried-over
placement in the same single operation, "Point Cloud: Use Cleaned LAS". SketchUp's Undo can put the
model's link back to the earlier file; Undo never deletes, moves or changes any file, and the
loaded cloud stays where it is (section 15).

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
- **A new local origin (v0.8.0):** a cleaned copy keeps the LAS coordinates of its source, but its
  bounds (and so its local origin `o`) can change when points are removed or moved. The placement
  is carried over so every survey point stays where it was: a LAS point `p` sits at
  `R k (p - o) + t` before and `R k (p - o') + t'` after, so `t' = t + R k (o' - o)`; the gimbal
  point (local) shifts by `o - o'`; rotation, lock and the unit are unchanged
  (`Na__Placement__ForNewOrigin`). Tested: the origin moved by (1229, -130, 1447) mm and a survey
  point kept its model position to 1.4e-14 in.
- **Undo / Redo reload rule (v0.8.0):** a stored record for the loaded cloud is applied; when the
  model now names ANOTHER cloud (a record for another cloud, or a link to another file, as after
  Undo of "Use Cleaned LAS"), the loaded cloud stays exactly where it is with a note ("The model now
  names ... Reload Point Cloud loads the file the model names."); only when there is no record and
  the link still names this cloud (its first saved change was undone) does it return to its import
  position.

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
destroys every live export job, then every cleaning context (each joins its worker thread), then
every native cloud, clearing each one's GC free function first, calls `napc_shutdown` (which also
stops any worker still alive before the pools go), unloads the old copy and loads the new one;
sessions see the generation change and upload again. Reload Plugin is refused while a job (an
import or a Clean & Export) is running. ABI 5 (v0.8.0) is checked before any function is bound.
After a swap the cloud must be loaded again (Reload Point Cloud reads the point cache, so this is
quick).

**Cold start (found 03-Oct-2026):** SketchUp loads extensions with a model already in place, but
that model must not be touched yet. Adding the overlay during extension loading crashed SketchUp
~20 s into every cold start, inside Ruby, while later extensions (AI Assistant) were loading:
`SketchUp.exe+0x384172` null write, the Ruby interpreter on the stack. Reload Plugin never showed
it (SketchUp already running), so it surfaced only when Adam restarted. Proven by bisection with
real cold starts (plugin off: no crash; plugin loaded but bootstrap skipped: no crash; overlay
added at load: crash; overlay added by the startup notification: no crash). Rule now: the first
`Na__Registry__InstallOnce` only registers the AppObserver; `expectsStartupModelNotifications`
delivers onNewModel / onOpenModel after loading and adds the overlay; any dialog action adds it on
demand. Only a reload (mid-session) adds it at once.

Testing cold starts: SketchUp 2026 loads extensions only after the Welcome screen, so launch
`SketchUp.exe "<scratch copy of a template>.skp"` and watch `%LOCALAPPDATA%\Temp\SketchUp*.dmp`.

---

## 19. Diagnostics

Settings > Technical Log: the last 30 log lines (warnings and errors coloured), the details behind
any status-bar message. Settings also shows the native engine's status (threads, build time,
newer build waiting). The View tab shows a drawing fault in plain English.

The M1 test tooling (synthetic cloud, benchmark, Diagnostics tab, live performance strip) was
removed in v0.4.0. Development checks now run outside SketchUp: a ctypes test of the DLL and an
offline harness that runs the real Ruby modules in SketchUp's own Ruby against API stubs with the
real engine and a real LAS (79 checks for v0.4.0, 183 for v0.7.0, plus 57 for the Clean tab in
v0.8.0; section 22.14 lists every v0.8.0 suite). The cleaning engine has a diagnostics call,
`napc_clean_debug_cells`, that returns each analysed cell's surfaces, sheets, flags and thin-test
measurements (tests only; not bound in Ruby).

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
| **Speed + cache** (built, v0.7.0) | Binned raster, screen crop, parallel PNG, orbit budget, `.napc` point cache; cold-start crash fixed | Reload in ~0.1 s; no crash on restart |
| **Clean** (built, v0.8.0) | Clean tab: Remove Noise, Refine Surfaces, Reduce Density with live preview in the clip box; Clean & Export LAS to a NEW file, reloaded and used by the model in one undoable step; cache v2 named by content key; record identity per point | Adam: a complete, non-destructive cleaning system; the original LAS is never touched |
| M4 | Two-point align, set origin, round trip across both computers | Round trip across both computers |
| M5 | Large-cloud hardening, error wording, docs | |

---

## 22. Cleaning: Remove Noise, Refine Surfaces, Reduce Density (BUILT in v0.8.0)

Engine: `01__CppSource/...CleanTypes__.hpp`, `...CleanRegion__.{hpp,cpp}` (parameters, zones,
gather, sparse cell grid), `...CleanNoise__.cpp`, `...CleanSurface__.cpp` (surface analysis,
refine, scatter test), `...CleanDensity__.cpp`, `...CleanSection__.cpp`, `...CleanPipeline__.{hpp,cpp}`
(stage caching, full-cloud tiling), `...CleanContext__.cpp` (C API, preview worker, export job),
`...LasExport__.{hpp,cpp}`, `...LasFile__.{hpp,cpp}`, `...KdTree__.{hpp,cpp}`, `...Geometry__.{hpp,cpp}`.
Ruby: `80__System__Clean/` (Settings, Preview, Export, Clean tab JS); style
`...UiFeature__Styles__Clean__.css`.

### 22.1 What it does, and what it never does

Three independent filters, each with On / Off, a strength slider and Advanced Settings (physical
values in millimetres). A live **preview** cleans the points inside the clip box; **Clean &
Export LAS...** cleans the WHOLE cloud with the same settings, writes a NEW LAS the user names,
loads it and makes the model use it.

Never: modify, truncate, rename, delete or replace the source LAS or any existing file (there is
no overwrite option anywhere); bake the SketchUp placement into the file; guess a unit (the unit
chosen at import converts the millimetre settings); average points into new ones (density keeps
measured points); average a doubled surface into a middle wall; run heavy work on SketchUp's main
thread; make file deletion part of SketchUp's Undo.

### 22.2 What the engine keeps per point (ABI 5)

| Field | Bytes | Why |
|---|---|---|
| xyz (f32 x 3, local, shuffled) | 12 | drawing and cleaning |
| bgra | 4 | drawing |
| source index (u32): which LAS record | 4 | export writes the source's own records; preview = export ordering ties |
| GPS time (f32, minus the first record's time) | 4 | scan pass test (omitted when the file has no time or it is constant) |

So 20 to 24 bytes per point in memory and in the v2 cache (section 9). Export refuses a cloud
without the record index (a v1 cache, or a cloud not from a LAS): "Reload it from the LAS first".

### 22.3 Determinism: the preview is exactly the export

The same point gets the same verdict and the same refined position whether it is cleaned in a
small preview box or in a full-cloud tile. Test H checks this bit for bit (five boxes and a
rotated model-frame box, largest difference 0.0 mm). What makes it true:

- **Canonical order:** points sorted by fine cell (z, then y, then x, global cell coordinates)
  and inside a cell by LAS record. Random choices (MSAC hypotheses) are seeded by the global
  coordinates of the cell, never by the region.
- **Own KD-tree** with neighbours ordered by (squared distance, LAS record). nanoflann was not
  used: with quantised LAS coordinates exact distance ties are common, and which tied neighbour a
  library returns depends on its traversal, so two regions could disagree.
- **Floating point:** `/fp:precise` for every cleaning source (the renderer keeps `/fp:fast`);
  one compiled function converts LAS integers to local floats everywhere.
- **Zones and halo:** each stage needs results from a known distance around it (CleanRegion.cpp
  documents each reach): density -> refine -> surface analysis (the scatter test reads 9 cells) ->
  noise verdicts (borrowed planes reach 3 cells: reach + 2) -> spacing (group size + link) -> kNN ->
  gather. Cell-shaped reaches are scaled by the frame's rotation spread (up to sqrt 3 for a box
  rotated against the cloud's axes). At the defaults the gathered margin is **1348 mm** around
  the box; it is computed with all three filters on, so switching a filter re-uses what was read.
- **Sparse cell grid:** only occupied 50 mm cells exist (a table of 16 x 16 x 16-cell blocks
  allocated where points are; cell ids in canonical order). A dense grid over a 16 m tile plus its
  halo had cost ~400 MB even for 60 points, and large Advanced values (a 2 m group extent) made
  exports fail; memory now follows the points (found by test J, fixed, all suites re-run).
- **Full cloud:** half-open tiles of whole grid cells, each one region run with its halo. A 16 m
  cube holding more than 2.5M points is halved along each axis, again and again, until each part
  fits or is 2 m across, so dense spots get small tiles and the rest of the site keeps large ones
  (one tile size for the whole site, set by its densest spot, had cut SK02 into 1181 tiles of
  ~2 m, each re-reading its 1.35 m margin: now 113 tiles, clean 480 -> 331 s). Every point must be
  in exactly one tile's core; if not, the export fails ("internal error") rather than skip one.
  Results do not depend on the tiling: uniform and adaptive tiles gave the same flags and
  positions for all 66.3M points of JW02, Cossethay and SK02, compared point by point.

### 22.4 Remove Noise

- **Isolated points:** a point's spacing (mean distance to its 8 nearest neighbours, searched to
  `knn_cap_mm`) compared with the median spacing around it. Removed when more than `iso_ratio`
  times the local spacing AND more than `iso_min_mm`. Relative, so sparse distant surfaces are not
  removed for being sparse.
- **Small detached groups:** points linked when closer than `link_factor` x the local spacing
  (clamped to `link_min_mm` to `link_max_mm`); union-find over the kNN edges, verified by radius
  queries so a group is never split by the kNN cap. A group of fewer than `cluster_min_points` that
  fits within `cluster_max_mm` is removed (floating clumps in front of windows). A handle, a pendant
  lamp, a pipe are larger or linked to their surface: kept (test D: 100 %).
- **Window blow-out:** sparse scatter off every confident surface, judged against the spacing of
  the surfaces around it (median per 150 mm coarse cell over the 5 x 5 x 5 around it, so scatter
  hanging off a window still sees the wall and frame). Default: only **marked** (orange in
  Differences, kept in the export); **Remove reflection scatter** removes it. A dense coherent false
  surface (a mirrored room seen through glass) is locally a real surface and is always kept: test D,
  100 %. Scatter with no surface within 300 mm is never judged (a garden seen through the glass can
  be real).

### 22.5 Refine Surfaces

Orientation from a LARGE neighbourhood, position from a SMALL one.

Per 50 mm cell, judging the 150 mm block around it:
1. **Noise width:** in "thin" cells (one clean sheet: PCA thickness ratio, a robust plane agreeing
   within 10 degrees with 80 % inliers, thickness <= 1.3 x the in-plane neighbour noise, and each
   half of the block facing the same way as the whole) the scatter across the sheet is measured
   from in-plane nearest-neighbour differences (immune to bows and tilt). Each cell uses the
   median of the thin cells around it (nearest nine within 3 cells if fewer than three adjacent).
2. **Orientations:** one sheet: its PCA plane. Otherwise up to three planes by MSAC, each next
   plane scored over the WHOLE block together with the planes already found (an edge-on strip of a
   perpendicular frame fits any plane through it when judged on leftovers alone), competing with
   the planes **borrowed** from thin cells within 3 cells (a corner block holds too little of each
   wall: 60 mm of wall with 10 mm noise fixes its normal only to ~5 degrees, and a tilted plane
   reads as two sheets). A borrowed plane keeps its orientation; block planes are refitted on their
   own nearest points.
3. **Families and sheets:** planes within 25 degrees are one family; its sheets are the modes of
   the members' offsets (smoothed by the noise width), or a two-Gaussian mixture when it is clearly
   better (BIC by 10, sheets 2.5 widths apart, each at least 15 %), each sheet checked to be smooth
   in-plane. The mixture is fitted by EM on bins 1/32 of the offsets' spread wide (see 22.16); the
   likelihoods that decide are summed over every point.
4. **Step or doubling:** two sheets side by side (complementary footprints) are a STEP (a skirting,
   a frame rebate, a sash): both refined. Two sheets over the same area AND mixed there (most of the
   which-sheet variance inside small footprint cells) AND both wide (10th to 90th percentile width
   >= 0.8 cells, so a pipe's near and far sides are not a doubled wall) AND further apart than
   `pass_disagree_mm` are a DOUBLING: marked (magenta) and, by default, not moved. With GPS time,
   scan passes over the main sheet whose medians differ by `pass_disagree_mm` are a doubling too.

Per point: assigned to the nearest sheet; points within ~1 noise width of where two orientations
meet are held (no rounding of corners); only points within `inlier_band` noise widths move; a
Tukey-weighted linear fit `z = a + b u + c v` over same-family neighbours within `smooth_radius_mm`
(redescending, started at the point's own height, so another sheet's points get zero weight)
gives the surface under it; the point moves `strength x confidence` of the way, at most
`max_move_mm`, along its family normal only (never sideways, so opening edges stay put). Nothing
assumes plumb, square or flat: every orientation is measured and the local fit follows bows (test
E: a bowed wall keeps its shape to 0.20 mm while its scatter drops 33.1 -> 10.5 mm).

### 22.6 Reduce Density

Keeps one REAL point per patch (the one nearest the patch's centroid; ties by LAS record), never
an average. On a confident surface the patch is 2D on that surface (`voxel_mm` square in the
surface's own frame), so a wall with 30 mm of noise thins evenly through its depth; off surfaces,
3D voxels. Points at corners, edges, steps, doubled or rough areas, held points and small objects
use patches `feature_factor` times finer. The result shows the share removed and the patch sizes
("About one point per 9 mm on plain surfaces, 3.6 mm at corners, edges and small objects").

### 22.7 Surface check (before / after scatter)

Up to two dominant planes in the box are measured: the 5th to 95th percentile of distances to a
plane fitted once (before) applied to the same points after, the robust (MAD) widths, and the
median shift (did the surface move?). When the box holds several surfaces of similar size, no
dominant flat surface (clutter, curves, openings) or too few points, **no figure is given** and the
tab shows an amber "Not suitable for a single figure" box with the reason.

### 22.8 Preview (Ruby)

`Na__CleanPreview`: one engine context per loaded cloud (created on the first request, destroyed
when the cloud changes or the engine is swapped). Changes (sliders, Advanced values, the clip box,
the placement, Undo / Redo) are debounced (`clean.preview.debounceSeconds`, 0.35 s); a request
carries 19 region numbers and 25 parameters; a poll timer (`pollSeconds`, 0.12 s) runs only while a
request is running. Previews run only while the Clean tab is the active tab. A finished result
builds two engine clouds of the box (Cleaned: kept points at refined positions; Differences: every
point coloured by verdict, colours in `render.cleanColours`), so the Original / Cleaned /
Differences switch is instant. The image renderer draws the preview cloud instead of the loaded
cloud only while the Clean tab is showing one; leaving the tab or closing the dialog shows the
loaded cloud again. The preview's points are in the loaded cloud's local frame, so the placement
and clip box apply unchanged.

### 22.9 Clean & Export LAS (the file rules, in order)

1. **Checks before Save As:** a cloud with record identity; the source LAS at its path, the same
   point count, the same content key as when it was loaded (else "Reload Point Cloud first"); an
   uncompressed `.las`; at least one filter on.
2. **Save As, every time:** suggested `<name>_Cleaned_01.las` (then `_02`, ...: the first free
   number; a cleaned copy counts on from its stem). Refused, with Save As shown again: the source
   itself (any path that resolves to it), any existing file, a missing folder, a non-`.las` name.
3. **The engine checks again, before cleaning:** a destination that exists (the source itself is
   named as such, by file identity), or a folder that does not, fails at once with nothing written.
4. **Clean** the whole cloud in tiles on the export thread (progress per point, Cancel works).
5. **Write** `<final>.partial-<tag>` in the destination folder, created exclusively
   (`CREATE_NEW`), then flushed to disk.
6. **Verify** with LASzip, an independent reader: point count, point format and an
   order-sensitive digest of every point's coordinates against what was written.
7. **Publish** with `MoveFileExW` WITHOUT `REPLACE_EXISTING`: a file that appeared meanwhile is
   never replaced. Cancel or any failure before this deletes the partial file, and nothing else.
8. **Load** the new file like any LAS (its own content key, its own new cache; the original's
   cache is kept).
9. **Only then** the model changes, in ONE undoable operation "Point Cloud: Use Cleaned LAS": the
   link names the new file (`derivedFrom` the original, `history` kept) and the placement is carried
   over (section 15) so the cloud stays exactly where it was; the clip box and scenes are model
   coordinates and are untouched. If that write fails the original stays loaded.
10. **Report:** points written, removed by kind, refined, held, doubled, file size, time, tiles,
    peak memory and the engine's notes (dropped index VLRs, cleared statistics).
11. **Export done but loading failed or was cancelled:** the file is kept, the model still uses
    the original, and **Load Cleaned LAS** tries again (outcome shown as a warning).

Re-cleaning a cleaned file creates another new file (`_Cleaned_02`) and its provenance VLR keeps
the previous one under `"previous"` (one VLR, chained). SketchUp's Undo can switch the model back to
the earlier file; it never deletes or changes a file, and the loaded cloud stays in place.

### 22.10 What the new LAS keeps

The writer copies the source's own point records byte for byte and patches only X / Y / Z of moved
points (rounded to the file's own scale and offset; a move that would leave the int32 range is
refused and the point keeps its position, counted as held). Kept: version, point format, record
length, scale, offset, GUID, global encoding (CRS bits), RGB, NIR, intensity, classification and
flags, returns, scan angle, user data, point source id, GPS time, extra bytes, every VLR and EVLR
(byte for byte), waveform data inside the file. Changed: System Identifier `MODIFICATION`,
Generating Software `Na Point Cloud Viewer <version>`, creation date, point counts (legacy and
1.4), points by return (recounted from the records), bounds (from the written points). Dropped,
with a note: records that index the source's own point order (LAStools spatial index 30, LASzip,
COPC). Cleared, with a note: extra-bytes
min / max when points were removed (they would describe removed points). Added: VLR
`NobleArch_PCV` / 1 with the settings, the engine parameters, the source's name, content key and
point count, and a random export id. Coordinates stay in the source's own frame; the SketchUp
placement is never written into the file. Test I checks all of this for LAS 1.2 formats 0 to 3 and
LAS 1.4 formats 6 to 8 (extra bytes, EVLRs, WKT), 122 checks.

### 22.11 Defaults and why

Strength 50 maps to the engine defaults the tests run (Refine 70); the mapping is documented in
`80__System__Clean/...Settings__.rb` and stored with every export.

| Setting | Default | Why |
|---|---|---|
| Remove Noise | on | stray returns are never wanted; the filter is conservative (relative isolation) |
| isolated ratio / gap | 3 x local spacing, 20 mm | at 2 x the edge of a sparse surface starts to go; 20 mm protects dense areas |
| detached group | < 35 points within 200 mm, link 3 x spacing (40 to 120 mm) | floating clumps go (D: 94.8 %); handles, lamps, pipes stay (100 %) |
| reflection scatter | marked, not removed | it can be real (a view through glass); the user decides |
| Refine Surfaces | on, strength 70 | A: band 32.9 -> 10.4 mm at 70 % (4.3 mm at 100 %); 70 keeps some texture and margin |
| largest move | 25 mm | about 2.5 noise widths of a noisy SLAM scan; never crosses a 30 mm step |
| analysis cell | 50 mm (150 mm blocks) | enough points to judge orientation at 10 mm noise; small enough for trims |
| fit radius | 30 mm | keeps steps from 30 to 50 mm (C: 30.1 and 51.1 mm) |
| surface band | 3 noise widths | points further out are another surface or an object, never pulled in |
| doubled surface gap | 15 mm | below that two passes are within one noise width: one noisy surface |
| leave doubled surfaces | on | never average two passes into a wall that is in neither |
| Reduce Density | off | thinning removes measured data: opt in |
| patch | 9 mm, 2.5 x finer at features | plain wall keeps ~one point per 9 mm (34 to 41 % of a 5 mm scan); details keep 81 % |

### 22.12 Dependencies evaluated (12-Oct-2026)

| Library | Licence | Verdict |
|---|---|---|
| Open3D | MIT | Rejected: very large (pulls Eigen, TBB, many more); its SOR / ROR and voxel down-sampling are the simple forms (voxel down-sampling averages points, which this design forbids). |
| PCL | BSD-3-Clause | Rejected: huge dependency tree (Boost, FLANN, Eigen, VTK); build cost far above the value of its SOR / ROR filters. |
| CCCoreLib | LGPL-2.0-or-later (CMake files MIT) | Rejected: static linking into this DLL would bring LGPL relinking obligations; it would need its own DLL. |
| nanoflann | BSD-2-Clause | Not used: header-only and small, but equal-distance neighbour ties depend on its traversal, which breaks preview = export on quantised LAS. Own deterministic KD-tree instead. |
| Eigen | MPL-2.0 | Not used: only 3 x 3 symmetric eigen problems are needed; a 60-line Jacobi solver does it. |

Result: no new third-party code. LASzip 3.5.0 (Apache-2.0, vendored) stays the only external
dependency, now also used to verify every exported file.

### 22.13 Known limitations (measured, not assumed)

- **SLAM registration:** a doubled surface is found when its sheets are at least ~2.5 noise widths
  apart and interleaved over the same area, or, with GPS time, when scan passes differ by 15 mm
  (F: 25 mm apart at 6 mm noise 99.7 %; 20 mm apart at 10 mm noise with time 99.9 %). Without time,
  sheets 20 mm apart at 10 mm noise are only 11 % flagged: they cannot be told from one noisy
  surface. Misregistration smaller than the noise cannot be seen at all.
- **Thin objects seen from both sides** look exactly like one surface scanned twice: an open door
  leaf (two faces ~40 mm apart over the same footprint), a radiator in front of its wall, a door
  frame return. On Cossethay they are flagged as possible doubling (render check, 12-Oct-2026).
  They are held where they were scanned, never averaged or moved: the flag is a prompt to look,
  not a verdict. Flag rates on the real GeoSLAM scans: Cossethay 6.1 %, Derby Road 7.7 %, SK02
  14.8 % of points (no GPS time in SK02); how much of that is real misregistration has not been
  checked against a survey.
- **Window reflections:** a dense coherent false surface is kept by design (locally it is a
  surface); sparse blow-out is only marked unless Remove reflection scatter is on.
- **Corners at high noise:** points within about 2 noise widths of a corner line are held, not
  refined (no rounding). B at 10 mm noise: points off both walls near the corner 3749 -> 936.
- **Residual false doubling at trim junctions** in noisy scans (no-doubling test scenes): window C
  at 10 mm noise 451 / 661 of ~35k points, blow-out D 3278 of 180k, details G 924 of 225k at 10 mm
  and 177 at 3 mm; corners B 0. Those points are marked and held, never averaged.
- **First preview of a session** also builds the cloud's coarse spatial grid (measured 0.26 to
  0.39 s for the 10.8M and 16.5M point scans, 0.9 to 1.1 s for 39M); later previews re-use it, and
  a strength change re-uses every earlier stage (0.01 to 0.23 s measured).
- **Preview time follows the points gathered, not the box:** every box is read with its 1348 mm
  margin, so a 1 m box over a dense scan processes up to 45 times the points inside it. Within 2 s
  for 0.5 to 1 m boxes over typical parts of all four real scans (the 1 m box at the middle of
  Cossethay: 1.26 to 1.38 s); not at the densest spots: a 1 m box takes 2.1 s at Cossethay's
  densest column and 7.0 s at SK02's (a passage scanned on many passes); 2 m boxes take 0.3 to
  4.1 s, and 13 s at that SK02 spot (22.16).
- **Preview size estimate** before the first run is only an even-spread estimate; the measured
  count replaces it once a preview has run.
- **Sources:** LAZ is not supported (neither for import nor export); export needs a cloud loaded
  from its LAS or a v2 cache.
- **Not tested here:** a destination folder without write permission (needs ACL changes; the
  engine's create failure path is covered by a missing folder and an unavailable drive).

### 22.14 Tests (what was actually run, 12-Oct-2026)

| Suite | Checks | Result | What |
|---|---|---|---|
| Algorithms A to H (`test_algorithms.py`) | 100 | all pass | noisy wall, corners, recessed window, blow-out, bowed wall, doubled passes, fine details + density, preview = full cloud bit for bit |
| Identity + cache (`test_identity_cache.py`) | 20 | all pass | record identity bit for bit, GPS time, cache v2 / v1, content key refusal |
| Export integrity I (`test_export.py I`) | 122 | all pass | 7 point formats, every byte checked, VLRs / EVLRs / WKT / extra bytes, re-cleaning chain |
| Failure handling J (`test_export.py J`) | 14 | all pass | cancel in each phase, existing / source / missing destinations, changed / truncated / missing source, wrong file, no record identity, everything removed |
| Ruby harness, existing (`pcv_runner.py`) | 183 | all pass | the whole plugin against the real engine and JW02 |
| Ruby harness, Clean tab (`pcv_runner.py clean`) | 57 | all pass | preview, display switch, settings, Save As refusals, export + reload + association, position carried over, Undo, cancel, failed load + retry, blockers |
| Performance K (`test_perf.py`) | 6 cases | see 22.15 | real scans read-only, SHA-256 and modified time unchanged |
| Preview speed changes (`snapshot.py` + `compare_snap.py`, scratch) | 36 boxes, 2.65M points | see 22.16 | per-point verdicts and positions before / after each change |
| Tiling independence (`full_compare.py`, scratch) | 66.3M points | identical | whole-cloud runs of JW02, Cossethay, SK02 with uniform and adaptive tiles: every point's flags and position |
| Renderer regression (`test_render_regression.py`) | 6 views | identical | the last committed engine (ABI 4) and the new one render JW02 pixel for pixel the same (perspective, parallel, clip, budget, crop, monochrome, 3 px points) |

Manual verification still needed in SketchUp itself: the live dialog and viewport (the preview
clouds drawn by the real renderer), SketchUp's own Save As (its overwrite prompt is answered by
our refusal, not trusted), Undo through SketchUp's real undo stack, a cold start with the new
modules, and visual judgement of the cleaning on Adam's scans.

### 22.15 Measured performance (12-Oct-2026)

AMD Ryzen 7 3700X (8 cores, 16 threads), 32 GB, Windows 10; the final engine, run 23:39 to 23:52.
RealityScan was open on the same PC: other processes kept 0 to 3.4 cores busy during the timed
phases (measured per phase by `bgload.py`); earlier in the evening they took up to 10 cores and
the same previews ran up to 40 % slower, and disk contention made one load (Synthetic 9 rooms,
7.9 s here, 1.1 s before) slow. Full export = clean + write + LASzip check + publish. Memory = the
test process's peak working set (the cloud loaded, the engine and Python). Preview boxes are at
the middle of each cloud (Derby's and JW02's middles are sparse; 22.16 has the densest spots).
Before the speed work of 22.16 and the adaptive tiles (same evening): export total JW02 73.3 s,
Cossethay 170.5 s, Derby Road 293.6 s, SK02 535.8 s; the 1 m Cossethay preview 2.60 s.

| Cloud | Points | Load | Clean whole cloud | Write + check | Export total | Engine work peak | Process peak | Preview 1 m / first 2 m / 2 m re-used | Source unchanged (SHA-256 + time) |
|---|---|---|---|---|---|---|---|---|---|
| Synthetic room (LAS 1.2 f1 + time) | 1.16M | 1.0 s | 3.2 s (1 tile) | 0.8 s | 4.0 s | 224 MB | 564 MB | 0.44 / 1.10 / 0.17 | n/a (synthetic) |
| Synthetic 9 rooms (LAS 1.2 f1 + time) | 10.46M | 7.9 s | 42.1 s (8 tiles) | 5.3 s | 47.5 s | 959 MB | 1722 MB | 0.49 / 1.42 / 0.19 | n/a (synthetic) |
| JW02, RealityCapture (LAS f2, no time) | 10.76M | 1.1 s | 33.0 s (12 tiles) | 5.5 s | 38.6 s | 576 MB | 1027 MB | 0.05 / 0.44 / 0.01 | yes |
| Cossethay, GeoSLAM (LAS f1 + time) | 16.47M | 1.9 s | 86.6 s (25 tiles) | 8.0 s | 94.8 s | 1566 MB | 2694 MB | 1.38 / 3.51 / 0.78 | yes |
| Derby Road, GeoSLAM (LAS f1 + time) | 31.30M | 3.7 s | 149.0 s (70 tiles) | 14.9 s | 164.0 s | 947 MB | 2413 MB | 0.04 / 1.13 / 0.01 | yes |
| SK02 Ascott Drive, GeoSLAM (LAS f0, no time) | 39.03M | 3.3 s | 324.9 s (113 tiles) | 31.1 s | 356.2 s | 1814 MB | 3787 MB | 0.24 / 1.73 / 0.07 | yes |

### 22.16 Preview speed (measured and tuned 12-Oct-2026)

**Where the time goes.** A preview processes the box AND its 1348 mm margin (22.3), so for a small
box over a dense scan the margin is almost all of the work: a 1 m box at the middle of Cossethay
(GeoSLAM, 16.5M points) holds 32 340 points but gathers 1 450 644. Measured stage by stage (engine
timers, plus a scratch build with timers inside the surface analysis): before tuning, that box took
2.5 s, of which gather 0.30 s, spatial index 0.39 s, noise 0.32 s and surface analysis 1.40 s; and
75 % of the surface analysis was ONE step, the two-sheet mixture test (EM ran ~52 rounds on average,
two `exp` per point per round, for every family with one visible sheet).

**What changed** (each verified on 36 preview boxes over three clouds, 2.65M points compared point by
point, and by test H):

| Change | Result |
|---|---|
| Mixture EM on bins 1/32 of the spread wide (count, sum, sum of squares per bin; one `exp` per bin) | EM 4.2 x less CPU. Not bit-identical, so validated against the per-point EM run beside it on 499 943 real cases: the same decision in all but 10, each on a threshold (separation 2.4999 against 2.5001, weight 0.1500); 14 of 2.65M points (0.0005 %) change a flag. Coarser bins were tried and rejected: 1/16 changed 135 decisions, some clear-cut; 1/4 finds other solutions on small or heavy-tailed sets. |
| Noise-width helper (in-plane nearest neighbours): bucket index by counting sort, each 3-bucket row searched as one contiguous run | 0.25 -> 0.09 ms per cell; bit-identical (same candidates, same order) |
| MSAC: the scored sample gathered once per cell as positions | the 40-hypothesis cost loop no longer reads through an index; bit-identical |
| Gather: each hit carries its position, LAS record and time; the loops after the scan run in parallel | 0.30 -> 0.08 s; bit-identical (nothing reads the shuffled cloud after the scan) |
| KD-tree build: flat copy of the coordinates, top levels split level by level in parallel, subtrees on their own threads | 0.39 -> 0.11 s; the same splits as a one-thread build (only the node numbering differs, and no query result depends on it) |

**Result** (same box, same machine, other processes 0.6 cores): **2.5 s -> 1.26 s** (gather 0.08,
KD-tree 0.11, noise 0.32, surface analysis 0.64, refine 0.09 s). Whole-cloud exports gained too
(each tile runs the same stages): see 22.15.

**The densest spot of each cloud** (`preview_dense.py`: a fresh box on the cloud's densest 1 m
column, full height, grid already built, other processes 0.7 to 2.7 cores):

| Cloud | Points inside the 1 m box | 0.5 m box | 1 m box | 2 m box |
|---|---|---|---|---|
| JW02 | 31 653 | 0.16 s | 0.19 s | 0.29 s |
| Derby Road | 126 635 | 0.70 s | 0.93 s | 1.78 s |
| Cossethay | 251 770 | 1.27 s | 2.08 s | 4.12 s |
| SK02 | 614 721 | 3.36 s | 6.97 s | 13.35 s |

SK02's densest column is a passage the scanner went through again and again (its points come from
records spread over the whole capture, about 1.0 to 2.7 m above the main floor, 1.6 % of the scan
in one square metre). There every point has hundreds to thousands of neighbours within the 50 mm reach
of the local fit, and refinement alone takes 3.1 s of the 1 m box's 7.0 s. The preview still runs
on the engine's thread, and moving the box or a slider supersedes it, but the 2 s target is not
met at such spots.

**Not done (would change results or need a new design):** a smaller margin (the scatter test's
5 x 5 x 5 coarse cells alone add 450 mm to it); fewer EM rounds; a cheaper first pass over the
outer ring of the margin. The noise stage (kNN for every gathered point) is now the second largest
stage.
