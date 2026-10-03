# =============================================================================
# NA POINT CLOUD VIEWER - APP UTILS - UNIT CONTRACT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppUtils__UnitContract__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__UnitContract
# PURPOSE    : The single place where length units are named and converted.
#
# THE CONTRACT (see ARCHITECTURE.md, Units):
#   - SketchUp stores every length in INCHES. Anything handed to the SketchUp
#     API (Point3d, BoundingBox, Camera) is in inches.
#   - LAS coordinates are in the cloud's SOURCE UNIT (m, cm, mm, ft, in).
#     LAS rarely says which, so the user must choose it explicitly at import.
#     Nothing here guesses.
#   - Source -> inches is a DETERMINISTIC UNIT CONVERSION, one exact factor
#     per unit (1 in = 25.4 mm by definition). It is stored and applied
#     separately from the user's rigid move/rotate, and it is never exposed as
#     a free scale value.
#   - The model's DISPLAY unit (Model Info > Units) is shown to the user for
#     orientation only; it never changes how the cloud is converted.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__UnitContract

    # -------------------------------------------------------------------------
    # REGION | Unit Table (exact factors - inch is defined as 25.4 mm)
    # -------------------------------------------------------------------------

        NA_SOURCE_UNITS = {
            'm'  => { 'label' => 'Metres',      'inchesPerUnit' => 1000.0 / 25.4 },
            'cm' => { 'label' => 'Centimetres', 'inchesPerUnit' => 10.0 / 25.4   },
            'mm' => { 'label' => 'Millimetres', 'inchesPerUnit' => 1.0 / 25.4    },
            'ft' => { 'label' => 'Feet',        'inchesPerUnit' => 12.0          },
            'in' => { 'label' => 'Inches',      'inchesPerUnit' => 1.0           }
        }.freeze

        NA_INTERNAL_STORAGE_LABEL = 'Inches'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Source Units
    # -------------------------------------------------------------------------

        def self.Na__Units__IsSupportedSourceUnit?(unit_key)
            NA_SOURCE_UNITS.key?(unit_key.to_s)
        end

        # Raises on an unknown key: an unrecognised unit must stop the import,
        # not fall back to a default that silently rescales a survey.
        def self.Na__Units__InchesPerSourceUnit(unit_key)
            entry = NA_SOURCE_UNITS[unit_key.to_s]
            raise ArgumentError, "Unsupported point cloud source unit '#{unit_key}'." unless entry
            entry['inchesPerUnit']
        end

        def self.Na__Units__SourceUnitLabel(unit_key)
            entry = NA_SOURCE_UNITS[unit_key.to_s]
            entry ? entry['label'] : 'Not set'
        end

        def self.Na__Units__SourceUnitOptions
            NA_SOURCE_UNITS.map { |key, entry| { 'key' => key, 'label' => entry['label'] } }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | SketchUp Model Display Units
    # -------------------------------------------------------------------------

        def self.Na__Units__ModelUnitLabel(model)
            return 'No model' unless model
            unit = model.options['UnitsOptions']['LengthUnit']
            labels = {
                Length::Inches     => 'Inches',
                Length::Feet       => 'Feet',
                Length::Millimeter => 'Millimetres',
                Length::Centimeter => 'Centimetres',
                Length::Meter      => 'Metres'
            }
            labels[Length::Yard] = 'Yards' if defined?(Length::Yard)
            labels.fetch(unit, 'Unknown')
        rescue StandardError
            'Unknown'
        end

        # How lengths are SHOWN and TYPED in the dialog: the model's own display
        # unit (Model Info > Units). Display only; conversion of the cloud never
        # depends on it.
        NA_MODEL_DISPLAY_UNITS = {
            'in' => { 'suffix' => 'in', 'inchesPerUnit' => 1.0,          'decimals' => 2 },
            'ft' => { 'suffix' => 'ft', 'inchesPerUnit' => 12.0,         'decimals' => 3 },
            'mm' => { 'suffix' => 'mm', 'inchesPerUnit' => 1.0 / 25.4,   'decimals' => 0 },
            'cm' => { 'suffix' => 'cm', 'inchesPerUnit' => 10.0 / 25.4,  'decimals' => 1 },
            'm'  => { 'suffix' => 'm',  'inchesPerUnit' => 1000.0 / 25.4, 'decimals' => 3 },
            'yd' => { 'suffix' => 'yd', 'inchesPerUnit' => 36.0,         'decimals' => 3 }
        }.freeze

        def self.Na__Units__ModelDisplay(model)
            key = begin
                unit = model.options['UnitsOptions']['LengthUnit']
                map = { Length::Inches => 'in', Length::Feet => 'ft', Length::Millimeter => 'mm',
                        Length::Centimeter => 'cm', Length::Meter => 'm' }
                map[Length::Yard] = 'yd' if defined?(Length::Yard)
                map.fetch(unit, 'in')
            rescue StandardError
                'in'
            end
            NA_MODEL_DISPLAY_UNITS[key].merge('key' => key)
        end

        def self.Na__Units__InchesToDisplayText(inches, display)
            format("%.#{display['decimals']}f", inches.to_f / display['inchesPerUnit'])
        end

        # Two more decimals than the display unit, trailing zeros dropped:
        # 1234 mm stays "1234", a typed 1234.5 mm shows as "1234.5".
        def self.Na__Units__InchesToPreciseText(inches, display)
            self.Na__Units__TrimNumber(inches.to_f / display['inchesPerUnit'], display['decimals'] + 2)
        end

        def self.Na__Units__TrimNumber(value, decimals)
            text = format("%.#{decimals}f", value.to_f)
            text = text.sub(/0+\z/, '').sub(/\.\z/, '') if text.include?('.')
            text == '-0' ? '0' : text
        end

        # A bare number is in the model's display unit; anything else ("3.5m",
        # "12'") goes through SketchUp's own length parser. Raises ArgumentError
        # with a plain message when the text is not a length.
        def self.Na__Units__ParseDisplayLength(text, display)
            clean = text.to_s.strip
            raise ArgumentError, 'Enter a length.' if clean.empty?
            return Float(clean) * display['inchesPerUnit'] if clean.match?(/\A-?\d+(\.\d+)?\z/)
            clean.to_l.to_f
        rescue ArgumentError
            raise ArgumentError, "\"#{clean}\" is not a length SketchUp understands."
        end

        # The three-line unit summary every tab shows.
        def self.Na__Units__SummaryPayload(model, source_unit_key)
            factor = self.Na__Units__IsSupportedSourceUnit?(source_unit_key) ? self.Na__Units__InchesPerSourceUnit(source_unit_key) : nil
            {
                'modelUnits'          => self.Na__Units__ModelUnitLabel(model),
                'sourceUnits'         => self.Na__Units__SourceUnitLabel(source_unit_key),
                'sourceUnitKey'       => source_unit_key.to_s,
                'internalStorage'     => NA_INTERNAL_STORAGE_LABEL,
                'sourceToInchesFactor'=> factor
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
