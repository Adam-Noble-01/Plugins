# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE EDIT PATH
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Edit__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Edit a pipe's route after it is built: a red line you change with
#              SketchUp's own tools, and a rebuild when you step out of it
# CREATED    : 2026
#
# THE GESTURE (the Profile Path Tracer's Edit Path, v1.6.16, made for pipes):
#   1  right-click a pipe > Edit Pipework Path (or the bar's Edit Path)
#   2  the solid goes and its route is drawn as a RED line in a group inside
#      the pipe, which is opened; the overlay (DrawnPipe__Overlay__) draws the
#      pipe along the line, live, whatever tool is in use
#   3  Move points, draw on with Line, erase legs, make swan necks — any tool
#   4  click outside the pipe: it is rebuilt along the line, the line becomes
#      its stored route, and the red line goes
#   Finish Pipework Path and Discard Pipework Path Edit (right-click, the
#   bar, the Extensions menu) do the same without hunting for empty space.
#
# WHAT THE LINE MAY BECOME:
#   one run             the pipe follows it
#   several runs        the longest stays this pipe; each other run becomes a
#                       pipe of its own beside it, same spec, same frame
#   nothing left        the pipe keeps the route it had
#   left as it was      the pipe is rebuilt as it was (the solid was taken
#                       away while the line was out)
#   cannot be piped     the line stays and says why; Edit Path reopens it,
#                       Ctrl+Z steps back. The same line is not retried until
#                       it changes
#   Arcs on the stored route are drawn as welded curves, so they read back as
#   curves and stay soft, not as a string of new bends.
#
# WHY IT FINISHES ON LEAVING (the Profile Path Tracer's research):
#   EntitiesObserver#onElementModified does not fire when the Move tool moves
#   an edge, and redo delivers no entity events at all. Nothing watches the
#   line while it is being edited. Leaving the pipe (onActivePathChanged) is
#   the reliable moment; a fingerprint of the line as drawn says whether it
#   changed. Every observer only SCHEDULES a debounced sweep on a UI timer:
#   changing the model inside an observer callback is SketchUp's documented
#   crash vector.
#
# UNDO:
#   Drawing the line and opening it are one undo step; each edit is the
#   user's own; the finish joins the last edit (transparent), so one Ctrl+Z
#   takes back the last edit and the rebuild together. Undo and redo sweeps
#   are PASSIVE: a line an undo brings back waits, and the next change made
#   finishes it. A solve is checked BEFORE any operation starts, because a
#   transparent operation must never be aborted (it would take the user's
#   edit with it).
#
# COORDINATES (the Coordinate Rule):
#   The route lives in the pipe's own coordinates. The line is drawn with the
#   pipe CLOSED (a user standing inside it is stepped out first), so the new
#   group's entities are local and at the identity: the stored points go in
#   as they are. It is read back only once the pipe is closed again, through
#   the line group's own transformation (relative to the pipe). No
#   edit_transform, no world conversion, in or out.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPipe__Spec__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Route__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Solver__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Build__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Edit Constants and State
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_EDIT_NAME       = 'Na__DrawnPipe__EditPath'
    NA_DRAWN_PIPE_EDIT_DICT       = 'Na__InsertPrimatives__PipeEdit'
    NA_DRAWN_PIPE_LINE_MATERIAL   = 'MTE201__LineColour__Red'                 # <-- The Profile Path Tracer's red line, so the two read alike
    NA_DRAWN_PIPE_LINE_RGB        = [229, 57, 53].freeze
    NA_DRAWN_PIPE_SWEEP_DELAY     = 0.25
    NA_DRAWN_PIPE_PASSIVE_REASONS = %w[undo redo model-changed install].freeze

    # Guarded: Reload Plugin Data re-`load`s this file, and an unguarded
    # assignment would orphan live observers and timers.
    @na_pipe_edit_watched   = {}    unless defined?(@na_pipe_edit_watched)
    @na_pipe_edit_failed    = {}    unless defined?(@na_pipe_edit_failed)
    @na_pipe_edit_timer     = nil   unless defined?(@na_pipe_edit_timer)
    @na_pipe_edit_full      = false unless defined?(@na_pipe_edit_full)
    @na_pipe_edit_passive   = false unless defined?(@na_pipe_edit_passive)
    @na_pipe_edit_busy      = false unless defined?(@na_pipe_edit_busy)
    @na_pipe_app_observer   = nil   unless defined?(@na_pipe_app_observer)
    @na_pipe_model_observer = nil   unless defined?(@na_pipe_model_observer)
    @na_pipe_observed_model = nil   unless defined?(@na_pipe_observed_model)
    @na_pipe_menu_added     = false unless defined?(@na_pipe_menu_added)
    @na_pipe_menu_marker    = nil   unless defined?(@na_pipe_menu_marker)
    @na_pipe_menu_time      = 0.0   unless defined?(@na_pipe_menu_time)

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Finding an Edit
    # -----------------------------------------------------------------------------

    # FUNCTION | Is This the Red Line Group of a Pipe Edit?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__IsEditGroup?(entity)
        entity.is_a?(Sketchup::Group) && entity.valid? && entity.name.to_s == NA_DRAWN_PIPE_EDIT_NAME
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Red Line Group Inside a Pipe, or nil
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditGroupOf(pipe)
        return nil unless pipe && pipe.valid?

        pipe.entities.find { |entity| Na__InsertPrimatives.Na__DrawnPipe__IsEditGroup?(entity) }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Pipe a Red Line Group Belongs To, or nil
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__PipeOfEdit(edit)
        return nil unless Na__InsertPrimatives.Na__DrawnPipe__IsEditGroup?(edit)

        owner = edit.parent
        return nil unless owner.respond_to?(:instances)

        owner.instances.find { |instance| Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(instance) }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Edit the User Is Standing In, or nil
    # ------------------------------------------------------------
    # { :pipe, :edit, :inside => :edit } inside the red line's group, or
    # { ..., :inside => :pipe } one step out, in the pipe around it. Both
    # count as still editing: the rebuild waits until the pipe is left.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OpenEdit(model)
        path = model ? Array(model.active_path) : []
        return nil if path.empty?

        path.each_with_index.reverse_each do |instance, index|
            if Na__InsertPrimatives.Na__DrawnPipe__IsEditGroup?(instance)
                pipe = index > 0 ? path[index - 1] : nil
                return { :pipe => pipe, :edit => instance, :inside => :edit } if Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(pipe)
            elsif Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(instance)
                edit = Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(instance)
                return { :pipe => instance, :edit => edit, :inside => :pipe } if edit
            end
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the User Standing in This Pipe or Its Line?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__InsideEdit?(model, pipe, edit)
        Array(model.active_path).any? { |instance| instance == pipe || instance == edit }
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Opening
    # -----------------------------------------------------------------------------

    # FUNCTION | Edit a Pipe's Path: Draw Its Red Line and Open It
    # ------------------------------------------------------------
    # Returns { :ok, :message }. A line already waiting inside the pipe (left
    # by an undo, or a model saved mid-edit) is reopened rather than drawn
    # again, so an unfinished edit is never thrown away.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditOpen(pipe)
        model = Sketchup.active_model
        return Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, 'no model is open') unless model
        return Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, 'editing a path needs SketchUp 2020 or newer') if Sketchup.version.to_i < 20
        return Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, 'select one pipe the Pipework tool built') unless Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(pipe)
        return Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, "#{pipe.name} is locked — unlock it to edit its path") if pipe.respond_to?(:locked?) && pipe.locked?

        existing = Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(pipe)
        if existing && Array(model.active_path).include?(existing)
            return Na__InsertPrimatives.Na__DrawnPipe__EditOpened(model, pipe, 'is already open')
        end

        unless Na__InsertPrimatives.Na__DrawnPipe__LeavePipe(model, pipe)
            return Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, "#{pipe.name} is open and could not be closed — click outside it, then Edit Pipework Path")
        end

        model.selection.clear
        edit = existing || Na__InsertPrimatives.Na__DrawnPipe__EditSpawn(model, pipe)
        return Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, 'the path could not be drawn') unless edit

        # Outside any operation: SketchUp wraps a path change in transparent
        # operations of its own, which join the one that drew the line.
        begin
            model.active_path = Array(model.active_path) + [pipe, edit]
        rescue ArgumentError => error
            return Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, "the path could not be opened (#{error.message}) — double-click into the pipe to reach it")
        end

        Na__InsertPrimatives.Na__DrawnPipe__EditWatch(edit)
        Na__InsertPrimatives.Na__DrawnPipe__OverlayEnable(model) if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__OverlayEnable)
        Na__InsertPrimatives.Na__DrawnPipe__EditOpened(model, pipe, existing ? 'is open again (its edit was waiting)' : 'is open')
    rescue StandardError => error
        Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, "Edit Pipework Path failed — #{error.message}")
    end
    # ---------------------------------------------------------------

    # FUNCTION | Step Out of a Pipe the User Is Standing In
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__LeavePipe(model, pipe)
        path  = Array(model.active_path)
        index = path.index(pipe)
        return true unless index

        model.active_path = index.zero? ? nil : path[0...index]
        !Array(model.active_path).include?(pipe)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Operation: Solid Out, Red Line In, Fingerprint Taken
    # ------------------------------------------------------------
    # The solid goes because the line runs down its middle and would be hidden
    # inside it; the overlay draws the pipe instead, and every finish rebuilds
    # it. A copy sharing this pipe's definition would grow the line too, so the
    # pipe is made unique first.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditSpawn(model, pipe)
        stored = Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(pipe)
        return nil unless stored

        model.start_operation('Edit Pipework Path', true)

        pipe.make_unique if pipe.respond_to?(:make_unique)
        pipe.entities.clear!

        edit      = pipe.entities.add_group
        edit.name = NA_DRAWN_PIPE_EDIT_NAME

        edges    = Na__InsertPrimatives.Na__DrawnPipe__EditDrawRoute(edit.entities, stored)
        material = Na__InsertPrimatives.Na__DrawnPipe__EditLineMaterial(model)
        edges.each { |edge| edge.material = material if edge.valid? } if material

        edit.set_attribute(NA_DRAWN_PIPE_EDIT_DICT, 'Baseline', Na__InsertPrimatives.Na__DrawnPipe__EditFingerprint(edit))
        model.commit_operation
        edit
    rescue StandardError => error
        model.abort_operation rescue nil
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: drawing the line failed — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw a Stored Route as Lines, Its Arcs as Welded Curves
    # ------------------------------------------------------------
    # A piece runs from one corner to the next through any smooth points; a
    # piece of three points or more goes in with add_curve, so the route
    # reader sees one curve there again and keeps it soft. A loop starts on a
    # corner, so no piece wraps round its start; a loop with no corner at all
    # (a circle) is one closed curve.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditDrawRoute(entities, stored)
        points = stored[:points]
        smooth = stored[:smooth] || []
        count  = points.length
        return [] if count < 2

        if stored[:closed]
            corner = (0...count).find { |index| !smooth[index] }
            return Array(entities.add_curve(points + [points.first])) if corner.nil?

            order = (0..count).map { |step| (corner + step) % count }
        else
            order = (0...count).to_a
        end

        edges = []
        piece = [order.first]

        order.drop(1).each_with_index do |index, step|
            piece << index
            final = step == order.length - 2
            next if smooth[index] && !final

            edges.concat(Na__InsertPrimatives.Na__DrawnPipe__EditDrawPiece(entities, piece.map { |at| points[at] }))
            piece = [index]
        end

        edges
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Piece: a Line, or a Welded Curve
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditDrawPiece(entities, points)
        return [entities.add_line(points[0], points[1])].compact if points.length == 2

        Array(entities.add_curve(points))
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Red the Line Is Drawn In
    # The Profile Path Tracer's own material when its edge colour library is
    # loaded, so both plugins' lines are one red; otherwise the same red by value.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditLineMaterial(model)
        existing = model.materials[NA_DRAWN_PIPE_LINE_MATERIAL]
        return existing if existing

        material = model.materials.add(NA_DRAWN_PIPE_LINE_MATERIAL)
        material.color = Sketchup::Color.new(*NA_DRAWN_PIPE_LINE_RGB)
        material
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Reading the Line Back
    # -----------------------------------------------------------------------------

    # FUNCTION | The Line's Runs, in the Pipe's Own Coordinates
    # ------------------------------------------------------------
    # Only called with the pipe closed: then the line's vertices read local to
    # the line's group, and its transformation is relative to the pipe.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditRuns(edit)
        edges = edit.entities.grep(Sketchup::Edge).select(&:valid?)
        xform = edit.transformation

        Na__InsertPrimatives.Na__DrawnPipe__Chains(edges).map do |run|
            run.merge(:points => run[:points].map { |point| point.transform(xform) })
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Order-Free Fingerprint of the Line, in the Pipe's Space
    # ------------------------------------------------------------
    # Rounded to 1e-4" so float noise is not an edit; FNV-1a so it needs no
    # library and reads the same in every session.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditFingerprint(edit)
        xform    = edit.transformation
        segments = edit.entities.grep(Sketchup::Edge).select(&:valid?).map do |edge|
            a = Na__InsertPrimatives.Na__DrawnPipe__EditPointKey(edge.start.position.transform(xform))
            b = Na__InsertPrimatives.Na__DrawnPipe__EditPointKey(edge.end.position.transform(xform))
            a < b ? "#{a}>#{b}" : "#{b}>#{a}"
        end

        hash = 0xcbf29ce484222325
        segments.sort.join('|').each_byte do |byte|
            hash ^= byte
            hash = (hash * 0x100000001b3) & 0xffffffffffffffff
        end

        format('%016x', hash)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Point as a Rounded Text Key
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditPointKey(point)
        [point.x, point.y, point.z].map do |value|
            rounded = value.to_f.round(4)
            format('%.4f', rounded.zero? ? 0.0 : rounded)
        end.join(',')
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Finishing
    # -----------------------------------------------------------------------------

    # FUNCTION | Rebuild the Pipe From Its Line and Take the Line Away
    # ------------------------------------------------------------
    # The caller has made sure the pipe is closed. `transparent` joins the
    # rebuild to the user's last edit (the sweep); a Finish chosen from a menu
    # is its own step. Returns { :ok, :message }.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditFinish(pipe, transparent)
        model = Sketchup.active_model
        edit  = Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(pipe)
        return { :ok => false, :message => 'that pipe has no path being edited' } unless model && edit

        spec   = Na__InsertPrimatives.Na__DrawnPipe__StoredSpec(pipe)
        stored = Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(pipe)
        runs   = Na__InsertPrimatives.Na__DrawnPipe__EditRuns(edit)
        print  = Na__InsertPrimatives.Na__DrawnPipe__EditFingerprint(edit)
        same   = print && print == edit.get_attribute(NA_DRAWN_PIPE_EDIT_DICT, 'Baseline')

        if runs.empty? || same
            note = runs.empty? ? 'the red path was erased, so it keeps the route it had' : 'path unchanged'
            return Na__InsertPrimatives.Na__DrawnPipe__EditRestore(model, pipe, spec, transparent, "#{pipe.name}: #{note}")
        end

        key = Na__InsertPrimatives.Na__DrawnPipe__EditKey(pipe)
        return { :ok => false, :message => 'that path was refused already — change it, or Discard' } if key && @na_pipe_edit_failed[key] == print

        # Solved before any operation starts: a transparent operation is never
        # aborted, because that would take the user's last edit with it.
        ordered = runs.sort_by { |run| -Na__InsertPrimatives.Na__DrawnPipe__RunLength(run) }
        solves  = ordered.map { |run| Na__InsertPrimatives.Na__DrawnPipe__Solve(run, spec, stored[:up]) }

        unless solves.first[:ok]
            @na_pipe_edit_failed[key] = print if key
            message = "#{pipe.name}: the red path cannot be piped — #{solves.first[:message]}. It is kept: fix it, Discard, or Ctrl+Z"
            Sketchup::set_status_text(message, SB_PROMPT)
            return { :ok => false, :message => message }
        end

        @na_pipe_edit_busy = true
        model.start_operation('Edit Pipework Path', true, false, transparent)
        Na__InsertPrimatives.Na__DrawnPipe__RebuildSolved(pipe, solves.first, spec, stored[:caps])

        extra   = solves.drop(1).select { |solved| solved[:ok] }
        refused = solves.length - 1 - extra.length
        made    = extra.map { |solved| Na__InsertPrimatives.Na__DrawnPipe__CreateSibling(pipe, solved, spec, stored[:up], stored[:caps]) }.compact
        model.commit_operation

        @na_pipe_edit_failed.delete(key) if key
        Na__InsertPrimatives.Na__DrawnPipe__EditUnwatch(edit)

        message = "#{pipe.name} rebuilt along its new path"
        message += " — #{made.length} more run#{made.length == 1 ? '' : 's'} built as pipe#{made.length == 1 ? '' : 's'} of their own" unless made.empty?
        message += " (#{refused} could not be piped)" if refused > 0
        message += " — #{solves.first[:warnings].length} bend#{solves.first[:warnings].length == 1 ? '' : 's'} adjusted to fit" unless solves.first[:warnings].empty?
        Sketchup::set_status_text(message, SB_PROMPT)
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: #{message}"
        solves.first[:warnings].each { |warning| Na__InsertPrimatives.Na__Debug__Puts "Fitted: #{warning}" }

        { :ok => true, :message => message, :pipes => [pipe] + made }
    rescue StandardError => error
        model.commit_operation rescue nil
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: finishing failed — #{error.message}"
        { :ok => false, :message => "finishing the path failed — #{error.message}" }
    ensure
        @na_pipe_edit_busy = false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild a Pipe From Its Stored Route (the Line Goes With It)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditRestore(model, pipe, spec, transparent, message)
        edit   = Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(pipe)
        stored = Na__InsertPrimatives.Na__DrawnPipe__StoredRoute(pipe)
        solved = Na__InsertPrimatives.Na__DrawnPipe__Solve(stored, spec, stored[:up])
        return { :ok => false, :message => "#{pipe.name} cannot be rebuilt — #{solved[:message]}" } unless solved[:ok]

        @na_pipe_edit_busy = true
        model.start_operation(transparent ? 'Edit Pipework Path' : 'Discard Pipework Path Edit', true, false, transparent)
        Na__InsertPrimatives.Na__DrawnPipe__RebuildSolved(pipe, solved, spec, stored[:caps])
        model.commit_operation

        Na__InsertPrimatives.Na__DrawnPipe__EditUnwatch(edit) if edit
        Sketchup::set_status_text(message, SB_PROMPT)
        { :ok => true, :message => message, :pipes => [pipe] }
    rescue StandardError => error
        model.commit_operation rescue nil
        { :ok => false, :message => "restoring the pipe failed — #{error.message}" }
    ensure
        @na_pipe_edit_busy = false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Finish Now: Step Out of the Pipe and Rebuild (Its Own Undo Step)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditFinishNow(pipe)
        model = Sketchup.active_model
        return { :ok => false, :message => 'no model is open' } unless model
        return { :ok => false, :message => "#{pipe.name} could not be closed — click outside it" } unless Na__InsertPrimatives.Na__DrawnPipe__LeavePipe(model, pipe)

        result = Na__InsertPrimatives.Na__DrawnPipe__EditFinish(pipe, false)
        Na__InsertPrimatives.Na__DrawnPipe__EditSelect(model, result[:pipes]) if result[:ok]
        result
    end
    # ---------------------------------------------------------------

    # FUNCTION | Discard: the Pipe Keeps Its Route, the Line Goes
    # Its own undo step, so Ctrl+Z brings the line back to carry on with.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditDiscard(pipe)
        model = Sketchup.active_model
        return { :ok => false, :message => 'no model is open' } unless model && Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(pipe)
        return { :ok => false, :message => "#{pipe.name} could not be closed — click outside it" } unless Na__InsertPrimatives.Na__DrawnPipe__LeavePipe(model, pipe)

        spec   = Na__InsertPrimatives.Na__DrawnPipe__StoredSpec(pipe)
        result = Na__InsertPrimatives.Na__DrawnPipe__EditRestore(model, pipe, spec, false, "#{pipe.name}: path edit discarded — it keeps the route it had")
        Na__InsertPrimatives.Na__DrawnPipe__EditSelect(model, result[:pipes]) if result[:ok]
        result
    end
    # ---------------------------------------------------------------

    # FUNCTION | Leave What Was Finished Selected
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditSelect(model, pipes)
        live = Array(pipes).select { |pipe| pipe && pipe.valid? }
        return if live.empty?

        model.selection.clear
        model.selection.add(live)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Run's Length Along Its Points (Loops Closed)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__RunLength(run)
        points = run[:points]
        total  = 0.0
        points.each_cons(2) { |a, b| total += a.distance(b).to_f }
        total += points.last.distance(points.first).to_f if run[:closed] && points.length > 2
        total
    end
    # ---------------------------------------------------------------

    # FUNCTION | Say an Edit's Outcome on the Status Line
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditSay(ok, message)
        Sketchup::set_status_text("Pipework: #{message}", SB_PROMPT)
        { :ok => ok, :message => message }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Line Is Out: Say What to Do With It
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditOpened(model, pipe, state)
        Na__InsertPrimatives.Na__DrawnPipe__EditSay(
            true,
            "the path of #{pipe.name} #{state}. Move points, draw on with Line, erase legs — any tool. " \
            'Click outside the pipe to rebuild it; right-click for Finish or Discard.'
        )
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Sweep (Finishing on Leaving)
    # -----------------------------------------------------------------------------

    # FUNCTION | Watch a Red Line So Leaving It Is Noticed
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditWatch(edit)
        key = Na__InsertPrimatives.Na__DrawnPipe__EditKey(edit)
        @na_pipe_edit_watched[key] = edit if key
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stop Watching a Line (and Forget Any That Are Gone)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditUnwatch(edit)
        @na_pipe_edit_watched.delete_if { |_key, group| group.equal?(edit) || !(group.valid? rescue false) }
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Lines Being Watched
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditWatched
        @na_pipe_edit_watched.delete_if { |_key, group| !(group.valid? rescue false) }
        @na_pipe_edit_watched.values
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Stable Key for a Group: Its Persistent Id
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditKey(entity)
        return nil unless entity && entity.valid?

        entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.object_id
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Coalesce Any Number of Triggers Into One Deferred Sweep
    # ------------------------------------------------------------
    # From a UI timer, so the model is never changed inside an observer
    # callback. One passive trigger in the window makes the whole sweep
    # passive.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditSchedule(reason, full = true)
        return if @na_pipe_edit_busy

        @na_pipe_edit_passive = true if NA_DRAWN_PIPE_PASSIVE_REASONS.include?(reason.to_s)
        @na_pipe_edit_full    = true if full
        return if @na_pipe_edit_timer

        @na_pipe_edit_timer = UI.start_timer(NA_DRAWN_PIPE_SWEEP_DELAY, false) do
            @na_pipe_edit_timer = nil
            run_full     = @na_pipe_edit_full
            run_passive  = @na_pipe_edit_passive
            @na_pipe_edit_full    = false
            @na_pipe_edit_passive = false
            Na__InsertPrimatives.Na__DrawnPipe__EditSweepNow(run_full, run_passive)
        end
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: sweep schedule failed — #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Sweep: Watch What Is Out, Finish What Was Left
    # ------------------------------------------------------------
    #   full     also look for lines left in the model (an undo brought one
    #            back, a model was saved mid-edit), via the group definitions,
    #            which costs one pass over definitions, not over geometry
    #   passive  look only: after an undo or redo, or a model opening, the
    #            line waits for the user's next change and joins it
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditSweepNow(full = true, passive = false)
        model = Sketchup.active_model
        return unless model
        return if @na_pipe_edit_busy

        open = Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(model)
        Na__InsertPrimatives.Na__DrawnPipe__EditWatch(open[:edit]) if open
        Na__InsertPrimatives.Na__DrawnPipe__EditLeftInModel(model).each { |edit| Na__InsertPrimatives.Na__DrawnPipe__EditWatch(edit) } if full
        return if passive

        Na__InsertPrimatives.Na__DrawnPipe__EditWatched.each do |edit|
            Na__InsertPrimatives.Na__DrawnPipe__EditFinishIfLeft(model, edit)
        end
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: sweep failed — #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Red Line Group in the Model
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditLeftInModel(model)
        found = []

        model.definitions.each do |definition|
            next unless definition.respond_to?(:group?) && definition.group?

            definition.instances.each do |instance|
                found << instance if Na__InsertPrimatives.Na__DrawnPipe__IsEditGroup?(instance)
            end
        end

        found
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Finish One Line If the User Has Left Its Pipe
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditFinishIfLeft(model, edit)
        return Na__InsertPrimatives.Na__DrawnPipe__EditUnwatch(edit) unless Na__InsertPrimatives.Na__DrawnPipe__IsEditGroup?(edit)

        pipe = Na__InsertPrimatives.Na__DrawnPipe__PipeOfEdit(edit)
        return Na__InsertPrimatives.Na__DrawnPipe__EditUnwatch(edit) unless pipe                  # <-- Exploded or deleted: not ours to finish
        return if Na__InsertPrimatives.Na__DrawnPipe__InsideEdit?(model, pipe, edit)               # <-- Still editing: leaving re-triggers this

        Na__InsertPrimatives.Na__DrawnPipe__EditFinish(pipe, true)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Observers
    # -----------------------------------------------------------------------------

    # FUNCTION | Install the App and Model Observers Once
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditInstall
        Na__InsertPrimatives.Na__DrawnPipe__EditUninstall

        @na_pipe_app_observer = DrawnPipeEditAppObserver.new
        Sketchup.add_observer(@na_pipe_app_observer)

        model = Sketchup.active_model
        Na__InsertPrimatives.Na__DrawnPipe__EditAttachModel(model) if model
        Na__InsertPrimatives.Na__DrawnPipe__EditSchedule('install', true)
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: observers not installed — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are the Observers Installed?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditInstalled?
        !@na_pipe_app_observer.nil?
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remove the Observers (Before Installing Again)
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditUninstall
        Sketchup.remove_observer(@na_pipe_app_observer) rescue nil if @na_pipe_app_observer
        @na_pipe_app_observer = nil
        Na__InsertPrimatives.Na__DrawnPipe__EditDetachModel
        Na__InsertPrimatives.Na__DrawnPipe__UnwatchModel if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__UnwatchModel)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Watch a Model: Its Observer, Its Selection and Its Overlay
    # ------------------------------------------------------------
    # One model at a time, the one being worked in: SketchUp 2027 opens
    # several in tabs, and the app observer moves the watch on each switch.
    # Attaching the model already watched is a no-op, so the overlapping
    # new-model and activate-model calls cannot double an observer.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditAttachModel(model)
        return unless model

        unless model.equal?(@na_pipe_observed_model) && @na_pipe_model_observer
            Na__InsertPrimatives.Na__DrawnPipe__EditDetachModel

            @na_pipe_model_observer = DrawnPipeEditModelObserver.new
            @na_pipe_observed_model = model
            model.add_observer(@na_pipe_model_observer)
        end

        Na__InsertPrimatives.Na__DrawnPipe__WatchModel(model) if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__WatchModel)
        Na__InsertPrimatives.Na__DrawnPipe__OverlayFor(model) if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__OverlayFor)
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: model observer not attached — #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Model Was Closed: Forget It, Without Touching It
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditModelClosed(model)
        if model && model.equal?(@na_pipe_observed_model)
            @na_pipe_model_observer = nil
            @na_pipe_observed_model = nil
        end

        Na__InsertPrimatives.Na__DrawnPipe__WatchClosed(model) if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__WatchClosed)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stop Watching the Model Watched Before
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__EditDetachModel
        @na_pipe_observed_model.remove_observer(@na_pipe_model_observer) rescue nil if @na_pipe_observed_model && @na_pipe_model_observer
        @na_pipe_model_observer = nil
        @na_pipe_observed_model = nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Right-Click Menu
    # -----------------------------------------------------------------------------

    # FUNCTION | Register the Context Menu Handler Once
    # ------------------------------------------------------------
    # UI.add_context_menu_handler has no remove, so this is guarded against
    # Reload Plugin Data; the handler calls a module function, so a reload
    # still changes what it does.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__ContextMenuRegister
        return false if @na_pipe_menu_added

        UI.add_context_menu_handler { |menu| Na__InsertPrimatives.Na__DrawnPipe__ContextMenu(menu) }
        @na_pipe_menu_added = true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: context menu not registered — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build the Pipework Items Into a Right-Click Menu
    # ------------------------------------------------------------
    #   standing in an edit    Finish / Discard / Pipework Options
    #   one pipe selected      Edit Pipework Path (or Finish / Discard for a
    #                          line left waiting) and Pipework Options
    #   several pipes          Pipework Options, to resize them all
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__ContextMenu(menu)
        model = Sketchup.active_model
        return unless model
        return if Na__InsertPrimatives.Na__DrawnPipe__MenuAlreadyBuilt?(menu)

        open = Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(model)

        if open
            menu.add_separator
            Na__InsertPrimatives.Na__DrawnPipe__MenuFinishItems(menu, open[:pipe])
            menu.add_item('Pipework Options...') { Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPipeTool }
            return
        end

        pipes = model.selection.to_a.select { |entity| Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(entity) }
        return if pipes.empty?

        menu.add_separator

        if pipes.length == 1
            pipe = pipes.first

            if Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(pipe)
                Na__InsertPrimatives.Na__DrawnPipe__MenuFinishItems(menu, pipe)
            else
                menu.add_item('Edit Pipework Path') { Na__InsertPrimatives.Na__InsertPrimatives__EditPipePath }
            end
        end

        label = pipes.length == 1 ? 'Pipework Options...' : "Pipework Options (#{pipes.length} pipes)..."
        menu.add_item(label) { Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPipeTool }
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "DRAWN PIPE EDIT: menu failed — #{error.message}"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Finish and Discard, for a Line Out or Waiting
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__MenuFinishItems(menu, pipe)
        menu.add_item('Finish Pipework Path')       { Na__InsertPrimatives.Na__DrawnPipe__EditFinishNow(pipe) }
        menu.add_item('Discard Pipework Path Edit') { Na__InsertPrimatives.Na__DrawnPipe__EditDiscard(pipe) }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Has This Popup Been Given Our Items Already?
    # A handler a previous code version leaked before the guard would build
    # the same section twice; this dedupes per popup.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__MenuAlreadyBuilt?(menu)
        marker = menu.object_id
        now    = Time.now.to_f
        return true if @na_pipe_menu_marker == marker && (now - @na_pipe_menu_time) < 2.0

        @na_pipe_menu_marker = marker
        @na_pipe_menu_time   = now
        false
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Points (Extensions Menu, Shortcuts)
    # -----------------------------------------------------------------------------

    # FUNCTION | Edit the Path of the Selected Pipe, With the Bar Up
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__EditPipePath
        model = Sketchup.active_model
        return false unless model

        pipes = model.selection.to_a.select { |entity| Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(entity) }
        unless pipes.length == 1
            Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, 'select one pipe to edit its path')
            return false
        end

        result = Na__InsertPrimatives.Na__DrawnPipe__EditOpen(pipes.first)
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPipeTool if result[:ok]
        result[:ok]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Finish the Path Edit the User Is In (or the Selected Pipe's)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__FinishPipePath
        model = Sketchup.active_model
        return false unless model

        open = Na__InsertPrimatives.Na__DrawnPipe__OpenEdit(model)
        pipe = open ? open[:pipe] : model.selection.to_a.find { |entity| Na__InsertPrimatives.Na__DrawnPipe__EditGroupOf(entity) }

        unless pipe
            Na__InsertPrimatives.Na__DrawnPipe__EditSay(false, 'no pipe path is being edited')
            return false
        end

        Na__InsertPrimatives.Na__DrawnPipe__EditFinishNow(pipe)[:ok]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # REGION | Observer Classes
    # =============================================================================
    # Callbacks only SCHEDULE the sweep; none of them touches the model.

    # CLASS | Models Opened, Created or Switched To
    # ------------------------------------------------------------
    class DrawnPipeEditAppObserver < Sketchup::AppObserver
        def expectsStartupModelNotifications
            true
        end

        def onNewModel(model);      na_pipe__model_changed(model); end
        def onOpenModel(model);     na_pipe__model_changed(model); end
        def onActivateModel(model); na_pipe__model_changed(model); end
        def onCloseModel(model);    na_pipe__model_closed(model);  end         # <-- SketchUp 2027: a tab closed

        def na_pipe__model_changed(model)
            Na__InsertPrimatives.Na__DrawnPipe__EditAttachModel(model)
            Na__InsertPrimatives.Na__DrawnPipe__EditSchedule('model-changed', true)
        rescue StandardError
            nil
        end

        def na_pipe__model_closed(model)
            Na__InsertPrimatives.Na__DrawnPipe__EditModelClosed(model)
        rescue StandardError
            nil
        end
    end
    # ---------------------------------------------------------------

    # CLASS | The Moments a Red Line Is Read (and the Bar's Count Goes Stale)
    # ------------------------------------------------------------
    # A transaction may resize a selected pipe without the selection moving,
    # so the bar on selection is told too (DrawnPipe__Watch__).
    # ------------------------------------------------------------
    class DrawnPipeEditModelObserver < Sketchup::ModelObserver
        def onActivePathChanged(_model)
            Na__InsertPrimatives.Na__DrawnPipe__EditSchedule('active-path-changed', true)
            na_pipe__bar_stale
        rescue StandardError
            nil
        end

        def onTransactionCommit(_model)
            Na__InsertPrimatives.Na__DrawnPipe__EditSchedule('commit', false)
            na_pipe__bar_stale
        rescue StandardError
            nil
        end

        def onTransactionUndo(_model)
            Na__InsertPrimatives.Na__DrawnPipe__EditSchedule('undo', true)
            na_pipe__bar_stale
        rescue StandardError
            nil
        end

        def onTransactionRedo(_model)
            Na__InsertPrimatives.Na__DrawnPipe__EditSchedule('redo', true)
            na_pipe__bar_stale
        rescue StandardError
            nil
        end

        def na_pipe__bar_stale
            Na__InsertPrimatives.Na__DrawnPipe__WatchStale if Na__InsertPrimatives.respond_to?(:Na__DrawnPipe__WatchStale)
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module


# =============================================================================
# SECTION | Install at Load (guarded: once, even across Reload Plugin Data)
# =============================================================================
# A path edit must finish in every session, whether or not the tool is ever
# opened, so the observers and the menu go in when the plugin loads.

Na__InsertPrimatives.Na__DrawnPipe__ContextMenuRegister

unless Na__InsertPrimatives.Na__DrawnPipe__EditInstalled?
    UI.start_timer(0.5, false) do
        begin
            Na__InsertPrimatives.Na__DrawnPipe__EditInstall unless Na__InsertPrimatives.Na__DrawnPipe__EditInstalled?
        rescue StandardError => error
            puts "[Na__InsertPrimatives][WARN] Pipework edit observers not installed: #{error.message}"
        end
    end
end

# =============================================================================
# END OF DRAWN PIPE EDIT PATH
# =============================================================================
