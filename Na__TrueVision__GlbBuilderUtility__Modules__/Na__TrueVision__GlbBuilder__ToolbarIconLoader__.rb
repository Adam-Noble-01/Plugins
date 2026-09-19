# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - TOOLBAR ICON LOADER
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__ToolbarIconLoader__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Create the SketchUp toolbar button using the Noble Architecture
#              square brand icon
# CREATED    : 19-Sep-2026
#
# DESCRIPTION:
# - Creates a single-button toolbar that opens the GLB Builder dialog.
# - Uses the Noble Architecture square logo from 06__Assets.
# - Respects the user-saved toolbar visibility state via UI::Toolbar#restore.
# - Safe to call repeatedly: a hot reload will not stack duplicate toolbars.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Sep-2026 - Version 2.8.0
# - Initial toolbar, added alongside the ValeVision-style UI rebuild.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Toolbar Creation
    # -----------------------------------------------------------------------------

        # FUNCTION | Create The TrueVision GLB Builder Toolbar
        # ---------------------------------------------------------------
        # The module instance variable survives a `load`-based hot reload, so the
        # guard keeps SketchUp from registering the same toolbar twice per session.
        # ---------------------------------------------------------------
        def self.Na__ToolbarIconLoader__CreateToolbar
            return @na_toolbar if @na_toolbar

            icon_small = self.Na__PathResolver__ToolbarIconSmallFilePath
            icon_large = self.Na__PathResolver__ToolbarIconLargeFilePath

            icon_small = icon_large unless File.exist?(icon_small)      # <-- Large stands in for a missing small
            icon_large = icon_small unless File.exist?(icon_large)      # <-- and vice versa

            command = UI::Command.new('TrueVision GLB Builder') do
                TrueVision3D::GlbBuilderUtility.Na__PublicApi__StartExport
            end

            command.tooltip         = 'Open TrueVision GLB Builder'
            command.status_bar_text = 'Open the TrueVision3D GLB Builder Utility export dialog'

            if File.exist?(icon_small)
                command.small_icon = icon_small
                command.large_icon = icon_large
                puts "[+] TrueVision GLB Builder toolbar icon loaded: #{File.basename(icon_large)}"
            else
                puts "[!] TrueVision GLB Builder toolbar icon not found at: #{icon_large}"
                puts '    Tool will work but the toolbar button will have a default icon'
            end

            @na_toolbar = UI::Toolbar.new('TrueVision GLB Builder')
            @na_toolbar.add_item(command)
            @na_toolbar.restore                                        # <-- Honour the user's saved show/hide state
            @na_toolbar
        rescue => error
            puts "[x] Error creating TrueVision GLB Builder toolbar: #{error.message}"
            puts error.backtrace.first(5).join("\n")
            nil
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
