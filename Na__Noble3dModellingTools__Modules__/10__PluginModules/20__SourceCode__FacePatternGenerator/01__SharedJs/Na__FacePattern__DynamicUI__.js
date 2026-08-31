// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - DYNAMIC UI
// =============================================================================
//
// FILE       : Na__FacePattern__DynamicUI__.js
// NAMESPACE  : window.Na__FacePattern__DynamicUI
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : JSON-config-driven control panel builder — number inputs,
//              slider-plus-box pairs, and selects from field-descriptor arrays
//              in UiConfig. Select fields
//              with an `applies` map write preset values into linked number
//              fields; editing a linked field flips the select back to custom.
//              A `showWhen` map hides a field until its source controls match.
// CREATED    : 2026
//
// =============================================================================

window.Na__FacePattern__DynamicUI = (function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var na_state = {
        containerId: null,
        statusId: null,
        fields: [],
        values: {},
        groups: {},
        onChange: null
    };

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Shorthand for getElementById
    // ------------------------------------------------------------
    function na_el(id) { return document.getElementById(id); }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Test Whether a Field Carries a Numeric Value
    // ------------------------------------------------------------
    // Slider fields are numbers with a range control bolted alongside the box,
    // so everywhere a number is read or written must treat the two alike.
    function na_isNumericField(field) {
        return field.type === 'number' || field.type === 'slider';
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Mount and Field Management
    // -------------------------------------------------------------------------

    // FUNCTION | Mount the Dynamic UI to Its Container and Status Elements
    // ------------------------------------------------------------
    function na_mount(options) {
        na_state.containerId = options.containerId;
        na_state.statusId    = options.statusId;
        na_state.onChange    = typeof options.onChange === 'function' ? options.onChange : null;
    }
    // ------------------------------------------------------------

    // FUNCTION | Replace the Control Panel with a New Field Descriptor Set
    // ------------------------------------------------------------
    function na_setFields(fields) {
        na_state.fields = fields || [];
        na_state.values = {};
        na_state.groups = {};
        na_render();
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Rendering
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Build DOM Controls from the Current Field Descriptors
    // ------------------------------------------------------------
    function na_render() {
        var container = na_el(na_state.containerId);
        if (!container) { return; }

        container.innerHTML = '';
        na_state.fields.forEach(function (field) {
            na_state.values[field.id] = field.default;

            var group = document.createElement('div');
            group.className = 'naFacePat__ControlGroup';

            var label = document.createElement('label');
            label.className = 'naFacePat__Label';
            label.htmlFor = field.id;
            label.textContent = field.label;
            group.appendChild(label);

            var input = field.type === 'select' ? document.createElement('select') : document.createElement('input');
            input.className = field.type === 'select' ? 'naFacePat__Select' : 'naFacePat__Input';
            input.id = field.id;

            var slider = null;
            if (field.type === 'select') {
                (field.options || []).forEach(function (option) {
                    var optionEl = document.createElement('option');
                    optionEl.value = option.value;
                    optionEl.textContent = option.label;
                    if (option.value === field.default) { optionEl.selected = true; }
                    input.appendChild(optionEl);
                });
            } else {
                input.type = 'number';
                input.value = field.default;
                if (field.min !== undefined)  { input.min  = field.min; }
                if (field.max !== undefined)  { input.max  = field.max; }
                if (field.step !== undefined) { input.step = field.step; }
            }

            if (field.type === 'slider') {                                      // <-- Range beside the box, both driving one value
                slider = document.createElement('input');
                slider.type = 'range';
                slider.className = 'naFacePat__Slider';
                slider.id = field.id + '_slider';
                slider.value = field.default;
                slider.min  = field.slider_min !== undefined ? field.slider_min : field.min;
                slider.max  = field.slider_max !== undefined ? field.slider_max : field.max;
                if (field.step !== undefined) { slider.step = field.step; }
                input.className = 'naFacePat__Input naFacePat__Input--withSlider';
            }

            function na_onFieldChange() {
                na_state.values[field.id] = na_isNumericField(field) ? Number(input.value) : input.value;
                if (field.type === 'select' && field.applies) { na_applyPresetValues(field, input.value); }
                if (na_isNumericField(field)) { na_syncPresetSelects(field.id); }
                na_applyFieldVisibility();
                if (na_state.onChange) { na_state.onChange(field.id, na_state.values[field.id]); }
            }

            input.addEventListener('input', na_onFieldChange);
            input.addEventListener('change', na_onFieldChange);

            if (slider) {
                slider.addEventListener('input', function () {                  // <-- Slider drives the box, then the shared handler
                    input.value = slider.value;
                    na_onFieldChange();
                });
                input.addEventListener('input', function () { slider.value = input.value; });
                input.addEventListener('change', function () { slider.value = input.value; });

                var row = document.createElement('div');
                row.className = 'naFacePat__SliderRow';
                row.appendChild(slider);
                row.appendChild(input);
                group.appendChild(row);
            } else {
                group.appendChild(input);
            }

            if (field.hint) {
                var hint = document.createElement('div');
                hint.className = 'naFacePat__Hint';
                hint.textContent = field.hint;
                group.appendChild(hint);
            }

            na_state.groups[field.id] = group;
            container.appendChild(group);
        });

        na_applyFieldVisibility();
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Conditional Field Visibility
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Test a Field's showWhen Map Against the Live Control Values
    // ------------------------------------------------------------
    // showWhen: { source_field_id: ['allowed', 'values'] } — every named source
    // must currently hold one of its listed values for the field to show.
    function na_fieldVisible(field) {
        if (!field.showWhen) { return true; }

        return Object.keys(field.showWhen).every(function (sourceId) {
            var allowed = field.showWhen[sourceId] || [];
            var source  = na_el(sourceId);
            var current = source ? String(source.value) : String(na_state.values[sourceId]);
            return allowed.indexOf(current) !== -1;
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Show or Hide Every Conditional Control Group
    // ------------------------------------------------------------
    // Hidden groups keep their inputs in the DOM, so na_getValues still reports
    // them and generators can ignore the ones their layout does not use.
    function na_applyFieldVisibility() {
        na_state.fields.forEach(function (field) {
            var group = na_state.groups[field.id];
            if (!group) { return; }
            group.style.display = na_fieldVisible(field) ? '' : 'none';
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Preset Select Linking
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Write a Preset's Linked Field Values into Sibling Inputs
    // ------------------------------------------------------------
    function na_applyPresetValues(field, presetKey) {
        var mapping = field.applies[presetKey];
        if (!mapping) { return; }
        Object.keys(mapping).forEach(function (targetId) {
            var target = na_el(targetId);
            if (!target) { return; }
            target.value = mapping[targetId];
            na_state.values[targetId] = mapping[targetId];

            var pairedSlider = na_el(targetId + '_slider');                     // <-- Keep a slider field's range in step
            if (pairedSlider) { pairedSlider.value = mapping[targetId]; }
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Flip Preset Selects to Custom When a Linked Field Diverges
    // ------------------------------------------------------------
    function na_syncPresetSelects(changedFieldId) {
        na_state.fields.forEach(function (presetField) {
            if (!presetField.applies) { return; }
            var select = na_el(presetField.id);
            if (!select) { return; }
            var mapping = presetField.applies[select.value];
            if (!mapping || !Object.prototype.hasOwnProperty.call(mapping, changedFieldId)) { return; }
            var matches = Object.keys(mapping).every(function (targetId) {
                var target = na_el(targetId);
                return !target || Number(target.value) === Number(mapping[targetId]);
            });
            if (matches) { return; }
            var hasCustom = Array.prototype.some.call(select.options, function (option) {
                return option.value === 'custom';
            });
            if (!hasCustom) { return; }
            select.value = 'custom';
            na_state.values[presetField.id] = 'custom';
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Value Access and Status
    // -------------------------------------------------------------------------

    // FUNCTION | Read All Current Control Values
    // ------------------------------------------------------------
    function na_getValues() {
        var values = {};
        na_state.fields.forEach(function (field) {
            var el = na_el(field.id);
            if (!el) { return; }
            values[field.id] = na_isNumericField(field) ? Number(el.value) : el.value;
        });
        return values;
    }
    // ------------------------------------------------------------

    // FUNCTION | Read a Single Control Value by Field Id
    // ------------------------------------------------------------
    function na_getValue(fieldId) {
        return na_getValues()[fieldId];
    }
    // ------------------------------------------------------------

    // FUNCTION | Set the Footer Status Bar Message
    // ------------------------------------------------------------
    function na_setStatus(message, success) {
        var status = na_el(na_state.statusId);
        if (!status) { return; }
        status.textContent = message;
        status.className = success === false ? 'naFacePat__StatusText naFacePat__StatusText--error' : 'naFacePat__StatusText';
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    return {
        na_mount: na_mount,
        na_setFields: na_setFields,
        na_getValues: na_getValues,
        na_getValue: na_getValue,
        na_setStatus: na_setStatus
    };

})();

// =============================================================================
// END OF FILE
// =============================================================================
