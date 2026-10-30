// =============================================================================
// NA PAINTERLYNPR ASSETS - AUTHOR - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PainterlyAssets__Author__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PainterlyAssets__AuthorUi
// PURPOSE    : The Author tab: the selected component, the form that makes it a
//              library asset (collection, type, family, name and Var; how the
//              catalogue shows it; how PainterlyNPR draws it; each plop), the
//              Check that shows the plan with its Id, and Author Asset.
// CREATED    : 30-Oct-2026
//
// DESCRIPTION:
// - Every choice comes from PainterlyNPR's own files (the register, the DAT
//   schema, the engine's generators, kinds and material classes), pushed by
//   Ruby in state.options; nothing is offered that its validator would refuse.
// - A collection or type fills the recipe fields from the config's defaults
//   (the seeded assets' own recipes); every field stays editable.
// - Author Asset is offered only for the exact form a Check passed: any edit
//   after it asks for another Check. Ruby asks the build utility for the Id
//   again as it files the asset, so two sessions can never take one number.
//
// RUBY CALLS : readSelection, checkAuthor, author
// LISTENS TO : state, catalogue, selection, plan, authored, tab
//
// =============================================================================

(function () {
    'use strict';

    var Shell  = window.Na__PainterlyAssets__Shell;
    var Bridge = window.Na__PainterlyAssets__Bridge;
    var Ui     = { Filled: false, DisplayAuto: true, Selection: null, Plan: null, PlanForm: null, CheckedForm: null };

    function $(id) { return document.getElementById(id); }

    function na_state() { return Shell.na_get_state() || {}; }
    function na_options() { return na_state().options || {}; }

    // -------------------------------------------------------------------------
    // REGION | Filling the Form From PainterlyNPR's Lists
    // -------------------------------------------------------------------------

    function na_collection(code) {
        return (na_options().collections || []).filter(function (c) { return c.Code === code; })[0] || null;
    }

    // FUNCTION | Every Select's Options, Keeping What Is Chosen Where It Still Exists
    function na_fill_lists() {
        var options = na_options();
        var keep    = function (id) { return $(id).value; };

        Shell.na_fill_select($('na-f-collection'), (options.collections || []).map(function (c) {
            return { value: c.Code, label: c.Code + '  ' + c.Label };
        }), keep('na-f-collection') || '07');
        Shell.na_fill_select($('na-f-generator'), (options.generators || []).map(function (g) { return g.Key; }), keep('na-f-generator'));
        Shell.na_fill_select($('na-f-kind'), [{ value: '', label: 'None (drawn by its edges)' }].concat(options.kinds || []), keep('na-f-kind'));
        Shell.na_fill_select($('na-f-material'), (options.materials || []).map(function (m) {
            return { value: m.Key, label: m.Key + (m.Label ? '  (' + m.Label + ')' : '') };
        }), keep('na-f-material'));
        Shell.na_fill_select($('na-f-role'), options.roles || [], keep('na-f-role'));
        Shell.na_fill_select($('na-f-season'), options.seasons || [], keep('na-f-season'));
        Shell.na_fill_select($('na-f-facing'), options.facings || [], keep('na-f-facing'));
        Shell.na_fill_select($('na-f-status'), options.statuses || [], keep('na-f-status') || (na_state().author || {}).defaultStatus);
        na_fill_types(false);

        var problems = options.problems || [];
        var fault    = $('na-author-options-fault');
        fault.textContent = problems.length ? problems.join(' ') : '';
        fault.classList.toggle('na-hidden', !problems.length);
    }

    function na_fill_types(applyDefaults) {
        var collection = na_collection($('na-f-collection').value);
        var current    = $('na-f-type').value;
        Shell.na_fill_select($('na-f-type'), (collection ? collection.Types : []).map(function (t) {
            return { value: t.Type, label: Shell.na_split_camel(t.Type) + '  (block ' + t.Block + ')' };
        }), current);
        na_fill_families();
        if (applyDefaults) na_apply_defaults();
    }

    // The families already in this type, from the catalogue: a new variant of
    // the oak goes in the oak's ten (NPR_07_002x).
    function na_families() {
        var code = $('na-f-collection').value;
        var type = $('na-f-type').value;
        var byFamily = {};
        ((na_state().catalogue || {}).assets || []).forEach(function (asset) {
            if (asset.Collection !== code || asset.Type !== type) return;
            (byFamily[asset.Family] = byFamily[asset.Family] || []).push(asset);
        });
        return Object.keys(byFamily).sort().map(function (family) {
            return { family: family, assets: byFamily[family] };
        });
    }

    function na_fill_families() {
        var current = $('na-f-family').value;
        var items   = [{ value: '', label: 'New family (the next free ten)' }].concat(na_families().map(function (f) {
            var names = f.assets.map(function (a) { return a.Name; }).filter(function (n, i, all) { return all.indexOf(n) === i; });
            return { value: f.family, label: f.family + 'x  ' + names.join(', ') + '  (' + f.assets.length + ' of 9)' };
        }));
        Shell.na_fill_select($('na-f-family'), items, current);
    }

    // FUNCTION | The Recipe Defaults for the Chosen Collection and Type
    function na_apply_defaults() {
        var table = na_state().authorDefaults || {};
        var code  = $('na-f-collection').value;
        var type  = $('na-f-type').value;
        var row   = {};
        ['*', code, code + '/' + type].forEach(function (key) {
            var source = table[key];
            if (source) Object.keys(source).forEach(function (field) { row[field] = source[field]; });
        });
        if (row.generator !== undefined) $('na-f-generator').value = row.generator;
        $('na-f-kind').value = row.kind ? row.kind : '';
        if (row.material !== undefined) $('na-f-material').value = row.material;
        if (row.role !== undefined)     $('na-f-role').value = row.role;
        if (row.facing !== undefined)   $('na-f-facing').value = row.facing;
        if (row.season !== undefined)   $('na-f-season').value = row.season;
        if (row.scaleJitter !== undefined) $('na-f-jitter').value = String(row.scaleJitter);
        $('na-f-newshape').checked = !!row.newShapeEachPlop;
        $('na-f-autorotate').checked = row.autoRotate !== false;                 // <-- Left out means on, as the engine reads a DAT (v0.8.16)
        $('na-f-autoscale').checked  = row.autoScale !== false;
        na_generator_note();
    }

    function na_generator_note() {
        var key   = $('na-f-generator').value;
        var entry = (na_options().generators || []).filter(function (g) { return g.Key === key; })[0];
        Shell.na_text('na-f-generator-note', entry ? entry.Note : '');
    }

    // A family chosen: its name, and the next Var of that name.
    function na_family_changed() {
        var family = $('na-f-family').value;
        if (!family) { $('na-f-variant').value = 'Var-01'; return; }
        var group = na_families().filter(function (f) { return f.family === family; })[0];
        if (!group) return;
        var name = group.assets[0].Name;
        $('na-f-name').value = name;
        var highest = 0;
        group.assets.forEach(function (a) {
            var n = parseInt(String(a.Variant).replace('Var-', ''), 10);
            if (a.Name === name && isFinite(n) && n > highest) highest = n;
        });
        $('na-f-variant').value = 'Var-' + (highest + 1 < 10 ? '0' : '') + (highest + 1);
        na_name_changed();
    }

    // The display name follows the Name until someone types their own.
    function na_name_changed() {
        if (!Ui.DisplayAuto) return;
        var words = Shell.na_split_camel($('na-f-name').value).replace(/-/g, ' ').trim();
        $('na-f-display').value = words ? words.charAt(0) + words.slice(1).toLowerCase() : '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Form as Ruby Reads It
    // -------------------------------------------------------------------------

    function na_read_form() {
        return {
            collection       : $('na-f-collection').value,
            type             : $('na-f-type').value,
            family           : $('na-f-family').value,
            name             : $('na-f-name').value.trim(),
            variant          : $('na-f-variant').value.trim(),
            displayName      : $('na-f-display').value.trim(),
            description      : $('na-f-description').value.trim(),
            keywords         : $('na-f-keywords').value,
            season           : $('na-f-season').value,
            botanical        : $('na-f-botanical').value.trim(),
            status           : $('na-f-status').value,
            generator        : $('na-f-generator').value,
            kind             : $('na-f-kind').value,
            material         : $('na-f-material').value,
            role             : $('na-f-role').value,
            autoRotate       : $('na-f-autorotate').checked,
            facing           : $('na-f-facing').value,
            autoScale        : $('na-f-autoscale').checked,
            scaleJitter      : $('na-f-jitter').value.trim(),
            newShapeEachPlop : $('na-f-newshape').checked,
            minSpacingM      : $('na-f-spacing').value.trim(),
            reseat           : $('na-f-reseat').checked
        };
    }

    // Author Asset only for the very form the last passing Check saw.
    function na_update_author_button() {
        var ready = !!(Ui.Plan && Ui.Plan.ok && Ui.PlanForm === JSON.stringify(na_read_form()));
        $('na-author-go').disabled = !ready;
        $('na-author-stale').classList.toggle('na-hidden', !(Ui.Plan && Ui.Plan.ok && !ready));
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Selection, the Plan, the Result
    // -------------------------------------------------------------------------

    function na_row(parent, label, value, level) {
        var row = Shell.na_el('div', 'na-kv__row' + (level ? ' na-kv__row--' + level : ''));
        row.appendChild(Shell.na_el('span', 'na-kv__label', label));
        row.appendChild(Shell.na_el('span', 'na-kv__value', value));
        parent.appendChild(row);
    }

    function na_render_selection(selection) {
        Ui.Selection = selection;
        var box = Shell.na_clear($('na-author-selection'));
        if (!selection) { box.appendChild(Shell.na_el('p', 'na-hint', 'Select a component in the model, then Use Selection.')); return; }
        if (!selection.definitionName) {
            box.appendChild(Shell.na_el('p', 'na-note', selection.message || 'Nothing selected.'));
            return;
        }
        var title = Shell.na_el('div', 'na-sel__title', selection.definitionName);
        title.appendChild(Shell.na_el('span', 'na-sel__kind', selection.kind + (selection.instances > 1 ? ', ' + selection.instances + ' copies in the model' : '')));
        box.appendChild(title);
        var kv = Shell.na_el('div', 'na-kv');
        var size = selection.sizeMm || [];
        na_row(kv, 'Size', size.length ? size[0] + ' wide x ' + size[1] + ' deep x ' + size[2] + ' high (mm)' : '');
        var offset = selection.originOffsetMm || [0, 0, 0];
        na_row(kv, 'Origin', selection.originOk ? 'at the centre of its base' : offset.join(', ') + ' mm from the centre of its base', selection.originOk ? null : 'warn');
        if (selection.scaled) na_row(kv, 'This copy', 'scaled ' + selection.scale.join(' x ') + ' (the asset takes the component at its own size)', 'warn');
        na_row(kv, 'Contents', selection.faces + ' faces at its top level, ' + selection.parts + ' groups or components inside');
        box.appendChild(kv);
        (selection.blocked || []).forEach(function (reason) { box.appendChild(Shell.na_el('p', 'na-fault', reason)); });

        if (!$('na-f-name').value && selection.ok) {
            var suggested = String(selection.definitionName).replace(/[^A-Za-z0-9]+/g, ' ').trim().split(/\s+/).map(function (w) {
                return w.charAt(0).toUpperCase() + w.slice(1);
            }).join('');
            if (/^[A-Z]/.test(suggested)) { $('na-f-name').value = suggested; na_name_changed(); }
        }
        na_update_author_button();
    }

    function na_render_plan(plan) {
        Ui.Plan = plan;
        Ui.PlanForm = Ui.CheckedForm;
        var box = Shell.na_clear($('na-author-plan'));
        if (!plan) { na_update_author_button(); return; }

        if (plan.assetId) {
            var head = Shell.na_el('div', 'na-plan__id', plan.assetId);
            head.appendChild(Shell.na_el('span', 'na-plan__stem', plan.stem || ''));
            box.appendChild(head);
        }
        (plan.errors || []).forEach(function (text) { box.appendChild(Shell.na_el('p', 'na-fault', text)); });
        (plan.warnings || []).forEach(function (text) { box.appendChild(Shell.na_el('p', 'na-note', text)); });

        if (plan.folderRel) {
            var kv = Shell.na_el('div', 'na-kv');
            na_row(kv, 'Folder', plan.folderRel);
            Object.keys(plan.files || {}).forEach(function (slot) {
                var writes = slot === 'DAT' || slot === 'SKP';
                na_row(kv, slot, plan.files[slot] + (writes ? '' : '  (the factory)'), writes ? null : 'quiet');
            });
            na_row(kv, 'Path length', plan.longestRel + ' of ' + plan.maxRelative + ' from the library; ' + plan.longestAbs + ' of ' + plan.pathLimit + ' on this PC',
                   plan.longestRel > plan.maxRelative || plan.longestAbs > plan.pathLimit ? 'error' : null);
            if (plan.geometry) {
                var b = plan.geometry.Bounds || {};
                na_row(kv, 'Geometry', 'height ' + plan.geometry.NominalHeightM + ' m, spread ' + plan.geometry.NominalSpreadM + ' m' + (b.Size ? '  (box ' + b.Size.join(' x ') + ' m)' : ''));
            }
            if (plan.skpStem) na_row(kv, 'Component', plan.skpStem);
            box.appendChild(kv);
        }
        if (plan.ok) box.appendChild(Shell.na_el('p', 'na-hint', 'Author Asset renames the component to the name above, writes its SKP and DAT into that folder, then runs PainterlyNPR\'s validator. MOD, PXY and RND come from the factory in the PainterlyNPR app afterwards.'));
        na_update_author_button();
    }

    function na_render_authored(result) {
        var box = $('na-author-result');
        Shell.na_clear(box);
        box.classList.toggle('na-hidden', !result);
        if (!result) return;
        box.className = 'na-result ' + (result.ok ? 'na-result--ok' : 'na-result--error');
        box.appendChild(Shell.na_el('p', 'na-result__text', result.message));
        if (result.ok) {
            Ui.Plan = null;                                                                             // <-- One Check files one asset: the plan is spent
            Ui.PlanForm = null;
            Shell.na_clear($('na-author-plan'));
            $('na-f-family').value = '';
            na_update_author_button();
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        $('na-f-collection').addEventListener('change', function () { $('na-f-type').value = ''; na_fill_types(true); });
        $('na-f-type').addEventListener('change', function () { na_fill_families(); na_apply_defaults(); });
        $('na-f-family').addEventListener('change', na_family_changed);
        $('na-f-generator').addEventListener('change', na_generator_note);
        $('na-f-name').addEventListener('input', na_name_changed);
        $('na-f-display').addEventListener('input', function () { Ui.DisplayAuto = $('na-f-display').value.trim() === ''; });

        // Any edit after a Check asks for another.
        $('na-tab-author').addEventListener('input', na_update_author_button);
        $('na-tab-author').addEventListener('change', na_update_author_button);

        $('na-author-use-selection').addEventListener('click', function () { Bridge.na_call('readSelection', {}); });
        $('na-author-check').addEventListener('click', function () {
            Ui.CheckedForm = JSON.stringify(na_read_form());
            na_render_authored(null);
            if (!Bridge.na_call('checkAuthor', { form: na_read_form() })) Shell.na_set_status('Check needs SketchUp: this is a preview of the page.', 'warn');
        });
        $('na-author-go').addEventListener('click', function () {
            var plan = Ui.Plan;
            if (!plan || !plan.ok) return;
            Shell.na_confirm({
                title   : 'Author ' + plan.assetId + '?',
                text    : 'The selected component is renamed ' + plan.skpStem + ', and its SKP and DAT are written into ' + plan.folderRel +
                          ' in PainterlyNPR\'s library. One Undo takes the model change back; the files then stay (they are the library\'s).',
                confirm : 'Author ' + plan.assetId
            }, function () {
                Bridge.na_call_after_paint('author', { form: na_read_form() }, 'Authoring the asset', 'Asking PainterlyNPR for the Id again, then writing the SKP and DAT...');
            });
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Subscriptions
    // -------------------------------------------------------------------------

    Shell.na_on('state', function () {
        na_fill_lists();
        if (!Ui.Filled) {
            Ui.Filled = true;
            na_fill_types(true);
            if (!$('na-f-variant').value) $('na-f-variant').value = 'Var-01';
        }
        na_generator_note();
        na_update_author_button();
    });
    Shell.na_on('catalogue', na_fill_families);
    Shell.na_on('selection', na_render_selection);
    Shell.na_on('plan', na_render_plan);
    Shell.na_on('authored', na_render_authored);
    Shell.na_on('tab', function (tabId) { if (tabId === 'author') Bridge.na_call('readSelection', {}); });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PainterlyAssets__AuthorUi = { na_read_form: na_read_form };
})();

// =============================================================================
// END OF FILE
// =============================================================================
