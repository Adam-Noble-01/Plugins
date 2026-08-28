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
    var NA_DOOR_DERIVED_UI_KEYS = [                                          // <-- UI-only leaf-size sliders; derived from structural opening + lining, never sent to Ruby
        'Na__DoorConfig__LeafWidth_mm',
        'Na__DoorConfig__LeafHeight_mm'
    ];
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

    // HELPER FUNCTION | Strip Derived UI-Only Keys From a Config Map
    // ------------------------------------------------------------
    // The leaf-size sliders are pure UI conveniences derived from the
    // structural opening + lining thickness. They are never persisted or
    // sent to Ruby, so they are removed from the outgoing payload snapshot.
    function na_prune_derived_ui_keys(configMap) {
        if (!configMap) return;
        NA_DOOR_DERIVED_UI_KEYS.forEach(function (key) {
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
// REGION | Arithmetic Entry Helpers
// -----------------------------------------------------------------------------
//
// The Interior Door tab builds its sliders imperatively rather than through
// Na__Ui__Controls, so it carries its own thin wrappers over the shared
// evaluator. Behaviour is deliberately identical to the Windows tab.
// @delegate: ../03__AppUtils/Na__AssemblyStudio__AppUtils__ArithmeticEvaluator__.js

    var NA_ARITHMETIC_HINT =
        'Accepts arithmetic: 1700-50, 2400/3, 800*3, 2400+(100+100+100+100). ' +
        'Start with an operator to work from the current value (+200). ' +
        'Up/Down arrows step; hold Shift for x10.';

    // HELPER FUNCTION | Resolve the Shared Arithmetic Evaluator
    // ------------------------------------------------------------
    function na_arithmetic() {
        return window.Na__Utils__Arithmetic || null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Format a Committed Value for a Field
    // ------------------------------------------------------------
    function na_format_number(value) {
        var arithmetic = na_arithmetic();
        return arithmetic ? arithmetic.na_format(value) : String(value);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Test Whether Field Text Needs No Evaluation
    // ------------------------------------------------------------
    function na_is_plain_number_text(text) {
        var arithmetic = na_arithmetic();
        if (arithmetic) return arithmetic.na_is_plain_number(text);
        return isFinite(parseFloat(text));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Test Whether Field Text Opens With an Operator
    // ------------------------------------------------------------
    // Marks a relative entry ('+200', '/3'), which must never be applied
    // mid-keystroke because its prefix parses as a signed number on its own.
    function na_starts_with_operator(text) {
        return /^[+\-*/^]/.test(String(text == null ? '' : text).trim());
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Flag / Clear a Field That Could Not Be Read
    // ------------------------------------------------------------
    // The field turns red and the reason replaces its tooltip until the next
    // keystroke; the arithmetic hint it normally carries is stashed so it can
    // be put back.
    function na_mark_input_error(input, message) {
        if (!input) return;
        if (!input.classList.contains('na-input-error')) {
            input.dataset.naTitle = input.getAttribute('title') || '';
        }
        input.classList.add('na-input-error');
        input.setAttribute('title', message || 'Could not read that entry');
    }

    function na_clear_input_error(input) {
        if (!input || !input.classList.contains('na-input-error')) return;
        input.classList.remove('na-input-error');
        input.setAttribute('title', input.dataset.naTitle || '');
        delete input.dataset.naTitle;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Read the Live Clamp Range Off a Rendered Field
    // ------------------------------------------------------------
    // The DOM wins over the descriptor because na_door_patch_slider_dom
    // widens a max in place when a measured opening exceeds it.
    function na_read_live_range(input, descriptor) {
        // Absent means absent: Number(null) is 0, so a missing max attribute
        // would otherwise read as a hard ceiling of zero and clamp every entry
        // in the control to nothing.
        function na_to_number(candidate) {
            if (candidate === null || candidate === undefined || candidate === '') return NaN;
            var value = Number(candidate);
            return isFinite(value) ? value : NaN;
        }
        function na_pick(attributeName, descriptorValue) {
            var fromDom = na_to_number(input ? input.getAttribute(attributeName) : null);
            if (isFinite(fromDom)) return fromDom;
            return na_to_number(descriptorValue);
        }
        return {
            min : na_pick('min',  descriptor && descriptor.min),
            max : na_pick('max',  descriptor && descriptor.max),
            step: na_pick('step', descriptor && descriptor.step)
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve Typed Text Into a Committed Numeric Value
    // ------------------------------------------------------------
    // @return {Object} { ok: true, value } | { ok: false, error }
    function na_resolve_typed_value(input, descriptor, previousValue) {
        var range      = na_read_live_range(input, descriptor);
        var arithmetic = na_arithmetic();

        if (!arithmetic) {                                                      // <-- Degrade to plain-number entry
            var parsed = parseFloat(input.value);
            if (!isFinite(parsed)) return { ok: false, error: 'Not a number' };
            if (isFinite(range.min)) parsed = Math.max(range.min, parsed);
            if (isFinite(range.max)) parsed = Math.min(range.max, parsed);
            return { ok: true, value: parsed };
        }

        return arithmetic.na_resolve_field_value(input.value, {
            currentValue      : previousValue,
            min               : range.min,
            max               : range.max,
            allowRelativeMinus: !(isFinite(range.min) && range.min < 0)
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve an Up/Down Arrow Keypress to a Stepped Value
    // ------------------------------------------------------------
    // Restores the stepping that type="number" used to provide natively.
    // Shift multiplies the step by 10.
    // @return {Number|null} Stepped value, or null when the key is not a stepper
    function na_resolve_step_key(event, input, descriptor, previousValue) {
        if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return null;

        var range = na_read_live_range(input, descriptor);
        var step  = (isFinite(range.step) && range.step > 0) ? range.step : 1;
        var typed = parseFloat(input.value);
        var base  = isFinite(typed) ? typed : previousValue;
        if (!isFinite(base)) return null;

        var next = base + (event.key === 'ArrowUp' ? step : -step) * (event.shiftKey ? 10 : 1);
        if (isFinite(range.min)) next = Math.max(range.min, next);
        if (isFinite(range.max)) next = Math.min(range.max, next);
        return next;
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

        // type="text", not type="number", so the field accepts arithmetic
        // ('1700-50', '2400/3', '+200'). A number input discards anything that
        // is not already a valid number, so the expression could never be read
        // back. @delegate: ../03__AppUtils/Na__AssemblyStudio__AppUtils__ArithmeticEvaluator__.js
        var number                        = document.createElement('input');
        number.type                       = 'text';
        number.className                  = 'na-slider-input';
        number.id                         = descriptor.id + '-input';
        number.min                        = descriptor.min;
        number.max                        = descriptor.max;
        number.step                       = descriptor.step;
        number.value                      = currentValue;
        number.autocomplete               = 'off';
        number.spellcheck                 = false;
        number.title                      = NA_ARITHMETIC_HINT;

        sliderContainer.appendChild(range);
        sliderContainer.appendChild(number);

        wrapper.appendChild(label);
        wrapper.appendChild(sliderContainer);

        // Last committed value, for relative entry and for restoring the field
        // when an expression cannot be read.
        var lastCommittedValue = Number(currentValue);

        // `fromSlider` suppresses the write back to the range element, so a
        // live drag is never assigned to mid-gesture from its own handler.
        var na_apply = function (value, fromSlider) {
            lastCommittedValue    = value;
            if (!fromSlider) range.value = value;
            number.value          = na_format_number(value);
            valueSpan.textContent = na_format_number(value) + (descriptor.unit || '');
            na_handle_control_change(descriptor.id, value);
        };

        var onSlide = function () {
            var value = parseFloat(range.value);
            if (!isFinite(value)) return;
            na_clear_input_error(number);
            na_apply(value, true);
        };

        // Live per-keystroke updates are kept for ordinary typing, but only
        // while the field still holds a plain, absolute number. The moment an
        // operator appears the entry is left alone until it is committed, so a
        // half-typed '1700-' never reaches the model. A leading operator is
        // excluded too: '+200' passes the plain-number test at '+2', and
        // applying that live would slam the door to 2mm mid-keystroke.
        var onType = function () {
            na_clear_input_error(number);
            if (na_starts_with_operator(number.value)) return;
            if (!na_is_plain_number_text(number.value)) return;
            var value = parseFloat(number.value);
            if (!isFinite(value)) return;
            lastCommittedValue    = value;
            range.value           = value;
            valueSpan.textContent = number.value + (descriptor.unit || '');
            na_handle_control_change(descriptor.id, value);
        };

        var onCommit = function () {
            var resolved = na_resolve_typed_value(number, descriptor, lastCommittedValue);
            if (!resolved.ok) {
                na_mark_input_error(number, resolved.error);
                number.value = isFinite(lastCommittedValue) ? na_format_number(lastCommittedValue) : '';
                return;
            }
            na_clear_input_error(number);

            // Ordinary typing has already been applied live by onType, so only
            // tidy the field text rather than firing a second identical rebuild.
            if (resolved.value === lastCommittedValue) {
                number.value          = na_format_number(resolved.value);
                valueSpan.textContent = na_format_number(resolved.value) + (descriptor.unit || '');
                return;
            }
            na_apply(resolved.value);
        };

        var onFocus = function () {
            var atFocus = parseFloat(number.value);
            if (isFinite(atFocus)) lastCommittedValue = atFocus;
        };

        var onStepKey = function (event) {
            var stepped = na_resolve_step_key(event, number, descriptor, lastCommittedValue);
            if (stepped === null) return;
            event.preventDefault();
            na_clear_input_error(number);
            na_apply(stepped);
        };

        range.addEventListener('input', onSlide);
        number.addEventListener('input', onType);
        number.addEventListener('change', onCommit);
        number.addEventListener('focus', onFocus);
        number.addEventListener('keydown', onStepKey);

        na_change_listeners.push(function () {
            range.removeEventListener('input', onSlide);
            number.removeEventListener('input', onType);
            number.removeEventListener('change', onCommit);
            number.removeEventListener('focus', onFocus);
            number.removeEventListener('keydown', onStepKey);
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
        // Derived leaf-size sliders drive the structural opening (and never
        // the reverse), so they are handled before the generic path.
        if (id === 'Na__DoorConfig__LeafWidth_mm')  { na_apply_leaf_width_change(value);  return; }
        if (id === 'Na__DoorConfig__LeafHeight_mm') { na_apply_leaf_height_change(value); return; }

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
        if (id === 'Na__DoorConfig__DoorType') {
            na_sync_door_type_visibility();
        }
        // Structural opening, lining thickness and door type all change the
        // derived leaf size, so refresh the leaf sliders to match.
        if (id === 'Na__DoorConfig__OpeningWidth_mm'  ||
            id === 'Na__DoorConfig__OpeningHeight_mm' ||
            id === 'Na__DoorConfig__LiningThickness_mm' ||
            id === 'Na__DoorConfig__DoorType') {
            na_sync_leaf_size_controls();
        }
        na_schedule_rerender();
        na_schedule_live_update();
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Apply a Door Leaf Width Change to the Structural Opening
    // ------------------------------------------------------------
    // Back-computes the structural opening width from the requested leaf
    // width (accounting for leaf count + both jamb linings), clamps it to
    // the structural slider's range, writes it to the config + the
    // structural slider UI, then re-derives both leaf sliders so the two
    // stay consistent (e.g. after clamping).
    function na_apply_leaf_width_change(leafWidth) {
        var structuralWidth = na_compute_structural_width_from_leaf(leafWidth);
        structuralWidth     = na_clamp_to_descriptor('Na__DoorConfig__OpeningWidth_mm', structuralWidth);

        na_active_config['Na__DoorConfig__OpeningWidth_mm'] = Math.round(structuralWidth);
        na_set_slider_control_value('Na__DoorConfig__OpeningWidth_mm', structuralWidth);
        na_sync_leaf_size_controls();

        na_schedule_rerender();
        na_schedule_live_update();
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Apply a Door Leaf Height Change to the Structural Opening
    // ------------------------------------------------------------
    // Back-computes the structural opening height from the requested leaf
    // height (head lining only), clamps + writes it, then re-derives both
    // leaf sliders.
    function na_apply_leaf_height_change(leafHeight) {
        var structuralHeight = na_compute_structural_height_from_leaf(leafHeight);
        structuralHeight     = na_clamp_to_descriptor('Na__DoorConfig__OpeningHeight_mm', structuralHeight);

        na_active_config['Na__DoorConfig__OpeningHeight_mm'] = Math.round(structuralHeight);
        na_set_slider_control_value('Na__DoorConfig__OpeningHeight_mm', structuralHeight);
        na_sync_leaf_size_controls();

        na_schedule_rerender();
        na_schedule_live_update();
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Grey Out the Swing Side Control for Double Doors
    // ------------------------------------------------------------
    // A double door's two leaves are always hinged on their own outer
    // jambs (left leaf left, right leaf right), so the user-facing Swing
    // Side (Left/Right) hand choice has no meaning. We disable - rather
    // than remove - the control so its value persists when switching back
    // to a single door, and add a tooltip explaining why it is inactive.
    var NA_SWING_SIDE_DISABLED_TOOLTIP = 'Swing Side is only available for single doors';

    function na_sync_door_type_visibility() {
        var isDouble = String(na_active_config['Na__DoorConfig__DoorType'] || 'Single').toLowerCase() === 'double';
        var wrapper  = document.querySelector('[data-control-id="Na__DoorConfig__SwingSide"]');
        if (!wrapper) return;

        if (isDouble) {
            wrapper.style.opacity       = '0.4';
            wrapper.style.pointerEvents = 'none';
            wrapper.setAttribute('title', NA_SWING_SIDE_DISABLED_TOOLTIP);
        } else {
            wrapper.style.opacity       = '';
            wrapper.style.pointerEvents = '';
            wrapper.removeAttribute('title');
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Leaf Size <-> Structural Opening Linking
// -----------------------------------------------------------------------------
// The "Door Leaf Width/Height" sliders are derived, two-way-linked views of
// the structural opening. The structural opening is what the measurement tool
// populates (raw wall opening); the leaf sliders expose the resulting door
// leaf size so the user can dial in standardised sizes (e.g. 762 x 1985).
//   * Leaf width  = (structural_w - 2 x lining) / leaf_count
//   * Leaf height =  structural_h - lining           (head lining only)
// Single door -> one leaf fills the clear opening; double door -> each of two.
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Read a Numeric Config Value With Fallback
    // ------------------------------------------------------------
    function na_config_number(key, fallback) {
        var value = Number(na_active_config[key]);
        return Number.isFinite(value) ? value : fallback;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Active Leaf Count (Single = 1, Double = 2)
    // ------------------------------------------------------------
    function na_active_leaf_count() {
        return String(na_active_config['Na__DoorConfig__DoorType'] || 'Single').toLowerCase() === 'double' ? 2 : 1;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Derive a Single Leaf Width From the Structural Opening
    // ------------------------------------------------------------
    function na_compute_leaf_width_from_structural() {
        var structuralWidth = na_config_number('Na__DoorConfig__OpeningWidth_mm', 850);
        var liningThickness = na_config_number('Na__DoorConfig__LiningThickness_mm', 35);
        var clearWidth      = structuralWidth - (liningThickness * 2);
        return clearWidth / na_active_leaf_count();
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Derive the Leaf Height From the Structural Opening
    // ------------------------------------------------------------
    function na_compute_leaf_height_from_structural() {
        var structuralHeight = na_config_number('Na__DoorConfig__OpeningHeight_mm', 2100);
        var liningThickness  = na_config_number('Na__DoorConfig__LiningThickness_mm', 35);
        return structuralHeight - liningThickness;                            // <-- Head lining only; opening is open at the floor
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Back-Compute the Structural Width From a Leaf Width
    // ------------------------------------------------------------
    function na_compute_structural_width_from_leaf(leafWidth) {
        var liningThickness = na_config_number('Na__DoorConfig__LiningThickness_mm', 35);
        return (leafWidth * na_active_leaf_count()) + (liningThickness * 2);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Back-Compute the Structural Height From a Leaf Height
    // ------------------------------------------------------------
    function na_compute_structural_height_from_leaf(leafHeight) {
        var liningThickness = na_config_number('Na__DoorConfig__LiningThickness_mm', 35);
        return leafHeight + liningThickness;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Find a Control Descriptor by ID Across All Sections
    // ------------------------------------------------------------
    function na_find_descriptor(controlId) {
        var arrays = na_collect_descriptor_arrays();
        for (var a = 0; a < arrays.length; a++) {
            var arr = arrays[a] || [];
            for (var i = 0; i < arr.length; i++) {
                if (arr[i] && arr[i].id === controlId) return arr[i];
            }
        }
        return null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Clamp a Value to a Control Descriptor's Min/Max
    // ------------------------------------------------------------
    function na_clamp_to_descriptor(controlId, value) {
        var descriptor = na_find_descriptor(controlId);
        var clamped    = value;
        if (descriptor) {
            if (typeof descriptor.min === 'number') clamped = Math.max(descriptor.min, clamped);
            if (typeof descriptor.max === 'number') clamped = Math.min(descriptor.max, clamped);
        }
        return clamped;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Programmatically Set a Slider Control's UI + Value
    // ------------------------------------------------------------
    // Updates the range input, number input and value display for a slider
    // WITHOUT firing its change handlers, so it can be driven by a linked
    // control. No-ops gracefully when the control is not currently mounted.
    function na_set_slider_control_value(controlId, value) {
        var descriptor = na_find_descriptor(controlId);
        var unit       = (descriptor && descriptor.unit) || 'mm';
        var rounded    = Math.round(value);

        var range   = document.getElementById(controlId + '-slider');
        var number  = document.getElementById(controlId + '-input');
        var display = document.getElementById(controlId + '-display');

        if (range)   range.value         = rounded;
        if (number)  number.value         = rounded;
        if (display) display.textContent  = rounded + unit;
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Refresh the Leaf-Size Sliders From the Structural Opening
    // ------------------------------------------------------------
    // Writes the derived leaf width/height into the working config and pushes
    // them to the slider UI. Called on mount, on config load, and whenever a
    // structural / lining / door-type control changes.
    function na_sync_leaf_size_controls() {
        var leafWidth  = na_compute_leaf_width_from_structural();
        var leafHeight = na_compute_leaf_height_from_structural();

        na_active_config['Na__DoorConfig__LeafWidth_mm']  = Math.round(leafWidth);
        na_active_config['Na__DoorConfig__LeafHeight_mm'] = Math.round(leafHeight);

        na_set_slider_control_value('Na__DoorConfig__LeafWidth_mm',  leafWidth);
        na_set_slider_control_value('Na__DoorConfig__LeafHeight_mm', leafHeight);
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Change Handling (continued)
// -----------------------------------------------------------------------------

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
        na_sync_door_type_visibility();
        na_sync_leaf_size_controls();
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
        na_sync_door_type_visibility();
        na_sync_leaf_size_controls();

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
        na_prune_derived_ui_keys(na_config_snapshot);                         // <-- Strip the leaf-size sliders (derived from structural opening + lining)
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
