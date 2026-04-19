# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - HOTKEY BINDER
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__HotkeyBinder

# -----------------------------------------------------------------------------
# REGION | Hotkey Registration
# -----------------------------------------------------------------------------

        # FUNCTION | Register Hotkey Through Command
        # ------------------------------------------------------------
        def self.Na__Hotkey__Register
            menu_command = Na__MenuAndCommand.Na__Ui__GetRegisteredCommand
            return unless menu_command

            shortcut = 'Ctrl+Shift+O'

            begin
                menu_command.set_validation_proc { MF_ENABLED }
                menu_command.accelerator = shortcut if menu_command.respond_to?(:accelerator=)
            rescue
                # SketchUp versions may not expose accelerator assignment consistently.
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
