# =============================================================================
# NA INSERT PRIMATIVES - QUAD RINGS (OFFSET, ARRAY AND DIVIDE)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnQuadRings__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Find the ring a quad line belongs to, measure the run it sits
#              on, and cut new rings parallel to it: one, an array, or a
#              divided span
# CREATED    : 2026
#
# DESCRIPTION:
# - QUAD mode leaves lines behind: the start loop of a push, and the inset ring
#   of a loop cut. Those lines had no way back into the tool. A loop cut could
#   only be made from an END face, so every further division of a run of wall
#   meant going back to the end and measuring from there.
# - A QUAD LINE is an edge dividing a flat surface: exactly two faces, and the
#   two are coplanar. That is precisely what a quad ring leaves on each side of
#   a solid, and nothing else in a model looks like it.
# - This module walks from one quad line round the whole ring it belongs to,
#   finds the direction the run goes (the RAILS, the edges the ring's corners
#   sit on), measures how much run there is each way, and cuts new rings
#   parallel to it. The tool side lives in DrawnPushPull__QuadOffset__.
#
# HOW THE RING IS WALKED (the edge-loop rule):
# - At each corner of a ring four edges meet: the ring edge arriving, the ring
#   edge leaving, and a rail each way along the run. The ring edge leaving is
#   the ONE edge there that shares no face with the edge arriving. Both rails
#   share a face with it. So the walk takes that edge, and carries on while it
#   is itself a quad line.
# - Back at the edge it started from, the ring is closed. A dead end instead
#   (a line drawn across one face only, whose ends sit on a corner) gives an
#   OPEN chain, and an open chain offsets just as well: every point of it rides
#   along its own rail.
#
# WHY THE NEW RING LANDS ON REAL FACES:
# - Every face the ring crosses contains the run direction (that is checked,
#   not assumed), so a ring edge moved along the run stays in its own face and
#   add_edges splits that face. Every ring corner sits on a rail, so a corner
#   moved along the run stays on its rail and splits it. The quad ring's
#   stitch then removes the fill face a closed ring makes and sweeps away
#   anything that bounded nothing, exactly as for a loop cut.
#
# THE RUN ENDS SOMEWHERE, AND THE ARRAY IS CHECKED AGAINST IT:
# - From each ring corner the rails are followed, through every collinear
#   piece, to where the run turns or stops. The shortest walk is the reach that
#   way. An offset, the last ring of an array, or a divided span must stay
#   short of it; the tool refuses anything past it and names the count that
#   does fit, rather than silently dropping the rings that fall off the end.
#
# COORDINATES (the rule in the DeepPick hub header):
# - Topology is walked and rails are compared in the space the entities
#   REPORT, where every position of one definition agrees. Reach and every
#   drawn point are world, through the pick's transformation. The commit
#   re-reads the ring INSIDE its operation, so the positions it offsets are in
#   the space the collection is accepting at that moment.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__QuadRing__'
require_relative 'Na__InsertPrimatives__DrawnEdgeLoops__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Quad Ring Constants
    # -----------------------------------------------------------------------------

    NA_QUAD_RING_RAIL_DOT   = 0.9998                                          # <-- cos ~1.1 degrees; an edge this parallel to the run is a rail
    NA_QUAD_RING_PLANE_DOT  = 0.0035                                          # <-- |normal . run| below this and the face contains the run
    NA_QUAD_RING_MAX_EDGES  = 4096                                            # <-- Walk guard on a ring that never closes
    NA_QUAD_RING_MAX_STEPS  = 4096                                            # <-- Walk guard along a rail
    NA_QUAD_RING_MAX_COUNT  = 200                                             # <-- The most rings one entry may cut
    NA_QUAD_RING_GRAB_PX    = 12.0                                            # <-- A quad line this close to the cursor is offered
    NA_QUAD_RING_PROBE_TOL  = 0.002                                           # <-- Inches; finding an edge again after an undo

    # One entry, one operator. The operator is * (array) or / (divide), and x,
    # the multiplication sign and the division sign are read as the same two,
    # so "4x", "x4", "*4" and "4*" are one entry typed four ways, as in native.
    NA_QUAD_RING_OPERATOR_PATTERN = %r{\A(.*?)\s*([*/])\s*(.*?)\z}m

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | What Counts as a Quad Line
    # -----------------------------------------------------------------------------

    # FUNCTION | Does This Edge Divide a Flat Surface?
    # Two faces, coplanar. A corner of the solid has two faces at an angle; a
    # loose line bounds none; a line on a crease or a T-junction bounds more.
    # Two faces sharing an edge with parallel normals share one plane, so the
    # normal test is the whole test (and reversed faces pass it too).
    # ------------------------------------------------------------
    def self.Na__QuadRings__QuadLine?(edge)
        return false unless edge.is_a?(Sketchup::Edge) && edge.valid?

        faces = edge.faces
        return false unless faces.length == 2

        faces[0].normal.parallel?(faces[1].normal)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does a Face Carry at Least One Quad Line?
    # Only asks the question the face hover wants answered: is there anything
    # here worth offering "hover the line to offset it" for.
    # ------------------------------------------------------------
    def self.Na__QuadRings__FaceHasQuadLine?(face)
        return false unless face && face.valid?

        face.edges.any? { |edge| Na__InsertPrimatives.Na__QuadRings__QuadLine?(edge) }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Walking the Ring
    # -----------------------------------------------------------------------------

    # FUNCTION | The Edge That Carries a Ring On Through a Vertex, or nil
    # The one edge at the vertex sharing no face with the edge arriving. Both
    # rails share a face with it, so on a clean ring corner exactly one edge
    # is left. None, or more than one, and the ring stops here.
    # ------------------------------------------------------------
    def self.Na__QuadRings__NextEdge(current, vertex)
        arriving = current.faces

        onward = vertex.edges.select do |edge|
            next false if edge == current

            edge.faces.none? { |face| arriving.include?(face) }
        end

        return nil unless onward.length == 1
        return nil unless Na__InsertPrimatives.Na__QuadRings__QuadLine?(onward[0])

        onward[0]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Walk From One End of an Edge Until the Ring Closes or Stops
    # Returns [edges, vertices, closed]: the edges after the start edge, the
    # far vertex of each, and whether the walk arrived back at the start edge.
    # ------------------------------------------------------------
    def self.Na__QuadRings__WalkFrom(start_edge, vertex)
        edges    = []
        vertices = []
        current  = start_edge
        at       = vertex

        while edges.length < NA_QUAD_RING_MAX_EDGES
            onward = Na__InsertPrimatives.Na__QuadRings__NextEdge(current, at)
            break unless onward
            return [edges, vertices, true] if onward == start_edge
            break if edges.include?(onward)                                   # <-- A figure-eight; stop rather than spin

            edges << onward
            at = onward.other_vertex(at)
            vertices << at
            current = onward
        end

        [edges, vertices, false]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Whole Ring (or Open Chain) a Quad Line Belongs To
    # Returns { :edges, :vertices, :closed } with the vertices in order round
    # the ring, or nil when the edge is not a quad line.
    # ------------------------------------------------------------
    def self.Na__QuadRings__WalkRing(edge)
        return nil unless Na__InsertPrimatives.Na__QuadRings__QuadLine?(edge)

        forward, ahead, closed = Na__InsertPrimatives.Na__QuadRings__WalkFrom(edge, edge.end)

        if closed
            # The last vertex walked IS the start edge's start, so it is dropped
            # rather than listed twice.
            return {
                :edges    => [edge] + forward,
                :vertices => [edge.start, edge.end] + ahead[0...-1],
                :closed   => true
            }
        end

        backward, behind, _closed = Na__InsertPrimatives.Na__QuadRings__WalkFrom(edge, edge.start)

        {
            :edges    => backward.reverse + [edge] + forward,
            :vertices => behind.reverse + [edge.start, edge.end] + ahead,
            :closed   => false
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Run
    # -----------------------------------------------------------------------------

    # FUNCTION | Unit Direction From One Vertex Along an Edge, or nil
    # ------------------------------------------------------------
    def self.Na__QuadRings__EdgeDirectionFrom(edge, vertex)
        vector = edge.other_vertex(vertex).position - vertex.position
        return nil if vector.length <= 0.0

        vector.normalize
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Direction the Run Goes, in the Space the Ring Reports In
    # ------------------------------------------------------------
    # From a rail at one of the grabbed edge's ends. With a face hint (the
    # face the cursor was on) it is that face's own edge beside the quad line,
    # so the answer points into the quad being hovered. With a direction hint
    # (finding a placed ring again after an undo) it is whichever rail runs
    # most nearly that way, turned to agree with it, so a signed offset keeps
    # the side it was made on.
    # ------------------------------------------------------------
    def self.Na__QuadRings__RunDirection(edge, ring_edges, hint_face = nil, hint_dir = nil)
        [edge.start, edge.end].each do |vertex|
            rails = vertex.edges.reject { |candidate| ring_edges.include?(candidate) }

            if hint_face
                rail = rails.find { |candidate| candidate.faces.include?(hint_face) }
                next unless rail

                direction = Na__InsertPrimatives.Na__QuadRings__EdgeDirectionFrom(rail, vertex)
                return direction if direction
            elsif hint_dir
                best  = nil
                score = 0.0

                rails.each do |candidate|
                    direction = Na__InsertPrimatives.Na__QuadRings__EdgeDirectionFrom(candidate, vertex)
                    next unless direction

                    dot = direction.dot(hint_dir).to_f
                    next unless dot.abs > score

                    score = dot.abs
                    best  = dot < 0.0 ? direction.reverse : direction
                end

                return best if best && score > NA_QUAD_RING_RAIL_DOT
            end
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does Every Face the Ring Crosses Contain the Run?
    # The check that makes the offset honest: a ring edge moved along the run
    # only stays in its face if the face contains the run. A tapered or
    # chamfered piece fails here and is refused before anything is cut.
    # ------------------------------------------------------------
    def self.Na__QuadRings__RunClear?(ring_edges, direction)
        ring_edges.all? do |edge|
            edge.faces.all? { |face| face.normal.dot(direction).to_f.abs < NA_QUAD_RING_PLANE_DOT }
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Follow a Rail From a Vertex to Where the Run Stops
    # ------------------------------------------------------------
    # Every collinear piece is walked through, because the run is cut into
    # pieces by every quad line already on it. Returns the vertex the run
    # stops at; the vertex itself when the run stops right here (a rail runs
    # the other way and none this way); nil when no rail touches the vertex
    # at all, which says nothing about the run and is left out of the reach.
    # ------------------------------------------------------------
    def self.Na__QuadRings__RailEnd(vertex, direction)
        at    = vertex
        steps = 0

        while steps < NA_QUAD_RING_MAX_STEPS
            rail = at.edges.find do |edge|
                heading = Na__InsertPrimatives.Na__QuadRings__EdgeDirectionFrom(edge, at)
                heading && heading.dot(direction).to_f > NA_QUAD_RING_RAIL_DOT
            end
            break unless rail

            at     = rail.other_vertex(at)
            steps += 1
        end

        return at if steps > 0

        backwards = vertex.edges.any? do |edge|
            heading = Na__InsertPrimatives.Na__QuadRings__EdgeDirectionFrom(edge, vertex)
            heading && heading.dot(direction).to_f < -NA_QUAD_RING_RAIL_DOT
        end

        backwards ? vertex : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far the Run Goes One Way, in World Inches, or nil
    # The shortest rail wins: the new ring has to land on every one of them.
    # nil when no corner of the ring sits on a rail running either way, which
    # leaves the offset unchecked rather than refused.
    # ------------------------------------------------------------
    def self.Na__QuadRings__Reach(vertices, direction_rep, xform, direction_world)
        shortest = nil

        vertices.each do |vertex|
            stop = Na__InsertPrimatives.Na__QuadRings__RailEnd(vertex, direction_rep)
            next unless stop

            travel = (stop.position.transform(xform) - vertex.position.transform(xform)).dot(direction_world).to_f
            shortest = travel if shortest.nil? || travel < shortest
        end

        shortest.nil? ? nil : [shortest, 0.0].max
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Space Conversion for Directions
    # -----------------------------------------------------------------------------

    # FUNCTION | A Reported-Space Direction in World, as a Unit Vector
    # Two points rather than the vector, the same rule the push tool keeps: a
    # direction is a difference of positions, and transforming positions
    # cannot be caught out by how a bare vector treats the translation.
    # ------------------------------------------------------------
    def self.Na__QuadRings__WorldDirection(direction_rep, xform)
        origin = Geom::Point3d.new(0, 0, 0)
        vector = origin.offset(direction_rep).transform(xform) - origin.transform(xform)
        return nil if vector.length <= 0.0

        vector.normalize
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Direction in the Space the Ring Reports In
    # ------------------------------------------------------------
    def self.Na__QuadRings__ReportedDirection(direction_world, xform)
        Na__InsertPrimatives.Na__QuadRings__WorldDirection(direction_world, xform.inverse)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Analysis — Everything the Tool Needs About a Ring
    # -----------------------------------------------------------------------------

    # FUNCTION | Analyse the Ring Through a Quad Line
    # ------------------------------------------------------------
    # Returns a hash the tool draws, measures and cuts from, or one carrying
    # :refusal (a sentence for the status bar) when the line is a quad line on
    # a run that cannot be offset, or nil when the edge is no quad line at all.
    # ------------------------------------------------------------
    def self.Na__QuadRings__Analyse(edge, xform, hint_face = nil, hint_dir = nil)
        walk = Na__InsertPrimatives.Na__QuadRings__WalkRing(edge)
        return nil unless walk

        direction = Na__InsertPrimatives.Na__QuadRings__RunDirection(edge, walk[:edges], hint_face, hint_dir)
        return { :refusal => 'this quad line has no straight run beside it to offset along' } unless direction

        unless Na__InsertPrimatives.Na__QuadRings__RunClear?(walk[:edges], direction)
            return { :refusal => 'the faces round this quad line taper or turn, so a ring cannot slide along them' }
        end

        world = Na__InsertPrimatives.Na__QuadRings__WorldDirection(direction, xform)
        return { :refusal => 'this quad line could not be measured in world space' } unless world

        {
            :kind          => :ring,
            :edge          => edge,
            :edges         => walk[:edges],
            :vertices      => walk[:vertices],
            :closed        => walk[:closed],
            :direction_rep => direction,
            :direction     => world,
            :ring_world    => walk[:vertices].map { |vertex| vertex.position.transform(xform) },
            :reach_pos     => Na__InsertPrimatives.Na__QuadRings__Reach(walk[:vertices], direction, xform, world),
            :reach_neg     => Na__InsertPrimatives.Na__QuadRings__Reach(walk[:vertices], direction.reverse, xform, world.reverse)
        }
    rescue StandardError => error
        { :refusal => "the ring could not be read (#{error.message})" }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Analyse a Face's Own Loop as the Ring to Offset From
    # ------------------------------------------------------------
    # The loop cut's reference: the end face of a run, offset INTO the solid.
    # There is no run behind a face, so the reach the other way is nil and the
    # tool never offers it; every face round the loop is left for the stitch
    # to prove, exactly as the loop cut always did.
    # ------------------------------------------------------------
    def self.Na__QuadRings__AnalyseFace(face, xform, direction_world)
        return nil unless face && face.valid? && direction_world

        direction = Na__InsertPrimatives.Na__QuadRings__ReportedDirection(direction_world, xform)
        return nil unless direction

        vertices = face.outer_loop.vertices

        {
            :kind          => :face,
            :face          => face,
            :edges         => face.outer_loop.edges,
            :vertices      => vertices,
            :closed        => true,
            :direction_rep => direction,
            :direction     => direction_world.normalize,
            :ring_world    => vertices.map { |vertex| vertex.position.transform(xform) },
            :reach_pos     => Na__InsertPrimatives.Na__QuadRings__Reach(vertices, direction, xform, direction_world.normalize),
            :reach_neg     => 0.0
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Layout — One, an Array, or a Divided Span
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Offset a Layout Places, Signed, in World Inches
    # ------------------------------------------------------------
    # distance is what the user dragged or typed. An array repeats it: *4 is
    # rings at 1, 2, 3 and 4 times the distance. A divide splits it: /4 is
    # rings at a quarter, a half, three quarters and the whole distance. Both
    # read exactly as native Move's copy array does.
    # ------------------------------------------------------------
    def self.Na__QuadRings__Offsets(distance, count = 1, mode = :array)
        total = count.to_i < 1 ? 1 : count.to_i
        span  = distance.to_f

        (1..total).map do |index|
            mode == :divide ? span * index / total : span * index
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Gap Between Neighbouring Rings of a Layout
    # ------------------------------------------------------------
    def self.Na__QuadRings__Spacing(distance, count = 1, mode = :array)
        total = count.to_i < 1 ? 1 : count.to_i
        mode == :divide ? distance.to_f.abs / total : distance.to_f.abs
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Length as Millimetres, One Decimal Only When It Has One
    # A divided span is rarely whole, and 428.6 is more honest than 429.
    # ------------------------------------------------------------
    def self.Na__QuadRings__MmText(value)
        millimetres = (value.to_f * NA_DRAWN_INCH_TO_MM).abs
        whole       = millimetres.round

        return whole.to_s if (millimetres - whole).abs < 0.05

        format('%.1f', millimetres)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Measurements Box Entry
    # -----------------------------------------------------------------------------

    # FUNCTION | Does This Entry Ask for an Array or a Divide?
    # ------------------------------------------------------------
    def self.Na__QuadRings__ArrayEntry?(text)
        Na__InsertPrimatives.Na__QuadRings__NormaliseEntry(text).include?('*') ||
            Na__InsertPrimatives.Na__QuadRings__NormaliseEntry(text).include?('/')
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Spelling for Every Way of Typing an Operator
    # x, X and the multiplication sign are *, the division sign is /, and a
    # comma is a space, so "450, *4" reads the same as "450*4".
    # ------------------------------------------------------------
    def self.Na__QuadRings__NormaliseEntry(text)
        text.to_s.strip.tr("xX×÷,", '***/ ').strip
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read an Entry as a Distance, a Count, or Both
    # ------------------------------------------------------------
    # Returns { :distance, :count, :mode }. :distance is the shared parser's
    # token ([sign, inches]) or nil when none was typed; :count and :mode are
    # nil when the entry carries no operator.
    #
    #   450        a distance            *4  x4  4x  4*   an array of 4
    #   +50 / -25  relative or reversed  /7  7/           a divide into 7
    #   450*4      both                  3000/7           both
    #
    # Refusals name the fix. *0 and /0 say what *1 does; a fractional count
    # says which whole numbers are either side of it.
    # ------------------------------------------------------------
    def self.Na__QuadRings__ParseEntry(text)
        cleaned = Na__InsertPrimatives.Na__QuadRings__NormaliseEntry(text)
        raise ArgumentError, 'no value entered' if cleaned.empty?

        match = NA_QUAD_RING_OPERATOR_PATTERN.match(cleaned)

        unless match
            raise ArgumentError, 'a quad offset takes one distance' if cleaned.include?(' ')

            return { :distance => Na__InsertPrimatives.Na__DrawnVcb__ParseToken(cleaned), :count => nil, :mode => nil }
        end

        before   = match[1].to_s.strip
        operator = match[2]
        after    = match[3].to_s.strip

        if (before + after).include?('*') || (before + after).include?('/')
            raise ArgumentError, 'one * or / at a time — *4 for an array, /7 to divide'
        end

        # Count before the operator ("4x", "7/") only when nothing follows it;
        # with both sides filled the count comes after, the native order.
        count_text, distance_text = after.empty? ? [before, ''] : [after, before]
        mode = operator == '/' ? :divide : :array
        sign = operator == '/' ? '/' : '*'

        raise ArgumentError, "#{sign} needs a count — *4 for an array, /7 to divide" if count_text.empty?

        if count_text =~ /\A\d+\.\d+\z/
            low = count_text.to_f.floor
            raise ArgumentError, "a count is a whole number — #{sign}#{low} or #{sign}#{low + 1}"
        end

        unless count_text =~ /\A\d+\z/
            raise ArgumentError, "cannot read '#{count_text}' as a count — type #{sign}4"
        end

        count = count_text.to_i

        if count < 1
            raise ArgumentError, "#{sign}0 makes no rings — #{sign}1 is a single ring, #{sign}2 or more #{mode == :divide ? 'divides the span' : 'repeats it'}"
        end

        if count > NA_QUAD_RING_MAX_COUNT
            raise ArgumentError, "#{sign}#{count} is more rings than one entry cuts — #{NA_QUAD_RING_MAX_COUNT} at most"
        end

        distance = distance_text.empty? ? nil : Na__InsertPrimatives.Na__DrawnVcb__ParseToken(distance_text)

        { :distance => distance, :count => count, :mode => mode }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Cutting a Ring
    # -----------------------------------------------------------------------------

    # FUNCTION | Stitch One Ring (Closed) or Chain (Open) Into the Faces It Crosses
    # ------------------------------------------------------------
    # A closed ring is the quad ring's own case and goes straight to it: the
    # landing check, the fill-face removal and the self-clean all apply. An
    # open chain must NOT be closed (the quad ring adds the closing edge), so
    # it gets the same three steps here without that edge. It can never make
    # a fill face, having no loop of its own to fill.
    #
    # Returns the quad ring's stats: { :kept, :swept, :faces_removed, :misplaced }.
    # ------------------------------------------------------------
    def self.Na__QuadRings__Stitch(entities, points, closed, build_transform)
        return Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, [points], build_transform) if closed

        stats = { :kept => 0, :swept => 0, :faces_removed => 0, :misplaced => false }
        return stats if entities.nil? || points.nil? || points.length < 2

        edges = entities.add_edges(points.map { |point| point.transform(build_transform) })
        return stats if edges.nil? || edges.empty?

        unless Na__InsertPrimatives.Na__PushPull__RingLanded?(edges, points)
            stats[:misplaced] = true
            edges.each { |edge| edge.erase! if edge.valid? }
            return stats
        end

        edges.each do |edge|
            next unless edge.valid?

            if edge.faces.empty?
                edge.erase!
                stats[:swept] += 1
            else
                stats[:kept] += 1
            end
        end

        stats
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Screen Picking
    # -----------------------------------------------------------------------------

    # FUNCTION | Pixels From the Cursor to a World Segment, or nil
    # nil when either end is behind a perspective camera: a segment folded
    # through the eye projects to nonsense, and an offer made from nonsense is
    # worse than none.
    # ------------------------------------------------------------
    def self.Na__QuadRings__ScreenDistance(view, point_a, point_b, x, y)
        screen = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, [point_a, point_b])
        return nil unless screen

        ax, ay = screen[0].x.to_f, screen[0].y.to_f
        bx, by = screen[1].x.to_f, screen[1].y.to_f
        dx, dy = bx - ax, by - ay
        length = (dx * dx) + (dy * dy)

        t = length <= 0.0 ? 0.0 : (((x.to_f - ax) * dx) + ((y.to_f - ay) * dy)) / length
        t = 0.0 if t < 0.0
        t = 1.0 if t > 1.0

        px = ax + (dx * t) - x.to_f
        py = ay + (dy * t) - y.to_f
        Math.sqrt((px * px) + (py * py))
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Quad Line of a Face Nearest the Cursor, Within Reach
    # Every edge of the face is measured on screen first (cheap) and only the
    # closest ones are asked whether they are quad lines. Returns the edge or nil.
    # ------------------------------------------------------------
    def self.Na__QuadRings__NearestQuadLine(view, face, xform, x, y, max_px = NA_QUAD_RING_GRAB_PX)
        return nil unless face && face.valid?

        measured = face.edges.map do |edge|
            px = Na__InsertPrimatives.Na__QuadRings__ScreenDistance(
                view, edge.start.position.transform(xform), edge.end.position.transform(xform), x, y
            )
            px && px <= max_px ? [edge, px] : nil
        end.compact

        measured.sort_by { |pair| pair[1] }.each do |edge, _px|
            return edge if Na__InsertPrimatives.Na__QuadRings__QuadLine?(edge)
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Point on a World Segment Nearest a Pick Ray
    # ------------------------------------------------------------
    def self.Na__QuadRings__PointOnSegment(point_a, point_b, ray)
        along = point_b - point_a
        return point_a if along.length <= 0.0

        closest = Geom.closest_points([point_a, along], ray)
        return point_a unless closest && closest[0]

        t = (closest[0] - point_a).dot(along).to_f / (along.length.to_f ** 2)
        t = 0.0 if t < 0.0
        t = 1.0 if t > 1.0

        Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point_a, along, t)
    rescue StandardError
        point_a
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Point on a Ring Nearest a World Point
    # Where a face-loop ring's dimension string starts: on the loop, beside
    # where the face was grabbed, so the string runs along a side face rather
    # than through the middle of the solid.
    # ------------------------------------------------------------
    def self.Na__QuadRings__NearestOnRing(ring_points, closed, point)
        return point if ring_points.nil? || ring_points.length < 2

        segments = ring_points.each_cons(2).to_a
        segments << [ring_points.last, ring_points.first] if closed

        best      = nil
        best_dist = nil

        segments.each do |point_a, point_b|
            along  = point_b - point_a
            length = along.length.to_f
            next if length <= 0.0

            t = (point - point_a).dot(along).to_f / (length * length)
            t = 0.0 if t < 0.0
            t = 1.0 if t > 1.0

            candidate = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point_a, along, t)
            distance  = candidate.distance(point)
            next unless best_dist.nil? || distance < best_dist

            best      = candidate
            best_dist = distance
        end

        best || point
    rescue StandardError
        point
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF QUAD RINGS MODULE
# =============================================================================
