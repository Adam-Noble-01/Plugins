/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - DXF EXPORT (JS FALLBACK)
   =============================================================================
   
   FILE       : Na__AssemblyStudio__WindowSystem__UiSystem__Export__Dxf__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : DXF file generation for CAD export
   CREATED    : 2026
   
   DESCRIPTION:
   - Generates simplified DXF format for browser-side export fallback
   - Note: Full DXF generation with proper layers and detail happens Ruby-side
   - This provides basic export capability for testing outside SketchUp
   - Generates LINE entities for frame and opening
   
   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Export__Dxf object
   
   ============================================================================= */

// =============================================================================
// REGION | DXF Export Module
// =============================================================================

const Na__Export__Dxf = (function() {

    // FUNCTION | Resolve Effective Frame Thicknesses
    // ------------------------------------------------------------
    function na_getEffectiveFrameThicknesses(config) {
        if (window.Na_DynamicUI && typeof window.Na_DynamicUI.na_getEffectiveFrameThicknesses === 'function') {
            return window.Na_DynamicUI.na_getEffectiveFrameThicknesses(config);
        }

        const uniformThickness = (config.frame_thickness_mm != null) ? Number(config.frame_thickness_mm) : 50;
        const useAdvancedFrameControls = config.advanced_frame_controls === true;

        function na_resolveFrameSideThickness(sideKey) {
            const rawValue = useAdvancedFrameControls ? config[sideKey] : uniformThickness;
            return Math.max(0, Number(rawValue != null ? rawValue : uniformThickness));
        }

        return {
            top: na_resolveFrameSideThickness('frame_top_thickness_mm'),
            bottom: na_resolveFrameSideThickness('frame_bottom_thickness_mm'),
            left: na_resolveFrameSideThickness('frame_left_thickness_mm'),
            right: na_resolveFrameSideThickness('frame_right_thickness_mm')
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Glaze Bar Storage Key
    // ------------------------------------------------------------
    function na_getGlazebarKey(openingIndex, cellIndex, panelIndex, sashIndex, orientation, barIndex) {
        return `${openingIndex}:${cellIndex}:${panelIndex}:${sashIndex}:${orientation}:${barIndex}`;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Removed Glaze Bar Set
    // ------------------------------------------------------------
    function na_getRemovedGlazebarSet(removedGlazebars) {
        return new Set(Array.isArray(removedGlazebars) ? removedGlazebars.map(key => String(key)) : []);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Removed Casement Set With Legacy Bare-Integer Support
    // ------------------------------------------------------------
    // Mirrors Na__Viewport__SvgGenerator.na_getRemovedCasementSet but kept local
    // to avoid hard coupling between modules. Returns { keys, legacyOpenings }.
    function na_getRemovedCasementSetForDxf(removedCasements) {
        const generator = window.Na__Viewport__SvgGenerator;
        if (generator && typeof generator.na_getRemovedCasementSet === 'function') {
            return generator.na_getRemovedCasementSet(removedCasements);  // <-- Reuse SVG generator helper when available
        }

        const keySet = new Set();
        const legacyOpeningSet = new Set();
        if (!Array.isArray(removedCasements)) return { keys: keySet, legacyOpenings: legacyOpeningSet };

        removedCasements.forEach(entry => {
            if (entry === null || entry === undefined) return;
            const stringValue = String(entry);
            if (stringValue.indexOf(':') !== -1) {
                keySet.add(stringValue);
                return;
            }
            const numericValue = Number(stringValue);
            if (Number.isFinite(numericValue) && numericValue >= 0) {
                legacyOpeningSet.add(Math.trunc(numericValue));
            }
        });

        return { keys: keySet, legacyOpenings: legacyOpeningSet };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Check Panel Casement Removal
    // ------------------------------------------------------------
    function na_isPanelCasementRemovedForDxf(removedSet, openingIndex, cellIndex, panelIndex) {
        const generator = window.Na__Viewport__SvgGenerator;
        if (generator && typeof generator.na_isPanelCasementRemoved === 'function') {
            return generator.na_isPanelCasementRemoved(removedSet, openingIndex, cellIndex, panelIndex);
        }

        if (!removedSet) return false;
        if (removedSet.legacyOpenings && removedSet.legacyOpenings.has(openingIndex)) return true;
        if (removedSet.keys && removedSet.keys.has(`${openingIndex}:${cellIndex}:${panelIndex}`)) return true;
        return false;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Export Current Model as DXF (Browser Fallback)
    // ------------------------------------------------------------
    // @param {Object} config - Window configuration object
    // @returns {string} DXF file content as string
    function na_exportDxf(config) {
        let dxf = '0\nSECTION\n2\nENTITIES\n';

        const width = config.width_mm || 900;
        const height = config.height_mm || 1200;
        const frameThicknesses = na_getEffectiveFrameThicknesses(config);
        const topFrameThickness = frameThicknesses.top;
        const bottomFrameThickness = frameThicknesses.bottom;
        const leftFrameThickness = frameThicknesses.left;
        const rightFrameThickness = frameThicknesses.right;
        const casementWidth = config.casement_width_mm || 65;
        const showCasements = config.show_casements !== false;
        const slidingSashWindow = config.sliding_sash_window === true;
        const slidingSashOverlap = Math.max(0, Math.min(60, config.sliding_sash_overlap_mm || 20));
        const casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const transomCount = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        const transomWidth = config.transom_width_mm || 40;
        const transomBottoms = na_getActiveTransomBottoms(config, transomCount);
        const removedTransomSegments = na_getRemovedTransomSegmentSet(config.removed_transom_segments);
        const removedGlazebars = na_getRemovedGlazebarSet(config.removed_glazebars);
        const hBars = config.horizontal_glaze_bars || 0;
        const vBars = config.vertical_glaze_bars || 0;
        const barWidth = config.glaze_bar_width_mm || 25;
        const removedCasementSet = na_getRemovedCasementSetForDxf(config.removed_casements); // <-- Per-panel removal lookup with legacy support

        const useIndividualSizes = config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const casLeftStile = useIndividualSizes ? (config.casement_left_stile_mm || casementWidth) : casementWidth;
        const casRightStile = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;

        const numOpenings = numMullions + 1;
        const innerWidth = width - leftFrameThickness - rightFrameThickness;
        const innerHeight = height - topFrameThickness - bottomFrameThickness;
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        const openingWidth = availableWidth / numOpenings;

        // Outer frame (skip in frameless mode)
        if (leftFrameThickness > 0) {
            dxf += na_dxfRect(0, 0, leftFrameThickness, height);
        }
        if (rightFrameThickness > 0) {
            dxf += na_dxfRect(width - rightFrameThickness, 0, rightFrameThickness, height);
        }
        if (bottomFrameThickness > 0) {
            dxf += na_dxfRect(leftFrameThickness, 0, innerWidth, bottomFrameThickness);
        }
        if (topFrameThickness > 0) {
            dxf += na_dxfRect(leftFrameThickness, height - topFrameThickness, innerWidth, topFrameThickness);
        }

        // Mullions
        for (let m = 1; m <= numMullions; m++) {
            const mullionX = leftFrameThickness + (m * openingWidth) + ((m - 1) * mullionWidth);
            dxf += na_dxfRect(mullionX, bottomFrameThickness, mullionWidth, innerHeight);
        }

        // Openings
        for (let i = 0; i < numOpenings; i++) {
            const openingX = leftFrameThickness + (i * (openingWidth + mullionWidth));
            const openingY = bottomFrameThickness;
            const openingLayout = na_getOpeningCellLayout(
                i,
                openingX,
                openingY,
                openingWidth,
                innerHeight,
                transomBottoms,
                transomWidth,
                removedTransomSegments
            );

            openingLayout.transomSegments.forEach(segment => {
                dxf += na_dxfRect(segment.x, segment.y, segment.width, segment.height);
            });

            openingLayout.cells.forEach((cell, cellIndex) => {
                const panelWidth = cell.width / casementsPerOpening;

                for (let p = 0; p < casementsPerOpening; p++) {
                    const panelX = cell.x + (p * panelWidth);
                    const panelHasCasement = showCasements && !na_isPanelCasementRemovedForDxf( // <-- Per-panel casement state
                        removedCasementSet,
                        i,
                        cellIndex,
                        p
                    );

                    if (panelHasCasement) {
                        if (slidingSashWindow) {
                            dxf += na_generateSlidingSashPanelDxf(
                                panelX, cell.y, panelWidth, cell.height,
                                casTopRail, casBottomRail, casLeftStile, casRightStile,
                                hBars, vBars, barWidth, slidingSashOverlap,
                                { openingIndex: i, cellIndex: cellIndex, panelIndex: p },
                                removedGlazebars
                            );
                        } else {
                            dxf += na_generateCasementDxf(
                                panelX, cell.y, panelWidth, cell.height,
                                casTopRail, casBottomRail, casLeftStile, casRightStile,
                                hBars, vBars, barWidth,
                                { openingIndex: i, cellIndex: cellIndex, panelIndex: p, sashIndex: 0 },
                                removedGlazebars
                            );
                        }
                    } else {
                        dxf += na_generateDirectGlazedDxf(
                            panelX,
                            cell.y,
                            panelWidth,
                            cell.height,
                            hBars,
                            vBars,
                            barWidth,
                            { openingIndex: i, cellIndex: cellIndex, panelIndex: p, sashIndex: 0 },
                            removedGlazebars
                        );
                    }
                }
            });
        }

        dxf += '0\nENDSEC\n0\nEOF\n';
        return dxf;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Casement DXF
    // ------------------------------------------------------------
    function na_generateCasementDxf(x, y, width, height, topRail, bottomRail, leftStile, rightStile, hBars, vBars, barWidth, panelContext, removedGlazebars) {
        let dxf = '';

        dxf += na_dxfRect(x, y, leftStile, height);
        dxf += na_dxfRect(x + width - rightStile, y, rightStile, height);
        dxf += na_dxfRect(x + leftStile, y, width - leftStile - rightStile, bottomRail);
        dxf += na_dxfRect(x + leftStile, y + height - topRail, width - leftStile - rightStile, topRail);

        const glassX = x + leftStile;
        const glassY = y + bottomRail;
        const glassWidth = width - leftStile - rightStile;
        const glassHeight = height - topRail - bottomRail;

        dxf += na_dxfRect(glassX, glassY, glassWidth, glassHeight);
        dxf += na_generateGlazeBarDxf(glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, panelContext, removedGlazebars);

        return dxf;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Direct-Glazed DXF
    // ------------------------------------------------------------
    function na_generateDirectGlazedDxf(x, y, width, height, hBars, vBars, barWidth, panelContext, removedGlazebars) {
        let dxf = '';
        dxf += na_dxfRect(x, y, width, height);
        dxf += na_generateGlazeBarDxf(x, y, width, height, hBars, vBars, barWidth, panelContext, removedGlazebars);
        return dxf;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Glaze Bars in Glass Area
    // ------------------------------------------------------------
    function na_generateGlazeBarDxf(glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, panelContext, removedGlazebars) {
        let dxf = '';

        if (hBars > 0) {
            const sectionHeight = glassHeight / (hBars + 1);
            for (let b = 1; b <= hBars; b++) {
                const barKey = na_getGlazebarKey(
                    panelContext.openingIndex,
                    panelContext.cellIndex,
                    panelContext.panelIndex,
                    panelContext.sashIndex,
                    'horizontal',
                    b
                );
                if (removedGlazebars.has(barKey)) continue;

                const barY = glassY + (sectionHeight * b) - (barWidth / 2);
                dxf += na_dxfRect(glassX, barY, glassWidth, barWidth);
            }
        }

        if (vBars > 0) {
            const sectionWidth = glassWidth / (vBars + 1);
            for (let b = 1; b <= vBars; b++) {
                const barKey = na_getGlazebarKey(
                    panelContext.openingIndex,
                    panelContext.cellIndex,
                    panelContext.panelIndex,
                    panelContext.sashIndex,
                    'vertical',
                    b
                );
                if (removedGlazebars.has(barKey)) continue;

                const barX = glassX + (sectionWidth * b) - (barWidth / 2);
                dxf += na_dxfRect(barX, glassY, barWidth, glassHeight);
            }
        }

        return dxf;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sliding Sash Panel DXF
    // ------------------------------------------------------------
    function na_generateSlidingSashPanelDxf(x, y, width, height, topRail, bottomRail, leftStile, rightStile, hBars, vBars, barWidth, overlapMm, panelContext, removedGlazebars) {
        const sashHeight = height / 2;
        const sashOverlap = Math.max(0, Math.min(overlapMm || 0, sashHeight - 1));

        let dxf = '';
        dxf += na_generateCasementDxf(
            x, y, width, sashHeight + sashOverlap,
            topRail, bottomRail, leftStile, rightStile,
            hBars, vBars, barWidth,
            {
                openingIndex: panelContext.openingIndex,
                cellIndex: panelContext.cellIndex,
                panelIndex: panelContext.panelIndex,
                sashIndex: 1
            },
            removedGlazebars
        );
        dxf += na_generateCasementDxf(
            x, y + sashHeight, width, sashHeight,
            topRail, bottomRail, leftStile, rightStile,
            hBars, vBars, barWidth,
            {
                openingIndex: panelContext.openingIndex,
                cellIndex: panelContext.cellIndex,
                panelIndex: panelContext.panelIndex,
                sashIndex: 0
            },
            removedGlazebars
        );

        return dxf;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Get Active Transom Heights
    // ------------------------------------------------------------
    function na_getActiveTransomBottoms(config, transomCount) {
        return [
            Number(config.transom_1_y_mm || 0),
            Number(config.transom_2_y_mm || 0),
            Number(config.transom_3_y_mm || 0)
        ].slice(0, transomCount);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Removed Transom Segment Set
    // ------------------------------------------------------------
    function na_getRemovedTransomSegmentSet(removedSegments) {
        return new Set(Array.isArray(removedSegments) ? removedSegments.map(segment => String(segment)) : []);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build Opening Cell Layout
    // ------------------------------------------------------------
    function na_getOpeningCellLayout(openingIndex, openingX, openingY, openingWidth, innerHeight, transomBottoms, transomWidth, removedSegments) {
        const cells = [];
        const transomSegments = [];
        let cellBottom = 0;

        transomBottoms.forEach((transomBottom, transomIndex) => {
            if (removedSegments.has(`${openingIndex}:${transomIndex}`)) {
                return;
            }

            const cellHeight = transomBottom - cellBottom;
            if (cellHeight > 0) {
                cells.push({
                    x: openingX,
                    y: openingY + cellBottom,
                    width: openingWidth,
                    height: cellHeight
                });
            }

            transomSegments.push({
                x: openingX,
                y: openingY + transomBottom,
                width: openingWidth,
                height: transomWidth
            });

            cellBottom = transomBottom + transomWidth;
        });

        const topCellHeight = innerHeight - cellBottom;
        if (topCellHeight > 0) {
            cells.push({
                x: openingX,
                y: openingY + cellBottom,
                width: openingWidth,
                height: topCellHeight
            });
        }

        return { cells, transomSegments };
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate DXF Rectangle
    // ------------------------------------------------------------
    // @param {number} x - Left X coordinate
    // @param {number} y - Bottom Y coordinate
    // @param {number} w - Width
    // @param {number} h - Height
    // @returns {string} DXF LINE entities forming a rectangle
    function na_dxfRect(x, y, w, h) {
        if (w <= 0 || h <= 0) return '';

        const x1 = x;
        const y1 = y;
        const x2 = x + w;
        const y2 = y + h;

        return `0\nLINE\n8\n0\n10\n${x1}\n20\n${y1}\n11\n${x2}\n21\n${y1}\n` +
               `0\nLINE\n8\n0\n10\n${x2}\n20\n${y1}\n11\n${x2}\n21\n${y2}\n` +
               `0\nLINE\n8\n0\n10\n${x2}\n20\n${y2}\n11\n${x1}\n21\n${y2}\n` +
               `0\nLINE\n8\n0\n10\n${x1}\n20\n${y2}\n11\n${x1}\n21\n${y1}\n`;
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_exportDxf: na_exportDxf,
        na_dxfRect: na_dxfRect,
        na_generateCasementDxf: na_generateCasementDxf,
        na_generateSlidingSashPanelDxf: na_generateSlidingSashPanelDxf
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Export__Dxf = Na__Export__Dxf;

console.log('[NA_EXPORT_DXF] DXF Export module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
