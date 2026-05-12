# =============================================================================
# NA PROFILE TOOLS - REGENERATION ENGINE
# =============================================================================
#
# FILE       : Na__ProfileTools__RegenerationEngine__Main__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__RegenEngine
# PURPOSE    : Rebuilds the swept-solid sub-group of a Profile Trace assembly
#              from the current edge geometry in its Helpers sub-group.
#              Called by the EntitiesObserver when path edges are modified.
#
# PUBLIC API
#   Na__RegenEngine__RegenerateFromHelpers(parent_group) -> Boolean
#       Deletes the SweptSolid sub-group and rebuilds it using the Helpers
#       edges as the path source. Returns true on success.
#
#   Na__RegenEngine__InProgress? -> Boolean
#       Re-entrancy guard — true while a regeneration operation is running.
#
# DEPENDENCIES
#   Na__DataSerializer  - reads parent payload, finds sub-groups
#   Na__PathAnalysis    - re-orders helpers edges into ordered path
#   Na__ProfileLibrary  - resolves profile_data from stored ProfileKey
#   Na__GeometryBuilders::Na__Geometry__SweepProfileIntoGroup
#       (shared sweep helper, extracted from BuildProfileAlongPath)
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__RegenEngine

    # -------------------------------------------------------------------------
    # REGION | Module State
    # -------------------------------------------------------------------------

        @na_in_progress = false

        def self.Na__RegenEngine__InProgress?
            @na_in_progress == true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -------------------------------------------------------------------------

        def self.Na__RegenEngine__RegenerateFromHelpers(parent_group)
            return false unless Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)
            return false if @na_in_progress

            payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(parent_group)
            return false unless payload

            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return false unless helpers_group

            path_result = self.Na__RegenEngine__BuildPathFromHelpers(helpers_group)
            unless path_result[:isValid]
                Na__DebugTools.Na__Debug__Warn("RegenEngine: path rebuild failed: #{path_result[:reason]}")
                return false
            end

            profile_data = self.Na__RegenEngine__ResolveProfileData(payload)
            unless profile_data
                Na__DebugTools.Na__Debug__Warn("RegenEngine: profile '#{payload['ProfileKey']}' not found.")
                return false
            end

            model = Sketchup.active_model
            return false unless model

            self.Na__RegenEngine__ExecuteRebuild(
                model:        model,
                parent_group: parent_group,
                profile_data: profile_data,
                path_result:  path_result,
                payload:      payload
            )
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenEngine: unexpected error: #{error.message}")
            @na_in_progress = false
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Path Extraction from Helpers
    # -------------------------------------------------------------------------

        def self.Na__RegenEngine__BuildPathFromHelpers(helpers_group)
            edges = helpers_group.entities.grep(Sketchup::Edge).select(&:valid?)
            if edges.empty?
                return { isValid: false, reason: 'Helpers sub-group contains no edges.' }
            end
            Na__PathAnalysis.Na__Path__BuildSegments(edges)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Profile Resolution
    # -------------------------------------------------------------------------

        def self.Na__RegenEngine__ResolveProfileData(payload)
            profile_key = payload['ProfileKey'].to_s
            return nil if profile_key.empty?
            profile_data = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            return nil unless profile_data
            return nil unless Na__ProfilePlacementEngine.Na__Engine__UnifiedProfileRecord?(profile_data)
            profile_data.merge('profileKey' => profile_key)
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Rebuild Operation
    # -------------------------------------------------------------------------

        def self.Na__RegenEngine__ExecuteRebuild(model:, parent_group:, profile_data:, path_result:, payload:)
            @na_in_progress = true

            ordered_points = Array(path_result[:orderedPoints])
            is_closed_loop = path_result[:isClosedLoop] == true
            rotation_step  = payload['RotationStep'].to_i
            toggle_states  = payload['ToggleStates'].is_a?(Hash) ? payload['ToggleStates'] : {}
            start_point    = ordered_points.first

            resolved_path_data = {
                ordered_points: ordered_points,
                ordered_edges:  [],
                is_closed_loop: is_closed_loop
            }

            frame_transform = Na__GeometryBuilders.Na__Geometry__BuildPathFrame(start_point, resolved_path_data)
            unless frame_transform
                Na__DebugTools.Na__Debug__Warn("RegenEngine: path frame could not be built.")
                @na_in_progress = false
                return false
            end

            model.start_operation('Na__ProfilePathTracer__Regenerate', true, false, true)

            old_solid = Na__DataSerializer.Na__DataSerializer__FindSolidSubGroup(parent_group)
            parent_group.entities.erase_entities([old_solid]) if old_solid && old_solid.valid?

            new_solid_group = parent_group.entities.add_group
            new_solid_group.name = Na__DataSerializer::NA_SOLID_GROUP_NAME

            swept = Na__GeometryBuilders.Na__Geometry__SweepProfileIntoGroup(
                target_entities: new_solid_group.entities,
                model:           model,
                profile_data:    profile_data,
                ordered_points:  ordered_points,
                is_closed_loop:  is_closed_loop,
                frame_transform: frame_transform,
                rotation_step:   rotation_step,
                toggle_states:   toggle_states,
                resolved_path_data: resolved_path_data
            )

            unless swept['isSwept']
                model.abort_operation
                Na__DebugTools.Na__Debug__Warn("RegenEngine: sweep failed: #{swept['reason']}")
                @na_in_progress = false
                return false
            end

            model.commit_operation
            @na_in_progress = false
            true
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("RegenEngine: rebuild operation failed: #{error.message}")
            @na_in_progress = false
            false
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
