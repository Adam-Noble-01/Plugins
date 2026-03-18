# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - KEYBOARD HANDLERS
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__KeyboardHandlers__.rb
# PURPOSE    : Keyboard behavior mixin for preview placement tool
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__KeyboardHandlers

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_ROTATION_KEY   = 9 # Tab key
        NA_ROTATION_STEPS = [0, 90, 180, 270].freeze
        NA_STATUS_PROMPT_KEY = SB_PROMPT

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Keyboard Handlers
    # -------------------------------------------------------------------------

        def onKeyDown(key, _repeat, _flags, view)
            if key == NA_ROTATION_KEY && !@na_key_tab_held
                @na_key_tab_held  = true
                @na_rotation_step = (@na_rotation_step.to_i + 1) % NA_ROTATION_STEPS.length
                self.Na__Keyboard__UpdateStatusText
                view.invalidate
            end
            false
        end

        def onKeyUp(key, _repeat, _flags, _view)
            @na_key_tab_held = false if key == NA_ROTATION_KEY
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | VCB (Value Control Box) Support
    # -------------------------------------------------------------------------

        def enableVCB?
            true
        end

        def onUserText(text, view)
            return if text.to_s.strip.empty?
            parsed = text.to_f
            return if parsed.zero?
            @na_crosshair_size = parsed.mm
            self.Na__Keyboard__UpdateStatusText
            view.invalidate
        rescue
            UI.beep
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Rotation State Helpers
    # -------------------------------------------------------------------------

        def Na__Keyboard__CurrentRotationDegrees
            NA_ROTATION_STEPS[@na_rotation_step.to_i]
        end

        def Na__Keyboard__UpdateStatusText
            degrees = self.Na__Keyboard__CurrentRotationDegrees
            Sketchup::set_status_text(
                "Profile Path Tracer: Click path vertex to place start | Rotation #{degrees}° [TAB]",
                NA_STATUS_PROMPT_KEY
            )
        end
        private :Na__Keyboard__UpdateStatusText

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
