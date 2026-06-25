# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC CORE APP LOADER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__CoreAppLoaders__Main__.rb
# NAMESPACE  : Na__ValeVisionCloudSync
# PURPOSE    : Load all core modules and expose public bootstrap methods
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Required by the root loader; chains all core requires in dependency order.
# - Exposes four public entrypoints: RegisterMenuAndToolbar, ShowMainDialog,
#   RunCommandById, and ReloadPluginData.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

require_relative '../../03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__PathResolver__'
require_relative '../../03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__ConfigLoader__'
require_relative '../02__ModuleLoaders/Na__ValeVisionCloudSync__ModuleLoaders__Main__'
require_relative '../03__PublicAPI/Na__ValeVisionCloudSync__PublicAPI__CommandRouter__'
require_relative '../../03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__DialogManager__'
require_relative '../04__PluginHotkeyManager/Na__ValeVisionCloudSync__HotkeyManager__'
require_relative '../../03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__ReloadManager__'
require_relative '../../03__Plugin__CoreAppLogic/Na__ValeVisionCloudSync__CoreAppLogic__ToolbarIconLoader__'

module Na__ValeVisionCloudSync

# -----------------------------------------------------------------------------
# REGION | Bootstrap Entry Points
# -----------------------------------------------------------------------------

    def self.Na__ValeVisionCloudSync__RegisterMenuAndToolbar
        Na__HotkeyManager.Na__ValeVisionCloudSync__RegisterHotkeysAndMenu
        Na__ToolbarIconLoader.Na__ValeVisionCloudSync__CreateToolbar
        Na__ModuleLoaders.Na__ValeVisionCloudSync__LoadSyncFeatureModules
        true
    rescue => error
        puts "[Na__ValeVisionCloudSync] Registration error: #{error.class}: #{error.message}"
        puts error.backtrace.first(10).join("\n") if error.backtrace
        false
    end

    def self.Na__ValeVisionCloudSync__ShowMainDialog
        Na__ModuleLoaders.Na__ValeVisionCloudSync__LoadSyncFeatureModules
        Na__DialogManager.Na__ValeVisionCloudSync__ShowDialog
    end

    def self.Na__ValeVisionCloudSync__RunCommandById(command_id)
        Na__ModuleLoaders.Na__ValeVisionCloudSync__LoadSyncFeatureModules
        Na__CommandRouter.Na__ValeVisionCloudSync__RunCommand(command_id)
    end

    def self.Na__ValeVisionCloudSync__ReloadPluginData
        Na__ReloadManager.Na__ValeVisionCloudSync__ReloadPluginData
    end

# endregion -------------------------------------------------------------------

end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
