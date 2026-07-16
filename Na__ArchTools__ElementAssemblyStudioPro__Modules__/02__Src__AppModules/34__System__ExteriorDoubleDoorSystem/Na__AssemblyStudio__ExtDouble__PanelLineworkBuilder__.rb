# frozen_string_literal: true

# =============================================================================
# EXTERIOR DOUBLE DOOR - PANEL LINEWORK BUILDER (DELEGATOR)
# -----------------------------------------------------------------------------
# Delegates to the shared exterior-door linework builder, supplying the
# double-door naming context so group names remain byte-identical.
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLineworkBuilder__.rb
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__PanelLineworkBuilder__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__PanelLineworkBuilder

    SharedBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__PanelLineworkBuilder
    NA_NAMING = { :container => 'Na__ExteriorDoubleDoor' }.freeze

    def self.na_build(entities, leaf, panel_layout, material = nil, edge_colour_id: nil)
        SharedBuilder.na_build(
            entities, leaf, panel_layout, material, NA_NAMING,
            edge_colour_id: edge_colour_id
        )
    end

end
end
end
