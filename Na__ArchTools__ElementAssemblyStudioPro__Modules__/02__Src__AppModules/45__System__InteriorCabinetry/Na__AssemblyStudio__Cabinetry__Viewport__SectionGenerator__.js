// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - SECTION PREVIEW
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Cabinetry__Viewport__SectionGenerator__.js
// NAMESPACE  : window.Na_CabinetSectionGenerator
// AUTHOR     : Noble Architecture
// PURPOSE    : A side section through the middle of one cabinet in the dialog
//              preview, front on the left and the wall on the right: base
//              panel, top rails or top, back panel and the scribe behind it,
//              shelves, the fronts' thickness and handle projection, drawer
//              boxes, the plinth set back and a leg drawn from its asset
//              outline.
// CREATED    : 29-Oct-2026
//
// COORDINATES
// - From Na__Cabinetry__LayoutResolver (mm). SVG x is the unit's Y (the
//   front, most negative, on the left; the wall, Y = 0, on the right). SVG
//   y is minus the unit's Z.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Na_CabinetSectionGenerator = {};

// -----------------------------------------------------------------------------
// REGION | Palette and Constants
// -----------------------------------------------------------------------------

    var NA_STROKE        = '#4a4a4a';
    var NA_FAINT_STROKE  = '#9a9a9a';
    var NA_CUT_FILL      = '#d9cdb8';                                          // <-- Boards cut by the section
    var NA_BEYOND_FILL   = '#f3f0ea';                                          // <-- The far side panel, seen beyond the cut
    var NA_FRONT_FILL    = '#cbbb9f';
    var NA_DRAWER_FILL   = '#e7dfd0';
    var NA_WALL_FILL     = '#d6d6d6';
    var NA_DIM_TEXT      = '#333333';
    var NA_HANDLE_FILL   = '#b8bcc2';
    var NA_PAD_MM        = 140;
    var NA_WALL_MM       = 60;
    var NA_BAR_END_MM    = 14;                                                 // <-- A horizontal bar seen end on
    var NA_SCRIBE_LABEL_GAP_MM = 6;
    var NA_FALLBACK_PROJECTION_MM = 35;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Helpers
// -----------------------------------------------------------------------------

    function na_svg(tag, attrs) { return window.Na__Viewport__SvgHelpers.na_make_svg(tag, attrs); }

    // HELPER FUNCTION | A Rectangle in Unit (Y, Z) Millimetres
    // ------------------------------------------------------------
    function na_rect(svg, y0, y1, z0, z1, attrs) {
        svg.appendChild(na_svg('rect', Object.assign({
            x: Math.min(y0, y1), y: -Math.max(z0, z1), width: Math.abs(y1 - y0), height: Math.abs(z1 - z0)
        }, attrs)));
    }
    // ---------------------------------------------------------------

    function na_text(svg, y, z, text, attrs) {
        var node = na_svg('text', Object.assign({ x: y, y: -z, fill: NA_DIM_TEXT, 'font-size': 32, 'text-anchor': 'middle' }, attrs));
        node.textContent = text;
        svg.appendChild(node);
    }

    var NA_CUT = { fill: NA_CUT_FILL, stroke: NA_STROKE, 'stroke-width': 1 };

    // HELPER FUNCTION | Label Size That Stays Readable at Any Unit Height (mm)
    // ------------------------------------------------------------
    // A share of what the section shows top to bottom: floor to top for a
    // standing unit, a strip of wall to the top for a wall unit.
    function na_label_size(v) {
        var low = (v.type === 'Wall') ? v.zBase - 200 : 0;
        return Math.max(40, (v.zBase + v.height - low) * 0.05);
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Layers
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Wall, Floor and the Far Side Panel
    // ------------------------------------------------------------
    function na_draw_context(svg, L) {
        var v   = L.values;
        var top = v.zBase + v.height;
        var low = (v.type === 'Wall') ? v.zBase - 200 : 0;
        na_rect(svg, 0, NA_WALL_MM, low, top + na_label_size(v) * 0.5, { fill: NA_WALL_FILL, stroke: 'none' });   // <-- Stops under the depth label
        if (v.type !== 'Wall') {
            svg.appendChild(na_svg('line', { x1: L.bounds.y0 - NA_PAD_MM * 0.6, y1: 0, x2: NA_WALL_MM, y2: 0, stroke: NA_STROKE, 'stroke-width': 2 }));
        }
        var side = L.parts.filter(function (part) { return part.role === 'side'; })[0];
        if (side) na_rect(svg, side.y0, side.y1, side.z0, side.z1, { fill: NA_BEYOND_FILL, stroke: NA_FAINT_STROKE, 'stroke-width': 1 });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Every Board the Section Cuts
    // ------------------------------------------------------------
    function na_draw_boards(svg, L) {
        L.parts.filter(function (part) { return part.role !== 'side'; }).forEach(function (part) {
            na_rect(svg, part.y0, part.y1, part.z0, part.z1, NA_CUT);
        });
        if (L.rail) {
            svg.appendChild(na_svg('circle', { cx: L.rail.y, cy: -L.rail.z, r: L.rail.diameter / 2, fill: '#c9cdd2', stroke: NA_STROKE, 'stroke-width': 1 }));
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Drawer Boxes (Front, Base, Back Cut; Side Beyond)
    // ------------------------------------------------------------
    function na_draw_drawers(svg, L) {
        L.drawerBoxes.forEach(function (box) {
            var side = box.parts[0];
            na_rect(svg, side.y0, side.y1, side.z0, side.z1, { fill: NA_DRAWER_FILL, stroke: NA_FAINT_STROKE, 'stroke-width': 0.8 });
            box.parts.slice(2).forEach(function (part) { na_rect(svg, part.y0, part.y1, part.z0, part.z1, NA_CUT); });
        });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Fronts, With the Groove or Shaker Recess in Profile
    // ------------------------------------------------------------
    function na_draw_fronts(svg, L) {
        L.fronts.forEach(function (front) {
            na_rect(svg, front.y0, front.y1, front.z0, front.z1, { fill: NA_FRONT_FILL, stroke: NA_STROKE, 'stroke-width': 1 });
            if (front.shaker) {
                na_rect(svg, front.y0, front.y0 + front.shaker.recess, front.z0 + front.shaker.rail, front.z1 - front.shaker.rail,
                        { fill: '#ffffff', stroke: NA_STROKE, 'stroke-width': 0.8 });
            }
            var g = front.groove;
            if (g && (g.edge === 'top' || g.edge === 'bottom')) {
                var zLow = (g.edge === 'top') ? front.z1 - g.offset - g.width : front.z0 + g.offset;
                svg.appendChild(na_svg('path', {
                    d: 'M ' + front.y0 + ' ' + (-(zLow + g.width)) + ' L ' + (front.y0 + g.depth - g.width / 2) + ' ' + (-(zLow + g.width)) +
                       ' A ' + (g.width / 2) + ' ' + (g.width / 2) + ' 0 0 1 ' + (front.y0 + g.depth - g.width / 2) + ' ' + (-zLow) +
                       ' L ' + front.y0 + ' ' + (-zLow) + ' Z',
                    fill: '#ffffff', stroke: NA_STROKE, 'stroke-width': 0.8
                }));
            }
        });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Handles Seen From the Side (One Per Front)
    // ------------------------------------------------------------
    // A vertical bar or a knob shows its profile, taken from the asset's own
    // Plan2D (X along the bar, Y out of the door). A horizontal bar is seen
    // end on: its post and bar, one bar's thickness tall.
    function na_draw_handles(svg, L) {
        var cache   = (window.NA_CABINET_ASSET_PREVIEW || {}).handles || {};
        var preview = cache[L.values.handleKey] || null;
        var knob    = window.Na__Cabinetry__LayoutResolver.na_is_knob(L.values.handleKey);
        var proud   = preview ? Number(preview.projection) || NA_FALLBACK_PROJECTION_MM : NA_FALLBACK_PROJECTION_MM;
        var length  = preview ? Number(preview.length) || 160 : 160;
        var paths   = preview && preview.plan && preview.plan.Na__Geometry__Paths;
        var style   = { fill: NA_HANDLE_FILL, stroke: NA_STROKE, 'stroke-width': 0.6 };
        L.handles.forEach(function (handle) {
            var zc = handle.anchor === 'top' ? handle.z - length / 2 : (handle.anchor === 'bottom' ? handle.z + length / 2 : handle.z);
            if ((handle.orientation === 'vertical' || knob) && Array.isArray(paths) && paths.length) {
                var toSvg = function (p) { return [handle.y - (Number(p.Y) || 0), -(zc + (Number(p.X) || 0))]; };
                paths.forEach(function (path) {
                    var type = String(path.PathType || '').toLowerCase();
                    if (type === 'polygon' && Array.isArray(path.Vertices_mm)) {
                        svg.appendChild(na_svg('polygon', Object.assign({ points: path.Vertices_mm.map(function (p) { return toSvg(p).join(','); }).join(' ') }, style)));
                    } else if (type === 'circle' && path.Center_mm) {
                        var c = toSvg(path.Center_mm);
                        svg.appendChild(na_svg('circle', Object.assign({ cx: c[0], cy: c[1], r: Math.max(0.5, Number(path.Radius_mm) || 0) }, style)));
                    }
                });
                return;
            }
            var span = (handle.orientation === 'vertical' && !knob) ? length : NA_BAR_END_MM;
            na_rect(svg, handle.y - proud, handle.y, zc - span / 2, zc + span / 2, Object.assign({ rx: 4 }, style));
        });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Plinth (Cut) and One Front and One Back Leg (Beyond)
    // ------------------------------------------------------------
    function na_draw_base(svg, L) {
        var ys = [];
        L.legs.forEach(function (leg) { if (ys.indexOf(leg.y) === -1) ys.push(leg.y); });
        ys.forEach(function (y) {
            if (window.Na_CabinetElevationGenerator && window.Na_CabinetElevationGenerator.na_draw_leg) {
                window.Na_CabinetElevationGenerator.na_draw_leg(svg, y, L.legHeight, L.values.legKey, function (across, z) { return [across, -z]; });
            }
        });
        if (L.plinth) na_rect(svg, L.plinth.y0, L.plinth.y1, L.plinth.z0, L.plinth.z1, NA_CUT);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Depth, Front and Plinth Labels
    // ------------------------------------------------------------
    function na_draw_dimensions(svg, L) {
        var v    = L.values;
        var top  = v.zBase + v.height;
        var size = na_label_size(v);
        var text = Math.round(v.depth) + (L.fronts.length ? ' + ' + Math.round(v.frontThickness) + ' = ' + Math.round(v.depth + v.frontThickness) : '') + 'mm deep';
        na_text(svg, -v.depth / 2, top + size * 1.4, text, { 'font-size': size });
        if (L.plinth) na_text(svg, L.plinth.y0 - 24, v.zBase / 2, 'set back ' + Math.round(L.plinth.y0 + v.depth), { 'font-size': size * 0.8, 'text-anchor': 'end' });
        if (v.back > 0 && v.backInset > 0.5) {
            na_text(svg, -NA_SCRIBE_LABEL_GAP_MM, top + size * 0.3, 'scribe ' + Math.round(v.backInset), { 'font-size': size * 0.8, 'text-anchor': 'end' });   // <-- Over the void, against the wall
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Paint the Section
    // ------------------------------------------------------------
    Na_CabinetSectionGenerator.na_render = function (svg, cfg) {
        if (!svg || !window.Na__Cabinetry__LayoutResolver) return;
        window.Na__Viewport__SvgHelpers.na_clear_svg(svg);
        var L = window.Na__Cabinetry__LayoutResolver.na_resolve(cfg);
        na_draw_context(svg, L);
        na_draw_base(svg, L);
        na_draw_boards(svg, L);
        na_draw_drawers(svg, L);
        na_draw_fronts(svg, L);
        na_draw_handles(svg, L);
        na_draw_dimensions(svg, L);
    };
    // ---------------------------------------------------------------

    // FUNCTION | The ViewBox That Fits the Section and Its Labels
    // ------------------------------------------------------------
    Na_CabinetSectionGenerator.na_fit_to_content = function (cfg) {
        var L   = window.Na__Cabinetry__LayoutResolver.na_resolve(cfg);
        var v   = L.values;
        var low = (v.type === 'Wall') ? v.zBase - 200 : 0;
        var top = v.zBase + v.height;
        var front = L.bounds.y0 - NA_FALLBACK_PROJECTION_MM;
        var above = Math.max(NA_PAD_MM, na_label_size(v) * 2.6);              // <-- Room for the depth label over the top
        return { x: front - NA_PAD_MM, y: -(top + above), width: (NA_WALL_MM - front) + 2 * NA_PAD_MM, height: (top - low) + above + NA_PAD_MM * 0.6 };
    };
    // ---------------------------------------------------------------

    window.Na_CabinetSectionGenerator = Na_CabinetSectionGenerator;

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
