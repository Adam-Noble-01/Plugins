# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE DRAW
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Draw__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnPipeDraw
# AUTHOR     : Noble Architecture
# PURPOSE    : Drawing a pipe run point by point, the way the Line tool draws
# CREATED    : 2026
#
# DESCRIPTION:
# - Mixed into DrawnPipeTool, for when nothing usable was selected. Click the
#   start, then click every turn; the pipe is on the cursor the whole time,
#   bends and all, so the bend at the last corner forms as the next leg is
#   swung round.
# - Finish with Enter, a double click, or a click on the last point again.
#   A click on the FIRST point closes the run into a loop. ESC drops the run;
#   BKSP takes back the last point.
#
# WHERE THE CURSOR IS:
#   free          SketchUp's inference from the last point (on-axis, endpoints,
#                 faces...), rounded onto the plugin's grid
#   ARROWS        locked to the drawing axis through the last point: Right red,
#                 Left green, Up blue, Down (or the same arrow) releases.
#                 Released by each click, since the next leg runs another way
#   SHIFT         locked to the leg's direction as it stands, while held
#   TAB           the run held to a plane through the last point: XY plan,
#                 XZ front, YZ side, then free again (SHIFT+TAB steps back).
#                 Kept through the clicks; an arrow or SHIFT lock wins while on
#   CTRL          exact, no grid; CTRL+SHIFT rounds it. CTRL KEEPS a lock
# - A locked leg snaps its LENGTH to the grid rather than the point, so a run
#   that started off the grid (CTRL on a vertex) stays square to its axis.
#
# IN LINE WITH (5.2.11) — a lock still looks at what is under the cursor:
#   a vertex      (midpoint, intersection, guide point) the leg stops square
#                 across from it, exactly. Always, CTRL or not
#   an edge       with CTRL: where the lock passes the edge (a TAB plane:
#                 where the edge pierces it)
#   a face        with CTRL: where the lock line pierces the face's plane
#   A dotted guide joins the leg's end to what it lines up with, and the
#   status line names it. Picked geometry is read in its own coordinates and
#   carried to world, then checked against the picked point (always world),
#   so a wrong space is refused rather than aimed at.
#
# TYPED WHILE DRAWING (the grammar is in DrawnPipe__Spec__):
#   1200          the leg on the cursor, 1200 long, the way it is pointing
#   [x,y,z]       the next point there, in the drawing axes, mm
#   <dx,dy,dz>    the next point that far along the drawing axes, mm
#   80,110,24s    change the pipe without losing the run
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPipe__Spec__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Solver__'

module Na__InsertPrimatives

    # =============================================================================
    # MODULE | Drawn Pipe — Draw a Run Point by Point
    # =============================================================================

    module DrawnPipeDraw

        NA_PIPE_CLOSE_PIXELS = 10.0                                           # <-- A click this near the first point closes the loop
        NA_PIPE_AIM_TOL      = 0.01                                           # <-- Inches: the picked point must sit this near a candidate world line or plane
        NA_PIPE_AIM_MIN_DOT  = 0.05                                           # <-- A line this near lying in a plane never meets it usefully
        NA_PIPE_AIM_MAX_DOT  = 0.98                                           # <-- An edge this near parallel with the lock has no crossing to speak of
        NA_PIPE_EDGE_ON_DOT  = 0.02                                           # <-- A TAB plane seen this near edge-on gives no ray answer
        NA_PIPE_PLANE_PIXELS = 90.0                                           # <-- Half the side of the TAB plane's square, on screen

        # -----------------------------------------------------------------------------
        # REGION | Run State
        # -----------------------------------------------------------------------------

        # FUNCTION | Forget the Run Being Drawn
        # ------------------------------------------------------------
        def na_pipe__reset_run
            @na_pipe_points  = []
            @na_pipe_ip_last = nil
            @na_pipe_dir     = nil
            @na_pipe_live    = nil
            @na_pipe_aim     = nil
            @na_axis_lock    = nil
            @na_state        = :idle
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Run Under Way?
        # ------------------------------------------------------------
        def na_pipe__drawing?
            @na_state == :drawing && !@na_pipe_points.empty?
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Cursor
        # -----------------------------------------------------------------------------

        # FUNCTION | Resolve Where the Next Point Would Go
        # ------------------------------------------------------------
        #   a lock line   (arrow, SHIFT)  the point stays on it
        #   a lock plane  (TAB)           the point stays in it
        #   neither                       SketchUp's inference, on the grid
        # A lock line wins over the plane while it is on. Both still look at
        # what is under the cursor and stop the leg in line with it.
        # ------------------------------------------------------------
        def na_pipe__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y
            @na_pipe_aim     = nil

            point = na_pipe__locked_point(view, x, y)
            point ||= na_pipe__plane_point(view, x, y) unless na_pipe__lock_line
            point ||= na_pipe__inferred_point(view, x, y)

            @na_pipe_cursor = point
            na_pipe__refresh_live
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cursor on a Lock Line
        # ------------------------------------------------------------
        # In line with what is under the cursor when there is something to line
        # up with: exact, as SketchUp's own inference is, and CTRL+SHIFT rounds
        # it along the line. Otherwise where the pick ray passes the line, its
        # LENGTH on the grid (exact with CTRL).
        # ------------------------------------------------------------
        def na_pipe__locked_point(view, x, y)
            line = na_pipe__lock_line
            return nil unless line

            origin, direction = line
            aimed = na_pipe__aim_on_line(na_pipe__aim_target(na_pipe__pick(view, x, y)), origin, direction)

            if aimed
                along = (aimed[:point] - origin).dot(direction)
                along = Na__InsertPrimatives.Na__DrawnGrid__SnapDistance(along) if na_drawn__snap_mode == :vertex_grid
                return na_pipe__take_aim(aimed, na_pipe__along(origin, direction, along))
            end

            ray     = view.pickray(x, y)
            closest = Geom.closest_points([origin, direction], ray)
            return nil unless closest && closest[0] && na_drawn__point_in_front_of_ray?(ray, closest[0])

            along = na_drawn__snap_distance((closest[0] - origin).dot(direction))
            na_pipe__along(origin, direction, along)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cursor in the TAB Plane Through the Last Point
        # ------------------------------------------------------------
        # In line with a vertex (or, with CTRL, an edge) under the cursor,
        # straight across the plane from it. Otherwise where the pick ray meets
        # the plane, rounded onto the grid (exact with CTRL) and laid back into
        # the plane, which the grid need not pass through. A plane seen edge-on
        # meets the ray nowhere useful, so SketchUp's own point is laid in.
        # ------------------------------------------------------------
        def na_pipe__plane_point(view, x, y)
            plane = na_pipe__lock_plane
            return nil unless plane

            origin, normal = plane
            picked = na_pipe__pick(view, x, y)
            aimed  = na_pipe__aim_on_plane(na_pipe__aim_target(picked), origin, normal)

            if aimed
                rounded = aimed[:point]
                rounded = na_pipe__onto_plane(Na__InsertPrimatives.Na__DrawnGrid__SnapPoint(rounded), origin, normal) if na_drawn__snap_mode == :vertex_grid
                return na_pipe__take_aim(aimed, rounded)
            end

            ray = view.pickray(x, y)
            hit = nil
            if ray[1].normalize.dot(normal).abs > NA_PIPE_EDGE_ON_DOT
                hit = Geom.intersect_line_plane(ray, [origin, normal])
                hit = nil unless na_drawn__point_in_front_of_ray?(ray, hit)
            end
            hit ||= picked.position if picked && picked.valid?
            return nil unless hit

            na_pipe__onto_plane(na_drawn__snap_point(hit), origin, normal)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | SketchUp's Inference From the Last Point, Then the Grid
        # ------------------------------------------------------------
        def na_pipe__inferred_point(view, x, y)
            picked   = na_pipe__pick(view, x, y)
            position = picked ? picked.position : nil
            return nil unless position

            @na_cursor_raw     = position
            @na_cursor_snapped = na_drawn__snap_point(position)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pick the InputPoint Under the Cursor, Inferring From the Last Point
        # ------------------------------------------------------------
        def na_pipe__pick(view, x, y)
            reference = na_pipe__drawing? ? @na_pipe_ip_last : nil

            if reference && reference.valid?
                @na_ip.pick(view, x, y, reference)
            else
                @na_ip.pick(view, x, y)
            end

            @na_ip
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Line the Next Point Is Held To, or nil
        # ------------------------------------------------------------
        def na_pipe__lock_line
            last = @na_pipe_points.last
            return nil unless last

            if @na_axis_lock
                axis = Na__InsertPrimatives.Na__DrawnGrid__AxisVector(@na_axis_lock)
                return [last, axis.normalize] if axis
            end

            return [last, @na_pipe_dir] if @na_pipe_dir

            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane the Next Point Is Held To (TAB), or nil
        # ------------------------------------------------------------
        def na_pipe__lock_plane
            return nil if @na_plane_lock.nil? || @na_plane_lock == :auto
            return nil unless na_pipe__drawing?

            _u_axis, _v_axis, normal = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_lock)
            return nil unless normal && normal.length.to_f > 0.0

            [@na_pipe_points.last, normal.normalize]
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB: the Next Plane in the Cycle; SHIFT+TAB the One Before
        # ------------------------------------------------------------
        # Free, XY plan, XZ front, YZ side, each through the last point. Kept
        # through the clicks, so a whole run can keep to one plane.
        # ------------------------------------------------------------
        def na_pipe__cycle_plane(step)
            cycle          = Na__InsertPrimatives::DrawnToolShared::NA_DRAWN_PLANE_LOCK_CYCLE
            index          = cycle.index(@na_plane_lock) || 0
            @na_plane_lock = cycle[(index + step) % cycle.length]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a TAB Plane Chosen (Whether or Not a Run Is Under Way)?
        # ------------------------------------------------------------
        def na_pipe__plane_chosen?
            !@na_plane_lock.nil? && @na_plane_lock != :auto
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lock to the Leg's Direction While SHIFT Is Held
        # ------------------------------------------------------------
        # Called after every change of the held keys. Not with CTRL down:
        # CTRL+SHIFT is the vertex-to-grid snap. Not over an arrow lock, which
        # already holds the leg to a line.
        # ------------------------------------------------------------
        def na_pipe__sync_direction_lock
            wanted = @na_shift_held && !@na_ctrl_held && @na_axis_lock.nil? && na_pipe__drawing?

            if !wanted
                @na_pipe_dir = nil
            elsif @na_pipe_dir.nil?
                @na_pipe_dir = na_pipe__free_direction
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Way the Leg Points: the Lock, Else the Cursor
        # ------------------------------------------------------------
        # A lock line points whichever way the cursor lies along it, so typing a
        # length with the cursor behind the last point runs the leg backwards.
        # ------------------------------------------------------------
        def na_pipe__leg_direction
            line   = na_pipe__lock_line
            toward = na_pipe__free_direction
            return toward unless line

            direction = line[1]
            return direction.reverse if toward && toward.dot(direction) < 0.0

            direction
        end
        # ---------------------------------------------------------------

        # FUNCTION | Unit Vector From the Last Point to the Cursor, or nil
        # ------------------------------------------------------------
        def na_pipe__free_direction
            last = @na_pipe_points.last
            return nil unless last && @na_pipe_cursor

            vector = @na_pipe_cursor - last
            return nil unless vector.length.to_f > NA_DRAWN_PIPE_MERGE_TOL

            vector.normalize
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point a Signed Distance Along a Direction
        # ------------------------------------------------------------
        def na_pipe__along(origin, direction, distance)
            Geom::Point3d.new(
                origin.x.to_f + direction.x.to_f * distance,
                origin.y.to_f + direction.y.to_f * distance,
                origin.z.to_f + direction.z.to_f * distance
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Long the Leg on the Cursor Is
        # ------------------------------------------------------------
        def na_pipe__leg_length
            last = @na_pipe_points.last
            return 0.0 unless last && @na_pipe_cursor

            last.distance(@na_pipe_cursor).to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point Laid Square Onto a Line
        # ------------------------------------------------------------
        def na_pipe__onto_line(point, origin, direction)
            na_pipe__along(origin, direction, (point - origin).dot(direction))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point Laid Square Into a Plane
        # ------------------------------------------------------------
        def na_pipe__onto_plane(point, origin, normal)
            na_pipe__along(point, normal, -(point - origin).dot(normal))
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | In Line With What Is Under the Cursor
        # -----------------------------------------------------------------------------

        # FUNCTION | What the InputPoint Found That a Locked Leg Can Line Up With
        # ------------------------------------------------------------
        #   :point  pinned to one place: a vertex, a midpoint, an intersection,
        #           a guide point. Always taken: this is the line-up a lock is for
        #   :line   an edge or a guide line, with CTRL: its line, in world
        #   :face   a face, with CTRL: its plane, in world
        # SketchUp's own inference along an axis from the last point has no
        # entity under it and nothing to line up with, so it is no target.
        # Without CTRL a lock passes over edges and faces and keeps the grid.
        # ------------------------------------------------------------
        def na_pipe__aim_target(picked)
            return nil unless picked && picked.valid?

            position = picked.position
            leaf     = na_pipe__picked_leaf(picked)
            guide    = leaf.is_a?(Sketchup::ConstructionPoint) || leaf.is_a?(Sketchup::ConstructionLine)
            return nil unless position && (picked.vertex || picked.edge || picked.face || guide)

            target  = { :position => position, :tooltip => picked.tooltip.to_s }
            freedom = picked.degrees_of_freedom.to_i
            return target.merge(:kind => :point) if freedom == 0 || picked.vertex
            return nil unless @na_ctrl_held

            if freedom == 1
                line = na_pipe__world_line(picked, picked.edge, leaf)
                return target.merge(:kind => :line, :line => line) if line
            end

            face = picked.face
            if face && freedom == 2
                plane = na_pipe__world_plane(picked, face)
                return target.merge(:kind => :face, :plane => plane) if plane
            end

            nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Entity at the End of the Pick's Instance Path, or nil
        # ------------------------------------------------------------
        def na_pipe__picked_leaf(picked)
            return nil unless picked.respond_to?(:instance_path)

            path = picked.instance_path
            path ? path.leaf : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Spaces a Picked Entity's Coordinates May Be In, Likeliest First
        # ------------------------------------------------------------
        # The InputPoint's transformation (SketchUp's word for it), the pick's
        # instance path, and none at all: geometry in the open group reads in
        # world already. Each is tried against the picked point, never trusted.
        # ------------------------------------------------------------
        def na_pipe__aim_spaces(picked)
            spaces = [picked.transformation]

            begin
                path = picked.respond_to?(:instance_path) ? picked.instance_path : nil
                spaces << path.transformation if path
            rescue StandardError
                nil
            end

            spaces << Geom::Transformation.new
            spaces.compact
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Edge's or Guide Line's Line in World, or nil
        # ------------------------------------------------------------
        # Read in the entity's own coordinates and carried out by each space in
        # turn, kept only if the picked point (world, always) lies on it: a
        # space that misses is the wrong one. nil when none fits — better no
        # aim than a wrong one. An edge keeps its length, so a lock is only
        # lined up where it passes the edge itself; a guide line is endless.
        # ------------------------------------------------------------
        def na_pipe__world_line(picked, edge, leaf)
            local =
                if edge
                    [edge.start.position, edge.end.position, true]
                elsif leaf.is_a?(Sketchup::ConstructionLine)
                    [leaf.position, leaf.position.offset(leaf.direction), false]
                end
            return nil unless local

            position = picked.position

            na_pipe__aim_spaces(picked).each do |space|
                start  = local[0].transform(space)
                finish = local[1].transform(space)
                length = start.distance(finish).to_f
                next unless length > 0.0

                direction = (finish - start).normalize
                next unless (position - start).cross(direction).length.to_f <= NA_PIPE_AIM_TOL  # <-- How far the picked point sits off this line

                return { :origin => start, :direction => direction, :length => local[2] ? length : nil }
            end

            nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Face's Plane in World, or nil — Checked the Same Way
        # ------------------------------------------------------------
        # From the outer loop's points carried out to world, not from the
        # normal: a scaled group's points carry out by its transformation, its
        # normals do not.
        # ------------------------------------------------------------
        def na_pipe__world_plane(picked, face)
            local = face.outer_loop.vertices.map(&:position)
            return nil if local.length < 3

            position = picked.position

            na_pipe__aim_spaces(picked).each do |space|
                points = local.map { |point| point.transform(space) }
                normal = na_pipe__polygon_normal(points)
                next unless normal
                next unless (position - points.first).dot(normal).abs <= NA_PIPE_AIM_TOL

                return [points.first, normal]
            end

            nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Polygon's Unit Normal by Newell's Sum, or nil
        # Concave outlines and a near-straight run of points are no trouble.
        # ------------------------------------------------------------
        def na_pipe__polygon_normal(points)
            nx = ny = nz = 0.0

            points.each_with_index do |a, index|
                b   = points[(index + 1) % points.length]
                nx += (a.y.to_f - b.y.to_f) * (a.z.to_f + b.z.to_f)
                ny += (a.z.to_f - b.z.to_f) * (a.x.to_f + b.x.to_f)
                nz += (a.x.to_f - b.x.to_f) * (a.y.to_f + b.y.to_f)
            end

            normal = Geom::Vector3d.new(nx, ny, nz)
            normal.length.to_f > 1.0e-9 ? normal.normalize : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a Lock Line Lines Up With a Target, or nil
        # ------------------------------------------------------------
        #   :point  square across to the line
        #   :line   where the two pass closest, if that is on the edge itself;
        #           near parallel, or past its ends, square across from the
        #           picked point instead
        #   :face   where the line pierces the face's plane, if it meets it at
        #           a usable angle; nil if not, and the ray decides
        # ------------------------------------------------------------
        def na_pipe__aim_on_line(target, origin, direction)
            return nil unless target

            point = nil

            case target[:kind]
            when :line
                line = target[:line]
                if line[:direction].dot(direction).abs < NA_PIPE_AIM_MAX_DOT
                    closest = Geom.closest_points([origin, direction], [line[:origin], line[:direction]])
                    point   = closest[0] if closest && closest[0] && closest[1] && na_pipe__on_segment?(line, closest[1])
                end
            when :face
                plane_origin, normal = target[:plane]
                return nil unless normal.dot(direction).abs > NA_PIPE_AIM_MIN_DOT

                point = Geom.intersect_line_plane([origin, direction], [plane_origin, normal])
                return nil unless point
            end

            point ||= na_pipe__onto_line(target[:position], origin, direction)
            target.merge(:point => point)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a TAB Plane Lines Up With a Target, or nil
        # ------------------------------------------------------------
        #   :point  straight across the plane from it, along the plane's normal
        #   :line   where the line pierces the plane, if that is on the edge;
        #           otherwise straight across from the picked point
        #   :face   no target here: the pick ray says more about a point in
        #           another plane than a face it happens to cross
        # ------------------------------------------------------------
        def na_pipe__aim_on_plane(target, origin, normal)
            return nil unless target && target[:kind] != :face

            point = nil

            if target[:kind] == :line
                line = target[:line]
                if line[:direction].dot(normal).abs > NA_PIPE_AIM_MIN_DOT
                    hit   = Geom.intersect_line_plane([line[:origin], line[:direction]], [origin, normal])
                    point = hit if hit && na_pipe__on_segment?(line, hit)
                end
            end

            point ||= na_pipe__onto_plane(target[:position], origin, normal)
            target.merge(:point => point)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Point on a Target Line Within the Edge (Any Point of a Guide)?
        # ------------------------------------------------------------
        def na_pipe__on_segment?(line, point)
            return true if line[:length].nil?

            reach = (point - line[:origin]).dot(line[:direction])
            reach >= -NA_PIPE_AIM_TOL && reach <= line[:length] + NA_PIPE_AIM_TOL
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep an Aimed Point as the Cursor; Remember What It Lines Up With
        # ------------------------------------------------------------
        # The exact and the rounded point go where the CTRL+SHIFT grid mark
        # reads them, so the rounding is shown along the lock, not hidden.
        # ------------------------------------------------------------
        def na_pipe__take_aim(aimed, point)
            @na_cursor_raw     = aimed[:point]
            @na_cursor_snapped = point
            @na_pipe_aim       = aimed.merge(:point => point)
            point
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Points In and Out
        # -----------------------------------------------------------------------------

        # FUNCTION | A Click While Drawing
        # ------------------------------------------------------------
        def na_pipe__click(view, x, y)
            na_pipe__update_cursor(view, x, y)
            point = @na_pipe_cursor
            return false unless point

            return na_pipe__begin_run(point) unless na_pipe__drawing?

            if @na_pipe_points.length >= 3 && na_pipe__near_on_screen?(view, x, y, @na_pipe_points.first)
                return na_pipe__finish(view, true)
            end

            return na_pipe__finish(view, false) if point.distance(@na_pipe_points.last).to_f < NA_DRAWN_PIPE_MERGE_TOL

            na_pipe__append(point)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Screen Position Within Reach of a Model Point?
        # ------------------------------------------------------------
        def na_pipe__near_on_screen?(view, x, y, point)
            screen = view.screen_coords(point)
            ((screen.x.to_f - x.to_f)**2 + (screen.y.to_f - y.to_f)**2) <= NA_PIPE_CLOSE_PIXELS**2
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Start a Run at a Point
        # ------------------------------------------------------------
        def na_pipe__begin_run(point)
            @na_pipe_points  = [point]
            @na_pipe_ip_last = Sketchup::InputPoint.new(point)
            @na_pipe_dir     = nil
            @na_state        = :drawing

            na_drawn__disarm_revise                                           # <-- A new run is a new thing: typing now changes it, not the last pipe
            na_pipe__refresh_live
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add the Next Turning Point
        # ------------------------------------------------------------
        # The arrow lock is let go: the next leg runs some other way. The
        # InputPoint reference moves to the new point so inference (on-axis,
        # parallel) is measured from where the run now is.
        # ------------------------------------------------------------
        def na_pipe__append(point)
            @na_pipe_points << point
            @na_pipe_ip_last = Sketchup::InputPoint.new(point)
            @na_axis_lock    = nil
            @na_pipe_dir     = nil

            na_pipe__refresh_live
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Back the Last Point (BKSP)
        # ------------------------------------------------------------
        def na_pipe__step_back
            return false unless na_pipe__drawing?

            @na_pipe_points.pop
            @na_axis_lock = nil
            @na_pipe_dir  = nil

            if @na_pipe_points.empty?
                na_pipe__reset_run
            else
                @na_pipe_ip_last = Sketchup::InputPoint.new(@na_pipe_points.last)
                na_pipe__refresh_live
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Run Drawn So Far
        # ------------------------------------------------------------
        # A run that will not build (one that doubles back, say) is KEPT, so
        # BKSP can take back the point that broke it.
        # ------------------------------------------------------------
        def na_pipe__finish(view, closed)
            points = @na_pipe_points.dup

            if points.length < 2
                UI.beep
                Sketchup::set_status_text('Click at least two points before finishing the run', SB_PROMPT)
                return false
            end

            run   = { :points => points, :closed => closed && points.length >= 3, :smooth => Array.new(points.length, false) }
            built = na_pipe__commit([run], closed ? 'Draw Pipe Loop' : 'Draw Pipe', nil)
            return false if built.empty?

            na_pipe__reset_run
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Typed Lengths and Points
        # -----------------------------------------------------------------------------

        # FUNCTION | A Typed Length: the Leg on the Cursor, That Long
        # ------------------------------------------------------------
        def na_pipe__type_length(token)
            raise ArgumentError, 'click the start of the run first — a number on its own then sets the leg length' unless na_pipe__drawing?

            direction = na_pipe__leg_direction
            raise ArgumentError, 'move the cursor the way the leg should run, then type its length' unless direction

            length = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(token, na_pipe__leg_length)
            raise ArgumentError, 'the leg must be longer than 0' unless length > NA_DRAWN_PIPE_MERGE_TOL

            na_pipe__append(na_pipe__along(@na_pipe_points.last, direction, length))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Point: [x,y,z] Absolute, <dx,dy,dz> From the Last
        # ------------------------------------------------------------
        # Both are read in the DRAWING axes, as the grid is, so a rotated
        # tripod is respected; the result is a world point like every other.
        # ------------------------------------------------------------
        def na_pipe__type_point(entry)
            axes   = Na__InsertPrimatives.Na__DrawnGrid__AxesTransform
            vector = entry[:vector]

            if entry[:mode] == :absolute
                point = Geom::Point3d.new(vector[0], vector[1], vector[2]).transform(axes)
                return na_pipe__begin_run(point) unless na_pipe__drawing?
            else
                raise ArgumentError, 'click the start of the run before typing an offset from it' unless na_pipe__drawing?

                offset = Geom::Vector3d.new(vector[0], vector[1], vector[2]).transform(axes)
                raise ArgumentError, 'that offset is zero — the next point would sit on the last' unless offset.length.to_f > NA_DRAWN_PIPE_MERGE_TOL

                point = @na_pipe_points.last.offset(offset)
            end

            raise ArgumentError, 'that is where the run already is' if point.distance(@na_pipe_points.last).to_f < NA_DRAWN_PIPE_MERGE_TOL

            na_pipe__append(point)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Pipe on the Cursor
        # -----------------------------------------------------------------------------

        # FUNCTION | Solve the Run as It Would Be Built if the Cursor Were Clicked
        # ------------------------------------------------------------
        def na_pipe__refresh_live
            @na_pipe_live = nil
            return unless na_pipe__drawing?

            points = @na_pipe_points.dup
            points << @na_pipe_cursor if @na_pipe_cursor && @na_pipe_cursor.distance(points.last).to_f >= NA_DRAWN_PIPE_MERGE_TOL
            return if points.length < 2

            run    = { :points => points, :closed => false, :smooth => Array.new(points.length, false) }
            solved = Na__InsertPrimatives.Na__DrawnPipe__Solve(run, Na__InsertPrimatives.Na__DrawnPipe__CurrentSpec, na_pipe__up)
            quads  = solved[:ok] && Na__InsertPrimatives.Na__DrawnPipe__QuadCount(solved) <= NA_DRAWN_PIPE_PREVIEW_MAX_QUADS ?
                     Na__InsertPrimatives.Na__DrawnPipe__PreviewQuads(solved) : nil

            @na_pipe_live = { :solved => solved, :quads => quads, :points => points }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPipeDraw module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE DRAW
# =============================================================================
