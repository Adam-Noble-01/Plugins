# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TOOLBAR ICON LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__ToolbarIconLoader__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToolbarIconLoader
# PURPOSE    : Create the SketchUp toolbar: the NA company icon that opens the
#              main dialog, then one button per `toolbar_items` entry in the
#              registry (the Agent Outliner first). Respects the user-saved
#              toolbar visibility state via UI::Toolbar#restore.
#
# CONFIG-FIRST DESIGN NOTE:
# The first button only opens the config-driven dialog. Every further button
# comes from `toolbar_items` in the JSON registry: it names a registry command
# and an icon, and runs through RunCommandById like the dialog, the menus and
# the hotkeys, so its launches are counted (source 'toolbar'). Individual tools
# are never hardcoded here.
#
# RELOAD NOTE:
# SketchUp keeps a toolbar's buttons until it restarts, and a button cannot be
# taken off at run time. The toolbar and the ids of the buttons on it live in
# module variables, which survive a `load`-based reload, so Reload Plugin Data
# appends a new registry item and never adds one twice. A removed item stays
# until SketchUp restarts.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 10-Nov-2026 - Version 0.9.27
# - Registry `toolbar_items` after the main button. The first is the Agent
#   Outliner, with its own SVG icon. Reload Plugin Data appends new items.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToolbarIconLoader

# -----------------------------------------------------------------------------
# REGION | Toolbar Creation
# -----------------------------------------------------------------------------

        # FUNCTION | Create The 3D Modelling Tools Toolbar
        # ---------------------------------------------------------------
        # Runs once per session. A second call only appends the registry items
        # the toolbar does not hold yet.
        # ---------------------------------------------------------------
        def self.Na__Noble3dModellingTools__CreateToolbar
            return self.Na__Noble3dModellingTools__SyncToolbarItems if @na_toolbar

            icon_path = Na__PathResolver.Na__Noble3dModellingTools__NaIconFilePath

            command = UI::Command.new('3D Modelling Tools') do
                Na__Noble3dModellingTools.Na__Noble3dModellingTools__ShowMainDialog
            end

            command.tooltip         = 'Open 3D Modelling Tools'
            command.status_bar_text = 'Open Noble 3D Modelling Tools'
            command.small_icon      = icon_path
            command.large_icon      = icon_path

            @na_toolbar = UI::Toolbar.new('3D Modelling Tools')
            @na_toolbar.add_item(command)
            na_add_registry_items                                       # <-- The registry's buttons follow the main one
            @na_toolbar.restore
        end
        # ---------------------------------------------------------------

        # FUNCTION | Append The Registry Toolbar Items Not Yet On The Toolbar
        # ---------------------------------------------------------------
        # Returns how many buttons were added. The ReloadManager calls it after
        # Reload Plugin Data, so a new registry item shows without a restart.
        # ---------------------------------------------------------------
        def self.Na__Noble3dModellingTools__SyncToolbarItems
            return 0 unless @na_toolbar

            added_count = na_add_registry_items
            na_refresh_toolbars if added_count > 0
            added_count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Registry Toolbar Items
# -----------------------------------------------------------------------------

        # One bad entry is reported and skipped; the others still get their buttons.
        def self.na_add_registry_items
            @na_toolbar_item_ids ||= {}
            added_count = 0

            Na__ConfigLoader.Na__Noble3dModellingTools__ToolbarItems.each do |item|
                next if @na_toolbar_item_ids[item['toolbar_item_id']]

                begin
                    command = na_toolbar_item_command(item)
                    next unless command

                    @na_toolbar.add_item(command)
                    @na_toolbar_item_ids[item['toolbar_item_id']] = true
                    added_count += 1
                rescue => error
                    puts "[Na__Noble3dModellingTools] Toolbar item #{item['toolbar_item_id']} skipped: #{error.class}: #{error.message}"
                end
            end

            added_count
        end

        # The block names its command id and finds the module by name when clicked,
        # so a button made before a reload runs the reloaded code.
        def self.na_toolbar_item_command(item)
            command_entry = Na__ConfigLoader.Na__Noble3dModellingTools__CommandById(item['command_id'])

            unless command_entry
                puts "[Na__Noble3dModellingTools] Toolbar item #{item['toolbar_item_id']} skipped: no command '#{item['command_id']}' in the registry."
                return nil
            end

            command_id  = command_entry['command_id']
            menu_text   = command_entry['menu_text'].empty? ? command_entry['command_name'] : command_entry['menu_text']
            tooltip     = item['tooltip'].empty? ? menu_text : item['tooltip']
            status_text = command_entry['status_bar_text'].empty? ? tooltip : command_entry['status_bar_text']
            icon_path   = na_toolbar_icon_path(item)

            command = UI::Command.new(menu_text) do
                Na__Noble3dModellingTools.Na__Noble3dModellingTools__RunCommandById(command_id, 'toolbar')
            end

            command.tooltip         = tooltip
            command.status_bar_text = status_text
            command.small_icon      = icon_path                         # <-- One SVG serves both sizes
            command.large_icon      = icon_path
            command
        end

        # icon_file is relative to the Modules folder. SVG works on Windows, and on
        # the Mac from 2027 (PDF before that). A missing or unusable icon falls back
        # to the NA company icon, so a button is never blank.
        def self.na_toolbar_icon_path(item)
            fallback_path = Na__PathResolver.Na__Noble3dModellingTools__NaIconFilePath
            return fallback_path if item['icon_file'].empty?

            icon_path = File.join(Na__PathResolver.Na__Noble3dModellingTools__ModulesRoot, item['icon_file'])

            unless File.exist?(icon_path)
                puts "[Na__Noble3dModellingTools] Toolbar icon not found, using the NA icon: #{icon_path}"
                return fallback_path
            end

            svg_unsupported = File.extname(icon_path).casecmp?('.svg') &&
                Sketchup.platform == :platform_osx && Sketchup.version.to_i < 27
            svg_unsupported ? fallback_path : icon_path
        end

        # SketchUp 2027 refreshes its toolbars itself and deprecates refresh_toolbars.
        def self.na_refresh_toolbars
            UI.refresh_toolbars if Sketchup.version.to_i < 27 && UI.respond_to?(:refresh_toolbars)
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToolbarIconLoader
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
