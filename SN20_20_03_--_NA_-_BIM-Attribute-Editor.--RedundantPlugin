# region [col01] |  -------------------------------------------------------------------------------
# NA |  BIM Attribute Editor
# -------------------------------------------------------------------------------------------------
#
# 01 - Project Details & Version History
# -------------------------------------------------------------------------------------------------
#
# PLUGIN NAME   | BIM Attribute Editor
# DESCRIPTION   | A SketchUp Plugin For Editing Dynamic Component Attributes
# AUTHOR        | Studio Noblefjørd
# CREATED       | 22-Jan-2025
#
# DEVELOPMENT VERSION ROOT DIRECTORY
#  `D:\RE00_--_Core_Repo_--_Local\SN01_--_Core-Library_--_Studio_Noodlfjord\SN20_--_Ruby_Script--_Sketchup-Ruby-Plugins\SN20_20_01_--_NA_-_Toolbox-Plugins`
#
# MAIN SKETCHUP PLUGIN DIRECTORY
#  `C:\Users\Administrator\AppData\Roaming\SketchUp\SketchUp 2025\SketchUp\Plugins`
#

#
# THIS FILE
#  `SN20_20_03_--_NA_-_BIM-Attribute-Editor_-_0.1.8.rb`
#
# DEVELOPMENT LOG
# - 0.1.0 - 19-Apr-2025 | Initial version
# - 0.1.1 - 19-Apr-2025 | Basic functionality testing
#     - Tested, working well, fetches info, updates info as intended, a good start
#     - UI Styling must be updated to match Noble Architecture Brand Standards
# - 0.1.2 - 19-Apr-2025 | UI Styling update
#     - Updated to use Noble Architecture standard CSS naming conventions
#     - Added StylesheetManager for remote/local CSS loading
#     - Improved UI layout with proper header, footer, and component structure
#     - Added fallback CSS in case external stylesheets can't be loaded
# - 0.1.3 - 19-Apr-2025 | Interaction improvement
#     - Changed dialog from modal to non-modal to allow selecting components while dialog is open
#     - Fixed issue where users couldn't select components in SketchUp with the editor open
#     - Confirmed Web-Loaded CSS Loading and correctly styling the Plugin in Sketchup
# - 0.1.4 - 19-Apr-2025 | UI Layout improvements
#     - Improved button placement with both Load and Save buttons side by side
#     - Removed redundant instruction line that was clipping the buttons
#     - Repositioned status message container for better visibility
#     - Added proper fallback CSS and custom styling for the BIM Attribute Editor
# - 0.1.5 - 19-Apr-2025 Fix: Load Definition & Instance Attributes
#     - Modified load_component_data to read 'dynamic_attributes' from both
#       the ComponentDefinition and ComponentInstance, merging them correctly.
#     - Instance attributes now properly override definition attributes.
#     - Improved validation and error messages for component selection.
# - 0.1.6 - 19-Apr-2025 Fix: Filter Internal Attributes
#     - Updated load_component_data to filter out internal DC attributes
#       (those starting with '_') before sending data to the UI.
#     - Added check in save_component_data to prevent saving unchanged values
#       and only trigger redraw if changes were actually made.
# - 0.1.7 - 20-Apr-2025 - UI: Improve Attribute Label Display
#     - Updated load_component_data (Ruby) to fetch '_label' attributes and
#       send a structured {value: ..., label: ...} object to JavaScript.
#     - Modified populateForm (JS) to create a two-part label structure.
#     - Added CSS to display the descriptive label prominently (left-aligned, default style).
#     - Technical attribute name is now shown right-aligned, smaller, and lighter.
#     - Ensures both descriptive context and technical reference are available.
#     - JS Section refactored to match Coding Standards.
# - 0.1.8 - 20-Apr-2025 - Feature: Enhanced Multi-line Text Support
#     - Confirmed proper handling of multi-line text in attribute values
#     - Optimized textarea auto-resize function to better handle paragraphs
#     - Added explicit newline preservation in data transfer between Ruby and JavaScript
#     - Ensured no unnecessary processing/escaping of newline characters
#     - Fixed potential edge cases with empty lines and whitespace handling
#
# -------------------------------------------------------------------------------------------------
# endregion


# region [LAUNCH] | Launch Notes
# -----------------------------------------------------------------------------  
# - This is Pasteable script for SketchUp Ruby Console
# - Speeds development 
#    - Will properly add into main UI After extensive testing.
#
# LAUNCH COMMAND
# `NobleBimEditor::BimAttributeEditor.launch_editor`
#
# -----------------------------------------------------------------------------  
# endregion


# region [LOAD] | Load Script Dependencies & External Libraries
require 'sketchup.rb'   # <-- Standard SketchUp Ruby Library, Methods Etc
require 'json'          # <-- Important For data transfer between Ruby and JS
require 'net/http'      # <-- For fetching external stylesheet
require 'uri'           # <-- For parsing URLs


# STYLE LOADING |  CSS STYLESHEET NOTES
# 
# Stylesheet loaded anc cached using this URL Link
# `https://www.noble-architecture.com/assets/AD02_-_STYL_-_Common_-_StyleSheets/AD02_40_-_STYL_-_Core-Default-SketchUp-Plugin-Stylesheet.css`
#
# System Path During Dev For Reference
# `d:\WE10_--_Public-Repo_--_Live-Website\assets\AD02_-_STYL_-_Common_-_StyleSheets\AD02_40_-_STYL_-_Core-Default-SketchUp-Plugin-Stylesheet.css`
#
# endregion 

# region [CSS] | CSS Stylesheet Handling
# --------------------------------------------------------------------------------
# This region handles loading and processing the external CSS stylesheet
# The system will first attempt to load from URL, then fall back to local version

module NobleBimEditor
  module StylesheetManager
    
    # Primary stylesheet URL
    STYLESHEET_URL = "https://www.noble-architecture.com/assets/AD02_-_STYL_-_Common_-_StyleSheets/AD02_40_-_STYL_-_Core-Default-SketchUp-Plugin-Stylesheet.css"
    
    # Local backup stylesheet path (for offline/development use)
    LOCAL_STYLESHEET_PATH = File.join(File.dirname(__FILE__), "stylesheets", "noble_sketchup_plugin_stylesheet.css")
    
    # Fallback minimal CSS in case external and local styles fail to load
    FALLBACK_MINIMAL_CSS = <<-CSS
      /* DON'T USE TESTING ONLY */
    CSS
    
    # Additional CSS specifically for the BIM Attribute Editor
    BIM_ATTRIBUTE_EDITOR_CSS_EXTENSIONS = <<-CSS
      /* DON'T USE TESTING ONLY */
    CSS
    
    # Variable to store the loaded CSS
    @stylesheet_content = nil
    @stylesheet_loading_error = nil
    
    # Fetch the external CSS stylesheet
    def self.load_stylesheet
      # First try the online version
      begin
        uri = URI.parse(STYLESHEET_URL)
        response = Net::HTTP.get_response(uri)
        
        if response.is_a?(Net::HTTPSuccess)
          @stylesheet_content = response.body
          puts "Successfully loaded stylesheet from URL: #{STYLESHEET_URL}"
          return @stylesheet_content
        else
          puts "Failed to load stylesheet from URL (HTTP #{response.code})"
          @stylesheet_loading_error = "HTTP Error: #{response.code}"
        end
      rescue => e
        puts "Error fetching stylesheet from URL: #{e.message}"
        @stylesheet_loading_error = e.message
      end
      
      # Fall back to local version if online fails
      begin
        if File.exist?(LOCAL_STYLESHEET_PATH)
          @stylesheet_content = File.read(LOCAL_STYLESHEET_PATH)
          puts "Successfully loaded local stylesheet from: #{LOCAL_STYLESHEET_PATH}"
          return @stylesheet_content
        else
          puts "Local stylesheet not found at: #{LOCAL_STYLESHEET_PATH}"
          @stylesheet_loading_error = "Local file not found" if @stylesheet_loading_error.nil?
        end
      rescue => e
        puts "Error reading local stylesheet: #{e.message}"
        @stylesheet_loading_error = "Local file error: #{e.message}" if @stylesheet_loading_error.nil?
      end
      
      # Return an empty stylesheet if all loading attempts fail
      puts "WARNING: Using fallback minimal stylesheet"
      @stylesheet_content = FALLBACK_MINIMAL_CSS
      return @stylesheet_content
    end
    
    # Get the stylesheet content (loading if necessary)
    def self.get_stylesheet
      @stylesheet_content = load_stylesheet if @stylesheet_content.nil?
      return @stylesheet_content
    end
    
    # Get loading status (for debugging)
    def self.get_loading_status
      if @stylesheet_loading_error.nil?
        return "Stylesheet loaded successfully"
      else
        return "Stylesheet loading error: #{@stylesheet_loading_error}"
      end
    end
    
    # Get the complete CSS (base + extensions)
    def self.get_complete_css
      return get_stylesheet + BIM_ATTRIBUTE_EDITOR_CSS_EXTENSIONS
    end
    
  end # module StylesheetManager
end # module NobleBimEditor
# endregion


# region [MODULE] | NobleBimEditor::BimAttributeEditor
# --------------------------------------------------------------------------------
module NobleBimEditor
  module BimAttributeEditor

    @dialog = nil
    @selected_instance_pid = nil # Store Persistent ID of the loaded component

    # region [CORE] | Core Logic
    # --------------------------------------------------------------------------------
    def self.launch_editor
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      options = {
        :dialog_title    => "BIM Attribute Editor",
        :preferences_key => "com_example_bim_attribute_editor",
        :scrollable      => true,
        :resizable       => true,
        :width           => 1000,
        :height          => 800,
        :left            => 200,
        :top             => 150,
        :style           => UI::HtmlDialog::STYLE_DIALOG # Use DIALOG style for typical tool window
      }
      @dialog = UI::HtmlDialog.new(options)
      @dialog.set_html(get_html_content)

      # --- Callbacks from JavaScript ---

      # JS asks Ruby to load data from the current selection
      @dialog.add_action_callback("request_load_data") { |action_context|
        puts "Callback: request_load_data received"
        load_component_data()
      }

      # JS sends updated attribute data back to Ruby
      @dialog.add_action_callback("receive_save_data") { |action_context, data_json, persistent_id|
        puts "Callback: receive_save_data received"
        save_component_data(data_json, persistent_id)
      }

      # --- Dialog Management ---

      @dialog.set_on_closed {
        puts "BIM Attribute Editor closed."
        @dialog = nil # Allow reopening
        @selected_instance_pid = nil # Clear selection on close
      }

      # @dialog.show # Non-blocking
      # @dialog.show_modal # Blocking - use show() for non-blocking if preferred during development
      @dialog.show # Non-blocking to allow selecting components in SketchUp
      # Note: show_modal might feel more like a dedicated editing session.
      # Use show() if you want to interact with SketchUp while the dialog is open.

      puts "BIM Attribute Editor launched."

    end # launch_editor
    # endregion


    # region [DATA] | Data Handling
    # --------------------------------------------------------------------------------
    def self.load_component_data
        model = Sketchup.active_model
        selection = model.selection
  
        # --- Validation: Ensure single component instance is selected ---
        unless selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
          # ... (Validation code remains the same as the previous version) ...
            message = "Please select exactly one Component instance."
            if selection.length == 1 && !selection.first.is_a?(Sketchup::ComponentInstance)
                message = "Selected item is not a Component Instance. Please select a component, not a group or other entity."
            elsif selection.length > 1
                message = "Please select only one Component instance."
            else # selection is empty
                message = "Please select a Component instance first."
            end
            @dialog.execute_script("handleError('#{message.gsub("'", "\\'")}')") if @dialog
            puts "Error: Invalid selection for loading. #{message}"
            @selected_instance_pid = nil
            return
        end
  
        instance = selection.first
        definition = instance.definition
        @selected_instance_pid = instance.persistent_id # Store PID for saving
  
        puts "Loading attributes for instance PID: #{@selected_instance_pid} (Definition: #{definition.name})"
  
        # --- Attribute Retrieval: Get ALL attributes first ---
        all_attributes = {}
  
        # 1. Get attributes from the Definition
        def_dict = definition.attribute_dictionary('dynamic_attributes', false)
        if def_dict
          puts "Reading Definition 'dynamic_attributes'."
          def_dict.each_pair { |key, value| all_attributes[key] = value } # Keep original types for now
        else
          puts "No 'dynamic_attributes' dictionary found on Definition."
        end
  
        # 2. Get attributes from the Instance (overrides)
        inst_dict = instance.attribute_dictionary('dynamic_attributes', false)
        if inst_dict
          puts "Reading Instance 'dynamic_attributes'."
          inst_dict.each_pair { |key, value| all_attributes[key] = value } # Instance overrides definition
        else
            puts "No 'dynamic_attributes' dictionary found on Instance."
        end
  
        # --- Prepare Data for JS: Filter and Structure ---
        attributes_for_js = {}
        all_attributes.each_pair do |key, value|
          # Skip keys starting with '_' UNLESS they are the actual value keys we want
          next if key.start_with?('_')
  
          # Found a user-facing attribute key (e.g., "a1_level_01")
          label_key = "_#{key}_label" # Construct the expected label key (e.g., "_a1_level_01_label")
          label_text = all_attributes.fetch(label_key, key) # Fetch the label, fallback to the key itself
  
          # Ensure value is properly converted to string while preserving newlines
          string_value = value.nil? ? "" : value.to_s
          
          attributes_for_js[key] = {
            value: string_value,  # Ensure value is a string for the textarea, with newlines intact
            label: label_text.to_s   # Ensure label is a string
          }
        end
  
        # --- Validation: Check if any user-editable attributes were found ---
        if attributes_for_js.empty?
          # ... (Validation code for empty attributes remains similar to previous version) ...
            is_dc = definition.attribute_dictionary('dynamic_attributes') || instance.attribute_dictionary('dynamic_attributes')
            if is_dc
                message = "Selected component appears to be Dynamic, but no user-editable attributes (or their labels) were found."
                @dialog.execute_script("handleError('#{message.gsub("'", "\\'")}')") if @dialog
                puts "Warning: #{message}"
            else
                message = "Selected component does not appear to be a Dynamic Component."
                @dialog.execute_script("handleError('#{message.gsub("'", "\\'")}')") if @dialog
                puts "Error: #{message}"
            end
            @selected_instance_pid = nil
            return
        end
  
        # Add component name/definition name for context
        component_info = {
          instance_name: instance.name.empty? ? "(no instance name)" : instance.name,
          definition_name: definition.name
        }
  
        # Package everything to send to JS
        payload = {
          persistent_id: @selected_instance_pid,
          attributes: attributes_for_js, # Use the structured hash
          info: component_info
        }
  
        json_data = payload.to_json
        # puts "Sending data to JS: #{json_data}" # Debug: Log JSON data
  
        @dialog.execute_script("populateForm(#{json_data});") if @dialog
        puts "Data sent to populate form. Found #{attributes_for_js.length} user-editable attributes."
  
      rescue => e
        # ... (Rescue block remains the same) ...
        puts "Error loading component data: #{e.message}"
        puts e.backtrace.join("\n")
        @dialog.execute_script("handleError('Error loading data: #{e.message.gsub("'", "\\'")}');") if @dialog # Escape quotes for JS
        @selected_instance_pid = nil
      end # load_component_data
  
      # --- save_component_data ---
      # NO CHANGES needed in save_component_data itself, as it correctly receives
      # the technical key ('a1_level_01') and the edited value from the textarea's
      # data-key and value properties, respectively.
      # The existing save_component_data from the previous version is fine.
      # (Include the save_component_data method from the previous response here)
      def self.save_component_data(data_json, persistent_id)
        # ... (Paste the entire save_component_data method from the previous response here) ...
        unless persistent_id && !persistent_id.to_s.empty?
          @dialog.execute_script("handleError('Error: No component ID provided for saving.')") if @dialog
          puts "Error: Missing persistent_id for saving."
          return
        end
  
        unless @selected_instance_pid && @selected_instance_pid == persistent_id.to_i
            message = "Error: The component originally loaded (PID: #{@selected_instance_pid || 'None'}) does not match the save target (PID: #{persistent_id}). Please reload."
            @dialog.execute_script("handleError('#{message.gsub("'", "\\'")}')") if @dialog
            puts "Error: PID mismatch during save. Stored: #{@selected_instance_pid}, Received: #{persistent_id}"
            return
        end
  
        model = Sketchup.active_model
        instance = model.find_entity_by_persistent_id(persistent_id.to_i)
  
        unless instance && instance.is_a?(Sketchup::ComponentInstance)
          message = "Error: Could not find the component instance (PID: #{persistent_id}) to save to. It might have been deleted."
          @dialog.execute_script("handleError('#{message.gsub("'", "\\'")}')") if @dialog
          puts "Error: Could not find instance with PID #{persistent_id}."
          return
        end
  
        begin
          new_attributes = JSON.parse(data_json)
          puts "Received attributes to save: #{new_attributes.inspect}"
  
          model.start_operation('Edit BIM Attributes', true)
          dict = instance.attribute_dictionary('dynamic_attributes', true)
          changes_made = false
  
          new_attributes.each do |key, new_value_str|
            next if key.start_with?('_')
            current_value_obj = instance.get_attribute('dynamic_attributes', key)
            current_value_obj = instance.definition.get_attribute('dynamic_attributes', key) if current_value_obj.nil?
            current_value_str = current_value_obj.to_s
  
            if new_value_str != current_value_str
              puts "Setting attribute: Key='#{key}', New Value='#{new_value_str}' (String with potentially multi-line content)"
              success = instance.set_attribute('dynamic_attributes', key, new_value_str)
              unless success
                puts "Warning: Failed to set attribute '#{key}'"
              else
                changes_made = true
              end
            end
          end
  
          model.commit_operation
  
          if changes_made
            if defined?($dc_observers) && $dc_observers.respond_to?(:get_latest_class)
              latest_dc_class = $dc_observers.get_latest_class
              if latest_dc_class && latest_dc_class.respond_to?(:redraw_with_undo)
                puts "Attempting DC redraw for instance PID: #{instance.persistent_id}"
                latest_dc_class.redraw_with_undo(instance)
                puts "DC redraw triggered."
              else
                puts "Warning: Could not find DC redraw_with_undo method."
                UI.messagebox("Attributes saved, but couldn't trigger automatic Dynamic Component refresh.")
              end
            else
              puts "Warning: DC Observers ($dc_observers) not found."
              UI.messagebox("Attributes saved, but couldn't trigger automatic Dynamic Component refresh.")
            end
            message = "Attributes saved successfully for #{instance.definition.name}."
            @dialog.execute_script("saveSuccess('#{message.gsub("'", "\\'")}')") if @dialog
            puts "#{message} PID: #{persistent_id}."
          else
             message = "No changes detected. Attributes not saved."
             @dialog.execute_script("updateStatus('#{message.gsub("'", "\\'")}', false);") if @dialog
             puts message
          end
  
        rescue JSON::ParserError => e
          puts "Error parsing JSON data from dialog: #{e.message}"
          @dialog.execute_script("handleError('Error: Invalid data format received.');") if @dialog
        rescue => e
          model.abort_operation
          puts "Error saving component data: #{e.message}"
          puts e.backtrace.join("\n")
          @dialog.execute_script("handleError('Error saving data: #{e.message.gsub("'", "\\'")}');") if @dialog
        end
      end # save_component_data
      # endregion



    # region [UI] | HTML/CSS/JS Content
    # --------------------------------------------------------------------------------
    def self.get_html_content
      # Fetch base CSS from StylesheetManager
      complete_css = StylesheetManager.get_complete_css
      
      # Build the HTML string using string concatenation instead of interpolation
      html = <<-HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>BIM Attribute Editor</title>
    <style>
HTML

      # Add CSS separately to avoid interpolation issues
      html += complete_css
      
      # Continue with the rest of the HTML
      html += <<-HTML
    </style>
</head>
<body>
    <div class="PAGE__container">
        <!-- Header Section -->
        <div class="HEAD__container">
            <div class="HEAD__nav">
                <h1 class="HEAD__title">BIM Attribute Editor</h1>
                <span class="HEAD__version-note">v0.1.8</span>
            </div>
        </div>

        <!-- Main Content Area -->
        <div class="FULL__page-app-container">
            <div class="MAIN__container">

                 <!-- Status Message Block -->
                 <div id="status" class="STATUS__container">Ready.</div>

                <!-- Controls Block -->
                <div class="CTRL__block">
                    <h2 class="CTRL__heading">Component Selection</h2>
                    <div class="BTTN__container">
                        <button id="loadButton" class="BTTN__standard">Load Selected Component Data</button>
                        <button id="saveButton" class="BTTN__standard" disabled>Save Changes</button>
                    </div>
                    <!-- componentInfoDiv element is needed for JS, even if hidden -->
                    <div id="componentInfo" class="INFO__component" style="display: none;"></div>
                </div>

                <!-- Results Block for Attributes -->
                <div class="RSLT__block">
                    <h2 class="RSLT__heading">Component Attributes</h2>
                    <div id="attributesContainer" class="ATTR__container">
                        <!-- Attributes will be loaded here -->
                    </div>
                </div>

            </div>
        </div>

        <!-- Footer Section -->
        <div class="FOOT__container">
            <div class="FOOT__content">
                Noble Architecture BIM Tools © 2025
            </div>
        </div>
    </div>

    <script>
        // ===================================================================================
        // JAVASCRIPT | BIM ATTRIBUTE EDITOR CORE
        // ===================================================================================
        //
        // INTEGRATED | 19-Apr-2025
        // STATUS     | Working
        //
        // Description:
        // - Core JavaScript functionality for the BIM Attribute Editor
        // - Handles UI interaction, data processing, and SketchUp communication
        // - Manages component attribute loading, editing, and saving
        // ----------------------------------------------------------------------------------



        // ----------------------------------------------------------------------------------
        // CORE VARIABLES
        // ----------------------------------------------------------------------------------

        // DOM Element References
        const componentInfoDiv       = document.getElementById('componentInfo');
        const loadButton            = document.getElementById('loadButton');
        const saveButton            = document.getElementById('saveButton');
        const attributesContainer   = document.getElementById('attributesContainer');
        const statusDiv             = document.getElementById('status');

        // State Management
        let currentPersistentId     = null;

        // Element validation check
        if (!componentInfoDiv) { 
            console.error("CRITICAL ERROR: componentInfoDiv element not found in HTML!"); 
        }



        //   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .  .


        // ===================================================================================
        // SKETCHUP COMMUNICATION FUNCTIONS
        // ===================================================================================

        // FUNCTION | Send Save Data To Ruby
        // ----------------------------------------------------------------------------------
        // - Sends attribute data back to SketchUp via callback
        // - callbackName: The Ruby callback to invoke
        // - attributesData: JavaScript object containing attribute key-value pairs
        // - persistentId: Component's unique persistent ID for verification

        function sendSaveDataToRuby(callbackName, attributesData, persistentId) {
            if (window.sketchup && window.sketchup[callbackName]) {
                sketchup[callbackName](JSON.stringify(attributesData), persistentId);
            } else {
                console.error('SketchUp callback ' + callbackName + ' not found.');
                updateStatus('Error: Cannot communicate with SketchUp.', true);
            }
        }



        //   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .  .


        // ===================================================================================
        // EVENT HANDLERS
        // ===================================================================================

        // EVENT HANDLER | Load Button Click
        // ----------------------------------------------------------------------------------
        // - Requests component data from SketchUp when Load button is clicked
        // - Prepares UI for data loading and clears previous content

        loadButton.addEventListener('click', () => {
            updateStatus('Requesting data from SketchUp...', false);
            saveButton.disabled = true;
            attributesContainer.innerHTML = 'Loading...';
            
            if (componentInfoDiv) { 
                componentInfoDiv.textContent = ''; 
                componentInfoDiv.style.display = 'none';
            }
            
            sketchup.request_load_data();
        });


        // EVENT HANDLER | Save Button Click
        // ----------------------------------------------------------------------------------
        // - Collects modified attribute data from form
        // - Sends data back to SketchUp for processing and saving

        saveButton.addEventListener('click', () => {
            updateStatus('Saving data...', false);
            saveButton.disabled = true;
            
            const attributeData = {};
            const textareas = attributesContainer.querySelectorAll('.ATTR__textarea[data-key]');
            
            textareas.forEach(textarea => { 
                attributeData[textarea.getAttribute('data-key')] = textarea.value; 
            });
            
            console.log("Data to send:", attributeData);
            console.log("Saving for PID:", currentPersistentId);
            
            if (currentPersistentId === null) { 
                handleError("Cannot save: No component was loaded."); 
                return; 
            }
            
            sendSaveDataToRuby('receive_save_data', attributeData, currentPersistentId);
        });



        //   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .  .


        // ===================================================================================
        // UI UTILITY FUNCTIONS
        // ===================================================================================

        // UI FUNCTION | Auto-resize Textarea
        // ----------------------------------------------------------------------------------
        // - Automatically adjusts textarea height based on content
        // - Ensures all text is visible without scrolling

        function autoGrowTextarea(textarea) {
            textarea.style.height = 'auto';
            // Add extra padding to ensure multi-line text is fully visible without scrolling
            textarea.style.height = (textarea.scrollHeight + 5) + 'px';
        }


        // UI FUNCTION | Update Status Message
        // ----------------------------------------------------------------------------------
        // - Updates the status message display with appropriate styling
        // - message: Text message to display
        // - isError: Whether this is an error message (applies error styling)
        // - type: Optional message type for additional styling variations

        function updateStatus(message, isError = false, type = null) {
            statusDiv.innerHTML = message; 
            
            if (isError) {
                statusDiv.className = 'STATUS__container STATUS__error';
            } else if (type === 'success') {
                statusDiv.className = 'STATUS__container STATUS__success';
            } else {
                statusDiv.className = 'STATUS__container';
            }
            
            console.log(`Status update: ${message} (Error: ${isError})`);
        }


        // UI FUNCTION | Handle Error
        // ----------------------------------------------------------------------------------
        // - Displays error message and resets interface to error state
        // - message: Error message to display

        function handleError(message) {
            updateStatus(message, true);
            saveButton.disabled = true;
            attributesContainer.innerHTML = '<p style="color: var(--color-error);"><i>Error processing data. See status message.</i></p>';
            currentPersistentId = null;
        }


        // UI FUNCTION | Handle Save Success
        // ----------------------------------------------------------------------------------
        // - Updates status with success message and re-enables the save button
        // - message: Success message to display

        function saveSuccess(message) {
            updateStatus(message, false, 'success');
            saveButton.disabled = false;
        }



        //   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .   .  .


        // ===================================================================================
        // DATA PROCESSING FUNCTIONS
        // ===================================================================================

        // DATA FUNCTION | Populate Form with Component Data
        // ----------------------------------------------------------------------------------
        // - Processes data received from SketchUp and creates form elements
        // - data: JSON object containing component attributes and metadata
        // - Creates attribute input fields with proper labeling

        function populateForm(data) {
            console.log("PopulateForm called. Received data:", JSON.stringify(data, null, 2));
            attributesContainer.innerHTML = '';
            statusDiv.className = 'STATUS__container';
            
            // Validate data structure
            if (!data || !data.attributes) { 
                console.error("populateForm Error: Received invalid data structure!"); 
                handleError("Received invalid data structure from SketchUp."); 
                return; 
            }
            
            // Store component ID for save operations
            currentPersistentId = data.persistent_id;
            console.log("Stored PID:", currentPersistentId);
            
            // Update status with component info
            let statusMessage = 'Component data loaded. Edit values below.';
            if (data.info) { 
                statusMessage += `<div class="INFO__component" style="margin-top: 8px; font-size: 0.90rem; color: var(--color-gray-700); font-family: var(--font-regular);">
                    Editing: <strong>${data.info.definition_name}</strong> 
                    (Instance: ${data.info.instance_name || 'N/A'}, PID: ${currentPersistentId})
                </div>`;
            }
            updateStatus(statusMessage, false);
            
            if(componentInfoDiv) componentInfoDiv.style.display = 'none';
            
            // Group attributes by their prefix categories
            const categoryGroups = {
                'a': { title: 'BIM Element Codes', attributes: [] },
                'b': { title: 'BIM Element Core Data', attributes: [] },
                'c': { title: 'BIM Element Properties', attributes: [] },
                'd': { title: 'Component Dimensions', attributes: [] },
                'e': { title: 'Component Location & Height', attributes: [] },
                'f': { title: 'Model Notes & Metadata', attributes: [] },
                't': { title: 'Technical Drawings', attributes: [] },
                'ungrouped': { title: 'Ungrouped Attributes', attributes: [] }
            };
            
            // Process and categorize attributes
            const keys = Object.keys(data.attributes).sort();
            console.log(`Processing ${keys.length} attribute keys:`, keys);
            
            // Handle empty attributes case
            if (keys.length === 0) {
                attributesContainer.innerHTML = '<p><i>No user-editable attributes found for this component.</i></p>';
                updateStatus('Loaded component has no editable attributes.', false);
                saveButton.disabled = true;
                console.log("No keys found, population complete.");
                return;
            }
            
            // Categorize attributes by prefix
            keys.forEach(key => {
                const attrData = data.attributes[key];
                
                // Validate attribute data
                if (!attrData || typeof attrData.value === 'undefined' || typeof attrData.label === 'undefined') { 
                    console.error(`Error: Invalid attrData for key "${key}":`, attrData); 
                    return; 
                }
                
                // Determine category based on key prefix
                let category = 'ungrouped';
                
                // Debug information about the key we're analyzing
                console.log(`Analyzing key: ${key} (type: ${typeof key})`);
                
                // Use simple string checking instead of regex
                if (key.startsWith('a') && key.charAt(1) >= '0' && key.charAt(1) <= '9' && key.indexOf('_') > 0) {
                    category = 'a';
                    console.log(`  Categorized as BIM Element Codes (${category})`);
                } 
                else if (key.startsWith('b') && key.charAt(1) >= '0' && key.charAt(1) <= '9' && key.indexOf('_') > 0) {
                    category = 'b';
                    console.log(`  Categorized as BIM Element Core Data (${category})`);
                } 
                else if (key.startsWith('c') && key.charAt(1) >= '0' && key.charAt(1) <= '9' && key.indexOf('_') > 0) {
                    category = 'c';
                    console.log(`  Categorized as BIM Element Properties (${category})`);
                } 
                else if (key.startsWith('d') && key.charAt(1) >= '0' && key.charAt(1) <= '9' && key.indexOf('_') > 0) {
                    category = 'd';
                    console.log(`  Categorized as Component Dimensions (${category})`);
                }
                else if (key.startsWith('e') && key.charAt(1) >= '0' && key.charAt(1) <= '9' && key.indexOf('_') > 0) {
                    category = 'e';
                    console.log(`  Categorized as Component Location & Height (${category})`);
                }
                else if (key.startsWith('f') && key.charAt(1) >= '0' && key.charAt(1) <= '9' && key.indexOf('_') > 0) {
                    category = 'f';
                    console.log(`  Categorized as Model Notes & Metadata (${category})`);
                }
                else if (key.startsWith('t') && key.charAt(1) >= '0' && key.charAt(1) <= '9' && key.indexOf('_') > 0) {
                    category = 't';
                    console.log(`  Categorized as Technical Drawings (${category})`);
                }
                else {
                    console.log(`  Categorized as Ungrouped - First char: '${key.charAt(0)}', Second char: '${key.charAt(1)}', Has underscore: ${key.indexOf('_') > 0}`);
                }
                
                // Add to appropriate category group
                categoryGroups[category].attributes.push({
                    key: key,
                    label: attrData.label,
                    value: attrData.value
                });
            });
            
            // After categorization is complete, before creating the section elements
            console.log("Category grouping results:");
            Object.keys(categoryGroups).forEach(category => {
                console.log(`  ${categoryGroups[category].title}: ${categoryGroups[category].attributes.length} attributes`);
            });
            
            // Create sections for each category
            Object.keys(categoryGroups).forEach(category => {
                const group = categoryGroups[category];
                
                // Skip empty categories
                if (group.attributes.length === 0) return;
                
                // Create the collapsible section container
                const sectionDiv = document.createElement('div');
                sectionDiv.className = 'ATTR__section';
                
                // Create the header/title that acts as toggle
                const headerDiv = document.createElement('div');
                headerDiv.className = 'ATTR__section-header';
                headerDiv.innerHTML = `
                    <span class="ATTR__section-title">${group.title}</span>
                    <span class="ATTR__section-count">(${group.attributes.length})</span>
                    <span class="ATTR__section-toggle">+</span>
                `;
                
                // Create the content container (initially collapsed)
                const contentDiv = document.createElement('div');
                contentDiv.className = 'ATTR__section-content';
                contentDiv.style.display = 'none'; // Initially collapsed
                
                // Add toggle behavior
                headerDiv.addEventListener('click', () => {
                    const isCollapsed = contentDiv.style.display === 'none';
                    contentDiv.style.display = isCollapsed ? 'block' : 'none';
                    headerDiv.querySelector('.ATTR__section-toggle').textContent = isCollapsed ? '-' : '+';
                });
                
                // Add attributes to the section
                group.attributes.forEach(attr => {
                    try {
                        // Create attribute container
                        const itemDiv = document.createElement('div'); 
                        itemDiv.className = 'FORM__group ATTR__item';
                        
                        const labelContainer = document.createElement('div'); 
                        labelContainer.className = 'ATTR__label-container';
                        
                        const mainLabel = document.createElement('span'); 
                        mainLabel.className = 'ATTR__label--main FORM__label'; 
                        mainLabel.textContent = attr.label; 
                        mainLabel.title = attr.label;
                        
                        const technicalLabel = document.createElement('span'); 
                        technicalLabel.className = 'ATTR__label--technical'; 
                        technicalLabel.textContent = attr.key; 
                        technicalLabel.title = attr.key;
                        
                        const textarea = document.createElement('textarea'); 
                        textarea.id = 'attr_' + attr.key; 
                        textarea.className = 'ATTR__textarea FORM__input'; 
                        textarea.setAttribute('data-key', attr.key); 
                        textarea.spellcheck = true;  // Enable spell checking
                        textarea.setAttribute('lang', 'en');  // Set language to English
                        
                        // Ensure multi-line text is preserved
                        const valueStr = attr.value !== null && attr.value !== undefined ? attr.value : '';
                        textarea.value = valueStr;
                        
                        // Add auto-resize event listener
                        textarea.addEventListener('input', () => autoGrowTextarea(textarea));
                        
                        // Build DOM structure
                        labelContainer.appendChild(mainLabel); 
                        labelContainer.appendChild(technicalLabel);
                        itemDiv.appendChild(labelContainer); 
                        itemDiv.appendChild(textarea);
                        contentDiv.appendChild(itemDiv);
                        
                        // Initial size adjustment
                        setTimeout(() => autoGrowTextarea(textarea), 50);
                        
                    } catch (e) { 
                        console.error(`DOM Error creating elements for key "${attr.key}":`, e); 
                    }
                });
                
                // Add section to the container
                sectionDiv.appendChild(headerDiv);
                sectionDiv.appendChild(contentDiv);
                attributesContainer.appendChild(sectionDiv);
            });
            
            saveButton.disabled = false;
            console.log("Population complete with folding sections.");
        }


        // Initial status on page load
        updateStatus('Ready. Select a Dynamic Component and click "Load".', false);
    </script>
</body>
</html>
HTML
      return html
    end # get_html_content
    # endregion


  end # module BimAttributeEditor
end # module NobleBimEditor
# endregion

# --------------------------------------------------------------------------------
# --------------------------------------------------------------------------------

# region [RUN] | How to Run
# --------------------------------------------------------------------------------
# 1. Open the SketchUp Ruby Console (Window -> Ruby Console).
# 2. Copy the ENTIRE script above.
# 3. Paste it into the Ruby Console.
# 4. Press Enter.
# 5. Run the editor by typing the following in the console and pressing Enter:
#    NobleBimEditor::BimAttributeEditor.launch_editor
#
# --- To make it a Toolbar button (Example - Requires Extension Registration): ---
# This part is NOT for pasting directly into the console initially, but shows
# how you would integrate it into a proper extension structure later.
#
# unless file_loaded?(__FILE__)
#   # Create a command
#   cmd = UI::Command.new("BIM Attribute Editor") {
#     NobleBimEditor::BimAttributeEditor.launch_editor
#   }
#   cmd.tooltip = "Open BIM Attribute Editor"
#   cmd.small_icon = "path/to/your/small_icon.png" # Optional icon
#   cmd.large_icon = "path/to/your/large_icon.png" # Optional icon
#
#   # Create a toolbar
#   toolbar = UI::Toolbar.new "BIM Tools"
#   toolbar.add_item cmd
#   toolbar.show # Show the toolbar if it's the first time
#
#   # Create a menu item (Optional)
#   UI.menu("Plugins").add_item(cmd) # Or Tools menu, etc.
#
#   file_loaded(__FILE__)
# end
# endregion

# region [EXPLANATION] | Explanation and Key Points
# --------------------------------------------------------------------------------
# 
# Module Structure:
# - Encapsulates the code to avoid polluting the global namespace (NobleBimEditor::BimAttributeEditor).
# 
# UI::HtmlDialog:
# - Creates the web dialog. Initially uses show_modal for simplicity, acting like a dedicated tool window.
# - Can switch to show if needed.
# 
# @dialog Variable:
# - Stores the dialog instance to interact with it and prevent multiple dialogs (unless closed).
# 
# @selected_instance_pid:
# - Stores the persistent_id of the component when loaded.
# - Ensures the user hasn't selected a different component between loading and saving.
# - persistent_id is reliable across SketchUp sessions, unlike entityID.
# 
# Callbacks (add_action_callback):
# - Define how JavaScript calls Ruby functions (request_load_data, receive_save_data).
# 
# load_component_data:
# - Checks the selection for a single valid DC instance.
# - Retrieves the dynamic_attributes dictionary using instance.attribute_dictionary(...).
# - Stores the persistent_id.
# - Converts the attributes to a Hash, converting all values to strings (value.to_s) for easier handling in HTML text areas.
# - Packages the attributes, PID, and basic component info into a payload Hash.
# - Converts the payload to JSON using require 'json' and payload.to_json.
# - Sends the JSON to the JavaScript function populateForm using dialog.execute_script(...).
# - Includes error handling (rescue).
# 
# save_component_data:
# - Receives the updated attribute data (as a JSON string) and the original persistent_id from JavaScript.
# - Validation: Checks if the received persistent_id matches the stored @selected_instance_pid.
# - Finds the instance again using model.find_entity_by_persistent_id.
# - Parses the incoming JSON string back into a Ruby Hash.
# - Uses model.start_operation / model.commit_operation to make the changes undoable.
# - Iterates through the received attributes and uses instance.set_attribute(...) to save them back to the dynamic_attributes dictionary.
# - Crucial Step: Calls $dc_observers.get_latest_class.redraw_with_undo(instance) to force the Dynamic Component extension to recognize the changes and update.
# - Includes checks (defined?, respond_to?) for safety in case the DC extension isn't loaded or the method signature changes in future SU versions.
# - Sends success or error messages back to the dialog using execute_script.
# - Includes error handling (rescue) and model.abort_operation on failure.
# 
# HTML/CSS/JS (within get_html_content):
# 
# HTML:
# - Basic structure with buttons, a status area, component info display, and a container (attributesContainer) for the dynamic fields.
# 
# CSS:
# - Minimal styling for readability. Textareas have resize: vertical; and overflow: hidden; initially.
# 
# JavaScript:
# - Event listeners for Load/Save buttons.
# - sketchup.callback_name(...) is used to trigger Ruby callbacks.
# 
# populateForm(data):
# - Clears the container, stores the persistent_id, displays component info.
# - Iterates through received attributes, creates labels and textarea elements for each.
# - Sets data-key attributes for easy retrieval, and attaches the autoGrowTextarea listener.
# - Enables the save button.
# 
# saveSuccess(message)/handleError(message):
# - Functions called by Ruby to update the status div in the dialog.
# 
# autoGrowTextarea:
# - Simple JS function to adjust textarea height based on its scrollHeight.
# - Called on input and initially after populating.
# 
# currentPersistentId:
# - JS variable to hold the PID from the loaded data, used when saving.
# 
# Save Logic:
# - Gathers data from all textareas using the data-key attribute.
# - Sends it along with the currentPersistentId back to the receive_save_data Ruby callback.
# 
# Important Fix in JS:
# - The save logic now correctly sends the persistent_id as a separate argument to the Ruby callback receive_save_data, matching the Ruby definition.
# 
# Next Steps & Potential Improvements:
# 
# Refined Type Handling:
# - The current script saves everything as a string.
# - For attributes expected to be Lengths, Numbers, etc., you'd need logic (probably in save_component_data) to parse the string from the textarea and convert it back to the appropriate SketchUp type (e.g., using value.to_l for lengths if the string looks like a length).
# 
# Filtering Attributes:
# - You might want to hide internal DC attributes (often starting with _).
# - Add filtering logic in load_component_data.
# 
# Spell Check:
# - Integrate a JavaScript spell-checking library into the HTML/JS part.
# - There are many options (e.g., libraries that hook into the browser's native spell check, or standalone libraries).
# - This would purely be a front-end enhancement.
# 
# Error Handling:
# - More granular error reporting back to the user.
# 
# UI Styling:
# - Apply your custom CSS.
# 
# Extension Packaging:
# - Convert this script into a proper SketchUp extension (.rbx) with registration code, toolbar buttons, menus, etc. (Basic structure commented out at the end of the script).
# 
# Definition vs. Instance Attributes:
# - Decide if/how you want to display or edit attributes that might only exist on the definition.
# - The current script prioritizes the instance.
# 
# Asynchronous Operations:
# - For very complex components or slow operations, explore more advanced asynchronous patterns if the UI feels blocked.
# 
# This script provides the fundamental link between the selected DC and your custom HTML editor, addressing the core requirement of reliable data transfer and DC updating.
# Remember to test thoroughly, especially the redraw_with_undo part, as DC behavior can sometimes be quirky.

# endregion