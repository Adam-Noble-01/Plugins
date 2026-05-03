// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - VIEWPORT ELEVATION SVG
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__Viewport__ElevationGenerator__.js
// NAMESPACE  : Na_DoorElevationGenerator (browser global, preserved name)
// AUTHOR     : Noble Architecture
// PURPOSE    : Build a 2D elevation view of the door (lining U-shape +
//              panel + 2D handle) for the dialog's preview.
// CREATED    : 01-May-2026
// RELOCATED  : 01-May-2026 (was Na__InteriorDoorConfigurator__; now 40__System__InteriorDoorSystem)
// SLIMMED    : 01-May-2026 - now uses Na__Viewport__SvgHelpers for the
//              previously-duplicated na_make_svg / na_num / na_bool /
//              clear-children helpers.
//
// DESCRIPTION:
// - Renders a head-on view of the door opening with the U-shaped door
//   lining (left jamb, head, right jamb), the panel inside, and a
//   simple handle marker. Future revisions will consume the unified
//   handle JSON (Na__Asset__Elevation2D paths) for richer 2D handle
//   geometry.
//
// COORDINATE SYSTEM:
// - Units: millimetres. Y-axis flipped (top of opening at low Y).
// - Origin: top-left of the SVG canvas, with horizontal padding so
//   the architrave outline (offset 5mm by default) stays visible.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';

    var Na_DoorElevationGenerator = {};                                       // <-- Public namespace


// -----------------------------------------------------------------------------
// REGION | Constants
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | Layout Padding
    // ------------------------------------------------------------
    var NA_HORIZONTAL_PADDING_MM   = 200;                                     // <-- mm padding either side of the opening
    var NA_VERTICAL_PADDING_MM     = 200;                                     // <-- mm padding above & below the opening
    // ---------------------------------------------------------------

    // MODULE CONSTANTS | Palette
    // ------------------------------------------------------------
    // Lining + panel + handle fills are now driven by the live finish
    // swatches (window.NA_FRAME_FINISH_SWATCHES) selected in the Joinery
    // Finish + Handle Finish card rows. Strokes and the dimension text
    // colour stay fixed for clarity.
    var NA_LINING_STROKE           = '#5a4324';                               // <-- Lining outline
    var NA_PANEL_STROKE            = '#5a4324';                               // <-- Door panel outline
    var NA_ARCHITRAVE_STROKE       = '#5a4324';                               // <-- Architrave outline
    var NA_HANDLE_STROKE           = '#5a4324';                               // <-- Handle rose outline
    var NA_DIM_TEXT_COLOR          = '#333333';                               // <-- Dimension label colour
    var NA_FALLBACK_TIMBER_HEX     = '#D2B48C';                               // <-- Used only before frame swatches arrive
    var NA_FALLBACK_HANDLE_HEX     = '#C0AE8A';                               // <-- Unlacquered Brass fallback (matches handle default)
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
// REGION | Material Hex Resolution (Live from NA_FRAME_FINISH_SWATCHES)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve a Material ID to a Hex Colour String
    // ------------------------------------------------------------
    // Reads the named window global (pushed in by Ruby from the central
    // materials JSON). Frame fills come from NA_FRAME_FINISH_SWATCHES,
    // handle fills come from NA_HANDLE_FINISH_SWATCHES. Falls back to the
    // supplied neutral tone only when the swatches have not arrived yet.
    function na_resolve_material_hex(materialId, fallbackHex, swatchesGlobalName) {
        var swatches = window[swatchesGlobalName];
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

    // HELPER FUNCTION | Resolve the Elevation Lining + Panel + Handle Fills
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
// REGION | Layout Calculation
// -----------------------------------------------------------------------------

    function na_compute_layout(config) {
        var openingWidth     = na_num(config, 'Na__DoorConfig__OpeningWidth_mm',    850);
        var openingHeight    = na_num(config, 'Na__DoorConfig__OpeningHeight_mm',  2100);
        var liningThickness  = na_num(config, 'Na__DoorConfig__LiningThickness_mm',  35);
        var archOffset       = na_num(config, 'Na__DoorConfig__ArchitraveOffset_mm', 5);
        var archEnabled      = na_bool(config, 'Na__DoorConfig__ArchitraveEnabled', true);
        var swingSide        = (config && config['Na__DoorConfig__SwingSide'])  || 'Right';
        var handleHeight     = na_num(config, 'Na__DoorConfig__HandleHeight_mm', 1050);

        var totalWidth       = openingWidth + (NA_HORIZONTAL_PADDING_MM * 2);
        var totalHeight      = openingHeight + (NA_VERTICAL_PADDING_MM * 2);

        var openingX         = NA_HORIZONTAL_PADDING_MM;
        var openingTopY      = NA_VERTICAL_PADDING_MM;
        var openingBottomY   = openingTopY + openingHeight;

        var panelClearWidth  = openingWidth - (liningThickness * 2);
        var panelClearHeight = openingHeight - liningThickness;
        var panelX           = openingX + liningThickness;
        var panelTopY        = openingTopY + liningThickness;
        var panelBottomY     = openingBottomY;

        var handleX = (swingSide === 'Left')
            ? panelX + panelClearWidth - 60
            : panelX + 60;
        var handleY = panelBottomY - handleHeight;

        return {
            totalWidth       : totalWidth,
            totalHeight      : totalHeight,
            openingX         : openingX,
            openingTopY      : openingTopY,
            openingWidth     : openingWidth,
            openingHeight    : openingHeight,
            liningThickness  : liningThickness,
            archOffset       : archOffset,
            archEnabled      : archEnabled,
            panelX           : panelX,
            panelTopY        : panelTopY,
            panelClearWidth  : panelClearWidth,
            panelClearHeight : panelClearHeight,
            handleX          : handleX,
            handleY          : handleY
        };
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Layer Builders
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Build the Door Lining U-Shape
    // ------------------------------------------------------------
    function na_build_lining_u_shape(svg, layout, palette) {
        var x  = layout.openingX;
        var y  = layout.openingTopY;
        var w  = layout.openingWidth;
        var h  = layout.openingHeight;
        var lt = layout.liningThickness;

        var d = 'M ' + x + ' ' + (y + h) +
                ' L ' + x + ' ' + y +
                ' L ' + (x + w) + ' ' + y +
                ' L ' + (x + w) + ' ' + (y + h) +
                ' L ' + (x + w - lt) + ' ' + (y + h) +
                ' L ' + (x + w - lt) + ' ' + (y + lt) +
                ' L ' + (x + lt) + ' ' + (y + lt) +
                ' L ' + (x + lt) + ' ' + (y + h) +
                ' Z';

        var path = na_make_svg('path', {
            d              : d,
            fill           : palette.liningFill,
            stroke         : NA_LINING_STROKE,
            'stroke-width' : 1
        });
        svg.appendChild(path);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the Door Panel Rectangle
    // ------------------------------------------------------------
    function na_build_panel(svg, layout, palette) {
        var rect = na_make_svg('rect', {
            x      : layout.panelX,
            y      : layout.panelTopY,
            width  : layout.panelClearWidth,
            height : layout.panelClearHeight,
            fill   : palette.panelFill,
            stroke : NA_PANEL_STROKE,
            'stroke-width' : 1
        });
        svg.appendChild(rect);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the Architrave Outline (3 sides + offset)
    // ------------------------------------------------------------
    function na_build_architrave_outline(svg, layout) {
        var x  = layout.openingX - layout.archOffset;
        var y  = layout.openingTopY - layout.archOffset;
        var w  = layout.openingWidth + (layout.archOffset * 2);
        var h  = layout.openingHeight + layout.archOffset;

        var d = 'M ' + x + ' ' + (y + h) +
                ' L ' + x + ' ' + y +
                ' L ' + (x + w) + ' ' + y +
                ' L ' + (x + w) + ' ' + (y + h);

        var path = na_make_svg('path', {
            d                  : d,
            fill               : 'none',
            stroke             : NA_ARCHITRAVE_STROKE,
            'stroke-width'     : 0.75,
            'stroke-dasharray' : '6 3'
        });
        svg.appendChild(path);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build a Simple Handle Marker
    // ------------------------------------------------------------
    function na_build_handle_marker(svg, layout, palette) {
        var rose = na_make_svg('circle', {
            cx     : layout.handleX,
            cy     : layout.handleY,
            r      : 18,
            fill   : palette.handleFill,
            stroke : NA_HANDLE_STROKE,
            'stroke-width' : 0.75
        });
        svg.appendChild(rose);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build the W/H Dimension Labels
    // ------------------------------------------------------------
    function na_build_dimension_labels(svg, layout) {
        var w = na_make_svg('text', {
            x             : layout.openingX + (layout.openingWidth / 2),
            y             : layout.openingTopY - 40,
            fill          : NA_DIM_TEXT_COLOR,
            'text-anchor' : 'middle',
            'font-size'   : '40'
        });
        w.textContent = 'W: ' + layout.openingWidth + 'mm';
        svg.appendChild(w);

        var h = na_make_svg('text', {
            x                   : layout.openingX - 60,
            y                   : layout.openingTopY + (layout.openingHeight / 2),
            fill                : NA_DIM_TEXT_COLOR,
            'text-anchor'       : 'end',
            'dominant-baseline' : 'middle',
            'font-size'         : '40'
        });
        h.textContent = 'H: ' + layout.openingHeight + 'mm';
        svg.appendChild(h);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Render the Elevation View into the Supplied SVG Element
    // ------------------------------------------------------------
    Na_DoorElevationGenerator.na_render = function (svgElement, config) {
        if (!svgElement) return;

        window.Na__Viewport__SvgHelpers.na_clear_svg(svgElement);             // <-- Wipe before re-paint

        var layout  = na_compute_layout(config);
        var palette = na_resolve_door_finish_palette(config);                 // <-- Live finish hex from JSON-sourced swatches

        if (layout.archEnabled) na_build_architrave_outline(svgElement, layout);
        na_build_lining_u_shape(svgElement, layout, palette);
        na_build_panel(svgElement, layout, palette);
        na_build_handle_marker(svgElement, layout, palette);
        na_build_dimension_labels(svgElement, layout);
    };
    // ---------------------------------------------------------------


    // FUNCTION | Compute the Fit ViewBox for This Elevation
    // ------------------------------------------------------------
    // Exposed so the Na__Viewport__Instance fitter callback can reuse
    // the exact extents the layout calculator produces.
    Na_DoorElevationGenerator.na_fit_to_content = function (config) {
        var layout = na_compute_layout(config);
        return {
            x      : 0,
            y      : 0,
            width  : layout.totalWidth,
            height : layout.totalHeight
        };
    };
    // ---------------------------------------------------------------


    window.Na_DoorElevationGenerator = Na_DoorElevationGenerator;

// endregion -------------------------------------------------------------------

})();


// =============================================================================
// END OF FILE
// =============================================================================
