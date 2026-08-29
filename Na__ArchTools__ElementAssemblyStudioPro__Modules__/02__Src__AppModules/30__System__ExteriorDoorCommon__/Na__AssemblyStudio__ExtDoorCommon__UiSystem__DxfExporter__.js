/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - DXF EXPORTER (UI)
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDoorCommon__UiSystem__DxfExporter__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Prefix-parameterised DXF entity-stream factory shared by every
                hinged exterior door product. Builds elevation + plan entities
                from the live UI config for the browser DXF download path.
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Extracted verbatim from the Exterior Double Door DXF exporter so the
     double door and the single door emit the same layers and geometry.
   - Elevation entities: frame, cill, leaf outlines, rails/stiles, field
     panels, glass, glaze bars, handle circle, dimension text.
   - Plan entities: closed leaf footprint, optional open-state copy and swing
     arcs below the elevation.
   - This is the browser fallback path. Inside SketchUp the Export DXF button
     routes to the Ruby exporter instead.

   SPEC CONTRACT:
     prefix                 {string}   Key prefix, no trailing underscore.
     productLabel           {string}   Title text used in the dimension label.
     na_resolver            {function} () -> the product leaf config resolver.
     na_draw_handle_for_leaf{function} (config, leaf) -> boolean.

   DEPENDENCIES:
   - window.Na__GlazebarMath (optional shared bar math)

   ============================================================================= */


// =============================================================================
// REGION | ExtDoorCommon DXF Exporter Factory
// =============================================================================

const Na__ExtDoorCommon__DxfExporter = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | DXF Primitive Writers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Emit a DXF LINE Entity
    // ------------------------------------------------------------
    function na_line(layer, x1, y1, x2, y2) {
        return '0\nLINE\n8\n' + layer +
            '\n10\n' + x1 + '\n20\n' + y1 +
            '\n11\n' + x2 + '\n21\n' + y2 + '\n';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Emit Four LINE Entities Forming a Rectangle
    // ------------------------------------------------------------
    function na_rect(layer, x, y, width, height) {
        if (width <= 0 || height <= 0) return '';
        return na_line(layer, x, y, x + width, y) +
            na_line(layer, x + width, y, x + width, y + height) +
            na_line(layer, x + width, y + height, x, y + height) +
            na_line(layer, x, y + height, x, y);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Emit a DXF CIRCLE Entity
    // ------------------------------------------------------------
    function na_circle(layer, x, y, radius) {
        return '0\nCIRCLE\n8\n' + layer +
            '\n10\n' + x + '\n20\n' + y +
            '\n40\n' + radius + '\n';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Emit a DXF TEXT Entity
    // ------------------------------------------------------------
    function na_text(layer, x, y, height, text) {
        return '0\nTEXT\n8\n' + layer +
            '\n10\n' + x + '\n20\n' + y +
            '\n40\n' + height + '\n1\n' + text + '\n';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Emit a DXF ARC Entity (Normalises Negative Sweep)
    // ------------------------------------------------------------
    function na_arc(layer, x, y, radius, startAngle, sweepAngle) {
        let endAngle = startAngle + sweepAngle;
        if (sweepAngle < 0) {
            const swap = startAngle;
            startAngle = endAngle;
            endAngle   = swap;
        }
        const startNorm = ((startAngle % 360) + 360) % 360;
        const endNorm   = ((endAngle % 360) + 360) % 360;
        return '0\nARC\n8\n' + layer +
            '\n10\n' + x + '\n20\n' + y +
            '\n40\n' + radius +
            '\n50\n' + startNorm +
            '\n51\n' + endNorm + '\n';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Rotate a Point Around a Pivot by Angle (deg)
    // ------------------------------------------------------------
    function na_rotate(point, pivot, angleDeg) {
        const radians = angleDeg * Math.PI / 180;
        const dx = point.x - pivot.x;
        const dy = point.y - pivot.y;
        return {
            x: pivot.x + dx * Math.cos(radians) - dy * Math.sin(radians),
            y: pivot.y + dx * Math.sin(radians) + dy * Math.cos(radians)
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Glaze Bar Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Glazebar Removal Key Matching Elevation Preview
    // ------------------------------------------------------------
    function na_glazebar_key(leaf, orientation, barIndex) {
        return '0:0:' + (leaf.index - 1) + ':0:' + orientation + ':' + barIndex;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Compute Even / Margin Bar Positions
    // ------------------------------------------------------------
    function na_bar_positions(start, size, count, marginEnabled, marginOffset) {
        const math = window.Na__GlazebarMath;
        if (math && typeof math.na_computeBarPositions === 'function') {
            return math.na_computeBarPositions(start, size, count, marginEnabled, marginOffset);
        }
        const positions = [];
        for (let index = 1; index <= count; index += 1) {
            positions.push(start + size * index / (count + 1));
        }
        return positions;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Apply Per-Bar Offset Nudges After Spacing
    // ------------------------------------------------------------
    // Positive = up for horizontal bars, right for vertical bars -
    // matching the elevation preview.
    function na_apply_offsets(positions, offsets) {
        const math = window.Na__GlazebarMath;
        if (math && typeof math.na_applyBarOffsets === 'function') {
            return math.na_applyBarOffsets(positions, offsets);
        }
        return positions;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Cill Lift Applied Under Elevation Geometry
    // ------------------------------------------------------------
    function na_elevation_lift(config, resolved) {
        return config.has_cill !== false && resolved.dimensions.frameBottomMm > 0
            ? Math.max(0, Number(config.cill_height_mm || 50))
            : 0;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Append Frame and Optional Cill Elevation Entities
    // ------------------------------------------------------------
    function na_add_frame(config, resolved, lift) {
        const dimensions = resolved.dimensions;
        let dxf = '';
        dxf += na_rect('NA_FRAME', 0, lift, dimensions.frameLeftMm, dimensions.heightMm);
        dxf += na_rect(
            'NA_FRAME',
            dimensions.widthMm - dimensions.frameRightMm,
            lift,
            dimensions.frameRightMm,
            dimensions.heightMm
        );
        dxf += na_rect(
            'NA_FRAME',
            dimensions.frameLeftMm,
            lift,
            dimensions.innerWidthMm,
            dimensions.frameBottomMm
        );
        dxf += na_rect(
            'NA_FRAME',
            dimensions.frameLeftMm,
            dimensions.heightMm - dimensions.frameTopMm + lift,
            dimensions.innerWidthMm,
            dimensions.frameTopMm
        );
        if (config.has_cill !== false && dimensions.frameBottomMm > 0) {
            const cillHeight = Math.max(0, Number(config.cill_height_mm || 50));
            dxf += na_rect('NA_CILL', 0, -cillHeight + lift, dimensions.widthMm, cillHeight);
        }
        return dxf;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Exporter Factory
    // -----------------------------------------------------------------------------

    // FUNCTION | Build a Prefix-Bound DXF Exporter
    // ------------------------------------------------------------
    function na_create(spec) {
        const prefix = String(spec.prefix);

        // HELPER FUNCTION | Build One Prefixed Config Key
        // ------------------------------------------------------------
        function na_key(suffix) {
            return prefix + '_' + suffix;
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Fixed-Panel Mode Predicate
        // ------------------------------------------------------------
        // Fixed panels export as dead joinery - no handle circle, no
        // open-state outline and no swing arc.
        function na_fixed_panels(config) {
            const raw = (config || {})[na_key('fixed_panels')];
            return raw === true || String(raw).toLowerCase() === 'true';
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Append Glaze Bar Lines for One Leaf Glazed Region
        // ------------------------------------------------------------
        function na_add_leaf_glazebars(config, leaf, glass, lift) {
            let dxf = '';
            const verticalPositions = na_apply_offsets(
                na_bar_positions(
                    glass.xMm, glass.widthMm, leaf.settings.verticalBars,
                    leaf.settings.marginEnabled, leaf.settings.marginOffsetMm
                ),
                leaf.settings.verticalOffsetsMm
            );
            const horizontalPositions = na_apply_offsets(
                na_bar_positions(
                    glass.zMm, glass.heightMm, leaf.settings.horizontalBars,
                    leaf.settings.marginEnabled, leaf.settings.marginOffsetMm
                ),
                leaf.settings.horizontalOffsetsMm
            );
            const removedSource = Array.isArray(config[na_key('removed_glazebars')])
                ? config[na_key('removed_glazebars')]
                : config.removed_glazebars;
            const removedBars = new Set(Array.isArray(removedSource)
                ? removedSource.map(String)
                : []);

            verticalPositions.forEach(function (vx, index) {
                if (removedBars.has(na_glazebar_key(leaf, 'vertical', index + 1))) return;
                dxf += na_line(
                    'NA_GLAZEBAR',
                    vx,
                    glass.zMm + lift,
                    vx,
                    glass.zMm + glass.heightMm + lift
                );
            });
            horizontalPositions.forEach(function (position, index) {
                if (removedBars.has(na_glazebar_key(leaf, 'horizontal', index + 1))) return;
                const hz = position + leaf.settings.horizontalOffsetMm;
                dxf += na_line(
                    'NA_GLAZEBAR',
                    glass.xMm,
                    hz + lift,
                    glass.xMm + glass.widthMm,
                    hz + lift
                );
            });
            return dxf;
        }
        // ---------------------------------------------------------------

        // FUNCTION | Append One Leaf Elevation (Rails, Fields, Glass, Handle)
        // ------------------------------------------------------------
        function na_add_leaf_elevation(config, leaf, lift) {
            const layout = leaf.panelLayout;
            let dxf = na_rect(
                'NA_DOOR_LEAF',
                leaf.originXMm,
                leaf.originZMm + lift,
                leaf.widthMm,
                leaf.heightMm
            );
            dxf += na_rect('NA_RAIL_STILE', leaf.originXMm, leaf.originZMm + lift, layout.stileMm, leaf.heightMm);
            dxf += na_rect(
                'NA_RAIL_STILE',
                leaf.originXMm + leaf.widthMm - layout.stileMm,
                leaf.originZMm + lift,
                layout.stileMm,
                leaf.heightMm
            );
            dxf += na_rect(
                'NA_RAIL_STILE',
                leaf.originXMm + layout.stileMm,
                leaf.originZMm + lift,
                leaf.widthMm - 2 * layout.stileMm,
                layout.bottomRailMm
            );
            dxf += na_rect(
                'NA_RAIL_STILE',
                leaf.originXMm + layout.stileMm,
                leaf.originZMm + leaf.heightMm - layout.topRailMm + lift,
                leaf.widthMm - 2 * layout.stileMm,
                layout.topRailMm
            );

            if (layout.fieldRegion && layout.glazedRegion) {
                dxf += na_rect(
                    'NA_RAIL_STILE',
                    layout.fieldRegion.xMm,
                    layout.fieldRegion.zMm + layout.fieldRegion.heightMm + lift,
                    layout.fieldRegion.widthMm,
                    layout.midRailMm
                );
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
                const glass = layout.glazedRegion;
                dxf += na_rect('NA_GLASS', glass.xMm, glass.zMm + lift, glass.widthMm, glass.heightMm);
                dxf += na_add_leaf_glazebars(config, leaf, glass, lift);
            }

            if (!na_fixed_panels(config) && spec.na_draw_handle_for_leaf(config, leaf)) {
                const backset = Number(config[na_key('handle_backset_mm')] || 40);
                const handleX = leaf.side === 'left'
                    ? leaf.originXMm + leaf.widthMm - backset
                    : leaf.originXMm + backset;
                dxf += na_circle(
                    'NA_DOOR_HARDWARE',
                    handleX,
                    leaf.originZMm + Number(config[na_key('handle_height_mm')] || 900) + lift,
                    12
                );
            }
            return dxf;
        }
        // ---------------------------------------------------------------

        // FUNCTION | Append One Leaf Plan Footprint, Open Copy, and Swing Arc
        // ------------------------------------------------------------
        function na_add_leaf_plan(config, leaf, offset) {
            let dxf = na_rect(
                'NA_DOOR_LEAF',
                leaf.originXMm,
                leaf.originYMm + offset,
                leaf.widthMm,
                leaf.thicknessMm
            );
            // Fixed panels export the closed footprint only - no open-state
            // outline and no swing arc.
            if (na_fixed_panels(config)) return dxf;

            const corners = [
                { x: leaf.originXMm, y: leaf.originYMm },
                { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm },
                { x: leaf.originXMm + leaf.widthMm, y: leaf.originYMm + leaf.thicknessMm },
                { x: leaf.originXMm, y: leaf.originYMm + leaf.thicknessMm }
            ];
            const pivot = { x: leaf.hingeXMm, y: leaf.pivotYMm };

            if (config[na_key('create_open_state_copy')] !== false) {
                const opened = corners.map(function (point) {
                    return na_rotate(point, pivot, leaf.signedAngleDeg);
                });
                opened.forEach(function (point, index) {
                    const following = opened[(index + 1) % opened.length];
                    dxf += na_line(
                        'NA_DOOR_SWING',
                        point.x,
                        point.y + offset,
                        following.x,
                        following.y + offset
                    );
                });
            }

            if (config[na_key('show_swing_arcs')] !== false) {
                dxf += na_arc(
                    'NA_DOOR_SWING',
                    pivot.x,
                    pivot.y + offset,
                    leaf.widthMm,
                    leaf.closedLatchAngleDeg,
                    leaf.signedAngleDeg
                );
            }
            return dxf;
        }
        // ---------------------------------------------------------------

        // FUNCTION | Build Complete DXF Entity Stream for Live Config
        // ------------------------------------------------------------
        function na_export_dxf(config) {
            const resolver = spec.na_resolver();
            if (!resolver) return '';

            const resolved      = resolver.na_resolve(config || {});
            const elevationLift = na_elevation_lift(config || {}, resolved);
            let dxf = '0\nSECTION\n2\nENTITIES\n';
            dxf += na_add_frame(config || {}, resolved, elevationLift);

            resolved.leaves.forEach(function (leaf) {
                dxf += na_add_leaf_elevation(config || {}, leaf, elevationLift);
            });

            if ((config || {}).show_dimensions !== false) {
                dxf += na_text(
                    'NA_DIMENSIONS',
                    resolved.dimensions.widthMm / 2,
                    resolved.dimensions.heightMm + 100 + elevationLift,
                    35,
                    spec.productLabel + ' ' +
                        Math.round(resolved.dimensions.widthMm) + ' x ' +
                        Math.round(resolved.dimensions.heightMm) + ' mm'
                );
                resolved.leaves.forEach(function (leaf) {
                    dxf += na_text(
                        'NA_DIMENSIONS',
                        leaf.originXMm + leaf.widthMm / 2,
                        leaf.originZMm - 80 + elevationLift,
                        25,
                        leaf.sideName + ' ' + Math.round(leaf.widthMm) + ' mm'
                    );
                });
            }

            const maximumLeafWidth = Math.max.apply(
                null,
                resolved.leaves.map(function (leaf) { return leaf.widthMm; })
            );
            const planOffset = -(maximumLeafWidth + resolved.dimensions.frameDepthMm + 300);
            resolved.leaves.forEach(function (leaf) {
                dxf += na_add_leaf_plan(config || {}, leaf, planOffset);
            });

            return dxf + '0\nENDSEC\n0\nEOF\n';
        }
        // ---------------------------------------------------------------

        return {
            na_export_dxf: na_export_dxf
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    return {
        na_create : na_create
    };

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtDoorCommon__DxfExporter = Object.freeze(Na__ExtDoorCommon__DxfExporter);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
