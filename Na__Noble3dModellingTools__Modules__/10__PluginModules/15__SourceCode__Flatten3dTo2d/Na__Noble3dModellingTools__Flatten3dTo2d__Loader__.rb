# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FLATTEN 3D TO 2D - LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Flatten3dTo2d__Loader__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__Flatten3dTo2d
# PURPOSE    : Load Flatten3dTo2d module files in deterministic order
# CREATED    : 2026
#
# DESCRIPTION:
# - Projects the selected groups/components onto a camera-facing plane while the
#   view is in Parallel Projection, producing a single new flat 2D group.
# - Two public entrypoints: full linework (Flatten To Group) and outline-only
#   (Flatten To Silhouette). The original 3D geometry is never modified.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Module Requires
# -----------------------------------------------------------------------------

require_relative 'Na__Noble3dModellingTools__Flatten3dTo2d__ViewProjection__'
require_relative 'Na__Noble3dModellingTools__Flatten3dTo2d__GeometryCollector__'
require_relative 'Na__Noble3dModellingTools__Flatten3dTo2d__FlattenBuilder__'
require_relative 'Na__Noble3dModellingTools__Flatten3dTo2d__SilhouetteBuilder__'
require_relative 'Na__Noble3dModellingTools__Flatten3dTo2d__Run__'

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
