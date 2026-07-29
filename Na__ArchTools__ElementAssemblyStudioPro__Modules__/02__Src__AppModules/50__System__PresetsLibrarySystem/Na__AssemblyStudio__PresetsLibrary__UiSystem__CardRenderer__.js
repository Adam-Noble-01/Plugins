// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY - CARD RENDERER
// =============================================================================
//
// FILE       : Na__AssemblyStudio__PresetsLibrary__UiSystem__CardRenderer__.js
// NAMESPACE  : window.Na__PresetsLibrary__CardRenderer
// MODULE     : Presets Library System
// AUTHOR     : Noble Architecture
// CREATED    : 2026
// PURPOSE    : Stateless DOM builders for the Presets Gallery: preset cards,
//              index table rows, stored-SVG thumbnails, and the shared
//              filter/sort pipeline used by both gallery presentations.
//
// DESCRIPTION:
// - Pure helpers only - no module state, no event wiring beyond per-element
//   click handlers supplied by the caller via a handlers object.
// - All record text lands in the DOM via textContent (never interpolated
//   innerHTML); na_escape_html is exported for callers composing markup.
// - SVG thumbnails rebuild a detached <svg> from the preset's stored viewBox
//   plus inner markup (markup is persisted without an outer <svg> tag).
//
// NAMING CONVENTION:
// - Aggregate Na__PresetsLibrary__CardRenderer + na_* internal helpers.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module Constants
// -----------------------------------------------------------------------------

    var Na__PresetsLibrary__CardRenderer = {};
    var NA_SVG_NAMESPACE                 = 'http://www.w3.org/2000/svg';

    var NA_FAMILY_LABELS = {
        Window       : 'Window',
        ExteriorDoor : 'Exterior Door',
        InteriorDoor : 'Interior Door'
    };

    var NA_FAMILY_CHIP_MODIFIERS = {
        Window       : 'na-preset-card__chip--window',
        ExteriorDoor : 'na-preset-card__chip--exteriordoor',
        InteriorDoor : 'na-preset-card__chip--interiordoor'
    };

    var NA_INDEX_COLUMN_HEADINGS = ['Preview', 'Code', 'Name', 'Family', 'Type', 'Keywords', 'Description', ''];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Text Helpers
// -----------------------------------------------------------------------------

    // FUNCTION | Escape a string for safe inclusion in HTML markup
    // ------------------------------------------------------------
    // @param  {*} text - Raw value; null/undefined coerce to ''.
    // @return {String} Entity-escaped text.
    function na_escape_html(text) {
        return String(text === null || text === undefined ? '' : text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Human family label for a productFamily key
    // ------------------------------------------------------------
    // @param  {String} productFamily - 'Window' | 'ExteriorDoor' | 'InteriorDoor'.
    // @return {String} Display label (falls back to the raw key).
    function na_family_label(productFamily) {
        return NA_FAMILY_LABELS[productFamily] || String(productFamily || '');
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Filter & Sort Pipeline
// -----------------------------------------------------------------------------

    // FUNCTION | Test one record against the free-text search term
    // ------------------------------------------------------------
    // @param  {Object} record - Preset record (bridge shape).
    // @param  {String} term   - Lower-cased, trimmed search term.
    // @return {Boolean} True when any searchable field contains the term.
    function na_record_matches_term(record, term) {
        if (!term) return true;
        var keywords = record.keywords || [];
        for (var i = 0; i < keywords.length; i++) {
            if (String(keywords[i]).toLowerCase().indexOf(term) !== -1) return true;
        }
        return String(record.presetCode  || '').toLowerCase().indexOf(term) !== -1 ||
               String(record.displayName || '').toLowerCase().indexOf(term) !== -1 ||
               String(record.description || '').toLowerCase().indexOf(term) !== -1 ||
               String(record.productType || '').toLowerCase().indexOf(term) !== -1;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Relevance score for ranking (keyword=2, name=1, other=0)
    // ------------------------------------------------------------
    // @param  {Object} record - Preset record.
    // @param  {String} term   - Lower-cased, trimmed search term.
    // @return {Number} 2 keyword hit, 1 name hit, 0 otherwise.
    function na_score_record(record, term) {
        if (!term) return 0;
        var keywords = record.keywords || [];
        for (var i = 0; i < keywords.length; i++) {
            if (String(keywords[i]).toLowerCase().indexOf(term) !== -1) return 2;
        }
        if (String(record.displayName || '').toLowerCase().indexOf(term) !== -1) return 1;
        return 0;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Filter records by term + family, rank, and sort
    // ------------------------------------------------------------
    // @param  {Array}  records      - Preset records from the bridge cache.
    // @param  {String} searchTerm   - Raw search input (any case, may be '').
    // @param  {String} familyFilter - '' (all) or exact productFamily value.
    // @return {Array} New array: score desc, then presetCode asc.
    function na_filter_and_sort(records, searchTerm, familyFilter) {
        var term   = String(searchTerm || '').toLowerCase().trim();
        var family = String(familyFilter || '');
        var scored = [];

        (records || []).forEach(function (record) {
            if (!record) return;
            if (family && String(record.productFamily || '') !== family) return;
            if (!na_record_matches_term(record, term)) return;
            scored.push({ record: record, score: na_score_record(record, term) });
        });

        scored.sort(function (a, b) {
            if (b.score !== a.score) return b.score - a.score;
            var codeA = String(a.record.presetCode || '');
            var codeB = String(b.record.presetCode || '');
            if (codeA === codeB) return 0;
            return (codeA < codeB) ? -1 : 1;
        });

        return scored.map(function (entry) { return entry.record; });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | SVG Preview Builder
// -----------------------------------------------------------------------------

    // FUNCTION | Rebuild a stored preview as a detached <svg> element
    // ------------------------------------------------------------
    // @param  {Object} svgPreview - { viewBox, widthMm, heightMm, svgMarkup }.
    // @return {SVGElement} Thumbnail svg (empty when no markup stored).
    function na_build_preview_svg(svgPreview) {
        var preview = svgPreview || {};
        var svg     = document.createElementNS(NA_SVG_NAMESPACE, 'svg');
        svg.setAttribute('class', 'na-preset-card__thumb-svg');
        svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
        if (preview.viewBox) svg.setAttribute('viewBox', String(preview.viewBox));
        svg.innerHTML = String(preview.svgMarkup || '');
        return svg;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Card Builder (Grid View)
// -----------------------------------------------------------------------------

    // FUNCTION | Compose the chip/code metadata strip for one record
    // ------------------------------------------------------------
    // @param  {Object} record - Preset record.
    // @return {HTMLElement} div.na-preset-card__meta with chips + code.
    function na_build_card_meta(record) {
        var meta = document.createElement('div');
        meta.className = 'na-preset-card__meta';

        var familyChip       = document.createElement('span');
        var familyModifier   = NA_FAMILY_CHIP_MODIFIERS[record.productFamily] || '';
        familyChip.className = 'na-preset-card__chip' + (familyModifier ? ' ' + familyModifier : '');
        familyChip.textContent = na_family_label(record.productFamily);
        familyChip.title       = 'Product family: ' + na_family_label(record.productFamily);
        meta.appendChild(familyChip);

        if (record.productType) {
            var typeChip = document.createElement('span');
            typeChip.className   = 'na-preset-card__chip';
            typeChip.textContent = String(record.productType);
            typeChip.title       = 'Product type: ' + String(record.productType);
            meta.appendChild(typeChip);
        }

        var code = document.createElement('span');
        code.className   = 'na-preset-card__code';
        code.textContent = String(record.presetCode || '');
        meta.appendChild(code);

        return meta;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build one clickable gallery card for a preset record
    // ------------------------------------------------------------
    // @param  {Object} record   - Preset record (bridge shape).
    // @param  {Object} handlers - { onApply(record), onEdit(record) }.
    // @return {HTMLElement} div.na-preset-card ready to append.
    function na_build_card(record, handlers) {
        var callbacks = handlers || {};

        var card = document.createElement('div');
        card.className = 'na-preset-card';
        card.title     = 'Click to apply: ' + String(record.displayName || record.presetCode || '');

        var thumb = document.createElement('div');
        thumb.className = 'na-preset-card__thumb';
        thumb.appendChild(na_build_preview_svg(record.svgPreview));

        var editButton = document.createElement('button');
        editButton.type        = 'button';
        editButton.className   = 'na-preset-card__edit';
        editButton.textContent = '✎';
        editButton.title       = 'Edit preset metadata';
        editButton.addEventListener('click', function (event) {
            event.stopPropagation();
            if (typeof callbacks.onEdit === 'function') callbacks.onEdit(record);
        });
        thumb.appendChild(editButton);

        var info = document.createElement('div');
        info.className = 'na-preset-card__info';

        var name = document.createElement('div');
        name.className   = 'na-preset-card__name';
        name.textContent = String(record.displayName || '');
        name.title       = String(record.displayName || '');

        info.appendChild(name);
        info.appendChild(na_build_card_meta(record));

        card.appendChild(thumb);
        card.appendChild(info);

        card.addEventListener('click', function () {
            if (typeof callbacks.onApply === 'function') callbacks.onApply(record);
        });

        return card;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Index Table Builder (Index View)
// -----------------------------------------------------------------------------

    // FUNCTION | One plain-text table cell with optional modifier class
    // ------------------------------------------------------------
    // @param  {String} text     - Cell text (set via textContent).
    // @param  {String} modifier - Optional extra class ('' for none).
    // @return {HTMLElement} td.na-presets-index__cell.
    function na_build_index_cell(text, modifier) {
        var cell = document.createElement('td');
        cell.className   = 'na-presets-index__cell' + (modifier ? ' ' + modifier : '');
        cell.textContent = String(text === null || text === undefined ? '' : text);
        return cell;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build one clickable index row for a preset record
    // ------------------------------------------------------------
    // @param  {Object} record    - Preset record.
    // @param  {Object} callbacks - { onApply(record), onEdit(record) }.
    // @return {HTMLElement} tr.na-presets-index__row.
    function na_build_index_row(record, callbacks) {
        var row = document.createElement('tr');
        row.className = 'na-presets-index__row';
        row.title     = 'Click to apply: ' + String(record.displayName || record.presetCode || '');

        var previewCell = document.createElement('td');
        previewCell.className = 'na-presets-index__cell na-presets-index__cell--preview';
        var previewWrap = document.createElement('div');
        previewWrap.className = 'na-presets-index__thumb';
        previewWrap.appendChild(na_build_preview_svg(record.svgPreview));
        previewCell.appendChild(previewWrap);
        row.appendChild(previewCell);

        row.appendChild(na_build_index_cell(record.presetCode,  'na-presets-index__cell--code'));
        row.appendChild(na_build_index_cell(record.displayName, 'na-presets-index__cell--name'));
        row.appendChild(na_build_index_cell(na_family_label(record.productFamily), ''));
        row.appendChild(na_build_index_cell(record.productType, ''));
        row.appendChild(na_build_index_cell((record.keywords || []).join(', '), ''));
        row.appendChild(na_build_index_cell(record.description, 'na-presets-index__cell--description'));

        var actionsCell = document.createElement('td');
        actionsCell.className = 'na-presets-index__cell na-presets-index__cell--actions';
        var editButton = document.createElement('button');
        editButton.type        = 'button';
        editButton.className   = 'na-btn na-btn-small na-presets-index__edit-btn';
        editButton.textContent = 'Edit';
        editButton.title       = 'Edit preset metadata';
        editButton.addEventListener('click', function (event) {
            event.stopPropagation();
            if (typeof callbacks.onEdit === 'function') callbacks.onEdit(record);
        });
        actionsCell.appendChild(editButton);
        row.appendChild(actionsCell);

        row.addEventListener('click', function () {
            if (typeof callbacks.onApply === 'function') callbacks.onApply(record);
        });

        return row;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build the full index table for a filtered record set
    // ------------------------------------------------------------
    // @param  {Array}  records  - Filtered + sorted preset records.
    // @param  {Object} handlers - { onApply(record), onEdit(record) }.
    // @return {HTMLElement} table.na-presets-index__table.
    function na_build_index_table(records, handlers) {
        var callbacks = handlers || {};

        var table = document.createElement('table');
        table.className = 'na-presets-index__table';

        var thead     = document.createElement('thead');
        var headerRow = document.createElement('tr');
        NA_INDEX_COLUMN_HEADINGS.forEach(function (heading) {
            var th = document.createElement('th');
            th.className   = 'na-presets-index__heading';
            th.textContent = heading;
            headerRow.appendChild(th);
        });
        thead.appendChild(headerRow);
        table.appendChild(thead);

        var tbody = document.createElement('tbody');
        (records || []).forEach(function (record) {
            if (record) tbody.appendChild(na_build_index_row(record, callbacks));
        });
        table.appendChild(tbody);

        return table;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API
// -----------------------------------------------------------------------------

    Na__PresetsLibrary__CardRenderer.na_escape_html       = na_escape_html;
    Na__PresetsLibrary__CardRenderer.na_filter_and_sort   = na_filter_and_sort;
    Na__PresetsLibrary__CardRenderer.na_build_preview_svg = na_build_preview_svg;
    Na__PresetsLibrary__CardRenderer.na_build_card        = na_build_card;
    Na__PresetsLibrary__CardRenderer.na_build_index_table = na_build_index_table;

    window.Na__PresetsLibrary__CardRenderer = Na__PresetsLibrary__CardRenderer;

    console.log('[NA_PRESET_CARDS] Presets Library card renderer ready');

// endregion -------------------------------------------------------------------

})();
