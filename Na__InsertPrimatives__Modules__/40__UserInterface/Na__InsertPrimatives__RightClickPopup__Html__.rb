# =============================================================================
# NA INSERT PRIMATIVES - RIGHT CLICK POPUP HTML
# =============================================================================
#
# FILE       : Na__InsertPrimatives__RightClickPopup__Html__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Html, CSS and script for the primitive right-click popup
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Html Css and Script
    # -----------------------------------------------------------------------------

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

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
