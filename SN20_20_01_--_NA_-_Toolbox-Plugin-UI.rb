# ====================================================================================================
# FILE: SN20_20_01_--_NA_-_Toolbox-Plugin-UI_-_2.0.0.rb
# Noble Architecture | Unified Toolbox Plugin
#
# CHANGELOG:
# - All original features & logic fully restored
# - BIM Data Report: uses the shared stylesheet and your local LOGO_PATH
# - UI is styled consistently
# - Added Collapse Geometry tool for flattening topographic/layered content to a plane
# - Enhanced visual feedback for point selection tools
# - Added shared PointPickerTool for consistent point selection across all tools
# - Added Profile Path Tracer tool for extruding library profiles along paths
# ====================================================================================================

# region [col10] =====================================================================================
# ====================================================================================
# - - - - - - GPT INSTRUCTIONS SECTION |  EXPERT RUBY DEV INSTRUCTIONS - - - - - - - -
# ====================================================================================
#
# Your Role | You are an expert Sketchup Ruby Plugin Developer
# My Role   | I am your client Noble Architecture, you have built this current version for me Previously
#             My Experience level is zero, all changes must be flagged with inline comments like This....
#                   <General_Ruby_Code>    # <--- CHANGE : This has been updated
#                   <General_Ruby_Code>    # <--- CHANGE : This has been added
#                   <General_Ruby_Code>    # <--- CHANGE : This is a problem
# Outputs  |  All Outputs returned must be as CODE BLOCKS, commicate with me using comments in the code 
#             generated. This also helps me track past changes and updates easier
#
# Objective | Maintain the original functionality and style updates
#
# TASK 01 | Restore & unify the final BIM Reporter with local path logo & styling
#
# ------------------------------------------------------------------------------------
# region [col10] end
# ====================================================================================================


# region [col11] =====================================================================================
# FILE DETAILS
# File Name   |  SN20_20_01_--_NA_-_Toolbox-Plugin-UI_-_1.8.3.rb
# File Type   |  Ruby Script for SketchUp
# Author      |  Adam Noble – Noble Architecture
# Created     |  12-Mar-2025
# ----------------------------------------------------------------------------------------------------
# DESCRIPTION
# Noble Architecture SketchUp Toolbox Plugin
# Combines multiple useful tools into one convenient UI. Unified code, single stylesheet,
# and new BIM Reporter logic with local path & styles.
#
# USAGE NOTES
# 1. Open the plugin from SketchUp's Extensions menu (NA_Toolbox > Toolbox UI).
# 2. Choose a tool from the interface to run.
#
# DEVELOPMENT LOG
# (See historical notes above.)
# WHEN TIME ADD OLD NOTES HERE
# 23-Mar-2025 - 1.8.0 - Added Scene Exporter
# 26-Mar-2025 - 1.8.1 - Added Infinite XY Guide Lines Creator
# 26-Mar-2025 - 1.8.2 - Added BIM Entity Classifier integration
# 27-Mar-2025 - 1.8.3 - Added Staircase Maker with UK Building Regulations compliance
# 27-Mar-2025 - 1.8.4 - UI Dated for main menu, now collapses sections
# 27-Mar-2025 - 1.8.5 - Updated Isolate Tool, User interface now reflects isolation state
# 27-Mar-2025 - 1.8.6 - Added Collapse Geometry Tool with projection transformation
# 27-Mar-2025 - 1.8.7 - Enhanced CoordinateSnapper and CollapseGeometry with visual feedback
# 27-Mar-2025 - 1.8.8 - Added SharedTools::PointPickerTool for consistent point selection across tools
# 27-Mar-2025 - 1.8.9 - Enhanced PointPickerTool with title_prefix and document_action capabilities
# 27-Mar-2025 - 1.9.0 - Added dynamic status text with status_formatter to display coordinate values
# 27-Mar-2025 - 1.9.1 - Added 3D tooltips with customizable position and styling for point selection
# 27-Mar-2025 - 1.9.2 - Consolidated CSS styles across all tools for consistent form elements
# 27-Mar-2025 - 1.9.3 - Implemented CSS variables and utility classes for maximum style consistency
# 27-Mar-2025 - 1.9.4 - Enhanced Scene Exporter with parametric controls, unified styling, and improved error handling
# --------------------------------------
# 27-Mar-2025 - 1.9.5 - MAJOR UPDATE
# - Modernised Coordinate Snapper UI with HTML-based interface to match other tools
# - Added comprehensive tolerance options from 5mm to 10000mm
# - Enhanced visual feedback with 3D tooltips and position markers during point selection
# - Implemented shared styling conventions across tool interfaces with explanatory text
# - Added native SketchUp hotkey support for the main toolbox and deep paint tools
# - Created consolidated Noble Architecture toolbar with all primary tools
# - General code improvements and standardization across modules
# --------------------------------------
# 27-Mar-2025 - 1.9.6 - 29-Mar-2025 - Staircase Maker UI Update
# - Update the UI for staircase maker to match the new UI standards
# --------------------------------------
# 29-Apr-2025 - 1.9.7 - MAJOR UPDATE - New Tool Added - Offloaded the BIM Data Reporter to a separate plugin
# --------------------------------------
# 06-May-2025 - 1.9.8 -  Added SketchUp UI Button for a new View State Tool
# - Created a new View State Tool with a UI
# 15-May-2025 - 1.9.9 - Added mirror planes toggle tool
# 15-May-2025 - 2.0.0 - MAJOR UPDATE - Added Profile Path Tracer tool
# - Tool allows extrusion of profile components along edge paths
# - Profile components are loaded from a library folder
# - Implements visualization of thumbnails and profile selection interface
# - Includes path selection tool for edge chains
# - Extrudes profiles using SketchUp's followme functionality
#
# ===================================================================================================
# CRITICAL NOTES REGARDING SKETCHUP API CONVENTIONS
# ===================================================================================================
#
# - SketchUp's Native Unit System Is Inches, conversions to mm are needed often.
#
# LESSONS LEARNED FOR FUTURE RUBY DEVELOPERS
# - Unit Conversion: SketchUp internally uses inches as its native unit system, while Noble
#   Architecture primarily works in millimeters. ALL dimensional inputs/outputs must be
#   converted between these systems. Standard conversion factors:
#     * MM to Inches: multiply by 0.0393701 (or divide by 25.4)
#     * Inches to MM: multiply by 25.4
#   You can use the .mm method on numeric values to convert mm to SketchUp's internal inches:
#     * length_in_inches = 100.mm  # Converts 100mm to SketchUp's internal inches
#
# - Coordinate System: SketchUp uses a right-handed coordinate system that differs from many 
#   other 3D software packages:
#     * X-axis: Red axis, runs left to right (east-west)
#     * Y-axis: Green axis, runs front to back (north-south)
#     * Z-axis: Blue axis, runs bottom to top (vertical)
#   This is different from software like AutoCAD and Revit where Y is vertical.
#   When working with transformations, be mindful of these orientation differences.
#
# - Vertex Manipulation: SketchUp doesn't allow direct manipulation of vertex positions
#   with methods like position=. Instead, you must:
#     * Use transformation operations through parent entities
#     * Create new geometry with the desired positions
#     * Use transform_entities on the parent container for vertices
#
# - Performance Considerations: When manipulating large sets of geometry:
#     * Group operations in start_operation/commit_operation blocks
#     * Process higher-level entities (faces, groups) rather than individual vertices when possible
#     * Use transformation matrices for complex movement rather than manually recalculating points
#
# ===================================================================================================
# FUTURE IMPROVEMENT IDEAS
# ===================================================================================================
# -
# -
# - 
# region [col11] end
# ===================================================================================================


# region [col00] =====================================================================================
# U N I F I E D   S T Y L E S H E E T
# -----------------------------------------------------------------------------------------------------
# <--- CHANGE : Single shared stylesheet for all UI dialogs

module NobleArchitectureUnifiedStylesheet
    extend self

    def shared_stylesheet
        <<-CSS
        /******************************************************************************************
         *  NOBLE ARCHITECTURE TOOLBOX | UNIFIED STYLESHEET
         *  Each main HTML body is given a prefix-based class (e.g. NA_Toolbox_body, NA_Notebook_body, etc).
         *  IDs have also been prefixed for clarity.
         ******************************************************************************************/

        /* ========================== STYLE VARIABLES ========================== */
        :root {
            /* Colors */
            --na-text-color: #333333;
            --na-text-secondary: #444444;
            --na-text-muted: #666666;
            --na-background: #f8f8f8;
            --na-primary: #787369;
            --na-primary-hover: #555041;
            --na-border-color: #d0d0d0;
            --na-table-header-bg: #eaeaea;
            
            /* Typography */
            --na-font-size-base: 10.5pt;
            --na-font-size-h1: 18pt;
            --na-font-size-h2: 14pt;
            --na-font-size-button: 11pt;
            --na-font-size-small: 9pt;
            
            /* Spacing */
            --na-spacing-base: 20px;
            --na-spacing-sm: 10px;
            --na-spacing-xs: 5px;
            --na-spacing-lg: 30px;
            
            /* Borders */
            --na-border-radius: 4px;
        }

        /* ========================== GLOBAL NORMALISATION ========================== */
        body, html {
            margin: 0;
            padding: 0;
        }
        
        /* Common body styles for all tools */
        .NA_Toolbox_body, .NA_FrontFace_body, .NA_MaterialsCreator_body, 
        .NA_Notebook_body, .NA_BIM_Report_body, .NA_StairMaker_body,
        .NA_InfiniteGuide_body, .NA_CoordinateSnapper_body, .NA_CollapseGeometry_body,
        .NA_SceneExporter_body, .NA_StructuralMember_body {
            font-family: 'Open Sans', sans-serif;
            margin: var(--na-spacing-base);
            color: var(--na-text-color);
            background: var(--na-background);
            line-height: 1.4;
        }
        
        /* Common heading styles */
        h1, h2, h3, .NA_Toolbox_body h1, .NA_FrontFace_body h2, 
        .NA_MaterialsCreator_body h2, .NA_Notebook_body h2, .NA_BIM_Report_body h2,
        .NA_StairMaker_body h2, .NA_InfiniteGuide_body h2 {
            font-weight: 600;
            color: var(--na-text-color);
            margin-bottom: var(--na-spacing-sm);
        }
        
        h1, .NA_Toolbox_body h1 {
            font-size: var(--na-font-size-h1);
            margin-top: var(--na-spacing-lg);
            margin-bottom: var(--na-spacing-base);
        }
        
        h2, .NA_Toolbox_body h2, .NA_FrontFace_body h2, .NA_MaterialsCreator_body h2, .NA_Notebook_body h2, 
        .NA_BIM_Report_body h2, .NA_StairMaker_body h2, .NA_InfiniteGuide_body h2 {
            font-size: var(--na-font-size-h1);
            margin-bottom: var(--na-spacing-sm);
        }
        
        /* Common paragraph styles */
        p, .NA_FrontFace_body p, .NA_MaterialsCreator_body p, .NA_Notebook_body p, 
        .NA_StairMaker_body p, .NA_InfiniteGuide_body p {
            font-size: var(--na-font-size-base);
            color: var(--na-text-secondary);
            margin-bottom: var(--na-spacing-base);
        }
        
        /* Common button styles */
        button {
            cursor: pointer;
            transition: all 0.2s ease;
            border: none;
            border-radius: var(--na-border-radius);
            background: var(--na-primary);
            color: #ffffff;
            padding: var(--na-spacing-sm) var(--na-spacing-base);
            font-weight: 600;
            font-size: var(--na-font-size-button);
        }
        
        button:hover {
            background: var(--na-primary-hover);
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }

        /* ========================== STANDARDIZED HEADER STYLE ========================== */
        /* <--- CHANGE: Added standardized header styling */
        .NA_header {
            text-align: left;
            margin-bottom: 15px;
            padding-bottom: 15px;
            border-bottom: 1px solid #e0e0e0;
        }
        .NA_logo {
            width: 250px;
            height: auto;
            display: block;
            margin-top: 20px;
            margin-left: 10px;
            margin-right: auto;
            margin-bottom: 30px;
        }
        .NA_header h2 {
            font-family: 'Open Sans', sans-serif;
            font-weight: 600;
            font-size: 18pt; 
            color: #333333;
            margin-top: 20px;
            margin-left: 20px;
            margin-bottom: 10px;
        }

        /* ========================== MAIN TOOLBOX UI ========================== */
        .NA_Toolbox_body {
            text-align: center;
        }
        /* Remove the conflicting rule for .NA_Toolbox_body h2 */
        .NA_Toolbox_body button {
            width: 80%;
            padding: 12px;
            font-weight: 500;
            margin: var(--na-spacing-sm) auto;
            display: block;
        }

        /* ========================== FRONT-FACE AREA REPORT ========================== */
        .NA_FrontFace_body #NA_FrontFace_btnGenerate {
            margin-bottom: var(--na-spacing-sm);
        }
        .NA_FrontFace_body table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 14px;
            background: #ffffff;
            border: 1px solid var(--na-border-color);
        }
        .NA_FrontFace_body th, .NA_FrontFace_body td {
            border: 1px solid var(--na-border-color);
            padding: 8px;
            text-align: left;
            font-size: var(--na-font-size-base);
        }
        .NA_FrontFace_body th {
            background: var(--na-table-header-bg);
            font-weight: 600;
            cursor: pointer;
        }
        .NA_FrontFace_body .footer-text {
            margin-top: 16px;
            font-size: var(--na-font-size-small);
            color: var(--na-text-muted);
        }

        /* ========================== MATERIALS CREATOR & NOTEBOOK ========================== */
        .NA_MaterialsCreator_body, .NA_Notebook_body {
            max-width: 460px;
        }
        .NA_MaterialsCreator_body textarea#NA_MaterialsCreator_input,
        .NA_Notebook_body #NA_Notebook_notepad {
            width: calc(100% - 16px);
            padding: 15px;
            margin-top: var(--na-spacing-sm);
            font-family: 'Open Sans', sans-serif;
            font-size: var(--na-font-size-base);
            border: 1px solid var(--na-border-color);
            border-radius: var(--na-border-radius);
            background: #ffffff;
            color: var(--na-text-secondary);
            min-height: 450px;
            margin-left: 5px;
            margin-right: 30px;
        }
        .NA_Notebook_body #NA_Notebook_notepad {
            resize: vertical;
        }
        .NA_Notebook_body #NA_Notebook_status {
            font-size: 10pt;
            color: var(--na-text-muted);
            margin-top: var(--na-spacing-sm);
            text-align: right;
            font-style: italic;
        }
        .NA_Notebook_body .NA_Notebook_autosave_status {
            font-size: var(--na-font-size-small);
            color: var(--na-primary);
            margin-top: 5px;
        }
        .NA_Notebook_body .NA_Notebook_button_container {
            display: flex;
            justify-content: space-between;
            margin-top: 15px;
        }

        /* ======================== BIM DATA REPORTER ======================== */
        .NA_BIM_Report_header {
            text-align: left;
            margin-bottom: 15px;
            padding-bottom: 15px;
            border-bottom: 1px solid #e0e0e0;
        }
        .NA_BIM_Report_logo {
            width: 75mm;
            height: auto;
            display: block;
            margin-top: var(--na-spacing-base);
            margin-left: var(--na-spacing-sm);
            margin-right: auto;
            margin-bottom: 30px;
        }
        .NA_BIM_Report_body h2 {
            margin-bottom: 0px;
        }
        .NA_BIM_Report_spinner {
            border: 6px solid #f3f3f3;
            border-top: 6px solid var(--na-primary);
            border-radius: 50%;
            width: 48px;
            height: 48px;
            animation: spin 1s linear infinite;
        }
        .NA_BIM_Report_loading_text {
            font-size: 14pt;
            margin-top: var(--na-spacing-base);
            text-align: center;
        }
        @keyframes spin {
            0%   { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .NA_BIM_btnBar button {
            margin-right: 12px;
        }
        .NA_BIM_Report_body table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 14px;
            background: #ffffff;
            border: 1px solid var(--na-border-color);
        }
        .NA_BIM_Report_body th, .NA_BIM_Report_body td {
            border: 1px solid var(--na-border-color);
            padding: 8px;
            text-align: left;
            font-size: var(--na-font-size-base);
        }
        .NA_BIM_Report_body th {
            background: var(--na-table-header-bg);
            font-weight: 600;
            cursor: pointer;
        }
        .NA_BIM_footer_text {
            margin-top: 16px;
            font-size: var(--na-font-size-small);
            color: var(--na-text-muted);
        }
        
        /* ========================== COMMON FORM ELEMENTS ========================== */
        /* Form groups - for consistent form layouts across all tools */
        .NA_form_group, .NA_StairMaker_form_group, .NA_InfiniteGuide_form_group {
            margin-bottom: 15px;
        }
        .NA_form_group label, .NA_StairMaker_form_group label, .NA_InfiniteGuide_form_group label {
            display: block;
            margin-bottom: 5px;
            font-weight: 500;
            font-size: var(--na-font-size-base);
        }
        .NA_form_group input, .NA_StairMaker_form_group input, .NA_InfiniteGuide_form_group input[type="text"],
        .NA_form_group input[type="number"], .NA_StairMaker_form_group input[type="number"] {
            width: 100%;
            padding: 8px;
            box-sizing: border-box;
            border: 1px solid var(--na-border-color);
            border-radius: var(--na-border-radius);
            font-size: var(--na-font-size-base);
        }
        /* Field errors */
        .NA_error, .NA_StairMaker_error {
            color: red;
            margin-top: 5px;
            display: none;
        }
        /* Checkbox styling */
        .NA_checkbox, .NA_InfiniteGuide_checkbox {
            margin: 15px 0;
        }
        .NA_checkbox label, .NA_InfiniteGuide_checkbox label {
            display: flex;
            align-items: center;
            font-size: var(--na-font-size-base);
        }
        .NA_checkbox input, .NA_InfiniteGuide_checkbox input {
            margin-right: 8px;
        }
        /* Buttons */
        .NA_button, .NA_StairMaker_button, .NA_InfiniteGuide_button {
            padding: 10px 15px;
            background-color: var(--na-primary);
            color: white;
            border: none;
            border-radius: var(--na-border-radius);
            cursor: pointer;
            font-weight: 600;
            font-size: var(--na-font-size-button);
            margin-top: var(--na-spacing-sm);
            transition: all 0.2s ease;
        }
        .NA_button:hover, .NA_StairMaker_button:hover, .NA_InfiniteGuide_button:hover {
            background-color: var(--na-primary-hover);
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }
        /* Results section */
        .NA_results, .NA_StairMaker_results {
            margin-top: var(--na-spacing-base);
            display: none;
        }

        /* Added styles for collapsible sections */
        .NA_Toolbox_body {
            text-align: left;  /* Changed from center to left */
        }
        
        .NA_Toolbox_body h1 {
            text-align: center;
        }
        
        .NA_Toolbox_section {
            margin-bottom: 15px;
        }
        
        .NA_Toolbox_section_header {
            display: flex;
            align-items: center;
            cursor: pointer;
            padding: 8px 5px;
            background-color: #eee;
            border-radius: var(--na-border-radius);
        }
        
        .NA_Toolbox_section_header:hover {
            background-color: #e0e0e0;
        }
        
        .NA_Toolbox_section_header h2 {
            margin: 0;
            flex-grow: 1;
            font-size: 10.5pt; /* <--- CHANGE: Decreased dropdown heading size by 25% (from 14pt to 10.5pt) */
        }
        
        .NA_Toolbox_toggle_icon {
            font-size: 18px;
            margin-right: var(--na-spacing-sm);
            transition: transform 0.3s;
        }
        
        .NA_Toolbox_section_content {
            overflow: hidden;
            transition: max-height 0.3s ease-out;
        }
        
        .NA_Toolbox_section.collapsed .NA_Toolbox_toggle_icon {
            transform: rotate(-90deg);
        }
        
        .NA_Toolbox_section.collapsed .NA_Toolbox_section_content {
            max-height: 0;
        }
        
        .NA_Toolbox_body button {
            margin: var(--na-spacing-sm) auto;
        }
        
        /* Utility classes for common display needs */
        .NA_display_none {
            display: none;
        }
        .NA_display_flex {
            display: flex;
        }
        .NA_flex_column {
            flex-direction: column;
        }
        .NA_items_center {
            align-items: center;
        }
        .NA_justify_center {
            justify-content: center;
        }
        .NA_full_height {
            height: 100vh;
        }
        .NA_text_center {
            text-align: center;
        }
        .NA_text_right {
            text-align: right;
        }
        .NA_margin_top_sm {
            margin-top: var(--na-spacing-sm);
        }
        .NA_margin_top {
            margin-top: var(--na-spacing-base);
        }
        .NA_margin_bottom_sm {
            margin-bottom: var(--na-spacing-sm);
        }
        .NA_margin_bottom {
            margin-bottom: var(--na-spacing-base);
        }
        .NA_padding {
            padding: var(--na-spacing-base);
        }
        
        /* Input controls */
        .NA_input_medium {
            width: 280px;
            padding: 8px;
            font-size: var(--na-font-size-button);
        }
        
        /* Text utilities */
        .NA_text_secondary {
            color: var(--na-text-secondary);
        }
        
        CSS
    end

    # <--- CHANGE: Added standardized header HTML generator
    def generate_header(title, logo_path)
        <<-HTML
        <div class="NA_header">
            <img src="C://Users/adamw/AppData/Roaming/SketchUp/SketchUp 2025/SketchUp/Plugins/na_plugin-dependencies/RE20_22_01_01_-_PNG_-_NA_Company_Logo.png" 
            class="NA_logo" alt="Noble Architecture">
            <h2>#{title}</h2>
        </div>
        HTML
    end
end

# endregion [col00] -----------------------------------------------------------------------------------------------


# region [col01] =====================================================================================
# MAIN PLUGIN SCRIPT
# -----------------------------------------------------------------------------------------------------

require 'sketchup.rb'
require 'fileutils'

# <--- CHANGE : The main BIM Classifier tool we previously used
require 'SN20_20_02_--_NA_-_BIM-Classifier-Tool.rb'
require 'SN20_20_03_--_NA_-_BIM-Attribute-Editor.rb'

# endregion [col01]


# region [col01a] =====================================================================================
# SHARED TOOLS MODULE - Reusable tools for multiple modules
# -----------------------------------------------------------------------------------------------------
# Created | 29-Mar-2025
#
# DESCRIPTION
# This section contains tools that are shared among multiple modules to ensure
# consistent behavior and reduce code duplication.
#
module NobleArchitectureToolbox
    module SharedTools
        # PointPickerTool - A reusable tool for picking points in 3D space
        # This tool provides consistent visual feedback and callback handling
        # for all point-selection operations across the Noble Architecture toolset.
        class PointPickerTool
            # Initialize the tool with a callback and optional parameters
            # @param callback [Proc] The callback to execute when a point is selected
            # @param options [Hash] Optional parameters
            # @option options [String] :status_text The static status text to display during point picking
            # @option options [Proc] :status_formatter A callback to dynamically format status text (takes a point as parameter)
            # @option options [Float] :marker_size Size of the 3D marker in model units (default: 4.0)
            # @option options [String] :color The color of the marker (CSS color name or hex)
            # @option options [String] :title_prefix Text to add to the model window title (e.g. "Creating Beam -")
            # @option options [Symbol] :document_action Action to perform after completion (:save, :save_as, etc.)
            # @option options [Hash] :tooltip Configuration for a 3D tooltip near the cursor
            # @option options[:tooltip] [Proc] :content Callback that returns tooltip text (takes point parameter)
            # @option options[:tooltip] [Symbol] :position Where to place tooltip (:right, :left, :above, :below)
            # @option options[:tooltip] [String] :color Text color for tooltip (default: black)
            # @option options[:tooltip] [String] :background Background color for tooltip (default: white)
            # @option options[:tooltip] [Integer] :opacity Tooltip background opacity 0-255 (default: 230)
            def initialize(callback, options = {})
                @callback = callback
                @ip = Sketchup::InputPoint.new
                
                # Default options
                @static_status_text = options[:status_text] || "Click to select a point"
                @status_formatter = options[:status_formatter]
                @marker_size = options[:marker_size] || 4.0
                @title_prefix = options[:title_prefix]
                @document_action = options[:document_action]
                @original_title = Sketchup.active_model.title
                
                # Tooltip options
                @tooltip = options[:tooltip]
                if @tooltip
                    # Set default values for tooltip if not provided
                    @tooltip[:position] ||= :right
                    @tooltip[:color] ||= Sketchup::Color.new(0, 0, 0) # Black text
                    
                    # Convert string colors to SketchUp::Color objects
                    if @tooltip[:color].is_a?(String) && @tooltip[:color].start_with?('#')
                        hex = @tooltip[:color].sub(/^#/, '')
                        r = hex[0..1].to_i(16)
                        g = hex[2..3].to_i(16)
                        b = hex[4..5].to_i(16)
                        @tooltip[:color] = Sketchup::Color.new(r, g, b)
                    end
                    
                    # Background color with opacity
                    bg_color = @tooltip[:background] || "#FFFFFF" # White by default
                    opacity = @tooltip[:opacity] || 230 # 0-255, default 230 (90% opaque)
                    
                    if bg_color.is_a?(String) && bg_color.start_with?('#')
                        hex = bg_color.sub(/^#/, '')
                        r = hex[0..1].to_i(16)
                        g = hex[2..3].to_i(16)
                        b = hex[4..5].to_i(16)
                        @tooltip[:background] = Sketchup::Color.new(r, g, b, opacity)
                    else
                        @tooltip[:background] = Sketchup::Color.new(255, 255, 255, opacity)
                    end
                    
                    # Font size in model units
                    @tooltip[:font_size] ||= 0.3 # Default font size in model units
                    @tooltip[:padding] ||= 0.15  # Default padding in model units
                    @tooltip[:offset] ||= 1.0    # Default offset from cursor in model units
                end
                
                # Set marker color - default to Noble Architecture golden yellow
                color_value = options[:color] || "#FFC800"
                if color_value.is_a?(String) && color_value.start_with?("#")
                    # Convert hex color to RGB
                    hex = color_value.sub(/^#/, '')
                    r = hex[0..1].to_i(16)
                    g = hex[2..3].to_i(16)
                    b = hex[4..5].to_i(16)
                    @color = Sketchup::Color.new(r, g, b)
                else
                    # Use a predefined color
                    @color = Sketchup::Color.new(255, 200, 0) # Default yellow
                end
            end
            
            def activate
                # Set initial status text
                Sketchup.status_text = @static_status_text
                
                # Update window title if title_prefix option is set
                if @title_prefix && !@title_prefix.empty?
                    model = Sketchup.active_model
                    @original_title = model.title
                    model.title = "#{@title_prefix} #{@original_title}"
                end
                
                # Ensure the view is updated
                Sketchup.active_model.active_view.invalidate
            end
            
            def deactivate(view)
                # Restore original title
                if @title_prefix && !@title_prefix.empty?
                    Sketchup.active_model.title = @original_title
                end
                view.invalidate
            end
            
            def onMouseMove(flags, x, y, view)
                @ip.pick(view, x, y)
                
                # Update status text dynamically if a formatter is provided
                if @status_formatter && @ip.valid?
                    dynamic_status = @status_formatter.call(@ip.position)
                    Sketchup.status_text = dynamic_status if dynamic_status
                end
                
                view.invalidate
            end
            
            def onLButtonDown(flags, x, y, view)
                @ip.pick(view, x, y)
                if @ip.valid?
                    # Execute the callback with the selected point
                    @callback.call(@ip.position) if @callback
                    
                    # Perform document action if specified
                    perform_document_action if @document_action
                    
                    # Deactivate the tool
                    Sketchup.active_model.select_tool(nil)
                end
            end
            
            def draw(view)
                # Only draw if we have a valid input point
                if @ip.valid?
                    # Standard InputPoint visualization
                    @ip.draw(view)
                    
                    # Enhanced visual feedback - 3D cross marker
                    position = @ip.position
                    view.drawing_color = @color
                    view.line_width = 2
                    
                    # Draw a 3D cross at the input point
                    size = @marker_size
                    view.draw(GL_LINES, [
                        Geom::Point3d.new(position.x - size, position.y, position.z),
                        Geom::Point3d.new(position.x + size, position.y, position.z),
                        Geom::Point3d.new(position.x, position.y - size, position.z),
                        Geom::Point3d.new(position.x, position.y + size, position.z),
                        Geom::Point3d.new(position.x, position.y, position.z - size),
                        Geom::Point3d.new(position.x, position.y, position.z + size)
                    ])
                    
                    # Draw 3D tooltip if configured
                    draw_tooltip(view, position) if @tooltip && @tooltip[:content]
                end
            end
            
            # Draw a 3D tooltip near the cursor position
            def draw_tooltip(view, position)
                return unless @tooltip && @tooltip[:content]
                
                # Get tooltip content
                tooltip_text = @tooltip[:content].call(position)
                return if tooltip_text.nil? || tooltip_text.empty?
                
                # Calculate tooltip position based on specified position
                offset = @tooltip[:offset] || 1.0
                padding = @tooltip[:padding] || 0.15
                
                # Create a transformation to align tooltip with camera view
                camera = view.camera
                up = camera.up
                target = camera.target
                eye = camera.eye
                
                # Calculate view direction vector
                view_vector = target - eye
                view_vector.length = 1.0 # Normalize
                
                # Calculate right vector
                right_vector = view_vector * up
                right_vector.length = 1.0 # Normalize
                
                # Calculate position offset based on specified position
                case @tooltip[:position]
                when :right
                    offset_vector = right_vector * offset
                when :left
                    offset_vector = right_vector * -offset
                when :above
                    offset_vector = up * offset
                when :below
                    offset_vector = up * -offset
                else
                    # Default to right if position is invalid
                    offset_vector = right_vector * offset
                end
                
                # Calculate tooltip position
                tooltip_position = position + offset_vector
                
                # Draw tooltip background
                font_size = @tooltip[:font_size] || 0.3
                line_height = font_size * 1.2
                
                # Approximate text dimensions
                lines = tooltip_text.split("\n")
                max_line_length = lines.map(&:length).max
                box_width = max_line_length * font_size * 0.6
                box_height = lines.length * line_height
                
                # Draw tooltip background rectangle
                view.drawing_color = @tooltip[:background]
                
                # Create tooltip points
                half_width = box_width / 2 + padding
                half_height = box_height / 2 + padding
                
                # Tooltip coordinates
                left = -half_width
                right = half_width
                top = half_height
                bottom = -half_height
                
                # Create rectangle in 3D space
                points = [
                    [left, bottom, 0],
                    [right, bottom, 0],
                    [right, top, 0],
                    [left, top, 0]
                ]
                
                # Create a transformation to position and orient the tooltip
                # First create rotation to orient tooltip to face camera
                tr = Geom::Transformation.new(tooltip_position, view_vector)
                
                # Draw the rectangle background
                view.drawing_color = @tooltip[:background]
                tooltip_pts = points.map { |pt| Geom::Point3d.new(pt[0], pt[1], pt[2]).transform(tr) }
                view.draw(GL_QUADS, tooltip_pts)
                
                # Draw text
                view.drawing_color = @tooltip[:color]
                
                # Calculate start position for text
                text_x = left + padding / 2
                text_y = top - padding - font_size
                
                # Draw each line of text
                lines.each_with_index do |line, index|
                    text_position = Geom::Point3d.new(text_x, text_y - (index * line_height), 0).transform(tr)
                    view.draw_text(text_position, line, font_size: font_size)
                end
            end
            
            def getExtents
                bb = Geom::BoundingBox.new
                bb.add(@ip.position) if @ip.valid?
                bb
            end
            
            # Cancel method - called when user cancels the operation (e.g., by pressing Esc)
            def onCancel(reason, view)
                # Restore original title
                if @title_prefix && !@title_prefix.empty?
                    Sketchup.active_model.title = @original_title
                end
                # Clean up any resources if needed
                Sketchup.active_model.select_tool(nil)
            end
            
            private
            
            # Perform document action based on the specified symbol
            def perform_document_action
                model = Sketchup.active_model
                
                case @document_action
                when :save
                    # Save the current model
                    model.save
                when :save_as
                    # Open the save dialog
                    model.save_as
                when :save_copy
                    # Save a copy of the model
                    model.save_copy
                end
                
                # Additional actions could be added here
            end
        end
    end
end
# endregion [col01a]


# region [col02] =====================================================================================
# NOBLE ARCHITECTURE TOOLBOX USER INTERFACE MODULE SECTION
# -----------------------------------------------------------------------------------------------------
module NobleArchitectureToolbox
    extend self

    # <--- CHANGE : Define plugin_dir & local LOGO_PATH
    plugin_dir = File.dirname(__FILE__)
    LOGO_PATH  = File.join(plugin_dir, "na_plugin-dependencies", "RE20_22_01_01_-_PNG_-_NA_Company_Logo.png")

    def run
        dialog = UI::HtmlDialog.new(
            dialog_title:    "Noble Architecture | Toolbox",
            preferences_key: "com.noble-architecture.toolbox",
            scrollable:      true,
            resizable:       true,
            width:           300,
            height:          1250,
            style:           UI::HtmlDialog::STYLE_DIALOG
        )

        # <--- CHANGE : Insert the shared stylesheet + HTML
        html_content = <<-HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <title>Noble Architecture | Toolbox</title>
                <style>
                #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                
                /* Added styles for collapsible sections */
                .NA_Toolbox_body {
                    text-align: left;  /* Changed from center to left */
                }
                
                .NA_Toolbox_body h1 {
                    text-align: center;
                }
                
                .NA_Toolbox_section {
                    margin-bottom: 15px;
                }
                
                .NA_Toolbox_section_header {
                    display: flex;
                    align-items: center;
                    cursor: pointer;
                    padding: 8px 5px;
                    background-color: #eee;
                    border-radius: 4px;
                }
                
                .NA_Toolbox_section_header:hover {
                    background-color: #e0e0e0;
                }
                
                .NA_Toolbox_section_header h2 {
                    margin: 0;
                    flex-grow: 1;
                }
                
                .NA_Toolbox_toggle_icon {
                    font-size: 18px;
                    margin-right: 10px;
                    transition: transform 0.3s;
                }
                
                .NA_Toolbox_section_content {
                    overflow: hidden;
                    transition: max-height 0.3s ease-out;
                }
                
                .NA_Toolbox_section.collapsed .NA_Toolbox_toggle_icon {
                    transform: rotate(-90deg);
                }
                
                .NA_Toolbox_section.collapsed .NA_Toolbox_section_content {
                    max-height: 0;
                }
                
                .NA_Toolbox_body button {
                    margin: var(--na-spacing-sm) auto;
                }
                </style>
            </head>
            <body class="NA_Toolbox_body">
                
                <div class="NA_header">
                    <img src="file:///#{LOGO_PATH}" class="NA_logo" alt="Noble Architecture">
                    <h2>Noble Architecture | Toolbox</h2>
                </div>

                <div class="NA_Toolbox_section collapsed" id="section_view_state">
                    <div class="NA_Toolbox_section_header" onclick="toggleSection('section_view_state')">
                        <div class="NA_Toolbox_toggle_icon">▼</div>
                        <h2>View State Tools</h2>
                    </div>
                    <div class="NA_Toolbox_section_content">
                        <button id="btnIsolateToggle" onclick="sketchup.toggleIsolation()">Isolate Selected</button>
                        <button onclick="sketchup.runDuplicateSelectedTool()">Duplicate Selected</button>
                        <button id="btnFrameworkToggle" onclick="sketchup.toggleFrameworkView()">Show Framework Only</button>
                        <button id="btnMirrorToggle" onclick="sketchup.toggleMirrorPlanes()">Hide Mirror Planes</button>
                    </div>
                </div>

                <div class="NA_Toolbox_section collapsed" id="section_organisation">
                    <div class="NA_Toolbox_section_header" onclick="toggleSection('section_organisation')">
                        <div class="NA_Toolbox_toggle_icon">▼</div>
                        <h2>Model Organisation Tools</h2>
                    </div>
                    <div class="NA_Toolbox_section_content">
                        <button onclick="sketchup.runCoordinateSnapper()">Coordinate Snapper</button>
                        <button onclick="sketchup.runUnTagSelection()">Un-Tag Selection</button>
                        <button onclick="sketchup.runUniqueRenameTool()">Unique Rename Tool</button>
                        <button onclick="sketchup.runInfiniteGuideCreator()">Infinite XY Guides</button>
                    </div>
                </div>

                <div class="NA_Toolbox_section collapsed" id="section_geometry">
                    <div class="NA_Toolbox_section_header" onclick="toggleSection('section_geometry')">
                        <div class="NA_Toolbox_toggle_icon">▼</div>
                        <h2>Raw Geometry Processing Tools</h2>
                    </div>
                    <div class="NA_Toolbox_section_content">
                        <button onclick="sketchup.runGroupFaceIslandsTool()">Group Face Islands</button>
                        <button onclick="sketchup.runDeepPaintFacesTool()">Deep Paint Face</button>
                        <button onclick="sketchup.runMakeFacesTool()">Make Faces</button>
                        <button onclick="sketchup.runCollapseGeometryTool()">Collapse Geometry</button>
                        <button onclick="sketchup.runProfilePathTracer()">Profile Path Tracer</button>
                    </div>
                </div>

                <div class="NA_Toolbox_section collapsed" id="section_bim">
                    <div class="NA_Toolbox_section_header" onclick="toggleSection('section_bim')">
                        <div class="NA_Toolbox_toggle_icon">▼</div>
                        <h2>BIM Object Creation</h2>
                    </div>
                    <div class="NA_Toolbox_section_content">
                        <button onclick="sketchup.runNobleBIMEntityClassifier()">BIM    –   Entity Classifier</button>
                        <button onclick="sketchup.runBimAttributeEditor()">BIM    –   Attribute Editor</button>
                        <button onclick="sketchup.runNA_StructuralMemberObjectCreation()">BIM    –   Structural Member Creator</button>
                        <button onclick="sketchup.runStairMaker()">BIM    –   Staircase Maker</button>
                    </div>
                </div>

                <div class="NA_Toolbox_section collapsed" id="section_reports">
                    <div class="NA_Toolbox_section_header" onclick="toggleSection('section_reports')">
                        <div class="NA_Toolbox_toggle_icon">▼</div>
                        <h2>Report Generation Tools</h2>
                    </div>
                    <div class="NA_Toolbox_section_content">
                        <button onclick="sketchup.runNotebookPlugin()">Notebook</button>
                        <button onclick="sketchup.runBIMReporter()">BIM Data Report</button>
                        <button onclick="sketchup.runFrontFaceAreaReport()">Front-Face Area Report</button>
                        <button onclick="sketchup.runMaterialsReport()">Materials Report</button>
                        <button onclick="sketchup.runMaterialsCreator()">Materials Creator</button>
                        <button onclick="sketchup.runSceneToImageExporter()">Export Scene Images</button>
                    </div>
                </div>
                
                <script>
                    function toggleSection(sectionId) {
                        const section = document.getElementById(sectionId);
                        section.classList.toggle('collapsed');
                    }
                    
                    function updateIsolationButtonText(text) {
                        document.getElementById('btnIsolateToggle').textContent = text;
                    }
                    
                    function updateFrameworkButtonText(text) {
                        document.getElementById('btnFrameworkToggle').textContent = text;
                    }
                    
                    function updateMirrorPlanesButtonText(text) {
                        document.getElementById('btnMirrorToggle').textContent = text;
                    }
                    
                    // Initialize when page loads
                    window.onload = function() {
                        sketchup.checkIsolationState();
                        sketchup.checkFrameworkViewState();
                        sketchup.checkMirrorPlanesState();
                    };
                </script>
            </body>
            </html>
        HTML

        dialog.set_html(html_content)

        # -----------------------------------------------------------------------------------
        # Action Callbacks
        # -----------------------------------------------------------------------------------
        # Tool Callbacks
        dialog.add_action_callback('runDuplicateSelectedTool') do
            NA_Tools::DuplicateSelectedEntityTool.run
        end

        dialog.add_action_callback('runCoordinateSnapper') do
            NA_Tools::MasterTools::CoordinateSnapperTool.new.run
        end

        dialog.add_action_callback('runUnTagSelection') do
            NA_Tools::MasterTools::UntagSelectionTool.new.execute
        end

        dialog.add_action_callback('runUniqueRenameTool') do
            NA_Tools::UniqueRenameTool.run
        end

        dialog.add_action_callback('runInfiniteGuideCreator') do
            NA_Tools::InfiniteGuideCreator.run
        end
        
        dialog.add_action_callback('runGroupFaceIslandsTool') do
            NA_Tools::GroupFaceIslandsTool.run
        end
        
        dialog.add_action_callback('runDeepPaintFacesTool') do
            NA_Tools::DeepPaintFacesTool.run
        end
        
        dialog.add_action_callback('runMakeFacesTool') do
            NA_Tools::MakeFacesTool.run
        end
        
        dialog.add_action_callback('runCollapseGeometryTool') do
            NA_Tools::CollapseGeometryTool.run
        end
        
        dialog.add_action_callback('runNobleBIMEntityClassifier') do
            begin
                require 'SN20_20_02_--_NA_-_BIM-Classifier-Tool.rb'
                na_classifier = SN20_BIM_Classifier::BIMClassification.new
                na_classifier.run
            rescue LoadError => e
                UI.messagebox("Could not load BIM Classifier: #{e.message}")
            end
        end

        dialog.add_action_callback('runBIMReporter') do
            require 'SN20_20_04_--_NA_-_BIM-Data-Report-Generator.rb'
            NA::BIM::DataReport.run(LOGO_PATH)
        end
        
        dialog.add_action_callback('runBimAttributeEditor') do
            require 'SN20_20_03_--_NA_-_BIM-Attribute-Editor.rb'
            NA_BIM_AttrEditor.run(false)
        end

        dialog.add_action_callback('runNA_StructuralMemberObjectCreation') do
            NA_Tools::NA_StructuralMemberObjectCreation.NA_METHOD_CreateSteelElement
        end
        
        dialog.add_action_callback('runStairMaker') do
            NA_Tools::StairMaker::StairGenerator.new.create_dialog
        end
        
        dialog.add_action_callback('runNotebookPlugin') do
            NA_Tools::NotebookPlugin.show_notebook
        end
        
        dialog.add_action_callback('runFrontFaceAreaReport') do
            NA_Tools::FrontFaceReport.run
        end
        
        dialog.add_action_callback('runMaterialsReport') do
            NA_Tools::MaterialsReporter.export_materials_report
        end
        
        dialog.add_action_callback('runMaterialsCreator') do
            NA_Tools::NobleMaterialsCreator.run
        end
        
        dialog.add_action_callback('runSceneToImageExporter') do
            NA_Tools::SceneToImageExporter.run
        end

        dialog.add_action_callback('runProfilePathTracer') do
            NA_Tools::ProfilePathTracer.run
        end

        # View State Tool Callbacks
        dialog.add_action_callback('toggleIsolation') do
            NA_Tools::IsolateSelectedEntityTool.toggle_isolation
            button_text = NA_Tools::IsolateSelectedEntityTool.current_state_text
            dialog.execute_script("updateIsolationButtonText('#{button_text}')")
        end
        dialog.add_action_callback('checkIsolationState') do
            button_text = NA_Tools::IsolateSelectedEntityTool.current_state_text
            dialog.execute_script("updateIsolationButtonText('#{button_text}')")
        end

        dialog.add_action_callback('toggleFrameworkView') do
            NA_Tools::ViewStateTool.toggle_framework_view
            button_text = NA_Tools::ViewStateTool.current_state_text
            dialog.execute_script("updateFrameworkButtonText('#{button_text}')")
        end

        dialog.add_action_callback('checkFrameworkViewState') do
            button_text = NA_Tools::ViewStateTool.current_state_text
            dialog.execute_script("updateFrameworkButtonText('#{button_text}')")
        end
        
        dialog.add_action_callback('toggleMirrorPlanes') do
            NA_Tools::MirrorPlanesTool.toggle_mirror_planes
            button_text = NA_Tools::MirrorPlanesTool.current_state_text
            dialog.execute_script("updateMirrorPlanesButtonText('#{button_text}')")
        end

        dialog.add_action_callback('checkMirrorPlanesState') do
            button_text = NA_Tools::MirrorPlanesTool.current_state_text
            dialog.execute_script("updateMirrorPlanesButtonText('#{button_text}')")
        end

        dialog.show
    end

end
# endregion [col02]


# region [col03] =====================================================================================
# N A  _  T O O L S   M O D U L E
# -----------------------------------------------------------------------------------------------------
module NobleArchitectureToolbox
    module NA_Tools
        extend self

        # region [col03a] UniqueRenameTool
        module UniqueRenameTool
            extend self

            def run
                model     = Sketchup.active_model
                selection = model.selection

                model.start_operation("Rename Components and Make Unique", true)
                selection.each do |entity|
                    next unless entity.is_a?(Sketchup::ComponentInstance)
                    definition = entity.definition
                    entity.make_unique if definition.instances.length > 1
                    definition = entity.definition
                    definition.name = definition.name + "_-_02"
                end
                model.commit_operation

                UI.messagebox("Components renamed successfully.")
            end
        end
        # endregion


        # region [col03_collapse] CollapseGeometryTool
        module CollapseGeometryTool
            extend self

            def run
                dialog = UI::HtmlDialog.new(
                    dialog_title:    "Noble Architecture | Collapse Geometry",
                    preferences_key: "com.noble-architecture.collapse-geometry",
                    scrollable:      true,
                    resizable:       true,
                    width:           450,
                    height:          550,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )

                html_content = <<-HTML
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                        <meta charset="UTF-8">
                        <title>Noble Architecture | Collapse Geometry</title>
                        <style>
                        #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                        
                        .NA_CollapseGeometry_body {
                            font-family: 'Open Sans', sans-serif;
                            margin: 20px;
                            color: #333333;
                            background: #f8f8f8;
                        }
                        .NA_CollapseGeometry_body h2 {
                            font-weight: 600;
                            font-size: 18pt;
                            color: #333333;
                            margin-bottom: 10px;
                        }
                        .NA_CollapseGeometry_body p {
                            font-size: 10.5pt;
                            color: #444444;
                            line-height: 1.5;
                            margin-bottom: 20px;
                        }
                        .NA_CollapseGeometry_info {
                            background: #f0f0f0;
                            padding: 15px;
                            border-radius: 4px;
                            margin-bottom: 25px;
                            border-left: 3px solid #787369;
                        }
                        .NA_CollapseGeometry_option_group {
                            margin-bottom: 20px;
                        }
                        .NA_CollapseGeometry_option_group label {
                            display: block;
                            font-weight: 500;
                            margin-bottom: 5px;
                        }
                        .NA_CollapseGeometry_option_group input[type="checkbox"] {
                            margin-right: 10px;
                        }
                        .NA_CollapseGeometry_button {
                            background: #787369;
                            color: #ffffff;
                            border: none;
                            padding: 12px 20px;
                            border-radius: 4px;
                            font-weight: 600;
                            font-size: 11pt;
                            cursor: pointer;
                            margin-top: 10px;
                            transition: all 0.2s ease;
                        }
                        .NA_CollapseGeometry_button:hover {
                            background: #555041;
                        }
                        .NA_CollapseGeometry_explanation {
                            font-weight: 300;
                            color: #666666;
                            margin-left: 4px;
                        }
                        </style>
                    </head>
                    <body class="NA_CollapseGeometry_body">
                        #{NobleArchitectureUnifiedStylesheet.generate_header("Collapse Geometry", NobleArchitectureToolbox::LOGO_PATH)}
                        
                        <div class="NA_CollapseGeometry_info">
                            <p>This tool flattens your selected geometry to a plane, useful for converting topographic data, building sections, or any layered content to a flat representation.</p>
                            <p>First <strong>select the geometry to flatten</strong>, then select which plane to flatten to.</p>
                        </div>
                        
                        <div class="NA_CollapseGeometry_option_group">
                            <label><input type="radio" name="plane" id="xy_plane" checked> Flatten to XY Plane <span class="NA_CollapseGeometry_explanation">(all Z values same)</span></label>
                            <label><input type="radio" name="plane" id="xz_plane"> Flatten to XZ Plane <span class="NA_CollapseGeometry_explanation">(all Y values same)</span></label>
                            <label><input type="radio" name="plane" id="yz_plane"> Flatten to YZ Plane <span class="NA_CollapseGeometry_explanation">(all X values same)</span></label>
                        </div>
                        
                        <div class="NA_CollapseGeometry_option_group">
                            <label><input type="radio" name="reference" id="use_zero" checked> Use Zero (0) as reference value</label>
                            <label><input type="radio" name="reference" id="use_bounds"> Use bounds center as reference value</label>
                            <label><input type="radio" name="reference" id="pick_point"> Pick a reference point</label>
                        </div>
                        
                        <button class="NA_CollapseGeometry_button" onclick="runCollapse()">Collapse Geometry</button>
                        
                        <script>
                            function getSelectedPlane() {
                                if (document.getElementById('xy_plane').checked) return 'xy';
                                if (document.getElementById('xz_plane').checked) return 'xz';
                                if (document.getElementById('yz_plane').checked) return 'yz';
                                return 'xy'; // Default to XY
                            }
                            
                            function getSelectedReference() {
                                if (document.getElementById('use_zero').checked) return 'zero';
                                if (document.getElementById('use_bounds').checked) return 'bounds';
                                if (document.getElementById('pick_point').checked) return 'pick';
                                return 'zero'; // Default to zero
                            }
                            
                            function runCollapse() {
                                const plane = getSelectedPlane();
                                const reference = getSelectedReference();
                                sketchup.collapseGeometry(plane, reference);
                            }
                        </script>
                    </body>
                    </html>
                HTML

                dialog.set_html(html_content)
                
                dialog.add_action_callback("collapseGeometry") do |action_context, plane, reference|
                    collapse_geometry(plane, reference)
                end
                
                dialog.show
            end
            
            def collapse_geometry(plane, reference)
                model = Sketchup.active_model
                selection = model.selection
                
                # Verify we have geometry to collapse
                if selection.empty?
                    UI.messagebox("Please select geometry to collapse before running this tool.")
                    return
                end
                
                # Different handling based on reference type
                if reference == 'pick'
                    # For 'pick' option, we launch a tool and let it handle the operation
                    # Save selected entities for the callback to use
                    entities_to_process = selection.to_a
                    
                    # Set up callback for when a point is picked
                    callback = lambda do |point|
                        # Process the collapse with the picked point
                        process_collapse(plane, point, entities_to_process)
                    end
                    
                    # Create a status formatter to show coordinate values
                    status_formatter = lambda do |point|
                        # Display different coordinate based on which plane we're collapsing to
                        coordinate_value = case plane
                                          when 'xy' then "Z = #{point.z.to_mm.round(1)} mm"
                                          when 'xz' then "Y = #{point.y.to_mm.round(1)} mm"
                                          when 'yz' then "X = #{point.x.to_mm.round(1)} mm"
                                          end
                        
                        "Click to pick a reference point for geometry collapse (#{coordinate_value})"
                    end
                    
                    # Create tooltip content generator for rich 3D tooltip
                    tooltip_content = lambda do |point|
                        # Basic info about point
                        x_mm = point.x.to_mm.round(1)
                        y_mm = point.y.to_mm.round(1)
                        z_mm = point.z.to_mm.round(1)
                        
                        # Highlight the important coordinate based on plane
                        case plane
                        when 'xy'
                            "Reference Point\nX: #{x_mm} mm\nY: #{y_mm} mm\n→ Z: #{z_mm} mm ←"
                        when 'xz'
                            "Reference Point\nX: #{x_mm} mm\n→ Y: #{y_mm} mm ←\nZ: #{z_mm} mm"
                        when 'yz'
                            "Reference Point\n→ X: #{x_mm} mm ←\nY: #{y_mm} mm\nZ: #{z_mm} mm"
                        end
                    end
                    
                    # Launch the shared point picker tool with our callback
                    model.select_tool(
                        SharedTools::PointPickerTool.new(
                            callback,
                            {
                                status_text: "Click to pick a reference point for geometry collapse",
                                status_formatter: status_formatter,
                                marker_size: 4.0,
                                color: "#FFC800", # Noble Architecture yellow
                                title_prefix: "Collapsing Geometry to #{plane.upcase} Plane -",
                                tooltip: {
                                    content: tooltip_content,
                                    position: :right,
                                    color: "#FFFFFF", # White text
                                    background: "#555041", # Dark gold background
                                    opacity: 200,
                                    font_size: 0.35,
                                    padding: 0.2,
                                    offset: 1.5
                                }
                            }
                        )
                    )
                else
                    # For non-pick options, process immediately
                    process_collapse(plane, reference, selection.to_a)
                end
            end
            
            # Process the collapse operation with known values
            def process_collapse(plane, reference, entities)
                model = Sketchup.active_model
                
                # Calculate reference value based on reference type
                ref_value = if reference.is_a?(Geom::Point3d)
                              # Extract coordinate from point based on plane
                              get_coordinate_from_point(plane, reference)
                          else
                              # Handle string reference types
                              case reference
                              when 'zero'
                                  0.0
                              when 'bounds'
                                  calculate_bounds_center(plane, entities)
                              else
                                  0.0 # Default fallback
                              end
                          end
                
                # Start the operation
                model.start_operation("Collapse Geometry to Plane", true)
                
                begin
                    # Create the proper projection transformation
                    projection = create_projection_transformation(plane, ref_value)
                    
                    # Apply projection to all selected entities at once
                    model.active_entities.transform_entities(projection, *entities)
                    
                    model.commit_operation
                    
                    # Report success
                    plane_name = case plane
                                when 'xy' then "XY (all Z = #{ref_value.round(2)})"
                                when 'xz' then "XZ (all Y = #{ref_value.round(2)})"
                                when 'yz' then "YZ (all X = #{ref_value.round(2)})"
                                end
                    
                    UI.messagebox("Successfully collapsed geometry to #{plane_name} plane.")
                rescue => e
                    model.abort_operation
                    UI.messagebox("Error during collapse: #{e.message}")
                    puts "Error in CollapseGeometryTool: #{e.message}"
                    puts e.backtrace.join("\n")
                end
            end
            
            # Calculate the appropriate center coordinate based on bounds
            def calculate_bounds_center(plane, entities)
                bb = Geom::BoundingBox.new
                entities.each { |e| bb.add(e.bounds) unless e.is_a?(Sketchup::Text) }
                
                case plane
                when 'xy' then bb.center.z
                when 'xz' then bb.center.y
                when 'yz' then bb.center.x
                else 0.0
                end
            end
            
            # Extract the appropriate coordinate from a point based on plane
            def get_coordinate_from_point(plane, point)
                case plane
                when 'xy' then point.z
                when 'xz' then point.y
                when 'yz' then point.x
                else 0.0
                end
            end
            
            # Create a transformation that projects to the target plane
            def create_projection_transformation(plane, value)
                case plane
                when 'xy'
                    # XY Plane (Z = value)
                    return Geom::Transformation.scaling(1, 1, 0) * 
                           Geom::Transformation.translation([0, 0, value])
                           
                when 'xz'
                    # XZ Plane (Y = value)
                    return Geom::Transformation.scaling(1, 0, 1) * 
                           Geom::Transformation.translation([0, value, 0])
                           
                when 'yz'
                    # YZ Plane (X = value)
                    return Geom::Transformation.scaling(0, 1, 1) * 
                           Geom::Transformation.translation([value, 0, 0])
                end
                
                # Default to identity if somehow an invalid plane is specified
                Geom::Transformation.identity
            end
            
            # Note: The CollapsePickTool class has been replaced with the more versatile
            # SharedTools::PointPickerTool to provide consistent point-picking behavior
            # across all tools in the Noble Architecture Toolbox.
        end
        # endregion


        # region [col03b] FrontFaceAreaReport
        module FrontFaceReport
            extend self

            def run
                @dialog = UI::HtmlDialog.new(
                    dialog_title:    "Noble Architecture | Front-Face Area Report",
                    preferences_key: "com.noble-architecture.front-face-area-report",
                    scrollable:      true,
                    resizable:       true,
                    width:           560,
                    height:          900,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )
                @dialog.set_html(html_main)
                @dialog.add_action_callback("generateReport") { generate_report }
                @dialog.add_action_callback("exportCSV")      { export_csv }
                @dialog.show
            end

            def html_main
                <<-HTML
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="UTF-8">
                    <title>Noble Architecture | Front-Face Area Report</title>
                    <style>
                    #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                    </style>
                </head>
                <body class="NA_FrontFace_body">
                    #{NobleArchitectureUnifiedStylesheet.generate_header("Front-Face Area Report", NobleArchitectureToolbox::LOGO_PATH)}
                    <p>Select faces in your model, then click "Generate Report".</p>
                    <button id="NA_FrontFace_btnGenerate" onclick="onGenerateClick()">Generate Report</button>
                    <button id="NA_FrontFace_btnExport" onclick="onExportCSV()" class="NA_display_none">Export CSV</button>

                    <table id="areaTable" class="NA_display_none">
                      <thead>
                        <tr>
                          <th onclick="onSortColumn(0)">Material Name</th>
                          <th onclick="onSortColumn(1)">Area (m²)</th>
                        </tr>
                      </thead>
                      <tbody id="tableBody"></tbody>
                    </table>

                    <div class="footer-text">
                        Noble Architecture – Front-Face Area Report v1.0.0
                    </div>

                    <script>
                    let rowData = [];
                    let currentSortCol = 0;
                    let currentSortDir = 1;

                    function onGenerateClick() {
                        sketchup.generateReport();
                    }
                    function loadTableData(jsArray) {
                        rowData = jsArray;
                        currentSortCol = 0;
                        currentSortDir = 1;
                        sortAndRender();
                        document.getElementById('areaTable').style.display = '';
                        document.getElementById('NA_FrontFace_btnExport').style.display = '';
                    }
                    function onSortColumn(colIndex) {
                        if (colIndex === currentSortCol) {
                            currentSortDir = -currentSortDir;
                        } else {
                            currentSortCol = colIndex;
                            currentSortDir = 1;
                        }
                        sortAndRender();
                    }
                    function sortAndRender() {
                        rowData.sort((a, b) => {
                            let x = (a[currentSortCol].toLowerCase) ? a[currentSortCol].toLowerCase() : a[currentSortCol];
                            let y = (b[currentSortCol].toLowerCase) ? b[currentSortCol].toLowerCase() : b[currentSortCol];
                            if (x < y) return -1 * currentSortDir;
                            if (x > y) return 1 * currentSortDir;
                            return 0;
                        });
                        renderTable();
                    end
                    function onExportCSV() {
                        sketchup.exportCSV();
                    }
                    function downloadCSV(csvString) {
                        const blob = new Blob([csvString], { type: 'text/csv' });
                        const url  = URL.createObjectURL(blob);
                        const link = document.createElement('a');
                        link.href        = url;
                        link.download    = 'front_face_area_report.csv';
                        document.body.appendChild(link);
                        link.click();
                        document.body.removeChild(link);
                        URL.revokeObjectURL(url);
                    }
                    </script>
                </body>
                </html>
                HTML
            end

            def generate_report
                model = Sketchup.active_model
                sel   = model.selection
                faces = sel.grep(Sketchup::Face)
                area_by_mat = Hash.new(0.0)

                faces.each do |face|
                    mat = face.material
                    next if mat.nil?
                    area_sq_in = face.area
                    area_sq_m  = area_sq_in * 0.00064516
                    area_by_mat[mat] += area_sq_m
                end

                report_rows = area_by_mat.map do |mat, total_area|
                    [mat.display_name, format('%.2f', total_area)]
                end

                require 'json'
                @dialog.execute_script("loadTableData(#{report_rows.to_json})")
            end

            def export_csv
                model = Sketchup.active_model
                sel   = model.selection
                faces = sel.grep(Sketchup::Face)
                return if faces.empty?

                area_by_mat = Hash.new(0.0)
                faces.each do |face|
                    mat = face.material
                    next if mat.nil?
                    area_sq_in = face.area
                    area_sq_m  = area_sq_in * 0.00064516
                    area_by_mat[mat] += area_sq_m
                end

                csv_content = "Material Name,Area (m2)\n"
                area_by_mat.each do |mat, total_area|
                    csv_content << "#{mat.display_name},#{format('%.2f', total_area)}\n"
                end

                escaped = csv_content
                          .gsub("\\", "\\\\")
                          .gsub("\n", "\\n")
                          .gsub("\r", "")
                          .gsub("'", "\\'")

                @dialog.execute_script("downloadCSV('#{escaped}')")
            end
        end
        # endregion


        # region [col03c] MaterialsReporter
        module MaterialsReporter
            extend self

            def export_materials_report
                model     = Sketchup.active_model
                materials = model.materials
                m_data    = []

                materials.each do |material|
                    row = []
                    row << material.display_name

                    case material.materialType
                    when 0 # no texture
                        color = material.color
                        row << "#{color.red}, #{color.green}, #{color.blue}"
                        row << rgb_to_hex(color.red, color.green, color.blue)
                        row << ""
                    when 1, 2 # texture or colorize
                        if material.texture
                            row << ""
                            row << ""
                            row << File.basename(material.texture.filename)
                        else
                            color = material.color
                            row << "#{color.red}, #{color.green}, #{color.blue}"
                            row << rgb_to_hex(color.red, color.green, color.blue)
                            row << ""
                        end
                    else
                        row << ""
                        row << ""
                        row << ""
                    end

                    row << "#{(material.alpha * 100).round}%"
                    m_data << row
                end

                md_table = create_markdown_table(m_data)
                export_to_txt(md_table)
            end

            def rgb_to_hex(r, g, b)
                r = [[r, 255].min, 0].max
                g = [[g, 255].min, 0].max
                b = [[b, 255].min, 0].max
                format("#%02x%02x%02x", r, g, b)
            end

            def create_markdown_table(data)
                table  = "| Material Name | R, G , B Value | Nearest Hex Code | Image Texture | Opacity |\n"
                table << "| -------------- | -------------- | ---------------- | ------------- | ------- |\n"
                data.each do |row|
                    table << "| #{row.join(' | ')} |\n"
                end
                table
            end

            def export_to_txt(markdown_table)
                filepath = UI.savepanel("Save Materials Report", Dir.home, "MaterialsReport.txt")
                return unless filepath
                begin
                    File.write(filepath, markdown_table)
                    UI.messagebox("Materials report exported successfully to:\n#{filepath}")
                rescue => e
                    UI.messagebox("Error exporting report:\n#{e.message}")
                end
            end
        end
        # endregion


        # region [col03d] NobleMaterialsCreator
        module NobleMaterialsCreator
            extend self

            def run
                dialog = UI::HtmlDialog.new(
                    dialog_title:    "SketchUp Materials Creator",
                    preferences_key: "com.noble-architecture.sketchup-materials-creator",
                    scrollable:      true,
                    resizable:       true,
                    width:           450,
                    height:          700,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )

                html_content = <<-HTML
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                        <meta charset="UTF-8">
                        <title>Noble Architecture | Materials Creator</title>
                        <style>
                        #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                        </style>
                    </head>
                    <body class="NA_MaterialsCreator_body">
                        #{NobleArchitectureUnifiedStylesheet.generate_header("Materials Creator", NobleArchitectureToolbox::LOGO_PATH)}
                        <p>Paste the materials table below, then click 'Create Materials':</p>
                        <textarea id="NA_MaterialsCreator_input" placeholder="Paste your materials table here..."></textarea>
                        <button id="NA_MaterialsCreator_create" onclick="createMaterials()">Create Materials</button>
                        <script>
                            function createMaterials() {
                                const input = document.getElementById('NA_MaterialsCreator_input').value;
                                if (input.trim() === '') {
                                    alert('Input cannot be empty.');
                                    return;
                                }
                                sketchup.createMaterials(input);
                            }
                        </script>
                    </body>
                    </html>
                HTML

                dialog.set_html(html_content)
                dialog.add_action_callback('createMaterials') do |_dlg, user_input|
                    create_materials(user_input)
                end
                dialog.show
            end

            def create_materials(input)
                lines = input.split("\n")
                # Skip first 6 lines (header row or formatting lines)
                lines = lines.drop(6)

                list = []
                lines.each do |line|
                    line = line.strip
                    next if line.empty?
                    columns = line.split('|').map(&:strip)
                    next if columns.size < 3
                    hex_code       = columns[0]
                    material_name  = columns[1]
                    opacity_string = columns[2]
                    list << [hex_code, material_name, opacity_string]
                end

                model     = Sketchup.active_model
                materials = model.materials

                list.each do |(hex, name, op_str)|
                    r, g, b = hex_to_rgb(hex)
                    alpha   = op_str.to_f / 100.0
                    alpha   = 1.0 if alpha > 1.0
                    alpha   = 0.0 if alpha < 0.0

                    mat = materials[name] || materials.add(name)
                    mat.color = Sketchup::Color.new(r, g, b)
                    mat.alpha = alpha
                end
                UI.messagebox("Materials created or updated successfully.")
            end

            def hex_to_rgb(hex_str)
                hex_str = hex_str.gsub('#', '')
                return [128, 128, 128] if hex_str.size < 6
                r = hex_str[0..1].to_i(16)
                g = hex_str[2..3].to_i(16)
                b = hex_str[4..5].to_i(16)
                [r, g, b]
            end
        end
        # endregion


        # region [col03e] GroupFaceIslandsTool
        module GroupFaceIslandsTool
            extend self

            def run
                model = Sketchup.active_model
                model.start_operation('Group Face Islands', true)
                group_face_islands
                model.commit_operation
            end

            def group_face_islands
                model = Sketchup.active_model
                sel   = model.selection
                ents  = model.active_entities

                faces = sel.grep(Sketchup::Face)
                edges = sel.grep(Sketchup::Edge)
                return if faces.empty?

                processed = []

                faces.each do |face|
                    next if processed.include?(face) || face.deleted?

                    c_faces = find_connected_faces(face, faces, edges)
                    c_edges = c_faces.flat_map(&:edges).uniq & edges

                    group   = ents.add_group(c_faces + c_edges)
                    group.name = "Island Group #{group.entityID}"
                    processed.concat(c_faces)
                end
            end

            def find_connected_faces(face, faces, edges)
                found = [face]
                queue = [face]

                while queue.any?
                    current = queue.pop
                    current.edges.each do |e|
                        next unless edges.include?(e)
                        e.faces.each do |adj|
                            next if found.include?(adj) || !faces.include?(adj)
                            found << adj
                            queue << adj
                        end
                    end
                end
                found
            end
        end
        # endregion


        # region [col03f] NA_StructuralMemberObjectCreation
        module NA_StructuralMemberObjectCreation
            extend self

            module NA_DATA_LIBRARY_StructuralSteel
                module NA_HASH_UniversalBeams
                    UNIVERSAL_BEAM_SIZES = {
                        "UB 152x89x16"   => { width: 89,  height: 152, flange_thickness:  8, web_thickness:  5 },
                        "UB 178x102x19"  => { width: 102, height: 178, flange_thickness:  8, web_thickness:  6 },
                        "UB 203x102x23"  => { width: 102, height: 203, flange_thickness:  9, web_thickness:  6 },
                        "UB 254x102x25"  => { width: 102, height: 254, flange_thickness: 10, web_thickness:  6 },
                        "UB 305x102x28"  => { width: 102, height: 305, flange_thickness: 10, web_thickness:  6 },
                        "UB 356x127x33"  => { width: 127, height: 356, flange_thickness: 11, web_thickness:  7 },
                        "UB 406x140x39"  => { width: 140, height: 406, flange_thickness: 12, web_thickness:  7 },
                        "UB 457x152x52"  => { width: 152, height: 457, flange_thickness: 13, web_thickness:  8 },
                        "UB 533x210x82"  => { width: 210, height: 533, flange_thickness: 14, web_thickness: 10 },
                        "UB 610x229x113" => { width: 229, height: 610, flange_thickness: 18, web_thickness: 12 }
                    } unless defined?(UNIVERSAL_BEAM_SIZES)
                end

                module NA_HASH_UniversalColumns
                    UNIVERSAL_COLUMN_SIZES = {
                        "UC 152x152x23" => { width: 152, height: 152, flange_thickness: 7,  web_thickness: 6 },
                        "UC 203x203x46" => { width: 203, height: 203, flange_thickness: 11, web_thickness: 8 },
                        "UC 254x254x73" => { width: 254, height: 254, flange_thickness: 15, web_thickness: 9 },
                        "UC 305x305x97" => { width: 305, height: 305, flange_thickness: 16, web_thickness: 10 }
                    } unless defined?(UNIVERSAL_COLUMN_SIZES)
                end

                module NA_HASH_SquareHollowSections
                    SQUARE_HOLLOW_SECTION_SIZES = {
                        "SHS 40x40x3"   => { width: 40,   height: 40,  wall_thickness: 3 },
                        "SHS 50x50x3"   => { width: 50,   height: 50,  wall_thickness: 3 },
                        "SHS 60x60x4"   => { width: 60,   height: 60,  wall_thickness: 4 },
                        "SHS 80x80x5"   => { width: 80,   height: 80,  wall_thickness: 5 },
                        "SHS 90x90x5"   => { width: 90,   height: 90,  wall_thickness: 5 },
                        "SHS 100x100x5" => { width: 100,  height: 100, wall_thickness: 5 }
                    } unless defined?(SQUARE_HOLLOW_SECTION_SIZES)
                end
            end

            TEMP_GROUP_NAME = "NA_Structural_Member_Creation_Temporary_Group".freeze
            DA_DICT         = "dynamic_attributes".freeze

            def NA_METHOD_CreateSteelElement
                dialog = UI::HtmlDialog.new(
                    dialog_title:    "Noble Architecture | Structural Member Creator",
                    preferences_key: "com.noble-architecture.structural-member-creator",
                    scrollable:      true,
                    resizable:       true,
                    width:           500,
                    height:          750,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )
                
                # Get lists of available sizes for each type
                beams   = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalBeams::UNIVERSAL_BEAM_SIZES
                columns = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalColumns::UNIVERSAL_COLUMN_SIZES
                shs     = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_SquareHollowSections::SQUARE_HOLLOW_SECTION_SIZES
                
                # Convert to JavaScript arrays for the HTML
                beams_js   = beams.keys.sort.map { |k| "\"#{k}\"" }.join(",")
                columns_js = columns.keys.sort.map { |k| "\"#{k}\"" }.join(",")
                shs_js     = shs.keys.sort.map { |k| "\"#{k}\"" }.join(",")
                
                html_content = <<-HTML
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                        <meta charset="UTF-8">
                        <title>Noble Architecture | Structural Member Creator</title>
                        <style>
                        #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                        
                        .NA_StructuralMember_body {
                            font-family: 'Open Sans', sans-serif;
                            margin: 20px;
                            color: #333333;
                            background: #f8f8f8;
                        }
                        .NA_StructuralMember_body h2 {
                            font-weight: 600;
                            font-size: 18pt;
                            color: #333333;
                            margin-bottom: 10px;
                        }
                        .NA_StructuralMember_body p {
                            font-size: 10.5pt;
                            color: #444444;
                            line-height: 1.5;
                            margin-bottom: 20px;
                        }
                        .NA_StructuralMember_info {
                            background: #f0f0f0;
                            padding: 15px;
                            border-radius: 4px;
                            margin-bottom: 25px;
                            border-left: 3px solid #787369;
                        }
                        .NA_StructuralMember_option_group {
                            margin-bottom: 20px;
                        }
                        .NA_StructuralMember_option_group label {
                            display: block;
                            font-weight: 500;
                            margin-bottom: 5px;
                        }
                        .NA_StructuralMember_button {
                            background: #787369;
                            color: #ffffff;
                            border: none;
                            padding: 12px 20px;
                            border-radius: 4px;
                            font-weight: 600;
                            font-size: 11pt;
                            cursor: pointer;
                            margin-top: 10px;
                            transition: all 0.2s ease;
                        }
                        .NA_StructuralMember_button:hover {
                            background: #555041;
                        }
                        .NA_StructuralMember_explanation {
                            font-weight: 300;
                            color: #666666;
                            margin-left: 4px;
                        }
                        </style>
                    </head>
                    <body class="NA_StructuralMember_body">
                        #{NobleArchitectureUnifiedStylesheet.generate_header("Structural Member Creator", NobleArchitectureToolbox::LOGO_PATH)}
                        
                        <div class="NA_StructuralMember_info">
                            <p>Create structural steel members to precise dimensions. Members are created with BIM metadata</p>
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="member_type">Member Type:</label>
                            <select id="member_type" class="NA_input_medium" onchange="updateSizesDropdown()">
                                <option value="Beam">Beam</option>
                                <option value="Column">Column</option>
                                <option value="SHS">Square Hollow Section</option>
                            </select>
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="size_key">Profile Size:</label>
                            <select id="size_key" class="NA_input_medium">
                                <!-- Options will be populated by JavaScript -->
                            </select>
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="length_mm">Length (mm):</label>
                            <input type="number" id="length_mm" class="NA_input_medium" value="3000" min="100">
                            <div id="length_error" class="NA_error">Length must be at least 100mm.</div>
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="member_name">Member Name (optional):</label>
                            <input type="text" id="member_name" class="NA_input_medium" placeholder="e.g. B01">
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="member_code">Member Code (optional):</label>
                            <input type="text" id="member_code" class="NA_input_medium" placeholder="e.g. STL-001">
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="member_location">Member Location (optional):</label>
                            <input type="text" id="member_location" class="NA_input_medium" placeholder="e.g. First Floor">
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="member_notes">Notes (optional):</label>
                            <textarea id="member_notes" class="NA_input_medium" rows="3" placeholder="Additional information about this structural member"></textarea>
                        </div>
                        
                        <button class="NA_StructuralMember_button" onclick="createStructuralMember()">Create Structural Member</button>
                        
                        <script>
                            // Define available sizes
                            const beamSizes = [#{beams_js}];
                            const columnSizes = [#{columns_js}];
                            const shsSizes = [#{shs_js}];
                            
                            // Populate size dropdown based on selected member type
                            function updateSizesDropdown() {
                                const memberType = document.getElementById('member_type').value;
                                const sizeDropdown = document.getElementById('size_key');
                                
                                // Clear existing options
                                sizeDropdown.innerHTML = '';
                                
                                // Get appropriate sizes based on member type
                                let sizes = [];
                                
                                if (memberType === 'Beam') {
                                    sizes = beamSizes;
                                } else if (memberType === 'Column') {
                                    sizes = columnSizes;
                                } else if (memberType === 'SHS') {
                                    sizes = shsSizes;
                                }
                                
                                // Add options to dropdown
                                sizes.forEach(size => {
                                    const option = document.createElement('option');
                                    option.value = size;
                                    option.textContent = size;
                                    sizeDropdown.appendChild(option);
                                });
                            }
                            
                            // Initialize dropdown on page load
                            window.onload = function() {
                                updateSizesDropdown();
                                document.getElementById('length_error').style.display = 'none';
                            };
                            
                            // Create structural member
                            function createStructuralMember() {
                                // Get form values
                                const memberType = document.getElementById('member_type').value;
                                const sizeKey = document.getElementById('size_key').value;
                                const lengthMm = parseFloat(document.getElementById('length_mm').value);
                                const memberName = document.getElementById('member_name').value;
                                const memberCode = document.getElementById('member_code').value;
                                const memberLocation = document.getElementById('member_location').value;
                                const memberNotes = document.getElementById('member_notes').value;
                                
                                // Validate length
                                if (isNaN(lengthMm) || lengthMm < 100) {
                                    document.getElementById('length_error').style.display = 'block';
                                    return;
                                }
                                document.getElementById('length_error').style.display = 'none';
                                
                                // Call Ruby function to create structural member
                                sketchup.createStructuralMember(
                                    memberType,
                                    sizeKey,
                                    lengthMm,
                                    memberName,
                                    memberCode,
                                    memberLocation,
                                    memberNotes
                                );
                            }
                        </script>
                    </body>
                    </html>
                HTML
                
                dialog.set_html(html_content)
                
                dialog.add_action_callback("createStructuralMember") do |action_context, member_type, size_key, length_mm, member_name, member_code, member_location, member_notes|
                    create_structural_member(member_type, size_key, length_mm.to_f, member_name, member_code, member_location, member_notes)
                end
                
                dialog.show
            end
            
            def create_structural_member(member_type, size_key, length_mm, member_name, member_code, member_location, member_notes)
                model = Sketchup.active_model
                info = NA_METHOD_FindProfileInfo(size_key)
                
                return UI.messagebox("Error: Invalid size selected.") unless info

                length_in_inches = length_mm.mm

                model.start_operation("Create Steel #{member_type}", true)
                begin
                    group = create_named_group_for_geometry(model)
                    face  = NA_METHOD_DrawISectionProfile(group.entities, info)
                    unless face && face.valid?
                        UI.messagebox("Error: Failed to create geometry.")
                        model.abort_operation
                        return
                    end
                    face.reverse! if face.normal.z < 0
                    face.pushpull(length_in_inches)

                    NA_METHOD_ApplySteelMaterial(group)
                    instance = convert_temp_group_to_component(model, size_key, member_type, length_mm)
                    unless instance
                        UI.messagebox("Error: Could not convert group to DC.")
                        model.abort_operation
                        return
                    end
                    
                    # Set custom name and location if provided
                    if !member_name.nil? && !member_name.empty?
                        instance.set_attribute(DA_DICT, "a3_member_name", member_name)
                    end
                    
                    if !member_code.nil? && !member_code.empty?
                        instance.set_attribute(DA_DICT, "a4_member_code", member_code)
                    end
                    
                    if !member_location.nil? && !member_location.empty?
                        instance.set_attribute(DA_DICT, "a5_member_location", member_location)
                    end
                    
                    if !member_notes.nil? && !member_notes.empty?
                        instance.set_attribute(DA_DICT, "a6_member_notes", member_notes)
                    end

                    if member_type == "Beam"
                        rot = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 0, 0), -90.degrees)
                        instance.transform!(rot)
                    end
                    model.commit_operation

                    NA_METHOD_MoveMemberToPickedPoint(instance, member_type)
                rescue => e
                    model.abort_operation
                    UI.messagebox("Error creating Steel #{member_type}:\n#{e.message}")
                    log_error(e)
                end
            end

            def NA_METHOD_FindProfileInfo(size_key)
                beams   = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalBeams::UNIVERSAL_BEAM_SIZES
                columns = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalColumns::UNIVERSAL_COLUMN_SIZES
                shs     = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_SquareHollowSections::SQUARE_HOLLOW_SECTION_SIZES

                return beams[size_key]   if beams.key?(size_key)
                return columns[size_key] if columns.key?(size_key)
                return shs[size_key]     if shs.key?(size_key)
                nil
            end

            def NA_METHOD_ComputeMemberMassPerM(size_key, _info_unused)
                matched = size_key.match(/(\d+)$/)
                return 0.0 unless matched
                kg_per_m = matched[1].to_f
                kg_per_m
            end

            def total_member_mass_kg(size_key, length_mm)
                kg_per_m = NA_METHOD_ComputeMemberMassPerM(size_key, nil)
                length_m = length_mm / 1000.0
                (kg_per_m * length_m).round(2)
            end

            def create_named_group_for_geometry(model)
                group = model.active_entities.add_group
                group.name = TEMP_GROUP_NAME
                group
            end

            def NA_METHOD_DrawISectionProfile(ents, info)
                w  = info[:width].mm
                h  = info[:height].mm
                ft = info[:flange_thickness].mm
                wt = info[:web_thickness].mm

                pts = [
                    [0, 0, 0],
                    [w, 0, 0],
                    [w, ft, 0],
                    [(w + wt)/2, ft, 0],
                    [(w + wt)/2, h - ft, 0],
                    [w, h - ft, 0],
                    [w, h, 0],
                    [0, h, 0],
                    [0, h - ft, 0],
                    [(w - wt)/2, h - ft, 0],
                    [(w - wt)/2, ft, 0],
                    [0, ft, 0]
                ]

                face = ents.add_face(pts)
                face.reverse! if face.valid? && face.normal.z < 0
                face
            end

            def NA_METHOD_ApplySteelMaterial(entity)
                mat_name = "E10_S01_V01_--_Structural_Steelwork"
                mats = Sketchup.active_model.materials
                mat  = mats[mat_name] || mats.add(mat_name)
                mat.color = Sketchup::Color.new(185, 95, 95)
                entity.material = mat
            end

            def convert_temp_group_to_component(model, size_key, member_type, length_mm)
                all_temp_groups = model.active_entities.grep(Sketchup::Group).select { |g| g.name == TEMP_GROUP_NAME }
                return nil if all_temp_groups.empty?

                group    = all_temp_groups.last
                instance = group.to_component
                return nil unless instance.is_a?(Sketchup::ComponentInstance)

                definition     = instance.definition
                base_def_name  = "NA_#{member_type}_#{size_key}"
                definition.name = safe_unique_def_name(model, base_def_name)
                instance.name   = next_instance_name(model, "#{member_type}_Instance")

                info              = NA_METHOD_FindProfileInfo(size_key) || {}
                width             = info[:width]  || 0
                ht                = info[:height] || 0
                member_total_mass = total_member_mass_kg(size_key, length_mm)

                da = DA_DICT
                instance.set_attribute(da, "_formatversion",     "1.0")
                instance.set_attribute(da, "IsDynamic",          "TRUE")
                instance.set_attribute(da, "_hasbehaviors",      "1.0")
                instance.set_attribute(da, "_lengthunits",       "INCHES")
                instance.set_attribute(da, "_name",              definition.name)

                code_prefix = case member_type
                              when "Beam"   then "BM0#"
                              when "Column" then "CM0#"
                              when "SHS"    then "SH0#"
                              else "XX01"
                              end

                instance.set_attribute(da, "a1_element_code", code_prefix)
                instance.set_attribute(da, "_a1_element_code_label",  "#{member_type} Code")
                instance.set_attribute(da, "_a1_element_code_access", "TEXTBOX")
                instance.set_attribute(da, "_a1_element_code_units",  "STRING")

                instance.set_attribute(da, "a2_section_name", size_key)
                instance.set_attribute(da, "_a2_section_name_label",  "Profile Type")
                instance.set_attribute(da, "_a2_section_name_access", "VIEW")
                instance.set_attribute(da, "_a2_section_name_units",  "STRING")

                instance.set_attribute(da, "a3_member_name", "Unspecified")
                instance.set_attribute(da, "_a3_member_name_label",   "Member Name")
                instance.set_attribute(da, "_a3_member_name_access",  "TEXTBOX")
                instance.set_attribute(da, "_a3_member_name_units",   "STRING")

                instance.set_attribute(da, "a4_member_code", "Unspecified")
                instance.set_attribute(da, "_a4_member_code_label",   "Member Code")
                instance.set_attribute(da, "_a4_member_code_access",  "TEXTBOX")
                instance.set_attribute(da, "_a4_member_code_units",   "STRING")

                instance.set_attribute(da, "a5_member_location", "Unspecified")
                instance.set_attribute(da, "_a5_member_location_label",   "Member Location")
                instance.set_attribute(da, "_a5_member_location_access",  "TEXTBOX")
                instance.set_attribute(da, "_a5_member_location_units",   "STRING")

                instance.set_attribute(da, "a6_member_notes", "Unspecified")
                instance.set_attribute(da, "_a6_member_notes_label",   "Notes")
                instance.set_attribute(da, "_a6_member_notes_access",  "TEXTAREA")
                instance.set_attribute(da, "_a6_member_notes_units",   "STRING")

                instance.set_attribute(da, "a7_element_type", member_type)
                instance.set_attribute(da, "_a7_element_type_label",  "Element Type")
                instance.set_attribute(da, "_a7_element_type_access", "VIEW")
                instance.set_attribute(da, "_a7_element_type_units",  "STRING")

                instance.set_attribute(da, "a8_element_size", size_key)
                instance.set_attribute(da, "_a8_element_size_label",  "#{member_type} Size")
                instance.set_attribute(da, "_a8_element_size_access", "VIEW")
                instance.set_attribute(da, "_a8_element_size_units",  "STRING")

                instance.set_attribute(da, "h1_calc_mm_to_inches", "")
                instance.set_attribute(da, "_h1_calc_mm_to_inches_label",        "MM_to_Inches_Helper")
                instance.set_attribute(da, "_h1_calc_mm_to_inches_units",        "STRING")
                instance.set_attribute(da, "_h1_calc_mm_to_inches_formulaunits", "FLOAT")
                instance.set_attribute(da, "_h1_calc_mm_to_inches_formula",      "*25.4")
                instance.set_attribute(da, "_h1_calc_mm_to_inches_access",       "NONE")

                instance.set_attribute(da, "d1_length_mm", length_mm.to_s)
                instance.set_attribute(da, "_d1_length_mm_label",   "Member Length (mm)")
                instance.set_attribute(da, "_d1_length_mm_units",   "STRING")
                instance.set_attribute(da, "_d1_length_mm_access",  "TEXTBOX")

                instance.set_attribute(da, "d2_length_in", "")
                instance.set_attribute(da, "_d2_length_in_label",    "Length (Inches)")
                instance.set_attribute(da, "_d2_length_in_formula",  "(d1_length_mm)/h1_calc_mm_to_inches")
                instance.set_attribute(da, "_d2_length_in_units",    "FLOAT")
                instance.set_attribute(da, "_d2_length_in_access",   "NONE")

                instance.set_attribute(da, "LenZ", "LenZ")
                instance.set_attribute(da, "_lenz_label",   "Overall Z Dimension")
                instance.set_attribute(da, "_lenz_formula", "d2_length_in")
                instance.set_attribute(da, "_lenz_access",  "NONE")

                instance.set_attribute(da, "profile_width_mm",  width.to_s)
                instance.set_attribute(da, "_profile_width_mm_label",  "Profile Width (mm)")
                instance.set_attribute(da, "_profile_width_mm_access", "VIEW")
                instance.set_attribute(da, "_profile_width_mm_units",  "STRING")

                instance.set_attribute(da, "profile_height_mm", ht.to_s)
                instance.set_attribute(da, "_profile_height_mm_label",  "Profile Height (mm)")
                instance.set_attribute(da, "_profile_height_mm_access", "VIEW")
                instance.set_attribute(da, "_profile_height_mm_units",  "STRING")

                instance.set_attribute(da, "w1_member_total_mass_kg", member_total_mass.to_s)
                instance.set_attribute(da, "_w1_member_total_mass_kg_label",  "Total Mass (kg)")
                instance.set_attribute(da, "_w1_member_total_mass_kg_access", "VIEW")
                instance.set_attribute(da, "_w1_member_total_mass_kg_units",  "FLOAT")

                if $dc_observers && $dc_observers.respond_to?(:get_latest_class)
                    $dc_observers.get_latest_class.redraw_with_undo(instance)
                end

                instance
            end

            def safe_unique_def_name(model, base_name)
                name    = base_name.dup
                counter = 1
                while model.definitions[name]
                    name = "#{base_name} (#{counter})"
                    counter += 1
                end
                name
            end

            def next_instance_name(model, base_name)
                existing = model.active_entities.grep(Sketchup::ComponentInstance).map(&:name)
                return base_name unless existing.include?(base_name)
                counter = 1
                while existing.include?("#{base_name} (#{counter})")
                    counter += 1
                end
                "#{base_name} (#{counter})"
            end

            def NA_METHOD_MoveMemberToPickedPoint(instance, member_type)
                # Build a detailed summary of the created member
                member_name = instance.get_attribute(DA_DICT, "a3_member_name") || "Unspecified"
                member_code = instance.get_attribute(DA_DICT, "a4_member_code") || "Unspecified"
                size_key = instance.get_attribute(DA_DICT, "a8_element_size") || "Unknown"
                length_mm = instance.get_attribute(DA_DICT, "d1_length_mm") || "0"
                mass_kg = instance.get_attribute(DA_DICT, "w1_member_total_mass_kg") || "0"
                
                # Create summarized details
                details = "Steel #{member_type} created successfully with the following properties:\n\n"
                details += "• Type: #{member_type}\n"
                details += "• Size: #{size_key}\n"
                details += "• Length: #{length_mm}mm\n"
                details += "• Mass: #{mass_kg}kg\n"
                details += "• Name: #{member_name}\n" if member_name != "Unspecified"
                details += "• Code: #{member_code}\n" if member_code != "Unspecified"
                details += "\nClick a point to place it."
                
                UI.messagebox(details)
                
                # Create callback for when point is picked
                callback = lambda do |picked_pt|
                    final_pt = round_point_to_nearest_5mm(picked_pt)
                    tr = Geom::Transformation.new(final_pt - instance.bounds.min)
                    instance.transform!(tr)
                    
                    # Show confirmation with placement coordinates
                    x_mm = (final_pt.x * 25.4).round
                    y_mm = (final_pt.y * 25.4).round
                    z_mm = (final_pt.z * 25.4).round
                    
                    placement_info = "Structural #{member_type} placed successfully at:\n"
                    placement_info += "X: #{x_mm}mm, Y: #{y_mm}mm, Z: #{z_mm}mm"
                    
                    UI.messagebox(placement_info)
                end
                
                # Create status formatter to show coordinates
                status_formatter = lambda do |point|
                    # Round to nearest 5mm and show in mm
                    x_mm = (point.x * 25.4 / 5.0).round * 5
                    y_mm = (point.y * 25.4 / 5.0).round * 5
                    z_mm = (point.z * 25.4 / 5.0).round * 5
                    
                    "Click to place #{member_type} at X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
                end
                
                # Use the shared point picker tool with customized options including title prefix
                Sketchup.active_model.select_tool(
                    SharedTools::PointPickerTool.new(
                        callback,
                        {
                            status_text: "Click to place the #{member_type}",
                            status_formatter: status_formatter,
                            marker_size: 4.0,
                            color: "#FFC800", # Noble Architecture yellow
                            title_prefix: "Creating #{member_type} -",
                            document_action: :save # Automatically save after placement
                        }
                    )
                )
            end
            
            def round_point_to_nearest_5mm(pt)
                mm_inch = 25.4
                step    = 5.0
                x_mm = pt.x * mm_inch
                y_mm = pt.y * mm_inch
                z_mm = pt.z * mm_inch

                rx = (x_mm / step).round * step
                ry = (y_mm / step).round * step
                rz = (z_mm / step).round * step

                Geom::Point3d.new(rx / mm_inch, ry / mm_inch, rz / mm_inch)
            end

            def log_error(e)
                puts "[#{Time.now}] #{e.class}: #{e.message}"
                puts e.backtrace.join("\n")
                puts "-" * 50
            end
            
            # Note: The original PointPickerTool class has been replaced with the more versatile
            # SharedTools::PointPickerTool to provide consistent point-picking behavior
            # across all tools in the Noble Architecture Toolbox.
        end
        # endregion


        # region [col03g] DuplicateSelectedEntityTool
        module DuplicateSelectedEntityTool
            extend self

            def run
                model     = Sketchup.active_model
                selection = model.selection
                to_dup    = selection.grep(Sketchup::Group) + selection.grep(Sketchup::ComponentInstance)
                return UI.messagebox("No Groups or Components selected!") if to_dup.empty?

                model.start_operation("Duplicate Selected Entities", true)
                to_dup.each do |entity|
                    new_entity = duplicate_entity(entity)
                    new_entity.name = find_next_duplicate_name(entity.name, model)
                end
                model.commit_operation
                UI.messagebox("Duplication complete!")
            end

            def duplicate_entity(entity)
                definition = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition : entity.to_component.definition
                tr         = entity.transformation
                ents       = Sketchup.active_model.active_entities
                ents.add_instance(definition, tr)
            end

            def find_next_duplicate_name(base_name, model)
                base_name = "Untitled" if base_name.nil? || base_name.strip.empty?
                counter   = 1
                new_name  = "#{base_name}_-_Duplicate_#{format('%02d', counter)}"
                all_names = model.active_entities.map(&:name)
                while all_names.include?(new_name)
                    counter += 1
                    new_name = "#{base_name}_-_Duplicate_#{format('%02d', counter)}"
                end
                new_name
            end
        end
        # endregion


        # region [col03h] IsolateSelectedEntityTool
        module IsolateSelectedEntityTool
            extend self
            
            # Dictionary name for tracking isolation state
            NA_ISOLATION_DICT = "NA_Object_Isolation_Status_Dictionary"
            
            # Track if in isolated state - improves UI responsiveness
            @is_isolated = false
            
            # Check if the model is currently in isolated state
            def is_isolated?
                model = Sketchup.active_model
                dict = model.attribute_dictionary(NA_ISOLATION_DICT)
                return false unless dict
                return dict["is_isolated"] == true
            end
            
            # Get the current state for UI button text
            def current_state_text
                is_isolated? ? "Revert Isolation" : "Isolate Selected"
            end
            
            # Toggle between isolation and reversion
            def toggle_isolation
                if is_isolated?
                    run_revert
                else
                    run_isolate
                end
            end

            def run_isolate
                model = Sketchup.active_model
                selection = model.selection
                selected = selection.grep(Sketchup::Group) + selection.grep(Sketchup::ComponentInstance)
                return UI.messagebox("No Groups or Components selected!") if selected.empty?
                # No need to explicitly create dictionary - set_attribute will do it automatically
                
                # Store selected entities' IDs for future reference
                selected_ids = selected.map(&:entityID)
                model.set_attribute(NA_ISOLATION_DICT, "selected_ids", selected_ids)
                
                # Create a serializable tracking of hidden state
                hidden_state = {}
                
                model.start_operation("Isolate Selected Entities", true)
                
                model.entities.each do |e|
                    next if selected.include?(e)
                    
                    # Remember current hidden state before changing it
                    hidden_state[e.entityID.to_s] = e.hidden?
                    
                    # Hide if not already hidden
                    e.hidden = true unless e.hidden?
                end
                
                # Store hidden state information in dictionary
                model.set_attribute(NA_ISOLATION_DICT, "hidden_state", hidden_state)
                model.set_attribute(NA_ISOLATION_DICT, "is_isolated", true)
                
                model.commit_operation
                
                # Update the instance variable for responsive UI
                @is_isolated = true
            end

            def run_revert
                model = Sketchup.active_model
                dict = model.attribute_dictionary(NA_ISOLATION_DICT)
                return UI.messagebox("Nothing to revert!") unless dict && dict["is_isolated"]
                
                # Start the operation
                model.start_operation("Revert Isolation", true)
                
                # Simplest approach: directly unhide all entities that were selected
                selected_ids = dict["selected_ids"] || []
                
                # Build a list of all entities that were selected during isolation
                selected_entities = []
                if selected_ids.any?
                    # First look in root entities
                    model.entities.each do |entity|
                        selected_entities << entity if selected_ids.include?(entity.entityID)
                    end
                end
                
                # Now unhide EVERYTHING except the selected entities
                process_entities = lambda do |entities|
                    entities.each do |entity|
                        # Only unhide if this entity wasn't one of the originally selected ones
                        unless selected_entities.include?(entity)
                            entity.hidden = false
                        end
                        
                        # Process nested entities
                        if entity.is_a?(Sketchup::Group)
                            process_entities.call(entity.entities)
                        elsif entity.is_a?(Sketchup::ComponentInstance)
                            process_entities.call(entity.definition.entities)
                        end
                    end
                end
                
                # Process all entities starting from root
                process_entities.call(model.entities)
                
                # Clear isolation state
                model.set_attribute(NA_ISOLATION_DICT, "is_isolated", false)
                model.set_attribute(NA_ISOLATION_DICT, "hidden_state", {})
                model.set_attribute(NA_ISOLATION_DICT, "selected_ids", [])
                
                model.commit_operation
                
                # Update the instance variable for responsive UI
                @is_isolated = false
            end
            
            # Helper to find an entity by ID in the model
            def find_entity_by_id(model, entity_id)
                # Try root entities first
                entity = model.entities.find { |e| e.entityID == entity_id }
                return entity if entity
                
                # If not found, do a deeper search through groups and components
                model.entities.each do |e|
                    if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
                        entity = find_entity_in_container(e, entity_id)
                        return entity if entity
                    end
                end
                
                nil
            end
            
            # Recursively search for entity by ID in groups/components
            def find_entity_in_container(container, entity_id)
                entities = container.is_a?(Sketchup::Group) ? 
                           container.entities : 
                           container.definition.entities
                
                entities.each do |e|
                    return e if e.entityID == entity_id
                    
                    if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
                        found = find_entity_in_container(e, entity_id)
                        return found if found
                    end
                end
                
                nil
            end
        end
        # endregion


        # region [col03i] DeepPaintFacesTool
        module DeepPaintFacesTool
            extend self

            def run
                Sketchup.active_model.select_tool(DeepPaintTool.new)
            end

            class DeepPaintTool
                def initialize
                    @hover_face = nil
                end

                def activate
                    @hover_face = nil
                end

                def onLButtonDown(_flags, x, y, view)
                    ph = view.pick_helper
                    ph.do_pick(x, y)
                    picked_face = nil
                    best_path   = nil

                    ph.count.times do |i|
                        path = ph.path_at(i)
                        next unless path && path.last.is_a?(Sketchup::Face)
                        if best_path.nil? || path.length > best_path.length
                            picked_face = path.last
                            best_path   = path
                        end
                    end

                    unless picked_face
                        UI.messagebox("No face found under the cursor.")
                        return
                    end

                    model = Sketchup.active_model
                    model.start_operation("NA Deep Paint Face", true)

                    if best_path
                        best_path[0...-1].each do |container|
                            if container.respond_to?(:material)
                                container.material = nil
                            end
                            if container.respond_to?(:back_material)
                                container.back_material = nil
                            end
                        end
                    end

                    picked_face.back_material = nil

                    current_material = model.materials.current
                    unless current_material
                        UI.messagebox("No current material selected.")
                        model.abort_operation
                        return
                    end

                    picked_face.material = current_material
                    model.commit_operation
                    view.invalidate
                end

                def onMouseMove(_flags, x, y, view)
                    ph = view.pick_helper
                    ph.do_pick(x, y)
                    best_face = nil
                    best_path = nil

                    ph.count.times do |i|
                        path = ph.path_at(i)
                        next unless path && path.last.is_a?(Sketchup::Face)
                        if best_path.nil? || path.length > best_path.length
                            best_face = path.last
                            best_path = path
                        end
                    end

                    @hover_face = best_face
                    view.invalidate
                end

                def draw(view)
                    return unless @hover_face && @hover_face.valid?
                    outer_loop = @hover_face.outer_loop
                    return unless outer_loop && !outer_loop.vertices.empty?
                    pts = outer_loop.vertices.map { |v| v.position }
                    view.drawing_color = "blue"
                    view.line_width    = 3
                    view.draw(GL_LINE_LOOP, pts)
                end

                def deactivate(view)
                    @hover_face = nil
                    view.invalidate
                end

                def getMenuText
                    "NA Deep Paint Tool"
                end
            end
        end
        # endregion


        # region [col04] MasterTools
        module MasterTools

            # CL01 | UntagSelectionTool
            class UntagSelectionTool
                def initialize
                    @model     = Sketchup.active_model
                    @selection = @model.selection
                end

                def untag_entities(entities)
                    entities.each do |entity|
                        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                            untag_entities(entity.definition.entities)
                        end
                        entity.layer = nil
                    end
                end

                def execute
                    if @selection.empty?
                        UI.messagebox("Please select one or more entities to untag.")
                        return
                    end

                    result = UI.messagebox("Confirm: All selected items will be untagged.", MB_OKCANCEL)
                    if result == IDOK
                        @model.start_operation("NA | Un-Tag Selection", true)
                        untag_entities(@selection)
                        @model.commit_operation
                    else
                        UI.messagebox("Operation cancelled.")
                    end
                end
            end

            # CL02 | CoordinateSnapperTool
            class CoordinateSnapperTool
                TOLERANCE_OPTIONS = ["5mm", "10mm", "25mm", "50mm", "100mm", "200mm", "250mm", "500mm", "1000mm", "2500mm", "5000mm", "10000mm"].freeze

                def initialize
                    @model     = Sketchup.active_model
                    @selection = @model.selection
                end

                def run
                    dialog = UI::HtmlDialog.new(
                        dialog_title:    "Noble Architecture | Coordinate Snapper",
                        preferences_key: "com.noble-architecture.coordinate-snapper",
                        scrollable:      true,
                        resizable:       true,
                        width:           450,
                        height:          700,
                        style:           UI::HtmlDialog::STYLE_DIALOG
                    )

                    html_content = <<-HTML
                        <!DOCTYPE html>
                        <html lang="en">
                        <head>
                            <meta charset="UTF-8">
                            <title>Noble Architecture | Coordinate Snapper</title>
                            <style>
                            #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                            
                            .NA_CoordinateSnapper_body {
                                font-family: 'Open Sans', sans-serif;
                                margin: 20px;
                                color: #333333;
                                background: #f8f8f8;
                            }
                            .NA_CoordinateSnapper_body h2 {
                                font-weight: 600;
                                font-size: 18pt;
                                color: #333333;
                                margin-bottom: 10px;
                            }
                            .NA_CoordinateSnapper_body p {
                                font-size: 10.5pt;
                                color: #444444;
                                line-height: 1.5;
                                margin-bottom: 20px;
                            }
                            .NA_CoordinateSnapper_info {
                                background: #f0f0f0;
                                padding: 15px;
                                border-radius: 4px;
                                margin-bottom: 25px;
                                border-left: 3px solid #787369;
                            }
                            .NA_CoordinateSnapper_option_group {
                                margin-bottom: 20px;
                            }
                            .NA_CoordinateSnapper_option_group label {
                                display: block;
                                font-weight: 500;
                                margin-bottom: 5px;
                            }
                            .NA_CoordinateSnapper_button {
                                background: #787369;
                                color: #ffffff;
                                border: none;
                                padding: 12px 20px;
                                border-radius: 4px;
                                font-weight: 600;
                                font-size: 11pt;
                                cursor: pointer;
                                margin-top: 10px;
                                transition: all 0.2s ease;
                            }
                            .NA_CoordinateSnapper_button:hover {
                                background: #555041;
                            }
                            .NA_CoordinateSnapper_explanation {
                                font-weight: 300;
                                color: #666666;
                                margin-left: 4px;
                            }
                            </style>
                        </head>
                        <body class="NA_CoordinateSnapper_body">
                            #{NobleArchitectureUnifiedStylesheet.generate_header("Coordinate Snapper", NobleArchitectureToolbox::LOGO_PATH)}
                            
                            <div class="NA_CoordinateSnapper_info">
                                <p>This tool helps you snap your selected geometry to precise coordinate positions. First select the entities you want to snap, then configure your options below and click "Start Snapping".</p>
                            </div>
                            
                            <div class="NA_CoordinateSnapper_option_group">
                                <label>Coordinate Type:</label>
                                <div class="NA_checkbox">
                                    <label>
                                        <input type="radio" name="coordinate_type" value="XYZ" checked>
                                        XYZ Coordinate <span class="NA_CoordinateSnapper_explanation">(Snap all axes)</span>
                                    </label>
                                </div>
                                <div class="NA_checkbox">
                                    <label>
                                        <input type="radio" name="coordinate_type" value="XY">
                                        XY Coordinate <span class="NA_CoordinateSnapper_explanation">(Snap X and Y, keep Z)</span>
                                    </label>
                                </div>
                                <div class="NA_checkbox">
                                    <label>
                                        <input type="radio" name="coordinate_type" value="Z">
                                        Z Coordinate <span class="NA_CoordinateSnapper_explanation">(Snap Z, keep X and Y)</span>
                                    </label>
                                </div>
                            </div>
                            
                            <div class="NA_CoordinateSnapper_option_group">
                                <label>Snap Tolerance:</label>
                                <select id="tolerance" class="NA_input_medium">
                                    <option value="5mm">5mm</option>
                                    <option value="10mm">10mm</option>
                                    <option value="25mm">25mm</option>
                                    <option value="50mm">50mm</option>
                                    <option value="100mm">100mm</option>
                                    <option value="200mm">200mm</option>
                                    <option value="250mm">250mm</option>
                                    <option value="500mm">500mm</option>
                                    <option value="1000mm">1000mm</option>
                                    <option value="2500mm">2500mm</option>
                                    <option value="5000mm">5000mm</option>
                                    <option value="10000mm">10000mm</option>
                                </select>
                            </div>
                            
                            <button class="NA_CoordinateSnapper_button" onclick="startSnapping()">Start Snapping</button>
                            
                            <script>
                                function getSelectedCoordinateType() {
                                    const radios = document.getElementsByName('coordinate_type');
                                    for (let i = 0; i < radios.length; i++) {
                                        if (radios[i].checked) {
                                            return radios[i].value;
                                        }
                                    }
                                    return 'XYZ'; // Default
                                }
                                
                                function startSnapping() {
                                    const coordinateType = getSelectedCoordinateType();
                                    const tolerance = document.getElementById('tolerance').value;
                                    sketchup.startSnapping(coordinateType, tolerance);
                                }
                            </script>
                        </body>
                        </html>
                    HTML

                    dialog.set_html(html_content)
                    
                    dialog.add_action_callback("startSnapping") do |action_context, coordinate_type, tolerance|
                        # Start the process with these preferences
                        start_snapping(coordinate_type, tolerance)
                    end
                    
                    dialog.show
                end

                # Launch a point picker and handle coordinate snapping
                def start_snapping(coordinate_type, tolerance)
                    # Convert tolerance string to length
                    tolerance_value = tolerance.to_l
                    preferences = { coordinate_type: coordinate_type, tolerance: tolerance_value }
                    
                    # Start the operation - will be committed when point is picked
                    @model.start_operation("NA | Coordinate Snap", true)
                    
                    # Create callback for when a point is picked
                    callback = lambda do |picked_point|
                        # Process the picked point
                        global_point = picked_point.transform(@model.edit_transform)
                        
                        snap_selection(global_point, preferences)
                        @model.commit_operation
                        
                        # Show success message
                        UI.messagebox("Selection successfully snapped to coordinates.")
                    end
                    
                    # Create a dynamic status formatter
                    status_formatter = lambda do |point|
                        # Convert point to mm for display
                        x_mm = (point.x * 25.4).round(1)
                        y_mm = (point.y * 25.4).round(1)
                        z_mm = (point.z * 25.4).round(1)
                        
                        "Click to snap (X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm)"
                    end
                    
                    # Create tooltip content generator for rich 3D tooltip
                    tooltip_content = lambda do |point|
                        # Basic info about point
                        x_mm = point.x.to_mm.round(1)
                        y_mm = point.y.to_mm.round(1)
                        z_mm = point.z.to_mm.round(1)
                        
                        # Highlight the important coordinates based on coordinate type
                        case coordinate_type
                        when "XY"
                            "Snap Point\n→ X: #{x_mm} mm ←\n→ Y: #{y_mm} mm ←\nZ: #{z_mm} mm"
                        when "Z"
                            "Snap Point\nX: #{x_mm} mm\nY: #{y_mm} mm\n→ Z: #{z_mm} mm ←"
                        when "XYZ"
                            "Snap Point\n→ X: #{x_mm} mm ←\n→ Y: #{y_mm} mm ←\n→ Z: #{z_mm} mm ←"
                        end
                    end
                    
                    # Use the shared point picker tool
                    Sketchup.active_model.select_tool(
                        SharedTools::PointPickerTool.new(
                            callback,
                            {
                                status_text: "Click to snap selection to a point",
                                status_formatter: status_formatter,
                                marker_size: 4.0,
                                color: "#FFC800", # Noble Architecture yellow
                                title_prefix: "Coordinate Snapping -",
                                tooltip: {
                                    content: tooltip_content,
                                    position: :right,
                                    color: "#FFFFFF", # White text
                                    background: "#555041", # Dark gold background
                                    opacity: 200,
                                    font_size: 0.35,
                                    padding: 0.2,
                                    offset: 1.5
                                }
                            }
                        )
                    )
                end

                def snap_selection(global_point, preferences)
                    target_point       = calculate_target_point(global_point, preferences)
                    translation_vector = global_point.vector_to(target_point)
                    @selection.each do |entity|
                        entity.transform!(Geom::Transformation.translation(translation_vector))
                    end
                end

                def calculate_target_point(point, preferences)
                    case preferences[:coordinate_type]
                    when "XY"
                        x = round_to_nearest(point.x, preferences[:tolerance])
                        y = round_to_nearest(point.y, preferences[:tolerance])
                        Geom::Point3d.new(x, y, point.z)
                    when "Z"
                        z = round_to_nearest(point.z, preferences[:tolerance])
                        Geom::Point3d.new(point.x, point.y, z)
                    when "XYZ"
                        x = round_to_nearest(point.x, preferences[:tolerance])
                        y = round_to_nearest(point.y, preferences[:tolerance])
                        z = round_to_nearest(point.z, preferences[:tolerance])
                        Geom::Point3d.new(x, y, z)
                    end
                end

                def round_to_nearest(value, tolerance)
                    (value / tolerance).round * tolerance
                end
            end
        end
        # endregion


        # region [col03] MakeFacesTool
        module MakeFacesTool
            extend self
            require 'set'

            def run
                model = Sketchup.active_model
                selection = model.selection
                selected_edges = selection.grep(Sketchup::Edge)

                if selected_edges.empty?
                  UI.messagebox("No edges selected. Please select some edges and try again.")
                  return
                end

                model.start_operation("Make Faces from Edges", true)
                adj_list, edge_map = build_edge_map(selected_edges)

                visited_edges = Set.new
                faces_created = 0

                get_edge = lambda do |va, vb|
                  va_id, vb_id = va.entityID, vb.entityID
                  key = (va_id < vb_id) ? [va_id, vb_id] : [vb_id, va_id]
                  edge_map[key]
                end

                selected_edges.each do |edge|
                  next if visited_edges.include?(edge)
                  loop_vertices = follow_loop(edge, adj_list, get_edge, visited_edges)
                  unless loop_vertices.nil? || loop_vertices.size < 3
                    face = model.active_entities.add_face(loop_vertices)
                    faces_created += 1 if face
                  end
                end

                model.commit_operation
                UI.messagebox("Created #{faces_created} faces from selected edges.")
            end

            def build_edge_map(selected_edges)
                adj_list = Hash.new { |hash, key| hash[key] = [] }
                edge_map = {}

                selected_edges.each do |edge|
                  v1, v2 = edge.vertices
                  v1_id, v2_id = v1.entityID, v2.entityID

                  key = (v1_id < v2_id) ? [v1_id, v2_id] : [v2_id, v1_id]
                  edge_map[key] = edge

                  adj_list[v1] << v2
                  adj_list[v2] << v1
                end
                [adj_list, edge_map]
            end

            def follow_loop(start_edge, adj_list, get_edge, visited_edges)
                start_v1, start_v2 = start_edge.vertices
                path = [start_v1, start_v2]
                visited_edges.add(start_edge)

                current_vertex = start_v2
                prev_vertex = start_v1

                loop do
                  possible_next = adj_list[current_vertex].find do |nbr|
                    nbr != prev_vertex && !visited_edges.include?(get_edge.call(current_vertex, nbr))
                  end

                  return nil if possible_next.nil?

                  path << possible_next
                  edge_used = get_edge.call(current_vertex, possible_next)
                  visited_edges.add(edge_used)

                  prev_vertex = current_vertex
                  current_vertex = possible_next

                  if current_vertex == start_v1
                    break
                  end
                end

                path
            end
        end
        # endregion


        # region [col03k] NotebookPlugin
        module NotebookPlugin
            extend self

            class NotebookModelObserver < Sketchup::ModelObserver
                def onSaveModel(_model)
                    NotebookPlugin.save_current_notes
                end
            end

            def create_dialog
                @dialog = UI::HtmlDialog.new(
                    dialog_title:    "Noble Architecture | Notebook",
                    preferences_key: "com.noble-architecture.notebook",
                    scrollable:      true,
                    resizable:       true,
                    width:           500,
                    height:          600,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )

                html_content = <<-HTML
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                        <meta charset="UTF-8">
                        <title>Noble Architecture | Notebook</title>
                        <style>
                        #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                        </style>
                    </head>
                    <body class="NA_Notebook_body">
                        #{NobleArchitectureUnifiedStylesheet.generate_header("Notebook", NobleArchitectureToolbox::LOGO_PATH)}
                        <p>Notes are automatically saved with this model:</p>
                        <textarea id="NA_Notebook_notepad" placeholder="Enter your notes here..."></textarea>
                        <div id="NA_Notebook_status">Last saved: -</div>
                        <div class="NA_Notebook_autosave_status">Autosave enabled (every 5 minutes)</div>
                        <div class="NA_Notebook_button_container">
                            <button onclick="clearNotes()">Clear Notes</button>
                            <button onclick="saveNotes()">Save Notes</button>
                        </div>

                        <script>
                        let saveTimer = null;
                        let autoSaveTimer = null;
                        let lastSavedContent = '';
                        let hasUnsavedChanges = false;

                        window.onload = function() {
                            sketchup.getNotes();
                            document.getElementById('NA_Notebook_notepad')
                                .addEventListener('input', function() {
                                    hasUnsavedChanges = true;
                                    if (saveTimer) clearTimeout(saveTimer);
                                    saveTimer = setTimeout(function() {
                                        saveNotes();
                                    }, 1000);
                                });
                            setAutoSaveTimer();
                            window.addEventListener('beforeunload', function(e) {
                                if (hasUnsavedChanges) {
                                    sketchup.checkForUnsavedChanges();
                                    e.preventDefault();
                                    e.returnValue = '';
                                }
                            });
                        };

                        function setAutoSaveTimer() {
                            if (autoSaveTimer) clearTimeout(autoSaveTimer);
                            autoSaveTimer = setTimeout(function() {
                                if (hasUnsavedChanges) {
                                    saveNotes();
                                }
                                setAutoSaveTimer();
                            }, 5 * 60 * 1000);
                        }

                        function saveNotes() {
                            const notes = document.getElementById('NA_Notebook_notepad').value;
                            sketchup.saveNotes(notes);
                            lastSavedContent = notes;
                            hasUnsavedChanges = false;
                            updateSaveStatus();
                        }
                        function clearNotes() {
                            if (confirm('Are you sure you want to clear all notes?')) {
                                document.getElementById('NA_Notebook_notepad').value = '';
                                saveNotes();
                            }
                        }
                        function setNotes(content) {
                            document.getElementById('NA_Notebook_notepad').value = content;
                            lastSavedContent = content;
                            hasUnsavedChanges = false;
                            updateSaveStatus();
                        }
                        function updateSaveStatus() {
                            const now = new Date();
                            const timeStr = now.toLocaleTimeString();
                            document.getElementById('NA_Notebook_status').textContent = 'Last saved: ' + timeStr;
                        }
                        function checkForUnsavedChanges() {
                            const result = confirm("You have unsaved changes. Click OK to save before closing, or Cancel to continue without saving.");
                            if(result) {
                                saveNotes();
                            }
                        }
                        </script>
                    </body>
                    </html>
                HTML

                @dialog.set_html(html_content)

                @dialog.add_action_callback('saveNotes') do |_dlg, notes|
                    save_notes_to_model(notes)
                end
                @dialog.add_action_callback('getNotes') do |_dlg|
                    notes = get_notes_from_model
                    @dialog.execute_script("setNotes('#{escape_js(notes)}');")
                end
                @dialog.add_action_callback('checkForUnsavedChanges') do |_dlg|
                    # Handled in JS
                end

                add_model_observers
                @dialog
            end

            def add_model_observers
                return if @observer_added
                @model_observer = NotebookModelObserver.new
                Sketchup.active_model.add_observer(@model_observer)
                @observer_added = true
            end

            def save_current_notes
                return unless @dialog && @dialog.visible?
                @dialog.execute_script("saveNotes();")
            end

            def escape_js(string)
                return '' if string.nil?
                string.to_s.gsub(/\\/, '\\\\\\').gsub(/\n/, '\\n').gsub(/\r/, '\\r').gsub(/['"]/) { |m| "\\#{m}" }
            end

            def save_notes_to_model(notes)
                model = Sketchup.active_model
                return if model.nil?
                model.start_operation("Save Notebook Notes", true)
                dict = model.attribute_dictionary("na_notebook_dictionary")
                if dict.nil?
                    model.set_attribute("na_notebook_dictionary", "notes", notes)
                else
                    model.set_attribute("na_notebook_dictionary", "notes", notes)
                end
                model.commit_operation
            end

            def get_notes_from_model
                model = Sketchup.active_model
                return '' if model.nil?
                dict = model.attribute_dictionary("na_notebook_dictionary")
                return '' if dict.nil?
                dict["notes"] || ''
            end

            def show_notebook
                if @dialog && @dialog.visible?
                    @dialog.bring_to_front
                else
                    @dialog = create_dialog
                    @dialog.show
                end
            end
        end
        # endregion


        # region [col03] BIM Data Reporter PLUGIN
        module BIMDataReporter
            extend self

            # <--- CHANGE : Accept local logo path
            def run(logo_path)
                @dialog = UI::HtmlDialog.new(
                    dialog_title:    "Noble Architecture | BIM Data Report",
                    preferences_key: "com.noble-architecture.dc-reporter",
                    scrollable:      true,
                    resizable:       true,
                    width:           600,
                    height:          480,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )

                stylesheet = NobleArchitectureUnifiedStylesheet.shared_stylesheet
                @logo_path  = logo_path  # store local path

                # Setup callbacks
                @dialog.add_action_callback("generateReport") do |_ctx, spid_code|
                    spid_code.strip!
                    next if spid_code.empty?

                    @dialog.set_html(html_loading(stylesheet))
                    UI.start_timer(0.0, false) do
                        all_ents   = collect_all_entities
                        filtered   = filter_by_spid(all_ents, spid_code)
                        @last_spid = spid_code
                        @last_rows = build_row_data(filtered)

                        if @last_rows.empty?
                            no_html = <<-HTML
                            <!DOCTYPE html>
                            <html>
                            <head>
                                <meta charset="UTF-8">
                                <title>No Results</title>
                                <style>#{stylesheet}</style>
                            </head>
                            <body class="NA_BIM_Report_body NA_text_center NA_padding">
                                <div class="NA_BIM_Report_header">
                                    <h2>BIM Data Report</h2>
                                </div>
                                <p>No entities found containing SPID '#{spid_code}'.</p>
                                <button onclick="sketchup.goBack()">Go Back</button>
                            </body>
                            </html>
                            HTML
                            @dialog.set_html(no_html)
                        else
                            require 'json'
                            data_json = @last_rows.to_json
                            finalhtml = html_final(spid_code, data_json, stylesheet)
                            @dialog.set_html(finalhtml)
                        end
                    end
                end

                @dialog.add_action_callback("goBack") do
                    @dialog.set_html(html_prompt_spid(stylesheet))
                end

                @dialog.add_action_callback("exportCSV") do
                    if @last_rows.nil? || @last_rows.empty?
                        UI.messagebox("No data to export.")
                    else
                        csv_str = build_csv(@last_rows)
                        escaped = csv_str.gsub("\\", "\\\\").gsub("\n", "\\n").gsub("\r", "").gsub("'", "\\'")
                        @dialog.execute_script("downloadCSV('#{escaped}')")
                    end
                end

                @dialog.set_html(html_prompt_spid(stylesheet))
                @dialog.show
            end

            def html_prompt_spid(stylesheet)
                <<-HTML
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="UTF-8">
                    <title>Noble Architecture | BIM Data Report Generator</title>
                    <style>#{stylesheet}</style>
                </head>
                <body class="NA_BIM_Report_body">
                    #{NobleArchitectureUnifiedStylesheet.generate_header("BIM Data Report Generator", @logo_path)}
                    <p>Please enter your SPID code, then click "Generate Report".</p>
                    <input type="text" id="spid_input" placeholder="e.g. CP10" class="NA_input_medium">
                    <br><br>
                    <button onclick="onGenerateReport()">Generate Report</button>

                    <script>
                    function onGenerateReport() {
                        const spidValue = document.getElementById('spid_input').value.trim();
                        if (!spidValue) {
                            alert("SPID code cannot be empty.");
                            return;
                        }
                        sketchup.generateReport(spidValue);
                    }
                    </script>
                </body>
                </html>
                HTML
            end

            def html_loading(stylesheet)
                <<-HTML
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="UTF-8">
                    <title>Generating Report...</title>
                    <style>#{stylesheet}</style>
                </head>
                <body class="NA_BIM_Report_body NA_display_flex NA_flex_column NA_items_center NA_justify_center NA_full_height">
                    <div class="NA_BIM_Report_spinner"></div>
                    <div class="NA_BIM_Report_loading_text">Generating your BIM Data Report...</div>
                </body>
                </html>
                HTML
            end
            
            def html_final(spid_code, row_data_js, stylesheet)
                <<-HTML
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="UTF-8">
                    <title>Noble Architecture | BIM Data Report Generator</title>
                    <style>#{stylesheet}</style>
                </head>
                <body class="NA_BIM_Report_body">
                    #{NobleArchitectureUnifiedStylesheet.generate_header("BIM Data Report Generator", @logo_path)}
                    <div class="NA_text_secondary NA_margin_bottom_sm">
                        SPID Code Entered: <strong>#{spid_code}</strong>
                    </div>

                    <table id="dcTable">
                        <thead>
                            <tr>
                                <th onclick="onSortColumn(0)">Entity Name</th>
                                <th onclick="onSortColumn(1)">Element ID Code</th>
                                <th onclick="onSortColumn(2)">Element Floor Level</th>
                                <th onclick="onSortColumn(3)">Element Status</th>
                                <th onclick="onSortColumn(4)">Element Type</th>
                                <th onclick="onSortColumn(5)">Element Elevation</th>
                                <th onclick="onSortColumn(6)">Element Material</th>
                                <th onclick="onSortColumn(7)">Element Finish</th>
                                <th onclick="onSortColumn(8)">Element Manufacturer</th>
                                <th onclick="onSortColumn(9)">Item Code</th>
                                <th onclick="onSortColumn(10)">Component Tag ID Code</th>
                                <th onclick="onSortColumn(11)">Nesting Level</th>
                            </tr>
                        </thead>
                        <tbody id="tableBody"></tbody>
                    </table>

                    <div class="NA_BIM_btnBar NA_margin_top">
                        <button onclick="onGoBack()">Go Back</button>
                        <button onclick="onExportCSV()">Export CSV</button>
                    </div>

                    <div class="NA_BIM_footer_text">
                        Noble Architecture – BIM Report Generator v0.3.0 Beta
                    </div>

                    <script>
                    let rowData = #{row_data_js};
                    let currentSortCol = 0;
                    let currentSortDir = -1;

                    window.onload = function() {
                        sortAndRender();
                    }

                    function onSortColumn(colIndex) {
                        if(colIndex === currentSortCol) {
                            currentSortDir = -currentSortDir;
                        } else {
                            currentSortCol = colIndex;
                            currentSortDir = -1;
                        }
                        sortAndRender();
                    }

                    function sortAndRender() {
                        rowData.sort((a,b) => {
                            let x = a[currentSortCol].toLowerCase ? a[currentSortCol].toLowerCase() : a[currentSortCol];
                            let y = b[currentSortCol].toLowerCase ? b[currentSortCol].toLowerCase() : b[currentSortCol];
                            if(x < y) return -1 * currentSortDir;
                            if(x > y) return 1 * currentSortDir;
                            return 0;
                        });
                        renderTable();
                    }

                    function renderTable() {
                        let tbody = document.getElementById("tableBody");
                        tbody.innerHTML = "";
                        for(let i=0; i<rowData.length; i++) {
                            let row = rowData[i];
                            let tr = document.createElement("tr");
                            for(let c=0; c<row.length; c++) {
                                let td = document.createElement("td");
                                td.textContent = row[c];
                                tr.appendChild(td);
                            }
                            tbody.appendChild(tr);
                        }
                    }

                    function onGoBack() {
                        sketchup.goBack();
                    }
                    function onExportCSV() {
                        sketchup.exportCSV();
                    }

                    function downloadCSV(csvData) {
                        const blob = new Blob([csvData], { type: 'text/csv' });
                        const url  = URL.createObjectURL(blob);
                        const link = document.createElement('a');
                        link.href = url;
                        link.download = 'dc_report.csv';
                        document.body.appendChild(link);
                        link.click();
                        document.body.removeChild(link);
                        URL.revokeObjectURL(url);
                    }
                    </script>
                </body>
                </html>
                HTML
            end

            # region [Data Logic]
            def collect_all_entities
                model     = Sketchup.active_model
                collector = []
                traverse_entities(model.entities, 0, collector)
                collector
            end

            def traverse_entities(entities, level, collector)
                entities.each do |ent|
                    if ent.is_a?(Sketchup::Group)
                        collector << [ent, level]
                        traverse_entities(ent.entities, level + 1, collector)
                    elsif ent.is_a?(Sketchup::ComponentInstance)
                        collector << [ent, level]
                        traverse_entities(ent.definition.entities, level + 1, collector)
                    end
                end
            end

            def filter_by_spid(collected, spid)
                needle = spid.downcase
                collected.select { |(ent, _)| matches_spid?(ent, needle) }
            end

            def matches_spid?(ent, needle)
                return true if ent.name.to_s.downcase.include?(needle)
                if ent.is_a?(Sketchup::ComponentInstance)
                    defn = ent.definition.name.to_s.downcase
                    return true if defn.include?(needle)
                end
                return true if has_spid_in_attr?(ent, needle)
                return true if ent.is_a?(Sketchup::ComponentInstance) && has_spid_in_attr?(ent.definition, needle)
                false
            end

            def has_spid_in_attr?(ent, needle)
                return false unless ent.attribute_dictionaries
                ent.attribute_dictionaries.each do |dict|
                    dict.each_pair do |k, v|
                        return true if k.to_s.downcase.include?(needle) || v.to_s.downcase.include?(needle)
                    end
                end
                false
            end

            def build_row_data(filtered)
                rows = []
                filtered.each do |(ent, level)|
                    entity_name         = best_entity_name(ent)
                    element_id_code     = multi_dc_attr(ent, "b4_ent_id_code", "element_id_code")
                    floor_level         = multi_dc_attr(ent, "b1_ent_floor",   "floor_level", "a2_level_02")
                    element_status      = multi_dc_attr(ent, "b2_ent_status",  "entity_status", "a3_level_03")
                    element_type        = multi_dc_attr(ent, "b3_ent_type",    "a4_level_04")
                    element_elev        = multi_dc_attr(ent, "b5_ent_elevation")
                    mat                 = multi_dc_attr(ent, "c1_element_material")
                    fin                 = multi_dc_attr(ent, "c2_element_finish")
                    manuf               = multi_dc_attr(ent, "i3_manufacturer")
                    item_code           = multi_dc_attr(ent, "item_code", "itemcode")
                    comp_tag_id         = multi_dc_attr(ent, "component_tag_id", "a5_level_05")

                    rows << [
                        entity_name,
                        element_id_code,
                        floor_level,
                        element_status,
                        element_type,
                        element_elev,
                        mat,
                        fin,
                        manuf,
                        item_code,
                        comp_tag_id,
                        level.to_s
                    ]
                end
                rows
            end

            def best_entity_name(ent)
                return ent.name.to_s.strip unless ent.name.to_s.strip.empty?

                if ent.is_a?(Sketchup::ComponentInstance)
                    def_name = ent.definition.name.to_s.strip
                    return def_name unless def_name.empty?
                end

                dc_name = multi_dc_attr(ent, "_name")
                return dc_name unless dc_name == "—"

                "Unnamed"
            end

            def multi_dc_attr(ent, *keys)
                dds = (ent.is_a?(Sketchup::ComponentInstance) ? ent.definition.attribute_dictionaries : nil)
                gds = (ent.is_a?(Sketchup::Group) ? ent.attribute_dictionaries : nil)

                keys.each do |k|
                    val = get_dc_val(dds, k) if dds
                    val ||= get_dc_val(gds, k) if gds
                    return val unless val == "—"
                end
                "—"
            end

            def get_dc_val(dicts, key)
                return "—" unless dicts
                dyn = dicts["dynamic_attributes"]
                return "—" unless dyn
                raw = dyn[key]
                raw.nil? || raw.to_s.strip.empty? ? "—" : raw.to_s
            end

            def build_csv(rows)
                headers = [
                    "Entity Name",
                    "Element ID Code",
                    "Element Floor Level",
                    "Element Status",
                    "Element Type",
                    "Element Elevation",
                    "Element Material",
                    "Element Finish",
                    "Element Manufacturer",
                    "Item Code",
                    "Component Tag ID",
                    "Nesting Level"
                ]
                csv = headers.join(",") + "\n"
                rows.each do |r|
                    line = r.map {|val| csv_escape(val)}.join(",")
                    csv << line + "\n"
                end
                csv
            end

            def csv_escape(str)
                s = str.to_s
                if s.include?(",") || s.include?("\"")
                    s = s.gsub("\"", "\"\"")
                    s = "\"#{s}\""
                end
                s
            end
            # endregion
        end
        # endregion



        module SceneToImageExporter
            extend self
            
            # Default export settings (can be changed by user in UI)
            DEFAULT_WIDTH = 3000
            DEFAULT_HEIGHT = 2000
            DEFAULT_LINE_THICKNESS = 0.5
            MAX_FILENAME_LENGTH = 250
            
            def run
                model = Sketchup.active_model
                pages = model.pages
                
                # Check if model has scenes
                if pages.count == 0
                    UI.messagebox('No scenes found in this model.')
                    return
                end
                
                # Create dialog with unified stylesheet
                dialog = UI::HtmlDialog.new(
                    dialog_title: 'Noble Architecture | Scene Exporter',
                    preferences_key: 'com.noble-architecture.scene-exporter',
                    scrollable: true,
                    resizable: true,
                    width: 650,
                    height: 900,
                    style: UI::HtmlDialog::STYLE_DIALOG
                )
                
                dialog.set_html(generate_scene_selection_html(pages))
                
                # Set up action callbacks
                dialog.add_action_callback('exportScenes') do |_action_context, params_json|
                    begin
                        params = JSON.parse(params_json)
                        process_export(params)
                    rescue => e
                        UI.messagebox("Error: #{e.message}\n#{e.backtrace.join("\n")}")
                    end
                end
                
                dialog.show
            end
            
            # Generate the HTML for the scene selection dialog with export options
            def generate_scene_selection_html(pages)
                scene_names = pages.map(&:name)
                
                html = <<-HTML
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <title>Noble Architecture | Scene Exporter</title>
                    <style>
                        #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                        
                        /* Tool-specific styles */
                        .NA_SceneExporter_body {
                            font-family: 'Open Sans', sans-serif;
                            margin: 20px;
                            color: var(--na-text-color);
                            background: var(--na-background);
                        }
                        .NA_SceneExporter_body h2 {
                            font-weight: 600;
                            font-size: var(--na-font-size-h1);
                            margin-bottom: 10px;
                        }
                        .NA_SceneExporter_divider {
                            border-top: 1px solid var(--na-border-color);
                            margin: 20px 0;
                        }
                        .NA_SceneExporter_options {
                            display: grid;
                            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
                            gap: 15px;
                            margin-bottom: 25px;
                        }
                        .NA_SceneExporter_scene_list {
                            max-height: 300px;
                            overflow-y: auto;
                            border: 1px solid var(--na-border-color);
                            padding: 10px;
                            margin: 15px 0;
                            background: white;
                            border-radius: var(--na-border-radius);
                        }
                        .NA_SceneExporter_scene_item {
                            display: flex;
                            align-items: center;
                            padding: 6px 0;
                        }
                        .NA_SceneExporter_scene_item label {
                            margin-left: 8px;
                            display: flex;
                            align-items: center;
                            cursor: pointer;
                            font-size: var(--na-font-size-base);
                            flex: 1;
                        }
                        .NA_SceneExporter_scene_item input {
                            margin-right: 8px;
                        }
                        .NA_SceneExporter_notes {
                            background: #f0f0f0;
                            padding: 12px;
                            border-left: 3px solid var(--na-primary);
                            margin: 15px 0;
                            font-size: var(--na-font-size-base);
                            line-height: 1.5;
                            border-radius: 0 var(--na-border-radius) var(--na-border-radius) 0;
                        }
                        .NA_SceneExporter_button_group {
                            display: flex;
                            gap: 10px;
                            margin-top: 20px;
                        }
                    </style>
                </head>
                <body class="NA_SceneExporter_body">
                    #{NobleArchitectureUnifiedStylesheet.generate_header("Scene Exporter", NobleArchitectureToolbox::LOGO_PATH)}
                    <p>Export your scenes as high-quality images with custom settings.</p>
                    
                    <div class="NA_SceneExporter_notes">
                        <p>Select scenes to export and configure export settings. The exporter will create one image file per selected scene.</p>
                    </div>
                    
                    <h3>Select Scenes</h3>
                    <div class="NA_SceneExporter_button_group">
                        <button class="NA_button" onclick="selectAllScenes()">Select All</button>
                        <button class="NA_button" onclick="deselectAllScenes()">Deselect All</button>
                    </div>
                    
                    <div class="NA_SceneExporter_scene_list">
                        <!-- Scene checkboxes will be inserted here -->
                        #{generate_scene_checkboxes(scene_names)}
                    </div>
                    
                    <div class="NA_SceneExporter_divider"></div>
                    
                    <h3>Export Options</h3>
                    <div class="NA_SceneExporter_options">
                        <div class="NA_form_group">
                            <label for="export_width">Width (pixels):</label>
                            <input type="number" id="export_width" value="#{DEFAULT_WIDTH}" min="500" max="10000">
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="export_height">Height (pixels):</label>
                            <input type="number" id="export_height" value="#{DEFAULT_HEIGHT}" min="500" max="10000">
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="line_thickness">Line Thickness Multiplier:</label>
                            <input type="number" id="line_thickness" value="#{DEFAULT_LINE_THICKNESS}" min="0.1" max="3.0" step="0.1">
                        </div>
                        
                        <div class="NA_checkbox">
                            <label>
                                <input type="checkbox" id="antialias" checked>
                                Anti-aliasing
                            </label>
                        </div>
                        
                        <div class="NA_checkbox">
                            <label>
                                <input type="checkbox" id="transparent">
                                Transparent Background
                            </label>
                        </div>
                    </div>
                    
                    <button class="NA_button" onclick="exportSelectedScenes()">Export Selected Scenes</button>
                    
                    <script>
                        function selectAllScenes() {
                            document.querySelectorAll('.scene-checkbox').forEach(checkbox => {
                                checkbox.checked = true;
                            });
                        }
                        
                        function deselectAllScenes() {
                            document.querySelectorAll('.scene-checkbox').forEach(checkbox => {
                                checkbox.checked = false;
                            });
                        }
                        
                        function exportSelectedScenes() {
                            // Gather selected scenes
                            const selectedScenes = [];
                            document.querySelectorAll('.scene-checkbox:checked').forEach(checkbox => {
                                selectedScenes.push(checkbox.value);
                            });
                            
                            if (selectedScenes.length === 0) {
                                alert('Please select at least one scene to export.');
                                return;
                            }
                            
                            // Gather export settings
                            const exportSettings = {
                                scenes: selectedScenes,
                                width: parseInt(document.getElementById('export_width').value),
                                height: parseInt(document.getElementById('export_height').value),
                                line_thickness: parseFloat(document.getElementById('line_thickness').value),
                                antialias: document.getElementById('antialias').checked,
                                transparent: document.getElementById('transparent').checked
                            };
                            
                            // Validate settings
                            if (isNaN(exportSettings.width) || exportSettings.width < 500 || exportSettings.width > 10000) {
                                alert('Width must be between 500 and 10000 pixels');
                                return;
                            }
                            
                            if (isNaN(exportSettings.height) || exportSettings.height < 500 || exportSettings.height > 10000) {
                                alert('Height must be between 500 and 10000 pixels');
                                return;
                            }
                            
                            if (isNaN(exportSettings.line_thickness) || exportSettings.line_thickness < 0.1 || exportSettings.line_thickness > 3.0) {
                                alert('Line thickness multiplier must be between 0.1 and 3.0');
                                return;
                            }
                            
                            // Send export request to Ruby
                            sketchup.exportScenes(JSON.stringify(exportSettings));
                        }
                    </script>
                </body>
                </html>
                HTML
                
                return html
            end
            
            # Generate HTML for scene checkboxes
            def generate_scene_checkboxes(scene_names)
                html = ""
                scene_names.each do |name|
                    html += <<-HTML
                    <div class="NA_SceneExporter_scene_item">
                        <label>
                            <input type="checkbox" class="scene-checkbox" value="#{name}" checked>
                            #{name}
                        </label>
                    </div>
                    HTML
                end
                return html
            end
            
            # Process the export request
            def process_export(params)
                model = Sketchup.active_model
                pages = model.pages
                
                # Extract parameters
                selected_scenes = params['scenes']
                export_width = params['width']
                export_height = params['height']
                line_thickness = params['line_thickness']
                antialias = params['antialias']
                transparent = params['transparent']
                
                # Get export directory
                export_dir = UI.select_directory(title: 'Select Export Folder')
                unless export_dir
                    UI.messagebox('No directory selected. Export cancelled.')
                    return
                end
                
                # Confirm export
                proceed = UI.messagebox("Export #{selected_scenes.size} scene(s) to #{export_dir}?", MB_YESNO)
                return if proceed == IDNO
                
                # Apply rendering options
                apply_rendering_options(model, line_thickness)
                disable_scene_transitions(model)
                
                # Track results
                successful = 0
                failed = 0
                
                # Export each selected scene
                selected_scenes.each do |scene_name|
                    page = pages.find { |p| p.name == scene_name }
                    unless page
                        UI.messagebox("Could not find a scene named '#{scene_name}'")
                        failed += 1
                        next
                    end
                    
                    # Switch to scene
                    model.pages.selected_page = page
                    view = model.active_view
                    view.refresh
                    sleep(0.2) # Brief pause to ensure view updates fully
                    
                    # Create safe filename
                    safe_name = scene_name.gsub(/[^0-9A-Za-z.\-\_\s]/, '_').strip
                    filename = "#{safe_name}.png"
                    file_path = File.join(export_dir, filename)
                    
                    # Check filename length
                    if file_path.length > MAX_FILENAME_LENGTH
                        response = UI.messagebox("File path exceeds #{MAX_FILENAME_LENGTH} characters.\nCurrent path:\n#{file_path}\nContinue anyway?", MB_YESNO)
                        if response == IDNO
                            failed += 1
                            next
                        end
                    end
                    
                    # Export the image
                    begin
                        success = view.write_image(
                            filename: file_path,
                            width: export_width,
                            height: export_height,
                            antialias: antialias,
                            compression: 0,
                            transparent: transparent
                        )
                        
                        if success
                            successful += 1
                        else
                            failed += 1
                            UI.messagebox("Failed to export scene #{scene_name}")
                        end
                    rescue StandardError => e
                        failed += 1
                        UI.messagebox("An error occurred while exporting scene '#{scene_name}': #{e.message}")
                    end
                end
                
                # Show results
                if failed > 0
                    UI.messagebox("Export completed with #{successful} successful and #{failed} failed exports.")
                else
                    UI.messagebox("Export completed successfully!")
                end
            end
            
            # Apply rendering options for better line visibility
            def apply_rendering_options(model, line_thickness)
                ro = model.rendering_options
                # Store original values to potentially restore later
                @original_line_extension = ro['LineExtension'] if ro['LineExtension']
                @original_profile_line_extension = ro['ProfileLineExtension'] if ro['ProfileLineExtension']
                
                # Apply line thickness multiplier
                if ro['LineExtension']
                    ro['LineExtension'] = @original_line_extension * line_thickness
                end
                if ro['ProfileLineExtension']
                    ro['ProfileLineExtension'] = @original_profile_line_extension * line_thickness
                end
            end
            
            # Disable scene transitions for consistent exports
            def disable_scene_transitions(model)
                page_options = model.options['PageOptions']
                
                # Store original values
                @original_show_transition = page_options['ShowTransition']
                @original_transition_time = page_options['TransitionTime']
                
                # Disable transitions
                page_options['ShowTransition'] = false
                page_options['TransitionTime'] = 0.0
            end
        end

        # region [col04] =====================================================================================
        # TOOL MODULE | Guide Lines Creator
        # ----------------------------------------------------------------------------------------------------
        # Created | 26-Mar-2025
        # Updated | 26-Mar-2025
        #
        # DESCRIPTION
        # This module provides a tool for creating infinite XY guide lines in SketchUp.
        # The tool allows users to specify the Z height, X offset, and Y offset for the guides,
        # and to enable or disable the creation of X and Y guides independently.    
        #
        # IMPORTANT NOTES
        # - The tool creates infinite guide lines along the X and Y axes.
        # - The guides are created in the active model.
        # - The guides are created at the specified Z height, with optional X and Y offsets.
        # - The guides are created using the SketchUp API.
        # - The guides are created using the SketchUp API.   
        # - The tool uses the `model.start_operation` and `model.commit_operation` methods
        #   to ensure that the guides are created as a single undoable action.      
        

        module InfiniteGuideCreator
            extend self
            
            def run
                dialog = UI::HtmlDialog.new(
                    dialog_title:    "Noble Architecture | Infinite XY Guide Lines",
                    preferences_key: "com.noble-architecture.infinite-guide-creator",
                    scrollable:      true,
                    resizable:       true,
                    width:           500,
                    height:          800,
                    style:           UI::HtmlDialog::STYLE_DIALOG
                )
                
                html_content = <<-HTML
                    <!DOCTYPE html>
                    <html lang="en">
                    <head>
                        <meta charset="UTF-8">
                        <title>Noble Architecture | Infinite XY Guide Lines</title>
                        <style>
                        #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                        
                        /* Tool-specific styles */
                        .NA_InfiniteGuide_body {
                            font-family: 'Open Sans', sans-serif;
                            margin: 20px;
                            color: #333333;
                            background: #f8f8f8;
                        }
                        .NA_InfiniteGuide_body h2 {
                            font-weight: 600;
                            font-size: 18pt;
                            margin-bottom: 10px;
                            color: #333333;
                        }
                        .NA_InfiniteGuide_body p {
                            font-size: 10.5pt;
                            color: #444444;
                            margin-bottom: 20px;
                        }
                        </style>
                    </head>
                    <body class="NA_InfiniteGuide_body">
                        #{NobleArchitectureUnifiedStylesheet.generate_header("Infinite XY Guide Lines", NobleArchitectureToolbox::LOGO_PATH)}
                        <p>Create guide lines along X and Y axes with custom parameters.</p>
                        
                        <div class="NA_form_group">
                            <label for="z_height">Z Height (mm):</label>
                            <input type="text" id="z_height" value="0">
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="x_offset">X Offset (mm):</label>
                            <input type="text" id="x_offset" value="0">
                        </div>
                        
                        <div class="NA_form_group">
                            <label for="y_offset">Y Offset (mm):</label>
                            <input type="text" id="y_offset" value="0">
                        </div>
                        
                        <div class="NA_checkbox">
                            <label>
                                <input type="checkbox" id="create_x_guide" checked>
                                Create X Guide
                            </label>
                        </div>
                        
                        <div class="NA_checkbox">
                            <label>
                                <input type="checkbox" id="create_y_guide" checked>
                                Create Y Guide
                            </label>
                        </div>
                        
                        <button class="NA_button" id="create_guides">Create Guides</button>
                        
                        <script>
                            document.getElementById('create_guides').addEventListener('click', function() {
                                var z_height = document.getElementById('z_height').value;
                                var x_offset = document.getElementById('x_offset').value;
                                var y_offset = document.getElementById('y_offset').value;
                                var create_x_guide = document.getElementById('create_x_guide').checked;
                                var create_y_guide = document.getElementById('create_y_guide').checked;
                                
                                // Call Ruby callback with input values
                                sketchup.create_guides(z_height, x_offset, y_offset, create_x_guide, create_y_guide);
                            });
                        </script>
                    </body>
                    </html>
                HTML
                
                dialog.set_html(html_content)
                
                dialog.add_action_callback("create_guides") do |action_context, z_height, x_offset, y_offset, create_x, create_y|
                    create_guides(z_height, x_offset, y_offset, create_x, create_y)
                end
                
                dialog.show
            end
            
            def create_guides(z_height_str, x_offset_str, y_offset_str, create_x, create_y)
                model = Sketchup.active_model
                return if model.nil?
                
                begin
                    # Convert string inputs to numeric values
                    z_height_mm = z_height_str.empty? ? 0.0 : Float(z_height_str)
                    x_offset_mm = x_offset_str.empty? ? 0.0 : Float(x_offset_str)
                    y_offset_mm = y_offset_str.empty? ? 0.0 : Float(y_offset_str)
                    
                    # Convert mm to SketchUp inches (internal units)
                    z = z_height_mm / 25.4
                    x_offset = x_offset_mm / 25.4
                    y_offset = y_offset_mm / 25.4

                    model.start_operation('Create Infinite Guides', true)
                    entities = model.entities  # Use root entities

                    # Create X-axis guide if enabled
                    if create_x
                        point = Geom::Point3d.new(0, y_offset, z)
                        vector = Geom::Vector3d.new(1, 0, 0)
                        entities.add_cline(point, vector)
                    end

                    # Create Y-axis guide if enabled
                    if create_y
                        point = Geom::Point3d.new(x_offset, 0, z)
                        vector = Geom::Vector3d.new(0, 1, 0)
                        entities.add_cline(point, vector)
                    end

                    model.commit_operation
                    UI.messagebox("Successfully created guides at Z: #{z_height_mm}mm")
                    
                rescue ArgumentError => e
                    UI.messagebox("Invalid number format: #{e.message}")
                rescue StandardError => e
                    UI.messagebox("Error: #{e.message}")
                ensure
                    model.commit_operation if model.operation_active?
                end
            end
        end
        # endregion

        # region [col03i] =====================================================================================
        # TOOL MODULE | Staircase Maker
        # -----------------------------------------------------------------------------------------------------
        # Created | 26-Mar-2025
        # Updated | 27-Mar-2025
        #
        # DESCRIPTION
        # This module provides a tool for creating staircases in SketchUp that comply with
        # UK Building Regulations Part K. The tool validates stair designs against requirements
        # for pitch, rise, going, width, and headroom.
        #
        # IMPORTANT NOTES
        # - Proper stringer requires precise calculation of where it intersects Z=0
        # - This creates the characteristic "cutoff" at the bottom of the stringer
        # - Perpendicular vector direction uses clockwise rotation for SketchUp
        # - The underside follows the user's preferred pitch exactly

        module StairMaker
            # ----------------------------------------------------------------------------
            # CONSTANTS
            # ----------------------------------------------------------------------------
            MM_TO_INCH = 0.0393701
            INCH_TO_MM = 25.4

            # =============================================================================
            # STAIR GENERATOR CLASS
            # =============================================================================
            class StairGenerator
                # --------------------------------------------------------------------------
                # INITIALIZATION
                # --------------------------------------------------------------------------
                def initialize
                    @model = Sketchup.active_model
                    @entities = @model.active_entities
                end

                # --------------------------------------------------------------------------
                # UI CREATION
                # --------------------------------------------------------------------------
                def create_dialog
                    dialog = UI::HtmlDialog.new(
                        dialog_title:    "Noble Architecture | Stair Maker",
                        preferences_key: "com.noble-architecture.stair-maker",
                        scrollable:      true,
                        resizable:       true,
                        width:           600,
                        height:          900,
                        style:           UI::HtmlDialog::STYLE_DIALOG
                    )
                    
                    html_content = <<-HTML
                        <!DOCTYPE html>
                        <html lang="en">
                        <head>
                            <meta charset="UTF-8">
                            <title>Noble Architecture | Stair Maker</title>
                            <style>
                            #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                            
                            .NA_StairMaker_body {
                                font-family: 'Open Sans', sans-serif;
                                margin: 20px;
                                color: #333333;
                                background: #f8f8f8;
                            }
                            .NA_StairMaker_body h2 {
                                font-weight: 600;
                                font-size: 18pt;
                                color: #333333;
                                margin-bottom: 10px;
                            }
                            .NA_StairMaker_body p {
                                font-size: 10.5pt;
                                color: #444444;
                                line-height: 1.5;
                                margin-bottom: 20px;
                            }
                            .NA_StairMaker_info {
                                background: #f0f0f0;
                                padding: 15px;
                                border-radius: 4px;
                                margin-bottom: 25px;
                                border-left: 3px solid #787369;
                            }
                            .NA_StairMaker_option_group {
                                margin-bottom: 20px;
                            }
                            .NA_StairMaker_option_group label {
                                display: block;
                                font-weight: 500;
                                margin-bottom: 5px;
                            }
                            .NA_StairMaker_button {
                                background: #787369;
                                color: #ffffff;
                                border: none;
                                padding: 12px 20px;
                                border-radius: 4px;
                                font-weight: 600;
                                font-size: 11pt;
                                cursor: pointer;
                                margin-top: 10px;
                                transition: all 0.2s ease;
                            }
                            .NA_StairMaker_button:hover {
                                background: #555041;
                            }
                            .NA_StairMaker_explanation {
                                font-weight: 300;
                                color: #666666;
                                margin-left: 4px;
                            }
                            </style>
                        </head>
                        <body class="NA_StairMaker_body">
                            #{NobleArchitectureUnifiedStylesheet.generate_header("Stair Maker", NobleArchitectureToolbox::LOGO_PATH)}
                            
                            <div class="NA_StairMaker_info">
                                <p>Design stairs that comply with UK Building Regulations Part K. This tool calculates the optimal stair dimensions based on your preferred pitch and landing height, ensuring compliance with regulations.</p>
                                <p>The tool will automatically adjust parameters to ensure: <span class="NA_StairMaker_explanation">Maximum rise of 220mm, minimum going of 220mm, and 2R+G between 550-700mm</span></p>
                            </div>
                            
                            <div class="NA_form_group">
                                <label for="landing_height">Landing Height (mm):</label>
                                <input type="number" id="landing_height" placeholder="e.g. 2730" class="NA_input_medium">
                                <div id="landing_height_error" class="NA_error">Please enter a valid landing height.</div>
                            </div>
                            
                            <div class="NA_form_group">
                                <label for="pitch">Preferred Pitch (degrees):</label>
                                <input type="number" id="pitch" placeholder="e.g. 41" max="42" class="NA_input_medium">
                                <div id="pitch_error" class="NA_error">Pitch must be 42 degrees or less (Part K).</div>
                            </div>
                            
                            <div class="NA_form_group">
                                <label for="width">Stair Width (mm):</label>
                                <input type="number" id="width" placeholder="e.g. 900" min="800" class="NA_input_medium">
                                <div id="width_error" class="NA_error">Width must be at least 800mm (Part K).</div>
                            </div>
                            
                            <div class="NA_form_group">
                                <label for="stringer_width">Stringer Width (mm):</label>
                                <input type="number" id="stringer_width" placeholder="e.g. 300" min="0" class="NA_input_medium">
                                <div id="stringer_width_error" class="NA_error">Stringer width must be positive.</div>
                            </div>
                            
                            <button class="NA_StairMaker_button" onclick="generateStairs()">Generate Stairs</button>

                            <div id="results" class="NA_results">
                                <h3>Calculated Stair Dimensions:</h3>
                                <div id="result_content"></div>
                            </div>

                            <script>
                                function generateStairs() {
                                    // Validate inputs
                                    let valid = true;
                                    const landingHeight = parseFloat(document.getElementById('landing_height').value);
                                    const pitch = parseFloat(document.getElementById('pitch').value);
                                    const width = parseFloat(document.getElementById('width').value);
                                    const stringerWidth = parseFloat(document.getElementById('stringer_width').value);

                                    if (isNaN(landingHeight) || landingHeight <= 0) {
                                        document.getElementById('landing_height_error').style.display = 'block';
                                        valid = false;
                                    } else {
                                        document.getElementById('landing_height_error').style.display = 'none';
                                    }

                                    if (isNaN(pitch) || pitch <= 0 || pitch > 42) {
                                        document.getElementById('pitch_error').style.display = 'block';
                                        valid = false;
                                    } else {
                                        document.getElementById('pitch_error').style.display = 'none';
                                    }

                                    if (isNaN(width) || width < 800) {
                                        document.getElementById('width_error').style.display = 'block';
                                        valid = false;
                                    } else {
                                        document.getElementById('width_error').style.display = 'none';
                                    }

                                    if (isNaN(stringerWidth) || stringerWidth <= 0) {
                                        document.getElementById('stringer_width_error').style.display = 'block';
                                        valid = false;
                                    } else {
                                        document.getElementById('stringer_width_error').style.display = 'none';
                                    }

                                    if (valid) {
                                        sketchup.generateStairs(landingHeight, pitch, width, stringerWidth);
                                    }
                                }
                            </script>
                        </body>
                        </html>
                    HTML

                    dialog.set_html(html_content)

                    dialog.add_action_callback("generateStairs") do |action_context, landing_height, pitch, width, stringer_width|
                        generate_stairs(landing_height, pitch, width, stringer_width)
                    end

                    dialog.show
                end

                # --------------------------------------------------------------------------
                # STAIR GENERATION
                # Creates the staircase based on user parameters and UK Building Regulations
                # --------------------------------------------------------------------------
                def generate_stairs(landing_height, pitch, width, stringer_width)
                    # Convert mm to inches for SketchUp
                    landing_height_inch = landing_height * MM_TO_INCH
                    width_inch          = width          * MM_TO_INCH
                    stringer_width_inch = stringer_width * MM_TO_INCH

                    # Store the user's preferred pitch
                    preferred_pitch = pitch
                    pitch_rad       = pitch * Math::PI / 180.0

                    # Calculate ideal run from landing height and pitch
                    ideal_run = landing_height / Math.tan(pitch_rad)

                    # UK Building Regs Part K constraints
                    max_rise_mm     = 220
                    min_going_mm    = 220
                    min_steps_needed = (landing_height / max_rise_mm).ceil
                    ideal_going_mm  = ideal_run / min_steps_needed

                    # Decide actual going and pitch
                    if ideal_going_mm < min_going_mm
                        actual_going_mm = min_going_mm
                        total_run       = min_steps_needed * actual_going_mm
                        actual_pitch_rad= Math.atan(landing_height / total_run)
                        actual_pitch    = actual_pitch_rad * 180.0 / Math::PI
                    else
                        actual_going_mm = ideal_going_mm
                        actual_pitch    = preferred_pitch
                    end

                    num_steps      = min_steps_needed
                    actual_rise_mm = landing_height / num_steps

                    # Check 2R + G compliance
                    rg_sum = (2 * actual_rise_mm) + actual_going_mm
                    if rg_sum < 550 || rg_sum > 700
                        ideal_rg_sum       = 625
                        adjusted_going_mm  = ideal_rg_sum - (2 * actual_rise_mm)
                        if adjusted_going_mm >= min_going_mm
                        actual_going_mm   = adjusted_going_mm
                        total_run         = num_steps * actual_going_mm
                        actual_pitch_rad  = Math.atan(landing_height / total_run)
                        actual_pitch      = actual_pitch_rad * 180.0 / Math::PI
                        end
                    end

                    # Convert final dims to inches for modeling
                    rise_inch         = actual_rise_mm  * MM_TO_INCH
                    going_inch        = actual_going_mm * MM_TO_INCH
                    total_run_inch    = going_inch * num_steps
                    total_run_mm      = total_run_inch * INCH_TO_MM

                    final_pitch_rad   = Math.atan(landing_height_inch / total_run_inch)
                    sin_theta         = Math.sin(final_pitch_rad)
                    cos_theta         = Math.cos(final_pitch_rad)

                    @model.start_operation("Create Stairs", true)
                    stair_group       = @entities.add_group
                    stair_entities    = stair_group.entities

                    # Generate the 2D profile
                    profile_points = create_stair_profile(
                        num_steps,
                        rise_inch,
                        going_inch,
                        stringer_width_inch,
                        preferred_pitch  # Pass the user's preferred pitch to ensure stringer follows this angle
                    )

                    # Create face and push-pull to 3D
                    profile_face = stair_entities.add_face(profile_points)
                    profile_face.pushpull(width_inch)

                    # Apply a wood material if available
                    if @model.materials["Wood_Oak"]
                        stair_material = @model.materials["Wood_Oak"]
                    else
                        stair_material = @model.materials.add("Wood_Oak")
                        stair_material.color = Sketchup::Color.new(210, 180, 140)
                    end
                    stair_group.material = stair_material

                    @model.commit_operation

                    # Inform user of final values
                    message  = "Stairs created with:\n"
                    message += "- #{num_steps} steps\n"
                    message += "- Rise: #{actual_rise_mm.round(1)}mm\n"
                    message += "- Going: #{actual_going_mm.round(1)}mm\n"
                    message += "- Preferred pitch: #{preferred_pitch.round(1)}°\n"
                    message += "- Actual pitch: #{(final_pitch_rad * 180.0 / Math::PI).round(1)}°\n"
                    message += "- Total run: #{total_run_mm.round}mm\n"
                    message += "- Stringer width: #{stringer_width.round}mm"

                    UI.messagebox(message)
                end

                # --------------------------------------------------------------------------
                # CREATE_STAIR_PROFILE
                # Builds a stepped top line, offsets the underside to match the same pitch,
                # truncates at Z=0, THEN does a vertical cut at the landing.
                # --------------------------------------------------------------------------
                def create_stair_profile(num_steps, rise_inch, going_inch, stringer_width_inch, preferred_pitch)
                    # Helper: push only if new_pt != points.last
                    def safe_push(points, new_pt)
                        points << new_pt unless points.last == new_pt
                    end

                    # 1) Build top "stepped" line for the actual steps
                    # The bottom riser is at (0,0,0), each step has a riser and a tread
                    top_points = []
                    cx = 0.0
                    cz = 0.0

                    safe_push(top_points, Geom::Point3d.new(cx, 0, cz))
                    (0...num_steps).each do |step_index|
                        # Riser
                        cz += rise_inch
                        safe_push(top_points, Geom::Point3d.new(cx, 0, cz))

                        # Tread (skip after last riser)
                        unless step_index == num_steps - 1
                        cx += going_inch
                        safe_push(top_points, Geom::Point3d.new(cx, 0, cz))
                        end
                    end
                    
                    # Get the total rise and the top point
                    bottom_pt = top_points.first # (0,0,0)
                    top_pt = top_points.last     # (total_run, total_rise)
                    total_rise = top_pt.z        # This is the actual stair height
                    
                    # 2) Create a reference line at exactly the preferred pitch angle
                    # Convert preferred pitch to radians
                    pitch_rad = preferred_pitch * Math::PI / 180.0
                    
                    # Calculate how far along X the reference line needs to extend to reach the top
                    run_at_preferred_pitch = total_rise / Math.tan(pitch_rad)
                    
                    # Create reference line points
                    ref_line_start = Geom::Point3d.new(0, 0, 0)                   # Origin
                    ref_line_end = Geom::Point3d.new(run_at_preferred_pitch, 0, total_rise) # Top at preferred angle
                    
                    # 3) Calculate offset distance perpendicular to reference line
                    # The perpendicular direction to the reference line
                    ref_dx = ref_line_end.x - ref_line_start.x
                    ref_dz = ref_line_end.z - ref_line_start.z
                    ref_length = Math.sqrt(ref_dx * ref_dx + ref_dz * ref_dz)
                    
                    # Normalize to get unit vector components
                    ref_dx_unit = ref_dx / ref_length
                    ref_dz_unit = ref_dz / ref_length
                    
                    # Perpendicular unit vector (rotate 90° CLOCKWISE this time to get correct direction)
                    # In SketchUp, we need to rotate clockwise to get the correct offset direction
                    perp_dx = ref_dz_unit  # Flipped sign compared to before
                    perp_dz = -ref_dx_unit # Flipped sign compared to before
                    
                    # Calculate offset values
                    offset_dx = perp_dx * stringer_width_inch
                    offset_dz = perp_dz * stringer_width_inch
                    
                    # 4) Create the offset line for the stringer underside
                    stringer_start_x = ref_line_start.x + offset_dx
                    stringer_start_z = ref_line_start.z + offset_dz
                    stringer_end_x = ref_line_end.x + offset_dx
                    stringer_end_z = ref_line_end.z + offset_dz
                    
                    # 5) Handle ground intersection if the stringer starts below ground
                    if stringer_start_z < 0
                        # Find intersection with ground plane (z=0)
                        # Point-slope calculation for where z=0
                        t = -stringer_start_z / (stringer_end_z - stringer_start_z)
                        ground_x = stringer_start_x + t * (stringer_end_x - stringer_start_x)
                        
                        # Update stringer start to ground intersection
                        stringer_start_x = ground_x
                        stringer_start_z = 0
                    end
                    
                    # 6) Create final stringer points
                    stringer_start = Geom::Point3d.new(stringer_start_x, 0, stringer_start_z)
                    stringer_end = Geom::Point3d.new(stringer_end_x, 0, stringer_end_z)
                    
                    # 7) Create vertical landing cut
                    landing_cut = Geom::Point3d.new(stringer_end_x, 0, total_rise)
                    
                    # 8) Construct the final polygon
                    profile_points = []
                    
                    # Start with the stringer underside start point
                    safe_push(profile_points, stringer_start)
                    
                    # Add the original bottom point
                    safe_push(profile_points, bottom_pt)
                    
                    # Add all stair tread/riser points (skipping the first one already added)
                    (1...top_points.size).each do |i|
                        safe_push(profile_points, top_points[i])
                    end
                    
                    # Add the vertical landing cut
                    safe_push(profile_points, landing_cut)
                    
                    # Add the stringer end point to close the profile
                    safe_push(profile_points, stringer_end)
                    
                    # Face closes automatically
                    profile_points
                end
            end
        end
        # endregion [col03i]


        # --------------------------------------------------------------------------
        # VIEW STATE TOOL
        # - Added  -  06-May-2025
        # - A tool to toggle between showing all elements and showing only framework elements
        # - First tool button added is to isolate / un-isolate framework elements
        #
        # Tool Description
        #   - Framework elements are prefixed with "20_" in the model (20 Series)
        #     - Any group / component / dynamic component etc. with a prefix of "20_" is a framework element
        #   - The tool makes it easy to view just framework elements but to quickly revert back to the original view state
        #   - This is achieved by checking the current hidden / unhidden item status and saving it when the button is pressed.
        #   - After the button is pressed once all items not named with a prefix of "20_" are hidden.
        #   - A second button is added to revert back to the original view state; this reloads the hidden items as they were.
        #   - This allows the user to quickly toggle between the two states – view framework elements only or view everything in context.
        #   - Storing the original object hidden / unhidden view state is key to the functionality of this tool.
        #   - The SketchUp UI Button is saved in the dependencies folder within the root of the plugin.
        #     - `C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2025\SketchUp\Plugins\na_plugin-dependencies\20_01_01_-_UI-Button_-_Window-Icon.svg`
        # --------------------------------------------------------------------------

        module ViewStateTool
            extend self

            # Dictionary name for tracking framework element state
            NA_FRAMEWORK_STATE_DICT = 'NA_Framework_Element_State_Dictionary'.freeze
            
            # Framework prefixes (20_ through 29_)
            FRAMEWORK_PREFIXES = ['20_', '21_', '22_', '23_', '24_', '25_', '26_', '27_', '28_', '29_'].freeze

            # Return true when the model is in framework-only mode
            def is_framework_only?
                model = Sketchup.active_model
                dict  = model.attribute_dictionary(NA_FRAMEWORK_STATE_DICT, false)
                dict && dict['is_framework_only'] == true
            end

            # Text string for any UI toggle
            def current_state_text
                is_framework_only? ? 'Show All Elements' : 'Show Framework Only'
            end

            # Toggle between view states
            def toggle_framework_view
                is_framework_only? ? show_all_elements : show_framework_only
            end
            
            # Check if this is a framework element (20-29 series)
            def is_framework_element?(entity)
                return false unless entity.respond_to?(:name)
                
                # Check entity name
                if !entity.name.to_s.empty?
                    FRAMEWORK_PREFIXES.each do |prefix|
                        return true if entity.name.to_s.start_with?(prefix)
                    end
                end
                
                # For components, also check definition name
                if entity.is_a?(Sketchup::ComponentInstance) && entity.definition.respond_to?(:name)
                    FRAMEWORK_PREFIXES.each do |prefix|
                        return true if entity.definition.name.to_s.start_with?(prefix)
                    end
                end
                
                false
            end

            # ----------------------------------------------------------------------
            # Show only framework elements
            # ----------------------------------------------------------------------
            def show_framework_only
                model = Sketchup.active_model
                hidden_state = {}
                framework_containers = []

                model.start_operation('Show Framework Elements Only', true)

                # First, mark all top-level framework containers
                model.entities.each do |entity|
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    next unless entity.valid?
                    
                    # Record current hidden state
                    hidden_state[entity.entityID] = entity.hidden?
                    
                    # Check if this is a framework element
                    if is_framework_element?(entity)
                        framework_containers << entity
                    end
                end
                
                # Hide all top-level entities except framework containers
                model.entities.each do |entity|
                    next unless entity.valid?
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    
                    if framework_containers.include?(entity)
                        entity.hidden = false
                        # Make sure all nested entities are visible too
                        unhide_all_nested_entities(entity)
                    else
                        entity.hidden = true
                    end
                end
                
                # Force refresh
                model.active_view.refresh

                # Store the hidden state
                model.set_attribute(NA_FRAMEWORK_STATE_DICT, 'hidden_state', hidden_state)
                model.set_attribute(NA_FRAMEWORK_STATE_DICT, 'is_framework_only', true)

                model.commit_operation
            end
            
            # Make all nested entities visible
            def unhide_all_nested_entities(container)
                if container.is_a?(Sketchup::Group)
                    entities = container.entities
                elsif container.is_a?(Sketchup::ComponentInstance)
                    entities = container.definition.entities
                else
                    return
                end
                
                entities.each do |entity|
                    entity.hidden = false if entity.respond_to?(:hidden=)
                    
                    # Recurse for nested containers
                    if (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.valid?
                        unhide_all_nested_entities(entity)
                    end
                end
            end

            # ----------------------------------------------------------------------
            # Restore the original visibility state
            # ----------------------------------------------------------------------
            def show_all_elements
                model = Sketchup.active_model
                dict  = model.attribute_dictionary(NA_FRAMEWORK_STATE_DICT, false)
                return unless dict && dict['is_framework_only']

                hidden_state = dict['hidden_state'] || {}

                model.start_operation('Show All Elements', true)

                process_entities = lambda do |entities|
                    entities.each do |entity|
                        next unless entity.valid?
                        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

                        # Restore original hidden state or default to visible
                        entity.hidden = hidden_state.fetch(entity.entityID, false)

                        # Process children
                        if entity.is_a?(Sketchup::Group)
                            process_entities.call(entity.entities)
                        elsif entity.is_a?(Sketchup::ComponentInstance)
                            process_entities.call(entity.definition.entities)
                        end
                    end
                end

                # Process all entities
                process_entities.call(model.entities)
                
                # Force refresh
                model.active_view.refresh

                # Clear stored state
                model.set_attribute(NA_FRAMEWORK_STATE_DICT, 'hidden_state', {})
                model.set_attribute(NA_FRAMEWORK_STATE_DICT, 'is_framework_only', false)

                model.commit_operation
            end
        end
        # endregion

        # --------------------------------------------------------------------------
        # MIRROR PLANES TOOL
        # - Added  -  15-May-2025
        # - A tool to toggle between showing and hiding 3D mirror planes in the model
        # - This tool toggles any entity or tag with the prefix "00_31_"
        #
        # Tool Description
        #   - Mirror planes are prefixed with "00_31_" in the model
        #     - Any group / component / dynamic component etc. with a prefix of "00_31_" is a mirror plane
        #   - The tool makes it easy to toggle visibility of mirror planes in the model
        #   - This is achieved by checking the current hidden / unhidden item status and saving it when the button is pressed
        #   - When the button is pressed, all items with the "00_31_" prefix are toggled (shown/hidden)
        #   - This allows the user to quickly toggle the visibility of 3D mirror planes
        #   - The SketchUp UI Button is saved in the dependencies folder within the root of the plugin.
        #     - `00_31_01_-_UI-Button_-_Mirror-Icon.svg`
        # --------------------------------------------------------------------------

        module MirrorPlanesTool
            extend self

            # Dictionary name for tracking mirror plane state
            NA_MIRROR_STATE_DICT = 'NA_Mirror_Planes_State_Dictionary'.freeze
            
            # Mirror planes prefix
            MIRROR_PREFIX = '00_31_'.freeze

            # Return true when mirror planes are hidden
            def are_mirror_planes_hidden?
                model = Sketchup.active_model
                dict  = model.attribute_dictionary(NA_MIRROR_STATE_DICT, false)
                dict && dict['are_mirror_planes_hidden'] == true
            end

            # Text string for UI toggle
            def current_state_text
                are_mirror_planes_hidden? ? 'Show Mirror Planes' : 'Hide Mirror Planes'
            end

            # Toggle between view states
            def toggle_mirror_planes
                are_mirror_planes_hidden? ? show_mirror_planes : hide_mirror_planes
            end
            
            # Check if this is a mirror plane element
            def is_mirror_plane?(entity)
                return false unless entity.respond_to?(:name)
                
                # Check entity name
                if !entity.name.to_s.empty?
                    return true if entity.name.to_s.start_with?(MIRROR_PREFIX)
                end
                
                # For components, also check definition name
                if entity.is_a?(Sketchup::ComponentInstance) && entity.definition.respond_to?(:name)
                    return true if entity.definition.name.to_s.start_with?(MIRROR_PREFIX)
                end
                
                false
            end

            # ----------------------------------------------------------------------
            # Hide mirror plane elements
            # ----------------------------------------------------------------------
            def hide_mirror_planes
                model = Sketchup.active_model
                hidden_state = {}
                mirror_containers = []

                model.start_operation('Hide Mirror Planes', true)

                # Save current hidden state for mirror elements
                model.entities.each do |entity|
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    next unless entity.valid?
                    
                    if is_mirror_plane?(entity)
                        # Record current hidden state
                        hidden_state[entity.entityID] = entity.hidden?
                        mirror_containers << entity
                        # Hide the mirror element
                        entity.hidden = true
                    end
                end
                
                # Also handle mirror plane tags/layers
                model.layers.each do |layer|
                    if layer.name.start_with?(MIRROR_PREFIX)
                        # Store current visibility and hide the layer
                        hidden_state["layer_#{layer.entityID}"] = layer.visible?
                        layer.visible = false
                    end
                end
                
                # Force refresh
                model.active_view.refresh

                # Store the hidden state
                model.set_attribute(NA_MIRROR_STATE_DICT, 'hidden_state', hidden_state)
                model.set_attribute(NA_MIRROR_STATE_DICT, 'are_mirror_planes_hidden', true)

                model.commit_operation
            end

            # ----------------------------------------------------------------------
            # Restore mirror plane elements
            # ----------------------------------------------------------------------
            def show_mirror_planes
                model = Sketchup.active_model
                dict  = model.attribute_dictionary(NA_MIRROR_STATE_DICT, false)
                return unless dict && dict['are_mirror_planes_hidden']

                hidden_state = dict['hidden_state'] || {}

                model.start_operation('Show Mirror Planes', true)

                # Process entities
                model.entities.each do |entity|
                    next unless entity.valid?
                    next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                    next unless is_mirror_plane?(entity)

                    # Restore original hidden state or default to visible
                    entity.hidden = hidden_state.fetch(entity.entityID, false)
                end

                # Process tags/layers
                model.layers.each do |layer|
                    if layer.name.start_with?(MIRROR_PREFIX)
                        # Restore original visibility
                        layer_visible = hidden_state.fetch("layer_#{layer.entityID}", true)
                        layer.visible = layer_visible
                    end
                end
                
                # Force refresh
                model.active_view.refresh

                # Clear stored state
                model.set_attribute(NA_MIRROR_STATE_DICT, 'hidden_state', {})
                model.set_attribute(NA_MIRROR_STATE_DICT, 'are_mirror_planes_hidden', false)

                model.commit_operation
            end
        end
        # endregion

        # ------------------------------------------------------------------------------------------------
        # region [col04] =====================================================================================
        # Profile Path Tracer Tool
        # - Added  -  15-May-2025
        # - A tool to extrude profile components along edge paths
        # - Select a profile from a library and extrude it along edge paths in the model
        # - Provides thumbnail preview of available profiles for easy selection
        # -----------------------------------------------------------------------------------------------------
        module ProfilePathTracer
            extend self
            
            # Profile library path - hardcoded for initial implementation, will be configurable in future versions
            PROFILE_LIBRARY_PATH = 'D:/02_-_Core-Lib_-_SketchUp/01_-_Core-Lib_-_SU-Components/70-Series_-_Standard-Vale-Profiles-Library'
            
            # Cache for profile thumbnails to avoid regenerating them
            @profile_thumbnails = {}
            @loaded_definitions = {}
            @selected_path_edges = nil
            @path_selection_pending = false
            @selected_profile_path = nil
            @mirror_profile = false  # <--- CHANGE: Added mirror profile flag
            
            def run
                # Check if path exists, show error if not
                unless Dir.exist?(PROFILE_LIBRARY_PATH)
                    UI.messagebox("Profile library folder not found at:\n#{PROFILE_LIBRARY_PATH}\n\nPlease ensure the folder exists.")
                    return
                end
                
                # Reset selection state
                @selected_path_edges = nil
                @path_selection_pending = false
                @selected_profile_path = nil
                @mirror_profile = false  # <--- CHANGE: Reset mirror flag
                
                # Create and show the profile selection dialog
                show_profile_selection_dialog
            end
            
            def show_profile_selection_dialog
                dialog = UI::HtmlDialog.new(
                    dialog_title: "Noble Architecture | Profile Path Tracer",
                    preferences_key: "com.noble-architecture.profile-path-tracer",
                    scrollable: true,
                    resizable: true,
                    width: 650,
                    height: 800,
                    style: UI::HtmlDialog::STYLE_DIALOG
                )
                
                # Set the HTML content for the dialog
                dialog.set_html(generate_html_content)
                
                # Add action callbacks for dialog interaction
                add_dialog_callbacks(dialog)
                
                # Show the dialog
                dialog.show
            end
            
            def generate_html_content
                # Get the list of profile files from the library folder
                profile_files = get_profile_files
                
                # Generate HTML for profile thumbnails
                profile_thumbs_html = generate_profile_thumbnails_html(profile_files)
                
                # Create complete HTML content
                html = <<-HTML
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <title>Noble Architecture | Profile Path Tracer</title>
                    <style>
                        #{NobleArchitectureUnifiedStylesheet.shared_stylesheet}
                        
                        /* Tool-specific styles */
                        .NA_ProfilePathTracer_body {
                            font-family: 'Open Sans', sans-serif;
                            margin: 20px;
                            color: var(--na-text-color);
                            background: var(--na-background);
                        }
                        
                        .NA_profiles_container {
                            display: grid;
                            grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
                            gap: 15px;
                            max-height: 400px;
                            overflow-y: auto;
                            margin: 20px 0;
                            padding: 10px;
                            background: white;
                            border: 1px solid var(--na-border-color);
                            border-radius: var(--na-border-radius);
                        }
                        
                        .NA_profile_item {
                            display: flex;
                            flex-direction: column;
                            align-items: center;
                            cursor: pointer;
                            padding: 10px;
                            border: 2px solid transparent;
                            border-radius: var(--na-border-radius);
                            transition: all 0.2s ease;
                        }
                        
                        .NA_profile_item:hover {
                            background-color: #f0f0f0;
                        }
                        
                        .NA_profile_item.selected {
                            border-color: var(--na-primary);
                            background-color: rgba(120, 115, 105, 0.1);
                        }
                        
                        .NA_profile_thumb {
                            width: 100px;
                            height: 100px;
                            object-fit: contain;
                            border: 1px solid #e0e0e0;
                            background-color: white;
                        }
                        
                        .NA_profile_name {
                            margin-top: 8px;
                            font-size: 9pt;
                            text-align: center;
                            max-width: 100%;
                            overflow: hidden;
                            text-overflow: ellipsis;
                            white-space: nowrap;
                        }
                        
                        .NA_path_selection {
                            margin-top: 20px;
                            padding: 15px;
                            background-color: #f8f8f8;
                            border: 1px solid var(--na-border-color);
                            border-radius: var(--na-border-radius);
                            display: none;
                        }
                        
                        .NA_path_selection.active {
                            display: block;
                        }
                        
                        .NA_divider {
                            margin: 20px 0;
                            border-top: 1px solid var(--na-border-color);
                        }
                        
                        .NA_notes {
                            background: #f0f0f0;
                            padding: 15px;
                            border-left: 3px solid var(--na-primary);
                            margin-top: 20px;
                            font-size: var(--na-font-size-base);
                            line-height: 1.5;
                            border-radius: 0 var(--na-border-radius) var(--na-border-radius) 0;
                        }
                        
                        /* <--- CHANGE: Added styles for the mirror option */
                        .NA_mirror_option {
                            margin: 15px 0;
                            padding: 10px;
                            background-color: #f0f0f0;
                            border-radius: var(--na-border-radius);
                        }
                        
                        .NA_checkbox_container {
                            display: flex;
                            align-items: center;
                            margin-bottom: 10px;
                        }
                        
                        .NA_checkbox_container input {
                            margin-right: 8px;
                        }
                        
                        .NA_mirror_explanation {
                            font-size: 9pt;
                            color: #666;
                            margin-top: 5px;
                        }
                    </style>
                </head>
                <body class="NA_ProfilePathTracer_body">
                    #{NobleArchitectureUnifiedStylesheet.generate_header("Profile Path Tracer", NobleArchitectureToolbox::LOGO_PATH)}
                    
                    <p>Select a profile from the library, then trace it along a path in your model.</p>
                    
                    <h3>Profile Library</h3>
                    <div class="NA_profiles_container">
                        #{profile_thumbs_html}
                    </div>
                    
                    <div id="selected_profile_info" class="NA_path_selection">
                        <h3>Selected Profile: <span id="profile_name">None</span></h3>
                        
                        <!-- <--- CHANGE: Added mirror profile option -->
                        <div class="NA_mirror_option">
                            <div class="NA_checkbox_container">
                                <input type="checkbox" id="mirror_profile" onchange="onMirrorChange()">
                                <label for="mirror_profile">Mirror Profile</label>
                            </div>
                            <div class="NA_mirror_explanation">
                                Toggle this option to flip the profile orientation (left/right) along the path.
                            </div>
                        </div>
                        
                        <p>Now select a path in your model for the profile extrusion.</p>
                        <div class="NA_form_group">
                            <button id="btn_select_path" class="NA_button">Select Path</button>
                            <button id="btn_extrude_profile" class="NA_button" style="display: none;">Extrude Profile</button>
                        </div>
                    </div>
                    
                    <div class="NA_notes">
                        <p><strong>Using the Profile Path Tracer:</strong></p>
                        <ol>
                            <li>Select a profile from the library above</li>
                            <li>Click "Select Path" to choose a continuous chain of edges</li>
                            <li>Toggle "Mirror Profile" if you need to flip the profile orientation</li>
                            <li>The profile will be extruded along the selected path</li>
                        </ol>
                        <p><em>Note: The profile's axis point will be used as the origin for the extrusion, with Z-up being the face normal.</em></p>
                    </div>
                    
                    <script>
                        let selectedProfilePath = null;
                        let mirrorProfile = false; // <--- CHANGE: Track mirror state
                        
                        // Initialize with no profile selected
                        function selectProfile(profilePath) {
                            // Remove selection from all profiles
                            document.querySelectorAll('.NA_profile_item').forEach(item => {
                                item.classList.remove('selected');
                            });
                            
                            // Add selection to clicked profile
                            document.getElementById('profile_' + btoa(profilePath)).classList.add('selected');
                            
                            // Update selected profile info
                            const profileName = profilePath.split('/').pop().replace('.skp', '');
                            document.getElementById('profile_name').textContent = profileName;
                            
                            // Show path selection section
                            document.getElementById('selected_profile_info').classList.add('active');
                            
                            // Store selected profile path
                            selectedProfilePath = profilePath;
                            
                            // Notify Ruby of selection
                            sketchup.profileSelected(profilePath);
                        }
                        
                        // <--- CHANGE: Added mirror toggle handler -->
                        function onMirrorChange() {
                            mirrorProfile = document.getElementById('mirror_profile').checked;
                            sketchup.setMirrorProfile(mirrorProfile);
                        }
                        
                        // Handle select path button click
                        document.getElementById('btn_select_path').addEventListener('click', function() {
                            if (selectedProfilePath) {
                                sketchup.selectPath();
                            }
                        });
                        
                        // Handle extrude profile button click
                        document.getElementById('btn_extrude_profile').addEventListener('click', function() {
                            if (selectedProfilePath) {
                                // <--- CHANGE: Pass mirror state to Ruby -->
                                sketchup.extrudeProfile(mirrorProfile);
                            }
                        });
                        
                        function showExtrudeButton() {
                            document.getElementById('btn_extrude_profile').style.display = 'inline-block';
                        }
                        
                        function hideExtrudeButton() {
                            document.getElementById('btn_extrude_profile').style.display = 'none';
                        }
                    </script>
                </body>
                </html>
                HTML
                
                return html
            end
            
            def get_profile_files
                # Get all .skp files in the library folder
                Dir.glob(File.join(PROFILE_LIBRARY_PATH, "*.skp")).sort
            end
            
            def generate_profile_thumbnails_html(profile_files)
                html = ""
                
                # For each profile file, generate a thumbnail element
                profile_files.each do |profile_path|
                    # Get just the filename without extension for display
                    filename = File.basename(profile_path, '.skp')
                    
                    # Create a unique ID for the profile item
                    profile_id = "profile_" + Base64.strict_encode64(profile_path)
                    
                    # Generate thumbnail path or use placeholder
                    thumbnail_path = get_or_generate_thumbnail(profile_path)
                    
                    # Create HTML for this profile
                    html += <<-HTML
                    <div class="NA_profile_item" id="#{profile_id}" onclick="selectProfile('#{profile_path.gsub("\\", "\\\\")}')">
                        <img src="file:///#{thumbnail_path.gsub("\\", "/")}" class="NA_profile_thumb" alt="#{filename}">
                        <div class="NA_profile_name">#{filename}</div>
                    </div>
                    HTML
                end
                
                return html
            end
            
            def get_or_generate_thumbnail(profile_path)
                # Return cached thumbnail if available
                return @profile_thumbnails[profile_path] if @profile_thumbnails[profile_path]
                
                # Create a temp directory for thumbnails if it doesn't exist
                temp_dir = File.join(Sketchup.temp_dir, 'na_profile_thumbnails')
                Dir.mkdir(temp_dir) unless Dir.exist?(temp_dir)
                
                # Generate a unique filename for the thumbnail
                thumbnail_filename = "#{Digest::MD5.hexdigest(profile_path)}.png"
                thumbnail_path = File.join(temp_dir, thumbnail_filename)
                
                # Check if thumbnail already exists
                unless File.exist?(thumbnail_path)
                    # Extract thumbnail from the .skp file
                    begin
                        Sketchup.save_thumbnail(profile_path, thumbnail_path)
                    rescue => e
                        # If thumbnail extraction fails, use a placeholder image
                        puts "Error extracting thumbnail: #{e.message}"
                        # Use default thumbnail (could be a generic placeholder)
                        thumbnail_path = File.join(File.dirname(__FILE__), "na_plugin-dependencies", "profile_placeholder.png")
                    end
                end
                
                # Cache the thumbnail path
                @profile_thumbnails[profile_path] = thumbnail_path
                
                return thumbnail_path
            end
            
            def add_dialog_callbacks(dialog)
                # Handle profile selection
                dialog.add_action_callback('profileSelected') do |action_context, profile_path|
                    @selected_profile_path = profile_path
                    # Preload the definition so it's ready when needed
                    load_profile_definition(profile_path)
                end
                
                # <--- CHANGE: Added callback for mirror profile toggle -->
                dialog.add_action_callback('setMirrorProfile') do |action_context, mirror_state|
                    @mirror_profile = mirror_state
                end
                
                # Handle path selection
                dialog.add_action_callback('selectPath') do |action_context|
                    # Prompt user to select a path
                    select_path_for_extrusion(dialog)
                end
                
                # <--- CHANGE: Updated to accept mirror parameter -->
                dialog.add_action_callback('extrudeProfile') do |action_context, mirror_state = false|
                    @mirror_profile = mirror_state
                    extrude_profile_along_path
                end
            end
            
            def load_profile_definition(profile_path)
                # Skip if already loaded
                return @loaded_definitions[profile_path] if @loaded_definitions[profile_path]
                
                # Load the profile component definition
                model = Sketchup.active_model
                begin
                    definition = model.definitions.load(profile_path)
                    @loaded_definitions[profile_path] = definition
                    return definition
                rescue => e
                    puts "Error loading profile definition: #{e.message}"
                    UI.messagebox("Failed to load profile from:\n#{profile_path}")
                    return nil
                end
            end
            
            def select_path_for_extrusion(dialog)
                model = Sketchup.active_model
                selection = model.selection
                
                # Clear any existing selection to ensure clean start
                selection.clear
                
                # <--- CHANGE: Remove popup, use status text instead -->
                Sketchup.status_text = "Select a path (edges or curve) for profile extrusion, then click 'Extrude Profile'"
                
                # Enable the extrude button regardless of current selection
                dialog.execute_script("showExtrudeButton()")
                @path_selection_pending = true
            end
            
            def extrude_profile_along_path
                model = Sketchup.active_model
                
                # Check if we have all the necessary information
                if @selected_profile_path.nil?
                    UI.messagebox("Please select a profile first.")
                    return
                end
                
                # <--- CHANGE: Get currently selected edges -->
                edges = model.selection.grep(Sketchup::Edge)
                curve_path = model.selection.grep(Sketchup::Curve).first
                
                # <--- CHANGE: Handle both edge selections and curve selections -->
                if edges.empty? && curve_path.nil?
                    UI.messagebox("Please select edges or a curve for the extrusion path.")
                    return
                end
                
                # Use curve if selected, otherwise use edges
                path_entities = curve_path ? [curve_path] : edges.to_a
                
                # Make sure the profile definition is loaded
                definition = load_profile_definition(@selected_profile_path)
                if definition.nil?
                    return
                end
                
                # Start the extrusion operation
                model.start_operation("Profile Path Trace", true)
                
                begin
                    # Create a temporary group for the extrusion
                    temp_group = model.active_entities.add_group
                    
                    # Calculate the position and orientation for the profile
                    if position_profile_at_path_start(temp_group, definition, path_entities, @mirror_profile)
                        # Get the profile face from the temporary group
                        profile_face = find_profile_face(temp_group)
                        
                        if profile_face
                            # <--- CHANGE: Improved path handling for both curves and edges -->
                            success = false
                            
                            if curve_path
                                # For curve, use directly
                                success = profile_face.followme([curve_path])
                            else
                                # For edges, use our existing path handling
                                path_edges = get_path_edges_in_context(temp_group, edges)
                                success = profile_face.followme(path_edges)
                            end
                            
                            if success
                                # Commit the operation
                                model.commit_operation
                                Sketchup.status_text = "Profile successfully extruded along the path."
                            else
                                model.abort_operation
                                UI.messagebox("Failed to extrude profile. Please check that the profile and path are valid.")
                            end
                        else
                            model.abort_operation
                            UI.messagebox("Could not find a valid face in the profile.")
                        end
                    else
                        model.abort_operation
                        UI.messagebox("Failed to position the profile at the path start.")
                    end
                rescue => e
                    model.abort_operation
                    puts "Error during extrusion: #{e.message}"
                    puts e.backtrace.join("\n")
                    UI.messagebox("An error occurred during extrusion: #{e.message}")
                end
            end
            
            # <--- CHANGE: Update to handle both edges and curves -->
            def position_profile_at_path_start(group, definition, path_entities, mirror_profile = false)
                # Determine if we're working with a curve or edges
                if path_entities.first.is_a?(Sketchup::Curve)
                    # Handle curve
                    curve = path_entities.first
                    start_point = curve.start.position
                    
                    # Get a point a small distance away on the curve for direction
                    # This approach handles curves better than just using the first segment
                    curve_length = curve.length
                    parameter = [curve_length * 0.01, 1.0].min # 1% of curve length or 1 inch, whichever is smaller
                    direction_point = curve.points_at_parameter(parameter).first
                    
                    path_direction = start_point.vector_to(direction_point)
                else
                    # Original code for handling edges
                    first_edge = path_entities.first
                    
                    # Determine path direction (use the edge's vector)
                    start_point = first_edge.start.position
                    end_point = first_edge.end.position
                    
                    # Check if the path continues from this edge
                    connected_edges = path_entities.select { |e| e != first_edge && (e.start == first_edge.end || e.end == first_edge.end) }
                    
                    # If no connected edges or connected edge is at the start, reverse the direction
                    if connected_edges.empty? || (connected_edges.first.start == first_edge.start || connected_edges.first.end == first_edge.start)
                        start_point, end_point = end_point, start_point
                    end
                    
                    path_direction = end_point.vector_to(start_point)
                end
                
                # Normalize direction
                path_direction.normalize!
                
                # Define the up vector (Z axis by default)
                up_vector = Geom::Vector3d.new(0, 0, 1)
                
                # Create a perpendicular vector for the X axis
                x_axis = path_direction.cross(up_vector)
                
                # If path is parallel to Z axis, use a different up vector
                if x_axis.length < 0.001
                    up_vector = Geom::Vector3d.new(1, 0, 0)
                    x_axis = path_direction.cross(up_vector)
                end
                
                x_axis.normalize!
                
                # Recalculate the Y axis to ensure orthogonality
                y_axis = x_axis.cross(path_direction)
                y_axis.normalize!
                
                # Mirror if requested
                if mirror_profile
                    # <--- CHANGE: Fix the mirroring to properly flip left-to-right -->
                    # Instead of reversing up_vector, directly invert the lateral axis
                    # This gives us proper left-right mirroring relative to the path direction
                    x_axis.reverse!
                    
                    # Keep y_axis the same direction to maintain proper orientation
                    # No need to recalculate y_axis since we want to keep its direction
                end
                
                # Create a transformation that positions and orients the profile
                transformation = Geom::Transformation.axes(start_point, x_axis, y_axis, path_direction)
                
                # Add the profile to the group with the transformation
                instance = group.entities.add_instance(definition, transformation)
                
                # Explode the instance to get the raw geometry
                instance.explode
                
                return true
            rescue => e
                puts "Error positioning profile: #{e.message}"
                puts e.backtrace.join("\n")
                return false
            end
            
            def find_profile_face(group)
                # Find all faces in the group
                faces = group.entities.grep(Sketchup::Face)
                
                # For simplicity, return the first face found
                # In a more complex implementation, could select based on area or other criteria
                return faces.first
            end
            
            def get_path_edges_in_context(group, original_edges)
                # Create a mapping of original to transformed edges
                edge_map = {}
                original_edge_vertices = {}
                
                # Store vertex positions of original edges
                original_edges.each do |edge|
                    original_edge_vertices[edge] = [edge.start.position, edge.end.position]
                end
                
                # Find matching edges in the group's context
                group_edges = group.entities.grep(Sketchup::Edge)
                
                # Match edges in the group to original edges
                # FIX: Use Geom::Transformation.new instead of Geom::Transformation.identity
                group.transformation = Geom::Transformation.new
                group_edges.each do |group_edge|
                    original_edges.each do |orig_edge|
                        orig_positions = original_edge_vertices[orig_edge]
                        
                        # Check if the edge positions match
                        if (group_edge.start.position == orig_positions[0] && group_edge.end.position == orig_positions[1]) ||
                           (group_edge.start.position == orig_positions[1] && group_edge.end.position == orig_positions[0])
                            edge_map[orig_edge] = group_edge
                            break
                        end
                    end
                end
                
                # Return transformed edges in the same order as original edges
                result = original_edges.map { |e| edge_map[e] }.compact
                
                # If we couldn't map all edges, create temporary ones
                if result.length != original_edges.length
                    # Clean up any partial mapping and create a fresh copy of the path
                    # For more complex cases, we would need more sophisticated edge connection logic
                    
                    # Reset the result array
                    result = []
                    
                    # Create new edges in the group's context following the original path
                    prev_point = nil
                    original_edges.each do |orig_edge|
                        start_point = orig_edge.start.position
                        end_point = orig_edge.end.position
                        
                        # Determine the direction based on connectivity
                        if prev_point && prev_point.distance(end_point) < prev_point.distance(start_point)
                            start_point, end_point = end_point, start_point
                        end
                        
                        # Create new edge in the group
                        new_edge = group.entities.add_line(start_point, end_point)
                        result << new_edge
                        
                        prev_point = end_point
                    end
                end
                
                return result
            end
            
            # Add an improved function to better handle path ordering
            def order_edges_in_path(edges)
                return edges if edges.length <= 1
                
                # Build a graph representation of the edges
                edge_connectivity = {}
                
                edges.each do |edge|
                    start_vertex = edge.start
                    end_vertex = edge.end
                    
                    edge_connectivity[edge] = {
                        start_vertex => start_vertex.position,
                        end_vertex => end_vertex.position
                    }
                end
                
                # Find a potential start edge (with a vertex connected to only one edge)
                start_edge = nil
                start_vertex = nil
                
                # Count vertex occurrences
                vertex_count = Hash.new(0)
                edges.each do |edge|
                    vertex_count[edge.start] += 1
                    vertex_count[edge.end] += 1
                end
                
                # Find vertices that appear only once (endpoints of the path)
                endpoints = vertex_count.select { |v, count| count == 1 }.keys
                
                if endpoints.length == 2
                    # We have a linear path (not a loop)
                    start_vertex = endpoints.first
                    start_edge = edges.find { |e| e.start == start_vertex || e.end == start_vertex }
                else
                    # It's a loop or invalid path - just pick the first edge
                    start_edge = edges.first
                    start_vertex = start_edge.start
                end
                
                # Order the edges starting from start_edge
                ordered_edges = [start_edge]
                current_vertex = (start_edge.start == start_vertex) ? start_edge.end : start_edge.start
                remaining_edges = edges.reject { |e| e == start_edge }
                
                while !remaining_edges.empty?
                    # Find the next edge connected to current_vertex
                    next_edge = remaining_edges.find { |e| e.start == current_vertex || e.end == current_vertex }
                    
                    break unless next_edge # No more connected edges
                    
                    ordered_edges << next_edge
                    remaining_edges.delete(next_edge)
                    
                    # Update current_vertex to the other end of next_edge
                    current_vertex = (next_edge.start == current_vertex) ? next_edge.end : next_edge.start
                end
                
                return ordered_edges
            end

            # <--- CHANGE: Added helper function to verify continuous path -->
            def verify_continuous_path(edges)
                return true if edges.length <= 1
                
                # Count connections between edges
                connections = 0
                
                edges.each_with_index do |edge1, i|
                    edges.each_with_index do |edge2, j|
                        next if i == j
                        
                        # Check if edges share a vertex
                        if edge1.start == edge2.start || 
                           edge1.start == edge2.end ||
                           edge1.end == edge2.start ||
                           edge1.end == edge2.end
                            connections += 1
                        end
                    end
                end
                
                # For a continuous path of n edges, we need at least n-1 connections
                # (Each edge except potentially the first and last should connect to 2 other edges)
                connections >= (edges.length - 1)
            end
        end
        # endregion

        end     # <--- Closes NA_Tools Module
        end         # <--- Closes NobleArchitectureToolbox Module

        # endregion [col03]


        

# region [col04] =====================================================================================
# CONTEXT MENU
# -----------------------------------------------------------------------------------------------------
UI.add_context_menu_handler do |menu|
    model     = Sketchup.active_model
    selection = model.selection

    # If a group or component is selected, add isolate/duplicate items
    if selection.any? { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        menu.add_item("NA | Duplicate Selected Entity") {
            NobleArchitectureToolbox::NA_Tools::DuplicateSelectedEntityTool.run
        }
        menu.add_separator

        menu.add_item("NA | Isolate Selected Entity") {
            NobleArchitectureToolbox::NA_Tools::IsolateSelectedEntityTool.run_isolate
        }
    end

    # Deep Paint
    menu.add_item("NA | Deep Paint Face") {
        NobleArchitectureToolbox::NA_Tools::DeepPaintFacesTool.run
    }
end

# endregion [col04]


# region [col05] =====================================================================================
# EXTENSION MENU & TOOLBAR
# -----------------------------------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Create a command for the main toolbox UI
    toolbox_cmd = UI::Command.new("Noble Architecture | Toolbox") {
        NobleArchitectureToolbox.run
    }
    
    # Set command properties
    plugin_dir = File.dirname(__FILE__)
    main_launcher_icon_path = File.join(plugin_dir, "na_plugin-dependencies", "na_custom_icon.png")
    paint_tool_icon_path = File.join(plugin_dir, "na_plugin-dependencies", "80_04_--_NA_-_UTL_-_Paint-Faces-Tool-Icon_-_Vector-Graphic.png")
    framework_view_icon_path = File.join(plugin_dir, "na_plugin-dependencies", "20_01_01_-_UI-Button_-_Window-Icon.svg")
    mirror_planes_icon_path = File.join(plugin_dir, "na_plugin-dependencies", "00_31_01_-_UI-Button_-_Mirror-Icon.svg")
    profile_tracer_icon_path = File.join(plugin_dir, "na_plugin-dependencies", "20_01_00_-_UI-Button_-_Profile-Icon.svg")
    
    toolbox_cmd.small_icon = main_launcher_icon_path
    toolbox_cmd.large_icon = main_launcher_icon_path
    toolbox_cmd.tooltip = "Open Noble Architecture Toolbox"
    toolbox_cmd.status_bar_text = "Open the Noble Architecture Toolbox with all available tools"
    toolbox_cmd.menu_text = "NA | Toolbox"
    
    # Create View State command
    view_state_cmd = UI::Command.new("NA | Toggle Framework View") {
        NobleArchitectureToolbox::NA_Tools::ViewStateTool.toggle_framework_view
    }
    view_state_cmd.small_icon = framework_view_icon_path
    view_state_cmd.large_icon = framework_view_icon_path
    view_state_cmd.tooltip = "Toggle Framework Elements View"
    view_state_cmd.status_bar_text = "Toggle visibility of framework elements (20_ prefix)"
    view_state_cmd.menu_text = "NA | Toggle Framework View"
    
    # Create Mirror Planes command
    mirror_planes_cmd = UI::Command.new("NA | Toggle Mirror Planes") {
        NobleArchitectureToolbox::NA_Tools::MirrorPlanesTool.toggle_mirror_planes
    }
    mirror_planes_cmd.small_icon = mirror_planes_icon_path
    mirror_planes_cmd.large_icon = mirror_planes_icon_path
    mirror_planes_cmd.tooltip = "Toggle Mirror Planes Visibility"
    mirror_planes_cmd.status_bar_text = "Toggle visibility of 3D mirror planes (00_31_ prefix)"
    mirror_planes_cmd.menu_text = "NA | Toggle Mirror Planes"
    
    # Create Profile Path Tracer command
    profile_path_tracer_cmd = UI::Command.new("NA | Profile Path Tracer") {
        NobleArchitectureToolbox::NA_Tools::ProfilePathTracer.run
    }
    profile_path_tracer_cmd.small_icon = profile_tracer_icon_path
    profile_path_tracer_cmd.large_icon = profile_tracer_icon_path
    profile_path_tracer_cmd.tooltip = "Profile Path Tracer Tool"
    profile_path_tracer_cmd.status_bar_text = "Extrude profile components along edge paths"
    profile_path_tracer_cmd.menu_text = "NA | Profile Path Tracer"
    
    # Create Deep Paint command
    deep_paint_cmd = UI::Command.new("NA | Deep Paint Tool") {
        NobleArchitectureToolbox::NA_Tools::DeepPaintFacesTool.run
    }
    deep_paint_cmd.small_icon = paint_tool_icon_path    
    deep_paint_cmd.large_icon = paint_tool_icon_path
    deep_paint_cmd.tooltip = "NA Deep Paint Tool"
    deep_paint_cmd.menu_text = "NA | Deep Paint Tool"
    
    # Add commands to Extension menu
    UI.menu('Extensions').add_item(toolbox_cmd)
    UI.menu('Extensions').add_item(view_state_cmd)
    UI.menu('Extensions').add_item(mirror_planes_cmd)
    UI.menu('Extensions').add_item(profile_path_tracer_cmd)
    
    # Add commands to Plugins menu (appears in native hotkey dialog)
    plugins_menu = UI.menu('Plugins')
    plugins_menu.add_item(toolbox_cmd)
    plugins_menu.add_item(view_state_cmd)
    plugins_menu.add_item(mirror_planes_cmd)
    plugins_menu.add_item(profile_path_tracer_cmd)
    plugins_menu.add_item(deep_paint_cmd)
    
    # Create toolbar
    na_toolbar = UI::Toolbar.new("Noble Architecture")
    
    # Add commands to toolbar
    na_toolbar.add_item(toolbox_cmd)
    na_toolbar.add_item(view_state_cmd)
    na_toolbar.add_item(mirror_planes_cmd)
    na_toolbar.add_item(profile_path_tracer_cmd)
    na_toolbar.add_item(deep_paint_cmd)
    
    # Set default keyboard shortcuts
    # These will appear in the native SketchUp keyboard shortcuts dialog
    view_state_cmd.set_validation_proc {
        if NobleArchitectureToolbox::NA_Tools::ViewStateTool.is_framework_only?
            MF_CHECKED
        else
            MF_ENABLED
        end
    }
    
    # Set validation proc for mirror planes button
    mirror_planes_cmd.set_validation_proc {
        if NobleArchitectureToolbox::NA_Tools::MirrorPlanesTool.are_mirror_planes_hidden?
            MF_CHECKED
        else
            MF_ENABLED
        end
    }
    
    # Restore toolbar at startup
    na_toolbar.restore

    file_loaded(__FILE__)
end
# endregion


# end of file
# =====================================================================================================


