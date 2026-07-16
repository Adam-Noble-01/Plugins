# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - ROTATION PIVOT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__RotationPivotBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__RotationPivotBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Delegates to the shared exterior-door ROT helper builder with
#              the single-door marker suffix (NA_ROT_SUFFIX defined in Init).
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__RotationPivotBuilder__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__RotationPivotBuilder__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__RotationPivotBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    SharedBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__RotationPivotBuilder

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build the ROT Helper Group for the Single Leaf
    # ------------------------------------------------------------
    def self.na_build(parent_entities, leaf)
        SharedBuilder.na_build(parent_entities, leaf, NA_ROT_SUFFIX)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__RotationPivotBuilder
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
