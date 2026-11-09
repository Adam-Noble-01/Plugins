# =============================================================================
# NA SKETCHUP MCP - HANDLERS - GEOMETRY
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Geometry__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Geometry
# PURPOSE    : geometry_draw, geometry_create_mesh, geometry_create_lines,
#              geometry_drape, geometry_extrude
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
            na_edge_flags(params, points, edges, stats, ctx)

            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, faces + edges, kind: 'Mesh')
            result['mesh'] = stats
            result
        end

        # Single edges by their two vertex indices, applied in this order (1.0.10 soft / hard,
        # 1.0.11 smooth / quad). Edges are found by their end positions in the build frame (the points
        # the polygons were built from), so a pair that is not an edge of the mesh (or whose faces
        # were skipped) is counted, never guessed. quad_edges are QuadFace Tools' dividing edges:
        # soft, smooth and casting no shadow (TT_QuadFaceTools QuadFace.divider_props?).
        NA_EDGE_FLAG_SETS = [
            ['hard_edges',   { soft: false, smooth: false }],
            ['smooth_edges', { soft: false, smooth: true }],
            ['soft_edges',   { soft: true,  smooth: true }],
            ['quad_edges',   { soft: true,  smooth: true, casts_shadows: false }]
        ].freeze

        def self.na_edge_flags(params, points, edges, stats, ctx)
            sets = NA_EDGE_FLAG_SETS.select { |label, _flags| Na__Params.Na__Params__Has(params, label) }
            return if sets.empty?

            key = lambda { |point| [point.x.to_f.round(4), point.y.to_f.round(4), point.z.to_f.round(4)] }
            by_ends = {}
            edges.each do |edge|
                next unless edge.valid?

                a = key.call(edge.start.position)
                b = key.call(edge.end.position)
                by_ends[[a, b]] = edge
                by_ends[[b, a]] = edge
            end
            missing = 0
            sets.each do |label, flags|
                pairs = Na__Params.Na__Params__Array(params, label, nil, max_items: 400_000)
                count = 0
                pairs.each_with_index do |pair, index|
                    unless pair.is_a?(Array) && pair.length == 2 && pair.all? { |value| value.is_a?(Integer) && value >= 0 && value < points.length }
                        raise Na__McpError.new('invalid_params', "#{label}[#{index}] must be two vertex indices between 0 and #{points.length - 1}.", nil)
                    end

                    edge = by_ends[[key.call(points[pair[0]]), key.call(points[pair[1]])]]
                    unless edge
                        missing += 1
                        next
                    end

                    edge.soft = flags[:soft]
                    edge.smooth = flags[:smooth]
                    edge.casts_shadows = flags[:casts_shadows] if flags.key?(:casts_shadows)
                    count += 1
                end
                stats["#{label.sub('_edges', '')}_set"] = count
            end
            stats['pairs_not_found'] = missing
            return unless missing > 0

            ctx[:warnings] << "#{missing} edge flag pair(s) are not edges of this mesh (not a polygon side, or its faces were skipped): left as they were."
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
# REGION | geometry_create_lines (1.0.11)
# -----------------------------------------------------------------------------

        NA_MAX_POLYLINES = 20_000
        NA_MAX_LINE_POINTS = 400_000

        # Many polylines in one call: each welded into one curve (or loose edges) and painted
        # with its own material, inside a new group by default so nothing merges or splits.
        def self.Na__Handlers__Geometry__CreateLines(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            lines = Na__Params.Na__Params__Array(params, 'polylines', nil, required: true, min_items: 1, max_items: NA_MAX_POLYLINES)
            prepared = Na__Creation.Na__Creation__Prepare(params, ctx, 'group')
            materials = {}
            stats = { 'polylines' => 0, 'curves' => 0, 'edges' => 0, 'skipped' => 0 }
            total = 0
            created = []
            lines.each_with_index do |line, index|
                unless line.is_a?(Hash) && line['points'].is_a?(Array)
                    raise Na__McpError.new('invalid_params', "polylines[#{index}] must be an object with points.", 'Pass {"points": [[x, y, z], ...]}.')
                end

                total += line['points'].length
                if total > NA_MAX_LINE_POINTS
                    raise Na__McpError.new('invalid_params', "More than #{NA_MAX_LINE_POINTS} points in one call.", 'Split the polylines over several calls.')
                end

                points = Na__Creation.Na__Creation__Points(line['points'], prepared, unit, "polylines[#{index}].points", 2)
                points = na_distinct_run(points)
                points << points.first if line['closed'] == true && points.length > 2 && points.first != points.last
                if points.length < 2
                    stats['skipped'] += 1
                    next
                end

                weld = line.key?('weld') ? line['weld'] == true : true
                edges = Array(weld && points.length > 2 ? prepared[:entities].add_curve(points) : prepared[:entities].add_edges(points)).compact
                if edges.empty?
                    stats['skipped'] += 1
                    next
                end

                if line.key?('material')
                    name = line['material'].to_s
                    materials[name] = Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, line['material'], ctx[:warnings]) unless materials.key?(name)
                    edges.each { |edge| edge.material = materials[name] }
                end
                stats['polylines'] += 1
                stats['curves'] += 1 if weld && points.length > 2
                stats['edges'] += edges.length
                created.concat(edges)
            end
            ctx[:warnings] << "#{stats['skipped']} polyline(s) had fewer than two distinct points and were skipped." if stats['skipped'] > 0
            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, created, kind: 'Lines')
            result['lines'] = stats
            result
        end

        def self.na_distinct_run(points)
            out = []
            points.each { |point| out << point unless out.last && out.last == point }
            out
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_drape (1.0.11)
# -----------------------------------------------------------------------------
#
# Vertical projection, in world inches. The surface becomes a list of triangles
# (every face facing up, through Face#mesh, at any depth) in a plan grid index.
# Each source segment is cut at every plan crossing with a triangle edge; each
# piece takes the plane of the highest triangle under its middle, so it lies
# exactly on one face. Pieces join into runs; runs off the surface break.

        def self.Na__Handlers__Geometry__Drape(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            sources = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids', required: true), 'ids')
            surfaces = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'surface_ids', required: true), 'surface_ids')
            lift = params.key?('lift') ? Na__Units.Na__Units__ToInches(params['lift'], unit, 'lift') : 0.0
            weld = Na__Params.Na__Params__Boolean(params, 'weld', true)
            override = params.key?('material') ? [Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, params['material'], ctx[:warnings])] : nil

            tris = na_drape_triangles(surfaces, ctx)
            if tris.empty?
                raise Na__McpError.new('invalid_params', 'surface_ids hold no faces facing up.',
                                       'Pass the terrain group (or its top faces); vertical and downward faces are not used.')
            end

            runs = na_drape_runs(sources, ctx)
            raise Na__McpError.new('invalid_params', 'ids hold no edges to drape.', 'Pass edges, or the group holding the 2D linework.') if runs.empty?

            grid = na_drape_index(tris)
            prepared = Na__Creation.Na__Creation__Prepare(params, ctx, 'group')
            to_target = prepared[:input_to_reported]
            stats = { 'source_runs' => runs.length, 'source_segments' => runs.sum { |run| run[:points].length - 1 },
                      'surface_triangles' => tris.length, 'curves' => 0, 'pieces' => 0, 'edges' => 0 }
            off = 0.0
            created = []
            runs.each do |run|
                pieces, missed = na_drape_run(run[:points], tris, grid, lift)
                off += missed
                material = override ? override[0] : run[:material]
                pieces.each do |piece|
                    points = na_distinct_run(piece.map { |p| to_target * Geom::Point3d.new(p[0], p[1], p[2]) })
                    next if points.length < 2

                    edges = Array(weld && points.length > 2 ? prepared[:entities].add_curve(points) : prepared[:entities].add_edges(points)).compact
                    next if edges.empty?

                    edges.each { |edge| edge.material = material } if material
                    stats['curves'] += 1 if weld && points.length > 2
                    stats['pieces'] += 1
                    stats['edges'] += edges.length
                    created.concat(edges)
                end
            end
            if created.empty?
                prepared[:wrapper].erase! if prepared[:wrapper] && prepared[:wrapper].valid?
                raise Na__McpError.new('operation_failed', 'None of the lines lie over the surface in plan.', 'Check the 2D lines sit inside the surface footprint.')
            end

            stats['off_surface_length'] = Na__Units.Na__Units__FromInches(off, unit)
            ctx[:warnings] << "#{stats['off_surface_length'].round(1)} #{unit} of line lies off the surface in plan and was left out." if off > 0.04
            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, created, kind: 'Draped Lines')
            result['drape'] = stats
            result
        end

        # Upward faces under the surface entities -> [ax, ay, az, bx, by, bz, cx, cy, cz] in world inches.
        def self.na_drape_triangles(surfaces, ctx)
            budget = Na__Traversal.Na__Traversal__NewBudget
            tris = []
            surfaces.each do |entity|
                container_path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                Na__Traversal.Na__Traversal__FacesWithin(entity, container_path, 64, budget).each do |face, face_path|
                    world = Na__Serializer.Na__Serializer__ToWorld(ctx, face_path)[:transform]
                    normal = face.normal.transform(world)
                    next if normal.length.to_f < 1.0e-9

                    normal.normalize!
                    next unless normal.z > 0.01

                    mesh = face.mesh(0)
                    (1..mesh.count_polygons).each do |index|
                        corners = mesh.polygon_points_at(index).map { |point| point.transform(world) }
                        next unless corners.length == 3

                        a, b, c = corners
                        next if ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)).abs < 1.0e-8

                        tris << [a.x.to_f, a.y.to_f, a.z.to_f, b.x.to_f, b.y.to_f, b.z.to_f, c.x.to_f, c.y.to_f, c.z.to_f]
                    end
                end
            end
            tris
        end

        # Source edges -> runs {points: [[x, y, z] world inches], material}: one per curve, and one
        # per chain of loose edges (split where three or more meet).
        def self.na_drape_runs(sources, ctx)
            budget = Na__Traversal.Na__Traversal__NewBudget
            found = []
            sources.each do |entity|
                container_path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                if entity.is_a?(Sketchup::Edge)
                    found << [entity, container_path]
                elsif Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    Na__Traversal.Na__Traversal__Walk(entity.definition.entities, container_path + [entity], 64, budget) do |child, child_path, _depth|
                        found << [child, child_path] if child.is_a?(Sketchup::Edge)
                    end
                end
            end
            runs = []
            seen = {}
            loose = Hash.new { |hash, key| hash[key] = [] }
            found.each do |edge, path|
                world = Na__Serializer.Na__Serializer__ToWorld(ctx, path)[:transform]
                curve = edge.curve
                if curve
                    key = [curve.persistent_id, path.map(&:persistent_id)]
                    next if seen[key]

                    seen[key] = true
                    vertices = curve.vertices
                    points = vertices.map { |vertex| na_world_xyz(vertex.position, world) }
                    points << points.first if curve.edges.length >= vertices.length && vertices.length > 2
                    runs << { points: points, material: curve.edges.first.material }
                else
                    loose[path.map(&:persistent_id)] << [edge, path, world]
                end
            end
            loose.each_value { |items| runs.concat(na_drape_chains(items)) }
            runs
        end

        def self.na_world_xyz(point, world)
            p = point.transform(world)
            [p.x.to_f, p.y.to_f, p.z.to_f]
        end

        # Loose edges of one context -> chains between vertices where other than two meet.
        def self.na_drape_chains(items)
            world = items.first[2]
            set = {}
            items.each { |edge, _path, _world| set[edge] = true }
            degree = lambda { |vertex| vertex.edges.count { |edge| set[edge] } }
            used = {}
            runs = []
            walk = lambda do |start, first|
                points = [na_world_xyz(start.position, world)]
                material = first.material
                vertex = start
                edge = first
                loop do
                    used[edge] = true
                    vertex = edge.other_vertex(vertex)
                    points << na_world_xyz(vertex.position, world)
                    break unless degree.call(vertex) == 2

                    edge = vertex.edges.find { |candidate| set[candidate] && !used[candidate] }
                    break unless edge
                end
                runs << { points: points, material: material }
            end
            items.each do |edge, _path, _world|
                edge.vertices.each do |vertex|
                    next if degree.call(vertex) == 2

                    vertex.edges.each { |candidate| walk.call(vertex, candidate) if set[candidate] && !used[candidate] }
                end
            end
            items.each { |edge, _path, _world| walk.call(edge.start, edge) unless used[edge] }
            runs
        end

        def self.na_drape_index(tris)
            sizes = tris.map { |t| [[t[0], t[3], t[6]].max - [t[0], t[3], t[6]].min, [t[1], t[4], t[7]].max - [t[1], t[4], t[7]].min].max }.sort
            cell = sizes[sizes.length / 2].to_f
            cell = 1.0 if cell < 1.0e-3
            cells = {}
            tris.each_with_index do |t, index|
                x0, x1 = [t[0], t[3], t[6]].minmax
                y0, y1 = [t[1], t[4], t[7]].minmax
                ((x0 / cell).floor..(x1 / cell).floor).each do |ix|
                    ((y0 / cell).floor..(y1 / cell).floor).each { |iy| (cells[[ix, iy]] ||= []) << index }
                end
            end
            { cell: cell, cells: cells }
        end

        def self.na_drape_candidates(grid, x0, y0, x1, y1)
            cell = grid[:cell]
            out = []
            ((x0 / cell).floor..(x1 / cell).floor).each do |ix|
                ((y0 / cell).floor..(y1 / cell).floor).each do |iy|
                    list = grid[:cells][[ix, iy]]
                    out.concat(list) if list
                end
            end
            out.uniq
        end

        # One run -> [pieces (arrays of [x, y, z]), length off the surface (inches)].
        def self.na_drape_run(points, tris, grid, lift)
            pieces = []
            current = nil
            off = 0.0
            points.each_cons(2) do |a, b|
                dx = b[0] - a[0]
                dy = b[1] - a[1]
                length = Math.sqrt(dx * dx + dy * dy)
                next if length < 1.0e-6

                candidates = na_drape_candidates(grid, [a[0], b[0]].min, [a[1], b[1]].min, [a[0], b[0]].max, [a[1], b[1]].max)
                ts = [0.0, 1.0]
                candidates.each do |index|
                    t = tris[index]
                    [[0, 3], [3, 6], [6, 0]].each do |i, j|
                        hit = Na__Handlers__Geometry.Na__Handlers__Geometry__SegmentCross(a[0], a[1], dx, dy, t[i], t[i + 1], t[j], t[j + 1])
                        ts << hit if hit
                    end
                end
                ts.sort!
                ts.each_cons(2) do |t0, t1|
                    next if (t1 - t0) * length < 1.0e-4

                    tm = 0.5 * (t0 + t1)
                    tri = na_drape_top(tris, candidates, a[0] + dx * tm, a[1] + dy * tm)
                    unless tri
                        off += (t1 - t0) * length
                        current = nil
                        next
                    end

                    x0 = a[0] + dx * t0
                    y0 = a[1] + dy * t0
                    x1 = a[0] + dx * t1
                    y1 = a[1] + dy * t1
                    q1 = [x1, y1, Na__Handlers__Geometry.Na__Handlers__Geometry__PlaneZ(tri, x1, y1) + lift]
                    if current && (current[-1][0] - x0).abs < 1.0e-6 && (current[-1][1] - y0).abs < 1.0e-6
                        current << q1
                    else
                        current = [[x0, y0, Na__Handlers__Geometry.Na__Handlers__Geometry__PlaneZ(tri, x0, y0) + lift], q1]
                        pieces << current
                    end
                end
            end
            [pieces, off]
        end

        # The highest triangle containing (x, y) in plan, or nil.
        def self.na_drape_top(tris, candidates, x, y)
            best = nil
            best_z = nil
            candidates.each do |index|
                t = tris[index]
                weights = Na__Handlers__Geometry.Na__Handlers__Geometry__Barycentric(t, x, y)
                next unless weights && weights.min > -1.0e-7

                z = weights[0] * t[2] + weights[1] * t[5] + weights[2] * t[8]
                next if best_z && z <= best_z

                best = t
                best_z = z
            end
            best
        end

        # Pure plan maths (tested offline in BridgeCore).
        # Segment (ax, ay) + t (dx, dy), t in (0, 1), against segment (ux, uy)-(vx, vy): t or nil.
        def self.Na__Handlers__Geometry__SegmentCross(ax, ay, dx, dy, ux, uy, vx, vy)
            ex = vx - ux
            ey = vy - uy
            den = dx * ey - dy * ex
            return nil if den.abs < 1.0e-12

            wx = ux - ax
            wy = uy - ay
            t = (wx * ey - wy * ex) / den
            s = (wx * dy - wy * dx) / den
            return nil if t <= 0.0 || t >= 1.0 || s < -1.0e-9 || s > 1.0 + 1.0e-9

            t
        end

        # Barycentric weights of (x, y) in triangle t (plan), or nil for a degenerate triangle.
        def self.Na__Handlers__Geometry__Barycentric(t, x, y)
            ax, ay, bx, by, cx, cy = t[0], t[1], t[3], t[4], t[6], t[7]
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            return nil if det.abs < 1.0e-12

            l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / det
            l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / det
            [l1, l2, 1.0 - l1 - l2]
        end

        # z of triangle t's plane at (x, y).
        def self.Na__Handlers__Geometry__PlaneZ(t, x, y)
            weights = self.Na__Handlers__Geometry__Barycentric(t, x, y)
            return t[2] unless weights

            weights[0] * t[2] + weights[1] * t[5] + weights[2] * t[8]
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
