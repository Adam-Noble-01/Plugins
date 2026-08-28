# =============================================================================
# NA PROFILE TOOLS - APPLY PROFILE - 3D PREVIEW GRAPHICS
# =============================================================================
#
# FILE       : Na__ProfileTools__ApplyProfile__3dPreviewGraphics__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__PreviewGraphics
# PURPOSE    : Stateless rendering helpers for in-viewport preview
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__PreviewGraphics

        NA_LOOP_CLOSE_TOLERANCE = 0.001

        def self.Na__Preview__DrawCrosshair(view, cursor_pos, arm_size)
            cx = cursor_pos.x
            cy = cursor_pos.y
            cz = cursor_pos.z

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = Sketchup::Color.new(220, 35, 35)

            view.draw_line(cursor_pos, Geom::Point3d.new(cx + arm_size, cy, cz))
            view.draw_line(cursor_pos, Geom::Point3d.new(cx - arm_size, cy, cz))
            view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy + arm_size, cz))
            view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy - arm_size, cz))
            view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy, cz + arm_size))
            view.draw_line(cursor_pos, Geom::Point3d.new(cx, cy, cz - arm_size))
        end

        def self.Na__Preview__DrawPath(view, ordered_points)
            return if ordered_points.nil? || ordered_points.length < 2

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = Sketchup::Color.new(60, 130, 220)
            view.draw(GL_LINE_STRIP, ordered_points)
        end

        def self.Na__Preview__DrawWaypointMarkers(view, waypoints, marker_size)
            return if waypoints.nil? || waypoints.empty?

            view.line_stipple  = ''
            view.line_width    = 3
            view.drawing_color = Sketchup::Color.new(255, 220, 0)

            waypoints.each do |waypoint|
                view.draw_line(
                    waypoint.offset(X_AXIS, -marker_size),
                    waypoint.offset(X_AXIS, marker_size)
                )
                view.draw_line(
                    waypoint.offset(Y_AXIS, -marker_size),
                    waypoint.offset(Y_AXIS, marker_size)
                )
                view.draw_line(
                    waypoint.offset(Z_AXIS, -marker_size),
                    waypoint.offset(Z_AXIS, marker_size)
                )
            end
        end

        def self.Na__Preview__DrawCandidateVertex(view, candidate_point)
            return unless candidate_point
            view.line_stipple  = ''
            view.line_width    = 6
            view.drawing_color = Sketchup::Color.new(255, 120, 0)
            view.draw_points([candidate_point], 10, 3, 'x')
        end

        def self.Na__Preview__DrawSweepSegments(view, sweep_segments)
            return unless sweep_segments.is_a?(Array)
            return if sweep_segments.empty?

            view.line_stipple  = ''
            view.line_width    = 1
            view.drawing_color = Sketchup::Color.new(0, 200, 180, 160)
            view.draw(GL_LINES, sweep_segments)
        end

        def self.Na__Preview__DrawProfileGhost(view, transformed_profile_points)
            return if transformed_profile_points.nil? || transformed_profile_points.length < 2

            view.line_stipple  = '-'
            view.line_width    = 2
            view.drawing_color = Sketchup::Color.new(0, 155, 110, 180)
            view.draw(GL_LINE_STRIP, transformed_profile_points)
        end

        # The datum cross-section shown before any path exists. Solid and closed,
        # unlike the dashed ghost that rides the cursor mid-sweep, because at this
        # point it is the only thing on screen telling the user which way up the
        # profile will land.
        def self.Na__Preview__DrawProfileFace(view, transformed_profile_points)
            return if transformed_profile_points.nil? || transformed_profile_points.length < 3

            outline_points = self.Na__Preview__ClosedLoopPoints(transformed_profile_points)

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = Sketchup::Color.new(0, 155, 110)
            view.draw(GL_LINE_STRIP, outline_points)
        end

        # An authored outer loop does not repeat its first vertex, so GL_LINE_STRIP
        # would leave the profile visibly open along its closing edge.
        def self.Na__Preview__ClosedLoopPoints(loop_points)
            first_point = loop_points.first
            last_point  = loop_points.last
            return loop_points if first_point.distance(last_point) <= NA_LOOP_CLOSE_TOLERANCE
            loop_points + [first_point]
        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
