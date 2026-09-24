# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - PROJECTION ENGINE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__ProjectionEngine__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__ProjectionEngine
# PURPOSE    : Capture the active viewport to a temporary PNG
# CREATED    : 2026
#
# =============================================================================

require 'tmpdir'

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__ProjectionEngine

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_TEMP_IMAGE_PREFIX = 'na_ortho_texture'.freeze unless const_defined?(:NA_TEMP_IMAGE_PREFIX)
        NA_DEFAULT_RESOLUTION = 2048 unless const_defined?(:NA_DEFAULT_RESOLUTION)
        NA_IMAGE_COMPRESSION = 0.9 unless const_defined?(:NA_IMAGE_COMPRESSION)
        NA_IMAGE_ANTIALIAS = true unless const_defined?(:NA_IMAGE_ANTIALIAS)
        NA_WHITE_COLOR_TUPLE = [255, 255, 255].freeze unless const_defined?(:NA_WHITE_COLOR_TUPLE)
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
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Write the Current Viewport to a Temporary PNG
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__ProjectionEngine__CaptureViewportImage(camera_frame, requested_resolution = nil, background_mode = :transparent)
            view = camera_frame[:view]
            output_width = na_output_width(requested_resolution)
            output_height = na_output_height(output_width, camera_frame[:aspect].to_f)
            temp_path = na_temp_image_path
            use_transparent = na_transparent_mode?(background_mode)
            snapshot = nil

            view.refresh
            begin
                snapshot = na_apply_white_background(view.model) unless use_transparent
                view.write_image(
                    filename: temp_path,
                    width: output_width,
                    height: output_height,
                    antialias: NA_IMAGE_ANTIALIAS,
                    transparent: use_transparent,
                    compression: NA_IMAGE_COMPRESSION
                )
            ensure
                na_restore_rendering_options(view.model, snapshot) if snapshot
            end

            {
                success: true,
                image_path: temp_path,
                output_width: output_width,
                output_height: output_height,
                background_mode: na_normalise_background_mode(background_mode)
            }
        rescue StandardError => error
            { success: false, message: "Viewport capture failed: #{error.message}" }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Background Mode
# -----------------------------------------------------------------------------

        def self.na_normalise_background_mode(raw_value)
            return :white if raw_value.to_s.downcase == 'white'

            :transparent
        end

        def self.na_transparent_mode?(raw_value)
            na_normalise_background_mode(raw_value) == :transparent
        end

        def self.na_apply_white_background(model)
            snapshot = na_snapshot_rendering_options(model)
            options = model.rendering_options
            white = Sketchup::Color.new(*NA_WHITE_COLOR_TUPLE)
            options['BackgroundColor'] = white
            options['SkyColor'] = white
            options['GroundColor'] = white
            options['DrawHorizon'] = false
            options['DrawGround'] = false
            options['DrawUnderground'] = false
            snapshot
        end

        def self.na_snapshot_rendering_options(model)
            options = model.rendering_options
            NA_RENDERING_KEYS_TO_SNAPSHOT.each_with_object({}) do |key, snapshot|
                snapshot[key] = options[key]
            rescue StandardError
                snapshot[key] = nil
            end
        end

        def self.na_restore_rendering_options(model, snapshot)
            return unless snapshot

            options = model.rendering_options
            snapshot.each do |key, value|
                next if value.nil?

                options[key] = value
            rescue StandardError
                nil
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Size and Path
# -----------------------------------------------------------------------------

        def self.na_output_width(requested_resolution)
            value = requested_resolution.to_i
            return NA_DEFAULT_RESOLUTION if value <= 0

            value
        end

        def self.na_output_height(output_width, aspect)
            return output_width if aspect <= 0

            (output_width.to_f / aspect).round
        end

        def self.na_temp_image_path
            temp_root = ENV['TMP'] || ENV['TEMP'] || Dir.tmpdir
            File.join(temp_root, "#{NA_TEMP_IMAGE_PREFIX}_#{Time.now.to_i}_#{rand(9999)}.png")
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__ProjectionEngine
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
