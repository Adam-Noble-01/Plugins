# =============================================================================
# NA NOBLE3D MODELLING TOOLS - ORIENT FACES TOWARD CAMERA - ORIENT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__OrientFacesTowardCamera__Orient__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__OrientFacesTowardCamera
# PURPOSE    : Decide whether a face's front points at the camera, then reverse it
# CREATED    : 2026
#
# WORLD NORMAL:
# Transform a local point and the same point offset along Face#normal. Subtracting
# those world points gives a normal that stays perpendicular under non-uniform
# scale and flips correctly under a mirrored instance.
#
# CAMERA TEST:
# Perspective uses the vector from the face sample toward Camera#eye.
# Parallel projection uses the reverse of Camera#direction (eye toward the view).
# A positive dot product means the front already faces the camera.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__OrientFacesTowardCamera

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_EDGE_ON_DOT_THRESHOLD = 1.0e-6

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Orientation
# -----------------------------------------------------------------------------

        # FUNCTION | Reverse One Face When Its Front Points Away From the Camera
        # ------------------------------------------------------------
        def self.na_orient_face(face, transformation, camera)
            decision = na_face_camera_decision(face, transformation, camera)
            return decision unless decision == :faces_away

            face.reverse!
            :reversed
        end
        # ------------------------------------------------------------

        # FUNCTION | Report Whether a Face Needs Reversing
        # ------------------------------------------------------------
        def self.na_face_requires_reverse?(face, transformation, camera)
            na_face_camera_decision(face, transformation, camera) == :faces_away
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Classify One Face Against the Camera
        # ------------------------------------------------------------
        def self.na_face_camera_decision(face, transformation, camera)
            return :skipped unless na_valid_face?(face)
            return :skipped unless camera

            world_point = na_world_sample_point(face, transformation)
            world_normal = na_world_normal(face, transformation)
            return :skipped unless world_point && world_normal

            toward_camera = na_vector_toward_camera(world_point, camera)
            return :skipped unless toward_camera

            alignment = world_normal.dot(toward_camera)
            return :already_facing if alignment > NA_EDGE_ON_DOT_THRESHOLD
            return :edge_on if alignment >= -NA_EDGE_ON_DOT_THRESHOLD

            :faces_away
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | World Space Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build a Unit Vector From the Face Toward the Camera
        # ------------------------------------------------------------
        def self.na_vector_toward_camera(world_point, camera)
            toward_camera = if camera.perspective?
                camera.eye - world_point
            else
                camera_direction = camera.direction
                return nil unless camera_direction && camera_direction.valid?

                camera_direction.reverse
            end

            return nil unless toward_camera && toward_camera.valid?
            return nil unless toward_camera.length > 0.0

            toward_camera.normalize
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Transform Face#normal Into World Space
        # ------------------------------------------------------------
        def self.na_world_normal(face, transformation)
            local_normal = na_local_face_normal(face)
            return nil unless local_normal

            sample_local = na_local_sample_point(face)
            return nil unless sample_local

            offset_local = sample_local.offset(local_normal)
            sample_world = sample_local.transform(transformation)
            offset_world = offset_local.transform(transformation)
            world_normal = offset_world - sample_world
            return nil unless world_normal.valid?
            return nil unless world_normal.length > 0.0

            world_normal.normalize
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Transform One Face Vertex Into World Space
        # ------------------------------------------------------------
        def self.na_world_sample_point(face, transformation)
            sample_local = na_local_sample_point(face)
            return nil unless sample_local

            sample_local.transform(transformation)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read Face#normal, Skipping Degenerate Faces
        # ------------------------------------------------------------
        def self.na_local_face_normal(face)
            local_normal = face.normal
            return nil unless local_normal && local_normal.valid?
            return nil unless local_normal.length > 0.0

            local_normal
        rescue StandardError
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Pick a Vertex Position on the Face
        # ------------------------------------------------------------
        def self.na_local_sample_point(face)
            vertices = face.vertices
            return nil if vertices.nil? || vertices.empty?

            sample_vertex = vertices[0]
            return nil unless sample_vertex && sample_vertex.valid?

            sample_vertex.position
        rescue StandardError
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check a Face Can Be Inspected and Reversed
        # ------------------------------------------------------------
        def self.na_valid_face?(face)
            face.is_a?(Sketchup::Face) &&
                face.respond_to?(:valid?) &&
                face.valid? &&
                (!face.respond_to?(:deleted?) || !face.deleted?)
        rescue StandardError
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__OrientFacesTowardCamera
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
