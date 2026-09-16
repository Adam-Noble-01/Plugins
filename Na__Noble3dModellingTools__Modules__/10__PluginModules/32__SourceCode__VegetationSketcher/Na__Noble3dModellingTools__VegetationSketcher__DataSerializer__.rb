# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__DataSerializer__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__DataSerializer
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Portable vegetation configuration on the definition, identity
#              on the instance, and last-used settings on the model
# CREATED    : 2026
#
# Reads never write, so selecting, reopening and undo do not create operations.
# Dictionary names stay Na__VegetationSketcher* so existing models still load.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__DataSerializer

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_SCHEMA_VERSION     = 2
        NA_INSTANCE_DICT      = 'Na__VegetationSketcher'.freeze
        NA_DEFINITION_DICT    = 'Na__VegetationSketcher__Definition'.freeze
        NA_MODEL_DICT         = 'Na__VegetationSketcher__Model'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Serializer API
# -----------------------------------------------------------------------------

        # FUNCTION | True For a Live Group or Component Instance
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__DataSerializer__Container?(entity)
            (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.valid?
        end
        # ------------------------------------------------------------

        # FUNCTION | True When the Entity Carries Vegetation Settings
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__DataSerializer__HasData?(entity)
            self.Na__VegetationSketcher__DataSerializer__Container?(entity) &&
                !!(entity.definition.get_attribute(NA_DEFINITION_DICT, 'data') || entity.get_attribute(NA_INSTANCE_DICT, 'settings'))
        end
        # ------------------------------------------------------------

        # FUNCTION | Resolve Saved Settings From Definition or Legacy Instance
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__DataSerializer__Load(entity)
            raise ArgumentError, 'This selection is not Noble vegetation.' unless self.Na__VegetationSketcher__DataSerializer__HasData?(entity)

            raw = entity.definition.get_attribute(NA_DEFINITION_DICT, 'data')
            return Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(entity.get_attribute(NA_INSTANCE_DICT, 'settings')) unless raw

            data = JSON.parse(raw)
            unless data.is_a?(Hash) && data['schema_version'] == NA_SCHEMA_VERSION && data['configuration'].is_a?(Hash)
                raise ArgumentError, 'This vegetation has an unsupported settings format.'
            end

            Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(data['configuration'])
        rescue JSON::ParserError
            raise ArgumentError, 'The selected vegetation contains damaged settings JSON.'
        end
        # ------------------------------------------------------------

        # FUNCTION | Write Definition, Instance and Model Settings
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__DataSerializer__Save(model, entity, options, quad_count)
            data = na_build_payload(entity, options, quad_count)
            entity.definition.set_attribute(NA_DEFINITION_DICT, 'data', JSON.generate(data))
            entity.set_attribute(NA_INSTANCE_DICT, 'vegetation_id', "NVG-#{entity.persistent_id}")
            entity.set_attribute(NA_INSTANCE_DICT, 'version', NA_SCHEMA_VERSION)
            entity.set_attribute(NA_INSTANCE_DICT, 'settings', JSON.generate(data['configuration']))
            entity.set_attribute(NA_INSTANCE_DICT, 'quad_count', quad_count)
            model.set_attribute(NA_MODEL_DICT, 'schema_version', NA_SCHEMA_VERSION)
            model.set_attribute(NA_MODEL_DICT, 'last_settings', JSON.generate(data['configuration']))
            data
        end
        # ------------------------------------------------------------

        # FUNCTION | Last Creation Settings For the Active Model
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__DataSerializer__ModelOptions(model, fallback)
            raw = model.get_attribute(NA_MODEL_DICT, 'last_settings')
            data = raw || fallback
            data = JSON.parse(data) if data.is_a?(String)
            data = data.merge('smooth' => true) unless data.key?('shading_version')
            Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(data.merge('path' => nil))
        rescue StandardError
            Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve
        end
        # ------------------------------------------------------------

        # FUNCTION | Entities Collection For a Group or Component Instance
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__DataSerializer__Entities(entity)
            entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Schema Payload, Reusing Created-At When Present
        # ------------------------------------------------------------
        def self.na_build_payload(entity, options, quad_count)
            previous = entity.definition.get_attribute(NA_DEFINITION_DICT, 'data')
            previous = previous ? JSON.parse(previous) : {}
            metadata = previous.fetch('metadata', {})
            now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
            {
                'schema_version' => NA_SCHEMA_VERSION,
                'metadata'       => {
                    'created_at' => metadata['created_at'] || now,
                    'updated_at' => now,
                    'preset'     => options['preset'],
                    'tree_type'  => options['tree_type'],
                    'quad_count' => quad_count
                },
                'configuration'  => Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(options)
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__DataSerializer
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
