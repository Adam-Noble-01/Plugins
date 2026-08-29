/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - PLAN SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDoorCommon__Viewport__PlanGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Prefix-parameterised plan SVG generator factory shared by every
                hinged exterior door product. Draws reveal walls, frame jambs,
                each leaf footprint, the open-state ghost, hinge pivot, swing
                arc and handle schematic.
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Extracted verbatim from the Exterior Double Door plan generator so the
     double door and the single door draw from one code path.
   - Fixed panels are dead joinery: only the closed footprint is drawn - no
     pivot, no open-state ghost, no swing arc and no handle.

   SPEC CONTRACT:
     prefix                 {string}   Key prefix, no trailing underscore.
     na_resolver            {function} () -> the product leaf config resolver.
     na_draw_handle_for_leaf{function} (config, leaf) -> boolean.

   DEPENDENCIES:
   - window.Na__Viewport__SvgHelpers.na_make_svg / na_clear_svg

   ============================================================================= */


// =============================================================================
// REGION | ExtDoorCommon Plan SVG Generator Factory
// =============================================================================

(function () {
    'use strict';

    var NA_SIDE_WALL_MM = 300;
    var NA_VERTICAL_PADDING_MM = 350;
    var NA_STROKE = '#4b4036';

    // HELPER FUNCTION | Create SVG Element via Shared Viewport Helpers
    // ------------------------------------------------------------
    function na_svg(tag, attributes) {
        return window.Na__Viewport__SvgHelpers.na_make_svg(tag, attributes);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Look Up Material Hex from a Global Swatch Array
    // ------------------------------------------------------------
    function na_materialHex(materialId, swatchName, fallback) {
        var swatches = window[swatchName] || [];
        for (var index = 0; index < swatches.length; index += 1) {
            if (swatches[index] && swatches[index].id === materialId) {
                return swatches[index].hex || swatches[index].color || fallback;
            }
        }
        return fallback;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Coerce to Boolean or Fallback
    // ------------------------------------------------------------
    function na_boolean(value, fallback) {
        if (value === undefined || value === null) return fallback;
        return value === true || String(value).toLowerCase() === 'true';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Plan Layout Box from Resolved Dimensions
    // ------------------------------------------------------------
    function na_layout(resolved) {
        var dimensions = resolved.dimensions;
        return {
            openingX: NA_SIDE_WALL_MM,
            baselineY: NA_VERTICAL_PADDING_MM + dimensions.frameInsetMm + dimensions.frameDepthMm,
            totalWidth: dimensions.widthMm + 2 * NA_SIDE_WALL_MM,
            totalHeight: dimensions.frameDepthMm + 2 * NA_VERTICAL_PADDING_MM
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Model (x, y) mm to SVG Point
    // ------------------------------------------------------------
    function na_point(layout, xMm, yMm) {
        return { x: layout.openingX + xMm, y: layout.baselineY - yMm };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Rotate a Point About a Pivot
    // ------------------------------------------------------------
    function na_rotate(point, pivot, angleDeg) {
        var radians = angleDeg * Math.PI / 180;
        var dx = point.x - pivot.x;
        var dy = point.y - pivot.y;
        return {
            x: pivot.x + dx * Math.cos(radians) - dy * Math.sin(radians),
            y: pivot.y + dx * Math.sin(radians) + dy * Math.cos(radians)
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Append a Polygon to the SVG
    // ------------------------------------------------------------
    function na_polygon(svg, points, fill, dash) {
        svg.appendChild(na_svg('polygon', {
            points: points.map(function (point) { return point.x + ',' + point.y; }).join(' '),
            fill: fill, stroke: NA_STROKE, 'stroke-width': 1,
            'stroke-dasharray': dash || ''
        }));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Draw the Reveal Walls Either Side of the Opening
    // ------------------------------------------------------------
    function na_drawWalls(svg, layout, dimensions) {
        var topY = layout.baselineY - dimensions.frameInsetMm - dimensions.frameDepthMm;
        svg.appendChild(na_svg('rect', {
            x: 0, y: topY, width: layout.openingX, height: dimensions.frameDepthMm,
            fill: '#d8d8d8', stroke: '#666', 'stroke-width': 1
        }));
        svg.appendChild(na_svg('rect', {
            x: layout.openingX + dimensions.widthMm, y: topY,
            width: NA_SIDE_WALL_MM, height: dimensions.frameDepthMm,
            fill: '#d8d8d8', stroke: '#666', 'stroke-width': 1
        }));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Draw Both Frame Jambs in Plan
    // ------------------------------------------------------------
    function na_drawFrame(svg, layout, dimensions, palette) {
        var y = layout.baselineY - dimensions.frameInsetMm - dimensions.frameDepthMm;
        [
            [layout.openingX, dimensions.frameLeftMm],
            [layout.openingX + dimensions.widthMm - dimensions.frameRightMm, dimensions.frameRightMm]
        ].forEach(function (item) {
            svg.appendChild(na_svg('rect', {
                x: item[0], y: y, width: item[1], height: dimensions.frameDepthMm,
                fill: palette.frame, stroke: NA_STROKE, 'stroke-width': 1
            }));
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Closed Leaf Footprint Corners (mm space)
    // ------------------------------------------------------------
    function na_leafCorners(leaf) {
        return [
            { x: leaf.originXMm, y: leaf.originYMm },
            { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm },
            { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm + leaf.thicknessMm },
            { x: leaf.originXMm, y: leaf.originYMm + leaf.thicknessMm }
        ];
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Draw the Dashed Swing Arc for One Leaf
    // ------------------------------------------------------------
    function na_drawArc(svg, layout, leaf) {
        var segments = 32;
        var points = [];
        for (var index = 0; index <= segments; index += 1) {
            var degrees = leaf.closedLatchAngleDeg + leaf.signedAngleDeg * index / segments;
            var radians = degrees * Math.PI / 180;
            points.push(na_point(
                layout,
                leaf.hingeXMm + leaf.widthMm * Math.cos(radians),
                leaf.pivotYMm + leaf.widthMm * Math.sin(radians)
            ));
        }
        svg.appendChild(na_svg('polyline', {
            points: points.map(function (point) { return point.x + ',' + point.y; }).join(' '),
            fill: 'none', stroke: NA_STROKE, 'stroke-width': 1, 'stroke-dasharray': '4 4'
        }));
    }
    // ---------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Generator Factory
    // -----------------------------------------------------------------------------

    // FUNCTION | Build a Prefix-Bound Plan Generator
    // ------------------------------------------------------------
    function na_create(spec) {
        var prefix = String(spec.prefix);

        // HELPER FUNCTION | Build One Prefixed Config Key
        // ------------------------------------------------------------
        function na_key(suffix) {
            return prefix + '_' + suffix;
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Resolve Frame / Leaf / Handle Palette Colours
        // ------------------------------------------------------------
        function na_palette(config) {
            return {
                frame: na_materialHex(config.frame_material_id, 'NA_FRAME_FINISH_SWATCHES', '#c29b6b'),
                leaf: na_materialHex(config[na_key('leaf_material_id')], 'NA_FRAME_FINISH_SWATCHES', '#b58a58'),
                handle: na_materialHex(config[na_key('handle_material_id')], 'NA_HANDLE_FINISH_SWATCHES', '#c0ae8a')
            };
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Fixed-Panel Mode Predicate
        // ------------------------------------------------------------
        // Fixed panels are dead joinery - no pivot, no open-state ghost, no
        // swing arc and no handle. Only the closed footprint is drawn.
        function na_fixedPanels(config) {
            return na_boolean(config && config[na_key('fixed_panels')], false);
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Draw the Plan Handle Schematic for One Leaf
        // ------------------------------------------------------------
        function na_drawHandle(svg, layout, leaf, palette, config) {
            var backset = Number(config[na_key('handle_backset_mm')]) || 40;
            var x = leaf.side === 'left'
                ? leaf.originXMm + leaf.widthMm - backset
                : leaf.originXMm + backset;
            var yClosed = leaf.originYMm + (leaf.side === 'left' ? leaf.thicknessMm : 0);
            var point = na_point(layout, x, yClosed);
            var fill = (palette && palette.handle) || '#6e6558';
            // Plan schematic: rose + short grip projecting off the leaf face
            var faceOut = leaf.side === 'left' ? 1 : -1;
            var tip = na_point(layout, x, yClosed + faceOut * 28);

            svg.appendChild(na_svg('circle', {
                cx: point.x, cy: point.y, r: 8, fill: fill, stroke: NA_STROKE, 'stroke-width': 1.5
            }));
            svg.appendChild(na_svg('line', {
                x1: point.x, y1: point.y, x2: tip.x, y2: tip.y,
                stroke: fill, 'stroke-width': 5, 'stroke-linecap': 'round'
            }));
            if (!na_boolean(config[na_key('create_open_state_copy')], true)) return;

            var opened = na_rotate(
                { x: x, y: yClosed },
                { x: leaf.hingeXMm, y: leaf.pivotYMm },
                leaf.signedAngleDeg
            );
            var openedPoint = na_point(layout, opened.x, opened.y);
            svg.appendChild(na_svg('circle', {
                cx: openedPoint.x, cy: openedPoint.y, r: 8, fill: 'none',
                stroke: NA_STROKE, 'stroke-width': 1.5, 'stroke-dasharray': '3 2'
            }));
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Draw One Leaf Footprint, Ghost, Pivot, Arc, Handle
        // ------------------------------------------------------------
        function na_drawLeaf(svg, layout, leaf, palette, config) {
            var closed = na_leafCorners(leaf).map(function (point) {
                return na_point(layout, point.x, point.y);
            });
            na_polygon(svg, closed, palette.leaf);
            if (na_fixedPanels(config)) return;

            var pivot = { x: leaf.hingeXMm, y: leaf.pivotYMm };
            if (na_boolean(config[na_key('create_open_state_copy')], true)) {
                var open = na_leafCorners(leaf).map(function (point) {
                    var rotated = na_rotate(point, pivot, leaf.signedAngleDeg);
                    return na_point(layout, rotated.x, rotated.y);
                });
                na_polygon(svg, open, 'none', '6 4');
            }

            var pivotSvg = na_point(layout, pivot.x, pivot.y);
            svg.appendChild(na_svg('circle', {
                cx: pivotSvg.x, cy: pivotSvg.y, r: 5, fill: '#d00000', stroke: '#d00000'
            }));
            if (na_boolean(config[na_key('show_swing_arcs')], true)) na_drawArc(svg, layout, leaf);
            if (spec.na_draw_handle_for_leaf(config, leaf)) na_drawHandle(svg, layout, leaf, palette, config);
        }
        // ---------------------------------------------------------------

        return {
            na_render: function (svgElement, config) {
                var resolver = spec.na_resolver();
                if (!svgElement || !resolver) return;
                window.Na__Viewport__SvgHelpers.na_clear_svg(svgElement);
                var resolved = resolver.na_resolve(config || {});
                var layout = na_layout(resolved);
                var palette = na_palette(config || {});
                na_drawWalls(svgElement, layout, resolved.dimensions);
                na_drawFrame(svgElement, layout, resolved.dimensions, palette);
                resolved.leaves.forEach(function (leaf) {
                    na_drawLeaf(svgElement, layout, leaf, palette, config || {});
                });
            },
            na_fit_to_content: function (config) {
                var resolver = spec.na_resolver();
                if (!resolver) return { x: 0, y: 0, width: 1000, height: 1000 };
                var resolved = resolver.na_resolve(config || {});
                var layout = na_layout(resolved);
                return { x: 0, y: 0, width: layout.totalWidth, height: layout.totalHeight };
            }
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    window.Na__ExtDoorCommon__PlanGenerator = Object.freeze({ na_create: na_create });

}());


/* =============================================================================
   END OF FILE
   ============================================================================= */
