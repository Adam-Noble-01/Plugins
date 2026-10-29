// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - ELEVATION PREVIEW
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Cabinetry__Viewport__ElevationGenerator__.js
// NAMESPACE  : window.Na_CabinetElevationGenerator
// AUTHOR     : Noble Architecture
// PURPOSE    : The front elevation of one cabinet in the dialog preview:
//              carcass, fronts in their style (shaker frame and panel,
//              recessed handle groove, flat), handles drawn from each handle
//              asset's own Elevation2D paths, the plinth or the legs, and the
//              width and height. With Interior on, the fronts go see-through
//              to show the shelves, drawer boxes and the wardrobe rail.
// CREATED    : 29-Oct-2026
//
// COORDINATES
// - From Na__Cabinetry__LayoutResolver (millimetres, unit frame). SVG x is
//   the unit's X; SVG y is minus the unit's Z, so up is up.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Na_CabinetElevationGenerator = {};

// -----------------------------------------------------------------------------
// REGION | Palette and Constants
// -----------------------------------------------------------------------------

    var NA_STROKE          = '#4a4a4a';
    var NA_FAINT_STROKE    = '#8c8c8c';
    var NA_DIM_TEXT        = '#333333';
    var NA_FALLBACK_FRONT  = '#E9E4DA';                                       // <-- Before the finish swatches arrive
    var NA_FALLBACK_BODY   = '#F4F2EE';
    var NA_FALLBACK_HANDLE = '#B8BCC2';
    var NA_PLINTH_SHADE    = 0.86;
    var NA_BOARD_SHADE     = 0.86;                                            // <-- Shelves and rails seen with the fronts off
    var NA_DRAWER_FILL     = '#e7dfd0';
    var NA_LEG_FILL        = '#3c3c3c';
    var NA_PAD_MM          = 140;
    var NA_FALLBACK_BAR_MM = 160;
    var NA_LABEL_SHARE     = 0.06;                                            // <-- Label size as a share of the drawing's height
    var NA_LABEL_MIN_MM    = 40;
    var NA_DIGIT_EM        = 0.56;                                            // <-- Rough advance of one character, in ems

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Helpers
// -----------------------------------------------------------------------------

    function na_svg(tag, attrs) { return window.Na__Viewport__SvgHelpers.na_make_svg(tag, attrs); }

    // HELPER FUNCTION | A Swatch Hex From a Live Palette (Fallback Before Push)
    // ------------------------------------------------------------
    function na_hex(materialId, globalName, fallback) {
        var swatches = window[globalName];
        if (!Array.isArray(swatches) || !materialId || materialId === 'MAT001__Default') return fallback;
        var swatch = swatches.filter(function (entry) { return entry && entry.id === materialId; })[0];
        return (swatch && (swatch.hex || swatch.color)) || fallback;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Darken a #RRGGBB Colour by a Factor
    // ------------------------------------------------------------
    function na_shade(hex, factor) {
        var match = /^#?([0-9a-f]{6})$/i.exec(String(hex || ''));
        if (!match) return hex;
        var value = parseInt(match[1], 16);
        var channel = function (shift) { return Math.max(0, Math.min(255, Math.round(((value >> shift) & 255) * factor))); };
        return '#' + [16, 8, 0].map(function (shift) { return ('0' + channel(shift).toString(16)).slice(-2); }).join('');
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | An Axis-Aligned Rectangle in Unit (X, Z) Millimetres
    // ------------------------------------------------------------
    function na_rect(svg, x0, x1, z0, z1, attrs) {
        svg.appendChild(na_svg('rect', Object.assign({
            x: x0, y: -z1, width: Math.max(0, x1 - x0), height: Math.max(0, z1 - z0)
        }, attrs)));
    }
    // ---------------------------------------------------------------

    function na_line(svg, x0, z0, x1, z1, attrs) {
        svg.appendChild(na_svg('line', Object.assign({ x1: x0, y1: -z0, x2: x1, y2: -z1 }, attrs)));
    }

    function na_text(svg, x, z, text, attrs) {
        var node = na_svg('text', Object.assign({ x: x, y: -z, fill: NA_DIM_TEXT, 'font-size': 34, 'text-anchor': 'middle' }, attrs));
        node.textContent = text;
        svg.appendChild(node);
    }

    // HELPER FUNCTION | Preview Data Ruby Pushed for a Handle / Leg Asset
    // ------------------------------------------------------------
    function na_asset_preview(bucket, key) {
        var cache = window.NA_CABINET_ASSET_PREVIEW || {};
        return (cache[bucket] || {})[key] || null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Label Size That Reads at Any Unit Height (mm)
    // ------------------------------------------------------------
    // A share of the drawing's own height, so a 2150 wardrobe's labels read
    // as well in the small preview pane as a 720 base unit's.
    function na_label_size(L) {
        var v   = L.values;
        var low = (v.type === 'Wall') ? v.zBase : 0;
        return Math.max(NA_LABEL_MIN_MM, (v.zBase + v.height - low) * NA_LABEL_SHARE);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Layers
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Carcass Outline, Seen Behind the Fronts
    // ------------------------------------------------------------
    function na_draw_carcass(svg, L, palette) {
        var v = L.values;
        na_rect(svg, 0, v.width, v.zBase, v.zBase + v.height, { fill: palette.body, stroke: NA_STROKE, 'stroke-width': 1.5 });
        L.parts.filter(function (part) { return part.role === 'side'; }).forEach(function (part) {
            na_rect(svg, part.x0, part.x1, part.z0, part.z1, { fill: na_shade(palette.body, 0.94), stroke: NA_FAINT_STROKE, 'stroke-width': 0.8 });
        });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Shelves, Drawer Boxes and Rail (Open Unit or Interior On)
    // ------------------------------------------------------------
    // Drawn as the boards are seen with the fronts off: each shelf, the base,
    // the rails or top by their front edge, each drawer box by its front, and
    // the wardrobe rail across the unit.
    function na_draw_interior(svg, L, palette) {
        var board = { fill: na_shade(palette.body, NA_BOARD_SHADE), stroke: NA_STROKE, 'stroke-width': 0.8 };
        L.parts.filter(function (part) { return ['shelf', 'fixedShelf', 'hatShelf', 'base', 'rail', 'top'].indexOf(part.role) !== -1; })
            .forEach(function (part) { na_rect(svg, part.x0, part.x1, part.z0, part.z1, board); });
        L.drawerBoxes.forEach(function (box) {
            var side = box.parts[0];
            var far  = box.parts[1];
            na_rect(svg, side.x0, far.x1, side.z0, side.z1, { fill: NA_DRAWER_FILL, stroke: NA_STROKE, 'stroke-width': 0.8 });
            na_rect(svg, side.x1, far.x0, side.z0, side.z1, { fill: na_shade(NA_DRAWER_FILL, 0.95), stroke: NA_FAINT_STROKE, 'stroke-width': 0.6 });
        });
        if (L.rail) na_rect(svg, L.rail.x0, L.rail.x1, L.rail.z - L.rail.diameter / 2, L.rail.z + L.rail.diameter / 2,
                            { fill: '#c9cdd2', stroke: NA_STROKE, 'stroke-width': 0.8 });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | One Front in Its Style
    // ------------------------------------------------------------
    function na_draw_front(svg, front, palette) {
        na_rect(svg, front.x0, front.x1, front.z0, front.z1, { fill: palette.front, stroke: NA_STROKE, 'stroke-width': 1.2 });

        if (front.shaker) {
            var s = front.shaker;
            var panel = { fill: na_shade(palette.front, 0.93), stroke: NA_STROKE, 'stroke-width': 0.9 };
            na_rect(svg, front.x0 + s.stile, front.x1 - s.stile, front.z0 + s.rail, front.z1 - s.rail, panel);
            [front.x0 + s.stile, front.x1 - s.stile].forEach(function (x) {                // <-- Rail-to-stile joints
                na_line(svg, x, front.z0, x, front.z0 + s.rail, { stroke: NA_FAINT_STROKE, 'stroke-width': 0.7 });
                na_line(svg, x, front.z1 - s.rail, x, front.z1, { stroke: NA_FAINT_STROKE, 'stroke-width': 0.7 });
            });
        }

        if (front.groove) {
            var g     = front.groove;
            var shade = { fill: na_shade(palette.front, 0.62), stroke: NA_STROKE, 'stroke-width': 0.7 };
            if (g.edge === 'top')    na_rect(svg, front.x0, front.x1, front.z1 - g.offset - g.width, front.z1 - g.offset, shade);
            if (g.edge === 'bottom') na_rect(svg, front.x0, front.x1, front.z0 + g.offset, front.z0 + g.offset + g.width, shade);
            if (g.edge === 'right')  na_rect(svg, front.x1 - g.offset - g.width, front.x1 - g.offset, front.z0, front.z1, shade);
            if (g.edge === 'left')   na_rect(svg, front.x0 + g.offset, front.x0 + g.offset + g.width, front.z0, front.z1, shade);
        }

        // Opening lines, European kitchen convention (Winner's Euro-style
        // hinge symbol): they leave the hinge corners and meet on the handle
        // side. The US symbol is the mirror of this.
        if (front.kind === 'door' && front.hinge) {
            var hingeX = front.hinge === 'Right' ? front.x1 : front.x0;
            var latchX = front.hinge === 'Right' ? front.x0 : front.x1;
            svg.appendChild(na_svg('polyline', {
                points: hingeX + ',' + (-front.z1) + ' ' + latchX + ',' + (-(front.z0 + front.z1) / 2) + ' ' + hingeX + ',' + (-front.z0),
                fill: 'none', stroke: NA_FAINT_STROKE, 'stroke-width': 0.8, 'stroke-dasharray': '14 8'
            }));
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | One Front as a Dashed Outline (Interior View)
    // ------------------------------------------------------------
    function na_draw_front_ghost(svg, front) {
        na_rect(svg, front.x0, front.x1, front.z0, front.z1,
                { fill: 'none', stroke: NA_STROKE, 'stroke-width': 1, 'stroke-dasharray': '12 7', 'stroke-opacity': 0.55 });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | One Handle, From Its Asset's Elevation2D Paths
    // ------------------------------------------------------------
    // Asset frame: X along the bar, Y across. A vertical handle turns X up.
    function na_draw_handle(svg, handle, key, palette) {
        var preview  = na_asset_preview('handles', key);
        var knob     = window.Na__Cabinetry__LayoutResolver.na_is_knob(key);
        var length   = preview ? Number(preview.length) || NA_FALLBACK_BAR_MM : (knob ? 30 : NA_FALLBACK_BAR_MM);
        var centre   = na_handle_centre(handle, length);
        var vertical = handle.orientation === 'vertical' && !knob;
        var toSvg    = function (point) {
            var ax = Number(point.X) || 0;
            var ay = Number(point.Y) || 0;
            return vertical ? [centre.x - ay, -(centre.z + ax)] : [centre.x + ax, -(centre.z + ay)];
        };
        var style = { fill: palette.handle, stroke: NA_STROKE, 'stroke-width': 0.8 };
        var paths = preview && preview.elevation && preview.elevation.Na__Geometry__Paths;

        if (Array.isArray(paths) && paths.length) {
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
        if (knob) {
            svg.appendChild(na_svg('circle', Object.assign({ cx: centre.x, cy: -centre.z, r: 15 }, style)));
            return;
        }
        var half = length / 2;
        if (vertical) na_rect(svg, centre.x - 6, centre.x + 6, centre.z - half, centre.z + half, Object.assign({ rx: 6 }, style));
        else          na_rect(svg, centre.x - half, centre.x + half, centre.z - 6, centre.z + 6, Object.assign({ rx: 6 }, style));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Handle Centre From Its Anchor (Mirrors the Ruby)
    // ------------------------------------------------------------
    function na_handle_centre(handle, length) {
        var half = length / 2;
        switch (handle.anchor) {
            case 'top':    return { x: handle.x, z: handle.z - half };
            case 'bottom': return { x: handle.x, z: handle.z + half };
            case 'right':  return { x: handle.x - half, z: handle.z };
            case 'left':   return { x: handle.x + half, z: handle.z };
            default:       return { x: handle.x, z: handle.z };
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Plinth Face, or the Legs When There Is No Plinth
    // ------------------------------------------------------------
    function na_draw_base(svg, L, palette) {
        if (L.plinth) {
            na_rect(svg, L.plinth.x0, L.plinth.x1, L.plinth.z0, L.plinth.z1,
                    { fill: na_shade(palette.plinth, NA_PLINTH_SHADE), stroke: NA_STROKE, 'stroke-width': 1 });
            return;
        }
        var seen = {};
        L.legs.forEach(function (leg) {
            if (seen[leg.x]) return;
            seen[leg.x] = true;
            Na_CabinetElevationGenerator.na_draw_leg(svg, leg.x, L.legHeight, L.values.legKey, function (x, z) { return [x, -z]; });
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | One Leg, From Its Asset's Side Outline Stretched to Height
    // ------------------------------------------------------------
    // Shared with the section preview. toSvg maps unit (across, z) to SVG.
    Na_CabinetElevationGenerator.na_draw_leg = function (svg, across, height, key, toSvg) {
        var preview = na_asset_preview('legs', key);
        var paths   = preview && preview.elevation && preview.elevation.Na__Geometry__Paths;
        var outline = Array.isArray(paths) ? paths.filter(function (path) { return Array.isArray(path.Vertices_mm); })[0] : null;
        var resolver = window.Na__Cabinetry__LayoutResolver;
        if (outline) {
            var points = outline.Vertices_mm.map(function (p) {
                return toSvg(across + (Number(p.X) || 0), resolver.na_stretch_leg_z(Number(p.Y) || 0, preview, height)).join(',');
            }).join(' ');
            svg.appendChild(na_svg('polygon', { points: points, fill: NA_LEG_FILL, stroke: NA_STROKE, 'stroke-width': 0.6 }));
            return;
        }
        [[11, 18, height - 10], [24, 0, 7], [30, height - 12, height]].forEach(function (band) {
            var a = toSvg(across - band[0], band[2]);
            var b = toSvg(across + band[0], band[1]);
            svg.appendChild(na_svg('rect', { x: Math.min(a[0], b[0]), y: Math.min(a[1], b[1]),
                                             width: Math.abs(b[0] - a[0]), height: Math.abs(b[1] - a[1]), fill: NA_LEG_FILL }));
        });
    };
    // ---------------------------------------------------------------

    // HELPER FUNCTION | One Tick of a Dimension String (Architectural Slash)
    // ------------------------------------------------------------
    function na_tick(svg, x, z, size) {
        var t = size * 0.22;
        na_line(svg, x - t, z - t, x + t, z + t, { stroke: NA_STROKE, 'stroke-width': Math.max(1, size * 0.035) });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | One Span of the Height String, Labelled
    // ------------------------------------------------------------
    // The figure runs up the span when it fits, otherwise it sits level
    // beside the span (a 150 plinth under a 2150 wardrobe).
    function na_height_span(svg, x, z0, z1, value, size) {
        var text = String(Math.round(value));
        var mid  = (z0 + z1) / 2;
        if ((z1 - z0) >= text.length * NA_DIGIT_EM * size * 1.25) {
            na_text(svg, x - size * 0.3, mid, text, { 'font-size': size, transform: 'rotate(-90 ' + (x - size * 0.3) + ' ' + (-mid) + ')' });
        } else {
            na_text(svg, x - size * 0.35, mid, text, { 'font-size': size * 0.8, 'text-anchor': 'end', 'dominant-baseline': 'middle' });
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Floor Line, Width String and Height String
    // ------------------------------------------------------------
    // Down the left: the plinth (or legs) and the carcass as two spans of
    // one string. Under the floor: the width. A wall unit says where it
    // hangs, and where its top lands, instead of standing on a floor.
    function na_draw_dimensions(svg, L) {
        var v    = L.values;
        var size = na_label_size(L);
        var top  = v.zBase + v.height;
        var low  = (v.type === 'Wall') ? v.zBase : 0;
        var line = { stroke: NA_FAINT_STROKE, 'stroke-width': Math.max(0.8, size * 0.025) };

        var x = -size * 0.9;                                                   // <-- Height string, left of the unit
        na_line(svg, x, low, x, top, line);
        [low, v.zBase, top].forEach(function (z, i) { if (i !== 1 || (v.zBase > 0 && v.type !== 'Wall')) na_tick(svg, x, z, size); });
        if (v.type !== 'Wall' && v.zBase > 0) na_height_span(svg, x, 0, v.zBase, v.zBase, size);
        na_height_span(svg, x, v.zBase, top, v.height, size);

        var z = low - size * 0.9;                                              // <-- Width string, under the unit
        na_line(svg, 0, z, v.width, z, line);
        na_tick(svg, 0, z, size);
        na_tick(svg, v.width, z, size);
        na_text(svg, v.width / 2, z - size * 1.15, Math.round(v.width) + 'mm', { 'font-size': size });

        if (v.type === 'Wall') {
            na_text(svg, v.width / 2, top + size * 0.55, 'Hung at ' + Math.round(v.zBase) + ' · top at ' + Math.round(top),
                    { 'font-size': size * 0.75 });
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Paint the Elevation
    // ------------------------------------------------------------
    // @param {SVGElement} svg
    // @param {Object}     cfg     - flat Na__CabinetConfig__* map
    // @param {Object}     options - { interior: Boolean, dimensions: Boolean }
    //                               (dimensions false: a preset thumbnail)
    Na_CabinetElevationGenerator.na_render = function (svg, cfg, options) {
        if (!svg || !window.Na__Cabinetry__LayoutResolver) return;
        window.Na__Viewport__SvgHelpers.na_clear_svg(svg);
        var L          = window.Na__Cabinetry__LayoutResolver.na_resolve(cfg);
        var interior   = !!(options && options.interior);
        var dimensions = !(options && options.dimensions === false);
        var palette  = {
            front : na_hex(cfg['Na__CabinetConfig__DoorMaterialId'],    'NA_FRAME_FINISH_SWATCHES',  NA_FALLBACK_FRONT),
            body  : na_hex(cfg['Na__CabinetConfig__CarcassMaterialId'], 'NA_FRAME_FINISH_SWATCHES',  NA_FALLBACK_BODY),
            handle: na_hex(cfg['Na__CabinetConfig__HandleMaterialId'],  'NA_HANDLE_FINISH_SWATCHES', NA_FALLBACK_HANDLE)
        };
        palette.plinth = (cfg['Na__CabinetConfig__PlinthMatchesDoors'] === false) ? palette.body : palette.front;

        na_draw_base(svg, L, palette);
        na_draw_carcass(svg, L, palette);
        if (interior || !L.fronts.length) na_draw_interior(svg, L, palette);
        L.fronts.forEach(function (front) { if (interior) na_draw_front_ghost(svg, front); else na_draw_front(svg, front, palette); });
        if (!interior) L.handles.forEach(function (handle) { na_draw_handle(svg, handle, L.values.handleKey, palette); });
        if (L.values.type !== 'Wall') {
            na_line(svg, -NA_PAD_MM * 0.8, 0, L.values.width + NA_PAD_MM * 0.8, 0, { stroke: NA_STROKE, 'stroke-width': 2 });
        }
        if (dimensions) na_draw_dimensions(svg, L);
    };
    // ---------------------------------------------------------------

    // FUNCTION | The ViewBox That Fits the Unit and Its Labels
    // ------------------------------------------------------------
    // @param {Object} options - { dimensions: false } fits a thumbnail: the
    //                           unit and its floor line, no label room.
    Na_CabinetElevationGenerator.na_fit_to_content = function (cfg, options) {
        var L     = window.Na__Cabinetry__LayoutResolver.na_resolve(cfg);
        var v     = L.values;
        var low   = (v.type === 'Wall') ? v.zBase : 0;
        var top   = v.zBase + v.height;
        if (options && options.dimensions === false) {
            var pad = NA_PAD_MM * 0.8;
            return { x: -pad, y: -(top + pad * 0.5), width: v.width + 2 * pad, height: (top - low) + pad };
        }
        var size  = na_label_size(L);
        var left  = size * 2.7;                                                // <-- Height string and its figures
        var right = NA_PAD_MM * 0.9;
        var above = (v.type === 'Wall') ? size * 1.5 : size * 0.9;
        var below = size * 2.5;                                                // <-- Width string and its figure
        return { x: -left, y: -(top + above), width: v.width + left + right, height: (top - low) + above + below };
    };
    // ---------------------------------------------------------------

    window.Na_CabinetElevationGenerator = Na_CabinetElevationGenerator;

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
