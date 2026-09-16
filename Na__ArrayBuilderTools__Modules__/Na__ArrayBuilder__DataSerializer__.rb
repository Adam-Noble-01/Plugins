# =============================================================================
# NA ARRAY BUILDER TOOLS - DATA SERIALIZER
# =============================================================================
# FILE       : Na__ArrayBuilder__DataSerializer__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Portable definition data, instance identity and model dictionary.
# =============================================================================

require 'json'
require 'securerandom'
require_relative 'Na__ArrayBuilder__Configuration__'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__DataSerializer

        NA_SCHEMA_VERSION  = 1
        NA_DEFINITION_DICT = 'Na__ArrayBuilder__Definition'.freeze
        NA_INSTANCE_DICT   = 'Na__ArrayBuilder__Instance'.freeze
        NA_MODEL_DICT      = 'Na__ArrayBuilder__Model'.freeze

        # FUNCTION | Recognise Assemblies Without Writing Attributes
        # ------------------------------------------------------------
        def self.Na__Data__HasData?(na_entity)
            na_entity && na_entity.valid? &&
                (na_entity.is_a?(Sketchup::ComponentInstance) || na_entity.is_a?(Sketchup::Group)) &&
                !na_entity.definition.get_attribute(NA_DEFINITION_DICT, 'data').nil?
        end

        # FUNCTION | Deserialize and Validate the Complete Recipe
        # ------------------------------------------------------------
        def self.Na__Data__Load(na_entity)
            raise ArgumentError, 'Select an editable Noble array.' unless Na__Data__HasData?(na_entity)
            Na__Data__Deserialize(na_entity.definition.get_attribute(NA_DEFINITION_DICT, 'data'))
        end

        def self.Na__Data__Deserialize(na_json)
            na_data = JSON.parse(na_json)
            unless na_data.is_a?(Hash) && na_data['schema_version'] == NA_SCHEMA_VERSION
                raise ArgumentError, 'Unsupported array data version.'
            end
            na_data['configuration'] = Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_data.fetch('configuration'))
            Na__Data__Points(na_data)
            raise ArgumentError, 'Missing array identity.' if na_data['array_id'].to_s.empty?
            na_data
        rescue JSON::ParserError, KeyError, TypeError
            raise ArgumentError, 'This array contains damaged saved data.'
        end

        # FUNCTION | Restore Definition-Local Path Coordinates (Millimetres)
        # ------------------------------------------------------------
        def self.Na__Data__Points(na_data)
            na_points = na_data['path_mm']
            unless na_points.is_a?(Array) && na_points.length.between?(2, 10_000) && na_points.all? { |na_point|
                na_point.is_a?(Array) && na_point.length == 3 && na_point.all? { |na_value| na_value.is_a?(Numeric) && na_value.finite? }
            }
                raise ArgumentError, 'The saved array path is invalid.'
            end
            na_points.map { |na_point| Geom::Point3d.new(na_point.map { |na_value| na_value.to_f.mm }) }
        end

        # FUNCTION | Save Inside the Geometry Operation (Undo Includes Data)
        # ------------------------------------------------------------
        def self.Na__Data__Save(na_model, na_entity, na_config, na_points, na_source, na_count, na_previous = nil)
            na_now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
            na_id = na_previous && na_previous['array_id']
            if na_previous && na_previous['definition_pid'] && na_previous['definition_pid'] != na_entity.definition.persistent_id
                na_id = nil
            end
            na_data = {
                'schema_version' => NA_SCHEMA_VERSION,
                'array_id' => na_id || SecureRandom.uuid,
                'definition_pid' => na_entity.definition.persistent_id,
                'created_at' => na_previous ? na_previous['created_at'] : na_now,
                'updated_at' => na_now,
                'configuration' => Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_config),
                'path_mm' => na_points.map { |na_point| na_point.to_a.map { |na_value| na_value.to_f * 25.4 } },
                'source' => Na__Data__SourceRecord(na_source), 'unit_count' => na_count
            }
            na_json = JSON.generate(na_data)
            na_entity.definition.set_attribute(NA_DEFINITION_DICT, 'data', na_json)
            na_entity.set_attribute(NA_INSTANCE_DICT, 'instance_id', "NAR-#{na_entity.persistent_id}")
            na_model.set_attribute(NA_MODEL_DICT, 'schema_version', NA_SCHEMA_VERSION)
            na_model.set_attribute(NA_MODEL_DICT, "array_#{na_data['array_id']}", na_json)
            na_model.set_attribute(NA_MODEL_DICT, 'last_settings', JSON.generate(na_data['configuration']))
            na_data
        end

        def self.Na__Data__SourceRecord(na_source)
            return nil unless na_source
            {
                'definition_pid' => na_source[:definition].persistent_id,
                'name' => na_source[:definition].name,
                'scale' => na_source[:scale]
            }
        end

        # FUNCTION | Resolve Embedded Geometry Before Model-Scoped Identifiers
        # ------------------------------------------------------------
        def self.Na__Data__RestoreSource(na_entity, na_data)
            return nil unless na_data['configuration']['type'] == 'object'
            na_record = na_data['source']
            raise ArgumentError, 'The saved source reference is missing.' unless na_record.is_a?(Hash)
            na_child = na_entity.definition.entities.find { |na_item|
                na_item.is_a?(Sketchup::ComponentInstance) &&
                    na_item.get_attribute(NA_INSTANCE_DICT, 'role') == 'unit'
            }
            raise ArgumentError, 'The source geometry is missing. Pick a replacement object.' unless na_child
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__SetDefinition(
                na_child.definition, na_record['name'], na_record['scale']
            )
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__GetPlacementInfo
        end

        def self.Na__Data__ModelSettings(na_model)
            Na__ArrayBuilder__Configuration.Na__Config__Resolve(na_model.get_attribute(NA_MODEL_DICT, 'last_settings', '{}'))
        rescue ArgumentError, JSON::ParserError
            Na__ArrayBuilder__Configuration.Na__Config__Resolve
        end

    end # module Na__ArrayBuilder__DataSerializer
end # module Na__ArrayBuilderTools
