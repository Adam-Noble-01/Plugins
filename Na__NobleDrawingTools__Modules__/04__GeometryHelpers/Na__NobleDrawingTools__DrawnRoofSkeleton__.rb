# =============================================================================
# NA NOBLE DRAWING TOOLS - DRAWN ROOF SKELETON
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnRoofSkeleton__.rb
# NAMESPACE  : Na__NobleDrawingTools
# CLASSES    : DrawnRoofSkeleton
# AUTHOR     : Noble Architecture
# PURPOSE    : Works out every hip, valley and ridge of a roof of one pitch over
#              any plan, and offsets any plan outward for the soffit
# CREATED    : 2026
#
# DESCRIPTION:
# - Plain arrays of numbers and no SketchUp API, so all of it runs and is tested
#   outside SketchUp. Plans are lists of loops of [x, y], with the inside of the
#   plan on the LEFT of each loop's direction: an outer loop runs anticlockwise,
#   a courtyard clockwise. The caller's frame decides what x and y are.
#
# THE IDEA, THE STRAIGHT SKELETON:
# - A roof of one pitch rises at the same rate from every eaves line. So let
#   every eaves line walk inwards at one unit per unit of time: how far a line
#   has walked is how high that roof plane has climbed. Where two walking lines
#   meet is where their planes meet. Two lines that meet at a corner trace a hip
#   or a valley; two lines that meet head on make a ridge.
# - The walking lines are the WAVEFRONT, and the plan's corners move along it.
#   A corner that turns inwards (a reflex corner, at a T junction) moves fast and
#   traces a valley, and it is the one thing that can run into another part of
#   the wavefront and cut it in two.
#
# WHY NOT THE TEXTBOOK EVENTS:
# - A building's plan is square-cornered, which is the worst case there is. Wings
#   of one width make two valleys collide head on, an eaves on each side of a
#   wing lands on one line, and a ridge closes in the same instant its ends do.
#   The textbook algorithm treats an edge shrinking away and a corner hitting an
#   edge as separate events, one at a time, and it falls apart on these.
# - So here, at each moment anything touches, the tool looks at everything that
#   touches at that moment and treats it as one job (na_skel__resolve):
#     1  corners in the same place are put together in a cluster
#     2  an edge with a corner lying on it is split there, into the cluster
#     3  edges with both ends in one cluster have shrunk away and are dropped
#     4  round each cluster the edges left are sorted by angle, and each one
#        going out is joined to the first one coming in anticlockwise from it:
#        between them is the inside of the plan that is left
#     5  the wavefront is walked again. A loop of two corners has closed flat,
#        and it is a ridge. The rest walk on, some loops now cut in two, some
#        joined into one
#   Every case above is the same few lines, and a square, a T junction and a
#   pinwheel of equal wings need no code of their own.
#
# PLANES THAT SHARE A LINE:
# - Eaves on one straight line, either side of a wing, are one plane of the roof
#   however far apart they start. Each eaves collects the segments round its
#   plane; for one plane the segments between two such eaves run both ways and
#   cancel, so the slope comes out as one face with no line down the middle.
#
# CHECKED BEFORE IT IS BELIEVED (na_skel__validate):
# - Every face must be a simple loop, and every interior segment is used once
#   each way or the faces do not close. Together those PROVE the faces cover the
#   plan exactly once, with no folds or overlaps. The sum of the areas on its own
#   would prove nothing: it telescopes to the right answer for any topology.
# - If a solve fails the check it is run again with a coarser tolerance, and if
#   none passes the answer is nil, so a wrong roof is never built.
#
# UNITS:
# - Lengths in, lengths out. A result's t values are how far an eaves has walked;
#   a roof's height there is t x the tangent of its pitch.
#
# =============================================================================

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Skeleton Constants
    # -----------------------------------------------------------------------------

    NA_SKEL_TOLERANCES   = [1.0e-6, 1.0e-5, 1.0e-4, 1.0e-3].freeze            # <-- Internal inches; tried in turn, tightest first
    NA_SKEL_POINT_TOL    = 0.001                                              # <-- SketchUp's own: closer than this is one point
    NA_SKEL_WELD_TOL     = 0.0011                                             # <-- Just over it, so no face asks SketchUp for less
    NA_SKEL_FLAT_TOL     = 1.0e-4                                             # <-- A corner this close to its neighbours' line has no corner
    NA_SKEL_PLANE_ANGLE  = 1.0e-6                                             # <-- Radians; two eaves on one line, one plane
    NA_SKEL_PLANE_OFFSET = 1.0e-4

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # CLASS | The Wavefront
    # =============================================================================

    class DrawnRoofSkeleton

        class Failed < StandardError; end

        NA_SKEL_RATE_EPS  = 1.0e-12
        NA_SKEL_ANGLE_TIE = 1.0e-10                                           # <-- Radians; two edges exactly on one line, as far as doubles can tell
        NA_SKEL_MIN_SUM   = 1.0e-20                                           # <-- Squared; below that tie, two edges back along each other have no corner
        NA_SKEL_CONVEX    = 1.0e-9
        NA_SKEL_FULL_TURN = Math::PI * 2.0

        # CLASS | One Eaves Line, With Its Inward Direction
        # ------------------------------------------------------------
        class WaveEdge
            attr_reader :px, :py, :dx, :dy, :nx, :ny

            def initialize(from, to)
                @px = from[0].to_f
                @py = from[1].to_f
                ex  = to[0].to_f - @px
                ey  = to[1].to_f - @py
                len = Math.sqrt((ex * ex) + (ey * ey))
                raise Failed, 'a plan edge has no length' unless len > 0.0

                @dx = ex / len
                @dy = ey / len
                @nx = -@dy
                @ny = @dx
            end
        end
        # ---------------------------------------------------------------

        # CLASS | One Corner of the Wavefront, or a Mark on an Edge While Resolving
        # ------------------------------------------------------------
        class WaveCorner
            attr_accessor :in_edge, :out_edge, :node, :x0, :y0, :t0, :vx, :vy, :convex,
                          :before, :after, :x, :y, :root, :mark, :fresh, :in_owner, :feed

            def initialize(in_edge, out_edge, node, x, y, t)
                @in_edge  = in_edge
                @out_edge = out_edge
                @node     = node
                @x0       = x
                @y0       = y
                @t0       = t
                @x        = x
                @y        = y
                @vx       = 0.0
                @vy       = 0.0
                @convex   = false
                @mark     = false
                @fresh    = false
            end
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Set Up and Run
        # -----------------------------------------------------------------------------

        # INITIALIZE | Every Loop Becomes a Wavefront at Time Nought
        # ------------------------------------------------------------
        def initialize(loops, tolerance)
            @tol      = tolerance.to_f
            @tol_sq   = @tol * @tol
            @loops    = loops
            @edges    = []
            @nodes    = []
            @corners  = []
            @segments = Hash.new { |hash, key| hash[key] = [] }

            loops.each { |points| na_skel__add_loop(points) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve the Whole Roof
        # ------------------------------------------------------------
        def solve
            na_skel__run
            na_skel__finish
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk Out to One Distance and Read the Wavefront There
        # ------------------------------------------------------------
        def wavefront_at(distance)
            na_skel__run(distance)
            na_skel__place_at(distance)

            seen  = {}
            rings = []

            @corners.each do |start|
                next if seen[start]

                ring   = []
                corner = start

                loop do
                    seen[corner] = true
                    ring << [corner.x, corner.y]
                    corner = corner.after
                    break if corner.equal?(start)
                end

                rings << ring
            end

            rings
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add One Loop of the Plan
        # ------------------------------------------------------------
        def na_skel__add_loop(points)
            count = points.length
            first = @edges.length

            points.each_with_index do |point, index|
                @edges << WaveEdge.new(point, points[(index + 1) % count])
            end

            rim = points.each_with_index.map do |point, index|
                node   = na_skel__add_node(point[0].to_f, point[1].to_f, 0.0)
                corner = WaveCorner.new(first + ((index - 1) % count), first + index, node, point[0].to_f, point[1].to_f, 0.0)
                na_skel__set_motion(corner)
                corner
            end

            rim.each_with_index do |corner, index|
                corner.after  = rim[(index + 1) % count]
                corner.before = rim[(index - 1) % count]
                @segments[corner.out_edge] << [corner.node, corner.after.node]    # <-- The eaves itself, along the foot of its plane
            end

            @corners.concat(rim)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add a Point of the Roof
        # ------------------------------------------------------------
        def na_skel__add_node(x, y, t)
            @nodes << [x, y, t]
            @nodes.length - 1
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Fast a Corner Moves, Given the Two Edges Either Side
        # ------------------------------------------------------------
        # A corner between inward directions a and b moves at (a + b) / (1 + a.b).
        # Written with the sum alone, 2 (a + b) / |a + b|^2 is the same thing, and it
        # stays good where the other goes to pieces: the two sides of a wing a hair
        # off parallel meet at a corner that races down the wing at millions of times
        # the wavefront's speed, and 1 + a.b has lost nearly all its digits by then.
        # ------------------------------------------------------------
        def na_skel__set_motion(corner)
            incoming = @edges[corner.in_edge]
            outgoing = @edges[corner.out_edge]
            sum_x    = incoming.nx + outgoing.nx
            sum_y    = incoming.ny + outgoing.ny
            square   = (sum_x * sum_x) + (sum_y * sum_y)

            raise Failed, 'two edges run back along each other with no room between' if square < NA_SKEL_MIN_SUM

            corner.vx     = 2.0 * sum_x / square
            corner.vy     = 2.0 * sum_y / square
            corner.convex = ((incoming.dx * outgoing.dy) - (incoming.dy * outgoing.dx)) > NA_SKEL_CONVEX
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Wavefront to the End, or to a Stopping Time
        # ------------------------------------------------------------
        def na_skel__run(stop_time = nil)
            now = 0.0
            na_skel__resolve(now)                                             # <-- A plan can touch itself before anything moves

            budget = (@corners.length * 20) + 200

            until @corners.empty?
                time = na_skel__next_event(now)
                return stop_time if stop_time && (time.nil? || time > stop_time)

                raise Failed, 'the wavefront stalled with corners left' if time.nil?

                budget -= 1
                raise Failed, 'the wavefront would not settle' if budget < 0

                now = time
                na_skel__resolve(now)
            end

            now
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put Every Corner Where It Is at a Given Time
        # ------------------------------------------------------------
        def na_skel__place_at(time)
            @corners.each do |corner|
                elapsed  = time - corner.t0
                corner.x = corner.x0 + (corner.vx * elapsed)
                corner.y = corner.y0 + (corner.vy * elapsed)
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | When Does Something Next Touch?
        # -----------------------------------------------------------------------------

        # FUNCTION | The Soonest Time an Edge Shrinks Away or a Corner Hits an Edge
        # ------------------------------------------------------------
        # Only corners that are not convex can hit anything: a convex corner runs
        # into the part of the plan it already closes round, and whatever it would
        # hit has gone by then. That case still gets found in na_skel__resolve,
        # which looks at everything touching, not just at what made the event.
        #
        # A corner already within tolerance of an edge's line is ignored. It has
        # just been dealt with, or it is on the outside of that edge and moving
        # away; counting it would find the same moment again for ever.
        # ------------------------------------------------------------
        def na_skel__next_event(now)
            na_skel__place_at(now)
            best = nil

            @corners.each do |corner|
                other = corner.after
                edge  = @edges[corner.out_edge]
                rate  = ((other.vx - corner.vx) * edge.dx) + ((other.vy - corner.vy) * edge.dy)
                next unless rate < -NA_SKEL_RATE_EPS

                length = ((other.x - corner.x) * edge.dx) + ((other.y - corner.y) * edge.dy)
                time   = now + ((length > 0.0 ? length : 0.0) / -rate)
                best   = time if best.nil? || time < best
            end

            @corners.each do |corner|
                next if corner.convex

                @corners.each do |start|
                    finish = start.after
                    next if start.equal?(corner) || finish.equal?(corner)
                    next if start.out_edge == corner.in_edge || start.out_edge == corner.out_edge

                    edge = @edges[start.out_edge]
                    gap  = ((corner.x - edge.px) * edge.nx) + ((corner.y - edge.py) * edge.ny) - now
                    next unless gap > @tol

                    rate = (corner.vx * edge.nx) + (corner.vy * edge.ny) - 1.0
                    next unless rate < -NA_SKEL_RATE_EPS

                    step = gap / -rate
                    time = now + step
                    next if best && time >= best

                    # The edge has moved too by then: is the corner within its ends?
                    start_x  = start.x + (start.vx * step)
                    start_y  = start.y + (start.vy * step)
                    along    = ((corner.x + (corner.vx * step) - start_x) * edge.dx) + ((corner.y + (corner.vy * step) - start_y) * edge.dy)
                    length   = ((finish.x + (finish.vx * step) - start_x) * edge.dx) + ((finish.y + (finish.vy * step) - start_y) * edge.dy)
                    next unless along >= -@tol && along <= length + @tol

                    best = time
                end
            end

            best
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Everything That Touches at One Moment
        # -----------------------------------------------------------------------------

        # FUNCTION | Deal With Everything Touching at This Moment as One Job
        # ------------------------------------------------------------
        def na_skel__resolve(now)
            na_skel__place_at(now)

            @corners.each do |corner|
                corner.root     = corner
                corner.mark     = false
                corner.in_owner = nil
            end

            na_skel__cluster_corners
            marks   = na_skel__mark_contacts
            members = @corners + marks

            survivors = []

            members.group_by { |member| na_skel__find(member) }.each_value do |cluster|
                if cluster.length == 1
                    only          = cluster.first
                    only.in_owner = only
                    only.feed     = only
                    survivors << only
                else
                    na_skel__reconnect(cluster, now, survivors)
                end
            end

            survivors.each do |corner|
                owner = corner.feed.after.in_owner
                raise Failed, 'an edge lost its far corner' unless owner

                corner.after = owner
                owner.before = corner
            end

            survivors = na_skel__drop_pass_throughs(survivors)
            @corners  = na_skel__walk_rings(survivors, now)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Follow a Corner's Cluster Link to Its Root
        # ------------------------------------------------------------
        def na_skel__find(corner)
            root = corner
            root = root.root until root.root.equal?(root)

            while !corner.root.equal?(root)
                onward      = corner.root
                corner.root = root
                corner      = onward
            end

            root
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put Two Corners in One Cluster
        # ------------------------------------------------------------
        def na_skel__union(first, second)
            root_a = na_skel__find(first)
            root_b = na_skel__find(second)
            root_b.root = root_a unless root_a.equal?(root_b)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Corners in the Same Place Become One Cluster
        # ------------------------------------------------------------
        def na_skel__cluster_corners
            sorted = @corners.sort_by(&:x)
            count  = sorted.length

            count.times do |index|
                first = sorted[index]
                later = index + 1

                while later < count
                    second = sorted[later]
                    break if second.x - first.x > @tol

                    delta_x = second.x - first.x
                    delta_y = second.y - first.y
                    na_skel__union(first, second) if (delta_x * delta_x) + (delta_y * delta_y) <= @tol_sq

                    later += 1
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Edge With a Corner Lying on It Is Split There
        # ------------------------------------------------------------
        # Returns the marks made. A corner a hair from an end of the edge joins
        # that end's cluster instead, or a mark would sit on top of the end.
        # ------------------------------------------------------------
        def na_skel__mark_contacts
            hits = {}

            @corners.each do |start|
                finish = start.after
                next if na_skel__find(start).equal?(na_skel__find(finish))

                edge   = @edges[start.out_edge]
                length = ((finish.x - start.x) * edge.dx) + ((finish.y - start.y) * edge.dy)
                raise Failed, 'an edge of the wavefront turned inside out' if length < -@tol

                min_x, max_x = start.x < finish.x ? [start.x, finish.x] : [finish.x, start.x]
                min_y, max_y = start.y < finish.y ? [start.y, finish.y] : [finish.y, start.y]
                min_x -= @tol
                min_y -= @tol
                max_x += @tol
                max_y += @tol

                @corners.each do |corner|
                    next if corner.x < min_x || corner.x > max_x || corner.y < min_y || corner.y > max_y
                    next if corner.equal?(start) || corner.equal?(finish)

                    off_x  = corner.x - start.x
                    off_y  = corner.y - start.y
                    height = (off_x * edge.nx) + (off_y * edge.ny)
                    next if height.abs > @tol

                    along = (off_x * edge.dx) + (off_y * edge.dy)
                    next if along < -@tol || along > length + @tol

                    root = na_skel__find(corner)
                    next if root.equal?(na_skel__find(start)) || root.equal?(na_skel__find(finish))

                    if along <= @tol
                        na_skel__union(corner, start)
                    elsif along >= length - @tol
                        na_skel__union(corner, finish)
                    else
                        (hits[start] ||= []) << [along, corner]
                    end
                end
            end

            marks = []

            hits.each do |start, list|
                finish   = start.after
                edge     = @edges[start.out_edge]
                previous = start
                placed   = {}

                list.sort_by(&:first).each do |along, corner|
                    root = na_skel__find(corner)
                    next if root.equal?(na_skel__find(start)) || root.equal?(na_skel__find(finish)) || placed[root]

                    placed[root] = true

                    mark        = WaveCorner.new(start.out_edge, start.out_edge, nil, start.x + (edge.dx * along), start.y + (edge.dy * along), 0.0)
                    mark.mark   = true
                    mark.root   = root
                    mark.before = previous
                    previous.after = mark
                    previous    = mark
                    marks << mark
                end

                previous.after = finish
                finish.before  = previous
            end

            marks
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rejoin the Edges Round One Cluster
        # ------------------------------------------------------------
        # Every corner that arrived here ends its hip or valley at a new point of
        # the roof. The edges still of any length are paired by angle, and each
        # pair is a new corner walking on from here.
        # ------------------------------------------------------------
        def na_skel__reconnect(cluster, now, survivors)
            sum_x = 0.0
            sum_y = 0.0

            cluster.each do |member|
                sum_x += member.x
                sum_y += member.y
            end

            x    = sum_x / cluster.length
            y    = sum_y / cluster.length
            node = na_skel__add_node(x, y, now)
            root = na_skel__find(cluster.first)

            cluster.each { |member| na_skel__end_arc(member, node) unless member.mark }

            spokes = []

            cluster.each do |member|
                unless na_skel__find(member.before).equal?(root)
                    edge = @edges[member.in_edge]
                    spokes << [na_skel__angle(-edge.dx, -edge.dy), :in, member]
                end

                next if na_skel__find(member.after).equal?(root)

                edge = @edges[member.out_edge]
                spokes << [na_skel__angle(edge.dx, edge.dy), :out, member]
            end

            na_skel__pair_spokes(spokes).each do |arriving, leaving|
                corner          = WaveCorner.new(arriving.in_edge, leaving.out_edge, node, x, y, now)
                corner.fresh    = true
                corner.feed     = leaving
                arriving.in_owner = corner
                survivors << corner
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Direction as an Angle in 0 to a Full Turn
        # ------------------------------------------------------------
        def na_skel__angle(dx, dy)
            angle = Math.atan2(dy, dx)
            angle < 0.0 ? angle + NA_SKEL_FULL_TURN : angle
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pair Each Edge Going Out With the Next Coming In, Anticlockwise
        # ------------------------------------------------------------
        # Looking out from the cluster, the unswept plan lies anticlockwise of an
        # edge going out and clockwise of one coming in, so each interior wedge
        # opens at an edge going out and closes at an edge coming in, and they
        # pair off like brackets.
        #
        # Two on one line have no wedge between them: the plan has closed flat
        # there, and that is what a ridge is. So in a tie the edge going out comes
        # first. The other reading, a wedge of a whole turn, would be a slit cut
        # into the plan, and the wavefront cannot make one.
        #
        # The circle is cut at its widest gap so no tie is split by the cut.
        # ------------------------------------------------------------
        def na_skel__pair_spokes(spokes)
            return [] if spokes.empty?

            ordered = spokes.sort_by(&:first)
            count   = ordered.length
            widest  = -1.0
            cut     = 0

            count.times do |index|
                gap = ordered[(index + 1) % count][0] - ordered[index][0]
                gap += NA_SKEL_FULL_TURN if index == count - 1

                if gap > widest
                    widest = gap
                    cut    = (index + 1) % count
                end
            end

            ring  = ordered.rotate(cut)
            items = []
            tied  = [ring.first]

            (1...count).each do |index|
                if (ring[index][0] - ring[index - 1][0]) % NA_SKEL_FULL_TURN <= NA_SKEL_ANGLE_TIE
                    tied << ring[index]
                else
                    items.concat(tied.partition { |spoke| spoke[1] == :out }.flatten(1))
                    tied = [ring[index]]
                end
            end

            items.concat(tied.partition { |spoke| spoke[1] == :out }.flatten(1))

            open_spokes = []
            unmatched   = []
            pairs       = []

            items.each do |_angle, kind, member|
                if kind == :out
                    open_spokes.push(member)
                elsif open_spokes.empty?
                    unmatched << member
                else
                    pairs << [member, open_spokes.pop]
                end
            end

            raise Failed, 'the edges round a point do not pair up' unless open_spokes.length == unmatched.length

            unmatched.each { |member| pairs << [member, open_spokes.pop] }             # <-- These wrap past the cut
            pairs
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Corner Between Two Pieces of One Edge Is No Corner
        # ------------------------------------------------------------
        def na_skel__drop_pass_throughs(survivors)
            survivors.reject do |corner|
                next false unless corner.in_edge == corner.out_edge

                corner.before.after = corner.after
                corner.after.before = corner.before
                true
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk the Wavefront Again: Loops of Two Have Closed as Ridges
        # ------------------------------------------------------------
        def na_skel__walk_rings(survivors, now)
            seen  = {}
            alive = []

            survivors.each do |start|
                next if seen[start]

                ring   = []
                corner = start

                loop do
                    raise Failed, 'the wavefront crossed itself' if seen[corner]

                    seen[corner] = true
                    ring << corner
                    corner = corner.after
                    break if corner.equal?(start)
                end

                raise Failed, 'an edge of the wavefront closed on itself' if ring.length < 2

                if ring.length == 2
                    na_skel__close_ridge(ring[0], ring[1], now)
                else
                    ring.each do |member|
                        next unless member.fresh

                        na_skel__set_motion(member)
                        member.fresh = false
                    end

                    alive.concat(ring)
                end
            end

            alive
        end
        # ---------------------------------------------------------------

        # FUNCTION | Two Edges Have Closed Flat Between Two Points: a Ridge
        # ------------------------------------------------------------
        # Each plane's own boundary runs along the ridge the opposite way to its
        # eaves, which is how the two come out each with the inside on the left.
        # ------------------------------------------------------------
        def na_skel__close_ridge(first, second, now)
            [first, second].each do |corner|
                next if corner.fresh

                node = na_skel__add_node(corner.x, corner.y, now)                 # <-- Still walking until now: end it here
                na_skel__end_arc(corner, node)
                corner.node = node
            end

            @segments[first.out_edge]  << [second.node, first.node]
            @segments[second.out_edge] << [first.node, second.node]
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Corner's Hip or Valley Ends Here
        # ------------------------------------------------------------
        def na_skel__end_arc(corner, node)
            return if corner.node == node || corner.in_edge == corner.out_edge

            @segments[corner.in_edge]  << [corner.node, node]
            @segments[corner.out_edge] << [node, corner.node]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | From Segments to Roof Faces
        # -----------------------------------------------------------------------------

        # FUNCTION | Weld, Stitch, Tidy and Check the Finished Roof
        # ------------------------------------------------------------
        def na_skel__finish
            welded = na_skel__weld_nodes
            faces  = []

            na_skel__plane_groups.each do |edge_ids|
                rings = na_skel__stitch_plane(edge_ids, welded)
                next if rings.empty?

                edge = @edges[edge_ids.first]
                faces.concat(na_skel__faces_from_rings(rings, edge))
            end

            na_skel__drop_flat_nodes(faces)
            faces.reject! { |face| face[:outer].length < 3 }
            na_skel__validate(faces)
            na_skel__package(faces)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Points Closer Than SketchUp Can Tell Apart Become One
        # ------------------------------------------------------------
        # Compared in plan. A roof is one height at each place on the plan, so two
        # points close in plan are close in height too. The earliest point stands
        # for the group, which keeps the eaves corners exactly as they came in.
        # ------------------------------------------------------------
        def na_skel__weld_nodes
            parent = (0...@nodes.length).to_a
            find   = lambda do |id|
                id = parent[id] = parent[parent[id]] until parent[id] == id
                id
            end

            sorted = (0...@nodes.length).sort_by { |id| @nodes[id][0] }

            sorted.each_with_index do |id, index|
                later = index + 1

                while later < sorted.length
                    other   = sorted[later]
                    delta_x = @nodes[other][0] - @nodes[id][0]
                    break if delta_x > NA_SKEL_WELD_TOL

                    delta_y = @nodes[other][1] - @nodes[id][1]

                    if (delta_x * delta_x) + (delta_y * delta_y) <= NA_SKEL_WELD_TOL * NA_SKEL_WELD_TOL
                        root_a = find.call(id)
                        root_b = find.call(other)
                        parent[root_a > root_b ? root_a : root_b] = root_a > root_b ? root_b : root_a
                    end

                    later += 1
                end
            end

            (0...@nodes.length).map { |id| find.call(id) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Eaves on One Straight Line Share One Plane
        # ------------------------------------------------------------
        def na_skel__plane_groups
            groups = []

            @edges.each_index do |id|
                edge   = @edges[id]
                offset = (edge.px * edge.nx) + (edge.py * edge.ny)

                match = groups.find do |group|
                    other = @edges[group.first]
                    cross = (edge.dx * other.dy) - (edge.dy * other.dx)
                    dot   = (edge.dx * other.dx) + (edge.dy * other.dy)

                    dot > 0.0 && cross.abs < NA_SKEL_PLANE_ANGLE &&
                        (offset - ((other.px * other.nx) + (other.py * other.ny))).abs < NA_SKEL_PLANE_OFFSET
                end

                match ? match << id : groups << [id]
            end

            groups
        end
        # ---------------------------------------------------------------

        # FUNCTION | Join a Plane's Segments Into Closed Loops
        # ------------------------------------------------------------
        # A segment and its reverse are a seam between two eaves of one plane, and
        # cancel. At a point the plane touches itself, the walk takes the first
        # segment clockwise from the way it came, which keeps inside the same lobe
        # and so comes out with two simple loops rather than one figure of eight.
        # ------------------------------------------------------------
        def na_skel__stitch_plane(edge_ids, welded)
            tally = Hash.new(0)

            edge_ids.each do |id|
                @segments[id].each do |from, to|
                    a = welded[from]
                    b = welded[to]
                    next if a == b

                    if tally[[b, a]] > 0
                        tally[[b, a]] -= 1
                    else
                        tally[[a, b]] += 1
                    end
                end
            end

            outgoing = Hash.new { |hash, key| hash[key] = [] }
            tally.each { |(a, b), times| times.times { outgoing[a] << b } }

            rings = []

            until outgoing.empty?
                start   = outgoing.keys.first
                ring    = [start]
                current = start
                last    = nil

                loop do
                    options = outgoing[current]
                    raise Failed, 'a roof plane did not close' if options.empty?

                    onward = na_skel__choose_onward(options, current, last)
                    options.delete_at(options.index(onward))
                    outgoing.delete(current) if options.empty?

                    break if onward == start

                    ring << onward
                    last    = current
                    current = onward
                end

                rings << ring
            end

            rings
        end
        # ---------------------------------------------------------------

        # FUNCTION | At a Point With a Choice, Keep to the Same Lobe
        # ------------------------------------------------------------
        def na_skel__choose_onward(options, current, last)
            return options.first if options.length == 1 || last.nil?

            here = @nodes[current]
            back = Math.atan2(@nodes[last][1] - here[1], @nodes[last][0] - here[0])

            options.min_by do |option|
                turn = (back - Math.atan2(@nodes[option][1] - here[1], @nodes[option][0] - here[0])) % NA_SKEL_FULL_TURN
                turn <= 0.0 ? NA_SKEL_FULL_TURN : turn
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Sort a Plane's Loops Into Faces With Their Holes
        # ------------------------------------------------------------
        def na_skel__faces_from_rings(rings, edge)
            outers = []
            holes  = []

            rings.each do |ring|
                points = ring.map { |id| @nodes[id] }
                area   = Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(points)
                next if area.abs <= NA_SKEL_POINT_TOL * NA_SKEL_POINT_TOL

                (area > 0.0 ? outers : holes) << ring
            end

            faces = outers.map do |ring|
                { :outer => ring, :holes => [], :normal => [edge.nx, edge.ny], :offset => (edge.px * edge.nx) + (edge.py * edge.ny) }
            end

            holes.each do |ring|
                owner = faces.find do |face|
                    Na__NobleDrawingTools.Na__DrawnRoofSkeleton__PointInLoop?(@nodes[ring.first], face[:outer].map { |id| @nodes[id] })
                end

                raise Failed, 'a roof plane has a hole outside itself' unless owner

                owner[:holes] << ring
            end

            faces
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point That Is No Corner of Any Face Is Dropped From All of Them
        # ------------------------------------------------------------
        # A seam between two eaves of one plane ends on a ridge. The seam is gone,
        # and the point it left would be a dot halfway along a straight ridge. It
        # goes only if it is flat in every face using it, so faces always agree.
        # ------------------------------------------------------------
        def na_skel__drop_flat_nodes(faces)
            corners = {}

            faces.each do |face|
                ([face[:outer]] + face[:holes]).each do |ring|
                    ring.each_with_index do |id, index|
                        a = @nodes[ring[index - 1]]
                        b = @nodes[id]
                        c = @nodes[ring[(index + 1) % ring.length]]
                        corners[id] = true unless na_skel__flat?(a, b, c)
                    end
                end
            end

            faces.each do |face|
                face[:outer] = face[:outer].select { |id| corners[id] }
                face[:holes] = face[:holes].map { |ring| ring.select { |id| corners[id] } }.select { |ring| ring.length >= 3 }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does b Lie on the Straight Line From a to c, Between Them?
        # ------------------------------------------------------------
        def na_skel__flat?(a, b, c)
            chord_x = c[0] - a[0]
            chord_y = c[1] - a[1]
            length  = Math.sqrt((chord_x * chord_x) + (chord_y * chord_y))
            return false unless length > 0.0

            off = (((b[0] - a[0]) * chord_y) - ((b[1] - a[1]) * chord_x)) / length
            return false if off.abs > NA_SKEL_FLAT_TOL

            ((a[0] - b[0]) * (c[0] - b[0])) + ((a[1] - b[1]) * (c[1] - b[1])) < 0.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refuse a Roof That Is Not One
        # ------------------------------------------------------------
        # Interior segments have cancelled or the planes would not have closed. If
        # each face is then a simple loop, the faces cover the plan exactly once.
        # ------------------------------------------------------------
        def na_skel__validate(faces)
            raise Failed, 'no faces came out' if faces.empty?

            faces.each do |face|
                ([face[:outer]] + face[:holes]).each do |ring|
                    points = ring.map { |id| @nodes[id] }
                    raise Failed, 'a roof plane crosses itself' if Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SelfCrossing?(points)

                    points.each do |point|
                        height = (point[0] * face[:normal][0]) + (point[1] * face[:normal][1]) - face[:offset]
                        raise Failed, 'a point of the roof is off its plane' if (height - point[2]).abs > NA_SKEL_WELD_TOL * 3.0
                    end
                end
            end

            expected = @loops.inject(0.0) { |sum, points| sum + Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(points) }
            found    = faces.inject(0.0) do |sum, face|
                sum + Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(face[:outer].map { |id| @nodes[id] }) -
                    face[:holes].inject(0.0) { |holes, ring| holes + Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(ring.map { |id| @nodes[id] }).abs }
            end

            allowance = 1.0e-6 * expected.abs + (NA_SKEL_WELD_TOL * Math.sqrt(expected.abs) * 4.0)
            raise Failed, 'the roof planes do not cover the plan' if (found - expected).abs > allowance
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Answer, as Plain Numbers
        # ------------------------------------------------------------
        def na_skel__package(faces)
            highest = 0.0

            built = faces.map do |face|
                outer = face[:outer].map { |id| @nodes[id].dup }
                holes = face[:holes].map { |ring| ring.map { |id| @nodes[id].dup } }

                outer.each { |point| highest = point[2] if point[2] > highest }

                {
                    :outer     => outer,
                    :holes     => holes,
                    :normal    => face[:normal],
                    :offset    => face[:offset],
                    :triangles => Na__NobleDrawingTools.Na__DrawnRoofSkeleton__Triangulate(outer, holes)
                }
            end

            volume = 0.0

            built.each do |face|
                face[:triangles].each do |a, b, c|
                    area    = ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])).abs * 0.5
                    volume += area * (a[2] + b[2] + c[2]) / 3.0
                end
            end

            {
                :faces  => built,
                :lines  => na_skel__classify_lines(faces),
                :height => highest,
                :volume => volume,                                            # <-- At a slope of 1; multiply by the real slope
                :loops  => @loops
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Name Every Line Between Two Planes: Ridge, Hip or Valley
        # ------------------------------------------------------------
        # Across a hip or ridge the roof takes the LOWER plane either side; across
        # a valley the higher. With a segment's own plane G on its left and the
        # other plane H on its right, (nG - nH) dotted with the left-hand
        # perpendicular is below zero for the first and above for the second.
        # ------------------------------------------------------------
        def na_skel__classify_lines(faces)
            owners = {}

            faces.each do |face|
                ([face[:outer]] + face[:holes]).each do |ring|
                    ring.each_with_index { |id, index| owners[[id, ring[(index + 1) % ring.length]]] = face }
                end
            end

            lines = []

            owners.each do |(from, to), face|
                other = owners[[to, from]]
                next unless other && from < to

                a     = @nodes[from]
                b     = @nodes[to]
                left  = [-(b[1] - a[1]), b[0] - a[0]]
                value = ((face[:normal][0] - other[:normal][0]) * left[0]) + ((face[:normal][1] - other[:normal][1]) * left[1])

                kind =
                    if value > 0.0
                        :valley
                    elsif (a[2] - b[2]).abs <= NA_SKEL_WELD_TOL
                        :ridge
                    else
                        :hip
                    end

                lines << { :a => a.dup, :b => b.dup, :kind => kind }
            end

            lines
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnRoofSkeleton class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plan Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Signed Area of a Loop: Positive When It Runs Anticlockwise
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__SignedArea(points)
        sum   = 0.0
        count = points.length

        count.times do |index|
            a = points[index]
            b = points[(index + 1) % count]
            sum += (a[0] * b[1]) - (b[0] * a[1])
        end

        sum * 0.5
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Point Inside a Loop?
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__PointInLoop?(point, loop_points)
        inside = false
        count  = loop_points.length

        count.times do |index|
            a = loop_points[index]
            b = loop_points[(index + 1) % count]
            next unless (a[1] > point[1]) != (b[1] > point[1])

            crossing = a[0] + ((point[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1]))
            inside = !inside if point[0] < crossing
        end

        inside
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do Two Segments Cross Each Other Properly?
    # ------------------------------------------------------------
    # Touching does not count, only passing through. The side tests are in plan
    # lengths, so "on the line" means the same thing at every size of segment.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__SegmentsCross?(a, b, c, d, margin = 1.0e-7)
        ab_x = b[0] - a[0]
        ab_y = b[1] - a[1]
        cd_x = d[0] - c[0]
        cd_y = d[1] - c[1]
        ab   = Math.sqrt((ab_x * ab_x) + (ab_y * ab_y))
        cd   = Math.sqrt((cd_x * cd_x) + (cd_y * cd_y))
        return false unless ab > 0.0 && cd > 0.0

        side_c = ((ab_x * (c[1] - a[1])) - (ab_y * (c[0] - a[0]))) / ab
        side_d = ((ab_x * (d[1] - a[1])) - (ab_y * (d[0] - a[0]))) / ab
        side_a = ((cd_x * (a[1] - c[1])) - (cd_y * (a[0] - c[0]))) / cd
        side_b = ((cd_x * (b[1] - c[1])) - (cd_y * (b[0] - c[0]))) / cd

        ((side_c > margin && side_d < -margin) || (side_c < -margin && side_d > margin)) &&
            ((side_a > margin && side_b < -margin) || (side_a < -margin && side_b > margin))
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does a Loop Cross Itself?
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__SelfCrossing?(points)
        count = points.length

        count.times do |first|
            a = points[first]
            b = points[(first + 1) % count]

            ((first + 2)...count).each do |second|
                next if first.zero? && second == count - 1

                return true if Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SegmentsCross?(a, b, points[second], points[(second + 1) % count])
            end
        end

        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Tidy a Loop: No Repeated Points, No Corner That Is Not One
    # ------------------------------------------------------------
    # A vertex partway along a straight run, as SketchUp leaves where a line once
    # met it, would otherwise make the roof think it had two eaves. A spike with
    # no width is taken out by the same test.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__CleanLoop(points, tolerance = NA_SKEL_POINT_TOL)
        list    = points.map { |point| [point[0].to_f, point[1].to_f] }
        changed = true

        while changed && list.length >= 3
            changed = false
            index   = 0

            while index < list.length && list.length >= 3
                a = list[index - 1]
                b = list[index]
                c = list[(index + 1) % list.length]

                from_a_x = b[0] - a[0]
                from_a_y = b[1] - a[1]
                chord_x  = c[0] - a[0]
                chord_y  = c[1] - a[1]
                chord    = Math.sqrt((chord_x * chord_x) + (chord_y * chord_y))

                if chord < tolerance || ((from_a_x * chord_y) - (from_a_y * chord_x)).abs / chord < tolerance
                    list.delete_at(index)
                    changed = true
                else
                    index += 1
                end
            end
        end

        list
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sort Loops Into Outers, Each With the Holes It Contains
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__GroupLoops(loops)
        outers = []
        holes  = []

        loops.each do |points|
            (Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(points) > 0.0 ? outers : holes) << points
        end

        groups = outers.map { |points| { :outer => points, :holes => [] } }

        holes.each do |points|
            owner = groups.find { |group| Na__NobleDrawingTools.Na__DrawnRoofSkeleton__PointInLoop?(points.first, group[:outer]) }
            owner[:holes] << points if owner
        end

        groups
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Triangles
    # -----------------------------------------------------------------------------

    # FUNCTION | Cut a Loop With Holes Into Triangles
    # ------------------------------------------------------------
    # A face of a roof can have any number of inside corners, and view.draw fills
    # a fan straight across those. Returns triples of the points it was given, so
    # any extra values they carry, such as a height, come along with them.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__Triangulate(outer, holes = [])
        ring = Na__NobleDrawingTools.Na__DrawnRoofSkeleton__BridgeHoles(outer, holes)
        Na__NobleDrawingTools.Na__DrawnRoofSkeleton__ClipEars(ring)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Join Each Hole to the Outer Loop by a Cut, Making One Loop
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__BridgeHoles(outer, holes)
        ring    = outer.dup
        pending = holes.sort_by { |hole| -hole.map { |point| point[0] }.max }

        until pending.empty?
            hole  = pending.shift
            start = hole.index(hole.max_by { |point| point[0] })
            near  = hole[start]

            walls = []
            ring.each_with_index { |point, index| walls << [point, ring[(index + 1) % ring.length]] }

            (pending + [hole]).each do |other|
                other.each_with_index { |point, index| walls << [point, other[(index + 1) % other.length]] }
            end

            choices = (0...ring.length).sort_by do |index|
                ((ring[index][0] - near[0])**2) + ((ring[index][1] - near[1])**2)
            end

            target = choices.find do |index|
                walls.none? { |a, b| Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SegmentsCross?(near, ring[index], a, b, 1.0e-9) }
            end

            next unless target                                                # <-- Should not happen; the fill loses one hole, the model nothing

            turned = hole.rotate(start)
            ring   = ring[0..target] + turned + [turned.first] + ring[target..-1]
        end

        ring
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clip Ears off a Single Loop
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__ClipEars(ring)
        list      = ring.dup
        triangles = []
        guard     = (list.length * list.length) + 16

        while list.length > 3 && guard > 0
            guard  -= 1
            clipped = false

            list.length.times do |index|
                a = list[index - 1]
                b = list[index]
                c = list[(index + 1) % list.length]

                turn = ((b[0] - a[0]) * (c[1] - b[1])) - ((b[1] - a[1]) * (c[0] - b[0]))

                if turn.abs <= 1.0e-10
                    list.delete_at(index)                                     # <-- No area, nothing lost
                    clipped = true
                    break
                end

                next if turn < 0.0
                next unless Na__NobleDrawingTools.Na__DrawnRoofSkeleton__EarClear?(list, a, b, c)

                triangles << [a, b, c]
                list.delete_at(index)
                clipped = true
                break
            end

            break unless clipped
        end

        if list.length == 3
            a, b, c = list
            turn = ((b[0] - a[0]) * (c[1] - b[1])) - ((b[1] - a[1]) * (c[0] - b[0]))
            triangles << [a, b, c] if turn > 1.0e-10
        end

        triangles
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is an Ear Free of Every Other Corner of the Loop?
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__EarClear?(list, a, b, c)
        list.none? do |point|
            next false if point.equal?(a) || point.equal?(b) || point.equal?(c)
            next false if [a, b, c].any? { |corner| corner[0] == point[0] && corner[1] == point[1] }  # <-- The same corner, met again by a hole's cut

            side_ab = ((b[0] - a[0]) * (point[1] - a[1])) - ((b[1] - a[1]) * (point[0] - a[0]))
            side_bc = ((c[0] - b[0]) * (point[1] - b[1])) - ((c[1] - b[1]) * (point[0] - b[0]))
            side_ca = ((a[0] - c[0]) * (point[1] - c[1])) - ((a[1] - c[1]) * (point[0] - c[0]))

            side_ab >= 0.0 && side_bc >= 0.0 && side_ca >= 0.0
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Points
    # -----------------------------------------------------------------------------

    # FUNCTION | Solve a Roof Over a Plan
    # ------------------------------------------------------------
    # loops have the plan's inside on their left. Returns
    #   :faces   one per roof plane: { :outer, :holes, :normal, :offset, :triangles },
    #            the points being [x, y, t]. A plane's height anywhere is t x slope,
    #            and :normal is the inward direction of its eaves in plan
    #   :lines   every line between two planes: { :a, :b, :kind } of :ridge, :hip, :valley
    #   :height  the highest t, which is the horizontal run the pitch is read over
    #   :volume  at a slope of 1
    #   :loops   the plan, tidied
    # or nil when no tolerance gives a roof that passes the checks.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__Solve(loops)
        cleaned = loops.map { |points| Na__NobleDrawingTools.Na__DrawnRoofSkeleton__CleanLoop(points) }
        cleaned = cleaned.select { |points| points.length >= 3 }
        return nil if cleaned.empty?

        NA_SKEL_TOLERANCES.each do |tolerance|
            begin
                return DrawnRoofSkeleton.new(cleaned, tolerance).solve
            rescue DrawnRoofSkeleton::Failed
                next
            end
        end

        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Push a Plan Outward by a Distance, Mitred at the Corners
    # ------------------------------------------------------------
    # The wavefront again, run on the plan's outside: reverse the loops and the
    # outside is on their left. A recess narrower than twice the distance closes
    # up by itself, and a courtyard that small disappears. Returns loops with the
    # plan's inside on the left, or nil.
    # ------------------------------------------------------------
    def self.Na__DrawnRoofSkeleton__Offset(loops, distance)
        cleaned = loops.map { |points| Na__NobleDrawingTools.Na__DrawnRoofSkeleton__CleanLoop(points) }
        cleaned = cleaned.select { |points| points.length >= 3 }
        return nil if cleaned.empty?
        return cleaned unless distance.to_f > 0.0

        NA_SKEL_TOLERANCES.each do |tolerance|
            begin
                rings  = DrawnRoofSkeleton.new(cleaned.map(&:reverse), tolerance).wavefront_at(distance.to_f)
                result = rings.map { |ring| Na__NobleDrawingTools.Na__DrawnRoofSkeleton__CleanLoop(ring.reverse) }
                result = result.select { |ring| ring.length >= 3 }
                next if result.empty?
                next if result.any? { |ring| Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SelfCrossing?(ring) }

                before = cleaned.inject(0.0) { |sum, ring| sum + Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(ring) }
                after  = result.inject(0.0) { |sum, ring| sum + Na__NobleDrawingTools.Na__DrawnRoofSkeleton__SignedArea(ring) }
                next unless after >= before

                return result
            rescue DrawnRoofSkeleton::Failed
                next
            end
        end

        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DRAWN ROOF SKELETON MODULE
# =============================================================================
