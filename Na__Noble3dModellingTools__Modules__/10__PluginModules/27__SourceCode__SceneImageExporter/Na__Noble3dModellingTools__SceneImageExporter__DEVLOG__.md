# Na Noble3d - Scene Image Exporter - Development Log
# =============================================================================
# Module : 27__SourceCode__SceneImageExporter
# Plugin : Na Noble3d Modelling Tools
# Tab    : Misc Utils > Image Export

## Overview

Batch image exporter for SketchUp scenes. Replaces the hacky "export an
animation and throw away the frames you did not want" workflow with a direct
tick-list of scenes, real export presets, and full persistence of both.

The two things that make it worth having:

1. **Scene ticks persist.** Tick 10 of 30 scenes, save, close SketchUp, reopen
   next week — the same 10 are still ticked. Stored in a model attribute
   dictionary, so the state travels inside the `.skp` file itself.
2. **Export settings persist.** Size, aspect, format, line weight, transparency,
   render overrides, filename pattern and output folder are all remembered per
   model. Nothing to reset every time.

## File Map

| File | Role |
| --- | --- |
| `..._SceneImageExporter__Loader__.rb` | Requires sub-modules in dependency order |
| `..._SceneImageExporter__Presets__.rb` | SSOT for presets, size steps, aspects, overrides, defaults |
| `..._SceneImageExporter__ModelState__.rb` | Model dictionary read / write (scene ticks + settings) |
| `..._SceneImageExporter__Exporter__.rb` | Timer-chained batch render engine |
| `..._SceneImageExporter__DialogManager__.rb` | HtmlDialog lifecycle, payload build, JS callbacks |
| `..._SceneImageExporter__Run__.rb` | Public entrypoint called by the command router |
| `..._SceneImageExporter__UiLayout__.html` | Dialog shell |
| `..._SceneImageExporter__Styles__.css` | Light Noble Architecture theme |
| `..._SceneImageExporter__UiBridge__.js` | Scene list, settings form, progress, persistence round-trip |

## Model Dictionary Schema

Dictionary `Na__SceneImageExporter` on `Sketchup::Model`. Every value is stored
as a plain string so each key stays individually readable in SketchUp's native
attribute inspector — the same pattern as
`Na__ComponentEditorTools::Na__LibrarySerializer`. Only `selected_scenes` is a
JSON string, because it is genuinely a list.

```
schema_version            "1.0.0"
selected_scenes           ["Scene 1","Scene 4","Scene 9"]        (JSON array)
preset_key                standard_4k | draft_1080 | ... | custom
image_height              4096
aspect_mode               viewport | ratio_16_9 | a_land | custom | ...
custom_aspect_width       16
custom_aspect_height      9
file_format               png | jpg | tif | bmp
jpeg_quality              0.92
line_scale_factor         1.5
transparent_background    true | false
antialias                 true                                   (never user-disabled)
filename_pattern          {{ModelName}}__{{SceneName}}__{{Date}}__
overwrite_mode            overwrite | skip | unique
export_folder             D:/Project/04__Renders
silhouette_width          2
line_extension_amount     4
render_override_<key>     scene | on | off                       (one per override)
last_export_time          25-Aug-2026 14:32
last_export_count         10
last_export_folder        D:/Project/04__Renders
```

Scene names read back from the dictionary are filtered against the live page
list on load, so renamed or deleted scenes drop out cleanly rather than
producing phantom ticks.

Dictionary writes run inside a **transparent** operation
(`start_operation(name, true, false, true)`), so silently remembering settings
never adds a stray step to the user's undo stack.

## SketchUp Ruby API Surface Used

Verified against `ruby.sketchup.com` while building this module.

**`Sketchup::View#write_image(options_hash)`**

| Key | Type | Notes |
| --- | --- | --- |
| `:filename` | String | Extension selects the encoder |
| `:width` / `:height` | Integer | Maximum 16000 px on either edge |
| `:antialias` | Boolean | Defaults to `false`; this tool always sends `true` |
| `:compression` | Float | 0.0–1.0, JPEG quality only |
| `:transparent` | Boolean | PNG alpha, SketchUp 8.0+ |
| `:scale_factor` | Float | SketchUp 2019.2+ — **this is the line thickness control** |
| `:source` | Symbol | `:image` (offscreen, any size) or `:framebuffer` (viewport only) |

`:scale_factor` scales every viewport-dependent element: edge and profile line
widths, text heights, arrow heads and stipple patterns. `1.0` matches the
screen. Higher values keep linework readable when a large export is later
scaled down. The exporter retries once without `:scale_factor` if a build
rejects it.

`:source => :image` is used rather than `:framebuffer` — the framebuffer source
is capped at the viewport size, which is exactly the limitation that makes the
native animation-export route so restrictive.

**`Sketchup::RenderingOptions`** keys driven by the tri-state override list:

`DrawSilhouettes` / `SilhouetteWidth`, `ExtendLines` / `LineExtension`,
`DisplayText`, `DisplayDims`, `DisplaySectionPlanes`, `DisplayWatermarks`,
`DisplaySketchAxes`.

**`model.options['PageOptions']['ShowTransition'] = false`** — suppresses the
animated camera fly-between when scenes are activated programmatically. Without
this, a 30-scene batch spends most of its wall time animating. Snapshotted and
restored around every run.

## Export Run Mechanics

The run is a chained `UI.start_timer`, not a tight loop, at two ticks per scene:

- **Tick A** — activate the page, re-apply render overrides, `view.refresh`,
  push a progress update.
- **Tick B** — `write_image`, apply the overwrite policy, advance the index.

Render overrides are re-applied on *every* tick A because activating a scene
restores that scene's own saved rendering options — set them once up front and
the second scene silently discards them.

The chained-timer shape buys three things a loop cannot: the dialog progress bar
actually moves, Cancel is honoured between scenes, and SketchUp gets a beat
between page activation and capture so no scene renders with the previous
scene's camera.

On completion, cancellation, or error the run restores, in this order: the
originally active page, the snapshotted rendering options (after the page
restore, since that resets them), and the `ShowTransition` setting.

Per-scene failures are recorded and the run continues — one bad scene does not
abort the other twenty-nine.

## Filename Tokens

Default pattern `{{ModelName}}__{{SceneName}}__{{Date}}__` produces
`ProjectModel__North Elevation__25-Aug-2026__.png`.

| Token | Resolves to |
| --- | --- |
| `{{ModelName}}` | `.skp` filename without extension, or `Untitled` |
| `{{SceneName}}` | Scene tab name |
| `{{Date}}` | `25-Aug-2026` |
| `{{Time}}` | `14-32` |
| `{{Index}}` | `01`, `02`, `03` — position in the export run |

Names are sanitised for `< > : " / \ | ? *`, control characters, collapsed
whitespace, and trailing dots or spaces (which Windows rejects).

# =============================================================================
# VERSION HISTORY
# =============================================================================


# Na Noble3d Modelling Tools
## Version 0.1.1 - 25-Aug-2026 - Writability Check Fix + Group Reorder

### Update 01 - `File.writable?` Rejected Ordinary Windows Folders
- Choosing `Documents` or `Downloads` as the export folder failed with
  "Export folder is not writable". Both are fully writable; the check was wrong.
- On Windows, `File.writable?` maps to `_waccess(path, W_OK)`, which reports the
  **read-only file attribute**. For *directories* that attribute does not mean
  read-only — Windows sets it on shell folders to flag their `desktop.ini`
  customisation, so `Documents` and `Downloads` both carry
  `Attributes: ReadOnly, Directory` while remaining writable.
- Replaced with `na_folder_writable?`, which writes a small probe file into the
  folder and deletes it again in an `ensure` block. That is the only trustworthy
  test on Windows, and it also catches the cases `File.writable?` misses:
  permission-denied network shares, full disks and read-only mounts.
- Failure message now names the folder and says what to check, rather than
  asserting the folder is not writable.

### Update 02 - Moved Below Image Viewer
- `tool_group_order` for the **Image Export** group changed from 5 to 20, so
  Misc Utils renders Image Tools > Image Viewer first, then Image Export >
  Scene Image Exporter second.

### Status - Confirmed Working
**First successful end-to-end export run, SketchUp 2026, 25-Aug-2026.**
The writability fix was the last blocker; batch export now completes.

Verified after the run:
- [x] Documents and Downloads both accepted as export folders.
- [x] Batch export completes and writes image files.
- [x] Probe cleanup works — no `.na_scene_exporter_probe_*.tmp` left behind in
      Documents, Downloads or Desktop.
- [x] Misc Utils group ordering renders Image Viewer first, exporter second.
- [x] Reload Plugin Data picks up the module and re-renders the dialog cleanly.

Not yet exercised (no known failures, simply untested — carried forward to the
0.1.0 checklist below): persistence round-trip, preset behaviour, line weight
range, transparency, render overrides, state restore, Cancel.

## -----------------------------------------------------------------------------

# Na Noble3d Modelling Tools
## Version 0.1.0 - 25-Aug-2026 - Initial Scene Image Exporter

### Update 01 - New Feature Module
- New module at `10__PluginModules/27__SourceCode__SceneImageExporter/`, wired
  into `ModuleLoaders__Main__.rb`, `PublicAPI__CommandRouter__.rb`
  (`scene_image_exporter` handler key) and the UI command registry as
  **Misc Utils > Image Export > Scene Image Exporter**. Exposed to hotkeys.
- `ReloadManager` resets the dialog on Reload Plugin Data, matching the Image
  Viewer and Select Similar Filter modules.

### Update 02 - Scene Tick List With Persistence
- Scene list with per-scene checkboxes, All On / All Off / Invert, and a live
  text filter. All On / All Off / Invert respect the active filter, so they act
  on what is visible rather than on scenes the user has filtered away.
- Every tick writes straight back to the model dictionary — no Save button, and
  nothing lost if SketchUp is closed without exporting.

### Update 03 - Export Presets
- Eleven presets: Standard 4K (default), Draft 1080, Presentation 2K,
  Line Heavy 4K, Fine Line 4K, Transparent 4K, Print A3 @300dpi,
  Print A4 @300dpi, Web JPG 2K, Maximum 8K, and Custom.
- Presets are declared in `Presets__.rb` and pushed to the dialog as data, so
  adding one is a single-file edit. Editing any field by hand flips the selector
  to Custom rather than silently diverging from the named preset.
- Ten height steps from 1080 to the documented 16000 px ceiling, plus a free
  height override. Width is derived from the chosen aspect ratio (viewport
  match, seven fixed ratios, A-series landscape / portrait, or custom), so a
  preset behaves identically on any monitor.
- Anti-aliasing is hard-wired on and shown as a locked checkbox.

### Update 04 - Render Overrides
- Seven tri-state overrides (Use scene style / Force on / Force off) for profile
  edges, edge extensions, screen text, dimensions, section plane markers, style
  watermarks and model axes, plus numeric companions for profile edge width and
  edge extension length.
- Applied per scene and fully restored afterwards.

### Update 05 - Output and Progress
- OS folder picker via `UI.select_directory`, with the chosen folder remembered
  in the model dictionary and mirrored to `Sketchup.write_default` so a brand
  new model still starts somewhere sensible.
- Overwrite policy: overwrite, skip, or keep both with a numbered suffix.
- Live progress bar, per-scene status line, Cancel button, and a run summary
  reporting written / skipped / failed counts.

### Validation Checklist

Confirmed in the first live run (25-Aug-2026):
- [x] Misc Utils tab shows an **Image Export** group with the Scene Image Exporter button.
- [x] Dialog lists the scenes in the model.
- [x] Browse opens the OS folder picker.
- [x] Export writes one file per ticked scene.
- [x] Reload Plugin Data closes and reloads the dialog without errors.

Still to verify:
- [ ] Ticking scenes, saving, closing and reopening the model restores the same ticks. *(the core promise of the module - worth confirming first)*
- [ ] Export settings likewise survive a save / close / reopen cycle.
- [ ] Changing a preset updates size, format, line weight and transparency together.
- [ ] Editing any field by hand flips the preset selector to Custom.
- [ ] Resolved size readout matches height x aspect, and caps at 16000 px.
- [ ] Filenames read `Model__Scene__25-Aug-2026__.png`.
- [ ] Line weight multiplier visibly changes edge thickness between 0.5x and 3x.
- [ ] Transparent 4K preset produces PNGs with an alpha background.
- [ ] Render overrides apply to every scene, not just the first.
- [ ] The originally active scene, rendering options and transition setting are all restored after a run.
- [ ] Cancel stops the run after the current scene and reports a cancelled summary.

### Known Gaps / Future Work
- **Camera aspect ratio.** If a scene has a locked `camera.aspect_ratio` (set in
  Scene properties), SketchUp letterboxes the render to that ratio rather than
  filling the requested pixel dimensions. The exporter deliberately leaves the
  setting alone rather than overriding the user's intent, but a future "ignore
  scene aspect lock" toggle would be a reasonable addition if it bites.
- **Very large exports block the UI.** `write_image` is synchronous, so an 8K or
  16K scene freezes SketchUp for the duration of that one capture. The chained
  timer keeps the progress bar responsive *between* scenes, not during a capture.
  This is an API limitation, not something the module can work around.

# =============================================================================
