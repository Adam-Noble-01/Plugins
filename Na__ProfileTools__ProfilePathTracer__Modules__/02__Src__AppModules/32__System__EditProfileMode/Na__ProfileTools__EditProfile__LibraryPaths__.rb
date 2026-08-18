# =============================================================================
# NA PROFILE TOOLS - EDIT PROFILE MODE - LIBRARY PATHS
# =============================================================================
#
# FILE       : Na__ProfileTools__EditProfile__LibraryPaths__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditProfile__LibraryPaths
# PURPOSE    : The one path guard for every operation that writes over or
#              deletes a profile data file.
#
# WHY THIS EXISTS
#   Three operations can now damage a user's library — metadata overwrite,
#   geometry re-capture, and outright delete. Each carries a file path supplied
#   by the dialog, so each needs the same traversal check. Three copies of that
#   check would drift; this is the single copy all three call.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__LibraryPaths

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

        # Returns { 'isValid' => true, 'expandedPath' => <absolute path> } or
        # { 'isValid' => false, 'reason' => <message> }. Callers must bail on a
        # false before touching the filesystem.
        def self.Na__LibraryPaths__ValidateProfileFile(source_file)
            candidate_path = source_file.to_s.strip
            if candidate_path.empty?
                return { 'isValid' => false, 'reason' => 'Source file path is required.' }
            end

            expanded_source = File.expand_path(candidate_path)
            expanded_root   = File.expand_path(NA_PROFILE_DATA_DIR)

            # The separator is appended before comparing, so a sibling folder
            # whose name merely starts with the library folder name — say
            # 04__Data__ProfileLibrary__Archive — cannot pass the guard.
            unless expanded_source.start_with?(expanded_root + File::SEPARATOR)
                return {
                    'isValid' => false,
                    'reason'  => 'Source file is outside the permitted profile data directory.'
                }
            end

            unless expanded_source.end_with?('.json')
                return { 'isValid' => false, 'reason' => 'Source file is not a .json file.' }
            end

            unless File.file?(expanded_source)
                return { 'isValid' => false, 'reason' => "Source file not found: #{source_file}" }
            end

            { 'isValid' => true, 'expandedPath' => expanded_source }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
