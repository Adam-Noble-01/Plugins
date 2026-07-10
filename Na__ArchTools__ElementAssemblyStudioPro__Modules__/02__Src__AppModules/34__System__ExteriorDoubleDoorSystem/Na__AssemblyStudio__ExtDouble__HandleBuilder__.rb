# frozen_string_literal: true

require_relative '../40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__'
require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__HandleBuilder

    InteriorHandleBuilder = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__HandleBuilder3D
    GeometryHelpers = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__GeometryHelpers

    def self.na_build_active_leaf_handle(config, entities, leaf, material = nil)
        return { :interior => nil, :exterior => nil } unless leaf[:is_active]

        adapter_config = na_adapter_config(config, leaf)
        adapter_leaf = na_adapter_leaf(config, leaf)
        InteriorHandleBuilder.na_build_handles(adapter_config, entities, material, adapter_leaf)
    end

    def self.na_adapter_config(config, leaf)
        dimensions = leaf[:dimensions]
        {
            'Na__DoorConfig__HandleAssetKey' => config['double_door_handle_asset_key'],
            'Na__DoorConfig__HandleHeight_mm' => GeometryHelpers.na_number(config, 'double_door_handle_height_mm', 1000),
            'Na__DoorConfig__OpeningWidth_mm' => dimensions[:width_mm],
            'Na__DoorConfig__LiningThickness_mm' => 0,
            'Na__DoorConfig__PanelThickness_mm' => leaf[:thickness_mm],
            'Na__DoorConfig__WallDepth_mm' => dimensions[:frame_depth_mm],
            'Na__DoorConfig__LiningFaceOffset_mm' => dimensions[:frame_wall_inset_mm],
            'Na__DoorConfig__SwingDirection' => config['double_door_swing_direction'] || 'Inward',
            'Na__DoorConfig__SwingSide' => leaf[:side_name]
        }
    end
    private_class_method :na_adapter_config

    def self.na_adapter_leaf(config, leaf)
        backset = GeometryHelpers.na_clamp(
            GeometryHelpers.na_number(config, 'double_door_handle_backset_mm', 60),
            20,
            [leaf[:width_mm] / 2.0, 20].max
        )
        {
            :index => leaf[:index],
            :swing_side => leaf[:side].to_s,
            :origin_x_mm => leaf[:origin_x_mm],
            :hinge_x_mm => leaf[:hinge_x_mm],
            :leaf_w_mm => [leaf[:width_mm] - backset, 1.0].max
        }
    end
    private_class_method :na_adapter_leaf

end
end
end
