# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - FACE DATA
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__FacePatternGenerator__FaceData__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__FacePatternGenerator__FaceData
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Validate single-face selection, derive an orthonormal local basis,
#              project the face boundary to 2D millimetres, and build the JS payload.
# CREATED    : 2026
#
# DESCRIPTION:
# - v1 constraint: exactly one face must be selected in the active context.
# - Pitched surfaces: Y axis = up-slope (world-up minus projection onto normal).
# - Near-horizontal surfaces: X axis = longest outer edge (floors / slabs).
# - Normal is flipped to the positive-Z side so lift_mm pushes geometry outward.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__FaceData

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        SAFE_POINT_CLASSES = [
            Sketchup::Face::PointInside,
            Sketchup::Face::PointOnFace,
            Sketchup::Face::PointOnEdge,
            Sketchup::Face::PointOnVertex
        ].freeze

        WORLD_UP = Geom::Vector3d.new(0, 0, 1).freeze

        NA_AXIS_EPSILON    = 1.0e-6                                                    # <-- Below this a direction vector is noise, not a direction
        NA_UP_SLOPE_MIN    = 0.001                                                     # <-- Original branch point between pitched and horizontal
        NA_ORTHO_TOLERANCE = 1.0e-4                                                    # <-- Slack on the orthonormality assertion
        NA_MIN_EXTENT_MM   = 0.001                                                     # <-- A face projecting smaller than this collapsed

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Face Payload from the Current Selection
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__BuildSelectionPayload
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            face = Na__FacePatternGenerator__GetSingleSelectedFace(model.selection)
            return na_result(false, 'Select one face only before launching Face Pattern Generator.') unless face

            payload = na_build_face_payload(face)
            return na_result(false, 'Unable to derive a local basis for the selected face.') unless payload

            bounds = payload[:bounds]
            if bounds[:width].abs < NA_MIN_EXTENT_MM && bounds[:height].abs < NA_MIN_EXTENT_MM
                return na_result(false, 'The selected face projected to a zero-size outline - it may be degenerate, or nested inside a group scaled to zero on one axis.')
            end

            na_result(true, 'Face captured for pattern generation.', payload: payload)
        rescue => error
            na_result(false, "Face read failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Selection
# -----------------------------------------------------------------------------

        # FUNCTION | Return the Sole Selected Face, or nil
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__GetSingleSelectedFace(selection)
            faces = selection.grep(Sketchup::Face).select { |face| face.valid? && !face.deleted? }
            return nil unless faces.length == 1

            faces.first
        end
        # ------------------------------------------------------------

        # FUNCTION | Classify Whether a World Point Lies on or Inside the Face
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__PointIsInsideFace(face, point)
            SAFE_POINT_CLASSES.include?(face.classify_point(point))
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Full Face Payload Hash for the Dialog
        # ------------------------------------------------------------
        def self.na_build_face_payload(face)
            basis = na_build_basis(face)
            return nil unless basis

            outer  = na_project_loop_vertices(face.outer_loop, basis)
            holes  = face.loops.reject(&:outer?).map { |loop| na_project_loop_vertices(loop, basis) }
            bounds = na_build_bounds(outer)

            {
                face_persistent_id: face.respond_to?(:persistent_id) ? face.persistent_id : nil,
                outer: outer,
                holes: holes,
                bounds: bounds,
                basis: {
                    origin: na_point_to_array(basis[:origin]),
                    x_axis: na_vector_to_array(basis[:x_axis]),
                    y_axis: na_vector_to_array(basis[:y_axis]),
                    z_axis: na_vector_to_array(basis[:z_axis])
                }
            }
        end
        private_class_method :na_build_face_payload
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Local Basis and Projection
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Derive Orthonormal Axes from the Face Normal
        # ------------------------------------------------------------
        # Every axis goes through na_unit_vector, which returns nil rather than
        # leaving a degenerate vector in place. A silently collapsed axis used to
        # project every vertex onto [0, 0], which reads in the dialog as a face
        # of 0.0mm x 0.0mm rather than as an error.
        def self.na_build_basis(face)
            normal = na_unit_vector(face.normal)
            return nil unless normal

            normal.reverse! if normal.z < 0                                            # <-- Flip to positive-Z side

            axes = na_axes_for_normal(face, normal)
            return nil unless axes
            return nil unless na_axes_are_orthonormal?(axes[0], axes[1], normal)

            {
                origin: face.outer_loop.vertices.first.position,
                x_axis: axes[0],
                y_axis: axes[1],
                z_axis: normal
            }
        end
        private_class_method :na_build_basis
        # ------------------------------------------------------------

        # HELPER FUNCTION | Choose the In-Plane X and Y Axes for a Face Normal
        # ------------------------------------------------------------
        # Pitched surfaces run Y up-slope. Near-horizontal ones have no usable
        # up-slope, so X seeds from the longest outer edge and falls back to the
        # world axes; the seeds are tried in turn so one bad candidate cannot
        # collapse the basis. NA_UP_SLOPE_MIN keeps the original branch point, so
        # a slab with only a construction tolerance of fall still aligns to its
        # longest edge rather than to a direction made of floating point noise.
        def self.na_axes_for_normal(face, normal)
            up_slope = na_up_slope_vector(normal)
            if na_vector_length(up_slope) >= NA_UP_SLOPE_MIN
                y_axis = na_unit_vector(up_slope)
                x_axis = y_axis ? na_unit_vector(y_axis.cross(normal)) : nil
                return [x_axis, y_axis] if x_axis && y_axis
            end

            na_horizontal_axis_seeds(face).each do |seed|
                x_axis = na_unit_vector(seed)
                next unless x_axis

                y_axis = na_unit_vector(normal.cross(x_axis))
                next unless y_axis

                x_axis = na_unit_vector(y_axis.cross(normal))                          # <-- Re-square X against the chosen Y
                next unless x_axis

                return [x_axis, y_axis]
            end

            nil
        end
        private_class_method :na_axes_for_normal
        # ------------------------------------------------------------

        # HELPER FUNCTION | World Up with the Normal Component Removed
        # ------------------------------------------------------------
        def self.na_up_slope_vector(normal)
            dot = WORLD_UP.dot(normal)
            Geom::Vector3d.new(
                WORLD_UP.x - (normal.x * dot),
                WORLD_UP.y - (normal.y * dot),
                WORLD_UP.z - (normal.z * dot)
            )
        end
        private_class_method :na_up_slope_vector
        # ------------------------------------------------------------

        # HELPER FUNCTION | Candidate In-Plane Directions for a Horizontal Face
        # ------------------------------------------------------------
        def self.na_horizontal_axis_seeds(face)
            [
                na_longest_outer_edge_vector(face),                                    # <-- Align the pattern to the slab
                Geom::Vector3d.new(1, 0, 0),
                Geom::Vector3d.new(0, 1, 0)
            ].compact
        end
        private_class_method :na_horizontal_axis_seeds
        # ------------------------------------------------------------

        # HELPER FUNCTION | Plain Float Length of a Vector
        # ------------------------------------------------------------
        # Geom::Vector3d#length returns a Length in inches; this keeps the axis
        # arithmetic in plain floats where the units are meaningless anyway.
        def self.na_vector_length(vector)
            return 0.0 unless vector

            Math.sqrt((vector.x * vector.x) + (vector.y * vector.y) + (vector.z * vector.z))
        end
        private_class_method :na_vector_length
        # ------------------------------------------------------------

        # HELPER FUNCTION | Normalise a Vector, or nil When It Carries No Direction
        # ------------------------------------------------------------
        # Geom::Vector3d#normalize! leaves a zero-length vector unchanged instead
        # of raising, so a bare normalize! can hand back a zero axis.
        def self.na_unit_vector(vector)
            return nil unless vector

            length = na_vector_length(vector)
            return nil unless length.finite? && length > NA_AXIS_EPSILON

            Geom::Vector3d.new(vector.x / length, vector.y / length, vector.z / length)
        end
        private_class_method :na_unit_vector
        # ------------------------------------------------------------

        # HELPER FUNCTION | Assert the Three Axes Really Form a Right-Handed Frame
        # ------------------------------------------------------------
        def self.na_axes_are_orthonormal?(x_axis, y_axis, z_axis)
            return false unless x_axis && y_axis && z_axis
            return false if x_axis.dot(y_axis).abs > NA_ORTHO_TOLERANCE
            return false if x_axis.dot(z_axis).abs > NA_ORTHO_TOLERANCE
            return false if y_axis.dot(z_axis).abs > NA_ORTHO_TOLERANCE

            (x_axis.cross(y_axis).dot(z_axis) - 1.0).abs <= NA_ORTHO_TOLERANCE
        end
        private_class_method :na_axes_are_orthonormal?
        # ------------------------------------------------------------

        # HELPER FUNCTION | Project a Face Loop to Local 2D Millimetre Coordinates
        # ------------------------------------------------------------
        def self.na_project_loop_vertices(loop, basis)
            loop.vertices.map do |vertex|
                na_point_to_local_mm(vertex.position, basis)
            end
        end
        private_class_method :na_project_loop_vertices
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert a World Point to Local [x_mm, y_mm]
        # ------------------------------------------------------------
        def self.na_point_to_local_mm(point, basis)
            vector = point - basis[:origin]
            [
                na_inches_to_mm(vector.dot(basis[:x_axis])),
                na_inches_to_mm(vector.dot(basis[:y_axis]))
            ]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert Local [x_mm, y_mm] Back to a World Point
        # ------------------------------------------------------------
        def self.na_point_from_local_mm(x_mm, y_mm, basis)
            basis[:origin]
                .offset(basis[:x_axis], x_mm.to_f.mm)
                .offset(basis[:y_axis], y_mm.to_f.mm)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Bounds and Geometry Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Compute Axis-Aligned Bounds from Projected Points
        # ------------------------------------------------------------
        def self.na_build_bounds(points)
            xs = points.map(&:first)
            ys = points.map(&:last)
            min_x, max_x = xs.minmax
            min_y, max_y = ys.minmax
            {
                min_x: min_x,
                min_y: min_y,
                max_x: max_x,
                max_y: max_y,
                width: max_x - min_x,
                height: max_y - min_y
            }
        end
        private_class_method :na_build_bounds
        # ------------------------------------------------------------

        # HELPER FUNCTION | Longest Outer-Loop Edge as the Horizontal X Axis
        # ------------------------------------------------------------
        def self.na_longest_outer_edge_vector(face)
            edge = face.outer_loop.edges.max_by(&:length)
            return nil unless edge

            edge.end.position - edge.start.position
        end
        private_class_method :na_longest_outer_edge_vector
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert SketchUp Inches to Millimetres
        # ------------------------------------------------------------
        def self.na_inches_to_mm(value_in_inches)
            value_in_inches.to_f / 1.mm
        end
        private_class_method :na_inches_to_mm
        # ------------------------------------------------------------

        # HELPER FUNCTION | Serialize a Point3d to a JSON-Friendly Array
        # ------------------------------------------------------------
        def self.na_point_to_array(point)
            [point.x.to_f, point.y.to_f, point.z.to_f]
        end
        private_class_method :na_point_to_array
        # ------------------------------------------------------------

        # HELPER FUNCTION | Serialize a Vector3d to a JSON-Friendly Array
        # ------------------------------------------------------------
        def self.na_vector_to_array(vector)
            [vector.x.to_f, vector.y.to_f, vector.z.to_f]
        end
        private_class_method :na_vector_to_array
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FacePatternGenerator__FaceData
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
