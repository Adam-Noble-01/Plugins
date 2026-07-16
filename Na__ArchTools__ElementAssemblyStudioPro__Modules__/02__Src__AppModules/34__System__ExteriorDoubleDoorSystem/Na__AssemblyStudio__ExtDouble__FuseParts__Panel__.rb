# frozen_string_literal: true

# =============================================================================
# EXTERIOR DOUBLE DOOR - FUSE PARTS (DELEGATOR)
# -----------------------------------------------------------------------------
# Delegates to the shared exterior-door fuse pipeline, supplying the double-door
# naming context so the joinery/glaze/glass/frame fuse behaviour is unchanged.
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__FuseParts__Panel__.rb
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__FuseParts__Panel__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__FuseParts__Panel

    SharedFuse = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__FuseParts__Panel
    NA_NAMING = { :container => 'Na__ExteriorDoubleDoor' }.freeze

    def self.na_fuse_exterior_double_door(entities)
        SharedFuse.na_fuse_door(entities, NA_NAMING)
    end

end
end
end
