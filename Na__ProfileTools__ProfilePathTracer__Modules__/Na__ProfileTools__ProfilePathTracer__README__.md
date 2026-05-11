# Na__ProfileTools__ProfilePathTracer

## Overview

`Na__ProfileTools__ProfilePathTracer` is a new SketchUp plugin scaffold in the Noble Architecture ecosystem.

The target product is your own profile tracing system inspired by Profile Builder workflows, but designed around:
- your naming conventions and modular architecture;
- ecosystem reuse by other plugins;
- both interactive HtmlDialog usage and headless API execution.

The plugin now includes a full interactive drawing workflow with live viewport feedback.

## Project Intent

- Build profile objects along user-selected paths or interactive free-draw paths.
- Provide reusable functions for other Noble Architecture plugins.
- Support automated headless runs (batch and script-driven).
- Keep all modules cleanly separated and easy to evolve.

## Modes

- **Interactive Mode (HtmlDialog):**
  - Profile source selection (library or strict scene pick).
  - Path mode selection (selection-based or free-draw interactive).
  - Free-draw waypoints in SketchUp viewport with live profile sweep preview.
  - Arrow-key axis lock constraints and TAB rotation for profile orientation.
  - Preview + action callbacks.

- **Headless Mode (API):**
  - Trigger from Ruby or other plugins.
  - Pass config hash/payload.
  - Return structured result for workflow chaining.

## Dependency Contract

This plugin follows ecosystem-level dependency rules:

- **Common Plugin Dependencies**
  - Path root: `../Na__Common__PluginDependencies`
  - Purpose: shared icons/branding assets.
  - Resolver module: `Na__ProfileTools__ProfilePathTracer__AssetResolver__.rb`

- **Common DataLib Core Standards**
  - Path root: `../Na__Common__DataLib__CoreSuEntityStandards`
  - Loader call pattern: `Na__DataLib__CacheData.Na__Cache__LoadData(...)`
  - Initial keys preloaded: `:tags`, `:materials`, `:edge_materials`
  - Bootstrap module: `Na__ProfileTools__ProfilePathTracer__DependencyBootstrap__.rb`

## Main Files

- Loader:
  - `../Na__ProfileTools__ProfilePathTracer__Loader__.rb`
- Orchestrator:
  - `Na__ProfileTools__ProfilePathTracer__Main__.rb`
- HtmlDialog:
  - `Na__ProfileTools__ProfilePathTracer__UiLayout__.html`
  - `Na__ProfileTools__ProfilePathTracer__UiLogic__.js`
  - `Na__ProfileTools__ProfilePathTracer__UiEventToRubyApiBridge__.js`

## Notes

- Scene profile source requires exactly one top-level planar face in the picked Group/Component.
- The plugin keeps compatibility with selection-based path generation while prioritising interactive drawing mode.

## Unified Profile Schema (Current)

`Na__ProfileTools__ProfilePathTracer` now uses one authoritative JSON contract for save/load/scene source:

- Required root blocks:
  - `meta`
  - `Na__Asset__Metadata`
  - `Na__Asset__Profile2D`
  - `Na__Asset__Mesh3D`
- `Na__Asset__Profile2D` stores profile section geometry:
  - `Na__Geometry__Vertices` (`VertexId`, `PosY_mm`, `PosZ_mm`)
  - `Na__Geometry__Edges` (`EdgeId`, `StartVertex`, `EndVertex`)
  - `Na__Geometry__Faces` (`FaceId`, `OuterLoopVertices`)
- `Na__Asset__Mesh3D.Na__Geometry__Edges` stores style fidelity:
  - `EdgeId`, `StartVertex`, `EndVertex`
  - `IsSoft`, `IsSmooth`, `IsHidden`, `CastsShadows`
  - plus edge colour extension:
    - `EdgeMaterialName`
    - `EdgeColourId`
    - `EdgeColourHex`

Legacy `polyline2d` and legacy `meta/vertices/edges/faces` root files are rejected.

## Origin Helper Save Flow

When saving a profile:

1. Selection is validated.
2. User is prompted to click a UCS/origin point in the model viewport.
3. Export runs using that clicked point as local origin.
4. A persistent `00__OriginPoint` crosshair helper is created at the clicked location.
5. Helper is assigned to tag `02__DoorHelpers__RotationPivots`.
6. Helper edges are painted with `MTE201__LineColour__Red` (DataLib-backed).

## Roundtrip Validation Steps

Use SketchUp Ruby Console to validate state roundtrip (export -> load -> regenerate):

1. Select path edges in the model (optional for full generation check).
2. Run:

```ruby
result = Na__ProfileTools__ProfilePathTracer.Na__PublicApi__RunRoundtripValidation('YOUR_PROFILE_KEY')
puts result
```

3. Inspect:
   - `sourceStats` (from saved unified JSON mesh edges)
   - `generatedStats` (from regenerated group edges)
   - `comparison` (`softDelta`, `smoothDelta`, `hiddenDelta`, `colouredDelta`)
