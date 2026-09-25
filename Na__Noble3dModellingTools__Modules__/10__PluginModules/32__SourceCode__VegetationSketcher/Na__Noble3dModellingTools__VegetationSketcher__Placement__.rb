# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - PLACEMENT VARIATION
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__Placement__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__Placement
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Random size, height stretch, turn and lean for each tree or
#              plant placed individually, matching the Scatter brush ranges
# CREATED    : 2026
#
# The roll becomes the instance transform, like Scatter, so the component
# definition keeps its exact base size and the dialog never drifts.
# Matrices are world: InputPoint positions are world in any open context.
# Order: translate * lean * turn * scale, so the base stays on the picked point.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__Placement

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DEFAULTS = {
            'enabled'    => true,
            'scale_min'  => 90.0,
            'scale_max'  => 110.0,
            'height_min' => 95.0,
            'height_max' => 105.0,
            'rotation'   => 360.0,
            'lean'       => 0.0
        }.freeze

        NA_LIMITS = {
            'scale_min'  => [10, 500],
            'scale_max'  => [10, 500],
            'height_min' => [25, 400],
            'height_max' => [25, 400],
            'rotation'   => [0, 360],
            'lean'       => [0, 30]
        }.freeze

        NA_LABELS = {
            'scale_min'  => 'Minimum size',
            'scale_max'  => 'Maximum size',
            'height_min' => 'Minimum height stretch',
            'height_max' => 'Maximum height stretch',
            'rotation'   => 'Random rotation',
            'lean'       => 'Maximum lean'
        }.freeze

        NA_IDENTITY_ROLL = { 'scale' => 1.0, 'height' => 1.0, 'yaw' => 0.0, 'lean' => 0.0, 'lean_dir' => 0.0 }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings
# -----------------------------------------------------------------------------

        # FUNCTION | Validate Posted Placement Ranges; Refuse, Never Clamp
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Placement__Resolve(raw = {})
            raw = JSON.parse(raw) if raw.is_a?(String)
            raise ArgumentError, 'Placement settings must be an object.' unless raw.is_a?(Hash)

            raw = raw.transform_keys(&:to_s)
            out = NA_DEFAULTS.dup
            NA_LIMITS.each do |key, (low, high)|
                next unless raw.key?(key)

                value = Float(raw[key]) rescue nil
                unless value && value.finite? && value.between?(low, high)
                    unit = %w[rotation lean].include?(key) ? ' degrees' : '%'
                    raise ArgumentError, "#{NA_LABELS[key]} must be #{low} to #{high}#{unit}."
                end
                out[key] = value
            end
            out['enabled'] = raw['enabled'] == true if raw.key?('enabled')
            raise ArgumentError, 'Minimum size is above maximum size. Lower the minimum or raise the maximum.' if out['scale_min'] > out['scale_max']
            raise ArgumentError, 'Minimum height stretch is above the maximum. Lower the minimum or raise the maximum.' if out['height_min'] > out['height_max']
            out
        end
        # ------------------------------------------------------------

        # FUNCTION | Read Stored Preferences; Damaged Data Falls Back to Defaults
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Placement__Load(json)
            self.Na__VegetationSketcher__Placement__Resolve(json.to_s.empty? ? {} : json)
        rescue StandardError
            NA_DEFAULTS.dup
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Roll and Transform
# -----------------------------------------------------------------------------

        # FUNCTION | Roll One Plant's Size, Stretch, Turn and Lean
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Placement__Roll(settings, random = Random.new)
            return NA_IDENTITY_ROLL.dup unless settings && settings['enabled']

            {
                'scale'    => na_between(random, settings['scale_min'], settings['scale_max']) / 100.0,
                'height'   => na_between(random, settings['height_min'], settings['height_max']) / 100.0,
                'yaw'      => random.rand * settings['rotation'] * Math::PI / 180.0,
                'lean'     => random.rand * settings['lean'] * Math::PI / 180.0,
                'lean_dir' => random.rand * 2.0 * Math::PI
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Column-Major 4x4 For Geom::Transformation.new
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Placement__Matrix(point, roll)
            size = roll['scale']
            cos_yaw, sin_yaw = Math.cos(roll['yaw']), Math.sin(roll['yaw'])
            axes = [
                [cos_yaw * size, sin_yaw * size, 0.0],
                [-sin_yaw * size, cos_yaw * size, 0.0],
                [0.0, 0.0, size * roll['height']]
            ]
            axis = [Math.cos(roll['lean_dir']), Math.sin(roll['lean_dir']), 0.0]
            axes = axes.map { |v| na_rotate(v, axis, roll['lean']) }
            axes.flat_map { |v| v + [0.0] } + point.to_a.map(&:to_f) + [1.0]
        end
        # ------------------------------------------------------------

        # FUNCTION | Short Summary of a Roll For Status Text
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__Placement__Describe(roll)
            text = format('%d%% size', (roll['scale'] * 100).round)
            text += format(', %d%% height', (roll['height'] * 100).round) unless (roll['height'] - 1.0).abs < 0.005
            text += format(', %d° turn', (roll['yaw'] * 180 / Math::PI).round) if roll['yaw'] > 0.001
            text += format(', %.1f° lean', roll['lean'] * 180 / Math::PI) if roll['lean'] > 0.001
            text
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Uniform Value Between Two Percentages
        # ------------------------------------------------------------
        def self.na_between(random, low, high)
            low + random.rand * (high - low)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rodrigues Rotation of a Vector About a Unit Axis
        # ------------------------------------------------------------
        def self.na_rotate(v, k, angle)
            return v if angle.abs < 1.0e-12

            cos_a, sin_a = Math.cos(angle), Math.sin(angle)
            dot = k[0] * v[0] + k[1] * v[1] + k[2] * v[2]
            cross = [k[1] * v[2] - k[2] * v[1], k[2] * v[0] - k[0] * v[2], k[0] * v[1] - k[1] * v[0]]
            3.times.map { |i| v[i] * cos_a + cross[i] * sin_a + k[i] * dot * (1 - cos_a) }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__Placement
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
