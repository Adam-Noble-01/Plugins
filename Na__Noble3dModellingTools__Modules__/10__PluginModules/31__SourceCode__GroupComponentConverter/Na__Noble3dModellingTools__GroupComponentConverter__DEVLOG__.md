# Na Noble3d Modelling Tools - Group / Component Converter - Development Log
# =============================================================================
# Module : 31__SourceCode__GroupComponentConverter
# Plugin : Na Noble3d Modelling Tools
# Tab    : Entity Utils > Component Containers

## Overview

Converts groups to components or components to groups from one dedicated
HtmlDialog. Two switches drive it:

- **Direction** - Groups -> Components | Components -> Groups
- **Reach**     - Current Level Only | Deep Nesting

Deep Nesting reaches every child and grandchild container below the selection
as well as the top level. The dialog reports how many groups and components
sit at each nested level, and states exactly how many will convert, from what
to what, before anything changes. The whole run is one SketchUp Undo step.

Replaces two single-shot Entity Utils buttons, retired in the same release:
**Convert Components To Groups** (module 05) and **Groups To Component**
(module 17).

**Common groups become one shared component** turns groups with the same
geometry - however they are moved or rotated - into instances of one
component, so editing one edits them all. New definitions are named
`__Common` when shared and `__Unique` when single.

Parent entries: main devlog **Version 0.8.8** (1.0.0) and **Version 0.8.9**
(1.0.1), both 11-Sep-2026.

# =============================================================================
# VERSION HISTORY
# =============================================================================


## Version 1.0.1 - 11-Sep-2026 - Common Groups Share One Component

### Update 01 - Reported: 22 Identical Groups Became 22 Components
- First live run: 22 identical groups converted into 22 separate component
  definitions, so editing one did nothing to the other 21.
- Not a fault in 1.0.0's rules, but a gap in them. **Group copies become one
  shared component** only joins groups that still share one definition. These
  22 each had their own, so nothing tied them together. **Also merge identical
  groups** also required matching local axes, so a group copied then moved or
  rotated inside its own axes never matched.

### Update 02 - New Toggle: Common Groups Become One Shared Component
- Off by default. Groups with the same geometry become instances of one
  component, however they are moved or rotated, and every placement edits as
  one - standard SketchUp component behaviour.
- Candidates are found the Select Similar way, by a signature that ignores
  position and rotation. Unlike Select Similar's size test, a candidate must
  then pass a full check before it merges, because merging *replaces*
  geometry.
- New `ShapeMatcher__.rb`. It reads each definition once into a plain-value
  record: vertices with their edge counts, edge midpoints and flags, face
  centroids / normals / areas / paint / tag, nested placements. It keys the
  record on counts, total area, total edge length, spread about the centroid,
  and material, tag and nested tallies.
- Registration tries the pure translation between centroids first. It then
  builds frames from the centroid, the rarest far point and the rarest
  off-axis point (rarity by distance and edge count), and tries each candidate
  frame in the other group.
- A move is accepted only when every vertex, edge, face (normal, area,
  materials, tag, hidden) and nested placement lands within 0.002" (about
  0.05 mm). Only proper rotations are produced, so a mirrored copy of a
  handed shape stays separate. A shape with a mirror plane matches its mirror
  image by a rotation, and that is correct.
- A merged group becomes an instance at `group.transformation * offset`, so
  the shared component sits exactly where each group was.
- Includes group copies. The **Group copies** toggle greys out while it is
  on. The **Also merge identical groups** toggle from 1.0.0 is removed; the
  new toggle does everything it did, plus moved and rotated copies.
- Prototyped in Python before the port: 61 synthetic checks. Rotated and
  moved copies register with an offset equal to the ground truth. Mirrored
  and face-reversed copies of handed shapes are rejected. A UV sphere and a
  3,721-vertex grid each resolve on the first candidate frame.

### Update 03 - __Common and __Unique Naming
- Every definition made by Groups -> Components is named last, once its
  group count is known: `<group name>__Common` when two or more groups share
  it, `<group name>__Unique` when one group has it alone. Unnamed groups use
  `Component`. Clashes take SketchUp's usual `#1`, `#2` counter.
- Applies whatever the toggles are set to, so with Common groups off every
  new definition reads `__Unique`.
- Components -> Groups takes a trailing `__Common` / `__Unique` (and its
  counter) off a definition name before naming the group, so a round trip
  does not stack suffixes.

### Update 04 - One Registry for Preview and Conversion
- `MergeKeys__.rb` is replaced by `MergeRegistry__.rb`: Lookup, Register,
  AddMember and Summary over the three modes (none, copies, common). The
  scanner and the converter drive their own registries in the same walk
  order, so the preview's `__Common` / `__Unique` counts are the ones the
  conversion makes.
- The live preview caps common matching at 400,000 work units. Past that it
  says so and reads the `__Common` count as possibly low; the conversion
  itself is uncapped.

### Validation Checklist
- [x] UiBridge.js passes `node --check`; every module file is ASCII.
- [x] Ruby block balance 0 on all ten files; called-vs-defined and
      bare-capitalised-call checks clean; no stale references to the removed
      toggle or MergeKeys.
- [x] Headless run of the dialog script against a stubbed DOM: Common on
      reads "1 __Common, shared by 22 groups"; off reads "22 ... each named
      __Unique"; the copies row greys out and returns; Components -> Groups
      hides the group options.
- [ ] Reload Plugin Data, then the 22-group case: preview and result both
      show one `__Common` definition; open one and edit - all 22 follow.
- [ ] Rotated and moved copies land exactly where each group was.
- [ ] A mirrored copy of a handed shape stays `__Unique`.
- [ ] Common groups off: every new definition is named `__Unique`.

### Status
**Written and statically verified; not yet exercised in SketchUp.**

# =============================================================================

## Version 1.0.0 - 11-Sep-2026 - First Release

### Update 01 - One Dialog, Two Switches
- Direction and reach are segmented switches at the top of the dialog; the
  choice persists through `Sketchup.write_default`. First run opens on
  Groups -> Components, Current Level Only.
- Every scan simulates both directions at both reaches, so flipping a switch
  redraws instantly from data already in the dialog. Toggles change the plan
  itself, so they post back and trigger a rescan.
- Live selection observer, deferred through a zero-delay timer, detached for
  the conversion and reattached after - the Mega Explode pattern.

### Update 02 - Nesting Report and Conversion Preview
- Tiles for groups, components and levels deep; top-level vs nested counts,
  component definitions, locked containers; a per-level breakdown table with
  the levels the current reach will touch highlighted.
- A **Will Convert** card with the exact count, `from -> to`, and the split
  between the current level and nested levels.
- Notes cover locked skips, empty components, merged group copies, shared
  definitions edited in place, glue / cut-opening loss and file growth.
- Preview walks stop at 50,000 containers; the conversion is never capped by
  the preview.

### Update 03 - Groups -> Components
- `Group#to_component` deletes the group and drops its instance name and lock
  (confirmed against tt_selection_toys' `convert_group_copies_to_components`),
  so both are captured first and re-applied with tag, material, hidden,
  shadows and every top-level attribute dictionary.
- A group whose definition is shared with other group copies is made unique
  before conversion, so a copy outside the selection can never flip too.
- **Group copies become one shared component** (on by default): copies that
  still share a definition become instances of the first copy's new
  component at their own transformation. Exact by construction.
- **Also merge identical groups** (off by default): groups made unique since
  copying still merge when a local fingerprint matches - face / edge / vertex
  counts, area, local bounds, material and tag tallies, nested placements.
  This is what the old Groups To Component tool did with its picker, without
  its failure mode: that tool compared bounds *sizes* only, so a group drawn
  with a different local origin was replaced at the wrong position.
- The new definition is named after the group; an unnamed group gets
  SketchUp's `Component` name rather than `Group#N`. The instance keeps the
  group's name.
- Deep Nesting walks each component definition once. A group inside a shared
  component converts once and every placement follows - SketchUp's own edit
  semantics - and the dialog warns how many placements sit outside the
  selection.

### Update 04 - Components -> Groups
- A new group takes the instance's transformation, a temporary instance is
  exploded inside it at identity, then the instance is erased. The component's
  own axes survive, unlike explode-then-regroup.
- The group takes the instance name, or the definition name when unnamed, so
  a Groups -> Components -> Groups round trip keeps its names.
- Deep Nesting walks the new group's private copy. Existing groups on the way
  are made unique first, and only when a component sits somewhere below them,
  so plain group copies are not split for nothing.
- Empty components are skipped: an empty group would be discarded by
  SketchUp at commit.

### Update 05 - Locked Containers
- **Include locked containers** is off by default: locked groups and
  components are skipped with everything inside. On, they are unlocked,
  converted and relocked; a failed conversion restores the original's lock.

### Known Limitations
- Glue and cut-opening behaviour cannot survive Components -> Groups; the
  dialog warns before converting.
- Definition-level attributes (classification, descriptions) stay on the
  source definition; only instance-level dictionaries are carried across.
- Editing inside an open group copy relies on SketchUp having made that copy
  unique on entry, as its own editor does.

### Validation Checklist
- [x] UiBridge.js passes `node --check`.
- [ ] Dialog opens from Entity Utils > Component Containers; search finds "convert".
- [ ] Switch flips redraw instantly; toggles rescan.
- [ ] Preview count equals the result count for each direction and reach.
- [ ] Group copies merge into one component; unmerged groups get their own.
- [ ] Components -> Groups keeps axes, names, tags and materials.
- [ ] Locked skipped with the toggle off; converted and relocked with it on.
- [ ] One undo reverses the whole run.

### Status
**Written and statically verified; not yet exercised in SketchUp.**

# =============================================================================
# END OF FILE
# =============================================================================
