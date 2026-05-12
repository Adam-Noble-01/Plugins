# Na__SelectionStats - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================
## Selection Statistics Version 1.1.1 - 12-May-2026

### SketchUp Names + Dynamic Component Key/Value Reporting

- Added **`Na__SelectionStats__StatsBuilder__NameAndDynamicAttributeCollector__.rb`**
  under `12__Core__StatsBuilder`.
- The recursive walk now reports named SketchUp owners alongside existing geometry stats:
  - group names / group instance names
  - component definition names (`definition.name`)
  - component instance names (`instance.name`)
  - generic instance names for any named SketchUp owner that responds to `name`
- Dynamic Component attributes are now collected from both selected / nested entities and
  their component or group definitions when dictionaries named `dynamic_attributes` or
  `_dynamic_attributes` are found.
- The live HtmlDialog gains two new sections:
  - **SketchUp Names**
  - **Dynamic Component Attributes**
- Markdown export now includes matching **SketchUp Names** and **Dynamic Component Attributes**
  tables so exported reports preserve the same name and key/value data shown in the HUD.
- The new rows use the existing truncation path (`MAX_LIST_ITEMS`) so large models do not flood
  the dialog bridge or Markdown export.

#### Files Touched

| Path | Purpose |
|---|---|
| `12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__NameAndDynamicAttributeCollector__.rb` | New collector for names and Dynamic Component key/value rows |
| `01__AppCore/Na__SelectionStats__AppCore__Main__.rb` | Added `@delegate` and require for the new collector |
| `12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__Main__.rb` | Added `sketchup_names` and `dynamic_attributes` payload arrays |
| `12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__EntityWalker__.rb` | Calls collector during recursive entity/definition traversal |
| `Na__SelectionStats__UiLayout__.html` | Renders the new HUD sections |
| `20__System__GenerateReport__MarkdownFile/Na__SelectionStats__GenerateReport__MarkdownFile__Main__.rb` | Adds matching Markdown sections |

# =======================================================================================
## Selection Statistics Version 1.1.0 - 12-May-2026

### Markdown Report Export (.md via UI.savepanel)

- Added **`20__System__GenerateReport__MarkdownFile`** with
  **`Na__SelectionStats__GenerateReport__MarkdownFile__Main__.rb`**
  (`Na__SelectionStats::Na__GenerateReport::Na__MarkdownFile`).
- Public wiring:
  - **AppCore** now `require_relative` + `@delegate` breadcrumb ahead of observers / DialogManager,
    plus alias `MarkdownReport` for IntelliSense parity with sibling apps.
  - **DialogManager** registers HtmlDialog **`na_generateMarkdownReport`** Ruby callback **each time**
    the HtmlDialog shell is instantiated, and exposes **`na_push_report_status`** (`JSON.generate` payloads
    feeding `execute_script`) so Markdown export flows can safely update the HUD without assuming ivar captures.
  - **Ui layout** grows a grouped header row (**Export Markdown Report…** primary), a dedicated **`#report-status`**
    channel (`NaSelectionStatsSetReportStatus(kind, message)` tones: `busy|success|error|muted`),
    resilient click binding `(function NaSelectionStatsBindReportExport(){…})()`, and tightened warning rendering when
    the JSON payload mixes **string alerts with `{ truncated: true, omitted_count: n }`** marker rows sourced from `na_trim_array`.
- Markdown document structure produced by **`na_build_markdown_report`**:
  - Title + bullets (extension name, SketchUp version, `{model_title}`, HUD clock stamp, authoritative UTC epoch string for reports, recursive selection-root count).
  - Sectioned Markdown tables (**Summary**, **Materials** including slot rollup, **Entity types**, paired dictionary exports, warnings with optional truncation sentinel).
  - Robust cell escaping (**pipe + newline sanitisation**) so downstream Markdown renderers do not rupture alignment.
  - Saves through **`UI.savepanel('Save Selection Statistics Report (.md)', '', suggested_slug)`**, default filename skeleton
    `#{slugged_model_title}__Na__SelectionStats_Report__YYYYMMDDHHMMSS.md`, tolerant `.md` auto-append if SketchUp feeds a bare basename.
  - UTF-8 `File.write`; console echo mirrors success / failure beside dialog status pings.
- Behaviour check: cancelling the SketchUp browse dialog leaves the dialog status on **muted** (`Save cancelled`).
- Files touched besides the new **`20__...__MarkdownFile`** module:
  **`AppCore Main`**, **`DialogManager Main`**, **`Na__SelectionStats__UiLayout__.html`**.

#### Verification checklist (extension session)

| Step | Expected |
|---|---|
| Reload Ruby / restart SketchUp after dropping the new folders | Loads without `LoadError`; Console shows `[+] NA Selection Statistics loaded successfully` via loader shim |
| Toggle selection + open dialog HUD | Existing metrics still refresh (`na_refresh_dialog`) |
| Click **Export Markdown Report…**, save to Desktop | HUD success tone + Markdown file renders tables in Cursor / VS Code |
| Repeat export and hit **Cancel** in savepanel | HUD muted confirmation (`Save cancelled`) |

# =======================================================================================
## Selection Statistics Version 1.0.0 - 12-May-2026

### Modular Architecture Split + Noble Architecture Loader Pattern

Split the legacy monolithic SketchUp bootstrap (`Na_SelectionStats__Launcher__.rb`,
`AdamNoble::NaSelectionStats`) into a payload tree under `Na__SelectionStats__Modules__`
and a thin root loader, matching how **Element Assembly Studio Pro**
(`Na__ElementAssemblyStudioPro__Loader.rb` -> `Na__ArchTools__ElementAssemblyStudioPro__Modules__`)
and **Na__ProfileTools__ProfilePathTracer** resolve paths, gate `require`, and defer
lifecycle to AppCore.

#### Entry Wiring

| Concern | Lives where |
|---|---|
| SketchUp Plugins autoload shim | `../Na__SelectionStats__Loader__.rb` (REGION blocks: path gate, Command, Extensions + Toolbar, `file_loaded`) |
| `require_relative` orchestration | `02__Src__AppModules/01__AppCore/Na__SelectionStats__AppCore__Main__.rb` (`@delegate` breadcrumbs to Stats/Core) |
| Public entry (`na_init`) | `Na__SelectionStats.na_init` opens dialog via DialogManager |

#### Module Map (Ruby)

| Domain | Purpose |
|---|---|
| `Na__AppData::Na__Constants` | Strings, preferences key, list caps (`MAX_LIST_ITEMS`, `MAX_DICTIONARY_KEYS`, `WARNINGS_TRUNCATE_AFTER`) |
| `Na__AppUtils::Na__EntityHelpers` | `valid?`/token/typename/component-name/model-title helpers |
| `Na__AppUtils::Na__DataFormatters` | Material-hash projection, sorted name/count rows, truncation sentinel row |
| `Na__GeometryHelpers::Na__FaceAnalysis` | Triangulated mesh polygon fan count; native triangle/quad loop checks |
| `Na__DictionaryCollector` | Attribute dictionary rows (+ key preview cap) |
| `Na__MaterialTracker` | Front/back slot counts and entity paint buckets |
| `Na__EntityWalker` | Recursive walk: selection roots, groups, instances (cycle-guard via definition stack), faces/edges/vertices |
| `Na__StatsBuilder` | Builds empty stats/trackers; drives walk; trims + sorts for HtmlDialog JSON |
| `Na__SelectionStats__SelectionObserver` | SelectionObserver -> `Na__DialogManager.na_refresh_dialog` |
| `Na__DialogManager` | `UI::HtmlDialog`, observer attach/detach, `JSON.generate` + `execute_script` |

#### UI Asset

| Asset | Purpose |
|---|---|
| `Na__SelectionStats__UiLayout__.html` | Single-file dark-theme panel; exposes `window.NaSelectionStatsSetData` for Ruby bridge |

Previously the HTML lived in a heredoc (`set_html`). The dialog now uses `set_file` so the shell
tracks the standalone file under `Na__SelectionStats__Modules__` root (parity with HtmlDialog shells
placed next to sibling style/script folders on larger Noble Architecture tools).

#### Namespacing Convention

Top-level Ruby namespace is **`Na__SelectionStats`** (`Na__` double-underscore Noble Architecture prefix).
Subsystem modules use **`na_*`** instance-style helpers behind `extend self` rather than scattering
bare methods on Kernel.

#### Code Regions

All Ruby beneath `Na__SelectionStats__Modules__` carries `# REGION | ...` / `# endregion`
banners aligned with Element Assembly Studio / ProfilePathTracer housekeeping.

#### Behaviour Preserved Across Refactor

- Recursive aggregation with per-instance-path de-duplication keys (`persistent_id` / `entityID` /
  object-id fallback).
- Component-definition recursion skips when definition token already on stack (warns rather than looping).
- JSON payload shape unchanged for the embedded JS renderer (symbol keys stringify through `JSON.generate`).

#### Operational Notes

- Extensions menu behaviour from the retired launcher remains available; the loader additionally
  registers a small toolbar mirroring Assembly Studio ergonomics (`TB_HIDDEN` restore).
- Restart SketchUp (or Developer Tools reload) after swapping loader filenames so `file_loaded?`
  guards do not leave stale registrations.

---

#### Files Touched (First Modular Drop)

**New / active**

| Path |
|---|
| `Plugins/Na__SelectionStats__Loader__.rb` |
| `Na__SelectionStats__Modules__/Na__SelectionStats__UiLayout__.html` |
| `02__Src__AppModules/01__AppCore/Na__SelectionStats__AppCore__Main__.rb` |
| `02__Src__AppModules/02__AppData/Na__SelectionStats__AppData__Constants__.rb` |
| `02__Src__AppModules/03__AppUtils/Na__SelectionStats__AppUtils__EntityHelpers__.rb` |
| `02__Src__AppModules/03__AppUtils/Na__SelectionStats__AppUtils__DataFormatters__.rb` |
| `02__Src__AppModules/04__GeometryHelpers/Na__SelectionStats__GeometryHelpers__FaceAnalysis__.rb` |
| `02__Src__AppModules/10__Core__SelectionObserver/Na__SelectionStats__SelectionObserver__.rb` |
| `02__Src__AppModules/11__Core__DialogManager/Na__SelectionStats__DialogManager__Main__.rb` |
| `02__Src__AppModules/12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__Main__.rb` |
| `02__Src__AppModules/12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__EntityWalker__.rb` |
| `02__Src__AppModules/12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__MaterialTracker__.rb` |
| `02__Src__AppModules/12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__DictionaryCollector__.rb` |
| `Na__SelectionStats__DEVLOG__.md` (this entry)

**Removed**

| Path |
|---|
| `Plugins/Na_SelectionStats__Launcher__.rb`

#### Verification Checklist

- Open **Extensions ▸ NA Selection Statistics** (or toolbar) on a heavy nested component selection;
  triangles / dictionaries / warnings populate without console errors.
- Change selection repeatedly; observer-driven refresh keeps counts in sync (`na_refresh_dialog` path).
- Close dialog; reopen from menu — `@dialog` nil reset via DialogManager closure (`instance_eval`
  shim prevents HtmlDialog capturing the wrong implicit `self` for ivar clears).

---

## Related Context (Companion Plugin DEVLOG Patterns)

Structural inspiration for headings, separators, module-audit tables, and verification bullets:

| Reference DEVLOG |
|---|
| `Na__ProfileTools__ProfilePathTracer__Modules__/Na__ProfileTools__ProfilePathTracer__DEVLOG__.md` |
| `Na__ArrayBuilderTools__Modules__/Na__ArrayBuilder__DEVLOG__.md` |
| `Na__ToScaleOrthoTextureMaker__Modules__/Na__ToScaleOrthoTextureMaker__DEVLOG__.md` |
| `Na__ArchTools__ElementAssemblyStudioPro__Modules__/85__Docs__AppDocumentation/Na__AssemblyStudio__DEVLOG__.md` |

# =======================================================================================

# END OF DEVLOG
