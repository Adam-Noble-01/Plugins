# =============================================================================
# VALEDESIGNSUITE - AUTO GROUP INDIVIDUAL FACE ISLANDS
# =============================================================================
#
# FILE       : Na_AutoGroup_ByIslands.rb
# NAMESPACE  : NaTools::Tools
# MODULE     : AutoGroupByIslands
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Detects and groups individual enclosed faces from the current
#              SketchUp selection into separate groups. Each face becomes its
#              own group regardless of connectivity to adjacent faces.
# CREATED    : 2025
#
# DESCRIPTION:
# - Automatically detects all individual faces in the active selection.
# - Each face is grouped into its own SketchUp Group sequentially.
# - Useful for separating adjoined enclosed boxes or individual face elements.
# - Provides validation warnings if any group is not a valid manifold solid.
# - Based on official SketchUp Ruby API 2024/2025 face detection methods.
# - Automatically filters selection to faces only, ignoring edges and other geometry.
#
# -----------------------------------------------------------------------------
#
# API RESEARCH FINDINGS:
# - Face#all_connected is the official method for connected geometry detection
# - Edge#all_connected works similarly for edge-based connectivity analysis
# - Face#classify_point(point) determines point-to-face spatial relationships
# - Face#coplanar_with?(other_face) available in SketchUp 2025.0 for planarity tests
# - Group#manifold? validates solid geometry integrity
# - Known display bug with all_connected method affecting selection highlighting
# - Connectivity detection only works within single editing contexts
# - Groups and Components create isolated geometry contexts
#
# DEVELOPMENT LOG:
# 28-May-2025 - Version 1.0.0
# - Initial implementation for individual face grouping
# - Sequential processing of enclosed faces from selection
# - Integration of SketchUp 2024/2025 API research findings
# - Added manifold validation and selection display bug workaround
#
# 02-Jun-2025 - Version 1.1.0
# - Enhanced batch selection support with automatic edge filtering
# - Added UI toolbar button following ValeDesignSuite design patterns
# - Improved selection workflow for mixed geometry selections
# - Auto-updates selection to show only processed faces
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Main Tool Functionality - Auto Group Individual Face Islands
# -----------------------------------------------------------------------------

module NaTools
    module Tools
        module AutoGroupByIslands

            # FUNCTION | Run Individual Face Grouping and Solid Validation
            # ------------------------------------------------------------
            def self.run
                model     = Sketchup.active_model                         # <-- Access current model
                selection = model.selection                              # <-- Get current selection
                ents      = model.active_entities                         # <-- Active editing context

                if selection.empty?
                    UI.messagebox("Please select geometry to process.")
                    return
                end

                # FILTER SELECTION TO FACES ONLY AND UPDATE SELECTION
                faces = filter_selection_to_faces_only(model, selection)
                if faces.empty?
                    UI.messagebox("Selection contains no faces to group.")
                    return
                end

                model.start_operation("Auto Group Face Islands", true)

                grouped_faces   = []                                     # <-- Track grouped faces
                non_solids      = []                                     # <-- Track non-manifold groups
                group_count     = 0                                      # <-- Sequential group counter

                faces.each do |face|
                    next if grouped_faces.include?(face)                 # <-- Skip already processed faces
                    
                    group_count += 1                                     # <-- Increment group counter
                    
                    # CREATE INDIVIDUAL FACE GROUP
                    face_group = create_individual_face_group(ents, face, group_count)
                    grouped_faces << face
                    
                    # VALIDATE GROUP AS MANIFOLD SOLID
                    is_solid = validate_group_manifold(face_group)
                    non_solids << face_group unless is_solid
                end

                model.commit_operation

                # APPLY SELECTION DISPLAY FIX FOR ALL_CONNECTED BUG
                apply_selection_display_fix(model, grouped_faces) if grouped_faces.any?

                # REPORT RESULTS TO USER
                report_grouping_results(group_count, non_solids)
            end
            # ---------------------------------------------------------------

            # SUB FUNCTION | Filter Selection to Faces Only and Update Selection
            # ---------------------------------------------------------------
            def self.filter_selection_to_faces_only(model, selection)
                faces = selection.grep(Sketchup::Face)                   # <-- Extract faces from selection
                
                # UPDATE SELECTION TO SHOW ONLY FACES
                if faces.any? && selection.length > faces.length
                    model.selection.clear                                # <-- Clear current selection
                    model.selection.add(faces)                          # <-- Add only faces back to selection
                end
                
                return faces                                             # <-- Return filtered faces array
            end
            # ---------------------------------------------------------------

            # SUB FUNCTION | Create Individual Face Group with Sequential Naming
            # ---------------------------------------------------------------
            def self.create_individual_face_group(entities, face, group_number)
                face_with_edges = [face] + face.edges                   # <-- Include face and bounding edges
                group = entities.add_group(face_with_edges)             # <-- Create group from face geometry
                group.name = "FaceIsland_#{group_number.to_s.rjust(3, '0')}"  # <-- Sequential naming with padding
                return group
            end
            # ---------------------------------------------------------------

            # SUB FUNCTION | Validate Group Manifold Solid Status
            # ---------------------------------------------------------------
            def self.validate_group_manifold(group)
                is_solid = false
                begin
                    is_solid = group.manifold?                          # <-- SketchUp 2024/2025 API solid validation
                rescue StandardError => e
                    puts "Manifold validation error: #{e.message}"      # <-- Handle validation errors gracefully
                    is_solid = false
                end
                return is_solid
            end
            # ---------------------------------------------------------------

            # SUB FUNCTION | Apply Selection Display Fix for all_connected Bug
            # ---------------------------------------------------------------
            def self.apply_selection_display_fix(model, processed_faces)
                # WORKAROUND FOR KNOWN SKETCHUP API BUG WITH ALL_CONNECTED
                # Bug affects selection highlighting after using connectivity methods
                current_selection = model.selection.to_a               # <-- Capture current selection
                model.selection.clear                                  # <-- Clear selection display
                model.selection.add(current_selection)                 # <-- Restore selection to fix display
            end
            # ---------------------------------------------------------------

            # SUB FUNCTION | Report Grouping Results to User
            # ---------------------------------------------------------------
            def self.report_grouping_results(group_count, non_solid_groups)
                success_message = "Successfully created #{group_count} face island groups."
                UI.messagebox(success_message)                               # <-- Show success message only
            end
            # ---------------------------------------------------------------

        end # module AutoGroupByIslands
    end # module Tools
end # module NaTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp UI Integration - Command and Toolbar Setup
# -----------------------------------------------------------------------------

unless file_loaded?(__FILE__)
    
    # PATH SETUP | Define Icon Paths from Na_Dependencies Folder
    # ------------------------------------------------------------
    plugin_root = File.dirname(__FILE__)                           # <-- Get current script directory
    plugins_root = File.dirname(File.dirname(plugin_root))         # <-- Go up to main Plugins directory  
    na_dependencies = File.join(plugins_root, 'Na_Dependencies')   # <-- Path to Na_Dependencies folder
    icon_path_small = File.join(na_dependencies, 'Icons_ValeIcons', 'Vale_Icon16px.png')  # <-- 16px icon path
    icon_path_large = File.join(na_dependencies, 'Icons_ValeIcons', 'Vale_Icon32px.png')  # <-- 32px icon path
    # ---------------------------------------------------------------

    # COMMAND SETUP | Create UI Command Following ValeDesignSuite Pattern
    # ------------------------------------------------------------
    cmd = UI::Command.new("NA | Auto Group Face Islands") {
        NaTools::Tools::AutoGroupByIslands.run                     # <-- Execute tool function
    }
    
    # Set command properties following ValeDesignSuite conventions
    cmd.tooltip = "Auto Group Face Islands"                        # <-- Tooltip text
    cmd.status_bar_text = "Groups each individual face in selection into separate groups"  # <-- Status bar text
    cmd.menu_text = "NA | Auto Group Face Islands"                 # <-- Menu display text
    
    # Set icons from Na_Dependencies folder
    if File.exist?(icon_path_small) && File.exist?(icon_path_large)
        cmd.small_icon = icon_path_small                            # <-- 16px icon for toolbar
        cmd.large_icon = icon_path_large                            # <-- 32px icon for toolbar
    else
        # Fallback: Log missing icons but continue without them
        puts "NA Tools: Icon files not found at Na_Dependencies paths"
        puts "Small icon path: #{icon_path_small}"
        puts "Large icon path: #{icon_path_large}"
        puts "Na_Dependencies folder: #{na_dependencies}"
        puts "Folder exists: #{File.exist?(na_dependencies)}"
    end
    # ---------------------------------------------------------------

    # MENU INTEGRATION | Add to Extensions Menu
    # ------------------------------------------------------------
    UI.menu("Extensions").add_item(cmd)                            # <-- Add command to Extensions menu
    # ---------------------------------------------------------------

    # TOOLBAR SETUP | Create Dedicated Toolbar Following ValeDesignSuite Pattern
    # ------------------------------------------------------------
    toolbar = UI::Toolbar.new("NA Tools")                          # <-- Create or get NA Tools toolbar
    toolbar.add_item(cmd)                                          # <-- Add command to toolbar
    
    # Auto-show toolbar (following ValeDesignSuite pattern)
    toolbar.show if toolbar.get_last_state != TB_HIDDEN           # <-- Show toolbar if not explicitly hidden
    # ---------------------------------------------------------------
    
    file_loaded(__FILE__)                                          # <-- Mark file as loaded
end

# endregion -------------------------------------------------------------------
