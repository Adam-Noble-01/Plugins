// =============================================================================
// NA COMPONENT EDITOR TOOLS - GEOMETRY CLIPBOARD
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__GeometryClipboard__.js
// PURPOSE    : Format and copy component geometry stats as plain-text columns
//              to the system clipboard.
//
// FORMAT EXAMPLE:
//   ### Edge Stats
//   Edges        =  29436
//   Soft         =  28162
//   Smooth       =  28162
//   Hidden       =  0
//   Non-manifold =  0
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Text Formatting Helpers
// -----------------------------------------------------------------------------

    var NA_COL_WIDTH = 20;   // characters reserved for the key column
    var NA_SEPARATOR = '  =  ';

    function na_pad_key(key_string) {
        var s = String(key_string);
        while (s.length < NA_COL_WIDTH) { s += ' '; }
        return s;
    }

    function na_format_section(heading, rows) {
        var lines = ['### ' + heading];
        rows.forEach(function (row) {
            lines.push(na_pad_key(row[0]) + NA_SEPARATOR + String(row[1]));
        });
        return lines.join('\n');
    }

    function na_list_to_text(items) {
        if (!items || items.length === 0) return 'None';
        if (typeof items[0] === 'object' && items[0] !== null) {
            return items.map(function (m) {
                var label = m.name || '(unnamed)';
                return m.textured ? label + ' [texture: ' + (m.texture_file || '?') + ']' : label;
            }).join(', ');
        }
        return items.join(', ');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Stats Serialiser
// -----------------------------------------------------------------------------

    function na_build_plain_text(geometry, component_name) {
        if (!geometry) return '(No geometry data captured yet.)';

        var header = component_name
            ? ('Component: ' + component_name + '\n' + new Array(component_name.length + 12).join('-'))
            : 'Component Geometry Stats';

        var sections = [
            header,
            '',
            na_format_section('Polygon Stats', [
                ['Faces',           geometry.faces],
                ['Triangles',       geometry.triangles],
                ['Quads',           geometry.quads],
                ['Total Face Area', geometry.total_face_area],
                ['Solid?',          geometry.is_solid ? 'Yes' : 'No']
            ]),
            '',
            na_format_section('Edge Stats', [
                ['Edges',           geometry.edges],
                ['Soft',            geometry.soft_edges],
                ['Smooth',          geometry.smooth_edges],
                ['Hidden',          geometry.hidden_edges],
                ['Non-manifold',    geometry.non_manifold_edges]
            ]),
            '',
            na_format_section('Nested Entities', [
                ['Groups',          geometry.nested_groups],
                ['Components',      geometry.nested_components],
                ['Unique Defs',     geometry.unique_definitions]
            ]),
            '',
            na_format_section('Misc & Topology', [
                ['Constr. Lines',   geometry.construction_lines],
                ['Constr. Points',  geometry.construction_points],
                ['Texts',           geometry.texts],
                ['Dimensions',      geometry.dimensions],
                ['Images',          geometry.images],
                ['Section Planes',  geometry.section_planes],
                ['Attr. Dicts',     geometry.attribute_dicts],
                ['Attr. Keys',      geometry.attribute_keys]
            ]),
            '',
            na_format_section('Face Materials', [
                ['Materials', na_list_to_text(geometry.face_materials)]
            ]),
            '',
            na_format_section('Edge Materials', [
                ['Materials', na_list_to_text(geometry.edge_materials)]
            ]),
            '',
            na_format_section('Tags Used', [
                ['Tags', na_list_to_text(geometry.tags)]
            ])
        ];

        return sections.join('\n');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Clipboard Write
// -----------------------------------------------------------------------------

    function na_write_to_clipboard(text, on_success, on_fail) {
        if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
            navigator.clipboard.writeText(text).then(on_success, on_fail);
        } else {
            // Fallback for older WebViews
            try {
                var textarea = document.createElement('textarea');
                textarea.value = text;
                textarea.style.position = 'fixed';
                textarea.style.top = '-9999px';
                document.body.appendChild(textarea);
                textarea.select();
                var ok = document.execCommand('copy');
                document.body.removeChild(textarea);
                if (ok) { on_success(); } else { on_fail(new Error('execCommand returned false')); }
            } catch (err) {
                on_fail(err);
            }
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    function Na__ComponentEditorTools__CopyGeometryStats() {
        var payload = typeof window.Na__ComponentEditorTools__CurrentPayload === 'function'
            ? window.Na__ComponentEditorTools__CurrentPayload()
            : null;

        var geometry = payload && payload.geometry ? payload.geometry : null;
        var component_name = (payload && payload.definition && payload.definition.name)
            ? payload.definition.name
            : '';

        var plain_text = na_build_plain_text(geometry, component_name);

        var btn = document.getElementById('na-component-btn-copy-stats');

        na_write_to_clipboard(
            plain_text,
            function () {
                if (btn) {
                    var original = btn.innerHTML;
                    btn.innerHTML = '&#10003; Copied!';
                    btn.classList.add('naComponentEditor__GeomCopyBtn--success');
                    setTimeout(function () {
                        btn.innerHTML = original;
                        btn.classList.remove('naComponentEditor__GeomCopyBtn--success');
                    }, 1800);
                }
            },
            function (err) {
                console.error('[Na__ComponentEditorTools] Clipboard write failed:', err);
                if (btn) {
                    var original_on_fail = btn.innerHTML;
                    btn.innerHTML = '&#10007; Failed';
                    btn.classList.add('naComponentEditor__GeomCopyBtn--fail');
                    setTimeout(function () {
                        btn.innerHTML = original_on_fail;
                        btn.classList.remove('naComponentEditor__GeomCopyBtn--fail');
                    }, 1800);
                }
            }
        );
    }

    window.Na__ComponentEditorTools__CopyGeometryStats = Na__ComponentEditorTools__CopyGeometryStats;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Init — bind copy button
// -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        var copy_btn = document.getElementById('na-component-btn-copy-stats');
        if (copy_btn) {
            copy_btn.addEventListener('click', Na__ComponentEditorTools__CopyGeometryStats);
        }
    });

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
