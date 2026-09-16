# =============================================================================
# NA ARRAY BUILDER TOOLS - PATH INFERENCE
# FILE       : Na__ArrayBuilder__PathInference__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Infer virtual path corners from the start without model geometry.
# =============================================================================

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__PathInference

        NA_ACQUIRE_PIXELS = 12.0
        NA_RELEASE_PIXELS = 18.0
        NA_POINT_TOLERANCE = 0.001

        # FUNCTION | Resolve Start Endpoint or an Aligned Closing Corner
        # ------------------------------------------------------------
        # Points are WORLD coordinates, including inside an open nested context.
        # Screen distances give the same acquisition behaviour at any zoom level.
        def self.Na__Inference__Resolve(na_points, na_cursor, na_view, na_lock = nil, na_previous = nil)
            return nil if na_points.length < 3
            na_first, na_last = na_points.first, na_points.last
            return nil if na_last.distance(na_first) < NA_POINT_TOLERANCE
            na_axes = Na__Inference__Axes(na_points)
            na_candidates = []
            if !na_lock || Na__Inference__OnLine?(na_first, na_last, na_lock)
                na_candidates << { point: na_first, kind: :start, label: 'Start point — click to close loop', colour: [30,150,85] }
            end
            na_travel_axes = na_lock ? [na_lock] : na_axes.map { |na_axis| na_axis[:vector] }
            na_travel_axes.each do |na_travel|
                na_axes.each do |na_axis|
                    na_point = Na__Inference__Intersection(na_last, na_travel, na_first, na_axis[:vector])
                    next unless na_point
                    next if na_point.distance(na_first) < NA_POINT_TOLERANCE || na_point.distance(na_last) < NA_POINT_TOLERANCE
                    na_candidates << { point: na_point, kind: :alignment,
                        label: "From start point · #{na_axis[:label]}", colour: na_axis[:colour] }
                end
            end
            na_screen = na_view.screen_coords(na_cursor)
            na_ranked = na_candidates.filter_map do |na_candidate|
                na_same = na_previous && na_previous[:kind] == na_candidate[:kind] &&
                    na_previous[:point].distance(na_candidate[:point]) < NA_POINT_TOLERANCE
                na_radius = na_same ? NA_RELEASE_PIXELS : NA_ACQUIRE_PIXELS
                na_target = na_view.screen_coords(na_candidate[:point])
                na_distance = Math.hypot(na_screen.x - na_target.x, na_screen.y - na_target.y)
                next if na_distance > na_radius
                [na_candidate, na_distance, na_same ? 0 : 1]
            end
            # The actual start endpoint takes precedence over alignment guides.
            na_best = na_ranked.min_by { |na_candidate, na_distance, na_stability|
                [na_candidate[:kind] == :start ? 0 : 1, na_stability, na_distance]
            }
            na_best && na_best.first
        end

        # FUNCTION | World Axes and the Drawn Path's Own Rotated Plane
        # ------------------------------------------------------------
        def self.Na__Inference__Axes(na_points)
            na_axes = [
                { vector: X_AXIS, label: 'red axis', colour: [210,60,60] },
                { vector: Y_AXIS, label: 'green axis', colour: [40,145,80] },
                { vector: Z_AXIS, label: 'blue axis', colour: [55,100,210] }
            ]
            na_first = na_points[1] - na_points[0]
            if na_first.length > NA_POINT_TOLERANCE
                na_directions = [na_first]
                na_points.reverse.each_cons(2) do |na_b, na_a|
                    na_direction = na_b - na_a
                    next if na_direction.length < NA_POINT_TOLERANCE || na_first.cross(na_direction).length < NA_POINT_TOLERANCE
                    na_normal = na_first.cross(na_direction).normalize
                    na_directions.concat([na_direction, na_normal.cross(na_first)])
                    break
                end
                na_directions.each do |na_direction|
                    na_direction = na_direction.normalize
                    next if na_axes.any? { |na_axis| na_axis[:vector].cross(na_direction).length < 0.000001 }
                    na_axes << { vector: na_direction, label: 'path alignment', colour: [145,75,175] }
                end
            end
            na_axes
        end

        def self.Na__Inference__Dot(na_a, na_b)
            na_a.x * na_b.x + na_a.y * na_b.y + na_a.z * na_b.z
        end

        def self.Na__Inference__OnLine?(na_point, na_anchor, na_direction)
            (na_point - na_anchor).cross(na_direction.normalize).length < NA_POINT_TOLERANCE
        end

        # FUNCTION | Intersect True 3D Lines; Reject Parallel or Skew Guides
        # ------------------------------------------------------------
        def self.Na__Inference__Intersection(na_a, na_u, na_b, na_v)
            na_u, na_v = na_u.normalize, na_v.normalize
            na_dot = Na__Inference__Dot(na_u, na_v)
            na_denominator = 1.0 - na_dot * na_dot
            return nil if na_denominator < 0.000001
            na_delta = na_b - na_a
            na_distance = (Na__Inference__Dot(na_delta, na_u) - na_dot * Na__Inference__Dot(na_delta, na_v)) / na_denominator
            na_point = na_a.offset(na_u, na_distance)
            Na__Inference__OnLine?(na_point, na_b, na_v) ? na_point : nil
        end

    end # module Na__ArrayBuilder__PathInference
end # module Na__ArrayBuilderTools
