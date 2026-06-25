# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC GLB ARCHIVER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__GlbArchiver__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__GlbArchiver
# PURPOSE    : Archive existing GLB files to a dated ZIP before a new export
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Scans the ValeVision__GlbFileSync folder for existing *.glb files.
# - Zips them into 00__ArchivedModels/{ProjectName}__GLBArchive__{date}.zip.
# - Uses Ruby's built-in zlib + zip stream (no external gem required).
# - Returns { success:, message:, archived_count:, archive_path: }.
#
# =============================================================================

require 'fileutils'
require 'zlib'

module Na__ValeVisionCloudSync
    module Na__GlbArchiver

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Archive Existing GLBs Before A Fresh Export
        # ------------------------------------------------------------
        # Returns { success:, message:, archived_count:, archive_path: }
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ArchiveExistingGlbs(glb_sync_dir, project_name)
            glb_sync_dir = glb_sync_dir.to_s.tr('\\', '/')                    # <-- Dir.glob treats '\' as escape on Windows
            glb_files    = Dir.glob(File.join(glb_sync_dir, '*.glb'))

            if glb_files.empty?
                return {
                    success: true,
                    message: 'No existing GLB files to archive.',
                    archived_count: 0,
                    archive_path: nil
                }
            end

            archive_dir  = File.join(glb_sync_dir, '00__ArchivedModels')
            FileUtils.mkdir_p(archive_dir)

            date_stamp   = Time.now.strftime('%d-%b-%Y')
            archive_name = "#{project_name}__GLBArchive__#{date_stamp}.zip"
            archive_path = File.join(archive_dir, archive_name)

            na_write_zip_archive(archive_path, glb_files)

            {
                success:        true,
                message:        "Archived #{glb_files.size} GLB file(s) to #{archive_name}",
                archived_count: glb_files.size,
                archive_path:   archive_path
            }
        rescue => error
            {
                success:        false,
                message:        "GLB archive failed: #{error.message}",
                archived_count: 0,
                archive_path:   nil
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Archive Writing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Write a minimal ZIP archive from a list of file paths
        # ---------------------------------------------------------------
        # Writes a PKZIP-compatible archive using pure Ruby (zlib + binary IO).
        # Each entry is deflated individually; the central directory is appended.
        # ---------------------------------------------------------------
        def self.na_write_zip_archive(archive_path, file_paths)
            central_directory = []

            File.open(archive_path, 'wb') do |zip_io|
                file_paths.each do |file_path|
                    next unless File.exist?(file_path)

                    local_file_name  = File.basename(file_path)
                    file_data        = File.binread(file_path)
                    crc32            = Zlib.crc32(file_data)
                    compressed_data  = Zlib::Deflate.deflate(file_data, Zlib::DEFAULT_COMPRESSION)

                    local_header_offset = zip_io.tell

                    local_header = na_build_local_file_header(
                        local_file_name, file_data.bytesize, compressed_data.bytesize, crc32
                    )

                    zip_io.write(local_header)
                    zip_io.write(compressed_data)

                    central_directory << {
                        name:              local_file_name,
                        offset:            local_header_offset,
                        crc32:             crc32,
                        compressed_size:   compressed_data.bytesize,
                        uncompressed_size: file_data.bytesize
                    }
                end

                central_dir_offset = zip_io.tell
                central_directory.each do |entry|
                    zip_io.write(na_build_central_directory_entry(entry))
                end
                central_dir_size = zip_io.tell - central_dir_offset

                zip_io.write(na_build_end_of_central_directory(
                    central_directory.size, central_dir_size, central_dir_offset
                ))
            end
        end

        # HELPER FUNCTION | Build Local File Header (PK\x03\x04)
        # ---------------------------------------------------------------
        def self.na_build_local_file_header(name, uncompressed_size, compressed_size, crc32)
            name_bytes     = name.encode('UTF-8').b
            mtime_dostime  = na_current_dos_mtime

            [
                0x04034b50,          # Local file header signature
                20,                  # Version needed: 2.0
                0,                   # General purpose bit flag
                8,                   # Compression method: deflate
                mtime_dostime[0],    # Last mod file time
                mtime_dostime[1],    # Last mod file date
                crc32,               # CRC-32
                compressed_size,     # Compressed size
                uncompressed_size,   # Uncompressed size
                name_bytes.bytesize, # File name length
                0                    # Extra field length
            ].pack('VvvvvVVVvv') + name_bytes
        end

        # HELPER FUNCTION | Build Central Directory Entry (PK\x01\x02)
        # ---------------------------------------------------------------
        def self.na_build_central_directory_entry(entry)
            name_bytes    = entry[:name].encode('UTF-8').b
            mtime_dostime = na_current_dos_mtime

            [
                0x02014b50,                # Central directory signature
                20,                        # Version made by (MS-DOS 2.0)
                20,                        # Version needed to extract
                0,                         # General purpose bit flag
                8,                         # Compression method: deflate
                mtime_dostime[0],          # Last mod file time
                mtime_dostime[1],          # Last mod file date
                entry[:crc32],             # CRC-32
                entry[:compressed_size],   # Compressed size
                entry[:uncompressed_size], # Uncompressed size
                name_bytes.bytesize,       # File name length
                0,                         # Extra field length
                0,                         # File comment length
                0,                         # Disk number start
                0,                         # Internal file attributes
                0,                         # External file attributes
                entry[:offset]             # Relative offset of local header
            ].pack('VvvvvvvVVVvvvvvVV') + name_bytes
        end

        # HELPER FUNCTION | Build End of Central Directory Record (PK\x05\x06)
        # ---------------------------------------------------------------
        def self.na_build_end_of_central_directory(count, central_dir_size, central_dir_offset)
            [
                0x06054b50,      # End of central directory signature
                0,               # Disk number
                0,               # Disk where central directory starts
                count,           # Number of entries on this disk
                count,           # Total entries
                central_dir_size,
                central_dir_offset,
                0                # Comment length
            ].pack('VvvvvVVv')
        end

        # HELPER FUNCTION | Current Time As MS-DOS Time/Date Pair
        # ---------------------------------------------------------------
        def self.na_current_dos_mtime
            now = Time.now
            dos_time = ((now.hour << 11) | (now.min << 5) | (now.sec / 2))
            dos_date = (((now.year - 1980) << 9) | (now.month << 5) | now.mday)
            [dos_time, dos_date]
        end

# endregion -------------------------------------------------------------------

    end # module Na__GlbArchiver
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
