# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR MULTI-FOLDING DOOR SYSTEM (PHASE-1 SCAFFOLD)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem
# MODULE     : Na__ExteriorMultiFoldingDoorSystem
# AUTHOR     : Noble Architecture
# PURPOSE    : Entry point for the Exterior Multi-Folding (Bifold) Door
#              system. Owns module-level constants, lazy-loads sub-modules,
#              and registers with the AppCore selection coordinator + dialog
#              manager.
# CREATED    : 17-May-2026
#
# NAMING NOTE:
# Folder is `33__System__ExteriorMultiFoldingDoorSystem` (user-approved).
# The Ruby module name is `Na__ExteriorMultiFoldingDoorSystem` (full
# descriptive). Filenames use the abbreviated `ExtFold__` segment so
# absolute Windows paths stay below the 260-char MAX_PATH ceiling. See
# `85__Docs__AppDocumentation/Na__AssemblyStudio__Architecture__.md` for
# the full file-segment shortening table.
#
# DESCRIPTION:
# - Phase-1 scaffold: file structure only. Geometry / UI / animation logic
#   lands in Phases 3a, 2 and 6 respectively.
# - Mirrors the structure of `Na__InteriorDoorSystem::Na__Init` so the
#   AppCore wiring is identical across systems.
# - Naming contract for the GLB/TrueVision animation pipeline:
#       ADR-component
#         |- MOD001__ROT__-90-Deg__BifoldPanel
#         |- MOD002__ROT__180-Deg__MVE__X-600-mm__BifoldPanel
#         |- ROT001__RotationPoint__BifoldHingeCentre
#         |- ROT002__RotationPoint__BifoldHingeCentre
#         |- MVE001__MovementPoint__BifoldPanelTrack
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
module Na__ExteriorMultiFoldingDoorSystem

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools                      # <-- Shared debug logger
    TagManager     = Na__AssemblyStudio::Na__AppUtils::Na__TagManager                      # <-- Shared layer/tag helper

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Path Resolution
# -----------------------------------------------------------------------------

    NA_MODULE_ROOT_PATH         = File.dirname(__FILE__).freeze
    NA_ASSETS_ROOT_PATH         = File.expand_path(
        File.join(NA_MODULE_ROOT_PATH, "..", "..", "04__Data__AssetLibrary")
    ).freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - ADR Door ID System (shared with sibling systems)
# -----------------------------------------------------------------------------

    NA_DOOR_ID_PREFIX            = "ADR".freeze
    NA_DOOR_ID_REGEX             = /^ADR\d{3}$/.freeze
    NA_DOOR_ID_FORMAT            = "ADR%03d".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Component Naming Conventions (TrueVision contract)
# -----------------------------------------------------------------------------

    NA_DEFINITION_SUFFIX_DOOR        = "__BifoldDoor__".freeze                             # <-- ComponentDefinition suffix
    NA_GROUP_NAME_ROT_HINGE_FORMAT   = "ROT%03d__RotationPoint__BifoldHingeCentre".freeze  # <-- ROT marker per panel
    NA_MVE_NAME_FORMAT               = "MVE%03d__MovementPoint__BifoldPanelTrack".freeze   # <-- MVE marker per moving panel

    # MOD names are resolved per layout algorithm at build time.
    # Examples:
    #   MOD001__ROT__-90-Deg__BifoldPanel                (master panel, no MVE)
    #   MOD002__ROT__180-Deg__MVE__X+600-mm__BifoldPanel (slave panel, ROT + MVE, positive direction)
    #   MOD003__ROT__180-Deg__MVE__X-600-mm__BifoldPanel (slave panel, ROT + MVE, negative direction)
    #
    # The MVE token is "<axis_letter><signed-magnitude>" with explicit sign on the
    # magnitude. The "%+d" format specifier guarantees both signs render so the
    # canonical TrueVision regex `MVE__([XYZ])([+-]\d+)-mm` matches both directions.
    # See `04__GeometryHelpers/Na__AssemblyStudio__DoorNamingContract__.rb` for the
    # cross-system source-of-truth contract.
    NA_MOD_NAME_FORMAT_ROT_ONLY      = "MOD%03d__ROT__%s-Deg__BifoldPanel".freeze
    NA_MOD_NAME_FORMAT_ROT_MVE       = "MOD%03d__ROT__%s-Deg__MVE__%s%+d-mm__BifoldPanel".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Layout Algorithm Identifiers
# -----------------------------------------------------------------------------

    NA_LAYOUT_EQUAL_EQUAL        = "EqualEqual".freeze        # <-- Panels split open to both sides
    NA_LAYOUT_ALL_ONE_WAY        = "AllOneWay".freeze         # <-- All panels fold to one side
    NA_LAYOUT_MASTER_SLAVES      = "MasterSlaves".freeze      # <-- Master swings 90deg, slaves cascade opposite

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Dictionary Keys
# -----------------------------------------------------------------------------

    NA_DOOR_INFO_DICT            = "Na__BifoldDoorConfiguratorInfo".freeze
    NA_DOOR_DEF_DICT_PREFIX      = "Na__BifoldDoorConfigurator_".freeze
    NA_KEY_DOOR_ID               = "DoorID".freeze
    NA_KEY_SU_INSTANCE_NAME      = "SketchUpInstanceName".freeze
    NA_KEY_SU_DEFINITION_NAME    = "SketchUpDefinitionName".freeze
    NA_KEY_DOOR_METADATA         = "Na__BifoldDoorMetadata".freeze
    NA_KEY_DOOR_COMPONENTS       = "Na__BifoldDoorComponents".freeze
    NA_KEY_DOOR_CONFIGURATION    = "Na__BifoldDoorConfiguration".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Default Bifold Door Configuration
# -----------------------------------------------------------------------------

    # All numeric values are millimetres unless suffixed. Keys mirror the
    # snake_case payload sent by NA_BIFOLD_DOOR_CONFIG (the Window-tab
    # bifold schema) so the Ruby engine can read JS state directly without
    # a long-form name conversion layer. Mode flags `multifold_mode` /
    # `sliding_mode` live on the parent WindowSystem config; this hash is
    # the bifold-specific block consumed when `multifold_mode == true`.
    NA_DEFAULT_DOOR_CONFIG = {
        "bifold_door_layout"             => NA_LAYOUT_EQUAL_EQUAL,           # <-- EqualEqual | AllOneWay | MasterSlaves
        "bifold_door_open_side"          => "Right",                         # <-- AllOneWay only (Left | Right)
        "bifold_door_master_side"        => "Right",                         # <-- MasterSlaves only (Left | Right)
        "bifold_door_panel_count"        => 4,                               # <-- 2..8 leaves (default 4)
        "bifold_door_opening_width_mm"   => 3600,                            # <-- Total clear opening width
        "bifold_door_opening_height_mm"  => 2100,                            # <-- Clear opening height
        "bifold_door_panel_thickness_mm" => 50,                              # <-- Per-leaf thickness
        "bifold_door_head_rail_mm"       => 95,                              # <-- Per-leaf head rail height
        "bifold_door_base_rail_mm"       => 200,                             # <-- Per-leaf base rail height
        "bifold_door_stile_width_mm"     => 95,                              # <-- Per-leaf stile width
        "bifold_door_glazed"             => true,                            # <-- Fully glazed default
        "bifold_door_panel_design_open"  => false,                           # <-- Reveals PanelDesign sub-panel (Phase-3.6)
        "bifold_door_wall_depth_mm"      => 105,                             # <-- Surrounding wall depth (head/base track)
        "bifold_door_floor_clearance_mm" => 10,                              # <-- Bottom gap to slab
        "bifold_door_handle_asset_key"   => "Na__ExteriorDoor__Handle__BifoldDefault",
        "bifold_door_handle_height_mm"   => 1000
    }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Late-Bound Sub-Module Loading
# -----------------------------------------------------------------------------

    # FUNCTION | Load Sub-Modules in Dependency Order (Late Bound)
    # ------------------------------------------------------------
    def self.na_require_bifold_modules
        return if @na_bifold_modules_loaded

        require_relative 'Na__AssemblyStudio__ExtFold__GeometryHelpers__'
        require_relative 'Na__AssemblyStudio__ExtFold__RotationPivotBuilder__'
        require_relative 'Na__AssemblyStudio__ExtFold__MovementPivotBuilder__'
        require_relative 'Na__AssemblyStudio__ExtFold__Layout__EqualEqual__'
        require_relative 'Na__AssemblyStudio__ExtFold__Layout__AllOneWay__'
        require_relative 'Na__AssemblyStudio__ExtFold__Layout__MasterSlaves__'
        require_relative 'Na__AssemblyStudio__ExtFold__AssemblyComposer__'
        require_relative 'Na__AssemblyStudio__ExtFold__GeometryEngine__'
        require_relative 'Na__AssemblyStudio__ExtFold__DataSerializer__'
        require_relative 'Na__AssemblyStudio__ExtFold__DialogRouter__'

        @na_bifold_modules_loaded = true
        DebugTools.na_debug_info("[ExtFold] Sub-modules lazy-loaded (Phase-3a)")
    end

    # FUNCTION | Reset the Lazy-Load Gate After Developer Reload
    # ------------------------------------------------------------
    def self.na_reset_bifold_module_load_gate_for_developer_reload
        @na_bifold_modules_loaded = false
        DebugTools.na_debug_info("[ExtFold] Lazy-load gate reset for developer reload")
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Dialog Wiring (Phase-2 will populate)
# -----------------------------------------------------------------------------

    # FUNCTION | Initialise Bifold-Door Action Callbacks on the Active Dialog
    # ------------------------------------------------------------
    def self.na_init_bifold_callbacks(dialog)
        return false unless dialog
        na_require_bifold_modules
        DebugTools.na_debug_info("[ExtFold] Dialog callbacks placeholder (Phase-1 scaffold)")
        true
    rescue StandardError => e
        DebugTools.na_debug_error("na_init_bifold_callbacks failed", e) if defined?(DebugTools)
        false
    end

    # FUNCTION | Load a Bifold-Door Selection into the Dialog (Observer Hook)
    # ------------------------------------------------------------
    # Phase-3.5: Selection routing now lives in
    # `Na__WindowSystem::Na__DialogCallbacks.na_load_bifold_into_dialog`
    # because the bifold UI controls share the Windows tab. This thin
    # redirect remains for any legacy caller and ensures the bifold
    # sub-modules are loaded before the dialog state is updated.
    def self.na_load_bifold_into_dialog(instance, door_id)
        na_require_bifold_modules
        return unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
        Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_load_bifold_into_dialog(instance, door_id)
    end

    # FUNCTION | Clear the Bifold-Door Tab State on Empty Selection
    # ------------------------------------------------------------
    # Phase-3.5: Thin redirect. See note above.
    def self.na_clear_bifold_from_dialog
        return unless @na_bifold_modules_loaded
        return unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
        Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_clear_bifold_from_dialog
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Default Configuration Access
# -----------------------------------------------------------------------------

    def self.na_default_bifold_config
        Marshal.load(Marshal.dump(NA_DEFAULT_DOOR_CONFIG))
    end

    def self.na_default_bifold_config_json
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
                Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem.na_init_bifold_callbacks(dialog)
            end
        end

        def self.na_handler_descriptor
            {
                :tab_id      => 'windows',                                                       # <-- Bifold UI lives inside the Windows tab; switch back to it on selection
                :resolve_id  => proc { |instance|
                    next nil unless defined?(Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer)
                    begin
                        Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DataSerializer.na_get_door_id_from_instance(instance)
                    rescue StandardError
                        nil
                    end
                },
                :on_selected => proc { |instance, id|
                    next unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
                    Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_load_bifold_into_dialog(instance, id)
                },
                :on_cleared  => proc {
                    next unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
                    Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_clear_bifold_from_dialog
                }
            }
        end

    end

# endregion -------------------------------------------------------------------

end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
