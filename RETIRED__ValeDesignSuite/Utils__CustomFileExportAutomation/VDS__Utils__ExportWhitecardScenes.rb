# =============================================================================
# VALEDESIGNSUITE - WHITECARD EXPORT AUTOMATION
# =============================================================================
#
# FILE       : VDS__Utils__ExportWhitecardScenes.rb
# NAMESPACE  : ValeDesignSuite
# MODULE     : ExportWhitecardScenes
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Automated export of whitecard render scenes to PNG and DWG formats
# CREATED    : 16-Sep-2025
#
# DESCRIPTION:
# - Automates the export of SketchUp whitecard render files
# - Exports scenes prefixed with IMG## as PNG images with standard settings
# - Optionally exports same IMG## scenes as CAD files with user consent
# - Appends date stamps and appropriate suffixes to exported files
# - Provides consistent export settings across all outputs
# - Integrates with Vale Design Suite main user interface
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 16-Sep-2025 - Version 1.0.0
# - Initial implementation of whitecard export automation
# - Support for PNG image exports with 6000x4000 resolution
# - Support for DWG CAD exports with Release 12 format
# - Date stamping and naming convention enforcement
#
# 16-Sep-2025 - Version 1.1.0
# - Fixed scene transition handling to prevent animation during export
# - Added configurable delay between scene changes for proper rendering
# - Fixed static position export issue with scene transitions
# - Implemented 2D DWG export using Windows automation (send_action method)
#
# 17-Sep-2025 - Version 1.2.0
# - Implemented conditional CAD export system with user opt-in dialog
# - Added CAD-specific custom naming with date and whitecard suffix appending
# - Separated CAD export workflow from PNG export workflow completely
# - Added Windows automation capability checking before offering CAD export
# - Enhanced export confirmation dialog to show CAD inclusion status
# - Preserved butter-smooth PNG export workflow without any changes
#
# 17-Sep-2025 - Version 1.3.0
# - Replaced unreliable Windows automation with manual dialog approach
# - CAD exports now use UI.savepanel with pre-populated custom filenames
# - Removed dependency on WIN32OLE and SendKeys automation
# - Added user-guided manual export process for better reliability
# - Each CAD scene shows save dialog with suggested filename then opens export dialog
#
# 17-Sep-2025 - Version 1.4.0
# - Fixed image export configuration to match manual SketchUp standards
# - Added proper line scale multiplier (2.0x) for correct line thickness
# - Updated to use hash format for view.write_image with scale_factor parameter
# - Added comprehensive image export constants with 3:2 aspect ratio support
# - Enhanced logging to show all export settings during image generation
#
# 25-Sep-2025 - Version 1.5.0
# - Consolidated workflow to use only IMG## tagged scenes for both image and CAD export
# - Removed separate DWG## scene handling to eliminate duplicate scene management
# - Added upfront user prompt for DWG export requirement before processing
# - Images exported first, then same scenes exported as CAD files if user opted in
# - Updated all dialogs and reports to reflect streamlined IMG-only workflow
# - Eliminates need to maintain duplicate IMG## and DWG## scenes in SketchUp model
#
# =============================================================================

module ValeDesignSuite
module ExportWhitecardScenes

# -----------------------------------------------------------------------------
# REGION | Embedded JSON Method & Function Index
# -----------------------------------------------------------------------------

    # EMBEDDED JSON | Script Method & Function Index
    # ------------------------------------------------------------
    SCRIPT_METHOD_INDEX = {
      "script_info": {
        "name": "ExportWhitecardScenes",
        "version": "1.5.0",
        "purpose": "Automated whitecard scene export from IMG## scenes with optional PNG and DWG export"
      },
      "constants": {
        "image_export": ["EXPORT_IMAGE_WIDTH", "EXPORT_IMAGE_HEIGHT", "EXPORT_IMAGE_ASPECT_RATIO", "EXPORT_IMAGE_LINE_SCALE", "EXPORT_IMAGE_ANTIALIAS", "EXPORT_IMAGE_TRANSPARENT", "EXPORT_IMAGE_COMPRESSION"],
        "cad_export": ["EXPORT_2D_ACTION_CODE", "EXPORT_CAD_FILE_FORMAT", "DIALOG_WAIT_TIME"],
        "naming": ["IMG_PREFIX_PATTERN", "WHITECARD_IMAGE_SUFFIX", "WHITECARD_CAD_SUFFIX"],
        "timing": ["SCENE_CHANGE_DELAY_SECONDS"]
      },
      "helper_functions": {
        "utilities": ["fetch_formatted_date", "append_whitecard_naming", "build_cad_filename_with_custom_naming"],
        "validation": ["validate_scene_prefix", "ensure_export_directory"],
        "automation": ["initialize_windows_automation", "check_cad_export_capability"],
        "scene_management": ["disable_scene_transitions", "restore_scene_transitions", "wait_for_scene_load"]
      },
      "export_functions": {
        "detection": ["detect_required_scenes"],
        "image": ["export_image_files", "configure_image_export_options"],
        "cad": ["export_cad_files_with_manual_dialog", "export_2d_dwg_with_manual_dialog"]
      },
      "ui_functions": {
        "dialogs": ["show_cad_export_opt_in_dialog", "show_export_dialog", "report_export_results"]
      },
      "main_functions": {
        "entry": ["execute_export_workflow"]
      }
    }.freeze
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Export Timing Settings
    # ------------------------------------------------------------
    SCENE_CHANGE_DELAY_SECONDS  =   1.0                                        # <-- Delay after scene change (seconds)
    # ------------------------------------------------------------
    
    
    # MODULE CONSTANTS | Standard Image Export Configuration Settings
    # ------------------------------------------------------------
    EXPORT_IMAGE_WIDTH           =   6000                                      # <-- Width in pixels (6000px)
    EXPORT_IMAGE_HEIGHT          =   4000                                      # <-- Height in pixels (4000px - 3:2 aspect ratio)
    EXPORT_IMAGE_ASPECT_RATIO    =   "3:2"                                     # <-- Aspect ratio (Width:Height)
    EXPORT_IMAGE_LINE_SCALE      =   2.0                                       # <-- Line scale multiplier (2.00x for proper thickness)
    EXPORT_IMAGE_ANTIALIAS       =   true                                      # <-- Enable anti-aliasing (TRUE)
    EXPORT_IMAGE_TRANSPARENT     =   false                                     # <-- Transparent background (FALSE)
    EXPORT_IMAGE_COMPRESSION     =   0.9                                       # <-- PNG compression quality (0.0-1.0)
    # ------------------------------------------------------------
    
    
    
    # MODULE CONSTANTS | Export 2D CAD Settings
    # ------------------------------------------------------------
    EXPORT_2D_ACTION_CODE        =   21237                                     # <-- Windows action code for 2D export
    EXPORT_CAD_FILE_FORMAT       =   "AutoCAD DWG Files (*.dwg)"              # <-- File format selection string
    DIALOG_WAIT_TIME             =   2.0                                       # <-- Time to wait for dialog to open
    # ------------------------------------------------------------
    
    
    # MODULE CONSTANTS | Naming Patterns and Prefixes
    # ------------------------------------------------------------
    IMG_PREFIX_PATTERN          =   /^IMG\d{2,3}/                              # <-- Matches IMG01, IMG001, etc.
    WHITECARD_IMAGE_SUFFIX      =   "__WhitecardImage"                         # <-- Suffix for image exports
    WHITECARD_CAD_SUFFIX        =   "__WhitecardCadFile"                       # <-- Suffix for CAD exports
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

    # MODULE VARIABLES | Export State Tracking
    # ------------------------------------------------------------
    @@export_directory          =   nil                                        # <-- Selected export directory
    @@img_scenes                =   []                                         # <-- IMG## scenes for both image and CAD export
    @@export_results            =   { images: [], cad: [], errors: [] }        # <-- Export operation results
    @@original_transitions      =   {}                                         # <-- Store original scene transition settings
    @@shell                     =   nil                                        # <-- Windows shell automation object
    @@user_wants_cad_export     =   false                                      # <-- User opted for CAD export
    @@cad_export_enabled        =   false                                      # <-- CAD export capability confirmed
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Helper Functions - Date and Naming Utilities
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Fetch Formatted Date String
    # ------------------------------------------------------------
    def self.fetch_formatted_date
        time = Time.now                                                        # <-- Get current time
        time.strftime("%d-%b-%Y")                                              # <-- Format as DD-MMM-YYYY
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Append Whitecard Naming to Scene Name
    # ------------------------------------------------------------
    def self.append_whitecard_naming(scene_name, export_type)
        date_string = fetch_formatted_date                                     # <-- Get formatted date
        
        case export_type
        when :image
            suffix = WHITECARD_IMAGE_SUFFIX                                    # <-- Use image suffix
            extension = ".png"                                                  # <-- PNG extension
        when :cad
            suffix = WHITECARD_CAD_SUFFIX                                      # <-- Use CAD suffix
            extension = ".dwg"                                                  # <-- DWG extension
        else
            return scene_name                                                   # <-- Return unchanged if unknown type
        end
        
        "#{scene_name}#{suffix}__#{date_string}#{extension}"                   # <-- Build complete filename
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Build CAD-Specific Filename with Custom Naming
    # ------------------------------------------------------------
    def self.build_cad_filename_with_custom_naming(scene_name)
        date_string = fetch_formatted_date                                     # <-- Get formatted date
        
        # Extract IMG prefix and convert to DWG prefix
        if scene_name.match?(IMG_PREFIX_PATTERN)
            img_prefix = scene_name.match(IMG_PREFIX_PATTERN)[0]               # <-- Extract IMG## code
            dwg_prefix = img_prefix.gsub('IMG', 'DWG')                         # <-- Convert IMG## to DWG##
            base_name = scene_name.gsub(IMG_PREFIX_PATTERN, '')                # <-- Remove IMG prefix from scene name
            
            # Build enhanced filename with DWG prefix, base name, whitecard suffix and date
            enhanced_name = "#{dwg_prefix}#{base_name}#{WHITECARD_CAD_SUFFIX}__#{date_string}"  # <-- Build complete name
        else
            # Fallback if no IMG prefix found
            enhanced_name = "#{scene_name}#{WHITECARD_CAD_SUFFIX}__#{date_string}"  # <-- Append whitecard suffix and date
        end
        
        enhanced_name                                                          # <-- Return enhanced name without extension
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Validate Scene Name Prefix
    # ------------------------------------------------------------
    def self.validate_scene_prefix(scene_name)
        return :img if scene_name.match?(IMG_PREFIX_PATTERN)                   # <-- Check for IMG prefix
        return nil                                                              # <-- No valid prefix found
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Ensure Export Directory Exists
    # ------------------------------------------------------------
    def self.ensure_export_directory
        unless @@export_directory && File.directory?(@@export_directory)       # <-- Check if directory set and exists
            @@export_directory = UI.select_directory(                          # <-- Prompt for directory selection
                title: "Select Export Directory for Whitecard Files"
            )
            return false unless @@export_directory                             # <-- Return false if cancelled
        end
        true                                                                    # <-- Directory confirmed
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Disable Scene Transitions
    # ------------------------------------------------------------
    def self.disable_scene_transitions
        model = Sketchup.active_model                                          # <-- Get active model
        page_options = model.options["PageOptions"]                            # <-- Get page options
        
        # Store original settings
        @@original_transitions[:transition_time] = page_options["TransitionTime"]     # <-- Store transition time
        @@original_transitions[:show_transition] = page_options["ShowTransition"]     # <-- Store transition enabled state
        
        puts "Original transitions - Show: #{@@original_transitions[:show_transition]}, Time: #{@@original_transitions[:transition_time]}"
        
        # Disable transitions and set time to zero
        page_options["ShowTransition"] = false                                 # <-- Disable scene transitions
        page_options["TransitionTime"] = 0.0                                   # <-- Set transition time to zero
        
        puts "Scene transitions disabled for export (was: #{@@original_transitions[:show_transition]})"  # <-- Log status
        true                                                                    # <-- Return that we disabled them
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Restore Scene Transitions
    # ------------------------------------------------------------
    def self.restore_scene_transitions
        return if @@original_transitions.empty?                                # <-- Exit if no settings stored
        
        model = Sketchup.active_model                                          # <-- Get active model
        page_options = model.options["PageOptions"]                            # <-- Get page options
        
        # Restore original settings
        page_options["ShowTransition"] = @@original_transitions[:show_transition]     # <-- Restore transition state
        page_options["TransitionTime"] = @@original_transitions[:transition_time]     # <-- Restore transition time
        
        puts "Scene transitions restored"                                      # <-- Log status
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Wait for Scene to Load
    # ------------------------------------------------------------
    def self.wait_for_scene_load
        # Force view update and wait
        Sketchup.active_model.active_view.refresh                              # <-- Force view refresh
        sleep(SCENE_CHANGE_DELAY_SECONDS)                                      # <-- Wait for scene to fully load
        
        # Process pending UI events to ensure scene is fully rendered
        UI.start_timer(0, false) {}                                            # <-- Process UI events
        sleep(0.1)                                                             # <-- Small additional delay for UI
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Initialize Windows Automation
    # ------------------------------------------------------------
    def self.initialize_windows_automation
        return @@shell if @@shell                                              # <-- Return existing shell if available
        
        begin
            if Sketchup.platform == :platform_win                             # <-- Check if running on Windows
                require 'win32ole'                                             # <-- Load Windows automation library
                @@shell = WIN32OLE.new("WScript.Shell")                        # <-- Create shell automation object
                puts "Windows automation initialized"                          # <-- Log success
            else
                puts "Warning: 2D DWG export only supported on Windows"        # <-- Warn about platform limitation
            end
        rescue LoadError => e
            puts "Error: WIN32OLE not available - #{e.message}"               # <-- Log error
        rescue => e
            puts "Error initializing Windows automation: #{e.message}"        # <-- Log error
        end
        
        @@shell                                                                # <-- Return shell object or nil
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Check CAD Export Capability
    # ------------------------------------------------------------
    def self.check_cad_export_capability
        # Initialize Windows automation if not already done
        initialize_windows_automation unless @@shell                           # <-- Setup automation
        
        if @@shell.nil?
            @@cad_export_enabled = false                                       # <-- Mark CAD export as disabled
            puts "CAD export disabled: Windows automation not available"       # <-- Log status
        else
            @@cad_export_enabled = true                                        # <-- Mark CAD export as enabled
            puts "CAD export capability confirmed"                             # <-- Log status
        end
        
        @@cad_export_enabled                                                   # <-- Return capability status
    end
    # ------------------------------------------------------------
    
    
    # HELPER FUNCTION | Show CAD Export Opt-In Dialog
    # ------------------------------------------------------------
    def self.show_cad_export_opt_in_dialog
        return false unless @@img_scenes.any?                                  # <-- Exit if no IMG scenes detected
        
        message = "Export Options\n\n"                                         # <-- Build message header
        message += "📷 #{@@img_scenes.length} IMG## scenes detected\n\n"        # <-- Show IMG scene count
        message += "Export Options:\n"
        message += "• PNG images will be exported automatically\n"
        message += "• DWG files can also be exported from the same scenes\n\n"
        message += "DWG exports will:\n"
        message += "• Show a save dialog with custom filename for each scene\n"
        message += "• Open SketchUp's 2D DWG export dialog for manual completion\n"
        message += "• Require user interaction for each export\n\n"
        message += "Export DWG files in addition to PNG images?\n\n"
        message += "(PNG exports will proceed automatically regardless of your choice)"  # <-- Clarify PNG independence
        
        result = UI.messagebox(message, MB_YESNO)                              # <-- Show opt-in dialog
        
        if result == IDYES
            @@user_wants_cad_export = true                                     # <-- User opted in
            puts "User opted for DWG export from IMG scenes"                   # <-- Log choice
        else
            @@user_wants_cad_export = false                                    # <-- User opted out
            puts "User declined DWG export - PNG only"                         # <-- Log choice
        end
        
        @@user_wants_cad_export                                               # <-- Return user choice
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Scene Detection and Classification
# -----------------------------------------------------------------------------

    # FUNCTION | Detect Required Scenes for Export
    # ------------------------------------------------------------
    def self.detect_required_scenes
        model = Sketchup.active_model                                          # <-- Get active model
        pages = model.pages                                                    # <-- Get all scenes/pages
        
        @@img_scenes.clear                                                     # <-- Clear previous IMG scenes
        
        pages.each do |page|                                                    # <-- Iterate through all scenes
            scene_name = page.name                                             # <-- Get scene name
            export_type = validate_scene_prefix(scene_name)                    # <-- Check prefix pattern
            
            if export_type == :img
                @@img_scenes << page                                           # <-- Add to IMG scene list
                puts "Found IMG scene: #{scene_name}"                          # <-- Log detection
            end
        end
        
        puts "Detected #{@@img_scenes.length} IMG## scenes for export"
        
        @@img_scenes.length > 0                                               # <-- Return true if scenes found
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Image Export Functions
# -----------------------------------------------------------------------------

    # SUB FUNCTION | Configure Standard Image Export Options Hash
    # ------------------------------------------------------------
    def self.configure_image_export_options
        {
            width:        EXPORT_IMAGE_WIDTH,                                  # <-- Image width in pixels (6000px)
            height:       EXPORT_IMAGE_HEIGHT,                                 # <-- Image height in pixels (4000px)
            antialias:    EXPORT_IMAGE_ANTIALIAS,                              # <-- Enable anti-aliasing (TRUE)
            compression:  EXPORT_IMAGE_COMPRESSION,                            # <-- PNG compression quality (0.9)
            transparent:  EXPORT_IMAGE_TRANSPARENT,                            # <-- Transparent background (FALSE)
            scale_factor: EXPORT_IMAGE_LINE_SCALE                              # <-- Line scale multiplier (2.0x for thickness)
        }
    end
    # ------------------------------------------------------------
    
    
    # FUNCTION | Export Image Files for Marked Scenes with Standard Configuration
    # ------------------------------------------------------------
    def self.export_image_files
        return unless @@img_scenes.any?                                        # <-- Exit if no IMG scenes
        
        model = Sketchup.active_model                                          # <-- Get active model
        view = model.active_view                                               # <-- Get active view
        
        puts "Starting PNG image export for #{@@img_scenes.length} IMG scenes..."
        
        @@img_scenes.each do |scene|                                           # <-- Process each IMG scene
            begin
                model.pages.selected_page = scene                              # <-- Activate the scene
                view.refresh                                                    # <-- Refresh the view
                wait_for_scene_load                                            # <-- Wait for scene to fully load
                
                filename = append_whitecard_naming(scene.name, :image)         # <-- Build filename
                filepath = File.join(@@export_directory, filename)             # <-- Create full path
                
                # Configure export options with all standard settings
                export_options = configure_image_export_options                 # <-- Get complete options hash
                export_options[:filename] = filepath                           # <-- Add filepath to options
                
                puts "Exporting image: #{filename}"                            # <-- Log export attempt
                puts "  Resolution: #{EXPORT_IMAGE_WIDTH}x#{EXPORT_IMAGE_HEIGHT} (#{EXPORT_IMAGE_ASPECT_RATIO})"
                puts "  Line Scale: #{EXPORT_IMAGE_LINE_SCALE}x"               # <-- Log line scale setting
                puts "  Anti-alias: #{EXPORT_IMAGE_ANTIALIAS}"                 # <-- Log anti-alias setting
                puts "  Transparent: #{EXPORT_IMAGE_TRANSPARENT}"              # <-- Log transparency setting
                
                # Export image using hash format with all settings
                success = view.write_image(export_options)                     # <-- Export with complete options hash
                
                if success
                    @@export_results[:images] << filename                      # <-- Record success
                    puts "✅ Exported: #{filename}"                            # <-- Log success
                else
                    raise "Failed to export image"                             # <-- Raise error on failure
                end
                
            rescue => e
                error_msg = "Error exporting #{scene.name}: #{e.message}"     # <-- Format error message
                @@export_results[:errors] << error_msg                         # <-- Record error
                puts "❌ #{error_msg}"                                         # <-- Log error
            end
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | CAD Export Functions
# -----------------------------------------------------------------------------

    # SUB FUNCTION | Export Single 2D DWG Using Manual File Dialog with Custom Naming
    # ------------------------------------------------------------
    def self.export_2d_dwg_with_manual_dialog(scene)
        # Build custom filename using enhanced naming
        custom_filename = build_cad_filename_with_custom_naming(scene.name)    # <-- Get custom filename
        suggested_filepath = File.join(@@export_directory, "#{custom_filename}.dwg")  # <-- Create suggested path
        
        begin
            puts "Requesting CAD export for scene: #{scene.name}"              # <-- Log export request
            
            # Show save dialog with custom filename pre-populated
            filepath = UI.savepanel(
                "Export 2D DWG - #{scene.name}",                              # <-- Dialog title with scene name
                @@export_directory,                                            # <-- Default directory
                "#{custom_filename}.dwg"                                       # <-- Default filename with extension
            )
            
            # Check if user cancelled the dialog
            unless filepath
                puts "User cancelled CAD export for #{scene.name}"            # <-- Log cancellation
                return { success: false, filename: "#{custom_filename}.dwg", cancelled: true }
            end
            
            # Trigger 2D export dialog and let user complete manually
            puts "Please complete the 2D DWG export manually in the dialog..."  # <-- Instruction to user
            puts "Suggested filename: #{File.basename(filepath)}"              # <-- Show suggested name
            
            Sketchup.send_action(EXPORT_2D_ACTION_CODE)                        # <-- Open 2D export dialog
            
            # Wait for user to complete export manually
            result = UI.messagebox(
                "Complete the 2D DWG export in the dialog that opened.\n\n" +
                "Suggested filename: #{File.basename(filepath)}\n\n" +
                "Click OK when export is complete, or Cancel if export failed.",
                MB_OKCANCEL
            )
            
            if result == IDOK
                return { success: true, filename: File.basename(filepath) }     # <-- Return success
            else
                return { success: false, filename: File.basename(filepath) }   # <-- Return failure
            end
            
        rescue => e
            puts "CAD export error: #{e.message}"                              # <-- Log error
            return { success: false, filename: "#{custom_filename}.dwg" }      # <-- Return failure on error
        end
    end
    # ------------------------------------------------------------
    
    
    # FUNCTION | Export 2D CAD Files for IMG Scenes with Manual Dialog Approach
    # ------------------------------------------------------------
    def self.export_cad_files_with_manual_dialog
        return unless @@img_scenes.any?                                        # <-- Exit if no IMG scenes
        return unless @@user_wants_cad_export                                  # <-- Exit if user declined CAD export
        
        puts "Starting DWG export workflow for #{@@img_scenes.length} IMG scenes..." # <-- Log start
        
        model = Sketchup.active_model                                          # <-- Get active model
        view = model.active_view                                               # <-- Get active view
        
        @@img_scenes.each_with_index do |scene, index|                         # <-- Process each IMG scene with index
            begin
                model.pages.selected_page = scene                              # <-- Activate the scene
                view.refresh                                                    # <-- Refresh the view
                wait_for_scene_load                                            # <-- Wait for scene to fully load
                
                puts "Processing DWG export #{index + 1} of #{@@img_scenes.length}: #{scene.name}"
                
                # Export as 2D DWG using manual dialog with custom naming
                result = export_2d_dwg_with_manual_dialog(scene)               # <-- Export with manual dialog
                
                if result[:cancelled]
                    puts "⚠️ CAD export cancelled for: #{scene.name}"          # <-- Log cancellation
                    # Don't treat cancellation as error, just skip
                elsif result[:success]
                    @@export_results[:cad] << result[:filename]                # <-- Record success
                    puts "✅ Exported 2D DWG: #{result[:filename]}"            # <-- Log success
                else
                    @@export_results[:errors] << "Failed to export #{scene.name}" # <-- Record error
                    puts "❌ Failed to export: #{scene.name}"                  # <-- Log error
                end
                
            rescue => e
                error_msg = "Error exporting #{scene.name}: #{e.message}"     # <-- Format error message
                @@export_results[:errors] << error_msg                         # <-- Record error
                puts "❌ #{error_msg}"                                         # <-- Log error
            end
        end
        
        puts "CAD export workflow completed"                                   # <-- Log completion
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Main Export Workflow and User Interface
# -----------------------------------------------------------------------------

    # SUB FUNCTION | Show Export Confirmation Dialog
    # ------------------------------------------------------------
    def self.show_export_dialog
        message = "Ready to export whitecard scenes:\n\n"                      # <-- Build message
        message += "📷 PNG Images: #{@@img_scenes.length} IMG## scenes\n"      # <-- Add image count
        
        # Add DWG information based on user choice
        if @@user_wants_cad_export
            message += "📐 DWG Files: #{@@img_scenes.length} scenes (MANUAL EXPORT)\n"  # <-- DWG export enabled
        else
            message += "📐 DWG Files: SKIPPED\n"                              # <-- DWG export skipped
        end
        
        message += "\nExport Sequence:\n"
        message += "1. All PNG images will export automatically\n"
        if @@user_wants_cad_export
            message += "2. DWG files will export with manual dialogs\n"
        else
            message += "2. DWG export skipped (user declined)\n"
        end
        
        message += "\nContinue with export?"                                   # <-- Add prompt
        
        result = UI.messagebox(message, MB_YESNO)                              # <-- Show confirmation dialog
        result == IDYES                                                         # <-- Return true if Yes clicked
    end
    # ------------------------------------------------------------
    
    
    # SUB FUNCTION | Report Export Results to User
    # ------------------------------------------------------------
    def self.report_export_results
        message = "Export Complete!\n\n"                                       # <-- Build header
        
        # Report image exports
        if @@export_results[:images].any?                                      # <-- Check for image exports
            message += "✅ PNG Images Exported: #{@@export_results[:images].length}\n"
        else
            message += "⚠️ PNG Images: None exported\n"
        end
        
        # Report CAD exports
        if @@export_results[:cad].any?                                         # <-- Check for CAD exports
            message += "✅ DWG Files Exported: #{@@export_results[:cad].length}\n"
        elsif @@user_wants_cad_export
            message += "⚠️ DWG Files: None exported (check for errors)\n"
        else
            message += "ℹ️ DWG Files: Skipped (user declined)\n"
        end
        
        # Report any errors
        if @@export_results[:errors].any?                                      # <-- Check for errors
            message += "\n❌ Errors:\n"
            @@export_results[:errors].each { |err| message += "• #{err}\n" }   # <-- List errors
        end
        
        # Add summary
        total_files = @@export_results[:images].length + @@export_results[:cad].length
        message += "\nTotal Files Exported: #{total_files}"
        
        UI.messagebox(message)                                                  # <-- Show results dialog
    end
    # ------------------------------------------------------------
    
    
    # FUNCTION | Execute Complete Export Workflow with Conditional CAD Export
    # ------------------------------------------------------------
    def self.execute_export_workflow
        # Reset export results and flags
        @@export_results = { images: [], cad: [], errors: [] }                 # <-- Clear previous results
        @@user_wants_cad_export = false                                        # <-- Reset user choice
        @@cad_export_enabled = false                                           # <-- Reset capability flag
        
        # Detect scenes to export
        unless detect_required_scenes                                          # <-- Find exportable IMG scenes
            UI.messagebox("No scenes found with IMG## prefixes.")              # <-- Alert if none found
            return
        end
        
        # Show export options dialog to ask about DWG export
        show_cad_export_opt_in_dialog                                          # <-- Show opt-in dialog for DWG export
        
        # Get export directory
        return unless ensure_export_directory                                  # <-- Ensure directory selected
        
        # Show confirmation dialog
        return unless show_export_dialog                                       # <-- Confirm with user
        
        # Disable scene transitions if needed
        transitions_were_disabled = disable_scene_transitions                   # <-- Disable transitions for export
        
        # Start operation
        model = Sketchup.active_model                                          # <-- Get active model
        model.start_operation("Export Whitecard Scenes", true)                 # <-- Start undo group
        
        begin
            # PHASE 1: Export all IMG scenes as PNG images (always happens)
            puts "\n=== PHASE 1: PNG IMAGE EXPORT ==="
            export_image_files if @@img_scenes.any?                            # <-- Export PNG files first
            
            # PHASE 2: Export same IMG scenes as DWG files (only if user opted in)
            if @@user_wants_cad_export && @@img_scenes.any?
                puts "\n=== PHASE 2: DWG CAD EXPORT ==="
                export_cad_files_with_manual_dialog                            # <-- Export DWG files second
            elsif @@user_wants_cad_export
                puts "\n=== PHASE 2: DWG CAD EXPORT SKIPPED (No IMG scenes) ==="
            else
                puts "\n=== PHASE 2: DWG CAD EXPORT SKIPPED (User declined) ==="
            end
            
            model.commit_operation                                             # <-- Commit operation
            
        rescue => e
            model.abort_operation                                              # <-- Abort on error
            @@export_results[:errors] << "Critical error: #{e.message}"        # <-- Record error
            puts "Critical error during export: #{e.message}"                  # <-- Log error
        ensure
            # Always restore scene transitions
            restore_scene_transitions                                           # <-- Restore original settings
        end
        
        # Report results
        report_export_results                                                   # <-- Show results dialog
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module ExportWhitecardScenes
end # module ValeDesignSuite
