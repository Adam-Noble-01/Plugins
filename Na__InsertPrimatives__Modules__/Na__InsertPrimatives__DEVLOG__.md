# Na Insert Primatives - Development Log
# =============================================================================

# =============================================================================

## Version 5.1.13 - 24-Sep-2026 - Staircase: a Block, a Side, and an Even Flight

### Asked For
*"Draw like the volume tool, then select a volume side to be the stairs side and its
creates a equal set of steps"* — *"Report the pitch in degrees as you draw in the preview,
and user can type a value to set the degrees in the VCB, but alteratively can type ####r or
####g or ####r,####g which can control the rise and going if it needs to be strict like a
part k staircase in the UK"* — *"after setting the steps bounds depth the user can press up
or down arrow to increase or decrease amount of steps."* With four mockups: the block, its
side's top edge picked out in blue, and the flight dragged inward under a 35° pitch line.

### The Gesture
1. **Block.** Exactly Drawn Volume: drag the base, then the height, or type
   `3595,1525,1690`. Inherited whole, with grid snapping, CTRL, CTRL+SHIFT, TAB planes and
   arrow-key axis locks.
2. **Side.** The block stays on screen and the side under the cursor turns blue, with an
   arrow pointing into the block. From above, where no side faces the camera, it is the side
   whose top edge is nearest the cursor. Click, or press Enter.
3. **Flight.** Drag inward. The drag sets the **run**, from the chosen side to the top
   riser, and the block past it stays full height as the landing. UP and DOWN add and remove
   a step while the run holds. A gold line runs through the nosings at both ends with the
   pitch written on it. The card beside it gives the risers, goings, run, landing and a
   Part K check. Click or Enter builds.

### Even Steps, Counted the UK Way
N risers and N − 1 goings in the flight, and the landing is the last tread:
`rise = height / N`, `going = run / (N − 1)`, `pitch = atan(rise / going)`. The first riser
stands on the chosen side. A run of the whole block leaves no landing. The top riser then
meets the floor beyond the far face, so the block tops out one rise below its drawn
height. A fresh block opens at the step count nearest a 175mm rise; after that, the rise of
the last stair built is the target, for the session.

### Typed Values
| Typed | Means |
|---|---|
| `35` (`35d`, `35deg`, `35°`) | a **pitch**: the run becomes (N − 1) × rise / tan(pitch) |
| `175r` | an exact **rise**. The risers become the whole number nearest the block's height, and the height becomes risers × 175, so the top can move by up to half a rise. The status bar says how far. |
| `250g` | an exact **going**: the run becomes goings × 250, and the landing takes the rest |
| `175r,250g` | both, in either order |
| `9s` (`9st`, `9steps`, `9risers`) | the **step count** |
| `+5`, `+10r`, `-20g`, `+1s` | relative to the stair on screen |

A bare number is a pitch, as it is on a roof (5.1.10): a stair is specified by its
steepness. In the flight stage a typed value builds the stair, the way a typed pitch builds
a roof. Straight after, the same entries correct it in place. An exact rise or going stays
exact through later corrections, so `9s` after `175r` is nine rises of 175. A pitch
releases an exact going, because both set the run.

### Refused With the Fix Named
Nothing is clamped. Each refusal says what would work, and every fix it names was checked
to be accepted:
- `175` → *175.0° is not a stair pitch — a rise needs r (175r), a going needs g (250g)*
- `30` on a 1690 run → *30.0° needs a 2634.4 run for 10 risers — the block is 1690 deep,
  and 42.0° is the shallowest that fits*
- `250g` on the same → *9 goings of 250 need a 2250 run — the block is 1690 deep; 187.7g
  fits, or 7s at this going*
- `9r` → *a 9 rise is not a step — a step rises at least 50. A count of steps takes an s,
  e.g. 10s*
- `1s`, `200s` and `35,250g` are refused the same way.

### Part K Readout
These are the private stair limits of Approved Document K, Table 1.1: rise 150–220, going
220–300, pitch at most 42°, and 2R + G from 550 to 700. A pass reads green, as `OK · 2R+G
590`, and a failure reads red with the first two problems named. It is a readout, not a
gate, because garden steps and loft ladders get drawn with this tool too. The limits live in
`NA_DRAWN_STAIR_PARTK_RULES`, so a utility or general access stair is one table away. 2R + G
is ADK's "normal relationship" rather than a hard limit, but it is reported as a failure
here, to be on the safe side.

### Built on Drawn Volume, Not Beside It
`DrawnStairTool < DrawnVolumeTool`, the way Deep Ogee and Deep Fillet sit on Deep Chamfer.
It overrides the depth stage's completion and adds two states, `:picking_side` and
`:picking_going`, with their own mouse, Enter, double-click, BKSP, arrow and status
handling. Everything else goes to `super`. Drawn Volume's Subtraction and Transparent
options are answered `false`. They are read by option id, not by mode key, so a
Subtraction left switched on in Drawn Volume would otherwise send the stair hunting for a
group to cut. The volume and the shared mixin are untouched.

### The Drag Cuts a Plane, Not a Line
This is Deep Chamfer's lesson again. The cursor ray is intersected with the block's top
face when the camera looks down onto it, so the landing edge sits under the cursor. At eye
level, or in a side elevation, it is intersected with the side profile through the middle
of the width instead. The plane is chosen from the camera's direction, not the ray's, so it
cannot change mid-drag. The run rounds to the grid the way the chamfer's setback does, CTRL
runs it to a vertex such as the edge of an upper floor, and CTRL+SHIFT rounds that.

### What Is Built
One group, `01__DrawnStaircase`, in one operation. The step profile is laid on one end and
pushed across the width, the way the volume pushes its base. The group is pinned to the
world identity before any point goes in, like every drawn shape (the Coordinate Rule), so
it lands where it was previewed inside open, moved, rotated and nested groups. A correction
rebuilds that group in place. It is refused, rather than landing displaced, if the editing
context has changed since the stair was built.

### Rehearsed Before Shipping
The profile, solve, side frames and entry resolution were ported to Python and run against
the mockup's 3595 x 1525 x 1690 block:
- On all four sides, the first riser stands on the chosen face, the flight covers the
  block's footprint, and the frames wind the same way.
- Every profile is closed, simple and rectilinear, and the preview's column fill tiles it
  exactly, from 2 to 33 risers and runs from 5mm to the whole block.
- A zero run folds to the plain block, a full run leaves no landing, and a run within 0.5mm
  of the far face snaps to it.
- 21 entries are accepted and 15 refused, with every named fix accepted in turn.

### Also: Ogee Moves to the End
Asked for straight after 5.1.12: *"make Ogee last — Chamfer, Fillet, Ogee"*. The Modify
tools now read Deep Push Pull, Deep Chamfer, Deep Fillet, Deep Ogee. The popup shows the
new order straight after Reload Plugin Data. The Extensions submenu shows it after a
SketchUp restart, because the API cannot move a menu item that already exists. Load order
is unchanged.

### Files
- **New** `22__System__DrawnStairs/`:
  - `Na__InsertPrimatives__DrawnStairTool__.rb`, the tool;
  - `..__DrawnStair__Geometry__.rb`: block frame, side frames and picking, the drag plane,
    step count, solve, profile, Part K and the build;
  - `..__DrawnStair__Entry__.rb`: the typed grammar and its resolution;
  - `..__DrawnStair__Preview__.rb`: the side and flight previews.
- `01__AppCore`: the manifest entries, `Na__ModeSwitch__ActivateDrawnStairTool`,
  `Na__DrawnMode__SetStairMode`, and the folder map.
- `40__UserInterface`: the Staircase button under Draw and its callback, and Fillet above
  Ogee.
- `Na__InsertPrimatives__Loader__.rb`: the `NA_DrawStaircasePrimitive` command, the
  `staircase` menu entry, and Fillet above Ogee.
- `.cursor/rules`: the folder map.

### Testing Notes
- [ ] Reload Plugin Data. **Staircase** appears under Draw in the popup, and at the bottom
      of the Extensions submenu until a restart moves it under Drawn Cylinder.
- [ ] Drag a block 3595 x 1525 x 1690. Hover each side: it turns blue with an arrow
      pointing in. From straight above, hover near each top edge instead.
- [ ] Click a short side and drag inward. The flight follows the cursor, the gold line and
      degrees update, and the card reads 10 risers of 169. UP and DOWN change the count
      while the run holds.
- [ ] Click to build: one solid group, and one Ctrl+Z removes it.
- [ ] Type `35` in the flight stage: it builds at 35°. Then `175r`: 10 risers of 175, and
      the status bar says the flight rises 1750, 60 above the block. Then `250g`, then `9s`.
- [ ] Type `175`, or `3000`: refused, the stair untouched, the fix in the status bar.
- [ ] A shallow flight reads green for Part K. Drag it steep until it turns red and names
      the pitch.
- [ ] Inside a group that is moved AND rotated, and one nested three deep: the stair lands
      where it was previewed.
- [ ] With Subtraction left on in Drawn Volume, the Staircase still goes block, side,
      flight.
- [ ] The popup's Modify tools read Push Pull, Chamfer, Fillet, Ogee.

# =============================================================================

## Version 5.1.12 - 24-Sep-2026 - Deep Fillet, and One Profile Sweep for Every Moulding

### Asked For
*"Now add fillet / radius — default should be 6 sides if fillet less than r10, 12 sides if
r10 - r200, 24 sides if r200 - r2000, 48 sides if r2000+ — typing ##s changes the segments
making up the fillet / radius."*

### Deep Fillet
A new tool alongside Deep Chamfer and Deep Ogee: the Extensions submenu, the popup under
Deep Ogee, and `Na__InsertPrimatives.Na__InsertPrimatives__DeepFillet` for a hotkey. It
works exactly as the chamfer does, with the same hover, bank, drag, retype and repeat.
- **The size is a true radius** at any corner angle. The round is an arc tangent to both
  faces: its centre sits on the bisector r / sin(half) from the corner, and it touches each
  face r / tan(half) back. That is r on a square corner, 16.6 for R40 at 135 degrees and
  69.3 at 60 degrees. The section is solved in **world** space and carried back into the
  space the edge reports through the inverse of `target[:transformation]`, so the radius
  holds inside rotated, nested and non-uniformly scaled components.
- **The drag puts the arc under the cursor.** The chamfer reads travel along the bisector
  as `travel / cos_half`, which puts its chord under the cursor. The chamfer now routes that
  reading through a hook, `na_drawn__size_from_travel`, and the fillet answers
  `travel / (1/sin(half) − 1)`, so the arc's nearest point to the corner follows the
  mouse. For a cove the travel is the radius.
- **Sides are automatic:** 6 under R10, 12 up to R200, 24 up to R2000, and 48 beyond. A
  radius sitting exactly on a band edge takes the band above; the grid puts R10 and R200
  there often, so the mm value is rounded to a millionth before it is compared.
- **"##s" sets the sides of the fillet in hand.** Mid-drag it redraws the preview. Straight
  after a cut it re-cuts that fillet at its own radius. With nothing grabbed it waits for
  the next fillet. A typed count belongs to the fillet it was typed for: it stays with that
  fillet through retyped radii, and the next fillet goes back to automatic.
- **TAB swaps the round-over for a cove** of the same radius, the ogee's turn-round idea
  carried over. It works mid-drag, or straight after a cut to re-cut that fillet, and the
  choice is remembered between sessions.
- **Internal corners fill.** On a concave edge the same plan fills the corner up to the
  arc, so a round becomes a classic internal fillet and a cove a quadrant bead.

### One Profile Sweep, Shared
The ogee's plan, build and mitre were never ogee-specific, so they now live in one place
that every profile tool uses:
- `04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb` (`Na__ProfileSweep__*`)
  holds the corner frame, the solve packer, the profile-aware face planner, the facet
  build, the batch plan and build, and the corner mitre. Two things were generalised on the
  way:
  - **Symmetric profiles mitre with faces in either order.** A fillet reads the same from
    either face, so `:symmetric` solves skip the ogee's "roll off the same face" check.
  - **Facets face the air on concave corners too.** On a convex corner the air is
    opposite the bisector; on a concave one it is on the bisector's side. The corner
    frame reports which, as `:convex`.
- `06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__.rb` is the tool-side
  mixin. It answers the chamfer's plan, build and mitre hooks, draws any profile, and
  carries a profile through the retype ghost. A tool describes its shape with
  `na_drawn__profile_state` (the ogee's `{flip, sides}`, the fillet's
  `{kind, sides_typed, sides}`). The shared capture merges that into the retype record, so
  a rebuild can wear it again, and redraws the ghost when the shape has changed.
- Deep Ogee now includes that mixin. Its mitre file is gone, its geometry file is its curve
  and its solve, and its revise module is its wording. Nothing about how it cuts has
  changed, and the 5.1.11 rehearsal was re-run against it and passes.

A new profile tool is now its curve, its solve and its words.

### Reload or Restart
This update moves methods out of the Ogee tool and into the shared mixin. Under Reload
Plugin Data a moved method's old copy stays in memory (see 5.1.9) and keeps answering.
The old copies are identical, so the Ogee keeps working, and the Fillet runs the new code
either way. A **SketchUp restart** puts the Ogee on the shared code as well.

### Rehearsed Before Shipping
- The fillet section: every point lies exactly R from the centre and is tangent to both
  faces at 90, 135 and 60 degrees. The setback is r / tan(half) and the arc takes the short
  way round. The cove is R from the edge everywhere and concave.
- Automatic sides at every band edge: R5, R9.99, R10, R199.9, R200, R1999, R2000 and R5000.
- The drag's arc sits under the cursor at 90 and 135 degrees.
- Facets face the air on a convex box edge and on a concave internal corner.
- A square-corner mitre closes even when the two edges list their faces in opposite
  orders.
- The ogee rehearsal still passes.

### Files
- **New:**
  - `04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb`
  - `06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__.rb`
  - `33__System__DeepFillet/` with its tool, geometry and revise files.
- **Deep Ogee:** the geometry, revise and tool files are slimmed onto the shared layers,
  and `Na__InsertPrimatives__DrawnOgee__Mitre__.rb` is removed.
- `31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__.rb`: the
  `na_drawn__size_from_travel` hook. Its default is the old `travel / cos_half`.
- Wiring:
  - `02__AppData`: `Na__DrawnSettings__FilletCove?` / `ToggleFilletCove` and
    `NA_TOOL_MEMORY_FILLET_KEY`.
  - `04__GeometryHelpers/..DrawnGridSnap__.rb`: `NA_DRAWN_FILLET_COVE_KEY`.
  - `01__AppCore`: the manifest, the mode switch and the folder map.
  - `40__UserInterface`: the popup button and its callback.
  - The Loader: the `NA_DeepFillet` command and the `fillet` menu entry.
  - `.cursor/rules`.

### Testing Notes
- [ ] Restart SketchUp (or Reload Plugin Data; see above). **Deep Fillet** appears in the
      menu and in the popup under Deep Ogee.
- [ ] Drag a fillet on a box edge: the arc follows the cursor, the status reads
      `Fillet R40 · 12 sides (auto)`, and it cuts tangent to both faces.
- [ ] R8 cuts with 6 sides, R10 with 12, R250 with 24 and R2500 with 48.
- [ ] Type `8s` mid-drag, then cut: 8 sides. The next fillet is automatic again.
- [ ] Straight after a cut, `24s` re-cuts it with 24 sides and `60` re-cuts it at R60,
      keeping its typed count.
- [ ] TAB mid-drag shows the cove; TAB after a cut re-cuts it as a cove.
- [ ] An internal corner fills with a concave fillet whose faces point outward (no
      blue-grey back faces).
- [ ] SHIFT-bank the four top edges of a box: the fillets mitre cleanly.
- [ ] Deep Ogee and Deep Chamfer still cut, bank, mitre and retype as before.

# =============================================================================

## Version 5.1.11 - 24-Sep-2026 - Deep Ogee: a Classical Moulding on Any Edge

### Asked For
*"create a version that creates a classical Ogee moulding on an edge, i very commonly have
to detail classical mouldings and edges so a fast way to apply them on selected edges in
the same manner as the chamfer tool would be awesome."*

### What It Is
A new tool, **Deep Ogee**, in the Extensions submenu, the right-click popup under Deep
Chamfer, and `Na__InsertPrimatives.Na__InsertPrimatives__DeepOgee` for a hotkey. It works
exactly as Deep Chamfer does: hover an edge at any nesting depth, click to grab it, drag
into the corner to size it, then click, press Enter or type a size to cut it. SHIFT+click
banks edges so that one drag moulds them all.

### The Profile — a Roman Ogee
Two quarter arcs of radius s/2, where s is the size (the setback on each face, exactly as
a chamfer's). The **roll** is convex and leaves its face tangent, so the edge rolls over
like a bullnose. The **cove** is concave and arrives at the other face square, leaving a
crisp lip under it. The arcs meet tangent at the inflection of the S. On a corner that
is not square, the same shape is laid in the oblique frame of the two faces, so the roll
still leaves its face tangent and the lip still runs parallel to it.

- **Which face rolls:** the face nearer horizontal. The top and the underside of a table
  top both roll over, and every banked edge agrees, which is what lets them mitre.
- **TAB turns it round** for every edge being cut. Mid-drag it flips the preview.
  Straight after a cut, it re-cuts that ogee the other way round through the same
  undo-and-rebuild that a typed size uses. The choice is remembered between sessions.
- **Smoothness:** each quarter arc takes a quarter of the Circle Sides setting, so 24
  gives 12 facets. `48s` doubles it, before a cut or after one (which re-cuts the ogee
  just made). The seams between facets are softened and smoothed, so the moulding shades
  as one curved surface. The edges onto the two faces stay hard.

### Corners Mitre
Where two banked edges meet at a square corner, every profile point is mitred the way the
chamfer mitres its two. Point *i* swept along one edge and point *i* swept along the
other are two lines, and where they cross is that point's place on the mitre. On a
square corner every pair crosses and the crossings run down the diagonal, so the four
top edges of a box are one pass that closes like a picture frame. A corner is refused,
with the reason in the status bar, when:
- it is not square in the third direction and the lines do not meet;
- the two edges roll off different kinds of face;
- three moulded edges meet at one corner. The curved three-way junction is not built.

### Built on the Chamfer, Not Beside It
`DrawnOgeeTool < DrawnChamferTool`. The chamfer tool gained a **Cut Hooks** region:
`na_drawn__solve_cut`, `na_drawn__mitre_cuts`, `na_drawn__plan_cut`, `na_drawn__build_cut`,
`na_drawn__plan_group`, `na_drawn__build_group`, plus `na_drawn__cut_title`,
`na_drawn__cut_phrase` and `na_drawn__cut_verb` for its messages. Every call to the chamfer
geometry and every place its name appears goes through them. The chamfer's own answers are
its existing functions and words, so Deep Chamfer behaves exactly as it did. The only
change in its wording is the multiple-instances warning, which is now built from the verb
("chamfering changes all of them" reads the same as before). Deep Ogee overrides the hooks
and inherits the deep pick, the bank, the corner-plane drag, CTRL vertex snapping, grid
snapping, one undo step per group, retype, double-click repeat and the replay ghost.

The chamfer's own geometry files are untouched. The ogee geometry reuses the chamfer's
inward directions, corner-vertex identity, face rebuild and single-substitution merge, and
adds a profile-aware planner in which an end face is clipped by the whole profile instead
of the pair `[a, b]`.

### Rehearsed Before Shipping
The maths was run numerically on a 600 x 400 x 300 box before handing over, with the
profile, the roll rule, facet orientation, end-face ordering, the flip, and the four-corner
mitre of the whole top all mirrored from the Ruby. Every facet has air on its outward side
and solid on its inward side, in both orientations and on the underside and vertical edges.
The four corner mitres meet to 5e-15 mm and lie on the diagonal.

### Files
- **New** `32__System__DeepOgee/`:
  - `Na__InsertPrimatives__DrawnOgeeTool__.rb` for the tool;
  - `..__DrawnOgee__Geometry__.rb` for the profile, solve, plan and build;
  - `..__DrawnOgee__Mitre__.rb` for the corner mitres and the batch plan and build;
  - `..__DrawnOgee__Revise__.rb` for memory, wording, the retype flip and smoothing, and
    the ghost.
- `31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__.rb`: the Cut Hooks
  region, with the geometry calls and messages routed through it.
- `02__AppData`: `Na__DrawnSettings__OgeeFlipped?` / `ToggleOgeeFlip`, and
  `NA_TOOL_MEMORY_OGEE_KEY`.
- `04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__.rb`: `NA_DRAWN_OGEE_FLIP_KEY`.
- `01__AppCore`: the LoadManifest entries, `Na__ModeSwitch__ActivateDrawnOgeeTool`,
  `Na__DrawnMode__SetOgeeMode`, and the folder map.
- `40__UserInterface`: the Deep Ogee popup button and its callback.
- `Na__InsertPrimatives__Loader__.rb`: the `NA_DeepOgee` command and the `ogee` menu entry.
- `.cursor/rules`: the folder map.

### Testing Notes
- [ ] Reload Plugin Data. **Deep Ogee** appears at the bottom of the Extensions submenu (it
      moves under Deep Chamfer after a SketchUp restart) and in the popup under Deep
      Chamfer.
- [ ] One edge of a box top: drag, click. The top rolls over, the cove finishes in a lip
      on the side face, the curve shades smoothly, and the end faces are clipped to the
      profile.
- [ ] TAB mid-drag turns the preview round. TAB straight after the cut re-cuts it the
      other way round, and Ctrl+Z still undoes to the uncut box.
- [ ] SHIFT-bank all four top edges of a box and drag once: the four mitres close cleanly.
- [ ] Type `60` straight after a cut: it resizes. `48s`: it re-cuts smoother at the same
      size.
- [ ] Inside a group that is moved AND rotated, and one nested three deep: the moulding
      lands on the edge that was picked.
- [ ] Deep Chamfer still cuts, banks and mitres exactly as before.

# =============================================================================

## Version 5.1.10 - 24-Sep-2026 - Roofs Read a Bare Number as a Pitch

### Asked For
*"assume the value type is degrees pitch, if the user types a value such as 3000mm or 3m
then use that to determine the rise ... otherwise a value like 30 is assumed to mean 30
degrees as no one uses measured rises."*

### What a Typed Rise-Slot Value Means Now
| Typed | Was | Now |
|---|---|---|
| `30` | a 30mm rise | a **30° pitch** |
| `+5` | 5mm more rise | **5° steeper** |
| `30d`, `30deg`, `30°` | 30° pitch | 30° pitch (unchanged) |
| `3000mm`, `3m`, `300cm` | a 3000mm rise | a 3000mm rise (unchanged) |
| `+100mm` | 100mm more rise | 100mm more rise (unchanged) |
| `3000` | a 3000mm rise | **refused**: "3000.0° is not a roof pitch — a rise needs its unit, e.g. 3000mm" |

This applies wherever a roof takes a rise: the pitch stage, the third slot of a plan
entry (`6000,4000,35`), and a retype straight after drawing. Plan sizes are untouched, so
a bare number there is still millimetres.

### Refused, Not Clamped
`Na__DrawnRoof__HeightFromPitch` clamps to 0.5–89.5°, which is the right safety net for
geometry and the wrong answer to a typing habit: a `3000` meant as millimetres would have
built the steepest roof the clamp allows, without a word. A pitch outside 0–90 is now
refused, with the fix named in the status bar.

### The Measurements Box Shows the Pitch
The box displays what a bare number typed into it will mean. In the pitch stage it reads
`Roof pitch` with the live pitch in degrees (for example `35.0°`), and after drawing it
reads `Roof W,L,pitch` as `6000,4000,35.0°`. Showing the rise in millimetres there would
invite exactly the entry that is no longer read as millimetres. The status line leads
with the pitch too.

### Retyping After Drawing
The idle hint has always said *"Type a rise or a pitch to correct the roof just drawn"*,
but the retype path was strictly positional. A lone `2000` set the width and a lone `35d`
failed to parse. A comma-free entry now goes to the rise slot: `35` re-pitches the roof
just drawn and `3000mm` sets its rise. The plan is still reachable positionally: `6000,`
is the width, `,4000` the length, and `6000,4000,35` sets all three.

### Files
- `03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`:
  `NA_DRAWN_VCB_PITCH_PATTERN`, `Na__DrawnVcb__ParsePitchOrRise`, and
  `Na__DrawnVcb__ParseAngleToken` gains `bare_is_angle`.
- `21__System__DrawnRoofs/Na__InsertPrimatives__DrawnRoofTools__.rb`:
  `na_drawn__resolve_rise_token` reads pitch-first and refuses outside 0–90,
  `na_drawn__pitch_vcb_text`, the measurements-box label and value, the retype routing,
  and the status text, hints and header.

### Testing Notes
- [ ] Pitched Roof: drag the plan, then type `30`. The roof builds at 30°.
- [ ] Type `3m` in the pitch stage: the rise is 3000mm, and the pitch reads from it.
- [ ] Type `3000` in the pitch stage: a beep and the "not a roof pitch" message, with no
      roof built.
- [ ] `6000,4000,35` in the plan stage builds a 6000 x 4000 roof at 35°.
- [ ] Straight after drawing, `40` re-pitches that roof to 40° and `+5` makes it 45°.
      `6000,` still changes only the width.
- [ ] The Hipped Roof behaves the same.

# =============================================================================

## Version 5.1.9 - 24-Sep-2026 - Reload Plugin Data Kept the Method 5.1.8 Deleted

### Reported
*"holding control + shift + pushing does not lock either"* and *"see 1906 that should be
1905 when pushing with control shift"*, with a screenshot of the regular Deep Push/Pull
reading `Push 1906 mm` while CTRL+SHIFT was held. The message before it said the orange
mark was missing, which has the same cause.

### The Cause
5.1.7 opted Push/Pull out of CTRL+SHIFT with its own `na_drawn__vertex_grid_supported?`
returning `false`. 5.1.8 opted it back in by *deleting* that method, so that the mixin's
`true` would show through. On disk that is correct, but not in a running SketchUp. Reload
Plugin Data re-runs every file with `load`, which re-opens each class and redefines what
the file contains. It never removes what the file no longer contains. The 5.1.7 `false`
therefore stayed on `DrawnPushPullTool`, and on the 2D subclass. A class's own method
always wins over a mixin's, so CTRL+SHIFT went on behaving as plain CTRL: an exact 1906
and no mark.

### The Fix
The method is back in Push/Pull, returning `true`. It repeats the mixin's answer on
purpose, because a definition in this file is the only thing a reload can put over the
stale one. A SketchUp restart would also have cleared it.

### The Rule Going Forward
Under Reload Plugin Data, deleting a method changes nothing; only redefining one does. To
undo an override, replace it with a definition that gives the new answer rather than
deleting it. The same goes for constants. The reloader shares this behaviour with the
Noble3d and Profile Path Tracer reload managers it mirrors.

### Files
- `30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPullTool__.rb`:
  `na_drawn__vertex_grid_supported?` returning `true`, with the reason.

### Testing Notes
- [ ] Reload Plugin Data only, no restart. In Deep Push/Pull, CTRL+SHIFT to the same
      vertex gives `Push 1905 mm`, the orange square beside the vertex, and
      `Vertex → Grid 5mm — CTRL+SHIFT` in the status bar.
- [ ] The same in a 2D scene tab.
- [ ] CTRL alone still gives the exact 1906.

# =============================================================================

## Version 5.1.8 - 24-Sep-2026 - CTRL+SHIFT Reaches Both Push/Pull Tools

### Asked For
*"does the 2d push pull have the same feature?"* It did not. Deep Push/Pull 2D is a
subclass of the 3D tool, and 5.1.7 left both out because SHIFT is their slope mode. The
agreed follow-up: give both tools CTRL+SHIFT, and on a roof end let it do both things.

### What CTRL+SHIFT Does in Push/Pull
The travel is read from the vertex the InputPoint lands on, exactly as with CTRL, and is
then rounded to the grid step. Push/Pull has always rounded the travel rather than the
point (a face normal is rarely axis-aligned; see the file header), and CTRL+SHIFT keeps to
that. A wall face that starts on the grid and is pulled square to an axis therefore ends
on the grid. That covers the elevation case this was asked for: pulling walls out to the
vertices of a CAD drawing in a 2D view.

### Roof Ends: SHIFT Does Both
| Held | Wall or box face | Roof end (a slope to follow) |
|---|---|---|
| nothing | along the normal, rounded | along the normal, rounded |
| SHIFT | no slope to follow, so along the normal, rounded | down the rake, rounded |
| CTRL | along the normal to the exact vertex | along the normal to the exact vertex |
| CTRL+SHIFT | along the normal to the vertex, **rounded** (new) | down the rake to the vertex, **rounded** (was exact) |

SHIFT still means slope mode wherever the face has a slope to follow, so on a roof end
CTRL+SHIFT runs down the rake to the vertex and rounds the distance in grid steps along
the slope, as a plain SHIFT slope push always has. The one combination given up is the old
exact, unrounded slope push to a vertex. That was agreed on purpose: CTRL+SHIFT now means
"on the grid" in every tool that offers it, which is the promise the feature exists to
keep.

### The Mark and the Status Line
The 5.1.7 orange square is drawn here too, at the point the rounding actually leaves: the
vertex slid along the measured direction by the amount rounded off. The status bar now
lists `CTRL+SHIFT vertex→grid` and reads `Vertex → Grid 5mm — CTRL+SHIFT` while the keys
are held. The "SHIFT: no sloped neighbour to follow here" note stays quiet while CTRL is
down as well, because SHIFT is doing something after all.

Deep Chamfer still opts out. SHIFT+click banks edges there, so CTRL+SHIFT still means
plain CTRL.

### Files
- `30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPullTool__.rb`: the 5.1.7
  opt-out removed, `na_drawn__recalculate_sizes` records the rounded point for the mark,
  `draw` draws it, `na_drawn__slope_hint` stays quiet under CTRL, plus header notes and a
  console hint line.
- `30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull2dTool__.rb`: a console
  hint line. Everything else is inherited from the 3D tool.
- `06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__.rb` and
  `31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__.rb`: comments only.

### Testing Notes
- [ ] A 2D scene tab over a CAD elevation: grab a wall by its edge and CTRL+SHIFT a CAD
      vertex. The pull is a whole multiple of 5mm and the orange square sits beside the
      vertex.
- [ ] The same pull with CTRL alone still lands exactly on the vertex.
- [ ] 3D Push/Pull on a box face with CTRL+SHIFT: the distance rounds, the status line
      shows `Vertex → Grid 5mm — CTRL+SHIFT`, and there is no "no sloped neighbour" note.
- [ ] A roof end with CTRL+SHIFT: it follows the rake (`Slope` in the status line) and
      the distance rounds.
- [ ] An arrow-key axis lock with CTRL+SHIFT: the distance measured along the locked axis
      rounds.

# =============================================================================

## Version 5.1.7 - 24-Sep-2026 - CTRL+SHIFT Snaps to the Vertex, Then Rounds It onto the Grid

### Asked For
Tracing an imported CAD drawing with new volumes and planes that still sit on the grid:
*"I'm pointing you towards THIS vertex, snap to it but THEN APPLY the correction based on
the current setting setup"* — *"so you can infer to vertex points without losing the
strict accuracy."*

### Three Snap Modes
| Held | Where the point comes from | Rounded onto the grid? |
|---|---|---|
| nothing | the stage's own source: InputPoint while idle or on an auto plane, a pick ray on a locked plane or in the depth stage | yes |
| CTRL | SketchUp's InputPoint, at every stage | no |
| CTRL+SHIFT | SketchUp's InputPoint, at every stage | **yes**: the same `SnapPoint`, on the step the popup's Snap Grid button sets |

### What CTRL+SHIFT Adds That the Plain Grid Could Not Do
It is easy to assume the plain grid ignores geometry, and it does not do so everywhere.
While idle and on an auto plane the plain cursor already comes from the InputPoint, so
hovering a CAD vertex for the first two corners already rounds that vertex. What the plain
grid cannot do is:

- take a **depth, height or roof rise** from a vertex. The depth stage follows a pick ray
  projected onto the extrusion axis, which knows nothing about the model;
- snap to vertices on a **TAB- or arrow-locked plane**. That is a ray-plane intersection,
  just as blind.

Until now the only way to reach a vertex in either place was CTRL, which gave up the grid.
CTRL+SHIFT is CTRL's InputPoint at every stage with the rounding put back.

### Rounded to the Lattice, Not to the Size
A CTRL+SHIFT point lands on the nearest lattice point, exactly as a plain-grid point does.
Two shapes traced to the same CAD corner meet on the same point, and every dimension
between two CTRL+SHIFT picks is a whole number of steps. The one way to get a ragged size
is to mix modes within one shape: a first corner placed with CTRL alone keeps its exact,
off-grid position, and the rounded second corner cannot make up for it.

The cylinder radius is still rounded as a distance, for the same reason as on the plain
grid: the diagonal between two lattice points is not itself a grid multiple.

### Seeing the Correction
The InputPoint marker stays on the vertex that was pointed at, and an orange open square
marks the grid point it became, with a dotted leader between the two. At working zoom the
square just frames the inference dot, which is the sign the mode is live. Zoom in and they
pull apart by exactly how far the vertex was off the grid. It is drawn in screen space like
the 5.1.6 cutter, so the preview's own fill cannot hide it, and it is left out of
Subtraction's pick-the-group stage, which takes nothing from the cursor point. The status
bar reads `Vertex → Grid 5mm — CTRL+SHIFT` while the keys are held.

### Shape Tools Only
Drawn Plane, Volume and Cylinder, and the Pitched and Hipped Roofs. Deep Push/Pull (2D
included) and Deep Chamfer are unchanged: SHIFT is already slope mode and edge banking
there, so CTRL+SHIFT keeps its old meaning. In Push/Pull that is still slope mode plus
vertex snapping, unrounded. Both answer `false` to `na_drawn__vertex_grid_supported?`, and
their status lines still advertise CTRL alone.

### No New Coordinate Maths
Both halves already existed: the InputPoint pick (CTRL) and the lattice rounding (plain
grid). CTRL+SHIFT only chains them, so it rounds in the same drawing-axes frame the plain
grid always has, inside or outside an open group, with no conversion of its own to get
wrong.

### Files
- `06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__.rb`:
  `na_drawn__snap_mode`, `na_drawn__vertex_grid_supported?`, `na_drawn__snap_point` and
  `na_drawn__snap_distance` round unless CTRL is held alone, the correction mark in
  `draw`, the status fragments `na_drawn__grid_description` and `na_drawn__vertex_hint`,
  and a SNAP MODES note in the header.
- `05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`:
  `Na__DrawnPreview__DrawGridCorrection`, `NA_DRAWN_GRID_MARK_COLOR`,
  `NA_DRAWN_GRID_MARK_PIXELS`.
- `30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPullTool__.rb` and
  `31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__.rb`: the opt-out.
- The Plane, Volume, Cylinder and Roof tools: one console hint line each.

### Testing Notes
- [ ] Drawn Volume over an imported DWG: CTRL+SHIFT on a CAD corner, CTRL+SHIFT on the
      opposite corner, then CTRL+SHIFT on a vertex at the wanted height. The console
      `Anchor:` and `Size` lines are whole multiples of 5mm.
- [ ] The same three picks with CTRL alone still give the exact, off-grid numbers.
- [ ] Hold CTRL, then press and release SHIFT with the mouse still: the status bar swaps
      between `Grid OFF — CTRL vertex snap` and `Vertex → Grid 5mm — CTRL+SHIFT`, and the
      orange square comes and goes.
- [ ] Zoom right in on a CAD vertex that is off the grid: the square sits beside the
      inference dot with a dotted leader between them.
- [ ] A TAB-locked plane (XZ, say) over a CAD elevation: CTRL+SHIFT picks its vertices
      and rounds them.
- [ ] Snap Grid set to 10mm in the popup: CTRL+SHIFT rounds to 10mm.
- [ ] Cylinder: CTRL+SHIFT centre on one vertex and radius to another; the radius reads as
      a multiple of the step.
- [ ] Deep Push/Pull on a roof end: CTRL+SHIFT still slope-pushes to an exact vertex, and
      the status line shows only `CTRL vertex`.
- [ ] Inside a group that is moved AND rotated: CTRL+SHIFT lands on the same lattice the
      plain grid uses there.
- [ ] With two keyboard layouts installed, Ctrl+Shift is also Windows' layout-switch
      hotkey. If the layout starts flipping, turn that hotkey off under Settings → Time &
      language → Typing → Advanced keyboard settings → Input language hot keys.

# =============================================================================

## Version 5.1.6 - 17-Sep-2026 - The Cutter Preview Draws Through the Wall

### Asked For
*"The red box that is displayed to show the depth cutting, it gets lost behind the face of
the SketchUp object. If I press K it shows the model in X-ray mode and it's much easier to
use, because you can see the volume you're actually cutting. Is it possible to render that
red box forward of the other layers?"*

### Why It Was Hidden
`View#draw` is depth-tested against the model. That is correct for a box being **placed**
— it is about to become geometry and should sit in the scene like geometry. It is exactly
wrong for a box being **cut**, because a cutter lives INSIDE the thing it cuts, so the
wall's own front face wins the depth test and the preview vanishes at the one moment it is
being adjusted. Reaching for X-ray to work around that is the bug, not the workaround.

### The Fix
`View#draw2d` has no depth test — it draws in screen space, after everything else. So when
a target is locked the cutter's eight corners are projected through `View#screen_coords`
and the box is drawn there instead. This is the same route the dimension labels have always
used, which is why they never disappeared into the wall.

Two details that matter:

- **The fill had to get thinner.** Drawn on top, all six faces blend over each other
  instead of being depth-rejected, so the original alpha of 70 stacked to very nearly
  opaque and hid the wall behind it. At 34 the densest overlap lands near 57% coverage:
  the box reads as a volume and the model still reads through it.
- **It falls back.** `screen_coords` still answers for a point behind a perspective
  camera, but with a mirrored point that would smear the box across the viewport. Any
  corner failing that test abandons the screen-space draw and the ordinary depth-tested
  one runs instead — one frame without the effect rather than one frame of garbage. A
  parallel camera is exempt from the test: it has no vanishing point to turn inside out.

A box being placed is untouched and still draws depth-tested.

### Files
- `05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__.rb` —
  `DrawFilledBoxOnTop`, `ScreenPoints`, `InFrontOfCamera?`, and `NA_DRAWN_CUTTER_XRAY_FILL`.
- `20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnVolumeTool__.rb` —
  `na_volume__draw_cutter_or_volume` picks the route; the depth label and summary card
  moved into `na_drawn__draw_box_labels`.

### Testing Notes
- [ ] Cut into a wall from outside: the red box stays visible through the face, with X-ray
      OFF.
- [ ] Orbit until the cutter is behind the camera plane: the preview degrades to the
      depth-tested draw rather than smearing.
- [ ] A plain Drawn Volume with Subtraction off still draws depth-tested amber.
- [ ] Parallel projection (a scene tab set to a 2D view) still draws the cutter.

# =============================================================================

## Version 5.1.5 - 17-Sep-2026 - Cut Every Solid at Every Depth, and Say What the Walk Saw

### Reported
*"It's not working on deep nested groups (recursive groups within the parent) so children
and grandchildren, it should cut all."* With this console report:

```
Target: Difference (1 deep)
Result: Cut 1 solid
Scope : 1 editing context opened
```

### The Walk Stopped at the First Solid on Each Branch
5.1.3 descended into a child only when that child was NOT a solid:

```ruby
if Solid?(child)
    ConsiderVictim(child, ...)
    next                      # <-- a solid is the thing to cut, not a container to open
end
WalkChildren(child, ...)
```

The reasoning was that SketchUp calls nothing a solid if it holds nested instances, so a
solid is always a leaf and there is nothing below it to miss. That may hold for the test
SketchUp's own UI applies, but `#manifold?` is a *different* test and there is no way to
confirm the two agree from outside the application. The brief is not ambiguous — children
**and** grandchildren — so the assumption is gone: **every solid at every depth is now
collected, and a solid is descended into like anything else.** It costs one extra level of
iteration per solid branch.

### Deepest First
Once a solid ancestor and a solid descendant can both be victims, order starts to matter:
`subtract` REPLACES the container it cuts, so a parent cut before its children would
strand the references to them. Victims are sorted by context depth, descending, and
because Ruby hashes keep insertion order the batches inherit that order — a container is
never replaced before the solids inside it have been cut.

The picked parent stays a **fallback**, cut only when nothing inside it was a solid. That
is deliberate even now: cutting a container *and* its contents in one pass means replacing
a container whose contents were just rebuilt, and the API gives no promise about what
survives inside it.

### The Report Could Not Explain Itself
"Cut 1 solid" out of a nested assembly might mean the walk found one solid, or found six
and rejected five — and there was no way to tell, because a rejected solid was dropped
silently. Every branch of the scan is now counted and printed:

```
Scan  : 14 nested objects walked, 3 levels down | 6 solids | 1 outside the box | 0 locked
        cut target: Wall Inner Leaf (1 deep)
        cut target: Lintel (2 deep)
```

The refusals split three ways too, where they used to be one flat sentence: nothing
watertight anywhere, *N* solids none of which the box reaches, or *N* solids all locked.

### The Bounds Gate Now Fails Open
The bounding-box test in front of each boolean was added as an optimisation and could
silently drop a cuttable solid — the worst possible failure mode for this tool. Since
5.1.4 a boolean that declines is handled safely (counted as a miss, cutter cleared, no
data loss), so the gate has nothing critical to protect. When bounds cannot be worked out
at all the solid is now **kept** and the boolean is allowed the last word; when the gate
does reject, it is counted and reported rather than vanishing.

A stale victim — a solid erased by an earlier cut in the same operation, which two
instances of one definition can produce — is counted as a miss instead of being ignored,
so "cut 3 of 5" never goes unexplained.

### Files
- `04__GeometryHelpers/Na__InsertPrimatives__DrawnSubtract__.rb` — the walk descends
  through solids; `CollectVictims` returns the whole scan state; deepest-first sort;
  fail-open bounds gate; `NothingToCutMessage`.
- `20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnVolume__Subtract__.rb` —
  `na_volume__log_scan`.

### Testing Notes
- [ ] Parent → child → grandchild, solids at both levels: **all** are cut, and the Scan
      line reports the depth it reached.
- [ ] A solid child that itself contains solid grandchildren: all cut, deepest first.
- [ ] If a cut still does less than expected, the Scan line now names the cause —
      `outside the box` points at the bounds gate or the world transform, a low `solids`
      count points at `#manifold?`, and a low `nested objects walked` points at the walk.

# =============================================================================

## Version 5.1.4 - 17-Sep-2026 - The Subtract Operands Were the Wrong Way Round

### Reported
*"It's currently just deleting the selected object. I tested on a simple solid group with
geom inside and it fails. I also tested on a nested set of groups, still fails."* Three
sequential screenshots: draw the opening, pick the group (highlight correct, cutter preview
correct, `W 1270 x H 1550 x D 220`), commit the depth — and the solid is **gone**.

### The Cause
`Sketchup::Group#subtract` is documented in two places that contradict each other, and
5.1.3 believed the wrong one.

| Source | Says |
|---|---|
| `#subtract` summary | "the boolean difference of the two groups ... **(this - arg)**" |
| `#subtract` `@param` | "group — The group to subtract **this group from**" → `arg - this` |
| `#trim` (the non-destructive sibling) | "the original **group2** is erased and a newly trimmed version is created" |
| SketchUp's own Solid Tools UI | "The **first** solid you select is your **cutting tool**" |

Three of the four agree: **the receiver is the cutter and the argument is the thing being
cut.** Only the summary line says otherwise, and it is the line 5.1.3 coded against.

So `victim.subtract(cutter)` computed `cutter - victim`. A window-sized cutter sitting
wholly inside a wall leaves **nothing**, and an empty solid result takes BOTH operands with
it. The wall was not failing to be cut; it was being consumed as the offcut of a boolean
run backwards. It is one root cause for both reported tests — in the nested case the deep
walk found the lower box as a solid child and consumed that instead.

### The Fix
`cutter.subtract(victim)`, in one place, with the research written into the module header
so the next person does not have to repeat it.

### And a Guard, Because the Documentation Cannot Be Trusted
A one-character operand swap should not be able to destroy a wall, so the result is now
checked while the operation is **still open**:

- A valid result → the identity transplant runs and the cut is counted.
- No result, solid still standing → the boolean declined. Clear the cutter, count a miss.
- No result and **the solid is gone** → abort the whole operation, so nothing is committed
  and the model is untouched. The status bar says
  *"the boolean removed <name> instead of cutting it — nothing was committed"*.
- The one exception: a solid that genuinely sits **inside** the cutter is supposed to
  vanish, so that case is detected up front (bounding-box containment) and reported as
  *"N removed entirely"* rather than treated as a fault.

Being wrong about the operand order, or having the API move under us in a future release,
now costs a status-bar message and an undo-safe abort instead of geometry. The console
report also states the order used on every cut — if solids ever start disappearing again,
that line is where to look.

### Files
- `04__GeometryHelpers/Na__InsertPrimatives__DrawnSubtract__.rb` — operand order, the
  header research note, `Na__Subtract__CutOne` with the result check, `Swallows?` /
  `BoxContains?`, and a `:removed` tally.
- `20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnVolume__Subtract__.rb` — the
  order is named in the console report.

### Testing Notes
- [ ] Simple solid group, geometry only: the opening appears and the group survives with
      its name, tag and material intact.
- [ ] Nested groups: every solid child is cut, none disappears.
- [ ] A cutter drawn deliberately larger than a small solid: that solid is removed and the
      status bar says "removed entirely" — the abort must NOT fire here.
- [ ] Ctrl+Z after a cut returns the solid uncut, in one step.

# =============================================================================

## Version 5.1.3 - 17-Sep-2026 - Context-Aware Submenus, and Drawn Volume Learns to Cut

### Asked For
Three things, and the third is the one that shapes the other two:

1. Drawn Volume gets a **Subtraction** option — draw the opening, click the group to cut
   (with a highlight so it is obvious which one), give a depth, and the box is subtracted
   rather than placed. 100mm typed on the reference screenshot is a window reveal.
2. Drawn Volume gets a **Transparent** option — paint the new box with the indexed
   material `MAT011__ModelingUtility__Transparent`, on the group CONTAINER, not the faces.
3. And the reason both of those need somewhere to live: *"make a context aware submenu
   appear under the tool in use with further toggleable configs... keeping the menu
   smaller when all options aren't required."*

### The Submenu Framework
Nine tools share one right-click menu. Adding two buttons for Drawn Volume to the bottom
of it would be two buttons every other tool has to scroll past, and the next tool with
options makes it four. So options are **declared against a tool's mode key** and rendered
only under the button of the tool that is actually running.

- `02__AppData/Na__InsertPrimatives__AppData__ToolOptions__.rb` is the whole framework:
  a table of `{ :id, :key, :label, :default, :summary }` keyed by mode key, persisted
  through `Sketchup.write_default` in the same registry section as the snap grid, and
  cached in memory because a commit asks for these and `read_default` is a native call.
- `PrimitiveModeSwitching` gained two methods, so EVERY tool answers the same way:
  `Na__DrawnMode__ToolOptions` describes them and `Na__DrawnMode__ToggleToolOption`
  flips one and hands back its new caption.
- The popup builds its mode buttons through one helper now, and a tool with nothing
  declared returns an empty list and renders nothing. **Adding an option to any tool is
  one entry in `NA_TOOL_OPTIONS` and nothing else.**
- Toggling rewrites the button in place and leaves the menu open, the way the grid step
  and the segment count already do — options are rarely changed one at a time. Three
  colours, three meanings: blue is the tool you are in, green is an option switched on,
  white is everything else.
- An option left on days ago would otherwise be invisible until it surprised somebody,
  so the status line carries `| SUBTRACTION+TRANSPARENT` whenever one is live.

### The Optional Fourth Stage
`DrawnToolShared`'s state machine grew one optional stage, `:picking_target`, between
`:picking_b` and `:picking_depth`. Five no-op hooks (`advance_from_target`,
`track_target`, `on_pick_state_reset`, `stage_before_depth`, `constrain_depth_sign`) mean
a tool can insert a stage that hunts something in the MODEL rather than a dimension
without reimplementing the mouse, keyboard and draw contract. Every tool that does not
ask for it goes `:picking_b` → `:picking_depth` and never sees it.

### Subtraction, and the Two Pipelines
`04__GeometryHelpers/Na__InsertPrimatives__DrawnSubtract__.rb`, driven by
`20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnVolume__Subtract__.rb`.

- **SIMPLE** — the picked group holds no child instances. One candidate, one question:
  `manifold?`. Not solid, and the overlay turns red and says **"Selection Not Solid"**.
- **DEEP** — the picked group holds children. Every descendant is walked and each solid
  one is cut. A solid is NOT descended into: cutting the shell is cutting everything it
  stands for. Nothing solid anywhere below and the same red overlay reads
  **"No Solid Children"**.
- **The parent is the fallback in both.** A group that holds children and is itself a
  watertight shell is cut when none of its children are solids — the "loose geometry in
  one shell" case from the brief.
- The hover survey runs on every mouse move, so the deep probe **stops at the first solid
  it meets** rather than counting them, is capped at 400 nodes, and is cached against the
  instance's definition and entity count so it is thrown away by an undo or an explode.

### Why Each Solid Is Cut Inside Its Own Editing Context
`Sketchup::Group#subtract` needs both operands in the SAME entities collection, so the
cutter has to be built beside the solid it cuts, at whatever depth that is. Editing a
definition's entities from outside its editing context is the stale-display-cache saga
the push tool was cured of in 5.0. So victims are grouped by the collection they live in,
each collection is opened once through `Na__DeepPick__ExecuteInContext`, and every solid
in it is cut in that one operation.

Inside an open context every coordinate is global (the 5.1.2 rule), which is exactly the
space the box arrives in — **the cutter needs no conversion at all**. And because that is
load-bearing, the context is **asserted** inside the block rather than assumed: if
SketchUp refuses to open it the batch is abandoned and counted as skipped. Building world
geometry into a closed definition would silently cut a hole somewhere nobody asked for,
which is far worse than not cutting.

Two more things that are easy to get wrong and are handled:

- **`subtract` consumes both operands and returns a NEW container.** Name, tag, material,
  shadow flags and every attribute dictionary are read off the solid first and written
  onto the result — without that, cutting a window out of a wall renames the wall to
  `Group#417` and drops its tag.
- **A bounding-box gate runs in front of every boolean.** A cut against a solid the box
  cannot reach is wasted work on a large assembly, and it comes back `nil`, which is then
  indistinguishable from a real failure.

### The Depth Direction Is Decided For You
Having just named the object to cut, a cutter pointing away from it is never what was
meant. The sign is taken from where the target actually sits relative to the rectangle and
the drag sets the depth's SIZE only, so dragging either way grows the opening into the
wall. Typing `2400,1200,100` in one go skips the depth stage entirely: the cut fires the
moment a valid target is clicked.

### The Transparent Option
`03__AppUtils/Na__InsertPrimatives__AppUtils__StandardMaterials__.rb` resolves
`MAT011__ModelingUtility__Transparent` from the shared data library
(`Na__DataLib__CoreIndex__Materials__.json`), hunting it by `SketchUpName` rather than by
a hard-coded path through the file, with MAT011's own values as the built-in fallback when
the library cannot be read. The file is read straight off disk rather than through
`Na__DataLib__CacheData` — a tool option must never be able to stall a click on a network
fetch. A material already in the model under that exact name is used as it stands, because
the name is the lookup key across the whole toolchain.

The material name goes IN to `Na__DrawnGeom__CreateVolume` rather than being painted on
afterwards, so the paint and the geometry are one operation and one Ctrl+Z. It goes on the
**container**: every face inside inherits it, one assignment tints the whole box, and one
assignment clears it again.

### Files
| New | |
|---|---|
| `02__AppData/...AppData__ToolOptions__.rb` | The submenu framework |
| `03__AppUtils/...AppUtils__StandardMaterials__.rb` | MAT011 resolution and container painting |
| `04__GeometryHelpers/...DrawnDeepPick__Instance__.rb` | Pick the group under the cursor, and its own oriented box |
| `04__GeometryHelpers/...DrawnSubtract__.rb` | Survey, collect, and cut |
| `20__System__DrawnPrimitives/...DrawnVolume__Subtract__.rb` | The stage, the preview and the commit |

| Changed | |
|---|---|
| `DrawnToolShared__.rb` | The optional `:picking_target` stage and its five hooks; option summary in the status line |
| `AppCore__ModeSwitch__.rb` | `Na__DrawnMode__ToolOptions` / `ToggleToolOption` on the shared mixin |
| `RightClickPopup__Html__.rb` | Mode buttons built through one helper; the submenu block and its CSS |
| `RightClickPopup__.rb` | `toggleToolOption` callback and a JS string escape |
| `DrawnPreviewGraphics__.rb` | Target highlight, its blue/red palette, and the cutter red |
| `DrawnGeometry__.rb` | `CreateVolume` takes an optional container material |
| `DrawnVolumeTool__.rb` | Wiring: the stages, the preview colours, the hints |

### Instance Transforms, and Why `instance.transformation` Is Read Straight
`PickHelper#path_at` starts at the ACTIVE entities, so `instances.first` lives directly in
the context the user has open — and by the 5.1.2 rule the active context and all its
parents report global coordinates, so that instance's own transformation IS the world one.
Below it the rule flips and a descendant's world transform is `parent_world * its own`,
which is the accumulation the subtract walk does and nothing else needs.

The selection bias tests **only** `instances.first`, and that is not a shortcut: a
SketchUp selection can only hold entities from the open context, so a selected instance is
by definition the outermost one on the path — and only the outermost one can have its
transformation read as world.

### Testing Notes
Per the coordinate rule, a wrong conversion is invisible at the origin, so:

- [ ] A box in the model root, Subtraction off — nothing has changed.
- [ ] Window opening cut from a wall group at the root (the reference screenshot).
- [ ] The same wall inside a group that is MOVED **and** ROTATED, nested three deep.
- [ ] A wall group whose children are the solids (deep pipeline), and one where the
      children are not solids but the parent is (parent fallback).
- [ ] Hover something that is not a solid: red overlay, "Selection Not Solid", and the
      click is refused with a beep rather than doing nothing.
- [ ] A **scaled** group. The cutter is pinned to a global identity so its definition
      units are world units and `pushpull` needs no scale correction — this is the one
      claim in the release that is reasoned rather than measured.
- [ ] A component with more than one instance: the cut lands on every copy and the status
      line says so. Deliberate — making it unique silently would be its own surprise.
- [ ] `2400,1200,100` typed at the base stage with Subtraction on: it should go straight
      to the target pick and cut on the click.
- [ ] BKSP from the depth stage returns to the target pick and releases it.
- [ ] Transparent on: the GROUP carries the material, the faces do not, and one Ctrl+Z
      removes box and paint together.
- [ ] The submenu appears under Drawn Volume only, moves when the tool changes, and both
      toggles survive a SketchUp restart.

# =============================================================================

## Version 5.1.2 - 08-Sep-2026 - Stacked Local Axes: One Coordinate Rule for Every Nesting Depth

### Reported
"The preview is messed up if using the push pull and other tools inside deeply nested
objects" — Model → Group → Group → Group. And the question behind it: is there any
awareness of stacked local axes, and how does SketchUp actually handle them?

### The Research
There was no awareness — there was a belief, written into three file headers, that
entity positions are always definition-local and that view drawing happens in the
open group's space. Both are wrong, and the API documentation is thin enough that it
took the SketchUp team's own words on the forum to settle it.

**The rule, from SketchUp (Eneroth, quoted by DanRathbun):**
> "In the active drawing context and all its parent coordinate systems all
> coordinates are global. In all other coordinate systems they are local."

And ThomThom, twelve years earlier: *"SU changes the co-ordinates when you open a
group/component. When a group or component is open SU returns global co-ordinates
for the entities in that context."*

What that means in practice:

| Thing | Group CLOSED | Group OPEN (active context or a parent of it) |
|---|---|---|
| `Vertex#position`, `Face#normal`, `Face#mesh` | definition-local | **global** |
| `Group#transformation` | relative to its parent | **global** |
| points given to `entities.add_*` | local | **global** |
| `transform_entities` / `transform_by_vectors` | local | **global** (documented) |
| `Face#pushpull(distance)` | definition units | definition units (a scalar has no space) |

And three things that are **always global**, open context or not: `InputPoint#position`
("always returns a point that is transformed into model space"), `View#pickray`, and
everything handed to `View#draw` / `View#screen_coords`. The classic line tool draws
straight between two InputPoints inside any group; that is the proof.

`PickHelper` is the third piece and it is **relative to the open context**, not the
model root: `path_at` "starts from the active entities" and `transformation_at` maps
the leaf "into the coordinates of the active entities" — which are global. So
`transformation_at` is already the "to world" transform for a face inside a closed
group, and the **identity** is the right transform for a face in the open context.
The path, however, is missing the instances the user is standing in, and
`Model#active_path=` refuses any path that does not chain from the root.

### What Was Actually Wrong
1. **The deep pick applied `edit_transform` to positions that were already global.**
   PASS 1 (a face loose in the open context) built its target with the open
   context's transform. That moves every preview by the open group's own placement.
2. **0.4.36 cancelled that with an equal and opposite error at draw time.** Every
   preview point went through `edit_transform.inverse`. For a face in the open
   context the two cancel, which is why it looked fixed. For a face inside a closed
   group *below* the open one — picked correctly through `transformation_at` — the
   inverse is applied to a correct point, and the preview lands displaced by exactly
   the open group's transform. Open a moved group, hover a face of a group inside it:
   that is the reported bug. Groups this plugin makes sit at the world origin, which
   is why every test passed.
3. **Pick paths were relative, so entering a nested group from inside another one
   failed.** `active_path = [inner]` is not a valid path from the root; the commit
   silently fell back to editing the definition from outside, with the stale display
   cache the push tool was cured of at the root, back one level down.
4. **The chamfer batch planned faces after entering the group and then pushed the
   plans through `edit_transform` again.** Read-after-enter positions are already
   global; the second transform puts the cut somewhere else in any group that is not
   at the origin. The single-edge cut had the mirror-image gap: an edge loose in an
   opened, moved group planned in global and was built through the open group's
   transform.
5. **The push commit used definition-local vectors inside an entered group.** Loop
   cuts offset global loops along a local direction, and the slope routes handed
   local vectors to `transform_by_vectors`, which reads them as global once the group
   is open. Invisible for a translated group, wrong for a rotated one.
6. **New shape groups inherited the open group's placement.** Drawing a volume while
   inside a moved group put global numbers into a group whose axes were not the
   world's. The rebuild paths already pinned the group to the identity; the create
   paths did not.

### The Fix: One Contract on the Target Hash
Every target now carries an **absolute** `:path` (model root to innermost instance)
and a `:transformation` that carries the entity's **reported** coordinates to global.
Read those two words as the contract and no code needs to know how deep it is.

- `Na__DeepPick__AbsolutePath` prepends the open context's instances to a pick path.
  Every scan uses it; PASS 1 passes the context path with a **nil** transform.
  `Na__DeepPick__ContextTransform` is gone — there was no correct use for it.
- `Na__DrawnPreview__DrawSpace` returns nil. The `ToDraw*` seams stay as the one
  place a correction would go, and now hand every point back untouched.
- `Na__DeepPick__ExecuteInContext` yields `entered` to its block. The chamfer's
  single cut uses `edit_transform` (read inside the block) only when the group was
  entered, the identity otherwise; the batch solves and builds with the identity,
  swapping the members' transforms for the identity once inside.
- `na_drawn__execute_push` splits the offset **twice**: once before entering, for
  the pushpull scalar (definition units), and once after, against the normal the
  face now reports, for every vector — loop-cut direction and step, stretch, shear,
  the moved-face search. `working_offset` is the world offset when entered and the
  local one when not.
- `Na__DrawnGeom__PinGroupToWorld` sets a fresh group's transformation to the
  identity — read as a global identity inside an open context — before any global
  point goes into it. Plane, volume, cylinder and roof creation all call it.
- `Na__DeepPick__AddTransform` is retained for the push ring, where points are read
  and added on the same side of the open and it measures the identity it expects.
  Its header now says why it must not be used for read-before-enter points.

### Not Verified: Scaled Instances
`Face#pushpull` is documented as a distance along the normal and nothing more. The
tools divide the world travel by the instance scale along the normal on the
assumption that the scalar is in definition units whether or not the group is open.
That matched an overshoot observed in 0.4.x; whether it still holds once the context
is entered has not been measured. A push inside a *scaled* group is the one case in
the list below to watch for a wrong distance.

### Files Touched
- `DrawnDeepPick__.rb` (hub header: the rule), `DrawnDeepPick__Pick__.rb`
  (`AbsolutePath`, identity for open-context picks, `ContextTransform` removed),
  `DrawnDeepPick__Focus__.rb`, `DrawnDeepPick__Context__.rb` (`yield(entered)`,
  `AddTransform` header)
- `DrawnPreviewGraphics__.rb` — draw space is world space
- `DrawnPushPull__Commit__.rb` — working offset after entering
- `DrawnChamferTool__.rb`, `DrawnChamfer__Geometry__.rb` — build transform rule
- `DrawnGeometry__.rb`, `DrawnRoofGeometry__.rb` — `PinGroupToWorld`
- The project structure rule — the coordinate rule in one paragraph

### Status: IMPLEMENTED — NOT YET VERIFIED IN SKETCHUP
Build the test model first: a box in a group **moved and rotated** (not at the
origin), a second such group inside it, a third inside that. Then, in this order:

1. At the root, hover and push a face three groups deep — preview and result land on
   the face (this always worked; it must still)
2. Double-click into the outer group; hover a face of the group inside it — the
   preview must sit ON the face, not displaced by the outer group's move
3. Push it, then retype — the push must enter the inner group (one Ctrl+Z, the
   viewport updates at once, the status bar says "In <inner> (2 deep)")
4. Two groups deep, push a loose face of the group you are in — preview on the face,
   push along its true normal (rotated group: the old code measured along a rotated
   copy of the normal)
5. Quads on, inward loop cut, two deep in a rotated group — the ring lands in the
   surrounding faces
6. SHIFT slope push, two deep in a rotated group
7. Chamfer a loose edge two deep; then SHIFT-bank three edges of a nested group and
   cut them — every cut lands on its edge
8. Draw a volume, a plane and a roof while two deep inside a moved group — each
   appears where the cursor drew it
9. The 2D elevation pull, inside an opened moved group
10. A push inside a SCALED group — check the distance (see the note above)

# =============================================================================

## Version 5.1.1 - 08-Sep-2026 - Retype, Repeat, Replay: the Modifier Tools Behave Like SketchUp

### Reported
"A previous agent did a crappy job at implementing a feature." Native Push/Pull and
Fredo's Joint Push/Pull both leave the measurements box live after a placement —
type a new value and the push you just made becomes that value — and both repeat
the last distance on a double-click of the next face. 5.1.0 built the first half of
that for the push tools only, refused to arm it after a loop cut (the exact case in
the screenshot), could not offer it in the chamfer tool at all, verified the undo
stack by guesswork, and gave no visual sign of what a retype had done. One slip of
the finger and the only way back was to grab the face again.

Three asks, all delivered:

1. **Retype after placing, in every modifier tool** — Deep Push/Pull 3D, Deep
   Push/Pull 2D and Deep Chamfer. Forgiving: nothing short of grabbing a new
   target, changing the model or leaving the tool closes it.
2. **A visual replay of every retype** — the preview sweeps from the old size to the
   new, fast, so trying 3000 then 5000 then 4200 is *seen*, not inferred.
3. **Double-click repeats the last value** — remembered in the model's own
   attribute dictionary, per tool, until a different value is placed.

Plus the right-click menu now stays where you leave it, from a new UserConfig JSON.

### One Revise System, Shared
5.1.0 wrote the retype into the push tool alone. This release lifts the mechanics
every modifier tool has in common into one mixin and leaves each tool with only what
is genuinely its own:

- **`06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__.rb`** —
  `DrawnReviseShared`: the record of the last placement, the undo-stack watch, the
  retype flow (undo → re-acquire → rebuild → animate, with a put-it-back fallback),
  the double-click repeat and its guard, the remembered value, the status and
  measurements-box wording. Included AFTER `DrawnToolShared` so its `activate`,
  `deactivate` and `onCancel` wrap the mixin's.
- **`Na__InsertPrimatives__DrawnRevise__Watch__.rb`** — `DrawnReviseWatch`, a
  `Sketchup::ModelObserver` that forwards every transaction event to the tool.
- **`Na__InsertPrimatives__DrawnRevise__Animate__.rb`** — `DrawnReviseAnimate`, the
  ghost engine: a repeating timer, an eased value off the wall clock, the draw hook
  and the extents. It draws nothing itself.
- **`30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__Revise__.rb`** —
  rewritten as the push half of the contract: capture, re-acquire the face by its
  interior point, rebuild through `na_drawn__commit_push` wearing the recorded
  state, the sign-is-a-direction parse, the ghost.
- **`31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Revise__.rb`** —
  new: the chamfer half. An edge is gone once it is cut, so it is remembered by
  where its two ends were and found again as the one edge in the same collection
  standing on those points. Batches across groups record how many operations they
  took and undo that many.

The host contract is eleven small `na_revise__*` hooks, listed in the shared file's
header. `na_drawn__revise_available?` overrides are gone from both modifier tools;
they were never called by anything but themselves.

### Told, Not Guessed: How It Knows the Undo Stack Is Still Ours
`Sketchup.undo` pops whatever is on top. 5.1.0 decided whether that was our push by
counting entities and probing for a face at the pushed position — which could not be
made to work for a loop cut (nothing moves) and refused in cases it did not need to.

Now the tool is **told**. The watch rides on the model while a modifier tool is
active. Any transaction that lands after ours — a commit, an undo, a redo, from any
source — closes the record. `onCancel(2)`, which SketchUp raises on a user undo, is
the second witness. A cheap entity-count check stays as a third, run once at the
moment a size is typed, before anything is undone. While our own undo-and-rebuild
runs the watch is told to look away, so a retype is not closed by its own footsteps.

That is why a loop cut can be armed now: there is nothing left to verify by probing.

What does NOT close it: moving the mouse, hovering other faces, TAB, the arrows,
SHIFT, opening the right-click menu, SHIFT-banking more chamfer edges. Only the
three things that end it natively do.

### The Ghost
After every successful retype the preview comes back for a beat. For a push: the
start loop, the face at its moved position, the rungs between and the travel arrow,
sweeping from the old distance to the new with `Push 3000 → 5000 mm` written on it.
An inward quad value draws as the loop cut it is. The 2D tool's swept strip comes
along when the record came from an edge. For a chamfer: the same cut-face painter
the live drag uses, fed a solve re-scaled to the interpolated setback — every
chamfer point is its corner vertex plus an offset that grows in proportion to the
setback, mitred corners included, so one solve describes the cut at every setback.

Timing: 0.30 s of cubic ease-out travel, 0.25 s held at the new size, then clear.
The ghost geometry is copied out of the record at the start, so a record dropped
mid-sweep cannot leave a draw pass holding nothing, and the draw is fenced so a ghost
can never be the thing that kills a frame.

### Double-Click Repeat and the Model Dictionary
Every successful placement writes its measured value to
`Na__InsertPrimatives__ToolMemory` on the model —
`Na__DeepPushPull__LastDistanceMm` (signed: negative is into the material) and
`Na__DeepChamfer__LastSetbackMm` — in millimetres so the dictionary reads sensibly.

It is written **inside the placing operation**, between `start_operation` and
`commit_operation`. A model attribute write is itself undoable; written on its own
it would cost a second Ctrl+Z after every push. Merged into the placement it rides
in the same step, and undoing the push forgets it too, which is the right answer.
An aborted operation rolls the write back, so the tool re-reads the dictionary on
that path rather than trusting what it just set.

A double-click arrives as Down, Up, DoubleClick, Up, and the first Down has already
grabbed the target. If the mouse has not travelled since the grab (the same 6 px
click-versus-drag test the tools already use) there is no drag to place, and the
remembered value is applied — to the face, or to the edge and everything banked
with it. A double-click landing within 0.55 s of a placement is read as "place, then
grab the next face" and left alone, because that is what two quick clicks on a busy
model almost always are. The value is read back on activation, so it survives a
tool switch, a plugin reload and a reopened file. `2D` and `3D` share one key on
purpose: to the user they are one tool.

The measurements box at idle now always has a number in it: the placed size while a
retype is open, otherwise the remembered size a double-click will repeat.

### Sign Conventions, Per Tool
- **Push/pull, after placing:** the sign is a direction. `1200` is 1200 the way you
  dragged, `-1200` the other way, anchored to the ORIGINAL drag direction so
  `-1200` then `1200` lands back where the first push was. Unchanged from 5.1.0.
- **Chamfer, after cutting:** a setback has no direction, so the sign keeps its
  plugin-wide meaning — `+5` is five more than the placed setback, `-5` five less,
  `75` is seventy-five.

### The Menu Stays Where You Put It
The popup used to open at the cursor on every right-click, so the buttons were
somewhere new each time and the hand never learned them. It is now **anchored** by
default: it opens at the cursor the first time only, and after that wherever it was
last left. Drag it by its title bar and it stays there, at whatever size it was
resized to, across right-clicks, tools and sessions.

New per-user document, kept apart from AppConfig because a window position has no
business in a diff of the plugin's own switches:

`02__AppData/Na__InsertPrimatives__UserConfig__Main.json`

```json
{
    "Na__InsertPrimatives__UserConfig": {
        "Na__RightClickMenu__Config": {
            "Na__RightClickMenu__AnchorMode": "anchored",
            "Na__RightClickMenu__Position": { "Na__Position__X": null, "Na__Position__Y": null },
            "Na__RightClickMenu__Size":     { "Na__Size__Width": 216, "Na__Size__Height": null }
        }
    }
}
```

`Na__InsertPrimatives__AppData__UserConfigLoader__.rb` reads it over the defaults
(deep-merged, unknown keys carried through), and offers `Na__UserConfig__Get` /
`Na__UserConfig__Set` by key path. The placement is read back with `get_position` /
`get_size` (SketchUp 2021.1+) in the moment before the popup closes — the only moment
it is certain to still have one — and validated: a window already on its way out
answers with zeros, and a remembered 0,0 is far more likely to be that than a choice.
A `Menu: Anchored (drag to move)` / `Menu: At Cursor` button at the foot of the popup
flips the mode in place. **Extensions › Na__InsertPrimitives › Reset Menu Position**
forgets the spot, for the day a monitor is unplugged and the popup opens off-screen.

A remembered height TALLER than the buttons need is kept as the user's own resize;
one shorter would clip the last button, so the content wins. The popup is now
`resizable: true`.

### Shape Tools: No Longer Disarmed by a Twitch
The plane, volume, cylinder and roof tools revise by rebuilding the group they still
hold, and that offer was withdrawn the moment the mouse moved eight pixels. No native
tool does that. The mouse-move disarm, its constant and its anchor coordinates are
gone from `DrawnToolShared`; only starting a new drag, the group ceasing to exist,
or leaving the tool ends it.

### Also
- `Na__DeepPick__SameContext?` in DeepPick Context is now the one answer to "are
  these two editing contexts the same place" — the push commit, ExecuteInContext
  and every revise use it; the copy in the Commit mixin is gone.
- Tool memory and the UserConfig loader are in the load manifest; the project
  structure rule documents the config split and the revise contract.

### Files Added
1. `02__AppData/Na__InsertPrimatives__UserConfig__Main.json`
2. `02__AppData/Na__InsertPrimatives__AppData__UserConfigLoader__.rb`
3. `02__AppData/Na__InsertPrimatives__AppData__ToolMemory__.rb`
4. `06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__.rb`
5. `06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__Watch__.rb`
6. `06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__Animate__.rb`
7. `31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Revise__.rb`

### Files Touched
- `DrawnPushPull__Revise__.rb` — rewritten onto the shared contract
- `DrawnPushPull__Commit__.rb` — snapshot / capture through the new names; memory
  write inside the operation; SameContext? from DeepPick
- `DrawnPushPullTool__.rb` / `DrawnPushPull2dTool__.rb` — includes, double-click
  repeat, ghost overlay in draw, status and measurements-box wording, hints
- `DrawnChamferTool__.rb` — includes, member snapshot before the cut, capture after,
  batch op count, double-click repeat, ghost overlay, status / VCB / VCB entry
- `DrawnToolShared__.rb` — mouse-move disarm removed
- `DrawnDeepPick__Context__.rb` — `Na__DeepPick__SameContext?`
- `RightClickPopup__.rb` / `RightClickPopup__Html__.rb` — anchored placement, size
  memory, anchor toggle, reset
- `Na__InsertPrimatives__Loader__.rb` — Reset Menu Position entry
- `AppCore__LoadManifest__.rb`, `AppCore__Main__.rb`, the project structure rule

### Status: IMPLEMENTED — NOT YET VERIFIED IN SKETCHUP
No Ruby interpreter on the build machine. Reload Plugin Data and check, in this order:

1. Push a face 300, type 1200, type -600, type 900 — each retype replays the ghost
   and Ctrl+Z afterwards unwinds the lot in ONE press
2. Same with QUADS armed dragging INWARD (a loop cut) — the inset retypes and the
   ghost sweeps the ring
3. Same inside a group, and inside a group inside a group
4. Move the mouse a long way, hover other faces, press TAB and an arrow, open and
   close the right-click menu — then type: the retype must still be open
5. Ctrl+Z yourself, then type — must say "no longer the last thing done" and leave
   the model alone; same after editing something with another panel
6. Push a face, wait a second, double-click another face — same distance; with
   QUADS on and an inward memory it must loop-cut
7. Push, then within half a second click a new face — must grab, not repeat
8. Save, reopen, activate the tool, double-click a face — the distance survived
9. 2D elevation edge pull, retype, double-click another edge
10. Chamfer 50, type 75, type +5, type -10; double-click another edge
11. SHIFT-bank three edges across two groups, cut, retype — both groups move
12. Right-click: menu opens at the cursor the first time; drag it away, close it,
    right-click again — it opens where it was left. Toggle the Menu button, check
    Reset Menu Position, resize it taller and confirm the height is kept
13. Drawn Volume: draw a box, waggle the mouse, type 2400,1200,300 — it corrects

# =============================================================================

## Version 5.1.0 - 07-Sep-2026 - Retype a Push After You Have Placed It

### Reported
"To a SketchUp user this is the final last step that feels not quite SketchUp-like.
Everything else is perfect." Native Push/Pull leaves the measurements box live after
the click that places the extrusion — type 1200, Enter, and the push you just made
becomes 1200, again and again until you start something else. Fredo's Joint Push/Pull
does the same. Deep Push/Pull did not: the moment the push landed, the box went dead
and the only way to correct a distance was to grab the face again.

### What Changed
Both variants — the 3d face push and the 2d edge pull — now keep the box live after
placing. While the tool is idle with a placed push behind it:

- `1200` rebuilds the push at 1200 in the direction it was dragged
- `-1200` rebuilds it at 1200 the **other** way
- `1200mm`, `1.2m`, `120cm` all work, same parser as mid-drag
- Repeat as often as you like; grabbing another face ends it

The status bar says so — `placed 1200 mm, type a distance to adjust it (- reverses)` —
and the box keeps showing the distance that is standing, so there is always a number to
correct rather than an empty field to guess at.

### The Sign Is a Direction Here, Not Arithmetic
Everywhere else in this plugin a leading `+` or `-` is relative arithmetic against the
live drag: `-25` means 25 less than what the mouse is showing. There is no drag to be
relative to once the push is placed, and what a SketchUp user reaches for at that moment
is the other thing entirely — a minus to turn the extrusion round.

So in this one state the sign names the direction. The anchor stays the **original** drag
direction, never the last value entered, so `-1200` then `1200` lands back where the first
push was rather than walking off in one direction.

The relative arithmetic is untouched mid-drag. Only the placed state reads a sign as a
direction, and the status line and the activation banner both say which state you are in.

### Rebuild, Don't Top Up
The obvious cheap version is to push the already-moved face by the difference. It falls
apart immediately:

- the quad ring would be stitched a second time, at the new position
- a slope shear would compound on top of itself
- a loop cut has no face that moved at all
- a sign flip would have to drag the face back through its own start plane and hope the
  walls it made get reabsorbed

So the push is taken off the undo stack with `Sketchup.undo` and **re-run** from the state
it was made in. Typing 1200 gives byte-for-byte what dragging 1200 would have given, in
every mode, because it is literally `na_drawn__commit_push` running again. Repeat entries
cost one undo step in total rather than one each — same as native.

The record carries tool state, not geometry: `@na_pp_target`, the axis lock, the slope
candidate, whether SHIFT was down, whether TAB quads were armed. Restore those six and the
commit path recomputes the offset, the slope split and the quad decision itself. There is
still only one implementation of what a push is, which is why a retype cannot drift from a
fresh drag.

Quad mode is deliberately read from the record and not from the live setting: pressing TAB
between placing and retyping must not quietly add or drop a quad line.

### It Refuses Rather Than Guesses
`Sketchup.undo` pops whatever is on top of the stack. If that is not our push then calling
it destroys somebody else's work — a user who has already pressed Ctrl+Z themselves being
the obvious case. So before any undo is attempted the model is asked whether the push is
still the thing standing there. Two tests, covering each other's blind spots:

1. **The count.** A push adds walls, so the definition holds more entities after it than
   before. A Ctrl+Z has put that count back. Blind to a slope stretch, which creates
   nothing.
2. **The place.** Either a face where the push left one, or — for a push that went clean
   through and consumed its own face — nothing at all where it started. An undo puts that
   face back, so finding one at the start point is proof the push is no longer standing.
   Blind to a push that changes neither, which is what the count is there for.

Fail either and the record is dropped with a line in the status bar, and **nothing is
undone**.

If the rebuild itself will not build, the push the user actually had is put back down the
same path that made it, rather than leaving them with an undo and nothing after it.

### Not Armed After a Loop Cut
The inward-with-quads gesture moves no face, so there is no "where the push left it" to
test the undo stack against, and an unverifiable undo is not worth the convenience. A loop
cut ends the chance to retype. Note that with QUADS armed, typing a negative that turns the
push inward produces a loop cut — the same thing dragging inward produces, which is the
point: typing and dragging must not disagree.

### Sketchup::Entities Has No valid?
Worth writing down because it would have been a silent kill. `Sketchup::Entities` is a
COLLECTION, not an `Entity`, and has no `valid?` — asking one raises `NoMethodError`, and
a `rescue StandardError` around the availability check would have answered "no" forever
and taken the whole feature with it without ever printing anything. Touching a purged
collection raises instead, so it is asked its `length` and the raise is the answer.

### Files Added
1. **`30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__Revise__.rb`** —
   `Na__InsertPrimatives::DrawnPushPullRevise`, mixed into `DrawnPushPullTool` last so its
   `na_drawn__disarm_revise` wraps the mixin's. Listed in the load manifest ahead of the
   tool.

### Files Touched
- `DrawnPushPull__Commit__.rb` — snapshot the face's own space before `pushpull` moves it;
  arm the record after a successful push; console headline says ADJUSTED on a retype
- `DrawnPushPullTool__.rb` — `na_drawn__revise_available?` now answers from the record
  instead of a hard `false`; quad mode honours a replay; a successful grab drops the
  record; status, measurements box and VCB entry routing
- `DrawnPushPull2dTool__.rb` — same three, with the 2d wording
- `AppCore__LoadManifest__.rb` — the new file

### Status: IMPLEMENTED — NOT YET VERIFIED IN SKETCHUP
No Ruby interpreter on the build machine, so this has not been parsed or run. Reload
Plugin Data and check, in this order:

1. Plain push on loose geometry — place 300, type 1200, type -600, type 900
2. Same inside a group, and inside a group inside a group
3. Inside a scaled component — the retyped distance must be the world distance
4. With QUADS armed — the quad line must move with the retyped push, not double up
5. SHIFT slope push, then retype — the rake must be kept
6. Arrow-key axis lock, then retype — the lock must still be what is measured
7. A push clean through a solid, then retype
8. Ctrl+Z yourself, then type — must refuse with "no longer the last thing done" and
   leave the model alone
9. Ctrl+Z after a retype — must unwind in ONE press, not one per entry
10. 2d elevation edge pull, then retype

# =============================================================================

## Version 5.0.0 - 04-Sep-2026 - Numbered Modules, One Manifest, Instant Tools

### Why This Is 5.0.0
The 0.4.x line built the modelling suite: click-and-drag primitives, roofs, nested
push/pull, chamfer. The code outgrew a flat Modules folder and three disagreeing
load lists. This release is the architecture pass, not a new tool. Tool behaviour
is unchanged. What changed is how the plugin is laid out, loaded, reloaded, and
logged.

The `Na__InsertPrimatives` namespace spelling is kept on purpose. English UI still
says Primitives (`Na__InsertPrimitives` submenu). No toolbar. DEVLOG stays at the
Modules root.

### Numbered Folder Map
The plugin now follows the Element Studio / Component Editor pattern: low numbers
are core and shared, `10+` are product systems.

```
01__AppCore                 PathResolver, LoadManifest, Main, Reloader, ModeSwitch
02__AppData                 AppConfig JSON, ConfigLoader, persisted drawn settings
03__AppUtils                VCB, format, keyboard
04__GeometryHelpers         grid, solids, roofs, deep pick, slope, edge loops
05__PreviewGraphics         cube wireframe and drawn overlays
06__Tools__DrawnShared      drag state machine
10__System__PlaceCube       click-to-place cube and plane mode
20__System__DrawnPrimitives plane / volume / cylinder
21__System__DrawnRoofs      pitched / hipped
30__System__DeepPushPull    3d + 2d tools, commit, quad ring, 2d pick
31__System__DeepChamfer     tool, geometry, mitre
40__UserInterface           right-click HtmlDialog
```

Folder numbers never appear in filenames. Public entry names and menu keys are
unchanged, so existing shortcuts do not duplicate.

### One Load List
Main, the Loader forget-list, and the Reloader used to each carry their own file
order. Those lists had already drifted. There is now one source of truth:

`01__AppCore/Na__InsertPrimatives__AppCore__LoadManifest__.rb`

Main requires it. The Reloader discovers `**/*.rb`, sorts by that index, then
loads leftovers alphabetically so a forgotten new file still hot-reloads. The
Reloader itself is still loaded alone by the root Loader, so a broken module does
not take Reload Plugin Data down with it.

### Oversized Files Split Along Existing Regions
Splits followed the `# REGION |` maps that were already in the files. Every
extract left a `# @delegate:` pointer at the old site. Public method names were
not renamed.

- Chamfer Geometry + Mitre out of the tool class
- Push/pull Quad Ring + Commit out of the 3d tool
- ModeSwitch out of DrawnToolShared
- PrimitiveCubeTool out of Main (Main is require + entries only)
- Drawn settings + format out of GridSnap
- Push/pull 2d pick helpers
- DeepPick Focus / Pick / ExecuteInContext
- Right-click popup HTML/CSS/JS builder

`DrawnPreviewGraphics` was left whole: it already has clear regions, and the plan
marked a further split as lowest priority. A shared Deep-Edit base for push/pull
and chamfer was an explicit non-goal.

### Hotkeys Must Not Reload the Plugin
After the nested-folder move, every menu command and shortcut still forgot
`$LOADED_FEATURES` and re-required the whole plugin. That is ~34 Ruby files, a
wall of `already initialized constant` warnings, and the delay on Deep Push/Pull.

Tools now only activate. If startup failed, they point at Reload Plugin Data
instead of recovering by reloading on the spot.

**Extensions → Na__InsertPrimitives → Reload Plugin Data** is the hot-reload path.
Edit Ruby, use that item (or restart SketchUp). Do not expect a shortcut to pick
up disk changes by itself.

### AppConfig and Dev Mode
Diagnostic `puts` (activation banners, create/apply dumps, “loaded successfully”)
were cheap when the plugin was small and expensive once every hotkey reprinted
them after a full reload.

New file:

`02__AppData/Na__InsertPrimatives__AppConfig__Main.json`

Keys follow the three-stage `Na__Domain__Name` style:

```json
{
    "Na__InsertPrimatives__AppConfig": {
        "Na__DevMode__Config": {
            "Na__DevMode__Enabled": false
        }
    }
}
```

Default is off. Load errors still print. Reload Plugin Data still reports to the
console, because that is an explicit reload.

**Enable Dev Mode** is a checkable item at the bottom of the Extensions submenu.
It writes `Na__DevMode__Enabled` immediately. No plugin reload required for the
flag to take effect.

### Files Added or Relocated (Architecture)
1. **`Na__InsertPrimatives__AppCore__PathResolver__.rb`** — modules root and plugin root
2. **`Na__InsertPrimatives__AppCore__LoadManifest__.rb`** — single ordered load list
3. **`Na__InsertPrimatives__AppData__ConfigLoader__.rb`** — read/write AppConfig; gate `Na__Debug__Puts`
4. **`Na__InsertPrimatives__AppConfig__Main.json`** — `Na__DevMode__Enabled`
5. **`Na__InsertPrimatives__DrawnDeepPick__Focus__.rb` / `__Pick__.rb` / `__Context__.rb`**
6. **`Na__InsertPrimatives__RightClickPopup__Html__.rb`**
7. **`Na__InsertPrimatives__Loader__.rb`** — startup load only; tools call `Na__InsertPrimatives__RunTool`; Dev Mode menu at the bottom

Plus the Phase 2 extracts already named above (Chamfer Geometry/Mitre, PushPull
Commit/QuadRing, ModeSwitch, PrimitiveCubeTool, DrawnSettings, DrawnFormat,
PushPull2d Pick).

### Status: IMPLEMENTED — VERIFIED IN SKETCHUP
Tools activate without a reload delay. Nested push/pull, chamfer, drawn volume
and the right-click popup all still work. Reload Plugin Data remains the way to
pick up Ruby edits.

# =============================================================================

## Version 0.4.36 - 03-Sep-2026 - Previews Land Where They Are Aimed Inside a Group

### Reported
Push/pull a face inside a group and the preview flies off somewhere else entirely — right
shape, right size, nowhere near the face. The geometry it commits is correct. Only the
preview is wrong.

### The Third Coordinate Rule
Two coordinate rules were already known and are written up in the chamfer tool's header:

1. Entity positions **read** are in the definition's local space — bridged with
   `PickHelper#transformation_at`, which the deep picker has always done.
2. Geometry **added** while an editing context is open is interpreted in the editing
   session's space — passed through `Model#edit_transform`, which the chamfer builder does.

This is the third, and it is the same pipeline as the second: points handed to `View#draw`,
`View#draw_line` and `View#screen_coords` while a context is open are **also** read in the
editing session's space. Feed those calls correct world coordinates with a group open and
the whole preview renders at `edit_transform * point` — displaced by exactly the group's
transform. Skewed as well, if the group is rotated or scaled.

Nothing was wrong with the maths. `world_normal`, `@na_point_a` and `@na_size_d` were all
correct, and the 4980 mm the label reported was genuinely the distance dragged.

### Why the Push Itself Was Always Right
Rule 2's own note explains it: *"Push/pull never met this because pushpull takes a scalar."*
The commit path hands SketchUp no positions at all — `na_drawn__local_offset_vector` reduces
the move to a difference of two points and `Face#pushpull` gets a length. A translation-only
group transform leaves vectors untouched, so the distance survived intact while the preview
drifted. The preview is the only half that draws absolute positions.

### What Gave It Away
Two things, both visible in a single screenshot:

- **The un-offset start loop was displaced too.** `@na_pp_loop` is cached world geometry with
  no arithmetic applied to it. A bad offset vector would have moved the orange result loop
  only and left the start loop sitting on the face. Both were in the air, the push distance
  apart.
- **The text label was displaced by the same amount.** `DrawWorldLabel` goes through
  `View#screen_coords`, a separate call from `View#draw`. Geometry and text landing in the
  same wrong place is a shared *space*, not shared arithmetic.

### The Fix
`Na__DrawnPreview__DrawSpace` resolves `model.edit_transform.inverse`, or nil at the model
root where the transform is the identity — which is why loose geometry was never affected and
why nothing outside a group changes behaviour. `ToDrawPoint`, `ToDrawSpace`, `ToDrawVector`
and `ToDrawTriangles` apply it.

Conversion happens at exactly **one** layer: the functions that touch `view.draw*` directly.
The composite overlays (`LabelRectangle`, every `Summarise*`) delegate to those and must not
convert again, or the preview would be displaced twice over.

Vectors are converted as well as points. An axis lock names a **world** axis and a camera has
a **world** direction, so the locked ray and the arrow barbs need re-expressing in the space
they will be read in, or they point off true inside a rotated group.

Fourteen functions in the preview module now convert. Thirteen more places draw or measure
outside it and were converted by hand: the connector rungs and label slots in both push/pull
tools, the 2D tool's hover edge, swept edge and label-dodge maths, and the chamfer tool's
banked-edge, hover-edge and setback-label draws. The two legacy preview modules still wired
into the classic tool — `3dPreviewGraphics` and `PlaneMode` — carried the same bug and are
fixed too.

### If the Preview Is Still Displaced After This
Then the transform wants applying the other way round, and the whole correction is one word:
`edit.inverse` becomes `edit` in `Na__DrawnPreview__DrawSpace`. Nothing else needs touching.
Behaviour at the model root is unchanged either way.

# =============================================================================

## Version 0.4.38 - 03-Sep-2026 - Quads in Slope Mode: the Ring Was Following the Face

### Reported
Slope mode works in both tools now, but TAB quad mode does not come with it. The loop-cut
preview shows on an inward drag and the purple quad line shows at the joint on an outward pull,
and neither ever materialises into linework.

### A Record of Where Something WAS Is Worthless If It Tracks Where the Thing Goes
`Na__PushPull__CaptureLoops` reads the face's loops before the push, because the face is about
to move and those positions are the only record of where it started. It read them as
`vertex.position` and held the results.

Plain pushpull hid the need to copy them out. It leaves the original vertices where they are
and re-bounds the face on new ones, so a held position never moved and the ring landed
correctly — by luck rather than by design, for as long as quads only ever ran after a pushpull.

Slope mode's stretch route moves the face's OWN vertices. That is exactly what makes it
seamless, and it is what broke this: the held positions followed the face. The ring was then
re-drawn on top of the face's NEW boundary, where `add_edges` quietly handed back the edges that
were already there. Four edges reported as "kept", nothing created, and no line at the joint —
a ring that previewed perfectly and built nothing.

**The fix is `.clone` at the capture.** Same one-word class of bug this feature already had to
defend against in `Na__SlopePush__Nudge`, where a witness vertex that appeared never to move
would have made every move route read as a failure.

`Na__DeepPick__AddTransform` got the same treatment: it reads the probe point's position and
then compares it AFTER erasing the probe, which is the same shape of risk in code that had no
business carrying it.

### A Ring That Builds Nothing Now Says So
The outward quad ring only ever announced itself when it landed in the wrong SPACE. A ring that
landed on top of edges that were already there — building nothing, and reporting them as kept —
passed in complete silence, which is why this could only be described as "the preview works and
nothing appears". It now beeps and says so, exactly as the inward loop cut already did when it
kept nothing.

That asymmetry was the real reason this took a round trip to find: the console said
"4 edges kept" and the model said otherwise, and nothing reconciled the two.

### What Was Already Right
Nothing else needed changing. Quad mode was wired into both slope routes from the start — the
loops are captured whenever TAB is armed, `Na__PushPull__StitchQuadRing` runs on the stretch
route and on the pushpull-and-shear route, `Na__SlopePush__HealSeam` correctly stands down when
quads are on so the line it would otherwise clear is kept, and the inward drag offsets its ring
along the WHOLE slope travel rather than the normal's share, because in slope mode the faces
around the pushed one are the sweep of its loop along the slope. All of that was doing its job
against positions that had quietly moved.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** - `Na__PushPull__CaptureLoops` clones the
   captured positions; a quad ring that keeps nothing on an outward push now beeps and reports
2. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** - `Na__DeepPick__AddTransform` clones the
   probe position it reads back across the erase

### Status: IMPLEMENTED - NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.37 - 03-Sep-2026 - Slope Mode Actually Builds Geometry

### Reported
SHIFT previews correctly in both the 3D and 2D tools — arrow, shear, distance all right — and
confirming creates nothing at all.

### The Commit Was Raising, and Only One Call Could Have Done It
0.4.35 made a slope commit that cannot apply its move RAISE rather than fall through to an
ordinary push. That was the right change and it is what turned this from "commits as a normal
push" into "commits nothing" — the operation aborts and the model is left untouched.

Working back from there: both routes, stretch and pushpull-plus-shear, end at
`Na__SlopePush__MoveVertices`, and in 0.4.36 that function could only return false three ways —
a nil argument, an empty vertex list, or **an exception**. The arguments were all present and
the shear was ~130mm, which leaves exactly one candidate: `Entities#transform_by_vectors` was
raising. It is the documented way to move vertices, it is what the function was built on, and
it took the whole commit with it.

### Three Routes, Each Measured
`Na__SlopePush__Nudge` now tries, in order, and measures a witness vertex after each:

1. `transform_by_vectors(vertices, deltas)` — the documented route.
2. `transform_entities(translation, vertices)` — how everything else in SketchUp gets moved,
   aimed at the vertices.
3. `transform_entities(translation, [face])` — the same, aimed at the FACE, which carries the
   vertices it is bounded by. This is literally the hand operation being reproduced: select the
   end of the roof and move it.

A call that quietly does nothing is indistinguishable from one that was never made, so none of
them are taken on trust. It returns the delta the witness ACTUALLY travelled, and
`MoveVertices` corrects any shortfall once — which also covers the undocumented question of
which SPACE each API reads a delta in, since a wrong-space move is measured and topped up
rather than guessed at.

The witness position is now **cloned**. If `Vertex#position` ever handed back a live handle
instead of a copy, the witness would appear never to have moved and all three routes would be
judged failures — a measurement that cannot be trusted is worse than no measurement.

### The Moved Face Is Now Identified, Not Assumed
Separately, and still worth fixing: `Face#pushpull` is not documented to leave the Face object
alive and bounding the moved loop. Shearing a dead or unmoved face is a silent no-op, so the
shear path was resting on an assumption it did not need to.

`Na__SlopePush__MovedFace` identifies it instead. A point known to lie strictly inside the face
before the push — taken off the face's own triangulation, so it holds for a concave or holed
outline — is carried along the push, and the face it lands strictly inside IS the moved face.
The original object is asked first because it is one test and very often the answer; only when
it is not does this sweep the definition, which is affordable once at commit and never during a
drag. The seam heal then reads the same face.

### Refusals Print Themselves Now
`na_drawn__trace` is off by default and a status-bar line is gone by the time anyone thinks to
read it, so a refusal that produced no geometry printed nothing anybody would ever see. That is
how this landed as "the preview works and nothing is created" with no way to tell which of four
things had gone wrong.

`na_drawn__report_failure` prints unconditionally on any refused push: the reason, the target,
the mode, the trajectory, the local offset, how it split into normal and sideways travel, and
which route ran. A failure is not chatter — it is the one thing always worth printing. The
trace line also carries `shift=` and `slope=` now, since ALT-era `ctrl=` was no longer the
modifier that mattered.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnSlopePush__.rb`** - `Na__SlopePush__Nudge` (three measured
   routes), `Na__SlopePush__Travelled`, `Na__SlopePush__MoveVertices` (one correction pass),
   `Na__SlopePush__InteriorPoint`, `Na__SlopePush__MovedFace`; `Stretch` and `ApplyShear`
   pass the face through
2. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** - the shear branch resolves the moved
   face before shearing it and heals the seam from it, distinct refusal messages per failure,
   `na_drawn__report_failure`, trace line carries the modifier state

### Status: IMPLEMENTED - NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.36 - 03-Sep-2026 - Slope Mode Moves to SHIFT

### Requested
ALT proving too problematic. Use SHIFT instead.

### Why SHIFT Is the Right Key and ALT Never Was
This is not a preference, it is the fix for the class of bug 0.4.35 was patching around.

**MK_SHIFT is a genuine Windows mouse-message bit. There is no MK_ALT.** So the flags SketchUp
hands a tool always state the truth about SHIFT, and never reliably state anything about ALT.
Everything that went wrong followed from that one fact:

- ALT had to be tracked through key events, which meant a key-up eaten by the Windows menu bar
  left slope mode stuck on.
- Reading ALT out of the flags anyway made a missing bit mean "ALT is up", which wiped what the
  key event had just set — including on the button-down that commits. That was 0.4.34's
  "previews right, commits as a normal push".
- 0.4.35's `@na_alt_in_flags` capability probe worked around both, but it was a workaround for
  a key that simply is not reported.

On SHIFT all of that goes away. `na_drawn__sync_modifier` now reads SHIFT the same plain way it
reads Ctrl: whatever the keyboard did, the next mouse event states the truth, and a key-up this
tool never saw corrects itself. The capability probe is deleted rather than adapted, because
there is nothing left for it to discover. The key-down and key-up handlers stay, demoted to
what they always should have been — a supplement so the preview and status line react the
instant the key is pressed rather than waiting for the mouse to twitch.

### Nothing Else Changed
Same trajectory maths, same stretch-or-shear commit, same seam healing, same reporting. The
geometry side of 0.4.34 and 0.4.35 is untouched — this release swaps a key and deletes the
scaffolding that key needed.

Constants come from SketchUp's own `CONSTRAIN_MODIFIER_MASK` / `CONSTRAIN_MODIFIER_KEY` where
they exist, with the Windows literals (4 and 16) as the fallback. Unlike the ALT constants there
is no platform surprise waiting: SHIFT is SHIFT on both.

### The One Thing Worth Knowing
The chamfer tool already uses SHIFT+click to bank multiple edges, reading bit 4 out of the mouse
flags itself. That is a different tool, so there is no clash — but it is now two tools with two
meanings for the same modifier, which is worth remembering before a third one wants it.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnToolShared__.rb`** - `NA_DRAWN_MK_SHIFT` /
   `NA_DRAWN_SHIFT_KEY` replace the ALT constants, `@na_shift_held` replaces `@na_alt_held`,
   `@na_alt_in_flags` deleted, `na_drawn__sync_modifier` reads SHIFT like Ctrl,
   `onKeyDown` / `onKeyUp` / `activate` / `resume`
2. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** - `na_drawn__slope_mode?` and
   `na_drawn__slope_hint` read SHIFT; status line, hover label and activation hints reworded
3. **`Na__InsertPrimatives__DrawnPushPull2dTool__.rb`** - hover label reworded
4. **`Na__InsertPrimatives__DrawnSlopePush__.rb`**, **`Na__InsertPrimatives__Main__.rb`** -
   documentation reworded

### Status: IMPLEMENTED - NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.35 - 03-Sep-2026 - Slope Mode Fixes: ALT Survives the Click

### Reported
Slope mode previewed correctly and then committed as an ordinary normal push, and it did
nothing at all in the 2D variant.

### Both Were the Same Bug: the Mouse Flags Were Wiping ALT
`na_drawn__sync_modifier` read the ALT bit out of the mouse-event flags exactly the way it
reads Ctrl. That is wrong, and it is wrong in a way that looks like it works:

- Windows mouse messages carry no ALT bit of their own. MK_SHIFT and MK_CONTROL are real;
  there is no MK_ALT. Whether SketchUp synthesises one into the flags it hands a tool is not
  something to take on trust.
- Read like Ctrl, a missing bit means "ALT is up" — so every mouse event WIPED the state
  `onKeyDown` had just set.
- The preview still worked because the ALT key-down handler calls `update_cursor` and
  `invalidate` itself, so the frame it drew was a slope frame. The very next mouse event
  cleared the flag again — including the button-down that commits. Hence: correct preview,
  ordinary push.
- In the 2D tool the same clearing happened, but with no separate route drawing a good frame
  first it simply never appeared to do anything.

**The fix.** The flags may now only ever turn ALT ON, until a set bit has actually been seen —
`@na_alt_in_flags`. Once one has, the platform is known to be reporting ALT and the flags are
allowed to turn it off again too, which keeps the useful half of reading them: a key-up lost to
the Windows menu bar corrects itself on the next mouse move. Until then the key events are the
sole authority, and a held ALT's auto-repeat key-downs re-assert it, which also recovers a
press made before the tool started.

Nothing in the 2D tool needed changing. Its preview, its ray solve and its commit were already
reading `na_drawn__travel_direction`; they were being handed a flag that had just been reset.

### While In There: the Roof Case Now Takes the Clean Route
The commit had one route — pushpull along the normal by its share of the travel, then shear the
moved face sideways by the remainder. That is the route that always works, but it leans on
`Face#pushpull` leaving the Face object alive and bounding the moved loop, which is not
documented, and it leaves a coplanar seam that then has to be tidied.

There is a better answer whenever it is available, and on a roof it always is:
**`Na__SlopePush__CanStretch?`** asks whether every face sharing a VERTEX with the pushed one
contains the slope direction. On a rafter end they all do — the top surface, the soffit and both
sides are all planes the rake lies in. So the face is simply carried along the slope and they
stretch to follow, which is exactly what selecting the end of the roof and moving it down the
rake does by hand: nothing created, nothing welded, no seam across the surface that was just
made continuous.

Vertices and not edges, because a face touching only a corner of this one still moves with it,
so the edge neighbours alone are not the whole affected set. Where the test fails — something
around the face does NOT contain the slope, and stretching would drag it out of its own plane —
the pushpull-and-shear route runs as before, because that one stays valid whatever the
neighbours are doing.

### Vertex Moves Now Check Themselves
`transform_by_vectors` takes a delta per vertex and does not document which SPACE it reads that
delta in. Guessing wrong there is silent: the geometry moves, just not where it was told to.
That is the class of bug that cost the chamfer tool three releases, and it is why
`Na__DeepPick__AddTransform` probes rather than assumes.

So `Na__SlopePush__MoveVertices` measures. One vertex is read before and after the move, and if
it did not land where it was sent the shortfall is applied as a second move. When the first move
was right the shortfall is zero and nothing else happens.

### Failure Is Loud Now
A slope commit that cannot apply its move RAISES rather than returning quietly. The operation
aborts, the status bar says which of the two routes failed and the console carries it. Falling
through to an ordinary push hands back geometry that does not match the preview, which is worse
than doing nothing — and it is precisely how this release's bug managed to hide. The console
report also names the route taken, so "stretched" versus "pushpull + shear" is never a guess.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnToolShared__.rb`** - `na_drawn__sync_modifier` no longer lets
   the mouse flags clear ALT until they have proved they report it; `@na_alt_in_flags`
2. **`Na__InsertPrimatives__DrawnSlopePush__.rb`** - `Na__SlopePush__MoveVertices`,
   `Na__SlopePush__CanStretch?`, `Na__SlopePush__Stretch`; `Na__SlopePush__ApplyShear`
   delegates to the measured move and reports failure
3. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** - stretch-or-shear dispatch in
   `na_drawn__execute_push`, both routes refuse loudly, `@na_pp_stretched` and the route in the
   console report

### Status: IMPLEMENTED - NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.34 - 03-Sep-2026 - ALT Pushes Along the Neighbour's Plane

### Requested
Hold ALT and push/pull should stop feeling like SketchUp's: instead of travelling along the
face normal it should extend along the ANGLE OF THE ADJACENT FACE, so a roof carries on down
its own rake rather than getting longer on plan. A different method for continuing a
trajectory along a sloped face.

### Why the Native Gesture Cannot Do This
`Sketchup::Face#pushpull` only ever extrudes along the face normal. On the plumb-cut end of a
roof that normal is horizontal, so the only thing a push can do is shove the end sideways: the
roof gets longer measured on plan and the rake it was cut to is thrown away. There is no
argument to pushpull that changes this, which is why the gesture had to be built rather than
configured.

### Where the Direction Comes From
`Na__InsertPrimatives__DrawnSlopePush__.rb`. Across the edge shared with a neighbour, the
direction that continues that neighbour's surface is the one lying IN its plane, square to the
edge, pointing away from it - a cross product of its normal with the edge direction, signed to
lead out rather than back across.

**Which neighbour, when a roof end has four.** The two sloped ones (top surface and soffit) are
parallel and hand back the SAME direction, so they collapse to one candidate. The two upright
ones hand back the face normal itself, because continuing a plane already square to the face is
just pushing normally. So the rule is: keep the candidates going FORWARD, drop the ones that are
the normal in disguise, take the one that deviates most. On anything roof-shaped that leaves
exactly one answer and it is the rake. On a plain box it leaves none, which is the honest
answer - a box has no trajectory to continue.

**Signing it is done twice on purpose.** The neighbour's centroid says which side its bulk lies
on, which is right for anything convex and costs nothing. `classify_point` then asks the face
itself whether a step that way lands back inside it, which is the answer that holds for an
L-shaped or holed neighbour where a centroid can mislead.

### Why It Is Still a pushpull
Moving the end face along the slope by hand would stretch every face around it, and that is
only valid while every one of those faces contains the slope direction. Let one not contain it
and the result is a face that is no longer planar - silently, and only sometimes.

So the extrusion stays a pushpull, along the normal, by the normal's SHARE of the slope travel.
The moved face is then sheared sideways by the remainder. Every wall the push created goes from
a rectangle to a parallelogram - still planar, because the moved loop is a pure translation of
the loop it grew from - so the solid stays valid whatever the neighbours are doing, and the end
face lands exactly where the slope said it should, still plumb.

`Na__SlopePush__SplitOffset` does that split. Off slope the remainder comes out as a zero
vector and the maths is exactly what the tool used before, which is why nothing about an
ordinary push changed.

### The Seam, and Why It Had to Be Cleared
A normal push welds its new wall into the coplanar wall it grew from and deletes the line
between them. A sheared one cannot: at the moment pushpull runs the new wall is NOT yet
coplanar with the roof - the shear is what makes it so, and by then the weld has already not
happened. Left alone that puts a plumb line across a roof the user just made continuous.

`Na__SlopePush__HealSeam` clears it afterwards, and reads its candidates off the moved face
rather than assuming which edges pushpull chose to keep - that is undocumented and not the sort
of thing to bet a delete on. The faces touching the moved face ARE the walls this push created,
so every edge considered is a line this push put there and every weld it can make is one native
pushpull would have made itself. It refuses anything not bounded by exactly two faces, refuses
the moved face's own boundary so the pushed face can never dissolve into its own wall, and
tests `samedirection?` rather than `parallel?` so two faces folding back on each other are left
alone. QUAD mode exists to KEEP that line, so this never runs there.

### One Direction, Everything Downstream for Free
`na_drawn__travel_direction` is the only place the two modes differ. The ray solve, the grid
snap, the measurements box, the preview shear, the travel arrow, the axis-lock cosine and the
commit all read it, so slope mode needed no second copy of any of them. `axis_normal_factor`
and `world_normal_travel` were renamed to `axis_travel_factor` and `world_travel_distance`,
because after this they are no longer about the normal.

**The loop cut came along too.** With QUADS on, an inward slope drag offsets its ring along the
whole travel rather than the normal's share - in slope mode the faces around the pushed one are
the sweep of its loop along the SLOPE, so that is the direction a cut has to follow to land in
them. Off slope the two are the same vector.

### ALT Is Read From the Mouse Flags First
On Windows a bare ALT press goes to the menu bar, so the matching key-up can simply never
arrive. The mouse flags are therefore the authority and `na_drawn__sync_modifier` re-reads the
bit on every mouse event, so a lost key-up corrects itself the moment the mouse moves. The key
events are kept as the supplement that catches a press made while the mouse is still - exactly
the arrangement CTRL already used. `activate` and `resume` both clear it.

The mask and key come from SketchUp's own `ALT_MODIFIER_MASK` / `ALT_MODIFIER_KEY` where they
exist, with the Windows literals as the fallback. Worth knowing: on a Mac those constants are
the Command key, because Option is already the copy modifier.

### Saying So Before the Click, Not After
A modifier that silently no-ops reads as broken. So the status line says three different things:
what ALT is following when it is doing something, WHY it is not when the face has no sloped
neighbour, and - with ALT up - that a trajectory is available at all, which is the only way
anyone discovers the feature. The hover label carries the same, the measurements box reads
"Slope distance", and the travel arrow in both tools now points along the travel rather than the
normal, so the picture matches the result.

### The 2D Tool Got It Without Asking
`DrawnPushPull2dTool` subclasses the 3D one and inherits the travel direction, the commit and
the shear. Since an elevation is exactly where a rake is easiest to see, that is the tool this
was really asked for.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnSlopePush__.rb`** - NEW. `Na__SlopePush__Candidates`,
   `Na__SlopePush__Best`, `Na__SlopePush__Distinct`, `Na__SlopePush__ContinuationOf`,
   `Na__SlopePush__ToWorld`, `Na__SlopePush__Label`, `Na__SlopePush__SplitOffset`,
   `Na__SlopePush__ApplyShear`, `Na__SlopePush__HealSeam`
2. **`Na__InsertPrimatives__DrawnToolShared__.rb`** - ALT tracked alongside CTRL:
   `NA_DRAWN_MK_ALT`, `NA_DRAWN_ALT_KEY`, `@na_alt_held`, `na_drawn__sync_modifier`,
   `onKeyDown` / `onKeyUp`, `activate` / `resume`
3. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** - `na_drawn__slope_mode?`,
   `na_drawn__slope_direction`, `na_drawn__travel_direction`,
   `na_drawn__local_offset_vector`, `na_drawn__slope_hint`; `axis_travel_factor` and
   `world_travel_distance` renames; `execute_push` takes a local offset and shears; seam
   healing; status, measurements box, hover label, hints and console report
4. **`Na__InsertPrimatives__DrawnPushPull2dTool__.rb`** - travel-direction arrows and labels,
   slope wording in the status line and measurements box
5. **`Na__InsertPrimatives__Main__.rb`**, **`Loader__.rb`**, **`PluginReloader__.rb`** - new
   module registered ahead of the tool that asks it

### Status: IMPLEMENTED - NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.33 - 03-Sep-2026 - Selection Biases the Deep Pick

### Requested
On deep push/pull and deep chamfer, prefer an already-selected group over the other groups
in the model, so faces inside the wrong group stop being grabbed by accident. With nothing
selected, nothing changes: loose geometry keeps its priority and the nearest group still
wins. A bias only, on the user's CURRENT selection - not a history of what was picked before.

### What Was Guessing, and Why It Was Wrong to Keep Guessing
The deep pickers walk the pick paths under the cursor and take the nearest one. That is a
good guess while the user has not said which group they mean. The moment they have, it is
just wrong: two groups overlapping on screen, and the face that gets grabbed is decided by
which of them sits a millimetre nearer the camera.

Selecting a group is the user saying it. So the selection is now read as intent - "work on
THIS one, leave the rest of the model alone until I deselect it" - and it is read fresh on
every hover, never remembered. Deselect and the bias is gone the same frame.

### The Rule, in Order
`Na__DeepPick__FaceAt` and `Na__DeepPick__EdgeAt` now run one pass ahead of the two they had:

0. **The selected group.** Any face or edge whose instance path passes through a selected
   group or component wins, at any depth below it, without the group ever being opened.
1. Loose geometry in the open editing context - unchanged.
2. The nearest nested face or edge - unchanged.

Pass 0 outranks the loose-geometry safeguard because a decision beats a guard against
accidents the user has explicitly stopped having. It is still a **bias and not a lock**:
nothing of the selection under the cursor and passes 1 and 2 run exactly as before, so
hovering a group that was not selected still picks it rather than refusing. The tool never
goes dead.

### Why Only Groups and Components Are Collected
The question the bias answers is WHICH CONTAINER did you mean. A selected loose face needs no
bias - rule 1 already hands it the pick. Collecting containers only also means a selection
holding no group at all says nothing about containers and correctly changes nothing.

### Ctrl+A Had to Be Harmless
With everything selected the focus contains every group in the model, which would favour the
nearest group over the loose face in front of it - a bias in the one case where the user
expressed no preference whatsoever. `Na__DeepPick__FocusYieldsTo?` stands the focus down when
the loose thing under the cursor is ITSELF selected: the safeguard's answer and the
selection's answer are then the same answer, so there is nothing to arbitrate. Selections
above 512 entities are dropped outright, so a select-all in a large model costs nothing per
frame either.

### The Focus Had to Survive Its Own Commit
Opening a group's editing context clears the selection, exactly as double-clicking into one
does by hand - and both tools open the target's context to commit. Left alone, the focus
would have died on the first push of the session with nothing on screen to explain why. The
selection is now taken before the context is entered and put back after it is restored, in
`Na__DeepPick__ExecuteInContext` (chamfer) and in `na_drawn__execute_push` (push/pull, and so
the 2D variant that inherits it). It only ever refills an EMPTY selection, and only with
entities that survived the edit, so it can never stomp a selection made since.

### No Cache, Deliberately
SketchUp offers no selection version to invalidate against and `SelectionObserver` is known
to miss changes. A stale focus would keep favouring the group the user just deselected -
precisely the bug this exists to prevent, and one that would be blamed on the tool. So it is
rebuilt on every hover. `Selection#length` is the native O(1) count, so the Ctrl+A guard runs
before any walk happens at all, and the focus test is a hash lookup that runs BEFORE a target
is built rather than after.

### Saying So
The status line carries ` - favouring <group name>` while a focus is active, in all three deep
tools. A rule that silently changes what a click grabs is worse than no rule; this one is
visible before the click, alongside the hover highlight.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** - new Selection Focus region:
   `Na__DeepPick__FocusInstances`, `Na__DeepPick__FocusSet`, `Na__DeepPick__InFocus?`,
   `Na__DeepPick__FocusedPickAt`, `Na__DeepPick__FocusYieldsTo?`, `Na__DeepPick__FocusLabel`,
   `Na__DeepPick__FocusSnapshot`, `Na__DeepPick__FocusRestore`; pass 0 wired into
   `Na__DeepPick__FaceAt` and `Na__DeepPick__EdgeAt`; selection preserved across
   `Na__DeepPick__ExecuteInContext`
2. **`Na__InsertPrimatives__DrawnToolShared__.rb`** - `na_drawn__focus_hint`
3. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** - selection preserved across
   `na_drawn__execute_push`, focus hint in the status line
4. **`Na__InsertPrimatives__DrawnPushPull2dTool__.rb`** - focus hint in the status line
5. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** - focus hint in the status line

### Status: IMPLEMENTED - NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.32 - 03-Sep-2026 - Inset Edge Loops (Inward Quad Drag)

### Requested
QUAD mode works flawlessly pulling OUTWARDS. Dragging inwards should cut inset edge loops
instead — proper edge-loop flexibility — in its own module, and still on the 5mm grid.

### Why the Inward Gesture Was Dead
Quads put a line back where an OUTWARD push started. Dragged the other way the start loop
ends up OUTSIDE the now-shorter solid, bounds no face, and the ring's own self-clean sweeps
it straight back off. The gesture ran, did nothing, and said nothing.

### What Was Built
**`Na__InsertPrimatives__DrawnEdgeLoops__.rb`.** With quads armed, dragging a face INTO the
material no longer shortens anything — it cuts an edge loop across the surrounding faces,
inset from the original face by the drag distance. Quads OFF still shortens, so TAB is the
switch between the two and neither behaviour is lost.

### Why the Offset Ring Lands on Real Faces
The faces around a pushed face are the SWEEP of its loop along its normal. So a start-loop
edge, offset along that same normal, lies exactly IN the face it generated — not near it,
in it. Handing those points to `add_edges` splits each surrounding face in two, which is an
edge loop.

That is the identical mechanism quads use outward, aimed at a different plane. It is
deliberately **not** a second copy of that code: `Na__PushPull__StitchQuadRing` already
carries the landing check, the fill-face removal (a closed coplanar ring inside a solid
makes SketchUp fill it, and that fill would be an internal wall) and the self-clean. The new
module owns the offset maths, the direction rule and the reporting, and delegates the ring.

### No pushpull Runs on This Path At All
That is the whole point — an inward drag with quads on is a CUT, not a shortening. The face
is never moved, so there is no start-loop-in-mid-air problem to solve.

### The Preview Had to Change or It Would Have Been Lying
The ordinary preview shades the face at its new position in result orange, which reads as
"the solid is about to end HERE". On this path the solid does not move. So the face stays
drawn where it is and the only thing placed at the inset position is the ring itself, in the
quad colour, because a line is genuinely all that gets created. The 2D tool keeps its swept
quad — that strip IS the nib the new line marks off — but the line takes the quad colour.

### One Rule, One Place
`Na__EdgeLoops__IsCut?` is asked by the preview, the status bar, the console report and the
commit, so they cannot disagree about which of the two a given drag is going to be. It reads
the SIGNED travel along the face normal rather than the raw drag: an axis lock divides by the
cosine between axis and normal, and that cosine can be negative, so a drag the mouse calls
positive can be travelling into the material. The commit asks the same question of the local
distance — `normal_scale` is a vector length and always positive, so the sign survives the
world-to-local conversion and the two answers always match.

### Failing Visibly
A chamfered or non-planar surround is not the sweep of the loop, so the offset edges land in
mid-air and get swept off. Worst case the gesture does nothing — so it now SAYS so, in the
status bar and the console, rather than reading as having been ignored. Nothing stray is ever
left behind and nothing pre-existing is ever removed.

### Snapping
Untouched. The distance still comes through the shared voxel snap, so a loop cut lands on the
5mm grid exactly as a push does, and CTRL still suspends it for vertex snapping.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnEdgeLoops__.rb`** — NEW. `Na__EdgeLoops__IsCut?`,
   `Na__EdgeLoops__OffsetLoops`, `Na__EdgeLoops__Cut`, `Na__EdgeLoops__Report`
2. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — the cut branch in
   `na_drawn__execute_push`, `na_drawn__loop_cut_mode?`,
   `na_drawn__draw_loop_cut_preview`, and the label / status / console wording
3. **`Na__InsertPrimatives__DrawnPushPull2dTool__.rb`** — loop-cut colouring and wording
4. **`Na__InsertPrimatives__Main__.rb`**, **`Loader__.rb`**, **`PluginReloader__.rb`** — new
   module registered, ordered after the tool whose ring stitcher it reuses

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.31 - 03-Sep-2026 - Push/Pull Dimensions on Every Travel Edge + Travel Arrow

### Requested
When push/pulling, ALWAYS show the dimension on every edge being extruded — three of the
four corners of a pushed wall were carrying no number at all — and add the direction arrow
the 2D tool has.

### Why Only One Corner Was Labelled
`na_drawn__draw_distance_label` took `@na_pp_loop.first` and `moved_loop.first` and labelled
that one travel edge. Which corner that turned out to be was down to loop order, so the
number appeared at a corner the user had not chosen and could not predict.

### Dimensions on Every Travel Edge
Every corresponding pair in `@na_pp_loop` / `moved_loop` is now labelled. A rectangle gets
four, which is the case this was asked for.

**"Every" is only safe because of the overlap cull.** A pushed circle has as many travel
edges as it has segments, and two dozen copies of one number stacked on each other is worse
than the single label this replaced. So a label is skipped when it would land within
`NA_DRAWN_LABEL_MIN_GAP_PX` (42 px) of one already placed that frame. The comparison is in
SCREEN space, not model space: whether two labels collide is a question about the viewport,
and two corners far apart in the model can project onto the same pixels.

### The Travel Arrow
Drawn from `@na_point_a` — the point actually grabbed — during the push.

**It follows the OFFSET, not the face normal and not the locked axis.** Taking it from the
offset means it flips to point INTO the solid on a negative push, which is the one case
where "which way is this going" is genuinely not obvious from the preview. An axis lock
changes what the drag MEASURES and never where the face goes, so an arrow following the
locked axis would point somewhere the geometry is not going.

### The Arrow Now Has One Implementation
It was written for the 2D tool; rather than copy it, it moved to
`Na__DrawnPreview__DrawDirectionArrow` and both tools call it. The barbs are still laid out
with the CAMERA direction so they open across the screen from any viewpoint, and the whole
arrow is still sized in pixels so it reads the same at any zoom. The 2D tool keeps a
one-line method of its own, because what it points at (the face normal, before any drag has
begun) is a decision belonging to that tool rather than to the drawing helper.

### What Did NOT Change
The 2D tool keeps its single label centred on the swept quad. Its target face is edge-on, so
its travel edges project onto the top and bottom of one strip — labelling both would print
the same number twice, a few pixels apart, for nothing.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — `na_drawn__draw_distance_label`
   rewritten to walk every travel edge, `na_drawn__claim_label_slot` for the overlap cull,
   `na_drawn__draw_travel_arrow`
2. **`Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — `Na__DrawnPreview__DrawDirectionArrow`
   plus the `NA_DRAWN_ARROW_PIXELS`, `NA_DRAWN_ARROW_BARB_PIXELS` and
   `NA_DRAWN_LABEL_MIN_GAP_PX` metrics
3. **`Na__InsertPrimatives__DrawnPushPull2dTool__.rb`** — its private arrow drawing replaced
   by a call to the shared one; three now-unused constants removed

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.30 - 03-Sep-2026 - Deep Push/Pull 2D Label Placement

### Requested
The 2D tool works. Its labels do not sit anywhere sensible — the hover block landed on top
of the direction arrow and read as belonging to nothing. Wanted: centred on the edge, inset
clear of the arrow.

### Why It Landed There
`Na__DrawnPreview__DrawWorldLabel` hangs its text off the anchor at a fixed `+14, -26` — up
and to the right. Every other tool anchors labels on a CORNER, where up-and-right is free
space. This tool anchors on an edge MIDPOINT and draws an arrow from that same point, so the
one fixed offset it inherited was guaranteed to collide.

### What Was Built
**The label is centred on its anchor and pushed to the side OPPOSITE the arrow**, measured
in screen pixels. The push includes half the block's own size along that direction, so the
whole block clears the anchor by the padding whichever way it ends up going:
- Horizontal edge, arrow up (the common case) — text centred on the line, sitting under it
- Vertical edge, arrow left — text to the right of the line, vertically centred on it

Chasing "below" literally was rejected: on a vertical corner line "below" walks the text down
to the foot of the wall for no reason, while "away from the arrow" keeps it beside the cursor
where the eye already is. In the horizontal case the two are the same thing.

**The drag label moved too, for the same underlying reason.** The inherited version hangs off
`@na_pp_loop.first`, an arbitrary corner of the target face — and that face is edge-on here,
so the number landed at one end of a line, nowhere near what it measures. It now sits in the
**middle of the swept quad**, which IS the thing being measured, and there is no arrow to
dodge once a drag is running. The direct-face path still falls back to the inherited label,
because there is no swept quad to centre on there.

### Text Metrics Are Estimated, and That Is Fine
`view.draw_text` reports no metrics, so `Na__DrawnPreview__TextBlockSize` estimates width from
the character count at the single size and weight every label in this plugin uses
(`NA_DRAWN_TEXT_CHAR_WIDTH`). Height is exact. The estimate only ever feeds CENTRING, where a
few pixels of error moves a label a few pixels — nothing measures anything by it.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — two purely ADDITIVE helpers,
   `Na__DrawnPreview__TextBlockSize` and `Na__DrawnPreview__DrawCentredScreenText`, plus the
   `NA_DRAWN_TEXT_CHAR_WIDTH` metric. No existing caller changes behaviour
2. **`Na__InsertPrimatives__DrawnPushPull2dTool__.rb`** — `na_drawn__draw_label_clear_of`,
   `na_drawn__screen_direction_away_from`, and an override of `na_drawn__draw_distance_label`
   that centres on the swept quad

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.30 - 03-Sep-2026 - Three-Way Corner Mitres (X-Y-Z Junctions)

### Reported
Two chamfers meeting at a corner mitre correctly; THREE — the full X-Y-Z box-corner
junction, all three edges banked — refused. A dedicated block now handles it.

### The Geometry — the Three Planes Are Concurrent
Worked through and verified numerically: the three chamfer planes at such a corner all
pass through a single apex point Q (on a square corner with setback d, Q sits at
(d/2, d/2, -d/2) from the vertex — 210mm on the reported 420 chamfer). Three planes in
general position ALWAYS meet at one point, so this is exact for any corner, not a box
coincidence. Consequently NO corner facet is needed:

- Each PAIR of edges gets its ordinary shared-face mitre point P — three of them.
- Each chamfer face's corner end becomes THREE points, P-Q-P, growing the face to a
  pentagon (hexagon when both ends of an edge meet three-way corners).
- The three pentagons pairwise share their P-Q mitre edges and the corner closes itself.
- The face substitutions needed NOTHING new: every face at the vertex is the shared face
  of exactly one pair and borders two of the three edges, so it receives the same P from
  both — which MergeSingles already dedupes.

### Implementation
- `MitreThreeWay`: validates the corner (pairwise shared faces exist, distinct, no extra
  faces), computes the three P points and the three chamfer planes from the UNPATCHED
  solves, derives Q as (plane1 intersect plane2) intersect plane3, then patches ends and
  apexes last. Any degenerate step refuses the whole group before anything is cut.
- The chamfer face is no longer a fixed quad: `FaceLoopLocal` / `FaceLoopWorld` build the
  boundary with apex points slotted in, feeding construction and preview from the same
  loop. Four-plus edges at one vertex still refuse honestly.

### Verified Before Handing Over
JS port of the exact solver path — side selection, P line intersections, plane normals,
seam, apex: P_AB=(d,d,0), P_AC=(d,0,-d), P_BC=(0,d,-d), Q=(d/2,d/2,-d/2) at d=420, and
the resulting pentagon confirmed planar.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** — three-way dispatch, MitreThreeWay, PatchCorner, face-loop builders, loop-based construction and preview

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.29 - 03-Sep-2026 - Locked Geometry Is Invisible + Open-Context Pick Corrected

### Requested
1. The quad extrude modifier to be available when push/pulling loose geometry.
2. Locked SketchUp objects to be ignored completely — no preview, no target, no edit.

### 1. Quad Extrude on Loose Faces
TAB was already shared: `na_drawn__quad_mode?` is read inside `execute_push`, which is the
same commit path for loose and nested faces alike, and the ring stitch runs against
`face.parent.entities` either way. Nothing was gated on nesting. What was missing was any
way to SEE the mode before committing to it, and quad mode is invisible until it matters:
on a face with no coplanar wall to divide, an armed push and an unarmed one look identical.

So the mode now shows on the face you are pointing at, not just in the status bar:
the hover outline draws magenta at width 3 when quads are armed, and the floating label
gains a `QUADS — keeps the start loop` line. Same treatment on every face, loose included.

### 2. Locked Geometry Is Not Refused, It Is Not There
`Na__DeepPick__LockedOut?` is now consulted by both pickers, and a locked pick is SKIPPED
rather than returned — so a locked group is transparent and the scan carries on to whatever
stands behind it. No hover highlight, no target, no push, no beep.

Refusing on click was the wrong model: it still highlights the face, still puts a target
under the cursor and still beeps at you for asking, which is noise when the reason a thing
is locked is that you have decided to stop touching it.

Both halves are tested. The PATH covers the normal case — a locked group or component
anywhere above the entity. The ENTITY'S OWN flag covers a drawing element locked directly,
which the UI does not offer but the API does, and which would otherwise slip through at
depth zero — exactly the loose geometry v0.4.28 just opened up. The click-time refusal in
`grab_face` is kept as a backstop and is now unreachable.

### Bug Found While Reviewing v0.4.28's Pass 1
The `picked_face` / `picked_edge` pass built its target with `nil` for both path and
transformation. At the model root that is correct — the path is empty and the transform is
the identity. **Inside a group the user has opened it is not.** That geometry is "loose" to
them but still nested to the model, so nil meant:

- depth reported as zero, so it was labelled loose and the group name was lost
- the face's LOCAL normal used as if it were the world normal — a rotated group would have
  previewed and pushed in the wrong direction
- `target_path` nil at commit, so `execute_push` would have decided the contexts differed
  and set `model.active_path = nil`, **closing the user's own open group** before pushing

Pass 1 now builds from `Na__DeepPick__ContextPath` and `Na__DeepPick__ContextTransform`.
Both are the identity case at root, so loose geometry behaves exactly as it did.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** — `LockedOut?` skipping in `FaceAt` and
   `EdgeAt`, `ContextPath` / `ContextTransform`, `ContextDepth` derived from the path
2. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — quad state on the hover outline and
   label, backstop comment on the locked refusal

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.28 - 03-Sep-2026 - Loose Geometry Push/Pull (Shallowest Face Wins)

### Reported
Deep Push/Pull could not operate on a loose face at all — geometry not inside any group or
component was simply not pickable. Asked for: make it work, PREFER it over nested geometry,
and label it as loose rather than showing a group name.

### Root Cause
`PickHelper#leaf_at` / `#path_at` walk INSTANCE PATHS. A face lying loose in the open
editing context has no instance path to walk, so it can be absent from that list entirely.
Both pickers scanned only that list, so loose faces and loose edges were invisible to them.

### The Fix — Two Passes, Shallowest Wins
`Na__DeepPick__FaceAt` and `Na__DeepPick__EdgeAt` now ask `PickHelper#picked_face` /
`#picked_edge` FIRST — the route that does report loose geometry — and fall back to the path
scan. The path scan itself now returns the first hit whose depth equals the open context's
depth, keeping the deepest nested hit only as a last resort.

**This is a safeguard, not a preference.** Reaching into a group without opening it is what
this tool is for, and it is also how a model gets wrecked by accident while drafting. If
something is in the context the user actually has open, that is what gets pushed.

The rule is written against the OPEN CONTEXT, not against the model root, so it reads the
same way at root (loose geometry wins) and inside a group the user is already editing (that
group's own geometry wins). `Na__DeepPick__ContextDepth` and `Na__DeepPick__InOpenContext?`
carry it. The `picked_face` pass is guarded by `InOpenContext?` deliberately: if that API
ever hands back something nested, taking it unchecked would kill deep picking outright.

### Quad Ring Bug This Exposed
Pushing a LOOSE face makes a box, and that box's new bottom face sits exactly on the start
ring — so it matched the fill-face test perfectly and got erased, leaving an open-bottomed
box. A second test now has to pass before anything is cut: **no edge of the candidate may
carry exactly two faces.**

- Two faces on an edge is a manifold pair — the candidate is half the skin there, and
  cutting it opens the solid. That is the loose-face box bottom.
- Three means the material already meets across that edge without the candidate's help —
  a genuine internal divider, safe to cut. That is the fill face quad mode must remove.
- One means the edge is holding nothing but the candidate — also safe, and it covers an
  open shell (a wall box with no bottom), where the leftover ring edge is then swept.

### Labels
`Na__DeepPick__PathLabel` returns `Loose geometry` at depth zero instead of `model context`,
and the push tool's status line reads `Loose geometry face` rather than `In ...`.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** — two-pass `FaceAt` / `EdgeAt`,
   `InOpenContext?`, `ContextDepth`, loose label
2. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — `DividerNotSkin?` guard on the ring
   fill erase, loose status line

### Knock-On
`EdgeAt` was fixed alongside `FaceAt` because it had the identical gap: the chamfer could
not chamfer a loose edge, and the 2D push/pull of v0.4.27 — whose whole premise is grabbing
an edge in elevation — would have been dead in a model of loose geometry.

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.27 - 03-Sep-2026 - Deep Push/Pull 2D (Parallel Camera Edge Push)

### Requested
Deep Push/Pull to work when the camera is 2D. The existing tool was designed for a 3D
camera and is perfect there, so it was not to be touched — a parallel-projection version
was wanted alongside it, and the plugin was to work out for itself which one applies so
there is no second button, no second shortcut and nothing for the user to manage.

### Why the 3D Tool Cannot Work in an Elevation
The wall you want to extend is edge-on to the camera. It renders as a LINE, so there is no
face to hover and nothing to grab. The face you *can* hover is the elevation itself, whose
normal points straight down the camera axis: pushing it moves geometry toward or away from
the viewer, which is invisible on screen and never what was wanted. Screenshot 01 of the
request marks exactly this — the elevation face `NO`, the wall behind the line `YES`.

### What Was Built
`DrawnPushPull2dTool`, a **subclass of `DrawnPushPullTool`**. It replaces two things —
how a target is CHOSEN and how it is DRAWN — and inherits the distance maths, axis lock,
quad ring, VCB entry, undo chaining and the entire commit path verbatim. The 3D file is
otherwise untouched, so nothing that was working can regress from a change made here.

**The pick is inverted.** Hover an edge, and the tool walks from that edge to the face
behind it and pushes THAT. The chamfer tool's `Na__DeepPick__EdgeAt` already does the edge
pick, and an edge and the faces it bounds live in the same definition — so the edge pick's
own path and transformation feed straight into `Na__DeepPick__BuildTarget`. No new picking
code was needed in the deep-pick module at all.

**Which face, decided by SCREEN FACTOR.** Every face the edge borders is scored on how much
of its normal lies in the plane of the screen: `sqrt(1 - (n . camera)^2)`. 1.0 is a face
perfectly edge-on to the camera — invisible, fully draggable. 0.0 is a face staring back at
the camera — fully visible, undraggable. Highest score wins, so the tool always takes the
face you cannot see over the one you can. In an elevation the split is total: the elevation
face scores 0.0 and is refused, the return wall scores 1.0 and is taken.

**Known ambiguity, deliberately resolved and shown.** A horizontal eaves or base line
borders both the wall end AND the wall top — in a level elevation both score 1.0. Ties
inside a narrow band go to the larger face, which picks the wall rather than its thin top,
and the hover arrow shows which way the push will go before a single pixel of drag.

**The direct face path survives.** Isometric views are parallel too, and a face is
perfectly grabbable in one. With no edge under the cursor the tool falls back to the
ordinary face grab, but only if that face is oblique enough (30 degrees off face-on) to
be dragged meaningfully. A face pointing at the camera is refused with a line saying to
hover an edge instead, rather than being silently accepted and behaving badly.

### The Ray Guard Had to Be Lifted
The inherited `na_drawn__depth_point_from_ray` discards a solve landing behind the pick
ray's origin. That guard is right for perspective and **harmful under a parallel camera**:
every pixel gets its own ray origin on the near plane, and where that plane sits relative
to the model is SketchUp's business — a perfectly good solve on the wall in front of the
user can test as "behind" and be thrown away, freezing the drag on its last good distance.
The degeneracy the guard protects against cannot arise here anyway: this tool only ever
grabs a direction lying across the screen, which is the best-conditioned case the solve
has, and an undraggable direction is refused at the pick before it can get that far.

### Camera Switching Is Automatic
- `Na__ModeSwitch__ActivateDrawnPushPullTool` is the single door every route already came
  through — menu item, shortcut, right-click popup — so asking the camera in that one place
  is what makes the split invisible. Perspective gets the 3D tool, parallel gets the 2D one.
- While a tool is running, an idle mouse move re-checks. Switch to a 2D scene tab and the
  2D variant takes over on the next move; orbit back into perspective and the 3D one
  returns. **Never mid-drag** — the check only runs at `:idle`.
- The swap is deferred one tick by a timer, because `select_tool` inside a mouse callback
  would tear down the object whose callback is still on the stack.
- Both tools report the same `:drawn_push_pull` popup key. To the user this is one tool
  that adapts, so the popup highlights one button either way.

### Preview, Rebuilt for a Camera That Cannot See the Target
Shading the target face would paint nothing — it is edge-on. Drawn instead:
- The grabbed edge, thick, in hover blue (magenta at width 5 when QUAD mode is armed)
- A **screen-sized direction arrow** along the push normal, so travel direction is readable
  before the drag starts — this is what disambiguates a tied eaves line
- Once dragging, the **swept quad**: the grabbed edge traced along the push. In an elevation
  that is exactly the strip of new wall the push will add, shown as an area rather than as
  a number in the status bar
- The target face's outline at both start and finish, with travel lines between them

### Controls
Unchanged from the 3D tool and all inherited — CTRL vertex snap, ARROWS axis lock, TAB quad
mode, VCB typed distance, BKSP, ESC, press-drag-release and click-move-click. One addition:
an arrow-key axis lock naming an axis that runs INTO the screen is refused, because the
mouse has no way to express travel along it and the lock would leave the drag stuck at zero.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPull2dTool__.rb`** — NEW. Camera interrogation, edge to
   hidden-face resolution, the `DrawnPushPull2dTool` subclass and its preview
2. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — `Na__ModeSwitch__ActivateDrawnPushPullTool`
   now asks the camera which tool to build (one function)
3. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — ONE guarded statement at the top of
   `onMouseMove` for the live 3D-to-2D handover. Inert if the 2D module is not loaded
4. **`Na__InsertPrimatives__Main__.rb`** — `require_relative` for the new module. This is the
   file that actually builds the dependency graph; the loader and reloader lists are
   ordering and hot-reload bookkeeping, so all three needed the entry
5. **`Na__InsertPrimatives__Loader__.rb`** and **`Na__InsertPrimatives__PluginReloader__.rb`** —
   new file registered, ordered after the tool it subclasses (a subclass reopened before its
   superclass would be a `superclass mismatch` on every hot reload)

### Console Entry Points for Testing
`Na__InsertPrimatives.Na__InsertPrimatives__DeepPushPull2d` and `...__DeepPushPull3d` force
either variant regardless of camera. `Na__InsertPrimatives.Na__PushPull__SetTrace(true)`
still traces both.

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.26 - 03-Sep-2026 - Deep Push/Pull Quad Mode (TAB)

### Requested
Deep Push/Pull to gain a TAB-toggled mode that extrudes but **keeps the join lines** —
edges only, no face. The use case is internal building walls: with quads armed, two
push/pulls strung together in different directions meet on a proper quad corner instead of
one melted-together surface.

### Why the Line Disappears in the First Place
`Face#pushpull` builds a fresh wall from the start loop to the finish loop, then MERGES
that wall into the coplanar wall it grew out of and **deletes the edge where they met**.
That edge is the quad line. It is not hidden, not softened, not smoothed — it is gone, and
no pushpull argument keeps it.

### What Was Rejected
`pushpull(distance, true)` — the "create new starting face" copy flag — leaves a whole
FACE in the start plane, and which of the two faces survives flips with the push direction.
Erasing the wrong one punches a hole in the solid. Screenshot 03 of the request is explicit
that the inside must stay hollow, so the copy flag is the wrong tool.

### What Was Built
The start loops are re-drawn as edges AFTER the push — the same merge machinery that
deleted the line, run the other way: an edge landing on a face splits it.

- **Loops are captured BEFORE the push.** `pushpull` moves the face, so its pre-push vertex
  positions are the only record of where it began. All loops are taken, not just the outer
  one, so a face with a hole gets its inner ring back too.
- **Any fill face the closed ring creates is erased.** A closed coplanar loop makes SketchUp
  fill it in, and that fill is the one thing this mode must not leave. Only a face whose
  OUTER loop IS the ring qualifies — a surrounding face that merely shares the ring (the
  wall around a recess) has a bigger outline and is left alone. Erasing a face leaves its
  edges, which is exactly the wanted result.
- **The ring self-cleans.** Every ring edge that ends up bounding no face at all is swept
  back off. That covers pushing INTO a solid (the start loop is left in mid-air, so it goes)
  without special-casing direction, and it covers a face that refused to split. Worst case
  the push behaves exactly as it does with quads off — it never leaves debris.

### The Coordinate Space Is Now MEASURED, Not Assumed
v0.4.22-v0.4.24 cost three releases to the open-context coordinate rule, and the fix that
came out of it is still unverified in SketchUp. Rather than bet this feature on the same
assumption, `Na__DeepPick__AddTransform` **probes** it: a construction point is added at a
known session-space position and its position read straight back. Unchanged means the
collection took the input as definition-local; moved means it converted it out of the
session's space. The probe is inert, lives and dies inside the caller's own operation, and
does not erase a construction point the user already had there (size guard).

Belt and braces on top: after `add_edges` the ring is checked corner by corner against the
local points it was aimed at. If a corner is missing the edges are taken straight back out,
the plain push stands, and both the status bar and the console say so. A quad ring can fail
to appear; it cannot leave a stray loop in the model.

### Controls
- **TAB** toggles quad mode, mid-drag included, and the preview redraws to show it
- The armed state is persisted (`DrawnQuadPushEnabled`) — set once, not per face
- Status bar carries `QUADS` and `TAB quads ON/OFF`; the start loop draws magenta at width 3
  when armed, because it is geometry the push is about to leave behind rather than a memory
- Console report gains a `Quads :` line — edges kept, edges swept, fill faces removed

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — TAB toggle, quad preview and status,
   ring capture/stitch/sweep, console report
2. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** — `Na__DeepPick__AddTransform` probe
3. **`Na__InsertPrimatives__DrawnGridSnap__.rb`** — persisted `QuadPushEnabled?` setting

### Note for the Chamfer Tool
`Na__DeepPick__AddTransform` answers, by measurement, the exact question v0.4.24 answered by
reading the docs. If the chamfer still misbehaves inside a group, swapping its
`model.edit_transform` for a call to this probe is the one-line test.

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.27 - 03-Sep-2026 - Corner Mitres (Batch Edges Meeting at a Vertex)

### Reported
Two banked edges meeting at a corner: the preview showed the two wedges' end triangles
stabbing through each other, and the generation failed outright. v0.4.26 named this case in
its own test list instead of engineering it.

### Why Sequential Cuts Can NEVER Work at a Shared Vertex
Diagnosed, not observed: when edge A cuts, it erases the shared face and the end face. At
that instant edge B bounds NO faces — so A's stray-edge sweep erases edge B itself. By B's
turn, `edge.valid?` is false and the group aborts. Independence is structurally impossible;
the corner must be built as one construction.

### The Geometry — a Mitre, Like a Picture Frame
Worked through on the box corner and verified numerically: the two chamfer planes intersect
along a line from **P** (where the two offset lines cross on the SHARED face — that face's
new corner, replacing the old vertex outright) down to **M** (the lower offset point, which
both edges place at the same spot on a square corner). Each chamfer quad ends on the mitre
edge P–M instead of its own end cap — still planar, verified — the two quads knit along it,
and NO end triangles exist at that corner. Each edge's OTHER face keeps its plain single
substitution; the partner's would-be end clip is a subset of the strip already removed and
contributes nothing.

### The Machinery — Whole-Group Construction
The batch group is now built as ONE construction, replacing the sequential loop:
1. Validate + solve every edge, aligned with its target.
2. `MitreBatch` pairs shared corners by Vertex identity, computes P by line-line
   intersection on the shared face, patches the solves in place and flags mitred ends.
3. `BuildGroupPlans` accumulates substitutions PER FACE across the whole group and merges
   them — a shared face carries both edges' strips in one plan (which also makes the
   parallel-edges-on-one-face case order-independent, better than v0.4.26's sequential
   re-planning). Mitred ends contribute no end-face pairs: the mitre IS their ending.
   Conflicting substitutions on one corner refuse the group.
4. `BuildGroup` erases everything once, rebuilds every plan, adds every mitred quad.
All-or-nothing per group, as before.

### Honest Refusals, Stated Refusals
Three-way corners, corners whose lower offset points do not coincide (non-square in the
third direction — needs extra facets this does not build), parallel edges at a shared
vertex, and corners carrying extra faces all refuse BEFORE anything is erased, with plain
messages. The preview shows the same mitre the commit will build — patched solves feed
both — and when a corner cannot mitre, the drag continues unmitred with the refusal
spelled out live in the status bar rather than discovered at commit.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** — MitreBatch / EndPoint / PatchEnd / MergeSingles / BuildGroupPlans / BuildGroup, group commit, aligned preview solves, mitred-end triangle suppression, status note

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.26 - 03-Sep-2026 - Multi-Edge Chamfer (SHIFT to Bank)

### Summary
SHIFT+click banks edges; one drag cuts them all. Each banked edge is validated on the way
in (two faces, unlocked, solvable), draws in the selection amber, and previews its own cut
at the live setback during the drag. The clicked edge drives the measurement; every rider
is solved against its OWN corner, so a batch can mix corner angles and even nesting depths.

### Interaction Grammar
- **SHIFT+click** banks an edge; SHIFT+click again un-banks it.
- **Plain click** on an edge starts the drag — clicked edge drives, banked edges ride.
  Clicking an already-banked edge does not double it.
- **BKSP** at idle un-banks the newest edge (the same newest-first peel the dimension
  locks use). **ESC** mid-drag drops the drag but KEEPS the bank — abandoning one drag
  should not cost a carefully built selection; ESC at idle clears the bank; ESC with
  nothing held exits. A banked edge undone out of existence silently drops from the bank.

### Commit — One Operation Per Context
Edges are grouped by instance path and each group cuts inside ONE ExecuteInContext
operation — the common case (several edges on the same group, as in the request's
screenshot) undoes in a single Ctrl+Z. Groups in different containers become one undo step
each. Any edge failing aborts its whole group: all-or-nothing per context, never a
half-cut group; partial batch results are reported in the status bar and console.

### The Ordering Subtlety Worth Recording
Adjacent edges share faces — the two long top edges of a box both border the top face, and
the first cut ERASES and REBUILDS that face. Plans captured up front for the whole batch
would therefore hold dead references by the second edge. So within a group each edge is
re-validated, re-solved and RE-PLANNED sequentially, just before its own build, from the
current model state (`edge.faces` re-read; the edge object itself survives its
neighbour's rebuild). Reads are definition-local whether or not the context is open — the
researched rule — so planning while entered is sound.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** — bank/toggle/batch state, SHIFT routing, rider previews, grouped batch commit, ESC/BKSP semantics, hints

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.25 - 03-Sep-2026 - Chamfer Drag Starts From Zero (Corner Plane Measurement)

### Reported
Nested chamfering now works, but the first moment of a drag was erratic: grabbing the edge
opened with a huge suggested chamfer (1395mm on a 4180mm edge in the report) that only
settled after wiggling the cursor. It should start from nothing and grow with the drag.

### Root Cause — Ill-Conditioned Ray-to-Line Solve
The setback was measured by finding the closest points between the cursor ray and the
bisector LINE anchored at the edge midpoint. Click near the END of a long edge and that
skew-ray solve finds its nearest approach far down the bisector — a metre-plus phantom
setback on frame one, calming only as the cursor happens toward the midpoint where the
solve is well-conditioned. The reported numbers match the geometry exactly.

### The Fix — Measure Against the Corner Plane
The cursor ray is now intersected with the CORNER PLANE — through the grab point, spanned
by the edge direction and the bisector — and the hit's bisector component is the travel:
- Ray-plane intersection is stable anywhere along the edge; there is no bad regime.
- The bisector is exactly perpendicular to the edge, so edge-parallel motion contributes
  nothing.
- At the grab instant the hit sits on the edge itself — the chamfer genuinely starts at
  zero and grows with the drag. Verified numerically: a hit 2m along the edge on the edge
  line gives setback 0; dragged to the 50mm chord it gives exactly 50.
- The anchor is now the point on the edge actually CLICKED (midpoint fallback), so the
  crosshair sits under the cursor rather than mid-edge.
- CTRL vertex snapping keeps its absolute meaning — a snapped vertex still yields the true
  setback that reaches it — and a grazing view holds the last good value as before.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** — corner-plane measurement, clicked-point anchor, frame vars

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.24 - 03-Sep-2026 - Chamfer Works Nested (Open-Context Coordinate Rule)

### Reported
v0.4.23's rebuild worked on loose geometry but failed inside groups and components —
useless for a tool whose whole point is DEEP NESTED, when Deep Push/Pull handles the same
nesting fine.

### Root Cause — Docs-Checked, Not Guessed
From Model#active_path=: **"When changing the active entities in SketchUp, the coordinate
system also changes."** Entity positions READ are always in the definition's local space,
but geometry ADDED while an editing context is open is interpreted in the EDITING SESSION's
coordinate system — the thing `Model#edit_transform` reports. Push/pull never met this
trap because `Face#pushpull` takes a scalar: no points cross the boundary. The chamfer
adds points, so inside an entered context its local coordinates landed in the wrong space.

This also retro-explains the stray displaced quad visible in the v0.4.22 destruction
screenshot — that WAS the chamfer face, built offset by exactly the group's transform.
And it explains "works on loose geometry": with nothing open, edit_transform is the
identity, so local and session coordinates coincide.

### The Fix
- **Plans are built BEFORE the context is entered** (`Na__DrawnChamfer__BuildPlans`), so
  every read is unambiguously definition-local, and a refusal costs nothing — no context
  change, no operation, no erase. Refusals now also print to the console.
- **Every added point passes through `model.edit_transform`**, read inside the entered
  block. That is correct in all four situations: context entered (session transform), root
  (identity), the user already inside the target group themselves (their session's
  transform), and the outside-context fallback at root. Erases are coordinate-free and
  untouched. The captured normals and the bisector are transformed the same way so winding
  and orientation checks compare like with like.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** — `BuildPlans` pre-entry, `Build`/`RebuildFace` take a build transform, header rule documented

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.23 - 03-Sep-2026 - Chamfer Construction Rebuilt (Destroyed Geometry Fix)

### Reported
The chamfer preview and interaction were right, but committing destroyed the geometry:
the corner cut away with no chamfer face, top and front faces gone, hollow box.

### Root Cause — an Unverified Assumption, Now Checked Against the Docs
The construction assumed that an edge added on a face SPLITS it, the way the UI Line tool
does. The API documentation was fetched and checked this time: `Entities#add_face` /
`#add_line` / `#add_edges` carry **no note of any automatic splitting, merging or
intersection with existing geometry whatsoever** — that behaviour belongs to the UI tools,
not the API (the API-side options are explicit `intersect_with`, or building the result
yourself). So the chamfer quad never split the top and front faces, and when the corner
edge was erased, every face it bounded died whole. Exactly the hollowed box.

### The Fix — Capture, Substitute, Rebuild (No Splitting Relied On Anywhere)
The strategy mature chamfer plugins use:
1. **Capture** every face touching the corner — the two chamfered faces plus every face on
   either end vertex — as ordered outer-loop position lists with material, back material
   and tag.
2. **Substitute** the corner vertices: v0/v1 become a0/a1 on face A, b0/b1 on face B, and
   the **a/b pair** on each end face, clipping its corner into the chamfer. Pair winding is
   settled by which offset point sits nearer the previous loop position.
3. **Erase** the captured faces and the corner edge, sweep edges left bounding nothing.
4. **Rebuild** each planned face — `add_face` reuses the surviving coincident edges, which
   knits the new shell onto the untouched neighbours — restore front/back materials and
   tags against the captured normal, then add the chamfer quad dressed like face A.

### Safety Property Worth Stating
All plans are built and validated BEFORE the erase phase, and every failure raises — the
surrounding operation aborts and the model is left exactly as it was. Faces with inner
loops (openings) are refused up front rather than mangled. The tool can no longer destroy
geometry: it cuts correctly or it declines.

### Verified Before Handing Over
The plan substitution was simulated on the box case: all four rebuilt loops planar, the two
end-face pentagons simple (non-self-intersecting) with the pair heuristic choosing the
right insertion order on BOTH ends (they wind opposite ways), chamfer quad planar.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** — `RebuildPlan` / `RebuildFace`, `Build` rewritten, header construction note corrected

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.22 - 03-Sep-2026 - Chamfer Preview Polish

### Update 01 — The Doomed Wedge Shades Blue
The preview previously showed only the amber cut plane. It now also fills the material
being REMOVED — the two face slivers plus the end triangles — in the plane blue, so what
disappears reads separately from the cut face that replaces it. Blue wedge first, amber
plane over it.

### Update 02 — Setback Dims Nudged Clear of the Corner
The two setback numbers sat at the guide-line midpoints, right on the corner geometry. Each
is now pushed 34px further along the screen direction AWAY from the cut plane's centre, so
the number lands beside the shape whatever the camera angle, with an edge-on fallback when
that direction degenerates.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnChamferTool__.rb`** — wedge fill, `na_drawn__draw_setback_label`

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.21 - 03-Sep-2026 - Deep Chamfer Tool

### Summary
A second Modify tool alongside Deep Push/Pull: **Deep Chamfer**. Hover any edge — at any
nesting depth — click to grab it, drag into the corner to open the cut, click / Enter / a
typed value to place it. The preview is the established style: amber cut plane, guide lines
along both setbacks with bracketed-when-pinned dimensions, and a summary card carrying
setback, face width, angle and edge length. The same solve feeds the preview and the
commit, so the cut that lands is exactly the one shown.

### Built on the Push/Pull Lessons From the Start
Every lesson that saga was paid for is wired in on day one, not found later:
- The edit runs inside the edge's own context, so the display refreshes instantly and undo
  is one Ctrl+Z. The context manager is now a shared function —
  `Na__DeepPick__ExecuteInContext` — carrying the enter/restore logic and the conditional
  transparent-operation undo chaining. (Push/pull keeps its private copy untouched; it just
  started working and stays that way. Migrating it to the shared function is a tidy-up for
  a quiet day.)
- Once an edge is grabbed nothing is picked mid-drag: the setback is pure ray-to-bisector
  maths, an unsolvable frame keeps the last good value, CTRL alone re-enables inference.
- Two states only, `ensure_known_state` at every entry point, Backspace releases the edge
  outright, `onReturn` / double-click owned by the tool.

### What the Drag Measures
The cursor is projected onto the corner bisector and converted to the per-face setback —
the number a joiner specifies ("a 50 chamfer" is 50 off each face). The setback is what
snaps to the voxel grid. The chamfer is symmetric IN WORLD SPACE: under a non-uniformly
scaled instance the two local setbacks are solved separately from the per-direction scale —
the push tool's normal_scale trap, in two directions at once.

### A Real Bug the Numeric Pass Caught Before Shipping
The drag conversion was first written as `d = t * cos_half`; the verification harness
showed the cut plane trailing at HALF the drag on a square corner. The chord crosses the
bisector at `t = d * cos_half`, so the WYSIWYG mapping — cut plane under the cursor — is
`d = t / cos_half`. Corrected and re-verified at 90 and 120 degrees. Same discipline as the
roof pitch bug in v0.4.9: the JS port of the solve earns its keep.

### Construction
One `add_face` does most of the work: the chamfer quad's long edges lie on the two faces
and split them; its end edges clip any coplanar end faces. Erasing the original edge kills
the two slivers, corner triangles are erased by vertex identity, orphaned edges swept, and
the chamfer face oriented outward (against the bisector). On a clean solid the result is a
solid again. Guards: edge must border exactly two faces, locked paths refused, folded-flat
corners (cos half-angle under cos 85°) refused at grab, shared-definition warning as per
push/pull.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnChamferTool__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** — `EdgeAt` / `BuildEdgeTarget` deep edge picking, shared `ExecuteInContext`
2. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — chamfer activation and mode switching
3. **`Na__InsertPrimatives__RightClickPopup__.rb`** — Deep Chamfer button in the Modify section
4. **`Na__InsertPrimatives__Main__.rb`** — require and architecture note
5. **`Na__InsertPrimatives__Loader__.rb`** — `NA_DeepChamfer` command, keyed menu entry, purge list
6. **`Na__InsertPrimatives__PluginReloader__.rb`** — reload order

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.20 - 03-Sep-2026 - Push Undoes in One Ctrl+Z

### Confirmed in Testing
v0.4.19's caveat was real: a push took **three** Ctrl+Z to unwind — restore-context, push,
enter-context — with the middle press teleporting the user back inside the group.

### The Fix
Checked against the Model docs first: `start_operation(op_name, disable_ui,
next_transparent, transparent)`. `transparent` merges an operation backwards into the
previous undo entry; `next_transparent` pulls the following entry forwards into it. When a
context was entered, the push op now starts as `('Deep Push Pull', true, true, true)` —
merging backwards into the enter step and pulling the restore step in behind it, so
enter-push-restore undoes as one action.

- `next_transparent` is deprecated and dangerous when a user action can slip in behind it.
  None can here: the restore runs synchronously in the same call before control returns.
- **Strictly conditional.** Without a context change those flags would merge the push into
  whatever the user did last, making their next Ctrl+Z silently eat two unrelated actions —
  so the plain two-arg form is kept for the no-entry path.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — conditional transparent chaining in `execute_push`

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.19 - 02-Sep-2026 - Root Cause: Outside-Context Edits Never Repaint

### The Clue That Cracked It
"If I hit escape it completes though?" — ESC at idle exits the tool, and a tool switch
forces SketchUp to regenerate the display. So the push was landing in the model at click
time all along; only the **render** was stale. Every symptom re-reads correctly under that:

- "Preview shows it but doesn't build it" — it did build; the screen didn't update.
- "Delays a second then builds it" — some other event forced a repaint.
- "Selecting invisible faces" — picks found the REAL (moved) geometry; the drawn box was
  the stale one. The v0.4.16 screenshot showed the highlight bigger than the box — that was
  read backwards at the time. The highlight was the truth; the box was the lie.

### Root Cause
`Face#pushpull` on entities inside a group/component **from outside its editing context**
changes the model but does not rebuild that instance's display cache. `invalidate_bounds`
(v0.4.15) refreshes only the bounding box, and `view.refresh` does not rebuild instance
caches either — which is why both earlier attempts changed nothing. The create tools never
hit this because they build into `active_entities`, the open context, which SketchUp always
repaints. Community guidance is blunt about outside-context edits: unsupported, artifact-prone.

### The Fix — Do What a User Does: Enter, Push, Leave
`na_drawn__execute_push` now opens the face's own context with `model.active_path=`
(SketchUp 2020+) before the operation, pushes, commits, then restores whatever context the
user was in (root or otherwise), falling back to root rather than ever stranding them
inside a group the tool opened. `active_path=` refuses to run inside an open transaction,
so the order is strict: enter → start_operation → pushpull → commit → restore. If entering
fails (old version, dead path), it falls back to the outside-context edit plus
`invalidate_bounds`, same as before.

### Caveat to Verify in Testing
Programmatic context changes may record their own undo steps around the push — check
whether undoing a push takes one Ctrl+Z or three. If three, the follow-up is operation
chaining, not a redesign.

### Retained
Every earlier fix in the saga was real and stays: `onReturn`/double-click existing at all
(0.4.15), the status-bar throttle (0.4.16), no InputPoint fallback mid-drag (0.4.17), state
containment + trace switch (0.4.18). They were necessary layers — this one was the cause of
the headline symptom.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — context-managed push (`execute_push` / `same_context?` / `restore_context`)

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.18 - 02-Sep-2026 - Push/Pull State Limbo (Audit, Not Guesswork)

### Method
Three rounds of fixes had been reasoned from screenshots and had not landed. This round
audited the code mechanically instead: nesting depth of every method, which Tool callbacks
the class actually owns versus inherits, and which states each callback can produce.

That found the limbo immediately.

### The Bug — a State the Tool Cannot Service
The audit showed **15 behavioural Tool callbacks still coming from `DrawnToolShared`**, a
mixin built around a three-stage machine: `:idle` > `:picking_b` > `:picking_depth`. The
shape tools sweep a rectangle before extruding; push/pull has no rectangle stage and **no
`:picking_b` branch anywhere in it**.

The inherited BKSP/DEL handler calls `na_drawn__step_back`, which demotes `:picking_depth`
to `:picking_b`. In that state push/pull is dead:

- `onLButtonDown` — `case @na_state` matches no branch, so clicks do nothing
- `onReturn` / double click — routed to `advance_from_b`, which is a stub returning false
- `onMouseMove` — the cursor override bails out, so the distance never updates
- `draw` — still not idle, so it keeps painting the push preview

Everything except ESC is inert, while the preview stays on screen. That is exactly the
reported "stuck in a weird limbo where you can effectively select invisible faces" — the
preview overlay persisting over geometry that is no longer being driven.

### The Fix — Contain the State Machine
- `na_drawn__ensure_known_state` snaps any state that is not `:idle` or `:picking_depth`
  straight back to `:idle`, and is called at every mouse and key entry point. Rather than
  audit every inherited path for respecting a state this tool lacks, the tool now refuses to
  sit in one.
- `na_drawn__step_back` is overridden: Backspace releases the grabbed face and returns to
  idle. A push either has a face or it does not — there is no half-retreat.
- `onReturn` and `onLButtonDoubleClick` are overridden so neither can be routed at a stage
  this tool does not have.
- Verified mechanically: nothing in the file sets `:picking_b`, the guard sits at 5 entry
  points, and all 51 methods are at class-body depth so every override genuinely wins over
  the mixin.

### Trace Switch
Diagnosing this from screenshots cost three wrong guesses. There is now a console trace:

```ruby
Na__InsertPrimatives.Na__PushPull__SetTrace(true)
```

Every grab, placement, refusal and state recovery prints with the state, distance, face id,
CTRL and axis lock it saw. The next question about this tool gets answered from a log.

### Retained from Earlier Rounds
`onReturn`/`onLButtonDoubleClick` existing at all (0.4.15), the status-bar throttle (0.4.16)
and removing the InputPoint fallback from the push cursor (0.4.17) are all still correct and
still in. None of them was the limbo.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — state containment, step_back / onReturn / double-click overrides, trace switch

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.17 - 02-Sep-2026 - The Actual Push/Pull Bug

### Read the Docs First This Time
Three rounds of fixes had not touched the cause. The Tool API documentation was read
properly before this one, and it both named the bug and turned up two facts worth recording.

### The Bug — an InputPoint Pick Hiding in a Fallback
`DrawnToolShared#na_drawn__update_cursor` ends with:

```ruby
resolved ||= na_drawn__input_point_position(view, x, y)
```

For the shape tools that line is harmless — the InputPoint is their normal cursor source
anyway. For push/pull it is the whole problem. Any frame where the ray-to-line solve returns
nil (a near-parallel view, the behind-camera guard tripping) silently **re-picks against
whatever face is under the cursor** and turns its inferred point into a push distance.

That is precisely the reported symptom: "the face selection remains active the whole time,
even when you're dragging, so you're accidentally selecting other faces." And because the
solve only fails on *some* frames, it read as intermittent stickiness rather than a
straightforward bug — which is what sent the previous three attempts chasing rendering and
caching instead.

Why the drawing tools felt perfect while this one did not now has a concrete answer, rather
than the guesses in v0.4.15 and v0.4.16.

### The Fix
The push tool now owns its cursor tracking outright:
- Once a face is grabbed, **nothing is picked again** unless CTRL explicitly asks for vertex
  inference.
- The distance is pure ray-to-line maths against the stored push direction.
- A frame that cannot be solved **keeps the previous distance** rather than inventing a new
  one from a stray pick.

Which is what the brief asked for: grab the face, follow the drag, place it where the user
stops. No intermediate picking.

### Two Facts from the Documentation Worth Keeping
1. **`onMouseMove`** — "Try to make this method as efficient as possible because this method
   is called often." Confirms the v0.4.16 status-bar throttle was worth doing on its own
   merits, even though it was not the cause here.
2. **`onKeyDown` has a known Return/Enter regression in SketchUp 2026.0 on Windows, fixed in
   2026.1** — and `onReturn` had its own regression in 2025.0, fixed in 2026.0. Enter is
   handled through `onReturn`, which is the path that works on 2026.0 and later. Worth
   knowing if Enter ever misbehaves again: check the point release before the code.
3. Screen coordinates changed from Integer to **Float** in SketchUp 2025.0. Nothing in this
   plugin depends on them being whole numbers, but it is worth knowing they are not.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — dedicated `na_drawn__update_cursor` with no pick fallback

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.16 - 02-Sep-2026 - Push/Pull Stickiness (v0.4.15 Follow-Up)

### What the Screenshot Settled
A hover highlight reported 27.97 m² and was drawn larger than, and offset from, the box it
belonged to — while the box itself rendered cleanly, with correct shading and a shadow.

That rules out the v0.4.15 theory. The **render was fine**; the **highlight** was wrong. Two
of the three fixes in v0.4.15 were aimed at a stale viewport that was not the problem, and
one of them actively made things worse.

### Bug 01 — The Cache Guard Could Not See a Moved Face
v0.4.15 added a hover cache keyed on `entityID` plus the transformation. But `pushpull`
**moves a face and keeps its id**, and the group transformation never changes — so after a
push the guard said "same face" and happily reused triangles cached from before it moved.
That is the offset blue overlay, exactly.

The fingerprint now includes a vertex position and the vertex count alongside the id and
transformation, so a face that has moved reads as different. Reading one vertex costs
nothing next to re-triangulating a mesh, so the performance win is kept.

### Bug 02 — Re-Picking Inside the Commit
v0.4.15 also re-hovered immediately after committing, to refresh the highlight without
waiting for a mouse move. That picks geometry SketchUp has not finished settling, in the
same event as the change, and caches a highlight of the old shape. Removed — the next mouse
move re-picks cleanly and is instant in practice.

### Bug 03 — view.refresh
Also from v0.4.15, and also removed. Forcing a full synchronous repaint from inside a click
handler costs more than it buys, and it was aimed at the render problem that turned out not
to exist. `invalidate` and `invalidate_bounds` stay — `invalidate_bounds` is cheap and still
correct for nested edits.

### Bug 04 — The Actual Stickiness
`na_drawn__update_status_text` called `Sketchup::set_status_text` **unconditionally on every
mouse-move event**, in every tool. That is a native UI call at mouse-move rate, composing and
pushing an identical string hundreds of times a second. It is now only sent when the composed
line actually differs.

This is the one that should be felt across the whole plugin, not just push/pull.

Side benefit: a transient warning is no longer wiped by the very next mouse move, because an
unchanged composed line is not re-sent over the top of it.

### Retained from v0.4.15
`onReturn` and `onLButtonDoubleClick` were genuinely missing and stay fixed.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — status text only sent on change
2. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — position-aware fingerprint, re-pick and refresh removed

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.15 - 02-Sep-2026 - Push/Pull Commit Bugs

### Reported
"Sometimes a second delay. Other times Enter or double-click doesn't close it at all. It
renders the preview of the extruded bit but doesn't build it, then delays and builds it.
When it gets stuck you end up in limbo selecting invisible faces."

Four separate defects, not one.

### Bug 01 — Enter Did Literally Nothing
SketchUp only routes Enter to `onUserText` when text is pending in the measurements box.
With an **empty** box it calls `onReturn` instead — and `onReturn` was implemented nowhere
in this plugin. So "drag, then press Enter" had no handler at all.

Galling detail: this exact routing rule is written up in the Profile Path Tracer devlog,
researched at the time, and then not applied here. `onReturn` now confirms the current
stage, which fixes Enter across **all six** tools, not just push/pull.

### Bug 02 — Double-Click Was Unhandled
`onLButtonDoubleClick` did not exist either. A double click delivers Down, Up, DoubleClick,
Up, so the first Down usually placed the shape already — but "usually" is what made it feel
random. It is now handled explicitly and is a no-op once the tool is back to idle.

### Bug 03 — The Invisible Faces
The push **was** working. A component definition caches its bounding box, and editing its
entities from outside its editing context does not reliably dirty that cache, so the model
held the new geometry while the viewport carried on drawing the old shape. Hovering then
picked geometry that was genuinely there but not being rendered — the "invisible faces",
and the "delay, then it appears" once something else forced a repaint.

Three fixes, all cheap and none with a downside for a single push:
- `Na__DeepPick__InvalidateDefinitions` walks the instance path innermost-first and calls
  `invalidate_bounds` on each definition. Innermost first because an outer definition's
  bounds depend on the inner ones already having been recomputed.
- The push operation no longer passes `disable_ui`. The create tools can afford it because
  they add to `active_entities`, which dirties the model on its own; suppressing the UI
  through a nested-definition edit is what leaves the viewport stale.
- `view.refresh` after commit, since `invalidate` only marks the view dirty and leaves the
  actual repaint until the next event.

### Bug 04 — The Stutter
Hover called `adopt_target` on every mouse move, and that triangulated the face through its
`PolygonMesh`, transformed every vertex to world and re-measured its area — all at
mouse-move rate. On any reasonably dense face that is exactly the "lagging a beat behind the
cursor" feel. The cache is now rebuilt only when the picked face actually changes, compared
on `entityID` plus the transformation.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — `onReturn` and `onLButtonDoubleClick`, benefiting every tool
2. **`Na__InsertPrimatives__DrawnDeepPick__.rb`** — `InvalidateDefinitions`
3. **`Na__InsertPrimatives__DrawnPushPullTool__.rb`** — hover cache guard, operation flags, forced redraw, re-hover after commit

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.14 - 02-Sep-2026 - Menu Registration Survives a Reload

### The Problem
Deep Push/Pull did not appear in Preferences → Shortcuts. Not a typo in the wiring — the
command was built and added correctly. The menu block sat inside
`unless file_loaded?(__FILE__)`, which means it only ever runs at SketchUp startup, and the
reloader only ever touched the modules folder. So a tool added mid-session had no menu
entry, and SketchUp keys shortcuts to the menu path — no entry, no shortcut.

That is a design flaw rather than an oversight: v0.4.10 added a hot reloader and then left
the one thing that most needs refreshing outside its reach. Every future tool would have
hit the same wall.

### Update 01 — Keyed, Idempotent Menu Registration
- The `file_loaded?` guard is gone. Each menu entry and separator now carries a permanent
  key in a registry held in a global — a global specifically because it has to survive this
  file being re-loaded, which a constant on the plugin module would not.
- Running the block again therefore adds only what is genuinely new and never duplicates,
  which matters because SketchUp cannot remove a menu item once added.
- Simulated the double-run: a second pass adds nothing, a pass carrying a new tool adds
  exactly one entry, and the submenu is created exactly once.
- **Caveat, stated rather than hidden:** an entry registered by a reload appends to the end
  of the submenu, since the API has no insert-at-position. It lands in its designed place on
  the next restart. Available immediately beats perfectly ordered.
- Keys are the permanent identity of an entry. Renaming one would make a reload add a
  duplicate alongside the original, so the comment in the loader says so.

### Update 02 — The Reloader Now Refreshes the Menu
- `Na__Reload__RootLoader` loads the root loader after the modules and reports how many new
  entries appeared, in both the console and the status bar.
- A `$na_insert_primatives_reloading` flag stops the loader re-requiring every module on the
  way through — the reloader has just done that — and stops it reloading the reloader from
  inside the reloader, which is a reentrancy knot with nothing to gain.

### Update 03 — Slash Removed from the Menu Text
`menu_text` was `"Deep Push / Pull"`. SketchUp builds the shortcut path with `/` as the
separator, so that would have read as two extra path levels in the shortcuts dialog. Now
`"Deep Push Pull"`. The status bar title and the popup button keep the slash — neither is a
menu path.

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — keyed menu registry, guard removed, reload-aware skips, menu text fix
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__PluginReloader__.rb`** — reloads the root loader and reports new menu entries

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.13 - 02-Sep-2026 - Deep Push/Pull + Arrow Key Axis Locking

### Summary
A sixth tool, in a new **Modify** section of the right-click menu: **Deep Push/Pull** works
on any face at any nesting depth, without opening the group or component first. And arrow
keys now lock an axis across every tool, drawing SketchUp's red / green / blue ray.

### Update 01 — Reaching Into Nested Geometry
- Native Push/Pull only sees faces in the current editing context: a face inside a group
  means double-clicking down to it first. `PickHelper#leaf_at` with `#transformation_at`
  hands back the deepest face under the cursor plus the accumulated transformation, which
  is everything needed to work on it in place.
- Hover highlights the face, click grabs it, drag pushes, click places. Press-drag-release
  works too.
- **The scale trap.** `Face#pushpull` takes a distance in the face's own local space, while
  the drag is measured in world. Inside a scaled component those disagree, and a push would
  overshoot by exactly the scale factor. Transforming the unit local normal gives a vector
  whose *length* is the scale along that direction, so `local = world / scale` corrects it.
  Verified numerically against uniform, non-uniform, mirrored and rotated-then-scaled
  transformations with tilted normals — all land within 1e-9 of the requested world travel.
- Faces inside locked groups are refused. Pushing a face in a definition placed more than
  once changes every copy, which is correct SketchUp behaviour rather than something to work
  around silently — so the instance count is counted on pick and called out in the status bar
  and the console.

### Update 02 — Distance Is Snapped, Not the Point
Every other tool rounds the cursor point onto the lattice. That is wrong here: a face normal
is rarely axis-aligned, so rounding a point on it gives ragged distances. The travel along
the push direction is snapped instead, which keeps clean 5mm pushes at any face angle. CTRL
still suspends it, and because the cursor then comes from the InputPoint, the push distance
becomes the projection of an inferred vertex onto the push axis — push a face until it is
flush with an existing corner.

### Update 03 — Arrow Key Axis Locking, Everywhere
- Right / Left / Up lock X / Y / Z following SketchUp's own colour mapping; the same arrow
  again releases, and Down always releases.
- A full-width coloured ray is drawn along the locked axis. Its span comes from
  `pixels_to_model` rather than a fixed model length — a fixed one would vanish to a dot on
  a site plan and shoot past the horizon on a detail.
- Each tool maps the arrows onto **its own** axis decision, so the key always means "this
  axis" without ever meaning nothing:
  - Shape tools — the axis names the plane it is normal to, so Up (blue Z) draws on plan.
  - Roofs — the axis is the ridge direction. Up is refused with a note, since a ridge
    cannot stand vertical.
  - Push/Pull — the axis is what the drag measures along.
- **What a lock means for push/pull.** `pushpull` only ever extrudes along the face normal,
  so a lock cannot redirect it. Instead it changes what the drag measures: lock to Z, drag
  1000, and the face is pushed far enough along its own normal to end up 1000 higher.
  Raising a sloped plane by a known vertical is a real gap in the native tool and this
  closes it. A face edge-on to the locked axis cannot travel along it at all, so the lock is
  refused rather than dividing by something close to zero.

### Update 04 — Preview
- The hover and push previews use the face's own `PolygonMesh` triangles rather than its
  outer loop, so concave faces and faces with holes shade correctly instead of being filled
  straight over.
- World-space triangles and loop are cached on pick rather than re-transformed every frame,
  which matters on a dense face during a drag.
- Original outline stays visible in blue while the pushed result draws in amber with
  connectors between them, and the distance label carries the axis colour when locked.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnDeepPick__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPushPullTool__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — Deep Push/Pull command and menu item, reload list
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — requires
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__PluginReloader__.rb`** — reload order
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`** — axis keys, labels, axis-to-plane map
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — axis colours and ray, triangle and loop drawing
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`** — arrow key handling, axis lock state, ray drawing, push/pull activation
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofTools__.rb`** — arrows drive the ridge direction
8. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — Modify section

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.12 - 02-Sep-2026 - Axis Pinning + CTRL Vertex Override

### Summary
Two changes to how the drag tools take input. A typed value now **pins one axis** and
leaves the rest on the mouse, instead of being broadcast to all of them. And holding
**CTRL** suspends the voxel grid for as long as it is down, handing the cursor over to
SketchUp's own inference so a drag can land on an existing vertex, midpoint or endpoint.

### Update 01 — Typed Values Pin One Axis
- Typing `350` used to broadcast to a 350 square. It now sets the width, **pins** it so the
  drag stops moving it, and leaves the height under the mouse. A second bare value pins the
  height and places the shape; a click places it with the height as dragged.
- `Na__DrawnVcb__ResolveAgainst` is strictly positional now — the single-token broadcast is
  gone. The click-to-place Cube and Plane modes keep their own broadcast parsers, so
  `1m` still makes a cube there. Only the drag tools changed.
- A comma makes an entry positional, which is what lets a specific axis be named:
  `,1610` pins the height and leaves the width dragging, `350,` does the reverse.
- **A bare value addresses the first axis still on the drag, not slot zero.** Caught while
  tracing the flow: with the width already pinned, a second `1610` would otherwise have
  landed back on the width and quietly overwritten the pin, so `350` then `1610` could never
  have pinned both. `na_drawn__align_single_token` shifts a comma-free entry to the first
  unpinned slot.
- Pins are shown two ways at once, because colour alone is easy to miss mid-drag: a pinned
  dimension is drawn in burnt orange **and** wrapped in brackets, `[350]`, in both the
  viewport labels and the status bar.
- **BKSP releases the newest pin** before it steps back a stage, so a mistyped lock does not
  mean abandoning the drag.
- Applies across all five drag tools: plane W/H, volume W/L/D, cylinder radius and height,
  roof plan sides and rise.
- Revise mode (typing straight after a shape is drawn) clears pins and stays strictly
  positional. There is no drag there, so "the axis still under the mouse" would mean nothing.

### Update 02 — CTRL Suspends the Grid for Vertex Snapping
- Held CTRL bypasses `Na__DrawnGrid__SnapPoint` entirely and routes the cursor through the
  InputPoint, so whatever SketchUp infers — a vertex, a midpoint, an endpoint inside a
  nested group or component — survives instead of being rounded onto the lattice. Release
  it and the 5mm grid is back. The grid remains the default and is never turned off.
- It applies to **every** pick: the anchor click, the second corner, the extrusion, and the
  cylinder radius. So a drag can start on one existing corner and finish on another at,
  say, 2.5 / 2.5 / 5.
- CTRL also overrides the locked-plane and depth pick-ray paths. Those are more predictable
  for free dragging, but they have no vertex inference to offer, which is the entire point
  of holding the key.
- Read from two sources: the mouse-event flags (authoritative during a drag) and
  `COPY_MODIFIER_KEY` in the key callbacks (catches a press or release while the mouse is
  still). The SKEXT-3890 double-fire that broke Tab rotation cannot bite here — this is a
  held flag, not a toggle. `activate` and `resume` clear it so a key-up missed while the
  window was away cannot leave it stuck on.
- The status bar swaps `Grid 5mm` for `Grid OFF — CTRL vertex snap` while it is held, and
  the InputPoint indicators are drawn so the inference being snapped to is visible.

### Verification
The token pipeline was simulated end to end before shipping, since none of this can be
exercised without SketchUp: pin-then-drag, second-value-moves-to-next-axis, `,1610` naming
an axis explicitly, relative pinning, BKSP release, and confirmation that a bare `350` no
longer touches the other axis. One JS-port artifact surfaced and was dismissed — Ruby's
`tokens[1]` past the end is `nil` and `ApplyToken` returns the live value for it, which JS
does not mirror.

### Files Modified:
1. **`Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — positional resolution, `NamedSlots`
2. **`Na__InsertPrimatives__DrawnToolShared__.rb`** — pin state and helpers, single-token alignment, CTRL tracking and snap bypass, BKSP release, status text
3. **`Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — locked dimension colour and bracket rendering
4. **`Na__InsertPrimatives__DrawnPlaneTool__.rb`** — pin on type, hold for the second axis
5. **`Na__InsertPrimatives__DrawnVolumeTool__.rb`** — same across W/L/D
6. **`Na__InsertPrimatives__DrawnCylinderTool__.rb`** — pin radius and height, CTRL-aware radius snapping
7. **`Na__InsertPrimatives__DrawnRoofTools__.rb`** — pin plan sides and rise

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.11 - 02-Sep-2026 - Longer Segment Suffixes

### Update — "seg" Accepted Alongside "s" for Circle Segments
- `NA_DRAWN_VCB_SEGMENT_PATTERN` widened from `s` only to `(?:segments|segs|seg|s)`, so
  `24s`, `24seg`, `24segs` and `24segments` all set the cylinder segment count.
- Alternation is deliberately longest-first. With `s` leading, `24seg` would match the `s`
  branch and then fail on the leftover `eg` rather than falling through to the longer one.
- Hint text and the file header updated so both forms are discoverable from the tool itself.

### No Change Needed — "d" for Degrees on Roofs
Already supported since v0.4.9: `NA_DRAWN_VCB_ANGLE_PATTERN` is `(?:deg|d|°)`, so `35d`,
`35deg`, `35°`, `+5d`, `-2.5d`, `35 d` and `35D` all read as a pitch. The tool hint text
only advertised `35deg`, which is presumably why it looked missing — the hints and header
now show `35d` first.

### Token Routing Verified
All three token patterns were checked against each other to confirm nothing is swallowed by
the wrong reader: dimensions (`2400`, `2.4m`, `600cm`, `+100`, `-50`) match neither the
segment nor the angle pattern, `24`/`d600`/`600,300` fall through segment matching to
dimension parsing, and `2000mm` is never mistaken for an angle.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — widened segment suffix pattern
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnCylinderTool__.rb`** — hint and header text
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofTools__.rb`** — hint and header text

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.10 - 02-Sep-2026 - Self-Sizing Popup, Extensions Submenu, Hot Reload

### Summary
Housekeeping pass. The right-click popup now sizes itself to its own content, the six
loose Extensions entries collapse into one `Na__InsertPrimitives` submenu, and a
Reload Plugin Data item sits at the bottom of it.

### Update 01 — Popup Sizes Itself
- The dialog height had been a hand-maintained number, and adding the Roof section pushed
  Plane Faces and Exit Primitive Tool off the bottom of the window.
- Rather than bump the number again, the page now measures `document.body.scrollHeight` on
  load and hands it back through a `reportContentHeight` callback, and Ruby calls
  `set_size`. The window ends up exactly as tall as its buttons need plus clear space at
  the base, and it cannot silently clip again the next time an entry is added.
- Opens at a generous fallback height first so there is no clipped flash before the resize
  lands, and body bottom padding went from 12px to 18px.

### Update 02 — One Submenu Instead of Six Loose Entries
- All six tools moved into an `Na__InsertPrimitives` submenu under Extensions, grouped with
  separators: Insert Cube / the three drag tools / the two roofs / the reloader.
- Menu texts shortened now that the submenu carries the namespace — `Drawn Plane` rather
  than `Na__InsertPrimitives__DrawnPlane`.
- Registration switched from `UI.menu('Plugins')` to `UI.menu('Extensions')`, matching the
  house style used by Na__DevTools, Na__EdgeUtil and Noble3d Modelling Tools.

**SHORTCUTS NEED RE-BINDING.** SketchUp keys shortcuts to the menu path, so moving these
entries clears whatever was bound to the old top-level items. The bindings that were in
place before this change:

| Tool | Was |
|---|---|
| Insert Cube | `Ctrl+Alt+O` |
| Drawn Plane | `Ctrl+Alt+P` |
| Drawn Volume | `Ctrl+Alt+V` |

Re-assign once in Preferences → Shortcuts against `Extensions/Na__InsertPrimitives/...`.

### Update 03 — Hot Reload
- New `Na__InsertPrimatives__PluginReloader__.rb`, modelled on the reload managers in
  Noble3d Modelling Tools and Profile Path Tracer: `load` every module file, count what
  worked, report what did not.
- **Loaded separately from the main script, on purpose.** It requires nothing else in the
  plugin, so a module that fails to parse leaves the reloader intact — which is the one
  moment it is actually needed. Loading it through `Main__.rb` would have taken it down
  with everything else.
- `$VERBOSE` is nil-ed around each `load`. These modules define a lot of constants and Ruby
  warns on every redefinition, which would bury the real errors in the report.
- Files load in an explicit priority order, then anything unlisted alphabetically after it,
  so a newly added module still reloads even if nobody remembers to list it. Order matters
  less than it looks — reopening a class or module mutates the object already in memory, so
  an earlier file holding a reference to a later one still ends up with the fresh methods.
- A running tool holds a reference to the class object it was built from, so the reloader
  drops the active tool before reloading — but only when the active tool name marks it as
  one of ours, so an unrelated tool is never stolen.
- Quiet on success (status bar plus console summary), loud on failure (messagebox listing
  each file and error).

### Note — Dead File Found
`Na__InsertPrimatives__ContextMenu__.rb` is a deprecated no-op shim from v0.4.6. Nothing
requires it and the loader never listed it, so it has not been loaded since. It is skipped
by the reloader rather than being counted as a reloaded file. Safe to delete whenever.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__PluginReloader__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — Extensions submenu, shortened menu texts, reload command, separate reloader load
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — content-measured self sizing and extra base padding

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.9 - 02-Sep-2026 - Pitched and Hipped Roof Primitives

### Summary
Two roof tools join the drag family. Drag the plan rectangle on X,Y, then pull up in Z —
or type the pitch in degrees instead of a rise. **Pitched Roof** builds a gable, **Hipped
Roof** builds a hip; both come out as closed solids sitting on the shared voxel grid.

### Update 01 — Plan-Pinned Footprint, TAB Freed for the Ridge
- A roof has no plane decision to make, so the footprint is pinned to plan and the drag
  never infers a plane. The mixin's plane resolution moved behind an overridable
  `na_drawn__resolve_plane_key`; the roof base returns `:xy` and that is the whole change.
- The plane lock stays `:auto`, which matters: it keeps the InputPoint driving the cursor,
  so the footprint corners still snap to existing wall corners and edges rather than being
  projected blindly onto a drawing plane.
- That frees **TAB** for the decision that does matter on a roof — which way the ridge runs.
  Auto puts it along the longer side (right nine times in ten); TAB forces X or Y. The
  status-bar hint is now supplied by `na_drawn__tab_hint` so it tells the truth per tool.

### Update 02 — Ridge and Pitch Maths
- A gable ridge spans the full length at mid-span. A hip pulls each ridge end in by the same
  distance the roof rises over, which is what gives all four planes one pitch; ridge length
  comes out as `along - across`.
- A square plan collapses the two ridge ends onto one apex. Rather than special-casing the
  pyramid, coincident points are deduped out of each face loop, so one set of face
  definitions covers both — the trapezoids simply become triangles.
- Capping the inset at half the length keeps a ridge **forced onto the short side** from
  inverting; it degenerates to a rectangular pyramid instead, and both the status bar and
  the console say so rather than quietly handing back a different roof.

### Update 03 — Pitch Reporting Bug Caught Before Shipping
The maths was checked numerically (a JS port of the ridge, face, pitch and volume
functions) rather than trusted, since there is no Ruby CLI here to exercise it. Planarity,
per-face pitch, negative drags and volume all verified against independent formulas — the
pyramid case reproduces `base × h / 3` exactly, and a 35° round trip through
rise-and-back returns 35.00°.

That check found a real defect. The pitch run was originally `min(across, along) / 2` for
hips, which is correct for every normal hip but reports the **wrong pitch** on the
degenerate short-side case: it quoted 34.99° for a roof whose two large faces were actually
at 25.02°, and a typed `35deg` would have set those faces to 25°. The run is now
`across / 2` for both forms — the main slopes rise over exactly that distance whatever the
inset does, so the reported number always describes the faces you can see. As a bonus the
gable and hip branches collapsed into one line.

### Update 04 — Degrees in the Measurements Box
- A trailing `deg`, `d` or `°` makes a token an angle: `35deg`, `35°`, `35d`. Matched before
  the dimension pattern, which would reject the suffix rather than misread it.
- Relative angles work too — `+5deg` means five degrees steeper than what is on screen,
  because an angle token resolves against the live pitch while a length token resolves
  against the live rise. `+100` and `+5deg` therefore both mean what they look like.
- `6000,4000,35deg` at the plan stage goes straight to a finished roof. The footprint is
  applied before the angle is read, because a pitch is meaningless until the span it is
  measured over is settled.
- Typed pitches clamp to 0.5°–89.5°.

### Update 05 — Preview
- The preview draws the **same face loops the builder will use**, so what is on screen is
  what lands in the model — no second implementation to drift.
- Shaded roof planes in amber over the dashed plan footprint, the ridge picked out as a
  heavy line with the pitch labelled on it, and a summary card carrying plan size, rise,
  pitch and roof-mass volume.
- Roofs are built as closed solids (slopes, ends and a base face). Both forms are convex
  polyhedra, which is what makes the centroid test in `OrientFacesOutward` a correct way to
  turn every face the right way out without an adjacency walk.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofGeometry__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnRoofTools__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — reload list, pitched and hipped roof commands and menu items
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — requires and architecture notes
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`** — `na_drawn__resolve_plane_key` and `na_drawn__tab_hint` hooks, roof mode switching
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — angle tokens
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — convex polygon fill, ridge line, roof summary card
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`** — degrees formatter
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — Roof section with both tools

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.8 - 01-Sep-2026 - Drawn Cylinder (Centre-Anchored)

### Summary
A third drag tool joins Drawn Plane and Drawn Volume. **Drawn Cylinder** takes the same
two-gesture shape as the volume tool — drag the radius, then drag the height — but the
anchor is the **circle centre** rather than a corner, so a column always stands on a
rounded voxel coordinate with the circle growing symmetrically about it.

### Update 01 — Centre Anchoring and Radius Snapping
- The anchor click snaps to the shared voxel lattice exactly as the other tools do; the
  circle is then built around it rather than away from it
  (`Na__DrawnGrid__BuildCirclePoints`).
- **The radius has to be snapped in its own right.** Snapping the cursor to the lattice is
  not enough: the radius is the diagonal between two lattice points, and a diagonal is not
  itself a grid multiple — a 5,5 travel is a 7.07 radius. It goes through
  `Na__DrawnGrid__SnapDistance`, so dragging gives clean 5mm steps and the VCB gives
  anything else.
- Base plane inference, TAB plane locking, step-back and revise-in-place all come free from
  the shared mixin — dragging on the ground gives an upright column, dragging on a wall
  gives one lying on its side.

### Update 02 — One Hook in the Shared Mixin
- `na_drawn__recalculate_sizes` previously wrote width and height inline. The last four
  lines moved into an overridable `na_drawn__apply_planar_travel(u, v)`, which is the only
  change the corner-anchored tools needed.
- The cylinder overrides it to read the same drag travel as a radius, and mirrors that
  radius back into the u/v sizes so every shared validity and extents helper keeps working
  untouched. `na_drawn__preview_points` is overridden too, so the draw extents cover the
  whole circle instead of one quadrant of its bounding box.
- `Na__DrawnGrid__OffsetRectPoints` renamed to `Na__DrawnGrid__OffsetPointsAlongNormal` —
  it now builds the far cap of a cylinder as well as a box, and the old name claimed it
  only handled four rectangle corners.

### Update 03 — Segments
- Circle segment count is a persisted setting (default 24, matching native SketchUp),
  clamped to 3–360, cycled 8/12/16/24/32/48/64/96 from a **Circle Sides** button that
  updates in place in the right-click popup.
- The measurements box takes `24s` as a whole entry at any stage, the way the native Circle
  tool takes a sides count. It is matched before dimension parsing so the trailing `s` is
  never mistaken for a unit suffix. Typed mid-drag the preview re-tessellates live; typed
  after a cylinder is drawn it rebuilds that cylinder.
- Geometry uses `entities.add_circle` rather than a hand-rolled polygon, so the result
  carries real curve metadata — the extrusion comes out softened and smoothed and stays
  editable as a circle rather than as loose segments.

### Update 04 — Radius / Diameter in the VCB
- A bare number is a **radius**, matching the native Circle tool so typed muscle memory
  carries over. A `d` prefix makes it a **diameter** — `d1200` for a 1200 dia column.
- The two compose with the relative arithmetic: `d+100` widens the live *diameter* by 100
  (so the radius moves 50), because with `d` in play the live value a relative entry acts on
  is the diameter. This is why the radius token is resolved by hand rather than through
  `ResolveAgainst`.
- `600,300` at the radius stage goes straight to a finished cylinder, mirroring the volume
  tool's `2400,1200,300`.
- The preview card always shows radius **and** diameter, so there is never any doubt about
  which number the box is holding.

### Update 05 — Cylinder Preview
- Filled circle via a triangle fan from the centre (rather than `GL_POLYGON`, so the fill is
  correct at any segment count), filled walls via a quad strip, blue for the circle stage and
  amber for the extrusion to match the volume tool.
- A dotted radius leader runs centre-to-perimeter with an `R###` label on it; the summary
  card carries dia × H, volume in m³ and the live segment count.
- Only the quarter-point verticals are drawn on the wall. One line per segment would be a
  thicket of 24-plus edges over the live model for no extra information.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnCylinderTool__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — reload list, `Na__InsertPrimitives__DrawnCylinder` command and menu item
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — require and architecture note
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`** — segment settings, circle point builder, circle area / cylinder volume formatters, offset helper rename
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`** — `24s` segment entries and the `d` diameter prefix
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`** — filled circle, filled cylinder, circle and cylinder summary cards
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGeometry__.rb`** — `CreateCylinder` / `RebuildCylinder` / `AddExtrudedCylinder`
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`** — `na_drawn__apply_planar_travel` hook, cylinder mode switching, segment cycling
8. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — Drawn Cylinder entry and Circle Sides cycle

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.7 - 01-Sep-2026 - Drawn Plane + Drawn Volume Click-and-Drag Tools

### Summary
Two new tools sit alongside the existing click-to-place Cube and Plane modes:
**Drawn Plane** sweeps out a rectangle, **Drawn Volume** sweeps out a rectangle and then
its extrusion. Both are Blender-style grid drawing — every pick lands on the shared
voxel lattice, so an anchor corner is always on a rounded grid coordinate and dragged
dimensions are always grid multiples. Shaded coloured previews with live dimension
labels follow the drag, and the measurements box overrides the dragged size at any point
with absolute values or `+`/`-` arithmetic.

### Update 01 — One Voxel Lattice for Every Tool
- New `Na__InsertPrimatives__DrawnGridSnap__.rb` owns the snap lattice, plane-axis maths
  and the settings that persist through `Sketchup.read_default` / `write_default`.
- `round_point_to_nearest_5mm` in `Main__.rb` now **delegates** to `Na__DrawnGrid__SnapPoint`
  rather than keeping its own copy of the rounding maths. A second copy would have drifted
  the moment the snap step or the drawing axes changed, and the whole point of the feature
  is that all four modes share one grid.
- Snapping is now expressed in the **model drawing-axes frame** (the approach already used
  by the EASP measurement tools), so a rotated axes tripod aligned to an angled wall gets a
  grid that follows the wall. With the default axes and a 5mm step the result is bit-for-bit
  what the old world-space rounding produced.
- Snap step is no longer hard-coded: 1 / 5 / 10 / 25 / 50 / 100 mm, cycled from the
  right-click menu, default 5mm, remembered between sessions.

### Update 02 — Drag State Machine (`DrawnToolShared__.rb`)
- `:idle` → `:picking_b` → (`:picking_depth`) with **both** gestures supported, matching the
  native Rectangle tool: a press that travels more than 6px before release completes the
  stage; anything shorter is treated as a click and leaves the stage open for a second click.
- The drawing plane is **inferred from the drag** — the axis the cursor travels least along
  becomes the plane normal. Dragging across a wall gives a vertical plane, dragging across
  the ground gives a horizontal one. A 0.6 ratio hysteresis stops a near-diagonal drag
  flapping between planes.
- TAB cycles an explicit lock: Auto → XY → XZ → YZ. Backspace steps back one stage,
  ESC clears the drag then leaves the tool on a second press.
- Three different cursor sources, each the most predictable one for its stage:
  InputPoint while inferring (with the anchor passed as a reference so axis inference from
  the anchor works in open space), pick-ray-to-plane intersection on a locked plane, and
  pick-ray-projected-onto-the-extrusion-axis for depth. The last one is what keeps depth
  dragging smooth over busy geometry instead of chasing whatever surface is under the cursor.

### Update 03 — Shaded Previews (`DrawnPreviewGraphics__.rb`)
- Built on the EASP measurement overlays: translucent filled face, solid border, green
  crosshair on the anchor.
- Blue for the 2D rectangle, amber for the extruded prism, so the two stages of the volume
  tool read differently at a glance.
- Dimension text sits **beside the shape** — a number on each edge it measures, plus a
  summary card at the far corner carrying W×H and area in m², or W×H×D and volume in m³.
- Labels are drawn with a one-pixel halo so they stay readable against both the white sky
  and dark geometry. Costs 5 `draw_text` calls per line; tune `NA_DRAWN_TEXT_HALO_OFFSETS`
  if that ever shows up in frame times.

### Update 04 — VCB Override with Arithmetic (`DrawnVcbArithmetic__.rb`)
- Absolute `2400`, relative `+100` / `-50`, and empty tokens that keep a dimension:
  `2400,1200` `+100,-50` `1200,` `2.4m,600mm`.
- A **single absolute** value broadcasts to every dimension (square / cube). A **single
  relative** value is applied to each dimension in turn instead, which grows the shape
  without squaring it off — `+100` on a 2400×1200 gives 2500×1300, not a 2500 square.
- Sign always stays with the drag, never with the typed number, so a typed size extends the
  way the drag was already heading.
- The anchor corner is untouched by any of this: it stays on the rounded voxel coordinate
  while the dimensions go wherever they are told. That split is the whole point.
- Parsing deliberately does **not** use `String#to_l`. `to_l` follows model units, so a bare
  `2400` in an imperial model would become 2400 inches; every other input path in this plugin
  documents bare numbers as millimetres and shares `NA_UNIT_CONVERSIONS_TO_MM`, so that
  contract is kept.
- Typing straight after a shape is drawn **corrects that shape in place** rather than leaving
  a wrong one behind (`RebuildPlane` / `RebuildVolume`). Revise mode disarms after 8px of
  deliberate mouse travel — the pixel test rather than a world distance so it is not
  zoom-fragile. Pattern lifted from the Profile Path Tracer VCB engine.
- SketchUp wipes the measurements box once `onUserText` has been handled, so the refreshed
  value is re-pushed from a 0.1s `UI.start_timer`.
- Digit and operator keys arm a typing flag so Backspace mid-entry is a typo fix rather than
  a stage step-back — the same collision the Path Tracer had to solve.

### Update 05 — Four-Mode Right-Click Menu and Mappable Hotkeys
- The popup now covers Cube / Plane / Drawn Plane / Drawn Volume with the running mode
  highlighted, and switches the active SketchUp tool where needed. All tool classes now
  include `Na__InsertPrimatives::PrimitiveModeSwitching` so the popup speaks one interface
  regardless of which tool raised it.
- Snap grid cycles **in place** without closing the popup, so 5mm → 100mm does not need four
  passes through right-click.
- Plane-face preference moved to module level so it survives switching tools and sessions.
- Two new top-level Plugins entries — `Na__InsertPrimitives__DrawnPlane` and
  `Na__InsertPrimitives__DrawnVolume` — each independently mappable in
  Preferences → Shortcuts. The original `Na__InsertPrimitives` entry keeps its exact menu
  text so any shortcut already bound to it still resolves.
- **Menu registration is guarded by `file_loaded?`, so the two new entries only appear after
  a SketchUp restart.** Until then the new tools are reachable from the right-click menu or
  from `Na__InsertPrimatives.Na__InsertPrimatives__DrawPlane` / `__DrawVolume`.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGridSnap__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVcbArithmetic__.rb`**
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPreviewGraphics__.rb`**
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnGeometry__.rb`**
5. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnToolShared__.rb`**
6. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnPlaneTool__.rb`**
7. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DrawnVolumeTool__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`** — reload list, two new commands and menu items
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`** — requires, snap delegation, shared plane-face preference, mode-switch mixin
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`** — four-mode menu, grid cycle, active-mode highlight

### Status: IMPLEMENTED — NOT YET TESTED IN SKETCHUP

# =============================================================================

## Version 0.4.6 - 06-May-2026 - HtmlDialog Primitive Right-Click Menu

### Update — HtmlDialog-Only Right-Click Menu
- Replaced the native/global SketchUp context-menu approach with a dedicated `UI::HtmlDialog` popup triggered from the active primitive tool's right-click callbacks.
- Deprecated `Na__InsertPrimatives__ContextMenu__.rb` as a no-op shim because `UI.add_context_menu_handler` is unreliable for empty viewport space and clutters SketchUp's normal context menu.
- Removed `getMenu`/native menu wiring from `PrimitiveCubeTool`; right-click now uses the popup as the single source of truth for primitive options.
- Popup actions cover cube mode, plane mode, plane face enable/disable, and exiting the tool.

### Files Modified:
1. **`Na__InsertPrimatives__Loader__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__RightClickPopup__.rb`**
4. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__ContextMenu__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.5 - 10-Mar-2026 - Remove Imperial Units

### Update — Metric-Only VCB Input
- Removed `in`, `ft`, `yd` entries from `NA_UNIT_CONVERSIONS_TO_MM` hash.
- Simplified `NA_UNIT_SUFFIX_PATTERN` regex: `(mm|cm|m|in|ft|yd)?` → `(mm|cm|m)?`.
- Updated all comments and user-facing strings to reference `mm | cm | m` only.
- VCB label: `"Cube: single value or X,Y,Z (mm | cm | m | in | ft | yd)"` → `"Cube: single value or X,Y,Z (mm | cm | m)"`.
- Activate console output: `"Units: mm cm m in ft yd"` → `"Units: mm cm m"`.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.4 - 10-Mar-2026 - 4-Step Rotation + Tab Double-Press Fix

### Research Findings — Tab Double-Press
Using `onKeyUp` alone caused Tab to require a double press. Root cause: SketchUp's focus
management consumes the `onKeyUp` event on alternating presses for certain keys (same mechanism
documented for the Alt key in bug report SKEXT-3890). The fix is `onKeyDown` with a
`@key_tab_held` guard that prevents acting on the SKEXT-3890 double-fire and also prevents
acting on typematic repeats. `onKeyUp` is kept solely to reset the held flag.

### Update 01 — Tab Double-Press Fix
- Replaced `onKeyUp`-only handler with `onKeyDown` + `onKeyUp` key-state pattern.
- `@key_tab_held` flag: set to `true` on first `onKeyDown`, reset to `false` on `onKeyUp`.
- `onKeyDown` only acts when `@key_tab_held` is `false` (key transitioning from up → down).
- Suppresses both SKEXT-3890 double-fire and typematic repeats with no timer hacks.

### Update 02 — 4-Step Rotation Cycle
- Replaced boolean `@rotated` toggle with integer `@rotation_step` (0-3, wraps at 4).
- Each Tab press advances one step: 0° → 90° → 180° → 270° → 0°.
- `@last_rotation_state` now stores an integer step (was boolean).
- `Na__Preview__BuildCubeCorners` updated with full 4-case rotation using CCW rotation math.
- `Na__Preview__DrawCubeBox` signature updated to pass `rotation_step`.
- Status bar now shows current degree value: `"Rotation: 90° [TAB to rotate]"`.
- `NA_ROTATION_STEPS = [0, 90, 180, 270]` constant added for display lookup.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__KeyboardHandlers__.rb`**
3. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__3dPreviewGraphics__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.3 - 10-Mar-2026 - Keyboard Handlers Extraction

### Update — Keyboard and VCB Logic Extracted to Dedicated Mixin
- Created `Na__InsertPrimatives__KeyboardHandlers__.rb` as a Ruby mixin module (`module Na__InsertPrimatives::KeyboardHandlers`).
- Included into `PrimitiveCubeTool` via `include Na__InsertPrimatives::KeyboardHandlers`.
- Mixin has full access to the host class instance variables (`@rotated`, `@cube_size_x/y/z`, etc.) at runtime.
- Moved from `Main__.rb` into the mixin:
  - `NA_ROTATION_KEY = 9` constant
  - `onKeyUp` key handler
  - `enableVCB?` callback
  - `onUserText` VCB input handler
  - `na_key__update_status_text` private helper (renamed from `Na__Primitive__UpdateStatusText` to lowercase to avoid Ruby constant-lookup ambiguity when called without `()`)
- `activate` and `resume` in `Main__.rb` updated to call `na_key__update_status_text()`.
- Added `require_relative 'Na__InsertPrimatives__KeyboardHandlers__'` to `Main__.rb`.
- Updated MODULE ARCHITECTURE comment in `Main__.rb` header.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__KeyboardHandlers__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.4.2 - 10-Mar-2026 - Rotation Key: Shift → Tab

### Research Findings
Three reasons Shift rotation never worked:
1. **Wrong constant**: `COPY_MODIFIER_KEY` = Ctrl on PC, not Shift. Shift is `CONSTRAIN_MODIFIER_KEY`. The code never matched a Shift press.
2. **SKEXT-3890 double-fire regression**: `onKeyDown` fires twice per press on Windows since 23.1.340. A toggle would turn on then immediately off. Still open and unresolved as of 2026.
3. **VCB interference**: With `enableVCB?` returning `true`, pressing Shift while typing in the VCB (e.g. uppercase "2M") would trigger the rotation toggle mid-input.

### Fix Applied
- Replaced `onKeyDown` with `onKeyUp`. `onKeyUp` fires exactly once per key release and is unaffected by SKEXT-3890.
- Changed rotation key from `COPY_MODIFIER_KEY` (Ctrl) to Tab (raw key code `9`). The SketchUp Ruby API does not export `VK_TAB`, so the raw integer is used.
- Tab does not send characters to the VCB, is unassigned by default, and eliminates all three issues.
- Added `NA_ROTATION_KEY = 9` class constant inside `PrimitiveCubeTool` for readability.
- Updated all user-facing hint text: `"SHIFT to rotate"` → `"TAB to rotate"`.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.2.4 - 10-Mar-2026 - Preview Graphics Extraction + Visual Tweaks

### Update 01 — Extract Rendering to Dedicated Module
- Created `Na__InsertPrimatives__3dPreviewGraphics__.rb`.
- Moved `Na__Primitive__DrawCrosshair` → `Na__Preview__DrawCrosshair(view, cursor_pos, arm_size)` (stateless, parameters only).
- Moved `Na__Primitive__BuildCubeCorners` → `Na__Preview__BuildCubeCorners(origin, sx, sy, rotated)` (stateless, parameters only).
- Moved `Na__Primitive__DrawCubePreview` → `Na__Preview__DrawCubeBox(view, origin, sx, sy, sz, rotated)` (stateless, parameters only).
- `Na__Preview__BuildCubeCorners` is now shared by both the preview renderer and the geometry engine (`CreateCubeGeometry`, `RegenerateCube`).
- `Main__.rb` `draw` method delegates entirely to the graphics module; no rendering logic remains in the tool class.
- Added `require_relative 'Na__InsertPrimatives__3dPreviewGraphics__'` to `Main__.rb`.
- Updated module architecture comment in `Main__.rb` header.

### Update 02 — Preview Box Visual Tweaks
- Line width: `1` → `2` (thicker).
- Colour: `Color(0, 220, 255, 180)` → `Color(0, 160, 200, 210)` (darker teal, slightly more opaque).

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__3dPreviewGraphics__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================

## Version 0.2.3 - 10-Mar-2026 - Rotation Toggle + VCB Single-Value

### Update 01 — Shift-Key 90° Z-Rotation Toggle
- Added `@rotated` and `@last_rotation_state` instance variables to `PrimitiveCubeTool`.
- Added `onKeyDown` handler: pressing Shift toggles `@rotated` between `false` (0°) and `true` (90° CCW around Z).
- Added `Na__Primitive__UpdateStatusText` private helper — keeps the status bar in sync with rotation state; called from `activate`, `resume`, and `onKeyDown`.
- Added `Na__Primitive__BuildCubeCorners(origin, rotated)` private helper — single source of truth for all corner geometry. When `rotated` is `true`, the +X axis maps to +Y and +Y maps to −X (90° CCW).
- Refactored `Na__Primitive__DrawCubePreview`, `Na__Primitive__CreateCubeGeometry`, and `Na__Primitive__RegenerateCube` to all delegate corner calculation to `Na__Primitive__BuildCubeCorners`.
- `@last_rotation_state` is stored at placement time so VCB-triggered regeneration rebuilds the cube with the same orientation it was originally placed in.
- Live preview wireframe reflects rotation in real-time as user toggles.

### Update 02 — VCB Single-Value Broadcast
- Updated `Na__VcbInput__ParseDimensions` to accept 1 token or 3 tokens.
  - 1 token: value is broadcast to all three dimensions (e.g. `"1m"` → 1000mm × 1000mm × 1000mm).
  - 3 tokens: unchanged X,Y,Z behaviour.
  - Any other count raises `ArgumentError` with a clear message.
- Updated VCB label to `"Cube: single value or X,Y,Z (mm | cm | m | in | ft | yd)"`.
- Updated file header comment in `VcbFunctions__.rb` to document single-value mode.

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**
2. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**

### Status: IMPLEMENTED

# =============================================================================
## Version 0.2.2 - 10-Mar-2026 - Preview + VCB Multi-Unit Support

### Update 01 — 3D Ghost Cube Preview
- Added `Na__Primitive__DrawCubePreview` private method to `PrimitiveCubeTool`.
- Draws a dashed cyan wireframe box at the snapped cursor position in real-time using `view.draw(GL_LINES, edge_points)`.
- Preview dimensions reflect the current `@cube_size_x/y/z` stored in the tool, updating immediately after VCB input.
- Crosshair drawing extracted into `Na__Primitive__DrawCrosshair` private method to keep `draw` clean.

### Update 02 — VCB Multi-Unit Input Module
- Created `Na__InsertPrimatives__UserInput__VcbFunctions__.rb` loaded via `require_relative` from `Main__.rb`.
- Unit conversion constants: `NA_UNIT_CONVERSIONS_TO_MM` (mm, cm, m, in, ft, yd).
- `Na__VcbInput__ParseSingleDimension(str)` — parses a single token with optional unit suffix; bare numbers default to mm.
- `Na__VcbInput__ParseDimensions(text)` — splits comma-separated input, delegates each token to `ParseSingleDimension`, returns `[x, y, z]` in SketchUp internal lengths.
- `Na__VcbInput__UpdateDisplay(x, y, z)` — sets VCB value and updates label to `"Cube X,Y,Z (mm | cm | m | in | ft | yd)"`.
- `onUserText` in `PrimitiveCubeTool` refactored to call `Na__VcbInput__ParseDimensions`; error messages surface the `ArgumentError` message directly.
- `update_vcb_display` instance method removed; all display calls now go through `Na__VcbInput__UpdateDisplay`.
- Private geometry helpers renamed to `Na__Primitive__*` convention: `Na__Primitive__CreateCubeGeometry`, `Na__Primitive__RegenerateCube`.

### Files Added:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__UserInput__VcbFunctions__.rb`**

### Files Modified:
1. **`Na__InsertPrimatives__Modules__/Na__InsertPrimatives__Main__.rb`**

### Status: IMPLEMENTED

# =============================================================================
## Version 0.2.0 - 10-Mar-2026 - Plugin Modularisation

### Update 01 - Restructure into Loader + Modules Pattern
- Migrated from a single flat file to a loader + modules subdirectory architecture.
- Pattern mirrors the `Na__WindowConfiguratorTool` structure for consistency.
- The plugins root now contains only the loader; all logic lives under the modules folder.
- Future features can be added as individual `.rb` files inside the modules folder and loaded via `require_relative` in `Main__.rb`.

### Files Added:
1. **`Na__InsertPrimatives__Loader__.rb`** (plugins root)
   - Handles path setup, `require` of `Main__.rb`, `UI::Command` creation, and Plugins menu registration.
   - Guards against double-loading with `file_loaded?` / `file_loaded`.
2. **`Na__InsertPrimatives__Modules__\Na__InsertPrimatives__Main__.rb`**
   - Contains `Na__InsertPrimatives` module, `PrimitiveCubeTool` class, grid-snapping helper, and `Na__InsertPrimatives__InsertCube` entry point.
   - No startup wiring — all UI registration delegated to the loader.

### Files Removed:
1. **`Na__InsertPrimatives__Main__.rb`** (plugins root)
   - Deleted; replaced by the loader + modules structure above.

### Status: IMPLEMENTED

# =============================================================================
