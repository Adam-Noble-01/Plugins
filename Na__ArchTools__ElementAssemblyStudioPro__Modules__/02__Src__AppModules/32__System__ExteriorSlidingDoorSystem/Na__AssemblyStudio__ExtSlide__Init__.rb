# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SLIDING DOOR SYSTEM (PHASE-1 SCAFFOLD)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem
# MODULE     : Na__ExteriorSlidingDoorSystem
# AUTHOR     : Noble Architecture
# PURPOSE    : Entry point for the Exterior Sliding Door system. Owns module-
#              level constants, lazy-loads sub-modules and registers with the
#              AppCore selection coordinator + dialog manager.
# CREATED    : 17-May-2026
#
# NAMING NOTE:
# Folder is `32__System__ExteriorSlidingDoorSystem` (user-approved). The
# Ruby module name is `Na__ExteriorSlidingDoorSystem` (full descriptive).
# Filenames use the abbreviated `ExtSlide__` segment so absolute Windows
# paths stay below the 260-char MAX_PATH ceiling. See
# `85__Docs__AppDocumentation/Na__AssemblyStudio__Architecture__.md` for
# the full file-segment shortening table.
#
# DESCRIPTION:
# - Phase-1 scaffold: file structure only. Geometry / UI / animation logic
#   lands in Phases 3b, 2 and 6 respectively.
# - Mirrors the structure of `Na__InteriorDoorSystem::Na__Init` so the
#   AppCore wiring (DialogManager.init hooks + SelectionCoordinator
#   handlers) is identical across systems.
# - Naming contract for the GLB/TrueVision animation pipeline:
#       ADR-component
#         |- MOD001__MVE__X-{value}-mm__SlidingPanel    (front leaf)
#         |- MOD002__MVE__X-{value}-mm__SlidingPanel    (rear leaf, setback)
#         |- ROT001__RotationPoint__SlidingPanelTrack   (placeholder ROT)
#         |- MVE001__MovementPoint__SlidingPanelTrack
#         |- MVE002__MovementPoint__SlidingPanelTrack
#
# DEVELOPMENT LOG:
# 17-May-2026 - Version 0.1.0
# - Initial Phase-1 scaffold (skeleton only, no functional logic).
#
# =============================================================================

require 'json'
require 'sketchup.rb'

require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools                      # <-- Shared debug logger
    TagManager     = Na__AssemblyStudio::Na__AppUtils::Na__TagManager                      # <-- Shared layer/tag helper

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Path Resolution
# -----------------------------------------------------------------------------

    NA_MODULE_ROOT_PATH         = File.dirname(__FILE__).freeze                            # <-- Folder of this Init file
    NA_ASSETS_ROOT_PATH         = File.expand_path(
        File.join(NA_MODULE_ROOT_PATH, "..", "..", "04__Data__AssetLibrary")
    ).freeze                                                                               # <-- Shared asset library root

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - ADR Door ID System (shared with sibling systems)
# -----------------------------------------------------------------------------

    NA_DOOR_ID_PREFIX            = "ADR".freeze                                            # <-- ADR-series door codes
    NA_DOOR_ID_REGEX             = /^ADR\d{3}$/.freeze                                     # <-- Validation pattern
    NA_DOOR_ID_FORMAT            = "ADR%03d".freeze                                        # <-- sprintf format

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Component Naming Conventions (TrueVision contract)
# -----------------------------------------------------------------------------

    NA_DEFINITION_SUFFIX_DOOR        = "__SlidingDoor__".freeze                            # <-- ComponentDefinition suffix appended to ADR id
    NA_GROUP_NAME_ROT_PLACEHOLDER    = "ROT001__RotationPoint__SlidingPanelTrack".freeze   # <-- Minimal ROT placeholder per ADR (TrueVision contract)
    NA_MVE_NAME_FORMAT               = "MVE%03d__MovementPoint__SlidingPanelTrack".freeze  # <-- MVE marker name template
    NA_MOD_NAME_FORMAT               = "MOD%03d__MVE__%s%+d-mm__SlidingPanel".freeze       # <-- Signed magnitude (e.g. MOD002__MVE__X+1200-mm or X-1200-mm)
    NA_MOD_NAME_FORMAT_FIXED         = "MOD%03d__FIXED__SlidingPanel".freeze               # <-- Fixed leaf uses explicit FIXED token (Phase-4 contract)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Dictionary Keys (mirrors InteriorDoorSystem)
# -----------------------------------------------------------------------------

    NA_DOOR_INFO_DICT            = "Na__SlidingDoorConfiguratorInfo".freeze
    NA_DOOR_DEF_DICT_PREFIX      = "Na__SlidingDoorConfigurator_".freeze
    NA_KEY_DOOR_ID               = "DoorID".freeze
    NA_KEY_SU_INSTANCE_NAME      = "SketchUpInstanceName".freeze
    NA_KEY_SU_DEFINITION_NAME    = "SketchUpDefinitionName".freeze
    NA_KEY_DOOR_METADATA         = "Na__SlidingDoorMetadata".freeze
    NA_KEY_DOOR_COMPONENTS       = "Na__SlidingDoorComponents".freeze
    NA_KEY_DOOR_CONFIGURATION    = "Na__SlidingDoorConfiguration".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Default Sliding Door Configuration
# -----------------------------------------------------------------------------

    # All numeric values are millimetres unless suffixed. Keys mirror the
    # snake_case payload sent by NA_SLIDING_DOOR_CONFIG (the Window-tab
    # sliding schema) so the Ruby engine reads JS state directly without
    # a long-form name conversion layer. Mode flags `multifold_mode` /
    # `sliding_mode` live on the parent WindowSystem config; this hash is
    # the sliding-specific block consumed when `sliding_mode == true`.
    #
    # Phase-9: Opening dimensions / floor clearance now read from the
    # shared window-level keys (`width_mm`, `height_mm`,
    # `frame_*_thickness_mm`) so the same Dimensions sliders drive every
    # opening type. Legacy keys `sliding_door_opening_width_mm`,
    # `sliding_door_opening_height_mm`, `sliding_door_floor_clearance_mm`,
    # `sliding_door_wall_depth_mm` are migrated on load.
    NA_DEFAULT_DOOR_CONFIG = {
        "sliding_door_mode"               => "FrontSlidesRight",                         # <-- FrontSlidesLeft | FrontSlidesRight
        "sliding_door_panel_thickness_mm" => 50,                                         # <-- Single leaf thickness
        "sliding_door_rear_setback_mm"    => 60,                                         # <-- Y-offset of rear panel from front panel face
        "sliding_door_head_rail_mm"       => 95,                                         # <-- Default head rail height
        "sliding_door_base_rail_mm"       => 200,                                        # <-- Default base rail height
        "sliding_door_stile_width_mm"     => 95,                                         # <-- Default stile width (left/right)
        "sliding_door_glazed"             => true,                                       # <-- Fully glazed default
        "sliding_door_panel_design_open"  => false,                                      # <-- Reveals PanelDesign sub-panel (Phase 3.6)
        "sliding_door_handle_asset_key"   => "Na__ExteriorDoor__Handle__SlidingDefault",
        "sliding_door_handle_height_mm"   => 1000
    }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Late-Bound Sub-Module Loading
# -----------------------------------------------------------------------------

    # FUNCTION | Load Sub-Modules in Dependency Order (Late Bound)
    # ------------------------------------------------------------
    # Called the first time the Sliding tab is used by AppCore. Phase-3b
    # populated the geometry stack; Phase-3.5 wires DataSerializer +
    # DialogRouter alongside the bifold pair.
    def self.na_require_sliding_modules
        return if @na_sliding_modules_loaded

        require_relative 'Na__AssemblyStudio__ExtSlide__GeometryHelpers__'
        require_relative 'Na__AssemblyStudio__ExtSlide__RotationPivotBuilder__'
        require_relative 'Na__AssemblyStudio__ExtSlide__MovementPivotBuilder__'
        require_relative 'Na__AssemblyStudio__ExtSlide__AssemblyComposer__'
        require_relative 'Na__AssemblyStudio__ExtSlide__GeometryEngine__'
        require_relative 'Na__AssemblyStudio__ExtSlide__DataSerializer__'
        require_relative 'Na__AssemblyStudio__ExtSlide__DialogRouter__'
        require_relative 'Na__AssemblyStudio__ExtSlide__FuseParts__Panel__'

        @na_sliding_modules_loaded = true
        DebugTools.na_debug_info("[ExtSlide] Sub-modules lazy-loaded (Phase-3b)")
    end

    # FUNCTION | Reset the Lazy-Load Gate After Developer Reload
    # ------------------------------------------------------------
    def self.na_reset_sliding_module_load_gate_for_developer_reload
        @na_sliding_modules_loaded = false
        DebugTools.na_debug_info("[ExtSlide] Lazy-load gate reset for developer reload")
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Dialog Wiring (Phase-2 will populate)
# -----------------------------------------------------------------------------

    # FUNCTION | Initialise Sliding-Door Action Callbacks on the Active Dialog
    # ------------------------------------------------------------
    def self.na_init_sliding_callbacks(dialog)
        return false unless dialog
        na_require_sliding_modules
        # Phase-2 wires Na__DialogRouter.na_init(dialog, NA_DEFAULT_DOOR_CONFIG)
        DebugTools.na_debug_info("[ExtSlide] Dialog callbacks placeholder (Phase-1 scaffold)")
        true
    rescue StandardError => e
        DebugTools.na_debug_error("na_init_sliding_callbacks failed", e) if defined?(DebugTools)
        false
    end

    # FUNCTION | Load a Sliding-Door Selection into the Dialog (Observer Hook)
    # ------------------------------------------------------------
    # Phase-3.5: Selection routing now lives in
    # `Na__WindowSystem::Na__DialogCallbacks.na_load_sliding_into_dialog`
    # because the sliding UI controls share the Windows tab. This thin
    # redirect remains for any legacy caller and ensures the sliding
    # sub-modules are loaded before the dialog state is updated.
    def self.na_load_sliding_into_dialog(instance, door_id)
        na_require_sliding_modules
        return unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
        Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_load_sliding_into_dialog(instance, door_id)
    end

    # FUNCTION | Clear the Sliding-Door Tab State on Empty Selection
    # ------------------------------------------------------------
    # Phase-3.5: Thin redirect. See note above.
    def self.na_clear_sliding_from_dialog
        return unless @na_sliding_modules_loaded
        return unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
        Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_clear_sliding_from_dialog
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Default Configuration Access
# -----------------------------------------------------------------------------

    def self.na_default_sliding_config
        Marshal.load(Marshal.dump(NA_DEFAULT_DOOR_CONFIG))
    end

    def self.na_default_sliding_config_json
        JSON.generate(NA_DEFAULT_DOOR_CONFIG)
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | EASP v2 - per-system Init partial called by AppCore::Main
# -----------------------------------------------------------------------------

    module Na__Init

        def self.na_init
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__DialogManager__'
            require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__SelectionCoordinator__'

            dialog_manager        = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
            selection_coordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator

            selection_coordinator.na_register_handler(na_handler_descriptor)

            dialog_manager.na_register_system_init_hook do |dialog|
                Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem.na_init_sliding_callbacks(dialog)
            end
        end

        def self.na_handler_descriptor
            {
                :tab_id      => 'windows',                                                       # <-- Sliding UI lives inside the Windows tab; switch back to it on selection
                :resolve_id  => proc { |instance|
                    next nil unless defined?(Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer)
                    begin
                        Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DataSerializer.na_get_door_id_from_instance(instance)
                    rescue StandardError
                        nil
                    end
                },
                :on_selected => proc { |instance, id|
                    next unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
                    Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_load_sliding_into_dialog(instance, id)
                },
                :on_cleared  => proc {
                    next unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
                    Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_clear_sliding_from_dialog
                }
            }
        end

    end

# endregion -------------------------------------------------------------------

end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
