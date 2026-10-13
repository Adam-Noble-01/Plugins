# =============================================================================
# NA PROFILE TOOLS - APP CORE - EDIT PATH NAVIGATOR
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__EditPathNavigator__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EditPathNavigator
# PURPOSE    : Edit Path. A trace keeps its path as data (PathRuns, v1.6.16):
#              there is no path linework in the model and no helper tag. Edit
#              Path draws the path as a red line in a group inside the trace
#              (Na__ProfileTrace__EditPath), opens that group with
#              Model#active_path= (SketchUp 2020+) and selects the line, ready
#              for Move, stretch, Line, Eraser: any SketchUp tool. Clicking
#              outside the trace finishes the edit (Na__RegenSweep): the trace
#              rebuilds along the line, the line becomes the stored path, and
#              the group is erased. Left unchanged, it is simply erased.
#
# COORDINATE SPACE (the Coordinate Rule)
#   The stored path is in the assembly's own space. The line is drawn with
#   the assembly CLOSED (a trace the user is standing in is stepped out of
#   first), so the new group's entities are local, the group starts at the
#   identity, and the stored points go in exactly as they are: no
#   edit_transform, no inverse. It is read back the same way, once the user
#   has left the trace. Nothing is converted on the way in or out, so a path
#   opened and closed without an edit comes back bit for bit, however often.
#
# UNDO
#   Drawing the line and opening it are one undo step. Each edit is the
#   user's own. Finishing joins the last edit (transparent), so one Ctrl+Z
#   takes back the last edit and the rebuild together. An undo can bring the
#   line back; it then waits, and the next change made applies it.
#
# LEGACY TRACES (built before v1.6.16)
#   Their path is edges in a Helpers group on the 02__ProfilePathTracer_Helpers
#   tag. Edit Path moves the path into PathRuns and erases the Helpers group in
#   the same step as it draws the red line, so the path never shows twice.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__EditPathNavigator

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        # The red of the old Helpers linework (MTE201), from the edge colour
        # library; a model without the library gets the same red by value.
        NA_LINE_MATERIAL_ID  = 'MTE201__LineColour__Red'.freeze
        NA_LINE_FALLBACK_RGB = [229, 57, 53].freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Entry Points
    # -------------------------------------------------------------------------

        def self.Na__EditPath__OpenForCurrentSelection
            model = Sketchup.active_model
            return self.Na__EditPath__Failure('No active model.') unless model

            if Sketchup.version.to_i < 20
                return self.Na__EditPath__Failure(
                    'Opening the path programmatically needs SketchUp 2020 or newer.'
                )
            end

            parent_group = self.Na__EditPath__ResolveTraceParent(model)
            unless parent_group
                return self.Na__EditPath__Failure(
                    'Select one Profile Trace assembly (or any part of one) first.'
                )
            end

            self.Na__EditPath__OpenTrace(model, parent_group)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: open failed: #{error.message}")
            self.Na__EditPath__Failure("Edit path failed: #{error.message}")
        end

        def self.Na__EditPath__OpenTrace(model, parent_group)
            existing = Na__DataSerializer.Na__DataSerializer__FindEditPathGroup(parent_group)
            if existing && self.Na__EditPath__InsideGroup?(model, existing)
                count = self.Na__EditPath__SelectLine(model, existing)
                return self.Na__EditPath__Opened(parent_group, count, 'is already open for editing')
            end

            if parent_group.respond_to?(:locked?) && parent_group.locked?
                return self.Na__EditPath__Failure("#{parent_group.name} is locked — unlock it to edit its path.")
            end

            # The line is drawn and read in the trace's own space, which the API
            # reports only while the trace is closed.
            unless Na__RegenEngine.Na__RegenEngine__LeaveAssemblyContext(parent_group)
                return self.Na__EditPath__Failure("#{parent_group.name} is open and could not be closed — click outside it, then Edit Path.")
            end

            model.selection.clear
            edit_group = existing
            created    = false
            unless edit_group
                spawn = self.Na__EditPath__SpawnLine(model, parent_group)
                return self.Na__EditPath__Failure(spawn[:reason]) unless spawn[:isSpawned]
                edit_group = spawn[:group]
                created    = true
            end

            # Outside any operation: SketchUp wraps a path change in transparent
            # operations of its own, which join the one that drew the line.
            begin
                model.active_path = Array(model.active_path) + [parent_group, edit_group]
            rescue ArgumentError => error
                self.Na__EditPath__RemoveLine(model, parent_group, edit_group) if created
                return self.Na__EditPath__Failure("Could not open the path (locked or invalid context): #{error.message}")
            end

            edit_group = Na__DataSerializer.Na__DataSerializer__FindEditPathGroup(parent_group) || edit_group
            Na__RegenSweep.Na__RegenSweep__WatchEditGroup(edit_group) if defined?(Na__RegenSweep)
            count = self.Na__EditPath__SelectLine(model, edit_group)
            self.Na__EditPath__Opened(parent_group, count, created ? 'is open for editing' : 'is open for editing again (its edit was waiting)')
        rescue => error
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: open failed: #{error.message}")
            self.Na__EditPath__Failure("Edit path failed: #{error.message}")
        end

        # Apply the red line now rather than by clicking outside: the rebuild
        # takes the line along, stores it and erases it.
        def self.Na__EditPath__FinishNow(parent_group)
            Na__RegenEngine.Na__RegenEngine__RegenerateTrace(parent_group)
        end

        # Throw the red line away; the trace keeps the path it has. Its own
        # undo step, so Ctrl+Z brings the line back.
        def self.Na__EditPath__Discard(parent_group)
            model = Sketchup.active_model
            return false unless model && Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)

            edit_groups = Na__DataSerializer.Na__DataSerializer__FindEditPathGroups(parent_group)
            return false if edit_groups.empty?
            return false unless Na__RegenEngine.Na__RegenEngine__LeaveAssemblyContext(parent_group)

            model.start_operation('Na__ProfilePathTracer__EditPathDiscard', true)
            parent_group.entities.erase_entities(edit_groups.select(&:valid?))
            model.commit_operation
            Sketchup.status_text = "Profile Path Tracer: path edit discarded — #{parent_group.name} keeps its path."
            true
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: discard failed: #{error.message}")
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Drawing the Line
    # -------------------------------------------------------------------------

        # One operation: the line, its material and its marker, and on a legacy
        # trace the move onto stored data. The baseline fingerprint is taken
        # from the edges just drawn, in the trace's own space, so the finish
        # compares like with like.
        def self.Na__EditPath__SpawnLine(model, parent_group)
            payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(parent_group)
            return { isSpawned: false, reason: "#{parent_group.name} carries no Profile Path Tracer data." } unless payload

            stored = Na__RegenEngine.Na__RegenEngine__StoredPathRuns(parent_group, payload)
            return { isSpawned: false, reason: "#{parent_group.name} has no path to edit: #{stored[:reason]}" } unless stored[:isValid]

            # Legacy linework edited by hand but never rebuilt: the solid does not
            # follow it yet, so the finish must rebuild even if the line is left
            # alone. Read before the Helpers group goes.
            force_rebuild = stored[:source] == :legacy && self.Na__EditPath__LegacyLineworkEdited?(parent_group)

            model.start_operation('Na__ProfilePathTracer__EditPath', true)
            # A copy sharing this trace's definition would grow the line too.
            Na__RegenEngine.Na__RegenEngine__EnsureUniqueAssembly(parent_group)

            if stored[:source] != :stored
                Na__DataSerializer.Na__DataSerializer__WritePathRuns(parent_group, stored[:runs])
                Na__DataSerializer.Na__DataSerializer__RetireLegacyHelpers(parent_group)
            end

            edit_group = parent_group.entities.add_group
            edit_group.name = Na__DataSerializer::NA_EDIT_PATH_GROUP_NAME
            edges = self.Na__EditPath__DrawRuns(edit_group.entities, stored[:runs])
            material = self.Na__EditPath__LineMaterial(model)
            edges.each { |edge| edge.material = material } if material

            baseline = Na__RegenSweep.Na__RegenSweep__ComputeFingerprint(edit_group)
            Na__DataSerializer.Na__DataSerializer__StampEditPathGroup(
                edit_group, payload['ProfileTraceId'], baseline, force_rebuild
            )
            model.commit_operation
            { isSpawned: true, group: edit_group, reason: nil }
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: drawing the path failed: #{error.message}")
            { isSpawned: false, reason: "the path could not be drawn: #{error.message}" }
        end

        # Stored points, straight in: the group is closed and at the identity.
        # A loop's closing edge is implied by the data and drawn here.
        def self.Na__EditPath__DrawRuns(entities, runs)
            edges = []
            Array(runs).each do |run|
                points = Array(run[:ordered_points])
                (0...(points.length - 1)).each do |index|
                    edge = entities.add_line(points[index], points[index + 1])
                    edges << edge if edge
                end
                if run[:is_closed_loop] && points.length >= 3
                    edge = entities.add_line(points.last, points.first)
                    edges << edge if edge
                end
            end
            edges
        end

        def self.Na__EditPath__LineMaterial(model)
            if defined?(Na__EdgeColourManager) && Na__EdgeColourManager.respond_to?(:Na__EdgeColours__EnsureSketchUpMaterial)
                material = Na__EdgeColourManager.Na__EdgeColours__EnsureSketchUpMaterial(model, NA_LINE_MATERIAL_ID)
                return material if material
            end
            existing = model.materials[NA_LINE_MATERIAL_ID]
            return existing if existing

            material = model.materials.add(NA_LINE_MATERIAL_ID)
            material.color = Sketchup::Color.new(*NA_LINE_FALLBACK_RGB)
            material
        rescue => error
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: line colour skipped: #{error.message}")
            nil
        end

        def self.Na__EditPath__LegacyLineworkEdited?(parent_group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return false unless helpers_group
            stored_fingerprint = Na__DataSerializer.Na__DataSerializer__ReadHelpersFingerprint(parent_group)
            return false if stored_fingerprint.to_s.empty?
            current_fingerprint = Na__RegenSweep.Na__RegenSweep__ComputeFingerprint(helpers_group)
            !current_fingerprint.nil? && current_fingerprint != stored_fingerprint
        rescue
            false
        end

        # The path change failed after the line was drawn: take it away again,
        # joined to the step that drew it, so nothing is left behind.
        def self.Na__EditPath__RemoveLine(model, parent_group, edit_group)
            model.start_operation('Na__ProfilePathTracer__EditPathClose', true, false, true)
            parent_group.entities.erase_entities([edit_group]) if edit_group.valid?
            model.commit_operation
        rescue => error
            model.commit_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: line removal failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Resolution Helpers
    # -------------------------------------------------------------------------

        # Every selected entity resolves up to its trace (the assembly itself,
        # its solid, a face of it, or the red line's own edges while it is
        # open), and exactly one trace must come out of it.
        def self.Na__EditPath__ResolveTraceParent(model)
            found = {}
            model.selection.to_a.each do |entity|
                parent = Na__DataSerializer.Na__DataSerializer__ResolveTraceParentForEntity(entity)
                next unless parent
                found[(parent.persistent_id rescue parent.object_id)] = parent
                return nil if found.length > 1
            end
            found.values.first
        rescue
            nil
        end

        def self.Na__EditPath__InsideGroup?(model, group)
            Array(model.active_path).any? { |instance| instance == group }
        rescue
            false
        end

        def self.Na__EditPath__SelectLine(model, edit_group)
            edges = edit_group.entities.grep(Sketchup::Edge).select(&:valid?)
            model.selection.clear
            model.selection.add(edges) unless edges.empty?
            edges.length
        rescue => error
            Na__DebugTools.Na__Debug__Warn("EditPathNavigator: edge selection skipped: #{error.message}")
            0
        end

        def self.Na__EditPath__Opened(parent_group, edge_count, state)
            message = "Path of #{parent_group.name} #{state} — #{edge_count} edge(s) selected. " \
                      'Move, stretch or redraw the red line with any tool, then click outside the trace: ' \
                      'it rebuilds along the line and the line is removed.'
            Sketchup.status_text = message
            { 'isOpened' => true, 'statusMessage' => message }
        end

        def self.Na__EditPath__Failure(reason)
            Sketchup.status_text = "Profile Path Tracer: #{reason}"
            { 'isOpened' => false, 'statusMessage' => reason }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
