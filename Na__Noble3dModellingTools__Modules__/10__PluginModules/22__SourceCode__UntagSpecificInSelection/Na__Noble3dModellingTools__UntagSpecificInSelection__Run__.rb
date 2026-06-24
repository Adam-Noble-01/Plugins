# =============================================================================
# NA NOBLE3D MODELLING TOOLS - UNTAG SPECIFIC IN SELECTION - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__UntagSpecificInSelection__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__UntagSpecificInSelection
# PURPOSE    : Public execution entrypoint for the Untag Specific In Selection tool
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__UntagSpecificInSelection

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Untag Specific In Selection
        # ------------------------------------------------------------
        # Validates the selection, collects tags recursively, and opens
        # the checklist dialog.  Returns an early na_result with a clear
        # message if preconditions are not met.
        # ------------------------------------------------------------
        def self.Na__UntagSpecificInSelection__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selection = model.selection
            return na_result(false, 'Select one or more entities, then run Untag Specific In Selection again.') if selection.empty?

            tags_data = Na__UntagSpecificInSelection__TagCollector.Na__UntagSpecificInSelection__TagCollector__CollectTagsRecursive(
                selection,
                model
            )

            return na_result(false, 'No tags found in selection. All entities are already untagged.') if tags_data.empty?

            Na__UntagSpecificInSelection__DialogManager.Na__UntagSpecificInSelection__DialogManager__ShowDialog(
                tags_data,
                model
            )

            tag_count = tags_data.size
            na_result(true, "Untag Specific In Selection dialog opened. Found #{tag_count} #{tag_count == 1 ? 'tag' : 'tags'} in selection.")
        rescue => error
            na_result(false, "Untag Specific In Selection failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

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

    end # module Na__UntagSpecificInSelection
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
