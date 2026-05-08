# =============================================================================
# NA NOBLE3D MODELLING TOOLS - AUTO GROUP UTILITY - ISLAND DETECTOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__AutoGroupUtility__IslandDetector__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__AutoGroupUtility__IslandDetector
# PURPOSE    : Extract raw geometry and detect disconnected island clusters
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__AutoGroupUtility__IslandDetector

# -----------------------------------------------------------------------------
# REGION | Geometry Extraction
# -----------------------------------------------------------------------------

        # FUNCTION | Extract Edges and Faces from a Selection
        # ------------------------------------------------------------
        def self.Na__AutoGroupUtility__ExtractRawGeometry(selection)
            edges = selection.grep(Sketchup::Edge)
            faces = selection.grep(Sketchup::Face)
            (edges + faces).uniq
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Island Detection
# -----------------------------------------------------------------------------

        # FUNCTION | Detect Disconnected Geometry Islands via Flood Fill
        # ------------------------------------------------------------
        def self.Na__AutoGroupUtility__DetectIslands(raw_geometry)
            islands   = []
            remaining = raw_geometry.dup

            until remaining.empty?
                seed      = remaining.first
                connected = seed.all_connected
                islands  << connected
                remaining -= connected
            end

            islands
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__AutoGroupUtility__IslandDetector
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
