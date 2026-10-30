// =============================================================================
// NA PAINTERLYNPR ASSETS - CATALOGUE - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PainterlyAssets__Catalogue__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PainterlyAssets__CatalogueUi
// PURPOSE    : The Catalogue tab: every library asset as a card, searched and
//              filtered by collection and type, shown Rendered (RND) or as its
//              Proxy (PXY), exactly as PainterlyNPR's Assets drawer does; the
//              chosen asset's details; Place in Model, Write SKP, Open Folder.
// CREATED    : 30-Oct-2026
//
// DESCRIPTION:
// - Search is the app's rule (PainterlyNPR__AssetLibrary__Search): every word
//   of the query must appear somewhere among the asset's Id, names, type,
//   collection, variant, description, botanical name and keywords, so
//   "oak tree" finds the mature oak and "lav" every lavender.
// - A card with no picture of the chosen kind shows the other one; with
//   neither, "No picture yet" (the factory has not rendered it).
// - Click a card for its details; double-click it to place it at once.
//
// RUBY CALLS : refresh, place, writeSkp, writeMissingSkps, openFolder, setPref
// LISTENS TO : state, catalogue
//
// =============================================================================

(function () {
    'use strict';

    var Shell  = window.Na__PainterlyAssets__Shell;
    var Bridge = window.Na__PainterlyAssets__Bridge;
    var Ui     = { Query: '', Collection: '', Type: '', Thumbs: 'RND', Selected: null };
    var SLOTS  = ['DAT', 'MOD', 'SKP', 'PXY', 'RND'];

    // -------------------------------------------------------------------------
    // REGION | Reading the Catalogue
    // -------------------------------------------------------------------------

    function na_catalogue() {
        var state = Shell.na_get_state();
        return state && state.catalogue ? state.catalogue : { ok: false, assets: [], collections: [], problems: [] };
    }

    function na_find(assetId) {
        var assets = na_catalogue().assets || [];
        for (var i = 0; i < assets.length; i += 1) if (assets[i].AssetId === assetId) return assets[i];
        return null;
    }

    // HELPER FUNCTION | The Assets the Search and Filters Leave
    // @return {Array}
    function na_search() {
        var words = Ui.Query.toLowerCase().split(/\s+/).filter(Boolean);
        return (na_catalogue().assets || []).filter(function (asset) {
            if (Ui.Collection && asset.Collection !== Ui.Collection) return false;
            if (Ui.Type && asset.Type !== Ui.Type) return false;
            if (!words.length) return true;
            var hay = [asset.AssetId, asset.DisplayName, asset.Name, asset.Type, asset.CollectionName, asset.Variant,
                       asset.Description, asset.Botanical || ''].concat(asset.Keywords || []).join(' ').toLowerCase();
            return words.every(function (word) { return hay.indexOf(word) >= 0; });
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Filters and Cards
    // -------------------------------------------------------------------------

    function na_chip(attr, value, label, active) {
        var chip = Shell.na_el('button', 'na-chip' + (active ? ' na-chip--active' : ''), label);
        chip.type = 'button';
        chip.setAttribute('data-' + attr, value);
        chip.setAttribute('aria-pressed', active ? 'true' : 'false');
        return chip;
    }

    // FUNCTION | The Chips: a chip per collection that has assets, then its types
    function na_render_filters() {
        var catalogue   = na_catalogue();
        var collections = catalogue.collections || [];
        var row         = Shell.na_clear(document.getElementById('na-cat-collections'));
        row.appendChild(na_chip('collection', '', 'All ' + (catalogue.assets || []).length, !Ui.Collection));
        collections.filter(function (c) { return c.Count > 0; }).forEach(function (c) {
            row.appendChild(na_chip('collection', c.Code, c.Label + ' ' + c.Count, Ui.Collection === c.Code));
        });

        var types      = Shell.na_clear(document.getElementById('na-cat-types'));
        var collection = collections.filter(function (c) { return c.Code === Ui.Collection; })[0];
        types.classList.toggle('na-hidden', !collection);
        if (!collection) return;
        types.appendChild(na_chip('type', '', 'All types', !Ui.Type));
        collection.Types.filter(function (t) { return t.Count > 0; }).forEach(function (t) {
            types.appendChild(na_chip('type', t.Type, Shell.na_split_camel(t.Type) + ' ' + t.Count, Ui.Type === t.Type));
        });
    }

    function na_picture_url(asset) {
        var pictures = asset.Pictures || {};
        return pictures[Ui.Thumbs] || pictures[Ui.Thumbs === 'RND' ? 'PXY' : 'RND'] || null;
    }

    function na_card(asset) {
        var card = Shell.na_el('div', 'na-asset-card' + (Ui.Selected === asset.AssetId ? ' na-asset-card--selected' : ''));
        card.setAttribute('role', 'listitem');
        card.setAttribute('data-asset-id', asset.AssetId);
        card.title = asset.DisplayName + ' (' + asset.AssetId + '). Click for details; double-click to place it.';

        var thumb = Shell.na_el('div', 'na-asset-card__thumb');
        var url   = na_picture_url(asset);
        if (url) {
            var img = document.createElement('img');
            img.src = url;
            img.alt = '';
            img.loading = 'lazy';
            img.draggable = false;
            img.onerror = function () { thumb.classList.add('na-asset-card__thumb--none'); thumb.textContent = 'Picture unreadable'; };
            thumb.appendChild(img);
        } else {
            thumb.classList.add('na-asset-card__thumb--none');
            thumb.textContent = 'No picture yet';
        }

        var badges = Shell.na_el('div', 'na-asset-card__badges');
        var skp    = asset.Files && asset.Files.SKP;
        badges.appendChild(Shell.na_el('span', 'na-badge ' + (skp && skp.Present ? 'na-badge--ok' : 'na-badge--pending'), skp && skp.Present ? 'SKP' : 'No SKP'));
        if (asset.InModel) badges.appendChild(Shell.na_el('span', 'na-badge na-badge--model', 'In model'));
        if (asset.Status === 'Draft') badges.appendChild(Shell.na_el('span', 'na-badge na-badge--draft', 'Draft'));
        thumb.appendChild(badges);

        var height = Shell.na_format_height(asset.NominalHeightM);
        card.appendChild(thumb);
        card.appendChild(Shell.na_el('div', 'na-asset-card__name', asset.DisplayName));
        card.appendChild(Shell.na_el('div', 'na-asset-card__meta', asset.AssetId + (height ? ' \u00b7 ' + height : '')));
        return card;
    }

    // FUNCTION | The Cards: what the search and filters leave
    function na_render_cards() {
        Array.prototype.forEach.call(document.querySelectorAll('[data-na-thumbs]'), function (button) {
            var on = button.getAttribute('data-na-thumbs') === Ui.Thumbs;
            button.classList.toggle('na-segment--active', on);
            button.setAttribute('aria-pressed', on ? 'true' : 'false');
        });

        var catalogue = na_catalogue();
        var grid      = Shell.na_clear(document.getElementById('na-cat-grid'));
        var fault     = document.getElementById('na-cat-fault');
        var problems  = catalogue.problems || [];
        if (!catalogue.ok) {
            fault.textContent = catalogue.message || 'The library could not be read.';
        } else if (problems.length) {
            fault.textContent = problems.length + (problems.length === 1 ? ' problem' : ' problems') + ' reading the library. First: ' + problems[0];
        }
        fault.classList.toggle('na-hidden', catalogue.ok && !problems.length);

        var found = na_search();
        Shell.na_text('na-cat-count', found.length === (catalogue.assets || []).length ? (catalogue.assets || []).length + ' in the library' : found.length + ' of ' + (catalogue.assets || []).length);
        if (!found.length) {
            grid.appendChild(Shell.na_el('p', 'na-cat-empty', catalogue.ok ? 'Nothing in the library matches.' : 'No catalogue to show.'));
            return;
        }
        found.forEach(function (asset) { grid.appendChild(na_card(asset)); });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Chosen Asset
    // -------------------------------------------------------------------------

    function na_detail_row(label, value) {
        var row = Shell.na_el('div', 'na-detail__row');
        row.appendChild(Shell.na_el('span', 'na-detail__label', label));
        row.appendChild(Shell.na_el('span', 'na-detail__value', value));
        return row;
    }

    // FUNCTION | The Detail Panel Under the Grid
    function na_render_detail() {
        var panel = document.getElementById('na-cat-detail');
        var asset = Ui.Selected ? na_find(Ui.Selected) : null;
        panel.classList.toggle('na-hidden', !asset);
        Shell.na_clear(panel);
        if (!asset) return;

        var picture = Shell.na_el('div', 'na-detail__picture');
        var url     = na_picture_url(asset);
        if (url) {
            var img = document.createElement('img');
            img.src = url;
            img.alt = asset.DisplayName;
            picture.appendChild(img);
        } else {
            picture.classList.add('na-detail__picture--none');
            picture.textContent = 'No picture yet';
        }

        var body  = Shell.na_el('div', 'na-detail__body');
        var title = Shell.na_el('div', 'na-detail__title');
        title.appendChild(Shell.na_el('span', 'na-detail__name', asset.DisplayName));
        title.appendChild(Shell.na_el('span', 'na-detail__id', asset.AssetId + '  ' + asset.CollectionName + ' \u203a ' + Shell.na_split_camel(asset.Type) + '  ' + asset.Variant));
        body.appendChild(title);
        if (asset.Description) body.appendChild(Shell.na_el('p', 'na-detail__description', asset.Description));

        var files = Shell.na_el('div', 'na-detail__files');
        SLOTS.forEach(function (slot) {
            var state = asset.Files && asset.Files[slot];
            var chip  = Shell.na_el('span', 'na-file ' + (state && state.Present ? 'na-file--present' : 'na-file--pending'), slot);
            chip.title = state ? (state.File + (state.Present ? ' (' + Math.round((state.Bytes || 0) / 1024) + ' KB)' : ' (not written yet)')) : slot + ' is not named in the DAT';
            files.appendChild(chip);
        });
        body.appendChild(files);

        var recipe = [asset.Generator && asset.Generator + ' generator', asset.Kind && asset.Kind + ' kind', asset.Material && asset.Material + ' material',
                      asset.Role && asset.Role + ' role'].filter(Boolean).join(', ');
        body.appendChild(na_detail_row('Drawn as', recipe ? recipe + (asset.Source ? ' (' + asset.Source + ')' : '') : 'not stated'));
        var size = [Shell.na_format_height(asset.NominalHeightM) && 'height ' + Shell.na_format_height(asset.NominalHeightM),
                    Shell.na_format_height(asset.NominalSpreadM) && 'spread ' + Shell.na_format_height(asset.NominalSpreadM)].filter(Boolean).join(', ');
        if (size) body.appendChild(na_detail_row('Size', size));
        if (asset.Botanical) body.appendChild(na_detail_row('Botanical', asset.Botanical));
        if ((asset.Keywords || []).length) body.appendChild(na_detail_row('Keywords', asset.Keywords.join(', ')));

        var actions = Shell.na_el('div', 'na-detail__actions');
        var place   = Shell.na_el('button', 'naButton', 'Place in Model');
        place.type  = 'button';
        place.title = asset.InModel ? 'Already in this model: place another copy' : (asset.Files.SKP && asset.Files.SKP.Present ? 'Loads its SKP, then click in the model' : 'Builds its proxy from the MOD (no SKP yet), then click in the model');
        place.addEventListener('click', function () { na_place(asset.AssetId); });
        actions.appendChild(place);

        var skp = asset.Files && asset.Files.SKP;
        var mod = asset.Files && asset.Files.MOD;
        if (skp && !skp.Present && mod && mod.Present) {
            var write = Shell.na_el('button', 'naButtonSecondary', 'Write SKP');
            write.type  = 'button';
            write.title = 'Saves the MOD proxy as this asset\'s SKP (' + skp.File + ') and marks its DAT, then validates the library';
            write.setAttribute('data-na-needs-idle', '');
            write.addEventListener('click', function () {
                Bridge.na_call_after_paint('writeSkp', { assetId: asset.AssetId }, 'Writing the SKP', asset.DisplayName + ': building the proxy and saving it into its folder...');
            });
            actions.appendChild(write);
        }

        var folder = Shell.na_el('button', 'naButtonSecondary', 'Open Folder');
        folder.type = 'button';
        folder.addEventListener('click', function () { Bridge.na_call('openFolder', { assetId: asset.AssetId }); });
        actions.appendChild(folder);
        body.appendChild(actions);

        panel.appendChild(picture);
        panel.appendChild(body);
    }

    function na_place(assetId) {
        var asset = na_find(assetId);
        if (!asset) return;
        var status = asset.InModel ? 'It is in this model already.' : (asset.Files.SKP && asset.Files.SKP.Present ? 'Loading its SKP...' : 'Building its proxy from the MOD...');
        Bridge.na_call_after_paint('place', { assetId: assetId }, 'Getting ' + asset.DisplayName + ' ready', status);
    }

    function na_render_all() {
        na_render_filters();
        na_render_cards();
        na_render_detail();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        document.getElementById('na-cat-search').addEventListener('input', function (event) {
            Ui.Query = event.target.value;
            na_render_cards();
        });
        document.getElementById('na-cat-collections').addEventListener('click', function (event) {
            var chip = event.target.closest('[data-collection]');
            if (!chip) return;
            Ui.Collection = chip.getAttribute('data-collection');
            Ui.Type = '';
            na_render_filters();
            na_render_cards();
        });
        document.getElementById('na-cat-types').addEventListener('click', function (event) {
            var chip = event.target.closest('[data-type]');
            if (!chip) return;
            Ui.Type = chip.getAttribute('data-type');
            na_render_filters();
            na_render_cards();
        });
        Array.prototype.forEach.call(document.querySelectorAll('[data-na-thumbs]'), function (button) {
            button.addEventListener('click', function () {
                Ui.Thumbs = button.getAttribute('data-na-thumbs');
                Bridge.na_call('setPref', { key: 'thumbs', value: Ui.Thumbs });
                na_render_cards();
                na_render_detail();
            });
        });
        var grid = document.getElementById('na-cat-grid');
        grid.addEventListener('click', function (event) {
            var card = event.target.closest('[data-asset-id]');
            if (!card) return;
            Ui.Selected = card.getAttribute('data-asset-id');
            Array.prototype.forEach.call(grid.querySelectorAll('.na-asset-card'), function (c) {
                c.classList.toggle('na-asset-card--selected', c === card);
            });
            na_render_detail();
        });
        grid.addEventListener('dblclick', function (event) {
            var card = event.target.closest('[data-asset-id]');
            if (card) na_place(card.getAttribute('data-asset-id'));
        });
        document.getElementById('na-cat-refresh').addEventListener('click', function () {
            Bridge.na_call('refresh', {});
        });
        document.getElementById('na-cat-write-missing').addEventListener('click', function () {
            var missing = (na_catalogue().assets || []).filter(function (a) { return a.Files.SKP && !a.Files.SKP.Present && a.Files.MOD && a.Files.MOD.Present; });
            if (!missing.length) { Shell.na_set_status('Every asset with a MOD already has its SKP.', 'info'); return; }
            Shell.na_confirm({
                title   : 'Write ' + missing.length + ' missing SKP files?',
                text    : 'Each asset\'s proxy is built from its MOD, saved into its own folder in the library as its SKP, and its DAT marked SKP Present; then PainterlyNPR validates the library. ' +
                          'The proxies are built into this model and stay in its component list (purge them if unused), so a new, empty model is the place to do it.',
                confirm : 'Write ' + missing.length + ' SKPs'
            }, function () {
                Bridge.na_call_after_paint('writeMissingSkps', {}, 'Writing ' + missing.length + ' SKPs', 'Building each proxy and saving it into the library...');
            });
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Subscriptions
    // -------------------------------------------------------------------------

    Shell.na_on('state', function (state) {
        if (state && state.prefs && (state.prefs.thumbs === 'RND' || state.prefs.thumbs === 'PXY')) Ui.Thumbs = state.prefs.thumbs;
        if (Ui.Selected && !na_find(Ui.Selected)) Ui.Selected = null;
        na_render_all();
    });
    Shell.na_on('catalogue', function () {
        if (Ui.Selected && !na_find(Ui.Selected)) Ui.Selected = null;
        na_render_all();
    });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PainterlyAssets__CatalogueUi = { na_render_all: na_render_all };
})();

// =============================================================================
// END OF FILE
// =============================================================================
