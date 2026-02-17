# =============================================================================
# VALEDESIGNSUITE - GLB BUILDER UTILITY
# =============================================================================
#
# FILE       : TrueVisionApp__GlbBuilderUtility.rb
# NAMESPACE  : ValeDesignSuite
# MODULE     : GLBBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Export SketchUp models to GLB format with texture optimization
# CREATED    : 2025
#
# DESCRIPTION:
# - Exports SketchUp models to GLB format with proper binary formatting
# - Includes material and texture export with automatic optimization
# - Excludes entities on layers matching "TrueVision_{wildcard}_DoNotExportGLTF"
# - Provides options for exporting selection only or entire model
# - Integrates with ValeDesignSuite plugin ecosystem
#
# EXPORT METHOD (v1.0.4+):
# - Uses "apply transforms" approach via temporary explosion
# - All nested groups/components are exploded to get true global coordinates
# - Faces are grouped by material and layer for efficient mesh creation
# - Original model is restored via single undo operation
# - Ensures perfect coordinate accuracy between SketchUp and GLB output
#
# MATERIAL HANDLING SYSTEM (for downstream texture switching):
# - SketchUp material names are preserved exactly in GLB output using material.display_name
# - Handles face materials, per-object materials, and nested component materials
# - All materials logged to console during export for debugging
# - @material_map maintains consistent material-to-index mapping across export process
# - Enables TrueVision texture switcher scripts to match materials by original SketchUp names
#
# POSITIONED TEXTURE SUPPORT (v1.0.6+):
# - Automatically detects textures positioned using SketchUp's texture positioning tool
# - Handles rotated, scaled, skewed, and translated textures correctly
# - Uses dual-method approach: standard UVHelper for normal textures, enhanced extraction for positioned
# - Preserves all texture transformations applied via right-click > Texture > Position
# - Supports perspective-corrected UV coordinates with proper Q-component handling
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
# DEVELOPMENT LOG:
# 12-Jul-2025 - Version 1.0.0
# - Initial implementation with core GLB export functionality
# - Texture downscaling feature for optimized file sizes
# - Layer filtering system for TrueVision exclusions
#
# 12-Jul-2025 - Version 1.0.1
# - Complete rewrite with proper GLB binary format
# - Full material and texture support
# - Correct GLTF 2.0 JSON structure
#
# 12-Jul-2025 - Version 1.0.2
# - Fixed coordinate system conversion (Z-up to Y-up)
# - Fixed unit conversion (inches to meters)
# - Fixed texture UV mapping and material colorization
# - Added comprehensive progress tracking
#
# 12-Jan-2025 - Version 1.0.3
# - Implemented smart leaf container detection for manifold validation
# - Added intelligent parent/child container analysis to prevent false positives
# - Only validates groups/components containing raw geometry (faces/edges)
# - Skips validation on parent containers that only hold nested objects
# - Added material handling documentation for downstream texture switching
# - Enhanced validation feedback with clear container type identification
# - Improved support for complex nested furniture and architectural models
#
# 13-Jan-2025 - Version 1.0.4
# - Complete rewrite using "apply transforms" explosion approach
# - Eliminates complex transformation matrix calculations
# - All nested hierarchies temporarily exploded for true global coordinates
# - Faces grouped by material and layer for optimized mesh generation
# - Single undo operation restores original model state
# - Guarantees pixel-perfect coordinate accuracy in GLB output
# - Simplified codebase with improved maintainability
#
# 13-Jan-2025 - Version 1.0.5
# - Fixed corruption issue when running script multiple times in one session
# - Added comprehensive state reset function to clear all module variables
# - Eliminates texture index mismatches between exports
# - Ensures clean state for each export without requiring SketchUp restart
#
# 13-Jan-2025 - Version 1.0.6
# - Added positioned texture support for SketchUp's texture positioning tool
# - Dual-method UV extraction: standard for normal textures, enhanced for positioned
# - Automatic detection of positioned textures (rotated, scaled, skewed, translated)
# - Proper perspective correction using UVQ coordinates with Q-component handling
# - Maintains backward compatibility with existing texture workflows
# - Enhanced debugging output to distinguish between standard and positioned textures
#
# =============================================================================

require 'json'                                                                    # <-- JSON parsing for dialog parameters
require 'fileutils'                                                               # <-- File operations for texture caching

module ValeDesignSuite
    module GLBBuilderUtility
    
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
    
    # -----------------------------------------------------------------------------
    # REGION | Module Constants and Configuration
    # -----------------------------------------------------------------------------
    
        # MODULE CONSTANTS | Export Configuration and Thresholds
        # ------------------------------------------------------------
        MAX_TEXTURE_SIZE        =   1024                                          # <-- Maximum texture dimension before downscaling
        TEXTURE_SCALE_FACTOR    =   0.25                                          # <-- Scale factor for texture downscaling (50%)
        EXCLUDED_LAYER_PATTERN  =   /^TrueVision_.*_DoNotExportGLTF$/             # <-- Regex pattern for excluded layers
        DEFAULT_EXPORT_NAME     =   "SketchUpExport"                             # <-- Default filename for exports
        GLB_FILE_EXTENSION      =   ".glb"                                        # <-- GLB file extension
        # ------------------------------------------------------------
    
        # MODULE CONSTANTS | Tag Range Definitions for Segmentation
        # ------------------------------------------------------------
        TAG_RANGES = {
            "LandscapeEnvironment"      => (5..9),                                # <-- Landscape & Environment
            "MainBuildingModel"         => (10..19),                              # <-- Main Building
            "GroundFloorFurniture"      => (30..38),                              # <-- Ground Floor Furniture
            "GroundFloorDecor"          => [39],                                  # <-- Ground Floor High Detail
            "FirstFloorFurniture"       => (40..48),                              # <-- First Floor Furniture
            "FirstFloorDecor"           => [49],                                  # <-- First Floor High Detail
            "SceneContextual"           => (60..70)                               # <-- Scene Context (people, vehicles)
        }
        SKIP_RANGES             =   (1..4)                                        # <-- Modeling utility items - DO NOT EXPORT
        MAX_NESTING_DEPTH       =   3                                             # <-- Maximum nesting depth for validation
        
        # ------------------------------------------------------------
    
        # MODULE CONSTANTS | GLB Format Constants
        # ------------------------------------------------------------
        GLB_MAGIC               =   0x46546C67                                    # <-- "glTF" in ASCII
        GLB_VERSION             =   2                                             # <-- glTF 2.0 version
        GLB_CHUNK_TYPE_JSON     =   0x4E4F534A                                    # <-- "JSON" chunk type
        GLB_CHUNK_TYPE_BIN      =   0x004E4942                                    # <-- "BIN\0" chunk type
        # ------------------------------------------------------------
    
        # MODULE VARIABLES | State Management
        # ------------------------------------------------------------
        @export_dialog          =   nil                                           # <-- HTML dialog for export options
        @export_selection_only  =   false                                         # <-- Flag for selection-only export
        @downscale_textures     =   true                                          # <-- Flag for texture downscaling
        @excluded_layers        =   []                                            # <-- Array of excluded layer names
        @material_map           =   {}                                            # <-- Material to index mapping
        @texture_map            =   {}                                            # <-- Texture to index mapping
        @image_map              =   {}                                            # <-- Image data mapping
        @progress_dialog        =   nil                                           # <-- Progress dialog
        @validation_errors      =   []                                            # <-- Validation error messages
        @texture_cache_folder   =   File.join(Sketchup.temp_dir, "glb_texture_cache")  # <-- Temp cache folder for textures
        @texture_cache          =   {}                                            # <-- Hash to track cached texture paths
        # ------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Core Export Functionality
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Reset All Module State Variables
        # ---------------------------------------------------------------
        def self.reset_export_state
            puts "    Resetting module state for new export..."
            
            # Clear all mapping variables
            @material_map           = {}                                          # <-- Material to index mapping
            @texture_map            = {}                                          # <-- Texture to index mapping
            @image_map              = {}                                          # <-- Image data mapping
            @texture_cache          = {}                                          # <-- Texture cache (this was missing!)
            
            # Clear validation and layer data
            @validation_errors      = []                                          # <-- Validation error messages
            @excluded_layers        = []                                          # <-- Array of excluded layer names
            
            # Clear any progress tracking
            @last_reported_percentage = nil                                       # <-- Reset progress tracking
            
            puts "    Module state reset complete"
        end
        # ---------------------------------------------------------------
    
        # FUNCTION | Initialize GLB Export Process
        # ------------------------------------------------------------
        def self.start_export
            model = Sketchup.active_model                                         # Get active model
            
            # Check if there's anything to export using correct SketchUp API
            if model.active_entities.length == 0
                UI.messagebox("No entities to export in the current model.")      # Alert user
                return false
            end
            
            # Reset state at the very beginning
            reset_export_state                                                    # Comprehensive state reset
            
            identify_excluded_layers(model)                                       # Identify layers to exclude
            
            # Skip validation for explosion-based export approach
            # The explosion method works with any geometry, not just manifold solids
            puts "\n=== Starting TrueVision GLB Export (Simplified Method) ==="    # Console header
            puts "Using explosion/regrouping for accurate global coordinates"
            
            # Create texture cache folder if it doesn't exist
            Dir.mkdir(@texture_cache_folder) unless Dir.exist?(@texture_cache_folder)
            
            show_export_dialog                                                     # Show export options dialog
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Validate All Model Entities are Watertight - Smart Leaf Detection
        # ---------------------------------------------------------------
        def self.validate_model_watertight(model)
            @validation_errors = []                                                # Clear errors
            total_entities = count_all_entities(model.active_entities)            # Count leaf containers only
            checked_entities = 0                                                   # Progress counter
            
            puts "Smart validation: Checking #{total_entities} leaf containers (ignoring parent containers)..."
            puts "  → Only validating groups/components that contain raw geometry"
            puts "  → Skipping parent containers that only hold nested objects"
            puts "  → Maximum nesting depth: #{MAX_NESTING_DEPTH} levels\n"
            
            # Validate all entities recursively with smart detection
            validate_result = validate_entities_recursive(model.active_entities, checked_entities, total_entities)
            
            if @validation_errors.any?
                puts "\n=== VALIDATION ERRORS ==="
                @validation_errors.each { |error| puts "  - #{error}" }
                puts "\nNote: Only leaf containers (containing raw geometry) are validated."
                puts "Parent containers that only hold nested objects are ignored."
                puts "=== END VALIDATION ERRORS ===\n"
                return false
            end
            
            puts "\n✓ All leaf containers validated successfully!"                # Success message
            puts "  → #{total_entities} leaf containers checked"
            puts "  → Parent containers automatically skipped\n"
            true
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Recursively Validate Entities - Smart Leaf Container Detection
        # ---------------------------------------------------------------
        def self.validate_entities_recursive(entities, checked_count, total_count, depth = 0)
            return checked_count if depth > MAX_NESTING_DEPTH                      # Prevent infinite recursion
            
            entities.each do |entity|
                next if entity_excluded?(entity)                                   # Skip excluded
                
                case entity
                when Sketchup::Group
                    if is_leaf_container?(entity)
                        # Only validate groups that contain raw geometry (leaf containers)
                        if entity.manifold?
                            checked_count += 1
                            report_progress("Validating", checked_count, total_count)
                            puts "      ✓ Leaf group '#{entity.name || 'Unnamed'}' is solid"
                        else
                            entity_name = entity.name && !entity.name.empty? ? entity.name : 'Unnamed'
                            @validation_errors << "Group '#{entity_name}' contains geometry but is not solid"
                        end
                    else
                        # Parent container - skip validation but traverse children
                        puts "      → Skipping parent group '#{entity.name || 'Unnamed'}' (contains only nested containers)"
                    end
                    
                    # Always traverse nested entities regardless of validation
                    checked_count = validate_entities_recursive(entity.entities, checked_count, total_count, depth + 1)
                    
                when Sketchup::ComponentInstance
                    if is_leaf_container?(entity)
                        # Only validate components that contain raw geometry (leaf containers)
                        if entity.manifold?
                            checked_count += 1
                            report_progress("Validating", checked_count, total_count)
                            puts "      ✓ Leaf component '#{entity.name || entity.definition.name || 'Unnamed'}' is solid"
                        else
                            entity_name = entity.name && !entity.name.empty? ? entity.name : (entity.definition.name || 'Unnamed')
                            @validation_errors << "Component '#{entity_name}' contains geometry but is not solid"
                        end
                    else
                        # Parent container - skip validation but traverse children
                        puts "      → Skipping parent component '#{entity.name || entity.definition.name || 'Unnamed'}' (contains only nested containers)"
                    end
                    
                    # Always traverse nested entities regardless of validation
                    definition = entity.respond_to?(:definition) ? entity.definition : entity
                    checked_count = validate_entities_recursive(definition.entities, checked_count, total_count, depth + 1)
                end
            end
            
            checked_count
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Check if Container is a Leaf (Contains Raw Geometry)
        # ---------------------------------------------------------------
        def self.is_leaf_container?(entity)
            case entity
            when Sketchup::Group
                return contains_raw_geometry?(entity.entities)
            when Sketchup::ComponentInstance
                definition = entity.respond_to?(:definition) ? entity.definition : entity
                return contains_raw_geometry?(definition.entities)
            else
                return false
            end
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Check if Entities Collection Contains Raw Geometry
        # ---------------------------------------------------------------
        def self.contains_raw_geometry?(entities)
            entities.each do |entity|
                # If we find faces or edges, this is a leaf container
                return true if entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
                
                # If we find other entity types (curves, etc.) that represent geometry
                return true if entity.respond_to?(:curve) && entity.curve
            end
            
            # No raw geometry found - this is a parent container
            false
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Count Leaf Entities That Need Validation
        # ---------------------------------------------------------------
        def self.count_all_entities(entities, depth = 0)
            count = 0
            return count if depth > MAX_NESTING_DEPTH                              # Prevent infinite recursion
            
            entities.each do |entity|
                next if entity_excluded?(entity)
                
                case entity
                when Sketchup::Group
                    if is_leaf_container?(entity)
                        count += 1                                                 # Only count leaf containers
                    end
                    count += count_all_entities(entity.entities, depth + 1)       # Always traverse children
                when Sketchup::ComponentInstance
                    if is_leaf_container?(entity)
                        count += 1                                                 # Only count leaf containers
                    end
                    definition = entity.respond_to?(:definition) ? entity.definition : entity
                    count += count_all_entities(definition.entities, depth + 1)   # Always traverse children
                end
            end
            count
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Report Progress to Console
        # ---------------------------------------------------------------
        def self.report_progress(operation, current, total)
            percentage = (current.to_f / total * 100).to_i
            if percentage % 10 == 0 && percentage != @last_reported_percentage
                puts "#{operation}: #{percentage}% complete (#{current}/#{total})"
                @last_reported_percentage = percentage
            end
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Identify Layers Matching Exclusion Pattern
        # ---------------------------------------------------------------
        def self.identify_excluded_layers(model)
            @excluded_layers = []                                                  # Reset excluded layers array
            
            model.layers.each do |layer|
                if layer.name =~ EXCLUDED_LAYER_PATTERN                           # Check against pattern
                    @excluded_layers << layer.name                                 # Add to excluded list
                end
            end
            
            puts "Excluded layers: #{@excluded_layers.join(', ')}" if @excluded_layers.any?
        end
        # ---------------------------------------------------------------
    
        # FUNCTION | Perform GLB Export with Configuration
        # ---------------------------------------------------------------
        def self.perform_export(export_dir)
            model = Sketchup.active_model                                         # Get active model
            
            # Reset ALL state variables before export
            reset_export_state                                                    # Comprehensive state reset
            
            # Re-identify excluded layers after reset
            identify_excluded_layers(model)                                       # Identify layers to exclude
            
            # Get tag-based entity groups
            tag_groups = organize_entities_by_tags(model)                         # Organize by tags
            
            if tag_groups.length == 0
                puts "\n=== NO ENTITIES FOUND WITH PROPER TAG RANGES ==="
                puts "Please ensure your objects are on layers with names starting with:"
                puts "  05-09 = Landscape & Environment (exports as 'LandscapeEnvironment.glb')"
                puts "  10-19 = Main Building (exports as 'MainBuildingModel.glb')"
                puts "  30-38 = Ground Floor Furniture (exports as 'GroundFloorFurniture.glb')"
                puts "  39    = Ground Floor Decor (exports as 'GroundFloorDecor.glb')"
                puts "  40-48 = First Floor Furniture (exports as 'FirstFloorFurniture.glb')"
                puts "  49    = First Floor Decor (exports as 'FirstFloorDecor.glb')"
                puts "  60-70 = Scene Context (exports as 'SceneContextual.glb')"
                puts "\nExample layer names: '10_Building', '30_Chairs', '40_Tables', etc."
                puts "================================================\n"
                
                UI.messagebox("No entities found with proper tag ranges for export.\n\nPlease check the Ruby Console for required layer naming.")
                return false
            end
            
            # Show what will be exported
            puts "\n=== Export Plan ==="
            tag_groups.each do |filename, entities|
                puts "  #{filename}.glb - #{entities.length} top-level entities"
            end
            puts "=== End Export Plan ===\n"
            
            model.start_operation("GLB Export", true)                            # Start operation for undo
            
            begin
                success_count = 0
                tag_groups.each do |base_filename, entities|
                    filepath = File.join(export_dir, "#{base_filename}.glb")     # Build filepath
                    puts "\nExporting: #{base_filename}.glb..."
                    
                    # Use the new simplified export method
                    if export_entities_to_glb_simplified(entities, filepath)
                        success_count += 1
                    else
                        puts "  ERROR: Failed to export #{base_filename}.glb"
                    end
                end
                
                model.commit_operation                                             # Commit the operation
                
                # Clean up texture cache
                cleanup_texture_cache                                              # Remove temporary files
                
                # Open output folder
                if success_count > 0
                    open_folder(export_dir)                                        # Open in file explorer
                    UI.messagebox("GLB export completed!\n\n#{success_count} files exported to:\n#{export_dir}")
                else
                    UI.messagebox("Export failed. Please check the console for errors.")
                end
                
            rescue => e
                model.abort_operation                                              # Abort on error
                UI.messagebox("Export error: #{e.message}")                       # Show error message
                puts "GLB Export Error: #{e.message}\n#{e.backtrace.join("\n")}"  # Log full error
                false
            end
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Organize Entities by Tag Ranges
        # ---------------------------------------------------------------
        def self.organize_entities_by_tags(model)
            tag_groups = {}                                                        # Initialize groups
            found_layers = {}                                                      # Track found layer names
            
            puts "\n=== Analyzing model layers ==="
            
            model.active_entities.each do |entity|
                next if entity_excluded?(entity)                                   # Skip excluded
                next unless entity.respond_to?(:layer)                             # Skip if no layer
                
                # Track all layer names found
                layer_name = entity.layer.name
                found_layers[layer_name] ||= 0
                found_layers[layer_name] += 1
                
                # Get tag number from layer name
                tag_match = layer_name.match(/^(\d+)/)                           # Match leading digits
                next unless tag_match                                              # Skip if no number
                
                tag_number = tag_match[1].to_i                                    # Get tag number
                
                # Skip if in skip range
                if SKIP_RANGES.include?(tag_number)
                    puts "  Skipping layer '#{layer_name}' (tag #{tag_number} is in skip range 1-4)"
                    next
                end
                
                # Find matching range
                TAG_RANGES.each do |group_name, range|
                    if range.is_a?(Range) && range.include?(tag_number)
                        tag_groups[group_name] ||= []
                        tag_groups[group_name] << entity
                        puts "  Found entity on layer '#{layer_name}' -> #{group_name}.glb"
                        break
                    elsif range.is_a?(Array) && range.include?(tag_number)
                        tag_groups[group_name] ||= []
                        tag_groups[group_name] << entity
                        puts "  Found entity on layer '#{layer_name}' -> #{group_name}.glb"
                        break
                    end
                end
            end
            
            # Report all layers found
            puts "\n=== All layers in model ==="
            found_layers.each do |layer_name, count|
                puts "  '#{layer_name}' (#{count} entities)"
            end
            puts "=========================\n"
            
            # Remove empty groups using correct API
            tag_groups.delete_if { |_, entities| entities.length == 0 }
            
            tag_groups
        end
        # ---------------------------------------------------------------
    
        # HELPER FUNCTION | Open Folder in File Explorer
        # ---------------------------------------------------------------
        def self.open_folder(path)
            if Sketchup.platform == :platform_win
                system("explorer \"#{path.gsub('/', '\\')}\"")                    # Windows
            elsif Sketchup.platform == :platform_osx
                system("open \"#{path}\"")                                         # macOS
            else
                puts "Please navigate to: #{path}"                                # Linux/other
            end
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | GLB Binary Format Implementation
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Export Entities to GLB Format
        # ------------------------------------------------------------
        def self.export_entities_to_glb(entities, filepath)
            # Ensure filepath has GLB extension
            filepath += GLB_FILE_EXTENSION unless filepath.end_with?(GLB_FILE_EXTENSION)
            
            puts "  Initializing GLTF structure..."
            
            # Initialize GLTF data structure
            gltf = {
                "asset" => {
                    "version" => "2.0",                                           # <-- GLTF version
                    "generator" => "ValeDesignSuite GLB Builder v1.0.6"          # <-- Generator info
                },
                "scene" => 0,                                                     # <-- Default scene
                "scenes" => [{ "nodes" => [] }],                                  # <-- Scene array
                "nodes" => [],                                                     # <-- Node hierarchy
                "meshes" => [],                                                    # <-- Mesh data
                "accessors" => [],                                                 # <-- Data accessors
                "bufferViews" => [],                                               # <-- Buffer views
                "buffers" => [],                                                   # <-- Binary buffers
                "materials" => [],                                                 # <-- Materials
                "textures" => [],                                                  # <-- Textures
                "images" => [],                                                    # <-- Images
                "samplers" => []                                                   # <-- Texture samplers
            }
            
            # Binary buffer for vertex and image data
            binary_buffer = []                                                     # Binary data array
            
            # Collect all materials first
            collect_materials_from_entities(entities)                              # Find all materials
            
            # Create GLTF materials (including textures)
            create_gltf_materials(gltf, binary_buffer)                            # Convert materials
            
            puts "  Processing #{entities.length} entities..."
            
            # Process entities into GLTF structure
            process_entities_to_gltf(entities, gltf, binary_buffer)               # Convert to GLTF
            
            puts "  Generated: #{gltf['meshes'].length} meshes, #{gltf['materials'].length} materials, #{gltf['textures'].length} textures"
            puts "  Writing GLB file..."
            
            # Write GLB file
            write_glb_file(filepath, gltf, binary_buffer)                        # Save to file
            
            puts "  ✓ Export complete: #{File.basename(filepath)}"
            true
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Process Entities into GLTF Structure
        # ---------------------------------------------------------------
        def self.process_entities_to_gltf(entities, gltf, binary_buffer)
            total_entities = entities.length
            processed_count = 0
            
            # Create a root node for coordinate system conversion
            # This rotates -90 degrees around X axis to convert Z-up to Y-up
            root_node_index = gltf["nodes"].length
            gltf["nodes"] << {
                "name" => "Root_CoordSystemConversion",
                "rotation" => [-0.7071068, 0, 0, 0.7071068],  # -90° rotation around X axis (as quaternion)
                "children" => []
            }
            
            # Add root node to scene
            gltf["scenes"][0]["nodes"] = [root_node_index]
            
            entities.each_with_index do |entity, index|
                next if entity_excluded?(entity)                                   # Skip excluded
                
                # Report progress
                processed_count += 1
                entity_name = entity.respond_to?(:name) && !entity.name.empty? ? entity.name : entity.class.name
                puts "    Processing entity #{processed_count}/#{total_entities}: #{entity_name}"
                
                case entity
                when Sketchup::Group, Sketchup::ComponentInstance
                    node_index = process_group_or_component(entity, gltf, binary_buffer)
                    gltf["nodes"][root_node_index]["children"] << node_index if node_index  # Add to root node
                    
                when Sketchup::Face, Sketchup::Edge
                    # Create a mesh for loose geometry
                    mesh_data = extract_geometry_data([entity], nil)              # No instance material for loose geometry
                    if mesh_data && !mesh_data[:positions].empty?
                        mesh_index = add_mesh_to_gltf(mesh_data, gltf, binary_buffer)
                        
                        # Create node for mesh
                        node_index = gltf["nodes"].length                          # Get node index
                        gltf["nodes"] << {
                            "mesh" => mesh_index,                                  # <-- Mesh reference
                            "name" => "Geometry_#{node_index}"                    # <-- Node name
                        }
                        gltf["nodes"][root_node_index]["children"] << node_index  # Add to root node
                    end
                end
            end
            
            puts "    Processed #{processed_count} entities total"
        end
        # ---------------------------------------------------------------
    
        # FUNCTION | Export Entities to GLB Format (Simplified with Explosion)
        # ---------------------------------------------------------------
        def self.export_entities_to_glb_simplified(entities, filepath)
            # Ensure filepath has GLB extension
            filepath += GLB_FILE_EXTENSION unless filepath.end_with?(GLB_FILE_EXTENSION)
            
            puts "  Using explosion/regrouping strategy for accurate global coordinates..."
            
            model = Sketchup.active_model
            
            # Start a single operation that can be undone
            model.start_operation("GLB Export - Temporary Explosion", true)
            
            begin
                # Store original selection state
                original_selection = model.selection.to_a
                model.selection.clear
                
                # Step 1: Collect entities to process and their metadata
                entities_metadata = collect_entity_metadata(entities)
                
                # Step 2: Explode all nested hierarchies to get global coordinates
                exploded_faces = explode_all_to_global(entities)
                
                # Step 3: Group faces by material and layer
                face_groups = group_faces_by_properties(exploded_faces)
                
                # Step 4: Create glTF structure from grouped faces
                gltf, binary_buffer = create_gltf_from_face_groups(face_groups)
                
                # Step 5: Write GLB file
                write_glb_file(filepath, gltf, binary_buffer)
                
                # Step 6: Restore original model state (undo all explosions)
                model.abort_operation
                
                # Restore selection (filter out invalid entities)
                begin
                    valid_entities = original_selection.select { |entity| entity.valid? }
                    model.selection.clear
                    model.selection.add(valid_entities) unless valid_entities.empty?
                rescue => selection_error
                    puts "  Warning: Could not restore original selection: #{selection_error.message}"
                    model.selection.clear  # Just clear selection if restoration fails
                end
                
                puts "  ✓ Export complete with accurate global coordinates"
                return true
                
            rescue => e
                # Ensure we always restore the model on error
                model.abort_operation
                puts "  ERROR: Export failed - #{e.message}"
                puts "  #{e.backtrace.first(5).join("\n  ")}"
                puts "  Model restored to original state"
                return false
            end
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Collect Entity Metadata Before Explosion
        # ---------------------------------------------------------------
        def self.collect_entity_metadata(entities)
            metadata = []
            
            entities.each do |entity|
                next if entity_excluded?(entity)
                
                if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    metadata << {
                        :name => entity.respond_to?(:name) ? entity.name : "",
                        :layer => entity.layer.name,
                        :material => entity.material,
                        :transformation => entity.transformation
                    }
                end
            end
            
            metadata
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Explode All Nested Hierarchies to Global Space
        # ---------------------------------------------------------------
        def self.explode_all_to_global(entities)
            all_faces = []
            entities_to_process = entities.to_a
            max_iterations = 20  # Prevent infinite loops
            
            max_iterations.times do |iteration|
                puts "    Explosion pass #{iteration + 1}..."
                
                # Collect all groups and components to explode
                groups_to_explode = []
                
                Sketchup.active_model.active_entities.each do |entity|
                    if (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
                        unless entity_excluded?(entity)
                            groups_to_explode << entity
                        end
                    end
                end
                
                break if groups_to_explode.empty?  # Nothing left to explode
                
                puts "      Found #{groups_to_explode.length} containers to explode"
                
                # Explode each group/component
                groups_to_explode.each do |entity|
                    if entity.valid?
                        begin
                            exploded = entity.explode
                            if exploded
                                # Collect any faces from the explosion
                                exploded.each do |e|
                                    if e.is_a?(Sketchup::Face) && !entity_excluded?(e)
                                        all_faces << e
                                    end
                                end
                            end
                        rescue => e
                            puts "      Warning: Failed to explode entity: #{e.message}"
                        end
                    end
                end
            end
            
            # Also collect any faces that were already at the root level
            Sketchup.active_model.active_entities.each do |entity|
                if entity.is_a?(Sketchup::Face) && !entity_excluded?(entity)
                    all_faces << entity unless all_faces.include?(entity)
                end
            end
            
            puts "    Collected #{all_faces.length} faces in global coordinates"
            all_faces
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Group Faces by Material and Layer Properties
        # ---------------------------------------------------------------
        def self.group_faces_by_properties(faces)
            face_groups = {}
            
            faces.each do |face|
                next unless face.valid?
                
                # Get material (front or back)
                material = face.material || face.back_material
                material_name = material ? material.display_name : "Default"
                
                # Get layer name
                layer_name = face.layer.name
                
                # Create group key
                group_key = "#{layer_name}::#{material_name}"
                
                # Initialize group if needed
                face_groups[group_key] ||= {
                    :faces => [],
                    :material => material,
                    :layer_name => layer_name,
                    :positions => [],
                    :normals => [],
                    :uvs => [],
                    :indices => [],
                    :vertex_count => 0
                }
                
                # Add face to group
                face_groups[group_key][:faces] << face
            end
            
            puts "    Grouped faces into #{face_groups.length} material/layer combinations"
            face_groups
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Create glTF Structure from Face Groups
        # ---------------------------------------------------------------
        def self.create_gltf_from_face_groups(face_groups)
            # Initialize GLTF structure
            gltf = {
                "asset" => {
                    "version" => "2.0",
                    "generator" => "ValeDesignSuite GLB Builder v1.0.6 (Simplified)"
                },
                "scene" => 0,
                "scenes" => [{ "nodes" => [] }],
                "nodes" => [],
                "meshes" => [],
                "accessors" => [],
                "bufferViews" => [],
                "buffers" => [],
                "materials" => [],
                "textures" => [],
                "images" => [],
                "samplers" => []
            }
            
            binary_buffer = []
            
            # Collect all unique materials
            face_groups.each do |group_key, group_data|
                material = group_data[:material]
                if material && !@material_map.has_key?(material)
                    @material_map[material] = @material_map.length
                end
            end
            
            # Create GLTF materials
            create_gltf_materials(gltf, binary_buffer)
            
            # Process each face group
            face_groups.each do |group_key, group_data|
                puts "    Processing group: #{group_key}"
                
                # Extract vertex data from faces
                extract_global_face_data(group_data, gltf, binary_buffer)
                
                # Skip if no geometry
                next if group_data[:positions].empty?
                
                # Create mesh for this group
                mesh_index = add_mesh_to_gltf_simplified(group_data, gltf, binary_buffer)
                
                # Create node for this mesh
                node_index = gltf["nodes"].length
                gltf["nodes"] << {
                    "name" => group_key,
                    "mesh" => mesh_index
                }
                
                # Add to scene
                gltf["scenes"][0]["nodes"] << node_index
            end
            
            [gltf, binary_buffer]
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Add Mesh to GLTF (Simplified for Single Material)
        # ---------------------------------------------------------------
        def self.add_mesh_to_gltf_simplified(group_data, gltf, binary_buffer)
            mesh_index = gltf["meshes"].length
            
            # Get material index
            material_index = 0  # Default material
            if group_data[:material] && @material_map.has_key?(group_data[:material])
                material_index = @material_map[group_data[:material]]
            end
            
            # Create primitive
            primitive = {
                "attributes" => {},
                "material" => material_index,
                "mode" => 4  # TRIANGLES
            }
            
            # Add position accessor
            position_accessor = add_accessor(
                group_data[:positions], gltf, binary_buffer,
                5126, "VEC3", true, 34962  # FLOAT, VEC3, calc bounds, ARRAY_BUFFER
            )
            primitive["attributes"]["POSITION"] = position_accessor
            
            # Add normal accessor
            normal_accessor = add_accessor(
                group_data[:normals], gltf, binary_buffer,
                5126, "VEC3", false, 34962  # FLOAT, VEC3, no bounds, ARRAY_BUFFER
            )
            primitive["attributes"]["NORMAL"] = normal_accessor
            
            # Add UV accessor if we have UVs and material has texture
            if !group_data[:uvs].empty? && group_data[:material] && group_data[:material].texture
                uv_accessor = add_accessor(
                    group_data[:uvs], gltf, binary_buffer,
                    5126, "VEC2", false, 34962  # FLOAT, VEC2, no bounds, ARRAY_BUFFER
                )
                primitive["attributes"]["TEXCOORD_0"] = uv_accessor
            end
            
            # Add indices accessor
            if group_data[:indices].max < 65536
                indices_accessor = add_accessor(
                    group_data[:indices], gltf, binary_buffer,
                    5123, "SCALAR", false, 34963  # UNSIGNED_SHORT, SCALAR, ELEMENT_ARRAY_BUFFER
                )
            else
                indices_accessor = add_accessor(
                    group_data[:indices], gltf, binary_buffer,
                    5125, "SCALAR", false, 34963  # UNSIGNED_INT, SCALAR, ELEMENT_ARRAY_BUFFER
                )
            end
            primitive["indices"] = indices_accessor
            
            # Create mesh
            mesh = {
                "name" => "Mesh_#{mesh_index}",
                "primitives" => [primitive]
            }
            
            gltf["meshes"] << mesh
            mesh_index
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Extract Global Face Data (Already in World Coordinates)
        # ---------------------------------------------------------------
        def self.extract_global_face_data(group_data, gltf, binary_buffer)
            vertex_count = group_data[:vertex_count]
            
            group_data[:faces].each_with_index do |face, face_index|
                next unless face.valid?
                
                # Report progress
                if face_index % 100 == 0
                    puts "      Processing face #{face_index + 1}/#{group_data[:faces].length}"
                end
                
                # Get material
                material = group_data[:material]
                
                # Get UVHelper if material has texture
                uv_helper = nil
                if material && material.texture && material.texture.valid?
                    if face.material && face.material == material
                        uv_helper = face.get_UVHelper(true, true)
                    elsif face.back_material && face.back_material == material
                        uv_helper = face.get_UVHelper(false, false)
                    end
                end
                
                # Get face mesh
                mesh = face.mesh(7)  # Full mesh with normals
                
                # Process each polygon
                (1..mesh.count_polygons).each do |poly_index|
                    polygon_points = mesh.polygon_at(poly_index)
                    next unless polygon_points.length == 3  # Only triangles
                    
                    face_indices = []
                    
                    polygon_points.each do |point_index|
                        # Get vertex position - already in global coordinates
                        position = mesh.point_at(point_index)
                        normal = mesh.normal_at(point_index)
                        
                        # Convert to glTF coordinate system
                        # SketchUp: X=right, Y=forward, Z=up
                        # glTF: X=right, Y=up, Z=forward
                        gltf_pos = [
                            position.x * 0.0254,      # X stays, convert to meters
                            position.z * 0.0254,      # Z becomes Y (up)
                            -position.y * 0.0254      # -Y becomes Z (forward)
                        ]
                        
                        gltf_normal = [
                            normal.x,                 # X stays
                            normal.z,                 # Z becomes Y
                            -normal.y                 # -Y becomes Z
                        ]
                        
                                        # Get UV coordinates using appropriate method
                uv = [0.0, 0.0]
                
                # Check if this face has positioned texture
                has_positioned_texture = has_positioned_texture?(face, material)
                
                if has_positioned_texture && material
                    # NEW METHOD: Use positioned texture extraction
                    uv = extract_positioned_texture_uv(face, position, material)
                elsif uv_helper
                    # ORIGINAL METHOD: Use standard UVHelper
                    begin
                        uvq = uv_helper.get_front_UVQ(position)
                        if uvq
                            uv = [uvq.x.to_f, uvq.y.to_f]
                            uv[1] = 1.0 - uv[1]  # Flip V for glTF
                        end
                    rescue => e
                        # Use default UV on error
                    end
                end
                        
                        # Add vertex data
                        group_data[:positions].concat(gltf_pos)
                        group_data[:normals].concat(gltf_normal)
                        group_data[:uvs].concat(uv)
                        
                        face_indices << vertex_count
                        vertex_count += 1
                    end
                    
                    # Add face indices
                    group_data[:indices].concat(face_indices)
                end
            end
            
            # Update vertex count
            group_data[:vertex_count] = vertex_count
        end
        # ---------------------------------------------------------------
    
        # HELPER FUNCTION | Check if Transform Can Decompose to TRS
        # ---------------------------------------------------------------
        def self.can_decompose_to_trs?(transform)
            # Extract scale factors
            x_axis = transform.xaxis
            y_axis = transform.yaxis
            z_axis = transform.zaxis
            
            scale_x = x_axis.length
            scale_y = y_axis.length
            scale_z = z_axis.length
            
            # Check for shear by verifying axes are perpendicular
            dot_xy = x_axis.normalize.dot(y_axis.normalize).abs
            dot_xz = x_axis.normalize.dot(z_axis.normalize).abs
            dot_yz = y_axis.normalize.dot(z_axis.normalize).abs
            
            # If any dot product is not near zero, we have shear
            tolerance = 0.001
            return false if dot_xy > tolerance || dot_xz > tolerance || dot_yz > tolerance
            
            # Check determinant sign (negative means reflection)
            det = transform.to_a[0] * transform.to_a[5] * transform.to_a[10] +
                  transform.to_a[1] * transform.to_a[6] * transform.to_a[8] +
                  transform.to_a[2] * transform.to_a[4] * transform.to_a[9] -
                  transform.to_a[2] * transform.to_a[5] * transform.to_a[8] -
                  transform.to_a[1] * transform.to_a[4] * transform.to_a[10] -
                  transform.to_a[0] * transform.to_a[6] * transform.to_a[9]
            return false if det < 0
            
            true
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Convert Rotation Matrix to Quaternion
        # ---------------------------------------------------------------
        def self.matrix_to_quaternion(m)
            # Convert rotation matrix to quaternion
            # Root node handles coordinate system conversion
            trace = m[0][0] + m[1][1] + m[2][2]
            
            if trace > 0
                s = 0.5 / Math.sqrt(trace + 1.0)
                w = 0.25 / s
                x = (m[2][1] - m[1][2]) * s
                y = (m[0][2] - m[2][0]) * s
                z = (m[1][0] - m[0][1]) * s
            elsif m[0][0] > m[1][1] && m[0][0] > m[2][2]
                s = 2.0 * Math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2])
                w = (m[2][1] - m[1][2]) / s
                x = 0.25 * s
                y = (m[0][1] + m[1][0]) / s
                z = (m[0][2] + m[2][0]) / s
            elsif m[1][1] > m[2][2]
                s = 2.0 * Math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2])
                w = (m[0][2] - m[2][0]) / s
                x = (m[0][1] + m[1][0]) / s
                y = 0.25 * s
                z = (m[1][2] + m[2][1]) / s
            else
                s = 2.0 * Math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1])
                w = (m[1][0] - m[0][1]) / s
                x = (m[0][2] + m[2][0]) / s
                y = (m[1][2] + m[2][1]) / s
                z = 0.25 * s
            end
            
            [x, y, z, w]
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Add TRS to Node
        # ---------------------------------------------------------------
        def self.add_trs_to_node(node, transform)
            # Translation - convert units from inches to meters
            origin = transform.origin
            gltf_trans = convert_inches_to_meters(origin.x, origin.y, origin.z)
            node["translation"] = gltf_trans
            
            # Scale
            x_axis = transform.xaxis
            y_axis = transform.yaxis
            z_axis = transform.zaxis
            
            scale_x = x_axis.length
            scale_y = y_axis.length
            scale_z = z_axis.length
            
            if (scale_x - 1.0).abs > 0.001 || (scale_y - 1.0).abs > 0.001 || (scale_z - 1.0).abs > 0.001
                node["scale"] = [scale_x, scale_y, scale_z]
            end
            
            # Rotation (as quaternion)
            rotation_matrix = [
                [x_axis.normalize.x, x_axis.normalize.y, x_axis.normalize.z],
                [y_axis.normalize.x, y_axis.normalize.y, y_axis.normalize.z],
                [z_axis.normalize.x, z_axis.normalize.y, z_axis.normalize.z]
            ]
            
            quat = matrix_to_quaternion(rotation_matrix)
            # Only add rotation if not identity
            if quat[0].abs > 0.001 || quat[1].abs > 0.001 || quat[2].abs > 0.001
                node["rotation"] = quat
            end
        end
        # ---------------------------------------------------------------

        # SUB HELPER FUNCTION | Process Group or Component Instance
        # ---------------------------------------------------------------
        def self.process_group_or_component(entity, gltf, binary_buffer)
            node_index = gltf["nodes"].length                                     # Current node index
            node = {
                "name" => entity.respond_to?(:name) ? entity.name : "Node_#{node_index}"
            }
            
            # Add transformation - try to decompose to TRS first
            if entity.respond_to?(:transformation)
                transform = entity.transformation                                  # Get transformation
                unless transform.identity?
                    # Try to decompose to TRS
                    if can_decompose_to_trs?(transform)
                        add_trs_to_node(node, transform)                          # Use TRS decomposition
                    else
                        # Fall back to matrix for non-decomposable transforms
                        puts "    Warning: Using matrix for node #{node_index} (non-TRS transform)"
                        matrix = convert_sketchup_matrix_to_gltf(transform)       # Convert to glTF
                        node["matrix"] = matrix                                    # Set matrix
                    end
                end
            end
            
            # Get entity definition
            definition = entity.respond_to?(:definition) ? entity.definition : entity
            
            # Get the instance material (Per Object material)
            instance_material = entity.material if entity.respond_to?(:material)
            
            # Extract mesh data from all faces
            mesh_data = extract_geometry_data(definition.entities, instance_material)  # Pass instance material
            
            if mesh_data && !mesh_data[:positions].empty?
                mesh_index = add_mesh_to_gltf(mesh_data, gltf, binary_buffer)     # Add mesh
                node["mesh"] = mesh_index                                          # Reference mesh
            end
            
            # Process child entities
            child_indices = []
            child_count = definition.entities.count { |e| (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && !entity_excluded?(e) }
            
            if child_count > 0
                puts "      Processing #{child_count} child entities in #{node['name']}"
            end
            
            definition.entities.each do |child|
                next if entity_excluded?(child)                                    # Skip excluded
                
                if child.is_a?(Sketchup::Group) || child.is_a?(Sketchup::ComponentInstance)
                    child_index = process_group_or_component(child, gltf, binary_buffer)
                    child_indices << child_index if child_index                   # Add child
                end
            end
            
            node["children"] = child_indices unless child_indices.empty?          # Set children
            
            gltf["nodes"] << node                                                  # Add node
            node_index                                                             # Return index
        end
        # ---------------------------------------------------------------
    
        # HELPER FUNCTION | Check if Entity Should Be Excluded
        # ---------------------------------------------------------------
        def self.entity_excluded?(entity)
            return false unless entity.respond_to?(:layer)                        # Skip if no layer
            @excluded_layers.include?(entity.layer.name)                          # Check exclusion
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Geometry Data Extraction
    # -----------------------------------------------------------------------------
    
        # HELPER FUNCTION | Check if Face Has Positioned Texture
        # ---------------------------------------------------------------
        def self.has_positioned_texture?(face, material)
            return false unless face && material && material.texture
            
            begin
                # Try to get UVHelper - if this succeeds, texture might be positioned
                uv_helper = face.get_UVHelper(true) if face.material == material
                uv_helper = face.get_UVHelper(false) if face.back_material == material
                
                return false unless uv_helper
                
                # Test a corner of the face to see if UV coordinates are non-standard
                bounds = face.bounds
                test_point = bounds.corner(0)  # Get a corner point
                
                uvq = uv_helper.get_front_UVQ(test_point)
                return false unless uvq
                
                # Check if UV coordinates suggest positioning has been applied
                # Standard textures typically have UVs in predictable ranges
                u, v = uvq.x.to_f, uvq.y.to_f
                
                # If UVs are significantly outside 0-1 range or have unusual values,
                # it's likely a positioned texture
                return true if u.abs > 2.0 || v.abs > 2.0
                
                # Check for rotation by testing multiple points
                if face.vertices.length >= 3
                    test_point2 = face.vertices[1].position
                    uvq2 = uv_helper.get_front_UVQ(test_point2)
                    if uvq2
                        u2, v2 = uvq2.x.to_f, uvq2.y.to_f
                        # If UV direction doesn't align with geometry direction, it's positioned
                        return true if (u2 - u).abs > 0.1 && (v2 - v).abs > 0.1
                    end
                end
                
                false
            rescue => e
                puts "        Error checking positioned texture: #{e.message}"
                false
            end
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Extract UV Coordinates for Positioned Textures
        # ---------------------------------------------------------------
        def self.extract_positioned_texture_uv(face, position, material)
            return [0.0, 0.0] unless face && material && material.texture
            
            begin
                # Get the correct UVHelper based on which side has the material
                uv_helper = nil
                if face.material == material
                    uv_helper = face.get_UVHelper(true)                               # Front face
                elsif face.back_material == material
                    uv_helper = face.get_UVHelper(false)                              # Back face
                end
                
                return [0.0, 0.0] unless uv_helper
                
                # Get UV coordinates for this position
                uvq = uv_helper.get_front_UVQ(position)
                return [0.0, 0.0] unless uvq
                
                # Extract UV coordinates with perspective correction
                u = uvq.x.to_f
                v = uvq.y.to_f
                q = uvq.z.to_f
                
                # Apply perspective correction if Q is not 1.0
                if q != 0.0 && q != 1.0
                    u = u / q
                    v = v / q
                end
                
                # UVHelper returns coordinates in texture space
                # These are already normalized for positioned textures
                uv = [u, v]
                
                # Flip V coordinate for glTF (glTF uses top-left origin)
                uv[1] = 1.0 - uv[1]
                
                # Clamp to reasonable range (positioned textures can go outside 0-1)
                uv[0] = [[uv[0], -10.0].max, 10.0].min
                uv[1] = [[uv[1], -10.0].max, 10.0].min
                
                return uv
                
            rescue => e
                puts "        Error extracting positioned UV: #{e.message}"
                return [0.0, 0.0]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract Geometry Data from Entities
        # ------------------------------------------------------------
        def self.extract_geometry_data(entities, instance_material = nil)
            positions = []                                                         # Vertex positions
            normals = []                                                           # Vertex normals
            uvs = []                                                               # Texture coordinates
            indices = []                                                           # Face indices
            material_indices = []                                                  # Material per primitive
            
            vertex_count = 0                                                       # Track vertices
            face_count = 0                                                         # Track faces processed
            
            # Count total faces for progress
            total_faces = entities.count { |e| e.is_a?(Sketchup::Face) && !entity_excluded?(e) }
            uv_debug_count = 0                                                     # Track faces with UVs
            positioned_texture_count = 0                                           # Track positioned textures
            
            entities.each do |entity|
                next unless entity.is_a?(Sketchup::Face)                          # Only process faces
                next if entity_excluded?(entity)                                   # Skip excluded
                
                # Report face processing progress
                face_count += 1
                if face_count % 100 == 0 || face_count == total_faces
                    puts "      Processing faces: #{face_count}/#{total_faces}"
                end
                
                # Determine which material to use:
                # 1. Instance material (Per Object) overrides face materials
                # 2. Otherwise use face material
                effective_material = instance_material || entity.material || entity.back_material
                material_index = get_or_create_material_index(effective_material)  # Material index
                
                # Check if this face has a positioned texture
                has_positioned = has_positioned_texture?(entity, effective_material)
                if has_positioned
                    positioned_texture_count += 1
                    puts "        Face #{face_count} has positioned texture: #{effective_material.display_name}"
                end
                
                # Get UVHelper for proper UV coordinate extraction (ORIGINAL METHOD)
                uv_helper = nil
                if effective_material && effective_material.texture && !has_positioned
                    # Use the face's material for UV mapping (not instance material)
                    if entity.material && entity.material.texture
                        uv_helper = entity.get_UVHelper(true, true)              # Original method with texture parameter
                    elsif entity.back_material && entity.back_material.texture
                        uv_helper = entity.get_UVHelper(false, false)            # Original method with texture parameter
                    end
                end
                
                # Get face mesh with normals
                mesh = entity.mesh(7)                                              # Full mesh data
                
                # Process each polygon in the mesh
                (1..mesh.count_polygons).each do |poly_index|
                    polygon_points = mesh.polygon_at(poly_index)                  # Get polygon
                    
                    # Only process triangles
                    next unless polygon_points.length == 3                        # Skip non-triangles
                    
                    # Create face indices
                    face_indices = []
                    
                    polygon_points.each do |point_index|
                        # Get vertex data
                        position = mesh.point_at(point_index)                     # Position in inches
                        normal = mesh.normal_at(point_index)                      # Normal vector
                        
                        # Get UV coordinates using appropriate method
                        uv = [0.0, 0.0]
                        
                        if has_positioned && effective_material && effective_material.texture
                            # NEW METHOD: Use positioned texture extraction
                            uv = extract_positioned_texture_uv(entity, position, effective_material)
                            
                            # Debug positioned texture UVs
                            if point_index == polygon_points.first
                                uv_debug_count += 1
                                if uv_debug_count <= 5  # Only log first 5 for brevity
                                    puts "          Positioned UV coords: [#{uv[0].round(3)}, #{uv[1].round(3)}]"
                                end
                            end
                            
                        elsif uv_helper
                            # ORIGINAL METHOD: Use standard UVHelper
                            begin
                                # Get UV for this vertex position
                                uvq = uv_helper.get_front_UVQ(position)
                                if uvq
                                    # Extract UV from UVQ (ignore Q component)
                                    uv = [uvq.x.to_f, uvq.y.to_f]
                                    # UVHelper returns normalized coordinates, no need to divide by texture size
                                    # Flip V coordinate for glTF
                                    uv[1] = 1.0 - uv[1]
                                    
                                    # Debug first UV of each face
                                    if point_index == polygon_points.first
                                        uv_debug_count += 1
                                        if uv_debug_count <= 5  # Only log first 5 for brevity
                                            puts "          Standard UV coords: [#{uv[0].round(3)}, #{uv[1].round(3)}]"
                                        end
                                    end
                                else
                                    puts "          WARNING: get_front_UVQ returned nil for position"
                                end
                            rescue => e
                                puts "        UV extraction error: #{e.message}"
                                puts "        Error class: #{e.class}"
                            end
                            
                        elsif effective_material && effective_material.texture
                            puts "          WARNING: Have texture but no UV helper!"
                        end
                        
                        # Convert units from inches to meters (root node handles coord system)
                        gltf_pos = convert_inches_to_meters(position.x, position.y, position.z)
                        
                        # Add vertex data (normals don't need unit conversion)
                        positions.concat(gltf_pos)                                # Converted position
                        normals.concat([normal.x.to_f, normal.y.to_f, normal.z.to_f])  # Normal as-is
                        uvs.concat(uv)                                            # UV coordinates
                        
                        face_indices << vertex_count                               # Add index
                        vertex_count += 1                                          # Increment
                    end
                    
                    # Add indices for this triangle
                    indices.concat(face_indices)                                   # Add face
                    material_indices << material_index                             # Material for primitive
                end
            end
            
            return nil if positions.empty?                                        # No geometry
            
            # Debug UV extraction
            if uv_debug_count > 0
                puts "        Faces with texture UVs: #{uv_debug_count}/#{face_count}"
            end
            if positioned_texture_count > 0
                puts "        Faces with positioned textures: #{positioned_texture_count}/#{face_count}"
            end
            
            {
                :positions => positions,                                           # <-- Vertex positions
                :normals => normals,                                               # <-- Vertex normals
                :uvs => uvs,                                                       # <-- Texture coordinates
                :indices => indices,                                               # <-- Face indices
                :materials => material_indices                                     # <-- Material index per triangle
            }
        end
        # ---------------------------------------------------------------
    
        # HELPER FUNCTION | Fix SketchUp UV Coordinates
        # ---------------------------------------------------------------
        def self.fix_sketchup_uv(uv_point, texture)
            return [0.0, 0.0] unless uv_point && texture
            
            # Handle SketchUp's UV representation
            if uv_point.respond_to?(:x) && uv_point.respond_to?(:y)
                # Point3d with UV coordinates
                u = uv_point.x.to_f
                v = uv_point.y.to_f
            elsif uv_point.is_a?(Array) && uv_point.length >= 2
                # Array format [u, v]
                u = uv_point[0].to_f
                v = uv_point[1].to_f
            else
                puts "        WARNING: Unknown UV format: #{uv_point.class}"
                return [0.0, 0.0]
            end
            
            # SketchUp returns UVs in different formats depending on texture size
            # If values are > 1.0, they're likely in pixel coordinates
            if u.abs > 1.0 || v.abs > 1.0
                # Convert from pixel coordinates to normalized 0-1 range
                u = u / texture.width.to_f
                v = v / texture.height.to_f
            end
            
            # SketchUp uses bottom-left origin, glTF uses top-left
            # Flip V coordinate
            v = 1.0 - v
            
            # Clamp to valid range
            u = [[u, 0.0].max, 1.0].min
            v = [[v, 0.0].max, 1.0].min
            
            [u, v]
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Generate UV Coordinates for Untextured Face
        # ---------------------------------------------------------------
        def self.generate_uv_for_face(face, point)
            # Get face normal to determine projection plane
            normal = face.normal
            
            # Choose projection plane based on dominant normal axis
            abs_x = normal.x.abs
            abs_y = normal.y.abs  
            abs_z = normal.z.abs
            
            # Get bounding box of the face
            bounds = face.bounds
            min_pt = bounds.min
            max_pt = bounds.max
            
            # Calculate UV based on dominant axis
            if abs_z >= abs_x && abs_z >= abs_y
                # Z is dominant - project to XY plane
                u = (point.x - min_pt.x) / (max_pt.x - min_pt.x)
                v = (point.y - min_pt.y) / (max_pt.y - min_pt.y)
            elsif abs_y >= abs_x && abs_y >= abs_z
                # Y is dominant - project to XZ plane
                u = (point.x - min_pt.x) / (max_pt.x - min_pt.x)
                v = (point.z - min_pt.z) / (max_pt.z - min_pt.z)
            else
                # X is dominant - project to YZ plane
                u = (point.y - min_pt.y) / (max_pt.y - min_pt.y)
                v = (point.z - min_pt.z) / (max_pt.z - min_pt.z)
            end
            
            # Ensure values are in 0-1 range
            u = [[u, 0.0].max, 1.0].min
            v = [[v, 0.0].max, 1.0].min
            
            # Flip V for glTF compatibility
            v = 1.0 - v
            
            [u, v]
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Convert SketchUp Units to glTF
        # ---------------------------------------------------------------
        def self.convert_inches_to_meters(x, y, z)
            # Convert from inches to meters (glTF standard)
            # We're using a root rotation for coordinate system conversion
            # so we only need unit conversion here
            inches_to_meters = 0.0254
            
            [
                x * inches_to_meters,
                y * inches_to_meters,
                z * inches_to_meters
            ]
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Convert SketchUp Transformation Matrix to glTF
        # ---------------------------------------------------------------
        def self.convert_sketchup_matrix_to_gltf(transform)
            # SketchUp uses 4x4 matrix in row-major order
            # glTF expects column-major order
            # Root node handles coordinate system conversion
            
            # Convert units for translation
            origin = transform.origin
            gltf_origin = convert_inches_to_meters(origin.x, origin.y, origin.z)
            
            # Build column-major matrix for glTF
            matrix = []
            4.times do |col|
                4.times do |row|
                    if row < 3 && col == 3
                        # Translation column - use converted values
                        matrix << gltf_origin[row]
                    else
                        # Other values stay as-is
                        matrix << transform.to_a[row * 4 + col]
                    end
                end
            end
            
            matrix
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Material and Texture Processing
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Collect All Materials from Entities
        # ------------------------------------------------------------
        def self.collect_materials_from_entities(entities)
            puts "    Collecting materials from entities..."
            material_count = 0
            
            entities.each do |entity|
                next if entity_excluded?(entity)                                   # Skip excluded
                
                case entity
                when Sketchup::Group, Sketchup::ComponentInstance
                    # Check if the group/component itself has a material (Per Object)
                    if entity.material && !@material_map.has_key?(entity.material)
                        @material_map[entity.material] = material_count
                        material_count += 1
                        puts "      Found material on #{entity.class}: #{entity.material.display_name}"
                    end
                    
                    # Get entity definition
                    definition = entity.respond_to?(:definition) ? entity.definition : entity
                    
                    # Recursively collect from nested entities
                    definition.entities.each do |sub_entity|
                        if sub_entity.is_a?(Sketchup::Face)
                            if sub_entity.material && !@material_map.has_key?(sub_entity.material)
                                @material_map[sub_entity.material] = material_count
                                material_count += 1
                                puts "      Found material: #{sub_entity.material.display_name}"
                            end
                            if sub_entity.back_material && !@material_map.has_key?(sub_entity.back_material)
                                @material_map[sub_entity.back_material] = material_count
                                material_count += 1
                                puts "      Found back material: #{sub_entity.back_material.display_name}"
                            end
                        elsif sub_entity.is_a?(Sketchup::Group) || sub_entity.is_a?(Sketchup::ComponentInstance)
                            # Recursively collect materials from nested groups/components
                            collect_materials_from_entities([sub_entity])
                        end
                    end
                    
                when Sketchup::Face
                    if entity.material && !@material_map.has_key?(entity.material)
                        @material_map[entity.material] = material_count
                        material_count += 1
                        puts "      Found material: #{entity.material.display_name}"
                    end
                    if entity.back_material && !@material_map.has_key?(entity.back_material)
                        @material_map[entity.back_material] = material_count
                        material_count += 1
                        puts "      Found back material: #{entity.back_material.display_name}"
                    end
                end
            end
            
            puts "    Found #{@material_map.length} unique materials"
        end
        # ---------------------------------------------------------------
    
        # FUNCTION | Get or Create Material Index
        # ---------------------------------------------------------------
        def self.get_or_create_material_index(material)
            return 0 unless material                                               # Default material
            
            # Check if material already processed
            return @material_map[material] if @material_map.has_key?(material)    # Return existing
            
            # Create new material index
            material_index = @material_map.length                                  # New index
            @material_map[material] = material_index                               # Store mapping
            
            material_index                                                         # Return index
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Create GLTF Materials from Material Map
        # ---------------------------------------------------------------
        def self.create_gltf_materials(gltf, binary_buffer)
            puts "    Creating materials: #{@material_map.length} materials found"
            
            @material_map.each do |material, index|
                puts "      Material #{index}: #{material.display_name}"
                
                gltf_material = {
                    "name" => material.display_name || "Material_#{index}"        # <-- Material name
                }
                
                # Set base color
                color = material.color
                base_color = [
                    color.red / 255.0,                                            # <-- Red channel
                    color.green / 255.0,                                          # <-- Green channel
                    color.blue / 255.0,                                           # <-- Blue channel
                    material.alpha                                                 # <-- Alpha channel
                ]
                
                puts "        Color: RGB(#{color.red}, #{color.green}, #{color.blue}), Alpha: #{material.alpha}"
                
                pbr = {
                    "baseColorFactor" => base_color,                              # <-- Base color
                    "metallicFactor" => 0.0,                                      # <-- Non-metallic
                    "roughnessFactor" => 0.5                                      # <-- Medium roughness
                }
                
                # Add texture if present (check and cache)
                if material.texture && material.texture.valid?
                    puts "        Has texture: #{material.texture.filename}"
                    texture_index = get_or_create_texture(material.texture, gltf, binary_buffer)
                    if texture_index
                        pbr["baseColorTexture"] = {
                            "index" => texture_index,                              # <-- Texture index
                            "texCoord" => 0                                        # <-- UV set
                        }
                        puts "        Assigned texture index: #{texture_index}"
                    else
                        puts "        ERROR: Failed to create texture!"
                    end
                else
                    puts "        No texture - using RGB color fallback"
                    # No texture: Create 1x1 pixel image from material color
                    texture_index = create_rgb_fallback_texture(material.color, gltf, binary_buffer)
                    if texture_index
                        pbr["baseColorTexture"] = {
                            "index" => texture_index,
                            "texCoord" => 0
                        }
                        puts "        Assigned RGB fallback texture index: #{texture_index}"
                    end
                end
                
                gltf_material["pbrMetallicRoughness"] = pbr                       # Set PBR
                
                # Handle transparency
                if material.alpha < 1.0
                    gltf_material["alphaMode"] = "BLEND"                          # <-- Blended transparency
                    puts "        Transparency enabled: #{material.alpha}"
                end
                
                gltf["materials"] << gltf_material                                # Add material
            end
            
            # Always ensure at least one material exists for glTF compliance
            if gltf["materials"].empty?
                puts "      Adding default material"
                gltf["materials"] << {
                    "name" => "Default",                                          # <-- Default name
                    "pbrMetallicRoughness" => {
                        "baseColorFactor" => [0.8, 0.8, 0.8, 1.0],               # <-- Light gray
                        "metallicFactor" => 0.0,                                  # <-- Non-metallic
                        "roughnessFactor" => 0.5                                  # <-- Medium roughness
                    }
                }
            end
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Get or Create Texture (with caching)
        # ---------------------------------------------------------------
        def self.get_or_create_texture(texture, gltf, binary_buffer)
            # Create consistent cache key (same as in get_or_create_image)
            cache_key = texture.filename.gsub(/[^a-zA-Z0-9._-]/, '_')
            cache_key = "texture_#{cache_key}" if cache_key.empty?
            
            # Check if already processed
            if @texture_cache.has_key?(cache_key)
                puts "        Using cached texture index: #{@texture_cache[cache_key]} for #{cache_key}"
                return @texture_cache[cache_key]  # Return cached index
            end
            
            # Create sampler if first texture
            if gltf["samplers"].empty?
                gltf["samplers"] << {
                    "magFilter" => 9729,                                          # <-- LINEAR
                    "minFilter" => 9987,                                          # <-- LINEAR_MIPMAP_LINEAR
                    "wrapS" => 10497,                                             # <-- REPEAT
                    "wrapT" => 10497                                              # <-- REPEAT
                }
            end
            
            # Get/create image and cache
            image_index = get_or_create_image(texture, gltf, binary_buffer)      # Create image
            return nil unless image_index                                         # Failed to create
            
            # Create texture
            texture_index = gltf["textures"].length                               # New index
            gltf["textures"] << {
                "sampler" => 0,                                                   # <-- Default sampler
                "source" => image_index                                           # <-- Image source
            }
            
            @texture_map[texture] = texture_index                                 # Store mapping
            @texture_cache[cache_key] = texture_index                             # Cache the index
            puts "        Created texture index: #{texture_index} for #{cache_key}"
            texture_index                                                          # Return index
        end
        # ---------------------------------------------------------------
    
        # SUB HELPER FUNCTION | Get or Create Image (with temp file caching)
        # ---------------------------------------------------------------
        def self.get_or_create_image(texture, gltf, binary_buffer)
            return @image_map[texture] if @image_map.has_key?(texture)            # Return existing
            
            begin
                puts "      Processing texture: #{texture.filename}"
                
                # Create a safe cache filename by replacing invalid characters
                cache_key = texture.filename.gsub(/[^a-zA-Z0-9._-]/, '_')         # Replace invalid chars with underscore
                cache_key = "texture_#{cache_key}" if cache_key.empty?            # Ensure non-empty name
                cached_path = File.join(@texture_cache_folder, "#{cache_key}.png")
                
                # Check if already cached
                if File.exist?(cached_path)
                    puts "        Using cached image file: #{cached_path}"
                    image_data = File.binread(cached_path)
                    width = texture.image_width
                    height = texture.image_height
                else
                    # Try multiple methods to extract texture
                    success = false
                    
                    # Method 1: Try ImageRep for 2025+
                    begin
                        image_rep = texture.image_rep(true)  # true = include colorization
                        
                        if image_rep && image_rep.width > 0 && image_rep.height > 0
                            puts "        ImageRep dimensions: #{image_rep.width}x#{image_rep.height}"
                            success = image_rep.save_file(cached_path)
                            width = image_rep.width
                            height = image_rep.height
                            puts "        ImageRep save result: #{success}"
                            if success
                                puts "        Successfully cached using ImageRep: #{cached_path}"
                            end
                        else
                            puts "        ImageRep invalid or zero dimensions"
                        end
                    rescue => e
                        puts "        ImageRep method failed: #{e.message}"
                        puts "        Error class: #{e.class}"
                    end
                    
                    # Method 2: Try texture.write if ImageRep failed
                    if !success || !File.exist?(cached_path)
                        begin
                            puts "        Trying legacy texture.write method..."
                            # Ensure directory exists
                            FileUtils.makedirs(File.dirname(cached_path)) rescue nil
                            
                            success = texture.write(cached_path, true)  # true for colorized
                            width = texture.image_width
                            height = texture.image_height
                            puts "        texture.write result: #{success}"
                            if success && File.exist?(cached_path)
                                puts "        Successfully cached using texture.write"
                            end
                        rescue => e
                            puts "        texture.write failed: #{e.message}"
                        end
                    end
                    
                    # Method 3: Try using texture writer as last resort
                    if !success || !File.exist?(cached_path)
                        begin
                            puts "        Trying TextureWriter method..."
                            tw = Sketchup.create_texture_writer
                            # Load the texture into the writer
                            tw.load(texture)
                            # Write all textures
                            result = tw.write_all(@texture_cache_folder, false)
                            if result == 0  # Success
                                # Find the written file
                                possible_names = [
                                    File.join(@texture_cache_folder, File.basename(texture.filename)),
                                    File.join(@texture_cache_folder, File.basename(texture.filename, '.*') + '.png')
                                ]
                                possible_names.each do |possible_path|
                                    if File.exist?(possible_path)
                                        FileUtils.mv(possible_path, cached_path) rescue nil
                                        success = File.exist?(cached_path)
                                        puts "        Found and moved texture from TextureWriter"
                                        break
                                    end
                                end
                            end
                        rescue => e
                            puts "        TextureWriter method failed: #{e.message}"
                        end
                    end
                    
                    unless success && File.exist?(cached_path)
                        puts "        ERROR: All texture extraction methods failed"
                        puts "        Texture filename: #{texture.filename}"
                        puts "        Texture valid?: #{texture.valid?}"
                        puts "        Texture dimensions: #{texture.image_width}x#{texture.image_height}"
                        return nil
                    end
                    
                    image_data = File.binread(cached_path)
                    width = texture.image_width
                    height = texture.image_height
                end
                
                puts "        Texture data size: #{image_data.bytesize} bytes"
                
                # Add padding for 4-byte alignment
                buffer_offset = binary_buffer.length
                padding = (4 - (buffer_offset % 4)) % 4
                padding.times { binary_buffer << 0 }
                buffer_offset = binary_buffer.length
                
                # Add to buffer
                binary_buffer.concat(image_data.bytes)
                
                # Create buffer view
                buffer_view_index = gltf["bufferViews"].length
                gltf["bufferViews"] << {
                    "buffer" => 0,
                    "byteOffset" => buffer_offset,
                    "byteLength" => image_data.bytesize
                }
                
                # Create image
                image_index = gltf["images"].length
                gltf["images"] << {
                    "bufferView" => buffer_view_index,
                    "mimeType" => "image/png"
                }
                
                puts "        Added as image index: #{image_index}"
                @image_map[texture] = image_index
                image_index
                
            rescue => e
                puts "        ERROR processing texture: #{e.message}"
                puts "        #{e.backtrace.first(3).join("\n        ")}"
                nil
            end
        end
        # ---------------------------------------------------------------
    
        # HELPER FUNCTION | Create 1x1 RGB Fallback Texture (for no-texture materials)
        # ---------------------------------------------------------------
        def self.create_rgb_fallback_texture(color, gltf, binary_buffer)
            begin
                # Create 1x1 pixel ImageRep from color
                image_rep = Sketchup::ImageRep.new
                r, g, b = color.red, color.green, color.blue
                
                # Try to use set_data if available
                if image_rep.respond_to?(:set_data)
                    pixel_data = [r, g, b, 255].pack("C*")  # RGBA byte string
                    image_rep.set_data(1, 1, 32, 0, pixel_data)  # 32bpp for RGBA
                else
                    # Fallback: Create a tiny colored square in the model, capture it, then delete
                    puts "        Creating RGB fallback using alternative method"
                    return nil  # For now, skip RGB fallback if set_data not available
                end
                
                # Cache to temp file
                cache_key = "rgb_#{color.to_i.abs}"  # Use abs to avoid negative numbers
                cached_path = File.join(@texture_cache_folder, "#{cache_key}.png")
            
            unless File.exist?(cached_path)
                success = image_rep.save_file(cached_path)
                unless success
                    puts "        ERROR: Failed to create RGB fallback"
                    return nil
                end
            end
            
            # Read and add to buffer (same as regular image)
            image_data = File.binread(cached_path)
            
            buffer_offset = binary_buffer.length
            padding = (4 - (buffer_offset % 4)) % 4
            padding.times { binary_buffer << 0 }
            buffer_offset = binary_buffer.length
            
            binary_buffer.concat(image_data.bytes)
            
            buffer_view_index = gltf["bufferViews"].length
            gltf["bufferViews"] << {
                "buffer" => 0,
                "byteOffset" => buffer_offset,
                "byteLength" => image_data.bytesize
            }
            
            image_index = gltf["images"].length
            gltf["images"] << {
                "bufferView" => buffer_view_index,
                "mimeType" => "image/png"
            }
            
            texture_index = gltf["textures"].length
            gltf["textures"] << {
                "sampler" => 0,
                "source" => image_index
            }
            
            texture_index  # Return the texture index
            
            rescue => e
                puts "        ERROR creating RGB fallback: #{e.message}"
                nil
            end
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Mesh and Buffer Management
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Add Mesh to GLTF Structure
        # ------------------------------------------------------------
        def self.add_mesh_to_gltf(mesh_data, gltf, binary_buffer)
            mesh_index = gltf["meshes"].length                                    # Current mesh index
            
            # Create mesh
            mesh = {
                "name" => "Mesh_#{mesh_index}",                                  # <-- Mesh name
                "primitives" => []                                                # <-- Mesh primitives
            }
            
            # Group indices by material
            material_groups = {}
            mesh_data[:indices].each_slice(3).with_index do |triangle, idx|
                material = mesh_data[:materials][idx] || 0                        # Get material
                material_groups[material] ||= []                                  # Initialize group
                material_groups[material].concat(triangle)                        # Add triangle
            end
            
            # Create primitive for each material
            material_groups.each do |material_index, indices|
                primitive = {
                    "attributes" => {},                                           # <-- Vertex attributes
                    "material" => material_index,                                 # <-- Material index
                    "mode" => 4                                                   # <-- TRIANGLES
                }
                
                # Add position accessor
                position_accessor = add_accessor(
                    mesh_data[:positions], gltf, binary_buffer,
                    5126, "VEC3", true, 34962                                     # FLOAT, VEC3, calc bounds, ARRAY_BUFFER
                )
                primitive["attributes"]["POSITION"] = position_accessor           # Set attribute
                
                # Add normal accessor
                normal_accessor = add_accessor(
                    mesh_data[:normals], gltf, binary_buffer,
                    5126, "VEC3", false, 34962                                    # FLOAT, VEC3, no bounds, ARRAY_BUFFER
                )
                primitive["attributes"]["NORMAL"] = normal_accessor               # Set attribute
                
                # Check if we have textured materials
                has_textured_materials = @material_map.keys.any? { |mat| mat && mat.texture }
                
                # Debug UV export
                if material_index < @material_map.length
                    material = @material_map.keys[material_index]
                    if material && material.texture
                        puts "        Material #{material_index} has texture, UV count: #{mesh_data[:uvs].length / 2}"
                    end
                end
                
                # Add UV accessor only if we have textures in use
                if has_textured_materials && !mesh_data[:uvs].empty?
                    uv_accessor = add_accessor(
                        mesh_data[:uvs], gltf, binary_buffer,
                        5126, "VEC2", false, 34962                                # FLOAT, VEC2, no bounds, ARRAY_BUFFER
                    )
                    primitive["attributes"]["TEXCOORD_0"] = uv_accessor           # Set attribute
                    puts "        Added TEXCOORD_0 accessor: #{uv_accessor}"
                elsif has_textured_materials
                    puts "        WARNING: Have textured materials but no UV data!"
                end
                
                # Add indices accessor
                if indices.max < 65536
                    # Use unsigned short for indices
                    indices_accessor = add_accessor(
                        indices, gltf, binary_buffer,
                        5123, "SCALAR", false, 34963                              # UNSIGNED_SHORT, SCALAR, ELEMENT_ARRAY_BUFFER
                    )
                else
                    # Use unsigned int for large meshes
                    indices_accessor = add_accessor(
                        indices, gltf, binary_buffer,
                        5125, "SCALAR", false, 34963                              # UNSIGNED_INT, SCALAR, ELEMENT_ARRAY_BUFFER
                    )
                end
                primitive["indices"] = indices_accessor                           # Set indices
                
                mesh["primitives"] << primitive                                   # Add primitive
            end
            
            gltf["meshes"] << mesh                                                # Add mesh
            mesh_index                                                             # Return index
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Add Accessor to GLTF
        # ---------------------------------------------------------------
        def self.add_accessor(data, gltf, binary_buffer, component_type, type, calc_bounds, target_hint = nil)
            # Calculate element count
            element_size = case type
                           when "SCALAR" then 1
                           when "VEC2" then 2
                           when "VEC3" then 3
                           when "VEC4" then 4
                           else 1
                           end
            
            count = data.length / element_size                                    # Element count
            
            # Add padding for 4-byte alignment
            buffer_offset = binary_buffer.length                                  # Current offset
            padding = (4 - (buffer_offset % 4)) % 4                              # Calculate padding
            padding.times { binary_buffer << 0 }                                  # Add padding
            buffer_offset = binary_buffer.length                                  # Update offset
            
            # Add data to buffer based on component type
            case component_type
            when 5120  # BYTE
                data.each { |v| binary_buffer << [v.to_i].pack('c').unpack('C')[0] }
            when 5121  # UNSIGNED_BYTE
                data.each { |v| binary_buffer << [v.to_i].pack('C')[0] }
            when 5122  # SHORT
                data.each { |v| binary_buffer.concat([v.to_i].pack('s<').unpack('C*')) }
            when 5123  # UNSIGNED_SHORT
                data.each { |v| binary_buffer.concat([v.to_i].pack('S<').unpack('C*')) }
            when 5125  # UNSIGNED_INT
                data.each { |v| binary_buffer.concat([v.to_i].pack('L<').unpack('C*')) }
            when 5126  # FLOAT
                data.each { |v| binary_buffer.concat([v.to_f].pack('f').unpack('C*')) }  # <-- Changed from 'e' to 'f' for proper float packing
            end
            
            byte_length = binary_buffer.length - buffer_offset                    # Data length
            
            # Create buffer view
            buffer_view_index = gltf["bufferViews"].length                       # New index
            buffer_view = {
                "buffer" => 0,                                                    # <-- Main buffer
                "byteOffset" => buffer_offset,                                    # <-- Start offset
                "byteLength" => byte_length                                       # <-- Data length
            }
            
            # Add target hint for vertex/index data
            if target_hint
                buffer_view["target"] = target_hint                               # <-- Buffer target (ARRAY_BUFFER or ELEMENT_ARRAY_BUFFER)
            end
            
            gltf["bufferViews"] << buffer_view
            
            # Create accessor
            accessor_index = gltf["accessors"].length                             # New index
            accessor = {
                "bufferView" => buffer_view_index,                                # <-- Buffer view
                "componentType" => component_type,                                # <-- Data type
                "count" => count,                                                 # <-- Element count
                "type" => type                                                    # <-- Element type
            }
            
            # Calculate bounds if requested
            if calc_bounds && type == "VEC3"
                min = [Float::INFINITY, Float::INFINITY, Float::INFINITY]         # Initialize min
                max = [-Float::INFINITY, -Float::INFINITY, -Float::INFINITY]      # Initialize max
                
                data.each_slice(3) do |x, y, z|
                    min[0] = x if x < min[0]                                      # Update X min
                    min[1] = y if y < min[1]                                      # Update Y min
                    min[2] = z if z < min[2]                                      # Update Z min
                    max[0] = x if x > max[0]                                      # Update X max
                    max[1] = y if y > max[1]                                      # Update Y max
                    max[2] = z if z > max[2]                                      # Update Z max
                end
                
                accessor["min"] = min                                             # Set bounds min
                accessor["max"] = max                                             # Set bounds max
            end
            
            gltf["accessors"] << accessor                                         # Add accessor
            accessor_index                                                         # Return index
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | GLB File Writing
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Write GLB File to Disk
        # ------------------------------------------------------------
        def self.write_glb_file(filepath, gltf, binary_buffer)
            # Clean up empty arrays before writing
            gltf.delete("images") if gltf["images"].empty?                        # Remove if empty
            gltf.delete("textures") if gltf["textures"].empty?                    # Remove if empty
            gltf.delete("samplers") if gltf["samplers"].empty?                    # Remove if empty
            # Convert binary buffer array to binary string
            binary_data = binary_buffer.pack('C*')                                # Pack as bytes
            
            # Pad binary data to 4-byte boundary
            padding = (4 - (binary_data.bytesize % 4)) % 4                       # Calculate padding
            binary_data += "\0" * padding if padding > 0                         # Add padding
            
            # Update buffer byte length in GLTF
            gltf["buffers"] = [{
                "byteLength" => binary_data.bytesize                             # <-- Total size
            }]
            
            # Convert GLTF to JSON
            json_string = JSON.generate(gltf)                                     # Generate JSON
            
            # Pad JSON to 4-byte boundary with spaces
            json_padding = (4 - (json_string.bytesize % 4)) % 4                  # Calculate padding
            json_string += " " * json_padding if json_padding > 0                # Add padding
            
            # Calculate total file size
            total_size = 12 +                                                     # GLB header
                         8 + json_string.bytesize +                               # JSON chunk
                         8 + binary_data.bytesize                                 # BIN chunk
            
            # Write GLB file
            File.open(filepath, 'wb') do |file|
                # Write GLB header (12 bytes)
                file.write([GLB_MAGIC].pack('V'))                                 # Magic: "glTF"
                file.write([GLB_VERSION].pack('V'))                               # Version: 2
                file.write([total_size].pack('V'))                                # Total file size
                
                # Write JSON chunk
                file.write([json_string.bytesize].pack('V'))                      # Chunk length
                file.write([GLB_CHUNK_TYPE_JSON].pack('V'))                       # Chunk type: "JSON"
                file.write(json_string)                                           # JSON data
                
                # Write binary chunk
                file.write([binary_data.bytesize].pack('V'))                      # Chunk length
                file.write([GLB_CHUNK_TYPE_BIN].pack('V'))                        # Chunk type: "BIN\0"
                file.write(binary_data)                                           # Binary data
            end
            
            puts "GLB file written: #{filepath} (#{total_size} bytes)"           # Log success
            
            # Validate the file structure
            validate_glb_structure(filepath)
        end
        # ---------------------------------------------------------------
        
        # HELPER FUNCTION | Validate GLB Structure
        # ---------------------------------------------------------------
        def self.validate_glb_structure(filepath)
            puts "\n  Validating GLB structure..."
            
            File.open(filepath, 'rb') do |file|
                # Read header
                magic = file.read(4)
                version = file.read(4).unpack('V')[0]
                length = file.read(4).unpack('V')[0]
                
                puts "    Magic: #{magic} (should be 'glTF')"
                puts "    Version: #{version} (should be 2)"
                puts "    File size: #{length} bytes"
                
                valid = true
                valid = false unless magic == 'glTF'
                valid = false unless version == 2
                
                # Read chunks
                chunk_count = 0
                while file.pos < length
                    chunk_length = file.read(4).unpack('V')[0]
                    chunk_type = file.read(4)
                    
                    chunk_count += 1
                    puts "    Chunk #{chunk_count}: #{chunk_type.inspect}, Length: #{chunk_length} bytes"
                    
                    file.seek(chunk_length, IO::SEEK_CUR)
                end
                
                puts "  ✓ GLB validation #{valid ? 'passed' : 'FAILED'}"
                valid
            end
        rescue => e
            puts "  ✗ GLB Validation Error: #{e.message}"
            false
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | User Interface and Dialog Management
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Show Export Options Dialog
        # ------------------------------------------------------------
        def self.show_export_dialog
            # Close existing dialog if open
            @export_dialog.close if @export_dialog && @export_dialog.visible?      # Close if already open
            
            # Create new dialog
            @export_dialog = UI::HtmlDialog.new(
                :dialog_title => "GLB Export Options",                             # <-- Dialog title
                :preferences_key => "ValeDesignSuite_GLBExport",                   # <-- Preferences key
                :scrollable => false,                                              # <-- No scrolling
                :resizable => false,                                               # <-- Fixed size
                :width => 500,                                                     # <-- Dialog width
                :height => 700,                                                    # <-- Dialog height
                :left => 200,                                                      # <-- X position
                :top => 200                                                        # <-- Y position
            )
            
            # Set dialog HTML
            @export_dialog.set_html(generate_dialog_html)                         # Set HTML content
            
            # Add callbacks
            add_dialog_callbacks(@export_dialog)                                   # Setup callbacks
            
            # Show dialog
            @export_dialog.show                                                    # Display dialog
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Generate HTML for Export Dialog
        # ---------------------------------------------------------------
        def self.generate_dialog_html
            excluded_count = @excluded_layers.length                               # Count excluded layers
            model = Sketchup.active_model
            tag_groups = organize_entities_by_tags(model)                         # Get tag groups
            
            html = <<-HTML
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <style>
                    /* CSS Variables - Vale Design Suite Standards */
                    :root {
                        --FontCol_ValeStandardTextColour   : #1e1e1e;
                        --FontCol_ValeLinkTextColour       : #336699;
                        --ValeBackgroundColor              : #f5f5f5;
                        --ValeBorderColor                  : #172b3a;
                        --ValeButtonBackground             : #172b3a;
                        --ValeButtonHover                  : #2a4558;
                        font-size                          : 14px;
                    }
    
                    /* Base Layout Styles */
                    html, body {
                        margin                             : 0;
                        padding                            : 20px;
                        font-family                        : Arial, sans-serif;
                        font-size                          : 14px;
                        color                              : var(--FontCol_ValeStandardTextColour);
                        background-color                   : var(--ValeBackgroundColor);
                    }
    
                    /* Form Styles */
                    h1 {
                        font-size                          : 18px;
                        margin-bottom                      : 20px;
                        color                              : var(--ValeBorderColor);
                    }
    
                    .option-group {
                        margin-bottom                      : 15px;
                        padding                            : 10px;
                        background                         : white;
                        border-radius                      : 4px;
                    }
    
                    label {
                        display                            : block;
                        margin-bottom                      : 5px;
                        font-weight                        : bold;
                    }
    
                    input[type="checkbox"] {
                        margin-right                       : 8px;
                        vertical-align                     : middle;
                    }
    
                    .info-text {
                        font-size                          : 12px;
                        color                              : #666;
                        margin-top                         : 5px;
                    }
    
                    .excluded-info {
                        background                         : #fff3cd;
                        border                             : 1px solid #ffeaa7;
                        padding                            : 8px;
                        border-radius                      : 4px;
                        margin-top                         : 10px;
                        font-size                          : 12px;
                    }
                    
                    .export-info {
                        background                         : #d4edda;
                        border                             : 1px solid #c3e6cb;
                        padding                            : 10px;
                        border-radius                      : 4px;
                        margin                             : 15px 0;
                        font-size                          : 13px;
                    }
                    
                    .export-list {
                        margin                             : 10px 0;
                        padding-left                       : 20px;
                        font-size                          : 12px;
                        color                              : #555;
                    }
    
                    /* Button Styles */
                    .button-group {
                        margin-top                         : 20px;
                        text-align                         : center;
                    }
    
                    button {
                        padding                            : 8px 20px;
                        margin                             : 0 5px;
                        background                         : var(--ValeButtonBackground);
                        color                              : white;
                        border                             : none;
                        border-radius                      : 4px;
                        cursor                             : pointer;
                        font-size                          : 14px;
                    }
    
                    button:hover {
                        background                         : var(--ValeButtonHover);
                    }
    
                    button:disabled {
                        background                         : #999;
                        cursor                             : not-allowed;
                    }
                </style>
            </head>
            <body>
                <h1>TrueVision GLB Builder Utility</h1>
                
                <div class="export-info">
                    <strong>Files to be exported:</strong>
                    <div class="export-list">
            HTML
            
            if tag_groups.length == 0
                html += "        <em>No entities found with valid tag ranges</em>\n"
            else
                tag_groups.each do |filename, entities|
                    html += "        • #{filename}.glb (#{entities.length} entities)<br>\n"
                end
            end
            
            html += <<-HTML
                    </div>
                </div>
                
                <div class="option-group">
                    <label>
                        <input type="checkbox" id="downscale-textures" checked>
                        Optimize Large Textures
                    </label>
                    <div class="info-text">
                        Downscales textures larger than 2048x2048 pixels to 50% size
                    </div>
                </div>
                
                <div class="info-text" style="background: #e8f4f8; padding: 10px; border-radius: 4px; margin: 10px 0;">
                    <strong>Export Method:</strong> Using simplified explosion approach for accurate global coordinates.
                    All transformations will be applied during export.
                </div>
                
                #{excluded_count > 0 ? "<div class='excluded-info'>#{excluded_count} layer(s) matching 'TrueVision_*_DoNotExportGLTF' will be excluded</div>" : ""}
                
                <div class="button-group">
                    <button onclick="performExport()" #{tag_groups.length == 0 ? 'disabled' : ''}>Export GLB Files</button>
                    <button onclick="window.location = 'skp:cancel'">Cancel</button>
                </div>
                
                <script>
                    function performExport() {
                        var selectionOnly = false;  // Always export by tags
                        var downscaleTextures = document.getElementById('downscale-textures').checked;
                        
                        // Pass parameters through the callback URL
                        var params = {
                            selectionOnly: selectionOnly,
                            downscaleTextures: downscaleTextures
                        };
                        
                        // Encode parameters and trigger callback
                        window.location = 'skp:export@' + JSON.stringify(params);
                    }
                </script>
            </body>
            </html>
            HTML
            
            html
        end
        # ---------------------------------------------------------------
    
        # SUB FUNCTION | Add Dialog Callbacks
        # ---------------------------------------------------------------
        def self.add_dialog_callbacks(dialog)
            # Export callback
            dialog.add_action_callback("export") do |action_context, params_string|
                puts "Export button clicked - getting parameters..."              # Debug log
                
                # Get parameters from the callback URL
                begin
                    if params_string && !params_string.empty?
                        puts "Parameters received: #{params_string}"              # Debug log
                        params = JSON.parse(params_string)                        # Parse JSON
                        @export_selection_only = params['selectionOnly']          # Set selection flag  
                        @downscale_textures = params['downscaleTextures']         # Set downscale flag
                        puts "Parsed parameters: selection=#{@export_selection_only}, downscale=#{@downscale_textures}"
                    else
                        # Default values if no parameters
                        @export_selection_only = false                            # Default values
                        @downscale_textures = true                                # Default values
                        puts "Using default parameters"
                    end
                    
                rescue => e
                    puts "Parameter parsing error: #{e.message}"                   # Log error
                    @export_selection_only = false                                 # Default values
                    @downscale_textures = true                                     # Default values
                end
                
                dialog.close                                                       # Close dialog
                
                # Get save directory from user
                export_dir = UI.select_directory(title: "Select Export Directory")
                
                if export_dir
                    puts "Starting export to directory: #{export_dir}"            # Debug log
                    perform_export(export_dir)                                     # Perform the export
                else
                    puts "Export cancelled - no directory selected"               # Debug log
                end
            end
            
            # Cancel callback
            dialog.add_action_callback("cancel") do |action_context|
                puts "Export cancelled by user"                                   # Debug log
                dialog.close                                                       # Close dialog
            end
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Menu Integration
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Add Export Option to Extensions Menu
        # ------------------------------------------------------------
        def self.add_to_menu
            # Get or create Vale Design Suite submenu in Extensions
            extensions_menu = UI.menu("Extensions")
            vale_submenu = nil
            
            # Check if Vale Design Suite submenu already exists
            # Note: SketchUp doesn't provide a direct way to check for existing submenus
            # So we'll just add to it - if it exists, it will use the existing one
            vale_submenu = extensions_menu.add_submenu("Vale Design Suite")
            
            # Add separator if menu has items (best effort)
            begin
                vale_submenu.add_separator
            rescue
                # Ignore if separator fails
            end
            
            # Add TrueVision GLB Builder menu item
            vale_submenu.add_item("TrueVisionApp | .GLB Builder Utility") {
                start_export                                                       # Trigger export
            }
            
            puts "TrueVision GLB Builder Utility added to Extensions > Vale Design Suite"
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Cleanup (Add at end of export)
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Cleanup Texture Cache
        # ---------------------------------------------------------------
        def self.cleanup_texture_cache
            return unless Dir.exist?(@texture_cache_folder)
            
            Dir.glob(File.join(@texture_cache_folder, "*")).each do |file|
                File.delete(file) if File.file?(file)
            end
            
            Dir.rmdir(@texture_cache_folder) if Dir.empty?(@texture_cache_folder)
            puts "      Cleaned up texture cache folder"
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------
    
    # -----------------------------------------------------------------------------
    # REGION | Plugin Initialization
    # -----------------------------------------------------------------------------
    
        # Initialize the GLB Builder Utility when loaded
        unless file_loaded?(__FILE__)
            ValeDesignSuite::GLBBuilderUtility.add_to_menu                        # Add menu items
            file_loaded(__FILE__)                                                  # Mark as loaded
        end
    
    # endregion -------------------------------------------------------------------

    end  # module GLBBuilderUtility
end  # module ValeDesignSuite