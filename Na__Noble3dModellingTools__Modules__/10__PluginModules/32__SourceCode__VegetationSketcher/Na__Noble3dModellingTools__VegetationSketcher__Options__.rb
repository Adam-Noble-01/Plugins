# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - OPTIONS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__Options__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__Options
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : One definition of vegetation presets, tree types, limits and
#              resolved millimetre settings shared by mesh, dialog and tools
# CREATED    : 2026
#
# Stored JSON keys and millimetre values stay stable so existing vegetation
# components continue to load. Representative species sizes are landscape
# specimens, not growth predictions; see the module README.
#
# =============================================================================

require 'json'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__HedgePath__'

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__Options

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_RESOLUTIONS = [10, 25, 50, 100, 200, 300, 500].freeze

        NA_COMMON = {
            'resolution'      => 100,
            'seed'            => 12345,
            'smooth'          => true,
            'shading_version' => 1,
            'vary'            => true,
            'length'          => 3000,
            'path'            => nil,
            'tree_type'       => 'generic',
            'shrub_type'      => 'generic',
            'plant_detail'    => 'medium'
        }.freeze

        NA_PRESETS = {
            'hedge' => {
                'width'           => 800,
                'depth'           => 800,
                'height'          => 1600,
                'soften'          => 45,
                'random'          => 55,
                'trunk_height'    => 700,
                'trunk_diameter'  => 160
            },
            'tree' => {
                'width'           => 3200,
                'depth'           => 2800,
                'height'          => 5200,
                'soften'          => 95,
                'random'          => 180,
                'trunk_height'    => 1800,
                'trunk_diameter'  => 240
            },
            'shrub' => {
                'width'           => 1200,
                'depth'           => 1000,
                'height'          => 900,
                'soften'          => 100,
                'random'          => 90,
                'trunk_height'    => 300,
                'trunk_diameter'  => 100
            }
        }.freeze

        NA_TREE_TYPES = {
            'generic' => {
                'name'        => 'Generic canopy',
                'botanical'   => '',
                'description' => 'An adjustable rounded whitecard canopy.',
                'settings'    => NA_PRESETS['tree']
            },
            'douglas_fir' => {
                'name'        => 'Douglas fir',
                'botanical'   => 'Pseudotsuga menziesii',
                'description' => 'Tiered conical crown. Landscape specimen: 18 m tall, 7 m spread. Forest trees can grow much larger.',
                'settings'    => {
                    'width'          => 7000,
                    'depth'          => 7000,
                    'height'         => 18000,
                    'trunk_height'   => 900,
                    'trunk_diameter' => 600,
                    'soften'         => 75,
                    'random'         => 160,
                    'resolution'     => 200
                }
            },
            'english_oak' => {
                'name'        => 'English oak',
                'botanical'   => 'Quercus robur',
                'description' => 'Broad, lobed crown with spreading limbs. Mature specimen: 20 m tall, 20 by 18 m spread.',
                'settings'    => {
                    'width'          => 20000,
                    'depth'          => 18000,
                    'height'         => 20000,
                    'trunk_height'   => 3500,
                    'trunk_diameter' => 1100,
                    'soften'         => 85,
                    'random'         => 350,
                    'resolution'     => 300
                }
            }
        }.freeze

        # Indicative planting forms, not species or maturity predictions.
        NA_SHRUB_TYPES = {
            'generic' => { 'name' => 'Generic shrub', 'description' => 'The original adjustable rounded shrub.', 'settings' => NA_PRESETS['shrub'] },
            'spreading' => { 'name' => 'Low spreading', 'description' => 'Low, irregular groundcover for the front of a bed.',
                'settings' => { 'width' => 800, 'depth' => 700, 'height' => 250, 'soften' => 85, 'random' => 22, 'resolution' => 100 } },
            'cushion' => { 'name' => 'Compact cushion', 'description' => 'A small, dense cushion for low edging and repeated groups.',
                'settings' => { 'width' => 550, 'depth' => 500, 'height' => 450, 'soften' => 95, 'random' => 25, 'resolution' => 100 } },
            'rounded' => { 'name' => 'Rounded shrub', 'description' => 'A softly lobed mid-height mound for the body of a planting bed.',
                'settings' => { 'width' => 850, 'depth' => 750, 'height' => 750, 'soften' => 85, 'random' => 45, 'resolution' => 100 } },
            'loose' => { 'name' => 'Loose flowering form', 'description' => 'An irregular, clustered outline suggesting a loose flowering shrub.',
                'settings' => { 'width' => 1100, 'depth' => 950, 'height' => 1000, 'soften' => 65, 'random' => 65, 'resolution' => 100 } },
            'upright' => { 'name' => 'Upright shrub', 'description' => 'A narrow, tapered accent for the back of a bed.',
                'settings' => { 'width' => 650, 'depth' => 600, 'height' => 1400, 'soften' => 75, 'random' => 45, 'resolution' => 100 } },
            'arching' => { 'name' => 'Arching shrub', 'description' => 'A broad, flared crown with drooping lobes to break up rounded planting.',
                'settings' => { 'width' => 1400, 'depth' => 1100, 'height' => 950, 'soften' => 70, 'random' => 55, 'resolution' => 100 } },
            'daisy_clump' => { 'name' => 'Daisy-like clump', 'procedural' => true, 'description' => 'Open petalled flowers on slender stems above a leafy basal clump.',
                'settings' => { 'width' => 650, 'depth' => 600, 'height' => 600, 'soften' => 65, 'random' => 35 } },
            'flower_spikes' => { 'name' => 'Flower spikes', 'procedural' => true, 'description' => 'Upright flowering spires with tiered whorls and paired leaves.',
                'settings' => { 'width' => 600, 'depth' => 550, 'height' => 850, 'soften' => 65, 'random' => 40 } },
            'umbel_clump' => { 'name' => 'Flat flower clusters', 'procedural' => true, 'description' => 'Branching stems with airy, flat-topped clusters of small flowers.',
                'settings' => { 'width' => 750, 'depth' => 650, 'height' => 800, 'soften' => 70, 'random' => 40 } },
            'tuft_grass' => { 'name' => 'Compact tuft grass', 'procedural' => true, 'description' => 'A low tuft of individually curved, creased grass blades.',
                'settings' => { 'width' => 500, 'depth' => 450, 'height' => 450, 'soften' => 60, 'random' => 30 } },
            'fountain_grass' => { 'name' => 'Fountain grass', 'procedural' => true, 'description' => 'Long arching blades, with upright inner leaves and cascading outer foliage.',
                'settings' => { 'width' => 950, 'depth' => 850, 'height' => 900, 'soften' => 85, 'random' => 50 } },
            'plume_grass' => { 'name' => 'Plumed grass', 'procedural' => true, 'description' => 'Arching foliage beneath tall stems and tapered, lobed seed plumes.',
                'settings' => { 'width' => 1000, 'depth' => 850, 'height' => 1400, 'soften' => 75, 'random' => 45 } }
        }.freeze

        NA_LIMITS = {
            'width'          => [50, 50000],
            'depth'          => [50, 50000],
            'height'         => [50, 100000],
            'length'         => [50, 100000],
            'soften'         => [0, 100],
            'random'         => [0, 500],
            'trunk_height'   => [25, 75000],
            'trunk_diameter' => [20, 5000],
            'seed'           => [1, 2147483646]
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Options API
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Complete Preset Hash For Hedge, Tree or Shrub
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Options__Preset(kind)
            kind = 'hedge' unless NA_PRESETS.key?(kind)
            NA_COMMON.merge(NA_PRESETS.fetch(kind, NA_PRESETS['hedge'])).merge('preset' => kind)
        end
        # ------------------------------------------------------------

        # FUNCTION | Build Tree Settings For a Named Species
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Options__TreePreset(type)
            raise ArgumentError, 'Choose a supported tree type.' unless NA_TREE_TYPES.key?(type)

            self.Na__VegetationSketcher__Options__Preset('tree')
                .merge(NA_TREE_TYPES[type]['settings'])
                .merge('tree_type' => type)
        end
        # ------------------------------------------------------------

        def self.Na__VegetationSketcher__Options__ShrubPreset(type)
            raise ArgumentError, 'Choose a supported shrub type.' unless NA_SHRUB_TYPES.key?(type)
            self.Na__VegetationSketcher__Options__Preset('shrub')
                .merge(NA_SHRUB_TYPES[type]['settings']).merge('shrub_type' => type)
        end

        def self.Na__VegetationSketcher__Options__ShrubTypeInfo
            NA_SHRUB_TYPES.transform_values { |data| data.reject { |key, _| key == 'settings' } }
        end

        # FUNCTION | Short Display Name For the Current Preset
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Options__Label(options)
            if options['preset'] == 'tree'
                NA_TREE_TYPES.fetch(options['tree_type'], NA_TREE_TYPES['generic'])['name']
            elsif options['preset'] == 'shrub'
                NA_SHRUB_TYPES.fetch(options['shrub_type'], NA_SHRUB_TYPES['generic'])['name']
            else
                options['preset'].capitalize
            end
        end
        # ------------------------------------------------------------

        # FUNCTION | Species Metadata Without Geometry Settings
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Options__TreeTypeInfo
            NA_TREE_TYPES.transform_values { |data| data.reject { |key, _| key == 'settings' } }
        end
        # ------------------------------------------------------------

        # FUNCTION | Normalise Raw Settings Into a Complete Millimetre Hash
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Options__Resolve(raw = {})
            raw = JSON.parse(raw) if raw.is_a?(String)
            raise ArgumentError, 'Settings must be an object.' unless raw.is_a?(Hash)

            raw = raw.transform_keys(&:to_s)
            kind = NA_PRESETS.key?(raw['preset']) ? raw['preset'] : 'hedge'
            type = kind == 'tree' && NA_TREE_TYPES.key?(raw['tree_type']) ? raw['tree_type'] : 'generic'
            result = kind == 'tree' ? self.Na__VegetationSketcher__Options__TreePreset(type) : self.Na__VegetationSketcher__Options__Preset(kind)
            if kind == 'shrub'
                shrub = NA_SHRUB_TYPES.key?(raw['shrub_type']) ? raw['shrub_type'] : 'generic'
                result = self.Na__VegetationSketcher__Options__ShrubPreset(shrub)
            end

            na_apply_numeric_limits(result, raw)
            na_apply_flags_and_path(result, raw, kind)
            result
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Clamp Posted Numeric Keys Against NA_LIMITS
        # ------------------------------------------------------------
        def self.na_apply_numeric_limits(result, raw)
            NA_LIMITS.each do |key, (low, high)|
                next unless raw.key?(key)

                value = Float(raw[key])
                raise ArgumentError, "Invalid #{key}." unless value.finite?

                result[key] = value.clamp(low, high)
            end

            result['seed'] = result['seed'].to_i
            resolution = raw.fetch('resolution', result['resolution']).to_i
            result['resolution'] = resolution if NA_RESOLUTIONS.include?(resolution)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply Booleans, Trunk Caps and an Optional Hedge Path
        # ------------------------------------------------------------
        def self.na_apply_flags_and_path(result, raw, kind)
            detail = raw.fetch('plant_detail', result['plant_detail'])
            result['plant_detail'] = %w[low medium high].include?(detail) ? detail : 'medium'
            %w[smooth vary].each { |key| result[key] = raw[key] == true if raw.key?(key) }
            result['trunk_height'] = [result['trunk_height'], result['height'] * 0.75].min
            result['trunk_diameter'] = [result['trunk_diameter'], result['width'] * 0.4, result['depth'] * 0.4].min
            if kind == 'hedge' && raw['path']
                result['path'] = Na__VegetationSketcher__HedgePath.Na__VegetationSketcher__HedgePath__Validate(raw['path'])
            end
            result['length'] = Na__VegetationSketcher__HedgePath.Na__VegetationSketcher__HedgePath__Length(result['path']) if result['path']
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__Options
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
