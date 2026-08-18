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
#   1. Validate the sourceFile through Na__EditProfile__LibraryPaths, the guard
#      shared with the geometry re-capture and delete paths.
#   2. Patch Name, Description, Keywords in the JSON.
#   3. Optionally mirror the geometry (params['flipHorizontal']) via
#      Na__EditProfile__GeometryWriter — folded into this same write so flipping
#      cannot silently discard whatever is currently typed into the form.
#   4. Write <file>.bak alongside the original — LAST, immediately before the
#      overwrite, so a path that bails out early cannot burn the rollback point.
#   5. Write the updated JSON with the same pretty-print state as the exporter.
#   6. Return the freshly re-parsed profile record (so the store can update).
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__MetaWriter

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__SaveMeta(params)
            profile_key  = params['profileKey'].to_s.strip
            source_file  = params['sourceFile'].to_s.strip
            new_name     = params['name'].to_s.strip
            new_desc     = params['description'].to_s
            new_keywords = Array(params['keywords'])
            flip_horizontal = params['flipHorizontal'] == true

            return { 'isSaved' => false, 'reason' => 'Profile key is required.' } if profile_key.empty?
            return { 'isSaved' => false, 'reason' => 'Source file path is required.' } if source_file.empty?

            validation = self.Na__MetaWriter__ValidateSourcePath(source_file)
            return validation unless validation['isValid']

            self.Na__MetaWriter__WriteMeta(
                source_file, profile_key, new_name, new_desc, new_keywords, flip_horizontal
            )
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__MetaWriter__SaveMeta failed.', error)
            { 'isSaved' => false, 'reason' => "MetaWriter failed: #{error.message}" }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Path Validation (traversal guard)
    # -------------------------------------------------------------------------

        # @delegate: Na__ProfileTools__EditProfile__LibraryPaths__
        def self.Na__MetaWriter__ValidateSourcePath(source_file)
            Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(source_file)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write Meta
    # -------------------------------------------------------------------------

        def self.Na__MetaWriter__WriteMeta(source_file, profile_key, new_name, new_desc, new_keywords, flip_horizontal = false)
            expanded_path = File.expand_path(source_file)
            raw_content   = File.read(expanded_path, encoding: 'utf-8')
            data          = JSON.parse(raw_content)

            self.Na__MetaWriter__PatchData(data, new_name, new_desc, new_keywords)

            # @delegate: Na__ProfileTools__EditProfile__GeometryWriter__
            is_flipped = false
            if flip_horizontal
                is_flipped = Na__EditProfile__GeometryWriter.Na__GeometryWriter__FlipHorizontal(data)
                unless is_flipped
                    return {
                        'isSaved'    => false,
                        'reason'     => 'Profile has no mirrorable geometry — nothing was written.',
                        'profileKey' => profile_key
                    }
                end
            end

            # Backup last, immediately before the overwrite. Writing it earlier
            # burns the user's only rollback point even on the paths that bail out
            # without changing the file.
            self.Na__MetaWriter__WriteBackup(expanded_path, raw_content)
            self.Na__MetaWriter__WriteFile(expanded_path, data)

            fresh_record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(expanded_path)
            unless fresh_record
                return {
                    'isSaved'    => false,
                    'reason'     => 'Saved OK but re-parse of updated file failed.',
                    'profileKey' => profile_key
                }
            end

            display_name = new_name.empty? ? profile_key : new_name
            status_message = if is_flipped
                                 "Profile \"#{display_name}\" flipped horizontally and saved. Backup written as .bak."
                             else
                                 "Profile \"#{display_name}\" saved. Backup written as .bak."
                             end

            {
                'isSaved'       => true,
                'isFlipped'     => is_flipped,
                'profileKey'    => profile_key,
                'profileRecord' => fresh_record,
                'statusMessage' => status_message,
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
