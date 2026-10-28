# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE SOLVER
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Solver__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnPipeSolver
# AUTHOR     : Noble Architecture
# PURPOSE    : A route of straight legs into the rings of a pipe: bends filleted
#              to a radius, mitres where asked, caps, and a closed loop with no seam
# CREATED    : 2026
#
# PURE MATHS:
# - Points go in as anything with x, y, z (or [x, y, z]) in internal inches
#   and every ring comes out as plain [x, y, z] arrays. No SketchUp geometry is
#   touched here: the builder and the preview share one answer, and the whole
#   solver can be proven offline.
#
# A BEND IS A FILLET:
# - At a corner turning by theta, a bend of centreline radius R starts
#   R tan(theta / 2) back along the incoming leg and ends the same distance
#   along the outgoing one. The arc between is a slice of a torus.
# - Legs too short for two bends are SHARED: both bends shrink by the same
#   factor until they meet. A bend that would then be no wider than the pipe
#   would turn its own inside out, so it is MITRED instead. Both are said in
#   the warnings, never done quietly.
#
# A MITRE IS A CUT ON THE BISECTOR:
# - With a bend radius of 0, and at every vertex inside an arc the user drew,
#   the two legs meet on the plane halfway between them. Inside an arc the
#   seam is softened (the arc is the bend); at a real corner it stays a hard
#   line, the way a welded mitre reads.
#
# NO TWIST:
# - Each ring's orientation is carried from the last by the same rotation
#   that turns the pipe through the bend (a rotation-minimising frame), so the
#   facets run true along the whole pipe. The first ring puts a flat facet
#   down and one to each side, so a pipe sits flush on a floor or a wall.
# - A closed loop that does not lie in one plane comes back turned. The
#   seam is closed by re-indexing to the nearest facet and spreading the
#   remaining fraction of a facet evenly round the loop.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Solver Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_MERGE_TOL     = 0.01 / 25.4                                 # <-- Inches; route points closer than 0.01mm are one point
    NA_DRAWN_PIPE_MIN_TURN_RAD  = 0.05 * Math::PI / 180.0                     # <-- A vertex turning less than this is a straight run
    NA_DRAWN_PIPE_MAX_TURN_DEG  = 175.0                                       # <-- Sharper than this the route doubles back on itself
    NA_DRAWN_PIPE_MAX_BEND_STEP = 64                                          # <-- Most rings round one bend
    NA_DRAWN_PIPE_ROUND_SIDES   = 6                                           # <-- From here up the facets are smoothed into a round pipe

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Drawn Pipe Solver Class
    # -----------------------------------------------------------------------------

    # CLASS | One Pipe Run, Solved Into Rings
    # ------------------------------------------------------------
    class DrawnPipeSolver

        # INITIALIZE | Route, Spec and the Model's Up
        # ------------------------------------------------------------
        # points  route vertices, internal inches
        # closed  true for a loop: the last point joins the first
        # smooth  per point: true where the route is already a curve
        # spec    { :diameter, :bend, :sides } in internal inches
        # up      the drawing axes' blue; the first flat facet faces it
        # ------------------------------------------------------------
        def initialize(points, closed, smooth, spec, up = nil)
            @closed   = closed ? true : false
            @radius   = spec[:diameter].to_f * 0.5
            @bore     = spec[:inner].to_f > 0.0 ? spec[:inner].to_f * 0.5 : 0.0
            @bend     = spec[:bend].to_f
            @sides    = spec[:sides].to_i
            @up       = na_vec__norm(up ? na_vec__of(up) : [0.0, 0.0, 1.0])
            @warnings = []

            raw    = (points || []).map { |point| na_vec__of(point) }
            flags  = (smooth || []).map { |flag| flag ? true : false }
            @points, @smooth = na_pipe__clean(raw, flags)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve the Run
        # ------------------------------------------------------------
        # Returns { :ok => false, :message } when the route cannot be piped, or
        #   :rings    Array of rings, each `sides` [x, y, z] points
        #   :bore     the same rings at the bore's radius for a hollow pipe, or nil
        #   :hard     per ring, true where its edges stay hard (caps, real mitres)
        #   :roles    per ring: :end, :bend_edge (a bend starts or ends),
        #             :bend_step (inside a bend), :mitre or :curve
        #   :closed   whether the last ring joins the first
        #   :offset   index shift where the last ring meets the first
        #   :round    whether the long edges are smoothed
        #   :centres  the centreline, one point per ring
        #   :points   the cleaned route; :smooth its curve flags
        #   :corners  one summary per bend or mitre; :warnings what was changed
        #   :length   the centreline length, bends included
        #   :box      [min, max] corners round every ring point, for getExtents
        # ------------------------------------------------------------
        def solve
            return na_pipe__refuse('a pipe needs a diameter and at least 3 sides') unless @radius > 0.0 && @sides >= 3
            return na_pipe__refuse('the route needs two points that are apart') if @points.length < 2
            return na_pipe__refuse('a closed route needs at least three corners') if @closed && @points.length < 3

            corners = na_pipe__plan_corners
            return corners if corners.is_a?(Hash)

            na_pipe__fit(corners)
            na_pipe__check_folds(corners)

            stations = na_pipe__walk(corners)
            offset   = @closed ? na_pipe__close_loop(stations) : 0
            rings    = stations.map { |station| na_pipe__ring(station, @radius) }

            {
                :ok       => true,
                :rings    => rings,
                :bore     => @bore > 0.0 ? stations.map { |station| na_pipe__ring(station, @bore) } : nil,
                :box      => na_pipe__box(rings),
                :hard     => stations.map { |station| station[:hard] },
                :roles    => stations.map { |station| station[:role] },
                :closed   => @closed,
                :offset   => offset,
                :round    => @sides >= NA_DRAWN_PIPE_ROUND_SIDES,
                :sides    => @sides,
                :radius   => @radius,
                :centres  => stations.map { |station| station[:centre] },
                :points   => @points,
                :smooth   => @smooth,
                :corners  => na_pipe__corner_report(corners),
                :warnings => @warnings,
                :length   => @closed ? @loop_length : stations.last[:s]
            }
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cleaning the Route
        # -----------------------------------------------------------------------------

        # FUNCTION | Drop Repeated Points and Points That Do Not Turn
        # ------------------------------------------------------------
        def na_pipe__clean(points, flags)
            kept       = []
            kept_flags = []

            points.each_with_index do |point, index|
                next if !kept.empty? && na_vec__dist(kept.last, point) < NA_DRAWN_PIPE_MERGE_TOL

                kept << point
                kept_flags << (flags[index] || false)
            end

            if @closed && kept.length > 1 && na_vec__dist(kept.first, kept.last) < NA_DRAWN_PIPE_MERGE_TOL
                kept.pop
                kept_flags.pop
            end

            return [kept, kept_flags] if kept.length < 3

            @closed ? na_pipe__drop_straight_loop(kept, kept_flags) : na_pipe__drop_straight_open(kept, kept_flags)
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Open Route Keeps Its Ends and Every Real Turn
        # ------------------------------------------------------------
        def na_pipe__drop_straight_open(points, flags)
            kept       = [points.first]
            kept_flags = [flags.first]

            1.upto(points.length - 2) do |index|
                next unless na_pipe__turns?(kept.last, points[index], points[index + 1])

                kept << points[index]
                kept_flags << flags[index]
            end

            kept << points.last
            kept_flags << flags.last
            [kept, kept_flags]
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Loop Keeps Only Its Real Corners
        # Rotated to start on one first, so the pass never has to judge a
        # point against a neighbour it is about to drop.
        # ------------------------------------------------------------
        def na_pipe__drop_straight_loop(points, flags)
            count = points.length
            start = (0...count).find do |index|
                na_pipe__turns?(points[(index - 1) % count], points[index], points[(index + 1) % count])
            end
            return [[], []] unless start                                       # <-- Every point on one line: no loop at all

            points = points.rotate(start)
            flags  = flags.rotate(start)

            kept       = [points.first]
            kept_flags = [flags.first]

            1.upto(count - 1) do |index|
                after = index == count - 1 ? kept.first : points[index + 1]
                next unless na_pipe__turns?(kept.last, points[index], after)

                kept << points[index]
                kept_flags << flags[index]
            end

            [kept, kept_flags]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does the Route Turn at This Point?
        # ------------------------------------------------------------
        def na_pipe__turns?(before, here, after)
            d_in  = na_vec__sub(here, before)
            d_out = na_vec__sub(after, here)
            return false if na_vec__len(d_in) < NA_DRAWN_PIPE_MERGE_TOL || na_vec__len(d_out) < NA_DRAWN_PIPE_MERGE_TOL

            na_vec__angle(d_in, d_out) >= NA_DRAWN_PIPE_MIN_TURN_RAD
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Corners
        # -----------------------------------------------------------------------------

        # FUNCTION | Decide What Happens at Every Turning Point
        # ------------------------------------------------------------
        # :end     an open run's first or last point
        # :bend    filleted to the bend radius
        # :mitre   cut on the bisector, a hard seam
        # :curve   cut on the bisector inside an arc, a soft seam
        # Returns the corner list, or a refusal Hash.
        # ------------------------------------------------------------
        def na_pipe__plan_corners
            count   = @points.length
            corners = Array.new(count) { |index| { :kind => :end, :index => index, :t => 0.0, :want => 0.0 } }
            turning = @closed ? (0...count).to_a : (1...(count - 1)).to_a

            turning.each do |index|
                here  = @points[index]
                d_in  = na_vec__norm(na_vec__sub(here, @points[(index - 1) % count]))
                d_out = na_vec__norm(na_vec__sub(@points[(index + 1) % count], here))
                theta = na_vec__angle(d_in, d_out)

                if theta > NA_DRAWN_PIPE_MAX_TURN_DEG * Math::PI / 180.0
                    return na_pipe__refuse("the route turns back on itself at point #{index + 1}")
                end

                kind = if @smooth[index] then :curve
                       elsif @bend <= 0.0 then :mitre
                       else :bend
                       end

                want = kind == :bend ? @bend * Math.tan(theta * 0.5) : 0.0

                corners[index] = {
                    :kind   => kind,
                    :index  => index,
                    :theta  => theta,
                    :d_in   => d_in,
                    :d_out  => d_out,
                    :want   => want,
                    :t      => want,
                    :radius => @bend
                }
            end

            corners
        end
        # ---------------------------------------------------------------

        # FUNCTION | Share Out Legs Too Short for the Bends at Both Ends
        # ------------------------------------------------------------
        # Every bend wants R tan(theta / 2) of the legs either side of it. Where
        # one leg cannot give both of its bends what they want, each is scaled
        # by the same factor; a bend scaled until it is no wider than the pipe
        # becomes a mitre, and that frees its legs, so the share is worked out
        # again from the original wants until nothing more changes.
        # ------------------------------------------------------------
        def na_pipe__fit(corners)
            count = @points.length

            3.times do
                scale = Array.new(count, 1.0)

                na_pipe__segment_count.times do |segment|
                    a = segment
                    b = (segment + 1) % count
                    demand = na_pipe__demand(corners[a]) + na_pipe__demand(corners[b])
                    next unless demand > 0.0

                    length = na_vec__dist(@points[a], @points[b])
                    next unless demand > length

                    factor   = length / demand
                    scale[a] = factor if factor < scale[a]
                    scale[b] = factor if factor < scale[b]
                end

                changed = false

                corners.each do |corner|
                    next unless corner[:kind] == :bend

                    t      = corner[:want] * scale[corner[:index]]
                    radius = t / Math.tan(corner[:theta] * 0.5)

                    if radius <= @radius * 1.000001
                        corner[:kind]   = :mitre
                        corner[:t]      = 0.0
                        corner[:folded] = true
                        changed         = true
                    else
                        corner[:t]         = t
                        corner[:radius]    = radius
                        corner[:tightened] = scale[corner[:index]] < 1.0 - 1.0e-9
                    end
                end

                break unless changed
            end

            corners.each do |corner|
                label = "point #{corner[:index] + 1}"

                if corner[:folded]
                    @warnings << "bend at #{label} mitred: its legs are too short for any bend wider than the pipe"
                elsif corner[:kind] == :bend && corner[:tightened]
                    @warnings << "bend at #{label} tightened to R#{na_pipe__mm(corner[:radius])} to fit its legs"
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Much Leg a Corner Asks For
        # ------------------------------------------------------------
        def na_pipe__demand(corner)
            corner[:kind] == :bend ? corner[:want] : 0.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Number of Legs in the Route
        # ------------------------------------------------------------
        def na_pipe__segment_count
            @closed ? @points.length : @points.length - 1
        end
        # ---------------------------------------------------------------

        # FUNCTION | Warn Where Mitres Would Overlap on a Short Leg
        # ------------------------------------------------------------
        # A mitre's outer side runs past its corner by r tan(theta / 2). Two of
        # them on a leg shorter than that pair (an arc drawn tighter than the
        # pipe, usually) cross over; it is built anyway, and said.
        # ------------------------------------------------------------
        def na_pipe__check_folds(corners)
            count = @points.length

            na_pipe__segment_count.times do |segment|
                a = corners[segment]
                b = corners[(segment + 1) % count]

                straight = na_vec__dist(@points[segment], @points[(segment + 1) % count]) - a[:t] - b[:t]
                overhang = na_pipe__overhang(a) + na_pipe__overhang(b)
                next unless overhang > straight + NA_DRAWN_PIPE_MERGE_TOL

                @warnings << "the pipe folds over itself between points #{segment + 1} and #{(segment + 1) % count + 1} — the route curves tighter than the pipe is wide"
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far a Mitre's Outer Side Runs Past Its Corner
        # ------------------------------------------------------------
        def na_pipe__overhang(corner)
            return 0.0 unless corner[:kind] == :mitre || corner[:kind] == :curve

            @radius * Math.tan(corner[:theta] * 0.5)
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Line per Bend or Mitre, for the Console and the Labels
        # ------------------------------------------------------------
        def na_pipe__corner_report(corners)
            corners.reject { |corner| corner[:kind] == :end }.map do |corner|
                {
                    :index     => corner[:index],
                    :kind      => corner[:kind],
                    :point     => @points[corner[:index]],
                    :radius    => corner[:kind] == :bend ? corner[:radius] : 0.0,
                    :changed   => (corner[:tightened] || corner[:folded]) ? true : false,
                    :degrees   => corner[:theta] * 180.0 / Math::PI
                }
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Walking the Centreline
        # -----------------------------------------------------------------------------

        # FUNCTION | Lay a Ring Station at Every Change Along the Pipe
        # ------------------------------------------------------------
        # Open runs: a capped ring at each end, one at each end of a bend and
        # one per bend step between, one per mitre. Straight legs need nothing
        # in their middles. A closed run starts where corner 0 hands over to
        # leg 0 and ends by walking corner 0 last, back on top of its start.
        # ------------------------------------------------------------
        def na_pipe__walk(corners)
            count    = @points.length
            first    = @closed ? corners[0][:d_out] : na_vec__norm(na_vec__sub(@points[1], @points[0]))
            u, v     = na_pipe__initial_frame(first)
            stations = []
            length   = 0.0

            if @closed && corners[0][:kind] == :bend
                start = na_vec__add(@points[0], na_vec__scale(corners[0][:d_out], corners[0][:t]))
                stations << na_pipe__ring_station(start, u, v, first, false, 0.0, :bend_edge)
            elsif @closed
                stations << na_pipe__mitre_station(@points[0], u, v, corners[0], 0.0)
            else
                stations << na_pipe__ring_station(@points[0], u, v, first, true, 0.0, :end)
            end

            cursor = stations.last[:centre]

            na_pipe__segment_count.times do |segment|
                k = (segment + 1) % count

                if !@closed && k == count - 1
                    length += na_vec__dist(cursor, @points[k])
                    direction = na_vec__norm(na_vec__sub(@points[k], @points[segment]))
                    na_pipe__push(stations, na_pipe__ring_station(@points[k], u, v, direction, true, length, :end))
                    break
                end

                corner = corners[k]

                if corner[:kind] == :bend
                    entry   = na_vec__sub(@points[k], na_vec__scale(corner[:d_in], corner[:t]))
                    length += na_vec__dist(cursor, entry)
                    na_pipe__push(stations, na_pipe__ring_station(entry, u, v, corner[:d_in], false, length, :bend_edge))

                    axis   = na_vec__norm(na_vec__cross(corner[:d_in], corner[:d_out]))
                    inward = na_vec__norm(na_vec__sub(corner[:d_out], na_vec__scale(corner[:d_in], na_vec__dot(corner[:d_in], corner[:d_out]))))
                    centre = na_vec__add(entry, na_vec__scale(inward, corner[:radius]))
                    arm    = na_vec__sub(entry, centre)
                    steps  = na_pipe__bend_steps(corner[:theta])

                    1.upto(steps) do |step|
                        phi = corner[:theta] * step / steps
                        na_pipe__push(stations, na_pipe__ring_station(
                            na_vec__add(centre, na_vec__rot(arm, axis, phi)),
                            na_vec__rot(u, axis, phi),
                            na_vec__rot(v, axis, phi),
                            na_vec__rot(corner[:d_in], axis, phi),
                            false,
                            length + corner[:radius] * phi,
                            step == steps ? :bend_edge : :bend_step
                        ))
                    end

                    length += corner[:radius] * corner[:theta]
                    u = na_vec__rot(u, axis, corner[:theta])
                    v = na_vec__rot(v, axis, corner[:theta])
                else
                    length += na_vec__dist(cursor, @points[k])
                    axis    = na_vec__norm(na_vec__cross(corner[:d_in], corner[:d_out]))
                    u       = na_vec__rot(u, axis, corner[:theta])
                    v       = na_vec__rot(v, axis, corner[:theta])
                    na_pipe__push(stations, na_pipe__mitre_station(@points[k], u, v, corner, length))
                end

                cursor = stations.last[:centre]
            end

            stations
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add a Station Unless It Sits on the One Before
        # ------------------------------------------------------------
        # Two bends that meet on a leg with nothing left between them hand over
        # at one point; a ring there twice would be a band of zero-length faces.
        # A mitre arriving on a ring replaces it: the cut is the true section.
        # ------------------------------------------------------------
        def na_pipe__push(stations, station)
            last = stations.last

            if last && na_vec__dist(last[:centre], station[:centre]) < NA_DRAWN_PIPE_MERGE_TOL
                stations[-1] = station if station[:kind] == :mitre
                return stations
            end

            stations << station
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Ring Square to the Pipe
        # ------------------------------------------------------------
        def na_pipe__ring_station(centre, u, v, tangent, hard, length, role)
            { :kind => :ring, :role => role, :centre => centre, :u => u, :v => v, :t => tangent, :hard => hard, :s => length }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Ring Cut on a Corner's Bisector
        # The frame is the OUTGOING leg's; the cut is the same either side.
        # ------------------------------------------------------------
        def na_pipe__mitre_station(centre, u, v, corner, length)
            {
                :kind   => :mitre,
                :role   => corner[:kind] == :mitre ? :mitre : :curve,
                :centre => centre,
                :u      => u,
                :v      => v,
                :t      => corner[:d_out],
                :d_in   => corner[:d_in],
                :d_out  => corner[:d_out],
                :hard   => corner[:kind] == :mitre,
                :s      => length
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Many Rings Round a Bend
        # The same angular step as the facets: a 24-sided pipe takes a 90 degree
        # bend in 6 steps, an 8-sided one in 2.
        # ------------------------------------------------------------
        def na_pipe__bend_steps(theta)
            step  = 2.0 * Math::PI / @sides
            steps = (theta / step - 1.0e-9).ceil
            steps = 1 if steps < 1
            steps > NA_DRAWN_PIPE_MAX_BEND_STEP ? NA_DRAWN_PIPE_MAX_BEND_STEP : steps
        end
        # ---------------------------------------------------------------

        # FUNCTION | The First Ring's Orientation
        # ------------------------------------------------------------
        # u runs level across the pipe and v up through it, so with the
        # half-step phase in na_pipe__ring a flat facet faces up, down and to
        # each side. A pipe starting vertically takes the drawing red instead.
        # (u, v, direction) is right-handed, which is what keeps every face
        # pointing outward.
        # ------------------------------------------------------------
        def na_pipe__initial_frame(direction)
            side = na_vec__cross(@up, direction)

            if na_vec__len(side) < 1.0e-6
                red  = na_vec__cross(@up, [0.0, 1.0, 0.0])
                red  = [1.0, 0.0, 0.0] if na_vec__len(red) < 1.0e-6
                side = na_vec__sub(red, na_vec__scale(direction, na_vec__dot(red, direction)))
            end

            u = na_vec__norm(side)
            [u, na_vec__cross(direction, u)]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Close a Loop Without a Seam
        # ------------------------------------------------------------
        # The walk ends on top of its start with the frame turned by alpha.
        # The last ring is dropped, the join is re-indexed by the whole facets
        # in alpha, and what is left — under half a facet — is unwound evenly
        # round the loop, so the closing faces line up exactly.
        # Returns the index offset from the last kept ring to the first.
        # ------------------------------------------------------------
        def na_pipe__close_loop(stations)
            final        = stations.pop
            origin       = stations.first
            @loop_length = final[:s]

            alpha    = Math.atan2(na_vec__dot(final[:u], origin[:v]), na_vec__dot(final[:u], origin[:u]))
            step     = 2.0 * Math::PI / @sides
            offset   = (alpha / step).round
            residual = alpha - offset * step

            if residual.abs > 1.0e-9 && @loop_length > 0.0
                stations.each do |station|
                    twist        = -residual * station[:s] / @loop_length
                    station[:u]  = na_vec__rot(station[:u], station[:t], twist)
                    station[:v]  = na_vec__rot(station[:v], station[:t], twist)
                end
            end

            offset % @sides
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Points of One Ring, at the Outside or the Bore
        # ------------------------------------------------------------
        # A mitre ring is the section slid along the leg onto the bisector
        # plane, so it is an ellipse exactly where the two cylinders meet —
        # at any radius, which is why the bore needs nothing of its own.
        # ------------------------------------------------------------
        def na_pipe__ring(station, radius)
            phase = Math::PI / @sides

            Array.new(@sides) do |index|
                angle  = phase + 2.0 * Math::PI * index / @sides
                radial = na_vec__add(
                    na_vec__scale(station[:u], radius * Math.cos(angle)),
                    na_vec__scale(station[:v], radius * Math.sin(angle))
                )
                point = na_vec__add(station[:centre], radial)
                next point unless station[:kind] == :mitre

                bisector = na_vec__norm(na_vec__add(station[:d_in], station[:d_out]))
                along    = -na_vec__dot(radial, bisector) / na_vec__dot(station[:d_out], bisector)
                na_vec__add(point, na_vec__scale(station[:d_out], along))
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Small Helpers
        # -----------------------------------------------------------------------------

        # FUNCTION | A Refusal, in the Same Shape as an Answer
        # ------------------------------------------------------------
        def na_pipe__refuse(message)
            { :ok => false, :message => message, :warnings => @warnings, :points => @points, :smooth => @smooth, :closed => @closed }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Box Round Every Ring Point, as [min, max]
        # Worked out once per solve: getExtents is asked far more often.
        # ------------------------------------------------------------
        def na_pipe__box(rings)
            low  = [Float::INFINITY] * 3
            high = [-Float::INFINITY] * 3

            rings.each do |ring|
                ring.each do |point|
                    3.times do |axis|
                        low[axis]  = point[axis] if point[axis] < low[axis]
                        high[axis] = point[axis] if point[axis] > high[axis]
                    end
                end
            end

            [low, high]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Inches to a Rounded Millimetre String
        # ------------------------------------------------------------
        def na_pipe__mm(value)
            (value.to_f * 25.4).round.to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Any Point or Vector as [x, y, z] Floats
        # ------------------------------------------------------------
        def na_vec__of(value)
            return [value.x.to_f, value.y.to_f, value.z.to_f] if value.respond_to?(:x)

            [value[0].to_f, value[1].to_f, value[2].to_f]
        end
        # ---------------------------------------------------------------

        def na_vec__add(a, b);    [a[0] + b[0], a[1] + b[1], a[2] + b[2]];                       end
        def na_vec__sub(a, b);    [a[0] - b[0], a[1] - b[1], a[2] - b[2]];                       end
        def na_vec__scale(a, s);  [a[0] * s, a[1] * s, a[2] * s];                                 end
        def na_vec__dot(a, b);    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];                        end
        def na_vec__len(a);       Math.sqrt(na_vec__dot(a, a));                                   end
        def na_vec__dist(a, b);   na_vec__len(na_vec__sub(a, b));                                 end

        def na_vec__cross(a, b)
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end

        def na_vec__norm(a)
            length = na_vec__len(a)
            length > 0.0 ? na_vec__scale(a, 1.0 / length) : [0.0, 0.0, 0.0]
        end

        # FUNCTION | Angle Between Two Directions, 0 to pi
        # ------------------------------------------------------------
        def na_vec__angle(a, b)
            la = na_vec__len(a)
            lb = na_vec__len(b)
            return 0.0 unless la > 0.0 && lb > 0.0

            cosine = na_vec__dot(a, b) / (la * lb)
            cosine = 1.0 if cosine > 1.0
            cosine = -1.0 if cosine < -1.0
            Math.acos(cosine)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rotate a Vector About a Unit Axis (Rodrigues)
        # ------------------------------------------------------------
        def na_vec__rot(vector, axis, angle)
            cosine = Math.cos(angle)
            sine   = Math.sin(angle)
            cross  = na_vec__cross(axis, vector)
            along  = na_vec__dot(axis, vector) * (1.0 - cosine)

            [
                vector[0] * cosine + cross[0] * sine + axis[0] * along,
                vector[1] * cosine + cross[1] * sine + axis[1] * along,
                vector[2] * cosine + cross[2] * sine + axis[2] * along
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPipeSolver class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Convenience
    # -----------------------------------------------------------------------------

    # FUNCTION | Solve a Run Hash ({ :points, :closed, :smooth }) With a Spec
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__Solve(run, spec, up = nil)
        DrawnPipeSolver.new(run[:points], run[:closed], run[:smooth], spec, up).solve
    rescue StandardError => error
        { :ok => false, :message => "could not solve the pipe — #{error.message}", :warnings => [] }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE SOLVER
# =============================================================================
