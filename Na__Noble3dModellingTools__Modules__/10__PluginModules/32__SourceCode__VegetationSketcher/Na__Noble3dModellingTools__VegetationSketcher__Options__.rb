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
            'tree_type'       => 'generic'
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

        # FUNCTION | Short Display Name For the Current Preset
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Options__Label(options)
            if options['preset'] == 'tree'
                NA_TREE_TYPES.fetch(options['tree_type'], NA_TREE_TYPES['generic'])['name']
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
