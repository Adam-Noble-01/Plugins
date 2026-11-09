# =============================================================================
# NA SKETCHUP MCP - HANDLERS - ENTITY EDIT
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__EntityEdit__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__EntityEdit
# PURPOSE    : entity_transform (move, rotate, scale, mirror, copy, array),
#              entity_delete, entity_set_properties, entity_reparent (1.0.18)
# CREATED    : 2026
#
# ONE WORLD TRANSFORM, CARRIED INTO EACH CONTAINER:
# The operation list is composed into a single world-space transformation Tw.
# Each entity then receives W^-1 * Tw * W, where W is its container's
# reported-to-world transform (Na__Coordinates). Groups and components use
# #transform!; loose geometry uses Entities#transform_entities on its own
# collection. So "rotate 90 degrees about the world Z through this point" means
# exactly that, for a face at the root or a group three levels deep inside a
# rotated, open parent.
#
# COPIES AND ARRAYS:
# copies:N applies the sequence cumulatively to N new copies (T, T^2, ... T^N),
# like SketchUp's Move with Ctrl then typing "5x". Groups copy with Group#copy;
# components get a new instance of the same definition with the same name, tag,
# material, shadow flags and attributes.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__EntityEdit

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_TYPES = %w[translate move_to rotate scale mirror].freeze
        NA_ANCHORS = %w[origin bounds_min bounds_center bounds_bottom_center].freeze
        NA_PROPERTY_KEYS = %w[name tag hidden locked casts_shadows receives_shadows soft smooth].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | entity_transform
# -----------------------------------------------------------------------------

        def self.Na__Handlers__EntityEdit__Transform(params, ctx)
            model = ctx[:model]
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
            operations = Na__Params.Na__Params__Array(params, 'operations', nil, required: true, min_items: 1, max_items: 50)
            copies = Na__Params.Na__Params__Integer(params, 'copies', 0, min: 0, max: 1000)
            copies = 1 if copies.zero? && Na__Params.Na__Params__Boolean(params, 'copy', false)

            na_refuse_open_and_nested(model, entities, ctx)
            bounds = Na__Serializer.Na__Serializer__WorldBoundsOfMany(entities, ctx)
            raise Na__McpError.new('invalid_params', 'Those entities have no extent to transform.', nil) unless bounds

            world = na_compose(operations, bounds, entities, ctx)
            if copies.zero?
                na_apply_world_transform(entities, world, ctx)
                result = { 'transformed' => entities.length, 'ids' => entities.map(&:persistent_id) }
                moved = entities
            else
                created = na_make_copies(entities, world, copies, ctx)
                result = { 'copies_created' => created.length, 'ids' => created.map(&:persistent_id) }
                moved = created
            end

            after = Na__Serializer.Na__Serializer__WorldBoundsOfMany(moved, ctx.merge(to_world_cache: {}, path_cache: {}))
            result['bounds_after'] = Na__Handlers__Selection.Na__Handlers__Selection__BoundsHash(after, ctx[:unit]) if after
            result['units'] = ctx[:unit]
            result['summary'] = copies.zero? ? "Transformed #{entities.length} entit(ies)." : "Made #{result['copies_created']} transformed cop(ies)."
            result
        end

        def self.na_refuse_open_and_nested(model, entities, ctx)
            open = entities.find { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) && Na__Coordinates.Na__Coordinates__InstanceIsOpen(model, entity) }
            if open
                raise Na__McpError.new('context_error', "Id #{open.persistent_id} is open for editing; SketchUp cannot move a group while you are inside it.",
                                       'Close it first with context_set action "close_all", or transform the geometry inside it instead.')
            end

            instances = entities.select { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            entities.each do |entity|
                path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                ancestor = (path & instances).first
                next unless ancestor

                raise Na__McpError.new('invalid_params', "Id #{entity.persistent_id} is inside id #{ancestor.persistent_id}, which is also being transformed.",
                                       'Pass only the outermost group; its contents move with it.')
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Composing the World Transformation
# -----------------------------------------------------------------------------

        def self.na_compose(operations, bounds, entities, ctx)
            unit = ctx[:unit]
            total = Geom::Transformation.new
            minimum, maximum = bounds
            centre = Geom::Point3d.new(*[0, 1, 2].map { |axis| (minimum[axis] + maximum[axis]) / 2.0 })

            operations.each_with_index do |operation, index|
                unless operation.is_a?(Hash) && NA_OPERATION_TYPES.include?(operation['type'])
                    raise Na__McpError.new('invalid_params', "operations[#{index}] needs a type: #{NA_OPERATION_TYPES.join(', ')}.", nil)
                end

                current_centre = total * centre
                step = case operation['type']
                       when 'translate' then Geom::Transformation.translation(Na__Units.Na__Units__Offset(Na__Params.Na__Params__Required(operation, 'vector'), unit, "operations[#{index}].vector"))
                       when 'move_to'   then na_move_to(operation, index, bounds, entities, total, ctx)
                       when 'rotate'    then na_rotation(operation, index, current_centre, unit)
                       when 'scale'     then na_scaling(operation, index, current_centre, unit)
                       when 'mirror'    then na_mirror(operation, index, current_centre, unit)
                       end
                total = step * total
            end
            total
        end

        def self.na_move_to(operation, index, bounds, entities, total, ctx)
            target = Na__Units.Na__Units__Point(Na__Params.Na__Params__Required(operation, 'position'), ctx[:unit], "operations[#{index}].position")
            anchor_name = Na__Params.Na__Params__Enum(operation, 'anchor', NA_ANCHORS, entities.length == 1 && Na__EntityResolver.Na__EntityResolver__IsInstance(entities.first) ? 'origin' : 'bounds_min')
            minimum, maximum = bounds
            anchor = case anchor_name
                     when 'origin'
                         unless entities.length == 1 && Na__EntityResolver.Na__EntityResolver__IsInstance(entities.first)
                             raise Na__McpError.new('invalid_params', "anchor 'origin' needs exactly one group/component.", "Use anchor 'bounds_min' or 'bounds_center'.")
                         end

                         world = Na__Serializer.Na__Serializer__ToWorld(ctx, Na__Serializer.Na__Serializer__ContainerPath(ctx, entities.first))
                         world[:transform] * entities.first.transformation.origin
                     when 'bounds_min' then Geom::Point3d.new(*minimum)
                     when 'bounds_center' then Geom::Point3d.new(*[0, 1, 2].map { |axis| (minimum[axis] + maximum[axis]) / 2.0 })
                     when 'bounds_bottom_center' then Geom::Point3d.new((minimum[0] + maximum[0]) / 2.0, (minimum[1] + maximum[1]) / 2.0, minimum[2])
                     end
            Geom::Transformation.translation((total * anchor).vector_to(target))
        end

        def self.na_centre_for(operation, key, default_centre, unit, label)
            operation[key] ? Na__Units.Na__Units__Point(operation[key], unit, label) : default_centre
        end

        def self.na_rotation(operation, index, default_centre, unit)
            angle = Na__Units.Na__Units__Radians(Na__Params.Na__Params__Number(operation, 'angle', nil, required: true))
            axis = Na__Units.Na__Units__Direction(operation['axis'] || [0, 0, 1], "operations[#{index}].axis")
            centre = na_centre_for(operation, 'center', default_centre, unit, "operations[#{index}].center")
            Geom::Transformation.rotation(centre, axis, angle)
        end

        def self.na_scaling(operation, index, default_centre, unit)
            factors = operation['factors']
            factors = [factors, factors, factors] if factors.is_a?(Numeric)
            unless factors.is_a?(Array) && factors.length == 3 && factors.all? { |factor| factor.is_a?(Numeric) && factor.to_f.abs > 1.0e-9 }
                raise Na__McpError.new('invalid_params', "operations[#{index}].factors must be a non-zero number or [sx, sy, sz].",
                                       'Zero would flatten the geometry (SketchUp 2026 refuses non-invertible transforms). Use mirror for negatives.')
            end

            centre = na_centre_for(operation, 'center', default_centre, unit, "operations[#{index}].center")
            Geom::Transformation.scaling(centre, *factors.map(&:to_f))
        end

        # Reflection through the plane with the given normal passing through center.
        def self.na_mirror(operation, index, default_centre, unit)
            normal = Na__Units.Na__Units__Direction(operation['normal'] || [1, 0, 0], "operations[#{index}].normal")
            centre = na_centre_for(operation, 'center', default_centre, unit, "operations[#{index}].center")
            frame = Geom::Transformation.axes(centre, *normal.axes)
            frame * Geom::Transformation.scaling(1.0, 1.0, -1.0) * frame.inverse
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Applying and Copying
# -----------------------------------------------------------------------------

        def self.na_apply_world_transform(entities, world_transformation, ctx)
            loose_by_container = Hash.new { |hash, key| hash[key] = [] }
            entities.each do |entity|
                path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
                to_world = Na__Serializer.Na__Serializer__ToWorld(ctx, path)[:transform]
                local = Na__Coordinates.Na__Coordinates__WorldTransformToReported(world_transformation, to_world)
                if Na__EntityResolver.Na__EntityResolver__IsInstance(entity) || entity.is_a?(Sketchup::Image)
                    entity.transform!(local)
                else
                    loose_by_container[[entity.parent, path.map(&:persistent_id)]] << [entity, local]
                end
            end

            loose_by_container.each_value do |pairs|
                owner = pairs.first.first.parent
                owner.entities.transform_entities(pairs.first.last, pairs.map(&:first))
            end
        end

        def self.na_make_copies(entities, world_transformation, copies, ctx)
            loose = entities.reject { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            unless loose.empty?
                raise Na__McpError.new('wrong_type', "Only groups and components can be copied (id #{loose.first.persistent_id} is a #{Na__EntityResolver.Na__EntityResolver__TypeName(loose.first)}).",
                                       'Group the loose geometry first with group_create.')
            end

            created = []
            step = Geom::Transformation.new
            copies.times do
                step = world_transformation * step
                entities.each do |entity|
                    duplicate = self.Na__Handlers__EntityEdit__Duplicate(entity)
                    na_apply_world_transform([duplicate], step, ctx)
                    created << duplicate
                end
            end
            created
        end

        # A faithful copy in the same parent: Group#copy, or a new instance of the definition.
        # Group#copy's documentation does not promise the name, tag or attributes, so both kinds
        # get them set explicitly: a copy of "Wall - North" must not show as "Group".
        def self.Na__Handlers__EntityEdit__Duplicate(instance)
            duplicate = if instance.is_a?(Sketchup::Group)
                            instance.copy
                        else
                            instance.parent.entities.add_instance(instance.definition, instance.transformation)
                        end
            duplicate.name = instance.name
            duplicate.layer = instance.layer
            duplicate.material = instance.material
            duplicate.casts_shadows = instance.casts_shadows?
            duplicate.receives_shadows = instance.receives_shadows?
            (instance.attribute_dictionaries || []).each do |dictionary|
                dictionary.each_pair { |key, value| duplicate.set_attribute(dictionary.name, key, value) }
            end
            duplicate
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | entity_delete
# -----------------------------------------------------------------------------

        def self.Na__Handlers__EntityEdit__Delete(params, ctx)
            model = ctx[:model]
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
            not_drawn = entities.reject { |entity| entity.is_a?(Sketchup::Drawingelement) }
            unless not_drawn.empty?
                raise Na__McpError.new('wrong_type', "Id #{not_drawn.first.persistent_id} is a #{Na__EntityResolver.Na__EntityResolver__TypeName(not_drawn.first)}, not model geometry.",
                                       'Remove materials with material_manage, tags with tag_manage, scenes with scene_manage, unused definitions with model_purge.')
            end

            open = entities.find { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) && Na__Coordinates.Na__Coordinates__InstanceIsOpen(model, entity) }
            raise Na__McpError.new('context_error', "Id #{open.persistent_id} is open for editing.", 'Close it with context_set first.') if open

            types = Hash.new(0)
            entities.each { |entity| types[Na__EntityResolver.Na__EntityResolver__TypeName(entity)] += 1 }
            entities.group_by(&:parent).each { |owner, members| owner.entities.erase_entities(members.select(&:valid?)) }
            noun = entities.length == 1 ? 'entity' : 'entities'
            { 'deleted' => entities.length, 'types' => types, 'summary' => "Deleted #{entities.length} #{noun}. Undo restores them." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | entity_set_properties
# -----------------------------------------------------------------------------

        def self.Na__Handlers__EntityEdit__SetProperties(params, ctx)
            model = ctx[:model]
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
            requested = NA_PROPERTY_KEYS.select { |key| params.key?(key) }
            if requested.empty?
                raise Na__McpError.new('invalid_params', 'No property to set.', "Pass any of: #{NA_PROPERTY_KEYS.join(', ')}. Paint with material_apply.")
            end

            layer = params.key?('tag') ? Na__EntityResolver.Na__EntityResolver__ResolveTag(model, params['tag'], true, ctx[:warnings]) : nil
            changed = Hash.new(0)
            entities.each do |entity|
                requested.each do |key|
                    changed[key] += 1 if na_set_property(entity, key, key == 'tag' ? layer : params[key])
                end
            end
            skipped = requested.select { |key| changed[key].zero? }
            ctx[:warnings] << "No entity accepted: #{skipped.join(', ')} (e.g. 'locked' is only for groups/components, 'soft' only for edges)." unless skipped.empty?
            { 'changed' => changed, 'entities' => entities.length }
        end

        def self.na_set_property(entity, key, value)
            case key
            when 'name'
                return false unless entity.respond_to?(:name=) && entity.is_a?(Sketchup::Drawingelement)

                entity.name = value.to_s
            when 'tag'
                return false unless entity.respond_to?(:layer=)

                entity.layer = value
            when 'hidden'
                return false unless entity.respond_to?(:hidden=)

                entity.hidden = value ? true : false
            when 'locked'
                return false unless entity.respond_to?(:locked=)

                entity.locked = value ? true : false
            when 'casts_shadows'
                return false unless entity.respond_to?(:casts_shadows=)

                entity.casts_shadows = value ? true : false
            when 'receives_shadows'
                return false unless entity.respond_to?(:receives_shadows=)

                entity.receives_shadows = value ? true : false
            when 'soft'
                return false unless entity.is_a?(Sketchup::Edge)

                entity.soft = value ? true : false
            when 'smooth'
                return false unless entity.is_a?(Sketchup::Edge)

                entity.smooth = value ? true : false
            end
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | entity_reparent (1.0.18)
# -----------------------------------------------------------------------------
#
# SketchUp has no call that moves an entity between contexts. Each group or
# component is placed again from its own definition in the destination, at the
# same world placement, given its name, tag, material, flags and instance
# attributes, and the original is erased. Measured on NP03 (09-Nov-2026): a
# group comes back as a Group (its definition, and that definition's
# attributes, carried over), a component keeps its definition, 0.0 mm shift.
#
# Refused: loose geometry (group it first), anything open for editing, an id
# inside another id, a source inside a component used more than once (moving
# it would take it out of every copy), a destination inside what moves, and a
# shared destination component.
#
# -----------------------------------------------------------------------------

        def self.Na__Handlers__EntityEdit__Reparent(params, ctx)
            model = ctx[:model]
            entities = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
            new_group = Na__Params.Na__Params__Hash(params, 'new_group', nil)
            unless params.key?('parent_id') || new_group
                raise Na__McpError.new('invalid_params', 'Say where they go: parent_id (0 = model root, else a group or component) or new_group.',
                                       'new_group {name, tag} makes a group (at the root unless parent_id says otherwise) and moves them into it.')
            end

            na_reparent_check_sources(model, entities)
            parent_id = params.key?('parent_id') ? params['parent_id'] : 0
            container = Na__Coordinates.Na__Coordinates__ResolveContainer(model, parent_id, params['path'], ctx[:warnings])
            na_reparent_check_destination(container[:owner], entities)

            destination = na_reparent_destination(model, container, new_group, ctx)
            moved = []
            unchanged = []
            worst_shift = 0.0
            entities.each do |entity|
                if entity.parent.respond_to?(:entities) && entity.parent.entities == destination[:entities]
                    unchanged << entity.persistent_id
                    next
                end

                result = na_reparent_one(model, entity, destination, ctx)
                worst_shift = [worst_shift, result.delete(:shift_mm)].max
                moved << result
            end

            if moved.any? { |entry| entry['type'] == 'Group' }
                ctx[:warnings] << 'Moved groups are new entities with new ids. Dimensions or text attached to points inside them, and scenes that hid them one by one, no longer refer to them.'
            end
            ctx[:warnings] << "Already in the destination, left as they were: #{unchanged.join(', ')}." unless unchanged.empty?
            if worst_shift > 0.01
                ctx[:warnings] << "Largest change in world placement: #{worst_shift.round(3)} mm (expected 0). Check the moved objects."
            end

            where = destination[:label].sub(/\Ainside /, '')
            result = { 'moved' => moved, 'ids' => moved.map { |entry| entry['id'] }, 'parent' => destination[:label],
                       'max_shift_mm' => worst_shift.round(4),
                       'summary' => "Moved #{moved.length} object(s) into #{where}#{unchanged.empty? ? '' : " (#{unchanged.length} already there)"}." }
            result['new_group_id'] = destination[:group].persistent_id if destination[:group]
            result
        end

        def self.na_reparent_check_sources(model, entities)
            loose = entities.reject { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            unless loose.empty?
                types = loose.map { |entity| Na__EntityResolver.Na__EntityResolver__TypeName(entity) }.uniq.join(', ')
                raise Na__McpError.new('wrong_type', "Only groups and components can be moved; #{loose.length} id(s) are #{types}.",
                                       'Wrap loose faces and edges in a group first (group_create, in their own context), then move the group.')
            end

            open = entities.find { |entity| Na__Coordinates.Na__Coordinates__InstanceIsOpen(model, entity) }
            raise Na__McpError.new('context_error', "Id #{open.persistent_id} is open for editing.", 'Close it with context_set first.') if open

            definitions = entities.map(&:definition)
            entities.each do |entity|
                parent = entity.parent
                next unless parent.is_a?(Sketchup::ComponentDefinition)

                if !parent.group? && parent.instances.length > 1
                    raise Na__McpError.new('shared_parent', "Id #{entity.persistent_id} is inside component '#{parent.name}', used #{parent.instances.length} times: moving it would take it out of every copy.",
                                           'Make that component unique first (component_manage make_unique), or move the whole component.')
                end
                if na_reparent_ancestors(parent).any? { |definition| definitions.include?(definition) }
                    raise Na__McpError.new('invalid_params', "Id #{entity.persistent_id} is inside another id in this call.",
                                           'Move the outer one only: what is inside it moves with it.')
                end
            end
        end

        def self.na_reparent_check_destination(owner, entities)
            return unless owner

            if entities.include?(owner) || entities.any? { |entity| entity.definition == owner.definition }
                raise Na__McpError.new('invalid_params', 'The destination is one of the objects being moved.', 'Choose another parent_id.')
            end
            if na_reparent_ancestors(owner.parent).any? { |definition| entities.map(&:definition).include?(definition) }
                raise Na__McpError.new('invalid_params', 'The destination is inside one of the objects being moved.', 'Choose a parent outside them.')
            end
            return if owner.definition.group? || owner.definition.instances.length <= 1

            raise Na__McpError.new('shared_parent', "The destination component '#{owner.definition.name}' is used #{owner.definition.instances.length} times: everything moved in would appear in every copy.",
                                   'Make it unique first (component_manage make_unique), or move into a group.')
        end

        # Every definition the given definition sits inside, through all of its instances.
        def self.na_reparent_ancestors(start, depth = 0, seen = {})
            return [] unless start.is_a?(Sketchup::ComponentDefinition) && depth < 64 && !seen[start]

            seen[start] = true
            found = [start]
            start.instances.each do |instance|
                found.concat(na_reparent_ancestors(instance.parent, depth + 1, seen))
            end
            found
        end

        def self.na_reparent_destination(model, container, new_group, ctx)
            return { entities: container[:entities], path: container[:path], to_world: container[:to_world], label: container[:label], group: nil } unless new_group

            name = new_group['name'].to_s.strip
            raise Na__McpError.new('invalid_params', 'new_group needs a name.', 'For example {"name": "Ground Floor", "tag": "90__Storey__GroundFloor"}.') if name.empty?

            group = container[:entities].add_group
            Na__Coordinates.Na__Coordinates__PinGroupToIdentity(group)
            group.name = name
            group.layer = Na__EntityResolver.Na__EntityResolver__ResolveTag(model, new_group['tag'], true, ctx[:warnings]) if new_group['tag']
            path = container[:path] + [group]
            { entities: group.entities, path: path, to_world: Na__Coordinates.Na__Coordinates__ReportedToWorld(model, path),
              label: "new group #{name.inspect} (id #{group.persistent_id}) in #{container[:label]}", group: group }
        end

        def self.na_reparent_one(model, entity, destination, ctx)
            source_path = Na__Coordinates.Na__Coordinates__ContainerPathForEntity(model, entity, ctx[:warnings])
            world = Na__Coordinates.Na__Coordinates__InstanceWorldPlacement(model, source_path, entity)
            instance = destination[:entities].add_instance(entity.definition, destination[:to_world].inverse * world)
            na_reparent_copy_properties(entity, instance)
            if entity.respond_to?(:glued_to) && entity.glued_to
                ctx[:warnings] << "#{Na__EntityResolver.Na__EntityResolver__DisplayName(entity)} (id #{entity.persistent_id}) was glued to a face; it no longer is, and any opening it cut is closed."
            end
            after = Na__Coordinates.Na__Coordinates__InstanceWorldPlacement(model, destination[:path], instance).to_a
            before = world.to_a
            shift_mm = (12..14).map { |index| (before[index].to_f - after[index].to_f).abs * 25.4 }.max     # Transformation#to_a: translation at 12-14 (inches)
            if (0..11).any? { |index| (before[index].to_f - after[index].to_f).abs > 1.0e-6 }
                ctx[:warnings] << "#{Na__EntityResolver.Na__EntityResolver__DisplayName(entity)} (id #{entity.persistent_id}): its rotation or scale changed in the move. Check it."
            end
            old_id = entity.persistent_id
            entity.erase!
            { 'from' => old_id, 'id' => instance.persistent_id, 'type' => Na__EntityResolver.Na__EntityResolver__TypeName(instance),
              'name' => Na__EntityResolver.Na__EntityResolver__DisplayName(instance), shift_mm: shift_mm.to_f }
        end

        def self.na_reparent_copy_properties(source, target)
            target.name = source.name.to_s
            target.layer = source.layer
            target.material = source.material
            target.hidden = source.hidden?
            target.casts_shadows = source.casts_shadows?
            target.receives_shadows = source.receives_shadows?
            (source.attribute_dictionaries || []).each do |dictionary|
                dictionary.each_pair { |key, value| target.set_attribute(dictionary.name, key, value) }
            end
            target.locked = source.locked?
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__EntityEdit
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
