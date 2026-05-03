# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - APPCONFIG LOADER (Ruby)
# =============================================================================
#
# FILE        : Na__AssemblyStudio__AppData__ConfigLoader__.rb
# AUTHOR      : Noble Architecture
# PURPOSE     : Single source of truth loader for the application config JSON.
# DEPENDENCIES: json (stdlib)
# CONSUMERS   : Every system reads constants/flags via Na__ConfigLoader.na_get(...)
#
# =============================================================================

require 'json'

module Na__AssemblyStudio
    module Na__AppData
        module Na__ConfigLoader

            NA_CONFIG_FILE_NAME = 'Na__AssemblyStudio__AppConfig__Main.json'.freeze

            @na_config_cache = nil

            def self.na_config_path
                File.join(__dir__, NA_CONFIG_FILE_NAME)
            end

            def self.na_load
                return @na_config_cache if @na_config_cache
                path = na_config_path
                raise "Element Assembly Studio Pro: AppConfig not found at #{path}" unless File.exist?(path)
                json_text = File.read(path, encoding: 'UTF-8')
                parsed    = JSON.parse(json_text)
                @na_config_cache = parsed['appConfig'] || parsed
                @na_config_cache
            end

            def self.na_reload
                @na_config_cache = nil
                na_load
            end

            def self.na_get(*key_path)
                node = na_load
                key_path.each do |key|
                    return nil unless node.is_a?(Hash)
                    node = node[key.to_s]
                end
                node
            end

            def self.na_get_or(default_value, *key_path)
                value = na_get(*key_path)
                value.nil? ? default_value : value
            end

        end
    end
end
