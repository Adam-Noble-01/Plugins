# =============================================================================
# NA SKETCHUP MCP - HANDLERS - OFFSET BAND (geometry_offset_band)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__OffsetBand__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__OffsetBand
# PURPOSE    : Turn a rule into geometry in one call: a path (an edge Adam
#              drew, a terrace edge, a sketch_read clean_path) plus a list of
#              bands at parallel offsets from it, each a named solid (a wall, a
#              raised bed, a kerb, a path) or a line (a lawn edge, an edging)
# CREATED    : 12-Nov-2026 (1.0.30)
#
# THE CORRETT STANDARD IT WAS BUILT FOR (Adam's redraw, 12-Nov-2026):
#   path   = the terrace edge
#   wall   = from 0 to 1270, 0..200 high, hollow 150 (a ring wall)
#   bed    = from 150 to 1120, 0..120 high, end_inset [150, 150]
#   lawn   = line at 2300, z 0
#   (offline against his own geometry: wall IoU 0.98, bed IoU 0.976)
#   ends   = start_line on the terrace's straight edge, end_line on x 11790
#
# GEOMETRY:
# Offsets are true parallels in plan: straight runs are mitred, and the
# vertices of drawn arcs (fitted within arc_tolerance) move radially, so a
# band along an arc stays concentric. Every side face is a planar quad and
# faces meeting under soften_angle are softened and smoothed. Each solid must
# be manifold or the whole call is undone. Plan maths: Na__PlanGeometry.
#
# COORDINATES:
# path_points and every end line are world points (z of the path is ignored:
# bands carry their own z). One wrapper group (named by name) goes where
# parent_id says, pinned to the identity, and each band is a group inside it,
# pinned too, so points go in through Na__Creation (world -> reported).
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__OffsetBand

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_PATH_POINTS = 5000
        NA_MAX_BANDS       = 24

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_offset_band
# -----------------------------------------------------------------------------

        def self.Na__Handlers__OffsetBand__Build(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            path, closed = na_path(params, ctx)
            closed = Na__Params.Na__Params__Boolean(params, 'closed', closed)
            path.pop if closed && path.length > 2 && Na__PlanGeometry.na_dist(path.first, path.last) < 1.0e-6
            if path.length < 2 || (closed && path.length < 3)
                raise Na__McpError.new('invalid_params', 'The path needs at least two distinct points (three when closed).', nil)
            end

            sign = Na__Params.Na__Params__Enum(params, 'side', %w[left right], 'left') == 'right' ? -1.0 : 1.0
            arc_tolerance = Na__Units.Na__Units__PositiveLength(params.fetch('arc_tolerance', Na__Units.Na__Units__FromInches(1.0 / 25.4, unit)), unit, 'arc_tolerance')
            centres = Na__PlanGeometry.Na__PlanGeometry__ArcCentres(path, closed, arc_tolerance)
            caps = [na_end_line(params, 'start_line', unit), na_end_line(params, 'end_line', unit)]
            if closed && caps.any?
                raise Na__McpError.new('invalid_params', 'start_line / end_line are for an open path; a closed path makes rings.', 'Leave them out, or pass closed: false.')
            end

            bands = Na__Params.Na__Params__Array(params, 'bands', nil, required: true, min_items: 1, max_items: NA_MAX_BANDS)
            prepared = Na__Creation.Na__Creation__Prepare(params.merge('wrap_in' => 'group'), ctx, 'group')
            up = Na__Creation.Na__Creation__Direction([0, 0, 1], prepared, 'up', normal: true)
            built = bands.each_with_index.map do |band, index|
                na_build_band(band, index, path, closed, centres, caps, sign, prepared, up, ctx)
            end

            result = Na__Creation.Na__Creation__Finish(prepared, params, ctx, [], kind: 'Bands')
            result['bands'] = built
            result['path'] = { 'points' => path.length, 'closed' => closed, 'side' => sign > 0 ? 'left' : 'right',
                               'arc_vertices' => centres.compact.length,
                               'start' => na_out2(path.first, 0.0, unit), 'end' => na_out2(path.last, 0.0, unit) }
            result['summary'] = "#{built.length} band(s): " + built.map { |band| band['volume'] ? "#{band['name']} (#{band['volume']} #{Na__Units.Na__Units__VolumeUnitLabel(unit)})" : "#{band['name']} (line)" }.join(', ')
            result
        end

        # The path in world inches, 2D: from path points or from drawn edges (path_ids).
        def self.na_path(params, ctx)
            unit = ctx[:unit]
            has_points = Na__Params.Na__Params__Has(params, 'path_points')
            has_ids = Na__Params.Na__Params__Has(params, 'path_ids')
            if has_points == has_ids
                raise Na__McpError.new('invalid_params', 'Give the path as path_points (world points) or path_ids (edges, a curve or a group of edges), not both.',
                                       'sketch_read returns clean_path points you can pass as path_points.')
            end

            if has_points
                list = Na__Params.Na__Params__Array(params, 'path_points', nil, required: true, min_items: 2, max_items: NA_MAX_PATH_POINTS)
                points = list.each_with_index.map { |values, index| p = Na__Units.Na__Units__Point(values, unit, "path_points[#{index}]"); [p.x.to_f, p.y.to_f] }
                return [na_distinct(points), false]
            end

            sources = Na__EntityResolver.Na__EntityResolver__RequireEntities(ctx[:model], Na__Params.Na__Params__IdArray(params, 'path_ids', required: true), 'path_ids')
            sketch = Na__Handlers__SketchIntake.Na__Handlers__SketchIntake__WorldSketch(sources, ctx)
            chains = Na__PlanGeometry.Na__PlanGeometry__ChainSegments(sketch[:segments], 0.5 / 25.4)
            if chains.length != 1
                raise Na__McpError.new('invalid_params', "path_ids make #{chains.length} separate lines; a band needs one.",
                                       'Pass the edges of one connected line, or read them with sketch_read and pass one clean_path as path_points.')
            end

            [na_distinct(chains.first['points'].map { |p| [p[0], p[1]] }), chains.first['closed']]
        end

        # Path points closer than 0.5 mm are one point (rounded input can leave a hair-thin segment).
        def self.na_distinct(points)
            Na__PlanGeometry.Na__PlanGeometry__Dedupe(points, 0.5 / 25.4, false)
        end

        def self.na_end_line(params, key, unit)
            return nil unless Na__Params.Na__Params__Has(params, key)

            values = Na__Params.Na__Params__Array(params, key, nil, required: true, min_items: 2, max_items: 2)
            points = values.each_with_index.map { |item, index| p = Na__Units.Na__Units__Point(item, unit, "#{key}[#{index}]"); [p.x.to_f, p.y.to_f] }
            { line: points }
        end

        def self.na_build_band(band, index, path, closed, centres, caps, sign, prepared, up, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            label = "bands[#{index}]"
            raise Na__McpError.new('invalid_params', "#{label} must be an object.", nil) unless band.is_a?(Hash)

            name = Na__Params.Na__Params__String(band, 'name', nil, required: true)
            line_only = Na__Params.Na__Params__Boolean(band, 'line_only', false)
            insets = Array(band['end_inset'] || [0, 0]).first(2).map { |value| Na__Units.Na__Units__ToInches(value, unit, "#{label}.end_inset") }
            insets << insets.first while insets.length < 2
            edge_material = band['edge_material'] ? Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, band['edge_material'], ctx[:warnings]) : nil
            group = prepared[:entities].add_group
            Na__Coordinates.Na__Coordinates__PinGroupToIdentity(group)
            group.name = name
            to_reported = prepared[:input_to_reported]

            begin
                if line_only
                    at = sign * Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(band, 'at'), unit, "#{label}.at")
                    z = Na__Units.Na__Units__ToInches(band.fetch('z', 0), unit, "#{label}.z")
                    line = Na__PlanGeometry.Na__PlanGeometry__Dedupe(Na__PlanGeometry.Na__PlanGeometry__OffsetLine(path, at, closed, centres, caps, insets), 0.05 / 25.4, closed)
                    points = line.map { |p| to_reported * Geom::Point3d.new(p[0], p[1], z) }
                    points << points.first if closed
                    edges = Array(points.length > 2 ? group.entities.add_curve(points) : group.entities.add_edges(points)).compact
                    edges.each { |edge| edge.material = edge_material } if edge_material
                    return { 'name' => name, 'id' => group.persistent_id, 'kind' => 'line', 'edges' => edges.length,
                             'length' => Na__Units.Na__Units__FromInches(Na__PlanGeometry.Na__PlanGeometry__PolylineLength(line.map { |p| p + [0.0] }, closed), unit).round(1),
                             'start' => na_out2(line.first, z, unit), 'end' => na_out2(line.last, z, unit) }
                end

                from = sign * Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(band, 'from'), unit, "#{label}.from")
                to = sign * Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(band, 'to'), unit, "#{label}.to")
                z0 = Na__Units.Na__Units__ToInches(band.fetch('z0', 0), unit, "#{label}.z0")
                z1 = Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(band, 'z1'), unit, "#{label}.z1")
                raise Na__McpError.new('invalid_params', "#{label}: z1 must be above z0.", 'A solid band rises from z0 to z1.') unless z1 > z0 + 1.0e-6

                outline = Na__PlanGeometry.Na__PlanGeometry__BandOutline(path, from, to, closed, centres, caps, insets)
                holes = outline[:inner] ? [outline[:inner]] : []
                if Na__Params.Na__Params__Has(band, 'hollow')
                    if closed
                        raise Na__McpError.new('invalid_params', "#{label}: hollow is for an open path (a wall round a bed with ends).",
                                               'Round a closed path, give the two walls as two bands, e.g. from 0 to 150 and from 1120 to 1270.')
                    end

                    wall = Na__Units.Na__Units__PositiveLength(band['hollow'], unit, "#{label}.hollow")
                    low, high = [from, to].minmax
                    if high - low <= 2.0 * wall
                        raise Na__McpError.new('invalid_params', "#{label}: hollow #{band['hollow']} leaves nothing inside a band #{Na__Units.Na__Units__FromInches(high - low, unit).round(1)} wide.",
                                               'Make the band wider than twice the wall, or leave hollow out.')
                    end

                    inner = Na__PlanGeometry.Na__PlanGeometry__BandOutline(path, low + wall, high - wall, false, centres, caps, insets.map { |value| value + wall })
                    holes = [inner[:outer]]
                end
                ([outline[:outer]] + holes).each do |ring|
                    next unless Na__PlanGeometry.Na__PlanGeometry__SelfIntersects(ring)

                    raise Na__McpError.new('invalid_params', "#{label} (#{name}) folds over itself: an offset is larger than the path's tightest inside curve, or the end lines cross it.",
                                           'Use smaller offsets on the inside of the curve, smooth the path, or move the end lines.')
                end

                gap = 0.05 / 25.4
                outline[:outer] = Na__PlanGeometry.Na__PlanGeometry__Dedupe(outline[:outer], gap, true)
                holes = holes.map { |ring| Na__PlanGeometry.Na__PlanGeometry__Dedupe(ring, gap, true) }
                face = group.entities.add_face(outline[:outer].map { |p| to_reported * Geom::Point3d.new(p[0], p[1], z0) })
                raise Na__McpError.new('operation_failed', "#{label} (#{name}): SketchUp made no face from the outline.", 'Check the path and offsets.') unless face

                holes.each do |ring|
                    inner_face = group.entities.add_face(ring.map { |p| to_reported * Geom::Point3d.new(p[0], p[1], z0) })
                    inner_face.erase! if inner_face && inner_face.valid?
                end
                face = group.entities.grep(Sketchup::Face).max_by(&:area)
                Na__Creation.Na__Creation__OrientFace(face, up)
                Na__Creation.Na__Creation__PushPull(face, z1 - z0, prepared, ctx)

                angle = Na__Params.Na__Params__Number(band, 'soften_angle', 15.0, min: 0.0, max: 90.0)
                na_soften(group.entities, angle)
                group.entities.grep(Sketchup::Edge).each { |edge| edge.material = edge_material } if edge_material
                if band['material']
                    face_material = Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, band['material'], ctx[:warnings])
                    group.entities.grep(Sketchup::Face).each { |item| item.material = face_material }
                end
                unless group.manifold?
                    raise Na__McpError.new('operation_failed', "#{label} (#{name}) is not a closed solid, so nothing was built.",
                                           'Check the end lines meet the band cleanly and the offsets do not fold; the whole call was undone.')
                end

                # Group#volume is in its parent's units: inside a scaled container, scale it to world.
                parent_scale = Na__LinearMath.Na__LinearMath__Determinant(Na__Serializer.Na__Serializer__ToWorld(ctx, prepared[:path])[:columns]).abs
                out = { 'name' => name, 'id' => group.persistent_id, 'kind' => holes.empty? ? 'solid' : 'solid with hole', 'manifold' => true,
                        'volume' => Na__Units.Na__Units__VolumeFromCubicInches(group.volume * parent_scale, unit).round(3),
                        'plan_area' => Na__Units.Na__Units__AreaFromSquareInches(Na__PlanGeometry.Na__PlanGeometry__Area(outline[:outer]).abs -
                                                                                    holes.sum { |ring| Na__PlanGeometry.Na__PlanGeometry__Area(ring).abs }, unit).round(3),
                        'z' => [Na__Units.Na__Units__FromInches(z0, unit).round(1), Na__Units.Na__Units__FromInches(z1, unit).round(1)] }
                if outline[:lines]
                    out['near_line'] = { 'start' => na_out2(outline[:lines][:near].first, z0, unit), 'end' => na_out2(outline[:lines][:near].last, z0, unit) }
                    out['far_line'] = { 'start' => na_out2(outline[:lines][:far].first, z0, unit), 'end' => na_out2(outline[:lines][:far].last, z0, unit) }
                end
                out
            rescue ArgumentError => error
                raise Na__McpError.new('invalid_params', "#{label} (#{name}): #{error.message}.", 'Check the offsets, insets and end lines against the path.')
            end
        end

        def self.na_soften(entities, angle_degrees)
            limit = angle_degrees * Math::PI / 180.0
            entities.grep(Sketchup::Edge).each do |edge|
                faces = edge.faces
                next unless faces.length == 2 && faces[0].normal.angle_between(faces[1].normal) < limit

                edge.soft = true
                edge.smooth = true
            end
        end

        def self.na_out2(point, z, unit)
            Na__Units.Na__Units__PointOut(Geom::Point3d.new(point[0], point[1], z), unit).map { |value| value.round(1) + 0.0 }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__OffsetBand
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
