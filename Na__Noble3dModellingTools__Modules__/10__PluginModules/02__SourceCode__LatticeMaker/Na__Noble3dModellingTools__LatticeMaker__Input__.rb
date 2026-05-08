# =============================================================================
# NA NOBLE3D MODELLING TOOLS - LATTICE MAKER - INPUT HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__LatticeMaker__Input__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__LatticeMaker__Input
# PURPOSE    : Input collection, parsing, and validation helpers
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__LatticeMaker__Input

# -----------------------------------------------------------------------------
# REGION | Input and Validation Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Collect Valid Edges from Selection
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__CollectSelectedEdges(selection)
            selection.grep(Sketchup::Edge).select { |edge| edge.valid? }
        end
        # ------------------------------------------------------------

        # FUNCTION | Request Width/Depth/Mode From User
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__RequestUserParameters(plugin_name, default_width, default_depth, default_mode)
            prompts = ['Width', 'Depth', 'Mode']
            defaults = [default_width, default_depth, default_mode]
            lists = ['', '', '3D|2D']

            input = UI.inputbox(prompts, defaults, lists, plugin_name)
            return nil unless input

            width = self.Na__LatticeMaker__LengthFromInput(input[0], default_width)
            depth = self.Na__LatticeMaker__LengthFromInput(input[1], default_depth)
            mode = input[2].to_s.strip.upcase
            mode = '3D' unless %w[2D 3D].include?(mode)

            [width, depth, mode]
        end
        # ------------------------------------------------------------

        # FUNCTION | Convert User Input to Length
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__LengthFromInput(value, fallback)
            return value if defined?(Length) && value.is_a?(Length)
            return value.to_l if value.respond_to?(:to_l)

            value.to_s.to_l
        rescue
            fallback
        end
        # ------------------------------------------------------------

        # FUNCTION | Validate Lattice Parameters
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__ValidateParameters(width, depth, mode)
            raise 'Width must be greater than 0.' unless width && width > 0
            raise 'Depth must be greater than 0 for 3D mode.' if mode == '3D' && (!depth || depth <= 0)

            true
        end
        # ------------------------------------------------------------

        # FUNCTION | Convert Edges to Segment Point Pairs
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__ConvertEdgesToSegments(edges)
            edges.map { |edge| [edge.start.position.clone, edge.end.position.clone] }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__LatticeMaker__Input
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
