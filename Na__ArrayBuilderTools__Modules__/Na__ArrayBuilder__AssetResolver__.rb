# =============================================================================
# NA ARRAY BUILDER TOOLS - ASSET RESOLVER
# =============================================================================
#
# FILE       : Na__ArrayBuilder__AssetResolver__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__AssetResolver
# PURPOSE    : Resolve toolbar / dialog branding paths (Profile Path Tracer parity)
# CREATED    : 2026
#
# =============================================================================

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__AssetResolver

        NA_PLUGIN_ROOT                = File.dirname(__FILE__).freeze
        NA_LOCAL_ASSETS_FOLDER        = '02__PluginImageAssets'.freeze
        NA_MAIN_ICON_FILENAME         = 'Na__ArrayBuilder__Icon__.png'.freeze
        NA_SHARED_DEPENDENCIES_FOLDER = 'Na__Common__PluginDependencies'.freeze
        NA_SHARED_MAIN_ICON_FILENAME  = 'IMG02__ICN__NaCompanyIcon.png'.freeze

        def self.Na__Assets__PluginRoot
            NA_PLUGIN_ROOT
        end

        def self.Na__Assets__SharedDependenciesRoot
            File.join(NA_PLUGIN_ROOT, '..', NA_SHARED_DEPENDENCIES_FOLDER)
        end

        def self.Na__Assets__LocalAssetsRoot
            File.join(NA_PLUGIN_ROOT, NA_LOCAL_ASSETS_FOLDER)
        end

        # Same resolution order as Na__ProfileTools__ProfilePathTracer::Na__AssetResolver
        def self.Na__Assets__MainIconPath
            local_icon_path = File.join(self.Na__Assets__LocalAssetsRoot, NA_MAIN_ICON_FILENAME)
            return local_icon_path if File.exist?(local_icon_path)

            File.join(self.Na__Assets__SharedDependenciesRoot, NA_SHARED_MAIN_ICON_FILENAME)
        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
