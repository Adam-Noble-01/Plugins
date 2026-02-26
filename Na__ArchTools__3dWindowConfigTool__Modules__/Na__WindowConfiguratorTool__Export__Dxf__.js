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
    
    // FUNCTION | Export Current Model as DXF (Simplified)
    // ------------------------------------------------------------
    // @param {Object} config - Window configuration object
    // @returns {string} DXF file content as string
    function na_exportDxf(config) {
        // Generate simple DXF content
        let dxf = '0\nSECTION\n2\nENTITIES\n';
        
        const width = config.width_mm || 900;
        const height = config.height_mm || 1200;
        const frameThickness = config.frame_thickness_mm || 0;
        
        // Outer frame rectangle (skip in frameless mode)
        if (frameThickness > 0) {
            dxf += na_dxfRect(0, 0, width, height);
            dxf += na_dxfRect(frameThickness, frameThickness, width - frameThickness, height - frameThickness);
        }
        
        dxf += '0\nENDSEC\n0\nEOF\n';
        
        return dxf;
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Generate DXF Rectangle
    // ------------------------------------------------------------
    // @param {number} x1 - First X coordinate
    // @param {number} y1 - First Y coordinate
    // @param {number} x2 - Second X coordinate
    // @param {number} y2 - Second Y coordinate
    // @returns {string} DXF LINE entities forming a rectangle
    function na_dxfRect(x1, y1, x2, y2) {
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
        na_dxfRect: na_dxfRect
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
