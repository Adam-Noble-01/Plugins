# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - FACE DATA
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__FaceData

        SAFE_POINT_CLASSES = [
            Sketchup::Face::PointInside,
            Sketchup::Face::PointOnFace,
            Sketchup::Face::PointOnEdge,
            Sketchup::Face::PointOnVertex
        ].freeze

        WORLD_UP = Geom::Vector3d.new(0, 0, 1).freeze

        def self.Na__FacePatternGenerator__BuildSelectionPayload
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            face = Na__FacePatternGenerator__GetSingleSelectedFace(model.selection)
            return na_result(false, 'Select one face only before launching Face Pattern Generator.') unless face

            payload = na_build_face_payload(face)
            return na_result(false, 'Unable to derive a local basis for the selected face.') unless payload

            na_result(true, 'Face captured for pattern generation.', payload: payload)
        rescue => error
            na_result(false, "Face read failed: #{error.class}: #{error.message}")
        end

        def self.Na__FacePatternGenerator__GetSingleSelectedFace(selection)
            faces = selection.grep(Sketchup::Face).select { |face| face.valid? && !face.deleted? }
            return nil unless faces.length == 1

            faces.first
        end

        def self.Na__FacePatternGenerator__PointIsInsideFace(face, point)
            SAFE_POINT_CLASSES.include?(face.classify_point(point))
        end

        def self.na_build_face_payload(face)
            basis = na_build_basis(face)
            return nil unless basis

            outer = na_project_loop_vertices(face.outer_loop, basis)
            holes = face.loops.reject(&:outer?).map { |loop| na_project_loop_vertices(loop, basis) }
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

        def self.na_build_basis(face)
            normal = face.normal
            return nil if normal.length < 0.001

            normal = Geom::Vector3d.new(normal.x, normal.y, normal.z)
            normal.normalize!
            normal.reverse! if normal.z < 0

            dot = WORLD_UP.dot(normal)
            projection = Geom::Vector3d.new(normal.x * dot, normal.y * dot, normal.z * dot)
            up_slope = Geom::Vector3d.new(
                WORLD_UP.x - projection.x,
                WORLD_UP.y - projection.y,
                WORLD_UP.z - projection.z
            )

            if up_slope.length < 0.001
                x_axis = na_longest_outer_edge_vector(face)
                return nil unless x_axis && x_axis.length >= 0.001

                x_axis.normalize!
                y_axis = normal.cross(x_axis)
                y_axis.normalize!
            else
                up_slope.normalize!
                y_axis = up_slope
                x_axis = y_axis.cross(normal)
                x_axis.normalize!
            end

            {
                origin: face.outer_loop.vertices.first.position,
                x_axis: x_axis,
                y_axis: y_axis,
                z_axis: normal
            }
        end
        private_class_method :na_build_basis

        def self.na_project_loop_vertices(loop, basis)
            loop.vertices.map do |vertex|
                na_point_to_local_mm(vertex.position, basis)
            end
        end
        private_class_method :na_project_loop_vertices

        def self.na_point_to_local_mm(point, basis)
            vector = point - basis[:origin]
            [
                na_inches_to_mm(vector.dot(basis[:x_axis])),
                na_inches_to_mm(vector.dot(basis[:y_axis]))
            ]
        end

        def self.na_point_from_local_mm(x_mm, y_mm, basis)
            basis[:origin]
                .offset(basis[:x_axis], x_mm.to_f.mm)
                .offset(basis[:y_axis], y_mm.to_f.mm)
        end

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

        def self.na_longest_outer_edge_vector(face)
            edge = face.outer_loop.edges.max_by(&:length)
            return nil unless edge

            edge.end.position - edge.start.position
        end
        private_class_method :na_longest_outer_edge_vector

        def self.na_inches_to_mm(value_in_inches)
            value_in_inches.to_f / 1.mm
        end
        private_class_method :na_inches_to_mm

        def self.na_point_to_array(point)
            [point.x.to_f, point.y.to_f, point.z.to_f]
        end
        private_class_method :na_point_to_array

        def self.na_vector_to_array(vector)
            [vector.x.to_f, vector.y.to_f, vector.z.to_f]
        end
        private_class_method :na_vector_to_array

        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
