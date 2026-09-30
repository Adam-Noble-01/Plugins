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
# PATH OFFSETS (v1.6.11)
#   The stored StartOffset / EndOffset overshoot (or trim) the sweep past the
#   ends of each open run — StartOffset at the end nearest StartPoint, which is
#   the end the build started from. They are applied at FREE ends only: an end
#   that meets another run or a loop is a junction, and pushing the solid past
#   it would bury one moulding inside its neighbour.
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

            # Edge positions are local to the Helpers group. The group normally
            # carries an identity transform, but if the user has moved or scaled
            # the Helpers instance itself, that transform must be baked into the
            # path or the rebuild lands at the pre-move position. The stored
            # anchor lives in parent space, so it maps into local space first.
            transform    = helpers_group.transformation
            local_anchor = self.Na__RegenEngine__MapAnchorToLocal(anchor_point, transform)

            path_result = Na__PathAnalysis.Na__Path__BuildChains(edges, local_anchor)
            return path_result unless path_result[:isValid]

            path_result[:chains].each do |chain|
                chain[:ordered_points] = chain[:ordered_points].map { |point| point.transform(transform) }
            end
            path_result
        end

        def self.Na__RegenEngine__MapAnchorToLocal(anchor_point, transform)
            return nil unless anchor_point
            anchor_point.transform(transform.inverse)
        rescue
            anchor_point
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

            # Assemblies stamped before dictionary schema 1.2.0 were swept with
            # the legacy right-handed path frame. Rebuilding those with the
            # WYSIWYG frame would silently mirror geometry that already stands
            # in the model, so the stored schema picks the frame.
            legacy_frame = self.Na__RegenEngine__LegacyFrameSchema?(payload)

            runs = self.Na__RegenEngine__BuildSweepableRuns(path_result[:chains])
            if runs.empty?
                self.Na__RegenEngine__ReportFailure('helpers linework has no run with two or more distinct points.')
                @na_in_progress = false
                return false
            end

            path_offsets   = { 'start' => payload['StartOffset'].to_f, 'end' => payload['EndOffset'].to_f }
            free_end_flags = self.Na__RegenEngine__FreeEndFlags(runs)

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
                    origin_offset:   origin_offset,
                    legacy_frame:    legacy_frame,
                    path_offsets:    self.Na__RegenEngine__RunPathOffsets(run, path_offsets, free_end_flags[run_index])
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
            self.Na__RegenEngine__StampCurrentFingerprint(parent_group)

            model.commit_operation
            @na_in_progress = false
            self.Na__RegenEngine__ReattachHelpersObserver(parent_group)
            self.Na__RegenEngine__ReportSuccess(parent_group, runs, swept_run_count, first_failure)
            true
        rescue => error
            model.abort_operation rescue nil
            self.Na__RegenEngine__ReportFailure("rebuild operation failed — #{error.message}")
            @na_in_progress = false
            false
        end

        NA_WYSIWYG_FRAME_SCHEMA = '1.2.0'.freeze

        # True when the assembly predates the WYSIWYG path frame (dictionary
        # schema 1.2.0) and must therefore be rebuilt with the legacy
        # right-handed frame it was originally swept with. Unparseable or
        # missing versions count as legacy — mirroring standing geometry is the
        # failure mode to avoid.
        def self.Na__RegenEngine__LegacyFrameSchema?(payload)
            version_text = (payload.is_a?(Hash) ? payload['SchemaVersion'] : nil).to_s.strip
            return true if version_text.empty?
            Gem::Version.new(version_text) < Gem::Version.new(NA_WYSIWYG_FRAME_SCHEMA)
        rescue
            true
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

        # [head_free, tail_free] per run. An end is free when no other run
        # touches it: every open run's two ends and every vertex of a loop go
        # into one pool, and an end seen there only once (itself) is free. A run
        # whose two ends meet each other counts both twice, so it is not free
        # either. Loops have no ends: [false, false].
        def self.Na__RegenEngine__FreeEndFlags(runs)
            contact_points = []
            runs.each do |run|
                points = Array(run[:ordered_points])
                if run[:is_closed_loop]
                    contact_points.concat(points)
                else
                    contact_points << points.first << points.last
                end
            end

            runs.map do |run|
                next [false, false] if run[:is_closed_loop]
                points = Array(run[:ordered_points])
                [
                    contact_points.count { |point| point == points.first } == 1,
                    contact_points.count { |point| point == points.last } == 1
                ]
            end
        end

        # Runs arrive oriented from the end nearest the stored StartPoint (see
        # Na__Path__OrientChain), which is the traversal start the offsets were
        # stamped against — so 'start' belongs on the run's head.
        def self.Na__RegenEngine__RunPathOffsets(run, path_offsets, free_end_flags)
            return nil if run[:is_closed_loop]
            head_free, tail_free = Array(free_end_flags)
            Na__GeometryBuilders.Na__Geometry__NormalisePathOffsets(
                'start' => head_free ? path_offsets['start'] : 0.0,
                'end'   => tail_free ? path_offsets['end']   : 0.0
            )
        end

        def self.Na__RegenEngine__BuildRunSubGroup(solid_group, run_index)
            run_group = solid_group.entities.add_group
            run_group.name = format("#{NA_RUN_GROUP_PREFIX}%02d", run_index + 1)
            run_group
        end

        def self.Na__RegenEngine__SweepRun(target_entities:, model:, profile_data:, run:,
                                            rotation_step:, toggle_states:, origin_offset:,
                                            legacy_frame: false, path_offsets: nil)
            # Same order as the first build: the run as drawn stays the Helpers
            # linework, the sweep follows the run with its ends offset.
            offset_result = Na__GeometryBuilders.Na__Geometry__ApplyPathOffsets(
                run[:ordered_points], run[:is_closed_loop], path_offsets
            )
            return { 'isSwept' => false, 'reason' => offset_result[:reason] } unless offset_result[:isValid]
            sweep_points = offset_result[:ordered_points]

            resolved_path_data = {
                ordered_points: sweep_points,
                ordered_edges:  [],
                is_closed_loop: run[:is_closed_loop]
            }

            frame_transform = Na__GeometryBuilders.Na__Geometry__BuildPathFrame(
                sweep_points.first, resolved_path_data, legacy_frame
            )
            return { 'isSwept' => false, 'reason' => 'path frame could not be built' } unless frame_transform

            Na__GeometryBuilders.Na__Geometry__SweepProfileIntoGroup(
                target_entities:    target_entities,
                model:              model,
                profile_data:       profile_data,
                ordered_points:     sweep_points,
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

        # Written inside the rebuild operation so an undo reverts the stored
        # fingerprint together with the geometry it describes — the RegenSweep
        # comparison then still holds and cannot fire a phantom rebuild.
        def self.Na__RegenEngine__StampCurrentFingerprint(parent_group)
            return unless defined?(Na__RegenSweep)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return unless helpers_group
            fingerprint = Na__RegenSweep.Na__RegenSweep__ComputeFingerprint(helpers_group)
            Na__DataSerializer.Na__DataSerializer__WriteHelpersFingerprint(parent_group, fingerprint) if fingerprint
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenEngine: fingerprint stamp skipped: #{error.message}")
        end

        # A user edit can silently make a copied assembly unique, swapping the
        # Helpers definition (and Entities collection) underneath the attached
        # observer. Re-resolve and re-attach after every rebuild.
        def self.Na__RegenEngine__ReattachHelpersObserver(parent_group)
            return unless defined?(Na__ObserverRegistry)
            return unless Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return unless helpers_group
            Na__ObserverRegistry.Na__ObserverRegistry__AttachIfMissing(helpers_group)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenEngine: observer reattach skipped: #{error.message}")
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
