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

    function na_round_mm_string(str) {
        var num = parseFloat(String(str).replace(/[^0-9.\-]/g, ''));
        return isNaN(num) ? str : Math.round(num) + ' mm';
    }

    function na_format_point_mm(arr) {
        if (!Array.isArray(arr)) return String(arr);
        return arr.map(function (coord) {
            var num = parseFloat(String(coord).replace(/[^0-9.\-]/g, ''));
            return isNaN(num) ? coord : String(Math.round(num));
        }).join(', ');
    }

    function na_expand_bounds_into_hash(bounds_obj, target_hash) {
        delete target_hash.bounds;
        target_hash.width_x  = na_round_mm_string(bounds_obj.width_x);
        target_hash.depth_y  = na_round_mm_string(bounds_obj.depth_y);
        target_hash.height_z = na_round_mm_string(bounds_obj.height_z);
        target_hash.min      = na_format_point_mm(bounds_obj.min);
        target_hash.max      = na_format_point_mm(bounds_obj.max);
        target_hash.center   = na_format_point_mm(bounds_obj.center);
    }

    function na_format_load_time(time_str) {
        var months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        var parts = String(time_str).split(' ');
        var date_parts = parts[0] ? parts[0].split('-') : [];
        if (date_parts.length < 3) return time_str;
        var year  = date_parts[0];
        var month = months[parseInt(date_parts[1], 10) - 1] || date_parts[1];
        var day   = date_parts[2].replace(/^0/, '');
        var time  = parts[1] ? parts[1].substring(0, 5) : '';
        return day + '-' + month + '-' + year + '  -  ' + time;
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

    function na_geom_stat_row(label, value) {
        return (
            '<div class="naComponentEditor__MetaRow">' +
                '<div class="naComponentEditor__MetaKey">' + na_escape_html(label) + '</div>' +
                '<div class="naComponentEditor__MetaValue naComponentEditor__MetaValue--stat">' + na_escape_html(String(value !== null && value !== undefined ? value : '')) + '</div>' +
            '</div>'
        );
    }

    function na_material_chip(mat) {
        if (!mat || typeof mat !== 'object') return '';
        var label  = mat.name || '(unnamed)';
        var suffix = mat.textured ? (' \u2014 ' + (mat.texture_file || 'texture')) : '';
        var icon   = mat.textured ? '\uD83D\uDDBC ' : '';
        return '<span class="naComponentEditor__GeomChip">' + na_escape_html(icon + label + suffix) + '</span>';
    }

    function na_tag_chip(tag_name) {
        return '<span class="naComponentEditor__GeomTagChip">' + na_escape_html(tag_name) + '</span>';
    }

    function na_render_material_list(container_element, materials) {
        if (!container_element) return;
        if (!materials || materials.length === 0) {
            container_element.innerHTML = '<span class="naComponentEditor__MutedText">None</span>';
            return;
        }
        container_element.innerHTML = materials.map(na_material_chip).join('');
    }

    function na_render_tag_list(container_element, tags) {
        if (!container_element) return;
        if (!tags || tags.length === 0) {
            container_element.innerHTML = '<span class="naComponentEditor__MutedText">None</span>';
            return;
        }
        container_element.innerHTML = tags.map(na_tag_chip).join('');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Geometry Panel
// -----------------------------------------------------------------------------

    function na_render_geometry_panel(geometry) {
        var counts_el   = document.getElementById('na-component-geometry-counts');
        var edges_el    = document.getElementById('na-component-geometry-edges');
        var nested_el   = document.getElementById('na-component-geometry-nested');
        var misc_el     = document.getElementById('na-component-geometry-misc');
        var face_mat_el = document.getElementById('na-component-geometry-face-materials');
        var edge_mat_el = document.getElementById('na-component-geometry-edge-materials');
        var tags_el     = document.getElementById('na-component-geometry-tags');

        if (!geometry) {
            var empty = '<p class="naComponentEditor__MutedText">Enable Monitor Selection to load geometry data.</p>';
            if (counts_el)   counts_el.innerHTML   = empty;
            if (edges_el)    edges_el.innerHTML     = '';
            if (nested_el)   nested_el.innerHTML    = '';
            if (misc_el)     misc_el.innerHTML      = '';
            if (face_mat_el) face_mat_el.innerHTML  = '';
            if (edge_mat_el) edge_mat_el.innerHTML  = '';
            if (tags_el)     tags_el.innerHTML      = '';
            return;
        }

        if (counts_el) {
            counts_el.innerHTML =
                na_geom_stat_row('File Size',       geometry.file_size || '') +
                na_geom_stat_row('Faces',           geometry.faces) +
                na_geom_stat_row('Triangles',       geometry.triangles) +
                na_geom_stat_row('Quads',           geometry.quads) +
                na_geom_stat_row('Total Face Area', geometry.total_face_area) +
                na_geom_stat_row('Solid?',          geometry.is_solid ? 'Yes' : 'No');
        }

        if (edges_el) {
            edges_el.innerHTML =
                na_geom_stat_row('Edges',               geometry.edges) +
                na_geom_stat_row('Soft Edges',          geometry.soft_edges) +
                na_geom_stat_row('Smooth Edges',        geometry.smooth_edges) +
                na_geom_stat_row('Hidden Edges',        geometry.hidden_edges) +
                na_geom_stat_row('Non-manifold Edges',  geometry.non_manifold_edges);
        }

        if (nested_el) {
            nested_el.innerHTML =
                na_geom_stat_row('Nested Groups',      geometry.nested_groups) +
                na_geom_stat_row('Nested Components',  geometry.nested_components) +
                na_geom_stat_row('Unique Definitions', geometry.unique_definitions);
        }

        if (misc_el) {
            misc_el.innerHTML =
                na_geom_stat_row('Construction Lines',  geometry.construction_lines) +
                na_geom_stat_row('Construction Points', geometry.construction_points) +
                na_geom_stat_row('Texts',               geometry.texts) +
                na_geom_stat_row('Dimensions',          geometry.dimensions) +
                na_geom_stat_row('Images',              geometry.images) +
                na_geom_stat_row('Section Planes',      geometry.section_planes) +
                na_geom_stat_row('Attribute Dicts',     geometry.attribute_dicts) +
                na_geom_stat_row('Attribute Keys',      geometry.attribute_keys);
        }

        na_render_material_list(face_mat_el, geometry.face_materials);
        na_render_material_list(edge_mat_el, geometry.edge_materials);
        na_render_tag_list(tags_el, geometry.tags);
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

            na_render_geometry_panel(null);
            return;
        }

        if (message_element) {
            message_element.textContent = payload.message + ' Selected items: ' + payload.selected_count;
        }

        var instance_hash = Object.assign({}, payload.instance || {});
        var definition_hash = Object.assign({}, payload.definition || {});
        var behavior_hash = Object.assign({}, payload.behavior || {});

        if (instance_hash.bounds) na_expand_bounds_into_hash(instance_hash.bounds, instance_hash);
        if (instance_hash.transformation) instance_hash.transformation = na_to_text(instance_hash.transformation);
        if (definition_hash.thumbnail_camera) definition_hash.thumbnail_camera = '[See Thumbnail tab]';
        if (definition_hash.load_time) definition_hash.load_time = na_format_load_time(definition_hash.load_time);

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

        na_render_geometry_panel(payload.geometry || null);
    };

    window.Na__ComponentEditorTools__OverviewTab = Na__ComponentEditorTools__OverviewTab;

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
