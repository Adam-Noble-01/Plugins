# =============================================================================
# NA - ORTHO MIRROR TOOL - 2D CAMERA-BASED MIRROR
# =============================================================================
#
# FILE      : Na__OrthoMirrorTool__MirrorBasedOn2dCamera__Main__.rb
# NAMESPACE : Na__OrthoMirrorTool
# MODULE    : Na__OrthoMirrorTool
# AUTHOR    : Adam Noble - Noble Architecture
# PURPOSE   : 2D Mirror Tool for Orthographic Views in SketchUp
# CREATED   : 2025
#
# DESCRIPTION:
# - Creates a mirror transformation based on the current 2D camera view direction.
# - User clicks start and end points to define the mirror axis line.
# - Mirror plane is perpendicular to the screen (vertical to view plane).
# - Provides visual feedback: blue preview line, red endpoint squares, green midpoint circles.
# - Designed for efficient 2D drawing workflows in parallel projection views.
# - Requires objects to be selected before activating the tool.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 12-Dec-2025 - Version 1.0.0
# - Initial Release
# - Two-click mirror plane definition with visual feedback
# - Ortho view detection (Top, Front, Right, etc.)
# - Copy-and-mirror workflow preserving original selection
#
# 12-Dec-2025 - Version 1.1.0
# - Added arrow key axis locking (standard SketchUp behavior)
# - Right arrow = Red axis (X), Left arrow = Green axis (Y), Up arrow = Blue axis (Z)
# - Down arrow or same key = Toggle unlock
# - Preview line changes color to match locked axis
# - Status bar shows current lock state
#
# =============================================================================

module Na__OrthoMirrorTool

# -----------------------------------------------------------------------------
# REGION | Embedded JSON Method & Function Index
# -----------------------------------------------------------------------------

    # EMBEDDED JSON | Script Method & Function Index
    # ------------------------------------------------------------
    SCRIPT_METHOD_INDEX = {
        "script_info" => {
            "name" => "Na__OrthoMirrorTool",
            "version" => "1.1.0",
            "purpose" => "2D Mirror Tool for Orthographic Views with Axis Locking"
        },
        "constants" => {
            "visual" => ["PREVIEW_LINE_COLOR", "PREVIEW_LINE_WIDTH", "ENDPOINT_COLOR", "MIDPOINT_COLOR", "INDICATOR_SIZE"],
            "axis_colors" => ["AXIS_COLOR_X", "AXIS_COLOR_Y", "AXIS_COLOR_Z"],
            "state" => ["STATE_IDLE", "STATE_FIRST_POINT_SET"],
            "lock_state" => ["LOCK_NONE", "LOCK_X", "LOCK_Y", "LOCK_Z"]
        },
        "helper_functions" => {
            "view_detection" => ["get_camera_view_direction", "is_parallel_projection?"],
            "point_detection" => ["detect_point_type", "calculate_edge_midpoint", "is_near_midpoint?"],
            "geometry" => ["calculate_mirror_plane_normal"],
            "axis_locking" => ["get_axis_vector", "get_axis_color", "constrain_point_to_axis"]
        },
        "tool_class" => {
            "lifecycle" => ["initialize", "activate", "deactivate", "resume"],
            "input" => ["onMouseMove", "onLButtonDown", "onCancel", "onKeyDown"],
            "drawing" => ["draw", "draw_preview_line", "draw_endpoint_indicator", "draw_midpoint_indicator"],
            "axis_locking" => ["handle_axis_lock_key", "toggle_axis_lock", "get_constrained_end_point"]
        },
        "core_functions" => {
            "mirror" => ["execute_mirror_transformation", "build_mirror_transform"]
        },
        "entry_points" => {
            "public" => ["Na__OrthoMirrorTool__Run"],
            "menu" => ["install_menu_and_commands", "activate_for_model"]
        }
    }.freeze
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Visual Feedback Settings
    # ------------------------------------------------------------
    PREVIEW_LINE_COLOR   = Sketchup::Color.new(0, 120, 255)      # <-- Blue preview line color
    PREVIEW_LINE_WIDTH   = 3                                      # <-- Preview line width in pixels
    ENDPOINT_COLOR       = Sketchup::Color.new(255, 0, 0)         # <-- Red color for endpoint indicators
    MIDPOINT_COLOR       = Sketchup::Color.new(0, 200, 0)         # <-- Green color for midpoint indicators
    INDICATOR_SIZE       = 8                                      # <-- Size of point indicators in pixels
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Tool State Values
    # ------------------------------------------------------------
    STATE_IDLE            = 0                                     # <-- Waiting for first point
    STATE_FIRST_POINT_SET = 1                                     # <-- First point placed, waiting for second
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Axis Lock States
    # ------------------------------------------------------------
    LOCK_NONE             = :none                                 # <-- No axis lock active
    LOCK_X                = :x                                    # <-- Locked to Red axis (X)
    LOCK_Y                = :y                                    # <-- Locked to Green axis (Y)
    LOCK_Z                = :z                                    # <-- Locked to Blue axis (Z)
    # ------------------------------------------------------------

    # MODULE CONSTANTS | Axis Colors (Standard SketchUp Colors)
    # ------------------------------------------------------------
    AXIS_COLOR_X          = Sketchup::Color.new(255, 0, 0)        # <-- Red for X axis
    AXIS_COLOR_Y          = Sketchup::Color.new(0, 128, 0)        # <-- Green for Y axis
    AXIS_COLOR_Z          = Sketchup::Color.new(0, 0, 255)        # <-- Blue for Z axis
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Helper Functions - Axis Locking
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Get Axis Vector for Lock State
    # ------------------------------------------------------------
    def self.get_axis_vector(lock_state)
        case lock_state
        when LOCK_X then X_AXIS                                   # <-- Return X axis vector
        when LOCK_Y then Y_AXIS                                   # <-- Return Y axis vector
        when LOCK_Z then Z_AXIS                                   # <-- Return Z axis vector
        else nil                                                  # <-- No lock, return nil
        end
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Get Axis Color for Lock State
    # ------------------------------------------------------------
    def self.get_axis_color(lock_state)
        case lock_state
        when LOCK_X then AXIS_COLOR_X                             # <-- Return red for X
        when LOCK_Y then AXIS_COLOR_Y                             # <-- Return green for Y
        when LOCK_Z then AXIS_COLOR_Z                             # <-- Return blue for Z
        else PREVIEW_LINE_COLOR                                   # <-- Default blue preview color
        end
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Get Axis Name for Lock State
    # ------------------------------------------------------------
    def self.get_axis_name(lock_state)
        case lock_state
        when LOCK_X then "Red (X)"                                # <-- Red axis name
        when LOCK_Y then "Green (Y)"                              # <-- Green axis name
        when LOCK_Z then "Blue (Z)"                               # <-- Blue axis name
        else "None"                                               # <-- No lock
        end
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Constrain Point to Axis from Origin Point
    # ------------------------------------------------------------
    # Projects the target point onto the line from origin along axis_vector
    # Returns the constrained point
    # ------------------------------------------------------------
    def self.constrain_point_to_axis(origin, target, axis_vector)
        return target unless axis_vector                          # <-- Return original if no axis
        
        # Vector from origin to target
        direction = target - origin                               # <-- Get direction vector
        
        # Project direction onto axis vector
        # projection = (direction · axis) * axis / |axis|²
        dot_product = direction.dot(axis_vector)                  # <-- Calculate dot product
        
        # Constrained point = origin + projection along axis
        constrained = origin.offset(axis_vector, dot_product)     # <-- Offset along axis
        
        return constrained
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Helper Functions - View Detection
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Check if Camera is in Parallel Projection
    # ------------------------------------------------------------
    def self.is_parallel_projection?(view)
        !view.camera.perspective?                                 # <-- Returns true if parallel (ortho) mode
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Get Camera View Direction Vector
    # ------------------------------------------------------------
    # Returns the direction the camera is looking (from eye to target)
    # This is the opposite of the view plane normal
    # ------------------------------------------------------------
    def self.get_camera_view_direction(view)
        camera = view.camera                                      # <-- Get camera object
        direction = camera.target - camera.eye                    # <-- Calculate view direction
        direction.normalize                                       # <-- Return normalized vector
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Identify Named Ortho View
    # ------------------------------------------------------------
    # Returns symbol: :top, :bottom, :front, :back, :left, :right, or :custom
    # ------------------------------------------------------------
    def self.identify_ortho_view(view)
        return :perspective if view.camera.perspective?           # <-- Not ortho if perspective mode
        
        direction = get_camera_view_direction(view)               # <-- Get view direction
        
        # Check against primary axes with tolerance
        if direction.parallel?(Z_AXIS)                            # <-- Looking along Z axis
            direction.z > 0 ? :bottom : :top                      # <-- +Z = bottom view, -Z = top view
        elsif direction.parallel?(Y_AXIS)                         # <-- Looking along Y axis
            direction.y > 0 ? :front : :back                      # <-- +Y = front view, -Y = back view
        elsif direction.parallel?(X_AXIS)                         # <-- Looking along X axis
            direction.x > 0 ? :left : :right                      # <-- +X = left view, -X = right view
        else
            :custom                                               # <-- Non-axis-aligned ortho view
        end
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Helper Functions - Point Type Detection
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Calculate Edge Midpoint
    # ------------------------------------------------------------
    def self.calculate_edge_midpoint(edge)
        start_pt = edge.start.position                            # <-- Get start vertex position
        end_pt   = edge.end.position                              # <-- Get end vertex position
        Geom::Point3d.linear_combination(0.5, start_pt, 0.5, end_pt)  # <-- Return midpoint
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Check if Point is Near Edge Midpoint
    # ------------------------------------------------------------
    def self.is_near_midpoint?(point, edge, tolerance = 0.001)
        midpoint = calculate_edge_midpoint(edge)                  # <-- Calculate edge midpoint
        point.distance(midpoint) < tolerance                      # <-- Return true if within tolerance
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Detect Point Type from InputPoint
    # ------------------------------------------------------------
    # Returns: :vertex, :midpoint, :edge, :face, or :free
    # ------------------------------------------------------------
    def self.detect_point_type(ip)
        return :free unless ip.valid?                             # <-- Return free if no valid snap
        
        # Check for vertex snap first (highest priority)
        if ip.vertex                                              # <-- InputPoint snapped to vertex
            return :vertex
        end
        
        # Check for edge snap and determine if midpoint
        if ip.edge                                                # <-- InputPoint snapped to edge
            if is_near_midpoint?(ip.position, ip.edge)            # <-- Check if near midpoint
                return :midpoint
            else
                return :edge
            end
        end
        
        # Check for face snap
        if ip.face                                                # <-- InputPoint snapped to face
            return :face
        end
        
        :free                                                     # <-- No specific snap type
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Helper Functions - Mirror Geometry
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Calculate Mirror Plane Normal
    # ------------------------------------------------------------
    # The mirror plane contains the mirror line and is perpendicular to the view
    # Normal = cross product of mirror_line and view_direction
    # ------------------------------------------------------------
    def self.calculate_mirror_plane_normal(start_point, end_point, view)
        mirror_line = end_point - start_point                     # <-- Vector along mirror axis
        return nil if mirror_line.length < 0.001                  # <-- Handle degenerate case
        
        view_direction = get_camera_view_direction(view)          # <-- Get camera view direction
        plane_normal = mirror_line.cross(view_direction)          # <-- Cross product gives plane normal
        
        return nil if plane_normal.length < 0.001                 # <-- Handle parallel vectors
        plane_normal.normalize                                    # <-- Return normalized normal
    end
    # ------------------------------------------------------------


    # HELPER FUNCTION | Build Mirror Transformation Matrix
    # ------------------------------------------------------------
    # Creates a reflection transformation about an arbitrary plane
    # The plane passes through midpoint with the given normal
    # ------------------------------------------------------------
    def self.build_mirror_transform(midpoint, plane_normal)
        # Reflection formula: P' = P - 2(P·N - d)N
        # Where N is plane normal, d is distance from origin to plane along normal
        # This can be expressed as a 4x4 transformation matrix
        
        nx = plane_normal.x                                       # <-- Normal X component
        ny = plane_normal.y                                       # <-- Normal Y component
        nz = plane_normal.z                                       # <-- Normal Z component
        
        # Distance from origin to plane along normal
        d = midpoint.x * nx + midpoint.y * ny + midpoint.z * nz   # <-- Plane constant d
        
        # Build reflection matrix components
        # Reflection matrix: I - 2*N*N^T (translated to pass through midpoint)
        m11 = 1.0 - 2.0 * nx * nx                                 # <-- Matrix element [0,0]
        m12 = -2.0 * nx * ny                                      # <-- Matrix element [0,1]
        m13 = -2.0 * nx * nz                                      # <-- Matrix element [0,2]
        m14 = 2.0 * nx * d                                        # <-- Matrix element [0,3] (translation)
        
        m21 = -2.0 * ny * nx                                      # <-- Matrix element [1,0]
        m22 = 1.0 - 2.0 * ny * ny                                 # <-- Matrix element [1,1]
        m23 = -2.0 * ny * nz                                      # <-- Matrix element [1,2]
        m24 = 2.0 * ny * d                                        # <-- Matrix element [1,3] (translation)
        
        m31 = -2.0 * nz * nx                                      # <-- Matrix element [2,0]
        m32 = -2.0 * nz * ny                                      # <-- Matrix element [2,1]
        m33 = 1.0 - 2.0 * nz * nz                                 # <-- Matrix element [2,2]
        m34 = 2.0 * nz * d                                        # <-- Matrix element [2,3] (translation)
        
        # Create transformation from 4x4 matrix array (column-major order)
        # SketchUp uses: [m11, m21, m31, 0, m12, m22, m32, 0, m13, m23, m33, 0, m14, m24, m34, 1]
        matrix_array = [
            m11, m21, m31, 0.0,                                   # <-- Column 0
            m12, m22, m32, 0.0,                                   # <-- Column 1
            m13, m23, m33, 0.0,                                   # <-- Column 2
            m14, m24, m34, 1.0                                    # <-- Column 3 (translation + homogeneous)
        ]
        
        Geom::Transformation.new(matrix_array)                    # <-- Return transformation object
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Tool Class
# -----------------------------------------------------------------------------

    # CLASS | OrthoMirrorTool - Interactive Mirror Placement Tool
    # ------------------------------------------------------------
    class OrthoMirrorTool

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip             = Sketchup::InputPoint.new            # <-- Create input point for snapping
            @cursor_pos     = nil                                 # <-- Current cursor world position
            @point_type     = :free                               # <-- Current snap point type
            @state          = STATE_IDLE                          # <-- Tool state machine
            @start_point    = nil                                 # <-- First clicked point
            @end_point      = nil                                 # <-- Second clicked point (preview)
            @selection_copy = nil                                 # <-- Stored selection entities
            @locked_axis    = LOCK_NONE                           # <-- Current axis lock state
        end
        # ------------------------------------------------------------


        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            model = Sketchup.active_model                         # <-- Get active model
            view  = model.active_view                             # <-- Get active view
            
            puts "\n"                                             # <-- Clean linebreak
            puts "----------------------------------------"        # <-- Print horizontal line
            puts "ORTHO MIRROR TOOL ACTIVATED"                    # <-- Print activation message
            puts "Arrow keys: Right=Red(X), Left=Green(Y), Up=Blue(Z)"  # <-- Print axis lock instructions
            
            # Check for parallel projection
            unless Na__OrthoMirrorTool.is_parallel_projection?(view)
                puts "WARNING: Not in Parallel Projection mode"   # <-- Print warning
                puts "Tool works best in Top/Front/Right etc views"
            end
            
            # Check for selection
            if model.selection.empty?
                puts "WARNING: No objects selected"               # <-- Print warning
                puts "Please select objects to mirror first"
                Sketchup::set_status_text("Select objects first, then reactivate tool", SB_PROMPT)
            else
                puts "Selection count: #{model.selection.count}"  # <-- Print selection info
                puts "Click first point of mirror axis"            # <-- Print instruction
                Sketchup::set_status_text("Click first point of mirror axis. Arrow keys to lock axis.", SB_PROMPT)
            end
            
            ortho_view = Na__OrthoMirrorTool.identify_ortho_view(view)
            puts "Current view: #{ortho_view.to_s.upcase}"        # <-- Print current view
            puts "----------------------------------------"        # <-- Print horizontal line
            
            @state = STATE_IDLE                                   # <-- Reset state
            @start_point = nil                                    # <-- Clear start point
            @locked_axis = LOCK_NONE                              # <-- Reset axis lock
            view.invalidate                                       # <-- Refresh view
        end
        # ------------------------------------------------------------


        # DEACTIVATE | Called when tool is deselected
        # ------------------------------------------------------------
        def deactivate(view)
            view.lock_inference                                   # <-- Unlock any inference lock
            view.invalidate                                       # <-- Refresh view to clear overlays
            @state = STATE_IDLE                                   # <-- Reset state
            @start_point = nil                                    # <-- Clear start point
            @locked_axis = LOCK_NONE                              # <-- Reset axis lock
        end
        # ------------------------------------------------------------


        # RESUME | Called when tool is resumed
        # ------------------------------------------------------------
        def resume(view)
            view.invalidate                                       # <-- Refresh view
            update_status_text                                    # <-- Update status bar
        end
        # ------------------------------------------------------------


        # ON MOUSE MOVE | Track cursor position and snap type
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                  # <-- Update input point with snapping
            @cursor_pos = @ip.position                            # <-- Store cursor position
            @point_type = Na__OrthoMirrorTool.detect_point_type(@ip)  # <-- Detect snap type
            
            # Update preview end point if in drawing state
            if @state == STATE_FIRST_POINT_SET && @cursor_pos
                @end_point = get_constrained_end_point(@cursor_pos)  # <-- Get constrained end point
            end
            
            view.invalidate                                       # <-- Refresh view for overlay update
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Get Constrained End Point Based on Axis Lock
        # ------------------------------------------------------------
        def get_constrained_end_point(raw_position)
            return raw_position unless @start_point               # <-- Return raw if no start point
            return raw_position if @locked_axis == LOCK_NONE      # <-- Return raw if no lock
            
            # Get the axis vector for the locked axis
            axis_vector = Na__OrthoMirrorTool.get_axis_vector(@locked_axis)
            return raw_position unless axis_vector                # <-- Return raw if no valid axis
            
            # Constrain the point to the locked axis
            Na__OrthoMirrorTool.constrain_point_to_axis(@start_point, raw_position, axis_vector)
        end
        # ------------------------------------------------------------


        # ON LEFT BUTTON DOWN | Handle click events
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)                                  # <-- Update input point
            return unless @ip.valid?                              # <-- Exit if no valid position
            
            click_pos = @ip.position                              # <-- Get click position
            
            case @state
            when STATE_IDLE
                handle_first_click(click_pos, view)               # <-- Handle first point click
                
            when STATE_FIRST_POINT_SET
                handle_second_click(click_pos, view)              # <-- Handle second point click
            end
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Handle First Point Click
        # ------------------------------------------------------------
        def handle_first_click(position, view)
            model = Sketchup.active_model                         # <-- Get active model
            
            # Validate selection exists
            if model.selection.empty?
                UI.beep                                           # <-- Audio feedback
                Sketchup::set_status_text("No selection! Select objects first", SB_PROMPT)
                return
            end
            
            @start_point = position                               # <-- Store first point
            @state = STATE_FIRST_POINT_SET                        # <-- Advance state
            
            puts "First point set: #{format_point(@start_point)}" # <-- Print confirmation
            Sketchup::set_status_text("Click second point of mirror axis", SB_PROMPT)
            
            view.invalidate                                       # <-- Refresh view
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Handle Second Point Click
        # ------------------------------------------------------------
        def handle_second_click(position, view)
            # Get constrained end point if axis is locked
            @end_point = get_constrained_end_point(position)      # <-- Store constrained end point
            
            # Validate mirror line length
            if @start_point.distance(@end_point) < 0.001
                UI.beep                                           # <-- Audio feedback for error
                Sketchup::set_status_text("Points too close! Click different point", SB_PROMPT)
                return
            end
            
            puts "Second point set: #{format_point(@end_point)}"  # <-- Print confirmation
            if @locked_axis != LOCK_NONE
                puts "Axis lock: #{Na__OrthoMirrorTool.get_axis_name(@locked_axis)}"
            end
            
            # Execute the mirror operation
            execute_mirror_transformation(view)
            
            # Reset tool state for another mirror operation
            @state = STATE_IDLE                                   # <-- Reset state
            @start_point = nil                                    # <-- Clear start point
            @end_point = nil                                      # <-- Clear end point
            @locked_axis = LOCK_NONE                              # <-- Reset axis lock
            view.lock_inference                                   # <-- Unlock inference
            
            Sketchup::set_status_text("Mirror complete. Click for new mirror axis", SB_PROMPT)
            view.invalidate                                       # <-- Refresh view
        end
        # ------------------------------------------------------------


        # ON KEY DOWN | Handle keyboard input
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            # Handle Escape key (27 on Windows, 53 on macOS - no VK_ESCAPE constant exists)
            escape_key_code = (Sketchup.platform == :platform_win ? 27 : 53)
            if key == escape_key_code                             # <-- Escape key pressed
                if @state == STATE_FIRST_POINT_SET
                    # Cancel current operation, reset to idle
                    @state = STATE_IDLE                           # <-- Reset state
                    @start_point = nil                            # <-- Clear start point
                    @locked_axis = LOCK_NONE                      # <-- Reset axis lock
                    view.lock_inference                           # <-- Unlock inference
                    Sketchup::set_status_text("Cancelled. Click first point of mirror axis", SB_PROMPT)
                    view.invalidate                               # <-- Refresh view
                    return true                                   # <-- Key handled
                end
            end
            
            # Handle Arrow keys for axis locking (only when first point is set)
            if @state == STATE_FIRST_POINT_SET
                case key
                when VK_RIGHT                                     # <-- Right arrow = Red axis (X)
                    handle_axis_lock_key(LOCK_X, view)
                    return true
                    
                when VK_LEFT                                      # <-- Left arrow = Green axis (Y)
                    handle_axis_lock_key(LOCK_Y, view)
                    return true
                    
                when VK_UP                                        # <-- Up arrow = Blue axis (Z)
                    handle_axis_lock_key(LOCK_Z, view)
                    return true
                    
                when VK_DOWN                                      # <-- Down arrow = Unlock
                    unlock_axis(view)
                    return true
                end
            end
            
            false                                                 # <-- Key not handled
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Handle Axis Lock Key Press
        # ------------------------------------------------------------
        def handle_axis_lock_key(new_lock, view)
            if @locked_axis == new_lock                           # <-- Same key pressed again
                unlock_axis(view)                                 # <-- Toggle off (unlock)
            else
                lock_to_axis(new_lock, view)                      # <-- Lock to new axis
            end
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Lock to Specified Axis
        # ------------------------------------------------------------
        def lock_to_axis(axis_lock, view)
            @locked_axis = axis_lock                              # <-- Set locked axis
            
            # Get axis vector and set up inference lock
            axis_vector = Na__OrthoMirrorTool.get_axis_vector(axis_lock)
            if axis_vector && @start_point
                # Create InputPoints for lock_inference
                ip1 = Sketchup::InputPoint.new(@start_point)
                ip2 = Sketchup::InputPoint.new(@start_point.offset(axis_vector, 1000.mm))
                view.lock_inference(ip1, ip2)                     # <-- Lock inference to axis
            end
            
            # Update status and console
            axis_name = Na__OrthoMirrorTool.get_axis_name(axis_lock)
            puts "Axis locked to: #{axis_name}"                   # <-- Print lock status
            Sketchup::set_status_text("Locked to #{axis_name} axis. Click second point.", SB_PROMPT)
            
            view.invalidate                                       # <-- Refresh view
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Unlock Axis Constraint
        # ------------------------------------------------------------
        def unlock_axis(view)
            @locked_axis = LOCK_NONE                              # <-- Clear axis lock
            view.lock_inference                                   # <-- Unlock inference (no args)
            
            puts "Axis lock released"                             # <-- Print unlock status
            Sketchup::set_status_text("Axis unlocked. Click second point or use arrow keys to lock.", SB_PROMPT)
            
            view.invalidate                                       # <-- Refresh view
        end
        # ------------------------------------------------------------


        # ON CANCEL | Handle tool cancellation
        # ------------------------------------------------------------
        def onCancel(reason, view)
            @state = STATE_IDLE                                   # <-- Reset state
            @start_point = nil                                    # <-- Clear start point
            @locked_axis = LOCK_NONE                              # <-- Reset axis lock
            view.lock_inference                                   # <-- Unlock inference
            view.invalidate                                       # <-- Refresh view
        end
        # ------------------------------------------------------------


        # DRAW | Render Visual Feedback Overlays
        # ------------------------------------------------------------
        def draw(view)
            return unless @cursor_pos                             # <-- Exit if no cursor position
            
            # Draw the standard InputPoint indicator
            @ip.draw(view)                                        # <-- Draw snap indicator
            
            # Draw preview line if first point is set
            if @state == STATE_FIRST_POINT_SET && @start_point
                # Use constrained end point for preview
                preview_end = get_constrained_end_point(@cursor_pos)
                draw_preview_line(view, @start_point, preview_end)
                
                # Draw axis lock indicator if locked
                if @locked_axis != LOCK_NONE
                    draw_axis_lock_indicator(view)
                end
            end
            
            # Draw point type indicator at cursor
            case @point_type
            when :vertex
                draw_endpoint_indicator(view, @cursor_pos)        # <-- Red square for vertex
            when :midpoint
                draw_midpoint_indicator(view, @cursor_pos)        # <-- Green circle for midpoint
            end
            
            # Draw indicator at start point if set
            if @start_point
                draw_start_point_marker(view, @start_point)       # <-- Mark the first point
            end
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Draw Axis Lock Indicator
        # ------------------------------------------------------------
        def draw_axis_lock_indicator(view)
            return unless @start_point && @locked_axis != LOCK_NONE
            
            # Get axis vector and color
            axis_vector = Na__OrthoMirrorTool.get_axis_vector(@locked_axis)
            axis_color = Na__OrthoMirrorTool.get_axis_color(@locked_axis)
            
            return unless axis_vector
            
            # Draw a dashed line extending from start point along the locked axis
            extend_length = 2000.mm                               # <-- Length of axis indicator line
            
            pt_pos = @start_point.offset(axis_vector, extend_length)
            pt_neg = @start_point.offset(axis_vector.reverse, extend_length)
            
            view.line_stipple = "."                               # <-- Dotted line for axis indicator
            view.line_width = 1                                   # <-- Thin line
            view.drawing_color = axis_color                       # <-- Axis color
            
            view.draw_line(pt_neg, pt_pos)                        # <-- Draw axis indicator line
            
            view.line_stipple = ""                                # <-- Reset to solid
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Draw Preview Line Between Points
        # ------------------------------------------------------------
        def draw_preview_line(view, pt1, pt2)
            view.line_stipple = ""                                # <-- Solid line
            view.line_width = PREVIEW_LINE_WIDTH                  # <-- Set line width
            
            # Use axis color if locked, otherwise default preview color
            line_color = Na__OrthoMirrorTool.get_axis_color(@locked_axis)
            view.drawing_color = line_color                       # <-- Set color based on lock state
            
            view.draw_line(pt1, pt2)                              # <-- Draw the line
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Draw Start Point Marker
        # ------------------------------------------------------------
        def draw_start_point_marker(view, point)
            screen_pt = view.screen_coords(point)                 # <-- Convert to screen coords
            size = INDICATOR_SIZE                                 # <-- Get indicator size
            
            # Use axis color if locked, otherwise default preview color
            marker_color = Na__OrthoMirrorTool.get_axis_color(@locked_axis)
            view.drawing_color = marker_color                     # <-- Set marker color
            
            # Create square corners in screen space
            x = screen_pt.x
            y = screen_pt.y
            half = size / 2.0
            
            square_pts = [
                Geom::Point3d.new(x - half, y - half, 0),         # <-- Top-left
                Geom::Point3d.new(x + half, y - half, 0),         # <-- Top-right
                Geom::Point3d.new(x + half, y + half, 0),         # <-- Bottom-right
                Geom::Point3d.new(x - half, y + half, 0)          # <-- Bottom-left
            ]
            
            view.draw2d(GL_QUADS, square_pts)                     # <-- Draw filled square
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Draw Endpoint Indicator (Red Square)
        # ------------------------------------------------------------
        def draw_endpoint_indicator(view, point)
            screen_pt = view.screen_coords(point)                 # <-- Convert to screen coords
            size = INDICATOR_SIZE                                 # <-- Get indicator size
            
            # Draw red square outline
            view.drawing_color = ENDPOINT_COLOR                   # <-- Red color
            view.line_width = 2                                   # <-- Line width
            
            x = screen_pt.x
            y = screen_pt.y
            half = size / 2.0
            
            square_pts = [
                Geom::Point3d.new(x - half, y - half, 0),         # <-- Top-left
                Geom::Point3d.new(x + half, y - half, 0),         # <-- Top-right
                Geom::Point3d.new(x + half, y + half, 0),         # <-- Bottom-right
                Geom::Point3d.new(x - half, y + half, 0)          # <-- Bottom-left
            ]
            
            view.draw2d(GL_LINE_LOOP, square_pts)                 # <-- Draw square outline
        end
        # ------------------------------------------------------------


        # SUB FUNCTION | Draw Midpoint Indicator (Green Circle)
        # ------------------------------------------------------------
        def draw_midpoint_indicator(view, point)
            screen_pt = view.screen_coords(point)                 # <-- Convert to screen coords
            radius = INDICATOR_SIZE / 2.0                         # <-- Circle radius
            
            # Draw green circle using polygon approximation
            view.drawing_color = MIDPOINT_COLOR                   # <-- Green color
            view.line_width = 2                                   # <-- Line width
            
            x = screen_pt.x
            y = screen_pt.y
            segments = 12                                         # <-- Number of circle segments
            
            circle_pts = []
            (0...segments).each do |i|
                angle = (2.0 * Math::PI * i) / segments           # <-- Calculate angle
                px = x + radius * Math.cos(angle)                 # <-- X coordinate
                py = y + radius * Math.sin(angle)                 # <-- Y coordinate
                circle_pts << Geom::Point3d.new(px, py, 0)
            end
            
            view.draw2d(GL_LINE_LOOP, circle_pts)                 # <-- Draw circle outline
        end
        # ------------------------------------------------------------


        # FUNCTION | Execute Mirror Transformation
        # ------------------------------------------------------------
        def execute_mirror_transformation(view)
            model = Sketchup.active_model                         # <-- Get active model
            selection = model.selection                           # <-- Get current selection
            entities = model.active_entities                      # <-- Get active entities context
            
            # Validate selection
            if selection.empty?
                UI.beep
                puts "ERROR: No entities selected to mirror"
                return
            end
            
            # Calculate mirror plane normal
            plane_normal = Na__OrthoMirrorTool.calculate_mirror_plane_normal(
                @start_point, @end_point, view
            )
            
            if plane_normal.nil?
                UI.beep
                puts "ERROR: Could not calculate mirror plane"
                return
            end
            
            # Calculate midpoint of mirror axis
            midpoint = Geom::Point3d.linear_combination(
                0.5, @start_point, 0.5, @end_point
            )
            
            # Build the mirror transformation
            mirror_transform = Na__OrthoMirrorTool.build_mirror_transform(midpoint, plane_normal)
            
            # Start undo operation
            model.start_operation('Mirror Selection', true)       # <-- Begin undo operation
            
            begin
                # Create a temporary group from selection
                temp_group = entities.add_group(selection.to_a)   # <-- Group selection
                
                # Create a copy of the group (this will be the mirrored version)
                group_copy = entities.add_instance(
                    temp_group.definition, 
                    temp_group.transformation
                )
                
                # Apply mirror transformation to the copy
                group_copy.transform!(mirror_transform)           # <-- Apply mirror
                
                # Explode both groups to return entities to model space
                original_entities = temp_group.explode            # <-- Explode original group
                mirrored_entities = group_copy.explode            # <-- Explode mirrored group
                
                # Update selection to include mirrored entities
                selection.clear                                   # <-- Clear current selection
                selection.add(mirrored_entities) if mirrored_entities  # <-- Select mirrored entities
                
                model.commit_operation                            # <-- Commit undo operation
                
                puts "\n"
                puts "----------------------------------------"
                puts "MIRROR OPERATION COMPLETE"
                puts "Mirror axis: #{format_point(@start_point)} to #{format_point(@end_point)}"
                puts "Plane normal: [#{plane_normal.x.round(3)}, #{plane_normal.y.round(3)}, #{plane_normal.z.round(3)}]"
                puts "Mirrored entities: #{mirrored_entities ? mirrored_entities.count : 0}"
                puts "----------------------------------------"
                
            rescue => e
                model.abort_operation                             # <-- Abort on error
                puts "ERROR: Mirror operation failed - #{e.message}"
                UI.beep
            end
        end
        # ------------------------------------------------------------


        # HELPER FUNCTION | Format Point for Console Output
        # ------------------------------------------------------------
        def format_point(pt)
            return "nil" unless pt
            "[#{pt.x.to_mm.round(1)}mm, #{pt.y.to_mm.round(1)}mm, #{pt.z.to_mm.round(1)}mm]"
        end
        # ------------------------------------------------------------


        # HELPER FUNCTION | Update Status Bar Text
        # ------------------------------------------------------------
        def update_status_text
            case @state
            when STATE_IDLE
                Sketchup::set_status_text("Click first point of mirror axis. Arrow keys to lock axis.", SB_PROMPT)
            when STATE_FIRST_POINT_SET
                if @locked_axis != LOCK_NONE
                    axis_name = Na__OrthoMirrorTool.get_axis_name(@locked_axis)
                    Sketchup::set_status_text("Locked to #{axis_name}. Click second point. Down arrow to unlock.", SB_PROMPT)
                else
                    Sketchup::set_status_text("Click second point. Arrow keys: Right=X, Left=Y, Up=Z", SB_PROMPT)
                end
            end
        end
        # ------------------------------------------------------------

    end # End OrthoMirrorTool class

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public Entry Point
# -----------------------------------------------------------------------------

    # FUNCTION | Run Ortho Mirror Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts
    # Method name: Na__OrthoMirrorTool.Na__OrthoMirrorTool__Run
    # ------------------------------------------------------------
    def self.Na__OrthoMirrorTool__Run
        model = Sketchup.active_model                             # <-- Get active model
        return unless model                                       # <-- Exit if no active model
        
        model.select_tool(OrthoMirrorTool.new)                    # <-- Activate the tool
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Menu Registration
# -----------------------------------------------------------------------------

    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                 # <-- Exit if already installed
        
        # Create UI command
        cmd = UI::Command.new('NA_OrthoMirrorTool') do            # <-- Create command
            Na__OrthoMirrorTool.Na__OrthoMirrorTool__Run          # <-- Run logic
        end
        cmd.tooltip = "2D Ortho Mirror Tool"                      # <-- Tooltip
        cmd.status_bar_text = "Mirror selection using 2D camera view plane"  # <-- Status bar
        cmd.menu_text = "Na__OrthoMirrorTool"                     # <-- Menu text
        
        # Add to Plugins menu
        UI.menu('Plugins').add_item(cmd)                          # <-- Add item
        
        @menu_installed = true                                    # <-- Mark installed
    end
    # ------------------------------------------------------------


    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                 # <-- Install commands
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # End Na__OrthoMirrorTool module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    Na__OrthoMirrorTool.activate_for_model(Sketchup.active_model) # <-- Activate
    file_loaded(__FILE__)                                         # <-- Mark loaded
end

# -----------------------------------------------------------------------------
# CONSOLE EXECUTION | Uncomment to run directly in Ruby Console
# -----------------------------------------------------------------------------
# Na__OrthoMirrorTool.Na__OrthoMirrorTool__Run
