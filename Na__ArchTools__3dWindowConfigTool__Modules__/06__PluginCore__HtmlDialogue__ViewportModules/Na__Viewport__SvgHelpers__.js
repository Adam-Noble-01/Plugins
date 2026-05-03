// =============================================================================
// NA PLUGIN CORE - HTML DIALOGUE VIEWPORT SVG HELPERS
// =============================================================================
//
// FILE       : Na__Viewport__SvgHelpers__.js
// NAMESPACE  : Na__Viewport__SvgHelpers (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Tool-agnostic SVG primitives shared by every viewport
//              generator (window casement, door plan, door elevation,
//              and any future generator).
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Single source of truth for the byte-for-byte identical SVG / config
//   helper functions that previously lived inside each generator
//   (na_make_svg, na_num, na_bool, na_clear_svg).
// - No DOM ownership. Pure utility module - safe to load before any
//   tab-specific viewport generator.
// - Any future viewport generator (skylight, frame, structural cavity,
//   etc.) should consume this module rather than duplicate helpers.
//
// PUBLIC API:
//     window.Na__Viewport__SvgHelpers.NA_VIEWPORT_SVG_NS
//     window.Na__Viewport__SvgHelpers.na_make_svg(tag, attrs)
//     window.Na__Viewport__SvgHelpers.na_num(config, key, fallback)
//     window.Na__Viewport__SvgHelpers.na_bool(config, key, fallback)
//     window.Na__Viewport__SvgHelpers.na_clear_svg(svgElement)
//
// NAMING CONVENTION:
// - All identifiers use Na__ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module Constants
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | SVG Namespace
    // ------------------------------------------------------------
    var NA_VIEWPORT_SVG_NS = 'http://www.w3.org/2000/svg';                     // <-- Standard SVG namespace
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | SVG Element Construction
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Create an SVG Element with Attributes
    // ------------------------------------------------------------
    // @param  {String} tag   - SVG tag name ('rect', 'path', 'text', ...)
    // @param  {Object} attrs - Optional attribute map {key:value}
    // @return {SVGElement}
    function na_make_svg(tag, attrs) {
        var el = document.createElementNS(NA_VIEWPORT_SVG_NS, tag);            // <-- Create namespaced element
        if (attrs) {
            for (var key in attrs) {
                if (Object.prototype.hasOwnProperty.call(attrs, key)) {
                    el.setAttribute(key, attrs[key]);                          // <-- Apply each attribute
                }
            }
        }
        return el;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Remove Every Child Node from an SVG Element
    // ------------------------------------------------------------
    // Avoids `innerHTML = ''` which incurs an HTML parser invocation
    // and breaks SVG namespacing edge cases on older WebViews.
    function na_clear_svg(svgElement) {
        if (!svgElement) return;
        while (svgElement.firstChild) {
            svgElement.removeChild(svgElement.firstChild);                     // <-- Drop every child node
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Configuration Value Readers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Read a Numeric Value from Config with Fallback
    // ------------------------------------------------------------
    // @param  {Object} config   - Configuration object
    // @param  {String} key      - Property name to read
    // @param  {Number} fallback - Value to return if missing or NaN
    // @return {Number}
    function na_num(config, key, fallback) {
        var raw = config && config[key];
        var v   = (raw == null) ? fallback : Number(raw);                      // <-- Coerce, allow zero
        return isNaN(v) ? fallback : v;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read a Boolean Value from Config with Fallback
    // ------------------------------------------------------------
    // @param  {Object}  config   - Configuration object
    // @param  {String}  key      - Property name to read
    // @param  {Boolean} fallback - Value to return if missing
    // @return {Boolean}
    function na_bool(config, key, fallback) {
        if (!config) return fallback;
        var v = config[key];
        return (v === undefined || v === null) ? fallback : !!v;               // <-- Strict null/undef respect
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public Export
// -----------------------------------------------------------------------------

    window.Na__Viewport__SvgHelpers = {
        NA_VIEWPORT_SVG_NS : NA_VIEWPORT_SVG_NS,
        na_make_svg        : na_make_svg,
        na_clear_svg       : na_clear_svg,
        na_num             : na_num,
        na_bool            : na_bool
    };

    console.log('[NA_VIEWPORT_SVG_HELPERS] Shared SVG helpers loaded');

// endregion -------------------------------------------------------------------

})();


// =============================================================================
// END OF FILE
// =============================================================================
