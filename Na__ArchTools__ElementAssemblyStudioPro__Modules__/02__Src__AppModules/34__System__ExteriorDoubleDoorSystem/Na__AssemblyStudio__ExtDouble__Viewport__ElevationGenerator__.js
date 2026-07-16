(function () {
    'use strict';

    var NA_PADDING_MM = 180;
    var NA_STROKE = '#4b4036';
    var NA_GLASS_FILL = '#b9dcea';

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

    function na_palette(config) {
        return {
            frame: na_materialHex(config.frame_material_id, 'NA_FRAME_FINISH_SWATCHES', '#c29b6b'),
            leaf: na_materialHex(config.double_door_leaf_material_id, 'NA_FRAME_FINISH_SWATCHES', '#b58a58'),
            handle: na_materialHex(config.double_door_handle_material_id, 'NA_HANDLE_FINISH_SWATCHES', '#c0ae8a')
        };
    }

    function na_rect(svg, x, y, width, height, fill, options) {
        options = options || {};
        svg.appendChild(na_svg('rect', {
            x: x, y: y, width: Math.max(0, width), height: Math.max(0, height),
            fill: fill, stroke: options.stroke || NA_STROKE,
            'stroke-width': options.strokeWidth || 1,
            'stroke-dasharray': options.dash || ''
        }));
    }

    function na_y(layout, zMm) {
        return layout.openingY + layout.heightMm - zMm;
    }

    function na_drawFrame(svg, layout, dimensions, palette) {
        na_rect(svg, layout.openingX, layout.openingY, dimensions.frameLeftMm, layout.heightMm, palette.frame);
        na_rect(svg, layout.openingX + layout.widthMm - dimensions.frameRightMm, layout.openingY,
            dimensions.frameRightMm, layout.heightMm, palette.frame);
        na_rect(svg, layout.openingX + dimensions.frameLeftMm, layout.openingY,
            dimensions.innerWidthMm, dimensions.frameTopMm, palette.frame);
        na_rect(svg, layout.openingX + dimensions.frameLeftMm,
            layout.openingY + layout.heightMm - dimensions.frameBottomMm,
            dimensions.innerWidthMm, dimensions.frameBottomMm, palette.frame);
        if (layout.cillLiftMm > 0) {
            na_rect(svg, layout.openingX, layout.openingY + layout.heightMm,
                layout.widthMm, layout.cillLiftMm, palette.frame);
        }
    }

    function na_drawLeaf(svg, layout, leaf, palette) {
        var panel = leaf.panelLayout;
        var x = layout.openingX + leaf.originXMm;
        var top = na_y(layout, leaf.originZMm + leaf.heightMm);
        na_rect(svg, x, top, leaf.widthMm, leaf.heightMm, palette.leaf);

        if (panel.glazedRegion) {
            var glazed = panel.glazedRegion;
            na_rect(svg, layout.openingX + glazed.xMm, na_y(layout, glazed.zMm + glazed.heightMm),
                glazed.widthMm, glazed.heightMm, NA_GLASS_FILL);
            na_drawGlazeBars(svg, layout, leaf, glazed, palette);
        }

        panel.fieldCells.forEach(function (cell) {
            var inset = Math.min(leaf.settings.insetMm, cell.widthMm / 3, cell.heightMm / 3);
            var fill = leaf.settings.outputMode === 'Linework' ? 'none' : palette.leaf;
            na_rect(svg, layout.openingX + cell.xMm + inset,
                na_y(layout, cell.zMm + cell.heightMm - inset),
                cell.widthMm - 2 * inset, cell.heightMm - 2 * inset, fill, {
                    strokeWidth: leaf.settings.outputMode === 'Linework' ? 1 : 3
                });
            if (leaf.settings.outputMode === 'ThreeDimensional' && leaf.settings.profile === 'RaisedBevelled') {
                var bevel = Math.min(leaf.settings.bevelMm, inset);
                na_rect(svg, layout.openingX + cell.xMm + bevel,
                    na_y(layout, cell.zMm + cell.heightMm - bevel),
                    cell.widthMm - 2 * bevel, cell.heightMm - 2 * bevel, 'none', { strokeWidth: 1 });
            }
        });

        var handlePaired = String((layout.config && layout.config.double_door_handle_pairing) || 'Paired').toLowerCase() === 'paired';
        if (leaf.isActive || handlePaired) na_drawHandle(svg, layout, leaf, palette);
    }

    function na_drawGlazeBars(svg, layout, leaf, region, palette) {
        var settings = leaf.settings;
        var removedSource = Array.isArray(layout.config.double_door_removed_glazebars)
            ? layout.config.double_door_removed_glazebars
            : layout.config.removed_glazebars;
        var removedBars = new Set(Array.isArray(removedSource)
            ? removedSource.map(String)
            : []);
        var math = window.Na__GlazebarMath;
        var verticalPositions = math && typeof math.na_computeBarPositions === 'function'
            ? math.na_computeBarPositions(
                region.xMm, region.widthMm, settings.verticalBars,
                settings.marginEnabled, settings.marginOffsetMm
            )
            : na_evenBarPositions(region.xMm, region.widthMm, settings.verticalBars);
        var horizontalPositions = math && typeof math.na_computeBarPositions === 'function'
            ? math.na_computeBarPositions(
                region.zMm, region.heightMm, settings.horizontalBars,
                settings.marginEnabled, settings.marginOffsetMm
            )
            : na_evenBarPositions(region.zMm, region.heightMm, settings.horizontalBars);

        verticalPositions.forEach(function (x, index) {
            var barIndex = index + 1;
            var barX = layout.openingX + x - settings.glazeBarWidthMm / 2;
            var barY = na_y(layout, region.zMm + region.heightMm);
            if (!removedBars.has(na_glazebarKey(leaf, 'vertical', barIndex))) {
                na_rect(svg, barX, barY,
                    settings.glazeBarWidthMm, region.heightMm, palette.leaf);
            }
            na_addGlazebarClickTarget(
                svg, barX, barY, settings.glazeBarWidthMm, region.heightMm,
                leaf, 'vertical', barIndex
            );
        });
        horizontalPositions.forEach(function (position, index) {
            var barIndex = index + 1;
            var z = position + settings.horizontalOffsetMm;
            var barX = layout.openingX + region.xMm;
            var barY = na_y(layout, z + settings.glazeBarWidthMm / 2);
            if (!removedBars.has(na_glazebarKey(leaf, 'horizontal', barIndex))) {
                na_rect(svg, barX, barY,
                    region.widthMm, settings.glazeBarWidthMm, palette.leaf);
            }
            na_addGlazebarClickTarget(
                svg, barX, barY, region.widthMm, settings.glazeBarWidthMm,
                leaf, 'horizontal', barIndex
            );
        });
    }

    function na_glazebarKey(leaf, orientation, barIndex) {
        return `0:0:${leaf.index - 1}:0:${orientation}:${barIndex}`;
    }

    function na_addGlazebarClickTarget(svg, x, y, width, height, leaf, orientation, barIndex) {
        var minimumHitSize = 16;
        var targetX = x;
        var targetY = y;
        var targetWidth = width;
        var targetHeight = height;
        if (orientation === 'horizontal') {
            var extraHeight = Math.max(0, minimumHitSize - height);
            targetY -= extraHeight / 2;
            targetHeight += extraHeight;
        } else {
            var extraWidth = Math.max(0, minimumHitSize - width);
            targetX -= extraWidth / 2;
            targetWidth += extraWidth;
        }
        svg.appendChild(na_svg('rect', {
            class: 'na-glazebar-click-target',
            'data-opening-index': 0,
            'data-cell-index': 0,
            'data-panel-index': leaf.index - 1,
            'data-sash-index': 0,
            'data-orientation': orientation,
            'data-bar-index': barIndex,
            x: targetX,
            y: targetY,
            width: targetWidth,
            height: targetHeight,
            fill: 'rgba(0, 0, 0, 0.001)',
            stroke: 'none',
            style: 'cursor:pointer;pointer-events:all'
        }));
    }

    function na_evenBarPositions(start, size, count) {
        var positions = [];
        for (var index = 1; index <= count; index += 1) {
            positions.push(start + size * index / (count + 1));
        }
        return positions;
    }

    function na_drawHandle(svg, layout, leaf, palette) {
        var backset = Number(layout.config.double_door_handle_backset_mm) || 40;
        var height = Number(layout.config.double_door_handle_height_mm) || 900;
        var x = leaf.side === 'left'
            ? layout.openingX + leaf.originXMm + leaf.widthMm - backset
            : layout.openingX + leaf.originXMm + backset;
        var y = na_y(layout, leaf.originZMm + height);
        // Scroll hangs down; curl toward the meeting stile (left leaf → +X, right → -X)
        var towardMeeting = leaf.side === 'left' ? 1 : -1;
        var fill = palette.handle || '#6e6558';

        svg.appendChild(na_svg('circle', {
            cx: x, cy: y, r: 10, fill: fill, stroke: NA_STROKE, 'stroke-width': 1.5
        }));
        // Stem + scroll tip (schematic — Scroll asset has no Elevation2D paths yet)
        svg.appendChild(na_svg('path', {
            d: [
                'M', x, y + 8,
                'C', x + towardMeeting * 6, y + 28,
                x + towardMeeting * 34, y + 48,
                x + towardMeeting * 10, y + 72
            ].join(' '),
            fill: 'none',
            stroke: fill,
            'stroke-width': 7,
            'stroke-linecap': 'round'
        }));
        svg.appendChild(na_svg('path', {
            d: [
                'M', x + towardMeeting * 10, y + 72,
                'C', x + towardMeeting * -4, y + 86,
                x + towardMeeting * 18, y + 92,
                x + towardMeeting * 8, y + 78
            ].join(' '),
            fill: 'none',
            stroke: NA_STROKE,
            'stroke-width': 2.5,
            'stroke-linecap': 'round'
        }));
    }

    function na_drawDimensions(svg, layout, resolved) {
        var overall = na_svg('text', {
            x: layout.openingX + layout.widthMm / 2, y: layout.openingY - 45,
            fill: '#333', 'text-anchor': 'middle', 'font-size': 34
        });
        overall.textContent = 'W: ' + Math.round(layout.widthMm) + 'mm  H: ' + Math.round(layout.heightMm) + 'mm';
        svg.appendChild(overall);
        resolved.leaves.forEach(function (leaf) {
            var text = na_svg('text', {
                x: layout.openingX + leaf.originXMm + leaf.widthMm / 2,
                y: layout.openingY + layout.heightMm + layout.cillLiftMm + 50,
                fill: '#333', 'text-anchor': 'middle', 'font-size': 28
            });
            text.textContent = leaf.sideName + ': ' + Math.round(leaf.widthMm) + 'mm';
            svg.appendChild(text);
        });
    }

    function na_layout(config, resolved) {
        var hasCill = config.has_cill !== false && String(config.has_cill).toLowerCase() !== 'false';
        var cillLift = hasCill && resolved.dimensions.frameBottomMm > 0
            ? Math.max(0, Number(config.cill_height_mm) || 50)
            : 0;
        return {
            config: config,
            openingX: NA_PADDING_MM,
            openingY: NA_PADDING_MM,
            widthMm: resolved.dimensions.widthMm,
            heightMm: resolved.dimensions.heightMm,
            cillLiftMm: cillLift,
            totalWidth: resolved.dimensions.widthMm + 2 * NA_PADDING_MM,
            totalHeight: resolved.dimensions.heightMm + cillLift + 2 * NA_PADDING_MM
        };
    }

    var Na__ExtDouble__ElevationGenerator = {
        na_render: function (svgElement, config) {
            if (!svgElement || !window.Na__ExtDouble__LeafConfigResolver) return;
            window.Na__Viewport__SvgHelpers.na_clear_svg(svgElement);
            // @delegate: Na__AssemblyStudio__ExtDouble__UiSystem__LeafConfigResolver__.js
            var resolved = window.Na__ExtDouble__LeafConfigResolver.na_resolve(config || {});
            var layout = na_layout(config || {}, resolved);
            var palette = na_palette(config || {});
            na_drawFrame(svgElement, layout, resolved.dimensions, palette);
            resolved.leaves.forEach(function (leaf) { na_drawLeaf(svgElement, layout, leaf, palette); });
            if ((config || {}).show_dimensions !== false) na_drawDimensions(svgElement, layout, resolved);
        },
        na_fit_to_content: function (config) {
            var resolved = window.Na__ExtDouble__LeafConfigResolver.na_resolve(config || {});
            var layout = na_layout(config || {}, resolved);
            return { x: 0, y: 0, width: layout.totalWidth, height: layout.totalHeight };
        }
    };

    window.Na__ExtDouble__ElevationGenerator = Object.freeze(Na__ExtDouble__ElevationGenerator);
}());
