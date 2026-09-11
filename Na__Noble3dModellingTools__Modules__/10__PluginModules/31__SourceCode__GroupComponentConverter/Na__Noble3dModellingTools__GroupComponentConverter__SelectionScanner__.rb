# =============================================================================
# NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - SELECTION SCANNER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__GroupComponentConverter__SelectionScanner__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__GroupComponentConverter__SelectionScanner
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Walk the selection read-only, report how many groups and
#              components are nested at each level, and simulate both
#              conversion directions at both scopes for the dialog preview
# CREATED    : 2026
#
# SAFETY:
# - Read-only. Nothing is converted, unlocked or made unique here. Contents
#   are read through definition.entities, which never makes a group unique.
#
# WHY TWO WALKS:
# - Tree walk, per path. Counts what the user sees: a component placed ten
#   times with five groups inside shows fifty groups. Components to Groups
#   also works per path - every converted component is a private copy and
#   every group it passes through is made unique - so this walk carries that
#   plan too.
# - Groups to Components walk, per definition. A group inside a component
#   definition is one entity however many times the component is placed, so
#   it converts once and every placement follows. Converted groups are made
#   unique first, so their own contents are walked per path. Merged groups
#   are not walked again: they reuse the first matching group's component.
#
# SHARED DEFINITIONS:
# - Both Groups to Components plans run the same merge registry the
#   converter runs, in the same walk order, so the preview reports how many
#   definitions come out __Common (shared) and __Unique (single).
#
# The converter follows exactly these rules, so the preview count is the
# count that converts. Live preview walks stop at NA_PREVIEW_ENTITY_LIMIT and
# common-shape matching at NA_PREVIEW_MATCH_BUDGET; the conversion itself is
# never capped by the preview.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__GroupComponentConverter__SelectionScanner

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_RECURSION_DEPTH  = 64
        NA_PREVIEW_ENTITY_LIMIT = 50_000
        NA_PREVIEW_MATCH_BUDGET = 400_000
        NA_LEVEL_ROW_LIMIT      = 12
        NA_LIMIT_THROW_TAG      = :na_group_component_converter_limit

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Scan API
# -----------------------------------------------------------------------------

        # FUNCTION | Summarise the Selection and Simulate Every Conversion
        # ------------------------------------------------------------
        # @param selection    [Sketchup::Selection, Array]
        # @param options      [Hash] Resolved or raw dialog options
        # @param entity_limit [Integer, nil] Preview cap; nil walks everything
        # @return [Hash] String-keyed payload for the HtmlDialog
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__SelectionScanner__Scan(selection, options, entity_limit = NA_PREVIEW_ENTITY_LIMIT)
            return na_empty_summary unless selection

            seeds = selection.to_a.select { |entity| na_valid_entity?(entity) }
            return na_empty_summary if seeds.empty?

            resolved = Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__Resolve(options)
            matching = {
                records: {},
                work:    Na__GroupComponentConverter__ShapeMatcher.Na__GroupComponentConverter__ShapeMatcher__NewWork(NA_PREVIEW_MATCH_BUDGET)
            }

            tree_context = na_scan_tree(seeds, resolved, entity_limit)
            g2c_current  = na_scan_groups_to_components_current(seeds, resolved, matching)
            g2c_deep     = na_scan_groups_to_components_deep(seeds, resolved, matching, entity_limit)

            na_finish_repeat_count(g2c_deep, tree_context)
            na_summary_payload(seeds.length, tree_context, g2c_current, g2c_deep)
        rescue => error
            puts "[Na__GroupComponentConverter] Scan warning: #{error.class}: #{error.message}"
            na_empty_summary
        end
        # ------------------------------------------------------------

        # FUNCTION | Build the Empty Selection Payload
        # ------------------------------------------------------------
        def self.Na__GroupComponentConverter__SelectionScanner__EmptySummary
            na_empty_summary
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tree Walk - Per Path (Tree Stats + Components to Groups)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Run the Per-Path Walk Over Every Seed
        # ------------------------------------------------------------
        def self.na_scan_tree(seeds, options, entity_limit)
            context = {
                include_locked:      !!options[:include_locked],
                limit:               entity_limit,
                visited_count:       0,
                limit_reached:       false,
                depth_limit_count:   0,
                tree:                na_empty_tree,
                levels:              Hash.new { |hash, key| hash[key] = { groups: 0, components: 0 } },
                component_def_ids:   {},
                c2g_current:         na_empty_plan,
                c2g_deep:            na_empty_plan,
                c2g_target_def_ids:  {},
                c2g_top_by_def:      Hash.new(0),
                c2g_top_definitions: {},
                g2c_path_count:      0
            }

            catch(NA_LIMIT_THROW_TAG) do
                seeds.each do |entity|
                    na_walk_tree(entity, 1, context, false, [])
                end
            end

            context[:c2g_deep][:unique_definition_count]    = context[:c2g_target_def_ids].length
            context[:c2g_current][:unique_definition_count] = context[:c2g_top_definitions].length
            other_placements = na_other_placement_count(context)
            context[:c2g_current][:other_placement_count] = other_placements
            context[:c2g_deep][:other_placement_count]    = other_placements
            context
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk One Container and Everything Beneath It
        # ------------------------------------------------------------
        # blocked is true beneath a locked container the conversion will
        # skip. Tree stats still count there; the plans do not.
        # ------------------------------------------------------------
        def self.na_walk_tree(entity, depth, context, blocked, definition_stack)
            return unless na_valid_entity?(entity) && na_container?(entity)

            na_bump_visit_count(context)
            is_group   = entity.is_a?(Sketchup::Group)
            definition = na_definition_for(entity)
            lock_skip  = entity.locked? && !context[:include_locked]

            na_record_tree_entity(entity, is_group, definition, depth, context)

            unless blocked
                if is_group
                    na_plan_tree_group(depth, lock_skip, context)
                else
                    na_plan_tree_component(entity, definition, depth, lock_skip, context)
                end
            end

            na_walk_tree_children(definition, depth, context, blocked || lock_skip, definition_stack)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Descend Into a Definition Along This Path
        # ------------------------------------------------------------
        def self.na_walk_tree_children(definition, depth, context, blocked, definition_stack)
            return unless definition

            if depth >= NA_MAX_RECURSION_DEPTH
                context[:depth_limit_count] += 1
                return
            end

            definition_id = definition.entityID
            return if definition_stack.include?(definition_id)

            next_stack = definition_stack + [definition_id]
            definition.entities.each do |child|
                na_walk_tree(child, depth + 1, context, blocked, next_stack)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record Raw Tree Totals for One Container
        # ------------------------------------------------------------
        def self.na_record_tree_entity(entity, is_group, definition, depth, context)
            tree = context[:tree]
            tree[:deepest_level] = depth if depth > tree[:deepest_level]
            tree[:locked_container_count] += 1 if entity.locked?

            if is_group
                tree[:group_count] += 1
                tree[:top_group_count] += 1 if depth == 1
                context[:levels][depth][:groups] += 1
            else
                tree[:component_count] += 1
                tree[:top_component_count] += 1 if depth == 1
                context[:levels][depth][:components] += 1
                context[:component_def_ids][definition.entityID] = true if definition
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Components to Groups Treats a Group as a Pass-Through
        # ------------------------------------------------------------
        # A locked group stops the walk beneath it, so deep plans report it.
        # The per-path Groups to Components count is gathered here too, so
        # the dialog can say how many nested groups repeat inside shared
        # definitions and convert only once.
        # ------------------------------------------------------------
        def self.na_plan_tree_group(depth, lock_skip, context)
            if lock_skip
                context[:c2g_deep][:locked_skipped_count] += 1
                return
            end

            context[:g2c_path_count] += 1
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Components to Groups Converts Every Reachable Component
        # ------------------------------------------------------------
        def self.na_plan_tree_component(entity, definition, depth, lock_skip, context)
            if lock_skip
                context[:c2g_deep][:locked_skipped_count] += 1
                context[:c2g_current][:locked_skipped_count] += 1 if depth == 1
                return
            end

            if na_empty_definition?(definition)
                context[:c2g_deep][:empty_skipped_count] += 1
                context[:c2g_current][:empty_skipped_count] += 1 if depth == 1
                return
            end

            glue_or_cut = na_glues_or_cuts?(definition)
            na_count_target(context[:c2g_deep], depth, glue_or_cut)
            context[:c2g_target_def_ids][definition.entityID] = true
            return unless depth == 1

            na_count_target(context[:c2g_current], depth, glue_or_cut)
            context[:c2g_top_by_def][definition.entityID] += 1
            context[:c2g_top_definitions][definition.entityID] = definition
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Placements of the Selected Components That Stay Components
        # ------------------------------------------------------------
        def self.na_other_placement_count(context)
            context[:c2g_top_definitions].sum do |definition_id, definition|
                next 0 unless definition.valid?

                [definition.instances.length - context[:c2g_top_by_def][definition_id], 0].max
            end
        rescue
            0
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Groups to Components - Current Level
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Plan Groups to Components for the Selected Groups Only
        # ------------------------------------------------------------
        def self.na_scan_groups_to_components_current(seeds, options, matching)
            plan     = na_empty_plan
            registry = na_build_registry(options, matching)

            seeds.each do |entity|
                next unless entity.is_a?(Sketchup::Group)

                if entity.locked? && !options[:include_locked]
                    plan[:locked_skipped_count] += 1
                    next
                end

                na_count_target(plan, 1, false)
                na_plan_merge(entity, registry, plan)
            end

            na_apply_registry_summary(plan, registry)
            plan
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Groups to Components - Deep Nesting (Per Definition)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Plan Groups to Components Through Every Nested Level
        # ------------------------------------------------------------
        def self.na_scan_groups_to_components_deep(seeds, options, matching, entity_limit)
            context = {
                include_locked:        !!options[:include_locked],
                registry:              na_build_registry(options, matching),
                visited_definitions:   {},
                definition_changes:    {},
                definitions_by_id:     {},
                encountered_instances: Hash.new { |hash, key| hash[key] = {} },
                plan:                  na_empty_plan,
                limit:                 entity_limit,
                visited_count:         0,
                limit_reached:         false,
                depth_limit_count:     0
            }

            catch(NA_LIMIT_THROW_TAG) do
                seeds.each do |entity|
                    na_walk_groups_to_components(entity, 1, context, [])
                end
            end

            na_finish_affected_definitions(context)
            na_apply_registry_summary(context[:plan], context[:registry])
            context
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk One Container the Way Groups to Components Converts It
        # ------------------------------------------------------------
        # @return [Boolean] True when this container or anything beneath it
        #                   is converted
        # ------------------------------------------------------------
        def self.na_walk_groups_to_components(entity, depth, context, definition_stack)
            return false unless na_valid_entity?(entity) && na_container?(entity)

            na_bump_visit_count(context)

            if entity.locked? && !context[:include_locked]
                context[:plan][:locked_skipped_count] += 1
                return false
            end

            if entity.is_a?(Sketchup::Group)
                na_walk_group_target(entity, depth, context, definition_stack)
            else
                na_walk_component_definition(entity, depth, context, definition_stack)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count a Group, Then Walk Its Own Contents Once Per Path
        # ------------------------------------------------------------
        def self.na_walk_group_target(group, depth, context, definition_stack)
            plan = context[:plan]
            na_count_target(plan, depth, false)
            return true if na_plan_merge(group, context[:registry], plan) == :merged

            na_walk_definition_entities(na_definition_for(group), depth, context, definition_stack)
            true
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk a Component Definition Once, However Often It Is Placed
        # ------------------------------------------------------------
        def self.na_walk_component_definition(instance, depth, context, definition_stack)
            definition = na_definition_for(instance)
            return false unless definition

            definition_id = definition.entityID
            context[:encountered_instances][definition_id][instance.entityID] = true
            return !!context[:definition_changes][definition_id] if context[:visited_definitions][definition_id]

            context[:visited_definitions][definition_id] = true
            context[:definitions_by_id][definition_id]   = definition
            changed = na_walk_definition_entities(definition, depth, context, definition_stack)
            context[:definition_changes][definition_id] = changed
            changed
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk Every Child Without Short-Circuiting the Counts
        # ------------------------------------------------------------
        def self.na_walk_definition_entities(definition, depth, context, definition_stack)
            return false unless definition

            if depth >= NA_MAX_RECURSION_DEPTH
                context[:depth_limit_count] += 1
                return false
            end

            definition_id = definition.entityID
            return false if definition_stack.include?(definition_id)

            next_stack = definition_stack + [definition_id]
            changed = false
            definition.entities.each do |child|
                changed = true if na_walk_groups_to_components(child, depth + 1, context, next_stack)
            end
            changed
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count Shared Component Definitions the Conversion Edits
        # ------------------------------------------------------------
        # Every placement of an edited definition changes, including ones
        # outside the selection. Those are the ones worth warning about.
        # ------------------------------------------------------------
        def self.na_finish_affected_definitions(context)
            plan = context[:plan]

            context[:definition_changes].each do |definition_id, changed|
                next unless changed

                definition = context[:definitions_by_id][definition_id]
                next unless definition && definition.valid?

                plan[:affected_definition_count] += 1
                outside = definition.instances.length - context[:encountered_instances][definition_id].length
                plan[:outside_placement_count] += outside if outside > 0
            end
        rescue => error
            puts "[Na__GroupComponentConverter] Affected definition warning: #{error.class}: #{error.message}"
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Nested Groups That Repeat Inside Shared Definitions
        # ------------------------------------------------------------
        def self.na_finish_repeat_count(g2c_deep, tree_context)
            return if g2c_deep[:limit_reached] || tree_context[:limit_reached]

            repeat_count = tree_context[:g2c_path_count] - g2c_deep[:plan][:convert_count]
            g2c_deep[:plan][:repeat_count] = repeat_count if repeat_count > 0
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plan Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Count One Conversion Target at Its Depth
        # ------------------------------------------------------------
        def self.na_count_target(plan, depth, glue_or_cut)
            plan[:convert_count] += 1

            if depth == 1
                plan[:top_level_count] += 1
            else
                plan[:nested_count] += 1
            end

            plan[:glue_or_cut_count] += 1 if glue_or_cut
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Decide Whether a Group Joins an Earlier Group's Component
        # ------------------------------------------------------------
        # @return [Symbol] :merged when it reuses an earlier component,
        #                  :new when it gets its own definition
        # ------------------------------------------------------------
        def self.na_plan_merge(group, registry, plan)
            lookup = Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Lookup(registry, group)

            if lookup[:template]
                Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__AddMember(lookup[:template])
                plan[:merged_count] += 1
                return :merged
            end

            Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Register(
                registry, lookup, true, group.name
            )
            plan[:new_definition_count] += 1
            :new
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Merge Registry Sharing One Record Cache and Work Budget
        # ------------------------------------------------------------
        def self.na_build_registry(options, matching)
            Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Build(
                Na__GroupComponentConverter__Options.Na__GroupComponentConverter__Options__MergeMode(options),
                matching[:work],
                matching[:records]
            )
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Copy the __Common / __Unique Split Into a Plan
        # ------------------------------------------------------------
        def self.na_apply_registry_summary(plan, registry)
            summary = Na__GroupComponentConverter__MergeRegistry.Na__GroupComponentConverter__MergeRegistry__Summary(registry)
            plan[:common_definition_count] = summary[:common_definition_count]
            plan[:common_group_count]      = summary[:common_group_count]
            plan[:single_definition_count] = summary[:single_definition_count]
            plan[:common_preview_partial]  = summary[:partial]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Stop a Preview Walk Once the Cap Is Hit
        # ------------------------------------------------------------
        def self.na_bump_visit_count(context)
            return unless context[:limit]

            context[:visited_count] += 1
            return if context[:visited_count] <= context[:limit]

            context[:limit_reached] = true
            throw(NA_LIMIT_THROW_TAG)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Assembly
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert Both Walks Into the Dialog Payload
        # ------------------------------------------------------------
        def self.na_summary_payload(selected_count, tree_context, g2c_current, g2c_deep)
            tree = tree_context[:tree]

            {
                'has_selection'                     => true,
                'selected_count'                    => selected_count,
                'group_count'                       => tree[:group_count],
                'component_count'                   => tree[:component_count],
                'top_group_count'                   => tree[:top_group_count],
                'top_component_count'               => tree[:top_component_count],
                'nested_group_count'                => tree[:group_count] - tree[:top_group_count],
                'nested_component_count'            => tree[:component_count] - tree[:top_component_count],
                'deepest_level'                     => tree[:deepest_level],
                'locked_container_count'            => tree[:locked_container_count],
                'unique_component_definition_count' => tree_context[:component_def_ids].length,
                'levels'                            => na_level_rows(tree_context[:levels], tree[:deepest_level]),
                'plans'                             => {
                    Na__GroupComponentConverter__Options::NA_DIRECTION_GROUPS_TO_COMPONENTS => {
                        Na__GroupComponentConverter__Options::NA_SCOPE_CURRENT_LEVEL => na_plan_payload(g2c_current),
                        Na__GroupComponentConverter__Options::NA_SCOPE_DEEP_NESTING  => na_plan_payload(g2c_deep[:plan])
                    },
                    Na__GroupComponentConverter__Options::NA_DIRECTION_COMPONENTS_TO_GROUPS => {
                        Na__GroupComponentConverter__Options::NA_SCOPE_CURRENT_LEVEL => na_plan_payload(tree_context[:c2g_current]),
                        Na__GroupComponentConverter__Options::NA_SCOPE_DEEP_NESTING  => na_plan_payload(tree_context[:c2g_deep])
                    }
                },
                'depth_limit_count'                 => tree_context[:depth_limit_count] + g2c_deep[:depth_limit_count],
                'limit_reached'                     => !!(tree_context[:limit_reached] || g2c_deep[:limit_reached]),
                'preview_limit'                     => NA_PREVIEW_ENTITY_LIMIT
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Per-Level Rows, the Deepest Levels Folded Into One
        # ------------------------------------------------------------
        def self.na_level_rows(levels, deepest_level)
            rows = []
            (1..[deepest_level, NA_LEVEL_ROW_LIMIT].min).each do |level|
                rows << na_level_row(level.to_s, levels[level][:groups], levels[level][:components])
            end
            return rows if deepest_level <= NA_LEVEL_ROW_LIMIT

            deeper = ((NA_LEVEL_ROW_LIMIT + 1)..deepest_level).map { |level| levels[level] }
            rows << na_level_row(
                "#{NA_LEVEL_ROW_LIMIT + 1}+",
                deeper.sum { |counts| counts[:groups] },
                deeper.sum { |counts| counts[:components] }
            )
            rows
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | One Row of the Nesting Breakdown
        # ------------------------------------------------------------
        def self.na_level_row(label, group_count, component_count)
            {
                'label'      => label,
                'groups'     => group_count,
                'components' => component_count
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | String-Keyed Copy of One Plan
        # ------------------------------------------------------------
        def self.na_plan_payload(plan)
            plan.each_with_object({}) do |(key, value), payload|
                payload[key.to_s] = value
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Zeroed Plan Counters
        # ------------------------------------------------------------
        def self.na_empty_plan
            {
                convert_count:             0,
                top_level_count:           0,
                nested_count:              0,
                locked_skipped_count:      0,
                empty_skipped_count:       0,
                merged_count:              0,
                new_definition_count:      0,
                affected_definition_count: 0,
                outside_placement_count:   0,
                repeat_count:              0,
                glue_or_cut_count:         0,
                other_placement_count:     0,
                unique_definition_count:   0,
                common_definition_count:   0,
                common_group_count:        0,
                single_definition_count:   0,
                common_preview_partial:    false
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Zeroed Tree Counters
        # ------------------------------------------------------------
        def self.na_empty_tree
            {
                group_count:            0,
                component_count:        0,
                top_group_count:        0,
                top_component_count:    0,
                deepest_level:          0,
                locked_container_count: 0
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Empty Dialog Payload
        # ------------------------------------------------------------
        def self.na_empty_summary
            empty_plan = na_plan_payload(na_empty_plan)

            {
                'has_selection'                     => false,
                'selected_count'                    => 0,
                'group_count'                       => 0,
                'component_count'                   => 0,
                'top_group_count'                   => 0,
                'top_component_count'               => 0,
                'nested_group_count'                => 0,
                'nested_component_count'            => 0,
                'deepest_level'                     => 0,
                'locked_container_count'            => 0,
                'unique_component_definition_count' => 0,
                'levels'                            => [],
                'plans'                             => {
                    Na__GroupComponentConverter__Options::NA_DIRECTION_GROUPS_TO_COMPONENTS => {
                        Na__GroupComponentConverter__Options::NA_SCOPE_CURRENT_LEVEL => empty_plan.dup,
                        Na__GroupComponentConverter__Options::NA_SCOPE_DEEP_NESTING  => empty_plan.dup
                    },
                    Na__GroupComponentConverter__Options::NA_DIRECTION_COMPONENTS_TO_GROUPS => {
                        Na__GroupComponentConverter__Options::NA_SCOPE_CURRENT_LEVEL => empty_plan.dup,
                        Na__GroupComponentConverter__Options::NA_SCOPE_DEEP_NESTING  => empty_plan.dup
                    }
                },
                'depth_limit_count'                 => 0,
                'limit_reached'                     => false,
                'preview_limit'                     => NA_PREVIEW_ENTITY_LIMIT
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | True When the Entity Is a Group or Component Instance
        # ------------------------------------------------------------
        def self.na_container?(entity)
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When the Entity Can Still Be Read
        # ------------------------------------------------------------
        def self.na_valid_entity?(entity)
            entity && entity.valid?
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Definition for a Group or Component Instance
        # ------------------------------------------------------------
        def self.na_definition_for(entity)
            return nil unless entity.respond_to?(:definition)

            entity.definition
        rescue
            nil
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

        # HELPER FUNCTION | True When a Component Glues To or Cuts Faces
        # ------------------------------------------------------------
        def self.na_glues_or_cuts?(definition)
            behavior = definition.behavior
            !!(behavior.is2d? || behavior.cuts_opening?)
        rescue
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GroupComponentConverter__SelectionScanner
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
