# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - DATA FORMATTERS
# =============================================================================
#
# FILE       : Na__SelectionStats__AppUtils__DataFormatters__.rb
# PURPOSE    : Plain-Ruby projections for hashes → UI-bound arrays (sorting, trim).
#
# =============================================================================

module Na__SelectionStats
    module Na__AppUtils
        module Na__DataFormatters
            extend self

# -----------------------------------------------------------------------------
# REGION | Named Count Collections
# -----------------------------------------------------------------------------

            def na_material_hash_to_sorted_array(material_hash)
                material_hash.values.sort_by { |item| [-item[:count], item[:name].downcase] }.map do |item|
                    {
                        name: item[:name],
                        count: item[:count],
                        slots: na_hash_to_sorted_name_count_array(item[:slots])
                    }
                end
            end

            def na_hash_to_sorted_name_count_array(hash)
                hash.map { |name, count| { name: name.to_s, count: count.to_i } }
                    .sort_by { |item| [-item[:count], item[:name].downcase] }
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Truncation
# -----------------------------------------------------------------------------

            def na_trim_array(array, max_items)
                return array if array.length <= max_items

                array.first(max_items) + [{ truncated: true, omitted_count: array.length - max_items }]
            end

# endregion -------------------------------------------------------------------

        end
    end
end
