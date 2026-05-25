# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECTED HIERARCHY TAG REPORTER - TREE DATA
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectedHierarchyTagReporter__TreeData__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectedHierarchyTagReporter__TreeData
# PURPOSE    : Build plain Ruby hierarchy data for console and HtmlDialog reports
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectedHierarchyTagReporter__TreeData

# -----------------------------------------------------------------------------
# REGION | Public Data Builders
# -----------------------------------------------------------------------------

        def self.Na__SelectedHierarchyTagReporter__TreeData__Build(include_siblings)
            model = Sketchup.active_model
            return na_empty_report('No active model available.', include_siblings) unless model

            selection = model.selection.to_a
            active_path = model.active_path || []
            selected_entity_keys = na_runtime_keys_for_entities(selection)
            root_node = na_model_root_node
            current_context_node = na_attach_active_path_nodes(root_node, active_path)

            if selection.empty?
                current_context_node[:children] << na_message_node(
                    active_path.length + 1,
                    'Current Selection',
                    'No current selection found.'
                )
            elsif include_siblings
                current_context_node[:children] << na_sibling_context_node(
                    model,
                    active_path.length + 1,
                    selected_entity_keys,
                    na_visited_definition_keys_for_active_path(active_path)
                )
            elsif selection.length == 1
                current_context_node[:children] << na_entity_node(
                    selection.first,
                    active_path.length + 1,
                    'Selected Object',
                    selected_entity_keys,
                    na_visited_definition_keys_for_active_path(active_path)
                )
            else
                current_context_node[:children] << na_multi_selection_node(
                    selection,
                    active_path.length + 1,
                    selected_entity_keys,
                    na_visited_definition_keys_for_active_path(active_path)
                )
            end

            {
                generated_at: na_formatted_report_timestamp(Time.now),
                include_siblings: !!include_siblings,
                selection_count: selection.length,
                selection_empty: selection.empty?,
                active_path_count: active_path.length,
                summary: na_summary_text(selection, include_siblings),
                nodes: [root_node]
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tree Node Builders
# -----------------------------------------------------------------------------

        def self.na_model_root_node
            {
                node_type: 'model',
                level: 0,
                role: 'Model Root',
                title: 'Loose SketchUp Model',
                display_text: 'Loose SketchUp Model | Tag: n/a',
                tag_name: 'n/a',
                selected: false,
                children: []
            }
        end

        def self.na_attach_active_path_nodes(root_node, active_path)
            current_node = root_node

            active_path.each_with_index do |entity, index|
                context_node = na_base_entity_node(
                    entity,
                    index + 1,
                    'Parent Context',
                    false
                )
                current_node[:children] << context_node
                current_node = context_node
            end

            current_node
        end

        def self.na_multi_selection_node(selection, level_number, selected_entity_keys, visited_definition_keys)
            {
                node_type: 'selection_group',
                level: level_number,
                role: 'Current Selection',
                title: "Items: #{selection.length}",
                display_text: "Current Selection | Items: #{selection.length}",
                tag_name: 'n/a',
                selected: false,
                children: selection.each_with_index.map do |entity, index|
                    na_entity_node(
                        entity,
                        level_number + 1,
                        "Selected Object #{index + 1}",
                        selected_entity_keys,
                        visited_definition_keys
                    )
                end
            }
        end

        def self.na_sibling_context_node(model, level_number, selected_entity_keys, visited_definition_keys)
            context_entities = model.active_entities.to_a
            container_entities, loose_geometry_entities = na_partition_entities(context_entities)

            sibling_node = {
                node_type: 'sibling_group',
                level: level_number,
                role: 'Current Context Siblings',
                title: "Items: #{context_entities.length}",
                display_text: "Current Context Siblings | Items: #{context_entities.length}",
                tag_name: 'n/a',
                selected: false,
                loose_geometry_summary: na_loose_geometry_summary(loose_geometry_entities),
                children: container_entities.map do |entity|
                    na_entity_node(
                        entity,
                        level_number + 1,
                        selected_entity_keys.include?(na_runtime_key(entity)) ? 'Selected Object' : 'Sibling Object',
                        selected_entity_keys,
                        visited_definition_keys
                    )
                end
            }

            sibling_node[:children] << na_message_node(level_number + 1, 'Empty Context', 'No entities found.') if context_entities.empty?
            sibling_node
        rescue => error
            na_message_node(level_number, 'Current Context Siblings', "Sibling read failed: #{error.class}: #{error.message}")
        end

        def self.na_entity_node(entity, level_number, role_label, selected_entity_keys, visited_definition_keys)
            entity_key = na_runtime_key(entity)
            definition_key = Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__DefinitionKeyForEntity(entity)
            node = na_base_entity_node(entity, level_number, role_label, selected_entity_keys.include?(entity_key))
            child_entities = Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__ChildEntitiesForContainer(entity)

            return node unless child_entities

            if definition_key && visited_definition_keys.include?(definition_key)
                node[:children] << na_message_node(
                    level_number + 1,
                    'Recursive Component Definition Skipped',
                    'Prevented infinite loop'
                )
                return node
            end

            next_visited_definition_keys = definition_key ? visited_definition_keys + [definition_key] : visited_definition_keys
            container_entities, loose_geometry_entities = na_partition_entities(child_entities.to_a)
            node[:loose_geometry_summary] = na_loose_geometry_summary(loose_geometry_entities)
            node[:children] = container_entities.map do |child_entity|
                na_entity_node(
                    child_entity,
                    level_number + 1,
                    'Child Object',
                    selected_entity_keys,
                    next_visited_definition_keys
                )
            end

            if container_entities.empty? && loose_geometry_entities.empty?
                node[:children] << na_message_node(level_number + 1, 'Empty Container', 'Tag: n/a')
            end

            node
        end

        def self.na_base_entity_node(entity, level_number, role_label, selected_flag)
            {
                node_type: 'entity',
                entity_key: na_runtime_key(entity),
                level: level_number,
                role: role_label,
                title: Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__EntityTypeName(entity),
                display_text: Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__EntityDescription(entity),
                tag_name: Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__TagNameForEntity(entity),
                entity_name: Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__EntityNameForEntity(entity),
                definition_name: Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__RawDefinitionNameForEntity(entity),
                selected: selected_flag,
                children: []
            }
        end

        def self.na_message_node(level_number, role_label, message_text)
            {
                node_type: 'message',
                level: level_number,
                role: role_label,
                title: message_text.to_s,
                display_text: "#{role_label} | #{message_text}",
                tag_name: 'n/a',
                selected: false,
                children: []
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Summaries
# -----------------------------------------------------------------------------

        def self.na_partition_entities(entities)
            container_entities = []
            loose_geometry_entities = []

            entities.each do |entity|
                if Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__ContainerEntity?(entity)
                    container_entities << entity
                else
                    loose_geometry_entities << entity
                end
            end

            [container_entities, loose_geometry_entities]
        end

        def self.na_loose_geometry_summary(entities)
            return nil if entities.empty?

            type_counts = Hash.new(0)
            tag_counts = Hash.new(0)

            entities.each do |entity|
                type_name = Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__EntityTypeName(entity)
                tag_name = Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__TagNameForEntity(entity)

                type_counts[type_name] += 1
                tag_counts[tag_name] += 1
            end

            {
                item_count: entities.length,
                type_summary: na_count_summary(type_counts, false),
                tag_summary: na_count_summary(tag_counts, true)
            }
        end

        def self.na_count_summary(counts, quote_names)
            counts
                .sort_by { |name, _count| name.to_s.downcase }
                .map do |name, count|
                    display_name = quote_names ? Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__QuotedOrUnnamed(name) : name
                    "#{display_name} x#{count}"
                end
                .join(', ')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection and Recursion Helpers
# -----------------------------------------------------------------------------

        def self.na_runtime_keys_for_entities(entities)
            entities.map { |entity| na_runtime_key(entity) }
        end

        def self.na_runtime_key(entity)
            Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__RuntimeEntityKey(entity)
        end

        def self.na_visited_definition_keys_for_active_path(active_path)
            active_path
                .map { |entity| Na__SelectedHierarchyTagReporter__EntityText.Na__SelectedHierarchyTagReporter__EntityText__DefinitionKeyForEntity(entity) }
                .compact
        end

        def self.na_summary_text(selection, include_siblings)
            return 'No current selection found.' if selection.empty?
            return "Showing selected object and its descendants. Selection count: #{selection.length}." unless include_siblings

            "Showing all siblings in the active context. Selection count: #{selection.length}."
        end

        def self.na_formatted_report_timestamp(time_value)
            hour_text = time_value.strftime('%I').sub(/\A0/, '')
            "#{time_value.strftime('%d-%b-%Y')} - #{hour_text}:#{time_value.strftime('%M')}#{time_value.strftime('%p').downcase}"
        end

        def self.na_empty_report(message_text, include_siblings)
            {
                generated_at: na_formatted_report_timestamp(Time.now),
                include_siblings: !!include_siblings,
                selection_count: 0,
                selection_empty: true,
                active_path_count: 0,
                summary: message_text.to_s,
                nodes: [
                    na_model_root_node.merge(
                        children: [
                            na_message_node(1, 'Reporter', message_text)
                        ]
                    )
                ]
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__SelectedHierarchyTagReporter__TreeData
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
