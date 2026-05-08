# =============================================================================
# NA NOBLE3D MODELLING TOOLS - HOTKEY MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__HotkeyManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__HotkeyManager
# PURPOSE    : Register UI::Command items for menu and native hotkey binding
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__HotkeyManager

# -----------------------------------------------------------------------------
# REGION | Registration
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__RegisterHotkeysAndMenu
            return if @na_commands_registered

            extensions_menu = UI.menu('Extensions')
            plugin_submenu = extensions_menu.add_submenu('Na__Noble3dModellingTools')
            command_entries = na_hotkey_command_entries_for_registration

            if command_entries.empty?
                puts '[Na__Noble3dModellingTools] Hotkey registration warning: no command entries resolved.'
            end

            command_entries.each do |command_entry|
                command, skip_reason = na_build_ui_command(command_entry)
                command_id = command_entry.fetch('command_id', '<missing_command_id>')

                if command
                    plugin_submenu.add_item(command)
                    puts "[Na__Noble3dModellingTools] Registered command: #{command_id}"
                else
                    puts "[Na__Noble3dModellingTools] Skipped command: #{command_id} (#{skip_reason})"
                end
            end

            @na_commands_registered = true
            true
        rescue => error
            puts "[Na__Noble3dModellingTools] Hotkey manager error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
            false
        end

        def self.Na__Noble3dModellingTools__ResetRegistrationState
            @na_commands_registered = false
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        def self.na_hotkey_command_entries_for_registration
            command_entries = Na__ConfigLoader.Na__Noble3dModellingTools__HotkeyVisibleCommands.map(&:dup)
            open_main_dialog_entry = na_resolved_open_main_dialog_command_entry(command_entries)
            non_dialog_entries = command_entries.reject { |command_entry| command_entry.fetch('command_id', '') == 'open_main_dialog' }

            na_unique_command_entries_by_command_id([open_main_dialog_entry] + non_dialog_entries)
        end

        def self.na_resolved_open_main_dialog_command_entry(command_entries)
            config_entry = command_entries.find { |command_entry| command_entry.fetch('command_id', '') == 'open_main_dialog' }
            return config_entry if na_command_entry_valid_for_registration(config_entry)

            puts '[Na__Noble3dModellingTools] Hotkey registration warning: open_main_dialog missing; using fallback command entry.'
            na_fallback_open_main_dialog_command_entry
        end

        def self.na_fallback_open_main_dialog_command_entry
            {
                'command_id' => 'open_main_dialog',
                'command_name' => 'Na Noble3d Modelling Tools - Open Dialog',
                'tooltip' => 'Open the Na Noble3d Modelling Tools dialog',
                'status_bar_text' => 'Open Na Noble3d Modelling Tools',
                'menu_text' => 'Open Noble3d Modelling Tools',
                'handler_key' => 'open_main_dialog',
                'expose_to_hotkeys' => true
            }
        end

        def self.na_unique_command_entries_by_command_id(command_entries)
            seen_command_ids = {}

            command_entries.each_with_object([]) do |command_entry, unique_entries|
                next unless command_entry.is_a?(Hash)

                command_id = command_entry.fetch('command_id', '').to_s
                next if command_id.empty?
                next if seen_command_ids[command_id]

                seen_command_ids[command_id] = true
                unique_entries << command_entry
            end
        end

        def self.na_command_entry_valid_for_registration(command_entry)
            return false unless command_entry.is_a?(Hash)

            command_id = command_entry.fetch('command_id', '').to_s
            command_name = command_entry.fetch('command_name', '').to_s
            handler_key = command_entry.fetch('handler_key', '').to_s

            !(command_id.empty? || command_name.empty? || handler_key.empty?)
        end

        def self.na_build_ui_command(command_entry)
            command_id = command_entry.fetch('command_id', '').to_s
            return [nil, 'missing command_id'] if command_id.empty?

            command_name = command_entry.fetch('command_name', '').to_s
            return [nil, 'missing command_name'] if command_name.empty?

            handler_key = command_entry.fetch('handler_key', '').to_s
            return [nil, 'missing handler_key'] if handler_key.empty?

            command = UI::Command.new(command_name) do
                na_run_command_with_module_load(command_id)
            end

            command.tooltip = command_entry.fetch('tooltip', command_name)
            command.status_bar_text = command_entry.fetch('status_bar_text', command_name)
            command.menu_text = command_entry.fetch('menu_text', command_name)
            [command, nil]
        rescue => error
            [nil, "#{error.class}: #{error.message}"]
        end

        def self.na_run_command_with_module_load(command_id)
            if Na__Noble3dModellingTools.respond_to?(:Na__Noble3dModellingTools__RunCommandById)
                Na__Noble3dModellingTools.Na__Noble3dModellingTools__RunCommandById(command_id)
            else
                Na__CommandRouter.Na__Noble3dModellingTools__RunCommand(command_id)
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__HotkeyManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
