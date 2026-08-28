(function () {
    'use strict';

    var NA_SIDE_WALL_MM = 300;
    var NA_VERTICAL_PADDING_MM = 350;
    var NA_STROKE = '#4b4036';

    function na_svg(tag, attributes) {
        return window.Na__Viewport__SvgHelpers.na_make_svg(tag, attributes);
    }

    function na_materialHex(materialId, swatchName, fallback) {
        var swatches = window[swatchName] || [];
        for (var index = 0; index < swatches.length; index += 1) {
            if (swatches[index] && swatches[index].id === materialId) {
                return swatches[index].hex || swatches[index].color || fallback;
            }
        }
        return fallback;
    }

    function na_boolean(value, fallback) {
        if (value === undefined || value === null) return fallback;
        return value === true || String(value).toLowerCase() === 'true';
    }

    function na_palette(config) {
        return {
            frame: na_materialHex(config.frame_material_id, 'NA_FRAME_FINISH_SWATCHES', '#c29b6b'),
            leaf: na_materialHex(config.double_door_leaf_material_id, 'NA_FRAME_FINISH_SWATCHES', '#b58a58'),
            handle: na_materialHex(config.double_door_handle_material_id, 'NA_HANDLE_FINISH_SWATCHES', '#c0ae8a')
        };
    }

    function na_layout(resolved) {
        var dimensions = resolved.dimensions;
        return {
            openingX: NA_SIDE_WALL_MM,
            baselineY: NA_VERTICAL_PADDING_MM + dimensions.frameInsetMm + dimensions.frameDepthMm,
            totalWidth: dimensions.widthMm + 2 * NA_SIDE_WALL_MM,
            totalHeight: dimensions.frameDepthMm + 2 * NA_VERTICAL_PADDING_MM
        };
    }

    function na_point(layout, xMm, yMm) {
        return { x: layout.openingX + xMm, y: layout.baselineY - yMm };
    }

    function na_rotate(point, pivot, angleDeg) {
        var radians = angleDeg * Math.PI / 180;
        var dx = point.x - pivot.x;
        var dy = point.y - pivot.y;
        return {
            x: pivot.x + dx * Math.cos(radians) - dy * Math.sin(radians),
            y: pivot.y + dx * Math.sin(radians) + dy * Math.cos(radians)
        };
    }

    function na_polygon(svg, points, fill, dash) {
        svg.appendChild(na_svg('polygon', {
            points: points.map(function (point) { return point.x + ',' + point.y; }).join(' '),
            fill: fill, stroke: NA_STROKE, 'stroke-width': 1,
            'stroke-dasharray': dash || ''
        }));
    }

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

    function na_leafCorners(leaf) {
        return [
            { x: leaf.originXMm, y: leaf.originYMm },
            { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm },
            { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm + leaf.thicknessMm },
            { x: leaf.originXMm, y: leaf.originYMm + leaf.thicknessMm }
        ];
    }

    // Fixed panels are dead joinery - no pivot, no open-state ghost, no swing
    // arc and no handle. Only the closed footprint is drawn.
    function na_fixedPanels(config) {
        return na_boolean(config && config.double_door_fixed_panels, false);
    }

    function na_drawLeaf(svg, layout, leaf, palette, config) {
        var closed = na_leafCorners(leaf).map(function (point) {
            return na_point(layout, point.x, point.y);
        });
        na_polygon(svg, closed, palette.leaf);
        if (na_fixedPanels(config)) return;

        var pivot = { x: leaf.hingeXMm, y: leaf.pivotYMm };
        if (na_boolean(config.double_door_create_open_state_copy, true)) {
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
        if (na_boolean(config.double_door_show_swing_arcs, true)) na_drawArc(svg, layout, leaf);
        var handlePaired = String((config && config.double_door_handle_pairing) || 'Paired').toLowerCase() === 'paired';
        if (leaf.isActive || handlePaired) na_drawHandle(svg, layout, leaf, palette, config);
    }

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

    function na_drawHandle(svg, layout, leaf, palette, config) {
        var backset = Number(config.double_door_handle_backset_mm) || 40;
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
        if (!na_boolean(config.double_door_create_open_state_copy, true)) return;

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

    var Na__ExtDouble__PlanGenerator = {
        na_render: function (svgElement, config) {
            if (!svgElement || !window.Na__ExtDouble__LeafConfigResolver) return;
            window.Na__Viewport__SvgHelpers.na_clear_svg(svgElement);
            // @delegate: Na__AssemblyStudio__ExtDouble__UiSystem__LeafConfigResolver__.js
            var resolved = window.Na__ExtDouble__LeafConfigResolver.na_resolve(config || {});
            var layout = na_layout(resolved);
            var palette = na_palette(config || {});
            na_drawWalls(svgElement, layout, resolved.dimensions);
            na_drawFrame(svgElement, layout, resolved.dimensions, palette);
            resolved.leaves.forEach(function (leaf) {
                na_drawLeaf(svgElement, layout, leaf, palette, config || {});
            });
        },
        na_fit_to_content: function (config) {
            var resolved = window.Na__ExtDouble__LeafConfigResolver.na_resolve(config || {});
            var layout = na_layout(resolved);
            return { x: 0, y: 0, width: layout.totalWidth, height: layout.totalHeight };
        }
    };

    window.Na__ExtDouble__PlanGenerator = Object.freeze(Na__ExtDouble__PlanGenerator);
}());
