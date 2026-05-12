# =============================================================================
# NA PROFILE TOOLS - APP CORE - DEPENDENCY BOOTSTRAP
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__DependencyBootstrap__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__DependencyBootstrap
# PURPOSE    : Load shared DataLib and configure per-plugin cache directory
#
# POLICY     : Edge materials use the strict URL+cache loader in EdgeColourManager.
#              This module only configures the cache dir override and loads tags/
#              materials via Na__DataLib__CacheData (which has a local fallback).
#
# =============================================================================

require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'

module Na__ProfileTools__ProfilePathTracer
    module Na__DependencyBootstrap

    # -------------------------------------------------------------------------
    # REGION | DataLib Cache Keys
    # -------------------------------------------------------------------------

        NA_DATALIB_CACHE_KEY_TAGS      = :tags
        NA_DATALIB_CACHE_KEY_MATERIALS = :materials

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Bootstrap Entry Point
    # -------------------------------------------------------------------------

        def self.Na__Dependencies__PreloadCoreData
            self.Na__Dependencies__ConfigureCacheDir
            self.Na__Dependencies__LoadTags
            self.Na__Dependencies__LoadMaterials
            self.Na__Dependencies__LoadEdgeMaterials
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cache Directory Override
    # -------------------------------------------------------------------------

        def self.Na__Dependencies__ConfigureCacheDir
            return unless defined?(Na__DataLib__CacheData)
            return unless Na__DataLib__CacheData.respond_to?(:Na__Cache__SetCacheDirOverride)

            cache_dir = File.join(
                Na__ProfileTools__ProfilePathTracer::NA_PLUGIN_ROOT,
                '90__AppCache__TempFilesCache'
            )
            Na__DataLib__CacheData.Na__Cache__SetCacheDirOverride(cache_dir)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Cache dir override failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Data Loaders
    # -------------------------------------------------------------------------

        def self.Na__Dependencies__LoadTags
            Na__DataLib__CacheData.Na__Cache__LoadData(NA_DATALIB_CACHE_KEY_TAGS)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Failed to preload tags from DataLib: #{error.message}")
            nil
        end

        def self.Na__Dependencies__LoadMaterials
            Na__DataLib__CacheData.Na__Cache__LoadData(NA_DATALIB_CACHE_KEY_MATERIALS)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Failed to preload materials from DataLib: #{error.message}")
            nil
        end

        def self.Na__Dependencies__LoadEdgeMaterials
            return unless defined?(Na__EdgeColourManager)
            Na__EdgeColourManager.Na__EdgeColours__ForceRefreshFromUrl
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Edge colour manager bootstrap failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
