# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - CONVERTER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__Converter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__Converter
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Convert groups to components or components to groups, at the
#              current level or through every nested level, in one undo step
# CREATED    : 2026
#
# GROUPS -> COMPONENTS (top-down):
# - Each group is made unique first when other group copies share its
#   definition, so Group#to_component can never reach a copy outside the
#   selection. to_component deletes the group and drops its name and lock,
#   so both are captured beforehand and re-applied.
# - Merged groups (group copies, or common geometry when that toggle is on)
#   are replaced by an instance of the first matching group's component at
#   group.transformation * offset, where the offset is the rigid move the
#   shape matcher proved lands that component's geometry on the group's.
# - Every new definition is named last, once its count is known: __Common
#   when two or more groups share it, __Unique when one group has it alone.
# - Deep Nesting then walks the new component definition once. Component
#   instances met on the way are walked through their definition, once per
#   definition, so a group inside a shared component converts once and every
#   placement of that component follows - SketchUp's own edit semantics.
#
# COMPONENTS -> GROUPS (top-down):
# - A new group takes the instance's transformation, a temporary instance of
#   the definition is exploded inside it at identity, then the instance is
#   erased. The component's own axes are kept. Other placements of the
#   definition stay components.
# - Deep Nesting then walks the new group's contents, which are private
#   copies. Existing groups on the way are made unique before anything
#   inside them changes, but only when there is a component to convert
#   below them, so plain group copies are not split for nothing.
#
# The rules match Na__GroupComponentConverter__SelectionScanner exactly, so
# the dialog preview count is the count that converts.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter__Converter

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME_GROUPS_TO_COMPONENTS = 'Convert Groups to Components'.freeze
        NA_OPERATION_NAME_COMPONENTS_TO_GROUPS = 'Convert Components to Groups'.freeze
        NA_MAX_RECURSION_DEPTH                 = 64
        NA_MAX_CONVERSIONS                     = 100_000
        NA_STATUS_EVERY                        = 100
        NA_RESELECT_BATCH_SIZE                 = 500

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Conversion API
# -----------------------------------------------------------------------------

        # FUNCTION | Convert the Active Selection
        # ------------------------------------------------------------
        # @param options [Hash] Raw or resolved dialog options
        # @return [Hash] { success:, message: }
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__Converter__ConvertSelection(options = {})
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            selection = model.selection
            seeds = selection.to_a.select { |entity| na_valid_entity?(entity) }
            unless seeds.any? { |entity| na_container?(entity) }
                return na_result(false, 'Select one or more groups or components, then convert again.')
            end

            resolved = Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__Resolve(options)
            na_run_conversion(model, selection, seeds, resolved)
        rescue => error
            na_result(false, "Group / Component Converter failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Conversion Operation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Run the Conversion and Reselect in One Undo Step
        # ------------------------------------------------------------
        # Nothing converted means nothing worth keeping, so the operation is
        # aborted rather than committed as an empty undo step.
        # ------------------------------------------------------------
        def self.na_run_conversion(model, selection, seeds, options)
            context = na_build_context(model, options)
            operation_started = false

            model.start_operation(na_operation_name(context), true)
            operation_started = true

            if context[:groups_to_components]
                na_g2c_process_entities(seeds, 1, context)
            else
                na_c2g_process_entities(seeds, 1, context)
            end

            if context[:stats][:converted_count].zero?
                model.abort_operation
                operation_started = false
                return na_result(false, na_nothing_converted_message(context))
            end

            na_name_converted_definitions(context) if context[:groups_to_components]
            na_reselect(selection, seeds, context[:top_level_results])
            model.commit_operation
            operation_started = false

            message_text = na_summary_message(context)
            Sketchup.set_status_text(message_text)
            na_result(true, message_text)
        rescue => error
            model.abort_operation if operation_started
            na_result(false, "Group / Component Converter failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Everything One Conversion Run Needs to Remember
        # ------------------------------------------------------------
        def self.na_build_context(model, options)
            merge_mode = Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__MergeMode(options)

            {
                model:                model,
                groups_to_components: Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__GroupsToComponents?(options),
                deep:                 Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__DeepNesting?(options),
                include_locked:       !!options[:include_locked],
                registry:             Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Build(merge_mode),
                visited_definitions:  {},
                subtree_memo:         {},
                top_level_results:    [],
                stats:                na_empty_stats
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Name Every New Definition Now Its Group Count Is Known
        # ------------------------------------------------------------
        def self.na_name_converted_definitions(context)
            templates = Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Templates(context[:registry])

            templates.each do |template|
                definition = template[:payload]
                next unless definition && definition.valid?

                Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__NameConvertedDefinition(
                    definition, template[:base_name], template[:member_count] > 1, context[:model]
                )
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Groups to Components
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert the Groups in One Entity List
        # ------------------------------------------------------------
        def self.na_g2c_process_entities(entities, depth, context)
            entities.each do |entity|
                break if context[:stats][:step_limit_hit]
                next unless na_valid_entity?(entity) && na_container?(entity)

                if entity.is_a?(Sketchup::Group)
                    next if na_skip_locked?(entity, context)

                    na_g2c_process_group(entity, depth, context)
                elsif context[:deep]
                    next if na_skip_locked?(entity, context)

                    na_g2c_descend_definition(entity.definition, depth, context)
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert One Group, or Swap It Onto a Shared Component
        # ------------------------------------------------------------
        def self.na_g2c_process_group(group, depth, context)
            return unless na_take_step(context)

            registry = context[:registry]
            lookup   = Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Lookup(registry, group)
            template = lookup[:template]

            if template && template[:payload] && template[:payload].valid?
                instance = na_replace_group_with_instance(group, template[:payload], lookup[:offset], context)
                return unless instance

                Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__AddMember(template)
                na_record_conversion(instance, depth, context)
                context[:stats][:merged_count] += 1
                return
            end

            group_name = group.name.to_s
            instance = na_convert_group_to_component(group, context)
            return unless instance

            Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Register(
                registry, lookup, instance.definition, group_name
            )
            na_record_conversion(instance, depth, context)
            context[:stats][:new_definition_count] += 1
            return unless context[:deep]

            na_g2c_descend_definition(instance.definition, depth, context)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk a Component Definition Once
        # ------------------------------------------------------------
        def self.na_g2c_descend_definition(definition, depth, context)
            return unless definition && definition.valid?

            if depth >= NA_MAX_RECURSION_DEPTH
                context[:stats][:depth_limit_count] += 1
                return
            end

            definition_id = definition.entityID
            return if context[:visited_definitions][definition_id]

            context[:visited_definitions][definition_id] = true
            na_g2c_process_entities(definition.entities.to_a, depth + 1, context)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Turn One Group Into a Component Instance
        # ------------------------------------------------------------
        def self.na_convert_group_to_component(group, context)
            properties = Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__Capture(group)
            group.locked = false if properties[:locked]

            if na_shared_definition?(group)
                group.make_unique
                context[:stats][:uniquified_group_count] += 1
            end

            instance = group.to_component
            unless instance && instance.valid?
                context[:stats][:failed_count] += 1
                return nil
            end

            Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__Apply(
                instance, properties, properties[:name]
            )
            na_relock(instance, properties, context)
            instance
        rescue => error
            context[:stats][:failed_count] += 1
            puts "[Na__GroupComponentConverter] Group to component warning: #{error.class}: #{error.message}"
            na_relock_original(group, properties)
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Replace a Merged Group With an Instance of the Shared Component
        # ------------------------------------------------------------
        # offset is the shape matcher's local-space move from the shared
        # component's geometry onto this group's; identity for group copies.
        # ------------------------------------------------------------
        def self.na_replace_group_with_instance(group, definition, offset, context)
            owning_entities = na_owning_entities(group)
            unless owning_entities
                context[:stats][:failed_count] += 1
                return nil
            end

            properties = Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__Capture(group)
            group.locked = false if properties[:locked]

            placement = offset ? properties[:transformation] * offset : properties[:transformation]
            instance = owning_entities.add_instance(definition, placement)
            owning_entities.erase_entities(group)

            Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__Apply(
                instance, properties, properties[:name]
            )
            na_relock(instance, properties, context)
            instance
        rescue => error
            context[:stats][:failed_count] += 1
            puts "[Na__GroupComponentConverter] Group merge warning: #{error.class}: #{error.message}"
            instance.erase! if instance && instance.valid? && group && group.valid?
            na_relock_original(group, properties)
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Components to Groups
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert the Components in One Entity List
        # ------------------------------------------------------------
        def self.na_c2g_process_entities(entities, depth, context)
            entities.each do |entity|
                break if context[:stats][:step_limit_hit]
                next unless na_valid_entity?(entity) && na_container?(entity)

                if entity.is_a?(Sketchup::ComponentInstance)
                    na_c2g_process_component(entity, depth, context)
                elsif context[:deep]
                    na_c2g_process_group(entity, depth, context)
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert One Component, Then Its Private Copy's Contents
        # ------------------------------------------------------------
        def self.na_c2g_process_component(instance, depth, context)
            return if na_skip_locked?(instance, context)

            definition = instance.definition
            if na_empty_definition?(definition)
                context[:stats][:empty_skipped_count] += 1
                return
            end

            return unless na_take_step(context)

            group = na_convert_component_to_group(instance, definition, context)
            return unless group

            na_record_conversion(group, depth, context)
            return unless context[:deep]

            if depth >= NA_MAX_RECURSION_DEPTH
                context[:stats][:depth_limit_count] += 1
                return
            end

            na_c2g_process_entities(group.entities.to_a, depth + 1, context)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Pass Through an Existing Group, Made Unique First
        # ------------------------------------------------------------
        def self.na_c2g_process_group(group, depth, context)
            return if na_skip_locked?(group, context)

            if depth >= NA_MAX_RECURSION_DEPTH
                context[:stats][:depth_limit_count] += 1
                return
            end

            return unless na_subtree_has_component_target?(group.definition, context, 0)

            was_locked = group.locked?
            group.locked = false if was_locked

            if na_shared_definition?(group)
                group.make_unique
                context[:stats][:uniquified_group_count] += 1
            end

            na_c2g_process_entities(group.entities.to_a, depth + 1, context)
        ensure
            group.locked = true if was_locked && group.valid?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Replace One Component Instance With an Equivalent Group
        # ------------------------------------------------------------
        def self.na_convert_component_to_group(instance, definition, context)
            owning_entities = na_owning_entities(instance)
            unless owning_entities
                context[:stats][:failed_count] += 1
                return nil
            end

            properties = Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__Capture(instance)
            instance.locked = false if properties[:locked]

            group = owning_entities.add_group
            group.transformation = properties[:transformation]
            temporary_instance = group.entities.add_instance(definition, Geom::Transformation.new)
            temporary_instance.explode
            owning_entities.erase_entities(instance)

            Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__Apply(
                group, properties, Na__GroupComponentConverter__PropertyTransfer.Na__GroupComponentConverter__PropertyTransfer__GroupNameFor(properties)
            )
            na_relock(group, properties, context)
            group
        rescue => error
            context[:stats][:failed_count] += 1
            puts "[Na__GroupComponentConverter] Component to group warning: #{error.class}: #{error.message}"
            na_discard_partial_group(instance, group)
            na_relock_original(instance, properties)
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When a Component Sits Anywhere Below Through Groups
        # ------------------------------------------------------------
        # Guards make_unique: a group copy holding only raw geometry, or only
        # locked containers that will be skipped, is left sharing its
        # definition.
        # ------------------------------------------------------------
        def self.na_subtree_has_component_target?(definition, context, depth)
            return false unless definition && definition.valid?
            return false if depth > NA_MAX_RECURSION_DEPTH

            memo = context[:subtree_memo]
            definition_id = definition.entityID
            return memo[definition_id] if memo.key?(definition_id)

            memo[definition_id] = false
            memo[definition_id] = definition.entities.any? do |child|
                na_component_target_below?(child, context, depth)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When One Child Is, or Leads To, a Component Target
        # ------------------------------------------------------------
        def self.na_component_target_below?(child, context, depth)
            return false unless na_valid_entity?(child) && na_container?(child)
            return false if child.locked? && !context[:include_locked]
            return !na_empty_definition?(child.definition) if child.is_a?(Sketchup::ComponentInstance)

            na_subtree_has_component_target?(child.definition, context, depth + 1)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Conversion Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Skip a Locked Container Unless Locked Ones Are Included
        # ------------------------------------------------------------
        def self.na_skip_locked?(entity, context)
            return false unless entity.locked? && !context[:include_locked]

            context[:stats][:locked_skipped_count] += 1
            true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Allow One More Conversion Under the Safety Cap
        # ------------------------------------------------------------
        def self.na_take_step(context)
            stats = context[:stats]
            return true if stats[:converted_count] + stats[:failed_count] < NA_MAX_CONVERSIONS

            stats[:step_limit_hit] = true
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count a Successful Conversion
        # ------------------------------------------------------------
        def self.na_record_conversion(result, depth, context)
            stats = context[:stats]
            stats[:converted_count] += 1

            if depth == 1
                stats[:top_level_count] += 1
                context[:top_level_results] << result
            else
                stats[:nested_count] += 1
            end

            na_report_progress(context)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Relock a Converted Container That Was Locked Before
        # ------------------------------------------------------------
        def self.na_relock(target, properties, context)
            return unless properties[:locked]

            target.locked = true
            context[:stats][:relocked_count] += 1
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Restore the Lock on an Original That Failed to Convert
        # ------------------------------------------------------------
        def self.na_relock_original(original, properties)
            return unless properties && properties[:locked]
            return unless original && original.valid?

            original.locked = true
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Drop a Half-Built Group While the Original Still Exists
        # ------------------------------------------------------------
        def self.na_discard_partial_group(instance, group)
            return unless instance && instance.valid?
            return unless group && group.valid?

            group.erase!
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When Other Group Copies Share This Definition
        # ------------------------------------------------------------
        def self.na_shared_definition?(group)
            group.definition.instances.length > 1
        rescue
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Owning Entities Collection for a Container
        # ------------------------------------------------------------
        def self.na_owning_entities(entity)
            parent = entity.parent
            return parent.entities if parent.respond_to?(:entities)

            nil
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Replace the Selection With Survivors and Top-Level Results
        # ------------------------------------------------------------
        def self.na_reselect(selection, seeds, top_level_results)
            survivors = seeds.select { |entity| na_valid_entity?(entity) }
            results   = top_level_results.select { |entity| na_valid_entity?(entity) }
            targets   = (survivors + results).uniq

            selection.clear
            targets.each_slice(NA_RESELECT_BATCH_SIZE) do |batch|
                selection.add(*batch)
            end
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Show Progress So a Long Run Does Not Look Frozen
        # ------------------------------------------------------------
        def self.na_report_progress(context)
            converted = context[:stats][:converted_count]
            return unless (converted % NA_STATUS_EVERY).zero?

            Sketchup.set_status_text("Group / Component Converter: converted #{converted}...")
        rescue
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Messaging
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Result Sentence
        # ------------------------------------------------------------
        def self.na_summary_message(context)
            stats = context[:stats]
            from_word, to_word = na_direction_words(context)
            converted = stats[:converted_count]
            parts = ["Converted #{converted} #{na_plural(converted, from_word, "#{from_word}s")} to #{to_word}s."]

            if stats[:nested_count] > 0
                parts << "#{stats[:top_level_count]} at the current level, #{stats[:nested_count]} nested."
            end

            parts << na_definition_sentence(context) if context[:groups_to_components]
            parts.concat(na_skip_notes(stats))
            parts.join(' ')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | How the New Definitions Split Into __Common and __Unique
        # ------------------------------------------------------------
        def self.na_definition_sentence(context)
            summary = Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Summary(context[:registry])
            common = summary[:common_definition_count]
            single = summary[:single_definition_count]

            if common.zero?
                return single == 1 ? 'It has its own __Unique definition.' : 'Each has its own __Unique definition.'
            end

            text = "#{summary[:common_group_count]} share #{common} __Common #{na_plural(common, 'definition', 'definitions')}"
            text += "; #{single} #{na_plural(single, 'has its', 'have their')} own __Unique" if single > 0
            "#{text}."
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Explain Why a Run Converted Nothing
        # ------------------------------------------------------------
        def self.na_nothing_converted_message(context)
            stats = context[:stats]
            from_word, _to_word = na_direction_words(context)
            where = context[:deep] ? 'anywhere in the selection' : 'at the current level of the selection'
            parts = ["Nothing converted: no #{from_word}s #{where} could be converted."]
            parts.concat(na_skip_notes(stats))
            parts << 'Switch to Deep Nesting to reach nested containers.' unless context[:deep]
            parts.join(' ')
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Sentences for Skipped, Failed and Capped Containers
        # ------------------------------------------------------------
        def self.na_skip_notes(stats)
            notes = []

            if stats[:locked_skipped_count] > 0
                skipped = stats[:locked_skipped_count]
                notes << "#{skipped} locked #{na_plural(skipped, 'container was', 'containers were')} skipped."
            end

            if stats[:relocked_count] > 0
                notes << "#{stats[:relocked_count]} locked #{na_plural(stats[:relocked_count], 'container', 'containers')} relocked after converting."
            end

            if stats[:empty_skipped_count] > 0
                notes << "#{stats[:empty_skipped_count]} empty #{na_plural(stats[:empty_skipped_count], 'component', 'components')} skipped."
            end

            notes << "#{stats[:failed_count]} could not be converted." if stats[:failed_count] > 0
            notes << "Stopped at the #{NA_MAX_CONVERSIONS} conversion safety limit." if stats[:step_limit_hit]

            if stats[:depth_limit_count] > 0
                notes << "Containers nested deeper than #{NA_MAX_RECURSION_DEPTH} levels were left alone."
            end

            notes
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Source and Result Words for the Chosen Direction
        # ------------------------------------------------------------
        def self.na_direction_words(context)
            context[:groups_to_components] ? %w[group component] : %w[component group]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Undo Menu Name for the Chosen Direction
        # ------------------------------------------------------------
        def self.na_operation_name(context)
            return NA_OPERATION_NAME_GROUPS_TO_COMPONENTS if context[:groups_to_components]

            NA_OPERATION_NAME_COMPONENTS_TO_GROUPS
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Pick Singular or Plural
        # ------------------------------------------------------------
        def self.na_plural(count_value, singular_word, plural_word)
            count_value == 1 ? singular_word : plural_word
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Zeroed Run Statistics
        # ------------------------------------------------------------
        def self.na_empty_stats
            {
                converted_count:        0,
                top_level_count:        0,
                nested_count:           0,
                merged_count:           0,
                new_definition_count:   0,
                locked_skipped_count:   0,
                relocked_count:         0,
                empty_skipped_count:    0,
                uniquified_group_count: 0,
                failed_count:           0,
                depth_limit_count:      0,
                step_limit_hit:         false
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When the Entity Is a Group or Component Instance
        # ------------------------------------------------------------
        def self.na_container?(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When the Entity Can Still Be Used
        # ------------------------------------------------------------
        def self.na_valid_entity?(entity)
            entity && entity.valid?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When a Definition Holds Nothing to Copy
        # ------------------------------------------------------------
        def self.na_empty_definition?(definition)
            definition.nil? || definition.entities.length.zero?
        rescue
            true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter__Converter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
