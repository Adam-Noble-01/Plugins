# =============================================================================
# NA NOBLE3D MODELLING TOOLS - STANDARD DATA CACHE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__StandardDataCache__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__StandardDataCache
# PURPOSE    : Prime and refresh SSOT data cache for Noble3d tools
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# All source data remains in Na__Common__DataLib__CoreSuEntityStandards. This
# wrapper only manages load timing and per-plugin cache directory selection.
#
# =============================================================================

require 'fileutils'
require_relative '../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'

module Na__Noble3dModellingTools
    module Na__StandardDataCache

# -----------------------------------------------------------------------------
# REGION | Constants and State
# -----------------------------------------------------------------------------

        NA_CACHE_SUBFOLDER_NAME = '90__AppCache__TempFilesCache'.freeze
        NA_STANDARD_FILE_KEYS = [
            :materials,
            :edge_materials,
            :tags,
            :components
        ].freeze

        @na_cache_initialized = false
        @na_last_sources = {}

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__PrimeStandardCache(force_reload = false)
            na_initialize_cache_override
            na_load_keys_with_strategy(NA_STANDARD_FILE_KEYS, force_reload)
        end

        def self.Na__Noble3dModellingTools__LoadStandardData(file_key, force_reload = false)
            na_initialize_cache_override
            data_hash = Na__DataLib__CacheData.Na__Cache__LoadData(file_key, force_reload)
            @na_last_sources[file_key] = na_source_for_key(file_key)
            data_hash
        rescue => error
            @na_last_sources[file_key] = :failed
            puts "[Na__Noble3dModellingTools] Standard data load failed for :#{file_key} - #{error.class}: #{error.message}"
            nil
        end

        def self.Na__Noble3dModellingTools__PurgeAndForceReloadStandardCache
            na_initialize_cache_override
            source_map = {}

            NA_STANDARD_FILE_KEYS.each do |file_key|
                begin
                    Na__DataLib__CacheData.Na__Cache__PurgeCacheFile(file_key)
                    Na__DataLib__CacheData.Na__Cache__LoadData(file_key, true)
                    source_map[file_key] = na_source_for_key(file_key)
                    @na_last_sources[file_key] = source_map[file_key]
                rescue => error
                    puts "[Na__Noble3dModellingTools] Standard cache refresh failed for :#{file_key} - #{error.class}: #{error.message}"
                    source_map[file_key] = :failed
                    @na_last_sources[file_key] = :failed
                end
            end

            source_map
        end

        def self.Na__Noble3dModellingTools__LastSource(file_key)
            @na_last_sources[file_key] || na_source_for_key(file_key)
        end

        def self.Na__Noble3dModellingTools__StandardDataKeys
            NA_STANDARD_FILE_KEYS.dup
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        def self.na_initialize_cache_override
            return if @na_cache_initialized

            cache_directory = na_cache_directory_path
            FileUtils.mkdir_p(cache_directory) unless Dir.exist?(cache_directory)
            Na__DataLib__CacheData.Na__Cache__SetCacheDirOverride(cache_directory)
            @na_cache_initialized = true
        end

        def self.na_cache_directory_path
            File.join(
                Na__PathResolver.Na__Noble3dModellingTools__ModulesRoot,
                NA_CACHE_SUBFOLDER_NAME
            )
        end

        def self.na_load_keys_with_strategy(file_keys, force_reload)
            file_keys.each do |file_key|
                begin
                    Na__DataLib__CacheData.Na__Cache__LoadData(file_key, force_reload)
                    @na_last_sources[file_key] = na_source_for_key(file_key)
                rescue => error
                    puts "[Na__Noble3dModellingTools] Standard data prime failed for :#{file_key} - #{error.class}: #{error.message}"
                    @na_last_sources[file_key] = :failed
                end
            end
        end

        def self.na_source_for_key(file_key)
            Na__DataLib__CacheData.Na__Cache__LastSource(file_key) || :failed
        end

# endregion -------------------------------------------------------------------

    end # module Na__StandardDataCache
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
