# frozen_string_literal: true

require 'json'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__HedgePath__'

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    module Options
      RESOLUTIONS = [10, 25, 50, 100, 200, 300, 500].freeze
      COMMON = { 'resolution' => 100, 'seed' => 12345, 'smooth' => true, 'shading_version' => 1,
                 'vary' => true, 'length' => 3000, 'path' => nil, 'tree_type' => 'generic' }.freeze
      PRESETS = {
        'hedge' => { 'width' => 800, 'depth' => 800, 'height' => 1600,
                     'soften' => 45, 'random' => 55, 'trunk_height' => 700, 'trunk_diameter' => 160 },
        'tree' => { 'width' => 3200, 'depth' => 2800, 'height' => 5200,
                    'soften' => 95, 'random' => 180, 'trunk_height' => 1800, 'trunk_diameter' => 240 },
        'shrub' => { 'width' => 1200, 'depth' => 1000, 'height' => 900,
                     'soften' => 100, 'random' => 90, 'trunk_height' => 300, 'trunk_diameter' => 100 }
      }.freeze
      # Representative landscape specimens, in millimetres; not maximum sizes
      # or a growth/age prediction. See README for the botanical references.
      TREE_TYPES = {
        'generic' => { 'name' => 'Generic canopy', 'botanical' => '',
          'description' => 'An adjustable rounded whitecard canopy.', 'settings' => PRESETS['tree'] },
        'douglas_fir' => { 'name' => 'Douglas fir', 'botanical' => 'Pseudotsuga menziesii',
          'description' => 'Tiered conical crown. Landscape specimen: 18 m tall, 7 m spread. Forest trees can grow much larger.',
          'settings' => { 'width' => 7000, 'depth' => 7000, 'height' => 18000, 'trunk_height' => 900,
            'trunk_diameter' => 600, 'soften' => 75, 'random' => 160, 'resolution' => 200 } },
        'english_oak' => { 'name' => 'English oak', 'botanical' => 'Quercus robur',
          'description' => 'Broad, lobed crown with spreading limbs. Mature specimen: 20 m tall, 20 by 18 m spread.',
          'settings' => { 'width' => 20000, 'depth' => 18000, 'height' => 20000, 'trunk_height' => 3500,
            'trunk_diameter' => 1100, 'soften' => 85, 'random' => 350, 'resolution' => 300 } }
      }.freeze
      LIMITS = { 'width' => [50, 50000], 'depth' => [50, 50000], 'height' => [50, 100000],
                 'length' => [50, 100000], 'soften' => [0, 100], 'random' => [0, 500],
                 'trunk_height' => [25, 75000], 'trunk_diameter' => [20, 5000],
                 'seed' => [1, 2147483646] }.freeze

      def self.preset(kind)
        kind = 'hedge' unless PRESETS.key?(kind)
        COMMON.merge(PRESETS.fetch(kind, PRESETS['hedge'])).merge('preset' => kind)
      end

      def self.tree_preset(type)
        raise ArgumentError, 'Choose a supported tree type.' unless TREE_TYPES.key?(type)
        preset('tree').merge(TREE_TYPES[type]['settings']).merge('tree_type' => type)
      end

      def self.label(options)
        options['preset'] == 'tree' ? TREE_TYPES.fetch(options['tree_type'], TREE_TYPES['generic'])['name'] : options['preset'].capitalize
      end

      def self.tree_type_info
        TREE_TYPES.transform_values { |data| data.reject { |key, _| key == 'settings' } }
      end

      def self.resolve(raw = {})
        raw = JSON.parse(raw) if raw.is_a?(String)
        raise ArgumentError, 'Settings must be an object.' unless raw.is_a?(Hash)
        raw = raw.transform_keys(&:to_s)
        kind = PRESETS.key?(raw['preset']) ? raw['preset'] : 'hedge'
        type = kind == 'tree' && TREE_TYPES.key?(raw['tree_type']) ? raw['tree_type'] : 'generic'
        result = kind == 'tree' ? tree_preset(type) : preset(kind)
        LIMITS.each do |key, (low, high)|
          next unless raw.key?(key)
          value = Float(raw[key])
          raise ArgumentError, "Invalid #{key}." unless value.finite?
          result[key] = value.clamp(low, high)
        end
        result['seed'] = result['seed'].to_i
        resolution = raw.fetch('resolution', result['resolution']).to_i
        result['resolution'] = resolution if RESOLUTIONS.include?(resolution)
        %w[smooth vary].each { |key| result[key] = raw[key] == true if raw.key?(key) }
        result['trunk_height'] = [result['trunk_height'], result['height'] * 0.75].min
        result['trunk_diameter'] = [result['trunk_diameter'], result['width'] * 0.4, result['depth'] * 0.4].min
        result['path'] = HedgePath.validate(raw['path']) if kind == 'hedge' && raw['path']
        result['length'] = HedgePath.length(result['path']) if result['path']
        result
      end
    end
  end
end
