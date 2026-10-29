# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - CARCASS BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__CarcassBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__CarcassBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds the carcass from a resolved layout: sides, base panel,
#              top rails or top panel, back panel, shelves (adjustable, the
#              fixed split shelf, the wardrobe top shelf) and the hanging rail.
# CREATED    : 29-Oct-2026
#
# DESCRIPTION:
# - Every board is its own named solid group inside Na__Cabinet__Carcass, so
#   a cutting list can be read straight off the Outliner.
# - Positions come from Na__LayoutResolver; nothing is measured here.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__CarcassBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryHelpers

        NA_GROUP_NAME     = "Na__Cabinet__Carcass".freeze
        NA_PART_PREFIX    = "Na__Carcass__".freeze
        NA_RAIL_SEGMENTS  = 16

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Carcass Group
        # ------------------------------------------------------------
        # @param layout   [Hash] Na__LayoutResolver.na_resolve result
        # @param entities [Sketchup::Entities] the cabinet definition's
        # @param materials [Hash] { :carcass, :handle }
        # @return [Sketchup::Group]
        def self.na_build(layout, entities, materials)
            group = GeometryHelpers.na_add_group(entities, NA_GROUP_NAME)
            layout[:parts].each do |part|
                GeometryHelpers.na_add_box_part(group.entities, part, NA_PART_PREFIX, materials[:carcass])
            end
            na_build_hanging_rail(layout[:rail], group.entities, materials[:handle]) if layout[:rail]
            DebugTools.na_debug_geometry("Cabinet carcass: #{layout[:parts].length} boards")
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Hanging Rail
# -----------------------------------------------------------------------------

        # SUB FUNCTION | A Round Wardrobe Rail Between the Sides
        # ------------------------------------------------------------
        def self.na_build_hanging_rail(rail, entities, material)
            group   = GeometryHelpers.na_add_group(entities, "#{NA_PART_PREFIX}#{rail[:name]}")
            profile = GeometryHelpers.na_circle_profile(rail[:diameter] / 2.0, NA_RAIL_SEGMENTS)
            GeometryHelpers.na_add_prism(
                group.entities, profile,
                [rail[:x0], rail[:y], rail[:z]], [0, 1, 0], [0, 0, 1], [1, 0, 0],
                rail[:x1] - rail[:x0], material, (0...NA_RAIL_SEGMENTS).to_a
            )
            group
        end
        private_class_method :na_build_hanging_rail
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__CarcassBuilder
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
