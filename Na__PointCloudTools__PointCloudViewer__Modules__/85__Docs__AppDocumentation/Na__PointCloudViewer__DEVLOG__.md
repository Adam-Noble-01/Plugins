# Na__PointCloudViewer - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================

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
