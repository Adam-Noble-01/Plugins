# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INSERTION FRAME HELPER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__GeometryHelpers__InsertionFrame__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__GeometryHelpers
# MODULE     : Na__InsertionFrame
# AUTHOR     : Noble Architecture
# PURPOSE    : Central authority for resolving how a freshly-built window or
#              door ComponentInstance is positioned + oriented when it is
#              inserted into the model. Replaces the old translation-only
#              `Geom::Transformation.new(point)` calls that ignored wall
#              orientation and the user's drawing axes.
#
# RESOLUTION PRIORITY:
#   1. Full measurement frame (origin + xaxis + yaxis + zaxis from the 2-point
#      or 3-point Opening tool). Built by `na_build_measurement_frame_*`.
#   2. Origin only + the model's active drawing axes (so a user-rotated axis
#      tripod is honoured even when the orientation vector wasn't captured).
#   3. The model's drawing axes alone (caller engages a placement tool).
#   4. IDENTITY (last-resort fallback).
#
# WHY:
#   Native SketchUp drawing tools all respect `Sketchup.active_model.axes`,
#   so users expect a parametric component built by a plugin to do the same.
#   The Opening tools also capture the wall direction (Point A -> Point B
#   in plan view) and, for the 3-point variant, the depth direction. This
#   helper packages that information into a single rigid transform via
#   `Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)`.
#
# NAMING CONVENTION:
#   - Geometry helper namespace Na__GeometryHelpers / na_ prefixes.
#   - Frame Hash schema:  { :origin_in => Geom::Point3d,
#                           :xaxis     => Geom::Vector3d,   # along wall, in plan
#                           :yaxis     => Geom::Vector3d,   # into wall depth
#                           :zaxis     => Geom::Vector3d }  # up (drawing Z)
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
    module Na__GeometryHelpers
        module Na__InsertionFrame

# -----------------------------------------------------------------------------
# REGION | Schema Key + Tolerance Constants
# -----------------------------------------------------------------------------

            NA_FRAME_KEY_ORIGIN = :origin_in
            NA_FRAME_KEY_XAXIS  = :xaxis
            NA_FRAME_KEY_YAXIS  = :yaxis
            NA_FRAME_KEY_ZAXIS  = :zaxis

            NA_MIN_VECTOR_LENGTH = 1.0e-6

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Builders (Measurement Tools -> Frame Hash)
# -----------------------------------------------------------------------------

            # FUNCTION | Build Insertion Frame from a 2-Point Opening Pick
            # ------------------------------------------------------------
            # Two diagonal corner picks on the wall face. The XY component
            # of (B - A) gives the wall direction (xaxis); zaxis is the
            # drawing-axes up vector; yaxis = zaxis x xaxis (into the wall).
            #
            # @param point_a [Geom::Point3d] base corner pick (inches)
            # @param point_b [Geom::Point3d] opposite corner pick (inches)
            # @return [Hash] frame Hash or { :origin_in => point_a } when
            #         the wall direction degenerates (vertical-only delta)
            def self.na_build_measurement_frame_2pt(point_a, point_b)
                return nil unless point_a.is_a?(Geom::Point3d)
                return { NA_FRAME_KEY_ORIGIN => point_a } unless point_b.is_a?(Geom::Point3d)

                zaxis        = na_model_zaxis
                horizontal_v = na_planar_vector(point_a, point_b, zaxis)

                return { NA_FRAME_KEY_ORIGIN => point_a } if horizontal_v.nil?

                xaxis = horizontal_v
                yaxis = (zaxis * xaxis)
                return { NA_FRAME_KEY_ORIGIN => point_a } if yaxis.length < NA_MIN_VECTOR_LENGTH
                yaxis.normalize!

                {
                    NA_FRAME_KEY_ORIGIN => point_a,
                    NA_FRAME_KEY_XAXIS  => xaxis,
                    NA_FRAME_KEY_YAXIS  => yaxis,
                    NA_FRAME_KEY_ZAXIS  => zaxis
                }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Build Insertion Frame from a 3-Point Opening Pick
            # ------------------------------------------------------------
            # Three picks: A (corner), B (opposite façade corner) and D
            # (depth point on the same horizontal as A). xaxis follows
            # the projection of (B - A) onto the drawing ground plane,
            # yaxis follows the projection of (D - A) onto the same plane
            # so the resulting frame is always rigid + orthonormal.
            #
            # @param point_a     [Geom::Point3d] base corner (inches)
            # @param point_b     [Geom::Point3d] far corner  (inches)
            # @param depth_point [Geom::Point3d] depth pick  (inches)
            # @return [Hash] frame Hash; falls back to 2pt frame when the
            #         depth direction is degenerate
            def self.na_build_measurement_frame_3pt(point_a, point_b, depth_point)
                return nil unless point_a.is_a?(Geom::Point3d)
                two_pt_frame = na_build_measurement_frame_2pt(point_a, point_b)
                return two_pt_frame unless depth_point.is_a?(Geom::Point3d)
                return two_pt_frame unless two_pt_frame && two_pt_frame[NA_FRAME_KEY_XAXIS]

                zaxis      = two_pt_frame[NA_FRAME_KEY_ZAXIS]
                depth_v    = na_planar_vector(point_a, depth_point, zaxis)
                return two_pt_frame if depth_v.nil?

                xaxis = two_pt_frame[NA_FRAME_KEY_XAXIS]
                # Re-orthogonalise: yaxis = component of depth_v perpendicular to xaxis
                yaxis = na_orthogonalise_vector(depth_v, xaxis)
                return two_pt_frame if yaxis.nil?

                # Re-derive zaxis to keep the basis right-handed.
                zaxis_rh = (xaxis * yaxis)
                return two_pt_frame if zaxis_rh.length < NA_MIN_VECTOR_LENGTH
                zaxis_rh.normalize!

                {
                    NA_FRAME_KEY_ORIGIN => point_a,
                    NA_FRAME_KEY_XAXIS  => xaxis,
                    NA_FRAME_KEY_YAXIS  => yaxis,
                    NA_FRAME_KEY_ZAXIS  => zaxis_rh
                }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Insertion Transform Resolver (Engine-Facing Public API)
# -----------------------------------------------------------------------------

            # FUNCTION | Resolve Insertion Transform for a New ComponentInstance
            # ------------------------------------------------------------
            # Accepts a measurement frame Hash, a bare origin Point3d, or
            # nil. Always returns a Geom::Transformation suitable for
            # passing to `entities.add_instance(definition, transform)`.
            #
            # When only an origin is supplied the model's active drawing
            # axes provide the orientation. When nothing is supplied the
            # active drawing axes are returned (so even an axis-only
            # rotation is honoured for the placement-tool fallback).
            #
            # @param frame_or_origin [Hash, Geom::Point3d, nil]
            # @return [Geom::Transformation]
            def self.na_resolve_insertion_transform(frame_or_origin)
                return na_transform_from_frame(frame_or_origin) if na_frame_hash?(frame_or_origin)
                return na_transform_from_origin(frame_or_origin) if frame_or_origin.is_a?(Geom::Point3d)
                na_active_axes_transformation
            end
            # ---------------------------------------------------------------

            # FUNCTION | Extract the Origin Point3d from a Frame or Origin
            # ------------------------------------------------------------
            # Convenience used by engines that still pass an inches-origin
            # into legacy positioning code paths.
            def self.na_extract_origin(frame_or_origin)
                return frame_or_origin[NA_FRAME_KEY_ORIGIN] if na_frame_hash?(frame_or_origin)
                return frame_or_origin if frame_or_origin.is_a?(Geom::Point3d)
                nil
            end
            # ---------------------------------------------------------------

            # FUNCTION | Has Orientation Vectors? (Predicate)
            # ------------------------------------------------------------
            def self.na_frame_has_orientation?(frame)
                return false unless na_frame_hash?(frame)
                frame[NA_FRAME_KEY_XAXIS].is_a?(Geom::Vector3d) &&
                    frame[NA_FRAME_KEY_YAXIS].is_a?(Geom::Vector3d) &&
                    frame[NA_FRAME_KEY_ZAXIS].is_a?(Geom::Vector3d)
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Frame Hash Detection
            # ------------------------------------------------------------
            def self.na_frame_hash?(value)
                value.is_a?(Hash) && value.key?(NA_FRAME_KEY_ORIGIN)
            end
            private_class_method :na_frame_hash?

            # HELPER FUNCTION | Build Transform from Full Frame Hash
            # ------------------------------------------------------------
            def self.na_transform_from_frame(frame)
                origin = frame[NA_FRAME_KEY_ORIGIN]
                return na_active_axes_transformation unless origin.is_a?(Geom::Point3d)

                xaxis = frame[NA_FRAME_KEY_XAXIS]
                yaxis = frame[NA_FRAME_KEY_YAXIS]
                zaxis = frame[NA_FRAME_KEY_ZAXIS]

                if na_orthonormal_vectors?(xaxis, yaxis, zaxis)
                    return Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
                end

                na_transform_from_origin(origin)
            end
            private_class_method :na_transform_from_frame

            # HELPER FUNCTION | Build Transform from Origin + Active Axes
            # ------------------------------------------------------------
            # When only an origin is known, honour the user's drawing axes
            # for orientation. This is what a native SketchUp tool would do.
            def self.na_transform_from_origin(origin)
                axes = Sketchup.active_model && Sketchup.active_model.axes
                return Geom::Transformation.new(origin) unless axes

                Geom::Transformation.axes(origin, axes.xaxis, axes.yaxis, axes.zaxis)
            end
            private_class_method :na_transform_from_origin

            # HELPER FUNCTION | Return the Active Drawing Axes Transformation
            # ------------------------------------------------------------
            # Falls back to IDENTITY when no model is available
            # (defensive guard for tooling unit tests).
            def self.na_active_axes_transformation
                model = Sketchup.active_model
                return Geom::Transformation.new unless model
                model.axes.transformation
            end
            private_class_method :na_active_axes_transformation

            # HELPER FUNCTION | Drawing-Axes Up Vector
            # ------------------------------------------------------------
            def self.na_model_zaxis
                model = Sketchup.active_model
                return Z_AXIS unless model
                model.axes.zaxis
            end
            private_class_method :na_model_zaxis

            # HELPER FUNCTION | Project (Point B - Point A) onto the Ground Plane
            # ------------------------------------------------------------
            # The ground plane is defined by `up_vector`. Removes the
            # vertical component so the resulting horizontal direction
            # describes the wall in plan view. Returns nil when the
            # projection has no length (purely vertical delta).
            def self.na_planar_vector(point_a, point_b, up_vector)
                delta_vec = point_b - point_a
                return nil if delta_vec.length < NA_MIN_VECTOR_LENGTH

                up_component = up_vector.dot(delta_vec)
                horizontal   = Geom::Vector3d.new(
                    delta_vec.x - up_vector.x * up_component,
                    delta_vec.y - up_vector.y * up_component,
                    delta_vec.z - up_vector.z * up_component
                )
                return nil if horizontal.length < NA_MIN_VECTOR_LENGTH

                horizontal.normalize!
                horizontal
            end
            private_class_method :na_planar_vector

            # HELPER FUNCTION | Gram-Schmidt Orthogonalisation
            # ------------------------------------------------------------
            # Removes the component of `vec` that lies along `reference`
            # so the result is guaranteed perpendicular to `reference`.
            def self.na_orthogonalise_vector(vec, reference)
                projection_scalar = reference.dot(vec)
                ortho = Geom::Vector3d.new(
                    vec.x - reference.x * projection_scalar,
                    vec.y - reference.y * projection_scalar,
                    vec.z - reference.z * projection_scalar
                )
                return nil if ortho.length < NA_MIN_VECTOR_LENGTH
                ortho.normalize!
                ortho
            end
            private_class_method :na_orthogonalise_vector

            # HELPER FUNCTION | Validate Vector Trio is Orthonormal Enough
            # ------------------------------------------------------------
            def self.na_orthonormal_vectors?(xaxis, yaxis, zaxis)
                return false unless xaxis.is_a?(Geom::Vector3d)
                return false unless yaxis.is_a?(Geom::Vector3d)
                return false unless zaxis.is_a?(Geom::Vector3d)
                return false if xaxis.length < NA_MIN_VECTOR_LENGTH
                return false if yaxis.length < NA_MIN_VECTOR_LENGTH
                return false if zaxis.length < NA_MIN_VECTOR_LENGTH
                true
            end
            private_class_method :na_orthonormal_vectors?

# endregion -------------------------------------------------------------------

        end
    end
end
