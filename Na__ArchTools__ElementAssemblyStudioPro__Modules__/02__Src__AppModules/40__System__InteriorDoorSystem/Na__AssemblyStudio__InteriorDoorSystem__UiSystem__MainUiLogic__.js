// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - DOOR TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__UiSystem__MainUiLogic__.js
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

    var NA_LIVE_UPDATE_DEBOUNCE_MS = 150;                                     // <-- Mirrors window-tool live-update cadence
    var NA_DOOR_OBSOLETE_CONFIG_KEYS = ['Na__DoorConfig__HandleSide'];        // <-- Removed for Interior single-door workflow
    var NA_DOOR_ARCHITRAVE_DEFAULT_PROFILE_KEY = 'Na__Asset__Plan2D__Architrave__Default__w70mm_x_d20mm';
    var NA_DOOR_ARCHITRAVE_LEGACY_DEFAULT_KEY = 'Na__InteriorDoor__Architrave__Default';

    // Material IDs no longer ride on visible JS descriptors (the Joinery /
    // Handle Finish swatch cards write them straight into na_active_config).
    // Seed them here so the create/update payload sent to Ruby always carries
    // a value, even before the user clicks a swatch.
    var NA_DOOR_MATERIAL_DEFAULTS = {
        'Na__DoorConfig__LiningMaterialId'    : 'MAT001__Default',
        'Na__DoorConfig__PanelMaterialId'     : 'MAT001__Default',
        'Na__DoorConfig__ArchitraveMaterialId': 'MAT001__Default',
        'Na__DoorConfig__HandleMaterialId'    : 'MAT615__Metal__Ironmongery__Chrome'
    };

    var na_active_config        = na_build_default_door_config();             // <-- Working config snapshot (Na__DoorConfiguration shape)
    var na_active_metadata      = na_build_default_door_metadata();           // <-- Metadata block (Na__DoorMetadata)
    var na_change_listeners     = [];                                         // <-- Per-mount cleanup callbacks
    var na_rerender_pending     = false;                                      // <-- requestAnimationFrame batching guard
    var na_live_update_timeout  = null;                                       // <-- Debounce id for live updates
    var na_preview_request_state = {};                                        // <-- Handle key -> pending flag (prevents request spam)

    var na_plan_instance        = null;                                       // <-- Na__Viewport__Instance for plan view
    var na_elevation_instance   = null;                                       // <-- Na__Viewport__Instance for elevation view
    var na_resize_bound         = false;                                      // <-- Guard so drag handlers are only bound once

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
        Object.keys(NA_DOOR_MATERIAL_DEFAULTS).forEach(function (key) {
            if (!Object.prototype.hasOwnProperty.call(defaults, key)) {
                defaults[key] = NA_DOOR_MATERIAL_DEFAULTS[key];
            }
        });
        na_prune_obsolete_config_keys(defaults);
        na_normalize_architrave_config_keys(defaults, { stripLegacyKeys: false });
        return defaults;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Remove Deprecated Door Config Keys
    // ------------------------------------------------------------
    function na_prune_obsolete_config_keys(configMap) {
        if (!configMap) return;
        (NA_DOOR_OBSOLETE_CONFIG_KEYS || []).forEach(function (key) {
            if (Object.prototype.hasOwnProperty.call(configMap, key)) {
                delete configMap[key];
            }
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Normalize Architrave Keys to Runtime Canonical Shape
    // ------------------------------------------------------------
    function na_normalize_architrave_config_keys(configMap, options) {
        if (!configMap || typeof configMap !== 'object') return;

        var runtimeOptions = options || {};
        var shouldStripLegacy = runtimeOptions.stripLegacyKeys === true;
        var profileKey = (configMap['Na__DoorConfig__ArchitraveProfileKey'] || '').toString().trim();
        var legacyAssetKey = (configMap['Na__DoorConfig__ArchitraveAssetKey'] || '').toString().trim();

        if (!profileKey && legacyAssetKey) {
            profileKey = legacyAssetKey;
        }
        if (!profileKey || profileKey === NA_DOOR_ARCHITRAVE_LEGACY_DEFAULT_KEY) {
            profileKey = NA_DOOR_ARCHITRAVE_DEFAULT_PROFILE_KEY;
        }
        configMap['Na__DoorConfig__ArchitraveProfileKey'] = profileKey;

        if (Object.prototype.hasOwnProperty.call(configMap, 'Na__DoorConfig__ArchitraveEnabled')) {
            var unifiedEnabled = configMap['Na__DoorConfig__ArchitraveEnabled'] !== false;
            configMap['Na__DoorConfig__ArchitraveFrontEnabled'] = unifiedEnabled;
            configMap['Na__DoorConfig__ArchitraveBackEnabled'] = unifiedEnabled;
        } else {
            var frontEnabled = configMap['Na__DoorConfig__ArchitraveFrontEnabled'] !== false;
            var backEnabled = configMap['Na__DoorConfig__ArchitraveBackEnabled'] !== false;
            configMap['Na__DoorConfig__ArchitraveFrontEnabled'] = frontEnabled;
            configMap['Na__DoorConfig__ArchitraveBackEnabled'] = backEnabled;
            configMap['Na__DoorConfig__ArchitraveEnabled'] = frontEnabled && backEnabled;
        }

        if (shouldStripLegacy) {
            delete configMap['Na__DoorConfig__ArchitraveAssetKey'];
            delete configMap['Na__DoorConfig__ArchitraveEnabled'];
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Build the Default Na__DoorMetadata Block
    // ------------------------------------------------------------
    function na_build_default_door_metadata() {
        return {
            'Na__Door__UniqueId'     : null,
            'Na__Door__Name'         : 'New Interior Door',
            'Na__Door__Description'  : '',
            'Na__Door__Notes'        : 'Created with Element Assembly Studio Pro',
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

    // HELPER FUNCTION | Create a Binary Toggle Control DOM Subtree
    // ------------------------------------------------------------
    // Mirrors the na-toggle-container layout: descriptor label on the left,
    // and the two-option inline toggle (left label | track | right label)
    // on the right — matching the row alignment of checkbox controls.
    // options[0] = left side value, options[1] = right side value.
    function na_build_binary_toggle_control(descriptor, currentValue) {
        var options                       = descriptor.options || [];
        var leftOpt                       = options[0] || { value: '', label: '' };
        var rightOpt                      = options[1] || { value: '', label: '' };
        var isRight                       = (currentValue === rightOpt.value);

        var wrapper                       = document.createElement('div');
        wrapper.className                 = 'na-control-item';
        wrapper.setAttribute('data-control-id', descriptor.id);

        var container                     = document.createElement('div');
        container.className               = 'na-toggle-container';                // <-- Reuse existing label-left / control-right row layout

        var labelSpan                     = document.createElement('span');
        labelSpan.className               = 'na-control-label';
        labelSpan.textContent             = descriptor.label;
        container.appendChild(labelSpan);

        var toggle                        = document.createElement('div');
        toggle.className                  = 'na-binary-toggle' + (isRight ? ' na-binary-toggle--right' : ' na-binary-toggle--left');
        toggle.id                         = descriptor.id + '-btoggle';
        toggle.setAttribute('data-value', currentValue);

        var leftLabel                     = document.createElement('span');
        leftLabel.className               = 'na-binary-toggle__option na-binary-toggle__option--left';
        leftLabel.textContent             = leftOpt.label;

        var track                         = document.createElement('div');
        track.className                   = 'na-binary-toggle__track';

        var thumb                         = document.createElement('div');
        thumb.className                   = 'na-binary-toggle__thumb';
        track.appendChild(thumb);

        var rightLabel                    = document.createElement('span');
        rightLabel.className              = 'na-binary-toggle__option na-binary-toggle__option--right';
        rightLabel.textContent            = rightOpt.label;

        toggle.appendChild(leftLabel);
        toggle.appendChild(track);
        toggle.appendChild(rightLabel);

        container.appendChild(toggle);
        wrapper.appendChild(container);

        var onClick = function () {
            var currentVal = toggle.getAttribute('data-value');
            var newVal     = (currentVal === rightOpt.value) ? leftOpt.value : rightOpt.value;
            var goingRight = (newVal === rightOpt.value);

            toggle.setAttribute('data-value', newVal);
            toggle.classList.toggle('na-binary-toggle--left',  !goingRight);
            toggle.classList.toggle('na-binary-toggle--right', goingRight);

            na_handle_control_change(descriptor.id, newVal);
        };
        toggle.addEventListener('click', onClick);
        na_change_listeners.push(function () {
            toggle.removeEventListener('click', onClick);
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
            case 'slider':        return na_build_slider_control(descriptor, current);
            case 'select':        return na_build_select_control(descriptor, current);
            case 'binary_toggle': return na_build_binary_toggle_control(descriptor, current);
            case 'checkbox':      return na_build_checkbox_control(descriptor, current);
            default:              return null;
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
        na_normalize_architrave_config_keys(na_active_config, { stripLegacyKeys: false });
        if (id === 'Na__DoorConfig__HandleAssetKey') {
            na_reset_preview_request_state(value);
            na_request_handle_preview_if_needed('handle-select-change');
        }
        if (id === 'Na__DoorConfig__PanelDesignStyle' ||
            id === 'Na__DoorConfig__PanelDesignEnabled') {
            na_sync_panel_design_visibility();
        }
        na_schedule_rerender();
        na_schedule_live_update();
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Sync Conditional Visibility of Panel Design Controls
    // ------------------------------------------------------------
    // When PanelDesignEnabled is false the entire sub-block of style/
    // dimension controls is hidden. When it is true, the VerticalNarrow
    // slider is additionally shown/hidden based on the active style.
    // Control wrappers are not removed so values persist across toggles.
    var NA_PANEL_DESIGN_SUB_CONTROLS = [                                  // <-- All controls gated by PanelDesignEnabled
        'Na__DoorConfig__PanelDesignStyle',
        'Na__DoorConfig__PanelDesignStileWidth_mm',
        'Na__DoorConfig__PanelDesignTopRail_mm',
        'Na__DoorConfig__PanelDesignBottomRail_mm',
        'Na__DoorConfig__PanelDesignInnerRailThickness_mm',
        'Na__DoorConfig__PanelDesignVerticalPaneWidth_mm'
    ];

    function na_sync_panel_design_visibility() {
        var enabled = na_active_config['Na__DoorConfig__PanelDesignEnabled'] !== false;
        var style   = na_active_config['Na__DoorConfig__PanelDesignStyle'];

        NA_PANEL_DESIGN_SUB_CONTROLS.forEach(function (controlId) {
            var wrapper = document.querySelector('[data-control-id="' + controlId + '"]');
            if (!wrapper) return;

            if (!enabled) {
                wrapper.style.display = 'none';
                return;
            }

            if (controlId === 'Na__DoorConfig__PanelDesignVerticalPaneWidth_mm') {
                wrapper.style.display = (style === 'VerticalNarrow') ? '' : 'none';
            } else {
                wrapper.style.display = '';
            }
        });
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Ensure Selected Handle Has Preview Cache Data
    // ------------------------------------------------------------
    function na_request_handle_preview_if_needed(reason) {
        var key = (na_active_config['Na__DoorConfig__HandleAssetKey'] || '').toString().trim();
        if (!key) key = 'Na__InteriorDoor__Handle__Default';

        var cacheEntry = (typeof window.na_getDoorHandlePreviewCacheEntry === 'function')
            ? window.na_getDoorHandlePreviewCacheEntry(key)
            : null;
        var hasPlan = !!(cacheEntry && cacheEntry['Na__Asset__Plan2D']);
        var hasElevation = !!(cacheEntry && cacheEntry['Na__Asset__Elevation2D']);
        if (hasPlan || hasElevation) return;
        if (window.NA_DOOR_HANDLE_ASSET_PREVIEW_WARNINGS && window.NA_DOOR_HANDLE_ASSET_PREVIEW_WARNINGS[key]) return;
        if (na_preview_request_state[key]) return;
        if (typeof window.na_requestDoorHandlePreviewAsset !== 'function') return;

        na_preview_request_state[key] = true;
        console.warn('[Na_DoorUI] Missing handle preview cache for', key, '| reason:', reason || 'unspecified');
        window.na_requestDoorHandlePreviewAsset(key);

        window.setTimeout(function () {
            na_preview_request_state[key] = false;
        }, 1200);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Reset Pending Flag for One Handle Key
    // ------------------------------------------------------------
    function na_reset_preview_request_state(handleKey) {
        var key = (handleKey || '').toString().trim();
        if (!key) return;
        na_preview_request_state[key] = false;
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
// REGION | Door Preview Resize
// -----------------------------------------------------------------------------

    function na_init_preview_resize() {
        if (na_resize_bound) return;

        var handle = document.getElementById('na-door-viewport-resize-handle');
        var planWrapper = document.getElementById('na-door-plan-wrapper');
        var elevationWrapper = document.getElementById('na-door-elevation-wrapper');
        if (!handle || !planWrapper || !elevationWrapper) return;

        var isResizing = false;
        var startY = 0;
        var startHeight = 0;
        var minHeight = 120;
        var maxHeight = 600;

        handle.addEventListener('mousedown', function (event) {
            isResizing = true;
            startY = event.clientY;
            startHeight = Math.round(planWrapper.getBoundingClientRect().height);
            document.body.style.cursor = 'ns-resize';
            event.preventDefault();
        });

        document.addEventListener('mousemove', function (event) {
            if (!isResizing) return;

            var deltaY = event.clientY - startY;
            var newHeight = Math.max(minHeight, Math.min(maxHeight, startHeight + deltaY));
            planWrapper.style.height = newHeight + 'px';
            elevationWrapper.style.height = newHeight + 'px';
        });

        document.addEventListener('mouseup', function () {
            if (!isResizing) return;
            isResizing = false;
            document.body.style.cursor = '';
            na_reset_door_viewports();
        });

        na_resize_bound = true;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Mount the Door Tab (Build Controls, Bind, First Render)
    // ------------------------------------------------------------
    Na_DoorUI.na_mount = function (initialConfig) {
        if (initialConfig) Na_DoorUI.na_set_active_config(initialConfig);
        na_init_preview_resize();

        na_mount_section('na-door-controls-opening',    window.NA_DOOR_OPENING_CONFIG);
        na_mount_section('na-door-controls-panel',      window.NA_DOOR_PANEL_TAB_CONFIG);
        na_mount_section('na-door-controls-architrave', window.NA_DOOR_ARCHITRAVE_CONFIG);
        na_mount_section('na-door-controls-handle',     window.NA_DOOR_HANDLE_CONFIG);
        na_mount_section('na-door-controls-options',    window.NA_DOOR_OPTIONS_CONFIG);

        if (typeof window.na_requestDoorHandleAssetOptions === 'function') {
            window.na_requestDoorHandleAssetOptions();
        }
        if (typeof window.na_requestDoorArchitraveAssetOptions === 'function') {
            window.na_requestDoorArchitraveAssetOptions();
        }
        na_request_handle_preview_if_needed('door-ui-mount');

        if (window.Na_FrameFinishCards && typeof window.Na_FrameFinishCards.na_render_all === 'function') {
            window.Na_FrameFinishCards.na_render_all();
        }

        na_sync_panel_design_visibility();
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
        na_request_handle_preview_if_needed('door-ui-render');
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

        na_prune_obsolete_config_keys(na_active_config);
        na_normalize_architrave_config_keys(na_active_config, { stripLegacyKeys: false });
        na_request_handle_preview_if_needed('set-active-config');
        na_sync_panel_design_visibility();

        if (window.Na_FrameFinishCards && typeof window.Na_FrameFinishCards.na_sync_selection === 'function') {
            window.Na_FrameFinishCards.na_sync_selection(na_active_config);
        }
    };
    // ---------------------------------------------------------------


    // FUNCTION | Apply a Bulk Config Change (Used by External UI Modules)
    // ------------------------------------------------------------
    // Used by the FinishCards module so a single swatch click can update
    // multiple door config keys (Lining + Panel + Architrave) in one shot.
    // Triggers the standard re-render + debounced live-update pipeline.
    // @param {Object} updates - Map of Na__DoorConfig__* keys to new values.
    Na_DoorUI.na_apply_config_change = function (updates) {
        if (!updates || typeof updates !== 'object') return;
        Object.keys(updates).forEach(function (key) {
            na_active_config[key] = updates[key];
        });
        na_normalize_architrave_config_keys(na_active_config, { stripLegacyKeys: false });
        na_schedule_rerender();
        na_schedule_live_update();
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
    // Ruby Na__AssemblyStudio::Na__InteriorDoorSystem module so the Ruby side can
    // simply JSON.parse and consume.
    function na_build_full_config_payload() {
        var na_config_snapshot = Object.assign({}, na_active_config);
        na_prune_obsolete_config_keys(na_config_snapshot);
        na_normalize_architrave_config_keys(na_config_snapshot, { stripLegacyKeys: true });
        return {
            'Na__DoorMetadata'      : [na_active_metadata],
            'Na__DoorComponents'    : [],
            'Na__DoorConfiguration' : na_config_snapshot
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
