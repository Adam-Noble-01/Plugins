# Array Builder: nested axes and preview coordinates

Updated 16 September 2026 for version 0.3.

This applies the established Noble coordinate-space findings from
[Insert Primatives 5.1.2, “Stacked Local Axes”](../../Na__InsertPrimatives__Modules__/Na__InsertPrimatives__DEVLOG__.md)
and [Noble 3D Modelling Tools, OrthoMirror 1.2.1](../../Na__Noble3dModellingTools__Modules__/Na__Noble3dModellingTools__DEVLOG__.md).
Those logs contain the earlier investigation into the displaced nested previews.

## The boundary that matters

SketchUp reports positions in the active drawing context and its open ancestors in
world coordinates. Geometry inside other, closed definitions reports local
coordinates. The number of nesting levels alone does not tell you which transform
to apply. Record which space each value already occupies.

| Data | Reported / expected space | Array Builder handling |
| --- | --- | --- |
| `InputPoint#position` | World | Keep unchanged for a new path |
| Selected vertices in `active_entities` | World | Keep unchanged, just like drawn points |
| `View#draw` and `View#screen_coords` points | World | Never append `edit_transform` to world points |
| Selected array directly in active entities | Its reported placement maps its closed definition to world | Use the instance transformation once |
| Source faces inside a closed component definition | Definition local | Accumulate closed child transforms, parent first |
| New private array definition | Definition local | Subtract the chosen world origin before saving path points |

Do not prefix `model.edit_transform` to an `InputPoint`, an active selected vertex,
or a transformation that already maps a closed child into the reported active
world context. Do not “fix” that error by applying its inverse during drawing.
Two erroneous conversions may cancel at one depth and compound at the next.

## A new array

1. Both path tools provide world points `P_world`.
2. Choose the first point as the array origin `O_world`.
3. Save `P_array = P_world - O_world` in the new, closed definition's recipe.
4. Populate that definition with array-local placement matrices.
5. Insert its instance into active entities using `T_origin = translation(O_world)`.

The active-context insertion API consumes that world placement. Applying an
extra inverse parent transform here makes the created array disagree with the
preview. This is tested for both the drawn and selected-path entry points with a
non-identity parent frame in the isolated suite, and covered by the native smoke
script for actual SketchUp API behaviour.

## Redrawing a moved array

The existing array is a closed instance directly inside the active entities.
Its reported transform is `T_array_to_world`.

```text
P_array = inverse(T_array_to_world) * P_world
P_preview_world = T_array_to_world * T_unit * P_source
```

Use that same inverse when committing the replacement path. Stored recipes stay
definition-local, so moving or rotating an array does not rewrite its path. A
linked definition can regenerate all its copies without changing their placement.

## Nested custom sources

The picked source definition is closed. A source may contain a component that
contains another group and then a face. Start at identity and walk only this
closed subtree:

```text
T_accumulated_child = T_accumulated_parent * T_child
P_source = T_accumulated_child * P_face_local
P_array = T_unit * P_source
P_world = T_array_to_world * P_array  # existing-array redraw only
```

Matrix order is significant. Parent-first multiplication also preserves nested
rotation, scaling and mirroring inside the source. The selected source's outer
scale follows the existing registry convention (axis magnitudes). Its local axes
remain the array orientation reference. No `active_path` transforms are prefixed
to this source walk. Open contexts and closed definition subtrees are different
API cases.

`PreviewGeometry` caches the resulting source mesh, then instances it with
`LayoutEngine.Na__Layout__Transform`, the same transform used by `GeometryBuilder`.
World draw batches are prepared after a 120 ms pause; the draw callback only draws
cached faces and edges. No temporary groups, definitions or Undo operations are
created for preview. Preview extents include the actual geometry and offsets.

## HTML graphics

Ruby obtains triangles using [`Face#mesh(0)`](https://ruby.sketchup.com/Sketchup/Face.html#mesh-instance_method),
preserves visible edges and material colours, and sends one source mesh plus
column-major 4×4 placement matrices as JSON through `HtmlDialog#execute_script`.
Both mesh coordinates and matrix translations are in SketchUp inches.

The JavaScript preview applies each matrix, projects the resulting 3D points into
an isometric 2D view, sorts triangles by depth, shades them from their normals,
and draws polygons and paths in SVG. It uses no Three.js, Babylon.js, WebGL or
third-party graphics library. SVG is resolution-independent and fits this small
fixed-view preview well. It is a lightweight illustration renderer, with material
colours rather than texture maps or photorealistic lighting. Native viewport
preview uses SketchUp `View#draw` with `GL_TRIANGLES` and `GL_LINES`.

Heavy arrays show a labelled subset of complete source instances, within separate
native and HTML mesh budgets. Build count and saved geometry remain complete.
Gallery thumbnails remain parameter-based illustrations. Corner unions run when
geometry is created or live-updated; pre-build previews show the constituent units.

## Virtual inference from the start point

PathInference works on the same WORLD points as InputPoint and the drawn preview.
It intersects a line through the last committed point with candidate lines through
the first point. Candidates include world axes and directions from the drawn
path's rotated plane. Parallel/skew 3D lines are rejected; an explicit arrow-key
lock restricts the travelling line. No active-context parent transform is added.

Acquisition uses `View#screen_coords` with a 12 logical-pixel radius and an 18-pixel
release radius for an existing snap. Mouse-move and click call the same resolver.
The exact inferred position seeds the next InputPoint, without 1 mm grid rounding.
The dashed guide, endpoint marker, preview and final vertex therefore share one
position. Clicking the highlighted start after at least three committed points
appends that exact first point and finishes the closed path. These virtual guides
do not add construction points or edges to the model.

## Regression cases

- Three translated, rotated and scaled closed source levels: accumulate each once.
- Draw and select paths while editing three transformed nested groups.
- Pick a source with an offset origin; compare first preview and built vertices.
- Move/rotate a saved array, redraw it, and compare world path endpoints.
- Change active context during a pending preview: old session work is discarded.
- Change the source geometry and Undo/Redo: mesh caches invalidate.
- Negative margins and offsets: clipping extents include outward geometry.

See [validation instructions](../65__Dev__Tests/Na__ArrayBuilder__Validation__.md).
