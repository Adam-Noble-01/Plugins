# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MEGA EXPLODE - STATS COLLECTOR
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MegaExplode__StatsCollector__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MegaExplode__StatsCollector
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Walk the current selection and summarise nested containers,
#              geometry, tags and materials for the Mega Explode dialog
# CREATED    : 2026
#
# SAFETY:
# - Read-only. Nothing is exploded, unlocked or painted here.
# - Locked containers are counted and still walked, because Mega Explode
#   reports what is nested even when it will later skip them.
# - Recursion is capped and definition identity is tracked to stop cycles.
# - Live preview walks stop at NA_PREVIEW_ENTITY_LIMIT so a huge selection
#   cannot stall the dialog. The explode path itself is never capped.
#
# =============================================================================

require 'set'

module Na__Noble3dModellingTools
    module Na__MegaExplode__StatsCollector

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_RECURSION_DEPTH  = 64
        NA_PREVIEW_ENTITY_LIMIT = 50_000
        NA_LIMIT_THROW_TAG     = :na_mega_explode_limit

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Collection API
# -----------------------------------------------------------------------------

        # FUNCTION | Summarise the Current Selection for the Dialog
        # ------------------------------------------------------------
        # @param selection [Sketchup::Selection, Array]
        # @param model     [Sketchup::Model]
        # @param face_limit [Integer, nil] Preview cap; nil walks everything
        # @return [Hash] String-keyed payload for the HtmlDialog
        # ------------------------------------------------------------
        def self.Na__MegaExplode__StatsCollector__Collect(selection, model, entity_limit = NA_PREVIEW_ENTITY_LIMIT)
            return na_empty_summary unless model && selection

            selected_entities = selection.to_a
            return na_empty_summary if selected_entities.empty?

            context = {
                stats:              na_empty_statistics,
                seen_defs:          Set.new,
                definitions_by_id: {},
                selected_instances: Hash.new { |hash, key| hash[key] = Set.new },
                tag_names:          Set.new,
                material_ids:       Set.new,
                untagged_layer:    na_untagged_layer(model),
                limit:              entity_limit,
                visited_count:     0
            }

            catch(NA_LIMIT_THROW_TAG) do
                selected_entities.each do |entity|
                    na_walk_entity(entity, context, 1, [], true)
                end
            end

            na_summary_from_context(context, selected_entities.length, model)
        rescue => error
            puts "[Na__MegaExplode] Stats collection warning: #{error.class}: #{error.message}"
            na_empty_summary
        end
        # ------------------------------------------------------------

        # FUNCTION | Build the Empty Selection Payload
        # ------------------------------------------------------------
        def self.Na__MegaExplode__StatsCollector__EmptySummary
            na_empty_summary
        end
        # ------------------------------------------------------------

        # FUNCTION | Display Name of SketchUp's Default Tag (Layer0)
        # ------------------------------------------------------------
        def self.Na__MegaExplode__StatsCollector__UntaggedDisplayName(model)
            layer = na_untagged_layer(model)
            return 'Untagged' unless layer

            return layer.display_name if layer.respond_to?(:display_name)

            'Untagged'
        rescue
            'Untagged'
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Walk
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Walk One Entity and Its Nested Contents
        # ------------------------------------------------------------
        def self.na_walk_entity(entity, context, depth, definition_stack, count_as_selected)
            return unless na_valid_entity?(entity)

            na_bump_visit_count(context)
            na_record_drawing_stats(entity, context, count_as_selected)

            return unless na_container?(entity)

            na_record_container(entity, context, depth)
            na_walk_container_contents(entity, context, depth, definition_stack)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record Group / Component Totals at This Depth
        # ------------------------------------------------------------
        def self.na_record_container(entity, context, depth)
            stats = context[:stats]
            stats[:deepest_level] = depth if depth > stats[:deepest_level]
            stats[:locked_container_count] += 1 if entity.locked?

            if entity.is_a?(Sketchup::Group)
                stats[:group_count] += 1
            else
                stats[:component_count] += 1
            end

            definition = na_container_definition(entity)
            return unless definition

            definition_id = definition.entityID
            context[:seen_defs] << definition_id
            context[:definitions_by_id][definition_id] = definition
            context[:selected_instances][definition_id] << entity.entityID
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Descend Into a Group or Component Definition
        # ------------------------------------------------------------
        def self.na_walk_container_contents(entity, context, depth, definition_stack)
            if depth > NA_MAX_RECURSION_DEPTH
                context[:stats][:depth_limit_count] += 1
                return
            end

            definition = na_container_definition(entity)
            return unless definition

            definition_id = definition.entityID
            if definition_stack.include?(definition_id)
                context[:stats][:cyclic_container_count] += 1
                return
            end

            next_stack = definition_stack + [definition_id]
            definition.entities.each do |child|
                na_walk_entity(child, context, depth + 1, next_stack, false)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count Faces, Edges, Tags and Materials
        # ------------------------------------------------------------
        def self.na_record_drawing_stats(entity, context, count_as_selected)
            stats = context[:stats]
            stats[:selected_leaf_count] += 1 if count_as_selected && !na_container?(entity)

            case entity
            when Sketchup::Face
                stats[:face_count] += 1
            when Sketchup::Edge
                stats[:edge_count] += 1
            when Sketchup::Image
                stats[:image_count] += 1
            end

            na_record_tag(entity, context)
            na_record_material(entity, context)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record a Non-Default Tag Name
        # ------------------------------------------------------------
        def self.na_record_tag(entity, context)
            return unless entity.respond_to?(:layer) && entity.layer

            layer = entity.layer
            return if context[:untagged_layer] && layer == context[:untagged_layer]

            context[:tag_names] << na_layer_display_name(layer)
            context[:stats][:tagged_entity_count] += 1
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record Front and Back Materials
        # ------------------------------------------------------------
        def self.na_record_material(entity, context)
            na_remember_material(entity.material, context) if entity.respond_to?(:material)
            return unless entity.is_a?(Sketchup::Face)

            na_remember_material(entity.back_material, context)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Remember One Non-Default Material
        # ------------------------------------------------------------
        def self.na_remember_material(material, context)
            return if material.nil?

            context[:material_ids] << material.entityID
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Stop the Preview Walk Once the Cap Is Hit
        # ------------------------------------------------------------
        def self.na_bump_visit_count(context)
            return unless context[:limit]

            context[:visited_count] += 1
            return if context[:visited_count] <= context[:limit]

            context[:stats][:limit_reached] = true
            throw(NA_LIMIT_THROW_TAG)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Assembly
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert the Walk Context Into a JS Payload
        # ------------------------------------------------------------
        def self.na_summary_from_context(context, selected_count, model)
            stats = context[:stats]
            untagged_name = Na__MegaExplode__StatsCollector__UntaggedDisplayName(model)

            {
                'has_selection'           => true,
                'selected_count'          => selected_count,
                'group_count'             => stats[:group_count],
                'component_count'         => stats[:component_count],
                'container_count'         => stats[:group_count] + stats[:component_count],
                'unique_definition_count' => context[:seen_defs].length,
                'deepest_level'           => stats[:deepest_level],
                'face_count'              => stats[:face_count],
                'edge_count'              => stats[:edge_count],
                'image_count'             => stats[:image_count],
                'locked_container_count' => stats[:locked_container_count],
                'tagged_entity_count'    => stats[:tagged_entity_count],
                'unique_tag_count'        => context[:tag_names].length,
                'unique_material_count'  => context[:material_ids].length,
                'other_instance_count'   => na_other_instance_count(context),
                'cyclic_container_count'  => stats[:cyclic_container_count],
                'depth_limit_count'      => stats[:depth_limit_count],
                'limit_reached'           => stats[:limit_reached],
                'preview_limit'           => NA_PREVIEW_ENTITY_LIMIT,
                'untagged_display_name'  => untagged_name
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count Placements of Selected Definitions Outside the Walk
        # ------------------------------------------------------------
        def self.na_other_instance_count(context)
            other_count = 0
            context[:selected_instances].each do |definition_id, selected_ids|
                definition = context[:definitions_by_id][definition_id]
                next unless definition && definition.valid?

                other_count += [definition.instances.length - selected_ids.length, 0].max
            end
            other_count
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Empty Statistics Hash
        # ------------------------------------------------------------
        def self.na_empty_statistics
            {
                group_count:             0,
                component_count:         0,
                deepest_level:           0,
                face_count:              0,
                edge_count:              0,
                image_count:             0,
                locked_container_count:  0,
                tagged_entity_count:    0,
                cyclic_container_count:  0,
                depth_limit_count:       0,
                selected_leaf_count:    0,
                limit_reached:           false
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Empty Dialog Payload
        # ------------------------------------------------------------
        def self.na_empty_summary
            {
                'has_selection'           => false,
                'selected_count'          => 0,
                'group_count'             => 0,
                'component_count'         => 0,
                'container_count'         => 0,
                'unique_definition_count' => 0,
                'deepest_level'           => 0,
                'face_count'              => 0,
                'edge_count'              => 0,
                'image_count'             => 0,
                'locked_container_count' => 0,
                'tagged_entity_count'    => 0,
                'unique_tag_count'        => 0,
                'unique_material_count'  => 0,
                'other_instance_count'   => 0,
                'cyclic_container_count'  => 0,
                'depth_limit_count'      => 0,
                'limit_reached'           => false,
                'preview_limit'           => NA_PREVIEW_ENTITY_LIMIT,
                'untagged_display_name'  => 'Untagged'
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
        def self.na_container_definition(entity)
            return nil unless entity.respond_to?(:definition)

            entity.definition
        rescue
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | SketchUp's Default Layer0 / Untagged Tag
        # ------------------------------------------------------------
        def self.na_untagged_layer(model)
            return nil unless model && model.layers

            model.layers[0]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | UI Name for a Layer / Tag
        # ------------------------------------------------------------
        def self.na_layer_display_name(layer)
            return layer.display_name if layer.respond_to?(:display_name)

            layer.name.to_s
        rescue
            layer.name.to_s
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__MegaExplode__StatsCollector
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
