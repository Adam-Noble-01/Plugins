// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY - GALLERY TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__AssemblyStudio__PresetsLibrary__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na_PresetsUI
// MODULE     : Presets Library System
// AUTHOR     : Noble Architecture
// CREATED    : 2026
// PURPOSE    : Owns the Presets Gallery tab: toolbar (search / family filter /
//              view toggle / capture), grid + index presentations of preset
//              cards, apply + edit + capture flows, and page-swap navigation
//              between the main tabs and the presets pages.
//
// DESCRIPTION:
// - Mount renders into `#na-presets-body` under `#na-tab-presets`; unmount
//   clears generated nodes only (Settings-tab pattern).
// - Search term, family filter, view mode, and origin tab persist in module
//   state so the gallery survives remounts within a session.
// - Card / table DOM comes from Na__PresetsLibrary__CardRenderer; preset data
//   and apply logic come from Na__PresetsLibrary__Bridge (both typeof-guarded).
// - Applying a preset activates the owning main tab FIRST, then applies via
//   the bridge, then raises a status toast.
//
// NAMING CONVENTION:
// - Aggregate Na_PresetsUI + na_* internal helpers aligned with Noble prefix.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module State & Descriptor Tables
// -----------------------------------------------------------------------------

    var Na_PresetsUI          = {};
    var NA_PANEL_CONTAINER_ID = 'na-tab-presets';                                // <-- host tab pane
    var NA_BODY_CONTAINER_ID  = 'na-presets-body';                               // <-- mutable body subtree
    var NA_CONTENT_HOST_ID    = 'na-presets-content';                            // <-- grid/index swap host
    var NA_DEFAULT_ORIGIN_TAB = 'windows';

    var na_origin_tab_id = NA_DEFAULT_ORIGIN_TAB;                                // 'windows' | 'doors'
    var na_view_mode     = 'grid';                                               // 'grid' | 'index'
    var na_search_term   = '';
    var na_family_filter = '';
    var na_is_mounted    = false;

    var NA_FAMILY_FILTER_OPTIONS = [
        { value : '',             label : 'All Products'   },
        { value : 'Window',       label : 'Windows'        },
        { value : 'ExteriorDoor', label : 'Exterior Doors' },
        { value : 'InteriorDoor', label : 'Interior Doors' }
    ];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Collaborator Guards
// -----------------------------------------------------------------------------

    // FUNCTION | Resolve the presets bridge module (or null)
    // ------------------------------------------------------------
    // @return {Object|null} window.Na__PresetsLibrary__Bridge when loaded.
    function na_get_bridge() {
        return (typeof window.Na__PresetsLibrary__Bridge !== 'undefined')
            ? window.Na__PresetsLibrary__Bridge
            : null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve the stateless card renderer module (or null)
    // ------------------------------------------------------------
    // @return {Object|null} window.Na__PresetsLibrary__CardRenderer when loaded.
    function na_get_card_renderer() {
        return (typeof window.Na__PresetsLibrary__CardRenderer !== 'undefined')
            ? window.Na__PresetsLibrary__CardRenderer
            : null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve the preset editor tab module (or null)
    // ------------------------------------------------------------
    // @return {Object|null} window.Na_PresetEditorUI when loaded.
    function na_get_editor() {
        return (typeof window.Na_PresetEditorUI !== 'undefined')
            ? window.Na_PresetEditorUI
            : null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Route to another tab via the shared TabRouter
    // ------------------------------------------------------------
    // @param {String} tabId - Target tab id ('windows', 'doors', 'presets', ...).
    function na_activate_tab(tabId) {
        if (typeof window.Na_TabRouter !== 'undefined' &&
            typeof window.Na_TabRouter.na_activateTab === 'function') {
            window.Na_TabRouter.na_activateTab(tabId);
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Raise a status-bar toast when the shell exposes one
    // ------------------------------------------------------------
    // @param {String} type    - 'success' | 'info' | 'warning' | 'error'.
    // @param {String} message - Human-readable status text.
    function na_show_status(type, message) {
        if (typeof window.na_showStatus === 'function') {
            window.na_showStatus(type, message);
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Current cached preset records from the bridge
    // ------------------------------------------------------------
    // @return {Array} Preset records ([] when bridge/cache unavailable).
    function na_get_library_records() {
        var bridge = na_get_bridge();
        if (!bridge || typeof bridge.na_get_presets !== 'function') return [];
        return bridge.na_get_presets() || [];
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM — Panel & Body Container
// -----------------------------------------------------------------------------

    // FUNCTION | Return the HtmlDialog `#na-tab-presets` root
    // ------------------------------------------------------------
    function na_get_panel_container() {
        return document.getElementById(NA_PANEL_CONTAINER_ID);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Locate or lazily instantiate the scrolling body subtree
    // ------------------------------------------------------------
    function na_get_or_create_body_container() {
        var existing = document.getElementById(NA_BODY_CONTAINER_ID);
        if (existing) return existing;
        var panel = na_get_panel_container();
        if (!panel) return null;
        var body = document.createElement('div');
        body.id        = NA_BODY_CONTAINER_ID;
        body.className = 'na-presets-body';
        panel.appendChild(body);
        return body;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Return the grid/index content host (null pre-mount)
    // ------------------------------------------------------------
    function na_get_content_host() {
        return document.getElementById(NA_CONTENT_HOST_ID);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Toolbar Builders
// -----------------------------------------------------------------------------

    // FUNCTION | Label for the view toggle (names the view you SWITCH TO)
    // ------------------------------------------------------------
    // @return {String} 'Index View' while in grid mode, else 'Grid View'.
    function na_view_toggle_label() {
        return (na_view_mode === 'grid') ? 'Index View' : 'Grid View';
    }
    // ---------------------------------------------------------------

    // FUNCTION | Compose the search / filter / toggle / capture toolbar row
    // ------------------------------------------------------------
    // @return {HTMLElement} div.na-presets-gallery__toolbar.
    function na_build_toolbar() {
        var toolbar = document.createElement('div');
        toolbar.className = 'na-presets-gallery__toolbar';

        var search = document.createElement('input');
        search.type        = 'text';
        search.id          = 'na-presets-search';
        search.className   = 'na-presets-gallery__search';
        search.placeholder = 'Search presets…';
        search.value       = na_search_term;
        search.addEventListener('input', function () {
            na_search_term = search.value;
            na_render_content();
        });
        toolbar.appendChild(search);

        var filter = document.createElement('select');
        filter.id        = 'na-presets-family-filter';
        filter.className = 'na-presets-gallery__filter';
        NA_FAMILY_FILTER_OPTIONS.forEach(function (descriptor) {
            var option = document.createElement('option');
            option.value       = descriptor.value;
            option.textContent = descriptor.label;
            filter.appendChild(option);
        });
        filter.value = na_family_filter;
        filter.addEventListener('change', function () {
            na_family_filter = filter.value;
            na_render_content();
        });
        toolbar.appendChild(filter);

        var toggle = document.createElement('button');
        toggle.type        = 'button';
        toggle.id          = 'na-presets-view-toggle';
        toggle.className   = 'na-btn na-btn-secondary na-presets-gallery__view-toggle';
        toggle.textContent = na_view_toggle_label();
        toggle.addEventListener('click', function () {
            na_view_mode       = (na_view_mode === 'grid') ? 'index' : 'grid';
            toggle.textContent = na_view_toggle_label();
            na_render_content();
        });
        toolbar.appendChild(toggle);

        var capture = document.createElement('button');
        capture.type        = 'button';
        capture.id          = 'na-btn-presets-capture';
        capture.className   = 'na-btn na-btn-primary na-presets-gallery__capture-btn';
        capture.textContent = 'Capture Current Design';
        capture.addEventListener('click', na_begin_capture);
        toolbar.appendChild(capture);

        return toolbar;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Content Rendering (Grid / Index / Empty States)
// -----------------------------------------------------------------------------

    // FUNCTION | One centred muted empty-state message block
    // ------------------------------------------------------------
    // @param  {String} message - Empty-state copy.
    // @return {HTMLElement} p.na-presets-gallery__empty.
    function na_build_empty_state(message) {
        var empty = document.createElement('p');
        empty.className   = 'na-presets-gallery__empty';
        empty.textContent = message;
        return empty;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Re-render the content host from cache + current filters
    // ------------------------------------------------------------
    function na_render_content() {
        var host = na_get_content_host();
        if (!host) return;
        host.innerHTML = '';

        var renderer = na_get_card_renderer();
        if (!renderer) return;

        var records = na_get_library_records();
        if (!records.length) {
            host.appendChild(na_build_empty_state('No presets yet — click Capture Current Design to save your first preset.'));
            return;
        }

        var filtered = renderer.na_filter_and_sort(records, na_search_term, na_family_filter);
        if (!filtered.length) {
            host.appendChild(na_build_empty_state('No presets match the current filter.'));
            return;
        }

        var handlers = {
            onApply : na_apply_preset,
            onEdit  : na_edit_preset
        };

        if (na_view_mode === 'index') {
            host.appendChild(renderer.na_build_index_table(filtered, handlers));
        } else {
            var grid = document.createElement('div');
            grid.className = 'na-presets-gallery__grid';
            filtered.forEach(function (record) {
                grid.appendChild(renderer.na_build_card(record, handlers));
            });
            host.appendChild(grid);
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Recompose the entire mutable body subtree
    // ------------------------------------------------------------
    function na_render_body() {
        var body = na_get_or_create_body_container();
        if (!body) return;
        body.innerHTML = '';
        body.appendChild(na_build_toolbar());

        var content = document.createElement('div');
        content.id        = NA_CONTENT_HOST_ID;
        content.className = 'na-presets-gallery__content';
        body.appendChild(content);

        na_render_content();
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Apply / Edit / Capture Flows
// -----------------------------------------------------------------------------

    // FUNCTION | Apply one preset: route to its main tab, then populate
    // ------------------------------------------------------------
    // @param {Object} record - Preset record (bridge shape).
    function na_apply_preset(record) {
        if (!record) return;
        var bridge = na_get_bridge();
        if (!bridge) {
            na_show_status('error', 'Presets bridge unavailable — cannot apply preset.');
            return;
        }

        if (record.productFamily === 'InteriorDoor') {
            na_activate_tab('doors');
            if (typeof bridge.na_apply_interior_door_preset === 'function') {
                bridge.na_apply_interior_door_preset(record);
            }
        } else {
            na_activate_tab('windows');
            if (typeof bridge.na_apply_window_family_preset === 'function') {
                bridge.na_apply_window_family_preset(record);
            }
        }

        na_show_status('success', 'Preset ' + String(record.presetCode || '') + ' — ' + String(record.displayName || '') + ' applied.');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Jump to the editor with this preset pre-selected
    // ------------------------------------------------------------
    // @param {Object} record - Preset record (bridge shape).
    function na_edit_preset(record) {
        if (!record) return;
        var editor = na_get_editor();
        if (editor && typeof editor.na_set_selected_preset === 'function') {
            editor.na_set_selected_preset(record.presetCode);
        }
        na_activate_tab('preset_editor');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Capture current design and hand off to editor create mode
    // ------------------------------------------------------------
    function na_begin_capture() {
        var bridge = na_get_bridge();
        if (!bridge || typeof bridge.na_capture_current_design !== 'function') {
            na_show_status('error', 'Presets bridge unavailable — cannot capture the current design.');
            return;
        }

        var pendingCapture = bridge.na_capture_current_design(na_origin_tab_id);
        if (!pendingCapture) {
            na_show_status('error', 'Could not capture the current design — check the active configuration and try again.');
            return;
        }

        var editor = na_get_editor();
        if (editor && typeof editor.na_enter_create_mode === 'function') {
            editor.na_enter_create_mode();
        }
        na_activate_tab('preset_editor');
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API — Navigation & Mount Contract
// -----------------------------------------------------------------------------

    // FUNCTION | Enter the presets pages from a main-tab header button
    // ------------------------------------------------------------
    // @param {String} originTabId - 'windows' | 'doors' (defaults 'windows').
    Na_PresetsUI.na_open_from_main = function (originTabId) {
        na_origin_tab_id = (originTabId === 'doors') ? 'doors' : NA_DEFAULT_ORIGIN_TAB;
        na_activate_tab('presets');
    };
    // ---------------------------------------------------------------

    // FUNCTION | Leave the presets pages back to the originating tab
    // ------------------------------------------------------------
    Na_PresetsUI.na_navigate_back = function () {
        na_activate_tab(na_origin_tab_id || NA_DEFAULT_ORIGIN_TAB);
    };
    // ---------------------------------------------------------------

    // FUNCTION | First paint / reopen hook (re-requests an empty cache)
    // ------------------------------------------------------------
    Na_PresetsUI.na_mount = function (_initialConfig) {
        na_is_mounted = true;
        na_render_body();
        var bridge = na_get_bridge();
        if (bridge && !na_get_library_records().length &&
            typeof bridge.na_request_library === 'function') {
            bridge.na_request_library();
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Tab tear-down clears generated nodes only
    // ------------------------------------------------------------
    Na_PresetsUI.na_unmount = function () {
        na_is_mounted = false;
        var body = document.getElementById(NA_BODY_CONTAINER_ID);
        if (body) body.innerHTML = '';
    };
    // ---------------------------------------------------------------

    // FUNCTION | Bridge ping after a fresh library push re-paints content
    // ------------------------------------------------------------
    Na_PresetsUI.na_on_library_updated = function () {
        if (!na_is_mounted) return;
        na_render_content();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Tab-visible refresh ping (delegates na_render_body)
    // ------------------------------------------------------------
    Na_PresetsUI.na_render = function (_config) {
        if (na_is_mounted) na_render_body();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Presets tab emits no persisted config payload
    // ------------------------------------------------------------
    Na_PresetsUI.na_get_active_config = function () {
        return null;
    };
    // ---------------------------------------------------------------

    window.Na_PresetsUI = Na_PresetsUI;

    console.log('[NA_PRESETS_UI] Presets Gallery tab UiLogic mounted contract ready');

// endregion -------------------------------------------------------------------

})();
