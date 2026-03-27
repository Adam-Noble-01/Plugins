# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PLUGIN RELOADER
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__PluginReloader__.rb
# PURPOSE    : Hot reload Ruby modules + validate UI assets for dialog refresh
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__PluginReloader

    # -------------------------------------------------------------------------
    # REGION | File Lists
    # -------------------------------------------------------------------------

        NA_UI_JS_FILES = [
            'Na__ProfileTools__ProfilePathTracer__Ui__Config__.js',
            'Na__ProfileTools__ProfilePathTracer__Ui__Controls__.js',
            'Na__ProfileTools__ProfilePathTracer__Ui__Events__.js',
            'Na__ProfileTools__ProfilePathTracer__Viewport__SvgGenerator__.js',
            'Na__ProfileTools__ProfilePathTracer__UiLogic__.js',
            'Na__ProfileTools__ProfilePathTracer__UiEventToRubyApiBridge__.js'
        ].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Reload__PluginFiles(plugin_root_path)
            rb_reload_count = 0
            js_asset_count = 0
            error_messages = []

            rb_files = Dir.glob(File.join(plugin_root_path, '*.rb')).sort
            rb_files.each do |rb_file|
                begin
                    load rb_file
                    rb_reload_count += 1
                rescue => error
                    error_messages << "Ruby reload failed for #{File.basename(rb_file)}: #{error.message}"
                end
            end

            NA_UI_JS_FILES.each do |js_filename|
                js_filepath = File.join(plugin_root_path, js_filename)
                if File.exist?(js_filepath)
                    js_asset_count += 1
                else
                    error_messages << "Missing JS asset: #{js_filename}"
                end
            end

            UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)

            total_count = rb_reload_count + js_asset_count
            has_errors = !error_messages.empty?
            status_message = if has_errors
                                "Reloaded #{total_count} files (#{rb_reload_count} Ruby, #{js_asset_count} JS) with #{error_messages.length} issues."
                             else
                                "Reloaded #{total_count} files (#{rb_reload_count} Ruby, #{js_asset_count} JS)."
                             end

            {
                'isSuccess' => !has_errors,
                'statusMessage' => status_message,
                'rubyFileCount' => rb_reload_count,
                'jsFileCount' => js_asset_count,
                'issues' => error_messages
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
