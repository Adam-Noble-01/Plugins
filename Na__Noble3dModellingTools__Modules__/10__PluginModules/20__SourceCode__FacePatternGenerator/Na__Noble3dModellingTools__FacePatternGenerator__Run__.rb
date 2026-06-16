# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - RUN ENTRYPOINT
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator

        NA_FACE_PATTERN_TITLE = 'Na Noble3d - Face Pattern Generator'.freeze

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

        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
