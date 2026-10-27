# =============================================================================
# NA POINT CLOUD VIEWER - HOTKEYS - MANAGER
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Hotkeys__Manager__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__HotkeyManager
# PURPOSE    : Puts every shortcut command into Extensions > Na__PointCloudViewer
#              so SketchUp can give each one a key, reads back which keys they
#              have for the Settings tab, and opens SketchUp's Shortcuts page
#              (v0.13.0).
#
# WHY A MENU: SketchUp gives keys only to menu items (Window > Preferences >
#   Shortcuts) and keeps each key by the item's MENU PATH, for example
#   "Extensions/Na__PointCloudViewer/Draw Clip Box". So the submenu's name and
#   each command's menuText (config: hotkeys) must never change: a renamed
#   item loses the key someone gave it. The commands work with the viewer's
#   window closed.
#
# CONFIG FIRST: which commands there are, their order, menu text and summary
#   live in the defaults JSON (hotkeys.commands), as in Noble 3D Tools' command
#   registry; Na__HotkeyCommands holds what each one does.
#
# HOT RELOAD: a menu built once at start up never shows a command added later,
#   so it cannot be given a key until SketchUp restarts (Insert Primitives found
#   the same). Here each command is added once per SketchUp session and
#   remembered (`unless defined?`), so Reload Plugin adds exactly the commands
#   that are new, and never a second copy (SketchUp cannot take a menu item
#   back). Every item runs Na__Hotkeys__Run(id), looked up again on each press,
#   so the reloaded code is what runs.
#
# COLD START: adding menu items is safe while SketchUp loads extensions (no
#   model is touched). The menu checkmarks read the model only once
#   Na__ModelRegistry says loading is over.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__HotkeyManager

    # -------------------------------------------------------------------------
    # REGION | State (survives Reload Plugin)
    # -------------------------------------------------------------------------

        NA_DEFAULT_SUBMENU = 'Na__PointCloudViewer'.freeze

        @na_menu    = nil unless defined?(@na_menu)       # the Extensions submenu, made once per SketchUp session
        @na_entries = {}  unless defined?(@na_entries)    # command id => the UI::Command in it

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Commands (config)
    # -------------------------------------------------------------------------

        def self.Na__Hotkeys__Submenu
            name = Na__ConfigLoader.Na__Config__GetOr(NA_DEFAULT_SUBMENU, 'hotkeys', 'submenu').to_s.strip
            name.empty? ? NA_DEFAULT_SUBMENU : name
        end

        # Every usable entry of hotkeys.commands, in menu order: an id that
        # Na__HotkeyCommands knows and a menu text. Others are left out with a
        # log line.
        def self.Na__Hotkeys__Commands
            seen = {}
            Array(Na__ConfigLoader.Na__Config__GetOr([], 'hotkeys', 'commands')).each_with_object([]) do |entry, list|
                next unless entry.is_a?(Hash)
                id = entry['id'].to_s
                text = entry['menuText'].to_s.strip
                if id.empty? || text.empty? || seen[id]
                    Na__DebugTools.Na__Debug__Warn("A shortcut command in the config was left out (id '#{id}', menu text '#{text}').")
                    next
                end
                unless Na__HotkeyCommands.Na__Commands__Known?(id)
                    Na__DebugTools.Na__Debug__Warn("The shortcut command '#{id}' has no handler and was left out.")
                    next
                end
                seen[id] = true
                list << entry.merge('menuText' => text)
            end
        end

        # "Extensions/Na__PointCloudViewer/Draw Clip Box": how SketchUp names it.
        def self.Na__Hotkeys__MenuPath(entry)
            "Extensions/#{self.Na__Hotkeys__Submenu}/#{entry['menuText']}"
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Registration (each command once per SketchUp session)
    # -------------------------------------------------------------------------

        # Adds the commands not in the menu yet. Returns how many were added.
        # (Outside SketchUp, with no menus to add to, it adds none.)
        def self.Na__Hotkeys__Register
            added = 0
            return added unless UI.respond_to?(:menu) && defined?(UI::Command)
            self.Na__Hotkeys__Commands.each do |entry|
                next if @na_entries[entry['id']]
                command = self.na_build_command(entry)
                menu = self.na_menu
                menu.add_separator if entry['separatorBefore'] && !@na_entries.empty?
                menu.add_item(command)
                @na_entries[entry['id']] = command
                added += 1
            end
            added
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The shortcut commands could not be added to the Extensions menu.', error)
            added
        end

        def self.Na__Hotkeys__Registered?(id)
            @na_entries.key?(id.to_s)
        end

        def self.na_menu
            @na_menu ||= UI.menu('Extensions').add_submenu(self.Na__Hotkeys__Submenu)
        end

        def self.na_build_command(entry)
            id = entry['id']
            command = UI::Command.new("Na Point Cloud Viewer: #{entry['menuText']}") do
                Na__PointCloudViewer::Na__HotkeyManager.Na__Hotkeys__Run(id)
            end
            command.menu_text       = entry['menuText']
            command.tooltip         = entry['menuText']
            command.status_bar_text = entry['summary'].to_s
            command.set_validation_proc { Na__PointCloudViewer::Na__HotkeyManager.na_menu_state(id) }
            command
        end

        # A checkmark beside the switches that are on (never greyed out: a
        # greyed command does nothing when its key is pressed, and a key that
        # does nothing says nothing).
        def self.na_menu_state(id)
            return MF_ENABLED unless Na__HotkeyCommands.Na__Commands__Toggle?(id)
            return MF_UNCHECKED unless Na__ModelRegistry.Na__Registry__Ready?
            Na__HotkeyCommands.Na__Commands__Checked?(id) ? MF_CHECKED : MF_UNCHECKED
        rescue StandardError
            MF_ENABLED
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Run
    # -------------------------------------------------------------------------

        # What every menu item and key runs. The status line (and the window,
        # when open) says what happened.
        def self.Na__Hotkeys__Run(id)
            message, level = Na__HotkeyCommands.Na__Commands__Run(id)
            self.na_tell(message, level || 'info')
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("The shortcut '#{id}' failed.", error)
            self.na_tell("Sorry, that did not work (#{error.message}). Details are in Settings > Technical Log.", 'error')
        end

        def self.na_tell(message, level)
            Sketchup.status_text = message if message
            return unless Na__DialogManager.Na__Dialog__Visible?
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(message, level) if message
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Keys SketchUp Has Given Them (Settings tab)
    # -------------------------------------------------------------------------

        # For the Settings tab: every command, its key(s) now, and any key it
        # shares with another command.
        def self.Na__Hotkeys__Payload
            keys_by_path, paths_by_key = self.na_shortcut_tables
            commands = self.Na__Hotkeys__Commands.map do |entry|
                path = self.Na__Hotkeys__MenuPath(entry)
                keys = keys_by_path[path] || []
                clashes = keys.flat_map do |key|
                    (paths_by_key[key] || []).reject { |other| other == path }.map { |other| { 'key' => key, 'with' => self.na_readable(other) } }
                end
                {
                    'id'              => entry['id'],
                    'menuText'        => entry['menuText'],
                    'summary'         => entry['summary'].to_s,
                    'separatorBefore' => entry['separatorBefore'] ? true : false,
                    'path'            => self.na_readable(path),
                    'keys'            => keys,
                    'clashes'         => clashes,
                    'inMenu'          => self.Na__Hotkeys__Registered?(entry['id'])
                }
            end
            {
                'isAvailable'        => true,
                'submenu'            => self.Na__Hotkeys__Submenu,
                'canOpenPreferences' => UI.respond_to?(:show_preferences),
                'commands'           => commands,
                'keysById'           => commands.each_with_object({}) { |command, keys| keys[command['id']] = command['keys'].first if command['keys'].first }
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The keyboard shortcuts could not be listed.', error)
            { 'isAvailable' => false, 'commands' => [], 'keysById' => {}, 'problem' => "The keyboard shortcuts could not be listed (#{error.message})." }
        end

        # Sketchup.get_shortcuts: ["Ctrl+Alt+B\tExtensions/Na__PointCloudViewer/Draw Clip Box", ...]
        # -> [{ path => [keys] }, { key => [paths] }]. A path SketchUp still
        # calls Plugins/... is read as Extensions/...
        def self.na_shortcut_tables
            keys_by_path = {}
            paths_by_key = {}
            list = Sketchup.respond_to?(:get_shortcuts) ? Array(Sketchup.get_shortcuts) : []
            list.each do |line|
                key, path = line.to_s.split("\t", 2)
                key = key.to_s.strip
                path = path.to_s.strip.sub(%r{\APlugins/}, 'Extensions/')
                next if key.empty? || path.empty?
                (keys_by_path[path] ||= []) << key unless (keys_by_path[path] || []).include?(key)
                (paths_by_key[key] ||= []) << path unless (paths_by_key[key] || []).include?(path)
            end
            [keys_by_path, paths_by_key]
        end

        # "Extensions > Na__PointCloudViewer > Draw Clip Box"
        def self.na_readable(path)
            path.to_s.split('/').join(' > ')
        end

        # Opens SketchUp's Shortcuts page (modal; the keys are read again when
        # it closes). Returns nil, or what to do instead.
        def self.Na__Hotkeys__OpenPreferences
            fallback = "Open Window > Preferences > Shortcuts in SketchUp, then type #{self.Na__Hotkeys__Submenu} in Filter."
            return fallback unless UI.respond_to?(:show_preferences)
            page = 'Shortcuts'
            if UI.respond_to?(:preferences_pages)
                named = Array(UI.preferences_pages).map(&:to_s).find { |name| name =~ /shortcut/i }
                page = named if named
            end
            UI.show_preferences(page)
            nil
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("SketchUp's Shortcuts page could not be opened: #{error.message}")
            fallback
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
