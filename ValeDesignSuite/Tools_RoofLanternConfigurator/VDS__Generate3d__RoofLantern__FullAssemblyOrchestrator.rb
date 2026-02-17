# =============================================================================
# VALEDESIGNSUITE - ROOF LANTERN FULL ASSEMBLY ORCHESTRATOR
# =============================================================================
#
# FILE       : VDS__Generate3d__RoofLantern__FullAssemblyOrchestrator.rb
# NAMESPACE  : ValeDesignSuite
# MODULE     : RoofLanternAssemblyOrchestrator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Orchestrate generation of complete roof lantern 3D assembly
# CREATED    : 2025
#
# DESCRIPTION:
# - This script orchestrates the generation of a complete roof lantern assembly.
# - It intelligently sorts user selection into rafters and hip rafters.
# - Delegates to appropriate generation scripts for each element type.
# - Processes standard rafters, hip rafters, and prepares for ridge beam.
# - Provides comprehensive feedback on generation success or failure.
#
# EXPECTED GROUP STRUCTURE:
# - Standard Rafters: Groups named "95__ValeRoofLantern__2dStandardRafterDatumLine__##"
#   containing SR##__3dDatumLine__Hypotenuse child groups
# - Hip Rafters: Groups named "95__ValeRoofLantern__2dHipRafterDatumLine__##"
#   containing HR##__3dDatumLine__Hypotenuse child groups
# - Ridge Beams: Groups named "95__ValeRoofLantern__2dRidgeBeamDatumLine__##"
#   (no child groups, contains edge directly)
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 12-Sep-2025 - Version 1.0.0
# - Initial implementation of orchestration logic
# - Intelligent sorting of rafters and hip rafters
# - Delegation to appropriate generation scripts
# - Placeholder for ridge beam generation
#
# 12-Sep-2025 - Version 1.0.1
# - Fixed group identification patterns to match actual naming convention
# - Added support for both RoofAngleTriangle and ValeRoofLantern prefixes
# - Added debug output to show group identification results
#
# =============================================================================

require 'sketchup.rb'

module ValeDesignSuite
    module RoofLanternAssemblyOrchestrator
        extend self

        # -----------------------------------------------------------------------------
        # REGION | Module Constants and Configuration
        # -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Group Identification Patterns
        # ------------------------------------------------------------
        # Patterns support both naming conventions (RoofAngleTriangle and ValeRoofLantern)
        STANDARD_RAFTER_PATTERN  =  /(RoofAngleTriangle__StandardRafter|ValeRoofLantern__2dStandardRafterDatumLine)/i   # <-- Pattern for standard rafter groups
        HIP_RAFTER_PATTERN       =  /(RoofAngleTriangle__HipRafter|ValeRoofLantern__2dHipRafterDatumLine)/i            # <-- Pattern for hip rafter groups
        RIDGE_BEAM_PATTERN       =  /(RoofAngleTriangle__RidgeBeam|ValeRoofLantern__2dRidgeBeamDatumLine)/i            # <-- Pattern for ridge beam groups
        
        # MODULE CONSTANTS | User Messages
        # ------------------------------------------------------------
        MSG_NO_MODEL             =  'No active SketchUp model.'                     # <-- Error when no model is open
        MSG_NO_SELECTION         =  'Please select roof lantern geometry groups.'   # <-- Error when nothing selected
        MSG_NO_VALID_GROUPS      =  'No valid roof lantern groups found in selection.' # <-- Error when no recognized groups
        MSG_SUCCESS_TEMPLATE     =  "Roof Lantern Assembly Generation Complete!\n\n" # <-- Success message template
        MSG_FAILURE_TEMPLATE     =  "Roof Lantern Assembly Generation Failed!\n\n"  # <-- Failure message template
        # ------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Helper Functions - Validation and Identification
        # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Validate Prerequisites for Generation
        # ------------------------------------------------------------
        def validate_prerequisites
            model = Sketchup.active_model                                           # <-- Get active model
            return [false, MSG_NO_MODEL] unless model                               # <-- Check model exists
            
            selection = model.selection                                             # <-- Get current selection
            return [false, MSG_NO_SELECTION] if selection.empty?                    # <-- Check selection not empty
            
            [true, nil]                                                             # <-- Return success
        end
        # ------------------------------------------------------------


        # HELPER FUNCTION | Check if Selection Has Valid Groups
        # ------------------------------------------------------------
        def has_valid_selection(selection)
            groups = selection.grep(Sketchup::Group) + selection.grep(Sketchup::ComponentInstance)
            !groups.empty?                                                          # <-- Return true if groups exist
        end
        # ------------------------------------------------------------


        # HELPER FUNCTION | Identify Group Type Based on Name
        # ------------------------------------------------------------
        def identify_group_type(group)
            name = group.name                                                       # <-- Get group name
            
            return :standard_rafter if name =~ STANDARD_RAFTER_PATTERN              # <-- Check for standard rafter
            return :hip_rafter if name =~ HIP_RAFTER_PATTERN                        # <-- Check for hip rafter
            return :ridge_beam if name =~ RIDGE_BEAM_PATTERN                        # <-- Check for ridge beam
            
            :unknown                                                                # <-- Unknown type
        end
        # ------------------------------------------------------------


        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Helper Functions - Selection Sorting
        # -----------------------------------------------------------------------------

        # FUNCTION | Sort Selection into Categories by Type
        # ------------------------------------------------------------
        def sort_selection_by_type(selection)
            sorted_groups = {                                                       # <-- Initialize result hash
                standard_rafters: [],                                               # <-- Standard rafter groups
                hip_rafters: [],                                                     # <-- Hip rafter groups
                ridge_beams: [],                                                     # <-- Ridge beam groups
                unknown: []                                                          # <-- Unrecognized groups
            }
            
            # Process all groups and components in selection
            all_groups = selection.grep(Sketchup::Group) + selection.grep(Sketchup::ComponentInstance)
            
            puts "\nIdentifying #{all_groups.length} selected groups:"                # <-- Debug output
            
            all_groups.each do |group|                                              # <-- Process each group
                type = identify_group_type(group)                                   # <-- Identify group type
                puts "  - '#{group.name}' → #{type}"                                # <-- Show identification result
                
                case type
                when :standard_rafter
                    sorted_groups[:standard_rafters] << group                       # <-- Add to standard rafters
                when :hip_rafter
                    sorted_groups[:hip_rafters] << group                            # <-- Add to hip rafters
                when :ridge_beam
                    sorted_groups[:ridge_beams] << group                            # <-- Add to ridge beams
                else
                    sorted_groups[:unknown] << group                                # <-- Add to unknown
                end
            end
            
            sorted_groups                                                           # <-- Return sorted groups
        end
        # ------------------------------------------------------------


        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Processing Functions - Element Generation
        # -----------------------------------------------------------------------------

        # SUB FUNCTION | Process Standard Rafters
        # ------------------------------------------------------------
        def process_standard_rafters(model, rafter_groups)
            return { success: true, count: 0, message: "No standard rafters to process" } if rafter_groups.empty?
            
            # Temporarily set selection to standard rafters
            model.selection.clear                                                   # <-- Clear current selection
            rafter_groups.each { |group| model.selection.add(group) }               # <-- Select rafter groups
            
            # Call the standard rafter generation script
            begin
                ValeDesignSuite::Create3dStandardRafterObject.run                  # <-- Run rafter generation
                
                # Return success with count
                {
                    success: true,
                    count: rafter_groups.length,
                    message: "Successfully processed #{rafter_groups.length} standard rafter group(s)"
                }
            rescue => e
                # Return failure with error
                {
                    success: false,
                    count: 0,
                    message: "Standard rafter generation failed: #{e.message}"
                }
            end
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Process Hip Rafters
        # ------------------------------------------------------------
        def process_hip_rafters(model, hip_groups)
            return { success: true, count: 0, message: "No hip rafters to process" } if hip_groups.empty?
            
            # Temporarily set selection to hip rafters
            model.selection.clear                                                   # <-- Clear current selection
            hip_groups.each { |group| model.selection.add(group) }                  # <-- Select hip groups
            
            # Call the hip rafter generation script
            begin
                ValeDesignSuite::Create3dStandardHipRafterObject.run                # <-- Run hip rafter generation
                
                # Return success with count
                {
                    success: true,
                    count: hip_groups.length,
                    message: "Successfully processed #{hip_groups.length} hip rafter group(s)"
                }
            rescue => e
                # Return failure with error
                {
                    success: false,
                    count: 0,
                    message: "Hip rafter generation failed: #{e.message}"
                }
            end
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Process Ridge Beam (Placeholder)
        # ------------------------------------------------------------
        def process_ridge_beam(model, ridge_groups)
            return { success: true, count: 0, message: "No ridge beams to process" } if ridge_groups.empty?
            
            # PLACEHOLDER: Ridge beam generation not yet implemented
            {
                success: true,
                count: ridge_groups.length,
                message: "Ridge beam generation pending (#{ridge_groups.length} group(s) found)"
            }
        end
        # ------------------------------------------------------------


        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Processing Functions - Main Orchestration
        # -----------------------------------------------------------------------------

        # FUNCTION | Orchestrate Complete Assembly Generation
        # ------------------------------------------------------------
        def orchestrate_generation(model, sorted_groups)
            results = {                                                             # <-- Initialize results tracking
                standard_rafters: nil,
                hip_rafters: nil,
                ridge_beams: nil,
                overall_success: true
            }
            
            # Save original selection to restore later
            original_selection = model.selection.to_a                               # <-- Store original selection
            
            # Process each element type in sequence
            puts "\n" + "="*60                                                      # <-- Visual separator in console
            puts "ROOF LANTERN ASSEMBLY ORCHESTRATOR - Starting Generation"
            puts "="*60
            
            # Process standard rafters
            if sorted_groups[:standard_rafters].any?
                puts "\nProcessing Standard Rafters..."
                results[:standard_rafters] = process_standard_rafters(model, sorted_groups[:standard_rafters])
                results[:overall_success] &&= results[:standard_rafters][:success]
            end
            
            # Process hip rafters
            if sorted_groups[:hip_rafters].any?
                puts "\nProcessing Hip Rafters..."
                results[:hip_rafters] = process_hip_rafters(model, sorted_groups[:hip_rafters])
                results[:overall_success] &&= results[:hip_rafters][:success]
            end
            
            # Process ridge beams (placeholder)
            if sorted_groups[:ridge_beams].any?
                puts "\nProcessing Ridge Beams..."
                results[:ridge_beams] = process_ridge_beam(model, sorted_groups[:ridge_beams])
                results[:overall_success] &&= results[:ridge_beams][:success]
            end
            
            # Restore original selection
            model.selection.clear                                                   # <-- Clear selection
            original_selection.each { |entity| model.selection.add(entity) if entity.valid? }
            
            puts "\n" + "="*60                                                      # <-- Visual separator
            puts "GENERATION COMPLETE"
            puts "="*60 + "\n"
            
            results                                                                  # <-- Return all results
        end
        # ------------------------------------------------------------


        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | User Feedback Functions
        # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Format Results for Display
        # ------------------------------------------------------------
        def format_results(results, sorted_groups)
            message_lines = []                                                      # <-- Initialize message lines
            
            # Add header based on overall success
            if results[:overall_success]
                message_lines << MSG_SUCCESS_TEMPLATE
            else
                message_lines << MSG_FAILURE_TEMPLATE
            end
            
            # Add standard rafter results
            if results[:standard_rafters]
                message_lines << "Standard Rafters:"
                message_lines << "  • #{results[:standard_rafters][:message]}"
            end
            
            # Add hip rafter results
            if results[:hip_rafters]
                message_lines << "\nHip Rafters:"
                message_lines << "  • #{results[:hip_rafters][:message]}"
            end
            
            # Add ridge beam results
            if results[:ridge_beams]
                message_lines << "\nRidge Beams:"
                message_lines << "  • #{results[:ridge_beams][:message]}"
            end
            
            # Add unknown groups warning if any
            if sorted_groups[:unknown].any?
                message_lines << "\n⚠ Warning:"
                message_lines << "  • #{sorted_groups[:unknown].length} unrecognized group(s) were not processed"
            end
            
            # Add summary
            total_processed = 0
            total_processed += results[:standard_rafters][:count] if results[:standard_rafters]
            total_processed += results[:hip_rafters][:count] if results[:hip_rafters]
            total_processed += results[:ridge_beams][:count] if results[:ridge_beams]
            
            message_lines << "\n" + "-"*40
            message_lines << "Total Groups Processed: #{total_processed}"
            
            message_lines.join("\n")                                                # <-- Join lines into message
        end
        # ------------------------------------------------------------


        # HELPER FUNCTION | Show Results Message to User
        # ------------------------------------------------------------
        def show_results_message(results, sorted_groups)
            formatted_message = format_results(results, sorted_groups)              # <-- Format the results
            
            # Determine icon based on success
            if results[:overall_success]
                UI.messagebox(formatted_message, MB_OK)                             # <-- Show success message
            else
                UI.messagebox(formatted_message, MB_OK)                             # <-- Show failure message
            end
        end
        # ------------------------------------------------------------


        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Main Entry Point
        # -----------------------------------------------------------------------------

        # FUNCTION | Main Entry Point for Assembly Orchestration
        # ------------------------------------------------------------
        def run
            # Validate prerequisites
            valid, error_message = validate_prerequisites                           # <-- Check prerequisites
            unless valid
                UI.messagebox(error_message)                                        # <-- Show error message
                return false
            end
            
            model = Sketchup.active_model                                           # <-- Get active model
            selection = model.selection                                             # <-- Get current selection
            
            # Check for valid groups in selection
            unless has_valid_selection(selection)
                UI.messagebox(MSG_NO_VALID_GROUPS)                                  # <-- Show error for no valid groups
                return false
            end
            
            # Sort selection by element type
            sorted_groups = sort_selection_by_type(selection)                       # <-- Sort groups by type
            
            # Check if any recognized groups were found
            total_recognized = sorted_groups[:standard_rafters].length +
                             sorted_groups[:hip_rafters].length +
                             sorted_groups[:ridge_beams].length
            
            if total_recognized == 0
                UI.messagebox(MSG_NO_VALID_GROUPS)                                  # <-- No recognized groups
                return false
            end
            
            # Start single operation for entire assembly
            model.start_operation('Generate Roof Lantern Assembly', true)
            
            begin
                # Orchestrate the generation process
                results = orchestrate_generation(model, sorted_groups)              # <-- Run orchestration
                
                # Commit the operation
                model.commit_operation
                
                # Show results to user
                show_results_message(results, sorted_groups)                        # <-- Display results
                
                results[:overall_success]                                           # <-- Return success status
                
            rescue => e
                # Abort operation on error
                model.abort_operation
                
                # Show error message
                error_msg = "Assembly generation failed!\n\nError: #{e.message}\n\nBacktrace:\n#{e.backtrace[0..2].join("\n")}"
                UI.messagebox(error_msg)
                
                false                                                                # <-- Return failure
            end
        end
        # ------------------------------------------------------------


        # endregion -------------------------------------------------------------------

    end
end


# -----------------------------------------------------------------------------
# REGION | Menu Integration and Auto-execution
# -----------------------------------------------------------------------------

# Menu hook - Add to Extensions menu
unless defined?($vale_assembly_orchestrator_menu_added) && $vale_assembly_orchestrator_menu_added
    UI.menu('Extensions').add_item('Vale: Generate Complete Roof Lantern Assembly') { 
        ValeDesignSuite::RoofLanternAssemblyOrchestrator.run 
    }
    $vale_assembly_orchestrator_menu_added = true
end

# Auto-run for console paste (for testing)
ValeDesignSuite::RoofLanternAssemblyOrchestrator.run

# endregion -------------------------------------------------------------------
