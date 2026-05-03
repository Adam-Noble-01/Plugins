// =============================================================================
// NA PLUGIN CORE - VIEWPORT INSTANCE FACTORY
// =============================================================================
//
// FILE       : Na__Viewport__Instance__.js
// NAMESPACE  : Na__Viewport__Instance (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Factory that creates one independent, pan/zoom/reset-capable
//              viewport per (wrapper, svg) pair. Used by the Window tab,
//              the Door Plan view, the Door Elevation view, and any future
//              viewport that needs the same interaction story without
//              duplicating the state machine.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Each call to Na__Viewport__Instance.na_create(spec) returns a fresh
//   public namespace owning its own viewBox + interaction state. The
//   instance binds wheel-zoom + click-drag pan to its wrapper (via
//   Na__Viewport__Controls.na_setupPanZoom) and exposes:
//
//     instance.na_render(config)   - render then snap to fit
//     instance.na_resetView()      - snap to fit using the configured fitter
//     instance.na_get_svg()        - the bound SVG element (or null)
//     instance.na_get_wrapper()    - the bound wrapper element (or null)
//
// - The factory is window/door-agnostic. The caller supplies:
//     spec.wrapperId    - DOM id of the wrapper (required)
//     spec.svgId        - DOM id of the SVG element (required)
//     spec.fitToContent - (config) => { x, y, width, height } (required for resets)
//     spec.onRender     - (svgEl, config) => void (required - paints the SVG)
//     spec.beforeRender - (svgEl, config) => void (optional - validation hook)
//     spec.afterRender  - (svgEl, config) => void (optional - click target hook)
//     spec.autoResetOnRender - boolean - call na_resetView after each render (default true)
//     spec.initialViewBox    - optional seed viewBox before first render
//
// - All console output is prefixed [NA_VIEWPORT_INSTANCE] to make the
//   logs distinguishable from the per-tab orchestrator logs.
//
// NAMING CONVENTION:
// - All identifiers use Na__ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module Definition
// -----------------------------------------------------------------------------

    var Na__Viewport__Instance = {};


    // FUNCTION | Create a New Viewport Instance Bound to (wrapperId, svgId)
    // ------------------------------------------------------------
    // @param  {Object} spec - See file header for the full spec contract.
    // @return {Object} Public viewport instance namespace.
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

        var na_wrapper_id          = spec.wrapperId;                          // <-- DOM id of the wrapper
        var na_svg_id              = spec.svgId;                              // <-- DOM id of the SVG
        var na_fit_to_content      = spec.fitToContent || null;               // <-- Optional fitter
        var na_on_render           = spec.onRender;                           // <-- Required painter
        var na_before_render       = (typeof spec.beforeRender === 'function') ? spec.beforeRender : null;
        var na_after_render        = (typeof spec.afterRender  === 'function') ? spec.afterRender  : null;
        var na_auto_reset_on_render = (spec.autoResetOnRender === false) ? false : true;

        var na_view_box = (spec.initialViewBox && typeof spec.initialViewBox === 'object')
            ? {
                x      : Number(spec.initialViewBox.x      || 0),
                y      : Number(spec.initialViewBox.y      || 0),
                width  : Number(spec.initialViewBox.width  || 1000),
                height : Number(spec.initialViewBox.height || 1000)
              }
            : { x: 0, y: 0, width: 1000, height: 1000 };

        var na_interaction_state = {                                          // <-- Mutated by Controls.na_setupPanZoom
            scale        : 1,
            isPanning    : false,
            didPan       : false,
            lastMousePos : { x: 0, y: 0 },
            panStartPos  : { x: 0, y: 0 }
        };

        var na_wrapper_el = null;                                             // <-- Resolved on first DOM access
        var na_svg_el     = null;                                             // <-- Resolved on first DOM access
        var na_pan_zoom_bound = false;                                        // <-- Idempotent setup flag


        // SUB FUNCTION | Resolve and Cache DOM References (Idempotent)
        // ---------------------------------------------------------------
        function na_resolve_dom() {
            if (!na_wrapper_el) na_wrapper_el = document.getElementById(na_wrapper_id);
            if (!na_svg_el)     na_svg_el     = document.getElementById(na_svg_id);
            return !!(na_wrapper_el && na_svg_el);
        }
        // ---------------------------------------------------------------


        // SUB FUNCTION | Bind Pan and Zoom to the Wrapper (Idempotent)
        // ---------------------------------------------------------------
        function na_bind_pan_zoom() {
            if (na_pan_zoom_bound) return;
            if (!na_resolve_dom()) return;
            if (!window.Na__Viewport__Controls) {
                console.error('[NA_VIEWPORT_INSTANCE] Na__Viewport__Controls not available');
                return;
            }

            window.Na__Viewport__Controls.na_setupPanZoom(
                na_wrapper_el,
                na_svg_el,
                na_view_box,
                na_interaction_state,
                function () {
                    window.Na__Viewport__Controls.na_updateViewBox(na_svg_el, na_view_box);
                }
            );

            na_pan_zoom_bound = true;
        }
        // ---------------------------------------------------------------


        // FUNCTION | Reset View to Fit Content via the Configured Fitter
        // ---------------------------------------------------------------
        publicApi.na_resetView = function (config) {
            if (!na_resolve_dom()) return;
            if (typeof na_fit_to_content !== 'function') return;
            if (!window.Na__Viewport__Controls) return;

            window.Na__Viewport__Controls.na_resetView(
                na_svg_el,
                na_view_box,
                na_interaction_state,
                config,
                na_fit_to_content
            );
        };
        // ---------------------------------------------------------------


        // FUNCTION | Render the Viewport with the Provided Config
        // ---------------------------------------------------------------
        publicApi.na_render = function (config) {
            if (!na_resolve_dom()) return false;

            na_bind_pan_zoom();                                               // <-- Lazy interaction binding

            if (na_before_render) {
                try { na_before_render(na_svg_el, config); }
                catch (err) { console.error('[NA_VIEWPORT_INSTANCE] beforeRender threw:', err); }
            }

            try {
                na_on_render(na_svg_el, config);
            } catch (err) {
                console.error('[NA_VIEWPORT_INSTANCE] onRender threw:', err);
                return false;
            }

            if (na_after_render) {
                try { na_after_render(na_svg_el, config); }
                catch (err) { console.error('[NA_VIEWPORT_INSTANCE] afterRender threw:', err); }
            }

            if (na_auto_reset_on_render) {
                publicApi.na_resetView(config);
            }

            return true;
        };
        // ---------------------------------------------------------------


        // FUNCTION | Return the Bound SVG Element (Resolves Lazily)
        // ---------------------------------------------------------------
        publicApi.na_get_svg = function () {
            na_resolve_dom();
            return na_svg_el;
        };
        // ---------------------------------------------------------------


        // FUNCTION | Return the Bound Wrapper Element (Resolves Lazily)
        // ---------------------------------------------------------------
        publicApi.na_get_wrapper = function () {
            na_resolve_dom();
            return na_wrapper_el;
        };
        // ---------------------------------------------------------------


        // FUNCTION | Force the Pan/Zoom Bindings to Be Set Up Eagerly
        // ---------------------------------------------------------------
        // Useful when the caller wants to ensure interactivity is wired
        // even before the first render (e.g. on tab mount).
        publicApi.na_init = function () {
            na_bind_pan_zoom();
        };
        // ---------------------------------------------------------------


        // FUNCTION | Return the Live Interaction State Object (Same Reference)
        // ---------------------------------------------------------------
        // Returns the same object the pan/zoom binder mutates, so callers
        // (e.g. a window-specific click delegate) can read `didPan` to
        // distinguish click from drag without leaking other internals.
        publicApi.na_get_interaction_state = function () {
            return na_interaction_state;
        };
        // ---------------------------------------------------------------

        return publicApi;
    };
    // ---------------------------------------------------------------


    window.Na__Viewport__Instance = Na__Viewport__Instance;

    console.log('[NA_VIEWPORT_INSTANCE] Viewport Instance factory loaded');

// endregion -------------------------------------------------------------------

})();


// =============================================================================
// END OF FILE
// =============================================================================
