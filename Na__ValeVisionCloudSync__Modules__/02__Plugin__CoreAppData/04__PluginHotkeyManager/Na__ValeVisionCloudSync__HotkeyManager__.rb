# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC HOTKEY MANAGER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__HotkeyManager__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__HotkeyManager
# PURPOSE    : Register UI::Command items for the Extensions menu and hotkeys
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Reads the expose_to_hotkeys commands from the registry and registers
#   UI::Command wrappers for each so SketchUp can assign keyboard shortcuts.
# - The primary registered command is 'open_main_dialog'; sync actions use
#   the dialog UI and are not exposed as standalone hotkeys.
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__HotkeyManager

# -----------------------------------------------------------------------------
# REGION | Registration
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__RegisterHotkeysAndMenu
            return if @na_commands_registered

            extensions_menu = UI.menu('Extensions')
            plugin_submenu  = extensions_menu.add_submenu('ValeVision Cloud Sync')

            command_entries = Na__ConfigLoader.Na__ValeVisionCloudSync__HotkeyVisibleCommands

            command_entries.each do |command_entry|
                ui_command, skip_reason = na_build_ui_command(command_entry)
                command_id = command_entry.fetch('command_id', '<missing>')

                if ui_command
                    plugin_submenu.add_item(ui_command)
                    puts "[Na__ValeVisionCloudSync] Registered command: #{command_id}"
                else
                    puts "[Na__ValeVisionCloudSync] Skipped command: #{command_id} (#{skip_reason})"
                end
            end

            @na_commands_registered = true
            true
        rescue => error
            puts "[Na__ValeVisionCloudSync] HotkeyManager error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
            false
        end

        def self.Na__ValeVisionCloudSync__ResetRegistrationState
            @na_commands_registered = false
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        def self.na_build_ui_command(command_entry)
            command_id   = command_entry.fetch('command_id', '').to_s
            return [nil, 'missing command_id'] if command_id.empty?

            command_name = command_entry.fetch('command_name', '').to_s
            return [nil, 'missing command_name'] if command_name.empty?

            handler_key  = command_entry.fetch('handler_key', '').to_s
            return [nil, 'missing handler_key'] if handler_key.empty?

            ui_command = UI::Command.new(command_name) do
                Na__ValeVisionCloudSync.Na__ValeVisionCloudSync__RunCommandById(command_id)
            end

            ui_command.tooltip         = command_entry.fetch('tooltip', command_name)
            ui_command.status_bar_text = command_entry.fetch('status_bar_text', command_name)
            ui_command.menu_text       = command_entry.fetch('menu_text', command_name)
            [ui_command, nil]
        rescue => error
            [nil, "#{error.class}: #{error.message}"]
        end

# endregion -------------------------------------------------------------------

    end # module Na__HotkeyManager
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
