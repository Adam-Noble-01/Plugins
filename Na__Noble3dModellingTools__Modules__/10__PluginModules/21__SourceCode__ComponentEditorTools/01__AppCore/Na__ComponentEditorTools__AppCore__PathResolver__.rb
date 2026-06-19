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
            File.expand_path('..', __dir__)
        end

        def self.Na__ComponentEditorTools__PluginRoot
            File.expand_path('../../..', self.Na__ComponentEditorTools__ModulesRoot)
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
# REGION | User Data Paths
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__UserDataDirectory
            File.join(self.Na__ComponentEditorTools__ModulesRoot, '07__UserData')
        end

        def self.Na__ComponentEditorTools__UserConfigFilePath
            File.join(self.Na__ComponentEditorTools__UserDataDirectory, 'Na__ComponentEditorTools__UserConfig__.json')
        end

        def self.Na__ComponentEditorTools__CategoryTaxonomyFilePath
            File.join(self.Na__ComponentEditorTools__UserDataDirectory, 'Na__ComponentEditorTools__CategoryTaxonomy__.json')
        end

        def self.Na__ComponentEditorTools__LibraryCacheDirectory
            File.join(Sketchup.temp_dir, 'Na__ComponentEditorTools__LibraryCache')
        end

        def self.Na__ComponentEditorTools__LibraryCacheFilePath
            File.join(self.Na__ComponentEditorTools__LibraryCacheDirectory, 'Na__ComponentEditorTools__LibraryCache__.json')
        end

        def self.Na__ComponentEditorTools__LibraryThumbnailCacheDirectory
            File.join(self.Na__ComponentEditorTools__LibraryCacheDirectory, 'thumbnails')
        end

        def self.Na__ComponentEditorTools__LibraryLastResultFilePath
            File.join(self.Na__ComponentEditorTools__LibraryCacheDirectory, 'Na__ComponentEditorTools__LibraryLastResult__.json')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plugin And Shared Asset Paths
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__SharedAssetsDirectory
            File.join(self.Na__ComponentEditorTools__PluginRoot, 'Na__Common__PluginDependencies')
        end

        def self.Na__ComponentEditorTools__ToolbarIconPath
            File.join(self.Na__ComponentEditorTools__SharedAssetsDirectory, 'IMG02__ICN__NaCompanyIcon.png')
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
