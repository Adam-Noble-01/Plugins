# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR ROTATION PIVOT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__RotationPivotBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem
# MODULE     : Na__RotationPivotBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the single placeholder ROT001 marker required by
#              the TrueVision animation contract even though sliding
#              doors do not pivot. The marker is a tiny named group on
#              the `:door_helpers` excluded layer so the GLB exporter
#              preserves the node name without surfacing geometry in
#              production scenes.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Sliding doors translate along a single linear track; rotation is
#   not part of the animation contract. However the TrueVision3D
#   click-to-open scanner expects every ADR to expose at least one
#   ROT###__RotationPoint__... sibling so the door is recognised as a
#   first-class animatable assembly. We satisfy that contract by
#   emitting a single zero-content ROT marker at the ADR origin.
# - The placeholder also serves as a useful debug breadcrumb when an
#   exported GLB is inspected: the marker's group name announces the
#   door type ("SlidingPanelTrack") even with no geometry inside.
# - One additional 50x50 mm crosshair is rendered inside the placeholder
#   so the marker is visible in SketchUp during authoring (the helper
#   tag's `02__` prefix excludes it from the GLB exporter, so the user
#   sees it locally but TrueVision never does).
#
# COORDINATE SYSTEM (ROT-local):
# - Origin       = supplied origin_point (typically the front-leaf hinge
#   edge at floor level).
# - X+, Y+, Z+   = mirror the parent ADR-local frame.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3b implementation: emits a named placeholder marker with a
#   single visible crosshair.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (returned nil).
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__ExtSlide__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__RotationPivotBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    TagManager        = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
    GeometryHelpers   = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_CROSSHAIR_HALF_LENGTH_MM     = 25                                        # <-- Half-extent of the 50x50 mm '+'
    NA_HELPER_EDGE_COLOUR_ID        = "MTE201__LineColour__Red".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build the Single Placeholder ROT001 Marker for a Sliding ADR
    # ------------------------------------------------------------
    # @param parent_entities [Sketchup::Entities] target entities
    # @param origin_point    [Geom::Point3d] marker origin (inches)
    # @return [Sketchup::Group, nil]
    def self.na_build_rotation_pivot(parent_entities, origin_point)
        return nil unless parent_entities
        return nil unless origin_point.is_a?(Geom::Point3d)

        rot_group        = parent_entities.add_group
        rot_group.name   = Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_GROUP_NAME_ROT_PLACEHOLDER
        rot_group.transform!(Geom::Transformation.new(origin_point))

        entities = rot_group.entities
        na_draw_crosshair_at_origin(entities)
        na_paint_helper_edges_red(rot_group)

        DebugTools.na_debug_geometry("Built sliding placeholder ROT marker (#{rot_group.name})")
        rot_group
    rescue StandardError => e
        DebugTools.na_debug_error("ExtSlide::RotationPivotBuilder.na_build_rotation_pivot failed", e)
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry
# -----------------------------------------------------------------------------

    def self.na_draw_crosshair_at_origin(entities)
        half = NA_CROSSHAIR_HALF_LENGTH_MM
        x_edge = entities.add_line(
            na_local_point_in(-half, 0.0, 0.0),
            na_local_point_in(+half, 0.0, 0.0)
        )
        na_apply_helper_tag(x_edge)
        y_edge = entities.add_line(
            na_local_point_in(0.0, -half, 0.0),
            na_local_point_in(0.0, +half, 0.0)
        )
        na_apply_helper_tag(y_edge)
    end
    private_class_method :na_draw_crosshair_at_origin

    def self.na_local_point_in(x_mm, y_mm, z_mm)
        Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(x_mm),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(z_mm)
        )
    end
    private_class_method :na_local_point_in

    def self.na_apply_helper_tag(edge)
        return unless edge && edge.respond_to?(:layer=)
        TagManager.na_apply_tag_to_entity(edge, :door_helpers)
    end
    private_class_method :na_apply_helper_tag

    def self.na_paint_helper_edges_red(rot_group)
        return unless rot_group && rot_group.respond_to?(:valid?) && rot_group.valid?
        EdgeColourManager.na_apply_edge_colour_to_group(rot_group, NA_HELPER_EDGE_COLOUR_ID)
    end
    private_class_method :na_paint_helper_edges_red

# endregion -------------------------------------------------------------------

end # module Na__RotationPivotBuilder
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
