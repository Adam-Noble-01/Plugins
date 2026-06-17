// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB | INDEX
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__Tab__Index__.js
// PURPOSE    : Index tab - sortable/filterable table with inline Code and
//              Gallery Name editing (writes to component DC dictionary via
//              UpdateLibraryData), drill-down edit panel for Notes and custom
//              fields, and Definition Name / Description editing via disk save.
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__IndexTab = {};
    var na_events_bound  = false;
    var na_all_entries   = [];
    var na_sort_key      = 'code';
    var na_sort_asc      = true;
    var na_expanded_rows = {};
    var na_editing_active = false;
    var na_taxonomy = { categories: [] };

    // Editable data columns, in table order. Each maps a header to the entry
    // field and how its inline editor renders. Saving routes through Ruby's
    // single-field updater which writes back to the .skp (or moves/renames the
    // file) then re-extracts that component.
    var NA_EDITABLE_COLUMNS = [
        { field: 'code',         td_class: ' naComponentEditor__IndexTd--inline', input_class: ' naComponentEditor__IndexCellInput--code', placeholder: 'code',                 multiline: false },
        { field: 'gallery_name', td_class: ' naComponentEditor__IndexTd--inline', input_class: '',                                          placeholder: 'Gallery display name\u2026', multiline: false },
        { field: 'def_name',     td_class: '',                                    input_class: '',                                          placeholder: 'Definition name',       multiline: false },
        { field: 'file_name',    td_class: ' naComponentEditor__IndexTd--mono',   input_class: ' naComponentEditor__IndexCellInput--mono',  placeholder: 'file.skp',              multiline: false },
        { field: 'relative_dir', td_class: ' naComponentEditor__IndexTd--mono',   input_class: ' naComponentEditor__IndexCellInput--mono',  placeholder: '(root)',                multiline: false },
        { field: 'description',  td_class: ' naComponentEditor__IndexTd--desc',   input_class: '',                                          placeholder: 'Description\u2026',     multiline: true  }
    ];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Helpers
// -----------------------------------------------------------------------------

    function na_tbody() {
        return document.getElementById('na-index-tbody');
    }

    function na_filter_input() {
        return document.getElementById('na-index-filter');
    }

    function na_index_folder_filter() {
        return document.getElementById('na-index-folder-filter');
    }

    function na_index_category_filter() {
        return document.getElementById('na-index-category-filter');
    }

    function na_index_type_filter() {
        return document.getElementById('na-index-type-filter');
    }

    function na_index_message() {
        return document.getElementById('na-index-message');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Taxonomy Helpers
// -----------------------------------------------------------------------------

    function na_index_category_names() {
        return (na_taxonomy && na_taxonomy.categories)
            ? na_taxonomy.categories.map(function (c) { return c.name; })
            : [];
    }

    function na_index_types_for(category_name) {
        if (!na_taxonomy || !na_taxonomy.categories) return [];
        for (var i = 0; i < na_taxonomy.categories.length; i++) {
            if (na_taxonomy.categories[i].name === category_name) {
                return na_taxonomy.categories[i].types || [];
            }
        }
        return [];
    }

    function na_index_all_types() {
        var seen = {};
        var list = [];
        (na_taxonomy.categories || []).forEach(function (c) {
            (c.types || []).forEach(function (t) {
                if (!seen[t]) { seen[t] = true; list.push(t); }
            });
        });
        return list;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Filter Populate Functions
// -----------------------------------------------------------------------------

    function na_populate_index_folder_filter() {
        var filter_el = na_index_folder_filter();
        if (!filter_el) return;

        var current_val = filter_el.value;
        var seen = {};
        var folders = [];
        na_all_entries.forEach(function (entry) {
            var dir = entry.relative_dir || '';
            if (!seen[dir]) { seen[dir] = true; folders.push(dir); }
        });
        folders.sort();

        filter_el.innerHTML = '<option value="">All Folders</option>';
        folders.forEach(function (folder_name) {
            var opt = document.createElement('option');
            opt.value = folder_name;
            opt.textContent = folder_name || '(root)';
            filter_el.appendChild(opt);
        });

        filter_el.value = current_val;
    }

    function na_populate_index_category_filter() {
        var filter_el = na_index_category_filter();
        if (!filter_el) return;

        var current_val = filter_el.value;
        filter_el.innerHTML = '<option value="">All Categories</option>';

        na_index_category_names().forEach(function (name) {
            var opt = document.createElement('option');
            opt.value = name;
            opt.textContent = name;
            filter_el.appendChild(opt);
        });

        filter_el.value = current_val;
    }

    function na_populate_index_type_filter() {
        var filter_el = na_index_type_filter();
        if (!filter_el) return;

        var category_val = (na_index_category_filter() && na_index_category_filter().value) || '';
        var current_val  = filter_el.value;
        var types        = category_val ? na_index_types_for(category_val) : na_index_all_types();

        filter_el.innerHTML = '<option value="">All Types</option>';
        types.forEach(function (type_name) {
            var opt = document.createElement('option');
            opt.value = type_name;
            opt.textContent = type_name;
            filter_el.appendChild(opt);
        });

        filter_el.value = (types.indexOf(current_val) !== -1) ? current_val : '';
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Render
// -----------------------------------------------------------------------------

    function na_render_index(index_payload) {
        if (!index_payload) return;

        na_all_entries = index_payload.entries || [];

        na_populate_index_folder_filter();
        na_populate_index_category_filter();
        na_populate_index_type_filter();

        var msg_el = na_index_message();
        if (msg_el) msg_el.textContent = index_payload.message || '';

        // Never clobber an in-progress cell edit with a full re-render.
        if (na_editing_active) return;

        na_rebuild_table();
        na_update_sort_indicators();
    }

    function na_rebuild_table() {
        var tbody = na_tbody();
        if (!tbody) return;

        var filter_text    = ((na_filter_input()          && na_filter_input().value)          || '').toLowerCase().trim();
        var folder_value   = (na_index_folder_filter()    && na_index_folder_filter().value)   || '';
        var category_value = (na_index_category_filter()  && na_index_category_filter().value) || '';
        var type_value     = (na_index_type_filter()      && na_index_type_filter().value)     || '';

        var visible = na_all_entries.filter(function (entry) {
            var text_match = !filter_text ||
                   (entry.code         || '').toLowerCase().indexOf(filter_text) !== -1 ||
                   (entry.gallery_name || '').toLowerCase().indexOf(filter_text) !== -1 ||
                   (entry.def_name     || '').toLowerCase().indexOf(filter_text) !== -1 ||
                   (entry.file_name    || '').toLowerCase().indexOf(filter_text) !== -1 ||
                   (entry.description  || '').toLowerCase().indexOf(filter_text) !== -1 ||
                   (entry.relative_dir || '').toLowerCase().indexOf(filter_text) !== -1;

            var folder_match   = !folder_value   || (entry.relative_dir || '') === folder_value;
            var category_match = !category_value || (entry.category     || '') === category_value;
            var type_match     = !type_value     || (entry.type         || '') === type_value;

            return text_match && folder_match && category_match && type_match;
        });

        visible.sort(function (a, b) {
            var val_a = String(a[na_sort_key] || '').toLowerCase();
            var val_b = String(b[na_sort_key] || '').toLowerCase();
            if (val_a < val_b) return na_sort_asc ? -1 :  1;
            if (val_a > val_b) return na_sort_asc ?  1 : -1;
            return 0;
        });

        tbody.innerHTML = '';

        visible.forEach(function (entry) {
            var entry_key = entry.path || entry.file_name;
            tbody.appendChild(na_build_main_row(entry, entry_key));

            if (na_expanded_rows[entry_key]) {
                tbody.appendChild(na_build_edit_row(entry, entry_key));
            }
        });
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Main Row
// -----------------------------------------------------------------------------

    function na_column(field) {
        for (var i = 0; i < NA_EDITABLE_COLUMNS.length; i++) {
            if (NA_EDITABLE_COLUMNS[i].field === field) return NA_EDITABLE_COLUMNS[i];
        }
        return { field: field, td_class: '', input_class: '', placeholder: '', multiline: false };
    }

    function na_build_main_row(entry, entry_key) {
        var tr = document.createElement('tr');
        tr.className = 'naComponentEditor__IndexRow';
        tr.setAttribute('data-entry-key', entry_key);

        tr.appendChild(na_build_editable_cell(entry, na_column('code')));
        tr.appendChild(na_build_editable_cell(entry, na_column('gallery_name')));
        tr.appendChild(na_build_category_cell(entry));
        tr.appendChild(na_build_type_cell(entry));
        tr.appendChild(na_build_editable_cell(entry, na_column('def_name')));
        tr.appendChild(na_build_editable_cell(entry, na_column('file_name')));
        tr.appendChild(na_build_editable_cell(entry, na_column('relative_dir')));
        tr.appendChild(na_build_editable_cell(entry, na_column('description')));

        tr.appendChild(na_build_actions_cell(entry, entry_key));
        return tr;
    }

    function na_build_actions_cell(entry, entry_key) {
        var actions_td = document.createElement('td');
        actions_td.className = 'naComponentEditor__IndexTd naComponentEditor__IndexTd--actions';

        var edit_btn = document.createElement('button');
        edit_btn.type = 'button';
        edit_btn.className = 'naComponentEditor__Button naComponentEditor__IndexBtn';
        edit_btn.textContent = na_expanded_rows[entry_key] ? 'Close' : 'Edit';
        edit_btn.addEventListener('click', function () { na_toggle_edit_row(entry_key); });

        var insert_btn = document.createElement('button');
        insert_btn.type = 'button';
        insert_btn.className = 'naComponentEditor__Button naComponentEditor__IndexBtn';
        insert_btn.textContent = 'Insert';
        insert_btn.title = 'Place component in model';
        insert_btn.addEventListener('click', function () {
            if (entry.path && typeof window.Na__ComponentEditorTools__InsertLibraryComponent === 'function') {
                window.Na__ComponentEditorTools__InsertLibraryComponent(entry.path);
            }
        });

        var open_btn = document.createElement('button');
        open_btn.type = 'button';
        open_btn.className = 'naComponentEditor__Button naComponentEditor__IndexBtn';
        open_btn.textContent = 'Open';
        open_btn.title = 'Open component file in a new SketchUp instance';
        open_btn.addEventListener('click', function () {
            if (entry.path && typeof window.Na__ComponentEditorTools__OpenComponentFile === 'function') {
                window.Na__ComponentEditorTools__OpenComponentFile(entry.path);
            }
        });

        actions_td.appendChild(edit_btn);
        actions_td.appendChild(insert_btn);
        actions_td.appendChild(open_btn);
        return actions_td;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Double-Click Editable Cells
// -----------------------------------------------------------------------------

    function na_field_value(entry, field) {
        return (entry && entry[field] != null) ? String(entry[field]) : '';
    }

    function na_build_editable_cell(entry, column) {
        var td = document.createElement('td');
        td.className = 'naComponentEditor__IndexTd naComponentEditor__IndexCell--editable' + (column.td_class || '');
        td.setAttribute('data-field', column.field);

        na_render_cell_display(td, entry, column);

        td.addEventListener('dblclick', function () {
            na_begin_cell_edit(td, entry, column);
        });

        return td;
    }

    function na_render_cell_display(td, entry, column) {
        td.innerHTML = '';
        td.classList.remove('naComponentEditor__IndexCell--editing');

        var value = na_field_value(entry, column.field);

        var span = document.createElement('span');
        span.className = 'naComponentEditor__IndexCellText';

        if (value) {
            span.textContent = value;
            span.title = value;
        } else {
            span.className += ' naComponentEditor__IndexCellText--empty';
            span.textContent = column.placeholder || '\u2014';
        }

        if (column.field === 'code' && !entry.code_stored && entry.code_derived) {
            span.title = 'Auto-derived from definition name. Double-click to type an override.';
        } else if (!value) {
            span.title = 'Double-click to edit';
        }

        td.appendChild(span);
    }

    function na_set_cell_saving(td) {
        td.innerHTML = '';
        var span = document.createElement('span');
        span.className = 'naComponentEditor__IndexCellText naComponentEditor__IndexCellText--saving';
        span.textContent = 'Saving\u2026';
        td.appendChild(span);
    }

    function na_begin_cell_edit(td, entry, column) {
        if (td.classList.contains('naComponentEditor__IndexCell--editing')) return;

        na_editing_active = true;
        td.classList.add('naComponentEditor__IndexCell--editing');
        td.innerHTML = '';

        var initial = na_field_value(entry, column.field);

        var input;
        if (column.multiline) {
            input = document.createElement('textarea');
            input.rows = 2;
        } else {
            input = document.createElement('input');
            input.type = 'text';
        }
        input.className = 'naComponentEditor__IndexCellInput' + (column.input_class || '');
        input.value = initial;
        input.placeholder = column.placeholder || '';

        td.appendChild(input);
        input.focus();
        input.select();

        var settled = false;

        function revert() {
            if (settled) return;
            settled = true;
            na_editing_active = false;
            na_render_cell_display(td, entry, column);
        }

        function commit() {
            if (settled) return;
            settled = true;
            na_editing_active = false;

            var new_value = input.value;
            if (new_value === initial) {
                na_render_cell_display(td, entry, column);
                return;
            }

            na_set_cell_saving(td);
            na_save_field(entry, column.field, new_value);
        }

        input.addEventListener('keydown', function (evt) {
            var commit_key = (evt.key === 'Enter') && !(column.multiline && evt.shiftKey);
            if (commit_key) {
                evt.preventDefault();
                commit();
            } else if (evt.key === 'Escape') {
                evt.preventDefault();
                revert();
            }
        });

        input.addEventListener('blur', function () {
            revert();
        });
    }

    function na_save_field(entry, field, new_value) {
        if (!entry.path) return;
        if (typeof window.Na__ComponentEditorTools__UpdateField !== 'function') return;

        window.Na__ComponentEditorTools__UpdateField({
            path:  entry.path,
            field: field,
            value: new_value
        });
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Category & Type Dropdown Cells
// -----------------------------------------------------------------------------

    function na_category_names() {
        return (na_taxonomy && na_taxonomy.categories)
            ? na_taxonomy.categories.map(function (c) { return c.name; })
            : [];
    }

    function na_types_for(category_name) {
        if (!na_taxonomy || !na_taxonomy.categories) return [];
        for (var i = 0; i < na_taxonomy.categories.length; i++) {
            if (na_taxonomy.categories[i].name === category_name) {
                return na_taxonomy.categories[i].types || [];
            }
        }
        return [];
    }

    function na_fill_select_options(select, options, current_value) {
        select.innerHTML = '';

        var blank = document.createElement('option');
        blank.value = '';
        blank.textContent = '\u2014';
        select.appendChild(blank);

        var found = false;
        options.forEach(function (value) {
            var opt = document.createElement('option');
            opt.value = value;
            opt.textContent = value;
            if (value === current_value) { opt.selected = true; found = true; }
            select.appendChild(opt);
        });

        if (current_value && !found) {
            var stray = document.createElement('option');
            stray.value = current_value;
            stray.textContent = current_value + ' (?)';
            stray.selected = true;
            select.appendChild(stray);
        }
    }

    function na_build_category_cell(entry) {
        var td = document.createElement('td');
        td.className = 'naComponentEditor__IndexTd naComponentEditor__IndexTd--select';

        var select = document.createElement('select');
        select.className = 'naComponentEditor__IndexSelect';
        na_fill_select_options(select, na_category_names(), entry.category || '');

        select.addEventListener('change', function () {
            var new_category = select.value;
            var existing_type = entry.type || '';
            var clears_type = existing_type && na_types_for(new_category).indexOf(existing_type) === -1;

            entry.category = new_category;
            if (clears_type) entry.type = '';

            na_save_field(entry, 'category', new_category);
            if (clears_type) na_save_field(entry, 'type', '');
        });

        td.appendChild(select);
        return td;
    }

    function na_build_type_cell(entry) {
        var td = document.createElement('td');
        td.className = 'naComponentEditor__IndexTd naComponentEditor__IndexTd--select';

        var select = document.createElement('select');
        select.className = 'naComponentEditor__IndexSelect';
        na_fill_select_options(select, na_types_for(entry.category || ''), entry.type || '');

        if (!(entry.category || '')) {
            select.disabled = true;
            select.title = 'Choose a category first';
        }

        select.addEventListener('change', function () {
            entry.type = select.value;
            na_save_field(entry, 'type', select.value);
        });

        td.appendChild(select);
        return td;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Edit Row (drill-down panel)
// -----------------------------------------------------------------------------

    function na_build_edit_row(entry, entry_key) {
        var tr = document.createElement('tr');
        tr.className = 'naComponentEditor__IndexEditRow';
        tr.setAttribute('data-edit-key', entry_key);

        var td = document.createElement('td');
        td.colSpan = 9;
        td.className = 'naComponentEditor__IndexEditTd';
        td.appendChild(na_build_edit_panel(entry));
        tr.appendChild(td);
        return tr;
    }

    function na_build_edit_panel(entry) {
        var panel = document.createElement('div');
        panel.className = 'naComponentEditor__IndexEditPanel';

        var heading = document.createElement('h3');
        heading.className = 'naComponentEditor__IndexEditHeading';
        heading.textContent = 'Edit: ' + (entry.file_name || '');
        panel.appendChild(heading);

        var grid = document.createElement('div');
        grid.className = 'naComponentEditor__Grid2';

        var safe_id = na_safe_id(entry_key_of(entry));

        grid.appendChild(na_build_labelled_input(
            'Definition Name (saved to .skp)',
            'na-idx-defname-' + safe_id,
            entry.def_name || ''
        ));
        grid.appendChild(na_build_labelled_input(
            'Notes (Na__ComponentLibrary dict)',
            'na-idx-notes-' + safe_id,
            entry.notes || ''
        ));
        panel.appendChild(grid);

        var desc_label = document.createElement('label');
        desc_label.className = 'naComponentEditor__Label';
        var desc_span = document.createElement('span');
        desc_span.textContent = 'Description (saved to .skp)';
        var desc_input = document.createElement('input');
        desc_input.type = 'text';
        desc_input.id = 'na-idx-desc-' + safe_id;
        desc_input.className = 'naComponentEditor__Input';
        desc_input.value = entry.description || '';
        desc_label.appendChild(desc_span);
        desc_label.appendChild(desc_input);
        panel.appendChild(desc_label);

        var rename_row = document.createElement('div');
        rename_row.className = 'naComponentEditor__IndexRenameRow';
        var rename_chk = document.createElement('input');
        rename_chk.type = 'checkbox';
        rename_chk.id = 'na-idx-rename-' + safe_id;
        rename_chk.className = 'naComponentEditor__IndexCheckbox';
        var rename_label_el = document.createElement('label');
        rename_label_el.htmlFor = rename_chk.id;
        rename_label_el.textContent = 'Also rename the .skp file to match definition name';
        rename_row.appendChild(rename_chk);
        rename_row.appendChild(rename_label_el);
        panel.appendChild(rename_row);

        panel.appendChild(na_build_custom_fields_section(entry, safe_id));

        if (entry.attributes && Object.keys(entry.attributes).length) {
            panel.appendChild(na_build_attribute_section(entry));
        }

        var btn_row = document.createElement('div');
        btn_row.className = 'naComponentEditor__ButtonRow';

        var save_lib_btn = document.createElement('button');
        save_lib_btn.type = 'button';
        save_lib_btn.className = 'naComponentEditor__Button naComponentEditor__Button--primary';
        save_lib_btn.textContent = 'Save Library Data';
        save_lib_btn.title = 'Writes Notes and Custom Fields to Na__ComponentLibrary dictionary';
        save_lib_btn.addEventListener('click', function () { na_save_library_data(entry, panel, safe_id); });

        var save_meta_btn = document.createElement('button');
        save_meta_btn.type = 'button';
        save_meta_btn.className = 'naComponentEditor__Button';
        save_meta_btn.textContent = 'Save Definition & Description';
        save_meta_btn.title = 'Saves Definition Name and Description to the .skp';
        save_meta_btn.addEventListener('click', function () { na_save_metadata(entry, panel, safe_id); });

        btn_row.appendChild(save_lib_btn);
        btn_row.appendChild(save_meta_btn);
        panel.appendChild(btn_row);

        return panel;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Custom Fields Section
// -----------------------------------------------------------------------------

    function na_build_custom_fields_section(entry, safe_id) {
        var section = document.createElement('div');
        section.className = 'naComponentEditor__CustomFieldsSection';
        section.setAttribute('id', 'na-idx-custom-section-' + safe_id);

        var heading = document.createElement('p');
        heading.className = 'naComponentEditor__DictionaryTitle';
        heading.textContent = 'Custom Fields (Na__ComponentLibrary dictionary)';
        section.appendChild(heading);

        var rows_wrap = document.createElement('div');
        rows_wrap.className = 'naComponentEditor__CustomFieldsRows';
        rows_wrap.setAttribute('id', 'na-idx-custom-rows-' + safe_id);

        var custom = entry.custom || {};
        Object.keys(custom).forEach(function (key) {
            rows_wrap.appendChild(na_build_custom_field_row(key, custom[key]));
        });

        section.appendChild(rows_wrap);

        var add_row = document.createElement('div');
        add_row.className = 'naComponentEditor__CustomFieldsAddRow';

        var add_key_input = document.createElement('input');
        add_key_input.type = 'text';
        add_key_input.className = 'naComponentEditor__Input naComponentEditor__CustomFieldKey';
        add_key_input.placeholder = 'New field name\u2026';

        var add_value_input = document.createElement('input');
        add_value_input.type = 'text';
        add_value_input.className = 'naComponentEditor__Input naComponentEditor__CustomFieldValue';
        add_value_input.placeholder = 'Value\u2026';

        var add_btn = document.createElement('button');
        add_btn.type = 'button';
        add_btn.className = 'naComponentEditor__Button';
        add_btn.textContent = 'Add Field';
        add_btn.addEventListener('click', function () {
            var key = add_key_input.value.trim();
            var val = add_value_input.value;
            if (!key) return;
            rows_wrap.appendChild(na_build_custom_field_row(key, val));
            add_key_input.value = '';
            add_value_input.value = '';
        });

        add_row.appendChild(add_key_input);
        add_row.appendChild(add_value_input);
        add_row.appendChild(add_btn);
        section.appendChild(add_row);

        return section;
    }

    function na_build_custom_field_row(key, value) {
        var row = document.createElement('div');
        row.className = 'naComponentEditor__CustomFieldRow';
        row.setAttribute('data-custom-key', key);

        var key_span = document.createElement('span');
        key_span.className = 'naComponentEditor__CustomFieldKeyLabel';
        key_span.textContent = key;
        key_span.title = key;

        var val_input = document.createElement('input');
        val_input.type = 'text';
        val_input.className = 'naComponentEditor__Input naComponentEditor__CustomFieldValueInput';
        val_input.value = value || '';
        val_input.setAttribute('data-custom-value', '');

        var del_btn = document.createElement('button');
        del_btn.type = 'button';
        del_btn.className = 'naComponentEditor__Button naComponentEditor__Button--danger naComponentEditor__CustomFieldDel';
        del_btn.textContent = '\u00d7';
        del_btn.title = 'Remove this custom field from dictionary';
        del_btn.addEventListener('click', function () {
            row.setAttribute('data-custom-deleted', '1');
            row.style.opacity = '0.4';
            val_input.disabled = true;
            del_btn.disabled = true;
        });

        row.appendChild(key_span);
        row.appendChild(val_input);
        row.appendChild(del_btn);
        return row;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Attribute Display (read-only expanded view)
// -----------------------------------------------------------------------------

    function na_build_attribute_section(entry) {
        var section = document.createElement('div');
        section.className = 'naComponentEditor__IndexAttrSection';

        var toggle_btn = document.createElement('button');
        toggle_btn.type = 'button';
        toggle_btn.className = 'naComponentEditor__Button naComponentEditor__IndexAttrToggle';
        toggle_btn.textContent = 'Show / Hide Attributes';

        var attr_wrap = document.createElement('div');
        attr_wrap.className = 'naComponentEditor__IndexAttrWrap';
        attr_wrap.style.display = 'none';

        toggle_btn.addEventListener('click', function () {
            attr_wrap.style.display = attr_wrap.style.display === 'none' ? 'block' : 'none';
        });

        Object.keys(entry.attributes).forEach(function (dict_name) {
            var dict_data = entry.attributes[dict_name];

            var dict_heading = document.createElement('p');
            dict_heading.className = 'naComponentEditor__DictionaryTitle';
            dict_heading.textContent = dict_name;
            attr_wrap.appendChild(dict_heading);

            var tbl = document.createElement('table');
            tbl.className = 'naComponentEditor__AttributeTable';

            var thead = document.createElement('thead');
            thead.innerHTML = '<tr><th>Key</th><th>Value</th></tr>';
            tbl.appendChild(thead);

            var tbody_el = document.createElement('tbody');
            Object.keys(dict_data).forEach(function (attr_key) {
                var tr = document.createElement('tr');
                tr.innerHTML = '<td class="naComponentEditor__IndexTd">' + na_escape(attr_key) + '</td>' +
                               '<td class="naComponentEditor__IndexTd">' + na_escape(dict_data[attr_key]) + '</td>';
                tbody_el.appendChild(tr);
            });

            tbl.appendChild(tbody_el);
            attr_wrap.appendChild(tbl);
        });

        section.appendChild(toggle_btn);
        section.appendChild(attr_wrap);
        return section;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Save Handlers
// -----------------------------------------------------------------------------

    function na_save_library_data(entry, panel, safe_id) {
        if (!entry.path) return;

        var notes_input = document.getElementById('na-idx-notes-' + safe_id);
        var notes_val   = notes_input ? notes_input.value : (entry.notes || '');

        var custom_section = document.getElementById('na-idx-custom-section-' + safe_id);
        var custom_rows    = custom_section
            ? custom_section.querySelectorAll('.naComponentEditor__CustomFieldRow')
            : [];

        var custom     = {};
        var deleted    = [];

        custom_rows.forEach(function (row) {
            var key = row.getAttribute('data-custom-key');
            if (!key) return;
            if (row.getAttribute('data-custom-deleted') === '1') {
                deleted.push(key);
            } else {
                var val_input = row.querySelector('[data-custom-value]');
                custom[key] = val_input ? val_input.value : '';
            }
        });

        var payload = {
            path:                entry.path,
            code:                entry.code_stored || '',
            gallery_name:        entry.gallery_name || '',
            notes:               notes_val,
            category:            entry.category || '',
            type:                entry.type || '',
            custom:              custom,
            deleted_custom_keys: deleted
        };

        if (typeof window.Na__ComponentEditorTools__UpdateLibraryData === 'function') {
            window.Na__ComponentEditorTools__UpdateLibraryData(payload);
        }
    }

    function na_save_metadata(entry, panel, safe_id) {
        var def_name_input = document.getElementById('na-idx-defname-' + safe_id);
        var desc_input     = document.getElementById('na-idx-desc-'    + safe_id);
        var rename_chk     = document.getElementById('na-idx-rename-'  + safe_id);

        var new_def_name = def_name_input ? def_name_input.value.trim() : '';
        var new_desc     = desc_input     ? desc_input.value            : '';
        var rename_file  = rename_chk     ? rename_chk.checked          : false;

        if (new_def_name && new_def_name !== entry.def_name) {
            if (typeof window.Na__ComponentEditorTools__RenameLibraryComponent === 'function') {
                window.Na__ComponentEditorTools__RenameLibraryComponent({
                    path:         entry.path,
                    new_def_name: new_def_name,
                    rename_file:  rename_file
                });
            }
        }

        if (typeof window.Na__ComponentEditorTools__UpdateLibraryMetadata === 'function') {
            window.Na__ComponentEditorTools__UpdateLibraryMetadata({
                path:        entry.path,
                def_name:    new_def_name || entry.def_name,
                description: new_desc,
                attributes:  []
            });
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Sort, Toggle & Utilities
// -----------------------------------------------------------------------------

    function entry_key_of(entry) {
        return entry.path || entry.file_name || '';
    }

    function na_toggle_edit_row(entry_key) {
        na_expanded_rows[entry_key] = !na_expanded_rows[entry_key];
        na_rebuild_table();
    }

    function na_set_sort(key) {
        if (na_sort_key === key) {
            na_sort_asc = !na_sort_asc;
        } else {
            na_sort_key = key;
            na_sort_asc = true;
        }
        na_rebuild_table();
        na_update_sort_indicators();
    }

    function na_update_sort_indicators() {
        var headers = document.querySelectorAll('.naComponentEditor__IndexTh--sortable');
        headers.forEach(function (th) {
            var key       = th.getAttribute('data-sort-key');
            var indicator = th.querySelector('.naComponentEditor__SortIndicator');
            if (!indicator) return;
            indicator.textContent = (key === na_sort_key)
                ? (na_sort_asc ? ' \u25b2' : ' \u25bc')
                : '';
        });
    }

    function na_build_labelled_input(label_text, input_id, value) {
        var label_el = document.createElement('label');
        label_el.className = 'naComponentEditor__Label';
        var span = document.createElement('span');
        span.textContent = label_text;
        var input = document.createElement('input');
        input.type = 'text';
        input.id = input_id;
        input.className = 'naComponentEditor__Input';
        input.value = value;
        label_el.appendChild(span);
        label_el.appendChild(input);
        return label_el;
    }

    function na_safe_id(str) {
        return String(str || '').replace(/[^A-Za-z0-9]/g, '_');
    }

    function na_escape(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Event Binding
// -----------------------------------------------------------------------------

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        var load_btn = document.getElementById('na-index-btn-load');
        if (load_btn) {
            load_btn.addEventListener('click', function () {
                if (typeof window.Na__ComponentEditorTools__GetIndex === 'function') {
                    window.Na__ComponentEditorTools__GetIndex();
                }
            });
        }

        var collapse_btn = document.getElementById('na-index-btn-collapse-all');
        if (collapse_btn) {
            collapse_btn.addEventListener('click', function () {
                na_expanded_rows = {};
                na_rebuild_table();
            });
        }

        var filter_input = na_filter_input();
        if (filter_input) {
            filter_input.addEventListener('input', na_rebuild_table);
        }

        var index_folder_filter = na_index_folder_filter();
        if (index_folder_filter) {
            index_folder_filter.addEventListener('change', na_rebuild_table);
        }

        var index_category_filter = na_index_category_filter();
        if (index_category_filter) {
            index_category_filter.addEventListener('change', function () {
                na_populate_index_type_filter();
                na_rebuild_table();
            });
        }

        var index_type_filter = na_index_type_filter();
        if (index_type_filter) {
            index_type_filter.addEventListener('change', na_rebuild_table);
        }

        var sortable_headers = document.querySelectorAll('.naComponentEditor__IndexTh--sortable');
        sortable_headers.forEach(function (th) {
            th.style.cursor = 'pointer';
            th.addEventListener('click', function () {
                var key = th.getAttribute('data-sort-key');
                if (key) na_set_sort(key);
            });
        });
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__RenderIndex = function (index_payload) {
        na_bind_events_once();
        na_render_index(index_payload);
    };

    Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__ApplyEntryUpdate = function (old_path, updated_entry) {
        if (!updated_entry) return;

        na_editing_active = false;

        var norm_old = String(old_path || '').replace(/\\/g, '/');
        var index = -1;
        for (var i = 0; i < na_all_entries.length; i++) {
            if (String(na_all_entries[i].path || '').replace(/\\/g, '/') === norm_old) {
                index = i;
                break;
            }
        }

        if (index === -1) {
            na_all_entries.push(updated_entry);
        } else {
            var old_key = na_all_entries[index].path || na_all_entries[index].file_name;
            var new_key = updated_entry.path || updated_entry.file_name;
            na_all_entries[index] = updated_entry;

            if (na_expanded_rows[old_key] && old_key !== new_key) {
                na_expanded_rows[new_key] = true;
                delete na_expanded_rows[old_key];
            }
        }

        na_rebuild_table();
        na_update_sort_indicators();
    };

    Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__SetTaxonomy = function (taxonomy) {
        na_taxonomy = taxonomy || { categories: [] };
        na_populate_index_category_filter();
        na_populate_index_type_filter();
        if (!na_editing_active) na_rebuild_table();
    };

    Na__ComponentEditorTools__IndexTab.Na__ComponentEditorTools__OnTabActivate = function () {
        if (typeof window.Na__ComponentEditorTools__GetIndex === 'function') {
            window.Na__ComponentEditorTools__GetIndex();
        }
    };

    window.Na__ComponentEditorTools__IndexTab = Na__ComponentEditorTools__IndexTab;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Init
// -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        na_bind_events_once();
    });

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
