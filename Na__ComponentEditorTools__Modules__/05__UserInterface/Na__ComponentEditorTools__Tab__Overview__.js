// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB | OVERVIEW
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__Tab__Overview__.js
// PURPOSE    : Render and manage the Overview tab content and event binding
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__OverviewTab = {};
    var na_events_bound = false;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Private Helpers
// -----------------------------------------------------------------------------

    function na_escape_html(value) {
        return String(value === null || value === undefined ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function na_to_text(value) {
        if (value === null || value === undefined) return '';
        if (Array.isArray(value)) return value.join(', ');
        if (typeof value === 'object') return JSON.stringify(value);
        return String(value);
    }

    function na_rows_from_hash(hash_object) {
        if (!hash_object || typeof hash_object !== 'object') {
            return '<p class="naComponentEditor__MutedText">No data available.</p>';
        }

        return Object.keys(hash_object).map(function (key_name) {
            return (
                '<div class="naComponentEditor__MetaRow">' +
                    '<div class="naComponentEditor__MetaKey">' + na_escape_html(key_name) + '</div>' +
                    '<div class="naComponentEditor__MetaValue">' + na_escape_html(na_to_text(hash_object[key_name])) + '</div>' +
                '</div>'
            );
        }).join('');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Event Binding
// -----------------------------------------------------------------------------

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        var apply_button = document.getElementById('na-component-btn-apply-fields');
        if (apply_button) {
            apply_button.addEventListener('click', function () {
                window.Na__ComponentEditorTools__ApplyBasicFields({
                    instance_name: document.getElementById('na-component-instance-name').value,
                    definition_name: document.getElementById('na-component-definition-name').value,
                    definition_description: document.getElementById('na-component-definition-description').value
                });
            });
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    Na__ComponentEditorTools__OverviewTab.Na__ComponentEditorTools__Render = function (payload) {
        na_bind_events_once();

        var message_element = document.getElementById('na-component-overview-message');
        var instance_data_element = document.getElementById('na-component-overview-instance-data');
        var definition_data_element = document.getElementById('na-component-overview-definition-data');
        var behavior_data_element = document.getElementById('na-component-overview-behavior-data');

        if (!payload || payload.ok !== true) {
            if (message_element) message_element.textContent = payload && payload.message ? payload.message : 'No component selected.';
            if (instance_data_element) instance_data_element.innerHTML = '';
            if (definition_data_element) definition_data_element.innerHTML = '';
            if (behavior_data_element) behavior_data_element.innerHTML = '';

            var instance_name_input = document.getElementById('na-component-instance-name');
            var definition_name_input = document.getElementById('na-component-definition-name');
            var definition_description_input = document.getElementById('na-component-definition-description');
            if (instance_name_input) instance_name_input.value = '';
            if (definition_name_input) definition_name_input.value = '';
            if (definition_description_input) definition_description_input.value = '';
            return;
        }

        if (message_element) {
            message_element.textContent = payload.message + ' Selected items: ' + payload.selected_count;
        }

        var instance_hash = Object.assign({}, payload.instance || {});
        var definition_hash = Object.assign({}, payload.definition || {});
        var behavior_hash = Object.assign({}, payload.behavior || {});

        if (instance_hash.bounds) instance_hash.bounds = na_to_text(instance_hash.bounds);
        if (instance_hash.transformation) instance_hash.transformation = na_to_text(instance_hash.transformation);
        if (definition_hash.thumbnail_camera) definition_hash.thumbnail_camera = '[See Thumbnail tab]';

        if (instance_data_element) instance_data_element.innerHTML = na_rows_from_hash(instance_hash);
        if (definition_data_element) definition_data_element.innerHTML = na_rows_from_hash(definition_hash);
        if (behavior_data_element) behavior_data_element.innerHTML = na_rows_from_hash(behavior_hash);

        var instance_name_input = document.getElementById('na-component-instance-name');
        var definition_name_input = document.getElementById('na-component-definition-name');
        var definition_description_input = document.getElementById('na-component-definition-description');
        if (instance_name_input) instance_name_input.value = payload.instance && payload.instance.name ? payload.instance.name : '';
        if (definition_name_input) definition_name_input.value = payload.definition && payload.definition.name ? payload.definition.name : '';
        if (definition_description_input) {
            definition_description_input.value = payload.definition && payload.definition.description ? payload.definition.description : '';
        }
    };

    window.Na__ComponentEditorTools__OverviewTab = Na__ComponentEditorTools__OverviewTab;

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
