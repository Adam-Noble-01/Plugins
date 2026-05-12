# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - PROFILE LIBRARY
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__ProfileLibrary__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__ProfileLibrary
# PURPOSE    : Load profiles from 04__Data__ProfileLibrary (recursive *.json)
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__ProfileLibrary

    # -------------------------------------------------------------------------
    # REGION | File Paths
    # -------------------------------------------------------------------------

        # @delegate: ../../04__Data__ProfileLibrary/
        NA_PROFILE_DATA_DIR = File.expand_path('../../04__Data__ProfileLibrary', File.dirname(__FILE__)).freeze

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
    # REGION | Data File Scanner
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

            unless self.Na__ProfileLibrary__ValidUnifiedSchema?(data)
                Na__DebugTools.Na__Debug__Warn("Rejected profile file (legacy or invalid schema): #{file_path}")
                return nil
            end

            meta = data['meta'] || {}
            asset_metadata = data['Na__Asset__Metadata'] || {}
            profile_block = data['Na__Asset__Profile2D'] || {}
            profile_vertices = Array(profile_block['Na__Geometry__Vertices'])
            profile_edges = Array(profile_block['Na__Geometry__Edges'])
            profile_faces = Array(profile_block['Na__Geometry__Faces'])

            if profile_vertices.empty? || profile_edges.empty? || profile_faces.empty?
                Na__DebugTools.Na__Debug__Warn("Rejected profile file (empty geometry arrays): #{file_path}")
                return nil
            end

            profile_key  = asset_metadata['Na__Asset__Code'].to_s
            profile_key  = meta['Meta_ProfileId'].to_s if profile_key.strip.empty?
            profile_key  = File.basename(file_path, '.json') if profile_key.strip.empty?

            display_name = asset_metadata['Na__Asset__Name'].to_s
            display_name = meta['Meta_ProfileName'].to_s if display_name.strip.empty?
            display_name = profile_key if display_name.strip.empty?

            keywords = Array(meta['Meta_ProfileKeywords'])
            keywords = Array(meta['Meta_Keywords']) if keywords.empty?
            category = asset_metadata['Na__Asset__Type'].to_s
            category = keywords.first.to_s if category.empty?
            category = 'User Profiles' if category.empty?

            {
                'profileKey'  => profile_key,
                'displayName' => display_name,
                'category'    => category,
                'isEnabled'   => true,
                'sourceFile'  => file_path,
                'profileData' => {
                    'type' => 'na_unified_asset',
                    'schemaContract' => 'meta + Na__Asset__Metadata + Na__Asset__Profile2D + Na__Asset__Mesh3D',
                    'assetData' => data,
                    'units' => 'mm'
                }
            }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Failed to parse profile data file: #{file_path} - #{error.message}")
            nil
        end

        def self.Na__ProfileLibrary__ValidUnifiedSchema?(data)
            return false unless data.is_a?(Hash)

            required_root_keys = ['meta', 'Na__Asset__Metadata', 'Na__Asset__Profile2D', 'Na__Asset__Mesh3D']
            return false unless required_root_keys.all? { |key| data.key?(key) }

            profile_block = data['Na__Asset__Profile2D']
            mesh_block = data['Na__Asset__Mesh3D']
            return false unless profile_block.is_a?(Hash)
            return false unless mesh_block.is_a?(Hash)

            vertices_ok = profile_block['Na__Geometry__Vertices'].is_a?(Array)
            edges_ok = profile_block['Na__Geometry__Edges'].is_a?(Array)
            faces_ok = profile_block['Na__Geometry__Faces'].is_a?(Array)
            mesh_edges_ok = mesh_block['Na__Geometry__Edges'].is_a?(Array)

            vertices_ok && edges_ok && faces_ok && mesh_edges_ok
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
