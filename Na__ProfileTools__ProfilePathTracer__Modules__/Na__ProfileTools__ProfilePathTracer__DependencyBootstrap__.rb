# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - DEPENDENCY BOOTSTRAP
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__DependencyBootstrap__.rb
# PURPOSE    : Centralized external dependency loading (DataLib + shared data)
# CREATED    : 2026
#
# =============================================================================

require_relative '../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'

module Na__ProfileTools__ProfilePathTracer
    module Na__DependencyBootstrap

    # -------------------------------------------------------------------------
    # REGION | DataLib Cache Keys
    # -------------------------------------------------------------------------

        NA_DATALIB_CACHE_KEY_TAGS      = :tags
        NA_DATALIB_CACHE_KEY_MATERIALS = :materials

    # endregion ----------------------------------------------------------------

        # DataLib is the source of truth for standards in this ecosystem.
        def self.Na__Dependencies__PreloadCoreData
            self.Na__Dependencies__LoadTags
            self.Na__Dependencies__LoadMaterials
        end

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

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
