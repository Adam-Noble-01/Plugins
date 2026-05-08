# =============================================================================
# NA NOBLE3D MODELLING TOOLS - AUTO GROUP UTILITY - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__AutoGroupUtility__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__AutoGroupUtility
# PURPOSE    : Public execution entrypoint for auto-grouping disconnected islands
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__AutoGroupUtility

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Auto Group Utility on Active Selection
        # ------------------------------------------------------------
        def self.Na__AutoGroupUtility__Run
            model     = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selection = model.selection
            return na_result(false, 'Select geometry to process, then run the command again.') if selection.empty?

            raw_geometry = Na__AutoGroupUtility__IslandDetector.Na__AutoGroupUtility__ExtractRawGeometry(selection)
            return na_result(false, 'Selection contains no raw geometry (edges or faces).') if raw_geometry.empty?

            islands = Na__AutoGroupUtility__IslandDetector.Na__AutoGroupUtility__DetectIslands(raw_geometry)
            return na_result(false, 'No geometry islands could be detected from the selection.') if islands.empty?

            entities   = model.active_entities
            non_solids = []

            model.start_operation('Auto Group Solids', true)

            islands.each do |cluster|
                group = na_group_island(entities, cluster)
                non_solids << group unless na_validate_manifold(group)
            end

            model.commit_operation

            na_report_non_solids(non_solids) if non_solids.any?
            na_result(true, "Grouped #{islands.length} island(s). #{non_solids.length} non-solid warning(s).")
        rescue => error
            na_result(false, "#{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Group a Single Island Cluster into a SketchUp Group
        # ------------------------------------------------------------
        def self.na_group_island(entities, cluster)
            entities.add_group(cluster)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Validate a Group as a Manifold Solid
        # ------------------------------------------------------------
        def self.na_validate_manifold(group)
            group.manifold?
        rescue
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Report Non-Solid Groups to User
        # ------------------------------------------------------------
        def self.na_report_non_solids(non_solid_groups)
            ids = non_solid_groups.map(&:entityID).join("\n")
            UI.messagebox("\u26A0 Some groups are NOT valid solids:\n\n#{ids}")
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

    end # module Na__AutoGroupUtility
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
