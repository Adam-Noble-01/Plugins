# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - PHOTO INFO
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__PhotoInfo__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel__PhotoInfo
# PURPOSE    : Read a photo's lens data (EXIF) for the Perspective Angle tool
# CREATED    : 09-Oct-2026
#
# DESIGN NOTES:
# - Reads only the bytes it needs: the APP1 segment of a JPEG, the eXIf chunk
#   of a PNG, the EXIF chunk of a WebP, or the start of a TIFF. A 15 MB PNG
#   is walked chunk by chunk with seeks, never read whole.
# - The useful value is FocalLengthIn35mmFilm, which phones always write.
#   Make, model and lens model are passed on for the panel's note.
# - A file with no EXIF, or a malformed one, gives { 'none' => true }. Errors
#   are logged and never raised into the dialog callback.
# - Photos converted to PNG by most tools lose their EXIF; the panel then
#   falls back to its lens setting and to the lens solved from the lines.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ImageCarousel__PhotoInfo

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MAX_SEGMENT_BYTES = 1024 * 1024 unless const_defined?(:NA_MAX_SEGMENT_BYTES)
        NA_TIFF_HEAD_BYTES   = 512 * 1024 unless const_defined?(:NA_TIFF_HEAD_BYTES)
        NA_TAG_NAMES = {
            0x010F => 'make',
            0x0110 => 'model',
            0x8769 => 'exif_ifd',
            0x920A => 'focal_mm',
            0xA405 => 'focal35',
            0xA434 => 'lens_model'
        }.freeze unless const_defined?(:NA_TAG_NAMES)
        NA_TYPE_SIZES = { 1 => 1, 2 => 1, 3 => 2, 4 => 4, 5 => 8, 7 => 1, 9 => 4, 10 => 8 }.freeze unless const_defined?(:NA_TYPE_SIZES)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # Returns a Hash with string keys, ready for to_json:
        # { 'path', 'focal35', 'focalMm', 'make', 'model', 'lensModel' } or
        # { 'path', 'none' => true } when the file carries no lens data.
        def self.Na__ImageCarousel__PhotoInfo__Read(path)
            file_path = path.to_s
            none = { 'path' => file_path, 'none' => true }
            return none unless File.file?(file_path)

            tiff = File.open(file_path, 'rb') { |io| na_find_tiff_block(io) }
            tags = tiff ? na_parse_tiff(tiff) : {}
            focal35 = tags['focal35']
            focal35 = nil unless focal35.is_a?(Numeric) && focal35 > 0 && focal35 < 2000
            return none.merge(na_text_fields(tags)) unless focal35

            {
                'path'      => file_path,
                'focal35'   => focal35,
                'focalMm'   => tags['focal_mm'].is_a?(Numeric) ? tags['focal_mm'].round(2) : nil
            }.merge(na_text_fields(tags))
        rescue => error
            puts "[Na__ImageCarousel] photo info read failed: #{error.class}: #{error.message}"
            { 'path' => path.to_s, 'none' => true }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Containers (JPEG, PNG, WebP, TIFF)
# -----------------------------------------------------------------------------

        def self.na_find_tiff_block(io)
            head = io.read(12) || ''.b
            io.seek(0)
            return na_jpeg_exif(io)                    if head.byteslice(0, 2) == "\xFF\xD8".b
            return na_png_exif(io)                     if head.byteslice(0, 8) == "\x89PNG\r\n\x1A\n".b
            return na_webp_exif(io)                    if head.byteslice(0, 4) == 'RIFF'.b && head.byteslice(8, 4) == 'WEBP'.b
            return io.read(NA_TIFF_HEAD_BYTES)         if ['II*'.b + "\x00".b, 'MM'.b + "\x00*".b].include?(head.byteslice(0, 4))
            nil
        end

        def self.na_strip_exif_header(data)
            return nil unless data
            data.byteslice(0, 6) == "Exif\x00\x00".b ? data.byteslice(6, data.bytesize - 6) : data
        end

        def self.na_jpeg_exif(io)
            io.seek(2)
            loop do
                byte = io.read(1)
                return nil unless byte
                next unless byte.getbyte(0) == 0xFF
                code = io.read(1)
                return nil unless code
                code = code.getbyte(0)
                next if code == 0xFF || code == 0x00 || code == 0x01 || (0xD0..0xD7).include?(code)
                return nil if code == 0xD9 || code == 0xDA   # end of image, or the image data itself

                size_bytes = io.read(2)
                return nil unless size_bytes && size_bytes.bytesize == 2
                size = size_bytes.unpack1('n')
                return nil if size < 2 || size > NA_MAX_SEGMENT_BYTES

                if code == 0xE1
                    data = io.read(size - 2)
                    return nil unless data && data.bytesize == size - 2
                    return na_strip_exif_header(data) if data.byteslice(0, 6) == "Exif\x00\x00".b
                else
                    io.seek(size - 2, IO::SEEK_CUR)
                end
            end
        end

        def self.na_png_exif(io)
            io.seek(8)
            loop do
                header = io.read(8)
                return nil unless header && header.bytesize == 8
                length, type = header.unpack('Na4')
                return nil if type == 'IEND'.b
                if type == 'eXIf'.b
                    return nil if length > NA_MAX_SEGMENT_BYTES
                    return na_strip_exif_header(io.read(length))
                end
                io.seek(length + 4, IO::SEEK_CUR)   # chunk data and its CRC
            end
        end

        def self.na_webp_exif(io)
            io.seek(12)
            loop do
                header = io.read(8)
                return nil unless header && header.bytesize == 8
                fourcc, length = header.unpack('a4V')
                if fourcc == 'EXIF'.b
                    return nil if length > NA_MAX_SEGMENT_BYTES
                    return na_strip_exif_header(io.read(length))
                end
                io.seek(length + (length & 1), IO::SEEK_CUR)   # chunks are padded to even sizes
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | TIFF / EXIF Tags
# -----------------------------------------------------------------------------

        def self.na_parse_tiff(data)
            return {} unless data && data.bytesize >= 8
            order = data.byteslice(0, 2)
            little = order == 'II'.b
            return {} unless little || order == 'MM'.b
            return {} unless na_u16(data, 2, little) == 42

            tags = {}
            na_read_ifd(data, na_u32(data, 4, little), little, tags)
            exif_ifd = tags.delete('exif_ifd')
            na_read_ifd(data, exif_ifd, little, tags) if exif_ifd.is_a?(Integer)
            tags
        end

        def self.na_read_ifd(data, offset, little, tags)
            return unless offset.is_a?(Integer) && offset >= 8 && offset + 2 <= data.bytesize
            count = na_u16(data, offset, little)
            return if count.nil? || count > 1000

            count.times do |i|
                entry = offset + 2 + i * 12
                break if entry + 12 > data.bytesize
                tag   = na_u16(data, entry, little)
                name  = NA_TAG_NAMES[tag]
                next unless name

                type  = na_u16(data, entry + 2, little)
                n     = na_u32(data, entry + 4, little)
                size  = NA_TYPE_SIZES[type]
                next unless size && n && n > 0 && n < 100_000
                total = size * n
                value_at = total > 4 ? na_u32(data, entry + 8, little) : entry + 8
                next unless value_at && value_at + total <= data.bytesize

                value = na_decode(data, value_at, type, n, little)
                tags[name] = value unless value.nil?
            end
        end

        def self.na_decode(data, at, type, n, little)
            case type
            when 2
                text = data.byteslice(at, n).delete("\x00".b).strip
                text.force_encoding('UTF-8').scrub('')
            when 3 then na_u16(data, at, little)
            when 4 then na_u32(data, at, little)
            when 5
                num = na_u32(data, at, little)
                den = na_u32(data, at + 4, little)
                num && den && den > 0 ? num.to_f / den : nil
            end
        end

        def self.na_u16(data, at, little)
            return nil unless at && at >= 0 && at + 2 <= data.bytesize
            data.byteslice(at, 2).unpack1(little ? 'v' : 'n')
        end

        def self.na_u32(data, at, little)
            return nil unless at && at >= 0 && at + 4 <= data.bytesize
            data.byteslice(at, 4).unpack1(little ? 'V' : 'N')
        end

        def self.na_text_fields(tags)
            out = {}
            out['make']      = tags['make']       if tags['make'].is_a?(String) && !tags['make'].empty?
            out['model']     = tags['model']      if tags['model'].is_a?(String) && !tags['model'].empty?
            out['lensModel'] = tags['lens_model'] if tags['lens_model'].is_a?(String) && !tags['lens_model'].empty?
            out
        end

# endregion -------------------------------------------------------------------

    end # module Na__ImageCarousel__PhotoInfo
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
