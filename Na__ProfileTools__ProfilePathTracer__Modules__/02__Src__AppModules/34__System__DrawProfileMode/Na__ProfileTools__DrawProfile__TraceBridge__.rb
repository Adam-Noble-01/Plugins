# =============================================================================
# NA PROFILE TOOLS - DRAW PROFILE MODE - TRACE BRIDGE
# =============================================================================
#
# FILE       : Na__ProfileTools__DrawProfile__TraceBridge__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__DrawProfile__TraceBridge
# PURPOSE    : Connects the Draw Profile editor to the model: reads the current
#              selection as a starting drawing, and puts a drawn profile onto
#              the Profile Trace it was opened from.
#
# READING THE SELECTION (Na__TraceBridge__ResolveSelection)
#   1. A Profile Trace, or any part of one: its library profile becomes the
#      base drawing and the trace is bound, so Update Trace knows where the
#      edit goes. Several selected traces are bound together.
#   2. Otherwise a face: its outer boundary, flattened into the face's own
#      plane (the exporter's frame, world up as profile Z) with the bounding
#      box's lower-left corner as the datum. Edges that SketchUp holds as an
#      arc come through as arcs.
#   3. Otherwise loose edges: flattened the same way, as straight segments.
#
# UPDATING A TRACE THROUGH THE LIBRARY (Na__TraceBridge__SaveAndApply)
#   The drawing is written to the library first (Na__DrawProfile__ProfileWriter)
#   and the bound traces moved onto that key through the swap engine, which
#   already does the rebuild, the undo step and the roll back on failure.
#   Saving over the profile a trace already uses rebuilds it with the new
#   shape; other traces on that key are rebuilt only when asked.
#
# UPDATING THIS TRACE ONLY (Na__TraceBridge__ApplyLocal, v1.6.14)
#   The drawing goes onto the bound trace itself, as a LOCAL profile in its
#   dictionary (Na__DataSerializer__WriteLocalProfile); the library is not
#   touched and no other trace changes. The rebuild sweeps the local profile
#   from then on, path edits included, until a library profile is swapped
#   onto the trace or Revert to Library (Na__TraceBridge__RevertLocal) clears
#   it. The Draw tab's Live mode calls this on every change, as Element
#   Assembly Studio Pro's Live Mode does: one undo step per update, and a
#   failed rebuild puts the previous profile back.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__DrawProfile__TraceBridge

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_MM_PER_INCH     = 25.4
        NA_MAX_EDGES_READ  = 5000

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Read the Selection
    # -------------------------------------------------------------------------

        def self.Na__TraceBridge__ResolveSelection(model)
            return self.Na__TraceBridge__Failure('No active model.') unless model
            return self.Na__TraceBridge__Failure('Nothing is selected. Select a Profile Trace, or a face to draw over.') if model.selection.empty?

            # @delegate: ../31__System__ApplyProfileMode/Na__ProfileTools__ProfileSwapEngine__Main__
            traces = Na__SwapEngine.Na__SwapEngine__ResolveSelectedTraces(model)
            return self.Na__TraceBridge__TracePayload(traces) unless traces.empty?

            self.Na__TraceBridge__GeometryPayload(model)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Draw Profile: reading the selection failed.', error)
            self.Na__TraceBridge__Failure("The selection could not be read: #{error.message}")
        end

        def self.Na__TraceBridge__CountTracesUsing(profile_key)
            key = profile_key.to_s
            return 0 if key.empty?
            model = Sketchup.active_model
            return 0 unless model
            self.Na__TraceBridge__TracesUsing(model, key).length
        rescue
            0
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - Save, Then Update the Bound Traces
    # -------------------------------------------------------------------------

        # params: everything the profile writer takes, plus
        #   'saveMode'      => 'new' | 'overwrite'
        #   'traceIds'      => [...]   the bound traces; empty for a plain save
        #   'originOffset'  => {...} | nil   only sent when the datum must be
        #                      set explicitly (a different key): present-but-nil
        #                      clears it, absent keeps whatever the trace has
        #   'rebuildOthers' => true to rebuild every other trace on the key
        def self.Na__TraceBridge__SaveAndApply(params)
            params    = {} unless params.is_a?(Hash)
            save_mode = params['saveMode'].to_s == 'overwrite' ? 'overwrite' : 'new'

            save_result = if save_mode == 'overwrite'
                              Na__DrawProfile__ProfileWriter.Na__ProfileWriter__SaveOverwrite(params)
                          else
                              Na__DrawProfile__ProfileWriter.Na__ProfileWriter__SaveNew(params)
                          end
            return save_result.merge('isApplied' => false, 'saveMode' => save_mode) unless save_result['isSaved']

            trace_ids = Array(params['traceIds']).map(&:to_s).reject(&:empty?).uniq
            if trace_ids.empty?
                return save_result.merge(
                    'isApplied' => false,
                    'saveMode'  => save_mode,
                    'otherTraceCount' => self.Na__TraceBridge__CountTracesUsing(save_result['profileKey'])
                )
            end

            swap_request = { 'traceIds' => trace_ids, 'profileKey' => save_result['profileKey'] }
            swap_request['originOffset'] = params['originOffset'] if params.key?('originOffset')

            # @delegate: ../31__System__ApplyProfileMode/Na__ProfileTools__ProfileSwapEngine__Main__
            swap_result = Na__SwapEngine.Na__SwapEngine__ApplySwap(swap_request)

            others = { 'rebuilt' => 0, 'failed' => 0 }
            if save_mode == 'overwrite' && params['rebuildOthers'] == true
                others = self.Na__TraceBridge__RebuildOtherTraces(save_result['profileKey'], trace_ids)
            end

            save_result.merge(
                'isApplied'      => swap_result['isSwapped'] == true,
                'saveMode'       => save_mode,
                'bind'           => swap_result['bind'],
                'swapStatus'     => swap_result['statusMessage'].to_s,
                'othersRebuilt'  => others['rebuilt'],
                'othersFailed'   => others['failed'],
                'otherTraceCount' => self.Na__TraceBridge__CountTracesUsing(save_result['profileKey']) - trace_ids.length,
                'statusMessage'  => self.Na__TraceBridge__ApplyStatus(save_result, swap_result, others)
            )
        rescue => error
            Na__DebugTools.Na__Debug__Error('Draw Profile: save and apply failed.', error)
            {
                'isSaved'       => false,
                'isApplied'     => false,
                'reason'        => error.message,
                'statusMessage' => "Update failed: #{error.message}"
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public - This Trace Only (local profiles)
    # -------------------------------------------------------------------------

        # params: 'traceIds', 'geometry' (the writer's payload), 'displayName',
        # 'live' (true from Live mode: quieter status).
        def self.Na__TraceBridge__ApplyLocal(params)
            params    = {} unless params.is_a?(Hash)
            trace_ids = Array(params['traceIds']).map(&:to_s).reject(&:empty?).uniq
            return self.Na__TraceBridge__LocalFailure('No trace is bound. Select one in the model and press Edit Profile first.') if trace_ids.empty?

            model = Sketchup.active_model
            return self.Na__TraceBridge__LocalFailure('No active model.') unless model

            primary = Na__SwapEngine.Na__SwapEngine__ResolveTraceById(trace_ids.first)
            return self.Na__TraceBridge__LocalFailure("#{trace_ids.first} is no longer in the model.") unless primary

            local = Na__DrawProfile__ProfileWriter.Na__ProfileWriter__BuildLocalAssetData(
                params['geometry'], self.Na__TraceBridge__StyleSource(primary), params['displayName']
            )
            return self.Na__TraceBridge__LocalFailure(local[:reason]) unless local[:isValid]

            name     = local[:data]['Na__Asset__Metadata']['Na__Asset__Name']
            outcomes = trace_ids.map { |trace_id| self.Na__TraceBridge__ApplyLocalToOne(model, trace_id, local[:data], name) }
            applied  = outcomes.count { |outcome| outcome[:ok] }
            failures = outcomes.reject { |outcome| outcome[:ok] }.map { |outcome| outcome[:reason] }

            label  = trace_ids.length == 1 ? trace_ids.first : "#{applied} of #{trace_ids.length} traces"
            status = if applied.zero?
                         "Not updated: #{failures.uniq.join('; ')}"
                     elsif failures.empty?
                         "#{label} rebuilt with its own profile (#{local[:counts][:vertices]} vertices). The library is unchanged."
                     else
                         "#{label} rebuilt with their own profile. Not updated: #{failures.uniq.join('; ')}"
                     end
            Sketchup.status_text = "Profile Path Tracer: #{status}" unless params['live'] == true && failures.empty?

            {
                'isApplied'     => applied > 0,
                'appliedCount'  => applied,
                'failures'      => failures,
                'displayName'   => name,
                'bind'          => Na__SwapEngine.Na__SwapEngine__BuildBindPayloadForIds(trace_ids),
                'statusMessage' => status
            }
        rescue => error
            Na__DebugTools.Na__Debug__Error('Draw Profile: local update failed.', error)
            self.Na__TraceBridge__LocalFailure("Update failed: #{error.message}")
        end

        # Back to the library profile the trace was drawn from.
        def self.Na__TraceBridge__RevertLocal(params)
            params    = {} unless params.is_a?(Hash)
            trace_ids = Array(params['traceIds']).map(&:to_s).reject(&:empty?).uniq
            return self.Na__TraceBridge__LocalFailure('No trace is bound.') if trace_ids.empty?
            model = Sketchup.active_model
            return self.Na__TraceBridge__LocalFailure('No active model.') unless model

            reverted = 0
            failures = []
            trace_ids.each do |trace_id|
                group = Na__SwapEngine.Na__SwapEngine__ResolveTraceById(trace_id)
                next failures << "#{trace_id} is no longer in the model" unless group
                previous_local = Na__DataSerializer.Na__DataSerializer__ReadLocalProfileRaw(group)
                next unless previous_local

                model.start_operation('Na__ProfilePathTracer__RevertLocalProfile', true)
                Na__DataSerializer.Na__DataSerializer__ClearLocalProfile(group)
                model.commit_operation
                if Na__RegenEngine.Na__RegenEngine__RegenerateFromHelpers(group)
                    reverted += 1
                else
                    model.start_operation('Na__ProfilePathTracer__RevertLocalProfileUndo', true, false, true)
                    Na__DataSerializer.Na__DataSerializer__WriteLocalProfileJson(group, previous_local['json'], previous_local['name'])
                    model.commit_operation
                    failures << "#{trace_id}: its library profile would not rebuild, so it keeps its own"
                end
            end

            bind   = Na__SwapEngine.Na__SwapEngine__BuildBindPayloadForIds(trace_ids)
            key    = bind['primaryProfileKey'].to_s
            record = key.empty? ? nil : Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(key)
            status = if reverted.zero? && failures.empty?
                         'The bound trace already uses its library profile.'
                     elsif failures.empty?
                         "#{reverted} trace(s) back on the library profile \"#{record ? record['displayName'] : key}\"."
                     else
                         "#{reverted} trace(s) reverted. #{failures.join('; ')}"
                     end
            {
                'isApplied'     => reverted > 0,
                'isReverted'    => true,
                'appliedCount'  => reverted,
                'failures'      => failures,
                'bind'          => bind,
                'profileRecord' => record,
                'statusMessage' => status
            }
        rescue => error
            Na__DebugTools.Na__Debug__Error('Draw Profile: revert to library failed.', error)
            self.Na__TraceBridge__LocalFailure("Revert failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - This Trace Only
    # -------------------------------------------------------------------------

        # The dictionary write and the rebuild are two operations, the rebuild's
        # transparent, so they undo as one - the swap engine's own pattern. A
        # failed rebuild puts back whatever profile the trace had before.
        def self.Na__TraceBridge__ApplyLocalToOne(model, trace_id, asset_data, display_name)
            group = Na__SwapEngine.Na__SwapEngine__ResolveTraceById(trace_id)
            return { ok: false, reason: "#{trace_id} is no longer in the model" } unless group
            readiness = Na__SwapEngine.Na__SwapEngine__CheckHelpersReady(group)
            return { ok: false, reason: "#{trace_id}: #{readiness[:reason]}" } unless readiness[:isReady]

            previous_local = Na__DataSerializer.Na__DataSerializer__ReadLocalProfileRaw(group)
            model.start_operation('Na__ProfilePathTracer__LocalProfileEdit', true)
            Na__DataSerializer.Na__DataSerializer__WriteLocalProfile(group, asset_data, display_name)
            model.commit_operation

            return { ok: true } if Na__RegenEngine.Na__RegenEngine__RegenerateFromHelpers(group)

            model.start_operation('Na__ProfilePathTracer__LocalProfileEditUndo', true, false, true)
            if previous_local
                Na__DataSerializer.Na__DataSerializer__WriteLocalProfileJson(group, previous_local['json'], previous_local['name'])
            else
                Na__DataSerializer.Na__DataSerializer__ClearLocalProfile(group)
            end
            model.commit_operation
            { ok: false, reason: "#{trace_id} would not rebuild with that outline (the status bar says why); it keeps its previous profile" }
        rescue => error
            model.abort_operation rescue nil
            { ok: false, reason: "#{trace_id}: #{error.message}" }
        end

        # Where a local profile takes its edge colour from: the trace's current
        # local profile (Live mode's every update after the first, no library
        # scan), else the library profile it was drawn from.
        def self.Na__TraceBridge__StyleSource(group)
            local = Na__DataSerializer.Na__DataSerializer__LocalProfileRecord(group)
            return local.dig('profileData', 'assetData') if local
            payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(group) || {}
            Na__DrawProfile__ProfileWriter.Na__ProfileWriter__BaseAssetData(payload['ProfileKey'])
        rescue
            nil
        end

        def self.Na__TraceBridge__LocalFailure(reason)
            {
                'isApplied'     => false,
                'appliedCount'  => 0,
                'failures'      => [reason.to_s],
                'reason'        => reason.to_s,
                'statusMessage' => reason.to_s
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Trace Selection
    # -------------------------------------------------------------------------

        def self.Na__TraceBridge__TracePayload(traces)
            trace_ids = traces.map { |group| Na__DataSerializer.Na__DataSerializer__ReadTraceId(group) }.reject(&:empty?)
            return self.Na__TraceBridge__Failure('The selected assembly carries no Profile Trace id.') if trace_ids.empty?

            unique_ids = trace_ids.uniq
            bind = Na__SwapEngine.Na__SwapEngine__BuildBindPayloadForIds(unique_ids)
            return self.Na__TraceBridge__Failure(bind['statusMessage']) unless bind['isBound']

            profile_key = bind['primaryProfileKey'].to_s
            primary     = Na__SwapEngine.Na__SwapEngine__ResolveTraceById(unique_ids.first)
            # A trace with its own profile opens THAT, not the library one it
            # was drawn from: it is what the model shows.
            record      = bind['primaryIsLocal'] && primary ? Na__DataSerializer.Na__DataSerializer__LocalProfileRecord(primary) : nil
            record    ||= profile_key.empty? ? nil : Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_key)
            label       = unique_ids.length == 1 ? unique_ids.first : "#{unique_ids.length} traces (#{unique_ids.first} first)"
            duplicates  = trace_ids.length - unique_ids.length

            status = if record && record['isLocal']
                         "#{label} bound. Its own local profile is loaded — edit it, then Update This Trace (or turn Live on)."
                     elsif record
                         "#{label} bound. Its profile \"#{record['displayName']}\" is loaded — edit it, then Update This Trace (this trace only) or Save to Library."
                     else
                         "#{label} bound, but its profile \"#{profile_key}\" is not in the library. Draw one, then Update This Trace."
                     end
            if duplicates > 0
                status += " #{duplicates} selected copy(ies) share a trace id and were left out — click outside them once so they are re-stamped."
            end

            {
                'isResolved'    => true,
                'kind'          => 'trace',
                'bind'          => bind.reject { |key, _| key == 'statusMessage' },
                'profileRecord' => record,
                'keyUsageCount' => self.Na__TraceBridge__CountTracesUsing(profile_key),
                'statusMessage' => status
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Face / Edge Selection
    # -------------------------------------------------------------------------

        def self.Na__TraceBridge__GeometryPayload(model)
            faces = []
            edges = []
            # @delegate: ../33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__Exporter__
            Na__ProfileExporter.Na__Exporter__CollectEntitiesFromSelection(model.selection.to_a, faces, edges)

            return self.Na__TraceBridge__FacePayload(faces) unless faces.empty?
            return self.Na__TraceBridge__EdgePayload(edges) unless edges.empty?

            self.Na__TraceBridge__Failure('The selection holds no Profile Trace, face or edges. Select one of those first.')
        end

        # The largest selected face. Its outer loop is walked vertex by vertex
        # (Vertex#common_edge finds each edge, so the walk never relies on the
        # loop handing its edges back in the same order as its vertices) and
        # every run of edges belonging to one ArcCurve becomes an arc run.
        def self.Na__TraceBridge__FacePayload(faces)
            face = faces.max_by { |candidate| (candidate.area rescue 0.0) }
            loop_vertices = face.outer_loop.vertices
            return self.Na__TraceBridge__Failure('The selected face has fewer than three corners.') if loop_vertices.length < 3

            frame  = Na__ProfileExporter.Na__Exporter__BuildLocalFrame([face], [], loop_vertices.first.position)
            points = loop_vertices.map { |vertex| Na__ProfileExporter.Na__Exporter__ProjectPointToLocalYZ(vertex.position, frame) }
            points = self.Na__TraceBridge__ShiftToLowerLeft(points)

            loop_edges = loop_vertices.each_index.map do |index|
                loop_vertices[index].common_edge(loop_vertices[(index + 1) % loop_vertices.length])
            end
            curve_ids = loop_edges.map do |edge|
                curve = edge ? edge.curve : nil
                curve.is_a?(Sketchup::ArcCurve) ? curve : nil
            end
            curves = self.Na__TraceBridge__ArcRuns(curve_ids)
            paint  = self.Na__TraceBridge__EdgePaints(loop_edges)

            hole_count = [face.loops.length - 1, 0].max
            hole_note  = hole_count > 0 ? " Its #{hole_count} hole(s) were left out: a profile is one outline." : ''
            {
                'isResolved'    => true,
                'kind'          => 'face',
                'loop'          => points,
                'curves'        => curves,
                'edgePaint'     => paint[:ids],
                'paintHex'      => paint[:hex],
                'holeCount'     => hole_count,
                'statusMessage' => "Face outline loaded: #{points.length} corners, #{curves.length} arc(s), lower-left corner at the datum.#{hole_note}"
            }
        end

        # Edge Paint (v1.6.15): each loop edge's colour, as Create Profile reads
        # it - the registry's key for a standard material, else the material's
        # own name and colour - so a face drawn in colour opens in colour. An
        # unpainted edge is nil: it takes the profile's usual colour.
        def self.Na__TraceBridge__EdgePaints(loop_edges)
            hex = {}
            ids = loop_edges.map do |edge|
                material = edge && edge.material
                next nil unless material
                name  = material.display_name.to_s
                id    = Na__EdgeColourManager.Na__EdgeColours__CanonicalIdForMaterial(name) || name
                entry = Na__EdgeColourManager.Na__EdgeColours__GetEntryByName(id)
                colour = entry ? entry['HexValue'].to_s : self.Na__TraceBridge__HexOf(material.color)
                hex[id] = colour unless colour.to_s.empty?
                id.empty? ? nil : id
            end
            { ids: ids, hex: hex }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Draw Profile: edge colours not read: #{error.message}")
            { ids: Array.new(loop_edges.length), hex: {} }
        end

        def self.Na__TraceBridge__HexOf(color)
            return '' unless color
            format('#%02X%02X%02X', color.red.to_i, color.green.to_i, color.blue.to_i)
        rescue
            ''
        end

        def self.Na__TraceBridge__EdgePayload(edges)
            if edges.length > NA_MAX_EDGES_READ
                return self.Na__TraceBridge__Failure("#{edges.length} edges is more than the editor reads (#{NA_MAX_EDGES_READ}). Select less.")
            end

            frame    = Na__ProfileExporter.Na__Exporter__BuildLocalFrame([], edges, edges.first.start.position)
            segments = edges.map do |edge|
                [
                    Na__ProfileExporter.Na__Exporter__ProjectPointToLocalYZ(edge.start.position, frame),
                    Na__ProfileExporter.Na__Exporter__ProjectPointToLocalYZ(edge.end.position, frame)
                ]
            end
            flat     = self.Na__TraceBridge__ShiftToLowerLeft(segments.flatten(1))
            segments = flat.each_slice(2).to_a
            {
                'isResolved'    => true,
                'kind'          => 'edges',
                'segments'      => segments,
                'statusMessage' => "#{segments.length} edge(s) loaded as straight segments. Join them into one closed outline; Rebuild Arcs turns arc-shaped runs back into arcs."
            }
        end

        # [curve_or_nil per loop edge] -> [{ startIndex, segments, radius }].
        # A run may wrap past the first edge; a run of every edge is a circle.
        def self.Na__TraceBridge__ArcRuns(curve_per_edge)
            count = curve_per_edge.length
            ids   = curve_per_edge.map { |curve| curve ? curve.entityID : nil }
            return [] if ids.all?(&:nil?)

            if ids.uniq.length == 1
                radius = (curve_per_edge.first.radius.to_f * NA_MM_PER_INCH).round(6)
                return [{ 'startIndex' => 0, 'segments' => count, 'radius' => radius }]
            end

            # Start the walk on an edge where a run begins, so no run is split
            # across the end of the array.
            start = (0...count).find { |index| ids[index] != ids[(index - 1) % count] } || 0
            runs  = []
            index = 0
            while index < count
                slot = (start + index) % count
                curve_id = ids[slot]
                length = 1
                length += 1 while index + length < count && ids[(start + index + length) % count] == curve_id
                if curve_id && length >= 2
                    radius = (curve_per_edge[slot].radius.to_f * NA_MM_PER_INCH).round(6)
                    runs << { 'startIndex' => slot, 'segments' => length, 'radius' => radius }
                end
                index += length
            end
            runs
        end

        def self.Na__TraceBridge__ShiftToLowerLeft(points)
            min_y = points.map { |point| point[0] }.min
            min_z = points.map { |point| point[1] }.min
            points.map { |point| [(point[0] - min_y).round(6), (point[1] - min_z).round(6)] }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Other Traces on a Key
    # -------------------------------------------------------------------------

        def self.Na__TraceBridge__TracesUsing(model, profile_key)
            Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model)
                              .uniq { |group| (group.persistent_id rescue group.object_id) }
                              .select do |group|
                payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(group)
                # A trace with its own local profile does not follow the library file.
                payload && payload['ProfileKey'].to_s == profile_key && payload['ProfileSource'] != 'local'
            end
        end

        def self.Na__TraceBridge__RebuildOtherTraces(profile_key, exclude_ids)
            model = Sketchup.active_model
            return { 'rebuilt' => 0, 'failed' => 0 } unless model

            rebuilt = 0
            failed  = 0
            self.Na__TraceBridge__TracesUsing(model, profile_key).each do |group|
                next if exclude_ids.include?(Na__DataSerializer.Na__DataSerializer__ReadTraceId(group))
                # @delegate: ../31__System__ApplyProfileMode/Na__ProfileTools__RegenerationEngine__Main__
                if Na__RegenEngine.Na__RegenEngine__RegenerateFromHelpers(group)
                    rebuilt += 1
                else
                    failed += 1
                end
            end
            { 'rebuilt' => rebuilt, 'failed' => failed }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Messages
    # -------------------------------------------------------------------------

        def self.Na__TraceBridge__ApplyStatus(save_result, swap_result, others)
            parts = [save_result['statusMessage'].to_s, swap_result['statusMessage'].to_s]
            parts << "#{others['rebuilt']} other trace(s) rebuilt." if others['rebuilt'] > 0
            parts << "#{others['failed']} other trace(s) could not be rebuilt." if others['failed'] > 0
            parts.reject(&:empty?).join(' ')
        end

        def self.Na__TraceBridge__Failure(reason)
            {
                'isResolved'    => false,
                'kind'          => '',
                'reason'        => reason.to_s,
                'statusMessage' => reason.to_s
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
