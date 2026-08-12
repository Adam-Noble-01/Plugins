// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB | EXPORT
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__Tab__Export__.js
// PURPOSE    : Render the Export tab - 2D and 3D preview viewports for the
//              multi-view asset JSON exporter, plus generate/export actions
// CREATED    : 05-Aug-2026
//
// DESCRIPTION:
// - The user selects a component (Monitor Selection capture flow), presses
//   Generate Preview, and the Ruby side returns the full asset document.
// - The four viewports (Front / Right / Top / Isometric) are rendered from
//   that document, so the preview is exactly the data that will export.
// - Export JSON File is enabled only while a generated preview is held.
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__ExportTab = {};
    var na_events_bound   = false;
    var na_active_preview = null;

    var NA_VIEWPORTS_2D = [
        { view_key: 'Na__Asset__Elevation2D__Front', svg_id: 'na-export-viewport-front', caption_id: 'na-export-viewport-front-caption' },
        { view_key: 'Na__Asset__Elevation2D__Right', svg_id: 'na-export-viewport-right', caption_id: 'na-export-viewport-right-caption' },
        { view_key: 'Na__Asset__Plan2D__Top',        svg_id: 'na-export-viewport-top',   caption_id: 'na-export-viewport-top-caption' }
    ];

    var NA_ISO_SOFT_EDGE_LIMIT = 30000;

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

    function na_meta_row(key_name, value_text, mono_value) {
        var value_class = mono_value ? 'naComponentEditor__MetaValue naComponentEditor__Mono' : 'naComponentEditor__MetaValue';
        return (
            '<div class="naComponentEditor__MetaRow">' +
                '<div class="naComponentEditor__MetaKey">' + na_escape_html(key_name) + '</div>' +
                '<div class="' + value_class + '">' + na_escape_html(value_text) + '</div>' +
            '</div>'
        );
    }

    function na_round(value) {
        return Math.round(value * 1000) / 1000;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | 2D Viewport Renderer
// -----------------------------------------------------------------------------
// Draws a view block's Na__Geometry__Paths into an SVG element. World Y is up,
// SVG Y is down, so every Y is negated on the way in.

    function na_render_2d_viewport(svg_element, view_block) {
        if (!svg_element) return;

        if (!view_block || !view_block['Na__Geometry__Paths'] || !view_block['Na__Geometry__Paths'].length) {
            svg_element.innerHTML = '';
            svg_element.removeAttribute('viewBox');
            return;
        }

        var paths = view_block['Na__Geometry__Paths'];
        var bbox  = view_block['Na__Geometry__BoundingBox'] || {};

        var min_x = bbox['Na__Geometry__MinX_mm'];
        var max_x = bbox['Na__Geometry__MaxX_mm'];
        var min_y = bbox['Na__Geometry__MinY_mm'];
        var max_y = bbox['Na__Geometry__MaxY_mm'];

        if (typeof min_x !== 'number' || typeof max_x !== 'number' ||
            typeof min_y !== 'number' || typeof max_y !== 'number') {
            svg_element.innerHTML = '';
            return;
        }

        var width  = Math.max(max_x - min_x, 1);
        var height = Math.max(max_y - min_y, 1);
        var margin = Math.max(width, height) * 0.06;

        var fragments = [];

        // Origin crosshair (local 0,0)
        var cross = Math.max(width, height) * 0.03;
        fragments.push(
            '<line class="naComponentEditor__ExportSvgOrigin" x1="' + (-cross) + '" y1="0" x2="' + cross + '" y2="0"></line>' +
            '<line class="naComponentEditor__ExportSvgOrigin" x1="0" y1="' + (-cross) + '" x2="0" y2="' + cross + '"></line>'
        );

        paths.forEach(function (path_entry) {
            var path_type = path_entry['PathType'];

            if (path_type === 'Line') {
                var line_start = path_entry['Start_mm'];
                var line_end   = path_entry['End_mm'];
                if (!line_start || !line_end) return;
                fragments.push(
                    '<line class="naComponentEditor__ExportSvgStroke" x1="' + na_round(line_start['X']) + '" y1="' + na_round(-line_start['Y']) +
                    '" x2="' + na_round(line_end['X']) + '" y2="' + na_round(-line_end['Y']) + '"></line>'
                );
                return;
            }

            if (path_type === 'Circle') {
                var circle_center = path_entry['Center_mm'];
                if (!circle_center) return;
                fragments.push(
                    '<circle class="naComponentEditor__ExportSvgStroke" cx="' + na_round(circle_center['X']) + '" cy="' + na_round(-circle_center['Y']) +
                    '" r="' + na_round(path_entry['Radius_mm']) + '"></circle>'
                );
                return;
            }

            if (path_type === 'Arc') {
                var arc_center = path_entry['Center_mm'];
                var arc_start  = path_entry['StartPoint_mm'];
                var arc_end    = path_entry['EndPoint_mm'];
                var radius     = path_entry['Radius_mm'];
                var sweep_deg  = Math.abs(path_entry['Sweep_deg'] || 0);
                if (!arc_center || !arc_start || !arc_end) return;

                var large_arc = sweep_deg > 180 ? 1 : 0;
                // Path data sweeps CCW in world coordinates (y up). After the
                // y negation the same travel runs in SVG's negative-angle
                // direction, so sweep-flag must be 0.
                fragments.push(
                    '<path class="naComponentEditor__ExportSvgStroke" d="M ' +
                    na_round(arc_start['X']) + ' ' + na_round(-arc_start['Y']) +
                    ' A ' + na_round(radius) + ' ' + na_round(radius) + ' 0 ' + large_arc + ' 0 ' +
                    na_round(arc_end['X']) + ' ' + na_round(-arc_end['Y']) + '"></path>'
                );
                return;
            }

            if (path_type === 'Polygon') {
                var vertices = path_entry['Vertices_mm'];
                if (!vertices || !vertices.length) return;
                var points_attr = vertices.map(function (vertex) {
                    return na_round(vertex['X']) + ',' + na_round(-vertex['Y']);
                }).join(' ');
                fragments.push('<polygon class="naComponentEditor__ExportSvgStroke" points="' + points_attr + '"></polygon>');
            }
        });

        svg_element.setAttribute('viewBox',
            (min_x - margin) + ' ' + (-max_y - margin) + ' ' + (width + margin * 2) + ' ' + (height + margin * 2));
        svg_element.setAttribute('preserveAspectRatio', 'xMidYMid meet');
        svg_element.innerHTML = fragments.join('');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | 3D Isometric Viewport Renderer
// -----------------------------------------------------------------------------
// Projects Mesh3D vertices with a fixed isometric basis and draws the edge
// list. Hard edges draw solid; soft/smooth edges draw light (skipped entirely
// on very heavy meshes to keep the dialog responsive).
//
// Schema 1.2.0 edges carry Na__Edge__IsDisplayed - the resolved "does SketchUp
// draw this line" answer (not soft, not hidden, tag visible). The preview
// honours it so what you see here matches the SketchUp viewport, and paints
// each line with its authored Na__Edge__ColorHex when one was applied. Edges
// suppressed only by hiding are still drawn faintly so an author can confirm
// the hidden state was captured rather than silently lost.

    function na_iso_project(x, y, z) {
        return {
            u: (x - y) * 0.8660254,
            v: z - (x + y) * 0.5
        };
    }

    function na_render_iso_viewport(svg_element, mesh_block) {
        if (!svg_element) return;

        if (!mesh_block || !mesh_block['Na__Geometry__Vertices'] || !mesh_block['Na__Geometry__Vertices'].length) {
            svg_element.innerHTML = '';
            svg_element.removeAttribute('viewBox');
            return;
        }

        var vertices = mesh_block['Na__Geometry__Vertices'];
        var edges    = mesh_block['Na__Geometry__Edges'] || [];

        var projected = {};
        var min_u = Infinity, max_u = -Infinity, min_v = Infinity, max_v = -Infinity;

        vertices.forEach(function (vertex) {
            var point = na_iso_project(vertex['PosX_mm'], vertex['PosY_mm'], vertex['PosZ_mm']);
            projected[vertex['VertexId']] = point;
            if (point.u < min_u) min_u = point.u;
            if (point.u > max_u) max_u = point.u;
            if (point.v < min_v) min_v = point.v;
            if (point.v > max_v) max_v = point.v;
        });

        if (min_u === Infinity) {
            svg_element.innerHTML = '';
            return;
        }

        var width  = Math.max(max_u - min_u, 1);
        var height = Math.max(max_v - min_v, 1);
        var margin = Math.max(width, height) * 0.06;

        var draw_soft = edges.length <= NA_ISO_SOFT_EDGE_LIMIT;
        var fragments = [];

        edges.forEach(function (edge_entry) {
            var start_point = projected[edge_entry['StartVertex']];
            var end_point   = projected[edge_entry['EndVertex']];
            if (!start_point || !end_point) return;

            var is_soft = edge_entry['Na__Edge__IsSoft'] || edge_entry['IsSoft'] ||
                          edge_entry['Na__Edge__IsSmooth'] || edge_entry['IsSmooth'];
            if (is_soft && !draw_soft) return;

            // Fall back to the legacy soft/smooth test on pre-1.2.0 documents
            // that have no resolved display flag.
            var is_displayed = (typeof edge_entry['Na__Edge__IsDisplayed'] === 'boolean')
                ? edge_entry['Na__Edge__IsDisplayed']
                : !is_soft;

            var stroke_class = is_displayed
                ? 'naComponentEditor__ExportSvgStroke'
                : 'naComponentEditor__ExportSvgStrokeSoft';

            var colour_attr = '';
            if (edge_entry['Na__Edge__HasOwnMaterial'] && edge_entry['Na__Edge__ColorHex']) {
                colour_attr = ' stroke="' + edge_entry['Na__Edge__ColorHex'] + '"';
            }

            var dash_attr = edge_entry['Na__Edge__IsHidden'] ? ' stroke-dasharray="4 3"' : '';

            fragments.push(
                '<line class="' + stroke_class + '"' + colour_attr + dash_attr +
                ' x1="' + na_round(start_point.u) + '" y1="' + na_round(-start_point.v) +
                '" x2="' + na_round(end_point.u) + '" y2="' + na_round(-end_point.v) + '"></line>'
            );
        });

        svg_element.setAttribute('viewBox',
            (min_u - margin) + ' ' + (-max_v - margin) + ' ' + (width + margin * 2) + ' ' + (height + margin * 2));
        svg_element.setAttribute('preserveAspectRatio', 'xMidYMid meet');
        svg_element.innerHTML = fragments.join('');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Summary, Warnings and Captions
// -----------------------------------------------------------------------------

    function na_render_summary(preview_payload) {
        var summary_element = document.getElementById('na-export-summary');
        if (!summary_element) return;

        if (!preview_payload) {
            summary_element.innerHTML = '<p class="naComponentEditor__MutedText">Generate a preview to see export data.</p>';
            return;
        }

        var rows = [];
        rows.push(na_meta_row('Component',    preview_payload.component_name || '', false));
        rows.push(na_meta_row('Product Code', preview_payload.product_code || '(none)', true));
        rows.push(na_meta_row('Output File',  preview_payload.file_name || '', true));

        (preview_payload.stats || []).forEach(function (stat_entry) {
            if (!stat_entry) return;
            if (stat_entry.label === '3D Mesh') {
                rows.push(na_meta_row(
                    stat_entry.label,
                    stat_entry.vertices + ' vertices, ' + stat_entry.faces + ' faces, ' + stat_entry.edges + ' edges, ' + stat_entry.objects + ' objects',
                    false
                ));
                if (typeof stat_entry.displayed === 'number') {
                    rows.push(na_meta_row(
                        'Edge Styles',
                        stat_entry.hard + ' hard, ' + stat_entry.soft + ' soft, ' + stat_entry.smooth + ' smooth, ' +
                        stat_entry.hidden + ' hidden, ' + stat_entry.coloured + ' coloured (' + stat_entry.displayed + ' drawn)',
                        false
                    ));
                }
            } else {
                rows.push(na_meta_row(
                    stat_entry.label,
                    stat_entry.lines + ' lines, ' + stat_entry.arcs + ' arcs (' + stat_entry.circles + ' circles), ' +
                    stat_entry.width + ' x ' + stat_entry.height + ' mm',
                    false
                ));
            }
        });

        summary_element.innerHTML = rows.join('');
    }

    function na_render_warnings(warning_list) {
        var warnings_element = document.getElementById('na-export-warnings');
        if (!warnings_element) return;

        if (!warning_list || !warning_list.length) {
            warnings_element.innerHTML = '<p class="naComponentEditor__MutedText">No warnings.</p>';
            return;
        }

        warnings_element.innerHTML = warning_list.map(function (warning_text) {
            return '<div class="naComponentEditor__ExportWarningItem">' + na_escape_html(warning_text) + '</div>';
        }).join('');
    }

    function na_set_caption(caption_id, caption_text) {
        var caption_element = document.getElementById(caption_id);
        if (caption_element) caption_element.textContent = caption_text || '';
    }

    function na_clear_viewports() {
        NA_VIEWPORTS_2D.forEach(function (viewport_def) {
            var svg_element = document.getElementById(viewport_def.svg_id);
            if (svg_element) {
                svg_element.innerHTML = '';
                svg_element.removeAttribute('viewBox');
            }
            na_set_caption(viewport_def.caption_id, '');
        });

        var iso_element = document.getElementById('na-export-viewport-iso');
        if (iso_element) {
            iso_element.innerHTML = '';
            iso_element.removeAttribute('viewBox');
        }
        na_set_caption('na-export-viewport-iso-caption', '');
    }

    function na_set_export_enabled(enabled_flag) {
        var export_button = document.getElementById('na-export-btn-write');
        if (export_button) export_button.disabled = !enabled_flag;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Event Binding
// -----------------------------------------------------------------------------

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        var generate_button = document.getElementById('na-export-btn-generate');
        if (generate_button) {
            generate_button.addEventListener('click', function () {
                window.Na__ComponentEditorTools__ExportGeneratePreview();
            });
        }

        var export_button = document.getElementById('na-export-btn-write');
        if (export_button) {
            export_button.addEventListener('click', function () {
                window.Na__ComponentEditorTools__ExportWriteJson();
            });
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    // FUNCTION | Selection payload render - resets stale previews
    // ------------------------------------------------------------
    Na__ComponentEditorTools__ExportTab.Na__ComponentEditorTools__Render = function (payload) {
        na_bind_events_once();

        var message_element = document.getElementById('na-export-message');

        if (!payload || payload.ok !== true) {
            if (message_element) message_element.textContent = payload && payload.message ? payload.message : 'No component selected.';
            na_active_preview = null;
            na_set_export_enabled(false);
            na_clear_viewports();
            na_render_summary(null);
            na_render_warnings(null);
            return;
        }

        // A fresh selection payload invalidates any previously generated
        // preview - the component may have changed since it was built.
        na_active_preview = null;
        na_set_export_enabled(false);
        na_clear_viewports();
        na_render_summary(null);
        na_render_warnings(null);

        if (message_element) {
            var component_label = payload.instance && payload.instance.definition_name
                ? payload.instance.definition_name
                : 'the selected component';
            message_element.textContent = 'Press Generate Preview to build all 2D views and 3D data for ' + component_label + ', then export the unified JSON.';
        }
    };

    // FUNCTION | Receive a generated preview from Ruby
    // ------------------------------------------------------------
    Na__ComponentEditorTools__ExportTab.Na__ComponentEditorTools__ReceivePreview = function (preview_payload) {
        na_bind_events_once();

        if (!preview_payload || preview_payload.success !== true || !preview_payload.preview_document) {
            na_active_preview = null;
            na_set_export_enabled(false);
            na_render_warnings(preview_payload ? preview_payload.warnings : null);
            return;
        }

        na_active_preview = preview_payload;
        var document_data = preview_payload.preview_document;

        NA_VIEWPORTS_2D.forEach(function (viewport_def) {
            var svg_element = document.getElementById(viewport_def.svg_id);
            var view_block  = document_data[viewport_def.view_key];
            na_render_2d_viewport(svg_element, view_block);

            if (view_block && view_block['Na__Geometry__Counts']) {
                var counts = view_block['Na__Geometry__Counts'];
                na_set_caption(viewport_def.caption_id,
                    counts['Na__Geometry__LineCount'] + ' lines | ' +
                    counts['Na__Geometry__ArcCount'] + ' arcs | ' +
                    counts['Na__Geometry__CircleCount'] + ' circles');
            } else {
                na_set_caption(viewport_def.caption_id, 'No linework captured');
            }
        });

        var iso_element = document.getElementById('na-export-viewport-iso');
        var mesh_block  = document_data['Na__Asset__Mesh3D'];
        na_render_iso_viewport(iso_element, mesh_block);

        if (mesh_block && mesh_block['Na__Geometry__Counts']) {
            var mesh_counts = mesh_block['Na__Geometry__Counts'];
            na_set_caption('na-export-viewport-iso-caption',
                mesh_counts['Na__Geometry__VertexCount'] + ' vertices | ' +
                mesh_counts['Na__Geometry__FaceCount'] + ' faces | ' +
                mesh_counts['Na__Geometry__EdgeCount'] + ' edges');
        } else {
            na_set_caption('na-export-viewport-iso-caption', 'No 3D mesh captured');
        }

        na_render_summary(preview_payload);
        na_render_warnings(preview_payload.warnings);
        na_set_export_enabled(true);

        var message_element = document.getElementById('na-export-message');
        if (message_element) {
            message_element.textContent = 'Preview generated. Check the viewports, then press Export JSON File to save ' + (preview_payload.file_name || 'the asset file') + '.';
        }
    };

    // FUNCTION | Receive the export write result from Ruby
    // ------------------------------------------------------------
    Na__ComponentEditorTools__ExportTab.Na__ComponentEditorTools__ReceiveExportResult = function (result_payload) {
        var message_element = document.getElementById('na-export-message');
        if (!message_element) return;

        if (result_payload.success === true) {
            message_element.textContent = 'Exported to: ' + (result_payload.path || 'file saved.');
        } else {
            message_element.textContent = result_payload.message || 'Export failed.';
        }
    };

    window.Na__ComponentEditorTools__ExportTab = Na__ComponentEditorTools__ExportTab;

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
