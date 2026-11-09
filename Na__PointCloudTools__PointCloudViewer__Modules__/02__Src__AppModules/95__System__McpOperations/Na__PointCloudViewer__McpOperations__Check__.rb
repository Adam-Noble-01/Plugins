# =============================================================================
# NA POINT CLOUD VIEWER - MCP OPERATIONS - MODEL TO CLOUD CHECK
# =============================================================================
#
# FILE       : Na__PointCloudViewer__McpOperations__Check__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__McpCheck
# CREATED    : 09-Nov-2026 (v0.14.3)
# PURPOSE    : How far points sit from a model's surfaces, for the Na SketchUp
#              MCP's point_cloud_check. For each point: the nearest triangle
#              within reach, the distance, and the side it is on (outside the
#              face, along its normal, is positive: the model sits inside the
#              scan there). Pure Ruby, no SketchUp API: the MCP handler turns
#              the faces into world triangles, the seam reads an even sample
#              of the points with napc_box_points.
#
# METHOD:
# - Triangles go into a grid of cells `reach` wide. A triangle goes into every
#   cell its bounding box touches; one whose box would touch more than
#   NA_SLAB_CELLS cells (a big face on a slant) only into the cells its plane
#   passes through, found column by column along the axis the plane faces
#   most (0.14.5), so the cost follows those cells, not the whole box.
# - A point looks in its own cell and the 26 round it, so every triangle within
#   reach is found; each triangle is measured once per point (a stamp).
# - Closest point on a triangle: Ericson, Real-Time Collision Detection, 5.1.5.
# - The side (0.14.5): when the nearest point is an edge or corner that several
#   faces share, the sum of their normals decides it (the pseudo-normal of
#   Baerentzen and Aanaes), so a point just outside a sharp ridge reads outside.
#
# Every length in and out is in model inches.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__McpCheck

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_SLAB_CELLS     = 64
        NA_MAX_CELLS      = 4_000_000
        NA_MAX_BOX_CELLS  = 2_000_000  # one triangle's bounding box, before the plane test
        NA_MIN_AREA2      = 1e-16      # twice a triangle's area, squared: smaller is skipped
        NA_HALF_DIAGONAL  = 0.8661     # a cell's half diagonal, in cells (a little over sqrt(3) / 2)
        NA_TIE            = 1e-12      # nearest points this close (relative, squared) are the same point

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Index
    # -------------------------------------------------------------------------

        # triangles: [[a, b, c, normal, part], ...] (normal: the face's outward
        # unit normal; part: an index the caller groups results by). Returns the
        # index Na__Check__Nearest reads. Degenerate triangles are left out.
        def self.Na__Check__Index(triangles, reach)
            raise ArgumentError, 'reach must be positive.' unless reach > 0
            cell = reach.to_f
            grid = {}
            kept = []
            filled = 0
            triangles.each do |triangle|
                a, b, c = triangle
                cross = self.na_cross(self.na_sub(b, a), self.na_sub(c, a))
                next if self.na_dot(cross, cross) < NA_MIN_AREA2
                index = kept.length
                kept << triangle
                lo = (0..2).map { |i| ([a[i], b[i], c[i]].min / cell).floor }
                hi = (0..2).map { |i| ([a[i], b[i], c[i]].max / cell).floor }
                count = (hi[0] - lo[0] + 1) * (hi[1] - lo[1] + 1) * (hi[2] - lo[2] + 1)
                if count <= NA_SLAB_CELLS
                    (lo[0]..hi[0]).each do |x|
                        (lo[1]..hi[1]).each do |y|
                            (lo[2]..hi[2]).each do |z|
                                (grid[[x, y, z]] ||= []) << index
                                filled += 1
                            end
                        end
                    end
                else
                    filled += self.na_slab_cells(grid, index, a, cross, lo, hi, cell)
                end
                raise ArgumentError, "The faces fill more than #{NA_MAX_CELLS} grid cells at this reach; raise reach or check fewer faces." if filled > NA_MAX_CELLS
            end
            { 'cell' => cell, 'grid' => grid, 'triangles' => kept, 'stamp' => Array.new(kept.length, -1) }
        end

        # A big face's cells: those of its bounding box whose centre is within
        # half a cell's diagonal of its plane, found column by column along the
        # axis the plane faces most (k): in each column only the few cells the
        # plane crosses are tested. The same cells the whole-box test kept, at a
        # cost that follows them (0.14.5). Returns how many were filled.
        def self.na_slab_cells(grid, index, a, cross, lo, hi, cell)
            length = Math.sqrt(self.na_dot(cross, cross))
            normal = cross.map { |x| x / length }
            k = (0..2).max_by { |axis| normal[axis].abs }
            i, j = [0, 1, 2] - [k]
            columns = (hi[i] - lo[i] + 1) * (hi[j] - lo[j] + 1)
            if columns > NA_MAX_BOX_CELLS
                raise ArgumentError, "A face spans #{columns} grid columns at this reach; raise reach or check fewer faces."
            end
            limit = NA_HALF_DIAGONAL * cell
            spread = limit / normal[k].abs
            filled = 0
            (lo[i]..hi[i]).each do |ci|
                (lo[j]..hi[j]).each do |cj|
                    # The plane's k over this column: it is flat, so its corners bound it.
                    ks = [ci * cell, (ci + 1) * cell].product([cj * cell, (cj + 1) * cell]).map do |pi, pj|
                        a[k] - (normal[i] * (pi - a[i]) + normal[j] * (pj - a[j])) / normal[k]
                    end
                    first = [((ks.min - spread) / cell - 0.5).ceil, lo[k]].max
                    last = [((ks.max + spread) / cell - 0.5).floor, hi[k]].min
                    (first..last).each do |ck|
                        key = [0, 0, 0]
                        key[i] = ci
                        key[j] = cj
                        key[k] = ck
                        centre = [(key[0] + 0.5) * cell - a[0], (key[1] + 0.5) * cell - a[1], (key[2] + 0.5) * cell - a[2]]
                        next if self.na_dot(normal, centre).abs > limit
                        (grid[key] ||= []) << index
                        filled += 1
                    end
                end
            end
            filled
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Nearest Triangle
    # -------------------------------------------------------------------------

        # [distance, signed distance, triangle] for the nearest triangle within
        # reach of point, or nil. ticket must change from call to call (the
        # point's number does).
        def self.Na__Check__Nearest(index, point, ticket)
            cell = index['cell']
            grid = index['grid']
            triangles = index['triangles']
            stamp = index['stamp']
            px, py, pz = point
            cx = (px / cell).floor
            cy = (py / cell).floor
            cz = (pz / cell).floor
            best = nil
            best_d2 = cell * cell
            best_q = nil
            shared = nil   # the summed normals of every face whose nearest point is best_q (a shared edge or corner)
            (cx - 1..cx + 1).each do |x|
                (cy - 1..cy + 1).each do |y|
                    (cz - 1..cz + 1).each do |z|
                        list = grid[[x, y, z]]
                        next unless list
                        list.each do |t|
                            next if stamp[t] == ticket
                            stamp[t] = ticket
                            a, b, c = triangles[t]
                            q = self.na_closest(px, py, pz, a, b, c)
                            dx = px - q[0]
                            dy = py - q[1]
                            dz = pz - q[2]
                            d2 = dx * dx + dy * dy + dz * dz
                            tie = NA_TIE * (1.0 + best_d2)
                            next if d2 > best_d2 + tie
                            normal = triangles[t][3]
                            if best && (d2 - best_d2).abs <= tie &&
                               (q[0] - best_q[0])**2 + (q[1] - best_q[1])**2 + (q[2] - best_q[2])**2 <= tie
                                3.times { |k| shared[k] += normal[k] }
                                next
                            end
                            next unless best.nil? || d2 < best_d2
                            best_d2 = d2
                            best = t
                            best_q = q
                            shared = normal.dup
                        end
                    end
                end
            end
            return nil unless best
            distance = Math.sqrt(best_d2)
            normal = shared[0]**2 + shared[1]**2 + shared[2]**2 > 1e-18 ? shared : triangles[best][3]
            side = (px - best_q[0]) * normal[0] + (py - best_q[1]) * normal[1] + (pz - best_q[2]) * normal[2]
            [distance, side < 0 ? -distance : distance, best]
        end

        # The point of triangle abc nearest p (Ericson 5.1.5), as [x, y, z].
        def self.na_closest(px, py, pz, a, b, c)
            abx = b[0] - a[0]
            aby = b[1] - a[1]
            abz = b[2] - a[2]
            acx = c[0] - a[0]
            acy = c[1] - a[1]
            acz = c[2] - a[2]
            apx = px - a[0]
            apy = py - a[1]
            apz = pz - a[2]
            d1 = abx * apx + aby * apy + abz * apz
            d2 = acx * apx + acy * apy + acz * apz
            return a if d1 <= 0 && d2 <= 0
            bpx = px - b[0]
            bpy = py - b[1]
            bpz = pz - b[2]
            d3 = abx * bpx + aby * bpy + abz * bpz
            d4 = acx * bpx + acy * bpy + acz * bpz
            return b if d3 >= 0 && d4 <= d3
            vc = d1 * d4 - d3 * d2
            if vc <= 0 && d1 >= 0 && d3 <= 0
                v = d1 / (d1 - d3)
                return [a[0] + abx * v, a[1] + aby * v, a[2] + abz * v]
            end
            cpx = px - c[0]
            cpy = py - c[1]
            cpz = pz - c[2]
            d5 = abx * cpx + aby * cpy + abz * cpz
            d6 = acx * cpx + acy * cpy + acz * cpz
            return c if d6 >= 0 && d5 <= d6
            vb = d5 * d2 - d1 * d6
            if vb <= 0 && d2 >= 0 && d6 <= 0
                w = d2 / (d2 - d6)
                return [a[0] + acx * w, a[1] + acy * w, a[2] + acz * w]
            end
            va = d3 * d6 - d5 * d4
            if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0
                w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
                return [b[0] + (c[0] - b[0]) * w, b[1] + (c[1] - b[1]) * w, b[2] + (c[2] - b[2]) * w]
            end
            denominator = 1.0 / (va + vb + vc)
            v = vb * denominator
            w = vc * denominator
            [a[0] + abx * v + acx * w, a[1] + aby * v + acy * w, a[2] + abz * v + acz * w]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Summaries
    # -------------------------------------------------------------------------

        # Distances (signed) -> { 'points', 'rms', 'mean', 'p50', 'p95', 'max',
        # 'within' (the share within tolerance) }, all inches but the counts.
        def self.Na__Check__Summary(signed, tolerance)
            return { 'points' => 0 } if signed.empty?
            sizes = signed.map(&:abs).sort
            {
                'points' => signed.length,
                'rms'    => Math.sqrt(signed.sum { |d| d * d } / signed.length),
                'mean'   => signed.sum / signed.length,
                'p50'    => self.na_percentile(sizes, 0.5),
                'p95'    => self.na_percentile(sizes, 0.95),
                'max'    => sizes.last,
                'within' => sizes.count { |d| d <= tolerance }.to_f / sizes.length
            }
        end

        # The worst places: points beyond tolerance gathered into cells `size`
        # wide, the fullest first. [{ 'centre', 'points', 'mean' }].
        def self.Na__Check__Spots(points, signed, tolerance, size, limit)
            cells = {}
            points.each_with_index do |point, i|
                next if signed[i].abs <= tolerance
                key = point.map { |x| (x / size).floor }
                entry = (cells[key] ||= { 'sum' => [0.0, 0.0, 0.0], 'points' => 0, 'distance' => 0.0 })
                3.times { |k| entry['sum'][k] += point[k] }
                entry['points'] += 1
                entry['distance'] += signed[i]
            end
            cells.values.sort_by { |entry| -entry['points'] }.first(limit).map do |entry|
                n = entry['points']
                { 'centre' => entry['sum'].map { |x| x / n }, 'points' => n, 'mean' => entry['distance'] / n }
            end
        end

        def self.na_percentile(sorted, q)
            return 0.0 if sorted.empty?
            at = (sorted.length - 1) * q
            low = at.floor
            high = [low + 1, sorted.length - 1].min
            sorted[low] + (sorted[high] - sorted[low]) * (at - low)
        end

        def self.na_sub(a, b)
            [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
        end

        def self.na_cross(a, b)
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end

        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
