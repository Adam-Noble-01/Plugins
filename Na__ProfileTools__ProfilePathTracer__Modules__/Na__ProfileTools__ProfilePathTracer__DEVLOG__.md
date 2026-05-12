# Na__ProfileTools__ProfilePathTracer - DEVLOG
# =======================================================================================
## Version History

# =======================================================================================
## Profile Path Tracer - v1.1.0 - 12-May-2026

### Fix: Scene Pick Profile Extraction — Broken Edge Colour Resolution

#### Problem

Selecting a Group/Component face via the **Scene Pick** workflow (`Profile Source → Scene Pick
(Group/Component Face)` → **Pick Scene Profile** button) always failed with:

```
Scene profile extraction failed: undefined method `Na__Exporter__ResolveEdgeColourHex'
for Na__ProfileTools__ProfilePathTracer::Na__ProfileExporter:Module
```

`Na__SceneProfileRegistry__ExtractUnifiedGeometry` was manually building mesh edge records
inline and calling `Na__ProfileExporter.Na__Exporter__ResolveEdgeColourHex` — a method that
was never defined anywhere on `Na__ProfileExporter`.

#### Root Cause

The inline edge-record block was duplicating logic that already lives in
`Na__Exporter__BuildMeshEdgeRecord` and referenced a non-existent method name (missing
`Fallback` suffix, or stale from a prior API rename). Because the exception was rescued in
`Na__SceneProfileRegistry__SetFromEntity`, every scene pick silently returned the error
string rather than the extracted profile.

#### Fix

Replaced the 15-line inline block in `Na__SceneProfileRegistry__ExtractUnifiedGeometry`
(lines 264–278) with a single delegation call to the canonical exporter helper:

```ruby
# Before (broken)
material_name = edge.material ? edge.material.display_name.to_s : ''
colour_id = Na__ProfileExporter.Na__Exporter__ResolveEdgeColourId(material_name)
colour_hex = Na__ProfileExporter.Na__Exporter__ResolveEdgeColourHex(edge, colour_id)
mesh_edges << {
    'EdgeId' => edge_id,
    ...
    'EdgeColourHex' => colour_hex
}

# After (fixed — DRY delegation)
mesh_edges << Na__ProfileExporter.Na__Exporter__BuildMeshEdgeRecord(edge, edge_id, start_vertex_id, end_vertex_id)
```

`Na__Exporter__BuildMeshEdgeRecord` applies the full colour resolution chain used by the
library export path:
1. `Na__EdgeColourManager.Na__EdgeColours__CanonicalIdForMaterial` when `Na__EdgeColourManager`
   is available (correct colour ID + hex from the centralised edge-colour library).
2. `Na__Exporter__ResolveEdgeColourHexFallback` + edge material colour when the manager is
   absent.
3. `NA_DEFAULT_EDGE_HEX` (`#666666`) as a final safe fallback.

Scene-picked profiles now carry edge colours, soft/smooth flags, and hidden/shadow state
that are byte-for-byte identical to profiles produced via the full Create Profile editor,
satisfying the single-source-of-truth requirement.

#### Files Touched

| Path | Change |
|---|---|
| `02__Src__AppModules/20__System__ApplyProfileAlongPath/Na__ProfileTools__ApplyProfile__SceneProfileRegistry__.rb` | Replaced broken inline mesh-edge block with `Na__Exporter__BuildMeshEdgeRecord` delegation |

# =======================================================================================

# END OF DEVLOG
