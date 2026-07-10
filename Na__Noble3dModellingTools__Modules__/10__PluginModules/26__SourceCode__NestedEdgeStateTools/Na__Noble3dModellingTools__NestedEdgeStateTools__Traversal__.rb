# =============================================================================
# NA NOBLE3D MODELLING TOOLS - NESTED EDGE STATE TOOLS - TRAVERSAL
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__NestedEdgeStateTools__Traversal__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__NestedEdgeStateTools
# PURPOSE    : Traverse selected edges and nested editable containers safely
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__NestedEdgeStateTools

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_RECURSION_DEPTH = 64
        NA_SELECTION_REMAP_DICTIONARY = 'Na__NestedEdgeStateTools__TemporarySelectionRemap'.freeze
        NA_SELECTION_REMAP_KEY = 'Na__NestedEdgeStateTools__SelectionToken'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Traversal
# -----------------------------------------------------------------------------

        # FUNCTION | Process Supported Entities in the Active Selection
        # ------------------------------------------------------------
        def self.na_process_selection(selection, action_key)
            statistics = na_empty_statistics

            selection.to_a.each do |entity|
                na_process_entity(entity, action_key, statistics, 0, [], true)
            end

            statistics
        end
        # ------------------------------------------------------------

        # FUNCTION | Check Whether the Selection Requires Any Mutation
        # ------------------------------------------------------------
        def self.na_selection_requires_change?(selection, action_key)
            selection.to_a.any? do |entity|
                na_entity_requires_change?(entity, action_key, 0, [])
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Isolate the Active Editing Path Before Mutation
        # ------------------------------------------------------------
        def self.na_make_active_path_unique(model, selected_entities)
            active_path = model.active_path
            return selected_entities if active_path.nil? || active_path.empty?

            selection_tokens = na_mark_selection_for_remap(selected_entities)

            begin
                active_path.length.times do |path_index|
                    current_path = model.active_path
                    container = current_path && current_path[path_index]
                    raise 'The active editing path changed while preparing edge updates.' unless container
                    raise 'Cannot update edges inside a locked active editing path.' if container.locked?

                    container.make_unique
                end

                na_entities_with_remap_tokens(model.active_entities, selection_tokens)
            ensure
                na_clear_selection_remap_markers(selected_entities)
                na_clear_selection_remap_markers(model.active_entities.to_a)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Process One Edge or Container
        # ------------------------------------------------------------
        def self.na_process_entity(entity, action_key, statistics, depth, definition_stack, count_unsupported)
            return unless na_valid_entity?(entity)

            case entity
            when Sketchup::Edge
                na_process_edge(entity, action_key, statistics)
            when Sketchup::Group
                na_process_container(entity, action_key, statistics, depth, definition_stack)
            when Sketchup::ComponentInstance
                na_process_container(entity, action_key, statistics, depth, definition_stack)
            else
                statistics[:unsupported_selection_count] += 1 if count_unsupported
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Process One Editable Container Hierarchy
        # ------------------------------------------------------------
        def self.na_process_container(container, action_key, statistics, depth, definition_stack)
            if container.locked?
                statistics[:locked_container_count] += 1
                return
            end

            if depth > NA_MAX_RECURSION_DEPTH
                statistics[:depth_limit_count] += 1
                return
            end

            definition_id = na_container_definition_id(container)
            if definition_id && definition_stack.include?(definition_id)
                statistics[:cyclic_container_count] += 1
                return
            end

            if na_container_requires_change?(container, action_key, depth, definition_stack)
                container.make_unique
                statistics[:uniquified_container_count] += 1
            end

            next_definition_stack = definition_stack.dup
            unique_definition_id = na_container_definition_id(container)
            next_definition_stack << unique_definition_id if unique_definition_id

            statistics[:visited_container_count] += 1
            na_container_entities(container).to_a.each do |child_entity|
                na_process_entity(
                    child_entity,
                    action_key,
                    statistics,
                    depth + 1,
                    next_definition_stack,
                    false
                )
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Process One Edge and Record Its Outcome
        # ------------------------------------------------------------
        def self.na_process_edge(edge, action_key, statistics)
            statistics[:visited_edge_count] += 1

            case na_apply_edge_state(edge, action_key)
            when :changed
                statistics[:changed_edge_count] += 1
            else
                statistics[:unchanged_edge_count] += 1
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Mutation Preflight
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check Whether One Entity Requires Mutation
        # ------------------------------------------------------------
        def self.na_entity_requires_change?(entity, action_key, depth, definition_stack)
            return false unless na_valid_entity?(entity)
            return !na_edge_already_matches?(entity, action_key) if entity.is_a?(Sketchup::Edge)
            return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

            na_container_requires_change?(entity, action_key, depth, definition_stack)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check Whether a Container Branch Requires Mutation
        # ------------------------------------------------------------
        def self.na_container_requires_change?(container, action_key, depth, definition_stack)
            return false if container.locked?
            return false if depth > NA_MAX_RECURSION_DEPTH

            definition_id = na_container_definition_id(container)
            return false if definition_id && definition_stack.include?(definition_id)

            next_definition_stack = definition_stack.dup
            next_definition_stack << definition_id if definition_id

            na_container_entities(container).any? do |child_entity|
                na_entity_requires_change?(
                    child_entity,
                    action_key,
                    depth + 1,
                    next_definition_stack
                )
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Container Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Mark Selection for Identity-Safe Remapping
        # ------------------------------------------------------------
        def self.na_mark_selection_for_remap(selected_entities)
            selected_entities.each_with_index.map do |entity, selection_index|
                selection_token = [
                    'Na__NestedEdgeStateTools',
                    entity.object_id,
                    Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond),
                    selection_index
                ].join('__')

                entity.set_attribute(
                    NA_SELECTION_REMAP_DICTIONARY,
                    NA_SELECTION_REMAP_KEY,
                    selection_token
                )
                selection_token
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Find Marked Selection in Uniquified Entities
        # ------------------------------------------------------------
        def self.na_entities_with_remap_tokens(active_entities, selection_tokens)
            entities_by_token = {}
            active_entities.each do |entity|
                selection_token = entity.get_attribute(
                    NA_SELECTION_REMAP_DICTIONARY,
                    NA_SELECTION_REMAP_KEY
                )
                entities_by_token[selection_token] = entity if selection_token
            end

            selection_tokens.map do |selection_token|
                remapped_entity = entities_by_token[selection_token]
                raise 'Could not remap the selection after making the active editing path unique.' unless remapped_entity

                remapped_entity
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remove Temporary Selection Markers
        # ------------------------------------------------------------
        def self.na_clear_selection_remap_markers(entities)
            entities.each do |entity|
                next unless na_valid_entity?(entity)
                next unless entity.get_attribute(NA_SELECTION_REMAP_DICTIONARY, NA_SELECTION_REMAP_KEY)

                entity.delete_attribute(NA_SELECTION_REMAP_DICTIONARY)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return the Editable Entities for a Container
        # ------------------------------------------------------------
        def self.na_container_entities(container)
            return container.entities if container.is_a?(Sketchup::Group)

            container.definition.entities
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return a Container Definition Identity
        # ------------------------------------------------------------
        def self.na_container_definition_id(container)
            container.definition.object_id
        rescue StandardError
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check Entity Can Be Safely Inspected
        # ------------------------------------------------------------
        def self.na_valid_entity?(entity)
            entity &&
                entity.respond_to?(:valid?) &&
                entity.valid? &&
                (!entity.respond_to?(:deleted?) || !entity.deleted?)
        rescue StandardError
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Statistics
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build an Empty Traversal Statistics Hash
        # ------------------------------------------------------------
        def self.na_empty_statistics
            {
                visited_edge_count: 0,
                changed_edge_count: 0,
                unchanged_edge_count: 0,
                visited_container_count: 0,
                uniquified_container_count: 0,
                locked_container_count: 0,
                unsupported_selection_count: 0,
                depth_limit_count: 0,
                cyclic_container_count: 0
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__NestedEdgeStateTools
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
