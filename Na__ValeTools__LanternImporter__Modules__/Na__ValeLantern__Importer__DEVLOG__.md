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
### Vale Lantern Importer - Version 1.5.0 - 12-Aug-2026
#### FEATURE - Reload on the Right Click Menu

1.4.0 put the reload on the Plugins menu, which is four clicks away from a lantern you are
already pointing at. This puts it on the right click menu, and only when the thing being
right clicked is a Vale lantern.

- **NEW `Na__ContextMenu`**, loaded last in the chain. Two items, appearing only when the
  click resolves to a lantern:

  | Item | Behaviour |
  |---|---|
  | `Reload Lantern Json...` | opens the file picker, rebuilds in place |
  | `Regenerate Lantern from '<file>'` | rebuilds from the file it was last built from, no picker |

- **THE HANDLER IS REGISTERED IN THE LOADER, NOT IN THE MODULE THAT BUILDS IT**, inside the
  same `file_loaded?` guard as the Plugins menu items, and for a sharper version of the same
  reason. `UI.add_context_menu_handler` has no counterpart: no remove, no replace, no way to
  enumerate what is already registered. Every module here is `load`ed so a re-paste of the
  one line loader picks up edits, so a registration living in a chain module would run again
  on every re-paste and a developer who reloaded four times would be looking at four Reload
  Lantern Json items on every right click. A module level "have I registered" flag cannot fix
  it either, because the same reload re-initialises the flag.
- **The single handler resolves the builder BY NAME on each click** rather than capturing it.
  That indirection is the point: one handler exists forever, and editing `Na__ContextMenu`
  still takes effect on the next right click.
- **The handler swallows everything**, and guards on `defined?` before calling. An exception
  raised from a context menu handler is raised again on every subsequent right click, so a
  chain that failed to load would otherwise break the right click menu of every model in
  the session - including ones this plugin is not being used in.

**NO MODEL DICTIONARY, AND WHY NOT**

The suggestion was a register in the model's own attribute dictionary, written at import
time, of the sort Element Assembly Studio Pro keeps. It was considered and deliberately not
built, because the question this menu has to answer is not the question a register answers.

- **The question is "is the thing under the cursor part of a lantern", not "does this model
  contain one"**, and the first is already answered in CONSTANT time by the stamp the
  importer puts on the lantern itself: read `RecordType` off the clicked entity, or off its
  definition, and climb if it is nested. There is no scan, so there is nothing to cache.
- **A register would be a second copy of a fact the lantern already carries, and the second
  copy is the one that goes stale.** A lantern deleted, a lantern copy-pasted in from
  another model, a lantern arriving inside an imported building: every one of those changes
  what the model contains without going through this plugin. A register would have to be
  reconciled against reality on read, which is the scan it was meant to avoid. The stamp
  travels WITH the lantern through all four cases and cannot disagree with itself.
- Where a per-lantern fact genuinely IS needed - which file it was built from - it is
  already stamped on the root, for the same reason: it survives being copied between models.

**Detail**

- **NEW `LanternReloader.na_selected_lantern`**, non-interactive and cheap, separate from
  `na_resolve_target` which may open an inputbox. A context menu builder can neither ask a
  question to decide what to show nor walk the model to find out. It answers only from what
  the user has already pointed at - the selection, then the open edit context - and
  deliberately does NOT fall back to "the model's only lantern": a right click on empty
  space is not a request to reload something elsewhere.
- **Selection scanning is capped at 32 entities** for the context menu path, uncapped for
  the menu path. A right click must not stall behind a selection of forty thousand faces,
  and a lantern being reloaded is always within the first few entities of a deliberate
  selection. The menu driven path has a user waiting on a result, where correctness beats
  latency.
- **A nested click resolves upward.** Right clicking one glaze bar inside an opened lantern
  offers the reload for the lantern containing it, by climbing definition to instances. With
  shared definitions that climb is still unambiguous, because a part definition is never
  shared BETWEEN lanterns - the registry is cleared per import and definition names are
  uniquified per lantern - so every instance of one belongs to a single lantern.
- **The lantern resolved when the MENU IS BUILT is captured in the item's block** rather than
  re-resolved when the item is clicked. Between the menu opening and the click the selection
  is not guaranteed to be what it was, and an item naming a lantern must act on that one.
- **`Regenerate Lantern from '<file>'` skips the picker, which does not contradict 1.4.0's
  "the picker is ALWAYS shown".** That rule exists because a reload replaces geometry
  somebody has positioned and may have copied, so it must never be silent about which file
  it is building. Naming the file IN THE LABEL the user clicks discloses exactly what the
  picker would have, one click earlier. It appears only when the lantern remembers a path
  AND that file is still on disk, so it can never fail for a reason the user could have been
  warned about first.
- **`ContextMenu.Enabled` in the config** turns the whole thing off. SketchUp's right click
  menu gets crowded with plugins installed, and this is the switch for anybody who would
  rather it stayed out of theirs. Read on every right click, which the cached config makes a
  hash lookup rather than a file read.
- **`Na__ContextMenu` lives in `01__AppCore` but loads LAST**, because it is UI wiring by
  nature and names the reloader by dependency. Noted in the chain comment: the folder
  numbers describe what a file IS, and `NA_MODULE_CHAIN` is the only thing that describes
  what loads when.
- **`na_label_for` became the public `na_describe`** rather than being duplicated, since the
  context menu needs to name the lantern it is acting on and the inputbox already did.

**Verification note:** block structure of every module checked for balance and the config
JSON checked for parse. The context menu itself is untested in SketchUp.

**Files Created:**
- `02__Src__AppModules/01__AppCore/Na__ValeLantern__Importer__ContextMenu__.rb`

**Files Changed:**
- `Na__ValeLanternImporter__Loader.rb` - one `UI.add_context_menu_handler` inside the
  `file_loaded?` guard, dispatching by name
- `01__AppCore/Na__ValeLantern__Importer__Main__.rb` - ContextMenu last in the chain
- `02__AppData/Na__ValeLantern__Importer__Config.json` - `ContextMenu` block
- `02__AppData/Na__ValeLantern__Importer__ConfigLoader__.rb` - `na_context_menu_enabled?`
- `05__Assembly/Na__ValeLantern__Importer__LanternReloader__.rb` - `na_selected_lantern`,
  `na_source_file_for`, `na_describe`, capped selection scanning
# ---------------------------------------------------------


# ---------------------------------------------------------
### Vale Lantern Importer - Version 1.4.0 - 12-Aug-2026
#### FEATURE - Softened Edges, Shared Component Definitions, and Reload In Place

Three changes that turn out to be one change. An imported lantern read as a bundle of
pinstripes running the length of every extruded member; it held one definition per
placement where four hips are the same hip four times; and changing the design meant
deleting the lantern and importing a new one, which loses its position. Components are the
answer to the second and third, and the first is a pass that only makes sense once a part
is a definition rather than a group.

**AIM 1 - Remove the visible lines down every member**

- **NEW `Na__EdgeSoftener`**: SketchUp's own Soften Edges panel, applied at build time from
  a table instead of by hand on a selection. Reads the angle between the two faces either
  side of an edge and sets `soft` and `smooth` where it is shallower than the family's
  threshold.
- **WHY THE COPLANAR MERGE COULD NOT FIX THIS**: an extruded aluminium section is not flat.
  A glaze bar cap has a shallow crown, a lead flashing a rolled edge, a cornice a curve,
  and each arrives from the exporter as a run of short straight facets because that is what
  a swept polyline section IS. Those facet boundaries are genuinely not coplanar - they are
  a few degrees apart - so the merge pass correctly refuses to erase them, and `add_face`
  gives every one of them SketchUp's default hard visible edge.
- **BOTH FLAGS, BECAUSE THEY ARE TWO DECISIONS**: `soft` hides the edge and merges its two
  faces into a Surface, which removes the LINE. `smooth` blends the shading, which is what
  stops the result reading as a fan of flats catching light differently; on its own smooth
  leaves the edge visible, and only the Soften/Smooth slider setting both together makes
  them look like one thing. `SoftenCoplanar` mirrors the panel's third checkbox and is off,
  because the merge pass has already erased what it would act on.
- **RUNS LAST, AND DEPENDS ON THE TWO PASSES BEFORE IT**: after the coplanar merge, so
  nothing is softly hidden that should have been erased outright and no Surface spans a
  flat face; and after the orientation pass, because the angle between two normals only
  means the real dihedral when both faces are wound the same way out of the solid. On a
  shell that came out inside in, a 5 degree facet boundary reads as 175 and nothing would
  soften.
- **Softens once per DEFINITION, not once per placement**, which is the second dividend of
  the sharing below - four hip beams are softened by one pass.
- **Eight families on at 22.5 degrees** as specified: glaze bar trims and caps, ridge and
  hip beam timber, ridge aluminium cap, ridge and hip lead flashing, interior cornice. The
  other sixteen are listed explicitly as `false` rather than omitted, so a family is
  visibly a decision rather than an oversight.
- **The base/eaves `leadFlashing` is deliberately NOT softened** while the ridge and hip
  flashings are. It is a folded sheet with shallow folds and softening it would hide the
  fold lines that show where the sheet breaks. Noted in the config so the reasoning is
  where the switch is.
- **Finials are never touched by it.** They are the one thing in a lantern that is not a
  swept section, and their soft / smooth / hidden / colour state is replayed exactly as the
  component author set it (1.3.0). An angle threshold cannot tell a deliberately hidden
  edge from a shallow one, so it would throw away better information than it adds. The pass
  only ever runs on prisms, so the `components` row is documentation rather than a switch.

**NEW - Plugin side config, and where the line between the two configs falls**

- **NEW `Na__ValeLantern__Importer__Config.json` and `Na__ConfigLoader`**: the first
  configuration this plugin has ever carried, which needs justifying against the standing
  rule that the vocabulary lives in the payload. The rule holds: a decision about the
  LANTERN - tags, materials, part names, geometry - stays in the exporter's config and
  travels in the payload. A decision about how SketchUp should PRESENT it - a softening
  angle, component versus group, whether congruent parts share - belongs here, because a
  modeller wants to change those without re-exporting, and because they mean nothing to any
  other consumer of the payload.
- **A missing config file does not stop an import.** The loader's fallback carries the
  STRUCTURAL defaults so a correct lantern is still built. It deliberately does NOT mirror
  the softening table: duplicating twenty four rows of decisions in Ruby would guarantee
  the two copies drift. With the file gone every part imports hard edged - which is exactly
  what 1.3.0 did - and the console names the path it could not find. A visibly unsoftened
  lantern plus a named error beats a silently half correct table.
- **Cached on first read and reset by the module chain loader**, so editing an angle is
  picked up by re-pasting the one line loader, the same as editing a Ruby module.

**AIM 2 - Components instead of groups, and shared definitions where instances repeat**

- **Every container level is now a ComponentInstance**: root lantern, assembly, part group
  and individual part. Each level is independently switchable back to a group in the config,
  because a part that has come out wrong is easier to pick apart as a group.
- **A group and a component are the same object underneath** - a group IS a
  ComponentDefinition carrying one instance with `group?` true - and three differences
  decide it. SHARING: a definition can carry many instances that genuinely share one copy
  of the geometry, where SketchUp silently makes a copied group unique the moment it is
  edited. IDENTITY: a component is named, counted and swappable in the Component browser,
  where a group appears nowhere. REGENERATION: a definition's contents can be replaced
  while every instance keeps its transform, which is the whole of AIM 3.
- **NEW `Na__DefinitionRegistry`** owns definition identity: what to call one, and whether
  a part being asked for is one it has already built. A lantern's four hip cores, four hip
  beams, four hip blockings, four hip flashings and N glaze bars per slope each collapse
  onto one definition.
- **CONGRUENCE IS TESTED IN A FRAME DERIVED FROM THE PART ITSELF**, because the payload
  gives finished world coordinates and two hip beams at two corners share not one number.
  The frame is built by rule in index order - origin at the first point, X toward the first
  point far enough away to give a direction, Z from the cross product with the first point
  after that which is not collinear, Y as Z cross X - so it is identical for two congruent
  parts, since the exporter emits both from the same section in the same order. Every point
  is then expressed in that frame, rounded to 1e-4 inch and concatenated with the ring
  spans and the TagKey into a signature string.
- **MIRRORS COST ONE EXTRA SIGNATURE AND NOTHING ELSE.** On a rectangular lantern the four
  hips are two rotations and two reflections: front-right rotated 180 about Z gives
  back-left, but front-right MIRRORED gives front-left, so a rigid only test finds two
  definitions of two instances where one of four was available. Because the derived frame
  is always right handed - Y is computed as Z cross X, never measured - a reflection carries
  X and Y through and flips only Z, so a mirrored part's local coordinates are the
  original's with z negated and nothing else. Testing for a mirror is testing the same
  signature with the z column's sign reversed. The placement is the part's own frame times
  `scaling(1, 1, -1)`.
- **`ShareMirroredInstances` is the switch to reach for first** if a mirrored part ever
  renders with its back faces outward. A mirrored instance has a negative determinant
  transform, which is what the Scale tool produces with a negative handle and which
  SketchUp handles - but rotation sharing keeps working with the mirror half off.
- **THE TAGKEY IS PART OF THE SIGNATURE ON PURPOSE.** Two parts of different families that
  happened to be geometrically identical would be a legitimate share, but the definition
  would be named after whichever was built first - a glaze bar core called HipBlocking.
  Keeping families apart costs a definition or two and keeps every name honest.
- **PARTS ARE NOW BUILT IN LOCAL COORDINATES**, which sharing forces but which pays off
  independently: a component whose geometry sits at its own origin has its axes ON the
  part rather than at a model origin several metres away, so Entity Info's dimensions and
  the Move tool's inferences read sensibly on a selected member. A part whose points are
  collinear yields no frame, builds in world coordinates at identity and never shares -
  exactly the old behaviour.
- **TAG, MATERIAL AND ATTRIBUTES GO ON THE INSTANCE, NEVER THE SHARED DEFINITION.** They
  are precisely what differs between two placements of the same geometry, so writing them
  to the definition would have the four hips overwrite each other's identity and settle on
  the last one's. Instance name keeps the payload's part name, so the Outliner reads exactly
  as it did when every part was a group.
- **Definition naming is `{RootToken}__{Family}__{Index}`**, where RootToken is the
  payload's own RootGroupName. One lantern's thirty definitions therefore sort together in
  the Component browser under the lantern they belong to, and a second lantern from the same
  project cannot silently adopt the first one's geometry.
- **SKETCHUP GOTCHA - `definitions.add` RETURNS AN EXISTING DEFINITION** when the name is
  taken, rather than raising or renaming. Left unguarded that hands a second lantern the
  first one's definition and then appends four hundred more faces to it. Every name goes
  through `na_unique_definition_name` first, every time.
- **Construction linework stays a GROUP**, the one deliberate exception, switchable. Nothing
  in a setting out set repeats so there is no definition to share; `GroupPerEntity` puts
  every datum in its own container, so components would add dozens of one-off entries to
  the Component browser for a class of object nobody selects from there.
- **An empty container now removes its DEFINITION as well as its instance.** Erasing an
  empty group was enough before; an empty component would leave an entry in the Component
  browser forever.

**AIM 3 - Reload Lantern Json, regenerating in place**

- **NEW `Na__LanternReloader`** and a **Reload Lantern Json** menu item, plus
  `Na__ValeLantern.na_reload_lantern`.
- **THE GEOMETRY INSIDE THE LANTERN'S DEFINITION IS REPLACED. THE INSTANCE IS NEVER
  TOUCHED.** Which is what makes it robust, and the reason the alternative was not built:
  delete-and-reimport has to measure the user's transform and reapply it, so any rounding
  is a lantern a millimetre out of position; it replaces one of three copies along a roof
  and leaves the other two stale; anything aligned to the lantern loses its reference; and
  the undo stack holds a delete and an import as separate steps. A component instance is a
  definition plus a transform, so rebuilding the definition changes what is drawn and
  leaves the positioning alone. The lantern does not move, EVERY copy regenerates at once
  each where it stands, its name, tag, material and attributes survive, and it is one undo
  step.
- **ORDER OF THE REBUILD IS LOAD BEARING**: collect the previous build's definitions by
  walking the root BEFORE anything is destroyed (after the clear there is nothing to walk),
  clear the root definition's entities, release the collected definitions, THEN build. The
  release must precede the build not only to keep the Component browser from growing by
  thirty entries per reload but because definition names are unique in a model: a name still
  held by the old build forces the new one onto `__2`, and a lantern reloaded five times
  would carry five generations of suffix.
- **Definitions are released OUTERMOST FIRST** - assemblies before the parts nested inside
  them - and tested with `count_used_instances`, not `count_instances`. After the clear, a
  part definition's instances survive inside assembly definitions that are themselves
  unused; `count_used_instances` reads through that nesting and answers zero, where
  `count_instances` answers four and nothing would ever be released.
- **NOT `purge_unused`**, which would take the user's own unused components with it. Only
  definitions this plugin stamped with a `RecordType`, and only those with no instance left
  anywhere. Authored finials carry an `AssetId` and no `RecordType`, so a finial shared with
  another Noble Architecture tool is never released.
- **The target lantern is resolved by how explicit the user has been**: a selection first
  (walked UP to the lantern containing it, so selecting one glaze bar and asking for a
  reload works), then the open edit context, then whatever the model holds - and it only
  ASKS when the model holds more than one and the user has said nothing.
- **Roots are found by walking DEFINITIONS, not entities.** A lantern dropped inside
  somebody's building group is nested arbitrarily deep, and definitions are a flat list of
  everything the model holds however deeply placed, so this costs one pass whatever the
  model looks like. Both the definition and its instances are tested, which is what lets a
  lantern imported before 1.4.0 - stamped on the group, not on the group's definition - be
  found and reloaded.
- **A lantern imported before 1.4.0 reloads.** Its root is a group, and a group has a
  definition, so the same clear-and-rebuild applies. It gains none of the copy-regeneration,
  because a group cannot carry a second instance.
- **Build choices are read back off the lantern**: an import stamps `BuiltModel` and
  `BuiltSettingOut`, so one imported with its construction linework reloads with it and one
  imported without does not silently gain it. A pre-1.4.0 root carries neither and falls to
  the metal alone, which is what those imports built.
- **The identity check asks rather than refusing.** Reloading one lantern's file over
  another is legitimate - it is how you swap an orangery lantern for a kitchen one in place
  - but far more often a wrong file picked in a hurry, so a differing `Lantern.Id` puts both
  titles in a yes/no box.
- **The picker is ALWAYS shown**, even though the source path is now stamped on the root and
  used to open the picker in the right folder. A reload replaces geometry somebody has
  positioned and may have copied, and doing that off a remembered path without showing it
  is the kind of convenience only ever noticed when it was wrong.
- **`Na__Main`'s file picker became public** rather than being copied. There must be exactly
  one place that knows the filter string and the settings key the last folder is remembered
  under; two copies would drift the day one was renamed, and the symptom - a picker opening
  in the wrong folder - is too small to ever get investigated.
- **SKETCHUP GOTCHA - `Entities#clear!` answers false on an already empty collection** as
  well as on one it could not clear, and an empty root definition is a real state that a
  reload failing part way through leaves behind. Emptiness is tested rather than inferred
  from the return value.

**Verification note:** no Ruby interpreter is installed on this machine (SketchUp embeds
Ruby as a DLL), so the congruence scheme was checked by transcribing `na_local_frame`,
`na_to_local`, `na_signature` and `na_placement` into a standalone script and asserting the
three claims the design rests on: a rotated and translated copy produces the same
signature; a mirrored copy misses the direct signature and hits the z-negated one; and the
placement transform reconstructs the copy's world geometry from the ORIGINAL's local
geometry to within 2e-15 inch. Different lengths and different TagKeys correctly fail to
match. Block structure of every module was checked for balance. The build itself is
untested in SketchUp.

**Files Created:**
- `02__Src__AppModules/02__AppData/Na__ValeLantern__Importer__Config.json`
- `02__Src__AppModules/02__AppData/Na__ValeLantern__Importer__ConfigLoader__.rb`
- `02__Src__AppModules/04__GeometryBuilders/Na__ValeLantern__Importer__EdgeSoftener__.rb`
- `02__Src__AppModules/04__GeometryBuilders/Na__ValeLantern__Importer__DefinitionRegistry__.rb`
- `02__Src__AppModules/05__Assembly/Na__ValeLantern__Importer__LanternReloader__.rb`

**Files Changed:**
- `Na__ValeLanternImporter__Loader.rb` - Reload Lantern Json menu items
- `01__AppCore/Na__ValeLantern__Importer__Main__.rb` - four new modules in the chain,
  public file picker, `na_reload_lantern`, config cache reset on reload
- `04__GeometryBuilders/Na__ValeLantern__Importer__PrismBuilder__.rb` - component path with
  local coordinates and sharing, softening pass, group path kept behind the config switch
- `04__GeometryBuilders/Na__ValeLantern__Importer__LineBuilder__.rb` - container switch
- `05__Assembly/Na__ValeLantern__Importer__ModelComposer__.rb` - component containers at
  every level, root stamped on definition and instance, `na_rebuild` entry point
# ---------------------------------------------------------


# ---------------------------------------------------------
### Vale Lantern Importer - Version 1.3.0 - 12-Aug-2026
#### FEATURE - Authored Edge Styles Replayed on Component Definitions

Components rebuilt into SketchUp arrived as black wireframes of their own tessellation.
`add_face` gives every edge SketchUp's defaults - visible, hard, unpainted - and the only
remedy available was a softening pass with an angle threshold. A threshold cannot tell a
deliberately hidden edge from a shallow one, and it has no opinion at all about edge
colour, so an authored component could not survive the round trip. This closes that.

- **THE THREE FLAGS ARE REPLAYED SEPARATELY, NOT COLLAPSED**: per SketchUp's own
  definitions, `soft` hides the edge and merges its two faces into a Surface entity;
  `smooth` blends the shading and **leaves the edge visible on its own**; `hidden` hides it
  with no surface merge and no shading change. SketchUp's Soften/Smooth slider sets soft
  and smooth together, which is why they get conflated. Collapsing them into a single
  "soften" call is exactly the loss this work set out to fix, so `na_style_one_edge` writes
  each independently, plus `casts_shadows`.
- **New region in `MeshBuilder`** - `na_apply_edge_styles` runs after `na_build_faces` and
  is reported in the definition's debug line as `(N faces, M edges styled)`.
- **Edges are matched by position, not by build order**: SketchUp decides for itself which
  edges exist - it merges coincident geometry and can split an edge another vertex lands
  on - so a payload index cannot be trusted against a built edge. Every edge in the
  definition is looked up by the rounded positions of its two ends (`NA_EDGE_KEY_DP`, 1e-4
  inch ~ 0.0025mm) against the same vertex table the faces were built from. An edge the
  payload does not describe keeps SketchUp's defaults, which is the safe direction to fail.
- **Edge colour resolves through the MTE library first**: `DataLibBridge.na_edge_material_for`
  is asked before anything else, so an imported red datum line is the same material object
  as one painted by the rest of the toolchain and stays recognisable to
  `Na__EdgeUtil__PaintDeepNestedEdges`. Only when DataLib cannot answer is a plain material
  created from the exported hex, so a colour authored outside the library is still not lost.
  An edge with no authored material is left **unpainted** rather than forced black -
  unpainted is what SketchUp calls an untinted edge, and it keeps Color By Tag working.
- **Hidden faces are rebuilt then re-hidden** rather than skipped. A hidden face is still
  part of the solid; dropping it would leave a hole.
- **Dependency contract updated**: `MeshBuilder` now also depends on `DataLibBridge`, which
  already loads earlier in `NA_MODULE_CHAIN` (position 3 against MeshBuilder's 8).

Upstream companions: Component Editor Tools **0.6.2** captures the flags (schema 1.2.0),
and the web application's `Encoders__JoineryAndComponents` carries them into the payload as
a `Definitions[].Edges` array. Payloads without that array import exactly as before.


# ---------------------------------------------------------
### Vale Lantern Importer - Version 1.2.2 - 11-Aug-2026
#### FIX - Roof Glass Rendered Opaque in ValeVision3D

Reported from ValeVision3D: an imported lantern's roof glass rendered as opaque white
beside conservatory glazing built by Element Assembly Studio Pro, which rendered correctly.
Root cause was naming, and the mechanism is worth recording because it is invisible from
inside SketchUp - the model looks right there either way.

- **ROOT CAUSE - the GLB builder identifies materials by NAME**:
  `Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__` enriches a material only
  when its name matches `INDEXED_MATERIAL_REGEX = /^MAT\d{3}__/` **and** appears as a
  `SketchUpName` key in `Na__DataLib__CoreIndex__Materials__.json`. This importer was
  creating `VGH__Glazing`, which fails both tests, so `EnrichGltfMaterial` was never
  called for it: no `alphaMode: BLEND`, no `baseColorFactor` alpha, no `doubleSided`. The
  pane reached ValeVision3D as a plain opaque surface.
- **New SSOT material swap**: Payload material rows now carry `SsotMaterialId`. Where one
  is set and the surface materials index can answer, the importer creates the material
  under the **index's own SketchUpName** with the index's colour and opacity, instead of
  the `VGH__` name. Glazing becomes `MAT101__Glass__ClearDefault` - the exact material
  Element Assembly Studio Pro uses as `NA_SAFETY_GLASS_NAME`, so a lantern and a window in
  the same model now share one swatch.
- **Two other unambiguous swaps taken at the same time**: `sapele` to
  `MAT541__Timber__Sapele` and `timber` to `MAT120__Wood__TimberDefault`.
- **Four roles deliberately left unmapped**: builders upstand (site blockwork, by others),
  mill aluminium, lead flashing and plywood. The index carries no honest equivalent -
  `MAT616` is ironmongery brushed steel, which is a different product, not mill finish
  extrusion. They import under their `VGH__` names and are not enriched. Inventing a
  mapping would have been worse than leaving the gap visible.
- **Frame and joinery finishes also left unmapped, and for a sharper reason**:
  `MAT300__PaintSeries__` carries four Farrow and Ball colours against the seven the
  lantern offers. A partial mapping would render two finishes enriched and five not, which
  is a worse and more confusing result than none of them being enriched.
- **`DataLibBridge` now serves the surface materials index too**: `:materials` alongside
  `:edge_materials`, through the same cache path, with `na_ssot_material_for` and
  `na_parse_base_color` (the index stores colour as `"rgb(230, 240, 255)"`, matching the
  GLB builder's own parser).
- **An existing material of the same name is still adopted, never repainted**: which is
  the point. If Element Assembly Studio Pro has already created
  `MAT101__Glass__ClearDefault` in the model, the lantern joins it rather than making a
  second glass.

**Verification added** (`VghLantern__DevCheck__SketchUpExport__MaterialSsot__.cjs`): reads
`INDEXED_MATERIAL_REGEX` out of the GLB builder's own source rather than retyping it,
flattens the materials index the same way it does, and asserts the glazing passes both
tests, is enriched as transparent double-sided glass, and matches the name Element Assembly
Studio Pro builds with. Also reports which roles remain unenriched.

**Files Modified (web application):**
- `02__Src__AppModules/80__System__SketchUpExport/Na__SketchUpExport__Config.json` (`SsotMaterialId` on every material row, plus the notes recording why four are null)
- `02__Src__AppModules/80__System__SketchUpExport/VghLantern__SketchUpExport__PartFactory__.js` (`SsotMaterialId` carried into the payload material table)
- `60__Dev__WebBuildUtils/VghLantern__DevCheck__SketchUpExport__MaterialSsot__.cjs` (new)

**Files Modified (this plugin):**
- `02__Src__AppModules/02__AppData/Na__ValeLantern__Importer__DataLibBridge__.rb` (surface materials index loading, `na_ssot_material_for`, `na_parse_base_color`, reset covers both indexes)
- `02__Src__AppModules/03__AppUtils/Na__ValeLantern__Importer__MaterialManager__.rb` (`na_apply_ssot_material` swap, swapped count in the prepared-materials report)
# ---------------------------------------------------------


# ---------------------------------------------------------
### Vale Lantern Importer - Version 1.2.1 - 11-Aug-2026
#### FIX - Hips and Glazing Stopped Short of the Roof Edge

Reported from a SketchUp import: the hip noses hung in the air above the eaves corner and
the glass stopped short of it, where the web application's own 3D view showed both running
out correctly. Two eaves modifiers in the 3D pipeline had not been carried across.

- **ROOT CAUSE - almost nothing physically stops on the eaves datum**: The solver puts the
  hips and the glazing faces on the eaves datum, but the glaze bar cap runs 170mm further
  down the pitch past it to cover the eaves junction. Anything left on the datum floats
  short of the roof edge. Both fixes take the same number from the same place,
  `BaseFrameAssembly.EavesInterface().GlazeBarCapExtensionAlongPitchMm`.
- **Hip extension ported**: The hip's LOWER end slides down the hip's OWN axis until it
  reaches the level of the cap ends (`datum - extension * sin(pitch)`), which by the roof
  plane geometry also lands it on the extended eaves line. Sliding along the hip axis
  rather than down the slope is what keeps the nose on the hip line so the two roof planes
  still meet on it. Ported from
  `VghLantern__Env3d__MeshBuilder__Skeleton__ExtendHips`.
- **Glazing extension ported**: Every eaves vertex slides along its OWN upslope boundary
  edge, extended. For a corner that edge is the hip, so the pane's mitred side stays
  collinear with the hip line rather than swinging sideways. The slide is scaled so its
  down-slope component is exactly the cap extension. Ported from
  `VghLantern__Env3d__MeshBuilder__Glazing__ExtendPointsToCapEnds`.
- **Previously documented as a deliberate omission - it was not**: v1.1.0 shipped the
  glazing at datum bounds on the reasoning that a construction model wants the pane the
  takeoff counts. That was wrong. The datum numbers are preserved in attributes
  (`DatumLengthMm`, `DatumAreaSqMm`, alongside `EavesExtendedMm`) so the takeoff keeps them
  either way, and the solid should read as the roof reads. The README claim has been
  removed.
- **Solved geometry still never mutated**: Extended copies are swept. Setting out
  centrelines come from `SettingOutModel`, which is untouched, so the construction linework
  correctly keeps the datum hip lengths while the swept solid runs past them.
- **Extension functions exposed on the public API**: `ExtendHip`,
  `ExtendFaceToCapEnds` and `CapExtensionMm`. The DXF exporter will need the same extended
  outlines for its plan and elevations, and a second copy would be a second thing to keep
  in step.

**Verification added** (`VghLantern__DevCheck__SketchUpExport__EavesExtension__.cjs`):
asserts the exported hip noses and pane feet land on the same level as the REAL glaze bar
cap feet, queried from `BaseFrameAssembly` rather than recomputed; that the extension is
not a no-op; and that adjacent panes share their extended hip corners exactly, which is
what stops a wedge opening on every hip.

The first draft of that last check compared the built SLAB corners and failed. Two faces
on a hip have different normals, so their bedded rings are correctly not coincident - it is
the extended DATUM ring the hip line is shared on. Bad test, not a bad fix.

**Files Modified (web application, not this plugin):**
- `02__Src__AppModules/80__System__SketchUpExport/VghLantern__SketchUpExport__Encoders__BaseAndRoof__.js` (new Eaves Cap End Extension region, wired into the roof frame and glazing encoders, extension functions exposed)
- `02__Src__AppModules/80__System__SketchUpExport/VghLantern__SketchUpExport__README__.md` (deliberate-difference claim removed, extension documented)
- `60__Dev__WebBuildUtils/VghLantern__DevCheck__SketchUpExport__EavesExtension__.cjs` (new)
# ---------------------------------------------------------


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
| 3 | `Na__ConfigLoader` | 387 | DebugTools |
| 4 | `Na__DataLibBridge` | 286 | DebugTools, optional `Na__DataLib` install |
| 5 | `Na__TagManager` | 210 | DebugTools, DataLibBridge |
| 6 | `Na__MaterialManager` | 145 | DebugTools |
| 7 | `Na__PayloadReader` | 259 | DebugTools |
| 8 | `Na__EdgeSoftener` | 205 | DebugTools, ConfigLoader |
| 9 | `Na__DefinitionRegistry` | 536 | DebugTools, ConfigLoader |
| 10 | `Na__PrismBuilder` | 663 | DebugTools, Units, TagManager, MaterialManager, ConfigLoader, EdgeSoftener, DefinitionRegistry |
| 11 | `Na__MeshBuilder` | 527 | DebugTools, Units, TagManager, MaterialManager, DataLibBridge |
| 12 | `Na__LineBuilder` | 295 | DebugTools, Units, TagManager, DataLibBridge, ConfigLoader, DefinitionRegistry |
| 13 | `Na__ModelComposer` | 612 | everything above |
| 14 | `Na__LanternReloader` | 698 | everything above, plus `Na__Main` for the file picker |
| 15 | `Na__ContextMenu` | 174 | DebugTools, ConfigLoader, LanternReloader |

`Na__Main` (429 lines) owns the chain and is loaded by `Na__ValeLanternImporter__Loader.rb`
(170 lines) at SketchUp start.

`Na__ContextMenu` sits in `01__AppCore` because it is UI wiring, and loads LAST because it
names the reloader. The folder numbers describe what a file IS; `NA_MODULE_CHAIN` is the only
thing that describes what loads when.

`Na__LanternReloader` naming `Na__Main` looks circular and is not: `Na__Main`'s module body
is fully defined before the line at the foot of its own file that loads the chain, so the
constant resolves. The alternative was a second copy of the picker's filter string and
settings key, which would drift.

### Console Entry Points

```ruby
Na__ValeLantern.na_import                # the metal alone
Na__ValeLantern.na_import_with_setout    # metal plus construction linework
Na__ValeLantern.na_import_setout_only    # linework alone, to check an existing model
Na__ValeLantern.na_import_verbose        # per part reporting: every prism, every
                                         # coplanar merge, every face the API refused

Na__ValeLantern.na_reload_lantern         # rebuild a lantern already in the model, in
                                          # place, from an updated build file
Na__ValeLantern.na_reload_lantern_verbose # the same with per part reporting
```

The reload is also on the RIGHT CLICK menu, and appears there only when the thing being
right clicked is a Vale lantern or something inside one. That path can additionally
regenerate straight from the file the lantern was last built from, which is the fast loop
for tweak, re-export, regenerate.

### The Two Configs, and Which Owns What

| Decision | Lives in | Reaches the plugin via |
|---|---|---|
| Tags, materials, part naming, assemblies, geometry | `Na__SketchUpExport__Config.json` (web app) | the payload |
| Edge softening per family and angle | `Na__ValeLantern__Importer__Config.json` (plugin) | read off disk |
| Component versus group, per level | same | read off disk |
| Congruent and mirrored definition sharing | same | read off disk |
| Reload behaviour | same | read off disk |
| Whether the reload appears on the right click menu | same | read off disk |

The test is whether the decision is about the LANTERN or about how SketchUp should PRESENT
it. A tag colour is about the lantern and must be able to change for every consumer of the
payload at once. A softening angle means nothing to any consumer but this one, and a
modeller has to be able to change it without re-exporting.

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

Every container carries its payload attributes in the `VghLantern` dictionary, so a
downstream report can walk a model and pick out Vale lantern parts without matching on
names.

`RecordType` values, and what carries each one:

| Value | Carried by |
|---|---|
| `ValeLanternRoot` | the root lantern's DEFINITION and its instance, both |
| `ValeLanternAssembly` | the assembly instance |
| `ValeLanternPartGroup` | the part group instance |
| `ValeLanternPartDefinition` | a shared part definition |
| `ValeLanternContainerDefinition` | a container definition |

`RecordType` is also the reload's test for "is this definition mine to release". An authored
finial carries an `AssetId` and NO `RecordType`, which is what keeps it safe from the sweep.

Per part identity - tag, material, attribute block - is on the INSTANCE, never on a shared
definition, because it is what differs between two placements of the same geometry. Reading
it back is the same `get_attribute` call it always was.

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
