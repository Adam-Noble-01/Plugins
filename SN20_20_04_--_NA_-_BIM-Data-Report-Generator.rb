# ---------------------------------------------------------------------------------------------------------------------
# NA | Noble Architecture BIM Tools | BIM Data Report Generator
# ---------------------------------------------------------------------------------------------------------------------
# region [col01] | 01 - Project Details & Version History
# ---------------------------------------------------------------------------------------------------------------------
#
# PLUGIN NAME   | BIM Data Report Generator
# DESCRIPTION   | A SketchUp Plugin For Generating BIM Data Reports
# AUTHOR        | Studio Noodlfjørd
# CREATED       | 29-Mar-2025
#
# ROOT DIRECTORY
#   C:\Users\Administrator\AppData\Roaming\SketchUp\SketchUp 2025\SketchUp\Plugins
#
# THIS FILE
#   SN20_20_04_--_NA_-_BIM-Data-Report-Generator.rb
#
# RUN COMMAND 
# - Execute by running the command in the Ruby Console
#   `NobleArchitectureToolbox::BIMDataReporter.run`
#
# DEVELOPMENT LOG
# - 1.0.0 - 29-Apr-2025 | Initial version - Extracted from Toolbox Plugin
# - 1.0.1 - 29-Apr-2025 | Added dynamic field selection functionality
# - 1.0.2 - 29-Apr-2025 | Second Menu page for selection of reported fields
#
# ---------------------------------------------------------------------------------------------------------------------
# endregion

require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'set'

module NobleArchitectureToolbox
  module BIMDataReporter
    extend self

    # Default fields that will be included in the report
    DEFAULT_FIELDS = [
      # Basic Properties (checked in screenshot)
      { id: "entity_name", label: "Entity Name", key: nil, group: "Basic Properties", selected: true },
      { id: "b1_ent_floor", label: "Element Floor Level", key: ["b1_ent_floor"], group: "Basic Properties", selected: true },
      { id: "b2_ent_status", label: "Element Status", key: ["b2_ent_status"], group: "Basic Properties", selected: true },
      { id: "b3_ent_type", label: "Element Type", key: ["b3_ent_type"], group: "Basic Properties", selected: true },
      { id: "b4_ent_id_code", label: "Element ID Code", key: ["b4_ent_id_code"], group: "Basic Properties", selected: true },
      { id: "b5_ent_elevation", label: "Element Elevation", key: ["b5_ent_elevation"], group: "Basic Properties", selected: true },
      
      # Nesting Level - should come after Basic Properties but before other sections
      { id: "nesting_level", label: "Nesting Level", key: nil, group: "Other Attributes", selected: true },
      
      # Physical Properties (checked in screenshot)
      { id: "c1_element_material", label: "Element Material", key: ["c1_element_material"], group: "Physical Properties", selected: true },
      { id: "c2_element_finish", label: "Element Finish", key: ["c2_element_finish"], group: "Physical Properties", selected: true },
      { id: "c3_element_product", label: "Element Product", key: ["c3_element_product"], group: "Physical Properties", selected: true },
      
      # Dimensions (checked in screenshot)
      { id: "d1_length", label: "Length (mm)", key: ["d1_length"], group: "Dimensions", selected: true },
      { id: "d2_width", label: "Width (mm)", key: ["d2_width"], group: "Dimensions", selected: true },
      { id: "d3_height", label: "Height (mm)", key: ["d3_height"], group: "Dimensions", selected: true }
    ]

    # Path to the configuration file
    CONFIG_FILE_PATH = File.join(File.dirname(__FILE__), "na_plugin-dependencies", "bim_report_config.json")

    def discover_component_fields(entity)
      fields = DEFAULT_FIELDS.dup
      return fields unless entity

      # Get attribute dictionaries from both instance and definition
      dicts = []
      dicts << entity.attribute_dictionaries if entity.respond_to?(:attribute_dictionaries)
      if entity.is_a?(Sketchup::ComponentInstance)
        dicts << entity.definition.attribute_dictionaries if entity.definition
      end

      # Predefined attributes to look for (based on the BIM Classifier tool)
      predefined_fields = [
        # A Series - Classification (unchecked in screenshot)
        { id: "a1_level_01", label: "Entity Model Class", key: ["a1_level_01"], group: "Classification", selected: false },
        { id: "a2_level_02", label: "Entity Floor Level", key: ["a2_level_02"], group: "Classification", selected: false },
        { id: "a3_level_03", label: "Entity Status", key: ["a3_level_03"], group: "Classification", selected: false },
        { id: "a4_level_04", label: "Entity Type", key: ["a4_level_04"], group: "Classification", selected: false },
        { id: "a5_level_05", label: "Component Tag ID Code", key: ["a5_level_05"], group: "Classification", selected: false },
        { id: "a6_descriptive_tag", label: "Descriptive Tag", key: ["a6_descriptive_tag"], group: "Classification", selected: false },
        
        # B Series - Extra entries unchecked
        { id: "b6_descriptive_tag", label: "Descriptive Tag", key: ["b6_descriptive_tag"], group: "Basic Properties", selected: false },
        
        # C Series - Extra entries unchecked
        { id: "c4_element_info_01", label: "Custom Info 01", key: ["c4_element_info_01"], group: "Physical Properties", selected: false },
        
        # D Series - Extra entries unchecked
        { id: "d8_height_from_datum", label: "Height From Datum (mm)", key: ["d8_height_from_datum"], group: "Dimensions", selected: false },
        
        # E Series - Position (unchecked in screenshot)
        { id: "e1_global_position_x", label: "Global X Position", key: ["e1_global_position_x"], group: "Position Information", selected: false },
        { id: "e2_global_position_y", label: "Global Y Position", key: ["e2_global_position_y"], group: "Position Information", selected: false },
        { id: "e3_global_position_z", label: "Global Z Position", key: ["e3_global_position_z"], group: "Position Information", selected: false },
        { id: "e4_local_position_x", label: "Local X Position", key: ["e4_local_position_x"], group: "Position Information", selected: false },
        { id: "e5_local_position_y", label: "Local Y Position", key: ["e5_local_position_y"], group: "Position Information", selected: false },
        { id: "e6_local_position_z", label: "Local Z Position", key: ["e6_local_position_z"], group: "Position Information", selected: false },
        { id: "e8_height_from_datum", label: "Height From Main Site Datum", key: ["e8_height_from_datum"], group: "Position Information", selected: false },
        { id: "e9_height_from_secondary_datum", label: "Height From Secondary Datum Point", key: ["e9_height_from_secondary_datum"], group: "Position Information", selected: false },
        
        # F Series - Model Information (unchecked in screenshot)
        { id: "f1_model_notes", label: "General Notes", key: ["f1_model_notes"], group: "Model Information", selected: false },
        { id: "f2_model_author", label: "Version Author", key: ["f2_model_author"], group: "Model Information", selected: false },
        { id: "f3_model_created", label: "Creation Date", key: ["f3_model_created"], group: "Model Information", selected: false },
        { id: "f4_model_modified", label: "Last Modified", key: ["f4_model_modified"], group: "Model Information", selected: false },
        
        # T Series - Technical Notes (unchecked in screenshot)
        { id: "t1_note_title", label: "Specification Title", key: ["t1_note_title"], group: "Technical Notes", selected: false },
        { id: "t2_note_text", label: "Specification Text", key: ["t2_note_text"], group: "Technical Notes", selected: false },
        { id: "t3_critical_note_title", label: "Critical Notes Title", key: ["t3_critical_note_title"], group: "Technical Notes", selected: false },
        { id: "t4_critical_note_text", label: "Critical Notes Text", key: ["t4_critical_note_text"], group: "Technical Notes", selected: false },
        { id: "t5_thermal_note_title", label: "Thermal Notes Title", key: ["t5_thermal_note_title"], group: "Technical Notes", selected: false },
        { id: "t6_thermal_note_text", label: "Thermal Notes Text", key: ["t6_thermal_note_text"], group: "Technical Notes", selected: false },
        { id: "t7_compliance_note_title", label: "Compliance Notes Title", key: ["t7_compliance_note_title"], group: "Technical Notes", selected: false },
        { id: "t8_compliance_note_text", label: "Compliance Notes Text", key: ["t8_compliance_note_text"], group: "Technical Notes", selected: false }
      ]
      
      # Add each predefined field if it exists in any of the dictionaries
      dicts.compact.each do |dictionaries|
        dictionaries.each do |dict|
          next unless dict.name == "dynamic_attributes"
          
          # First, check for predefined fields
          predefined_fields.each do |field_info|
            key = field_info[:id]
            # Skip if already added
            next if fields.any? { |f| f[:id] == key }
            
            # Check if the key exists in the dictionary
            if dict[key] != nil
              # Get custom label if available, otherwise use predefined
              label = dict["_#{key}_label"] || field_info[:label]
              
              # Add the field with the selected status from field_info
              fields << {
                id: key,
                label: label,
                key: [key],
                group: field_category(key),
                selected: field_info[:selected] || false # Default to false for additional fields
              }
            end
          end
          
          # Then add any additional fields that aren't in the predefined list
          dict.each_pair do |key, value|
            next if key.start_with?('_') # Skip metadata attributes
            next if key == 'dialogwidth' || key == 'dialogheight' # Skip dialog settings
            next if fields.any? { |f| f[:id] == key } # Skip if already added
            
            # Get the label from metadata if available
            label = dict["_#{key}_label"] || key.split('_').map(&:capitalize).join(' ')
            
            fields << {
              id: key,
              label: label,
              key: [key],
              group: field_category(key),
              selected: false # Additional discovered fields are not selected by default
            }
          end
        end
      end

      # Make sure entity_name is in Basic Properties group and not in any other group
      fields.each do |field|
        if field[:id] == "entity_name"
          field[:group] = "Basic Properties"
        end
      end

      fields
    end
    
    # Helper to determine field category based on prefix
    def field_category(key)
      # Special case for entity_name and nesting_level
      return "Basic Properties" if key.to_s == "entity_name"
      return "Other Attributes" if key.to_s == "nesting_level"
      
      # For other keys, determine by prefix
      prefix = key.to_s[0]
      case prefix
      when 'a' then 'Classification'
      when 'b' then 'Basic Properties'
      when 'c' then 'Physical Properties'
      when 'd' then 'Dimensions'
      when 'e' then 'Position Information'
      when 'f' then 'Model Information'
      when 't' then 'Technical Notes'
      else 'Other Attributes'
      end
    end

    def run(logo_path)
      @dialog = UI::HtmlDialog.new(
        dialog_title:    "Noble Architecture | BIM Data Report",
        preferences_key: "com.noble-architecture.dc-reporter",
        scrollable:      true,
        resizable:      true,
        width:          600,
        height:         480,
        style:          UI::HtmlDialog::STYLE_DIALOG
      )

      stylesheet = NobleArchitectureUnifiedStylesheet.shared_stylesheet
      @logo_path = logo_path  # store local path

      # Get the selected component if any
      model = Sketchup.active_model
      selection = model.selection
      @selected_entity = selection.first if selection.length == 1

      # Discover available fields from the selected component
      discovered_fields = discover_component_fields(@selected_entity)
      
      # Load saved field configuration
      saved_fields = load_selected_fields
      
      # Check if this is a first-time run (no saved configuration)
      first_run = !File.exist?(CONFIG_FILE_PATH)
      
      # Create a hash map of saved fields for quick lookup
      saved_fields_map = {}
      saved_fields.each do |field|
        saved_fields_map[field[:id]] = field
      end
      
      # Merge saved fields with discovered fields
      @selected_fields = discovered_fields.map do |field|
        if saved_fields_map.has_key?(field[:id])
          # Use the saved configuration
          saved_field = saved_fields_map[field[:id]]
          
          # Make sure key and group are properly set
          if saved_field[:key].nil? && !field[:key].nil?
            saved_field[:key] = field[:key]
          end
          
          if saved_field[:group].nil? && !field[:group].nil?
            saved_field[:group] = field[:group]
          end
          
          # Force entity_name to be in Basic Properties
          if saved_field[:id] == "entity_name"
            saved_field[:group] = "Basic Properties"
          end
          
          saved_field
        else
          # For first run or new fields, respect the default selected state from the field definition
          field
        end
      end
      
      # Ensure entity_name is always in Basic Properties
      @selected_fields.each do |field|
        if field[:id] == "entity_name"
          field[:group] = "Basic Properties"
        end
      end

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

      @dialog.add_action_callback("showFieldConfig") do
        @dialog.set_html(html_field_config(stylesheet))
      end

      @dialog.add_action_callback("saveFieldConfig") do |_ctx, selected_fields_json|
        begin
          selected_fields = JSON.parse(selected_fields_json)
          
          # Update the selected status for each field
          selected_fields.each do |field|
            next unless field['id'] # Skip if field id is missing
            
            existing = @selected_fields.find { |f| f[:id] == field['id'] }
            if existing
              existing[:selected] = field['selected']
            end
          end
          
          save_selected_fields(@selected_fields)
          @dialog.set_html(html_prompt_spid(stylesheet))
        rescue => e
          puts "Error saving field configuration: #{e.message}"
          puts e.backtrace.join("\n")
          UI.messagebox("Error saving field configuration: #{e.message}")
        end
      end

      @dialog.add_action_callback("resetFieldConfig") do
        # Reset to default fields with proper selected status
        default_field_ids = DEFAULT_FIELDS.map { |f| f[:id] }
        
        @selected_fields.each do |field|
          if default_field_ids.include?(field[:id])
            # Set selected status based on DEFAULT_FIELDS
            default_field = DEFAULT_FIELDS.find { |f| f[:id] == field[:id] }
            field[:selected] = default_field[:selected]
          else
            # Non-default fields should be unselected
            field[:selected] = false
          end
        end
        
        save_selected_fields(@selected_fields)
        @dialog.set_html(html_field_config(stylesheet))
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
        <button onclick="onShowFieldConfig()" class="NA_BIM_btnSecondary">Configure Report Fields</button>

        <script>
        function onGenerateReport() {
          const spidValue = document.getElementById('spid_input').value.trim();
          if (!spidValue) {
            alert("SPID code cannot be empty.");
            return;
          }
          sketchup.generateReport(spidValue);
        }

        function onShowFieldConfig() {
          sketchup.showFieldConfig();
        }
        </script>
      </body>
      </html>
      HTML
    end

    def html_field_config(stylesheet)
      # Ensure fields are properly formatted for JSON
      sanitized_fields = @selected_fields.map do |field|
        # Force entity_name to be in Basic Properties
        group = field[:id].to_s == "entity_name" ? "Basic Properties" : (field[:group] || "Other Attributes")
        
        # Create a clean hash with string keys for JSON
        {
          'id' => field[:id].to_s,
          'label' => field[:label].to_s, 
          'group' => group,
          'selected' => !!field[:selected],
          'key' => field[:key]
        }
      end
      
      # Convert Ruby array to JSON, ensuring it's properly serialized
      fields_json = JSON.generate(sanitized_fields)
      
      <<-HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>Noble Architecture | BIM Data Report Fields</title>
        <style>#{stylesheet}</style>
        <style>
          .field-config-container {
            padding           :    10px;
          }
          .field-list {
            max-height        :    95vh;
            overflow-y        :    auto; 
            margin            :    15px 0;
            border            :    1px solid #ddd;
            padding           :    10px;
            border-radius     :    4px;
          }
          .field-group {
            background        :    #f8f8f8;
            padding-top       :    10px;
            padding-bottom    :    10px;
            padding-left      :    05px;
            padding-right     :    05px;
            border-radius     :    4px;
          }
          .field-group-title {
            font-weight       :    600;
            margin-bottom     :    10px;
            color             :    #555;
            border-bottom     :    1px solid #ddd;
            padding-bottom    :    5px;
          }
          .field-item {
            margin-bottom     :    8px;
            padding           :    5px;
            border-bottom     :    1px solid #eee;
            background        :    white;
          }
          .field-item:last-child {
            border-bottom     :    none;
          }
          .field-checkbox {
            margin-right      :    10px;
          }
          .field-label {
            font-weight       :    500;
          }
          .field-actions {
            margin-top        :    15px;
            display           :    flex;
            justify-content   :    space-between;
          }
          .select-all-container {
            margin-bottom     :    10px;
            padding           :    5px;
            background-color  :   #f5f5f5;
            border-radius     :    4px;
          }
        </style>
      </head>
      <body class="NA_BIM_Report_body">
        #{NobleArchitectureUnifiedStylesheet.generate_header("BIM Data Report Fields", @logo_path)}
        
        <div class="field-config-container">
          <h3>Select Fields to Include in Report</h3>
          
          <div class="select-all-container">
            <label>
              <input type="checkbox" id="select-all"> Select All Fields
            </label>
          </div>
          
          <div class="field-list" id="field-list">
            <!-- Fields will be populated here by JavaScript -->
          </div>
          
          <div class="field-actions">
            <button onclick="onResetFields()" class="NA_BIM_btnSecondary">Reset to Default</button>
            <button onclick="onSaveFields()" class="NA_BIM_btnPrimary">Save & Return</button>
          </div>
        </div>

        <script>
        // Initialize with the fields from Ruby
        const fields = #{fields_json};
        
        // First, ensure entity_name is in Basic Properties
        fields.forEach(field => {
          if (field.id === 'entity_name') {
            field.group = 'Basic Properties';
          }
        });
        
        // Group fields by their group property
        function groupFields(fields) {
          const groups = {};
          fields.forEach(field => {
            const group = field.group || 'Other Attributes';
            if (!groups[group]) groups[group] = [];
            groups[group].push(field);
          });
          return groups;
        }
        
        // Populate the field list
        function populateFieldList() {
          const fieldList = document.getElementById('field-list');
          fieldList.innerHTML = '';
          
          const groups = groupFields(fields);
          
          // Define group order for display
          const groupOrder = [
            'Basic Properties',
            'Physical Properties',
            'Dimensions',
            'Classification',
            'Position Information',
            'Model Information',
            'Technical Notes',
            'Other Attributes'
          ];
          
          // Sort groups by predefined order
          const sortedGroups = groupOrder
            .filter(groupName => groups[groupName] && groups[groupName].length > 0)
            .concat(Object.keys(groups).filter(g => !groupOrder.includes(g)));
             
          sortedGroups.forEach(groupName => {
            if (!groups[groupName]) return;
            
            const groupDiv = document.createElement('div');
            groupDiv.className = 'field-group';
            
            const groupTitle = document.createElement('div');
            groupTitle.className = 'field-group-title';
            groupTitle.textContent = groupName;
            groupDiv.appendChild(groupTitle);
            
            // Special sorting for Basic Properties to ensure "Entity Name" is at the top
            let sortedFields = [];
            if (groupName === 'Basic Properties') {
              // First add Entity Name if it exists
              const entityNameField = groups[groupName].find(f => f.id === 'entity_name');
              if (entityNameField) {
                sortedFields.push(entityNameField);
              }
              
              // Then add all other fields sorted by ID
              sortedFields = sortedFields.concat(
                groups[groupName]
                  .filter(f => f.id !== 'entity_name')
                  .sort((a, b) => a.id.localeCompare(b.id))
              );
            } else {
              // For other groups, just sort by ID
              sortedFields = groups[groupName].sort((a, b) => a.id.localeCompare(b.id));
            }
            
            // Create field items
            sortedFields.forEach(field => {
              const fieldItem = document.createElement('div');
              fieldItem.className = 'field-item';
              
              const checkbox = document.createElement('input');
              checkbox.type = 'checkbox';
              checkbox.className = 'field-checkbox';
              checkbox.id = `field-${field.id}`;
              checkbox.checked = field.selected === true;
              checkbox.dataset.fieldId = field.id;
              
              const label = document.createElement('label');
              label.className = 'field-label';
              label.htmlFor = `field-${field.id}`;
              label.textContent = field.label;
              
              fieldItem.appendChild(checkbox);
              fieldItem.appendChild(label);
              groupDiv.appendChild(fieldItem);
            });
            
            fieldList.appendChild(groupDiv);
          });
          
          // Update select all checkbox
          updateSelectAllCheckbox();
        }
        
        // Update the select all checkbox based on individual checkboxes
        function updateSelectAllCheckbox() {
          const checkboxes = document.querySelectorAll('.field-checkbox');
          const selectAllCheckbox = document.getElementById('select-all');
          
          if (checkboxes.length === 0) {
            selectAllCheckbox.checked = false;
            return;
          }
          
          const allChecked = Array.from(checkboxes).every(cb => cb.checked);
          selectAllCheckbox.checked = allChecked;
        }
        
        // Toggle all checkboxes
        function toggleAllCheckboxes() {
          const selectAllCheckbox = document.getElementById('select-all');
          const checkboxes = document.querySelectorAll('.field-checkbox');
          
          checkboxes.forEach(checkbox => {
            checkbox.checked = selectAllCheckbox.checked;
          });
        }
        
        // Save the selected fields and return to the main page
        function onSaveFields() {
          // Get the current state of all checkboxes
          const checkboxes = document.querySelectorAll('.field-checkbox');
          const updatedFields = [];
          
          checkboxes.forEach(checkbox => {
            updatedFields.push({
              id: checkbox.dataset.fieldId,
              selected: checkbox.checked
            });
          });
          
          sketchup.saveFieldConfig(JSON.stringify(updatedFields));
        }
        
        // Reset fields to default
        function onResetFields() {
          sketchup.resetFieldConfig();
        }
        
        // Add event listeners
        document.getElementById('select-all').addEventListener('change', toggleAllCheckboxes);
        
        // Initialize the field list
        populateFieldList();
        
        // Add event listeners to all checkboxes for the select all toggle behavior
        document.addEventListener('change', function(e) {
          if (e.target.classList.contains('field-checkbox')) {
            updateSelectAllCheckbox();
          }
        });
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
      # Get the selected fields
      selected_fields = @selected_fields.select { |field| field[:selected] != false }
      
      # Create the table headers based on selected fields
      table_headers = selected_fields.map { |field| field[:label] || field["label"] || field[:id] || field["id"] }
      
      # Create the table header HTML
      table_header_html = table_headers.map.with_index do |header, index|
        "<th onclick=\"onSortColumn(#{index})\">#{header}</th>"
      end.join("\n              ")
      
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
              #{table_header_html}
            </tr>
          </thead>
          <tbody id="tableBody"></tbody>
        </table>

        <div class="NA_BIM_btnBar NA_margin_top">
          <button onclick="onGoBack()">Go Back</button>
          <button onclick="onExportCSV()">Export CSV</button>
        </div>

        <div class="NA_BIM_footer_text">
          Noble Architecture – BIM Report Generator v0.2.0
        </div>

        <script>
        let rowData = #{row_data_js};
        let currentSortCol = 0;
        let currentSortDir = -1;

        window.onload = function() {
          sortAndRender();
        }

        function onSortColumn(colIndex) {
          if (colIndex === currentSortCol) {
            currentSortDir *= -1;
          } else {
            currentSortCol = colIndex;
            currentSortDir = -1;
          }
          sortAndRender();
        }

        function onGoBack() {
          sketchup.goBack();
        }

        function onExportCSV() {
          sketchup.exportCSV();
        }

        function sortAndRender() {
          rowData.sort((a, b) => {
            let x = (a[currentSortCol] && a[currentSortCol].toLowerCase) ? a[currentSortCol].toLowerCase() : (a[currentSortCol] || '');
            let y = (b[currentSortCol] && b[currentSortCol].toLowerCase) ? b[currentSortCol].toLowerCase() : (b[currentSortCol] || '');
            if (x < y) return -1 * currentSortDir;
            if (x > y) return 1 * currentSortDir;
            return 0;
          });
          renderTable();
        }

        function renderTable() {
          const tbody = document.getElementById('tableBody');
          tbody.innerHTML = '';
          rowData.forEach(row => {
            const tr = document.createElement('tr');
            row.forEach(cell => {
              const td = document.createElement('td');
              td.textContent = cell || '';
              tr.appendChild(td);
            });
            tbody.appendChild(tr);
          });
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
      return true if has_spid_in_attr?(ent, needle)
      if ent.is_a?(Sketchup::ComponentInstance)
        return true if ent.definition.name.to_s.downcase.include?(needle)
      end
      false
    end

    def has_spid_in_attr?(ent, needle)
      return false unless ent.attribute_dictionaries
      ent.attribute_dictionaries.each do |dict|
        dict.each_pair do |key, value|
          return true if value.to_s.downcase.include?(needle)
        end
      end
      false
    end

    def build_row_data(filtered)
      rows = []
      filtered.each do |(ent, level)|
        # Get all the field values based on the selected fields
        field_values = @selected_fields.select { |field| field[:selected] != false }.map do |field|
          case field[:id]
          when "entity_name"
            best_entity_name(ent)
          when "nesting_level"
            level.to_s
          else
            # For any field with a key, try to get the attribute value
            if field[:key] && field[:key].is_a?(Array) && !field[:key].empty?
              multi_dc_attr(ent, *field[:key])
            else
              # For fields without keys, try using the ID as the key
              multi_dc_attr(ent, field[:id])
            end
          end
        end
        
        rows << field_values
      end
      rows
    end

    def best_entity_name(ent)
      return ent.name.to_s.strip unless ent.name.to_s.strip.empty?

      if ent.is_a?(Sketchup::ComponentInstance)
        def_name = ent.definition.name.to_s.strip
        return def_name unless def_name.empty?
      end

      "Untitled Entity"
    end

    def multi_dc_attr(ent, *keys)
      return "—" if keys.empty? || keys.all?(&:nil?)
      
      # Get attribute dictionaries from both instance and definition (if it's a component)
      entity_dicts = ent.attribute_dictionaries
      definition_dicts = nil
      if ent.is_a?(Sketchup::ComponentInstance) && ent.definition
        definition_dicts = ent.definition.attribute_dictionaries
      end
      
      # Try each key in order
      keys.each do |key|
        next if key.nil? || key.to_s.strip.empty?
        
        # Try entity attributes first
        val = get_dc_val(entity_dicts, key)
        return val unless val == "—"
        
        # Then try definition attributes
        val = get_dc_val(definition_dicts, key)
        return val unless val == "—"
      end
      
      # Nothing found for any key
      "—"
    end

    def get_dc_val(dicts, key)
      return "—" unless dicts
      
      # First try dynamic_attributes dictionary
      dict = dicts["dynamic_attributes"]
      if dict && dict[key] && !dict[key].to_s.strip.empty?
        return dict[key].to_s
      end
      
      # Then try a direct dictionary with the key name
      dict = dicts[key]
      if dict
        # If it's a dictionary itself, just return that it exists
        return key.to_s
      end
      
      # Try other dictionaries
      dicts.each do |d|
        next if d.name == "dynamic_attributes" # Already checked
        if d[key] && !d[key].to_s.strip.empty?
          return d[key].to_s
        end
      end
      
      # Nothing found
      "—"
    end

    def build_csv(rows)
      # Get the selected fields
      selected_fields = @selected_fields.select { |field| field[:selected] != false }
      headers = selected_fields.map { |field| field[:label] || field["label"] || field[:id] || field["id"] }

      csv = headers.map { |h| csv_escape(h) }.join(",") + "\n"
      rows.each do |row|
        csv << row.map { |cell| csv_escape(cell) }.join(",") + "\n"
      end
      csv
    end

    def csv_escape(str)
      s = str.to_s
      if s.include?(",") || s.include?('"') || s.include?("\n")
        '"' + s.gsub('"', '""') + '"'
      else
        s
      end
    end

    # region [Configuration]
    def load_selected_fields
      # Create the directory if it doesn't exist
      config_dir = File.dirname(CONFIG_FILE_PATH)
      FileUtils.mkdir_p(config_dir) unless File.exist?(config_dir)
      
      # Try to load the configuration file
      if File.exist?(CONFIG_FILE_PATH)
        begin
          config_data = JSON.parse(File.read(CONFIG_FILE_PATH))
          
          # Ensure each field has the proper attributes and convert string keys to symbols
          symbolized_fields = config_data.map do |field|
            next unless field.is_a?(Hash) && field["id"] # Skip invalid entries
            
            # Convert string keys to symbols
            symbolized_field = {}
            field.each do |k, v|
              symbolized_field[k.to_sym] = v
            end
            
            # Ensure each field has a key property (array or nil)
            if !symbolized_field.has_key?(:key) || symbolized_field[:key].nil?
              symbolized_field[:key] = nil
            elsif !symbolized_field[:key].is_a?(Array)
              symbolized_field[:key] = [symbolized_field[:key].to_s]
            end
            
            # Ensure each field has a group property
            if !symbolized_field.has_key?(:group) || symbolized_field[:group].nil?
              symbolized_field[:group] = field_category(symbolized_field[:id].to_s)
            end
            
            # Ensure each field has a selected property
            if !symbolized_field.has_key?(:selected)
              symbolized_field[:selected] = false
            end
            
            symbolized_field
          end
          
          return symbolized_fields.compact # Remove any nil entries
        rescue => e
          puts "Error loading field configuration: #{e.message}"
          puts e.backtrace.join("\n")
          return DEFAULT_FIELDS
        end
      else
        return DEFAULT_FIELDS
      end
    end

    def save_selected_fields(fields)
      return false unless fields.is_a?(Array)
      
      # Create the directory if it doesn't exist
      config_dir = File.dirname(CONFIG_FILE_PATH)
      FileUtils.mkdir_p(config_dir) unless File.exist?(config_dir)
      
      # Ensure each field has proper attributes before saving
      fields_to_save = fields.compact.map do |field|
        next unless field.is_a?(Hash) && (field[:id] || field["id"]) # Skip invalid entries
        
        # Start with a clean hash
        cleaned_field = {}
        
        # Get id from either symbol or string key
        id = field[:id] || field["id"]
        cleaned_field[:id] = id
        
        # Get label from either symbol or string key
        label = field[:label] || field["label"] || id.to_s.split('_').map(&:capitalize).join(' ')
        cleaned_field[:label] = label
        
        # Handle key (either symbol or string key)
        key = field[:key] || field["key"]
        if key.nil?
          cleaned_field[:key] = nil
        elsif key.is_a?(Array)
          cleaned_field[:key] = key.compact # Remove nil entries from array
        else
          cleaned_field[:key] = [key.to_s]
        end
        
        # Get group from either symbol or string key
        group = field[:group] || field["group"] || field_category(id.to_s)
        cleaned_field[:group] = group
        
        # Get selected status from either symbol or string key
        selected = field.has_key?(:selected) ? field[:selected] : 
                  field.has_key?("selected") ? field["selected"] : false
        cleaned_field[:selected] = selected
        
        cleaned_field
      end
      
      # Filter out nil entries
      fields_to_save = fields_to_save.compact
      
      # Save the configuration file
      begin
        File.write(CONFIG_FILE_PATH, JSON.pretty_generate(fields_to_save))
        return true
      rescue => e
        puts "Error saving field configuration: #{e.message}"
        puts e.backtrace.join("\n")
        return false
      end
    end
    # endregion
  end

  # Register plugin menu item
  unless file_loaded?(__FILE__)
    UI.menu("Plugins").add_item("NA | BIM Data Report Generator") {
      BIMDataReporter.run(NobleArchitectureToolbox::LOGO_PATH)
    }
    file_loaded(__FILE__)
  end
end 
