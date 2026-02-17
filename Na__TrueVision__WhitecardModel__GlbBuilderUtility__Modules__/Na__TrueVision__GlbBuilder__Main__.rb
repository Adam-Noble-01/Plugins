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
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__'
require_relative 'Na__TrueVision__GlbBuilder__EngineCore__LineworkModelHandling__'
require_relative 'Na__TrueVision__GlbBuilder__UserInterface__'
require_relative 'Na__TrueVision__GlbBuilder__DynamicReloaderPluginUtil__'

module TrueVision3D
    module GlbBuilderUtility
    
    # -----------------------------------------------------------------------------
    # REGION | Module Constants and Configuration
    # -----------------------------------------------------------------------------
    
        # MODULE CONSTANTS | Export Configuration and Thresholds
        # ------------------------------------------------------------
        MAX_TEXTURE_SIZE            =   1024                                      # <-- Maximum texture dimension before downscaling
        TEXTURE_SCALE_FACTOR        =   0.25                                      # <-- Scale factor for texture downscaling (25%)
        EXCLUDED_LAYER_PATTERN      =   /^TrueVision_.*_DoNotExportGLTF$/         # <-- Regex pattern for excluded layers
        EXCLUDED_LAYER_DESCRIPTION  =   "TrueVision_*_DoNotExportGLTF".freeze     # <-- Human-readable description for excluded layers
        INCHES_TO_METERS            =   0.0254                                    # <-- Unit conversion factor: inches → meters
        DEFAULT_EXPORT_NAME         =   "SketchUpExport"                          # <-- Default filename for exports
        GLB_FILE_EXTENSION          =   ".glb"                                    # <-- GLB file extension
        MESH_MODEL_SUFFIX           =   "__MeshModel__"                           # <-- Suffix for mesh GLB (face geometry)
        LINEWORK_MODEL_SUFFIX       =   "__LineworkModel__"                       # <-- Suffix for linework GLB (edge geometry)
        # ------------------------------------------------------------
    
        # MODULE CONSTANTS | Tag Range Definitions for Segmentation
        # ------------------------------------------------------------
        # NOTE: 01__OrbitHelperCube Tag Purpose
        # The SketchUp tag "01__OrbitHelperCube" is used by the Camera Orbit tool
        # as the centre pivot point in the downstream Web 3D Model Viewer App.
        # This allows precise control of the camera rotation center for better UX.
        # ------------------------------------------------------------
        TAG_RANGES = {
            "01__OrbitHelperCube"                   => [1],                       # <-- Camera orbit pivot for Web 3D Viewer App
            "NaModel__LandscapeEnvironment"         => (7..9),                    # <-- Landscape & Environment
            "NaModel__MainBuildingModel__Existing"  => (10..19),                  # <-- Existing Main Building
            "NaModel__MainBuildingModel__Proposed"  => (20..29),                  # <-- Proposed Main Building
            "NaModel__GroundFloorFurniture"         => (30..38),                  # <-- Ground Floor Furniture
            "NaModel__GroundFloorDecor"             => [39],                      # <-- Ground Floor High Detail
            "NaModel__FirstFloorFurniture"          => (40..48),                  # <-- First Floor Furniture
            "NaModel__FirstFloorDecor"              => [49],                      # <-- First Floor High Detail
            "NaModel__Vegetation"                   => (50..59),                  # <-- Vegetation
            "NaModel__SceneContextual"              => (60..70)                   # <-- Scene Context (people, vehicles)
        }
        SKIP_RANGES             =   [0, 2, 3, 4, 5, 6]                            # <-- Ignored tags - DO NOT EXPORT (tag 01 is now exported as OrbitHelperCube)
        MAX_NESTING_DEPTH       =   3                                             # <-- Maximum nesting depth for validation
        
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
        @downscale_textures     =   false                                         # <-- DEBUG: Texture processing disabled until core geometry engine is resolved
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
