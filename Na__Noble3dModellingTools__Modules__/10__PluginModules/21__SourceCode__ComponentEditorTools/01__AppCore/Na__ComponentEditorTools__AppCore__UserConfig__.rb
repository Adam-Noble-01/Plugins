# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE USER CONFIG
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__UserConfig__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__UserConfig
# PURPOSE    : Read and write the user's persistent config JSON that survives
#              between SketchUp sessions. Seeded from the bundled default file
#              on first run; thereafter the user copy in 07__UserData is used.
# CREATED    : 2026
#
# @delegate: ../07__UserData/Na__ComponentEditorTools__UserConfig__.json
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__UserConfig

# -----------------------------------------------------------------------------
# REGION | Defaults
# -----------------------------------------------------------------------------

        NA_USER_CONFIG_DEFAULTS = {
            'components_library_path' => '',
            'blocked_folder_names'    => ['00__Archive'],
            'blocked_file_names'      => []
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Accessors
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LibraryPath
            self.Na__ComponentEditorTools__Get('components_library_path').to_s
        end

        def self.Na__ComponentEditorTools__BlockedFolders
            value = self.Na__ComponentEditorTools__Get('blocked_folder_names')
            value.is_a?(Array) ? value.map(&:to_s) : ['00__Archive']
        end

        def self.Na__ComponentEditorTools__BlockedFiles
            value = self.Na__ComponentEditorTools__Get('blocked_file_names')
            value.is_a?(Array) ? value.map(&:to_s) : []
        end

        def self.Na__ComponentEditorTools__SetLibraryPath(path_string)
            self.Na__ComponentEditorTools__Set('components_library_path', path_string.to_s.strip)
        end

        def self.Na__ComponentEditorTools__AddBlockedFolder(folder_name)
            blocked = self.Na__ComponentEditorTools__BlockedFolders
            clean_name = folder_name.to_s.strip
            return if clean_name.empty?
            return if blocked.include?(clean_name)

            blocked << clean_name
            self.Na__ComponentEditorTools__Set('blocked_folder_names', blocked)
        end

        def self.Na__ComponentEditorTools__RemoveBlockedFolder(folder_name)
            blocked = self.Na__ComponentEditorTools__BlockedFolders
            clean_name = folder_name.to_s.strip
            self.Na__ComponentEditorTools__Set('blocked_folder_names', blocked.reject { |name| name == clean_name })
        end

        def self.Na__ComponentEditorTools__AddBlockedFile(file_name)
            blocked = self.Na__ComponentEditorTools__BlockedFiles
            clean_name = file_name.to_s.strip
            return if clean_name.empty?
            return if blocked.include?(clean_name)

            blocked << clean_name
            self.Na__ComponentEditorTools__Set('blocked_file_names', blocked)
        end

        def self.Na__ComponentEditorTools__RemoveBlockedFile(file_name)
            blocked = self.Na__ComponentEditorTools__BlockedFiles
            clean_name = file_name.to_s.strip
            self.Na__ComponentEditorTools__Set('blocked_file_names', blocked.reject { |name| name == clean_name })
        end

        def self.Na__ComponentEditorTools__GetAll
            self.Na__ComponentEditorTools__LoadConfig
        end

        def self.Na__ComponentEditorTools__InvalidateCache
            @na_user_config_cache = nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read / Write Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Get(key_name)
            config = self.Na__ComponentEditorTools__LoadConfig
            config[key_name.to_s]
        end

        def self.Na__ComponentEditorTools__Set(key_name, value)
            config = self.Na__ComponentEditorTools__LoadConfig
            config[key_name.to_s] = value
            self.Na__ComponentEditorTools__SaveConfig(config)
            @na_user_config_cache = config
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JSON Load / Save
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LoadConfig
            return @na_user_config_cache if @na_user_config_cache

            config_path = Na__PathResolver.Na__ComponentEditorTools__UserConfigFilePath

            parsed_config = if File.exist?(config_path)
                                begin
                                    JSON.parse(File.read(config_path, encoding: 'UTF-8'))
                                rescue JSON::ParserError
                                    {}
                                end
                            else
                                {}
                            end

            merged_config = NA_USER_CONFIG_DEFAULTS.merge(parsed_config)

            unless File.exist?(config_path)
                self.Na__ComponentEditorTools__SaveConfig(merged_config)
            end

            @na_user_config_cache = merged_config
        end

        def self.Na__ComponentEditorTools__SaveConfig(config_hash)
            config_path = Na__PathResolver.Na__ComponentEditorTools__UserConfigFilePath
            FileUtils.mkdir_p(File.dirname(config_path))
            File.write(config_path, JSON.pretty_generate(config_hash), encoding: 'UTF-8')
        rescue => error
            puts "[Na__ComponentEditorTools] UserConfig save warning: #{error.class}: #{error.message}"
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
