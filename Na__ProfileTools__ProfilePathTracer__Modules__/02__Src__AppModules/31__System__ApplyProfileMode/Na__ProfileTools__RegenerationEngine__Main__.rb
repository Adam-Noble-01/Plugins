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
# MULTI-RUN BEHAVIOUR
#   The Helpers linework is an editable proxy, so the user is expected to keep
#   drawing into it. Na__Path__BuildChains splits whatever is in the group into
#   maximal non-branching chains plus closed loops, and every chain is swept —
#   a new disconnected run or a spur off an existing one extends the moulding
#   instead of failing the rebuild.
#
#   1 chain  -> geometry sits directly in Na__ProfileTrace__SweptSolid.
#   N chains -> one Na__ProfileTrace__Run__NN sub-group per chain, so the
#               per-run seam cleanup cannot erase a neighbouring run's faces.
#
#   Chain direction is anchored to the assembly's stored StartPoint, so adding
#   segments at either end will not flip the profile around.
#
# PUBLIC API
#   Na__RegenEngine__RegenerateFromHelpers(parent_group) -> Boolean
#       Deletes the SweptSolid sub-group and rebuilds it using the Helpers
#       edges as the path source. Returns true if at least one run swept.
#
#   Na__RegenEngine__InProgress? -> Boolean
#       Re-entrancy guard — true while a regeneration operation is running.
#
# DEPENDENCIES
#   Na__DataSerializer  - reads parent payload, finds sub-groups
#   Na__PathAnalysis    - splits helpers edges into ordered chains
#   Na__ProfileLibrary  - resolves profile_data from stored ProfileKey
#   Na__TagApplier      - repaints newly drawn helper edges
#   Na__GeometryBuilders::Na__Geometry__SweepProfileIntoGroup
#       (shared sweep helper, extracted from BuildProfileAlongPath)
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__RegenEngine

    # -------------------------------------------------------------------------
    # REGION | Module State
    # -------------------------------------------------------------------------

        NA_POINT_MERGE_TOLERANCE = 0.001
        NA_RUN_GROUP_PREFIX      = 'Na__ProfileTrace__Run__'.freeze

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

            # The remembered start point anchors chain direction, so extending the
            # linework at either end does not flip the profile round.
            path_result = self.Na__RegenEngine__BuildPathFromHelpers(helpers_group, payload['StartPoint'])
            unless path_result[:isValid]
                self.Na__RegenEngine__ReportFailure("path rebuild failed — #{path_result[:reason]}")
                return false
            end

            profile_data = self.Na__RegenEngine__ResolveProfileData(payload)
            unless profile_data
                self.Na__RegenEngine__ReportFailure("profile '#{payload['ProfileKey']}' not found in the library.")
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
            self.Na__RegenEngine__ReportFailure("unexpected error — #{error.message}")
            @na_in_progress = false
            false
        end

        # Regeneration is triggered by an observer, so a silent `false` looks
        # identical to "the feature is broken". Always surface the reason.
        def self.Na__RegenEngine__ReportFailure(reason)
            Na__DebugTools.Na__Debug__Warn("RegenEngine: #{reason}")
            Sketchup.status_text = "Profile Path Tracer regen skipped: #{reason}"
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Path Extraction from Helpers
    # -------------------------------------------------------------------------

        def self.Na__RegenEngine__BuildPathFromHelpers(helpers_group, anchor_point = nil)
            edges = helpers_group.entities.grep(Sketchup::Edge).select(&:valid?)
            if edges.empty?
                return { isValid: false, reason: 'Helpers sub-group contains no edges.', chains: [] }
            end
            Na__PathAnalysis.Na__Path__BuildChains(edges, anchor_point)
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

            rotation_step = payload['RotationStep'].to_i
            toggle_states = payload['ToggleStates'].is_a?(Hash) ? payload['ToggleStates'] : {}
            origin_offset = payload['OriginOffset']

            # Reverse is baked into the parent group's own transformation at build
            # time, so the rebuild only needs to reproduce the 180 deg profile
            # roll — flipping again here would double-apply it.
            effective_rotation_step =
                payload['ReverseDirection'] == true ? (rotation_step + 2) % 4 : rotation_step

            runs = self.Na__RegenEngine__BuildSweepableRuns(path_result[:chains])
            if runs.empty?
                self.Na__RegenEngine__ReportFailure('helpers linework has no run with two or more distinct points.')
                @na_in_progress = false
                return false
            end

            model.start_operation('Na__ProfilePathTracer__Regenerate', true, false, true)

            old_solid = Na__DataSerializer.Na__DataSerializer__FindSolidSubGroup(parent_group)
            parent_group.entities.erase_entities([old_solid]) if old_solid && old_solid.valid?

            new_solid_group = parent_group.entities.add_group
            new_solid_group.name = Na__DataSerializer::NA_SOLID_GROUP_NAME

            swept_run_count = 0
            first_failure   = nil

            runs.each_with_index do |run, run_index|
                # A single run sweeps straight into the SweptSolid group, keeping the
                # original structure. Multiple runs get one sub-group each so the
                # per-run seam cleanup cannot chew on a neighbouring run's faces.
                run_group = runs.length == 1 ? nil : self.Na__RegenEngine__BuildRunSubGroup(new_solid_group, run_index)
                target_entities = run_group ? run_group.entities : new_solid_group.entities

                swept = self.Na__RegenEngine__SweepRun(
                    target_entities: target_entities,
                    model:           model,
                    profile_data:    profile_data,
                    run:             run,
                    rotation_step:   effective_rotation_step,
                    toggle_states:   toggle_states,
                    origin_offset:   origin_offset
                )

                if swept['isSwept']
                    swept_run_count += 1
                else
                    first_failure ||= swept['reason']
                    Na__DebugTools.Na__Debug__Warn("RegenEngine: run #{run_index + 1} skipped — #{swept['reason']}")
                    # Drop the empty shell so failed runs do not accumulate as
                    # hollow Run__NN groups over repeated rebuilds.
                    new_solid_group.entities.erase_entities([run_group]) if run_group && run_group.valid?
                end
            end

            if swept_run_count.zero?
                model.abort_operation
                self.Na__RegenEngine__ReportFailure("no run could be swept — #{first_failure}")
                @na_in_progress = false
                return false
            end

            self.Na__RegenEngine__RestyleHelperEdges(model, parent_group)
            Na__DataSerializer.Na__DataSerializer__WritePathPoints(parent_group, runs.first[:ordered_points])

            model.commit_operation
            @na_in_progress = false
            self.Na__RegenEngine__ReportSuccess(parent_group, runs, swept_run_count, first_failure)
            true
        rescue => error
            model.abort_operation rescue nil
            self.Na__RegenEngine__ReportFailure("rebuild operation failed — #{error.message}")
            @na_in_progress = false
            false
        end

        # Sanitises every chain and drops the ones too short to sweep, so one
        # stray two-point stub cannot fail the whole rebuild.
        def self.Na__RegenEngine__BuildSweepableRuns(chains)
            Array(chains).map do |chain|
                is_closed_loop = chain[:is_closed_loop] == true
                ordered_points = self.Na__RegenEngine__SanitizeOrderedPoints(chain[:ordered_points], is_closed_loop)
                next nil if ordered_points.length < 2
                next nil if is_closed_loop && ordered_points.length < 3
                { ordered_points: ordered_points, is_closed_loop: is_closed_loop }
            end.compact
        end

        def self.Na__RegenEngine__BuildRunSubGroup(solid_group, run_index)
            run_group = solid_group.entities.add_group
            run_group.name = format("#{NA_RUN_GROUP_PREFIX}%02d", run_index + 1)
            run_group
        end

        def self.Na__RegenEngine__SweepRun(target_entities:, model:, profile_data:, run:,
                                            rotation_step:, toggle_states:, origin_offset:)
            resolved_path_data = {
                ordered_points: run[:ordered_points],
                ordered_edges:  [],
                is_closed_loop: run[:is_closed_loop]
            }

            frame_transform = Na__GeometryBuilders.Na__Geometry__BuildPathFrame(
                run[:ordered_points].first, resolved_path_data
            )
            return { 'isSwept' => false, 'reason' => 'path frame could not be built' } unless frame_transform

            Na__GeometryBuilders.Na__Geometry__SweepProfileIntoGroup(
                target_entities:    target_entities,
                model:              model,
                profile_data:       profile_data,
                ordered_points:     run[:ordered_points],
                is_closed_loop:     run[:is_closed_loop],
                frame_transform:    frame_transform,
                rotation_step:      rotation_step,
                toggle_states:      toggle_states,
                resolved_path_data: resolved_path_data,
                origin_offset:      origin_offset
            )
        rescue => error
            # Contained here so one bad run cannot abort the whole operation and
            # throw away the runs that already swept cleanly.
            { 'isSwept' => false, 'reason' => error.message }
        end

        # Freshly drawn helper edges carry the default style, so re-apply the
        # helpers material and keep the proxy reading as one piece of linework.
        #
        # Only the edges that are actually wrong get painted. Writing to an edge
        # already carrying the right material would still fire onElementModified
        # on the Helpers observer, and any callback delivered after the operation
        # commits would schedule another regen — a rebuild loop that never settles.
        def self.Na__RegenEngine__RestyleHelperEdges(model, parent_group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return unless helpers_group

            material = Na__TagApplier.Na__TagApplier__ResolveMteMaterial(
                model, Na__GeometryBuilders::NA_HELPERS_MATERIAL_ID
            )
            return unless material

            unpainted_edges = helpers_group.entities.grep(Sketchup::Edge).select do |edge|
                edge.valid? && edge.material != material
            end
            return if unpainted_edges.empty?

            Na__TagApplier.Na__TagApplier__PaintEdgesWithMteMaterial(
                model, unpainted_edges, Na__GeometryBuilders::NA_HELPERS_MATERIAL_ID
            )
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenEngine: helper edge restyle skipped: #{error.message}")
        end

        def self.Na__RegenEngine__ReportSuccess(parent_group, runs, swept_run_count, first_failure)
            point_total = runs.sum { |run| run[:ordered_points].length }
            message = "Profile Path Tracer: rebuilt #{parent_group.name} — " \
                      "#{swept_run_count} of #{runs.length} run(s), #{point_total} helper points."
            message += " Some runs were skipped: #{first_failure}" if swept_run_count < runs.length
            Sketchup.status_text = message
            Na__DebugTools.Na__Debug__Info(message)
        rescue
            nil
        end

        # Na__Path__WalkChainFrom returns a closed run as N+1 points with the last
        # repeating the first. The sweep planner expects N distinct corners, so
        # the duplicate has to go or it emits a zero-length rail segment.
        def self.Na__RegenEngine__SanitizeOrderedPoints(ordered_points, is_closed_loop)
            points = Array(ordered_points).compact
            return [] if points.length < 2

            sanitized = [points.first]
            points[1..-1].each do |point|
                next if sanitized.last.distance(point) <= NA_POINT_MERGE_TOLERANCE
                sanitized << point
            end

            if is_closed_loop &&
               sanitized.length >= 3 &&
               sanitized.first.distance(sanitized.last) <= NA_POINT_MERGE_TOLERANCE
                sanitized = sanitized[0...-1]
            end

            sanitized
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
