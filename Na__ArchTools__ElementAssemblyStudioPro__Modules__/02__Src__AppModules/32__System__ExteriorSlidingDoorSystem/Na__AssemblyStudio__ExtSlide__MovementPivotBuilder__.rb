# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR MOVEMENT PIVOT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__MovementPivotBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem
# MODULE     : Na__MovementPivotBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Build the per-leaf MVE marker groups consumed by the
#              TrueVision3D click-to-open animation. Mirrors the bifold
#              `Na__MovementPivotBuilder` but emits `MVE###__MovementPoint
#              __SlidingPanelTrack` markers and limits travel to the
#              opening-X axis.
# CREATED    : 17-May-2026
#
# DESCRIPTION:
# - Each MVE marker is a SketchUp::Group whose origin is the leaf's
#   CLOSED-state hinge-edge position (start of the track displacement).
# - Helper geometry consists of:
#     * Linear track line from origin to (origin + axis * distance).
#     * 50x50 mm crosshair at both ends of the track line.
#     * Arrowhead at the destination indicating travel direction.
# - All edges live on the `:door_helpers` role tag and are painted red
#   via `MTE201__LineColour__Red`. The helper tag's `02__` prefix is in
#   the GLB exporter skipRanges so the helper geometry never reaches
#   production GLBs - only the marker GROUP NODE NAME survives.
#
# COORDINATE SYSTEM (MVE-local):
# - Origin       = closed-state leaf top edge (panel-local 0, 0, 0).
# - X+           = along the track axis.
# - Y+           = through the wall depth.
# - Z+           = upwards.
#
# PHASE-4 NOTE:
# This file is a near-clone of the bifold MovementPivotBuilder. Phase 4
# extracts the shared drawing logic into a common marker builder under
# `04__GeometryHelpers/`. Today the duplication is intentional so each
# system can ship/iterate independently of the other.
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.2.0
# - Phase-3b implementation: full MVE marker emission for sliding leaves.
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
module Na__MovementPivotBuilder

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
    NA_ARROW_HEAD_LENGTH_MM         = 25                                        # <-- Length of each arrowhead 'V' edge
    NA_HELPER_EDGE_COLOUR_ID        = "MTE201__LineColour__Red".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build an MVE Marker for a Single Sliding Leaf
    # ------------------------------------------------------------
    # Creates an empty group at `origin_point`, names it per the sliding
    # MVE format (MVE###__MovementPoint__SlidingPanelTrack), and fills
    # it with red track helper geometry inside the group's local frame.
    #
    # @param parent_entities [Sketchup::Entities] target entities
    # @param origin_point    [Geom::Point3d] closed-state leaf top (inches)
    # @param mve_index       [Integer] 1-based MVE marker index
    # @param axis            [String]  "X" - axis of translation (always X for sliding)
    # @param distance_mm     [Integer] signed translation magnitude in mm
    # @return [Sketchup::Group, nil]
    def self.na_build_movement_pivot(parent_entities, origin_point, mve_index, axis, distance_mm)
        return nil unless parent_entities
        return nil unless origin_point.is_a?(Geom::Point3d)
        return nil if axis.nil? || distance_mm.to_i == 0

        mve_group        = parent_entities.add_group
        mve_group.name   = format(
            Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::NA_MVE_NAME_FORMAT,
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
            "Built sliding MVE marker MVE#{format('%03d', mve_index.to_i)} (axis=#{axis}, d=#{distance_mm.to_i}mm)"
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

    def self.na_resolve_endpoint_mm(axis, distance_mm)
        case axis.to_s.upcase
        when "X" then [distance_mm.to_f, 0.0, 0.0]
        when "Y" then [0.0, distance_mm.to_f, 0.0]
        else          [distance_mm.to_f, 0.0, 0.0]
        end
    end
    private_class_method :na_resolve_endpoint_mm

    def self.na_draw_track_line(entities, axis, distance_mm)
        endpoint_mm = na_resolve_endpoint_mm(axis, distance_mm)
        p0 = na_local_point_in(0.0, 0.0, 0.0)
        p1 = na_local_point_in(endpoint_mm[0], endpoint_mm[1], endpoint_mm[2])
        edge = entities.add_line(p0, p1)
        na_apply_helper_tag(edge)
    end
    private_class_method :na_draw_track_line

    def self.na_draw_crosshair_at_origin(entities)
        na_draw_crosshair_at_local(entities, 0.0, 0.0, 0.0)
    end
    private_class_method :na_draw_crosshair_at_origin

    def self.na_draw_crosshair_at_destination(entities, axis, distance_mm)
        endpoint_mm = na_resolve_endpoint_mm(axis, distance_mm)
        na_draw_crosshair_at_local(entities, endpoint_mm[0], endpoint_mm[1], endpoint_mm[2])
    end
    private_class_method :na_draw_crosshair_at_destination

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

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Math + Tagging
# -----------------------------------------------------------------------------

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

    def self.na_paint_helper_edges_red(mve_group)
        return unless mve_group && mve_group.respond_to?(:valid?) && mve_group.valid?
        EdgeColourManager.na_apply_edge_colour_to_group(mve_group, NA_HELPER_EDGE_COLOUR_ID)
    end
    private_class_method :na_paint_helper_edges_red

# endregion -------------------------------------------------------------------

end # module Na__MovementPivotBuilder
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
