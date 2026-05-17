# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR ROTATION PIVOT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__RotationPivotBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__RotationPivotBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the per-panel ROT marker groups consumed by the
#              TrueVision3D click-to-open animation. Mirrors
#              `Na__InteriorDoorSystem::Na__RotationPivotBuilder` but
#              emits ONE marker per pivoting panel, indexed via
#              `NA_GROUP_NAME_ROT_HINGE_FORMAT` (e.g. ROT001, ROT002).
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Each ROT marker is a SketchUp::Group whose origin is the panel's
#   hinge axis at the bottom of the opening. The TrueVision3D GLB
#   importer reads `rotObject.position` to derive the rotation pivot.
# - Helper geometry consists of:
#     * Vertical hinge axis line (Z+ direction, panel-height tall).
#     * 50x50mm crosshair at top + bottom of the axis line.
#     * Swing-direction arrow (only when rot_degrees magnitude == 90).
# - All edges live on the `:door_helpers` role tag (resolves to
#   `02__DoorHelpers__RotationPivots`) and are painted red via
#   `MTE201__LineColour__Red` so the helper is unambiguously a marker
#   in any SketchUp display style.
# - The ROT marker tag's `02__` numeric prefix is in the GLB exporter
#   skipRanges so the helper geometry never reaches production GLBs;
#   only the marker GROUP NODE NAME (`ROT###__RotationPoint__...`) is
#   preserved for TrueVision's animation scanner.
#
# COORDINATE SYSTEM (ROT-local):
# - Origin       = hinge axis at bottom of panel (panel-local 0, 0, 0).
# - X+           = along the panel's leading edge direction.
# - Y+           = through the wall depth.
# - Z+           = upwards (panel height direction).
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3a implementation: emits per-panel ROT marker with red helper
#   geometry. Adapts the InteriorDoor pivot builder pattern.
#
# 17-May-2026 - Version 0.1.0
# - Phase-1 scaffold (returned nil).
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__ExtFold__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorMultiFoldingDoorSystem
module Na__RotationPivotBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    TagManager        = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
    GeometryHelpers   = Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_PIVOT_END_INSET_MM           = 100                                       # <-- Inset of axis line ends from panel top + bottom
    NA_CROSSHAIR_HALF_LENGTH_MM     = 25                                        # <-- Half-extent of the 50x50 mm '+'
    NA_SWING_ARROW_RADIUS_MM        = 100                                       # <-- Arc radius for the rotation indicator
    NA_SWING_ARROW_SEGMENT_COUNT    = 8                                         # <-- Polyline segments for the arc
    NA_SWING_ARROW_HEAD_LENGTH_MM   = 25                                        # <-- Length of each arrowhead 'V' edge
    NA_HELPER_EDGE_COLOUR_ID        = "MTE201__LineColour__Red".freeze
    NA_SWING_DRAW_DEG_THRESHOLD     = 95                                        # <-- Only draw arc for |angle| <= this many deg (covers +/- 2 deg accordion tilt on top of the 90 deg base swing)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build a ROT Marker for a Single Pivoting Panel
    # ------------------------------------------------------------
    # Creates an empty group at `origin_point`, names it per the bifold
    # ROT format (ROT###__RotationPoint__BifoldHingeCentre), and fills
    # it with red pivot helper geometry sized to the panel height.
    #
    # @param parent_entities [Sketchup::Entities] target entities
    # @param origin_point    [Geom::Point3d] hinge axis at panel base (inches)
    # @param rot_index       [Integer] 1-based ROT marker index
    # @param panel_height_mm [Numeric] panel height for axis line length
    # @param rotation_deg    [Integer] signed open-state rotation angle
    # @return [Sketchup::Group, nil]
    def self.na_build_rotation_pivot(parent_entities, origin_point, rot_index, panel_height_mm, rotation_deg)
        return nil unless parent_entities
        return nil unless origin_point.is_a?(Geom::Point3d)

        rot_group        = parent_entities.add_group
        rot_group.name   = format(
            Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_GROUP_NAME_ROT_HINGE_FORMAT,
            rot_index.to_i
        )
        rot_group.transform!(Geom::Transformation.new(origin_point))

        bottom_z_mm      = NA_PIVOT_END_INSET_MM
        top_z_mm         = panel_height_mm.to_f - NA_PIVOT_END_INSET_MM
        return rot_group if top_z_mm <= bottom_z_mm                             # <-- Degenerate panel - keep empty marker for ADR id

        entities         = rot_group.entities

        na_draw_vertical_axis_line(entities, bottom_z_mm, top_z_mm)
        na_draw_crosshair_at(entities, bottom_z_mm)
        na_draw_crosshair_at(entities, top_z_mm)
        na_draw_swing_arrow_if_applicable(entities, top_z_mm, rotation_deg)

        na_paint_helper_edges_red(rot_group)

        DebugTools.na_debug_geometry(
            "Built bifold ROT marker ROT#{format('%03d', rot_index.to_i)} (rot=#{rotation_deg.to_i}deg, h=#{panel_height_mm.round}mm)"
        )
        rot_group
    rescue StandardError => e
        DebugTools.na_debug_error("na_build_rotation_pivot failed", e)
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Draw the Vertical Hinge Axis Line at Local X=0, Y=0
    # ------------------------------------------------------------
    def self.na_draw_vertical_axis_line(entities, bottom_z_mm, top_z_mm)
        p0 = na_local_point_in(0.0, 0.0, bottom_z_mm)
        p1 = na_local_point_in(0.0, 0.0, top_z_mm)
        edge = entities.add_line(p0, p1)
        na_apply_helper_tag(edge)
    end
    private_class_method :na_draw_vertical_axis_line
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw a 50x50mm '+' Crosshair on the XY Plane at Z
    # ------------------------------------------------------------
    def self.na_draw_crosshair_at(entities, z_mm)
        half = NA_CROSSHAIR_HALF_LENGTH_MM
        x_edge = entities.add_line(
            na_local_point_in(-half, 0.0, z_mm),
            na_local_point_in(+half, 0.0, z_mm)
        )
        na_apply_helper_tag(x_edge)
        y_edge = entities.add_line(
            na_local_point_in(0.0, -half, z_mm),
            na_local_point_in(0.0, +half, z_mm)
        )
        na_apply_helper_tag(y_edge)
    end
    private_class_method :na_draw_crosshair_at
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw the Swing-Direction Arrow When Applicable
    # ------------------------------------------------------------
    # Emits a visible quarter-circle arc for panels rotating around 90 deg
    # (every master and V1.7.2-onwards every accordion slave). Anything
    # past the threshold (e.g. legacy 180 deg slaves) is skipped because
    # a half circle visually clutters the model without aiding intent.
    def self.na_draw_swing_arrow_if_applicable(entities, z_mm, rotation_deg)
        return if rotation_deg.to_i.abs > NA_SWING_DRAW_DEG_THRESHOLD
        return if rotation_deg.to_i == 0

        sweep_deg  = rotation_deg.to_i
        start_deg  = 0.0                                                        # <-- Closed-state direction along +X (panel leading edge)
        arc_pts_in = na_compute_arrow_arc_points(start_deg, sweep_deg, z_mm)
        return if arc_pts_in.length < 2

        na_draw_polyline_edges(entities, arc_pts_in)
        na_draw_arrowhead_at_open_end(entities, arc_pts_in)
    end
    private_class_method :na_draw_swing_arrow_if_applicable
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Compute Polyline Points for the Swing Arrow Arc
    # ------------------------------------------------------------
    def self.na_compute_arrow_arc_points(start_deg, sweep_deg, z_mm)
        radius_in = GeometryHelpers.na_mm_to_inch(NA_SWING_ARROW_RADIUS_MM)
        z_in      = GeometryHelpers.na_mm_to_inch(z_mm)
        segments  = NA_SWING_ARROW_SEGMENT_COUNT
        points    = []

        (0..segments).each do |i|
            t       = i.to_f / segments
            angle   = (start_deg + sweep_deg * t) * Math::PI / 180.0
            px_in   = radius_in * Math.cos(angle)
            py_in   = radius_in * Math.sin(angle)
            points << Geom::Point3d.new(px_in, py_in, z_in)
        end

        points
    end
    private_class_method :na_compute_arrow_arc_points
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Add Consecutive Edges Between an Ordered Point List
    # ------------------------------------------------------------
    def self.na_draw_polyline_edges(entities, points)
        (points.length - 1).times do |i|
            edge = entities.add_line(points[i], points[i + 1])
            na_apply_helper_tag(edge)
        end
    end
    private_class_method :na_draw_polyline_edges
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw the 'V' Arrowhead at the Last Point of the Arc
    # ------------------------------------------------------------
    def self.na_draw_arrowhead_at_open_end(entities, arc_pts_in)
        tip      = arc_pts_in.last
        previous = arc_pts_in[-2]
        tangent  = na_normalise_xy_vector(tip.x - previous.x, tip.y - previous.y)
        return unless tangent

        perp_x   = -tangent[1]
        perp_y   =  tangent[0]
        head_in  = GeometryHelpers.na_mm_to_inch(NA_SWING_ARROW_HEAD_LENGTH_MM)
        back_x   = -tangent[0]
        back_y   = -tangent[1]

        wing_a_x = (back_x + perp_x) * head_in / Math.sqrt(2.0)
        wing_a_y = (back_y + perp_y) * head_in / Math.sqrt(2.0)
        wing_b_x = (back_x - perp_x) * head_in / Math.sqrt(2.0)
        wing_b_y = (back_y - perp_y) * head_in / Math.sqrt(2.0)

        wing_a   = Geom::Point3d.new(tip.x + wing_a_x, tip.y + wing_a_y, tip.z)
        wing_b   = Geom::Point3d.new(tip.x + wing_b_x, tip.y + wing_b_y, tip.z)

        edge_a = entities.add_line(tip, wing_a)
        edge_b = entities.add_line(tip, wing_b)
        na_apply_helper_tag(edge_a)
        na_apply_helper_tag(edge_b)
    end
    private_class_method :na_draw_arrowhead_at_open_end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Math + Tagging
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build a SketchUp Point in Inches from mm-Local Coords
    # ------------------------------------------------------------
    def self.na_local_point_in(x_mm, y_mm, z_mm)
        Geom::Point3d.new(
            GeometryHelpers.na_mm_to_inch(x_mm),
            GeometryHelpers.na_mm_to_inch(y_mm),
            GeometryHelpers.na_mm_to_inch(z_mm)
        )
    end
    private_class_method :na_local_point_in
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Normalise a 2D Vector in the XY Plane
    # ------------------------------------------------------------
    def self.na_normalise_xy_vector(dx, dy)
        length = Math.sqrt(dx * dx + dy * dy)
        return nil if length < 1.0e-9
        [dx / length, dy / length]
    end
    private_class_method :na_normalise_xy_vector
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Tag an Edge with the :door_helpers Role
    # ------------------------------------------------------------
    def self.na_apply_helper_tag(edge)
        return unless edge && edge.respond_to?(:layer=)
        TagManager.na_apply_tag_to_entity(edge, :door_helpers)
    end
    private_class_method :na_apply_helper_tag
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Paint Every Helper Edge with the Red MTE Colour
    # ------------------------------------------------------------
    def self.na_paint_helper_edges_red(rot_group)
        return unless rot_group && rot_group.respond_to?(:valid?) && rot_group.valid?
        EdgeColourManager.na_apply_edge_colour_to_group(rot_group, NA_HELPER_EDGE_COLOUR_ID)
    end
    private_class_method :na_paint_helper_edges_red
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__RotationPivotBuilder
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
