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
# - One popup serves every primitive tool in the plugin. The four modes are
#   Cube, Plane, Drawn Plane and Drawn Volume; the running one is highlighted.
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
    # REGION | Right Click Popup Menu
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


    # FUNCTION | Build Primitive Popup HTML
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__BuildHtml(tool_instance)
        faces_on   = tool_instance.respond_to?(:Na__PrimitiveMode__PlaneFacesEnabled?) ?
                     tool_instance.Na__PrimitiveMode__PlaneFacesEnabled? : true
        face_label = faces_on ? "Plane Faces: Disable" : "Plane Faces: Enable"
        active_key = Na__InsertPrimatives.Na__RightClickPopup__ActiveModeKey(tool_instance)
        grid_label = Na__InsertPrimatives.Na__RightClickPopup__GridLabel(tool_instance)
        side_label = Na__InsertPrimatives.Na__RightClickPopup__SegmentsLabel(tool_instance)

        cube_class   = active_key == :cube            ? 'mode active' : 'mode'
        plane_class  = active_key == :plane           ? 'mode active' : 'mode'
        drawn_p_cls  = active_key == :drawn_plane     ? 'mode active' : 'mode'
        drawn_v_cls  = active_key == :drawn_volume    ? 'mode active' : 'mode'
        drawn_c_cls  = active_key == :drawn_cylinder  ? 'mode active' : 'mode'
        roof_p_cls   = active_key == :drawn_pitched_roof ? 'mode active' : 'mode'
        roof_h_cls   = active_key == :drawn_hipped_roof  ? 'mode active' : 'mode'
        push_cls     = active_key == :drawn_push_pull    ? 'mode active' : 'mode'
        chamfer_cls  = active_key == :drawn_chamfer      ? 'mode active' : 'mode'

        <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                html, body {
                    margin: 0;
                    padding: 6px 6px 18px;
                    font-family: "Segoe UI", Arial, sans-serif;
                    font-size: 12px;
                    background: #f3f3f3;
                    color: #222;
                    overflow: hidden;
                    user-select: none;
                }

                .heading {
                    margin: 2px 2px 5px;
                    font-size: 10px;
                    letter-spacing: 0.06em;
                    text-transform: uppercase;
                    color: #777;
                }

                .rule {
                    height: 1px;
                    margin: 7px 2px;
                    background: #d5d5d5;
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

                button.active {
                    background: #dce9fb;
                    border-color: #4b83c8;
                    font-weight: 600;
                }

                button:last-child {
                    margin-bottom: 0;
                }
            </style>
        </head>
        <body>
            <div class="heading">Place</div>
            <button class="#{cube_class}"  onclick="sketchup.setCubeMode()">Cube</button>
            <button class="#{plane_class}" onclick="sketchup.setPlaneMode()">Plane</button>

            <div class="heading">Draw</div>
            <button class="#{drawn_p_cls}" onclick="sketchup.setDrawnPlaneMode()">Drawn Plane</button>
            <button class="#{drawn_v_cls}" onclick="sketchup.setDrawnVolumeMode()">Drawn Volume</button>
            <button class="#{drawn_c_cls}" onclick="sketchup.setDrawnCylinderMode()">Drawn Cylinder</button>

            <div class="heading">Roof</div>
            <button class="#{roof_p_cls}" onclick="sketchup.setPitchedRoofMode()">Pitched Roof</button>
            <button class="#{roof_h_cls}" onclick="sketchup.setHippedRoofMode()">Hipped Roof</button>

            <div class="heading">Modify</div>
            <button class="#{push_cls}" onclick="sketchup.setPushPullMode()">Deep Push / Pull</button>
            <button class="#{chamfer_cls}" onclick="sketchup.setChamferMode()">Deep Chamfer</button>

            <div class="rule"></div>
            <button id="gridBtn" onclick="sketchup.cycleGridStep()">Snap Grid: #{grid_label}</button>
            <button id="sidesBtn" onclick="sketchup.cycleCircleSegments()">Circle Sides: #{side_label}</button>
            <button onclick="sketchup.togglePlaneFaces()">#{face_label}</button>
            <button onclick="sketchup.exitPrimitiveTool()">Exit Primitive Tool</button>

            <script>
                // Report the real content height so Ruby can shrink the window to
                // fit. Without this the height is a hand-maintained number that
                // silently clips the last button every time an entry is added.
                window.addEventListener('load', function () {
                    var measured = Math.max(
                        document.body.scrollHeight,
                        document.documentElement.scrollHeight
                    );
                    if (window.sketchup && sketchup.reportContentHeight) {
                        sketchup.reportContentHeight(measured);
                    }
                });
            </script>
        </body>
        </html>
        HTML
    end
    # ---------------------------------------------------------------


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
                puts "PRIMITIVE POPUP RESIZE FAILED: #{error.message}"
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
                puts "PRIMITIVE POPUP GRID CYCLE FAILED: #{error.message}"
            end
        end

        # Segments cycle in place too, for the same reason as the grid step.
        dialog.add_action_callback("cycleCircleSegments") do |_action_context|
            begin
                count = tool_instance.Na__DrawnMode__CycleCircleSegments()
                dialog.execute_script("document.getElementById('sidesBtn').textContent = 'Circle Sides: #{count}';")
            rescue StandardError => error
                puts "PRIMITIVE POPUP SEGMENT CYCLE FAILED: #{error.message}"
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
                puts "PRIMITIVE POPUP ACTION FAILED: #{error.message}"
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
