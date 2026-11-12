# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - PLAN GEOMETRY
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__PlanGeometry__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__PlanGeometry
# PURPOSE    : Pure maths on plain [x, y] / [x, y, z] arrays for the 1.0.30
#              sketch and site tools: chaining edges into polylines, fitting
#              lines and arcs to a rough sketch, parallel offsets with end caps,
#              band outlines, a plane-to-photo homography, photo flattening
#              (a rectangle's proportions from its perspective, an unknown
#              height solved from known points, the pixel warp; 1.0.33), and
#              footprint comparison (area, overlap, outline distance)
# CREATED    : 12-Nov-2026
#
# NO SKETCHUP API HERE:
# Every function takes and returns plain Ruby arrays and numbers, in whatever
# length unit the caller uses (the handlers pass inches). That keeps the maths
# testable offline with SketchUp's own Ruby (Tests__BridgeCore) and keeps the
# coordinate rule out of it: callers convert world points in and out through
# Na__Coordinates / Na__Creation / Na__Serializer, as every handler does.
#
# WHY THESE TOOLS EXIST (Corrett 64610, 12-Nov-2026):
# An agent spent three rounds turning a drone photo into a planting bed, and
# Adam redrew it in twelve minutes as plain parallel offsets of his terrace
# edge. sketch_read lets him draw intent in seconds, geometry_offset_band turns
# a rule ("150 wall ring, 970 bed, lawn line 1,050 beyond") into solids in one
# call, and model_diff measures his redraw against the agent's.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__PlanGeometry

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_EPS = 1.0e-9

        # Adam's segment budget (11-Nov-2026): edges per arch (half circle) by span in mm.
        # A circle gets twice the arch count for its diameter.
        NA_ARCH_BUDGET_MM = [[10.0, 6], [100.0, 12], [1000.0, 24], [5000.0, 48], [Float::INFINITY, 96]].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Small Vector Helpers (2D unless named)
# -----------------------------------------------------------------------------

        # Floats always: whole-number input must never fall into integer division.
        def self.na_sub(a, b)
            [(a[0] - b[0]).to_f, (a[1] - b[1]).to_f]
        end

        def self.na_add(a, b)
            [(a[0] + b[0]).to_f, (a[1] + b[1]).to_f]
        end

        def self.na_mul(a, s)
            [a[0] * s, a[1] * s]
        end

        def self.na_dot(a, b)
            (a[0] * b[0]) + (a[1] * b[1])
        end

        def self.na_cross(a, b)
            (a[0] * b[1]) - (a[1] * b[0])
        end

        def self.na_dot3(a, b)
            (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
        end

        def self.na_cross3(a, b)
            [(a[1] * b[2]) - (a[2] * b[1]), (a[2] * b[0]) - (a[0] * b[2]), (a[0] * b[1]) - (a[1] * b[0])]
        end

        def self.na_len(a)
            Math.hypot(a[0], a[1])
        end

        def self.na_unit(a)
            length = na_len(a)
            length < NA_EPS ? nil : [a[0] / length, a[1] / length]
        end

        def self.na_left(direction)
            [-direction[1], direction[0]]
        end

        def self.na_dist(a, b)
            Math.hypot(a[0] - b[0], a[1] - b[1])
        end

        def self.na_dist3(a, b)
            Math.sqrt(((a[0] - b[0])**2) + ((a[1] - b[1])**2) + (((a[2] || 0.0) - (b[2] || 0.0))**2))
        end

        # Distance from p to the segment a-b.
        def self.Na__PlanGeometry__PointSegmentDistance(p, a, b)
            ab = na_sub(b, a)
            length_sq = na_dot(ab, ab)
            return na_dist(p, a) if length_sq < NA_EPS

            t = [[na_dot(na_sub(p, a), ab) / length_sq, 0.0].max, 1.0].min
            na_dist(p, na_add(a, na_mul(ab, t)))
        end

        # Distance from p to the infinite line through a and b.
        def self.Na__PlanGeometry__PointLineDistance(p, a, b)
            direction = na_unit(na_sub(b, a))
            return na_dist(p, a) unless direction

            na_cross(direction, na_sub(p, a)).abs
        end

        # Solves the square system matrix * x = vector by Gaussian elimination with
        # partial pivoting. nil when the system is singular.
        def self.Na__PlanGeometry__Solve(matrix, vector)
            n = vector.length
            rows = matrix.each_with_index.map { |row, index| row.map(&:to_f) + [vector[index].to_f] }
            n.times do |column|
                pivot = (column...n).max_by { |row| rows[row][column].abs }
                return nil if rows[pivot][column].abs < 1.0e-14

                rows[column], rows[pivot] = rows[pivot], rows[column]
                (column + 1...n).each do |row|
                    factor = rows[row][column] / rows[column][column]
                    next if factor.zero?

                    (column..n).each { |k| rows[row][k] -= factor * rows[column][k] }
                end
            end
            solution = Array.new(n, 0.0)
            (n - 1).downto(0) do |row|
                total = rows[row][n]
                (row + 1...n).each { |k| total -= rows[row][k] * solution[k] }
                solution[row] = total / rows[row][row]
            end
            solution
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chaining Segments Into Polylines (sketch_read)
# -----------------------------------------------------------------------------

        # FUNCTION | Chain Loose Segments Into Polylines
        # ------------------------------------------------------------
        # segments: [[[x, y, z], [x, y, z]], ...]. Ends closer than snap become one
        # node (their average). A node where three or more segments meet ends the
        # chains there. Returns [{ 'points' => [...], 'closed' => bool,
        # 'segments' => [indices in walk order] }], longest first.
        def self.Na__PlanGeometry__ChainSegments(segments, snap)
            snap = [snap.to_f, NA_EPS].max
            nodes = []
            cells = {}
            node_of = lambda do |point|
                key = point.map { |value| (value / snap).floor }
                found = nil
                [-1, 0, 1].each do |dx|
                    [-1, 0, 1].each do |dy|
                        [-1, 0, 1].each do |dz|
                            Array(cells[[key[0] + dx, key[1] + dy, key[2] + dz]]).each do |index|
                                found = index if found.nil? && na_dist3(nodes[index][:sum].map { |v| v / nodes[index][:count] }, point) <= snap
                            end
                        end
                    end
                end
                unless found
                    found = nodes.length
                    nodes << { sum: [0.0, 0.0, 0.0], count: 0, links: [] }
                    (cells[key] ||= []) << found
                end
                node = nodes[found]
                node[:sum] = [node[:sum][0] + point[0], node[:sum][1] + point[1], node[:sum][2] + point[2]]
                node[:count] += 1
                found
            end

            edges = []
            segments.each_with_index do |(a, b), index|
                a3 = [a[0].to_f, a[1].to_f, (a[2] || 0.0).to_f]
                b3 = [b[0].to_f, b[1].to_f, (b[2] || 0.0).to_f]
                na = node_of.call(a3)
                nb = node_of.call(b3)
                next if na == nb

                edges << [na, nb, index]
                nodes[na][:links] << edges.length - 1
                nodes[nb][:links] << edges.length - 1
            end
            position = ->(index) { nodes[index][:sum].map { |value| value / nodes[index][:count] } }

            used = Array.new(edges.length, false)
            chains = []
            walk = lambda do |start_node, first_edge|
                node_list = [start_node]
                segment_list = []
                node = start_node
                edge_index = first_edge
                loop do
                    used[edge_index] = true
                    a, b, source = edges[edge_index]
                    node = a == node ? b : a
                    node_list << node
                    segment_list << source
                    break if node == start_node || nodes[node][:links].length != 2

                    edge_index = nodes[node][:links].find { |candidate| !used[candidate] }
                    break unless edge_index
                end
                closed = node_list.length > 2 && node_list.first == node_list.last
                node_list.pop if closed
                { 'points' => node_list.map { |index| position.call(index) }, 'closed' => closed, 'segments' => segment_list }
            end

            nodes.each_index do |index|
                next if nodes[index][:links].length == 2

                nodes[index][:links].each do |edge_index|
                    chains << walk.call(index, edge_index) unless used[edge_index]
                end
            end
            edges.each_index do |edge_index|
                chains << walk.call(edges[edge_index][0], edge_index) unless used[edge_index]
            end
            chains.sort_by { |chain| -self.Na__PlanGeometry__PolylineLength(chain['points'], chain['closed']) }
        end
        # ---------------------------------------------------------------

        def self.Na__PlanGeometry__PolylineLength(points, closed = false)
            total = 0.0
            points.each_cons(2) { |a, b| total += na_dist3(a, b) }
            total += na_dist3(points.last, points.first) if closed && points.length > 2
            total
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Fitting Lines and Arcs
# -----------------------------------------------------------------------------

        # FUNCTION | Least-Squares Circle Through 2D Points
        # ------------------------------------------------------------
        # Algebraic (Kasa) fit, refined by Gauss-Newton on the true distances.
        # Returns { center:, radius:, max_dev:, rms: } or nil (collinear points).
        def self.Na__PlanGeometry__FitCircle(points)
            return nil if points.length < 3

            sxx = sxy = syy = sx = sy = sxz = syz = sz = 0.0
            n = points.length.to_f
            points.each do |p|
                x = p[0].to_f
                y = p[1].to_f
                z = (x * x) + (y * y)
                sxx += x * x
                sxy += x * y
                syy += y * y
                sx += x
                sy += y
                sxz += x * z
                syz += y * z
                sz += z
            end
            solution = self.Na__PlanGeometry__Solve([[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]], [-sxz, -syz, -sz])
            return nil unless solution

            cx = -solution[0] / 2.0
            cy = -solution[1] / 2.0
            r_sq = (cx * cx) + (cy * cy) - solution[2]
            return nil if r_sq <= 0.0 || !r_sq.finite?

            r = Math.sqrt(r_sq)
            8.times do
                jtj = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
                jtr = [0.0, 0.0, 0.0]
                points.each do |p|
                    dx = p[0] - cx
                    dy = p[1] - cy
                    d = Math.hypot(dx, dy)
                    next if d < NA_EPS

                    j = [-dx / d, -dy / d, -1.0]
                    residual = d - r
                    3.times do |row|
                        jtr[row] += j[row] * residual
                        3.times { |col| jtj[row][col] += j[row] * j[col] }
                    end
                end
                step = self.Na__PlanGeometry__Solve(jtj, jtr.map { |value| -value })
                break unless step

                cx += step[0]
                cy += step[1]
                r += step[2]
                break if step.map(&:abs).max < 1.0e-10 * [r.abs, 1.0].max
            end
            deviations = points.map { |p| (Math.hypot(p[0] - cx, p[1] - cy) - r).abs }
            { center: [cx, cy], radius: r, max_dev: deviations.max,
              rms: Math.sqrt(deviations.sum { |value| value * value } / deviations.length) }
        end
        # ---------------------------------------------------------------

        # Signed sweep (radians, anticlockwise positive) walking points round center.
        def self.Na__PlanGeometry__Sweep(points, center)
            total = 0.0
            points.each_cons(2) do |a, b|
                va = na_sub(a, center)
                vb = na_sub(b, center)
                total += Math.atan2(na_cross(va, vb), na_dot(va, vb))
            end
            total
        end

        # FUNCTION | Split a Rough Polyline Into Straight and Arc Runs
        # ------------------------------------------------------------
        # points: 2D (z ignored). A run is a line when every point lies within
        # tolerance of its chord, an arc when a circle fits within tolerance (at
        # least min_arc_points points, sweep under 350 degrees). Otherwise the run
        # splits at its farthest point and both halves are tried again. Adjacent
        # runs that are one line or one circle are merged.
        # Returns [{ 'type' => 'line'|'arc', 'from' => i, 'to' => j, 'max_dev' =>,
        #            'center' =>, 'radius' =>, 'sweep' => radians }]
        def self.Na__PlanGeometry__SplitRuns(points, tolerance, min_arc_points = 4)
            runs = []
            fit = lambda do |from, to|
                slice = points[from..to]
                chord_dev = slice.map { |p| self.Na__PlanGeometry__PointLineDistance(p, slice.first, slice.last) }.max || 0.0
                chord_dev = 0.0 if slice.length <= 2
                if slice.length <= 2 || chord_dev <= tolerance
                    runs << { 'type' => 'line', 'from' => from, 'to' => to, 'max_dev' => chord_dev }
                    next
                end
                if slice.length >= min_arc_points && self.na_even_spacing?(slice)
                    circle = self.Na__PlanGeometry__FitCircle(slice)
                    if circle && circle[:max_dev] <= tolerance
                        sweep = self.Na__PlanGeometry__Sweep(slice, circle[:center])
                        if sweep.abs < (350.0 * Math::PI / 180.0)
                            runs << { 'type' => 'arc', 'from' => from, 'to' => to, 'max_dev' => circle[:max_dev],
                                      'center' => circle[:center], 'radius' => circle[:radius], 'sweep' => sweep }
                            next
                        end
                    end
                end
                split = (from + 1...to).max_by { |index| self.Na__PlanGeometry__PointLineDistance(points[index], points[from], points[to]) }
                fit.call(from, split)
                fit.call(split, to)
            end
            fit.call(0, points.length - 1) if points.length >= 2
            self.na_merge_runs(points, runs, tolerance)
        end
        # ---------------------------------------------------------------

        # Neighbouring runs become one when the joint points still fit one line, or one
        # circle when either is an arc (a split can leave an arc's end segment as a
        # line of two points). Repeated until nothing joins.
        def self.na_merge_runs(points, runs, tolerance)
            merged = runs.map(&:dup)
            loop do
                joined = false
                index = 0
                while index < merged.length - 1
                    first = merged[index]
                    second = merged[index + 1]
                    combined = first['to'] == second['from'] ? self.na_joint_fit(points, first, second, tolerance) : nil
                    if combined
                        merged[index, 2] = [combined]
                        joined = true
                    else
                        index += 1
                    end
                end
                break unless joined
            end
            merged
        end

        def self.na_joint_fit(points, first, second, tolerance)
            slice = points[first['from']..second['to']]
            if first['type'] == 'line' && second['type'] == 'line'
                dev = slice.map { |p| self.Na__PlanGeometry__PointLineDistance(p, slice.first, slice.last) }.max
                return { 'type' => 'line', 'from' => first['from'], 'to' => second['to'], 'max_dev' => dev } if dev <= tolerance
            end
            return nil if first['type'] == 'line' && second['type'] == 'line' && slice.length < 5
            return nil unless self.na_even_spacing?(slice)

            circle = self.Na__PlanGeometry__FitCircle(slice)
            return nil unless circle && circle[:max_dev] <= tolerance

            sweep = self.Na__PlanGeometry__Sweep(slice, circle[:center])
            return nil unless sweep.abs < (350.0 * Math::PI / 180.0)

            { 'type' => 'arc', 'from' => first['from'], 'to' => second['to'], 'max_dev' => circle[:max_dev],
              'center' => circle[:center], 'radius' => circle[:radius], 'sweep' => sweep }
        end

        # A drawn arc (a SketchUp curve, or freehand) has roughly even spacing; a run with
        # one segment far longer than the rest is a straight line meeting an arc, so it
        # is never fitted as one arc (live test 12-Nov-2026: an arc's last facet plus the
        # tangent line after it fitted a 17.8 m arc within 15 mm).
        def self.na_even_spacing?(slice)
            lengths = slice.each_cons(2).map { |a, b| na_dist(a, b) }
            return true if lengths.length < 3

            sorted = lengths.sort
            median = sorted[sorted.length / 2]
            median > NA_EPS && lengths.max <= 3.0 * median
        end

        # Edges for an arc of this radius and sweep under Adam's budget (radius in mm).
        def self.Na__PlanGeometry__ArcSegments(radius_mm, sweep_radians)
            span = 2.0 * radius_mm.abs
            per_half = NA_ARCH_BUDGET_MM.find { |limit, _count| span <= limit }[1]
            [(per_half * sweep_radians.abs / Math::PI).ceil, 1].max
        end

        # FUNCTION | A Clean Path From Fitted Runs
        # ------------------------------------------------------------
        # Lines keep their two end points; arcs are resampled on the fitted circle
        # (end points snapped onto it) with Adam's budget. mm_per_unit converts the
        # caller's unit to mm for the budget. Returns 2D points.
        def self.Na__PlanGeometry__CleanPath(points, runs, mm_per_unit)
            out = []
            runs.each do |run|
                a = points[run['from']]
                b = points[run['to']]
                if run['type'] == 'arc'
                    center = run['center']
                    start_angle = Math.atan2(a[1] - center[1], a[0] - center[0])
                    count = self.Na__PlanGeometry__ArcSegments(run['radius'] * mm_per_unit, run['sweep'])
                    (0..count).each do |k|
                        angle = start_angle + (run['sweep'] * k / count)
                        out << [center[0] + (run['radius'] * Math.cos(angle)), center[1] + (run['radius'] * Math.sin(angle))]
                    end
                else
                    out << [a[0], a[1]]
                    out << [b[0], b[1]]
                end
            end
            self.Na__PlanGeometry__Dedupe(out, 0.5 / mm_per_unit, false)
        end

        # Drops points closer than gap to the one before (and a closing copy of the first):
        # a run of rounded points can leave two a hair apart, whose offsets then fold.
        def self.Na__PlanGeometry__Dedupe(points, gap, closed)
            out = []
            points.each { |p| out << p unless out.last && na_dist(out.last, p) < gap }
            out.pop while closed && out.length > 2 && na_dist(out.last, out.first) < gap
            out
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Parallel Offsets, End Caps and Bands (geometry_offset_band)
# -----------------------------------------------------------------------------

        # Arc centres per vertex: a vertex strictly inside an arc run (fitted within
        # tolerance) is offset radially from that run's centre, so offsets of a
        # drawn arc stay true concentric arcs. Other vertices are mitred.
        def self.Na__PlanGeometry__ArcCentres(points, closed, tolerance)
            centres = Array.new(points.length)
            return centres if points.length < 4

            ring = closed ? points + [points.first] : points
            self.Na__PlanGeometry__SplitRuns(ring, tolerance).each do |run|
                next unless run['type'] == 'arc'

                (run['from'] + 1...run['to']).each { |index| centres[index % points.length] = run['center'] }
            end
            centres
        end

        # FUNCTION | Offset a Polyline Sideways
        # ------------------------------------------------------------
        # distance > 0 goes to the LEFT of the walking direction (seen from above).
        # Open ends are perpendicular to the end segments; trim them with
        # Na__PlanGeometry__TrimToCaps. Returns 2D points.
        def self.Na__PlanGeometry__OffsetPolyline(points, distance, closed, centres = nil)
            count = points.length
            seg_count = closed ? count : count - 1
            dirs = (0...seg_count).map { |index| na_unit(na_sub(points[(index + 1) % count], points[index])) }
            raise ArgumentError, 'the path has two points in the same place' if dirs.any?(&:nil?)

            normals = dirs.map { |direction| na_left(direction) }
            (0...count).map do |k|
                p = points[k]
                if !closed && k.zero?
                    next na_add(p, na_mul(normals[0], distance))
                end
                if !closed && k == count - 1
                    next na_add(p, na_mul(normals[-1], distance))
                end

                previous = (k - 1) % seg_count
                following = k % seg_count
                centre = centres && centres[k]
                if centre
                    radial = na_sub(p, centre)
                    radius = na_len(radial)
                    unit = na_unit(radial)
                    if unit
                        sign = na_dot(unit, normals[following]) >= 0 ? 1.0 : -1.0
                        next na_add(centre, na_mul(unit, radius + (sign * distance)))
                    end
                end
                a = na_add(p, na_mul(normals[previous], distance))
                b = na_add(p, na_mul(normals[following], distance))
                denominator = na_cross(dirs[previous], dirs[following])
                if denominator.abs < 1.0e-9
                    a
                else
                    t = na_cross(na_sub(b, a), dirs[following]) / denominator
                    na_add(a, na_mul(dirs[previous], t))
                end
            end
        end
        # ---------------------------------------------------------------

        # A cap is a line { point:, dir: } that ends a band. inset moves it that far
        # into the band, measured square to the cap line.
        def self.Na__PlanGeometry__Cap(point, direction, interior_point, inset = 0.0)
            unit = na_unit(direction)
            raise ArgumentError, 'an end line needs two different points' unless unit

            normal = na_left(unit)
            normal = na_mul(normal, -1.0) if na_dot(normal, na_sub(interior_point, point)) < 0
            { point: na_add(point, na_mul(normal, inset.to_f)), dir: unit, inward: normal }
        end

        # Point halfway along a polyline (by length): which side of a cap is "inside".
        def self.Na__PlanGeometry__MidPoint(points)
            total = 0.0
            points.each_cons(2) { |a, b| total += na_dist(a, b) }
            target = total / 2.0
            run = 0.0
            points.each_cons(2) do |a, b|
                step = na_dist(a, b)
                return na_add(a, na_mul(na_sub(b, a), (target - run) / step)) if step > NA_EPS && run + step >= target

                run += step
            end
            points.last
        end

        # FUNCTION | Trim an Offset Line to Its Two End Caps
        # ------------------------------------------------------------
        # Both ends are extended by extension first, so a cap beyond the offset's
        # own end still meets it. Raises ArgumentError when a cap never crosses.
        def self.Na__PlanGeometry__TrimToCaps(points, start_cap, end_cap, extension)
            first_dir = na_unit(na_sub(points[1], points[0]))
            last_dir = na_unit(na_sub(points[-1], points[-2]))
            extended = [na_sub(points[0], na_mul(first_dir, extension))] + points + [na_add(points[-1], na_mul(last_dir, extension))]
            trimmed = self.na_trim_start(extended, start_cap)
            raise ArgumentError, 'the start line never crosses this offset' unless trimmed

            reversed = self.na_trim_start(trimmed.reverse, end_cap)
            raise ArgumentError, 'the end line never crosses this offset' unless reversed

            result = reversed.reverse
            raise ArgumentError, 'the end lines cross before this offset starts (band too short)' if result.length < 2

            result
        end
        # ---------------------------------------------------------------

        def self.na_trim_start(points, cap)
            side = ->(p) { na_dot(na_sub(p, cap[:point]), cap[:inward]) }
            points.each_cons(2).with_index do |(a, b), index|
                sa = side.call(a)
                sb = side.call(b)
                next unless sa <= 0.0 && sb > 0.0

                t = sa.to_f / (sa - sb)
                crossing = na_add(a, na_mul(na_sub(b, a), t))
                return [crossing] + points[(index + 1)..]
            end
            nil
        end

        # FUNCTION | The Outline of One Band Between Two Offsets
        # ------------------------------------------------------------
        # path: 2D points; from/to: signed offsets (left positive); caps: for an
        # open path [start, end] as { line: [[x,y],[x,y]] } or nil (square to the
        # path end), with insets [start, end]. Returns { outer: [...], inner: nil }
        # for an open path, or { outer:, inner: } rings for a closed one.
        def self.Na__PlanGeometry__BandOutline(path, from, to, closed, centres, caps, insets)
            from, to = [from.to_f, to.to_f].minmax
            raise ArgumentError, 'a band needs from and to to differ' if (to - from).abs < NA_EPS

            near = self.Na__PlanGeometry__OffsetPolyline(path, from, closed, centres)
            far = self.Na__PlanGeometry__OffsetPolyline(path, to, closed, centres)
            if closed
                outer, inner = [near, far].sort_by { |ring| -self.Na__PlanGeometry__Area(ring).abs }
                return { outer: outer, inner: inner }
            end

            middle = self.Na__PlanGeometry__MidPoint(path)
            start_cap = self.na_cap_for(caps[0], path[0], na_left(na_unit(na_sub(path[1], path[0]))), middle, insets[0])
            end_cap = self.na_cap_for(caps[1], path[-1], na_left(na_unit(na_sub(path[-1], path[-2]))), middle, insets[1])
            reach = [from.abs, to.abs].max
            extension = (4.0 * reach) + (2.0 * (insets[0].to_f.abs + insets[1].to_f.abs)) + self.Na__PlanGeometry__PolylineLength(path.map { |p| p + [0.0] })
            near = self.Na__PlanGeometry__TrimToCaps(near, start_cap, end_cap, extension)
            far = self.Na__PlanGeometry__TrimToCaps(far, start_cap, end_cap, extension)
            { outer: near + far.reverse, inner: nil, lines: { near: near, far: far } }
        end
        # ---------------------------------------------------------------

        def self.na_cap_for(cap, end_point, square_direction, interior, inset)
            if cap.is_a?(Hash) && cap[:line]
                a, b = cap[:line]
                self.Na__PlanGeometry__Cap(a, na_sub(b, a), interior, inset.to_f)
            else
                self.Na__PlanGeometry__Cap(end_point, square_direction, interior, inset.to_f)
            end
        end

        # One offset line trimmed to the caps (a line_only band, e.g. a lawn edge).
        def self.Na__PlanGeometry__OffsetLine(path, distance, closed, centres, caps, insets)
            line = self.Na__PlanGeometry__OffsetPolyline(path, distance.to_f, closed, centres)
            return line if closed

            middle = self.Na__PlanGeometry__MidPoint(path)
            start_cap = self.na_cap_for(caps[0], path[0], na_left(na_unit(na_sub(path[1], path[0]))), middle, insets[0])
            end_cap = self.na_cap_for(caps[1], path[-1], na_left(na_unit(na_sub(path[-1], path[-2]))), middle, insets[1])
            extension = (4.0 * distance.to_f.abs) + (2.0 * (insets[0].to_f.abs + insets[1].to_f.abs)) + self.Na__PlanGeometry__PolylineLength(path.map { |p| p + [0.0] })
            self.Na__PlanGeometry__TrimToCaps(line, start_cap, end_cap, extension)
        end

        # True when two non-adjacent edges of the closed polygon cross.
        def self.Na__PlanGeometry__SelfIntersects(polygon)
            n = polygon.length
            return false if n < 4

            n.times do |i|
                a = polygon[i]
                b = polygon[(i + 1) % n]
                (i + 2...n).each do |j|
                    next if i.zero? && j == n - 1

                    c = polygon[j]
                    d = polygon[(j + 1) % n]
                    return true if self.na_segments_cross?(a, b, c, d)
                end
            end
            false
        end

        def self.na_segments_cross?(a, b, c, d)
            d1 = na_cross(na_sub(b, a), na_sub(c, a))
            d2 = na_cross(na_sub(b, a), na_sub(d, a))
            d3 = na_cross(na_sub(d, c), na_sub(a, c))
            d4 = na_cross(na_sub(d, c), na_sub(b, c))
            ((d1 > 1.0e-9 && d2 < -1.0e-9) || (d1 < -1.0e-9 && d2 > 1.0e-9)) &&
                ((d3 > 1.0e-9 && d4 < -1.0e-9) || (d3 < -1.0e-9 && d4 > 1.0e-9))
        end

        # Signed area (anticlockwise positive).
        def self.Na__PlanGeometry__Area(polygon)
            total = 0.0
            polygon.each_with_index do |p, index|
                q = polygon[(index + 1) % polygon.length]
                total += (p[0] * q[1]) - (q[0] * p[1])
            end
            total / 2.0
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plane-to-Photo Homography (image_rectify)
# -----------------------------------------------------------------------------

        # FUNCTION | Fit a Homography From Plane Points to Photo Pixels
        # ------------------------------------------------------------
        # src: [[x, y], ...] on the plane; dst: [[u, v], ...] pixels. Four or more
        # pairs, normalised (Hartley), least squares with h33 = 1. Returns
        # { matrix: 3x3, rms_px:, max_px:, residuals_px: [...] } or nil.
        def self.Na__PlanGeometry__FitHomography(src, dst)
            return nil if src.length < 4 || src.length != dst.length

            ts = self.na_normaliser(src)
            td = self.na_normaliser(dst)
            ns = src.map { |p| self.Na__PlanGeometry__ApplyHomography(ts, p) }
            nd = dst.map { |p| self.Na__PlanGeometry__ApplyHomography(td, p) }
            ata = Array.new(8) { Array.new(8, 0.0) }
            atb = Array.new(8, 0.0)
            ns.each_with_index do |(x, y), index|
                u, v = nd[index]
                [[[x, y, 1.0, 0.0, 0.0, 0.0, -u * x, -u * y], u], [[0.0, 0.0, 0.0, x, y, 1.0, -v * x, -v * y], v]].each do |row, rhs|
                    8.times do |i|
                        atb[i] += row[i] * rhs
                        8.times { |j| ata[i][j] += row[i] * row[j] }
                    end
                end
            end
            h = self.Na__PlanGeometry__Solve(ata, atb)
            return nil unless h

            hn = [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1.0]]
            inverse_td = self.Na__PlanGeometry__Invert3(td)
            return nil unless inverse_td

            matrix = self.na_mat_mul(self.na_mat_mul(inverse_td, hn), ts)
            scale = matrix[2][2].abs > NA_EPS ? matrix[2][2] : 1.0
            matrix = matrix.map { |row| row.map { |value| value / scale } }
            residuals = src.each_with_index.map do |p, index|
                q = self.Na__PlanGeometry__ApplyHomography(matrix, p)
                q ? na_dist(q, dst[index]) : Float::INFINITY
            end
            { matrix: matrix, residuals_px: residuals, max_px: residuals.max,
              rms_px: Math.sqrt(residuals.sum { |value| value * value } / residuals.length) }
        end
        # ---------------------------------------------------------------

        # The homogeneous divisor: its sign says which side of the horizon a point is.
        def self.Na__PlanGeometry__HomographyW(matrix, point)
            (matrix[2][0] * point[0]) + (matrix[2][1] * point[1]) + matrix[2][2]
        end

        def self.Na__PlanGeometry__ApplyHomography(matrix, point)
            w = self.Na__PlanGeometry__HomographyW(matrix, point)
            return nil if w.abs < 1.0e-15

            [((matrix[0][0] * point[0]) + (matrix[0][1] * point[1]) + matrix[0][2]) / w,
             ((matrix[1][0] * point[0]) + (matrix[1][1] * point[1]) + matrix[1][2]) / w]
        end

        def self.Na__PlanGeometry__Invert3(m)
            a, b, c = m[0]
            d, e, f = m[1]
            g, h, i = m[2]
            det = (a * ((e * i) - (f * h))) - (b * ((d * i) - (f * g))) + (c * ((d * h) - (e * g)))
            return nil if det.abs < 1.0e-18

            [[((e * i) - (f * h)) / det, ((c * h) - (b * i)) / det, ((b * f) - (c * e)) / det],
             [((f * g) - (d * i)) / det, ((a * i) - (c * g)) / det, ((c * d) - (a * f)) / det],
             [((d * h) - (e * g)) / det, ((b * g) - (a * h)) / det, ((a * e) - (b * d)) / det]]
        end

        def self.na_mat_mul(a, b)
            (0..2).map { |r| (0..2).map { |c| (0..2).sum { |k| a[r][k] * b[k][c] } } }
        end

        def self.na_normaliser(points)
            cx = points.sum { |p| p[0].to_f } / points.length
            cy = points.sum { |p| p[1].to_f } / points.length
            mean = points.sum { |p| Math.hypot(p[0] - cx, p[1] - cy) } / points.length
            s = mean > NA_EPS ? Math.sqrt(2.0) / mean : 1.0
            [[s, 0.0, -s * cx], [0.0, s, -s * cy], [0.0, 0.0, 1.0]]
        end

        # FUNCTION | Clip a Polygon by a Half-Plane (Sutherland-Hodgman, one edge)
        # ------------------------------------------------------------
        # keeps the points where inside.call(p) >= 0; inside must be linear in p.
        def self.Na__PlanGeometry__ClipHalfPlane(polygon, &inside)
            return [] if polygon.empty?

            out = []
            polygon.each_with_index do |current, index|
                previous = polygon[index - 1]
                sc = inside.call(current)
                sp = inside.call(previous)
                if sc >= 0.0
                    out << self.na_lerp_at_zero(previous, current, sp, sc) if sp < 0.0
                    out << current
                elsif sp >= 0.0
                    out << self.na_lerp_at_zero(previous, current, sp, sc)
                end
            end
            out
        end

        def self.na_lerp_at_zero(a, b, sa, sb)
            t = sa.to_f / (sa - sb)
            na_add(a, na_mul(na_sub(b, a), t))
        end

        # Clip a polygon to an axis-aligned rectangle [xmin, ymin, xmax, ymax].
        def self.Na__PlanGeometry__ClipRectangle(polygon, rect)
            xmin, ymin, xmax, ymax = rect
            out = self.Na__PlanGeometry__ClipHalfPlane(polygon) { |p| p[0] - xmin }
            out = self.Na__PlanGeometry__ClipHalfPlane(out) { |p| xmax - p[0] }
            out = self.Na__PlanGeometry__ClipHalfPlane(out) { |p| p[1] - ymin }
            self.Na__PlanGeometry__ClipHalfPlane(out) { |p| ymax - p[1] }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Photo Flattening (image_flatten, 1.0.33)
# -----------------------------------------------------------------------------

        # FUNCTION | Proportions of a Rectangle Seen in a Photo (Zhang and He, 2007)
        # ------------------------------------------------------------
        # corners: the rectangle's four corners in the photo, [u, v] pixels from its
        # top left, in the order origin, along x, far corner, along y. centre: the
        # principal point (the middle of an uncropped photo); square pixels assumed.
        # The corners' perspective fixes the focal length, and the focal length the
        # true proportions. Returns { aspect: side along x / side along y,
        # focal_px: } (focal_px nil when the view is too square-on to fix it; the
        # sides' own ratio is right there), or nil for corners that make no rectangle.
        def self.Na__PlanGeometry__RectangleAspect(corners, centre)
            return nil unless corners.length == 4

            m1, m2, m4, m3 = corners.map { |u, v| [u.to_f - centre[0], v.to_f - centre[1], 1.0] }
            c14 = self.na_cross3(m1, m4)
            d2 = self.na_dot3(self.na_cross3(m2, m4), m3)
            d3 = self.na_dot3(self.na_cross3(m3, m4), m2)
            return nil if d2.abs < NA_EPS || d3.abs < NA_EPS

            k2 = self.na_dot3(c14, m3) / d2
            k3 = self.na_dot3(c14, m2) / d3
            n2 = [(k2 * m2[0]) - m1[0], (k2 * m2[1]) - m1[1], (k2 * m2[2]) - m1[2]]
            n3 = [(k3 * m3[0]) - m1[0], (k3 * m3[1]) - m1[1], (k3 * m3[2]) - m1[2]]
            flat2 = (n2[0] * n2[0]) + (n2[1] * n2[1])
            flat3 = (n3[0] * n3[0]) + (n3[1] * n3[1])
            return nil if flat2 < NA_EPS || flat3 < NA_EPS

            depth = n2[2] * n3[2]
            focal_sq = depth.abs > NA_EPS ? -((n2[0] * n3[0]) + (n2[1] * n3[1])) / depth : -1.0
            if focal_sq.positive? && focal_sq.finite?
                aspect_sq = ((flat2 / focal_sq) + (n2[2] * n2[2])) / ((flat3 / focal_sq) + (n3[2] * n3[2]))
                return { aspect: Math.sqrt(aspect_sq), focal_px: Math.sqrt(focal_sq) }
            end

            { aspect: Math.sqrt(flat2 / flat3), focal_px: nil }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve a Rectangle's Unknown Height From Known Points
        # ------------------------------------------------------------
        # corners as above; width: the known side along x; points: [[[x, y], [u, v]],
        # ...] positions measured from the origin corner along x and y (so they do not
        # depend on the height) with their pixels, at least one. Each trial height
        # gives a least-squares homography over corners and points; the height whose
        # fit is tightest wins (a log scan from low to high, then golden section).
        # Returns { height:, fit: } or nil.
        def self.Na__PlanGeometry__SolveRectangleHeight(corners, width, points, low, high)
            return nil if points.empty? || low <= 0.0 || high <= low

            known = points.map { |pair| pair[0].map(&:to_f) }
            dst = corners.map { |p| p.map(&:to_f) } + points.map { |pair| pair[1].map(&:to_f) }
            fit_at = ->(height) { self.Na__PlanGeometry__FitHomography([[0.0, 0.0], [width, 0.0], [width, height], [0.0, height]] + known, dst) }
            cost = lambda do |height|
                fit = fit_at.call(height)
                fit ? fit[:rms_px] : Float::INFINITY
            end

            steps = 160
            samples = (0..steps).map { |index| low * ((high / low)**(index.to_f / steps)) }
            costs = samples.map { |height| cost.call(height) }
            best = (0..steps).min_by { |index| costs[index] }
            return nil unless costs[best].finite?

            a = samples[[best - 1, 0].max]
            b = samples[[best + 1, steps].min]
            golden = (Math.sqrt(5.0) - 1.0) / 2.0
            c = b - (golden * (b - a))
            d = a + (golden * (b - a))
            fc = cost.call(c)
            fd = cost.call(d)
            100.times do
                break if (b - a) < width * 1.0e-7

                if fc < fd
                    b = d
                    d = c
                    fd = fc
                    c = b - (golden * (b - a))
                    fc = cost.call(c)
                else
                    a = c
                    c = d
                    fc = fd
                    d = a + (golden * (b - a))
                    fd = cost.call(d)
                end
            end
            height = (a + b) / 2.0
            fit = fit_at.call(height)
            fit ? { height: height, fit: fit } : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A JPEG's EXIF Orientation
        # ------------------------------------------------------------
        # bytes: the start of the file (the EXIF block sits before the image data).
        # Returns 1 to 8, or 1 when there is none. Sketchup::ImageRep loads the raw
        # pixels and ignores it (SketchUp 2027, 12-Nov-2026: a portrait phone photo
        # loads as 4000 x 3000), while every viewer shows the photo turned upright.
        def self.Na__PlanGeometry__JpegOrientation(bytes)
            return 1 unless bytes && bytes.bytesize > 4 && bytes.getbyte(0) == 0xFF && bytes.getbyte(1) == 0xD8

            offset = 2
            while offset + 4 <= bytes.bytesize
                return 1 unless bytes.getbyte(offset) == 0xFF

                marker = bytes.getbyte(offset + 1)
                length = (bytes.getbyte(offset + 2) << 8) | bytes.getbyte(offset + 3)
                return 1 if marker == 0xDA || length < 2

                if marker == 0xE1 && bytes.byteslice(offset + 4, 6) == "Exif\0\0".b
                    return self.na_tiff_orientation(bytes.byteslice(offset + 10, length - 8).to_s)
                end

                offset += 2 + length
            end
            1
        end

        def self.na_tiff_orientation(tiff)
            return 1 if tiff.bytesize < 8

            little = tiff.byteslice(0, 2) == 'II'
            u16 = ->(at) { tiff.byteslice(at, 2).to_s.unpack1(little ? 'v' : 'n') }
            u32 = ->(at) { tiff.byteslice(at, 4).to_s.unpack1(little ? 'V' : 'N') }
            ifd = u32.call(4)
            count = ifd && u16.call(ifd)
            return 1 unless count

            count.times do |index|
                entry = ifd + 2 + (index * 12)
                next unless u16.call(entry) == 0x0112

                value = u16.call(entry + 8)
                return value && (1..8).cover?(value) ? value : 1
            end
            1
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Pixel as Viewers Show the Photo -> SketchUp's Raw Pixel
        # ------------------------------------------------------------
        # orientation: EXIF 1 to 8; raw_w, raw_h: the size ImageRep loads. Viewers
        # turn the raw image by the orientation; this undoes that for one position
        # (pixels from the top left, edges on whole numbers).
        def self.Na__PlanGeometry__UprightToRaw(pixel, orientation, raw_w, raw_h)
            u, v = pixel
            case orientation
            when 2 then [raw_w - u, v]
            when 3 then [raw_w - u, raw_h - v]
            when 4 then [u, raw_h - v]
            when 5 then [v, u]
            when 6 then [v, raw_h - u]
            when 7 then [raw_w - v, raw_h - u]
            when 8 then [raw_w - v, u]
            else [u, v]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Warp a Photo's Pixels Through a Homography
        # ------------------------------------------------------------
        # src: the photo's bytes as Sketchup::ImageRep#data gives them (top row first;
        # BGR(A) on Windows, RGB(A) on macOS: the order is kept), with its width,
        # height, bytes per pixel (3 or 4) and row stride in bytes. matrix maps an
        # output position (pixels from the output's top left, pixel edges on whole
        # numbers) to a photo position (the same convention). Returns the output's
        # 32-bit bytes in the same channel order, top row first: bilinear inside the
        # photo, alpha 0 outside it and beyond the horizon. Pure Ruby, about 1.4 s a
        # megapixel inside SketchUp 2027 (12-Nov-2026).
        def self.Na__PlanGeometry__WarpPixels(src, sw, sh, bpp, stride, matrix, dw, dh)
            sign = self.Na__PlanGeometry__HomographyW(matrix, [dw / 2.0, dh / 2.0]).negative? ? -1.0 : 1.0
            m = matrix.map { |row| row.map { |value| value * sign } }
            out = ("\0" * (dw * dh * 4)).b
            alpha = bpp >= 4
            max_u = sw - 1.0
            max_v = sh - 1.0
            index = 0
            dh.times do |row|
                y = row + 0.5
                a = (m[0][0] * 0.5) + (m[0][1] * y) + m[0][2]
                b = (m[1][0] * 0.5) + (m[1][1] * y) + m[1][2]
                c = (m[2][0] * 0.5) + (m[2][1] * y) + m[2][2]
                dw.times do
                    if c > 1.0e-12
                        u = (a / c) - 0.5
                        v = (b / c) - 0.5
                        if u > -0.5 && v > -0.5 && u < sw - 0.5 && v < sh - 0.5
                            u = 0.0 if u.negative?
                            v = 0.0 if v.negative?
                            u = max_u if u > max_u
                            v = max_v if v > max_v
                            x0 = u.to_i
                            y0 = v.to_i
                            fx = u - x0
                            fy = v - y0
                            x1 = x0 < sw - 1 ? x0 + 1 : x0
                            y1 = y0 < sh - 1 ? y0 + 1 : y0
                            p00 = (y0 * stride) + (x0 * bpp)
                            p10 = (y0 * stride) + (x1 * bpp)
                            p01 = (y1 * stride) + (x0 * bpp)
                            p11 = (y1 * stride) + (x1 * bpp)
                            w00 = (1.0 - fx) * (1.0 - fy)
                            w10 = fx * (1.0 - fy)
                            w01 = (1.0 - fx) * fy
                            w11 = fx * fy
                            out.setbyte(index, ((src.getbyte(p00) * w00) + (src.getbyte(p10) * w10) + (src.getbyte(p01) * w01) + (src.getbyte(p11) * w11) + 0.5).to_i)
                            out.setbyte(index + 1, ((src.getbyte(p00 + 1) * w00) + (src.getbyte(p10 + 1) * w10) + (src.getbyte(p01 + 1) * w01) + (src.getbyte(p11 + 1) * w11) + 0.5).to_i)
                            out.setbyte(index + 2, ((src.getbyte(p00 + 2) * w00) + (src.getbyte(p10 + 2) * w10) + (src.getbyte(p01 + 2) * w01) + (src.getbyte(p11 + 2) * w11) + 0.5).to_i)
                            out.setbyte(index + 3, alpha ? ((src.getbyte(p00 + 3) * w00) + (src.getbyte(p10 + 3) * w10) + (src.getbyte(p01 + 3) * w01) + (src.getbyte(p11 + 3) * w11) + 0.5).to_i : 255)
                        end
                    end
                    a += m[0][0]
                    b += m[1][0]
                    c += m[2][0]
                    index += 4
                end
            end
            out
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Footprint Comparison (model_diff)
# -----------------------------------------------------------------------------

        # FUNCTION | Area, Overlap and Union of Two Plan Footprints
        # ------------------------------------------------------------
        # Each footprint is a list of loops (outer loops and holes alike); a point
        # is inside when an odd number of loops surround it, so faces with holes
        # and touching faces both read right. Scanline: rows across the joint
        # bounding box, exact interval lengths along each row.
        # Returns { area_a:, area_b:, overlap:, union:, iou: }.
        def self.Na__PlanGeometry__CompareFootprints(loops_a, loops_b, rows = 800)
            all = loops_a + loops_b
            return { area_a: 0.0, area_b: 0.0, overlap: 0.0, union: 0.0, iou: 0.0 } if all.empty?

            ys = all.flatten(1).map { |p| p[1] }
            ymin = ys.min.to_f
            ymax = ys.max.to_f
            height = ymax - ymin
            return { area_a: 0.0, area_b: 0.0, overlap: 0.0, union: 0.0, iou: 0.0 } if height < NA_EPS

            step = height / rows
            totals = { a: 0.0, b: 0.0, overlap: 0.0, union: 0.0 }
            rows.times do |row|
                y = ymin + ((row + 0.5) * step)
                ia = self.na_row_intervals(loops_a, y)
                ib = self.na_row_intervals(loops_b, y)
                la = ia.sum { |x0, x1| x1 - x0 }
                lb = ib.sum { |x0, x1| x1 - x0 }
                both = self.na_interval_overlap(ia, ib)
                totals[:a] += la * step
                totals[:b] += lb * step
                totals[:overlap] += both * step
                totals[:union] += (la + lb - both) * step
            end
            { area_a: totals[:a], area_b: totals[:b], overlap: totals[:overlap], union: totals[:union],
              iou: totals[:union] > NA_EPS ? totals[:overlap] / totals[:union] : 0.0 }
        end
        # ---------------------------------------------------------------

        def self.na_row_intervals(loops, y)
            xs = []
            loops.each do |loop_points|
                loop_points.each_with_index do |p, index|
                    q = loop_points[(index + 1) % loop_points.length]
                    next if (p[1] > y) == (q[1] > y)

                    xs << p[0] + ((y - p[1]) * (q[0] - p[0]) / (q[1] - p[1]))
                end
            end
            xs.sort.each_slice(2).select { |pair| pair.length == 2 }
        end

        def self.na_interval_overlap(a, b)
            total = 0.0
            i = 0
            j = 0
            while i < a.length && j < b.length
                low = [a[i][0], b[j][0]].max
                high = [a[i][1], b[j][1]].min
                total += high - low if high > low
                a[i][1] < b[j][1] ? i += 1 : j += 1
            end
            total
        end

        # FUNCTION | How Far Apart Two Sets of Outlines Are
        # ------------------------------------------------------------
        # Samples every loop of each set every step and measures to the other set's
        # edges. Returns { a_to_b_max:, b_to_a_max:, hausdorff:, a_to_b_median:,
        # b_to_a_median:, worst_a: [x, y] } (worst_a: the point of A farthest from B).
        def self.Na__PlanGeometry__OutlineDistance(loops_a, loops_b, step)
            seg_a = self.na_loop_segments(loops_a)
            seg_b = self.na_loop_segments(loops_b)
            return nil if seg_a.empty? || seg_b.empty?

            da = self.na_sample_distances(seg_a, seg_b, step)
            db = self.na_sample_distances(seg_b, seg_a, step)
            worst = da.max_by { |pair| pair[1] }
            {
                a_to_b_max: da.map(&:last).max, b_to_a_max: db.map(&:last).max,
                hausdorff: [da.map(&:last).max, db.map(&:last).max].max,
                a_to_b_median: self.na_median(da.map(&:last)), b_to_a_median: self.na_median(db.map(&:last)),
                worst_a: worst ? worst[0] : nil
            }
        end
        # ---------------------------------------------------------------

        def self.na_loop_segments(loops)
            loops.flat_map { |loop_points| loop_points.each_with_index.map { |p, index| [p, loop_points[(index + 1) % loop_points.length]] } }
        end

        def self.na_sample_distances(from_segments, to_segments, step)
            samples = []
            from_segments.each do |a, b|
                length = na_dist(a, b)
                count = [(length / step).ceil, 1].max
                count.times do |k|
                    p = na_add(a, na_mul(na_sub(b, a), k.to_f / count))
                    distance = to_segments.map { |c, d| self.Na__PlanGeometry__PointSegmentDistance(p, c, d) }.min
                    samples << [p, distance]
                end
            end
            samples
        end

        def self.na_median(values)
            return nil if values.empty?

            sorted = values.sort
            middle = sorted.length / 2
            sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
        end

# endregion -------------------------------------------------------------------

    end # module Na__PlanGeometry
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
