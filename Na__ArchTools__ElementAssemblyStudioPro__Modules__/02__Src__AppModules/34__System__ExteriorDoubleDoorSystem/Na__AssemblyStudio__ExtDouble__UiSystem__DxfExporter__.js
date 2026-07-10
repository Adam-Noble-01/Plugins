(function () {
    'use strict';

    function na_line(layer, x1, y1, x2, y2) {
        return `0\nLINE\n8\n${layer}\n10\n${x1}\n20\n${y1}\n11\n${x2}\n21\n${y2}\n`;
    }

    function na_rect(layer, x, y, width, height) {
        if (width <= 0 || height <= 0) return '';
        return na_line(layer, x, y, x + width, y) +
            na_line(layer, x + width, y, x + width, y + height) +
            na_line(layer, x + width, y + height, x, y + height) +
            na_line(layer, x, y + height, x, y);
    }

    function na_circle(layer, x, y, radius) {
        return `0\nCIRCLE\n8\n${layer}\n10\n${x}\n20\n${y}\n40\n${radius}\n`;
    }

    function na_text(layer, x, y, height, text) {
        return `0\nTEXT\n8\n${layer}\n10\n${x}\n20\n${y}\n40\n${height}\n1\n${text}\n`;
    }

    function na_arc(layer, x, y, radius, startAngle, sweepAngle) {
        var endAngle = startAngle + sweepAngle;
        if (sweepAngle < 0) {
            var swap = startAngle;
            startAngle = endAngle;
            endAngle = swap;
        }
        return `0\nARC\n8\n${layer}\n10\n${x}\n20\n${y}\n40\n${radius}\n50\n${((startAngle % 360) + 360) % 360}\n51\n${((endAngle % 360) + 360) % 360}\n`;
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

    function na_elevationLift(config, resolved) {
        return config.has_cill !== false && resolved.dimensions.frameBottomMm > 0
            ? Math.max(0, Number(config.cill_height_mm || 50))
            : 0;
    }

    function na_addFrame(config, resolved, lift) {
        var dimensions = resolved.dimensions;
        var dxf = '';
        dxf += na_rect('NA_FRAME', 0, lift, dimensions.frameLeftMm, dimensions.heightMm);
        dxf += na_rect('NA_FRAME', dimensions.widthMm - dimensions.frameRightMm, lift,
            dimensions.frameRightMm, dimensions.heightMm);
        dxf += na_rect('NA_FRAME', dimensions.frameLeftMm, lift,
            dimensions.innerWidthMm, dimensions.frameBottomMm);
        dxf += na_rect('NA_FRAME', dimensions.frameLeftMm,
            dimensions.heightMm - dimensions.frameTopMm + lift,
            dimensions.innerWidthMm, dimensions.frameTopMm);
        if (config.has_cill !== false && dimensions.frameBottomMm > 0) {
            var cillHeight = Math.max(0, Number(config.cill_height_mm || 50));
            dxf += na_rect('NA_CILL', 0, -cillHeight + lift, dimensions.widthMm, cillHeight);
        }
        return dxf;
    }

    function na_addLeafElevation(config, leaf, lift) {
        var layout = leaf.panelLayout;
        var dxf = na_rect('NA_DOOR_LEAF', leaf.originXMm, leaf.originZMm + lift, leaf.widthMm, leaf.heightMm);
        dxf += na_rect('NA_RAIL_STILE', leaf.originXMm, leaf.originZMm + lift, layout.stileMm, leaf.heightMm);
        dxf += na_rect('NA_RAIL_STILE', leaf.originXMm + leaf.widthMm - layout.stileMm,
            leaf.originZMm + lift, layout.stileMm, leaf.heightMm);
        dxf += na_rect('NA_RAIL_STILE', leaf.originXMm + layout.stileMm, leaf.originZMm + lift,
            leaf.widthMm - 2 * layout.stileMm, layout.bottomRailMm);
        dxf += na_rect('NA_RAIL_STILE', leaf.originXMm + layout.stileMm,
            leaf.originZMm + leaf.heightMm - layout.topRailMm + lift,
            leaf.widthMm - 2 * layout.stileMm, layout.topRailMm);

        if (layout.fieldRegion && layout.glazedRegion) {
            dxf += na_rect('NA_RAIL_STILE', layout.fieldRegion.xMm,
                layout.fieldRegion.zMm + layout.fieldRegion.heightMm + lift,
                layout.fieldRegion.widthMm, layout.midRailMm);
        }
        layout.fieldCells.forEach(function (cell) {
            dxf += na_rect('NA_DOOR_PANEL', cell.xMm, cell.zMm + lift, cell.widthMm, cell.heightMm);
        });
        layout.fieldDividers.forEach(function (divider) {
            dxf += na_rect(
                'NA_RAIL_STILE',
                divider.xMm,
                divider.zMm + lift,
                divider.widthMm,
                divider.heightMm
            );
        });
        if (layout.glazedRegion) {
            var glass = layout.glazedRegion;
            dxf += na_rect('NA_GLASS', glass.xMm, glass.zMm + lift, glass.widthMm, glass.heightMm);
            var verticalPositions = na_barPositions(
                glass.xMm, glass.widthMm, leaf.settings.verticalBars,
                leaf.settings.marginEnabled, leaf.settings.marginOffsetMm
            );
            var horizontalPositions = na_barPositions(
                glass.zMm, glass.heightMm, leaf.settings.horizontalBars,
                leaf.settings.marginEnabled, leaf.settings.marginOffsetMm
            );
            var removedSource = Array.isArray(config.double_door_removed_glazebars)
                ? config.double_door_removed_glazebars
                : config.removed_glazebars;
            var removedBars = new Set(Array.isArray(removedSource)
                ? removedSource.map(String)
                : []);
            verticalPositions.forEach(function (vx, index) {
                if (removedBars.has(na_glazebarKey(leaf, 'vertical', index + 1))) return;
                dxf += na_line('NA_GLAZEBAR', vx, glass.zMm + lift, vx, glass.zMm + glass.heightMm + lift);
            });
            horizontalPositions.forEach(function (position, index) {
                if (removedBars.has(na_glazebarKey(leaf, 'horizontal', index + 1))) return;
                var hz = position + leaf.settings.horizontalOffsetMm;
                dxf += na_line('NA_GLAZEBAR', glass.xMm, hz + lift, glass.xMm + glass.widthMm, hz + lift);
            });
        }
        if (leaf.isActive) {
            var backset = Number(config.double_door_handle_backset_mm || 60);
            var handleX = leaf.side === 'left'
                ? leaf.originXMm + leaf.widthMm - backset
                : leaf.originXMm + backset;
            dxf += na_circle('NA_DOOR_HARDWARE', handleX,
                leaf.originZMm + Number(config.double_door_handle_height_mm || 1000) + lift, 12);
        }
        return dxf;
    }

    function na_glazebarKey(leaf, orientation, barIndex) {
        return `0:0:${leaf.index - 1}:0:${orientation}:${barIndex}`;
    }

    function na_barPositions(start, size, count, marginEnabled, marginOffset) {
        var math = window.Na__GlazebarMath;
        if (math && typeof math.na_computeBarPositions === 'function') {
            return math.na_computeBarPositions(start, size, count, marginEnabled, marginOffset);
        }
        var positions = [];
        for (var index = 1; index <= count; index += 1) {
            positions.push(start + size * index / (count + 1));
        }
        return positions;
    }

    function na_addLeafPlan(config, leaf, offset) {
        var dxf = na_rect(
            'NA_DOOR_LEAF',
            leaf.originXMm,
            leaf.originYMm + offset,
            leaf.widthMm,
            leaf.thicknessMm
        );
        var corners = [
            { x: leaf.originXMm, y: leaf.originYMm },
            { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm },
            { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm + leaf.thicknessMm },
            { x: leaf.originXMm, y: leaf.originYMm + leaf.thicknessMm }
        ];
        var pivot = { x: leaf.hingeXMm, y: leaf.pivotYMm };
        if (config.double_door_create_open_state_copy !== false) {
            var opened = corners.map(function (point) {
                return na_rotate(point, pivot, leaf.signedAngleDeg);
            });
            opened.forEach(function (point, index) {
                var following = opened[(index + 1) % opened.length];
                dxf += na_line('NA_DOOR_SWING', point.x, point.y + offset,
                    following.x, following.y + offset);
            });
        }
        if (config.double_door_show_swing_arcs !== false) {
            dxf += na_arc('NA_DOOR_SWING', pivot.x, pivot.y + offset,
                leaf.widthMm, leaf.closedLatchAngleDeg, leaf.signedAngleDeg);
        }
        return dxf;
    }

    function na_export_dxf(config) {
        var resolver = window.Na__ExtDouble__LeafConfigResolver;
        if (!resolver) return '';
        var resolved = resolver.na_resolve(config || {});
        var elevationLift = na_elevationLift(config || {}, resolved);
        var dxf = '0\nSECTION\n2\nENTITIES\n';
        dxf += na_addFrame(config || {}, resolved, elevationLift);
        resolved.leaves.forEach(function (leaf) {
            dxf += na_addLeafElevation(config || {}, leaf, elevationLift);
        });
        if ((config || {}).show_dimensions !== false) {
            dxf += na_text('NA_DIMENSIONS', resolved.dimensions.widthMm / 2,
                resolved.dimensions.heightMm + 100 + elevationLift, 35,
                `Exterior Double Door ${Math.round(resolved.dimensions.widthMm)} x ${Math.round(resolved.dimensions.heightMm)} mm`);
            resolved.leaves.forEach(function (leaf) {
                dxf += na_text('NA_DIMENSIONS', leaf.originXMm + leaf.widthMm / 2,
                    leaf.originZMm - 80 + elevationLift, 25,
                    `${leaf.sideName} ${Math.round(leaf.widthMm)} mm`);
            });
        }
        var maximumLeafWidth = Math.max.apply(null, resolved.leaves.map(function (leaf) { return leaf.widthMm; }));
        var planOffset = -(maximumLeafWidth + resolved.dimensions.frameDepthMm + 300);
        resolved.leaves.forEach(function (leaf) {
            dxf += na_addLeafPlan(config || {}, leaf, planOffset);
        });
        return dxf + '0\nENDSEC\n0\nEOF\n';
    }

    window.Na__ExtDouble__DxfExporter = Object.freeze({
        na_export_dxf: na_export_dxf
    });
}());
