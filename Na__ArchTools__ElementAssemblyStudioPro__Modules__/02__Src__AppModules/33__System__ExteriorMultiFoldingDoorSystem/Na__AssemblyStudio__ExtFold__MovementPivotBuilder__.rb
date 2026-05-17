# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR MOVEMENT PIVOT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__MovementPivotBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__MovementPivotBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the per-panel MVE marker groups consumed by the
#              TrueVision3D click-to-open animation. Mirrors
#              `Na__RotationPivotBuilder` but encodes a LINEAR track
#              translation rather than a rotation. One marker per
#              translating panel, indexed via `NA_MVE_NAME_FORMAT`
#              (e.g. MVE001, MVE002).
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Each MVE marker is a SketchUp::Group whose origin is the panel's
#   CLOSED-state hinge position (start of the track displacement).
# - Helper geometry consists of:
#     * Linear track line from origin to (origin + axis * distance) at
#       the panel TOP (so it visually reads as a head-track marker
#       near the head rail).
#     * 50x50mm crosshair at both ends of the track line.
#     * Arrowhead at the destination indicating travel direction.
# - All edges live on the `:door_helpers` role tag and are painted red
#   via `MTE201__LineColour__Red`. The tag's `02__` prefix is in the
#   GLB exporter skipRanges so the helper geometry never reaches
#   production GLBs - only the marker GROUP NODE NAME survives.
# - The group's transformation/origin is what the TrueVision GLB
#   importer reads to derive the translation start point. The MVE
#   distance + axis is parsed directly from the parent MOD group name
#   token (e.g. `MVE__X--600-mm`).
#
# COORDINATE SYSTEM (MVE-local):
# - Origin       = closed-state hinge axis at panel TOP (panel-local 0, 0, 0).
#   The marker sits at panel TOP rather than panel BOTTOM (where ROT
#   sits) so the track helper is visually distinct from the hinge axis.
# - X+           = along the panel's leading edge direction.
# - Y+           = through the wall depth.
# - Z+           = upwards (axis line stays in XY plane at z=0).
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3a implementation: emits per-panel MVE marker with red track
#   helper geometry.
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
module Na__MovementPivotBuilder

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

    NA_CROSSHAIR_HALF_LENGTH_MM     = 25                                        # <-- Half-extent of the 50x50 mm '+'
    NA_ARROW_HEAD_LENGTH_MM         = 25                                        # <-- Length of each arrowhead 'V' edge
    NA_HELPER_EDGE_COLOUR_ID        = "MTE201__LineColour__Red".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build an MVE Marker for a Single Translating Panel
    # ------------------------------------------------------------
    # Creates an empty group at `origin_point`, names it per the bifold
    # MVE format (MVE###__MovementPoint__BifoldPanelTrack), and fills
    # it with red track helper geometry (origin -> destination line +
    # crosshairs + arrowhead) inside the group's local frame.
    #
    # @param parent_entities [Sketchup::Entities] target entities
    # @param origin_point    [Geom::Point3d] closed-state hinge position (inches)
    # @param mve_index       [Integer] 1-based MVE marker index
    # @param axis            [String]  "X" | "Y" - axis of translation
    # @param distance_mm     [Integer] signed translation magnitude in mm
    # @return [Sketchup::Group, nil]
    def self.na_build_movement_pivot(parent_entities, origin_point, mve_index, axis, distance_mm)
        return nil unless parent_entities
        return nil unless origin_point.is_a?(Geom::Point3d)
        return nil if axis.nil? || distance_mm.to_i == 0

        mve_group        = parent_entities.add_group
        mve_group.name   = format(
            Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::NA_MVE_NAME_FORMAT,
            mve_index.to_i
        )
        mve_group.transform!(Geom::Transformation.new(origin_point))

        entities         = mve_group.entities

        na_draw_track_line(entities, axis, distance_mm)
        na_draw_crosshair_at_origin(entities)
        na_draw_crosshair_at_destination(entities, axis, distance_mm)
        na_draw_arrowhead_at_destination(entities, axis, distance_mm)

        na_paint_helper_edges_red(mve_group)

        DebugTools.na_debug_geometry(
            "Built bifold MVE marker MVE#{format('%03d', mve_index.to_i)} (axis=#{axis}, d=#{distance_mm.to_i}mm)"
        )
        mve_group
    rescue StandardError => e
        DebugTools.na_debug_error("na_build_movement_pivot failed", e)
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Resolve Track Endpoint in Local mm Coordinates
    # ------------------------------------------------------------
    # Returns the destination point in mm given the axis letter + signed
    # distance. Y axis falls back to a vertical track line when needed
    # (rare for bifold; common for sliding sashes).
    def self.na_resolve_endpoint_mm(axis, distance_mm)
        case axis.to_s.upcase
        when "X" then [distance_mm.to_f, 0.0, 0.0]
        when "Y" then [0.0, distance_mm.to_f, 0.0]
        else          [distance_mm.to_f, 0.0, 0.0]
        end
    end
    private_class_method :na_resolve_endpoint_mm
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw the Linear Track Line from Origin to Destination
    # ------------------------------------------------------------
    def self.na_draw_track_line(entities, axis, distance_mm)
        endpoint_mm = na_resolve_endpoint_mm(axis, distance_mm)
        p0 = na_local_point_in(0.0, 0.0, 0.0)
        p1 = na_local_point_in(endpoint_mm[0], endpoint_mm[1], endpoint_mm[2])
        edge = entities.add_line(p0, p1)
        na_apply_helper_tag(edge)
    end
    private_class_method :na_draw_track_line
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw a 50x50mm '+' Crosshair at the Track Origin
    # ------------------------------------------------------------
    def self.na_draw_crosshair_at_origin(entities)
        na_draw_crosshair_at_local(entities, 0.0, 0.0, 0.0)
    end
    private_class_method :na_draw_crosshair_at_origin
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw a 50x50mm '+' Crosshair at the Track Destination
    # ------------------------------------------------------------
    def self.na_draw_crosshair_at_destination(entities, axis, distance_mm)
        endpoint_mm = na_resolve_endpoint_mm(axis, distance_mm)
        na_draw_crosshair_at_local(entities, endpoint_mm[0], endpoint_mm[1], endpoint_mm[2])
    end
    private_class_method :na_draw_crosshair_at_destination
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw a Generic Crosshair at a Local mm Point
    # ------------------------------------------------------------
    def self.na_draw_crosshair_at_local(entities, x_mm, y_mm, z_mm)
        half = NA_CROSSHAIR_HALF_LENGTH_MM
        x_edge = entities.add_line(
            na_local_point_in(x_mm - half, y_mm,        z_mm),
            na_local_point_in(x_mm + half, y_mm,        z_mm)
        )
        na_apply_helper_tag(x_edge)
        y_edge = entities.add_line(
            na_local_point_in(x_mm,        y_mm - half, z_mm),
            na_local_point_in(x_mm,        y_mm + half, z_mm)
        )
        na_apply_helper_tag(y_edge)
    end
    private_class_method :na_draw_crosshair_at_local
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Draw a 'V' Arrowhead at the Track Destination
    # ------------------------------------------------------------
    # Arrowhead tip points along the travel axis; wings fan back at 45 deg.
    def self.na_draw_arrowhead_at_destination(entities, axis, distance_mm)
        endpoint_mm = na_resolve_endpoint_mm(axis, distance_mm)
        return if endpoint_mm[0] == 0.0 && endpoint_mm[1] == 0.0

        head_mm  = NA_ARROW_HEAD_LENGTH_MM
        sign_x   = endpoint_mm[0].zero? ? 0.0 : (endpoint_mm[0] <=> 0).to_f
        sign_y   = endpoint_mm[1].zero? ? 0.0 : (endpoint_mm[1] <=> 0).to_f

        if sign_x.abs > 0.0
            wing_a = na_local_point_in(endpoint_mm[0] - sign_x * head_mm, +head_mm, endpoint_mm[2])
            wing_b = na_local_point_in(endpoint_mm[0] - sign_x * head_mm, -head_mm, endpoint_mm[2])
        else
            wing_a = na_local_point_in(+head_mm, endpoint_mm[1] - sign_y * head_mm, endpoint_mm[2])
            wing_b = na_local_point_in(-head_mm, endpoint_mm[1] - sign_y * head_mm, endpoint_mm[2])
        end

        tip   = na_local_point_in(endpoint_mm[0], endpoint_mm[1], endpoint_mm[2])
        edge_a = entities.add_line(tip, wing_a)
        edge_b = entities.add_line(tip, wing_b)
        na_apply_helper_tag(edge_a)
        na_apply_helper_tag(edge_b)
    end
    private_class_method :na_draw_arrowhead_at_destination
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
    def self.na_paint_helper_edges_red(mve_group)
        return unless mve_group && mve_group.respond_to?(:valid?) && mve_group.valid?
        EdgeColourManager.na_apply_edge_colour_to_group(mve_group, NA_HELPER_EDGE_COLOUR_ID)
    end
    private_class_method :na_paint_helper_edges_red
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__MovementPivotBuilder
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
