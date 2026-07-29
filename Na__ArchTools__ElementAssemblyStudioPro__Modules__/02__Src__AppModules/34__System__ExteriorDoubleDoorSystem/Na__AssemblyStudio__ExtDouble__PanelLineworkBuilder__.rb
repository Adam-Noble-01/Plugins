# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - PANEL LINEWORK BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDouble__PanelLineworkBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem
# MODULE     : Na__PanelLineworkBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Delegates to the shared exterior-door linework builder, supplying
#              the double-door naming context so group names remain byte-identical.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLineworkBuilder__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLineworkBuilder__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelLineworkBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    SharedBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelLineworkBuilder
    NA_NAMING     = { :container => 'Na__ExteriorDoubleDoor' }.freeze                      # <-- Group name prefix

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build Linework Fielded Panel Geometry for One Leaf
    # ------------------------------------------------------------
    def self.na_build(entities, leaf, panel_layout, material = nil, edge_colour_id: nil)
        SharedBuilder.na_build(
            entities, leaf, panel_layout, material, NA_NAMING,
            edge_colour_id: edge_colour_id
        )
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__PanelLineworkBuilder
end # module Na__ExteriorDoubleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
