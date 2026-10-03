# =============================================================================
# NA POINT CLOUD TOOLS - POINT CLOUD VIEWER - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__PointCloudTools__PointCloudViewer__Loader__.rb
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : SketchUp entrypoint - require AppCore, register command, menu
#              and toolbar for Na Point Cloud Viewer.
# CREATED    : 03-Oct-2026
#
# DESCRIPTION:
# - Loader only: path setup, require the AppCore main file, register the
#   UI::Command, Extensions menu item and dedicated toolbar.
# - All logic lives in Na__PointCloudTools__PointCloudViewer__Modules__.
# - The viewport overlay is registered per model by AppCore on load, so a
#   model's point cloud draws without the dialog ever being opened.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

    # -------------------------------------------------------------------------
    # REGION | Path Setup
    # -------------------------------------------------------------------------

        na_plugin_root   = File.dirname(__FILE__)
        na_plugin_folder = File.join(na_plugin_root, 'Na__PointCloudTools__PointCloudViewer__Modules__')
        na_main_file     = File.join(na_plugin_folder, '02__Src__AppModules', '01__AppCore', 'Na__PointCloudViewer__AppCore__Main__.rb')
        na_fallback_icon = File.join(na_plugin_folder, '01__AppAssets__PointCloudViewer', 'Na__PointCloudViewer__Brand__CustomToolbarIcon__.png')
        na_plugin_name   = 'Na Point Cloud Viewer'

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Script Loading
    # -------------------------------------------------------------------------

        if File.exist?(na_main_file)
            begin
                require na_main_file
                puts '[+] Na Point Cloud Viewer loaded successfully'
            rescue StandardError => na_error
                puts "[!] Error loading Na Point Cloud Viewer: #{na_error.message}"
                puts na_error.backtrace.first(8).join("\n")
            end
        else
            puts "[!] Na Point Cloud Viewer main file not found at: #{na_main_file}"
        end

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Command, Icon, Menu and Toolbar
    # -------------------------------------------------------------------------

        na_command = UI::Command.new(na_plugin_name) do
            if defined?(Na__PointCloudViewer)
                Na__PointCloudViewer.Na__PublicApi__OpenDialog
            else
                UI.messagebox('Na Point Cloud Viewer did not load. See the Ruby Console for details.')
            end
        end

        na_command.menu_text       = na_plugin_name
        na_command.tooltip         = na_plugin_name
        na_command.status_bar_text = 'Open the Na Point Cloud Viewer (locked, non-snappable point cloud reference)'

        begin
            na_icon_path = nil
            if defined?(Na__PointCloudViewer::Na__AssetResolver)
                na_icon_path = Na__PointCloudViewer::Na__AssetResolver.Na__Assets__ToolbarIconPath
            end
            na_icon_path = na_fallback_icon unless na_icon_path && File.exist?(na_icon_path)
            if File.exist?(na_icon_path)
                na_command.small_icon = na_icon_path
                na_command.large_icon = na_icon_path
            end
        rescue StandardError => na_error
            puts "[!] Na Point Cloud Viewer icon warning: #{na_error.message}"
        end

        UI.menu('Extensions').add_item(na_command)

        na_toolbar = UI::Toolbar.new(na_plugin_name)
        na_toolbar.add_item(na_command)
        na_toolbar.show if na_toolbar.get_last_state != TB_HIDDEN

    # endregion ---------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
