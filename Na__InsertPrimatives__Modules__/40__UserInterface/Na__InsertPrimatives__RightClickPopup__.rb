# =============================================================================
# NA INSERT PRIMATIVES - RIGHT CLICK POPUP
# =============================================================================
#
# FILE       : Na__InsertPrimatives__RightClickPopup__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Reliable primitive menu fallback for empty viewport right-clicks
# CREATED    : 2026
#
# DESCRIPTION:
# - One popup serves every primitive tool in the plugin. The running mode is highlighted.
# - Switching between the click-to-place tool and the click-and-drag tools swaps
#   the active SketchUp tool, which is why all of them implement the same small
#   menu interface (see Na__InsertPrimatives::PrimitiveModeSwitching).
# - The snap grid button cycles in place without closing the popup, so stepping
#   from 5mm to 100mm does not need four trips through the context menu.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Popup Sizing Constants
    # -----------------------------------------------------------------------------

    NA_POPUP_WIDTH            = 216
    NA_POPUP_FALLBACK_HEIGHT  = 560                                           # <-- Opens generous, then shrinks to fit
    NA_POPUP_CHROME_ALLOWANCE = 52                                            # <-- Title bar plus clear space under the last button

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Popup Lifecycle
    # -----------------------------------------------------------------------------

    # FUNCTION | Show Primitive Popup Menu
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ShowPrimitiveMenu(tool_instance, x, y)
        Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()

        @na_right_click_popup = UI::HtmlDialog.new(
            dialog_title: "Primitive Menu",
            preferences_key: "Na__InsertPrimatives__RightClickPopup",
            scrollable: false,
            resizable: false,
            width: NA_POPUP_WIDTH,
            height: NA_POPUP_FALLBACK_HEIGHT,
            style: UI::HtmlDialog::STYLE_UTILITY
        )

        @na_right_click_popup.set_html(Na__InsertPrimatives.Na__RightClickPopup__BuildHtml(tool_instance))
        Na__InsertPrimatives.Na__RightClickPopup__InstallCallbacks(@na_right_click_popup, tool_instance)
        @na_right_click_popup.set_position(x.to_i + 20, y.to_i + 20)
        @na_right_click_popup.show
        @na_right_click_popup.bring_to_front
    end
    # ---------------------------------------------------------------


    # FUNCTION | Read the Active Mode Key from Any Primitive Tool
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ActiveModeKey(tool_instance)
        return nil unless tool_instance.respond_to?(:Na__DrawnMode__ActiveModeKey)

        tool_instance.Na__DrawnMode__ActiveModeKey
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------


    # FUNCTION | Read the Current Snap Grid Label
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__GridLabel(tool_instance)
        if tool_instance.respond_to?(:Na__DrawnMode__GridStepLabel)
            return tool_instance.Na__DrawnMode__GridStepLabel
        end

        Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel
    rescue StandardError
        '5mm'
    end
    # ---------------------------------------------------------------


    # FUNCTION | Read the Current Circle Segment Count
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__SegmentsLabel(tool_instance)
        if tool_instance.respond_to?(:Na__DrawnMode__CircleSegmentsLabel)
            return tool_instance.Na__DrawnMode__CircleSegmentsLabel
        end

        Na__InsertPrimatives.Na__DrawnSettings__CircleSegments.to_s
    rescue StandardError
        '24'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # @delegate: Na__InsertPrimatives__RightClickPopup__Html__.rb


    # -----------------------------------------------------------------------------
    # REGION | Dialog Callbacks
    # -----------------------------------------------------------------------------

    # FUNCTION | Install Primitive Popup Callbacks
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__InstallCallbacks(dialog, tool_instance)
        # Fired once the page has laid out, so the window ends up exactly as tall
        # as its buttons need plus clear space at the base.
        dialog.add_action_callback("reportContentHeight") do |_action_context, content_height|
            begin
                measured = content_height.to_i
                dialog.set_size(NA_POPUP_WIDTH, measured + NA_POPUP_CHROME_ALLOWANCE) if measured > 0
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP RESIZE FAILED: #{error.message}"
            end
        end

        dialog.add_action_callback("setCubeMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__SetCubeMode()
            end
        end

        dialog.add_action_callback("setPlaneMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__SetPlaneMode()
            end
        end

        dialog.add_action_callback("setDrawnPlaneMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetDrawnPlaneMode()
            end
        end

        dialog.add_action_callback("setDrawnVolumeMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetDrawnVolumeMode()
            end
        end

        dialog.add_action_callback("setDrawnCylinderMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetDrawnCylinderMode()
            end
        end

        dialog.add_action_callback("setPitchedRoofMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetPitchedRoofMode()
            end
        end

        dialog.add_action_callback("setHippedRoofMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetHippedRoofMode()
            end
        end

        dialog.add_action_callback("setPushPullMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetPushPullMode()
            end
        end

        dialog.add_action_callback("setChamferMode") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__DrawnMode__SetChamferMode()
            end
        end

        dialog.add_action_callback("togglePlaneFaces") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__TogglePlaneFaces()
            end
        end

        # Cycling the grid keeps the popup open and rewrites its own button, so
        # stepping 5mm -> 100mm does not need four passes through right-click.
        dialog.add_action_callback("cycleGridStep") do |_action_context|
            begin
                label = tool_instance.Na__DrawnMode__CycleGridStep()
                dialog.execute_script("document.getElementById('gridBtn').textContent = 'Snap Grid: #{label}';")
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP GRID CYCLE FAILED: #{error.message}"
            end
        end

        # Segments cycle in place too, for the same reason as the grid step.
        dialog.add_action_callback("cycleCircleSegments") do |_action_context|
            begin
                count = tool_instance.Na__DrawnMode__CycleCircleSegments()
                dialog.execute_script("document.getElementById('sidesBtn').textContent = 'Circle Sides: #{count}';")
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP SEGMENT CYCLE FAILED: #{error.message}"
            end
        end

        dialog.add_action_callback("exitPrimitiveTool") do |_action_context|
            Na__InsertPrimatives.Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__ScheduleExitTool()
            end
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Run Popup Action Safely
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RunAction(tool_instance)
        Na__InsertPrimatives.Na__RightClickPopup__CloseMenu()

        UI.start_timer(0, false) do
            begin
                yield if tool_instance
            rescue StandardError => error
                Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP ACTION FAILED: #{error.message}"
            end
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Close Primitive Popup Menu
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__CloseMenu
        return unless @na_right_click_popup && @na_right_click_popup.visible?

        @na_right_click_popup.close
    rescue
        @na_right_click_popup = nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF RIGHT CLICK POPUP
# =============================================================================
