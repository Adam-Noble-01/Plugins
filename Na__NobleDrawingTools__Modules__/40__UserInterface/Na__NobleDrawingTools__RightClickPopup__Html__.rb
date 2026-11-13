# =============================================================================
# NA NOBLE DRAWING TOOLS - RIGHT CLICK POPUP HTML
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__RightClickPopup__Html__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Html, CSS and script for the tool right-click popup
# CREATED    : 2026
#
# CONTEXT-AWARE SUBMENUS:
# - Every tool in the plugin is listed in this one menu, so an option belonging
#   to one of them cannot simply be added to the bottom: nine tools with three
#   options each is a menu nobody can read. Options are therefore declared
#   against a tool's mode key (Na__NobleDrawingTools__AppData__ToolOptions__.rb)
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

module Na__NobleDrawingTools

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

    # FUNCTION | The Menu Icon File for Each Tool, by Mode Key
    # ------------------------------------------------------------
    # The SVGs live in UiIcons__MenuIcons__ToolMenu beside this file; a tool
    # with no entry, or a file gone missing, just shows its label as before. A
    # method rather than a constant, so Reload Plugin Data redefines it quietly.
    def self.Na__RightClickPopup__IconFiles
        {
        :cube               => 'Icon__NobleDrawingTools__Cube__.svg',
        :plane              => 'Icon__NobleDrawingTools__Plane__.svg',
        :drawn_plane        => 'Icon__NobleDrawingTools__DrawnPlane__.svg',
        :drawn_volume       => 'Icon__NobleDrawingTools__DrawnVolume__.svg',
        :drawn_cylinder     => 'Icon__NobleDrawingTools__DrawnCylinder__.svg',
        :drawn_stair        => 'Icon__NobleDrawingTools__Staircase__.svg',
        :drawn_pipe         => 'Icon__NobleDrawingTools__Pipework__.svg',
        :drawn_pitched_roof => 'Icon__NobleDrawingTools__PitchedRoof__.svg',
        :drawn_hipped_roof  => 'Icon__NobleDrawingTools__HippedRoof__.svg',
        :drawn_push_pull    => 'Icon__NobleDrawingTools__DeepPushPull__.svg',
        :drawn_project      => 'Icon__NobleDrawingTools__DeepProject__.svg',
        :drawn_chamfer      => 'Icon__NobleDrawingTools__DeepChamfer__.svg',
        :drawn_fillet       => 'Icon__NobleDrawingTools__DeepFillet__.svg',
        :drawn_ogee         => 'Icon__NobleDrawingTools__DeepOgee__.svg',
        :drawn_ovolo        => 'Icon__NobleDrawingTools__DeepOvoloCavetto__.svg',
        :drawn_scale        => 'Icon__NobleDrawingTools__DeepScale__.svg',
        :drawn_stretch      => 'Icon__NobleDrawingTools__DeepStretch__.svg',      # Deep Scale locked to stretching (5.2.42)
        :drawn_vertex_move  => 'Icon__NobleDrawingTools__VertexEdit__.svg',
        :snap_grid          => 'Icon__NobleDrawingTools__SnapGrid__.svg',          # settings, not tools: see SettingButton
        :circle_sides       => 'Icon__NobleDrawingTools__CircleSides__.svg',
        :brand_logo        => 'Na__NobleDrawingTools__Brand__CompanyLogo__.svg'  # the Noble Architecture logo across the top
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | An SVG Beside This File as a Data URI, or Nil
    # ------------------------------------------------------------
    # The popup is built with set_html, so it has no folder to resolve a
    # relative src against: each SVG goes in as a data URI. Kept until the file
    # changes, so a redrawn icon shows on the next popup without a reload.
    def self.Na__RightClickPopup__SvgDataUri(file)
        return nil unless file

        path = File.join(__dir__, 'UiIcons__MenuIcons__ToolMenu', file)
        return nil unless File.exist?(path)

        @na_menu_icon_uris ||= {}
        stamp  = File.mtime(path).to_f
        cached = @na_menu_icon_uris[path]
        return cached[1] if cached && cached[0] == stamp

        uri = "data:image/svg+xml;base64,#{[File.binread(path)].pack('m0')}"
        @na_menu_icon_uris[path] = [stamp, uri]
        uri
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Tool's Menu Icon as an Inline Img Tag, or Nothing
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__IconHtml(mode_key)
        uri = Na__NobleDrawingTools.Na__RightClickPopup__SvgDataUri(Na__NobleDrawingTools.Na__RightClickPopup__IconFiles[mode_key])
        uri ? "<img class=\"ico\" src=\"#{uri}\" alt=\"\">" : ''
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Logo Band at the Top of the Menu, or Nothing
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__BrandHtml
        uri = Na__NobleDrawingTools.Na__RightClickPopup__SvgDataUri(Na__NobleDrawingTools.Na__RightClickPopup__IconFiles[:brand_logo])
        uri ? "<div class=\"brand\"><img src=\"#{uri}\" alt=\"Noble Architecture\"></div>" : ''
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
            id      = Na__NobleDrawingTools.Na__RightClickPopup__Escape(option[:id])
            caption = Na__NobleDrawingTools.Na__RightClickPopup__Escape(option[:caption])
            summary = Na__NobleDrawingTools.Na__RightClickPopup__Escape(option[:summary])
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
        icon    = Na__NobleDrawingTools.Na__RightClickPopup__IconHtml(mode_key)
        button  = "<button class=\"#{classes}\" onclick=\"sketchup.#{callback}()\">#{icon}<span>#{label}</span></button>"

        running ? button + submenu : button
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Setting Button: an Icon and a Label That Can Be Rewritten
    # ------------------------------------------------------------
    # Cycling a setting rewrites its label in place with the popup open, so the
    # label has its own element, <button_id>Label. Writing to the button itself
    # would wipe out the icon.
    def self.Na__RightClickPopup__SettingButton(button_id, callback, icon_key, label)
        icon = Na__NobleDrawingTools.Na__RightClickPopup__IconHtml(icon_key)

        "<button id=\"#{button_id}\" class=\"mode\" onclick=\"sketchup.#{callback}()\">" \
        "#{icon}<span id=\"#{button_id}Label\">#{label}</span></button>"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Html Css and Script
    # -----------------------------------------------------------------------------

    # FUNCTION | Build Tool Popup HTML
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__BuildHtml(tool_instance)
        active_key   = Na__NobleDrawingTools.Na__RightClickPopup__ActiveModeKey(tool_instance)
        grid_label   = Na__NobleDrawingTools.Na__RightClickPopup__GridLabel(tool_instance)
        side_label   = Na__NobleDrawingTools.Na__RightClickPopup__SegmentsLabel(tool_instance)
        anchor_label = Na__NobleDrawingTools.Na__RightClickPopup__AnchorLabel
        show_label   = Na__NobleDrawingTools.Na__RightClickPopup__ShowModeLabel

        # Built once and handed to every button — only the one whose mode key is
        # the running tool's ever renders it. Plane Faces lives here now, as the
        # Face option under Plane and Drawn Plane, seen only while one is running.
        tool_options = Na__NobleDrawingTools.Na__RightClickPopup__ToolOptions(tool_instance)
        submenu      = Na__NobleDrawingTools.Na__RightClickPopup__SubMenuHtml(tool_options)

        cube_btn    = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Cube',             'setCubeMode',          :cube,               active_key, submenu)
        plane_btn   = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Plane',            'setPlaneMode',         :plane,              active_key, submenu)
        drawn_p_btn = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Drawn Plane',      'setDrawnPlaneMode',    :drawn_plane,        active_key, submenu)
        drawn_v_btn = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Drawn Volume',     'setDrawnVolumeMode',   :drawn_volume,       active_key, submenu)
        drawn_c_btn = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Drawn Cylinder',   'setDrawnCylinderMode', :drawn_cylinder,     active_key, submenu)
        stair_btn   = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Staircase',        'setStairMode',         :drawn_stair,        active_key, submenu)
        pipe_btn    = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Pipework',         'setPipeMode',          :drawn_pipe,         active_key, submenu)
        roof_p_btn  = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Pitched Roof',     'setPitchedRoofMode',   :drawn_pitched_roof, active_key, submenu)
        roof_h_btn  = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Hipped Roof',      'setHippedRoofMode',    :drawn_hipped_roof,  active_key, submenu)
        push_btn    = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Push / Pull', 'setPushPullMode',      :drawn_push_pull,    active_key, submenu)
        project_btn = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Project',     'setProjectMode',       :drawn_project,      active_key, submenu)
        chamfer_btn = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Chamfer',     'setChamferMode',       :drawn_chamfer,      active_key, submenu)
        fillet_btn  = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Fillet',      'setFilletMode',        :drawn_fillet,       active_key, submenu)
        ogee_btn    = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Ogee',        'setOgeeMode',          :drawn_ogee,         active_key, submenu)
        ovolo_btn   = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Ovolo / Cavetto', 'setOvoloMode',     :drawn_ovolo,        active_key, submenu)
        scale_btn   = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Scale',       'setScaleMode',         :drawn_scale,        active_key, submenu)
        stretch_btn = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Stretch',     'setStretchMode',       :drawn_stretch,      active_key, submenu)
        vertex_btn  = Na__NobleDrawingTools.Na__RightClickPopup__ModeButton('Deep Vertex Move', 'setVertexMoveMode',    :drawn_vertex_move,  active_key, submenu)

        grid_btn    = Na__NobleDrawingTools.Na__RightClickPopup__SettingButton('gridBtn',  'cycleGridStep',       :snap_grid,    "Snap Grid: #{grid_label}")
        sides_btn   = Na__NobleDrawingTools.Na__RightClickPopup__SettingButton('sidesBtn', 'cycleCircleSegments', :circle_sides, "Circle Sides: #{side_label}")

        <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                /* The window is the size the user gave it (5.2.16): a menu
                   taller than that scrolls, it never grows the window. */
                html {
                    margin: 0;
                    padding: 0;
                    height: 100%;
                    overflow: hidden;
                    background: #f3f3f3;
                }

                body {
                    box-sizing: border-box;
                    height: 100%;
                    margin: 0;
                    padding: 12px 12px 36px;
                    font-family: "Segoe UI", Arial, sans-serif;
                    font-size: 12px;
                    background: #f3f3f3;
                    color: #222;
                    overflow-x: hidden;
                    overflow-y: auto;
                    user-select: none;
                }

                body::-webkit-scrollbar { width: 8px; }
                body::-webkit-scrollbar-thumb { background: #c8c8c8; border-radius: 4px; }
                body::-webkit-scrollbar-thumb:hover { background: #a9a9a9; }

                /* The Noble Architecture logo, ruled off from the tools below. */
                .brand {
                    margin: 0 2px 7px;
                    padding: 2px 0 7px;
                    border-bottom: 1px solid #d5d5d5;
                }

                .brand img {
                    display: block;
                    width: 100%;
                    max-width: 144px;
                    height: auto;
                    margin: 0;
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

                /* A tool button: its icon, then its label. */
                button.mode {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    padding: 4px 8px;
                }

                button.mode .ico {
                    flex: none;
                    width: 22px;
                    height: 22px;
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
            <div id="naMenu">
            #{Na__NobleDrawingTools.Na__RightClickPopup__BrandHtml}
            <div class="heading">Place</div>
            #{cube_btn}
            #{plane_btn}

            <div class="heading">Draw Primitives</div>
            #{drawn_p_btn}
            #{drawn_v_btn}
            #{drawn_c_btn}

            <div class="heading">Building Parts</div>
            #{roof_p_btn}
            #{roof_h_btn}
            #{stair_btn}
            #{pipe_btn}

            <div class="heading">Modify</div>
            #{push_btn}
            #{project_btn}
            #{scale_btn}
            #{stretch_btn}
            #{vertex_btn}

            <div class="heading">Edge Treatments</div>
            #{chamfer_btn}
            #{fillet_btn}
            #{ogee_btn}
            #{ovolo_btn}

            <div class="rule"></div>
            #{grid_btn}
            #{sides_btn}

            <div class="rule"></div>
            <button id="anchorBtn" onclick="sketchup.toggleMenuAnchor()">#{anchor_label}</button>
            <button id="showModeBtn" onclick="sketchup.toggleMenuShowMode()">#{show_label}</button>
            <button onclick="sketchup.exitTool()">Exit Tool</button>
            </div>

            <script>
                // Report the page's own size (content area, CSS pixels), the
                // height the buttons need, and the foot of the screen's work
                // area. Ruby fits the window to the remembered size on 'load',
                // and remembers the user's size after a resize settles.
                var naLoaded = false;
                var naResizeTimer = null;

                function naReportLayout(reason) {
                    if (!(window.sketchup && sketchup.reportLayout)) { return; }
                    var style  = window.getComputedStyle(document.body);
                    var menu   = document.getElementById('naMenu');
                    var needed = Math.ceil(
                        menu.getBoundingClientRect().height +
                        parseFloat(style.paddingTop) + parseFloat(style.paddingBottom)
                    );
                    var availBottom = (screen.availTop || 0) + screen.availHeight;
                    sketchup.reportLayout(
                        window.innerWidth, window.innerHeight, needed,
                        availBottom, window.screenY, reason
                    );
                }

                window.addEventListener('load', function () {
                    naLoaded = true;
                    naReportLayout('load');
                });

                window.addEventListener('resize', function () {
                    if (!naLoaded) { return; }
                    clearTimeout(naResizeTimer);
                    naResizeTimer = setTimeout(function () { naReportLayout('resize'); }, 250);
                });

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
