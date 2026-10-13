# =============================================================================
# NA PROFILE TOOLS - REGENERATION ENGINE
# =============================================================================
#
# FILE       : Na__ProfileTools__RegenerationEngine__Main__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__RegenEngine
# PURPOSE    : Rebuilds the swept-solid sub-group of a Profile Trace assembly
#              along the path the trace stores (PathRuns), or along the red
#              line of an Edit Path in progress.
#
# WHERE THE PATH COMES FROM (v1.6.16)
#   1. An Edit Path group in the trace (Na__ProfileTrace__EditPath): its edges
#      ARE the edit, so a rebuild while one is open or pending sweeps them,
#      stores them as the new path and erases the group.
#   2. PathRuns, stamped on the assembly by the build and every rebuild.
#   3. LEGACY: a pre-v1.6.16 trace's Helpers linework. The rebuild stores it as
#      PathRuns and erases the Helpers group (Na__DataSerializer__RetireLegacyHelpers).
#   4. LEGACY: PathPoints, for an old trace whose Helpers group is gone.
#
# MULTI-RUN BEHAVIOUR
#   An edit can leave several runs (a second stroke, a spur off the first).
#   Na__Path__BuildChains splits the edges into maximal non-branching chains
#   plus closed loops, and every chain is swept.
#
#   1 run  -> geometry sits directly in Na__ProfileTrace__SweptSolid.
#   N runs -> one Na__ProfileTrace__Run__NN sub-group per run, so the per-run
#             seam cleanup cannot erase a neighbouring run's faces.
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
# COORDINATE SPACE (v1.6.12)
#   A rebuild reads its path and writes the new solid in PARENT space, the
#   assembly's own axes, which is what the API reports only while the assembly
#   is closed. A rebuild run from inside the trace (Regenerate Now while in
#   Edit Path, a swap) therefore steps out first, as clicking outside would.
#   Stored points go into the sweep as they are, with no transformation, so
#   rebuilding again and again cannot move a trace by even a rounding error.
#
# UNDO (v1.6.16)
#   The rebuild is a transparent operation: it joins the operation before it
#   (the last path edit, a swap's dictionary write), so one undo takes both
#   back. A transparent operation must never be aborted (that would abort the
#   operation it joins), so the new solid is swept first, and the old one is
#   erased only once the new one stands. A rebuild that sweeps nothing erases
#   its empty group, commits, and leaves the trace exactly as it was.
#
# PUBLIC API
#   Na__RegenEngine__RegenerateTrace(parent_group) -> Boolean
#   Na__RegenEngine__RegenerateFromHelpers(parent_group) -> Boolean  (old name)
#   Na__RegenEngine__StoredPathRuns(parent_group, payload) -> Hash
#   Na__RegenEngine__RunsFromEdges(edges, transform, anchor_point) -> Hash
#   Na__RegenEngine__InProgress? -> Boolean
#   Na__RegenEngine__LastFailure -> String
#
# DEPENDENCIES
#   Na__DataSerializer  - reads the payload and path, finds sub-groups
#   Na__PathAnalysis    - splits edges into ordered chains
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

        NA_POINT_MERGE_TOLERANCE = 0.001
        NA_RUN_GROUP_PREFIX      = 'Na__ProfileTrace__Run__'.freeze

        @na_in_progress = false
        @na_last_failure = ''

        def self.Na__RegenEngine__InProgress?
            @na_in_progress == true
        end

        # The reason the last rebuild did not happen, for callers that word
        # their own message (an Edit Path that could not be swept).
        def self.Na__RegenEngine__LastFailure
            @na_last_failure.to_s
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -------------------------------------------------------------------------

        def self.Na__RegenEngine__RegenerateTrace(parent_group)
            return false unless Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)
            return false if @na_in_progress
            @na_last_failure = ''

            payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(parent_group)
            return false unless payload

            unless self.Na__RegenEngine__LeaveAssemblyContext(parent_group)
                self.Na__RegenEngine__ReportFailure('the trace is open for editing and could not be closed — click outside it, then regenerate.')
                return false
            end

            path_result = self.Na__RegenEngine__ResolveRebuildPath(parent_group, payload)
            unless path_result[:isValid]
                self.Na__RegenEngine__ReportFailure("path rebuild failed — #{path_result[:reason]}")
                return false
            end

            profile_data = self.Na__RegenEngine__ResolveProfileData(payload, parent_group)
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
                runs:         path_result[:runs],
                payload:      payload,
                source:       path_result[:source]
            )
        rescue => error
            self.Na__RegenEngine__ReportFailure("unexpected error — #{error.message}")
            @na_in_progress = false
            false
        end

        # The name every caller used before the path became data. Kept so a
        # caller that still uses it (or a stale reload) rebuilds the same way.
        def self.Na__RegenEngine__RegenerateFromHelpers(parent_group)
            self.Na__RegenEngine__RegenerateTrace(parent_group)
        end

        # Regeneration is triggered by an observer, so a silent `false` looks
        # identical to "the feature is broken". Always surface the reason.
        def self.Na__RegenEngine__ReportFailure(reason)
            @na_last_failure = reason.to_s
            Na__DebugTools.Na__Debug__Warn("RegenEngine: #{reason}")
            Sketchup.status_text = "Profile Path Tracer regen skipped: #{reason}"
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Edit Context
    # -------------------------------------------------------------------------

        # A rebuild reads its path and sweeps into a fresh sub-group: parent
        # space in, parent space out. That holds only while the assembly is
        # CLOSED. Opened (Regenerate Now or a swap run from inside Edit Path),
        # everything in it reports world space: "in the active drawing context
        # and all its parent coordinate systems all coordinates are global".
        # The Edit Path line would be read as parent space while it reported
        # world, and the rebuild could erase the SweptSolid group the user was
        # standing in. The change sweep already waits for the user to step out
        # (Na__RegenSweep__InsideEditContext?); a manual rebuild steps out
        # itself, to the context the assembly sits in, as clicking outside it
        # would. A no-op whenever the assembly is not open.
        #
        # Runs before the rebuild opens its operation. SketchUp wraps a path
        # change in transparent operations of its own, since entities cannot be
        # modified in the same operation as the active entities change.
        def self.Na__RegenEngine__LeaveAssemblyContext(parent_group)
            model = Sketchup.active_model
            return false unless model

            active_path    = Array(model.active_path)
            assembly_index = active_path.index { |instance| instance == parent_group }
            return true unless assembly_index

            model.active_path = active_path[0...assembly_index]
            true
        rescue ArgumentError => error
            Na__DebugTools.Na__Debug__Warn("RegenEngine: could not leave the assembly: #{error.message}")
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - The Path to Rebuild Along
    # -------------------------------------------------------------------------

        # An Edit Path line in the trace is the user's edit, open or pending
        # (an undo can bring one back), so a rebuild takes it along rather than
        # rebuilding past it. An emptied line is no path: the stored one is
        # used, and the rebuild erases the empty group.
        def self.Na__RegenEngine__ResolveRebuildPath(parent_group, payload)
            edit_group = Na__DataSerializer.Na__DataSerializer__FindEditPathGroup(parent_group)
            if edit_group
                edges = edit_group.entities.grep(Sketchup::Edge).select(&:valid?)
                unless edges.empty?
                    result = self.Na__RegenEngine__RunsFromEdges(edges, edit_group.transformation, payload['StartPoint'])
                    return result.merge(source: :edit)
                end
            end
            self.Na__RegenEngine__StoredPathRuns(parent_group, payload)
        end

        # The path the trace carries: PathRuns, else (legacy) its Helpers
        # linework, else (legacy, Helpers gone) its primary PathPoints run.
        # { isValid:, runs:, source:, reason: }
        def self.Na__RegenEngine__StoredPathRuns(parent_group, payload = nil)
            payload ||= Na__DataSerializer.Na__DataSerializer__ReadParentPayload(parent_group) || {}

            stored = Na__DataSerializer.Na__DataSerializer__ReadPathRuns(parent_group)
            if stored
                runs = self.Na__RegenEngine__BuildSweepableRuns(stored)
                return { isValid: true, runs: runs, source: :stored, reason: nil } unless runs.empty?
            end

            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            if helpers_group
                edges = helpers_group.entities.grep(Sketchup::Edge).select(&:valid?)
                unless edges.empty?
                    result = self.Na__RegenEngine__RunsFromEdges(edges, helpers_group.transformation, payload['StartPoint'])
                    return result.merge(source: :legacy) if result[:isValid]
                end
            end

            primary = self.Na__RegenEngine__BuildSweepableRuns(
                [{ ordered_points: Array(payload['PathPoints']), is_closed_loop: payload['IsClosedLoop'] == true }]
            )
            return { isValid: true, runs: primary, source: :primary, reason: nil } unless primary.empty?

            { isValid: false, runs: [], source: nil, reason: 'the trace carries no path.' }
        rescue => error
            { isValid: false, runs: [], source: nil, reason: "its path could not be read: #{error.message}" }
        end

        # Edges in one group -> sweepable runs in PARENT space. Positions are
        # local to the group (closed, which every caller guarantees); the
        # group's own transformation carries them into the assembly's space, so
        # an edit group or Helpers group moved as a whole still lands right.
        # The anchor lives in parent space, so it maps into local space first.
        # With the identity (the usual case) both mappings are exact.
        def self.Na__RegenEngine__RunsFromEdges(edges, transform, anchor_point = nil)
            local_anchor = self.Na__RegenEngine__MapAnchorToLocal(anchor_point, transform)
            path_result  = Na__PathAnalysis.Na__Path__BuildChains(edges, local_anchor)
            return { isValid: false, runs: [], reason: path_result[:reason] } unless path_result[:isValid]

            chains = path_result[:chains].map do |chain|
                { ordered_points: chain[:ordered_points].map { |point| point.transform(transform) }, is_closed_loop: chain[:is_closed_loop] }
            end
            runs = self.Na__RegenEngine__BuildSweepableRuns(chains)
            return { isValid: false, runs: [], reason: 'no run has two or more distinct points.' } if runs.empty?
            { isValid: true, runs: runs, reason: nil }
        rescue => error
            { isValid: false, runs: [], reason: "path scan failed: #{error.message}" }
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

        # A trace carrying its own profile (ProfileSource 'local', written by the
        # Draw Profile tab, v1.6.14) sweeps that; one whose local profile no
        # longer parses falls back to the library key it was drawn from.
        def self.Na__RegenEngine__ResolveProfileData(payload, parent_group = nil)
            if parent_group && payload['ProfileSource'] == 'local'
                local_record = Na__DataSerializer.Na__DataSerializer__LocalProfileRecord(parent_group)
                return local_record if local_record && Na__ProfilePlacementEngine.Na__Engine__UnifiedProfileRecord?(local_record)
                Na__DebugTools.Na__Debug__Warn("RegenEngine: local profile unreadable on #{payload['ProfileTraceId']}; using '#{payload['ProfileKey']}'.")
            end

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

        def self.Na__RegenEngine__ExecuteRebuild(model:, parent_group:, profile_data:, runs:, payload:, source: :stored)
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

            runs = Array(runs)
            if runs.empty?
                self.Na__RegenEngine__ReportFailure('the path has no run with two or more distinct points.')
                @na_in_progress = false
                return false
            end

            path_offsets   = { 'start' => payload['StartOffset'].to_f, 'end' => payload['EndOffset'].to_f }
            free_end_flags = self.Na__RegenEngine__FreeEndFlags(runs)

            new_solid_group = nil
            old_erased      = false
            model.start_operation('Na__ProfilePathTracer__Regenerate', true, false, true)

            # A copy of a trace shares its definition until something makes it
            # unique; rebuilding a shared one would rebuild every copy, only one
            # of which carries the new settings.
            self.Na__RegenEngine__EnsureUniqueAssembly(parent_group)

            old_solids = parent_group.entities.grep(Sketchup::Group).select do |child|
                child.valid? && child.name == Na__DataSerializer::NA_SOLID_GROUP_NAME
            end

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
                # Never abort: this operation is transparent, and aborting it
                # would abort the operation it joins. The old solid was never
                # touched, so taking the empty group away leaves the trace as
                # it was.
                parent_group.entities.erase_entities([new_solid_group]) if new_solid_group.valid?
                model.commit_operation
                self.Na__RegenEngine__ReportFailure("no run could be swept — #{first_failure}")
                @na_in_progress = false
                return false
            end

            parent_group.entities.erase_entities(old_solids.select(&:valid?)) unless old_solids.empty?
            old_erased = true

            # The path the new solid follows becomes the trace's path, and with
            # it gone anything that held the path as geometry: an Edit Path line
            # (now applied) and, on a pre-v1.6.16 trace, the Helpers linework.
            Na__DataSerializer.Na__DataSerializer__WritePathRuns(parent_group, runs)
            edit_groups = Na__DataSerializer.Na__DataSerializer__FindEditPathGroups(parent_group)
            parent_group.entities.erase_entities(edit_groups) unless edit_groups.empty?
            Na__DataSerializer.Na__DataSerializer__RetireLegacyHelpers(parent_group)

            model.commit_operation
            @na_in_progress = false
            self.Na__RegenEngine__ReportSuccess(parent_group, runs, swept_run_count, first_failure, source)
            true
        rescue => error
            # The operation is transparent, so it is committed, not aborted. A
            # half-built solid goes, unless the old one is already gone: then
            # the new solid is the only one the trace has.
            begin
                if new_solid_group && new_solid_group.valid? && !old_erased
                    parent_group.entities.erase_entities([new_solid_group])
                end
            rescue
                nil
            end
            model.commit_operation rescue nil
            self.Na__RegenEngine__ReportFailure("rebuild operation failed — #{error.message}")
            @na_in_progress = false
            false
        end

        def self.Na__RegenEngine__EnsureUniqueAssembly(parent_group)
            return unless parent_group.respond_to?(:make_unique) && parent_group.respond_to?(:definition)
            return unless parent_group.definition.instances.length > 1
            parent_group.make_unique
        rescue => error
            Na__DebugTools.Na__Debug__Warn("RegenEngine: make unique skipped: #{error.message}")
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
            # Same order as the first build: the run as drawn stays the stored
            # path, the sweep follows the run with its ends offset.
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

        def self.Na__RegenEngine__ReportSuccess(parent_group, runs, swept_run_count, first_failure, source = :stored)
            point_total = runs.sum { |run| run[:ordered_points].length }
            along = source == :edit ? 'along its edited path' : 'along its path'
            message = "Profile Path Tracer: rebuilt #{parent_group.name} #{along} — " \
                      "#{swept_run_count} of #{runs.length} run(s), #{point_total} path points."
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
