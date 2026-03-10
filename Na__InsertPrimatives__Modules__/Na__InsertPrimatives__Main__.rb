# =============================================================================
# NA INSERT PRIMATIVES - MAIN MODULE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__Main__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Core tool logic for the Insert Primatives plugin
# CREATED    : 2026
#
# DESCRIPTION:
# - Defines the Na__InsertPrimatives module
# - PrimitiveCubeTool interactive placement class
# - Grid snapping helper
# - Entry point method for tool activation
#
# MODULE ARCHITECTURE:
# - Na__InsertPrimatives__UserInput__VcbFunctions__ : VCB parsing and unit conversion
# - Na__InsertPrimatives__3dPreviewGraphics__       : Crosshair and wireframe preview rendering
# - Na__InsertPrimatives__KeyboardHandlers__        : Key bindings, VCB callbacks, status text
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__UserInput__VcbFunctions__'
require_relative 'Na__InsertPrimatives__3dPreviewGraphics__'
require_relative 'Na__InsertPrimatives__KeyboardHandlers__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Helper Functions
    # -----------------------------------------------------------------------------

    # FUNCTION | Round Point to Nearest 5mm Grid Coordinate
    # ------------------------------------------------------------
    def self.round_point_to_nearest_5mm(pt)
        mm_inch = 25.4
        step    = 5.0
        x_mm    = pt.x * mm_inch
        y_mm    = pt.y * mm_inch
        z_mm    = pt.z * mm_inch

        rx = (x_mm / step).round * step
        ry = (y_mm / step).round * step
        rz = (z_mm / step).round * step

        Geom::Point3d.new(rx / mm_inch, ry / mm_inch, rz / mm_inch)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Primitive Cube Interactive Placement Tool
    # ------------------------------------------------------------
    class PrimitiveCubeTool

        include Na__InsertPrimatives::KeyboardHandlers

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip                   = Sketchup::InputPoint.new
            @cursor_pos           = nil
            @crosshair_size       = 300.mm
            @cube_size_x          = 1000.mm
            @cube_size_y          = 1000.mm
            @cube_size_z          = 1000.mm
            @rotation_step        = 0
            @key_tab_held         = false
            @last_cube_group      = nil
            @last_corner_position = nil
            @last_rotation_state  = 0
        end
        # ---------------------------------------------------------------

        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            puts "\n"
            puts "----------------------------------------"
            puts "PRIMITIVE CUBE TOOL ACTIVATED"
            puts "Click to place cube (snaps to 5mm grid)"
            puts "TAB to rotate 90 degrees around Z axis"
            puts "VCB: single value (all sides) or X,Y,Z"
            puts "Units: mm cm m (bare number = mm)"
            puts "Example: 1m  |  2000,4000,100  |  2m,4m,100mm"
            puts "Default: 1000mm x 1000mm x 1000mm"
            puts "----------------------------------------"
            na_key__update_status_text()
            Na__InsertPrimatives.Na__VcbInput__UpdateDisplay(@cube_size_x, @cube_size_y, @cube_size_z)
        end
        # ---------------------------------------------------------------

        # RESUME | Called when tool is resumed
        # ------------------------------------------------------------
        def resume(view)
            view.invalidate
            na_key__update_status_text()
            Na__InsertPrimatives.Na__VcbInput__UpdateDisplay(@cube_size_x, @cube_size_y, @cube_size_z)
        end
        # ---------------------------------------------------------------

        # ON MOUSE MOVE | Track cursor position with snapping
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            @ip.pick(view, x, y)
            @cursor_pos = @ip.position
            view.invalidate
        end
        # ---------------------------------------------------------------

        # DRAW | Render crosshair and ghost cube preview at cursor position
        # ------------------------------------------------------------
        def draw(view)
            return unless @cursor_pos

            @ip.draw(view)
            snapped = Na__InsertPrimatives.round_point_to_nearest_5mm(@cursor_pos)
            Na__InsertPrimatives.Na__Preview__DrawCrosshair(view, @cursor_pos, @crosshair_size)
            Na__InsertPrimatives.Na__Preview__DrawCubeBox(view, snapped, @cube_size_x, @cube_size_y, @cube_size_z, @rotation_step)
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Create cube geometry at click position
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)
            position = @ip.position

            if position
                Na__Primitive__CreateCubeGeometry(position)
            end
        end
        # ---------------------------------------------------------------

        private

        # FUNCTION | Rebuild Cube with New Dimensions at Same Corner Position
        # ------------------------------------------------------------
        def Na__Primitive__RegenerateCube(cube_group, corner_position)
            return unless cube_group && cube_group.valid?

            model = Sketchup.active_model

            model.start_operation('Regenerate Primitive Cube', true)

            cube_group.transformation = Geom::Transformation.new
            cube_group.entities.clear!

            p0, p1, p2, p3 = Na__InsertPrimatives.Na__Preview__BuildCubeCorners(corner_position, @cube_size_x, @cube_size_y, @last_rotation_state)

            face = cube_group.entities.add_face(p0, p1, p2, p3)
            face.reverse! if face.normal.z < 0
            face.pushpull(@cube_size_z)

            model.commit_operation

            puts "\n"
            puts "----------------------------------------"
            puts "PRIMITIVE CUBE REGENERATED"
            puts "New Size: #{@cube_size_x.to_mm.round}mm x #{@cube_size_y.to_mm.round}mm x #{@cube_size_z.to_mm.round}mm"
            puts "Rotation: #{Na__InsertPrimatives::KeyboardHandlers::NA_ROTATION_STEPS[@last_rotation_state]}°"
            puts "----------------------------------------"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Cube Geometry at Specified Click Position
        # ------------------------------------------------------------
        def Na__Primitive__CreateCubeGeometry(click_point)
            model    = Sketchup.active_model
            entities = model.active_entities

            model.start_operation('Insert Primitive Cube', true)

            snapped_corner = Na__InsertPrimatives.round_point_to_nearest_5mm(click_point)

            p0, p1, p2, p3 = Na__InsertPrimatives.Na__Preview__BuildCubeCorners(snapped_corner, @cube_size_x, @cube_size_y, @rotation_step)

            cube_group      = entities.add_group
            cube_group.name = "01__PrimitiveCube"

            face = cube_group.entities.add_face(p0, p1, p2, p3)
            face.reverse! if face.normal.z < 0
            face.pushpull(@cube_size_z)

            @last_cube_group      = cube_group
            @last_corner_position = snapped_corner
            @last_rotation_state  = @rotation_step

            model.commit_operation

            puts "\n"
            puts "----------------------------------------"
            puts "PRIMITIVE CUBE CREATED"
            puts "Corner: X=#{snapped_corner.x.to_mm.round(2)}mm, Y=#{snapped_corner.y.to_mm.round(2)}mm, Z=#{snapped_corner.z.to_mm.round(2)}mm"
            puts "Size: #{@cube_size_x.to_mm.round}mm x #{@cube_size_y.to_mm.round}mm x #{@cube_size_z.to_mm.round}mm"
            puts "Rotation: #{Na__InsertPrimatives::KeyboardHandlers::NA_ROTATION_STEPS[@rotation_step]}°"
            puts "----------------------------------------"
        end
        # ---------------------------------------------------------------

    end # End PrimitiveCubeTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Insert Primitive Cube (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts to activate the tool
    # Method name: Na__InsertPrimatives.Na__InsertPrimatives__InsertCube
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__InsertCube
        model = Sketchup.active_model
        return unless model

        model.select_tool(PrimitiveCubeTool.new)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF MAIN MODULE
# =============================================================================
