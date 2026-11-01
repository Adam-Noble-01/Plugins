# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR VIEWPORT - CAMERA SYNC
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprViewport__CameraSync__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__CameraSync
# PURPOSE    : SketchUp's camera as the NPR Viewport needs it: the eye and the
#              target in the engine's world, the field of view or the
#              orthographic height, and the shape of SketchUp's view, so the
#              painterly drawing looks from where the modelling view does.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - THE SAME AXES AS THE GLBS: SketchUp inches to the GLB builder's glTF metres
#   (x, z, -y), then the scene's placement (turn about +Y, then move), so the
#   eye stands where it does among the model's own files.
# - SketchUp's field of view is vertical unless fov_is_height? says otherwise;
#   a camera with its own aspect ratio (a scene's) keeps it. The host page
#   turns this into the engine's camera (yaw, pitch, distance, the field of
#   view fitted so the whole SketchUp view shows on the engine's sheet).
# - The camera is read, never written. Its eye and target do not change when a
#   group is opened, so the camera follows whatever context is open.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__CameraSync

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_INCH_M = 0.0254 unless defined?(NA_INCH_M)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | The View's Camera in the Engine's World
        # ------------------------------------------------------------
        # @param placement [Hash] the scene's NprScene__ModelPlacement ({} before a scene exists)
        # @return [Hash] { 'Mode', 'EyeM', 'TargetM', 'UpM', 'FovYDeg', 'HalfHeightM', 'Aspect' }
        def self.Na__Camera__Payload(view, placement)
            camera = view.camera
            aspect = camera.aspect_ratio.to_f > 0 ? camera.aspect_ratio.to_f : view.vpwidth.to_f / [view.vpheight.to_f, 1.0].max
            eye    = self.na_world(camera.eye, placement)
            target = self.na_world(camera.target, placement)
            up     = self.na_direction(camera.up, placement)
            if camera.perspective?
                fov  = camera.fov.to_f
                fovy = camera.fov_is_height? ? fov : 2.0 * Math.atan(Math.tan(fov * Math::PI / 360.0) / aspect) * 180.0 / Math::PI
                { 'Mode' => 'Perspective', 'EyeM' => eye, 'TargetM' => target, 'UpM' => up, 'FovYDeg' => fovy.round(4), 'HalfHeightM' => nil, 'Aspect' => aspect.round(5) }
            else
                height = camera.height.to_f
                height /= aspect unless camera.fov_is_height?                            # <-- A width-based camera keeps the width
                { 'Mode' => 'Ortho', 'EyeM' => eye, 'TargetM' => target, 'UpM' => up, 'FovYDeg' => nil, 'HalfHeightM' => (height * NA_INCH_M / 2.0).round(5), 'Aspect' => aspect.round(5) }
            end
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # A SketchUp point to the engine's world: inches to glTF metres, then the placement
        def self.na_world(point, placement)
            gltf = [point.x.to_f * NA_INCH_M, point.z.to_f * NA_INCH_M, -point.y.to_f * NA_INCH_M]
            Na__AssetProxies.Na__Proxies__Place(gltf, placement || {}).map { |v| v.round(5) }
        end

        # A direction turns with the placement but never moves
        def self.na_direction(vector, placement)
            gltf  = [vector.x.to_f, vector.z.to_f, -vector.y.to_f]
            angle = (placement && placement['RotationDeg']).to_f * Math::PI / 180.0
            c     = Math.cos(angle)
            s     = Math.sin(angle)
            [c * gltf[0] + s * gltf[2], gltf[1], -s * gltf[0] + c * gltf[2]].map { |v| v.round(6) }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
