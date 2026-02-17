# =============================================================================
# VALEDESIGNSUITE - PATH TO CONTINUOUS PROFILE TOOL
# =============================================================================
#
# FILE       : VDS__Tool__Create3d__PathToContinousProfileTool.rb
# NAMESPACE  : ValeDesignSuite
# MODULE     : PathToContinuousProfileTool
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : JSON Profile Follow Me Along Selected Path with Inset Start and Corner Safety
# CREATED    : 2025
#
# DESCRIPTION:
# - Creates 3D geometry by following JSON-defined 2D profiles along selected paths in SketchUp.
# - Supports multiple JSON profile file selection for batch processing.
# - Automatically calculates and applies path start inset based on profile maximum dimension (max_dim × 1.10).
# - Builds continuous paths from selected edges, handling both open and closed path configurations.
# - Uses temporary x100 scaling during Follow Me operation to prevent tiny-face artifacts.
# - Automatically applies smooth and soften operations at 20-degree threshold for clean geometry.
# - Processes each profile sequentially in separate groups to avoid sticky geometry.
# - Validates path continuity and rejects branching or T-junction configurations.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 03-Sep-2025 - Version 1.0.0
# - Initial implementation with JSON profile reading and Follow Me functionality
# - Path validation and inset calculation features
# - Temporary scaling for tiny-face artifact prevention
#
# 03-Sep-2025 - Version 1.1.0
# - Refactored to ValeDesignSuite coding conventions
# - Added proper regional structure and embedded JSON method index
# - Enhanced error handling and user feedback systems
# - Improved code organization with logical function groupings
#
# 03-Sep-2025 - Version 1.2.0
# - Major refactoring to eliminate duplicate code sections
# - Created unified process_json_followme_with_options core function
# - Simplified entry points to use parameterized core function
# - Reduced code size by ~150 lines while maintaining full functionality
# - Improved maintainability through single source of truth architecture
#
# 03-Sep-2025 - Version 2.0.0
# - Added support for multiple JSON profile file selection
# - Each profile creates separate groups for all paths to avoid sticky geometry
# - Added default profile library path with fallback to user home directory
# - Enhanced completion reporting to show profile and path counts
# - Added intelligent loop detection to conditionally apply inset feature
# - Inset only applied to closed loops (skirting boards), disabled for open paths (U-shapes)
#
# 03-Sep-2025 - Version 2.1.0
# - Added directory selection mode for batch processing of JSON profiles
# - Implemented UI.select_directory for folder-based profile loading
# - Profiles are automatically sorted alphabetically for consistent processing order
# - Added pattern matching to filter only profile files (PFL### naming convention)
# - Enhanced menu system with four options: normal/reversed × files/directory
# - Directory mode shows confirmation dialog with file list before processing
#
# 17-Sep-2025 - Version 2.2.1
# - Fixed Y-axis negation error - SketchUp Ruby API doesn't support unary minus on Vector3d
# - Changed to use .reverse method for proper vector negation
# - Corrected handedness control by reversing X-axis only
# - Profile flips to opposite side of path while maintaining upright orientation
# - Y-axis remains unchanged to prevent profile from being inverted
#
# =============================================================================

require 'sketchup.rb'
require 'json'

module ValeDesignSuite
module PathToContinuousProfileTool
    extend self


# -----------------------------------------------------------------------------
# REGION | Embedded JSON Method & Function Index
# -----------------------------------------------------------------------------

    # EMBEDDED JSON | Script Method & Function Index
    # ------------------------------------------------------------
    SCRIPT_METHOD_INDEX = {
      "script_info": {
        "name": "PathToContinuousProfileTool",
        "version": "2.2.2", 
        "purpose": "JSON Profile Follow Me Along Selected Path with Handedness Control and Directory Support"
      },
      "constants": {
        "conversion": ["MM_PER_INCH"],
        "tolerances": ["GEOMETRIC_TOLERANCE"],
        "processing": ["DEFAULT_SCALE_FACTOR", "DEFAULT_SMOOTH_THRESHOLD"]
      },
      "entry_point": {
        "main": ["run", "run_with_reversed_profile", "run_from_directory", "run_from_directory_with_reversed_profile"],
        "core_processing": ["process_json_followme_with_options"]
      },
      "json_processing": {
        "schema_reader": ["extract_first_profile_loop_from_schema"],
        "profile_analysis": ["profile_max_dimension_mm", "build_profile_definition_preserving_datum"]
      },
      "profile_manipulation": {
        "deprecated": ["reverse_profile_x_coordinates"]
      },
      "loop_detection": {
        "closure_analysis": ["path_requires_inset?", "analyze_path_closure_requirements"]
      },
      "path_processing": {
        "chain_building": ["build_connected_chains", "shares_vertex_with_set"],
        "path_ordering": ["order_edges_into_path", "path_is_closed?"],
        "point_extraction": ["points_from_ordered_edges"],
        "path_modification": ["reseed_points_with_inset", "sanitize_points"],
        "single_profile_processing": ["process_single_profile_on_edges"]
      },
      "geometry_utilities": {
        "coordinate_systems": ["robust_xy_from_z"],
        "path_creation": ["add_path_edges_from_points"],
        "validation": ["branching_vertices_in_set", "near_equal?"],
        "utilities": ["safe_pid"]
      },
      "finishing_operations": {
        "edge_management": ["hide_edges"],
        "surface_treatment": ["apply_smooth_and_soften"]
      },
      "api_functions": {
        "menu_management": ["register_menu_item", "force_reload_menu_items"]
      }
    }.freeze
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Main Global Scope Constants
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Unit Conversion and Geometric Tolerances
    # ------------------------------------------------------------
    MM_PER_INCH                 = 25.4                                        # <-- Millimeter to inch conversion factor
    GEOMETRIC_TOLERANCE         = 1.0e-6                                      # <-- Geometric tolerance in inches
    DEFAULT_SCALE_FACTOR        = 100.0                                       # <-- Temporary scale factor for Follow Me
    DEFAULT_SMOOTH_THRESHOLD    = 20.0                                        # <-- Default smoothing threshold in degrees
    DEFAULT_INSET_MULTIPLIER    = 1.10                                        # <-- Profile size multiplier for path inset
    DEFAULT_PROFILE_LIBRARY     = 'D:\02_CoreLib__SketchUp\01_CoreLib__Components\60-Series__ProfilesLibrary__ValeProfilesLib'  # <-- Default profile library path
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------



# -----------------------------------------------------------------------------
# REGION | Global Helper Functions
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Check Point Proximity Within Tolerance
    # ------------------------------------------------------------
    def near_equal?(point1, point2, tolerance)
        point1.distance(point2) <= tolerance                                  # <-- Calculate distance and compare to tolerance
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Safe Persistent ID Extraction for Vertex Sorting
    # ------------------------------------------------------------
    def safe_pid(vertex)
        vertex.respond_to?(:persistent_id) ? vertex.persistent_id : 0         # <-- Get persistent ID or fallback to 0
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Check if Edge Shares Vertex with Edge Set
    # ------------------------------------------------------------
    def shares_vertex_with_set?(edge, edge_set)
        edge_vertices = edge.vertices                                         # <-- Get vertices from target edge
        edge_set.any? { |set_edge| (set_edge.vertices & edge_vertices).any? } # <-- Check for shared vertices
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Entry Point Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Main Entry Point for Path to Continuous Profile Tool
    # ------------------------------------------------------------
    def run
        process_json_followme_with_options(reverse_profile: false)           # <-- Execute with normal profile
    end
    # ------------------------------------------------------------


    # FUNCTION | Main Entry Point with Opposite Handedness for Interior/Exterior Control
    # ------------------------------------------------------------
    def run_with_reversed_profile
        process_json_followme_with_options(reverse_profile: true)            # <-- Execute with opposite handedness
    end
    # ------------------------------------------------------------


    # FUNCTION | Process All JSON Files from Selected Directory
    # ------------------------------------------------------------
    def run_from_directory
        process_json_followme_with_options(reverse_profile: false, use_directory: true)  # <-- Execute with directory selection
    end
    # ------------------------------------------------------------


    # FUNCTION | Process All JSON Files from Directory with Opposite Handedness
    # ------------------------------------------------------------
    def run_from_directory_with_reversed_profile
        process_json_followme_with_options(reverse_profile: true, use_directory: true)   # <-- Execute with directory selection and opposite handedness
    end
    # ------------------------------------------------------------


    # FUNCTION | Process JSON Follow Me with Configurable Options
    # ------------------------------------------------------------
    def process_json_followme_with_options(reverse_profile: false, use_directory: false)
        active_model = Sketchup.active_model                                 # <-- Get active SketchUp model
        return UI.messagebox('No active model.') unless active_model        # <-- Validate model exists
        
        model_entities = active_model.active_entities                        # <-- Get current edit context
        model_selection = active_model.selection                             # <-- Get current selection
        selected_edges = model_selection.grep(Sketchup::Edge)                # <-- Filter for edges only
        
        return UI.messagebox('Select a continuous path: connected edges in the current edit context.') if selected_edges.empty? # <-- Validate selection
        
        # Determine default directory for file dialog
        default_directory = File.directory?(DEFAULT_PROFILE_LIBRARY) ? DEFAULT_PROFILE_LIBRARY : Dir.home  # <-- Use library or home
        
        # Get multiple JSON profile files from user
        json_file_paths = []                                                 # <-- Initialize file paths array
        
        if use_directory
            # Directory selection mode
            selected_directory = UI.select_directory(
                title: "Select Directory Containing JSON Profiles",
                directory: default_directory
            )                                                                 # <-- Open directory selection dialog
            
            return unless selected_directory                                 # <-- Exit if cancelled
            
            # Find all JSON files in the selected directory
            json_file_paths = Dir.glob(File.join(selected_directory, "*.json")).sort  # <-- Get sorted JSON files
            
            if json_file_paths.empty?
                UI.messagebox("No JSON files found in selected directory:\n#{selected_directory}")  # <-- Show error
                return
            end
            
            # Filter for profile files (exclude non-profile JSON files)
            json_file_paths = json_file_paths.select do |path|
                basename = File.basename(path)
                basename.match?(/^PFL\d{3}.*\.json$/i)                      # <-- Match profile naming pattern
            end
            
            if json_file_paths.empty?
                UI.messagebox("No profile JSON files (PFL###) found in selected directory:\n#{selected_directory}")  # <-- Show error
                return
            end
            
            # Show confirmation dialog with file list
            file_list = json_file_paths.map { |f| File.basename(f) }.join("\n")  # <-- Create file list
            truncated_list = file_list.lines.first(15).join                  # <-- Truncate long lists
            if json_file_paths.length > 15
                truncated_list += "\n... and #{json_file_paths.length - 15} more files"  # <-- Add truncation note
            end
            
            result = UI.messagebox(
                "Found #{json_file_paths.length} profile JSON files:\n\n" +
                truncated_list + "\n\n" +
                "Process all files in order?",
                MB_YESNO
            )                                                                 # <-- Confirm processing
            
            return if result == IDNO                                         # <-- Exit if user cancels
            
        else
            # Original iterative selection mode
            loop do
                file_prompt = json_file_paths.empty? ? 
                    'Select First Profile JSON File' : 
                    "Select Next Profile JSON File (#{json_file_paths.length} selected so far)"  # <-- Dynamic prompt
                
                json_file_path = UI.openpanel(file_prompt, default_directory, 'JSON Files|*.json||') # <-- Open single file dialog
                
                break unless json_file_path && File.exist?(json_file_path)   # <-- Break if cancelled or invalid
                
                # Check for duplicates
                unless json_file_paths.include?(json_file_path)
                    json_file_paths << json_file_path                        # <-- Add to collection
                end
                
                # Ask user if they want to add more files
                result = UI.messagebox("Added: #{File.basename(json_file_path)}\n\nTotal files selected: #{json_file_paths.length}\n\nAdd another profile file?", MB_YESNO) # <-- Continue prompt
                break if result == IDNO                                      # <-- Break if user says no
            end
        end
        
        return if json_file_paths.empty?                                     # <-- Exit if no files selected
        
        # Process selected edges into connected chains once (reuse for all profiles)
        edge_chains = build_connected_chains(selected_edges)                 # <-- Build connected chains
        if edge_chains.empty?
            UI.messagebox('No connected paths found in the selection.')      # <-- Show error message
            return
        end
        
        # Analyze path closure to determine inset requirements
        path_analysis = analyze_path_closure_requirements(edge_chains)       # <-- Analyze path closure
        should_apply_inset = path_analysis[:requires_inset]                  # <-- Determine if inset needed
        
        # Configure operation parameters based on profile type and inset requirement
        inset_suffix = should_apply_inset ? ' (Inset Start)' : ' (No Inset)'  # <-- Indicate inset status
        source_suffix = use_directory ? ' [Directory]' : ' [Files]'          # <-- Indicate source type
        operation_name = reverse_profile ? 
            "VDS JSON Follow Me Along Path (Reversed Profile)#{inset_suffix}#{source_suffix} - #{json_file_paths.length} Profiles" : 
            "VDS JSON Follow Me Along Path#{inset_suffix}#{source_suffix} - #{json_file_paths.length} Profiles"  # <-- Set operation name
        
        # Start SketchUp operation
        active_model.start_operation(operation_name, true)                   # <-- Begin operation
        
        total_profiles_processed = 0                                         # <-- Track successful profiles
        total_groups_created = 0                                             # <-- Track total groups created
        
        # Process each JSON profile file
        json_file_paths.each_with_index do |json_file_path, profile_index|
            begin
                # Parse JSON profile data
                profile_data = JSON.parse(File.read(json_file_path))         # <-- Load and parse JSON
                
                # Extract profile loop from JSON schema
                profile_loop_mm = extract_first_profile_loop_from_schema(profile_data) # <-- Extract 2D profile
                unless profile_loop_mm && profile_loop_mm.length >= 3
                    UI.messagebox("Profile #{profile_index + 1}: No valid 2D profile loop found in JSON file:\n#{File.basename(json_file_path)}") # <-- Show error
                    next
                end
                
                # Profile coordinates remain unchanged - handedness is controlled via coordinate system
                processed_profile_loop_mm = profile_loop_mm                  # <-- Use original profile geometry
                
                # Calculate profile-based inset distance
                max_profile_dimension_mm = profile_max_dimension_mm(processed_profile_loop_mm) # <-- Get profile size
                inset_distance_mm = max_profile_dimension_mm * DEFAULT_INSET_MULTIPLIER # <-- Calculate inset
                inset_distance_inches = inset_distance_mm / MM_PER_INCH      # <-- Convert to inches
                
                # Generate unique profile name from filename
                profile_name = File.basename(json_file_path, '.json')        # <-- Extract filename without extension
                
                # Build profile definition
                profile_definition = build_profile_definition_preserving_datum(active_model, processed_profile_loop_mm) # <-- Create profile
                unless profile_definition
                    UI.messagebox("Profile #{profile_index + 1}: Failed to build profile definition for:\n#{profile_name}") # <-- Show error
                    next
                end
                
                # Process the selected edges as a single path for this profile
                success = process_single_profile_on_edges(
                    active_model, 
                    model_entities, 
                    edge_chains, 
                    profile_definition, 
                    profile_name, 
                    inset_distance_inches, 
                    reverse_profile,
                    should_apply_inset
                )                                                             # <-- Process profile on all edges
                
                if success
                    total_profiles_processed += 1                            # <-- Count successful profiles
                    total_groups_created += success                          # <-- Add number of groups created
                end
                
            rescue JSON::ParserError => json_error
                UI.messagebox("Profile #{profile_index + 1}: JSON Parse Error in file:\n#{File.basename(json_file_path)}\n\n#{json_error.message}") # <-- Show JSON error
                next
            rescue => profile_error
                UI.messagebox("Profile #{profile_index + 1}: Error processing file:\n#{File.basename(json_file_path)}\n\n#{profile_error.message}") # <-- Show general error
                next
            end
        end
        
        # Complete operation
        active_model.commit_operation                                         # <-- Commit operation
        
        # Generate completion message
        completion_message = "Finished processing:\n"                        # <-- Start message
        completion_message += "- #{total_profiles_processed} of #{json_file_paths.length} profile#{json_file_paths.length == 1 ? '' : 's'} successfully processed\n" # <-- Profile count
        completion_message += "- #{total_groups_created} total group#{total_groups_created == 1 ? '' : 's'} created\n" # <-- Group count
        completion_message += "- Each profile applied to the same #{edge_chains.length} selected path#{edge_chains.length == 1 ? '' : 's'}" # <-- Summary
        
        UI.messagebox(completion_message)                                    # <-- Show completion
        
    rescue => general_error
        Sketchup.active_model.abort_operation rescue nil                     # <-- Clean up on general error
        UI.messagebox("Error: #{general_error.class}: #{general_error.message}") # <-- Show general error
        raise general_error                                                   # <-- Re-raise for debugging
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | JSON Processing Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Extract First Profile Loop from JSON Schema
    # ------------------------------------------------------------
    def extract_first_profile_loop_from_schema(json_data)
        vertices_array = json_data.dig('vertices', 'items')                   # <-- Extract vertices array
        faces_array = json_data.dig('faces', 'items')                        # <-- Extract faces array
        
        return nil unless vertices_array.is_a?(Array) && 
                         faces_array.is_a?(Array) && 
                         faces_array.any?                                     # <-- Validate input arrays
        
        outer_indices = faces_array[0]['outer']                               # <-- Get outer loop indices
        return nil unless outer_indices.is_a?(Array) && 
                         outer_indices.length >= 3                           # <-- Validate outer loop
        
        # Extract 3D points from vertex indices
        points_3d = outer_indices.map do |vertex_index|
            vertex_data = vertices_array[vertex_index.to_i]                   # <-- Get vertex data by index
            return nil unless vertex_data                                     # <-- Validate vertex exists
            
            [vertex_data['PosX'].to_f, 
             vertex_data['PosY'].to_f, 
             vertex_data['PosZ'].to_f]                                        # <-- Extract XYZ coordinates
        end
        
        # Validate planar constraint (all Z values equal)
        reference_z = points_3d[0][2]                                         # <-- Get reference Z coordinate
        return nil unless points_3d.all? { |_, _, z| (z - reference_z).abs <= 1.0e-6 } # <-- Check planarity
        
        points_3d.map { |x, y, _| [x, y] }                                    # <-- Return 2D profile coordinates
    end
    # ------------------------------------------------------------


    # FUNCTION | Calculate Maximum Dimension of Profile in Millimeters
    # ------------------------------------------------------------
    def profile_max_dimension_mm(loop_coordinates_mm)
        x_coordinates = loop_coordinates_mm.map { |x, _| x }                  # <-- Extract all x coordinates
        y_coordinates = loop_coordinates_mm.map { |_, y| y }                  # <-- Extract all y coordinates
        
        width_mm  = x_coordinates.max - x_coordinates.min                     # <-- Calculate width span
        height_mm = y_coordinates.max - y_coordinates.min                     # <-- Calculate height span
        
        [width_mm.abs, height_mm.abs].max                                     # <-- Return maximum dimension
    end
    # ------------------------------------------------------------


    # FUNCTION | Build Profile Definition Preserving Datum at Origin
    # ------------------------------------------------------------
    def build_profile_definition_preserving_datum(model, loop_coordinates_mm)
        definition = model.definitions.add("VDS_Profile_#{Time.now.to_i}")    # <-- Create unique profile definition
        entities = definition.entities                                        # <-- Get definition entities
        
        # Convert millimeter coordinates to inches for SketchUp
        points_inches = loop_coordinates_mm.map do |x_mm, y_mm|
            Geom::Point3d.new(x_mm / MM_PER_INCH, y_mm / MM_PER_INCH, 0.0)   # <-- Convert to SketchUp units
        end
        
        # Remove duplicate closing point if present
        points_inches.pop if points_inches.length >= 2 && 
                            points_inches.first == points_inches.last         # <-- Remove duplicate end point
        
        profile_face = entities.add_face(points_inches)                       # <-- Create profile face
        return nil unless profile_face && 
                         profile_face.valid? && 
                         profile_face.area > 0.0                             # <-- Validate face creation
        
        profile_face.reverse! if profile_face.normal.z < 0.0                 # <-- Ensure upward-facing normal
        
        definition                                                            # <-- Return profile definition
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Profile Manipulation Functions
# -----------------------------------------------------------------------------

    # DEPRECATED FUNCTION | Legacy Profile X Coordinate Reversal (No Longer Used)
    # ------------------------------------------------------------
    # Note: Handedness control is now achieved via coordinate system rotation, not profile mirroring
    def reverse_profile_x_coordinates(profile_coordinates_mm)
        return profile_coordinates_mm if profile_coordinates_mm.nil? || profile_coordinates_mm.empty? # <-- Skip if invalid
        
        # Find the center X coordinate for mirroring
        x_coordinates = profile_coordinates_mm.map { |x, _| x }              # <-- Extract all x coordinates
        center_x = (x_coordinates.max + x_coordinates.min) / 2.0             # <-- Calculate center point
        
        # Reverse X coordinates around center point
        reversed_coordinates = profile_coordinates_mm.map do |x, y|
            reversed_x = center_x - (x - center_x)                           # <-- Mirror X coordinate around center
            [reversed_x, y]                                                   # <-- Return reversed coordinate pair
        end
        
        reversed_coordinates                                                  # <-- Return reversed profile
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Loop Detection Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Determine if Path Requires Inset Based on Loop Closure
    # ------------------------------------------------------------
    def path_requires_inset?(edge_chains)
        return false if edge_chains.empty?                                    # <-- No inset for empty chains
        
        # Check each edge chain for closure
        edge_chains.each do |edge_set|
            ordered_edges = order_edges_into_path(edge_set)                  # <-- Order edges into path
            next unless ordered_edges && !ordered_edges.empty?               # <-- Skip invalid paths
            
            # Check if this chain forms a closed loop
            if path_is_closed?(ordered_edges)
                return true                                                   # <-- Found at least one closed loop
            end
        end
        
        false                                                                 # <-- No closed loops found
    end
    # ------------------------------------------------------------


    # FUNCTION | Comprehensive Path Closure Analysis
    # ------------------------------------------------------------
    def analyze_path_closure_requirements(edge_chains)
        analysis_result = {
            requires_inset: false,                                           # <-- Overall inset requirement
            total_chains: edge_chains.length,                               # <-- Total number of chains
            closed_chains: 0,                                               # <-- Number of closed chains
            open_chains: 0,                                                 # <-- Number of open chains
            chain_details: []                                               # <-- Details for each chain
        }
        
        edge_chains.each_with_index do |edge_set, chain_index|
            ordered_edges = order_edges_into_path(edge_set)                  # <-- Order edges into path
            
            if ordered_edges && !ordered_edges.empty?
                is_closed = path_is_closed?(ordered_edges)                   # <-- Check closure status
                
                chain_detail = {
                    index: chain_index,                                      # <-- Chain index
                    is_closed: is_closed,                                   # <-- Closure status
                    edge_count: edge_set.length                             # <-- Number of edges
                }
                
                analysis_result[:chain_details] << chain_detail              # <-- Add chain details
                
                if is_closed
                    analysis_result[:closed_chains] += 1                    # <-- Increment closed count
                    analysis_result[:requires_inset] = true                 # <-- Set inset requirement
                else
                    analysis_result[:open_chains] += 1                      # <-- Increment open count
                end
            end
        end
        
        analysis_result                                                       # <-- Return comprehensive analysis
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Global Math Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Calculate Orthonormal X and Y Axes from Z Vector
    # ------------------------------------------------------------
    def robust_xy_from_z(z_axis)
        # Choose helper vector that's not parallel to z_axis
        helper_vector = z_axis.parallel?(Geom::Vector3d.new(0, 0, 1)) ? 
                       Geom::Vector3d.new(1, 0, 0) : 
                       Geom::Vector3d.new(0, 0, 1)                            # <-- Select non-parallel helper
        
        x_axis = helper_vector.cross(z_axis)                                  # <-- Calculate initial x-axis
        
        # Fallback if cross product is zero
        if x_axis.length == 0.0
            helper_vector = Geom::Vector3d.new(0, 1, 0)                       # <-- Use Y-axis as fallback helper
            x_axis = helper_vector.cross(z_axis)                              # <-- Recalculate x-axis
        end
        
        x_axis.normalize!                                                      # <-- Normalize x-axis
        y_axis = z_axis.cross(x_axis)                                         # <-- Calculate y-axis from z and x
        y_axis.normalize!                                                      # <-- Normalize y-axis
        
        [x_axis, y_axis]                                                       # <-- Return orthonormal basis
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Processing Functions
# -----------------------------------------------------------------------------

    # SUB REGION | Edge Chain Building and Connectivity
    # ========================================================

    # FUNCTION | Build Connected Chains from Selected Edges
    # ------------------------------------------------------------
    def build_connected_chains(selected_edges)
        unvisited_edges = selected_edges.dup                                 # <-- Create working copy of edges
        connected_chains = []                                                 # <-- Initialize chains collection
        
        until unvisited_edges.empty?
            seed_edge = unvisited_edges.shift                                 # <-- Take first unvisited edge
            current_component = [seed_edge]                                   # <-- Start new component
            processing_queue = [seed_edge]                                    # <-- Initialize processing queue
            
            while (current_edge = processing_queue.shift)
                current_edge.vertices.each do |vertex|                       # <-- Process each vertex
                    vertex.edges.each do |neighbor_edge|                     # <-- Check connected edges
                        next unless unvisited_edges.include?(neighbor_edge)  # <-- Skip if already processed
                        
                        if shares_vertex_with_set?(neighbor_edge, current_component)
                            current_component << neighbor_edge                # <-- Add to current component
                            processing_queue << neighbor_edge                 # <-- Queue for processing
                            unvisited_edges.delete(neighbor_edge)            # <-- Mark as visited
              end
            end
          end
        end

            connected_chains << current_component.uniq                        # <-- Add unique component to chains
        end
        
        connected_chains                                                      # <-- Return all connected chains
    end
    # ------------------------------------------------------------

    # ========================================================

    # SUB REGION | Path Ordering and Validation
    # ========================================================

    # FUNCTION | Order Edge Set into Single Continuous Path
    # ------------------------------------------------------------
    def order_edges_into_path(edge_set)
        adjacency_map = Hash.new { |hash, key| hash[key] = [] }              # <-- Initialize adjacency mapping
        edge_set.each { |edge| edge.vertices.each { |vertex| adjacency_map[vertex] << edge } } # <-- Build adjacency
        
        endpoint_vertices = adjacency_map.keys.select { |vertex| adjacency_map[vertex].length == 1 } # <-- Find endpoints
        
        # Determine starting vertex based on path type
        starting_vertex = 
            if endpoint_vertices.length == 2                                 # <-- Open path case
                endpoint_vertices.first                                      # <-- Start from first endpoint
            elsif endpoint_vertices.empty? && adjacency_map.keys.all? { |vertex| adjacency_map[vertex].length == 2 }
                # Closed path case - choose deterministic start
                adjacency_map.keys.min_by { |vertex| [safe_pid(vertex), vertex.position.x, vertex.position.y, vertex.position.z] } # <-- Deterministic start
            else
                return nil                                                    # <-- Invalid path topology
            end
        
        ordered_edges = []                                                    # <-- Initialize ordered edge list
        visited_edges = {}                                                    # <-- Track visited edges
        
        current_vertex = starting_vertex                                      # <-- Set current position
        current_edge = adjacency_map[current_vertex].first                   # <-- Get first edge
        return nil unless current_edge                                        # <-- Validate starting edge
        
        # Traverse path following connectivity
        while current_edge
            ordered_edges << current_edge                                     # <-- Add edge to ordered list
            visited_edges[current_edge] = true                               # <-- Mark edge as visited
            
            next_vertex = (current_edge.start == current_vertex) ? 
                         current_edge.end : current_edge.start               # <-- Find next vertex
            
            next_edge = adjacency_map[next_vertex].find { |edge| !visited_edges[edge] } # <-- Find unvisited edge
            break unless next_edge                                            # <-- Exit if no more edges
            
            current_vertex = next_vertex                                      # <-- Move to next vertex
            current_edge = next_edge                                          # <-- Move to next edge
        end
        
        # Validate complete path coverage
        return nil unless ordered_edges.uniq.length == edge_set.uniq.length  # <-- Ensure all edges included
        
        ordered_edges                                                         # <-- Return ordered edge sequence
    end
    # ------------------------------------------------------------


    # FUNCTION | Check if Path Forms Closed Loop
    # ------------------------------------------------------------
    def path_is_closed?(ordered_edges)
        return false if ordered_edges.empty?                                  # <-- Handle empty path
        
        first_edge_start = ordered_edges.first.start.position                # <-- First edge start point
        first_edge_end = ordered_edges.first.end.position                    # <-- First edge end point
        last_edge_start = ordered_edges.last.start.position                  # <-- Last edge start point
        last_edge_end = ordered_edges.last.end.position                      # <-- Last edge end point
        
        # Check if any combination connects first and last edges
        near_equal?(first_edge_start, last_edge_start, GEOMETRIC_TOLERANCE) ||
        near_equal?(first_edge_start, last_edge_end, GEOMETRIC_TOLERANCE) ||
        near_equal?(first_edge_end, last_edge_start, GEOMETRIC_TOLERANCE) ||
        near_equal?(first_edge_end, last_edge_end, GEOMETRIC_TOLERANCE)      # <-- Test all connection possibilities
    end
    # ------------------------------------------------------------


    # FUNCTION | Detect Branching Vertices in Edge Set
    # ------------------------------------------------------------
    def branching_vertices_in_set(edge_set)
        vertex_degree = Hash.new(0)                                          # <-- Initialize degree counter
        edge_set.each { |edge| edge.vertices.each { |vertex| vertex_degree[vertex] += 1 } } # <-- Count connections
        
        vertex_degree.select { |_, degree| degree > 2 }.keys                # <-- Return vertices with degree > 2
    end
    # ------------------------------------------------------------

    # ========================================================

    # SUB REGION | Point Processing and Path Modification
    # ========================================================

    # FUNCTION | Extract Points from Ordered Edge Sequence
    # ------------------------------------------------------------
    def points_from_ordered_edges(ordered_edges)
        extracted_points = []                                                 # <-- Initialize points collection
        
        # Determine direction from first two edges
        first_edge_start = ordered_edges.first.start.position               # <-- First edge start
        first_edge_end = ordered_edges.first.end.position                   # <-- First edge end
        
        if ordered_edges.length >= 2
            second_edge = ordered_edges[1]                                   # <-- Get second edge
            # Check which direction maintains continuity
            forward_direction = near_equal?(second_edge.start.position, first_edge_end, GEOMETRIC_TOLERANCE) ||
                               near_equal?(second_edge.end.position, first_edge_end, GEOMETRIC_TOLERANCE) # <-- Test forward
            
            extracted_points << (forward_direction ? first_edge_start : first_edge_end) # <-- Add start point
            extracted_points << (forward_direction ? first_edge_end : first_edge_start) # <-- Add second point
        else
            extracted_points << first_edge_start << first_edge_end           # <-- Simple two-point path
        end
        
        # Process remaining edges maintaining continuity
        ordered_edges[1..-1].each do |edge|
            tail_point = extracted_points.last                               # <-- Get current path end
            edge_start = edge.start.position                                 # <-- Edge start position
            edge_end = edge.end.position                                     # <-- Edge end position
            
            if near_equal?(edge_start, tail_point, GEOMETRIC_TOLERANCE)
                extracted_points << edge_end                                  # <-- Add end point
            elsif near_equal?(edge_end, tail_point, GEOMETRIC_TOLERANCE)
                extracted_points << edge_start                                # <-- Add start point
            else
                # Fallback: choose closer point
                if tail_point.distance(edge_start) <= tail_point.distance(edge_end)
                    extracted_points << edge_start << edge_end               # <-- Add both points
                else
                    extracted_points << edge_end << edge_start               # <-- Add both points reversed
          end
        end
      end

        extracted_points                                                      # <-- Return point sequence
    end
    # ------------------------------------------------------------


    # FUNCTION | Apply Inset to Path Start with Reseeding
    # ------------------------------------------------------------
    def reseed_points_with_inset(original_points, is_closed_path, inset_distance_inches)
        return original_points if original_points.length < 2 || inset_distance_inches <= 0.0 # <-- Skip if invalid
        
        # Calculate and clamp inset to prevent over-inset
        first_segment_length = original_points[0].distance(original_points[1]) # <-- Get first segment length
        return original_points if first_segment_length <= GEOMETRIC_TOLERANCE # <-- Skip if degenerate
        
        clamped_inset = [[inset_distance_inches, first_segment_length * 0.49].min, 0.0].max # <-- Clamp inset safely
        
        # Calculate new start point
        direction_vector = original_points[1] - original_points[0]            # <-- Get direction vector
        direction_vector.length = clamped_inset                              # <-- Set inset distance
        new_start_point = original_points[0].offset(direction_vector)        # <-- Calculate new start
        
        if is_closed_path
            # Closed path: new_start → p1 → ... → pN → p0 → new_start
            reseeded_points = [new_start_point]                              # <-- Start with new start
            reseeded_points.concat(original_points[1..-1])                   # <-- Add middle points
            reseeded_points << original_points[0]                            # <-- Add original start
            reseeded_points << new_start_point                               # <-- Close loop
            reseeded_points                                                   # <-- Return closed path
        else
            # Open path: shift start forward by inset
            reseeded_points = [new_start_point]                              # <-- Start with new start
            reseeded_points.concat(original_points[1..-1])                   # <-- Add remaining points
            reseeded_points                                                   # <-- Return open path
      end
    end
    # ------------------------------------------------------------


    # FUNCTION | Sanitize Points by Removing Consecutive Duplicates
    # ------------------------------------------------------------
    def sanitize_points(point_array, tolerance)
        return point_array if point_array.length < 2                         # <-- Skip if insufficient points
        
        sanitized_points = [point_array.first]                               # <-- Start with first point
        
        point_array.each_with_index do |point, index|
            next if index == 0                                                # <-- Skip first point (already added)
            sanitized_points << point unless near_equal?(point, sanitized_points.last, tolerance) # <-- Add if not duplicate
        end
        
        sanitized_points                                                      # <-- Return cleaned points
    end
    # ------------------------------------------------------------

    # ========================================================

    # SUB REGION | Single Profile Processing Functions
    # ========================================================

    # FUNCTION | Process Single Profile on All Edge Chains
    # ------------------------------------------------------------
    def process_single_profile_on_edges(active_model, model_entities, edge_chains, profile_definition, profile_name, inset_distance_inches, reverse_profile, should_apply_inset)
        groups_created = 0                                                   # <-- Track groups created for this profile
        
        # Configure group naming for this profile
        group_name_prefix = reverse_profile ? 
            "VDS_FollowMe_Rev_#{profile_name}_Path_" : 
            "VDS_FollowMe_#{profile_name}_Path_"                             # <-- Set group name prefix
        
        # Process each connected chain for this profile
        edge_chains.each_with_index do |edge_set, chain_index|
            ordered_edges = order_edges_into_path(edge_set)                  # <-- Order edges into path
            unless ordered_edges && !ordered_edges.empty?
                next                                                         # <-- Skip invalid paths silently
            end
            
            # Validate path topology (no branching)
            branching_vertices = branching_vertices_in_set(edge_set)         # <-- Check for branches
            unless branching_vertices.empty?
                next                                                         # <-- Skip branching paths silently
            end
            
            # Process path geometry with conditional inset
            is_closed_path = path_is_closed?(ordered_edges)                  # <-- Determine if closed
            base_points = points_from_ordered_edges(ordered_edges)           # <-- Extract points
            
            # Apply inset only if path analysis indicates it's needed (closed loops)
            inset_points = should_apply_inset ? 
                reseed_points_with_inset(base_points, is_closed_path, inset_distance_inches) : 
                base_points                                                   # <-- Conditionally apply inset
            
            # Clean and validate points
            sanitized_points = sanitize_points(inset_points, GEOMETRIC_TOLERANCE) # <-- Remove duplicates
            if sanitized_points.length < 2
                next                                                         # <-- Skip short paths silently
            end
            
            # Create group for this profile-path combination
            path_group = model_entities.add_group                            # <-- Create containing group
            path_group.name = "#{group_name_prefix}#{format('%03d', chain_index + 1)}" # <-- Set descriptive name
            group_entities = path_group.entities                             # <-- Get group entities
            
            # Create path edges in group
            path_edges = add_path_edges_from_points(group_entities, sanitized_points, is_closed_path) # <-- Create path
            if path_edges.nil? || path_edges.empty?
                path_group.erase!                                            # <-- Clean up group
                next
            end
            
            # Establish local coordinate frame at inset start
            start_point = sanitized_points.first                            # <-- Get start point
            z_axis_direction = sanitized_points[1] - sanitized_points[0]     # <-- Calculate direction
            
            if z_axis_direction.length <= GEOMETRIC_TOLERANCE
                path_group.erase!                                            # <-- Clean up group
                next
            end
            
            z_axis_direction.normalize!                                      # <-- Normalize direction
            x_axis, y_axis = robust_xy_from_z(z_axis_direction)             # <-- Calculate orthonormal basis
            
            # Apply coordinate system rotation for handedness control
            if reverse_profile
                # Flip to opposite side of path by reversing X-axis only
                x_axis = x_axis.reverse                                      # <-- Reverse X-axis to flip to opposite side
                # Note: Y-axis remains unchanged to keep profile upright
            end
            transformation_axes = Geom::Transformation.axes(start_point, x_axis, y_axis, z_axis_direction) # <-- Create transformation
            
            # Place profile instance at start location
            profile_instance = group_entities.add_instance(profile_definition, transformation_axes) # <-- Place profile
            
            # Explode instance to get driver face
            faces_before_explode = group_entities.grep(Sketchup::Face)       # <-- Count faces before
            profile_instance.explode                                         # <-- Explode instance
            new_faces = group_entities.grep(Sketchup::Face) - faces_before_explode # <-- Find new faces
            profile_face = new_faces.first || group_entities.grep(Sketchup::Face).first # <-- Get profile face
            
            unless profile_face && profile_face.valid? && profile_face.area > 0.0
                path_group.erase!                                            # <-- Clean up group
                next
            end
            
            # Ensure profile face normal aligns with path direction
            profile_face.reverse! if profile_face.normal.dot(z_axis_direction) < 0.0 # <-- Correct orientation
            
            # Apply temporary scaling to prevent tiny-face artifacts
            scale_up_transform = Geom::Transformation.scaling(start_point, DEFAULT_SCALE_FACTOR) # <-- Scale up
            scale_down_transform = Geom::Transformation.scaling(start_point, 1.0 / DEFAULT_SCALE_FACTOR) # <-- Scale down
            path_group.transform!(scale_up_transform)                        # <-- Apply scale up
            
            # Execute Follow Me operation
            follow_me_success = profile_face.followme(path_edges)            # <-- Perform Follow Me
            
            path_group.transform!(scale_down_transform)                      # <-- Restore original scale
            
            unless follow_me_success
                path_group.erase!                                            # <-- Clean up group
                next
            end
            
            # Clean up driver face if it remains
            profile_face.erase! if profile_face.valid?                      # <-- Remove driver face
            
            # Hide driver path edges
            hide_edges(path_edges)                                           # <-- Hide path edges
            
            # Apply smoothing and softening
            apply_smooth_and_soften(path_group, DEFAULT_SMOOTH_THRESHOLD)    # <-- Apply surface treatment
            
            groups_created += 1                                              # <-- Increment group counter
        end
        
        groups_created                                                       # <-- Return number of groups created
    end
    # ------------------------------------------------------------

    # ========================================================

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | 3D Generation Functions
# -----------------------------------------------------------------------------

    # SUB REGION | Path Creation and Geometry Building
    # ========================================================

    # FUNCTION | Create Path Edges from Point Array
    # ------------------------------------------------------------
    def add_path_edges_from_points(group_entities, point_array, is_closed_path)
        working_points = point_array.dup                                     # <-- Create working copy
        
        # Handle path closure for closed paths
        if is_closed_path
            working_points << working_points.first unless near_equal?(working_points.first, 
                                                                      working_points.last, 
                                                                      GEOMETRIC_TOLERANCE) # <-- Ensure closure
        else
            # Clean trailing duplicates for open paths
            while working_points.length >= 2 && 
                  near_equal?(working_points[-1], working_points[-2], GEOMETRIC_TOLERANCE)
                working_points.pop                                            # <-- Remove trailing duplicates
            end
        end
        
        # Validate minimum point requirements
        minimum_points = is_closed_path ? 3 : 2                              # <-- Set minimum based on path type
        return [] if working_points.length < minimum_points                  # <-- Return empty if insufficient
        
        created_edges = group_entities.add_edges(*working_points)            # <-- Create edge geometry
        return [] if created_edges.nil?                                      # <-- Handle creation failure
        
        created_edges.grep(Sketchup::Edge)                                   # <-- Return only edge entities
    end
    # ------------------------------------------------------------

    # ========================================================

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Finishing Operations Functions
# -----------------------------------------------------------------------------

    # FUNCTION | Hide Driver Path Edges After Follow Me Operation
    # ------------------------------------------------------------
    def hide_edges(edge_array)
        edge_array.each do |edge|
            next unless edge.valid?                                          # <-- Skip invalid edges
            
            edge.hidden = true                                                # <-- Hide edge from view
            edge.soft = true                                                  # <-- Make edge soft
            edge.smooth = true                                                # <-- Make edge smooth
      end
    end
    # ------------------------------------------------------------


    # FUNCTION | Apply Smooth and Soften by Angle Threshold
    # ------------------------------------------------------------
    def apply_smooth_and_soften(target_group, degree_threshold = DEFAULT_SMOOTH_THRESHOLD)
        group_entities = target_group.entities                               # <-- Get group entities
        angle_threshold_radians = degree_threshold.degrees                   # <-- Convert to radians
        angle_epsilon = 1.0e-6                                               # <-- Small angle tolerance
        
        group_entities.grep(Sketchup::Edge).each do |edge|
            connected_faces = edge.faces                                      # <-- Get faces connected to edge
            
            if connected_faces.length == 2                                   # <-- Process shared edges
                angle_between = connected_faces[0].normal.angle_between(connected_faces[1].normal) # <-- Calculate angle
                
                if angle_between > angle_epsilon && angle_between < angle_threshold_radians
                    edge.smooth = true                                        # <-- Smooth edge
                    edge.soft = true                                          # <-- Soften edge
                    edge.hidden = true                                        # <-- Hide edge
                else
                    edge.smooth = false                                       # <-- Keep edge sharp
                    edge.soft = false                                         # <-- Keep edge hard
                    edge.hidden = false                                       # <-- Show edge
          end
        else
                # Boundary edges remain visible and sharp
                edge.smooth = false                                           # <-- Keep boundary sharp
                edge.soft = false                                             # <-- Keep boundary hard
                edge.hidden = false                                           # <-- Show boundary
            end
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Event Handling & Callbacks / API
# -----------------------------------------------------------------------------

    # API FUNCTION | Register Tool in SketchUp Extensions Menu
    # ------------------------------------------------------------
    def self.register_menu_item
        # Register normal profile function (individual file selection)
        unless defined?($vds_json_followme_normal_menu_added) && $vds_json_followme_normal_menu_added
            UI.menu('Extensions').add_item('VDS - JSON Follow Me Along Path (Multi-Profile, Inset Start, Smooth 20°)') do
                ValeDesignSuite::PathToContinuousProfileTool.run             # <-- Execute main function
            end
            $vds_json_followme_normal_menu_added = true                      # <-- Mark normal menu as added
        end
        
        # Register reversed profile function (individual file selection)
        unless defined?($vds_json_followme_reverse_menu_added) && $vds_json_followme_reverse_menu_added
            UI.menu('Extensions').add_item('VDS - JSON Follow Me Along Path (Multi-Profile, Inset Start, Smooth 20°) - Reverse Profile') do
                ValeDesignSuite::PathToContinuousProfileTool.run_with_reversed_profile # <-- Execute reversed profile function
            end
            $vds_json_followme_reverse_menu_added = true                     # <-- Mark reverse menu as added
        end
        
        # Register directory selection function (normal profile)
        unless defined?($vds_json_followme_dir_menu_added) && $vds_json_followme_dir_menu_added
            UI.menu('Extensions').add_item('VDS - JSON Follow Me Along Path [Directory] (Multi-Profile, Inset Start, Smooth 20°)') do
                ValeDesignSuite::PathToContinuousProfileTool.run_from_directory  # <-- Execute directory selection function
            end
            $vds_json_followme_dir_menu_added = true                         # <-- Mark directory menu as added
        end
        
        # Register directory selection function (reversed profile)
        unless defined?($vds_json_followme_dir_reverse_menu_added) && $vds_json_followme_dir_reverse_menu_added
            UI.menu('Extensions').add_item('VDS - JSON Follow Me Along Path [Directory] (Multi-Profile, Inset Start, Smooth 20°) - Reverse Profile') do
                ValeDesignSuite::PathToContinuousProfileTool.run_from_directory_with_reversed_profile  # <-- Execute directory selection with reversed profile
            end
            $vds_json_followme_dir_reverse_menu_added = true                 # <-- Mark directory reverse menu as added
        end
      end
    # ------------------------------------------------------------


    # API FUNCTION | Force Reload Menu Items (Development Helper)
    # ------------------------------------------------------------
    def self.force_reload_menu_items
        # Clear existing menu flags
        $vds_json_followme_normal_menu_added = false                         # <-- Reset normal menu flag
        $vds_json_followme_reverse_menu_added = false                        # <-- Reset reverse menu flag
        $vds_json_followme_dir_menu_added = false                            # <-- Reset directory menu flag
        $vds_json_followme_dir_reverse_menu_added = false                    # <-- Reset directory reverse menu flag
        
        # Re-register menu items
        register_menu_item                                                    # <-- Register all menu items
        
        UI.messagebox('VDS JSON Follow Me menu items reloaded successfully!') # <-- Confirm reload
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

  end
end

# Force reload menu items to ensure both buttons appear
ValeDesignSuite::PathToContinuousProfileTool.force_reload_menu_items

# Convenience alias for console execution
ValeDesignSuite::PathToContinuousProfileTool.run
