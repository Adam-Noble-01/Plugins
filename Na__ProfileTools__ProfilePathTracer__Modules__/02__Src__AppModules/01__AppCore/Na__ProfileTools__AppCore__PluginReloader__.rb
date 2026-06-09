# =============================================================================
# NA PROFILE TOOLS - APP CORE - PLUGIN RELOADER
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__PluginReloader__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__PluginReloader
# PURPOSE    : Hot-reload Ruby modules and validate JS assets for dialog refresh
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__PluginReloader

    # -------------------------------------------------------------------------
    # REGION | File Lists
    # -------------------------------------------------------------------------

        NA_RUBY_RELOAD_EXCLUDE_FILES = [].freeze

        NA_JS_SUBFOLDER_FILES = [
            '02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__UiSystem__BridgeBase__.js',
            '02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__UiSystem__MainShell__.js',
            '02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__ProfileStore__.js',
            '02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__TabRouter__.js',
            '02__Src__AppModules/01__AppCore/Na__ProfileTools__AppCore__AppContext__.js',
            '02__Src__AppModules/05__Viewport__2dPreviewEngine/Na__ProfileTools__Viewport__SvgGenerator__.js',
            '02__Src__AppModules/30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__CardRenderer__.js',
            '02__Src__AppModules/30__System__GalleryMode/Na__ProfileTools__Gallery__UiSystem__MainUiLogic__.js',
            '02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js',
            '02__Src__AppModules/31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__UiSystem__Events__.js',
            '02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__MainUiLogic__.js',
            '02__Src__AppModules/32__System__EditProfileMode/Na__ProfileTools__EditProfile__UiSystem__Bridge__.js',
            '02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Config__.js',
            '02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js',
            '02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__Bridge__.js',
            '02__Src__AppModules/33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__UiSystem__MainUiLogic__.js',
            '02__Src__AppModules/35__System__SettingsMode/Na__ProfileTools__AppUtils__SettingsTab__UiLogic__.js',
            '02__Src__AppModules/35__System__SettingsMode/Na__ProfileTools__AppUtils__SettingsTab__Bridge__.js'
        ].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Reload__PluginFiles(plugin_root_path)
            rb_reload_count = 0
            js_asset_count = 0
            error_messages = []

            rb_files = Dir.glob(File.join(plugin_root_path, '02__Src__AppModules', '**', '*.rb')).sort
            rb_files.reject! do |rb_file|
                NA_RUBY_RELOAD_EXCLUDE_FILES.include?(File.basename(rb_file))
            end

            rb_files.each do |rb_file|
                begin
                    previous_verbose = $VERBOSE
                    $VERBOSE = nil
                    load rb_file
                    rb_reload_count += 1
                rescue => error
                    error_messages << "Ruby reload failed for #{File.basename(rb_file)}: #{error.message}"
                ensure
                    $VERBOSE = previous_verbose
                end
            end

            NA_JS_SUBFOLDER_FILES.each do |js_relative_path|
                js_filepath = File.join(plugin_root_path, js_relative_path)
                if File.exist?(js_filepath)
                    js_asset_count += 1
                else
                    error_messages << "Missing JS asset: #{js_relative_path}"
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
