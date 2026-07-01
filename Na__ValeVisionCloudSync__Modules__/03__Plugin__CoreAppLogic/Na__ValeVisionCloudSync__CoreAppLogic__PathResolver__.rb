# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC PATH RESOLVER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__CoreAppLogic__PathResolver__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__PathResolver
# PURPOSE    : Centralize all plugin-internal path resolution
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Exposes helpers for the JSON registries, UI assets, and the icon.
# - Does NOT resolve project/model paths; that belongs in ProjectPathMapper.
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__PathResolver

# -----------------------------------------------------------------------------
# REGION | Root Paths
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__ModulesRoot
            @na_modules_root ||= File.expand_path(File.join(__dir__, '..'))
        end

        def self.Na__ValeVisionCloudSync__PluginRoot
            @na_plugin_root ||= File.expand_path(File.join(self.Na__ValeVisionCloudSync__ModulesRoot, '..'))
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Data and UI Paths
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__CoreAppDataDirectory
            File.join(self.Na__ValeVisionCloudSync__ModulesRoot, '02__Plugin__CoreAppData')
        end

        def self.Na__ValeVisionCloudSync__CoreLogicDirectory
            File.join(self.Na__ValeVisionCloudSync__ModulesRoot, '03__Plugin__CoreAppLogic')
        end

        def self.Na__ValeVisionCloudSync__SyncFeaturesDirectory
            File.join(self.Na__ValeVisionCloudSync__ModulesRoot, '04__Plugin__SyncFeatures')
        end

        def self.Na__ValeVisionCloudSync__UiDirectory
            File.join(self.Na__ValeVisionCloudSync__ModulesRoot, '05__Plugin__UserInterface')
        end

        def self.Na__ValeVisionCloudSync__AssetsDirectory
            File.join(self.Na__ValeVisionCloudSync__ModulesRoot, '06__Assets')
        end

        def self.Na__ValeVisionCloudSync__UiCommandRegistryFilePath
            File.join(
                self.Na__ValeVisionCloudSync__CoreAppDataDirectory,
                'Na__ValeVisionCloudSync__CoreAppData__UiCommandRegistry__.json'
            )
        end

        def self.Na__ValeVisionCloudSync__AppConfigFilePath
            File.join(
                self.Na__ValeVisionCloudSync__CoreAppDataDirectory,
                'Na__ValeVisionCloudSync__CoreAppData__AppConfig__.json'
            )
        end

        def self.Na__ValeVisionCloudSync__UiLayoutFilePath
            File.join(self.Na__ValeVisionCloudSync__UiDirectory, 'Na__ValeVisionCloudSync__UiLayout__.html')
        end

        def self.Na__ValeVisionCloudSync__UiStylesheetFilePath
            File.join(self.Na__ValeVisionCloudSync__UiDirectory, 'Na__ValeVisionCloudSync__Styles__.css')
        end

        def self.Na__ValeVisionCloudSync__UiBridgeFilePath
            File.join(self.Na__ValeVisionCloudSync__UiDirectory, 'Na__ValeVisionCloudSync__UiBridge__.js')
        end

        def self.Na__ValeVisionCloudSync__RootLoaderFilePath
            File.join(self.Na__ValeVisionCloudSync__PluginRoot, 'Na__ValeVisionCloudSync__Loader__.rb')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared DataLib Paths (Cross-Plugin SSOT)
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve The Shared SketchUp Tags SSOT JSON Path
        # ------------------------------------------------------------
        # Lives outside this plugin, in the shared DataLib folder used by
        # TrueVision3D::GlbBuilderUtility and other Noble Architecture plugins.
        # Sits directly under the SketchUp Plugins root, alongside this plugin.
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__TagsDataLibFilePath
            File.join(
                self.Na__ValeVisionCloudSync__PluginRoot,
                'Na__Common__DataLib__CoreSuEntityStandards',
                'Na__DataLib__CoreIndex__Tags__.json'
            )
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Brand and Icon Asset Paths
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__BrandLogoFilePath
            File.join(self.Na__ValeVisionCloudSync__AssetsDirectory, 'Na__ValeVisionCloudSync__BrandLogo__Horizontal__.png')
        end

        def self.Na__ValeVisionCloudSync__Icon16FilePath
            File.join(self.Na__ValeVisionCloudSync__AssetsDirectory, 'Vale_Icon16px.png')
        end

        def self.Na__ValeVisionCloudSync__Icon32FilePath
            File.join(self.Na__ValeVisionCloudSync__AssetsDirectory, 'Vale_Icon32px.png')
        end

# endregion -------------------------------------------------------------------

    end # module Na__PathResolver
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
