# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECT QUAD FACE RINGS - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectQuadFaceRings__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectQuadFaceRings
# PURPOSE    : Public execution entrypoints and result handling
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectQuadFaceRings

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_SELECT_QUAD_FACE_RINGS__MAXIMUM_STEP_COUNT = 10_000

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Run Quad Rings with Shortest Strategy
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__RunShortest
            self.Na__SelectQuadFaceRings__Run(:shortest_opposite_edges)
        end
        # ------------------------------------------------------------

        # FUNCTION | Run Quad Rings with Longest Strategy
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__RunLongest
            self.Na__SelectQuadFaceRings__Run(:longest_opposite_edges)
        end
        # ------------------------------------------------------------

        # FUNCTION | Run Quad Rings with Largest Count Strategy
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__RunLargest
            self.Na__SelectQuadFaceRings__Run(:largest_face_count)
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute Quad Ring Selection from Active Selection
        # ------------------------------------------------------------
        def self.Na__SelectQuadFaceRings__Run(preferred_direction_strategy = :shortest_opposite_edges)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selection = model.selection
            selected_faces = Na__SelectQuadFaceRings__Selection.Na__SelectQuadFaceRings__SelectedFacesFromSelection(selection)
            return na_result(false, 'Select one or more quad faces, then run the command again.') if selected_faces.empty?

            non_quad_faces = Na__SelectQuadFaceRings__Selection.Na__SelectQuadFaceRings__NonQuadFacesFromFaces(selected_faces)
            unless non_quad_faces.empty?
                return na_result(false, "Only quad faces are supported. Found #{non_quad_faces.length} non-quad face(s).")
            end

            ring_faces = Na__SelectQuadFaceRings__Strategy.Na__SelectQuadFaceRings__PreferredFaceRingsFromSeedFaces(
                selected_faces,
                preferred_direction_strategy,
                NA_SELECT_QUAD_FACE_RINGS__MAXIMUM_STEP_COUNT
            )
            return na_result(false, 'No face rings could be found from the selected seed faces.') if ring_faces.empty?

            selected_face_count = Na__SelectQuadFaceRings__Selection.Na__SelectQuadFaceRings__ReplaceSelectionWithFaces(
                selection,
                ring_faces
            )

            na_result(true, "Selected #{selected_face_count} face(s) across #{selected_faces.length} seed ring(s).")
        rescue => error
            na_result(false, "#{error.class}: #{error.message}")
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

    end # module Na__SelectQuadFaceRings
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
