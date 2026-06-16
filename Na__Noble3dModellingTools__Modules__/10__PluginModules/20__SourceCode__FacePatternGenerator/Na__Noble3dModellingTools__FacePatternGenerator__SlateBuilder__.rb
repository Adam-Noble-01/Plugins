# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - SLATE BUILDER
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__SlateBuilder

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
            'slate_460x220_80' => [460.0, 220.0, 80.0],
            'slate_400x250_75' => [400.0, 250.0, 75.0]
        }.freeze

        def self.Na__FacePatternGenerator__ApplySlatePattern(payload_hash)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            face = Na__FacePatternGenerator__FaceData.Na__FacePatternGenerator__GetSingleSelectedFace(model.selection)
            return na_result(false, 'Select the target face before applying the slate pattern.') unless face

            options = na_read_options(payload_hash)
            visible_gauge_mm = (options[:slate_length_mm] - options[:headlap_mm]) / 2.0
            return na_result(false, 'Headlap must be smaller than slate length.') if visible_gauge_mm <= 0

            model.start_operation(NA_OPERATION_NAME, true)
            begin
                definition = na_build_slate_definition(model, options[:slate_width_mm], visible_gauge_mm)
                group = model.active_entities.add_group
                group.name = 'Na Face Pattern - Slate'

                count = na_populate_face(
                    group.entities,
                    definition,
                    face,
                    options[:slate_width_mm],
                    visible_gauge_mm,
                    options[:side_gap_mm],
                    options[:lift_mm],
                    options[:stagger]
                )

                if count.zero?
                    model.abort_operation
                    return na_result(false, 'No slate instances fit inside the selected face.')
                end

                model.commit_operation
                na_result(true, "Slate pattern applied with #{count} instance(s).")
            rescue => error
                model.abort_operation
                na_result(false, "Slate build failed: #{error.class}: #{error.message}")
            end
        end

        def self.na_read_options(payload_hash)
            preset_key = payload_hash.fetch('preset_key', '').to_s
            preset = PRESET_TABLE[preset_key]

            slate_length_mm = payload_hash.fetch('slate_length_mm', preset ? preset[0] : 500.0).to_f
            slate_width_mm = payload_hash.fetch('slate_width_mm', preset ? preset[1] : 250.0).to_f
            headlap_mm = payload_hash.fetch('headlap_mm', preset ? preset[2] : 100.0).to_f
            side_gap_mm = payload_hash.fetch('side_gap_mm', 0.0).to_f
            lift_mm = payload_hash.fetch('lift_mm', 0.0).to_f
            stagger = !!payload_hash.fetch('stagger', true)

            {
                slate_length_mm: slate_length_mm,
                slate_width_mm: slate_width_mm,
                headlap_mm: headlap_mm,
                side_gap_mm: side_gap_mm,
                lift_mm: lift_mm,
                stagger: stagger
            }
        end
        private_class_method :na_read_options

        def self.na_build_slate_definition(model, slate_width_mm, visible_gauge_mm)
            width_text = slate_width_mm.round(1)
            gauge_text = visible_gauge_mm.round(1)
            definition_name = "Na__FacePattern__Slate__#{width_text}x#{gauge_text}"

            existing = model.definitions[definition_name]
            return existing if existing

            definition = model.definitions.add(definition_name)
            entities = definition.entities

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

        def self.na_populate_face(entities, definition, face, slate_width_mm, visible_gauge_mm, side_gap_mm, lift_mm, stagger)
            basis = na_build_basis(face)
            return 0 unless basis

            local_vertices = face.outer_loop.vertices.map { |vertex| na_to_local_2d(vertex.position, basis) }
            min_x, max_x = local_vertices.map(&:first).minmax
            min_y, max_y = local_vertices.map(&:last).minmax

            x_step_mm = slate_width_mm + side_gap_mm
            y_step_mm = visible_gauge_mm
            row_index = 0
            y_mm = min_y - y_step_mm
            count = 0

            while y_mm <= max_y + y_step_mm
                row_offset_mm = stagger && row_index.odd? ? -(x_step_mm / 2.0) : 0.0
                x_mm = min_x - x_step_mm + row_offset_mm

                while x_mm <= max_x + x_step_mm
                    corners = [
                        [x_mm, y_mm],
                        [x_mm + slate_width_mm, y_mm],
                        [x_mm + slate_width_mm, y_mm + visible_gauge_mm],
                        [x_mm, y_mm + visible_gauge_mm]
                    ]

                    if na_corners_fit_face?(face, corners, basis)
                        placement_origin = basis[:origin]
                            .offset(basis[:x_axis], x_mm.mm)
                            .offset(basis[:y_axis], y_mm.mm)
                            .offset(basis[:z_axis], lift_mm.mm)
                        transform = Geom::Transformation.axes(placement_origin, basis[:x_axis], basis[:y_axis], basis[:z_axis])
                        entities.add_instance(definition, transform)
                        count += 1
                    end

                    x_mm += x_step_mm
                end

                y_mm += y_step_mm
                row_index += 1
            end

            count
        end
        private_class_method :na_populate_face

        def self.na_build_basis(face)
            normal = face.normal
            return nil if normal.length < 0.001

            normal = Geom::Vector3d.new(normal.x, normal.y, normal.z)
            normal.normalize!
            normal.reverse! if normal.z < 0

            world_up = Geom::Vector3d.new(0, 0, 1)
            x_axis = world_up.cross(normal)
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

        def self.na_to_local_2d(point, basis)
            vector = point - basis[:origin]
            [
                vector.dot(basis[:x_axis]).to_f / 1.mm,
                vector.dot(basis[:y_axis]).to_f / 1.mm
            ]
        end
        private_class_method :na_to_local_2d

        def self.na_corners_fit_face?(face, local_corners, basis)
            local_corners.all? do |xy|
                world_point = basis[:origin]
                    .offset(basis[:x_axis], xy[0].mm)
                    .offset(basis[:y_axis], xy[1].mm)
                SAFE_POINT_CLASSES.include?(face.classify_point(world_point))
            end
        end
        private_class_method :na_corners_fit_face?

        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
    end
end

# =============================================================================
# END OF FILE
# =============================================================================
