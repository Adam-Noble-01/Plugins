# =============================================================================
# NA PROFILE TOOLS - EDIT PROFILE MODE - PROFILE DELETER
# =============================================================================
#
# FILE       : Na__ProfileTools__EditProfile__ProfileDeleter__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditProfile__ProfileDeleter
# PURPOSE    : Permanently remove a profile data file from the library.
#
# DELETE CONTRACT
#   1. Path guard the target (Na__EditProfile__LibraryPaths) — the caller hands
#      in a path that originated in the dialog, so it is never trusted.
#   2. Confirm the file still parses as a profile before removing it. A file
#      that will not parse is not in the gallery, so a delete request naming one
#      means the dialog and disk have diverged and the request is stale.
#   3. Delete the .json. This is not a soft delete and there is no undo — the
#      dialog gates it behind an explicit confirmation for exactly that reason.
#   4. Report any sibling .bak left on disk, so the user knows a recovery
#      artefact exists rather than assuming everything is gone.
#
# NOT IN SCOPE
#   Geometry already placed in the model is untouched. Deleting the data file
#   only removes the profile from the library, so those runs can no longer be
#   re-applied or regenerated from it.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__ProfileDeleter

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__ProfileDeleter__Delete(params)
            params = {} unless params.is_a?(Hash)

            profile_key = params['profileKey'].to_s.strip
            if profile_key.empty?
                return self.Na__ProfileDeleter__Failure('Profile key is required.')
            end

            path_check = Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(params['sourceFile'])
            unless path_check['isValid']
                return self.Na__ProfileDeleter__Failure(path_check['reason'], profile_key)
            end

            expanded_path = path_check['expandedPath']

            # Guards against a stale dialog: if this file no longer parses as the
            # profile the user is looking at, the request does not describe what
            # is actually on disk and must not be acted on.
            record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(expanded_path)
            unless record
                return self.Na__ProfileDeleter__Failure(
                    'Target file is not a readable profile data file — nothing was deleted.',
                    profile_key
                )
            end

            unless record['profileKey'].to_s == profile_key
                return self.Na__ProfileDeleter__Failure(
                    "Target file holds profile \"#{record['profileKey']}\", not \"#{profile_key}\" — nothing was deleted.",
                    profile_key
                )
            end

            display_name = record['displayName'].to_s
            display_name = profile_key if display_name.strip.empty?

            File.delete(expanded_path)

            {
                'isDeleted'     => true,
                'profileKey'    => profile_key,
                'displayName'   => display_name,
                'filePath'      => expanded_path,
                'reason'        => nil,
                'statusMessage' => self.Na__ProfileDeleter__SuccessMessage(display_name, expanded_path)
            }
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__ProfileDeleter__Delete failed.', error)
            self.Na__ProfileDeleter__Failure("Delete failed: #{error.message}", profile_key)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Result Helpers
    # -------------------------------------------------------------------------

        # The .bak note matters: the confirmation told the user this is
        # permanent, so an unmentioned recovery file on disk would be a
        # surprise in either direction.
        def self.Na__ProfileDeleter__SuccessMessage(display_name, expanded_path)
            backup_path = expanded_path + '.bak'
            backup_note = File.file?(backup_path) ?
                " A .bak of the previous save remains at #{File.basename(backup_path)}." : ''

            "Profile \"#{display_name}\" permanently deleted: #{expanded_path}#{backup_note}"
        rescue
            "Profile \"#{display_name}\" permanently deleted: #{expanded_path}"
        end

        def self.Na__ProfileDeleter__Failure(reason, profile_key = '')
            {
                'isDeleted'     => false,
                'profileKey'    => profile_key,
                'reason'        => reason,
                'statusMessage' => "Delete blocked: #{reason}"
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
