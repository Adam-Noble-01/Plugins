# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE ROUTE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Route__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Turn the user's selected edges into pipe runs, and recognise a
#              pipe this tool built earlier
# CREATED    : 2026
#
# FROM EDGES TO RUNS:
# - The selected edges are a graph. Every vertex with one edge is an END and
#   every vertex with three or more is a JUNCTION; a run is the chain of edges
#   between two of them. Whatever is left over has no ends at all and is a
#   closed loop, built round with no caps and no seam.
# - A junction ends every run that meets it, so a tee becomes three pipes
#   meeting at its centre, each capped there. A loop hanging off a junction
#   comes back to where it started and is built closed.
# - Collinear points (a line split by an intersection) are merged later by
#   the solver, so a route never sprouts a needless ring.
#
# CURVES ARE ALREADY BENT:
# - A vertex inside an arc or circle is SMOOTH: the solver mitres it softly
#   instead of filleting it, because the arc is already the bend the user drew.
#   So is a vertex inside any other curve (a welded polyline, a Bezier) that
#   turns less than NA_DRAWN_PIPE_SMOOTH_MAX_DEG, and the tangent joint where
#   a straight runs into a curve. A welded polyline's real corners still bend.
#
# COORDINATES:
# - Selected edges are always in the active context, where Vertex#position is
#   WORLD at any nesting depth. The runs are world, the pipe group is pinned
#   to the world identity, and nothing here converts anything.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Route Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_DICTIONARY       = 'Na__InsertPrimatives__Pipe'             # <-- Where a pipe keeps its route and spec
    NA_DRAWN_PIPE_SMOOTH_MAX_DEG   = 30.0                                     # <-- A curve turning more than this at a vertex has a corner there
    NA_DRAWN_PIPE_TANGENT_MAX_DEG  = 25.0                                     # <-- A straight meeting a curve within this is a tangent joint

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Reading the Selection
    # -----------------------------------------------------------------------------

    # FUNCTION | Sort the Selection Into Route Edges, Existing Pipes and the Rest
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__ReadSelection(selection)
        edges   = []
        pipes   = []
        ignored = 0

        (selection ? selection.to_a : []).each do |entity|
            next unless entity && entity.valid?

            if entity.is_a?(Sketchup::Edge)
                edges << entity
            elsif Na__InsertPrimatives.Na__DrawnPipe__IsPipe?(entity)
                pipes << entity
            else
                ignored += 1
            end
        end

        {
            :edges   => edges,
            :pipes   => pipes,
            :ignored => ignored,
            :runs    => Na__InsertPrimatives.Na__DrawnPipe__Chains(edges)
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This a Group the Pipe Tool Built?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__IsPipe?(entity)
        return false unless entity.is_a?(Sketchup::Group)

        !entity.get_attribute(NA_DRAWN_PIPE_DICTIONARY, 'Version').nil?
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Edges Into Runs
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Run in a Set of Edges
    # Each run is { :points, :closed, :smooth, :edges }.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__Chains(edges)
        live      = edges.select { |edge| edge && edge.valid? }
        by_vertex = {}

        live.each do |edge|
            edge.vertices.each { |vertex| (by_vertex[vertex.entityID] ||= []) << edge }
        end

        used = {}
        runs = []

        # Open runs first: each one starts at an end or a junction.
        live.each do |edge|
            edge.vertices.each do |vertex|
                touching = by_vertex[vertex.entityID]
                next if touching.length == 2

                touching.each do |first|
                    next if used[first.entityID]

                    runs << Na__InsertPrimatives.Na__DrawnPipe__Walk(vertex, first, by_vertex, used)
                end
            end
        end

        # What is left has no ends: closed loops, each walked once.
        live.each do |edge|
            next if used[edge.entityID]

            runs << Na__InsertPrimatives.Na__DrawnPipe__Walk(edge.start, edge, by_vertex, used)
        end

        runs.compact
    end
    # ---------------------------------------------------------------

    # FUNCTION | Walk One Run From a Vertex Along an Edge
    # Stops at an end, a junction, or back at the start (a loop).
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__Walk(start_vertex, first_edge, by_vertex, used)
        vertices = [start_vertex]
        edges    = []
        vertex   = start_vertex
        edge     = first_edge
        closed   = false

        loop do
            used[edge.entityID] = true
            edges << edge
            vertex = Na__InsertPrimatives.Na__DrawnPipe__OtherEnd(edge, vertex)

            if vertex.entityID == start_vertex.entityID
                closed = true
                break
            end

            vertices << vertex
            touching = by_vertex[vertex.entityID]
            break unless touching.length == 2

            edge = touching.find { |candidate| candidate.entityID != edge.entityID }
            break if edge.nil? || used[edge.entityID]
        end

        points = vertices.map(&:position)

        {
            :points => points,
            :closed => closed,
            :smooth => Na__InsertPrimatives.Na__DrawnPipe__SmoothFlags(points, edges, closed),
            :edges  => edges
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Vertex at the Far End of an Edge
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__OtherEnd(edge, vertex)
        edge.start.entityID == vertex.entityID ? edge.end : edge.start
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Vertices of a Run Lie Inside a Curve
    # ------------------------------------------------------------
    # Vertex i joins edges[i - 1] and edges[i]. An open run's two ends join
    # nothing and are never smooth; a closed run's vertex 0 joins the last
    # edge and the first.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__SmoothFlags(points, edges, closed)
        count = points.length

        Array.new(count) do |index|
            next false if !closed && (index.zero? || index == count - 1)

            before = edges[(index - 1) % edges.length]
            after  = edges[index % edges.length]
            turn   = Na__InsertPrimatives.Na__DrawnPipe__TurnDegrees(
                points[(index - 1) % count], points[index], points[(index + 1) % count]
            )

            Na__InsertPrimatives.Na__DrawnPipe__SmoothJoint?(before, after, turn)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Route Already Curve Through This Joint?
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__SmoothJoint?(before, after, turn_degrees)
        curve_a = before.respond_to?(:curve) ? before.curve : nil
        curve_b = after.respond_to?(:curve)  ? after.curve  : nil

        if curve_a && curve_b && curve_a == curve_b
            return true if defined?(Sketchup::ArcCurve) && curve_a.is_a?(Sketchup::ArcCurve)

            return turn_degrees <= NA_DRAWN_PIPE_SMOOTH_MAX_DEG
        end

        # A straight running on into an arc (or one arc into another): the
        # arc's first segment leaves the tangent by half its own angle, so
        # the joint turns a little. Filleting that would only tighten bends.
        return turn_degrees <= NA_DRAWN_PIPE_TANGENT_MAX_DEG if curve_a || curve_b

        false
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Far a Route Turns at a Point, in Degrees
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__TurnDegrees(before, here, after)
        d_in  = here - before
        d_out = after - here
        return 0.0 if d_in.length.to_f <= 0.0 || d_out.length.to_f <= 0.0

        cosine = d_in.normalize.dot(d_out.normalize)
        cosine = 1.0 if cosine > 1.0
        cosine = -1.0 if cosine < -1.0
        Math.acos(cosine) * 180.0 / Math::PI
    rescue StandardError
        0.0
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE ROUTE
# =============================================================================
