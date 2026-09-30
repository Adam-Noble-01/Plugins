# =============================================================================
# NA SKETCHUP MCP - HANDLERS - SELECTION AND EDIT CONTEXT
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Selection__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Selection
# PURPOSE    : selection_get, selection_set, context_set
# CREATED    : 2026
#
# THE SELECTION IS THE USER'S POINTER:
# "Look at what I selected" is the most common way a user hands an agent the
# thing they mean, so selection_get is cheap and returns world-space summaries.
# The selection only ever holds entities of the ACTIVE context; to select inside
# a closed group the context has to be opened first (context_set).
#
# CONTEXT_SET:
# Model#active_path= (SketchUp 2020.0+) opens a group for editing exactly as a
# double-click does. The path must chain from the model root, so a single id is
# expanded to its full path first. Changing the context also changes which
# coordinates the API reports (see Na__Coordinates), which is why it is refused
# inside atomic batches.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Selection

# -----------------------------------------------------------------------------
# REGION | selection_get
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Selection__Get(params, ctx)
            model = ctx[:model]
            limit, offset = Na__Params.Na__Params__Page(params)
            detailed = Na__Params.Na__Params__Enum(params, 'response_format', %w[concise detailed], 'concise') == 'detailed'
            selected = model.selection.to_a
            active_path = Na__Coordinates.Na__Coordinates__ActivePath(model)

            types = Hash.new(0)
            selected.each { |entity| types[Na__EntityResolver.Na__EntityResolver__TypeName(entity)] += 1 }
            page = (selected[offset, limit] || []).map { |entity| Na__Serializer.Na__Serializer__Summary(entity, ctx, active_path, detailed) }
            result = {
                'units'       => ctx[:unit],
                'count'       => selected.length,
                'types'       => types,
                'returned'    => page.length,
                'offset'      => offset,
                'next_offset' => offset + page.length < selected.length ? offset + page.length : nil,
                'entities'    => page
            }
            bounds = Na__Serializer.Na__Serializer__WorldBoundsOfMany(selected, ctx)
            result['bounds'] = na_bounds_hash(bounds, ctx[:unit]) if bounds
            result['context'] = active_path.map { |instance| Na__Serializer.Na__Serializer__InstanceLabel(instance) } unless active_path.empty?
            result
        end

        def self.na_bounds_hash(bounds, unit)
            minimum, maximum = bounds
            {
                'min'  => minimum.map { |value| Na__Units.Na__Units__FromInches(value, unit) },
                'max'  => maximum.map { |value| Na__Units.Na__Units__FromInches(value, unit) },
                'size' => [0, 1, 2].map { |axis| Na__Units.Na__Units__FromInches(maximum[axis] - minimum[axis], unit) }
            }
        end

        def self.Na__Handlers__Selection__BoundsHash(bounds, unit)
            na_bounds_hash(bounds, unit)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | selection_set
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Selection__Set(params, ctx)
            model = ctx[:model]
            selection = model.selection
            action = Na__Params.Na__Params__Enum(params, 'action', %w[replace add remove toggle clear invert select_all], 'replace')

            case action
            when 'clear'
                selection.clear
            when 'invert'
                selection.invert
            when 'select_all'
                selection.clear
                selection.add(model.active_entities.to_a)
            else
                entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
                na_require_active_context(model, entities)
                selection.clear if action == 'replace'
                case action
                when 'replace', 'add' then selection.add(entities)
                when 'remove' then selection.remove(entities)
                when 'toggle' then selection.toggle(entities)
                end
            end

            { 'action' => action, 'count' => selection.length, 'summary' => "Selection now holds #{selection.length} entities." }
        end

        # SketchUp can only select entities of the active context.
        def self.na_require_active_context(model, entities)
            active_path = Na__Coordinates.Na__Coordinates__ActivePath(model)
            active_owner = active_path.empty? ? model : active_path.last.definition
            outside = entities.reject { |entity| entity.parent == active_owner }
            return if outside.empty?

            raise Na__McpError.new('context_error',
                                   "#{outside.length} of the entities are not in the active context (e.g. id #{outside.first.persistent_id}).",
                                   'Open their group first with context_set action "open", or select the group that contains them.')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | context_set
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Selection__ContextSet(params, ctx)
            model = ctx[:model]
            action = Na__Params.Na__Params__Enum(params, 'action', %w[open close close_all], nil, required: true)

            case action
            when 'open'
                instance = Na__EntityResolver.Na__EntityResolver__RequireInstance(model, Na__Params.Na__Params__Integer(params, 'id', nil, required: true))
                explicit = Na__Params.Na__Params__IdArray(params, 'path', required: false)
                path = explicit && !explicit.empty? ? Na__Coordinates.Na__Coordinates__PathFromIds(model, explicit) : nil
                path ||= Na__Coordinates.Na__Coordinates__ContainerPathForEntity(model, instance, ctx[:warnings]) + [instance]
                path << instance unless path.last == instance
                na_open_path(model, path)
            when 'close'
                model.close_active
            when 'close_all'
                model.active_path = nil
            end

            active_path = Na__Coordinates.Na__Coordinates__ActivePath(model)
            {
                'action'         => action,
                'active_context' => active_path.map { |entry| Na__Serializer.Na__Serializer__InstanceLabel(entry) },
                'summary'        => active_path.empty? ? 'Editing the model root.' : "Editing inside #{active_path.length} level(s)."
            }
        end

        def self.na_open_path(model, path)
            model.active_path = path
        rescue ArgumentError => error
            raise Na__McpError.new('context_error', "SketchUp refused to open that group: #{error.message}",
                                   'Locked instances (or locked copies of the same component) and Live Components cannot be opened.')
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Selection
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
