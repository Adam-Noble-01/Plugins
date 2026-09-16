# =============================================================================
# NA NOBLE3D MODELLING TOOLS - ORIENT FACES TOWARD CAMERA - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__OrientFacesTowardCamera__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__OrientFacesTowardCamera
# PURPOSE    : Run the one-click face-toward-camera command
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__OrientFacesTowardCamera

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'Orient Faces Toward Camera'.freeze
        NA_PROGRESS_TEXT = 'Orienting selected faces toward the camera...'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Reverse Selected Faces That Point Away From the Camera
        # ------------------------------------------------------------
        def self.Na__OrientFacesTowardCamera__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model
            return na_result(false, 'Select one or more faces, groups, or components first.') if model.selection.empty?

            view = model.active_view
            camera = view && view.camera
            return na_result(false, 'No active camera available.') unless camera

            operation_started = false
            Sketchup.status_text = NA_PROGRESS_TEXT

            model.start_operation(NA_OPERATION_NAME, true)
            operation_started = true
            selected_entities = model.selection.to_a
            if na_selection_requires_change?(selected_entities, camera)
                selected_entities = na_make_active_path_unique(model, selected_entities)
            end
            statistics = na_process_selection(selected_entities, camera)

            if statistics[:reversed_face_count].positive?
                model.commit_operation
                view.invalidate
            else
                model.abort_operation
            end
            operation_started = false

            Sketchup.status_text = ''
            na_result(
                statistics[:visited_face_count].positive?,
                na_build_result_message(statistics)
            )
        rescue StandardError => error
            model.abort_operation if model && operation_started
            Sketchup.status_text = ''
            na_result(false, "#{NA_OPERATION_NAME} failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Messages
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build a Concise Action Summary
        # ------------------------------------------------------------
        def self.na_build_result_message(statistics)
            message_parts = []

            if statistics[:visited_face_count].zero?
                message_parts << 'No editable faces were found in the supported selection'
            else
                message_parts << "#{statistics[:reversed_face_count]} face(s) reversed"
                message_parts << "#{statistics[:already_facing_face_count]} face(s) already facing the camera"
                message_parts << "#{statistics[:edge_on_face_count]} face(s) edge-on to the view" if statistics[:edge_on_face_count].positive?
                message_parts << "#{statistics[:skipped_face_count]} face(s) skipped" if statistics[:skipped_face_count].positive?
            end

            message_parts << "skipped #{statistics[:locked_container_count]} locked container(s)" if statistics[:locked_container_count].positive?
            message_parts << "ignored #{statistics[:unsupported_selection_count]} unsupported selected object(s)" if statistics[:unsupported_selection_count].positive?
            message_parts << "stopped at #{statistics[:depth_limit_count]} over-depth container(s)" if statistics[:depth_limit_count].positive?
            message_parts << "skipped #{statistics[:cyclic_container_count]} cyclic container reference(s)" if statistics[:cyclic_container_count].positive?

            "#{NA_OPERATION_NAME}: #{message_parts.join('; ')}."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__OrientFacesTowardCamera
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
