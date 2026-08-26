# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FACE PATTERN GENERATOR - RECT CLIP
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__FacePatternGenerator__RectClip__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__FacePatternGenerator__RectClip
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Trim one pattern unit (an axis-aligned rectangle in local face
#              millimetres) back to the selected face perimeter, so the roof
#              builders can overshoot the face and cut units to the boundary.
# CREATED    : 2026
#
# DESCRIPTION:
# - Ruby mirror of 01__SharedJs/Na__FacePattern__RectClip__.js; both must agree
#   so the SVG preview and the applied SketchUp geometry match.
# - Sutherland-Hodgman clips the face ring against the unit rectangle's four
#   half-planes. The clip window is the rectangle (always convex), so concave
#   face outlines - hips, valleys, dormer cheeks - clip correctly.
# - Holes are subtracted with a convex half-plane decomposition when the hole
#   footprint inside the unit is convex; concave footprints fall back to
#   dropping units centred in the opening.
# - All coordinates are plain [x_mm, y_mm] arrays in the face local basis.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__FacePatternGenerator__RectClip

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_EPSILON       = 1e-6                                                 # <-- Millimetre tolerance for on-edge points
        NA_AREA_FRACTION = 1e-4                                                 # <-- Sliver / full-cover tolerance as a rect fraction
        NA_MIN_AREA_MM2  = 1e-3                                                 # <-- Absolute floor for the sliver area test

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Trim One Rectangular Pattern Unit to the Face Outline
        # ------------------------------------------------------------
        # Returns { rings: [...], full: bool }. A full unit survived whole and
        # can stay a clean rectangle - or a component instance.
        def self.Na__FacePatternGenerator__ClipUnitRect(x_mm, y_mm, width_mm, height_mm, outer, holes)
            return { rings: [], full: false } if width_mm <= 0 || height_mm <= 0
            return { rings: [], full: false } if !outer.is_a?(Array) || outer.length < 3

            rect           = { min_x: x_mm, min_y: y_mm, max_x: x_mm + width_mm, max_y: y_mm + height_mm }
            rect_area      = width_mm * height_mm
            area_tolerance = [NA_MIN_AREA_MM2, rect_area * NA_AREA_FRACTION].max

            region = na_clip_ring_to_rect(outer, rect)
            return { rings: [], full: false } if na_ring_area(region).abs <= area_tolerance

            regions = [region]
            (holes || []).each do |hole|
                break if regions.empty?
                next  unless hole.is_a?(Array) && hole.length >= 3

                footprint = na_clip_ring_to_rect(hole, rect)
                next if na_ring_area(footprint).abs <= area_tolerance            # <-- Opening misses this unit

                if na_convex_ring?(footprint)
                    regions = na_subtract_convex_ring(regions, footprint, area_tolerance)
                else
                    regions = regions.reject { |piece| na_point_in_ring?(na_ring_centroid(piece), hole) }
                end
            end

            return { rings: [], full: false } if regions.empty?

            covered_area = regions.reduce(0.0) { |total, piece| total + na_ring_area(piece).abs }
            if regions.length == 1 && covered_area >= rect_area - area_tolerance
                full_rect = [                                                    # <-- Whole unit fits, hand back a clean rectangle
                    [x_mm, y_mm],
                    [x_mm + width_mm, y_mm],
                    [x_mm + width_mm, y_mm + height_mm],
                    [x_mm, y_mm + height_mm]
                ]
                return { rings: [full_rect], full: true }
            end

            { rings: regions.select { |piece| piece.length >= 3 }, full: false }
        end
        # ------------------------------------------------------------

        # FUNCTION | Clip a Straight Segment to the Face, Returning Inside Runs
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__ClipSegment(start_point, end_point, outer, holes)
            parameters = [0.0, 1.0]
            na_collect_ring_crossings(start_point, end_point, outer, parameters)
            (holes || []).each { |hole| na_collect_ring_crossings(start_point, end_point, hole, parameters) }
            parameters.sort!

            segments = []
            (0...(parameters.length - 1)).each do |index|
                t0 = parameters[index]
                t1 = parameters[index + 1]
                next if (t1 - t0) < 1e-9

                midpoint = na_point_at(start_point, end_point, (t0 + t1) / 2.0)
                next unless self.Na__FacePatternGenerator__PointInFace(midpoint, outer, holes)

                segments << [na_point_at(start_point, end_point, t0), na_point_at(start_point, end_point, t1)]
            end
            segments
        end
        # ------------------------------------------------------------

        # FUNCTION | Test Whether a Local Point Lies Inside the Face Outline
        # ------------------------------------------------------------
        def self.Na__FacePatternGenerator__PointInFace(point, outer, holes)
            return false unless na_point_in_ring?(point, outer)

            (holes || []).none? { |hole| na_point_in_ring?(point, hole) }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ring Primitives
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Signed Area of a Closed Ring (Shoelace)
        # ------------------------------------------------------------
        def self.na_ring_area(ring)
            return 0.0 if !ring.is_a?(Array) || ring.length < 3

            total = 0.0
            ring.each_with_index do |current, index|
                following = ring[(index + 1) % ring.length]
                total += (current[0] * following[1]) - (following[0] * current[1])
            end
            total / 2.0
        end
        private_class_method :na_ring_area
        # ------------------------------------------------------------

        # HELPER FUNCTION | Arithmetic Centroid of a Ring
        # ------------------------------------------------------------
        def self.na_ring_centroid(ring)
            [
                ring.reduce(0.0) { |sum, point| sum + point[0] } / ring.length,
                ring.reduce(0.0) { |sum, point| sum + point[1] } / ring.length
            ]
        end
        private_class_method :na_ring_centroid
        # ------------------------------------------------------------

        # HELPER FUNCTION | Ray-Cast Point-in-Ring Test
        # ------------------------------------------------------------
        def self.na_point_in_ring?(point, ring)
            return false if !ring.is_a?(Array) || ring.length < 3

            inside = false
            previous_index = ring.length - 1
            ring.each_with_index do |current, index|
                previous = ring[previous_index]
                crosses  = (current[1] > point[1]) != (previous[1] > point[1])
                if crosses
                    span = (previous[1] - current[1]).to_f
                    span = 1e-12 if span.abs < 1e-12
                    boundary_x = (((previous[0] - current[0]) * (point[1] - current[1])) / span) + current[0]
                    inside = !inside if point[0] < boundary_x
                end
                previous_index = index
            end
            inside
        end
        private_class_method :na_point_in_ring?
        # ------------------------------------------------------------

        # HELPER FUNCTION | Drop Consecutive Duplicate Vertices Including the Wrap
        # ------------------------------------------------------------
        def self.na_dedupe_ring(ring)
            return [] if !ring.is_a?(Array) || ring.empty?

            output = []
            ring.each do |point|
                previous = output.last
                next if previous && (previous[0] - point[0]).abs < NA_EPSILON && (previous[1] - point[1]).abs < NA_EPSILON

                output << point
            end

            while output.length > 1
                first_point = output.first
                last_point  = output.last
                break if (first_point[0] - last_point[0]).abs >= NA_EPSILON || (first_point[1] - last_point[1]).abs >= NA_EPSILON

                output.pop                                                       # <-- Ring is implicitly closed
            end

            output
        end
        private_class_method :na_dedupe_ring
        # ------------------------------------------------------------

        # HELPER FUNCTION | Test Whether a Ring Turns the Same Way at Every Corner
        # ------------------------------------------------------------
        def self.na_convex_ring?(ring)
            return false if !ring.is_a?(Array) || ring.length < 3

            sign = 0
            ring.each_with_index do |point_a, index|
                point_b = ring[(index + 1) % ring.length]
                point_c = ring[(index + 2) % ring.length]
                cross   = ((point_b[0] - point_a[0]) * (point_c[1] - point_b[1])) -
                          ((point_b[1] - point_a[1]) * (point_c[0] - point_b[0]))
                next if cross.abs < NA_EPSILON                                   # <-- Collinear run, no turn to judge

                turn = cross > 0 ? 1 : -1
                if sign.zero?
                    sign = turn
                elsif turn != sign
                    return false
                end
            end
            !sign.zero?
        end
        private_class_method :na_convex_ring?
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Half-Plane Clipping
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Interpolate the Crossing Point Between Two Signed Distances
        # ------------------------------------------------------------
        def self.na_interpolate(point_a, point_b, distance_a, distance_b)
            span = (distance_a - distance_b).to_f
            return [point_a[0], point_a[1]] if span.abs < 1e-12

            ratio = distance_a / span
            [
                point_a[0] + ((point_b[0] - point_a[0]) * ratio),
                point_a[1] + ((point_b[1] - point_a[1]) * ratio)
            ]
        end
        private_class_method :na_interpolate
        # ------------------------------------------------------------

        # HELPER FUNCTION | Sutherland-Hodgman Clip of a Ring Against One Half-Plane
        # ------------------------------------------------------------
        # The block returns a positive signed distance for points to keep. The
        # subject ring may be concave; the half-plane is trivially convex.
        def self.na_clip_ring_to_half_plane(ring)
            return [] if !ring.is_a?(Array) || ring.length < 3

            output            = []
            previous          = ring.last
            previous_distance = yield(previous)

            ring.each do |current|
                current_distance = yield(current)

                if current_distance >= -NA_EPSILON
                    output << na_interpolate(previous, current, previous_distance, current_distance) if previous_distance < -NA_EPSILON
                    output << current
                elsif previous_distance >= -NA_EPSILON
                    output << na_interpolate(previous, current, previous_distance, current_distance)
                end

                previous          = current
                previous_distance = current_distance
            end

            output
        end
        private_class_method :na_clip_ring_to_half_plane
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clip a Ring to an Axis-Aligned Rectangle
        # ------------------------------------------------------------
        def self.na_clip_ring_to_rect(ring, rect)
            result = ring
            result = na_clip_ring_to_half_plane(result) { |point| point[0] - rect[:min_x] }
            result = na_clip_ring_to_half_plane(result) { |point| rect[:max_x] - point[0] }
            result = na_clip_ring_to_half_plane(result) { |point| point[1] - rect[:min_y] }
            result = na_clip_ring_to_half_plane(result) { |point| rect[:max_y] - point[1] }
            na_dedupe_ring(result)
        end
        private_class_method :na_clip_ring_to_rect
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Convex Hole Subtraction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Signed Side of a Point Against a Directed Hole Edge
        # ------------------------------------------------------------
        def self.na_edge_side(point, edge_start, edge_x, edge_y)
            (edge_x * (point[1] - edge_start[1])) - (edge_y * (point[0] - edge_start[0]))
        end
        private_class_method :na_edge_side
        # ------------------------------------------------------------

        # HELPER FUNCTION | Subtract One Convex Hole Ring from a Set of Regions
        # ------------------------------------------------------------
        # For a counter-clockwise hole, "inside" is left of every directed edge.
        # Walking the edges and peeling off the outside slice of each one yields
        # a disjoint decomposition of region minus hole with no overlaps.
        def self.na_subtract_convex_ring(regions, hole_ring, area_tolerance)
            hole   = na_ring_area(hole_ring) < 0 ? hole_ring.reverse : hole_ring
            pieces = []

            regions.each do |region|
                remainder = region

                hole.each_with_index do |edge_start, index|
                    break if remainder.length < 3

                    edge_end = hole[(index + 1) % hole.length]
                    edge_x   = edge_end[0] - edge_start[0]
                    edge_y   = edge_end[1] - edge_start[1]
                    next if ((edge_x * edge_x) + (edge_y * edge_y)) < NA_EPSILON

                    outside_slice = na_clip_ring_to_half_plane(remainder) { |point| -na_edge_side(point, edge_start, edge_x, edge_y) }
                    outside_slice = na_dedupe_ring(outside_slice)
                    pieces << outside_slice if na_ring_area(outside_slice).abs > area_tolerance

                    inside_slice = na_clip_ring_to_half_plane(remainder) { |point| na_edge_side(point, edge_start, edge_x, edge_y) }
                    remainder    = na_dedupe_ring(inside_slice)
                end
            end

            pieces
        end
        private_class_method :na_subtract_convex_ring
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Segment Clipping
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Collect Segment Parameters Where a Ring Is Crossed
        # ------------------------------------------------------------
        def self.na_collect_ring_crossings(start_point, end_point, ring, parameters)
            return unless ring.is_a?(Array) && ring.length >= 3

            delta_x = end_point[0] - start_point[0]
            delta_y = end_point[1] - start_point[1]

            ring.each_with_index do |edge_start, index|
                edge_end = ring[(index + 1) % ring.length]
                edge_x   = edge_end[0] - edge_start[0]
                edge_y   = edge_end[1] - edge_start[1]

                denominator = (delta_x * edge_y) - (delta_y * edge_x)
                next if denominator.abs < 1e-12                                  # <-- Parallel or degenerate edge

                offset_x = edge_start[0] - start_point[0]
                offset_y = edge_start[1] - start_point[1]
                t = ((offset_x * edge_y) - (offset_y * edge_x)) / denominator
                u = ((offset_x * delta_y) - (offset_y * delta_x)) / denominator
                next if t <= 0 || t >= 1 || u < 0 || u > 1

                parameters << t
            end
        end
        private_class_method :na_collect_ring_crossings
        # ------------------------------------------------------------

        # HELPER FUNCTION | Evaluate a Point Along a Segment Parameter
        # ------------------------------------------------------------
        def self.na_point_at(start_point, end_point, t)
            [
                start_point[0] + ((end_point[0] - start_point[0]) * t),
                start_point[1] + ((end_point[1] - start_point[1]) * t)
            ]
        end
        private_class_method :na_point_at
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FacePatternGenerator__RectClip
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
