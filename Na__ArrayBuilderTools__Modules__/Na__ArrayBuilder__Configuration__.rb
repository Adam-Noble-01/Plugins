# =============================================================================
# NA ARRAY BUILDER TOOLS - CONFIGURATION
# =============================================================================
# FILE       : Na__ArrayBuilder__Configuration__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Canonical, validated settings shared by creation, edit and presets.
# =============================================================================

require 'json'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__Configuration

        NA_DEFAULTS = {
            'type' => 'block', 'unit_width_mm' => 110.0,
            'unit_depth_mm' => 30.0, 'unit_height_mm' => 75.0,
            'spacing_mm' => 115.0, 'distribution' => 'fixed', 'inset_mm' => 200.0,
            'anchor_mode' => 'local_axis', 'keep_upright' => false,
            'reverse_path' => false, 'path_source' => 'draw',
            'offset_lateral_mm' => 0.0, 'offset_vertical_mm' => 0.0,
            'merge_corners' => false
        }.freeze
        NA_ENUMS = {
            'type' => %w[block object], 'distribution' => %w[fixed normalise inset],
            'anchor_mode' => %w[local_axis centre], 'path_source' => %w[draw selection]
        }.freeze
        NA_LIMIT = 1_000_000.0

        # FUNCTION | Validate Without Replacing Missing Fields With Zero
        # ------------------------------------------------------------
        def self.Na__Config__Resolve(na_input = {})
            na_input = JSON.parse(na_input) if na_input.is_a?(String)
            raise ArgumentError, 'Array settings must be an object.' unless na_input.is_a?(Hash)
            na_result = NA_DEFAULTS.merge(na_input.select { |na_key, _| NA_DEFAULTS.key?(na_key) })
            NA_ENUMS.each do |na_key, na_values|
                raise ArgumentError, "Invalid #{na_key.tr('_', ' ')}." unless na_values.include?(na_result[na_key])
            end
            NA_DEFAULTS.each do |na_key, na_default|
                next unless na_default.is_a?(Numeric)
                na_value = Float(na_result[na_key]) rescue nil
                na_signed = na_key.start_with?('offset_') || na_key == 'inset_mm'
                na_min = na_signed ? -NA_LIMIT : (na_key.start_with?('unit_') ? 0.1 : 0.0)
                unless na_value && na_value.finite? && na_value.between?(na_min, NA_LIMIT)
                    raise ArgumentError, "#{na_key.tr('_', ' ')} must be between #{na_min} and #{NA_LIMIT.to_i}."
                end
                na_result[na_key] = na_value
            end
            %w[keep_upright reverse_path merge_corners].each do |na_key|
                raise ArgumentError, "Invalid #{na_key}." unless [true, false].include?(na_result[na_key])
            end
            na_result
        end
        # ---------------------------------------------------------------

    end # module Na__ArrayBuilder__Configuration
end # module Na__ArrayBuilderTools
