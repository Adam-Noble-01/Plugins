# =============================================================================
# NA SKETCHUP MCP - HANDLERS - GEOMETRY
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Geometry__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Geometry
# PURPOSE    : geometry_draw, geometry_create_mesh, geometry_extrude
# CREATED    : 2026
#
# FACE ORIENTATION RULE (agents never have to know SketchUp's quirk):
# Entities#add_face ignores point order on the ground plane and always faces
# down there. Every face made here is therefore re-oriented to the right-hand
# rule of the points it was given (counter-clockwise seen from above = up), or
# to the explicit "normal" for circles and polygons. A positive "extrude" then
# always pushes along that normal.
#
# @delegate: Na__SketchUpMcp__BridgeHelpers__Creation__.rb (parent, coords, wrap_in, finishing)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Geometry

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DRAW_KINDS = %w[line polyline rectangle circle arc polygon face].freeze
        NA_MAX_MESH_POLYGONS = 50_000
        NA_PLANAR_TOLERANCE_INCHES = 0.001

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_draw
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Geometry__Draw(params, ctx)
            kind = Na__Params.Na__Params__Enum(params, 'kind', NA_DRAW_KINDS, nil, required: true)
            closed_kind = %w[rectangle circle polygon face].include?(kind)
            prepared = Na__Creation.Na__Creation__Prepare(params, ctx, closed_kind ? 'group' : 'none')
            unit = ctx[:unit]

            created, face, expected_normal = case kind
                                             when 'line', 'polyline' then na_draw_polyline(params, prepared, unit, kind)
                                             when 'rectangle'        then na_draw_rectangle(params, prepared, unit)
                                             when 'circle'           then na_draw_circle(params, prepared, unit)
                                             when 'arc'              then na_draw_arc(params, prepared, unit)
                                             when 'polygon'          then na_draw_polygon(params, prepared, unit)
                                             when 'face'             then na_draw_face(params, prepared, unit)
                                             end

            if face && face.valid?
                Na__Creation.Na__Creation__OrientFace(face, expected_normal) if expected_normal
                created = na_fill_or_extrude(face, created, params, prepared, ctx)
            end

            # An unnamed wrapper is named from what was drawn: "Extruded rectangle 6000 x 4000 x 2700".
            label = Na__Params.Na__Params__Has(params, 'extrude') ? "Extruded #{kind}" : kind.capitalize
            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, created, kind: label)
            result['kind'] = kind
            result
        end

        def self.na_draw_polyline(params, prepared, unit, kind)
            points = Na__Creation.Na__Creation__Points(params['points'], prepared, unit, 'points', 2)
            if kind == 'line' && points.length != 2
                raise Na__McpError.new('invalid_params', "kind 'line' takes exactly 2 points (got #{points.length}).", "Use kind 'polyline' for more.")
            end

            closed = Na__Params.Na__Params__Boolean(params, 'closed', false)
            if closed && points.length >= 3
                face = prepared[:entities].add_face(points)
                if face
                    return [face.edges + [face], face, Na__Creation.Na__Creation__WindingNormal(points)]
                end
                points += [points.first]
            end
            edges = points.length == 2 ? [prepared[:entities].add_line(points[0], points[1])] : prepared[:entities].add_edges(points)
            [edges.compact, nil, nil]
        end

        # 2 points: opposite corners on a plane parallel to XY, XZ or YZ. 3 points: corner,
        # end of the first side, and a point that fixes the second side's direction and length.
        def self.na_draw_rectangle(params, prepared, unit)
            corners = Na__Params.Na__Params__Array(params, 'points', nil, required: true, min_items: 2, max_items: 3)
            input = corners.each_with_index.map { |values, index| Na__Units.Na__Units__Point(values, unit, "points[#{index}]") }
            outline = corners.length == 2 ? na_axis_rectangle(input[0], input[1]) : na_three_point_rectangle(*input)
            points = outline.map { |point| prepared[:input_to_reported] * point }
            face = prepared[:entities].add_face(points)
            raise Na__McpError.new('operation_failed', 'SketchUp could not make that rectangle.', 'Check the corners are distinct.') unless face

            expected = params['normal'] ? Na__Creation.Na__Creation__Direction(params['normal'], prepared, 'normal', normal: true) : Na__Creation.Na__Creation__WindingNormal(points)
            [face.edges + [face], face, expected]
        end

        def self.na_axis_rectangle(first, second)
            deltas = [second.x - first.x, second.y - first.y, second.z - first.z].map { |value| value.to_f.abs }
            flat_axis = deltas.index(deltas.min)
            if deltas.min > NA_PLANAR_TOLERANCE_INCHES
                raise Na__McpError.new('invalid_params', 'Two rectangle corners must share one coordinate (lie on a plane parallel to XY, XZ or YZ).',
                                       'Give 3 points (corner, side end, side direction) for a tilted rectangle.')
            end

            case flat_axis
            when 2 then [[first.x, first.y], [second.x, first.y], [second.x, second.y], [first.x, second.y]].map { |x, y| Geom::Point3d.new(x, y, first.z) }
            when 1 then [[first.x, first.z], [second.x, first.z], [second.x, second.z], [first.x, second.z]].map { |x, z| Geom::Point3d.new(x, first.y, z) }
            else [[first.y, first.z], [second.y, first.z], [second.y, second.z], [first.y, second.z]].map { |y, z| Geom::Point3d.new(first.x, y, z) }
            end
        end

        def self.na_three_point_rectangle(corner, side_end, direction_point)
            side = corner.vector_to(side_end)
            raise Na__McpError.new('invalid_params', 'The first two rectangle points are the same.', nil) unless side.length > 0

            toward = corner.vector_to(direction_point)
            along = side.normalize
            perpendicular = toward - Geom::Vector3d.new(along.x * toward.dot(along), along.y * toward.dot(along), along.z * toward.dot(along))
            unless perpendicular.length > NA_PLANAR_TOLERANCE_INCHES
                raise Na__McpError.new('invalid_params', 'The third rectangle point lies on the first side.', 'Move it off the line of the first side.')
            end

            [corner, side_end, side_end.offset(perpendicular), corner.offset(perpendicular)]
        end

        def self.na_draw_circle(params, prepared, unit)
            center = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'center'), prepared, unit, 'center')
            radius = Na__Creation.Na__Creation__Length(Na__Params.Na__Params__Required(params, 'radius'), prepared, unit, 'radius')
            normal = Na__Creation.Na__Creation__Direction(params['normal'] || [0, 0, 1], prepared, 'normal', normal: true)
            segments = na_segments(params)
            edges = prepared[:entities].add_circle(center, normal, radius, segments)
            return [edges, nil, nil] unless Na__Params.Na__Params__Boolean(params, 'fill_face', true)

            face = prepared[:entities].add_face(edges)
            [edges + [face].compact, face, normal]
        end

        def self.na_draw_arc(params, prepared, unit)
            center = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'center'), prepared, unit, 'center')
            radius = Na__Creation.Na__Creation__Length(Na__Params.Na__Params__Required(params, 'radius'), prepared, unit, 'radius')
            normal = Na__Creation.Na__Creation__Direction(params['normal'] || [0, 0, 1], prepared, 'normal', normal: true)
            x_axis = Na__Creation.Na__Creation__Direction(params['x_axis'] || [1, 0, 0], prepared, 'x_axis')
            start_angle = Na__Units.Na__Units__Radians(Na__Params.Na__Params__Number(params, 'start_angle', 0.0))
            end_angle = Na__Units.Na__Units__Radians(Na__Params.Na__Params__Number(params, 'end_angle', nil, required: true))
            if (end_angle - start_angle).abs < 1.0e-9
                raise Na__McpError.new('invalid_params', 'start_angle and end_angle are equal; the arc has no length.', nil)
            end

            edges = prepared[:entities].add_arc(center, x_axis, normal, radius, start_angle, end_angle, na_segments(params))
            [edges, nil, nil]
        end

        def self.na_draw_polygon(params, prepared, unit)
            center = Na__Creation.Na__Creation__Point(Na__Params.Na__Params__Required(params, 'center'), prepared, unit, 'center')
            radius = Na__Creation.Na__Creation__Length(Na__Params.Na__Params__Required(params, 'radius'), prepared, unit, 'radius')
            normal = Na__Creation.Na__Creation__Direction(params['normal'] || [0, 0, 1], prepared, 'normal', normal: true)
            sides = Na__Params.Na__Params__Integer(params, 'sides', 6, min: 3, max: 360)
            edges = prepared[:entities].add_ngon(center, normal, radius, sides)
            return [edges, nil, nil] unless Na__Params.Na__Params__Boolean(params, 'fill_face', true)

            face = prepared[:entities].add_face(edges)
            [edges + [face].compact, face, normal]
        end

        def self.na_draw_face(params, prepared, unit)
            outer = Na__Creation.Na__Creation__Points(params['points'], prepared, unit, 'points', 3)
            face = prepared[:entities].add_face(outer)
            unless face
                raise Na__McpError.new('operation_failed', 'SketchUp could not make a face from those points.',
                                       'Points must be planar, distinct and not all on one line.')
            end

            holes = Na__Params.Na__Params__Array(params, 'holes', []) || []
            holes.each_with_index do |hole, index|
                hole_points = Na__Creation.Na__Creation__Points(hole, prepared, unit, "holes[#{index}]", 3)
                hole_face = prepared[:entities].add_face(hole_points)
                hole_face.erase! if hole_face && hole_face.valid? && hole_face != face
            end
            # Cutting a hole can replace the outer face; the largest face on the outer points is it.
            face = na_face_on_points(prepared[:entities], outer) unless face.valid?
            [face ? face.all_connected : [], face, Na__Creation.Na__Creation__WindingNormal(outer)]
        end

        def self.na_face_on_points(entities, outer_points)
            candidates = entities.grep(Sketchup::Face).select do |candidate|
                outer_points.all? { |point| candidate.classify_point(point) != Sketchup::Face::PointOutside }
            end
            candidates.max_by(&:area)
        end

        def self.na_segments(params)
            default_segments = Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'curve_segments', 24).to_i
            Na__Params.Na__Params__Integer(params, 'segments', default_segments, min: 3, max: 720)
        end

        def self.na_fill_or_extrude(face, created, params, prepared, ctx)
            fill = Na__Params.Na__Params__Boolean(params, 'fill_face', true)
            if Na__Params.Na__Params__Has(params, 'extrude')
                distance = Na__Units.Na__Units__ToInches(params['extrude'], ctx[:unit], 'extrude')
                if distance.abs > 1.0e-9
                    Na__Creation.Na__Creation__PushPull(face, distance, prepared, ctx)
                    # The new solid is everything now connected to the pushed face.
                    return face.valid? ? face.all_connected : created.select(&:valid?)
                end
            end
            unless fill
                face.erase!
                return created.select(&:valid?)
            end
            created
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_create_mesh
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Geometry__CreateMesh(params, ctx)
            unit = ctx[:unit]
            vertices = Na__Params.Na__Params__Array(params, 'vertices', nil, required: true, min_items: 3, max_items: 200_000)
            polygons = Na__Params.Na__Params__Array(params, 'polygons', nil, required: true, min_items: 1, max_items: NA_MAX_MESH_POLYGONS)
            prepared = Na__Creation.Na__Creation__Prepare(params, ctx, 'group')
            points = vertices.each_with_index.map { |values, index| Na__Creation.Na__Creation__Point(values, prepared, unit, "vertices[#{index}]") }
            loops = polygons.each_with_index.map { |indices, index| na_polygon_points(indices, points, index) }

            stats, faces = na_build_faces(prepared[:entities], loops)
            # Hand-wound polygons are often mixed up: make each shell consistent and closed shells
            # face out, so a closed mesh is a real solid whatever the winding (Na__SolidHealth).
            orientation = Na__SolidHealth.Na__SolidHealth__OrientShells(faces.select(&:valid?))
            stats.merge!(orientation)
            if orientation['faces_flipped'] > 0 || orientation['shells_turned_outward'] > 0
                ctx[:warnings] << "Re-oriented the mesh: #{orientation['faces_flipped']} face(s) turned to match their neighbours, " \
                                  "#{orientation['shells_turned_outward']} closed shell(s) turned outward."
            end
            open_shells = orientation['shells'] - orientation['closed_shells']
            if open_shells > 0
                ctx[:warnings] << "#{open_shells} of #{orientation['shells']} shell(s) are open (not closed): fine for a surface, " \
                                  'but solid tools will refuse this mesh. Add the missing polygons if it should be a solid.'
            end
            edges = faces.select(&:valid?).flat_map(&:edges).uniq
            if Na__Params.Na__Params__Boolean(params, 'smooth', false)
                angle = Na__Params.Na__Params__Number(params, 'smooth_angle', 30.0, min: 0.0, max: 180.0)
                stats['softened_edges'] = Na__Handlers__GeometryEdit.Na__Handlers__GeometryEdit__SoftenByAngle(edges, angle, true)
            end
            ctx[:warnings] << "#{stats['skipped']} polygon(s) were degenerate and skipped." if stats['skipped'] > 0

            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, faces + edges, kind: 'Mesh')
            result['mesh'] = stats
            result
        end

        def self.na_polygon_points(indices, points, polygon_index)
            unless indices.is_a?(Array) && indices.length >= 3 && indices.all? { |value| value.is_a?(Integer) && value >= 0 && value < points.length }
                raise Na__McpError.new('invalid_params', "polygons[#{polygon_index}] must list 3+ vertex indices between 0 and #{points.length - 1}.", nil)
            end

            indices.map { |value| points[value] }
        end

        # EntitiesBuilder (SketchUp 2022+) when present: fast, no merging with other geometry.
        # Non-planar polygons are fanned into triangles instead of being refused.
        # Returns [stats, faces_created].
        def self.na_build_faces(entities, loops)
            stats = { 'faces' => 0, 'triangulated' => 0, 'skipped' => 0 }
            faces = []
            add = lambda do |target, loop_points|
                pieces = na_planar?(loop_points) ? [loop_points] : na_fan_triangles(loop_points)
                stats['triangulated'] += 1 if pieces.length > 1
                pieces.each do |piece|
                    begin
                        face = target.add_face(piece)
                        if face
                            faces << face
                            stats['faces'] += 1
                        else
                            stats['skipped'] += 1
                        end
                    rescue ArgumentError
                        stats['skipped'] += 1
                    end
                end
            end

            if entities.respond_to?(:build)
                entities.build { |builder| loops.each { |loop_points| add.call(builder, loop_points) } }
                stats['builder'] = 'EntitiesBuilder'
            else
                loops.each { |loop_points| add.call(entities, loop_points) }
                stats['builder'] = 'Entities#add_face'
            end
            [stats, faces]
        end

        def self.na_planar?(points)
            return true if points.length == 3

            arrays = points.map { |point| [point.x.to_f, point.y.to_f, point.z.to_f] }
            normal = Na__LinearMath.Na__LinearMath__PolygonNormal(arrays)
            return false if Na__LinearMath.Na__LinearMath__Length(normal) < 0.5

            origin = arrays.first
            arrays.all? { |point| Na__LinearMath.Na__LinearMath__Dot(Na__LinearMath.Na__LinearMath__Subtract(point, origin), normal).abs < NA_PLANAR_TOLERANCE_INCHES }
        end

        def self.na_fan_triangles(points)
            (1...(points.length - 1)).map { |index| [points[0], points[index], points[index + 1]] }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_extrude (push/pull, Follow Me)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Geometry__Extrude(params, ctx)
            mode = Na__Params.Na__Params__Enum(params, 'mode', %w[pushpull followme], nil, required: true)
            mode == 'pushpull' ? na_pushpull(params, ctx) : na_followme(params, ctx)
        end

        def self.na_pushpull(params, ctx)
            model = ctx[:model]
            faces = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'face_ids'), 'face_ids')
            not_faces = faces.reject { |entity| entity.is_a?(Sketchup::Face) }
            unless not_faces.empty?
                raise Na__McpError.new('wrong_type', "face_ids contains a #{Na__EntityResolver.Na__EntityResolver__TypeName(not_faces.first)} (id #{not_faces.first.persistent_id}).",
                                       'Find face ids with entity_query types:["Face"] (parent_id = the group).')
            end

            distance = Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(params, 'distance'), ctx[:unit], 'distance')
            copy = Na__Params.Na__Params__Boolean(params, 'copy', false)
            factors = faces.map do |face|
                path = Na__Serializer.Na__Serializer__ContainerPath(ctx, face)
                scale = Na__Coordinates.Na__Coordinates__PushPullScale(model, face, path)
                face.pushpull(distance / scale, copy)
                scale.round(6)
            end
            ctx[:warnings] << 'Some faces sit in scaled groups; distances were converted to their definition units.' if factors.any? { |factor| (factor - 1.0).abs > 1.0e-6 }
            { 'pushed' => faces.length, 'distance' => Na__Units.Na__Units__FromInches(distance, ctx[:unit]), 'units' => ctx[:unit],
              'summary' => "Pushed #{faces.length} face(s) by #{Na__Units.Na__Units__FromInches(distance, ctx[:unit])} #{ctx[:unit]}." }
        end

        def self.na_followme(params, ctx)
            model = ctx[:model]
            profile = Na__EntityResolver.Na__EntityResolver__RequireOfClass(model, Na__Params.Na__Params__Integer(params, 'profile_face_id', nil, required: true), Sketchup::Face, 'profile_face_id')
            owner_entities = profile.parent.entities
            made_path = false

            path_edges = if Na__Params.Na__Params__Has(params, 'path_edge_ids')
                             edges = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'path_edge_ids'), 'path_edge_ids')
                             stray = edges.find { |edge| !edge.is_a?(Sketchup::Edge) || edge.parent != profile.parent }
                             if stray
                                 raise Na__McpError.new('invalid_params', 'Every path edge must be an Edge in the same group/context as the profile face.',
                                                        'Use path_points instead to draw the path in the right place automatically.')
                             end
                             edges
                         else
                             made_path = true
                             na_path_edges_from_points(params, profile, owner_entities, ctx)
                         end

            unless profile.followme(path_edges)
                raise Na__McpError.new('operation_failed', 'Follow Me failed.',
                                       'The path must be connected, start at (or near) the profile, and not be parallel to the profile face.')
            end

            removed = 0
            if made_path && !Na__Params.Na__Params__Boolean(params, 'keep_path', false)
                stray_edges = path_edges.select { |edge| edge.valid? && edge.faces.empty? }
                owner_entities.erase_entities(stray_edges) unless stray_edges.empty?
                removed = stray_edges.length
            end
            { 'followed' => true, 'path_edges' => path_edges.length, 'path_edges_removed' => removed,
              'summary' => "Swept the profile along #{path_edges.length} path edge(s)." }
        end

        # path_points are world (or local with coords:"local") positions, drawn in the profile's own context.
        def self.na_path_edges_from_points(params, profile, owner_entities, ctx)
            model = ctx[:model]
            container_path = Na__Serializer.Na__Serializer__ContainerPath(ctx, profile)
            to_world = Na__Coordinates.Na__Coordinates__ReportedToWorld(model, container_path)
            coords = Na__Params.Na__Params__Enum(params, 'coords', %w[world local], 'world')
            input_to_reported = coords == 'world' ? to_world.inverse : to_world.inverse * Na__Coordinates.Na__Coordinates__PlacementForPath(model, container_path)
            raw_points = Na__Params.Na__Params__Array(params, 'path_points', nil, required: true, min_items: 2)
            points = raw_points.each_with_index.map { |values, index| input_to_reported * Na__Units.Na__Units__Point(values, ctx[:unit], "path_points[#{index}]") }
            owner_entities.add_curve(points)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Geometry
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
