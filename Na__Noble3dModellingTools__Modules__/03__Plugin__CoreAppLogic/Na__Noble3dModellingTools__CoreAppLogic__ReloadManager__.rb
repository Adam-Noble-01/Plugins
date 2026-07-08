# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CORE RELOAD MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__ReloadManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ReloadManager
# PURPOSE    : Hot reload Ruby files and refresh dialog/config state
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# Reloading invalidates and refreshes config-driven UI state. Tool placement,
# grouping, labels, and command metadata should be changed in the JSON registry,
# then reloaded here, rather than hardcoded into Ruby UI scripts.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ReloadManager

# -----------------------------------------------------------------------------
# REGION | Public Reload API
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__ReloadPluginData
            standard_cache_sources = na_refresh_standard_cache_before_reload
            ruby_reload_result = self.Na__Noble3dModellingTools__ReloadRubyFiles
            Na__ConfigLoader.Na__Noble3dModellingTools__InvalidateConfigCache

            if defined?(Na__ModuleLoaders) &&
               Na__ModuleLoaders.respond_to?(:Na__Noble3dModellingTools__ResetModuleLoadState)
                Na__ModuleLoaders.Na__Noble3dModellingTools__ResetModuleLoadState
                Na__ModuleLoaders.Na__Noble3dModellingTools__LoadFeatureModules
            end

            na_reset_feature_dialogs_after_reload
            Na__DialogManager.Na__Noble3dModellingTools__RefreshDialogIfVisible

            cache_has_failures = standard_cache_sources.values.any? { |source| source == :failed }
            has_error = ruby_reload_result[:error_count] > 0 || cache_has_failures
            summary_text = "Ruby reload: #{ruby_reload_result[:reload_count]} loaded, #{ruby_reload_result[:error_count]} errors. " \
                "SSOT cache: #{na_standard_cache_summary_text(standard_cache_sources)}."

            {
                success: !has_error,
                message: summary_text,
                reload_count: ruby_reload_result[:reload_count],
                error_count: ruby_reload_result[:error_count],
                standard_cache_sources: standard_cache_sources
            }
        rescue => error
            {
                success: false,
                message: "Reload failed: #{error.class}: #{error.message}",
                reload_count: 0,
                error_count: 1
            }
        end

        def self.Na__Noble3dModellingTools__ReloadRubyFiles
            rb_files = na_module_rb_files
            reload_count = 0
            error_count = 0

            rb_files.each do |rb_file|
                begin
                    load rb_file
                    reload_count += 1
                rescue => error
                    puts "[Na__Noble3dModellingTools] Reload error in #{File.basename(rb_file)}: #{error.class}: #{error.message}"
                    error_count += 1
                end
            end

            na_reload_root_loader
            { reload_count: reload_count, error_count: error_count }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_module_rb_files
            modules_root = Na__PathResolver.Na__Noble3dModellingTools__ModulesRoot
            Dir.glob(File.join(modules_root, '**', '*.rb')).sort
        end

        def self.na_reload_root_loader
            root_loader_path = Na__PathResolver.Na__Noble3dModellingTools__RootLoaderFilePath
            return unless File.exist?(root_loader_path)

            load root_loader_path
        rescue => error
            puts "[Na__Noble3dModellingTools] Root loader reload warning: #{error.class}: #{error.message}"
        end

        def self.na_refresh_standard_cache_before_reload
            return {} unless defined?(Na__StandardDataCache) &&
                Na__StandardDataCache.respond_to?(:Na__Noble3dModellingTools__PurgeAndForceReloadStandardCache)

            Na__StandardDataCache.Na__Noble3dModellingTools__PurgeAndForceReloadStandardCache
        rescue => error
            puts "[Na__Noble3dModellingTools] Standard cache refresh warning: #{error.class}: #{error.message}"
            {}
        end

        def self.na_reset_feature_dialogs_after_reload
            if defined?(Na__ImageCarousel__DialogManager) &&
               Na__ImageCarousel__DialogManager.respond_to?(:Na__ImageCarousel__DialogManager__ResetDialog)
                Na__ImageCarousel__DialogManager.Na__ImageCarousel__DialogManager__ResetDialog
                puts '[Na__Noble3dModellingTools] Reload reset Image Viewer dialog.'
            end

            if defined?(Na__SelectSimilarFilter__DialogManager) &&
               Na__SelectSimilarFilter__DialogManager.respond_to?(:Na__SelectSimilarFilter__DialogManager__ResetDialog)
                Na__SelectSimilarFilter__DialogManager.Na__SelectSimilarFilter__DialogManager__ResetDialog
                puts '[Na__Noble3dModellingTools] Reload reset Select Similar Filter dialog.'
            end
        rescue => error
            puts "[Na__Noble3dModellingTools] Feature dialog reset warning: #{error.class}: #{error.message}"
        end

        def self.na_standard_cache_summary_text(source_map)
            return 'not-loaded' if source_map.nil? || source_map.empty?

            ordered_keys = if defined?(Na__StandardDataCache) &&
                Na__StandardDataCache.respond_to?(:Na__Noble3dModellingTools__StandardDataKeys)
                Na__StandardDataCache.Na__Noble3dModellingTools__StandardDataKeys
            else
                source_map.keys
            end

            ordered_keys.map do |file_key|
                source = source_map[file_key] || :failed
                "#{file_key}=#{source}"
            end.join(', ')
        end

# endregion -------------------------------------------------------------------

    end # module Na__ReloadManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
