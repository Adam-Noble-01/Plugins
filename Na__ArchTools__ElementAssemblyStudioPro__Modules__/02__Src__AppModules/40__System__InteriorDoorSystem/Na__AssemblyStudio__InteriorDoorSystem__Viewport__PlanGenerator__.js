// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - VIEWPORT PLAN SVG
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__Viewport__PlanGenerator__.js
// NAMESPACE  : Na_DoorPlanGenerator (browser global, preserved name)
// AUTHOR     : Noble Architecture
// PURPOSE    : Build a 2D plan view of the door opening, lining, panel
//              and dotted swing arc for the dialog's preview.
// CREATED    : 01-May-2026
// RELOCATED  : 01-May-2026 (was Na__InteriorDoorConfigurator__; now 40__System__InteriorDoorSystem)
// SLIMMED    : 01-May-2026 - now uses Na__Viewport__SvgHelpers for the
//              previously-duplicated na_make_svg / na_num / na_bool /
//              clear-children helpers.
//
// DESCRIPTION:
// - Pure-function module: na_render(svgEl, config) wipes the supplied
//   <svg> element and re-draws every plan-view layer based on the
//   configuration values prefixed Na__DoorConfig__*.
// - Coordinate system: SVG units = millimetres. The Instance factory's
//   pan/zoom owns the viewBox; this generator only paints geometry.
//
// LAYERS DRAWN (back to front):
//   1. Wall fill rectangles (left + right of opening)
//   2. Door lining sections (left jamb + right jamb plan rectangles)
//   3. Door panel rectangle (closed position)
//   4. Handle preview from selected Na__Asset__Plan2D (fallback: marker)
//   5. Dotted door panel outline (swing position)
//   6. Dotted door swing arc
//   7. Dimension labels (W / D)
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';

    var Na_DoorPlanGenerator = {};                                            // <-- Public namespace


// -----------------------------------------------------------------------------
// REGION | Constants
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | Layout Padding
    // ------------------------------------------------------------
    var NA_WALL_PADDING_MM         = 300;                                     // <-- mm of wall to show either side of the opening
    var NA_VIEW_VERTICAL_PAD_MM    = 200;                                     // <-- mm padding above & below the wall in plan
    // ---------------------------------------------------------------

    // MODULE CONSTANTS | Palette
    // ------------------------------------------------------------
    // Wall + stroke + dim colours stay fixed; lining + panel fills are now
    // driven by the selected Joinery Finish material (live data sourced from
    // window.NA_FRAME_FINISH_SWATCHES). Fallbacks below are only used when
    // the materials JSON has not yet loaded.
    var NA_WALL_FILL               = '#d8d8d8';                               // <-- Cool grey wall fill
    var NA_WALL_STROKE             = '#666666';                               // <-- Wall outline
    var NA_PANEL_STROKE            = '#5a4324';                               // <-- Door panel outline
    var NA_HANDLE_STROKE           = '#5a4324';                               // <-- Handle path outline
    var NA_SWING_STROKE            = '#5a4324';                               // <-- Swing arc outline
    var NA_DIM_TEXT_COLOR          = '#333333';                               // <-- Dimension label colour
    var NA_FALLBACK_TIMBER_HEX     = '#D2B48C';                               // <-- Used only before swatches arrive
    var NA_FALLBACK_HANDLE_HEX     = '#C0AE8A';                               // <-- Unlacquered brass fallback for handle preview
    var NA_FALLBACK_HANDLE_RADIUS  = 12;                                      // <-- Visible fallback if Plan2D data is missing
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Shared Helper Aliases
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Read Numeric Config Value Through Shared Helpers
    // ------------------------------------------------------------
    function na_num(config, key, fallback) {
        return window.Na__Viewport__SvgHelpers.na_num(config, key, fallback);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read Boolean Config Value Through Shared Helpers
    // ------------------------------------------------------------
    function na_bool(config, key, fallback) {
        return window.Na__Viewport__SvgHelpers.na_bool(config, key, fallback);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Create SVG Element Through Shared Helpers
    // ------------------------------------------------------------
    function na_make_svg(tag, attrs) {
        return window.Na__Viewport__SvgHelpers.na_make_svg(tag, attrs);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Safe Numeric Coercion
    // ------------------------------------------------------------
    function na_to_number(value, fallback) {
        var num = Number(value);
        return Number.isFinite(num) ? num : fallback;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Material Hex Resolution (Live from Swatch Globals)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve a Material ID to a Hex Colour String
    // ------------------------------------------------------------
    // Reads the provided swatch global name (default frame-finish swatches).
    function na_resolve_material_hex(materialId, fallbackHex, swatchesGlobalName) {
        var swatches = window[swatchesGlobalName || 'NA_FRAME_FINISH_SWATCHES'];
        if (Array.isArray(swatches)) {
            for (var i = 0; i < swatches.length; i++) {
                if (swatches[i] && swatches[i].id === materialId) {
                    return swatches[i].hex || swatches[i].color || fallbackHex;
                }
            }
        }
        return fallbackHex;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Plan View Lining + Panel Fills
    // ------------------------------------------------------------
    function na_resolve_door_finish_palette(config) {
        var liningId = (config && config['Na__DoorConfig__LiningMaterialId']) || 'MAT120__GenericWood';
        var panelId  = (config && config['Na__DoorConfig__PanelMaterialId'])  || 'MAT120__GenericWood';
        var handleId = (config && config['Na__DoorConfig__HandleMaterialId']) || 'MAT612__Metal__Ironmongery__Brass';
        return {
            liningFill : na_resolve_material_hex(liningId, NA_FALLBACK_TIMBER_HEX, 'NA_FRAME_FINISH_SWATCHES'),
            panelFill  : na_resolve_material_hex(panelId,  NA_FALLBACK_TIMBER_HEX, 'NA_FRAME_FINISH_SWATCHES'),
            handleFill : na_resolve_material_hex(handleId, NA_FALLBACK_HANDLE_HEX, 'NA_HANDLE_FINISH_SWATCHES')
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Handle Asset Preview Helpers (Plan2D)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve Selected Handle's Plan2D block
    // ------------------------------------------------------------
    function na_get_handle_asset_key(config) {
        return (config && config['Na__DoorConfig__HandleAssetKey']) || 'Na__InteriorDoor__Handle__Default';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve Selected Handle's Plan2D block
    // ------------------------------------------------------------
    function na_get_handle_plan_block(config) {
        var handleKey = na_get_handle_asset_key(config);
        var cache = window.NA_DOOR_HANDLE_ASSET_PREVIEW_CACHE || {};
        var asset = cache[handleKey];
        if (!asset || typeof asset !== 'object') return null;
        return asset['Na__Asset__Plan2D'] || null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Transform asset local XY point into plan SVG XY
    // ------------------------------------------------------------
    // Mirrors X when the door is left-hand so the handle lever always
    // projects outward from the hinge into the room side of the panel,
    // matching the 3D handle builder's ScaleX = -1 handing rule.
    //
    // Mirrors Y when the door swings outward so the handle rose sits
    // on the FAR (exterior-facing) face of the panel with the handle
    // body extending into the exterior, rather than on the near face
    // with the body buried inside the panel.
    function na_transform_handle_point_plan(layout, point) {
        var localX = na_to_number(point && point.X, 0);
        var localY = na_to_number(point && point.Y, 0);
        var mirroredX = layout.handleMirrorX ? -localX : localX;
        var mirroredY = layout.handleMirrorY ? -localY : localY;
        return {
            x: layout.handleX + mirroredX,
            y: layout.handleY + mirroredY
        };
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Draw handle paths from Na__Asset__Plan2D
    // ------------------------------------------------------------
    function na_build_handle_paths_from_asset(svg, layout, palette, block) {
        var paths = block && block['Na__Geometry__Paths'];
        if (!Array.isArray(paths) || !paths.length) return false;

        var drew = false;
        paths.forEach(function (pathItem) {
            if (!pathItem || typeof pathItem !== 'object') return;
            var pathType = String(pathItem.PathType || '').toLowerCase();

            if (pathType === 'polygon') {
                var vertices = Array.isArray(pathItem.Vertices_mm) ? pathItem.Vertices_mm : [];
                if (!vertices.length) return;

                var pointString = vertices.map(function (vertex) {
                    var pt = na_transform_handle_point_plan(layout, vertex);
                    return pt.x + ',' + pt.y;
                }).join(' ');
                if (!pointString) return;

                svg.appendChild(na_make_svg('polygon', {
                    points: pointString,
                    fill: palette.handleFill,
                    stroke: NA_HANDLE_STROKE,
                    'stroke-width': 0.6
                }));
                drew = true;
                return;
            }

            if (pathType === 'line') {
                var start = na_transform_handle_point_plan(layout, pathItem.Start_mm);
                var end = na_transform_handle_point_plan(layout, pathItem.End_mm);
                svg.appendChild(na_make_svg('line', {
                    x1: start.x,
                    y1: start.y,
                    x2: end.x,
                    y2: end.y,
                    stroke: NA_HANDLE_STROKE,
                    'stroke-width': 0.6
                }));
                drew = true;
                return;
            }

            if (pathType === 'circle') {
                var center = na_transform_handle_point_plan(layout, pathItem.Center_mm);
                svg.appendChild(na_make_svg('circle', {
                    cx: center.x,
                    cy: center.y,
                    r: Math.max(0.1, na_to_number(pathItem.Radius_mm, 0)),
                    fill: 'none',
                    stroke: NA_HANDLE_STROKE,
                    'stroke-width': 0.6
                }));
                drew = true;
            }
        });

        return drew;
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build a Simple Handle Marker (Fallback)
    // ------------------------------------------------------------
    function na_build_handle_marker(svg, layout, palette) {
        svg.appendChild(na_make_svg('circle', {
            cx: layout.handleX,
            cy: layout.handleY,
            r: NA_FALLBACK_HANDLE_RADIUS,
            fill: palette.handleFill,
            stroke: NA_HANDLE_STROKE,
            'stroke-width': 0.75
        }));
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Warn Once Per Handle Key for Missing Plan2D Paths
    // ------------------------------------------------------------
    function na_warn_plan_preview_missing_once(handleKey, reason) {
        window.NA_DOOR_HANDLE_PLAN_PREVIEW_WARNINGS = window.NA_DOOR_HANDLE_PLAN_PREVIEW_WARNINGS || {};
        var token = String(handleKey || 'unknown') + '::' + String(reason || 'unknown');
        if (window.NA_DOOR_HANDLE_PLAN_PREVIEW_WARNINGS[token]) return;
        window.NA_DOOR_HANDLE_PLAN_PREVIEW_WARNINGS[token] = true;
        console.warn('[Na_DoorPlanGenerator] Using fallback marker for handle', handleKey, '| reason:', reason);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build Handle Preview for Plan View
    // ------------------------------------------------------------
    function na_build_handle_preview(svg, layout, palette, config) {
        var handleKey = na_get_handle_asset_key(config);
        var block = na_get_handle_plan_block(config);
        if (na_build_handle_paths_from_asset(svg, layout, palette, block)) return;
        var reason = (block && block['Na__Geometry__Paths']) ? 'invalid-path-records' : 'missing-plan2d-block-or-paths';
        na_warn_plan_preview_missing_once(handleKey, reason);
        na_build_handle_marker(svg, layout, palette);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Layer Builders
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Build the Two Wall Fill Rectangles
    // ------------------------------------------------------------
    function na_build_wall_layers(svg, layout) {
        var leftWall = na_make_svg('rect', {
            x      : layout.viewMinX,
            y      : layout.wallTopY,
            width  : layout.openingX - layout.viewMinX,
            height : layout.wallDepth,
            fill   : NA_WALL_FILL,
            stroke : NA_WALL_STROKE,
            'stroke-width' : 1
        });
        var rightWall = na_make_svg('rect', {
            x      : layout.openingX + layout.openingWidth,
            y      : layout.wallTopY,
            width  : layout.viewMaxX - (layout.openingX + layout.openingWidth),
            height : layout.wallDepth,
            fill   : NA_WALL_FILL,
            stroke : NA_WALL_STROKE,
            'stroke-width' : 1
        });
        svg.appendChild(leftWall);
        svg.appendChild(rightWall);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build Both Door Lining Plan Rectangles (Left + Right Jamb)
    // ------------------------------------------------------------
    function na_build_lining_layers(svg, layout, palette) {
        var leftLining = na_make_svg('rect', {
            x      : layout.openingX,
            y      : layout.wallTopY,
            width  : layout.liningThickness,
            height : layout.wallDepth,
            fill   : palette.liningFill,
            stroke : NA_PANEL_STROKE,
            'stroke-width' : 0.75
        });
        var rightLining = na_make_svg('rect', {
            x      : layout.openingX + layout.openingWidth - layout.liningThickness,
            y      : layout.wallTopY,
            width  : layout.liningThickness,
            height : layout.wallDepth,
            fill   : palette.liningFill,
            stroke : NA_PANEL_STROKE,
            'stroke-width' : 0.75
        });
        svg.appendChild(leftLining);
        svg.appendChild(rightLining);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the Closed-Position Door Panel Rectangle
    // ------------------------------------------------------------
    // Drawn on the hinge side flush with the lining face.
    function na_build_closed_panel(svg, layout, palette) {
        var x = (layout.swingSide === 'Left')
            ? layout.openingX + layout.liningThickness
            : layout.openingX + layout.openingWidth - layout.liningThickness - layout.panelClearWidth;

        var rect = na_make_svg('rect', {
            x      : x,
            y      : layout.panelY,
            width  : layout.panelClearWidth,
            height : layout.panelThickness,
            fill   : palette.panelFill,
            stroke : NA_PANEL_STROKE,
            'stroke-width' : 0.75
        });
        svg.appendChild(rect);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the Open-Position (Dotted) Panel Outline
    // ------------------------------------------------------------
    // The open-position panel rectangle is anchored at the hinge-side
    // corner of the reveal (layout.hingeY) and extends perpendicular
    // to the wall on the side the door opens to:
    //   Outward  -> ABOVE the wall (small SVG Y = exterior)
    //   Inward   -> BELOW the wall (large SVG Y = room)
    function na_build_open_panel_outline(svg, layout) {
        var hingeX = (layout.swingSide === 'Left')
            ? layout.openingX + layout.liningThickness
            : layout.openingX + layout.openingWidth - layout.liningThickness;
        var hingeY = layout.hingeY;

        var outward = (layout.swingDirection === 'outward');
        var rectY   = outward ? hingeY - layout.panelClearWidth : hingeY;       // <-- Extend UP (small Y) for outward, DOWN (large Y) for inward
        var rectX   = (layout.swingSide === 'Left') ? hingeX : hingeX - layout.panelThickness;

        var openRect = na_make_svg('rect', {
            x      : rectX,
            y      : rectY,
            width  : layout.panelThickness,
            height : layout.panelClearWidth,
            fill   : 'none',
            stroke : NA_PANEL_STROKE,
            'stroke-width'      : 0.5,
            'stroke-dasharray'  : '4 3'
        });
        svg.appendChild(openRect);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the Dotted Swing Arc
    // ------------------------------------------------------------
    // The arc anchors at the hinge-side corner of the reveal and
    // sweeps 90 deg to the open position:
    //   Outward -> end is ABOVE (smaller SVG Y = exterior side)
    //   Inward  -> end is BELOW (larger SVG Y = room side)
    // layout.hingeY is on the exterior face for outward and the
    // room face for inward (matching panelY positioning in na_compute_layout).
    function na_build_swing_arc(svg, layout) {
        var hingeX = (layout.swingSide === 'Left')
            ? layout.openingX + layout.liningThickness
            : layout.openingX + layout.openingWidth - layout.liningThickness;
        var hingeY = layout.hingeY;

        var startX = (layout.swingSide === 'Left')
            ? hingeX + layout.panelClearWidth
            : hingeX - layout.panelClearWidth;
        var startY = hingeY;
        var endX   = hingeX;

        var outward = (layout.swingDirection === 'outward');
        var signY   = outward ? -1 : +1;                                       // <-- UP (smaller Y) for outward, DOWN (larger Y) for inward
        var endY    = hingeY + signY * layout.panelClearWidth;

        var sweepFlag;
        if (outward) {
            sweepFlag = (layout.swingSide === 'Left') ? 0 : 1;                 // <-- Arc bulges on the exterior side (above wall)
        } else {
            sweepFlag = (layout.swingSide === 'Left') ? 1 : 0;                 // <-- Arc bulges on the room side (below wall)
        }

        var d = 'M ' + startX + ' ' + startY +
                ' A ' + layout.panelClearWidth + ' ' + layout.panelClearWidth +
                ' 0 0 ' + sweepFlag + ' ' + endX + ' ' + endY;

        var path = na_make_svg('path', {
            d                   : d,
            fill                : 'none',
            stroke              : NA_SWING_STROKE,
            'stroke-width'      : 0.5,
            'stroke-dasharray'  : '3 3'
        });
        svg.appendChild(path);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build Width and Depth Dimension Labels
    // ------------------------------------------------------------
    function na_build_dimension_labels(svg, layout, openingWidthMm, wallDepthMm) {
        var widthLabel = na_make_svg('text', {
            x       : layout.openingX + (layout.openingWidth / 2),
            y       : layout.wallTopY - 30,
            fill    : NA_DIM_TEXT_COLOR,
            'text-anchor' : 'middle',
            'font-size'   : '36'
        });
        widthLabel.textContent = 'W: ' + openingWidthMm + 'mm';
        svg.appendChild(widthLabel);

        var depthLabel = na_make_svg('text', {
            x       : layout.viewMaxX - 30,
            y       : layout.wallTopY + (layout.wallDepth / 2),
            fill    : NA_DIM_TEXT_COLOR,
            'text-anchor' : 'end',
            'dominant-baseline' : 'middle',
            'font-size'         : '36'
        });
        depthLabel.textContent = 'D: ' + wallDepthMm + 'mm';
        svg.appendChild(depthLabel);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Layout Calculation
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Compute the Plan View's Geometry Layout in mm
    // ------------------------------------------------------------
    function na_compute_layout(config) {
        var openingWidth     = na_num(config, 'Na__DoorConfig__OpeningWidth_mm',    850);
        var wallDepth        = na_num(config, 'Na__DoorConfig__WallDepth_mm',       105);
        var liningThickness  = na_num(config, 'Na__DoorConfig__LiningThickness_mm',  35);
        var panelThickness   = na_num(config, 'Na__DoorConfig__PanelThickness_mm',   40);
        var swingSide        = (config && config['Na__DoorConfig__SwingSide']) || 'Right';
        var swingDirection   = String((config && config['Na__DoorConfig__SwingDirection']) || 'Inward').toLowerCase();

        var openingX         = NA_WALL_PADDING_MM;
        var totalWidth       = openingWidth + (NA_WALL_PADDING_MM * 2);
        var wallTopY         = NA_VIEW_VERTICAL_PAD_MM;
        var totalHeight      = wallDepth + (NA_VIEW_VERTICAL_PAD_MM * 2);

        var panelClearWidth  = openingWidth - (liningThickness * 2);

        // SVG Y AXIS NOTE:
        // Ruby 3D Y+ maps to the TOP of the SVG plan (small SVG Y), so the
        // mapping is: exterior (far / large Ruby Y) = small SVG Y (top) and
        // room (near / small Ruby Y) = large SVG Y (bottom).
        // Outward opens toward exterior (top / small Y); inward opens toward
        // room (bottom / large Y).  Panel and hinge positions are set
        // accordingly so the closed panel lies on the correct wall face and
        // the swing arc bulges on the correct side.
        var panelY;
        var hingeY;                                                            // <-- Hinge pivot Y: panel's hinge-side face (= wall face the hinge sits on)
        if (swingDirection === 'outward') {
            panelY = wallTopY;                                                 // <-- Flush with TOP wall face (exterior side = small SVG Y); panel swings UP into exterior
            hingeY = wallTopY;                                                 // <-- Hinge on exterior face (top of wall strip)
        } else if (swingDirection === 'inward') {
            panelY = wallTopY + wallDepth - panelThickness;                    // <-- Flush with BOTTOM wall face (room side = large SVG Y); panel swings DOWN into room
            hingeY = wallTopY + wallDepth;                                     // <-- Hinge on room face (bottom of wall strip)
        } else {
            panelY = wallTopY + ((wallDepth - panelThickness) / 2);            // <-- Centred fallback
            hingeY = wallTopY + (wallDepth / 2);                               // <-- Centred fallback
        }

        var panelX           = (swingSide === 'Left')
            ? openingX + liningThickness
            : openingX + openingWidth - liningThickness - panelClearWidth;
        var handleX          = (swingSide === 'Left')
            ? panelX + panelClearWidth - 60
            : panelX + 60;

        // Handle rose + body mirror across the panel centre-line based
        // on swing direction so the rose always sits on the panel face
        // that is being operated from, with the body extending AWAY
        // from the panel (never back into it).
        //
        //   * Outward -> rose on TOP face of panel (exterior side, small SVG Y).
        //     handleY sits on panelY (top of panel rect in SVG). Asset's
        //     local -Y body extends to smaller SVG Y = into exterior above wall.
        //   * Inward  -> rose on BOTTOM face of panel (room side, large SVG Y).
        //     handleY sits on panelY + panelThickness (bottom of panel rect).
        //     Asset's local -Y body must be mirrored to +Y so the body
        //     extends to larger SVG Y = into room below wall.
        var handleY;
        var handleMirrorY;
        if (swingDirection === 'inward') {
            handleY       = panelY + panelThickness;                           // <-- Room face (bottom of panel in SVG)
            handleMirrorY = true;                                              // <-- Flip asset local Y so body extends into room (downward)
        } else {
            handleY       = panelY;                                            // <-- Exterior face (top of panel in SVG)
            handleMirrorY = false;                                             // <-- Asset's local -Y already extends into exterior (upward)
        }
        var handleMirrorX    = (swingSide === 'Left');                         // <-- Mirror local X so the lever points out of the handed side

        return {
            openingWidth     : openingWidth,
            wallDepth        : wallDepth,
            liningThickness  : liningThickness,
            panelThickness   : panelThickness,
            panelClearWidth  : panelClearWidth,
            swingSide        : swingSide,
            swingDirection   : swingDirection,
            handleMirrorX    : handleMirrorX,
            handleMirrorY    : handleMirrorY,
            viewMinX         : 0,
            viewMaxX         : totalWidth,
            viewMinY         : 0,
            viewMaxY         : totalHeight,
            wallTopY         : wallTopY,
            openingX         : openingX,
            panelY           : panelY,
            hingeY           : hingeY,
            handleX          : handleX,
            handleY          : handleY
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Render the Plan View into the Supplied SVG Element
    // ------------------------------------------------------------
    Na_DoorPlanGenerator.na_render = function (svgElement, config) {
        if (!svgElement) return;

        window.Na__Viewport__SvgHelpers.na_clear_svg(svgElement);             // <-- Wipe before re-paint

        var layout  = na_compute_layout(config);
        var palette = na_resolve_door_finish_palette(config);                 // <-- Live finish hex from JSON-sourced swatches

        na_build_wall_layers(svgElement, layout);
        na_build_lining_layers(svgElement, layout, palette);
        na_build_closed_panel(svgElement, layout, palette);
        na_build_handle_preview(svgElement, layout, palette, config);

        if (na_bool(config, 'Na__DoorConfig__ShowSwingArc', true)) {
            na_build_open_panel_outline(svgElement, layout);
            na_build_swing_arc(svgElement, layout);
        }

        na_build_dimension_labels(svgElement, layout, layout.openingWidth, layout.wallDepth);
    };
    // ---------------------------------------------------------------


    // FUNCTION | Compute the Bottom-Left Origin Fit ViewBox for This Plan
    // ------------------------------------------------------------
    // Exposed so the Na__Viewport__Instance fitter callback can reuse
    // the exact extents the layout calculator produces, keeping the
    // pan/zoom reset perfectly aligned with the rendered geometry.
    Na_DoorPlanGenerator.na_fit_to_content = function (config) {
        var layout = na_compute_layout(config);
        return {
            x      : 0,
            y      : 0,
            width  : layout.viewMaxX,
            height : layout.viewMaxY
        };
    };
    // ---------------------------------------------------------------


    window.Na_DoorPlanGenerator = Na_DoorPlanGenerator;

// endregion -------------------------------------------------------------------

})();


// =============================================================================
// END OF FILE
// =============================================================================
