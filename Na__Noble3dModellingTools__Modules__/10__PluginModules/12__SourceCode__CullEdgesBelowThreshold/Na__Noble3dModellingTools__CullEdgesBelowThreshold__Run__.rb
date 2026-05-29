# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CULL EDGES BELOW THRESHOLD - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CullEdgesBelowThreshold__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__CullEdgesBelowThreshold
# PURPOSE    : Public execution entrypoint for culling edges below a length threshold
# CREATED    : 2026
#
# METHODOLOGY (GROUP ISOLATION STRATEGY):
# 1. Explode Curves : Ensures arcs/circles are treated as individual segments.
# 2. Partition      : Sorts edges into Keep (>= threshold) and Cull (< threshold).
# 3. Isolate        : Moves Keep edges into a temporary group to protect shared vertices.
# 4. Delete         : Removes cull edges from the active context.
# 5. Restore        : Explodes the temp group, returning Keep edges to their original context.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__CullEdgesBelowThreshold

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Cull Edges Below Threshold
        # ------------------------------------------------------------
        def self.Na__CullEdgesBelowThreshold__Run
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            sel = model.selection
            return na_result(false, 'Select edges first, then run again.') if sel.empty?

            threshold_mm = na_prompt_threshold
            return na_result(false, 'Cancelled.') unless threshold_mm

            threshold_internal = threshold_mm.mm

            model.start_operation('Cull Edges Below Threshold', true)

            entities       = model.active_entities
            count_exploded = na_explode_curves(sel)
            edges_keep, edges_cull = na_partition_edges(sel, threshold_internal)
            counts         = na_isolate_and_cull(entities, edges_keep, edges_cull)

            model.commit_operation

            puts "[Na__CullEdgesBelowThreshold] Threshold: #{threshold_mm}mm | Curves Exploded: #{count_exploded} | Culled: #{counts[:culled]} | Kept: #{counts[:kept]}"
            na_result(true, "Culled #{counts[:culled]} edge(s) below #{threshold_mm}mm. Kept #{counts[:kept]}.")
        rescue => error
            model&.abort_operation rescue nil
            na_result(false, "#{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Prompt User for Minimum Edge Length
        # ------------------------------------------------------------
        def self.na_prompt_threshold
            input = UI.inputbox(['Minimum Edge Length (mm):'], [20.0], 'Cull Edges Threshold')
            return nil unless input
            input[0].to_f
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Explode Curves in Selection to Individual Segments
        # ------------------------------------------------------------
        def self.na_explode_curves(selection)
            edges  = selection.grep(Sketchup::Edge)
            curves = edges.map(&:curve).compact.uniq
            count  = 0
            curves.each do |curve|
                next unless curve.valid?
                curve.explode
                count += 1
            end
            count
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Partition Edges into Keep and Cull Arrays
        # ------------------------------------------------------------
        def self.na_partition_edges(selection, threshold_internal)
            edges_keep = []
            edges_cull = []
            selection.grep(Sketchup::Edge).each do |edge|
                next unless edge.valid?
                if edge.length < threshold_internal
                    edges_cull << edge
                else
                    edges_keep << edge
                end
            end
            [edges_keep, edges_cull]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Isolate Keep Edges, Erase Cull Edges, Restore Keep Edges
        # ------------------------------------------------------------
        def self.na_isolate_and_cull(entities, edges_keep, edges_cull)
            temp_group = entities.add_group(edges_keep) unless edges_keep.empty?
            entities.erase_entities(edges_cull)         unless edges_cull.empty?
            temp_group.explode if temp_group && temp_group.valid?
            { culled: edges_cull.size, kept: edges_keep.size }
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

    end # module Na__CullEdgesBelowThreshold
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
