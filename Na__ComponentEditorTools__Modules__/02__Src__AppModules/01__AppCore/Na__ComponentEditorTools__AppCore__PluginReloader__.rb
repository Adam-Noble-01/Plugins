# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE PLUGIN RELOADER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__PluginReloader__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__PluginReloader
# PURPOSE    : Hot reload Ruby module files for rapid plugin iteration
# CREATED    : 2026
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__PluginReloader

# -----------------------------------------------------------------------------
# REGION | Public Reload API
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ReloadPluginData(dialog_reference = nil, active_tab_id = 'overview')
            reload_result = self.Na__ComponentEditorTools__ReloadRubyFiles
            UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)

            dialog_was_visible = dialog_reference && dialog_reference.respond_to?(:visible?) && dialog_reference.visible?
            dialog_reference.close if dialog_was_visible

            if defined?(Na__ComponentEditorTools::Na__DialogManager)
                Na__DialogManager.Na__ComponentEditorTools__SetActiveTab(active_tab_id)
                Na__DialogManager.Na__ComponentEditorTools__PushStatus(
                    reload_result[:message],
                    reload_result[:success] ? 'success' : 'error'
                )
                Na__DialogManager.Na__ComponentEditorTools__ShowDialog if dialog_was_visible
            end

            reload_result
        rescue => error
            {
                success: false,
                message: "Reload failed: #{error.class}: #{error.message}",
                reload_count: 0,
                error_count: 1
            }
        end

        def self.Na__ComponentEditorTools__ReloadRubyFiles
            rb_files = self.Na__ComponentEditorTools__ModuleRubyFiles
            reload_count = 0
            error_count = 0

            rb_files.each do |rb_file|
                previous_verbose = $VERBOSE

                begin
                    $VERBOSE = nil
                    load rb_file
                    reload_count += 1
                rescue => error
                    error_count += 1
                    puts "[Na__ComponentEditorTools] Reload error in #{File.basename(rb_file)}: #{error.class}: #{error.message}"
                ensure
                    $VERBOSE = previous_verbose
                end
            end

            {
                success: error_count.zero?,
                message: "Ruby reload: #{reload_count} loaded, #{error_count} errors.",
                reload_count: reload_count,
                error_count: error_count
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ModuleRubyFiles
            modules_root = Na__PathResolver.Na__ComponentEditorTools__ModulesRoot
            Dir.glob(File.join(modules_root, '02__Src__AppModules', '**', '*.rb')).sort
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
