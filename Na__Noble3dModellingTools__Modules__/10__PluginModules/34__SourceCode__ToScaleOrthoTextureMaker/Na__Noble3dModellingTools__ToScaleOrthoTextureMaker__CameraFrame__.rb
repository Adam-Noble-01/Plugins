# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - CAMERA FRAME
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__CameraFrame__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__CameraFrame
# PURPOSE    : Resolve a parallel-projection camera frame for viewport capture
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__CameraFrame

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_CURRENT_VIEW_LABEL = 'Current View'.freeze unless const_defined?(:NA_CURRENT_VIEW_LABEL)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve the Ortho Camera Frame for a Scene or the Current View
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__CameraFrame__ResolveFrame(model, scene_name)
            view = model.active_view
            warnings = []
            scene_page = na_find_scene_by_name(model, scene_name)

            if scene_page
                view.camera = scene_page.camera
                view.refresh
            end

            if view.camera.perspective?
                warnings << 'Camera was in Perspective; switched to Parallel Projection.' unless scene_page
                na_force_parallel_projection(view)
            end

            na_build_frame_from_view(view, scene_page, warnings)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scene Lookup
# -----------------------------------------------------------------------------

        def self.na_find_scene_by_name(model, scene_name)
            return nil unless model
            return nil if scene_name.nil?
            return nil if scene_name.to_s.strip.empty?
            return nil if scene_name == NA_CURRENT_VIEW_LABEL
            return nil unless model.pages

            model.pages.find { |page| page.name == scene_name }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Parallel Projection
# -----------------------------------------------------------------------------

        def self.na_force_parallel_projection(view)
            source_camera = view.camera
            ortho_height = na_ortho_height_from_perspective(source_camera, view)
            new_camera = Sketchup::Camera.new(source_camera.eye, source_camera.target, source_camera.up)
            new_camera.perspective = false
            new_camera.height = ortho_height if ortho_height > 0
            view.camera = new_camera
            view.refresh
        end

        def self.na_ortho_height_from_perspective(camera, view)
            distance = camera.eye.distance(camera.target).to_f
            return 0.0 if distance <= 0

            fov_radians = camera.fov.to_f * Math::PI / 180.0
            return 2.0 * distance * Math.tan(fov_radians / 2.0) if camera.fov_is_height?

            horizontal_extent = 2.0 * distance * Math.tan(fov_radians / 2.0)
            horizontal_extent / na_viewport_aspect(view)
        end

        def self.na_viewport_aspect(view)
            viewport_height = view.vpheight.to_f
            return 1.0 if viewport_height <= 0

            view.vpwidth.to_f / viewport_height
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Construction
# -----------------------------------------------------------------------------

        def self.na_build_frame_from_view(view, scene_page, warnings)
            camera = view.camera
            aspect = na_viewport_aspect(view)
            direction = camera.direction.normalize
            up = camera.up.normalize
            height_world = camera.height.to_f

            {
                view: view,
                scene_page: scene_page,
                scene_name: scene_page ? scene_page.name : NA_CURRENT_VIEW_LABEL,
                eye: camera.eye,
                target: camera.target,
                up: up,
                right: (direction * up).normalize,
                direction: direction,
                height_world: height_world,
                width_world: height_world * aspect,
                aspect: aspect,
                vp_width: view.vpwidth.to_f,
                vp_height: view.vpheight.to_f,
                warnings: warnings
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__CameraFrame
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
