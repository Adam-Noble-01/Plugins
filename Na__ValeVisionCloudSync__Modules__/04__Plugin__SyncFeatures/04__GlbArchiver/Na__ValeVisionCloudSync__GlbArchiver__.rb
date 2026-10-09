# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC GLB ARCHIVER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__GlbArchiver__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__GlbArchiver
# PURPOSE    : Before each GLB export: zip the previous GLB set, then clear the folder
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - The GLB builder overwrites files in place and never removes one, so a GLB whose tag was
#   deleted or renamed in SketchUp stayed in ValeVision__GlbFileSync and was published with
#   every sync. Before each export this module now:
#     1. makes 00__Archive inside the GLB folder;
#     2. zips the previous *.glb set into {ProjectName}__ArchivedGlbFiles__DD-MMM-YYYY__.zip
#        and reads it back (every entry, every CRC) before anything is deleted;
#     3. deletes the older archive zip (00__Archive keeps ONE: the set before this export);
#     4. deletes the previous GLBs, so the folder holds only what this export writes.
# - An empty folder (e.g. after a failed export) keeps its archive: there is nothing newer.
# - Pure Ruby zip writer (zlib raw deflate + binary IO); no gem needed. No ZIP64, so an
#   archive over 4 GB is refused (and nothing is deleted).
# - Returns { success:, message:, archived_count:, archive_path: }.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-Jun-2026 - Version 1.0.0
# - Zipped existing GLBs to 00__ArchivedModels/{ProjectName}__GLBArchive__{date}.zip.
#
# 07-Oct-2026 - Version 1.0.1
# - Clears the folder after archiving (stale GLBs were re-published every sync) and keeps
#   one archive in 00__Archive, named {ProjectName}__ArchivedGlbFiles__DD-MMM-YYYY__.zip.
# - Fixed the zip writer: the local file header was 2 bytes short (one field missing from
#   the pack format) and the data was zlib-wrapped, so no unzip tool could open a 1.0.0
#   archive. Entries are now raw deflate under a full 30-byte header, names are flagged
#   UTF-8, and each archive is read back before the GLBs it holds are deleted.
#
# =============================================================================

require 'fileutils'
require 'zlib'

module Na__ValeVisionCloudSync
    module Na__GlbArchiver

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        ARCHIVE_DIR_NAME    = '00__Archive'.freeze             # <-- Inside the GLB folder: ONE zip of the previous set
        ARCHIVE_NAME_TOKEN  = '__ArchivedGlbFiles__'.freeze    # <-- {ProjectName}__ArchivedGlbFiles__DD-MMM-YYYY__.zip
        ZIP32_LIMIT         = 0xFFFFFFFF                       # <-- No ZIP64: sizes and offsets must fit 32 bits
        ZIP_UTF8_NAME_FLAG  = 0x0800                           # <-- General purpose bit 11: names are UTF-8
        ZIP_METHOD_DEFLATE  = 8

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Archive the Previous GLB Set, Then Clear the Folder for a Fresh Export
        # ------------------------------------------------------------
        # Returns { success:, message:, archived_count:, archive_path: }
        # A failure before step 4 deletes no GLB; the export is then stopped by the bridge.
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ArchiveExistingGlbs(glb_sync_dir, project_name)
            glb_sync_dir = glb_sync_dir.to_s.tr('\\', '/')                    # <-- Dir.glob treats '\' as escape on Windows
            glb_files    = Dir.glob(File.join(glb_sync_dir, '*.glb')).select { |f| File.file?(f) }.sort

            if glb_files.empty?
                return {
                    success:        true,
                    message:        'No previous GLB files: nothing to archive.',
                    archived_count: 0,
                    archive_path:   nil
                }
            end

            archive_dir  = File.join(glb_sync_dir, ARCHIVE_DIR_NAME)
            archive_name = "#{project_name}#{ARCHIVE_NAME_TOKEN}#{Time.now.strftime('%d-%b-%Y')}__.zip"
            archive_path = File.join(archive_dir, archive_name)
            temp_path    = "#{archive_path}.writing.tmp"

            FileUtils.mkdir_p(archive_dir)                                    # <-- 1. 00__Archive
            na_write_zip_archive(temp_path, glb_files)                        # <-- 2. the previous set ...
            problem = na_zip_read_back_problem(temp_path, glb_files)          #        ... read back whole
            raise "the archive did not read back whole (#{problem})" if problem

            older = Dir.glob(File.join(archive_dir, '*.zip')).select { |f| File.file?(f) }
            older.each { |f| File.delete(f) }                                 # <-- 3. the older archive (and today's earlier one)
            File.rename(temp_path, archive_path)

            stuck = na_delete_files(glb_files)                                # <-- 4. the folder now waits for the new set
            unless stuck.empty?
                return {
                    success:        false,
                    message:        "Archived the previous GLBs to #{ARCHIVE_DIR_NAME}/#{archive_name}, but could not " \
                                    "remove #{stuck.join(', ')} (open in another program?). Close it and sync again, " \
                                    'so a stale model is never published.',
                    archived_count: glb_files.size,
                    archive_path:   archive_path
                }
            end

            removed = older.map { |f| File.basename(f) } - [archive_name]
            {
                success:        true,
                message:        "Archived the previous #{glb_files.size} GLB file(s) to " \
                                "#{ARCHIVE_DIR_NAME}/#{archive_name} and cleared the folder" +
                                (removed.empty? ? '.' : "; removed the older archive #{removed.join(', ')}."),
                archived_count: glb_files.size,
                archive_path:   archive_path
            }
        rescue => error
            begin
                File.delete(temp_path) if temp_path && File.exist?(temp_path)
            rescue SystemCallError
                nil                                                           # <-- A *.tmp left behind is harmless
            end
            {
                success:        false,
                message:        "GLB archive failed, so no GLB was deleted: #{error.message}",
                archived_count: 0,
                archive_path:   nil
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Archive Writing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Write a PKZIP Archive From a List of File Paths
        # ---------------------------------------------------------------
        # Each entry is raw-deflated on its own; the central directory is appended.
        # ---------------------------------------------------------------
        def self.na_write_zip_archive(archive_path, file_paths)
            central_directory  = []
            dos_time, dos_date = na_current_dos_mtime

            File.open(archive_path, 'wb') do |zip_io|
                file_paths.each do |file_path|
                    file_data  = File.binread(file_path)
                    compressed = na_raw_deflate(file_data)
                    entry = {
                        name_bytes:        File.basename(file_path).encode('UTF-8').b,
                        crc32:             Zlib.crc32(file_data),
                        compressed_size:   compressed.bytesize,
                        uncompressed_size: file_data.bytesize,
                        offset:            zip_io.pos,
                        dos_time:          dos_time,
                        dos_date:          dos_date
                    }
                    if [entry[:uncompressed_size], entry[:offset] + 30 + compressed.bytesize].max > ZIP32_LIMIT
                        raise "#{File.basename(file_path)} takes the archive past 4 GB, the zip limit"
                    end

                    zip_io.write(na_build_local_file_header(entry))
                    zip_io.write(compressed)
                    central_directory << entry
                end

                central_dir_offset = zip_io.pos
                central_directory.each do |entry|
                    zip_io.write(na_build_central_directory_entry(entry))
                end
                central_dir_size = zip_io.pos - central_dir_offset
                if central_dir_offset + central_dir_size > ZIP32_LIMIT || central_directory.size > 0xFFFF
                    raise 'the archive is past the zip limits (4 GB or 65,535 files)'
                end

                zip_io.write(na_build_end_of_central_directory(
                    central_directory.size, central_dir_size, central_dir_offset
                ))
            end
        end

        # HELPER FUNCTION | Raw DEFLATE (no zlib header or trailer, as ZIP method 8 requires)
        # ---------------------------------------------------------------
        def self.na_raw_deflate(data)
            deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
            deflater.deflate(data, Zlib::FINISH)
        ensure
            deflater&.close
        end

        # HELPER FUNCTION | Raw INFLATE (the read-back check)
        # ---------------------------------------------------------------
        def self.na_raw_inflate(data)
            inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
            inflater.inflate(data)
        ensure
            inflater&.close
        end

        # HELPER FUNCTION | Build Local File Header (PK\x03\x04, 30 bytes + name)
        # ---------------------------------------------------------------
        def self.na_build_local_file_header(entry)
            [
                0x04034b50,                   # Local file header signature
                20,                           # Version needed: 2.0
                ZIP_UTF8_NAME_FLAG,           # General purpose bit flag
                ZIP_METHOD_DEFLATE,           # Compression method
                entry[:dos_time],             # Last mod file time
                entry[:dos_date],             # Last mod file date
                entry[:crc32],                # CRC-32
                entry[:compressed_size],      # Compressed size
                entry[:uncompressed_size],    # Uncompressed size
                entry[:name_bytes].bytesize,  # File name length
                0                             # Extra field length
            ].pack('VvvvvvVVVvv') + entry[:name_bytes]
        end

        # HELPER FUNCTION | Build Central Directory Entry (PK\x01\x02, 46 bytes + name)
        # ---------------------------------------------------------------
        def self.na_build_central_directory_entry(entry)
            [
                0x02014b50,                   # Central directory signature
                20,                           # Version made by (MS-DOS 2.0)
                20,                           # Version needed to extract
                ZIP_UTF8_NAME_FLAG,           # General purpose bit flag
                ZIP_METHOD_DEFLATE,           # Compression method
                entry[:dos_time],             # Last mod file time
                entry[:dos_date],             # Last mod file date
                entry[:crc32],                # CRC-32
                entry[:compressed_size],      # Compressed size
                entry[:uncompressed_size],    # Uncompressed size
                entry[:name_bytes].bytesize,  # File name length
                0,                            # Extra field length
                0,                            # File comment length
                0,                            # Disk number start
                0,                            # Internal file attributes
                0,                            # External file attributes
                entry[:offset]                # Relative offset of local header
            ].pack('VvvvvvvVVVvvvvvVV') + entry[:name_bytes]
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

# -----------------------------------------------------------------------------
# REGION | Read-Back Check and Clearing
# -----------------------------------------------------------------------------

        # FUNCTION | Read a Written Archive Back: Every Entry Inflates to Its Size and CRC
        # ---------------------------------------------------------------
        # Returns nil when the archive holds exactly file_paths, whole; else what is wrong.
        # ---------------------------------------------------------------
        def self.na_zip_read_back_problem(archive_path, file_paths)
            names = []
            File.open(archive_path, 'rb') do |io|
                size = io.size
                return 'too short to be a zip' if size < 22

                io.seek(size - 22)
                signature, _disk, _cd_disk, _on_disk, count, cd_size, cd_offset, _comment = io.read(22).unpack('VvvvvVVv')
                return 'no end-of-archive record' unless signature == 0x06054b50
                return "#{count} entries, #{file_paths.size} expected" unless count == file_paths.size

                io.seek(cd_offset)
                central = io.read(cd_size)
                pos     = 0
                count.times do
                    fields = central.byteslice(pos, 46).unpack('VvvvvvvVVVvvvvvVV')
                    return 'damaged central directory' unless fields[0] == 0x02014b50

                    crc32, compressed_size, uncompressed_size = fields[7], fields[8], fields[9]
                    name = central.byteslice(pos + 46, fields[10])
                    pos += 46 + fields[10] + fields[11] + fields[12]

                    io.seek(fields[16])
                    local = io.read(30).unpack('VvvvvvVVVvv')
                    unless local[0] == 0x04034b50 && local[6] == crc32 && local[7] == compressed_size
                        return "#{name}: damaged local header"
                    end

                    io.seek(fields[16] + 30 + local[9] + local[10])
                    data = na_raw_inflate(io.read(compressed_size))
                    unless data.bytesize == uncompressed_size && Zlib.crc32(data) == crc32
                        return "#{name}: size or CRC does not match"
                    end
                    names << name.b
                end
            end
            expected = file_paths.map { |f| File.basename(f).encode('UTF-8').b }
            names.sort == expected.sort ? nil : 'its file list differs'
        rescue => error
            "unreadable: #{error.message}"
        end

        # HELPER FUNCTION | Delete Files, Returning the Names That Could Not Be Deleted
        # ---------------------------------------------------------------
        def self.na_delete_files(file_paths)
            file_paths.each_with_object([]) do |file_path, stuck|
                begin
                    File.delete(file_path)
                rescue SystemCallError
                    stuck << File.basename(file_path)
                end
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__GlbArchiver
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
