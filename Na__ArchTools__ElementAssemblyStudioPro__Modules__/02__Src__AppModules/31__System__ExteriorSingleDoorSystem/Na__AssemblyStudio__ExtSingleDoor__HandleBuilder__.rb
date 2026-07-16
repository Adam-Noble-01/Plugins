# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - HANDLE BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__HandleBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__HandleBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Adapter that maps single_door_* handle keys into the shared
#              handle_config and delegates to ExtDoorCommon. A single door
#              always carries exactly one interior + exterior handle pair.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__HandleBuilder__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__HandleBuilder__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__HandleBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    SharedHandleBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__HandleBuilder
    GeometryHelpers     = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build an Interior + Exterior Handle Pair on the Single Leaf
    # ------------------------------------------------------------
    def self.na_build_leaf_handle(config, entities, leaf, material = nil)
        SharedHandleBuilder.na_build_leaf_handle(na_handle_config(config), entities, leaf, material)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Config Mapping
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Map single_door_* Keys to Shared Handle Config
    # ------------------------------------------------------------
    def self.na_handle_config(config)
        {
            :asset_key => config['single_door_handle_asset_key'],
            :height_mm => GeometryHelpers.na_number(config, 'single_door_handle_height_mm', 900),
            :backset_mm => GeometryHelpers.na_number(config, 'single_door_handle_backset_mm', 40),
            :swing_direction => config['single_door_swing_direction'] || 'Inward'
        }
    end
    private_class_method :na_handle_config
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__HandleBuilder
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
