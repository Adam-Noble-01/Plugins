# Array Builder 0.4 validation

Run offline regression checks from the Plugins directory:

```powershell
python Na__ArrayBuilderTools__Modules__/65__Dev__Tests/Na__ArrayBuilder__RunRubyChecks__.py
node Na__ArrayBuilderTools__Modules__/65__Dev__Tests/Na__ArrayBuilder__UiInput__Spec__.mjs
```

The Python runner embeds SketchUp 2026's bundled Ruby in an isolated process. It
does not connect to a running SketchUp model. Ruby specifications use explicit API
doubles for layout, serialization, gallery storage, controller sessions and geometry
operation contracts. They do not verify SketchUp's native face builder or observers.

The `.rb.test` suffix prevents tests being picked up by Ruby reloaders. Production
code has no dependency on the tests, other Noble plugins or test fixtures.

For native verification, hot reload Array Builder (or restart SketchUp) to load 0.4, open a new EMPTY model and
run in the Ruby Console:

```ruby
load File.join(Sketchup.find_support_file('Plugins'), 'Na__ArrayBuilderTools__Modules__', '65__Dev__Tests', 'Na__ArrayBuilder__SketchUpSmoke__Spec__.rb.test')
```

This leaves test arrays in the empty model and checks native construction, single
and linked update scope, dictionary round-trip, Undo/Redo, native corner union, and
creation inside three transformed open contexts. It also archives a real nested
group source, removes its original references, restores native SKP bytes and
checks nested attributes/materials before rebuilding. Save and reopen that test
model; reselect the custom array and verify its source and parameters restore in
Create / Edit Array. Edit selected and Edit Noble Array use the same controls.

Interactive checks:

1. Draw an open path and change width, gap, offsets, reverse and upright mid-draw.
   Both previews and metrics should update. Finish using Enter and the dialog.
2. Repeat using selected edges, a curve and a closed face outline. Press R while
   reviewing a selected path, then edit the completed array and reverse it again.
3. Move, rotate and scale an array; edit it and redraw its path. Repeat inside a
   transformed group. Position, tag, material and transformation should persist.
4. Edit Only this array, then All linked copies. Lock a linked copy and confirm the
   linked update is rejected without touching geometry.
5. Type blank, '-', '15 cm', '0.15 m' and '6 in'. Incomplete fields must keep the
   last valid preview. Large layouts must report the 5,000-unit limit.
6. Turn Live Mode off, prepare changes and press Update array. Undo/Redo, change
   selection, switch models and close/reopen the dialog with pending input.
7. Pick a scaled source whose axes are offset from its bounds. Save an object
   preset; use it in a new model; verify dimensions, alignment and spacing.
8. Save, rename/update, duplicate, search and archive gallery records. Restore an
   archived JSON to the gallery folder. Missing source files and malformed JSON
   must report an error while the remaining gallery stays usable.
9. Pick a detailed source with multiple nested, translated, rotated and scaled
   children. Pause for 120 ms while drawing: both previews must show its actual
   faces and edges. Compare positions with the committed instances. Repeat while
   three parent groups are open. No preview geometry should enter the Undo stack.
10. Enter `1200/3`, `(250+50)*2`, `+50`, `*2`, and `1 m - 25 cm`. Commit using
    Enter and blur. `1/0`, `100+`, blank and `-` must retain the previous preview.
    In each box check Up/Down adds/subtracts 5 mm, Shift 50 mm. Type 9000 into a
    slider parameter and verify the slider expands rather than capping it at 2000.
11. In Fixed end margins, use -50: the first leading face starts 50 mm before the
    segment and the last trailing face ends 50 mm beyond it. Save/reload the preset.
12. Parametric blocks: switch Merge corner objects on at an overlapping bend,
    inspect the resulting native solid, then off. Repeat in Edit with Undo/Redo.
    The pre-build illustration shows constituent units; the built/live-updated
    geometry uses the native union. Custom objects never invoke solid union.
13. In Settings, Hot reload twice. The draft/source and current edit target should
    survive; an unfinished path should cancel. Check that callbacks, context-menu
    entries and model observers have not duplicated. Change a JS/CSS file and
    confirm the reopened panel uses it. Reload never changes model geometry.

14. Draw three sides of a rectangle in empty space. Follow the dashed guide from
    Start to align the final corner; click the highlighted Start to close. Repeat
    with a red/green axis lock and a rotated rectangle. The committed point must
    match the preview exactly; moving deliberately beyond the guide must release
    the snap. Repeat while nested groups are open, at different zoom levels and
    after Backspace. Exact existing vertices must not round onto the 1 mm grid.
15. Build from a scaled custom Group, deselect and reselect it, then adjust its gap.
    Close/reopen the dialog and model. Repeat with a ComponentInstance. Delete the
    original picked object; editing must still restore the source. Existing arrays
    should acquire the native snapshot on their next successful update.
16. Change Custom object to Parametric block, save/reopen, then switch back. The
    original custom source must return. In the dedicated test model, remove all
    generated units and the original source, then Edit selected to recover from
    the archived geometry. Undo the rebuild and verify model/data consistency.
17. With an array selected, visit Settings and return to Create / Edit Array.
    Editing must persist. New array must keep parameters/source and show creation
    controls despite the old selection. Deselect/reselect or select another array
    to resume editing. Save to gallery must open Preset Editor with those settings.

The isolated suite currently passes 135 Ruby checks plus the JavaScript arithmetic,
unit parsing and mesh projection tests. New checks cover group source recovery,
archive transport/corruption, selection lifecycle, rotated-plane inference, lock
compatibility, pixel hysteresis and preview/click consistency. Browser interaction
checks cover combined editing, Settings round-trip, New array and preset navigation.
The developer-only `Na__ArrayBuilder__UiSession__Fixture__.html` hosts the real UI
with a simulated SketchUp bridge for repeating these browser checks; it never
connects to a model. Earlier browser checks cover formulas, nudges and signed
margins. Native smoke tests are supplied but have not been run in this session.

Pre-0.2 arrays contain no stored recipe or path and cannot be edited parametrically.
Existing geometry remains intact; recreate those arrays once to enable editing.
