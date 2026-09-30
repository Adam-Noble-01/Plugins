# =============================================================================
# NA COMPONENT EDITOR TOOLS - MCP OPERATIONS | ARCHIVE ZIPS
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__McpOperations__Archive__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__McpArchive
# PURPOSE    : Archive a library file the way Adam asked (30-Sep-2026): zip it
#              into the set's 00__Archive folder, date-stamped
#              <name>__30-Sep-2026.zip.
# CREATED    : 2026
#
# THE ZIP:
# A standard single-entry .zip (deflate, UTF-8 name flag) written with Ruby's
# own zlib, so no gem or external program is needed. It opens in Windows
# Explorer and 7-Zip. Before the original leaves the library the zip is read
# back and its bytes and CRC compared with the file, so a bad archive is never
# the only copy. The original then moves into the change journal (archived/),
# which keeps revert exact; nothing is deleted.
#
# =============================================================================

require 'zlib'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__McpArchive

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_ZIP_UTF8_FLAG     = 0x0800
        NA_ZIP_DEFLATE       = 8
        NA_ZIP_VERSION       = 20
        NA_DEFAULT_DATE_TAIL = '__%d-%b-%Y'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # "<set>/00__Archive/<stem>__30-Sep-2026.zip" for a file in a set. The
        # stem's own trailing __ is dropped first, so the date joins with one __.
        def self.Na__ComponentEditorTools__DefaultZipPath(root, file_path)
            relative = Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, file_path)
            set_name = relative.split('/').first
            folders = Na__McpConvention.Na__ComponentEditorTools__Config['holding_folders'] || {}
            archive = folders['archive'].to_s.empty? ? '00__Archive' : folders['archive'].to_s
            stem = File.basename(file_path, '.*').sub(/_+\z/, '')
            File.join(root, set_name, archive, "#{stem}#{self.Na__ComponentEditorTools__DateTail}.zip")
        end

        def self.Na__ComponentEditorTools__DateTail
            format_text = (Na__McpConvention.Na__ComponentEditorTools__Config['archive_date_suffix'] || NA_DEFAULT_DATE_TAIL).to_s
            Time.now.strftime(format_text)
        end

        # Writes a one-file zip and proves it reads back to the same bytes.
        def self.Na__ComponentEditorTools__ZipFile(file_path, zip_path)
            data = File.binread(file_path)
            name = File.basename(file_path).encode('UTF-8').b
            crc = Zlib.crc32(data)
            deflater = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
            compressed = deflater.deflate(data, Zlib::FINISH)
            deflater.close
            time, date = self.Na__ComponentEditorTools__DosStamp(File.mtime(file_path))

            local = [0x04034b50, NA_ZIP_VERSION, NA_ZIP_UTF8_FLAG, NA_ZIP_DEFLATE, time, date, crc,
                     compressed.bytesize, data.bytesize, name.bytesize, 0].pack('VvvvvvVVVvv') + name
            central = [0x02014b50, NA_ZIP_VERSION, NA_ZIP_VERSION, NA_ZIP_UTF8_FLAG, NA_ZIP_DEFLATE, time, date, crc,
                       compressed.bytesize, data.bytesize, name.bytesize, 0, 0, 0, 0, 0, 0].pack('VvvvvvvVVVvvvvvVV') + name
            ending = [0x06054b50, 0, 0, 1, 1, central.bytesize, local.bytesize + compressed.bytesize, 0].pack('VvvvvVVv')

            FileUtils.mkdir_p(File.dirname(zip_path))
            File.binwrite(zip_path, local + compressed + central + ending)
            self.Na__ComponentEditorTools__VerifyZip(zip_path, data, crc)
            { 'zip' => zip_path, 'bytes' => data.bytesize, 'zip_bytes' => File.size(zip_path), 'crc32' => format('%08x', crc) }
        end

        # Reads the single entry back; raises unless it matches the original bytes.
        def self.Na__ComponentEditorTools__VerifyZip(zip_path, original_data, original_crc)
            raw = File.binread(zip_path)
            signature, _version, _flags, method, _time, _date, crc, compressed_size, size, name_length, extra_length = raw.unpack('VvvvvvVVVvv')
            raise "#{File.basename(zip_path)} is not a zip written by this tool." unless signature == 0x04034b50 && method == NA_ZIP_DEFLATE

            start = 30 + name_length + extra_length
            inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
            restored = inflater.inflate(raw.byteslice(start, compressed_size))
            inflater.close
            unless restored == original_data && crc == original_crc && size == original_data.bytesize
                raise "The archive #{File.basename(zip_path)} did not read back identical to the file; the original was left in place."
            end

            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # MS-DOS time and date words for a zip header.
        def self.Na__ComponentEditorTools__DosStamp(time_value)
            year = [[time_value.year, 1980].max, 2107].min
            dos_time = (time_value.hour << 11) | (time_value.min << 5) | (time_value.sec / 2)
            dos_date = ((year - 1980) << 9) | (time_value.month << 5) | time_value.day
            [dos_time, dos_date]
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
