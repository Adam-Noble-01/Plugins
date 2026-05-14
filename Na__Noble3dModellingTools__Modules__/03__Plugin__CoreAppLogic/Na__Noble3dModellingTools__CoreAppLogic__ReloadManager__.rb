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
            ruby_reload_result = self.Na__Noble3dModellingTools__ReloadRubyFiles
            Na__ConfigLoader.Na__Noble3dModellingTools__InvalidateConfigCache

            if defined?(Na__ModuleLoaders) &&
               Na__ModuleLoaders.respond_to?(:Na__Noble3dModellingTools__ResetModuleLoadState)
                Na__ModuleLoaders.Na__Noble3dModellingTools__ResetModuleLoadState
                Na__ModuleLoaders.Na__Noble3dModellingTools__LoadFeatureModules
            end

            Na__DialogManager.Na__Noble3dModellingTools__RefreshDialogIfVisible

            has_error = ruby_reload_result[:error_count] > 0
            summary_text = "Ruby reload: #{ruby_reload_result[:reload_count]} loaded, #{ruby_reload_result[:error_count]} errors."

            {
                success: !has_error,
                message: summary_text,
                reload_count: ruby_reload_result[:reload_count],
                error_count: ruby_reload_result[:error_count]
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

# endregion -------------------------------------------------------------------

    end # module Na__ReloadManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
