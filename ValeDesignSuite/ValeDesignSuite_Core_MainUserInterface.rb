# =============================================================================
# VALEDESIGNSUITE - UI MODULE
# =============================================================================
#
# FILE       : ValeDesignSuite_Core_MainUserInterface.rb
# NAMESPACE  : ValeDesignSuite
# MODULE     : MainUserInterface
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Main User Interface Dialog and Selection Observer for ValeDesignSuite
# CREATED    : 2025
#
# DESCRIPTION:
# - This module handles the main user interface for the Vale Design Suite plugin.
# - It utilises HTML and CSS to create a modern, responsive dialog within SketchUp.
# - The interface is designed to reflect the Vale brand's aesthetics and usability standards.
# - The dialog is initialized with specific dimensions and positioning for optimal user experience.
# - The HTML content includes necessary meta tags and links to external resources for styling.
# - Loaded automatically by ValeDesignSuite_Core_PluginScript.rb
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 21-May-2025 - Version 0.0.1
# - Initial Setup
# - Created the main user interface module  
# - Added the show_main_dialog method
# - Added the HTML content for the main dialog
#
# 21-May-2025 - Version 0.0.2
# - UI Enhancement and Tool Integration
# - Added multi-page UI with navigation between pages
# - Created dedicated Roof Lantern Tool page
# - Added navigation controls (back button)
# - Improved button styling and added tool description cards
# - Connected UI to RoofLanternTools functionality
# - Added collapsible help section
#
# 21-May-2025 - Version 0.0.6
# - Future Development
# - 
# - 
#
# =============================================================================

# Load required libraries
require 'sketchup.rb'
require 'json'
require_relative 'ValeDesignSuite_Core_PluginDebuggingAndDiagnosticTools'
require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic'
require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsDataSerializer'
require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsConfigurator'
require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator'
require_relative 'Tools_WindowPanelConfigurator/ValeDesignSuite_Tools_WindowPanelConfigurator'
require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkDebugTools'
require_relative 'Tools_ComponentBrowser/ValeDesignSuite_Tools_ComponentBrowser'
require_relative 'Tools_ImageRenderingTools/ValeDesignSuite_RenderingTools__WatercolourRenderer'
require_relative 'Tools_ValeSketchTools/ValeSketchTools__DrawingAid__CreateCurrentSceneCameraVanishingPoints'

module ValeDesignSuite

    # DEBUG TOOLS REFERENCE
    # ------------------------------------------------------------
    DebugTools = ValeDesignSuite::Tools::FrameworkDebugTools

    # -----------------------------------------------------------------------------
    # REGION | Framework Selection Observer Class
    # -----------------------------------------------------------------------------

        # CLASS | Framework Selection Observer for Component Tracking
        # ------------------------------------------------------------
        class FrameworkSelectionObserver < Sketchup::SelectionObserver
            
            # SUB FUNCTION | Initialize Observer with Dialog Reference
            # ---------------------------------------------------------------
            def initialize(dialog_ref)
                @dialog_ref = dialog_ref                                         # <-- Store the direct dialog reference
            end
            # ---------------------------------------------------------------

            # FUNCTION | Handle Selection Change Events
            # ------------------------------------------------------------
            def onSelectionBulkChange(selection)
                DebugTools.debug_ui("======= SELECTION CHANGED ========")
                
                # Check if we have a valid dialog reference
                unless @dialog_ref && @dialog_ref.respond_to?(:execute_script)
                    DebugTools.debug_ui("No valid dialog reference available")
                    return                                                       # <-- Exit if no dialog
                end
                
                # Check if selection is empty
                if selection.empty?
                    DebugTools.debug_ui("Selection is empty - clearing UI")
                    @dialog_ref.execute_script("app.clearData();")              # <-- Clear UI data
                    return                                                       # <-- Exit for empty selection
                end
                
                # Process each selected entity
                selection.each do |entity|
                    DebugTools.debug_ui("Processing selected entity: #{entity.class}")
                    
                    # Only process ComponentInstance entities
                    next unless entity.is_a?(Sketchup::ComponentInstance)
                    
                    DebugTools.debug_ui("Selected component: #{entity.name} (EntityID: #{entity.entityID})")
                    
                    # Check if this component has framework assembly data
                    assembly_id = entity.get_attribute(
                        ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_INFO_DICT_NAME,
                        ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_ID_KEY
                    )
                    
                    if assembly_id
                        DebugTools.debug_ui("Found framework component with AssemblyID: #{assembly_id}")
                        
                        # Load framework data for this component
                        framework_data = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.load_framework_data_from_component(entity.entityID)
                        
                        if framework_data
                            DebugTools.debug_ui("Successfully loaded framework data for #{assembly_id}")
                            
                            # Send data to JavaScript UI
                            data_for_js = framework_data.to_json
                            @dialog_ref.execute_script("app.loadData(#{data_for_js}, #{entity.entityID});")
                            
                            # Show success message
                            framework_name = "Unknown"
                            if framework_data['frameworkMetadata'] && 
                               framework_data['frameworkMetadata'].is_a?(Array) && 
                               !framework_data['frameworkMetadata'].empty? &&
                               framework_data['frameworkMetadata'][0]['FrameworkName']
                                framework_name = framework_data['frameworkMetadata'][0]['FrameworkName']
                            end
                            
                            @dialog_ref.execute_script("app.showSaveStatusMessage('Loaded framework: #{framework_name}', true);")
                            
                            DebugTools.debug_ui("Framework data sent to UI for component: #{entity.name}")
                        else
                            DebugTools.debug_ui("Failed to load framework data for component: #{entity.name}")
                            @dialog_ref.execute_script("app.showSaveStatusMessage('Failed to load framework data', false);")
                        end
                    else
                        DebugTools.debug_ui("Selected component has no framework assembly data: #{entity.name}")
                        # Clear the UI since this isn't a framework component
                        @dialog_ref.execute_script("app.clearData();")
                    end
                    
                    # Only process the first framework component found
                    break if assembly_id
                end
                
                DebugTools.debug_ui("======= SELECTION PROCESSING COMPLETE ========")
            end
            # ---------------------------------------------------------------
            
        end
        # endregion ----------------------------------------------------

    # endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Main User Interface Module
# -----------------------------------------------------------------------------

# MODULE | Main User Interface Dialog Management
# -----------------------------------------------------------------------------
module MainUserInterface
@dialog_instance = nil                                               # <-- Module instance variable to hold the dialog
@framework_selection_observer = nil                                  # <-- Framework selection observer instance
# -----------------------------------------------------------------------------



# -----------------------------------------------------------------------------
# REGION | Development Utilities - Script Reloading Tools
# -----------------------------------------------------------------------------
# Added Version Version: 0.8.2  -  15-Aug-2025
# - Hot-reload functionality for ValeDesignSuite Ruby scripts during development
# - Allows developers to reload all .rb files without restarting SketchUp
# - Provides comprehensive error handling and reporting for script loading issues
# - Includes exempt file/folder system for excluding problematic development scripts
# - Automatically refreshes UI inspectors and rebuilds HtmlDialog after reload
# - Supports both individual file and folder-level exclusions for flexible control

    # FUNCTION | Reload All ValeDesignSuite Ruby Scripts (Development Only)
    # ------------------------------------------------------------
    def self.reload_vale_design_suite_scripts
        base_dir = ValeDesignSuite::PLUGIN_ROOT                               # <-- ValeDesignSuite root directory
        success_count = 0                                                     # <-- Track successful reloads
        failed_count = 0                                                      # <-- Track failed reloads
        results = []                                                          # <-- Store results for reporting

        # -----------------------------------------------------------------------------
        # REGION | Exempt Files and Folders Configuration
        # -----------------------------------------------------------------------------
        # Add files or folders to skip during reload. Use relative paths from plugin root.
        # For files: "ScriptHeaderTemplate.rb" or "SomeFolder/BadScript.rb"
        # For folders: "10_Dev_Templates" or "02_Dev__ScriptTestingSandbox"
        
        exempt_files_and_folders = [
            "ScriptHeaderTemplate.rb",                                        # <-- Specific broken template file
            "00_Dev_Temp--Earmarked-For-Deleted",                             # <-- Earmarked for deletion folder
            "00_DEV_-_Developer-Utilities",                                   # <-- Developer utilities folder
            "01_Dev__SketchUpDeveloper__UtilityScripts",                      # <-- Developer utility scripts
            "02_Dev__ScriptTestingSandbox",                                   # <-- Development sandbox folder
            "03_Dev__SimpleWebUiScripts",                                     # <-- Simple Web UI Scripts
            "10_Dev_Templates",                                               # <-- Template files folder
            "20_Dev_External-Scripts",                                        # <-- External scripts folder
            "100_PluginDocumentation",                                        # <-- Plugin documentation folder
            "Docs__PluginDocumentation",                                      # <-- Plugin documentation folder
            "Docs__ValeSketchUpConventions"                                   # <-- Vale SketchUp Conventions folder

        ]
        # endregion -------------------------------------------------------------------

        # Print header
        puts "\n" + "=" * 80
        puts "VALEDESIGNSUITE - SCRIPT RELOAD REPORT"
        puts "=" * 80

        # Find all .rb files under the plugin root
        all_rb_files = Dir.glob(File.join(base_dir, '**', '*.rb')).sort
        total_files = all_rb_files.length
        
        # Filter out exempt files and folders
        skipped_files = all_rb_files.select do |file_path|
            relative_path = file_path.gsub(base_dir + File::SEPARATOR, '')
            
            exempt_files_and_folders.any? do |exempt_item|
                if exempt_item.include?('/')                                       # <-- Folder path
                    relative_path.start_with?(exempt_item + '/')
                elsif exempt_item.include?('.')                                    # <-- File with extension
                    relative_path.end_with?(exempt_item) || relative_path == exempt_item
                else                                                               # <-- Folder name without path
                    relative_path.start_with?(exempt_item + '/') || relative_path.include?('/' + exempt_item + '/')
                end
            end
        end
        
        all_rb_files.reject! { |file_path| skipped_files.include?(file_path) }
        
        puts "DISCOVERED #{total_files} Ruby files total, #{all_rb_files.length} files to load"
        if skipped_files.any?
            puts "EXEMPTED #{skipped_files.length} files/folders from loading (see exempt list)"
        end
        puts "-" * 80

        # Process each file
        all_rb_files.each do |rb_file|
            relative_path = rb_file.gsub(base_dir + File::SEPARATOR, '')          # <-- Get relative path for display
            begin
                load rb_file                                                      # <-- Force re-evaluation of Ruby file
                results << { file: relative_path, status: :success }
                success_count += 1
            rescue SyntaxError => e
                # Handle syntax errors specifically
                error_msg = e.message.split("\n").first || "Syntax error"        # <-- Get first line of syntax error
                results << { file: relative_path, status: :failed, error: "SYNTAX ERROR: #{error_msg}" }
                failed_count += 1
            rescue LoadError => e
                # Handle load errors (missing dependencies, etc.)
                results << { file: relative_path, status: :failed, error: "LOAD ERROR: #{e.message}" }
                failed_count += 1
            rescue => e
                # Handle all other errors
                results << { file: relative_path, status: :failed, error: "ERROR: #{e.message}" }
                failed_count += 1
            end
        end

        # Display columnized results
        max_filename_length = results.map { |r| r[:file].length }.max || 0       # <-- Find longest filename
        column_width = [max_filename_length + 5, 40].max                         # <-- Set minimum column width

        results.each do |result|
            filename = "`#{result[:file]}`"
            padding = " " * (column_width - filename.length)
            
            if result[:status] == :success
                puts "#{filename}#{padding} = ✅ Successfully Reloaded"
            else
                puts "#{filename}#{padding} = ❌ Failed To Reload"
                puts "#{' ' * column_width}   Error: #{result[:error]}"
            end
        end

        # Print summary
        puts "-" * 80
        puts "SUMMARY: #{success_count} successful, #{failed_count} failed, #{success_count + failed_count} total"
        puts "=" * 80
        puts ""

        # Refresh UI inspectors after code reload (official API)
        UI.refresh_inspectors if UI.respond_to?(:refresh_inspectors)

        # Clean up duplicate menu items after successful reload
        begin
            puts "CLEANING UP: Removing duplicate extension menu items..."
            cleanup_duplicate_extension_menu_items                              # <-- Remove duplicate menu items
            puts "CLEANUP COMPLETE: Extension menu duplicates removed"
        rescue => e
            puts "Menu cleanup failed: #{e.message}"
        end

        # Attempt to rebuild the main UI so changes take effect immediately
        begin
            if @dialog_instance && @dialog_instance.respond_to?(:visible?) && @dialog_instance.visible?
                @dialog_instance.close                                           # <-- Close existing dialog instance
            end
            # Re-open the dialog with updated code
            show_main_dialog
        rescue => e
            puts "UI rebuild after reload failed: #{e.message}"
        end

        return success_count
    end
    # ---------------------------------------------------------------


    # SUB FUNCTION | Clean Up Duplicate Extension Menu Items After Reload
    # ---------------------------------------------------------------
    def self.cleanup_duplicate_extension_menu_items
        # This method removes duplicate menu items that get created when scripts are reloaded.
        # It focuses on cleaning up the Extensions menu and other common menu locations
        # where ValeDesignSuite components add items.
        
        begin
            # Track what we're cleaning up
            removed_count = 0
            
            # Get the Extensions menu
            extensions_menu = UI.menu("Extensions")                             # <-- Get Extensions menu reference
            
            if extensions_menu
                # Get all menu items in Extensions menu
                menu_items = []
                
                # SketchUp doesn't provide direct access to menu items, but we can use reflection
                # to access the internal menu structure for cleanup purposes
                begin
                    # Use Ruby's reflection to access SketchUp's internal menu structure
                    # This is a development-only feature for cleaning up during script reloads
                    if extensions_menu.respond_to?(:instance_variable_get)
                        # Check if we can access the menu's internal item list
                        items = extensions_menu.instance_variable_get(:@items) rescue nil
                        
                        if items && items.respond_to?(:each)
                            # Look for duplicate Vale items by name pattern matching
                            vale_items = []
                            
                            items.each_with_index do |item, index|
                                item_text = ""
                                
                                # Try to get the menu item text/name
                                if item.respond_to?(:text)
                                    item_text = item.text
                                elsif item.respond_to?(:name)
                                    item_text = item.name
                                elsif item.respond_to?(:caption)
                                    item_text = item.caption
                                end
                                
                                # Check if this is a Vale-related menu item
                                if item_text.match(/Vale|VGH|Framework/i)
                                    vale_items << { item: item, index: index, text: item_text }
                                end
                            end
                            
                            # Remove duplicates (keep only the first occurrence of each unique name)
                            seen_names = []
                            vale_items.reverse.each do |vale_item|  # Reverse to remove from end first
                                if seen_names.include?(vale_item[:text])
                                    # This is a duplicate - attempt to remove it
                                    begin
                                        items.delete_at(vale_item[:index]) if vale_item[:index] < items.length
                                        removed_count += 1
                                        puts "  → Removed duplicate: '#{vale_item[:text]}'"
                                    rescue => e
                                        puts "  → Failed to remove '#{vale_item[:text]}': #{e.message}"
                                    end
                                else
                                    seen_names << vale_item[:text]
                                end
                            end
                        end
                    end
                rescue => e
                    puts "  → Menu reflection cleanup failed: #{e.message}"
                    # Fallback: If reflection fails, we can't clean up automatically
                    # The user will need to restart SketchUp for full cleanup
                end
            end
            
            # Also clean up Tools menu if we can
            tools_menu = UI.menu("Tools")                                       # <-- Get Tools menu reference
            if tools_menu
                # Apply similar cleanup logic to Tools menu for Framework Configurator items
                begin
                    if tools_menu.respond_to?(:instance_variable_get)
                        items = tools_menu.instance_variable_get(:@items) rescue nil
                        
                        if items && items.respond_to?(:each)
                            framework_items = []
                            
                            items.each_with_index do |item, index|
                                item_text = ""
                                
                                if item.respond_to?(:text)
                                    item_text = item.text
                                elsif item.respond_to?(:name)
                                    item_text = item.name
                                elsif item.respond_to?(:caption)
                                    item_text = item.caption
                                end
                                
                                # Look for Framework Configurator items
                                if item_text.match(/Vale.*Framework|Framework.*Configurator/i)
                                    framework_items << { item: item, index: index, text: item_text }
                                end
                            end
                            
                            # Remove duplicates from Tools menu
                            seen_names = []
                            framework_items.reverse.each do |framework_item|
                                if seen_names.include?(framework_item[:text])
                                    begin
                                        items.delete_at(framework_item[:index]) if framework_item[:index] < items.length
                                        removed_count += 1
                                        puts "  → Removed duplicate from Tools: '#{framework_item[:text]}'"
                                    rescue => e
                                        puts "  → Failed to remove from Tools '#{framework_item[:text]}': #{e.message}"
                                    end
                                else
                                    seen_names << framework_item[:text]
                                end
                            end
                        end
                    end
                rescue => e
                    puts "  → Tools menu cleanup failed: #{e.message}"
                end
            end
            
            # Clean up Plugins menu for deep nested edges script
            plugins_menu = UI.menu("Plugins")                                   # <-- Get Plugins menu reference
            if plugins_menu
                begin
                    if plugins_menu.respond_to?(:instance_variable_get)
                        items = plugins_menu.instance_variable_get(:@items) rescue nil
                        
                        if items && items.respond_to?(:each)
                            # Look for Vale-related submenu duplicates
                            vale_submenu_items = []
                            
                            items.each_with_index do |item, index|
                                item_text = ""
                                
                                if item.respond_to?(:text)
                                    item_text = item.text
                                elsif item.respond_to?(:name)
                                    item_text = item.name
                                elsif item.respond_to?(:caption)
                                    item_text = item.caption
                                end
                                
                                # Look for Paint Deep Nested Edges and similar Vale tools
                                if item_text.match(/Vale.*Material|Paint.*Deep.*Nested|ValeDesignSuite/i)
                                    vale_submenu_items << { item: item, index: index, text: item_text }
                                end
                            end
                            
                            # Remove duplicate submenus
                            seen_names = []
                            vale_submenu_items.reverse.each do |submenu_item|
                                if seen_names.include?(submenu_item[:text])
                                    begin
                                        items.delete_at(submenu_item[:index]) if submenu_item[:index] < items.length
                                        removed_count += 1
                                        puts "  → Removed duplicate from Plugins: '#{submenu_item[:text]}'"
                                    rescue => e
                                        puts "  → Failed to remove from Plugins '#{submenu_item[:text]}': #{e.message}"
                                    end
                                else
                                    seen_names << submenu_item[:text]
                                end
                            end
                        end
                    end
                rescue => e
                    puts "  → Plugins menu cleanup failed: #{e.message}"
                end
            end
            
            puts "  → Successfully removed #{removed_count} duplicate menu items"
            
            # Note about complete cleanup
            if removed_count == 0
                puts "  → No accessible duplicates found (SketchUp menu API limitations)"
                puts "  → For complete cleanup, restart SketchUp after development session"
            end
            
        rescue => e
            puts "  → Menu cleanup encountered error: #{e.message}"
            puts "  → Menu duplicates may persist until SketchUp restart"
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------



# FUNCTION | Show Main Dialog Interface
# ------------------------------------------------------------
def self.show_main_dialog
    plugin_root = File.dirname(__FILE__)                            # <-- Get plugin root directory
    button_image_path = File.join(plugin_root, 'Assets_PluginAssets', 'TemporaryRoofLanternButtonGraphic.png')
    logo_image_path = File.join(plugin_root, 'Assets_ValeBrandAssets', 'ValeHeaderImage_ValeLogo_HorizontalFormat.png')
    framework_configurator_js_path = File.join(plugin_root, 'Tools_FrameworkTools', 'ValeDesignSuite_Tools_FrameworkConfigurator_Logic.js')
    button_image_url = "file:///" + button_image_path.gsub(File::SEPARATOR, '/')
    logo_image_url = "file:///" + logo_image_path.gsub(File::SEPARATOR, '/')
    framework_configurator_js_url = "file:///" + framework_configurator_js_path.gsub(File::SEPARATOR, '/')

    # CHECK IF DIALOG ALREADY EXISTS AND IS VISIBLE
    if @dialog_instance && @dialog_instance.respond_to?(:visible?) && @dialog_instance.visible?
        @dialog_instance.bring_to_front                             # <-- Bring existing dialog to front
        return
    end
    
    # CREATE NEW DIALOG INSTANCE
    @dialog_instance = ::UI::HtmlDialog.new(
        dialog_title: "Vale Design Suite",
        preferences_key: "ValeDesignSuite",
        style: ::UI::HtmlDialog::STYLE_DIALOG,
        width: 1100,
        height: 800,
        left: 150,
        top: 150,
        resizable: true
    )
    
html_content = <<-HTML
<!DOCTYPE html>
    <html>
        <head>
            <meta charset="UTF-8">
            <title>Vale Design Suite</title>

            <!-- #region =============================================================== -->
            <!-- -   -   -   -   -   -   FONT LOADER SECTION   -   -   -   -   -   -     -->
            <!-- ======================================================================= -->
            <style>
                @font-face {
                    font-family   : 'Open Sans Regular';
                    src           : url('https://www.noble-architecture.com/assets/AD04_-_LIBR_-_Common_-_Front-Files/AD04_01_-_Standard-Font_-_Open-Sans-Regular.ttf') format('truetype');
                    font-weight   : normal;
                    font-style    : normal;
                    font-display  : swap;
                }
                @font-face {
                    font-family   : 'Open Sans Semibold';
                    src           : url('https://www.noble-architecture.com/assets/AD04_-_LIBR_-_Common_-_Front-Files/AD04_02_-_Standard-Font_-_Open-Sans-SemiBold.ttf') format('truetype');
                    font-weight   : 600;
                    font-style    : normal;
                    font-display  : swap;
                }
                @font-face {
                    font-family   : 'Open Sans Light';
                    src           : url('https://www.noble-architecture.com/assets/AD04_-_LIBR_-_Common_-_Front-Files/AD04_03_-_Standard-Font_-_Open-Sans-Light.ttf') format('truetype');
                    font-weight   : 300;
                    font-style    : normal;
                    font-display  : swap;
                }
            </style>
            <!-- #endregion -->
            
            
        <!-- #region ================================================================= -->
        <!-- -   -   -   -     MAIN PLUGIN STYLESHEET SECTION     -   -   -   -   -  -->
        <!-- ======================================================================= -->
            <style>
                :root {
                    --FontCol_ValeTitleTextColour      : #172b3a;
                    --FontCol_ValeTitleHeadingColour   : #172b3a;
                    --FontCol_ValeStandardTextColour   : #1e1e1e;
                    --FontCol_ValeLinkTextColour       : #336699;
                    --FontCol_ValeVisitedTextColour    : #663399;
                    --FontCol_ValeHoverTextColour      : #3377aa;
                    --FontCol_ValeActiveTextColour     : #006600;
                    --FontCol_ValeDisabledTextColour   : #999999;
                    font-size                          : 16px;
                    --FontSize_ValeTitleText           : 2.25rem;
                    --FontSize_ValeTitleHeading01      : 1.75rem;
                    --FontSize_ValeTitleHeading02      : 1.25rem;
                    --FontSize_ValeTitleHeading03      : 1.10rem;
                    --FontSize_ValeTitleHeading04      : 1.00rem;
                    --FontSize_ValeStandardText        : 1.00rem;
                    --FontType_ValeTitleText           : 'Open Sans Semibold';
                    --FontType_ValeTitleHeading01      : 'Open Sans Semibold';
                    --FontType_ValeTitleHeading02      : 'Open Sans Semibold';
                    --FontType_ValeTitleHeading03      : 'Open Sans Semibold';
                    --FontType_ValeTitleHeading04      : 'Open Sans Semibold';
                    --FontType_ValeStandardText        : 'Open Sans Regular';
                    --FontType_ValeLightText           : 'Open Sans Light';
                    --ValeBackgroundColor              : #f0f0f0;
                    --ValeContentBackground            : #ffffff;
                    --ValeBorderColor                  : #dddddd;
                    --ValeHighlightColor               : #006600;
                    --ValePrimaryButtonBg              : #006600;
                    --ValePrimaryButtonHoverBg         : #008800;
                    --ValePrimaryButtonText            : #ffffff;
                    --ValeSecondaryButtonBg            : #172b3a;
                    --ValeSecondaryButtonHoverBg       : #2a4a63;
                    --ValeSecondaryButtonText          : #ffffff;
                }
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
                    text-align                         : center;
                    display                            : flex;
                    flex-direction                     : column;
                }
                h1 {
                    font-family                        : var(--FontType_ValeTitleText);
                    font-size                          : var(--FontSize_ValeTitleText);
                    color                              : var(--FontCol_ValeTitleTextColour);
                    margin-bottom                      : 20px;
                }
                h2 {
                    font-family                        : var(--FontType_ValeTitleHeading01);
                    font-size                          : var(--FontSize_ValeTitleHeading01);
                    color                              : var(--FontCol_ValeTitleHeadingColour);
                    margin-bottom                      : 15px;
                }
                h3 {
                    font-family                        : var(--FontType_ValeTitleHeading02);
                    font-size                          : var(--FontSize_ValeTitleHeading02);
                    color                              : var(--FontCol_ValeTitleHeadingColour);
                    margin-bottom                      : 12px;
                }
                h4 {
                    font-family                        : var(--FontType_ValeTitleHeading03);
                    font-size                          : var(--FontSize_ValeTitleHeading03);
                    color                              : var(--FontCol_ValeTitleHeadingColour);
                    margin-bottom                      : 10px;
                }
                h5 {
                    font-family                        : var(--FontType_ValeTitleHeading04);
                    font-size                          : var(--FontSize_ValeTitleHeading04);
                    color                              : var(--FontCol_ValeTitleHeadingColour);
                    margin-bottom                      : 8px;
                }
                p {
                    font-family                        : var(--FontType_ValeStandardText);
                    font-size                          : var(--FontSize_ValeStandardText);
                    color                              : var(--FontCol_ValeStandardTextColour);
                    margin-bottom                      : 10px;
                    line-height                        : 1.5;
                }
                a {
                    color                              : var(--FontCol_ValeLinkTextColour);
                    text-decoration                    : none;
                }
                a:visited {
                    color                              : var(--FontCol_ValeVisitedTextColour);
                }
                a:hover {
                    color                              : var(--FontCol_ValeHoverTextColour);
                    text-decoration                    : underline;
                }
                a:active {
                    color                              : var(--FontCol_ValeActiveTextColour);
                }
                .message {
                    margin-top                         : 20px;
                    padding                            : 20px;
                    background-color                   : var(--ValeContentBackground);
                    border                             : 1px solid var(--ValeBorderColor);
                    border-radius                      : 5px;
                    box-shadow                         : 0 2px 5px rgba(0, 0, 0, 0.1);
                }
                .message h2 {
                    color                              : var(--ValeHighlightColor);
                    margin-top                         : 0;
                }
                
                /* Page System Styles */
                .page {
                    display                            : none;
                    width                              : 100%;
                    flex-grow                          : 1;
                    opacity                            : 0;
                    transition                         : opacity 0.3s ease-in-out;
                    overflow-y                         : auto;
                    padding                            : 20px;
                    box-sizing                         : border-box;
                }
                
                .page.active {
                    display                            : flex;
                    flex-direction                     : column;
                    opacity                            : 1;
                }

                #home.page.active {
                    align-items                        : center; 
                }

                .tool-cards-container {
                    display                            : flex;
                    flex-wrap                          : wrap; 
                    justify-content                    : center;
                    align-items                        : flex-start; 
                    width                              : 100%; 
                    padding                            : 10px 0; 
                }

                .tool-cards-container .tool-card {
                    /* This the the main cards that the buttons are placed on */
                    width                              : 20.00rem;
                    min-height                         : 28.00rem;
                    margin-top                         : 01.00rem;
                    margin-bottom                      : 01.00rem;
                    margin-left                        : 02.00rem;
                    margin-right                       : 02.00rem;
                }
                
                .back-button {
                    display                            : inline-flex;
                    align-items                        : center;
                    padding                            : 8px 16px;
                    background-color                   : var(--ValeSecondaryButtonBg);
                    color                              : var(--ValeSecondaryButtonText);
                    border                             : none;
                    border-radius                      : 4px;
                    cursor                             : pointer;
                    font-family                        : var(--FontType_ValeStandardText);
                    font-size                          : 1rem;
                    margin-bottom                      : 20px;
                    margin-top                         : 10px;
                    transition                         : background-color 0.2s ease-in-out;
                    flex-shrink                        : 0;
                }
                
                .back-button:hover {
                    background-color                   : var(--ValeSecondaryButtonHoverBg);
                    text-decoration                    : none;
                }
                
                .back-button:before {
                    content                            : "←";
                    margin-right                       : 8px;
                    font-size                          : 1.2rem;
                }

                /* Tool Card Styles */
                .tool-card {
                    position                           : relative;
                    background-color                   : var(--ValeContentBackground);
                    border-radius                      : 10px;
                    box-shadow                         : 0 6px 12px rgba(0,0,0,0.1);
                    overflow                           : hidden;
                    transition                         : transform 0.3s ease, box-shadow 0.3s ease;
                    cursor                             : pointer;
                }
                
                /* Default styling for tool-cards not in the flex container */
                .tool-card:not(.tool-cards-container .tool-card) { 
                        width                             : 300px;
                        margin                            : 20px auto;
                }

                .tool-card:hover {
                    transform                          : translateY(-5px);
                    box-shadow                         : 0 12px 24px rgba(0,0,0,0.15);
                }
                
                .tool-card-image {
                    width                              : 100%;
                    height                             : auto;
                    display                            : block;
                }
                
                .tool-card-content {
                    padding                            : 15px;
                    text-align                         : center;
                    display                            : flex;
                    flex-direction                     : column;
                    justify-content                    : space-between;
                    flex-grow                          : 1;
                    min-height                         : 180px;                 /* <-- Reduced from 200px to 180px */
                }
                
                .tool-card-title {
                    font-family                        : var(--FontType_ValeTitleHeading03);
                    font-size                          : var(--FontSize_ValeTitleHeading03);
                    color                              : var(--FontCol_ValeTitleHeadingColour);
                    margin-top                         : 0;
                    margin-bottom                      : 10px;
                }
                
                .tool-card-description {
                    color                              : var(--FontCol_ValeStandardTextColour);
                    line-height                        : 1.5;
                    margin-bottom                      : 15px;                  /* <-- Changed back from auto to 15px for better spacing */
                    flex-grow                          : 1;
                }
                
                .tool-button,
                .coming-soon-button {
                    background-color                   : var(--ValeSecondaryButtonBg);
                    color                              : var(--ValeSecondaryButtonText);
                    border                             : none;
                    padding                            : 10px 20px;
                    text-align                         : center;
                    text-decoration                    : none;
                    display                            : inline-block;
                    font-size                          : 0.9rem;
                    font-family                        : var(--FontType_ValeStandardText);
                    cursor                             : pointer;
                    border-radius                      : 5px;
                    transition                         : background-color 0.3s ease;
                    width                              : auto;
                    min-width                          : 120px;
                    margin-top                         : auto;                  /* <-- Changed to auto to push button to bottom */
                    margin-bottom                      : 0;
                    align-self                         : center;
                    flex-shrink                        : 0;
                }
                
                .tool-button:hover {
                    background-color                   : var(--ValeHighlightColor);
                    color                              : var(--ValeSecondaryButtonText);
                }
                
                .coming-soon-button {
                    background-color                   : #dddddd;
                    color                              : #777777;
                    cursor                             : default;
                }
                
                .coming-soon-button:hover {
                    background-color                   : #dddddd;
                    color                              : #777777;
                }
                
                /* Tool Settings Styles */
                .tool-settings {
                    background-color                   : var(--ValeContentBackground);
                    border-radius                      : 8px;
                    padding                            : 20px;
                    margin                             : 20px 0;
                    text-align                         : left;
                    box-shadow                         : 0 2px 5px rgba(0,0,0,0.1);
                }
                
                .tool-settings h3 {
                    margin-top                         : 0;
                    color                              : var(--FontCol_ValeTitleHeadingColour);
                }
                
                .settings-group {
                    margin-bottom                      : 15px;
                }
                
                .setting-label {
                    display                            : block;
                    margin-bottom                      : 5px;
                    font-weight                        : 600;
                }
                
                .setting-input {
                    width                              : 100%;
                    padding                            : 8px;
                    border                             : 1px solid var(--ValeBorderColor);
                    border-radius                      : 4px;
                    font-family                        : var(--FontType_ValeStandardText);
                    margin-bottom                      : 10px;
                }
                
                .setting-select {
                    width                              : 100%;
                    padding                            : 8px;
                    border                             : 1px solid var(--ValeBorderColor);
                    border-radius                      : 4px;
                    font-family                        : var(--FontType_ValeStandardText);
                    margin-bottom                      : 10px;
                    background-color                   : white;
                }
                
                .action-button {
                    display                            : inline-block;
                    background-color                   : var(--ValeSecondaryButtonBg);
                    color                              : var(--ValeSecondaryButtonText);
                    padding                            : 12px 25px;
                    border                             : none;
                    border-radius                      : 5px;
                    font-family                        : var(--FontType_ValeStandardText);
                    font-size                          : 1rem;
                    cursor                             : pointer;
                    transition                         : background-color 0.2s ease;
                    margin-top                         : 10px;
                }
                
                .action-button:hover {
                    background-color                   : var(--ValeHighlightColor);
                    color                              : var(--ValeSecondaryButtonText);
                }
                
                /* Instructions Section */
                .instructions {
                    background-color                   : rgba(0, 102, 0, 0.05);
                    border-left                        : 4px solid var(--ValeHighlightColor);
                    padding                            : 15px;
                    margin                             : 20px 0;
                    text-align                         : left;
                }
                
                .instructions h4 {
                    margin-top                         : 0;
                    color                              : var(--ValeHighlightColor);
                }
                
                .instructions ol, .instructions ul {
                    margin-left                        : 1em;
                    padding-left                       : 1.1em;
                }
                .instructions ul {
                    list-style-type                    : disc;
                }
                .instructions-primary {
                    text-align                         : left !important;
                    margin-left                        : 1em;
                    padding-left                       : 1.1em;
                }
                
                .instructions li {
                    margin-bottom                      : 8px;
                    line-height                        : 1.5;
                }
                
                .instructions-secondary {
                    font-size                          : 0.75rem;
                    text-align                         : left;
                    margin-left                        : 0;
                }
                
                /* Collapsible Section Styles */
                .collapsible {
                    cursor                             : pointer;
                    display                            : flex;
                    justify-content                    : space-between;
                    align-items                        : center;
                    width                              : 100%;
                    padding-top                        : 0.50rem;
                    padding-bottom                     : 0.50rem;
                    padding-left                       : 1.00rem;
                    padding-right                      : 1.00rem;
                    background-color                   : rgba(0, 102, 0, 0.05);
                    border-left                        : 4px solid var(--ValeHighlightColor);
                    text-align                         : left;
                    border-radius                      : 4px 4px 0 0;
                }
                
                .collapsible:hover {
                    background-color                   : rgba(0, 102, 0, 0.1);
                }
                
                .collapsible-content {
                    max-height                         : 0;
                    overflow                           : hidden;
                    transition                         : max-height 0.3s ease-out, padding-top 0.3s ease-out, padding-bottom 0.3s ease-out;
                    background-color                   : rgba(0, 102, 0, 0.03);
                    border-left                        : 4px solid var(--ValeHighlightColor);
                    padding                            : 0 15px;
                }
                
                .collapsible.active + .collapsible-content {
                    padding-top: 15px;
                    padding-bottom: 15px;
                }
                
                .collapsible:after {
                    content                            : '▼';
                    font-size                          : 0.8rem;
                    color                              : var(--ValeHighlightColor);
                    transform                          : rotate(0deg);
                    transition                         : transform 0.3s;
                }
                
                .active:after {
                    transform                          : rotate(180deg);
                }
                
                /* Button Animation Styles - Enhanced */
                .tool-card {
                    cursor                             : pointer;
                    transition                         : transform 0.2s ease-in-out;
                }
                
                /* Clearfix for proper container sizing */
                .clearfix::after {
                    content                            : "";
                    clear                             : both;
                    display                           : table;
                }

                /* Framework Configurator Specific Styles */
                #configurator-wrapper {
                    display                            : flex;
                    flex-direction                     : column;
                    flex-grow                          : 1;
                    padding                            : 0;
                    background-color                   : var(--ValeContentBackground);
                    min-height                         : 0;
                }
                #canvas-toolbar {
                    padding                            : 10px 20px;
                    background-color                   : var(--ValeContentBackground);
                    border-bottom                      : 1px solid var(--ValeBorderColor);
                    display                            : flex;
                    gap                                : 10px;
                    align-items                        : center;
                    flex-shrink                        : 0; 
                }
                #canvas-toolbar button { 
                    background-color                   : var(--ValeSecondaryButtonBg);
                    color                              : var(--ValeSecondaryButtonText);
                    border                             : none;
                    border-radius                      : 4px;
                    padding                            : 8px 12px;
                    cursor                             : pointer;
                    font-family                        : var(--FontType_ValeStandardText);
                    font-size                          : 0.9rem;
                    transition                         : background-color 0.2s ease-in-out;
                }
                #canvas-toolbar button:hover {
                    background-color                   : var(--ValeSecondaryButtonHoverBg);
                }
                #canvas-container { 
                    flex-grow                          : 1;
                    position                           : relative; 
                    background-color                   : #e0e0e0; 
                    overflow                           : hidden; 
                    padding                            : 10px;
                    display                            : flex; 
                    justify-content                    : center; 
                    align-items                        : center;    
                    min-height                         : 0;
                }
                #drawing-canvas {
                    display                            : block; 
                    background-color                   : #ffffff;
                    border                             : 1px solid var(--ValeBorderColor);
                }
                #custom-prompt-overlay {
                    position                           : fixed; 
                    top                                : 0;
                    left                               : 0;
                    width                              : 100%;
                    height                             : 100%;
                    background-color                   : rgba(0,0,0,0.6);
                    z-index                            : 1050; 
                    display                            : none; 
                    justify-content                    : center;
                    align-items                        : center;
                    font-family                        : var(--FontType_ValeStandardText);
                }
                #custom-prompt-dialog {
                    background-color                   : var(--ValeContentBackground);
                    padding                            : 25px;
                    border-radius                      : 6px;
                    box-shadow                         : 0 5px 15px rgba(0,0,0,0.2);
                    width                              : 300px;
                    text-align                         : left;
                }
                #custom-prompt-dialog p {
                    margin-top                         : 0;
                    margin-bottom                      : 15px;
                    color                              : var(--FontCol_ValeStandardTextColour);
                    font-size                          : 0.95rem;
                    line-height                        : 1.4;
                }
                #custom-prompt-dialog input[type="text"],
                #custom-prompt-dialog input[type="number"] {
                    width                              : 100%;
                    padding                            : 10px;
                    margin-bottom                      : 20px;
                    border                             : 1px solid var(--ValeBorderColor);
                    border-radius                      : 4px;
                    box-sizing                         : border-box;
                    font-size                          : 0.9rem;
                }
                #custom-prompt-buttons {
                    text-align                         : right;
                }
                #custom-prompt-buttons button {
                    padding                            : 8px 15px;
                    border                             : none;
                    border-radius                      : 4px;
                    cursor                             : pointer;
                    font-size                          : 0.9rem;
                    margin-left                        : 10px;
                    transition                         : background-color 0.2s ease-in-out;
                }
                #custom-prompt-save {
                    background-color                   : var(--ValePrimaryButtonBg);
                    color                              : var(--ValePrimaryButtonText);
                }
                #custom-prompt-save:hover {
                    background-color                   : var(--ValePrimaryButtonHoverBg);
                }
                #custom-prompt-cancel {
                    background-color                   : #f0f0f0; 
                    color                              : var(--FontCol_ValeStandardTextColour);
                    border                             : 1px solid var(--ValeBorderColor);
                }
                #custom-prompt-cancel:hover {
                    background-color                   : #e0e0e0;
                }
                /* End of Framework Configurator Specific Styles */

                /* Header Styles */
                .HeaderBar__main-header {
                    display                            : flex;
                    align-items                        : center;
                    justify-content                    : center;
                    padding                            : 10px 15px;
                    margin                             : 0;
                    flex-shrink                        : 0;
                    background-color                   : var(--ValeContentBackground);
                    border-bottom                      : 1px solid var(--ValeBorderColor);
                    position                           : relative;
                }
                .HeaderBar__logo-image {
                    position                           : absolute;
                    left                               : 15px;
                    top                                : 50%;
                    transform                          : translateY(-50%);
                    height                             : 35px;
                }
                .HeaderBar__main-header-title {
                    margin                             : 0;
                    font-size                          : var(--FontSize_ValeTitleHeading01);
                    color                              : var(--FontCol_ValeTitleTextColour);
                    font-family                        : var(--FontType_ValeTitleText);
                }

                /* Save Status Message Styles */
                #saveStatusMessage {
                    position                           : fixed;
                    top                                : 100px;
                    left                               : 50%;
                    transform                          : translateX(-50%);
                    padding-top                        : 01.00rem;
                    padding-bottom                     : 01.00rem;
                    padding-left                       : 01.25rem;
                    padding-right                      : 01.25rem;
                    border-radius                      : 5px;
                    color                              : white;
                    z-index                            : 10000;
                    opacity                            : 0;
                    transition                         : opacity 0.5s ease-in-out;
                    font-family                        : var(--FontType_ValeStandardText);
                    font-size                          : 0.9rem;
                    box-shadow                         : 0 2px 4px rgba(0,0,0,0.2);
                }
            </style>
            <!-- #endregion -->


            <!-- #region =============================================================== -->
            <!-- -   -   PAGE NAVIGATION & STATE MANAGEMENT   -   -   -   -   -   -   - -->
            <!-- ======================================================================= -->
            <script>
            let currentPage = 'home';
            
            function goBack() { showPage('home'); }

            function navigateToHome() { showPage('home'); }
            
            function navigateToRoofLantern() { showPage('roofLanternToolPage'); }
            
            function navigateToNotesApp() {
                window.location = 'skp:launch_notes_app@';
            }
            
            function navigateToImageCarousel() {
                window.location = 'skp:launch_image_carousel@';
            }
            
            function navigateToWindowConfigurator() {
                window.location = 'skp:launch_window_configurator@';
            }
            
            function navigateToComponentBrowser() {
                window.location = 'skp:launch_component_browser@';
            }
            
            function navigateToWatercolorTool() {
                window.location = 'skp:launch_watercolor_tool@';
            }
            
            function navigateToVanishingPointsTool() {
                window.location = 'skp:launch_vanishing_points_tool@';
            }
            
            function navigateToWhitecardExport() {
                window.location = 'skp:launch_whitecard_export@';
            }
            
            function navigateToPreferences() { showPage('preferencesPage'); }
            </script>
            <!-- #endregion -->
            
            <!-- #region =============================================================== -->
            <!-- -   -   UI INITIALIZATION & DOM EVENT HANDLERS   -   -   -   -   -   - -->
            <!-- ======================================================================= -->
            <script>
            document.addEventListener('DOMContentLoaded', function() {
                // Initialize navigation elements
                document.querySelectorAll('[data-navigate]').forEach(element => {
                    element.addEventListener('click', function() {
                        showPage(this.getAttribute('data-navigate'));
                    });
                });
                
                // Initialize collapsible sections
                const collapsibles = document.getElementsByClassName("collapsible");
                for (let i = 0; i < collapsibles.length; i++) {
                    collapsibles[i].addEventListener("click", function() {
                        this.classList.toggle("active");
                    });
                }
                
                // Show home page after all initialization is complete
                showPage('home');
            });
            </script>
            <!-- #endregion -->
            
            <!-- #region =============================================================== -->
            <!-- -   -   TOOL-SPECIFIC FUNCTIONS   -   -   -   -   -   -   -   -   -   - -->
            <!-- ======================================================================= -->
            <script>
            function runRoofLanternTool() {
                const params = {
                    pitch_deg: document.getElementById('rl-pitch').value,
                    add_mouldings: document.getElementById('rl-mouldings').value,
                    ridge_z_offset_mm: document.getElementById('rl-ridge-offset').value,
                    hip_z_offset_mm: document.getElementById('rl-hip-offset').value,
                    bar_z_offset_mm: document.getElementById('rl-bar-offset').value,
                    light_block_z_offset_mm: document.getElementById('rl-light-block-offset').value
                };
                window.location = 'skp:generate_roof_lantern@' + JSON.stringify(params);
            }
            </script>
            <!-- #endregion -->
            
            <!-- #region =============================================================== -->
            <!-- -   -   FRAMEWORK CONFIGURATOR JAVASCRIPT INTEGRATION   -   -   -   - -->
            <!-- ======================================================================= -->
            <script src="#{framework_configurator_js_url}"></script>
            <script>
            // BRIDGE FUNCTION | Enhanced page navigation with framework configurator support
            // ---------------------------------------------------------------------------------
            function showPage(pageId) {
                document.querySelectorAll('.page').forEach(page => page.classList.remove('active'));
                const targetPage = document.getElementById(pageId);
                if (targetPage) {
                    targetPage.classList.add('active');
                    currentPage = pageId;
                    
                    // Enhanced framework configurator initialization
                    if (pageId === 'frameworkConfiguratorPage') {
                        console.log('ValeDesignSuite: Navigating to Framework Configurator page');
                        
                        // Ensure app object exists before calling methods
                        if (typeof app !== 'undefined') {
                            // Force canvas resize with multiple attempts for robustness
                            setTimeout(() => { 
                                if (app.forceResizeCanvas) {
                                    console.log('ValeDesignSuite: Forcing canvas resize (attempt 1)');
                                    app.forceResizeCanvas(); 
                                }
                            }, 150);
                            
                            setTimeout(() => { 
                                if (app.forceResizeCanvas) {
                                    console.log('ValeDesignSuite: Forcing canvas resize (attempt 2)');
                                    app.forceResizeCanvas(); 
                                }
                            }, 500);
                            
                            // Initialize canvas if method exists
                            if (app.initializeCanvas) {
                                console.log('ValeDesignSuite: Initializing canvas');
                                app.initializeCanvas();
                            }
                            
                            // Request node types configuration from Ruby
                            if (window.location && window.location.href) {
                                console.log('ValeDesignSuite: Requesting node types configuration');
                                window.location = 'skp:get_node_types_config@';
                            }
                        } else {
                            console.error('ValeDesignSuite: Framework Configurator app object not available');
                        }
                    }
                }
            }
            
            // BRIDGE FUNCTION | Framework Configurator initialization after DOM and app are ready
            // ---------------------------------------------------------------------------------
            document.addEventListener('DOMContentLoaded', function() {
                // Wait for app object to be available before initializing
                function initializeFrameworkBridge() {
                    if (typeof app !== 'undefined') {
                        console.log('ValeDesignSuite: Framework Configurator app object detected');
                        
                        // Initialize framework configurator if method exists
                        if (app.initializeFrameworkConfigurator) {
                            console.log('ValeDesignSuite: Initializing Framework Configurator bridge');
                            app.initializeFrameworkConfigurator();
                        }
                        
                        // Request initial node types configuration
                        if (window.location && window.location.href) {
                            console.log('ValeDesignSuite: Requesting initial node types configuration');
                            window.location = 'skp:get_node_types_config@';
                        }
                    } else {
                        console.log('ValeDesignSuite: Waiting for Framework Configurator app object...');
                        // Retry after a short delay
                        setTimeout(initializeFrameworkBridge, 100);
                    }
                }
                
                // Start initialization process
                initializeFrameworkBridge();
            });
            </script>
            <!-- #endregion -->
            </head>
        
    <!-- #region =============================================================== -->
    <!-- -   -   -   -   -   -   MAIN USER INTERFACE   -   -   -   -   -   -     -->
    <!-- ======================================================================= -->
        <body>
            <div class="HeaderBar__main-header">
            <img src="#{logo_image_url}" alt="Vale Garden Houses Logo" class="HeaderBar__logo-image">
            <h1 class="HeaderBar__main-header-title">Vale Design Suite : Main Menu</h1>
            </div>
            
            <!-- HOME PAGE | Main landing page with tool selection
            ------------------------------------------------------------------------- -->
            <div id="home" class="page active">
            <h3>Available Tools</h3>
            
            <div class="tool-cards-container">

                <!-- TOOL CARD | Roof Lantern Generator tool selection card
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToRoofLantern()">
                <img src="#{button_image_url}" alt="Roof Lantern Tool" class="tool-card-image">
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Roof Lantern Generator</h3>
                    <p class="tool-card-description">Create custom roof lanterns with configurable ridge beams, hip beams, and glazing bars based on your design.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToRoofLantern();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Model Notes App
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToNotesApp()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Notes App
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Model Notes</h3>
                    <p class="tool-card-description">Store and manage notes directly within your SketchUp model. Notes are automatically saved with the model.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToNotesApp();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Image Carousel App
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToImageCarousel()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Image Carousel
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Image Carousel</h3>
                    <p class="tool-card-description">View reference images from a folder. Folder path is stored with the model for team collaboration. Use arrow keys to navigate.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToImageCarousel();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Vale Asset Library
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToComponentBrowser()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Vale Asset Library
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Vale Asset Library</h3>
                    <p class="tool-card-description">Access the centralised repository of Vale assets, including components, materials, and textures.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToComponentBrowser();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Framework Configurator
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="showPage('frameworkConfiguratorPage')">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Framework Configurator Tool
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Framework Configurator</h3>
                    <p class="tool-card-description">Configure the framework of Vale structures. Note: This tool is currently in development.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); showPage('frameworkConfiguratorPage');">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Window Panel Configurator 
                ------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToWindowConfigurator()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Window Panel Configurator Tool
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Window Panel Configurator</h3>
                    <p class="tool-card-description">Create and configure custom window panels with adjustable dimensions, glazing bars, and frame colors.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToWindowConfigurator();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Watercolour Pen & Wash Renderer
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToWatercolorTool()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Watercolor Pen & Wash Renderer
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Watercolour Effects</h3>
                    <p class="tool-card-description">Transform SketchUp views into artistic watercolour pen and wash illustrations with customizable painterly effects, paper textures, and color bleeding.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToWatercolorTool();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Vanishing Points Drawing Aid
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToVanishingPointsTool()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Vanishing Points Drawing Aid
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Vanishing Points Tool</h3>
                    <p class="tool-card-description">Generate vanishing points and horizon lines for perspective drawing based on the current camera view. Creates crosshair targets and construction lines.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToVanishingPointsTool();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Profile Tracer Tool
                -------------------------------------------------------- -->
                <div class="tool-card">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Profile Tracer Tool
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Profile Tracer Tool</h3>
                    <p class="tool-card-description">Access Vale Garden Houses' extensive library of moldings, beadings, and profiles. Create custom profiles and apply them to your designs with precision.</p>
                    <span class="coming-soon-button">Coming Soon</span>
                </div>
                </div>

                <!-- TOOL CARD | Export Whitecard Scenes
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToWhitecardExport()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Export Whitecard Scenes
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Export Whitecard Scenes</h3>
                    <p class="tool-card-description">Automate the export of whitecard render scenes to PNG images and 2D DWG vector files with standardised settings and naming conventions.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToWhitecardExport();">Open Tool</span>
                </div>
                </div>

                <!-- TOOL CARD | Preferences & Dev Tools
                -------------------------------------------------------- -->
                <div class="tool-card" onclick="navigateToPreferences()">
                <div class="tool-card-image" style="width: 100%; height: 180px; background-color: #eeeeee; display: flex; align-items: center; justify-content: center; color: #999999; font-family: var(--FontType_ValeStandardText);">
                    Preferences & Dev Tools
                </div>
                <div class="tool-card-content">
                    <h3 class="tool-card-title">Preferences & Dev Tools</h3>
                    <p class="tool-card-description">Access development utilities, including hot-reloading ValeDesignSuite Ruby scripts without restarting SketchUp.</p>
                    <span class="tool-button" onclick="event.stopPropagation(); navigateToPreferences();">Open</span>
                </div>
                </div>
             </div>
            <div class="message" style="margin-top: 2.00rem; margin-bottom: 2.00rem; width: auto; max-width: 600px; align-self: center;">
                <h2>Success!</h2>
                <p>The Vale Design Suite plugin has loaded successfully.</p>
                <p>Version: 0.8.4</p>
            </div>
            </div>

            <!-- ROOF LANTERN PAGE | Tool configuration and execution interface
            ------------------------------------------------------------------------- -->
            <div id="roofLanternToolPage" class="page">
            <h2 style="margin:0;">Roof Lantern Generator Tool</h2>
            
            <!-- HELP SECTION | Collapsible instructions and guidance
            ------------------------------------------------------------------------- -->
            <div class="collapsible">
                <h4 style="margin:0;">Instructions & Help</h4>
            </div>
            <div class="collapsible-content">
                <div style="padding: 15px 0;">
                <h4>How to Use This Tool</h4>
                <ol class="instructions-primary">
                    <li>Draw the wire frame lines representing the roof lantern plan</li>
                    <li>
                    Tag the lines appropriately:
                    <ul>
                        <li><strong>1-ridge</strong> - For ridge lines</li>\
                        <li><strong>2-hips</strong> - For hip lines</li>
                        <li><strong>3-glaze-bars</strong> - For glazing bars</li>
                    </ul>
                    </li>
                    <li>Select all tagged lines</li>
                    <li>Click the "Generate Roof Lantern" button below</li>
                    <li>Configure settings in the dialog that appears</li>
                </ol>
                
                <h4>About This Tool</h4>
                <ul class="instructions-secondary">
                    <li>
                    This tool generates a 3D roof lantern with ridge beams (250mm height x 50mm width).
                    </li>
                    <li>
                    Hip beams (200mm height x 50mm width).
                    </li>
                    <li>
                    Glazing bars (100mm height x 35mm width).
                    </li>
                    <li>
                    Optional lighting blocks at ridge-hip intersections.
                    </li>
                    <li>
                    The tool will automatically calculate proper angles and heights based on your selected roof pitch.
                    </li>
                </ul>
                </div>
            </div>
            
            <!-- TOOL SETTINGS | Configuration options and parameter inputs
            ------------------------------------------------------------------------- -->
            <div class="tool-settings">
                <h3>Preparation Checklist</h3>
                <p>Before generating your roof lantern, ensure you have:</p>
                <ul>
                <li>✓ Created all necessary lines in your model</li>
                <li>✓ Tagged the lines with the appropriate layer names</li>
                <li>✓ Selected all the lines you want to include</li>
                </ul>
                
                <!-- PARAMETER INPUTS | User-configurable tool settings
                ------------------------------------------------------------------------- -->
                <div class="settings-group">
                <label for="rl-pitch" class="setting-label">Roof Pitch (°):</label>
                <input type="number" id="rl-pitch" class="setting-input" value="30.0">
                </div>
                
                <div class="settings-group">
                <label for="rl-mouldings" class="setting-label">Add Mouldings:</label>
                <select id="rl-mouldings" class="setting-select">
                    <option value="Yes" selected>Yes</option>
                    <option value="No">No</option>
                </select>
                </div>
                
                <div class="settings-group">
                <label for="rl-ridge-offset" class="setting-label">Ridge Z Offset (mm):</label>
                <input type="number" id="rl-ridge-offset" class="setting-input" value="-50.0">
                </div>
                
                <div class="settings-group">
                <label for="rl-hip-offset" class="setting-label">Hip Z Offset (mm):</label>
                <input type="number" id="rl-hip-offset" class="setting-input" value="-20.0">
                </div>
                
                <div class="settings-group">
                <label for="rl-bar-offset" class="setting-label">Bar Z Offset (mm):</label>
                <input type="number" id="rl-bar-offset" class="setting-input" value="20.0">
                </div>
                
                <div class="settings-group">
                <label for="rl-light-block-offset" class="setting-label">Lighting Block Z Offset (mm):</label>
                <input type="number" id="rl-light-block-offset" class="setting-input" value="-70.0">
                </div>
                
                <!-- ACTION BUTTON | Tool execution trigger
                ------------------------------------------------------------------------- -->
                <button class="action-button" onclick ="runRoofLanternTool()">
                Generate Roof Lantern
                </button>
            </div>
            <button class="back-button" onclick="goBack()" style="margin-top: auto;">Back to Home</button>
            </div>

            <!-- MENU PAGE |  Framework Configurator Tool Page 
            ------------------------------------------------------------------------- -->
            <div id="frameworkConfiguratorPage" class="page">
            <h1 id="frameworkConfiguratorTitle" style="font-size: 1.2em; margin-bottom: 0.2em; text-align: left;">Framework Configurator</h1>
            <p id="currentFrameworkElementName" style="margin-top: 0; margin-bottom: 1em; text-align: left; font-size: 0.9em; color: #555;">Current Framework Element: N/A</p>
            <div id="configurator-wrapper">
                <div id="canvas-toolbar">
                <button onclick="app.addNode()">Add Element</button>
                <button onclick="app.zoomIn()">Zoom +</button>
                <button onclick="app.zoomOut()">Zoom -</button>
                <button onclick="app.saveConfiguration()">Save Data</button>
                <button onclick="app.requestLoadConfiguration()">Load Data</button>
                <button onclick="app.handleCreateNewFrameworkAssembly()" style="background-color: var(--ValeHighlightColor);">Create New Framework</button>
                <button onclick="app.clearCanvas()" style="background-color: #555555;">Clear Canvas</button>
                <span style="margin-left: auto; font-size: 0.8em; color: #555;">Framework Thickness: 94mm</span>
                </div>
                <div id="canvas-container">
                    <canvas id="drawing-canvas"></canvas>
                </div>
            </div>


            <!-- Overlay  |  Custom Prompt Dialog Overlay
            ------------------------------------------------------------------------- -->
            <div id="custom-prompt-overlay">
                <div id="custom-prompt-dialog">
                <p id="custom-prompt-message"></p>
                <input type="number" id="custom-prompt-input" />
                <div id="custom-prompt-buttons">
                    <button id="custom-prompt-cancel">Cancel</button>
                    <button id="custom-prompt-save">Save</button>
                </div>
                </div>
            </div>
            <!-- -------------------------------------------------------------------- -->

            <!-- ----------------------------------------------------------------- -->
            <!-- SUB REGION  |  Navigation Controls                                -->
            <!-- ----------------------------------------------------------------- -->
            <button class="back-button" onclick="goBack()" style="margin-top: auto;">Back to Home</button>
            <!--  ---------------------------------------------------------------- -->
            </div>
            
            <!-- STATUS MESSAGE | Global status message display element
            ------------------------------------------------------------------------- -->
            <div id="saveStatusMessage"></div>
            
            <!-- PREFERENCES PAGE | Development utilities (hot reload)
            ------------------------------------------------------------------------- -->
            <div id="preferencesPage" class="page">
            <h2 style="margin:0;">Preferences & Development Utilities</h2>
            
            <div class="tool-settings">
                <h3>Development</h3>
                <p>Reload all ValeDesignSuite Ruby scripts without restarting SketchUp. This re-evaluates unencrypted .rb files and rebuilds the UI.</p>
                <button class="action-button" onclick="window.location='skp:reload_vale_design_suite_scripts@'">Reload ValeDesignSuite Scripts</button>
                <div class="instructions" style="margin-top: 1rem;">
                    <h4>Notes</h4>
                    <ul class="instructions-secondary">
                        <li>Encrypted files (.rbe/.rbs) cannot be hot-reloaded.</li>
                        <li>UI/menu duplication is prevented by load guards; observers may be reattached as needed.</li>
                    </ul>
                </div>
            </div>

            <button class="back-button" onclick="goBack()" style="margin-top: auto;">Back to Home</button>
            </div>

            <!-- STATUS MESSAGE | Global status message display element
            ------------------------------------------------------------------------- -->
            <div id="saveStatusMessage"></div>
            
        </body>
        </html>
        <!-- #endregion ===================================================== -->
        HTML

    # endregion -------------------------------------------------------------------
        

    
    # Region ============================================================================
    # -   -  -  -  -  -  -  -  -  RUBY HTML DIALOG CALLBACKS-  -  -  -  -  -  -  -  -  - 
    # ===================================================================================
    # Local variable for dialog to ensure callbacks capture the correct instance
    dialog_for_callbacks = @dialog_instance

    # CALLBACK |  Callback for Roof Lantern Generation
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("generate_roof_lantern") { |_, params_json|
        begin
            params = JSON.parse(params_json)
            # Call the roof lantern generator from the RoofLanternTools module
            ValeDesignSuite::Tools::RoofLanternTools.generate_roof_lantern(params)
        rescue => e
            puts "Error in generate_roof_lantern callback: #{e.message}"
        end
        }

    # CALLBACK | Launch Window Configurator Tool
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("launch_window_configurator") do |_|
        begin
            DebugTools.debug_ui("Launching Window Configurator Tool")
            ValeDesignSuite::Tools::WindowPanelConfigurator.init                                           # <-- Initialize and show window configurator
        rescue => e
            DebugTools.debug_ui("Error launching Window Configurator: #{e.message}")
        end
        end

    # CALLBACK | Launch Component Browser Tool
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("launch_component_browser") do |_|
        begin
            DebugTools.debug_ui("Launching Component Browser Tool")
            ValeDesignSuite::Tools::ComponentBrowser.init                                                  # <-- Initialize and show component browser
        rescue => e
            DebugTools.debug_ui("Error launching Component Browser: #{e.message}")
        end
        end

    # CALLBACK | Launch Watercolor Tool
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("launch_watercolor_tool") do |_|
        begin
            DebugTools.debug_ui("Launching Watercolor Tool")
            ValeDesignSuite::WatercolourRenderingTools.activate                                             # <-- Activate watercolor tool
        rescue => e
            DebugTools.debug_ui("Error launching Watercolor Tool: #{e.message}")
            UI.messagebox("Error launching Watercolor Tool: #{e.message}")
        end
        end

    # CALLBACK | Launch Vanishing Points Drawing Aid
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("launch_vanishing_points_tool") do |_|
        begin
            DebugTools.debug_ui("Launching Vanishing Points Drawing Aid")
            VanishingPointDrawingAid.create_vanishing_point_geometry                                        # <-- Create vanishing points
        rescue => e
            DebugTools.debug_ui("Error launching Vanishing Points Tool: #{e.message}")
            UI.messagebox("Error launching Vanishing Points Tool: #{e.message}")
        end
        end
        
    # CALLBACK | Launch Whitecard Export Tool
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("launch_whitecard_export") do |_|
        begin
            DebugTools.debug_ui("Launching Whitecard Export Tool")
            ValeDesignSuite::ExportWhitecardScenes.execute_export_workflow                                  # <-- Execute export workflow
        rescue => e
            DebugTools.debug_ui("Error launching Whitecard Export: #{e.message}")
            UI.messagebox("Error launching Whitecard Export: #{e.message}")
        end
        end

    # CALLBACK | Launch Notes App
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("launch_notes_app") do |_|
        begin
            DebugTools.debug_ui("Launching Notes App")
            ValeDesignSuite::Utils::NotesApp.show_notes_app
        rescue => e
            DebugTools.debug_ui("Error launching Notes App: #{e.message}")
            UI.messagebox("Error launching Notes App: #{e.message}")
        end
        end

    # CALLBACK | Launch Image Carousel
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("launch_image_carousel") do |_|
        begin
            DebugTools.debug_ui("Launching Image Carousel")
            ValeDesignSuite::Utils::ImageCarousel.show_carousel
        rescue => e
            DebugTools.debug_ui("Error launching Image Carousel: #{e.message}")
            UI.messagebox("Error launching Image Carousel: #{e.message}")
        end
        end

    # CALLBACK | Reload ValeDesignSuite Scripts (Development Only)
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("reload_vale_design_suite_scripts") do |_|
        begin
            count = ValeDesignSuite::MainUserInterface.reload_vale_design_suite_scripts
            dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Reloaded #{count} script(s) successfully!', true);")
        rescue => e
            puts "Reload failed: #{e.message}"
            dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Reload failed: #{e.message}', false);")
        end
        end

    # CALLBACK |  Callback for Saving Framework Data to Model
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("save_data_to_model") do |_, data_to_save|
        DebugTools.debug_ui("Ruby save_data_to_model callback: Received data_to_save.inspect: #{data_to_save.inspect}")
        nodes_data = data_to_save['frameworkNodes'] 
        lines_data = data_to_save['frameworkPanelLines'] 
        metadata_data = data_to_save['frameworkMetadata']
        
        assembly_id_from_metadata = nil
        framework_name = "Current" # Default for messages

        if metadata_data && metadata_data.is_a?(Array) && !metadata_data.empty? && metadata_data[0].is_a?(Hash)
            # Check for FrameworkUniqueId in the correct format
            if metadata_data[0]['FrameworkUniqueId'] && metadata_data[0]['FrameworkUniqueId'].match?(/^VFW\d{3}$/)
            assembly_id_from_metadata = metadata_data[0]['FrameworkUniqueId']
            DebugTools.debug_ui("Found valid AssemblyID in metadata: #{assembly_id_from_metadata}")
            else
            DebugTools.debug_ui("Invalid or missing FrameworkUniqueId in metadata: #{metadata_data[0]['FrameworkUniqueId'].inspect}")
            end
            
            if metadata_data[0]['FrameworkName']
            framework_name = metadata_data[0]['FrameworkName']
            end
        else
            DebugTools.debug_ui("Metadata is nil, empty, or not in expected format")
        end

        success = false
        if assembly_id_from_metadata
            DebugTools.debug_ui("Saving framework data for AssemblyID '#{assembly_id_from_metadata}' using FrameworkDataSerializer.")
            
            # The serializer expects :frameworkMetadata, :frameworkNodes, :frameworkPanelLines
            # which our data_to_save already provides in the correct format (uppercase F)
            success = ValeDesignSuite::DataUtils::FrameworkDataSerializer.save_assembly_data(assembly_id_from_metadata, data_to_save)
            
            if success
                # Update the geometry after saving data using smart update
                geometry_updated = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.update_framework_geometry_smart(assembly_id_from_metadata)
                if geometry_updated
                    DebugTools.debug_ui("Framework geometry updated successfully")
                else
                    DebugTools.debug_ui("Warning - Failed to update framework geometry")
                end
            end
        else
            # Instead of falling back to global save, create a new component
            DebugTools.debug_ui("No specific AssemblyID in metadata. Creating new component instead of global save.")
            
            # Generate a temporary name for the component based on current date/time
            new_component_name = "Framework_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
            
            # Create the new framework assembly with the data from the UI
            instance = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.create_new_framework_assembly(
            new_component_name, 
            data_to_save['frameworkNodes'], 
            data_to_save['frameworkPanelLines']
            )
            
            if instance && instance.valid?
            DebugTools.debug_ui("Successfully created new component: #{new_component_name}")
            # Select the new component
            model = Sketchup.active_model
            model.selection.clear
            model.selection.add(instance)
            success = true
            framework_name = new_component_name
            else
            DebugTools.debug_ui("Failed to create new component: #{new_component_name}")
            success = false
            end
        end
        
        if success
            dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Framework \\\'#{framework_name}\\\' saved successfully!', true);")
        else
            dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Failed to save framework \\\'#{framework_name}\\\'.', false);")
        end
        end

    # CALLBACK | Real-Time Save Framework Data (Silent, No Status Messages)
    # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("save_data_to_model_realtime") do |_, data_to_save|
        DebugTools.debug_ui("Ruby save_data_to_model_realtime callback: Received real-time data update")
        nodes_data = data_to_save['frameworkNodes'] 
        lines_data = data_to_save['frameworkPanelLines'] 
        metadata_data = data_to_save['frameworkMetadata']
        
        assembly_id_from_metadata = nil

        if metadata_data && metadata_data.is_a?(Array) && !metadata_data.empty? && metadata_data[0].is_a?(Hash)
            # Check for FrameworkUniqueId in the correct format
            if metadata_data[0]['FrameworkUniqueId'] && metadata_data[0]['FrameworkUniqueId'].match?(/^VFW\d{3}$/)
            assembly_id_from_metadata = metadata_data[0]['FrameworkUniqueId']
            DebugTools.debug_ui("Found valid AssemblyID in metadata: #{assembly_id_from_metadata}")
            end
        end

        # Only save if we have a valid assembly ID (don't create new components during real-time updates)
        if assembly_id_from_metadata
            DebugTools.debug_ui("Saving real-time framework data for AssemblyID '#{assembly_id_from_metadata}'")
            
            success = ValeDesignSuite::DataUtils::FrameworkDataSerializer.save_assembly_data(assembly_id_from_metadata, data_to_save)
            
            if success
                # Update the geometry after saving data (real-time geometry updates)
                geometry_updated = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.update_framework_geometry_smart(assembly_id_from_metadata)
                if geometry_updated
                    DebugTools.debug_ui("Framework geometry updated successfully")
                else
                    DebugTools.debug_ui("Warning - Failed to update framework geometry")
                end
            else
                DebugTools.debug_ui("Failed to save real-time data")
            end
        else
            DebugTools.debug_ui("No valid AssemblyID found - skipping real-time save")
        end
        end

        # CALLBACK | Load Framework Data from Model (Deprecated)
        # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("load_data_from_model") do |_|
            # This global loading callback is deprecated - do nothing
            # All data should be stored on component instances, not in global dictionaries
            dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Global data loading is disabled - please select a component', false);")
        end

        # CALLBACK | Create New Framework Assembly
        # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("handle_create_new_framework_assembly") do |_, params|
            # Handle both the new format (complete data) and legacy format (just name)
            assembly_name = nil
            framework_nodes = nil
            framework_panel_lines = nil
            
            if params.is_a?(String)
                # Legacy format - just a name string
                assembly_name = params
            elsif params.is_a?(Hash) || params.respond_to?(:to_hash)
                # New format - complete data hash
                params_hash = params.is_a?(Hash) ? params : params.to_hash
                
                # Extract the name
                assembly_name = params_hash['name']
                
                # Extract the framework data if available
                framework_nodes = params_hash['frameworkNodes'] if params_hash.key?('frameworkNodes')
                framework_panel_lines = params_hash['frameworkPanelLines'] if params_hash.key?('frameworkPanelLines')
            end
            
            if assembly_name.nil? || assembly_name.strip.empty?
                dialog_for_callbacks.execute_script("alert('Framework name cannot be empty.');")
                next 
            end
            
            DebugTools.debug_ui("Creating new framework assembly with name: #{assembly_name}")
            DebugTools.debug_ui("Including #{framework_nodes&.size || 0} nodes and #{framework_panel_lines&.size || 0} panel lines from UI")
            
            # Pass both the name and the data to the create method
            instance = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.create_new_framework_assembly(
                assembly_name, framework_nodes, framework_panel_lines
            )
            
            if instance && instance.valid?
                DebugTools.debug_ui("Successfully created framework: #{assembly_name}")
                # Select the new component so its data shows in the UI
                model = Sketchup.active_model
                model.selection.clear
                model.selection.add(instance)
                
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Framework \\'#{assembly_name}\\' created successfully.', true);")
            else
                DebugTools.debug_ui("Failed to create framework: #{assembly_name}")
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Failed to create framework \\'#{assembly_name}\\' .', false);")
            end
        end

        # CALLBACK | Clear Selection in SketchUp
        # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("clear_selection") do |_|
            model = Sketchup.active_model
            if model && model.selection
                DebugTools.debug_ui("Clearing selection")
                model.selection.clear
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Selection cleared', true);")
            else
                DebugTools.debug_ui("Could not clear selection - no active model")
            end
        end

        # CALLBACK | Request Component Data Load
        # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("request_load_data_for_component") do |_, params|
            entity_id = params['entityID']
            original_entity_id_for_js = params['originalEntityIDForJS'] # Get the passed entityID for JS confirmation

            if entity_id.nil?
                DebugTools.debug_ui("request_load_data_for_component called with nil entityID")
                next
            end
            
            DebugTools.debug_ui("Loading data for component with entityID: #{entity_id}")
            loaded_data_hash = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.load_framework_data_from_component(entity_id.to_i)
            
            if loaded_data_hash.nil? 
                DebugTools.debug_ui("No framework data found for component with entityID: #{entity_id}")
                # Pass the original_entity_id_for_js back so JS knows which load failed if relevant
                dialog_for_callbacks.execute_script("app.loadData(null, #{original_entity_id_for_js || 'null'}); app.showSaveStatusMessage('No framework data found on selected component', false);")
                next
            end
            
            DebugTools.debug_ui("Successfully loaded data for component with entityID: #{entity_id}")
            
            # Look for FrameworkName in metadata for debugging
            if loaded_data_hash['frameworkMetadata'] && loaded_data_hash['frameworkMetadata'].is_a?(Array) && 
                loaded_data_hash['frameworkMetadata'][0] && loaded_data_hash['frameworkMetadata'][0]['FrameworkName']
                DebugTools.debug_ui("Found framework name: #{loaded_data_hash['frameworkMetadata'][0]['FrameworkName']}")
            end
            
            # Verify we have nodes before sending to UI
            if loaded_data_hash['frameworkNodes'] && loaded_data_hash['frameworkNodes'].is_a?(Array)
                DebugTools.debug_ui("Found #{loaded_data_hash['frameworkNodes'].size} nodes in loaded data")
            else
                DebugTools.debug_ui("WARNING - No nodes found in loaded data or invalid format")
                loaded_data_hash['frameworkNodes'] = [] # Ensure we have an empty array at minimum
            end
            
            # Ensure we have panel lines
            if loaded_data_hash['frameworkPanelLines'] && loaded_data_hash['frameworkPanelLines'].is_a?(Array)
                DebugTools.debug_ui("Found #{loaded_data_hash['frameworkPanelLines'].size} panel lines in loaded data")
            else
                DebugTools.debug_ui("WARNING - No panel lines found in loaded data or invalid format")
                loaded_data_hash['frameworkPanelLines'] = [] # Ensure we have an empty array at minimum
            end
            
            # Convert to JSON and send to JavaScript, including the original_entity_id_for_js
            data_for_js = loaded_data_hash.to_json
            DebugTools.debug_ui("Sending data to JavaScript: #{data_for_js[0..100]}...") if data_for_js.length > 100
            dialog_for_callbacks.execute_script("console.log('Loading component data into canvas...'); app.loadData(#{data_for_js}, #{original_entity_id_for_js || 'null'}); app.showSaveStatusMessage('Component data loaded successfully', true);")
        end

        # CALLBACK | Get Assembly ID for Component
        # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("get_assembly_id_for_component") do |_, params|
            entity_id = params['entityID']
            callback = params['callback']
            
            if entity_id.nil?
                DebugTools.debug_ui("get_assembly_id_for_component called with nil entityID")
                next
            end
            
            unless callback
                DebugTools.debug_ui("get_assembly_id_for_component called without a callback")
                next
            end
            
            DebugTools.debug_ui("Getting AssemblyID for component with entityID: #{entity_id}")
            model = Sketchup.active_model
            instance = model.entities.find { |e| e.entityID == entity_id.to_i }
            
            if instance.nil? || !instance.is_a?(Sketchup::ComponentInstance)
                DebugTools.debug_ui("Component with entityID #{entity_id} not found or not a ComponentInstance")
                dialog_for_callbacks.execute_script("#{callback}(null);")
                next
            end
            
            assembly_id = instance.get_attribute(ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_INFO_DICT_NAME, 
                                                ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_ID_KEY)
            
            if assembly_id
                DebugTools.debug_ui("Found AssemblyID #{assembly_id} for component #{instance.name} (ID: #{entity_id})")
                dialog_for_callbacks.execute_script("#{callback}('#{assembly_id}');")
            else
                DebugTools.debug_ui("No AssemblyID found for component #{instance.name} (ID: #{entity_id})")
                dialog_for_callbacks.execute_script("#{callback}(null);")
            end
        end

        # CALLBACK | Debug Utility - Dump All Model Dictionaries
        # -------------------------------------------------------------------------
        dialog_for_callbacks.add_action_callback("debug_dump_model_dictionaries") do |_|
            model = Sketchup.active_model
            dicts = model.attribute_dictionaries
            
            puts "\n============================================================="
            puts "ALL MODEL-LEVEL ATTRIBUTE DICTIONARIES"
            puts "=============================================================\n"
            
            if dicts.nil?
                puts "No attribute dictionaries found at the model level."
            else
                puts "Found #{dicts.size} attribute dictionaries at model level:"
                
                dicts.each do |dict|
                    # Skip GeoReference dictionary as requested
                    next if dict.name == "GeoReference"
                    
                    puts "Dictionary Name: #{dict.name}"
                    puts "----------------------------------------"
                    
                    dict.each_pair do |key, value|
                        puts "  #{key.inspect} => #{value.inspect}"
                    end
                    
                    puts "\n"
                end
            end
            
            # Look through component definitions for dictionaries with our prefix
            puts "FRAMEWORK ASSEMBLIES IN COMPONENT DEFINITIONS:"
            puts "----------------------------------------"
            
            found_assembly_dicts = false
            prefix = ValeDesignSuite::DataUtils::FrameworkDataSerializer::DICTIONARY_PREFIX
            model.definitions.each do |definition|
                # Find dictionaries that match our prefix
                assembly_dicts = definition.attribute_dictionaries&.select { |dict| dict.name.start_with?(prefix) }
                if assembly_dicts && !assembly_dicts.empty?
                    found_assembly_dicts = true
                    assembly_dicts.each do |dict|
                        assembly_id = dict.name.sub(prefix, '')
                        puts "Found assembly '#{assembly_id}' on definition '#{definition.name}'"
                        
                        # Print metadata
                        metadata_json = dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY]
                        nodes_json = dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::NODES_KEY]
                        panel_lines_json = dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::PANEL_LINES_KEY]
                        
                        if metadata_json
                            begin
                                metadata = JSON.parse(metadata_json)
                                if metadata.is_a?(Array) && !metadata.empty?
                                    puts "  - Framework Name: #{metadata[0]['FrameworkName']}"
                                    puts "  - Framework UID: #{metadata[0]['FrameworkUniqueId']}"
                                end
                                puts "  - Nodes Count: #{JSON.parse(nodes_json || '[]').size}"
                                puts "  - Panel Lines Count: #{JSON.parse(panel_lines_json || '[]').size}"
                                puts ""
                            rescue => e
                                puts "Error parsing data for #{assembly_id}: #{e.message}"
                            end
                        end
                    end
                end
            end
            unless found_assembly_dicts
                puts "No framework assemblies found in component definitions."
            end
            
            # Return a message to the dialog
            dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Model dictionaries dumped to Ruby Console', true);")
        end

    # -----------------------------------------------------------------------------
    # REGION | Framework Panel Click Handler Callback
    # -----------------------------------------------------------------------------
    dialog_for_callbacks.add_action_callback("handle_framework_panel_click") do |_, panel_id, component_entity_id|
        DebugTools.debug_ui("Framework panel click - Panel: #{panel_id}, Component: #{component_entity_id}")
        
        begin
            # Get the framework component by entity ID
            model = Sketchup.active_model
            framework_component = nil
            
            # Find the component by entity ID
            model.entities.each do |entity|
                if entity.is_a?(Sketchup::ComponentInstance) && entity.entityID == component_entity_id.to_i
                    framework_component = entity
                    break
                end
            end
            
            unless framework_component && framework_component.is_a?(Sketchup::ComponentInstance)
                DebugTools.debug_ui("Invalid framework component for panel configuration")
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Invalid framework component selected', false);")
                next
            end
            
            # Load framework data to get panel information
            framework_data = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.load_framework_data_from_component(framework_component.entityID)
            unless framework_data
                DebugTools.debug_ui("Failed to load framework data")
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Failed to load framework data', false);")
                next
            end
            
            # Find the panel line data
            panel_lines = framework_data["frameworkPanelLines"] || []
            panel_line_data = panel_lines.find { |line| line["PanelUniqueId"] == panel_id }
            
            unless panel_line_data
                DebugTools.debug_ui("Panel data not found for #{panel_id}")
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Panel data not found', false);")
                next
            end
            
            # Extract panel dimensions from framework
            panel_width_mm = panel_line_data["length_mm"] || 800
            panel_height_mm = panel_line_data["PanelSizeZ"] || 1500
            
            # Use the integrated window panel configurator
            success = ValeDesignSuite::Tools::FrameworkIntegratedWindowPanelConfigurator.handle_panel_click(
                panel_id, 
                framework_component
            )
            
            if success
                DebugTools.debug_ui("Successfully opened panel configuration for #{panel_id}")
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Panel configuration opened for #{panel_id}', true);")
            else
                DebugTools.debug_ui("Failed to open panel configuration for #{panel_id}")
                dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Failed to open panel configuration', false);")
            end
            
        rescue => e
            DebugTools.debug_ui("Error handling panel click: #{e.message}")
            DebugTools.debug_backtrace(e.backtrace)
            dialog_for_callbacks.execute_script("app.showSaveStatusMessage('Error opening panel configuration', false);")
        end
    end
    # endregion -------------------------------------------------------------------

    
    # -----------------------------------------------------------------------------
    # REGION | Framework Configurator Callback Setup
    # -----------------------------------------------------------------------------

        # FUNCTION | Setup Framework Configurator Callbacks
        # ------------------------------------------------------------
        ValeDesignSuite::Tools::FrameworkToolsConfigurator.setup_dialog_callbacks(@dialog_instance)  # <-- Initialize framework callbacks
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | SketchUp Observer Setup and Lifecycle Management
    # -----------------------------------------------------------------------------

        # FUNCTION | Initialize Framework Selection Observer
        # ------------------------------------------------------------
        if @framework_selection_observer.nil?
            @framework_selection_observer = FrameworkSelectionObserver.new(@dialog_instance)  # <-- Create new observer instance
            Sketchup.active_model.selection.add_observer(@framework_selection_observer)       # <-- Register observer with selection
        end
        # ---------------------------------------------------------------

        # FUNCTION | Setup Dialog Close Handler
        # ------------------------------------------------------------
        @dialog_instance.set_on_closed {
            if @framework_selection_observer && Sketchup.active_model.selection.respond_to?(:remove_observer)
                Sketchup.active_model.selection.remove_observer(@framework_selection_observer)  # <-- Cleanup observer
                @framework_selection_observer = nil                                             # <-- Reset observer reference
            end
            @dialog_instance = nil                                                              # <-- Reset dialog reference
        }
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | Dialog Finalization and Display
    # -----------------------------------------------------------------------------

        # FUNCTION | Initialize Dialog Display
        # ------------------------------------------------------------
        @dialog_instance.set_html(html_content)  # <-- Set dialog HTML content
        @dialog_instance.show                    # <-- Display dialog window
        # ---------------------------------------------------------------

        # FUNCTION | Setup Debug Callbacks
        # ------------------------------------------------------------
        ValeDesignSuite::Core::PluginDebuggingAndDiagnosticTools.setup_debug_callbacks(@dialog_instance)  # <-- Initialize debug tools
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end
    end
end



# =============================================================================
# END OF FILE
# ============================================================================= 
