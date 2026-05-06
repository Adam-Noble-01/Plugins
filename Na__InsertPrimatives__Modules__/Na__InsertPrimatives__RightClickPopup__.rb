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
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Right Click Popup Menu
    # -----------------------------------------------------------------------------

    # FUNCTION | Show Primitive Popup Menu
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ShowPrimitiveMenu(tool_instance, x, y)
        Na__RightClickPopup__CloseMenu()

        @na_right_click_popup = UI::HtmlDialog.new(
            dialog_title: "Primitive Menu",
            preferences_key: "Na__InsertPrimatives__RightClickPopup",
            scrollable: false,
            resizable: false,
            width: 190,
            height: 188,
            style: UI::HtmlDialog::STYLE_UTILITY
        )

        @na_right_click_popup.set_html(Na__RightClickPopup__BuildHtml(tool_instance))
        Na__RightClickPopup__InstallCallbacks(@na_right_click_popup, tool_instance)
        @na_right_click_popup.set_position(x.to_i + 20, y.to_i + 20)
        @na_right_click_popup.show
        @na_right_click_popup.bring_to_front
    end
    # ---------------------------------------------------------------


    # FUNCTION | Build Primitive Popup HTML
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__BuildHtml(tool_instance)
        face_label = tool_instance.Na__PrimitiveMode__PlaneFacesEnabled? ? "Plane Faces: Disable" : "Plane Faces: Enable"

        <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                html, body {
                    margin: 0;
                    padding: 6px 6px 12px;
                    font-family: "Segoe UI", Arial, sans-serif;
                    font-size: 12px;
                    background: #f3f3f3;
                    color: #222;
                    overflow: hidden;
                    user-select: none;
                }

                button {
                    display: block;
                    width: 100%;
                    margin: 0 0 4px;
                    padding: 7px 8px;
                    border: 1px solid #bbb;
                    border-radius: 3px;
                    background: #fff;
                    color: #222;
                    text-align: left;
                    cursor: pointer;
                }

                button:hover {
                    background: #e7f0ff;
                    border-color: #7aa7e0;
                }

                button:last-child {
                    margin-bottom: 0;
                }
            </style>
        </head>
        <body>
            <button onclick="sketchup.setCubeMode()">Primitive: Cube</button>
            <button onclick="sketchup.setPlaneMode()">Primitive: Plane</button>
            <button onclick="sketchup.togglePlaneFaces()">#{face_label}</button>
            <button onclick="sketchup.exitPrimitiveTool()">Exit Primitive Tool</button>
        </body>
        </html>
        HTML
    end
    # ---------------------------------------------------------------


    # FUNCTION | Install Primitive Popup Callbacks
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__InstallCallbacks(dialog, tool_instance)
        dialog.add_action_callback("setCubeMode") do |_action_context|
            Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__SetCubeMode()
            end
        end

        dialog.add_action_callback("setPlaneMode") do |_action_context|
            Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__SetPlaneMode()
            end
        end

        dialog.add_action_callback("togglePlaneFaces") do |_action_context|
            Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__TogglePlaneFaces()
            end
        end

        dialog.add_action_callback("exitPrimitiveTool") do |_action_context|
            Na__RightClickPopup__RunAction(tool_instance) do
                tool_instance.Na__PrimitiveMode__ScheduleExitTool()
            end
        end
    end
    # ---------------------------------------------------------------


    # FUNCTION | Run Popup Action Safely
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__RunAction(tool_instance)
        Na__RightClickPopup__CloseMenu()

        UI.start_timer(0, false) do
            yield if tool_instance
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
