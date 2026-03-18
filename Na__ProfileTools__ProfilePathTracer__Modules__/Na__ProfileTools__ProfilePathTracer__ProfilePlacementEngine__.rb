# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PROFILE PLACEMENT ENGINE
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__ProfilePlacementEngine__.rb
# PURPOSE    : High-level orchestration for profile trace generation
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__ProfilePlacementEngine

    # -------------------------------------------------------------------------
    # REGION | Engine Surface
    # -------------------------------------------------------------------------

        def self.Na__Engine__ValidateSelectionForPreview(profile_key)
            model = Sketchup.active_model
            return { 'isValid' => false, 'reason' => 'No active model.' } unless model

            profile_data = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            return { 'isValid' => false, 'reason' => 'Select a valid profile.' } unless profile_data

            selected_entities = model.selection.to_a
            path_result = Na__PathAnalysis.Na__Path__BuildSegments(selected_entities)
            return { 'isValid' => false, 'reason' => path_result[:reason] } unless path_result[:isValid]

            {
                'isValid' => true,
                'reason' => nil,
                'profileData' => profile_data,
                'pathData' => {
                    ordered_points: path_result[:orderedPoints],
                    ordered_edges: path_result[:orderedEdges],
                    is_closed_loop: path_result[:isClosedLoop]
                }
            }
        end

        def self.Na__Engine__BuildFromSelection(profile_key, selected_entities)
            path_result = Na__PathAnalysis.Na__Path__BuildSegments(selected_entities)
            return { 'isBuilt' => false, 'reason' => path_result[:reason] } unless path_result[:isValid]

            model = Sketchup.active_model
            profile_data = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            return { 'isBuilt' => false, 'reason' => 'Select a valid profile.' } unless profile_data

            start_point = path_result[:orderedPoints].first
            self.Na__Engine__GenerateFromPathData(
                profile_key: profile_key,
                profile_data: profile_data,
                path_data: {
                    ordered_points: path_result[:orderedPoints],
                    ordered_edges: path_result[:orderedEdges],
                    is_closed_loop: path_result[:isClosedLoop]
                },
                start_point: start_point,
                rotation_step: 0
            )
        end

        def self.Na__Engine__GenerateFromPathData(profile_key:, profile_data:, path_data:, start_point:, rotation_step:)
            model = Sketchup.active_model
            reordered_path = Na__PathAnalysis.Na__Path__ReorderPathFromStart(path_data, start_point)
            unless reordered_path[:isValid]
                return {
                    'isBuilt' => false,
                    'statusMessage' => "Generation failed: #{reordered_path[:reason]}"
                }
            end

            result = Na__GeometryBuilders.Na__Geometry__BuildProfileAlongPath(
                model: model,
                profile_data: profile_data.merge('profileKey' => profile_key),
                path_data: reordered_path[:pathData],
                start_point: start_point,
                rotation_step: rotation_step
            )

            if result['isBuilt']
                {
                    'isBuilt' => true,
                    'statusMessage' => "Generated profile along path: #{result['groupName']}"
                }
            else
                {
                    'isBuilt' => false,
                    'statusMessage' => "Generation failed: #{result['reason']}"
                }
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
