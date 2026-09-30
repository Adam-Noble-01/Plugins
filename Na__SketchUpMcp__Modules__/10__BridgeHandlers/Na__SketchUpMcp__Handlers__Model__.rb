# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MODEL
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Model__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Model
# PURPOSE    : model_info, model_settings, model_purge
# CREATED    : 2026
#
# UNITS OPTIONS ARE PROBED, NOT ASSUMED:
# The stubs document only some UnitsOptions keys (AreaUnit, VolumeUnit,
# AreaPrecision, VolumePrecision). Every key is therefore read from the live
# OptionsProvider#keys and a write to a key SketchUp does not have is refused
# with the real key list, never guessed.
#
# @delegate: Na__SketchUpMcp__Handlers__ModelFile__.rb (save, open, new, import, export)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Model

# -----------------------------------------------------------------------------
# REGION | Constants (Length constant names by option)
# -----------------------------------------------------------------------------

        NA_LENGTH_UNIT_NAMES = {
            'in' => 'Inches', 'ft' => 'Feet', 'mm' => 'Millimeter', 'cm' => 'Centimeter', 'm' => 'Meter', 'yd' => 'Yard'
        }.freeze
        NA_LENGTH_FORMAT_NAMES = {
            'decimal' => 'Decimal', 'architectural' => 'Architectural', 'engineering' => 'Engineering', 'fractional' => 'Fractional'
        }.freeze
        NA_AREA_UNIT_NAMES = {
            'in2' => 'SquareInches', 'ft2' => 'SquareFeet', 'mm2' => 'SquareMillimeter', 'cm2' => 'SquareCentimeter',
            'm2' => 'SquareMeter', 'yd2' => 'SquareYard'
        }.freeze
        NA_VOLUME_UNIT_NAMES = {
            'in3' => 'CubicInches', 'ft3' => 'CubicFeet', 'mm3' => 'CubicMillimeter', 'cm3' => 'CubicCentimeter',
            'm3' => 'CubicMeter', 'yd3' => 'CubicYard', 'l' => 'Liter', 'us_gallon' => 'USGallon'
        }.freeze
        NA_PURGE_TARGETS = %w[components materials tags styles environments].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | model_info
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Model__Info(params, ctx)
            model = ctx[:model]
            info = {
                'title'            => model.title.to_s,
                'path'             => model.path.to_s,
                'description'      => model.description.to_s,
                'guid'             => model.guid.to_s,
                'modified'         => model.modified?,
                'sketchup_version' => Sketchup.version.to_s,
                'reporting_units'  => ctx[:unit],
                'units_options'    => na_units_options(model),
                'bounds'           => na_model_bounds(model, ctx),
                'counts'           => na_counts(model),
                'active_context'   => Na__Coordinates.Na__Coordinates__ActivePath(model).map { |instance| Na__Serializer.Na__Serializer__InstanceLabel(instance) },
                'active_tag'       => Na__EntityResolver.Na__EntityResolver__TagDisplayName(model.active_layer),
                'active_scene'     => model.pages.selected_page ? model.pages.selected_page.name : nil,
                'active_style'     => model.styles.selected_style ? model.styles.selected_style.name : nil,
                'location'         => na_location(model)
            }
            info['file_size_bytes'] = File.size(model.path) if !model.path.to_s.empty? && File.exist?(model.path)
            info['statistics'] = na_statistics(model, params) if Na__Params.Na__Params__Boolean(params, 'include_statistics', false)
            info
        end

        def self.na_units_options(model)
            provider = model.options['UnitsOptions']
            options = {}
            provider.keys.each { |key| options[key] = Na__Serializer.Na__Serializer__JsonSafe(provider[key]) }
            options['LengthUnit_name'] = na_constant_label(provider['LengthUnit'], NA_LENGTH_UNIT_NAMES)
            options['LengthFormat_name'] = na_constant_label(provider['LengthFormat'], NA_LENGTH_FORMAT_NAMES)
            options['AreaUnit_name'] = na_constant_label(provider['AreaUnit'], NA_AREA_UNIT_NAMES) if provider.key?('AreaUnit')
            options['VolumeUnit_name'] = na_constant_label(provider['VolumeUnit'], NA_VOLUME_UNIT_NAMES) if provider.key?('VolumeUnit')
            options
        end

        def self.na_constant_label(value, names)
            names.each do |label, constant_name|
                return label if Length.const_defined?(constant_name) && Length.const_get(constant_name) == value
            end
            nil
        end

        def self.na_model_bounds(model, ctx)
            corners = Na__Coordinates.Na__Coordinates__WorldBoundsArrays(model.bounds, Na__Coordinates.Na__Coordinates__Identity)
            return nil unless corners

            {
                'min'  => corners[0].map { |value| Na__Units.Na__Units__FromInches(value, ctx[:unit]) },
                'max'  => corners[1].map { |value| Na__Units.Na__Units__FromInches(value, ctx[:unit]) },
                'size' => [0, 1, 2].map { |axis| Na__Units.Na__Units__FromInches(corners[1][axis] - corners[0][axis], ctx[:unit]) }
            }
        end

        def self.na_counts(model)
            root_types = Hash.new(0)
            model.entities.each { |entity| root_types[Na__EntityResolver.Na__EntityResolver__TypeName(entity)] += 1 }
            definitions = model.definitions.to_a
            counts = {
                'root_entities'          => root_types,
                'faces_total'            => model.number_faces,
                'component_definitions'  => definitions.count { |definition| !definition.group? && !definition.image? },
                'group_definitions'      => definitions.count(&:group?),
                'materials'              => model.materials.length,
                'tags'                   => model.layers.length,
                'scenes'                 => model.pages.size,
                'styles'                 => model.styles.size
            }
            counts['tag_folders'] = model.layers.folders.length if model.layers.respond_to?(:folders)
            counts
        end

        def self.na_location(model)
            shadow_info = model.shadow_info
            location = { 'georeferenced' => model.georeferenced? }
            %w[City Country Latitude Longitude NorthAngle].each { |key| location[key] = Na__Serializer.Na__Serializer__JsonSafe(shadow_info[key]) }
            location
        end

        def self.na_statistics(model, params)
            budget = Na__Traversal.Na__Traversal__NewBudget
            max_depth = Na__Params.Na__Params__Integer(params, 'max_depth', 32, min: 0, max: 64)
            by_type = Hash.new(0)
            deepest = 0
            Na__Traversal.Na__Traversal__Walk(model.entities, [], max_depth, budget) do |entity, _path, depth|
                by_type[Na__EntityResolver.Na__EntityResolver__TypeName(entity)] += 1
                deepest = depth if depth > deepest
            end
            { 'entities_by_type_including_nested_copies' => by_type, 'max_nesting_depth' => deepest,
              'visited' => budget[:visited], 'truncated' => budget[:truncated] }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | model_settings
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Model__Settings(params, ctx)
            model = ctx[:model]
            provider = model.options['UnitsOptions']
            changed = {}

            na_set_length_constant(provider, 'LengthUnit', params['length_unit'], NA_LENGTH_UNIT_NAMES, changed)
            na_set_length_constant(provider, 'LengthFormat', params['length_format'], NA_LENGTH_FORMAT_NAMES, changed)
            na_set_length_constant(provider, 'AreaUnit', params['area_unit'], NA_AREA_UNIT_NAMES, changed)
            na_set_length_constant(provider, 'VolumeUnit', params['volume_unit'], NA_VOLUME_UNIT_NAMES, changed)
            if Na__Params.Na__Params__Has(params, 'length_precision')
                na_set_option(provider, 'LengthPrecision', Na__Params.Na__Params__Integer(params, 'length_precision', nil, min: 0, max: 6), changed)
            end
            (Na__Params.Na__Params__Hash(params, 'units_options', {}) || {}).each { |key, value| na_set_option(provider, key, value, changed) }

            if Na__Params.Na__Params__Has(params, 'description')
                model.description = Na__Params.Na__Params__String(params, 'description', '', allow_empty: true)
                changed['description'] = model.description
            end
            na_set_location(model, Na__Params.Na__Params__Hash(params, 'location', nil), changed)

            if changed.empty?
                raise Na__McpError.new('invalid_params', 'Nothing to change.',
                                       'Pass at least one of length_unit, length_format, length_precision, area_unit, volume_unit, units_options, description, location.')
            end
            { 'changed' => changed, 'units_options' => na_units_options(model) }
        end

        def self.na_set_length_constant(provider, key, value, names, changed)
            return if value.nil?

            constant_name = names[value.to_s]
            unless constant_name && Length.const_defined?(constant_name)
                raise Na__McpError.new('invalid_params', "#{key} '#{value}' is not recognised.", "Use one of: #{names.keys.join(', ')}.")
            end

            na_set_option(provider, key, Length.const_get(constant_name), changed)
            changed[key] = value
        end

        def self.na_set_option(provider, key, value, changed)
            unless provider.key?(key.to_s)
                raise Na__McpError.new('invalid_params', "This SketchUp has no UnitsOptions key '#{key}'.",
                                       "Available keys: #{provider.keys.join(', ')}.")
            end

            provider[key.to_s] = value
            changed[key.to_s] = Na__Serializer.Na__Serializer__JsonSafe(provider[key.to_s])
        end

        def self.na_set_location(model, location, changed)
            return if location.nil?

            key_map = { 'latitude' => 'Latitude', 'longitude' => 'Longitude', 'city' => 'City', 'country' => 'Country', 'north_angle' => 'NorthAngle' }
            shadow_info = model.shadow_info
            location.each do |key, value|
                shadow_key = key_map[key.to_s]
                unless shadow_key
                    raise Na__McpError.new('invalid_params', "location.#{key} is not a location field.", "Use: #{key_map.keys.join(', ')}.")
                end

                begin
                    shadow_info[shadow_key] = shadow_key.match?(/Latitude|Longitude|NorthAngle/) ? value.to_f : value.to_s
                rescue KeyError, TypeError => error
                    raise Na__McpError.new('invalid_params', "SketchUp refused location.#{key}: #{error.message}", nil)
                end
                changed["location.#{key}"] = Na__Serializer.Na__Serializer__JsonSafe(shadow_info[shadow_key])
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | model_purge
# -----------------------------------------------------------------------------

        # Order matters: components first frees the materials and tags they held.
        def self.Na__Handlers__Model__Purge(params, ctx)
            model = ctx[:model]
            targets = Na__Params.Na__Params__Array(params, 'what', NA_PURGE_TARGETS)
            unknown = targets - NA_PURGE_TARGETS
            unless unknown.empty?
                raise Na__McpError.new('invalid_params', "Unknown purge target(s): #{unknown.join(', ')}.", "Use any of: #{NA_PURGE_TARGETS.join(', ')}.")
            end

            removed = {}
            NA_PURGE_TARGETS.each do |target|
                next unless targets.include?(target)

                collection = na_purge_collection(model, target)
                next unless collection

                before = collection.to_a.length
                collection.purge_unused
                removed[target] = before - collection.to_a.length
            end
            { 'removed' => removed, 'summary' => "Purged #{removed.values.sum} unused item(s)." }
        end

        def self.na_purge_collection(model, target)
            case target
            when 'components' then model.definitions
            when 'materials' then model.materials
            when 'tags' then model.layers
            when 'styles' then model.styles
            when 'environments' then model.respond_to?(:environments) ? model.environments : nil
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Model
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
