/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - ELEVATION SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDoorCommon__Viewport__ElevationGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Prefix-parameterised elevation SVG generator factory shared by
                every hinged exterior door product. Draws frame, each leaf
                (fielded panels + glazed regions), glaze bars, leaded glass,
                handles, and the overall / per-leaf dimension labels.
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Extracted verbatim from the Exterior Double Door elevation generator so
     the double door and the single door render from one code path and cannot
     drift apart. Only the config key prefix and the handle-visibility rule
     differ between products.
   - Layout is resolved through the product's leaf config resolver so the SVG
     matches the Ruby 3D builder and the DXF exporter.
   - Glaze-bar centre lines and leaded cell grids share na_final_bar_positions
     so the two can never disagree.
   - Click targets for glaze bars and leaded cells use the same key scheme as
     WindowSystem (opening:cell:panel:sash:...).

   SPEC CONTRACT:
     prefix                 {string}   Key prefix, no trailing underscore.
     na_resolver            {function} () -> the product leaf config resolver.
     na_draw_handle_for_leaf{function} (config, leaf) -> boolean.

   DEPENDENCIES:
   - window.Na__Viewport__SvgHelpers.na_make_svg / na_clear_svg
   - window.Na__GlazebarMath (optional shared bar math)
   - window.Na__Viewport__SvgGenerator (optional leaded colour helpers)

   ============================================================================= */


// =============================================================================
// REGION | ExtDoorCommon Elevation SVG Generator Factory
// =============================================================================

const Na__ExtDoorCommon__ElevationGenerator = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Constants
    // -----------------------------------------------------------------------------

    const NA_PADDING_MM = 180;                                                            // <-- SVG content padding
    const NA_STROKE     = '#4b4036';                                                      // <-- Frame / leaf outline
    const NA_GLASS_FILL = '#b9dcea';                                                      // <-- Glazing fill tint

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | SVG / Material Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Create SVG Element via Shared Viewport Helpers
    // ------------------------------------------------------------
    function na_svg(tag, attributes) {
        return window.Na__Viewport__SvgHelpers.na_make_svg(tag, attributes);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Look Up Material Hex from a Global Swatch Array
    // ------------------------------------------------------------
    function na_material_hex(materialId, swatchName, fallback) {
        const swatches = window[swatchName] || [];
        for (let index = 0; index < swatches.length; index += 1) {
            if (swatches[index] && swatches[index].id === materialId) {
                return swatches[index].hex || swatches[index].color || fallback;
            }
        }
        return fallback;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Append Filled Rectangle to SVG
    // ------------------------------------------------------------
    function na_rect(svg, x, y, width, height, fill, options) {
        options = options || {};
        svg.appendChild(na_svg('rect', {
            x                  : x,
            y                  : y,
            width              : Math.max(0, width),
            height             : Math.max(0, height),
            fill               : fill,
            stroke             : options.stroke || NA_STROKE,
            'stroke-width'     : options.strokeWidth || 1,
            'stroke-dasharray' : options.dash || ''
        }));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Convert Model Z (mm Up) to SVG Y (mm Down)
    // ------------------------------------------------------------
    function na_y(layout, zMm) {
        return layout.openingY + layout.heightMm - zMm;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Coerce to Boolean or Fallback
    // ------------------------------------------------------------
    function na_boolean(value, fallback) {
        if (value === undefined || value === null) return fallback;
        return value === true || String(value).toLowerCase() === 'true';
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Layout Resolution
    // -----------------------------------------------------------------------------

    // FUNCTION | Build Elevation Layout Box from Resolved Dimensions
    // ------------------------------------------------------------
    function na_layout(config, resolved) {
        const hasCill  = config.has_cill !== false && String(config.has_cill).toLowerCase() !== 'false';
        const cillLift = hasCill && resolved.dimensions.frameBottomMm > 0
            ? Math.max(0, Number(config.cill_height_mm) || 50)
            : 0;

        return {
            config      : config,
            openingX    : NA_PADDING_MM,
            openingY    : NA_PADDING_MM,
            widthMm     : resolved.dimensions.widthMm,
            heightMm    : resolved.dimensions.heightMm,
            cillLiftMm  : cillLift,
            totalWidth  : resolved.dimensions.widthMm + 2 * NA_PADDING_MM,
            totalHeight : resolved.dimensions.heightMm + cillLift + 2 * NA_PADDING_MM
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Frame Drawing
    // -----------------------------------------------------------------------------

    // FUNCTION | Draw Outer Frame Jambs, Head, Bottom, and Optional Cill
    // ------------------------------------------------------------
    function na_draw_frame(svg, layout, dimensions, palette) {
        na_rect(svg, layout.openingX, layout.openingY, dimensions.frameLeftMm, layout.heightMm, palette.frame);
        na_rect(
            svg,
            layout.openingX + layout.widthMm - dimensions.frameRightMm,
            layout.openingY,
            dimensions.frameRightMm,
            layout.heightMm,
            palette.frame
        );
        na_rect(
            svg,
            layout.openingX + dimensions.frameLeftMm,
            layout.openingY,
            dimensions.innerWidthMm,
            dimensions.frameTopMm,
            palette.frame
        );
        na_rect(
            svg,
            layout.openingX + dimensions.frameLeftMm,
            layout.openingY + layout.heightMm - dimensions.frameBottomMm,
            dimensions.innerWidthMm,
            dimensions.frameBottomMm,
            palette.frame
        );
        if (layout.cillLiftMm > 0) {
            na_rect(
                svg,
                layout.openingX,
                layout.openingY + layout.heightMm,
                layout.widthMm,
                layout.cillLiftMm,
                palette.frame
            );
        }
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Glaze Bar Math
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Evenly Spaced Bar Centre Lines (Fallback)
    // ------------------------------------------------------------
    function na_even_bar_positions(start, size, count) {
        const positions = [];
        for (let index = 1; index <= count; index += 1) {
            positions.push(start + size * index / (count + 1));
        }
        return positions;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Final Bar Centre Lines for One Leaf Glazed Region
    // ------------------------------------------------------------
    // Even / margin spacing, then the uniform horizontal offset, then the
    // per-bar offsets. Shared by the bar drawer and the leaded cell grid
    // so the two can never disagree.
    function na_final_bar_positions(leaf, region) {
        const settings = leaf.settings;
        const math     = window.Na__GlazebarMath;

        let vertical = math && typeof math.na_computeBarPositions === 'function'
            ? math.na_computeBarPositions(
                region.xMm, region.widthMm, settings.verticalBars,
                settings.marginEnabled, settings.marginOffsetMm
            )
            : na_even_bar_positions(region.xMm, region.widthMm, settings.verticalBars);

        let horizontal = math && typeof math.na_computeBarPositions === 'function'
            ? math.na_computeBarPositions(
                region.zMm, region.heightMm, settings.horizontalBars,
                settings.marginEnabled, settings.marginOffsetMm
            )
            : na_even_bar_positions(region.zMm, region.heightMm, settings.horizontalBars);

        horizontal = horizontal.map(function (position) {
            return position + settings.horizontalOffsetMm;
        });

        if (math && typeof math.na_applyBarOffsets === 'function') {
            horizontal = math.na_applyBarOffsets(horizontal, settings.horizontalOffsetsMm);
            vertical   = math.na_applyBarOffsets(vertical, settings.verticalOffsetsMm);
        }

        return { horizontal: horizontal, vertical: vertical };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Glazebar Removal / Click Key for One Leaf Bar
    // ------------------------------------------------------------
    function na_glazebar_key(leaf, orientation, barIndex) {
        return '0:0:' + (leaf.index - 1) + ':0:' + orientation + ':' + barIndex;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Append Invisible Glazebar Hit Target
    // ------------------------------------------------------------
    function na_add_glazebar_click_target(svg, x, y, width, height, leaf, orientation, barIndex) {
        const minimumHitSize = 16;
        let targetX      = x;
        let targetY      = y;
        let targetWidth  = width;
        let targetHeight = height;

        if (orientation === 'horizontal') {
            const extraHeight = Math.max(0, minimumHitSize - height);
            targetY      -= extraHeight / 2;
            targetHeight += extraHeight;
        } else {
            const extraWidth = Math.max(0, minimumHitSize - width);
            targetX     -= extraWidth / 2;
            targetWidth += extraWidth;
        }

        svg.appendChild(na_svg('rect', {
            class               : 'na-glazebar-click-target',
            'data-opening-index': 0,
            'data-cell-index'   : 0,
            'data-panel-index'  : leaf.index - 1,
            'data-sash-index'   : 0,
            'data-orientation'  : orientation,
            'data-bar-index'    : barIndex,
            x                   : targetX,
            y                   : targetY,
            width               : targetWidth,
            height              : targetHeight,
            fill                : 'rgba(0, 0, 0, 0.001)',
            stroke              : 'none',
            style               : 'cursor:pointer;pointer-events:all'
        }));
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Generator Factory
    // -----------------------------------------------------------------------------

    // FUNCTION | Build a Prefix-Bound Elevation Generator
    // ------------------------------------------------------------
    function na_create(spec) {
        const prefix = String(spec.prefix);

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
                frame  : na_material_hex(config.frame_material_id, 'NA_FRAME_FINISH_SWATCHES', '#c29b6b'),
                leaf   : na_material_hex(config[na_key('leaf_material_id')], 'NA_FRAME_FINISH_SWATCHES', '#b58a58'),
                handle : na_material_hex(config[na_key('handle_material_id')], 'NA_HANDLE_FINISH_SWATCHES', '#c0ae8a')
            };
        }
        // ---------------------------------------------------------------

        // FUNCTION | Draw Vertical and Horizontal Glaze Bars for One Leaf
        // ------------------------------------------------------------
        function na_draw_glaze_bars(svg, layout, leaf, region, palette) {
            const settings      = leaf.settings;
            const removedSource = Array.isArray(layout.config[na_key('removed_glazebars')])
                ? layout.config[na_key('removed_glazebars')]
                : layout.config.removed_glazebars;
            const removedBars = new Set(Array.isArray(removedSource)
                ? removedSource.map(String)
                : []);
            const positions = na_final_bar_positions(leaf, region);

            positions.vertical.forEach(function (x, index) {
                const barIndex = index + 1;
                const barX     = layout.openingX + x - settings.glazeBarWidthMm / 2;
                const barY     = na_y(layout, region.zMm + region.heightMm);
                if (!removedBars.has(na_glazebar_key(leaf, 'vertical', barIndex))) {
                    na_rect(svg, barX, barY, settings.glazeBarWidthMm, region.heightMm, palette.leaf);
                }
                na_add_glazebar_click_target(
                    svg, barX, barY, settings.glazeBarWidthMm, region.heightMm,
                    leaf, 'vertical', barIndex
                );
            });

            positions.horizontal.forEach(function (z, index) {
                const barIndex = index + 1;
                const barX     = layout.openingX + region.xMm;
                const barY     = na_y(layout, z + settings.glazeBarWidthMm / 2);
                if (!removedBars.has(na_glazebar_key(leaf, 'horizontal', barIndex))) {
                    na_rect(svg, barX, barY, region.widthMm, settings.glazeBarWidthMm, palette.leaf);
                }
                na_add_glazebar_click_target(
                    svg, barX, barY, region.widthMm, settings.glazeBarWidthMm,
                    leaf, 'horizontal', barIndex
                );
            });
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Draw Lead Lines Inside One Glazing Cell
        // ------------------------------------------------------------
        function na_draw_leaded_cell_lines(
            svg, layout, cellX, cellZ, cellW, cellH,
            hLeads, vLeads, stroke, centreLines, leadWidthMm
        ) {
            const math = window.Na__GlazebarMath;
            let index;

            if (hLeads > 0) {
                const hPositions = math.na_computeBarPositions(cellZ, cellH, hLeads, false, 0);
                for (index = 0; index < hPositions.length; index += 1) {
                    const z = hPositions[index];
                    if (centreLines) {
                        svg.appendChild(na_svg('line', {
                            x1: layout.openingX + cellX,
                            y1: na_y(layout, z),
                            x2: layout.openingX + cellX + cellW,
                            y2: na_y(layout, z),
                            stroke: stroke,
                            'stroke-width': 1
                        }));
                    } else {
                        na_rect(
                            svg,
                            layout.openingX + cellX,
                            na_y(layout, z + leadWidthMm / 2),
                            cellW,
                            leadWidthMm,
                            stroke,
                            { stroke: stroke, strokeWidth: 0.4 }
                        );
                    }
                }
            }

            if (vLeads > 0) {
                const vPositions = math.na_computeBarPositions(cellX, cellW, vLeads, false, 0);
                for (index = 0; index < vPositions.length; index += 1) {
                    const x = vPositions[index];
                    if (centreLines) {
                        svg.appendChild(na_svg('line', {
                            x1: layout.openingX + x,
                            y1: na_y(layout, cellZ),
                            x2: layout.openingX + x,
                            y2: na_y(layout, cellZ + cellH),
                            stroke: stroke,
                            'stroke-width': 1
                        }));
                    } else {
                        na_rect(
                            svg,
                            layout.openingX + x - leadWidthMm / 2,
                            na_y(layout, cellZ + cellH),
                            leadWidthMm,
                            cellH,
                            stroke,
                            { stroke: stroke, strokeWidth: 0.4 }
                        );
                    }
                }
            }
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Append Invisible Leaded-Cell Hit Target
        // ------------------------------------------------------------
        function na_add_leaded_cell_click_target(svg, layout, cellX, cellZ, cellW, cellH, leaf, col, row) {
            const inset   = 4;
            const targetW = cellW - inset * 2;
            const targetH = cellH - inset * 2;
            if (targetW <= 0 || targetH <= 0) return;

            svg.appendChild(na_svg('rect', {
                class               : 'na-leaded-cell-click-target',
                'data-opening-index': 0,
                'data-cell-index'   : 0,
                'data-panel-index'  : leaf.index - 1,
                'data-sash-index'   : 0,
                'data-col'          : col,
                'data-row'          : row,
                x                   : layout.openingX + cellX + inset,
                y                   : na_y(layout, cellZ + cellH - inset),
                width               : targetW,
                height              : targetH,
                fill                : 'rgba(0, 0, 0, 0.001)',
                stroke              : 'none',
                style               : 'cursor:pointer;pointer-events:all'
            }));
        }
        // ---------------------------------------------------------------

        // FUNCTION | Draw Leaded Glass Per Glazing Cell (Between Glaze Bars)
        // ------------------------------------------------------------
        // Lead lines are laid out inside each cell of the glaze bar grid,
        // matching the WindowSystem SVG generator and the Ruby 3D builder.
        // Each cell gets a whole-cell click target so the user can toggle
        // its leaded glass off/on directly in the preview.
        function na_draw_leaded_glass(svg, layout, leaf, region) {
            const config = layout.config || {};
            if (config.leaded_glass_enabled !== true) return;

            const hLeads = Math.max(0, Math.min(10, Math.round(Number(config.horizontal_leaded_bars || 0))));
            const vLeads = Math.max(0, Math.min(8, Math.round(Number(config.vertical_leaded_bars || 0))));
            if (hLeads <= 0 && vLeads <= 0) return;
            if (region.widthMm <= 0 || region.heightMm <= 0) return;

            const math = window.Na__GlazebarMath;
            if (!math || typeof math.na_computeCellBounds !== 'function') return;

            const svgGen = window.Na__Viewport__SvgGenerator;
            let stroke = '#999999';
            if (svgGen && typeof svgGen.na_leadedColourHex === 'function') {
                stroke = svgGen.na_leadedColourHex(
                    typeof svgGen.na_resolveLeadedColourId === 'function'
                        ? svgGen.na_resolveLeadedColourId(config)
                        : config.edge_colour_leaded_id
                );
            }

            const centreLines = config.leaded_centre_lines_only === true;
            const leadWidthMm = Math.max(2, Number(config.leaded_width_mm || 6));
            const disabledSource = Array.isArray(config[na_key('leaded_disabled_cells')])
                ? config[na_key('leaded_disabled_cells')]
                : config.leaded_disabled_cells;
            const disabledCells = new Set(Array.isArray(disabledSource)
                ? disabledSource.map(String)
                : []);

            const positions    = na_final_bar_positions(leaf, region);
            const barWidth     = leaf.settings.glazeBarWidthMm;
            const columnBounds = math.na_computeCellBounds(region.xMm, region.widthMm, positions.vertical, barWidth);
            const rowBounds    = math.na_computeCellBounds(region.zMm, region.heightMm, positions.horizontal, barWidth);

            for (let row = 0; row < rowBounds.length; row += 1) {
                for (let col = 0; col < columnBounds.length; col += 1) {
                    const cellX = columnBounds[col].start;
                    const cellW = columnBounds[col].size;
                    const cellZ = rowBounds[row].start;
                    const cellH = rowBounds[row].size;
                    if (cellW <= 0 || cellH <= 0) continue;

                    const cellKey = '0:0:' + (leaf.index - 1) + ':0:' + col + ':' + row;
                    if (!disabledCells.has(cellKey)) {
                        na_draw_leaded_cell_lines(
                            svg, layout, cellX, cellZ, cellW, cellH,
                            hLeads, vLeads, stroke, centreLines, leadWidthMm
                        );
                    }
                    na_add_leaded_cell_click_target(svg, layout, cellX, cellZ, cellW, cellH, leaf, col, row);
                }
            }
        }
        // ---------------------------------------------------------------

        // FUNCTION | Draw Schematic Scroll Handle on One Leaf
        // ------------------------------------------------------------
        // The handle sits `backset` in from the latch stile - the meeting
        // stile on a double door, the closing stile on a single door - and
        // the scroll curls back toward that same edge.
        function na_draw_handle(svg, layout, leaf, palette) {
            const backset = Number(layout.config[na_key('handle_backset_mm')]) || 40;
            const height  = Number(layout.config[na_key('handle_height_mm')]) || 900;
            const x = leaf.side === 'left'
                ? layout.openingX + leaf.originXMm + leaf.widthMm - backset
                : layout.openingX + leaf.originXMm + backset;
            const y = na_y(layout, leaf.originZMm + height);
            // Scroll hangs down; curl toward the latch stile (left-hung -> +X, right-hung -> -X)
            const towardLatch = leaf.side === 'left' ? 1 : -1;
            const fill = palette.handle || '#6e6558';

            svg.appendChild(na_svg('circle', {
                cx: x, cy: y, r: 10, fill: fill, stroke: NA_STROKE, 'stroke-width': 1.5
            }));
            // Stem + scroll tip (schematic - Scroll asset has no Elevation2D paths yet)
            svg.appendChild(na_svg('path', {
                d: [
                    'M', x, y + 8,
                    'C', x + towardLatch * 6, y + 28,
                    x + towardLatch * 34, y + 48,
                    x + towardLatch * 10, y + 72
                ].join(' '),
                fill            : 'none',
                stroke          : fill,
                'stroke-width'  : 7,
                'stroke-linecap': 'round'
            }));
            svg.appendChild(na_svg('path', {
                d: [
                    'M', x + towardLatch * 10, y + 72,
                    'C', x + towardLatch * -4, y + 86,
                    x + towardLatch * 18, y + 92,
                    x + towardLatch * 8, y + 78
                ].join(' '),
                fill            : 'none',
                stroke          : NA_STROKE,
                'stroke-width'  : 2.5,
                'stroke-linecap': 'round'
            }));
        }
        // ---------------------------------------------------------------

        // FUNCTION | Draw One Leaf Body, Field Cells, Glazing, and Handle
        // ------------------------------------------------------------
        function na_draw_leaf(svg, layout, leaf, palette) {
            const panel = leaf.panelLayout;
            const x     = layout.openingX + leaf.originXMm;
            const top   = na_y(layout, leaf.originZMm + leaf.heightMm);
            na_rect(svg, x, top, leaf.widthMm, leaf.heightMm, palette.leaf);

            if (panel.glazedRegion) {
                const glazed = panel.glazedRegion;
                na_rect(
                    svg,
                    layout.openingX + glazed.xMm,
                    na_y(layout, glazed.zMm + glazed.heightMm),
                    glazed.widthMm,
                    glazed.heightMm,
                    NA_GLASS_FILL
                );
                na_draw_leaded_glass(svg, layout, leaf, glazed);
                na_draw_glaze_bars(svg, layout, leaf, glazed, palette);
            }

            panel.fieldCells.forEach(function (cell) {
                const inset = Math.min(leaf.settings.insetMm, cell.widthMm / 3, cell.heightMm / 3);
                const fill  = leaf.settings.outputMode === 'Linework' ? 'none' : palette.leaf;
                na_rect(
                    svg,
                    layout.openingX + cell.xMm + inset,
                    na_y(layout, cell.zMm + cell.heightMm - inset),
                    cell.widthMm - 2 * inset,
                    cell.heightMm - 2 * inset,
                    fill,
                    { strokeWidth: leaf.settings.outputMode === 'Linework' ? 1 : 3 }
                );
                if (leaf.settings.outputMode === 'ThreeDimensional' && leaf.settings.profile === 'RaisedBevelled') {
                    const bevel = Math.min(leaf.settings.bevelMm, inset);
                    na_rect(
                        svg,
                        layout.openingX + cell.xMm + bevel,
                        na_y(layout, cell.zMm + cell.heightMm - bevel),
                        cell.widthMm - 2 * bevel,
                        cell.heightMm - 2 * bevel,
                        'none',
                        { strokeWidth: 1 }
                    );
                }
            });

            if (spec.na_draw_handle_for_leaf(layout.config || {}, leaf)) {
                na_draw_handle(svg, layout, leaf, palette);
            }
        }
        // ---------------------------------------------------------------

        // FUNCTION | Draw Overall and Per-Leaf Width Labels
        // ------------------------------------------------------------
        function na_draw_dimensions(svg, layout, resolved) {
            const overall = na_svg('text', {
                x: layout.openingX + layout.widthMm / 2,
                y: layout.openingY - 45,
                fill: '#333',
                'text-anchor': 'middle',
                'font-size': 34
            });
            overall.textContent = 'W: ' + Math.round(layout.widthMm) + 'mm  H: ' + Math.round(layout.heightMm) + 'mm';
            svg.appendChild(overall);

            resolved.leaves.forEach(function (leaf) {
                const text = na_svg('text', {
                    x: layout.openingX + leaf.originXMm + leaf.widthMm / 2,
                    y: layout.openingY + layout.heightMm + layout.cillLiftMm + 50,
                    fill: '#333',
                    'text-anchor': 'middle',
                    'font-size': 28
                });
                text.textContent = leaf.sideName + ': ' + Math.round(leaf.widthMm) + 'mm';
                svg.appendChild(text);
            });
        }
        // ---------------------------------------------------------------

        // FUNCTION | Render Full Elevation into an Existing SVG Element
        // ------------------------------------------------------------
        function na_render(svgElement, config) {
            const resolver = spec.na_resolver();
            if (!svgElement || !resolver) return;
            window.Na__Viewport__SvgHelpers.na_clear_svg(svgElement);
            const resolved = resolver.na_resolve(config || {});
            const layout   = na_layout(config || {}, resolved);
            const palette  = na_palette(config || {});
            na_draw_frame(svgElement, layout, resolved.dimensions, palette);
            resolved.leaves.forEach(function (leaf) {
                na_draw_leaf(svgElement, layout, leaf, palette);
            });
            if ((config || {}).show_dimensions !== false) {
                na_draw_dimensions(svgElement, layout, resolved);
            }
        }
        // ---------------------------------------------------------------

        // FUNCTION | Compute Content Bounding Box for Viewport Fit
        // ------------------------------------------------------------
        function na_fit_to_content(config) {
            const resolver = spec.na_resolver();
            if (!resolver) return { x: 0, y: 0, width: 1000, height: 1000 };
            const resolved = resolver.na_resolve(config || {});
            const layout   = na_layout(config || {}, resolved);
            return { x: 0, y: 0, width: layout.totalWidth, height: layout.totalHeight };
        }
        // ---------------------------------------------------------------

        return {
            na_render         : na_render,
            na_fit_to_content : na_fit_to_content
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    return {
        na_create               : na_create,
        na_final_bar_positions  : na_final_bar_positions,
        na_glazebar_key         : na_glazebar_key,
        na_boolean              : na_boolean
    };

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtDoorCommon__ElevationGenerator = Object.freeze(Na__ExtDoorCommon__ElevationGenerator);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
