# =============================================================================
# NA SKETCHUP MCP - CORE APP LOADER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__CoreAppLoaders__Main__.rb
# NAMESPACE  : Na__SketchUpMcp
# PURPOSE    : Load every bridge module in order and expose the public entry
#              points the root loader, menu, toolbar and dialog call
# CREATED    : 2026
#
# WHAT THIS PLUGIN IS:
# The SketchUp half of the Na SketchUp MCP server. It listens on 127.0.0.1 for
# the Python MCP server (30__McpServer__Python), which speaks the Model Context
# Protocol to Claude, Codex, Cursor and other agents. Every agent request runs
# here, on SketchUp's main thread, through Na__CommandRouter.
#
# CONFIG-FIRST DESIGN NOTE:
# Tool metadata lives in Na__SketchUpMcp__CoreAppData__ToolRegistry__.json and
# settings in Na__SketchUpMcp__CoreAppData__AppConfig__.json. This file only
# wires modules together; no tool or setting is hardcoded here.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

# Core logic
require_relative '../../03__Plugin__CoreAppLogic/Na__SketchUpMcp__CoreAppLogic__PathResolver__'
require_relative '../../03__Plugin__CoreAppLogic/Na__SketchUpMcp__CoreAppLogic__ConfigLoader__'
require_relative '../../03__Plugin__CoreAppLogic/Na__SketchUpMcp__CoreAppLogic__ActivityLog__'

# Bridge core (error type first: everything raises it)
require_relative '../../04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__McpError__'

# Helpers (@delegate: 06__Plugin__BridgeHelpers)
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Params__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Units__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__LinearMath__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Coordinates__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__EntityResolver__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Traversal__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Serializer__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__Creation__'
require_relative '../../06__Plugin__BridgeHelpers/Na__SketchUpMcp__BridgeHelpers__SolidHealth__'

# Bridge core services
require_relative '../../04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__ConnectionFile__'
require_relative '../../04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__ApiSelfTest__'
require_relative '../../04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__CommandRouter__'
require_relative '../../04__Plugin__BridgeCore/Na__SketchUpMcp__BridgeCore__SocketServer__'

# Tool handlers (@delegate: 10__BridgeHandlers, one file per domain)
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Status__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Model__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__ModelFile__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Query__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Collections__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Selection__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Measure__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Geometry__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Primitives__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__GeometryEdit__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Booleans__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Annotations__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Components__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__AssetLibrary__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__EntityEdit__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Attributes__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Materials__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Tags__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Scenes__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__View__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Actions__'
require_relative '../../10__BridgeHandlers/Na__SketchUpMcp__Handlers__Ruby__'

# User interface and maintenance
require_relative '../../03__Plugin__CoreAppLogic/Na__SketchUpMcp__CoreAppLogic__DialogManager__'
require_relative '../../03__Plugin__CoreAppLogic/Na__SketchUpMcp__CoreAppLogic__ReloadManager__'

module Na__SketchUpMcp

# -----------------------------------------------------------------------------
# REGION | App Observer (stop on quit, track the open model)
# -----------------------------------------------------------------------------

    class Na__AppObserver < Sketchup::AppObserver

        def onQuit
            Na__SocketServer.Na__SocketServer__Stop(silent: true)
        end

        def onNewModel(_model)
            Na__ConnectionFile.Na__ConnectionFile__Refresh
        end

        def onOpenModel(_model)
            Na__ConnectionFile.Na__ConnectionFile__Refresh
        end

    end # class Na__AppObserver

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Bootstrap Entry Points
# -----------------------------------------------------------------------------

    def self.Na__SketchUpMcp__RegisterMenuAndAutoStart
        self.Na__SketchUpMcp__RegisterMenu unless @na_menu_registered
        @na_menu_registered = true

        unless @na_app_observer
            @na_app_observer = Na__AppObserver.new
            Sketchup.add_observer(@na_app_observer)
        end

        return true unless Na__ConfigLoader.Na__ConfigLoader__Get('bridge', 'auto_start', true)

        # Give SketchUp a moment to finish opening its first model before listening.
        UI.start_timer(1.0, false) { self.Na__SketchUpMcp__StartBridge unless Na__SocketServer.Na__SocketServer__Running }
        true
    rescue StandardError => error
        puts "[Na__SketchUpMcp] Registration error: #{error.class}: #{error.message}"
        puts error.backtrace.first(10).join("\n") if error.backtrace
        false
    end

    def self.Na__SketchUpMcp__StartBridge
        status = Na__SocketServer.Na__SocketServer__Start
        Na__DialogManager.Na__DialogManager__RefreshIfVisible
        status
    end

    def self.Na__SketchUpMcp__StopBridge
        status = Na__SocketServer.Na__SocketServer__Stop
        Na__DialogManager.Na__DialogManager__RefreshIfVisible
        status
    end

    def self.Na__SketchUpMcp__ShowStatusDialog
        Na__DialogManager.Na__DialogManager__Show
    end

    def self.Na__SketchUpMcp__ToggleSetting(section_name, key_name)
        current = Na__ConfigLoader.Na__ConfigLoader__Get(section_name, key_name, false) == true
        Na__ConfigLoader.Na__ConfigLoader__SaveUserSetting(section_name, key_name, !current)
        Na__ActivityLog.Na__ActivityLog__Record('setting', 0, true, "#{key_name} = #{!current}")
        Na__DialogManager.Na__DialogManager__RefreshIfVisible
        !current
    end

    def self.Na__SketchUpMcp__ReloadPluginData
        Na__ReloadManager.Na__ReloadManager__ReloadPluginData
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu and Toolbar
# -----------------------------------------------------------------------------

    def self.Na__SketchUpMcp__RegisterMenu
        menu_name = Na__ConfigLoader.Na__ConfigLoader__Get('metadata', 'menu_name', 'Na SketchUp MCP')
        submenu = UI.menu('Extensions').add_submenu(menu_name)

        status_command = na_command('Status Dialog...', 'Bridge status, client setup and the activity log') { self.Na__SketchUpMcp__ShowStatusDialog }
        submenu.add_item(status_command)
        submenu.add_separator

        running_command = na_command('Bridge Running', 'Start or stop the MCP bridge for this SketchUp window') do
            Na__SocketServer.Na__SocketServer__Running ? self.Na__SketchUpMcp__StopBridge : self.Na__SketchUpMcp__StartBridge
        end
        running_command.set_validation_proc { Na__SocketServer.Na__SocketServer__Running ? MF_CHECKED : MF_UNCHECKED }
        submenu.add_item(running_command)

        submenu.add_item(na_toggle_command('Read-Only Mode', 'Refuse every agent request that would change the model', 'safety', 'read_only_mode'))
        submenu.add_item(na_toggle_command('Allow Ruby Eval', 'Let agents run Ruby code with ruby_eval', 'safety', 'allow_ruby_eval'))
        submenu.add_item(na_toggle_command('Start With SketchUp', 'Start the bridge automatically when SketchUp opens', 'bridge', 'auto_start'))
        submenu.add_separator
        submenu.add_item(na_command('Reload Plugin Data', 'Reload the bridge code and JSON without restarting SketchUp') do
            result = self.Na__SketchUpMcp__ReloadPluginData
            puts "[Na__SketchUpMcp] #{result[:message]}"
        end)

        na_register_toolbar(status_command)
    end

    def self.na_command(menu_text, status_text, &block)
        command = UI::Command.new(menu_text, &block)
        command.menu_text = menu_text
        command.tooltip = menu_text
        command.status_bar_text = status_text
        command
    end

    def self.na_toggle_command(menu_text, status_text, section_name, key_name)
        command = na_command(menu_text, status_text) { self.Na__SketchUpMcp__ToggleSetting(section_name, key_name) }
        command.set_validation_proc { Na__ConfigLoader.Na__ConfigLoader__Get(section_name, key_name, false) == true ? MF_CHECKED : MF_UNCHECKED }
        command
    end

    def self.na_register_toolbar(status_command)
        icon_path = Na__PathResolver.Na__PathResolver__NaIconFilePath
        if File.exist?(icon_path)
            status_command.small_icon = icon_path
            status_command.large_icon = icon_path
        end
        toolbar = UI::Toolbar.new('Na SketchUp MCP')
        toolbar.add_item(status_command)
        toolbar.show if toolbar.get_last_state != TB_HIDDEN
    end

# endregion -------------------------------------------------------------------

end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
