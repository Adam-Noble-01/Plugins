# =============================================================================
# VALEDESIGNSUITE - PAINT EDGES TOOL
# =============================================================================
#
# FILE       : MaterialsUtilScripts__PaintDeepNestedEdges.rb
# NAMESPACE  : ValeDesignSuite
# MODULE     : PaintDeepNestedEdges
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Edge Painting Tool for SketchUp with Color Palette Management
# CREATED    : 2025
#
# DESCRIPTION:
# - This tool provides an interactive dialog for painting SketchUp edges with predefined colors.
# - Features a curated color palette optimized for architectural linework visualization.
# - Supports recursive edge collection from groups and component instances.
# - Provides real-time selection count feedback and batch edge processing.
# - Integrates with SketchUp's material system for consistent color management.
# - Uses HTML dialog interface for modern user interaction patterns.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-Jan-2025 - Version 1.3.4
# - Fixed dialog callback references to use correct HtmlDialog instance
# - Eliminated NoMethodError for close and execute_script methods
#
# 25-Jan-2025 - Version 1.4.0  
# - Refactored to ValeDesignSuite namespace and coding conventions
# - Implemented proper regional structure and function organization
# - Enhanced color palette with architectural linework standards
# - Improved documentation and code maintainability
#
# =============================================================================

require 'sketchup'
require 'json'

module ValeDesignSuite
module PaintDeepNestedEdges

# -----------------------------------------------------------------------------
# REGION | Module Constants and Color Palette Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Extension Metadata and Version Information
    # ------------------------------------------------------------
    EXTENSION_NAME          =   'ValeDesignSuite - PaintDeepNestedEdges'.freeze                # <-- Extension display name
    EXTENSION_VERSION       =   '1.4.0'.freeze                                       # <-- Current version number
    DIALOG_PREFERENCES_KEY  =   'ValeDesignSuite_PaintDeepNestedEdges'.freeze                  # <-- Dialog preferences storage key
    # endregion ----------------------------------------------------

    # MODULE CONSTANTS | Color Palette Definition - Architectural Linework Standards
    # ------------------------------------------------------------
    PAINTDEEPNESTEDEDGES_COLOUR_JSON = <<-JSON.freeze
    {
      "Default" : "default",
      "02_01__Linework__AbsoluteBlack"       : "#000000",
      "02_02__Linework__SoftBlack__L20"      : "#333333",
      "02_03__Linework__DarkGrey__L40"       : "#666666",
      "02_04__Linework__MidGrey__L60"        : "#999999",
      "02_04__Linework__LightMidGrey__L70"   : "#B4B4B4",
      "02_05__Linework__LightGrey__L85"      : "#D9D9D9",
      "02_06__Linework__VeryLightGrey__L95"  : "#F2F2F2"
    }
    JSON

    COLOURS = JSON.parse(PAINTDEEPNESTEDEDGES_COLOUR_JSON)                                     # <-- Parsed color palette hash
    # endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Extension Registration and Menu Integration
# -----------------------------------------------------------------------------

    # EXTENSION SETUP | Register Extension with SketchUp Plugin System
    # ------------------------------------------------------------
    unless file_loaded?(__FILE__)
        submenu = UI.menu('Plugins').add_submenu(EXTENSION_NAME)                           # <-- Create plugin submenu
        command = UI::Command.new('PaintDeepNestedEdges') { self.show_dialog }             # <-- Create menu command
        command.tooltip = 'Open PaintDeepNestedEdges dialogue for edge color management'   # <-- Set command tooltip
        submenu.add_item(command)                                                          # <-- Add command to submenu
        file_loaded(__FILE__)                                                              # <-- Mark file as loaded
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Collection and Analysis Helper Functions
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Count Selected Edges for User Feedback
    # ---------------------------------------------------------------
    def self.edge_count_selection
        edges = []                                                                  # <-- Initialize edge collection array
        Sketchup.active_model.selection.each { |ent| collect_edges(ent, edges) }    # <-- Collect all edges recursively
        return edges.size                                                           # <-- Return total edge count
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Recursively Collect Edges from Entities
    # ---------------------------------------------------------------
    def self.collect_edges(entity, bucket)
        case entity
        when Sketchup::Edge
            bucket << entity                                                        # <-- Add edge to collection
        when Sketchup::Group
            entity.entities.each { |child| collect_edges(child, bucket) }          # <-- Recurse into group entities
        when Sketchup::ComponentInstance
            entity.definition.entities.each { |child| collect_edges(child, bucket) } # <-- Recurse into component definition
        else
            if entity.respond_to?(:entities)                                        # <-- Handle other entity containers
                entity.entities.each { |child| collect_edges(child, bucket) }      # <-- Recurse into container entities
            end
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Creation and Color Conversion Utilities
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Convert Hexadecimal Color to RGB Values
    # ---------------------------------------------------------------
    def self.hex_to_rgb(hex)
        hex = hex.strip.delete('#')                                                 # <-- Remove whitespace and hash symbol
        return [0, 0, 0] unless hex.length == 6                                    # <-- Return black for invalid hex
        [hex[0..1], hex[2..3], hex[4..5]].map { |c| c.to_i(16) }                  # <-- Convert hex pairs to integers
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Convert HSL Color Values to RGB
    # ---------------------------------------------------------------
    def self.hsl_to_rgb(h, s, l)
        h /= 360.0; s /= 100.0; l /= 100.0                                         # <-- Normalize HSL values
        return Array.new(3, (l*255).round) if s.zero?                              # <-- Handle grayscale colors
        
        q = l < 0.5 ? l*(1+s) : l+s-l*s                                            # <-- Calculate intermediate value q
        p = 2*l - q                                                                 # <-- Calculate intermediate value p
        r = hue_to_rgb(p, q, h + 1.0/3)                                            # <-- Calculate red component
        g = hue_to_rgb(p, q, h)                                                    # <-- Calculate green component
        b = hue_to_rgb(p, q, h - 1.0/3)                                            # <-- Calculate blue component
        
        return [(r*255).round, (g*255).round, (b*255).round]                       # <-- Return RGB integer values
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | HSL Hue Component Conversion
    # ---------------------------------------------------------------
    def self.hue_to_rgb(p, q, t)
        t += 1 if t < 0; t -= 1 if t > 1                                           # <-- Normalize hue value
        return p + (q-p)*6*t             if t < 1.0/6                              # <-- First hue sector
        return q                         if t < 1.0/2                              # <-- Second hue sector
        return p + (q-p)*(2.0/3 - t)*6   if t < 2.0/3                             # <-- Third hue sector
        return p                                                                    # <-- Fourth hue sector
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create or Retrieve Material for Color Key
    # ------------------------------------------------------------
    def self.material_for_key(model, key)
        return nil if key == 'Default'                                              # <-- Return nil for default material
        
        mat = model.materials[key]                                                  # <-- Check existing materials
        return mat if mat                                                           # <-- Return existing material if found
        
        spec = COLOURS[key]                                                         # <-- Get color specification
        rgb = spec.is_a?(String) ? hex_to_rgb(spec) : hsl_to_rgb(spec['h'], spec['s'], spec['l']) # <-- Convert to RGB
        
        mat = model.materials.add(key)                                              # <-- Create new material
        mat.color = Sketchup::Color.new(*rgb)                                      # <-- Set material color
        mat.name = key                                                              # <-- Set material name
        
        return mat                                                                  # <-- Return created material
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Edge Painting and Processing Logic
# -----------------------------------------------------------------------------

    # FUNCTION | Apply Color to Selected Edges
    # ------------------------------------------------------------
    def self.paint_edges(colour_key)
        model     = Sketchup.active_model                                           # <-- Get active SketchUp model
        selection = model.selection                                                 # <-- Get current selection
        
        if selection.empty?                                                         # <-- Validate selection exists
            UI.messagebox('Select something first.')                               # <-- Show error message
            return                                                                  # <-- Exit early if no selection
        end
        
        edges = []                                                                  # <-- Initialize edge collection
        selection.each { |ent| collect_edges(ent, edges) }                        # <-- Collect all edges from selection
        
        if edges.empty?                                                             # <-- Validate edges found
            UI.messagebox('No edges found in selection.')                          # <-- Show error message
            return                                                                  # <-- Exit early if no edges
        end
        
        model.start_operation("PaintDeepNestedEdges #{colour_key}", true)                     # <-- Start undo operation
        material = material_for_key(model, colour_key)                             # <-- Get or create material
        edges.each { |edge| edge.material = material }                            # <-- Apply material to all edges
        model.commit_operation                                                      # <-- Commit operation for undo
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | User Interface Dialog Generation and Management
# -----------------------------------------------------------------------------

    # FUNCTION | Create and Display Paint Edges Dialog
    # ------------------------------------------------------------
    def self.show_dialog
        opts = {
            dialog_title:     EXTENSION_NAME,                                       # <-- Set dialog title
            preferences_key:  DIALOG_PREFERENCES_KEY,                              # <-- Set preferences key
            scrollable:       false,                                                # <-- Disable scrolling
            resizable:        false,                                                # <-- Disable resizing
            width:            320,                                                  # <-- Set dialog width
            height:           220,                                                  # <-- Set dialog height
            style:            UI::HtmlDialog::STYLE_DIALOG                         # <-- Set dialog style
        }
        
        dlg = UI::HtmlDialog.new(opts)                                              # <-- Create HTML dialog
        
        options_html = COLOURS.keys.map { |k| "<option value=\"#{k}\">#{k}</option>" }.join # <-- Generate select options
        initial_info = "#{edge_count_selection} edges selected."                   # <-- Get initial selection count
        
        html = generate_dialog_html(options_html, initial_info)                     # <-- Generate complete HTML
        dlg.set_html(html)                                                          # <-- Set dialog HTML content
        
        setup_dialog_callbacks(dlg)                                                # <-- Configure dialog callbacks
        dlg.show                                                                    # <-- Display dialog to user
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Generate Complete HTML for Paint Edges Dialog
    # ---------------------------------------------------------------
    def self.generate_dialog_html(options_html, initial_info)
        return <<-HTML
<!DOCTYPE html>
<html>

<!-- ----------------------------------------------------------------- -->
<!-- REGION  |  User Interface HTML Layout & Elements                  -->
<!-- ----------------------------------------------------------------- -->

<head>
    <meta charset='utf-8'>
    <title>#{EXTENSION_NAME}</title>
    <style>
        /* CSS Variables - Vale Design Suite Standards */
        :root {
            --FontCol_ValeStandardTextColour   : #1e1e1e;
            --FontSize_ValeStandardText        : 14px;
            --FontSize_ValeSmallText           : 13px;
            --ValeBackgroundColor              : #ffffff;
            --ValeBorderColor                  : #cccccc;
            --ValeButtonPadding                : 6px 16px;
            --ValeButtonMargin                 : 14px 0 0 0;
        }

        /* Base Layout Styles */
        body {
            font-family                        : Arial, Helvetica, sans-serif;
            margin                             : 16px;
            color                              : var(--FontCol_ValeStandardTextColour);
            background-color                   : var(--ValeBackgroundColor);
        }

        /* Form Element Styles */
        label, select {
            font-size                          : var(--FontSize_ValeStandardText);
        }

        select {
            width                              : 280px;
            padding                            : 4px;
            border                             : 1px solid var(--ValeBorderColor);
        }

        /* Information Display Styles */
        #info {
            margin-top                         : 10px;
            font-size                          : var(--FontSize_ValeSmallText);
            color                              : #555555;
        }

        /* Button Layout and Styling */
        button {
            margin                             : var(--ValeButtonMargin);
            padding                            : var(--ValeButtonPadding);
            border                             : 1px solid var(--ValeBorderColor);
            background-color                   : var(--ValeBackgroundColor);
            cursor                             : pointer;
        }

        #btnRow {
            display                            : flex;
            gap                                : 10px;
            flex-wrap                          : wrap;
        }
    </style>
</head>

<body>
    
    <!-- ----------------------------------------------------------------- -->
    <!-- UI MENU | Color Selection and Edge Information Display             -->
    <!-- ----------------------------------------------------------------- -->
    
    <label for='colour'>Choose edge colour:</label><br>
    <select id='colour'>#{options_html}</select>
    <p id='info'>#{initial_info}</p>
    
    <!-- ----------------------------------------------------------------- -->
    <!-- UI MENU | Action Button Controls                                   -->
    <!-- ----------------------------------------------------------------- -->
    
    <div id='btnRow'>
        <button onclick='sketchup.fetch_selection()'>Refresh Selection</button>
        <button onclick='sketchup.apply_colour(document.getElementById("colour").value)'><strong>Paint Edges</strong></button>
    </div>
    
    <!-- ---------------------------------------------------------------- -->
    
    <!-- endregion ----------------------------------------------------------------- -->

</body>
</html>
        HTML
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Configure Dialog Callbacks for User Interaction
    # ---------------------------------------------------------------
    def self.setup_dialog_callbacks(dlg)
        # Apply colour callback - paint selected edges with chosen color
        dlg.add_action_callback('apply_colour') do |_ctx, key|
            self.paint_edges(key)                                                   # <-- Apply color to edges
            dlg.close                                                               # <-- Close dialog after painting
        end
        
        # Refresh selection count callback - update edge count display
        dlg.add_action_callback('fetch_selection') do |_ctx, _|
            count = edge_count_selection                                            # <-- Get current edge count
            dlg.execute_script("document.getElementById('info').textContent='#{count} edges selected.';") # <-- Update display
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module PaintDeepNestedEdges
end # module ValeDesignSuite

# =============================================================================
# USAGE INSTRUCTIONS
# =============================================================================
#
# MENU ACCESS:
# - Navigate to Plugins → ValeDesignSuite - PaintDeepNestedEdges
# - Dialog will open showing available color options
#
# WORKFLOW:
# 1. Select edges, groups, or components containing edges in SketchUp
# 2. Choose desired color from dropdown menu
# 3. Click "Paint Edges" to apply color to all edges in selection
# 4. Use "Refresh Selection" to update edge count after changing selection
#
# KEYBOARD SHORTCUT:
# - Bind shortcut via: Window → Preferences → Shortcuts → search 'PaintDeepNestedEdges'
#
# =============================================================================
