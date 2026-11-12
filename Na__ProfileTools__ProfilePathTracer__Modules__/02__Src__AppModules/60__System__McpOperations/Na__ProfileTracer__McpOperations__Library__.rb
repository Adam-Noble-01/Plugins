# =============================================================================
# NA PROFILE TOOLS - MCP OPERATIONS - LIBRARY (THE PROFILE FILES)
# =============================================================================
#
# FILE       : Na__ProfileTracer__McpOperations__Library__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__McpOperations
# AUTHOR     : Noble Architecture
# PURPOSE    : profile_tracer_library: new profiles and changes to existing
#              ones in 04__Data__ProfileLibrary, through the plugin's own
#              writers. Never the model.
# CREATED    : 11-Nov-2026 (v1.6.17)
#
# ADAM'S RULE (11-Nov-2026): "I will ask you to save any profiles on a case by
# case basis to the library if we have to add new ones." An agent saves,
# overwrites or deletes a library profile only when Adam has asked for that
# profile. Everything else stays local to its trace.
#
# WHAT EACH ACTION REUSES:
#   save_new     an outline or a face: the Draw Profile writer's SaveNew (its
#                code, file-name and collision rules). A whole asset (a trace's
#                local profile, a reshaped library profile, a JSON profile):
#                the same rules, the exporter's own meta blocks, the asset's
#                geometry blocks as they are
#   overwrite    confirm = the key; geometry blocks merged over the old ones as
#                the Draw Profile writer's SaveOverwrite does, .bak written last
#   set_meta     Edit Profile's MetaWriter (name, short name, description,
#                keywords; .bak)
#   rename_file  Edit Profile's FileRenamer (stale and collision checks)
#   redatum      Edit Profile's Re-datum (MetaWriter + DatumWriter; .bak)
#   flip         Edit Profile's Flip Profile (MetaWriter + GeometryWriter; .bak)
#   delete       confirm = the key. By default the file is set aside, renamed
#                <file>.json.deleted__<date-time> beside it, so it leaves the
#                library but stays on disk; permanent: true deletes it through
#                Edit Profile's ProfileDeleter
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | save_new / overwrite
# -----------------------------------------------------------------------------

        def self.na_library_save_new(params)
            name = self.na_text(params, 'name', '').strip
            self.na_refuse('invalid_params', 'save_new needs name (the profile\'s display name).', 'Agree the name with Adam first.') if name.empty?
            source = self.na_library_source(params)
            meta = {
                'Meta_ProfileName'      => name,
                'Meta_ProfileId'        => self.na_text(params, 'code', '').strip,
                'Meta_ProfileShortName' => self.na_text(params, 'short_name', '').strip,
                'Meta_Description'      => self.na_text(params, 'description', ''),
                'Meta_Keywords'         => Array(params['keywords']).map(&:to_s).map(&:strip).reject(&:empty?)
            }

            # The plugin's code cleaner trims leading and trailing underscores,
            # so "<key>__" would slip past an exact-key check and land beside the
            # profile it copies: any key that cleans to the same code counts.
            wanted = Na__DrawProfile__ProfileWriter.Na__ProfileWriter__CleanCode(meta['Meta_ProfileId'].to_s.empty? ? name : meta['Meta_ProfileId'])
            clash  = self.na_code_clash(wanted)
            if clash
                self.na_refuse('invalid_params', "The library already holds \"#{clash}\", which the code \"#{wanted}\" would duplicate.",
                               "Choose another code, or overwrite that profile (only on Adam's say-so).")
            end

            result = if source[:payload] && !source[:edits]
                         Na__DrawProfile__ProfileWriter.Na__ProfileWriter__SaveNew(
                             'geometry' => source[:payload], 'meta' => meta, 'baseProfileKey' => self.na_text(params, 'base_profile_key', '')
                         )
                     else
                         self.na_write_new_asset(source[:asset], meta)
                     end
            self.na_refuse('operation_failed', result['reason'].to_s, 'Nothing was written.') unless result['isSaved']
            self.na_saved(result, 'saved as a new library profile', source)
        end

        def self.na_library_overwrite(params)
            key = self.na_text(params, 'profile_key', '').strip
            self.na_refuse('invalid_params', 'overwrite needs profile_key (the library profile to save over).', nil) if key.empty?
            self.na_require_confirm(params, key, 'overwrite')
            record = self.na_source_from_library(key)[:record]
            # The source is anything but the target itself, unless only a
            # profile_edit is given: then the target is reshaped in place.
            params = params.reject { |param_key, _| param_key == 'profile_key' }
            given  = (NA_SOURCE_KEYS + ['from_trace']).any? { |source_key| self.na_has?(params, source_key) }
            params = params.merge('profile_key' => key) if !given && params['profile_edit'].is_a?(Hash)
            source = self.na_library_source(params)

            path_check = Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(record['sourceFile'])
            self.na_refuse('operation_failed', path_check['reason'].to_s, nil) unless path_check['isValid']
            path = path_check['expandedPath']
            raw  = File.read(path, encoding: 'utf-8')
            data = JSON.parse(raw)
            %w[Na__Asset__Profile2D Na__Asset__Mesh3D].each do |block|
                fresh = source[:asset][block]
                next unless fresh.is_a?(Hash)
                data[block] = data[block].is_a?(Hash) ? data[block].merge(fresh) : fresh
            end
            if source[:asset].key?('Na__Asset__Annotations2D')
                data['Na__Asset__Annotations2D'] = source[:asset]['Na__Asset__Annotations2D']
            else
                data.delete('Na__Asset__Annotations2D')
            end
            (data['meta'] ||= {})['lastUpdated'] = Time.now.strftime('%d-%b-%Y')
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteBackup(path, raw)
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteFile(path, data)
            fresh_record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(path)
            self.na_refuse('operation_failed', 'The file was written but did not read back as a profile.', "Restore #{File.basename(path)}.bak beside it.") unless fresh_record
            self.na_saved({ 'isSaved' => true, 'profileKey' => key, 'filePath' => path, 'profileRecord' => fresh_record },
                          'saved over the library profile (the old file kept as .bak)', source)
        rescue JSON::ParserError => error
            self.na_refuse('operation_failed', "The library file is not valid JSON: #{error.message}", nil)
        end

        # Where a library save takes its geometry from: any profile source,
        # and/or profile_edit; a trace (from_trace) gives its local profile.
        def self.na_library_source(params)
            params = params.merge('profile_from' => params['from_trace']) if self.na_has?(params, 'from_trace') && !self.na_has?(params, 'profile_from')
            source = self.na_profile_source(params, required: true, default_key: self.na_text(params, 'base_profile_key', ''))
            source = self.na_apply_profile_edit(source, params['profile_edit'], params['name']) if params['profile_edit'].is_a?(Hash)
            source
        end

        # A whole asset as a new file, by SaveNew's rules: the code (from code,
        # else the name) cleaned, never a code or a file the library holds.
        def self.na_write_new_asset(asset, meta)
            code = Na__DrawProfile__ProfileWriter.Na__ProfileWriter__CleanCode(meta['Meta_ProfileId'].to_s.empty? ? meta['Meta_ProfileName'] : meta['Meta_ProfileId'])
            return { 'isSaved' => false, 'reason' => 'The profile code is empty once unusable characters are taken out.' } if code.empty?
            clash = self.na_code_clash(code)
            return { 'isSaved' => false, 'reason' => "The library already holds \"#{clash}\", which the code \"#{code}\" would duplicate." } if clash
            file_name = Na__EditProfile__FileRenamer.Na__FileRenamer__SanitiseFileName(code)
            return { 'isSaved' => false, 'reason' => 'No usable file name could be made from the code.' } unless file_name
            library_dir = Na__EditProfile__LibraryPaths::NA_PROFILE_DATA_DIR
            path = File.join(library_dir, file_name).tr('\\', '/')
            return { 'isSaved' => false, 'reason' => "A file named \"#{file_name}\" is already in the library." } if File.exist?(path)

            meta = meta.merge('Meta_ProfileId' => code)
            data = Na__ProfileExporter.Na__Exporter__BuildJsonPayload({}, meta)
            data['meta']['fileName']    = file_name
            data['meta']['description'] = 'Profile saved through the Na SketchUp MCP (Na__ProfileTools__ProfilePathTracer).'
            %w[Na__Asset__Profile2D Na__Asset__Mesh3D Na__Asset__Annotations2D].each do |block|
                if asset[block].is_a?(Hash)
                    data[block] = self.na_deep_copy(asset[block])
                else
                    data.delete(block)
                end
            end
            data['Na__Asset__Metadata']['Na__Asset__Notes'] = 'Saved through the Na SketchUp MCP from a trace or a reshaped profile.'
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteFile(path, data)
            record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(path)
            return { 'isSaved' => false, 'reason' => "Written to #{file_name} but it did not read back as a profile; delete it." } unless record
            { 'isSaved' => true, 'profileKey' => record['profileKey'], 'filePath' => path, 'profileRecord' => record }
        end

        # The existing key a new code would duplicate, exactly or once both are
        # cleaned (file names follow the cleaned code), or nil.
        def self.na_code_clash(code)
            return nil if code.to_s.empty?
            Na__ProfileLibrary.Na__ProfileLibrary__EnabledProfiles.map { |record| record['profileKey'].to_s }.find do |key|
                key == code || Na__DrawProfile__ProfileWriter.Na__ProfileWriter__CleanCode(key) == code
            end
        end

        def self.na_saved(result, verb, source = nil)
            record = result['profileRecord'] || {}
            facts  = self.na_shape_facts(record.dig('profileData', 'assetData'))
            {
                'saved'   => true,
                'key'     => result['profileKey'],
                'name'    => record['displayName'],
                'file'    => result['filePath'],
                'size_mm' => facts['size_mm'],
                'vertices' => facts['vertices'],
                'from'    => source ? source[:kind] : nil,
                'summary' => "\"#{record['displayName'] || result['profileKey']}\" #{verb} (#{facts['size_mm'] ? "#{facts['size_mm'][0]} x #{facts['size_mm'][1]} mm" : 'no size'}). The Gallery shows it after a refresh."
            }.compact
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | set_meta / rename_file / redatum / flip
# -----------------------------------------------------------------------------

        def self.na_library_set_meta(params)
            record = self.na_library_record(params)
            info   = record.dig('profileData', 'assetData', 'Na__Asset__Metadata') || {}
            meta   = record.dig('profileData', 'assetData', 'meta') || {}
            request = {
                'profileKey'  => record['profileKey'],
                'sourceFile'  => record['sourceFile'],
                'name'        => self.na_text(params, 'name', info['Na__Asset__Name'].to_s),
                'description' => self.na_text(params, 'description', info['Na__Asset__Description'].to_s),
                'keywords'    => params['keywords'].is_a?(Array) ? params['keywords'] : Array(meta['Meta_ProfileKeywords'])
            }
            request['shortName'] = params['short_name'].to_s if self.na_has?(params, 'short_name')
            self.na_meta_write(request, 'details saved')
        end

        def self.na_library_redatum(params)
            record = self.na_library_record(params)
            datum  = params['datum']
            unless datum.is_a?(Array) && datum.length == 2 && datum.all? { |value| value.is_a?(Numeric) }
                self.na_refuse('invalid_params', 'redatum needs datum: [y, z] in mm, the profile point that becomes 0,0.', 'profile_tracer {action: "profile"} shows the outline points.')
            end
            self.na_meta_write(self.na_meta_request(record).merge('originOffset' => { 'y' => datum[0].to_f, 'z' => datum[1].to_f }), 're-datumed')
        end

        def self.na_library_flip(params)
            record = self.na_library_record(params)
            self.na_meta_write(self.na_meta_request(record).merge('flipHorizontal' => true), 'flipped left to right')
        end

        def self.na_library_rename_file(params)
            record = self.na_library_record(params)
            file_name = self.na_text(params, 'file_name', '').strip
            self.na_refuse('invalid_params', 'rename_file needs file_name.', nil) if file_name.empty?
            result = Na__EditProfile__FileRenamer.Na__FileRenamer__Rename(
                'profileKey' => record['profileKey'], 'sourceFile' => record['sourceFile'], 'newFileName' => file_name
            )
            self.na_refuse('operation_failed', (result['reason'] || result['statusMessage']).to_s, nil) unless result['isRenamed'] == true
            { 'renamed' => true, 'key' => record['profileKey'], 'result' => result.reject { |key, _| key == 'profileRecord' }, 'summary' => result['statusMessage'].to_s }
        end

        # The MetaWriter rewrites name, description and keywords on every call,
        # so a geometry-only change sends back what the file already holds.
        def self.na_meta_request(record)
            info = record.dig('profileData', 'assetData', 'Na__Asset__Metadata') || {}
            meta = record.dig('profileData', 'assetData', 'meta') || {}
            {
                'profileKey'  => record['profileKey'],
                'sourceFile'  => record['sourceFile'],
                'name'        => info['Na__Asset__Name'].to_s,
                'description' => info['Na__Asset__Description'].to_s,
                'keywords'    => Array(meta['Meta_ProfileKeywords'])
            }
        end

        def self.na_meta_write(request, verb)
            result = Na__EditProfile__MetaWriter.Na__MetaWriter__SaveMeta(request)
            self.na_refuse('operation_failed', result['reason'].to_s, 'Nothing was written.') unless result['isSaved']
            self.na_saved(result.merge('filePath' => request['sourceFile']), "#{verb} (the old file kept as .bak)")
        end

        def self.na_library_record(params)
            key = self.na_text(params, 'profile_key', '').strip
            self.na_refuse('invalid_params', 'Say which library profile: profile_key.', 'profile_tracer {action: "profiles"} lists them.') if key.empty?
            self.na_source_from_library(key)[:record]
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | delete
# -----------------------------------------------------------------------------

        def self.na_library_delete(params)
            record = self.na_library_record(params)
            key    = record['profileKey'].to_s
            self.na_require_confirm(params, key, 'delete')
            model = params['model_object'] || Sketchup.active_model
            using = model ? self.na_key_usage(model)[key].to_i : 0

            if self.na_bool(params, 'permanent', false)
                result = Na__EditProfile__ProfileDeleter.Na__ProfileDeleter__Delete('profileKey' => key, 'sourceFile' => record['sourceFile'])
                self.na_refuse('operation_failed', result['reason'].to_s, nil) unless result['isDeleted']
                return { 'deleted' => key, 'permanent' => true, 'traces_still_using' => using, 'summary' => result['statusMessage'].to_s }
            end

            path_check = Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(record['sourceFile'])
            self.na_refuse('operation_failed', path_check['reason'].to_s, nil) unless path_check['isValid']
            path = path_check['expandedPath']
            aside = "#{path}.deleted__#{Time.now.strftime('%Y%m%d-%H%M%S')}"
            File.rename(path, aside)
            {
                'deleted'   => key,
                'permanent' => false,
                'set_aside' => aside,
                'traces_still_using' => using,
                'summary'   => "\"#{record['displayName']}\" left the library: its file is now #{File.basename(aside)} (rename it back to .json to restore it)." \
                               "#{using > 0 ? " #{using} trace(s) in this model still use the key and keep their solids; a rebuild of them would fail." : ''}"
            }
        end

        def self.na_require_confirm(params, key, what)
            return if self.na_text(params, 'confirm', '').strip == key
            self.na_refuse('confirmation_required', "#{what} changes Adam's library: pass confirm = \"#{key}\".",
                           "Only when Adam asked for this #{what} of this profile.")
        end

# endregion -------------------------------------------------------------------

    end # module Na__McpOperations
end # module Na__ProfileTools__ProfilePathTracer

# =============================================================================
# END OF FILE
# =============================================================================
