# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUPS TO COMPONENT - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupsToComponent__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupsToComponent
# PURPOSE    : Public execution entrypoint for converting groups to a component
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupsToComponent

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Convert Selected Groups to Shared Component Instances
        # ------------------------------------------------------------
        def self.Na__GroupsToComponent__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            candidate_groups = Na__GroupsToComponent__Validator
                .Na__GroupsToComponent__Validator__CollectCandidateGroups(model)
            return na_result(false, 'Select one or more unlocked groups, then run the command again.') if candidate_groups.empty?

            consistency_result = Na__GroupsToComponent__Validator
                .Na__GroupsToComponent__Validator__CheckConsistency(candidate_groups)
            warning_message = Na__GroupsToComponent__Validator
                .Na__GroupsToComponent__Validator__BuildWarningMessage(candidate_groups, consistency_result)

            return na_result(false, 'Groups To Component cancelled by user.') unless na_user_confirms_warnings?(warning_message)

            if candidate_groups.length == 1
                return na_run_single_group_conversion(model, candidate_groups.first)
            end

            na_activate_inference_picker(model, candidate_groups)
        rescue => error
            Sketchup.status_text = ''
            na_result(false, "Groups To Component failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert a Single Selected Group
        # ------------------------------------------------------------
        def self.na_run_single_group_conversion(model, group)
            converted_instances = Na__GroupsToComponent__Converter
                .Na__GroupsToComponent__Converter__RunConversion(model, [group], group)

            return na_result(false, 'Groups To Component failed to convert the selected group.') if converted_instances.empty?

            na_result(true, 'Converted 1 group to a component instance.')
        rescue => error
            na_result(false, "Groups To Component failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Activate Inference Group Picker Tool
        # ------------------------------------------------------------
        def self.na_activate_inference_picker(model, candidate_groups)
            on_pick_callback = proc do |inference_group|
                na_handle_inference_pick(model, candidate_groups, inference_group)
            end

            model.select_tool(Na__GroupsToComponent__PickerTool.new(candidate_groups, on_pick_callback))
            na_result(true, 'Click the group to use as the component template.')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Handle Inference Group Selection Callback
        # ------------------------------------------------------------
        def self.na_handle_inference_pick(model, candidate_groups, inference_group)
            return unless model

            unless inference_group&.valid?
                Sketchup.status_text = 'Groups To Component cancelled.'
                return
            end

            converted_instances = Na__GroupsToComponent__Converter
                .Na__GroupsToComponent__Converter__RunConversion(model, candidate_groups, inference_group)

            if converted_instances.empty?
                Sketchup.status_text = 'Groups To Component failed.'
                return
            end

            Sketchup.status_text = "Converted #{converted_instances.length} group(s) to component instance(s)."
        rescue => error
            Sketchup.status_text = "Groups To Component failed: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Confirm Geometry Warnings with the User
        # ------------------------------------------------------------
        def self.na_user_confirms_warnings?(warning_message)
            return true if warning_message.nil? || warning_message.empty?

            messagebox_yesno = defined?(UI::MB_YESNO) ? UI::MB_YESNO : 4
            messagebox_yes   = defined?(UI::MSGDIALOG_YES) ? UI::MSGDIALOG_YES : 6

            UI.messagebox(warning_message, messagebox_yesno) == messagebox_yes
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

    end # module Na__GroupsToComponent
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
