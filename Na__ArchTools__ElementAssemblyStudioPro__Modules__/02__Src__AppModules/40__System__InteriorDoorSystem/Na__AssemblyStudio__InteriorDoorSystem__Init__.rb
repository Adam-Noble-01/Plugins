# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM (MAIN ORCHESTRATOR)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__InteriorDoorSystem
# AUTHOR     : Noble Architecture
# PURPOSE    : Entry point for the Interior Door tab. Loads sub-modules,
#              owns module-level constants, and wires up dialog callbacks.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Sole entry point required by Element Assembly Studio Pro when the
#   user activates the Interior Doors tab in the shared HtmlDialog.
# - Centralises every constant the door subsystem needs (paths, dictionary
#   keys, default ADR identifiers, default configuration JSON).
# - Exposes a single public initialiser, na_init_door_callbacks(dialog),
#   that the parent Na__DialogManager calls after the HtmlDialog has been shown.
# - Stays out of the way of the Window System: it does not modify any
#   global state and never touches @window_component or window dictionaries.
#
# DEPENDENCIES (loaded in dependency order, helpers first):
# - Na__AssemblyStudio__AppUtils__DebugTools__
# - Na__AssemblyStudio__AppUtils__TagManager__
# - Na__AssemblyStudio__AppData__EdgeColourManager__
# - Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__
# - Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__
# - Na__AssemblyStudio__InteriorDoorSystem__DataSerializer__
# - Na__AssemblyStudio__InteriorDoorSystem__GeometryBuilders__
# - Na__AssemblyStudio__InteriorDoorSystem__ArchitraveBuilder__
# - Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__
# - Na__AssemblyStudio__InteriorDoorSystem__FuseLiningParts__
# - Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__
# - Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__VerticalNarrow__
# - Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__ClassicalSix__
# - Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__FourPanel__
# - Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__HorizontalThree__
# - Na__AssemblyStudio__InteriorDoorSystem__PanelDesignBuilder__
# - Na__AssemblyStudio__InteriorDoorSystem__RotationPivotBuilder__
# - Na__AssemblyStudio__InteriorDoorSystem__DoorAssemblyComposer__
# - Na__AssemblyStudio__InteriorDoorSystem__GeometryEngine__
# - Na__AssemblyStudio__MeasurementTools__ThreePointOpeningTool__ (06__Tools__MeasurementTools)
# - Na__AssemblyStudio__InteriorDoorSystem__DialogRouter__
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'json'
require 'sketchup.rb'

require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    TagManager     = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
    AssetLibrary   = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Path Resolution
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Plugin Layout Paths
    # ------------------------------------------------------------
    # Door UI markup lives directly inside the parent
    # Na__AssemblyStudio__UiLayout__.html (page-swap tab panel),
    # so no fragment HTML is loaded from here.
    NA_MODULE_ROOT_PATH         = File.dirname(__FILE__).freeze
    # v2/EASP: assets moved to root 04__Data__AssetLibrary so multiple systems can share.
    NA_ASSETS_ROOT_PATH         = File.expand_path(
        File.join(NA_MODULE_ROOT_PATH, "..", "..", "04__Data__AssetLibrary")
    ).freeze
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - ADR Door ID System
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Door ID Format
    # ------------------------------------------------------------
    NA_DOOR_ID_PREFIX            = "ADR".freeze                                # <-- ADR-series door codes
    NA_DOOR_ID_REGEX             = /^ADR\d{3}$/.freeze                         # <-- Validation pattern
    NA_DOOR_ID_FORMAT            = "ADR%03d".freeze                            # <-- sprintf format
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Component Naming Conventions (TrueVision compatible)
    # ------------------------------------------------------------
    NA_DEFINITION_SUFFIX_DOOR        = "__InteriorDoor__".freeze                          # <-- ComponentDefinition is the ADR (e.g. ADR013__InteriorDoor__); MOD/ROT are direct siblings inside its entities
    # MOD name is resolved per swing direction at build time by
    # Na__DoorAssemblyComposer.na_resolve_mod_panel_name(config) so
    # TrueVision3D's click-to-open animation parses the right sign and
    # rotates each door the correct way:
    NA_GROUP_NAME_MOD_PANEL_OUTWARD  = "MOD001__ROT__-90-Deg__DoorPanel".freeze            # <-- Outward swing -> clockwise from above in TV3D
    NA_GROUP_NAME_MOD_PANEL_INWARD   = "MOD001__ROT__90-Deg__DoorPanel".freeze             # <-- Inward  swing -> counterclockwise from above in TV3D
    NA_GROUP_NAME_MOD_PANEL          = NA_GROUP_NAME_MOD_PANEL_OUTWARD                     # <-- legacy alias, defaults to outward
    NA_GROUP_NAME_ROT_HINGE          = "ROT001__RotationPoint__DoorHingeCentre".freeze
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Dictionary Keys
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Definition / Instance Dictionary Names
    # ------------------------------------------------------------
    NA_DOOR_INFO_DICT            = "Na__DoorConfiguratorInfo".freeze           # <-- Dictionary on ComponentInstance
    NA_DOOR_DEF_DICT_PREFIX      = "Na__DoorConfigurator_".freeze              # <-- Prefix for ComponentDefinition dict
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Dictionary Keys (instance-side)
    # ------------------------------------------------------------
    NA_KEY_DOOR_ID               = "DoorID".freeze                             # <-- Instance attribute key
    NA_KEY_SU_INSTANCE_NAME      = "SketchUpInstanceName".freeze
    NA_KEY_SU_DEFINITION_NAME    = "SketchUpDefinitionName".freeze
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Dictionary Keys (definition-side, three blocks)
    # ------------------------------------------------------------
    NA_KEY_DOOR_METADATA         = "Na__DoorMetadata".freeze
    NA_KEY_DOOR_COMPONENTS       = "Na__DoorComponents".freeze
    NA_KEY_DOOR_CONFIGURATION    = "Na__DoorConfiguration".freeze
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Default Material IDs
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Default Material IDs (resolved against MaterialManager)
    # ------------------------------------------------------------
    NA_DEFAULT_LINING_MATERIAL_ID      = "MAT001__Default".freeze               # <-- Default lining material
    NA_DEFAULT_PANEL_MATERIAL_ID       = "MAT001__Default".freeze               # <-- Default door panel material
    NA_DEFAULT_ARCHITRAVE_MATERIAL_ID  = "MAT001__Default".freeze               # <-- Default architrave material
    NA_DEFAULT_HANDLE_MATERIAL_ID      = "MAT615__Metal__Ironmongery__Chrome".freeze  # <-- Default handle material (Chrome)
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Default Door Configuration JSON
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Default Door Configuration
    # ------------------------------------------------------------
    # Mirrors the structure of NA_DEFAULT_CONFIG_JSON in the Window
    # System. Three top-level blocks:
    #   * Na__DoorMetadata       (array, mirrors windowMetadata)
    #   * Na__DoorComponents     (array, mirrors windowComponents - reserved)
    #   * Na__DoorConfiguration  (hash,  mirrors windowConfiguration)
    # All numeric configuration values are millimetres unless suffixed.
    NA_DEFAULT_DOOR_CONFIG = {
        "Na__DoorMetadata" => [
            {
                "Na__Door__UniqueId"     => nil,
                "Na__Door__Name"         => "New Interior Door",
                "Na__Door__Description"  => "",
                "Na__Door__Notes"        => "Created with Element Assembly Studio Pro",
                "Na__Door__CreatedDate"  => nil,
                "Na__Door__LastModified" => nil
            }
        ],
        "Na__DoorComponents" => [],
        "Na__DoorConfiguration" => {
            "Na__DoorConfig__OpeningWidth_mm"        => 850,
            "Na__DoorConfig__OpeningHeight_mm"       => 2100,
            "Na__DoorConfig__WallDepth_mm"           => 105,
            "Na__DoorConfig__LiningThickness_mm"     => 35,
            "Na__DoorConfig__LiningFaceOffset_mm"    => 0,
            "Na__DoorConfig__PanelThickness_mm"      => 40,
            "Na__DoorConfig__PanelFloorClearance_mm" => 10,
            "Na__DoorConfig__ArchitraveProfileKey"   => "Na__Asset__Plan2D__Architrave__Default__w70mm_x_d20mm",
            "Na__DoorConfig__ArchitraveOffset_mm"    => 5,
            "Na__DoorConfig__ArchitraveFrontEnabled" => true,
            "Na__DoorConfig__ArchitraveBackEnabled"  => true,
            "Na__DoorConfig__SwingSide"              => "Left",
            "Na__DoorConfig__SwingDirection"         => "Inward",
            "Na__DoorConfig__HandleAssetKey"         => "Na__InteriorDoor__Handle__Default",
            "Na__DoorConfig__HandleHeight_mm"        => 900,
            "Na__DoorConfig__CreateOpenStateCopy"    => true,
            "Na__DoorConfig__FuseLining"             => true,
            "Na__DoorConfig__LiningMaterialId"       => NA_DEFAULT_LINING_MATERIAL_ID,
            "Na__DoorConfig__PanelMaterialId"        => NA_DEFAULT_PANEL_MATERIAL_ID,
            "Na__DoorConfig__ArchitraveMaterialId"   => NA_DEFAULT_ARCHITRAVE_MATERIAL_ID,
            "Na__DoorConfig__HandleMaterialId"       => NA_DEFAULT_HANDLE_MATERIAL_ID,
            "Na__DoorConfig__PanelDesignEnabled"            => true,
            "Na__DoorConfig__PanelDesignStyle"              => "None",
            "Na__DoorConfig__PanelDesignStileWidth_mm"      => 95,
            "Na__DoorConfig__PanelDesignTopRail_mm"         => 100,
            "Na__DoorConfig__PanelDesignBottomRail_mm"      => 200,
            "Na__DoorConfig__PanelDesignInnerRailThickness_mm" => 70,
            "Na__DoorConfig__PanelDesignVerticalPaneWidth_mm" => 90,
            "Na__DoorConfig__PanelDesignEdgeColourId"       => "MTE103__LineColour__DarkGrey__L40"
        }
    }.freeze
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Late-Bound Sub-Module Loading
# -----------------------------------------------------------------------------

    # FUNCTION | Load Sub-Modules in Dependency Order (Late Bound)
    # ------------------------------------------------------------
    # Called by na_init_door_callbacks the first time the door tab is
    # used, so that the parent tool can boot without any door module
    # loaded if the user never opens the door tab. All requires use
    # require_relative against this file's directory.
    def self.na_require_door_modules
        return if @na_door_modules_loaded

        require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__DataSerializer__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryBuilders__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__ArchitraveBuilder__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__FuseLiningParts__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__VerticalNarrow__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__ClassicalSix__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__FourPanel__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__HorizontalThree__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelDesignBuilder__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__RotationPivotBuilder__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__DoorAssemblyComposer__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryEngine__'
        require_relative '../06__Tools__MeasurementTools/Na__AssemblyStudio__MeasurementTools__ThreePointOpeningTool__'
        require_relative 'Na__AssemblyStudio__InteriorDoorSystem__DialogRouter__'

        AssetLibrary.na_set_assets_root_path(NA_ASSETS_ROOT_PATH)

        @na_door_modules_loaded = true
        DebugTools.na_debug_door("All door sub-modules loaded")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Reset Door Lazy-Load Gate After Developer Reload
    # ------------------------------------------------------------
    # DialogManager.hot-reloads Ruby with `Kernel#load`. Cached
    # `@na_door_modules_loaded` would otherwise skip `na_require_door_modules`
    # on the next dialog open before `Na__InteriorDoorSystem::Na__AssetLibrary`
    # `na_set_assets_root_path` replay and any future funnel side effects are
    # applied. Invoked exclusively from DialogManager.na_finalize_developer_reload.
    def self.na_reset_door_module_load_gate_for_developer_reload
        @na_door_modules_loaded = false
        DebugTools.na_debug_door("Door lazy-load gate reset for developer reload")
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Dialog Wiring
# -----------------------------------------------------------------------------

    # FUNCTION | Initialise Door-Tab Action Callbacks on the Active Dialog
    # ------------------------------------------------------------
    # Bootstraps the door tab against the parent tool's shared HtmlDialog
    # by delegating to Na__DialogRouter.na_init, which caches the dialog
    # reference and registers every door-side action callback (createDoor,
    # updateDoor, liveUpdateDoor, measureDoorOpening, ...). Safe to call
    # repeatedly - SketchUp replaces same-name handlers on each call.
    #
    # @param dialog [UI::HtmlDialog] The shared dialog instance
    # @return [Boolean] True on success, false on failure
    def self.na_init_door_callbacks(dialog)
        return false unless dialog
        na_require_door_modules

        Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter.na_init(
            dialog, NA_DEFAULT_DOOR_CONFIG
        )
        DebugTools.na_debug_door("Door tab callbacks registered on dialog")
        true
    rescue StandardError => e
        DebugTools.na_debug_error("na_init_door_callbacks failed", e) if defined?(DebugTools)
        puts "[NA_DOOR_INIT] Failed to register door callbacks : #{e.message}"
        puts e.backtrace.first(10).join("\n") if e.backtrace
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load a Door Selection into the Dialog (Observer Hook)
    # ------------------------------------------------------------
    # Called by the shared SelectionObserver when a component instance
    # carrying a DoorID is selected.
    #
    # @param instance [Sketchup::ComponentInstance] The selected door instance
    # @param door_id [String] The validated door ID (e.g. "ADR001")
    def self.na_load_door_into_dialog(instance, door_id)
        na_require_door_modules
        Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter.na_load_door_into_dialog(instance, door_id)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear the Door Tab State on Empty Selection
    # ------------------------------------------------------------
    def self.na_clear_door_from_dialog
        return unless @na_door_modules_loaded
        Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DialogRouter.na_clear_door_from_dialog
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Default Configuration Access
# -----------------------------------------------------------------------------

    # FUNCTION | Return a Deep Copy of the Default Door Configuration
    # ------------------------------------------------------------
    # @return [Hash] Deep clone safe to mutate
    def self.na_default_door_config
        Marshal.load(Marshal.dump(NA_DEFAULT_DOOR_CONFIG))
    end
    # ---------------------------------------------------------------

    # FUNCTION | Return the Default Door Configuration as a JSON String
    # ------------------------------------------------------------
    # @return [String] JSON serialisation suitable for sending to the dialog
    def self.na_default_door_config_json
        JSON.generate(NA_DEFAULT_DOOR_CONFIG)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------
    # REGION | EASP v2 - per-system Init partial called by AppCore::Main
    # -----------------------------------------------------------------

    module Na__Init

        def self.na_init
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__DialogManager__'
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__SelectionCoordinator__'

            dialog_manager        = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
            selection_coordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator

            # Register selection handler with the multi-system coordinator.
            selection_coordinator.na_register_handler(na_handler_descriptor)

            # When AppCore opens the dialog, register door callbacks on it.
            dialog_manager.na_register_system_init_hook do |dialog|
                Na__AssemblyStudio::Na__InteriorDoorSystem.na_init_door_callbacks(dialog)
            end
        end

        def self.na_handler_descriptor
            {
                :tab_id      => 'doors',
                :resolve_id  => proc { |instance|
                    next nil unless defined?(Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DataSerializer)
                    begin
                        Na__AssemblyStudio::Na__InteriorDoorSystem::Na__DataSerializer.na_get_door_id_from_instance(instance)
                    rescue StandardError
                        nil
                    end
                },
                :on_selected => proc { |instance, id|
                    Na__AssemblyStudio::Na__InteriorDoorSystem.na_load_door_into_dialog(instance, id)
                },
                :on_cleared  => proc {
                    Na__AssemblyStudio::Na__InteriorDoorSystem.na_clear_door_from_dialog
                }
            }
        end

    end

end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
