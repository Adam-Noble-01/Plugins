# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PROFILE LIBRARY
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__ProfileLibrary__.rb
# PURPOSE    : Load profiles from 01__ProfileDataFiles (recursive *.json)
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__ProfileLibrary

    # -------------------------------------------------------------------------
    # REGION | File Paths
    # -------------------------------------------------------------------------

        NA_PROFILE_DATA_DIR = File.join(File.dirname(__FILE__), '01__ProfileDataFiles').freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Load / Parse
    # -------------------------------------------------------------------------

        def self.Na__ProfileLibrary__Load
            scanned_profiles = self.Na__ProfileLibrary__ScanDataFiles
            { 'profiles' => scanned_profiles }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Profile library load failed: #{error.message}")
            {}
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Data File Scanner (01__ProfileDataFiles)
    # -------------------------------------------------------------------------

        def self.Na__ProfileLibrary__ScanDataFiles
            return [] unless File.directory?(NA_PROFILE_DATA_DIR)

            json_files = Dir.glob(File.join(NA_PROFILE_DATA_DIR, '**', '*.json'))
            profiles = []

            json_files.each do |file_path|
                profile = self.Na__ProfileLibrary__ParseDataFile(file_path)
                profiles << profile if profile
            end

            profiles
        end

        def self.Na__ProfileLibrary__ParseDataFile(file_path)
            content = File.read(file_path)
            data = JSON.parse(content)

            meta     = data['meta'] || {}
            vertices = data['vertices']
            edges    = data['edges']
            faces    = data['faces']

            return nil unless vertices && edges && faces

            profile_key  = meta['Meta_ProfileId'].to_s
            profile_key  = File.basename(file_path, '.json') if profile_key.strip.empty?
            display_name = meta['Meta_ProfileName'].to_s
            display_name = profile_key if display_name.strip.empty?

            keywords = Array(meta['Meta_Keywords'])
            category = keywords.first || 'User Profiles'

            {
                'profileKey'  => profile_key,
                'displayName' => display_name,
                'category'    => category,
                'isEnabled'   => true,
                'sourceFile'  => file_path,
                'profileData' => {
                    'type'     => 'rich_geometry',
                    'vertices' => vertices,
                    'edges'    => edges,
                    'faces'    => faces,
                    'units'    => 'mm'
                }
            }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Failed to parse profile data file: #{file_path} - #{error.message}")
            nil
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
