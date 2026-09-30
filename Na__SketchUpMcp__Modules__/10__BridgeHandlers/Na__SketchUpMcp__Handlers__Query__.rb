# =============================================================================
# NA SKETCHUP MCP - HANDLERS - QUERY
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Query__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Query
# PURPOSE    : entity_query, entity_get, outliner_tree (all read-only)
# CREATED    : 2026
#
# TOKEN BUDGET:
# Agents pay for every byte returned. Queries are paginated (limit/offset with
# next_offset), concise by default, and report "truncated" with the fix when a
# walk hits its budget, rather than dumping a whole model into the context.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Query

# -----------------------------------------------------------------------------
# REGION | entity_query
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Query__EntityQuery(params, ctx)
            model = ctx[:model]
            limit, offset = Na__Params.Na__Params__Page(params)
            detailed = Na__Params.Na__Params__Enum(params, 'response_format', %w[concise detailed], 'concise') == 'detailed'
            filters = na_filters(params, model)
            budget = Na__Traversal.Na__Traversal__NewBudget
            matches = []
            total = 0

            each_candidate = lambda do |entity, container_path|
                next unless na_matches?(entity, filters)

                total += 1
                matches << [entity, container_path] if total > offset && matches.length < limit
            end

            scope_label = na_walk_scope(params, model, ctx, budget, &each_candidate)
            entities = matches.map { |entity, container_path| Na__Serializer.Na__Serializer__Summary(entity, ctx, container_path, detailed) }
            next_offset = offset + entities.length < total ? offset + entities.length : nil

            result = {
                'units' => ctx[:unit], 'scope' => scope_label, 'total' => total, 'returned' => entities.length,
                'offset' => offset, 'next_offset' => next_offset, 'entities' => entities,
                'summary' => "#{total} match#{total == 1 ? '' : 'es'}, #{entities.length} returned#{next_offset ? " (more from offset #{next_offset})" : ''}."
            }
            if budget[:truncated]
                result['truncated'] = true
                ctx[:warnings] << "Stopped after #{budget[:visited]} entities (budget). Narrow with parent_id, types, max_depth or recursive:false."
            end
            result
        end

        # Walks the selection or a container; yields |entity, container_path|. Returns a scope label.
        def self.na_walk_scope(params, model, ctx, budget)
            recursive = Na__Params.Na__Params__Boolean(params, 'recursive', false)
            max_depth = Na__Params.Na__Params__Integer(params, 'max_depth', 8, min: 0, max: 64)

            if Na__Params.Na__Params__Boolean(params, 'selection_only', false)
                active_path = Na__Coordinates.Na__Coordinates__ActivePath(model)
                model.selection.to_a.each do |entity|
                    yield(entity, active_path)
                    next unless recursive && Na__EntityResolver.Na__EntityResolver__IsInstance(entity)

                    Na__Traversal.Na__Traversal__Walk(entity.definition.entities, active_path + [entity], max_depth - 1, budget) { |child, path, _depth| yield(child, path) }
                end
                return 'selection'
            end

            container = Na__Coordinates.Na__Coordinates__ResolveContainer(
                model, params['parent_id'], Na__Params.Na__Params__IdArray(params, 'path', required: false), ctx[:warnings]
            )
            Na__Traversal.Na__Traversal__Walk(container[:entities], container[:path], max_depth, budget, recursive) do |entity, path, _depth|
                yield(entity, path)
            end
            container[:label]
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Filters
# -----------------------------------------------------------------------------

        def self.na_filters(params, model)
            attribute = Na__Params.Na__Params__Hash(params, 'attribute', nil)
            if attribute && !attribute['dictionary'].is_a?(String)
                raise Na__McpError.new('invalid_params', 'attribute.dictionary is required when filtering by attribute.', nil)
            end

            tag = params['tag']
            {
                types:           (Na__Params.Na__Params__Array(params, 'types', nil) || []).map(&:to_s),
                name_contains:   params['name_contains'] ? params['name_contains'].to_s.downcase : nil,
                definition_name: params['definition_name'],
                tag_layer:       tag.nil? ? nil : (Na__EntityResolver.Na__EntityResolver__IsUntagged(tag) ? model.layers[0] : (model.layers[tag.to_s] || :missing)),
                material:        params['material'],
                attribute:       attribute,
                visibility:      Na__Params.Na__Params__Enum(params, 'visibility', %w[all visible hidden], 'all')
            }
        end

        def self.na_matches?(entity, filters)
            return false unless na_type_matches?(entity, filters[:types])
            return false if filters[:name_contains] && !na_name_text(entity).include?(filters[:name_contains])
            return false if filters[:definition_name] && !(Na__EntityResolver.Na__EntityResolver__IsInstance(entity) && entity.definition.name == filters[:definition_name])
            return false if filters[:tag_layer] && !(entity.respond_to?(:layer) && entity.layer == filters[:tag_layer])
            return false if filters[:material] && !na_material_matches?(entity, filters[:material])
            return false if filters[:attribute] && !na_attribute_matches?(entity, filters[:attribute])

            case filters[:visibility]
            when 'visible' then !(entity.respond_to?(:hidden?) && entity.hidden?)
            when 'hidden' then entity.respond_to?(:hidden?) && entity.hidden?
            else true
            end
        end

        def self.na_type_matches?(entity, types)
            return true if types.empty?

            type_name = Na__EntityResolver.Na__EntityResolver__TypeName(entity)
            types.include?(type_name) ||
                (types.include?('Instance') && Na__EntityResolver.Na__EntityResolver__IsInstance(entity)) ||
                (types.include?('Dimension') && entity.is_a?(Sketchup::Dimension))
        end

        def self.na_name_text(entity)
            parts = []
            parts << entity.name.to_s if entity.respond_to?(:name)
            parts << entity.definition.name.to_s if Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
            parts.join(' ').downcase
        end

        def self.na_material_matches?(entity, material_filter)
            return false unless entity.respond_to?(:material)

            material = entity.material
            return material.nil? if Na__EntityResolver.Na__EntityResolver__IsNoMaterial(material_filter)

            material && (material.name == material_filter.to_s || material.display_name == material_filter.to_s)
        end

        def self.na_attribute_matches?(entity, attribute)
            dictionary = entity.attribute_dictionary(attribute['dictionary'])
            return false unless dictionary
            return true unless attribute['key']

            value = dictionary[attribute['key']]
            return false if value.nil?
            return true unless attribute.key?('value')

            value.to_s == attribute['value'].to_s
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | entity_get
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Query__EntityGet(params, ctx)
            model = ctx[:model]
            ids = Na__Params.Na__Params__IdArray(params, 'ids')
            if ids.length > 100
                raise Na__McpError.new('invalid_params', "entity_get takes at most 100 ids (got #{ids.length}).", 'Use entity_query for lists, entity_get for detail.')
            end

            explicit_path = Na__Params.Na__Params__IdArray(params, 'path', required: false)
            include_geometry = Na__Params.Na__Params__Boolean(params, 'include_geometry', false)
            include_attributes = Na__Params.Na__Params__Boolean(params, 'include_attributes', true)
            max_vertices = Na__Params.Na__Params__Integer(params, 'max_vertices', 200, min: 3,
                                                           max: Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'max_vertices_per_entity', 400).to_i)
            max_chars = Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'max_attribute_value_chars', 2000).to_i

            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, ids)
            details = entities.map do |entity|
                container_path = na_container_path_for(model, entity, explicit_path, ctx)
                record = Na__Serializer.Na__Serializer__Summary(entity, ctx, container_path, true)
                record['parent'] = container_path.empty? ? 'model root' : Na__Serializer.Na__Serializer__InstanceLabel(container_path.last)
                if include_geometry
                    geometry = Na__Serializer.Na__Serializer__Geometry(entity, ctx, container_path, max_vertices)
                    record['geometry'] = geometry if geometry
                end
                if include_attributes
                    attributes = Na__Serializer.Na__Serializer__AttributeDictionaries(entity, nil, nil, max_chars)
                    record['attributes'] = attributes unless attributes.empty?
                end
                na_add_non_drawing_facts(record, entity, ctx)
                record
            end
            { 'units' => ctx[:unit], 'entities' => details }
        end

        def self.na_container_path_for(model, entity, explicit_path, ctx)
            return Na__Serializer.Na__Serializer__ContainerPath(ctx, entity) unless explicit_path && !explicit_path.empty?

            path = Na__Coordinates.Na__Coordinates__PathFromIds(model, explicit_path)
            return path if !path.empty? && entity.parent == path.last.definition

            ctx[:warnings] << "path does not lead to the container of #{entity.persistent_id}; used its own path instead."
            Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
        end

        def self.na_add_non_drawing_facts(record, entity, ctx)
            case entity
            when Sketchup::ComponentDefinition
                record['description'] = entity.description.to_s
                record['is_group'] = entity.group?
                record['file'] = entity.path.to_s unless entity.path.to_s.empty?
                bounds = entity.bounds
                record['local_size'] = [bounds.width, bounds.height, bounds.depth].map { |extent| Na__Units.Na__Units__FromInches(extent, ctx[:unit]) } unless bounds.empty?
            when Sketchup::Material
                record['color'] = Na__EntityResolver.Na__EntityResolver__ColourToHex(entity.color)
                record['alpha'] = entity.alpha.round(4)
            when Sketchup::Layer
                record['visible'] = entity.visible?
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | outliner_tree
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Query__OutlinerTree(params, ctx)
            model = ctx[:model]
            max_depth = Na__Params.Na__Params__Integer(params, 'max_depth', 3, min: 0, max: 32)
            max_children = Na__Params.Na__Params__Integer(params, 'max_children', 100, min: 1, max: 1000)
            include_loose = Na__Params.Na__Params__Boolean(params, 'include_loose_counts', true)
            include_bounds = Na__Params.Na__Params__Boolean(params, 'include_bounds', false)
            parent_id = params.key?('parent_id') ? params['parent_id'] : 0
            container = Na__Coordinates.Na__Coordinates__ResolveContainer(model, parent_id, nil, ctx[:warnings])
            state = { nodes: 0, max_nodes: 3000, truncated: false }

            options = { max_depth: max_depth, max_children: max_children, include_loose: include_loose, include_bounds: include_bounds }
            children = na_tree_children(container[:entities], container[:path], 0, options, state, ctx)
            tree = { 'root' => container[:label], 'children' => children }
            tree['loose'] = na_loose_counts(container[:entities]) if include_loose
            tree['truncated'] = true if state[:truncated]
            tree['units'] = ctx[:unit] if include_bounds
            tree
        end

        def self.na_tree_children(entities, container_path, depth, options, state, ctx)
            instances = entities.select { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            nodes = []
            instances.first(options[:max_children]).each do |instance|
                if state[:nodes] >= state[:max_nodes]
                    state[:truncated] = true
                    break
                end

                state[:nodes] += 1
                nodes << na_tree_node(instance, container_path, depth, options, state, ctx)
            end
            nodes << { 'more_siblings' => instances.length - options[:max_children] } if instances.length > options[:max_children]
            nodes
        end

        def self.na_tree_node(instance, container_path, depth, options, state, ctx)
            node = { 'id' => instance.persistent_id, 'type' => Na__EntityResolver.Na__EntityResolver__TypeName(instance) }
            node['name'] = instance.name.to_s unless instance.name.to_s.empty?
            node['definition'] = instance.definition.name if instance.is_a?(Sketchup::ComponentInstance)
            tag = instance.layer
            node['tag'] = Na__EntityResolver.Na__EntityResolver__TagDisplayName(tag) if tag && tag != ctx[:model].layers[0]
            node['hidden'] = true if instance.hidden?
            node['locked'] = true if instance.locked?
            if options[:include_bounds]
                summary = Na__Serializer.Na__Serializer__Summary(instance, ctx, container_path, false)
                node['bounds'] = summary['bounds'] if summary['bounds']
            end

            child_entities = instance.definition.entities
            node['loose'] = na_loose_counts(child_entities) if options[:include_loose]
            if depth + 1 <= options[:max_depth]
                children = na_tree_children(child_entities, container_path + [instance], depth + 1, options, state, ctx)
                node['children'] = children unless children.empty?
            else
                nested = child_entities.count { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
                node['nested_instances_not_shown'] = nested if nested > 0
            end
            node
        end

        def self.na_loose_counts(entities)
            counts = Hash.new(0)
            entities.each do |entity|
                next if Na__EntityResolver.Na__EntityResolver__IsInstance(entity)

                counts[Na__EntityResolver.Na__EntityResolver__TypeName(entity)] += 1
            end
            counts
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Query
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
