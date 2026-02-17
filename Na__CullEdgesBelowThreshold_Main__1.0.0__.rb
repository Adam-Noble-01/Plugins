# -----------------------------------------------------------------------------
# REGION | Cull Edges Below Threshold Tool
# -----------------------------------------------------------------------------
# Automates cleaning of small edges that fall below a user-defined threshold.
#
# METHODOLOGY (GROUP ISOLATION STRATEGY):
# 1. Explode Curves: Ensures all arcs/circles are treated as individual segments.
# 2. Analysis: Sorts edges into 'Keep' (>= threshold) and 'Cull' (< threshold).
# 3. ISOLATE (Copy/Move): Moves 'Keep' edges into a temporary Group. This protects
#    them completely from the deletion process (vertex preservation).
# 4. DELETION: Removes the small edges from the main context.
# 5. RESTORE (Paste In Place): Explodes the temporary group, returning the 
#    'Keep' edges to the model exactly as they were.
# -----------------------------------------------------------------------------

module Na__CullEdgesBelowThreshold

    # -----------------------------------------------------------------------------
    # REGION | Main Logic
    # -----------------------------------------------------------------------------

    # FUNCTION | Execute the Cull Process
    # ------------------------------------------------------------
    def self.run_cull_tool
        model = Sketchup.active_model                                    # <-- Get active model
        sel   = model.selection                                          # <-- Get current selection
        
        # 1. Validation: Check if selection is empty
        if sel.empty?
            UI.messagebox("Please select geometry first.")                 # <-- Warn user
            return
        end

        # 2. UI: Prompt user for threshold
        prompts  = ["Minimum Edge Length (mm):"]                         # <-- UI Label
        defaults = [20.0]                                                # <-- Default value (20mm)
        input    = UI.inputbox(prompts, defaults, "Cull Edges Threshold") # <-- Show Input Box
        
        return unless input                                              # <-- Exit if user cancelled
        
        # 3. Unit Conversion
        # Convert user input (float) to internal SketchUp length
        threshold_input = input[0].to_f                                  # <-- Ensure Float
        threshold_internal = threshold_input.mm                          # <-- Native API conversion
        
        # Debugging
        puts "Debug: Input=#{threshold_input}mm | Internal Threshold=#{threshold_internal.to_f}\""

        # 4. Start Undoable Operation
        model.start_operation('Cull Small Edges (Smart Group)', true)    # <-- Start undo block
        
        begin
            # ---------------------------------------------------------
            # STEP A: Explode Curves
            # ---------------------------------------------------------
            entities = model.active_entities
            initial_edges = sel.grep(Sketchup::Edge)                     # <-- Filter selection for edges
            
            # Find and explode curves to ensure we treat segments individually
            curves = initial_edges.map(&:curve).compact.uniq             # <-- Get unique curves
            count_exploded = 0
            
            curves.each do |c|
                if c.valid?
                    c.explode                                            # <-- Explode the curve
                    count_exploded += 1
                end
            end
            
            # ---------------------------------------------------------
            # STEP B: Analyze & Protect (Group Isolation Strategy)
            # ---------------------------------------------------------
            # We re-scan the selection to get current edges (post-explode).
            current_edges = sel.grep(Sketchup::Edge)
            
            edges_to_keep = []
            edges_to_cull = []
            
            current_edges.each do |edge|
                next unless edge.valid?
                
                if edge.length < threshold_internal
                    # Case 1: Edge is too small - Mark for deletion
                    edges_to_cull << edge
                else
                    # Case 2: Edge is valid - Mark for protection
                    edges_to_keep << edge
                end
            end
            
            count_to_delete = edges_to_cull.size
            count_kept = edges_to_keep.size
            
            # ---------------------------------------------------------
            # STEP C: Protection (The "Copy/Move" Phase)
            # ---------------------------------------------------------
            # We move the valid edges into a temporary group. 
            # This physically isolates them from the deletion process, 
            # ensuring no shared vertices are lost when culling neighbors.
            temp_group = nil
            if count_kept > 0
                # Create a group containing the 'keep' edges
                # Note: This moves them from the active context into the group
                # This bypasses the need for 'add_edge' entirely.
                temp_group = entities.add_group(edges_to_keep) 
            end

            # ---------------------------------------------------------
            # STEP D: Destructive Action (The "Clean" Phase)
            # ---------------------------------------------------------
            if count_to_delete > 0
                # Now we can safely delete the small edges. 
                # Since the good edges are in the group, they are safe.
                entities.erase_entities(edges_to_cull)
            end
            
            # ---------------------------------------------------------
            # STEP E: Restoration (The "Paste In Place" Phase)
            # ---------------------------------------------------------
            # We explode the temporary group to return the protected edges 
            # to their original context.
            if temp_group && temp_group.valid?
                temp_group.explode
            end
            
            # ---------------------------------------------------------
            # STEP F: Final Report
            # ---------------------------------------------------------
            model.commit_operation                                       # <-- Commit changes
            
            # Console Log
            puts "\n"                                                    # <-- Clean linebreak
            puts "----------------------------------------"              # <-- Print horizontal line
            puts "SMART CULL REPORT (Group Method)"                      # <-- Title
            puts "Threshold: #{threshold_input}mm"                       # <-- Log input
            puts "Curves Exploded: #{count_exploded}"                    # <-- Log exploded
            puts "Edges Deleted: #{count_to_delete}"                     # <-- Log deleted
            puts "Edges Protected: #{count_kept}"                        # <-- Log preserved
            puts "----------------------------------------"              # <-- Print horizontal line
            
            # UI Message
            msg = "Operation Complete.\n\n"
            msg += "Edges Deleted: #{count_to_delete} (Below #{threshold_input}mm)\n"
            msg += "Edges Protected: #{count_kept}\n"
            msg += "(Used Group Isolation to preserve geometry)"
            
            UI.messagebox(msg, MB_OK)                                    # <-- Show summary to user
            
        rescue => e
            model.abort_operation                                        # <-- Cancel if error occurs
            UI.messagebox("Error occurred: #{e.message}")                # <-- Report error
            puts "Error: #{e.message}"                                   # <-- Log error
            puts e.backtrace                                             # <-- Log backtrace
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Cull Edges Below Threshold (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences → Shortcuts to activate the tool
    # Method name: Na__CullEdgesBelowThreshold.Na__CullEdgesBelowThreshold__RunCullTool
    # ------------------------------------------------------------
    def self.Na__CullEdgesBelowThreshold__RunCullTool
        run_cull_tool                                                      # <-- Execute the cull process
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Menu Registration and Startup Wiring
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                          # <-- Exit if already installed

        # Create UI command
        cmd = UI::Command.new('NA_CullEdgesBelowThreshold') do             # <-- Create command with label
            Na__CullEdgesBelowThreshold.Na__CullEdgesBelowThreshold__RunCullTool  # <-- Call the hotkey entry point method
        end
        cmd.tooltip = "Cull Edges Below Threshold"                         # <-- Set tooltip
        cmd.status_bar_text = "Smart cleanup of small edges"               # <-- Set status bar text

        # Add command to Plugins menu
        menu = UI.menu('Plugins')                                          # <-- Get Plugins menu
        menu.add_item(cmd)                                                 # <-- Add item to Plugins menu

        @menu_installed = true                                             # <-- Mark as installed
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                          # <-- Install menu and commands
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__CullEdgesBelowThreshold module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK | Prevent re-execution on reload
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    # Activate immediately for the current model
    Na__CullEdgesBelowThreshold.activate_for_model(Sketchup.active_model)  # <-- Activate menu registration
    
    file_loaded(__FILE__)                                                  # <-- Mark file as loaded
end

# -----------------------------------------------------------------------------
# CONSOLE EXECUTION | Uncomment to run directly in Ruby Console
# -----------------------------------------------------------------------------
# Na__CullEdgesBelowThreshold.Na__CullEdgesBelowThreshold__RunCullTool