# =============================================================================
# NA DATALIB - URL GENERATOR
# =============================================================================
#
# FILE       : Na__DataLib__UrlGenerator__.rb
# NAMESPACE  : Na__DataLib__UrlGenerator
# MODULE     : Na__DataLib__UrlGenerator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Builds raw GitHub URLs for centralised Na__ data files
# CREATED    : 15-Mar-2026
#
# DESCRIPTION:
# - Single place that knows the GitHub repo structure for Na__ data files.
# - All consuming plugins call this module to resolve the raw fetch URL
#   for any registered data file key.
# - If the repository location ever changes, only this file needs updating.
# - Used by Na__DataLib__CacheData__ as the primary URL source.
#
# =============================================================================

module Na__DataLib__UrlGenerator

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | GitHub Raw Content Base URL
    # ------------------------------------------------------------
    GITHUB_RAW_BASE  = "https://raw.githubusercontent.com/Adam-Noble-01/Plugins/main/Na__Common__DataLib__CoreSuEntityStandards/".freeze
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Registered Data File Keys
    # ------------------------------------------------------------
    FILE_KEYS = {
        :materials      => "Na__DataLib__CoreIndex__Materials__.json",
        :edge_materials => "Na__DataLib__CoreIndex__EdgeMaterials__.json",
        :tags           => "Na__DataLib__CoreIndex__Tags__.json",
        :components     => "Na__DataLib__CoreIndex__Components__.json"
    }.freeze
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build Raw GitHub URL for a Data File Key
    # ------------------------------------------------------------
    def self.Na__Url__BuildRawUrl(file_key)
        filename = FILE_KEYS[file_key]
        unless filename
            puts "    [Na__DataLib__UrlGenerator] Unknown file_key: #{file_key.inspect}"
            return nil
        end

        GITHUB_RAW_BASE + filename
    end
    # ---------------------------------------------------------------

    # FUNCTION | Return the Filename String for a Data File Key
    # ------------------------------------------------------------
    def self.Na__Url__FileNameForKey(file_key)
        FILE_KEYS[file_key]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Return All Registered File Keys
    # ------------------------------------------------------------
    def self.Na__Url__AllFileKeys
        FILE_KEYS
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__DataLib__UrlGenerator

# =============================================================================
# END OF FILE
# =============================================================================
