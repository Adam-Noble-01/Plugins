# =============================================================================
# NA NOBLE3D MODELLING TOOLS - ORTHO MIRROR TOOL - HELPERS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__OrthoMirrorTool__Helpers__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__OrthoMirrorTool
# PURPOSE    : Module-level helper functions for the Ortho Mirror Tool
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__OrthoMirrorTool

# -----------------------------------------------------------------------------
# REGION | Axis Locking Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Get Axis Vector for Lock State
        # ------------------------------------------------------------
        def self.get_axis_vector(lock_state)
            case lock_state
            when LOCK_X then X_AXIS                                      # <-- Return X axis vector
            when LOCK_Y then Y_AXIS                                      # <-- Return Y axis vector
            when LOCK_Z then Z_AXIS                                      # <-- Return Z axis vector
            else nil                                                     # <-- No lock, return nil
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Get World-Space Axis Direction for the Active Drawing Context
        # ------------------------------------------------------------
        # Maps the local axis (X/Y/Z) of the active edit context into world space.
        # At the top level edit_transform is identity, so this returns the global
        # axis. Inside a group/component it returns the group's local axis expressed
        # in world coordinates, so the arrow-key lock follows "where the axis is set".
        # ------------------------------------------------------------
        def self.world_axis_for_lock(lock_state, edit_transform)
            base_axis = get_axis_vector(lock_state)                      # <-- Local X/Y/Z (or nil)
            return nil unless base_axis                                  # <-- No lock, no axis
            return base_axis.clone unless edit_transform                 # <-- No context, use global axis

            world_axis = base_axis.transform(edit_transform)             # <-- Direction of local axis in world space
            return base_axis.clone if world_axis.length < 1.0e-9         # <-- Degenerate transform fallback
            world_axis.normalize                                         # <-- Return unit world direction
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Get Axis Color for Lock State
        # ------------------------------------------------------------
        def self.get_axis_color(lock_state)
            case lock_state
            when LOCK_X then AXIS_COLOR_X                                # <-- Return red for X
            when LOCK_Y then AXIS_COLOR_Y                                # <-- Return green for Y
            when LOCK_Z then AXIS_COLOR_Z                                # <-- Return blue for Z
            else PREVIEW_LINE_COLOR                                      # <-- Default blue preview color
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Get Axis Name for Lock State
        # ------------------------------------------------------------
        def self.get_axis_name(lock_state)
            case lock_state
            when LOCK_X then "Red (X)"                                   # <-- Red axis name
            when LOCK_Y then "Green (Y)"                                 # <-- Green axis name
            when LOCK_Z then "Blue (Z)"                                  # <-- Blue axis name
            else "None"                                                  # <-- No lock
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Constrain Point to Axis from Origin Point
        # ------------------------------------------------------------
        # Projects the target point onto the line from origin along axis_vector.
        # Returns the constrained point.
        # ------------------------------------------------------------
        def self.constrain_point_to_axis(origin, target, axis_vector)
            return target unless axis_vector                             # <-- Return original if no axis
            direction    = target - origin                               # <-- Vector from origin to target
            dot_product  = direction.dot(axis_vector)                   # <-- Project onto axis
            origin.offset(axis_vector, dot_product)                     # <-- Constrained point along axis
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | View Detection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check if Camera is in Parallel Projection
        # ------------------------------------------------------------
        def self.is_parallel_projection?(view)
            !view.camera.perspective?                                    # <-- True if parallel (ortho) mode
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Get Camera View Direction Vector
        # ------------------------------------------------------------
        # Returns the direction the camera is looking (from eye to target).
        # This is the opposite of the view plane normal.
        # ------------------------------------------------------------
        def self.get_camera_view_direction(view)
            camera    = view.camera                                      # <-- Get camera object
            direction = camera.target - camera.eye                      # <-- Calculate view direction
            direction.normalize                                          # <-- Return normalized vector
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Identify Named Ortho View
        # ------------------------------------------------------------
        # Returns symbol: :top, :bottom, :front, :back, :left, :right, or :custom
        # ------------------------------------------------------------
        def self.identify_ortho_view(view)
            return :perspective if view.camera.perspective?              # <-- Not ortho if perspective mode

            direction = get_camera_view_direction(view)                  # <-- Get view direction

            if direction.parallel?(Z_AXIS)                               # <-- Looking along Z axis
                direction.z > 0 ? :bottom : :top
            elsif direction.parallel?(Y_AXIS)                            # <-- Looking along Y axis
                direction.y > 0 ? :front : :back
            elsif direction.parallel?(X_AXIS)                            # <-- Looking along X axis
                direction.x > 0 ? :left : :right
            else
                :custom
            end
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Point Type Detection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Calculate Edge Midpoint
        # ------------------------------------------------------------
        def self.calculate_edge_midpoint(edge)
            start_pt = edge.start.position                               # <-- Get start vertex position
            end_pt   = edge.end.position                                 # <-- Get end vertex position
            Geom::Point3d.linear_combination(0.5, start_pt, 0.5, end_pt)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Check if Point is Near Edge Midpoint
        # ------------------------------------------------------------
        def self.is_near_midpoint?(point, edge, tolerance = 0.001)
            midpoint = calculate_edge_midpoint(edge)
            point.distance(midpoint) < tolerance
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Detect Point Type from InputPoint
        # ------------------------------------------------------------
        # Returns: :vertex, :midpoint, :edge, :face, or :free
        # ------------------------------------------------------------
        def self.detect_point_type(ip)
            return :free unless ip.valid?                                # <-- Return free if no valid snap

            return :vertex   if ip.vertex                                # <-- Vertex snap (highest priority)

            if ip.edge                                                   # <-- Edge snap
                return is_near_midpoint?(ip.position, ip.edge) ? :midpoint : :edge
            end

            return :face if ip.face                                      # <-- Face snap

            :free
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Mirror Geometry Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Calculate Mirror Plane Normal
        # ------------------------------------------------------------
        # The mirror plane contains the mirror line and is perpendicular to the view.
        # Normal = cross product of mirror_line and view_direction.
        # All vectors must be supplied in the SAME coordinate space (the caller works
        # in the active edit-context's local space so the result applies cleanly to
        # geometry inside groups/components).
        # ------------------------------------------------------------
        def self.calculate_mirror_plane_normal(start_point, end_point, view_direction)
            mirror_line = end_point - start_point                        # <-- Vector along mirror axis
            return nil if mirror_line.length < 0.001                    # <-- Degenerate case
            return nil if view_direction.nil?
            return nil if view_direction.length < 1.0e-9

            plane_normal = mirror_line.cross(view_direction)             # <-- Cross product gives plane normal
            return nil if plane_normal.length < 0.001                   # <-- Mirror line parallel to view

            plane_normal.normalize
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Mirror Transformation Matrix
        # ------------------------------------------------------------
        # Creates a reflection transformation about an arbitrary plane.
        # The plane passes through midpoint with the given normal.
        # ------------------------------------------------------------
        def self.build_mirror_transform(midpoint, plane_normal)
            nx = plane_normal.x
            ny = plane_normal.y
            nz = plane_normal.z

            d   = midpoint.x * nx + midpoint.y * ny + midpoint.z * nz   # <-- Plane constant d

            m11 = 1.0 - 2.0 * nx * nx
            m12 = -2.0 * nx * ny
            m13 = -2.0 * nx * nz
            m14 = 2.0 * nx * d

            m21 = -2.0 * ny * nx
            m22 = 1.0 - 2.0 * ny * ny
            m23 = -2.0 * ny * nz
            m24 = 2.0 * ny * d

            m31 = -2.0 * nz * nx
            m32 = -2.0 * nz * ny
            m33 = 1.0 - 2.0 * nz * nz
            m34 = 2.0 * nz * d

            # SketchUp column-major 4x4 array
            matrix_array = [
                m11, m21, m31, 0.0,
                m12, m22, m32, 0.0,
                m13, m23, m33, 0.0,
                m14, m24, m34, 1.0
            ]

            Geom::Transformation.new(matrix_array)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__OrthoMirrorTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
