# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - PATH EDITOR
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__PathEditor__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__PathEditor (+ class Na__RunPathObserver)
# AUTHOR     : Noble Architecture
# PURPOSE    : Edit Path in SketchUp. A run keeps its path as data; this
#              draws that path as a red line inside the run, opens it for
#              SketchUp's own tools (Move, Line, Eraser), and when the user
#              steps back out reads the line and rebuilds the run along it.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# THE PROFILE PATH TRACER'S METHOD (its Edit Path, v1.6.16)
# - The path is DATA on the run (Na__RunConfig__PathPoints), never read back
#   from the built geometry. Edit Path only lends it to SketchUp as a line:
#     1. Draw the stored points as red edges in a group inside the run.
#     2. Open that group (Model#active_path=), so the user is straight in.
#     3. A ModelObserver notices the active path change. It only SCHEDULES a
#        look (a short timer): nothing is written inside an observer.
#     4. Once the group is no longer open: unchanged line, erase it; changed
#        line, chain its edges into one path and rebuild the run.
#
# COORDINATES
# - The line is drawn in the run definition's own frame, where the stored
#   path already is, so a run that is moved, turned or nested needs no
#   conversion. Read back, the group's own transformation is applied (the
#   user may have moved the whole line), and heights are dropped: a path
#   lies on the run's base.
# - Model#active_path= is called OUTSIDE any operation: SketchUp wraps path
#   changes in undo steps of its own.
#
# LIMIT (V2.7.0)
# - The run must stand in the context that is open now (the model root, or
#   the group being edited). A run nested elsewhere is refused with the fix.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'digest'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PathMath__'
require_relative 'Na__AssemblyStudio__AssemblyRun__DataSerializer__'
require_relative 'Na__AssemblyStudio__AssemblyRun__RunPipelines__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem

# -----------------------------------------------------------------------------
# REGION | Model Observer (Schedules, Never Writes)
# -----------------------------------------------------------------------------

    # CLASS | Notices the User Stepping Out of the Path Line
    # ------------------------------------------------------------
    class Na__RunPathObserver < Sketchup::ModelObserver
        def onActivePathChanged(_model)
            Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathEditor.na_schedule_check
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    module Na__PathEditor

# -----------------------------------------------------------------------------
# REGION | Module References, Constants and State
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        Defaults          = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        PathMath          = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath
        DataSerializer    = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__DataSerializer
        RunPipelines      = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunPipelines

        NA_EDIT_GROUP_NAME   = "Na__Run__EditPath".freeze
        NA_EDIT_LINE_COLOUR  = "MTE201__LineColour__Red".freeze
        NA_CHECK_DELAY_S     = 0.25

        @na_editing          ||= nil      # <-- { :instance, :group, :run_id, :baseline, :start } while a path line is open
        @na_observer         ||= nil
        @na_observed_model   ||= nil
        @na_check_pending    ||= false
        @na_on_finished      ||= nil      # <-- Proc(result Hash) the dialog router sets, to report back

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Who to Tell When a Path Edit Ends
        # ------------------------------------------------------------
        # @yield [Hash] { :status => :rebuilt | :unchanged | :discarded | :failed, :message, :report }
        def self.na_on_finished(&block)
            @na_on_finished = block
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Path Line Open Now (and for Which Run)
        # ------------------------------------------------------------
        # @return [String, nil] the run id
        def self.na_editing_run_id
            na_editing_valid? ? @na_editing[:run_id] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Run's Path as a Red Line and Open It
        # ------------------------------------------------------------
        # @return [Hash] { :run_id, :points, :closed }
        # @raise [RuntimeError] when the run cannot be edited where it stands
        def self.na_open(instance)
            loaded = RunPipelines.na_pipeline_load(instance)
            raise "Select an assembly run first." unless loaded
            raise "Finish or discard the path edit already open (run #{@na_editing[:run_id]}) first." if na_editing_valid?

            model = Sketchup.active_model
            RunPipelines.na_leave_run_context(instance)                          # <-- Inside the run itself (a span selected): step out, then draw
            unless instance.parent == model.active_entities.parent
                raise "This run is inside another group or component. Open that group (double click it) so the run is in the open context, then use Edit Path."
            end

            config = loaded[:root][Defaults::NA_KEY_CONFIGURATION] || {}
            closed = config[Defaults.na_key("PathClosed")] == true
            points = PathMath.na_clean_points(config[Defaults.na_key("PathPoints")] || [], closed)
            raise "#{loaded[:id]} has no path to edit." if points.length < 2

            model.start_operation("Edit Run Path", true)
            group = na_draw_line(instance.definition.entities, points, closed)
            model.commit_operation

            @na_editing = { :instance => instance, :group => group, :run_id => loaded[:id],
                            :baseline => na_fingerprint(group), :start => points.first }
            na_attach_observer(model)
            model.active_path = Array(model.active_path) + [instance, group]     # <-- Outside the operation (see the header)
            DebugTools.na_debug_ui("Run #{loaded[:id]}: path line opened (#{points.length} points)")
            { :run_id => loaded[:id], :points => points, :closed => closed }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Line Back and Rebuild the Run Along It
        # ------------------------------------------------------------
        # Leaves the line's context first when the user is still inside.
        # @return [Hash] the result handed to na_on_finished
        def self.na_finish
            return na_done(:failed, "No path edit is open.") unless na_editing_valid?
            editing = @na_editing
            na_leave_context(editing)

            segments = na_segments(editing[:group])
            return na_discard_now(editing, "The path line was empty, so the run was left as it was.") if segments.empty?
            if na_fingerprint(editing[:group]) == editing[:baseline]
                return na_discard_now(editing, "The path was not changed.", :unchanged)
            end

            chain = PathMath.na_chain_segments(segments, editing[:start])
            @na_editing = nil
            report = RunPipelines.na_pipeline_set_path(editing[:instance], chain[:points], chain[:closed], "Edit Run Path")   # <-- The rebuild clears the run, line and all
            na_done(:rebuilt, "#{editing[:run_id]} rebuilt along its new path: #{chain[:points].length} points#{chain[:closed] ? ', closed' : ''}.", report)
        rescue ArgumentError, Na__RunLayoutError => e
            # The line stays, so it can be put right and finished again. Its
            # fingerprint is remembered so stepping about the model does not
            # try (and refuse) the same line over and over.
            editing[:failed_print] = na_fingerprint(editing[:group]) if editing[:group].valid?
            @na_editing = editing
            na_done(:failed, "The run was not changed: #{e.message} The red path line is still inside the run: correct it and finish again, or discard it.")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Throw the Line Away and Leave the Run as It Was
        # ------------------------------------------------------------
        def self.na_discard
            return na_done(:failed, "No path edit is open.") unless @na_editing
            editing = @na_editing
            na_leave_context(editing) if na_editing_valid?
            na_discard_now(editing, "Path edit discarded.")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Look, a Moment From Now, Whether the User Has Stepped Out
        # ------------------------------------------------------------
        # Called by the observer. One timer at a time; the work happens in
        # the timer, outside the observer callback.
        def self.na_schedule_check
            return if @na_check_pending || @na_editing.nil?
            @na_check_pending = true
            UI.start_timer(NA_CHECK_DELAY_S, false) do
                @na_check_pending = false
                begin
                    if na_editing_valid? && !na_inside_line? && na_fingerprint(@na_editing[:group]) != @na_editing[:failed_print]
                        na_finish
                    end
                rescue StandardError => e
                    DebugTools.na_debug_error("Run path edit could not finish", e)
                    na_done(:failed, "The path edit could not finish: #{e.message}")
                end
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Line
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Draw the Path as Red Edges in a Group
        # ------------------------------------------------------------
        def self.na_draw_line(entities, points, closed)
            group      = entities.add_group
            group.name = NA_EDIT_GROUP_NAME
            corners    = points.map { |point| Geom::Point3d.new(point[0].mm, point[1].mm, 0) }
            corners.each_cons(2) { |a, b| group.entities.add_line(a, b) }
            group.entities.add_line(corners.last, corners.first) if closed && corners.length > 2
            begin
                EdgeColourManager.na_apply_edge_colour_to_group(group, NA_EDIT_LINE_COLOUR)
            rescue StandardError => e
                DebugTools.na_debug_warn("Run path line left unpainted: #{e.message}")
            end
            group
        end
        private_class_method :na_draw_line
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Line's Edges as Plan Segments in the Run's Frame
        # ------------------------------------------------------------
        # @return [Array] [[[x, y], [x, y]], ...] in mm
        def self.na_segments(group)
            return [] unless group && group.valid?
            transform = group.transformation
            group.entities.grep(Sketchup::Edge).map do |edge|
                edge.vertices.map do |vertex|
                    point = vertex.position.transform(transform)
                    [point.x.to_mm, point.y.to_mm]
                end
            end
        end
        private_class_method :na_segments
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Fingerprint of the Line (Order Free)
        # ------------------------------------------------------------
        def self.na_fingerprint(group)
            pairs = na_segments(group).map { |a, b| [a, b].map { |point| point.map { |value| value.round(2) } }.sort }
            Digest::SHA1.hexdigest(pairs.sort.inspect)
        end
        private_class_method :na_fingerprint
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Context and State
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Is the Remembered Edit Still Real
        # ------------------------------------------------------------
        def self.na_editing_valid?
            editing = @na_editing
            return false unless editing && editing[:instance] && editing[:group]
            return true if editing[:instance].valid? && editing[:group].valid?
            @na_editing = nil                                                   # <-- Undone, erased or the model closed
            false
        end
        private_class_method :na_editing_valid?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Is the User Inside the Path Line's Group Now
        # ------------------------------------------------------------
        def self.na_inside_line?
            return false unless na_editing_valid?
            Array(Sketchup.active_model.active_path).include?(@na_editing[:group])
        end
        private_class_method :na_inside_line?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Step Out to the Context the Run Stands In
        # ------------------------------------------------------------
        def self.na_leave_context(editing)
            model = Sketchup.active_model
            path  = Array(model.active_path)
            index = path.index(editing[:instance])
            return unless index
            model.active_path = index.zero? ? nil : path[0...index]
        end
        private_class_method :na_leave_context
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Erase the Line and Report
        # ------------------------------------------------------------
        def self.na_discard_now(editing, message, status = :discarded)
            @na_editing = nil
            group = editing[:group]
            if group && group.valid?
                model = Sketchup.active_model
                model.start_operation("Close Run Path Edit", true, false, true)   # <-- Joins the step that drew the line
                group.erase!
                model.commit_operation
            end
            na_done(status, message)
        end
        private_class_method :na_discard_now
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Tell the Listener and Hand the Result Back
        # ------------------------------------------------------------
        def self.na_done(status, message, report = nil)
            result = { :status => status, :message => message, :report => report }
            begin
                @na_on_finished.call(result) if @na_on_finished
            rescue StandardError => e
                DebugTools.na_debug_warn("Run path edit listener failed: #{e.message}")
            end
            result
        end
        private_class_method :na_done
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One Observer on the Model Being Edited
        # ------------------------------------------------------------
        def self.na_attach_observer(model)
            return if @na_observer && @na_observed_model == model
            @na_observer       = Na__RunPathObserver.new
            @na_observed_model = model
            model.add_observer(@na_observer)
        end
        private_class_method :na_attach_observer
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PathEditor
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
