# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - PLINTH AND LEGS BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__PlinthLegsBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__PlinthLegsBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds the plinth board and places the adjustable legs of a
#              floor standing unit (base, drawer, tall, wardrobe).
# CREATED    : 29-Oct-2026
#
# DESCRIPTION:
# - The plinth runs the full width of the unit, so a run of units reads as
#   one plinth, set back from the carcass front and as tall as the legs.
# - Each leg is an instance of the leg asset's ComponentDefinition stretched
#   to the plinth height (Na__AssetMeshBuilder), standing on the floor with
#   its top plate under the carcass. All legs of one height share one
#   definition, so a kitchen of 4-leg units adds one leg definition.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__Cabinetry__AssetMeshBuilder__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__PlinthLegsBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        GeometryHelpers   = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryHelpers
        AssetMeshBuilder  = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__AssetMeshBuilder

        NA_PLINTH_PREFIX = "Na__Cabinet__".freeze
        NA_LEGS_GROUP    = "Na__Cabinet__Legs".freeze
        NA_LEG_NAME      = "Na__Cabinet__Leg__%02d".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Plinth Board (Nil When There Is None)
        # ------------------------------------------------------------
        # @return [Sketchup::Group, nil]
        def self.na_build_plinth(layout, entities, materials)
            return nil unless layout[:plinth]
            GeometryHelpers.na_add_box_part(entities, layout[:plinth], NA_PLINTH_PREFIX, materials[:plinth])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Place the Legs (Nil When There Are None)
        # ------------------------------------------------------------
        # @param leg_key [String] leg asset key
        # @return [Sketchup::Group, nil]
        def self.na_build_legs(layout, entities, leg_key, materials)
            return nil if layout[:legs].empty?
            definition = AssetMeshBuilder.na_leg_definition(leg_key, layout[:leg_height])
            unless definition
                DebugTools.na_debug_warn("Leg asset '#{leg_key}' could not be built - legs skipped")
                return nil
            end

            group = GeometryHelpers.na_add_group(entities, NA_LEGS_GROUP)
            layout[:legs].each_with_index do |leg, index|
                origin   = GeometryHelpers.na_point(leg[:x], leg[:y], 0.0)
                instance = group.entities.add_instance(definition, Geom::Transformation.new(origin))
                instance.name     = format(NA_LEG_NAME, index + 1)
                instance.material = materials[:leg] if materials[:leg]
            end
            na_paint_edges(group)
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Standard Dark Grey Edges, as on the Door Handles
        # ------------------------------------------------------------
        def self.na_paint_edges(group)
            EdgeColourManager.na_apply_edge_colour_to_group(group, EdgeColourManager::NA_DEFAULT_DARK_GREY_KEY)
        rescue StandardError => e
            DebugTools.na_debug_warn("Leg edge colour skipped: #{e.message}")
        end
        private_class_method :na_paint_edges
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PlinthLegsBuilder
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
