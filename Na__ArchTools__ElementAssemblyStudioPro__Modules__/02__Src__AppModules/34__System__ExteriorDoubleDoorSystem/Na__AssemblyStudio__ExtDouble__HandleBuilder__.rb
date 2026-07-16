# frozen_string_literal: true

# =============================================================================
# EXTERIOR DOUBLE DOOR - HANDLE BUILDER (DELEGATOR)
# -----------------------------------------------------------------------------
# Maps double_door_* handle keys into the shared handle_config and delegates to
# the shared exterior-door handle builder. Active-leaf-only placement is
# preserved here (the composer decides which leaf(s) receive a handle).
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__HandleBuilder__.rb
# =============================================================================

require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__HandleBuilder__'
require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__HandleBuilder

    SharedHandleBuilder = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__HandleBuilder
    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers

    def self.na_build_active_leaf_handle(config, entities, leaf, material = nil)
        return { :interior => nil, :exterior => nil } unless leaf[:is_active]
        na_build_leaf_handle(config, entities, leaf, material)
    end

    def self.na_build_leaf_handle(config, entities, leaf, material = nil)
        SharedHandleBuilder.na_build_leaf_handle(na_handle_config(config), entities, leaf, material)
    end

    def self.na_handle_config(config)
        {
            :asset_key => config['double_door_handle_asset_key'],
            :height_mm => GeometryHelpers.na_number(config, 'double_door_handle_height_mm', 900),
            :backset_mm => GeometryHelpers.na_number(config, 'double_door_handle_backset_mm', 40),
            :swing_direction => config['double_door_swing_direction'] || 'Inward'
        }
    end
    private_class_method :na_handle_config

end
end
end
