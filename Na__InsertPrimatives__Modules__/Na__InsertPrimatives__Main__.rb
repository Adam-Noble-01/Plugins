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
# - Na__InsertPrimatives__PlaneMode__               : Rectangle mode parsing, preview, and camera-aligned plane creation
# - Na__InsertPrimatives__RightClickPopup__         : HtmlDialog right-click primitive menu
# - Na__InsertPrimatives__KeyboardHandlers__        : Key bindings, VCB callbacks, status text
# - Na__InsertPrimatives__DrawnGridSnap__           : Shared voxel lattice, plane axis maths, persisted settings
# - Na__InsertPrimatives__DrawnVcbArithmetic__      : VCB parsing with relative (+/-) arithmetic
# - Na__InsertPrimatives__DrawnPreviewGraphics__    : Shaded face previews and live dimension labels
# - Na__InsertPrimatives__DrawnGeometry__           : Drawn plane / volume group creation and rebuild
# - Na__InsertPrimatives__DrawnToolShared__         : Drag state machine shared by both drag tools
# - Na__InsertPrimatives__DrawnPlaneTool__          : Click-and-drag rectangle primitive
# - Na__InsertPrimatives__DrawnVolumeTool__         : Click-and-drag box primitive
# - Na__InsertPrimatives__DrawnCylinderTool__       : Click-and-drag cylinder primitive (centre anchored)
# - Na__InsertPrimatives__DrawnRoofGeometry__       : Ridge maths, pitch conversion, roof solid construction
# - Na__InsertPrimatives__DrawnRoofTools__          : Click-and-drag pitched and hipped roof primitives
# - Na__InsertPrimatives__DrawnDeepPick__           : Deep nested face picking and instance transformation maths
# - Na__InsertPrimatives__DrawnSlopePush__          : SHIFT pushes along the neighbouring face's plane, not the normal
# - Na__InsertPrimatives__DrawnPushPullTool__       : Push/pull any face at any nesting depth (3D camera)
# - Na__InsertPrimatives__DrawnEdgeLoops__          : Inward quad drag cuts an inset edge loop instead of shortening
# - Na__InsertPrimatives__DrawnPushPull2dTool__     : The same push/pull for a parallel camera, picked through an edge
# - Na__InsertPrimatives__DrawnChamferTool__        : Chamfer any edge at any nesting depth
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__UserInput__VcbFunctions__'
require_relative 'Na__InsertPrimatives__3dPreviewGraphics__'
require_relative 'Na__InsertPrimatives__PlaneMode__'
require_relative 'Na__InsertPrimatives__RightClickPopup__'
require_relative 'Na__InsertPrimatives__KeyboardHandlers__'
require_relative 'Na__InsertPrimatives__DrawnGridSnap__'
require_relative 'Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative 'Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnGeometry__'
require_relative 'Na__InsertPrimatives__DrawnToolShared__'
require_relative 'Na__InsertPrimatives__DrawnPlaneTool__'
require_relative 'Na__InsertPrimatives__DrawnVolumeTool__'
require_relative 'Na__InsertPrimatives__DrawnRoofGeometry__'
require_relative 'Na__InsertPrimatives__DrawnCylinderTool__'
require_relative 'Na__InsertPrimatives__DrawnDeepPick__'
require_relative 'Na__InsertPrimatives__DrawnSlopePush__'
require_relative 'Na__InsertPrimatives__DrawnRoofTools__'
require_relative 'Na__InsertPrimatives__DrawnPushPullTool__'
require_relative 'Na__InsertPrimatives__DrawnEdgeLoops__'
require_relative 'Na__InsertPrimatives__DrawnPushPull2dTool__'
require_relative 'Na__InsertPrimatives__DrawnChamferTool__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Helper Functions
    # -----------------------------------------------------------------------------

    # FUNCTION | Round Point to the Shared Voxel Grid Coordinate
    # ------------------------------------------------------------
    # Delegates to Na__DrawnGrid__SnapPoint so the click-to-place tool and the
    # click-and-drag tools are guaranteed to land on the *same* lattice — a
    # separate copy of the rounding maths here would drift the moment the snap
    # step or the drawing axes changed. Behaviour with the default axes and the
    # default 5mm step is identical to the original world-space rounding.
    # ------------------------------------------------------------
    def self.round_point_to_nearest_5mm(pt)
        Na__InsertPrimatives.Na__DrawnGrid__SnapPoint(pt)
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
        include Na__InsertPrimatives::PrimitiveModeSwitching

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            @ip                   = Sketchup::InputPoint.new
            @cursor_pos           = nil
            @crosshair_size       = 300.mm
            @primitive_mode       = :cube
            @plane_faces_enabled  = Na__InsertPrimatives.Na__DrawnSettings__PlaneFacesEnabled?
            @cube_size_x          = 1000.mm
            @cube_size_y          = 1000.mm
            @cube_size_z          = 1000.mm
            @rotation_step        = 0
            @key_tab_held         = false
            @last_cube_group      = nil
            @last_corner_position = nil
            @last_plane_group     = nil
            @last_plane_position  = nil
            @last_rotation_state  = 0
            @na_exit_scheduled    = false
            @na_context_click_x   = 0
            @na_context_click_y   = 0
            @na_popup_menu_scheduled = false
        end
        # ---------------------------------------------------------------

        # ACTIVATE | Called when tool is activated
        # ------------------------------------------------------------
        def activate
            puts "\n"
            puts "----------------------------------------"
            puts "PRIMITIVE TOOL ACTIVATED"
            puts "Default mode: Cube"
            puts "Click to place primitive (snaps to 5mm grid)"
            puts "TAB to rotate 90 degrees around Z axis"
            puts "VCB mode switch: '..' + Enter => Plane mode"
            puts "Cube VCB: single value (all sides) or X,Y,Z"
            puts "Plane VCB: single value or X,Y"
            puts "Units: mm cm m (bare number = mm)"
            puts "Example: 1m  |  2000,4000,100  |  2m,4m,100mm  |  ..  |  1m,600mm"
            puts "Default: 1000mm x 1000mm x 1000mm"
            puts "Right-click for Drawn Plane / Drawn Volume click-and-drag modes"
            puts "Snap grid: #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            puts "----------------------------------------"
            na_key__update_status_text()
            Na__PrimitiveMode__RefreshVcbDisplay()
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Refresh View When Another Tool Is Selected
        # ------------------------------------------------------------
        def deactivate(view)
            Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # RESUME | Called when tool is resumed
        # ------------------------------------------------------------
        def resume(view)
            view.invalidate
            na_key__update_status_text()
            Na__PrimitiveMode__RefreshVcbDisplay()
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

            if @primitive_mode == :plane
                Na__InsertPrimatives.Na__PlaneMode__DrawPlanePreview(view, snapped, @cube_size_x, @cube_size_y, @rotation_step)
            else
                Na__InsertPrimatives.Na__Preview__DrawCubeBox(view, snapped, @cube_size_x, @cube_size_y, @cube_size_z, @rotation_step)
            end
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Create cube geometry at click position
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @ip.pick(view, x, y)
            position = @ip.position

            if position
                if @primitive_mode == :plane
                    plane_group, plane_corner = Na__InsertPrimatives.Na__PlaneMode__CreatePlaneGeometry(
                        position,
                        @cube_size_x,
                        @cube_size_y,
                        view,
                        @rotation_step,
                        @plane_faces_enabled
                    )

                    if plane_group
                        @last_plane_group    = plane_group
                        @last_plane_position = plane_corner
                        @last_rotation_state = @rotation_step
                        @last_cube_group     = nil
                    end
                else
                    Na__Primitive__CreateCubeGeometry(position)
                end
            end
        end
        # ---------------------------------------------------------------

        # GET MENU | Schedule HtmlDialog Popup Without Adding Native Items
        # ------------------------------------------------------------
        def getMenu(menu, *args)
            puts "PRIMITIVE TOOL RIGHT CLICK MENU REQUESTED (args=#{args.length})"
            Na__PrimitiveMode__ScheduleRightClickPopupFromMenuArgs(args)
            nil
        end
        # ---------------------------------------------------------------

        # ON RIGHT BUTTON DOWN | Track Right-Click Coordinates
        # ------------------------------------------------------------
        def onRButtonDown(flags, x, y, view)
            @na_context_click_x = x
            @na_context_click_y = y
            false
        end
        # ---------------------------------------------------------------

        # ON RIGHT BUTTON UP | Fallback Popup When Native Context Menu Is Missing
        # ------------------------------------------------------------
        def onRButtonUp(flags, x, y, view)
            @na_context_click_x = x
            @na_context_click_y = y
            Na__PrimitiveMode__ScheduleRightClickPopup(x, y)
            false
        end
        # ---------------------------------------------------------------

        # ON CANCEL | Exit Tool When Escape Is Pressed
        # ------------------------------------------------------------
        def onCancel(reason, view)
            if reason == 0
                Na__PrimitiveMode__ScheduleExitTool()
            else
                view.invalidate if view
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch Tool State to Cube Mode
        # ------------------------------------------------------------
        def Na__PrimitiveMode__SetCubeMode
            @primitive_mode = :cube
            Na__PrimitiveMode__RefreshVcbDisplay()
            na_key__update_status_text()
            Sketchup.active_model.active_view.invalidate
            Sketchup::set_status_text("Mode switched: Cube", SB_PROMPT)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch Tool State to Plane Mode
        # ------------------------------------------------------------
        def Na__PrimitiveMode__SetPlaneMode
            @primitive_mode = :plane
            Na__PrimitiveMode__RefreshVcbDisplay()
            na_key__update_status_text()
            Sketchup.active_model.active_view.invalidate
            Na__InsertPrimatives.Na__PlaneMode__ShowModePrompt()
        end
        # ---------------------------------------------------------------

        # FUNCTION | Toggle Plane Face Creation
        # The preference lives at module level so it survives switching between
        # this tool and the click-and-drag tools, and between sessions.
        # ------------------------------------------------------------
        def Na__PrimitiveMode__TogglePlaneFaces
            @plane_faces_enabled = Na__InsertPrimatives.Na__DrawnSettings__SetPlaneFacesEnabled(
                !Na__InsertPrimatives.Na__DrawnSettings__PlaneFacesEnabled?
            )

            view = Sketchup.active_model.active_view
            view.invalidate if view

            state_label = @plane_faces_enabled ? "enabled" : "disabled"
            Sketchup::set_status_text("Plane faces #{state_label}", SB_PROMPT)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Plane Face Creation Enabled?
        # ------------------------------------------------------------
        def Na__PrimitiveMode__PlaneFacesEnabled?
            @plane_faces_enabled = Na__InsertPrimatives.Na__DrawnSettings__PlaneFacesEnabled?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Primitive Mode Is Running (Popup Highlight)
        # ------------------------------------------------------------
        def Na__DrawnMode__ActiveModeKey
            @primitive_mode == :plane ? :plane : :cube
        end
        # ---------------------------------------------------------------

        # FUNCTION | Schedule Right Click Popup Fallback
        # ------------------------------------------------------------
        def Na__PrimitiveMode__ScheduleRightClickPopup(x, y)
            return if @na_popup_menu_scheduled

            @na_popup_menu_scheduled = true

            UI.start_timer(0.05, false) do
                begin
                    puts "PRIMITIVE RIGHT CLICK POPUP FALLBACK REQUESTED"
                    Na__InsertPrimatives.Na__RightClickPopup__ShowPrimitiveMenu(self, x, y)
                ensure
                    @na_popup_menu_scheduled = false
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Schedule Right Click Popup From getMenu Arguments
        # ------------------------------------------------------------
        def Na__PrimitiveMode__ScheduleRightClickPopupFromMenuArgs(args)
            if args.length >= 4
                x = args[1]
                y = args[2]
            else
                x = @na_context_click_x
                y = @na_context_click_y
            end

            Na__PrimitiveMode__ScheduleRightClickPopup(x, y)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Exit Primitive Tool
        # ------------------------------------------------------------
        def Na__PrimitiveMode__ExitTool
            Sketchup.active_model.select_tool(nil)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Schedule Safe Exit from Active Tool
        # ------------------------------------------------------------
        def Na__PrimitiveMode__ScheduleExitTool
            return if @na_exit_scheduled
            @na_exit_scheduled = true

            UI.start_timer(0, false) do
                begin
                    model = Sketchup.active_model
                    model.select_tool(nil) if model
                ensure
                    @na_exit_scheduled = false
                end
            end
        end
        # ---------------------------------------------------------------

        private

        # FUNCTION | Update VCB Display for Active Primitive Mode
        # ------------------------------------------------------------
        def Na__PrimitiveMode__RefreshVcbDisplay
            if @primitive_mode == :plane
                Na__InsertPrimatives.Na__PlaneMode__UpdateVcbDisplay(@cube_size_x, @cube_size_y)
            else
                Na__InsertPrimatives.Na__VcbInput__UpdateDisplay(@cube_size_x, @cube_size_y, @cube_size_z)
            end
        end
        # ---------------------------------------------------------------

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

        # FUNCTION | Rebuild Plane with New Dimensions at Same Corner Position
        # ------------------------------------------------------------
        def Na__PrimitiveMode__RegeneratePlane(plane_group, corner_position, view)
            return unless plane_group && plane_group.valid?

            model = Sketchup.active_model

            model.start_operation('Regenerate Primitive Plane', true)

            plane_group.transformation = Geom::Transformation.new
            plane_group.entities.clear!

            p0, p1, p2, p3 = Na__InsertPrimatives.Na__PlaneMode__BuildPlaneCorners(
                corner_position,
                @cube_size_x,
                @cube_size_y,
                view,
                @last_rotation_state
            )

            plane_geometry = Na__InsertPrimatives.Na__PlaneMode__AddPlaneEntities(
                plane_group.entities,
                [p0, p1, p2, p3],
                view,
                @plane_faces_enabled
            )

            unless plane_geometry
                model.abort_operation
                UI.beep
                Sketchup::set_status_text("Plane regeneration failed", SB_PROMPT)
                return
            end

            model.commit_operation

            puts "\n"
            puts "----------------------------------------"
            puts "PRIMITIVE PLANE REGENERATED"
            puts "New Size: #{@cube_size_x.to_mm.round}mm x #{@cube_size_y.to_mm.round}mm"
            puts "Faces: #{@plane_faces_enabled ? 'Enabled' : 'Disabled'}"
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
            @last_plane_group     = nil
            @last_plane_position  = nil

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
