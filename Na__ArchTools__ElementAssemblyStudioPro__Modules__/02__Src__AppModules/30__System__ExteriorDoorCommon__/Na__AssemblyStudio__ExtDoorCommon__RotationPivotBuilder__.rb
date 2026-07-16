# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - ROTATION PIVOT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDoorCommon__RotationPivotBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorCommon
# MODULE     : Na__RotationPivotBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the TrueVision / ValeVision ROT helper (axis line,
#              crosshairs, angle-sweep arrow) at the definition root for a leaf.
#
# DESCRIPTION:
# - Extracted from the Exterior Double Door System. The ROT marker suffix is
#   passed in so each system emits its own documentation tail
#   (ExteriorDoubleDoorHingeCentre, ExteriorSingleDoorHingeCentre, ...). The
#   DoorNamingContract parser is suffix-agnostic.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__DoorNamingContract__'
require_relative 'Na__AssemblyStudio__ExtDoorCommon__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoorCommon
module Na__RotationPivotBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers   = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__GeometryHelpers
    NamingContract    = Na__AssemblyStudio::Na__GeometryHelpers::Na__DoorNamingContract
    TagManager        = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_CROSSHAIR_HALF_MM = 25.0                                                 # <-- Half-extent of the '+' crosshair
    NA_ARROW_RADIUS_MM   = 100.0                                                # <-- Swing-arc arrow radius
    NA_EDGE_COLOUR_ID    = 'MTE201__LineColour__Red'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build the ROT Helper Group for a Leaf
    # ------------------------------------------------------------
    # @param parent_entities [Sketchup::Entities] Target entities (ADR root)
    # @param leaf            [Hash] Leaf descriptor with hinge / angle data
    # @param rot_suffix      [String] Per-system documentation tail for the marker
    # @return [Sketchup::Group]
    def self.na_build(parent_entities, leaf, rot_suffix)
        group = parent_entities.add_group
        group.name = NamingContract.na_format_rot_marker(leaf[:index], rot_suffix)
        origin = Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(leaf[:hinge_x_mm]),
            GeometryHelpers.na_mm_to_inch(leaf[:pivot_y_mm]),
            GeometryHelpers.na_mm_to_inch(leaf[:origin_z_mm])
        )
        group.transform!(Geom::Transformation.translation(origin))

        na_build_axis(group.entities, leaf[:height_mm])
        na_build_crosshair(group.entities, 0)
        na_build_crosshair(group.entities, leaf[:height_mm])
        na_build_angle_arrow(group.entities, leaf)
        na_style(group)
        group
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Draw Vertical Hinge Axis Line
    # ------------------------------------------------------------
    def self.na_build_axis(entities, height_mm)
        entities.add_line(na_point(0, 0, 0), na_point(0, 0, height_mm))
    end
    private_class_method :na_build_axis
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw XY Crosshair at a Given Z Height
    # ------------------------------------------------------------
    def self.na_build_crosshair(entities, z_mm)
        half = NA_CROSSHAIR_HALF_MM
        entities.add_line(na_point(-half, 0, z_mm), na_point(half, 0, z_mm))
        entities.add_line(na_point(0, -half, z_mm), na_point(0, half, z_mm))
    end
    private_class_method :na_build_crosshair
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw Swing-Angle Arc Polyline for the Leaf
    # ------------------------------------------------------------
    def self.na_build_angle_arrow(entities, leaf)
        return if leaf[:signed_angle_deg].zero?

        points = GeometryHelpers.na_arc_points_mm(
            0, 0, NA_ARROW_RADIUS_MM,
            leaf[:closed_latch_angle_deg], leaf[:signed_angle_deg], 24
        ).map { |point| na_point(point[:x], point[:y], leaf[:height_mm]) }
        points.each_cons(2) { |first, second| entities.add_line(first, second) }
        na_build_arrowhead(entities, points)
    end
    private_class_method :na_build_angle_arrow
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw Arrowhead Wings at the Arc Tip
    # ------------------------------------------------------------
    def self.na_build_arrowhead(entities, points)
        return if points.length < 2
        tip = points[-1]
        prior = points[-2]
        vector = tip - prior
        return unless vector.valid?
        vector.length = GeometryHelpers.na_mm_to_inch(25)
        wing_a = vector.transform(Geom::Transformation.rotation(ORIGIN, Z_AXIS, 150.degrees))
        wing_b = vector.transform(Geom::Transformation.rotation(ORIGIN, Z_AXIS, -150.degrees))
        entities.add_line(tip, tip.offset(wing_a))
        entities.add_line(tip, tip.offset(wing_b))
    end
    private_class_method :na_build_arrowhead
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Styling + Primitives
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Tag Edges as Door Helpers and Apply Red Edge Colour
    # ------------------------------------------------------------
    def self.na_style(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
            TagManager.na_apply_tag_to_entity(edge, :door_helpers)
        end
        EdgeColourManager.na_apply_edge_colour_to_group(group, NA_EDGE_COLOUR_ID)
    end
    private_class_method :na_style
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build a Geom::Point3d From Millimetre Coordinates
    # ------------------------------------------------------------
    def self.na_point(x_mm, y_mm, z_mm)
        Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(x_mm),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(z_mm)
        )
    end
    private_class_method :na_point
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__RotationPivotBuilder
end # module Na__ExteriorDoorCommon
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
