# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - LEAF LAYOUT RESOLVER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__LeafLayoutResolver__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__LeafLayoutResolver
# AUTHOR     : Noble Architecture
# PURPOSE    : Resolve the single door's one leaf descriptor (position, hinge,
#              swing, dimensions) in the same shape the shared ExtDoorCommon
#              builders and the AssemblyComposer consume. Returns a one-element
#              array so the composer leaf pipeline mirrors the double door.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtSingleDoor__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__LeafLayoutResolver

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve the Single Leaf Descriptor Array
    # ------------------------------------------------------------
    # @param config [Hash] Door configuration
    # @return [Array<Hash>] One-element frozen leaf array, or empty
    def self.na_resolve(config)
        return [] unless config.is_a?(Hash)

        dimensions = GeometryHelpers.na_resolve_opening_dimensions(config)
        return [] if dimensions[:inner_w_mm] <= 0 || dimensions[:inner_h_mm] <= 0

        panel_y = GeometryHelpers.na_panel_y_origin_mm(config, dimensions)
        [na_build_leaf(config, dimensions, panel_y).freeze].freeze
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Leaf Descriptor
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Build the Single Leaf Descriptor Hash
    # ------------------------------------------------------------
    def self.na_build_leaf(config, dimensions, panel_y)
        hinge_side = config['single_door_swing_side'].to_s.casecmp('Right').zero? ? :right : :left
        left_hinge = hinge_side == :left
        width = dimensions[:inner_w_mm]
        origin_x = dimensions[:inner_x_mm]
        hinge_x = left_hinge ? dimensions[:inner_x_mm] : dimensions[:inner_x_mm] + dimensions[:inner_w_mm]
        side_name = left_hinge ? 'Left' : 'Right'
        projection = GeometryHelpers.na_clamp(
            GeometryHelpers.na_number(config, 'single_door_hinge_projection_mm', 0), 0, 150
        )
        angle = GeometryHelpers.na_number(config, 'single_door_opening_angle_deg', 90)
        direction = config['single_door_swing_direction'] || 'Inward'

        {
            :index => 1,
            :side => hinge_side,
            :side_name => side_name,
            :hinge_side => hinge_side,
            :is_active => true,
            :origin_x_mm => origin_x,
            :origin_y_mm => panel_y,
            :origin_z_mm => dimensions[:inner_z_mm],
            :width_mm => width,
            :height_mm => dimensions[:inner_h_mm],
            :thickness_mm => [GeometryHelpers.na_number(config, 'single_door_leaf_thickness_mm', 50), 1.0].max,
            :hinge_x_mm => hinge_x,
            :pivot_y_mm => GeometryHelpers.na_hinge_pivot_y_mm(config, dimensions, projection),
            :hinge_projection_mm => projection,
            :opening_angle_deg => GeometryHelpers.na_clamp(angle, 0, 180).round,
            :signed_angle_deg => GeometryHelpers.na_signed_angle_deg(hinge_side, direction, angle),
            :closed_latch_angle_deg => left_hinge ? 0.0 : 180.0,
            :latch_x_mm => left_hinge ? origin_x + width : origin_x,
            :dimensions => dimensions.freeze
        }
    end
    private_class_method :na_build_leaf
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__LeafLayoutResolver
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
