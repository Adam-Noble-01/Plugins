# =============================================================================
# NA POINT CLOUD VIEWER - CLEAN - SETTINGS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Clean__Settings__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__CleanSettings
# PURPOSE    : The three filters as the user sets them (on / off, a strength
#              slider, Advanced values) and their translation into the
#              engine's physical parameters (CleanTypes.hpp, all lengths in
#              millimetres).
#
# STRENGTH -> PHYSICAL PARAMETERS (s = strength / 100; 50 = the engine
#   defaults the test suite runs; every mapping is monotonic and named):
#   Remove Noise
#     isolated ratio      3.0 x 1.5^(1 - 2s)    4.5 .. 3.0 .. 2.0   (lower removes more)
#     group size          35 x 2^(2s - 1)       18 .. 35 .. 70 points (smaller groups go)
#     group extent        200 x 1.5^(2s - 1)    133 .. 200 .. 300 mm
#     scatter ratio       2.5 x 1.4^(1 - 2s)    3.5 .. 2.5 .. 1.8
#   Refine Surfaces
#     strength            s                     share of the way to the local fit
#   Reduce Density
#     patch size          9 x 2.2^(2s - 1)      4.1 .. 9 .. 19.8 mm
#   An Advanced value the user has typed replaces the mapped one; Reset to
#   Defaults clears them all.
#
# WHERE IT LIVES: this computer's user config ('clean' section). Settings
#   belong to the person, not the model; the export records the exact values
#   in the new LAS (provenance).
#
# =============================================================================

module Na__PointCloudViewer
    module Na__CleanSettings

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_FILTERS = %w[noise refine density].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Read
    # -------------------------------------------------------------------------

        # The filter definitions from the plugin config (labels, explanations,
        # default strength, Advanced parameter specs).
        def self.Na__CleanSettings__Spec
            spec = Na__ConfigLoader.Na__Config__GetOr({}, 'clean', 'filters')
            spec.is_a?(Hash) ? spec : {}
        end

        # { 'noise' => { 'enabled', 'strength', 'advanced' => { key => number } }, ... }
        def self.Na__CleanSettings__Current
            stored = Na__UserConfigStore.Na__UserConfig__Get('clean', 'filters', {})
            stored = {} unless stored.is_a?(Hash)
            spec = self.Na__CleanSettings__Spec
            NA_FILTERS.to_h do |filter|
                defaults = spec[filter].is_a?(Hash) ? spec[filter] : {}
                saved = stored[filter].is_a?(Hash) ? stored[filter] : {}
                advanced = saved['advanced'].is_a?(Hash) ? saved['advanced'] : {}
                specs = self.na_advanced_specs(filter)
                clean_advanced = advanced.each_with_object({}) do |(key, value), out|
                    item = specs.find { |entry| entry['key'] == key }
                    next unless item
                    number = self.na_number(value)
                    out[key] = self.na_clamp(number, item) unless number.nil?
                end
                enabled = saved.key?('enabled') ? saved['enabled'] == true : defaults['enabled'] == true
                strength = self.na_number(saved['strength']) || self.na_number(defaults['strength']) || 50.0
                [filter, { 'enabled' => enabled, 'strength' => [[strength, 0.0].max, 100.0].min, 'advanced' => clean_advanced }]
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Change (each returns nil or a plain-English reason)
    # -------------------------------------------------------------------------

        # change: { 'filter' => 'noise', 'enabled' => bool, 'strength' => 0..100,
        #           'advanced' => { key => number or '' (back to the mapped value) } }
        def self.Na__CleanSettings__Apply(change)
            filter = change['filter'].to_s
            return 'Unknown filter.' unless NA_FILTERS.include?(filter)
            current = self.Na__CleanSettings__Current
            entry = current[filter]
            entry['enabled'] = change['enabled'] == true if change.key?('enabled')
            if change.key?('strength')
                number = self.na_number(change['strength'])
                return 'The strength must be a number from 0 to 100.' if number.nil?
                entry['strength'] = [[number, 0.0].max, 100.0].min
            end
            if change['advanced'].is_a?(Hash)
                specs = self.na_advanced_specs(filter)
                change['advanced'].each do |key, value|
                    item = specs.find { |spec| spec['key'] == key }
                    return "Unknown setting '#{key}'." unless item
                    if value.nil? || value.to_s.strip.empty?
                        entry['advanced'].delete(key)
                        next
                    end
                    number = self.na_number(value)
                    return "#{item['label']} must be a number." if number.nil?
                    if number < item['min'].to_f || number > item['max'].to_f
                        return "#{item['label']} must be between #{self.na_trim(item['min'])} and #{self.na_trim(item['max'])}#{item['unit'] ? ' ' + item['unit'] : ''}."
                    end
                    entry['advanced'][key] = number
                end
            end
            Na__UserConfigStore.Na__UserConfig__Set('clean', 'filters', current)
            nil
        end

        def self.Na__CleanSettings__Reset
            Na__UserConfigStore.Na__UserConfig__Set('clean', 'filters', {})
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Engine Parameters
    # -------------------------------------------------------------------------

        # The physical values (mm, ratios) each filter runs with: the strength
        # mapping, then any Advanced value typed by the user.
        def self.Na__CleanSettings__Physical(settings = nil)
            settings ||= self.Na__CleanSettings__Current
            noise   = settings['noise']
            refine  = settings['refine']
            density = settings['density']
            sn = noise['strength'] / 100.0
            sr = refine['strength'] / 100.0
            sd = density['strength'] / 100.0
            mapped = {
                'noise' => {
                    'iso_ratio'          => 3.0 * 1.5**(1.0 - 2.0 * sn),
                    'iso_min_mm'         => 20.0,
                    'knn_cap_mm'         => 100.0,
                    'link_factor'        => 3.0,
                    'link_min_mm'        => 40.0,
                    'link_max_mm'        => 120.0,
                    'cluster_min_points' => (35.0 * 2.0**(2.0 * sn - 1.0)).round.to_f,
                    'cluster_max_mm'     => 200.0 * 1.5**(2.0 * sn - 1.0),
                    'scatter_ratio'      => 2.5 * 1.4**(1.0 - 2.0 * sn),
                    'blowout_remove'     => 0.0
                },
                'refine' => {
                    'refine_strength'    => sr,
                    'max_move_mm'        => 25.0,
                    'cell_mm'            => 50.0,
                    'smooth_radius_mm'   => 30.0,
                    'inlier_band'        => 3.0,
                    'pass_gap_s'         => 2.0,
                    'pass_disagree_mm'   => 15.0,
                    'doubling_hold'      => 1.0,
                    'sigma_fallback_mm'  => 8.0
                },
                'density' => {
                    'voxel_mm'           => 9.0 * 2.2**(2.0 * sd - 1.0),
                    'feature_factor'     => 2.5
                }
            }
            NA_FILTERS.each do |filter|
                settings[filter]['advanced'].each { |key, value| mapped[filter][key] = value.to_f if mapped[filter].key?(key) }
            end
            # the engine fits the local surface within one analysis cell at most
            mapped['refine']['smooth_radius_mm'] = [mapped['refine']['smooth_radius_mm'], mapped['refine']['cell_mm']].min
            mapped['noise']['link_max_mm'] = [mapped['noise']['link_max_mm'], mapped['noise']['link_min_mm']].max
            mapped
        end

        # NA_CLEAN_PARAM_KEYS numbers for the engine. mm_per_unit comes from
        # the unit the user chose when the cloud was imported: never guessed.
        def self.Na__CleanSettings__EngineParams(mm_per_unit, settings = nil)
            settings ||= self.Na__CleanSettings__Current
            physical = self.Na__CleanSettings__Physical(settings)
            values = physical['noise'].merge(physical['refine']).merge(physical['density'])
            values['mm_per_unit']     = mm_per_unit.to_f
            values['noise_enabled']   = settings['noise']['enabled'] ? 1.0 : 0.0
            values['refine_enabled']  = settings['refine']['enabled'] ? 1.0 : 0.0
            values['density_enabled'] = settings['density']['enabled'] ? 1.0 : 0.0
            Na__NativeEngine::NA_CLEAN_PARAM_KEYS.map { |key| values.fetch(key).to_f }
        end

        # Millimetres per source unit, from the unit chosen at import.
        def self.Na__CleanSettings__MmPerUnit(cloud)
            Na__UnitContract.Na__Units__InchesPerSourceUnit(cloud.source_unit) * 25.4
        end

        # Recorded in the exported LAS: what the user set and what ran.
        def self.Na__CleanSettings__Provenance(settings = nil)
            settings ||= self.Na__CleanSettings__Current
            physical = self.Na__CleanSettings__Physical(settings)
            NA_FILTERS.to_h do |filter|
                [filter, { 'enabled' => settings[filter]['enabled'], 'strength' => settings[filter]['strength'].round(1),
                           'values' => physical[filter].transform_values { |v| v.round(4) } }]
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Payload
    # -------------------------------------------------------------------------

        def self.Na__CleanSettings__Payload
            settings = self.Na__CleanSettings__Current
            physical = self.Na__CleanSettings__Physical(settings)
            spec = self.Na__CleanSettings__Spec
            NA_FILTERS.to_h do |filter|
                info = spec[filter].is_a?(Hash) ? spec[filter] : {}
                [filter, {
                    'enabled'   => settings[filter]['enabled'],
                    'strength'  => settings[filter]['strength'],
                    'label'     => info['label'].to_s,
                    'summary'   => info['summary'].to_s,
                    'strengthLow'  => info['strengthLow'].to_s,
                    'strengthHigh' => info['strengthHigh'].to_s,
                    'mapped'    => self.na_mapped_text(filter, physical[filter]),
                    'advanced'  => self.na_advanced_specs(filter).map do |item|
                        typed = settings[filter]['advanced'][item['key']]
                        item.merge('value' => physical[filter][item['key']], 'isOverride' => !typed.nil?)
                    end
                }]
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_advanced_specs(filter)
            info = self.Na__CleanSettings__Spec[filter]
            list = info.is_a?(Hash) && info['advanced'].is_a?(Array) ? info['advanced'] : []
            list.select { |item| item.is_a?(Hash) && item['key'].is_a?(String) }
        end

        # What the slider currently means, in plain words.
        def self.na_mapped_text(filter, values)
            case filter
            when 'noise'
                "Removes points more than #{self.na_trim(values['iso_ratio'], 1)} x as far from their neighbours as the surface around them, " \
                    "and detached groups under #{values['cluster_min_points'].round} points and #{values['cluster_max_mm'].round} mm."
            when 'refine'
                "Moves each surface point #{(values['refine_strength'] * 100).round} % of the way to its local fit, never more than #{self.na_trim(values['max_move_mm'], 1)} mm."
            when 'density'
                "About one point per #{self.na_trim(values['voxel_mm'], 1)} mm on plain surfaces, " \
                    "#{self.na_trim(values['voxel_mm'] / [values['feature_factor'], 1.0].max, 1)} mm at corners, edges and small objects."
            else ''
            end
        end

        def self.na_number(value)
            return nil if value.nil?
            return value.to_f if value.is_a?(Numeric) && value.to_f.finite?
            text = value.to_s.strip
            return nil unless text.match?(/\A-?\d+(\.\d+)?\z/)
            text.to_f
        end

        def self.na_clamp(number, item)
            [[number, item['min'].to_f].max, item['max'].to_f].min
        end

        def self.na_trim(value, decimals = 3)
            Na__UnitContract.Na__Units__TrimNumber(value.to_f, decimals)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
