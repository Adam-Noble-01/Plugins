# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - FUSE PARTS (PANEL)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__FuseParts__Panel__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__FuseParts__Panel
# AUTHOR     : Noble Architecture
# PURPOSE    : Delegates to the shared exterior-door fuse pipeline with the
#              single-door naming context. Distinct from the legacy
#              FuseParts__DoorPanel used by the WindowSystem door_mode path.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__FuseParts__Panel__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__FuseParts__Panel__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__FuseParts__Panel

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    SharedFuse = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__FuseParts__Panel

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_NAMING = { :container => 'Na__ExteriorSingleDoor' }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Fuse Exterior Single Door Joinery + Glaze Bars + Frame
    # ------------------------------------------------------------
    def self.na_fuse_exterior_single_door(entities)
        SharedFuse.na_fuse_door(entities, NA_NAMING)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__FuseParts__Panel
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
