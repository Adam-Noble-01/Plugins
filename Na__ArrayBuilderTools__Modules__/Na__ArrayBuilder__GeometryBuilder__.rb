# =============================================================================
# NA ARRAY BUILDER TOOLS - GEOMETRY BUILDER
# =============================================================================
#
# FILE       : Na__ArrayBuilder__GeometryBuilder__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# MODULE     : Na__ArrayBuilder__GeometryBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Creates array course geometry from path and configuration
# CREATED    : 2026
# VERSION    : 0.0.2
#
# DESCRIPTION:
# - Creates a component containing all array units along a path
# - Each unit is a grouped box with correct face normals
# - Supports dentil (axis-aligned) and dog-tooth (45-degree rotated) types
# - Orients units along the local path segment direction
# - Applies brick-coloured material
#
# =============================================================================

require 'sketchup.rb'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__GeometryBuilder

        NA_INCH_TO_MM = 25.4

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Create Array Course
        # ------------------------------------------------------------
        # @param waypoints [Array<Geom::Point3d>] Committed path points
        # @param config [Hash] Configuration with type, dimensions, spacing
        # @param positions [Array<Hash>] Pre-calculated positions from PathTool
        # @return [Sketchup::ComponentInstance, nil]
        def self.na_create_array(waypoints, config, positions)
            return nil if positions.nil? || positions.empty?

            model = Sketchup.active_model
            type = config['type'] || 'dentil'
            unit_w_mm  = (config['unit_width_mm']  || 110).to_f
            unit_d_mm  = (config['unit_depth_mm']  || 30).to_f
            unit_h_mm  = (config['unit_height_mm'] || 75).to_f

            unit_w = unit_w_mm.mm
            unit_d = unit_d_mm.mm
            unit_h = unit_h_mm.mm

            model.start_operation("Create #{type.capitalize} Course", true)

            begin
                material = na_get_or_create_brick_material(model)
                comp_def = model.definitions.add("Na_ArrayCourse_#{type}_#{Time.now.to_i}")
                comp_entities = comp_def.entities

                positions.each_with_index do |pos, idx|
                    na_create_unit_at_position(
                        comp_entities, pos[:point], pos[:direction],
                        unit_w, unit_d, unit_h,
                        type, idx, material
                    )
                end

                instance = model.active_entities.add_instance(
                    comp_def, Geom::Transformation.new
                )

                model.commit_operation

                model.selection.clear
                model.selection.add(instance)

                puts "✓ Na Array Builder: Created #{positions.length} #{type} units"
                instance

            rescue => e
                model.abort_operation
                puts "✗ Na Array Builder geometry error: #{e.message}"
                puts e.backtrace.first(5).join("\n")
                nil
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Unit Creation
# -----------------------------------------------------------------------------

        # FUNCTION | Create Single Unit at Position
        # ------------------------------------------------------------
        def self.na_create_unit_at_position(entities, origin, direction, w, d, h, type, index, material)
            forward = direction.clone
            forward.length = 1.0 if forward.length > 0

            up = Z_AXIS.clone

            lateral = forward.cross(up)
            if lateral.length < 0.001
                lateral = Y_AXIS.clone
            else
                lateral.length = 1.0
            end

            actual_up = lateral.cross(forward)
            actual_up.length = 1.0 if actual_up.length > 0

            if type == 'dogtooth'
                rot = Geom::Transformation.rotation(ORIGIN, forward, 45.degrees)
                lateral  = lateral.transform(rot)
                actual_up = actual_up.transform(rot)
            end

            half_d = d * 0.5

            group_name = "Na_#{type.capitalize}_#{index}"
            group = entities.add_group
            group.name = group_name
            g_ents = group.entities

            corners = na_compute_oriented_corners(origin, forward, lateral, actual_up, w, half_d, h)
            faces = na_create_box_faces(g_ents, corners)
            na_fix_face_normals(faces, corners)
            na_apply_material(faces, material)

            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compute 8 Corners of Oriented Box
        # ------------------------------------------------------------
        def self.na_compute_oriented_corners(origin, fwd, lat, up, width, half_depth, height)
            c0 = origin.offset(lat, -half_depth)
            c1 = origin.offset(fwd, width).offset(lat, -half_depth)
            c2 = origin.offset(fwd, width).offset(lat, half_depth)
            c3 = origin.offset(lat, half_depth)
            c4 = c0.offset(up, height)
            c5 = c1.offset(up, height)
            c6 = c2.offset(up, height)
            c7 = c3.offset(up, height)

            [c0, c1, c2, c3, c4, c5, c6, c7]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Box Faces from 8 Corners
        # ------------------------------------------------------------
        def self.na_create_box_faces(entities, c)
            faces = []
            faces << entities.add_face(c[3], c[2], c[1], c[0])  # Bottom
            faces << entities.add_face(c[4], c[5], c[6], c[7])  # Top
            faces << entities.add_face(c[0], c[1], c[5], c[4])  # Front
            faces << entities.add_face(c[2], c[3], c[7], c[6])  # Back
            faces << entities.add_face(c[3], c[0], c[4], c[7])  # Left
            faces << entities.add_face(c[1], c[2], c[6], c[5])  # Right
            faces.compact
        end
        # ---------------------------------------------------------------

        # FUNCTION | Fix Face Normals to Point Outward
        # ------------------------------------------------------------
        def self.na_fix_face_normals(faces, corners)
            center = Geom::Point3d.new(
                corners.map(&:x).sum / 8.0,
                corners.map(&:y).sum / 8.0,
                corners.map(&:z).sum / 8.0
            )

            faces.each do |face|
                next unless face.valid?
                face_center = face.bounds.center
                outward = face_center - center
                face.reverse! if outward % face.normal < 0
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply Material to Faces
        # ------------------------------------------------------------
        def self.na_apply_material(faces, material)
            return unless material

            faces.each do |face|
                next unless face.valid?
                face.material = material
                face.back_material = material
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material
# -----------------------------------------------------------------------------

        # FUNCTION | Get or Create Brick Material
        # ------------------------------------------------------------
        def self.na_get_or_create_brick_material(model)
            mat_name = "Na_Brick_RedBrown"
            existing = model.materials[mat_name]
            return existing if existing

            mat = model.materials.add(mat_name)
            mat.color = Sketchup::Color.new(160, 82, 45)
            mat
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__GeometryBuilder
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
