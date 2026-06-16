# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__FacePatternGenerator__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__FacePatternGenerator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Public execution entrypoint for the Face Pattern Generator tool.
# CREATED    : 2026
#
# WORKFLOW:
# 1. Validate that exactly one SketchUp face is selected in the active context.
# 2. Project the face boundary to local 2D millimetre coordinates (FaceData).
# 3. Open the HtmlDialog and push the face payload to the SVG preview.
# 4. The dialog generates and previews the chosen pattern inside the face bounds.
# 5. On "Apply to Face" the polylines (or slate instances) are written to the model.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_FACE_PATTERN_TITLE = 'Na Noble3d - Face Pattern Generator'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run the Face Pattern Generator Workflow
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__Run
            payload_result = Na__FacePatternGenerator__FaceData.Na__FacePatternGenerator__BuildSelectionPayload
            unless payload_result[:success]
                UI.messagebox(payload_result[:message])
                return payload_result
            end

            Na__FacePatternGenerator__DialogManager.Na__FacePatternGenerator__ShowDialog(payload_result[:payload])
            na_result(true, "#{NA_FACE_PATTERN_TITLE} dialog opened.")
        rescue => error
            na_result(false, "Face Pattern Generator failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FacePatternGenerator
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
