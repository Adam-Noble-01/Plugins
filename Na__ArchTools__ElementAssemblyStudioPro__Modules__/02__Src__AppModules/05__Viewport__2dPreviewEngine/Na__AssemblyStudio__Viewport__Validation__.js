// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - VIEWPORT VALIDATION
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Viewport__Validation__.js
// NAMESPACE  : window.Na__Viewport__Validation
// AUTHOR     : Noble Architecture
//
// PURPOSE
// - Status-bar show/hide helpers used by every viewport.
// - Window-config validation (na_validateConfig) preserved here so the
//   WindowSystem MainUiLogic can validate before rendering. The validation
//   logic is window-schema-aware today; full extraction into WindowSystem is
//   a tracked follow-up in the DEVLOG.
// - Frame thickness resolution prefers Na_DynamicUI when available,
//   otherwise falls back to its own implementation so this module stays
//   usable even if the window UI module has not yet booted.
//
// PUBLIC API
//   window.Na__Viewport__Validation.na_validateConfig(config)
//   window.Na__Viewport__Validation.na_getEffectiveFrameThicknesses(config)
//   window.Na__Viewport__Validation.na_showValidationError(errors)
//   window.Na__Viewport__Validation.na_showValidationSuccess()
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Frame Thickness Resolution
// -----------------------------------------------------------------------------

    // FUNCTION | Resolve effective frame thicknesses for the four sides
    // ------------------------------------------------------------
    function na_getEffectiveFrameThicknesses(config) {
        if (window.Na_DynamicUI && typeof window.Na_DynamicUI.na_getEffectiveFrameThicknesses === 'function') {
            return window.Na_DynamicUI.na_getEffectiveFrameThicknesses(config);
        }

        var uniformThickness = (config.frame_thickness_mm != null) ? Number(config.frame_thickness_mm) : 50;
        var useAdvanced      = config.advanced_frame_controls === true;

        function na_resolveSide(sideKey) {
            var raw = useAdvanced ? config[sideKey] : uniformThickness;
            return Math.max(0, Number(raw != null ? raw : uniformThickness));
        }

        return {
            top    : na_resolveSide('frame_top_thickness_mm'),
            bottom : na_resolveSide('frame_bottom_thickness_mm'),
            left   : na_resolveSide('frame_left_thickness_mm'),
            right  : na_resolveSide('frame_right_thickness_mm')
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Window Config Validation
// -----------------------------------------------------------------------------

    // FUNCTION | Validate window configuration before rendering
    // ------------------------------------------------------------
    // @param  {Object} config - Window configuration object
    // @return {{ valid: boolean, errors: string[] }}
    function na_validateConfig(config) {
        var errors = [];

        var width             = config.width_mm  || 0;
        var height            = config.height_mm || 0;
        var frameThicknesses  = na_getEffectiveFrameThicknesses(config);
        var casementWidth     = config.casement_width_mm || 65;
        var showCasements     = config.show_casements   !== false;
        var slidingSashWindow = config.sliding_sash_window === true;
        var casementsPerOpening = Math.max(1, Math.min(6, config.casements_per_opening || 1));
        var numMullions       = config.mullions || 0;
        var mullionWidth      = config.mullion_width_mm || 40;
        var transomCount      = Math.max(0, Math.min(3, Math.round(config.transoms || 0)));
        var transomWidth      = config.transom_width_mm || 40;

        var useIndividualSizes = config.casement_sizes_individual === true;
        var casTopRail     = useIndividualSizes ? (config.casement_top_rail_mm    || casementWidth) : casementWidth;
        var casBottomRail  = useIndividualSizes ? (config.casement_bottom_rail_mm || casementWidth) : casementWidth;
        var casLeftStile   = useIndividualSizes ? (config.casement_left_stile_mm  || casementWidth) : casementWidth;
        var casRightStile  = useIndividualSizes ? (config.casement_right_stile_mm || casementWidth) : casementWidth;

        if (width  < 200) errors.push('Width must be at least 200mm');
        if (height < 200) errors.push('Height must be at least 200mm');

        var isFrameless = frameThicknesses.top === 0 && frameThicknesses.bottom === 0 &&
                          frameThicknesses.left === 0 && frameThicknesses.right === 0;

        var numOpenings        = numMullions + 1;
        var innerWidth         = width  - frameThicknesses.left - frameThicknesses.right;
        var innerHeight        = height - frameThicknesses.top  - frameThicknesses.bottom;
        var totalMullionWidth  = numMullions * mullionWidth;
        var availableWidth     = innerWidth - totalMullionWidth;
        var openingWidth       = availableWidth / numOpenings;
        var casementUnitWidth  = openingWidth / casementsPerOpening;
        var minCasementWidth   = showCasements ? (casLeftStile + casRightStile) + 50 : 50;

        if (casementUnitWidth < minCasementWidth) {
            errors.push('Opening too narrow - reduce mullions or increase width');
        }

        var minSingleSashHeight = (casTopRail + casBottomRail) + 50;
        var minInnerHeight      = showCasements
            ? (slidingSashWindow ? (minSingleSashHeight * 2) : minSingleSashHeight)
            : 50;

        if (innerHeight < minInnerHeight) {
            if (slidingSashWindow && showCasements) {
                errors.push(isFrameless ? 'Window too short for sliding sash casements' : 'Window too short for frame and sliding sash casements');
            } else {
                errors.push(isFrameless ? 'Window too short for casement' : 'Window too short for frame and casement');
            }
        }

        var minCellHeight             = minInnerHeight;
        var requiredHeightForTransoms = (transomCount * transomWidth) + ((transomCount + 1) * minCellHeight);
        if (transomCount > 0 && innerHeight < requiredHeightForTransoms) {
            errors.push('Window too short for the requested transom layout');
        }

        return { valid: errors.length === 0, errors: errors };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Status Bar Helpers
// -----------------------------------------------------------------------------

    // FUNCTION | Show validation errors in the shared status bar
    // ------------------------------------------------------------
    function na_showValidationError(errors) {
        var statusBar = document.getElementById('na-status-bar');
        if (!statusBar) return;
        statusBar.classList.remove('na-hidden', 'na-status-success', 'na-status-info');
        statusBar.classList.add('na-status-error');
        var messageEl = document.getElementById('na-status-message');
        if (messageEl) messageEl.textContent = (errors || []).join(', ');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Hide the status bar after a successful validation path
    // ------------------------------------------------------------
    function na_showValidationSuccess() {
        var statusBar = document.getElementById('na-status-bar');
        if (statusBar) statusBar.classList.add('na-hidden');
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API & Global Export
// -----------------------------------------------------------------------------

    window.Na__Viewport__Validation = {
        na_validateConfig              : na_validateConfig,
        na_getEffectiveFrameThicknesses: na_getEffectiveFrameThicknesses,
        na_showValidationError         : na_showValidationError,
        na_showValidationSuccess       : na_showValidationSuccess
    };

    console.log('[NA_VIEWPORT_VALIDATION] Validation module loaded');

// endregion -------------------------------------------------------------------

})();
