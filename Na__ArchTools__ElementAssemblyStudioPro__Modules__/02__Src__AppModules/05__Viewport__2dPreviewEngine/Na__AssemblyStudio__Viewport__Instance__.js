// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - VIEWPORT INSTANCE FACTORY
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Viewport__Instance__.js
// NAMESPACE  : window.Na__Viewport__Instance (legacy global preserved)
// AUTHOR     : Noble Architecture
// PURPOSE    : Factory that creates one independent pan/zoom/reset viewport
//              per (wrapper, svg) pair for Window, Door plan, and elevation
//              adapters.
//
// DESCRIPTION:
// - na_create(spec) validates spec.wrapperId, spec.svgId, and spec.onRender.
// - Optional spec.fitToContent, beforeRender, afterRender, initialViewBox,
//   and autoResetOnRender (default true) tune lifecycle.
// - DOM is resolved lazily; pan/zoom binds once both nodes exist.
//
// REFACTOR NOTES (v2 / EASP)
// - WindowSystem keeps a thin adapter over this factory; scope is unchanged.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix on the public global.
//
// =============================================================================


(function () {
    'use strict';

    var Na__Viewport__Instance = {};


// -----------------------------------------------------------------------------
// REGION | Viewport Instance Factory (na_create)
// -----------------------------------------------------------------------------

    // FUNCTION | Build a viewport handle for one wrapper + svg id pair
    // ------------------------------------------------------------
    Na__Viewport__Instance.na_create = function (spec) {
        if (!spec || !spec.wrapperId || !spec.svgId) {
            console.error('[NA_VIEWPORT_INSTANCE] na_create requires spec.wrapperId and spec.svgId');
            return null;
        }
        if (typeof spec.onRender !== 'function') {
            console.error('[NA_VIEWPORT_INSTANCE] na_create requires spec.onRender(svgEl, config)');
            return null;
        }

        var publicApi = {};
        var na_wrapper_id           = spec.wrapperId;
        var na_svg_id               = spec.svgId;
        var na_fit_to_content       = spec.fitToContent || null;
        var na_on_render            = spec.onRender;
        var na_before_render        = (typeof spec.beforeRender === 'function') ? spec.beforeRender : null;
        var na_after_render         = (typeof spec.afterRender  === 'function') ? spec.afterRender  : null;
        var na_auto_reset_on_render = (spec.autoResetOnRender === false) ? false : true;

        var na_view_box = (spec.initialViewBox && typeof spec.initialViewBox === 'object')
            ? {
                x      : Number(spec.initialViewBox.x      || 0),
                y      : Number(spec.initialViewBox.y      || 0),
                width  : Number(spec.initialViewBox.width  || 1000),
                height : Number(spec.initialViewBox.height || 1000)
              }
            : { x: 0, y: 0, width: 1000, height: 1000 };

        var na_interaction_state = {
            scale        : 1,
            isPanning    : false,
            didPan       : false,
            lastMousePos : { x: 0, y: 0 },
            panStartPos  : { x: 0, y: 0 }
        };

        var na_wrapper_el     = null;
        var na_svg_el         = null;
        var na_pan_zoom_bound = false;

        // INTERNAL | Resolve wrapper and svg from document ids
        // ------------------------------------------------------------
        function na_resolve_dom() {
            if (!na_wrapper_el) na_wrapper_el = document.getElementById(na_wrapper_id);
            if (!na_svg_el)     na_svg_el     = document.getElementById(na_svg_id);
            return !!(na_wrapper_el && na_svg_el);
        }
        // ---------------------------------------------------------------

        // INTERNAL | One-shot bind to Na__Viewport__Controls pan/zoom
        // ------------------------------------------------------------
        function na_bind_pan_zoom() {
            if (na_pan_zoom_bound)               return;
            if (!na_resolve_dom())               return;
            if (!window.Na__Viewport__Controls)  return;

            window.Na__Viewport__Controls.na_setupPanZoom(
                na_wrapper_el,
                na_svg_el,
                na_view_box,
                na_interaction_state,
                function () { window.Na__Viewport__Controls.na_updateViewBox(na_svg_el, na_view_box); }
            );
            na_pan_zoom_bound = true;
        }
        // ---------------------------------------------------------------

        // PUBLIC INSTANCE API | Reset view to fitted box
        // ------------------------------------------------------------
        publicApi.na_resetView = function (config) {
            if (!na_resolve_dom()) return;
            if (typeof na_fit_to_content !== 'function') return;
            if (!window.Na__Viewport__Controls) return;
            window.Na__Viewport__Controls.na_resetView(
                na_svg_el, na_view_box, na_interaction_state, config, na_fit_to_content
            );
        };
        // ---------------------------------------------------------------

        // PUBLIC INSTANCE API | Render through onRender + optional hooks
        // ------------------------------------------------------------
        publicApi.na_render = function (config) {
            if (!na_resolve_dom()) return false;
            na_bind_pan_zoom();
            if (na_before_render) {
                try { na_before_render(na_svg_el, config); }
                catch (err) { console.error('[NA_VIEWPORT_INSTANCE] beforeRender threw:', err); }
            }
            try { na_on_render(na_svg_el, config); }
            catch (err) { console.error('[NA_VIEWPORT_INSTANCE] onRender threw:', err); return false; }
            if (na_after_render) {
                try { na_after_render(na_svg_el, config); }
                catch (err) { console.error('[NA_VIEWPORT_INSTANCE] afterRender threw:', err); }
            }
            if (na_auto_reset_on_render) publicApi.na_resetView(config);
            return true;
        };
        // ---------------------------------------------------------------

        // PUBLIC INSTANCE API | DOM & state accessors
        // ------------------------------------------------------------
        publicApi.na_get_svg               = function () { na_resolve_dom(); return na_svg_el; };
        publicApi.na_get_wrapper           = function () { na_resolve_dom(); return na_wrapper_el; };
        publicApi.na_init                  = function () { na_bind_pan_zoom(); };
        publicApi.na_get_interaction_state = function () { return na_interaction_state; };
        // ---------------------------------------------------------------

        return publicApi;
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Global Export & Load Log
// -----------------------------------------------------------------------------

    window.Na__Viewport__Instance = Na__Viewport__Instance;
    console.log('[NA_VIEWPORT_INSTANCE] Viewport Instance factory loaded');

// endregion -------------------------------------------------------------------

})();
