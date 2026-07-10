# =============================================================================
# NA NOBLE3D MODELLING TOOLS - NESTED EDGE STATE TOOLS - MUTATOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__NestedEdgeStateTools__Mutator__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__NestedEdgeStateTools
# PURPOSE    : Apply one requested SketchUp edge property state
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__NestedEdgeStateTools

# -----------------------------------------------------------------------------
# REGION | Edge State Mutation
# -----------------------------------------------------------------------------

        # FUNCTION | Apply the Requested State to One Edge
        # ------------------------------------------------------------
        def self.na_apply_edge_state(edge, action_key)
            return :unchanged if na_edge_already_matches?(edge, action_key)

            na_write_edge_state(edge, action_key)
            :changed
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check Whether an Edge Already Matches
        # ------------------------------------------------------------
        def self.na_edge_already_matches?(edge, action_key)
            case action_key
            when :hide
                edge.hidden?
            when :unhide
                !edge.hidden?
            when :unsmooth
                !edge.smooth?
            when :unsoften
                !edge.soft?
            else
                raise ArgumentError, "Unsupported edge-state action: #{action_key.inspect}"
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write One Edge Property
        # ------------------------------------------------------------
        def self.na_write_edge_state(edge, action_key)
            case action_key
            when :hide
                edge.hidden = true
            when :unhide
                edge.hidden = false
            when :unsmooth
                edge.smooth = false
            when :unsoften
                edge.soft = false
            else
                raise ArgumentError, "Unsupported edge-state action: #{action_key.inspect}"
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__NestedEdgeStateTools
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
