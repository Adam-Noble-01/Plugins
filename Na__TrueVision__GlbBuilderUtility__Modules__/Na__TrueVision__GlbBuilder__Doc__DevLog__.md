# GLB Builder Utility - Development Log

**Main File:** [`Na__TrueVision__WhitecardModel__GlbBuilderUtility__Main__.rb`](../Na__TrueVision__WhitecardModel__GlbBuilderUtility__Main__.rb)

---


## Version History

# ---------------------------------------------------------
### GLB Builder Utility - Version 2.0.0 - 12-Mar-2026
#### Material & Texture Export Overhaul

- **Texture embedding in GLB binary**: New `Na__TrueVision__GlbBuilder__EngineCore__TextureHandling__.rb` module extracts colorized textures from SketchUp materials via `texture.write(path, true)`, packs PNG binary data into the GLB buffer, and creates the full glTF chain (image -> sampler -> texture -> baseColorTexture). Textures are cached per-material to avoid re-processing duplicates.
- **Face-only material resolution**: `Na__GlbEngine__ResolveEffectiveFaceMaterial` now returns only `face.material || face.back_material`. The `inherited_material` parameter has been removed from `TraverseEntities`, `AddFaceToBucket`, and `ResolveEffectiveFaceMaterial`. Group/component container materials are no longer inherited by child faces — unpainted faces resolve to the default whitecard material.
- **MAT000E__ "Material Exempt" prefix**: New `EXEMPT_MATERIAL_REGEX = /^MAT000E__/` in MaterialLookupSystem. In `:indexed_only` mode, materials matching the exempt prefix are included in the export alongside standard indexed materials (MAT###__). Exempt materials retain their SketchUp color and texture but do not receive PBR enrichment from the library.
- **bin_buffer propagation**: `Na__MaterialEngine__EnsureMaterialRegistered` and `Na__MaterialEngine__ResolveMaterialIndexForGroup` now accept an optional `bin_buffer` parameter for texture embedding. All callers in GeometryHandling, ComponentInstancing, and DoorObjectHandling updated to pass `bin_buffer` through.
- **Texture optimization checkbox re-enabled**: UI checkbox for "Optimize Large Textures" is now functional. When checked, textures exceeding `MAX_TEXTURE_SIZE` (1024px) are downscaled via ImageRep.
- **Export Materials checkbox defaults to checked**: UI now defaults to exporting materials with the indexed-only sub-option visible immediately.
- **Component instancing simplified**: `Na__Instancing__RecursiveScan` no longer tracks `inherited_material`. All ComponentInstances are eligible for shared-mesh instancing regardless of container material, since face-only resolution makes container materials irrelevant.
- **Texture cache lifecycle**: Texture cache folder is created at export start and cleaned up after export completes. TextureEngine state is reset at the beginning of each `PrepareMaterialsForExport` call.

**Files Created:**
- `Na__TrueVision__GlbBuilder__EngineCore__TextureHandling__.rb`

**Files Modified:**
- `Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__.rb` (texture integration, exempt prefix, bin_buffer param)
- `Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__.rb` (EXEMPT_MATERIAL_REGEX, IsExemptMaterial?)
- `Na__TrueVision__GlbBuilder__EngineCore__GeometryHandling__.rb` (face-only materials, bin_buffer passthrough)
- `Na__TrueVision__GlbBuilder__EngineCore__ComponentInstancing__.rb` (removed inherited_material, bin_buffer passthrough)
- `Na__TrueVision__GlbBuilder__SpecialObject__DoorObjectHandling__.rb` (removed inherited_material, bin_buffer passthrough)
- `Na__TrueVision__GlbBuilder__UserInterface__.rb` (UI defaults, texture checkbox, downscaleTextures param)
- `Na__TrueVision__GlbBuilder__Main__.rb` (require_relative TextureHandling)
- `Na__TrueVision__GlbBuilder__CoreExport__.rb` (texture cache lifecycle re-enabled)
# ---------------------------------------------------------

# ---------------------------------------------------------
### TrueVision3D App - Door Animation v1.2.0 - 06-Mar-2026
- **Negative rotation degree support**: MOD object names now accept a leading `-` on the degree value (e.g. `MOD001__ROT__-90-Deg__DoorPanel`). This reverses the swing direction, allowing left-hand and right-hand doors to be modelled correctly without mirroring the hinge geometry.
- **No plugin changes required**: The GLB Builder already exports MOD node names verbatim; a name such as `MOD001__ROT__-90-Deg__DoorPanel` is written into the GLB unchanged and is valid in SketchUp.
- **App changes** (`3dObjectIInteraction__Animation__ClickToOpenDoors__.js`):
  - Regex updated: `/(\d+)-Deg/i` → `/(-?\d+)-Deg/i` to capture the optional minus sign.
  - Validation guard updated: `degrees > 0` → `degrees !== 0` to permit negative values while still rejecting zero.
  - Downstream animation logic (`ApplyPivotRotation`) was already sign-agnostic — a negative `angleRad` passed to `THREE.Quaternion.setFromAxisAngle` naturally rotates in the opposite direction with no further changes needed.
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.9.3 - 05-Mar-2026
- **Inherited material propagation for mesh export**: `Na__GlbEngine__TraverseEntities` and `Na__GlbEngine__AddFaceToBucket` now carry an optional inherited material so explicit face paint still wins, but unpainted faces can inherit the nearest painted parent group/component material.
- **Effective face material rule**: Added `Na__GlbEngine__ResolveEffectiveFaceMaterial(face, inherited_material)` with the resolution order `face.material || face.back_material || inherited_material`. This preserves indexed materials such as `MAT101__Glass__ClearDefault` even when geometry is nested inside painted containers.
- **Door material parity with all other mesh exports**: Door child/direct mesh extraction now passes inherited material through the same geometry traversal path, and door mesh build no longer uses a door-specific material registration branch. Door meshes now resolve material indices through the same shared `Na__MaterialEngine__ResolveMaterialIndexForGroup(..., gltf)` path as flat and instanced mesh exports.
- **Instancing correctness over deduplication for painted containers**: `Na__Instancing__RecursiveScan` now tracks inherited material during scan. Component instances carrying inherited material are left on the normal flattening path instead of being claimed by shared-mesh instancing, preventing per-instance container materials from being lost in the exported GLB.
- **Unified indexed material application path**: Flat geometry, doors, and instanced meshes now all flow through the shared MaterialEngine entry point. If an indexed material exists in the library, the same lookup/enrichment rules apply regardless of object type; door/object-specific modules remain responsible only for hierarchy, transforms, and interaction metadata.
- **Result**: Indexed materials such as `MAT101__Glass__ClearDefault` now preserve their exact material identity more reliably across nesting, door assemblies, and repeated component workflows, while keeping one consistent library-driven PBR material pipeline for all mesh models.
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.9.2 - 05-Mar-2026
- **Recursive ignore for technical 02 linework tags**: Added a global always-excluded tag list for `02__Linetype__DoorSwings` and `02__ClearanceLines`.
- **Nesting-safe exclusion behavior**: The two tags are now injected into `@excluded_layers` during exclusion scan, so existing recursive checks in mesh, linework, instancing, storey, and door handling paths automatically skip them at any depth.
- **Documentation alignment**: README now explicitly states this nesting exception to avoid ambiguity with top-level tag range segmentation.
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.9.1 - 28-Feb-2026
- **Linework alignment fix for instanced components**: `BuildSharedLinework` now mirrors `BuildSharedMesh` exactly — uses the same `local_root` transform calculation (including mirrored partition handling via `MirroredLocalTransform`) instead of hardcoding `Z_UP_TO_Y_UP_MATRIX`. This ensures instanced component linework and mesh GLBs are extracted in identical coordinate space, fixing a spatial offset where linework was shifted relative to mesh geometry.
- **Signature change**: `Na__Instancing__BuildSharedLinework` now accepts `is_mirrored` parameter (matching `BuildSharedMesh`).
- **Linework deduplication key updated**: `ProcessAllInstancedLinework` now caches by `[definition, is_mirrored]` pair instead of `definition` alone, matching the mesh orchestrator's per-partition approach.
- **Root cause**: `BuildSharedMesh` computed `local_root = is_mirrored ? MirroredLocalTransform() : Z_UP_TO_Y_UP_MATRIX` while `BuildSharedLinework` always used `Z_UP_TO_Y_UP_MATRIX`. The mismatch meant linework geometry was extracted in a different coordinate space than the mesh geometry for the same instanced definition, causing the per-instance node transform to place linework at an offset position.
# ---------------------------------------------------------

# ---------------------------------------------------------
## GLB Builder Utility v1.9.0  -  28-Feb-2026
### Component Instancing — 449 MB → 1 MB GLB Export Optimisation

**This entry documents an upstream SketchUp plugin change that directly benefits TrueVision3D load times and runtime performance. No TrueVision app code changes were required.**

**Result: >99% reduction in exported GLB file size on production architectural model.**

The GLB Builder Utility plugin (`Na__TrueVision__GlbBuilder__EngineCore__ComponentInstancing__.rb`) was extended with a full Component Instancing system. SketchUp "Components" (as distinct from "Groups") are shared-definition objects — editing one updates all. The exporter now respects this: instead of flattening every component instance into duplicated vertex data, each unique `ComponentDefinition` is written to the GLB binary buffer exactly once, and multiple glTF nodes reference it with per-instance transform matrices.

**Why TrueVision benefits automatically (zero code changes):**
- Three.js `GLTFLoader` automatically shares a single `BufferGeometry` instance in GPU memory when multiple nodes reference the same mesh index (confirmed Three.js issue #29768). No `InstancedMesh` required for the GPU memory savings.
- Material traversal in `Na__ModelLoader__MultiModel.js` operates per-node (`node.material.name`), not per-geometry, so all existing material cloning, PBR swap, and shadow setup work identically for instanced nodes.
- Walk mode collision, door animation (ADR entities excluded from instancing), storey visibility toggles — all operate by scene traversal and are unaffected by the new node structure.

**Future opportunity:** Converting shared-mesh node groups into `THREE.InstancedMesh` on load would reduce these to a single draw call per definition, delivering a further GPU render performance improvement on top of the memory savings already achieved.

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.8.0 - 28-Feb-2026
#### Component Instancing — Shared Mesh GLB Export

**Production Result: ~449 MB → ~1 MB (>99% file size reduction)**

The single most impactful optimisation added to the export pipeline. Before this change, every placed SketchUp Component was individually flattened by `TraverseEntities` — 100 identical chairs produced 100 full copies of chair vertex data in the binary buffer. After this change, chair geometry is written once; 100 glTF nodes reference that one mesh with individual world-space transforms. Three.js `GLTFLoader` automatically shares a single `BufferGeometry` in GPU memory across all nodes (confirmed Three.js issue #29768).

**New Module:** `Na__TrueVision__GlbBuilder__EngineCore__ComponentInstancing__.rb`
- `Na__Instancing__ScanForInstancedDefinitions` — public entry point; runs the recursive scan then builds `instanced_groups` and a `skip_set` of object_ids
- `Na__Instancing__RecursiveScan` — DFS walk into the full entity tree (including inside Groups at any depth); collects `ComponentInstance` entities grouped by `ComponentDefinition` object identity
- `Na__Instancing__BuildSharedMesh` — extracts definition geometry once in local Y-up space; uses existing `TraverseEntities` engine (no skip_set — full definition contents needed)
- `Na__Instancing__MirroredLocalTransform` — prepends a -1 X scale so `AddFaceToBucket` reverses winding/normals for mirrored instances
- `Na__Instancing__PackBucketsToMesh` — packs local geometry buckets into a single glTF mesh entry (no node; nodes are per-instance)
- `Na__Instancing__BuildSharedLinework` — parallel function for edge-only GLBs; extracts visible edges from definition in local Y-up space
- `Na__Instancing__EmitInstanceNodes` — creates one glTF node per instance referencing the shared mesh index with a conjugated world-space matrix (same pattern as `DoorHandler`)
- `Na__Instancing__RegisterInstancedMaterials` — ensures instanced component materials are present in `@material_map` / `gltf["materials"]` before geometry packing
- `Na__Instancing__ProcessAllInstanced` — mesh orchestrator; calls BuildSharedMesh + EmitInstanceNodes per instanced group
- `Na__Instancing__ProcessAllInstancedLinework` — linework orchestrator; deduplicates by definition so normal+mirrored partitions share one linework mesh

**Key design decisions:**
- Groups are recursed into but never instanced; only `Sketchup::ComponentInstance` entities are candidates
- ADR door assemblies excluded from instancing; they continue through `DoorHandler` for animation hierarchy
- Minimum threshold: 2+ instances in the same mirror partition to qualify (single-use components fall through unchanged)
- Mirrored instances (negative determinant transform from SketchUp "Flip Along") are partitioned into a separate shared mesh with reversed winding and negated normals, avoiding the cross-renderer winding bug with shared meshes under negative-scale transforms
- `skip_set` mechanism: instanced entity `object_id`s are passed into `TraverseEntities`/`TraverseEdges` so they are skipped during flat traversal — no geometry duplication, no structural changes to the traversal engines
- Materials on instanced definitions registered on-the-fly before geometry packing if not already in `@material_map`
- Linework early-exit guard updated to account for `instanced_groups` so linework-only-component scenes still produce a file

**Files Modified:**
- `Na__TrueVision__GlbBuilder__EngineCore__GeometryHandling__.rb`: `Na__GlbEngine__TraverseEntities` gains optional `instanced_skip_set` 6th parameter; skips instanced entities and propagates the set through recursive calls
- `Na__TrueVision__GlbBuilder__EngineCore__LineworkModelHandling__.rb`: `Na__LineworkEngine__TraverseEdges` gains optional `instanced_skip_set` 7th parameter with same propagation; `ExportLineworkToGlb` early-exit guard updated; `ProcessAllInstancedLinework` called after glTF build
- `Na__TrueVision__GlbBuilder__EngineCore__.rb`: `ExportEntitiesToGlb` Phase 1b now runs `ScanForInstancedDefinitions` (recursive); receives `skip_set` not `remaining_entities`; top-level loop iterates all entities with skip_set guard; passes skip_set into `TraverseEntities`; calls `ProcessAllInstanced` as Phase 3a
- `Na__TrueVision__GlbBuilder__Main__.rb`: added `require_relative` for new instancing module between GeometryHandling and MaterialHandling requires

**Downstream TrueVision App — zero changes required:**
- `GLTFLoader` shares `BufferGeometry` automatically; materials are cloned per-node not per-geometry
- Material swap by `node.material.name` works independently per instance
- Shadow settings, walk mode collision, door animation, storey visibility toggles — all unaffected
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.7.0 - 23-Feb-2026
- **Material Lookup System** (new module `Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__.rb`): fetches `Na__AppConfig__MaterialsLibrary.json` from GitHub Pages over HTTPS; builds a flat `{ SketchUpName => config_hash }` index for O(1) material lookups; caches both raw data and index in module state for the session.
- **Indexed material detection**: `Na__MaterialLookup__IsIndexedMaterial?(name)` — regex `/^MAT\d{3}__/` check with no dependency on the library being loaded.
- **Library index queries**: `Na__MaterialLookup__InLibrary?(name)` and `Na__MaterialLookup__GetConfig(name)` for O(1) exact-key lookups against the built index.
- **glTF material enrichment**: `Na__MaterialLookup__EnrichGltfMaterial(gltf_material, config)` patches a glTF material hash in-place using `config.key?()` guards so sparse library entries (materials with only a subset of keys defined) are handled safely. Sets `metallicFactor`, `roughnessFactor`, `baseColorFactor` (with alpha from `Opacity`), `alphaMode: "BLEND"` when opacity < 1, `doubleSided` from `IsDoubleSided`, and `emissiveFactor`.
- **IsDoubleSided support**: when a library entry carries `"IsDoubleSided": true`, the enrichment sets `"doubleSided": true` on the glTF material so the exported GLB itself carries the double-sided flag — glass and mirror faces render correctly from both sides in any glTF viewer without requiring WebApp-side overrides.
- **Three material export modes**: `Na__MaterialEngine__SetExportMode(mode)` in `MaterialHandling__.rb` accepts `:no_materials`, `:all_materials`, or `:indexed_only`.
  - `:no_materials` — only the default whitecard material (index 0) is emitted; all mesh primitives reference it. Produces a sanitised whitecard GLB identical to previous behavior.
  - `:all_materials` — all unique SketchUp materials exported with their face colours; indexed materials additionally enriched with PBR values from the library.
  - `:indexed_only` — only materials matching `/^MAT\d{3}__/` and present in the library index are exported; non-indexed materials fall back to index 0 (whitecard). Avoids bloating the GLB with unnamed or custom materials.
- **UI — Export Materials toggle** (Toggle 1): unchecked by default; when unchecked, export mode is `:no_materials`. No library fetch is performed.
- **UI — Export Standard Indexed Materials Only toggle** (Toggle 2): greyed out (`opacity: 0.4`, `pointer-events: none`) when Toggle 1 is unchecked; re-enabled when Toggle 1 is checked; checked by default. Resolves to `:indexed_only` when checked, `:all_materials` when unchecked.
- **Three possible export combinations**: (1) Toggle 1 OFF → whitecard only; (2) Toggle 1 ON + Toggle 2 ON → indexed PBR materials only; (3) Toggle 1 ON + Toggle 2 OFF → all SketchUp materials exported.
- **Callback parameter**: export JS callback passes `materialExportMode` string in JSON params; Ruby callback converts to symbol and calls `Na__MaterialEngine__SetExportMode` before invoking export; parse errors fall back safely to `:no_materials`.
- **Module load order**: `Na__TrueVision__GlbBuilder__Main__.rb` now requires `MaterialLookupSystem` immediately after `MaterialHandling` so the enrichment API is available when material handling runs.
- **Sparse library authoring**: `MaterialsLibrary.json` v2.1.0 uses the `MAT001__Default` entry as the full key reference template; all other materials only define keys that differ from defaults. `EnrichGltfMaterial` `config.key?()` guards ensure missing keys are silently skipped.
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.6.1 - 15-Feb-2026
- **Staircase support in storey-based export**: Added tags 16 (ExistingStairs) and 26 (ProposedStairs) to STOREY_ELEMENT_TAG_MAP
- **TAG_RANGES expansion**: Split ExistingStairs (16) and ProposedStairs (26) as dedicated entries instead of being in "Other" ranges
- **ExistingOther range update**: Changed from (16..19) to (17..19) to exclude stairs
- **ProposedOther range update**: Changed from (26..29) to (27..29) to exclude stairs
- **Documentation update**: README now lists stairs (16__, 26__) as supported element tags within storey containers
- **Export filenames**: Staircases now export as "Storey__[StoreyName]__[Existing/Proposed]Stairs__[Mesh/Linework]Model__.glb"
- **Backward compatibility**: Non-storey models can still export stairs using flat 16__ or 26__ tags
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.6.0 - 15-Feb-2026
- **Storey-based export system**: New top-level container detection for multi-storey buildings with tags 90-93
- **Storey container detection**: `Na__ExportCore__DetectStoreyContainers` scans root entities for storey tags (90=GroundFloor, 91=FirstFloor, 92=SecondFloor, 93=ThirdFloor)
- **Per-storey per-element export**: `Na__ExportCore__OrganizeStoreyChildrenByTags` groups storey children by element tags (11-15 Existing, 21-25 Proposed)
- **Storey-prefixed GLB filenames**: Pattern `{prefix}Storey__{StoreyName}__{ElementName}{Suffix}.glb` (e.g., "Storey__GroundFloor__ProposedWalls__MeshModel__.glb")
- **Parent transform parameter**: `Na__GlbEngine__ExportEntitiesToGlb` and `Na__LineworkEngine__ExportLineworkToGlb` now accept optional `parent_transform` for world-space baking
- **World-space correctness**: Storey container transformation pre-multiplied into root transform: `Z_UP_TO_Y_UP * storey.transformation * child.transformation`
- **Element tag granularity**: Split tag 10 (Existing) into [10] + [11-15] + [16-19], and tag 20 (Proposed) into [20] + [21-25] + [26-29] for finer export control
- **TAG_RANGES expansion**: Added individual entries for Walls (11, 21), Floors (12, 22), Roofs (13, 23), Windows (14, 24), Doors (15, 25)
- **STOREY_TAG_MAP constant**: Maps storey tag numbers to storey names for filename generation
- **STOREY_ELEMENT_TAG_MAP constant**: Maps child element tags to element names within storey context
- **MAX_NESTING_DEPTH increase**: Raised from 3 to 4 to support storey container nesting level
- **Backward compatibility**: Non-storey models export identically; tag 10 and 20 single-value ranges preserve existing "MainBuildingModel__Existing" and "MainBuildingModel__Proposed" filenames
- **Dual export path**: PHASE 1 exports flat non-storey items, PHASE 2 exports storey-based element groups when storeys detected
- **UI export preview**: Dialog shows storey-grouped file list with storey headings and building icon when storey mode active
- **Storey mode badge**: Export dialog displays "Storey Mode Active" badge when storey containers detected
- **Non-storey preservation**: OrbitHelperCube, Landscape, Vegetation, SceneContextual continue to export with flat naming even when storeys exist
- **Door assembly compatibility**: ADR-prefixed door assemblies inside storey containers detected and exported correctly within storey-specific ProposedDoors GLBs
- **Downstream benefits**: Enables per-storey visibility toggling in 3D web viewer for dolls house view and interior exploration
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.5.0 - 14-Feb-2026
- **Door assembly hierarchy preservation**: New SpecialObject module for ADR-prefixed door assemblies
- **Dual export support**: Both mesh and linework models preserve door hierarchy (ADR > MOD/ROT/OuterShell structure)
- **Inline detection**: ADR entities detected during traversal and diverted from normal virtual flattening pipeline
- **Top-level and nested detection**: Supports doors at any depth in model hierarchy (root level or nested in building groups)
- **Transform conjugation**: Similarity transform `Z_UP * M_su * inv(Z_UP)` converts door local spaces to Y-up for Three.js animation
- **Y-up rotation axis**: Enables standard `(0, 1, 0)` vertical rotation in downstream door animation scripts
- **Naming convention support**: ADR (door assembly), MOD (modifier with `__ROT__` tag and `[N]-Deg` pattern), ROT (hinge pivot point)
- **Per-material mesh splitting**: Door child geometry extracted via existing TraverseEntities, creating separate meshes per material within hierarchy
- **Linework hierarchy**: LineworkEngine updated with door detection, preserves same ADR/MOD/ROT structure with LINES primitives
- **Zero overhead**: When `door_assemblies` parameter is `nil`, no detection occurs—identical performance to previous versions
- **Tag mapping update**: Tag 25 now maps to `NaModel__MainBuildingModel__ProposedDoors` for proper door GLB naming
- **Material registration**: On-the-fly material registration for door-specific materials via `@material_map` integration
- **Child visibility filtering**: Respects `hidden?` and `layer.visible?` flags for door children during export
- **Geometry reuse**: Leverages existing face/edge extraction, normal transforms, mirror correction, and vertex deduplication logic
- **API integration**: `Na__DoorHandler__ExportDoorAssemblies` and `Na__DoorHandler__ExportDoorLinework` called from EngineCore after bucket-based export
- **Documentation**: Comprehensive README for door animation system architecture and integration
- **Downstream compatibility**: Enables click-to-open door animation in ValeVision3D web viewer with synchronized mesh and linework movement
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.4.0 - 12-Feb-2026
- **Project name prefix extraction**: GLB exports now automatically prepend project identifier from SketchUp filename
- **Filename parsing**: Extracts first section before "__" delimiter (e.g., "Rowbotham__" from "Rowbotham__WhiteCardModel__0.3.0__.skp")
- **Automatic application**: Prefix applied to all exported GLB files (mesh and linework models)
- **Downstream compatibility**: Enables 3D viewer apps to identify project context from GLB filenames
- **Graceful fallback**: Unsaved files or files without prefix delimiter export normally without prefix
- **API method**: Uses `Sketchup::Model.path` and `File.basename()` for reliable filename extraction
- **UI preview**: Export dialog shows prefixed filenames before export
- **OrbitHelperCube tag**: Added "01__OrbitHelperCube" export tag for camera orbit pivot control in Web 3D Viewer App
- **Tag range update**: Tag 01 removed from SKIP_RANGES (now [0, 2, 3, 4, 5, 6]) to enable OrbitHelperCube export
- **Mesh-only export**: OrbitHelperCube exports mesh model only (no linework) since it's used as pivot point, not visual geometry
- **Camera pivot control**: OrbitHelperCube model provides centre pivot point for camera rotation in downstream 3D viewer
- **Conditional export logic**: Export loop checks for "01__OrbitHelperCube" and skips linework generation for this tag only
- **Example output**: "Rowbotham__01__OrbitHelperCube__MeshModel__.glb" (mesh only), "Rowbotham__NaModel__LandscapeEnvironment__MeshModel__.glb" + "...__LineworkModel__.glb" (both)
# ---------------------------------------------------------

# ---------------------------------------------------------
### GLB Builder Utility - Version 1.3.0 - 10-Feb-2026
- **Twin GLB output per tagged series**: Each tag range now exports two GLBs—a Mesh model and a Linework model—for downstream 3D web app flexibility
- **Mesh model** (`__MeshModel__.glb`): Face geometry only; suffix configurable via `MESH_MODEL_SUFFIX`
- **Linework model** (`__LineworkModel__.glb`): Edge geometry with visibility semantics; suffix via `LINEWORK_MODEL_SUFFIX`
- **LineworkModelHandling module**: New `Na__TrueVision__GlbBuilder__EngineCore__LineworkModelHandling__.rb` for edge-only export
- **Visibility filters**: Linework respects `hidden?`, `soft?`, `smooth?`, and `layer.visible?`; exports only visible hard edges
- **Edge color**: `COLOR_0` (VEC4) vertex attribute from `entity.material.color` (default black)
- **Same transforms**: Uses `Z_UP_TO_Y_UP_MATRIX` and virtual flattening traversal for alignment with mesh GLBs
- **MESH_MODEL_INCLUDE_EDGES constant**: Toggle in GeometryHandling (default `false`) to include edges in mesh GLBs; set to `true` if needed
- **CoreExport**: PerformExport now produces both mesh and linework files per series; success message reports mesh + linework counts
# ---------------------------------------------------------


# ---------------------------------------------------------
### GLB Builder Utility - Version 1.2.0 - 10-Feb-2026
- Complete rewrite of geometry export engine: "Virtual Flattening" architecture
- **Non-destructive export**: recursive DFS traversal with matrix accumulation replaces destructive explosion approach
- Model is never modified during export (no start_operation / abort_operation needed)
- **Mirror correction**: determinant check on accumulated 3x3 matrix detects mirrored geometry; winding order swap [A,B,C] to [A,C,B] restores CCW normals
- **Inverse-transpose normal matrix**: cofactor matrix used for correct normal transformation under non-uniform scale
- **Vertex deduplication**: Hash-based cache keyed on [pos+normal+uv] reduces file size and improves GPU efficiency
- **Binary buffer packing**: `Na__GltfHelpers__AddAccessor` implementation with proper bufferView/accessor creation, 4-byte alignment, min/max bounds
- **Layer0 inheritance**: entities on Layer0 inherit the parent container's layer context during traversal
- **Hard edge export**: non-soft, non-smooth edges exported as glTF LINES primitives (mode 1)
- **UV extraction**: UVQ perspective correction from face.mesh(7) with V-flip for glTF convention
- **Entity naming**: persistent_id-based sanitized names for web viewer debugging
- **Z-up to Y-up**: constant rotation matrix applied at traversal root (determinant +1, no false mirror detection)
- Fixes: "reference to deleted DrawingElement" crash on multi-file export
- Fixes: "Na__GltfHelpers__AddAccessor not implemented" error (BIN chunk was 0 bytes)
- Fixes: empty GLB files with no actual geometry data
# ---------------------------------------------------------


# ---------------------------------------------------------
### GLB Builder Utility - Version 1.1.0 - 10-Feb-2026
- Total rewrite of the GLB Builder Utility.
- Total refactoring of the codebase to improve readability and maintainability.
- Modularisation of the codebase to improve maintainability and separation of concerns.
- Aligned Intelligent SketchUp Tag export ranges with README-defined `##__` prefix system
- Added explicit export buckets for `MainBuildingModel__Existing` (`10__`-`19__`) and `MainBuildingModel__Proposed` (`20__`-`29__`)
- Added `Vegetation` export bucket (`50__`-`59__`) and kept `SceneContextual` at (`60__`-`70__`) to avoid overlap
- Updated parser to accept only strict two-digit prefix tags formatted as `##__...`
- Updated no-match console/help messaging to show full required tag map and naming examples
- Centralised unit conversion and configuration: added shared `INCHES_TO_METERS`, wired Core/Engine modules to use it, and updated UI/export messaging to derive ranges, filenames, and texture/exclusion descriptions from module constants
# ---------------------------------------------------------


# ---------------------------------------------------------
### GLB Builder Utility - Version 1.0.6 - 13-Jan-2025
- Added positioned texture support for SketchUp's texture positioning tool
- Dual-method UV extraction: standard for normal textures, enhanced for positioned
- Automatic detection of positioned textures (rotated, scaled, skewed, translated)
- Proper perspective correction using UVQ coordinates with Q-component handling
- Maintains backward compatibility with existing texture workflows
- Enhanced debugging output to distinguish between standard and positioned textures
# ---------------------------------------------------------


# ---------------------------------------------------------
### GLB Builder Utility - Version 1.0.5 - 13-Jan-2025
- Fixed corruption issue when running script multiple times in one session
- Added comprehensive state reset function to clear all module variables
- Eliminates texture index mismatches between exports
- Ensures clean state for each export without requiring SketchUp restart


# ---------------------------------------------------------
### GLB Builder Utility - Version 1.0.4 - 13-Jan-2025
- Complete rewrite using "apply transforms" explosion approach
- Eliminates complex transformation matrix calculations
- All nested hierarchies temporarily exploded for true global coordinates
- Faces grouped by material and layer for optimized mesh generation
- Single undo operation restores original model state
- Guarantees pixel-perfect coordinate accuracy in GLB output
- Simplified codebase with improved maintainability
# ---------------------------------------------------------

# ---------------------------------------------------------
### Version 1.0.3 - 12-Jan-2025
- Implemented smart leaf container detection for manifold validation
- Added intelligent parent/child container analysis to prevent false positives
- Only validates groups/components containing raw geometry (faces/edges)
- Skips validation on parent containers that only hold nested objects
- Added material handling documentation for downstream texture switching
- Enhanced validation feedback with clear container type identification
- Improved support for complex nested furniture and architectural models
# ---------------------------------------------------------

# ---------------------------------------------------------
### Version 1.0.2 - 12-Jul-2025
- Fixed coordinate system conversion (Z-up to Y-up)
- Fixed unit conversion (inches to meters)
- Fixed texture UV mapping and material colorization
- Added comprehensive progress tracking
# ---------------------------------------------------------

# ---------------------------------------------------------
### Version 1.0.1 - 12-Jul-2025

- Complete rewrite with proper GLB binary format
- Full material and texture support
- Correct GLTF 2.0 JSON structure

---

### Version 1.0.0 - 12-Jul-2025

- Initial implementation with core GLB export functionality
- Texture downscaling feature for optimized file sizes
- Layer filtering system for TrueVision exclusions
