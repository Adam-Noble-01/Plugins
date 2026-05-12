# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - STATS BUILDER · DICTIONARY COLLECTOR
# =============================================================================
#
# FILE       : Na__SelectionStats__StatsBuilder__DictionaryCollector__.rb
# PURPOSE    : Flatten attribute dictionaries (model, entity, definitions) into rows.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'

# endregion -------------------------------------------------------------------

module Na__SelectionStats
    module Na__DictionaryCollector
        extend self

# -----------------------------------------------------------------------------
# REGION | Attribute Dictionary Rows
# -----------------------------------------------------------------------------

        def na_collect_owner_dictionaries(owner, owner_type, owner_label, target_array)
            return nil unless owner.respond_to?(:attribute_dictionaries)

            dictionaries = owner.attribute_dictionaries
            return nil unless dictionaries

            max_keys = Na__SelectionStats::Na__AppData::Na__Constants::MAX_DICTIONARY_KEYS

            dictionaries.each do |dictionary|
                keys = []
                dictionary.each_key { |key| keys << key.to_s }

                target_array << {
                    owner: owner_label,
                    owner_type: owner_type,
                    name: dictionary.name.to_s,
                    key_count: keys.length,
                    keys: keys.first(max_keys)
                }
            end

            nil
        rescue StandardError
            nil
        end

# endregion -------------------------------------------------------------------

    end
end
