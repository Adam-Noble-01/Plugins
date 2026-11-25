# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MEASURE
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Measure__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Measure
# PURPOSE    : geometry_measure: world bounds, areas, volumes, edge lengths,
#              point-to-point distances and ray tests;
#              geometry_faces (1.0.41): world face loops, normals and planes
# CREATED    : 2026
#
# WORLD MEASUREMENTS, WHATEVER THE NESTING:
# - Face#area(transform) and Edge#length(transform) take the face's full
#   reported-to-world transform, so a face inside a scaled, rotated group three
#   deep reports its true world area.
# - A group/component id measures every face and edge inside it, each through
#   its own path (a component used twice inside the group is counted twice).
# - Volume is SketchUp's own Group/ComponentInstance#volume, which needs a
#   manifold solid; non-manifold ids are listed so the agent can fix them.
# - Model#raytest casts through the whole model; max_hits > 1 re-casts from just
#   beyond each hit to list what the ray passes through.
#
# GEOMETRY_FACES (1.0.41, Cooper 62712): the face loops agents wrote in
# ruby_eval on every whitecard job. Each face is read through its own path's
# reported-to-world transform (Na__Serializer__ToWorld), so faces inside moved,
# rotated, scaled and nested groups come back in true world positions, with the
# world normal (inverse transpose) and the plane's offset (normal . point).
# What is read is what SketchUp shows (Na__Handlers__PointCloud.na_shown?)
# unless include_hidden; the ids themselves are read even when hidden.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Measure

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MEASURES = %w[bounds area volume length counts].freeze
        NA_RAY_STEP_INCHES = 0.01

        # geometry_faces: how a face meets the box, how many come back, and the box's slack (inches).
        NA_FACE_BOX_MODES = %w[overlap inside].freeze
        NA_FACES_DEFAULT = 500
        NA_FACES_LIMIT = 5000
        NA_FACE_BOX_SLACK = 0.001
        NA_FACE_MAX_DEPTH = 64

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_measure
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Measure__Measure(params, ctx)
            model = ctx[:model]
            result = { 'units' => ctx[:unit] }
            ids = Na__Params.Na__Params__IdArray(params, 'ids', required: false)
            points = Na__Params.Na__Params__Array(params, 'points', nil, min_items: 2, max_items: 1000)
            ray = Na__Params.Na__Params__Hash(params, 'raytest', nil)

            if ids.nil? && points.nil? && ray.nil?
                raise Na__McpError.new('invalid_params', 'Nothing to measure.', 'Pass ids (entities), points (a polyline) and/or raytest.')
            end

            result['entities'] = na_measure_entities(model, ids, params, ctx) if ids
            result['points'] = na_measure_points(points, ctx[:unit]) if points
            result['raytest'] = na_raytest(model, ray, ctx) if ray
            result
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entities
# -----------------------------------------------------------------------------

        def self.na_measure_entities(model, ids, params, ctx)
            measures = Na__Params.Na__Params__Array(params, 'measure', %w[bounds area volume])
            unknown = measures - NA_MEASURES
            raise Na__McpError.new('invalid_params', "Unknown measure(s): #{unknown.join(', ')}.", "Use: #{NA_MEASURES.join(', ')}.") unless unknown.empty?

            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, ids)
            unit = ctx[:unit]
            output = { 'count' => entities.length }

            if measures.include?('bounds')
                bounds = Na__Serializer.Na__Serializer__WorldBoundsOfMany(entities, ctx)
                output['bounds'] = Na__Handlers__Selection.Na__Handlers__Selection__BoundsHash(bounds, unit) if bounds
            end

            if (measures & %w[area length counts]).any?
                totals = na_face_and_edge_totals(entities, ctx)
                output['area'] = Na__Units.Na__Units__AreaFromSquareInches(totals[:area], unit) if measures.include?('area')
                output['area_unit'] = Na__Units.Na__Units__AreaUnitLabel(unit) if measures.include?('area')
                output['edge_length'] = Na__Units.Na__Units__FromInches(totals[:length], unit) if measures.include?('length')
                output['counts'] = { 'faces' => totals[:faces], 'edges' => totals[:edges] } if measures.include?('counts')
                output['truncated'] = true if totals[:truncated]
            end

            na_add_volumes(output, entities, ctx) if measures.include?('volume')
            output
        end

        def self.na_face_and_edge_totals(entities, ctx)
            totals = { area: 0.0, length: 0.0, faces: 0, edges: 0, truncated: false }
            budget = Na__Traversal.Na__Traversal__NewBudget

            add_element = lambda do |element, container_path|
                world = Na__Serializer.Na__Serializer__ToWorld(ctx, container_path)
                if element.is_a?(Sketchup::Face)
                    totals[:area] += element.area(world[:transform])
                    totals[:faces] += 1
                elsif element.is_a?(Sketchup::Edge)
                    totals[:length] += element.length(world[:transform])
                    totals[:edges] += 1
                end
            end

            entities.each do |entity|
                container_path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                if Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    Na__Traversal.Na__Traversal__Walk(entity.definition.entities, container_path + [entity], 64, budget) do |child, child_path, _depth|
                        add_element.call(child, child_path)
                    end
                else
                    add_element.call(entity, container_path)
                end
            end
            totals[:truncated] = budget[:truncated]
            totals
        end

        def self.na_add_volumes(output, entities, ctx)
            unit = ctx[:unit]
            volume = 0.0
            not_manifold = []
            solids = entities.select { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            solids.each do |instance|
                unless instance.manifold?
                    not_manifold << instance.persistent_id
                    next
                end

                world = Na__Serializer.Na__Serializer__ToWorld(ctx, Na__Serializer.Na__Serializer__ContainerPath(ctx, instance))
                volume += instance.volume.to_f * Na__LinearMath.Na__LinearMath__Determinant(world[:columns]).abs
            end
            output['volume'] = Na__Units.Na__Units__VolumeFromCubicInches(volume, unit)
            output['volume_unit'] = Na__Units.Na__Units__VolumeUnitLabel(unit)
            return if not_manifold.empty?

            output['not_manifold_ids'] = not_manifold
            ctx[:warnings] << "#{not_manifold.length} group(s)/component(s) are not solid (manifold), so they have no volume. " \
                              'Check them with geometry_edit or fix holes/internal faces first.'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | geometry_faces (1.0.41)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Measure__Faces(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            roots = na_face_roots(model, params, ctx)
            box = na_face_box(params, unit)
            box_mode = Na__Params.Na__Params__Enum(params, 'box_mode', NA_FACE_BOX_MODES, 'overlap')
            facing = Na__Params.Na__Params__Has(params, 'facing') ? Na__Units.Na__Units__Direction(params['facing'], 'facing').to_a.map(&:to_f) : nil
            tolerance = Na__Params.Na__Params__Number(params, 'facing_tolerance', 5.0, min: 0.0, max: 90.0)
            min_dot = Math.cos(Na__Units.Na__Units__Radians(tolerance)) - 1.0e-9
            include_hidden = Na__Params.Na__Params__Boolean(params, 'include_hidden', false)
            include_holes = Na__Params.Na__Params__Boolean(params, 'include_holes', true)
            max_faces = Na__Params.Na__Params__Integer(params, 'max_faces', NA_FACES_DEFAULT, min: 1, max: NA_FACES_LIMIT)

            budget = Na__Traversal.Na__Traversal__NewBudget
            seen = {}
            faces = []
            counts = { scanned: 0, matched: 0 }
            roots.each do |root, root_path|
                na_each_face(root, root_path, include_hidden, budget) do |face, path, part|
                    key = [face.persistent_id] + path.map(&:persistent_id)
                    next if seen[key]

                    seen[key] = true
                    counts[:scanned] += 1
                    world = Na__Serializer.Na__Serializer__ToWorld(ctx, path)
                    outer = face.outer_loop.vertices.map { |vertex| (world[:transform] * vertex.position).to_a.map(&:to_f) }
                    next if box && !na_face_in_box?(outer, box, box_mode)

                    normal = Na__Serializer.Na__Serializer__WorldNormal(face.normal, world)
                    next if facing && Na__LinearMath.Na__LinearMath__Dot(normal, facing) < min_dot

                    counts[:matched] += 1
                    next if faces.length >= max_faces

                    faces << na_face_out(face, root, path, part, outer, normal, world, unit, include_holes)
                end
            end

            truncated = counts[:matched] > faces.length
            ctx[:warnings] << "Only the first #{faces.length} of #{counts[:matched]} matching faces came back: pass a box, facing or a higher max_faces." if truncated
            ctx[:warnings] << 'The traversal budget ran out, so some faces were not read: name fewer or smaller solids.' if budget[:truncated]
            {
                'units'     => unit,
                'area_unit' => Na__Units.Na__Units__AreaUnitLabel(unit),
                'scanned'   => counts[:scanned],
                'matched'   => counts[:matched],
                'returned'  => faces.length,
                'truncated' => truncated || budget[:truncated],
                'faces'     => faces,
                'summary'   => "#{counts[:matched]} of #{counts[:scanned]} faces matched in #{roots.length} solid#{roots.length == 1 ? '' : 's'}" \
                               "#{truncated ? " (#{faces.length} returned)" : ''}."
            }
        end

        # [[entity, container_path]] from ids (groups, components, faces) and names
        # (Outliner names of groups and components at any depth; * and ? match).
        def self.na_face_roots(model, params, ctx)
            ids = Na__Params.Na__Params__IdArray(params, 'ids', required: false)
            names = Na__Params.Na__Params__Array(params, 'names', nil, max_items: 200)
            if ids.nil? && names.nil?
                raise Na__McpError.new('invalid_params', 'Nothing to read.', 'Pass ids (groups, components or faces) and/or names (Outliner names).')
            end

            roots = []
            (ids ? Na__EntityResolver.Na__EntityResolver__RequireEntities(model, ids) : []).each do |entity|
                unless entity.is_a?(Sketchup::Face) || Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    raise Na__McpError.new('invalid_params', "id #{entity.persistent_id} is a #{Na__EntityResolver.Na__EntityResolver__TypeName(entity)}: geometry_faces reads groups, components and faces.",
                                           'Pass the group or component that holds it.')
                end
                roots << [entity, Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)]
            end
            roots.concat(na_named_roots(model, names)) if names
            roots
        end

        def self.na_named_roots(model, names)
            patterns = names.map(&:to_s)
            found = Hash.new { |hash, key| hash[key] = [] }
            budget = Na__Traversal.Na__Traversal__NewBudget
            Na__Traversal.Na__Traversal__Walk(model.entities, [], NA_FACE_MAX_DEPTH, budget) do |entity, path, _depth|
                next unless Na__EntityResolver.Na__EntityResolver__IsInstance(entity)

                name = entity.name.to_s
                patterns.each do |pattern|
                    hit = pattern.include?('*') || pattern.include?('?') ? File.fnmatch(pattern, name) : pattern == name
                    found[pattern] << [entity, path] if hit
                end
            end
            missing = patterns.reject { |pattern| found.key?(pattern) }
            unless missing.empty?
                raise Na__McpError.new('not_found', "No group or component is named #{missing.map { |name| "'#{name}'" }.join(', ')}.",
                                       'Find names with entity_query or outliner_tree (in names a * matches any characters), or pass ids.')
            end
            patterns.flat_map { |pattern| found[pattern] }
        end

        # box {min, max} in the call's units -> [min, max] in inches, or nil.
        def self.na_face_box(params, unit)
            box = Na__Params.Na__Params__Hash(params, 'box', nil)
            return nil unless box

            minimum = Na__Units.Na__Units__Point(Na__Params.Na__Params__Required(box, 'min'), unit, 'box.min').to_a.map(&:to_f)
            maximum = Na__Units.Na__Units__Point(Na__Params.Na__Params__Required(box, 'max'), unit, 'box.max').to_a.map(&:to_f)
            bad = (0..2).select { |axis| minimum[axis] > maximum[axis] }
            unless bad.empty?
                raise Na__McpError.new('invalid_params', "box.min is above box.max on #{bad.map { |axis| %w[x y z][axis] }.join(', ')}.",
                                       'Give box as {min: [smallest x, y, z], max: [largest x, y, z]}.')
            end
            [minimum, maximum]
        end

        # overlap: the face's world box meets the box; inside: every outer vertex is in it.
        def self.na_face_in_box?(points, box, mode)
            minimum, maximum = box
            if mode == 'inside'
                return points.all? { |point| (0..2).all? { |axis| point[axis] >= minimum[axis] - NA_FACE_BOX_SLACK && point[axis] <= maximum[axis] + NA_FACE_BOX_SLACK } }
            end

            (0..2).all? do |axis|
                values = points.map { |point| point[axis] }
                values.max >= minimum[axis] - NA_FACE_BOX_SLACK && values.min <= maximum[axis] + NA_FACE_BOX_SLACK
            end
        end

        # Yields |face, container_path, part names| for a face root, or every shown face inside
        # an instance root (64 deep at most), within the traversal budget.
        def self.na_each_face(root, root_path, include_hidden, budget, &block)
            if root.is_a?(Sketchup::Face)
                yield(root, root_path, [])
                return
            end

            na_walk_faces(root.definition.entities, root_path + [root], [], include_hidden, budget, 0, &block)
        end

        def self.na_walk_faces(entities, path, part, include_hidden, budget, depth, &block)
            entities.each do |entity|
                if budget[:remaining] <= 0
                    budget[:truncated] = true
                    return
                end

                budget[:remaining] -= 1
                budget[:visited] += 1
                next unless include_hidden || Na__Handlers__PointCloud.na_shown?(entity)

                if entity.is_a?(Sketchup::Face)
                    yield(entity, path, part)
                elsif depth < NA_FACE_MAX_DEPTH && Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    na_walk_faces(entity.definition.entities, path + [entity], part + [Na__EntityResolver.Na__EntityResolver__DisplayName(entity)],
                                  include_hidden, budget, depth + 1, &block)
                    return if budget[:truncated]
                end
            end
        end

        def self.na_face_out(face, root, path, part, outer, normal, world, unit, include_holes)
            to_unit = ->(point) { point.map { |value| Na__Units.Na__Units__FromInches(value, unit) } }
            out = {
                'id'           => face.persistent_id,
                'root_id'      => root.persistent_id,
                'container_id' => path.empty? ? nil : path.last.persistent_id,
                'part'         => part.empty? ? nil : part.join(' > '),
                'normal'       => normal,
                'plane_offset' => Na__Units.Na__Units__FromInches(Na__LinearMath.Na__LinearMath__Dot(normal, outer.first), unit),
                'area'         => Na__Units.Na__Units__AreaFromSquareInches(face.area(world[:transform]), unit),
                'outer'        => outer.map { |point| to_unit.call(point) }
            }
            if include_holes
                holes = face.loops.reject(&:outer?).map do |loop|
                    loop.vertices.map { |vertex| to_unit.call((world[:transform] * vertex.position).to_a.map(&:to_f)) }
                end
                out['holes'] = holes unless holes.empty?
            end
            out['material'] = face.material.display_name if face.material
            out['back_material'] = face.back_material.display_name if face.back_material
            out['tag'] = Na__EntityResolver.Na__EntityResolver__TagDisplayName(face.layer) if face.layer && face.layer != face.model.layers[0]
            out
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Points
# -----------------------------------------------------------------------------

        def self.na_measure_points(points, unit)
            positions = points.each_with_index.map { |values, index| Na__Units.Na__Units__Point(values, unit, "points[#{index}]") }
            segments = positions.each_cons(2).map { |start_point, end_point| start_point.distance(end_point).to_f }
            {
                'segments'  => segments.map { |length| Na__Units.Na__Units__FromInches(length, unit) },
                'total'     => Na__Units.Na__Units__FromInches(segments.sum, unit),
                'straight'  => Na__Units.Na__Units__FromInches(positions.first.distance(positions.last).to_f, unit)
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ray Test
# -----------------------------------------------------------------------------

        def self.na_raytest(model, ray, ctx)
            unit = ctx[:unit]
            origin = Na__Units.Na__Units__Point(ray['origin'], unit, 'raytest.origin')
            direction = Na__Units.Na__Units__Direction(ray['direction'], 'raytest.direction')
            wysiwyg = ray.key?('include_hidden') ? !ray['include_hidden'] : true
            max_hits = Na__Params.Na__Params__Integer(ray, 'max_hits', 1, min: 1, max: 50)

            hits = []
            start = origin
            max_hits.times do
                result = model.raytest([start, direction], wysiwyg)
                break unless result

                point, path = result
                leaf = path.last
                hits << {
                    'point'    => Na__Units.Na__Units__PointOut(point, unit),
                    'distance' => Na__Units.Na__Units__FromInches(origin.distance(point).to_f, unit),
                    'entity'   => leaf ? { 'id' => leaf.persistent_id, 'type' => Na__EntityResolver.Na__EntityResolver__TypeName(leaf) } : nil,
                    'path'     => path[0..-2].map { |instance| instance.persistent_id }
                }
                start = point.offset(direction, NA_RAY_STEP_INCHES)
            end
            { 'origin' => Na__Units.Na__Units__PointOut(origin, unit), 'direction' => Na__Units.Na__Units__DirectionOut(direction),
              'hits' => hits, 'hit' => !hits.empty? }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Measure
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
