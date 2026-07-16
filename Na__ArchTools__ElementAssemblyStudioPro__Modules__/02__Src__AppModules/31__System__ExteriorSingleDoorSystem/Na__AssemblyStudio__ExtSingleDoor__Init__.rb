# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - INIT
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# PURPOSE    : Standalone exterior single door system bootstrap - constants,
#              default config, lazy module loading, AppCore registration.
#              Overhauled from the legacy no-op panel sub-module into a full
#              standalone door product (ADR ids, ROT logic, fielded panels,
#              handles) mirroring the Exterior Double Door System.
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem

    DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

    NA_MODULE_ROOT_PATH      = File.dirname(__FILE__).freeze
    NA_DOOR_ID_REGEX         = /^ADR\d{3}$/.freeze
    NA_DEFINITION_SUFFIX     = '__ExteriorSingleDoor__'.freeze
    NA_PANEL_TAG             = 'ExteriorSingleDoorPanel'.freeze
    NA_ROT_SUFFIX            = 'ExteriorSingleDoorHingeCentre'.freeze

    NA_DOOR_INFO_DICT        = 'Na__ExteriorSingleDoorConfiguratorInfo'.freeze
    NA_DOOR_DEF_DICT_PREFIX  = 'Na__ExteriorSingleDoorConfigurator_'.freeze
    NA_KEY_DOOR_ID           = 'DoorID'.freeze
    NA_KEY_INSTANCE_NAME     = 'SketchUpInstanceName'.freeze
    NA_KEY_DEFINITION_NAME   = 'SketchUpDefinitionName'.freeze
    NA_KEY_METADATA          = 'Na__ExteriorSingleDoorMetadata'.freeze
    NA_KEY_COMPONENTS        = 'Na__ExteriorSingleDoorComponents'.freeze
    NA_KEY_CONFIGURATION     = 'Na__ExteriorSingleDoorConfiguration'.freeze

    NA_DEFAULT_DOOR_CONFIG = {
        'ext_single_door_mode'                     => false,
        'single_door_swing_side'                   => 'Left',
        'single_door_swing_direction'              => 'Inward',
        'single_door_opening_angle_deg'            => 90,
        'single_door_hinge_projection_mm'          => 0,
        'single_door_show_swing_arcs'              => true,
        'single_door_create_open_state_copy'       => true,
        'single_door_removed_glazebars'            => [],
        'single_door_leaf_composition'             => 'GlazedOverFielded',
        'single_door_panel_output_mode'            => 'ThreeDimensional',
        'single_door_panel_profile'                => 'RaisedBevelled',
        'single_door_panel_preset'                 => 'OnePanel',
        'single_door_panel_columns'                => 1,
        'single_door_panel_rows'                   => 1,
        'single_door_fielded_section_height_mm'    => 300,
        'single_door_mid_rail_width_mm'            => 120,
        'single_door_panel_stile_width_mm'         => 95,
        'single_door_panel_top_rail_width_mm'      => 95,
        'single_door_panel_bottom_rail_width_mm'   => 150,
        'single_door_panel_inset_mm'               => 25,
        'single_door_panel_depth_mm'               => 12,
        'single_door_panel_bevel_width_mm'         => 18,
        'single_door_leaf_thickness_mm'            => 50,
        'single_door_leaf_material_id'             => 'MAT120__GenericWood',
        'single_door_handle_asset_key'             => 'Na__ExteriorDoor__Handle__Scroll',
        'single_door_handle_material_id'           => 'MAT615__Metal__Ironmongery__Chrome',
        'single_door_handle_height_mm'             => 900,
        'single_door_handle_backset_mm'            => 40
    }.freeze

    def self.na_default_config
        Marshal.load(Marshal.dump(NA_DEFAULT_DOOR_CONFIG))
    end

    def self.na_default_config_json
        JSON.generate(NA_DEFAULT_DOOR_CONFIG)
    end

    def self.na_require_modules
        return if @na_modules_loaded
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__GeometryHelpers__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__LeafLayoutResolver__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__PanelLayoutResolver__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__HandleBuilder__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__RotationPivotBuilder__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__FuseParts__Panel__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__AssemblyComposer__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__DataSerializer__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__GeometryEngine__'
        require_relative 'Na__AssemblyStudio__ExtSingleDoor__SelectionHandler__'
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
            Na__ExteriorSingleDoorSystem.na_require_modules
            if defined?(Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator)
                coordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator
                coordinator.na_register_handler(
                    Na__ExteriorSingleDoorSystem::Na__SelectionHandler.na_handler_descriptor
                )
            end
            if defined?(Na__AssemblyStudio::Na__AppCore::Na__DialogManager)
                dialog_manager = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
                dialog_manager.na_register_system_init_hook do |dialog|
                    Na__ExteriorSingleDoorSystem.na_init_callbacks(dialog)
                end
            end
            true
        end
    end

end
end
