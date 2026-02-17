# ---------------------------------------------------------------------------------------------------------------------
# NA | Noble Architecture BIM Tools | Core Plugin Script
# ---------------------------------------------------------------------------------------------------------------------
# region [col01] | 01 - Project Details & Version History
# ---------------------------------------------------------------------------------------------------------------------
#
# PLUGIN NAME   | Noble Architecture BIM Tool
# DESCRIPTION   | A SketchUp Plugin For Automating The Efficient Creation & Manipulation Of BIM Entities
# AUTHOR        | Studio Noodlfjørd
# CREATED       | 22-Jan-2025
#
# ROOT DIRECTORY
#   C:\Users\Administrator\AppData\Roaming\SketchUp\SketchUp 2025\SketchUp\Plugins
#
# THIS FILE
#   0SN20_20_02_--_NA_-_BIM-Classifier-Tool_-_2.3.0.rb
#
# DEVELOPMENT LOG
# - 0.0.1 - 22-Jan-2025 | Initial stable Beta testing version
# - 0.0.2 - 22-Jan-2025 | Minor GUI Tweaks
# - 0.0.3 - 22-Jan-2025 | Style updated
# - 0.1.0 - 22-Jan-2025 | Group Instance naming logic added
# - 0.2.0 - 22-Jan-2025 | Initial Cardinal direction system
# - 0.3.0 - 23-Jan-2025 | JSON-compatible BIM data structure
# - 0.3.4 - 23-Jan-2025 | Fixed Bugs 
# - 0.4.0 - 23-Jan-2025 | More "Level 4" Entity classifications
# - 0.5.0 - 24-Jan-2025 | Refactored Code, separated into multiple files, GUI Now separate HTML / CSS / JS
# - 0.6.0 - 26-Jan-2025 | Code reorganised into multiple files & modules.
# - 0.6.1 - 26-Jan-2025 | Tested, UI Works, Styled Correctly, Buttons Linked etc, Group Naming Works, Directions Work
# - 0.6.2 - 26-Jan-2025 | Confirmed All Features Work Apart From Dynamic Component Creation Feature
# - 0.7.0 - 26-Jan-2025 | Full Dynamic Component Handling Added
# - 0.8.0 - 27-Jan-2025 | Extensive Debugging Of DC Creation Feature
# - 0.9.0 - 27-Jan-2025 | Extensive Debugging Of DC Attribute Naming Function, Create-Component-Instance Script Rewritten
# - 0.9.1 - 27-Jan-2025 | Further Debugging to 02_02_--_NA_-_BIM_-_ToolsApp_-_Method_-_Create-Component-Instance.rb
# - 1.0.0 - 27-Jan-2025 | FIRST STABLE RELEASE! YAYY!  - Code Version Filed In Vault
#  -1.1.1 - 28-Jan-2025 | Duplicate Whitelist Logic Updated
#  -2.2.0 - 27-Apr-2025 | Naming simplified, Null Vales Created at each level
#  -2.2.1 - 27-Apr-2025 | Null options added as default for all fields, simplified naming implemented
#  -2.2.2 - 27-Apr-2025 | Added descriptive tag field for more flexible naming
#  -2.2.3 - 27-Apr-2025 | Improved UI, added new style for default text to be Grey and less obtrusive.
#  -2.2.4 - 27-Apr-2025 | Added rounding to nearest integer for all dimensional attributes
# ---------------------------------------------------------------------------------------------------------------------
# endregion
#
#
# ------------------------------------------------------------------------------------
# Noble Architecture | BIM Entity Creation Tools | SINGLE MERGED MASTER PLUGIN FILE
# ------------------------------------------------------------------------------------
#
# DESCRIPTION:
#   A single Ruby file that:
#    - Handles user selections in an HTML dialog (levels, unique ID, entity type).
#    - Automatically names created entities using a 5-level code scheme + optional
#      cardinal (elevation) descriptor if the user has saved a principal direction.
#    - Creates either a Group or a Dynamic Component from the selected geometry.
#    - Writes debug/error logs to /na_plugin-dependencies/error_log.txt, creating
#      that folder if needed.
#
# RUN COMMAND
# `NA::EntityClassifier::EntityClassifierApp.new.run`
# - Used for testing script updates without reloading 
#
# CARDINAL DIRECTION LOGIC
#   The cardinal direction logic is specifically used if the selected element code
#   (level_04) is one of the "E03", "E04", "E08", or "E18" codes, and the user has
#   saved a principal elevation direction on the "Site Information" page. In that
#   case, the plugin calls 'CardinalDirection.calculate_elevation_name' and appends
#   that direction to the final name (e.g. "North-Elevation").
#
#
# ------------------------------------------------------------------------------------
require 'sketchup.rb'
require 'erb'
require 'fileutils'

module NA
  module EntityClassifier

    # region [CLASS] | EntityClassifierApp
    # --------------------------------------------------------------------------------
    class EntityClassifierApp

      def initialize
        # region [INLINE CSS]
        # --------------------------------------------------------------------------------
        @css_content = <<-CSS
body {
    font-family: 'Open Sans', sans-serif;
    margin: 8px;
    color: #333333;
    background: #f8f8f8;
}

h2 {
    font-family: 'Open Sans', sans-serif;
    font-weight: 600;
    font-size: 18.00pt;
    color: #333333;
    margin-top: 20px;
    margin-left: 20px;
    margin-bottom: 10px;
}

.menu_header {
    text-align: left;
    margin-bottom: 15px;
    padding-bottom: 15px;
    border-bottom: 1px solid #e0e0e0;
}
.company_logo {
    width: 75mm;
    height: auto;
    display: block;
    margin-top: 20px;
    margin-left: 10px;
    margin-right: auto;
    margin-bottom: 30px;
}

.type-toggle-container {}
.type-toggle {
    display: flex;
    gap: 8px;
    margin-bottom: 20px;
}
.type-toggle input[type="radio"] {
    display: none;
}
.type-toggle label {
    flex: 1;
    padding: 12px;
    border: 1px solid #cccccc;
    border-radius: 3px;
    text-align: center;
    cursor: pointer;
    font-family: 'Open Sans', sans-serif;
    font-weight: 500;
    color: #555041;
    background: #ffffff;
    transition: all 0.2s ease;
}
.type-toggle input:checked + label {
    background: #787369;
    color: #ffffff;
    border-color: #5580A5;
    font-weight: 600;
}

.dropdown_section {
    margin-bottom: 15px;
    background: #ffffff;
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    padding: 12px;
}
.dropdown_section h3 {
    font-family: 'Open Sans', sans-serif;
    font-weight: 600;
    font-size: 11pt;
    color: #444444;
    margin: 0 0 8px 0;
}
.dropdown_section p.help-text {
    font-size: 9pt;
    color: #666666;
    margin-top: 8px;
    line-height: 1.4;
}
select {
    width: 100%;
    padding: 8px;
    border: 1px solid #d0d0d0;
    border-radius: 3px;
    font-size: 10.5pt;
    background: #ffffff;
    color: #444444;
}

.component-code-input-box {
    font-family: 'Open Sans', sans-serif;
    font-size: 10.5pt;
    width: 100%;
    padding: 8px;
    margin: 5px 0;
    border: 1px solid #d0d0d0;
    border-radius: 3px;
    color: #444444;
    background: #ffffff;
}
.component-code-input-box:invalid {
    border-color: #ff4444;
    background-color: #fff0f0;
}

button {
    background: #787369;
    color: #ffffff;
    border: none;
    padding: 12px 24px;
    border-radius: 3px;
    cursor: pointer;
    width: 100%;
    font-weight: 600;
    font-size: 11.00pt;
    letter-spacing: 0.5px;
    transition: all 0.2s ease;
    margin-top: 15px;
}
button:hover {
    background: #555041;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.nav-buttons {
    margin-top: 20px;
    display: flex;
    gap: 8px;
}
.nav-button {
    background: #e0e0e0;
    color: #555041;
    padding: 8px 16px;
    font-size: 10pt;
    width: auto;
    border-radius: 3px;
    cursor: pointer;
}
.nav-button:hover {
    background: #cccccc;
}

.help-text {
    font-size: 9pt;
    color: #666666;
    margin-top: 8px;
    line-height: 1.4;
}

#main-page, #site-info-page {
    display: none;
}

#main-page {
    display: block;
}

/* --- New for greyed-out dropdowns --- */
.dropdown_section select {
    color: #444444;
}
.dropdown_section select.null-selected {
    color: #b0b0b0;
}
.dropdown_section option {
    color: #444444;
}
.dropdown_section option.null-option {
    color: #b0b0b0;
}
        CSS

        # region [INLINE JS]
        # --------------------------------------------------------------------------------
        @js_content = <<-JS
document.addEventListener('DOMContentLoaded', () => {

  // Set all dropdowns to null value by default and apply greyed style
  document.querySelectorAll('.dropdown_section select').forEach(select => {
    select.value = "0000";
    select.classList.add('null-selected');
    select.addEventListener('change', function() {
      if (this.value === "0000") {
        this.classList.add('null-selected');
      } else {
        this.classList.remove('null-selected');
      }
    });
  });

  const codeInput = document.getElementById('component-code');
  if(codeInput){
    codeInput.addEventListener('input', function() {
      this.value = this.value.replace(/[^0-9]/g, '').slice(0, 2);
    });
    // Default to "00" when level_05 is null
    codeInput.value = "00";
  }

  const createBtn = document.getElementById('create-button');
  if(createBtn){
    createBtn.addEventListener('click', handleCreate);
  }

  const siteInfoBtn = document.getElementById('show-site-info-button');
  if(siteInfoBtn){
    siteInfoBtn.addEventListener('click', showSiteInfo);
  }

  const saveSiteBtn = document.getElementById('save-site-info-button');
  if(saveSiteBtn){
    saveSiteBtn.addEventListener('click', saveSiteInfo);
  }

  const pluginSettingsBtn = document.getElementById('plugin-settings-button');
  if(pluginSettingsBtn){
    pluginSettingsBtn.addEventListener('click', showPluginSettings);
  }

  // Add event listener for level_05 dropdown to update component code
  const level05Select = document.getElementById('level_05');
  if(level05Select && codeInput) {
    level05Select.addEventListener('change', function() {
      if(this.value === "0000") {
        codeInput.value = "00";
      }
    });
  }

});

function handleCreate() {
  const codeInput = document.getElementById('component-code');
  if (!codeInput || !/^[0-9]{2}$/.test(codeInput.value)) {
    alert("Please enter a valid 2-digit code (00-99).");
    if (codeInput) codeInput.focus();
    return;
  }

  const selections = {};
  document.querySelectorAll('.dropdown_section select').forEach(select => {
    selections[select.id] = select.value;
  });
  selections['component_code'] = codeInput.value.padStart(2, '0');
  
  // Get descriptive tag value
  const descriptiveTag = document.getElementById('descriptive-tag');
  selections['descriptive_tag'] = descriptiveTag ? descriptiveTag.value.trim() : "";

  const entityTypeToggle = document.querySelector('input[name="entity-type"]:checked');
  if (!entityTypeToggle) {
    alert("Please select an entity type (Group or Component).");
    return;
  }
  const entityType = entityTypeToggle.value;

  try {
    sketchup.createEntity(entityType, selections);
  } catch (error) {
    console.error('Error calling SketchUp API:', error);
    alert("Failed to communicate with SketchUp. See console for details.");
  }

  codeInput.value = '';
  if (descriptiveTag) descriptiveTag.value = '';
}

function showSiteInfo() {
  document.getElementById('main-page').style.display = 'none';
  document.getElementById('site-info-page').style.display = 'block';
}

function showMainPage() {
  document.getElementById('site-info-page').style.display = 'none';
  document.getElementById('main-page').style.display = 'block';
}

function saveSiteInfo() {
  const direction = document.getElementById('cardinal-direction').value;
  sketchup.saveSiteInfo({ direction });
  showMainPage();
}

function showPluginSettings() {
  alert('Plugin settings coming in a future version!');
}
        JS
        # endregion
      end

      def run
        # Build and display the UI
        html_content = build_html_dialog
        dialog       = UI::HtmlDialog.new(
          dialog_title:    "BIM Entity Creation Tools",
          preferences_key: "NA_BIM_EntityCreation",
          width:           400,
          height:          600,
          resizable:       true
        )
        dialog.set_html(html_content)

        # Callback to create entity
        dialog.add_action_callback("createEntity") do |_ctx, entity_type, selections|
          begin
            handle_create_entity(entity_type, selections)
          rescue => e
            UI.messagebox("Error creating entity: #{e.message}")
            EntityClassifierApp.log_error(e)
          end
        end

        # Callback to save site info
        dialog.add_action_callback("saveSiteInfo") do |_ctx, data|
          begin
            handle_save_site_info(data)
          rescue => e
            UI.messagebox("Error saving site info: #{e.message}")
            EntityClassifierApp.log_error(e)
          end
        end

        dialog.show
      end

      # region [HTML] | Build The Inline HTML
      # --------------------------------------------------------------------------------
      def build_html_dialog
        dropdowns = generate_dropdowns
        template = <<-HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Noble Architecture | BIM Entity Creation Tools</title>
  <style>
    <%= @css_content %>
  </style>
</head>
<body>

  <div id="main-page">
    <div class="menu_header">
      <img src="C:/Users/Administrator/AppData/Roaming/SketchUp/SketchUp 2025/SketchUp/Plugins/na_plugin-dependencies/RE20_22_01_01_-_PNG_-_NA_Company_Logo.png"
           class="company_logo"
           alt="Noble Architecture">
      <h2>Noble Architecture | BIM Entity Creation Tools</h2>
    </div>

    <div class="type-toggle-container">
      <div class="type-toggle">
        <input type="radio" name="entity-type" id="group-type" value="group">
        <label for="group-type">Group</label>

        <input type="radio" name="entity-type" id="component-type" value="component" checked>
        <label for="component-type">Dynamic Component</label>
      </div>
    </div>

    <%= dropdowns %>

    <div class="dropdown_section">
      <h3>Unique Identifier Code</h3>
      <input type="text"
             id="component-code"
             class="component-code-input-box"
             pattern="[0-9]{2}"
             maxlength="2"
             placeholder="00"
             title="Enter a 2-digit number between 00-99">
    </div>

    <div class="dropdown_section">
      <h3>Descriptive Tag (Optional)</h3>
      <p class='help-text'>Will be appended to the end of the entity name for better visual identification.</p>
      <input type="text"
             id="descriptive-tag"
             class="component-code-input-box"
             maxlength="30"
             placeholder="Leave empty to use default">
    </div>

    <button id="create-button">Create Classifier Entity</button>

    <div class="nav-buttons">
      <button id="show-site-info-button" class="nav-button">Site Information</button>
      <button id="plugin-settings-button" class="nav-button" disabled>Plugin Settings</button>
    </div>
  </div>

  <div id="site-info-page" style="display:none;">
    <h2>Site Configuration</h2>
    <div class="dropdown_section">
      <h3>Principal Elevation Direction</h3>
      <select id="cardinal-direction">
        <option value="North">North</option>
        <option value="South">South</option>
        <option value="East">East</option>
        <option value="West">West</option>
        <option value="North East">North East</option>
        <option value="North West">North West</option>
        <option value="South East">South East</option>
        <option value="South West">South West</option>
      </select>
    </div>

    <div class="nav-buttons">
      <button id="save-site-info-button" class="action-button">Save Settings</button>
      <button onclick="showMainPage()" class="nav-button">← Back to Main</button>
    </div>
  </div>

  <script>
    <%= @js_content %>
  </script>
</body>
</html>
        HTML

        ERB.new(template).result(binding)
      end

      # endregion

      # region [EVENTS] | Callback Handlers
      # --------------------------------------------------------------------------------
      def handle_create_entity(entity_type, selections)
        # 1) Validate
        return unless ClassifierNaming.validate_selections(selections)

        # 2) Generate name
        entity_name = ClassifierNaming.generate_entity_name(selections)
        return unless entity_name

        model     = Sketchup.active_model
        selection = model.selection

        if entity_type == "component"
          CreateClassifierComponent.create_component_instance(model, selection, entity_name, selections)
        else
          CreateClassifierGroup.create_group_instance(model, selection, entity_name, selections)
        end
      end

      def handle_save_site_info(data)
        direction = data['direction'] || "North"
        model     = Sketchup.active_model
        dict      = model.attribute_dictionary("NA_Classifier_SiteInfo", true)
        dict["cardinal_direction"] = direction
        UI.messagebox("Site configuration saved successfully!")
      end

      # endregion

      # region [DROPDOWNS] | Generate The 5 Levels
      # --------------------------------------------------------------------------------
      def generate_dropdowns
        library  = ClassifierDefinitions.data["naming_definitions"]
        sections = []

        %w[level_01 level_02 level_03 level_04 level_05].each do |key|
          definition = library[key]
          next unless definition

          # New: Null option text
          null_text = "Select #{definition['name']} Value"

          block = <<-HTML
          <div class="dropdown_section">
            <h3>#{definition['name']}</h3>
            #{definition['description'] ? "<p class='help-text'>#{definition['description']}</p>" : ""}
            <select id="#{key}" class="null-selected">
              <option value="0000" class="null-option">#{null_text}</option>
              #{definition['options'].map { |code, desc| next if code == "0000"; "<option value='#{code}'>#{code} - #{desc}</option>" }.compact.join}
            </select>
          </div>
          HTML

          sections << block
        end

        sections.join
      end

      # region [ERROR] | Logging
      # --------------------------------------------------------------------------------
      def self.log_error(exception)
        begin
          base_dir = File.dirname(__FILE__)
          log_dir  = File.join(base_dir, "na_plugin-dependencies")
          FileUtils.mkdir_p(log_dir) unless File.exist?(log_dir)

          log_file = File.join(log_dir, "error_log.txt")
          File.open(log_file, "a") do |file|
            file.puts("[#{Time.now}] #{exception.class}: #{exception.message}")
            file.puts(exception.backtrace.join("\n"))
            file.puts("-" * 60)
          end
        rescue => e
          UI.messagebox("Failed to write to log file: #{e.message}")
        end
      end
      # endregion

    end
    # endregion


    # region [NAMING] | ClassifierNaming
    # --------------------------------------------------------------------------------
    module ClassifierNaming

      UNIQUE_CODES = %w[WD01 DE01 DR01 SC01 BM01 CM01].freeze

      def self.validate_selections(selections)
        required_keys = %w[level_01 level_02 level_03 level_04 level_05 component_code]
        missing = required_keys.select { |k| selections[k].nil? }
        unless missing.empty?
          UI.messagebox("Missing selections: #{missing.join(', ')}")
          return false
        end
        
        # If all levels are set to null (0000), require at least one non-null level
        all_null = true
        %w[level_01 level_02 level_03 level_04 level_05].each do |level|
          if selections[level] != "0000"
            all_null = false
            break
          end
        end
        
        if all_null
          UI.messagebox("Please select at least one non-null level for classification.")
          return false
        end

        # For null level_05, component_code must be 00
        if selections["level_05"] == "0000" && selections["component_code"] != "00"
          UI.messagebox("When 'None (Null Value)' is selected for Component Tag ID, the Unique Identifier Code must be '00'.")
          return false
        end

        unless selections["component_code"] =~ /^\d{2}$/
          UI.messagebox("Unique Identifier Code must be a 2-digit number between 00-99.")
          return false
        end

        # Descriptive tag validation (only length for now)
        if selections["descriptive_tag"] && selections["descriptive_tag"].length > 30
          UI.messagebox("Descriptive tag must be 30 characters or less.")
          return false
        end

        true
      end

      def self.generate_entity_name(selections)
        naming_data = ClassifierDefinitions.data["naming_definitions"]
        base_keys   = %w[level_01 level_02 level_03 level_04 level_05]
        
        # Filter out null values before joining
        base_parts = []
        base_keys.each_with_index do |k, i|
          if selections[k] != "0000"
            base_parts << selections[k]
          end
        end

        # If level_05 is non-null, append the component_code to it
        if selections["level_05"] != "0000"
          user_code = selections["component_code"]
          # Remove last 2 digits and append user code
          last_part = base_parts.pop
          if last_part
            modified_part = last_part[0..-3] + user_code
            base_parts << modified_part
          end
        end
        
        # If all parts are null, create a minimal name with just a unique identifier
        if base_parts.empty?
          pot_name = "NA_BIM_Entity_#{Time.now.to_i}"
          return pot_name
        end
        
        # Join the non-null parts
        pot_name = "#{base_parts.join}_-_"

        # descriptors
        descriptors = []

        # Check if we require cardinal direction
        element_type_code  = selections["level_04"] && selections["level_04"] != "0000" ? selections["level_04"][0..2] : nil
        elevation_required = element_type_code && naming_data["elevation_required"]["element_codes"].include?(element_type_code)

        if elevation_required && selections["level_05"] != "0000"
          elevation_name = CardinalDirection.calculate_elevation_name
          descriptors << elevation_name if elevation_name
        end

        # Only add floor descriptor if level_02 is not null
        if selections["level_02"] != "0000"
          floor_desc = naming_data["level_02"]["options"][selections["level_02"]].gsub(' ', '-')
          descriptors << floor_desc
        end

        # Only add status and element type if they're not null
        if selections["level_03"] != "0000" && selections["level_04"] != "0000"
          status_desc = naming_data["level_03"]["options"][selections["level_03"]].split.first
          elem_type   = naming_data["level_04"]["options"][selections["level_04"]].split.last if selections["level_04"] != "0000"
          
          if elem_type
            elem_type = elem_type[0..-2] if elem_type.end_with?('s')
            descriptors << "#{status_desc}-#{elem_type}-No-#{selections['component_code']}"
          end
        end

        # Add descriptive tag if it exists
        if selections["descriptive_tag"] && !selections["descriptive_tag"].empty?
          descriptors << selections["descriptive_tag"]
        end

        pot_name += descriptors.join('_-_') unless descriptors.empty?
        
        # For nil descriptors, use a cleaner format
        if descriptors.empty?
          pot_name.chomp!('_-_')
        end
        
        component_code = selections["level_05"] != "0000" ? selections["level_05"] : nil

        # Dup check only if we have a component code
        if component_code && UNIQUE_CODES.include?(component_code)
          if entity_exists?(pot_name)
            UI.messagebox("A unique entity named '#{pot_name}' already exists.")
            return nil
          end
        elsif component_code && naming_data["construction_details_exclude"]["element_codes"].include?(component_code)
          # whitelisted
        else
          if entity_exists?(pot_name)
            UI.messagebox("Duplicate found! Existing entity selected. Please choose a different code.")
            return nil
          end
        end

        pot_name
      rescue => e
        EntityClassifierApp.log_error(e)
        UI.messagebox("Error generating entity name: #{e.message}")
        nil
      end

      def self.entity_exists?(entity_name)
        model = Sketchup.active_model
        existing = model.entities.find { |e| e.respond_to?(:name) && e.name == entity_name }
        if existing
          model.selection.clear
          model.selection.add(existing)
          true
        else
          false
        end
      end

    end
    # endregion


    # region [CARDINAL] | CardinalDirection
    # --------------------------------------------------------------------------------
    module CardinalDirection

      def self.calculate_elevation_name
        cd = cardinal_direction
        return "Front-Elevation" unless cd

        view   = Sketchup.active_model.active_view
        camera = view.camera
        dir    = camera.direction

        side =
          if dir.y >  0.7
            :front
          elsif dir.y < -0.7
            :back
          elsif dir.x >  0.7
            :right
          elsif dir.x < -0.7
            :left
          else
            :front
          end

        real_dir = cardinal_rotation(cd, side)
        "#{real_dir}-Elevation"
      end

      def self.cardinal_direction
        model = Sketchup.active_model
        dict  = model.attribute_dictionary("NA_Classifier_SiteInfo", false)
        dict ? dict["cardinal_direction"] : nil
      end

      def self.cardinal_rotation(front_dir, side)
        lookup = {
          "North"      => { left: "West",       right: "East",       back: "South"      },
          "South"      => { left: "East",       right: "West",       back: "North"      },
          "East"       => { left: "North",      right: "South",      back: "West"       },
          "West"       => { left: "South",      right: "North",      back: "East"       },
          "North East" => { left: "North West", right: "South East", back: "South West" },
          "North West" => { left: "South West", right: "North East", back: "South East" },
          "South East" => { left: "North East", right: "South West", back: "North West" },
          "South West" => { left: "South East", right: "North West", back: "North East" }
        }

        return front_dir if side == :front
        lookup.fetch(front_dir, {}).fetch(side, front_dir)
      end

    end
    # endregion


    # region [CLASSIFIER DEFINITIONS]
    # --------------------------------------------------------------------------------
    module ClassifierDefinitions

      def self.data
        {
          "naming_definitions" => {
            "elevation_required" => {
              "name"          => "Elements Requiring Elevation Identification",
              "description"   => "Element types requiring cardinal directions in their names",
              "element_codes" => ["E03", "E04", "E08", "E18"]
            },
            "construction_details_exclude" => {
              "name"          => "Construction Details Whitelist",
              "description"   => "Codes excluded from duplication checks",
              "element_codes" => ["EW01","PT01","PT02","MR01","BK01","GF01","IF01","FS01","FT02","FP01","RP01","RF01","IC01","RW01","0000"]
            },
            "level_01" => {
              "name"        => "Top Level Container",
              "description" => "Primary classification of the entity",
              "options"     => {
                "0000" => "None (Null Value)",
                "M10_" => "Existing Conditions",
                "M20_" => "Proposed Design",
                "M30_" => "Design Alterations Illustration",
                "M40_" => "Construction Details"
              }
            },
            "level_02" => {
              "name"        => "Element Floor Level",
              "description" => "Specifies floor or site level",
              "options"     => {
                "0000" => "None (Null Value)",
                "L00_" => "Site Elements",
                "L01_" => "Ground Floor",
                "L11_" => "First Floor",
                "L21_" => "Second Floor"
              }
            },
            "level_03" => {
              "name"        => "Element Status",
              "description" => "Existing, proposed, or altered status",
              "options"     => {
                "0000" => "None (Null Value)",
                "S00_" => "Existing To Remain",
                "S05_" => "Existing To Be Removed",
                "S10_" => "Alterations To Existing",
                "S20_" => "Proposed New Element",
                "S30_" => "Replacement Element",
                "S40_" => "Refurbished Element"
              }
            },
            "level_04" => {
              "name"        => "Element Type",
              "description" => "Windows, doors, roof elements, etc.",
              "options"     => {
                "0000" => "None (Null Value)",
                "E00_" => "General",
                "E01_" => "Floors",
                "E02_" => "Walls",
                "E03_" => "Windows",
                "E04_" => "Exterior Doors",
                "E05_" => "Interior Doors",
                "E06_" => "Staircase",
                "E07_" => "Services",
                "E08_" => "Rainwater Goods",
                "E09_" => "Roof",
                "E10_" => "Structural Beams",
                "E11_" => "Structural Columns",
                "E14_" => "Outdoor Terrace",
                "E15_" => "Outdoor Structures",
                "E16_" => "Site Ground Level",
                "E17_" => "Site Walls",
                "E18_" => "Boundary Treatment",
                "E19_" => "Site Vegetation"
              }
            },
            "level_05" => {
              "name"        => "Component Tag ID Code",
              "description" => "Unique code for tagging/reference",
              "options"     => {
                "0000" => "None (Null Value)",
                "WD01" => "Window Code",
                "DE01" => "Exterior Door Code",
                "DR01" => "Interior Door Code",
                "BM01" => "Structural Beam Code",
                "CM01" => "Structural Column Code",
                "EW01" => "External Wall Code",
                "WI01" => "Interior Wall Code",
                "PT01" => "Partition Type 1",
                "PT02" => "Partition Type 2",
                "MR01" => "Masonry Detail",
                "BK01" => "Brickwork / Blockwork Code",
                "GF01" => "Ground Floor Code",
                "IF01" => "Intermediate Floor Code",
                "FS01" => "Strip Foundation Code",
                "FT02" => "Trench Foundation Code",
                "FP01" => "Pad Foundation Code",
                "RP01" => "Pitched Roof Code",
                "RF01" => "Flat Roof Code",
                "IC01" => "Intermediate Ceiling Code",
                "RW01" => "Fascia Code"
              }
            }
          }
        }
      end

    end
    # endregion


    # region [GROUP] | CreateClassifierGroup
    # --------------------------------------------------------------------------------
    module CreateClassifierGroup

      def self.create_group_instance(model, selection, entity_name, _selections)
        if selection.empty?
          UI.messagebox("No entities selected for group creation!")
          return
        end

        model.start_operation("Create Classifier Group", true)
        begin
          grp = model.active_entities.add_group(selection.to_a)
          grp.name = entity_name
          selection.clear

          model.commit_operation
          UI.messagebox("Created group: #{entity_name}")
        rescue => e
          model.abort_operation
          UI.messagebox("Error creating group: #{e.message}")
          EntityClassifierApp.log_error(e)
        end
      end

    end
    # endregion


    # region [COMPONENT] | CreateClassifierComponent
    # --------------------------------------------------------------------------------
    # ------------------------------------------------------------------------------------------------
    # Replacement module for CreateClassifierComponent in the BIM Classifier master script
    # ------------------------------------------------------------------------------------------------
    module CreateClassifierComponent
    
      # Main entry method called when user selects "Dynamic Component" creation
      def self.create_component_instance(model, selection, entity_name, selections)
        if selection.empty?
          UI.messagebox("No entities selected! Please select geometry to create a Dynamic Component.")
          return
        end
    
        model.start_operation("Create Classifier Component", true)
        begin
          # Convert the selected geometry into a group first (if user selects multiple entities)
          grp = model.active_entities.add_group(selection.to_a)
          # Now convert that group into a component
          instance = grp.to_component
          # Make it unique (avoids merging with other instances if they share geometry)
          instance.make_unique
    
          # Only set the definition name, not the instance name
          instance.definition.name = entity_name
          
          selection.clear
          selection.add(instance)
    
          # Assign full dynamic component attributes
          set_component_attributes(instance, selections)
    
          # Attempt a DC redraw if the Dynamic Components extension is available
          if defined?($dc_observers) && $dc_observers.respond_to?(:get_latest_class)
            dc_class = $dc_observers.get_latest_class
            if dc_class.respond_to?(:redraw_with_undo)
              dc_class.redraw_with_undo(instance)
            else
              # Fallback: refresh thumbnail
              instance.definition.refresh_thumbnail
            end
          else
            # Fallback: refresh thumbnail if dynamic observers are not available
            instance.definition.refresh_thumbnail
          end
    
          model.commit_operation
          UI.messagebox("Created Dynamic Component:\n#{entity_name}")
    
        rescue => e
          model.abort_operation
          UI.messagebox("Error creating Dynamic Component:\n#{e.message}")
          EntityClassifierApp.log_error(e)
        end
      end
    
      # --------------------------------------------------------------------------
      # set_component_attributes
      #
      # Applies the A-Series, B-Series, C-Series, D-Series, E-Series, F-Series, and T-Series
      # attributes from the project information document, adapted to use the ClassifierDefinitions
      # and CardinalDirection modules from the main script.
      # --------------------------------------------------------------------------
      def self.set_component_attributes(instance, selections)
        definition = instance.definition
        da_key     = "dynamic_attributes"
    
        # Set the dynamic component dialog size (if desired)
        definition.set_attribute(da_key, 'dialogwidth',  600)
        definition.set_attribute(da_key, 'dialogheight', 800)
    
        # A-Series (combined code + description)
        assign_a_series(definition, da_key, selections)
    
        # B-Series (processed text / naming details)
        assign_b_series(definition, da_key, selections)
    
        # C-Series (custom metadata placeholders)
        assign_c_series(definition, da_key)
    
        # D-Series (dimension placeholders)
        assign_d_series(definition, da_key)
    
        # E-Series (component location & height)
        assign_e_series(instance, definition, da_key)
        
        # F-Series (model notes & metadata)
        assign_f_series(definition, da_key)
        
        # T-Series (technical drawings)
        assign_t_series(definition, da_key)
      end
    
      # --------------------------------------------------------------------------
      # A-SERIES  |  Combine Code + Description from Each Level
      # --------------------------------------------------------------------------
      def self.assign_a_series(definition, da_key, selections)
        # level_01
        code_01      = selections["level_01"] || ""
        desc_01      = get_description("level_01", code_01)
        combined_01  = code_01 == "0000" ? "Not Defined" : "#{sanitize_code(code_01)} - #{desc_01}"
        set_dc_textbox(definition, da_key, "a1_level_01", combined_01, "Entity Model Class")
    
        # level_02
        code_02      = selections["level_02"] || ""
        desc_02      = get_description("level_02", code_02)
        combined_02  = code_02 == "0000" ? "Not Defined" : "#{sanitize_code(code_02)} - #{desc_02}"
        set_dc_textbox(definition, da_key, "a2_level_02", combined_02, "Entity Floor Level")
    
        # level_03
        code_03      = selections["level_03"] || ""
        desc_03      = get_description("level_03", code_03)
        combined_03  = code_03 == "0000" ? "Not Defined" : "#{sanitize_code(code_03)} - #{desc_03}"
        set_dc_textbox(definition, da_key, "a3_level_03", combined_03, "Entity Status")
    
        # level_04
        code_04      = selections["level_04"] || ""
        desc_04      = get_description("level_04", code_04)
        combined_04  = code_04 == "0000" ? "Not Defined" : "#{sanitize_code(code_04)} - #{desc_04}"
        set_dc_textbox(definition, da_key, "a4_level_04", combined_04, "Entity Type")
    
        # level_05
        code_05      = selections["level_05"] || ""
        desc_05      = get_description("level_05", code_05)
        combined_05  = code_05 == "0000" ? "Not Defined" : "#{sanitize_code(code_05)} - #{desc_05}"
        set_dc_textbox(definition, da_key, "a5_level_05", combined_05, "Component Tag ID Code")
        
        # descriptive tag
        descriptive_tag = selections["descriptive_tag"] || ""
        set_dc_textbox(definition, da_key, "a6_descriptive_tag", descriptive_tag.empty? ? "Not Defined" : descriptive_tag, "Descriptive Tag")
      end
    
      # --------------------------------------------------------------------------
      # B-SERIES  |  More User-Friendly Text Fields
      # --------------------------------------------------------------------------
      def self.assign_b_series(definition, da_key, selections)
        # Floor
        code_02 = selections["level_02"] || ""
        desc_02 = get_description("level_02", code_02)
        floor_text = code_02 == "0000" ? "Not Defined" : desc_02
        set_dc_textbox(definition, da_key, "b1_ent_floor", floor_text, "Element Floor Level")
    
        # Status
        code_03 = selections["level_03"] || ""
        desc_03 = get_description("level_03", code_03)
        status_text = code_03 == "0000" ? "Not Defined" : desc_03
        set_dc_textbox(definition, da_key, "b2_ent_status", status_text, "Element Status")
    
        # Type (singular if it ends with an 's')
        code_04 = selections["level_04"] || ""
        desc_04 = get_description("level_04", code_04)
        if code_04 == "0000"
          type_text = "Not Defined"
        else
          desc_04_singular = desc_04 && desc_04.end_with?('s') ? desc_04.chomp('s') : desc_04
          type_text = desc_04_singular
        end
        set_dc_textbox(definition, da_key, "b3_ent_type", type_text, "Element Type")
    
        # ID code (merge 5th code with user two-digit code)
        code_05 = selections["level_05"] || ""
        user_digits = selections["component_code"] || "00"
        
        if code_05 == "0000"
          id_code = "Not Defined"
        else
          id_code = merge_5th_code_with_user_digits(code_05, user_digits)
        end
        set_dc_textbox(definition, da_key, "b4_ent_id_code", id_code, "Element ID Code")
    
        # Elevation (only if required by naming_definitions.elevation_required)
        if code_04 != "0000" && requires_cardinal_elevation?(code_04)
          direction_str = CardinalDirection.calculate_elevation_name
          final_elev = direction_str ? direction_str : "Not Applicable"
        else
          final_elev = "Not Applicable"
        end
    
        set_dc_textbox(definition, da_key, "b5_ent_elevation", final_elev, "Element Elevation")
        
        # Descriptive tag (B-series)
        descriptive_tag = selections["descriptive_tag"] || ""
        set_dc_textbox(definition, da_key, "b6_descriptive_tag", descriptive_tag.empty? ? "Not Defined" : descriptive_tag, "Descriptive Tag")
      end
    
      # --------------------------------------------------------------------------
      # C-SERIES  |  Element Macro Information 
      # --------------------------------------------------------------------------
      def self.assign_c_series(definition, da_key)
        set_dc_textbox(definition, da_key, "c1_element_material",  "Element Material - Not Defined" , "Element Material")
        set_dc_textbox(definition, da_key, "c2_element_finish"  ,  "Element Finish - Not Defined"   , "Element Finish")
        set_dc_textbox(definition, da_key, "c3_element_product" ,  "Element Product - Not Defined"  , "Element Product")
        set_dc_textbox(definition, da_key, "c4_element_info_01" ,  "Custom Info 01 - Not Defined"   , "Custom Info 01")
      end
    
      # --------------------------------------------------------------------------
      # D-SERIES  |  Dimension Placeholders
      # --------------------------------------------------------------------------
      def self.assign_d_series(definition, da_key)
        # d1_length
        definition.set_attribute(da_key, "d1_length", "")
        definition.set_attribute(da_key, "_d1_length_label",  "Object Length")
        definition.set_attribute(da_key, "_d1_length_access", "VIEW")
        definition.set_attribute(da_key, "_d1_length_units",  "INTEGER")
        definition.set_attribute(da_key, "_d1_length_formula", "round(LenX * 25.4)")
    
        # d2_width
        definition.set_attribute(da_key, "d2_width", "")
        definition.set_attribute(da_key, "_d2_width_label",  "Object Width")
        definition.set_attribute(da_key, "_d2_width_access", "VIEW")
        definition.set_attribute(da_key, "_d2_width_units",  "INTEGER")
        definition.set_attribute(da_key, "_d2_width_formula", "round(LenY * 25.4)")
    
        # d3_height
        definition.set_attribute(da_key, "d3_height", "")
        definition.set_attribute(da_key, "_d3_height_label",  "Object Height")
        definition.set_attribute(da_key, "_d3_height_access", "VIEW")
        definition.set_attribute(da_key, "_d3_height_units",  "INTEGER")
        definition.set_attribute(da_key, "_d3_height_formula", "round(LenZ * 25.4)")
    
        # d8_height_from_datum
        definition.set_attribute(da_key, "d8_height_from_datum", "")
        definition.set_attribute(da_key, "_d8_height_from_datum_label",  "Object Height From Datum")
        definition.set_attribute(da_key, "_d8_height_from_datum_access", "VIEW")
        definition.set_attribute(da_key, "_d8_height_from_datum_units",  "INTEGER")
        definition.set_attribute(da_key, "_d8_height_from_datum_formula", "round(Z * 25.4)")
      end
    
      # --------------------------------------------------------------------------
      # E-SERIES  |  Component Location & Height
      # --------------------------------------------------------------------------
      def self.assign_e_series(instance, definition, da_key)
        # Global position
        position = instance.transformation.origin
        set_dc_textbox(definition, da_key, "e1_global_position_x", (position.x * 25.4).round.to_s, "Global X Position")
        set_dc_textbox(definition, da_key, "e2_global_position_y", (position.y * 25.4).round.to_s, "Global Y Position")
        set_dc_textbox(definition, da_key, "e3_global_position_z", (position.z * 25.4).round.to_s, "Global Z Position")
        
        # Local position (relative to parent)
        # Note: This is a simplified implementation - in a real scenario, you might need to calculate
        # the local position based on the parent component's transformation
        set_dc_textbox(definition, da_key, "e4_local_position_x", "0", "Local X Position")
        set_dc_textbox(definition, da_key, "e5_local_position_y", "0", "Local Y Position")
        set_dc_textbox(definition, da_key, "e6_local_position_z", "0", "Local Z Position")
        
        # Height from datums
        set_dc_textbox(definition, da_key, "e8_height_from_datum", (position.z * 25.4).round.to_s, "Height From Main Site Datum")
        set_dc_textbox(definition, da_key, "e9_height_from_secondary_datum", "0", "Height From Secondary Datum Point")
      end
      
      # --------------------------------------------------------------------------
      # F-SERIES  |  Model Notes & Metadata
      # --------------------------------------------------------------------------
      def self.assign_f_series(definition, da_key)
        # Get current date in dd-mmm-yyyy format
        current_date = Time.now.strftime("%d-%b-%Y")
        
        set_dc_textbox(definition, da_key, "f1_model_notes"    , "Model Notes - Not Defined" , "General Notes")
        set_dc_textbox(definition, da_key, "f2_model_author"   , "Studio Noblefjord"         , "Version Author")
        set_dc_textbox(definition, da_key, "f3_model_created"  , current_date                , "Creation Date")
        set_dc_textbox(definition, da_key, "f4_model_modified" , current_date                , "Last Modified")
      end
      
      # --------------------------------------------------------------------------
      # T-SERIES  |  Technical Drawings
      # --------------------------------------------------------------------------
      def self.assign_t_series(definition, da_key)
        # General Specification Notes
        set_dc_textbox(definition, da_key, "t1_note_title", "General Specifications", "Specification Title")
        set_dc_textbox(definition, da_key, "t2_note_text", "▹ No specifications defined yet.", "Specification Text")
        
        # Critical Notes
        set_dc_textbox(definition, da_key, "t3_critical_note_title", "Critical Notes & Key Considerations", "Critical Notes Title")
        set_dc_textbox(definition, da_key, "t4_critical_note_text", "▹ No critical requirements defined yet.", "Critical Notes Text")
        
        # Thermal Performance Notes
        set_dc_textbox(definition, da_key, "t5_thermal_note_title", "Thermal Performance", "Thermal Notes Title")
        set_dc_textbox(definition, da_key, "t6_thermal_note_text", "▹ No thermal performance requirements defined yet.", "Thermal Notes Text")
        
        # Standards Compliance Notes
        set_dc_textbox(definition, da_key, "t7_compliance_note_title", "Standards Compliance", "Compliance Notes Title")
        set_dc_textbox(definition, da_key, "t8_compliance_note_text", "▹ No standards compliance requirements defined yet.", "Compliance Notes Text")
      end
    
      # --------------------------------------------------------------------------
      # Utility: get_description from ClassifierDefinitions
      # --------------------------------------------------------------------------
      def self.get_description(level, code)
        defs = ClassifierDefinitions.data["naming_definitions"][level]["options"] rescue {}
        defs[code] || ""
      end
    
      # --------------------------------------------------------------------------
      # Utility: merges the base code from level_05 with user input
      # --------------------------------------------------------------------------
      def self.merge_5th_code_with_user_digits(code_05, user_digits)
        return "" if code_05.to_s.strip.empty?
        trimmed = code_05.sub(/_\z/, "").sub(/\d+\z/, "").gsub(/\s+/, "")
        "#{trimmed}#{user_digits}"
      end
    
      # --------------------------------------------------------------------------
      # Utility: checks if the code requires cardinal elevation from definitions
      # --------------------------------------------------------------------------
      def self.requires_cardinal_elevation?(code_04)
        code_sanitised = sanitize_code(code_04)
        elevation_codes = ClassifierDefinitions.data["naming_definitions"]["elevation_required"]["element_codes"] rescue []
        elevation_codes.include?(code_sanitised)
      end
    
      # --------------------------------------------------------------------------
      # Utility: remove trailing underscore
      # --------------------------------------------------------------------------
      def self.sanitize_code(code)
        code.to_s.sub(/_\z/, "")
      end
    
      # --------------------------------------------------------------------------
      # Utility: set_dc_textbox - convenience for TEXTBOX attributes
      # --------------------------------------------------------------------------
      def self.set_dc_textbox(defn, dict_key, attr_name, value, label)
        defn.set_attribute(dict_key, attr_name, value)
        defn.set_attribute(dict_key, "_#{attr_name}_label",  label)
        defn.set_attribute(dict_key, "_#{attr_name}_access", "TEXTBOX")
        defn.set_attribute(dict_key, "_#{attr_name}_units",  "STRING")
      end
    
      # --------------------------------------------------------------------------
      # Utility: fetch the Z-height in millimetres from the origin
      # --------------------------------------------------------------------------
      def self.fetch_height_from_origin(instance)
        return 0.0 unless instance.is_a?(Sketchup::ComponentInstance)
        z_position = instance.transformation.origin.z
        z_position * 25.4  # convert inches to mm
      end
    
    end
    
    # endregion


    # region [AUTOSTART] | Load Plugin
    # --------------------------------------------------------------------------------
    unless file_loaded?(__FILE__)
      UI.menu("Plugins").add_item("NA |  Entity Classifier") {
        EntityClassifierApp.new.run
      }
      file_loaded(__FILE__)
    end
    # endregion

  end
end


