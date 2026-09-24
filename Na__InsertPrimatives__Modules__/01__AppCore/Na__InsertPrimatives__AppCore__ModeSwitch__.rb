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

    # FUNCTION | Activate the Drawn Staircase Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnStairTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnStairTool.new
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

    # FUNCTION | Activate the Deep Ogee Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnOgeeTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnOgeeTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Deep Fillet Tool
    # ------------------------------------------------------------
    def self.Na__ModeSwitch__ActivateDrawnFilletTool
        model = Sketchup.active_model
        return nil unless model

        tool = DrawnFilletTool.new
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

        # FUNCTION | Switch to the Drawn Staircase Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetStairMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnStairTool
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

        # FUNCTION | Switch to the Deep Ogee Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetOgeeMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnOgeeTool
        end
        # ---------------------------------------------------------------

        # FUNCTION | Switch to the Deep Fillet Tool
        # ------------------------------------------------------------
        def Na__DrawnMode__SetFilletMode
            Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnFilletTool
        end
        # ---------------------------------------------------------------

        # -----------------------------------------------------------------------------
        # REGION | Tool Options Submenu Interface
        # -----------------------------------------------------------------------------
        #
        # The popup asks every running tool for its options and renders whatever
        # comes back as an indented block under that tool's own button. A tool
        # with nothing declared in NA_TOOL_OPTIONS answers with an empty list and
        # the menu is exactly as short as it was before — which is the point:
        # options live under the tool in use, not in one growing list everybody
        # has to scroll past.
        #
        # Both methods are here rather than in each tool because the answer is
        # the same for all of them: look up this tool's mode key in the table.

        # FUNCTION | This Tool's Options, Described for the Popup
        # ------------------------------------------------------------
        def Na__DrawnMode__ToolOptions
            Na__InsertPrimatives.Na__ToolOptions__Describe(self.Na__DrawnMode__ActiveModeKey)
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Flip One Option and Hand Back Its New Caption
        # ------------------------------------------------------------
        # Returns the caption so the popup can rewrite its own button without
        # closing, the way the grid step and the segment count already do. An
        # option is a modelling decision, and reopening the menu to make the
        # next one would make a pair of them feel like a chore.
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            state   = Na__InsertPrimatives.Na__ToolOptions__Toggle(option_id)
            caption = Na__InsertPrimatives.Na__ToolOptions__CaptionFor(option_id)

            view = Sketchup.active_model ? Sketchup.active_model.active_view : nil
            view.invalidate if view

            Sketchup::set_status_text(caption, SB_PROMPT)
            { :caption => caption, :enabled => state }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


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
