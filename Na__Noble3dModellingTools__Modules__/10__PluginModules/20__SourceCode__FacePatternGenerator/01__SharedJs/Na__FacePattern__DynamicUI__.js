// =============================================================================
// NA NOBLE3D MODELLING TOOLS - FACE PATTERN - DYNAMIC UI
// =============================================================================
//
// FILE       : Na__FacePattern__DynamicUI__.js
// NAMESPACE  : window.Na__FacePattern__DynamicUI
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : JSON-config-driven control panel builder — number inputs and
//              selects from field-descriptor arrays in UiConfig.
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

            function na_onFieldChange() {
                na_state.values[field.id] = field.type === 'number' ? Number(input.value) : input.value;
                if (na_state.onChange) { na_state.onChange(field.id, na_state.values[field.id]); }
            }

            input.addEventListener('input', na_onFieldChange);
            input.addEventListener('change', na_onFieldChange);
            group.appendChild(input);

            if (field.hint) {
                var hint = document.createElement('div');
                hint.className = 'naFacePat__Hint';
                hint.textContent = field.hint;
                group.appendChild(hint);
            }

            container.appendChild(group);
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
            values[field.id] = field.type === 'number' ? Number(el.value) : el.value;
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
