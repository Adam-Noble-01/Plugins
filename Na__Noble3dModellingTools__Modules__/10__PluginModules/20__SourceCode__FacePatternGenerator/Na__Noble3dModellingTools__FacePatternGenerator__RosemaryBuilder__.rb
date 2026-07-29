# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - ROSEMARY BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__FacePatternGenerator__RosemaryBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__FacePatternGenerator__RosemaryBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Apply a British plain tile (Rosemary style) roof pattern by
#              placing component instances on the selected face using the same
#              proven course-tiling logic as the slate builder.
# CREATED    : 2026
#
# DESCRIPTION:
# - Rosemary Apply ignores dialog polylines and regenerates from the live selection.
# - Uses face.classify_point for corner-inside tests (handles edge coincidence).
# - Visible gauge = (tile_length - headlap) / 2 per UK double-lap plain tiling.
# - Standard plain tile is 265x165mm with 65mm minimum headlap (100mm max gauge).
# - Half-bond stagger offsets alternate courses by half a tile width + shunt gap.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__RosemaryBuilder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'Face Pattern Generator - Apply Rosemary Tiles'.freeze

        SAFE_POINT_CLASSES = [
            Sketchup::Face::PointInside,
            Sketchup::Face::PointOnFace,
            Sketchup::Face::PointOnEdge,
            Sketchup::Face::PointOnVertex
        ].freeze

        PRESET_TABLE = {
            'rosemary_265x165_65' => [265.0, 165.0, 65.0],
            'rosemary_265x165_75' => [265.0, 165.0, 75.0],
            'rosemary_265x165_85' => [265.0, 165.0, 85.0]
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

        # FUNCTION | Apply Rosemary Tile Component Instances to the Selected Face
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__ApplyRosemaryPattern(payload_hash)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            face = Na__FacePatternGenerator__FaceData.Na__FacePatternGenerator__GetSingleSelectedFace(model.selection)
            return na_result(false, 'Select the target face before applying the rosemary tile pattern.') unless face

            options          = na_read_options(payload_hash)
            visible_gauge_mm = (options[:tile_length_mm] - options[:headlap_mm]) / 2.0
            return na_result(false, 'Headlap must be smaller than tile length.') if visible_gauge_mm <= 0
            return na_result(false, 'Tile width must be greater than zero.') if options[:tile_width_mm] <= 0

            model.start_operation(NA_OPERATION_NAME, true)
            begin
                definition = na_build_tile_definition(model, options[:tile_width_mm], visible_gauge_mm, options[:base_thickness_mm])
                group      = model.active_entities.add_group
                group.name   = 'Na Face Pattern - Rosemary'

                count = na_populate_face(
                    group.entities,
                    definition,
                    face,
                    options[:tile_width_mm],
                    visible_gauge_mm,
                    options[:side_gap_mm],
                    options[:lift_mm],
                    options[:stagger],
                    options[:rotation_steps]
                )

                if count.zero?
                    model.abort_operation
                    return na_result(false, 'No rosemary tile instances fit inside the selected face.')
                end

                model.commit_operation
                na_result(true, "Rosemary tile pattern applied with #{count} instance(s).")
            rescue => error
                model.abort_operation
                na_result(false, "Rosemary tile build failed: #{error.class}: #{error.message}")
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Options and Definition
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Parse Rosemary Tile Options from the Apply Payload
        # ------------------------------------------------------------
        def self.na_read_options(payload_hash)
            preset_key = payload_hash.fetch('preset_key', '').to_s
            preset     = PRESET_TABLE[preset_key]

            {
                tile_length_mm:    payload_hash.fetch('tile_length_mm', preset ? preset[0] : 265.0).to_f,
                tile_width_mm:     payload_hash.fetch('tile_width_mm', preset ? preset[1] : 165.0).to_f,
                headlap_mm:        payload_hash.fetch('headlap_mm', preset ? preset[2] : 65.0).to_f,
                side_gap_mm:       [payload_hash.fetch('side_gap_mm', 0.0).to_f, 0.0].max,
                base_thickness_mm: [payload_hash.fetch('base_thickness_mm', 10.0).to_f, 0.0].max,
                lift_mm:           payload_hash.fetch('lift_mm', 0.0).to_f,
                stagger:           !!payload_hash.fetch('stagger', true),
                rotation_steps:    payload_hash.fetch('rotation_steps', 0).to_i % 4
            }
        end
        private_class_method :na_read_options
        # ------------------------------------------------------------

        # HELPER FUNCTION | Get or Create the Rosemary Tile Rectangle Component Definition
        # ------------------------------------------------------------
        # base_thickness_mm draws the visible tile end as a second line above the
        # bottom edge of the course rectangle (0 or >= gauge disables it).
        def self.na_build_tile_definition(model, tile_width_mm, visible_gauge_mm, base_thickness_mm = 0.0)
            width_text      = tile_width_mm.round(1)
            gauge_text      = visible_gauge_mm.round(1)
            base_text       = base_thickness_mm.round(1)
            definition_name = "Na__FacePattern__RosemaryTile__#{width_text}x#{gauge_text}b#{base_text}"

            existing = model.definitions[definition_name]
            return existing if existing

            definition = model.definitions.add(definition_name)
            entities   = definition.entities

            p0 = Geom::Point3d.new(0, 0, 0)
            p1 = Geom::Point3d.new(tile_width_mm.mm, 0, 0)
            p2 = Geom::Point3d.new(tile_width_mm.mm, visible_gauge_mm.mm, 0)
            p3 = Geom::Point3d.new(0, visible_gauge_mm.mm, 0)

            entities.add_line(p0, p1)
            entities.add_line(p1, p2)
            entities.add_line(p2, p3)
            entities.add_line(p3, p0)

            if base_thickness_mm > 0 && base_thickness_mm < visible_gauge_mm
                b0 = Geom::Point3d.new(0, base_thickness_mm.mm, 0)
                b1 = Geom::Point3d.new(tile_width_mm.mm, base_thickness_mm.mm, 0)
                entities.add_line(b0, b1)
            end

            definition
        end
        private_class_method :na_build_tile_definition
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Population
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Tile Rosemary Instances Across the Face in Courses
        # ------------------------------------------------------------
        def self.na_populate_face(entities, definition, face, tile_width_mm, visible_gauge_mm, side_gap_mm, lift_mm, stagger, rotation_steps = 0)
            basis = na_build_basis(face)
            return 0 unless basis

            na_rotate_basis_clockwise!(basis, rotation_steps)

            local_vertices = face.outer_loop.vertices.map { |vertex| na_to_local_2d(vertex.position, basis) }
            min_x, max_x   = local_vertices.map(&:first).minmax
            min_y, max_y   = local_vertices.map(&:last).minmax

            x_step_mm = tile_width_mm + side_gap_mm
            y_step_mm = visible_gauge_mm
            row_index = 0
            y_mm      = min_y - y_step_mm
            count     = 0

            while y_mm <= max_y + y_step_mm
                row_offset_mm = stagger && row_index.odd? ? -(x_step_mm / 2.0) : 0.0
                x_mm = min_x - x_step_mm + row_offset_mm

                while x_mm <= max_x + x_step_mm
                    corners = [
                        [x_mm, y_mm],
                        [x_mm + tile_width_mm, y_mm],
                        [x_mm + tile_width_mm, y_mm + visible_gauge_mm],
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

        # HELPER FUNCTION | Test Whether All Tile Corners Lie on or Inside the Face
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

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { success: !!success_flag, message: message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FacePatternGenerator__RosemaryBuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
