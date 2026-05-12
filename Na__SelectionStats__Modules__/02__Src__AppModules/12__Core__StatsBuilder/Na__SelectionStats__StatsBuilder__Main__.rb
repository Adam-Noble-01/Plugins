# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - STATS BUILDER (MAIN)
# =============================================================================
#
# FILE       : Na__SelectionStats__StatsBuilder__Main__.rb
# PURPOSE    : Assemble the recursive selection payload for the HtmlDialog bridge.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'

# endregion -------------------------------------------------------------------

module Na__SelectionStats
    module Na__StatsBuilder
        extend self

# -----------------------------------------------------------------------------
# REGION | Cross-Refs
# -----------------------------------------------------------------------------

        EW = Na__SelectionStats::Na__EntityWalker
        DF = Na__SelectionStats::Na__AppUtils::Na__DataFormatters
        EH = Na__SelectionStats::Na__AppUtils::Na__EntityHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Build Pipeline
# -----------------------------------------------------------------------------

        def na_build_stats(model)
            stats = na_create_empty_stats_hash
            return stats unless model

            selection = model.selection
            stats[:selection_count] = selection ? selection.length : 0
            stats[:model_title]     = EH.na_model_title(model)
            stats[:last_updated]    = Time.now.strftime('%H:%M:%S')

            tracker = na_create_empty_tracker_hash

            Na__SelectionStats::Na__DictionaryCollector.na_collect_owner_dictionaries(
                model,
                'Model',
                'Active Model',
                stats[:model_dictionaries]
            )

            if selection
                selection.each_with_index do |entity, index|
                    root_path_key = "active_context.selection_#{index}"
                    root_label = "Selection #{index + 1}"
                    EW.na_accumulate_entity_recursive(
                        entity,
                        stats,
                        tracker,
                        root_path_key,
                        root_label,
                        []
                    )
                end
            end

            const_mod = Na__SelectionStats::Na__AppData::Na__Constants

            stats[:edges]               = tracker[:edges].length
            stats[:faces]               = tracker[:faces].length
            stats[:vertices]           = tracker[:vertices].length
            stats[:materials]          = DF.na_material_hash_to_sorted_array(tracker[:materials])
            stats[:entity_types]       = DF.na_hash_to_sorted_name_count_array(tracker[:entity_types])
            stats[:entity_dictionaries] = DF.na_trim_array(stats[:entity_dictionaries], const_mod::MAX_LIST_ITEMS)
            stats[:model_dictionaries]    = DF.na_trim_array(stats[:model_dictionaries], const_mod::MAX_LIST_ITEMS)
            stats[:warnings]              = DF.na_trim_array(stats[:warnings], const_mod::WARNINGS_TRUNCATE_AFTER)
            stats
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Empty-State Factories
# -----------------------------------------------------------------------------

        def na_create_empty_stats_hash
            {
                model_title: '',
                last_updated: '',
                selection_count: 0,
                triangles: 0,
                native_triangular_faces: 0,
                edges: 0,
                faces: 0,
                vertices: 0,
                quads: 0,
                groups: 0,
                component_instances: 0,
                images: 0,
                curves: 0,
                nested_containers: 0,
                materials: [],
                entity_types: [],
                model_dictionaries: [],
                entity_dictionaries: [],
                warnings: []
            }
        end

        def na_create_empty_tracker_hash
            {
                edges: {},
                faces: {},
                vertices: {},
                materials: {},
                entity_types: {}
            }
        end

# endregion -------------------------------------------------------------------

    end
end
