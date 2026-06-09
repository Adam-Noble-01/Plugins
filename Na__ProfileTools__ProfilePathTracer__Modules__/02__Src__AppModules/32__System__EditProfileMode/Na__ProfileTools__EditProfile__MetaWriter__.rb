# =============================================================================
# NA PROFILE TOOLS - EDIT PROFILE MODE - META WRITER
# =============================================================================
#
# FILE       : Na__ProfileTools__EditProfile__MetaWriter__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditProfile__MetaWriter
# PURPOSE    : In-place metadata save for profile JSON data files.
#              Writes a .bak copy of the previous version before overwriting.
#
# SAVE CONTRACT:
#   1. Validate the sourceFile is inside NA_PROFILE_DATA_DIR (path traversal guard).
#   2. Write <file>.bak alongside the original.
#   3. Patch Name, Description, Keywords in the JSON.
#   4. Write the updated JSON with the same pretty-print state as the exporter.
#   5. Return the freshly re-parsed profile record (so the store can update).
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__MetaWriter

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        # @delegate: ../../04__Data__ProfileLibrary/  (from 32__System__EditProfileMode)
        NA_PROFILE_DATA_DIR = File.expand_path(
            '../../04__Data__ProfileLibrary',
            File.dirname(__FILE__)
        ).freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__SaveMeta(params)
            profile_key  = params['profileKey'].to_s.strip
            source_file  = params['sourceFile'].to_s.strip
            new_name     = params['name'].to_s.strip
            new_desc     = params['description'].to_s
            new_keywords = Array(params['keywords'])

            return { 'isSaved' => false, 'reason' => 'Profile key is required.' } if profile_key.empty?
            return { 'isSaved' => false, 'reason' => 'Source file path is required.' } if source_file.empty?

            validation = self.Na__MetaWriter__ValidateSourcePath(source_file)
            return validation unless validation['isValid']

            self.Na__MetaWriter__WriteMeta(source_file, profile_key, new_name, new_desc, new_keywords)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__MetaWriter__SaveMeta failed.', error)
            { 'isSaved' => false, 'reason' => "MetaWriter failed: #{error.message}" }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Path Validation (traversal guard)
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__ValidateSourcePath(source_file)
            expanded_source = File.expand_path(source_file)
            expanded_data   = File.expand_path(NA_PROFILE_DATA_DIR)

            unless expanded_source.start_with?(expanded_data)
                return {
                    'isValid' => false,
                    'reason'  => "Source file is outside the permitted profile data directory."
                }
            end

            unless File.exist?(expanded_source)
                return { 'isValid' => false, 'reason' => "Source file not found: #{source_file}" }
            end

            unless expanded_source.end_with?('.json')
                return { 'isValid' => false, 'reason' => "Source file is not a .json file." }
            end

            { 'isValid' => true, 'expandedPath' => expanded_source }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write Meta
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__WriteMeta(source_file, profile_key, new_name, new_desc, new_keywords)
            expanded_path = File.expand_path(source_file)
            raw_content   = File.read(expanded_path, encoding: 'utf-8')
            data          = JSON.parse(raw_content)

            self.Na__MetaWriter__WriteBackup(expanded_path, raw_content)
            self.Na__MetaWriter__PatchData(data, new_name, new_desc, new_keywords)
            self.Na__MetaWriter__WriteFile(expanded_path, data)

            fresh_record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(expanded_path)
            unless fresh_record
                return {
                    'isSaved'    => false,
                    'reason'     => 'Saved OK but re-parse of updated file failed.',
                    'profileKey' => profile_key
                }
            end

            {
                'isSaved'       => true,
                'profileKey'    => profile_key,
                'profileRecord' => fresh_record,
                'statusMessage' => "Profile \"#{new_name.empty? ? profile_key : new_name}\" saved. Backup written as .bak.",
                'reason'        => nil
            }
        rescue JSON::ParserError => error
            { 'isSaved' => false, 'reason' => "JSON parse error: #{error.message}" }
        rescue => error
            { 'isSaved' => false, 'reason' => "Write failed: #{error.message}" }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Backup
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__WriteBackup(expanded_path, raw_content)
            bak_path = expanded_path + '.bak'
            File.open(bak_path, 'w:utf-8') { |file| file.write(raw_content) }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Backup write failed for #{expanded_path}: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | JSON Patch
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__PatchData(data, new_name, new_desc, new_keywords)
            meta       = data['meta']       ||= {}
            asset_meta = data['Na__Asset__Metadata'] ||= {}

            unless new_name.empty?
                asset_meta['Na__Asset__Name'] = new_name
                meta['Meta_ProfileName']      = new_name
            end

            asset_meta['Na__Asset__Description'] = new_desc
            meta['Meta_ProfileKeywords']          = new_keywords
            meta['lastUpdated']                   = Time.now.strftime('%d-%b-%Y')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | File Write (same pretty-print state as Exporter)
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__WriteFile(expanded_path, data)
            json_state = JSON::State.new(
                indent:     '  ',
                space:      '  ',
                space_before: '  ',
                object_nl:  "\n",
                array_nl:   "\n"
            )
            File.open(expanded_path, 'w:utf-8') { |file| file.write(JSON.generate(data, json_state)) }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
