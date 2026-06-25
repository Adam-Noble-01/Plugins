# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC RELOAD MANAGER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__CoreAppLogic__ReloadManager__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__ReloadManager
# PURPOSE    : Hot reload all Ruby files and refresh the dialog/config state
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Globs all .rb files under the modules root, calls `load` on each.
# - Invalidates config cache so updated JSON is picked up immediately.
# - Refreshes the visible dialog after reload.
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__ReloadManager

# -----------------------------------------------------------------------------
# REGION | Public Reload API
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__ReloadPluginData
            ruby_result = self.Na__ValeVisionCloudSync__ReloadRubyFiles
            Na__ConfigLoader.Na__ValeVisionCloudSync__InvalidateConfigCache

            if defined?(Na__ModuleLoaders) &&
               Na__ModuleLoaders.respond_to?(:Na__ValeVisionCloudSync__ResetModuleLoadState)
                Na__ModuleLoaders.Na__ValeVisionCloudSync__ResetModuleLoadState
                Na__ModuleLoaders.Na__ValeVisionCloudSync__LoadSyncFeatureModules
            end

            Na__DialogManager.Na__ValeVisionCloudSync__ResetDialog if defined?(Na__DialogManager)
            Na__DialogManager.Na__ValeVisionCloudSync__RefreshDialogIfVisible if defined?(Na__DialogManager)

            has_error    = ruby_result[:error_count] > 0
            summary_text = "Reload: #{ruby_result[:reload_count]} files loaded, #{ruby_result[:error_count]} errors."

            { success: !has_error, message: summary_text, reload_count: ruby_result[:reload_count] }
        rescue => error
            { success: false, message: "Reload failed: #{error.class}: #{error.message}", reload_count: 0 }
        end

        def self.Na__ValeVisionCloudSync__ReloadRubyFiles
            rb_files    = na_module_rb_files
            reload_count = 0
            error_count  = 0

            rb_files.each do |rb_file|
                begin
                    load rb_file
                    reload_count += 1
                rescue => error
                    puts "[Na__ValeVisionCloudSync] Reload error in #{File.basename(rb_file)}: #{error.class}: #{error.message}"
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
            modules_root = Na__PathResolver.Na__ValeVisionCloudSync__ModulesRoot.to_s.tr('\\', '/')  # <-- Dir.glob '\' escape guard
            Dir.glob(File.join(modules_root, '**', '*.rb')).sort
        end

        def self.na_reload_root_loader
            root_path = Na__PathResolver.Na__ValeVisionCloudSync__RootLoaderFilePath
            return unless File.exist?(root_path)

            load root_path
        rescue => error
            puts "[Na__ValeVisionCloudSync] Root loader reload warning: #{error.class}: #{error.message}"
        end

# endregion -------------------------------------------------------------------

    end # module Na__ReloadManager
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
