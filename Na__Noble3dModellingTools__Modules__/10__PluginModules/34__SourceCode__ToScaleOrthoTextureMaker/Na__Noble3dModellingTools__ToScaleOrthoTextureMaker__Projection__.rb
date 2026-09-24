# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - PROJECTION
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__Projection__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__Projection
# PURPOSE    : Run the viewport capture pipeline inside one undo operation
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__Projection

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'To Scale Ortho Texture Maker'.freeze unless const_defined?(:NA_OPERATION_NAME)
        NA_INCHES_TO_MM = 25.4 unless const_defined?(:NA_INCHES_TO_MM)
        NA_HIGH_RESOLUTION_THRESHOLD = 4096 unless const_defined?(:NA_HIGH_RESOLUTION_THRESHOLD)
        NA_RESOLUTION_HARD_CAP = 8192 unless const_defined?(:NA_RESOLUTION_HARD_CAP)
        NA_DEFAULT_RESOLUTION = 2048 unless const_defined?(:NA_DEFAULT_RESOLUTION)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Capture the Viewport and Build the Textured Plane
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__Projection__Run(config_hash = {})
            model = Sketchup.active_model
            return { success: false, message: 'No active SketchUp model found.' } unless model

            scene_name = config_hash['scene_name']
            requested_resolution = na_clamp_resolution(config_hash['capture_resolution'])
            background_mode = config_hash['background_mode']
            operation_started = false

            model.start_operation(NA_OPERATION_NAME, true)
            operation_started = true

            camera_frame = Na__ToScaleOrthoTextureMaker__CameraFrame.Na__ToScaleOrthoTextureMaker__CameraFrame__ResolveFrame(model, scene_name)
            na_append_non_standard_warning(camera_frame)
            na_append_high_resolution_warning(camera_frame, requested_resolution)

            capture_result = Na__ToScaleOrthoTextureMaker__ProjectionEngine.Na__ToScaleOrthoTextureMaker__ProjectionEngine__CaptureViewportImage(
                camera_frame,
                requested_resolution,
                background_mode
            )
            unless capture_result[:success]
                model.abort_operation
                return capture_result
            end

            plane_result = Na__ToScaleOrthoTextureMaker__PlaneBuilder.Na__ToScaleOrthoTextureMaker__PlaneBuilder__BuildViewportPlane(
                model: model,
                camera_frame: camera_frame,
                texture_path: capture_result[:image_path],
                capture_result: capture_result
            )
            unless plane_result[:success]
                model.abort_operation
                return plane_result
            end

            model.commit_operation
            {
                success: true,
                message: na_success_message(plane_result, capture_result, camera_frame),
                warnings: camera_frame[:warnings],
                label: plane_result[:label]
            }
        rescue StandardError => error
            model.abort_operation if model && operation_started
            { success: false, message: "Projection failed: #{error.message}" }
        end
        # ------------------------------------------------------------

        # FUNCTION | Export the Baked Texture from a Capture Group
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__Projection__Export(config_hash = {})
            model = Sketchup.active_model
            return { success: false, message: 'No active SketchUp model found.' } unless model

            Na__ToScaleOrthoTextureMaker__TextureExporter.Na__ToScaleOrthoTextureMaker__TextureExporter__ExportSelected(model, config_hash)
        rescue StandardError => error
            { success: false, message: "Export failed: #{error.message}" }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Warnings and Messages
# -----------------------------------------------------------------------------

        def self.na_append_non_standard_warning(camera_frame)
            return if camera_frame[:scene_page]
            return if Na__ToScaleOrthoTextureMaker__ViewClassifier.Na__ToScaleOrthoTextureMaker__ViewClassifier__IsStandardPlane(camera_frame[:direction])

            camera_frame[:warnings] << 'Camera is not aligned to a standard ortho plane; captured as CustomView.'
        end

        def self.na_append_high_resolution_warning(camera_frame, requested_resolution)
            return if requested_resolution.to_i <= NA_HIGH_RESOLUTION_THRESHOLD

            camera_frame[:warnings] << "High-resolution capture (#{requested_resolution}px) can fail on low GPU memory; try 4096 if this crashes."
        end

        def self.na_clamp_resolution(raw_value)
            value = raw_value.to_i
            return NA_DEFAULT_RESOLUTION if value <= 0
            return NA_RESOLUTION_HARD_CAP if value > NA_RESOLUTION_HARD_CAP

            value
        end

        def self.na_success_message(plane_result, capture_result, camera_frame)
            width_mm = camera_frame[:width_world] * NA_INCHES_TO_MM
            height_mm = camera_frame[:height_world] * NA_INCHES_TO_MM
            pixel_text = "#{capture_result[:output_width]}x#{capture_result[:output_height]} px"
            scale_text = "#{format('%.1f', width_mm)}mm x #{format('%.1f', height_mm)}mm"
            "Captured #{plane_result[:label]} (#{pixel_text}, true-scale #{scale_text})."
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__Projection
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
