(function () {
    'use strict';

    var na_state = {
        containerId: null,
        statusId: null,
        fields: [],
        values: {},
        onChange: null
    };

    function na_el(id) {
        return document.getElementById(id);
    }

    function na_mount(options) {
        na_state.containerId = options.containerId;
        na_state.statusId = options.statusId;
        na_state.onChange = typeof options.onChange === 'function' ? options.onChange : null;
    }

    function na_setFields(fields) {
        na_state.fields = fields || [];
        na_state.values = {};
        na_render();
    }

    function na_render() {
        var container = na_el(na_state.containerId);
        if (!container) {
            return;
        }

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
                    if (option.value === field.default) {
                        optionEl.selected = true;
                    }
                    input.appendChild(optionEl);
                });
            } else {
                input.type = 'number';
                input.value = field.default;
                if (field.min !== undefined) { input.min = field.min; }
                if (field.max !== undefined) { input.max = field.max; }
                if (field.step !== undefined) { input.step = field.step; }
            }

            input.addEventListener('input', function () {
                na_state.values[field.id] = field.type === 'number' ? Number(input.value) : input.value;
                if (na_state.onChange) {
                    na_state.onChange(field.id, na_state.values[field.id]);
                }
            });
            input.addEventListener('change', function () {
                na_state.values[field.id] = field.type === 'number' ? Number(input.value) : input.value;
                if (na_state.onChange) {
                    na_state.onChange(field.id, na_state.values[field.id]);
                }
            });

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

    function na_getValues() {
        var values = {};
        na_state.fields.forEach(function (field) {
            var el = na_el(field.id);
            if (!el) {
                return;
            }
            values[field.id] = field.type === 'number' ? Number(el.value) : el.value;
        });
        return values;
    }

    function na_getValue(fieldId) {
        return na_getValues()[fieldId];
    }

    function na_setStatus(message, success) {
        var status = na_el(na_state.statusId);
        if (!status) {
            return;
        }
        status.textContent = message;
        status.className = success === false ? 'naFacePat__StatusBar naFacePat__StatusBar--error' : 'naFacePat__StatusBar';
    }

    window.Na__FacePattern__DynamicUI = {
        na_mount: na_mount,
        na_setFields: na_setFields,
        na_getValues: na_getValues,
        na_getValue: na_getValue,
        na_setStatus: na_setStatus
    };
})();
