/* Advanced resource inventory and side-by-side editing. Ruby owns scope checks. */
(function () {
    'use strict';
    var data = null, sourcePath = '', kind = 'tags', busy = false, sequence = 0;
    var drafts = {}, standardChoices = {}, standardFilters = {}, editorOpen = false;
    function el(id) { return document.getElementById('na-advanced-' + id); }
    function node(tag, text, className) {
        var item = document.createElement(tag);
        if (text !== undefined) item.textContent = text;
        if (className) item.className = className;
        return item;
    }
    function button(text, handler) {
        var b = node('button', text, 'naComponentEditor__Button');
        b.type = 'button'; b.disabled = busy; b.addEventListener('click', handler); return b;
    }
    function status(message, error) {
        el('status').textContent = message;
        el('status').classList.toggle('naAdvanced__Error', !!error);
    }
    function controls() {
        ['current', 'query', 'tags', 'materials', 'close'].forEach(function (id) { el(id).disabled = busy; });
        el('edit').disabled = busy || !data;
        el('filter').disabled = busy;
        el('save-file').disabled = busy || !data || !data.path || !data.modified;
        el('editor').querySelectorAll('button, input, select').forEach(function (item) { item.disabled = busy || item.dataset.protected === 'true' || item.dataset.unavailable === 'true'; });
    }
    function request(action, extra) {
        if (busy) return;
        var callback = window.sketchup && window.sketchup.na_componenteditortools_advanced;
        if (typeof callback !== 'function') { status('SketchUp connection unavailable. Reopen the plugin in SketchUp.', true); return; }
        var payload = Object.assign({ action: action, token: data && data.token, request_id: ++sequence }, extra || {});
        busy = true; controls(); status(action === 'query' ? 'Opening and querying model…' : 'Applying change…');
        try { callback(JSON.stringify(payload)); }
        catch (error) { busy = false; controls(); status(error.message, true); }
    }
    function query() {
        data = null; drafts = {}; standardChoices = {}; standardFilters = {}; render(); request('query', { path: sourcePath });
    }
    function rows() {
        var filter = el('filter').value.trim().toLowerCase();
        return data ? data[kind].filter(function (row) { return (row.display_name + ' ' + row.name).toLowerCase().indexOf(filter) >= 0; }) : [];
    }
    function detail(row) {
        if (kind === 'tags') return row.uses + ' assigned entities · ' + (row.visible ? 'Visible' : 'Hidden') + (row.folder ? ' · Folder: ' + row.folder : '') + (row.active ? ' · Active tag' : '') + (row.default ? ' · Protected default' : '');
        return row.uses + ' direct assignments · ' + row.opacity + '% opacity · ' + (row.texture ? 'Texture: ' + row.texture : 'Solid colour');
    }
    function standardPicker(row) {
        var standards = (data.standards && data.standards[kind]) || [];
        var box = node('div', undefined, 'naAdvanced__StandardPicker');
        box.appendChild(node('strong', kind === 'tags' ? 'Retag from SSOT collection' : 'Swap to SSOT material'));
        var search = node('input'); search.type = 'search'; search.placeholder = 'Search your collection…';
        search.value = standardFilters[row.id] || '';
        search.setAttribute('aria-label', 'Search SSOT collection for ' + row.display_name);
        var select = node('select'); select.setAttribute('aria-label', 'SSOT replacement for ' + row.display_name);
        select.id = 'na-advanced-standard-' + row.id;
        var hint = node('small');
        var apply = button(kind === 'tags' ? 'Retag all uses' : 'Swap all uses', function () {
            if (!select.value) return;
            request(kind === 'tags' ? 'retag_ssot' : 'swap_material_ssot', { id: row.id, existing_name: row.name, standard_key: select.value });
        });
        function selectionChanged() {
            standardChoices[row.id] = select.value;
            var entry = standards.find(function (item) { return item.key === select.value; });
            hint.textContent = entry ? entry.description : 'Choose a collection item to apply.';
            apply.dataset.unavailable = String(!entry);
            controls();
        }
        function populate() {
            var filter = search.value.trim().toLowerCase(); standardFilters[row.id] = search.value;
            select.replaceChildren();
            var placeholder = node('option', 'Choose from SSOT…'); placeholder.value = ''; select.appendChild(placeholder);
            var groups = {};
            standards.forEach(function (entry) {
                if (filter && [entry.name, entry.key, entry.group, entry.description].join(' ').toLowerCase().indexOf(filter) < 0) return;
                if (!groups[entry.group]) { groups[entry.group] = node('optgroup'); groups[entry.group].label = entry.group; select.appendChild(groups[entry.group]); }
                var option = node('option', entry.default ? 'Default — remove direct material' : entry.name);
                option.value = entry.key; groups[entry.group].appendChild(option);
            });
            select.value = standardChoices[row.id] || '';
            selectionChanged();
        }
        search.addEventListener('input', populate); select.addEventListener('change', selectionChanged);
        [search, select, apply].forEach(function (item) { item.dataset.protected = String(!!row.default); });
        box.append(search, select, hint, apply);
        if (!standards.length) box.appendChild(node('small', 'SSOT collection unavailable. Query again to reload it.'));
        populate();
        return box;
    }
    function renderList() {
        el('list').replaceChildren(); el('edit-list').replaceChildren();
        el('tags').setAttribute('aria-pressed', String(kind === 'tags'));
        el('materials').setAttribute('aria-pressed', String(kind === 'materials'));
        el('editor-title').textContent = kind === 'tags' ? 'Tags editor' : 'Materials editor';
        el('editor-help').textContent = kind === 'tags' ? 'Retag all uses assigns the chosen SSOT tag throughout this model. Original tags remain available. Delete moves geometry to Untagged; the default tag is protected.' : 'Swap applies the SSOT colour, opacity and PBR recipe to all uses, including face backs and nested groups. An existing material with the chosen name is also refreshed; original materials remain as unused entries. Undo restores the swap.';
        var visible = rows();
        if (!visible.length) el('list').appendChild(node('p', data ? 'No ' + kind + ' match this query.' : 'Run a query to list every tag and material.', 'naAdvanced__Empty'));
        visible.forEach(function (row) {
            var card = node('div', undefined, 'naAdvanced__Resource');
            var title = node('strong', row.display_name);
            if (row.color) {
                var swatch = node('span', '', 'naAdvanced__Swatch'); swatch.style.backgroundColor = row.color; title.prepend(swatch);
            }
            card.append(title, node('p', detail(row)));
            card.appendChild(button('Edit', function () { editorOpen = true; renderList(); controls(); var input = document.getElementById('na-advanced-name-' + row.id); if (input) { input.focus(); input.scrollIntoView({ block: 'nearest' }); } }));
            el('list').appendChild(card);
            if (!editorOpen) return;
            var edit = node('div', undefined, 'naAdvanced__EditRow');
            edit.appendChild(node('small', 'Existing name'));
            edit.appendChild(node('strong', row.display_name));
            var label = node('label', 'Becomes →');
            var input = node('input'); input.type = 'text'; input.id = 'na-advanced-name-' + row.id;
            input.value = Object.prototype.hasOwnProperty.call(drafts, row.id) ? drafts[row.id] : row.name;
            input.setAttribute('aria-label', 'New name for ' + row.display_name);
            input.dataset.protected = String(!!row.default);
            input.addEventListener('input', function () { drafts[row.id] = input.value; });
            label.appendChild(input); edit.appendChild(label);
            var actions = node('div', undefined, 'naAdvanced__Actions');
            var save = button('Save', function () { request('rename', { id: row.id, existing_name: row.name, name: input.value }); });
            save.dataset.protected = String(!!row.default); actions.appendChild(save);
            if (kind === 'tags') {
                var remove = button('Delete → Untagged', function () { request('delete_tag', { id: row.id, existing_name: row.name }); });
                remove.dataset.protected = String(!!row.default); actions.appendChild(remove);
            }
            if (row.default) edit.appendChild(node('small', 'SketchUp default tag — protected'));
            edit.appendChild(actions);
            edit.appendChild(standardPicker(row));
            el('edit-list').appendChild(edit);
        });
        el('editor').hidden = !editorOpen;
        el('editor').parentElement.classList.toggle('naAdvanced__Workspace--editing', editorOpen);
        controls();
    }
    function render() {
        el('source').textContent = (data && (data.path || data.title)) || sourcePath || 'Current SketchUp model';
        el('summary').replaceChildren(); el('contents').replaceChildren();
        if (data) {
            [[data.tags.length, 'Tags'], [data.materials.length, 'Materials'], [data.entity_count, 'Stored entities'], [data.definition_count, 'Definitions']].forEach(function (pair) {
                var stat = node('div'); stat.append(node('strong', String(pair[0])), node('span', pair[1])); el('summary').appendChild(stat);
            });
            el('contents').appendChild(node('p', data.root_count + ' root entities. Nested and unused definitions counted once; material counts include front and back face assignments.'));
            Object.keys(data.entity_types).sort().forEach(function (type) { el('contents').appendChild(node('p', type + ': ' + data.entity_types[type])); });
            var table = node('table', undefined, 'naAdvanced__Definitions');
            var head = node('tr'); ['Definition', 'Kind', 'Entities', 'Instances'].forEach(function (title) { head.appendChild(node('th', title)); }); table.appendChild(head);
            data.definitions.forEach(function (def) { var tr = node('tr'); [def.name, def.kind, def.entities, def.instances].forEach(function (value) { tr.appendChild(node('td', String(value))); }); table.appendChild(tr); });
            el('contents').appendChild(table);
        }
        renderList();
    }
    window.Na__ComponentEditorTools__ReceiveAdvanced = function (result) {
        if (result.request_id !== sequence) return;
        busy = false;
        if (result.success && result.data) {
            data = result.data;
            // Preserve unsaved drafts for other rows across a single-row save.
            Object.keys(drafts).forEach(function (id) {
                var row = data.tags.concat(data.materials).find(function (item) { return item.id === id; });
                if (!row || row.name === drafts[id].trim()) delete drafts[id];
            });
            render();
        }
        var catalogErrors = data && data.standards && data.standards.errors || [];
        controls(); status(result.message + (catalogErrors.length ? ' ' + catalogErrors.join(' ') : ''), !result.success || catalogErrors.length > 0);
    };
    window.Na__ComponentEditorTools__AdvancedTab = {
        open: function (entry) {
            if (busy) return;
            sourcePath = entry.path || ''; editorOpen = false; el('filter').value = '';
            window.Na__ComponentEditorTools__TabRouter.Na__ComponentEditorTools__ActivateTab('advanced', true);
            query();
        }
    };
    function init() {
        el('query').addEventListener('click', query);
        el('current').addEventListener('click', function () { sourcePath = ''; editorOpen = false; query(); });
        el('save-file').addEventListener('click', function () { request('save_file'); });
        el('tags').addEventListener('click', function () { kind = 'tags'; renderList(); });
        el('materials').addEventListener('click', function () { kind = 'materials'; renderList(); });
        el('filter').addEventListener('input', renderList);
        el('edit').addEventListener('click', function () { editorOpen = true; renderList(); });
        el('close').addEventListener('click', function () { editorOpen = false; renderList(); });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
