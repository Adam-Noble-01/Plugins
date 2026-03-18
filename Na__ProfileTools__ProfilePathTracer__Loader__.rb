# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__Loader__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Bootstrap loader for Profile Path Tracer plugin
# CREATED    : 2026
#
# DESCRIPTION:
# - Registers the plugin command in SketchUp.
# - Loads the modular main orchestrator from the Modules folder.
# - Preloads DataLib cache keys required by the ecosystem contract.
# - Contains no business logic (loader only).
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

    # -------------------------------------------------------------------------
    # REGION | Path Setup
    # -------------------------------------------------------------------------

        na_plugin_root      = File.dirname(__FILE__)
        na_plugin_folder    = File.join(na_plugin_root, 'Na__ProfileTools__ProfilePathTracer__Modules__')
        na_main_file        = File.join(na_plugin_folder, 'Na__ProfileTools__ProfilePathTracer__Main__.rb')
        na_fallback_icon    = File.join(na_plugin_folder, '02__PluginImageAssets', 'Na__ProfileTools__ProfilePathTracer__Icon__.png')
        na_plugin_name      = 'Na Profile Path Tracer'
        na_toolbar_name     = 'NA Profile Tools'
        na_command_text     = 'Na__ProfileTools__ProfilePathTracer'

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Script Loading
    # -------------------------------------------------------------------------

        if File.exist?(na_main_file)
            begin
                require na_main_file
                puts "✓ [Na__ProfilePathTracer] Main module loaded"
            rescue => na_error
                puts "✗ [Na__ProfilePathTracer] Failed to load main file: #{na_error.message}"
                puts na_error.backtrace.first(6).join("\n")
            end
        else
            puts "✗ [Na__ProfilePathTracer] Main file not found: #{na_main_file}"
        end

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Startup Data Preload (DataLib)
    # -------------------------------------------------------------------------

        begin
            if defined?(Na__ProfileTools__ProfilePathTracer)
                Na__ProfileTools__ProfilePathTracer.Na__Bootstrap__PreloadData
            elsif defined?(Na__DataLib__CacheData)
                # Fallback preload for early startup if plugin bootstrap is not yet available.
                Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
                Na__DataLib__CacheData.Na__Cache__LoadData(:materials)
            end
        rescue => na_error
            puts "⚠ [Na__ProfilePathTracer] Data preload warning: #{na_error.message}"
        end

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Command and Menu Registration
    # -------------------------------------------------------------------------

        na_command = UI::Command.new(na_plugin_name) do
            if defined?(Na__ProfileTools__ProfilePathTracer)
                Na__ProfileTools__ProfilePathTracer.Na__PublicApi__OpenDialog
            else
                UI.messagebox('Profile Path Tracer module is not loaded.')
            end
        end

        na_command.menu_text       = na_command_text
        na_command.tooltip         = na_plugin_name
        na_command.status_bar_text = 'Open Profile Path Tracer dialog'

        begin
            if defined?(Na__ProfileTools__ProfilePathTracer::Na__AssetResolver)
                na_icon_path = Na__ProfileTools__ProfilePathTracer::Na__AssetResolver.Na__Assets__MainIconPath
                if na_icon_path && File.exist?(na_icon_path)
                    na_command.small_icon = na_icon_path
                    na_command.large_icon = na_icon_path
                end
            elsif File.exist?(na_fallback_icon)
                na_command.small_icon = na_fallback_icon
                na_command.large_icon = na_fallback_icon
            end
        rescue => na_error
            puts "⚠ [Na__ProfilePathTracer] Icon resolution warning: #{na_error.message}"
        end

        UI.menu('Plugins').add_item(na_command)

        na_toolbar = UI::Toolbar.new(na_toolbar_name)
        na_toolbar.add_item(na_command)
        na_toolbar.show if na_toolbar.get_last_state != TB_HIDDEN

    # endregion ---------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
