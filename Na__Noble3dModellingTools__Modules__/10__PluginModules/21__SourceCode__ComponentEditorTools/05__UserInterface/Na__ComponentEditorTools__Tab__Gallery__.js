// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB | GALLERY
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__Tab__Gallery__.js
// PURPOSE    : Gallery tab - searchable thumbnail grid of library components.
//              Clicking a card triggers the Ruby placement tool.
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__GalleryTab = {};
    var na_events_bound  = false;
    var na_all_entries   = [];
    var na_taxonomy      = { categories: [] };
    var na_render_token  = '0';

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Helpers
// -----------------------------------------------------------------------------

    function na_gallery_grid() {
        return document.getElementById('na-gallery-grid');
    }

    function na_search_input() {
        return document.getElementById('na-gallery-search');
    }

    function na_folder_filter() {
        return document.getElementById('na-gallery-folder-filter');
    }

    function na_category_filter() {
        return document.getElementById('na-gallery-category-filter');
    }

    function na_type_filter() {
        return document.getElementById('na-gallery-type-filter');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Clipboard & Toast Helpers
// -----------------------------------------------------------------------------

    function na_extract_dir_from_path(file_path) {
        return String(file_path || '').replace(/[\\\/][^\\\/]+$/, '');
    }

    function na_copy_text_via_dom(text) {
        var ta = document.createElement('textarea');
        ta.value = String(text || '');
        ta.style.position = 'fixed';
        ta.style.left     = '-9999px';
        ta.style.top      = '0';
        ta.setAttribute('readonly', 'readonly');
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); } catch (e) { /* noop */ }
        document.body.removeChild(ta);
    }

    function na_show_copy_toast(message) {
        if (typeof window.Na__ComponentEditorTools__ReceiveStatus === 'function') {
            window.Na__ComponentEditorTools__ReceiveStatus({ message: message || 'File path copied to clipboard', variant: 'success' });
            setTimeout(function () {
                window.Na__ComponentEditorTools__ReceiveStatus({ message: '', variant: 'info' });
            }, 3000);
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Context Menu
// -----------------------------------------------------------------------------

    var na_context_menu_el = null;

    function na_get_context_menu() {
        if (na_context_menu_el) return na_context_menu_el;

        na_context_menu_el = document.createElement('div');
        na_context_menu_el.id = 'na-gallery-context-menu';
        na_context_menu_el.className = 'naComponentEditor__ContextMenu';
        document.body.appendChild(na_context_menu_el);
        return na_context_menu_el;
    }

    function na_build_context_menu_item(label, title, on_click) {
        var item = document.createElement('div');
        item.className = 'naComponentEditor__ContextMenuItem';
        item.textContent = label;
        if (title) item.title = title;
        item.addEventListener('click', function (e) {
            e.stopPropagation();
            on_click();
            na_hide_context_menu();
        });
        return item;
    }

    function na_show_context_menu(event, entry) {
        var menu = na_get_context_menu();
        menu.innerHTML = '';

        menu.appendChild(na_build_context_menu_item(
            'Insert At Axis',
            'Place component origin at the current model axes origin',
            function () {
                if (entry.path && typeof window.Na__ComponentEditorTools__InsertAtAxis === 'function') {
                    window.Na__ComponentEditorTools__InsertAtAxis(entry.path);
                }
            }
        ));

        menu.appendChild(na_build_context_menu_item(
            'Insert At Cursor',
            'Load component and place it interactively with the cursor (same as clicking the card)',
            function () {
                if (entry.path && typeof window.Na__ComponentEditorTools__InsertLibraryComponent === 'function') {
                    window.Na__ComponentEditorTools__InsertLibraryComponent(entry.path);
                }
            }
        ));

        menu.appendChild(na_build_context_menu_item(
            'Copy File Path',
            'Copy the full file path to clipboard',
            function () {
                if (!entry.path) return;
                na_copy_text_via_dom(entry.path.replace(/\//g, '\\'));
                if (typeof window.Na__ComponentEditorTools__CopyComponentPath === 'function') {
                    window.Na__ComponentEditorTools__CopyComponentPath(entry.path);
                }
                na_show_copy_toast('File path copied to clipboard');
            }
        ));

        menu.appendChild(na_build_context_menu_item(
            'Copy Directory Path',
            'Copy the containing folder path to clipboard',
            function () {
                if (!entry.path) return;
                var dir_path = na_extract_dir_from_path(entry.path);
                na_copy_text_via_dom(dir_path.replace(/\//g, '\\'));
                if (typeof window.Na__ComponentEditorTools__CopyDirectoryPath === 'function') {
                    window.Na__ComponentEditorTools__CopyDirectoryPath(dir_path);
                }
                na_show_copy_toast('Directory path copied to clipboard');
            }
        ));

        menu.appendChild(na_build_context_menu_item(
            'Open File',
            'Open the component file in a new SketchUp instance',
            function () {
                if (entry.path && typeof window.Na__ComponentEditorTools__OpenComponentFile === 'function') {
                    window.Na__ComponentEditorTools__OpenComponentFile(entry.path);
                }
            }
        ));

        var vw = document.documentElement.clientWidth;
        var vh = document.documentElement.clientHeight;
        var menu_w = 210;
        var menu_h = 210;
        var left = Math.min(event.clientX, vw - menu_w - 4);
        var top  = Math.min(event.clientY, vh - menu_h - 4);

        menu.style.left    = left + 'px';
        menu.style.top     = top  + 'px';
        menu.style.display = 'block';
    }

    function na_hide_context_menu() {
        var menu = na_get_context_menu();
        menu.style.display = 'none';
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Render
// -----------------------------------------------------------------------------

    function na_render_gallery(gallery_payload) {
        if (!gallery_payload) return;

        na_render_token = String(Date.now());
        na_all_entries  = gallery_payload.entries || [];

        var folders = gallery_payload.folders || [];
        na_populate_folder_filter(folders);
        na_populate_category_filter();
        na_populate_type_filter();

        na_apply_filters();
    }

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

    function na_all_types() {
        var seen = {};
        var list = [];
        (na_taxonomy.categories || []).forEach(function (c) {
            (c.types || []).forEach(function (t) {
                if (!seen[t]) { seen[t] = true; list.push(t); }
            });
        });
        return list;
    }

    function na_populate_category_filter() {
        var filter_el = na_category_filter();
        if (!filter_el) return;

        var current_val = filter_el.value;
        filter_el.innerHTML = '<option value="">All Categories</option>';

        na_category_names().forEach(function (name) {
            var opt = document.createElement('option');
            opt.value = name;
            opt.textContent = name;
            filter_el.appendChild(opt);
        });

        filter_el.value = current_val;
    }

    function na_populate_type_filter() {
        var filter_el = na_type_filter();
        if (!filter_el) return;

        var category_val = (na_category_filter() && na_category_filter().value) || '';
        var current_val  = filter_el.value;
        var types        = category_val ? na_types_for(category_val) : na_all_types();

        filter_el.innerHTML = '<option value="">All Types</option>';
        types.forEach(function (type_name) {
            var opt = document.createElement('option');
            opt.value = type_name;
            opt.textContent = type_name;
            filter_el.appendChild(opt);
        });

        filter_el.value = (types.indexOf(current_val) !== -1) ? current_val : '';
    }

    function na_first_level_folder(relative_dir) {
        if (!relative_dir || relative_dir === '(root)') return relative_dir || '';
        return relative_dir.split('/')[0];
    }

    function na_folder_matches(entry_dir, filter_value) {
        if (!filter_value) return true;
        if (!entry_dir) return false;
        return entry_dir === filter_value || entry_dir.indexOf(filter_value + '/') === 0;
    }

    function na_folder_display_label(raw_name, aliases) {
        var entry = aliases && aliases[raw_name];
        return (entry && entry['alias']) ? entry['alias'] : raw_name;
    }

    function na_folder_sort_order(raw_name, aliases) {
        var entry = aliases && aliases[raw_name];
        return (entry && entry['order'] != null) ? entry['order'] : 9999;
    }

    function na_populate_folder_filter(folders) {
        var filter_el = na_folder_filter();
        if (!filter_el) return;

        var current_val = filter_el.value;
        var seen = {};
        var top_level = [];

        folders.forEach(function (folder_name) {
            var first = na_first_level_folder(folder_name);
            if (!seen[first]) { seen[first] = true; top_level.push(first); }
        });

        var aliases = (typeof window.Na__ComponentEditorTools__CurrentFolderAliases === 'function')
            ? window.Na__ComponentEditorTools__CurrentFolderAliases()
            : {};

        top_level.sort(function (a, b) {
            var oa = na_folder_sort_order(a, aliases);
            var ob = na_folder_sort_order(b, aliases);
            if (oa !== ob) return oa - ob;
            return na_folder_display_label(a, aliases).toLowerCase() < na_folder_display_label(b, aliases).toLowerCase() ? -1 : 1;
        });

        filter_el.innerHTML = '<option value="">All Folders</option>';
        top_level.forEach(function (raw_name) {
            var opt = document.createElement('option');
            opt.value = raw_name;
            opt.textContent = na_folder_display_label(raw_name, aliases);
            filter_el.appendChild(opt);
        });

        filter_el.value = (seen[current_val]) ? current_val : '';
    }

    Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__RefreshFolderFilter = function () {
        if (!na_all_entries || !na_all_entries.length) return;
        var folders = [];
        var seen = {};
        na_all_entries.forEach(function (entry) {
            var dir = entry.relative_dir || '';
            if (!seen[dir]) { seen[dir] = true; folders.push(dir); }
        });
        na_populate_folder_filter(folders);
    };

    function na_apply_filters() {
        var search_term    = ((na_search_input() && na_search_input().value) || '').toLowerCase().trim();
        var folder_value   = (na_folder_filter() && na_folder_filter().value) || '';
        var category_value = (na_category_filter() && na_category_filter().value) || '';
        var type_value     = (na_type_filter() && na_type_filter().value) || '';

        var filtered = na_all_entries.filter(function (entry) {
            var text_match = !search_term ||
                (entry.code         || '').toLowerCase().indexOf(search_term) !== -1 ||
                (entry.gallery_name || '').toLowerCase().indexOf(search_term) !== -1 ||
                (entry.def_name     || '').toLowerCase().indexOf(search_term) !== -1 ||
                (entry.file_name    || '').toLowerCase().indexOf(search_term) !== -1 ||
                (entry.description  || '').toLowerCase().indexOf(search_term) !== -1;

            var folder_match   = na_folder_matches(entry.relative_dir || '', folder_value);
            var category_match = !category_value || (entry.category || '') === category_value;
            var type_match     = !type_value     || (entry.type || '') === type_value;

            return text_match && folder_match && category_match && type_match;
        });

        na_render_cards(filtered);
    }

    function na_render_cards(entries) {
        var grid = na_gallery_grid();
        if (!grid) return;

        grid.innerHTML = '';

        if (!entries.length) {
            var empty_msg = document.createElement('p');
            empty_msg.className = 'naComponentEditor__MutedText naComponentEditor__GalleryEmpty';
            empty_msg.textContent = 'No components match the current filter.';
            grid.appendChild(empty_msg);
            return;
        }

        entries.forEach(function (entry) {
            grid.appendChild(na_build_card(entry));
        });
    }

    function na_build_card(entry) {
        var card = document.createElement('div');
        card.className = 'naComponentEditor__GalleryCard';
        card.title = 'Click to place: ' + (entry.def_name || entry.file_name || '');

        var thumb_wrap = document.createElement('div');
        thumb_wrap.className = 'naComponentEditor__GalleryThumbWrap';

        var img = document.createElement('img');
        img.className = 'naComponentEditor__GalleryThumb';
        img.alt = entry.def_name || '';

        if (entry.thumbnail_uri) {
            img.src = entry.thumbnail_uri + '?v=' + na_render_token;
            img.onerror = function () {
                img.style.display = 'none';
                thumb_wrap.classList.add('naComponentEditor__GalleryThumbWrap--noImage');
            };
        } else {
            img.style.display = 'none';
            thumb_wrap.classList.add('naComponentEditor__GalleryThumbWrap--noImage');
        }

        thumb_wrap.appendChild(img);

        if (entry.truevision_valid === 'true') {
            var tv_badge = document.createElement('span');
            tv_badge.className = 'naComponentEditor__TvValidBadge';
            tv_badge.title = 'TrueVision Validated';
            tv_badge.textContent = '\u2713';
            thumb_wrap.appendChild(tv_badge);
        }

        var info = document.createElement('div');
        info.className = 'naComponentEditor__GalleryCardInfo';

        var display_name = (entry.gallery_name && entry.gallery_name.trim())
            ? entry.gallery_name.trim()
            : (entry.def_name || entry.file_name || '');

        var code_prefix = entry.code ? entry.code.trim().replace(/_+$/, '') : '';

        var name_el = document.createElement('div');
        name_el.className = 'naComponentEditor__GalleryCardName';
        name_el.textContent = display_name;
        name_el.title = entry.def_name || '';

        var meta_el = document.createElement('div');
        meta_el.className = 'naComponentEditor__GalleryCardMeta';
        if (entry.category) {
            var cat_badge = document.createElement('span');
            cat_badge.className = 'naComponentEditor__GalleryCardChip';
            cat_badge.textContent = entry.category;
            cat_badge.title = 'Category: ' + entry.category;
            window.Na__ComponentEditorTools__ApplyChipColor(cat_badge, entry.category);
            meta_el.appendChild(cat_badge);
        }
        if (entry.type) {
            var type_badge = document.createElement('span');
            type_badge.className = 'naComponentEditor__GalleryCardChip';
            type_badge.textContent = entry.type;
            type_badge.title = 'Type: ' + entry.type;
            window.Na__ComponentEditorTools__ApplyChipColor(type_badge, entry.type);
            meta_el.appendChild(type_badge);
        }
        if (code_prefix) {
            var code_badge = document.createElement('span');
            code_badge.className = 'naComponentEditor__GalleryCardCode';
            code_badge.textContent = code_prefix;
            meta_el.appendChild(code_badge);
        }

        info.appendChild(name_el);
        if (meta_el.children.length) info.appendChild(meta_el);

        card.appendChild(thumb_wrap);
        card.appendChild(info);

        card.addEventListener('click', function () {
            if (entry.path && typeof window.Na__ComponentEditorTools__InsertLibraryComponent === 'function') {
                window.Na__ComponentEditorTools__InsertLibraryComponent(entry.path);
            }
        });

        card.addEventListener('contextmenu', function (event) {
            event.preventDefault();
            na_show_context_menu(event, entry);
        });

        return card;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Event Binding
// -----------------------------------------------------------------------------

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        document.addEventListener('click', na_hide_context_menu);

        var search_input = na_search_input();
        if (search_input) {
            search_input.addEventListener('input', na_apply_filters);
        }

        var folder_filter = na_folder_filter();
        if (folder_filter) {
            folder_filter.addEventListener('change', na_apply_filters);
        }

        var category_filter = na_category_filter();
        if (category_filter) {
            category_filter.addEventListener('change', function () {
                na_populate_type_filter();
                na_apply_filters();
            });
        }

        var type_filter = na_type_filter();
        if (type_filter) {
            type_filter.addEventListener('change', na_apply_filters);
        }
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__RenderGallery = function (gallery_payload) {
        na_bind_events_once();
        na_render_gallery(gallery_payload);
    };

    Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__SetTaxonomy = function (taxonomy) {
        na_taxonomy = taxonomy || { categories: [] };
        na_populate_category_filter();
        na_populate_type_filter();
    };

    Na__ComponentEditorTools__GalleryTab.Na__ComponentEditorTools__OnTabActivate = function () {
        if (typeof window.Na__ComponentEditorTools__GetGallery === 'function') {
            window.Na__ComponentEditorTools__GetGallery();
        }
    };

    window.Na__ComponentEditorTools__GalleryTab = Na__ComponentEditorTools__GalleryTab;

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
