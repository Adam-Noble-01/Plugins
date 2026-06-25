# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC TOOLBAR ICON LOADER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__CoreAppLogic__ToolbarIconLoader__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__ToolbarIconLoader
# PURPOSE    : Create the SketchUp toolbar button using the Vale icon
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Creates a single-button toolbar that opens the sync dialog.
# - Uses Vale_Icon16px.png / Vale_Icon32px.png from 06__Assets.
# - Respects user-saved toolbar visibility state via UI::Toolbar#restore.
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__ToolbarIconLoader

# -----------------------------------------------------------------------------
# REGION | Toolbar Creation
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__CreateToolbar
            return if @na_toolbar

            icon_small = Na__PathResolver.Na__ValeVisionCloudSync__Icon16FilePath
            icon_large = Na__PathResolver.Na__ValeVisionCloudSync__Icon32FilePath

            # <-- Fall back to small icon if large is missing
            icon_large = icon_small unless File.exist?(icon_large)

            command = UI::Command.new('ValeVision Cloud Sync') do
                Na__ValeVisionCloudSync.Na__ValeVisionCloudSync__ShowMainDialog
            end

            command.tooltip         = 'Open ValeVision Cloud Sync'
            command.status_bar_text = 'Open ValeVision Cloud Sync'
            command.small_icon      = icon_small
            command.large_icon      = icon_large

            @na_toolbar = UI::Toolbar.new('ValeVision Cloud Sync')
            @na_toolbar.add_item(command)
            @na_toolbar.restore
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToolbarIconLoader
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
