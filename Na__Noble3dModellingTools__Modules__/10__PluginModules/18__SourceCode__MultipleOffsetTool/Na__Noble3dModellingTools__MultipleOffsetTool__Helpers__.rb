# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MULTIPLE OFFSET TOOL - HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MultipleOffsetTool__Helpers__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MultipleOffsetTool
# PURPOSE    : Pure per-face offset geometry math (plane frame, 2D offset,
#              winding, intersection, validity, cursor distance)
# CREATED    : 2026
#
# DESIGN NOTE:
# Every offset is computed in the face's OWN plane. The selected bay-window
# panels are individually planar but span multiple planes, so each face gets
# its own local 2D coordinate frame derived from face.normal.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MultipleOffsetTool

# -----------------------------------------------------------------------------
# REGION | Per-Face Plane Frame
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Local 2D Coordinate Frame From Loop Points
        # ------------------------------------------------------------
        # Derives the plane directly from the loop's own world points (Newell
        # normal + first real edge) instead of a transformed face.normal, which
        # could drift under edit transforms. Returns
        # { origin, xaxis, yaxis, zaxis, to_world, to_local }; points pushed
        # through to_local land in the local XY plane (z ~ 0). All inputs/outputs
        # share whatever space the caller supplies (this tool uses world space).
        # ------------------------------------------------------------
        def self.na_build_face_plane_frame(world_points)
            return nil if world_points.nil? || world_points.length < 3

            origin = world_points.first
            normal = na_newell_normal(world_points)
            return nil unless normal && normal.length > 0
            zaxis = normal.normalize

            xaxis = na_first_edge_direction(world_points, zaxis)
            return nil unless xaxis

            yaxis = zaxis.cross(xaxis)
            return nil if yaxis.length == 0
            yaxis = yaxis.normalize
            xaxis = yaxis.cross(zaxis).normalize                          # <-- Re-orthogonalise for an exact frame

            to_world = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
            to_local = to_world.inverse

            {
                origin:   origin,
                xaxis:    xaxis,
                yaxis:    yaxis,
                zaxis:    zaxis,
                to_world: to_world,
                to_local: to_local
            }
        end
        # ------------------------------------------------------------


        # FUNCTION | Newell Method Plane Normal From Polygon Points
        # ------------------------------------------------------------
        # Robust for any planar (or near-planar) loop; independent of vertex count.
        # ------------------------------------------------------------
        def self.na_newell_normal(points)
            count = points.length
            return nil if count < 3

            normal_x = 0.0
            normal_y = 0.0
            normal_z = 0.0
            count.times do |index|
                current = points[index]
                follow  = points[(index + 1) % count]
                normal_x += (current.y - follow.y) * (current.z + follow.z)
                normal_y += (current.z - follow.z) * (current.x + follow.x)
                normal_z += (current.x - follow.x) * (current.y + follow.y)
            end

            Geom::Vector3d.new(normal_x, normal_y, normal_z)
        end
        # ------------------------------------------------------------


        # FUNCTION | First In-Plane Edge Direction (X Axis Seed)
        # ------------------------------------------------------------
        # Returns the first sufficiently long edge direction with the plane-normal
        # component removed, so the X axis lies exactly in the face plane.
        # ------------------------------------------------------------
        def self.na_first_edge_direction(points, zaxis)
            count = points.length
            count.times do |index|
                start_point = points[index]
                end_point   = points[(index + 1) % count]
                edge        = Geom::Vector3d.new(
                    end_point.x - start_point.x,
                    end_point.y - start_point.y,
                    end_point.z - start_point.z
                )
                next if edge.length < MIN_EDGE_LENGTH_INTERNAL

                along = edge.dot(zaxis)
                planar = Geom::Vector3d.new(
                    edge.x - (along * zaxis.x),
                    edge.y - (along * zaxis.y),
                    edge.z - (along * zaxis.z)
                )
                return planar.normalize if planar.length > MIN_EDGE_LENGTH_INTERNAL
            end

            nil
        end
        # ------------------------------------------------------------


        # FUNCTION | Transform a Set of Points Into the Local 2D Frame
        # ------------------------------------------------------------
        def self.na_points_to_local(points, to_local)
            points.map { |point| point.transform(to_local) }
        end
        # ------------------------------------------------------------


        # FUNCTION | Transform Local 2D Points Back Into the Source Space
        # ------------------------------------------------------------
        def self.na_local_to_world(points, to_world)
            points.map { |point| point.transform(to_world) }
        end
        # ------------------------------------------------------------


        # FUNCTION | Average Centroid of a 2D Polygon's Vertices
        # ------------------------------------------------------------
        def self.na_polygon_centroid_2d(points)
            count = points.length
            return nil if count < 1

            sum_x = 0.0
            sum_y = 0.0
            points.each do |point|
                sum_x += point.x
                sum_y += point.y
            end

            Geom::Point3d.new(sum_x / count, sum_y / count, 0)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Polygon Winding & Offset Math
# -----------------------------------------------------------------------------

        # FUNCTION | Signed Area of a 2D Polygon (Shoelace)
        # ------------------------------------------------------------
        # Positive result = counter-clockwise winding, negative = clockwise.
        # ------------------------------------------------------------
        def self.na_signed_area_2d(points)
            count = points.length
            return 0.0 if count < 3

            sum = 0.0
            count.times do |index|
                current = points[index]
                follow  = points[(index + 1) % count]
                sum += (current.x * follow.y) - (follow.x * current.y)
            end

            sum / 2.0
        end
        # ------------------------------------------------------------


        # FUNCTION | Offset a 2D Polygon by a Signed Distance (Miter Join)
        # ------------------------------------------------------------
        # Each edge is shifted along its in-plane perpendicular, then each output
        # vertex is the intersection of the two adjacent offset edge lines.
        # area_sign (+1 CCW / -1 CW) orients the perpendicular so a POSITIVE
        # distance moves inward and a NEGATIVE distance moves outward, regardless
        # of loop winding.
        # ------------------------------------------------------------
        def self.na_inward_offset_polygon(local_points, distance, area_sign)
            count = local_points.length
            return nil if count < 3

            offset_lines = []
            count.times do |index|
                point_a = local_points[index]
                point_b = local_points[(index + 1) % count]
                delta_x = point_b.x - point_a.x
                delta_y = point_b.y - point_a.y
                length  = Math.sqrt((delta_x * delta_x) + (delta_y * delta_y))
                return nil if length < MIN_EDGE_LENGTH_INTERNAL

                normal_x = area_sign * (-delta_y / length)
                normal_y = area_sign * (delta_x / length)
                shift_x  = normal_x * distance
                shift_y  = normal_y * distance

                offset_lines << [
                    Geom::Point3d.new(point_a.x + shift_x, point_a.y + shift_y, 0),
                    Geom::Point3d.new(point_b.x + shift_x, point_b.y + shift_y, 0)
                ]
            end

            new_points = []
            count.times do |index|
                line_prev = offset_lines[(index - 1) % count]
                line_curr = offset_lines[index]
                intersection = self.na_line_intersection_2d(line_prev[0], line_prev[1], line_curr[0], line_curr[1])
                intersection = line_curr[0] if intersection.nil?         # <-- Near-collinear edges: fall back to translated start
                new_points << intersection
            end

            new_points
        end
        # ------------------------------------------------------------


        # FUNCTION | Intersection of Two 2D Lines (Each Given by Two Points)
        # ------------------------------------------------------------
        def self.na_line_intersection_2d(p1, p2, p3, p4)
            x1 = p1.x; y1 = p1.y
            x2 = p2.x; y2 = p2.y
            x3 = p3.x; y3 = p3.y
            x4 = p4.x; y4 = p4.y

            denominator = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4))
            return nil if denominator.abs < LINE_INTERSECT_EPSILON

            cross_a = (x1 * y2) - (y1 * x2)
            cross_b = (x3 * y4) - (y3 * x4)

            px = ((cross_a * (x3 - x4)) - ((x1 - x2) * cross_b)) / denominator
            py = ((cross_a * (y3 - y4)) - ((y1 - y2) * cross_b)) / denominator

            Geom::Point3d.new(px, py, 0)
        end
        # ------------------------------------------------------------


        # FUNCTION | Validate an Offset Polygon Against Its Source
        # ------------------------------------------------------------
        # Rejects collapsed, flipped, exploded, or degenerate results so a face is
        # skipped cleanly in both preview and commit. For an inward inset (expand
        # = false) the "must shrink" and "every vertex inside the original" tests
        # stop the miter math from drawing giant, far-flung loops when the distance
        # is too large. For an outward expansion (expand = true) the result must
        # instead grow and the vertices fall outside the source.
        # ------------------------------------------------------------
        def self.na_offset_polygon_valid?(original_points, offset_points, area_sign, expand = false)
            return false if offset_points.nil? || offset_points.length < 3

            new_area = self.na_signed_area_2d(offset_points)
            return false if new_area.abs < MIN_AREA_INTERNAL              # <-- Collapsed to a sliver / point
            new_sign = new_area >= 0 ? 1 : -1
            return false if new_sign != area_sign                        # <-- Winding flipped: offset overshot the centre

            original_area = self.na_signed_area_2d(original_points)
            if expand
                return false if new_area.abs <= original_area.abs        # <-- Outward offset must be larger than the source
            else
                return false if new_area.abs >= original_area.abs        # <-- Inset must be smaller than the source
            end

            count = offset_points.length
            count.times do |index|
                current = offset_points[index]
                follow  = offset_points[(index + 1) % count]
                delta_x = follow.x - current.x
                delta_y = follow.y - current.y
                length  = Math.sqrt((delta_x * delta_x) + (delta_y * delta_y))
                return false if length < MIN_EDGE_LENGTH_INTERNAL        # <-- Degenerate edge
            end

            unless expand
                offset_points.each do |point|
                    return false unless self.na_point_in_polygon_2d?(point, original_points)  # <-- Exploded vertex left the face
                end
            end

            true
        end
        # ------------------------------------------------------------


        # FUNCTION | Point-In-Polygon Test (2D Ray Casting)
        # ------------------------------------------------------------
        def self.na_point_in_polygon_2d?(point, polygon)
            count = polygon.length
            return false if count < 3

            inside     = false
            point_x    = point.x
            point_y    = point.y
            previous   = count - 1
            count.times do |index|
                xi = polygon[index].x
                yi = polygon[index].y
                xj = polygon[previous].x
                yj = polygon[previous].y

                crosses = ((yi > point_y) != (yj > point_y)) &&
                          (point_x < (((xj - xi) * (point_y - yi)) / (yj - yi)) + xi)
                inside = !inside if crosses
                previous = index
            end

            inside
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cursor Distance Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Minimum Distance From a Local Point to a Polygon Boundary
        # ------------------------------------------------------------
        # Used to translate the hovered cursor position into a natural offset
        # distance (how far the cursor sits inside the boundary).
        # ------------------------------------------------------------
        def self.na_point_to_polygon_min_distance(local_point, local_points)
            count = local_points.length
            return nil if count < 3

            best = nil
            count.times do |index|
                segment_start = local_points[index]
                segment_end   = local_points[(index + 1) % count]
                distance = self.na_point_to_segment_distance_2d(local_point, segment_start, segment_end)
                best = distance if best.nil? || distance < best
            end

            best
        end
        # ------------------------------------------------------------


        # FUNCTION | Distance From a 2D Point to a 2D Segment
        # ------------------------------------------------------------
        def self.na_point_to_segment_distance_2d(point, segment_start, segment_end)
            delta_x = segment_end.x - segment_start.x
            delta_y = segment_end.y - segment_start.y
            length_squared = (delta_x * delta_x) + (delta_y * delta_y)

            if length_squared < (MIN_EDGE_LENGTH_INTERNAL * MIN_EDGE_LENGTH_INTERNAL)
                return Math.sqrt(((point.x - segment_start.x)**2) + ((point.y - segment_start.y)**2))
            end

            parameter = (((point.x - segment_start.x) * delta_x) + ((point.y - segment_start.y) * delta_y)) / length_squared
            parameter = 0.0 if parameter < 0.0
            parameter = 1.0 if parameter > 1.0

            closest_x = segment_start.x + (parameter * delta_x)
            closest_y = segment_start.y + (parameter * delta_y)

            Math.sqrt(((point.x - closest_x)**2) + ((point.y - closest_y)**2))
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__MultipleOffsetTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
