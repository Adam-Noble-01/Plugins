// =============================================================================
// NA COMPONENT EDITOR TOOLS - TAB | SETTINGS
// =============================================================================
//
// FILE       : Na__ComponentEditorTools__Tab__Settings__.js
// PURPOSE    : Render and manage the Settings tab - library folder config,
//              blocked folder list, and plugin maintenance
// CREATED    : 2026
//
// =============================================================================

(function () {
    'use strict';

// -----------------------------------------------------------------------------
// REGION | Module State
// -----------------------------------------------------------------------------

    var Na__ComponentEditorTools__SettingsTab = {};
    var na_events_bound = false;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Helpers
// -----------------------------------------------------------------------------

    function na_library_path_input() {
        return document.getElementById('na-settings-library-path');
    }

    function na_blocked_folder_list_el() {
        return document.getElementById('na-settings-blocked-folder-list');
    }

    function na_blocked_folder_input_el() {
        return document.getElementById('na-settings-blocked-folder-input');
    }

    function na_blocked_file_list_el() {
        return document.getElementById('na-settings-blocked-file-list');
    }

    function na_blocked_file_input_el() {
        return document.getElementById('na-settings-blocked-file-input');
    }

    function na_taxonomy_list_el() {
        return document.getElementById('na-settings-taxonomy-list');
    }

    function na_category_input_el() {
        return document.getElementById('na-settings-category-input');
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Config Rendering
// -----------------------------------------------------------------------------

    function na_render_config(config) {
        if (!config) return;

        var path_input = na_library_path_input();
        if (path_input) {
            path_input.value = config.components_library_path || '';
        }

        na_render_exclusion_list(
            na_blocked_folder_list_el(),
            config.blocked_folder_names || [],
            'No blocked folders configured.',
            function (name) {
                if (typeof window.Na__ComponentEditorTools__RemoveBlockedFolder === 'function') {
                    window.Na__ComponentEditorTools__RemoveBlockedFolder(name);
                }
            }
        );

        na_render_exclusion_list(
            na_blocked_file_list_el(),
            config.blocked_file_names || [],
            'No blocked files configured.',
            function (name) {
                if (typeof window.Na__ComponentEditorTools__RemoveBlockedFile === 'function') {
                    window.Na__ComponentEditorTools__RemoveBlockedFile(name);
                }
            }
        );
    }

    function na_render_exclusion_list(list_el, names, empty_message, on_remove) {
        if (!list_el) return;

        list_el.innerHTML = '';

        if (!names.length) {
            var empty_msg = document.createElement('p');
            empty_msg.className = 'naComponentEditor__MutedText';
            empty_msg.textContent = empty_message;
            list_el.appendChild(empty_msg);
            return;
        }

        names.forEach(function (entry_name) {
            var chip = document.createElement('div');
            chip.className = 'naComponentEditor__BlockedChip';

            var label = document.createElement('span');
            label.className = 'naComponentEditor__BlockedChipLabel';
            label.textContent = entry_name;

            var remove_btn = document.createElement('button');
            remove_btn.className = 'naComponentEditor__BlockedChipRemove';
            remove_btn.type = 'button';
            remove_btn.textContent = '\u00d7';
            remove_btn.title = 'Remove block';
            remove_btn.setAttribute('data-entry', entry_name);
            remove_btn.addEventListener('click', function () {
                var name = remove_btn.getAttribute('data-entry');
                if (name) on_remove(name);
            });

            chip.appendChild(label);
            chip.appendChild(remove_btn);
            list_el.appendChild(chip);
        });
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Taxonomy Rendering
// -----------------------------------------------------------------------------

    function na_render_taxonomy(taxonomy) {
        var list_el = na_taxonomy_list_el();
        if (!list_el) return;

        list_el.innerHTML = '';

        var categories = (taxonomy && taxonomy.categories) || [];
        if (!categories.length) {
            var empty = document.createElement('p');
            empty.className = 'naComponentEditor__MutedText';
            empty.textContent = 'No categories yet. Click "Populate from Standards" or add one below.';
            list_el.appendChild(empty);
            return;
        }

        categories.forEach(function (category) {
            list_el.appendChild(na_build_category_block(category));
        });
    }

    function na_build_category_block(category) {
        var block = document.createElement('div');
        block.className = 'naComponentEditor__TaxonomyCategory';

        var header = document.createElement('div');
        header.className = 'naComponentEditor__TaxonomyCategoryHeader';

        var name_el = document.createElement('span');
        name_el.className = 'naComponentEditor__TaxonomyCategoryName';
        name_el.textContent = category.name;

        var remove_cat_btn = document.createElement('button');
        remove_cat_btn.type = 'button';
        remove_cat_btn.className = 'naComponentEditor__Button naComponentEditor__Button--danger naComponentEditor__TaxonomyCategoryRemove';
        remove_cat_btn.textContent = 'Remove Category';
        remove_cat_btn.addEventListener('click', function () {
            if (typeof window.Na__ComponentEditorTools__RemoveCategory === 'function') {
                window.Na__ComponentEditorTools__RemoveCategory(category.name);
            }
        });

        header.appendChild(name_el);
        header.appendChild(remove_cat_btn);
        block.appendChild(header);

        var chips = document.createElement('div');
        chips.className = 'naComponentEditor__TaxonomyTypeChips';

        (category.types || []).forEach(function (type_name) {
            chips.appendChild(na_build_type_chip(category.name, type_name));
        });

        block.appendChild(chips);
        block.appendChild(na_build_type_add_row(category.name));
        return block;
    }

    function na_build_type_chip(category_name, type_name) {
        var chip = document.createElement('div');
        chip.className = 'naComponentEditor__BlockedChip';

        var label = document.createElement('span');
        label.className = 'naComponentEditor__BlockedChipLabel';
        label.textContent = type_name;

        var remove_btn = document.createElement('button');
        remove_btn.type = 'button';
        remove_btn.className = 'naComponentEditor__BlockedChipRemove';
        remove_btn.textContent = '\u00d7';
        remove_btn.title = 'Remove type';
        remove_btn.addEventListener('click', function () {
            if (typeof window.Na__ComponentEditorTools__RemoveType === 'function') {
                window.Na__ComponentEditorTools__RemoveType(category_name, type_name);
            }
        });

        chip.appendChild(label);
        chip.appendChild(remove_btn);
        return chip;
    }

    function na_build_type_add_row(category_name) {
        var row = document.createElement('div');
        row.className = 'naComponentEditor__TaxonomyTypeAddRow';

        var input = document.createElement('input');
        input.type = 'text';
        input.className = 'naComponentEditor__Input naComponentEditor__TaxonomyTypeInput';
        input.placeholder = 'New type for ' + category_name + '\u2026';

        function submit_type() {
            var value = input.value.trim();
            if (!value) return;
            if (typeof window.Na__ComponentEditorTools__AddType === 'function') {
                window.Na__ComponentEditorTools__AddType(category_name, value);
            }
            input.value = '';
        }

        var add_btn = document.createElement('button');
        add_btn.type = 'button';
        add_btn.className = 'naComponentEditor__Button';
        add_btn.textContent = 'Add Type';
        add_btn.addEventListener('click', submit_type);

        input.addEventListener('keydown', function (evt) {
            if (evt.key === 'Enter') { evt.preventDefault(); submit_type(); }
        });

        row.appendChild(input);
        row.appendChild(add_btn);
        return row;
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Event Binding
// -----------------------------------------------------------------------------

    function na_bind_events_once() {
        if (na_events_bound) return;
        na_events_bound = true;

        var browse_btn = document.getElementById('na-settings-btn-browse-library');
        if (browse_btn) {
            browse_btn.addEventListener('click', function () {
                if (typeof window.Na__ComponentEditorTools__SetLibraryPath === 'function') {
                    window.Na__ComponentEditorTools__SetLibraryPath();
                }
            });
        }

        var add_folder_btn = document.getElementById('na-settings-btn-add-blocked-folder');
        if (add_folder_btn) {
            add_folder_btn.addEventListener('click', function () {
                na_add_blocked_folder_from_input();
            });
        }

        var folder_input = na_blocked_folder_input_el();
        if (folder_input) {
            folder_input.addEventListener('keydown', function (evt) {
                if (evt.key === 'Enter') na_add_blocked_folder_from_input();
            });
        }

        var add_file_btn = document.getElementById('na-settings-btn-add-blocked-file');
        if (add_file_btn) {
            add_file_btn.addEventListener('click', function () {
                na_add_blocked_file_from_input();
            });
        }

        var file_input = na_blocked_file_input_el();
        if (file_input) {
            file_input.addEventListener('keydown', function (evt) {
                if (evt.key === 'Enter') na_add_blocked_file_from_input();
            });
        }

        var refresh_library_btn = document.getElementById('na-settings-btn-refresh-library');
        if (refresh_library_btn) {
            refresh_library_btn.addEventListener('click', function () {
                if (typeof window.Na__ComponentEditorTools__RefreshLibrary === 'function') {
                    window.Na__ComponentEditorTools__RefreshLibrary();
                }
            });
        }

        var reload_button = document.getElementById('na-component-btn-settings-reload');
        if (reload_button) {
            reload_button.addEventListener('click', function () {
                if (typeof window.Na__ComponentEditorTools__ReloadPlugin === 'function') {
                    window.Na__ComponentEditorTools__ReloadPlugin();
                }
            });
        }

        var seed_taxonomy_btn = document.getElementById('na-settings-btn-seed-taxonomy');
        if (seed_taxonomy_btn) {
            seed_taxonomy_btn.addEventListener('click', function () {
                if (typeof window.Na__ComponentEditorTools__SeedTaxonomy === 'function') {
                    window.Na__ComponentEditorTools__SeedTaxonomy();
                }
            });
        }

        var add_category_btn = document.getElementById('na-settings-btn-add-category');
        if (add_category_btn) {
            add_category_btn.addEventListener('click', na_add_category_from_input);
        }

        var category_input = na_category_input_el();
        if (category_input) {
            category_input.addEventListener('keydown', function (evt) {
                if (evt.key === 'Enter') na_add_category_from_input();
            });
        }
    }

    function na_add_category_from_input() {
        var input = na_category_input_el();
        if (!input) return;

        var name = input.value.trim();
        if (!name) return;

        if (typeof window.Na__ComponentEditorTools__AddCategory === 'function') {
            window.Na__ComponentEditorTools__AddCategory(name);
        }
        input.value = '';
    }

    function na_add_blocked_folder_from_input() {
        var input = na_blocked_folder_input_el();
        if (!input) return;

        var folder_name = input.value.trim();
        if (!folder_name) return;

        if (typeof window.Na__ComponentEditorTools__AddBlockedFolder === 'function') {
            window.Na__ComponentEditorTools__AddBlockedFolder(folder_name);
        }
        input.value = '';
    }

    function na_add_blocked_file_from_input() {
        var input = na_blocked_file_input_el();
        if (!input) return;

        var file_name = input.value.trim();
        if (!file_name) return;

        if (typeof window.Na__ComponentEditorTools__AddBlockedFile === 'function') {
            window.Na__ComponentEditorTools__AddBlockedFile(file_name);
        }
        input.value = '';
    }

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__Render = function (_payload) {
        na_bind_events_once();
    };

    Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__RenderConfig = function (config) {
        na_render_config(config);
    };

    Na__ComponentEditorTools__SettingsTab.Na__ComponentEditorTools__RenderTaxonomy = function (taxonomy) {
        na_render_taxonomy(taxonomy);
    };

    window.Na__ComponentEditorTools__SettingsTab = Na__ComponentEditorTools__SettingsTab;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Init
// -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        na_bind_events_once();

        if (typeof window.Na__ComponentEditorTools__GetUserConfig === 'function') {
            window.Na__ComponentEditorTools__GetUserConfig();
        }
    });

// endregion -------------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
