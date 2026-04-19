# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__Main__.rb
# NAMESPACE  : Na__ToScaleOrthoTextureMaker
# MODULE     : Main Orchestrator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Wires module dependencies and exposes public plugin API
# CREATED    : 2026
#
# DESCRIPTION:
# - Loads every plugin module and registers UI entry points.
# - Owns the public `Na__Projection__RunFromUi` pipeline:
#     CameraFrame -> ViewClassifier -> ProjectionEngine -> PlaneBuilder.
# - No selection, no face picking, no geometry analysis.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Apr-2026 - Version 2.0.0
# - Rewired around viewport-based ortho capture; removed SelectionResolver.
#
# =============================================================================

require 'sketchup.rb'

require_relative 'Na__ToScaleOrthoTextureMaker__MenuAndCommand__'
require_relative 'Na__ToScaleOrthoTextureMaker__HotkeyBinder__'
require_relative 'Na__ToScaleOrthoTextureMaker__DialogManager__'
require_relative 'Na__ToScaleOrthoTextureMaker__CameraFrame__'
require_relative 'Na__ToScaleOrthoTextureMaker__ViewClassifier__'
require_relative 'Na__ToScaleOrthoTextureMaker__ProjectionEngine__'
require_relative 'Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__'
require_relative 'Na__ToScaleOrthoTextureMaker__PlaneBuilder__'
require_relative 'Na__ToScaleOrthoTextureMaker__TextureExporter__'

module Na__ToScaleOrthoTextureMaker

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_PLUGIN_ROOT_PATH          = File.dirname(__FILE__) unless const_defined?(:NA_PLUGIN_ROOT_PATH)
    NA_INCHES_TO_MM              = 25.4                   unless const_defined?(:NA_INCHES_TO_MM)
    NA_HIGH_RESOLUTION_THRESHOLD = 4096                   unless const_defined?(:NA_HIGH_RESOLUTION_THRESHOLD)
    NA_RESOLUTION_HARD_CAP       = 8192                   unless const_defined?(:NA_RESOLUTION_HARD_CAP)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Bootstrap API
# -----------------------------------------------------------------------------

    # FUNCTION | Register Plugin UI
    # ------------------------------------------------------------
    def self.Na__Bootstrap__RegisterPluginUi
        Na__MenuAndCommand.Na__Ui__RegisterCommand                                      # Extensions menu entry
        Na__HotkeyBinder.Na__Hotkey__Register                                           # Keyboard accelerator
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show Main Dialog
    # ------------------------------------------------------------
    def self.Na__Ui__ShowMainDialog
        Na__DialogManager.Na__Ui__ShowDialog                                            # Open HtmlDialog UI
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Export Pipeline
# -----------------------------------------------------------------------------

    # FUNCTION | Run Texture Export From UI
    # ------------------------------------------------------------
    def self.Na__Export__RunFromUi(config_hash = {})
        model = Sketchup.active_model
        return { success: false, message: 'No active SketchUp model found.' } unless model

        Na__TextureExporter.Na__Export__ExportSelectedTexture(model, config_hash)
    rescue => error
        { success: false, message: "Export failed: #{error.message}" }
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Projection Pipeline
# -----------------------------------------------------------------------------

    # FUNCTION | Run Viewport Projection From UI
    # ------------------------------------------------------------
    def self.Na__Projection__RunFromUi(config_hash = {})
        model = Sketchup.active_model
        return { success: false, message: 'No active SketchUp model found.' } unless model

        scene_name           = config_hash['scene_name']                                # UI-selected scene or 'Current View'
        requested_resolution = self.Na__Projection__ClampResolution(config_hash['capture_resolution'])
        background_mode      = config_hash['background_mode']                           # 'transparent' (default) or 'white'

        begin
            model.start_operation('Na__Ortho__Projection', true)

            camera_frame = Na__CameraFrame.Na__Camera__ResolveFrame(model, scene_name)  # Resolve ortho camera frame
            Na__ToScaleOrthoTextureMaker.Na__Projection__AppendNonStandardWarning(camera_frame)
            Na__ToScaleOrthoTextureMaker.Na__Projection__AppendHighResolutionWarning(camera_frame, requested_resolution)

            capture_result = Na__ProjectionEngine.Na__Projection__CaptureViewportImage(
                camera_frame,
                requested_resolution,
                background_mode
            )

            unless capture_result[:success]
                model.abort_operation
                return capture_result
            end

            plane_result = Na__PlaneBuilder.Na__Plane__BuildViewportPlane(
                model:          model,
                camera_frame:   camera_frame,
                texture_path:   capture_result[:image_path],
                capture_result: capture_result
            )

            unless plane_result[:success]
                model.abort_operation
                return plane_result
            end

            model.commit_operation

            {
                success:  true,
                message:  self.Na__Projection__BuildSuccessMessage(plane_result, capture_result, camera_frame),
                warnings: camera_frame[:warnings],
                label:    plane_result[:label]
            }
        rescue => error
            model.abort_operation
            { success: false, message: "Projection failed: #{error.message}" }
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Append Non-Standard Plane Warning To Frame
    # ------------------------------------------------------------
    def self.Na__Projection__AppendNonStandardWarning(camera_frame)
        return if camera_frame[:scene_page]                                             # <-- Skip if user chose a named scene
        return if Na__ViewClassifier.Na__View__IsStandardPlane(camera_frame[:direction])
        camera_frame[:warnings] << 'Camera is not aligned to a standard ortho plane; captured as CustomView.'
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Append High-Resolution Warning To Frame
    # ------------------------------------------------------------
    def self.Na__Projection__AppendHighResolutionWarning(camera_frame, requested_resolution)
        return if requested_resolution.to_i <= NA_HIGH_RESOLUTION_THRESHOLD              # <-- Only warn above threshold
        camera_frame[:warnings] << "High-resolution capture (#{requested_resolution}px) can fail on low GPU memory; try 4096 if this crashes."
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Clamp Requested Resolution To Safe Range
    # ------------------------------------------------------------
    def self.Na__Projection__ClampResolution(raw_value)
        value = raw_value.to_i                                                          # Coerce to integer
        return 2048 if value <= 0                                                       # <-- Default when missing
        return NA_RESOLUTION_HARD_CAP if value > NA_RESOLUTION_HARD_CAP                 # <-- Hard cap at 8192
        value
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Build Success Message For Dialog Status
    # ------------------------------------------------------------
    def self.Na__Projection__BuildSuccessMessage(plane_result, capture_result, camera_frame)
        width_mm  = camera_frame[:width_world]  * NA_INCHES_TO_MM                       # Convert inches -> mm
        height_mm = camera_frame[:height_world] * NA_INCHES_TO_MM                       # Convert inches -> mm

        pixel_text  = "#{capture_result[:output_width]}x#{capture_result[:output_height]} px"
        scale_text  = "#{format('%.1f', width_mm)}mm x #{format('%.1f', height_mm)}mm"

        "Captured #{plane_result[:label]} (#{pixel_text}, true-scale #{scale_text})."
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
