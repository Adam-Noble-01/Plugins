# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE PATH RESOLVER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__PathResolver__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__PathResolver
# PURPOSE    : Centralize filesystem path resolution for plugin source + assets
# CREATED    : 2026
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__PathResolver

# -----------------------------------------------------------------------------
# REGION | Root Paths
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ModulesRoot
            @na_modules_root ||= File.expand_path('../..', __dir__)
        end

        def self.Na__ComponentEditorTools__PluginRoot
            @na_plugin_root ||= File.expand_path('..', self.Na__ComponentEditorTools__ModulesRoot)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | UI Asset Paths
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__UiDirectory
            File.join(self.Na__ComponentEditorTools__ModulesRoot, '05__UserInterface')
        end

        def self.Na__ComponentEditorTools__UiLayoutFilePath
            File.join(self.Na__ComponentEditorTools__UiDirectory, 'Na__ComponentEditorTools__UiLayout__.html')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plugin And Shared Asset Paths
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LocalAssetsDirectory
            File.join(self.Na__ComponentEditorTools__ModulesRoot, '01__AppAssets__ComponentEditorTools')
        end

        def self.Na__ComponentEditorTools__SharedAssetsDirectory
            File.join(self.Na__ComponentEditorTools__PluginRoot, 'Na__Common__PluginDependencies')
        end

        def self.Na__ComponentEditorTools__LogoPath
            local_logo_path = File.join(
                self.Na__ComponentEditorTools__LocalAssetsDirectory,
                'Na__ComponentEditorTools__Brand__NobleLogo__.png'
            )
            return local_logo_path if File.exist?(local_logo_path)

            File.join(self.Na__ComponentEditorTools__SharedAssetsDirectory, 'IMG01__PNG__NaCompanyLogo.png')
        end

        def self.Na__ComponentEditorTools__ToolbarIconPath
            File.join(self.Na__ComponentEditorTools__SharedAssetsDirectory, 'IMG02__ICN__NaCompanyIcon.png')
        end

        def self.Na__ComponentEditorTools__LogoFileUri
            logo_path = self.Na__ComponentEditorTools__LogoPath
            return '' unless File.exist?(logo_path)

            normalized = logo_path.tr('\\', '/').sub(%r{^/+}, '')
            'file:///' + normalized.gsub(' ', '%20')
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
