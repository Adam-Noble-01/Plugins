# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - MIRROR PROFILE
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__MirrorProfile__.rb
# PURPOSE    : Local profile mirror transforms for preview/build parity
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__MirrorProfile

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # Applies flip toggles in a deterministic order so preview/build match:
        # 1) center mirrors, 2) world-origin mirrors.
        def self.Na__Mirror__ApplyToggles(local_points, toggle_states = {})
            return [] unless local_points.is_a?(Array)
            valid_points = local_points.select { |point| point.is_a?(Geom::Point3d) }
            return [] if valid_points.empty?

            mirrored_points = valid_points.map { |point| point.clone }
            center = self.Na__Mirror__ComputeCenter(mirrored_points)

            if toggle_states['flipXCenter'] == true
                mirrored_points = self.Na__Mirror__FlipAcrossXAtY(mirrored_points, center.y)
            end

            if toggle_states['flipYCenter'] == true
                mirrored_points = self.Na__Mirror__FlipAcrossYAtX(mirrored_points, center.x)
            end

            if toggle_states['flipXWorld'] == true
                mirrored_points = self.Na__Mirror__FlipAcrossXAtY(mirrored_points, 0.0)
            end

            if toggle_states['flipYWorld'] == true
                mirrored_points = self.Na__Mirror__FlipAcrossYAtX(mirrored_points, 0.0)
            end

            mirrored_points
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Helpers
    # -------------------------------------------------------------------------

        def self.Na__Mirror__ComputeCenter(points)
            min_x = points.map(&:x).min
            max_x = points.map(&:x).max
            min_y = points.map(&:y).min
            max_y = points.map(&:y).max
            min_z = points.map(&:z).min
            max_z = points.map(&:z).max

            Geom::Point3d.new(
                (min_x + max_x) / 2.0,
                (min_y + max_y) / 2.0,
                (min_z + max_z) / 2.0
            )
        end

        # Reflects points across horizontal axis y = axis_y.
        def self.Na__Mirror__FlipAcrossXAtY(points, axis_y)
            points.map do |point|
                mirrored_y = (2.0 * axis_y) - point.y
                Geom::Point3d.new(point.x, mirrored_y, point.z)
            end
        end

        # Reflects points across vertical axis x = axis_x.
        def self.Na__Mirror__FlipAcrossYAtX(points, axis_x)
            points.map do |point|
                mirrored_x = (2.0 * axis_x) - point.x
                Geom::Point3d.new(mirrored_x, point.y, point.z)
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
