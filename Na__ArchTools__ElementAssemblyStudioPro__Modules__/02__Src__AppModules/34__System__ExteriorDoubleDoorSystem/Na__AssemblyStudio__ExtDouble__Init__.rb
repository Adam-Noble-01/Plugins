# frozen_string_literal: true

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem

    DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

    NA_MODULE_ROOT_PATH      = File.dirname(__FILE__).freeze
    NA_DOOR_ID_REGEX         = /^ADR\d{3}$/.freeze
    NA_DEFINITION_SUFFIX     = '__ExteriorDoubleDoor__'.freeze
    NA_PANEL_TAG             = 'ExteriorDoubleDoorPanel'.freeze
    NA_ROT_SUFFIX            = 'ExteriorDoubleDoorHingeCentre'.freeze

    NA_DOOR_INFO_DICT        = 'Na__ExteriorDoubleDoorConfiguratorInfo'.freeze
    NA_DOOR_DEF_DICT_PREFIX  = 'Na__ExteriorDoubleDoorConfigurator_'.freeze
    NA_KEY_DOOR_ID           = 'DoorID'.freeze
    NA_KEY_INSTANCE_NAME     = 'SketchUpInstanceName'.freeze
    NA_KEY_DEFINITION_NAME   = 'SketchUpDefinitionName'.freeze
    NA_KEY_METADATA          = 'Na__ExteriorDoubleDoorMetadata'.freeze
    NA_KEY_COMPONENTS        = 'Na__ExteriorDoubleDoorComponents'.freeze
    NA_KEY_CONFIGURATION     = 'Na__ExteriorDoubleDoorConfiguration'.freeze

    NA_DEFAULT_DOOR_CONFIG = {
        'double_door_mode'                         => false,
        'double_door_active_leaf'                  => 'Left',
        'double_door_active_leaf_width_mm'         => 'EQ',
        'double_door_swing_direction'              => 'Inward',
        'double_door_left_opening_angle_deg'       => 90,
        'double_door_right_opening_angle_deg'      => 90,
        'double_door_left_hinge_projection_mm'     => 0,
        'double_door_right_hinge_projection_mm'    => 0,
        'double_door_show_swing_arcs'              => true,
        'double_door_create_open_state_copy'       => true,
        'double_door_removed_glazebars'             => [],
        'double_door_leaf_settings_linked'         => true,
        'double_door_left_leaf_override_enabled'   => false,
        'double_door_right_leaf_override_enabled'  => false,
        'double_door_leaf_composition'             => 'GlazedOverFielded',
        'double_door_panel_output_mode'            => 'ThreeDimensional',
        'double_door_panel_profile'                => 'RaisedBevelled',
        'double_door_panel_preset'                 => 'OnePanel',
        'double_door_panel_columns'                => 1,
        'double_door_panel_rows'                   => 1,
        'double_door_fielded_section_height_mm'    => 300,
        'double_door_mid_rail_width_mm'            => 120,
        'double_door_panel_stile_width_mm'         => 95,
        'double_door_panel_top_rail_width_mm'      => 95,
        'double_door_panel_bottom_rail_width_mm'   => 150,
        'double_door_panel_rail_width_mm'          => 150,
        'double_door_panel_inset_mm'               => 25,
        'double_door_panel_depth_mm'               => 12,
        'double_door_panel_bevel_width_mm'         => 18,
        'double_door_leaf_thickness_mm'            => 50,
        'double_door_leaf_material_id'             => 'MAT120__GenericWood',
        'double_door_handle_pairing'               => 'Paired',
        'double_door_handle_asset_key'             => 'Na__ExteriorDoor__Handle__Scroll',
        'double_door_handle_material_id'            => 'MAT615__Metal__Ironmongery__Chrome',
        'double_door_handle_height_mm'              => 900,
        'double_door_handle_backset_mm'             => 40
    }.freeze

    def self.na_default_config
        Marshal.load(Marshal.dump(NA_DEFAULT_DOOR_CONFIG))
    end

    def self.na_default_config_json
        JSON.generate(NA_DEFAULT_DOOR_CONFIG)
    end

    def self.na_require_modules
        return if @na_modules_loaded

        # @delegate: Na__AssemblyStudio__ExtDouble__GeometryHelpers__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__GeometryHelpers__'
        # @delegate: Na__AssemblyStudio__ExtDouble__LeafLayoutResolver__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__LeafLayoutResolver__'
        # @delegate: Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__'
        # @delegate: Na__AssemblyStudio__ExtDouble__PanelLineworkBuilder__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__PanelLineworkBuilder__'
        # @delegate: Na__AssemblyStudio__ExtDouble__PanelGeometryBuilder__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__PanelGeometryBuilder__'
        # @delegate: Na__AssemblyStudio__ExtDouble__HandleBuilder__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__HandleBuilder__'
        # @delegate: Na__AssemblyStudio__ExtDouble__RotationPivotBuilder__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__RotationPivotBuilder__'
        # @delegate: Na__AssemblyStudio__ExtDouble__AssemblyComposer__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__AssemblyComposer__'
        # @delegate: Na__AssemblyStudio__ExtDouble__FuseParts__Panel__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__FuseParts__Panel__'
        # @delegate: Na__AssemblyStudio__ExtDouble__DataSerializer__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__DataSerializer__'
        # @delegate: Na__AssemblyStudio__ExtDouble__GeometryEngine__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__GeometryEngine__'
        # @delegate: Na__AssemblyStudio__ExtDouble__SelectionHandler__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__SelectionHandler__'
        # @delegate: Na__AssemblyStudio__ExtDouble__DxfExporter__.rb
        require_relative 'Na__AssemblyStudio__ExtDouble__DxfExporter__'

        @na_modules_loaded = true
    end

    def self.na_reset_module_load_gate_for_developer_reload
        @na_modules_loaded = false
    end

    def self.na_init_callbacks(dialog)
        return false unless dialog
        na_require_modules
        true
    end

    module Na__Init
        def self.na_init
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__DialogManager__'
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__SelectionCoordinator__'
            Na__ExteriorDoubleDoorSystem.na_require_modules
            if defined?(Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator)
                coordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator
                coordinator.na_register_handler(
                    Na__ExteriorDoubleDoorSystem::Na__SelectionHandler.na_handler_descriptor
                )
            end
            if defined?(Na__AssemblyStudio::Na__AppCore::Na__DialogManager)
                dialog_manager = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
                dialog_manager.na_register_system_init_hook do |dialog|
                    Na__ExteriorDoubleDoorSystem.na_init_callbacks(dialog)
                end
            end
            true
        end
    end

end
end
