/* =============================================================================
   NA PROFILE TOOLS - GALLERY MODE - UI SYSTEM - CARD RENDERER
   =============================================================================
   FILE       : Na__ProfileTools__Gallery__UiSystem__CardRenderer__.js
   NAMESPACE  : window.Na__ProfileTools__Gallery__CardRenderer
   PURPOSE    : Build individual profile card HTML and provide keyword-prioritised
                filtering / sorting for the gallery grid.

   CARD CONTRACT
                A card shows a thumbnail, one title, and every keyword — and it
                clips none of them. The title is the profile's short name alias
                where one is set and its full authored name otherwise, because a
                library name is a 60-character __-joined string that reads as
                noise at any card width. Only an aliased card carries a tooltip,
                since it is the only card not already showing the full name.

                The asset type line is deliberately absent: every profile in the
                library is a Profile2D, so it cost a row of every card to say
                nothing that distinguished one card from the next.

   ONE CARD, TWO VIEWS
                The same markup serves both Gallery and Index — the stylesheet
                decides what each view shows, and Gallery hides the keyword chips
                rather than this file omitting them. That is what lets the mode
                switch be a class swap on the grid instead of a full re-render
                that would rebuild every SVG thumbnail to change nothing.
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

    // Every keyword, not the first four. The chips are how a profile is found by
    // eye, so a silent cap hid exactly the detail the Index view exists to show;
    // the grid absorbs the extra height by growing the row. Gallery hides the
    // whole block in CSS — see ONE CARD, TWO VIEWS above.
    function Na__Card__BuildKeywordChips(keywords) {
        if (!Array.isArray(keywords) || keywords.length === 0) return '';
        var chips = keywords.map(function (kw) {
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
    // REGION | Soft Break Hints
    // -------------------------------------------------------------------------

    // A full library name is one unbroken token — Vale__InteriorTrim__Standard__
    // ClassicInternalCornice__VG103__w150mm__ — so the browser has no legal wrap
    // point in it and CSS is left breaking mid-word at whatever column runs out.
    // A <wbr> after each underscore run gives it the separators to break on, so
    // the name stacks by segment and stays readable. Runs on ALREADY-ESCAPED
    // text: the markup it adds is the point, so it must not be escaped away.
    function Na__Card__AddSoftBreaks(escapedText) {
        return String(escapedText || '').replace(/(_+)/g, '$1<wbr>');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Single Card Builder
    // -------------------------------------------------------------------------

    function Na__Card__Build(record, isSelected) {
        if (!record) return '';

        var store     = window.Na__ProfileTools__ProfileStore;
        var keywords  = store ? store.Na__Store__ProfileKeywords(record)  : [];
        var shortName = store ? store.Na__Store__ProfileShortName(record) : '';
        var fullName  = String(record.displayName || record.profileKey || '');
        // The store owns the alias-or-full-name rule; the alias is read here only
        // to decide whether the card is hiding anything worth a tooltip.
        var label     = store ? store.Na__Store__ProfileLabel(record) : fullName;
        var title     = Na__Card__AddSoftBreaks(Na__Card__EscapeHtml(label));
        var key       = Na__Card__EscapeHtml(record.profileKey || '');

        var selectedClass = isSelected ? ' na-gallery-card--selected' : '';

        // Only an aliased card is hiding anything. On an un-aliased card the
        // tooltip would restate the title while covering the chips underneath it.
        var isAliased   = !!(shortName && fullName && shortName !== fullName);
        var tooltipAttr = isAliased
            ? ' data-tooltip="' + Na__Card__EscapeHtml(fullName) + '"'
            : '';

        return [
            '<div class="na-gallery-card' + selectedClass + '" data-na-profile-key="' + key + '"' + tooltipAttr + '>',
            '  <div class="na-gallery-card__thumb">',
            Na__Card__BuildSvgThumb(record),
            '  </div>',
            '  <div class="na-gallery-card__meta">',
            '    <div class="na-gallery-card__name">' + title + '</div>',
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
            // The alias is what the card is TITLED by, so typing what is on
            // screen has to find the card that shows it.
            var alias    = (store ? store.Na__Store__ProfileShortName(record) : '').toLowerCase();
            var category = (record.category || '').toLowerCase();
            var keywords = store ? store.Na__Store__ProfileKeywords(record) : [];
            var kwLower  = keywords.map(function (kw) { return String(kw).toLowerCase(); });

            var keywordMatch = kwLower.some(function (kw) { return kw.indexOf(term) !== -1; });
            var aliasMatch   = alias !== '' && alias.indexOf(term) !== -1;
            var nameMatch    = name.indexOf(term) !== -1;
            var catMatch     = category.indexOf(term) !== -1;

            if (!keywordMatch && !aliasMatch && !nameMatch && !catMatch) return;

            var score = keywordMatch ? 2 : ((aliasMatch || nameMatch) ? 1 : 0);
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
