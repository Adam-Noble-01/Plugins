// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY - SVG PREVIEW CAPTURE
// =============================================================================
//
// FILE       : Na__AssemblyStudio__PresetsLibrary__UiSystem__SvgCapture__.js
// NAMESPACE  : window.Na__PresetsLibrary__SvgCapture
// MODULE     : Presets Library SVG Capture
// AUTHOR     : Noble Architecture
// PURPOSE    : Renders the current design to inner SVG markup + viewBox for
//              storage inside a preset JSON file.
// CREATED    : 2026
//
// DESCRIPTION:
// - Window-family capture mirrors the Na_Viewport dispatch exactly:
//   double_door_mode renders through the DOM-based ExtDouble elevation
//   generator; multifold/sliding use their string generators; windows and
//   single exterior doors flow through the standard window SVG generator.
// - Interior-door capture renders Na_DoorElevationGenerator into a
//   detached <svg> element.
// - Dimensions are suppressed (show_dimensions: false) so thumbnails stay
//   clean at card scale.
// - Markup is stored WITHOUT the outer <svg> tag; consumers rebuild an
//   <svg> element and set the stored viewBox string on it.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module Constants
// -----------------------------------------------------------------------------

    var Na__PresetsLibrary__SvgCapture = {};

    var NA_SVG_NAMESPACE               = 'http://www.w3.org/2000/svg';
    var NA_FALLBACK_PADDING_MM         = 200;                                 // <-- Mirrors na_windowResetFitter's padding

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Generic Helpers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Convert a Fit Box to a viewBox Attribute String
    // ------------------------------------------------------------
    // @param  {Object} box - { x, y, width, height } in millimetres
    // @return {String}       'x y width height' with rounded values
    function na_box_to_view_box(box) {
        if (!box) return '0 0 100 100';
        return Math.round(box.x) + ' ' + Math.round(box.y) + ' ' +
               Math.round(box.width) + ' ' + Math.round(box.height);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Shallow-Clone a Config With Dimensions Suppressed
    // ------------------------------------------------------------
    // @param  {Object} config - Source configuration snapshot
    // @return {Object}          Clone with show_dimensions forced false
    function na_clone_without_dimensions(config) {
        var clone = {};
        Object.keys(config || {}).forEach(function (key) {
            clone[key] = config[key];
        });
        clone.show_dimensions = false;
        return clone;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Render a DOM-Based Generator Into a Detached <svg>
    // ------------------------------------------------------------
    // @param  {Object} generator - Module exposing na_render(svgEl, config)
    // @param  {Object} config    - Configuration handed to the generator
    // @return {String}             Inner SVG markup (no outer <svg> tag)
    function na_render_detached(generator, config) {
        var svgElement = document.createElementNS(NA_SVG_NAMESPACE, 'svg');
        generator.na_render(svgElement, config);
        return svgElement.innerHTML;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Window-Shaped Reset Fit Box
    // ------------------------------------------------------------
    // Uses the shared viewport fitter (mode-aware for multifold/sliding);
    // falls back to the same millimetre box shape when it is not loaded.
    // @param  {Object} config - Configuration snapshot
    // @return {Object}          { x, y, width, height }
    function na_resolve_window_reset_box(config) {
        if (window.Na__Viewport__Controls &&
            typeof window.Na__Viewport__Controls.na_windowResetFitter === 'function') {
            return window.Na__Viewport__Controls.na_windowResetFitter(config);
        }

        var widthMm  = Number((config && config.width_mm)  || 900);
        var heightMm = Number((config && config.height_mm) || 1200);
        return {
            x      : -NA_FALLBACK_PADDING_MM,
            y      : -heightMm - NA_FALLBACK_PADDING_MM,
            width  : widthMm  + (NA_FALLBACK_PADDING_MM * 2),
            height : heightMm + (NA_FALLBACK_PADDING_MM * 2)
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API - Preview Capture
// -----------------------------------------------------------------------------

    // FUNCTION | Capture a Window / Exterior-Door Elevation Preview
    // ------------------------------------------------------------
    // Dispatch mirrors the live viewport: double_door_mode uses the dual
    // viewport's DOM elevation generator; multifold/sliding use their
    // string generators (fit box via the shared mode-aware reset fitter);
    // windows AND single exterior doors render through the standard
    // window generator (na_resolve_active_svg_markup default branch).
    // @param  {Object} config - Flat Na_DynamicUI configuration snapshot
    // @return {Object|null}     { viewBox, widthMm, heightMm, svgMarkup }
    function na_capture_window_family_preview(config) {
        try {
            var cfg    = na_clone_without_dimensions(config);
            var markup = null;
            var box    = null;

            if (cfg.double_door_mode === true &&
                window.Na__ExtDouble__ElevationGenerator &&
                typeof window.Na__ExtDouble__ElevationGenerator.na_render === 'function') {
                markup = na_render_detached(window.Na__ExtDouble__ElevationGenerator, cfg);
                if (typeof window.Na__ExtDouble__ElevationGenerator.na_fit_to_content === 'function') {
                    box = window.Na__ExtDouble__ElevationGenerator.na_fit_to_content(cfg);
                }
            } else if (cfg.multifold_mode === true &&
                       window.Na__ExtFold__ElevationGenerator &&
                       typeof window.Na__ExtFold__ElevationGenerator.na_generate_bifold_svg === 'function') {
                markup = window.Na__ExtFold__ElevationGenerator.na_generate_bifold_svg(cfg);
            } else if (cfg.sliding_mode === true &&
                       window.Na__ExtSlide__ElevationGenerator &&
                       typeof window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg === 'function') {
                markup = window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(cfg);
            } else if (window.Na__Viewport__SvgGenerator &&
                       typeof window.Na__Viewport__SvgGenerator.na_generateWindowSvg === 'function') {
                markup = window.Na__Viewport__SvgGenerator.na_generateWindowSvg(cfg);
            }

            if (markup === null || typeof markup === 'undefined') {
                console.warn('[NA_PRESETS_SVG] No elevation generator available for capture');
                return null;
            }

            if (!box) box = na_resolve_window_reset_box(cfg);

            return {
                viewBox   : na_box_to_view_box(box),
                widthMm   : Math.round(Number(cfg.width_mm  || 900)),
                heightMm  : Math.round(Number(cfg.height_mm || 1200)),
                svgMarkup : String(markup)
            };
        } catch (err) {
            console.error('[NA_PRESETS_SVG] Window-family capture failed:', err);
            return null;
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Capture an Interior-Door Elevation Preview
    // ------------------------------------------------------------
    // Renders the door elevation into a detached <svg>; the fit box comes
    // straight from the layout calculator (origin 0,0 - no padding), so
    // its width/height double as the stored overall millimetre size.
    // @param  {Object} configBlock - Na__DoorConfiguration block
    // @return {Object|null}          { viewBox, widthMm, heightMm, svgMarkup }
    function na_capture_interior_door_preview(configBlock) {
        try {
            if (!window.Na_DoorElevationGenerator ||
                typeof window.Na_DoorElevationGenerator.na_render !== 'function') {
                console.warn('[NA_PRESETS_SVG] Na_DoorElevationGenerator not loaded');
                return null;
            }

            var markup = na_render_detached(window.Na_DoorElevationGenerator, configBlock);
            var box    = null;
            if (typeof window.Na_DoorElevationGenerator.na_fit_to_content === 'function') {
                box = window.Na_DoorElevationGenerator.na_fit_to_content(configBlock);
            }
            if (!box) box = { x: 0, y: 0, width: 1000, height: 2100 };

            return {
                viewBox   : na_box_to_view_box(box),
                widthMm   : Math.round(Number(box.width)),
                heightMm  : Math.round(Number(box.height)),
                svgMarkup : String(markup)
            };
        } catch (err) {
            console.error('[NA_PRESETS_SVG] Interior-door capture failed:', err);
            return null;
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public Exports
// -----------------------------------------------------------------------------

    Na__PresetsLibrary__SvgCapture.na_capture_window_family_preview = na_capture_window_family_preview;
    Na__PresetsLibrary__SvgCapture.na_capture_interior_door_preview = na_capture_interior_door_preview;

    window.Na__PresetsLibrary__SvgCapture = Na__PresetsLibrary__SvgCapture;

    console.log('[NA_PRESETS_SVG] Presets Library SVG capture loaded');

// endregion -------------------------------------------------------------------

})();
