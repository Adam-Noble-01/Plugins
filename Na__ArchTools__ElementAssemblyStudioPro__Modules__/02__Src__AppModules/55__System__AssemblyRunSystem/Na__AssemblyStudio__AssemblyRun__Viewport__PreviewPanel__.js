// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - PREVIEW PANEL
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AssemblyRun__Viewport__PreviewPanel__.js
// NAMESPACE  : Na_RunPreview (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : The Assembly Runs tab's preview: the plan and the elevation as
//              two drawings you can zoom, pan and fit, with dimensions you
//              can type over, shown both together, one at a time, or flipped
//              out into a large panel on the right of the dialog.
// CREATED    : 16-Nov-2026 (V2.7.1)
//
// WHY (Adam, 16-Nov-2026)
//   "The preview is hard to see, so add the same kind of zoom and dimensions
//   ... add some tabs to it on the top right. The initial view should be
//   like this, showing both. Have it so that you can make it show just the
//   plan or the elevation, or you can flip it out to the right-hand side. It
//   shows a much bigger window with it and a fully navigatable 2D space."
//
// WHAT IT USES
// - Na__Viewport__Instance (the shared preview engine): one pan / zoom / fit
//   viewport per drawing, CAD style as on the other tabs. Scroll zooms about
//   the cursor, a drag pans, a double click on empty space fits.
// - Na__Viewport__Controls.na_setupDimensionEditing: a click on a dimension
//   opens a text box over it, as in the window preview.
// - Na__AssemblyRun__LayoutDrawer: draws from Ruby's layout at a given unit
//   (millimetres per screen pixel). This file measures that unit and draws
//   again whenever the zoom or a pane's size changes, so labels and
//   dimensions stay one size on screen.
//
// THE FOUR WAYS TO LOOK
//   Both       plan and elevation side by side (how the tab opens)
//   Plan       the plan alone, the full width of the card
//   Elevation  the elevation alone
//   Flip Out   the preview leaves the column and fills a panel on the right.
//              Ruby widens the dialog to make room (na_runSetPreviewPanel)
//              and narrows it again on Flip Back, or when the tab is left.
//              Both, Plan and Elevation still choose what the panel shows.
//
// THE TAB'S SIDE (the host handed to na_init)
//   layout()                     the layout Ruby last resolved, or null
//   selection()                  { leg, span } picked out, or null
//   closed()                     true when the path is closed
//   product(key)                 a product's name as the tab shows it ("Sliding
//                                Doors"), for a span's label and hover text
//   on_select(span | null)       a span was clicked (or empty space)
//   on_menu(event, span)         a span was right-clicked
//   on_dimension(kind, index, text) -> { ok, error }   a size was typed
//
// NAMING CONVENTION:
// - All custom identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Na_RunPreview = {};

    // -----------------------------------------------------------------------
    // REGION | Constants and state
    // -----------------------------------------------------------------------

    var NA_SECTION_ID     = 'na-preview-runs';
    var NA_VIEWS_ID       = 'na-run-views';
    var NA_FLIP_ID        = 'na-run-view-flip';
    var NA_DIMS_ID        = 'na-btn-dims-runs';
    var NA_RESET_ID       = 'na-btn-run-reset-view';
    var NA_HANDLE_ID      = 'na-run-preview-resize-handle';
    var NA_PLAN_LABEL_ID  = 'na-run-plan-label';
    var NA_PANES          = {
        plan      : { wrapperId: 'na-run-plan-wrapper',      svgId: 'na-run-plan-svg' },
        elevation : { wrapperId: 'na-run-elevation-wrapper', svgId: 'na-run-elevation-svg' }
    };
    var NA_VIEW_NAMES     = ['both', 'plan', 'elevation'];
    var NA_FLIP_CLASS     = 'na-run-flipped';                                   // <-- On <body> while the preview is flipped out
    var NA_FLIP_EXTRA_MIN = 520;                                                // <-- The dialog grows by at least this (page pixels)
    var NA_FLIP_EXTRA_MAX = 1100;                                               // <-- ... and by no more than this
    var NA_FLIP_EDGE_GAP  = 12;                                                 // <-- Kept clear of the screen's right edge
    var NA_FLIP_PANEL_MIN = 360;                                                // <-- Narrowest the flipped-out panel is squeezed to
    var NA_FLIP_LEFT_MIN  = 380;                                                // <-- Narrowest the controls beside it are squeezed to
    var NA_FLIP_SETTLE_MS = 500;                                                // <-- Time given to the dialog to grow before it is checked
    var NA_HEIGHT_MIN     = 120;                                                // <-- The docked preview's height, by its drag handle
    var NA_HEIGHT_MAX     = 720;
    var NA_MIN_PANE_PX    = 4;                                                  // <-- A pane smaller than this is hidden: nothing is drawn

    var na_host    = null;                                                      // <-- The tab's side (see the header)
    var na_views   = { plan: null, elevation: null };                           // <-- Na__Viewport__Instance handles
    var na_queued  = { plan: false, elevation: false };                         // <-- A redraw is waiting for the next frame
    var na_state   = {
        view       : 'both',
        flipped    : false,
        wantFlip   : false,                                                     // <-- Flipped out when the tab was left: flip out again on return
        dimensions : true,
        baseWidth  : 0                                                          // <-- The page's width just before it flipped out
    };

    // -----------------------------------------------------------------------
    // REGION | Small helpers
    // -----------------------------------------------------------------------

    function na_el(id) { return document.getElementById(id); }

    function na_drawer() { return window.Na__AssemblyRun__LayoutDrawer; }

    function na_clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }

    function na_send(callback, payload) {
        if (typeof sketchup === 'undefined' || typeof sketchup[callback] !== 'function') return false;
        sketchup[callback](JSON.stringify(payload));
        return true;
    }

    function na_pane(name) {
        var wrapper = na_el(NA_PANES[name].wrapperId);
        return wrapper ? { width: wrapper.clientWidth, height: wrapper.clientHeight } : { width: 0, height: 0 };
    }

    function na_layout() { return na_host ? na_host.layout() : null; }

    // -----------------------------------------------------------------------
    // REGION | Fit, unit and drawing
    // -----------------------------------------------------------------------

    // HELPER FUNCTION | The View Box That Fits a Drawing to Its Pane
    // ---------------------------------------------------------------
    function na_fit(name) {
        var drawer = na_drawer();
        var layout = na_layout();
        var pane   = na_pane(name);
        if (!drawer || !layout) return { x: 0, y: 0, width: Math.max(pane.width, 40), height: Math.max(pane.height, 40), unit: 1 };
        var options = { dimensions: na_state.dimensions };
        return name === 'plan' ? drawer.na_plan_fit(layout, pane, options) : drawer.na_elevation_fit(layout, pane, options);
    }

    // HELPER FUNCTION | Millimetres per Screen Pixel in a Pane, Now
    // ---------------------------------------------------------------
    // Once the user has zoomed or panned, read off the view box on show;
    // until then, the unit the fit is about to give.
    function na_unit(name) {
        var view  = na_views[name];
        var state = view ? view.na_get_interaction_state() : null;
        if (state && state.userView === true) {
            var svg  = na_el(NA_PANES[name].svgId);
            var box  = (svg && svg.viewBox) ? svg.viewBox.baseVal : null;
            var pane = na_pane(name);
            if (box && box.width > 0 && pane.width > 0 && pane.height > 0) return Math.max(box.width / pane.width, box.height / pane.height);
        }
        return na_fit(name).unit;
    }

    // SUB FUNCTION | Paint One Drawing at the Present Unit
    // ---------------------------------------------------------------
    function na_paint(name, svg) {
        var drawer = na_drawer();
        var layout = na_layout();
        svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
        if (!drawer || !layout) { svg.innerHTML = ''; return; }
        var options = {
            unit       : na_unit(name),
            selection  : na_host.selection(),
            dimensions : na_state.dimensions,
            editable   : true,
            closed     : na_host.closed() === true,
            product    : typeof na_host.product === 'function' ? na_host.product : null
        };
        svg.innerHTML = (name === 'plan' ? drawer.na_plan(layout, options) : drawer.na_elevation(layout, options)).markup;
        if (name !== 'plan') return;
        // What the plan's arrowheads mean (V2.7.2): the side each span is seen from.
        var label = na_el(NA_PLAN_LABEL_ID);
        if (label) label.textContent = (layout.settings || {}).frames === false ? 'Plan · ▲ room side' : 'Plan · ▲ outside';
    }

    // SUB FUNCTION | Create the Two Viewports on First Use
    // ---------------------------------------------------------------
    function na_ensure_views() {
        if (!window.Na__Viewport__Instance) return;
        Object.keys(NA_PANES).forEach(function (name) {
            if (na_views[name]) return;
            var view = window.Na__Viewport__Instance.na_create({
                wrapperId    : NA_PANES[name].wrapperId,
                svgId        : NA_PANES[name].svgId,
                keepUserView : true,                                            // <-- A new layout never throws away the user's zoom
                fitToContent : function () { return na_fit(name); },
                beforeRender : function () { if (window.Na__Viewport__Controls) window.Na__Viewport__Controls.na_closeDimensionEditor(); },
                onRender     : function (svg) { na_paint(name, svg); }
            });
            if (!view) return;
            view.na_init();
            na_views[name] = view;
            na_bind_pane(name, view);
        });
    }

    // SUB FUNCTION | Draw One Pane (Fitting It Unless the User Has Zoomed)
    // ---------------------------------------------------------------
    function na_render_pane(name) {
        var view = na_views[name];
        var pane = na_pane(name);
        if (!view || pane.width < NA_MIN_PANE_PX || pane.height < NA_MIN_PANE_PX) return;
        view.na_render(name);
    }

    // SUB FUNCTION | Draw a Pane Again on the Next Frame
    // ---------------------------------------------------------------
    // The engine has just changed the view box (a wheel notch, a fit), so
    // the labels need their new size. Held back while a dimension is being
    // typed: a redraw would take the box away from under the cursor.
    function na_schedule(name) {
        if (na_queued[name]) return;
        na_queued[name] = true;
        var run = function () {
            na_queued[name] = false;
            var wrapper = na_el(NA_PANES[name].wrapperId);
            if (wrapper && wrapper.querySelector('.na-dim-editor')) return;
            na_render_pane(name);
        };
        if (typeof window.requestAnimationFrame === 'function') window.requestAnimationFrame(run);
        else setTimeout(run, 16);
    }

    // -----------------------------------------------------------------------
    // REGION | One pane's events
    // -----------------------------------------------------------------------

    function na_span_of(event) {
        var shape = (event.target && event.target.closest) ? event.target.closest('.na-run-span') : null;
        if (!shape) return null;
        return { leg: Number(shape.getAttribute('data-na-leg')), span: Number(shape.getAttribute('data-na-span')), type: shape.getAttribute('data-na-type') };
    }

    // SUB FUNCTION | Bind a Pane Once: Redraw on Zoom, Select, Menu, Dimensions
    // ---------------------------------------------------------------
    // The engine's own wheel, drag and double click listeners were bound
    // first (na_init), so each of these runs after the view box has moved.
    function na_bind_pane(name, view) {
        var wrapper = na_el(NA_PANES[name].wrapperId);
        var svg     = na_el(NA_PANES[name].svgId);
        var state   = view.na_get_interaction_state();
        if (!wrapper || !svg) return;

        wrapper.addEventListener('wheel', function () { na_schedule(name); }, { passive: true });
        wrapper.addEventListener('dblclick', function () { na_schedule(name); });
        wrapper.addEventListener('mousedown', function (event) { if (event.button === 1) na_schedule(name); });   // <-- A middle double press fits

        svg.addEventListener('click', function (event) {
            if (state.didPan) return;                                            // <-- The end of a drag is not a pick
            if (event.target.closest && event.target.closest('.na-dim-edit')) return;
            if (na_host) na_host.on_select(na_span_of(event));
        });
        svg.addEventListener('contextmenu', function (event) {
            var span = na_span_of(event);
            if (span && na_host) na_host.on_menu(event, span);
        });

        if (window.Na__Viewport__Controls) {
            window.Na__Viewport__Controls.na_setupDimensionEditing(wrapper, svg, state, function (kind, index, text) {
                return na_host ? na_host.on_dimension(kind, index, text) : { ok: false, error: 'The drawing is not ready' };
            });
        }
        if (typeof window.ResizeObserver === 'function') {
            new window.ResizeObserver(function () { na_schedule(name); }).observe(wrapper);
        }
    }

    // -----------------------------------------------------------------------
    // REGION | What the preview shows: Both, Plan, Elevation
    // -----------------------------------------------------------------------

    // HELPER FUNCTION | Forget Any Zoom, So the Next Draw Fits
    // ---------------------------------------------------------------
    function na_release_views() {
        Object.keys(na_views).forEach(function (name) { if (na_views[name]) na_views[name].na_releaseView(); });
    }

    // SUB FUNCTION | Paint the Tab Strip and the Tools From the State
    // ---------------------------------------------------------------
    function na_sync_head() {
        var section = na_el(NA_SECTION_ID);
        if (section) section.setAttribute('data-na-run-view', na_state.view);
        var strip = na_el(NA_VIEWS_ID);
        if (strip) {
            Array.prototype.forEach.call(strip.querySelectorAll('[data-na-run-view]'), function (button) {
                var on = button.getAttribute('data-na-run-view') === na_state.view;
                button.classList.toggle('na-run-view--on', on);
                button.setAttribute('aria-selected', on ? 'true' : 'false');
            });
        }
        var flip = na_el(NA_FLIP_ID);
        if (flip) {
            flip.setAttribute('aria-pressed', na_state.flipped ? 'true' : 'false');
            flip.textContent = na_state.flipped ? 'Flip Back' : 'Flip Out';
            flip.title = na_state.flipped
                ? 'Put the preview back in the column and the dialog back to its width.'
                : 'Open the preview in a large panel on the right of the dialog, to zoom and inspect it. Click again to put it back.';
        }
        var dims = na_el(NA_DIMS_ID);
        if (dims) dims.setAttribute('aria-pressed', na_state.dimensions ? 'true' : 'false');
    }

    // FUNCTION | Show Both Drawings, or One
    // ---------------------------------------------------------------
    // A pane changes size, so each drawing is fitted afresh.
    Na_RunPreview.na_set_view = function (view) {
        if (NA_VIEW_NAMES.indexOf(view) < 0 || view === na_state.view) return;
        na_state.view = view;
        na_sync_head();
        na_release_views();
        Na_RunPreview.na_draw();
    };

    // -----------------------------------------------------------------------
    // REGION | Flip Out: the preview in a panel on the right
    // -----------------------------------------------------------------------

    // SUB FUNCTION | Where the Panel Sits: Under the Top Bar, Right of the Controls
    // ---------------------------------------------------------------
    // The controls keep the width the page had before it flipped out. When
    // the dialog is narrower than that plus a workable panel (it could not
    // grow, or was dragged in), the controls give way, down to their limit.
    function na_place_panel() {
        var root   = document.documentElement;
        var chrome = document.querySelector('.na-top-chrome');
        var wide   = window.innerWidth;
        var left   = Math.min(na_state.baseWidth || wide, wide - NA_FLIP_PANEL_MIN);
        left = Math.max(left, Math.min(NA_FLIP_LEFT_MIN, wide * 0.5));
        root.style.setProperty('--na-run-left', Math.round(left) + 'px');
        root.style.setProperty('--na-run-panel-top', (chrome ? chrome.offsetHeight : 0) + 'px');
    }

    // SUB FUNCTION | After the Dialog Was Asked to Grow: Did It
    // ---------------------------------------------------------------
    function na_settle_panel() {
        if (!na_state.flipped) return;
        na_place_panel();
        if (window.innerWidth < na_state.baseWidth + NA_FLIP_PANEL_MIN && typeof window.na_showStatus === 'function') {
            window.na_showStatus('info', 'Drag the dialog wider to give the flipped-out preview more room.');
        }
    }

    // FUNCTION | Flip the Preview Out to the Right, or Back Into the Column
    // ---------------------------------------------------------------
    // Ruby is told how much wider to make the dialog, in page pixels, with
    // the dialog's present width as the page measures it: it sets the size
    // in its own units in the same proportion.
    Na_RunPreview.na_set_flipped = function (flipped) {
        var on = flipped === true;
        if (on === na_state.flipped) return;
        na_state.flipped = on;

        if (on) {
            var outer = window.outerWidth || window.innerWidth;
            var room  = ((window.screen && window.screen.availWidth) || 0) - ((window.screenX || 0) + outer);
            na_state.baseWidth = window.innerWidth;
            na_place_panel();
            document.body.classList.add(NA_FLIP_CLASS);
            na_send('na_runSetPreviewPanel', { open: true, outer: outer,
                                               extra: Math.round(na_clamp(room - NA_FLIP_EDGE_GAP, NA_FLIP_EXTRA_MIN, NA_FLIP_EXTRA_MAX)) });
            setTimeout(na_settle_panel, NA_FLIP_SETTLE_MS);
        } else {
            document.body.classList.remove(NA_FLIP_CLASS);
            na_send('na_runSetPreviewPanel', { open: false });
        }
        na_sync_head();
        na_release_views();
        Na_RunPreview.na_draw();
    };

    // FUNCTION | The Tab Was Shown or Left
    // ---------------------------------------------------------------
    // The panel belongs to this tab alone. Leaving the tab puts the dialog
    // back to its width; coming back flips the preview out again.
    Na_RunPreview.na_tab_shown = function (shown) {
        if (!shown) {
            na_state.wantFlip = na_state.flipped;
            if (na_state.flipped) Na_RunPreview.na_set_flipped(false);
            return;
        }
        if (na_state.wantFlip) {
            na_state.wantFlip = false;
            Na_RunPreview.na_set_flipped(true);
        }
    };

    // -----------------------------------------------------------------------
    // REGION | Tools: Dimensions, Reset View, the height handle
    // -----------------------------------------------------------------------

    // FUNCTION | Dimensions On or Off (Both Drawings)
    // ---------------------------------------------------------------
    Na_RunPreview.na_set_dimensions = function (on) {
        na_state.dimensions = on === true;
        na_sync_head();
        Na_RunPreview.na_draw();
    };

    // FUNCTION | Fit Both Drawings Again
    // ---------------------------------------------------------------
    Na_RunPreview.na_reset_view = function () {
        na_release_views();
        Na_RunPreview.na_draw();
    };

    // SUB FUNCTION | Drag the Handle Under the Docked Preview to Set Its Height
    // ---------------------------------------------------------------
    function na_bind_height_handle() {
        var handle  = na_el(NA_HANDLE_ID);
        var section = na_el(NA_SECTION_ID);
        if (!handle || !section) return;
        handle.addEventListener('mousedown', function (event) {
            var wrapper = na_el(NA_PANES[na_state.view === 'elevation' ? 'elevation' : 'plan'].wrapperId);
            var start_y = event.clientY;
            var start_h = wrapper ? wrapper.offsetHeight : 250;
            document.body.style.cursor = 'ns-resize';
            event.preventDefault();

            function na_move(move) {
                var height = na_clamp(start_h + move.clientY - start_y, NA_HEIGHT_MIN, NA_HEIGHT_MAX);
                section.style.setProperty('--na-run-preview-height', Math.round(height) + 'px');
            }
            function na_up() {
                window.removeEventListener('mousemove', na_move);
                window.removeEventListener('mouseup', na_up);
                document.body.style.cursor = '';
                Na_RunPreview.na_draw();
            }
            window.addEventListener('mousemove', na_move);
            window.addEventListener('mouseup', na_up);
        });
    }

    // -----------------------------------------------------------------------
    // REGION | Public API
    // -----------------------------------------------------------------------

    // FUNCTION | Draw Both Drawings From the Tab's Present Layout
    // ---------------------------------------------------------------
    Na_RunPreview.na_draw = function () {
        if (!na_host) return;
        na_ensure_views();
        Object.keys(NA_PANES).forEach(na_render_pane);
    };

    // FUNCTION | Bind the Preview's Tabs and Tools (Once) and Take the Tab's Side
    // ---------------------------------------------------------------
    Na_RunPreview.na_init = function (host) {
        na_host = host;
        var strip = na_el(NA_VIEWS_ID);
        if (strip && !strip._na_bound) {
            strip._na_bound = true;
            strip.addEventListener('click', function (event) {
                var button = (event.target && event.target.closest) ? event.target.closest('button') : null;
                if (!button) return;
                if (button.id === NA_FLIP_ID) Na_RunPreview.na_set_flipped(!na_state.flipped);
                else if (button.getAttribute('data-na-run-view')) Na_RunPreview.na_set_view(button.getAttribute('data-na-run-view'));
            });
            var dims = na_el(NA_DIMS_ID);
            if (dims) dims.addEventListener('click', function () { Na_RunPreview.na_set_dimensions(!na_state.dimensions); });
            var reset = na_el(NA_RESET_ID);
            if (reset) reset.addEventListener('click', Na_RunPreview.na_reset_view);
            na_bind_height_handle();
            window.addEventListener('resize', function () { if (na_state.flipped) na_place_panel(); });
        }
        na_sync_head();
    };

    // For the tests that drive the page: a copy of the state.
    Na_RunPreview.na_get_state = function () {
        return { view: na_state.view, flipped: na_state.flipped, dimensions: na_state.dimensions, baseWidth: na_state.baseWidth };
    };

    window.Na_RunPreview = Na_RunPreview;
})();
