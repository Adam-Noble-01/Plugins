# Na Noble3d - Scene Data Transfer - Development Log

```
Module  : 28__SourceCode__SceneDataTransfer
Plugin  : Na Noble3d Modelling Tools
Tab     : Misc Utils > Scene Data Transfer
Version : 0.1.0  (first stable)
Schema  : 1.1.0  (payload format)
Target  : SketchUp 2026.2+ for full function, 2026.0 with styles degraded
```

## Overview

Rebuild SketchUp scenes from a **different** model without opening that model.

Model B is captured: every scene is serialised into a hidden carrier component so the data
travels inside the `.skp`. Model A then reads that file straight off disk, and the user ticks
which scenes to pull and which properties to reconstruct. Each imported scene carries **only**
the ticked properties, suffixed `__IMPORTED`.

The problem it solves: a client asks for the exact camera angle from a model that was tidied
up months ago. Historically that means opening the old file, writing down numbers, and
eyeballing it back. This makes it a tick-box.

Full API research lives in `..._SceneDataTransfer__ApiResearch__.md` — 1,287 catalogued API
entries, 284 gotchas, 130 sources. Read Part 6 of that document before touching this module.

---

## Version History

### 0.1.0 — FIRST STABLE — 26 August 2026

First stable release. Tested end to end: captured in one model, reconstructed in another, with
camera, style, fog, shadows, sections and tag visibility all coming across correctly.

The 0.01, 0.02 and 0.02a entries below are kept as the development trail — they record *why*
each decision was made, and most of those reasons are non-obvious enough to be worth keeping.

**What it does.** Open the model you want scenes *from*, press Capture, save. Open the model
you want them *in*, browse to that `.skp`, tick the scenes and tick which properties to
reconstruct. The source file is read straight off disk — it is never opened, and the model you
are working in is never disturbed.

**Coverage — eight of nine domains live:**

| Domain | Status |
| --- | --- |
| Camera | Working — including parallel projection and ortho height |
| Global axis position | Working |
| Style | Working — creates a genuine named style in the target model |
| Fog | Working |
| Shadows and sun position | Working — geo and north applied once, model-wide |
| Sections and cuts | Working — model-level planes recreated and bound per scene |
| Tag visibility | Working — creates any tag the target model is missing |
| Hidden geometry / objects | Working — flags only, by design |
| Environment (HDRI) | Not built — deferred to 0.2.0 |

**Version requirements.** SketchUp 2026.2 or newer for full function. On 2026.0 / 2026.1
everything works except named style creation, which needs `Sketchup::Style#duplicate`
(2026.2) — scenes still carry the right appearance through their own rendering options, and
the dialog says so rather than failing quietly. Check with:

```ruby
Sketchup.active_model.styles.first.respond_to?(:duplicate)
```

**Numbers.** 19 Ruby files, none over 600 lines. 18 modules. Payload schema `1.1.0`.
Supporting research: 1,287 catalogued API entries, 284 gotchas, 130 sources.

**The five things most likely to bite a future maintainer**, all of which fail *silently*
rather than raising:

1. Writing a page property while its `use_X?` flag is false — the value goes nowhere.
2. Camera assignment out of order — `perspective=` → `aspect_ratio=` → `image_width=` →
   `fov=`/`height=` → `set(eye, target, up)`.
3. Reading `Camera#fov` on a parallel camera, or `#height` on a perspective one — returns a
   stale plausible number instead of raising.
4. Treating `Page#layers` as a visibility list — it is an *exception* list, and it returns
   `nil`, not `[]`, when `use_hidden_layers?` is false.
5. Reusing a path with `DefinitionList#load` — it caches on path and hands back a stale
   definition. Always copy to a unique temp filename first.

Read Part 6 of `..._SceneDataTransfer__ApiResearch__.md` before changing anything.

---

### 0.2.0 — Planned

Environment (HDRI) domain, and a decision on whether nested section planes are worth the world
transform work. Environment parameters are not stored per-Page as independent copies — the
model holds one live `Environment` object per collection entry and a Page stores only a use
flag plus a reference, so reading a non-active page's environment returns the **active** page's
values. Capturing it properly means making each page active with `PageOptions/ShowTransition`
disabled, which is the first thing in this tool that will need to touch the user's viewport.

---

### 0.01 — Foundation and feasibility proof — **TESTED, PASSED**

The whole tool rested on one unproven question: *can Ruby read a model attribute dictionary
out of a `.skp` on disk, without opening it?*

**Answer: not directly — but yes via a carrier component.** Model-level dictionaries written
with `model.set_attribute` do **not** survive `DefinitionList#load` into another model.
Definition-level dictionaries **do**. So the payload is written onto a purpose-built carrier
`ComponentDefinition` with a hidden, locked instance placed in model B's root.

**Test result:** scenes transferred between two models with camera positions reconstructed
exactly. Feasibility confirmed — the architecture is sound and everything else builds on it.

Shipped in 0.01:

| Area | State |
| --- | --- |
| Carrier component write / read | Working |
| External `.skp` probe (temp copy, load, read, unwind) | Working |
| Chunked + deflate/Base64 dictionary codec | Working |
| Camera capture and reconstruction | Working |
| Two-tab dialog, scene tick list, domain toggles | Working |
| `__IMPORTED` suffix with collision counter | Working |
| Settings persistence per model | Working |
| All other domains | Registered but disabled |

Key decisions taken in 0.01, all still load-bearing:

- **Probe hygiene.** The source file is copied to a uniquely named file in `Sketchup.temp_dir`
  for every read, because `DefinitionList#load` caches on path and silently returns a stale
  definition on a second read of the same path. The probe runs inside an operation that is
  always **aborted**, never committed, and the definition count is compared before and after
  so a leak is reported rather than hidden.
- **Never commit-then-undo.** `definitions.remove` inside an operation followed by
  `Sketchup.undo` is a documented crash (api-issue-tracker #75).
- **Flags by name, not by value.** Trimble does not treat `PAGE_USE_*` integer values as
  contractual, so the payload stores constant *names* and rebuilds the mask with
  `Object.const_get` guarded by `const_defined?`. Free forward-compatibility for
  `PAGE_USE_ENVIRONMENT`, graceful degradation on older releases.
- **`Pages#add(name, flags)` snapshot semantics are the whole mechanism.** `add` snapshots
  current state for every bit in `flags` and creates the other slots **off**. Passing only
  `PAGE_USE_CAMERA` yields a scene that overrides the camera and nothing else — exactly the
  "toggle each aspect independently" requirement.
- **Camera assignment order is mandatory.** `perspective=` → `aspect_ratio=` → `image_width=`
  → `fov=`/`height=` → `set(eye, target, up)`. Out of order it fails **silently**.
- **`yaxis` is serialised, not `up`.** `up` can be parallel to the view direction, which is a
  degenerate camera; `yaxis` is recomputed perpendicular and is safe by construction.
- **One undo operation for the whole import.** Since SketchUp 2026.0, editing a page's Camera,
  Axes, RenderingOptions or ShadowInfo is undoable, so a naive import would push hundreds of
  entries onto the undo stack.

Known limitations carried forward:

- Two-point perspective cannot be rebuilt — `is_2d?`, `center_2d`, `scale_2d` are read-only
  with no setters (api-issue-tracker #88, open since 2018). Captured and warned about, not
  silently mangled.
- Reading a large source model is slow, because `definitions.load` pulls the entire model into
  memory. Acceptable for now; a sidecar JSON fast path is the documented escape hatch if it
  becomes a problem.

### 0.02 — Full scene property coverage — **TESTED, PASSED**

Extends capture and reconstruction from camera-only to the full set of properties SketchUp
binds to a scene. Eight of the nine domains are now live; only Environment (HDRI) remains.

| Domain | Serialiser | What crosses |
| --- | --- | --- |
| `camera` | `CameraDomain` | Eye, target, up, projection, FOV / ortho height, aspect |
| `axes` | `AxesDomain` | Axes origin and the three axis vectors |
| `style` | `RenderingDomain` | Every rendering option except fog, plus style name binding |
| `fog` | `RenderingDomain` | `DisplayFog`, `FogColor`, `FogUseBkColor`, `FogStartDist`, `FogEndDist` |
| `shadows` | `ShadowDomain` | Shadow time, light/dark, display flags; geo + north applied once |
| `sections` | `SectionDomain` | Model-level section planes, and which plane each scene activates |
| `tags` | `TagDomain` | Per-scene tag and folder visibility, creating missing tags |
| `hidden_geometry` | `HiddenGeometryDomain` | The hidden-geometry / hidden-objects scene flags |
| `environment` | *(not built)* | Deferred to 0.03 |

Payload schema moves to `1.1.0`. It is **backward compatible** — a 0.01 payload carries only a
camera block and no `model_level` block, and both read back fine.

**The import is now three phases, and the order is load-bearing:**

- **A. Prepare (model-level, once).** Create tags — `Page#set_visibility` needs the Layer to
  already exist. Create section planes — a scene cannot activate a plane that is not there.
  Write latitude, longitude, time zone and north angle — these are **model-wide** in SketchUp,
  so writing them per scene would rewrite the whole model once for every scene imported.
- **B. Scenes.** Create each page with its flag mask, then apply the per-scene domains.
- **C. Restore.** Put back the model's own active section plane. Baking a scene's section
  state requires setting it on the model first, because there is no
  `Page#active_section_plane=`, and that side effect must not be left behind.

All three run inside **one** operation.

New decisions taken in 0.02:

- **A shared `ValueCodec`.** `RenderingOptions` and `ShadowInfo` hand back `Sketchup::Color`
  and `Time`, which JSON cannot represent. Everything crossing the boundary now passes through
  one tagged-envelope encoder so both ends agree in exactly one place. `Time` is stored as an
  integer epoch — any formatted string bakes the exporting machine's time zone into the payload
  and drifts on import.
- **Rendering option keys are enumerated at runtime, never hard-coded.** The key set differs
  between versions (`AmbientOcclusion*` is 2024+/2026+, `FaceColorMode` was removed in 2019.1,
  `DrawHidden*` is 2020+). Source keys are intersected against target keys, so a payload from a
  newer SketchUp cannot raise on an older one, and unsupported keys are reported not swallowed.
- **Shadow writes are driven from an allowlist, not from the payload.** SketchUp 2026.1 made
  `ShadowInfo#[]=` raise `KeyError` on a read-only key where it used to return `false`. A loop
  over the payload's own keys would now raise on `SunDirection`, `SunRise`, `SunSet` and the
  `*_time_t` twins. Driving writes from `NA_PAGE_KEYS` / `NA_MODEL_KEYS` makes that impossible
  by construction.
- **Every rendering and shadow write is individually rescued.** From 2024.0
  `RenderingOptions#[]=` raises `ArgumentError` on a value it rejects. One bad key must not
  abort a whole scene import, so failures are collected into warnings and shown in the dialog.
- **Style transfer is a rendering-options replay, not a file copy.** `Style#save_as` does not
  exist — no Ruby method writes a `.style` file, so a style can be imported from disk but never
  exported. Pages bind with `Page#use_style=`, which takes a **Style object**, not a boolean.
- **Style and Fog share one SketchUp flag** (`use_rendering_options`, labelled "Style and Fog"
  in the Scene Manager). They are kept as separate toggles because the useful case is pulling
  fog across without the whole visual style, but the UI states plainly that ticking either
  enables that one scene property.
- **Tag visibility is serialised as absolute booleans per tag name.** `Page#layers` is an
  *exception list* relative to each tag's `page_behavior`, not a visibility list, and it
  returns `nil` when `use_hidden_layers?` is false. Storing the raw array would make scenes
  invert whenever the target model's tag defaults differ.

Known limitations in 0.02:

- **Section planes nested inside groups or components are not transferred.** Their plane is
  expressed in the container's coordinate system, and recreating that faithfully needs a world
  transform with no counterpart in the target model. They are counted and reported rather than
  silently mangled.
- **Reading a scene's active section plane needs SketchUp 2026.** `Page#active_section_planes`
  is 2026.0+. A model captured on an older release transfers its planes but no scene activates
  one, and the import says so.
- **Per-entity hidden state does not transfer.** The hidden-geometry *flags* travel, but which
  geometry is hidden always comes from the target model — entity identity is not portable
  across models.
- **Watermarks, sketchy-edge stroke sets, background images and photo-match overlays are not
  reachable from Ruby at all.** Only the `DisplayWatermarks` on/off flag and the `EdgeType`
  standard-versus-sketchy switch cross the boundary.
- **Tag folder per-page visibility carries one assumption.** `LayerFolder` publishes no
  `page_behavior`, so a folder listed in `Page#layer_folders` is read as hidden on that page.
  The write side is unambiguous either way, since `set_visibility` takes an absolute boolean.

### 0.02a — Real named styles are now created — **TESTED, PASSED**

**Reported after the first 0.02 test: imported scenes carried the right appearance but no
actual Style appeared in the target model's Styles browser.** Correct for what was built —
0.02 only *bound* a style if one of that name already existed — but not what was wanted.

Researched whether creating a style from Ruby is possible at all. It is the single
most-requested gap in the Styles API (`SketchUp/api-issue-tracker` issue **#1026**), and for
most of the API's life the answer was no: no way to duplicate a loaded style or create one
from scratch, the GUI's "Save as a new Style" had no API equivalent, and the only workaround
was shipping pre-made `.style` files.

**`Sketchup::Style#duplicate` landed in SketchUp 2026.2** — *"creates a copy of the style with
all its properties"*, returning the new `Style`. That is the missing primitive.

New file `01__DomainSerialisers/Na__SceneDataTransfer__StyleFactory__.rb` works down four tiers
per style, in the import's prepare phase, before any page is built:

| Tier | Route | Needs |
| --- | --- | --- |
| 1 | Bind a style of that name already in the target model | any |
| 2 | `Styles#add_style(path, false)` using the captured `Style#path` | 2025.0 + file still on disk |
| 3 | `duplicate` → rename → select → replay options → `update_selected_style` | **2026.2** |
| 4 | Rendering options only, no named style — reported, not hidden | any |

Two details that make tier 3 work:

- **`update_selected_style` commits to whichever style is currently SELECTED**, so the new
  style has to be selected first. `active_style` is only a temporary working copy holding
  uncommitted edits — writing `model.rendering_options` edits *that*, and nothing persists into
  a real style until the commit.
- **Selecting a style changes what the user is looking at.** The original selection is captured
  before any of this and restored in an `ensure` block, so an import never leaves the model
  displaying an imported style. Styles are also created *before* pages, since `pages.add`
  snapshots live model state.

Style creation is a model-level concern, so `style` joined `NA_MODEL_LEVEL_DOMAINS` and the
prepare phase now runs styles first, then tags, then sections, then geo.

**If the SketchUp in use is older than 2026.2, tier 3 is unavailable** and the import falls to
tier 4 — the scenes still look correct, but the Styles browser stays empty. The dialog says so
explicitly rather than failing quietly.

Also trimmed the two Misc Utils button descriptions, which were 461 and 190 characters against
a plugin median of 118.

## File Map

| File | Role |
| --- | --- |
| `..._SceneDataTransfer__Loader__.rb` | Requires sub-modules in dependency order |
| `..._SceneDataTransfer__Schema__.rb` | SSOT for dictionary names, payload keys, capture domains, flag mapping |
| `..._SceneDataTransfer__Codec__.rb` | Chunked / compressed dictionary read and write |
| `..._SceneDataTransfer__Carrier__.rb` | The hidden carrier component, and finding it again after a load |
| `..._SceneDataTransfer__Capture__.rb` | Model B side: walk pages, serialise domains, write payload |
| `..._SceneDataTransfer__Reader__.rb` | Model A side: probe an external `.skp` and unwind cleanly |
| `..._SceneDataTransfer__Rebuilder__.rb` | Model A side: recreate pages from a decoded payload |
| `..._SceneDataTransfer__ModelState__.rb` | Dialog preference persistence per model |
| `..._SceneDataTransfer__DialogManager__.rb` | HtmlDialog lifecycle, payload build, JS callbacks |
| `..._SceneDataTransfer__Run__.rb` | Public entrypoints called by the command router |
| `..._SceneDataTransfer__UiLayout__.html` | Two-tab dialog shell |
| `..._SceneDataTransfer__Styles__.css` | Light Noble Architecture theme |
| `..._SceneDataTransfer__UiBridge__.js` | Domain toggles, scene tick list, persistence round-trip |
| `..._SceneDataTransfer__ApiResearch__.md` | The API reference this module was built from |
| `01__DomainSerialisers/` | One file per capture domain — see below |

### Domain serialisers

| File | Domain key | Since |
| --- | --- | --- |
| `Na__SceneDataTransfer__CameraDomain__.rb` | `camera` | 0.01 |
| `Na__SceneDataTransfer__ValueCodec__.rb` | *(shared helper)* | 0.02 |
| `Na__SceneDataTransfer__AxesDomain__.rb` | `axes` | 0.02 |
| `Na__SceneDataTransfer__RenderingDomain__.rb` | `style`, `fog` | 0.02 |
| `Na__SceneDataTransfer__ShadowDomain__.rb` | `shadows` | 0.02 |
| `Na__SceneDataTransfer__SectionDomain__.rb` | `sections` | 0.02 |
| `Na__SceneDataTransfer__TagDomain__.rb` | `tags` | 0.02 |
| `Na__SceneDataTransfer__HiddenGeometryDomain__.rb` | `hidden_geometry` | 0.02 |

Adding a domain is three edits: a record in `NA_CAPTURE_DOMAINS`, a branch in
`Capture.na_capture_domain`, and a branch in `Rebuilder.na_apply_domain`.

---

## Model Dictionary Schema

Two **separate** dictionaries on `Sketchup::Model`. Keeping them apart matters — one travels
between models, the other is just this user's dialog state.

### `Na__SceneDataTransfer` — the payload

Written to both the model **and** the carrier component definition.

```
schema_version          1.1.0
captured_at             26-Aug-2026 14:32
captured_by             Na Noble3d Tools Scene Data Transfer 0.1.0
source_model_name       ProjectModel__RevC
source_model_path       D:/Project/ProjectModel__RevC.skp
source_model_guid       {guid}
sketchup_version        26.0.x
scene_count             24
domains_captured        camera,axes,style,fog,shadows,sections,tags
payload_encoding        raw | deflate_base64
payload_chunk_count     3
payload_byte_length     48211
payload_0000            <chunk>
payload_0001            <chunk>
payload_0002            <chunk>
```

The header keys duplicate values already inside the JSON. That is deliberate: it keeps the
dictionary legible in SketchUp's native attribute inspector, and lets the reader summarise a
source model without paying to decompress the whole payload.

Chunks are reassembled strictly by walking `0...chunk_count`, **never** by iterating the
dictionary — `AttributeDictionary#each` gives no ordering guarantee. Stale chunks are deleted
before every write, or an old longer payload would leave orphans that bloat the file forever.

### `Na__SceneDataTransfer__UiState` — dialog preferences

```
source_model_path       last source .skp chosen in the Import tab
selected_domains        JSON array of ticked domain keys
selected_scenes         JSON array of ticked source scene names
name_suffix             __IMPORTED
last_import_time        26-Aug-2026 15:10
last_import_count       12
last_capture_time       26-Aug-2026 14:32
last_capture_count      24
```

All preference writes run inside a **transparent** operation
(`start_operation(name, true, false, true)`), so remembering settings never adds a stray step
to the user's undo stack.

---

## Notes and Traps

- **The carrier component is not optional and must not be deleted.** `definitions.load`
  reconstructs the source model's *root entities*; a definition with no placed instance is not
  reachable from that reconstruction, and is a casualty of any Purge Unused. It is a
  `ComponentInstance`, not a Group, because a group's definition is silently made unique on
  edit, which would orphan the attributes.
- **Capture does not survive without a save.** The payload only reaches the `.skp` when the
  user saves model B. The dialog says so in the capture callout.
- **Instance attributes are lost on export.** Always `instance.definition.set_attribute`.
- **`Hash` cannot be stored in an attribute.** Permitted types are Boolean, Integer, Float,
  Length, nil, String, Time, Array, `Geom::Point3d`, `Geom::Vector3d`. Everything structural
  goes in as a JSON String.
- **"Style and Fog" is one SketchUp flag.** `use_rendering_options` covers both, so ticking
  either domain enables the scene's Style-and-Fog property. The UI states this rather than
  pretending they are independent.
- **North angle, latitude and longitude are model-level, not page-level.** Writing them in a
  per-scene loop silently mutates the whole target model once per scene, so they are applied
  once per import.
- **`Page#layers` is an exception list, not a visibility list.** Absolute booleans per tag name
  are serialised instead, or scenes invert when the target model's tag defaults differ.
