// =============================================================================
// NA COMPONENT EDITOR TOOLS - UI BRIDGE
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__UiBridge__.js
// PURPOSE    : JS-to-Ruby bridge, global state, incoming payload handlers,
//              and outgoing SketchUp callback dispatch
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__State = {
        payload:            null,
        activeTab:          'overview',
        userConfig:         null,
        galleryData:        null,
        indexData:          null,
        taxonomy:           null,
        monitoringEnabled:  false
    };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Status Bar
// -----------------------------------------------------------------------------

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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | SketchUp Bridge
// -----------------------------------------------------------------------------

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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Tab Renderers
// -----------------------------------------------------------------------------

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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Incoming Handlers
// -----------------------------------------------------------------------------

    function Na__ComponentEditorTools__ReceiveStatus(status_payload) {
        if (!status_payload || typeof status_payload !== 'object') return;
        na_set_status(status_payload.message || '', status_payload.variant || 'info');
    }

    function Na__ComponentEditorTools__ReceivePayload(payload) {
        if (!payload || typeof payload !== 'object') return;

        Na__ComponentEditorTools__State.payload = payload;

        if (payload.status) {
            Na__ComponentEditorTools__ReceiveStatus(payload.status);
        }

        // Drive the capture overlay: show when not yet captured
        var is_awaiting = payload.captured !== true;
        document.body.classList.toggle('naComponentEditor--awaitingCapture', is_awaiting);

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

    function Na__ComponentEditorTools__ReceiveUserConfig(config_payload) {
        if (!config_payload || typeof config_payload !== 'object') return;
        Na__ComponentEditorTools__State.userConfig = config_payload;

        if (window.Na__ComponentEditorTools__SettingsTab &&
            typeof window.Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__RenderConfig === 'function') {
            window.Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__RenderConfig(config_payload);
        }

        if (window.Na__ComponentEditorTools__GalleryTab &&
            typeof window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__RefreshFolderFilter === 'function') {
            window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__RefreshFolderFilter();
        }

        if (window.Na__ComponentEditorTools__IndexTab &&
            typeof window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__RefreshFolderFilter === 'function') {
            window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__RefreshFolderFilter();
        }
    }

    function Na__ComponentEditorTools__ReceiveGallery(gallery_payload) {
        if (!gallery_payload || typeof gallery_payload !== 'object') return;
        Na__ComponentEditorTools__State.galleryData = gallery_payload;

        if (gallery_payload.message) na_set_status(gallery_payload.message, 'info');

        if (window.Na__ComponentEditorTools__GalleryTab &&
            typeof window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__RenderGallery === 'function') {
            window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__RenderGallery(gallery_payload);
        }
    }

    function Na__ComponentEditorTools__ReceiveIndex(index_payload) {
        if (!index_payload || typeof index_payload !== 'object') return;
        Na__ComponentEditorTools__State.indexData = index_payload;

        if (window.Na__ComponentEditorTools__IndexTab &&
            typeof window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__RenderIndex === 'function') {
            window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__RenderIndex(index_payload);
        }
    }

    function Na__ComponentEditorTools__ReceiveTaxonomy(taxonomy_payload) {
        if (!taxonomy_payload || typeof taxonomy_payload !== 'object') return;
        Na__ComponentEditorTools__State.taxonomy = taxonomy_payload;

        if (window.Na__ComponentEditorTools__SettingsTab &&
            typeof window.Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__RenderTaxonomy === 'function') {
            window.Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__RenderTaxonomy(taxonomy_payload);
        }

        if (window.Na__ComponentEditorTools__IndexTab &&
            typeof window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__SetTaxonomy === 'function') {
            window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__SetTaxonomy(taxonomy_payload);
        }

        if (window.Na__ComponentEditorTools__GalleryTab &&
            typeof window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__SetTaxonomy === 'function') {
            window.Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__SetTaxonomy(taxonomy_payload);
        }
    }

    function Na__ComponentEditorTools__ReceiveEntryUpdate(update_payload) {
        if (!update_payload || typeof update_payload !== 'object') return;

        if (window.Na__ComponentEditorTools__IndexTab &&
            typeof window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__ApplyEntryUpdate === 'function') {
            window.Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__ApplyEntryUpdate(
                update_payload.old_path, update_payload.entry
            );
        }
    }

    function Na__ComponentEditorTools__ReceiveMonitoringState(monitoring_payload) {
        if (!monitoring_payload || typeof monitoring_payload !== 'object') return;

        var enabled = !!monitoring_payload.enabled;
        Na__ComponentEditorTools__State.monitoringEnabled = enabled;

        var monitor_btn = document.getElementById('na-component-btn-monitor-selection');
        if (monitor_btn) {
            monitor_btn.classList.toggle('naComponentEditor__MonitorBtn--on',  enabled);
            monitor_btn.classList.toggle('naComponentEditor__MonitorBtn--off', !enabled);
            monitor_btn.textContent = enabled ? 'Monitor Selection: On' : 'Monitor Selection: Off';
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Outgoing Ruby Calls
// -----------------------------------------------------------------------------

    function Na__ComponentEditorTools__SetMonitoring(enabled_flag) {
        na_call_ruby('na_componenteditortools_set_monitoring', { enabled: !!enabled_flag });
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

    function Na__ComponentEditorTools__GetUserConfig() {
        na_call_ruby('na_componenteditortools_get_user_config');
    }

    function Na__ComponentEditorTools__SetLibraryPath() {
        na_set_status('Selecting library folder...', 'info');
        na_call_ruby('na_componenteditortools_set_library_path');
    }

    function Na__ComponentEditorTools__AddBlockedFolder(folder_name) {
        na_call_ruby('na_componenteditortools_add_blocked_folder', { folder_name: folder_name || '' });
    }

    function Na__ComponentEditorTools__RemoveBlockedFolder(folder_name) {
        na_call_ruby('na_componenteditortools_remove_blocked_folder', { folder_name: folder_name || '' });
    }

    function Na__ComponentEditorTools__AddBlockedFile(file_name) {
        na_call_ruby('na_componenteditortools_add_blocked_file', { file_name: file_name || '' });
    }

    function Na__ComponentEditorTools__RemoveBlockedFile(file_name) {
        na_call_ruby('na_componenteditortools_remove_blocked_file', { file_name: file_name || '' });
    }

    function Na__ComponentEditorTools__ScanLibrary() {
        na_set_status('Loading library...', 'info');
        na_call_ruby('na_componenteditortools_scan_library');
    }

    function Na__ComponentEditorTools__RefreshLibrary() {
        na_set_status('Refreshing library index...', 'info');
        na_call_ruby('na_componenteditortools_refresh_library');
    }

    function Na__ComponentEditorTools__GetGallery() {
        na_call_ruby('na_componenteditortools_get_gallery');
    }

    function Na__ComponentEditorTools__GetIndex() {
        na_call_ruby('na_componenteditortools_get_index');
    }

    function Na__ComponentEditorTools__InsertLibraryComponent(component_path) {
        na_call_ruby('na_componenteditortools_insert_library_component', { path: component_path || '' });
    }

    function Na__ComponentEditorTools__InsertAtAxis(component_path) {
        na_call_ruby('na_componenteditortools_insert_at_axis', { path: component_path || '' });
    }

    function Na__ComponentEditorTools__OpenComponentFile(component_path) {
        na_call_ruby('na_componenteditortools_open_component_file', { path: component_path || '' });
    }

    function Na__ComponentEditorTools__CopyComponentPath(component_path) {
        na_call_ruby('na_componenteditortools_copy_component_path', { path: component_path || '' });
    }

    function Na__ComponentEditorTools__CopyDirectoryPath(dir_path) {
        na_call_ruby('na_componenteditortools_copy_directory_path', { path: dir_path || '' });
    }

    function Na__ComponentEditorTools__SetFolderAlias(folder_name, alias_label, order_index) {
        na_call_ruby('na_componenteditortools_set_folder_alias', {
            folder_name:  folder_name  || '',
            alias_label:  alias_label  || '',
            order_index:  order_index  || 0
        });
    }

    function Na__ComponentEditorTools__RemoveFolderAlias(folder_name) {
        na_call_ruby('na_componenteditortools_remove_folder_alias', { folder_name: folder_name || '' });
    }

    function Na__ComponentEditorTools__RenameLibraryComponent(payload) {
        na_call_ruby('na_componenteditortools_rename_library_component', payload || {});
    }

    function Na__ComponentEditorTools__UpdateLibraryMetadata(payload) {
        na_call_ruby('na_componenteditortools_update_library_metadata', payload || {});
    }

    function Na__ComponentEditorTools__UpdateLibraryData(payload) {
        na_call_ruby('na_componenteditortools_update_library_data', payload || {});
    }

    function Na__ComponentEditorTools__UpdateField(payload) {
        na_call_ruby('na_componenteditortools_update_field', payload || {});
    }

    function Na__ComponentEditorTools__GetTaxonomy() {
        na_call_ruby('na_componenteditortools_get_taxonomy');
    }

    function Na__ComponentEditorTools__AddCategory(category_name) {
        na_call_ruby('na_componenteditortools_add_category', { category: category_name || '' });
    }

    function Na__ComponentEditorTools__RemoveCategory(category_name) {
        na_call_ruby('na_componenteditortools_remove_category', { category: category_name || '' });
    }

    function Na__ComponentEditorTools__AddType(category_name, type_name) {
        na_call_ruby('na_componenteditortools_add_type', { category: category_name || '', type: type_name || '' });
    }

    function Na__ComponentEditorTools__RemoveType(category_name, type_name) {
        na_call_ruby('na_componenteditortools_remove_type', { category: category_name || '', type: type_name || '' });
    }

    function Na__ComponentEditorTools__SetChipColor(key, hex_color) {
        na_call_ruby('na_componenteditortools_set_chip_color', { key: key || '', color: hex_color || '' });
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | State Accessors
// -----------------------------------------------------------------------------

    function Na__ComponentEditorTools__CurrentPayload() {
        return Na__ComponentEditorTools__State.payload;
    }

    function Na__ComponentEditorTools__CurrentGalleryData() {
        return Na__ComponentEditorTools__State.galleryData;
    }

    function Na__ComponentEditorTools__CurrentIndexData() {
        return Na__ComponentEditorTools__State.indexData;
    }

    function Na__ComponentEditorTools__CurrentUserConfig() {
        return Na__ComponentEditorTools__State.userConfig;
    }

    function Na__ComponentEditorTools__CurrentTaxonomy() {
        return Na__ComponentEditorTools__State.taxonomy;
    }

    function Na__ComponentEditorTools__CurrentFolderAliases() {
        var config = Na__ComponentEditorTools__State.userConfig;
        return (config && config.folder_aliases && typeof config.folder_aliases === 'object')
            ? config.folder_aliases
            : {};
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Window Exports
// -----------------------------------------------------------------------------

    window.Na__ComponentEditorTools__ReceiveStatus           = Na__ComponentEditorTools__ReceiveStatus;
    window.Na__ComponentEditorTools__ReceivePayload          = Na__ComponentEditorTools__ReceivePayload;
    window.Na__ComponentEditorTools__ReceiveMonitoringState  = Na__ComponentEditorTools__ReceiveMonitoringState;
    window.Na__ComponentEditorTools__SetMonitoring           = Na__ComponentEditorTools__SetMonitoring;
    window.Na__ComponentEditorTools__ReceiveUserConfig       = Na__ComponentEditorTools__ReceiveUserConfig;
    window.Na__ComponentEditorTools__ReceiveGallery          = Na__ComponentEditorTools__ReceiveGallery;
    window.Na__ComponentEditorTools__ReceiveIndex            = Na__ComponentEditorTools__ReceiveIndex;
    window.Na__ComponentEditorTools__ReceiveEntryUpdate      = Na__ComponentEditorTools__ReceiveEntryUpdate;
    window.Na__ComponentEditorTools__ReceiveTaxonomy         = Na__ComponentEditorTools__ReceiveTaxonomy;
    window.Na__ComponentEditorTools__SetActiveTab            = Na__ComponentEditorTools__SetActiveTab;
    window.Na__ComponentEditorTools__NotifyActiveTab         = Na__ComponentEditorTools__NotifyActiveTab;
    window.Na__ComponentEditorTools__RequestSelection        = Na__ComponentEditorTools__RequestSelection;
    window.Na__ComponentEditorTools__ApplyBasicFields        = Na__ComponentEditorTools__ApplyBasicFields;
    window.Na__ComponentEditorTools__UpdateComponent         = Na__ComponentEditorTools__UpdateComponent;
    window.Na__ComponentEditorTools__SetAttribute            = Na__ComponentEditorTools__SetAttribute;
    window.Na__ComponentEditorTools__DeleteAttribute         = Na__ComponentEditorTools__DeleteAttribute;
    window.Na__ComponentEditorTools__RefreshThumbnail        = Na__ComponentEditorTools__RefreshThumbnail;
    window.Na__ComponentEditorTools__CaptureViewportPng      = Na__ComponentEditorTools__CaptureViewportPng;
    window.Na__ComponentEditorTools__ReloadPlugin            = Na__ComponentEditorTools__ReloadPlugin;
    window.Na__ComponentEditorTools__GetUserConfig           = Na__ComponentEditorTools__GetUserConfig;
    window.Na__ComponentEditorTools__SetLibraryPath          = Na__ComponentEditorTools__SetLibraryPath;
    window.Na__ComponentEditorTools__AddBlockedFolder        = Na__ComponentEditorTools__AddBlockedFolder;
    window.Na__ComponentEditorTools__RemoveBlockedFolder     = Na__ComponentEditorTools__RemoveBlockedFolder;
    window.Na__ComponentEditorTools__AddBlockedFile          = Na__ComponentEditorTools__AddBlockedFile;
    window.Na__ComponentEditorTools__RemoveBlockedFile       = Na__ComponentEditorTools__RemoveBlockedFile;
    window.Na__ComponentEditorTools__ScanLibrary             = Na__ComponentEditorTools__ScanLibrary;
    window.Na__ComponentEditorTools__RefreshLibrary          = Na__ComponentEditorTools__RefreshLibrary;
    window.Na__ComponentEditorTools__GetGallery              = Na__ComponentEditorTools__GetGallery;
    window.Na__ComponentEditorTools__GetIndex                = Na__ComponentEditorTools__GetIndex;
    window.Na__ComponentEditorTools__InsertLibraryComponent  = Na__ComponentEditorTools__InsertLibraryComponent;
    window.Na__ComponentEditorTools__InsertAtAxis             = Na__ComponentEditorTools__InsertAtAxis;
    window.Na__ComponentEditorTools__OpenComponentFile        = Na__ComponentEditorTools__OpenComponentFile;
    window.Na__ComponentEditorTools__CopyComponentPath        = Na__ComponentEditorTools__CopyComponentPath;
    window.Na__ComponentEditorTools__CopyDirectoryPath        = Na__ComponentEditorTools__CopyDirectoryPath;
    window.Na__ComponentEditorTools__SetFolderAlias            = Na__ComponentEditorTools__SetFolderAlias;
    window.Na__ComponentEditorTools__RemoveFolderAlias         = Na__ComponentEditorTools__RemoveFolderAlias;
    window.Na__ComponentEditorTools__RenameLibraryComponent  = Na__ComponentEditorTools__RenameLibraryComponent;
    window.Na__ComponentEditorTools__UpdateLibraryMetadata   = Na__ComponentEditorTools__UpdateLibraryMetadata;
    window.Na__ComponentEditorTools__UpdateLibraryData       = Na__ComponentEditorTools__UpdateLibraryData;
    window.Na__ComponentEditorTools__UpdateField             = Na__ComponentEditorTools__UpdateField;
    window.Na__ComponentEditorTools__GetTaxonomy             = Na__ComponentEditorTools__GetTaxonomy;
    window.Na__ComponentEditorTools__AddCategory             = Na__ComponentEditorTools__AddCategory;
    window.Na__ComponentEditorTools__RemoveCategory          = Na__ComponentEditorTools__RemoveCategory;
    window.Na__ComponentEditorTools__AddType                 = Na__ComponentEditorTools__AddType;
    window.Na__ComponentEditorTools__RemoveType              = Na__ComponentEditorTools__RemoveType;
    window.Na__ComponentEditorTools__SetChipColor            = Na__ComponentEditorTools__SetChipColor;
    window.Na__ComponentEditorTools__CurrentPayload          = Na__ComponentEditorTools__CurrentPayload;
    window.Na__ComponentEditorTools__CurrentGalleryData      = Na__ComponentEditorTools__CurrentGalleryData;
    window.Na__ComponentEditorTools__CurrentIndexData        = Na__ComponentEditorTools__CurrentIndexData;
    window.Na__ComponentEditorTools__CurrentUserConfig       = Na__ComponentEditorTools__CurrentUserConfig;
    window.Na__ComponentEditorTools__CurrentTaxonomy         = Na__ComponentEditorTools__CurrentTaxonomy;
    window.Na__ComponentEditorTools__CurrentFolderAliases    = Na__ComponentEditorTools__CurrentFolderAliases;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Init
// -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        var refresh_button = document.getElementById('na-component-btn-header-refresh');
        if (refresh_button) {
            refresh_button.addEventListener('click', function () {
                if (window.confirm('Reload Library? This will re-scan and re-extract all component files and may take a moment.')) {
                    Na__ComponentEditorTools__RefreshLibrary();
                }
            });
        }

        var update_button = document.getElementById('na-component-btn-update-component');
        if (update_button) {
            update_button.addEventListener('click', function () {
                if (window.confirm('Apply component updates to the selected SketchUp entity?')) {
                    Na__ComponentEditorTools__UpdateComponent({
                        instance_name: document.getElementById('na-component-instance-name').value,
                        definition_name: document.getElementById('na-component-definition-name').value,
                        definition_description: document.getElementById('na-component-definition-description').value
                    });
                }
            });
        }

        // Monitor Selection toggle button
        var monitor_btn = document.getElementById('na-component-btn-monitor-selection');
        if (monitor_btn) {
            monitor_btn.addEventListener('click', function () {
                var now_enabled = !Na__ComponentEditorTools__State.monitoringEnabled;
                Na__ComponentEditorTools__SetMonitoring(now_enabled);
            });
        }

        // Capture overlay buttons — delegate on document since overlays may be
        // inside any auditing tab panel.
        document.addEventListener('click', function (event) {
            if (event.target && event.target.classList.contains('naComponentEditor__CaptureOverlayBtn')) {
                Na__ComponentEditorTools__SetMonitoring(true);
            }
        });

        Na__ComponentEditorTools__RequestSelection();
        Na__ComponentEditorTools__GetTaxonomy();
    });

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Chip Color Utility (shared by Gallery and Index)
// -----------------------------------------------------------------------------

    var NA_CHIP_PALETTE = [
        { bg: '#e5f4ec', border: '#a3cfb6', text: '#1a6b3a' },
        { bg: '#eef3fb', border: '#c9d8f0', text: '#2060b8' },
        { bg: '#fef4e0', border: '#f0c878', text: '#7a4800' },
        { bg: '#f2ecfb', border: '#c5a8e8', text: '#5a2a8a' },
        { bg: '#e5f5f5', border: '#8ecece', text: '#1a6b6b' },
        { bg: '#fce8ed', border: '#e8a0b0', text: '#8a2040' },
        { bg: '#feebd8', border: '#f0aa70', text: '#7a3800' },
        { bg: '#eceef8', border: '#a8b0e0', text: '#2a3880' },
        { bg: '#f4ede5', border: '#c8a888', text: '#5a3810' },
        { bg: '#edf0f4', border: '#b0bcc8', text: '#3a4858' }
    ];

    function na_chip_hash(name) {
        var h = 0;
        for (var i = 0; i < name.length; i++) {
            h = (h * 31 + name.charCodeAt(i)) & 0xffff;
        }
        return h;
    }

    function na_hex_to_rgb(hex) {
        var clean = hex.replace('#', '');
        if (clean.length === 3) {
            clean = clean[0] + clean[0] + clean[1] + clean[1] + clean[2] + clean[2];
        }
        return {
            r: parseInt(clean.substring(0, 2), 16),
            g: parseInt(clean.substring(2, 4), 16),
            b: parseInt(clean.substring(4, 6), 16)
        };
    }

    function na_rgb_to_hex(r, g, b) {
        function na_pad(n) { var s = n.toString(16); return s.length === 1 ? '0' + s : s; }
        return '#' + na_pad(r) + na_pad(g) + na_pad(b);
    }

    function na_clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function na_derive_chip_colors_from_hex(hex) {
        var rgb = na_hex_to_rgb(hex);
        var bg_r = na_clamp(Math.round(rgb.r * 0.15 + 255 * 0.85), 0, 255);
        var bg_g = na_clamp(Math.round(rgb.g * 0.15 + 255 * 0.85), 0, 255);
        var bg_b = na_clamp(Math.round(rgb.b * 0.15 + 255 * 0.85), 0, 255);
        var bd_r = na_clamp(Math.round(rgb.r * 0.45 + 255 * 0.55), 0, 255);
        var bd_g = na_clamp(Math.round(rgb.g * 0.45 + 255 * 0.55), 0, 255);
        var bd_b = na_clamp(Math.round(rgb.b * 0.45 + 255 * 0.55), 0, 255);
        var tx_r = na_clamp(Math.round(rgb.r * 0.55), 0, 255);
        var tx_g = na_clamp(Math.round(rgb.g * 0.55), 0, 255);
        var tx_b = na_clamp(Math.round(rgb.b * 0.55), 0, 255);
        return {
            bg:     na_rgb_to_hex(bg_r, bg_g, bg_b),
            border: na_rgb_to_hex(bd_r, bd_g, bd_b),
            text:   na_rgb_to_hex(tx_r, tx_g, tx_b)
        };
    }

    window.Na__ComponentEditorTools__ApplyChipColor = function (el, name) {
        if (!el || !name) return;
        var taxonomy      = Na__ComponentEditorTools__State.taxonomy;
        var chip_colors   = (taxonomy && taxonomy.chip_colors) ? taxonomy.chip_colors : {};
        var stored_hex    = chip_colors[name];
        var color;
        if (stored_hex && /^#[0-9a-fA-F]{3,6}$/.test(stored_hex)) {
            color = na_derive_chip_colors_from_hex(stored_hex);
        } else {
            color = NA_CHIP_PALETTE[na_chip_hash(name) % NA_CHIP_PALETTE.length];
        }
        el.style.background  = color.bg;
        el.style.borderColor = color.border;
        el.style.color       = color.text;
    };

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
