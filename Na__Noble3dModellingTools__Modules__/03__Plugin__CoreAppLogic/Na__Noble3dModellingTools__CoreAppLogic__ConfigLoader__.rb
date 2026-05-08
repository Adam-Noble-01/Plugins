# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CORE CONFIG LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__ConfigLoader__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ConfigLoader
# PURPOSE    : Load and normalize JSON-driven UI and command registry
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__ConfigLoader

# -----------------------------------------------------------------------------
# REGION | Default Configuration
# -----------------------------------------------------------------------------

        NA_DEFAULT_CONFIG = {
            'extension_name' => 'Na Noble3d Modelling Tools',
            'dialog_title' => 'Na Noble3d Modelling Tools',
            'dialog_preferences_key' => 'Na__Noble3dModellingTools',
            'dialog_width' => 560,
            'dialog_height' => 620,
            'dialog_resizable' => true,
            'tabs' => [
                {
                    'tab_id' => 'selection_tools',
                    'tab_name' => 'Selection Tools',
                    'tab_order' => 10,
                    'tab_description' => 'Selection-focused scripts for fast modelling workflows.'
                },
                {
                    'tab_id' => 'geometry_tools',
                    'tab_name' => 'Geometry Tools',
                    'tab_order' => 20,
                    'tab_description' => 'Geometry generation tools for rapid concept modelling.'
                },
                {
                    'tab_id' => 'settings',
                    'tab_name' => 'Settings',
                    'tab_order' => 90,
                    'tab_description' => 'Reload plugin data and Ruby modules in the active session.'
                }
            ],
            'commands' => [
                {
                    'command_id' => 'open_main_dialog',
                    'command_name' => 'Na Noble3d Modelling Tools - Open Dialog',
                    'tooltip' => 'Open the Noble3d modelling tools dialog',
                    'status_bar_text' => 'Open Na Noble3d Modelling Tools',
                    'menu_text' => 'Open Noble3d Modelling Tools',
                    'handler_key' => 'open_main_dialog',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'select_quad_face_rings_shortest',
                    'command_name' => 'Na Noble3d - Select Quad Face Rings (Shortest)',
                    'tooltip' => 'Select quad face rings using shortest opposite edges',
                    'status_bar_text' => 'Select quad face rings (shortest direction)',
                    'menu_text' => 'Select Quad Face Rings (Shortest)',
                    'handler_key' => 'select_quad_face_rings_shortest',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'select_quad_face_rings_longest',
                    'command_name' => 'Na Noble3d - Select Quad Face Rings (Longest)',
                    'tooltip' => 'Select quad face rings using longest opposite edges',
                    'status_bar_text' => 'Select quad face rings (longest direction)',
                    'menu_text' => 'Select Quad Face Rings (Longest)',
                    'handler_key' => 'select_quad_face_rings_longest',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'select_quad_face_rings_largest',
                    'command_name' => 'Na Noble3d - Select Quad Face Rings (Largest Count)',
                    'tooltip' => 'Select quad face rings with the largest connected face count',
                    'status_bar_text' => 'Select quad face rings (largest count)',
                    'menu_text' => 'Select Quad Face Rings (Largest Count)',
                    'handler_key' => 'select_quad_face_rings_largest',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'lattice_maker_prompt',
                    'command_name' => 'Na Noble3d - Lattice Maker (Prompt)',
                    'tooltip' => 'Build lattice from selected edges with custom values',
                    'status_bar_text' => 'Run Lattice Maker with prompt',
                    'menu_text' => 'Lattice Maker (Prompt)',
                    'handler_key' => 'lattice_maker_prompt',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'lattice_maker_last',
                    'command_name' => 'Na Noble3d - Lattice Maker (Use Last Values)',
                    'tooltip' => 'Build lattice from selected edges using last saved values',
                    'status_bar_text' => 'Run Lattice Maker with last values',
                    'menu_text' => 'Lattice Maker (Use Last Values)',
                    'handler_key' => 'lattice_maker_last',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'auto_group_utility',
                    'command_name' => 'Na Noble3d - Auto Group Utility',
                    'tooltip' => 'Group disconnected geometry islands from the active selection',
                    'status_bar_text' => 'Auto-group disconnected solid islands',
                    'menu_text' => 'Auto Group Utility',
                    'handler_key' => 'auto_group_utility',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'auto_group_face_islands',
                    'command_name' => 'Na Noble3d - Auto Group Face Islands',
                    'tooltip' => 'Group each individual face in the selection into its own group',
                    'status_bar_text' => 'Auto-group each face into a separate island group',
                    'menu_text' => 'Auto Group Face Islands',
                    'handler_key' => 'auto_group_face_islands',
                    'expose_to_hotkeys' => true
                },
                {
                    'command_id' => 'reload_plugin_data',
                    'command_name' => 'Na Noble3d - Reload Plugin Data',
                    'tooltip' => 'Reload Noble3d Ruby files and rebuild the dialog',
                    'status_bar_text' => 'Reload Noble3d plugin data',
                    'menu_text' => 'Reload Plugin Data',
                    'handler_key' => 'reload_plugin_data',
                    'expose_to_hotkeys' => true
                }
            ],
            'buttons' => [
                {
                    'button_id' => 'btn_select_quad_shortest',
                    'tab_name' => 'Selection Tools',
                    'button_label' => 'Select Quad Face Rings (Shortest)',
                    'command_id' => 'select_quad_face_rings_shortest',
                    'description' => 'Traverses quad-face rings using the shortest opposite-edge pair.'
                },
                {
                    'button_id' => 'btn_select_quad_longest',
                    'tab_name' => 'Selection Tools',
                    'button_label' => 'Select Quad Face Rings (Longest)',
                    'command_id' => 'select_quad_face_rings_longest',
                    'description' => 'Traverses quad-face rings using the longest opposite-edge pair.'
                },
                {
                    'button_id' => 'btn_select_quad_largest',
                    'tab_name' => 'Selection Tools',
                    'button_label' => 'Select Quad Face Rings (Largest Count)',
                    'command_id' => 'select_quad_face_rings_largest',
                    'description' => 'Chooses the candidate ring with the largest resulting face count.'
                },
                {
                    'button_id' => 'btn_lattice_prompt',
                    'tab_name' => 'Geometry Tools',
                    'button_label' => 'Lattice Maker (Prompt)',
                    'command_id' => 'lattice_maker_prompt',
                    'description' => 'Creates a lattice with a width/depth prompt before running.'
                },
                {
                    'button_id' => 'btn_lattice_last',
                    'tab_name' => 'Geometry Tools',
                    'button_label' => 'Lattice Maker (Use Last Values)',
                    'command_id' => 'lattice_maker_last',
                    'description' => 'Creates a lattice immediately using stored values.'
                },
                {
                    'button_id' => 'btn_auto_group_utility',
                    'tab_name' => 'Geometry Tools',
                    'button_label' => 'Auto Group Utility',
                    'command_id' => 'auto_group_utility',
                    'description' => 'Groups each disconnected geometry island in the selection into its own SketchUp group.'
                },
                {
                    'button_id' => 'btn_auto_group_face_islands',
                    'tab_name' => 'Geometry Tools',
                    'button_label' => 'Auto Group Face Islands',
                    'command_id' => 'auto_group_face_islands',
                    'description' => 'Groups each individual face in the selection into a sequentially named SketchUp group.'
                },
                {
                    'button_id' => 'btn_reload',
                    'tab_name' => 'Settings',
                    'button_label' => 'Reload Plugin Data',
                    'command_id' => 'reload_plugin_data',
                    'description' => 'Reloads Ruby files and refreshes the UI without restarting SketchUp.'
                }
            ],
            'settings' => {
                'reload_command_id' => 'reload_plugin_data',
                'status_element_id' => 'naNoble3dStatus'
            },
            'hotkey_bindings' => [
                { 'command_id' => 'open_main_dialog', 'expose_to_hotkeys' => true },
                { 'command_id' => 'select_quad_face_rings_shortest', 'expose_to_hotkeys' => true },
                { 'command_id' => 'select_quad_face_rings_longest', 'expose_to_hotkeys' => true },
                { 'command_id' => 'select_quad_face_rings_largest', 'expose_to_hotkeys' => true },
                { 'command_id' => 'lattice_maker_prompt', 'expose_to_hotkeys' => true },
                { 'command_id' => 'lattice_maker_last', 'expose_to_hotkeys' => true },
                { 'command_id' => 'auto_group_utility', 'expose_to_hotkeys' => true },
                { 'command_id' => 'auto_group_face_islands', 'expose_to_hotkeys' => true },
                { 'command_id' => 'reload_plugin_data', 'expose_to_hotkeys' => true }
            ]
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Config Access
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__ConfigHash
            return @na_cached_config if @na_cached_config

            config_file_path = Na__PathResolver.Na__Noble3dModellingTools__ConfigFilePath
            parsed_config = {}

            if File.exist?(config_file_path)
                parsed_config = JSON.parse(File.read(config_file_path))
            end

            merged_config = na_deep_merge_hashes(NA_DEFAULT_CONFIG, parsed_config)
            normalized_config = na_normalize_config(merged_config)
            normalized_config = na_apply_default_command_fallback_if_needed(normalized_config)
            na_log_config_diagnostics(config_file_path, normalized_config)
            @na_cached_config = normalized_config
            @na_cached_config
        rescue => error
            puts "[Na__Noble3dModellingTools] Config load warning: #{error.class}: #{error.message}"
            @na_cached_config = na_normalize_config(NA_DEFAULT_CONFIG)
            na_log_config_diagnostics(config_file_path, @na_cached_config)
            @na_cached_config
        end

        def self.Na__Noble3dModellingTools__InvalidateConfigCache
            @na_cached_config = nil
        end

        def self.Na__Noble3dModellingTools__ExtensionName
            self.Na__Noble3dModellingTools__ConfigHash.fetch('extension_name', NA_DEFAULT_CONFIG['extension_name'])
        end

        def self.Na__Noble3dModellingTools__DialogTitle
            self.Na__Noble3dModellingTools__ConfigHash.fetch('dialog_title', self.Na__Noble3dModellingTools__ExtensionName)
        end

        def self.Na__Noble3dModellingTools__DialogPreferencesKey
            self.Na__Noble3dModellingTools__ConfigHash.fetch('dialog_preferences_key', 'Na__Noble3dModellingTools')
        end

        def self.Na__Noble3dModellingTools__DialogWidth
            self.Na__Noble3dModellingTools__ConfigHash.fetch('dialog_width', 560).to_i
        end

        def self.Na__Noble3dModellingTools__DialogHeight
            self.Na__Noble3dModellingTools__ConfigHash.fetch('dialog_height', 620).to_i
        end

        def self.Na__Noble3dModellingTools__DialogResizable
            self.Na__Noble3dModellingTools__ConfigHash.fetch('dialog_resizable', true)
        end

        def self.Na__Noble3dModellingTools__Tabs
            self.Na__Noble3dModellingTools__ConfigHash.fetch('tabs', [])
        end

        def self.Na__Noble3dModellingTools__Commands
            self.Na__Noble3dModellingTools__ConfigHash.fetch('commands', [])
        end

        def self.Na__Noble3dModellingTools__Buttons
            self.Na__Noble3dModellingTools__ConfigHash.fetch('buttons', [])
        end

        def self.Na__Noble3dModellingTools__Settings
            self.Na__Noble3dModellingTools__ConfigHash.fetch('settings', {})
        end

        def self.Na__Noble3dModellingTools__CommandById(command_id)
            self.Na__Noble3dModellingTools__Commands.find { |command| command['command_id'] == command_id.to_s }
        end

        def self.Na__Noble3dModellingTools__ButtonsForTabName(tab_name)
            self.Na__Noble3dModellingTools__Buttons.select { |button| button['tab_name'] == tab_name.to_s }
        end

        def self.Na__Noble3dModellingTools__HotkeyVisibleCommands
            self.Na__Noble3dModellingTools__Commands.select { |command| command['expose_to_hotkeys'] }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Normalization Helpers
# -----------------------------------------------------------------------------

        def self.na_normalize_config(config_hash)
            normalized_hash = {}
            normalized_hash['extension_name'] = config_hash['extension_name'].to_s
            normalized_hash['dialog_title'] = config_hash['dialog_title'].to_s
            normalized_hash['dialog_preferences_key'] = config_hash['dialog_preferences_key'].to_s
            normalized_hash['dialog_width'] = config_hash['dialog_width'].to_i
            normalized_hash['dialog_height'] = config_hash['dialog_height'].to_i
            normalized_hash['dialog_resizable'] = !!config_hash['dialog_resizable']
            normalized_hash['tabs'] = na_normalized_tabs(config_hash['tabs'])
            normalized_hash['commands'] = na_normalized_commands(config_hash['commands'])
            normalized_hash['buttons'] = na_normalized_buttons(config_hash['buttons'])
            normalized_hash['settings'] = config_hash['settings'].is_a?(Hash) ? config_hash['settings'] : {}
            normalized_hash['hotkey_bindings'] = na_array_of_hashes(config_hash['hotkey_bindings'])
            normalized_hash
        end

        def self.na_apply_default_command_fallback_if_needed(normalized_config)
            normalized_commands = normalized_config.fetch('commands', [])
            return normalized_config unless normalized_commands.empty?

            fallback_commands = na_normalized_commands(NA_DEFAULT_CONFIG['commands'])
            return normalized_config if fallback_commands.empty?

            puts '[Na__Noble3dModellingTools] Config warning: no valid commands in registry; using default commands.'

            normalized_config_with_fallback = normalized_config.dup
            normalized_config_with_fallback['commands'] = fallback_commands
            normalized_config_with_fallback
        end

        def self.na_log_config_diagnostics(config_file_path, normalized_config)
            commands = normalized_config.fetch('commands', [])
            command_count = commands.length
            hotkey_visible_count = commands.count { |command| command['expose_to_hotkeys'] }

            puts "[Na__Noble3dModellingTools] Config path: #{config_file_path}"
            puts "[Na__Noble3dModellingTools] Command visibility: total=#{command_count}, hotkey_visible=#{hotkey_visible_count}"
        end

        def self.na_normalized_tabs(raw_tabs)
            tabs = na_array_of_hashes(raw_tabs).map do |tab|
                {
                    'tab_id' => tab.fetch('tab_id', '').to_s,
                    'tab_name' => tab.fetch('tab_name', '').to_s,
                    'tab_order' => tab.fetch('tab_order', 0).to_i,
                    'tab_description' => tab.fetch('tab_description', '').to_s
                }
            end

            tabs.reject! { |tab| tab['tab_id'].empty? || tab['tab_name'].empty? }
            tabs.sort_by { |tab| [tab['tab_order'], tab['tab_name']] }
        end

        def self.na_normalized_commands(raw_commands)
            commands = na_array_of_hashes(raw_commands).map do |command|
                {
                    'command_id' => command.fetch('command_id', '').to_s,
                    'command_name' => command.fetch('command_name', '').to_s,
                    'tooltip' => command.fetch('tooltip', '').to_s,
                    'status_bar_text' => command.fetch('status_bar_text', '').to_s,
                    'menu_text' => command.fetch('menu_text', '').to_s,
                    'handler_key' => command.fetch('handler_key', '').to_s,
                    'expose_to_hotkeys' => !!command.fetch('expose_to_hotkeys', false)
                }
            end

            commands.reject! do |command|
                command['command_id'].empty? || command['command_name'].empty? || command['handler_key'].empty?
            end

            commands
        end

        def self.na_normalized_buttons(raw_buttons)
            buttons = na_array_of_hashes(raw_buttons).map do |button|
                {
                    'button_id' => button.fetch('button_id', '').to_s,
                    'tab_name' => button.fetch('tab_name', '').to_s,
                    'button_label' => button.fetch('button_label', '').to_s,
                    'command_id' => button.fetch('command_id', '').to_s,
                    'description' => button.fetch('description', '').to_s
                }
            end

            buttons.reject! do |button|
                button['button_id'].empty? || button['tab_name'].empty? || button['button_label'].empty? || button['command_id'].empty?
            end

            buttons
        end

        def self.na_array_of_hashes(value)
            return [] unless value.is_a?(Array)

            value.select { |entry| entry.is_a?(Hash) }
        end

        def self.na_deep_merge_hashes(base_hash, override_hash)
            return base_hash unless override_hash.is_a?(Hash)

            merged_hash = base_hash.dup
            override_hash.each do |key, override_value|
                base_value = merged_hash[key]

                merged_hash[key] = if base_value.is_a?(Hash) && override_value.is_a?(Hash)
                    na_deep_merge_hashes(base_value, override_value)
                else
                    override_value
                end
            end

            merged_hash
        end

# endregion -------------------------------------------------------------------

    end # module Na__ConfigLoader
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
