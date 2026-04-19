# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - PROJECTION ENGINE
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__ProjectionEngine__.rb
# NAMESPACE  : Na__ToScaleOrthoTextureMaker::Na__ProjectionEngine
# MODULE     : Projection Engine
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Captures the active viewport to a temporary PNG at requested resolution
# CREATED    : 2026
#
# DESCRIPTION:
# - No geometry analysis, no selection, no visibility hacks.
# - Uses Sketchup::View#write_image so active Styles, Section Planes and Fog
#   are baked into the captured PNG with no extra work.
# - Supports two background modes:
#     :transparent (default) - PNG alpha channel preserves the checkerboard.
#     :white                 - Sky, ground and background colour are forced to
#                              solid white for the duration of the capture,
#                              then restored exactly.
# - Returns the temp file path for the caller to feed into the plane builder.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Apr-2026 - Version 2.0.0
# - Rewritten around Na__CameraFrame; removed face/container pipeline.
#
# 19-Apr-2026 - Version 2.2.0
# - Added background_mode argument with transparent and white options.
# - Added Na__Projection__ApplyWhiteBackground / Na__Projection__RestoreRenderingOptions
#   helpers that snapshot and restore the rendering options surrounding the capture.
#
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__ProjectionEngine

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_TEMP_IMAGE_PREFIX   = 'na_ortho_texture' unless const_defined?(:NA_TEMP_IMAGE_PREFIX)
        NA_DEFAULT_RESOLUTION  = 2048               unless const_defined?(:NA_DEFAULT_RESOLUTION)
        NA_IMAGE_COMPRESSION   = 0.9                unless const_defined?(:NA_IMAGE_COMPRESSION)
        NA_IMAGE_ANTIALIAS     = true               unless const_defined?(:NA_IMAGE_ANTIALIAS)
        NA_WHITE_COLOR_TUPLE   = [255, 255, 255]    unless const_defined?(:NA_WHITE_COLOR_TUPLE)
        NA_RENDERING_KEYS_TO_SNAPSHOT = %w[
            BackgroundColor
            SkyColor
            GroundColor
            DrawHorizon
            DrawGround
            DrawUnderground
        ].freeze unless const_defined?(:NA_RENDERING_KEYS_TO_SNAPSHOT)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture Pipeline
# -----------------------------------------------------------------------------

        # FUNCTION | Capture Viewport Image From Camera Frame
        # ------------------------------------------------------------
        def self.Na__Projection__CaptureViewportImage(camera_frame, requested_resolution = nil, background_mode = :transparent)
            view              = camera_frame[:view]                                     # Live view reference
            aspect            = camera_frame[:aspect].to_f                              # Viewport aspect ratio
            output_width      = self.Na__Projection__ResolveOutputWidth(requested_resolution)
            output_height     = self.Na__Projection__ResolveOutputHeight(output_width, aspect)
            temp_path         = self.Na__Projection__BuildTempImagePath                 # Unique temp PNG path
            use_transparent   = self.Na__Projection__IsTransparentMode(background_mode) # Boolean switch

            view.refresh                                                                # Flush camera prior to capture

            snapshot = nil                                                              # Rendering options snapshot
            begin
                snapshot = self.Na__Projection__ApplyWhiteBackground(view.model) unless use_transparent

                view.write_image(
                    filename:    temp_path,
                    width:       output_width,
                    height:      output_height,
                    antialias:   NA_IMAGE_ANTIALIAS,
                    transparent: use_transparent,
                    compression: NA_IMAGE_COMPRESSION
                )
            ensure
                self.Na__Projection__RestoreRenderingOptions(view.model, snapshot) if snapshot
            end

            {
                success:         true,
                image_path:      temp_path,
                output_width:    output_width,
                output_height:   output_height,
                background_mode: self.Na__Projection__NormaliseBackgroundMode(background_mode)
            }
        rescue => error
            {
                success: false,
                message: "Viewport capture failed: #{error.message}"
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Background Mode Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Normalise Raw Background Mode To Symbol
        # ------------------------------------------------------------
        def self.Na__Projection__NormaliseBackgroundMode(raw_value)
            return :white if raw_value.to_s.downcase == 'white'                         # <-- Accept string or symbol
            :transparent                                                                # Default matches legacy behaviour
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Is Transparent Background Mode
        # ------------------------------------------------------------
        def self.Na__Projection__IsTransparentMode(raw_value)
            self.Na__Projection__NormaliseBackgroundMode(raw_value) == :transparent
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | Apply White Background Override To Rendering Options
        # ------------------------------------------------------------
        def self.Na__Projection__ApplyWhiteBackground(model)
            snapshot = self.Na__Projection__SnapshotRenderingOptions(model)             # Snapshot current values
            options  = model.rendering_options                                          # Rendering options handle
            white    = Sketchup::Color.new(*NA_WHITE_COLOR_TUPLE)                       # Pure white colour

            options['BackgroundColor'] = white                                          # Force main background white
            options['SkyColor']        = white                                          # Force sky half white
            options['GroundColor']     = white                                          # Force ground half white
            options['DrawHorizon']     = false                                          # Disable sky gradient
            options['DrawGround']      = false                                          # Disable ground shading
            options['DrawUnderground'] = false                                          # Disable underground tint

            snapshot                                                                    # Return for restore
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Snapshot Current Rendering Option Values
        # ------------------------------------------------------------
        def self.Na__Projection__SnapshotRenderingOptions(model)
            snapshot = {}                                                               # Captured key/value map
            options  = model.rendering_options                                          # Rendering options handle

            NA_RENDERING_KEYS_TO_SNAPSHOT.each do |key|
                begin
                    snapshot[key] = options[key]                                        # <-- Store current value
                rescue
                    snapshot[key] = nil                                                 # <-- Silently skip unknown keys
                end
            end

            snapshot
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | Restore Rendering Options From Snapshot
        # ------------------------------------------------------------
        def self.Na__Projection__RestoreRenderingOptions(model, snapshot)
            return unless snapshot
            options = model.rendering_options                                           # Rendering options handle

            snapshot.each do |key, value|
                next if value.nil?                                                      # <-- Skip keys we could not read
                begin
                    options[key] = value                                                # Write value back
                rescue
                    # Silently ignore read-only keys on this SketchUp version
                end
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path And Size Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Output Width In Pixels
        # ------------------------------------------------------------
        def self.Na__Projection__ResolveOutputWidth(requested_resolution)
            value = requested_resolution.to_i                                           # Coerce to integer
            return NA_DEFAULT_RESOLUTION if value <= 0                                  # <-- Fallback to default
            value
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Output Height From Aspect
        # ------------------------------------------------------------
        def self.Na__Projection__ResolveOutputHeight(output_width, aspect)
            return output_width if aspect <= 0                                          # <-- Guard degenerate aspect
            (output_width.to_f / aspect).round                                          # Preserve viewport aspect
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Unique Temp Image Path
        # ------------------------------------------------------------
        def self.Na__Projection__BuildTempImagePath
            temp_root = ENV['TMP'] || ENV['TEMP'] || Dir.tmpdir                         # Windows/Unix safe temp root
            File.join(temp_root, "#{NA_TEMP_IMAGE_PREFIX}_#{Time.now.to_i}_#{rand(9999)}.png")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
