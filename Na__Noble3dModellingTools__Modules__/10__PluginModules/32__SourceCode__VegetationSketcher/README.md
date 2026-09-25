# Noble Vegetation Sketcher

Open **Geometry Tools > Landscape Tools > Vegetation Sketcher**.
After installing an update, close the dialog, use **Reload Plugin Data**, then reopen it.

## Create

- **Hedge:** choose **Draw hedge in SketchUp**. Click a start point, then click each corner. Dragging sets the first run too. The whole path stays in preview until **Enter**, **double-click**, **right-click**, or **Finish hedge** creates one component.
- **Tree / Shrub:** choose **Plant in SketchUp**, then click to place. Repeat to plant more. **Finish** ends placement and loads the last planting for editing.
- No selection is required to create vegetation. **New vegetation** leaves editing mode.

### Hedge controls

| Control | Action |
| --- | --- |
| Right arrow | Toggle red / X direction lock |
| Left arrow | Toggle green / Y direction lock |
| Down arrow | Toggle parallel to the preceding run |
| Up arrow | Release the direction lock |
| Type a length, then Enter | Add the next run at that length; units such as `3000mm` work |
| Enter with no typed value | Finish the hedge |
| Backspace / Delete | Remove the last waypoint; normal text editing while entering a length |
| Esc | Cancel the current unbuilt path; Esc again exits |
| R | New organic variation |

Locks re-anchor at every corner. Hedges use open paths on the horizontal plane through the first point. Miter sections join adjacent runs with shared vertices and no internal caps. Excessively sharp turns, overlapping runs and runs too short for their hedge width are rejected before creation. Change the path or width to resolve these cases.

## Shape and shading

- Resolution defaults to **100 mm** for Hedge, Generic canopy and Shrub, with **10 / 25 / 50 / 200 / 300 / 500 mm** options. Full-size species have coarser starting spacing as listed below.
- Corner rounding and the path sweep are calculated before XYZ randomisation.
- **Smooth model shading** defaults **on** for new vegetation: a **40.3 degree** edge threshold, smooth normals and coplanar softening. Off restores faceted shading. Shading changes do not change the mesh shape.
- Existing objects retain their saved shading choice. Select one and change the toggle to update it.
- A seed makes organic variation repeatable. Tree and shrub planting can vary the seed at each placement.
- Creation is limited to 80,000 foliage quads. The bounded preview identifies when it is simplified. Final geometry uses the selected resolution.
- SketchUp stores non-planar quads as paired triangles, with hidden internal diagonals. Hidden Geometry exposes the mesh.

## Tree types and real-world scale

Choose **Tree**, then **Tree type**. Generic canopy retains the original adjustable rounded form. Changing type loads its starting dimensions and mesh spacing; smoothing, the seed and automatic variation are retained. During live editing this updates the selected tree. With live editing paused, use **Update selected** to apply the new type.

| Type | Total height | Canopy width × depth | Crown base | Trunk diameter | Starting grid |
| --- | --- | --- | --- | --- | --- |
| Generic canopy | 5.2 m | 3.2 × 2.8 m | 1.8 m | 240 mm | 100 mm |
| Douglas fir (*Pseudotsuga menziesii*) | 18 m | 7 × 7 m | 0.9 m | 600 mm | 200 mm |
| English oak (*Quercus robur*) | 20 m | 20 × 18 m | 3.5 m | 1,100 mm | 300 mm |

Douglas fir uses a tiered, tapered conical crown and a slender central leader. English oak uses a single closed crown with clustered lobes, a stout bole, five spreading scaffold limbs and forks. Both remain opaque whitecard geometry. Crown rounding changes the species form before XYZ noise; smooth shading remains a separate toggle.

The species presets are representative landscape specimens, not age predictions or maximum sizes. The Douglas fir starting size falls within Iowa State Extension's [40–60 ft height and 15–25 ft spread](https://naturalresources.extension.iastate.edu/forestry/iowa_trees/trees/douglas_fir.html) for landscape trees. English oak uses a size within TCV's [20–40 m height and 15–25 m spread](https://www.tcv.org.uk/i-dig-trees-tree-library/common-oak/). Crown-base heights and trunk diameters are indicative modelling choices and can be edited to match a surveyed tree.

For Douglas fir and oak, entered height/width/depth are **actual overall geometry bounds in the component's local axes**, including randomisation. The foliage is fitted after displacement; both previews and final construction have the requested dimensions. Crown base is the lowest foliage height, while branches may begin below it. Geometry is authored in millimetres and converted to SketchUp inches only at the model boundary. External instance scaling affects world dimensions as with any SketchUp component.

Species and edited dimensions survive selection changes, model saving, copied definitions and live edits. Older trees without species data load as Generic canopy. Taller trees (up to 100 m) and wider canopies (up to 50 m) can be entered; choose a coarser grid if the 80,000-quad limit is exceeded.

## Small-to-mid shrubs for planting beds

Choose **Planting > Plant type > Shrubs**. Six indicative whitecard forms complement the original Generic shrub:

| Form | Height | Width × depth | Role in a bed | Starter mix share |
| --- | --- | --- | --- | --- |
| Low spreading | 250 mm | 800 × 700 mm | Low groundcover / front edge | 15% |
| Compact cushion | 450 mm | 550 × 500 mm | Small repeated mounds | 20% |
| Rounded shrub | 750 mm | 850 × 750 mm | Mid-height planting | 25% |
| Loose flowering form | 1,000 mm | 1,100 × 950 mm | Irregular clustered accents | 20% |
| Upright shrub | 1,400 mm | 650 × 600 mm | Narrow vertical accents | 10% |
| Arching shrub | 950 mm | 1,400 × 1,100 mm | Broad, flared foliage | 10% |

These are editable modelling forms, not species-specific planting recommendations. Each uses a single closed quad skin, default 100 mm spacing and smooth model shading. New variation changes the silhouette and XYZ detail while keeping exact width, depth and height. At their starting sizes they use 170–808 foliage quads. Existing shrubs without a type retain the original Generic shrub.

For a complete source set, open **Scatter vegetation > Load planting-bed mix**. This loads **12 sources: two seeded variations of each form**, with the shares above, a **1,200 mm brush radius**, **650 mm minimum spacing**, **90–110% scale** and a 1,500-plant cap. Change the individual weights or set them to zero, then choose **Paint new forest** and brush over the planting-bed face. No sample components need to be planted first. For a front-edge-only pass, keep the low spreading and cushion sources; a separate pass can add the taller accents.

Loading the mix only changes dialog settings. The first successful brush stroke creates shared shrub definitions and plants in the same undo operation; subsequent strokes reuse those definitions. Recipes and seeds are retained in the forest's saved source mix, and creating these sources leaves the individual vegetation tool's last-used settings intact.

## Flowers and ornamental grasses

Choose **Planting > Plant type > Flowers / Grasses**. These use separate stems, flower heads and curved, creased leaves instead of a single canopy envelope. They remain whitecard and indicative, without textures or individual tiny florets.

| Form | Height | Width × depth | Balanced quads |
| --- | --- | --- | --- |
| Daisy-like clump | 600 mm | 650 × 600 mm | 914 |
| Flower spikes | 850 mm | 600 × 550 mm | 914 |
| Flat flower clusters | 800 mm | 750 × 650 mm | 1,534 |
| Compact tuft grass | 450 mm | 500 × 450 mm | 384 |
| Fountain grass | 900 mm | 950 × 850 mm | 528 |
| Plumed grass | 1,400 mm | 1,000 × 850 mm | 1,116 |

**Plant detail: Light / Balanced / Fuller** controls fullness and curve subdivisions. Every finished plant is capped at **2,000 quads / 4,000 triangles**, regardless of its dimensions. The grid-resolution control returns when selecting a shrub or hedge. **Leaf arch / petal cup** changes blade droop and flower shape; **Stem variation** bends stems and grass blades coherently. New seeds rearrange the clump while retaining exact overall size.

Leaves and petals use thin two-sided surfaces; stems and flower heads use closed sections. The complete plant is therefore a collection of surfaces, not a single watertight solid. Smooth model shading works as before. Viewport placement uses reduced curve segments and head sides, with a **1,000-quad cap**; final construction uses the selected detail. HTML changes retain the 650 ms quiet period.

**Scatter vegetation > Load flowers & grasses mix** loads two variants of each of the six types at Balanced detail: 25% daisy-like, 20% spikes, 15% flat clusters, 20% tuft, 15% fountain and 5% plumed grass. The initial brush radius is **900 mm**, spacing **500 mm**, scale **90–110%**, and the plant limit is **1,000**. Individual source weights remain editable. This loads a new mix without changing an existing selected forest. Custom combinations and other detail settings can be captured from individually planted components with **Use selected vegetation**.

## Placement variation

For **Tree** and **Planting**, the **Placement variation** card gives each click its own roll, using the same kind of ranges as the Scatter brush:

| Range | Default | Limits | Effect |
| --- | --- | --- | --- |
| Minimum / maximum size | 90–110% | 10–500% | Uniform scale of the whole plant |
| Minimum / maximum height stretch | 95–105% | 25–400% | Extra vertical scale on top of size |
| Random rotation | 360° | 0–360° | Turn about the vertical |
| Maximum lean | 0° | 0–30° | Tilt in a random direction, pivoting on the base |

The viewport preview shows the next roll. The status bar and the panel describe it, for example *Next plant 104% size, 98% height, 212° turn*. **R** rolls again, together with a new form seed. Untick **Randomise each placement** to plant at exactly the dimensions entered.

The roll is applied as the instance transform, as in Scatter. The component definition keeps the exact base dimensions, which the panel shows and edits; Entity Info shows each plant's scale. Editing a placed plant rebuilds its definition and keeps its scale, turn and lean. The ranges are saved as a user preference rather than in the vegetation, and changing them never updates selected vegetation. A value outside its limits, or a minimum above its maximum, is refused with a message naming the fix.

## Edit

Selecting one unlocked Noble vegetation component or legacy group automatically loads its settings. **Live update selected vegetation** applies changes after a brief pause. Turn it off to use **Update selected** manually. Creation and each applied update are undoable.

The hedge path is saved with its configuration. Changing width, height, variation or shading preserves the corners. Changing **Total path length** scales the saved path while keeping the hedge width independent. Editing a copied component makes that instance unique first.

## Preview performance

- Form edits wait for **650 ms without further input** before sending the latest settings to SketchUp. New typing replaces any older queued slider edit.
- The HTML preview and drawing-progress message have a separate **650 ms quiet period**. Repeated requests coalesce before mesh generation or JSON transfer; while drawing, the panel reuses the existing viewport mesh. This keeps mesh streaming out of the mouse-event path.
- **Draw, Finish and Update selected** carry the current form immediately and discard redundant queued options. Final geometry always uses the selected resolution.
- Drawing previews use **50% linear resolution**: twice the grid spacing, for example **100 mm final → 200 mm preview**. A **1,300-quad** drawing cap also reduces detail for large trees and paths. The settled standalone dialog preview retains its 2,600-quad cap.
- Hedge mesh refreshes are limited to ten per second while moving; a trailing refresh catches the last cursor position. The inference line and native measurement display follow the cursor immediately. Tree movement reuses its cached mesh.
- Closing the dialog, switching editing contexts or leaving the tool cancels the relevant pending work. No preview-quality settings are saved into vegetation definitions.

## Scatter forests and shrub beds

Open **Scatter vegetation** inside Vegetation Sketcher.

1. Select vegetation groups or components in SketchUp, then choose **Use selected vegetation**, or load a ready-made mix. Noble vegetation and custom components are supported; hedges and existing forest groups are excluded.
2. Set each source's probability weight. Weights are relative: **75 / 25** gives a 75% / 25% mix; **0** excludes a source. Small samples can differ from these expected percentages.
3. Set brush radius, minimum spacing, placement chance, scale range, random rotation and maximum slope. All distances are in millimetres. **100% scale** preserves the selected source's current world size. Spacing separates planting points, so large canopies can overlap.
4. Choose **Paint new forest**, then drag over a face or connected terrain surface. A ring and stroke points keep dragging light; plants appear on release. Each stroke is one undo step. **Esc** cancels the current stroke; **Enter**, the right-click menu or **Finish** ends the brush and selects the forest.
5. Select a forest to reload its saved mix and settings. Change settings, then choose **Regenerate selected**; **New variation** changes the seed and regenerates. These controls apply explicitly, with no slider-to-Ruby traffic.

Trees stay upright by default. **Align plants to the surface normal** tilts them with the ground. Projection respects face boundaries, holes, terrain triangles and transformed groups/components. Once the brush has acquired a surface, existing scattered foliage does not obstruct continued painting on it.

The forest saves the seed, source mix, settings and brush positions relative to the target surface instances. Regeneration uses the current terrain geometry; regenerate explicitly after editing the terrain. Changing radius changes the footprint around the saved brush positions. An unchanged seed, settings and terrain reproduce the same result. Deleted target surfaces produce an error before modifying the forest.

Plants share source component definitions. A hidden **Scatter sources (hidden)** child retains references so deleting the original sample items does not break regeneration. Avoid removing this child. Regeneration preserves the forest's group transform and makes copied forests unique before replacing generated children. Untagged items manually added to the forest's root remain intact.

Limits keep generation bounded: up to **20 sources**, **2,000 brush positions**, **10,000 plants** and **250,000 sampling attempts** per forest; connected target surfaces are limited to **30,000 faces**. The default plant limit is 2,000. If a dense brush exceeds its sampling budget, increase spacing, reduce radius or create another forest.

## Integration

- `na_ready` handshake and acknowledged `na_event` requests connect HtmlDialog to the Ruby controller. Requests are serialised, slider events are debounced/coalesced, and editing requests carry a session, selection context and persistent entity ID.
- Selection, model, entity and app observers defer refreshes onto a UI timer. Undo/redo, lock changes, editing-context changes and model changes refresh or release the editing target. Closing/reloading detaches observers and cancels pending refreshes.
- `Na__VegetationSketcher__Definition/data` stores schema version 2, metadata and configuration JSON on the component definition, following Element Assembly Studio Pro's portable-definition pattern.
- `Na__VegetationSketcher` stores instance identity and compatibility settings; `Na__VegetationSketcher__Model/last_settings` stores per-model creation defaults. Legacy group settings remain readable.
- `HedgePath` validates and constructs the mitered sweep. `Mesh` owns the shared vertices used by panel preview, viewport preview and final creation. `Builder` owns native geometry and the undo operation.

## Verification

`tests/run_ruby_checks.py` runs the isolated Ruby tests using SketchUp's bundled Ruby 3.2 interpreter. It does not control SketchUp or modify an open model. The `.rb.test` suffix prevents the plugin's recursive Ruby reloader from executing tests.

`tests/ui.test.js` runs the actual HTML and JS in Chromium against a bridge double. Pass the Playwright package path and, optionally, the browser executable path as arguments. Run the Ruby tests first to generate the preset fixtures.

Verified: **417 Ruby checks** and **106 Chromium checks**, including placement-variation ranges, rolls and matrices, preview coalescing and cancellation, viewport mesh reuse and final density, vegetation dimensions and topology, seed variation at fixed bounds, type/detail persistence, live switching, default inputs, acknowledged Draw/Finish commands, selection lifecycle, saved path round trips, stale edits, manifold corner topology, keyboard events and smoothing flags. Flower/grass checks cover all six types at all three detail settings, nondegenerate triangles, exact bounds, reduced viewport geometry and polygon caps. Previews are visually checked in Chromium. These tests do not measure native SketchUp responsiveness.

Scatter adds **73 Ruby checks** and **26 Chromium checks**. Run `tests/run_ruby_checks.py tests/scatter.rb.test` with paths relative to this module, and `tests/scatter.ui.test.js` with the same Playwright/browser arguments as the existing browser suite. Coverage includes weighted sampling, repeatable seeds, spacing, slope limits, holes, transformed terrain, source scale, saved forests, retained source definitions, brush commit/cancel, acknowledged commands, stale targets, damaged data, model switching, both built-in mixes, creating their source meshes on the first stroke and reusing their definitions on regeneration. Ruby tests use native API contract doubles; an end-to-end native SketchUp check of the new flowers, grasses and mix remains for the user.
