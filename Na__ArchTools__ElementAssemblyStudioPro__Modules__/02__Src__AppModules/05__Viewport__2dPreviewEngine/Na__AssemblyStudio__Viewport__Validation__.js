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

        if (config && config.double_door_mode === true) {
            return na_validateDoubleDoorConfig(config);
        }
        if (config && config.ext_single_door_mode === true) {            // <-- Single exterior door: schema lives in NA_DOOR_PANEL_CONFIG
            return na_validateSingleDoorConfig(config);
        }
        if (config && config.multifold_mode === true) {                  // <-- Bifold mode: schema lives in NA_BIFOLD_DOOR_CONFIG
            return na_validateBifoldConfig(config);
        }
        if (config && config.sliding_mode === true) {                    // <-- Sliding mode: schema lives in NA_SLIDING_DOOR_CONFIG
            return na_validateSlidingConfig(config);
        }

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
        var topSashBottomRail = Number(config.top_sash_bottom_rail_mm || casBottomRail);
        var bottomSashTopRail = config.bottom_sash_top_rail_override === true
            ? Number(config.bottom_sash_top_rail_mm || casTopRail)
            : Number(casTopRail);
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

        var minSingleSashHeight = Math.max(
            casTopRail + topSashBottomRail,
            bottomSashTopRail + casBottomRail
        ) + 50;
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

    // FUNCTION | Validate exterior double-door configuration
    // ------------------------------------------------------------
    function na_validateDoubleDoorConfig(config) {
        var errors = [];
        var width = Number(config.width_mm || 0);
        var height = Number(config.height_mm || 0);
        var frameTh = na_getEffectiveFrameThicknesses(config);
        var innerW = width - frameTh.left - frameTh.right;
        var innerH = height - frameTh.top - frameTh.bottom;
        // Active leaf width is an EQ/mm hybrid: 'EQ' (or non-numeric) = equal split.
        var activeRaw = config.double_door_active_leaf_width_mm;
        var activeNum = (typeof activeRaw === 'number') ? activeRaw : parseFloat(activeRaw);
        var activeW = isFinite(activeNum) ? activeNum : (innerW / 2);
        var passiveW = innerW - activeW;
        var leftAngle = Number(config.double_door_left_opening_angle_deg);
        var rightAngle = Number(config.double_door_right_opening_angle_deg);
        var leftProjection = Number(config.double_door_left_hinge_projection_mm || 0);
        var rightProjection = Number(config.double_door_right_hinge_projection_mm || 0);

        if (width < 800) errors.push('Double-door opening width must be at least 800mm');
        if (height < 1500) errors.push('Double-door opening height must be at least 1500mm');
        if (innerW <= 0 || innerH <= 0) {
            errors.push('Double-door frame thickness leaves no clear opening');
        } else {
            if (activeW < 300) errors.push('Active double-door leaf must be at least 300mm wide');
            if (passiveW < 300) errors.push('Passive double-door leaf must be at least 300mm wide');
        }

        if (!Number.isFinite(leftAngle) || leftAngle < 0 || leftAngle > 180) {
            errors.push('Left leaf opening angle must be between 0 and 180 degrees');
        }
        if (!Number.isFinite(rightAngle) || rightAngle < 0 || rightAngle > 180) {
            errors.push('Right leaf opening angle must be between 0 and 180 degrees');
        }
        if (leftProjection < 0 || leftProjection > 150 || rightProjection < 0 || rightProjection > 150) {
            errors.push('Parliament hinge projection must be between 0 and 150mm');
        }

        if (window.Na__ExtDouble__LeafConfigResolver &&
            typeof window.Na__ExtDouble__LeafConfigResolver.na_validate === 'function') {
            var subsystemValidation = window.Na__ExtDouble__LeafConfigResolver.na_validate(config);
            if (subsystemValidation && Array.isArray(subsystemValidation.errors)) {
                subsystemValidation.errors.forEach(function (message) {
                    if (errors.indexOf(message) === -1) errors.push(message);
                });
            }
        }

        return { valid: errors.length === 0, errors: errors };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Validate exterior single-door configuration
    // ------------------------------------------------------------
    // Mirrors the double-door gate for the one-leaf product: the leaf spans
    // the whole clear width, so there is a single 300 mm minimum and one
    // opening angle / hinge projection to check.
    function na_validateSingleDoorConfig(config) {
        var errors = [];
        var width = Number(config.width_mm || 0);
        var height = Number(config.height_mm || 0);
        var frameTh = na_getEffectiveFrameThicknesses(config);
        var innerW = width - frameTh.left - frameTh.right;
        var innerH = height - frameTh.top - frameTh.bottom;
        var angle = Number(config.single_door_opening_angle_deg);
        var projection = Number(config.single_door_hinge_projection_mm || 0);

        if (width < 400) errors.push('Single-door opening width must be at least 400mm');
        if (height < 1200) errors.push('Single-door opening height must be at least 1200mm');
        if (innerW <= 0 || innerH <= 0) {
            errors.push('Single-door frame thickness leaves no clear opening');
        } else if (innerW < 300) {
            errors.push('Single-door leaf must be at least 300mm wide');
        }

        if (!Number.isFinite(angle) || angle < 0 || angle > 180) {
            errors.push('Opening angle must be between 0 and 180 degrees');
        }
        if (projection < 0 || projection > 150) {
            errors.push('Parliament hinge projection must be between 0 and 150mm');
        }

        if (window.Na__ExtSingleDoor__LeafConfigResolver &&
            typeof window.Na__ExtSingleDoor__LeafConfigResolver.na_validate === 'function') {
            var subsystemValidation = window.Na__ExtSingleDoor__LeafConfigResolver.na_validate(config);
            if (subsystemValidation && Array.isArray(subsystemValidation.errors)) {
                subsystemValidation.errors.forEach(function (message) {
                    if (errors.indexOf(message) === -1) errors.push(message);
                });
            }
        }

        return { valid: errors.length === 0, errors: errors };
    }
    // ---------------------------------------------------------------


    // FUNCTION | Validate bifold-door configuration before rendering
    // ------------------------------------------------------------
    // Phase-9: Bifold doors share the WindowSystem's Dimensions / Cill &
    // Frame sliders. Validation reads `width_mm`, `height_mm` and the
    // per-edge frame thickness keys (with a legacy fallback to the
    // pre-Phase-9 `bifold_door_opening_*_mm` keys for any config that
    // has not yet been migrated by the load helper).
    function na_validateBifoldConfig(config) {
        var errors = [];

        var width   = Number(config.width_mm  || config.bifold_door_opening_width_mm  || 0);
        var height  = Number(config.height_mm || config.bifold_door_opening_height_mm || 0);
        var panels  = Math.round(Number(config.bifold_door_panel_count) || 0);
        var stileW  = Math.max(40, Number(config.bifold_door_stile_width_mm || 95));
        var headRl  = Math.max(40, Number(config.bifold_door_head_rail_mm  || 95));
        var baseRl  = Math.max(40, Number(config.bifold_door_base_rail_mm  || 200));
        var frameTh = na_getEffectiveFrameThicknesses(config);

        if (width  < 800)  errors.push('Bifold opening width must be at least 800mm');
        if (height < 1500) errors.push('Bifold opening height must be at least 1500mm');
        if (panels < 2 || panels > 8) errors.push('Bifold panel count must be between 2 and 8');

        var innerW = width  - frameTh.left - frameTh.right;
        var innerH = height - frameTh.top  - frameTh.bottom;

        if (innerW <= 0 || innerH <= 0) {
            errors.push('Bifold frame thickness leaves no room for panels - reduce frame edges');
        } else if (panels >= 2) {
            var perPanelW = innerW / panels;
            var minPanelW = (2 * stileW) + 50;
            var minPanelH = headRl + baseRl + 50;
            if (perPanelW < minPanelW) errors.push('Bifold panels too narrow - reduce panel count, stile width or frame edges');
            if (innerH    < minPanelH) errors.push('Bifold opening too short for head + base rails - reduce rail size or frame edges');
        }

        return { valid: errors.length === 0, errors: errors };
    }
    // ---------------------------------------------------------------


    // FUNCTION | Validate sliding-door configuration before rendering
    // ------------------------------------------------------------
    // Phase-9: Sliding doors share the WindowSystem's Dimensions / Cill &
    // Frame sliders. Validation reads `width_mm`, `height_mm` and the
    // per-edge frame thickness keys (with a legacy fallback to the
    // pre-Phase-9 `sliding_door_opening_*_mm` keys for any config that
    // has not yet been migrated by the load helper).
    function na_validateSlidingConfig(config) {
        var errors = [];

        var width   = Number(config.width_mm  || config.sliding_door_opening_width_mm  || 0);
        var height  = Number(config.height_mm || config.sliding_door_opening_height_mm || 0);
        var setback = Number(config.sliding_door_rear_setback_mm)   || 0;
        var stileW  = Math.max(40, Number(config.sliding_door_stile_width_mm || 95));
        var headRl  = Math.max(40, Number(config.sliding_door_head_rail_mm   || 95));
        var baseRl  = Math.max(40, Number(config.sliding_door_base_rail_mm   || 200));
        var frameTh = na_getEffectiveFrameThicknesses(config);

        if (width  < 800)  errors.push('Sliding opening width must be at least 800mm');
        if (height < 1500) errors.push('Sliding opening height must be at least 1500mm');
        if (setback < 20)  errors.push('Sliding rear setback must be at least 20mm');

        var innerW = width  - frameTh.left - frameTh.right;
        var innerH = height - frameTh.top  - frameTh.bottom;

        if (innerW <= 0 || innerH <= 0) {
            errors.push('Sliding frame thickness leaves no room for leaves - reduce frame edges');
        } else {
            var perLeafW = innerW / 2;
            var minLeafW = (2 * stileW) + 50;
            var minLeafH = headRl + baseRl + 50;
            if (perLeafW < minLeafW) errors.push('Sliding leaves too narrow - reduce stile width or frame edges');
            if (innerH   < minLeafH) errors.push('Sliding opening too short for head + base rails - reduce rail size or frame edges');
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
