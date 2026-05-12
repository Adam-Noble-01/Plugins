# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - STATS BUILDER · ENTITY WALKER
# =============================================================================
#
# FILE       : Na__SelectionStats__StatsBuilder__EntityWalker__.rb
# PURPOSE    : Recursive selection walk (groups, defs, primitives, dictionaries).
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'

# endregion -------------------------------------------------------------------

module Na__SelectionStats
    module Na__EntityWalker
        extend self

# -----------------------------------------------------------------------------
# REGION | Cross-Refs
# -----------------------------------------------------------------------------

        EH = Na__SelectionStats::Na__AppUtils::Na__EntityHelpers
        FA = Na__SelectionStats::Na__GeometryHelpers::Na__FaceAnalysis
        MT = Na__SelectionStats::Na__MaterialTracker
        DC = Na__SelectionStats::Na__DictionaryCollector
        NC = Na__SelectionStats::Na__NameAndDynamicAttributeCollector

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Dispatch
# -----------------------------------------------------------------------------

        def na_accumulate_entity_recursive(entity, stats, tracker, path_key, owner_label, definition_stack)
            return nil unless EH.na_entity_usable?(entity)

            type_name = EH.na_entity_type_name(entity)
            tracker[:entity_types][type_name] ||= 0
            tracker[:entity_types][type_name] += 1

            DC.na_collect_owner_dictionaries(
                entity,
                type_name,
                owner_label,
                stats[:entity_dictionaries]
            )
            NC.na_collect_entity_names(entity, type_name, owner_label, stats[:sketchup_names])
            NC.na_collect_dynamic_component_attributes(entity, type_name, owner_label, stats[:dynamic_attributes])
            MT.na_record_entity_material(entity, tracker, owner_label)

            case entity
            when Sketchup::Face
                na_accumulate_face(entity, stats, tracker, path_key, owner_label)
            when Sketchup::Edge
                na_accumulate_edge(entity, tracker, path_key)
            when Sketchup::Group
                stats[:groups] += 1
                stats[:nested_containers] += 1 unless definition_stack.empty?
                group_definition = entity.respond_to?(:definition) ? entity.definition : nil
                NC.na_collect_dynamic_component_attributes(
                    group_definition,
                    'GroupDefinition',
                    "#{owner_label} > Definition",
                    stats[:dynamic_attributes]
                )
                na_accumulate_entities_collection_recursive(
                    entity.entities,
                    stats,
                    tracker,
                    "#{path_key}/group_#{EH.na_stable_token(entity)}",
                    "#{owner_label} > Group",
                    definition_stack
                )
            when Sketchup::ComponentInstance
                stats[:component_instances] += 1
                stats[:nested_containers] += 1 unless definition_stack.empty?
                na_accumulate_component_instance_recursive(
                    entity,
                    stats,
                    tracker,
                    path_key,
                    owner_label,
                    definition_stack
                )
            else
                na_accumulate_special_entity_if_supported(entity, stats, tracker, path_key, owner_label, definition_stack)
            end

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Special Entity Types
# -----------------------------------------------------------------------------

        def na_accumulate_special_entity_if_supported(entity, stats, tracker, path_key, owner_label, definition_stack)
            if defined?(Sketchup::Image) && entity.is_a?(Sketchup::Image)
                stats[:images] += 1
                return nil
            end

            if defined?(Sketchup::Curve) && entity.is_a?(Sketchup::Curve) && entity.respond_to?(:edges)
                stats[:curves] += 1
                entity.edges.each do |edge|
                    na_accumulate_edge(edge, tracker, path_key)
                end
                return nil
            end

            if entity.respond_to?(:entities)
                stats[:nested_containers] += 1 unless definition_stack.empty?
                na_accumulate_entities_collection_recursive(
                    entity.entities,
                    stats,
                    tracker,
                    "#{path_key}/entities_#{EH.na_stable_token(entity)}",
                    "#{owner_label} > Entities",
                    definition_stack
                )
            end

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Component Instances
# -----------------------------------------------------------------------------

        def na_accumulate_component_instance_recursive(entity, stats, tracker, path_key, owner_label, definition_stack)
            definition = entity.definition
            return nil unless definition

            definition_token = EH.na_stable_token(definition)
            if definition_stack.include?(definition_token)
                stats[:warnings] << "Skipped recursive component definition at #{owner_label}."
                return nil
            end

            DC.na_collect_owner_dictionaries(
                definition,
                'ComponentDefinition',
                "#{owner_label} > Definition",
                stats[:entity_dictionaries]
            )
            NC.na_collect_dynamic_component_attributes(
                definition,
                'ComponentDefinition',
                "#{owner_label} > Definition",
                stats[:dynamic_attributes]
            )

            na_accumulate_entities_collection_recursive(
                definition.entities,
                stats,
                tracker,
                "#{path_key}/instance_#{EH.na_stable_token(entity)}",
                "#{owner_label} > #{EH.na_component_definition_name(definition)}",
                definition_stack + [definition_token]
            )

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entity Collections
# -----------------------------------------------------------------------------

        def na_accumulate_entities_collection_recursive(entities, stats, tracker, path_key, owner_label, definition_stack)
            return nil unless entities

            entities.each do |child_entity|
                child_token = EH.na_stable_token(child_entity)
                child_path_key = "#{path_key}/#{child_token}"
                child_label = "#{owner_label} > #{EH.na_entity_type_name(child_entity)}"
                na_accumulate_entity_recursive(
                    child_entity,
                    stats,
                    tracker,
                    child_path_key,
                    child_label,
                    definition_stack
                )
            end

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Accumulation
# -----------------------------------------------------------------------------

        def na_accumulate_face(face, stats, tracker, path_key, owner_label)
            face_key = "#{path_key}/face_#{EH.na_stable_token(face)}"
            return nil if tracker[:faces].key?(face_key)

            tracker[:faces][face_key] = true
            MT.na_record_face_materials(face, tracker, owner_label)

            face.edges.each do |edge|
                na_accumulate_edge(edge, tracker, path_key)
            end

            face.vertices.each do |vertex|
                na_accumulate_vertex(vertex, tracker, path_key)
            end

            stats[:triangles] += FA.na_count_triangulated_mesh_polygons(face)

            stats[:native_triangular_faces] += 1 if FA.na_face_is_simple_native_triangle?(face)

            stats[:quads] += 1 if FA.na_face_is_simple_native_quad?(face)

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge & Vertex Accumulation
# -----------------------------------------------------------------------------

        def na_accumulate_edge(edge, tracker, path_key)
            return nil unless EH.na_entity_usable?(edge)

            edge_key = "#{path_key}/edge_#{EH.na_stable_token(edge)}"
            tracker[:edges][edge_key] = true

            edge.vertices.each do |vertex|
                na_accumulate_vertex(vertex, tracker, path_key)
            end

            nil
        end

        def na_accumulate_vertex(vertex, tracker, path_key)
            vertex_key = "#{path_key}/vertex_#{EH.na_stable_token(vertex)}"
            tracker[:vertices][vertex_key] = true
            nil
        end

# endregion -------------------------------------------------------------------

    end
end
