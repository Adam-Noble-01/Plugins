# =============================================================================
# NA POINT CLOUD VIEWER - MCP OPERATIONS - SHAPE FITTING
# =============================================================================
#
# FILE       : Na__PointCloudViewer__McpOperations__Fit__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__McpFit
# CREATED    : 09-Nov-2026 (v0.14.2)
# PURPOSE    : Fits a plane, a line, a circle, a cylinder along a model axis
#              or a box turned about a model axis to points ([[x, y, z], ...],
#              model inches) for the Na SketchUp MCP's point_cloud_fit. Pure
#              Ruby, no SketchUp API: the seam reads an even sample of a box
#              with napc_box_points and calls these, and the unit suite calls
#              them directly.
#
# METHOD:
# - RANSAC on a subsample of NA_RANSAC_POINTS finds the dominant shape, so a
#   box may also hold other surfaces (a floor under a wall, the next tread).
# - Least squares on every inlier of the whole sample then refines it, taking
#   the inliers again each round until they stop changing (0.14.5; up to
#   NA_REFINE_ROUNDS), so where the random search started does not matter.
#   Residuals are measured on those inliers: rms, and the 95th percentile of
#   their size.
# - The random number generator is seeded: the same points give the same
#   answer.
# - A box (a post, a newel) is the smallest rectangle, turned about the axis,
#   holding the points once `trim` percent is taken off each side, so stray
#   points do not widen it. Its residuals (0.14.5) are each point's distance
#   from the rectangle's sides, seen along the axis.
# - Extents (0.14.5) are the 1st to 99th percentiles widened by the share they
#   trim (1/98 of their span each way): exact for evenly scanned ends, and a
#   stray point still does not stretch them.
# - Directions (0.14.5): a line runs uphill (start low, end high) and a plane's
#   normal points up, except within NA_LEVEL_SINE of level (a line) or plumb (a
#   plane), where the larger horizontal part is positive. azimuth_deg is then
#   the way a line rises, and the way a plane falls or a wall faces.
#
# Every length in and out is in model inches; angles out are degrees.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__McpFit

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_SEED           = 20_261_109
        NA_RANSAC_POINTS  = 2_000
        NA_RANSAC_ROUNDS  = 300
        NA_REFINE_ROUNDS  = 20   # 0.14.5: until the inliers stop changing, so the answer does not hang on the search's start (was 4)
        NA_MIN_RADIUS_SHARE = 0.1  # a circle smaller than this share of tolerance is noise (0.14.5: was 2 x tolerance)
        NA_LEVEL_SINE     = 0.02   # within about 1.1 degrees of level (a line) or of plumb (a plane)
        NA_ORIENTATIONS   = %w[any horizontal vertical].freeze
        NA_AXES           = { 'x' => 0, 'y' => 1, 'z' => 2 }.freeze
        # The two in-plane axes for each model axis, right-handed: u x v = axis.
        NA_PLANE_AXES     = { 0 => [1, 2], 1 => [2, 0], 2 => [0, 1] }.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Plane
    # -------------------------------------------------------------------------

        # orientation: any, horizontal (normal along z: a floor, a tread) or
        # vertical (normal level: a wall, a riser, a post face).
        def self.Na__Fit__Plane(points, tolerance, orientation = 'any')
            raise ArgumentError, 'A plane needs at least 3 points.' if points.length < 3
            rng = Random.new(NA_SEED)
            sample = self.na_subsample(points, rng)
            best = nil
            NA_RANSAC_ROUNDS.times do
                trial = self.na_plane_from(sample.sample(3, random: rng), orientation)
                next unless trial
                normal, offset = trial
                count = sample.count { |point| (self.na_dot(normal, point) - offset).abs <= tolerance }
                best = [count, normal, offset] if best.nil? || count > best[0]
            end
            raise ArgumentError, 'No plane could be formed: the points are all in a line.' unless best
            normal = best[1]
            offset = best[2]
            inliers = []
            previous = nil
            NA_REFINE_ROUNDS.times do
                inliers = points.select { |point| (self.na_dot(normal, point) - offset).abs <= tolerance }
                break if inliers.length < 3 || inliers == previous
                previous = inliers
                normal = self.na_plane_normal(inliers, orientation)
                offset = self.na_dot(normal, self.na_mean(inliers))
            end
            raise ArgumentError, 'Fewer than 3 points lie on the plane.' if inliers.length < 3
            normal = self.na_sign_up(normal)
            centre = self.na_mean(inliers)
            offset = self.na_dot(normal, centre)
            residuals = inliers.map { |point| self.na_dot(normal, point) - offset }
            along = self.na_unit(self.na_cross([0.0, 0.0, 1.0], normal)) || [1.0, 0.0, 0.0]
            across = self.na_cross(normal, along)
            along_values = inliers.map { |point| self.na_dot(along, point) }
            across_values = inliers.map { |point| self.na_dot(across, point) }
            {
                'normal'      => normal,
                'point'       => centre,
                'offset'      => offset,
                'slope_deg'   => Math.acos([normal[2].abs, 1.0].min) * 180.0 / Math::PI,
                'azimuth_deg' => Math.atan2(normal[1], normal[0]) * 180.0 / Math::PI,
                'in_plane'    => { 'along' => along, 'across' => across,
                                   'along_range' => self.na_range(along_values), 'across_range' => self.na_range(across_values) },
                'inliers'     => inliers.length
            }.merge(self.na_residuals(residuals))
        end

        def self.na_plane_from(three, orientation)
            a, b, c = three
            case orientation
            when 'horizontal'
                [[0.0, 0.0, 1.0], a[2]]
            when 'vertical'
                normal = self.na_unit([-(b[1] - a[1]), b[0] - a[0], 0.0])
                normal ? [normal, self.na_dot(normal, a)] : nil
            else
                normal = self.na_unit(self.na_cross(self.na_sub(b, a), self.na_sub(c, a)))
                normal ? [normal, self.na_dot(normal, a)] : nil
            end
        end

        # The least-squares normal of the points, held to the orientation.
        def self.na_plane_normal(points, orientation)
            return [0.0, 0.0, 1.0] if orientation == 'horizontal'
            centre = self.na_mean(points)
            matrix = self.na_covariance(points, centre)
            if orientation == 'vertical'
                plan = [[matrix[0][0], matrix[0][1], 0.0], [matrix[1][0], matrix[1][1], 0.0], [0.0, 0.0, 0.0]]
                _values, vectors = self.na_eigen(plan)
                direction = vectors[2]                                   # the largest spread in plan
                return self.na_unit([-direction[1], direction[0], 0.0]) || [1.0, 0.0, 0.0]
            end
            _values, vectors = self.na_eigen(matrix)
            self.na_unit(vectors[0]) || [0.0, 0.0, 1.0]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Line
    # -------------------------------------------------------------------------

        def self.Na__Fit__Line(points, tolerance)
            raise ArgumentError, 'A line needs at least 2 points.' if points.length < 2
            rng = Random.new(NA_SEED)
            sample = self.na_subsample(points, rng)
            best = nil
            NA_RANSAC_ROUNDS.times do
                a, b = sample.sample(2, random: rng)
                direction = self.na_unit(self.na_sub(b, a))
                next unless direction
                count = sample.count { |point| self.na_line_distance(point, a, direction) <= tolerance }
                best = [count, a, direction] if best.nil? || count > best[0]
            end
            raise ArgumentError, 'No line could be formed: the points are all in one place.' unless best
            origin = best[1]
            direction = best[2]
            inliers = []
            previous = nil
            NA_REFINE_ROUNDS.times do
                inliers = points.select { |point| self.na_line_distance(point, origin, direction) <= tolerance }
                break if inliers.length < 2 || inliers == previous
                previous = inliers
                origin = self.na_mean(inliers)
                _values, vectors = self.na_eigen(self.na_covariance(inliers, origin))
                direction = self.na_unit(vectors[2]) || direction
            end
            raise ArgumentError, 'Fewer than 2 points lie on the line.' if inliers.length < 2
            direction = self.na_sign_up(direction)
            centre = self.na_mean(inliers)
            positions = inliers.map { |point| self.na_dot(direction, self.na_sub(point, centre)) }
            low, high = self.na_range(positions)
            residuals = inliers.map { |point| self.na_line_distance(point, centre, direction) }
            {
                'point'       => centre,
                'direction'   => direction,
                'start'       => self.na_add(centre, self.na_scale(direction, low)),
                'end'         => self.na_add(centre, self.na_scale(direction, high)),
                'length'      => high - low,
                'slope_deg'   => Math.asin([direction[2].abs, 1.0].min) * 180.0 / Math::PI,
                'azimuth_deg' => Math.atan2(direction[1], direction[0]) * 180.0 / Math::PI,
                'inliers'     => inliers.length
            }.merge(self.na_residuals(residuals))
        end

        def self.na_line_distance(point, origin, direction)
            offset = self.na_sub(point, origin)
            along = self.na_dot(offset, direction)
            Math.sqrt([self.na_dot(offset, offset) - along * along, 0.0].max)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Circle and Cylinder (round a model axis)
    # -------------------------------------------------------------------------

        # The circle the points make seen along `axis` (x, y or z): a bullnose
        # step or a round newel in plan, a pipe in section. max_radius stops a
        # flat wall in the box passing for a huge circle, in the search and in
        # the refinement (an arc that runs into a straight riser at a tangent
        # otherwise drifts to a big, flat circle). The cylinder adds the
        # inliers' extent along the axis.
        def self.Na__Fit__Circle(points, tolerance, axis, max_radius, cylinder = false)
            index = NA_AXES.fetch(axis.to_s) { raise ArgumentError, "axis must be x, y or z, not #{axis.inspect}." }
            u, v = NA_PLANE_AXES[index]
            raise ArgumentError, 'A circle needs at least 3 points.' if points.length < 3
            flat = points.map { |point| [point[u], point[v]] }
            rng = Random.new(NA_SEED)
            sample = self.na_subsample(flat, rng)
            best = nil
            NA_RANSAC_ROUNDS.times do
                circle = self.na_circle_through(*sample.sample(3, random: rng))
                next unless circle && circle[2] > NA_MIN_RADIUS_SHARE * tolerance && circle[2] <= max_radius
                count = sample.count { |q| (Math.hypot(q[0] - circle[0], q[1] - circle[1]) - circle[2]).abs <= tolerance }
                best = [count, circle] if best.nil? || count > best[0]
            end
            raise ArgumentError, 'No circle under max_radius could be formed from the points.' unless best
            circle, chosen = self.na_circle_settle(flat, best[1], tolerance, max_radius)
            raise ArgumentError, 'Fewer than 3 points lie on the circle.' if chosen.length < 3
            cx, cy, radius = circle
            residuals = chosen.map { |i| Math.hypot(flat[i][0] - cx, flat[i][1] - cy) - radius }
            # A second start (0.14.5): the least-squares circle through every point,
            # settled the same way. A curve that is not one arc (a bullnose easing into
            # its riser) settles on different circles from different starts.
            other = nil
            start = self.na_circle_algebraic(flat)
            if start && start[2] <= max_radius && start[2] > NA_MIN_RADIUS_SHARE * tolerance
                settled, kept = self.na_circle_settle(flat, start, tolerance, max_radius)
                rms = Math.sqrt(residuals.sum { |r| r * r } / residuals.length)
                if kept.length >= 3 && (settled[2] - radius).abs > [2.0 * rms, 0.02 * radius].max
                    other = settled
                end
            end
            heights = chosen.map { |i| points[i][index] }
            low, high = self.na_range(heights)
            centre = [0.0, 0.0, 0.0]
            centre[u] = cx
            centre[v] = cy
            centre[index] = cylinder ? (low + high) / 2.0 : self.na_percentile(heights.sort, 0.5)
            angles = chosen.map { |i| Math.atan2(flat[i][1] - cy, flat[i][0] - cx) * 180.0 / Math::PI }
            result = {
                'centre'   => centre,
                'axis'     => axis.to_s,
                'radius'   => radius,
                'diameter' => 2.0 * radius,
                'arc'      => self.na_arc(angles),
                'inliers'  => chosen.length
            }.merge(self.na_residuals(residuals))
            if cylinder
                result['from'] = low
                result['to'] = high
                result['length'] = high - low
            end
            if other
                result['other_radius'] = other[2]
                other_centre = centre.dup
                other_centre[u] = other[0]
                other_centre[v] = other[1]
                result['other_centre'] = other_centre
            end
            result
        end

        # Least squares from circle, taking the points within tolerance again
        # each round until they stop changing. Returns [circle, chosen indexes].
        def self.na_circle_settle(flat, circle, tolerance, max_radius)
            take = lambda do |c|
                flat.each_index.select { |i| (Math.hypot(flat[i][0] - c[0], flat[i][1] - c[1]) - c[2]).abs <= tolerance }
            end
            chosen = take.call(circle)
            NA_REFINE_ROUNDS.times do
                break if chosen.length < 3
                refined = self.na_circle_least_squares(chosen.map { |i| flat[i] }, circle)
                # Least squares may drift onto a bigger, flatter circle along a
                # straight piece that meets the arc at a tangent: max_radius holds.
                break if refined[2] > max_radius || refined[2] <= NA_MIN_RADIUS_SHARE * tolerance
                circle = refined
                again = take.call(circle)
                break if again == chosen
                chosen = again
            end
            [circle, chosen]
        end

        # The algebraic (Kasa) circle through every point, [cx, cy, r], or nil:
        # x^2 + y^2 = 2 cx x + 2 cy y + c, solved about the points' centre.
        def self.na_circle_algebraic(flat)
            return nil if flat.length < 3
            mx = flat.sum { |x, _| x } / flat.length
            my = flat.sum { |_, y| y } / flat.length
            m = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
            b = [0.0, 0.0, 0.0]
            flat.each do |x, y|
                dx = x - mx
                dy = y - my
                row = [2.0 * dx, 2.0 * dy, 1.0]
                rhs = dx * dx + dy * dy
                3.times do |i|
                    b[i] += row[i] * rhs
                    3.times { |j| m[i][j] += row[i] * row[j] }
                end
            end
            solved = self.na_solve3(m, b)
            return nil unless solved
            ux, uy, c = solved
            squared = c + ux * ux + uy * uy
            squared > 0 ? [mx + ux, my + uy, Math.sqrt(squared)] : nil
        end

        # The circle through three points [cx, cy, r], or nil when they are in a line.
        def self.na_circle_through(a, b, c)
            d = 2.0 * (a[0] * (b[1] - c[1]) + b[0] * (c[1] - a[1]) + c[0] * (a[1] - b[1]))
            return nil if d.abs < 1e-12
            aa = a[0] * a[0] + a[1] * a[1]
            bb = b[0] * b[0] + b[1] * b[1]
            cc = c[0] * c[0] + c[1] * c[1]
            cx = (aa * (b[1] - c[1]) + bb * (c[1] - a[1]) + cc * (a[1] - b[1])) / d
            cy = (aa * (c[0] - b[0]) + bb * (a[0] - c[0]) + cc * (b[0] - a[0])) / d
            [cx, cy, Math.hypot(a[0] - cx, a[1] - cy)]
        end

        # Geometric least squares (Gauss-Newton on distance to the circle),
        # started from `start` [cx, cy, r].
        def self.na_circle_least_squares(flat, start)
            cx, cy, radius = start
            12.times do
                jtj = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
                jtr = [0.0, 0.0, 0.0]
                flat.each do |x, y|
                    dx = x - cx
                    dy = y - cy
                    distance = Math.hypot(dx, dy)
                    next if distance < 1e-12
                    row = [-dx / distance, -dy / distance, -1.0]
                    residual = distance - radius
                    3.times do |i|
                        jtr[i] += row[i] * residual
                        3.times { |j| jtj[i][j] += row[i] * row[j] }
                    end
                end
                step = self.na_solve3(jtj, jtr.map(&:-@))
                break unless step
                cx += step[0]
                cy += step[1]
                radius += step[2]
                break if step.map(&:abs).max < 1e-9
            end
            [cx, cy, radius.abs]
        end

        # The arc the angles (degrees) cover: from the end of the widest gap
        # round to its start, anticlockwise seen down the axis.
        def self.na_arc(angles)
            return { 'start_deg' => 0.0, 'end_deg' => 0.0, 'span_deg' => 0.0 } if angles.empty?
            sorted = angles.map { |angle| angle % 360.0 }.sort
            gaps = sorted.each_with_index.map { |angle, i| [(i + 1 < sorted.length ? sorted[i + 1] : sorted[0] + 360.0) - angle, i] }
            gap, at = gaps.max_by(&:first)
            start = sorted[(at + 1) % sorted.length]
            { 'start_deg' => start, 'end_deg' => sorted[at], 'span_deg' => 360.0 - gap }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Box turned about a model axis (a post, a newel, a pier)
    # -------------------------------------------------------------------------

        # The smallest rectangle (seen along `axis`) holding the points once
        # trim percent is taken off each side of each direction, searched over
        # every turn of 0 to 90 degrees (1 degree, then 0.05 degrees round the
        # best). width runs along rotation_deg, measured from the first in-plane
        # axis (x for a z box) towards the second.
        def self.Na__Fit__Box(points, axis, trim, tolerance = nil)
            index = NA_AXES.fetch(axis.to_s) { raise ArgumentError, "axis must be x, y or z, not #{axis.inspect}." }
            u, v = NA_PLANE_AXES[index]
            raise ArgumentError, 'A box needs at least 4 points.' if points.length < 4
            share = trim / 100.0
            flat = points.map { |point| [point[u], point[v]] }
            measure = lambda do |degrees|
                c = Math.cos(degrees * Math::PI / 180.0)
                s = Math.sin(degrees * Math::PI / 180.0)
                along = flat.map { |x, y| x * c + y * s }.sort
                across = flat.map { |x, y| -x * s + y * c }.sort
                a = [self.na_percentile(along, share), self.na_percentile(along, 1.0 - share)]
                b = [self.na_percentile(across, share), self.na_percentile(across, 1.0 - share)]
                [(a[1] - a[0]) * (b[1] - b[0]), a, b]
            end
            coarse = (0...90).min_by { |degrees| measure.call(degrees.to_f)[0] }
            fine = (-20..20).map { |step| coarse + step * 0.05 }.min_by { |degrees| measure.call(degrees)[0] }
            fine %= 90.0
            _area, along, across = measure.call(fine)
            c = Math.cos(fine * Math::PI / 180.0)
            s = Math.sin(fine * Math::PI / 180.0)
            mid_a = (along[0] + along[1]) / 2.0
            mid_b = (across[0] + across[1]) / 2.0
            heights = points.map { |point| point[index] }.sort
            low, high = self.na_range(heights, share)
            place = lambda do |a, b, height|
                point = [0.0, 0.0, 0.0]
                point[u] = a * c - b * s
                point[v] = a * s + b * c
                point[index] = height
                point
            end
            corners = [[along[0], across[0]], [along[1], across[0]], [along[1], across[1]], [along[0], across[1]]].map { |a, b| place.call(a, b, low) }
            # Each point's distance from the rectangle's sides, seen along the axis.
            residuals = flat.map do |x, y|
                a = x * c + y * s
                b = -x * s + y * c
                outside_a = [along[0] - a, a - along[1], 0.0].max
                outside_b = [across[0] - b, b - across[1], 0.0].max
                if outside_a > 0 || outside_b > 0
                    Math.hypot(outside_a, outside_b)
                else
                    [a - along[0], along[1] - a, b - across[0], across[1] - b].min
                end
            end
            inliers = tolerance ? residuals.count { |r| r <= tolerance } : points.length
            {
                'centre'       => place.call(mid_a, mid_b, (low + high) / 2.0),
                'axis'         => axis.to_s,
                'rotation_deg' => fine,
                'width'        => along[1] - along[0],
                'depth'        => across[1] - across[0],
                'from'         => low,
                'to'           => high,
                'height'       => high - low,
                'corners'      => corners,
                'trim_percent' => trim,
                'inliers'      => inliers
            }.merge(self.na_residuals(residuals))
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Maths
    # -------------------------------------------------------------------------

        def self.na_subsample(points, rng)
            points.length > NA_RANSAC_POINTS ? points.sample(NA_RANSAC_POINTS, random: rng) : points
        end

        def self.na_residuals(residuals)
            sizes = residuals.map(&:abs).sort
            rms = Math.sqrt(residuals.sum { |r| r * r } / [residuals.length, 1].max)
            { 'rms' => rms, 'p95' => self.na_percentile(sizes, 0.95) }
        end

        # [low, high] of the values: their share and 1 - share percentiles, so a
        # stray point does not stretch an extent, widened by the share they trim
        # (share / (1 - 2 share) of their span each way): exact for evenly
        # spread values, where the bare percentiles came out 2% short (0.14.5).
        def self.na_range(values, share = 0.01)
            sorted = values.sort
            low = self.na_percentile(sorted, share)
            high = self.na_percentile(sorted, 1.0 - share)
            pad = share < 0.5 ? (high - low) * share / (1.0 - 2.0 * share) : 0.0
            [low - pad, high + pad]
        end

        # q (0..1) of sorted values, linear between neighbours.
        def self.na_percentile(sorted, q)
            return 0.0 if sorted.empty?
            at = (sorted.length - 1) * q
            low = at.floor
            high = [low + 1, sorted.length - 1].min
            sorted[low] + (sorted[high] - sorted[low]) * (at - low)
        end

        # A direction's sign made repeatable (0.14.5): up whenever it rises at
        # all (a line uphill, a plane's normal up), and only within NA_LEVEL_SINE
        # of level its larger horizontal part positive. One rule at every
        # steepness, so azimuth_deg always means the same thing.
        def self.na_sign_up(vector)
            key = vector[2].abs > NA_LEVEL_SINE ? 2 : (vector[0].abs >= vector[1].abs ? 0 : 1)
            vector[key] < 0 ? vector.map(&:-@) : vector
        end

        def self.na_mean(points)
            n = points.length.to_f
            [0, 1, 2].map { |i| points.sum { |point| point[i] } / n }
        end

        def self.na_covariance(points, centre)
            matrix = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
            points.each do |point|
                d = [point[0] - centre[0], point[1] - centre[1], point[2] - centre[2]]
                3.times { |i| 3.times { |j| matrix[i][j] += d[i] * d[j] } }
            end
            n = [points.length, 1].max.to_f
            matrix.map { |row| row.map { |value| value / n } }
        end

        # Eigenvalues (smallest first) and unit eigenvectors of a symmetric 3 x 3
        # matrix, by Jacobi rotations.
        def self.na_eigen(matrix)
            a = matrix.map(&:dup)
            vectors = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
            60.times do
                p, q = [[0, 1], [0, 2], [1, 2]].max_by { |i, j| a[i][j].abs }
                scale = a[0][0].abs + a[1][1].abs + a[2][2].abs
                break if a[p][q].abs <= 1e-15 * (scale > 0 ? scale : 1.0)
                theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
                t = (theta >= 0 ? 1.0 : -1.0) / (theta.abs + Math.sqrt(theta * theta + 1.0))
                c = 1.0 / Math.sqrt(t * t + 1.0)
                s = t * c
                3.times do |k|
                    akp = a[k][p]
                    akq = a[k][q]
                    a[k][p] = c * akp - s * akq
                    a[k][q] = s * akp + c * akq
                end
                3.times do |k|
                    apk = a[p][k]
                    aqk = a[q][k]
                    a[p][k] = c * apk - s * aqk
                    a[q][k] = s * apk + c * aqk
                end
                3.times do |k|
                    vkp = vectors[k][p]
                    vkq = vectors[k][q]
                    vectors[k][p] = c * vkp - s * vkq
                    vectors[k][q] = s * vkp + c * vkq
                end
            end
            order = [0, 1, 2].sort_by { |i| a[i][i] }
            [order.map { |i| a[i][i] }, order.map { |i| [vectors[0][i], vectors[1][i], vectors[2][i]] }]
        end

        # x for m x = b (3 x 3), or nil when m is singular.
        def self.na_solve3(m, b)
            det = self.na_det3(m)
            return nil if det.abs < 1e-30
            (0..2).map do |column|
                replaced = m.each_with_index.map { |row, i| row.each_with_index.map { |value, j| j == column ? b[i] : value } }
                self.na_det3(replaced) / det
            end
        end

        def self.na_det3(m)
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        end

        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

        def self.na_cross(a, b)
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end

        def self.na_sub(a, b)
            [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
        end

        def self.na_add(a, b)
            [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
        end

        def self.na_scale(a, k)
            [a[0] * k, a[1] * k, a[2] * k]
        end

        # The unit vector, or nil for (almost) zero length.
        def self.na_unit(a)
            length = Math.sqrt(self.na_dot(a, a))
            length < 1e-12 ? nil : a.map { |value| value / length }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
