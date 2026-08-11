# Na__ValeLantern__Importer - DEVLOG
# =======================================================================================

**Loader:** [`Na__ValeLanternImporter__Loader.rb`](../Na__ValeLanternImporter__Loader.rb)
**Entry Point:** `Na__ValeLantern.na_import`
**Companion:** Vale Lantern Designer web application, `02__Src__AppModules/80__System__SketchUpExport`

Reconstructs a Vale roof lantern in SketchUp from a millimetre build payload written by
the Lantern Designer web application. The payload is a fully resolved build recipe, not a
configuration: every mitre, plumb cut and eaves extension is applied by the web
application's geometry brain before the file is written, and this plugin's whole job is
to turn point lists into faces. There is no geometry maths in this plugin, and there is
never to be any.

## Version History

# =======================================================================================


# ---------------------------------------------------------
### Vale Lantern Importer - Version 1.2.0 - 11-Aug-2026
#### Na__DataLib Construction Linework Standard, Edge Colours and Tag Line Styles

- **New DataLib object consumed**: `Na__DataLib__CoreIndex__EdgeMaterials__.json` gains a
  sibling object `Na__DataLib__CoreIndex__ConstructionLinework` carrying the series
  `MTE300__ConstructionLineSeries__`. Fourteen entries, one per setting out class, each
  carrying the edge colour **and** the line type together, plus the MTE material name,
  the tag name and `SourceStyleKey` — the web application's own `Class__Family` key,
  which is how the two sides look each other up without either knowing the other's
  naming.
- **A sibling object, not another MTE series**: `na_flatten_mte_series` in
  `Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb` walks every series inside
  `Na__DataLib__CoreIndex__EdgeMaterials` into its swatch palette. Fourteen lantern datum
  colours added as an MTE series would have appeared as fourteen new swatches in the Edge
  Painter UI. A sibling object is invisible to that flattening.
- **New module: `Na__ValeLantern__Importer__DataLibBridge__.rb`**: Loads the standard
  through `Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials)` — the same web
  URL, thirty minute temp cache, local plugins-folder fallback path the Edge Painter
  uses. Requires the DataLib with the same `require_relative '../../../Na__Common__DataLib…'`
  depth as Element Assembly Studio Pro, guarded by `rescue LoadError` so a machine without
  the DataLib still imports using the payload's own colours.
- **DataLib wins, payload is the fallback**: A model may hold linework from three lantern
  exports made three months apart and they must all look the same, so the standard is
  authoritative wherever it can answer. A setting out class the standard has never heard
  of keeps the payload's colour, which means a new class added to the web application
  imports correctly before the standard catches up.
- **Edge colours applied per EDGE, not per group**: `edge.material =` is the same call
  `Na__EdgeUtil__PaintDeepNestedEdges` makes, and is the reason an imported datum is
  recognisable to that tool afterwards. A group material cascades to faces and does
  nothing for edges.
- **Tag line styles applied via the legal API**: `layer.line_style =` takes a
  `Sketchup::LineStyle` object fetched by name from `Sketchup.active_model.line_styles`,
  guarded on `respond_to?` for pre-2019. Names come from the standard, which took them
  from `Na__DataLib__CoreIndex__Tags__.json` -> `LineStyleReference.AvailableLineStyles`.
- **SketchUp has TWO line style vocabularies and only one is valid here**: The Styles
  panel edge rendering set lives in `CLineStyleManager` (`Solid Basic`, `Dotted Basic`,
  `Short Dashes Basic`, `Long Dashes Basic`, `Dot Dash Basic`, `Center Basic`,
  `Demolition Basic`). The Tags panel Dashes set lives in `CCustomLineStyle` (eleven dash
  patterns plus `Solid Basic`) and is the one `Layer#line_style=` reads. Using a name from
  the wrong set fails **silently** — the tag stays solid and nothing raises.
- **Line style names are CASE SENSITIVE**: `Dash dot` is legal. `Dash Dot` is not. This
  was caught before release; the first draft of the exporter config used `Dash Dot` and
  every datum tag would have imported looking correct and been solid.
- **Edge Painter swap-off protection**: All fourteen setting out tag names added to
  `Na__DataLib__CoreIndex__Tags__.json` -> `ExportExclusions.AdvancedSwapOffTagNames`, and
  every standard entry carries `EdgePainting__AdvancedSwapOff: true`. Without this, Apply
  Line Thickness Tags finds an MTE colour with no entry in
  `03__LayoutDrawingLineworkTags__` and moves the edge to Untagged, stripping the setting
  out tags off an imported lantern.
- **Standard forgotten on module reload**: `na_load_modules` calls
  `Na__DataLibBridge.na_reset` after the chain loads, so editing the local fallback JSON
  and re-pasting the loader picks the change up rather than serving a stale lookup.

**Requires pushing to GitHub before the standard is served from the web:**
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__EdgeMaterials__.json`
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json`

Until then the local plugins-folder fallback serves both, so the plugin works now and the
push only changes where the data comes from.

**Files Created:**
- `02__Src__AppModules/02__AppData/Na__ValeLantern__Importer__DataLibBridge__.rb`

**Files Modified:**
- `02__Src__AppModules/01__AppCore/Na__ValeLantern__Importer__Main__.rb` (DataLibBridge added to the module chain ahead of TagManager, `na_reset` on reload, dependency notes)
- `02__Src__AppModules/03__AppUtils/Na__ValeLantern__Importer__TagManager__.rb` (`na_apply_standard` overlays the DataLib tag name / swatch / line style onto a payload tag row carrying a `StyleKey`, `na_apply_line_style` with LineStyles lookup and respond_to guards)
- `02__Src__AppModules/04__GeometryBuilders/Na__ValeLantern__Importer__LineBuilder__.rb` (`na_paint_edges` applies the MTE edge material per edge)
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__EdgeMaterials__.json` (new `Na__DataLib__CoreIndex__ConstructionLinework` object, additive only; existing MTE library and meta byte-identical)
- `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json` (fourteen tag names appended to `ExportExclusions.AdvancedSwapOffTagNames`, additive only)
# ---------------------------------------------------------


# ---------------------------------------------------------
### Vale Lantern Importer - Version 1.1.0 - 11-Aug-2026
#### Setting Out Linework, Import Options and Data-Driven Sub-Groups

- **Third part kind: `linework`**: A set of open or closed polylines built as edges with
  no faces and no material. Carries the datums, derivation triangles and member
  centrelines the web application's 3D Setting Out view draws.
- **New module: `Na__ValeLantern__Importer__LineBuilder__.rb`**: Builds each polyline with
  `entities.add_edges`, which takes the whole point run at once and shares vertices along
  it. Closed polylines get their first point appended. Consecutive points closer than
  SketchUp's own tolerance are dropped, so a construction triangle whose rise is zero
  becomes a single line rather than handing `add_edges` a zero-length segment to reject.
- **Edges rather than `Sketchup::ConstructionLine` guides**: A guide cannot carry a
  colour, and the whole value of this linework is that a ridge datum reads red and a hip
  triangle green before any label is read. Guides are also wiped as a set by
  Edit > Delete Guides, which would take the user's own guides with them, and tags carry
  dash patterns while guides do not.
- **Three import routes, one exported file**: `na_import` builds the metal alone,
  `na_import_with_setout` builds both, `na_import_setout_only` builds the linework alone
  to drop over a lantern already in the model. All three reach `na_compose(payload, choices)`.
- **Filtered on assembly `Role`, not on key**: An assembly whose `Role` is `settingOut` is
  construction linework; anything else is metal. The exporter can add a second class of
  linework later without this plugin learning its name.
- **Honest part counts**: `na_expected_for_choices` counts the parts in the ADMITTED
  assemblies rather than reading the payload's own total, so a setting out only import
  does not report itself as having dropped four hundred parts.
- **Data-driven intermediate groups**: A part carrying a `GroupKey` is nested one level
  deeper in a group created on first use, which turns twenty two glaze bar centrelines
  into one collapsible outliner entry instead of twenty two siblings. This plugin carries
  no list of what those groups should be. Empty intermediate groups are pruned afterwards,
  because a subgroup is created before its first part is attempted.
- **Datum checks travel into the model**: The web application's sixteen setting out checks
  (measured against reported, with delta, tolerance and pass or fail) are stamped onto the
  setting out assembly group, so a file found six months later still says whether it
  agreed with itself at the moment it was exported.
- **Construction triangles carry their own numbers**: Each triangle group carries measured
  run, rise, hypotenuse and pitch plus the solver's reported counterparts, readable in
  Entity Info without measuring anything.
- **Menu restructured**: `Plugins > Vale Lantern Importer` now carries Import Lantern
  Build File, Import with Construction Linework, Import Construction Linework Only, a
  separator, and the verbose variant.

**Files Created:**
- `02__Src__AppModules/04__GeometryBuilders/Na__ValeLantern__Importer__LineBuilder__.rb`

**Files Modified:**
- `02__Src__AppModules/01__AppCore/Na__ValeLantern__Importer__Main__.rb` (LineBuilder in the module chain, `na_import(file_path, choices)`, `na_import_with_setout`, `na_import_setout_only`, namespace convenience entry points)
- `02__Src__AppModules/05__Assembly/Na__ValeLantern__Importer__ModelComposer__.rb` (`na_resolve_choices`, `na_admitted_assemblies`, `na_expected_for_choices`, `linework` kind dispatch, `na_entities_for_part` lazy sub-groups, `na_prune_empty_subgroups`, `na_stamp_all` for assembly attributes)
- `Na__ValeLanternImporter__Loader.rb` (three import menu items plus separator)
# ---------------------------------------------------------


# ---------------------------------------------------------
### Vale Lantern Importer - Version 1.0.0 - 11-Aug-2026
#### Initial Release - Payload Import and Solid Reconstruction

- **The build recipe contract**: The payload carries fully resolved millimetre vertices,
  not a lantern configuration. The obvious alternative - export width, depth, pitch and
  bar spacing and solve it in Ruby - would be a second geometry brain in a second language
  that has to agree with the first one forever, and would not. A change to how a hip meets
  a ridge lands in the web application's solver, flows through its 3D viewport and this
  importer together, and needs no plugin update at all.
- **Two part kinds cover every solid**: `prism` is two rings of millimetre points plus the
  ring spans saying which run of each is an outer loop and which is a hole. A glaze bar, a
  mitred head beam, a hollow builders upstand and a pane of glass are all that shape.
  `instance` is a placed copy of a mesh definition given as an origin and three axis
  vectors.
- **Prism build order is walls, caps, clean, orient**: Walls are one quad per section edge
  in the order the payload gives them, which faces outward on the holes as well as the
  outside because the section winding is normalised upstream (outer loops counter
  clockwise, holes clockwise). Caps are added AFTER the walls so the hole loops already
  exist as edges in the cap plane; where SketchUp does not read them as inner loops on its
  own, the hole face is added and immediately erased, leaving the loop behind because the
  wall faces still need its edges.
- **Coplanar edge merge**: An extruded aluminium section has long flat faces crossed by a
  vertex every few millimetres, and without this pass every one of those leaves a line
  down the middle of a flat surface. The edge list is snapshotted before anything is
  erased, because erasing an edge merges its two faces and invalidates both references.
- **Outward orientation by SIGNED VOLUME, not the centroid test**: The usual trick of
  comparing each face normal against the vector from the lump centre to the face centre is
  correct only on a convex solid. A cornice, a glaze bar trim and a lead flashing are
  emphatically not convex, and on those the centroid test reverses faces that were already
  right. Summing the signed volume over `face.mesh` triangulation reads the shell as a
  whole and is exact for any closed shape. An open shell sums near zero and is left alone.
- **Component definitions built from face LOOPS, not triangles**: The asset's own loops are
  carried through as loops with inner loops punched as holes, which is the difference
  between a finial that can be push-pulled and a triangle soup that can only be looked at.
  One definition per asset however many anchors it is placed at.
- **Three level hierarchy and no more**: Root lantern group, one group per assembly, one
  group per physical part. Enough to select a whole lantern, a whole system or one length
  of head beam, and shallow enough that the outliner is still readable.
- **The whole import is one operation**: `start_operation` with the disable-UI flag turns
  four hundred group creations into one undo step and stops SketchUp redrawing between
  each. A failure part way through aborts and leaves the model exactly as it was rather
  than leaving half a lantern to clean up by hand.
- **Tags and materials come from the PAYLOAD, not from this plugin**: The vocabulary is in
  the payload's Tags and Materials tables, generated from the web application's config, so
  a tag renamed or recoloured there is renamed and recoloured in SketchUp on the next
  export with no plugin edit. Existing tags and materials of the same name are adopted,
  never repainted: importing a second lantern must not restyle the first, and a swatch the
  user has tuned by hand is not this tool's to overrule.
- **Schema major/minor rule**: The reader refuses a MAJOR it was not written against and
  accepts any MINOR or PATCH. A new part kind or optional field is a MINOR bump, where an
  older importer ignoring what it does not recognise still builds a correct if less
  complete lantern. A field changing meaning is a MAJOR bump, where an older importer would
  build something confidently wrong and must not try.
- **Failures are counted and named, never raised**: One bad prism out of four hundred must
  not cost the other three hundred and ninety nine. `Na__DebugTools` keeps the tally and
  prints the closing report with every refused part named.
- **RUBY GOTCHA - constant assignment inside a method is a SyntaxError**: `Na__Main`
  originally resolved its collaborators as `DebugTools = Na__ValeLantern::…` inside
  `na_import`, which will not parse. Module-level constants were not an option either
  because this file loads before the modules it names. Resolved to local variables.
- **RUBY GOTCHA - reload warning spam**: Every module resolves its collaborators into
  module level constants at load time, so `load`ing the chain again re-assigns each of
  them and Ruby says so about twenty times, burying the import report. `$VERBOSE` is
  suppressed across the chain load and restored in an `ensure`, in one place, rather than
  guarding twenty constants.
- **`load` not `require` throughout**: Re-pasting the one line loader genuinely reloads
  every module. `require` would remember the path and quietly do nothing, which is the
  exact opposite of what somebody re-pasting a loader wants. The `file_loaded?` guard is
  keyed to the MENU registration only, because SketchUp cannot remove a menu item once
  added and a second paste would otherwise leave two of everything.
- **Picker remembers its folder**: `Sketchup.read_default` / `write_default` on the last
  import directory, because a build file lands in the same downloads folder every time.
- **Result is selected and zoomed**: The lantern lands at the model origin, which on a
  model that already holds a building can be a long way off screen. Selecting it also means
  the first thing the user does, moving it into place, is one drag away.

**Files Created:**
- `Na__ValeLanternImporter__Loader.rb` (Plugins folder root)
- `02__Src__AppModules/01__AppCore/Na__ValeLantern__Importer__Main__.rb`
- `02__Src__AppModules/02__AppData/Na__ValeLantern__Importer__PayloadReader__.rb`
- `02__Src__AppModules/03__AppUtils/Na__ValeLantern__Importer__Units__.rb`
- `02__Src__AppModules/03__AppUtils/Na__ValeLantern__Importer__DebugTools__.rb`
- `02__Src__AppModules/03__AppUtils/Na__ValeLantern__Importer__TagManager__.rb`
- `02__Src__AppModules/03__AppUtils/Na__ValeLantern__Importer__MaterialManager__.rb`
- `02__Src__AppModules/04__GeometryBuilders/Na__ValeLantern__Importer__PrismBuilder__.rb`
- `02__Src__AppModules/04__GeometryBuilders/Na__ValeLantern__Importer__MeshBuilder__.rb`
- `02__Src__AppModules/05__Assembly/Na__ValeLantern__Importer__ModelComposer__.rb`
# ---------------------------------------------------------


# =======================================================================================
## Reference

### Module Chain and Load Order

Each module resolves its dependencies into constants at load time, a pattern taken from
Element Assembly Studio Pro, where it makes every call site read as a plain module name
rather than a fully qualified path. The cost is that a module loaded before its dependency
raises a `NameError` immediately, so the order below is a contract rather than a
convenience.

| Order | Module | Lines | Depends On |
|---|---|---|---|
| 1 | `Na__Units` | 98 | none |
| 2 | `Na__DebugTools` | 157 | none |
| 3 | `Na__DataLibBridge` | 286 | DebugTools, optional `Na__DataLib` install |
| 4 | `Na__TagManager` | 210 | DebugTools, DataLibBridge |
| 5 | `Na__MaterialManager` | 145 | DebugTools |
| 6 | `Na__PayloadReader` | 259 | DebugTools |
| 7 | `Na__PrismBuilder` | 428 | DebugTools, Units, TagManager, MaterialManager |
| 8 | `Na__MeshBuilder` | 322 | the same four |
| 9 | `Na__LineBuilder` | 234 | DebugTools, Units, TagManager, DataLibBridge |
| 10 | `Na__ModelComposer` | 376 | everything above |

`Na__Main` (327 lines) owns the chain and is loaded by `Na__ValeLanternImporter__Loader.rb`
(117 lines) at SketchUp start.

### Console Entry Points

```ruby
Na__ValeLantern.na_import                # the metal alone
Na__ValeLantern.na_import_with_setout    # metal plus construction linework
Na__ValeLantern.na_import_setout_only    # linework alone, to check an existing model
Na__ValeLantern.na_import_verbose        # per part reporting: every prism, every
                                         # coplanar merge, every face the API refused
```

Reload after editing any module, without restarting SketchUp:

```ruby
load "C:/Users/adamw/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/Na__ValeLanternImporter__Loader.rb"
```

### Coordinate Space

Millimetres throughout. Origin at the centre of the lantern footprint at builders upstand
BASE level, `+X` width, `+Y` depth, `+Z` up. That is the web application's SkeletonSolver
convention unchanged, and it maps straight onto SketchUp's own Z-up axes with no swap,
only a scale by `1/25.4`. The Three.js environment's axis swap appears nowhere in this
plugin.

### Attribute Dictionary

Every group carries its payload attributes in the `VghLantern` dictionary, so a downstream
report can walk a model and pick out Vale lantern parts without matching on group names.
`RecordType` is `ValeLanternRoot`, `ValeLanternAssembly` or `ValeLanternPartGroup`.

### Tag Line Style Names - Do Not Guess These

`Layer#line_style=` takes a `Sketchup::LineStyle` object fetched by name from
`Sketchup.active_model.line_styles`. Names are **case sensitive** and a name the running
SketchUp does not carry fails **silently**, leaving the tag solid.

Authoritative list: `Na__DataLib__CoreIndex__Tags__.json` -> `LineStyleReference.AvailableLineStyles`.

Do NOT use the Styles panel line style names (`Dotted Basic`, `Short Dashes Basic`,
`Dot Dash Basic`, `Center Basic`, `Demolition Basic`). Those belong to a different
subsystem and are not valid for tags.

# =======================================================================================
# END OF FILE
# =======================================================================================
