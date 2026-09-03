# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - PLACEMENT ENGINE
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__PlacementEngine__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__ProfilePlacementEngine
# PURPOSE    : High-level orchestration for profile trace generation
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__ProfilePlacementEngine

    # -------------------------------------------------------------------------
    # REGION | Engine Surface
    # -------------------------------------------------------------------------

        NA_INTERACTIVE_POINT_MERGE_TOLERANCE = 0.001
        NA_INTERACTIVE_LOOP_CLOSE_TOLERANCE = 5.mm

        def self.Na__Engine__ResolveProfileData(generate_config = {})
            source_mode = generate_config['profileSourceMode'].to_s
            source_mode = 'library' if source_mode.empty?

            if source_mode == 'scene'
                scene_profile = Na__SceneProfileRegistry.Na__SceneProfileRegistry__ProfileData
                return { 'isValid' => false, 'reason' => 'Pick a scene profile source first.' } unless scene_profile
                unless self.Na__Engine__UnifiedProfileRecord?(scene_profile)
                    return { 'isValid' => false, 'reason' => 'Scene profile is not in unified schema format.' }
                end

                return {
                    'isValid' => true,
                    'reason' => nil,
                    'profileKey' => scene_profile['profileKey'],
                    'profileData' => scene_profile
                }
            end

            profile_key = generate_config['profileKey']
            profile_data = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            return { 'isValid' => false, 'reason' => 'Select a valid profile.' } unless profile_data
            unless self.Na__Engine__UnifiedProfileRecord?(profile_data)
                return { 'isValid' => false, 'reason' => 'Selected profile is not in unified schema format.' }
            end

            {
                'isValid' => true,
                'reason' => nil,
                'profileKey' => profile_key,
                'profileData' => profile_data
            }
        end

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

        def self.Na__Engine__BuildPathDataFromInteractivePoints(path_points, is_closed_loop = nil)
            cleaned_points = Array(path_points).compact
            return nil if cleaned_points.length < 2

            sanitized_points = [cleaned_points.first]
            cleaned_points[1..-1].each do |point|
                next if sanitized_points.last.distance(point) <= NA_INTERACTIVE_POINT_MERGE_TOLERANCE
                sanitized_points << point
            end
            return nil if sanitized_points.length < 2

            resolved_closed_loop = self.Na__Engine__ResolveInteractiveClosedLoopState(sanitized_points, is_closed_loop)
            if resolved_closed_loop &&
               sanitized_points.length >= 3 &&
               sanitized_points.first.distance(sanitized_points.last) <= NA_INTERACTIVE_LOOP_CLOSE_TOLERANCE
                sanitized_points[-1] = sanitized_points.first
            end
            if resolved_closed_loop &&
               sanitized_points.length >= 3 &&
               sanitized_points.first.distance(sanitized_points.last) <= NA_INTERACTIVE_POINT_MERGE_TOLERANCE
                sanitized_points = sanitized_points[0...-1]
            end

            if resolved_closed_loop
                sanitized_points = self.Na__Engine__NormaliseInteractiveLoopWinding(sanitized_points)
            else
                sanitized_points = self.Na__Engine__AlignOpenRunToCanonicalDirection(sanitized_points)
            end

            {
                ordered_points: sanitized_points,
                ordered_edges: [],
                is_closed_loop: resolved_closed_loop
            }
        end

        # OPEN RUNS — canonical traversal by axis sign, no camera anywhere
        #
        # A closed loop has an inside and an outside, so its winding can be
        # normalised against the geometry itself. An open run has neither: which
        # side the moulding lands on follows the direction of travel and nothing
        # else, so drawing the same wall left-to-right or right-to-left gave
        # mirror images with nothing to prefer between them.
        #
        # Two camera-relative tie-breakers were tried and both failed in use —
        # v1.6.5 probed toward the viewer, v1.6.6 away — and for the same
        # structural reason: a probe snapped to the camera axis says NOTHING
        # about a run drawn perpendicular to it (dot product zero), and drawing
        # an X run while viewing down the Y axis is not an edge case, it is how
        # people actually work. The "tie" was the common case.
        #
        # So the camera is out of the decision entirely. Field-tested rule
        # (03-Sep-2026): a run whose net direction is NEGATIVE along its
        # dominant model axis builds with the correct handedness; a POSITIVE
        # one comes out mirrored. Canonical traversal is therefore
        # negative-along-axis — a positive run is reversed, a negative one
        # kept. Deterministic, orbit-proof, and the same answer whichever way
        # the run was drawn. Reversal changes traversal order only; the swept
        # solid occupies identical space either way.
        def self.Na__Engine__AlignOpenRunToCanonicalDirection(sanitized_points)
            return sanitized_points if sanitized_points.length < 2

            # NET direction (last point minus first), not the first segment:
            # reversing a multi-segment run makes a DIFFERENT segment the first
            # one, so a first-segment test can reverse a run and still not
            # satisfy itself. Net direction negates under reversal, so this
            # converges in one step.
            net_direction = sanitized_points.last - sanitized_points.first

            x_run = net_direction.x.to_f
            y_run = net_direction.y.to_f
            dominant_component = x_run.abs >= y_run.abs ? x_run : y_run

            # A pure vertical or degenerate run has no horizontal sign to judge
            # by — left exactly as drawn.
            return sanitized_points if dominant_component.abs <= NA_INTERACTIVE_POINT_MERGE_TOLERANCE
            return sanitized_points if dominant_component < 0

            sanitized_points.reverse
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Open run canonical alignment skipped: #{error.message}")
            sanitized_points
        end

        # WINDING PARITY — why this exists
        #
        # The sweep frame is x_axis = tangent x Z, so which side of the path the
        # section lands on is decided entirely by the direction the points run.
        # Traverse a loop the other way and the profile mirrors about the
        # vertical: same shape, back to front. Reverse does undo it — the 180 deg
        # roll flips PosY and PosZ, the world-Z mirror puts the vertical back —
        # but needing Reverse on every anticlockwise loop is the defect, not the
        # remedy.
        #
        # Every other path producer already normalises a closed loop to one
        # winding before it reaches the builder:
        #
        #   Na__Path__OrderEdges     (Selection mode)          -> normalises
        #   Na__Path__WalkChainFrom  (Dynamic Regeneration)    -> normalises
        #   this method              (Interactive mode)        -> did NOT
        #
        # So a loop drawn anticlockwise in plan came out mirrored against the
        # identical loop selected as edges, and — worse — flipped on its first
        # regeneration, because the regen walk normalised the winding the build
        # never had. This closes that gap with the SAME shared normaliser rather
        # than a mode-specific flip, so all three producers agree by construction.
        #
        # Open paths are deliberately untouched: the normaliser is gated on
        # closed loops in the other two producers too, and for an open run the
        # draw direction IS the user's intent.
        def self.Na__Engine__NormaliseInteractiveLoopWinding(sanitized_points)
            return sanitized_points if sanitized_points.length < 3

            # @delegate: ../04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__PathAnalysis__
            normalised = Na__PathAnalysis.Na__Path__NormaliseClosedLoopWinding(sanitized_points, [])
            normalised_points = Array(normalised[:ordered_points])
            return sanitized_points if normalised_points.length != sanitized_points.length

            # Reversing moves the user's first click to the far end of the list,
            # and that first point is what becomes the frame origin, the follow-me
            # seam and the StartPoint the regen anchor is measured from. Rotating
            # it back keeps the seam where the user put it, exactly as
            # Na__Path__RotateLoopToAnchor does for a regenerated chain. A no-op
            # when the winding was already correct.
            anchor = sanitized_points.first
            anchor_index = normalised_points.index { |candidate| candidate == anchor }
            return normalised_points if anchor_index.nil? || anchor_index.zero?

            normalised_points[anchor_index..-1] + normalised_points[0...anchor_index]
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Interactive loop winding normalise skipped: #{error.message}")
            sanitized_points
        end

        def self.Na__Engine__ResolveInteractiveClosedLoopState(path_points, is_closed_loop)
            return true if is_closed_loop == true
            return false if is_closed_loop == false
            self.Na__Engine__InteractivePathClosedLoop?(path_points)
        end

        def self.Na__Engine__InteractivePathClosedLoop?(path_points)
            points = Array(path_points).compact
            return false if points.length < 3
            points.first.distance(points.last) <= NA_INTERACTIVE_LOOP_CLOSE_TOLERANCE
        end

        def self.Na__Engine__GenerateFromInteractivePath(profile_key:, profile_data:, path_points:, rotation_step:, toggle_states: {}, reverse_direction: false, origin_offset: nil)
            model = Sketchup.active_model
            return { 'isBuilt' => false, 'statusMessage' => 'Generation failed: No active model.' } unless model

            path_data = self.Na__Engine__BuildPathDataFromInteractivePoints(path_points)
            return { 'isBuilt' => false, 'statusMessage' => 'Generation failed: Add at least two waypoints.' } unless path_data

            start_point = path_data[:ordered_points].first
            self.Na__Engine__GenerateFromPathData(
                profile_key: profile_key,
                profile_data: profile_data,
                path_data: path_data,
                start_point: start_point,
                rotation_step: rotation_step,
                toggle_states: toggle_states,
                reverse_direction: reverse_direction,
                origin_offset: origin_offset
            )
        end

        def self.Na__Engine__BuildFromSelection(profile_key, selected_entities, toggle_states = {},
                                                 rotation_step: 0, reverse_direction: false, origin_offset: nil)
            path_result = Na__PathAnalysis.Na__Path__BuildSegments(selected_entities)
            return { 'isBuilt' => false, 'reason' => path_result[:reason] } unless path_result[:isValid]

            model = Sketchup.active_model
            profile_data = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            return { 'isBuilt' => false, 'reason' => 'Select a valid profile.' } unless profile_data
            return { 'isBuilt' => false, 'reason' => 'Selected profile is not in unified schema format.' } unless self.Na__Engine__UnifiedProfileRecord?(profile_data)

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
                rotation_step: rotation_step,
                toggle_states: toggle_states,
                reverse_direction: reverse_direction,
                origin_offset: origin_offset
            )
        end

        def self.Na__Engine__GenerateFromPathData(profile_key:, profile_data:, path_data:, start_point:, rotation_step:, toggle_states: {}, reverse_direction: false, origin_offset: nil)
            model = Sketchup.active_model
            return { 'isBuilt' => false, 'statusMessage' => 'Generation failed: No active model.' } unless model
            unless self.Na__Engine__UnifiedProfileRecord?(profile_data)
                return { 'isBuilt' => false, 'statusMessage' => 'Generation failed: profile schema is not unified.' }
            end

            self.Na__Engine__LogActiveBuilderRuntimeOnce

            resolved_path_data = path_data
            if path_data[:ordered_edges].is_a?(Array) && !path_data[:ordered_edges].empty?
                reordered_path = Na__PathAnalysis.Na__Path__ReorderPathFromStart(path_data, start_point)
                unless reordered_path[:isValid]
                    return {
                        'isBuilt' => false,
                        'statusMessage' => "Generation failed: #{reordered_path[:reason]}"
                    }
                end
                resolved_path_data = reordered_path[:pathData]
            end

            result = Na__GeometryBuilders.Na__Geometry__BuildProfileAlongPath(
                model: model,
                profile_data: profile_data.merge('profileKey' => profile_key),
                path_data: resolved_path_data,
                start_point: start_point,
                rotation_step: rotation_step,
                toggle_states: toggle_states,
                reverse_direction: reverse_direction,
                origin_offset: origin_offset
            )

            if result['isBuilt']
                {
                    'isBuilt' => true,
                    'statusMessage' => "Generated profile along path: #{result['groupName']} (styled edges: #{result['styledEdgeCount'].to_i})"
                }
            else
                {
                    'isBuilt' => false,
                    'statusMessage' => "Generation failed: #{result['reason']}"
                }
            end
        end

        def self.Na__Engine__UnifiedProfileRecord?(profile_record)
            return false unless profile_record.is_a?(Hash)
            type_name = profile_record.dig('profileData', 'type').to_s
            return false unless type_name == 'na_unified_asset'
            asset_data = profile_record.dig('profileData', 'assetData')
            return false unless asset_data.is_a?(Hash)
            asset_data.key?('Na__Asset__Profile2D') && asset_data.key?('Na__Asset__Mesh3D')
        end

        def self.Na__Engine__LogActiveBuilderRuntimeOnce
            @na_runtime_builder_logged_once ||= false
            return if @na_runtime_builder_logged_once == true

            builder_source = Na__ProfileTools__ProfilePathTracer.Na__Runtime__GeometryBuilderSourceLocation
            builder_source = '(source unavailable)' if builder_source.to_s.empty?
            Na__DebugTools.Na__Debug__Info("Active geometry builder source: #{builder_source}")
            @na_runtime_builder_logged_once = true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Runtime builder log warning: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
