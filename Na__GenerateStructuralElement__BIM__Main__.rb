# -----------------------------------------------------------------------------
# SketchUp Plugin | Structural Member Creator Tool
# -----------------------------------------------------------------------------
# Interactive tool to create structural steel members (beams, columns, SHS, RSA)
# Creates members with BIM metadata and Dynamic Component attributes
# Supports Universal Beams, Universal Columns, Square Hollow Sections, and Rolled Steel Angles
#
# Version 1.1.0 - 29-Dec-2025
#  - Major refactor from SU 2025 Combine tools version into new standalone version
#  - Updated to include angle steel & fixed shs
#
# Version 1.0.0 - 10-March-2025
#  - First Stable Version
#
# -----------------------------------------------------------------------------

module Na__GenerateStructuralElement

    # -----------------------------------------------------------------------------
    # REGION | Constants
    # -----------------------------------------------------------------------------

    TEMP_GROUP_NAME = "NA_Structural_Member_Creation_Temporary_Group".freeze    # <-- Temporary group name for geometry creation
    DA_DICT         = "dynamic_attributes".freeze                                # <-- Dynamic Component dictionary key
    ORIGIN          = Geom::Point3d.new(0, 0, 0)                                # <-- Origin point for transformations

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Helper Functions
    # -----------------------------------------------------------------------------

    # FUNCTION | Round Point to Nearest 5mm Grid Coordinate
    # ------------------------------------------------------------
    def self.round_point_to_nearest_5mm(pt)
        mm_inch = 25.4                                                           # <-- Millimeters to inches conversion
        step    = 5.0                                                            # <-- Grid step size (5mm)
        x_mm    = pt.x * mm_inch                                                 # <-- Convert X to millimeters
        y_mm    = pt.y * mm_inch                                                 # <-- Convert Y to millimeters
        z_mm    = pt.z * mm_inch                                                 # <-- Convert Z to millimeters
        
        rx = (x_mm / step).round * step                                         # <-- Round X to nearest 5mm
        ry = (y_mm / step).round * step                                         # <-- Round Y to nearest 5mm
        rz = (z_mm / step).round * step                                         # <-- Round Z to nearest 5mm
        
        Geom::Point3d.new(rx / mm_inch, ry / mm_inch, rz / mm_inch)            # <-- Return snapped point in inches
    end
    # ---------------------------------------------------------------

    # FUNCTION | Log Error to Console
    # ------------------------------------------------------------
    def self.log_error(e)
        puts "[#{Time.now}] #{e.class}: #{e.message}"                           # <-- Print error timestamp and message
        puts e.backtrace.join("\n")                                             # <-- Print stack trace
        puts "-" * 50                                                            # <-- Print separator line
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Data Libraries
    # -----------------------------------------------------------------------------

    # FUNCTION | Structural Steel Profile Data
    # ------------------------------------------------------------
    module NA_DATA_LIBRARY_StructuralSteel
        module NA_HASH_UniversalBeams
            UNIVERSAL_BEAM_SIZES = {
                "UB 152x89x16"   => { width: 89,  height: 152, flange_thickness:  8, web_thickness:  5 },
                "UB 178x102x19"  => { width: 102, height: 178, flange_thickness:  8, web_thickness:  6 },
                "UB 203x102x23"  => { width: 102, height: 203, flange_thickness:  9, web_thickness:  6 },
                "UB 254x102x22"  => { width: 102, height: 254, flange_thickness:  7, web_thickness:  5 },
                "UB 254x102x25"  => { width: 102, height: 254, flange_thickness: 10, web_thickness:  6 },
                "UB 254x102x28"  => { width: 102, height: 254, flange_thickness:  8, web_thickness:  6 },
                "UB 254x146x31"  => { width: 146, height: 254, flange_thickness:  7, web_thickness:  6 },
                "UB 254x146x37"  => { width: 146, height: 254, flange_thickness:  9, web_thickness:  6 },
                "UB 254x146x43"  => { width: 146, height: 254, flange_thickness: 10, web_thickness:  7 },
                "UB 254x146x50"  => { width: 146, height: 254, flange_thickness: 11, web_thickness:  7 },
                "UB 305x102x28"  => { width: 102, height: 305, flange_thickness: 10, web_thickness:  6 },
                "UB 356x127x33"  => { width: 127, height: 356, flange_thickness: 11, web_thickness:  7 },
                "UB 406x140x39"  => { width: 140, height: 406, flange_thickness: 12, web_thickness:  7 },
                "UB 457x152x52"  => { width: 152, height: 457, flange_thickness: 13, web_thickness:  8 },
                "UB 533x210x82"  => { width: 210, height: 533, flange_thickness: 14, web_thickness: 10 },
                "UB 610x229x113" => { width: 229, height: 610, flange_thickness: 18, web_thickness: 12 }
            } unless defined?(UNIVERSAL_BEAM_SIZES)
        end

        module NA_HASH_UniversalColumns
            UNIVERSAL_COLUMN_SIZES = {
                "UC 152x152x23" => { width: 152, height: 152, flange_thickness:  7, web_thickness: 6 },
                "UC 152x152x30" => { width: 152, height: 152, flange_thickness:  9, web_thickness: 7 },
                "UC 152x152x37" => { width: 152, height: 152, flange_thickness: 11, web_thickness: 8 },
                "UC 203x203x46" => { width: 203, height: 203, flange_thickness: 11, web_thickness: 8 },
                "UC 203x203x52" => { width: 203, height: 203, flange_thickness: 12, web_thickness: 8 },
                "UC 203x203x60" => { width: 203, height: 203, flange_thickness: 14, web_thickness: 9 },
                "UC 254x254x73" => { width: 254, height: 254, flange_thickness: 15, web_thickness: 9 },
                "UC 305x305x97" => { width: 305, height: 305, flange_thickness: 16, web_thickness: 10 }
            } unless defined?(UNIVERSAL_COLUMN_SIZES)
        end

        module NA_HASH_SquareHollowSections
            SQUARE_HOLLOW_SECTION_SIZES = {
                "SHS 40x40x3"    => { width: 40,   height: 40,  wall_thickness: 3 },
                "SHS 50x50x3"    => { width: 50,   height: 50,  wall_thickness: 3 },
                "SHS 60x60x4"    => { width: 60,   height: 60,  wall_thickness: 4 },
                "SHS 80x80x5"    => { width: 80,   height: 80,  wall_thickness: 5 },
                "SHS 90x90x5"    => { width: 90,   height: 90,  wall_thickness: 5 },
                "SHS 100x100x5"  => { width: 100,  height: 100, wall_thickness: 5 },
                "SHS 100x100x6"  => { width: 100,  height: 100, wall_thickness: 6 },
                "SHS 100x100x8"  => { width: 100,  height: 100, wall_thickness: 8 },
                "SHS 120x120x4"  => { width: 120,  height: 120, wall_thickness: 4 },
                "SHS 120x120x5"  => { width: 120,  height: 120, wall_thickness: 5 },
                "SHS 120x120x6"  => { width: 120,  height: 120, wall_thickness: 6 },
                "SHS 120x120x8"  => { width: 120,  height: 120, wall_thickness: 8 },
                "SHS 120x120x10" => { width: 120,  height: 120, wall_thickness: 10 },
                "SHS 150x150x6"  => { width: 150,  height: 150, wall_thickness: 6 },
                "SHS 150x150x8"  => { width: 150,  height: 150, wall_thickness: 8 },
                "SHS 150x150x10" => { width: 150,  height: 150, wall_thickness: 10 }
            } unless defined?(SQUARE_HOLLOW_SECTION_SIZES)
        end

        module NA_HASH_UnequalAngles
            UNEQUAL_ANGLE_SIZES = {
                "RSA 100x75x8"  => { leg1: 100, leg2: 75, thickness: 8 },
                "RSA 100x75x10" => { leg1: 100, leg2: 75, thickness: 10 },
                "RSA 100x75x12" => { leg1: 100, leg2: 75, thickness: 12 },
                "RSA 125x75x8"  => { leg1: 125, leg2: 75, thickness: 8 },
                "RSA 125x75x10" => { leg1: 125, leg2: 75, thickness: 10 },
                "RSA 125x75x12" => { leg1: 125, leg2: 75, thickness: 12 },
                "RSA 150x90x10" => { leg1: 150, leg2: 90, thickness: 10 },
                "RSA 150x90x12" => { leg1: 150, leg2: 90, thickness: 12 },
                "RSA 150x90x15" => { leg1: 150, leg2: 90, thickness: 15 }
            } unless defined?(UNEQUAL_ANGLE_SIZES)
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Point Picker Tool
    # -----------------------------------------------------------------------------

    # FUNCTION | Point Picker Tool for 3D Point Selection
    # ------------------------------------------------------------
    class PointPickerTool
        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize(callback, options = {})
            @callback = callback                                                # <-- Store callback function
            @ip = Sketchup::InputPoint.new                                      # <-- Create input point for detection
            
            # Default options
            @static_status_text = options[:status_text] || "Click to select a point"  # <-- Default status text
            @status_formatter = options[:status_formatter]                      # <-- Dynamic status formatter
            @crosshair_size = 300.mm                                            # <-- Crosshair arm length (300mm, matches primitives)
            @title_prefix = options[:title_prefix]                             # <-- Title prefix for window
            @document_action = options[:document_action]                        # <-- Document action after placement
            @original_title = Sketchup.active_model.title                       # <-- Store original window title
            @cursor_pos = nil                                                   # <-- Store cursor position
        end
        # ---------------------------------------------------------------

        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            Sketchup.status_text = @static_status_text                         # <-- Set initial status text
            
            # Update window title if title_prefix option is set
            if @title_prefix && !@title_prefix.empty?
                model = Sketchup.active_model
                @original_title = model.title
                model.title = "#{@title_prefix} #{@original_title}"            # <-- Update window title
            end
            
            Sketchup.active_model.active_view.invalidate                        # <-- Refresh view
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Called when tool is deselected
        # ------------------------------------------------------------
        def deactivate(view)
            # Restore original title
            if @title_prefix && !@title_prefix.empty?
                Sketchup.active_model.title = @original_title                   # <-- Restore original title
            end
            view.invalidate                                                     # <-- Refresh view
        end
        # ---------------------------------------------------------------

        # ON MOUSE MOVE | Track cursor position
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                               # <-- Update input point with snapping
            @cursor_pos = @ip.position                                         # <-- Store cursor position
            
            # Update status text dynamically if a formatter is provided
            if @status_formatter && @ip.valid?
                dynamic_status = @status_formatter.call(@ip.position)          # <-- Format status text
                Sketchup.status_text = dynamic_status if dynamic_status        # <-- Update status bar
            end
            
            view.invalidate                                                     # <-- Refresh view
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Execute callback when point is selected
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)                                               # <-- Update input point
            if @ip.valid?
                @callback.call(@ip.position) if @callback                      # <-- Execute callback
                
                # Perform document action if specified
                perform_document_action if @document_action                    # <-- Save if requested
                
                Sketchup.active_model.select_tool(nil)                         # <-- Deactivate tool
            end
        end
        # ---------------------------------------------------------------

        # DRAW | Render blue crosshair cursor at mouse position
        # ------------------------------------------------------------
        def draw(view)
            return unless @cursor_pos                                           # <-- Exit if no cursor position yet
            
            # Draw input point (shows vertex snapping indicator)
            @ip.draw(view)                                                     # <-- Draw standard InputPoint indicator
            
            # Draw custom blue crosshair cursor (matches primitives tool)
            cx = @cursor_pos.x                                                 # <-- Get cursor X coordinate
            cy = @cursor_pos.y                                                 # <-- Get cursor Y coordinate
            cz = @cursor_pos.z                                                 # <-- Get cursor Z coordinate
            size = @crosshair_size                                             # <-- Get crosshair size
            
            # Define crosshair line endpoints (world-aligned)
            x_pos = Geom::Point3d.new(cx + size, cy, cz)                      # <-- Positive X direction
            x_neg = Geom::Point3d.new(cx - size, cy, cz)                      # <-- Negative X direction
            y_pos = Geom::Point3d.new(cx, cy + size, cz)                      # <-- Positive Y direction
            y_neg = Geom::Point3d.new(cx, cy - size, cz)                      # <-- Negative Y direction
            z_pos = Geom::Point3d.new(cx, cy, cz + size)                      # <-- Positive Z direction
            z_neg = Geom::Point3d.new(cx, cy, cz - size)                      # <-- Negative Z direction
            
            # Set drawing color to blue
            view.line_stipple = ""                                             # <-- Solid line
            view.line_width = 2                                                # <-- Line width 2 pixels
            view.drawing_color = Sketchup::Color.new(0, 100, 255)             # <-- Blue color
            
            # Draw 3D crosshair lines (X, Y, Z axes)
            view.draw_line(@cursor_pos, x_pos)                                # <-- Draw +X arm
            view.draw_line(@cursor_pos, x_neg)                                # <-- Draw -X arm
            view.draw_line(@cursor_pos, y_pos)                                # <-- Draw +Y arm
            view.draw_line(@cursor_pos, y_neg)                                # <-- Draw -Y arm
            view.draw_line(@cursor_pos, z_pos)                                # <-- Draw +Z arm
            view.draw_line(@cursor_pos, z_neg)                                # <-- Draw -Z arm
        end
        # ---------------------------------------------------------------

        # GET EXTENTS | Return bounding box for view updates
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            bb.add(@ip.position) if @ip.valid?                                 # <-- Add point to bounding box
            bb
        end
        # ---------------------------------------------------------------

        # ON CANCEL | Called when user cancels operation
        # ------------------------------------------------------------
        def onCancel(reason, view)
            # Restore original title
            if @title_prefix && !@title_prefix.empty?
                Sketchup.active_model.title = @original_title                  # <-- Restore original title
            end
            Sketchup.active_model.select_tool(nil)                             # <-- Deactivate tool
        end
        # ---------------------------------------------------------------

        private

        # FUNCTION | Perform Document Action
        # ------------------------------------------------------------
        def perform_document_action
            model = Sketchup.active_model
            
            case @document_action
            when :save
                model.save                                                     # <-- Save current model
            when :save_as
                model.save_as                                                  # <-- Open save dialog
            when :save_copy
                model.save_copy                                                # <-- Save copy
            end
        end
        # ---------------------------------------------------------------
    end

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Placement Tool
    # -----------------------------------------------------------------------------

    # FUNCTION | Structural Member Placement Tool with Real-Time Tracking
    # ------------------------------------------------------------
    # Interactive tool that moves structural member to cursor position
    # Press SHIFT to toggle 90-degree rotation around Z axis
    # Left-click to commit final placement
    # ------------------------------------------------------------
    class StructuralMemberPlacementTool
        # CONSTANTS
        Z_AXIS          = Geom::Vector3d.new(0, 0, 1)                           # <-- Z axis vector for rotation
        CROSSHAIR_SIZE  = 300.mm                                                 # <-- Crosshair arm length (300mm)

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize(instance, member_type)
            @instance           = instance                                       # <-- Store component instance
            @member_type        = member_type                                    # <-- Store member type (Beam, Column, etc.)
            @ip                 = Sketchup::InputPoint.new                       # <-- Create input point for snapping
            @cursor_pos         = nil                                            # <-- Current cursor position
            @rotated            = false                                          # <-- Rotation toggle state (false = 0°, true = 90°)
            @original_transform = instance.transformation.clone                  # <-- Store original transformation
            @last_position      = instance.bounds.min                           # <-- Track last position for delta movement
        end
        # ---------------------------------------------------------------

        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            update_status_text                                                   # <-- Set initial status text
            Sketchup.active_model.active_view.invalidate                        # <-- Refresh view
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Called when tool is deselected
        # ------------------------------------------------------------
        def deactivate(view)
            view.invalidate                                                      # <-- Refresh view
        end
        # ---------------------------------------------------------------

        # ON MOUSE MOVE | Track cursor and move instance in real-time
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)                                                # <-- Update input point with snapping
            return unless @ip.valid?                                             # <-- Exit if no valid point

            # Snap cursor position to 5mm grid
            @cursor_pos = Na__GenerateStructuralElement.round_point_to_nearest_5mm(@ip.position)

            # Calculate movement delta from current instance position to cursor
            current_min = @instance.bounds.min
            delta = @cursor_pos - current_min

            # Apply translation to move instance to cursor
            translation = Geom::Transformation.new(delta)
            @instance.transform!(translation)

            # Update last position
            @last_position = @cursor_pos

            # Update status text with current position
            update_status_text

            view.invalidate                                                      # <-- Refresh view
        end
        # ---------------------------------------------------------------

        # ON KEY DOWN | Detect Shift key press to toggle rotation
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if key == CONSTRAIN_MODIFIER_KEY && repeat == 1                     # <-- Shift key, first press only
                toggle_rotation                                                  # <-- Toggle 90-degree rotation
                update_status_text                                               # <-- Update status bar
                view.invalidate                                                  # <-- Refresh view
            end
            false                                                                # <-- Return false to not block VCB
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Commit final placement
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)                                                # <-- Final input point
            return unless @ip.valid?                                             # <-- Exit if no valid point

            # Snap final position to 5mm grid
            final_pt = Na__GenerateStructuralElement.round_point_to_nearest_5mm(@ip.position)

            # Move instance to final position if cursor moved since last move
            current_min = @instance.bounds.min
            delta = final_pt - current_min
            if delta.length > 0.001
                translation = Geom::Transformation.new(delta)
                @instance.transform!(translation)
            end

            # Show confirmation with placement coordinates
            x_mm = (final_pt.x * 25.4).round
            y_mm = (final_pt.y * 25.4).round
            z_mm = (final_pt.z * 25.4).round
            rotation_angle = @rotated ? 90 : 0

            placement_info = "Structural #{@member_type} placed successfully at:\n"
            placement_info += "X: #{x_mm}mm, Y: #{y_mm}mm, Z: #{z_mm}mm\n"
            placement_info += "Rotation: #{rotation_angle}°"

            UI.messagebox(placement_info)

            # Save document after placement
            Sketchup.active_model.save

            # Deactivate tool
            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------

        # DRAW | Render blue crosshair cursor at mouse position
        # ------------------------------------------------------------
        def draw(view)
            return unless @cursor_pos                                            # <-- Exit if no cursor position yet

            # Draw input point (shows vertex snapping indicator)
            @ip.draw(view)                                                       # <-- Draw standard InputPoint indicator

            # Draw custom blue crosshair cursor
            cx   = @cursor_pos.x                                                 # <-- Get cursor X coordinate
            cy   = @cursor_pos.y                                                 # <-- Get cursor Y coordinate
            cz   = @cursor_pos.z                                                 # <-- Get cursor Z coordinate
            size = CROSSHAIR_SIZE                                                # <-- Get crosshair size

            # Define crosshair line endpoints (world-aligned)
            x_pos = Geom::Point3d.new(cx + size, cy, cz)                        # <-- Positive X direction
            x_neg = Geom::Point3d.new(cx - size, cy, cz)                        # <-- Negative X direction
            y_pos = Geom::Point3d.new(cx, cy + size, cz)                        # <-- Positive Y direction
            y_neg = Geom::Point3d.new(cx, cy - size, cz)                        # <-- Negative Y direction
            z_pos = Geom::Point3d.new(cx, cy, cz + size)                        # <-- Positive Z direction
            z_neg = Geom::Point3d.new(cx, cy, cz - size)                        # <-- Negative Z direction

            # Set drawing color to blue
            view.line_stipple = ""                                               # <-- Solid line
            view.line_width = 2                                                  # <-- Line width 2 pixels
            view.drawing_color = Sketchup::Color.new(0, 100, 255)               # <-- Blue color

            # Draw 3D crosshair lines (X, Y, Z axes)
            view.draw_line(@cursor_pos, x_pos)                                  # <-- Draw +X arm
            view.draw_line(@cursor_pos, x_neg)                                  # <-- Draw -X arm
            view.draw_line(@cursor_pos, y_pos)                                  # <-- Draw +Y arm
            view.draw_line(@cursor_pos, y_neg)                                  # <-- Draw -Y arm
            view.draw_line(@cursor_pos, z_pos)                                  # <-- Draw +Z arm
            view.draw_line(@cursor_pos, z_neg)                                  # <-- Draw -Z arm

            # Draw rotation indicator if rotated
            if @rotated
                view.drawing_color = Sketchup::Color.new(255, 165, 0)           # <-- Orange color for rotation indicator
                view.line_width = 3                                              # <-- Thicker line
                arc_size = size * 0.5                                            # <-- Arc radius
                # Draw arc indicator at cursor
                arc_start = Geom::Point3d.new(cx + arc_size, cy, cz)
                arc_end   = Geom::Point3d.new(cx, cy + arc_size, cz)
                view.draw_line(@cursor_pos, arc_start)                          # <-- Draw rotation indicator arm 1
                view.draw_line(@cursor_pos, arc_end)                            # <-- Draw rotation indicator arm 2
            end
        end
        # ---------------------------------------------------------------

        # GET EXTENTS | Return bounding box for view updates
        # ------------------------------------------------------------
        def getExtents
            bb = Geom::BoundingBox.new
            bb.add(@ip.position) if @ip.valid?                                   # <-- Add point to bounding box
            bb.add(@instance.bounds) if @instance && @instance.valid?           # <-- Add instance bounds
            bb
        end
        # ---------------------------------------------------------------

        # ON CANCEL | Called when user cancels operation (Escape key)
        # ------------------------------------------------------------
        def onCancel(reason, view)
            # Restore original transformation if cancelled
            if @instance && @instance.valid?
                @instance.transformation = @original_transform                   # <-- Restore original position/rotation
            end
            Sketchup.active_model.select_tool(nil)                              # <-- Deactivate tool
        end
        # ---------------------------------------------------------------

        private

        # FUNCTION | Toggle 90-Degree Rotation Around Z Axis
        # ------------------------------------------------------------
        def toggle_rotation
            return unless @instance && @instance.valid?                          # <-- Exit if instance invalid

            # Get center of instance for rotation pivot
            center = @instance.bounds.center

            # Calculate rotation angle (toggle between +90 and -90)
            angle = @rotated ? -90.degrees : 90.degrees

            # Create and apply rotation transformation
            rotation = Geom::Transformation.rotation(center, Z_AXIS, angle)
            @instance.transform!(rotation)

            # Toggle rotation state
            @rotated = !@rotated
        end
        # ---------------------------------------------------------------

        # FUNCTION | Update Status Bar Text
        # ------------------------------------------------------------
        def update_status_text
            if @cursor_pos
                # Show coordinates in mm (snapped to 5mm grid)
                x_mm = (@cursor_pos.x * 25.4).round
                y_mm = (@cursor_pos.y * 25.4).round
                z_mm = (@cursor_pos.z * 25.4).round
                rotation_angle = @rotated ? 90 : 0

                status = "Click to place #{@member_type} at X:#{x_mm}mm Y:#{y_mm}mm Z:#{z_mm}mm"
                status += " | Press SHIFT to rotate 90° [Current: #{rotation_angle}°]"
                Sketchup.status_text = status
            else
                Sketchup.status_text = "Move cursor to position #{@member_type} | Press SHIFT to rotate 90°"
            end
        end
        # ---------------------------------------------------------------
    end

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Profile Data Functions
    # -----------------------------------------------------------------------------

    # FUNCTION | Find Profile Information by Size Key
    # ------------------------------------------------------------
    def self.find_profile_info(size_key)
        beams   = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalBeams::UNIVERSAL_BEAM_SIZES
        columns = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalColumns::UNIVERSAL_COLUMN_SIZES
        shs     = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_SquareHollowSections::SQUARE_HOLLOW_SECTION_SIZES
        angles  = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UnequalAngles::UNEQUAL_ANGLE_SIZES

        return beams[size_key]   if beams.key?(size_key)                       # <-- Return beam data if found
        return columns[size_key] if columns.key?(size_key)                     # <-- Return column data if found
        return shs[size_key]     if shs.key?(size_key)                         # <-- Return SHS data if found
        return angles[size_key]  if angles.key?(size_key)                      # <-- Return angle data if found
        nil                                                                     # <-- Return nil if not found
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Mass Calculations
    # -----------------------------------------------------------------------------

    # FUNCTION | Compute Member Mass Per Meter
    # ------------------------------------------------------------
    def self.compute_member_mass_per_m(size_key, _info_unused)
        matched = size_key.match(/(\d+)$/)                                     # <-- Extract number from end of size key
        return 0.0 unless matched                                               # <-- Return 0 if no match
        kg_per_m = matched[1].to_f                                             # <-- Convert to float
        kg_per_m
    end
    # ---------------------------------------------------------------

    # FUNCTION | Calculate Total Member Mass
    # ------------------------------------------------------------
    def self.total_member_mass_kg(size_key, length_mm)
        kg_per_m = compute_member_mass_per_m(size_key, nil)                    # <-- Get mass per meter
        length_m = length_mm / 1000.0                                          # <-- Convert length to meters
        (kg_per_m * length_m).round(2)                                         # <-- Calculate total mass
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Geometry Creation
    # -----------------------------------------------------------------------------

    # FUNCTION | Create Named Group for Geometry
    # ------------------------------------------------------------
    def self.create_named_group_for_geometry(model)
        group = model.active_entities.add_group                                 # <-- Create new group
        group.name = TEMP_GROUP_NAME                                           # <-- Set temporary name
        group
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw I-Section Profile
    # ------------------------------------------------------------
    def self.draw_i_section_profile(ents, info)
        w  = info[:width].mm                                                    # <-- Convert width to inches
        h  = info[:height].mm                                                  # <-- Convert height to inches
        ft = info[:flange_thickness].mm                                        # <-- Convert flange thickness to inches
        wt = info[:web_thickness].mm                                           # <-- Convert web thickness to inches

        pts = [                                                                 # <-- Define I-section profile points
            [0, 0, 0],
            [w, 0, 0],
            [w, ft, 0],
            [(w + wt)/2, ft, 0],
            [(w + wt)/2, h - ft, 0],
            [w, h - ft, 0],
            [w, h, 0],
            [0, h, 0],
            [0, h - ft, 0],
            [(w - wt)/2, h - ft, 0],
            [(w - wt)/2, ft, 0],
            [0, ft, 0]
        ]

        face = ents.add_face(pts)                                              # <-- Create face from points
        face.reverse! if face.valid? && face.normal.z < 0                      # <-- Reverse if facing wrong direction
        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw L-Section Profile (Angle)
    # ------------------------------------------------------------
    def self.draw_angle_profile(ents, info)
        leg1 = info[:leg1].mm                                                   # <-- Convert leg1 length to inches
        leg2 = info[:leg2].mm                                                   # <-- Convert leg2 length to inches
        t    = info[:thickness].mm                                              # <-- Convert thickness to inches

        pts = [                                                                 # <-- Define L-section profile points
            [0, 0, 0],
            [leg1, 0, 0],
            [leg1, t, 0],
            [t, t, 0],
            [t, leg2, 0],
            [0, leg2, 0]
        ]

        face = ents.add_face(pts)                                              # <-- Create face from points
        face.reverse! if face.valid? && face.normal.z < 0                      # <-- Reverse if facing wrong direction
        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw SHS Profile (Square Hollow Section with hole)
    # ------------------------------------------------------------
    # Creates hollow rectangular profile by drawing outer and inner faces
    # Inner face becomes a hole when coplanar with outer face
    # ------------------------------------------------------------
    def self.draw_shs_profile(ents, info)
        w  = info[:width].mm                                                    # <-- Outer width in inches
        h  = info[:height].mm                                                   # <-- Outer height in inches
        wt = info[:wall_thickness].mm                                           # <-- Wall thickness in inches

        # Draw outer rectangle (perimeter)
        outer_pts = [                                                           # <-- Define outer profile points
            [0, 0, 0],
            [w, 0, 0],
            [w, h, 0],
            [0, h, 0]
        ]
        outer_face = ents.add_face(outer_pts)                                   # <-- Create outer face
        outer_face.reverse! if outer_face.valid? && outer_face.normal.z < 0    # <-- Ensure correct orientation

        # Draw inner rectangle (hole) - offset inward by wall thickness
        inner_pts = [                                                           # <-- Define inner profile points (hole)
            [wt, wt, 0],
            [w - wt, wt, 0],
            [w - wt, h - wt, 0],
            [wt, h - wt, 0]
        ]
        ents.add_face(inner_pts)                                                # <-- Creates hole in outer face

        outer_face                                                               # <-- Return outer face for pushpull
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Material Application
    # -----------------------------------------------------------------------------

    # FUNCTION | Apply Steel Material
    # ------------------------------------------------------------
    def self.apply_steel_material(entity)
        mat_name = "E10_S01_V01_--_Structural_Steelwork"                       # <-- Material name
        mats = Sketchup.active_model.materials
        mat  = mats[mat_name] || mats.add(mat_name)                            # <-- Get or create material
        mat.color = Sketchup::Color.new(185, 95, 95)                          # <-- Set steel color
        entity.material = mat                                                   # <-- Apply material
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Component Conversion
    # -----------------------------------------------------------------------------

    # FUNCTION | Convert Temporary Group to Component
    # ------------------------------------------------------------
    def self.convert_temp_group_to_component(model, size_key, member_type, length_mm)
        all_temp_groups = model.active_entities.grep(Sketchup::Group).select { |g| g.name == TEMP_GROUP_NAME }
        return nil if all_temp_groups.empty?                                    # <-- Exit if no temp groups found

        group    = all_temp_groups.last                                         # <-- Get last temp group
        instance = group.to_component                                           # <-- Convert to component
        return nil unless instance.is_a?(Sketchup::ComponentInstance)          # <-- Validate conversion

        definition     = instance.definition
        base_def_name  = "NA_#{member_type}_#{size_key}"
        definition.name = safe_unique_def_name(model, base_def_name)            # <-- Set unique definition name
        instance.name   = next_instance_name(model, "#{member_type}_Instance") # <-- Set unique instance name

        info              = find_profile_info(size_key) || {}
        width             = info[:width]  || 0
        ht                = info[:height] || 0
        member_total_mass = total_member_mass_kg(size_key, length_mm)

        da = DA_DICT
        instance.set_attribute(da, "_formatversion",     "1.0")
        instance.set_attribute(da, "IsDynamic",          "TRUE")
        instance.set_attribute(da, "_hasbehaviors",      "1.0")
        instance.set_attribute(da, "_lengthunits",       "INCHES")
        instance.set_attribute(da, "_name",              definition.name)

        code_prefix = case member_type
                      when "Beam"   then "BM0#"
                      when "Column" then "CM0#"
                      when "SHS"    then "SH0#"
                      when "RSA"    then "RS0#"
                      else "XX01"
                      end

        instance.set_attribute(da, "a1_element_code", code_prefix)
        instance.set_attribute(da, "_a1_element_code_label",  "#{member_type} Code")
        instance.set_attribute(da, "_a1_element_code_access", "TEXTBOX")
        instance.set_attribute(da, "_a1_element_code_units",  "STRING")

        instance.set_attribute(da, "a2_section_name", size_key)
        instance.set_attribute(da, "_a2_section_name_label",  "Profile Type")
        instance.set_attribute(da, "_a2_section_name_access", "VIEW")
        instance.set_attribute(da, "_a2_section_name_units",  "STRING")

        instance.set_attribute(da, "a3_member_name", "")
        instance.set_attribute(da, "_a3_member_name_label",   "Member Name")
        instance.set_attribute(da, "_a3_member_name_access",  "TEXTBOX")
        instance.set_attribute(da, "_a3_member_name_units",   "STRING")

        instance.set_attribute(da, "a4_member_code", "")
        instance.set_attribute(da, "_a4_member_code_label",   "Member Code")
        instance.set_attribute(da, "_a4_member_code_access",  "TEXTBOX")
        instance.set_attribute(da, "_a4_member_code_units",   "STRING")

        instance.set_attribute(da, "a5_member_location", "")
        instance.set_attribute(da, "_a5_member_location_label",   "Member Location")
        instance.set_attribute(da, "_a5_member_location_access",  "TEXTBOX")
        instance.set_attribute(da, "_a5_member_location_units",   "STRING")

        instance.set_attribute(da, "a6_member_notes", "")
        instance.set_attribute(da, "_a6_member_notes_label",   "Notes")
        instance.set_attribute(da, "_a6_member_notes_access",  "TEXTAREA")
        instance.set_attribute(da, "_a6_member_notes_units",   "STRING")

        instance.set_attribute(da, "a7_element_type", member_type)
        instance.set_attribute(da, "_a7_element_type_label",  "Element Type")
        instance.set_attribute(da, "_a7_element_type_access", "VIEW")
        instance.set_attribute(da, "_a7_element_type_units",  "STRING")

        instance.set_attribute(da, "a8_element_size", size_key)
        instance.set_attribute(da, "_a8_element_size_label",  "#{member_type} Size")
        instance.set_attribute(da, "_a8_element_size_access", "VIEW")
        instance.set_attribute(da, "_a8_element_size_units",  "STRING")

        instance.set_attribute(da, "h1_calc_mm_to_inches", "")
        instance.set_attribute(da, "_h1_calc_mm_to_inches_label",        "MM_to_Inches_Helper")
        instance.set_attribute(da, "_h1_calc_mm_to_inches_units",        "STRING")
        instance.set_attribute(da, "_h1_calc_mm_to_inches_formulaunits", "FLOAT")
        instance.set_attribute(da, "_h1_calc_mm_to_inches_formula",      "*25.4")
        instance.set_attribute(da, "_h1_calc_mm_to_inches_access",       "NONE")

        instance.set_attribute(da, "d1_length_mm", length_mm.to_s)
        instance.set_attribute(da, "_d1_length_mm_label",   "Member Length (mm)")
        instance.set_attribute(da, "_d1_length_mm_units",   "STRING")
        instance.set_attribute(da, "_d1_length_mm_access",  "TEXTBOX")

        instance.set_attribute(da, "d2_length_in", "")
        instance.set_attribute(da, "_d2_length_in_label",    "Length (Inches)")
        instance.set_attribute(da, "_d2_length_in_formula",  "(d1_length_mm)/h1_calc_mm_to_inches")
        instance.set_attribute(da, "_d2_length_in_units",    "FLOAT")
        instance.set_attribute(da, "_d2_length_in_access",   "NONE")

        instance.set_attribute(da, "LenZ", "LenZ")
        instance.set_attribute(da, "_lenz_label",   "Overall Z Dimension")
        instance.set_attribute(da, "_lenz_formula", "d2_length_in")
        instance.set_attribute(da, "_lenz_access",  "NONE")

        instance.set_attribute(da, "profile_width_mm",  width.to_s)
        instance.set_attribute(da, "_profile_width_mm_label",  "Profile Width (mm)")
        instance.set_attribute(da, "_profile_width_mm_access", "VIEW")
        instance.set_attribute(da, "_profile_width_mm_units",  "STRING")

        instance.set_attribute(da, "profile_height_mm", ht.to_s)
        instance.set_attribute(da, "_profile_height_mm_label",  "Profile Height (mm)")
        instance.set_attribute(da, "_profile_height_mm_access", "VIEW")
        instance.set_attribute(da, "_profile_height_mm_units",  "STRING")

        instance.set_attribute(da, "w1_member_total_mass_kg", member_total_mass.to_s)
        instance.set_attribute(da, "_w1_member_total_mass_kg_label",  "Total Mass (kg)")
        instance.set_attribute(da, "_w1_member_total_mass_kg_access", "VIEW")
        instance.set_attribute(da, "_w1_member_total_mass_kg_units",  "FLOAT")

        if $dc_observers && $dc_observers.respond_to?(:get_latest_class)
            $dc_observers.get_latest_class.redraw_with_undo(instance)          # <-- Force Dynamic Component redraw
        end

        instance
    end
    # ---------------------------------------------------------------

    # FUNCTION | Generate Safe Unique Definition Name
    # ------------------------------------------------------------
    def self.safe_unique_def_name(model, base_name)
        name    = base_name.dup
        counter = 1
        while model.definitions[name]                                           # <-- Check if name exists
            name = "#{base_name} (#{counter})"                                 # <-- Append counter
            counter += 1
        end
        name
    end
    # ---------------------------------------------------------------

    # FUNCTION | Generate Next Instance Name
    # ------------------------------------------------------------
    def self.next_instance_name(model, base_name)
        existing = model.active_entities.grep(Sketchup::ComponentInstance).map(&:name)
        return base_name unless existing.include?(base_name)                    # <-- Return base name if unique
        counter = 1
        while existing.include?("#{base_name} (#{counter})")                   # <-- Check if numbered name exists
            counter += 1
        end
        "#{base_name} (#{counter})"                                            # <-- Return numbered name
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Interactive Placement Orchestration
    # -----------------------------------------------------------------------------

    # FUNCTION | Move Member to Picked Point (Interactive Placement)
    # ------------------------------------------------------------
    # Activates interactive placement tool with real-time tracking
    # Member follows cursor, Shift toggles 90° rotation, click to place
    # ------------------------------------------------------------
    def self.move_member_to_picked_point(instance, member_type)
        # Build a brief summary of the created member
        size_key  = instance.get_attribute(DA_DICT, "a8_element_size") || "Unknown"
        length_mm = instance.get_attribute(DA_DICT, "d1_length_mm") || "0"
        mass_kg   = instance.get_attribute(DA_DICT, "w1_member_total_mass_kg") || "0"

        # Show brief creation confirmation
        details = "Steel #{member_type} created: #{size_key}, #{length_mm}mm, #{mass_kg}kg\n\n"
        details += "Move cursor to position the member.\n"
        details += "Press SHIFT to rotate 90° around Z axis.\n"
        details += "Click to place."

        UI.messagebox(details)

        # Activate interactive placement tool with real-time tracking
        Sketchup.active_model.select_tool(
            StructuralMemberPlacementTool.new(instance, member_type)
        )
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Member Creation Orchestration
    # -----------------------------------------------------------------------------

    # FUNCTION | Create Structural Member
    # ------------------------------------------------------------
    def self.create_structural_member(member_type, size_key, length_mm, member_name, member_code, member_location, member_notes)
        model = Sketchup.active_model
        info = find_profile_info(size_key)
        
        return UI.messagebox("Error: Invalid size selected.") unless info      # <-- Validate profile info

        length_in_inches = length_mm.mm

        model.start_operation("Create Steel #{member_type}", true)
        begin
            group = create_named_group_for_geometry(model)
            
            # Draw profile based on member type
            if member_type == "RSA"
                face = draw_angle_profile(group.entities, info)                # <-- Draw L-section for angles
            elsif member_type == "SHS"
                face = draw_shs_profile(group.entities, info)                  # <-- Draw hollow section for SHS
            else
                face = draw_i_section_profile(group.entities, info)            # <-- Draw I-section for beams/columns
            end
            
            unless face && face.valid?
                UI.messagebox("Error: Failed to create geometry.")
                model.abort_operation
                return
            end
            face.reverse! if face.normal.z < 0                                 # <-- Ensure correct face orientation
            face.pushpull(length_in_inches)                                    # <-- Extrude to length

            apply_steel_material(group)
            instance = convert_temp_group_to_component(model, size_key, member_type, length_mm)
            unless instance
                UI.messagebox("Error: Could not convert group to DC.")
                model.abort_operation
                return
            end
            
            # Set custom name and location if provided
            if !member_name.nil? && !member_name.empty?
                instance.set_attribute(DA_DICT, "a3_member_name", member_name)
            end
            
            if !member_code.nil? && !member_code.empty?
                instance.set_attribute(DA_DICT, "a4_member_code", member_code)
            end
            
            if !member_location.nil? && !member_location.empty?
                instance.set_attribute(DA_DICT, "a5_member_location", member_location)
            end
            
            if !member_notes.nil? && !member_notes.empty?
                instance.set_attribute(DA_DICT, "a6_member_notes", member_notes)
            end

            if member_type == "Beam"
                rot = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 0, 0), -90.degrees)
                instance.transform!(rot)                                        # <-- Rotate beam to horizontal
            end
            model.commit_operation

            move_member_to_picked_point(instance, member_type)
        rescue => e
            model.abort_operation
            UI.messagebox("Error creating Steel #{member_type}:\n#{e.message}")
            log_error(e)
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | User Interface
    # -----------------------------------------------------------------------------

    # FUNCTION | Create Steel Element Dialog
    # ------------------------------------------------------------
    def self.create_steel_element_dialog
        dialog = UI::HtmlDialog.new(
            dialog_title:    "Noble Architecture | Structural Member Creator",
            preferences_key: "com.noble-architecture.structural-member-creator",
            scrollable:      true,
            resizable:       true,
            width:           625,
            height:          1125,
            style:           UI::HtmlDialog::STYLE_DIALOG
        )
        
        # Get lists of available sizes for each type
        beams   = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalBeams::UNIVERSAL_BEAM_SIZES
        columns = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UniversalColumns::UNIVERSAL_COLUMN_SIZES
        shs     = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_SquareHollowSections::SQUARE_HOLLOW_SECTION_SIZES
        angles  = NA_DATA_LIBRARY_StructuralSteel::NA_HASH_UnequalAngles::UNEQUAL_ANGLE_SIZES
        
        # Convert to JavaScript arrays for the HTML
        beams_js   = beams.keys.sort.map { |k| "\"#{k}\"" }.join(",")
        columns_js = columns.keys.sort.map { |k| "\"#{k}\"" }.join(",")
        shs_js     = shs.keys.sort.map { |k| "\"#{k}\"" }.join(",")
        angles_js  = angles.keys.sort.map { |k| "\"#{k}\"" }.join(",")
        
        # Locate logo path
        plugin_dir = File.dirname(__FILE__)
        logo_path = File.join(plugin_dir, "Na__Common__PluginDependencies", "IMG01__PNG__NaCompanyLogo.png")
        logo_exists = File.exist?(logo_path)
        
        html_content = <<-HTML
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <title>Noble Architecture | Structural Member Creator</title>
                <style>
                /* ========================== STYLE VARIABLES ========================== */
                :root {
                    --na-text-color: #333333;
                    --na-text-secondary: #444444;
                    --na-background: #f8f8f8;
                    --na-primary: #787369;
                    --na-primary-hover: #555041;
                    --na-border-color: #d0d0d0;
                    --na-border-radius: 4px;
                }
                
                body, html {
                    margin: 0;
                    padding: 0;
                    font-family: 'Open Sans', sans-serif;
                }
                
                body {
                    margin: 20px;
                    color: var(--na-text-color);
                    background: var(--na-background);
                    line-height: 1.4;
                }
                
                h2 {
                    font-weight: 600;
                    font-size: 18pt;
                    color: var(--na-text-color);
                    margin: 0;
                }
                
                p {
                    font-size: 10.5pt;
                    color: var(--na-text-secondary);
                    line-height: 1.5;
                    margin-bottom: 20px;
                }
                
                /* Header with logo right, title left */
                .NA_header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding-bottom: 15px;
                    border-bottom: 1px solid #e0e0e0;
                    margin-bottom: 15px;
                }
                
                .NA_logo {
                    height: 40px;
                    width: auto;
                }
                
                .NA_StructuralMember_info {
                    background: #f0f0f0;
                    padding: 15px;
                    border-radius: var(--na-border-radius);
                    margin-bottom: 25px;
                    border-left: 3px solid var(--na-primary);
                }
                
                .NA_form_group {
                    margin-bottom: 15px;
                }
                
                .NA_form_group label {
                    display: block;
                    margin-bottom: 5px;
                    font-weight: 500;
                    font-size: 10.5pt;
                }
                
                .NA_form_group input,
                .NA_form_group select,
                .NA_form_group textarea {
                    width: 280px;
                    padding: 8px;
                    box-sizing: border-box;
                    border: 1px solid var(--na-border-color);
                    border-radius: var(--na-border-radius);
                    font-size: 11pt;
                }
                
                .NA_form_group textarea {
                    width: 100%;
                    resize: vertical;
                }
                
                .NA_error {
                    color: red;
                    margin-top: 5px;
                    display: none;
                }
                
                .NA_StructuralMember_button {
                    background: var(--na-primary);
                    color: #ffffff;
                    border: none;
                    padding: 12px 20px;
                    border-radius: var(--na-border-radius);
                    font-weight: 600;
                    font-size: 11pt;
                    cursor: pointer;
                    margin-top: 10px;
                    transition: all 0.2s ease;
                }
                
                .NA_StructuralMember_button:hover {
                    background: var(--na-primary-hover);
                    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                }
                </style>
            </head>
            <body>
                <div class="NA_header">
                    <h2>Structural Member Creator</h2>
                    #{logo_exists ? "<img src=\"file:///#{logo_path.gsub('\\', '/')}\" class=\"NA_logo\" alt=\"Noble Architecture\">" : ""}
                </div>
                
                <div class="NA_StructuralMember_info">
                    <p>Create structural steel members to precise dimensions. Members are created with BIM metadata</p>
                </div>
                
                <div class="NA_form_group">
                    <label for="member_type">Member Type:</label>
                    <select id="member_type" class="NA_input_medium" onchange="updateSizesDropdown()">
                        <option value="Beam">Beam</option>
                        <option value="Column">Column</option>
                        <option value="SHS">Square Hollow Section</option>
                        <option value="RSA">Rolled Steel Angle</option>
                    </select>
                </div>
                
                <div class="NA_form_group">
                    <label for="size_key">Profile Size:</label>
                    <select id="size_key" class="NA_input_medium">
                        <!-- Options will be populated by JavaScript -->
                    </select>
                </div>
                
                <div class="NA_form_group">
                    <label for="length_mm">Length (mm):</label>
                    <input type="number" id="length_mm" class="NA_input_medium" value="3000" min="100">
                    <div id="length_error" class="NA_error">Length must be at least 100mm.</div>
                </div>
                
                <div class="NA_form_group">
                    <label for="member_name">Member Name (optional):</label>
                    <input type="text" id="member_name" class="NA_input_medium" placeholder="e.g. B01">
                </div>
                
                <div class="NA_form_group">
                    <label for="member_code">Member Code (optional):</label>
                    <input type="text" id="member_code" class="NA_input_medium" placeholder="e.g. STL-001">
                </div>
                
                <div class="NA_form_group">
                    <label for="member_location">Member Location (optional):</label>
                    <input type="text" id="member_location" class="NA_input_medium" placeholder="e.g. First Floor">
                </div>
                
                <div class="NA_form_group">
                    <label for="member_notes">Notes (optional):</label>
                    <textarea id="member_notes" class="NA_input_medium" rows="3" placeholder="Additional information about this structural member"></textarea>
                </div>
                
                <button class="NA_StructuralMember_button" onclick="createStructuralMember()">Create Structural Member</button>
                
                <script>
                    // Define available sizes
                    const beamSizes = [#{beams_js}];
                    const columnSizes = [#{columns_js}];
                    const shsSizes = [#{shs_js}];
                    const angleSizes = [#{angles_js}];
                    
                    // Populate size dropdown based on selected member type
                    function updateSizesDropdown() {
                        const memberType = document.getElementById('member_type').value;
                        const sizeDropdown = document.getElementById('size_key');
                        
                        // Clear existing options
                        sizeDropdown.innerHTML = '';
                        
                        // Get appropriate sizes based on member type
                        let sizes = [];
                        
                        if (memberType === 'Beam') {
                            sizes = beamSizes;
                        } else if (memberType === 'Column') {
                            sizes = columnSizes;
                        } else if (memberType === 'SHS') {
                            sizes = shsSizes;
                        } else if (memberType === 'RSA') {
                            sizes = angleSizes;
                        }
                        
                        // Add options to dropdown
                        sizes.forEach(size => {
                            const option = document.createElement('option');
                            option.value = size;
                            option.textContent = size;
                            sizeDropdown.appendChild(option);
                        });
                    }
                    
                    // Initialize dropdown on page load
                    window.onload = function() {
                        updateSizesDropdown();
                        document.getElementById('length_error').style.display = 'none';
                    };
                    
                    // Create structural member
                    function createStructuralMember() {
                        // Get form values
                        const memberType = document.getElementById('member_type').value;
                        const sizeKey = document.getElementById('size_key').value;
                        const lengthMm = parseFloat(document.getElementById('length_mm').value);
                        const memberName = document.getElementById('member_name').value;
                        const memberCode = document.getElementById('member_code').value;
                        const memberLocation = document.getElementById('member_location').value;
                        const memberNotes = document.getElementById('member_notes').value;
                        
                        // Validate length
                        if (isNaN(lengthMm) || lengthMm < 100) {
                            document.getElementById('length_error').style.display = 'block';
                            return;
                        }
                        document.getElementById('length_error').style.display = 'none';
                        
                        // Call Ruby function to create structural member
                        sketchup.createStructuralMember(
                            memberType,
                            sizeKey,
                            lengthMm,
                            memberName,
                            memberCode,
                            memberLocation,
                            memberNotes
                        );
                    }
                </script>
            </body>
            </html>
        HTML
        
        dialog.set_html(html_content)
        
        dialog.add_action_callback("createStructuralMember") do |action_context, member_type, size_key, length_mm, member_name, member_code, member_location, member_notes|
            create_structural_member(member_type, size_key, length_mm.to_f, member_name, member_code, member_location, member_notes)
        end
        
        dialog.show
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Run Structural Member Creator (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts
    # Method name: Na__GenerateStructuralElement.Na__GenerateStructuralElement__Run
    # ------------------------------------------------------------
    def self.Na__GenerateStructuralElement__Run
        model = Sketchup.active_model                                           # <-- Get active model
        return unless model                                                      # <-- Exit if no active model

        create_steel_element_dialog                                              # <-- Show creation dialog
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Menu Registration
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Menu and Commands
    # ------------------------------------------------------------
    def self.install_menu_and_commands
        return if @menu_installed                                                # <-- Exit if already installed

        # Create UI command
        cmd = UI::Command.new('NA_GenerateStructuralElement') do                # <-- Create command
            Na__GenerateStructuralElement.Na__GenerateStructuralElement__Run     # <-- Run logic
        end
        cmd.tooltip = "Create Structural Member"                                 # <-- Tooltip
        cmd.status_bar_text = "Create structural steel members (beams, columns, SHS)"  # <-- Status bar
        cmd.menu_text = "Na__GenerateStructuralElement"                         # <-- Menu text

        # Add to Plugins menu
        UI.menu('Plugins').add_item(cmd)                                        # <-- Add item

        @menu_installed = true                                                  # <-- Mark installed
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate for Model
    # ------------------------------------------------------------
    def self.activate_for_model(model)
        install_menu_and_commands                                               # <-- Install commands
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Module

# -----------------------------------------------------------------------------
# FILE LOADED CHECK
# -----------------------------------------------------------------------------
unless file_loaded?(__FILE__)
    Na__GenerateStructuralElement.activate_for_model(Sketchup.active_model)     # <-- Activate
    file_loaded(__FILE__)                                                       # <-- Mark loaded
end

