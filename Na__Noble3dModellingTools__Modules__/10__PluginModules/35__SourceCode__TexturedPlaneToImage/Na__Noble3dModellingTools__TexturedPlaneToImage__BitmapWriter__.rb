# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TEXTURED PLANE TO IMAGE - BITMAP WRITER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__TexturedPlaneToImage__BitmapWriter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__TexturedPlaneToImage__BitmapWriter
# PURPOSE    : Write the texture pixels that the rectangular face actually shows
# CREATED    : 2026
#
# =============================================================================

require 'tmpdir'

module Na__Noble3dModellingTools
    module Na__TexturedPlaneToImage__BitmapWriter

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PIXEL_CAP = 8192 unless const_defined?(:NA_PIXEL_CAP)
        NA_FULL_BLEED_TOLERANCE = 0.001 unless const_defined?(:NA_FULL_BLEED_TOLERANCE)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Write a PNG of the Texture Region Shown on the Face
        # ------------------------------------------------------------
        def self.Na__TexturedPlaneToImage__BitmapWriter__Write(texture, corner_uvs)
            source = texture.image_rep
            return { success: false, message: 'The material texture has no pixel data.' } unless source

            width, height = na_output_size(source, corner_uvs)
            path = na_temp_png_path
            if na_full_bleed?(corner_uvs)
                source.save_file(path)
            elsif na_write_native_png(source, corner_uvs, width, height, path)
                nil
            else
                na_write_sampled_png(source, corner_uvs, width, height, path)
            end
            { success: true, path: path, pixel_width: width, pixel_height: height }
        rescue StandardError => error
            { success: false, message: "Could not write the image file: #{error.message}" }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Sampling
# -----------------------------------------------------------------------------

        def self.na_output_size(source, corner_uvs)
            across = na_uv_span(corner_uvs[0], corner_uvs[1])
            up = na_uv_span(corner_uvs[0], corner_uvs[3])
            width = (Math.hypot(across.x * source.width, across.y * source.height)).round
            height = (Math.hypot(up.x * source.width, up.y * source.height)).round
            [[width, 1].max, [height, 1].max].map { |value| [value, NA_PIXEL_CAP].min }
        end

        def self.na_uv_span(start_uv, end_uv)
            Geom::Vector3d.new(end_uv.x - start_uv.x, end_uv.y - start_uv.y, 0)
        end

        def self.na_full_bleed?(corner_uvs)
            expected = [
                Geom::Point3d.new(0, 0, 0),
                Geom::Point3d.new(1, 0, 0),
                Geom::Point3d.new(1, 1, 0),
                Geom::Point3d.new(0, 1, 0)
            ]
            corner_uvs.zip(expected).all? do |actual, target|
                (actual.x - target.x).abs < NA_FULL_BLEED_TOLERANCE &&
                    (actual.y - target.y).abs < NA_FULL_BLEED_TOLERANCE
            end
        end

        def self.na_write_native_png(source, corner_uvs, width, height, path)
            return false unless Na__TexturedPlaneToImage__NativeBridge.na_available?
            return false unless source.respond_to?(:data) && source.data

            pixel_bytes = Na__TexturedPlaneToImage__NativeBridge.Na__TexturedPlaneToImage__NativeBridge__Sample(
                source,
                corner_uvs,
                width,
                height
            )
            return false unless pixel_bytes

            image_rep = Sketchup::ImageRep.new
            image_rep.set_data(width, height, 32, 0, pixel_bytes)
            image_rep.save_file(path)
            true
        rescue StandardError => error
            puts "[Na__TexturedPlaneToImage] Native sampler failed, using Ruby: #{error.class}: #{error.message}"
            false
        end

        def self.na_write_sampled_png(source, corner_uvs, width, height, path)
            bytes = []
            height.times do |row_from_top|
                y_fraction = height == 1 ? 0.0 : (height - 1 - row_from_top).to_f / (height - 1)
                width.times do |column|
                    x_fraction = width == 1 ? 0.0 : column.to_f / (width - 1)
                    uv = na_bilinear_uv(corner_uvs, x_fraction, y_fraction)
                    bytes.concat(na_bgra_bytes(source.color_at_uv(na_repeat(uv.x), na_repeat(uv.y), true)))
                end
            end
            image_rep = Sketchup::ImageRep.new
            image_rep.set_data(width, height, 32, 0, bytes.pack('C*'))
            image_rep.save_file(path)
        end

        def self.na_bilinear_uv(corner_uvs, x_fraction, y_fraction)
            bottom = na_lerp_point(corner_uvs[0], corner_uvs[1], x_fraction)
            top = na_lerp_point(corner_uvs[3], corner_uvs[2], x_fraction)
            na_lerp_point(bottom, top, y_fraction)
        end

        def self.na_lerp_point(start_point, end_point, fraction)
            Geom::Point3d.new(
                start_point.x + ((end_point.x - start_point.x) * fraction),
                start_point.y + ((end_point.y - start_point.y) * fraction),
                0
            )
        end

        def self.na_repeat(value)
            wrapped = value % 1.0
            wrapped.negative? ? wrapped + 1.0 : wrapped
        end

        def self.na_bgra_bytes(color)
            red, green, blue, alpha = color.to_a
            return [blue, green, red, alpha] if defined?(Sketchup) && Sketchup.respond_to?(:platform) && Sketchup.platform == :platform_win

            [red, green, blue, alpha]
        end

        def self.na_temp_png_path
            temp_root = ENV['TMP'] || ENV['TEMP'] || Dir.tmpdir
            File.join(temp_root, "na_textured_plane_#{Time.now.to_i}_#{rand(9999)}.png")
        end

# endregion -------------------------------------------------------------------

    end # module Na__TexturedPlaneToImage__BitmapWriter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
