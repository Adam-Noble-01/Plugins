/* =============================================================================
   NA PROFILE TOOLS - GALLERY MODE - UI SYSTEM - CARD RENDERER
   =============================================================================
   FILE       : Na__ProfileTools__Gallery__UiSystem__CardRenderer__.js
   NAMESPACE  : window.Na__ProfileTools__Gallery__CardRenderer
   PURPOSE    : Build individual profile card HTML and provide keyword-prioritised
                filtering / sorting for the gallery grid.
   ============================================================================= */

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | SVG Thumbnail Builder
    // -------------------------------------------------------------------------

    function Na__Card__BuildSvgThumb(record) {
        var svgGen = window.Na__ProfilePathTracer__Viewport__SvgGenerator;
        if (!svgGen || !record) {
            return '<div class="na-gallery-card__thumb-empty"></div>';
        }

        var result = svgGen.Na__Svg__GenerateProfile(record, { toggleStates: {}, rotationStep: 0, thumbnailMode: true });
        if (!result || !result.isValid) {
            return '<div class="na-gallery-card__thumb-empty"></div>';
        }

        return [
            '<svg class="na-gallery-card__svg" viewBox="' + (result.viewBox || '-120 -120 240 240') + '"',
            '     xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet">',
            result.svg,
            '</svg>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Keyword Chips Builder
    // -------------------------------------------------------------------------

    function Na__Card__BuildKeywordChips(keywords) {
        if (!Array.isArray(keywords) || keywords.length === 0) return '';
        var chips = keywords.slice(0, 4).map(function (kw) {
            return '<span class="na-gallery-card__chip">' + Na__Card__EscapeHtml(kw) + '</span>';
        }).join('');
        return '<div class="na-gallery-card__chips">' + chips + '</div>';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | HTML Escape
    // -------------------------------------------------------------------------

    function Na__Card__EscapeHtml(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Single Card Builder
    // -------------------------------------------------------------------------

    function Na__Card__Build(record, isSelected) {
        if (!record) return '';

        var store    = window.Na__ProfileTools__ProfileStore;
        var keywords = store ? store.Na__Store__ProfileKeywords(record) : [];
        var name     = Na__Card__EscapeHtml(record.displayName || record.profileKey || '');
        var category = Na__Card__EscapeHtml(record.category || '');
        var key      = Na__Card__EscapeHtml(record.profileKey || '');
        var selectedClass = isSelected ? ' na-gallery-card--selected' : '';
        var tooltip       = Na__Card__EscapeHtml(record.displayName || record.profileKey || '');

        return [
            '<div class="na-gallery-card' + selectedClass + '" data-na-profile-key="' + key + '" data-tooltip="' + tooltip + '">',
            '  <div class="na-gallery-card__thumb">',
            Na__Card__BuildSvgThumb(record),
            '  </div>',
            '  <div class="na-gallery-card__meta">',
            '    <div class="na-gallery-card__name">' + name + '</div>',
            category ? '    <div class="na-gallery-card__category">' + category + '</div>' : '',
            Na__Card__BuildKeywordChips(keywords),
            '  </div>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Filter + Sort
    // -------------------------------------------------------------------------

    function Na__Card__FilterAndSort(profiles, query) {
        var keys   = Object.keys(profiles);
        var term   = (query || '').toLowerCase().trim();

        if (!term) {
            return keys.map(function (k) { return { key: k, record: profiles[k], score: 0 }; });
        }

        var store = window.Na__ProfileTools__ProfileStore;
        var results = [];

        keys.forEach(function (k) {
            var record   = profiles[k];
            var name     = (record.displayName || record.profileKey || '').toLowerCase();
            var category = (record.category || '').toLowerCase();
            var keywords = store ? store.Na__Store__ProfileKeywords(record) : [];
            var kwLower  = keywords.map(function (kw) { return String(kw).toLowerCase(); });

            var keywordMatch = kwLower.some(function (kw) { return kw.indexOf(term) !== -1; });
            var nameMatch    = name.indexOf(term) !== -1;
            var catMatch     = category.indexOf(term) !== -1;

            if (!keywordMatch && !nameMatch && !catMatch) return;

            var score = keywordMatch ? 2 : (nameMatch ? 1 : 0);
            results.push({ key: k, record: record, score: score });
        });

        results.sort(function (a, b) { return b.score - a.score; });
        return results;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__Gallery__CardRenderer = {
        Na__Card__Build:          Na__Card__Build,
        Na__Card__FilterAndSort:  Na__Card__FilterAndSort
    };

    // endregion ----------------------------------------------------------------
})();
