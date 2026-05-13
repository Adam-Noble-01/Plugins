# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - ASSET RESOLVER
# =============================================================================
#
# FILE       : Na__MeshDecimator__AppUtils__AssetResolver__.rb
# NAMESPACE  : Na__MeshDecimator::Na__AppUtils::Na__AssetResolver
# PURPOSE    : Resolve local/shared icon and branding asset paths.
#              Local assets take priority; shared Na__Common__PluginDependencies
#              assets are used as fallback.
#
# =============================================================================

module Na__MeshDecimator
    module Na__AppUtils
        module Na__AssetResolver

        # -------------------------------------------------------------------------
        # REGION | Module Constants and File Paths
        # -------------------------------------------------------------------------

            NA_ASSETS_MODULE_ROOT         = File.expand_path('../..', File.dirname(__FILE__)).freeze
            NA_LOCAL_ASSETS_FOLDER        = '01__AppAssets__MeshDecimator'.freeze
            NA_SHARED_DEPENDENCIES_FOLDER = 'Na__Common__PluginDependencies'.freeze

            NA_MAIN_ICON_FILENAME         = 'PluginIcon__QuadraticDecimator__248px__.png'.freeze
            NA_SHARED_MAIN_ICON_FILENAME  = 'IMG02__ICN__NaCompanyIcon.png'.freeze
            NA_SHARED_LOGO_FILENAME       = 'IMG01__PNG__NaCompanyLogo.png'.freeze

        # endregion ----------------------------------------------------------------

            def self.Na__Assets__PluginRoot
                NA_ASSETS_MODULE_ROOT
            end

            def self.Na__Assets__SharedDependenciesRoot
                File.join(NA_ASSETS_MODULE_ROOT, '..', NA_SHARED_DEPENDENCIES_FOLDER)
            end

            def self.Na__Assets__LocalAssetsRoot
                File.join(NA_ASSETS_MODULE_ROOT, NA_LOCAL_ASSETS_FOLDER)
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
end

# =============================================================================
# END OF FILE
# =============================================================================
