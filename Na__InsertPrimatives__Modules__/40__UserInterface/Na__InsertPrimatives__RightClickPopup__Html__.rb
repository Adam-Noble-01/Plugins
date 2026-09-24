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
# CONTEXT-AWARE SUBMENUS:
# - Every tool in the plugin is listed in this one menu, so an option belonging
#   to one of them cannot simply be added to the bottom: nine tools with three
#   options each is a menu nobody can read. Options are therefore declared
#   against a tool's mode key (Na__InsertPrimatives__AppData__ToolOptions__.rb)
#   and rendered as an indented block under the button of the tool that is
#   ACTUALLY RUNNING. Switch tools and the block moves with you; run a tool with
#   no options and the menu is exactly the length it always was.
# - The mode buttons are built through one helper, so a tool gains a submenu by
#   declaring options and nothing here needs to change.
# - Three colours, three meanings: blue is the tool you are in, green is an
#   option switched on, plain white is everything else.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Markup Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Make a String Safe to Drop Into the Popup Markup
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__Escape(text)
        text.to_s
            .gsub('&', '&amp;')
            .gsub('<', '&lt;')
            .gsub('>', '&gt;')
            .gsub('"', '&quot;')
            .gsub("'", '&#39;')
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Options the Running Tool Declares, or None
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ToolOptions(tool_instance)
        return [] unless tool_instance.respond_to?(:Na__DrawnMode__ToolOptions)

        tool_instance.Na__DrawnMode__ToolOptions || []
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Indented Block of Toggles Under the Running Tool
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__SubMenuHtml(options)
        return '' if options.nil? || options.empty?

        rows = options.map do |option|
            id      = Na__InsertPrimatives.Na__RightClickPopup__Escape(option[:id])
            caption = Na__InsertPrimatives.Na__RightClickPopup__Escape(option[:caption])
            summary = Na__InsertPrimatives.Na__RightClickPopup__Escape(option[:summary])
            state   = option[:enabled] ? 'opt on' : 'opt'

            "<button id=\"opt_#{id}\" class=\"#{state}\" title=\"#{summary}\" " \
            "onclick=\"sketchup.toggleToolOption('#{id}')\">#{caption}</button>"
        end

        "<div class=\"submenu\">#{rows.join}</div>"
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Mode Button, Carrying the Submenu When It Is the Live Tool
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__ModeButton(label, callback, mode_key, active_key, submenu)
        running = (active_key == mode_key)
        classes = running ? 'mode active' : 'mode'
        button  = "<button class=\"#{classes}\" onclick=\"sketchup.#{callback}()\">#{label}</button>"

        running ? button + submenu : button
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Html Css and Script
    # -----------------------------------------------------------------------------

    # FUNCTION | Build Primitive Popup HTML
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__BuildHtml(tool_instance)
        faces_on   = tool_instance.respond_to?(:Na__PrimitiveMode__PlaneFacesEnabled?) ?
                     tool_instance.Na__PrimitiveMode__PlaneFacesEnabled? : true
        face_label = faces_on ? "Plane Faces: Disable" : "Plane Faces: Enable"
        active_key   = Na__InsertPrimatives.Na__RightClickPopup__ActiveModeKey(tool_instance)
        grid_label   = Na__InsertPrimatives.Na__RightClickPopup__GridLabel(tool_instance)
        side_label   = Na__InsertPrimatives.Na__RightClickPopup__SegmentsLabel(tool_instance)
        anchor_label = Na__InsertPrimatives.Na__RightClickPopup__AnchorLabel

        # Built once and handed to every button — only the one whose mode key is
        # the running tool's ever renders it.
        submenu = Na__InsertPrimatives.Na__RightClickPopup__SubMenuHtml(
            Na__InsertPrimatives.Na__RightClickPopup__ToolOptions(tool_instance)
        )

        cube_btn    = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Cube',             'setCubeMode',          :cube,               active_key, submenu)
        plane_btn   = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Plane',            'setPlaneMode',         :plane,              active_key, submenu)
        drawn_p_btn = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Drawn Plane',      'setDrawnPlaneMode',    :drawn_plane,        active_key, submenu)
        drawn_v_btn = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Drawn Volume',     'setDrawnVolumeMode',   :drawn_volume,       active_key, submenu)
        drawn_c_btn = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Drawn Cylinder',   'setDrawnCylinderMode', :drawn_cylinder,     active_key, submenu)
        stair_btn   = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Staircase',        'setStairMode',         :drawn_stair,        active_key, submenu)
        roof_p_btn  = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Pitched Roof',     'setPitchedRoofMode',   :drawn_pitched_roof, active_key, submenu)
        roof_h_btn  = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Hipped Roof',      'setHippedRoofMode',    :drawn_hipped_roof,  active_key, submenu)
        push_btn    = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Deep Push / Pull', 'setPushPullMode',      :drawn_push_pull,    active_key, submenu)
        chamfer_btn = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Deep Chamfer',     'setChamferMode',       :drawn_chamfer,      active_key, submenu)
        fillet_btn  = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Deep Fillet',      'setFilletMode',        :drawn_fillet,       active_key, submenu)
        ogee_btn    = Na__InsertPrimatives.Na__RightClickPopup__ModeButton('Deep Ogee',        'setOgeeMode',          :drawn_ogee,         active_key, submenu)

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

                /* The options of the tool that is running, hung off its button
                   by a rule down the left so they read as belonging to it. */
                .submenu {
                    margin: 0 0 6px 9px;
                    padding-left: 8px;
                    border-left: 2px solid #4b83c8;
                }

                .submenu button {
                    margin-bottom: 3px;
                    padding: 5px 8px;
                    font-size: 11px;
                    background: #fbfbfb;
                    color: #444;
                }

                .submenu button.on {
                    background: #e3f2e5;
                    border-color: #6aa86f;
                    color: #1d5e26;
                    font-weight: 600;
                }

                .submenu button:hover {
                    background: #e7f0ff;
                    border-color: #7aa7e0;
                }

                button:last-child {
                    margin-bottom: 0;
                }
            </style>
        </head>
        <body>
            <div class="heading">Place</div>
            #{cube_btn}
            #{plane_btn}

            <div class="heading">Draw</div>
            #{drawn_p_btn}
            #{drawn_v_btn}
            #{drawn_c_btn}
            #{stair_btn}

            <div class="heading">Roof</div>
            #{roof_p_btn}
            #{roof_h_btn}

            <div class="heading">Modify</div>
            #{push_btn}
            #{chamfer_btn}
            #{fillet_btn}
            #{ogee_btn}

            <div class="rule"></div>
            <button id="gridBtn" onclick="sketchup.cycleGridStep()">Snap Grid: #{grid_label}</button>
            <button id="sidesBtn" onclick="sketchup.cycleCircleSegments()">Circle Sides: #{side_label}</button>
            <button onclick="sketchup.togglePlaneFaces()">#{face_label}</button>

            <div class="rule"></div>
            <button id="anchorBtn" onclick="sketchup.toggleMenuAnchor()">#{anchor_label}</button>
            <button onclick="sketchup.exitPrimitiveTool()">Exit Primitive Tool</button>

            <script>
                // Report the real content height so Ruby can shrink the window to
                // fit. Without this the height is a hand-maintained number that
                // silently clips the last button every time an entry is added.
                function naReportHeight() {
                    var measured = Math.max(
                        document.body.scrollHeight,
                        document.documentElement.scrollHeight
                    );
                    if (window.sketchup && sketchup.reportContentHeight) {
                        sketchup.reportContentHeight(measured);
                    }
                }

                window.addEventListener('load', naReportHeight);

                // Toggling an option rewrites its own button in place and leaves
                // the menu open, the way the grid step and the segment count
                // already do — an option is rarely changed on its own.
                function naApplyOption(optionId, caption, enabled) {
                    var button = document.getElementById('opt_' + optionId);
                    if (!button) { return; }
                    button.textContent = caption;
                    button.className = enabled ? 'opt on' : 'opt';
                }
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
