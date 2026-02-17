# -----------------------------------------------------------------------------
# REGION | Material Swap in Selection Tool
# -----------------------------------------------------------------------------
# A SketchUp Ruby plugin to selectively swap materials from the current
# selection with a different material from the model.
# Works recursively through groups, components, and loose geometry.
# Handles both front and back materials on faces, and materials on containers.
# Compatible with: SketchUp 2025+
# -----------------------------------------------------------------------------

module Na__MaterialSwap__InSelection

    # -----------------------------------------------------------------------------
    # REGION | Constants
    # -----------------------------------------------------------------------------

    PLUGIN_NAME        = "Material Swap in Selection"
    PLUGIN_VERSION     = "1.0.0"

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Core Logic - Material Collection
    # -----------------------------------------------------------------------------

    # FUNCTION | Collect all unique materials from selection (recursive)
    # ------------------------------------------------------------
    # Recursively traverses the selection and all nested entities to build
    # a hash of unique materials found, along with counts of material applications.
    #
    # @param entities [Sketchup::Entities] The entities to scan
    # @param materials_hash [Hash] Accumulator hash {material_name => {material: Material, count: Integer}}
    # @return [Hash] The accumulated materials hash
    # ------------------------------------------------------------
    def self.collect_materials_recursive(entities, materials_hash = {})
        entities.each do |entity|
            # Check if entity has a material property (Groups, Components, Faces)
            if entity.respond_to?(:material) && entity.material
                material      = entity.material                               # <-- Get material object
                material_name = material.name                                 # <-- Get material name

                if materials_hash[material_name]
                    materials_hash[material_name][:count] += 1                # <-- Increment count
                else
                    materials_hash[material_name] = { material: material, count: 1 } # <-- Initialize entry
                end
            end

            # Check back material on faces specifically
            if entity.is_a?(Sketchup::Face) && entity.back_material
                back_material      = entity.back_material                     # <-- Get back material object
                back_material_name = back_material.name                       # <-- Get back material name

                if materials_hash[back_material_name]
                    materials_hash[back_material_name][:count] += 1           # <-- Increment count
                else
                    materials_hash[back_material_name] = { material: back_material, count: 1 } # <-- Initialize entry
                end
            end

            # Recursively process nested entities
            if entity.is_a?(Sketchup::Group)
                collect_materials_recursive(entity.definition.entities, materials_hash)   # <-- Recurse into group
            elsif entity.is_a?(Sketchup::ComponentInstance)
                collect_materials_recursive(entity.definition.entities, materials_hash) # <-- Recurse into component
            end
        end

        materials_hash
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Core Logic - Material Swapping Operation
    # -----------------------------------------------------------------------------

    # FUNCTION | Swap materials with specified replacement (recursive)
    # ------------------------------------------------------------
    # Recursively traverses entities and replaces matching materials with the new material.
    # Handles front materials, back materials on faces, and materials on containers.
    #
    # @param entities [Sketchup::Entities] The entities to process
    # @param old_materials [Array<Sketchup::Material>] Array of materials to replace
    # @param new_material [Sketchup::Material] The replacement material
    # @return [Integer] Count of material applications modified
    # ------------------------------------------------------------
    def self.swap_materials_recursive(entities, old_materials, new_material)
        count = 0                                                             # <-- Initialize counter

        entities.each do |entity|
            # Swap front/primary material on all entities that support it
            if entity.respond_to?(:material) && entity.material
                if old_materials.include?(entity.material)
                    entity.material = new_material                            # <-- Set to new material
                    count += 1                                                # <-- Increment counter
                end
            end

            # Swap back material on faces specifically
            if entity.is_a?(Sketchup::Face) && entity.back_material
                if old_materials.include?(entity.back_material)
                    entity.back_material = new_material                       # <-- Set back material
                    count += 1                                                # <-- Increment counter
                end
            end

            # Recursively process nested entities
            if entity.is_a?(Sketchup::Group)
                count += swap_materials_recursive(entity.definition.entities, old_materials, new_material) # <-- Recurse into group
            elsif entity.is_a?(Sketchup::ComponentInstance)
                count += swap_materials_recursive(entity.definition.entities, old_materials, new_material) # <-- Recurse into component
            end
        end

        count
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | UI - First Dialog (Select Materials to Swap)
    # -----------------------------------------------------------------------------

    # FUNCTION | Generate HTML for the first dialog (material selection)
    # ------------------------------------------------------------
    # Creates the HTML content for the material selection dialog.
    #
    # @param materials_data [Hash] Hash of material data {name => {material:, count:}}
    # @return [String] HTML content
    # ------------------------------------------------------------
    def self.generate_first_dialog_html(materials_data)
        materials_json = materials_data.map { |name, data| 
            { name: name, count: data[:count] }
        }.to_json

        html = <<-HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family      :  Arial, sans-serif;
            margin           :  0;
            padding          :  20px;
            background-color :  #f5f5f5;
        }
        h2 {
            margin-top :  0;
            color      :  #333;
            font-size  :  18px;
        }
        .instructions {
            background-color  :  #e3f2fd;
            padding           :  10px;
            border-radius     :  4px;
            margin-bottom     :  15px;
            font-size         :  13px;
            color             :  #1976d2;
        }
        .materials-container {
            background-color :  white;
            border           :  1px solid #ddd;
            border-radius    :  4px;
            padding          :  10px;
            max-height       :  300px;
            overflow-y       :  auto;
            margin-bottom    :  15px;
        }
        .material-item {
            padding   :  8px;
            margin    :  4px 0;
            border-radius     :  3px;
            transition        :  background-color 0.2s;
        }
        .material-item:hover {
            background-color :  #f0f0f0;
        }
        .material-item input[type="checkbox"] {
            margin-right :  8px;
            cursor       :  pointer;
        }
        .material-item label {
            cursor       :  pointer;
            display      :  inline-block;
            width        :  calc(100% - 25px);
        }
        .material-name {
            font-weight :  bold;
            color       :  #333;
        }
        .material-count {
            color      :  #666;
            font-size  :  12px;
            margin-left :  8px;
        }
        .button-container {
            display          :  flex;
            gap              :  10px;
            justify-content  :  flex-end;
        }
        button {
            padding   :  8px 16px;
            border    :  none;
            border-radius     :  4px;
            cursor    :  pointer;
            font-size :  14px;
            transition        :  background-color 0.2s;
        }
        #nextBtn {
            background-color :  #4CAF50;
            color            :  white;
        }
        #nextBtn:hover {
            background-color :  #45a049;
        }
        #nextBtn:disabled {
            background-color :  #cccccc;
            cursor           :  not-allowed;
        }
        #cancelBtn {
            background-color :  #f44336;
            color            :  white;
        }
        #cancelBtn:hover {
            background-color :  #da190b;
        }
        #selectAllBtn {
            background-color :  #2196F3;
            color            :  white;
            margin-right     :  auto;
        }
        #selectAllBtn:hover {
            background-color :  #0b7dda;
        }
        .no-materials {
            text-align :  center;
            padding    :  20px;
            color      :  #666;
        }
    </style>
</head>
<body>
    <h2>Material Swap - Step 1: Select Materials to Replace</h2>
    
    <div class="instructions">
        Select the material(s) you want to replace from the current selection. 
        You can select multiple materials to swap them all to a single new material.
    </div>

    <div class="materials-container" id="materialsContainer"></div>

    <div class="button-container">
        <button id="selectAllBtn">Select All</button>
        <button id="nextBtn" disabled>Next: Choose Replacement</button>
        <button id="cancelBtn">Cancel</button>
    </div>

    <script>
        const materialsData = #{materials_json};
        let selectAllState = false;

        // Initialize the materials list
        function initializeMaterials() {
            const container = document.getElementById('materialsContainer');
            
            if (materialsData.length === 0) {
                container.innerHTML = '<div class="no-materials">No materials found in selection.</div>';
                return;
            }

            materialsData.forEach((material, index) => {
                const materialItem = document.createElement('div');
                materialItem.className = 'material-item';
                
                const checkbox = document.createElement('input');
                checkbox.type = 'checkbox';
                checkbox.id = 'material_' + index;
                checkbox.value = material.name;
                checkbox.addEventListener('change', updateNextButton);
                
                const label = document.createElement('label');
                label.htmlFor = 'material_' + index;
                label.innerHTML = '<span class="material-name">' + escapeHtml(material.name) + '</span>' +
                                '<span class="material-count">(' + material.count + ' applications)</span>';
                
                materialItem.appendChild(checkbox);
                materialItem.appendChild(label);
                container.appendChild(materialItem);
            });
        }

        // Update the Next button state
        function updateNextButton() {
            const checkboxes = document.querySelectorAll('input[type="checkbox"]');
            const anyChecked = Array.from(checkboxes).some(cb => cb.checked);
            document.getElementById('nextBtn').disabled = !anyChecked;
        }

        // Select/Deselect all materials
        document.getElementById('selectAllBtn').addEventListener('click', () => {
            selectAllState = !selectAllState;
            const checkboxes = document.querySelectorAll('input[type="checkbox"]');
            checkboxes.forEach(cb => cb.checked = selectAllState);
            updateNextButton();
            document.getElementById('selectAllBtn').textContent = selectAllState ? 'Deselect All' : 'Select All';
        });

        // Next button click
        document.getElementById('nextBtn').addEventListener('click', () => {
            const checkboxes = document.querySelectorAll('input[type="checkbox"]:checked');
            const selectedMaterials = Array.from(checkboxes).map(cb => cb.value);
            
            if (selectedMaterials.length > 0) {
                window.location = 'skp:materials_selected@' + JSON.stringify(selectedMaterials);
            }
        });

        // Cancel button click
        document.getElementById('cancelBtn').addEventListener('click', () => {
            window.location = 'skp:cancel@';
        });

        // Escape HTML to prevent injection
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        // Initialize on load
        initializeMaterials();
    </script>
</body>
</html>
        HTML

        html
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | UI - Second Dialog (Choose Replacement Material)
    # -----------------------------------------------------------------------------

    # FUNCTION | Generate HTML for the second dialog (replacement selection)
    # ------------------------------------------------------------
    # Creates the HTML content for the replacement material dialog with search.
    #
    # @param all_materials [Array<Sketchup::Material>] All materials in the model
    # @param selected_count [Integer] Number of materials being replaced
    # @return [String] HTML content
    # ------------------------------------------------------------
    def self.generate_second_dialog_html(all_materials, selected_count)
        materials_json = all_materials.sort_by(&:name).map { |mat| 
            { name: mat.name }
        }.to_json

        html = <<-HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family      :  Arial, sans-serif;
            margin           :  0;
            padding          :  20px;
            background-color :  #f5f5f5;
        }
        h2 {
            margin-top :  0;
            color      :  #333;
            font-size  :  18px;
        }
        .instructions {
            background-color  :  #e3f2fd;
            padding           :  10px;
            border-radius     :  4px;
            margin-bottom     :  15px;
            font-size         :  13px;
            color             :  #1976d2;
        }
        .search-container {
            margin-bottom :  10px;
        }
        .search-container input {
            width        :  calc(100% - 20px);
            padding      :  8px;
            border       :  1px solid #ddd;
            border-radius :  4px;
            font-size    :  14px;
        }
        .materials-container {
            background-color :  white;
            border           :  1px solid #ddd;
            border-radius    :  4px;
            padding          :  10px;
            max-height       :  350px;
            overflow-y       :  auto;
            margin-bottom    :  15px;
        }
        .material-item {
            padding   :  8px;
            margin    :  4px 0;
            border-radius     :  3px;
            transition        :  background-color 0.2s;
        }
        .material-item:hover {
            background-color :  #f0f0f0;
        }
        .material-item input[type="radio"] {
            margin-right :  8px;
            cursor       :  pointer;
        }
        .material-item label {
            cursor  :  pointer;
            display :  inline-block;
            width   :  calc(100% - 25px);
        }
        .material-name {
            font-weight :  bold;
            color       :  #333;
        }
        .button-container {
            display          :  flex;
            gap              :  10px;
            justify-content  :  flex-end;
        }
        button {
            padding   :  8px 16px;
            border    :  none;
            border-radius     :  4px;
            cursor    :  pointer;
            font-size :  14px;
            transition        :  background-color 0.2s;
        }
        #swapBtn {
            background-color :  #4CAF50;
            color            :  white;
        }
        #swapBtn:hover {
            background-color :  #45a049;
        }
        #swapBtn:disabled {
            background-color :  #cccccc;
            cursor           :  not-allowed;
        }
        #backBtn {
            background-color :  #FF9800;
            color            :  white;
        }
        #backBtn:hover {
            background-color :  #e68900;
        }
        #cancelBtn {
            background-color :  #f44336;
            color            :  white;
        }
        #cancelBtn:hover {
            background-color :  #da190b;
        }
        .no-materials {
            text-align :  center;
            padding    :  20px;
            color      :  #666;
        }
        .no-results {
            text-align :  center;
            padding    :  20px;
            color      :  #999;
            display    :  none;
        }
    </style>
</head>
<body>
    <h2>Material Swap - Step 2: Choose Replacement Material</h2>
    
    <div class="instructions">
        Replacing #{selected_count} material(s). Select the new material to apply.
        Use the search box to quickly find materials in large lists.
    </div>

    <div class="search-container">
        <input type="text" id="searchInput" placeholder="Search materials..." />
    </div>

    <div class="materials-container" id="materialsContainer"></div>
    <div class="no-results" id="noResults">No materials match your search.</div>

    <div class="button-container">
        <button id="backBtn">Back</button>
        <button id="swapBtn" disabled>Swap Materials</button>
        <button id="cancelBtn">Cancel</button>
    </div>

    <script>
        const materialsData = #{materials_json};

        // Initialize the materials list
        function initializeMaterials() {
            const container = document.getElementById('materialsContainer');
            
            if (materialsData.length === 0) {
                container.innerHTML = '<div class="no-materials">No materials found in model.</div>';
                return;
            }

            materialsData.forEach((material, index) => {
                const materialItem = document.createElement('div');
                materialItem.className = 'material-item';
                materialItem.setAttribute('data-material-name', material.name.toLowerCase());
                
                const radio = document.createElement('input');
                radio.type = 'radio';
                radio.name = 'replacement_material';
                radio.id = 'material_' + index;
                radio.value = material.name;
                radio.addEventListener('change', updateSwapButton);
                
                const label = document.createElement('label');
                label.htmlFor = 'material_' + index;
                label.innerHTML = '<span class="material-name">' + escapeHtml(material.name) + '</span>';
                
                materialItem.appendChild(radio);
                materialItem.appendChild(label);
                container.appendChild(materialItem);
            });
        }

        // Update the Swap button state
        function updateSwapButton() {
            const radios = document.querySelectorAll('input[type="radio"]');
            const anySelected = Array.from(radios).some(r => r.checked);
            document.getElementById('swapBtn').disabled = !anySelected;
        }

        // Search filter
        document.getElementById('searchInput').addEventListener('input', (e) => {
            const filter = e.target.value.toLowerCase();
            const materialItems = document.querySelectorAll('.material-item');
            const noResults = document.getElementById('noResults');
            let visibleCount = 0;

            materialItems.forEach(item => {
                const materialName = item.getAttribute('data-material-name');
                if (materialName.includes(filter)) {
                    item.style.display = 'block';
                    visibleCount++;
                } else {
                    item.style.display = 'none';
                }
            });

            // Show/hide no results message
            if (visibleCount === 0 && filter.length > 0) {
                noResults.style.display = 'block';
            } else {
                noResults.style.display = 'none';
            }
        });

        // Swap button click
        document.getElementById('swapBtn').addEventListener('click', () => {
            const selectedRadio = document.querySelector('input[type="radio"]:checked');
            
            if (selectedRadio) {
                window.location = 'skp:replacement_selected@' + JSON.stringify(selectedRadio.value);
            }
        });

        // Back button click
        document.getElementById('backBtn').addEventListener('click', () => {
            window.location = 'skp:back@';
        });

        // Cancel button click
        document.getElementById('cancelBtn').addEventListener('click', () => {
            window.location = 'skp:cancel@';
        });

        // Escape HTML to prevent injection
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        // Initialize on load
        initializeMaterials();
    </script>
</body>
</html>
        HTML

        html
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Dialog Management - Two-Stage Flow
    # -----------------------------------------------------------------------------

    # Class variable to store state between dialogs
    @selected_materials_to_swap = nil
    @current_selection = nil
    @current_model = nil

    # FUNCTION | Show the first dialog (material selection)
    # ------------------------------------------------------------
    # Creates and displays the HTML dialog for material selection.
    #
    # @param materials_data [Hash] Hash of material data
    # ------------------------------------------------------------
    def self.show_first_dialog(materials_data)
        dialog = UI::HtmlDialog.new(
            {
                :dialog_title     => "#{PLUGIN_NAME} - Step 1",                # <-- Dialog title
                :preferences_key  => "Na_MaterialSwap_Step1",                  # <-- Preferences key
                :scrollable       => false,                                     # <-- Disable scrolling
                :resizable        => true,                                      # <-- Allow resizing
                :width            => 565,                                       # <-- Initial width (450 * 1.25)
                :height           => 750,                                       # <-- Initial height (500 * 1.5)
                :left             => 200,                                       # <-- Initial X position
                :top              => 200,                                       # <-- Initial Y position
                :min_width        => 438,                                       # <-- Minimum width (350 * 1.25)
                :min_height       => 600,                                       # <-- Minimum height (400 * 1.5)
                :max_width        => 1000,                                      # <-- Maximum width (800 * 1.25)
                :max_height       => 1200,                                      # <-- Maximum height (800 * 1.5)
                :style            => UI::HtmlDialog::STYLE_DIALOG               # <-- Dialog style
            }
        )

        # Add callback for materials selected action
        dialog.add_action_callback("materials_selected") do |action_context, materials_json|
            begin
                selected_material_names = JSON.parse(materials_json)          # <-- Parse JSON from dialog
                
                # Store selected material names for second dialog
                @selected_materials_to_swap = selected_material_names        # <-- Store selection
                
                dialog.close                                                  # <-- Close first dialog
                
                # Show second dialog
                show_second_dialog(selected_material_names.length)           # <-- Open second dialog
            rescue => e
                UI.messagebox("Error processing selection: #{e.message}")    # <-- Show error
            end
        end

        # Add callback for cancel action
        dialog.add_action_callback("cancel") do |action_context|
            dialog.close                                                      # <-- Close dialog
            @selected_materials_to_swap = nil                                # <-- Clear state
            @current_selection = nil                                         # <-- Clear state
            @current_model = nil                                             # <-- Clear state
        end

        # Set the HTML content and show
        html_content = generate_first_dialog_html(materials_data)            # <-- Generate HTML
        dialog.set_html(html_content)                                         # <-- Set HTML content
        dialog.show                                                           # <-- Show dialog
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show the second dialog (replacement selection)
    # ------------------------------------------------------------
    # Creates and displays the HTML dialog for replacement material selection.
    #
    # @param selected_count [Integer] Number of materials being replaced
    # ------------------------------------------------------------
    def self.show_second_dialog(selected_count)
        all_materials = @current_model.materials.to_a                        # <-- Get all model materials

        dialog = UI::HtmlDialog.new(
            {
                :dialog_title     => "#{PLUGIN_NAME} - Step 2",                # <-- Dialog title
                :preferences_key  => "Na_MaterialSwap_Step2",                  # <-- Preferences key
                :scrollable       => false,                                     # <-- Disable scrolling
                :resizable        => true,                                      # <-- Allow resizing
                :width            => 565,                                       # <-- Initial width (450 * 1.25)
                :height           => 825,                                       # <-- Initial height (550 * 1.5)
                :left             => 200,                                       # <-- Initial X position
                :top              => 200,                                       # <-- Initial Y position
                :min_width        => 438,                                       # <-- Minimum width (350 * 1.25)
                :min_height       => 675,                                       # <-- Minimum height (450 * 1.5)
                :max_width        => 1000,                                      # <-- Maximum width (800 * 1.25)
                :max_height       => 1350,                                      # <-- Maximum height (900 * 1.5)
                :style            => UI::HtmlDialog::STYLE_DIALOG               # <-- Dialog style
            }
        )

        # Add callback for replacement material selected
        dialog.add_action_callback("replacement_selected") do |action_context, material_name_json|
            begin
                replacement_material_name = JSON.parse(material_name_json)    # <-- Parse JSON from dialog
                
                # Find the actual material objects
                old_materials = @current_model.materials.select { |m| 
                    @selected_materials_to_swap.include?(m.name) 
                }
                
                new_material = @current_model.materials[replacement_material_name] # <-- Get replacement material
                
                unless new_material
                    UI.messagebox("Error: Replacement material not found.")   # <-- Show error
                    dialog.close                                              # <-- Close dialog
                    return
                end
                
                # Perform the swap operation
                @current_model.start_operation("Material Swap in Selection", true) # <-- Start undo operation
                count = swap_materials_recursive(@current_selection, old_materials, new_material) # <-- Execute swap
                @current_model.commit_operation                               # <-- Commit undo operation
                
                # Show confirmation message
                material_names = @selected_materials_to_swap.join(", ")
                UI.messagebox("Successfully swapped #{count} material applications.\n\nReplaced: #{material_names}\nWith: #{replacement_material_name}")
                
                dialog.close                                                  # <-- Close dialog
                
                # Clear state
                @selected_materials_to_swap = nil                            # <-- Clear state
                @current_selection = nil                                     # <-- Clear state
                @current_model = nil                                         # <-- Clear state
            rescue => e
                UI.messagebox("Error during material swap: #{e.message}")    # <-- Show error
                @current_model.abort_operation if @current_model             # <-- Abort operation on error
            end
        end

        # Add callback for back button
        dialog.add_action_callback("back") do |action_context|
            dialog.close                                                      # <-- Close second dialog
            
            # Recollect materials and show first dialog again
            materials_data = collect_materials_recursive(@current_selection) # <-- Re-collect materials
            show_first_dialog(materials_data)                                # <-- Show first dialog again
        end

        # Add callback for cancel action
        dialog.add_action_callback("cancel") do |action_context|
            dialog.close                                                      # <-- Close dialog
            @selected_materials_to_swap = nil                                # <-- Clear state
            @current_selection = nil                                         # <-- Clear state
            @current_model = nil                                             # <-- Clear state
        end

        # Set the HTML content and show
        html_content = generate_second_dialog_html(all_materials, selected_count) # <-- Generate HTML
        dialog.set_html(html_content)                                         # <-- Set HTML content
        dialog.show                                                           # <-- Show dialog
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Main command to launch the tool
    # ------------------------------------------------------------
    # Entry point for the plugin. Checks selection, collects materials, and shows
    # the first dialog.
    # ------------------------------------------------------------
    def self.launch
        model      = Sketchup.active_model                                    # <-- Get active model
        selection  = model.selection                                          # <-- Get current selection

        # Check if there's a selection
        if selection.empty?
            UI.messagebox("Please select some entities first.", MB_OK)        # <-- Show warning
            return
        end

        # Store state for dialog flow
        @current_model     = model                                            # <-- Store model reference
        @current_selection = selection                                        # <-- Store selection reference

        # Collect all materials from the selection (recursive)
        materials_data = collect_materials_recursive(selection)              # <-- Collect materials

        # Check if any materials were found
        if materials_data.empty?
            UI.messagebox("No materials found in selection. All entities are unpainted.", MB_OK) # <-- Show info
            return
        end

        # Show the first dialog
        show_first_dialog(materials_data)                                    # <-- Show material selection dialog
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run Material Swap Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts
    # Method name: Na__MaterialSwap__InSelection.Na__MaterialSwap__InSelection__Run
    # ------------------------------------------------------------
    def self.Na__MaterialSwap__InSelection__Run
        model = Sketchup.active_model                                         # <-- Get active model
        return unless model                                                   # <-- Exit if no active model
        
        launch                                                                 # <-- Launch the dialog
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Menu Registration and Startup Wiring
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                             # <-- Exit if already installed
        
        # Create UI command for Material Swap tool
        cmd = UI::Command.new('NA_MaterialSwapInSelection') do              # <-- Create command with ID
            Na__MaterialSwap__InSelection.Na__MaterialSwap__InSelection__Run  # <-- Call the hotkey entry point
        end
        cmd.tooltip = "Material Swap in Selection"                          # <-- Set tooltip
        cmd.status_bar_text = "Swap materials in selected entities (including nested) with a different material" # <-- Set status bar text
        
        # SET NAME FOR EXTENSIONS MENU AND HOTKEY SEARCH
        cmd.menu_text = "Na__MaterialSwap__InSelection"                     # <-- Set menu text for hotkey search
        
        # Add command to Plugins menu
        UI.menu('Plugins').add_item(cmd)                                     # <-- Add to Plugins menu
        
        @menu_installed = true                                                # <-- Mark as installed
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                             # <-- Install menu and commands
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__MaterialSwap__InSelection module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    Na__MaterialSwap__InSelection.activate_for_model(Sketchup.active_model)   # <-- Activate menu registration
    
    file_loaded(__FILE__)                                                     # <-- Mark file as loaded
end
