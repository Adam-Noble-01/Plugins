# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MEASURE
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Measure__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Measure
# PURPOSE    : geometry_measure: world bounds, areas, volumes, edge lengths,
#              point-to-point distances and ray tests
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
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Measure

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MEASURES = %w[bounds area volume length counts].freeze
        NA_RAY_STEP_INCHES = 0.01

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
