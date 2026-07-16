# frozen_string_literal: true

# =============================================================================
# EXTERIOR DOUBLE DOOR - ROTATION PIVOT BUILDER (DELEGATOR)
# -----------------------------------------------------------------------------
# Delegates to the shared exterior-door ROT helper builder, supplying the
# double-door ROT marker suffix (NA_ROT_SUFFIX defined in Init).
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__RotationPivotBuilder__.rb
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__RotationPivotBuilder__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__RotationPivotBuilder

    SharedBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__RotationPivotBuilder

    def self.na_build(parent_entities, leaf)
        SharedBuilder.na_build(parent_entities, leaf, NA_ROT_SUFFIX)
    end

end
end
end
