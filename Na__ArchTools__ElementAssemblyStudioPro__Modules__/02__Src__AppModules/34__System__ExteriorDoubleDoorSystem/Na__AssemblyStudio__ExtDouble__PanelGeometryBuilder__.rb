# frozen_string_literal: true

# =============================================================================
# EXTERIOR DOUBLE DOOR - PANEL GEOMETRY BUILDER (DELEGATOR)
# -----------------------------------------------------------------------------
# Delegates to the shared exterior-door 3D fielded-panel builder, supplying the
# double-door naming context so group names remain byte-identical.
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelGeometryBuilder__.rb
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelGeometryBuilder__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelGeometryBuilder

    SharedBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelGeometryBuilder
    NA_NAMING = { :container => 'Na__ExteriorDoubleDoor' }.freeze

    def self.na_build(entities, leaf, panel_layout, material = nil)
        SharedBuilder.na_build(entities, leaf, panel_layout, material, NA_NAMING)
    end

end
end
end
