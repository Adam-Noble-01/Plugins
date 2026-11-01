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
# - Loader only: path setup, require the AppCore main file, register the
#   UI::Commands (Open Asset Library, NPR Viewport, NPR Parameters, Live NPR
#   Updates, Reload Remote Plugin Files, Reload Plugin Data), the submenu and a
#   toolbar. All logic lives in Na__PainterlyNPR__AssetLibrary__Modules__.
# - The toolbar (v0.2.0): the asset library, the NPR Viewport (PainterlyNPR's
#   drawing of the model, nothing else), the NPR Parameters (every parameter
#   the engine has) and Live NPR Updates, pressed while on.
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
        na_icon_folder   = File.join(na_plugin_folder, '01__AppAssets__PainterlyAssets')
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

        # The NPR windows (v0.2.0), each looked up by name like the commands above
        na_npr_call = lambda do |api, what|
            if defined?(Na__PainterlyAssets) && Na__PainterlyAssets.respond_to?(api)
                Na__PainterlyAssets.send(api)
            else
                UI.messagebox("Na PainterlyNPR Assets did not load, so #{what} cannot open. See the Ruby Console, or use Reload Plugin Data.")
            end
        end

        na_viewport_command = UI::Command.new('NPR Viewport') { na_npr_call.call(:Na__PublicApi__OpenNprViewport, 'the NPR Viewport') }
        na_viewport_command.menu_text       = 'NPR Viewport'
        na_viewport_command.tooltip         = 'NPR Viewport'
        na_viewport_command.status_bar_text = 'PainterlyNPR\'s pen and wash drawing of this model, in a window of its own, following SketchUp\'s camera'

        na_parameters_command = UI::Command.new('NPR Parameters') { na_npr_call.call(:Na__PublicApi__OpenNprParameters, 'the NPR Parameters') }
        na_parameters_command.menu_text       = 'NPR Parameters'
        na_parameters_command.tooltip         = 'NPR Parameters'
        na_parameters_command.status_bar_text = 'Every parameter of PainterlyNPR\'s drawing (pen, wash, paper, light, sky) for the NPR Viewport'

        na_live_command = UI::Command.new('Live NPR Updates') { na_npr_call.call(:Na__PublicApi__ToggleNprLive, 'live NPR updates') }
        na_live_command.menu_text       = 'Live NPR Updates'
        na_live_command.tooltip         = 'Live NPR Updates (on or off)'
        na_live_command.status_bar_text = 'On: the NPR Viewport follows the camera and every change to the model. Off: it holds still while you work'
        na_live_command.set_validation_proc do
            live = defined?(Na__PainterlyAssets) && Na__PainterlyAssets.respond_to?(:Na__PublicApi__NprLiveOn?) && Na__PainterlyAssets.Na__PublicApi__NprLiveOn?
            live ? MF_CHECKED : MF_UNCHECKED                                                   # <-- The button shows pressed while live
        end

        na_remote_command = UI::Command.new('Reload Remote Plugin Files') { na_npr_call.call(:Na__PublicApi__ReloadRemotePluginFiles, 'the remote plugin files') }
        na_remote_command.menu_text       = 'Reload Remote Plugin Files'
        na_remote_command.tooltip         = "#{na_plugin_name}: Reload Remote Plugin Files"
        na_remote_command.status_bar_text = 'Download PainterlyNPR\'s latest commit from its GitHub repo again, then reload the NPR windows onto it'

        {
            na_viewport_command   => 'Na__PainterlyAssets__Toolbar__NprViewport__.svg',
            na_parameters_command => 'Na__PainterlyAssets__Toolbar__NprParameters__.svg',
            na_live_command       => 'Na__PainterlyAssets__Toolbar__NprLiveOn__.svg'
        }.each do |command, icon|
            path = File.join(na_icon_folder, icon)
            next unless File.exist?(path)
            command.small_icon = path
            command.large_icon = path
        end

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Menu and Toolbar
    # -------------------------------------------------------------------------

        na_submenu = UI.menu('Extensions').add_submenu(na_plugin_name)
        na_submenu.add_item(na_open_command)
        na_submenu.add_separator
        na_submenu.add_item(na_viewport_command)
        na_submenu.add_item(na_parameters_command)
        na_submenu.add_item(na_live_command)
        na_submenu.add_item(na_remote_command)
        na_submenu.add_separator
        na_submenu.add_item(na_reload_command)

        na_toolbar = UI::Toolbar.new(na_plugin_name)
        na_toolbar.add_item(na_open_command)
        na_toolbar.add_item(na_viewport_command)
        na_toolbar.add_item(na_parameters_command)
        na_toolbar.add_item(na_live_command)
        na_toolbar.show if na_toolbar.get_last_state != TB_HIDDEN

    # endregion ---------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF LOADER
# =============================================================================
