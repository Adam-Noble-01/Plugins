(function () {
    'use strict';

    var Na__ComponentEditorTools__State = {
        payload: null,
        activeTab: 'overview'
    };

    function na_status_element() {
        return document.getElementById('na-component-status');
    }

    function na_set_status(message, variant) {
        var status_element = na_status_element();
        if (!status_element) return;

        status_element.textContent = String(message || '');
        status_element.className = 'naComponentEditor__StatusText';

        var variant_name = String(variant || 'info');
        if (variant_name === 'success') status_element.classList.add('naComponentEditor__StatusText--success');
        if (variant_name === 'error') status_element.classList.add('naComponentEditor__StatusText--error');
        if (variant_name === 'warning') status_element.classList.add('naComponentEditor__StatusText--warning');
    }

    function na_set_logo_uri(file_uri) {
        var logo_element = document.getElementById('na-component-logo');
        if (!logo_element || !file_uri) return;
        logo_element.src = String(file_uri);
    }

    function na_has_callback(callback_name) {
        return typeof window.sketchup !== 'undefined' && typeof window.sketchup[callback_name] === 'function';
    }

    function na_call_ruby(callback_name, payload_object) {
        if (!na_has_callback(callback_name)) {
            na_set_status('SketchUp callback not available: ' + callback_name, 'warning');
            return false;
        }

        try {
            if (payload_object === undefined) {
                window.sketchup[callback_name]();
            } else if (typeof payload_object === 'string') {
                window.sketchup[callback_name](payload_object);
            } else {
                window.sketchup[callback_name](JSON.stringify(payload_object));
            }
            return true;
        } catch (error) {
            na_set_status('Bridge call failed: ' + callback_name, 'error');
            console.error('[Na__ComponentEditorTools] Bridge call failed:', callback_name, error);
            return false;
        }
    }

    function na_render_tabs(payload) {
        if (window.Na__ComponentEditorTools__OverviewTab &&
            typeof window.Na__ComponentEditorTools__OverviewTab.Na__ComponentEditorTools__Render === 'function') {
            window.Na__ComponentEditorTools__OverviewTab.Na__ComponentEditorTools__Render(payload);
        }

        if (window.Na__ComponentEditorTools__AttributesTab &&
            typeof window.Na__ComponentEditorTools__AttributesTab.Na__ComponentEditorTools__Render === 'function') {
            window.Na__ComponentEditorTools__AttributesTab.Na__ComponentEditorTools__Render(payload);
        }

        if (window.Na__ComponentEditorTools__ThumbnailTab &&
            typeof window.Na__ComponentEditorTools__ThumbnailTab.Na__ComponentEditorTools__Render === 'function') {
            window.Na__ComponentEditorTools__ThumbnailTab.Na__ComponentEditorTools__Render(payload);
        }

        if (window.Na__ComponentEditorTools__SettingsTab &&
            typeof window.Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__Render === 'function') {
            window.Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__Render(payload);
        }
    }

    function Na__ComponentEditorTools__ReceiveStatus(status_payload) {
        if (!status_payload || typeof status_payload !== 'object') return;
        na_set_status(status_payload.message || '', status_payload.variant || 'info');
    }

    function Na__ComponentEditorTools__ReceivePayload(payload) {
        if (!payload || typeof payload !== 'object') return;

        Na__ComponentEditorTools__State.payload = payload;

        if (payload.ui && payload.ui.logo_file_uri) {
            na_set_logo_uri(payload.ui.logo_file_uri);
        }

        if (payload.status) {
            Na__ComponentEditorTools__ReceiveStatus(payload.status);
        }

        na_render_tabs(payload);

        var active_tab = (payload.ui && payload.ui.active_tab) || Na__ComponentEditorTools__State.activeTab || 'overview';
        Na__ComponentEditorTools__State.activeTab = active_tab;

        if (window.Na__ComponentEditorTools__TabRouter &&
            typeof window.Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab === 'function') {
            window.Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab(active_tab, false);
        }
    }

    function Na__ComponentEditorTools__SetActiveTab(active_tab_payload) {
        if (!active_tab_payload || typeof active_tab_payload !== 'object') return;

        var active_tab = String(active_tab_payload.active_tab || '').trim();
        if (!active_tab) return;

        Na__ComponentEditorTools__State.activeTab = active_tab;

        if (window.Na__ComponentEditorTools__TabRouter &&
            typeof window.Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab === 'function') {
            window.Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab(active_tab, false);
        }
    }

    function Na__ComponentEditorTools__NotifyActiveTab(active_tab_id) {
        Na__ComponentEditorTools__State.activeTab = String(active_tab_id || 'overview');
        na_call_ruby('na_componenteditortools_set_active_tab', Na__ComponentEditorTools__State.activeTab);
    }

    function Na__ComponentEditorTools__RequestSelection() {
        na_call_ruby('na_componenteditortools_request_selection');
    }

    function Na__ComponentEditorTools__ApplyBasicFields(payload) {
        na_call_ruby('na_componenteditortools_apply_basic_fields', payload || {});
    }

    function Na__ComponentEditorTools__UpdateComponent(payload) {
        na_call_ruby('na_componenteditortools_update_component', payload || {});
    }

    function Na__ComponentEditorTools__SetAttribute(payload) {
        na_call_ruby('na_componenteditortools_set_attribute', payload || {});
    }

    function Na__ComponentEditorTools__DeleteAttribute(payload) {
        na_call_ruby('na_componenteditortools_delete_attribute', payload || {});
    }

    function Na__ComponentEditorTools__RefreshThumbnail() {
        na_call_ruby('na_componenteditortools_refresh_thumbnail');
    }

    function Na__ComponentEditorTools__CaptureViewportPng() {
        na_call_ruby('na_componenteditortools_capture_viewport_png');
    }

    function Na__ComponentEditorTools__ReloadPlugin() {
        na_set_status('Reloading plugin...', 'info');
        na_call_ruby('na_componenteditortools_reload_plugin');
    }

    function Na__ComponentEditorTools__CurrentPayload() {
        return Na__ComponentEditorTools__State.payload;
    }

    window.Na__ComponentEditorTools__ReceiveStatus = Na__ComponentEditorTools__ReceiveStatus;
    window.Na__ComponentEditorTools__ReceivePayload = Na__ComponentEditorTools__ReceivePayload;
    window.Na__ComponentEditorTools__SetActiveTab = Na__ComponentEditorTools__SetActiveTab;
    window.Na__ComponentEditorTools__NotifyActiveTab = Na__ComponentEditorTools__NotifyActiveTab;
    window.Na__ComponentEditorTools__RequestSelection = Na__ComponentEditorTools__RequestSelection;
    window.Na__ComponentEditorTools__ApplyBasicFields = Na__ComponentEditorTools__ApplyBasicFields;
    window.Na__ComponentEditorTools__UpdateComponent = Na__ComponentEditorTools__UpdateComponent;
    window.Na__ComponentEditorTools__SetAttribute = Na__ComponentEditorTools__SetAttribute;
    window.Na__ComponentEditorTools__DeleteAttribute = Na__ComponentEditorTools__DeleteAttribute;
    window.Na__ComponentEditorTools__RefreshThumbnail = Na__ComponentEditorTools__RefreshThumbnail;
    window.Na__ComponentEditorTools__CaptureViewportPng = Na__ComponentEditorTools__CaptureViewportPng;
    window.Na__ComponentEditorTools__ReloadPlugin = Na__ComponentEditorTools__ReloadPlugin;
    window.Na__ComponentEditorTools__CurrentPayload = Na__ComponentEditorTools__CurrentPayload;

    document.addEventListener('DOMContentLoaded', function () {
        var refresh_button = document.getElementById('na-component-btn-header-refresh');
        if (refresh_button) {
            refresh_button.addEventListener('click', function () {
                Na__ComponentEditorTools__RequestSelection();
            });
        }

        var update_button = document.getElementById('na-component-btn-update-component');
        if (update_button) {
            update_button.addEventListener('click', function () {
                Na__ComponentEditorTools__UpdateComponent({
                    instance_name: document.getElementById('na-component-instance-name').value,
                    definition_name: document.getElementById('na-component-definition-name').value,
                    definition_description: document.getElementById('na-component-definition-description').value
                });
            });
        }

        Na__ComponentEditorTools__RequestSelection();
    });
})();
