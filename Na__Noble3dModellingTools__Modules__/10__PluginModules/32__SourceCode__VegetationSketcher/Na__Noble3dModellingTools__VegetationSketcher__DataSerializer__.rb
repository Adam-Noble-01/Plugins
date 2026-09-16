# frozen_string_literal: true

require 'json'

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    # Assembly Studio pattern: portable configuration on the definition,
    # identity on the instance. The model also remembers its last-used settings.
    # Reads never write, so selecting, reopening and undo do not create operations.
    module DataSerializer
      VERSION = 2
      INSTANCE_DICT = 'Na__VegetationSketcher'.freeze
      DEFINITION_DICT = 'Na__VegetationSketcher__Definition'.freeze
      MODEL_DICT = 'Na__VegetationSketcher__Model'.freeze

      def self.container?(entity)
        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.valid?
      end

      def self.has_data?(entity)
        container?(entity) && !!(entity.definition.get_attribute(DEFINITION_DICT, 'data') || entity.get_attribute(INSTANCE_DICT, 'settings'))
      end

      def self.load(entity)
        raise ArgumentError, 'This selection is not Noble vegetation.' unless has_data?(entity)
        raw = entity.definition.get_attribute(DEFINITION_DICT, 'data')
        return Options.resolve(entity.get_attribute(INSTANCE_DICT, 'settings')) unless raw

        data = JSON.parse(raw)
        unless data.is_a?(Hash) && data['schema_version'] == VERSION && data['configuration'].is_a?(Hash)
          raise ArgumentError, 'This vegetation has an unsupported settings format.'
        end
        Options.resolve(data['configuration'])
      rescue JSON::ParserError
        raise ArgumentError, 'The selected vegetation contains damaged settings JSON.'
      end

      def self.save(model, entity, options, quad_count)
        previous = entity.definition.get_attribute(DEFINITION_DICT, 'data')
        previous = previous ? JSON.parse(previous) : {}
        metadata = previous.fetch('metadata', {})
        now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
        data = {
          'schema_version' => VERSION,
          'metadata' => { 'created_at' => metadata['created_at'] || now, 'updated_at' => now,
                          'preset' => options['preset'], 'tree_type' => options['tree_type'], 'quad_count' => quad_count },
          'configuration' => Options.resolve(options)
        }
        entity.definition.set_attribute(DEFINITION_DICT, 'data', JSON.generate(data))
        entity.set_attribute(INSTANCE_DICT, 'vegetation_id', "NVG-#{entity.persistent_id}")
        entity.set_attribute(INSTANCE_DICT, 'version', VERSION)
        # Retain v1 compatibility for existing Noble tooling that reads this key.
        entity.set_attribute(INSTANCE_DICT, 'settings', JSON.generate(data['configuration']))
        entity.set_attribute(INSTANCE_DICT, 'quad_count', quad_count)
        model.set_attribute(MODEL_DICT, 'schema_version', VERSION)
        model.set_attribute(MODEL_DICT, 'last_settings', JSON.generate(data['configuration']))
        data
      end

      def self.model_options(model, fallback)
        raw = model.get_attribute(MODEL_DICT, 'last_settings')
        data = raw || fallback
        data = JSON.parse(data) if data.is_a?(String)
        # One-time creation-default migration. Loading an existing entity still
        # respects that entity's saved shading choice.
        data = data.merge('smooth' => true) unless data.key?('shading_version')
        Options.resolve(data.merge('path' => nil))
      rescue StandardError
        Options.resolve
      end

      def self.entities(entity)
        entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
      end
    end
  end
end
