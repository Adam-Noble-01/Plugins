# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CORE PATH RESOLVER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__PathResolver__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PathResolver
# PURPOSE    : Centralize all plugin path resolution
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PathResolver

# -----------------------------------------------------------------------------
# REGION | Root Paths
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__ModulesRoot
            @na_modules_root ||= File.expand_path(File.join(__dir__, '..'))
        end

        def self.Na__Noble3dModellingTools__PluginRoot
            @na_plugin_root ||= File.expand_path(File.join(self.Na__Noble3dModellingTools__ModulesRoot, '..'))
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Data and UI Paths
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__CoreAppDataDirectory
            File.join(self.Na__Noble3dModellingTools__ModulesRoot, '02__Plugin__CoreAppData')
        end

        def self.Na__Noble3dModellingTools__CoreLogicDirectory
            File.join(self.Na__Noble3dModellingTools__ModulesRoot, '03__Plugin__CoreAppLogic')
        end

        def self.Na__Noble3dModellingTools__UiDirectory
            File.join(self.Na__Noble3dModellingTools__ModulesRoot, '05__Plugin__UserInterface')
        end

        def self.Na__Noble3dModellingTools__FeatureModulesDirectory
            File.join(self.Na__Noble3dModellingTools__ModulesRoot, '10__PluginModules')
        end

        def self.Na__Noble3dModellingTools__ConfigFilePath
            File.join(
                self.Na__Noble3dModellingTools__CoreAppDataDirectory,
                'Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json'
            )
        end

        def self.Na__Noble3dModellingTools__UiLayoutFilePath
            File.join(self.Na__Noble3dModellingTools__UiDirectory, 'Na__Noble3dModellingTools__UiLayout__.html')
        end

        def self.Na__Noble3dModellingTools__UiStylesheetFilePath
            File.join(self.Na__Noble3dModellingTools__UiDirectory, 'Na__Noble3dModellingTools__Styles__.css')
        end

        def self.Na__Noble3dModellingTools__UiBridgeFilePath
            File.join(self.Na__Noble3dModellingTools__UiDirectory, 'Na__Noble3dModellingTools__UiBridge__.js')
        end

        def self.Na__Noble3dModellingTools__RootLoaderFilePath
            File.join(self.Na__Noble3dModellingTools__PluginRoot, 'Na__Noble3dModellingTools__Loader__.rb')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Common Assets (Na__Common__PluginDependencies)
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__SharedAssetsDirectory
            File.expand_path(File.join(self.Na__Noble3dModellingTools__PluginRoot, 'Na__Common__PluginDependencies'))
        end

        def self.Na__Noble3dModellingTools__NaLogoFilePath
            File.join(self.Na__Noble3dModellingTools__SharedAssetsDirectory, 'IMG01__PNG__NaCompanyLogo.png')
        end

        def self.Na__Noble3dModellingTools__NaIconFilePath
            File.join(self.Na__Noble3dModellingTools__SharedAssetsDirectory, 'IMG02__ICN__NaCompanyIcon.png')
        end

# endregion -------------------------------------------------------------------

    end # module Na__PathResolver
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
