# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - MENU AND COMMAND
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__MenuAndCommand

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_command_registered = false
        @na_run_command = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Command Registration
# -----------------------------------------------------------------------------

        # FUNCTION | Register Command and Menu Item
        # ------------------------------------------------------------
        def self.Na__Ui__RegisterCommand
            return if @na_command_registered

            @na_run_command = UI::Command.new('Na__ToScaleOrthoTextureMaker') do
                begin
                    Na__ToScaleOrthoTextureMaker.Na__Ui__ShowMainDialog
                rescue => error
                    UI.messagebox("Na__ToScaleOrthoTextureMaker command error:\n#{error.message}")
                end
            end

            @na_run_command.tooltip = 'Open Ortho Texture Maker dialog'
            @na_run_command.status_bar_text = 'Set up an ortho view or scene, then capture the viewport as a flat textured plane'
            @na_run_command.menu_text = 'Na__ToScaleOrthoTextureMaker'

            UI.menu('Extensions').add_item(@na_run_command)

            @na_command_registered = true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get Registered Command
        # ------------------------------------------------------------
        def self.Na__Ui__GetRegisteredCommand
            @na_run_command
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
