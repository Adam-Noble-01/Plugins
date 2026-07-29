# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - PANEL GEOMETRY BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDouble__PanelGeometryBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem
# MODULE     : Na__PanelGeometryBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Delegates to the shared exterior-door 3D fielded-panel builder,
#              supplying the double-door naming context so group names remain
#              byte-identical.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelGeometryBuilder__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelGeometryBuilder__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelGeometryBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    SharedBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelGeometryBuilder
    NA_NAMING     = { :container => 'Na__ExteriorDoubleDoor' }.freeze                      # <-- Group name prefix

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build 3D Fielded Panel Geometry for One Leaf
    # ------------------------------------------------------------
    def self.na_build(entities, leaf, panel_layout, material = nil)
        SharedBuilder.na_build(entities, leaf, panel_layout, material, NA_NAMING)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__PanelGeometryBuilder
end # module Na__ExteriorDoubleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
