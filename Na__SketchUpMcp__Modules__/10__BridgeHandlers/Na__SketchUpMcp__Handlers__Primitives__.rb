# =============================================================================
# NA SKETCHUP MCP - HANDLERS - PRIMITIVES
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Primitives__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Primitives
# PURPOSE    : geometry_create_solid: box, cylinder, cone, sphere, hemisphere,
#              prism, pyramid, tube, torus as clean solid groups
# CREATED    : 2026
#
# HOW A PRIMITIVE IS BUILT:
# 1. The mesh is generated in a canonical "base frame": footprint centred on the
#    origin, base on z = 0, height up +Z. Every polygon carries an outward hint.
# 2. It is built into a fresh group (EntitiesBuilder when available), so it is
#    a closed, manifold solid that never merges with neighbouring geometry.
# 3. Each face is turned to agree with its outward hint (never trusting winding,
#    because add_face flips faces on a ground plane) and curved surfaces are
#    softened and smoothed.
# 4. ONE placement transform puts it in the model: the anchor point of the base
#    frame goes to "position", the axes follow x_axis/z_axis/rotation_z, and the
#    group lands in any parent at any depth through Na__Creation.
# The group's own axes are therefore the solid's natural axes: later edits,
# rotations and scaling behave the way a modeller expects.
#
# @delegate: Na__SketchUpMcp__BridgeHelpers__Creation__.rb
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Primitives

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_SHAPES = %w[box cylinder cone sphere hemisphere prism pyramid tube torus].freeze
        NA_DEFAULT_ANCHORS = {
            'box' => 'corner', 'sphere' => 'center', 'torus' => 'center'
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_create_solid
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Primitives__CreateSolid(params, ctx)
            shape = Na__Params.Na__Params__Enum(params, 'shape', NA_SHAPES, nil, required: true)
            if params['wrap_in'] == 'none'
                raise Na__McpError.new('invalid_params', 'Solids are always created in their own group or component.',
                                       'Use wrap_in "group" or "component", then explode it if loose geometry is really wanted.')
            end

            dims = na_dimensions(shape, params, ctx[:unit])
            anchor = Na__Params.Na__Params__Enum(params, 'anchor', %w[corner base_center center], NA_DEFAULT_ANCHORS.fetch(shape, 'base_center'))
            placement = na_input_placement(params, ctx[:unit], na_anchor_point(shape, dims, anchor))

            prepared = Na__Creation.Na__Creation__Prepare(params, ctx, 'group')
            polygons = na_polygons(shape, dims)
            built = na_build(prepared[:entities], polygons)
            na_orient_and_soften(built)
            prepared[:wrapper].transformation = prepared[:input_to_reported] * placement

            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, [], kind: shape.capitalize)
            result['shape'] = shape
            result['anchor'] = anchor
            unless result['manifold']
                ctx[:warnings] << 'The new solid did not report as manifold; volume and solid tools may refuse it.'
            end
            result
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dimensions and Placement
# -----------------------------------------------------------------------------

        def self.na_dimensions(shape, params, unit)
            segments = Na__Params.Na__Params__Integer(params, 'segments', Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'curve_segments', 24).to_i, min: 3, max: 360)
            dims = { segments: segments }

            case shape
            when 'box'
                size = Na__Params.Na__Params__Array(params, 'size', nil, required: true, min_items: 3, max_items: 3)
                dims[:width], dims[:depth], dims[:height] = size.each_with_index.map { |value, index| Na__Units.Na__Units__PositiveLength(value, unit, "size[#{index}]") }
            when 'sphere', 'hemisphere'
                dims[:radius] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'radius'), unit, 'radius')
                dims[:segments] = [segments, 4].max
            when 'torus'
                dims[:radius] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'radius'), unit, 'radius')
                dims[:minor_radius] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'minor_radius'), unit, 'minor_radius')
                if dims[:minor_radius] >= dims[:radius]
                    raise Na__McpError.new('invalid_params', 'minor_radius must be smaller than radius (the distance to the tube centre).', nil)
                end
            else
                dims[:radius] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'radius'), unit, 'radius')
                dims[:height] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'height'), unit, 'height')
                dims[:segments] = Na__Params.Na__Params__Integer(params, 'sides', 6, min: 3, max: 360) if %w[prism pyramid].include?(shape)
                if shape == 'tube'
                    dims[:inner_radius] = Na__Units.Na__Units__PositiveLength(Na__Params.Na__Params__Required(params, 'inner_radius'), unit, 'inner_radius')
                    if dims[:inner_radius] >= dims[:radius]
                        raise Na__McpError.new('invalid_params', 'inner_radius must be smaller than radius.', 'The wall thickness is radius - inner_radius.')
                    end
                end
            end
            dims
        end

        # [half_x, half_y, height] of the base-frame bounding box.
        def self.na_extents(shape, dims)
            case shape
            when 'box' then [dims[:width] / 2.0, dims[:depth] / 2.0, dims[:height]]
            when 'sphere' then [dims[:radius], dims[:radius], dims[:radius] * 2.0]
            when 'hemisphere' then [dims[:radius], dims[:radius], dims[:radius]]
            when 'torus'
                outer = dims[:radius] + dims[:minor_radius]
                [outer, outer, dims[:minor_radius] * 2.0]
            else [dims[:radius], dims[:radius], dims[:height]]
            end
        end

        def self.na_anchor_point(shape, dims, anchor)
            half_x, half_y, height = na_extents(shape, dims)
            case anchor
            when 'corner' then [-half_x, -half_y, 0.0]
            when 'center' then [0.0, 0.0, height / 2.0]
            else [0.0, 0.0, 0.0]
            end
        end

        # Public: the shared position / x_axis / z_axis / rotation_z placement contract.
        def self.Na__Handlers__Primitives__InputPlacement(params, unit, anchor_point)
            na_input_placement(params, unit, anchor_point)
        end

        # position/x_axis/z_axis/rotation_z (input frame) -> Transformation placing the base frame.
        def self.na_input_placement(params, unit, anchor_point)
            position = Na__Units.Na__Units__Point(params['position'] || [0, 0, 0], unit, 'position')
            z_axis = params['z_axis'] ? Na__Units.Na__Units__Direction(params['z_axis'], 'z_axis') : Geom::Vector3d.new(0, 0, 1)
            x_axis = if params['x_axis']
                         Na__Units.Na__Units__Direction(params['x_axis'], 'x_axis')
                     elsif z_axis.parallel?(Geom::Vector3d.new(0, 0, 1))
                         Geom::Vector3d.new(1, 0, 0)
                     else
                         z_axis.axes[0]
                     end

            z_array = Na__LinearMath.Na__LinearMath__Normalize(z_axis.to_a.map(&:to_f))
            x_array = x_axis.to_a.map(&:to_f)
            x_array = Na__LinearMath.Na__LinearMath__Normalize(Na__LinearMath.Na__LinearMath__Subtract(x_array, Na__LinearMath.Na__LinearMath__Scale(z_array, Na__LinearMath.Na__LinearMath__Dot(x_array, z_array))))
            if Na__LinearMath.Na__LinearMath__Length(x_array) < 1.0e-9
                raise Na__McpError.new('invalid_params', 'x_axis is parallel to z_axis.', 'Give an x_axis perpendicular to z_axis.')
            end

            angle = Na__Units.Na__Units__Radians(Na__Params.Na__Params__Number(params, 'rotation_z', 0.0))
            y_array = Na__LinearMath.Na__LinearMath__Cross(z_array, x_array)
            rotated_x = Na__LinearMath.Na__LinearMath__Add(Na__LinearMath.Na__LinearMath__Scale(x_array, Math.cos(angle)), Na__LinearMath.Na__LinearMath__Scale(y_array, Math.sin(angle)))
            rotated_y = Na__LinearMath.Na__LinearMath__Cross(z_array, rotated_x)

            axes = Geom::Transformation.axes(position, Geom::Vector3d.new(*rotated_x), Geom::Vector3d.new(*rotated_y), Geom::Vector3d.new(*z_array))
            axes * Geom::Transformation.translation(Geom::Vector3d.new(*anchor_point.map { |value| -value }))
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Base-Frame Meshes ({points:, holes:, outward:, smooth:})
# -----------------------------------------------------------------------------

        def self.na_polygons(shape, dims)
            case shape
            when 'box'        then na_box(dims)
            when 'cylinder'   then na_extruded_ring(dims[:radius], dims[:height], dims[:segments], true)
            when 'prism'      then na_extruded_ring(dims[:radius], dims[:height], dims[:segments], false)
            when 'cone'       then na_cone(dims[:radius], dims[:height], dims[:segments], true)
            when 'pyramid'    then na_cone(dims[:radius], dims[:height], dims[:segments], false)
            when 'sphere'     then na_sphere(dims[:radius], dims[:segments], false)
            when 'hemisphere' then na_sphere(dims[:radius], dims[:segments], true)
            when 'tube'       then na_tube(dims[:radius], dims[:inner_radius], dims[:height], dims[:segments])
            when 'torus'      then na_torus(dims[:radius], dims[:minor_radius], dims[:segments])
            end
        end

        def self.na_box(dims)
            x = dims[:width] / 2.0
            y = dims[:depth] / 2.0
            z = dims[:height]
            corners = [[-x, -y, 0.0], [x, -y, 0.0], [x, y, 0.0], [-x, y, 0.0], [-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z]]
            [
                [[0, 3, 2, 1], [0, 0, -1]], [[4, 5, 6, 7], [0, 0, 1]], [[0, 1, 5, 4], [0, -1, 0]],
                [[1, 2, 6, 5], [1, 0, 0]], [[2, 3, 7, 6], [0, 1, 0]], [[3, 0, 4, 7], [-1, 0, 0]]
            ].map { |indices, outward| { points: indices.map { |index| corners[index] }, outward: outward, smooth: false } }
        end

        def self.na_ring(radius, z, segments)
            (0...segments).map do |index|
                angle = 2.0 * Math::PI * index / segments
                [radius * Math.cos(angle), radius * Math.sin(angle), z]
            end
        end

        def self.na_extruded_ring(radius, height, segments, smooth_sides)
            bottom = na_ring(radius, 0.0, segments)
            top = na_ring(radius, height, segments)
            polygons = [{ points: bottom.reverse, outward: [0, 0, -1], smooth: false },
                        { points: top, outward: [0, 0, 1], smooth: false }]
            segments.times do |index|
                following = (index + 1) % segments
                middle_angle = 2.0 * Math::PI * (index + 0.5) / segments
                polygons << { points: [bottom[index], bottom[following], top[following], top[index]],
                              outward: [Math.cos(middle_angle), Math.sin(middle_angle), 0.0], smooth: smooth_sides }
            end
            polygons
        end

        def self.na_cone(radius, height, segments, smooth_sides)
            base = na_ring(radius, 0.0, segments)
            apex = [0.0, 0.0, height]
            polygons = [{ points: base.reverse, outward: [0, 0, -1], smooth: false }]
            segments.times do |index|
                following = (index + 1) % segments
                middle_angle = 2.0 * Math::PI * (index + 0.5) / segments
                polygons << { points: [base[index], base[following], apex],
                              outward: [Math.cos(middle_angle) * height, Math.sin(middle_angle) * height, radius], smooth: smooth_sides }
            end
            polygons
        end

        # Latitude/longitude sphere sitting on z = 0 (centre at z = radius). Hemisphere: upper half + flat base.
        def self.na_sphere(radius, segments, hemisphere)
            rings = [segments / 2, 2].max
            rings += 1 if hemisphere && rings.odd? # the equator must be a ring to meet the base disk
            first_ring = hemisphere ? rings / 2 : 0
            centre = [0.0, 0.0, hemisphere ? 0.0 : radius]
            point_at = lambda do |ring, index|
                # Exact poles: sin(PI) is 1.2e-16, which kept the bottom pole ring from collapsing (non-manifold).
                return [centre[0], centre[1], centre[2] + radius] if ring.zero?
                return [centre[0], centre[1], centre[2] - radius] if ring == rings

                polar = Math::PI * ring / rings
                azimuth = 2.0 * Math::PI * index / segments
                height = 2 * ring == rings ? 0.0 : radius * Math.cos(polar) # exact equator, no 1e-17 drift
                [centre[0] + (radius * Math.sin(polar) * Math.cos(azimuth)),
                 centre[1] + (radius * Math.sin(polar) * Math.sin(azimuth)),
                 centre[2] + height]
            end

            polygons = []
            (0...rings).each do |ring|
                next if hemisphere && ring >= first_ring

                segments.times do |index|
                    following = (index + 1) % segments
                    corners = [point_at.call(ring, index), point_at.call(ring + 1, index), point_at.call(ring + 1, following), point_at.call(ring, following)]
                    corners.uniq! # pole quads collapse to triangles
                    outward = Na__LinearMath.Na__LinearMath__Subtract(na_centroid(corners), centre)
                    polygons << { points: corners, outward: outward, smooth: true }
                end
            end
            if hemisphere
                polygons << { points: na_ring(radius, 0.0, segments).reverse, outward: [0, 0, -1], smooth: false }
            end
            polygons
        end

        def self.na_tube(radius, inner_radius, height, segments)
            outer_bottom = na_ring(radius, 0.0, segments)
            outer_top = na_ring(radius, height, segments)
            inner_bottom = na_ring(inner_radius, 0.0, segments)
            inner_top = na_ring(inner_radius, height, segments)
            polygons = [
                { points: outer_bottom.reverse, holes: [inner_bottom.reverse], outward: [0, 0, -1], smooth: false },
                { points: outer_top, holes: [inner_top], outward: [0, 0, 1], smooth: false }
            ]
            segments.times do |index|
                following = (index + 1) % segments
                middle_angle = 2.0 * Math::PI * (index + 0.5) / segments
                radial = [Math.cos(middle_angle), Math.sin(middle_angle), 0.0]
                polygons << { points: [outer_bottom[index], outer_bottom[following], outer_top[following], outer_top[index]], outward: radial, smooth: true }
                polygons << { points: [inner_bottom[following], inner_bottom[index], inner_top[index], inner_top[following]],
                              outward: Na__LinearMath.Na__LinearMath__Scale(radial, -1.0), smooth: true }
            end
            polygons
        end

        # Torus lying on z = 0: tube centre circle radius R at height r.
        def self.na_torus(major, minor, segments)
            minor_segments = [segments / 2, 3].max
            point_at = lambda do |around, tube|
                u = 2.0 * Math::PI * around / segments
                v = 2.0 * Math::PI * tube / minor_segments
                ring = major + (minor * Math.cos(v))
                [ring * Math.cos(u), ring * Math.sin(u), minor + (minor * Math.sin(v))]
            end

            polygons = []
            segments.times do |around|
                minor_segments.times do |tube|
                    corners = [point_at.call(around, tube), point_at.call(around + 1, tube), point_at.call(around + 1, tube + 1), point_at.call(around, tube + 1)]
                    centroid = na_centroid(corners)
                    horizontal = Na__LinearMath.Na__LinearMath__Normalize([centroid[0], centroid[1], 0.0])
                    tube_centre = [horizontal[0] * major, horizontal[1] * major, minor]
                    polygons << { points: corners, outward: Na__LinearMath.Na__LinearMath__Subtract(centroid, tube_centre), smooth: true }
                end
            end
            polygons
        end

        def self.na_centroid(points)
            count = points.length.to_f
            [0, 1, 2].map { |axis| points.sum { |point| point[axis] } / count }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Build, Orient, Soften
# -----------------------------------------------------------------------------

        # Returns [[face, polygon], ...].
        def self.na_build(entities, polygons)
            built = []
            if entities.respond_to?(:build)
                entities.build do |builder|
                    polygons.each do |polygon|
                        outer = polygon[:points].map { |values| Geom::Point3d.new(*values) }
                        holes = (polygon[:holes] || []).map { |loop_values| loop_values.map { |values| Geom::Point3d.new(*values) } }
                        face = holes.empty? ? builder.add_face(outer) : builder.add_face(outer, holes: holes)
                        built << [face, polygon] if face
                    end
                end
            else
                polygons.each do |polygon|
                    face = entities.add_face(polygon[:points].map { |values| Geom::Point3d.new(*values) })
                    next unless face

                    (polygon[:holes] || []).each do |loop_values|
                        hole = entities.add_face(loop_values.map { |values| Geom::Point3d.new(*values) })
                        hole.erase! if hole && hole != face
                    end
                    built << [face, polygon] if face.valid?
                end
            end
            built
        end

        def self.na_orient_and_soften(built)
            smooth_faces = {}
            built.each do |face, polygon|
                next unless face.valid?

                face.reverse! if face.normal.dot(Geom::Vector3d.new(*polygon[:outward])) < 0
                smooth_faces[face] = true if polygon[:smooth]
            end

            built.map(&:first).select(&:valid?).flat_map(&:edges).uniq.each do |edge|
                neighbours = edge.faces
                next unless neighbours.length == 2 && neighbours.all? { |face| smooth_faces[face] }

                edge.soft = true
                edge.smooth = true
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Primitives
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
