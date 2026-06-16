// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB | THUMBNAIL
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__Tab__Thumbnail__.js
// PURPOSE    : Render and manage the Thumbnail tab content and event binding
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__ThumbnailTab = {};
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

    function na_rows(hash_object, mono_value) {
        if (!hash_object || typeof hash_object !== 'object') {
            return '<p class="naComponentEditor__MutedText">No data available.</p>';
        }

        var keys = Object.keys(hash_object);
        if (!keys.length) return '<p class="naComponentEditor__MutedText">No data available.</p>';

        return keys.map(function (key_name) {
            var value_text = na_to_text(hash_object[key_name]);
            var value_class = mono_value ? 'naComponentEditor__MetaValue naComponentEditor__Mono' : 'naComponentEditor__MetaValue';

            return (
                '<div class="naComponentEditor__MetaRow">' +
                    '<div class="naComponentEditor__MetaKey">' + na_escape_html(key_name) + '</div>' +
                    '<div class="' + value_class + '">' + na_escape_html(value_text) + '</div>' +
                '</div>'
            );
        }).join('');
    }

    function na_export_paths_data(temp_payload) {
        var export_data = Object.assign({}, temp_payload || {});
        var preview_source = export_data.current_thumbnail_preview_source || '';

        export_data.current_render_preview_path = export_data.current_thumbnail_preview_path || '';
        export_data.current_render_preview_source = preview_source === 'visible_viewport'
            ? 'saved visible viewport framebuffer render'
            : 'SketchUp component thumbnail export';

        delete export_data.current_thumbnail_preview_path;
        delete export_data.current_thumbnail_preview_uri;
        delete export_data.current_thumbnail_preview_source;
        delete export_data.current_thumbnail_preview_error;

        return export_data;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Thumbnail Preview
// -----------------------------------------------------------------------------

    function na_set_thumbnail_preview(temp_payload) {
        var image_element = document.getElementById('na-component-thumbnail-preview-image');
        if (!image_element) return;

        var preview_uri = temp_payload && temp_payload.current_thumbnail_preview_uri ? String(temp_payload.current_thumbnail_preview_uri) : '';

        if (preview_uri) {
            image_element.src = preview_uri;
            image_element.style.display = 'block';
        } else {
            image_element.removeAttribute('src');
            image_element.style.display = 'none';
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Event Binding
// -----------------------------------------------------------------------------

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        var refresh_button = document.getElementById('na-component-btn-refresh-thumbnail');
        if (refresh_button) {
            refresh_button.addEventListener('click', function () {
                window.Na__ComponentEditorTools__RefreshThumbnail();
            });
        }

        var capture_button = document.getElementById('na-component-btn-capture-viewport');
        if (capture_button) {
            capture_button.addEventListener('click', function () {
                window.Na__ComponentEditorTools__CaptureViewportPng();
            });
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    Na__ComponentEditorTools__ThumbnailTab.Na__ComponentEditorTools__Render = function (payload) {
        na_bind_events_once();

        var message_element = document.getElementById('na-component-thumbnail-message');
        var camera_element = document.getElementById('na-component-thumbnail-camera');
        var temp_paths_element = document.getElementById('na-component-thumbnail-temp-paths');

        if (!payload || payload.ok !== true) {
            if (message_element) message_element.textContent = payload && payload.message ? payload.message : 'No component selected.';
            if (camera_element) camera_element.innerHTML = '';
            if (temp_paths_element) temp_paths_element.innerHTML = '';
            na_set_thumbnail_preview({});
            return;
        }

        if (message_element) {
            message_element.textContent = 'The preview prefers the saved visible viewport render, so dimensions, watermark, and active style overlays are included after pressing Save Visible View Render.';
        }

        var thumbnail_camera = payload.definition && payload.definition.thumbnail_camera ? payload.definition.thumbnail_camera : {};
        var temp_data = na_export_paths_data(payload.temp || {});

        if (camera_element) camera_element.innerHTML = na_rows(thumbnail_camera, false);
        if (temp_paths_element) temp_paths_element.innerHTML = na_rows(temp_data, true);
        na_set_thumbnail_preview(payload.temp || {});
    };

    window.Na__ComponentEditorTools__ReceiveRenderPreview = function (preview_payload) {
        na_set_thumbnail_preview(preview_payload || {});
        var temp_paths_element = document.getElementById('na-component-thumbnail-temp-paths');
        var current_payload = typeof window.Na__ComponentEditorTools__CurrentPayload === 'function'
            ? window.Na__ComponentEditorTools__CurrentPayload()
            : null;

        if (current_payload && current_payload.temp) {
            current_payload.temp.current_thumbnail_preview_path = preview_payload.current_thumbnail_preview_path || '';
            current_payload.temp.current_thumbnail_preview_source = preview_payload.current_thumbnail_preview_source || '';
            if (temp_paths_element) temp_paths_element.innerHTML = na_rows(na_export_paths_data(current_payload.temp), true);
        }
    };

    window.Na__ComponentEditorTools__ThumbnailTab = Na__ComponentEditorTools__ThumbnailTab;

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
