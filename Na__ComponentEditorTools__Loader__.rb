# =============================================================================
# NA COMPONENT EDITOR TOOLS - ROOT LOADER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__Loader__.rb
# NAMESPACE  : Na__ComponentEditorTools (root bootstrap)
# PURPOSE    : Bootstrap Na__ComponentEditorTools from SketchUp Plugins root
# CREATED    : 2026
#
# DESCRIPTION:
# - Keeps the root loader thin and focused on SketchUp registration only.
# - Requires the modular AppCore main file from Na__ComponentEditorTools__Modules__.
# - Registers one command in Extensions > Noble Architecture plus a toolbar button.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

# -----------------------------------------------------------------------------
# REGION | Path Setup
# -----------------------------------------------------------------------------

    plugin_root      = File.dirname(__FILE__)
    modules_root     = File.join(plugin_root, 'Na__ComponentEditorTools__Modules__')
    appcore_main     = File.join(
        modules_root,
        '02__Src__AppModules',
        '01__AppCore',
        'Na__ComponentEditorTools__AppCore__Main__.rb'
    )
    fallback_icon    = File.join(plugin_root, 'Na__Common__PluginDependencies', 'IMG02__ICN__NaCompanyIcon.png')
    plugin_name      = 'Na Component Editor Tools'
    command_text     = 'Na__ComponentEditorTools'
    toolbar_name     = 'NA Component Tools'

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | AppCore Require
# -----------------------------------------------------------------------------

    if File.exist?(appcore_main)
        begin
            require appcore_main
        rescue => error
            puts "[Na__ComponentEditorTools] Loader require error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
        end
    else
        puts "[Na__ComponentEditorTools] AppCore main not found: #{appcore_main}"
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Command Registration
# -----------------------------------------------------------------------------

    command = UI::Command.new(plugin_name) do
        if defined?(Na__ComponentEditorTools) &&
           Na__ComponentEditorTools.respond_to?(:Na__ComponentEditorTools__OpenDialog)
            Na__ComponentEditorTools.Na__ComponentEditorTools__OpenDialog
        else
            UI.messagebox('Na__ComponentEditorTools is not loaded.')
        end
    end

    command.menu_text       = command_text
    command.tooltip         = plugin_name
    command.status_bar_text = 'Open Na Component Editor Tools'

    begin
        resolved_icon_path = nil

        if defined?(Na__ComponentEditorTools::Na__PathResolver) &&
           Na__ComponentEditorTools::Na__PathResolver.respond_to?(:Na__ComponentEditorTools__ToolbarIconPath)
            icon_candidate = Na__ComponentEditorTools::Na__PathResolver.Na__ComponentEditorTools__ToolbarIconPath
            resolved_icon_path = icon_candidate if icon_candidate && File.exist?(icon_candidate)
        end

        if !resolved_icon_path && File.exist?(fallback_icon)
            resolved_icon_path = fallback_icon
        end

        if resolved_icon_path
            command.small_icon = resolved_icon_path
            command.large_icon = resolved_icon_path
        end
    rescue => error
        puts "[Na__ComponentEditorTools] Icon resolution warning: #{error.class}: #{error.message}"
    end

    extensions_menu = UI.menu('Extensions')
    na_submenu = extensions_menu.add_submenu('Noble Architecture')
    na_submenu.add_item(command)

    toolbar = UI::Toolbar.new(toolbar_name)
    toolbar.add_item(command)
    toolbar.restore if toolbar.respond_to?(:restore)
    toolbar.show unless toolbar.get_last_state == TB_HIDDEN

# endregion -------------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF FILE
# =============================================================================
