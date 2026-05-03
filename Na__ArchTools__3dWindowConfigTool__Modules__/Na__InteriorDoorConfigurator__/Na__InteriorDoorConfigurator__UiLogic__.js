// =============================================================================
// NA INTERIOR DOOR CONFIGURATOR - DOOR TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__InteriorDoorConfigurator__UiLogic__.js
// NAMESPACE  : Na_DoorUI (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Mounts the Interior Doors tab UI: dynamic controls,
//              event wiring, and dual-viewport rendering on every
//              configuration change.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Public API:
//     Na_DoorUI.na_mount(initialConfig)        -> Build controls, bind events, render.
//     Na_DoorUI.na_unmount()                   -> Detach listeners and clear DOM state.
//     Na_DoorUI.na_render(config)              -> Force a viewport refresh.
//     Na_DoorUI.na_get_active_config()         -> Return the current door config snapshot.
//     Na_DoorUI.na_set_active_config(payload)  -> Apply an external config (selection load).
// - Lives behind the TabRouter: na_mount() runs when the user switches
//   to the Interior Doors tab; na_unmount() runs when they leave it.
//
// NAMING CONVENTION:
// - All identifiers use Na_ / na_ prefix.
//
// =============================================================================


(function () {
    'use strict';

    var Na_DoorUI = {};


// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var na_active_config        = na_build_default_door_config();             // <-- Working config snapshot (Na__DoorConfiguration shape)
    var na_active_metadata      = na_build_default_door_metadata();           // <-- Metadata block (Na__DoorMetadata)
    var na_change_listeners     = [];                                         // <-- Per-mount cleanup callbacks
    var na_rerender_pending     = false;                                      // <-- requestAnimationFrame batching guard
    var na_live_update_timeout  = null;                                       // <-- Debounce id for live updates

    var na_plan_instance        = null;                                       // <-- Na__Viewport__Instance for plan view
    var na_elevation_instance   = null;                                       // <-- Na__Viewport__Instance for elevation view

    var NA_LIVE_UPDATE_DEBOUNCE_MS = 150;                                     // <-- Mirrors window-tool live-update cadence

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Default Configuration Builders
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Build the Default Na__DoorConfiguration Object
    // ------------------------------------------------------------
    // Iterates every descriptor array exported by the door config
    // module and copies its `default` into a plain config object.
    function na_build_default_door_config() {
        var defaults = {};
        var sources  = na_collect_descriptor_arrays();
        sources.forEach(function (arr) {
            (arr || []).forEach(function (descriptor) {
                if (descriptor && descriptor.id) {
                    defaults[descriptor.id] = descriptor.default;
                }
            });
        });
        return defaults;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Build the Default Na__DoorMetadata Block
    // ------------------------------------------------------------
    function na_build_default_door_metadata() {
        return {
            'Na__Door__UniqueId'     : null,
            'Na__Door__Name'         : 'New Interior Door',
            'Na__Door__Description'  : '',
            'Na__Door__Notes'        : 'Created with Na Interior Door Configurator',
            'Na__Door__CreatedDate'  : null,
            'Na__Door__LastModified' : null
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Collect All Door Tab Descriptor Arrays
    // ------------------------------------------------------------
    function na_collect_descriptor_arrays() {
        return [
            window.NA_DOOR_OPENING_CONFIG,
            window.NA_DOOR_PANEL_TAB_CONFIG,
            window.NA_DOOR_ARCHITRAVE_CONFIG,
            window.NA_DOOR_HANDLE_CONFIG,
            window.NA_DOOR_OPTIONS_CONFIG
        ];
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Control HTML Builders
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Create a Slider Control DOM Subtree
    // ------------------------------------------------------------
    function na_build_slider_control(descriptor, currentValue) {
        var wrapper = document.createElement('div');
        wrapper.className                 = 'na-control-item';
        wrapper.setAttribute('data-control-id', descriptor.id);

        var label                         = document.createElement('div');
        label.className                   = 'na-control-label';
        var labelSpan                     = document.createElement('span');
        labelSpan.textContent             = descriptor.label;
        var valueSpan                     = document.createElement('span');
        valueSpan.className               = 'na-control-value';
        valueSpan.id                      = descriptor.id + '-display';
        valueSpan.textContent             = currentValue + (descriptor.unit || '');
        label.appendChild(labelSpan);
        label.appendChild(valueSpan);

        var sliderContainer               = document.createElement('div');
        sliderContainer.className         = 'na-slider-container';

        var range                         = document.createElement('input');
        range.type                        = 'range';
        range.className                   = 'na-slider';
        range.id                          = descriptor.id + '-slider';
        range.min                         = descriptor.min;
        range.max                         = descriptor.max;
        range.step                        = descriptor.step;
        range.value                       = currentValue;

        var number                        = document.createElement('input');
        number.type                       = 'number';
        number.className                  = 'na-slider-input';
        number.id                         = descriptor.id + '-input';
        number.min                        = descriptor.min;
        number.max                        = descriptor.max;
        number.step                       = descriptor.step;
        number.value                      = currentValue;

        sliderContainer.appendChild(range);
        sliderContainer.appendChild(number);

        wrapper.appendChild(label);
        wrapper.appendChild(sliderContainer);

        var onSlide = function () {
            number.value = range.value;
            valueSpan.textContent = range.value + (descriptor.unit || '');
            na_handle_control_change(descriptor.id, Number(range.value));
        };
        var onType = function () {
            range.value = number.value;
            valueSpan.textContent = number.value + (descriptor.unit || '');
            na_handle_control_change(descriptor.id, Number(number.value));
        };
        range.addEventListener('input', onSlide);
        number.addEventListener('input', onType);

        na_change_listeners.push(function () {
            range.removeEventListener('input', onSlide);
            number.removeEventListener('input', onType);
        });

        return wrapper;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Create a Select Control DOM Subtree
    // ------------------------------------------------------------
    function na_build_select_control(descriptor, currentValue) {
        var wrapper                       = document.createElement('div');
        wrapper.className                 = 'na-control-item';
        wrapper.setAttribute('data-control-id', descriptor.id);

        var label                         = document.createElement('div');
        label.className                   = 'na-control-label';
        var labelSpan                     = document.createElement('span');
        labelSpan.textContent             = descriptor.label;
        label.appendChild(labelSpan);

        var select                        = document.createElement('select');
        select.id                         = descriptor.id + '-select';
        select.className                  = 'na-select';
        (descriptor.options || []).forEach(function (option) {
            var opt                       = document.createElement('option');
            opt.value                     = option.value;
            opt.textContent               = option.label;
            if (option.value === currentValue) opt.selected = true;
            select.appendChild(opt);
        });

        wrapper.appendChild(label);
        wrapper.appendChild(select);

        var onChange = function () {
            na_handle_control_change(descriptor.id, select.value);
        };
        select.addEventListener('change', onChange);
        na_change_listeners.push(function () {
            select.removeEventListener('change', onChange);
        });

        return wrapper;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Create a Checkbox Control DOM Subtree
    // ------------------------------------------------------------
    function na_build_checkbox_control(descriptor, currentValue) {
        var wrapper                       = document.createElement('div');
        wrapper.className                 = 'na-control-item';
        wrapper.setAttribute('data-control-id', descriptor.id);

        var toggleContainer               = document.createElement('div');
        toggleContainer.className         = 'na-toggle-container';

        var labelSpan                     = document.createElement('span');
        labelSpan.className               = 'na-control-label';
        labelSpan.textContent             = descriptor.label;

        var toggle                        = document.createElement('div');
        toggle.className                  = 'na-toggle' + (currentValue ? ' na-active' : '');
        toggle.id                         = descriptor.id + '-toggle';
        toggle.setAttribute('data-value', currentValue ? 'true' : 'false');

        var knob                          = document.createElement('div');
        knob.className                    = 'na-toggle-knob';
        toggle.appendChild(knob);

        toggleContainer.appendChild(labelSpan);
        toggleContainer.appendChild(toggle);
        wrapper.appendChild(toggleContainer);

        var onToggle = function () {
            var current = toggle.getAttribute('data-value') === 'true';
            var next    = !current;
            toggle.setAttribute('data-value', next ? 'true' : 'false');
            toggle.classList.toggle('na-active', next);
            na_handle_control_change(descriptor.id, next);
        };
        toggle.addEventListener('click', onToggle);
        na_change_listeners.push(function () {
            toggle.removeEventListener('click', onToggle);
        });

        return wrapper;
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Build a Single Control by Descriptor Type
    // ------------------------------------------------------------
    function na_build_control(descriptor) {
        var current = na_active_config[descriptor.id];
        if (current === undefined) current = descriptor.default;

        switch (descriptor.type) {
            case 'slider':   return na_build_slider_control(descriptor, current);
            case 'select':   return na_build_select_control(descriptor, current);
            case 'checkbox': return na_build_checkbox_control(descriptor, current);
            default:         return null;
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Container Mounting
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Mount Every Descriptor in an Array into a Container
    // ------------------------------------------------------------
    function na_mount_section(containerId, descriptors) {
        var container = document.getElementById(containerId);
        if (!container) {
            console.warn('[Na_DoorUI] Container not found:', containerId);
            return;
        }
        container.innerHTML = '';
        (descriptors || []).forEach(function (descriptor) {
            var node = na_build_control(descriptor);
            if (node) container.appendChild(node);
        });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Change Handling
// -----------------------------------------------------------------------------

    // SUB FUNCTION | Apply a Control Change to the Working Config
    // ------------------------------------------------------------
    function na_handle_control_change(id, value) {
        na_active_config[id] = value;
        na_schedule_rerender();
        na_schedule_live_update();
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Re-render the Plan and Elevation Viewports
    // ------------------------------------------------------------
    function na_schedule_rerender() {
        if (na_rerender_pending) return;
        na_rerender_pending = true;
        window.requestAnimationFrame(function () {
            na_rerender_pending = false;
            Na_DoorUI.na_render(na_active_config);
        });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Debounce a Live Update Callback to Ruby
    // ------------------------------------------------------------
    function na_schedule_live_update() {
        if (typeof na_doorLiveUpdateRequested !== 'function') return;

        if (na_live_update_timeout) clearTimeout(na_live_update_timeout);
        na_live_update_timeout = setTimeout(function () {
            try {
                na_doorLiveUpdateRequested(na_build_full_config_payload());
            } catch (err) {
                console.error('[Na_DoorUI] Live update failed:', err);
            }
        }, NA_LIVE_UPDATE_DEBOUNCE_MS);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Mount the Door Tab (Build Controls, Bind, First Render)
    // ------------------------------------------------------------
    Na_DoorUI.na_mount = function (initialConfig) {
        if (initialConfig) Na_DoorUI.na_set_active_config(initialConfig);

        na_mount_section('na-door-controls-opening',    window.NA_DOOR_OPENING_CONFIG);
        na_mount_section('na-door-controls-panel',      window.NA_DOOR_PANEL_TAB_CONFIG);
        na_mount_section('na-door-controls-architrave', window.NA_DOOR_ARCHITRAVE_CONFIG);
        na_mount_section('na-door-controls-handle',     window.NA_DOOR_HANDLE_CONFIG);
        na_mount_section('na-door-controls-options',    window.NA_DOOR_OPTIONS_CONFIG);

        Na_DoorUI.na_render(na_active_config);
    };
    // ---------------------------------------------------------------

    // FUNCTION | Unmount the Door Tab (Clear Listeners and Containers)
    // ------------------------------------------------------------
    Na_DoorUI.na_unmount = function () {
        na_change_listeners.forEach(function (cleanup) {
            try { cleanup(); } catch (err) { /* swallow */ }
        });
        na_change_listeners = [];

        ['na-door-controls-opening',
         'na-door-controls-panel',
         'na-door-controls-architrave',
         'na-door-controls-handle',
         'na-door-controls-options'].forEach(function (id) {
            var el = document.getElementById(id);
            if (el) el.innerHTML = '';
        });

        na_plan_instance      = null;                                         // <-- Force fresh DOM lookup on remount
        na_elevation_instance = null;                                         // <-- ...so re-attached SVGs get re-bound

        if (na_live_update_timeout) clearTimeout(na_live_update_timeout);
        na_live_update_timeout = null;
    };
    // ---------------------------------------------------------------

    // FUNCTION | Force a Viewport Render with the Provided Config
    // ------------------------------------------------------------
    // Each call lazily ensures both viewport instances exist (so the
    // factory wires pan/zoom on the first render after the tab mounts)
    // then re-paints them through the shared Na__Viewport__Instance API.
    Na_DoorUI.na_render = function (config) {
        var renderConfig = config || na_active_config;
        na_ensure_viewport_instances();

        if (na_plan_instance)      na_plan_instance.na_render(renderConfig);
        if (na_elevation_instance) na_elevation_instance.na_render(renderConfig);
    };
    // ---------------------------------------------------------------


    // SUB FUNCTION | Lazily Build the Plan and Elevation Viewport Instances
    // ---------------------------------------------------------------
    // The Door tab is hidden until the user opens it, so the wrapper /
    // SVG elements only exist in the DOM after na_mount runs. This
    // helper resolves and binds the instances on demand and is
    // idempotent on subsequent calls.
    function na_ensure_viewport_instances() {
        if (!window.Na__Viewport__Instance) {
            console.warn('[Na_DoorUI] Na__Viewport__Instance not loaded yet');
            return;
        }

        if (!na_plan_instance && window.Na_DoorPlanGenerator) {
            na_plan_instance = window.Na__Viewport__Instance.na_create({
                wrapperId          : 'na-door-plan-wrapper',
                svgId              : 'na-door-plan-svg',
                autoResetOnRender  : true,
                fitToContent       : window.Na_DoorPlanGenerator.na_fit_to_content,
                onRender           : function (svgEl, cfg) {
                    window.Na_DoorPlanGenerator.na_render(svgEl, cfg);
                }
            });
            if (na_plan_instance) na_plan_instance.na_init();
        }

        if (!na_elevation_instance && window.Na_DoorElevationGenerator) {
            na_elevation_instance = window.Na__Viewport__Instance.na_create({
                wrapperId          : 'na-door-elevation-wrapper',
                svgId              : 'na-door-elevation-svg',
                autoResetOnRender  : true,
                fitToContent       : window.Na_DoorElevationGenerator.na_fit_to_content,
                onRender           : function (svgEl, cfg) {
                    window.Na_DoorElevationGenerator.na_render(svgEl, cfg);
                }
            });
            if (na_elevation_instance) na_elevation_instance.na_init();
        }
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Reset Both Door Viewports to Fit Their Content
    // ---------------------------------------------------------------
    // Backs the dialog's "Reset View" button on the Doors tab, which
    // calls Na_DoorViewport.na_resetView() in its onclick attribute.
    function na_reset_door_viewports() {
        na_ensure_viewport_instances();
        if (na_plan_instance)      na_plan_instance.na_resetView(na_active_config);
        if (na_elevation_instance) na_elevation_instance.na_resetView(na_active_config);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Return a Snapshot of the Current Door Configuration
    // ------------------------------------------------------------
    Na_DoorUI.na_get_active_config = function () {
        return na_build_full_config_payload();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Replace the Working Config With an External Payload
    // ------------------------------------------------------------
    // Accepts either the full root payload (with Na__DoorMetadata /
    // Na__DoorConfiguration) or just the Na__DoorConfiguration block.
    Na_DoorUI.na_set_active_config = function (payload) {
        if (!payload) return;

        var configBlock   = payload['Na__DoorConfiguration'] || payload;
        var metadataArray = payload['Na__DoorMetadata'];

        Object.keys(configBlock || {}).forEach(function (key) {
            na_active_config[key] = configBlock[key];
        });

        if (metadataArray && metadataArray[0]) {
            Object.keys(metadataArray[0]).forEach(function (key) {
                na_active_metadata[key] = metadataArray[0][key];
            });
        }
    };
    // ---------------------------------------------------------------


    // FUNCTION | Reset the Working Door Config to the Descriptor Defaults
    // ------------------------------------------------------------
    // Used by the door bridge when Ruby tells the dialog to clear the
    // currently loaded door (deselection or off-tab selection). Builds a
    // fresh defaults payload from every descriptor module, replaces both
    // active maps, then rebuilds the controls + viewports if the Doors
    // tab is currently visible. Safe to call when the tab is hidden -
    // the rebuild becomes a no-op until the next mount.
    Na_DoorUI.na_reset_to_default = function () {
        na_active_config   = na_build_default_door_config();
        na_active_metadata = na_build_default_door_metadata();

        if (typeof Na_AppContext !== 'undefined' &&
            Na_AppContext.na_is_active_tab('doors')) {
            Na_DoorUI.na_mount(na_build_full_config_payload());
        }
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Internal Helpers - Payload Construction
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Build the Full Root Payload (Metadata + Components + Configuration)
    // ------------------------------------------------------------
    // The payload shape mirrors NA_DEFAULT_DOOR_CONFIG defined in the
    // Ruby Na__InteriorDoorConfigurator module so the Ruby side can
    // simply JSON.parse and consume.
    function na_build_full_config_payload() {
        return {
            'Na__DoorMetadata'      : [na_active_metadata],
            'Na__DoorComponents'    : [],
            'Na__DoorConfiguration' : Object.assign({}, na_active_config)
        };
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


    window.Na_DoorUI = Na_DoorUI;


// -----------------------------------------------------------------------------
// REGION | Door Viewport Aggregator (Public Global)
// -----------------------------------------------------------------------------
// Exposes a stable Na_DoorViewport namespace so the dialog's HTML
// onclick="Na_DoorViewport && Na_DoorViewport.na_resetView()" target
// matches the window tab's Na_Viewport.na_resetView() shape. The
// aggregator simply forwards into the door UI helpers, which in turn
// drive both Na__Viewport__Instance objects.
// -----------------------------------------------------------------------------

    window.Na_DoorViewport = {
        na_resetView : na_reset_door_viewports
    };

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
