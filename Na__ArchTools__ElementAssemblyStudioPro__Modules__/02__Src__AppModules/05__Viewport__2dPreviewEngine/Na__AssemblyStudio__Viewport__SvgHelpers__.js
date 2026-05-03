// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - VIEWPORT SVG HELPERS
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Viewport__SvgHelpers__.js
// NAMESPACE  : window.Na__Viewport__SvgHelpers (legacy global preserved)
// AUTHOR     : Noble Architecture
// PURPOSE    : Tool-agnostic SVG primitives shared by every viewport
//              generator. Single owner of na_make_svg, na_clear_svg, na_num,
//              and na_bool so feature modules do not duplicate them.
//
// DESCRIPTION:
// - na_make_svg creates namespaced SVG elements with attribute maps.
// - na_clear_svg removes all child nodes from a root <svg>.
// - na_num / na_bool read config keys with safe fallbacks.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix on the public global.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Constants
// -----------------------------------------------------------------------------

    var NA_VIEWPORT_SVG_NS = 'http://www.w3.org/2000/svg';                    // <-- SVG XML namespace

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | SVG Element Factory
// -----------------------------------------------------------------------------

    // FUNCTION | Create an SVG element in the SVG namespace
    // ------------------------------------------------------------
    function na_make_svg(tag, attrs) {
        var el = document.createElementNS(NA_VIEWPORT_SVG_NS, tag);
        if (attrs) {
            for (var key in attrs) {
                if (Object.prototype.hasOwnProperty.call(attrs, key)) {
                    el.setAttribute(key, attrs[key]);
                }
            }
        }
        return el;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | SVG Clear
// -----------------------------------------------------------------------------

    // FUNCTION | Remove all children from an SVG root element
    // ------------------------------------------------------------
    function na_clear_svg(svgElement) {
        if (!svgElement) return;
        while (svgElement.firstChild) svgElement.removeChild(svgElement.firstChild);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Config Readers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Numeric config lookup with fallback
    // ------------------------------------------------------------
    function na_num(config, key, fallback) {
        var raw = config && config[key];
        var v   = (raw == null) ? fallback : Number(raw);
        return isNaN(v) ? fallback : v;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Boolean config lookup with fallback
    // ------------------------------------------------------------
    function na_bool(config, key, fallback) {
        if (!config) return fallback;
        var v = config[key];
        return (v === undefined || v === null) ? fallback : !!v;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API & Global Export
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
