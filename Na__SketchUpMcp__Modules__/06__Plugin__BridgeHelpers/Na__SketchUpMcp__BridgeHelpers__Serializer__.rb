# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - SERIALIZER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__Serializer__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Serializer
# PURPOSE    : Describe SketchUp entities as compact, world-space JSON
# CREATED    : 2026
#
# OUTPUT CONTRACT:
# - Every position, bound and length is WORLD space in the call's unit, whatever
#   the nesting depth and whichever group is open (Na__Coordinates does the maths).
# - "concise" gives what an agent needs to choose its next call: id, type, name,
#   tag, material, world bounds. "detailed" adds placement, volume, counts,
#   attribute dictionary names and type-specific facts.
# - Nested entities carry "path": the persistent ids of the groups/components
#   from the model root down to the one that holds them.
# - Nothing here changes the model.
#
# =============================================================================

require 'time'

module Na__SketchUpMcp
    module Na__Serializer

# -----------------------------------------------------------------------------
# REGION | Per-Request Transform Cache
# -----------------------------------------------------------------------------

        def self.Na__Serializer__ToWorld(ctx, container_path)
            cache = (ctx[:to_world_cache] ||= {})
            key = container_path.map(&:persistent_id).join('/')
            cache[key] ||= begin
                to_world = Na__Coordinates.Na__Coordinates__ReportedToWorld(ctx[:model], container_path)
                { transform: to_world, columns: Na__Coordinates.Na__Coordinates__LinearColumns(to_world) }
            end
        end

        def self.Na__Serializer__ContainerPath(ctx, entity)
            cache = (ctx[:path_cache] ||= {})
            parent = entity.parent
            return [] if parent.nil? || parent.is_a?(Sketchup::Model)

            cache[parent] ||= Na__Coordinates.Na__Coordinates__ContainerPathForEntity(ctx[:model], entity, ctx[:warnings])
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Summary (concise / detailed)
# -----------------------------------------------------------------------------

        # container_path: nil -> discovered from the entity's parent.
        def self.Na__Serializer__Summary(entity, ctx, container_path = nil, detailed = false)
            container_path ||= self.Na__Serializer__ContainerPath(ctx, entity)
            world = self.Na__Serializer__ToWorld(ctx, container_path)
            unit = ctx[:unit]

            summary = { 'id' => na_persistent_id(entity), 'type' => Na__EntityResolver.Na__EntityResolver__TypeName(entity) }
            na_add_names(summary, entity)
            summary['path'] = container_path.map(&:persistent_id) unless container_path.empty?

            if entity.is_a?(Sketchup::Drawingelement)
                bounds = na_world_bounds_hash(self.Na__Serializer__TightWorldBounds(entity, ctx, world), unit)
                summary['bounds'] = bounds if bounds
                summary['hidden'] = true if entity.hidden?
                summary['tag'] = Na__EntityResolver.Na__EntityResolver__TagDisplayName(entity.layer) if entity.layer && entity.layer != ctx[:model].layers[0]
                summary['material'] = entity.material.name if na_paintable?(entity) && entity.material
            end

            na_add_type_facts(summary, entity, world, unit, ctx, detailed)
            summary
        end

        # {id, type, name} for a group/component, as used in paths and context lists.
        def self.Na__Serializer__InstanceLabel(instance)
            {
                'id'   => instance.persistent_id,
                'type' => Na__EntityResolver.Na__EntityResolver__TypeName(instance),
                'name' => Na__EntityResolver.Na__EntityResolver__DisplayName(instance)
            }
        end

        def self.na_paintable?(entity)
            entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge) || Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
        end

        def self.na_persistent_id(entity)
            entity.respond_to?(:persistent_id) ? entity.persistent_id : nil
        end

        def self.na_add_names(summary, entity)
            if Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                summary['name'] = entity.name.to_s unless entity.name.to_s.empty?
                summary['definition'] = entity.definition.name if entity.is_a?(Sketchup::ComponentInstance)
            elsif entity.respond_to?(:name) && !entity.is_a?(Sketchup::Drawingelement)
                summary['name'] = entity.name.to_s
            elsif entity.is_a?(Sketchup::SectionPlane) && entity.respond_to?(:name)
                summary['name'] = entity.name.to_s unless entity.name.to_s.empty?
            end
        end

        def self.na_add_type_facts(summary, entity, world, unit, ctx, detailed)
            case entity
            when Sketchup::Face
                summary['area'] = Na__Units.Na__Units__AreaFromSquareInches(entity.area(world[:transform]), unit)
                summary['normal'] = na_world_normal(entity.normal, world)
                if detailed
                    summary['vertex_count'] = entity.vertices.length
                    summary['holes'] = entity.loops.length - 1
                    summary['back_material'] = entity.back_material.name if entity.back_material
                end
            when Sketchup::Edge
                summary['length'] = Na__Units.Na__Units__FromInches(entity.length(world[:transform]), unit)
                if detailed
                    summary['soft'] = entity.soft?
                    summary['smooth'] = entity.smooth?
                    summary['face_count'] = entity.faces.length
                    summary['curve'] = na_curve_facts(entity.curve, world, unit) if entity.curve
                end
            when Sketchup::Group, Sketchup::ComponentInstance
                na_add_instance_facts(summary, entity, world, unit, ctx, detailed)
            when Sketchup::Text
                summary['text'] = entity.text.to_s[0, 200]
            when Sketchup::Dimension
                summary['text'] = entity.text.to_s
            when Sketchup::SectionPlane
                summary['active'] = entity.active?
            when Sketchup::Image
                summary['file'] = entity.path.to_s
            when Sketchup::ComponentDefinition
                summary['instances'] = entity.count_instances
            end
        end

        def self.na_add_instance_facts(summary, instance, world, unit, ctx, detailed)
            summary['locked'] = true if instance.locked?
            return unless detailed

            placement = world[:transform] * instance.transformation
            summary['placement'] = self.Na__Serializer__Placement(placement, unit)
            local_bounds = instance.definition.bounds
            unless local_bounds.empty?
                scale = summary['placement']['scale']
                summary['size'] = [local_bounds.width, local_bounds.height, local_bounds.depth].each_with_index.map do |extent, axis|
                    Na__Units.Na__Units__FromInches(extent.to_f * scale[axis], unit)
                end
            end
            summary['entity_count'] = instance.definition.entities.length
            summary['definition_instances'] = instance.definition.count_instances
            na_add_solid_facts(summary, instance, world, unit)
            dictionaries = self.Na__Serializer__AttributeDictionaryNames(instance)
            summary['attribute_dictionaries'] = dictionaries unless dictionaries.empty?
            summary['open_for_editing'] = true if Na__Coordinates.Na__Coordinates__InstanceIsOpen(ctx[:model], instance)
        end

        def self.na_add_solid_facts(summary, instance, world, unit)
            return unless instance.respond_to?(:manifold?)

            manifold = instance.manifold?
            summary['manifold'] = manifold
            return unless manifold

            parent_scale = Na__LinearMath.Na__LinearMath__Determinant(world[:columns]).abs
            summary['volume'] = Na__Units.Na__Units__VolumeFromCubicInches(instance.volume.to_f * parent_scale, unit)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Placement, Bounds, Directions
# -----------------------------------------------------------------------------

        def self.Na__Serializer__Placement(transformation, unit)
            parts = Na__Coordinates.Na__Coordinates__Decompose(transformation)
            {
                'origin'       => parts[:origin].map { |value| Na__Units.Na__Units__FromInches(value, unit) },
                'x_axis'       => parts[:axes][0].map { |value| value.round(6) + 0.0 },
                'y_axis'       => parts[:axes][1].map { |value| value.round(6) + 0.0 },
                'z_axis'       => parts[:axes][2].map { |value| value.round(6) + 0.0 },
                'scale'        => parts[:scale].map { |value| value.round(6) },
                'mirrored'     => parts[:mirrored],
                'rotation_xyz' => parts[:rotation_zyx_degrees].map { |value| value.round(4) + 0.0 }
            }
        end

        # Tight world box [min, max] in inches. A closed group/component uses its own definition box
        # through its full placement (re-boxing the parent-frame box of a group inside a rotated parent
        # inflated it - live test 30-Sep-2026); faces and edges use their vertices; anything else, and
        # an instance that is open for editing, uses its bounds in the parent frame.
        def self.Na__Serializer__TightWorldBounds(entity, ctx, world)
            transform = world[:transform]
            if Na__EntityResolver.Na__EntityResolver__IsInstance(entity) && !Na__Coordinates.Na__Coordinates__InstanceIsOpen(ctx[:model], entity)
                definition_bounds = entity.definition.bounds
                return nil if definition_bounds.empty?

                return Na__Coordinates.Na__Coordinates__WorldBoundsArrays(definition_bounds, transform * entity.transformation)
            end
            if entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
                points = entity.vertices.map { |vertex| (transform * vertex.position).to_a.map(&:to_f) }
                return [[0, 1, 2].map { |axis| points.map { |point| point[axis] }.min },
                        [0, 1, 2].map { |axis| points.map { |point| point[axis] }.max }]
            end
            Na__Coordinates.Na__Coordinates__WorldBoundsArrays(entity.bounds, transform)
        end

        def self.na_world_bounds_hash(corners, unit)
            return nil unless corners

            minimum, maximum = corners
            {
                'min'  => minimum.map { |value| Na__Units.Na__Units__FromInches(value, unit) },
                'max'  => maximum.map { |value| Na__Units.Na__Units__FromInches(value, unit) },
                'size' => [0, 1, 2].map { |axis| Na__Units.Na__Units__FromInches(maximum[axis] - minimum[axis], unit) }
            }
        end

        def self.Na__Serializer__WorldBoundsOfMany(entities, ctx)
            minimum = [Float::INFINITY] * 3
            maximum = [-Float::INFINITY] * 3
            entities.each do |entity|
                next unless entity.is_a?(Sketchup::Drawingelement)

                world = self.Na__Serializer__ToWorld(ctx, self.Na__Serializer__ContainerPath(ctx, entity))
                corners = self.Na__Serializer__TightWorldBounds(entity, ctx, world)
                next unless corners

                3.times do |axis|
                    minimum[axis] = [minimum[axis], corners[0][axis]].min
                    maximum[axis] = [maximum[axis], corners[1][axis]].max
                end
            end
            return nil if minimum.any?(&:infinite?)

            [minimum, maximum]
        end

        def self.na_world_normal(normal, world)
            reported = [normal.x.to_f, normal.y.to_f, normal.z.to_f]
            transformed = Na__LinearMath.Na__LinearMath__InverseTransposeTimesVector(world[:columns], reported) || reported
            Na__LinearMath.Na__LinearMath__Normalize(transformed).map { |value| value.round(6) + 0.0 }
        end

        def self.Na__Serializer__WorldNormal(normal, world)
            na_world_normal(normal, world)
        end

        def self.Na__Serializer__WorldPointOut(point, world, unit)
            Na__Units.Na__Units__PointOut(world[:transform] * point, unit)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Detail (entity_get include_geometry)
# -----------------------------------------------------------------------------

        def self.Na__Serializer__Geometry(entity, ctx, container_path, max_vertices)
            world = self.Na__Serializer__ToWorld(ctx, container_path)
            unit = ctx[:unit]

            case entity
            when Sketchup::Face
                loops = entity.loops.map do |loop|
                    points = loop.vertices.first(max_vertices).map { |vertex| self.Na__Serializer__WorldPointOut(vertex.position, world, unit) }
                    { 'outer' => loop.outer?, 'points' => points, 'truncated' => loop.vertices.length > max_vertices }
                end
                { 'loops' => loops }
            when Sketchup::Edge
                { 'start' => self.Na__Serializer__WorldPointOut(entity.start.position, world, unit),
                  'end'   => self.Na__Serializer__WorldPointOut(entity.end.position, world, unit) }
            when Sketchup::ConstructionPoint
                { 'position' => self.Na__Serializer__WorldPointOut(entity.position, world, unit) }
            when Sketchup::ConstructionLine
                { 'position'  => self.Na__Serializer__WorldPointOut(entity.position, world, unit),
                  'direction' => Na__Units.Na__Units__DirectionOut(Geom::Vector3d.new(*Na__LinearMath.Na__LinearMath__MatrixTimesVector(world[:columns], entity.direction.to_a))) }
            when Sketchup::Text
                { 'point' => self.Na__Serializer__WorldPointOut(entity.point, world, unit) }
            when Sketchup::DimensionLinear
                { 'start' => self.Na__Serializer__WorldPointOut(entity.start[1], world, unit),
                  'end'   => self.Na__Serializer__WorldPointOut(entity.end[1], world, unit) }
            when Sketchup::SectionPlane
                plane = entity.get_plane
                { 'plane' => plane.map { |value| value.to_f.round(6) } }
            when Sketchup::Image
                { 'origin' => self.Na__Serializer__WorldPointOut(entity.origin, world, unit),
                  'width'  => Na__Units.Na__Units__FromInches(entity.width, unit),
                  'height' => Na__Units.Na__Units__FromInches(entity.height, unit) }
            else
                nil
            end
        end

        def self.na_curve_facts(curve, world, unit)
            facts = { 'edge_count' => curve.edges.length }
            return facts unless curve.is_a?(Sketchup::ArcCurve)

            facts['arc'] = true
            facts['center'] = self.Na__Serializer__WorldPointOut(curve.center, world, unit)
            facts['radius'] = Na__Units.Na__Units__FromInches(curve.radius, unit)
            facts['start_angle'] = Na__Units.Na__Units__Degrees(curve.start_angle)
            facts['end_angle'] = Na__Units.Na__Units__Degrees(curve.end_angle)
            facts
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Attributes and JSON Safety
# -----------------------------------------------------------------------------

        def self.Na__Serializer__AttributeDictionaryNames(entity)
            dictionaries = entity.attribute_dictionaries
            return [] unless dictionaries

            dictionaries.map(&:name)
        end

        def self.Na__Serializer__AttributeDictionaries(entity, dictionary_filter, key_filter, max_chars)
            dictionaries = entity.attribute_dictionaries
            return {} unless dictionaries

            dictionaries.each_with_object({}) do |dictionary, result|
                next if dictionary_filter && dictionary.name != dictionary_filter

                values = {}
                dictionary.each_pair do |key, value|
                    next if key_filter && key != key_filter

                    values[key.to_s] = self.Na__Serializer__JsonSafe(value, max_chars)
                end
                result[dictionary.name] = values
            end
        end

        # Anything -> JSON-generatable. Geometry becomes arrays, colours hex, times ISO 8601.
        def self.Na__Serializer__JsonSafe(value, max_chars = 20000, depth = 0)
            return '...' if depth > 12

            case value
            when nil, true, false, Integer
                value
            when Float
                value.finite? ? value : value.to_s
            when String
                text = value.encoding == Encoding::UTF_8 ? value : value.dup.force_encoding(Encoding::UTF_8)
                text = text.scrub('?')
                text.length > max_chars ? text[0, max_chars] + " ...[#{text.length - max_chars} more chars]" : text
            when Symbol
                value.to_s
            when Array
                value.first(5000).map { |item| self.Na__Serializer__JsonSafe(item, max_chars, depth + 1) }
            when Hash
                value.first(5000).each_with_object({}) do |(key, item), result|
                    result[key.to_s] = self.Na__Serializer__JsonSafe(item, max_chars, depth + 1)
                end
            when Time
                value.iso8601
            when Geom::Point3d, Geom::Vector3d
                value.to_a.map(&:to_f)
            when Sketchup::Color
                Na__EntityResolver.Na__EntityResolver__ColourToHex(value)
            when Sketchup::Entity
                { 'entity' => Na__EntityResolver.Na__EntityResolver__TypeName(value), 'id' => na_persistent_id(value) }
            else
                value.respond_to?(:to_f) && value.is_a?(Numeric) ? value.to_f : value.to_s[0, max_chars]
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__Serializer
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
