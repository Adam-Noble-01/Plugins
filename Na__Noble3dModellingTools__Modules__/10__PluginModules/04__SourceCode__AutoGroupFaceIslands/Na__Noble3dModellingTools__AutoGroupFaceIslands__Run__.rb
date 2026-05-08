# =============================================================================
# NA NOBLE3D MODELLING TOOLS - AUTO GROUP FACE ISLANDS - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__AutoGroupFaceIslands__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__AutoGroupFaceIslands
# PURPOSE    : Public execution entrypoint for grouping individual face islands
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__AutoGroupFaceIslands

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Run Auto Group Face Islands on Active Selection
        # ------------------------------------------------------------
        def self.Na__AutoGroupFaceIslands__Run
            model     = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selection = model.selection
            return na_result(false, 'Select faces to process, then run the command again.') if selection.empty?

            faces = Na__AutoGroupFaceIslands__FaceGrouper.Na__AutoGroupFaceIslands__FilterToFacesOnly(model, selection)
            return na_result(false, 'Selection contains no faces to group.') if faces.empty?

            entities      = model.active_entities
            grouped_faces = []
            non_solids    = []
            group_count   = 0

            model.start_operation('Auto Group Face Islands', true)

            faces.each do |face|
                next if grouped_faces.include?(face)

                group_count += 1
                face_group   = Na__AutoGroupFaceIslands__FaceGrouper.Na__AutoGroupFaceIslands__CreateFaceGroup(entities, face, group_count)
                grouped_faces << face

                is_solid = Na__AutoGroupFaceIslands__FaceGrouper.Na__AutoGroupFaceIslands__ValidateManifold(face_group)
                non_solids << face_group unless is_solid
            end

            model.commit_operation

            Na__AutoGroupFaceIslands__FaceGrouper.Na__AutoGroupFaceIslands__ApplySelectionDisplayFix(model)

            na_result(true, "Created #{group_count} face island group(s).")
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

    end # module Na__AutoGroupFaceIslands
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
