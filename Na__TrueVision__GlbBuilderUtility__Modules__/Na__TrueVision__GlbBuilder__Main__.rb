# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__Main__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Main orchestrator for the GLB Builder Utility
# CREATED    : 2025
#
# DESCRIPTION:
# - Export SketchUp models to GLB format with texture optimization
# - Includes material and texture export with automatic optimization
# - Excludes entities on layers matching "TrueVision_{wildcard}_DoNotExportGLTF"
# - Provides options for exporting selection only or entire model
# - Integrates with TrueVision3D plugin ecosystem
#
# -----------------------------------------------------------------------------
#
# DATA SOURCE - SINGLE SOURCE OF TRUTH
# All export configuration data is loaded from the centralised Na__DataLib:
#
#   Tags & Export Config:
#     Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json
#     -> TAG_RANGES, SKIP_RANGES, STOREY maps, ExportExclusions
#     -> Loaded via Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
#
#   Materials Library:
#     Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json
#     -> PBR material configs for indexed materials (MAT{NNN}__)
#     -> Loaded via Na__DataLib__CacheData.Na__Cache__LoadData(:materials)
#
# Data is fetched from GitHub (primary), cached locally for 30 minutes,
# with local plugin folder fallback if the web is unreachable.
# Hardcoded Ruby constants are retained as fallback defaults only.
#
# -----------------------------------------------------------------------------
#
# TECHNICAL IMPLEMENTATION: See devlog for export method, material handling, and texture support details
#
# -----------------------------------------------------------------------------
#
# SKETCHUP API QUIRKS AND IMPORTANT NOTES  -  !!READ BEFORE EDITING!!
# - Units: SketchUp stores ALL measurements internally in inches regardless of 
#   display units. Conversion to meters (glTF standard) requires factor 0.0254
# - Coordinate System: SketchUp uses Z-up right-handed system while glTF uses 
#   Y-up right-handed. Requires -90° rotation around X axis for conversion
# - UV Coordinates: SketchUp stores UVs in pixel coordinates with bottom-left 
#   origin. Must normalize to 0-1 range and flip V coordinate for glTF
# - Materials: Materials.current can cause BugSplats if not in model.materials
# - Textures: Use texture.write(path, true) to get colorized textures, not 
#   image_rep.save_file which loses material color adjustments
# - Image Materials: Image entities create hidden materials not visible in UI
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG: See Na__TrueVision__GlbBuilder__DevLog__.md in Modules folder
#
# =============================================================================

require 'json'                                                                    # <-- JSON parsing for dialog parameters
require 'fileutils'                                                               # <-- File operations for texture caching

# Load dependent modules
require_relative 'Na__TrueVision__GlbBuilder__CoreExport__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__GeometryHandling__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__ComponentInstancing__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__TextureHandling__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__LineworkModelHandling__'
require_relative 'Na__TrueVision__GlbBuilder__SpecialObject__DoorObjectHandling__'
require_relative 'Na__TrueVision__GlbBuilder__UserInterface__'
require_relative 'Na__TrueVision__GlbBuilder__DynamicReloaderPluginUtil__'
require_relative 'Na__TrueVision__GlbBuilder__TagsManager__'
require_relative 'Na__TrueVision__GlbBuilder__Logging__'
require_relative '../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'

module TrueVision3D
    module GlbBuilderUtility
    
    # -----------------------------------------------------------------------------
    # REGION | Module Constants and Configuration
    # -----------------------------------------------------------------------------
    
        # MODULE CONSTANTS | Export Configuration and Thresholds
        # ------------------------------------------------------------
        MAX_TEXTURE_SIZE            =   1024                                      # <-- Maximum texture dimension before downscaling
        TEXTURE_SCALE_FACTOR        =   0.25                                      # <-- Scale factor for texture downscaling (25%)
        EXCLUDED_LAYER_PATTERN      =   /^TrueVision_.*_DoNotExportGLTF$/         # <-- Regex pattern for excluded layers (hardcoded fallback)
        EXCLUDED_LAYER_DESCRIPTION  =   "TrueVision_*_DoNotExportGLTF".freeze     # <-- Human-readable description for excluded layers
        ALWAYS_EXCLUDED_LAYER_NAMES =   [
            "02__Linetype__DoorSwings",
            "02__ClearanceLines",
            "Na__Door__Open"                                                       # <-- Open-state MOD preview; must never land in GLB
        ].freeze                                                                   # <-- Hardcoded fallback - overridden by DataLib at runtime
        TREAT_AS_UNTAGGED_DEFAULTS  =   [].freeze                                 # <-- Hardcoded fallback - overridden by DataLib at runtime
        LINEWORK_HIDDEN_DEFAULTS    =   [
            "01__ModelFlag__FloorLevelLines",
            "01__ModelFlag__BuildingJoinLines"
        ].freeze                                                                   # <-- Hardcoded fallback - overridden by DataLib at runtime
        LOGGING_CONSOLE_VERBOSE_DEFAULT     = false                               # <-- Hardcoded fallback - overridden by DataLib/AppConfig at runtime
        LOGGING_TEXT_FILE_ENABLED_DEFAULT   = true                                # <-- Hardcoded fallback - overridden by DataLib/AppConfig at runtime
        LOGGING_TEXT_FILE_NAME_PATTERN_DEFAULT = "GlbBuilder__ExportLog__%TIMESTAMP%.txt".freeze  # <-- Hardcoded fallback
        INCHES_TO_METERS            =   0.0254                                    # <-- Unit conversion factor: inches → meters
        DEFAULT_EXPORT_NAME         =   "SketchUpExport"                          # <-- Default filename for exports
        GLB_FILE_EXTENSION          =   ".glb"                                    # <-- GLB file extension
        MESH_MODEL_SUFFIX           =   "__MeshModel__"                           # <-- Suffix for mesh GLB (face geometry)
        LINEWORK_MODEL_SUFFIX       =   "__LineworkModel__"                       # <-- Suffix for linework GLB (edge geometry)
        # ------------------------------------------------------------

        # MODULE VARIABLES | DataLib-Driven Export Configuration
        # ------------------------------------------------------------
        @na_datalib_exclusion_pattern     = nil                                   # <-- Regex from Tags JSON ExportExclusions
        @na_datalib_fully_excluded        = nil                                   # <-- Array of fully excluded tag names
        @na_datalib_treat_as_untagged     = nil                                   # <-- Array of treat-as-untagged tag names
        @na_datalib_linework_hidden       = nil                                   # <-- Array of linework-hidden tag names
        @na_datalib_profileline_excluded  = nil                                   # <-- Array of name tokens whose linework is omitted (Components JSON)
        @na_datalib_profileline_matchmode = "contains"                            # <-- Match mode for profile-line exclusion tokens
        @na_datalib_skip_ranges           = nil                                   # <-- Array of skipped tag range numbers
        @na_datalib_tag_ranges            = nil                                   # <-- { Glb__ExportFileNameStem => [range_nums] } replaces TAG_RANGES
        @na_datalib_storey_tag_map        = nil                                   # <-- { tag_number => Storey__ContainerExportName } replaces STOREY_TAG_MAP
        @na_datalib_storey_element_map    = nil                                   # <-- { tag_number => Storey__ElementExportName } replaces STOREY_ELEMENT_TAG_MAP
        @na_datalib_storey_tag_range      = nil                                   # <-- Array of storey container tag numbers replaces STOREY_TAG_RANGE
        @na_datalib_loaded                = false                                 # <-- Flag to prevent re-loading
        @na_logging_console_verbose       = LOGGING_CONSOLE_VERBOSE_DEFAULT       # <-- Console verbose flag (cached after load)
        @na_logging_text_file_enabled     = LOGGING_TEXT_FILE_ENABLED_DEFAULT     # <-- Text file enabled flag (cached after load)
        @na_logging_text_file_name_pattern = LOGGING_TEXT_FILE_NAME_PATTERN_DEFAULT # <-- Text file name pattern (cached after load)
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | DataLib-Driven Export Configuration Loader
    # -----------------------------------------------------------------------------

        # FUNCTION | Force Reload Export Configuration (clears cached state)
        # ------------------------------------------------------------
        def self.Na__ExportConfig__ForceReload
            @na_datalib_loaded = false
            self.Na__ExportConfig__LoadFromDataLib
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load Export Configuration from Centralised Tags JSON
        # ------------------------------------------------------------
        def self.Na__ExportConfig__LoadFromDataLib
            return if @na_datalib_loaded

            begin
                tags_data = Na__DataLib__CacheData.Na__Cache__LoadData(:tags)

                if tags_data
                    exclusions = tags_data["ExportExclusions"]
                    meta       = tags_data["meta"]

                    if exclusions.is_a?(Hash)
                        pattern_str       = exclusions["PatternExclusionRegex"]
                        fully_excluded    = Array(exclusions["FullyExcludedTagNames"])
                        treat_untagged    = Array(exclusions["TreatAsUntaggedTagNames"])
                        linework_hidden   = Array(exclusions["LineworkHiddenTagNames"])

                        @na_datalib_exclusion_pattern = pattern_str ? Regexp.new(pattern_str) : nil
                        @na_datalib_fully_excluded    = fully_excluded.empty?  ? nil : fully_excluded
                        @na_datalib_treat_as_untagged = treat_untagged.empty?  ? nil : treat_untagged
                        @na_datalib_linework_hidden   = linework_hidden.empty? ? nil : linework_hidden

                        puts "    [GlbBuilder] DataLib exclusions loaded: #{fully_excluded.size} fully excluded, #{treat_untagged.size} treat-as-untagged, #{linework_hidden.size} linework-hidden"
                    end

                    glb_config = tags_data["GlbBuilderConfig"]
                    if glb_config.is_a?(Hash) && glb_config["Logging"].is_a?(Hash)
                        logging = glb_config["Logging"]
                        @na_logging_console_verbose        = logging["ConsoleVerbose"]      == true
                        @na_logging_text_file_enabled      = logging["TextFileEnabled"]     != false
                        @na_logging_text_file_name_pattern = logging["TextFileNamePattern"] || LOGGING_TEXT_FILE_NAME_PATTERN_DEFAULT
                    end

                    self.Na__ExportConfig__OverlayLocalAppConfig

                    if meta.is_a?(Hash) && meta["skipRanges"].is_a?(Array)
                        @na_datalib_skip_ranges = meta["skipRanges"]
                    end

                    self.Na__ExportConfig__BuildHashesFromTagEntries(tags_data)
                end

                # PIPELINE EXCLUSIONS | Load name-based linework omission list from Components JSON
                components_data = Na__DataLib__CacheData.Na__Cache__LoadData(:components)
                if components_data.is_a?(Hash)
                    pipeline_exclusions = components_data["Na__DataLib__PipelineExclusions"]
                    if pipeline_exclusions.is_a?(Hash)
                        match_mode      = pipeline_exclusions["MatchMode"]
                        profile_section = pipeline_exclusions["Na__DataLib__PipelineExclusions__ProfileLines"]
                        profile_names   = profile_section.is_a?(Hash) ? Array(profile_section["Names"]) : []

                        @na_datalib_profileline_matchmode = match_mode.is_a?(String) ? match_mode : "contains"
                        @na_datalib_profileline_excluded  = profile_names.empty? ? nil : profile_names

                        puts "    [GlbBuilder] DataLib pipeline exclusions loaded: #{profile_names.size} profile-line names (match=#{@na_datalib_profileline_matchmode})"
                    end
                end
            rescue => e
                puts "    [GlbBuilder] WARNING: DataLib load failed, using hardcoded fallbacks: #{e.message}"
            end

            @na_datalib_loaded = true
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Overlay Local AppConfig JSON Over DataLib Logging Defaults
        # ---------------------------------------------------------------
        # Reads Na__TrueVision__GlbBuilder__AppConfig__.json (if present) from
        # the plugin folder and applies its Logging sub-keys on top of whatever
        # was loaded from the DataLib. Missing keys in the local file are skipped
        # so only present overrides take effect.
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__OverlayLocalAppConfig
            local_config_path = File.join(NA_PLUGIN_ROOT, 'Na__TrueVision__GlbBuilder__AppConfig__.json')
            return unless File.exist?(local_config_path)

            begin
                local_data = JSON.parse(File.read(local_config_path, encoding: 'UTF-8'))
                logging    = local_data["Logging"]
                return unless logging.is_a?(Hash)

                @na_logging_console_verbose        = logging["ConsoleVerbose"]      == true         unless logging["ConsoleVerbose"].nil?
                @na_logging_text_file_enabled      = logging["TextFileEnabled"]     != false        unless logging["TextFileEnabled"].nil?
                @na_logging_text_file_name_pattern = logging["TextFileNamePattern"]                 if logging["TextFileNamePattern"].is_a?(String)

                puts "    [GlbBuilder] Local AppConfig overlay applied (ConsoleVerbose=#{@na_logging_console_verbose}, TextFile=#{@na_logging_text_file_enabled})"
            rescue => e
                puts "    [GlbBuilder] WARNING: Could not read local AppConfig: #{e.message}"
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Walk Tag Entries and Build Runtime Hashes
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__BuildHashesFromTagEntries(tags_data)
            library = tags_data["Na__DataLib__CoreIndex__Tags"]
            return unless library.is_a?(Hash)

            tag_ranges         = {}
            storey_tag_map     = {}
            storey_element_map = {}
            storey_tag_range   = []

            library.each do |_section_key, section|
                next unless section.is_a?(Hash)

                section.each do |_entry_key, entry|
                    next unless entry.is_a?(Hash)

                    range_nums = entry["Glb__ExportRangeNumbers"]
                    file_stem  = entry["Glb__ExportFileNameStem"]

                    if file_stem && range_nums.is_a?(Array) && !range_nums.empty?
                        tag_ranges[file_stem] = range_nums
                    end

                    if entry["Storey__IsContainer"]
                        tag_match = entry["Tag__SketchUpName"]&.match(/^(\d{2})__/)
                        if tag_match
                            tag_num = tag_match[1].to_i
                            storey_tag_range << tag_num
                            container_name = entry["Storey__ContainerExportName"]
                            storey_tag_map[tag_num] = container_name if container_name
                        end
                    end

                    element_name = entry["Storey__ElementExportName"]
                    if element_name && range_nums.is_a?(Array)
                        range_nums.each { |num| storey_element_map[num] = element_name }
                    end
                end
            end

            if tag_ranges.empty?
                puts "    [GlbBuilder] WARNING: DataLib tag ranges empty (JSON may use old field names), using hardcoded fallbacks"
                @na_datalib_tag_ranges         = nil
                @na_datalib_storey_tag_map     = nil
                @na_datalib_storey_element_map = nil
                @na_datalib_storey_tag_range   = nil
            else
                @na_datalib_tag_ranges         = tag_ranges
                @na_datalib_storey_tag_map     = storey_tag_map
                @na_datalib_storey_element_map = storey_element_map
                @na_datalib_storey_tag_range   = storey_tag_range
                puts "    [GlbBuilder] DataLib tag ranges built: #{tag_ranges.size} export groups, #{storey_tag_map.size} storey containers, #{storey_element_map.size} storey elements"
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Fully Excluded Tag Names
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__FullyExcludedTagNames
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_fully_excluded || ALWAYS_EXCLUDED_LAYER_NAMES
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Treat-As-Untagged Tag Names
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__TreatAsUntaggedTagNames
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_treat_as_untagged || TREAT_AS_UNTAGGED_DEFAULTS
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Linework-Hidden Tag Names
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__LineworkHiddenTagNames
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_linework_hidden || LINEWORK_HIDDEN_DEFAULTS
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Profile-Line Excluded Name Tokens
        # ---------------------------------------------------------------
        # Names of Groups / Component definitions whose edge linework must be
        # omitted entirely from the LineworkModel GLB. Sourced from the
        # Components DataLib Na__DataLib__PipelineExclusions__ProfileLines list.
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__ProfileLineExcludedNames
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_profileline_excluded || []
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Profile-Line Exclusion Match Mode
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__ProfileLineMatchMode
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_profileline_matchmode || "contains"
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return ConsoleVerbose Logging Flag
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__LoggingConsoleVerbose
            self.Na__ExportConfig__LoadFromDataLib
            @na_logging_console_verbose
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return TextFileEnabled Logging Flag
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__LoggingTextFileEnabled
            self.Na__ExportConfig__LoadFromDataLib
            @na_logging_text_file_enabled
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return TextFileNamePattern String
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__LoggingTextFileNamePattern
            self.Na__ExportConfig__LoadFromDataLib
            @na_logging_text_file_name_pattern
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Exclusion Pattern Regex
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__ExclusionPattern
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_exclusion_pattern || EXCLUDED_LAYER_PATTERN
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Skip Ranges Array
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__SkipRanges
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_skip_ranges || SKIP_RANGES
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Tag Ranges Hash (replaces TAG_RANGES)
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__TagRanges
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_tag_ranges || TAG_RANGES
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Storey Tag Map (replaces STOREY_TAG_MAP)
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__StoreyTagMap
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_storey_tag_map || STOREY_TAG_MAP
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Storey Element Tag Map (replaces STOREY_ELEMENT_TAG_MAP)
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__StoreyElementTagMap
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_storey_element_map || STOREY_ELEMENT_TAG_MAP
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Return Storey Tag Range (replaces STOREY_TAG_RANGE)
        # ---------------------------------------------------------------
        def self.Na__ExportConfig__StoreyTagRange
            self.Na__ExportConfig__LoadFromDataLib
            @na_datalib_storey_tag_range || STOREY_TAG_RANGE.to_a
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Tag Range Definitions
    # -----------------------------------------------------------------------------
    
        # MODULE CONSTANTS | Tag Range Definitions for Segmentation
        # ------------------------------------------------------------
        # NOTE: 01__OrbitHelperCube Tag Purpose
        # The SketchUp tag "01__OrbitHelperCube" is used by the Camera Orbit tool
        # as the centre pivot point in the downstream Web 3D Model Viewer App.
        # This allows precise control of the camera rotation center for better UX.
        # ------------------------------------------------------------
        TAG_RANGES = {
            "01__OrbitHelperCube"                           => [1],                   # <-- Camera orbit pivot for Web 3D Viewer App
            "TrueVision__LandscapeEnvironment"              => [7, 9],                # <-- Landscape & Environment (range 8 is now SiteBoundaries)
            "TrueVision__SiteBoundaries"                    => [8],                   # <-- Site boundaries (fences, walls, site lines)
            "TrueVision__MainBuildingModel__Existing"       => [10],                  # <-- Existing Main Building Flag (whole building in simplified Massing Models)
            "TrueVision__MainBuildingModel__ExistingWalls"  => [11],                  # <-- Existing Building Walls
            "TrueVision__MainBuildingModel__ExistingFloors" => [12],                  # <-- Existing Building Floors
            "TrueVision__MainBuildingModel__ExistingRoofs"  => [13],                  # <-- Existing Building Roofs
            "TrueVision__MainBuildingModel__ExistingWindows"=> [14],                  # <-- Existing Building Windows
            "TrueVision__MainBuildingModel__ExistingDoors"  => [15],                  # <-- Existing Building Doors
            "TrueVision__MainBuildingModel__ExistingStairs" => [16],                  # <-- Existing Building Staircases
            "TrueVision__MainBuildingModel__ExistingFixtures" => [17],                # <-- Existing Building Fixtures and Fittings
            "TrueVision__MainBuildingModel__ExistingFurniture" => [18],               # <-- Existing Building Furniture
            "TrueVision__MainBuildingModel__ExistingInteriorDecor" => [19],           # <-- Existing Building Interior Decor
            "TrueVision__MainBuildingModel__Proposed"       => [20],                  # <-- Proposed Main Building Flag (whole building in simplified Massing Models)
            "TrueVision__MainBuildingModel__ProposedWalls"  => [21],                  # <-- Proposed Building Walls
            "TrueVision__MainBuildingModel__ProposedFloors" => [22],                  # <-- Proposed Building Floors
            "TrueVision__MainBuildingModel__ProposedRoofs"  => [23],                  # <-- Proposed Building Roofs
            "TrueVision__MainBuildingModel__ProposedWindows"=> [24],                  # <-- Proposed Building Windows
            "TrueVision__MainBuildingModel__ProposedDoors"  => [25],                  # <-- Proposed Building Doors (ADR assemblies)
            "TrueVision__MainBuildingModel__ProposedStairs" => [26],                  # <-- Proposed Building Staircases
            "TrueVision__MainBuildingModel__ProposedFixtures" => [27],                # <-- Proposed Building Fixtures and Fittings
            "TrueVision__MainBuildingModel__ProposedFurniture" => [28],               # <-- Proposed Building Furniture
            "TrueVision__MainBuildingModel__ProposedInteriorDecor" => [29],           # <-- Proposed Building Interior Decor
            "TrueVision__GroundFloorFurniture"              => (30..38),              # <-- Ground Floor Furniture
            "TrueVision__GroundFloorDecor"                  => [39],                  # <-- Ground Floor High Detail
            "TrueVision__FirstFloorFurniture"               => (40..48),              # <-- First Floor Furniture
            "TrueVision__FirstFloorDecor"                   => [49],                  # <-- First Floor High Detail
            "TrueVision__Vegetation"                        => (50..59),              # <-- Vegetation
            "TrueVision__SceneContextual"                   => (60..70)               # <-- Scene Context (people, vehicles)
        }
        SKIP_RANGES             =   [0, 2, 3, 4, 5, 6]                            # <-- Ignored tags - DO NOT EXPORT (tag 01 is now exported as OrbitHelperCube)
        MAX_NESTING_DEPTH       =   4                                             # <-- Maximum nesting depth for validation (4 to support storey container nesting)
        
        # ------------------------------------------------------------
    
        # MODULE CONSTANTS | Storey Container Detection and Export
        # ------------------------------------------------------------
        # Storey containers are top-level groups/components tagged with 90-93.
        # When detected, child entities inside are organized per-element and
        # exported with storey-prefixed filenames instead of MainBuildingModel.
        # When NO storey containers exist, the flat TAG_RANGES export is used
        # unchanged for full backward compatibility with simple massing models.
        # ------------------------------------------------------------
        STOREY_TAG_RANGE            =   (90..93)                                   # <-- Storey container tag numbers
        STOREY_TAG_MAP = {
            90 => "Storey__GroundFloor",                                           # <-- Ground Floor Top Grouping Level
            91 => "Storey__FirstFloor",                                            # <-- First Floor Top Grouping Level
            92 => "Storey__SecondFloor",                                           # <-- Second Floor Top Grouping Level
            93 => "Storey__ThirdFloor"                                             # <-- Third Floor Top Grouping Level
        }
        STOREY_ELEMENT_TAG_MAP = {
            7  => "LandscapeEnvironment",                                          # <-- Landscape & Environment
            8  => "SiteBoundaries",                                                # <-- Site boundaries (fences, walls, site lines)
            9  => "LandscapeEnvironment",                                          # <-- Landscape & Environment
            11 => "ExistingWalls",                                                 # <-- Existing Building Walls
            12 => "ExistingFloors",                                                # <-- Existing Building Floors
            13 => "ExistingRoofs",                                                 # <-- Existing Building Roofs
            14 => "ExistingWindows",                                               # <-- Existing Building Windows
            15 => "ExistingDoors",                                                 # <-- Existing Building Doors
            16 => "ExistingStairs",                                                # <-- Existing Building Staircases
            17 => "ExistingFixtures",                                              # <-- Existing Building Fixtures and Fittings
            18 => "ExistingFurniture",                                             # <-- Existing Building Furniture
            19 => "ExistingInteriorDecor",                                         # <-- Existing Building Interior Decor
            21 => "ProposedWalls",                                                 # <-- Proposed Building Walls
            22 => "ProposedFloors",                                                # <-- Proposed Building Floors
            23 => "ProposedRoofs",                                                 # <-- Proposed Building Roofs
            24 => "ProposedWindows",                                               # <-- Proposed Building Windows
            25 => "ProposedDoors",                                                 # <-- Proposed Building Doors
            26 => "ProposedStairs",                                                # <-- Proposed Building Staircases
            27 => "ProposedFixtures",                                              # <-- Proposed Building Fixtures and Fittings
            28 => "ProposedFurniture",                                             # <-- Proposed Building Furniture
            29 => "ProposedInteriorDecor"                                          # <-- Proposed Building Interior Decor
        }
        # ------------------------------------------------------------
    
        # MODULE CONSTANTS | GLB Format Constants
        # ------------------------------------------------------------
        GLB_MAGIC               =   0x46546C67                                    # <-- "glTF" in ASCII
        GLB_VERSION             =   2                                             # <-- glTF 2.0 version
        GLB_CHUNK_TYPE_JSON     =   0x4E4F534A                                    # <-- "JSON" chunk type
        GLB_CHUNK_TYPE_BIN      =   0x004E4942                                    # <-- "BIN\0" chunk type
        # ------------------------------------------------------------
    
        # MODULE CONSTANTS | File Paths
        # ------------------------------------------------------------
        NA_PLUGIN_ROOT = File.dirname(__FILE__).freeze                            # <-- Module root directory (…/Plugins/Na__TrueVision__WhitecardModel__GlbBuilderUtility__Modules__)
        # NOTE: The top-level loader script for this utility lives ONE LEVEL UP in the SketchUp Plugins folder:
        #       File.join(File.dirname(NA_PLUGIN_ROOT), 'Na__TrueVision__GlbBuilderUtility__Loader.rb')
        # ------------------------------------------------------------
    
        # MODULE VARIABLES | State Management
        # ------------------------------------------------------------
        @export_dialog          =   nil                                           # <-- HTML dialog for export options
        @export_selection_only  =   false                                         # <-- Flag for selection-only export
        @downscale_textures     =   false                                         # <-- Set by UI: downscale textures > MAX_TEXTURE_SIZE
        @excluded_layers        =   []                                            # <-- Array of excluded layer names
        @material_map           =   {}                                            # <-- Material to index mapping
        @texture_map            =   {}                                            # <-- Texture to index mapping
        @image_map              =   {}                                            # <-- Image data mapping
        @progress_dialog        =   nil                                           # <-- Progress dialog
        @validation_errors      =   []                                            # <-- Validation error messages
        @texture_cache_folder   =   File.join(Sketchup.temp_dir, "glb_texture_cache")  # <-- Temp cache folder for textures
        @texture_cache          =   {}                                            # <-- Hash to track cached texture paths
        @menu_registered        =   false                                         # <-- Tracks whether the Extensions menu entry has been created
        # ------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Entry Points (Public API)
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Start Export Process (called from menu)
        # ---------------------------------------------------------------
        def self.Na__PublicApi__StartExport
            puts "DEBUG: Na__PublicApi__StartExport called"
            begin
                self.Na__ExportCore__StartExport
            rescue => e
                puts "ERROR in Na__PublicApi__StartExport: #{e.message}"
                puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
                UI.messagebox("Export error: #{e.message}\n\nCheck Ruby Console for details.")
            end
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Perform Export (called from UI callback)
        # ---------------------------------------------------------------
        def self.Na__PublicApi__PerformExport(export_dir)
            self.Na__ExportCore__PerformExport(export_dir)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Standardised Tags From Index (called from UI or menu)
        # ---------------------------------------------------------------
        def self.Na__PublicApi__CreateStandardisedTags
            self.Na__TagsManager__CreateStandardisedTags
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Quick Reference: Supported Ruby Methods for Texture Handling
    # -----------------------------------------------------------------------------
    
    # Texture Handling Quick Reference – SketchUp 2025

    # ----------------------------------------
# 
    # | Method / Class                            | Description                                      | Params             | Returns       | Notes / Usage                                            |
    # |----------------------------------------   |--------------------------------------------------|--------------------|---------------|----------------------------------------------------------|
    # | `Texture#image_rep(colorized=false)`      | Gets texture pixel data as `ImageRep`.           | `colorized` (Bool) | `ImageRep`    | Best method for 2025+ PBR materials. Use for extraction. |
    # | `ImageRep#save_file(filepath)`            | Saves `ImageRep` to disk as PNG or JPG.          | `filepath` (String)| `Boolean`     | For caching extracted textures.                          |
    # | `Texture#write(filepath, colorize=false)` | Legacy texture-to-file method.                   | `filepath`, `Bool` | `Boolean`     | Deprecated in 2025+. Use only for fallback.              |
    # | `Material#texture`                        | Gets assigned texture.                           | –                  | `Texture/nil` | Use `valid?` check before accessing.                     |
    # | `Material#color`                          | Returns material's fallback RGB.                 | –                  | `Color`       | Use to create solid-colour image if no texture present.  |
    # | `Texture#valid?`                          | Confirms texture is valid and usable.            | –                  | `Boolean`     | Always check before using texture.                       |
    # | `Texture#filename`                        | Gets texture file name.                          | –                  | `String`      | Useful for cache naming / hashing.                       |
    # | `Texture#image_width` / `#image_height`   | Gets texture pixel size.                         | –                  | `Integer`     | For validation or resizing logic.                        |
    # | `Sketchup.temp_dir`                       | Gets system temp folder path.                    | –                  | `String`      | Store cache files here (e.g. GLB texture cache).         |
    # | `File.exist?(path)`                       | Checks if file exists at given path.             | `path` (String)    | `Boolean`     | For checking if cache already exists.                    |
    # | `File.binread(path)`                      | Loads binary file data from disk.                | `path` (String)    | `String`      | Use for buffer insertion (e.g. GLB export).              |
    # | `File.delete(path)`                       | Deletes file from disk.                          | `path` (String)    | `Integer`     | Use to clean up after export.                            |

    # endregion -------------------------------------------------------------------
    
    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
