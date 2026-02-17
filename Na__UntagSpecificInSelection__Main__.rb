# -----------------------------------------------------------------------------
# REGION | Untag Specific in Selection Tool
# -----------------------------------------------------------------------------
# A SketchUp Ruby plugin to selectively untag specific tags from the current
# selection while preserving other tags on deeply nested elements.
# Works recursively through groups, components, and loose geometry.
# Compatible with: SketchUp 2025+
# -----------------------------------------------------------------------------

module Na__UntagSpecificInSelection

    # -----------------------------------------------------------------------------
    # REGION | Constants
    # -----------------------------------------------------------------------------

    PLUGIN_NAME        = "Untag Specific in Selection"
    PLUGIN_VERSION     = "1.2.0"

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Core Logic - Tag Collection
    # -----------------------------------------------------------------------------

    # FUNCTION | Collect all unique tags from selection (recursive)
    # ------------------------------------------------------------
    # Recursively traverses the selection and all nested entities to build
    # a hash of unique tags found, along with counts of entities per tag.
    #
    # @param entities [Sketchup::Entities] The entities to scan
    # @param tags_hash [Hash] Accumulator hash {tag_name => {layer: Layer, count: Integer}}
    # @return [Hash] The accumulated tags hash
    # ------------------------------------------------------------
    def self.collect_tags_recursive(entities, tags_hash = {})
        entities.each do |entity|
            # Check if entity has a layer/tag property
            if entity.respond_to?(:layer) && entity.layer
                layer      = entity.layer                                     # <-- Get layer object
                layer_name = layer.name                                       # <-- Get layer name

                # Skip Layer0 (the default "untagged" layer)
                unless layer_name == "Layer0"
                    if tags_hash[layer_name]
                        tags_hash[layer_name][:count] += 1                    # <-- Increment count
                    else
                        tags_hash[layer_name] = { layer: layer, count: 1 }    # <-- Initialize entry
                    end
                end
            end

            # Recursively process nested entities
            if entity.is_a?(Sketchup::Group)
                collect_tags_recursive(entity.definition.entities, tags_hash)   # <-- Recurse into group
            elsif entity.is_a?(Sketchup::ComponentInstance)
                collect_tags_recursive(entity.definition.entities, tags_hash) # <-- Recurse into component
            end
        end

        tags_hash
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Core Logic - Untagging Operation
    # -----------------------------------------------------------------------------

    # FUNCTION | Untag entities with specified tags (recursive)
    # ------------------------------------------------------------
    # Recursively traverses entities and sets matching tags to Layer0 (untagged).
    #
    # @param entities [Sketchup::Entities] The entities to process
    # @param tag_names_to_remove [Array<String>] Array of tag names to remove
    # @param model [Sketchup::Model] The active model
    # @return [Integer] Count of entities modified
    # ------------------------------------------------------------
    def self.untag_entities_recursive(entities, tag_names_to_remove, model)
        count   = 0                                                           # <-- Initialize counter
        layer0  = model.layers[0]                                            # <-- Get default "untagged" layer

        entities.each do |entity|
            # Check if entity has a layer/tag and if it matches one to remove
            if entity.respond_to?(:layer) && entity.layer
                if tag_names_to_remove.include?(entity.layer.name)
                    entity.layer = layer0                                     # <-- Set to untagged
                    count += 1                                                # <-- Increment counter
                end
            end

            # Recursively process nested entities
            if entity.is_a?(Sketchup::Group)
                count += untag_entities_recursive(entity.definition.entities, tag_names_to_remove, model) # <-- Recurse into group
            elsif entity.is_a?(Sketchup::ComponentInstance)
                count += untag_entities_recursive(entity.definition.entities, tag_names_to_remove, model) # <-- Recurse into component
            end
        end

        count
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | UI - HTML Dialog Generation
    # -----------------------------------------------------------------------------

    # FUNCTION | Generate HTML for the dialog
    # ------------------------------------------------------------
    # Creates the HTML content for the tag selection dialog.
    #
    # @param tags_data [Hash] Hash of tag data {name => {layer:, count:}}
    # @return [String] HTML content
    # ------------------------------------------------------------
    def self.generate_html(tags_data)
        tags_json = tags_data.map { |name, data| 
            { name: name, count: data[:count] }
        }.to_json

        html = <<-HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        h2 {
            margin-top: 0;
            color: #333;
            font-size: 18px;
        }
        .instructions {
            background-color: #e3f2fd;
            padding: 10px;
            border-radius: 4px;
            margin-bottom: 15px;
            font-size: 13px;
            color: #1976d2;
        }
        .tags-container {
            background-color: white;
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 10px;
            max-height: 300px;
            overflow-y: auto;
            margin-bottom: 15px;
        }
        .tag-item {
            padding: 8px;
            margin: 4px 0;
            border-radius: 3px;
            transition: background-color 0.2s;
        }
        .tag-item:hover {
            background-color: #f0f0f0;
        }
        .tag-item input[type="checkbox"] {
            margin-right: 8px;
            cursor: pointer;
        }
        .tag-item label {
            cursor: pointer;
            display: inline-block;
            width: calc(100% - 25px);
        }
        .tag-name {
            font-weight: bold;
            color: #333;
        }
        .tag-count {
            color: #666;
            font-size: 12px;
            margin-left: 8px;
        }
        .button-container {
            display: flex;
            gap: 10px;
            justify-content: flex-end;
        }
        button {
            padding: 8px 16px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            transition: background-color 0.2s;
        }
        #untagBtn {
            background-color: #4CAF50;
            color: white;
        }
        #untagBtn:hover {
            background-color: #45a049;
        }
        #untagBtn:disabled {
            background-color: #cccccc;
            cursor: not-allowed;
        }
        #cancelBtn {
            background-color: #f44336;
            color: white;
        }
        #cancelBtn:hover {
            background-color: #da190b;
        }
        #selectAllBtn {
            background-color: #2196F3;
            color: white;
            margin-right: auto;
        }
        #selectAllBtn:hover {
            background-color: #0b7dda;
        }
        .no-tags {
            text-align: center;
            padding: 20px;
            color: #666;
        }
    </style>
</head>
<body>
    <h2>Untag Specific in Selection</h2>
    
    <div class="instructions">
        Select the tag(s) you want to remove from the current selection. 
        Only entities with the selected tags will be moved to "Untagged" (Layer0).
    </div>

    <div class="tags-container" id="tagsContainer"></div>

    <div class="button-container">
        <button id="selectAllBtn">Select All</button>
        <button id="untagBtn" disabled>Untag Selected</button>
        <button id="cancelBtn">Cancel</button>
    </div>

    <script>
        const tagsData = #{tags_json};
        let selectAllState = false;

        // Initialize the tags list
        function initializeTags() {
            const container = document.getElementById('tagsContainer');
            
            if (tagsData.length === 0) {
                container.innerHTML = '<div class="no-tags">No tags found in selection (all entities are untagged).</div>';
                return;
            }

            tagsData.forEach((tag, index) => {
                const tagItem = document.createElement('div');
                tagItem.className = 'tag-item';
                
                const checkbox = document.createElement('input');
                checkbox.type = 'checkbox';
                checkbox.id = 'tag_' + index;
                checkbox.value = tag.name;
                checkbox.addEventListener('change', updateUntagButton);
                
                const label = document.createElement('label');
                label.htmlFor = 'tag_' + index;
                label.innerHTML = '<span class="tag-name">' + escapeHtml(tag.name) + '</span>' +
                                '<span class="tag-count">(' + tag.count + ' entities)</span>';
                
                tagItem.appendChild(checkbox);
                tagItem.appendChild(label);
                container.appendChild(tagItem);
            });
        }

        // Update the Untag button state
        function updateUntagButton() {
            const checkboxes = document.querySelectorAll('input[type="checkbox"]');
            const anyChecked = Array.from(checkboxes).some(cb => cb.checked);
            document.getElementById('untagBtn').disabled = !anyChecked;
        }

        // Select/Deselect all tags
        document.getElementById('selectAllBtn').addEventListener('click', () => {
            selectAllState = !selectAllState;
            const checkboxes = document.querySelectorAll('input[type="checkbox"]');
            checkboxes.forEach(cb => cb.checked = selectAllState);
            updateUntagButton();
            document.getElementById('selectAllBtn').textContent = selectAllState ? 'Deselect All' : 'Select All';
        });

        // Untag button click
        document.getElementById('untagBtn').addEventListener('click', () => {
            const checkboxes = document.querySelectorAll('input[type="checkbox"]:checked');
            const selectedTags = Array.from(checkboxes).map(cb => cb.value);
            
            if (selectedTags.length > 0) {
                window.location = 'skp:untag@' + JSON.stringify(selectedTags);
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
        initializeTags();
    </script>
</body>
</html>
        HTML

        html
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show the tag selection dialog
    # ------------------------------------------------------------
    # Creates and displays the HTML dialog for tag selection.
    #
    # @param tags_data [Hash] Hash of tag data
    # ------------------------------------------------------------
    def self.show_dialog(tags_data)
        dialog = UI::HtmlDialog.new(
            {
                :dialog_title     => PLUGIN_NAME,                            # <-- Dialog title
                :preferences_key  => "Na_UntagSpecificInSelection",          # <-- Preferences key
                :scrollable       => false,                                   # <-- Disable scrolling
                :resizable        => true,                                    # <-- Allow resizing
                :width            => 450,                                     # <-- Initial width
                :height           => 500,                                     # <-- Initial height
                :left             => 200,                                     # <-- Initial X position
                :top              => 200,                                     # <-- Initial Y position
                :min_width        => 350,                                     # <-- Minimum width
                :min_height       => 400,                                     # <-- Minimum height
                :max_width        => 800,                                     # <-- Maximum width
                :max_height       => 800,                                     # <-- Maximum height
                :style            => UI::HtmlDialog::STYLE_DIALOG             # <-- Dialog style
            }
        )

        # Add callback for untag action
        dialog.add_action_callback("untag") do |action_context, tags_json|
            begin
                tags_to_remove = JSON.parse(tags_json)                        # <-- Parse JSON from dialog
                model         = Sketchup.active_model                         # <-- Get active model
                selection     = model.selection                               # <-- Get current selection

                # Perform the untagging operation
                model.start_operation("Untag Specific in Selection", true)     # <-- Start undo operation
                count = untag_entities_recursive(selection, tags_to_remove, model) # <-- Execute untagging
                model.commit_operation                                        # <-- Commit undo operation

                # Show confirmation message
                UI.messagebox("Successfully untagged #{count} entities from #{tags_to_remove.length} tag(s).")
                
                dialog.close                                                  # <-- Close dialog
            rescue => e
                UI.messagebox("Error during untagging: #{e.message}")         # <-- Show error
                model.abort_operation if model                               # <-- Abort operation on error
            end
        end

        # Add callback for cancel action
        dialog.add_action_callback("cancel") do |action_context|
            dialog.close                                                      # <-- Close dialog
        end

        # Set the HTML content and show
        html_content = generate_html(tags_data)                               # <-- Generate HTML
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
    # Entry point for the plugin. Checks selection, collects tags, and shows
    # the dialog.
    # ------------------------------------------------------------
    def self.launch
        model      = Sketchup.active_model                                    # <-- Get active model
        selection  = model.selection                                          # <-- Get current selection

        # Check if there's a selection
        if selection.empty?
            UI.messagebox("Please select some entities first.", MB_OK)        # <-- Show warning
            return
        end

        # Collect all tags from the selection (recursive)
        tags_data = collect_tags_recursive(selection)                        # <-- Collect tags

        # Check if any tags were found
        if tags_data.empty?
            UI.messagebox("No tags found in selection. All entities are already untagged (Layer0).", MB_OK) # <-- Show info
            return
        end

        # Show the dialog
        show_dialog(tags_data)                                                # <-- Show tag selection dialog
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run Untag Specific Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts
    # Method name: Na__UntagSpecificInSelection.Na__UntagSpecificInSelection__Run
    # ------------------------------------------------------------
    def self.Na__UntagSpecificInSelection__Run
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
        
        # Create UI command for Untag Specific tool
        cmd = UI::Command.new('NA_UntagSpecificInSelection') do              # <-- Create command with ID
            Na__UntagSpecificInSelection.Na__UntagSpecificInSelection__Run    # <-- Call the hotkey entry point
        end
        cmd.tooltip = "Untag Specific in Selection"                          # <-- Set tooltip
        cmd.status_bar_text = "Remove specific tags from selected entities while preserving others" # <-- Set status bar text
        
        # SET NAME FOR EXTENSIONS MENU AND HOTKEY SEARCH
        cmd.menu_text = "Na__UntagSpecificInSelection"                       # <-- Set menu text for hotkey search
        
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

end # End Na__UntagSpecificInSelection module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    Na__UntagSpecificInSelection.activate_for_model(Sketchup.active_model)   # <-- Activate menu registration
    
    file_loaded(__FILE__)                                                     # <-- Mark file as loaded
end
