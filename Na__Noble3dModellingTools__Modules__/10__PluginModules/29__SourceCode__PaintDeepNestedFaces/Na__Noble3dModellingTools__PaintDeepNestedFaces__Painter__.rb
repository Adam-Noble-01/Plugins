# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PAINT DEEP NESTED FACES - PAINTER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PaintDeepNestedFaces__Painter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PaintDeepNestedFaces__Painter
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Apply one material to a collected set of faces under the Noble
#              Architecture front / back face standard.
# CREATED    : 2026
#
# BACK FACE STANDARD:
# - Opaque material      -> front face painted, back face stripped to default.
#   A clean back face keeps section fills, exports and downstream renderers
#   predictable, and makes reversed geometry obvious rather than hidden.
# - Transparent material -> front and back faces both painted. Glass, water and
#   any alpha material must read correctly when viewed from either side.
# - Default material     -> both sides stripped. SketchUp represents the Default
#   material as nil, so passing nil here is a full reset of the face rather than
#   a special case bolted on beside painting.
#
# The transparency test comes from the MaterialProbe, so the rule applied here
# is always the rule previewed in the dialog.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PaintDeepNestedFaces__Painter

# -----------------------------------------------------------------------------
# REGION | Public Painting API
# -----------------------------------------------------------------------------

        # FUNCTION | Apply a Material to Every Face in a Collected Set
        # ------------------------------------------------------------
        # Caller owns the undo operation. This method only mutates faces and
        # reports what it changed.
        #
        # @param faces    [Array<Sketchup::Face>]  Faces gathered by the collector
        # @param material [Sketchup::Material, nil] Material to apply, or nil for
        #                                          the SketchUp default material
        # @return [Hash] Painting statistics
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__Painter__PaintFaces(faces, material)
            is_default     = material.nil?
            is_transparent = Na__PaintDeepNestedFaces__MaterialProbe
                             .Na__PaintDeepNestedFaces__MaterialProbe__IsTransparent(material)

            statistics = na_empty_statistics
            statistics[:is_default]     = is_default
            statistics[:back_face_rule] = na_back_face_rule(is_default, is_transparent)

            faces.each do |face|
                na_paint_one_face(face, material, is_transparent, statistics)
            end

            statistics
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Name the Rule Being Applied to Both Face Sides
        # ------------------------------------------------------------
        def self.na_back_face_rule(is_default, is_transparent)
            return 'strip_both' if is_default
            return 'paint_both' if is_transparent

            'front_only'
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Per Face Application
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Apply the Standard to a Single Face
        # ------------------------------------------------------------
        def self.na_paint_one_face(face, material, is_transparent, statistics)
            unless na_valid_face?(face)
                statistics[:skipped_face_count] += 1
                return
            end

            back_target  = is_transparent ? material : nil
            front_moved  = na_assign_front_material(face, material)
            back_moved   = na_assign_back_material(face, back_target)

            statistics[:front_changed_count] += 1 if front_moved
            statistics[:back_painted_count]  += 1 if back_moved && is_transparent
            statistics[:back_cleared_count]  += 1 if back_moved && !is_transparent

            if front_moved || back_moved
                statistics[:changed_face_count] += 1
            else
                statistics[:unchanged_face_count] += 1
            end
        rescue => error
            statistics[:skipped_face_count] += 1
            puts "[Na__PaintDeepNestedFaces] Face skipped: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Set the Front Material and Report Whether It Moved
        # ------------------------------------------------------------
        def self.na_assign_front_material(face, material)
            return false if na_same_material?(face.material, material)

            face.material = material
            true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Set the Back Material and Report Whether It Moved
        # ------------------------------------------------------------
        def self.na_assign_back_material(face, material)
            return false if na_same_material?(face.back_material, material)

            face.back_material = material
            true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare Two Material Slots Including the Nil Case
        # ------------------------------------------------------------
        def self.na_same_material?(current_material, target_material)
            return true if current_material.nil? && target_material.nil?
            return false if current_material.nil? || target_material.nil?

            current_material.equal?(target_material) ||
                current_material.name == target_material.name
        rescue
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check a Face Is Still Alive Before Painting
        # ------------------------------------------------------------
        def self.na_valid_face?(face)
            face.is_a?(Sketchup::Face) &&
                face.valid? &&
                (!face.respond_to?(:deleted?) || !face.deleted?)
        rescue
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Statistics
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build an Empty Painting Statistics Hash
        # ------------------------------------------------------------
        def self.na_empty_statistics
            {
                changed_face_count:   0,
                unchanged_face_count: 0,
                skipped_face_count:   0,
                front_changed_count:  0,
                back_painted_count:   0,
                back_cleared_count:   0,
                back_face_rule:       'front_only',
                is_default:           false
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PaintDeepNestedFaces__Painter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
