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

## Integration

- `na_ready` handshake and acknowledged `na_event` requests connect HtmlDialog to the Ruby controller. Requests are serialised, slider events are debounced/coalesced, and editing requests carry a session, selection context and persistent entity ID.
- Selection, model, entity and app observers defer refreshes onto a UI timer. Undo/redo, lock changes, editing-context changes and model changes refresh or release the editing target. Closing/reloading detaches observers and cancels pending refreshes.
- `Na__VegetationSketcher__Definition/data` stores schema version 2, metadata and configuration JSON on the component definition, following Element Assembly Studio Pro's portable-definition pattern.
- `Na__VegetationSketcher` stores instance identity and compatibility settings; `Na__VegetationSketcher__Model/last_settings` stores per-model creation defaults. Legacy group settings remain readable.
- `HedgePath` validates and constructs the mitered sweep. `Mesh` owns the shared vertices used by panel preview, viewport preview and final creation. `Builder` owns native geometry and the undo operation.

## Verification

`tests/run_ruby_checks.py` runs the isolated Ruby tests using SketchUp's bundled Ruby 3.2 interpreter. It does not control SketchUp or modify an open model. The `.rb.test` suffix prevents the plugin's recursive Ruby reloader from executing tests.

`tests/ui.test.js` runs the actual HTML and JS in Chromium against a bridge double. Pass the Playwright package path and, optionally, the browser executable path as arguments. Run the Ruby tests first to generate the preset fixtures.

Verified: **157 Ruby checks** and **52 Chromium checks**, including preview coalescing and cancellation, viewport mesh reuse and final density, species dimensions and topology, seed variation at fixed bounds, species persistence and live switching, default inputs, acknowledged Draw/Finish commands, selection lifecycle, saved path round trips, stale edits, manifold corner topology, keyboard events and smoothing flags. Species previews are also visually checked in Chromium. These tests do not measure native SketchUp responsiveness; the latest performance changes await the user's SketchUp check.
