// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Cabinetry__UiSystem__MainUiLogic__.js
// NAMESPACE  : Na_CabinetUI (browser global; TabRouter maps 'cabinets' to it)
// AUTHOR     : Noble Architecture
// PURPOSE    : Mounts the Cabinetry tab: builds every control with the shared
//              Na__Ui__Controls / Na__Ui__Events engine, keeps the working
//              configuration, repaints the elevation and section previews,
//              and sends Live Mode and placement updates to Ruby.
// CREATED    : 29-Oct-2026
//
// PUBLIC API
//   Na_CabinetUI.na_mount(payload)            build controls, bind, render
//   Na_CabinetUI.na_unmount()                 clear the build containers
//   Na_CabinetUI.na_render()                  repaint both previews
//   Na_CabinetUI.na_get_active_config()       root payload for Ruby
//   Na_CabinetUI.na_get_ui_config()           flat config the layout reads
//   Na_CabinetUI.na_set_active_config(payload) take a saved / loaded config
//   Na_CabinetUI.na_apply_control_value(id, v) one value from outside
//   Na_CabinetUI.na_apply_values(map)         several at once (product chips)
//   Na_CabinetUI.na_rebuild_finish_controls() swatches arrived from Ruby
//   Na_CabinetUI.na_set_select_options(id, options) asset lists from Ruby
//   Na_CabinetUI.na_toggle_interior()         fronts see-through in the preview
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Na_CabinetUI = {};
    var K            = 'Na__CabinetConfig__';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var NA_LIVE_DEBOUNCE_MS  = 150;                                           // <-- Matches the door and window live cadence
    var NA_TAB_ID            = 'cabinets';
    var NA_CONTAINERS = [
        ['na-cab-controls-product',  'NA_CABINET_PRODUCT_CONFIG'],
        ['na-cab-controls-size',     'NA_CABINET_SIZE_CONFIG'],
        ['na-cab-controls-fronts',   'NA_CABINET_FRONTS_CONFIG'],
        ['na-cab-controls-interior', 'NA_CABINET_INTERIOR_CONFIG'],
        ['na-cab-controls-carcass',  'NA_CABINET_CARCASS_CONFIG'],
        ['na-cab-controls-plinth',   'NA_CABINET_PLINTH_CONFIG'],
        ['na-cab-controls-hardware', 'NA_CABINET_HARDWARE_CONFIG'],
        ['na-cab-controls-finish',   'NA_CABINET_FINISH_CONFIG'],
        ['na-cab-controls-output',   'NA_CABINET_OUTPUT_CONFIG']
    ];

    var na_active_config    = na_build_default_config();                     // <-- Flat Na__CabinetConfig__* map
    var na_active_metadata  = na_build_default_metadata();
    var na_listeners        = [];                                             // <-- Called after every change (layout, search)
    var na_layout_bound     = false;
    var na_render_pending   = false;
    var na_live_timer       = null;
    var na_elevation_view   = null;
    var na_section_view     = null;
    var na_show_interior    = false;                                          // <-- Preview only: fronts drawn see-through

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Defaults
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Every Descriptor, Flattened
    // ------------------------------------------------------------
    function na_all_descriptors() {
        var out = [];
        NA_CONTAINERS.forEach(function (pair) {
            (window[pair[1]] || []).forEach(function (descriptor) { if (descriptor && descriptor.id) out.push(descriptor); });
        });
        return out;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Find One Descriptor by Id
    // ------------------------------------------------------------
    function na_descriptor(id) {
        return na_all_descriptors().filter(function (descriptor) { return descriptor.id === id; })[0] || null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Descriptor Defaults as a Flat Config
    // ------------------------------------------------------------
    function na_build_default_config() {
        var config = {};
        na_all_descriptors().forEach(function (descriptor) { config[descriptor.id] = descriptor.default; });
        return config;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Fresh Metadata Block (Mirrors the Ruby Defaults)
    // ------------------------------------------------------------
    function na_build_default_metadata() {
        return {
            'Na__Cabinet__UniqueId'      : null,
            'Na__Cabinet__Name'          : 'New Cabinet',
            'Na__Cabinet__ComponentName' : '',
            'Na__Cabinet__Description'   : '',
            'Na__Cabinet__Notes'         : 'Created with Element Assembly Studio Pro',
            'Na__Cabinet__CreatedDate'   : null,
            'Na__Cabinet__LastModified'  : null
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Building Controls (Shared Engine)
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Build One Container's Controls at Their Current Values
    // ------------------------------------------------------------
    function na_build_container(containerId, descriptors) {
        var container = document.getElementById(containerId);
        if (!container || !window.Na__Ui__Controls || !window.Na__Ui__Events) return;
        container.innerHTML = '';
        (descriptors || []).forEach(function (descriptor) {
            container.insertAdjacentHTML('beforeend', window.Na__Ui__Controls.na_createControl(na_render_descriptor(descriptor)));
        });
        (descriptors || []).forEach(function (descriptor) {
            window.Na__Ui__Events.na_attachEventListeners(na_render_descriptor(descriptor), na_on_control_change);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | A Descriptor Copy Whose Default Is the Current Value
    // ------------------------------------------------------------
    function na_render_descriptor(descriptor) {
        var value = na_active_config[descriptor.id];
        return Object.assign({}, descriptor, { default: (value === undefined) ? descriptor.default : value, unit: descriptor.unit || '' });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Show a Value in Its Control Without Firing Its Events
    // ------------------------------------------------------------
    function na_set_control_dom(id, value) {
        var descriptor = na_descriptor(id);
        if (!descriptor) return;
        var arithmetic = window.Na__Utils__Arithmetic;
        switch (descriptor.type) {
            case 'slider': {
                var slider  = document.getElementById(id + '-slider');
                var input   = document.getElementById(id + '-input');
                var display = document.getElementById(id + '-display');
                var text    = arithmetic ? arithmetic.na_format(Number(value)) : String(value);
                if (slider)  slider.value = value;
                if (input)   input.value = text;
                if (display) display.textContent = text + (descriptor.unit || '');
                break;
            }
            case 'toggle': {
                var toggle = document.getElementById(id + '-toggle');
                if (!toggle) break;
                toggle.dataset.value = value ? 'true' : 'false';
                toggle.classList.toggle('na-active', !!value);
                break;
            }
            case 'binary_toggle': {
                var binary = document.getElementById(id + '-btoggle');
                if (!binary) break;
                var isRight = String(value) === binary.getAttribute('data-right-value');
                binary.setAttribute('data-value', value);
                binary.classList.toggle('na-binary-toggle--right', isRight);
                binary.classList.toggle('na-binary-toggle--left', !isRight);
                break;
            }
            case 'multiway_toggle': {
                var group = document.getElementById(id + '-segmented');
                if (!group) break;
                group.setAttribute('data-value', value);
                group.querySelectorAll('.na-segmented-toggle__option').forEach(function (button) {
                    button.classList.toggle('na-segmented-toggle__option--active', button.getAttribute('data-option-value') === String(value));
                });
                break;
            }
            case 'select': {
                var select = document.getElementById(id + '-select');
                if (select) select.value = value;
                break;
            }
            case 'material_cards': {
                var cards = document.getElementById(id + '-cards');
                if (!cards) break;
                cards.querySelectorAll('.na-material-card').forEach(function (card) {
                    card.classList.toggle('na-material-card-selected', card.getAttribute('data-material-id') === value);
                });
                break;
            }
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Change Handling
// -----------------------------------------------------------------------------

    // SUB FUNCTION | A Control Changed
    // ------------------------------------------------------------
    function na_on_control_change(id, value) {
        na_active_config[id] = value;
        na_after_change();
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Repaint, Tell the Layout, and Send the Change on to Ruby
    // ------------------------------------------------------------
    function na_after_change() {
        na_notify();
        na_schedule_render();
        na_schedule_live();
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Tell Every Listener the Config Moved
    // ------------------------------------------------------------
    function na_notify() {
        na_listeners.forEach(function (listener) {
            try { listener(na_active_config); }
            catch (err) { console.error('[Na_CabinetUI] Change listener failed:', err); }
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | One Preview Repaint per Frame
    // ------------------------------------------------------------
    function na_schedule_render() {
        if (na_render_pending) return;
        na_render_pending = true;
        window.requestAnimationFrame(function () {
            na_render_pending = false;
            Na_CabinetUI.na_render();
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Debounced Live Update and Placement Sync
    // ------------------------------------------------------------
    // Live Mode rebuilds the selected cabinet; while Create at Cursor is
    // placing units, the next click uses the changed settings.
    function na_schedule_live() {
        if (na_live_timer) clearTimeout(na_live_timer);
        na_live_timer = setTimeout(function () {
            na_live_timer = null;
            var payload = na_build_payload();
            if (typeof window.na_cabinetLiveUpdateRequested === 'function') window.na_cabinetLiveUpdateRequested(payload);
            if (typeof window.na_cabinetPlacementSyncRequested === 'function') window.na_cabinetPlacementSyncRequested(payload);
        }, NA_LIVE_DEBOUNCE_MS);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Previews
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Create the Elevation and Section Viewports on Demand
    // ------------------------------------------------------------
    function na_ensure_views() {
        if (!window.Na__Viewport__Instance) return;
        if (!na_elevation_view && window.Na_CabinetElevationGenerator) {
            na_elevation_view = window.Na__Viewport__Instance.na_create({
                wrapperId    : 'na-cab-elevation-wrapper',
                svgId        : 'na-cab-elevation-svg',
                fitToContent : window.Na_CabinetElevationGenerator.na_fit_to_content,
                onRender     : function (svg, cfg) { window.Na_CabinetElevationGenerator.na_render(svg, cfg, { interior: na_show_interior }); }
            });
            if (na_elevation_view) na_elevation_view.na_init();
        }
        if (!na_section_view && window.Na_CabinetSectionGenerator) {
            na_section_view = window.Na__Viewport__Instance.na_create({
                wrapperId    : 'na-cab-section-wrapper',
                svgId        : 'na-cab-section-svg',
                fitToContent : window.Na_CabinetSectionGenerator.na_fit_to_content,
                onRender     : function (svg, cfg) { window.Na_CabinetSectionGenerator.na_render(svg, cfg); }
            });
            if (na_section_view) na_section_view.na_init();
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Repaint Both Previews
    // ------------------------------------------------------------
    Na_CabinetUI.na_render = function () {
        na_ensure_views();
        if (na_elevation_view) na_elevation_view.na_render(na_active_config);
        if (na_section_view)   na_section_view.na_render(na_active_config);
        na_render_warnings();
    };
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Show the Layout's Warnings Under the Preview
    // ------------------------------------------------------------
    function na_render_warnings() {
        var host = document.getElementById('na-cab-preview-warnings');
        var resolver = window.Na__Cabinetry__LayoutResolver;
        if (!host || !resolver) return;
        var warnings = resolver.na_resolve(na_active_config).warnings;
        host.hidden = warnings.length === 0;
        host.textContent = warnings.join(' ');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Fit Both Previews Again (Reset View)
    // ------------------------------------------------------------
    Na_CabinetUI.na_reset_view = function () {
        na_ensure_views();
        if (na_elevation_view) na_elevation_view.na_resetView(na_active_config);
        if (na_section_view)   na_section_view.na_resetView(na_active_config);
    };
    // ---------------------------------------------------------------

    // FUNCTION | Draw the Fronts See-Through in the Elevation (Preview Only)
    // ------------------------------------------------------------
    Na_CabinetUI.na_toggle_interior = function () {
        na_show_interior = !na_show_interior;
        var button = document.getElementById('na-btn-cab-interior');
        if (button) button.setAttribute('aria-pressed', na_show_interior ? 'true' : 'false');
        Na_CabinetUI.na_render();
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Mount / Unmount
// -----------------------------------------------------------------------------

    // FUNCTION | Build Every Control, Hand Them to the Layout, Render
    // ------------------------------------------------------------
    Na_CabinetUI.na_mount = function (payload) {
        if (payload) Na_CabinetUI.na_set_active_config(payload);
        var layout = window.Na__Ui__SectionLayout;
        if (layout && typeof layout.na_clear === 'function') layout.na_clear(NA_TAB_ID);

        NA_CONTAINERS.forEach(function (pair) { na_build_container(pair[0], window[pair[1]]); });

        if (layout && layout.na_get_spec(NA_TAB_ID)) {
            layout.na_mount(NA_TAB_ID);
            if (!na_layout_bound) {
                na_layout_bound = true;
                Na_CabinetUI.na_add_change_listener(function () { layout.na_request_refresh(NA_TAB_ID); });
                if (window.Na__Ui__ParameterSearch) window.Na__Ui__ParameterSearch.na_bind(NA_TAB_ID);
            }
        }
        if (typeof window.na_requestCabinetAssetOptions === 'function') window.na_requestCabinetAssetOptions();
        na_sync_info_strip();
        Na_CabinetUI.na_render();
        na_notify();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Clear the Build Containers (Leaving the Tab)
    // ------------------------------------------------------------
    Na_CabinetUI.na_unmount = function () {
        var layout = window.Na__Ui__SectionLayout;
        if (layout && typeof layout.na_clear === 'function') layout.na_clear(NA_TAB_ID);
        NA_CONTAINERS.forEach(function (pair) {
            var container = document.getElementById(pair[0]);
            if (container) container.innerHTML = '';
        });
        na_elevation_view = null;
        na_section_view   = null;
    };
    // ---------------------------------------------------------------

    // FUNCTION | Register a Callback Run After Every Change
    // ------------------------------------------------------------
    Na_CabinetUI.na_add_change_listener = function (listener) {
        if (typeof listener === 'function') na_listeners.push(listener);
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Config In and Out
// -----------------------------------------------------------------------------

    // FUNCTION | The Root Payload Ruby Builds From
    // ------------------------------------------------------------
    function na_build_payload() {
        return {
            'Na__CabinetMetadata'      : [Object.assign({}, na_active_metadata)],
            'Na__CabinetComponents'    : [],
            'Na__CabinetConfiguration' : Object.assign({}, na_active_config)
        };
    }
    Na_CabinetUI.na_get_active_config = na_build_payload;
    // ---------------------------------------------------------------

    // FUNCTION | The Flat Config the Layout and Search Read
    // ------------------------------------------------------------
    Na_CabinetUI.na_get_ui_config = function () {
        return Object.assign({}, na_active_config);
    };
    // ---------------------------------------------------------------

    // FUNCTION | Take a Root Payload (or a Bare Configuration Block)
    // ------------------------------------------------------------
    // Unknown keys are kept (the Ruby-only leg finish rides through).
    Na_CabinetUI.na_set_active_config = function (payload) {
        if (!payload) return;
        var block    = payload['Na__CabinetConfiguration'] || payload;
        var metadata = payload['Na__CabinetMetadata'];
        na_active_config = Object.assign(na_build_default_config(), block);
        if (Array.isArray(metadata) && metadata[0]) na_active_metadata = Object.assign(na_build_default_metadata(), metadata[0]);
        na_sync_info_strip();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Apply One Value From Outside Its Control
    // ------------------------------------------------------------
    Na_CabinetUI.na_apply_control_value = function (id, value) {
        var map = {};
        map[id] = value;
        Na_CabinetUI.na_apply_values(map);
    };
    // ---------------------------------------------------------------

    // FUNCTION | Apply Several Values at Once (Product Chips, Presets)
    // ------------------------------------------------------------
    Na_CabinetUI.na_apply_values = function (map) {
        if (!map || typeof map !== 'object') return;
        Object.keys(map).forEach(function (id) {
            na_active_config[id] = map[id];
            na_set_control_dom(id, map[id]);
        });
        na_after_change();
    };
    Na_CabinetUI.na_apply_config_change = Na_CabinetUI.na_apply_values;
    // ---------------------------------------------------------------

    // FUNCTION | Clear the Edit State (Nothing Selected), Keeping the Design
    // ------------------------------------------------------------
    // Unlike a deselected door, the settings stay: a fitter places the
    // same unit again straight after clicking away.
    Na_CabinetUI.na_clear_edit_state = function () {
        na_active_metadata = na_build_default_metadata();
        na_sync_info_strip();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Back to the UK Defaults (Presets Apply From Here)
    // ------------------------------------------------------------
    Na_CabinetUI.na_reset_to_default = function () {
        na_active_config   = na_build_default_config();
        na_active_metadata = na_build_default_metadata();
        if (window.Na_AppContext && window.Na_AppContext.na_is_active_tab(NA_TAB_ID)) Na_CabinetUI.na_mount();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Replace a Select's Options (Asset Lists From Ruby)
    // ------------------------------------------------------------
    Na_CabinetUI.na_set_select_options = function (id, options) {
        var descriptor = na_descriptor(id);
        if (!descriptor || !Array.isArray(options) || !options.length) return;
        descriptor.options = options;
        if (!options.some(function (option) { return option.value === na_active_config[id]; })) {
            na_active_config[id] = descriptor.default;
            if (!options.some(function (option) { return option.value === descriptor.default; })) na_active_config[id] = options[0].value;
        }
        var select = document.getElementById(id + '-select');
        if (select) {
            select.innerHTML = options.map(function (option) {
                return '<option value="' + option.value + '">' + option.label + '</option>';
            }).join('');
            select.value = na_active_config[id];
        }
        na_notify();
        na_schedule_render();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Rebuild the Swatch Rows Once Ruby Has Pushed the Palettes
    // ------------------------------------------------------------
    Na_CabinetUI.na_rebuild_finish_controls = function () {
        if (!window.Na__Ui__Controls) return;
        na_all_descriptors().filter(function (descriptor) { return descriptor.type === 'material_cards'; }).forEach(function (descriptor) {
            var existing = document.querySelector('[data-control-id="' + descriptor.id + '"]');
            if (!existing) return;
            existing.outerHTML = window.Na__Ui__Controls.na_createControl(na_render_descriptor(descriptor));
            window.Na__Ui__Events.na_attachEventListeners(na_render_descriptor(descriptor), na_on_control_change);
        });
        na_notify();
        na_schedule_render();
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Selected Cabinet Strip (Id, Dates, Name, Description)
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Show or Hide the Strip and Fill Its Fields
    // ------------------------------------------------------------
    function na_sync_info_strip() {
        var strip = document.getElementById('na-cab-info');
        if (!strip) return;
        var id = na_active_metadata['Na__Cabinet__UniqueId'];
        strip.classList.toggle('na-hidden', !id);
        na_set_text('na-info-cab-id', id || '-');
        na_set_text('na-info-cab-created', na_active_metadata['Na__Cabinet__CreatedDate'] || '-');
        na_set_text('na-info-cab-modified', na_active_metadata['Na__Cabinet__LastModified'] || '-');
        na_set_value('na-info-cab-name', na_active_metadata['Na__Cabinet__ComponentName'] || '');
        na_set_value('na-info-cab-description', na_active_metadata['Na__Cabinet__Description'] || '');
    }
    // ---------------------------------------------------------------

    function na_set_text(id, text) { var el = document.getElementById(id); if (el) el.textContent = text; }
    function na_set_value(id, value) { var el = document.getElementById(id); if (el && document.activeElement !== el) el.value = value; }

    // HELPER FUNCTION | Wire the Strip's Fields Once
    // ------------------------------------------------------------
    // Enter in Name renames the selected cabinet straight away; both fields
    // also travel with the next Create, Update or Live Mode rebuild.
    function na_bind_info_strip() {
        var name = document.getElementById('na-info-cab-name');
        var description = document.getElementById('na-info-cab-description');
        if (name) {
            name.addEventListener('input', function () { na_active_metadata['Na__Cabinet__ComponentName'] = name.value; });
            name.addEventListener('keydown', function (event) {
                if (event.key !== 'Enter') return;
                event.preventDefault();
                if (typeof window.na_renameCabinet === 'function') window.na_renameCabinet(name.value);
            });
        }
        if (description) {
            description.addEventListener('input', function () { na_active_metadata['Na__Cabinet__Description'] = description.value; });
        }
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', na_bind_info_strip);
    else na_bind_info_strip();
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------

    window.Na_CabinetUI = Na_CabinetUI;

})();

// =============================================================================
// END OF FILE
// =============================================================================
