(function () {
    'use strict';

    var Na__ComponentEditorTools__AttributesTab = {};
    var na_events_bound = false;

    function na_escape_html(value) {
        return String(value === null || value === undefined ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function na_default_type_for_class(value_class_name) {
        var normalized = String(value_class_name || '').toLowerCase();
        if (normalized.indexOf('integer') >= 0 || normalized.indexOf('fixnum') >= 0) return 'integer';
        if (normalized.indexOf('float') >= 0) return 'float';
        if (normalized.indexOf('trueclass') >= 0 || normalized.indexOf('falseclass') >= 0 || normalized === 'boolean') return 'boolean';
        return 'string';
    }

    function na_type_select_html(default_type) {
        var types = ['string', 'integer', 'float', 'boolean'];
        return (
            '<select class="naComponentEditor__Select na-component-attr-existing-type">' +
            types.map(function (type_name) {
                var selected = type_name === default_type ? ' selected' : '';
                return '<option value="' + type_name + '"' + selected + '>' + type_name + '</option>';
            }).join('') +
            '</select>'
        );
    }

    function na_dictionary_html(scope_name, dictionaries) {
        if (!dictionaries || !dictionaries.length) {
            return '<p class="naComponentEditor__MutedText">No attribute dictionaries found.</p>';
        }

        return dictionaries.map(function (dictionary) {
            var rows_html = (dictionary.pairs || []).map(function (pair) {
                var default_type = na_default_type_for_class(pair.value_class);
                return (
                    '<tr data-scope="' + na_escape_html(scope_name) + '" data-dictionary="' + na_escape_html(dictionary.name) + '" data-key="' + na_escape_html(pair.key) + '">' +
                        '<td>' + na_escape_html(pair.key) + '</td>' +
                        '<td><input class="naComponentEditor__Input na-component-attr-existing-value" type="text" value="' + na_escape_html(pair.value) + '"></td>' +
                        '<td>' + na_escape_html(pair.value_class) + '</td>' +
                        '<td>' +
                            '<div class="naComponentEditor__AttributeControls">' +
                                na_type_select_html(default_type) +
                                '<button class="naComponentEditor__Button" data-action="save-existing" type="button">Save</button>' +
                                '<button class="naComponentEditor__Button naComponentEditor__Button--danger" data-action="delete-existing" type="button">Delete</button>' +
                            '</div>' +
                        '</td>' +
                    '</tr>'
                );
            }).join('');

            return (
                '<div class="naComponentEditor__Dictionary">' +
                    '<h3 class="naComponentEditor__DictionaryTitle">' + na_escape_html(dictionary.name) + '</h3>' +
                    '<table class="naComponentEditor__AttributeTable">' +
                        '<thead><tr><th>Key</th><th>Value</th><th>Stored Type</th><th>Actions</th></tr></thead>' +
                        '<tbody>' + rows_html + '</tbody>' +
                    '</table>' +
                '</div>'
            );
        }).join('');
    }

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        var set_attribute_button = document.getElementById('na-component-btn-set-attribute');
        if (set_attribute_button) {
            set_attribute_button.addEventListener('click', function () {
                window.Na__ComponentEditorTools__SetAttribute({
                    scope: document.getElementById('na-component-attr-scope').value,
                    dictionary: document.getElementById('na-component-attr-dictionary').value,
                    key: document.getElementById('na-component-attr-key').value,
                    value: document.getElementById('na-component-attr-value').value,
                    value_type: document.getElementById('na-component-attr-type').value
                });
            });
        }

        ['na-component-attributes-instance', 'na-component-attributes-definition'].forEach(function (container_id) {
            var container = document.getElementById(container_id);
            if (!container) return;

            container.addEventListener('click', function (event_object) {
                var target_button = event_object.target.closest('button[data-action]');
                if (!target_button) return;

                var target_row = target_button.closest('tr[data-scope][data-dictionary][data-key]');
                if (!target_row) return;

                var payload = {
                    scope: target_row.getAttribute('data-scope'),
                    dictionary: target_row.getAttribute('data-dictionary'),
                    key: target_row.getAttribute('data-key')
                };

                if (target_button.getAttribute('data-action') === 'save-existing') {
                    var value_input = target_row.querySelector('.na-component-attr-existing-value');
                    var type_select = target_row.querySelector('.na-component-attr-existing-type');
                    payload.value = value_input ? value_input.value : '';
                    payload.value_type = type_select ? type_select.value : 'string';
                    window.Na__ComponentEditorTools__SetAttribute(payload);
                }

                if (target_button.getAttribute('data-action') === 'delete-existing') {
                    window.Na__ComponentEditorTools__DeleteAttribute(payload);
                }
            });
        });
    }

    Na__ComponentEditorTools__AttributesTab.Na__ComponentEditorTools__Render = function (payload) {
        na_bind_events_once();

        var message_element = document.getElementById('na-component-attributes-message');
        var instance_container = document.getElementById('na-component-attributes-instance');
        var definition_container = document.getElementById('na-component-attributes-definition');

        if (!payload || payload.ok !== true) {
            if (message_element) message_element.textContent = payload && payload.message ? payload.message : 'No component selected.';
            if (instance_container) instance_container.innerHTML = '';
            if (definition_container) definition_container.innerHTML = '';
            return;
        }

        if (message_element) message_element.textContent = 'Editing attributes for the current selection.';
        if (instance_container) {
            instance_container.innerHTML = na_dictionary_html('instance', payload.attributes ? payload.attributes.instance : []);
        }
        if (definition_container) {
            definition_container.innerHTML = na_dictionary_html('definition', payload.attributes ? payload.attributes.definition : []);
        }
    };

    window.Na__ComponentEditorTools__AttributesTab = Na__ComponentEditorTools__AttributesTab;
})();
