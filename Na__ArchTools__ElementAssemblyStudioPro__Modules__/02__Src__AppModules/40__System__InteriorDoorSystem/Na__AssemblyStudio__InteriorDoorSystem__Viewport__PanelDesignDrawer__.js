// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - VIEWPORT PANEL DESIGN
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__Viewport__PanelDesignDrawer__.js
// NAMESPACE  : Na_DoorPanelDesignDrawer (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : SVG mirror of the Ruby Na__PanelDesignBuilder + style modules.
//              Renders the inner perimeter, cross-rail pairs and mullion pairs
//              for the four UK door styles (Vertical Narrow, Classical Six,
//              Four-Panel, Horizontal Three) inside the elevation preview, with
//              the same butt-joint clipping the 3D side uses.
// CREATED    : 03-May-2026
//
// DESCRIPTION:
// - The elevation preview already draws the panel rectangle (via the
//   ElevationGenerator's na_build_panel). This module overlays the panel
//   design linework on top of that rectangle, faithfully reproducing the
//   3D output so the user gets immediate visual feedback when adjusting
//   the panel design controls.
// - All inputs are millimetres in PANEL-LOCAL coordinates (origin at
//   the panel's top-left in SVG space). The drawer translates to the
//   absolute SVG coordinates supplied by the elevation layout.
// - SVG Y is FLIPPED relative to the Ruby Z axis (top-of-panel sits at
//   panelTopY in SVG). The drawer flips Z internally so style code can
//   stay 1:1 with the Ruby intent.
//
// PUBLIC API:
//   Na_DoorPanelDesignDrawer.na_render(svg, panelLayout, config)
//
//   panelLayout : { panelX, panelTopY, panelClearWidth, panelClearHeight }
//   config      : current Na__DoorConfig__* hash (only PanelDesign* keys are read)
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';

    var Na_DoorPanelDesignDrawer = {};                                        // <-- Public namespace


// -----------------------------------------------------------------------------
// REGION | Constants
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | Defaults Mirroring the Ruby PanelDesignBuilder
    // ------------------------------------------------------------
    var NA_STYLE_NONE                 = 'None';
    var NA_STYLE_VERTICAL_NARROW      = 'VerticalNarrow';
    var NA_STYLE_CLASSICAL_SIX        = 'ClassicalSixPanel';
    var NA_STYLE_FOUR_PANEL           = 'FourPanel';
    var NA_STYLE_HORIZONTAL_THREE     = 'HorizontalThree';

    var NA_DEFAULT_STILE_W                = 95;
    var NA_DEFAULT_TOP_RAIL               = 100;
    var NA_DEFAULT_BOTTOM_RAIL            = 200;
    var NA_DEFAULT_INNER_RAIL_T           = 70;
    var NA_DEFAULT_VERTICAL_PANE_W        = 90;
    var NA_DEFAULT_FOUR_PANEL_CROSS_RAIL_T  = 200;                              // <-- Mirrors Ruby NA_DEFAULT_FOUR_PANEL_CROSS_RAIL_T
    var NA_DEFAULT_HANDLE_HEIGHT            = 900;                              // <-- Mirrors Ruby NA_DEFAULT_HANDLE_HEIGHT
    var NA_DEFAULT_SIX_PANEL_LOCK_RAIL_T   = 200;                              // <-- Mirrors Ruby NA_DEFAULT_SIX_PANEL_LOCK_RAIL_T
    var NA_DEFAULT_SIX_PANEL_MID_RAIL_T    = 125;                              // <-- Mirrors Ruby NA_DEFAULT_SIX_PANEL_MID_RAIL_T

    var NA_MIN_INNER_DIMENSION_MM     = 50.0;
    var NA_DESIGN_STROKE              = '#5a4324';
    var NA_DESIGN_STROKE_WIDTH        = 1;

    // Tier ratios for the Classical Six layout (must mirror Ruby).
    var NA_TIER_RATIO_BOTTOM          = 0.38;
    var NA_TIER_RATIO_MIDDLE          = 0.38;

    // Horizontal-Three boundary ratios.
    var NA_HZ3_LOWER_BOUNDARY         = 1.0 / 3.0;
    var NA_HZ3_UPPER_BOUNDARY         = 2.0 / 3.0;
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Shared Helper Aliases
// -----------------------------------------------------------------------------

    function na_make_svg(tag, attrs) {
        return window.Na__Viewport__SvgHelpers.na_make_svg(tag, attrs);
    }

    function na_num(config, key, fallback) {
        return window.Na__Viewport__SvgHelpers.na_num(config, key, fallback);
    }

    function na_bool(config, key, fallback) {
        return window.Na__Viewport__SvgHelpers.na_bool(config, key, fallback);
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Layout Computation (Panel-Local -> SVG Coordinates)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Translate Panel-Local (X, Z) Into Absolute SVG (X, Y)
    // ------------------------------------------------------------
    // Panel-local axes match the Ruby model: X right, Z up. SVG Y is
    // flipped, so SVG_Y(z) = panel_top_Y + (panel_height - z). The
    // inner perimeter then sits inside the panel rect with stile,
    // top rail and bottom rail offsets applied.
    function na_compute_layout(panelLayout, config) {
        var panelW       = panelLayout.panelClearWidth;
        var panelH       = panelLayout.panelClearHeight;
        var stileW       = na_num(config, 'Na__DoorConfig__PanelDesignStileWidth_mm',          NA_DEFAULT_STILE_W);
        var topRail      = na_num(config, 'Na__DoorConfig__PanelDesignTopRail_mm',             NA_DEFAULT_TOP_RAIL);
        var bottomRail   = na_num(config, 'Na__DoorConfig__PanelDesignBottomRail_mm',          NA_DEFAULT_BOTTOM_RAIL);
        var innerRailT   = na_num(config, 'Na__DoorConfig__PanelDesignInnerRailThickness_mm',  NA_DEFAULT_INNER_RAIL_T);
        var crossRailT      = na_num(config, 'Na__DoorConfig__FourPanel__CrossRailThickness_mm',  NA_DEFAULT_FOUR_PANEL_CROSS_RAIL_T);
        var handleHeight    = na_num(config, 'Na__DoorConfig__HandleHeight_mm',                   NA_DEFAULT_HANDLE_HEIGHT);
        var sixLockRailT    = na_num(config, 'Na__DoorConfig__ClassicalSix__LockRailThickness_mm', NA_DEFAULT_SIX_PANEL_LOCK_RAIL_T);
        var sixMidRailT     = na_num(config, 'Na__DoorConfig__ClassicalSix__MidRailThickness_mm',  NA_DEFAULT_SIX_PANEL_MID_RAIL_T);

        var innerW       = panelW - (stileW * 2);
        var innerH       = panelH - topRail - bottomRail;

        var innerYMin    = panelLayout.panelTopY + topRail;                     // <-- SVG Y at INNER top (corresponds to Ruby inner_z_max)
        var innerYMax    = panelLayout.panelTopY + panelH - bottomRail;         // <-- SVG Y at INNER bottom (corresponds to Ruby inner_z_min)
        var midY         = (innerYMin + innerYMax) / 2.0;

        // Resolve the four-panel cross-rail centre at handle height, clamped to fit inside the inner perimeter.
        // SVG Y is flipped: handle height rises from the panel BOTTOM, so crossRailY = panelTopY + panelH - handleHeight.
        var halfCross    = crossRailT / 2.0;
        var yMinSafe     = innerYMin + halfCross;                               // <-- Highest safe centre (small SVG Y)
        var yMaxSafe     = innerYMax - halfCross;                               // <-- Lowest safe centre (large SVG Y)
        var rawY         = panelLayout.panelTopY + panelH - handleHeight;
        var fourPanelCrossRailYCentre = (yMinSafe < yMaxSafe)
            ? Math.min(yMaxSafe, Math.max(yMinSafe, rawY))
            : midY;                                                             // <-- Fallback: geometric mid if perimeter is too small

        return {
            panelX                    : panelLayout.panelX,
            panelTopY                 : panelLayout.panelTopY,
            panelW                    : panelW,
            panelH                    : panelH,
            innerXMin                 : panelLayout.panelX + stileW,
            innerXMax                 : panelLayout.panelX + panelW - stileW,
            innerYMin                 : innerYMin,
            innerYMax                 : innerYMax,
            innerW                    : innerW,
            innerH                    : innerH,
            innerRailT                : innerRailT,
            crossRailT                : crossRailT,                            // <-- Four-panel lockrail thickness (mm)
            fourPanelCrossRailYCentre : fourPanelCrossRailYCentre,             // <-- Clamped handle-height position (SVG Y)
            sixLockRailT              : sixLockRailT,                          // <-- Classical Six lower lockrail thickness (mm)
            sixMidRailT               : sixMidRailT,                           // <-- Classical Six upper mid-rail thickness (mm)
            innerPerimValid           : (innerW >= NA_MIN_INNER_DIMENSION_MM &&
                                        innerH >= NA_MIN_INNER_DIMENSION_MM)
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Segmented Line Drawing (Joint Clipping)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Draw a Horizontal Line With Gaps
    // ------------------------------------------------------------
    // Walks left-to-right, skipping each [start, end] gap so the
    // line breaks cleanly at every perpendicular rail/mullion.
    function na_draw_horizontal_segmented(svg, x0, x1, y, gaps) {
        if (x1 <= x0) return;
        var cursor = x0;
        var sortedGaps = (gaps || []).slice().sort(function (a, b) { return a[0] - b[0]; });
        for (var i = 0; i < sortedGaps.length; i++) {
            var gapStart = sortedGaps[i][0];
            var gapEnd   = sortedGaps[i][1];
            if (gapEnd <= cursor) continue;
            if (gapStart >= x1) break;
            if (gapStart > cursor) {
                na_append_line(svg, cursor, y, gapStart, y);
            }
            if (gapEnd > cursor) cursor = gapEnd;
        }
        if (cursor < x1) {
            na_append_line(svg, cursor, y, x1, y);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Draw a Vertical Line With Gaps
    // ------------------------------------------------------------
    // SVG-space gaps are expressed in SVG Y coordinates (top-down),
    // so the smaller Y value is the visually-higher edge.
    function na_draw_vertical_segmented(svg, x, y0, y1, gaps) {
        if (y1 <= y0) return;
        var cursor = y0;
        var sortedGaps = (gaps || []).slice().sort(function (a, b) { return a[0] - b[0]; });
        for (var i = 0; i < sortedGaps.length; i++) {
            var gapStart = sortedGaps[i][0];
            var gapEnd   = sortedGaps[i][1];
            if (gapEnd <= cursor) continue;
            if (gapStart >= y1) break;
            if (gapStart > cursor) {
                na_append_line(svg, x, cursor, x, gapStart);
            }
            if (gapEnd > cursor) cursor = gapEnd;
        }
        if (cursor < y1) {
            na_append_line(svg, x, cursor, x, y1);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Append a Single SVG Line With the Standard Stroke
    // ------------------------------------------------------------
    function na_append_line(svg, x1, y1, x2, y2) {
        if (Math.abs(x2 - x1) < 0.01 && Math.abs(y2 - y1) < 0.01) return;
        svg.appendChild(na_make_svg('line', {
            x1: x1, y1: y1, x2: x2, y2: y2,
            stroke: NA_DESIGN_STROKE,
            'stroke-width': NA_DESIGN_STROKE_WIDTH
        }));
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Frame Helpers (SVG-Space Mirror of PanelDesignFrame.rb)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Convert Mullion Specs to SVG-Space X-Range Gaps
    // ------------------------------------------------------------
    function na_mullions_to_x_gaps(mullions) {
        return (mullions || []).map(function (m) { return [m.xLeft, m.xRight]; });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Convert Cross-Rail Specs to SVG-Space Y-Range Gaps
    // ------------------------------------------------------------
    // The Ruby version uses Z (up). In SVG space, Y is flipped, so
    // a Z band [z_low, z_high] becomes a Y band [y_high, y_low] and
    // we re-sort ascending to keep the segmented drawer happy.
    function na_cross_rails_to_y_gaps(cross_rails) {
        return (cross_rails || []).map(function (cr) {
            return [Math.min(cr.yTop, cr.yBottom), Math.max(cr.yTop, cr.yBottom)];
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Draw the Inner Perimeter With Joint Clipping
    // ------------------------------------------------------------
    function na_draw_inner_perimeter(svg, layout, mullions, cross_rails) {
        if (!layout.innerPerimValid) return;
        var xGaps = na_mullions_to_x_gaps(mullions);
        var yGaps = na_cross_rails_to_y_gaps(cross_rails);
        na_draw_horizontal_segmented(svg, layout.innerXMin, layout.innerXMax, layout.innerYMin, xGaps);
        na_draw_horizontal_segmented(svg, layout.innerXMin, layout.innerXMax, layout.innerYMax, xGaps);
        na_draw_vertical_segmented(svg, layout.innerXMin, layout.innerYMin, layout.innerYMax, yGaps);
        na_draw_vertical_segmented(svg, layout.innerXMax, layout.innerYMin, layout.innerYMax, yGaps);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Draw a Horizontal Cross-Rail Pair (Gap-Clipped)
    // ------------------------------------------------------------
    // railThicknessMm overrides layout.innerRailT when supplied and > 0,
    // allowing the FourPanel lockrail to use 200 mm while other callers
    // retain the shared innerRailT (70 mm default).
    function na_draw_horizontal_rail_pair(svg, layout, yCentre, mullions, railThicknessMm) {
        var thickness = (railThicknessMm && railThicknessMm > 0) ? railThicknessMm : layout.innerRailT;
        var halfT = thickness / 2.0;
        var xGaps = na_mullions_to_x_gaps(mullions);
        na_draw_horizontal_segmented(svg, layout.innerXMin, layout.innerXMax, yCentre - halfT, xGaps);
        na_draw_horizontal_segmented(svg, layout.innerXMin, layout.innerXMax, yCentre + halfT, xGaps);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Draw a Vertical Mullion Pair (Gap-Clipped)
    // ------------------------------------------------------------
    function na_draw_vertical_mullion_pair(svg, layout, xCentre, cross_rails) {
        var halfT = layout.innerRailT / 2.0;
        var yGaps = na_cross_rails_to_y_gaps(cross_rails);
        na_draw_vertical_segmented(svg, xCentre - halfT, layout.innerYMin, layout.innerYMax, yGaps);
        na_draw_vertical_segmented(svg, xCentre + halfT, layout.innerYMin, layout.innerYMax, yGaps);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Style Builders (SVG-Space Mirrors of the Ruby Style Modules)
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Vertical Narrow - normalised pane subdivision
    // ------------------------------------------------------------
    function na_build_vertical_narrow(svg, layout, config) {
        na_draw_inner_perimeter(svg, layout, [], []);

        var preferredPaneW = na_num(config, 'Na__DoorConfig__PanelDesignVerticalPaneWidth_mm', NA_DEFAULT_VERTICAL_PANE_W);
        var divisions = Math.max(1, Math.round(layout.innerW / Math.max(1, preferredPaneW)));
        if (divisions <= 1) return;
        var paneW = layout.innerW / divisions;
        for (var i = 1; i < divisions; i++) {
            var x = layout.innerXMin + (paneW * i);
            na_append_line(svg, x, layout.innerYMin, x, layout.innerYMax);
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Classical Six - 38/38/24 tiers + central mullion
    // ------------------------------------------------------------
    // SVG Y is top-down so the "lower tier boundary" (Ruby Z space)
    // corresponds to a HIGHER SVG Y value (closer to bottom of canvas).
    // Each cross-rail now uses its own thickness to match real Georgian doors:
    //   - Lower lockrail (crossLowYCentre)  : sixLockRailT (default 200 mm)
    //   - Upper mid-rail (crossHighYCentre) : sixMidRailT  (default 125 mm)
    // The vertical mullion keeps using innerRailT (default 70 mm).
    function na_build_classical_six(svg, layout) {
        var halfLock    = layout.sixLockRailT / 2.0;
        var halfMid     = layout.sixMidRailT  / 2.0;
        var halfMullion = layout.innerRailT   / 2.0;
        var innerH      = layout.innerH;
        var innerYMax   = layout.innerYMax;                                     // <-- bottom of inner perimeter (high SVG Y)
        var crossLowYCentre  = innerYMax - (innerH * NA_TIER_RATIO_BOTTOM);
        var crossHighYCentre = innerYMax - (innerH * (NA_TIER_RATIO_BOTTOM + NA_TIER_RATIO_MIDDLE));
        var mullionXCentre   = (layout.innerXMin + layout.innerXMax) / 2.0;

        var crossRails = [
            { yTop: crossLowYCentre  - halfLock, yBottom: crossLowYCentre  + halfLock, yCentre: crossLowYCentre  },
            { yTop: crossHighYCentre - halfMid,  yBottom: crossHighYCentre + halfMid,  yCentre: crossHighYCentre }
        ];
        var mullions = [
            { xLeft: mullionXCentre - halfMullion, xRight: mullionXCentre + halfMullion, xCentre: mullionXCentre }
        ];

        na_draw_inner_perimeter(svg, layout, mullions, crossRails);
        na_draw_horizontal_rail_pair(svg, layout, crossLowYCentre,  mullions, layout.sixLockRailT); // <-- 200 mm lockrail
        na_draw_horizontal_rail_pair(svg, layout, crossHighYCentre, mullions, layout.sixMidRailT);  // <-- 125 mm mid-rail
        mullions.forEach(function (m) {
            na_draw_vertical_mullion_pair(svg, layout, m.xCentre, crossRails);
        });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Four-Panel - 2x2 grid
    // ------------------------------------------------------------
    // Mirrors Ruby Na__PanelDesignStyles__FourPanel.na_build_face_lines:
    // - Cross-rail centred at handle height (clamped), thickness = crossRailT (200 mm default).
    // - Vertical mullion uses innerRailT (70 mm default) independently.
    function na_build_four_panel(svg, layout) {
        var halfCross      = layout.crossRailT / 2.0;
        var halfMullion    = layout.innerRailT / 2.0;
        var crossYCentre   = layout.fourPanelCrossRailYCentre;                 // <-- Handle-height-aligned, pre-clamped
        var mullionXCentre = (layout.innerXMin + layout.innerXMax) / 2.0;

        var crossRails = [
            { yTop: crossYCentre - halfCross, yBottom: crossYCentre + halfCross, yCentre: crossYCentre }
        ];
        var mullions = [
            { xLeft: mullionXCentre - halfMullion, xRight: mullionXCentre + halfMullion, xCentre: mullionXCentre }
        ];

        na_draw_inner_perimeter(svg, layout, mullions, crossRails);
        na_draw_horizontal_rail_pair(svg, layout, crossYCentre, mullions, layout.crossRailT); // <-- Pass 200 mm thickness
        na_draw_vertical_mullion_pair(svg, layout, mullionXCentre, crossRails);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Horizontal Three - two cross-rails, no mullion
    // ------------------------------------------------------------
    function na_build_horizontal_three(svg, layout) {
        var halfT = layout.innerRailT / 2.0;
        var innerH = layout.innerH;
        var innerYMax = layout.innerYMax;
        var lowerYCentre = innerYMax - (innerH * NA_HZ3_LOWER_BOUNDARY);
        var upperYCentre = innerYMax - (innerH * NA_HZ3_UPPER_BOUNDARY);

        var crossRails = [
            { yTop: lowerYCentre - halfT, yBottom: lowerYCentre + halfT, yCentre: lowerYCentre },
            { yTop: upperYCentre - halfT, yBottom: upperYCentre + halfT, yCentre: upperYCentre }
        ];
        var mullions = [];

        na_draw_inner_perimeter(svg, layout, mullions, crossRails);
        crossRails.forEach(function (cr) {
            na_draw_horizontal_rail_pair(svg, layout, cr.yCentre, mullions);
        });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Render the Panel Design Linework Onto an SVG Element
    // ------------------------------------------------------------
    // Returns silently (no-op) when the design subsystem is disabled,
    // when the requested style is "None" / unknown, or when the inner
    // perimeter would invert under aggressive slider values.
    //
    // @param {SVGElement} svg          - target SVG element
    // @param {Object}     panelLayout  - { panelX, panelTopY, panelClearWidth, panelClearHeight }
    // @param {Object}     config       - current Na__DoorConfig__* hash
    Na_DoorPanelDesignDrawer.na_render = function (svg, panelLayout, config) {
        if (!svg || !panelLayout || !config) return;
        if (!na_bool(config, 'Na__DoorConfig__PanelDesignEnabled', true)) return;

        var style = (config['Na__DoorConfig__PanelDesignStyle'] || NA_STYLE_NONE).toString();
        if (style === NA_STYLE_NONE) return;

        var layout = na_compute_layout(panelLayout, config);
        if (!layout.innerPerimValid) return;

        switch (style) {
            case NA_STYLE_VERTICAL_NARROW:
                na_build_vertical_narrow(svg, layout, config);
                break;
            case NA_STYLE_CLASSICAL_SIX:
                na_build_classical_six(svg, layout);
                break;
            case NA_STYLE_FOUR_PANEL:
                na_build_four_panel(svg, layout);
                break;
            case NA_STYLE_HORIZONTAL_THREE:
                na_build_horizontal_three(svg, layout);
                break;
            default:
                console.warn('[Na_DoorPanelDesignDrawer] Unknown style:', style);
        }
    };
    // ---------------------------------------------------------------

    window.Na_DoorPanelDesignDrawer = Na_DoorPanelDesignDrawer;

// endregion -------------------------------------------------------------------

})();


// =============================================================================
// END OF FILE
// =============================================================================
