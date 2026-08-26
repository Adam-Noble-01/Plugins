# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - SLATE BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__FacePatternGenerator__SlateBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__FacePatternGenerator__SlateBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Apply a slate roof pattern by placing component instances on the
#              selected face using proven course-tiling logic from the prototype.
# CREATED    : 2026
#
# DESCRIPTION:
# - Slate Apply ignores dialog polylines and regenerates from the live selection.
# - Uses face.classify_point for corner-inside tests (handles edge coincidence).
# - Visible gauge = (slate_length - headlap) / 2 per UK roofing convention.
# - Half-bond stagger offsets alternate courses by half a slate width + gap.
# - Trim to Face Edges (default on) runs the courses past the face perimeter and
#   cuts the overshoot back with RectClip: whole slates stay component instances,
#   boundary slates are drawn as trimmed loose edges in the same group.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__SlateBuilder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'Face Pattern Generator - Apply Slate'.freeze

        SAFE_POINT_CLASSES = [
            Sketchup::Face::PointInside,
            Sketchup::Face::PointOnFace,
            Sketchup::Face::PointOnEdge,
            Sketchup::Face::PointOnVertex
        ].freeze

        PRESET_TABLE = {
            'slate_600x300_100' => [600.0, 300.0, 100.0],
            'slate_500x300_100' => [500.0, 300.0, 100.0],
            'slate_500x250_100' => [500.0, 250.0, 100.0],
            'slate_460x220_80'  => [460.0, 220.0, 80.0],
            'slate_400x250_75'  => [400.0, 250.0, 75.0]
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Apply Slate Component Instances to the Selected Face
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__ApplySlatePattern(payload_hash)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            face = Na__FacePatternGenerator__FaceData.Na__FacePatternGenerator__GetSingleSelectedFace(model.selection)
            return na_result(false, 'Select the target face before applying the slate pattern.') unless face

            options          = na_read_options(payload_hash)
            visible_gauge_mm = (options[:slate_length_mm] - options[:headlap_mm]) / 2.0
            return na_result(false, 'Headlap must be smaller than slate length.') if visible_gauge_mm <= 0
            return na_result(false, 'Slate width must be greater than zero.') if options[:slate_width_mm] <= 0

            model.start_operation(NA_OPERATION_NAME, true)
            begin
                definition = na_build_slate_definition(model, options[:slate_width_mm], visible_gauge_mm)
                group      = model.active_entities.add_group
                group.name   = 'Na Face Pattern - Slate'

                tally = na_populate_face(group.entities, definition, face, options.merge(visible_gauge_mm: visible_gauge_mm))

                if tally[:total].zero?
                    model.abort_operation
                    return na_result(false, 'No slate instances fit inside the selected face.')
                end

                model.commit_operation
                na_result(true, na_tally_message(tally, options[:trim_to_face]))
            rescue => error
                model.abort_operation
                na_result(false, "Slate build failed: #{error.class}: #{error.message}")
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Options and Definition
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Parse Slate Options from the Apply Payload
        # ------------------------------------------------------------
        def self.na_read_options(payload_hash)
            preset_key = payload_hash.fetch('preset_key', '').to_s
            preset     = PRESET_TABLE[preset_key]

            {
                slate_length_mm: payload_hash.fetch('slate_length_mm', preset ? preset[0] : 500.0).to_f,
                slate_width_mm:  payload_hash.fetch('slate_width_mm', preset ? preset[1] : 250.0).to_f,
                headlap_mm:      payload_hash.fetch('headlap_mm', preset ? preset[2] : 100.0).to_f,
                side_gap_mm:     [payload_hash.fetch('side_gap_mm', 0.0).to_f, 0.0].max,
                lift_mm:         payload_hash.fetch('lift_mm', 0.0).to_f,
                stagger:         na_flag(payload_hash, 'stagger', true),
                trim_to_face:    na_flag(payload_hash, 'trim_to_face', true),
                rotation_steps:  payload_hash.fetch('rotation_steps', 0).to_i % 4
            }
        end
        private_class_method :na_read_options
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read a Boolean Payload Flag with a Default
        # ------------------------------------------------------------
        def self.na_flag(payload_hash, key, default_value)
            return default_value unless payload_hash.key?(key)

            value = payload_hash[key]
            return default_value if value.nil?
            return false if value == false || value.to_s.strip.downcase == 'false'

            true
        end
        private_class_method :na_flag
        # ------------------------------------------------------------

        # HELPER FUNCTION | Get or Create the Slate Rectangle Component Definition
        # ------------------------------------------------------------
        def self.na_build_slate_definition(model, slate_width_mm, visible_gauge_mm)
            width_text      = slate_width_mm.round(1)
            gauge_text      = visible_gauge_mm.round(1)
            definition_name = "Na__FacePattern__Slate__#{width_text}x#{gauge_text}"

            existing = model.definitions[definition_name]
            return existing if existing

            definition = model.definitions.add(definition_name)
            entities   = definition.entities

            p0 = Geom::Point3d.new(0, 0, 0)
            p1 = Geom::Point3d.new(slate_width_mm.mm, 0, 0)
            p2 = Geom::Point3d.new(slate_width_mm.mm, visible_gauge_mm.mm, 0)
            p3 = Geom::Point3d.new(0, visible_gauge_mm.mm, 0)

            entities.add_line(p0, p1)
            entities.add_line(p1, p2)
            entities.add_line(p2, p3)
            entities.add_line(p3, p0)

            definition
        end
        private_class_method :na_build_slate_definition
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Population
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Tile Slate Instances Across the Face in Courses
        # ------------------------------------------------------------
        # Returns { instances:, trimmed:, total: }. Whole slates are placed as
        # component instances; when trimming is on, slates crossing the face
        # perimeter are drawn as trimmed loose edges instead of being skipped.
        def self.na_populate_face(entities, definition, face, options)
            basis = na_build_basis(face)
            return { instances: 0, trimmed: 0, total: 0 } unless basis

            na_rotate_basis_clockwise!(basis, options[:rotation_steps])

            slate_width_mm   = options[:slate_width_mm]
            visible_gauge_mm = options[:visible_gauge_mm]
            lift_mm          = options[:lift_mm]
            trim_to_face     = options[:trim_to_face]

            outer_ring, hole_rings = na_face_local_rings(face, basis)
            min_x, max_x = outer_ring.map(&:first).minmax
            min_y, max_y = outer_ring.map(&:last).minmax

            x_step_mm = slate_width_mm + options[:side_gap_mm]
            y_step_mm = visible_gauge_mm
            row_index = 0
            y_mm      = min_y - y_step_mm
            instances = 0
            trimmed   = 0

            while y_mm <= max_y + y_step_mm
                row_offset_mm = options[:stagger] && row_index.odd? ? -(x_step_mm / 2.0) : 0.0
                x_mm = min_x - x_step_mm + row_offset_mm

                while x_mm <= max_x + x_step_mm
                    corners = [
                        [x_mm, y_mm],
                        [x_mm + slate_width_mm, y_mm],
                        [x_mm + slate_width_mm, y_mm + visible_gauge_mm],
                        [x_mm, y_mm + visible_gauge_mm]
                    ]

                    if na_corners_fit_face?(face, corners, basis)
                        na_place_instance(entities, definition, basis, x_mm, y_mm, lift_mm)
                        instances += 1
                    elsif trim_to_face
                        clip = Na__FacePatternGenerator__RectClip.Na__FacePatternGenerator__ClipUnitRect(
                            x_mm, y_mm, slate_width_mm, visible_gauge_mm, outer_ring, hole_rings
                        )
                        if clip[:full]
                            na_place_instance(entities, definition, basis, x_mm, y_mm, lift_mm)
                            instances += 1
                        elsif !clip[:rings].empty?
                            clip[:rings].each { |ring| na_draw_ring(entities, ring, basis, lift_mm) }
                            trimmed += 1
                        end
                    end

                    x_mm += x_step_mm
                end

                y_mm += y_step_mm
                row_index += 1
            end

            { instances: instances, trimmed: trimmed, total: instances + trimmed }
        end
        private_class_method :na_populate_face
        # ------------------------------------------------------------

        # HELPER FUNCTION | Place One Whole Slate Component Instance
        # ------------------------------------------------------------
        def self.na_place_instance(entities, definition, basis, x_mm, y_mm, lift_mm)
            placement_origin = basis[:origin]
                .offset(basis[:x_axis], x_mm.mm)
                .offset(basis[:y_axis], y_mm.mm)
                .offset(basis[:z_axis], lift_mm.mm)
            transform = Geom::Transformation.axes(placement_origin, basis[:x_axis], basis[:y_axis], basis[:z_axis])
            entities.add_instance(definition, transform)
        end
        private_class_method :na_place_instance
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Basis and Point Tests
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Derive Placement Axes from the Face Normal
        # ------------------------------------------------------------
        def self.na_build_basis(face)
            normal = face.normal
            return nil if normal.length < 0.001

            normal = Geom::Vector3d.new(normal.x, normal.y, normal.z)
            normal.normalize!
            normal.reverse! if normal.z < 0

            world_up = Geom::Vector3d.new(0, 0, 1)
            x_axis   = world_up.cross(normal)
            if x_axis.length < 0.001
                edge = face.outer_loop.edges.max_by(&:length)
                return nil unless edge

                x_axis = edge.end.position - edge.start.position
            end
            x_axis.normalize!

            y_axis = normal.cross(x_axis)
            y_axis.normalize!

            {
                origin: face.outer_loop.vertices.first.position,
                x_axis: x_axis,
                y_axis: y_axis,
                z_axis: normal
            }
        end
        private_class_method :na_build_basis
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rotate the In-Plane Basis 90 Degrees Clockwise N Times
        # ------------------------------------------------------------
        # Matches the dialog's canvas rotation of points (x, y) -> (y, -x):
        # each step sets x' = y, y' = -x, keeping the frame right-handed.
        def self.na_rotate_basis_clockwise!(basis, rotation_steps)
            (rotation_steps.to_i % 4).times do
                basis[:x_axis], basis[:y_axis] = basis[:y_axis], basis[:x_axis].reverse
            end
            basis
        end
        private_class_method :na_rotate_basis_clockwise!
        # ------------------------------------------------------------

        # HELPER FUNCTION | Project a World Point to Local 2D Millimetres
        # ------------------------------------------------------------
        def self.na_to_local_2d(point, basis)
            vector = point - basis[:origin]
            [
                vector.dot(basis[:x_axis]).to_f / 1.mm,
                vector.dot(basis[:y_axis]).to_f / 1.mm
            ]
        end
        private_class_method :na_to_local_2d
        # ------------------------------------------------------------

        # HELPER FUNCTION | Project the Face Loops to Local 2D Millimetre Rings
        # ------------------------------------------------------------
        def self.na_face_local_rings(face, basis)
            outer_ring = face.outer_loop.vertices.map { |vertex| na_to_local_2d(vertex.position, basis) }
            hole_rings = face.loops.reject(&:outer?).map do |loop|
                loop.vertices.map { |vertex| na_to_local_2d(vertex.position, basis) }
            end
            [outer_ring, hole_rings]
        end
        private_class_method :na_face_local_rings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Draw One Trimmed Ring as Closed Loose Edges
        # ------------------------------------------------------------
        def self.na_draw_ring(entities, ring, basis, lift_mm)
            points = ring.map do |xy|
                basis[:origin]
                    .offset(basis[:x_axis], xy[0].mm)
                    .offset(basis[:y_axis], xy[1].mm)
                    .offset(basis[:z_axis], lift_mm.mm)
            end
            return if points.length < 3

            closed = points + [points.first]
            closed.each_cons(2) do |start_point, end_point|
                next if start_point.distance(end_point) < 1e-6

                entities.add_line(start_point, end_point)
            end
        rescue ArgumentError, TypeError, RuntimeError
            nil                                                                  # <-- Skip a degenerate sliver, keep tiling
        end
        private_class_method :na_draw_ring
        # ------------------------------------------------------------

        # HELPER FUNCTION | Test Whether All Slate Corners Lie on or Inside the Face
        # ------------------------------------------------------------
        def self.na_corners_fit_face?(face, local_corners, basis)
            local_corners.all? do |xy|
                world_point = basis[:origin]
                    .offset(basis[:x_axis], xy[0].mm)
                    .offset(basis[:y_axis], xy[1].mm)
                SAFE_POINT_CLASSES.include?(face.classify_point(world_point))
            end
        end
        private_class_method :na_corners_fit_face?
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Describe the Placed and Trimmed Slate Counts
        # ------------------------------------------------------------
        def self.na_tally_message(tally, trim_to_face)
            return "Slate pattern applied with #{tally[:instances]} instance(s) - whole slates only." unless trim_to_face
            return "Slate pattern applied with #{tally[:instances]} instance(s)." if tally[:trimmed].zero?

            "Slate pattern applied with #{tally[:instances]} instance(s) and #{tally[:trimmed]} trimmed slate(s)."
        end
        private_class_method :na_tally_message
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FacePatternGenerator__SlateBuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
