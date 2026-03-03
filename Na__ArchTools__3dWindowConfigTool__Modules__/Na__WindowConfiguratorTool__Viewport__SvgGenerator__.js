/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - SVG GENERATOR
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__Viewport__SvgGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : SVG markup generation for window preview
   CREATED    : 2026
   
   DESCRIPTION:
   - Generates SVG markup from window configuration
   - Supports frames, mullions, casements, and glaze bars
   - Multi-casement openings (1-6 panels per opening)
   - Individual casement rail/stile sizing
   - Clickable casement removal targets
   - Dimension annotations
   - Pure rendering functions with no side effects
   
   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Viewport__SvgGenerator object
   
   ============================================================================= */

// =============================================================================
// REGION | SVG Generator Module
// =============================================================================

const Na__Viewport__SvgGenerator = (function() {
    
    // FUNCTION | Get Material Color by ID
    // ------------------------------------------------------------
    // Looks up a material's hex color from the hardcoded materials array.
    // @param {string} materialId - Material ID (e.g., 'MAT120__GenericWood')
    // @returns {string} Hex color string (e.g., '#D2B48C')
    function na_getMaterialColor(materialId) {
        // Get frame material config from NA_OPTIONS_CONFIG
        const frameMatConfig = window.NA_OPTIONS_CONFIG.find(c => c.id === 'frame_material_id');
        if (!frameMatConfig || !frameMatConfig.materials) {
            return '#D2B48C'; // Fallback to generic wood color
        }
        
        const material = frameMatConfig.materials.find(m => m.id === materialId);
        return material ? material.color : '#D2B48C';
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate SVG Content for Window with Mullions and Optional Casements
    // ------------------------------------------------------------
    // @param {Object} config - Window configuration object
    // @returns {string} SVG markup as string
    function na_generateWindowSvg(config) {
        const width = config.width_mm || 900;
        const height = config.height_mm || 1200;
        const frameThickness = (config.frame_thickness_mm != null) ? config.frame_thickness_mm : 50;
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
        const frameMaterialId = config.frame_material_id || 'MAT120__GenericWood';
        const frameColor = na_getMaterialColor(frameMaterialId);
        const showDimensions = config.show_dimensions !== false;
        const hasCill = config.has_cill !== false;
        const removedCasements = config.removed_casements || [];
        
        // Individual casement sizes (used when expanded panel is open)
        const useIndividualSizes = config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const casLeftStile = useIndividualSizes ? (config.casement_left_stile_mm || casementWidth) : casementWidth;
        const casRightStile = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;
        
        let svg = '';
        
        // Calculate openings
        const numOpenings = numMullions + 1;
        const innerWidth = width - (2 * frameThickness);
        const innerHeight = height - (2 * frameThickness);
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        const openingWidth = availableWidth / numOpenings;
        
        // Outer frame (4 rectangles) - skip in frameless mode (frameThickness === 0)
        if (frameThickness > 0) {
            // JOINERY CONVENTION: Stiles full height, rails inset
            svg += na_svgRect(0, 0, frameThickness, height, frameColor, '#000', 1); // Left stile (full height)
            svg += na_svgRect(width - frameThickness, 0, frameThickness, height, frameColor, '#000', 1); // Right stile (full height)
            svg += na_svgRect(frameThickness, 0, innerWidth, frameThickness, frameColor, '#000', 1); // Bottom rail (inset)
            svg += na_svgRect(frameThickness, height - frameThickness, innerWidth, frameThickness, frameColor, '#000', 1); // Top rail (inset)
        }
        
        // Draw mullions
        for (let m = 1; m <= numMullions; m++) {
            const mullionX = frameThickness + (m * openingWidth) + ((m - 1) * mullionWidth);
            svg += na_svgRect(mullionX, frameThickness, mullionWidth, innerHeight, frameColor, '#000', 1);
        }
        
        // Draw each opening with casement (if enabled), glass, and glaze bars
        for (let i = 0; i < numOpenings; i++) {
            const openingX = frameThickness + (i * (openingWidth + mullionWidth));
            const openingY = frameThickness;
            
            // Check if this opening has its casement removed
            const isCasementRemoved = removedCasements.indexOf(i) !== -1;
            
            // Determine if this opening should show casements
            const openingHasCasement = showCasements && !isCasementRemoved;
            
            if (openingHasCasement) {
                const panelWidth = openingWidth / casementsPerOpening;
                for (let p = 0; p < casementsPerOpening; p++) {
                    const panelX = openingX + (p * panelWidth);
                    if (slidingSashWindow) {
                        svg += na_generateSlidingSashPanelSvg(
                            panelX, openingY, panelWidth, innerHeight,
                            casTopRail, casBottomRail, casLeftStile, casRightStile,
                            frameColor, hBars, vBars, barWidth, slidingSashOverlap
                        );
                    } else {
                        svg += na_generateSingleCasementSvg(
                            panelX, openingY, panelWidth, innerHeight,
                            casTopRail, casBottomRail, casLeftStile, casRightStile,
                            frameColor, hBars, vBars, barWidth
                        );
                    }
                }
            } else {
                // Direct glazed - N glass panes without casement frames
                const panelWidth = openingWidth / casementsPerOpening;
                for (let p = 0; p < casementsPerOpening; p++) {
                    const panelX = openingX + (p * panelWidth);
                    svg += na_svgRect(panelX, openingY, panelWidth, innerHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);
                    
                    if (hBars > 0 || vBars > 0) {
                        svg += na_generateGlazeBarsSvg(panelX, openingY, panelWidth, innerHeight, hBars, vBars, barWidth, frameColor);
                    }
                }
            }
            
            // Add "casement removed" visual indicator (dashed border) for removed openings
            if (showCasements && isCasementRemoved) {
                const svgY = -openingY - innerHeight;
                const inset = 4;
                svg += `<rect class="na-casement-removed-indicator" 
                              x="${openingX + inset}" y="${svgY + inset}" 
                              width="${openingWidth - inset * 2}" height="${innerHeight - inset * 2}" 
                              fill="none" stroke="rgba(244, 67, 54, 0.5)" stroke-width="2" stroke-dasharray="10 5"
                              pointer-events="none"/>`;
            }
        }
        
        // Cill (skip in frameless mode)
        if (hasCill && frameThickness > 0) {
            const cillDepth = config.cill_depth_mm || 50;
            const cillHeight = config.cill_height_mm || 50;
            svg += na_svgRect(0, -cillHeight, width, cillHeight, '#A0908A', '#000', 1);
        }
        
        // Dimensions
        if (showDimensions) {
            svg += na_svgDimensions(width, height);
        }
        
        // Click-target overlays for casement toggling (rendered last so they're on top)
        // Only show when casements are globally enabled
        if (showCasements) {
            for (let i = 0; i < numOpenings; i++) {
                const openingX = frameThickness + (i * (openingWidth + mullionWidth));
                const openingY = frameThickness;
                const svgY = -openingY - innerHeight;
                svg += `<rect class="na-opening-click-target" 
                              data-opening-index="${i}"
                              x="${openingX}" y="${svgY}" 
                              width="${openingWidth}" height="${innerHeight}" 
                              fill="transparent" 
                              style="cursor: pointer; pointer-events: all;"/>`;
            }
        }
        
        return svg;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate SVG for a Single Casement with Individual Sizes
    // ------------------------------------------------------------
    function na_generateSingleCasementSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth) {
        let svg = '';
        
        // Casement frame (4 pieces) - JOINERY CONVENTION: Stiles full height, rails inset
        // Left stile (full height)
        svg += na_svgRect(x, y, leftStile, height, frameColor, '#000', 0.5);
        // Right stile (full height)
        svg += na_svgRect(x + width - rightStile, y, rightStile, height, frameColor, '#000', 0.5);
        // Bottom rail (inset between stiles)
        svg += na_svgRect(x + leftStile, y, width - leftStile - rightStile, bottomRail, frameColor, '#000', 0.5);
        // Top rail (inset between stiles)
        svg += na_svgRect(x + leftStile, y + height - topRail, width - leftStile - rightStile, topRail, frameColor, '#000', 0.5);
        
        // Glass area inside casement
        const glassX = x + leftStile;
        const glassY = y + bottomRail;
        const glassWidth = width - leftStile - rightStile;
        const glassHeight = height - topRail - bottomRail;
        
        // Glass pane
        svg += na_svgRect(glassX, glassY, glassWidth, glassHeight, 'rgba(135, 206, 235, 0.3)', '#87CEEB', 0.5);
        
        // Reuse glaze bar helper so direct-glazed and casement paths stay consistent.
        if (hBars > 0 || vBars > 0) {
            svg += na_generateGlazeBarsSvg(glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, frameColor);
        }
        
        return svg;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Generate Sliding Sash SVG for One Panel
    // ------------------------------------------------------------
    // Draws top and bottom casements stacked vertically.
    // Bottom sash gets a subtle shading overlay to indicate setback depth.
    function na_generateSlidingSashPanelSvg(x, y, width, height, topRail, bottomRail, leftStile, rightStile, frameColor, hBars, vBars, barWidth, overlapMm) {
        let svg = '';

        const sashHeight = height / 2;
        const sashOverlap = Math.max(0, Math.min(overlapMm || 0, sashHeight - 1));
        const bottomSashY = y;
        const topSashY = y + sashHeight;

        // Bottom sash extends behind the top sash to represent weathering overlap.
        svg += na_generateSingleCasementSvg(
            x, bottomSashY, width, sashHeight + sashOverlap,
            topRail, bottomRail, leftStile, rightStile,
            frameColor, hBars, vBars, barWidth
        );

        // Reduced by 50% from previous 0.2 intensity.
        svg += na_svgRect(x, bottomSashY, width, sashHeight + sashOverlap, 'rgba(0, 0, 0, 0.1)', 'none', 0);

        // Draw top sash last so it visually sits in front.
        svg += na_generateSingleCasementSvg(
            x, topSashY, width, sashHeight,
            topRail, bottomRail, leftStile, rightStile,
            frameColor, hBars, vBars, barWidth
        );

        return svg;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate SVG Glaze Bars for a Glass Area (No Casement Frame)
    // ------------------------------------------------------------
    // Used for direct-glazed openings where casement has been removed.
    // Draws horizontal and vertical glaze bars within the given glass area.
    function na_generateGlazeBarsSvg(glassX, glassY, glassWidth, glassHeight, hBars, vBars, barWidth, frameColor) {
        let svg = '';
        
        // Horizontal glaze bars
        if (hBars > 0) {
            const sectionHeight = glassHeight / (hBars + 1);
            for (let b = 1; b <= hBars; b++) {
                const barY = glassY + (sectionHeight * b) - (barWidth / 2);
                svg += na_svgRect(glassX, barY, glassWidth, barWidth, frameColor, '#000', 0.5);
            }
        }
        
        // Vertical glaze bars
        if (vBars > 0) {
            const sectionWidth = glassWidth / (vBars + 1);
            for (let b = 1; b <= vBars; b++) {
                const barX = glassX + (sectionWidth * b) - (barWidth / 2);
                svg += na_svgRect(barX, glassY, barWidth, glassHeight, frameColor, '#000', 0.5);
            }
        }
        
        return svg;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate SVG Rectangle
    // ------------------------------------------------------------
    // @param {number} x - X coordinate (bottom-left origin)
    // @param {number} y - Y coordinate (bottom-left origin)
    // @param {number} w - Width
    // @param {number} h - Height
    // @param {string} fill - Fill color
    // @param {string} stroke - Stroke color
    // @param {number} strokeWidth - Stroke width
    // @returns {string} SVG rect element
    function na_svgRect(x, y, w, h, fill, stroke, strokeWidth) {
        // Flip Y coordinate for SVG (origin at bottom-left visually)
        const svgY = -y - h;
        return `<rect x="${x}" y="${svgY}" width="${w}" height="${h}" 
                      fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}"/>`;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate Dimension Annotations
    // ------------------------------------------------------------
    // @param {number} width - Window width
    // @param {number} height - Window height
    // @returns {string} SVG dimension lines and text
    function na_svgDimensions(width, height) {
        let svg = '';
        
        // Responsive font size scales with window dimensions
        const fontSize = Math.min(height) * 0.04;
        const lineWidth = 2;
        const tickSize = 15;
        const dimOffset = 100;
        const textOffset = fontSize * 0.85;
        
        // Width dimension (below window)
        svg += `<line x1="0" y1="${dimOffset}" x2="${width}" y2="${dimOffset}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="0" y1="${dimOffset - tickSize}" x2="0" y2="${dimOffset + tickSize}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${width}" y1="${dimOffset - tickSize}" x2="${width}" y2="${dimOffset + tickSize}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<text x="${width / 2}" y="${dimOffset + textOffset}" text-anchor="middle" fill="#303030" font-size="${fontSize}" font-weight="600">${width}mm</text>`;
        
        // Height dimension (left of window)
        svg += `<line x1="${-dimOffset}" y1="${-height}" x2="${-dimOffset}" y2="0" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="${-height}" x2="${-dimOffset + tickSize}" y2="${-height}" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<line x1="${-dimOffset - tickSize}" y1="0" x2="${-dimOffset + tickSize}" y2="0" stroke="#606060" stroke-width="${lineWidth}"/>`;
        svg += `<text x="${-dimOffset - textOffset}" y="${-height / 2}" text-anchor="middle" fill="#303030" font-size="${fontSize}" font-weight="600" transform="rotate(-90, ${-dimOffset - textOffset}, ${-height / 2})">${height}mm</text>`;
        
        return svg;
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_generateWindowSvg: na_generateWindowSvg,
        na_generateSingleCasementSvg: na_generateSingleCasementSvg,
        na_generateSlidingSashPanelSvg: na_generateSlidingSashPanelSvg,
        na_generateGlazeBarsSvg: na_generateGlazeBarsSvg,
        na_svgRect: na_svgRect,
        na_svgDimensions: na_svgDimensions,
        na_getMaterialColor: na_getMaterialColor
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Viewport__SvgGenerator = Na__Viewport__SvgGenerator;

console.log('[NA_VIEWPORT_SVGGENERATOR] SVG Generator module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
