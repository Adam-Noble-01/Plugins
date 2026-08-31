# =============================================================================
# NA PROFILE TOOLS - EDIT PROFILE MODE - FILE RENAMER
# =============================================================================
#
# FILE       : Na__ProfileTools__EditProfile__FileRenamer__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditProfile__FileRenamer
# PURPOSE    : Rename a profile's data file on disk from inside the dialog, so
#              a placeholder capture can be given its real library name without
#              leaving SketchUp.
#
# WHY THIS EXISTS
#   Profiles get captured mid-model under throwaway names — TEMP__, Z-RENAME__,
#   whatever was quick to type — because the shape matters and the name does
#   not, yet. Until now the only way to correct that was to leave the model,
#   rename the .json in Explorer and reload, or to re-export the profile and
#   delete the original. This is the same on-disk rename the Component Editor
#   Tools do for .skp library files, applied to profile data files.
#
#   @delegate: Na__ComponentEditorTools__LibraryManager__Editor__.rb
#              (Na__ComponentEditorTools__RenameFileOnDisk — same sanitise,
#               same collision guard, same "return the new path" contract)
#
# RENAME CONTRACT
#   1. Path guard the current file (Na__EditProfile__LibraryPaths), the guard
#      shared with the metadata, re-capture and delete paths. The dialog
#      supplies the path, so it is never trusted.
#   2. Confirm the file still parses as the profile the dialog is showing. A
#      mismatch means the dialog and disk have diverged and the request is stale.
#   3. Sanitise the requested name to a bare basename — no directory parts, no
#      characters Windows will not take — and re-attach the .json extension.
#   4. Refuse a collision, so a rename can never overwrite another profile.
#   5. Rename. The sibling .bak comes along, or it is left pointing at a name
#      that no longer exists.
#   6. Patch meta.fileName to match, and re-parse, so the record handed back is
#      what is actually on disk.
#
# WHAT A RENAME IS NOT
#   The profile KEY (Na__Asset__Code) is untouched. That is what placed traces
#   store and what Dynamic Regeneration resolves against, so renaming the file
#   cannot orphan geometry already in a model. Only the filename changes.
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__FileRenamer

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        # Same character class the exporter sanitises new profile filenames
        # with, so a renamed file is indistinguishable from a freshly captured
        # one. @delegate: Na__ProfileTools__CreateNewProfile__Exporter__.rb
        NA_UNSAFE_FILENAME_CHARS = /[^\w\-\.\(\) ]+/.freeze

        NA_MAX_BASENAME_LENGTH = 180

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__FileRenamer__Rename(params)
            params = {} unless params.is_a?(Hash)

            profile_key   = params['profileKey'].to_s.strip
            requested_name = params['newFileName'].to_s

            if profile_key.empty?
                return self.Na__FileRenamer__Failure('Profile key is required.')
            end

            path_check = Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(params['sourceFile'])
            unless path_check['isValid']
                return self.Na__FileRenamer__Failure(path_check['reason'], profile_key)
            end

            current_path = path_check['expandedPath']

            stale_check = self.Na__FileRenamer__RejectIfStale(current_path, profile_key)
            return stale_check if stale_check

            sanitised = self.Na__FileRenamer__SanitiseFileName(requested_name)
            if sanitised.nil?
                return self.Na__FileRenamer__Failure(
                    'File name is empty once unusable characters are stripped — nothing was renamed.',
                    profile_key
                )
            end

            target_path = File.join(File.dirname(current_path), sanitised).tr('\\', '/')
            normalised_current = current_path.tr('\\', '/')

            if target_path == normalised_current
                return self.Na__FileRenamer__NoChangeResult(profile_key, normalised_current, sanitised)
            end

            collision_check = self.Na__FileRenamer__RejectIfCollision(target_path, normalised_current, sanitised, profile_key)
            return collision_check if collision_check

            self.Na__FileRenamer__PerformRename(normalised_current, target_path, sanitised, profile_key)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__FileRenamer__Rename failed.', error)
            self.Na__FileRenamer__Failure("Rename failed: #{error.message}", profile_key)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | File Name Sanitising
    # -------------------------------------------------------------------------

        # Returns a bare "<name>.json" basename, or nil when nothing usable is
        # left. File.basename first: a pasted path or a typed "..\" must land in
        # the same folder as the original, never one the path guard never saw.
        def self.Na__FileRenamer__SanitiseFileName(requested_name)
            candidate = requested_name.to_s.strip.tr('\\', '/')
            return nil if candidate.empty?

            candidate = File.basename(candidate)
            candidate = candidate[0...-5] if candidate.downcase.end_with?('.json')

            candidate = candidate.gsub(NA_UNSAFE_FILENAME_CHARS, '_')
            candidate = candidate[0, NA_MAX_BASENAME_LENGTH].to_s

            # Windows silently drops trailing dots and spaces from a filename, so
            # a name ending in either would not be the file the user asked for.
            # After the truncation, not before — a cut can land straight on one.
            candidate = candidate.strip.sub(/[.\s]+\z/, '').sub(/\A[.\s]+/, '')

            return nil if candidate.strip.empty?

            "#{candidate}.json"
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Pre-flight Guards
    # -------------------------------------------------------------------------

        # Guards against a stale dialog: if this file no longer parses as the
        # profile the user is looking at, the request does not describe what is
        # actually on disk and must not be acted on.
        def self.Na__FileRenamer__RejectIfStale(current_path, profile_key)
            record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(current_path)
            unless record
                return self.Na__FileRenamer__Failure(
                    'Target file is not a readable profile data file — nothing was renamed.',
                    profile_key
                )
            end

            unless record['profileKey'].to_s == profile_key
                return self.Na__FileRenamer__Failure(
                    "Target file holds profile \"#{record['profileKey']}\", not \"#{profile_key}\" — nothing was renamed.",
                    profile_key
                )
            end

            nil
        end

        # File.exist? is case-insensitive on Windows, so a pure re-casing of the
        # SAME file reports as a collision. That is the one case where the
        # existing file at the target path is the file being renamed, so it is
        # allowed through — every other hit is a different profile.
        def self.Na__FileRenamer__RejectIfCollision(target_path, current_path, sanitised, profile_key)
            return nil unless File.exist?(target_path)
            return nil if target_path.casecmp(current_path).zero?

            self.Na__FileRenamer__Failure(
                "A file named \"#{sanitised}\" already exists in the profile library — nothing was renamed.",
                profile_key
            )
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Rename Execution
    # -------------------------------------------------------------------------

        def self.Na__FileRenamer__PerformRename(current_path, target_path, sanitised, profile_key)
            File.rename(current_path, target_path)

            backup_note = self.Na__FileRenamer__RenameSiblingBackup(current_path, target_path)

            # Best-effort and deliberately after the rename: the file has already
            # moved, and a failure to patch one cosmetic field must not read as a
            # rename that did not happen.
            self.Na__FileRenamer__PatchMetaFileName(target_path, sanitised)

            fresh_record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(target_path)
            unless fresh_record
                return {
                    'isRenamed'     => true,
                    'profileKey'    => profile_key,
                    'fileName'      => sanitised,
                    'filePath'      => target_path,
                    'reason'        => nil,
                    'statusMessage' => "File renamed to \"#{sanitised}\", but the renamed file failed to re-parse. " \
                                       'Reopen the dialog to reload the library.'
                }
            end

            {
                'isRenamed'     => true,
                'profileKey'    => profile_key,
                'fileName'      => sanitised,
                'filePath'      => target_path,
                'profileRecord' => fresh_record,
                'reason'        => nil,
                'statusMessage' => "Data file renamed to \"#{sanitised}\". " \
                                   "Profile code \"#{profile_key}\" is unchanged, so placed runs still resolve.#{backup_note}"
            }
        end

        # A .bak left under the old name points at a file that no longer exists,
        # which is exactly the wrong thing to find when you go looking for a
        # rollback. It travels with its profile, or it is reported as left behind.
        def self.Na__FileRenamer__RenameSiblingBackup(current_path, target_path)
            current_backup = current_path + '.bak'
            return '' unless File.file?(current_backup)

            target_backup = target_path + '.bak'

            # Someone else's leftover rollback point. Overwriting it to tidy up
            # this one would destroy a recovery artefact to save a stale name.
            if File.exist?(target_backup) && !target_backup.casecmp(current_backup).zero?
                return " Note: a .bak already existed under the new name, so this profile's .bak was left " \
                       "as #{File.basename(current_backup)}."
            end

            File.rename(current_backup, target_backup)
            ' Its .bak was renamed alongside it.'
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Backup rename failed for #{current_path}: #{error.message}")
            " Note: the sibling .bak could not be renamed and still carries the old name."
        end

        def self.Na__FileRenamer__PatchMetaFileName(target_path, sanitised)
            raw_content = File.read(target_path, encoding: 'utf-8')
            data        = JSON.parse(raw_content)
            return unless data.is_a?(Hash)

            meta = data['meta']
            return unless meta.is_a?(Hash)
            return if meta['fileName'].to_s == sanitised

            meta['fileName'] = sanitised

            # @delegate: Na__ProfileTools__EditProfile__MetaWriter__
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteFile(target_path, data)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("meta.fileName patch failed for #{target_path}: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Result Helpers
    # -------------------------------------------------------------------------

        # Not a failure: the name on screen already matches disk. Reported as a
        # success so the panel settles back to idle rather than showing an error
        # for a request that asked for nothing.
        def self.Na__FileRenamer__NoChangeResult(profile_key, current_path, sanitised)
            {
                'isRenamed'     => true,
                'isUnchanged'   => true,
                'profileKey'    => profile_key,
                'fileName'      => sanitised,
                'filePath'      => current_path,
                'reason'        => nil,
                'statusMessage' => "File is already named \"#{sanitised}\" — nothing was changed."
            }
        end

        def self.Na__FileRenamer__Failure(reason, profile_key = '')
            {
                'isRenamed'     => false,
                'profileKey'    => profile_key,
                'reason'        => reason,
                'statusMessage' => "Rename blocked: #{reason}"
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
