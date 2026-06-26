# =============================================================================
# VALEDESIGNSUITE - WATERCOLOR PEN AND WASH RENDERING TOOL
# =============================================================================
#
# FILE       : ValeDesignSuite_RenderingTools__WatercolourRenderer.rb
# NAMESPACE  : ValeDesignSuite
# MODULE     : WatercolourRenderingTools
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Transform SketchUp views into watercolor pen and wash illustrations
# CREATED    : 2025
#
# DESCRIPTION:
# - Captures the current SketchUp view and applies artistic watercolor rendering
# - Creates authentic pen and wash style illustrations from 3D models
# - Uses advanced Kuwahara filtering with multiple painterly effects
# - Preserves original linework through multiply blend mode overlay
# - Simulates traditional watercolor techniques: bleeding, pooling, wet edges
# - Provides extensive customization through configuration parameters
# - Supports architectural illustration and artistic rendering workflows
#
# AESTHETIC INTENT:
# The tool aims to replicate the traditional architectural rendering technique
# of "pen and wash" - where ink line drawings are enhanced with watercolor
# washes. This creates illustrations that maintain technical precision through
# the pen lines while adding atmospheric depth and artistic quality through
# the watercolor effects. The result bridges the gap between technical drawings
# and artistic illustrations, suitable for presentation drawings, concept art,
# and architectural visualization.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 08-Jul-2025 - Version 1.1.0
# - Initial release with basic Kuwahara filter
#
# 09-Jul-2025 - Version 1.2.0
# - Complete rewrite following ValeDesignSuite conventions
# - Added configuration-driven development approach
# - Enhanced with multiple watercolor effects and parameters
# - Added pen overlay with multiply blend mode
# - Implemented color bleeding and wet edge effects
# - Added paper texture simulation
# - Created preset system for quick styling
#
# 10-Jul-2025 - Version 1.3.0
# - Added flexible image capture system with aspect ratio controls
# - Implemented canvas navigation tools (zoom, pan)
# - Enhanced UI with width input and aspect ratio toggles
# - Added refresh functionality for re-capturing SketchUp views
# - Removed side-by-side comparison feature
# - Organized code into clear functional regions
# - Added HTML dialog for improved user interaction
# - Implemented modern HTML dialog communication
# - Added save image functionality
# - Added update config functionality
# - Added refresh functionality
# - Added legacy capture functionality
# - Added open watercolor dialog functionality
#
# =============================================================================

require 'sketchup'
require 'extensions'
require 'json'
require 'base64'
require 'tmpdir'

module ValeDesignSuite
    module WatercolourRenderingTools

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | File Paths and Plugin Identity
    # ------------------------------------------------------------
    PLUGIN_ID               =   'vds_watercolor_renderer'                     # <-- Unique plugin identifier
    PLUGIN_NAME             =   'Watercolor Pen & Wash Renderer'              # <-- Display name
    PLUGIN_VERSION          =   '2.1.0'                                       # <-- Current version
    CONFIG_FILE_NAME        =   'ValeDesignSuite_RenderingTools__WatercolorConfig.json'  # <-- Configuration file
    CONFIG_FILE_PATH        =   File.join(File.dirname(__FILE__), CONFIG_FILE_NAME)      # <-- Full config path
    # ------------------------------------------------------------

    # MODULE VARIABLES | Configuration State
    # ------------------------------------------------------------
    @@config                =   nil                                           # <-- Loaded configuration
    @@original_image_data   =   nil                                           # <-- Store original for blending
    @@dialog                =   nil                                           # <-- HTML dialog reference
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Management
# -----------------------------------------------------------------------------

    # FUNCTION | Load Configuration from JSON File
    # ------------------------------------------------------------
    def self.load_configuration
        begin
            if File.exist?(CONFIG_FILE_PATH)
                config_content = File.read(CONFIG_FILE_PATH)                  # Read configuration file
                @@config = JSON.parse(config_content)                        # Parse JSON content
                puts "✅ Watercolor config loaded from: #{CONFIG_FILE_PATH}"
                return true
            else
                @@config = default_configuration                              # Use default if file missing
                puts "🔧 Using default watercolor configuration"
                return false
            end
        rescue => e
            puts "❌ Config error: #{e.message}"
            @@config = default_configuration                                  # Fallback to defaults
            return false
        end
    end
    # ------------------------------------------------------------

    # FUNCTION | Get Configuration Value by Key Path
    # ------------------------------------------------------------
    def self.get_config_value(key_path, default_value = nil)
        keys = key_path.split('.')                                           # Split path into keys
        value = @@config
        
        begin
            keys.each { |key| value = value[key] }                           # Navigate nested structure
            return value
        rescue
            return default_value                                              # Return default if key missing
        end
    end
    # ------------------------------------------------------------

    # FUNCTION | Provide Default Configuration Structure
    # ------------------------------------------------------------
    def self.default_configuration
        {
            "image_capture" => {
                "width" => 2048,
                "aspect_ratio" => "4:3",
                "dpi" => 150,
                "antialias" => true,
                "compression" => 0.9
            },
            "rendering_defaults" => {
                "kuwahara_filter" => {
                    "enabled" => true,
                    "radius" => 6,
                    "min_radius" => 1,
                    "max_radius" => 20,
                    "multiple_passes" => 4
                },
                "pen_overlay" => {
                    "enabled" => true,
                    "blend_mode" => "multiply",
                    "line_opacity" => 0.75
                },
                "watercolor_effects" => {
                    "color_bleeding" => {
                        "enabled" => true,
                        "intensity" => 0.3,
                        "spread_radius" => 8,
                        "wet_edge_intensity" => 0.2
                    },
                    "paper_texture" => {
                        "enabled" => true,
                        "texture_strength" => 0.6,
                        "roughness" => 0.7,
                        "grain_size" => "medium"
                    },
                    "color_vibrancy" => {
                        "saturation_boost" => 0.75,
                        "brightness_adjustment" => 1.15,
                        "contrast_enhancement" => 0.95
                    }
                }
            },
            "ui_settings" => {
                "dialog_width" => 1400,
                "dialog_height" => 900
            },
            "navigation" => {
                "zoom_sensitivity" => 0.1,
                "pan_sensitivity" => 1.0,
                "max_zoom" => 5.0,
                "min_zoom" => 0.1
            },
            "presets" => {
                "delicate_wash" => {
                    "kuwahara_radius" => 6,
                    "filter_passes" => 4,
                    "color_bleeding_intensity" => 0.3,
                    "pen_overlay_opacity" => 0.75,
                    "paper_texture_strength" => 0.6,
                    "saturation_boost" => 0.75,
                    "wet_edge_intensity" => 0.2,
                    "brightness" => 1.15
                },
                "bold_illustration" => {
                    "kuwahara_radius" => 5,
                    "color_bleeding_intensity" => 0.25,
                    "pen_overlay_opacity" => 0.85,
                    "paper_texture_strength" => 0.15,
                    "saturation_boost" => 0.8,
                    "wet_edge_intensity" => 0.5,
                    "brightness" => 1.15,
                    "filter_passes" => 2
                },
                "loose_sketch" => {
                    "kuwahara_radius" => 6,
                    "color_bleeding_intensity" => 0.35,
                    "pen_overlay_opacity" => 0.6,
                    "paper_texture_strength" => 0.20,
                    "saturation_boost" => 0.6,
                    "wet_edge_intensity" => 0.7,
                    "brightness" => 1.05,
                    "filter_passes" => 3
                }
            }
        }
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main Entry Point and Activation
# -----------------------------------------------------------------------------

    # FUNCTION | Activate the Watercolor Rendering Tool
    # ------------------------------------------------------------
    def self.activate
        puts "\n=== Watercolor Tool Activating ==="
        
        load_configuration                                                    # Load config first
        
        puts "Capturing SketchUp view..."
        image_path = capture_sketchup_view                                   # Capture current view
        
        if image_path
            puts "View captured to: #{image_path}"
            open_watercolor_dialog(image_path)                                # Open processing dialog
        else
            puts "Failed to capture view"
            UI.messagebox("Failed to capture SketchUp view")
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Image Capture Configuration and Management
# -----------------------------------------------------------------------------

    # FUNCTION | Calculate Height from Width and Aspect Ratio
    # ------------------------------------------------------------
    def self.calculate_height_from_aspect_ratio(width, aspect_ratio)
        case aspect_ratio
        when "3:2"
            return (width / 3.0 * 2.0).round                                 # 3:2 aspect ratio
        when "4:3"
            return (width / 4.0 * 3.0).round                                 # 4:3 aspect ratio
        when "16:9"
            return (width / 16.0 * 9.0).round                                # 16:9 aspect ratio
        else
            return (width / 4.0 * 3.0).round                                 # Default to 4:3
        end
    end
    # ------------------------------------------------------------

    # FUNCTION | Capture Current SketchUp View with New Configuration
    # ------------------------------------------------------------
    def self.capture_sketchup_view(custom_width = nil, custom_aspect = nil)
        temp_path = File.join(Dir.tmpdir, 'vds_watercolor_capture.png')      # Temporary file path
        
        # Get capture parameters
        width = custom_width || get_config_value('image_capture.width', 2048)
        aspect_ratio = custom_aspect || get_config_value('image_capture.aspect_ratio', '4:3')
        height = calculate_height_from_aspect_ratio(width, aspect_ratio)
        
        puts "Capturing at #{width}x#{height} (#{aspect_ratio}) @ 150 DPI"
        
        success = Sketchup.active_model.active_view.write_image(
            filename:   temp_path,
            width:      width,
            height:     height,
            antialias:  get_config_value('image_capture.antialias', true),
            compression: get_config_value('image_capture.compression', 0.9)
        )
        
        success ? temp_path : nil                                             # Return path or nil
    end
    # ------------------------------------------------------------

    # FUNCTION | Refresh SketchUp Image Capture
    # ------------------------------------------------------------
    def self.refresh_sketchup_capture(width, aspect_ratio)
        puts "Refreshing capture with #{width}x#{aspect_ratio}..."
        
        new_image_path = capture_sketchup_view(width, aspect_ratio)           # Capture with new settings
        
        if new_image_path && @@dialog
            # Convert new image to data URL
            new_image_data_url = convert_image_to_data_url(new_image_path)   # Convert to data URL
            
            if new_image_data_url
                # Update dialog with new image data URL
                escaped_data_url = new_image_data_url.gsub("'", "\\'")       # Escape single quotes
                script = "refreshCanvasWithNewImage('#{escaped_data_url}');"
                @@dialog.execute_script(script)
                puts "✅ Canvas refreshed with new capture"
            else
                puts "❌ Failed to convert image to data URL"
            end
        else
            puts "❌ Failed to refresh capture"
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp View Capture
# -----------------------------------------------------------------------------

    # FUNCTION | Legacy Capture Function (Redirects to New System)
    # ------------------------------------------------------------
    def self.capture_sketchup_view_legacy
        capture_sketchup_view                                                 # Use new enhanced capture system
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Dialog Creation and Management
# -----------------------------------------------------------------------------

    # FUNCTION | Open HTML Dialog for Watercolor Processing
    # ------------------------------------------------------------
    def self.open_watercolor_dialog(image_path)
        dialog_width = get_config_value('ui_settings.dialog_width', 1200)
        dialog_height = get_config_value('ui_settings.dialog_height', 800)
        
        @@dialog = UI::HtmlDialog.new(
            dialog_title:    PLUGIN_NAME,
            preferences_key: PLUGIN_ID,
            scrollable:      true,
            resizable:       true,
            width:           dialog_width,
            height:          dialog_height
        )
        
        html_content = generate_html_content(image_path)                      # Generate HTML with image
        @@dialog.set_html(html_content)                                       # Set dialog content
        
        setup_dialog_callbacks                                                # Setup Ruby callbacks
        
        @@dialog.show                                                         # Display dialog
    end
    # ------------------------------------------------------------

    # FUNCTION | Setup Dialog Action Callbacks
    # ------------------------------------------------------------
    def self.setup_dialog_callbacks
        @@dialog.add_action_callback('save_image') do |_, data_url|
            save_watercolor_image(data_url)                                   # Save processed image
        end
        
        @@dialog.add_action_callback('update_config') do |_, config_data|
            update_runtime_config(config_data)                                # Update config values
        end
        
        @@dialog.add_action_callback('load_preset') do |_, preset_name|
            apply_preset_configuration(preset_name)                           # Apply preset settings
        end
        
        @@dialog.add_action_callback('refresh_capture') do |_, params|
            width = params['width'].to_i
            aspect_ratio = params['aspect_ratio']
            refresh_sketchup_capture(width, aspect_ratio)                     # Refresh with new settings
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Content Generation
# -----------------------------------------------------------------------------

    # FUNCTION | Convert Image File to Base64 Data URL
    # ------------------------------------------------------------
    def self.convert_image_to_data_url(image_path)
        begin
            image_data = File.binread(image_path)                            # Read binary image data
            base64_data = Base64.strict_encode64(image_data)                 # Encode to base64 without newlines
            return "data:image/png;base64,#{base64_data}"                    # Return data URL
        rescue => e
            puts "Error converting image to data URL: #{e.message}"
            return nil
        end
    end
    # ------------------------------------------------------------

    # FUNCTION | Generate Complete HTML Content for Dialog
    # ------------------------------------------------------------
    def self.generate_html_content(image_path)
        # Convert image to base64 data URL for reliable loading
        image_data_url = convert_image_to_data_url(image_path)               # Convert to data URL
        config_json = @@config.to_json                                        # Convert config to JSON
        
        # Get paper texture path and convert to data URL
        plugin_root = File.expand_path(File.dirname(__FILE__))               # Get absolute path to watercolor tool directory  
        paper_texture_path = File.join(plugin_root, '01_PluginAssets', 'WaterColour__MaterialCompLayer__Var01.png')
        paper_texture_data_url = convert_image_to_data_url(paper_texture_path) # Convert texture to data URL
        
        puts "Image converted to data URL successfully"                       # Debug output
        puts "Paper texture converted to data URL"                            # Debug texture status
        
        <<~HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>#{PLUGIN_NAME}</title>
    <style>
        #{generate_css_styles}
    </style>
</head>
<body>
    #{generate_html_structure}
    
    <script>
        // TEST AND DEBUG
        console.log('Script starting...');
        console.log('CONFIG:', #{config_json});
        console.log('Image data URL loaded');
        console.log('Texture data URL loaded');
        
        const CONFIG = #{config_json};
        const IMAGE_DATA_URL = `#{image_data_url}`;
        const PAPER_TEXTURE_DATA_URL = `#{paper_texture_data_url || ''}`;
        
        // Add error handler
        window.onerror = function(msg, url, lineNo, columnNo, error) {
            console.error('JavaScript Error:', msg, 'at line', lineNo);
            console.error('Stack:', error ? error.stack : 'No stack trace');
            return false;
        };
        
        #{generate_javascript_code(config_json, image_data_url, paper_texture_data_url)}
    </script>
</body>
</html>
        HTML
    end
    # ------------------------------------------------------------

    # FUNCTION | Generate CSS Styles for Dialog
    # ------------------------------------------------------------
    def self.generate_css_styles
        <<~CSS
        /* CSS Variables - Vale Design Suite Watercolor Tool */
        :root {
            --FontCol_ValeTitleTextColour      : #172b3a;
            --FontCol_ValeStandardTextColour   : #1e1e1e;
            --ValeBackgroundColor              : #f5f5f5;
            --ValeAccentColor                  : #4a90e2;
            --ValeBorderColor                  : #d0d0d0;
            --ValeControlBackground            : #ffffff;
            --ValeSliderTrack                  : #e0e0e0;
            --ValeSliderThumb                  : #4a90e2;
            --ValeWarningColor                 : #f39c12;
            --ValeSuccessColor                 : #27ae60;
        }
        
        /* Base Layout Styles */
        * {
            box-sizing                         : border-box;
        }
        
        html, body {
            margin                             : 0;
            padding                            : 0;
            font-family                        : 'Open Sans', Arial, sans-serif;
            font-size                          : 14px;
            color                              : var(--FontCol_ValeStandardTextColour);
            background-color                   : var(--ValeBackgroundColor);
            height                             : 100vh;
            overflow                           : hidden;
        }
        
        /* Main Container Layout */
        .main-container {
            display                            : flex;
            height                             : 100vh;
            overflow                           : hidden;
        }
        
        /* Control Panel Styles */
        .control-panel {
            width                              : 350px;
            background                         : var(--ValeControlBackground);
            border-right                       : 1px solid var(--ValeBorderColor);
            overflow-y                         : auto;
            padding                            : 20px;
        }
        
        .control-section {
            margin-bottom                      : 20px;
            padding-bottom                     : 20px;
            border-bottom                      : 1px solid var(--ValeBorderColor);
        }
        
        .section-title {
            font-size                          : 16px;
            font-weight                        : 600;
            color                              : var(--FontCol_ValeTitleTextColour);
            margin-bottom                      : 12px;
        }
        
        /* Canvas Container */
        .canvas-container {
            flex                               : 1;
            display                            : flex;
            align-items                        : center;
            justify-content                    : center;
            overflow                           : hidden;
            background                         : #e8e8e8;
            position                           : relative;
            cursor                             : grab;
        }
        
        .canvas-container.panning {
            cursor                             : grabbing;
        }
        
        .canvas-wrapper {
            position                           : relative;
            transition                         : transform 0.1s ease-out;
            transform-origin                   : center center;
        }
        
        canvas {
            display                            : block;
            box-shadow                         : 0 4px 8px rgba(0,0,0,0.1);
            image-rendering                    : auto;
            user-select                        : none;
        }
        
        /* Navigation Info */
        .navigation-info {
            position                           : absolute;
            top                                : 10px;
            left                               : 10px;
            background                         : rgba(0,0,0,0.7);
            color                              : white;
            padding                            : 8px 12px;
            border-radius                      : 4px;
            font-size                          : 12px;
            font-family                        : monospace;
            pointer-events                     : none;
            opacity                            : 0;
            transition                         : opacity 0.3s;
        }
        
        .navigation-info.visible {
            opacity                            : 1;
        }
        
        /* Form Controls */
        .control-group {
            margin-bottom                      : 12px;
        }
        
        .control-row {
            display                            : flex;
            align-items                        : center;
            gap                                : 8px;
            margin-bottom                      : 8px;
        }
        
        label {
            display                            : block;
            margin-bottom                      : 4px;
            font-size                          : 13px;
            color                              : #555;
        }
        
        input[type="range"] {
            width                              : 100%;
            height                             : 6px;
            background                         : var(--ValeSliderTrack);
            outline                            : none;
            -webkit-appearance                 : none;
            appearance                         : none;
            border-radius                      : 3px;
        }
        
        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance                 : none;
            appearance                         : none;
            width                              : 16px;
            height                             : 16px;
            background                         : var(--ValeSliderThumb);
            cursor                             : pointer;
            border-radius                      : 50%;
        }
        
        input[type="number"] {
            width                              : 80px;
            padding                            : 6px 8px;
            border                             : 1px solid var(--ValeBorderColor);
            border-radius                      : 4px;
            font-size                          : 14px;
        }
        
        .value-display {
            display                            : inline-block;
            min-width                          : 40px;
            text-align                         : right;
            font-weight                        : 600;
            color                              : var(--ValeAccentColor);
        }
        
        /* Aspect Ratio Toggles */
        .aspect-ratio-toggles {
            display                            : flex;
            gap                                : 4px;
            margin-top                         : 8px;
        }
        
        .aspect-toggle {
            flex                               : 1;
            padding                            : 6px 8px;
            font-size                          : 12px;
            background                         : #f0f0f0;
            color                              : #333;
            border                             : 1px solid var(--ValeBorderColor);
            border-radius                      : 4px;
            cursor                             : pointer;
            transition                         : all 0.2s;
        }
        
        .aspect-toggle.active {
            background                         : var(--ValeAccentColor);
            color                              : white;
            border-color                       : var(--ValeAccentColor);
        }
        
        .aspect-toggle:hover:not(.active) {
            background                         : #e0e0e0;
        }
        
        /* Buttons */
        button {
            background                         : var(--ValeAccentColor);
            color                              : white;
            border                             : none;
            padding                            : 8px 16px;
            border-radius                      : 4px;
            cursor                             : pointer;
            font-size                          : 14px;
            transition                         : background 0.2s;
        }
        
        button:hover {
            background                         : #357abd;
        }
        
        button:active {
            transform                          : translateY(1px);
        }
        
        button.refresh-button {
            background                         : var(--ValeSuccessColor);
            font-size                          : 13px;
            padding                            : 6px 12px;
        }
        
        button.refresh-button:hover {
            background                         : #229954;
        }
        
        .button-group {
            display                            : flex;
            gap                                : 8px;
            margin-top                         : 16px;
        }
        
        .button-group button {
            flex                               : 1;
        }
        
        /* Toggle Switch */
        .toggle-switch {
            position                           : relative;
            display                            : inline-block;
            width                              : 44px;
            height                             : 24px;
        }
        
        .toggle-switch input {
            opacity                            : 0;
            width                              : 0;
            height                             : 0;
        }
        
        .toggle-slider {
            position                           : absolute;
            cursor                             : pointer;
            top                                : 0;
            left                               : 0;
            right                              : 0;
            bottom                             : 0;
            background-color                   : #ccc;
            transition                         : .4s;
            border-radius                      : 24px;
        }
        
        .toggle-slider:before {
            position                           : absolute;
            content                            : "";
            height                             : 18px;
            width                              : 18px;
            left                               : 3px;
            bottom                             : 3px;
            background-color                   : white;
            transition                         : .4s;
            border-radius                      : 50%;
        }
        
        input:checked + .toggle-slider {
            background-color                   : var(--ValeAccentColor);
        }
        
        input:checked + .toggle-slider:before {
            transform                          : translateX(20px);
        }
        
        /* Preset Buttons */
        .preset-buttons {
            display                            : grid;
            grid-template-columns              : repeat(2, 1fr);
            gap                                : 8px;
            margin-top                         : 12px;
        }
        
        .preset-button {
            padding                            : 6px 12px;
            font-size                          : 12px;
            background                         : #f0f0f0;
            color                              : #333;
        }
        
        .preset-button:hover {
            background                         : #e0e0e0;
        }
        CSS
    end
    # ------------------------------------------------------------

    # FUNCTION | Generate HTML Structure for Dialog
    # ------------------------------------------------------------
    def self.generate_html_structure
        <<~HTML
        <!-- ----------------------------------------------------------------- -->
        <!-- REGION  |  Main Container Layout                                  -->
        <!-- ----------------------------------------------------------------- -->
        <div class="main-container">
            
            <!-- ----------------------------------------------------------------- -->
            <!-- UI MENU | Control Panel with Parameters                           -->
            <!-- ----------------------------------------------------------------- -->
            <div class="control-panel">
                <h2 style="margin-top: 0;">Watercolor Parameters</h2>
                
                <!-- Image Capture Section -->
                <div class="control-section">
                    <div class="section-title">Image Capture</div>
                    <div class="control-group">
                        <label>Width (pixels):</label>
                        <div class="control-row">
                            <input type="number" id="image-width" value="2048" min="512" max="8192" step="1">
                            <span style="font-size: 12px; color: #666;">px @ 150 DPI</span>
                        </div>
                    </div>
                    <div class="control-group">
                        <label>Aspect Ratio:</label>
                        <div class="aspect-ratio-toggles">
                            <div class="aspect-toggle" data-ratio="3:2">3:2</div>
                            <div class="aspect-toggle active" data-ratio="4:3">4:3</div>
                            <div class="aspect-toggle" data-ratio="16:9">16:9</div>
                        </div>
                    </div>
                    <div class="control-group">
                        <label>Calculated Height: <span class="value-display" id="calculated-height">1536</span> px</label>
                        <button class="refresh-button" onclick="refreshSketchUpCapture()" style="margin-top: 8px; width: 100%;">
                            🔄 Refresh Canvas
                        </button>
                    </div>
                </div>
                
                <!-- Presets Section -->
                <div class="control-section">
                    <div class="section-title">Quick Presets</div>
                    <div class="preset-buttons">
                        <button class="preset-button" onclick="loadPreset('delicate_wash')">Delicate Wash</button>
                        <button class="preset-button" onclick="loadPreset('bold_illustration')">Bold Illustration</button>
                        <button class="preset-button" onclick="loadPreset('loose_sketch')">Loose Sketch</button>
                        <button class="preset-button" onclick="resetToDefaults()">Reset Defaults</button>
                    </div>
                </div>
                
                
                <!-- Kuwahara Filter Section -->
                <div class="control-section">
                    <div class="section-title">Paint Strokes</div>
                    <div class="control-group">
                        <label>
                            Brush Size: <span class="value-display" id="radius-value">4</span>
                        </label>
                        <input type="range" id="kuwahara-radius" min="1" max="20" value="4">
                    </div>
                    <div class="control-group">
                        <label>
                            Multiple Passes: <span class="value-display" id="passes-value">2</span>
                        </label>
                        <input type="range" id="filter-passes" min="1" max="5" value="2">
                    </div>
                </div>
                
                <!-- Watercolor Effects Section -->
                <div class="control-section">
                    <div class="section-title">Watercolor Effects</div>
                    <div class="control-group">
                        <label>
                            Color Bleeding: <span class="value-display" id="bleeding-value">30%</span>
                        </label>
                        <input type="range" id="color-bleeding" min="0" max="100" value="30">
                    </div>
                    <div class="control-group">
                        <label>
                            Wet Edges: <span class="value-display" id="wet-edge-value">50%</span>
                        </label>
                        <input type="range" id="wet-edge" min="0" max="100" value="50">
                    </div>
                    <div class="control-group">
                        <label>
                            Paper Texture Overlay: <span class="value-display" id="texture-value">15%</span>
                        </label>
                        <input type="range" id="paper-texture" min="0" max="100" value="15">
                        <div style="font-size: 11px; color: #666; margin-top: 2px;">
                            Multiplies seamless paper texture on top
                        </div>
                    </div>
                </div>
                
                <!-- Pen Overlay Section -->
                <div class="control-section">
                    <div class="section-title">Pen Line Overlay</div>
                    <div class="control-group">
                        <label style="display: flex; align-items: center; gap: 8px;">
                            Enable Pen Lines:
                            <span class="toggle-switch">
                                <input type="checkbox" id="pen-overlay-toggle" checked>
                                <span class="toggle-slider"></span>
                            </span>
                        </label>
                    </div>
                    <div class="control-group">
                        <label>
                            Line Opacity: <span class="value-display" id="line-opacity-value">80%</span>
                        </label>
                        <input type="range" id="line-opacity" min="0" max="100" value="80">
                    </div>
                    <div class="control-group">
                        <label>
                            Edge Detection: <span class="value-display" id="edge-threshold-value">5%</span>
                        </label>
                        <input type="range" id="edge-threshold" min="0" max="30" value="5">
                    </div>
                </div>
                
                <!-- Color Adjustments Section -->
                <div class="control-section">
                    <div class="section-title">Color Adjustments</div>
                    <div class="control-group">
                        <label>
                            Saturation: <span class="value-display" id="saturation-value">75%</span>
                        </label>
                        <input type="range" id="saturation" min="30" max="150" value="75">
                    </div>
                    <div class="control-group">
                        <label>
                            Brightness: <span class="value-display" id="brightness-value">115%</span>
                        </label>
                        <input type="range" id="brightness" min="50" max="150" value="115">
                    </div>
                </div>

                <!-- View Controls Section -->
                <div class="control-section">
                    <div class="section-title">View Controls</div>
                    <div class="control-group">
                        <label style="display: flex; align-items: center; gap: 8px;">
                            Show Processed Image:
                            <span class="toggle-switch">
                                <input type="checkbox" id="preview-toggle" checked>
                                <span class="toggle-slider"></span>
                            </span>
                        </label>
                        <div style="font-size: 11px; color: #666; margin-top: 2px;">
                            Toggle OFF to see original SketchUp image
                        </div>
                    </div>
                    <div style="font-size: 11px; color: #666; margin-top: 8px;">
                        <strong>Navigation:</strong><br>
                        • Mouse wheel: Zoom in/out<br>
                        • Right-click + drag: Pan image<br>
                        • Middle-click + drag: Pan image
                    </div>
                </div>

                
                <!-- Action Buttons -->
                <div class="button-group">
                    <button id="apply-filter" onclick="applyWatercolorEffect()">Apply Effect</button>
                    <button id="save-image" onclick="saveWatercolorImage()">Save Image</button>
                </div>
            </div>
            <!-- ---------------------------------------------------------------- -->
            
            <!-- ----------------------------------------------------------------- -->
            <!-- UI MENU | Canvas Display Area with Navigation                     -->
            <!-- ----------------------------------------------------------------- -->
            <div class="canvas-container" id="canvas-container">
                <div class="navigation-info" id="navigation-info">
                    Zoom: 100% | Pan: 0, 0
                </div>
                <div class="canvas-wrapper" id="canvas-wrapper">
                    <canvas id="main-canvas"></canvas>
                </div>
            </div>
            <!-- ---------------------------------------------------------------- -->
            
        </div>
        <!-- endregion ------------------------------------------------------------ -->
        HTML
    end
    # ------------------------------------------------------------

    # FUNCTION | Generate JavaScript Code for Watercolor Processing
    # ------------------------------------------------------------
    def self.generate_javascript_code(config_json, image_data_url, paper_texture_data_url)
        <<~JS
        // -----------------------------------------------------------------------------
        // REGION | Configuration and Initialization
        // -----------------------------------------------------------------------------
        
            // MODULE VARIABLES | Canvas and Image State
            // ------------------------------------------------------------
            let canvas              = document.getElementById('main-canvas');        // <-- Main canvas element
            let ctx                 = canvas.getContext('2d');                       // <-- 2D rendering context
            let originalImage       = new Image();                                   // <-- Original SketchUp image
            let paperTexture        = new Image();                                   // <-- Paper texture image
            let paperTextureLoaded  = false;                                         // <-- Paper texture load state
            let originalImageData   = null;                                          // <-- Original pixel data (immutable)
            let processedImageData  = null;                                          // <-- Current processed data
            let isShowingProcessed  = true;                                          // <-- Toggle state for preview
            let currentImageDataURL = IMAGE_DATA_URL;                                // <-- Current image data URL
            // ------------------------------------------------------------
            
        // endregion -------------------------------------------------------------------
        
        // -----------------------------------------------------------------------------
        // REGION | Image Capture Configuration and Canvas Management
        // -----------------------------------------------------------------------------
        
            // MODULE VARIABLES | Image Capture Settings
            // ------------------------------------------------------------
            let currentWidth        = 2048;                                          // <-- Current image width
            let currentAspectRatio  = '4:3';                                         // <-- Current aspect ratio
            let currentHeight       = 1536;                                          // <-- Calculated height
            // ------------------------------------------------------------
            
            
            // FUNCTION | Calculate Height from Width and Aspect Ratio
            // ------------------------------------------------------------
            function calculateHeight(width, aspectRatio) {
                switch(aspectRatio) {
                    case '3:2':  return Math.round(width / 3 * 2);                   // <-- 3:2 aspect ratio
                    case '4:3':  return Math.round(width / 4 * 3);                   // <-- 4:3 aspect ratio  
                    case '16:9': return Math.round(width / 16 * 9);                  // <-- 16:9 aspect ratio
                    default:     return Math.round(width / 4 * 3);                   // <-- Default to 4:3
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Update Height Display
            // ------------------------------------------------------------
            function updateHeightDisplay() {
                currentHeight = calculateHeight(currentWidth, currentAspectRatio);   // <-- Calculate new height
                document.getElementById('calculated-height').textContent = currentHeight; // <-- Update display
                console.log(`Image dimensions: ${currentWidth}x${currentHeight} (${currentAspectRatio})`);
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Setup Image Capture Controls
            // ------------------------------------------------------------
            function setupImageCaptureControls() {
                // WIDTH INPUT HANDLER
                const widthInput = document.getElementById('image-width');           // <-- Get width input
                widthInput.addEventListener('input', function() {
                    currentWidth = parseInt(this.value) || 2048;                    // <-- Update current width
                    updateHeightDisplay();                                           // <-- Recalculate height
                });
                
                // ASPECT RATIO TOGGLE HANDLERS
                const aspectToggles = document.querySelectorAll('.aspect-toggle');   // <-- Get all aspect toggles
                aspectToggles.forEach(toggle => {
                    toggle.addEventListener('click', function() {
                        // REMOVE ACTIVE CLASS FROM ALL TOGGLES
                        aspectToggles.forEach(t => t.classList.remove('active'));    // <-- Clear active states
                        
                        // ADD ACTIVE CLASS TO CLICKED TOGGLE
                        this.classList.add('active');                               // <-- Set new active state
                        currentAspectRatio = this.dataset.ratio;                    // <-- Update aspect ratio
                        updateHeightDisplay();                                       // <-- Recalculate height
                    });
                });
                
                // INITIALIZE HEIGHT DISPLAY
                updateHeightDisplay();                                               // <-- Set initial height
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Refresh SketchUp Capture with New Settings
            // ------------------------------------------------------------
            function refreshSketchUpCapture() {
                console.log(`Refreshing capture: ${currentWidth}x${currentHeight} (${currentAspectRatio})`);
                
                // SEND REFRESH REQUEST TO RUBY
                window.location = 'skp:refresh_capture@' + JSON.stringify({
                    width: currentWidth,
                    aspect_ratio: currentAspectRatio
                });
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Refresh Canvas with New Image (Called from Ruby)
            // ------------------------------------------------------------
            function refreshCanvasWithNewImage(newImageDataURL) {
                console.log('Refreshing canvas with new image data URL');
                
                currentImageDataURL = newImageDataURL;                               // <-- Update current data URL
                
                // LOAD NEW IMAGE
                const newImage = new Image();
                newImage.onload = function() {
                    console.log('New image loaded:', newImage.width + 'x' + newImage.height);
                    
                    // UPDATE CANVAS SIZE AND CONTENT
                    canvas.width = newImage.width;                                   // <-- Set new canvas dimensions
                    canvas.height = newImage.height;
                    ctx.drawImage(newImage, 0, 0);                                   // <-- Draw new image
                    
                    // UPDATE IMAGE DATA
                    originalImageData = ctx.getImageData(0, 0, canvas.width, canvas.height); // <-- Store new original
                    processedImageData = new ImageData(new Uint8ClampedArray(originalImageData.data), originalImageData.width, originalImageData.height); // <-- Reset processed
                    
                    // RESET NAVIGATION
                    resetCanvasNavigation();                                         // <-- Reset zoom and pan
                    
                    console.log('✅ Canvas refreshed successfully');
                };
                
                newImage.onerror = function() {
                    console.error('Failed to load new image');
                };
                
                newImage.src = newImageDataURL;                                      // <-- Load from data URL
            }
            // ------------------------------------------------------------
            
        // endregion -------------------------------------------------------------------
        
        // -----------------------------------------------------------------------------
        // REGION | Canvas Navigation Tools (Zoom and Pan)
        // -----------------------------------------------------------------------------
        
            // MODULE VARIABLES | Navigation State
            // ------------------------------------------------------------
            let currentZoom         = 1.0;                                           // <-- Current zoom level
            let currentPanX         = 0;                                             // <-- Current pan X offset
            let currentPanY         = 0;                                             // <-- Current pan Y offset
            let isPanning           = false;                                         // <-- Pan drag state
            let lastPanX            = 0;                                             // <-- Last pan mouse X
            let lastPanY            = 0;                                             // <-- Last pan mouse Y
            const maxZoom           = 5.0;                                           // <-- Maximum zoom level
            const minZoom           = 0.1;                                           // <-- Minimum zoom level
            const zoomSensitivity   = 0.001;                                        // <-- Zoom wheel sensitivity
            // ------------------------------------------------------------
            
            
            // FUNCTION | Update Canvas Transform
            // ------------------------------------------------------------
            function updateCanvasTransform() {
                const wrapper = document.getElementById('canvas-wrapper');           // <-- Get canvas wrapper
                const transform = `translate(${currentPanX}px, ${currentPanY}px) scale(${currentZoom})`;
                wrapper.style.transform = transform;                                // <-- Apply transform
                
                // UPDATE NAVIGATION INFO
                updateNavigationInfo();                                              // <-- Update info display
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Update Navigation Information Display
            // ------------------------------------------------------------
            function updateNavigationInfo() {
                const info = document.getElementById('navigation-info');             // <-- Get info element
                const zoomPercent = Math.round(currentZoom * 100);                  // <-- Calculate zoom percentage
                info.textContent = `Zoom: ${zoomPercent}% | Pan: ${Math.round(currentPanX)}, ${Math.round(currentPanY)}`;
                
                // SHOW INFO TEMPORARILY
                info.classList.add('visible');                                      // <-- Show info
                clearTimeout(info.hideTimeout);                                     // <-- Clear hide timer
                info.hideTimeout = setTimeout(() => {
                    info.classList.remove('visible');                               // <-- Hide after delay
                }, 2000);
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Handle Mouse Wheel Zoom
            // ------------------------------------------------------------
            function handleWheelZoom(event) {
                event.preventDefault();                                              // <-- Prevent page scroll
                
                const container = document.getElementById('canvas-container');       // <-- Get container
                const rect = container.getBoundingClientRect();                     // <-- Get container bounds
                
                // CALCULATE MOUSE POSITION RELATIVE TO CONTAINER
                const mouseX = event.clientX - rect.left;                           // <-- Mouse X in container
                const mouseY = event.clientY - rect.top;                            // <-- Mouse Y in container
                
                // CALCULATE ZOOM DELTA
                const delta = -event.deltaY * zoomSensitivity;                      // <-- Zoom direction
                const oldZoom = currentZoom;                                         // <-- Store old zoom
                currentZoom = Math.max(minZoom, Math.min(maxZoom, currentZoom + delta)); // <-- Clamp zoom
                
                if (currentZoom !== oldZoom) {
                    // ADJUST PAN TO ZOOM TOWARDS MOUSE POSITION
                    const zoomRatio = currentZoom / oldZoom;                         // <-- Zoom ratio
                    currentPanX = mouseX - (mouseX - currentPanX) * zoomRatio;      // <-- Adjust pan X
                    currentPanY = mouseY - (mouseY - currentPanY) * zoomRatio;      // <-- Adjust pan Y
                    
                    updateCanvasTransform();                                         // <-- Apply transform
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Handle Pan Start
            // ------------------------------------------------------------
            function handlePanStart(event) {
                if (event.button === 1 || event.button === 2) {                     // <-- Middle or right mouse
                    event.preventDefault();                                          // <-- Prevent context menu
                    isPanning = true;                                                // <-- Start panning
                    lastPanX = event.clientX;                                       // <-- Store start X
                    lastPanY = event.clientY;                                       // <-- Store start Y
                    
                    const container = document.getElementById('canvas-container');   // <-- Get container
                    container.classList.add('panning');                             // <-- Add panning cursor
                    
                    document.addEventListener('mousemove', handlePanMove);           // <-- Add move listener
                    document.addEventListener('mouseup', handlePanEnd);             // <-- Add end listener
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Handle Pan Movement
            // ------------------------------------------------------------
            function handlePanMove(event) {
                if (isPanning) {
                    const deltaX = event.clientX - lastPanX;                        // <-- Calculate X delta
                    const deltaY = event.clientY - lastPanY;                        // <-- Calculate Y delta
                    
                    currentPanX += deltaX;                                           // <-- Update pan X
                    currentPanY += deltaY;                                           // <-- Update pan Y
                    
                    lastPanX = event.clientX;                                       // <-- Update last X
                    lastPanY = event.clientY;                                       // <-- Update last Y
                    
                    updateCanvasTransform();                                         // <-- Apply transform
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Handle Pan End
            // ------------------------------------------------------------
            function handlePanEnd(event) {
                if (isPanning) {
                    isPanning = false;                                               // <-- Stop panning
                    
                    const container = document.getElementById('canvas-container');   // <-- Get container
                    container.classList.remove('panning');                          // <-- Remove panning cursor
                    
                    document.removeEventListener('mousemove', handlePanMove);       // <-- Remove move listener
                    document.removeEventListener('mouseup', handlePanEnd);         // <-- Remove end listener
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Reset Canvas Navigation
            // ------------------------------------------------------------
            function resetCanvasNavigation() {
                currentZoom = 1.0;                                                   // <-- Reset zoom
                currentPanX = 0;                                                     // <-- Reset pan X
                currentPanY = 0;                                                     // <-- Reset pan Y
                updateCanvasTransform();                                             // <-- Apply reset transform
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Setup Canvas Navigation Event Listeners
            // ------------------------------------------------------------
            function setupCanvasNavigation() {
                const container = document.getElementById('canvas-container');       // <-- Get canvas container
                
                // WHEEL ZOOM
                container.addEventListener('wheel', handleWheelZoom, { passive: false }); // <-- Add wheel listener
                
                // PAN CONTROLS
                container.addEventListener('mousedown', handlePanStart);             // <-- Add pan start
                container.addEventListener('contextmenu', (e) => e.preventDefault()); // <-- Disable context menu
                
                console.log('✅ Canvas navigation setup complete');
            }
            // ------------------------------------------------------------
            
        // endregion -------------------------------------------------------------------
        
        // -----------------------------------------------------------------------------
        // REGION | Watercolor Image Processing Engine
        // -----------------------------------------------------------------------------
            
            // FUNCTION | Initialize Canvas with Original Image
            // ------------------------------------------------------------
            function initializeCanvas() {
                console.log('Initializing canvas with data URL image');              // <-- Debug log
                
                // LOAD ORIGINAL IMAGE FIRST (CRITICAL)
                originalImage.onload = function() {
                    console.log('Original image loaded:', originalImage.width + 'x' + originalImage.height);
                    
                    canvas.width = originalImage.width;                              // <-- Set canvas dimensions
                    canvas.height = originalImage.height;                            // <-- Match image size
                    ctx.drawImage(originalImage, 0, 0);                              // <-- Draw original image
                    
                    try {
                        originalImageData = ctx.getImageData(0, 0, canvas.width, canvas.height);  // <-- Store original (IMMUTABLE)
                        processedImageData = new ImageData(new Uint8ClampedArray(originalImageData.data), originalImageData.width, originalImageData.height); // <-- Copy for processing
                        
                        console.log('Image data captured successfully');
                        
                        // SETUP PREVIEW TOGGLE
                        setupPreviewToggle();                                        // <-- Setup toggle functionality
                        
                        // SETUP NAVIGATION
                        setupCanvasNavigation();                                     // <-- Setup zoom and pan
                        
                        // LOAD PAPER TEXTURE (NON-BLOCKING)
                        loadPaperTexture();                                          // <-- Load texture after main image
                    } catch (e) {
                        console.error('Error capturing image data:', e);
                        alert('Error processing image. This may be a security restriction.');
                    }
                };
                
                originalImage.onerror = function() {
                    console.error('Failed to load original image');
                    alert('Failed to load the SketchUp image. Please try again.');
                };
                
                // LOAD FROM DATA URL
                originalImage.src = IMAGE_DATA_URL;                                  // <-- Load from data URL
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Load Paper Texture (Non-blocking)
            // ------------------------------------------------------------
            function loadPaperTexture() {
                try {
                    if (!PAPER_TEXTURE_DATA_URL) {
                        console.warn('No paper texture data URL provided');
                        paperTextureLoaded = false;
                        return;
                    }
                    
                    console.log('Loading paper texture from data URL');               // <-- Debug log
                    
                    paperTexture.onload = function() {
                        paperTextureLoaded = true;                                   // <-- Mark texture as loaded
                        console.log('✅ Paper texture loaded:', paperTexture.width + 'x' + paperTexture.height);
                    };
                    
                    paperTexture.onerror = function() {
                        console.warn('⚠️ Paper texture failed to load, continuing without it');
                        paperTextureLoaded = false;                                  // <-- Continue without texture
                    };
                    
                    paperTexture.src = PAPER_TEXTURE_DATA_URL;                       // <-- Load from data URL
                } catch (e) {
                    console.warn('Error loading paper texture:', e);
                    paperTextureLoaded = false;
                }
            }
            // ------------------------------------------------------------
            
            
            // HELPER FUNCTION | Calculate Pixel Luminance
            // ------------------------------------------------------------
            function calculateLuminance(r, g, b) {
                return 0.299 * r + 0.587 * g + 0.114 * b;                           // <-- Standard luminance formula
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Apply Kuwahara Filter for Painterly Effect
            // ------------------------------------------------------------
            function applyKuwaharaFilter(imageData, radius) {
                const width = imageData.width;                                       // <-- Image width
                const height = imageData.height;                                     // <-- Image height
                const src = imageData.data;                                          // <-- Source pixel data
                const dst = new Uint8ClampedArray(src.length);                       // <-- Destination buffer
                
                for (let y = 0; y < height; y++) {
                    for (let x = 0; x < width; x++) {
                        let minVariance = Infinity;                                  // <-- Track minimum variance
                        let bestR = 0, bestG = 0, bestB = 0;                        // <-- Best color values
                        
                        // CHECK FOUR QUADRANTS
                        for (let dy = 0; dy < 2; dy++) {
                            for (let dx = 0; dx < 2; dx++) {
                                let sumR = 0, sumG = 0, sumB = 0;                   // <-- Color sums
                                let sumLum = 0, sumLumSq = 0;                       // <-- Luminance statistics
                                let count = 0;                                       // <-- Pixel count
                                
                                // SAMPLE QUADRANT PIXELS
                                for (let ky = -radius; ky <= 0; ky++) {
                                    for (let kx = -radius; kx <= 0; kx++) {
                                        const px = x + kx + dx * radius;            // <-- Sample x position
                                        const py = y + ky + dy * radius;            // <-- Sample y position
                                        
                                        if (px >= 0 && px < width && py >= 0 && py < height) {
                                            const idx = (py * width + px) * 4;      // <-- Pixel index
                                            const r = src[idx];                      // <-- Red channel
                                            const g = src[idx + 1];                  // <-- Green channel
                                            const b = src[idx + 2];                  // <-- Blue channel
                                            const lum = calculateLuminance(r, g, b); // <-- Calculate luminance
                                            
                                            sumR += r;                               // <-- Accumulate red
                                            sumG += g;                               // <-- Accumulate green
                                            sumB += b;                               // <-- Accumulate blue
                                            sumLum += lum;                           // <-- Accumulate luminance
                                            sumLumSq += lum * lum;                   // <-- Accumulate squared
                                            count++;                                 // <-- Increment count
                                        }
                                    }
                                }
                                
                                if (count > 0) {
                                    const meanLum = sumLum / count;                 // <-- Mean luminance
                                    const variance = sumLumSq / count - meanLum * meanLum;  // <-- Variance
                                    
                                    if (variance < minVariance) {
                                        minVariance = variance;                      // <-- Update minimum
                                        bestR = sumR / count;                        // <-- Best red average
                                        bestG = sumG / count;                        // <-- Best green average
                                        bestB = sumB / count;                        // <-- Best blue average
                                    }
                                }
                            }
                        }
                        
                        const dstIdx = (y * width + x) * 4;                         // <-- Destination index
                        dst[dstIdx] = bestR;                                         // <-- Set red
                        dst[dstIdx + 1] = bestG;                                     // <-- Set green
                        dst[dstIdx + 2] = bestB;                                     // <-- Set blue
                        dst[dstIdx + 3] = 255;                                       // <-- Full opacity
                    }
                }
                
                return new ImageData(dst, width, height);                           // <-- Return processed data
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Apply Color Bleeding Effect
            // ------------------------------------------------------------
            function applyColorBleeding(imageData, intensity, radius) {
                const width = imageData.width;                                       // <-- Image dimensions
                const height = imageData.height;                                     
                const src = imageData.data;
                const dst = new Uint8ClampedArray(src);
                
                // GAUSSIAN BLUR FOR COLOR SPREADING
                const sigma = radius / 3;                                            // <-- Gaussian sigma
                const kernelSize = Math.ceil(radius * 2) + 1;                       // <-- Kernel dimensions
                const kernel = [];                                                   // <-- Gaussian kernel
                
                // BUILD GAUSSIAN KERNEL
                let sum = 0;
                for (let i = 0; i < kernelSize; i++) {
                    kernel[i] = [];
                    for (let j = 0; j < kernelSize; j++) {
                        const x = i - Math.floor(kernelSize / 2);
                        const y = j - Math.floor(kernelSize / 2);
                        const value = Math.exp(-(x * x + y * y) / (2 * sigma * sigma));
                        kernel[i][j] = value;
                        sum += value;
                    }
                }
                
                // NORMALIZE KERNEL
                for (let i = 0; i < kernelSize; i++) {
                    for (let j = 0; j < kernelSize; j++) {
                        kernel[i][j] /= sum;
                    }
                }
                
                // APPLY CONVOLUTION
                for (let y = 0; y < height; y++) {
                    for (let x = 0; x < width; x++) {
                        let r = 0, g = 0, b = 0;
                        
                        for (let ky = 0; ky < kernelSize; ky++) {
                            for (let kx = 0; kx < kernelSize; kx++) {
                                const sx = x + kx - Math.floor(kernelSize / 2);
                                const sy = y + ky - Math.floor(kernelSize / 2);
                                
                                if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
                                    const idx = (sy * width + sx) * 4;
                                    const weight = kernel[ky][kx];
                                    r += src[idx] * weight;
                                    g += src[idx + 1] * weight;
                                    b += src[idx + 2] * weight;
                                }
                            }
                        }
                        
                        const idx = (y * width + x) * 4;
                        dst[idx] = src[idx] * (1 - intensity) + r * intensity;      // <-- Blend with original
                        dst[idx + 1] = src[idx + 1] * (1 - intensity) + g * intensity;
                        dst[idx + 2] = src[idx + 2] * (1 - intensity) + b * intensity;
                    }
                }
                
                return new ImageData(dst, width, height);
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Apply Wet Edge Effect
            // ------------------------------------------------------------
            function applyWetEdgeEffect(imageData, intensity) {
                const width = imageData.width;
                const height = imageData.height;
                const src = imageData.data;
                const dst = new Uint8ClampedArray(src);
                
                // DETECT EDGES USING SOBEL OPERATOR
                for (let y = 1; y < height - 1; y++) {
                    for (let x = 1; x < width - 1; x++) {
                        const idx = (y * width + x) * 4;
                        
                        // SOBEL X GRADIENT
                        const gx = (
                            -1 * calculateLuminance(src[((y-1)*width+(x-1))*4], src[((y-1)*width+(x-1))*4+1], src[((y-1)*width+(x-1))*4+2]) +
                            -2 * calculateLuminance(src[((y)*width+(x-1))*4], src[((y)*width+(x-1))*4+1], src[((y)*width+(x-1))*4+2]) +
                            -1 * calculateLuminance(src[((y+1)*width+(x-1))*4], src[((y+1)*width+(x-1))*4+1], src[((y+1)*width+(x-1))*4+2]) +
                            1 * calculateLuminance(src[((y-1)*width+(x+1))*4], src[((y-1)*width+(x+1))*4+1], src[((y-1)*width+(x+1))*4+2]) +
                            2 * calculateLuminance(src[((y)*width+(x+1))*4], src[((y)*width+(x+1))*4+1], src[((y)*width+(x+1))*4+2]) +
                            1 * calculateLuminance(src[((y+1)*width+(x+1))*4], src[((y+1)*width+(x+1))*4+1], src[((y+1)*width+(x+1))*4+2])
                        );
                        
                        // SOBEL Y GRADIENT
                        const gy = (
                            -1 * calculateLuminance(src[((y-1)*width+(x-1))*4], src[((y-1)*width+(x-1))*4+1], src[((y-1)*width+(x-1))*4+2]) +
                            -2 * calculateLuminance(src[((y-1)*width+(x))*4], src[((y-1)*width+(x))*4+1], src[((y-1)*width+(x))*4+2]) +
                            -1 * calculateLuminance(src[((y-1)*width+(x+1))*4], src[((y-1)*width+(x+1))*4+1], src[((y-1)*width+(x+1))*4+2]) +
                            1 * calculateLuminance(src[((y+1)*width+(x-1))*4], src[((y+1)*width+(x-1))*4+1], src[((y+1)*width+(x-1))*4+2]) +
                            2 * calculateLuminance(src[((y+1)*width+(x))*4], src[((y+1)*width+(x))*4+1], src[((y+1)*width+(x))*4+2]) +
                            1 * calculateLuminance(src[((y+1)*width+(x+1))*4], src[((y+1)*width+(x+1))*4+1], src[((y+1)*width+(x+1))*4+2])
                        );
                        
                        const edge = Math.sqrt(gx * gx + gy * gy) / 255;            // <-- Edge strength
                        const darkening = 1 - edge * intensity;                     // <-- Darkening factor
                        
                        dst[idx] = src[idx] * darkening;                            // <-- Apply darkening
                        dst[idx + 1] = src[idx + 1] * darkening;
                        dst[idx + 2] = src[idx + 2] * darkening;
                    }
                }
                
                return new ImageData(dst, width, height);
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Apply Paper Texture Overlay (Tiled Image)
            // ------------------------------------------------------------
            function applyPaperTexture(imageData, strength) {
                if (!paperTextureLoaded || strength <= 0) {
                    return imageData;                                                // <-- Return unchanged if no texture or no strength
                }
                
                const width = imageData.width;
                const height = imageData.height;
                const src = imageData.data;
                const dst = new Uint8ClampedArray(src);
                
                // CREATE TEMPORARY CANVAS FOR PAPER TEXTURE TILING
                const tempCanvas = document.createElement('canvas');
                const tempCtx = tempCanvas.getContext('2d');
                tempCanvas.width = width;
                tempCanvas.height = height;
                
                // TILE PAPER TEXTURE ACROSS CANVAS
                const tileWidth = paperTexture.width;
                const tileHeight = paperTexture.height;
                
                for (let y = 0; y < height; y += tileHeight) {
                    for (let x = 0; x < width; x += tileWidth) {
                        tempCtx.drawImage(paperTexture, x, y);                       // <-- Tile the texture
                    }
                }
                
                // GET TILED TEXTURE IMAGE DATA
                const textureData = tempCtx.getImageData(0, 0, width, height);
                const texturePixels = textureData.data;
                
                // APPLY MULTIPLY BLEND WITH STRENGTH
                for (let i = 0; i < src.length; i += 4) {
                    // GET TEXTURE BRIGHTNESS (normalized)
                    const texR = texturePixels[i] / 255;
                    const texG = texturePixels[i + 1] / 255;
                    const texB = texturePixels[i + 2] / 255;
                    const texBrightness = (texR + texG + texB) / 3;                 // <-- Average brightness
                    
                    // MULTIPLY BLEND WITH STRENGTH CONTROL
                    const multiplier = 1 - strength + (texBrightness * strength);   // <-- Mix between 1 and texture brightness
                    
                    dst[i] = Math.max(0, Math.min(255, src[i] * multiplier));       // <-- Apply multiply blend
                    dst[i + 1] = Math.max(0, Math.min(255, src[i + 1] * multiplier));
                    dst[i + 2] = Math.max(0, Math.min(255, src[i + 2] * multiplier));
                    dst[i + 3] = src[i + 3];                                        // <-- Preserve alpha
                }
                
                return new ImageData(dst, width, height);
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Adjust Color Properties
            // ------------------------------------------------------------
            function adjustColorProperties(imageData, saturation, brightness) {
                const width = imageData.width;
                const height = imageData.height;
                const src = imageData.data;
                const dst = new Uint8ClampedArray(src);
                
                for (let i = 0; i < src.length; i += 4) {
                    let r = src[i] / 255;                                            // <-- Normalize RGB values
                    let g = src[i + 1] / 255;
                    let b = src[i + 2] / 255;
                    
                    // SIMPLE SATURATION ADJUSTMENT (preserves colors correctly)
                    const gray = 0.299 * r + 0.587 * g + 0.114 * b;                 // <-- Calculate grayscale
                    
                    // MIX BETWEEN GRAYSCALE AND ORIGINAL COLOR
                    r = gray + (r - gray) * saturation;                             // <-- Adjust saturation
                    g = gray + (g - gray) * saturation;
                    b = gray + (b - gray) * saturation;
                    
                    // APPLY BRIGHTNESS
                    r = r * brightness;                                              // <-- Apply brightness
                    g = g * brightness;
                    b = b * brightness;
                    
                    // WATERCOLOR DESATURATION EFFECT (subtle color shift)
                    const avgColor = (r + g + b) / 3;                               // <-- Average color value
                    const desatFactor = 0.15;                                        // <-- Desaturation amount
                    r = r + (avgColor - r) * desatFactor;                           // <-- Shift towards average
                    g = g + (avgColor - g) * desatFactor;
                    b = b + (avgColor - b) * desatFactor;
                    
                    // CONVERT BACK TO 0-255 RANGE
                    dst[i] = Math.max(0, Math.min(255, Math.round(r * 255)));       // <-- Clamp and convert
                    dst[i + 1] = Math.max(0, Math.min(255, Math.round(g * 255)));
                    dst[i + 2] = Math.max(0, Math.min(255, Math.round(b * 255)));
                    dst[i + 3] = src[i + 3];                                        // <-- Preserve alpha
                }
                
                return new ImageData(dst, width, height);
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Apply Pen Line Overlay with Multiply Blend
            // ------------------------------------------------------------
            function applyPenOverlay(processedData, originalData, opacity, edgeThreshold) {
                const width = processedData.width;
                const height = processedData.height;
                const processed = processedData.data;
                const original = originalData.data;
                const dst = new Uint8ClampedArray(processed);
                
                // APPLY MULTIPLY BLEND MODE TO PRESERVE DARK LINES
                for (let y = 0; y < height; y++) {
                    for (let x = 0; x < width; x++) {
                        const idx = (y * width + x) * 4;
                        
                        // GET ORIGINAL PIXEL DARKNESS (inverted luminance)
                        const origLum = calculateLuminance(original[idx], original[idx+1], original[idx+2]);
                        const darkness = 1 - (origLum / 255);                        // <-- 1 = black, 0 = white
                        
                        // DETECT IF THIS IS A DARK LINE OR EDGE
                        let isEdge = false;
                        if (darkness > edgeThreshold) {                              // <-- Dark pixels
                            isEdge = true;
                        } else if (x > 0 && x < width - 1 && y > 0 && y < height - 1) {
                            // CHECK FOR EDGE TRANSITIONS
                            const centerLum = origLum;
                            let maxDiff = 0;
                            
                            for (let dy = -1; dy <= 1; dy++) {
                                for (let dx = -1; dx <= 1; dx++) {
                                    if (dx === 0 && dy === 0) continue;
                                    const nIdx = ((y + dy) * width + (x + dx)) * 4;
                                    const neighborLum = calculateLuminance(original[nIdx], original[nIdx+1], original[nIdx+2]);
                                    const diff = Math.abs(centerLum - neighborLum) / 255;
                                    maxDiff = Math.max(maxDiff, diff);
                                }
                            }
                            
                            if (maxDiff > edgeThreshold) {
                                isEdge = true;
                            }
                        }
                        
                        if (isEdge || darkness > 0.3) {                              // <-- Apply to edges and dark areas
                            // MULTIPLY BLEND MODE (preserves dark lines)
                            const blendFactor = opacity * Math.min(1, darkness + 0.3); // <-- Boost dark lines
                            
                            dst[idx] = processed[idx] * (1 - blendFactor) + 
                                      (processed[idx] * original[idx] / 255) * blendFactor;
                            dst[idx + 1] = processed[idx + 1] * (1 - blendFactor) + 
                                          (processed[idx + 1] * original[idx + 1] / 255) * blendFactor;
                            dst[idx + 2] = processed[idx + 2] * (1 - blendFactor) + 
                                          (processed[idx + 2] * original[idx + 2] / 255) * blendFactor;
                        }
                    }
                }
                
                return new ImageData(dst, width, height);
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Main Watercolor Processing Pipeline
            // ------------------------------------------------------------
            function applyWatercolorEffect() {
                if (!originalImageData) return;                                      // <-- Check if image loaded
                
                console.log('Applying watercolor effect from original image...');   // <-- Debug log
                
                // GET PARAMETER VALUES
                const radius = parseInt(document.getElementById('kuwahara-radius').value);
                const passes = parseInt(document.getElementById('filter-passes').value);
                const bleeding = parseInt(document.getElementById('color-bleeding').value) / 100;
                const wetEdge = parseInt(document.getElementById('wet-edge').value) / 100;
                const texture = parseInt(document.getElementById('paper-texture').value) / 100;
                const saturation = parseInt(document.getElementById('saturation').value) / 100;
                const brightness = parseInt(document.getElementById('brightness').value) / 100;
                const penEnabled = document.getElementById('pen-overlay-toggle').checked;
                const lineOpacity = parseInt(document.getElementById('line-opacity').value) / 100;
                const edgeThreshold = parseInt(document.getElementById('edge-threshold').value) / 100;
                
                // ALWAYS START WITH FRESH COPY OF ORIGINAL IMAGE DATA
                let result = new ImageData(new Uint8ClampedArray(originalImageData.data), originalImageData.width, originalImageData.height);
                
                // APPLY MULTIPLE KUWAHARA PASSES
                for (let i = 0; i < passes; i++) {
                    result = applyKuwaharaFilter(result, radius);                   // <-- Apply filter pass
                }
                
                // APPLY WATERCOLOR EFFECTS
                if (bleeding > 0) {
                    result = applyColorBleeding(result, bleeding, radius * 2);       // <-- Color bleeding
                }
                
                if (wetEdge > 0) {
                    result = applyWetEdgeEffect(result, wetEdge);                   // <-- Wet edges
                }
                
                // ADJUST COLORS
                result = adjustColorProperties(result, saturation, brightness);      // <-- Color adjustments
                
                // APPLY PEN OVERLAY IF ENABLED
                if (penEnabled) {
                    result = applyPenOverlay(result, originalImageData, lineOpacity, edgeThreshold);
                }
                
                // APPLY PAPER TEXTURE ON TOP OF EVERYTHING (final multiply layer)
                if (texture > 0) {
                    console.log('Applying paper texture overlay with strength:', texture);
                    result = applyPaperTexture(result, texture);                    // <-- Paper texture as top layer
                    console.log('Paper texture applied successfully');
                }
                
                // STORE PROCESSED DATA
                processedImageData = result;                                         // <-- Store processed data
                
                // DISPLAY BASED ON TOGGLE STATE
                displayCurrentImage();                                               // <-- Update display
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Setup Preview Toggle Functionality
            // ------------------------------------------------------------
            function setupPreviewToggle() {
                const toggle = document.getElementById('preview-toggle');           // <-- Get toggle element
                
                toggle.addEventListener('change', function() {
                    isShowingProcessed = toggle.checked;                            // <-- Update state
                    displayCurrentImage();                                           // <-- Switch display
                });
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Display Current Image Based on Toggle State
            // ------------------------------------------------------------
            function displayCurrentImage() {
                if (isShowingProcessed && processedImageData) {
                    ctx.putImageData(processedImageData, 0, 0);                      // <-- Show processed
                    console.log('Displaying processed image');
                } else if (originalImageData) {
                    ctx.putImageData(originalImageData, 0, 0);                       // <-- Show original
                    console.log('Displaying original image');
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Update Value Displays
            // ------------------------------------------------------------
            function setupValueDisplays() {
                // KUWAHARA RADIUS
                document.getElementById('kuwahara-radius').addEventListener('input', function(e) {
                    document.getElementById('radius-value').textContent = e.target.value;
                });
                
                // FILTER PASSES
                document.getElementById('filter-passes').addEventListener('input', function(e) {
                    document.getElementById('passes-value').textContent = e.target.value;
                });
                
                // COLOR BLEEDING
                document.getElementById('color-bleeding').addEventListener('input', function(e) {
                    document.getElementById('bleeding-value').textContent = e.target.value + '%';
                });
                
                // WET EDGE
                document.getElementById('wet-edge').addEventListener('input', function(e) {
                    document.getElementById('wet-edge-value').textContent = e.target.value + '%';
                });
                
                // PAPER TEXTURE
                document.getElementById('paper-texture').addEventListener('input', function(e) {
                    document.getElementById('texture-value').textContent = e.target.value + '%';
                });
                
                // LINE OPACITY
                document.getElementById('line-opacity').addEventListener('input', function(e) {
                    document.getElementById('line-opacity-value').textContent = e.target.value + '%';
                });
                
                // EDGE THRESHOLD
                document.getElementById('edge-threshold').addEventListener('input', function(e) {
                    document.getElementById('edge-threshold-value').textContent = e.target.value + '%';
                });
                
                // SATURATION
                document.getElementById('saturation').addEventListener('input', function(e) {
                    document.getElementById('saturation-value').textContent = e.target.value + '%';
                });
                
                // BRIGHTNESS
                document.getElementById('brightness').addEventListener('input', function(e) {
                    document.getElementById('brightness-value').textContent = e.target.value + '%';
                });
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Load Preset Configuration
            // ------------------------------------------------------------
            function loadPreset(presetName) {
                const presets = CONFIG.presets[presetName];                         // <-- Get preset values
                if (!presets) return;
                
                // APPLY PRESET VALUES
                if (presets.kuwahara_radius !== undefined) {
                    document.getElementById('kuwahara-radius').value = presets.kuwahara_radius;
                    document.getElementById('radius-value').textContent = presets.kuwahara_radius;
                }
                
                if (presets.color_bleeding_intensity !== undefined) {
                    const value = presets.color_bleeding_intensity * 100;
                    document.getElementById('color-bleeding').value = value;
                    document.getElementById('bleeding-value').textContent = value + '%';
                }
                
                if (presets.pen_overlay_opacity !== undefined) {
                    const value = presets.pen_overlay_opacity * 100;
                    document.getElementById('line-opacity').value = value;
                    document.getElementById('line-opacity-value').textContent = value + '%';
                }
                
                if (presets.paper_texture_strength !== undefined) {
                    const value = presets.paper_texture_strength * 100;
                    document.getElementById('paper-texture').value = value;
                    document.getElementById('texture-value').textContent = value + '%';
                }
                
                if (presets.saturation_boost !== undefined) {
                    const value = presets.saturation_boost * 100;
                    document.getElementById('saturation').value = value;
                    document.getElementById('saturation-value').textContent = value + '%';
                }
                
                if (presets.wet_edge_intensity !== undefined) {
                    const value = presets.wet_edge_intensity * 100;
                    document.getElementById('wet-edge').value = value;
                    document.getElementById('wet-edge-value').textContent = value + '%';
                }
                
                // AUTO-APPLY IF CONFIGURED
                if (CONFIG.ui_settings && CONFIG.ui_settings.auto_apply_changes) {
                    applyWatercolorEffect();
                } else {
                    // ALWAYS APPLY WHEN PRESET IS LOADED
                    applyWatercolorEffect();
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Reset to Default Values
            // ------------------------------------------------------------
            function resetToDefaults() {
                try {
                    console.log('Resetting to defaults...');
                    
                    // USE HARDCODED DEFAULTS FOR SAFETY
                    document.getElementById('kuwahara-radius').value = 4;
                    document.getElementById('radius-value').textContent = '4';
                    
                    document.getElementById('filter-passes').value = 2;
                    document.getElementById('passes-value').textContent = '2';
                    
                    document.getElementById('color-bleeding').value = 30;
                    document.getElementById('bleeding-value').textContent = '30%';
                    
                    document.getElementById('wet-edge').value = 50;
                    document.getElementById('wet-edge-value').textContent = '50%';
                    
                    document.getElementById('paper-texture').value = 15;
                    document.getElementById('texture-value').textContent = '15%';
                    
                    document.getElementById('pen-overlay-toggle').checked = true;
                    
                    document.getElementById('line-opacity').value = 80;
                    document.getElementById('line-opacity-value').textContent = '80%';
                    
                    document.getElementById('saturation').value = 75;
                    document.getElementById('saturation-value').textContent = '75%';
                    
                    document.getElementById('brightness').value = 115;
                    document.getElementById('brightness-value').textContent = '115%';
                    
                    document.getElementById('edge-threshold').value = 5;
                    document.getElementById('edge-threshold-value').textContent = '5%';
                    
                    console.log('Defaults reset successfully');
                } catch (e) {
                    console.error('Error resetting defaults:', e);
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Save Watercolor Image
            // ------------------------------------------------------------
            function saveWatercolorImage() {
                try {
                    console.log('Starting image save process...');
                    
                    if (!processedImageData) {
                        alert('Please apply the watercolor effect first!');              // <-- Warn if no processed data
                        return;
                    }
                    
                    // CREATE A TEMPORARY CANVAS FOR EXPORT (AVOIDS AFFECTING DISPLAY)
                    const tempCanvas = document.createElement('canvas');                 // <-- Create temporary canvas
                    const tempCtx = tempCanvas.getContext('2d');                       // <-- Get temp context
                    
                    // SET TEMPORARY CANVAS TO ORIGINAL IMAGE DIMENSIONS
                    tempCanvas.width = processedImageData.width;                        // <-- Set width to processed image
                    tempCanvas.height = processedImageData.height;                      // <-- Set height to processed image
                    
                    // DRAW PROCESSED IMAGE DATA TO TEMPORARY CANVAS (FLATTENED FINAL IMAGE)
                    tempCtx.putImageData(processedImageData, 0, 0);                     // <-- Draw all layers baked together
                    
                    // CONVERT TO DATA URL FROM TEMPORARY CANVAS
                    const dataURL = tempCanvas.toDataURL('image/png');                  // <-- Get final flattened PNG
                    
                    console.log('Final watercolor image prepared for export');
                    console.log('Image dimensions:', tempCanvas.width + 'x' + tempCanvas.height);
                    console.log('Data URL length:', dataURL.length);
                    
                    // SEND TO RUBY USING MODERN HTMLDIALOG METHOD (PRESERVES HTML CONTENT)
                    sketchup.save_image(dataURL);                                       // <-- Modern HtmlDialog communication
                    
                } catch (e) {
                    console.error('Error saving watercolor image:', e);
                    alert('Error exporting image: ' + e.message + '\\nPlease try applying the effect again.');
                }
            }
            // ------------------------------------------------------------
            
            
            // FUNCTION | Initialize on Page Load
            // ------------------------------------------------------------
            window.onload = function() {
                console.log('Window loaded, initializing watercolor tool...');
                try {
                    setupImageCaptureControls();
                    initializeCanvas();
                    setupValueDisplays();
                    // Set all UI controls from config/preset
                    const defaults = CONFIG.presets && CONFIG.presets.delicate_wash ? CONFIG.presets.delicate_wash : {};
                    // Brush Size
                    document.getElementById('kuwahara-radius').value = defaults.kuwahara_radius || CONFIG.rendering_defaults.kuwahara_filter.radius || 4;
                    document.getElementById('radius-value').textContent = document.getElementById('kuwahara-radius').value;
                    // Multiple Passes
                    document.getElementById('filter-passes').value = defaults.filter_passes || CONFIG.rendering_defaults.kuwahara_filter.multiple_passes || 2;
                    document.getElementById('passes-value').textContent = document.getElementById('filter-passes').value;
                    // Color Bleeding
                    document.getElementById('color-bleeding').value = Math.round((defaults.color_bleeding_intensity !== undefined ? defaults.color_bleeding_intensity : CONFIG.rendering_defaults.watercolor_effects.color_bleeding.intensity || 0) * 100);
                    document.getElementById('bleeding-value').textContent = document.getElementById('color-bleeding').value + '%';
                    // Wet Edges
                    document.getElementById('wet-edge').value = Math.round((defaults.wet_edge_intensity !== undefined ? defaults.wet_edge_intensity : CONFIG.rendering_defaults.watercolor_effects.color_bleeding.wet_edge_intensity || 0) * 100);
                    document.getElementById('wet-edge-value').textContent = document.getElementById('wet-edge').value + '%';
                    // Paper Texture
                    document.getElementById('paper-texture').value = Math.round((defaults.paper_texture_strength !== undefined ? defaults.paper_texture_strength : CONFIG.rendering_defaults.watercolor_effects.paper_texture.texture_strength || 0) * 100);
                    document.getElementById('texture-value').textContent = document.getElementById('paper-texture').value + '%';
                    // Pen Overlay
                    document.getElementById('pen-overlay-toggle').checked = true;
                    // Line Opacity
                    document.getElementById('line-opacity').value = Math.round((defaults.pen_overlay_opacity !== undefined ? defaults.pen_overlay_opacity : CONFIG.rendering_defaults.pen_overlay.line_opacity || 0) * 100);
                    document.getElementById('line-opacity-value').textContent = document.getElementById('line-opacity').value + '%';
                    // Edge Detection
                    document.getElementById('edge-threshold').value = 5;
                    document.getElementById('edge-threshold-value').textContent = '5%';
                    // Saturation
                    document.getElementById('saturation').value = Math.round((defaults.saturation_boost !== undefined ? defaults.saturation_boost : CONFIG.rendering_defaults.watercolor_effects.color_vibrancy.saturation_boost || 0) * 100);
                    document.getElementById('saturation-value').textContent = document.getElementById('saturation').value + '%';
                    // Brightness
                    document.getElementById('brightness').value = Math.round((defaults.brightness !== undefined ? defaults.brightness : CONFIG.rendering_defaults.watercolor_effects.color_vibrancy.brightness_adjustment || 0) * 100);
                    document.getElementById('brightness-value').textContent = document.getElementById('brightness').value + '%';
                    // Show Processed Image
                    document.getElementById('preview-toggle').checked = true;
                    console.log('Initialization complete');
                } catch (e) {
                    console.error('Error during initialization:', e);
                    alert('Failed to initialize watercolor tool: ' + e.message);
                }
            };
            // ------------------------------------------------------------
            
        // endregion -------------------------------------------------------------------
        JS
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Image Saving Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Save Processed Watercolor Image
    # ------------------------------------------------------------
    def self.save_watercolor_image(data_url)
        default_name = "watercolor_render_#{Time.now.strftime('%Y%m%d_%H%M%S')}.png"
        file_path = UI.savepanel('Save Watercolor Image', Dir.home, default_name)
        
        return unless file_path                                               # User cancelled
        
        begin
            png_data = data_url.sub(/^data:image\/png;base64,/, '')          # Remove data URL prefix
            decoded_data = Base64.decode64(png_data)                          # Decode base64
            
            File.binwrite(file_path, decoded_data)                           # Write binary data
            UI.messagebox("Watercolor image saved successfully!")
        rescue => e
            UI.messagebox("Error saving image: #{e.message}")
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Configuration Updates
# -----------------------------------------------------------------------------

    # FUNCTION | Update Runtime Configuration
    # ------------------------------------------------------------
    def self.update_runtime_config(config_data)
        begin
            updated_config = JSON.parse(config_data)                         # Parse config data
            @@config.merge!(updated_config)                                   # Update runtime config
        rescue => e
            puts "Error updating config: #{e.message}"
        end
    end
    # ------------------------------------------------------------

    # FUNCTION | Apply Preset Configuration
    # ------------------------------------------------------------
    def self.apply_preset_configuration(preset_name)
        preset = get_config_value("presets.#{preset_name}")                  # Get preset values
        return unless preset
        
        # Update dialog with preset values through JavaScript
        script = "loadPreset('#{preset_name}');"
        @@dialog.execute_script(script) if @@dialog
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Extension Registration
# -----------------------------------------------------------------------------

    unless file_loaded?(__FILE__)
        # Create extension
        extension = SketchupExtension.new(PLUGIN_NAME, __FILE__)
        extension.description = "Transform SketchUp views into watercolor pen and wash illustrations with enhanced capture and navigation tools"
        extension.version = PLUGIN_VERSION
        extension.creator = "Adam Noble - Noble Architecture"
        extension.copyright = "© 2025 Noble Architecture"
        
        # Register extension
        Sketchup.register_extension(extension, true)
        
        # Add to Extensions menu
        extensions_menu = UI.menu('Extensions')
        vale_submenu = extensions_menu.add_submenu('Vale Design Suite')
        vale_submenu.add_item(PLUGIN_NAME) { activate }
        
        # Also add to Plugins menu for compatibility
        UI.menu('Plugins').add_item(PLUGIN_NAME) { activate }
        
        file_loaded(__FILE__)
    end

# endregion -------------------------------------------------------------------

    end # module WatercolourRenderingTools
end # module ValeDesignSuite
