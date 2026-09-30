# =============================================================================
# NA SKETCHUP MCP - CORE PATH RESOLVER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__CoreAppLogic__PathResolver__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__PathResolver
# PURPOSE    : Centralise every file and folder path the bridge uses
# CREATED    : 2026
#
# PATH RULE:
# Everything resolves from this file's own location, so the plugin works from
# any Plugins folder on any PC. No absolute C:\ paths anywhere in source.
# Per-user runtime files (connection files, captures, settings) live in the
# git-ignored 91__UserConfig__LocalOnly folder beside the modules.
#
# =============================================================================

require 'fileutils'

module Na__SketchUpMcp
    module Na__PathResolver

# -----------------------------------------------------------------------------
# REGION | Root Paths
# -----------------------------------------------------------------------------

        def self.Na__PathResolver__ModulesRoot
            @na_modules_root ||= File.expand_path(File.join(__dir__, '..'))
        end

        def self.Na__PathResolver__PluginsRoot
            @na_plugins_root ||= File.expand_path(File.join(self.Na__PathResolver__ModulesRoot, '..'))
        end

        def self.Na__PathResolver__RootLoaderFilePath
            File.join(self.Na__PathResolver__PluginsRoot, 'Na__SketchUpMcp__Loader__.rb')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Data Files (committed, shared by Ruby bridge and Python server)
# -----------------------------------------------------------------------------

        def self.Na__PathResolver__CoreAppDataDirectory
            File.join(self.Na__PathResolver__ModulesRoot, '02__Plugin__CoreAppData')
        end

        def self.Na__PathResolver__AppConfigFilePath
            File.join(self.Na__PathResolver__CoreAppDataDirectory, 'Na__SketchUpMcp__CoreAppData__AppConfig__.json')
        end

        def self.Na__PathResolver__ToolRegistryFilePath
            File.join(self.Na__PathResolver__CoreAppDataDirectory, 'Na__SketchUpMcp__CoreAppData__ToolRegistry__.json')
        end

        def self.Na__PathResolver__ApiIndexFilePath
            File.join(self.Na__PathResolver__CoreAppDataDirectory, 'Na__SketchUpMcp__CoreAppData__SketchUpApiIndex__.json')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | User Interface Files
# -----------------------------------------------------------------------------

        def self.Na__PathResolver__UiDirectory
            File.join(self.Na__PathResolver__ModulesRoot, '05__Plugin__UserInterface')
        end

        def self.Na__PathResolver__UiLayoutFilePath
            File.join(self.Na__PathResolver__UiDirectory, 'Na__SketchUpMcp__UiLayout__.html')
        end

        def self.Na__PathResolver__UiStylesheetFilePath
            File.join(self.Na__PathResolver__UiDirectory, 'Na__SketchUpMcp__Styles__.css')
        end

        def self.Na__PathResolver__UiBridgeFilePath
            File.join(self.Na__PathResolver__UiDirectory, 'Na__SketchUpMcp__UiBridge__.js')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Python MCP Server Paths (shown in the dialog's client setup panel)
# -----------------------------------------------------------------------------

        def self.Na__PathResolver__PythonServerDirectory
            File.join(self.Na__PathResolver__ModulesRoot, '30__McpServer__Python')
        end

        def self.Na__PathResolver__PythonServerEntryFilePath
            File.join(self.Na__PathResolver__PythonServerDirectory, 'Na__SketchUpMcp__Server__Main__.py')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Per-User Runtime Files (git-ignored, never travel with the plugin)
# -----------------------------------------------------------------------------

        def self.Na__PathResolver__UserConfigDirectory
            File.join(self.Na__PathResolver__ModulesRoot, '91__UserConfig__LocalOnly')
        end

        def self.Na__PathResolver__UserSettingsFilePath
            File.join(self.Na__PathResolver__UserConfigDirectory, 'Na__SketchUpMcp__UserConfig__Settings__.json')
        end

        # One file per running SketchUp process. The Python server reads these to
        # find the port and session token of every live bridge.
        def self.Na__PathResolver__ConnectionsDirectory
            File.join(self.Na__PathResolver__UserConfigDirectory, 'Connections')
        end

        def self.Na__PathResolver__ConnectionFilePath(process_id)
            File.join(self.Na__PathResolver__ConnectionsDirectory, "Na__SketchUpMcp__Connection__#{process_id}.json")
        end

        def self.Na__PathResolver__CapturesDirectory
            File.join(self.Na__PathResolver__UserConfigDirectory, 'Captures')
        end

        def self.Na__PathResolver__EnsureDirectory(directory_path)
            FileUtils.mkdir_p(directory_path) unless File.directory?(directory_path)
            directory_path
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Common Assets (Na__Common__PluginDependencies)
# -----------------------------------------------------------------------------

        def self.Na__PathResolver__SharedAssetsDirectory
            File.join(self.Na__PathResolver__PluginsRoot, 'Na__Common__PluginDependencies')
        end

        def self.Na__PathResolver__NaLogoFilePath
            File.join(self.Na__PathResolver__SharedAssetsDirectory, 'IMG01__PNG__NaCompanyLogo.png')
        end

        def self.Na__PathResolver__NaIconFilePath
            File.join(self.Na__PathResolver__SharedAssetsDirectory, 'IMG02__ICN__NaCompanyIcon.png')
        end

# endregion -------------------------------------------------------------------

    end # module Na__PathResolver
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
