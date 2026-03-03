/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - DXF EXPORT
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__Export__Dxf__.js
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
    
    // FUNCTION | Export Current Model as DXF (Browser Fallback)
    // ------------------------------------------------------------
    // @param {Object} config - Window configuration object
    // @returns {string} DXF file content as string
    function na_exportDxf(config) {
        let dxf = '0\nSECTION\n2\nENTITIES\n';

        const width = config.width_mm || 900;
        const height = config.height_mm || 1200;
        const frameThickness = config.frame_thickness_mm || 0;
        const casementWidth = config.casement_width_mm || 65;
        const showCasements = config.show_casements !== false;
        const slidingSashWindow = config.sliding_sash_window === true;
        const slidingSashOverlap = Math.max(0, Math.min(60, config.sliding_sash_overlap_mm || 20));
        const casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const hBars = config.horizontal_glaze_bars || 0;
        const vBars = config.vertical_glaze_bars || 0;
        const barWidth = config.glaze_bar_width_mm || 25;

        const useIndividualSizes = config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const casLeftStile = useIndividualSizes ? (config.casement_left_stile_mm || casementWidth) : casementWidth;
        const casRightStile = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;

        const numOpenings = numMullions + 1;
        const innerWidth = width - (2 * frameThickness);
        const innerHeight = height - (2 * frameThickness);
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        const openingWidth = availableWidth / numOpenings;

        // Outer frame (skip in frameless mode)
        if (frameThickness > 0) {
            dxf += na_dxfRect(0, 0, frameThickness, height);
            dxf += na_dxfRect(width - frameThickness, 0, frameThickness, height);
            dxf += na_dxfRect(frameThickness, 0, innerWidth, frameThickness);
            dxf += na_dxfRect(frameThickness, height - frameThickness, innerWidth, frameThickness);
        }

        // Mullions
        for (let m = 1; m <= numMullions; m++) {
            const mullionX = frameThickness + (m * openingWidth) + ((m - 1) * mullionWidth);
            dxf += na_dxfRect(mullionX, frameThickness, mullionWidth, innerHeight);
        }

        // Openings
        for (let i = 0; i < numOpenings; i++) {
            const openingX = frameThickness + (i * (openingWidth + mullionWidth));
            const openingY = frameThickness;
            const panelWidth = openingWidth / casementsPerOpening;

            for (let p = 0; p < casementsPerOpening; p++) {
                const panelX = openingX + (p * panelWidth);

                if (showCasements) {
                    if (slidingSashWindow) {
                        dxf += na_generateSlidingSashPanelDxf(
                            panelX, openingY, panelWidth, innerHeight,
                            casTopRail, casBottomRail, casLeftStile, casRightStile,
                            hBars, vBars, barWidth, slidingSashOverlap
                        );
                    } else {
                        dxf += na_generateCasementDxf(
                            panelX, openingY, panelWidth, innerHeight,
                            casTopRail, casBottomRail, casLeftStile, casRightStile,
                            hBars, vBars, barWidth
                        );
                    }
                } else {
                    dxf += na_dxfRect(panelX, openingY, panelWidth, innerHeight);
                }
            }
        }

        dxf += '0\nENDSEC\n0\nEOF\n';
        return dxf;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Casement DXF
    // ------------------------------------------------------------
    function na_generateCasementDxf(x, y, width, height, topRail, bottomRail, leftStile, rightStile, hBars, vBars, barWidth) {
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

        if (hBars > 0) {
            const sectionHeight = glassHeight / (hBars + 1);
            for (let b = 1; b <= hBars; b++) {
                const barY = glassY + (sectionHeight * b) - (barWidth / 2);
                dxf += na_dxfRect(glassX, barY, glassWidth, barWidth);
            }
        }

        if (vBars > 0) {
            const sectionWidth = glassWidth / (vBars + 1);
            for (let b = 1; b <= vBars; b++) {
                const barX = glassX + (sectionWidth * b) - (barWidth / 2);
                dxf += na_dxfRect(barX, glassY, barWidth, glassHeight);
            }
        }

        return dxf;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sliding Sash Panel DXF
    // ------------------------------------------------------------
    function na_generateSlidingSashPanelDxf(x, y, width, height, topRail, bottomRail, leftStile, rightStile, hBars, vBars, barWidth, overlapMm) {
        const sashHeight = height / 2;
        const sashOverlap = Math.max(0, Math.min(overlapMm || 0, sashHeight - 1));

        let dxf = '';
        dxf += na_generateCasementDxf(
            x, y, width, sashHeight + sashOverlap,
            topRail, bottomRail, leftStile, rightStile,
            hBars, vBars, barWidth
        );
        dxf += na_generateCasementDxf(
            x, y + sashHeight, width, sashHeight,
            topRail, bottomRail, leftStile, rightStile,
            hBars, vBars, barWidth
        );

        return dxf;
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
