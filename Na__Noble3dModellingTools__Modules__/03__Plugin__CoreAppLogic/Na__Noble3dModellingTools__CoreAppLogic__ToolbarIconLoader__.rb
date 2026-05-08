# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TOOLBAR ICON LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__ToolbarIconLoader__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToolbarIconLoader
# PURPOSE    : Create the SketchUp toolbar button using the NA company icon
#              from Na__Common__PluginDependencies. Respects the user-saved
#              toolbar visibility state via UI::Toolbar#restore.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToolbarIconLoader

# -----------------------------------------------------------------------------
# REGION | Toolbar Creation
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__CreateToolbar
            return if @na_toolbar

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
            @na_toolbar.restore
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToolbarIconLoader
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
