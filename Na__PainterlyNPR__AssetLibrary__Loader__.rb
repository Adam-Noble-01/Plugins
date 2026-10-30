# =============================================================================
# NA PAINTERLYNPR - ASSET LIBRARY - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__PainterlyNPR__AssetLibrary__Loader__.rb
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : SketchUp entrypoint - require AppCore, register the commands,
#              the Extensions submenu and the toolbar for the SketchUp side of
#              PainterlyNPR's asset library (catalogue, place, author, validate).
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - Loader only: path setup, require the AppCore main file, register two
#   UI::Commands (Open Asset Library, Reload Plugin Data), the submenu and a
#   toolbar. All logic lives in Na__PainterlyNPR__AssetLibrary__Modules__.
# - The library is PainterlyNPR's own (12__Data__AssetLibrary in the
#   Na__PainterlyNPR repo). This plugin reads it, places its assets, and files
#   new ones into it by the rules of its register; PainterlyNPR's build
#   utility stays the one judge of a number and of a valid asset.
# - Reload Plugin Data must work even when a module failed to load, so the
#   command falls back to loading the main file again by path.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

    # -------------------------------------------------------------------------
    # REGION | Path Setup
    # -------------------------------------------------------------------------

        na_plugin_root   = File.dirname(__FILE__)
        na_plugin_folder = File.join(na_plugin_root, 'Na__PainterlyNPR__AssetLibrary__Modules__')
        na_main_file     = File.join(na_plugin_folder, '02__Src__AppModules', '01__AppCore', 'Na__PainterlyAssets__AppCore__Main__.rb')
        na_icon_file     = File.join(na_plugin_folder, '01__AppAssets__PainterlyAssets', 'Na__PainterlyAssets__Brand__ToolbarIcon__.svg')
        na_plugin_name   = 'Na PainterlyNPR Assets'

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Script Loading
    # -------------------------------------------------------------------------

        if File.exist?(na_main_file)
            begin
                require na_main_file
                puts '[+] Na PainterlyNPR Assets loaded successfully'
            rescue ScriptError, StandardError => na_error                                       # <-- ScriptError too: a SyntaxError must not take the menu with it
                puts "[!] Error loading Na PainterlyNPR Assets: #{na_error.class}: #{na_error.message}"
                puts na_error.backtrace.first(8).join("\n")
            end
        else
            puts "[!] Na PainterlyNPR Assets main file not found at: #{na_main_file}"
        end

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Commands
    # -------------------------------------------------------------------------

        # The blocks look the module up BY NAME each time, so they keep working
        # after Reload Plugin Data has redefined everything behind them.
        na_open_command = UI::Command.new('Open Asset Library') do
            if defined?(Na__PainterlyAssets) && Na__PainterlyAssets.respond_to?(:Na__PublicApi__OpenDialog)
                Na__PainterlyAssets.Na__PublicApi__OpenDialog
            else
                UI.messagebox('Na PainterlyNPR Assets did not load. See the Ruby Console, or use Reload Plugin Data.')
            end
        end
        na_open_command.menu_text       = 'Open Asset Library'
        na_open_command.tooltip         = na_plugin_name
        na_open_command.status_bar_text = 'Browse, place and author PainterlyNPR library assets (trees, plants, furniture, boundaries)'

        na_reload_command = UI::Command.new('Reload Plugin Data') do
            if defined?(Na__PainterlyAssets) && Na__PainterlyAssets.respond_to?(:Na__PublicApi__ReloadPlugin)
                Na__PainterlyAssets.Na__PublicApi__ReloadPlugin
            else
                begin
                    load na_main_file                                                               # <-- A module that failed to parse never defined the reloader
                    puts '[+] Na PainterlyNPR Assets reloaded from its main file'
                rescue ScriptError, StandardError => na_error
                    UI.messagebox("Na PainterlyNPR Assets could not reload.\n\n#{na_error.class}: #{na_error.message}")
                end
            end
        end
        na_reload_command.menu_text       = 'Reload Plugin Data'
        na_reload_command.tooltip         = "#{na_plugin_name}: Reload Plugin Data"
        na_reload_command.status_bar_text = 'Reload every Ruby, HTML, CSS and JS file of Na PainterlyNPR Assets without restarting SketchUp'

        if File.exist?(na_icon_file)
            na_open_command.small_icon = na_icon_file
            na_open_command.large_icon = na_icon_file
        end

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Menu and Toolbar
    # -------------------------------------------------------------------------

        na_submenu = UI.menu('Extensions').add_submenu(na_plugin_name)
        na_submenu.add_item(na_open_command)
        na_submenu.add_item(na_reload_command)

        na_toolbar = UI::Toolbar.new(na_plugin_name)
        na_toolbar.add_item(na_open_command)
        na_toolbar.show if na_toolbar.get_last_state != TB_HIDDEN

    # endregion ---------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
