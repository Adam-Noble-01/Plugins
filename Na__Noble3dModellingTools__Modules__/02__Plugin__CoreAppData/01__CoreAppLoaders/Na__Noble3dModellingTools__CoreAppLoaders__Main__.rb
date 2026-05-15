# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CORE APP LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLoaders__Main__.rb
# NAMESPACE  : Na__Noble3dModellingTools
# PURPOSE    : Load all core modules and expose public bootstrap methods
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# Tool tabs, grouping, labels, command IDs, ordering, and hotkey visibility belong
# in Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json. Core entry
# points should delegate to config-driven loaders, renderers, and routers.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__PathResolver__'
require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__StandardDataCache__'
require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ConfigLoader__'
require_relative '../02__ModuleLoaders/Na__Noble3dModellingTools__ModuleLoaders__Main__'
require_relative '../03__PublicAPI/Na__Noble3dModellingTools__PublicAPI__CommandRouter__'
require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__DialogManager__'
require_relative '../04__PluginHotkeyManager/Na__Noble3dModellingTools__HotkeyManager__'
require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ReloadManager__'
require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__ToolbarIconLoader__'

module Na__Noble3dModellingTools

# -----------------------------------------------------------------------------
# REGION | Bootstrap Entry Points
# -----------------------------------------------------------------------------

    def self.Na__Noble3dModellingTools__RegisterHotkeysAndMenu
        Na__StandardDataCache.Na__Noble3dModellingTools__PrimeStandardCache
        Na__HotkeyManager.Na__Noble3dModellingTools__RegisterHotkeysAndMenu
        Na__ToolbarIconLoader.Na__Noble3dModellingTools__CreateToolbar
        feature_modules_loaded = Na__ModuleLoaders.Na__Noble3dModellingTools__LoadFeatureModules
        na_warn_feature_module_load_failure('register_hotkeys_and_menu') unless feature_modules_loaded
        true
    rescue => error
        puts "[Na__Noble3dModellingTools] Core loader registration error: #{error.class}: #{error.message}"
        puts error.backtrace.first(10).join("\n") if error.backtrace
        false
    end

    def self.Na__Noble3dModellingTools__ShowMainDialog
        Na__StandardDataCache.Na__Noble3dModellingTools__PrimeStandardCache
        feature_modules_loaded = Na__ModuleLoaders.Na__Noble3dModellingTools__LoadFeatureModules
        na_warn_feature_module_load_failure('show_main_dialog') unless feature_modules_loaded
        Na__DialogManager.Na__Noble3dModellingTools__ShowDialog
    end

    def self.Na__Noble3dModellingTools__RunCommandById(command_id)
        Na__StandardDataCache.Na__Noble3dModellingTools__PrimeStandardCache
        feature_modules_loaded = Na__ModuleLoaders.Na__Noble3dModellingTools__LoadFeatureModules
        na_warn_feature_module_load_failure("run_command:#{command_id}") unless feature_modules_loaded
        Na__CommandRouter.Na__Noble3dModellingTools__RunCommand(command_id)
    end

    def self.Na__Noble3dModellingTools__ReloadPluginData
        Na__ReloadManager.Na__Noble3dModellingTools__ReloadPluginData
    end

    def self.na_warn_feature_module_load_failure(callsite_name)
        puts "[Na__Noble3dModellingTools] Feature module load warning during #{callsite_name}; some feature commands may be unavailable."
    end

# endregion -------------------------------------------------------------------

end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
