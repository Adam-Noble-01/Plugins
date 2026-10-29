/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - SHARED PARAMETER SEARCH
   =============================================================================
   FILE       : Na__AssemblyStudio__AppCore__UiSystem__ParameterSearch__.js
   NAMESPACE  : window.Na__Ui__ParameterSearch
   AUTHOR     : Noble Architecture
   PURPOSE    : The search box above each configurator tab. Finds any
                parameter, nested ones included, by its label, its config key,
                its section or a trade synonym ("sill" finds Cill, "muntin"
                finds the glaze bars), and lends the real control into the
                result so it can be edited there. "Show in Panel" opens the
                section and tier it lives in and scrolls to it. The Changed
                chip lists every setting that differs from its default.
   CREATED    : 28-Oct-2026

   KEYS
   - Ctrl+F focuses the active tab's search. Up / Down move through the
     results, Enter shows the highlighted one in the panel, Esc clears.
   - No single-letter shortcuts: SketchUp takes those before the dialog.

   DEPENDS ON
   - Na__AssemblyStudio__AppCore__UiSystem__SectionLayout__.js (items, paths,
     lending, revealing). Each tab's layout spec supplies the DOM ids
     (searchInputId, changedChipId, resultsHostId, sectionsHostId, previewId)
     and setValue / defaultOf for the fixes and resets.
   ============================================================================= */

const Na__Ui__ParameterSearch = (function () {
    'use strict';

    // -----------------------------------------------------------------------------
    // REGION | Constants and Module State
    // -----------------------------------------------------------------------------

    const NA_MAX_RESULTS  = 40;
    const NA_SCORE_FLOOR  = 0.3;                                               // <-- Drop matches weaker than 30% of the best one

    // Trade words and spellings people type, mapped to the words the labels
    // and keyword lists actually use.
    const NA_SYNONYMS = {
        sill        : ['cill'],
        threshold   : ['cill'],
        color       : ['colour', 'finish'],
        colour      : ['finish', 'edge'],
        paint       : ['finish', 'paint'],
        material    : ['finish'],
        muntin      : ['bars'],
        astragal    : ['bars'],
        georgian    : ['bars'],
        grid        : ['bars'],
        bar         : ['bars'],
        fanlight    : ['transom'],
        toplight    : ['transom'],
        divider     : ['mullion', 'transom'],
        bifold      : ['fold'],
        folding     : ['fold'],
        slide       : ['sliding', 'slide'],
        hinge       : ['hinge', 'swing'],
        handing     : ['swing side'],
        hand        : ['swing side'],
        ironmongery : ['handle'],
        hardware    : ['handle'],
        lever       : ['handle'],
        merge       : ['fuse'],
        weld        : ['fuse'],
        solid       : ['fuse'],
        lead        : ['lead', 'leaded'],
        came        : ['lead'],
        arch        : ['arch', 'gothic'],
        arches      : ['arch'],
        lancet      : ['gothic'],
        reveal      : ['reveal', 'inset'],
        recess      : ['inset'],
        setback     : ['inset'],
        offset      : ['offset'],
        nudge       : ['offset'],
        horn        : ['horn'],
        horns       : ['horn'],
        glass       : ['glazing', 'glazed'],
        glazing     : ['glass', 'glazed'],
        panel       : ['fielded', 'panel'],
        thickness   : ['thickness', 'depth', 'width'],
        frameless   : ['frame thickness'],
        sash        : ['casement', 'sash'],
        casement    : ['casement', 'sash'],
        door        : ['leaf'],
        leaves      : ['leaf'],
        dims        : ['dimensions'],
        dimension   : ['dimensions'],
        midrail     : ['midrail', 'mid rail', 'mid_rail'],
        kick        : ['bottom rail', 'base rail'],
        head        : ['top rail', 'head'],
        jamb        : ['lining', 'frame'],
        lining      : ['lining'],
        wall        : ['wall', 'reveal'],
        opening     : ['opening', 'width', 'height'],
        size        : ['width', 'height'],
        // Cabinetry (kitchens and fitted wardrobes)
        kickboard   : ['plinth'],
        baseboard   : ['plinth'],
        skirting    : ['plinth'],
        toe         : ['plinth'],
        feet        : ['legs', 'leg'],
        foot        : ['legs', 'leg'],
        carcase     : ['carcass'],
        cupboard    : ['door', 'unit'],
        larder      : ['split', 'larder'],
        pantry      : ['split', 'larder'],
        handleless  : ['recessed', 'groove'],
        gola        : ['recessed', 'groove'],
        jpull       : ['groove'],
        slab        : ['flat'],
        stretcher   : ['rail'],
        crossbar    : ['rail'],
        mfc         : ['board'],
        melamine    : ['board'],
        chipboard   : ['board'],
        mdf         : ['board'],
        hangers     : ['hanging'],
        clothes     : ['hanging'],
        pan         : ['drawers'],
        drawerline  : ['drawer']
    };

    const na_states = {};                                                      // <-- tabId -> { query, changedOnly, active, cards }

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | The Shared Section Layout, Resolved Lazily
    // ------------------------------------------------------------
    function na_layout() {
        return window.Na__Ui__SectionLayout || null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Escape Text for Safe Insertion as HTML
    // ------------------------------------------------------------
    function na_escape(text) {
        return String(text == null ? '' : text).replace(/[&<>"']/g, ch => (
            { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]
        ));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Escape Text for Use Inside a Regular Expression
    // ------------------------------------------------------------
    function na_escape_regex(text) {
        return String(text).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Split a Query Into Lower-Case Terms
    // ------------------------------------------------------------
    function na_terms(query) {
        return String(query || '').toLowerCase().replace(/[^a-z0-9\s_-]/g, ' ').split(/\s+/).filter(Boolean);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Does a Phrase Start a Word Somewhere in the Text
    // ------------------------------------------------------------
    function na_word_start(haystack, phrase) {
        return (' ' + haystack).indexOf(' ' + phrase) !== -1;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Does a Short Term Appear as a Whole Word
    // ------------------------------------------------------------
    // "no" must find "no frame" in a hint, never the "no" in "nosing".
    function na_has_word(haystack, phrase) {
        return new RegExp('(^|[^a-z0-9])' + na_escape_regex(phrase) + '($|[^a-z0-9])').test(haystack);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Active Tab's Search State
    // ------------------------------------------------------------
    function na_state(tabId) {
        if (!na_states[tabId]) na_states[tabId] = { query: '', changedOnly: false, active: 0, cards: [] };
        return na_states[tabId];
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Scoring
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Build the Text Fields One Item Is Searched By
    // ------------------------------------------------------------
    function na_haystack(tabId, item, product) {
        const layout = na_layout();
        return {
            label   : layout.na_item_label(tabId, item.id).toLowerCase() + (item.side ? ' ' + item.side + ' leaf' : ''),
            keywords: String(item.kw || '').toLowerCase(),
            id      : String(item.id).toLowerCase(),
            path    : layout.na_item_path(tabId, item.id, product).toLowerCase(),
            hint    : item.need ? String(item.need.text || '').toLowerCase() : ''
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Score One Item Against Every Term (0 = No Match)
    // ------------------------------------------------------------
    // Every term must match somewhere. A label hit outranks a keyword hit,
    // which outranks a config-key, section or hint hit; a synonym counts a
    // little less than the word itself. Tier 1 items edge ahead of Tier 3.
    function na_score(tabId, item, terms, product) {
        const fields = na_haystack(tabId, item, product);
        let total = 0;
        for (let index = 0; index < terms.length; index += 1) {
            const term = terms[index];
            const alternatives = [[term, 1]].concat((NA_SYNONYMS[term] || []).map(alt => [alt, 0.8]));
            let best = 0;
            alternatives.forEach(pair => {
                const phrase = pair[0];
                let score = 0;
                if (phrase.length <= 2) {
                    if (na_has_word(fields.label, phrase)) score = 28;
                    else if (na_has_word(fields.keywords, phrase)) score = 14;
                    else if (na_has_word(fields.hint, phrase)) score = 3;
                }
                else if (fields.label.indexOf(phrase) === 0)                 score = 40;
                else if (na_word_start(fields.label, phrase))                score = 28;
                else if (fields.label.indexOf(phrase) !== -1)                score = 16;
                else if (na_word_start(fields.keywords, phrase))             score = 14;
                else if (fields.keywords.indexOf(phrase) !== -1)             score = 10;
                else if (fields.id.indexOf(phrase.replace(/\s+/g, '_')) !== -1) score = 8;
                else if (fields.path.indexOf(phrase) !== -1)                 score = 5;
                else if (fields.hint.indexOf(phrase) !== -1)                 score = 3;
                best = Math.max(best, score * pair[1]);
            });
            if (!best) return 0;
            total += best;
        }
        return total * (item.tier === 1 ? 1.15 : (item.tier === 3 ? 0.85 : 1));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Find Every Item Matching a Query, Best First
    // ------------------------------------------------------------
    // @return {Object} { here: [items for the active product], other: [items for other products] }
    function na_find(tabId, query) {
        const layout  = na_layout();
        const terms   = na_terms(query);
        const product = layout.na_get_product(tabId);
        const cfg     = layout.na_get_spec(tabId).getConfig() || {};
        const scored  = [];
        if (!terms.length) return { here: [], other: [] };

        layout.na_get_items(tabId).forEach(item => {
            if (item.nosearch || item.kind === 'picker') return;
            const here = layout.na_is_product_ok(tabId, item.id);
            if (here && item.pool && !layout.na_is_item_shown(tabId, item.id, cfg)) return;   // <-- Mullion 4 offset only once there are 4 mullions
            const score = na_score(tabId, item, terms, product);
            if (score > 0) scored.push({ item: item, score: score, here: here });
        });

        const top = scored.reduce((best, entry) => Math.max(best, entry.score), 0);
        const kept = scored
            .filter(entry => entry.score >= top * NA_SCORE_FLOOR)
            .sort((a, b) => (b.score - a.score) || (a.item.tier - b.item.tier));
        return {
            here : kept.filter(entry => entry.here).slice(0, NA_MAX_RESULTS).map(entry => entry.item),
            other: kept.filter(entry => !entry.here).map(entry => entry.item)
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Every Shown Setting That Differs From Its Default
    // ------------------------------------------------------------
    function na_find_changed(tabId) {
        const layout  = na_layout();
        const spec    = layout.na_get_spec(tabId);
        const cfg     = spec.getConfig() || {};
        const product = layout.na_get_product(tabId);
        return layout.na_get_items(tabId).filter(item =>
            !item.nosearch && item.kind !== 'picker' && item.kind !== 'block' &&
            layout.na_is_changed(tabId, item.id, cfg, product) &&
            layout.na_is_item_shown(tabId, item.id, cfg));
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Rendering
    // -----------------------------------------------------------------------------

    // FUNCTION | Re-Render a Tab's Results (or Restore Its Sections)
    // ------------------------------------------------------------
    function na_render(tabId) {
        const layout = na_layout();
        const spec   = layout && layout.na_get_spec(tabId);
        if (!spec || !layout.na_is_built(tabId)) return;
        const state  = na_state(tabId);
        const host   = document.getElementById(spec.resultsHostId);
        const sections = document.getElementById(spec.sectionsHostId);
        const preview  = spec.previewId ? document.getElementById(spec.previewId) : null;
        if (!host || !sections) return;

        na_unhighlight_all(tabId);
        layout.na_return_all(tabId);
        host.innerHTML = '';
        state.cards = [];

        const searching = !!state.query.trim() || state.changedOnly;
        host.hidden     = !searching;
        sections.hidden = searching;
        if (preview) preview.classList.toggle('na-lay-preview--hidden', searching);
        na_sync_chip(tabId);
        if (!searching) return;

        const found = state.changedOnly ? { here: na_find_changed(tabId), other: [] } : na_find(tabId, state.query);
        if (state.changedOnly && state.query.trim()) {
            const matching = na_find(tabId, state.query).here.map(item => item.id);
            found.here = found.here.filter(item => matching.indexOf(item.id) !== -1);
        }
        if (state.active >= found.here.length) state.active = Math.max(0, found.here.length - 1);

        host.appendChild(na_build_results_head(tabId, found.here));
        if (!found.here.length && !found.other.length) host.appendChild(na_build_empty_note(tabId));
        found.here.forEach((item, index) => host.appendChild(na_build_card(tabId, item, index)));
        if (found.other.length) host.appendChild(na_build_other_products(tabId, found.other));
        na_sync_cards(tabId);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Results Heading ("12 matches in Casement Window")
    // ------------------------------------------------------------
    function na_build_results_head(tabId, items) {
        const layout = na_layout();
        const spec   = layout.na_get_spec(tabId);
        const state  = na_state(tabId);
        const product = layout.na_get_product(tabId);
        const productName = spec.productName ? spec.productName(product) : '';
        const head = document.createElement('div');
        head.className = 'na-lay-res-head';

        if (state.changedOnly) {
            head.innerHTML = '<span><strong>' + items.length + '</strong> setting' + (items.length === 1 ? '' : 's') +
                ' changed from default' + (productName ? ' in ' + na_escape(productName) : '') + '</span>';
            if (items.length) {
                const resetAll = document.createElement('button');
                resetAll.type = 'button';
                resetAll.className = 'na-btn na-btn-small';
                resetAll.textContent = 'Reset All';
                resetAll.addEventListener('click', () => na_reset_items(tabId, items.map(item => item.id)));
                head.appendChild(resetAll);
            }
            return head;
        }
        head.innerHTML = '<span><strong>' + items.length + '</strong> match' + (items.length === 1 ? '' : 'es') +
            (productName ? ' in ' + na_escape(productName) : '') +
            '</span><span class="na-lay-res-head__keys">↑↓ to move · Enter to show in panel · Esc to clear</span>';
        return head;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Nothing Matched
    // ------------------------------------------------------------
    function na_build_empty_note(tabId) {
        const state = na_state(tabId);
        const note  = document.createElement('div');
        note.className = 'na-lay-res-empty';
        note.textContent = state.changedOnly
            ? 'Nothing changed: every setting is at its default.'
            : 'Nothing called "' + state.query.trim() + '". Try cill, horns, midrail, arch, hinge or reveal.';
        return note;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | One Result Card: Path, Key, Show Button, Live Control
    // ------------------------------------------------------------
    function na_build_card(tabId, item, index) {
        const layout  = na_layout();
        const state   = na_state(tabId);
        const product = layout.na_get_product(tabId);

        const card = document.createElement('div');
        card.className = 'na-lay-res';
        card.setAttribute('data-na-index', String(index));
        const top = document.createElement('div');
        top.className = 'na-lay-res__top';
        top.innerHTML = '<span class="na-lay-res__path">' + na_escape(layout.na_item_path(tabId, item.id, product)) + '</span>' +
                        '<code>' + na_escape(item.id) + '</code>';
        if (state.changedOnly) {
            const reset = document.createElement('button');
            reset.type = 'button';
            reset.className = 'na-lay-res__action';
            reset.textContent = 'Reset';
            reset.addEventListener('click', () => na_reset_items(tabId, [item.id]));
            top.appendChild(reset);
        }
        const show = document.createElement('button');
        show.type = 'button';
        show.className = 'na-lay-res__action';
        show.textContent = 'Show in Panel ↗';
        show.addEventListener('click', () => na_jump(tabId, item.id));
        top.appendChild(show);
        card.appendChild(top);

        const lent = layout.na_lend(tabId, item.id, card);
        if (lent) {
            na_highlight(lent, state.query);
        } else {
            const label = document.createElement('div');
            label.className = 'na-lay-res__label';
            label.innerHTML = na_highlight_text(layout.na_item_label(tabId, item.id), state.query);
            card.appendChild(label);
        }

        const need = document.createElement('div');
        need.className = 'na-lay-res__need';
        need.hidden = true;
        card.appendChild(need);

        card.addEventListener('mouseenter', () => { state.active = index; na_sync_active(tabId); });
        state.cards.push({ id: item.id, item: item, card: card, need: need });
        return card;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The "Other Products" Fold (Windows Tab)
    // ------------------------------------------------------------
    // One row per distinct label, so "Separating Midrail Width" is listed once
    // with every door type it applies to.
    function na_build_other_products(tabId, items) {
        const layout = na_layout();
        const spec   = layout.na_get_spec(tabId);
        const state  = na_state(tabId);
        const rows   = {};
        items.forEach(item => {
            const label = layout.na_item_label(tabId, item.id) + (item.side ? ' (' + item.side + ' leaf)' : '');
            if (!rows[label]) rows[label] = { label: label, item: item, products: [] };
            (item.products || []).forEach(product => {
                if (rows[label].products.indexOf(product) === -1) rows[label].products.push(product);
            });
        });

        const fold = document.createElement('details');
        fold.className = 'na-lay-res-other';
        fold.innerHTML = '<summary>Other products · ' + Object.keys(rows).length + '</summary>';
        Object.keys(rows).forEach(key => {
            const row = rows[key];
            const target = row.products[0];
            const line = document.createElement('div');
            line.className = 'na-lay-res-other__row';
            line.innerHTML = '<span>' + na_highlight_text(row.label, state.query) + '</span>' +
                row.products.map(product => '<span class="na-lay-pill">' + na_escape(spec.productName ? spec.productName(product) : product) + '</span>').join('');
            const go = document.createElement('button');
            go.type = 'button';
            go.textContent = 'Switch to ' + (spec.productName ? spec.productName(target) : target) + ' ↗';
            go.addEventListener('click', () => na_switch_and_jump(tabId, target, row.item.id));
            line.appendChild(go);
            fold.appendChild(line);
        });
        return fold;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Bring the Cards' Blocked State, Chip and Highlight Up to Date
    // ------------------------------------------------------------
    // Runs after every layout refresh, so a "Turn It On" fix or an edit made
    // inside a card is reflected without rebuilding the results.
    function na_sync_cards(tabId) {
        const layout = na_layout();
        const state  = na_state(tabId);
        const cfg    = layout.na_get_spec(tabId).getConfig() || {};
        state.cards.forEach(entry => {
            const shown = layout.na_is_item_shown(tabId, entry.id, cfg);
            entry.card.classList.toggle('na-lay-res--blocked', !shown);
            entry.need.hidden = shown;
            if (!shown) na_fill_need(tabId, entry);
        });
        na_sync_active(tabId);
        na_sync_chip(tabId);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Explain Why a Result Is Hidden, With a Fix Button
    // ------------------------------------------------------------
    // A finish row with no swatches yet is waiting on the materials library,
    // not on a switch, and says so.
    function na_fill_need(tabId, entry) {
        const need = entry.item.need;
        const lent = entry.card.querySelector('.na-material-cards-empty');
        const text = lent ? 'the materials library has loaded its swatches'
                   : (need && need.text ? need.text : 'its switch is on');
        if (entry.need.getAttribute('data-na-text') === text) return;
        entry.need.setAttribute('data-na-text', text);
        entry.need.innerHTML = '<span>Shows when: ' + na_escape(text) + '</span>';
        if (need && Array.isArray(need.fix) && need.fix.length) {
            const fix = document.createElement('button');
            fix.type = 'button';
            fix.textContent = 'Turn It On';
            fix.addEventListener('click', () => na_apply_fix(tabId, need.fix));
            entry.need.appendChild(fix);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Highlight the Active Card
    // ------------------------------------------------------------
    function na_sync_active(tabId) {
        const state = na_state(tabId);
        state.cards.forEach((entry, index) => entry.card.classList.toggle('na-lay-res--active', index === state.active));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Paint the Changed Chip's Count
    // ------------------------------------------------------------
    function na_sync_chip(tabId) {
        const layout = na_layout();
        const spec   = layout.na_get_spec(tabId);
        const chip   = spec.changedChipId ? document.getElementById(spec.changedChipId) : null;
        if (!chip) return;
        const state = na_state(tabId);
        const count = na_find_changed(tabId).length;
        const label = chip.querySelector('span');
        if (label) label.textContent = 'Changed · ' + count;
        chip.classList.toggle('na-lay-chg--none', count === 0 && !state.changedOnly);
        chip.classList.toggle('na-lay-chg--on', state.changedOnly);
        chip.setAttribute('aria-pressed', state.changedOnly ? 'true' : 'false');
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Label Highlighting
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Wrap Matched Words in <mark> (Text Only, Escaped)
    // ------------------------------------------------------------
    function na_highlight_text(text, query) {
        const needles = [];
        na_terms(query).forEach(term => {
            needles.push(term);
            (NA_SYNONYMS[term] || []).forEach(alt => needles.push(alt));
        });
        const lower = String(text).toLowerCase();
        const found = needles.filter(needle => needle.length > 2 && lower.indexOf(needle) !== -1)
                             .sort((a, b) => b.length - a.length);
        if (!found.length) return na_escape(text);
        const pattern = new RegExp('(' + found.map(na_escape_regex).join('|') + ')', 'gi');
        return String(text).split(pattern).map((piece, index) =>
            (index % 2) ? '<mark>' + na_escape(piece) + '</mark>' : na_escape(piece)).join('');
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Highlight the Label Inside a Lent Control
    // ------------------------------------------------------------
    // The original text is kept on the element and put back when the control
    // goes home (na_unhighlight_all). The marked text goes in as ONE span: a
    // toggle's label is a flex row, and loose pieces would each become a flex
    // item with a gap between them ("Offset s").
    function na_highlight(el, query) {
        if (!query || !query.trim()) return;
        const labelEl = el.querySelector('.na-expandable-title') ||
                        el.querySelector('.na-control-label > span:first-child') ||
                        el.querySelector('.na-control-label');
        if (!labelEl || (labelEl.children.length > 0 && !labelEl.hasAttribute('data-na-label'))) return;
        if (!labelEl.hasAttribute('data-na-label')) labelEl.setAttribute('data-na-label', labelEl.textContent);
        labelEl.innerHTML = '<span>' + na_highlight_text(labelEl.getAttribute('data-na-label'), query) + '</span>';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Put Every Highlighted Label Back to Plain Text
    // ------------------------------------------------------------
    function na_unhighlight_all(tabId) {
        const layout = na_layout();
        const spec   = layout.na_get_spec(tabId);
        const panel  = (spec.panelId && document.getElementById(spec.panelId)) || document;
        panel.querySelectorAll('[data-na-label]').forEach(labelEl => {
            labelEl.textContent = labelEl.getAttribute('data-na-label');
            labelEl.removeAttribute('data-na-label');
        });
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Actions (Jump, Fix, Reset, Switch Product)
    // -----------------------------------------------------------------------------

    // FUNCTION | Clear the Search and Show an Item in Its Panel
    // ------------------------------------------------------------
    function na_jump(tabId, id) {
        const layout = na_layout();
        const spec   = layout.na_get_spec(tabId);
        const state  = na_state(tabId);
        state.query = '';
        state.changedOnly = false;
        const input = document.getElementById(spec.searchInputId);
        if (input) input.value = '';
        na_render(tabId);

        const target = layout.na_reveal(tabId, id);
        if (!target) return;
        if (target.getAttribute('data-na-sec') !== null) {
            const item = layout.na_get_item(tabId, id);
            const why  = item && item.need && item.need.text ? item.need.text : 'its switch is on';
            if (typeof window.na_showStatus === 'function') {
                window.na_showStatus('info', layout.na_item_label(tabId, id) + ' shows when: ' + why);
            }
        }
        window.setTimeout(() => {                                             // <-- After the sections have laid out again
            layout.na_scroll_into_view(tabId, target);
            layout.na_flash(target);
        }, 0);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Apply a Result's "Turn It On" Fix
    // ------------------------------------------------------------
    // Each fix is [id, value] where value may be a function of the config
    // (raise Mullions to at least 3, without lowering it if it is already 5).
    function na_apply_fix(tabId, fixes) {
        const layout = na_layout();
        const spec   = layout.na_get_spec(tabId);
        fixes.forEach(pair => {
            const cfg   = spec.getConfig() || {};
            const value = (typeof pair[1] === 'function') ? pair[1](cfg) : pair[1];
            spec.setValue(pair[0], value);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Put Settings Back to Their Defaults
    // ------------------------------------------------------------
    function na_reset_items(tabId, ids) {
        const layout  = na_layout();
        const spec    = layout.na_get_spec(tabId);
        const product = layout.na_get_product(tabId);
        ids.forEach(id => {
            const fallback = spec.defaultOf(id, product);
            if (fallback !== undefined) spec.setValue(id, fallback);
        });
        na_render(tabId);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Switch Product, Then Show an Item
    // ------------------------------------------------------------
    function na_switch_and_jump(tabId, product, id) {
        const layout = na_layout();
        const spec   = layout.na_get_spec(tabId);
        spec.selectProduct(product);
        layout.na_refresh_now(tabId);
        na_jump(tabId, id);
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Binding
    // -----------------------------------------------------------------------------

    // FUNCTION | Set the Query and/or Changed Filter, Then Re-Render
    // ------------------------------------------------------------
    function na_set_query(tabId, query, changedOnly) {
        const state = na_state(tabId);
        state.query = String(query || '');
        if (typeof changedOnly === 'boolean') state.changedOnly = changedOnly;
        state.active = 0;
        na_render(tabId);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Wire a Tab's Search Box and Changed Chip
    // ------------------------------------------------------------
    // Called once per tab after its layout has mounted. Safe to call again.
    function na_bind(tabId) {
        const layout = na_layout();
        const spec   = layout && layout.na_get_spec(tabId);
        if (!spec) return;
        const input = document.getElementById(spec.searchInputId);
        const chip  = spec.changedChipId ? document.getElementById(spec.changedChipId) : null;
        const state = na_state(tabId);
        if (!input || input.getAttribute('data-na-bound') === 'true') return;
        input.setAttribute('data-na-bound', 'true');

        input.addEventListener('input', () => na_set_query(tabId, input.value));
        input.addEventListener('keydown', event => na_on_key(tabId, event, input));
        if (chip) chip.addEventListener('click', () => na_set_query(tabId, state.query, !state.changedOnly));

        layout.na_on_refresh(tabId, () => {
            if (state.query.trim() || state.changedOnly) na_sync_cards(tabId);
            else na_sync_chip(tabId);
        });
        layout.na_on_place(tabId, () => {
            if (state.query.trim() || state.changedOnly) na_render(tabId);
        });
        na_sync_chip(tabId);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Keyboard Handling Inside the Search Box
    // ------------------------------------------------------------
    function na_on_key(tabId, event, input) {
        const state = na_state(tabId);
        if (event.key === 'Escape') {
            input.value = '';
            na_set_query(tabId, '', false);
            input.blur();
            return;
        }
        if (!state.cards.length) return;
        if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            const step = event.key === 'ArrowDown' ? 1 : -1;
            state.active = Math.max(0, Math.min(state.cards.length - 1, state.active + step));
            na_sync_active(tabId);
            state.cards[state.active].card.scrollIntoView({ block: 'nearest' });
            return;
        }
        if (event.key === 'Enter') {
            event.preventDefault();
            const entry = state.cards[state.active] || state.cards[0];
            if (entry) na_jump(tabId, entry.id);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Ctrl+F Focuses the Active Configurator Tab's Search
    // ------------------------------------------------------------
    function na_on_global_key(event) {
        if (!(event.ctrlKey || event.metaKey) || String(event.key).toLowerCase() !== 'f') return;
        const tabId  = (window.Na_AppContext && window.Na_AppContext.na_get_active_tab) ? window.Na_AppContext.na_get_active_tab() : '';
        const layout = na_layout();
        const spec   = layout && layout.na_get_spec(tabId);
        const input  = spec ? document.getElementById(spec.searchInputId) : null;
        if (!input) return;
        event.preventDefault();
        input.focus();
        input.select();
    }
    document.addEventListener('keydown', na_on_global_key);
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Public API
    // -----------------------------------------------------------------------------

    return {
        na_bind      : na_bind,
        na_set_query : na_set_query,
        na_render    : na_render,
        na_jump      : na_jump,
        na_is_active : tabId => !!(na_states[tabId] && (na_states[tabId].query.trim() || na_states[tabId].changedOnly))
    };

    // endregion -------------------------------------------------------------------
})();

window.Na__Ui__ParameterSearch = Na__Ui__ParameterSearch;
console.log('[NA_UI_PARAMETER_SEARCH] Shared parameter search module loaded');

/* =============================================================================
   END OF FILE
   ============================================================================= */
