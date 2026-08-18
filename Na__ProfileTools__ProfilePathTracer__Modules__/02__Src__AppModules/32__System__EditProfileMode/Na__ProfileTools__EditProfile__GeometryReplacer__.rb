# =============================================================================
# NA PROFILE TOOLS - EDIT PROFILE MODE - GEOMETRY REPLACER
# =============================================================================
#
# FILE       : Na__ProfileTools__EditProfile__GeometryReplacer__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditProfile__GeometryReplacer
# PURPOSE    : Re-run the Create Profile capture against an EXISTING library
#              file — new selection, new origin point, same asset identity.
#
# WHY THIS EXISTS
#   Creating a profile is a one-shot capture: whatever face was selected and
#   wherever the origin was clicked is what the library gets, permanently. Miss
#   the origin by a few millimetres and the only remedy was to export a second
#   profile and delete the first, losing the code, keywords and description
#   along with it. This re-captures the geometry in place so a profile's
#   identity survives a re-take.
#
# REPLACE CONTRACT
#   1. Path guard the target file (Na__EditProfile__LibraryPaths).
#   2. Validate the live SketchUp selection through the exporter's own rules,
#      so a profile can never be re-captured from geometry that Create Profile
#      would have refused.
#   3. Collect geometry against the freshly picked origin point.
#   4. Replace ONLY Na__Asset__Profile2D and Na__Asset__Mesh3D. Both blocks are
#      shallow-merged over the existing ones, so any hand-added keys inside them
#      survive. Everything else in the file — code, name, notes, supplier
#      fields, placement offsets, finishes — is left exactly as authored.
#   5. Fold in whatever metadata is currently typed into the Edit form, on this
#      same write, so a re-capture cannot silently discard unsaved edits.
#   6. Write <file>.bak LAST, immediately before the overwrite, so a path that
#      bails out early cannot burn the user's rollback point.
#   7. Drop a 00__OriginPoint helper at the picked point, matching Create.
#   8. Return the freshly re-parsed record so the store can update.
#
# NOT IN SCOPE
#   Runs already placed in the model are not rebuilt. Their geometry was baked
#   at generate time; only Dynamic Regeneration touches those.
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__EditProfile__GeometryReplacer

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__GeometryReplacer__Replace(params, origin_point)
            params = {} unless params.is_a?(Hash)

            profile_key = params['profileKey'].to_s.strip
            if profile_key.empty?
                return self.Na__GeometryReplacer__Failure('Profile key is required.')
            end

            unless origin_point
                return self.Na__GeometryReplacer__Failure('No origin point was picked.', profile_key)
            end

            path_check = Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(params['sourceFile'])
            unless path_check['isValid']
                return self.Na__GeometryReplacer__Failure(path_check['reason'], profile_key)
            end

            # Re-validated here rather than trusted from the arming call: the
            # user has been back in the model picking a point since then and may
            # have changed the selection.
            validation = Na__ProfileExporter.Na__Exporter__ValidateSelection(origin_point)
            unless validation['isValid']
                return self.Na__GeometryReplacer__Failure(validation['reason'], profile_key)
            end

            self.Na__GeometryReplacer__WriteGeometry(path_check['expandedPath'], profile_key, params, origin_point)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__GeometryReplacer__Replace failed.', error)
            self.Na__GeometryReplacer__Failure("Geometry re-capture failed: #{error.message}", profile_key)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Write Geometry
    # -------------------------------------------------------------------------

        def self.Na__GeometryReplacer__WriteGeometry(expanded_path, profile_key, params, origin_point)
            raw_content = File.read(expanded_path, encoding: 'utf-8')
            data        = JSON.parse(raw_content)

            geometry_data = Na__ProfileExporter.Na__Exporter__CollectGeometry(origin_point)
            unless geometry_data
                return self.Na__GeometryReplacer__Failure(
                    'No geometry could be collected from the selection — nothing was written.',
                    profile_key
                )
            end

            self.Na__GeometryReplacer__MergeGeometryBlocks(data, geometry_data)

            # @delegate: Na__ProfileTools__EditProfile__MetaWriter__
            Na__EditProfile__MetaWriter.Na__MetaWriter__PatchData(
                data,
                params['name'].to_s.strip,
                params['description'].to_s,
                Array(params['keywords'])
            )

            # @delegate: Na__ProfileTools__EditProfile__MetaWriter__
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteBackup(expanded_path, raw_content)
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteFile(expanded_path, data)

            fresh_record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(expanded_path)
            unless fresh_record
                return self.Na__GeometryReplacer__Failure(
                    'Geometry written, but the updated file failed to re-parse. Restore the .bak alongside it.',
                    profile_key
                )
            end

            helper_result = Na__ProfileExporter.Na__Exporter__CreateOriginHelperAtPoint(origin_point)
            counts = self.Na__GeometryReplacer__Counts(geometry_data)

            {
                'isReplaced'          => true,
                'isPending'           => false,
                'profileKey'          => profile_key,
                'profileRecord'       => fresh_record,
                'originHelperCreated' => helper_result['isCreated'] == true,
                'originHelperReason'  => helper_result['reason'],
                'reason'              => nil,
                'statusMessage'       => self.Na__GeometryReplacer__SuccessMessage(fresh_record, counts, helper_result)
            }
        rescue JSON::ParserError => error
            self.Na__GeometryReplacer__Failure("JSON parse error: #{error.message}", profile_key)
        rescue => error
            self.Na__GeometryReplacer__Failure("Write failed: #{error.message}", profile_key)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Block Merge
    # -------------------------------------------------------------------------

        # Shallow-merged rather than assigned outright. The exporter writes every
        # key the schema needs, but a library file may carry hand-added keys
        # inside these blocks, and a re-capture is not a licence to drop them.
        def self.Na__GeometryReplacer__MergeGeometryBlocks(data, geometry_data)
            fresh_blocks = Na__ProfileExporter.Na__Exporter__BuildGeometryBlocks(geometry_data)

            fresh_blocks.each do |block_key, fresh_block|
                existing_block = data[block_key]
                data[block_key] = existing_block.is_a?(Hash) ? existing_block.merge(fresh_block) : fresh_block
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Result Helpers
    # -------------------------------------------------------------------------

        def self.Na__GeometryReplacer__Counts(geometry_data)
            {
                'vertices' => Array(geometry_data['profileVertices']).length,
                'edges'    => Array(geometry_data['profileEdges']).length,
                'faces'    => Array(geometry_data['profileFaces']).length
            }
        end

        def self.Na__GeometryReplacer__SuccessMessage(fresh_record, counts, helper_result)
            display_name = fresh_record['displayName'].to_s
            display_name = fresh_record['profileKey'].to_s if display_name.strip.empty?

            helper_note = if helper_result['isCreated'] == true
                              ' Origin helper inserted at the picked point.'
                          elsif helper_result['reason'].to_s.strip.empty?
                              ''
                          else
                              " Origin helper note: #{helper_result['reason']}"
                          end

            "Geometry re-captured for \"#{display_name}\" — " \
            "#{counts['vertices']} vertices, #{counts['edges']} edges, #{counts['faces']} faces. " \
            "Backup written as .bak.#{helper_note}"
        end

        def self.Na__GeometryReplacer__Failure(reason, profile_key = '')
            {
                'isReplaced'    => false,
                'isPending'     => false,
                'profileKey'    => profile_key,
                'reason'        => reason,
                'statusMessage' => "Geometry re-capture blocked: #{reason}"
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
