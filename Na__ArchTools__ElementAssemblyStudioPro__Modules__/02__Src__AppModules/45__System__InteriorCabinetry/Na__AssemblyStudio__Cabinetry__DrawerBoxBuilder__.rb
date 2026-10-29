# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - DRAWER BOX BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__DrawerBoxBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__DrawerBoxBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds a drawer box behind each drawer front: two sides, an
#              inner front, a back and a base, as named solid groups.
# CREATED    : 29-Oct-2026
#
# DESCRIPTION:
# - Sizes come from Na__LayoutResolver: 13mm runner space each side, 15mm
#   sides, a 6mm base, a box length in 50s (500 in a 560 carcass).
# - Off with Output > Build Drawer Boxes for lighter whole-house models.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__DrawerBoxBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        GeometryHelpers = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryHelpers

        NA_GROUP_NAME  = "Na__Cabinet__DrawerBoxes".freeze
        NA_PART_PREFIX = "Na__".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build Every Drawer Box (Nil When There Are None)
        # ------------------------------------------------------------
        # @return [Sketchup::Group, nil]
        def self.na_build(layout, entities, materials)
            return nil if layout[:drawer_boxes].empty?
            group = GeometryHelpers.na_add_group(entities, NA_GROUP_NAME)
            layout[:drawer_boxes].each do |box|
                box_group = GeometryHelpers.na_add_group(group.entities, "#{NA_PART_PREFIX}#{box[:name]}")
                box[:parts].each do |part|
                    GeometryHelpers.na_add_box_part(box_group.entities, part, NA_PART_PREFIX, materials[:carcass])
                end
            end
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DrawerBoxBuilder
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
