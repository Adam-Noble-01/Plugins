# =============================================================================
# NA NOBLE3D MODELLING TOOLS - IMAGE CAROUSEL - FOLDER SCANNER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ImageCarousel__FolderScanner__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ImageCarousel__FolderScanner
# PURPOSE    : Collect and filter image file paths from a root directory
# CREATED    : 2026
#
# NOTES:
# - Recursively scans all subdirectories under root
# - Rejects files whose path passes through any folder named 00__Archive
#   or 00__Ignore at any nesting level
# - Returns paths normalised to forward slashes for use in file:// URLs
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ImageCarousel__FolderScanner

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .bmp .webp .tif .tiff .heic .heif].freeze unless const_defined?(:NA_IMAGE_EXTENSIONS)
        NA_IGNORED_FOLDER_NAMES = %w[00__Archive 00__Ignore].freeze unless const_defined?(:NA_IGNORED_FOLDER_NAMES)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        def self.Na__ImageCarousel__FolderScanner__CollectImages(root_path)
            normalised_root = na_normalise_path(File.expand_path(root_path.to_s))
            raw_paths = Dir.glob(File.join(normalised_root, '**', '*'))
            raw_paths
                .select  { |f| File.file?(f) && na_supported_extension?(f) }
                .reject  { |f| na_path_in_ignored_folder?(f, normalised_root) }
                .sort_by { |f| f.downcase }
                .map     { |f| na_normalise_path(f) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_supported_extension?(file_path)
            NA_IMAGE_EXTENSIONS.include?(File.extname(file_path).downcase)
        end

        def self.na_path_in_ignored_folder?(file_path, root_path)
            relative = na_normalise_path(file_path).sub(na_normalise_path(root_path), '')
            relative.split('/').any? { |segment| NA_IGNORED_FOLDER_NAMES.include?(segment) }
        end

        def self.na_normalise_path(file_path)
            file_path.gsub('\\', '/')
        end

# endregion -------------------------------------------------------------------

    end # module Na__ImageCarousel__FolderScanner
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
