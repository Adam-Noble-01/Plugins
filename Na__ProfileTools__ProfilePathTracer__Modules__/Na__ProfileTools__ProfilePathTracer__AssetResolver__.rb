# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - ASSET RESOLVER
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__AssetResolver__.rb
# PURPOSE    : Resolve local/shared icon and branding asset paths
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__AssetResolver

    # -------------------------------------------------------------------------
    # REGION | Module Constants and File Paths
    # -------------------------------------------------------------------------

        NA_PLUGIN_ROOT                = File.dirname(__FILE__).freeze
        NA_LOCAL_ASSETS_FOLDER        = '02__PluginImageAssets'.freeze
        NA_MAIN_ICON_FILENAME         = 'Na__ProfileTools__ProfilePathTracer__Icon__.png'.freeze
        NA_SHARED_DEPENDENCIES_FOLDER = 'Na__Common__PluginDependencies'.freeze

        NA_SHARED_MAIN_ICON_FILENAME  = 'IMG02__ICN__NaCompanyIcon.png'.freeze
        NA_SHARED_LOGO_FILENAME       = 'IMG01__PNG__NaCompanyLogo.png'.freeze

    # endregion ----------------------------------------------------------------

        def self.Na__Assets__PluginRoot
            NA_PLUGIN_ROOT
        end

        def self.Na__Assets__SharedDependenciesRoot
            File.join(NA_PLUGIN_ROOT, '..', NA_SHARED_DEPENDENCIES_FOLDER)
        end

        def self.Na__Assets__LocalAssetsRoot
            File.join(NA_PLUGIN_ROOT, NA_LOCAL_ASSETS_FOLDER)
        end

        def self.Na__Assets__MainIconPath
            local_icon_path = File.join(self.Na__Assets__LocalAssetsRoot, NA_MAIN_ICON_FILENAME)
            return local_icon_path if File.exist?(local_icon_path)

            File.join(self.Na__Assets__SharedDependenciesRoot, NA_SHARED_MAIN_ICON_FILENAME)
        end

        def self.Na__Assets__CompanyLogoPath
            File.join(self.Na__Assets__SharedDependenciesRoot, NA_SHARED_LOGO_FILENAME)
        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
