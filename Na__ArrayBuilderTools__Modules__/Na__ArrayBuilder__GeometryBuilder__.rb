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
# VERSION    : 0.0.3
#
# DESCRIPTION:
# - Creates a component containing all array units along a path
# - Dentil  : grouped axis-aligned box
# - Dogtooth: grouped 45-degree-rotated box
# - Object  : repeated instance of a user-picked Group / Component
#             (registered via Na__ArrayBuilder__ObjectRegistry).
# - Orients units along the local path segment direction (local +X
#   forward, local +Z up by convention).
# - Supports two anchor modes for the 'object' type:
#     local_axis -> object's own definition origin lands on the path point
#     centre     -> object's bounding-box centre lands on the path point
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__GeometryBuilder

        NA_INCH_TO_MM = 25.4

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Create Array Course
        # ------------------------------------------------------------
        # Routes to the appropriate builder based on config['type'].
        #
        # @param waypoints [Array<Geom::Point3d>] Committed path points
        # @param config [Hash] Configuration with type, dimensions, spacing
        # @param positions [Array<Hash>] Pre-calculated positions from PathTool
        # @return [Sketchup::ComponentInstance, nil]
        def self.na_create_array(waypoints, config, positions)
            return nil if positions.nil? || positions.empty?

            type = config['type'] || 'dentil'

            if type == 'object'
                na_create_array_from_definition(positions, config)
            else
                na_create_array_from_box(positions, config, type)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Box-Based Array Course (Dentil / Dogtooth)
        # ------------------------------------------------------------
        def self.na_create_array_from_box(positions, config, type)
            model = Sketchup.active_model
            unit_w = ((config['unit_width_mm']  || 110).to_f).mm
            unit_d = ((config['unit_depth_mm']  || 30).to_f).mm
            unit_h = ((config['unit_height_mm'] || 75).to_f).mm

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

                Na__ArrayBuilderTools.na_debug_log("Created #{positions.length} #{type} units")
                instance

            rescue => e
                model.abort_operation
                puts "✗ Na Array Builder geometry error: #{e.message}"
                Na__ArrayBuilderTools.na_debug_log(e.backtrace.first(5).join("\n"))
                nil
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Object-Based Array (Custom Group / Component)
# -----------------------------------------------------------------------------

        # FUNCTION | Create Object-Based Array Course
        # ------------------------------------------------------------
        # Places repeated instances of the user-picked source definition
        # along the pre-calculated positions. Wraps all instances in a
        # single parent component so the result behaves identically to
        # the dentil / dogtooth output (one selectable assembly).
        def self.na_create_array_from_definition(positions, config)
            source_def = Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetDefinition
            return nil unless source_def && source_def.valid?

            model = Sketchup.active_model
            anchor_mode  = config['anchor_mode'] || 'local_axis'
            anchor_offset = na_compute_anchor_offset(source_def, anchor_mode)

            model.start_operation("Create Object Array", true)

            begin
                parent_def = model.definitions.add(
                    "Na_ArrayCourse_object_#{Time.now.to_i}"
                )

                positions.each do |pos|
                    tr = na_build_instance_transform(
                        pos[:point], pos[:direction], anchor_offset
                    )
                    parent_def.entities.add_instance(source_def, tr)
                end

                instance = model.active_entities.add_instance(
                    parent_def, Geom::Transformation.new
                )

                model.commit_operation

                model.selection.clear
                model.selection.add(instance)

                Na__ArrayBuilderTools.na_debug_log("Created #{positions.length} object instances")
                instance

            rescue => e
                model.abort_operation
                puts "✗ Na Array Builder object-array error: #{e.message}"
                Na__ArrayBuilderTools.na_debug_log(e.backtrace.first(5).join("\n"))
                nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compute Anchor-Offset Transform for Source Definition
        # ------------------------------------------------------------
        # local_axis -> identity (definition origin = path point)
        # centre     -> shifts so the bbox centre = path point
        #
        # Implementation note: translations are always invertible, so the
        # SU 2026 stricter Transformation#inverse rules do not affect us.
        def self.na_compute_anchor_offset(source_def, anchor_mode)
            return Geom::Transformation.new if anchor_mode != 'centre'

            bb = source_def.bounds
            return Geom::Transformation.new if bb.nil? || bb.empty?

            Geom::Transformation.translation(bb.center).inverse
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Per-Position Instance Transformation
        # ------------------------------------------------------------
        # Convention: local +X -> path forward, local +Z -> up.
        # The lateral (local +Y) is computed as forward × up so the basis
        # remains orthonormal even on non-horizontal segments.
        #
        # Final transform = translate_to_path_point * basis * anchor_offset
        def self.na_build_instance_transform(point, direction, anchor_offset)
            forward = na_unit_vector_or_default(direction, X_AXIS)
            up      = Z_AXIS.clone

            lateral = forward.cross(up)
            if lateral.length < 0.001
                lateral = Y_AXIS.clone
            else
                lateral.length = 1.0
            end

            actual_up = lateral.cross(forward)
            actual_up.length = 1.0 if actual_up.length > 0

            basis    = Geom::Transformation.axes(ORIGIN, forward, lateral, actual_up)
            position = Geom::Transformation.translation(point)

            position * basis * anchor_offset
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return Unit-Length Vector or a Default
        # ------------------------------------------------------------
        def self.na_unit_vector_or_default(vector, default_vector)
            return default_vector.clone if vector.nil? || vector.length < 0.001

            v = vector.clone
            v.length = 1.0
            v
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
