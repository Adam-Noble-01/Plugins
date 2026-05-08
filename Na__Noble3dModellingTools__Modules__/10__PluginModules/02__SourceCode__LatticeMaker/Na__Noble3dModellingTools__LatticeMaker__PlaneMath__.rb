# =============================================================================
# NA NOBLE3D MODELLING TOOLS - LATTICE MAKER - PLANE MATH HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__LatticeMaker__PlaneMath__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__LatticeMaker__PlaneMath
# PURPOSE    : Working-plane generation and lattice footprint construction
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__LatticeMaker__PlaneMath

# -----------------------------------------------------------------------------
# REGION | Working Plane Solvers
# -----------------------------------------------------------------------------

        # FUNCTION | Build Working Plane Transform Set from Segments
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__CalculateWorkingPlane(segments)
            points = segments.flatten
            origin = points.first.clone

            xaxis = self.Na__LatticeMaker__FindFirstSegmentVector(segments)
            raise 'Could not find a usable direction from the selected edges.' unless xaxis

            raw_normal = self.Na__LatticeMaker__FindNormalFromSegments(origin, xaxis, points)
            raw_normal = self.Na__LatticeMaker__FallbackNormalFromCamera(xaxis) unless raw_normal

            xaxis.normalize!
            yaxis = raw_normal.cross(xaxis)

            if yaxis.length < 0.001.mm
                raw_normal = Z_AXIS
                yaxis = raw_normal.cross(xaxis)
            end

            if yaxis.length < 0.001.mm
                raw_normal = X_AXIS
                yaxis = raw_normal.cross(xaxis)
            end

            yaxis.normalize!
            zaxis = xaxis.cross(yaxis)
            zaxis.normalize!

            to_world = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
            to_local = to_world.inverse

            {
                origin: origin,
                xaxis: xaxis,
                yaxis: yaxis,
                zaxis: zaxis,
                to_world: to_world,
                to_local: to_local
            }
        end
        # ------------------------------------------------------------

        # FUNCTION | Return First Valid Segment Vector
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__FindFirstSegmentVector(segments)
            segments.each do |start_point, end_point|
                vector = end_point - start_point
                return vector if vector.length > 0.001.mm
            end

            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Cross-Based Normal from Segment Cloud
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__FindNormalFromSegments(origin, xaxis, points)
            points.each do |point|
                vector = point - origin
                next if vector.length < 0.001.mm

                normal = xaxis.cross(vector)
                return normal if normal.length > 0.001.mm
            end

            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Fallback Normal from Camera and Axes
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__FallbackNormalFromCamera(xaxis)
            view_direction = Sketchup.active_model.active_view.camera.direction.reverse
            return view_direction if view_direction.cross(xaxis).length > 0.001.mm
            return Z_AXIS if Z_AXIS.cross(xaxis).length > 0.001.mm

            Y_AXIS
        end
        # ------------------------------------------------------------

        # FUNCTION | Validate Segment Coplanarity Against Working Plane
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__ValidateCoplanarSegments(segments, working_plane, tolerance)
            max_offset = 0.0

            segments.flatten.each do |point|
                local_point = point.transform(working_plane[:to_local])
                max_offset = [max_offset, local_point.z.abs].max
            end

            if max_offset > tolerance
                raise "Selected edges are not coplanar enough for one lattice plane. Maximum error: #{max_offset.to_mm.round(2)} mm."
            end

            true
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Lattice Footprint Builders
# -----------------------------------------------------------------------------

        # FUNCTION | Build Lattice Bar Data from Segments
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__CreateLatticeBarData(segments, working_plane, half_width)
            bars = []

            segments.each do |start_point, end_point|
                local_start = start_point.transform(working_plane[:to_local])
                local_end = end_point.transform(working_plane[:to_local])

                local_rectangle = self.Na__LatticeMaker__CreateSegmentRectangle2d(local_start, local_end, half_width)
                next unless local_rectangle

                world_rectangle = local_rectangle.map { |local_point| local_point.transform(working_plane[:to_world]) }

                bars << {
                    local_rectangle: local_rectangle,
                    world_rectangle: world_rectangle
                }
            end

            bars
        end
        # ------------------------------------------------------------

        # FUNCTION | Build Local 2D Rectangle Around Segment
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__CreateSegmentRectangle2d(local_start, local_end, half_width)
            dx = local_end.x - local_start.x
            dy = local_end.y - local_start.y
            length = Math.sqrt((dx * dx) + (dy * dy))
            return nil if length < 0.001.mm

            nx = -dy / length
            ny = dx / length

            [
                Geom::Point3d.new(local_start.x + (nx * half_width), local_start.y + (ny * half_width), 0),
                Geom::Point3d.new(local_end.x + (nx * half_width), local_end.y + (ny * half_width), 0),
                Geom::Point3d.new(local_end.x - (nx * half_width), local_end.y - (ny * half_width), 0),
                Geom::Point3d.new(local_start.x - (nx * half_width), local_start.y - (ny * half_width), 0)
            ]
        end
        # ------------------------------------------------------------

        # FUNCTION | Create Faces from Rectangle Point Collections
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__CreateRectangleFaces(entities, rectangles, normal)
            faces = []

            rectangles.each do |points|
                face = entities.add_face(points)
                face = entities.add_face(points.reverse) unless face
                next unless face

                face.reverse! if face.normal.dot(normal) < 0.0
                faces << face
            end

            faces
        end
        # ------------------------------------------------------------

        # FUNCTION | Build Prism Data Used for Internal Face Culling
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__CreateSolidPrismsFromBarData(lattice_bars, depth)
            min_z = [0.0, depth].min
            max_z = [0.0, depth].max

            lattice_bars.map do |bar_data|
                {
                    polygon: bar_data[:local_rectangle],
                    min_z: min_z,
                    max_z: max_z
                }
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__LatticeMaker__PlaneMath
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
