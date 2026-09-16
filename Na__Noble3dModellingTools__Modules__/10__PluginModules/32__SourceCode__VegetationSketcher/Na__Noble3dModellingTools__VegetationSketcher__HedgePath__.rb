# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - HEDGE PATH
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__HedgePath__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__HedgePath
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Validate a planar hedge polyline and build a mitered sweep
# CREATED    : 2026
#
# A bend is one cross section of one closed surface: there are no internal
# end caps or overlapping boxes. Units remain millimetres until Builder
# converts to SketchUp inches.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__HedgePath

# -----------------------------------------------------------------------------
# REGION | Public Path API
# -----------------------------------------------------------------------------

        # FUNCTION | Normalise and Reject an Invalid Hedge Polyline
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__HedgePath__Validate(raw)
            return nil if raw.nil?
            raise ArgumentError, 'A hedge path needs 2 to 256 points.' unless raw.is_a?(Array) && raw.length.between?(2, 256)

            points = raw.map { |point| na_normalise_path_point(point) }
            lengths = points.each_cons(2).map { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }
            raise ArgumentError, 'Each hedge run must be at least 50 mm.' if lengths.any? { |n| n < 49.999 }
            raise ArgumentError, 'Keep the total hedge path within 100 m.' if lengths.sum > 100000.001

            points
        end
        # ------------------------------------------------------------

        # FUNCTION | Plan Length of a Validated Polyline
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__HedgePath__Length(points)
            points.each_cons(2).sum { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }
        end
        # ------------------------------------------------------------

        # FUNCTION | Build Miter Sections, Mesh Lengths and an Outline Check
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__HedgePath__Prepare(points, width)
            segments = na_segment_list(points)
            miters = na_miter_normals(points, segments)
            total = na_annotate_segment_lengths(segments, miters, width)
            na_reject_overlapping_outline(points, miters, width)

            {
                points:      points,
                miters:      miters,
                segments:    segments,
                length:      total,
                width_scale: miters.map { |v| Math.hypot(*v) }.max
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Sample Stations Along the Sweep For the Quad Lattice
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__HedgePath__Stations(path, resolution)
            values = [0.0]
            path[:segments].each do |segment|
                n = [(segment[:mesh_length] / resolution).ceil, 1].max
                1.upto(n) { |i| values << segment[:start] + segment[:length] * i / n.to_f }
            end
            values
        end
        # ------------------------------------------------------------

        # FUNCTION | Map a Straight-Box Point Onto the Mitered Sweep
        # ------------------------------------------------------------
        def self.Na__VegetationSketcher__HedgePath__Warp(point, path)
            s, y, z = point
            index = path[:segments].bsearch_index { |segment| segment[:finish] >= s } || path[:segments].length - 1
            segment = path[:segments][index]
            t = (s - segment[:start]) / segment[:length]
            a, b = path[:points][index], path[:points][index + 1]
            n0, n1 = path[:miters][index], path[:miters][index + 1]
            [
                a[0] + (b[0] - a[0]) * t + (n0[0] + (n1[0] - n0[0]) * t) * y,
                a[1] + (b[1] - a[1]) * t + (n0[1] + (n1[1] - n0[1]) * t) * y,
                z
            ]
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Require a Finite Horizontal Path Point
        # ------------------------------------------------------------
        def self.na_normalise_path_point(point)
            raise ArgumentError, 'Invalid hedge path point.' unless point.is_a?(Array) && point.length == 3

            p = point.map { |n| Float(n) }
            raise ArgumentError, 'Hedge path coordinates must be finite.' unless p.all?(&:finite?)
            raise ArgumentError, 'Hedge paths must stay on their horizontal planting plane.' if p[2].abs > 0.001

            [p[0], p[1], 0.0]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Tangent and Left-Normal For Each Run
        # ------------------------------------------------------------
        def self.na_segment_list(points)
            points.each_cons(2).map do |a, b|
                distance = Math.hypot(b[0] - a[0], b[1] - a[1])
                tangent = [(b[0] - a[0]) / distance, (b[1] - a[1]) / distance]
                { length: distance, tangent: tangent, normal: [-tangent[1], tangent[0]] }
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Shared Miter Offset Vectors at Each Vertex
        # ------------------------------------------------------------
        def self.na_miter_normals(points, segments)
            points.each_index.map do |i|
                if i.zero?
                    segments.first[:normal]
                elsif i == points.length - 1
                    segments.last[:normal]
                else
                    a, b = segments[i - 1], segments[i]
                    denominator = 1 + na_dot(a[:tangent], b[:tangent])
                    raise ArgumentError, 'This turn is too sharp. Add a wider turn instead of doubling back.' if denominator < 0.15

                    2.times.map { |k| (a[:normal][k] + b[:normal][k]) / denominator }
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Accumulate Path Stations and Reject Too-Short Miters
        # ------------------------------------------------------------
        def self.na_annotate_segment_lengths(segments, miters, width)
            total = 0.0
            segments.each_with_index do |segment, i|
                shear = na_dot(2.times.map { |k| miters[i + 1][k] - miters[i][k] }, segment[:tangent]).abs * width / 2.0
                raise ArgumentError, 'Lengthen the run at this corner, or reduce the hedge width.' if segment[:length] <= shear + 2

                segment[:mesh_length] = segment[:length] + shear
                segment[:start] = total
                total += segment[:length]
                segment[:finish] = total
            end
            total
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Reject Self-Intersecting or Overlapping Outlines
        # ------------------------------------------------------------
        def self.na_reject_overlapping_outline(points, miters, width)
            left = points.each_with_index.map { |p, i| 2.times.map { |k| p[k] + miters[i][k] * width / 2.0 } }
            right = points.each_with_index.map { |p, i| 2.times.map { |k| p[k] - miters[i][k] * width / 2.0 } }
            outline = left + right.reverse
            outline.each_index do |i|
                (i + 2...outline.length).each do |j|
                    next if i.zero? && j == outline.length - 1

                    if na_segments_intersect?(outline[i], outline[(i + 1) % outline.length], outline[j], outline[(j + 1) % outline.length])
                        raise ArgumentError, 'These hedge runs overlap. Space the path farther apart or reduce its width.'
                    end
                end
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | 2D Dot Product
        # ------------------------------------------------------------
        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1]
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | True When Two Plan Segments Cross or Overlap
        # ------------------------------------------------------------
        def self.na_segments_intersect?(a, b, c, d)
            cross = lambda { |p, q, r| (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]) }
            x, y, z, w = cross.call(a, b, c), cross.call(a, b, d), cross.call(c, d, a), cross.call(c, d, b)
            return true if x * y < 0 && z * w < 0

            [[x, c, a, b], [y, d, a, b], [z, a, c, d], [w, b, c, d]].any? do |area, p, q, r|
                area.abs < 0.0001 &&
                    p[0].between?([q[0], r[0]].min - 0.001, [q[0], r[0]].max + 0.001) &&
                    p[1].between?([q[1], r[1]].min - 0.001, [q[1], r[1]].max + 0.001)
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__VegetationSketcher__HedgePath
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
