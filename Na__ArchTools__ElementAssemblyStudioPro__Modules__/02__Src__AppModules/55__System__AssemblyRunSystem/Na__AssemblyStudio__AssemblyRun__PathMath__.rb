# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - PATH MATHS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__PathMath__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__PathMath
# AUTHOR     : Noble Architecture
# PURPOSE    : The plan geometry of a run's path, with no SketchUp in it:
#              points to legs, the turn at each corner, a point along a leg,
#              legs back to points, and loose line segments chained into one
#              path (how Edit Path reads the red line back).
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# THE PATH
# - A list of [x, y] points in millimetres, in the run component's own plan
#   (z = 0 at the run's base). Stored as data on the run, as the Profile Path
#   Tracer stores a trace's PathRuns, so it can be edited as numbers in the
#   dialog and as a line in SketchUp.
# - A closed path does not repeat its first point.
# - Turns are signed: positive turns LEFT (anticlockwise from above).
# - "Left" of a leg is +Y of the leg's own frame, the side an element's own
#   +Y lies on: into the building for a frame, the wall for a cabinet.
#
# PURE RUBY: no Sketchup or Geom calls, so the offline suite can run it.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__PathMath

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_SAME_POINT_MM       = 0.05                                            # <-- Two points nearer than this are one
        NA_STRAIGHT_TURN_DEG   = 0.2                                             # <-- A smaller turn than this is no corner
        NA_RADIANS             = Math::PI / 180.0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Vectors (Plain [x, y] Arrays)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | a + b * scale
        # ------------------------------------------------------------
        def self.na_add(a, b, scale = 1.0)
            [a[0] + b[0] * scale, a[1] + b[1] * scale]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Distance Between Two Points
        # ------------------------------------------------------------
        def self.na_distance(a, b)
            Math.hypot(b[0] - a[0], b[1] - a[1])
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Unit Direction From a to b (Nil When They Coincide)
        # ------------------------------------------------------------
        def self.na_direction(a, b)
            length = na_distance(a, b)
            return nil if length < NA_SAME_POINT_MM
            [(b[0] - a[0]) / length, (b[1] - a[1]) / length]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Left Normal of a Direction (z cross d)
        # ------------------------------------------------------------
        def self.na_left(direction)
            [-direction[1], direction[0]]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Right Normal of a Direction
        # ------------------------------------------------------------
        def self.na_right(direction)
            [direction[1], -direction[0]]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Signed Turn From One Direction to the Next (Degrees)
        # ------------------------------------------------------------
        # Positive turns left. 0 carries straight on; +-180 doubles back.
        def self.na_turn_deg(direction_in, direction_out)
            cross = direction_in[0] * direction_out[1] - direction_in[1] * direction_out[0]
            dot   = direction_in[0] * direction_out[0] + direction_in[1] * direction_out[1]
            Math.atan2(cross, dot) / NA_RADIANS
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Direction Turned by an Angle (Degrees, Positive Left)
        # ------------------------------------------------------------
        def self.na_rotate(direction, degrees)
            cos = Math.cos(degrees * NA_RADIANS)
            sin = Math.sin(degrees * NA_RADIANS)
            [direction[0] * cos - direction[1] * sin, direction[0] * sin + direction[1] * cos]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Points In, Points Out
# -----------------------------------------------------------------------------

        # FUNCTION | Tidy a Point List Into a Path
        # ------------------------------------------------------------
        # Numbers as floats, repeated points dropped, a closing repeat of the
        # first point dropped, and a point on a straight line between its
        # neighbours dropped (it is not a corner).
        # @param points [Array<Array>] [[x, y], ...] in mm (a third value is ignored)
        # @return [Array<Array<Float>>]
        def self.na_clean_points(points, closed = false)
            list = Array(points).map { |point| [point[0].to_f, point[1].to_f] }
            list = list.each_with_object([]) { |point, kept| kept << point if kept.empty? || na_distance(kept.last, point) >= NA_SAME_POINT_MM }
            list.pop if closed && list.length > 1 && na_distance(list.first, list.last) < NA_SAME_POINT_MM
            na_drop_straight_points(list, closed)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Drop Points That Lie on a Straight Run
        # ------------------------------------------------------------
        def self.na_drop_straight_points(list, closed)
            changed = true
            while changed && list.length > 2
                changed = false
                first   = closed ? 0 : 1
                last    = closed ? list.length - 1 : list.length - 2
                (first..last).each do |index|
                    before = list[(index - 1) % list.length]
                    after  = list[(index + 1) % list.length]
                    d_in   = na_direction(before, list[index])
                    d_out  = na_direction(list[index], after)
                    next unless d_in && d_out && na_turn_deg(d_in, d_out).abs < NA_STRAIGHT_TURN_DEG
                    list.delete_at(index)
                    changed = true
                    break
                end
            end
            list
        end
        private_class_method :na_drop_straight_points
        # ---------------------------------------------------------------

        # FUNCTION | The Legs of a Path
        # ------------------------------------------------------------
        # @return [Array<Hash>] { :index, :p0, :p1, :dir, :left, :length, :angle_deg }
        def self.na_legs(points, closed = false)
            count = closed ? points.length : points.length - 1
            (0...[count, 0].max).map do |index|
                p0        = points[index]
                p1        = points[(index + 1) % points.length]
                direction = na_direction(p0, p1) || [1.0, 0.0]
                {
                    :index     => index,
                    :p0        => p0,
                    :p1        => p1,
                    :dir       => direction,
                    :left      => na_left(direction),
                    :length    => na_distance(p0, p1),
                    :angle_deg => Math.atan2(direction[1], direction[0]) / NA_RADIANS
                }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point on a Leg: a Station Along It, an Offset to Its Left
        # ------------------------------------------------------------
        def self.na_point_on_leg(leg, station, left_offset = 0.0)
            na_add(na_add(leg[:p0], leg[:dir], station), leg[:left], left_offset)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Path as Leg Lengths and Turns (the Dialog's Table)
        # ------------------------------------------------------------
        # @return [Array<Hash>] { "Length_mm", "Turn_deg" }: Turn_deg is the
        #     turn at the END of that leg into the next (0 on the last leg of
        #     an open path)
        def self.na_leg_rows(points, closed = false)
            legs = na_legs(points, closed)
            legs.each_with_index.map do |leg, index|
                following = closed ? legs[(index + 1) % legs.length] : legs[index + 1]
                turn      = following ? na_turn_deg(leg[:dir], following[:dir]) : 0.0
                { "Length_mm" => leg[:length].round(2), "Turn_deg" => turn.round(3) }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Leg Lengths and Turns Back Into Points
        # ------------------------------------------------------------
        # The first leg starts at [0, 0] along +X (or start / heading given).
        # @param rows [Array<Hash>] { "Length_mm", "Turn_deg" }
        # @return [Array<Array<Float>>] one more point than rows (an open path)
        def self.na_points_from_leg_rows(rows, start = [0.0, 0.0], heading = [1.0, 0.0])
            points    = [[start[0].to_f, start[1].to_f]]
            direction = heading
            Array(rows).each do |row|
                points << na_add(points.last, direction, row["Length_mm"].to_f)
                direction = na_rotate(direction, row["Turn_deg"].to_f)
            end
            points.map { |point| [point[0].round(3), point[1].round(3)] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Smallest Box Round a Set of Points
        # ------------------------------------------------------------
        # @return [Hash] { :min => [x, y], :max => [x, y] }
        def self.na_bounds(points)
            return { :min => [0.0, 0.0], :max => [0.0, 0.0] } if points.empty?
            xs = points.map { |point| point[0] }
            ys = points.map { |point| point[1] }
            { :min => [xs.min, ys.min], :max => [xs.max, ys.max] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Side of a Path a Point Lies On
        # ------------------------------------------------------------
        # Judged on the leg nearest the point.
        # @return [Symbol] :left or :right
        def self.na_side_of(points, closed, side_point)
            nearest = na_legs(points, closed).min_by { |leg| na_distance_to_leg(leg, side_point) }
            return :right unless nearest
            offset = (side_point[0] - nearest[:p0][0]) * nearest[:left][0] + (side_point[1] - nearest[:p0][1]) * nearest[:left][1]
            offset > 0 ? :left : :right
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Distance From a Point to a Leg's Segment
        # ------------------------------------------------------------
        def self.na_distance_to_leg(leg, point)
            along   = (point[0] - leg[:p0][0]) * leg[:dir][0] + (point[1] - leg[:p0][1]) * leg[:dir][1]
            clamped = [[along, 0.0].max, leg[:length]].min
            na_distance(na_add(leg[:p0], leg[:dir], clamped), point)
        end
        private_class_method :na_distance_to_leg
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Loose Segments Chained Into One Path (Edit Path Read-Back)
# -----------------------------------------------------------------------------

        # FUNCTION | Chain Line Segments Into One Ordered Path
        # ------------------------------------------------------------
        # @param segments [Array<Array>] [[[x, y], [x, y]], ...] in any order
        # @param start_near [Array, nil] the end to start from, when the path
        #     is open: the end nearer this point comes first
        # @return [Hash] { :points => [[x, y], ...], :closed => Boolean }
        # @raise [ArgumentError] when the segments branch or are several paths
        def self.na_chain_segments(segments, start_near = nil)
            pairs = Array(segments).map { |a, b| [[a[0].to_f, a[1].to_f], [b[0].to_f, b[1].to_f]] }
            pairs = pairs.reject { |a, b| na_distance(a, b) < NA_SAME_POINT_MM }
            raise ArgumentError, "The path has no lines." if pairs.empty?

            nodes = na_chain_nodes(pairs)
            links = Array.new(nodes.length) { [] }
            pairs.each do |a, b|
                ia = na_node_index(nodes, a)
                ib = na_node_index(nodes, b)
                links[ia] << ib
                links[ib] << ia
            end
            raise ArgumentError, "The path branches: three lines meet at one point. A run follows one line." if links.any? { |list| list.length > 2 }

            ends   = (0...nodes.length).select { |index| links[index].length == 1 }
            closed = ends.empty?
            raise ArgumentError, "The path is in #{ends.length / 2} separate pieces. Join them into one line." if ends.length > 2

            start = closed ? 0 : na_chain_start(nodes, ends, start_near)
            order = na_chain_walk(links, start)
            raise ArgumentError, "The path is in separate pieces. Join them into one line." if order.length != nodes.length
            { :points => na_clean_points(order.map { |index| nodes[index] }, closed), :closed => closed }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Distinct End Points of the Segments
        # ------------------------------------------------------------
        def self.na_chain_nodes(pairs)
            nodes = []
            pairs.flatten(1).each { |point| nodes << point unless na_node_index(nodes, point) }
            nodes
        end
        private_class_method :na_chain_nodes
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Which Node a Point Is (Nil When None)
        # ------------------------------------------------------------
        def self.na_node_index(nodes, point)
            nodes.index { |node| na_distance(node, point) < NA_SAME_POINT_MM }
        end
        private_class_method :na_node_index
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The End an Open Chain Starts From
        # ------------------------------------------------------------
        def self.na_chain_start(nodes, ends, start_near)
            return ends.first unless start_near
            ends.min_by { |index| na_distance(nodes[index], start_near) }
        end
        private_class_method :na_chain_start
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Walk the Links From a Start Node
        # ------------------------------------------------------------
        def self.na_chain_walk(links, start)
            order    = [start]
            previous = nil
            current  = start
            loop do
                following = links[current].find { |index| index != previous && !order.include?(index) }
                break unless following
                order << following
                previous = current
                current  = following
            end
            order
        end
        private_class_method :na_chain_walk
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PathMath
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
