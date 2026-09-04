# =============================================================================
# NA INSERT PRIMATIVES - APPCORE MODE SWITCH
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppCore__ModeSwitch__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Activate any primitive tool and share the popup mode-switch mixin
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Tool Activation Helpers (Module Level)
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Original Cube / Plane Placement Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateCubeTool(sub_mode = :cube)
        model = Sketchup.active_model
        return nil unless model

        tool = PrimitiveCubeTool.new
        model.select_tool(tool)
        tool.Na__PrimitiveMode__SetPlaneMode() if sub_mode == :plane
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Drawn Plane Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnPlaneTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnPlaneTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Drawn Volume Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnVolumeTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnVolumeTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Drawn Cylinder Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnCylinderTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnCylinderTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Deep Push/Pull Tool the Camera Calls For
    # ------------------------------------------------------------
    # ONE entry point, two tools. The menu item, the keyboard shortcut and the
    # right-click popup all arrive here, so asking the camera in this one place
    # is what makes the 2D/3D split invisible to the user — there is no second
    # button to find and no second shortcut to remember.
    #
    # A perspective camera gets DrawnPushPullTool, which is untouched and still
    # does all the work. A parallel camera gets DrawnPushPull2dTool, its
    # subclass, which inverts the pick so an edge grabs the wall standing behind
    # it. The 2D module loads after this file, so the class is looked up at call
    # time and the 3D tool is the fallback if it is missing.
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnPushPullTool
        model = Sketchup.active_model
        return nil unless model

        tool =
            if defined?(Na__InsertPrimatives::DrawnPushPull2dTool)
                Na__InsertPrimatives.Na__PushPull2d__NewToolForCamera(model)
            else
                DrawnPushPullTool.new
            end

        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Deep Chamfer Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnChamferTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnChamferTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Pitched Roof Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnPitchedRoofTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnPitchedRoofTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Click-and-Drag Hipped Roof Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnHippedRoofTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnHippedRoofTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | Primitive Mode Switching — Mixed Into Every Tool In The Plugin
    # =============================================================================

    module PrimitiveModeSwitching

        # FUNCTION | Switch to the Click-and-Drag Drawn Plane Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetDrawnPlaneMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPlaneTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Drawn Volume Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetDrawnVolumeMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnVolumeTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Drawn Cylinder Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetDrawnCylinderMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnCylinderTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Pitched Roof Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetPitchedRoofMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPitchedRoofTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Click-and-Drag Hipped Roof Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetHippedRoofMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnHippedRoofTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Deep Push/Pull Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetPushPullMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPushPullTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Deep Chamfer Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetChamferMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnChamferTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Advance the Circle Segment Count to the Next Value
        # ------------------------------------------------------------
        def Na__DrawnMode__CycleCircleSegments
            count = Na__InsertPrimatives.Na__DrawnSettings__CycleCircleSegments

            view = Sketchup.active_model ? Sketchup.active_model.active_view : nil
            view.invalidate if view

            Sketchup::set_status_text("Circle segments: #{count}", SB_PROMPT)
            count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Current Circle Segment Count for Menu Display
        # ------------------------------------------------------------
        def Na__DrawnMode__CircleSegmentsLabel
            Na__InsertPrimatives.Na__DrawnSettings__CircleSegments.to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Advance the Shared Snap Grid to the Next Step
        # ------------------------------------------------------------
        def Na__DrawnMode__CycleGridStep
            Na__InsertPrimatives.Na__DrawnSettings__CycleGridStepMm
            label = Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel

            view = Sketchup.active_model ? Sketchup.active_model.active_view : nil
            view.invalidate if view

            Sketchup::set_status_text("Snap grid: #{label}", SB_PROMPT)
            label
        end
        # ---------------------------------------------------------------

        # FUNCTION | Current Snap Grid Label for Menu Display
        # ------------------------------------------------------------
        def Na__DrawnMode__GridStepLabel
            Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel
        end
        # ---------------------------------------------------------------

    end # End PrimitiveModeSwitching module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF APPCORE MODE SWITCH
# =============================================================================
