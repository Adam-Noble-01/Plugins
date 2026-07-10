# =============================================================================
# NA NOBLE3D MODELLING TOOLS - NESTED EDGE STATE TOOLS - RUN ENTRYPOINTS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__NestedEdgeStateTools__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__NestedEdgeStateTools
# PURPOSE    : Run recursive hide, unhide, unsmooth, and unsoften commands
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__NestedEdgeStateTools

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_EDGE_STATE_ACTIONS = {
            hide: {
                operation_name: 'Hide Nested Edges',
                progress_text: 'Hiding edges in the selected hierarchy...',
                changed_label: 'hidden',
                unchanged_label: 'already hidden'
            }.freeze,
            unhide: {
                operation_name: 'Unhide Nested Edges',
                progress_text: 'Unhiding edges in the selected hierarchy...',
                changed_label: 'unhidden',
                unchanged_label: 'already visible'
            }.freeze,
            unsmooth: {
                operation_name: 'Unsmooth Nested Edges',
                progress_text: 'Removing smoothing from edges in the selected hierarchy...',
                changed_label: 'unsmoothed',
                unchanged_label: 'already unsmoothed'
            }.freeze,
            unsoften: {
                operation_name: 'Unsoften Nested Edges',
                progress_text: 'Removing softening from edges in the selected hierarchy...',
                changed_label: 'unsoftened',
                unchanged_label: 'already unsoftened'
            }.freeze
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Hide Selected and Nested Edges
        # ------------------------------------------------------------
        def self.Na__NestedEdgeStateTools__RunHideNestedEdges
            na_run_edge_state_action(:hide)
        end
        # ------------------------------------------------------------

        # FUNCTION | Unhide Selected and Nested Edges
        # ------------------------------------------------------------
        def self.Na__NestedEdgeStateTools__RunUnhideNestedEdges
            na_run_edge_state_action(:unhide)
        end
        # ------------------------------------------------------------

        # FUNCTION | Remove Smoothing from Selected and Nested Edges
        # ------------------------------------------------------------
        def self.Na__NestedEdgeStateTools__RunUnsmoothNestedEdges
            na_run_edge_state_action(:unsmooth)
        end
        # ------------------------------------------------------------

        # FUNCTION | Remove Softening from Selected and Nested Edges
        # ------------------------------------------------------------
        def self.Na__NestedEdgeStateTools__RunUnsoftenNestedEdges
            na_run_edge_state_action(:unsoften)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Command Execution
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Run One Recursive Edge-State Action
        # ------------------------------------------------------------
        def self.na_run_edge_state_action(action_key)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model
            return na_result(false, 'Select one or more edges, groups, or components first.') if model.selection.empty?

            action_config = NA_EDGE_STATE_ACTIONS.fetch(action_key)
            operation_started = false
            Sketchup.status_text = action_config.fetch(:progress_text)

            model.start_operation(action_config.fetch(:operation_name), true)
            operation_started = true
            selected_entities = model.selection.to_a
            if na_selection_requires_change?(selected_entities, action_key)
                selected_entities = na_make_active_path_unique(model, selected_entities)
            end
            statistics = na_process_selection(selected_entities, action_key)

            if statistics[:changed_edge_count].positive?
                model.commit_operation
            else
                model.abort_operation
            end
            operation_started = false

            Sketchup.status_text = ''
            na_result(
                statistics[:visited_edge_count].positive?,
                na_build_result_message(action_config, statistics)
            )
        rescue StandardError => error
            model.abort_operation if model && operation_started
            Sketchup.status_text = ''
            action_name = action_config ? action_config.fetch(:operation_name) : 'Nested Edge State'
            na_result(false, "#{action_name} failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Messages
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build a Concise Action Summary
        # ------------------------------------------------------------
        def self.na_build_result_message(action_config, statistics)
            message_parts = []

            if statistics[:visited_edge_count].zero?
                message_parts << 'No editable edges were found in the supported selection.'
            else
                message_parts << "#{statistics[:changed_edge_count]} edge(s) #{action_config.fetch(:changed_label)}"
                message_parts << "#{statistics[:unchanged_edge_count]} edge(s) #{action_config.fetch(:unchanged_label)}"
            end

            message_parts << "skipped #{statistics[:locked_container_count]} locked container(s)" if statistics[:locked_container_count].positive?
            message_parts << "ignored #{statistics[:unsupported_selection_count]} unsupported selected object(s)" if statistics[:unsupported_selection_count].positive?
            message_parts << "stopped at #{statistics[:depth_limit_count]} over-depth container(s)" if statistics[:depth_limit_count].positive?
            message_parts << "skipped #{statistics[:cyclic_container_count]} cyclic container reference(s)" if statistics[:cyclic_container_count].positive?

            "#{action_config.fetch(:operation_name)}: #{message_parts.join('; ')}."
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

    end # module Na__NestedEdgeStateTools
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
