# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - CAMERA FRAME RESOLVER
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__CameraFrame__.rb
# NAMESPACE  : Na__ToScaleOrthoTextureMaker::Na__CameraFrame
# MODULE     : Camera Frame Resolver
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Resolves a deterministic ortho camera frame for viewport capture
# CREATED    : 2026
#
# DESCRIPTION:
# - Applies a chosen scene camera to the active view or keeps the current view.
# - Forces Parallel Projection on the active camera (auto ortho conversion).
# - Returns an immutable frame hash containing eye, target, up, right,
#   direction, world-space height / width, viewport aspect and pixel size.
# - Produces human-readable warnings when the caller asked for Current View
#   but the camera state needed modification to become a valid ortho frame.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Apr-2026 - Version 2.0.0
# - Initial release as part of viewport-based capture rewrite.
#
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__CameraFrame

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve Camera Frame For Capture
        # ------------------------------------------------------------
        def self.Na__Camera__ResolveFrame(model, scene_name)
            view = model.active_view                                                    # <-- Active view reference
            warnings = []                                                               # <-- Non-blocking warnings for UI

            scene_page = self.Na__Camera__FindSceneByName(model, scene_name)            # Resolve requested scene page
            if scene_page
                view.camera = scene_page.camera                                         # Apply scene camera to view
                view.refresh                                                            # Ensure camera state is live
            end

            if view.camera.perspective?                                                 # Detect perspective state
                warnings << 'Camera was in Perspective; switched to Parallel Projection.' unless scene_page
                self.Na__Camera__ForceParallelProjection(view)                          # Convert to ortho in place
            end

            self.Na__Camera__BuildFrameFromView(view, scene_page, warnings)             # Return immutable frame
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scene Lookup
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Find Scene By Name
        # ------------------------------------------------------------
        def self.Na__Camera__FindSceneByName(model, scene_name)
            return nil unless model                                                     # <-- Guard nil model
            return nil if scene_name.nil?                                               # <-- Guard nil name
            return nil if scene_name.to_s.strip.empty?                                  # <-- Guard blank name
            return nil if scene_name == 'Current View'                                  # <-- Current view sentinel
            return nil unless model.pages                                               # <-- Guard nil pages collection

            model.pages.find { |page| page.name == scene_name }                         # Exact-name scene lookup
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Parallel Projection Enforcement
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Force Parallel Projection On Active View
        # ------------------------------------------------------------
        def self.Na__Camera__ForceParallelProjection(view)
            source_camera = view.camera                                                 # Current camera snapshot
            eye            = source_camera.eye                                          # Camera position
            target         = source_camera.target                                       # Look-at point
            up             = source_camera.up                                           # Up vector

            ortho_height = self.Na__Camera__ComputeOrthoHeightFromPerspective(          # Derive ortho height
                source_camera,
                view
            )

            new_camera = Sketchup::Camera.new(eye, target, up)                          # Replacement ortho camera
            new_camera.perspective = false                                              # Ortho flag
            new_camera.height      = ortho_height if ortho_height > 0                   # Preserve framing size
            view.camera            = new_camera                                         # Apply to view
            view.refresh                                                                # Flush camera change
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compute Ortho Height From Perspective Camera
        # ------------------------------------------------------------
        def self.Na__Camera__ComputeOrthoHeightFromPerspective(camera, view)
            distance = camera.eye.distance(camera.target).to_f                          # Eye-to-target distance
            return 0.0 if distance <= 0                                                 # Bail on degenerate camera

            fov_degrees = camera.fov.to_f                                               # Field of view in degrees
            fov_radians = fov_degrees * Math::PI / 180.0                                # Convert to radians

            if camera.fov_is_height?                                                    # Vertical FOV case
                return 2.0 * distance * Math.tan(fov_radians / 2.0)                     # Height at target plane
            end

            horizontal_extent = 2.0 * distance * Math.tan(fov_radians / 2.0)            # Horizontal extent
            aspect = self.Na__Camera__ResolveAspect(view)                               # Viewport aspect ratio
            horizontal_extent / aspect                                                  # Convert to height
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Viewport Aspect Ratio
        # ------------------------------------------------------------
        def self.Na__Camera__ResolveAspect(view)
            vp_w = view.vpwidth.to_f                                                    # Viewport pixel width
            vp_h = view.vpheight.to_f                                                   # Viewport pixel height
            return 1.0 if vp_h <= 0                                                     # <-- Guard divide by zero
            vp_w / vp_h                                                                 # Standard aspect
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Frame Hash From Current View
        # ------------------------------------------------------------
        def self.Na__Camera__BuildFrameFromView(view, scene_page, warnings)
            camera = view.camera                                                        # Post-conversion camera
            aspect = self.Na__Camera__ResolveAspect(view)                               # Viewport aspect ratio

            eye       = camera.eye                                                      # Camera eye point
            target    = camera.target                                                   # Camera target point
            up        = camera.up.normalize                                             # Normalised up vector
            direction = camera.direction.normalize                                      # Normalised view direction
            right     = (direction * up).normalize                                      # Right vector via cross

            height_world = camera.height.to_f                                           # Ortho frustum height
            width_world  = height_world * aspect                                        # Ortho frustum width

            {
                view:          view,                                                    # <-- Live view reference
                scene_page:    scene_page,                                              # <-- Source scene page or nil
                scene_name:    scene_page ? scene_page.name : 'Current View',           # <-- Display name
                eye:           eye,                                                     # <-- Camera eye
                target:        target,                                                  # <-- Camera target
                up:            up,                                                      # <-- Unit up vector
                right:         right,                                                   # <-- Unit right vector
                direction:     direction,                                               # <-- Unit view direction
                height_world:  height_world,                                            # <-- World-space frame height
                width_world:   width_world,                                             # <-- World-space frame width
                aspect:        aspect,                                                  # <-- Viewport aspect ratio
                vp_width:      view.vpwidth.to_f,                                       # <-- Viewport width in pixels
                vp_height:     view.vpheight.to_f,                                      # <-- Viewport height in pixels
                warnings:      warnings                                                 # <-- Non-blocking warnings
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
