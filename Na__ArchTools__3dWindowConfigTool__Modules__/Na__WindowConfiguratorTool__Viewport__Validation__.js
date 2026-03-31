/* =============================================================================
   NA WINDOW CONFIGURATOR TOOL - VIEWPORT VALIDATION
   =============================================================================
   
   FILE       : Na__WindowConfiguratorTool__Viewport__Validation__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Configuration validation and error display
   CREATED    : 2026
   
   DESCRIPTION:
   - Validates window configuration before rendering
   - Checks dimension constraints and geometry feasibility
   - Validates casement sizing and mullion spacing
   - Displays validation errors in status bar
   - Provides visual feedback for successful validation
   
   NAMING CONVENTION:
   - All functions use na_ prefix (lowercase)
   - Exported to window.Na__Viewport__Validation object
   
   ============================================================================= */

// =============================================================================
// REGION | Viewport Validation Module
// =============================================================================

const Na__Viewport__Validation = (function() {

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
    
    // FUNCTION | Validate Configuration Values
    // ------------------------------------------------------------
    // @param {Object} config - Window configuration object
    // @returns {Object} { valid: boolean, errors: Array<string> }
    function na_validateConfig(config) {
        const errors = [];
        
        // Check required values
        const width = config.width_mm || 0;
        const height = config.height_mm || 0;
        const frameThicknesses = na_getEffectiveFrameThicknesses(config);
        const casementWidth = config.casement_width_mm || 65;
        const showCasements = config.show_casements !== false;
        const slidingSashWindow = config.sliding_sash_window === true;
        const casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        const numMullions = config.mullions || 0;
        const mullionWidth = config.mullion_width_mm || 40;
        const transomCount = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        const transomWidth = config.transom_width_mm || 40;
        
        // Individual casement sizes
        const useIndividualSizes = config.casement_sizes_individual === true;
        const casTopRail = useIndividualSizes ? (config.casement_top_rail_mm || casementWidth) : casementWidth;
        const casBottomRail = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        const casLeftStile = useIndividualSizes ? (config.casement_left_stile_mm || casementWidth) : casementWidth;
        const casRightStile = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;
        
        if (width < 200) errors.push('Width must be at least 200mm');
        if (height < 200) errors.push('Height must be at least 200mm');
        const isFrameless =
            frameThicknesses.top === 0 &&
            frameThicknesses.bottom === 0 &&
            frameThicknesses.left === 0 &&
            frameThicknesses.right === 0;
        
        // Calculate opening dimensions
        const numOpenings = numMullions + 1;
        const innerWidth = width - frameThicknesses.left - frameThicknesses.right;
        const innerHeight = height - frameThicknesses.top - frameThicknesses.bottom;
        const totalMullionWidth = numMullions * mullionWidth;
        const availableWidth = innerWidth - totalMullionWidth;
        let openingWidth = availableWidth / numOpenings;
        
        const casementUnitWidth = openingWidth / casementsPerOpening;
        
        // Check that frame and mullions don't exceed window size
        const minCasementWidth = showCasements ? (casLeftStile + casRightStile) + 50 : 50;
        if (casementUnitWidth < minCasementWidth) {
            errors.push('Opening too narrow - reduce mullions or increase width');
        }
        
        // Check inner height
        const minSingleSashHeight = (casTopRail + casBottomRail) + 50;
        const minInnerHeight = showCasements
            ? (slidingSashWindow ? (minSingleSashHeight * 2) : minSingleSashHeight)
            : 50;
        if (innerHeight < minInnerHeight) {
            if (slidingSashWindow && showCasements) {
                errors.push(isFrameless ? 'Window too short for sliding sash casements' : 'Window too short for frame and sliding sash casements');
            } else {
                errors.push(isFrameless ? 'Window too short for casement' : 'Window too short for frame and casement');
            }
        }

        const minCellHeight = minInnerHeight;
        const requiredHeightForTransoms = (transomCount * transomWidth) + ((transomCount + 1) * minCellHeight);
        if (transomCount > 0 && innerHeight < requiredHeightForTransoms) {
            errors.push('Window too short for the requested transom layout');
        }
        
        return {
            valid: errors.length === 0,
            errors: errors
        };
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Show Validation Error in Status Bar
    // ------------------------------------------------------------
    // @param {Array<string>} errors - Array of error messages
    function na_showValidationError(errors) {
        const statusBar = document.getElementById('na-status-bar');
        if (statusBar) {
            statusBar.classList.remove('na-hidden', 'na-status-success', 'na-status-info');
            statusBar.classList.add('na-status-error');
            document.getElementById('na-status-message').textContent = errors.join(', ');
        }
    }
    // ---------------------------------------------------------------
    
    // FUNCTION | Show Validation Success (Hide Status Bar)
    // ------------------------------------------------------------
    function na_showValidationSuccess() {
        const statusBar = document.getElementById('na-status-bar');
        if (statusBar) {
            statusBar.classList.add('na-hidden');
        }
    }
    // ---------------------------------------------------------------
    
    // Public API
    // ------------------------------------------------------------
    return {
        na_validateConfig: na_validateConfig,
        na_showValidationError: na_showValidationError,
        na_showValidationSuccess: na_showValidationSuccess
    };
    
})();

// endregion ===================================================================

// =============================================================================
// REGION | Global Exports
// =============================================================================

// Export to global window object for access by other modules
// ------------------------------------------------------------
window.Na__Viewport__Validation = Na__Viewport__Validation;

console.log('[NA_VIEWPORT_VALIDATION] Validation module loaded');

// endregion ===================================================================

// =============================================================================
// END OF FILE
// =============================================================================
