# =============================================================================
# VALEDESIGNSUITE - COMPONENT BROWSER
# =============================================================================
#
# FILE       : ValeDesignSuite_Tools_ComponentBrowser.rb
# NAMESPACE  : ValeDesignSuite::Tools::ComponentBrowser
# MODULE     : ComponentBrowser
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Component library browser for Vale Design Suite
# CREATED    : 2025
#
# DESCRIPTION:
# - This module implements a component browser for the Vale Design Suite.
# - It provides a visual interface for browsing and inserting components.
# - Components are loaded from a user-configurable directory.
# - Features include thumbnail preview, search, filtering, and drag-and-drop.
# - Configuration is persisted in the plugin's config directory.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 05-Jun-2025 - Version 1.0.0
# - Initial Implementation
# - Created component browser with grid layout
# - Added search and filter functionality
# - Implemented drag and drop support
# - Added persistent configuration for library path
#
# 06-Jun-2025 - Version 1.1.0
# - Asset-Builder-Files Exclusion: Added exclusion of folders ending with "_-_Asset-Builder-Files"
# - Global Search: Implemented global search functionality across entire library structure
# - Enhanced UI: Updated search to work globally instead of folder-specific
# - Path Display: Added relative path display in global search results
# - Bug Fixes: Improved navigation and state management for search modes
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'fileutils'

module ValeDesignSuite
  module Tools
    module ComponentBrowser

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | File Paths and Dialog Settings
    # ------------------------------------------------------------
    DIALOG_TITLE            =   "Vale Component Browser"                          # <-- Dialog window title
    DIALOG_WIDTH            =   1200                                              # <-- Dialog width in pixels
    DIALOG_HEIGHT           =   800                                               # <-- Dialog height in pixels
    CONFIG_FILENAME         =   "ComponentBrowser_Config.json"                    # <-- Configuration file name
    THUMBNAIL_EXTENSIONS    =   ['.jpg', '.jpeg', '.png', '.gif', '.bmp']         # <-- Supported thumbnail formats
    COMPONENT_EXTENSIONS    =   ['.skp']                                          # <-- Supported component formats
    EXCLUDED_FOLDER_SUFFIX  =   "_-_Asset-Builder-Files"                          # <-- Suffix for excluded folders containing build files
    
    # MODULE VARIABLES | Dialog and State Management
    # ------------------------------------------------------------
    @dialog                 =   nil                                               # <-- HTML dialog instance
    @library_path           =   nil                                               # <-- Component library directory path
    @current_path           =   nil                                               # <-- Current browsing path within library
    @components_data        =   []                                                # <-- Array of component metadata
    @config_file_path       =   nil                                               # <-- Full path to config file
    @global_components_cache =   []                                                # <-- Cache for global search results

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Initialization and Configuration
# -----------------------------------------------------------------------------

    # FUNCTION | Initialize the Component Browser
    # ------------------------------------------------------------
    def self.init
        setup_config_file_path                                                    # <-- Setup configuration file path
        load_configuration                                                        # <-- Load saved configuration
        show_dialog                                                               # <-- Display the browser dialog
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Setup Configuration File Path
    # ---------------------------------------------------------------
    def self.setup_config_file_path
        plugin_root = File.dirname(File.dirname(__FILE__))                       # <-- Get plugin root directory
        config_dir = File.join(plugin_root, 'Config_PluginConfigFiles')          # <-- Config directory path
        @config_file_path = File.join(config_dir, CONFIG_FILENAME)               # <-- Full config file path
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Load Configuration from File
    # ---------------------------------------------------------------
    def self.load_configuration
        return unless File.exist?(@config_file_path)                             # <-- Exit if no config file
        
        begin
            config_data = File.read(@config_file_path)                           # <-- Read config file
            config = JSON.parse(config_data)                                     # <-- Parse JSON data
            @library_path = config['library_path'] if config['library_path']     # <-- Set library path
        rescue => e
            puts "Error loading component browser config: #{e.message}"          # <-- Log error
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Save Configuration to File
    # ---------------------------------------------------------------
    def self.save_configuration
        config = { 'library_path' => @library_path }                             # <-- Create config object
        
        begin
            File.write(@config_file_path, JSON.pretty_generate(config))          # <-- Write config file
        rescue => e
            puts "Error saving component browser config: #{e.message}"           # <-- Log error
        end
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Check if Folder Should Be Excluded from Browser
    # ---------------------------------------------------------------
    def self.should_exclude_folder?(folder_name)
        # Exclude folders ending with "_-_Asset-Builder-Files" suffix
        # These directories contain intermediate files used during component construction
        # but not final validated assets meant for the Vale Design Suite system
        return folder_name.end_with?(EXCLUDED_FOLDER_SUFFIX)                     # <-- Check for excluded suffix
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Check if Component is from 60-Series (Vale Sketcher Elements)
    # ---------------------------------------------------------------
    def self.is_60_series_component?(component_path)
        # Check if component path contains 60-Series directory or Vale Sketcher naming
        # These are wall cutting window components that need 90-degree rotation and hole cutter regeneration
        is_60_series = component_path.include?("60-Series_-_Vale-Sketcher-Elements") ||  # <-- Check for 60-Series directory
                       component_path.include?("Vale-Sketcher") ||                       # <-- Check for Vale-Sketcher in name
                       component_path.include?("60_") ||                                  # <-- Check for 60_ prefix
                       File.basename(component_path, '.skp').match?(/^60[_\-]/)          # <-- Check for 60- or 60_ filename prefix
        
        if is_60_series
            puts "ValeDesignSuite: Detected 60-Series component: #{File.basename(component_path)}"  # <-- Debug output
        end
        
        return is_60_series                                                       # <-- Return detection result
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Create 90-Degree Rotation Transformation for Window Components
    # ---------------------------------------------------------------
    def self.create_window_component_transformation(base_position)
        # Create a 90-degree rotation around X-axis to make window components upright
        # This ensures wall cutting windows insert correctly oriented
        rotation_angle = 90.degrees                                              # <-- 90-degree rotation
        rotation_axis = X_AXIS                                                    # <-- Rotate around X-axis
        rotation_point = ORIGIN                                                   # <-- Rotation center point
        
        # Create the rotation transformation
        rotation_transform = Geom::Transformation.rotation(rotation_point, rotation_axis, rotation_angle)
        
        # Create the position transformation
        position_transform = Geom::Transformation.new(base_position)             # <-- Position transformation
        
        # Combine rotation and position transformations
        combined_transform = position_transform * rotation_transform             # <-- Apply rotation then position
        
        return combined_transform                                                 # <-- Return combined transformation
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Force Hole Cutter Regeneration for Vale Sketch Elements
    # ---------------------------------------------------------------
    def self.force_hole_cutter_regeneration(component_instance)
        # For Vale Sketch Elements (hole cutting components), we need to cut and paste
        # in place to trigger the double cut plugin's hole cutter regeneration
        # This operation is completely separate from the main placement operation
        begin
            puts "ValeDesignSuite: Starting separate hole cutter regeneration operation"  # <-- Debug output
            
            model = Sketchup.active_model                                         # <-- Get active model
            
            # Start a completely separate operation for hole cutter regeneration
            model.start_operation("Regenerate Hole Cutter", true)                # <-- Start separate operation
            
            # Clear any existing material on the component
            component_instance.material = nil                                     # <-- Remove any preview material
            
            # Select the component instance
            model.selection.clear                                                 # <-- Clear current selection
            model.selection.add(component_instance)                              # <-- Select the placed component
            
            puts "ValeDesignSuite: Component selected, performing cut operation"  # <-- Debug output
            
            # Use SketchUp's send_action to trigger cut operation
            Sketchup.send_action("editCut")                                       # <-- Cut component using menu action
            
            # Wait for cut to complete, then paste in place
            UI.start_timer(0.5, false) do
                puts "ValeDesignSuite: Performing paste in place operation"       # <-- Debug output
                
                # Use SketchUp's send_action to trigger paste in place operation
                Sketchup.send_action("editPasteInPlace")                          # <-- Paste component back in same position
                
                # Final cleanup
                UI.start_timer(0.3, false) do
                    model.selection.clear                                         # <-- Clear selection after operation
                    model.commit_operation                                        # <-- Commit the separate operation
                    puts "ValeDesignSuite: Hole cutter regeneration operation completed"  # <-- Debug output
                end
            end
            
        rescue => e
            puts "Error forcing hole cutter regeneration: #{e.message}"          # <-- Log any errors
            model.abort_operation if model                                       # <-- Abort operation on error
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Creation and Management
# -----------------------------------------------------------------------------

    # FUNCTION | Show Component Browser Dialog
    # ------------------------------------------------------------
    def self.show_dialog
        if @dialog && @dialog.visible?                                           # <-- Check if dialog exists
            @dialog.bring_to_front                                                # <-- Bring to front if visible
            return
        end
        
        create_dialog                                                             # <-- Create new dialog
        setup_dialog_callbacks                                                    # <-- Setup Ruby callbacks
        
        @dialog.set_html(create_dialog_html)                                     # <-- Set dialog HTML content
        @dialog.show                                                              # <-- Display dialog
        
        # Small delay to ensure JavaScript is loaded
        UI.start_timer(0.1, false) do
            # Initialize library on first run or load saved path
            if @library_path && !@library_path.empty?
                @current_path = @library_path                                        # <-- Set current path to root
                @dialog.execute_script("updateLibraryPath('#{@library_path.gsub("\\", "\\\\\\\\")}')")  # <-- Update UI
                load_components_from_library                                          # <-- Load components
            else
                @dialog.execute_script("showFirstTimeSetup();")                      # <-- Show setup prompt
            end
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create HTML Dialog Instance
    # ---------------------------------------------------------------
    def self.create_dialog
        @dialog = UI::HtmlDialog.new(
            dialog_title: DIALOG_TITLE,
            preferences_key: "ValeDesignSuite_ComponentBrowser",
            style: UI::HtmlDialog::STYLE_DIALOG,
            width: DIALOG_WIDTH,
            height: DIALOG_HEIGHT,
            left: 200,
            top: 200,
            resizable: true
        )
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Dialog HTML Content
    # ---------------------------------------------------------------
    def self.create_dialog_html
        plugin_root = File.dirname(File.dirname(__FILE__))                       # <-- Get plugin root
        logo_path = File.join(plugin_root, 'Assets_ValeBrandAssets', 'ValeHeaderImage_ValeLogo_HorizontalFormat.png')
        logo_url = "file:///" + logo_path.gsub(File::SEPARATOR, '/')             # <-- Convert to URL format
        
        <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>#{DIALOG_TITLE}</title>
            
            <!-- ----------------------------------------------------------------- -->
            <!-- REGION  |  CSS Styles and Variables                                -->
            <!-- ----------------------------------------------------------------- -->
            <style>
                /* CSS Variables - Vale Design Suite Standards */
                :root {
                    --FontCol_ValeTitleTextColour      : #172b3a;
                    --FontCol_ValeTitleHeadingColour   : #172b3a;
                    --FontCol_ValeStandardTextColour   : #1e1e1e;
                    --FontCol_ValeLinkTextColour       : #336699;
                    --FontCol_ValeVisitedTextColour    : #663399;
                    --FontCol_ValeHoverTextColour      : #3377aa;
                    --FontCol_ValeActiveTextColour     : #006600;
                    --FontCol_ValeDisabledTextColour   : #999999;
                    font-size                          : 14px;
                    --FontSize_ValeTitleText           : 1.4rem;
                    --FontSize_ValeTitleHeading01      : 1.10rem;
                    --FontSize_ValeTitleHeading02      : 1.00rem;
                    --FontSize_ValeTitleHeading03      : 0.95rem;
                    --FontSize_ValeTitleHeading04      : 0.90rem;
                    --FontSize_ValeStandardText        : 0.85rem;
                    --FontType_ValeTitleText           : 'Arial', sans-serif;
                    --FontType_ValeTitleHeading01      : 'Arial', sans-serif;
                    --FontType_ValeTitleHeading02      : 'Arial', sans-serif;
                    --FontType_ValeTitleHeading03      : 'Arial', sans-serif;
                    --FontType_ValeTitleHeading04      : 'Arial', sans-serif;
                    --FontType_ValeStandardText        : 'Arial', sans-serif;
                    --FontType_ValeLightText           : 'Arial', sans-serif;
                    --ValeBackgroundColor              : #f0f0f0;
                    --ValeContentBackground            : #ffffff;
                    --ValeBorderColor                  : #dddddd;
                    --ValeHighlightColor               : #006600;
                    --ValePrimaryButtonBg              : #4CAF50;
                    --ValePrimaryButtonHoverBg         : #45a049;
                    --ValePrimaryButtonText            : #ffffff;
                    --ValeSecondaryButtonBg            : #172b3a;
                    --ValeSecondaryButtonHoverBg       : #2a4a63;
                    --ValeSecondaryButtonText          : #ffffff;
                }

                /* Base Layout Styles */
                html, body {
                    margin                             : 0;
                    padding                            : 0;
                    font-family                        : var(--FontType_ValeStandardText);
                    font-size                          : var(--FontSize_ValeStandardText);
                    color                              : var(--FontCol_ValeStandardTextColour);
                    background-color                   : var(--ValeBackgroundColor);
                    height                             : 100vh;
                    overflow                           : hidden;
                }

                body {
                    display                            : flex;
                    flex-direction                     : column;
                }

                /* Header Styles */
                .header {
                    background-color                   : var(--ValeContentBackground);
                    border-bottom                      : 2px solid var(--ValeHighlightColor);
                    padding                            : 15px 20px;
                    display                            : flex;
                    align-items                        : center;
                    justify-content                    : space-between;
                    box-shadow                         : 0 2px 4px rgba(0,0,0,0.1);
                }

                .header-logo {
                    height                             : 40px;
                    width                              : auto;
                }

                .header-title {
                    font-family                        : var(--FontType_ValeTitleText);
                    font-size                          : var(--FontSize_ValeTitleText);
                    color                              : var(--FontCol_ValeTitleTextColour);
                    margin                             : 0;
                    flex-grow                          : 1;
                    text-align                         : center;
                }

                /* Toolbar Styles */
                .toolbar {
                    background-color                   : var(--ValeContentBackground);
                    padding                            : 10px 20px;
                    display                            : flex;
                    align-items                        : center;
                    gap                                : 20px;
                    border-bottom                      : 1px solid var(--ValeBorderColor);
                }

                .search-container {
                    flex-grow                          : 1;
                    max-width                          : 400px;
                }

                .search-input {
                    width                              : 100%;
                    padding                            : 8px 15px;
                    border                             : 1px solid var(--ValeBorderColor);
                    border-radius                      : 4px;
                    font-size                          : var(--FontSize_ValeStandardText);
                    font-family                        : var(--FontType_ValeStandardText);
                }

                .search-input:focus {
                    outline                            : none;
                    border-color                       : var(--ValeHighlightColor);
                }

                /* Button Styles */
                .button {
                    background-color                   : var(--ValeSecondaryButtonBg);
                    color                              : var(--ValeSecondaryButtonText);
                    border                             : none;
                    padding                            : 8px 16px;
                    font-family                        : var(--FontType_ValeStandardText);
                    font-size                          : var(--FontSize_ValeStandardText);
                    cursor                             : pointer;
                    border-radius                      : 4px;
                    transition                         : background-color 0.2s ease;
                }

                .button:hover {
                    background-color                   : var(--ValeSecondaryButtonHoverBg);
                }

                .button-primary {
                    background-color                   : var(--ValePrimaryButtonBg);
                    color                              : var(--ValePrimaryButtonText);
                }

                .button-primary:hover {
                    background-color                   : var(--ValePrimaryButtonHoverBg);
                }

                /* Back Button Styles */
                .back-button {
                    margin-right                       : 10px;
                    font-weight                        : bold;
                }

                .back-button:disabled {
                    background-color                   : var(--ValeBorderColor);
                    color                              : var(--FontCol_ValeDisabledTextColour);
                    cursor                             : not-allowed;
                    opacity                            : 0.6;
                }

                .back-button:disabled:hover {
                    background-color                   : var(--ValeBorderColor);
                }

                /* Content Area Styles */
                .content {
                    flex-grow                          : 1;
                    overflow-y                         : auto;
                    padding                            : 20px;
                    background-color                   : var(--ValeBackgroundColor);
                }

                /* Component Grid Styles */
                .component-grid {
                    display                            : grid;
                    grid-template-columns              : repeat(auto-fill, minmax(200px, 1fr));
                    gap                                : 20px;
                    padding                            : 20px 0;
                }

                .component-card {
                    background-color                   : var(--ValeContentBackground);
                    border                             : 1px solid var(--ValeBorderColor);
                    border-radius                      : 8px;
                    overflow                           : hidden;
                    transition                         : all 0.3s ease;
                    cursor                             : pointer;
                    position                           : relative;
                }

                .component-card:hover {
                    transform                          : translateY(-5px);
                    box-shadow                         : 0 8px 16px rgba(0,0,0,0.15);
                    border-color                       : var(--ValeHighlightColor);
                }

                .component-card.folder {
                    background-color                   : #f8f8f8;
                }

                .component-card.folder .component-thumbnail {
                    display                            : flex;
                    align-items                        : center;
                    justify-content                    : center;
                    font-size                          : 48px;
                    color                              : var(--ValeHighlightColor);
                }

                .component-thumbnail {
                    width                              : 100%;
                    height                             : 150px;
                    object-fit                         : contain;
                    background-color                   : #f5f5f5;
                    padding                            : 10px;
                    box-sizing                         : border-box;
                }
                
                .component-thumbnail img {
                    width                              : 100%;
                    height                             : 100%;
                    object-fit                         : contain;
                }

                .component-info {
                    padding                            : 15px;
                }

                .component-name {
                    font-family                        : var(--FontType_ValeTitleHeading04);
                    font-size                          : var(--FontSize_ValeTitleHeading04);
                    color                              : var(--FontCol_ValeTitleHeadingColour);
                    margin                             : 0 0 5px 0;
                    white-space                        : nowrap;
                    overflow                           : hidden;
                    text-overflow                      : ellipsis;
                }

                .component-description {
                    font-size                          : 0.8rem;
                    color                              : var(--FontCol_ValeStandardTextColour);
                    opacity                            : 0.8;
                }

                /* First Time Setup Styles */
                .first-time-setup {
                    display                            : none;
                    position                           : fixed;
                    top                                : 50%;
                    left                               : 50%;
                    transform                          : translate(-50%, -50%);
                    background-color                   : var(--ValeContentBackground);
                    padding                            : 40px;
                    border-radius                      : 8px;
                    box-shadow                         : 0 10px 30px rgba(0,0,0,0.2);
                    text-align                         : center;
                    max-width                          : 500px;
                    z-index                            : 1000;
                }

                .first-time-setup h2 {
                    color                              : var(--ValeHighlightColor);
                    margin-bottom                      : 20px;
                }

                .first-time-setup p {
                    margin-bottom                      : 30px;
                    line-height                        : 1.6;
                }

                /* Settings Panel Styles */
                .settings-panel {
                    display                            : none;
                    position                           : fixed;
                    top                                : 0;
                    right                              : 0;
                    width                              : 400px;
                    height                             : 100%;
                    background-color                   : var(--ValeContentBackground);
                    box-shadow                         : -4px 0 10px rgba(0,0,0,0.1);
                    z-index                            : 999;
                    overflow-y                         : auto;
                }

                .settings-header {
                    background-color                   : var(--ValeSecondaryButtonBg);
                    color                              : var(--ValeSecondaryButtonText);
                    padding                            : 20px;
                    display                            : flex;
                    justify-content                    : space-between;
                    align-items                        : center;
                }

                .settings-content {
                    padding                            : 20px;
                }

                .settings-group {
                    margin-bottom                      : 30px;
                }

                .settings-label {
                    display                            : block;
                    margin-bottom                      : 10px;
                    font-weight                        : bold;
                }

                .path-display {
                    background-color                   : var(--ValeBackgroundColor);
                    padding                            : 10px;
                    border-radius                      : 4px;
                    margin-bottom                      : 10px;
                    word-break                         : break-all;
                    font-family                        : monospace;
                    font-size                          : 0.9rem;
                }

                /* Loading and Empty States */
                .loading, .empty-state {
                    text-align                         : center;
                    padding                            : 60px 20px;
                    color                              : var(--FontCol_ValeDisabledTextColour);
                }

                .loading-spinner {
                    display                            : inline-block;
                    width                              : 40px;
                    height                             : 40px;
                    border                             : 4px solid var(--ValeBorderColor);
                    border-top-color                   : var(--ValeHighlightColor);
                    border-radius                      : 50%;
                    animation                          : spin 1s linear infinite;
                }

                @keyframes spin {
                    0% { transform: rotate(0deg); }
                    100% { transform: rotate(360deg); }
                }

                /* Overlay Styles */
                .overlay {
                    display                            : none;
                    position                           : fixed;
                    top                                : 0;
                    left                               : 0;
                    width                              : 100%;
                    height                             : 100%;
                    background-color                   : rgba(0,0,0,0.5);
                    z-index                            : 998;
                }

                /* Drag and Drop Styles */
                .dragging {
                    opacity                            : 0.5;
                }

                .drop-indicator {
                    position                           : fixed;
                    pointer-events                     : none;
                    border                             : 2px dashed var(--ValeHighlightColor);
                    background-color                   : rgba(0,102,0,0.1);
                    border-radius                      : 4px;
                    transition                         : all 0.2s ease;
                }

                /* Minimized state during drag */
                body.drag-active {
                    opacity                            : 0.3;
                    pointer-events                     : none;
                    transition                         : opacity 0.2s ease;
                }

                /* Component card drag states */
                .component-card {
                    transition                         : transform 0.2s ease, box-shadow 0.2s ease;
                }

                .component-card:active {
                    cursor                             : grabbing;
                }

                .component-card.dragging {
                    transform                          : scale(0.95);
                    opacity                            : 0.5;
                    box-shadow                         : none;
                }

                /* Drag cursor */
                .component-card:not(.folder) {
                    cursor                             : grab;
                }

                .component-card:not(.folder):active {
                    cursor                             : grabbing;
                }

                /* Breadcrumb Navigation Styles */
                .breadcrumb {
                    padding                            : 10px 20px;
                    background-color                   : var(--ValeContentBackground);
                    border-bottom                      : 1px solid var(--ValeBorderColor);
                    font-size                          : 0.9rem;
                }

                .breadcrumb-item {
                    color                              : var(--FontCol_ValeLinkTextColour);
                    cursor                             : pointer;
                    text-decoration                    : none;
                }

                .breadcrumb-item:hover {
                    text-decoration                    : underline;
                }

                .breadcrumb-separator {
                    margin                             : 0 8px;
                    color                              : var(--FontCol_ValeDisabledTextColour);
                }
            </style>
            <!-- endregion ----------------------------------------------------------------- -->
        </head>
        <body>
            <!-- ----------------------------------------------------------------- -->
            <!-- REGION  |  Main Interface Layout                                   -->
            <!-- ----------------------------------------------------------------- -->
            
            <!-- UI MENU | Header Section -->
            <!-- ----------------------------------------------------------------- -->
            <div class="header">
                <img src="#{logo_url}" alt="Vale Logo" class="header-logo">
                <h1 class="header-title">Vale Component Browser</h1>
                <button class="button" onclick="closeDialog()">Close</button>
            </div>
            
            <!-- UI MENU | Toolbar Section -->
            <!-- ----------------------------------------------------------------- -->
            <div class="toolbar">
                <div class="search-container">
                    <input type="text" class="search-input" placeholder="Search all components globally..." id="searchInput" onkeyup="filterComponents()">
                </div>
                <button class="button back-button" id="backButton" onclick="goBackOneLevel()" disabled>
                    ← Back
                </button>
                <button class="button" onclick="showSettings()">Settings</button>
                <button class="button" onclick="refreshLibrary()">Refresh</button>
                <button class="button button-primary" onclick="backToMainMenu()">Main Menu</button>
            </div>
            
            <!-- UI MENU | Content Area -->
            <!-- ----------------------------------------------------------------- -->
            <div class="content" id="contentArea">
                <div class="breadcrumb" id="breadcrumbNav" style="display: none;">
                    <!-- Breadcrumb navigation will be inserted here -->
                </div>
                
                <div class="loading" id="loadingState">
                    <div class="loading-spinner"></div>
                    <p>Loading components...</p>
                </div>
                
                <div class="empty-state" id="emptyState" style="display: none;">
                    <h2>No Components Found</h2>
                    <p>Please check your library path in settings or add components to the library folder.</p>
                </div>
                
                <div class="component-grid" id="componentGrid" style="display: none;">
                    <!-- Components will be inserted here -->
                </div>
            </div>
            
            <!-- UI MENU | First Time Setup Dialog -->
            <!-- ----------------------------------------------------------------- -->
            <div class="first-time-setup" id="firstTimeSetup">
                <h2>Welcome to Vale Component Browser</h2>
                <p>To get started, please select the folder containing your Vale component library.</p>
                <button class="button button-primary" onclick="selectLibraryPath()">Select Component Library Folder</button>
            </div>
            
            <!-- UI MENU | Settings Panel -->
            <!-- ----------------------------------------------------------------- -->
            <div class="settings-panel" id="settingsPanel">
                <div class="settings-header">
                    <h2>Settings</h2>
                    <button class="button" onclick="hideSettings()">×</button>
                </div>
                <div class="settings-content">
                    <div class="settings-group">
                        <label class="settings-label">Component Library Path:</label>
                        <div class="path-display" id="currentPath">No path configured</div>
                        <button class="button button-primary" onclick="selectLibraryPath()">Change Library Path</button>
                    </div>
                </div>
            </div>
            
            <!-- UI MENU | Overlay -->
            <!-- ----------------------------------------------------------------- -->
            <div class="overlay" id="overlay" onclick="hideSettings()"></div>
            
            <!-- endregion ----------------------------------------------------------------- -->
            
            <!-- ----------------------------------------------------------------- -->
            <!-- REGION  |  JavaScript Functions                                     -->
            <!-- ----------------------------------------------------------------- -->
            <script>
            // MODULE VARIABLES | Component Data and State
            // ------------------------------------------------------------
            let componentsData          = [];                                // <-- Array of component metadata
            let filteredComponents      = [];                                // <-- Filtered component list
            let draggedComponent        = null;                              // <-- Currently dragged component
            let currentPath             = '';                                 // <-- Current browsing path
            let globalSearchActive      = false;                             // <-- Flag for global search mode
            let globalSearchResults     = [];                                // <-- Global search results cache
            let libraryRootPath         = '';                                 // <-- Root library path
            let dialogMinimized         = false;                              // <-- Track dialog state
            
            // FUNCTION | Show First Time Setup
            // ------------------------------------------------------------
            function showFirstTimeSetup() {
                document.getElementById('firstTimeSetup').style.display = 'block';
                document.getElementById('loadingState').style.display = 'none';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Hide First Time Setup
            // ------------------------------------------------------------
            function hideFirstTimeSetup() {
                document.getElementById('firstTimeSetup').style.display = 'none';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Show Settings Panel
            // ------------------------------------------------------------
            function showSettings() {
                // Update the current path display when opening settings
                if (libraryRootPath) {
                    document.getElementById('currentPath').textContent = libraryRootPath;
                }
                document.getElementById('settingsPanel').style.display = 'block';
                document.getElementById('overlay').style.display = 'block';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Hide Settings Panel
            // ------------------------------------------------------------
            function hideSettings() {
                document.getElementById('settingsPanel').style.display = 'none';
                document.getElementById('overlay').style.display = 'none';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Select Library Path
            // ------------------------------------------------------------
            function selectLibraryPath() {
                window.location = 'skp:select_library_path@';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Update Library Path Display
            // ------------------------------------------------------------
            function updateLibraryPath(path) {
                libraryRootPath = path;
                currentPath = path;
                document.getElementById('currentPath').textContent = path || 'No path configured';
                hideFirstTimeSetup();
                hideSettings();
                updateBreadcrumb();
                updateBackButtonState();                                         // <-- Update back button state
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Update Back Button State
            // ------------------------------------------------------------
            function updateBackButtonState() {
                const backButton = document.getElementById('backButton');
                const isAtRoot = !currentPath || currentPath === libraryRootPath;
                backButton.disabled = isAtRoot;                                  // <-- Disable at root level
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Update Breadcrumb Navigation
            // ------------------------------------------------------------
            function updateBreadcrumb() {
                const breadcrumb = document.getElementById('breadcrumbNav');
                if (!currentPath || currentPath === libraryRootPath) {
                    breadcrumb.style.display = 'none';
                    return;
                }
                
                breadcrumb.style.display = 'block';
                breadcrumb.innerHTML = '';
                
                // Create breadcrumb trail
                const pathParts = currentPath.replace(libraryRootPath, '').split(/[\\\/]/).filter(p => p);
                let fullPath = libraryRootPath;
                
                // Add root
                const rootLink = document.createElement('span');
                rootLink.className = 'breadcrumb-item';
                rootLink.textContent = 'Library Root';
                rootLink.onclick = () => navigateToFolder(libraryRootPath);
                breadcrumb.appendChild(rootLink);
                
                // Add path parts
                pathParts.forEach((part, index) => {
                    fullPath += '/' + part;
                    
                    const separator = document.createElement('span');
                    separator.className = 'breadcrumb-separator';
                    separator.textContent = '>';
                    breadcrumb.appendChild(separator);
                    
                    const link = document.createElement('span');
                    link.className = 'breadcrumb-item';
                    link.textContent = part;
                    const pathToNavigate = fullPath;
                    link.onclick = () => navigateToFolder(pathToNavigate);
                    breadcrumb.appendChild(link);
                });
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Load Components Data
            // ------------------------------------------------------------
            function loadComponents(components) {
                componentsData = components;                                 // <-- Store component data
                
                // Only update display if not in global search mode
                if (!globalSearchActive) {
                    filteredComponents = components;                         // <-- Initialize filtered list
                    displayComponents();                                      // <-- Display components
                }
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Display Components in Grid
            // ------------------------------------------------------------
            function displayComponents() {
                const grid = document.getElementById('componentGrid');
                const loading = document.getElementById('loadingState');
                const empty = document.getElementById('emptyState');
                
                // Clear existing content
                grid.innerHTML = '';
                
                // Hide loading state
                loading.style.display = 'none';
                
                if (filteredComponents.length === 0) {
                    grid.style.display = 'none';
                    empty.style.display = 'block';
                    return;
                }
                
                // Show grid
                empty.style.display = 'none';
                grid.style.display = 'grid';
                
                // Create component cards
                filteredComponents.forEach(component => {
                    const card = createComponentCard(component);
                    grid.appendChild(card);
                });
            }
            // ---------------------------------------------------------------
            
            // SUB FUNCTION | Create Component Card Element
            // ---------------------------------------------------------------
            function createComponentCard(component) {
                const card = document.createElement('div');
                card.className = component.type === 'folder' ? 'component-card folder' : 'component-card';
                card.draggable = component.type !== 'folder';
                
                if (component.type === 'folder') {
                    // Setup folder click
                    card.addEventListener('click', () => navigateToFolder(component.path));
                } else {
                    // Setup drag events for components
                    card.addEventListener('dragstart', (e) => handleDragStart(e, component));
                    card.addEventListener('dragend', handleDragEnd);
                    
                    // Setup click event for components
                    card.addEventListener('click', () => insertComponent(component.path));
                }
                
                // Create thumbnail
                const thumbnail = document.createElement('div');
                thumbnail.className = 'component-thumbnail';
                
                if (component.type === 'folder') {
                    thumbnail.innerHTML = '📁';
                } else {
                    const img = document.createElement('img');
                    img.src = component.thumbnail || 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAwIiBoZWlnaHQ9IjE1MCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMjAwIiBoZWlnaHQ9IjE1MCIgZmlsbD0iI2Y1ZjVmNSIvPjx0ZXh0IHg9IjUwJSIgeT0iNTAlIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjOTk5IiBmb250LWZhbWlseT0iQXJpYWwiIGZvbnQtc2l6ZT0iMTQiIGR5PSIuM2VtIj5ObyBQcmV2aWV3PC90ZXh0Pjwvc3ZnPg==';
                    img.alt = component.display_name || component.name;
                    img.draggable = false;  // Prevent image from being dragged
                    thumbnail.appendChild(img);
                }
                
                // Create info section
                const info = document.createElement('div');
                info.className = 'component-info';
                
                const name = document.createElement('div');
                name.className = 'component-name';
                name.textContent = component.display_name || component.name;        // <-- Use display_name for UI
                name.title = component.display_name || component.name;              // <-- Tooltip with clean name
                
                const description = document.createElement('div');
                description.className = 'component-description';
                
                // Show relative path in global search mode, otherwise show description
                if (globalSearchActive && component.relative_path) {
                    description.textContent = component.relative_path;           // <-- Show path in global search
                } else {
                    description.textContent = component.description || (component.type === 'folder' ? 'Folder' : 'Vale component');
                }
                
                info.appendChild(name);
                info.appendChild(description);
                
                card.appendChild(thumbnail);
                card.appendChild(info);
                
                return card;
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Filter Components Based on Search
            // ------------------------------------------------------------
            function filterComponents() {
                const searchTerm = document.getElementById('searchInput').value.toLowerCase();
                
                if (!searchTerm) {
                    // Clear search - return to folder view
                    globalSearchActive = false;
                    filteredComponents = componentsData;
                    displayComponents();
                    return;
                }
                
                // Trigger global search for any non-empty search term
                globalSearchActive = true;
                window.location = 'skp:global_search@' + encodeURIComponent(searchTerm);
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Load Global Search Results
            // ------------------------------------------------------------
            function loadGlobalSearchResults(results) {
                globalSearchResults = results;                                    // <-- Store global results
                globalSearchActive = true;                                       // <-- Set global search mode
                filteredComponents = results;                                    // <-- Use global results for display
                displayComponents();                                              // <-- Update display
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Insert Component into Model
            // ------------------------------------------------------------
            function insertComponent(componentPath) {
                window.location = 'skp:insert_component@' + componentPath;
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Handle Drag Start
            // ------------------------------------------------------------
            function handleDragStart(e, component) {
                draggedComponent = component;
                e.target.classList.add('dragging');
                e.dataTransfer.effectAllowed = 'copy';
                
                // Set the drag data to a special format that indicates this is a SketchUp component
                e.dataTransfer.setData('application/x-sketchup-component', component.path);
                e.dataTransfer.setData('text/plain', component.display_name || component.name);     // <-- Use display name for drag text
                
                // Create a custom drag image
                const dragImage = new Image();
                dragImage.src = 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNTAiIGhlaWdodD0iNTAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iMjUiIGN5PSIyNSIgcj0iMjAiIGZpbGw9IiMwMDY2MDAiIG9wYWNpdHk9IjAuOCIvPjx0ZXh0IHg9IjI1IiB5PSIzMCIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0id2hpdGUiIGZvbnQtc2l6ZT0iMjQiPis8L3RleHQ+PC9zdmc+';
                e.dataTransfer.setDragImage(dragImage, 25, 25);
                
                // Trigger Ruby callback to start preview tool
                setTimeout(() => {
                    window.location = 'skp:start_component_drag@' + component.path;
                }, 100); // Small delay to ensure drag has started
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Handle Drag End
            // ------------------------------------------------------------
            function handleDragEnd(e) {
                e.target.classList.remove('dragging');
                draggedComponent = null;
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Refresh Library
            // ------------------------------------------------------------
            function refreshLibrary() {
                // Clear global search mode when refreshing
                globalSearchActive = false;
                document.getElementById('searchInput').value = '';               // <-- Clear search input
                
                document.getElementById('loadingState').style.display = 'block';
                document.getElementById('componentGrid').style.display = 'none';
                document.getElementById('emptyState').style.display = 'none';
                window.location = 'skp:refresh_library@';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Back to Main Menu
            // ------------------------------------------------------------
            function backToMainMenu() {
                window.location = 'skp:back_to_main@';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Close Dialog
            // ------------------------------------------------------------
            function closeDialog() {
                window.location = 'skp:close_dialog@';
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Navigate to Folder
            // ------------------------------------------------------------
            function navigateToFolder(folderPath) {
                // Clear global search mode when navigating to a folder
                globalSearchActive = false;
                document.getElementById('searchInput').value = '';               // <-- Clear search input
                
                currentPath = folderPath;
                updateBreadcrumb();
                updateBackButtonState();                                         // <-- Update back button state
                window.location = 'skp:navigate_to_folder@' + folderPath;
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Minimize Dialog for Drag Operation
            // ------------------------------------------------------------
            function minimizeForDrag() {
                dialogMinimized = true;
                document.body.classList.add('drag-active');
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Restore Dialog from Drag Operation
            // ------------------------------------------------------------
            function restoreFromDrag() {
                dialogMinimized = false;
                document.body.classList.remove('drag-active');
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Go Back One Folder Level
            // ------------------------------------------------------------
            function goBackOneLevel() {
                if (!currentPath || currentPath === libraryRootPath) {
                    return;                                                      // <-- Can't go back from root
                }
                
                // Clear global search mode when navigating
                globalSearchActive = false;
                document.getElementById('searchInput').value = '';               // <-- Clear search input
                
                // Get parent directory path
                const parentPath = currentPath.replace(/[\\\/][^\\\/]*$/, '');   // <-- Remove last folder from path
                
                // Ensure we don't go above library root
                if (parentPath.length < libraryRootPath.length) {
                    navigateToFolder(libraryRootPath);                           // <-- Go to root if trying to go higher
                } else {
                    navigateToFolder(parentPath);                                // <-- Navigate to parent folder
                }
            }
            // ---------------------------------------------------------------
            
            // FUNCTION | Set up Drag and Drop for Viewport
            // ------------------------------------------------------------
            // Prevent default drag behavior on the document
            document.addEventListener('dragover', function(e) {
                e.preventDefault();
                e.dataTransfer.dropEffect = 'copy';
            });
            
            document.addEventListener('drop', function(e) {
                e.preventDefault();
                // Drop is now handled by the tool in SketchUp
            });
            
            // Detect when drag leaves the dialog window
            document.addEventListener('dragleave', function(e) {
                // Check if drag left the window entirely
                if (e.clientX <= 0 || e.clientY <= 0 || 
                    e.clientX >= window.innerWidth || e.clientY >= window.innerHeight) {
                    // User is dragging outside the dialog - component preview should be active
                }
            });
            
            // Cancel drag if it ends within the dialog
            document.addEventListener('dragend', function(e) {
                if (draggedComponent && !dialogMinimized) {
                    // Drag ended within dialog - cancel the preview tool
                    window.location = 'skp:cancel_drag@';
                }
            });
            </script>
            <!-- endregion ----------------------------------------------------------------- -->
        </body>
        </html>
        HTML
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Callbacks
# -----------------------------------------------------------------------------

    # FUNCTION | Setup Dialog Callbacks
    # ------------------------------------------------------------
    def self.setup_dialog_callbacks
        # CALLBACK | Select Library Path
        # ---------------------------------------------------------------
        @dialog.add_action_callback("select_library_path") do |_|
            select_library_folder                                                 # <-- Trigger folder selection
        end
        
        # CALLBACK | Insert Component
        # ---------------------------------------------------------------
        @dialog.add_action_callback("insert_component") do |_, component_path|
            insert_component_into_model(component_path)                           # <-- Insert component
        end
        
        # CALLBACK | Refresh Library
        # ---------------------------------------------------------------
        @dialog.add_action_callback("refresh_library") do |_|
            load_components_from_library                                          # <-- Reload components
        end
        
        # CALLBACK | Global Search
        # ---------------------------------------------------------------
        @dialog.add_action_callback("global_search") do |_, search_term|
            build_global_components_cache                                         # <-- Build global cache
            
            # Filter global cache based on search term
            if search_term && !search_term.empty?
                search_term_lower = search_term.downcase
                filtered_results = @global_components_cache.select do |item|
                    (item[:name] && item[:name].downcase.include?(search_term_lower)) ||
                    (item[:display_name] && item[:display_name].downcase.include?(search_term_lower)) ||
                    (item[:description] && item[:description].downcase.include?(search_term_lower)) ||
                    (item[:relative_path] && item[:relative_path].downcase.include?(search_term_lower))
                end
            else
                filtered_results = @global_components_cache
            end
            
            # Send filtered results to JavaScript
            js_data = filtered_results.to_json.gsub("'", "\\\\'")                # <-- Escape quotes
            @dialog.execute_script("loadGlobalSearchResults(JSON.parse('#{js_data}'))")  # <-- Update UI
        end
        
        # CALLBACK | Back to Main Menu
        # ---------------------------------------------------------------
        @dialog.add_action_callback("back_to_main") do |_|
            @dialog.close                                                         # <-- Close dialog
            # Main menu will already be open
        end
        
        # CALLBACK | Close Dialog
        # ---------------------------------------------------------------
        @dialog.add_action_callback("close_dialog") do |_|
            @dialog.close                                                         # <-- Close dialog
        end
        
        # CALLBACK | Navigate to Folder
        # ---------------------------------------------------------------
        @dialog.add_action_callback("navigate_to_folder") do |_, folder_path|
            @current_path = folder_path                                           # <-- Update current path
            load_components_from_library                                          # <-- Reload for new path
        end
        
        # CALLBACK | Start Component Drag
        # ---------------------------------------------------------------
        @dialog.add_action_callback("start_component_drag") do |_, component_path|
            start_component_drag_preview(component_path)                          # <-- Start drag preview
        end
        
        # CALLBACK | Cancel Drag
        # ---------------------------------------------------------------
        @dialog.add_action_callback("cancel_drag") do |_|
            model = Sketchup.active_model
            model.select_tool(nil) if model                                      # <-- Cancel any active tool
        end
        
        # CALLBACK | Drop Component
        # ---------------------------------------------------------------
        @dialog.add_action_callback("drop_component") do |_, params_json|
            begin
                params = JSON.parse(params_json)
                component_path = params['path']
                
                if component_path && File.exist?(component_path)
                    insert_component_into_model(component_path)               # <-- Insert component
                end
            rescue => e
                puts "Error dropping component: #{e.message}"
            end
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Library Management Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Select Library Folder via Dialog
    # ------------------------------------------------------------
    def self.select_library_folder
        folder = UI.select_directory(title: "Select Component Library Folder")    # <-- Show folder dialog
        
        if folder && File.directory?(folder)
            @library_path = folder                                                # <-- Set library path
            @current_path = folder                                                # <-- Set current path
            save_configuration                                                    # <-- Save to config
            @dialog.execute_script("updateLibraryPath('#{folder.gsub("\\", "\\\\\\\\")}')")  # <-- Update UI
            load_components_from_library                                          # <-- Load components
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load Components from Library Directory
    # ------------------------------------------------------------
    def self.load_components_from_library
        return unless @library_path && File.directory?(@library_path)            # <-- Validate path
        
        @components_data = []                                                     # <-- Clear existing data
        current_browse_path = @current_path || @library_path                     # <-- Use current path or root
        
        # First, get all folders in current directory excluding Asset-Builder-Files folders
        Dir.entries(current_browse_path).each do |entry|
            next if entry == '.' || entry == '..'                                # <-- Skip special entries
            next if should_exclude_folder?(entry)                                # <-- Skip excluded folders
            full_path = File.join(current_browse_path, entry)
            
            if File.directory?(full_path)
                folder_data = {
                    name: entry,
                    display_name: clean_display_name(entry),
                    path: full_path,
                    type: 'folder',
                    description: "Contains components"
                }
                @components_data << folder_data                                   # <-- Add folder to list
            end
        end
        
        # Then, get all SKP files in current directory only (not recursive)
        # Skip files if current directory is an excluded folder (shouldn't happen but safety check)
        unless should_exclude_folder?(File.basename(current_browse_path))
            Dir.glob(File.join(current_browse_path, "*.skp")).each do |skp_path|
                component_data = create_component_metadata(skp_path)              # <-- Create metadata
                @components_data << component_data if component_data              # <-- Add to array
            end
        end
        
        # Sort: folders first, then components by name (using original name for sort order)
        @components_data.sort_by! { |item| [item[:type] == 'folder' ? 0 : 1, item[:name].downcase] }
        
        # Send data to JavaScript
        js_data = @components_data.to_json.gsub("'", "\\\\'")                    # <-- Escape quotes
        @dialog.execute_script("loadComponents(JSON.parse('#{js_data}'))")       # <-- Update UI
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build Global Components Cache for Search
    # ------------------------------------------------------------
    def self.build_global_components_cache
        return unless @library_path && File.directory?(@library_path)            # <-- Validate path
        
        @global_components_cache = []                                             # <-- Clear existing cache
        scan_directory_recursive(@library_path)                                  # <-- Start recursive scan
        
        # Sort: folders first, then components by name (using original name for sort order)
        @global_components_cache.sort_by! { |item| [item[:type] == 'folder' ? 0 : 1, item[:name].downcase] }
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Recursively Scan Directory for Components
    # ---------------------------------------------------------------
    def self.scan_directory_recursive(directory_path)
        return unless File.directory?(directory_path)                            # <-- Validate directory exists
        
        Dir.entries(directory_path).each do |entry|
            next if entry == '.' || entry == '..'                                # <-- Skip special entries
            next if should_exclude_folder?(entry)                                # <-- Skip excluded folders
            full_path = File.join(directory_path, entry)
            
            if File.directory?(full_path)
                # Add folder to cache
                folder_data = {
                    name: entry,
                    display_name: clean_display_name(entry),
                    path: full_path,
                    type: 'folder',
                    description: "Contains components",
                    relative_path: full_path.sub(@library_path, '').gsub(/^[\\\/]/, '')  # <-- Relative path for display
                }
                @global_components_cache << folder_data                           # <-- Add folder to cache
                
                # Recursively scan subdirectory
                scan_directory_recursive(full_path)                              # <-- Scan subdirectory
            end
        end
        
        # Add SKP files from current directory (excluding files in excluded folders)
        unless should_exclude_folder?(File.basename(directory_path))
            Dir.glob(File.join(directory_path, "*.skp")).each do |skp_path|
                component_data = create_component_metadata(skp_path)              # <-- Create metadata
                if component_data
                    # Add relative path for display
                    component_data[:relative_path] = skp_path.sub(@library_path, '').gsub(/^[\\\/]/, '')
                    @global_components_cache << component_data                    # <-- Add to cache
                end
            end
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Create Component Metadata
    # ---------------------------------------------------------------
    def self.create_component_metadata(skp_path)
        return nil unless File.exist?(skp_path)                                  # <-- Validate file exists
        
        base_name = File.basename(skp_path, '.skp')                              # <-- Get filename without extension
        dir_path = File.dirname(skp_path)                                        # <-- Get directory path
        
        # Try to extract thumbnail from SKP file
        thumbnail_data = extract_skp_thumbnail(skp_path)                         # <-- Extract embedded thumbnail
        
        # If no embedded thumbnail, look for external thumbnail with same name
        if thumbnail_data.nil?
            THUMBNAIL_EXTENSIONS.each do |ext|
                test_path = File.join(dir_path, base_name + ext)                 # <-- Test each extension
                if File.exist?(test_path)
                    thumbnail_data = "file:///" + test_path.gsub(File::SEPARATOR, '/')  # <-- Convert to URL
                    break
                end
            end
        end
        
        # Extract description from filename or metadata
        description = extract_component_description(base_name)                    # <-- Parse description
        
        {
            name: base_name,
            display_name: clean_display_name(base_name),
            path: skp_path,
            thumbnail: thumbnail_data,
            description: description,
            type: 'component'
        }
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Clean Display Name by Removing Series Prefixes
    # ---------------------------------------------------------------
    def self.clean_display_name(original_name)
        cleaned = original_name.dup                                              # <-- Start with copy of original name
        
        # Debug output to see what we're processing
        puts "Cleaning name: '#{original_name}'"                                # <-- Debug: show original name
        
        # Remove various numbered prefix patterns (most specific first)
        # Pattern 1: "XX XX XX " or "XX XX XX" followed by any character
        cleaned = cleaned.gsub(/^\d{2} \d{2} \d{2}\s*/, '')                     # <-- Remove "20 10 01 " or "20 10 01" style prefixes
        
        # Pattern 2: "XX_XX_XX_" or "XX_XX_XX" followed by any character  
        cleaned = cleaned.gsub(/^\d{2}_\d{2}_\d{2}_?/, '')                      # <-- Remove "20_10_01_" or "20_10_01" style prefixes
        
        # Pattern 3: "XX XX XX_" mixed format
        cleaned = cleaned.gsub(/^\d{2} \d{2} \d{2}_/, '')                       # <-- Remove "20 10 01_" style prefixes
        
        # Pattern 4: "XX_XX " or "XX_XX" two-part with optional space
        cleaned = cleaned.gsub(/^\d{2}_\d{2}\s*/, '')                           # <-- Remove "30_01 " or "30_01" style prefixes
        
        # Pattern 5: "XX XX " or "XX XX" two-part with space
        cleaned = cleaned.gsub(/^\d{2} \d{2}\s*/, '')                           # <-- Remove "30 01 " or "30 01" style prefixes
        
        # Pattern 6: Series prefixes like "00-Series_-_", "10-Series_-_", etc.
        cleaned = cleaned.gsub(/^\d{2}-Series[-_]*/, '')                        # <-- Remove number-Series prefix
        
        # Pattern 7: Other common prefixes like "ABC_123_"
        cleaned = cleaned.gsub(/^[A-Z]{2,3}_\d+_/, '')                          # <-- Remove other prefix codes
        
        # Replace underscores and hyphens with spaces
        cleaned = cleaned.gsub(/_/, ' ')                                        # <-- Replace underscores with spaces
        cleaned = cleaned.gsub(/-/, ' ')                                        # <-- Replace hyphens with spaces
        cleaned = cleaned.strip                                                  # <-- Remove leading/trailing spaces
        
        # Clean up multiple spaces
        cleaned = cleaned.gsub(/\s+/, ' ')                                      # <-- Replace multiple spaces with single space
        
        # Capitalize first letter of each word
        cleaned = cleaned.split(' ').map { |word| word.capitalize }.join(' ')   # <-- Capitalize words
        
        # Debug output to see the result
        puts "Cleaned to: '#{cleaned}'"                                         # <-- Debug: show cleaned name
        
        # Return cleaned name or original if nothing left
        cleaned.empty? ? original_name : cleaned                                # <-- Fallback to original if empty
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Extract Thumbnail from SKP File
    # ---------------------------------------------------------------
    def self.extract_skp_thumbnail(skp_path)
        begin
            # Create a temporary directory for thumbnails in config folder
            plugin_root = File.dirname(File.dirname(__FILE__))
            temp_dir = File.join(plugin_root, 'Config_PluginConfigFiles', 'component_thumbnails')
            Dir.mkdir(temp_dir) unless File.directory?(temp_dir)
            
            # Clean up old thumbnails (older than 7 days)
            cleanup_old_thumbnails(temp_dir, 7)
            
            # Generate a unique filename for the thumbnail
            thumb_filename = "#{File.basename(skp_path, '.skp')}_thumb.png"
            temp_file = File.join(temp_dir, thumb_filename)
            
            # Check if thumbnail already exists and is recent
            if File.exist?(temp_file) && (Time.now - File.mtime(temp_file)) < 86400  # 24 hours
                return "file:///" + temp_file.gsub(File::SEPARATOR, '/')
            end
            
            model = Sketchup.active_model
            
            # Load the component definition
            definition = model.definitions.load(skp_path)
            return nil unless definition
            
            # Use save_thumbnail method if available
            if definition.respond_to?(:save_thumbnail)
                success = definition.save_thumbnail(temp_file)
                if success
                    return "file:///" + temp_file.gsub(File::SEPARATOR, '/')
                end
            end
            
            # Clean up the loaded definition to save memory
            # Note: Only remove if it has no instances
            if definition.instances.empty?
                model.definitions.remove(definition)
            end
            
        rescue => e
            puts "Error extracting thumbnail from #{skp_path}: #{e.message}"
        end
        
        nil                                                                       # <-- Return nil if extraction fails
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Clean Up Old Thumbnail Files
    # ---------------------------------------------------------------
    def self.cleanup_old_thumbnails(directory, days_old)
        return unless File.directory?(directory)
        
        threshold_time = Time.now - (days_old * 24 * 60 * 60)                    # <-- Calculate threshold
        
        Dir.glob(File.join(directory, "*.png")).each do |file|
            if File.mtime(file) < threshold_time
                begin
                    File.delete(file)                                             # <-- Delete old thumbnail
                rescue => e
                    puts "Could not delete old thumbnail: #{e.message}"
                end
            end
        end
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Extract Component Description
    # ---------------------------------------------------------------
    def self.extract_component_description(filename)
        # Remove common prefixes and clean up name
        cleaned = filename.gsub(/^[A-Z]{2,3}_\d+_/, '')                          # <-- Remove prefix codes
        cleaned = cleaned.gsub(/_/, ' ')                                         # <-- Replace underscores
        cleaned = cleaned.gsub(/\b\w/) { |match| match.upcase }                  # <-- Capitalize words
        
        cleaned
    end
    # ---------------------------------------------------------------

    # FUNCTION | Insert Component into SketchUp Model
    # ------------------------------------------------------------
    def self.insert_component_into_model(component_path)
        return unless File.exist?(component_path)                                 # <-- Validate file exists
        
        model = Sketchup.active_model                                             # <-- Get active model
        return unless model                                                       # <-- Validate model exists
        
        begin
            # Load component definition
            definition = model.definitions.load(component_path)                   # <-- Load SKP file
            
            # Create tool for placement with component path for 60-Series detection
            model.select_tool(ComponentPlacementTool.new(definition, component_path))  # <-- Activate placement tool with path
            
            @dialog.close                                                         # <-- Close browser temporarily
        rescue => e
            UI.messagebox("Error loading component: #{e.message}")               # <-- Show error
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Component Drag and Drop Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Start Component Drag Preview
    # ------------------------------------------------------------
    def self.start_component_drag_preview(component_path)
        return unless File.exist?(component_path)                                 # <-- Validate file exists
        
        model = Sketchup.active_model                                             # <-- Get active model
        return unless model                                                       # <-- Validate model exists
        
        begin
            # Load component definition
            definition = model.definitions.load(component_path)                   # <-- Load SKP file
            
            # Create enhanced placement tool with drag mode and component path for 60-Series detection
            tool = DragPreviewTool.new(definition, @dialog, component_path)      # <-- Create drag tool with path
            model.select_tool(tool)                                               # <-- Activate tool
            
            # Minimize dialog to allow drag interaction
            @dialog.execute_script("minimizeForDrag()")                           # <-- Minimize dialog
            
        rescue => e
            UI.messagebox("Error starting drag preview: #{e.message}")           # <-- Show error
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Component Placement Tool
# -----------------------------------------------------------------------------

    # CLASS | Component Placement Tool for Interactive Insertion
    # ------------------------------------------------------------
    class ComponentPlacementTool
        def initialize(component_definition, component_path = nil)
            @definition = component_definition                                    # <-- Store component definition
            @component_path = component_path                                      # <-- Store component path for 60-Series detection
            @current_position = Geom::Point3d.new(0, 0, 0)                       # <-- Initial position
            @ip = Sketchup::InputPoint.new                                        # <-- Input point for inference
        end
        
        # SUB FUNCTION | Activate Tool
        # ---------------------------------------------------------------
        def activate
            @ip.clear                                                             # <-- Clear input point
            Sketchup.status_text = "Click to place component. Press Esc to cancel."
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Mouse Move
        # ---------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                                  # <-- Update input point
            @current_position = @ip.position if @ip.valid?                       # <-- Update position
            view.invalidate                                                       # <-- Redraw view
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Left Button Down
        # ---------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            model = Sketchup.active_model                                         # <-- Get active model
            
            model.start_operation("Place Component", true)                       # <-- Start operation
            
            # Check if this is a 60-Series component that needs rotation
            is_60_series = @component_path && ValeDesignSuite::Tools::ComponentBrowser.is_60_series_component?(@component_path)
            
            if is_60_series
                # Apply 90-degree rotation for wall cutting window components
                transformation = ValeDesignSuite::Tools::ComponentBrowser.create_window_component_transformation(@current_position)
            else
                # Standard placement without rotation
                transformation = Geom::Transformation.new(@current_position)      # <-- Create standard transformation
            end
            
            instance = model.entities.add_instance(@definition, transformation)   # <-- Add instance with appropriate transformation
            model.commit_operation                                                # <-- Commit operation
            
            # For 60-Series components, force hole cutter regeneration as separate operation
            if is_60_series
                # Use a small delay to ensure the main operation is completely finished
                UI.start_timer(0.1, false) do
                    ValeDesignSuite::Tools::ComponentBrowser.force_hole_cutter_regeneration(instance)
                end
            end
            
            # Continue placing or finish
            if flags & COPY_MODIFIER_MASK == COPY_MODIFIER_MASK
                # Continue placing if modifier key held
            else
                model.select_tool(nil)                                            # <-- Deactivate tool
                ValeDesignSuite::Tools::ComponentBrowser.show_dialog             # <-- Reopen browser
            end
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Cancel
        # ---------------------------------------------------------------
        def onCancel(reason, view)
            Sketchup.active_model.select_tool(nil)                              # <-- Deactivate tool
            ValeDesignSuite::Tools::ComponentBrowser.show_dialog                # <-- Reopen browser
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Draw Preview
        # ---------------------------------------------------------------
        def draw(view)
            return unless @definition && @current_position                       # <-- Validate prerequisites
            
            # Draw preview outline
            transformation = Geom::Transformation.new(@current_position)          # <-- Create transformation
            view.draw(GL_LINE_LOOP, @definition.bounds.corner(0))               # <-- Draw bounding box
        end
        # ---------------------------------------------------------------
    end
    # ---------------------------------------------------------------

    # CLASS | Enhanced Drag Preview Tool with Live Component Display
    # ------------------------------------------------------------
    class DragPreviewTool
        def initialize(component_definition, dialog, component_path = nil)
            @definition = component_definition                                    # <-- Store component definition
            @dialog = dialog                                                      # <-- Store dialog reference
            @component_path = component_path                                      # <-- Store component path for 60-Series detection
            @current_position = Geom::Point3d.new(0, 0, 0)                       # <-- Initial position
            @ip = Sketchup::InputPoint.new                                        # <-- Input point for inference
            @preview_instance = nil                                               # <-- Preview instance
            @dragging = true                                                      # <-- Start in drag mode
        end
        
        # SUB FUNCTION | Activate Tool
        # ---------------------------------------------------------------
        def activate
            @ip.clear                                                             # <-- Clear input point
            Sketchup.status_text = "Drag to position component. Click to place. Press Esc to cancel."
            
            # Create preview instance at origin
            model = Sketchup.active_model                                         # <-- Get active model
            model.start_operation("Component Drag Preview", true)                # <-- Start operation
            
            # Check if this is a 60-Series component that needs rotation
            if @component_path && ValeDesignSuite::Tools::ComponentBrowser.is_60_series_component?(@component_path)
                # Apply 90-degree rotation for wall cutting window components at origin
                transformation = ValeDesignSuite::Tools::ComponentBrowser.create_window_component_transformation(ORIGIN)
            else
                # Standard placement without rotation
                transformation = Geom::Transformation.new(ORIGIN)                 # <-- Start at origin
            end
            
            @preview_instance = model.entities.add_instance(@definition, transformation)  # <-- Create instance with appropriate transformation
            @preview_instance.material = nil                                      # <-- Clear material for visibility
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Deactivate Tool
        # ---------------------------------------------------------------
        def deactivate(view)
            # Clean up preview instance if not placed
            if @preview_instance && @preview_instance.valid? && @dragging
                @preview_instance.erase!                                          # <-- Remove preview
                Sketchup.active_model.abort_operation                             # <-- Cancel operation
            end
            
            # Restore dialog
            @dialog.execute_script("restoreFromDrag()") if @dialog               # <-- Restore dialog
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Mouse Move
        # ---------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                                  # <-- Update input point
            
            if @ip.valid? && @preview_instance && @preview_instance.valid?
                @current_position = @ip.position                                  # <-- Update position
                
                # Check if this is a 60-Series component that needs rotation
                if @component_path && ValeDesignSuite::Tools::ComponentBrowser.is_60_series_component?(@component_path)
                    # Apply 90-degree rotation for wall cutting window components at current position
                    transformation = ValeDesignSuite::Tools::ComponentBrowser.create_window_component_transformation(@current_position)
                else
                    # Standard placement without rotation
                    transformation = Geom::Transformation.new(@current_position)  # <-- New transformation
                end
                
                @preview_instance.transformation = transformation                 # <-- Apply appropriate transformation
                
                view.invalidate                                                   # <-- Redraw view
            end
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Left Button Down
        # ---------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            return unless @preview_instance && @preview_instance.valid?           # <-- Validate preview
            
            # Store reference to the placed instance for hole cutter regeneration
            placed_instance = @preview_instance
            is_60_series = @component_path && ValeDesignSuite::Tools::ComponentBrowser.is_60_series_component?(@component_path)
            
            # Finalize placement
            @dragging = false                                                     # <-- End drag mode
            
            # Commit the preview instance placement
            Sketchup.active_model.commit_operation                                # <-- Commit operation
            
            # For 60-Series components, force hole cutter regeneration as separate operation
            if is_60_series
                # Use a small delay to ensure the main operation is completely finished
                UI.start_timer(0.1, false) do
                    ValeDesignSuite::Tools::ComponentBrowser.force_hole_cutter_regeneration(placed_instance)
                end
            end
            
            # Check for continuous placement mode
            if flags & COPY_MODIFIER_MASK == COPY_MODIFIER_MASK
                # Start new preview for continuous placement
                @dragging = true                                                  # <-- Continue dragging
                Sketchup.active_model.start_operation("Component Drag Preview", true)
                
                # Check if this is a 60-Series component that needs rotation for continuous placement
                if is_60_series
                    # Apply 90-degree rotation for wall cutting window components
                    transformation = ValeDesignSuite::Tools::ComponentBrowser.create_window_component_transformation(@current_position)
                else
                    # Standard placement without rotation
                    transformation = Geom::Transformation.new(@current_position)  # <-- Current position
                end
                
                @preview_instance = Sketchup.active_model.entities.add_instance(@definition, transformation)
                @preview_instance.material = nil                                  # <-- Clear any material
            else
                # Deactivate tool and reopen browser
                Sketchup.active_model.select_tool(nil)                           # <-- Deactivate tool
                ValeDesignSuite::Tools::ComponentBrowser.show_dialog             # <-- Reopen browser
            end
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Cancel
        # ---------------------------------------------------------------
        def onCancel(reason, view)
            # Clean up will be handled by deactivate
            Sketchup.active_model.select_tool(nil)                              # <-- Deactivate tool
            ValeDesignSuite::Tools::ComponentBrowser.show_dialog                # <-- Reopen browser
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Key Down
        # ---------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            # Allow shift key for continuous placement
            if key == COPY_MODIFIER_KEY || key == CONSTRAIN_MODIFIER_KEY
                Sketchup.status_text = "Hold Shift and click to place multiple copies."
            end
        end
        # ---------------------------------------------------------------
        
        # SUB FUNCTION | Handle Key Up
        # ---------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            # Reset status when modifier released
            if key == COPY_MODIFIER_KEY || key == CONSTRAIN_MODIFIER_KEY
                Sketchup.status_text = "Drag to position component. Click to place. Press Esc to cancel."
            end
        end
        # ---------------------------------------------------------------
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module ComponentBrowser
  end # module Tools
end # module ValeDesignSuite 