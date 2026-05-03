// =============================================================================
// NA PLUGIN CORE - DOOR PLAN VIEWPORT SVG GENERATOR
// =============================================================================
//
// FILE       : Na__Viewport__DoorPlanGenerator__.js
// NAMESPACE  : Na_DoorPlanGenerator (browser global, preserved name)
// AUTHOR     : Noble Architecture
// PURPOSE    : Build a 2D plan view of the door opening, lining, panel
//              and dotted swing arc for the dialog's preview.
// CREATED    : 01-May-2026
// RELOCATED  : 01-May-2026 (was in Na__InteriorDoorConfigurator__/)
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
//   4. Dotted door panel outline (swing position)
//   5. Dotted door swing arc
//   6. Dimension labels (W / D)
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
    var NA_WALL_FILL               = '#d8d8d8';                               // <-- Cool grey wall fill
    var NA_WALL_STROKE             = '#666666';                               // <-- Wall outline
    var NA_LINING_FILL             = '#a07e4a';                               // <-- Warm timber lining
    var NA_PANEL_FILL              = '#e6c98e';                               // <-- Door panel
    var NA_PANEL_STROKE            = '#5a4324';                               // <-- Door panel outline
    var NA_SWING_STROKE            = '#5a4324';                               // <-- Swing arc outline
    var NA_DIM_TEXT_COLOR          = '#333333';                               // <-- Dimension label colour
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
    function na_build_lining_layers(svg, layout) {
        var leftLining = na_make_svg('rect', {
            x      : layout.openingX,
            y      : layout.wallTopY,
            width  : layout.liningThickness,
            height : layout.wallDepth,
            fill   : NA_LINING_FILL,
            stroke : NA_PANEL_STROKE,
            'stroke-width' : 0.75
        });
        var rightLining = na_make_svg('rect', {
            x      : layout.openingX + layout.openingWidth - layout.liningThickness,
            y      : layout.wallTopY,
            width  : layout.liningThickness,
            height : layout.wallDepth,
            fill   : NA_LINING_FILL,
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
    function na_build_closed_panel(svg, layout) {
        var x = (layout.swingSide === 'Left')
            ? layout.openingX + layout.liningThickness
            : layout.openingX + layout.openingWidth - layout.liningThickness - layout.panelClearWidth;

        var rect = na_make_svg('rect', {
            x      : x,
            y      : layout.panelY,
            width  : layout.panelClearWidth,
            height : layout.panelThickness,
            fill   : NA_PANEL_FILL,
            stroke : NA_PANEL_STROKE,
            'stroke-width' : 0.75
        });
        svg.appendChild(rect);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the Open-Position (Dotted) Panel Outline
    // ------------------------------------------------------------
    function na_build_open_panel_outline(svg, layout) {
        var hingeX = (layout.swingSide === 'Left')
            ? layout.openingX + layout.liningThickness
            : layout.openingX + layout.openingWidth - layout.liningThickness;
        var hingeY = layout.panelY;

        var dirSign  = (layout.swingSide === 'Left') ? 1 : -1;
        var openRect = na_make_svg('rect', {
            x      : hingeX,
            y      : hingeY - layout.panelClearWidth,
            width  : layout.panelThickness,
            height : layout.panelClearWidth,
            fill   : 'none',
            stroke : NA_PANEL_STROKE,
            'stroke-width'      : 0.5,
            'stroke-dasharray'  : '4 3'
        });
        if (dirSign === -1) {
            openRect.setAttribute('x', hingeX - layout.panelThickness);
        }
        svg.appendChild(openRect);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the Dotted Swing Arc
    // ------------------------------------------------------------
    function na_build_swing_arc(svg, layout) {
        var hingeX = (layout.swingSide === 'Left')
            ? layout.openingX + layout.liningThickness
            : layout.openingX + layout.openingWidth - layout.liningThickness;
        var hingeY = layout.panelY;

        var startX = (layout.swingSide === 'Left')
            ? hingeX + layout.panelClearWidth
            : hingeX - layout.panelClearWidth;
        var startY = hingeY;
        var endX   = hingeX;
        var endY   = hingeY - layout.panelClearWidth;

        var sweepFlag = (layout.swingSide === 'Left') ? 0 : 1;
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

        var openingX         = NA_WALL_PADDING_MM;
        var totalWidth       = openingWidth + (NA_WALL_PADDING_MM * 2);
        var wallTopY         = NA_VIEW_VERTICAL_PAD_MM;
        var totalHeight      = wallDepth + (NA_VIEW_VERTICAL_PAD_MM * 2);

        var panelClearWidth  = openingWidth - (liningThickness * 2);
        var panelY           = wallTopY + ((wallDepth - panelThickness) / 2);

        return {
            openingWidth     : openingWidth,
            wallDepth        : wallDepth,
            liningThickness  : liningThickness,
            panelThickness   : panelThickness,
            panelClearWidth  : panelClearWidth,
            swingSide        : swingSide,
            viewMinX         : 0,
            viewMaxX         : totalWidth,
            viewMinY         : 0,
            viewMaxY         : totalHeight,
            wallTopY         : wallTopY,
            openingX         : openingX,
            panelY           : panelY
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

        var layout = na_compute_layout(config);

        na_build_wall_layers(svgElement, layout);
        na_build_lining_layers(svgElement, layout);
        na_build_closed_panel(svgElement, layout);

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
