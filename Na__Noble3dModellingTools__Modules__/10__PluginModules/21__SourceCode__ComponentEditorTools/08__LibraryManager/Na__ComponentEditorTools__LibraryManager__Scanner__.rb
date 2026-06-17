# =============================================================================
# NA COMPONENT EDITOR TOOLS - LIBRARY MANAGER | SCANNER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__LibraryManager__Scanner__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__LibraryScanner
# PURPOSE    : Recursively discover .skp files from the configured library
#              folder, honouring the blocked-folder list. Returns per-file
#              meta hashes (path, filename, relative folder, size, mtime,
#              cache_key) used by the Extractor.
# CREATED    : 2026
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__LibraryScanner

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ScanLibrary
            library_path = self.Na__ComponentEditorTools__NormalisePath(
                Na__UserConfig.Na__ComponentEditorTools__LibraryPath
            )
            return { ok: false, message: 'No library folder configured.', entries: [] } if library_path.empty?
            return { ok: false, message: "Library folder not found: #{library_path}", entries: [] } unless Dir.exist?(library_path)

            blocked = Na__UserConfig.Na__ComponentEditorTools__BlockedFolders
            blocked_files = Na__UserConfig.Na__ComponentEditorTools__BlockedFiles
            skp_files = self.Na__ComponentEditorTools__CollectSkpFiles(library_path, blocked, blocked_files)

            entries = skp_files.map do |full_path|
                self.Na__ComponentEditorTools__BuildEntryMeta(full_path, library_path)
            end

            {
                ok: true,
                message: "Found #{entries.length} component file(s).",
                library_path: library_path,
                entries: entries
            }
        rescue => error
            { ok: false, message: "#{error.class}: #{error.message}", entries: [] }
        end

        def self.Na__ComponentEditorTools__FolderList
            library_path = self.Na__ComponentEditorTools__NormalisePath(
                Na__UserConfig.Na__ComponentEditorTools__LibraryPath
            )
            return [] unless Dir.exist?(library_path.to_s)

            blocked = Na__UserConfig.Na__ComponentEditorTools__BlockedFolders
            blocked_files = Na__UserConfig.Na__ComponentEditorTools__BlockedFiles

            Dir.glob(File.join(library_path, '**', '*.skp')).reject do |full_path|
                norm = self.Na__ComponentEditorTools__NormalisePath(full_path)
                self.Na__ComponentEditorTools__BlockedPath?(norm, blocked) ||
                    self.Na__ComponentEditorTools__BlockedFile?(norm, blocked_files)
            end.map do |full_path|
                norm_path    = self.Na__ComponentEditorTools__NormalisePath(full_path)
                norm_library = library_path.chomp('/')
                rel_dir = File.dirname(norm_path).sub(norm_library, '').sub(%r{^/+}, '')
                rel_dir.empty? ? '(root)' : rel_dir
            end.uniq.sort.reject do |folder_path|
                self.Na__ComponentEditorTools__BlockedPath?(folder_path, blocked)
            end
        rescue
            []
        end

        def self.Na__ComponentEditorTools__InvalidateCache
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | File Discovery
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__CollectSkpFiles(normalised_library_path, blocked_folder_names, blocked_file_names = [])
            Dir.glob(File.join(normalised_library_path, '**', '*.skp')).sort.select do |full_path|
                norm = self.Na__ComponentEditorTools__NormalisePath(full_path)
                File.file?(norm) &&
                    !self.Na__ComponentEditorTools__BlockedPath?(norm, blocked_folder_names) &&
                    !self.Na__ComponentEditorTools__BlockedFile?(norm, blocked_file_names)
            end
        end

        def self.Na__ComponentEditorTools__BlockedPath?(path_string, blocked_folder_names)
            return false if blocked_folder_names.empty?

            normalised    = self.Na__ComponentEditorTools__NormalisePath(path_string.to_s)
            path_segments = normalised.split('/')
            blocked_folder_names.any? do |blocked_name|
                path_segments.any? { |segment| segment == blocked_name.to_s }
            end
        end

        def self.Na__ComponentEditorTools__BlockedFile?(path_string, blocked_file_names)
            return false if blocked_file_names.empty?

            file_name = File.basename(path_string.to_s)
            blocked_file_names.any? { |blocked| file_name == blocked.to_s }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entry Meta Builder
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__BuildEntryMeta(full_path, normalised_library_root)
            stat_info     = File.stat(full_path)
            norm_full     = self.Na__ComponentEditorTools__NormalisePath(full_path)
            norm_root     = normalised_library_root.chomp('/')
            relative_path = norm_full.sub(norm_root + '/', '').sub(norm_root, '')
            relative_dir  = File.dirname(relative_path).sub(%r{^\.$}, '(root)')
            file_name     = File.basename(full_path)
            file_key      = self.Na__ComponentEditorTools__CacheKey(norm_full, stat_info.mtime.to_i)

            {
                path:          norm_full,
                file_name:     file_name,
                relative_dir:  relative_dir,
                relative_path: relative_path,
                size_bytes:    stat_info.size,
                mtime:         stat_info.mtime.to_i,
                cache_key:     file_key
            }
        rescue => error
            norm_full = self.Na__ComponentEditorTools__NormalisePath(full_path.to_s)
            {
                path:          norm_full,
                file_name:     File.basename(full_path),
                relative_dir:  '(error)',
                relative_path: File.basename(full_path),
                size_bytes:    0,
                mtime:         0,
                cache_key:     norm_full,
                error:         error.message
            }
        end

        def self.Na__ComponentEditorTools__CacheKey(normalised_path, mtime_int)
            "#{normalised_path}::#{mtime_int}"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Normalisation
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__NormalisePath(raw_path)
            raw_path.to_s.tr('\\', '/')
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
