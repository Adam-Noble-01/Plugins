# Element Assembly Studio Pro - Architecture

## Product
Element Assembly Studio Pro by Noble Architecture is a SketchUp 2026 plugin that builds parametric architectural elements (windows, exterior doors, interior doors, and fitted kitchen and wardrobe units) inside the active model from an HtmlDialog UI.

## Top-level layout
```
Plugins/
  Na__ElementAssemblyStudioPro__Loader.rb              <-- SketchUp boots this
  Na__ArchTools__ElementAssemblyStudioPro__Modules__/  <-- everything else
    Na__AssemblyStudio__UiLayout__.html
    01__AppAssets__ElementAssemblyStudio/              brand assets
    02__Src__AppModules/                               source tree (numbered bands)
      01__AppCore/                                     dialog chrome, selection coordinator, UiBridge, shared Ui Controls/Events
      02__AppData/                                     AppConfig, ConfigLoader, MaterialManager, SerializerBase
      03__AppUtils/                                    DebugTools (unified), TagManager, SettingsTab UI
      04__GeometryHelpers/                             Box, Units, Fuse_Shared
      05__Viewport__2dPreviewEngine/                   generic SVG viewport factory
      06__Tools__MeasurementTools/                     TwoPoint + ThreePoint + RunMeasure (cabinet runs) + RunPathMeasure (an assembly run's path, any number of corners)
      07__Tools__PlacementTools/                       WindowPlacementTool + CabinetPlacementTool
      20__System__WindowSystem/                        window-specific code
      31__System__ExteriorSingleDoorSystem/            single exterior door panel + PanelInterface contract (filenames use ExtSingleDoor__ for MAX_PATH)
      32__System__ExteriorSlidingDoorSystem/           two-panel exterior sliding door (MVE-based translation)
      33__System__ExteriorMultiFoldingDoorSystem/      multi-panel exterior bifold door (ROT + MVE)
      40__System__InteriorDoorSystem/                  interior door tab
      45__System__InteriorCabinetry/                   cabinetry tab: kitchen and fitted wardrobe units (filenames use Cabinetry__)
      55__System__AssemblyRunSystem/                   assembly runs tab: runs of the other systems' elements along a path (filenames use AssemblyRun__)
      60__System__McpOperations/                       the agent seam (Na SketchUp MCP calls only this)
    03__Style__AppStylesheets/                         master CSS hub + brand/tab-strip stylesheets
    04__Data__AssetLibrary/                            asset JSON: interior door (architraves, handles, hinges), window boards, cabinet legs and handles; the Vale column .skp files runs use
    65__Dev__DevTools/                                 Na__ schema 2D/3D exporters + hierarchy metadata
    85__Docs__AppDocumentation/                        Architecture, DEVLOG, RewireMap, Tasks
    90__AppCache__TempFilesCache/                      plugin-local cache for live-fetched DataLib JSON
```

## Module conventions
- Ruby outer namespace: `module Na__AssemblyStudio`.
- Ruby per-system namespaces: `Na__AppCore`, `Na__AppData`, `Na__AppUtils`, `Na__GeometryHelpers`, `Na__MeasurementTools`, `Na__PlacementTools`, `Na__WindowSystem`, `Na__ExteriorSingleDoorSystem`, `Na__ExteriorSlidingDoorSystem`, `Na__ExteriorMultiFoldingDoorSystem`, `Na__InteriorDoorSystem`, `Na__InteriorCabinetrySystem`, `Na__AssemblyRunSystem`, `Na__DevTools`.
- File-segment shortening: where the full Ruby module name would push the absolute Windows path over the 260-char `MAX_PATH` limit, filenames use a shortened segment instead. The Ruby module name itself stays full for clarity. The shortening table is:

| Folder                                               | Ruby module                              | File segment used in filenames |
|------------------------------------------------------|------------------------------------------|--------------------------------|
| `40__System__InteriorDoorSystem`                     | `Na__InteriorDoorSystem`                 | `InteriorDoorSystem__` (full) — fits MAX_PATH |
| `40__System__InteriorDoorSystem` panel-style files   | `Na__PanelDesignStyles__*`               | `PanelStyle__*`                                |
| `31__System__ExteriorSingleDoorSystem`               | `Na__ExteriorSingleDoorSystem`           | `ExtSingleDoor__`                              |
| `32__System__ExteriorSlidingDoorSystem`              | `Na__ExteriorSlidingDoorSystem`          | `ExtSlide__`                                   |
| `33__System__ExteriorMultiFoldingDoorSystem`         | `Na__ExteriorMultiFoldingDoorSystem`     | `ExtFold__`                                    |
| `33__System__ExteriorMultiFoldingDoorSystem` layout files | n/a — sub-files                     | `Layout__<Algorithm>__` (e.g. `Layout__EqualEqual__`) |
| `45__System__InteriorCabinetry`                      | `Na__InteriorCabinetrySystem`            | `Cabinetry__`                                  |
| `55__System__AssemblyRunSystem`                      | `Na__AssemblyRunSystem`                  | `AssemblyRun__`                                |

  - Rationale: the longer folder names of the new sliding/multi-folding systems pushed `Na__AssemblyStudio__<full>__<deep-purpose>__.rb` over MAX_PATH. The very short `ExtSlide__` and `ExtFold__` segments (and `Layout__` instead of `LayoutAlgorithm__`) keep absolute paths comfortably below 260 chars. The folder names and Ruby module names stay full and self-documenting.
- File names follow `Na__AssemblyStudio__<Domain>__<Purpose>__.{rb,js,css,json,html}`.
- Method names use the `na_` prefix consistently.

## Single source of truth: AppConfig
`02__Src__AppModules/02__AppData/Na__AssemblyStudio__AppConfig__Main.json` is the single config file. The `Na__ConfigLoader` Ruby module exposes `na_get(*key_path)` for any module to read scoped defaults.

Sections:
- `metadata` - app/version
- `tabs` - registry of tabs the dialog should expose
- `debug` - debug + file-logging flags
- `attributeDictionaries` - per-system serializer parameters (used by `SerializerBase.na_config_from_app_config`)
- `measurement.callbacks` - host callback names for the measurement tools
- `devTools` - origin group name + export folder
- `assetLibrary` - root folder + remote URL + interior door bucket names (source-of-truth for AssetLibrary folder routing)
- `windowSystem.defaults` - window schema mm defaults
- `dxf.layers` - DXF layer names
- `theme.previewColors` - SVG preview hex colours

## Window Board (V1.9.0)
- Module: `20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__WindowBoardBuilder__.rb` (`Na__WindowBoardBuilder`), called by `GeometryEngine.na_build_window_elements` after the cill and before the cill lift, with the frame material.
- Assets: `04__Data__AssetLibrary/Windows__WindowBoards__/Na__Window__WindowBoard__Type-NN__<Name>__t30mm__.json` (AppConfig `assetLibrary.window.windowBoards`). Unified contract plus `Na__WindowBoard__Parameters`; the geometry is a Profile Path Tracer style `Na__Asset__Profile2D` outer loop (Y back across the reveal, Z up, origin = underside of the board on the wall face line).
- Parametric rule: the loop is split at Y = 0. Behind it is rebuilt at `window_board_reveal_depth_mm` (back of frame to wall face); the nose in front keeps its shape and slides with `window_board_nosing_overhang_mm`, never below the nose depth plus 1mm.
- Returned nosing (`window_board_nosing_returns_enabled`): the nose runs round the left end, front and right end, one board thickness past each side of the reveal, mitred at the front corners. All faces come from the pure `na_returned_board_faces(geometry)` and go into one `Na_WindowBoard` group; no Follow Me, no Solid Tools. Square ends: the full section extruded across the reveal.
- Placement: top face flush with the frame underside; starts at the back of the frame (`frame_wall_inset + frame_depth`).
- UI: toggle `window_board_enabled` in OPTIONS (window modes only) opens `#na-section-window-board` (`NA_WINDOW_BOARD_CONFIG`). Edge colour `edge_colour_window_board_id`, part `window_board` in `Na__EdgeColourPainter` (Medium Dark Grey). The 2D preview draws a dashed outline from `window.NA_WINDOW_BOARD_ASSET_CACHE` (pushed by `na_requestWindowBoardAssets`).

## Interior Cabinetry (V2.1.0)
- System: `45__System__InteriorCabinetry`, Ruby `Na__InteriorCabinetrySystem`, filenames `Na__AssemblyStudio__Cabinetry__<Purpose>__`. Tab id `cabinets`, JS module `Na_CabinetUI`.
- Unit frame (mm): origin at the back left at floor level on the wall line, X along the run, Y from `-depth` (carcass front) to 0 (the wall), with fronts further into -Y, and Z up. Wall units are built at their hanging height inside the same frame. Y = 0 is the sides' back edges, not the back panel: the back is set in by the scribe (`BackPanelInset_mm`, 20 by default), and the base, rails, top and shelves stop at its front face (`yBackPanelFront`).
- Layout: `Na__AssemblyStudio__Cabinetry__LayoutResolver__.rb` and its JS twin `..._Viewport__LayoutResolver__.js` return the same `{ values, parts, fronts, handles, drawerBoxes, rail, plinth, legs, legHeight, warnings, bounds }`. The builders and the previews only draw what it returns. Keep the two in step: same constants, same rules. The dev parity check and `CabinetLayout` spec catch drift.
- Builders: `GeometryEngine.na_create_cabinet(cfg, id, transform)` adds one instance to `model.active_entities` with the transform unchanged (Coordinate Rule: world in an open context). Then `CarcassBuilder`, `FrontBuilder` (shaker 14-face frame, grooved profile), `DrawerBoxBuilder`, `PlinthLegsBuilder` and `HandleBuilder` each fill one named group.
- Assets: legs and handles use the unified asset contract, with placement data in `Na__Asset__Metadata` (`Na__CabinetPlacement__*`). A leg's `StretchZoneMin_mm`/`StretchZoneMax_mm` mark the band that stretches to the plinth height. `AssetMeshBuilder` turns `Mesh3D` into one definition per asset (per height for legs), with soft and smooth edges as flagged.
- Tools: `Na__RunMeasureTool` returns a right-handed run frame (origin, axes, length) from start, end and room side. `Na__CabinetPlacementTool` resolves a frame each mouse move: beside a picked cabinet (pick path transform product), backed onto a picked wall face (normal through the input point's transformation), or free on the ground. Tab turns the unit.
- Data: `attributeDictionaries.interiorCabinetrySystem` (`Na__CabinetConfiguratorInfo` / `CabinetID`, IDs `ACBnnn`); payload `{ Na__CabinetMetadata, Na__CabinetComponents, Na__CabinetConfiguration }`.
- Presets: family `Cabinet`, schema contract `Na__CabinetConfiguration`, type = the product chip the values resolve to.

## Arched Header Rails (V2.5.2)
- Modules: `20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__ArchedHeaderBuilder__.rb` (`Na__ArchedHeaderBuilder`) and its JS twin `...__Viewport__ArchMath__.js` (`window.Na__ArchMath`). Same constants, same rules. The layout functions work in the caller's units: inches for windows, millimetres for doors (`na_scale` converts a door's arch for its solids and lead).
- Keys: windows `arched_header_enabled`, `arched_header_height_mm`, `arched_header_true_arch`, `arched_header_segments`. Each door type holds its own under `single_door_`, `double_door_`, `sliding_door_` or `bifold_door_`. An absent switch reads as off; `na_hydrateFullWindowConfig` sets it off on load so one element's arch cannot ride into the next. `NA_EXT_DOOR_SHARED_SUFFIXES` carries them across a door type switch.
- The rule: the crown sits at the flat glass top (`z + height`), the springing line the rise below it, radius `(half^2 + rise^2) / (2 x rise)`. Segment counts are even, so one point is exactly the crown and the rail keeps its set depth at the centre.
- Segmental: stiles full height, flat-topped rail between them. True arch (rise within 0.5mm of half the glass width): one head across the full casement or leaf width, on stiles that stop at the springing line (`na_stile_height`), because a rail between the stiles would end in a long feather edge.
- Limits: the rise never takes the glass below 20mm at each side (`na_resolve`); under 1mm of room there is no arch. Each casement resolves its own arch from its own glass, so unequal lights, Individual Casement Sizes and Per Casement Settings follow it.
- Who arches: `head_cell` in `GeometryEngine.na_create_opening` is the top casement of each light; a sash window passes it to the top sash only. A panel with no casement has no rail to arch. A door arches its top glass: `:arch` on the door panel layout, absent on a fully fielded leaf and on the `:lower_pane` view.
- Solids: `na_create_prism` draws explicit faces and turns each against the outward direction of its own outline edge, as `na_create_horned_cill` does, then softens facet joints within 22 degrees. Part names do not change (`Na_Casement_<id>_Top_Rail`, `...__RailTop`, `Na_DoorPanel_<id>_Rail_Top`, `Na_Glass_<id>`), so Fuse Parts and the edge painter need no new parts. Fuse Parts softens again after the boolean, which loses the flags (`na_arched_solid?` is asked first, because the boolean consumes the group).
- Bars and lead keep their flat pane positions and numbers, so removal keys are stable, and are cut with `na_trim_height` and `na_trim_run` on the true circle, which is never below the facets, so their ends run just inside the rail. Gothic tracery stays clipped to the glass rectangle.
- Previews draw the rail after the bars and lead so it covers their square ends. The hinged door preview draws a leaf as one block, so its rail is filled in the leaf colour with only the arc outlined.
- UI: `na_buildArchedHeaderDescriptor(keyPrefix)` in `...__UiSystem__Config__.js`, placed by `LayoutMap` in Casements > More (windows) and Leaves > More (doors) as a `switchgroup`. `na_updateArchedHeaderControls` hides the height under True Arch and sets the slider's top to a true arch over the widest glass; the descriptor's `max` of 4000 is only there so a stored height is never cut down before that runs.

## Shared Build Pipelines and the Agent Seam (V2.6.0)
- **One path for every create and update.** Each system has `na_pipeline_*` functions: `WindowSystem DialogCallbacks` (`na_pipeline_create` / `_update` / `_load` for windows and all four exterior doors), `InteriorDoorSystem DialogRouter` (`na_pipeline_create_door` / `_update_door`), `Cabinetry DialogRouter` (`na_pipeline_create` / `_update` / `_rename`). The dialog handlers call them and keep only what is the dialog's: tracking, the placement tool, the status line. Each is one undo step with the dialog's name, acts on the instance given, aborts and raises on failure, and touches no dialog state. A new step in a build goes in the pipeline, never in a handler, or agents and the dialog will build different things.
- **The agent seam** (`60__System__McpOperations`, Na SketchUp MCP `entity_studio` / `entity_studio_edit`) calls only those pipelines, the Presets Store and the generated parameter catalogue. Its own rules are the twins of JS-only behaviour, each file naming the JS it mirrors: `Validation` (Viewport__Validation.js), `SideEffects` (na_onControlChange), `Catalogue` (the product strip's switch). Change one of those JS rules, change its twin in the same commit.
- **The parameter catalogue** (`02__AppData/Na__AssemblyStudio__ParameterCatalogue__.json`) is generated from the UiSystem Config and LayoutMap files by `65__Dev__DevTools/Na__AssemblyStudio__DevTools__ParameterCatalogue__.js`. Rerun it after changing a control; `--check` fails when it is stale.
- **ADR ids** are shared by five door systems: every allocator counts all five instance dictionaries (`Na__ExteriorSingleDoor...`, `...ExteriorDoubleDoor...`, `Na__DoorConfiguratorInfo`, `Na__SlidingDoor...`, `Na__BifoldDoor...`). A new door system adds its dictionary to all of them.

## Assembly Runs (V2.7.0)
- System: `55__System__AssemblyRunSystem`, Ruby `Na__AssemblyRunSystem`, filenames `Na__AssemblyStudio__AssemblyRun__<Purpose>__`. Tab id `runs`, JS module `Na_RunUI`. Ids `ARNnnn`; `attributeDictionaries.assemblyRunSystem` (`Na__AssemblyRunConfiguratorInfo` / `RunID`); payload `{ Na__AssemblyRunMetadata, Na__AssemblyRunComponents, Na__AssemblyRunConfiguration }`, configuration keys prefixed `Na__RunConfig__`.
- **The words.** A run is one master component (`ARN001__AssemblyRun__<name>`). It has a PATH (plan points in mm, in the run's own frame: origin the first point, X the first leg). The path has LEGS. Along a leg stand SPANS (each an instance of a panel type's element) and COLUMNS (None, Infill, Vale260, Vale290, Gap). A CORNER joins two legs (Frames: Post, Vale260, Vale290, Open; Cabinets: CornerUnit, Blind, Open). Modes: Frames (the path is the framework face, seen from its right; an element's +Y points into the building) and Cabinets (the path is the wall line, the room on its right).
- **Hierarchy.**
  ```
  ARN005__AssemblyRun__Conservatory           ComponentInstance (the master; tag by mode: proposed windows or proposed fixtures)
    AWN007__Window__ARN005__Type-A            a span: an instance of panel type A's ONE element definition
    AWN007__Window__ARN005__Type-A            another span of type A
    ADR010__ExteriorDoubleDoor__ARN005__Type-C
    Na__Run__Posts                            mullions and jambs (run-owned; fused runs: in the framework)
    Na__Run__Columns                          infill blocks, library columns on their backings
    Na__Run__Corners                          corner blocks, library corner columns, corner units
    Na__Run__Framework                        V2.7.3 fused: Na__RunFramework__Fused, ONE solid of every frame member
    Na__Run__Cill                             V2.7.3: Na__RunCill__01 ... one solid per stretch
    Na__Run__WindowBoard                      V2.7.3: Na__RunWindowBoard__01 ... one solid per stretch
    Na__Run__Worktop                          V2.7.4, Cabinets: Na__RunWorktop__01 ... one solid per stretch of base units
  ```
  A span wears the element's own id dictionary (so it loads into its own tab) and the run's membership stamp `Na__AssemblyRunMemberInfo` { RunID, PanelType, Leg, Span }.
- **One resolver, in Ruby.** `LayoutResolver.na_resolve(config)` (pure) returns legs with their items (stations, widths), corners, each type's one width and height, warnings and errors. The page sends its configuration (`na_runResolve`) and draws what comes back (`LayoutDrawer`): there is no JS twin. `PathMath` and `RunEdits` are pure too; `65__Dev__DevTools/...AssemblyRunLayout__Spec__.rb.test` checks all three offline.
- **One build path.** `RunPipelines.na_pipeline_create` / `na_pipeline_update`; every edit (`na_pipeline_make_unique`, `_recode`, `_set_span_type`, `_set_span_product`, `_set_type_product`, `_flip_side`, `_set_path`) changes the stored configuration through `RunEdits` and calls `na_pipeline_update`. `GeometryEngine.na_build_run` order: (1) each panel type in use gets its element, made or resized by the element's own pipeline, while the old spans still stand (the id allocators count ids they can see); standing spans are matched to rows by ELEMENT id, so a recode keeps its element; (2) the definition is cleared and every span placed; (3) posts, columns, corners; (4) the temporary instances new elements were built on are erased.
- **One undo step.** The run pipeline opens the operation, then calls the element pipelines inside `Na__OperationScope.na_embed { }`, where their own start, commit and abort do nothing. Never rescue-and-continue inside the block.
- **The run sets a panel's size.** `PanelTypes.na_apply_size!` is the one place that writes width, height (less the cill) and, with Fuse Framework, the two side frames onto an element. `MemberSync` puts them back when a panel is rebuilt in its own tab at another size (it is told by `Na__OperationScope.na_on_commit`, and only schedules); the agent seam refuses the change up front (`na_run_refuse_owned!`).
- **Coordinates.** Everything inside the run is placed in the definition's own frame. In an OPEN context SketchUp reads and writes world space, so `na_pipeline_update` closes the run back to its parent first (`na_leave_run_context`, before the operation) and `na_pipeline_create` steps out of any open run. The dialog then selects the span again, which re-opens the run.
- **Path editing.** The path is data on the run, never read back from built geometry. `PathEditor.na_open` draws it as red edges in `Na__Run__EditPath` inside the run and opens that group. `Na__RunPathObserver#onActivePathChanged` only schedules a check; once the group is no longer open the line is read back (`PathMath.na_chain_segments`) and the run rebuilt, or the unchanged line erased.
- **Library columns.** `ColumnLibrary` loads the Vale column files copied into `04__Data__AssetLibrary/AssemblyRun__Columns__/` (index `Na__AssemblyRun__ColumnIndex__.json`; sizes in `Defaults::NA_LIBRARY_COLUMNS`) and makes one variant per height: a deep-unique copy (nested groups share definitions until `Group#make_unique`) with the vertices above z 1000 moved up.
- **The preview (V2.7.1).** `Viewport__LayoutDrawer__.js` draws the plan and the elevation from Ruby's layout at a given `unit` (millimetres per screen pixel): every label, tick and dimension offset is in screen pixels (`NA_PX`), so text stays one size at any zoom and a value with no room appears as you zoom in. `Viewport__PreviewPanel__.js` (`Na_RunPreview`) owns the two `Na__Viewport__Instance` viewports, measures the unit off the view box, and draws again when the zoom or a pane's size changes. It also owns the view tabs (Both, Plan, Elevation), the Dimensions switch, the height handle and Flip Out: `body.na-run-flipped` lays the preview out as a fixed panel on the right while `DialogRouter.na_set_preview_panel` widens the dialog (the page sends the extra width and the dialog's width as it sees them; Ruby scales by its own `get_size`). The width before is kept in SketchUp's preferences, so a dialog closed while flipped out is narrowed when it next opens. A dimension typed over goes to `Na_RunUI`'s `na_apply_dimension`, which sets the same value its field in the sections would.
- **Another product for a panel (V2.7.2).** `RunEdits.na_set_span_product!`, `na_set_fill_product!` and `na_set_type_product!` are the one rule for every route (the tab's menu and dropdowns, the member banner, the agent seam): a span or fill that shares its type takes a new type sized as the old one, one with its type to itself changes it; a type that changes product keeps its code, width and height (its sill only under a window, `Defaults::NA_SILL_PRODUCTS`) and drops `ElementId`, `SeedRoot`, `SeedFrom`, `PresetCode`, `Values`, `FrameBeforeFuse` and `UniqueOf`, so its element is built again from the new product's start. A type a fill made (`Auto`) follows its parent; its leg is written down as a list before one of its spans changes. `PanelTypes.na_follow_product!` brings a row into step with an element whose product was changed in its own tab.
- **Flip Inside Out (V2.7.2).** The elements are seen from the right of the path, so `RunEdits.na_flip_side!` turns the run inside out by storing the path the other way round, where it lies (open: every list reversed; closed: the first point and corner stay, the rest reversed; each leg's `Items` reversed, a cabinet fill's `Infill` End and Start swapped). `SideFlipped` is only the switch's state: the resolver and the builders never read it. After a flip the path's first point is no longer the run's origin, which nothing relies on (`na_points_from_rows` grows a path from whatever its first point and heading are).
- **Edits whose rule is Ruby's are staged through Ruby (V2.7.2).** The page sends its root and an edit's name (`na_runStageEdit`); `DialogRouter.na_staged_payload` runs `RunEdits.na_stage!` and sends the root back with its layout (`na_receiveRunStaged`). Nothing is built. Single-field edits are still made in the page.
- **Undo and redo are the page's (V2.7.2).** `Na_RunUI` keeps the last 100 states of its description (root, run id, dirty) and steps through them on Ctrl+Z / Ctrl+Y and the two buttons in the preview's head. It records in `na_changed`, on a staged answer, on New Run and on a change of mode, and starts afresh on `na_receive_run`, `na_clear_run` and a measured path arriving. What is built is SketchUp's own Undo.
- **A draft on a measured path (V2.7.2).** The measurement gives a new run its placement; the path is the draft's when the draft was seeded from that measurement (the page sends `Defaults::NA_KEY_DRAFT_PATH` with Create, never stored), else the measured path as picked.
- **One cill and one window board (V2.7.3).** `JoinCills` (on by default; always on when fused) has the run build one cill and one internal window board in place of each panel's own. `RunCills` (pure) walks the path in order: spans at the run's base, posts, infill blocks, corner posts and open corners CARRY the cill; a gap, a library column or corner column, a span on a sill height and the empty length at a leg's end break it; a door breaks the board, and a board ends at its first and last windows unless it reaches the path's free end. Each unbroken STRETCH may turn any number of corners. The resolver stands posts, infill blocks and corner posts on the cill (their `z0`, the corner's `z0`), gives each span `:base_z` (where its panel starts), and gives each cill stretch its plan outline (`na_band_outline`: a band to the path's left, mitred at every corner). `FrameworkBuilder.na_sweep` builds the cill and the board by running their section along the stretch as rails (`RunCills.na_rails`), a level side of the section as ONE face (no join line at a corner), without Follow Me. Each panel type on the cill has `has_cill` and `window_board_enabled` off (kept on its row as `CillBeforeJoin`). The cill's sizes are the run's (`CillHeight_mm`, `CillProjection_mm`); the board's are the first window's own (reveal, nosing overhang and type, from `WindowBoardBuilder`).
- **The fused framework (V2.7.3).** Fused, a WINDOW is built frameless (all four frame members 0; `FrameBeforeFuse` keeps what it had) and the run builds its head and bottom rail at the window's own thickness (`PanelTypes.na_own_rails_mm`). `FrameworkBuilder.na_build_framework` puts the rails, mullions, jambs, infill blocks and corner posts in `Na__Run__Framework` and fuses them by sequential `outer_shell` into `Na__RunFramework__Fused`, painted with the first window's frame finish and frame edge colour. A door keeps its own head and threshold (no side frames) and stands on the cill. Without SketchUp Pro the members stay separate, with a warning. `ColumnBuilder.na_build(..., framework: true)` leaves those members to it.
- **What the run owns of a panel (V2.7.3).** `MemberSync.na_owned_keys(system, fuse, type)`: width and height; fused, the side frames; a frameless window's head and bottom; a panel on a joined cill, its own cill and board. The agent seam refuses a change to any of them.
- **One worktop along the base units (V2.7.4, Cabinets).** `Worktop` (on by default). `RunCills.na_worktop_stretches` walks the path as the cill walk does, with its own rule: base and drawer units (`Defaults::NA_WORKTOP_PRODUCTS`), infill blocks, gaps and corner units, blind and open corners CARRY it; a wall, tall or wardrobe unit, a column item stored with `Worktop: false` (a cooker space) and an empty length at a leg's end break it; a stretch needs one base or drawer unit. Where a stretch reaches a free end of an open path it runs to the path's own end (not the last unit's, which an Equal fill rounds down) plus `WorktopEndOverhang_mm`. The resolver says only WHERE (`:worktops`): the depth and height are the units' own, known once the elements exist, so `FrameworkBuilder.na_build_worktops` reads each type's values through the Cabinetry resolver's `na_effective` (top = plinth + carcass; front = carcass depth + door, none when open-fronted), takes the highest and deepest with a warning when they differ, and sweeps a rectangle from `-(front + WorktopOverhang_mm)` to `WorktopBackOverhang_mm` (the same `na_sweep`). The dialog's preview sizes it from the first type's product start (`DialogRouter.na_preview_worktops!`). The pipelines report each worktop as built (`:worktops`: spans, underside, top, front, back, thickness, solid). The run takes over nothing of a unit, so it owns no unit key for it.
- **Worktop cut-outs (V2.7.5).** `WorktopCutouts` holds `{Label, Outline_mm}` rows in the run's own plan; the agent seam turns `{label, world: [[x0, y0], [x1, y1]]}` into one with the run's transformation (`na_run_localise_cutouts!`). `LayoutResolver.na_worktop_cutouts` checks them (`:worktop_cutouts`). `FrameworkBuilder.na_cut_worktop!` cuts every one that overlaps a worktop: a vertical prism from 20 below to 20 above, each side that reaches the worktop's edge (its outside, 1 mm away, is not worktop) carried 20 further, then `cutter.subtract(worktop)` (which returns the difference and erases both) on a kept copy that is put back if the result is not a closed solid.
- **A cabinet standing where an older version put it (V2.7.5).** Floor units stand on `PlinthHeight_mm` only with a plinth or legs. `PanelTypes.na_resize_standing!` rebuilds a standing cabinet element that should be on the floor and whose definition's lowest point is above it, so the run's worktop and infill blocks, which follow `na_effective`, agree with it.
- **A type a fill made starts as its parent (V2.7.4).** `PanelTypes.na_adopt_derived!` copies the parent's `SeedRoot`, or else its `PresetCode` and `Values`, onto the new row; `na_seed_root` prefers the parent's element when it has one. An Equal fill never builds the parent itself, so before 2.7.4 the derived type started from the product's start.
- **Agent seam.** `60__System__McpOperations/...McpOperations__Runs__.rb`: `Na__AssemblyStudio__McpRunRead` / `...McpRunEdit`, driven by Na SketchUp MCP's `assembly_run` / `assembly_run_edit`. It maps the agent's words to the stored keys in `na_run_config!` and calls only `RunPipelines`, `RunEdits` and `PathEditor`.

## Inter-system contracts
- `Na__AppCore::Na__OperationScope.na_start / na_commit / na_abort(model, ...)` - every build pipeline opens and closes its undo step through these. `na_embed { }` makes them no-ops so a caller's one step holds everything; `na_on_commit(name) { }` registers a listener told after each real commit (V2.7.0).
- `Na__AppCore::SelectionCoordinator.na_register_listener(name) { |selection| }` - told of every selection change, whichever handler owns the element (the run's panel banner). A handler owns an element and its tab; a listener only looks (V2.7.0).
- `Na__ExteriorSingleDoorSystem::PanelInterface.na_build_panel(context)` - WindowSystem builds a `DoorPanelContext` struct and hands it over to construct door-panel-in-casement geometry.
- `Na__ExteriorSingleDoorSystem::PanelInterface.na_fuse_panel_steps(entities)` - WindowSystem's FuseParts step 5/6 delegates here.
- `Na__AppCore::SelectionCoordinator.na_register_handler(descriptor)` - each system registers a `{tab_id, resolve_id, on_selected, on_cleared}` descriptor; the coordinator dispatches a single observer to all systems.
- `Na__AppCore::DialogManager.na_register_system_init_hook(&block)` - each system Init registers a block that is invoked with the live dialog when the dialog opens; inside the block the system registers its callbacks via `UiBridge.na_register_callbacks(dialog, registry)`.
- **Both registries start empty on every open (V2.7.0).** `Na__AssemblyStudio.na_init` calls `SelectionCoordinator.na_clear_handlers` and `DialogManager.na_clear_system_init_hooks` before the system Inits run. `UI::HtmlDialog#add_action_callback` keeps every callback registered under one name and runs them all, so a hook registered twice made every dialog action run twice. Never register a callback on a dialog that is already showing: close it and open it again.

## Error handling policy
See `01__AppCore/Na__AssemblyStudio__AppCore__ErrorPolicy__.md`. In short:
- Narrow rescues only.
- Broad `rescue StandardError` only at the top of `add_action_callback` blocks.
- All diagnostic output through `DebugTools`; all user-visible status through `UiBridge.na_send_status`.
- No bare `rescue`, no `... rescue nil`, no `Integer(...) rescue false` (use `rescue ArgumentError, TypeError` instead).

## Loader install
The Plugins-root loader is `Na__ElementAssemblyStudioPro__Loader.rb`. SketchUp loads it on startup. The loader:
1. Resolves the modules root path.
2. Requires `02__Src__AppModules/01__AppCore/Na__AssemblyStudio__AppCore__Main__.rb`.
3. Registers a `UI::Command` that calls `Na__AssemblyStudio.na_init`.
4. Adds the command to the Plugins menu and the "Element Assembly Studio Pro" toolbar.

## Reference docs
- `RewireMap.md` - module-to-module wiring map (Ruby require graph + JS load order + JS<->Ruby callback table).
- `DEVLOG.md` - chronological refactor history.
- `01__AppCore/Na__AssemblyStudio__AppCore__ErrorPolicy__.md` - rescue policy.

## InteriorDoor handle behavior
- Interior single-door handle placement follows swing-side behavior.
- The previous dedicated handle-side selector is removed from the UI workflow.

## InteriorDoor rotation pivot helper (TrueVision3D contract)
`ROT001__RotationPoint__DoorHingeCentre` is the door's rotation pivot consumed by the downstream TrueVision3D `Na__DoorAnimation__` module, which reads `rotObject.position` (the group's local origin) as the pivot for the click-to-open animation.

- **No inner ADR wrapper**: the door's ComponentDefinition itself (`ADRnnn__InteriorDoor__`) is the ADR for TrueVision3D's prefix-matching scanner. MOD and ROT are direct siblings at the definition root - we deliberately do NOT wrap them in an inner `ADR001__InternalDoor` group because the GLB Builder collapses redundant single-child groups, which used to strip the MOD prefix and break the click-to-open animation.
- **Hierarchy placement**: the ROT group lives at the **ComponentDefinition root level** (sibling of the MOD group) so the SketchUp author can grab the pivot helper without drilling into the door panel hierarchy. A single ROT is shared between the closed and open MOD copies.
- **Pivot positioning**: the composer translates the ROT group to the hinge axis via `na_translate_rot_marker_to_hinge` and then `Na__RotationPivotBuilder.na_build_pivot_helper` populates it with visible debug geometry inside that group's local coordinate space (hinge centre = `(0, 0, 0)`).
- **Helper geometry**: a vertical hinge axis line inset 100 mm from the bottom and top of the inner jamb opening, a 50x50 mm `+` crosshair on the XY plane at each end of the line, and a quarter-circle swing-direction arc + arrowhead at the top crosshair (computed from `Na__DoorConfig__SwingSide` + `Na__DoorConfig__SwingDirection`).
- **Red colouring**: as the final build step every helper edge is painted red via `Na__EdgeColourManager.na_apply_edge_colour_to_group(rot_group, "MTE201__LineColour__Red")`. This mirrors the dark-grey edge-colour application used by `Na__PanelDesignBuilder` for door panel design linework, and ensures the helper is unambiguously red in SketchUp regardless of the active "colour by tag" display option.
- **Tag visibility control**: all helper edges are tagged on `02__DoorHelpers__RotationPivots`, which is red, dashed (`Sketchup::Layer#line_style = Sketchup.active_model.line_styles["Dash"]`), excluded from GLB export by both its `02__` numeric prefix (in `Na__DataLib__CoreIndex__Tags__.json` `meta.skipRanges`) and `Glb__FullyExcluded: true`.
- **MOD rotation direction (per swing direction)**: the moving panel group is named according to the door's `Na__DoorConfig__SwingDirection`, picked at build time by `Na__DoorAssemblyComposer.na_resolve_mod_panel_name(config)`:
    - **Outward** -> `MOD001__ROT__-90-Deg__DoorPanel` (clockwise when viewed from above in TrueVision3D)
    - **Inward** -> `MOD001__ROT__90-Deg__DoorPanel` (counterclockwise when viewed from above)
  TrueVision3D's `Na__DoorAnim__DEG_REGEX` (`/(-?\d+)-Deg/i`) parses the signed degrees from the group name to drive its click-to-open Y-axis rotation. The SketchUp open-state copy direction is computed independently from `SwingSide` + `SwingDirection` in `na_compute_open_rotation_transform` and remains visually consistent with the TV3D animation.
- **Module file** (one feature per file per workspace rules): `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__RotationPivotBuilder__.rb`.

### Tag line style configuration (Layout__LineStyleName)
Tag JSON entries gain an optional `Layout__LineStyleName` field (string) keyed off the SketchUp Ruby `Sketchup::LineStyles` collection. The list of supported names (case sensitive) is documented in the `LineStyleReference` block at the bottom of `Na__DataLib__CoreIndex__Tags__.json` along with a copy-paste tag template. `TagManager.na_get_or_create_tag` reads the field via `na_apply_line_style_for_role`, falls back to a small in-Ruby table (`NA_ROLE_DEFAULT_LINE_STYLES`), and applies via `Sketchup::Layer#line_style=` only if the active SketchUp version exposes the API.

## InteriorDoor handle asset + exporter contract
- Canonical handle contract template lives at `04__Data__AssetLibrary/InteriorDoor__Handles__/Na__StandardTemplate.json`.
- `65__Dev__DevTools/Na__AssemblyStudio__DevTools__JsonExporter2D__.rb` now emits Na__ unified roots (`meta`, `Na__Asset__Metadata`, and one of `Na__Asset__Plan2D` / `Na__Asset__Elevation2D`) rather than legacy ValeSpec keys.
- `65__Dev__DevTools/Na__AssemblyStudio__DevTools__JsonExporter3D__.rb` now exports:
  - standardized `Na__Asset__Mesh3D` vertices/faces (`VertexId`, `OuterLoop_VertexIds`) compatible with `Na__HandleBuilder3D`,
  - recursive nested Group/Component hierarchy metadata in `Na__Asset__ObjectHierarchy3D` with local+world transforms.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__.rb` resolves `handles / architraves / hinges` bucket folder names from AppConfig (`assetLibrary.interiorDoor.*`) with fallbacks.
- Interior and exterior door elevation previews draw a handle from its `Na__Asset__Elevation2D` paths (cache `NA_DOOR_HANDLE_ASSET_PREVIEW_CACHE`, filled by the interior door bridge). An exterior handle without paths, like the Scroll, keeps the drawn schematic. Plan previews and DXF still use a generic marker.
- Handle edges are all painted `MTE103` by `Na__HandleBuilder3D`, then any edge record naming an `EdgeColourId` is repainted in that MTE (the lever handle's 2D keyhole, `MTE105`).
- A new handle needs no code: drop its JSON into `InteriorDoor__Handles__` or `ExteriorDoor__Handles__` and the dropdowns list it by `Na__Asset__Name`. Assets can come from the Dev Tools exporter (modelled by hand) or be written by a generator (`DevTools__CabinetryAssetGenerator__.js`; the lever handle's `lever_asset_writer.py` in the `mcp-sketchup-3d-modeling-expert` skill).

## Materials & Frame Finish Swatches (URL-first cache)

The plugin's frame-finish swatches (visible on the Window tab as "Frame Finish" and on the Interior Door tab as "Joinery Finish" + "Handle Finish") are sourced exclusively from the live materials JSON. There are NO hardcoded swatches in the JS layer.

### Data source
- Canonical file: `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json`
- Live URL: `https://raw.githubusercontent.com/Adam-Noble-01/Plugins/main/Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json`
- Two independent swatch palettes are declared inside `meta.Na__DataLib__UiDefaults`:
  - `Na__DataLib__UiDefaults__FrameFinish` -> 6 wood/paint swatches used by the Window's "Frame Finish" row AND the Door's "Joinery Finish" row (broadcasts to Lining + Panel + Architrave material IDs).
  - `Na__DataLib__UiDefaults__HandleFinish` -> 5 metal ironmongery swatches (Chrome, Brushed Steel, Satin Nickel, Unlacquered Brass, Bronze) used by the Door's "Handle Finish" row only.
- Each palette block holds three children: `...__SwatchKeys`, `...__DefaultSwatchKey`, `...__SwatchLabels`.
- Handle-finish materials live in the new `MAT600__MetalSeries__` group (IDs `MAT612` through `MAT616`), following the ValeSpec `MAT6XX__Metal__Ironmongery__*` convention. Brass + Bronze + Satin Nickel hex values are taken straight from ValeSpec's `ValeSpec__AppConfig__Main__.json`.

### Load flow on dialog open
1. `DialogManager.na_show_dialog` calls `MaterialManager.na_force_refresh_from_url`.
2. `MaterialManager` calls `Na__DataLib__CacheData.Na__Cache__LoadData(:materials, true)`.
3. The shared loader fetches the GitHub raw URL FIRST. On HTTP 200 it overwrites the cache file in `90__AppCache__TempFilesCache/`.
4. If the URL fails (offline, DNS, SSL, timeout) the loader reads the existing cache file from the same folder so the plugin keeps working with the last known good copy. **The cache file is never deleted.**
5. After the dialog HTML is loaded, the front-end fires `sketchup.na_requestFrameFinishSwatches()` which triggers `Na__FrameFinishSwatches.na_push_to_dialog` to set:
   - `window.NA_FRAME_FINISH_SWATCHES`      - array of `{id, label, hex}` (wood/paint)
   - `window.NA_FRAME_FINISH_DEFAULT_KEY`   - default ID for the frame palette
   - `window.NA_HANDLE_FINISH_SWATCHES`     - array of `{id, label, hex}` (metals)
   - `window.NA_HANDLE_FINISH_DEFAULT_KEY`  - default ID for the handle palette
   - `window.NA_MATERIALS_LOAD_STATUS`      - `'ok'` or `'failed'`
6. The push then invokes `Na_FrameFinishCards.na_render_all()` so the door's Joinery + Handle rows AND the window's Frame Finish row all populate immediately. Each row hides independently if its own palette is empty.

### Cache directory override
`Na__DataLib__CacheData` defaults to `Sketchup.temp_dir`. EASP overrides this in `na_init` via `Na__Cache__SetCacheDirOverride(NA_CACHE_DIR_PATH)` so cached files live in the plugin's own `90__AppCache__TempFilesCache/`. Other plugins (e.g. `Na__EdgeUtil__PaintDeepNestedEdges__`) do not set the override and continue using `Sketchup.temp_dir`.

### Failure UX
- If the materials JSON cannot be loaded (URL + cache + local fallback all fail), the door's Joinery Finish + Handle Finish sections and the window's Frame Finish control stay hidden -- no fallback swatches are emitted. This is intentional: empty UI = unambiguous "data missing" signal.
- A persistent toast appears in the shared `#na-status-bar` strip: "Na materials library could not be loaded from the web. Finish swatches are hidden - check internet connection." Persistent toasts are a new feature of `na_showStatus(type, message, persistent=true)` and `UiBridge.na_send_status(dialog, type, message, persistent: true)`.

### Hardcoded fallbacks (Ruby side)
Only two materials are hardcoded as a last-resort safety net so geometry can still be created when the materials library is unavailable:
- `MAT001__Default`
- `MAT101__GenericGlass`

These are created on the active model by `MaterialManager.na_ensure_safety_materials`. All other materials (timbers, paints, metals) come from the live JSON exclusively.

## Edge Colour Library (URL-first cache)

The plugin loads the Noble Architecture standard line-colour palette (MTE prefix) from the same `Na__Common__DataLib__CoreSuEntityStandards` repository that hosts face materials. The palette is consumed by the door panel design subsystem to paint generated linework with consistent dark-grey edges across every door.

### Data source
- Canonical file: `Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__EdgeMaterials__.json`
- Live URL: `https://raw.githubusercontent.com/Adam-Noble-01/Plugins/main/Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__EdgeMaterials__.json`
- DataLib key: `:edge_materials` (registered alongside `:materials`, `:tags`, `:components`).
- Default panel-design colour: `MTE103__LineColour__DarkGrey__L40` (#666666).

### Load flow on dialog open
1. `DialogManager.na_show_dialog` calls `MaterialManager.na_force_refresh_from_url` AND `EdgeColourManager.na_force_refresh_from_url`.
2. `EdgeColourManager` calls `Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials, true)` (URL first, cache fallback, local plugin copy as last resort - cache file never deleted).
3. The flat `{ mte_id => entry_hash }` index is held in-memory for the session; subsequent `na_get_edge_material_by_id` calls resolve in O(1) and lazily create matching `Sketchup::Material` entries on the active model.
4. `EdgeColourManager.na_apply_edge_colour_to_group(group, mte_id)` recursively walks groups + component instances and assigns the resolved material to every `Sketchup::Edge` it finds. Used by `Na__PanelDesignBuilder` after each design build.

### Developer reload
The `Reload Scripts` flow purges the on-disk cache for both `:materials` AND `:edge_materials` and re-fetches both from the live URL before reloading any Ruby files, so the next dialog open is guaranteed to see the latest published palettes.

### Hardcoded fallback
Only one edge colour is hardcoded as a last-resort safety net: `MTE103__LineColour__DarkGrey__L40` at RGB(102, 102, 102). It is created by `EdgeColourManager.na_create_safety_dark_grey_material` if and only if the live library fails AND the canonical dark-grey id is requested. All other MTE colours come from the live JSON exclusively.

## Door Panel Design Subsystem

Decorative UK-style panel linework on the front and back faces of an interior door panel. Entirely separate from the door panel solid - never modifies the panel, never adds faces, only authors `Sketchup::Edge` instances inside a dedicated nested group.

### Group nesting hierarchy
```
ComponentDefinition: ADRnnn__InteriorDoor__       [outer ADR for TrueVision3D - ComponentDefinition itself]
  Na__Lining__Container                          [static]
  <architraves>                                  [static]
  Na__DoorSwing__2D                              [static]
  ROT001__RotationPoint__DoorHingeCentre         [origin = hinge; shared by closed + open MODs]
    <pivot helper edges>                         [tag: 02__DoorHelpers__RotationPivots, MTE201 red, dashed line style]
  MOD001__ROT__{NN}-Deg__DoorPanel (closed)      [tag: door_closed]   {NN} = -90 outward, +90 inward
    Na__DoorPanel__Solid
    <handle groups>
    Na__DoorPanel__DesignContainer
      Na__PanelDesign__FrontFace                 [edges only, Y = panel_front_y - 0.5mm]
      Na__PanelDesign__BackFace                  [edges only, Y = panel_back_y  + 0.5mm]
  MOD001__ROT__{NN}-Deg__DoorPanel (open copy)   [tag: door_open]    {NN} matches the closed MOD
    <duplicated MOD via Sketchup::Group#copy, rotated 90deg about the hinge>
```
There is NO inner `ADR001__InternalDoor` wrapper group around the MOD - the door's ComponentDefinition (`ADRnnn__InteriorDoor__`) is the ADR for TrueVision3D's prefix-matching scanner, and MOD/ROT sit as direct siblings inside it. A redundant single-child wrapper group would otherwise be flattened by the GLB Builder, stripping the MOD prefix that the click-to-open animation needs.
The container sits inside `MOD` so the linework rotates with the door. The open ADR copy is built by duplicating the closed ADR, so the design subsystem only needs to run once per build (no manual mirroring).

### Module layout (one responsibility per file)
- `02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__.rb` -> URL/cache loader for the MTE palette + per-edge material application.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__.rb` -> `na_compute_layout` resolves the inner perimeter from the four constraint sliders; `na_draw_inner_perimeter` draws the shared four-edge rectangle each style sits inside.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__VerticalNarrow__.rb` -> divides the inner perimeter into N equal panes where N = (inner_w / preferred_pane_w).round.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__ClassicalSix__.rb` -> Georgian 38/38/24% three-tier layout + central mullion = 2+2+2 panels.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__FourPanel__.rb` -> 2x2 grid (one cross-rail at mid-Z + one mullion at mid-X).
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__HorizontalThree__.rb` -> two cross-rails at 1/3 and 2/3 of inner-perimeter height (no mullion).
- Note: file segments use `PanelStyle__` rather than `PanelDesignStyles__` to keep the absolute Windows path under the 260-character `MAX_PATH` limit that SketchUp's Ruby `require_relative` enforces. The Ruby module names inside each file remain `Na__PanelDesignStyles__*` for clarity.
- `40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__PanelDesignBuilder__.rb` -> orchestrator. Reads config, dispatches to the right style, wraps result in `Na__DoorPanel__DesignContainer`, applies edge colour.
- Geometry primitives `na_create_xz_line`, `na_create_horizontal_rail_lines`, `na_create_vertical_rail_lines` live on `Na__GeometryHelpers` so every style draws rails the same way.

### Configuration keys (Na__DoorConfiguration)
- `Na__DoorConfig__PanelDesignEnabled`              - master on/off (default `true`).
- `Na__DoorConfig__PanelDesignStyle`                - one of `None`, `VerticalNarrow`, `ClassicalSixPanel`, `FourPanel`, `HorizontalThree` (default `None`).
- `Na__DoorConfig__PanelDesignStileWidth_mm`        - side stile width, drives BOTH stiles (default `95`).
- `Na__DoorConfig__PanelDesignTopRail_mm`           - top rail height (default `100`).
- `Na__DoorConfig__PanelDesignBottomRail_mm`        - bottom rail height (default `200`).
- `Na__DoorConfig__PanelDesignInnerRailThickness_mm` - cross-rail / mullion thickness (default `70`).
- `Na__DoorConfig__PanelDesignVerticalPaneWidth_mm` - preferred pane width for VerticalNarrow only (default `90`).
- `Na__DoorConfig__PanelDesignEdgeColourId`         - MTE id for the linework (default `MTE103__LineColour__DarkGrey__L40`).

### Wiring
- `Na__DoorAssemblyComposer.na_compose_closed_assembly` calls `Na__PanelDesignBuilder.na_build_panel_design(config, mod_ents)` after `Na__HandleBuilder3D.na_build_handles`.
- `Na__InteriorDoorSystem.na_init_door_callbacks` -> `na_require_door_modules` requires all six new files (one EdgeColourManager + one Frame + four Styles + one Builder).
- The dialog UI exposes the new controls in `window.NA_DOOR_PANEL_TAB_CONFIG` (Panel & Swing tab). The Vertical Pane Width slider is hidden by `Na_DoorUI.na_sync_panel_design_visibility` for any style other than VerticalNarrow.
