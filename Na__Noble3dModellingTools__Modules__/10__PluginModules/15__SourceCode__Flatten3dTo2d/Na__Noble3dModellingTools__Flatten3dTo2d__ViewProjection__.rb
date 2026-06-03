# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FLATTEN 3D TO 2D - VIEW PROJECTION
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Flatten3dTo2d__ViewProjection__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__Flatten3dTo2d
# PURPOSE    : Camera/view maths for orthographic flattening onto a front plane
# CREATED    : 2026
#
# DESCRIPTION:
# - Reports whether the active camera is in Parallel Projection.
# - Provides the world view direction and converts it into the active edit
#   context's local space (so projection is correct inside nested containers).
# - Computes the front-most plane value (closest to camera) and projects points
#   onto that plane along the view normal.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__Flatten3dTo2d

# -----------------------------------------------------------------------------
# REGION | View / Camera Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check if Camera is in Parallel Projection
        # ------------------------------------------------------------
        def self.na_parallel_projection?(view)
            return false unless view && view.camera                      # <-- Guard missing view/camera
            !view.camera.perspective?                                    # <-- True when in Parallel Projection (ortho)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Get World-Space Camera View Direction (eye -> target)
        # ------------------------------------------------------------
        def self.na_world_view_direction(view)
            camera    = view.camera                                      # <-- Active camera
            direction = camera.target - camera.eye                       # <-- Looking direction in world space
            return Z_AXIS.clone if direction.length < 1.0e-9             # <-- Degenerate fallback
            direction.normalize                                          # <-- Unit world view direction
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Coordinate Space Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert a World Point Into the Active Edit Context
        # ------------------------------------------------------------
        # The whole pipeline works in world space (so model.raytest occlusion and
        # the camera direction line up). Geometry is created in model.active_entities,
        # whose local space is the active edit context, so each finished world point
        # is mapped back through edit_transform.inverse just before it is added. At
        # the top level edit_transform is identity, so this is a no-op.
        # ------------------------------------------------------------
        def self.na_to_local(world_point, edit_inverse)
            return world_point unless edit_inverse                        # <-- Top-level: world == context
            world_point.transform(edit_inverse)                           # <-- World -> active context space
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plane / Projection Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Minimum Projection Scalar Along the View Normal
        # ------------------------------------------------------------
        # The smallest dot product is the front-most extent (closest to camera).
        # ------------------------------------------------------------
        def self.na_min_projection(points, view_normal)
            min_value = nil
            points.each do |point|
                value     = (point.x * view_normal.x) + (point.y * view_normal.y) + (point.z * view_normal.z)
                min_value = value if min_value.nil? || value < min_value
            end
            min_value
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Project a Point onto the Front Plane
        # ------------------------------------------------------------
        # plane_value is the target dot-product along the unit view normal. The
        # point is shifted along the normal so it lands exactly on that plane.
        # ------------------------------------------------------------
        def self.na_project_point(point, plane_value, view_normal)
            current  = (point.x * view_normal.x) + (point.y * view_normal.y) + (point.z * view_normal.z)
            distance = current - plane_value                              # <-- Signed distance from front plane
            Geom::Point3d.new(
                point.x - (distance * view_normal.x),
                point.y - (distance * view_normal.y),
                point.z - (distance * view_normal.z)
            )
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__Flatten3dTo2d
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
