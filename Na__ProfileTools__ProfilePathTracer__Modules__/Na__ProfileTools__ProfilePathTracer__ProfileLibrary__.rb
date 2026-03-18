# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PROFILE LIBRARY
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__ProfileLibrary__.rb
# PURPOSE    : Read profile library metadata/configuration
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__ProfileLibrary

    # -------------------------------------------------------------------------
    # REGION | File Paths
    # -------------------------------------------------------------------------

        NA_PROFILE_LIBRARY_FILENAME = 'Na__ProfileTools__ProfilePathTracer__ProfileLibrary__.json'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | File IO
    # -------------------------------------------------------------------------

        def self.Na__ProfileLibrary__FilePath
            File.join(File.dirname(__FILE__), NA_PROFILE_LIBRARY_FILENAME)
        end

        def self.Na__ProfileLibrary__ReadFileContents
            file_path = self.Na__ProfileLibrary__FilePath
            return nil unless File.exist?(file_path)

            File.read(file_path)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Load / Parse
    # -------------------------------------------------------------------------

        def self.Na__ProfileLibrary__Load
            json_content = self.Na__ProfileLibrary__ReadFileContents
            return {} unless json_content

            JSON.parse(json_content)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Profile library load failed: #{error.message}")
            {}
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Query Helpers
    # -------------------------------------------------------------------------

        def self.Na__ProfileLibrary__FindByKey(profile_key)
            data = self.Na__ProfileLibrary__Load
            profiles = data.fetch('profiles', [])
            profiles.find { |item| item['profileKey'] == profile_key }
        end

        def self.Na__ProfileLibrary__EnabledProfiles
            data = self.Na__ProfileLibrary__Load
            profiles = data.fetch('profiles', [])
            profiles.select { |profile| profile.fetch('isEnabled', true) }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | UI Payload Builders
    # -------------------------------------------------------------------------

        def self.Na__ProfileLibrary__UiProfileOptions
            self.Na__ProfileLibrary__EnabledProfiles.map do |profile|
                {
                    'profileKey'  => profile['profileKey'],
                    'displayName' => profile['displayName'] || profile['profileKey'],
                    'category'    => profile['category']
                }
            end
        end

        def self.Na__ProfileLibrary__ProfilesByKey
            profile_hash = {}
            self.Na__ProfileLibrary__EnabledProfiles.each do |profile|
                profile_hash[profile['profileKey']] = profile
            end
            profile_hash
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Defaults
    # -------------------------------------------------------------------------

        def self.Na__ProfileLibrary__DefaultProfileKey
            first_profile = self.Na__ProfileLibrary__EnabledProfiles.first
            first_profile ? first_profile['profileKey'] : nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
