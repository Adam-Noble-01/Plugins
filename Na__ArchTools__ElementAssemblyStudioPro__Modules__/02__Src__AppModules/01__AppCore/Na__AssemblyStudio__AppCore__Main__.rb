# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - APPCORE MAIN (neutral app lifecycle)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppCore__Main__.rb
# NAMESPACE  : Na__AssemblyStudio
# MODULE     : top-level entry called by the Plugins-root loader
# AUTHOR     : Noble Architecture
# PURPOSE    : Plugin entry point. Does NOT contain any window or door
#              specific code. Loads each system's Init partial in order so
#              every system can register its own callbacks, selection
#              handlers and Init hooks against AppCore.
#
# WIRING
#   Plugins/Na__ElementAssemblyStudioPro__Loader.rb
#       -> require this file
#       -> calls Na__AssemblyStudio.na_init
# =============================================================================

require 'sketchup.rb'

# Foundation (load order matters - DebugTools is required by everyone else)
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__ConfigLoader__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__MaterialManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__FrameFinishSwatches__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__SerializerBase__'
require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Units__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Fuse__Shared__'

# AppCore (UiBridge -> DialogManager -> SelectionCoordinator)
require_relative 'Na__AssemblyStudio__AppCore__UiBridge__'
require_relative 'Na__AssemblyStudio__AppCore__DialogManager__'
require_relative 'Na__AssemblyStudio__AppCore__SelectionCoordinator__'

# Tools
require_relative '../06__Tools__MeasurementTools/Na__AssemblyStudio__MeasurementTools__TwoPointOpeningTool__'
require_relative '../06__Tools__MeasurementTools/Na__AssemblyStudio__MeasurementTools__ThreePointOpeningTool__'
require_relative '../07__Tools__PlacementTools/Na__AssemblyStudio__PlacementTools__WindowPlacementTool__'

# Per-system Init partials (each system self-registers callbacks/handlers/hooks)
require_relative '../20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Init__'
require_relative '../30__System__ExteriorDoorSystem/Na__AssemblyStudio__ExteriorDoorSystem__Init__'
require_relative '../40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__Init__'

# Optional dev tools (silently skipped if folder removed for shipping)
begin
    require_relative '../../../65__Dev__DevTools/Na__AssemblyStudio__DevTools__Main__'
rescue LoadError => e
    Na__AssemblyStudio::Na__AppUtils::Na__DebugTools.na_debug_warn("DevTools not loaded: #{e.message}")
end

module Na__AssemblyStudio

    # Resolve the modules root path (parent of 02__Src__AppModules) so the
    # loader / dialog manager can find sibling folders without guessing.
    NA_APPCORE_DIR    = File.dirname(__FILE__)
    NA_SRC_DIR        = File.expand_path("..", NA_APPCORE_DIR)
    NA_MODULES_ROOT   = File.expand_path("..", NA_SRC_DIR)
    NA_HTML_FILE_PATH = File.join(NA_MODULES_ROOT, "Na__AssemblyStudio__UiLayout__.html")
    NA_CACHE_DIR_PATH = File.join(NA_MODULES_ROOT, "90__AppCache__TempFilesCache")

    DebugTools             = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
    MaterialManager        = Na__AssemblyStudio::Na__AppData::Na__MaterialManager
    DialogManager          = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
    SelectionCoordinator   = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator

    # FUNCTION | Initialise the plugin and open the dialog
    # -----------------------------------------------------------------
    def self.na_init
        DebugTools.na_debug_method("Na__AssemblyStudio.na_init")

        # Route the shared DataLib cache to this plugin's local cache folder
        # so cached web data is co-located with the plugin and survives across
        # SketchUp's temp_dir cleanups.
        Na__DataLib__CacheData.Na__Cache__SetCacheDirOverride(NA_CACHE_DIR_PATH)

        # Load app config + materials library + standard materials
        begin
            cfg = Na__AssemblyStudio::Na__AppData::Na__ConfigLoader.na_load
            DebugTools.na_debug_info("AppConfig loaded (v#{cfg.dig('metadata', 'version')})") if cfg
        rescue StandardError => e
            DebugTools.na_debug_error("AppConfig load failed", e)
        end

        MaterialManager.na_load_materials_library
        MaterialManager.na_initialize_standard_materials
        MaterialManager.na_ensure_safety_materials

        # Per-system init hooks
        Na__AssemblyStudio::Na__WindowSystem::Na__Init.na_init       if defined?(Na__AssemblyStudio::Na__WindowSystem::Na__Init)
        Na__AssemblyStudio::Na__ExteriorDoorSystem::Na__Init.na_init if defined?(Na__AssemblyStudio::Na__ExteriorDoorSystem::Na__Init)
        Na__AssemblyStudio::Na__InteriorDoorSystem::Na__Init.na_init if defined?(Na__AssemblyStudio::Na__InteriorDoorSystem::Na__Init)

        # Selection observer
        SelectionCoordinator.na_attach

        # Show the dialog (system Init hooks already registered their callbacks
        # and DialogManager init hooks before this point)
        DialogManager.na_show_dialog(NA_HTML_FILE_PATH, NA_MODULES_ROOT)

        DebugTools.na_debug_success("Element Assembly Studio Pro initialised")
    end

end
