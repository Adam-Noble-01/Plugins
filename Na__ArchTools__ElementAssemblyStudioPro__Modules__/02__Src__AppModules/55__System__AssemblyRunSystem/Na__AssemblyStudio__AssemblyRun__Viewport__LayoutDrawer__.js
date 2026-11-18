// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - LAYOUT DRAWER
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AssemblyRun__Viewport__LayoutDrawer__.js
// NAMESPACE  : Na__AssemblyRun__LayoutDrawer (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Draws a run's resolved layout as two SVG drawings: the PLAN
//              (the path, each span and column in its place, the corners) and
//              the ELEVATION (every leg unfolded into one line, as you walk
//              along the side the elements are seen from), each with its
//              dimensions.
// CREATED    : 16-Nov-2026 (V2.7.0); zoom-aware labels and dimensions V2.7.1
//
// IT DRAWS, IT DOES NOT DECIDE
// - Every position comes from the layout Ruby resolved
//   (Na__AssemblyRunSystem::Na__LayoutResolver, sent by the dialog router).
//   There is no layout rule in this file to drift from the Ruby: change a
//   rule there and the drawing follows.
//
// THE LAYOUT (millimetres; see the resolver's header)
//   legs[].items[] : kind Span | Column | Post, s0 / s1 along the leg,
//                    y0 / y1 to the leg's LEFT, z0 / z1 above the base
//   corners[]      : outline (plan polygon), kind, library
//   Plan y is drawn upside down (SVG y runs down), so left of a leg heading
//   +x is up the page, as on a drawing.
//
// LABELS AND DIMENSIONS KEEP THEIR SIZE ON SCREEN (V2.7.1)
// - A run is 2 m or 30 m long. Text sized as a share of the drawing was too
//   small to read on a long run (Adam, 16-Nov-2026: "the preview is hard to
//   see"). Every label, tick and dimension offset is therefore given in
//   SCREEN PIXELS (NA_PX) and multiplied by options.unit, the millimetres
//   one screen pixel covers at the present zoom. The preview panel draws
//   again whenever the zoom changes, so text stays one size while the
//   drawing grows, and a value that had no room appears as you zoom in.
// - na_plan_fit / na_elevation_fit give the view box that fits the drawing
//   and its dimension rows into a pane of a given pixel size.
//
// THE RUN'S ONE CILL (V2.7.3)
// - layout.cills: each stretch the run's one cill runs along. In plan its
//   outline (Ruby's, mitred round every corner) is drawn under the frames,
//   so the strip proud of the framework face shows it wrapping the corners.
//   In elevation it is a strip of the cill's height along each stretch.
//
// THE RUN'S ONE WORKTOP (V2.7.4, Cabinets)
// - layout.worktops: each stretch one worktop runs along. Ruby sizes it for
//   the preview from the first unit type's product start (outline,
//   preview_front, preview_z0 / preview_z1); the build uses the units' own
//   settings. In plan the outline is drawn under the units, so its front
//   overhang and its run over gaps show; in elevation a strip at its height.
//
// WHICH WAY THE RUN FACES (V2.7.2)
// - In plan each span carries a small arrowhead off its outer face, pointing
//   to the side it is seen from. The preview panel says what they mean in the
//   plan's own label ("Plan · ▲ outside", or "▲ room side" for cabinets).
//
// WHAT CAN BE CLICKED
// - A span: class na-run-span with data-na-leg / data-na-span / data-na-type
//   (the tab selects on click and opens the panel menu on right-click).
// - A dimension value in <g class="na-dim-edit">: the shared viewport
//   controls open a text box over it (as in the window preview). Kinds:
//     leg    index = leg            the leg's length
//     type   index = type order     that panel type's set width
//     height index = 0              the run's height (Frames)
//     sill   index = type order     that panel type's sill height
//     joint  index = 0              the width between spans
//
// NAMING CONVENTION:
// - All custom identifiers use Na__ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Drawer = {};

    // -----------------------------------------------------------------------
    // REGION | Colours and sizes
    // -----------------------------------------------------------------------

    // One tint per panel type, in the order the types are listed, so every
    // span of a type reads alike in both drawings.
    var NA_TYPE_TINTS      = ['#cfe3f7', '#d8efd2', '#fbe3c2', '#e6d9f3', '#f7d5d9', '#cdeeee', '#eee9c4', '#dcdfe6'];
    var NA_TYPE_INKS       = ['#245fa8', '#2b7535', '#9c5d00', '#6a4696', '#a23645', '#1f7d7d', '#7d7420', '#4a5563'];
    var NA_COLOUR_INFILL   = '#c9ced4';
    var NA_COLOUR_LIBRARY  = '#cbbd9f';
    var NA_COLOUR_POST     = '#5d6670';
    var NA_COLOUR_CORNER   = '#aab2bb';
    var NA_COLOUR_CILL     = '#e6d3b3';                                         // <-- The window tab's Sapele cill, lightened for a drawing
    var NA_COLOUR_CILL_INK = '#9c7d55';
    var NA_COLOUR_WORKTOP  = '#dcd6cc';                                         // <-- A worktop, warm grey under the units (V2.7.4)
    var NA_COLOUR_WORKTOP_INK = '#7a7062';
    var NA_COLOUR_LINE     = '#3a4450';
    var NA_COLOUR_PATH     = '#3a7fd5';
    var NA_COLOUR_MUTE     = '#687380';
    var NA_DIM_STROKE      = '#606060';                                         // <-- The window preview's dimension colours
    var NA_DIM_WITNESS     = '#a8a8a8';
    var NA_LIBRARY_PROUD   = 88.5;                                              // <-- How far a library column stands proud of the framework face
    var NA_LIBRARY_SHY     = 6.5;                                               // <-- Its body is this much narrower than its backing, each side
    var NA_CABINET_HEIGHT  = 870;                                               // <-- Drawn height of a cabinet span when Ruby sends none
    var NA_LEG_GAP_SHARE   = 0.035;                                             // <-- Gap between unfolded legs, as a share of the whole run

    // Sizes on screen, in pixels. Multiplied by the unit (mm per pixel) when drawn.
    var NA_PX = {
        DIM_TEXT     : 11,                                                      // <-- A dimension value
        NOTE_TEXT    : 10.5,                                                    // <-- "Leg 1"
        TYPE_MIN     : 9,                                                       // <-- A panel type's letter, smallest and largest
        TYPE_MAX     : 26,
        ROW_1        : 18,                                                      // <-- First dimension row out from the drawing
        ROW_2        : 42,                                                      // <-- Second row (a leg's overall length)
        TEXT_OFF     : 9,                                                       // <-- A value's centre beyond its dimension line
        TICK         : 4,                                                       // <-- Half a tick
        WITNESS_GAP  : 4,
        WITNESS_OVER : 5,
        DOT          : 3,                                                       // <-- A path corner
        TYPE_OFF     : 12,                                                      // <-- A type letter beside a band too thin to hold it
        FACE_GAP     : 3,                                                       // <-- A facing arrowhead: clear of the span's outer face,
        FACE_LONG    : 7,                                                       //     how far it points,
        FACE_HALF    : 4,                                                       //     half its base,
        FACE_ROOM    : 26,                                                      //     and the narrowest span that carries one
        NOTE_OFF     : 30,                                                      // <-- A leg's name beyond its spans
        CHAR         : 0.6,                                                     // <-- Rough advance of one character, in ems
        SLACK        : 6                                                        // <-- Room a value needs beyond its own width
    };

    // Margins round the drawing when it is fitted to its pane (pixels).
    var NA_FIT_MARGINS = {
        plan      : { on: { l: 66, t: 80, r: 66, b: 66 }, off: { l: 46, t: 60, r: 46, b: 46 } },   // <-- More at the top: the plan's own label ("Plan · ▲ outside") sits there
        elevation : { on: { l: 54, t: 30, r: 16, b: 66 }, off: { l: 16, t: 30, r: 16, b: 16 } }
    };

    // -----------------------------------------------------------------------
    // REGION | Small helpers
    // -----------------------------------------------------------------------

    function na_num(value) { return Math.round(value * 100) / 100; }

    function na_escape(text) {
        return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    // A size as a dimension shows it: whole millimetres, or one decimal.
    function na_fmt(value) {
        var rounded = Math.round(Number(value) * 10) / 10;
        return isFinite(rounded) ? String(rounded) : '';
    }

    function na_type_order(layout, code) {
        return Object.keys(layout.types || {}).indexOf(code);
    }

    function na_type_index(layout, code) {
        var index = na_type_order(layout, code);
        return index < 0 ? 0 : index % NA_TYPE_TINTS.length;
    }

    function na_clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }

    // Does a text of this many characters fit a length, both in pixels?
    function na_fits(text, font_px, room_px) {
        return String(text).length * NA_PX.CHAR * font_px + NA_PX.SLACK <= room_px;
    }

    // HELPER FUNCTION | Claim Room for a Label; False When a Label Is There Already
    // ---------------------------------------------------------------
    // The plan's labels sit round a figure of any shape, so two can land on
    // one spot (a leg's name under its neighbour's dimension at an inside
    // corner). They are placed in order of importance and each claims the
    // box it covers; one that would overlap a claim is left out, and comes
    // back when a zoom gives it room.
    // @param taken [[x0, y0, x1, y1]] page millimetres, added to
    // @param angle degrees the text is turned through
    function na_claim(taken, x, y, text, size, angle) {
        var width  = (String(text).length * NA_PX.CHAR + 0.5) * size;
        var height = size * 1.2;
        var turn   = (angle || 0) * Math.PI / 180;
        var half_w = (Math.abs(Math.cos(turn)) * width + Math.abs(Math.sin(turn)) * height) / 2;
        var half_h = (Math.abs(Math.sin(turn)) * width + Math.abs(Math.cos(turn)) * height) / 2;
        var box    = [x - half_w, y - half_h, x + half_w, y + half_h];
        for (var index = 0; index < taken.length; index += 1) {
            var other = taken[index];
            if (box[0] < other[2] && box[2] > other[0] && box[1] < other[3] && box[3] > other[1]) return false;
        }
        taken.push(box);
        return true;
    }

    // HELPER FUNCTION | A Dimension's Text for the Room It Has
    // ---------------------------------------------------------------
    // To one decimal when that fits; to the whole millimetre when only that
    // does (zoom in and the decimal appears); null when neither does.
    function na_value_text(length, room_px) {
        var exact = na_fmt(length);
        if (na_fits(exact, NA_PX.DIM_TEXT, room_px)) return exact;
        var whole = String(Math.round(length));
        return (whole !== exact && na_fits(whole, NA_PX.DIM_TEXT, room_px)) ? whole : null;
    }

    // -----------------------------------------------------------------------
    // REGION | Plan geometry
    // -----------------------------------------------------------------------

    // HELPER FUNCTION | A Point on a Leg: s Along It, y to Its Left
    // ---------------------------------------------------------------
    function na_on_leg(leg, s, y) {
        return [leg.p0[0] + leg.dir[0] * s + leg.left[0] * y, leg.p0[1] + leg.dir[1] * s + leg.left[1] * y];
    }

    function na_leg_rect(leg, s0, s1, y0, y1) {
        return [na_on_leg(leg, s0, y0), na_on_leg(leg, s1, y0), na_on_leg(leg, s1, y1), na_on_leg(leg, s0, y1)];
    }

    // The band a span's element fills, across the leg.
    function na_span_band(settings) {
        return settings.frames ? [settings.post_inset, settings.post_inset + settings.post_depth] : [-settings.unit_depth, 0];
    }

    // HELPER FUNCTION | A Library Corner Column's Body, in Plan
    // ---------------------------------------------------------------
    // Its own X runs along the leg leaving the corner, its own Y back along
    // the leg arriving; the body wraps the corner, proud of both faces.
    function na_library_corner_body(corner) {
        var reach = corner.size - NA_LIBRARY_SHY;
        var own   = [[-NA_LIBRARY_PROUD, -NA_LIBRARY_PROUD], [reach, -NA_LIBRARY_PROUD], [reach, 0], [0, 0], [0, reach], [-NA_LIBRARY_PROUD, reach]];
        return own.map(function (pair) {
            return [corner.point[0] + corner.dir_out[0] * pair[0] - corner.dir_in[0] * pair[1],
                    corner.point[1] + corner.dir_out[1] * pair[0] - corner.dir_in[1] * pair[1]];
        });
    }

    // HELPER FUNCTION | A Cabinet Corner Unit's L-Shaped Footprint
    // ---------------------------------------------------------------
    function na_corner_unit_outline(corner, leg_in, settings) {
        var size  = corner.size;
        var depth = settings.unit_depth;
        var start = leg_in.length - size;
        var own   = [[0, 0], [size, 0], [size, -size], [size - depth, -size], [size - depth, -depth], [0, -depth]];
        return own.map(function (pair) { return na_on_leg(leg_in, start + pair[0], pair[1]); });
    }

    // -----------------------------------------------------------------------
    // REGION | SVG pieces
    // -----------------------------------------------------------------------

    // A shape's hover text, as a child <title> (empty when there is none).
    function na_title(text) {
        return text ? '<title>' + na_escape(text) + '</title>' : '';
    }

    // Plan points are flipped in y as they are written.
    function na_poly(points, attributes, flip, title) {
        var text = points.map(function (point) { return na_num(point[0]) + ',' + na_num(flip ? -point[1] : point[1]); }).join(' ');
        return '<polygon points="' + text + '" ' + attributes + '>' + na_title(title) + '</polygon>';
    }

    function na_rect(x, y, width, height, attributes, title) {
        return '<rect x="' + na_num(x) + '" y="' + na_num(y) + '" width="' + na_num(Math.max(width, 0.1)) + '" height="' + na_num(Math.max(height, 0.1)) + '" ' +
               attributes + '>' + na_title(title) + '</rect>';
    }

    function na_line(x1, y1, x2, y2, stroke, extra) {
        return '<line x1="' + na_num(x1) + '" y1="' + na_num(y1) + '" x2="' + na_num(x2) + '" y2="' + na_num(y2) + '" stroke="' + stroke +
               '" stroke-width="1" vector-effect="non-scaling-stroke"' + (extra || '') + '/>';
    }

    // HELPER FUNCTION | A Label That Takes No Clicks
    // ---------------------------------------------------------------
    // The colour is an inline style: the preview stylesheet sets a fill on
    // every <text>, which a plain fill attribute does not override.
    // @param angle degrees, turning the label about its own centre (0 = level)
    function na_label(x, y, text, size, colour, weight, angle) {
        var turn = angle ? ' transform="rotate(' + na_num(angle) + ' ' + na_num(x) + ' ' + na_num(y) + ')"' : '';
        return '<text x="' + na_num(x) + '" y="' + na_num(y) + '" font-size="' + na_num(size) + '" font-weight="' + (weight || 600) +
               '" text-anchor="middle" dominant-baseline="central"' + turn + ' style="fill:' + colour + ';pointer-events:none">' + na_escape(text) + '</text>';
    }

    // HELPER FUNCTION | One Dimension Value, Optionally Click to Edit
    // ---------------------------------------------------------------
    // The window preview's pattern: an editable value sits in
    // <g class="na-dim-edit"> with what it measures (kind, index) and its
    // exact number, behind a clear hit rectangle the size of the text.
    // @param edit { kind, index, value, label } or null
    function na_value(x, y, text, size, angle, edit) {
        var turn  = angle ? ' transform="rotate(' + na_num(angle) + ' ' + na_num(x) + ' ' + na_num(y) + ')"' : '';
        var label = '<text class="na-run-dim" x="' + na_num(x) + '" y="' + na_num(y) + '" font-size="' + na_num(size) +
                    '" font-weight="600" text-anchor="middle" dominant-baseline="central">' + na_escape(text) + '</text>';
        if (!edit) return '<g' + turn + ' style="pointer-events:none">' + label + '</g>';

        var width  = (String(text).length * NA_PX.CHAR + 1) * size;
        var height = size * 1.6;
        return '<g class="na-dim-edit" data-dim-kind="' + edit.kind + '" data-dim-index="' + edit.index + '" data-dim-value="' + edit.value +
               '" data-dim-label="' + na_escape(edit.label) + '"' + turn + '>' +
               '<title>' + na_escape(edit.label) + ': click to type a new size</title>' +
               '<rect class="na-dim-hit" x="' + na_num(x - width / 2) + '" y="' + na_num(y - height / 2) + '" width="' + na_num(width) + '" height="' + na_num(height) +
               '" fill="rgba(0, 0, 0, 0.001)" stroke="none"/>' + label + '</g>';
    }

    function na_centre(points) {
        var x = 0, y = 0;
        points.forEach(function (point) { x += point[0]; y += point[1]; });
        return [x / points.length, y / points.length];
    }

    // "click-target" in the class keeps a double click on a span from
    // fitting the view (the viewport controls read it as not empty canvas).
    function na_span_attributes(item, tint, stroke, selected) {
        return 'class="na-run-span na-run-click-target' + (selected ? ' na-run-span--on' : '') + '" data-na-leg="' + item.leg + '" data-na-span="' + item.span +
               '" data-na-type="' + na_escape(item.type) + '" fill="' + tint + '" stroke="' + stroke + '" stroke-width="' + (selected ? 3 : 1.5) +
               '" vector-effect="non-scaling-stroke"';
    }

    // HELPER FUNCTION | What a Panel Type Is, in Words ("Sliding Doors")
    // ---------------------------------------------------------------
    // @param product the tab's function from a product key to its name, or null
    function na_product_name(layout, code, product) {
        var key = ((layout.types || {})[code] || {}).product;
        if (!key) return '';
        return typeof product === 'function' ? String(product(key) || key) : String(key);
    }

    function na_span_title(item, layout, product) {
        var name = na_product_name(layout, item.type, product);
        return 'Panel type ' + item.type + (name ? ' · ' + name : '') + ' · ' + item.key + ' · ' + na_fmt(item.width) + 'mm (right-click for its commands)';
    }

    function na_item_fill(item) {
        if (item.kind === 'Post') return NA_COLOUR_POST;
        if (item.role === 'Vale260' || item.role === 'Vale290') return NA_COLOUR_LIBRARY;
        return NA_COLOUR_INFILL;
    }

    function na_is_selected(item, selection) {
        return !!selection && selection.leg === item.leg && selection.span === item.span;
    }

    // -----------------------------------------------------------------------
    // REGION | A leg cut into its dimension segments
    // -----------------------------------------------------------------------

    // FUNCTION | Every Stretch of a Leg, End to End
    // ---------------------------------------------------------------
    // Cut at each item's two ends and at what each corner takes from the
    // leg. A stretch that is exactly one item carries it.
    // @return [{ s0, s1, item }] in order along the leg
    function na_leg_segments(leg) {
        var cuts = [0, leg.length];
        if (leg.setback_start > 0.5) cuts.push(leg.setback_start);
        if (leg.setback_end > 0.5)   cuts.push(leg.length - leg.setback_end);
        (leg.items || []).forEach(function (item) { cuts.push(item.s0, item.s1); });
        cuts = cuts.map(function (value) { return na_clamp(value, 0, leg.length); }).sort(function (a, b) { return a - b; });

        var segments = [];
        for (var index = 0; index < cuts.length - 1; index += 1) {
            var s0 = cuts[index], s1 = cuts[index + 1];
            if (s1 - s0 < 0.5) continue;
            var owner = (leg.items || []).filter(function (item) { return Math.abs(item.s0 - s0) < 0.6 && Math.abs(item.s1 - s1) < 0.6; })[0] || null;
            segments.push({ s0: s0, s1: s1, item: owner });
        }
        return segments;
    }

    // HELPER FUNCTION | What Typing Over a Segment's Value Would Set
    // ---------------------------------------------------------------
    // A span sets its panel type's width (not a type a fill made: its
    // width follows the fill). A block or gap the run stands between spans
    // sets the run's Width Between.
    function na_segment_edit(layout, segment, editable) {
        var item = segment.item;
        if (!editable || !item) return null;
        if (item.kind === 'Span') {
            var type = (layout.types || {})[item.type] || {};
            if (type.auto) return null;
            return { kind: 'type', index: na_type_order(layout, item.type), value: item.width, label: 'Panel type ' + item.type + ' width' };
        }
        if (item.kind === 'Column' && item.origin === 'Joint' && (item.role === 'Infill' || item.role === 'Gap')) {
            return { kind: 'joint', index: 0, value: item.width, label: 'Width between spans' };
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // REGION | Plan
    // -----------------------------------------------------------------------

    // SUB FUNCTION | The Plan's Shapes and How Far They Reach
    // ---------------------------------------------------------------
    // Nothing here depends on the zoom.
    // @return { shapes, spans: [{ item, leg }], extents, reach } or null
    function na_plan_geometry(layout, selection, product) {
        var settings = layout.settings || {};
        var legs     = layout.legs || [];
        var band     = na_span_band(settings);
        var shapes   = [];
        var spans    = [];
        var reach    = { left: Math.max(0, band[1]), right: Math.max(0, -band[0]) };   // <-- How far the shapes stand off the path, each side
        var xs = [], ys = [];
        function na_track(points) { points.forEach(function (point) { xs.push(point[0]); ys.push(-point[1]); }); }

        // The run's one cill, under the frames (V2.7.3).
        (layout.cills || []).forEach(function (stretch) {
            var outline = stretch.outline || {};
            if (!outline.outer || outline.outer.length < 3) return;
            var loops = [outline.outer].concat(outline.inner ? [outline.inner] : []);
            var path  = loops.map(function (loop) {
                return 'M' + loop.map(function (point) { return na_num(point[0]) + ',' + na_num(-point[1]); }).join(' L') + ' Z';
            }).join(' ');
            shapes.push('<path class="na-run-cill" d="' + path + '" fill="' + NA_COLOUR_CILL + '" fill-rule="evenodd" stroke="' + NA_COLOUR_CILL_INK +
                        '" stroke-width="1" vector-effect="non-scaling-stroke" style="pointer-events:none">' +
                        na_title('One cill, ' + (stretch.spans || []).length + ' spans') + '</path>');
            na_track(outline.outer);
            reach.right = Math.max(reach.right, settings.cill_projection || 0);
        });

        // The run's one worktop, under the units (V2.7.4): its front overhang
        // and its run over gaps show past them.
        (layout.worktops || []).forEach(function (stretch) {
            var outline = stretch.outline || {};
            if (!outline.outer || outline.outer.length < 3) return;
            var loops = [outline.outer].concat(outline.inner ? [outline.inner] : []);
            var path  = loops.map(function (loop) {
                return 'M' + loop.map(function (point) { return na_num(point[0]) + ',' + na_num(-point[1]); }).join(' L') + ' Z';
            }).join(' ');
            shapes.push('<path class="na-run-worktop" d="' + path + '" fill="' + NA_COLOUR_WORKTOP + '" fill-rule="evenodd" stroke="' + NA_COLOUR_WORKTOP_INK +
                        '" stroke-width="1" vector-effect="non-scaling-stroke" style="pointer-events:none">' +
                        na_title('One worktop, ' + (stretch.spans || []).length + ' units') + '</path>');
            na_track(outline.outer);
            reach.right = Math.max(reach.right, stretch.preview_front || 0);
            reach.left  = Math.max(reach.left, settings.worktop_back || 0);
        });

        (layout.corners || []).forEach(function (corner) {
            var leg_in = legs[corner.leg_in];
            if (corner.kind === 'CornerUnit' && leg_in) {
                var unit = na_corner_unit_outline(corner, leg_in, settings);
                shapes.push(na_poly(unit, 'fill="#e9dcc3" stroke="' + NA_COLOUR_LINE + '" stroke-width="1.5" vector-effect="non-scaling-stroke"', true, 'Corner unit'));
                na_track(unit);
            }
            if (!corner.outline) return;
            shapes.push(na_poly(corner.outline, 'fill="' + NA_COLOUR_CORNER + '" stroke="' + NA_COLOUR_LINE + '" stroke-width="1" vector-effect="non-scaling-stroke"', true,
                                String(corner.kind || 'Corner')));
            na_track(corner.outline);
            if (corner.library) {
                var body = na_library_corner_body(corner);
                shapes.push(na_poly(body, 'fill="' + NA_COLOUR_LIBRARY + '" stroke="' + NA_COLOUR_LINE + '" stroke-width="1.5" vector-effect="non-scaling-stroke"', true));
                na_track(body);
                reach.right = Math.max(reach.right, NA_LIBRARY_PROUD);
            }
        });

        legs.forEach(function (leg) {
            (leg.items || []).forEach(function (item) {
                if (item.kind === 'Span') {
                    var rect  = na_leg_rect(leg, item.s0, item.s1, band[0], band[1]);
                    var index = na_type_index(layout, item.type);
                    var on    = na_is_selected(item, selection);
                    shapes.push(na_poly(rect, na_span_attributes(item, NA_TYPE_TINTS[index], on ? NA_COLOUR_PATH : NA_TYPE_INKS[index], on), true, na_span_title(item, layout, product)));
                    spans.push({ item: item, leg: leg });
                    na_track(rect);
                    return;
                }
                if (item.role === 'Gap') {
                    var gap = na_leg_rect(leg, item.s0, item.s1, band[0], band[1]);
                    shapes.push(na_poly(gap, 'fill="none" stroke="' + NA_COLOUR_MUTE + '" stroke-width="1" stroke-dasharray="6 4" vector-effect="non-scaling-stroke"', true,
                                        'Gap ' + na_fmt(item.width) + 'mm'));
                    na_track(gap);
                    return;
                }
                if (item.y0 === undefined || item.y0 === null) return;
                var block = na_leg_rect(leg, item.s0, item.s1, item.y0, item.y1);
                shapes.push(na_poly(block, 'fill="' + (item.kind === 'Post' ? NA_COLOUR_POST : NA_COLOUR_INFILL) + '" stroke="' + NA_COLOUR_LINE +
                                    '" stroke-width="1" vector-effect="non-scaling-stroke"', true, String(item.role || item.kind) + ' ' + na_fmt(item.width) + 'mm'));
                na_track(block);
                reach.left  = Math.max(reach.left, item.y1);
                reach.right = Math.max(reach.right, -item.y0);
                if (item.role === 'Vale260' || item.role === 'Vale290') {
                    var proud = na_leg_rect(leg, item.s0 + NA_LIBRARY_SHY, item.s1 - NA_LIBRARY_SHY, -NA_LIBRARY_PROUD, 0);
                    shapes.push(na_poly(proud, 'fill="' + NA_COLOUR_LIBRARY + '" stroke="' + NA_COLOUR_LINE + '" stroke-width="1.5" vector-effect="non-scaling-stroke"', true));
                    na_track(proud);
                    reach.right = Math.max(reach.right, NA_LIBRARY_PROUD);
                }
            });
        });

        // The worktop's cut-outs (V2.7.5): drawn over the units, dashed, so a
        // hob or a sink shows where the build cuts it.
        (layout.worktop_cutouts || []).forEach(function (cutout) {
            var outline = cutout.outline || [];
            if (outline.length < 3) return;
            shapes.push('<path class="na-run-cutout" d="M' + outline.map(function (point) { return na_num(point[0]) + ',' + na_num(-point[1]); }).join(' L') +
                        ' Z" fill="#ffffff" fill-opacity="0.6" stroke="' + NA_COLOUR_WORKTOP_INK + '" stroke-width="1.2" stroke-dasharray="5 3" vector-effect="non-scaling-stroke" style="pointer-events:none">' +
                        na_title(String(cutout.label || 'Cut-out')) + '</path>');
        });

        (layout.points || []).forEach(function (point) { xs.push(point[0]); ys.push(-point[1]); });
        if (!xs.length) return null;
        return {
            shapes  : shapes,
            spans   : spans,
            reach   : reach,
            extents : { x0: Math.min.apply(null, xs), y0: Math.min.apply(null, ys), x1: Math.max.apply(null, xs), y1: Math.max.apply(null, ys) }
        };
    }

    // HELPER FUNCTION | A Leg's Direction on the Page, and a Readable Text Angle
    // ---------------------------------------------------------------
    // The page's y runs down, so the leg's own y is turned over. Text runs
    // along the leg, never upside down; on a leg straight up or down the
    // page it reads from the bottom, as on a drawing.
    function na_leg_frame(leg) {
        var angle = Math.atan2(-leg.dir[1], leg.dir[0]) * 180 / Math.PI;
        if (angle > 89.99) angle -= 180;
        else if (angle < -90.01) angle += 180;
        return { text_angle: Math.abs(angle) < 0.01 ? 0 : angle };
    }

    // A point s along a leg and y to its left, as page coordinates.
    function na_page(leg, s, y) {
        var point = na_on_leg(leg, s, y);
        return [point[0], -point[1]];
    }

    // SUB FUNCTION | One Dimension Row Along a Leg, in Plan
    // ---------------------------------------------------------------
    // @param offset   millimetres to the leg's left (negative = right)
    // @param segments [{ s0, s1, edit }] each with its own value
    // @param away     +1 or -1: which way is further from the drawing
    // @param taken    the plan's label ledger (see na_claim)
    function na_plan_dimension_row(leg, offset, segments, unit, away, frame, taken) {
        var tick  = NA_PX.TICK * unit;
        var size  = NA_PX.DIM_TEXT * unit;
        var first = segments[0].s0, last = segments[segments.length - 1].s1;
        var a = na_page(leg, first, offset), b = na_page(leg, last, offset);
        var svg = na_line(a[0], a[1], b[0], b[1], NA_DIM_STROKE);

        var stations = [first].concat(segments.map(function (segment) { return segment.s1; }));
        stations.forEach(function (station) {
            var low = na_page(leg, station, offset - tick), high = na_page(leg, station, offset + tick);
            svg += na_line(low[0], low[1], high[0], high[1], NA_DIM_STROKE);
        });
        segments.forEach(function (segment) {
            var text = na_value_text(segment.s1 - segment.s0, (segment.s1 - segment.s0) / unit);
            if (text === null) return;
            var at = na_page(leg, (segment.s0 + segment.s1) / 2, offset + away * NA_PX.TEXT_OFF * unit);
            if (!na_claim(taken, at[0], at[1], text, size, frame.text_angle)) return;
            svg += na_value(at[0], at[1], text, size, frame.text_angle, segment.edit);
        });
        return svg;
    }

    // FUNCTION | The Plan Drawing
    // ---------------------------------------------------------------
    // @param layout  the resolved layout (Ruby's report)
    // @param options { unit (mm per screen pixel), selection ({ leg, span } or
    //                null), dimensions, editable, closed, product (a function
    //                from a product key to its name, for labels; optional) }
    // @return { markup, extents } (extents null when there is nothing to draw)
    Drawer.na_plan = function (layout, options) {
        var opts     = options || {};
        var unit     = opts.unit > 0 ? opts.unit : 1;
        var geometry = na_plan_geometry(layout, opts.selection, opts.product);
        if (!geometry) return { markup: '', extents: null };

        var settings = layout.settings || {};
        var legs     = layout.legs || [];
        var band     = na_span_band(settings);
        var side     = (band[0] + band[1]) / 2 >= 0 ? 1 : -1;                   // <-- The side of the path the elements stand on (+1 = left)
        var band_px  = (band[1] - band[0]) / unit;
        var reach    = geometry.reach;
        var middle   = na_centre(layout.points || [[0, 0]]);
        var marks    = [];

        // The path, its corners.
        var path = (layout.points || []).map(function (point) { return na_num(point[0]) + ',' + na_num(-point[1]); }).join(' ');
        marks.push('<' + (layout.closed ? 'polygon' : 'polyline') + ' points="' + path + '" fill="none" stroke="' + NA_COLOUR_PATH +
                   '" stroke-width="2" stroke-dasharray="10 5" vector-effect="non-scaling-stroke" style="pointer-events:none"/>');
        (layout.points || []).forEach(function (point) {
            marks.push('<circle cx="' + na_num(point[0]) + '" cy="' + na_num(-point[1]) + '" r="' + na_num(NA_PX.DOT * unit) + '" fill="' + NA_COLOUR_PATH + '" style="pointer-events:none"/>');
        });

        // Which side of each leg its dimensions go: the side facing away
        // from the middle of the run, so the strings go round the outside of
        // the figure and do not cross at an inside corner. A straight run has
        // no middle to face away from: away from its elements. The leg's
        // name and the type letters take the other side.
        var dim_side = legs.map(function (leg) {
            var at   = na_on_leg(leg, leg.length / 2, 0);
            var lean = (at[0] - middle[0]) * leg.left[0] + (at[1] - middle[1]) * leg.left[1];
            return Math.abs(lean) < 1 ? -side : (lean > 0 ? 1 : -1);
        });
        function na_beyond(towards, pixels) {                                   // <-- Millimetres to a leg's left, clear of the shapes on that side
            return towards * ((towards > 0 ? reach.left : reach.right) + pixels * unit);
        }

        // Labels are placed in order of importance, each claiming its room
        // (na_claim): a leg's whole length, the panel type letters, each
        // stretch's own length, then the leg's name.
        var taken = [];
        var rows  = legs.map(function (leg) {
            var segments = na_leg_segments(leg).map(function (segment) {
                return { s0: segment.s0, s1: segment.s1, edit: na_segment_edit(layout, segment, opts.editable) };
            });
            var whole = { s0: 0, s1: leg.length,
                          edit: (opts.editable && !opts.closed) ? { kind: 'leg', index: leg.index, value: leg.length, label: 'Leg ' + (leg.index + 1) + ' length' } : null };
            var chain = segments.length > 1;
            return { leg: leg, away: dim_side[leg.index], frame: na_leg_frame(leg), chain: chain ? segments : null, whole: [whole],
                     whole_px: chain ? NA_PX.ROW_2 : NA_PX.ROW_1 };
        });

        // 1. Each leg's whole length (the outer dimension row).
        if (opts.dimensions) {
            rows.forEach(function (row) {
                var out = na_beyond(row.away, row.whole_px);
                marks.push(na_plan_dimension_row(row.leg, out, row.whole, unit, row.away, row.frame, taken));
                [0, row.leg.length].forEach(function (station) {                // <-- Witness lines at the leg's two ends
                    var from = na_page(row.leg, station, na_beyond(row.away, NA_PX.WITNESS_GAP));
                    var to   = na_page(row.leg, station, out + row.away * NA_PX.WITNESS_OVER * unit);
                    marks.push(na_line(from[0], from[1], to[0], to[1], NA_DIM_WITNESS, ' style="pointer-events:none"'));
                });
            });
        }

        // 2. Each span's panel type: inside its band when the band is thick
        // enough on screen, else just beyond the shapes.
        geometry.spans.forEach(function (span) {
            var item = span.item;
            if (item.width / unit < 14) return;
            var index  = na_type_index(layout, item.type);
            var inside = band_px >= 16;
            var size   = inside ? na_clamp(band_px * 0.6, NA_PX.TYPE_MIN, NA_PX.TYPE_MAX) : NA_PX.DIM_TEXT + 1;
            size = Math.min(size, (item.width / unit) * 0.7);
            var y  = inside ? (band[0] + band[1]) / 2 : na_beyond(-dim_side[item.leg], NA_PX.TYPE_OFF);
            var at = na_page(span.leg, (item.s0 + item.s1) / 2, y);
            if (!na_claim(taken, at[0], at[1], item.type, size * unit, 0)) return;
            marks.push(na_label(at[0], at[1], item.type, size * unit, NA_TYPE_INKS[index], 700));
        });

        // Which way each span faces: an arrowhead off its outer face, pointing
        // to the side it is seen from (the outside of a framework, the room
        // for cabinets). The elements are seen from the path's RIGHT, so the
        // arrowheads are what Flip Inside Out turns round (V2.7.2): without
        // them a thin framework looks the same in plan either way. Set a
        // quarter along the span, clear of its type letter, and short enough
        // to stay inside the gap before the first dimension row.
        geometry.spans.forEach(function (span) {
            var item = span.item;
            if (item.width / unit < NA_PX.FACE_ROOM) return;
            var along = item.s0 + item.width * 0.25;
            var near  = band[0] - NA_PX.FACE_GAP * unit;                        // <-- band[0]: the band's edge on the path's right
            var shape = [na_page(span.leg, along - NA_PX.FACE_HALF * unit, near), na_page(span.leg, along + NA_PX.FACE_HALF * unit, near),
                         na_page(span.leg, along, near - NA_PX.FACE_LONG * unit)];
            marks.push('<polygon class="na-run-facing" points="' + shape.map(function (point) { return na_num(point[0]) + ',' + na_num(point[1]); }).join(' ') +
                       '" fill="' + NA_COLOUR_PATH + '" style="pointer-events:none"/>');
        });

        // 3. Each stretch of a leg (the inner dimension row).
        if (opts.dimensions) {
            rows.forEach(function (row) {
                if (row.chain) marks.push(na_plan_dimension_row(row.leg, na_beyond(row.away, NA_PX.ROW_1), row.chain, unit, row.away, row.frame, taken));
            });
        }

        // 4. Each leg's name, beyond the type letters. With the dimensions
        // off it carries the leg's length too.
        rows.forEach(function (row) {
            var leg  = row.leg;
            var text = 'Leg ' + (leg.index + 1) + (opts.dimensions ? '' : ' · ' + Math.round(leg.length));
            if (!na_fits(text, NA_PX.NOTE_TEXT, leg.length / unit)) return;
            var at = na_page(leg, leg.length / 2, na_beyond(-row.away, NA_PX.NOTE_OFF));
            if (!na_claim(taken, at[0], at[1], text, NA_PX.NOTE_TEXT * unit, row.frame.text_angle)) return;
            marks.push(na_label(at[0], at[1], text, NA_PX.NOTE_TEXT * unit, NA_COLOUR_MUTE, 500, row.frame.text_angle));
        });

        return { markup: geometry.shapes.join('') + marks.join(''), extents: geometry.extents };
    };

    // -----------------------------------------------------------------------
    // REGION | Elevation (every leg unfolded into one line)
    // -----------------------------------------------------------------------

    // HELPER FUNCTION | How High a Span Is Drawn
    // ---------------------------------------------------------------
    // Frames carry z0 / z1. A cabinet's height is its own product's: Ruby
    // sends preview_z0 / preview_z1 on the type when it knows them.
    function na_span_heights(item, layout) {
        if (item.z1 !== undefined && item.z1 !== null) return [item.z0 || 0, item.z1];
        var type = (layout.types || {})[item.type] || {};
        if (type.preview_z1) return [type.preview_z0 || 0, type.preview_z1];
        return [0, NA_CABINET_HEIGHT];
    }

    // SUB FUNCTION | The Elevation's Shapes and How Far They Reach
    // ---------------------------------------------------------------
    // Nothing here depends on the zoom.
    // @return { shapes, spans, legs: [{ leg, offset }], width, height, extents } or null
    function na_elevation_geometry(layout, selection, product) {
        var settings = layout.settings || {};
        var legs     = layout.legs || [];
        var total    = legs.reduce(function (sum, leg) { return sum + leg.length; }, 0);
        if (!legs.length || total <= 0) return null;

        var gap    = legs.length > 1 ? total * NA_LEG_GAP_SHARE : 0;
        var top    = settings.frames ? settings.height : 0;
        var shapes = [];
        var spans  = [];
        var placed = [];
        var offset = 0;

        legs.forEach(function (leg) {                                           // <-- First the tallest thing, so gaps and corners can match it
            (leg.items || []).forEach(function (item) {
                if (item.kind === 'Span') top = Math.max(top, na_span_heights(item, layout)[1]);
                else if (item.z1 !== undefined && item.z1 !== null) top = Math.max(top, item.z1);
            });
        });
        (layout.worktops || []).forEach(function (stretch) { top = Math.max(top, Number(stretch.preview_z1) || 0); });   // <-- V2.7.4: a worktop stands above the units
        var height = top || NA_CABINET_HEIGHT;

        legs.forEach(function (leg) {
            (leg.items || []).forEach(function (item) {
                var x = offset + item.s0;
                if (item.kind === 'Span') {
                    var heights = na_span_heights(item, layout);
                    var index   = na_type_index(layout, item.type);
                    var on      = na_is_selected(item, selection);
                    shapes.push(na_rect(x, -heights[1], item.width, heights[1] - heights[0],
                        na_span_attributes(item, NA_TYPE_TINTS[index], on ? NA_COLOUR_PATH : NA_TYPE_INKS[index], on), na_span_title(item, layout, product)));
                    spans.push({ item: item, x: x, heights: heights });
                    return;
                }
                if (item.role === 'Gap') {
                    shapes.push(na_rect(x, -height, item.width, height,
                        'fill="none" stroke="' + NA_COLOUR_MUTE + '" stroke-width="1" stroke-dasharray="6 4" vector-effect="non-scaling-stroke"', 'Gap ' + na_fmt(item.width) + 'mm'));
                    return;
                }
                if (item.z1 === undefined || item.z1 === null) return;
                shapes.push(na_rect(x, -item.z1, item.width, item.z1 - (item.z0 || 0),
                    'fill="' + na_item_fill(item) + '" stroke="' + NA_COLOUR_LINE + '" stroke-width="1" vector-effect="non-scaling-stroke"',
                    String(item.role || item.kind) + ' ' + na_fmt(item.width) + 'mm'));
            });

            // What each corner takes from the leg's two ends.
            [[0, leg.setback_start, leg.corner_start], [leg.length - leg.setback_end, leg.setback_end, leg.corner_end]].forEach(function (zone) {
                if (!(zone[1] > 0.5)) return;
                var corner = (layout.corners || [])[zone[2]] || {};
                shapes.push(na_rect(offset + zone[0], -height, zone[1], height,
                    'fill="' + (corner.library ? NA_COLOUR_LIBRARY : NA_COLOUR_CORNER) + '" fill-opacity="0.55" stroke="' + NA_COLOUR_LINE + '" stroke-width="1" vector-effect="non-scaling-stroke"',
                    String(corner.kind || 'Corner').replace('CornerUnit', 'Corner unit') + ' ' + na_fmt(zone[1]) + 'mm'));
            });

            placed.push({ leg: leg, offset: offset });
            offset += leg.length + gap;
        });

        // The run's one cill (V2.7.3): a strip of its height along each
        // stretch, over the feet of the spans and posts that stand on it.
        var cill_height = settings.join_cills ? Number(settings.cill_height) || 0 : 0;
        if (cill_height > 0) {
            (layout.cills || []).forEach(function (stretch) {
                (stretch.ranges || []).forEach(function (range) {
                    var entry = placed.filter(function (item) { return item.leg.index === range.leg; })[0];
                    if (!entry || !(range.s1 - range.s0 > 0.5)) return;
                    shapes.push(na_rect(entry.offset + range.s0, -cill_height, range.s1 - range.s0, cill_height,
                        'class="na-run-cill" fill="' + NA_COLOUR_CILL + '" stroke="' + NA_COLOUR_CILL_INK + '" stroke-width="1" vector-effect="non-scaling-stroke" style="pointer-events:none"',
                        'One cill, ' + na_fmt(cill_height) + 'mm'));
                });
            });
        }

        // The run's one worktop (V2.7.4): a strip at its height along each
        // stretch, over the units' tops and across the gaps.
        (layout.worktops || []).forEach(function (stretch) {
            var z0 = Number(stretch.preview_z0);
            var z1 = Number(stretch.preview_z1);
            if (!(z1 > z0)) return;
            (stretch.ranges || []).forEach(function (range) {
                var entry = placed.filter(function (item) { return item.leg.index === range.leg; })[0];
                if (!entry || !(range.s1 - range.s0 > 0.5)) return;
                shapes.push(na_rect(entry.offset + range.s0, -z1, range.s1 - range.s0, z1 - z0,
                    'class="na-run-worktop" fill="' + NA_COLOUR_WORKTOP + '" stroke="' + NA_COLOUR_WORKTOP_INK + '" stroke-width="1" vector-effect="non-scaling-stroke" style="pointer-events:none"',
                    'One worktop, ' + na_fmt(z1 - z0) + 'mm'));
            });
        });

        var width = offset - gap;
        return { shapes: shapes, spans: spans, legs: placed, width: width, height: height,
                 extents: { x0: 0, y0: -height, x1: width, y1: 0 } };
    }

    // FUNCTION | The Elevation Drawing
    // ---------------------------------------------------------------
    // @param options as na_plan
    // @return { markup, extents }
    Drawer.na_elevation = function (layout, options) {
        var opts     = options || {};
        var unit     = opts.unit > 0 ? opts.unit : 1;
        var geometry = na_elevation_geometry(layout, opts.selection, opts.product);
        if (!geometry) return { markup: '', extents: null };

        var settings = layout.settings || {};
        var size     = NA_PX.DIM_TEXT * unit;
        var tick     = NA_PX.TICK * unit;
        var marks    = [];

        // The ground line, each leg's name above it.
        marks.push('<line x1="' + na_num(-8 * unit) + '" y1="0" x2="' + na_num(geometry.width + 8 * unit) + '" y2="0" stroke="' + NA_COLOUR_LINE +
                   '" stroke-width="1.5" vector-effect="non-scaling-stroke" style="pointer-events:none"/>');
        geometry.legs.forEach(function (entry) {
            var leg  = entry.leg;
            var text = 'Leg ' + (leg.index + 1) + (opts.dimensions ? '' : ' · ' + Math.round(leg.length));
            if (!na_fits(text, NA_PX.NOTE_TEXT, leg.length / unit)) return;
            marks.push(na_label(entry.offset + leg.length / 2, -geometry.height - 14 * unit, text, NA_PX.NOTE_TEXT * unit, NA_COLOUR_MUTE, 600));
        });

        // Each span's panel type, as large as the span allows; under it, when
        // the span has the room, what the panel is ("Sliding Doors"), so a
        // change of product shows in the drawing (V2.7.2).
        geometry.spans.forEach(function (span) {
            var width_px  = span.item.width / unit;
            var height_px = (span.heights[1] - span.heights[0]) / unit;
            if (width_px < 12 || height_px < 12) return;
            var letter = na_clamp(Math.min(width_px * 0.45, height_px * 0.3), NA_PX.TYPE_MIN, NA_PX.TYPE_MAX);
            var ink    = NA_TYPE_INKS[na_type_index(layout, span.item.type)];
            var name   = na_product_name(layout, span.item.type, opts.product);
            var named  = !!name && na_fits(name, NA_PX.NOTE_TEXT, width_px) && height_px >= letter + NA_PX.NOTE_TEXT * 2.6;
            var at_x   = span.x + span.item.width / 2;
            var at_y   = -(span.heights[0] + span.heights[1]) / 2;
            marks.push(na_label(at_x, at_y - (named ? NA_PX.NOTE_TEXT * 0.65 * unit : 0), span.item.type, letter * unit, ink, 700));
            if (named) marks.push(na_label(at_x, at_y + (letter * 0.5 + NA_PX.NOTE_TEXT * 0.45) * unit, name, NA_PX.NOTE_TEXT * unit, ink, 500));
        });

        if (opts.dimensions) {
            // Below each leg: every stretch, then the leg's whole length.
            geometry.legs.forEach(function (entry) {
                var leg      = entry.leg;
                var segments = na_leg_segments(leg);
                var rows     = [];
                if (segments.length > 1) {
                    rows.push(segments.map(function (segment) {
                        return { x0: entry.offset + segment.s0, x1: entry.offset + segment.s1, edit: na_segment_edit(layout, segment, opts.editable) };
                    }));
                }
                rows.push([{ x0: entry.offset, x1: entry.offset + leg.length,
                             edit: (opts.editable && !opts.closed) ? { kind: 'leg', index: leg.index, value: leg.length, label: 'Leg ' + (leg.index + 1) + ' length' } : null }]);

                var reach = 0;
                rows.forEach(function (row, order) {
                    reach = (order === 0 ? NA_PX.ROW_1 : NA_PX.ROW_2) * unit;
                    marks.push(na_line(row[0].x0, reach, row[row.length - 1].x1, reach, NA_DIM_STROKE));
                    [row[0].x0].concat(row.map(function (segment) { return segment.x1; })).forEach(function (x) {
                        marks.push(na_line(x, reach - tick, x, reach + tick, NA_DIM_STROKE));
                    });
                    row.forEach(function (segment) {
                        var text = na_value_text(segment.x1 - segment.x0, (segment.x1 - segment.x0) / unit);
                        if (text === null) return;
                        marks.push(na_value((segment.x0 + segment.x1) / 2, reach + NA_PX.TEXT_OFF * unit, text, size, 0, segment.edit));
                    });
                });
                [entry.offset, entry.offset + leg.length].forEach(function (x) {  // <-- Witness lines at the leg's two ends
                    marks.push(na_line(x, NA_PX.WITNESS_GAP * unit, x, reach + NA_PX.WITNESS_OVER * unit, NA_DIM_WITNESS, ' style="pointer-events:none"'));
                });
            });

            // The height, up the left. A framework's is the run's own setting.
            var x = -NA_PX.ROW_1 * unit;
            marks.push(na_line(x, 0, x, -geometry.height, NA_DIM_STROKE));
            [0, -geometry.height].forEach(function (y) { marks.push(na_line(x - tick, y, x + tick, y, NA_DIM_STROKE)); });
            if (na_fits(na_fmt(geometry.height), NA_PX.DIM_TEXT, geometry.height / unit)) {
                marks.push(na_value(x - NA_PX.TEXT_OFF * unit, -geometry.height / 2, na_fmt(geometry.height), size, -90,
                    (opts.editable && settings.frames) ? { kind: 'height', index: 0, value: geometry.height, label: 'Run height' } : null));
            }

            // A sill, under the first span of each panel type that has one.
            var seen = {};
            geometry.spans.forEach(function (span) {
                var sill = span.heights[0];
                if (seen[span.item.type] || !(sill > 0.5)) return;
                seen[span.item.type] = true;
                if (!na_fits(na_fmt(sill), NA_PX.DIM_TEXT, sill / unit) || span.item.width / unit < 30) return;
                var at = span.x + span.item.width / 2;
                marks.push(na_line(at, 0, at, -sill, NA_DIM_STROKE));
                [0, -sill].forEach(function (y) { marks.push(na_line(at - tick, y, at + tick, y, NA_DIM_STROKE)); });
                marks.push(na_value(at - NA_PX.TEXT_OFF * unit, -sill / 2, na_fmt(sill), size, -90,
                    opts.editable ? { kind: 'sill', index: na_type_order(layout, span.item.type), value: sill, label: 'Panel type ' + span.item.type + ' sill height' } : null));
            });
        }

        return { markup: geometry.shapes.join('') + marks.join(''), extents: geometry.extents };
    };

    // -----------------------------------------------------------------------
    // REGION | Fitting a drawing to its pane
    // -----------------------------------------------------------------------

    // FUNCTION | The View Box That Shows a Drawing Whole, With Room for Its Dimensions
    // ---------------------------------------------------------------
    // The box has the pane's own proportions, so one screen pixel is the
    // same number of millimetres both ways (the unit, returned with it).
    // @param extents { x0, y0, x1, y1 } page millimetres
    // @param pane    { width, height } pixels
    // @param margins { l, t, r, b } pixels kept clear round the drawing
    // @return { x, y, width, height, unit }
    Drawer.na_fit = function (extents, pane, margins) {
        var wide  = Math.max(pane.width, 40), tall = Math.max(pane.height, 40);
        if (!extents) return { x: 0, y: 0, width: wide, height: tall, unit: 1 };
        var width  = Math.max(extents.x1 - extents.x0, 1);
        var height = Math.max(extents.y1 - extents.y0, 1);
        var unit   = Math.max(width / Math.max(wide - margins.l - margins.r, 40), height / Math.max(tall - margins.t - margins.b, 40));
        var mid_x  = (extents.x0 + extents.x1) / 2 + (margins.r - margins.l) / 2 * unit;
        var mid_y  = (extents.y0 + extents.y1) / 2 + (margins.b - margins.t) / 2 * unit;
        return { x: mid_x - wide * unit / 2, y: mid_y - tall * unit / 2, width: wide * unit, height: tall * unit, unit: unit };
    };

    Drawer.na_plan_fit = function (layout, pane, options) {
        var geometry = na_plan_geometry(layout, null);
        return Drawer.na_fit(geometry ? geometry.extents : null, pane, NA_FIT_MARGINS.plan[(options && options.dimensions) ? 'on' : 'off']);
    };

    Drawer.na_elevation_fit = function (layout, pane, options) {
        var geometry = na_elevation_geometry(layout, null);
        return Drawer.na_fit(geometry ? geometry.extents : null, pane, NA_FIT_MARGINS.elevation[(options && options.dimensions) ? 'on' : 'off']);
    };

    window.Na__AssemblyRun__LayoutDrawer = Drawer;
})();
