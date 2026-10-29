/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - SHARED SECTION LAYOUT
   =============================================================================
   FILE       : Na__AssemblyStudio__AppCore__UiSystem__SectionLayout__.js
   NAMESPACE  : window.Na__Ui__SectionLayout
   AUTHOR     : Noble Architecture
   PURPOSE    : Arranges a tab's controls into collapsible sections with three
                tiers: Tier 1 always shown, Tier 2 behind "More", Tier 3 behind
                "Advanced". Owns the product strip, the one-line section
                summaries, the changed-value badges, and the hooks the
                parameter search uses to lend a control into its results.
   CREATED    : 28-Oct-2026

   HOW IT FITS
   - Each system still builds its controls exactly as it always has (Windows:
     Na_DynamicUI into the na-controls-* containers, Interior Doors:
     Na_DoorUI.na_mount_section). This module then MOVES each control node,
     listeners and all, into its slot, found by data-control-id. Nothing the
     systems or the Ruby bridge look up by id changes.
   - Visibility the systems already manage (inline style.display) is left
     alone. This module adds three classes of its own on top of it:
       na-lay-off       the control does not belong to the active product
       na-lay-dep-off   a layout rule (showIf) hides it, e.g. cill sizes
                        while Include Cill is off
       na-lay-side-off  a per-leaf override for the leaf not being edited
   - The layout itself is data: each system registers a spec (see the
     WindowSystem and InteriorDoorSystem LayoutMap files) listing its sections,
     their items and tiers, summaries and product rules.
   - A control that has no slot in its spec is never lost: it is swept out of
     the staging container into Output > Advanced > Other with a warning.
   ============================================================================= */

const Na__Ui__SectionLayout = (function () {
    'use strict';

    // -----------------------------------------------------------------------------
    // REGION | Constants and Module State
    // -----------------------------------------------------------------------------

    const NA_STORAGE_KEY       = 'na-easp-section-layout-ui';
    const NA_TIERS             = [1, 2, 3];
    const NA_CLS_PRODUCT_OFF   = 'na-lay-off';
    const NA_CLS_DEP_OFF       = 'na-lay-dep-off';
    const NA_CLS_SIDE_OFF      = 'na-lay-side-off';
    const NA_CLS_LENT          = 'na-lay-lent';
    const NA_CLS_FLASH         = 'na-lay-flash';
    const NA_WIDE_KINDS        = ['cards', 'expandable'];
    const NA_CHEVRON_SVG       = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5 6 7.5 9 4.5"/></svg>';
    const NA_CARET_SVG         = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="M3.5 2 6.5 5 3.5 8"/></svg>';

    const na_specs  = {};                                                      // <-- tabId -> registered layout spec
    const na_states = {};                                                      // <-- tabId -> runtime state

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Small DOM Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Create an Element With a Class and Optional Markup
    // ------------------------------------------------------------
    function na_el(tag, className, html) {
        const el = document.createElement(tag);
        if (className) el.className = className;
        if (html != null) el.innerHTML = html;
        return el;
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

    // HELPER FUNCTION | Resolve a Value That May Be a Function of the Product
    // ------------------------------------------------------------
    function na_resolve(value, product, cfg) {
        return (typeof value === 'function') ? value(product, cfg) : value;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Persisted Open / Shut State
    // -----------------------------------------------------------------------------
    // Which sections are collapsed and which tiers are open survives a reopen of
    // the dialog. Storage can be missing or blocked in an HtmlDialog; the layout
    // then simply starts from its defaults every time.

    // HELPER FUNCTION | Load One Tab's Saved Open / Shut State
    // ------------------------------------------------------------
    function na_load_ui(tabId) {
        const empty = { collapsed: {}, more: {}, adv: {} };
        try {
            const all = JSON.parse(window.localStorage.getItem(NA_STORAGE_KEY) || '{}');
            const saved = all && all[tabId];
            if (!saved) return empty;
            return {
                collapsed : saved.collapsed || {},
                more      : saved.more      || {},
                adv       : saved.adv       || {}
            };
        } catch (err) {
            return empty;
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Save One Tab's Open / Shut State
    // ------------------------------------------------------------
    function na_save_ui(tabId) {
        try {
            const all = JSON.parse(window.localStorage.getItem(NA_STORAGE_KEY) || '{}') || {};
            all[tabId] = na_states[tabId].ui;
            window.localStorage.setItem(NA_STORAGE_KEY, JSON.stringify(all));
        } catch (err) {
            /* Storage unavailable: the state just is not remembered */
        }
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Registration
    // -----------------------------------------------------------------------------

    // FUNCTION | Register a Tab's Layout Spec
    // ------------------------------------------------------------
    // Called by each system's LayoutMap at load time. Nothing touches the DOM
    // until na_mount runs, after the system has built its controls.
    function na_register(tabId, spec) {
        na_specs[tabId]  = spec;
        na_states[tabId] = na_create_state(tabId, spec);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Build the Runtime State for One Registered Spec
    // ------------------------------------------------------------
    function na_create_state(tabId, spec) {
        const items = [];
        (spec.sections || []).forEach(section => {
            (section.items || []).forEach(raw => items.push(na_normalise_item(raw, section.key)));
        });
        const itemById = {};
        items.forEach(item => { if (!itemById[item.id]) itemById[item.id] = item; });
        return {
            tabId        : tabId,
            built        : false,
            items        : items,
            itemById     : itemById,
            sections     : {},
            ui           : na_load_ui(tabId),
            leafSide     : 'left',
            product      : null,
            orderKey     : '',
            elCache      : {},
            pickers      : {},
            lent         : [],
            refreshQueued: false,
            listeners    : [],
            placeListeners: []
        };
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Fill In Every Optional Field of a Layout Item
    // ------------------------------------------------------------
    // kind:  control      an existing [data-control-id] control (the default)
    //        switchgroup  an expandable whose open state is a setting (Per-Side
    //                     Frame Thickness): drawn as a switch with its children
    //        flatten      an expandable used only as a box: header hidden,
    //                     contents always shown (Per Casement Settings)
    //        block        a static element found by its element id
    //        picker       a UI-only switch built here (the leaf picker)
    // inside: the id of the switch group the control lives in. Such controls
    //         are searchable but never moved; they travel with their group.
    // pool:   one of a numbered set (Mullion 4 Offset); the search lists it
    //         only once it exists (four mullions), not as a hidden result.
    function na_normalise_item(raw, sectionKey) {
        return {
            id       : raw.id,
            section  : sectionKey,
            tier     : raw.tier || 1,
            group    : raw.group || '',
            products : raw.products || null,
            showIf   : raw.showIf || null,
            need     : raw.need || null,
            kw       : raw.kw || '',
            wide     : raw.wide === true,
            kind     : raw.kind || 'control',
            side     : raw.side || null,
            inside   : raw.inside || null,
            pool     : raw.pool || 0,
            label    : raw.label || '',
            nosearch : raw.nosearch === true
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Skeleton Build (Sections, Tiers, Slots, Product Strip)
    // -----------------------------------------------------------------------------

    // FUNCTION | Build a Tab's Section Skeletons Once
    // ------------------------------------------------------------
    // @return {boolean} true when the skeleton exists (built now or before)
    function na_build(tabId) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        if (!spec || !state) return false;
        if (state.built) return true;

        const host = document.getElementById(spec.sectionsHostId);
        if (!host) return false;

        spec.sections.forEach(section => {
            const built = na_build_section(tabId, section);
            state.sections[section.key] = built;
            host.appendChild(built.el);
        });
        na_build_product_strip(tabId);
        state.built = true;
        return true;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Build One Section Card With Its Three Tiers
    // ------------------------------------------------------------
    function na_build_section(tabId, section) {
        const el    = na_el('section', 'na-lay-sec');
        el.setAttribute('data-na-sec', section.key);

        const top   = na_el('div', 'na-lay-sec__top');
        const head  = na_el('button', 'na-lay-sec__head',
            NA_CHEVRON_SVG +
            '<span class="na-lay-sec__title"></span>' +
            '<span class="na-lay-sec__sum"></span>' +
            '<span class="na-lay-sec__badge" hidden></span>');
        head.type = 'button';
        const moreBtn = na_el('button', 'na-lay-more na-lay-more--head',
            NA_CARET_SVG + '<span class="na-lay-more__label"></span><em></em><b hidden></b>');
        moreBtn.type   = 'button';
        moreBtn.hidden = true;
        top.appendChild(head);
        top.appendChild(moreBtn);

        const body    = na_el('div', 'na-lay-sec__body');
        const offNote = na_el('div', 'na-lay-offnote');
        offNote.hidden = true;
        const tierEls = {
            1: na_el('div', 'na-lay-tier na-lay-tier--1'),
            2: na_el('div', 'na-lay-tier na-lay-tier--2'),
            3: na_el('div', 'na-lay-tier na-lay-tier--3')
        };
        tierEls[2].hidden = true;
        tierEls[3].hidden = true;
        const advBtn = na_el('button', 'na-lay-more na-lay-more--adv',
            NA_CARET_SVG + '<span class="na-lay-more__label">Advanced</span><em></em><b hidden></b>');
        advBtn.type   = 'button';
        advBtn.hidden = true;

        body.appendChild(offNote);
        body.appendChild(tierEls[1]);
        body.appendChild(tierEls[2]);
        body.appendChild(advBtn);
        body.appendChild(tierEls[3]);
        el.appendChild(top);
        el.appendChild(body);

        const built = {
            key     : section.key,
            def     : section,
            el      : el,
            head    : head,
            titleEl : head.querySelector('.na-lay-sec__title'),
            sumEl   : head.querySelector('.na-lay-sec__sum'),
            badgeEl : head.querySelector('.na-lay-sec__badge'),
            moreBtn : moreBtn,
            advBtn  : advBtn,
            body    : body,
            offNote : offNote,
            tierEls : tierEls,
            slots   : {},
            headRole: ''
        };
        na_build_slots(tabId, built);
        na_bind_section_events(tabId, built);
        return built;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Create the Grids Each Tier's Items Land In
    // ------------------------------------------------------------
    // Ungrouped items share one grid at the top of their tier; each named
    // group gets its own heading and grid, in the order the spec lists them.
    function na_build_slots(tabId, built) {
        const state = na_states[tabId];
        NA_TIERS.forEach(tier => {
            const groups = [];
            state.items.forEach(item => {
                if (item.section !== built.key || item.tier !== tier || item.inside) return;
                if (groups.indexOf(item.group) === -1) groups.push(item.group);
            });
            groups.sort((a, b) => (a === '' ? -1 : (b === '' ? 1 : 0)));
            groups.forEach(group => na_create_slot(built, tier, group));
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Create One Slot Grid (Optionally Under a Group Heading)
    // ------------------------------------------------------------
    function na_create_slot(built, tier, group) {
        const key = tier + '|' + group;
        if (built.slots[key]) return built.slots[key];

        const tierEl = built.tierEls[tier];
        const grid   = na_el('div', 'na-lay-grid');
        if (!group) {
            tierEl.insertBefore(grid, tierEl.firstChild);
            built.slots[key] = grid;
            return grid;
        }
        const wrap = na_el('div', 'na-lay-group');
        wrap.appendChild(na_el('div', 'na-lay-group__head', na_escape(group)));
        wrap.appendChild(grid);
        tierEl.appendChild(wrap);
        built.slots[key] = grid;
        return grid;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Wire a Section's Header, More and Advanced Buttons
    // ------------------------------------------------------------
    function na_bind_section_events(tabId, built) {
        const ui = na_states[tabId].ui;
        built.head.addEventListener('click', () => {
            ui.collapsed[built.key] = !ui.collapsed[built.key];
            na_save_ui(tabId);
            na_refresh_now(tabId);
        });
        built.moreBtn.addEventListener('click', () => {
            const store = (built.headRole === 'adv') ? ui.adv : ui.more;
            store[built.key] = !store[built.key];
            na_save_ui(tabId);
            na_refresh_now(tabId);
        });
        built.advBtn.addEventListener('click', () => {
            ui.adv[built.key] = !ui.adv[built.key];
            na_save_ui(tabId);
            na_refresh_now(tabId);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Render the Product Strip Chips
    // ------------------------------------------------------------
    function na_build_product_strip(tabId) {
        const spec = na_specs[tabId];
        const host = spec.productStripId ? document.getElementById(spec.productStripId) : null;
        if (!host || !Array.isArray(spec.products) || !spec.products.length) return;

        const groups = [];
        spec.products.forEach(product => { if (groups.indexOf(product.group) === -1) groups.push(product.group); });
        host.innerHTML = groups.map(group => {
            const chips = spec.products.filter(product => product.group === group).map(product =>
                '<button type="button" class="na-lay-chip" data-na-product="' + na_escape(product.key) + '" aria-pressed="false" title="' + na_escape(product.title || product.label) + '">' +
                '<svg viewBox="0 0 24 24" aria-hidden="true">' + product.icon + '</svg>' +
                '<span>' + na_escape(product.label) + '</span></button>'
            ).join('');
            return '<div class="na-lay-chipgroup">' + (group ? '<b>' + na_escape(group) + '</b>' : '') + '<div>' + chips + '</div></div>';
        }).join('');

        host.querySelectorAll('[data-na-product]').forEach(button => {
            button.addEventListener('click', () => {
                const key = button.getAttribute('data-na-product');
                if (key === na_states[tabId].product) return;
                spec.selectProduct(key);
            });
        });
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Placement
    // -----------------------------------------------------------------------------

    // FUNCTION | Move Every Built Control Into Its Slot
    // ------------------------------------------------------------
    // Called by each system once its controls exist (and again by the
    // Interior Door tab after every rebuild). Safe to call repeatedly.
    function na_mount(tabId) {
        if (!na_build(tabId)) return;
        const state = na_states[tabId];
        Object.keys(state.sections).forEach(key => na_place_section(tabId, key));
        na_sweep_leftovers(tabId);
        na_refresh_now(tabId);
        state.placeListeners.forEach(fn => na_call_safely(fn));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Place Every Item of One Section, In Spec Order
    // ------------------------------------------------------------
    function na_place_section(tabId, sectionKey) {
        const state = na_states[tabId];
        state.items.forEach(item => {
            if (item.section !== sectionKey || item.inside) return;
            na_place_item(tabId, item);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Move One Item's Element Into Its Slot
    // ------------------------------------------------------------
    function na_place_item(tabId, item) {
        const el = na_find_item_element(tabId, item);
        if (!el) return null;
        if (na_is_lent(tabId, item.id)) return el;                             // <-- The search holds it; it comes back on return
        const slot = na_slot_for(tabId, item);
        if (slot) slot.appendChild(el);
        na_tag_element(el, item);
        return el;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Resolve (Creating If Needed) an Item's Slot Grid
    // ------------------------------------------------------------
    function na_slot_for(tabId, item) {
        const built = na_states[tabId].sections[item.section];
        if (!built) return null;
        return built.slots[item.tier + '|' + item.group] || na_create_slot(built, item.tier, item.group);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Find the Live Element for an Item
    // ------------------------------------------------------------
    // Cached, but re-resolved whenever the cached node has been replaced
    // (material cards re-render by outerHTML) or rebuilt (Interior Door mount).
    function na_find_item_element(tabId, item) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        if (item.kind === 'block') return document.getElementById(item.id);
        if (item.kind === 'picker') {
            if (!state.pickers[item.id]) state.pickers[item.id] = na_build_leaf_picker(tabId, item);
            return state.pickers[item.id];
        }

        const cached = state.elCache[item.id];
        if (cached && cached.isConnected && cached.getAttribute('data-control-id') === item.id) return cached;

        const scope = (spec.panelId && document.getElementById(spec.panelId)) || document;
        const found = scope.querySelector('[data-control-id="' + item.id + '"]');
        state.elCache[item.id] = found || null;
        return found;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Sweep Unmapped Controls Out of the Staging Container
    // ------------------------------------------------------------
    // A control added to a system's config without a slot in its layout map
    // would otherwise stay invisible in staging. It is placed under
    // <fallback section> > Advanced > Other and reported.
    function na_sweep_leftovers(tabId) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        const staging = spec.stagingId ? document.getElementById(spec.stagingId) : null;
        if (!staging) return;

        const hidden = spec.hiddenIds || [];
        staging.querySelectorAll('[data-control-id]').forEach(el => {
            const id = el.getAttribute('data-control-id');
            if (hidden.indexOf(id) !== -1 || state.itemById[id]) return;
            const parent = el.parentElement && el.parentElement.closest('[data-control-id]');
            if (parent && hidden.indexOf(parent.getAttribute('data-control-id')) === -1) return;   // <-- Travels with an unmapped parent

            const item = na_normalise_item({ id: id, tier: 3, group: 'Other' }, spec.fallbackSection || 'output');
            state.items.push(item);
            state.itemById[id] = item;
            na_place_item(tabId, item);
            console.warn('[Na__Ui__SectionLayout] ' + tabId + ': control "' + id +
                         '" has no layout slot; placed under Advanced > Other.');
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Remove Every Placed Control (Before a Tab Rebuilds Them)
    // ------------------------------------------------------------
    // The Interior Door tab rebuilds its controls on every mount, so the old
    // nodes must leave their slots first or each id would appear twice.
    // Static blocks and the leaf picker are layout-owned and stay.
    function na_clear(tabId) {
        const state = na_states[tabId];
        if (!state) return;
        na_return_all(tabId);
        state.items.forEach(item => {
            if (item.kind === 'block' || item.kind === 'picker' || item.inside) return;
            const el = na_find_item_element(tabId, item);
            if (el && el.parentNode) el.parentNode.removeChild(el);
        });
        state.elCache = {};
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Element Tagging (Kinds, Width, Click Guard)
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Tag an Element With Its Layout Classes Once
    // ------------------------------------------------------------
    function na_tag_element(el, item) {
        el.classList.add('na-lay-item');
        if (item.kind === 'switchgroup') el.classList.add('na-lay-switchgroup');
        if (item.kind === 'flatten')     el.classList.add('na-lay-flatten');
        na_tag_kind(el);
        el.querySelectorAll('[data-control-id]').forEach(na_tag_kind);
        const kind = el.getAttribute('data-na-lay-kind');
        el.classList.toggle('na-lay-wide',
            item.wide || item.kind === 'block' || item.kind === 'picker' || NA_WIDE_KINDS.indexOf(kind) !== -1);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Record What Kind of Control an Element Is
    // ------------------------------------------------------------
    // The stylesheet lays each kind out differently (a slider is label, track
    // and number on one line; a material row wraps its swatches).
    function na_tag_kind(el) {
        if (!el || el.getAttribute('data-na-lay-kind')) return;
        el.setAttribute('data-na-lay-kind', na_detect_kind(el));
        if (el.getAttribute('data-na-lay-kind') === 'binary') na_guard_binary_toggle(el);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Detect a Control's Kind From Its Markup
    // ------------------------------------------------------------
    function na_detect_kind(el) {
        if (el.classList.contains('na-expandable-wrapper'))   return 'expandable';
        if (el.querySelector('.na-slider-container'))         return 'slider';
        if (el.querySelector('.na-material-cards-container')) return 'cards';
        if (el.querySelector('.na-binary-toggle'))            return 'binary';
        if (el.querySelector('.na-segmented-toggle'))         return 'segmented';
        if (el.querySelector('.na-eq-number-input'))          return 'eq';
        if (el.querySelector('select'))                       return 'select';
        if (el.querySelector('.na-toggle'))                   return 'toggle';
        return 'other';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Stop a Click on the Chosen Side Flipping a Binary Toggle
    // ------------------------------------------------------------
    // The two-option switch is drawn as a pair of buttons here. Its own
    // listener flips on any click, so clicking the side that is already
    // chosen would select the other one. Swallowed in the capture phase.
    function na_guard_binary_toggle(el) {
        el.addEventListener('click', event => {
            const option = event.target.closest('.na-binary-toggle__option');
            if (!option) return;
            const toggle = option.closest('.na-binary-toggle');
            if (!toggle) return;
            const leftChosen   = toggle.classList.contains('na-binary-toggle--left');
            const clickedLeft  = option.classList.contains('na-binary-toggle__option--left');
            if (clickedLeft === leftChosen) event.stopPropagation();
        }, true);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Build the Leaf Picker (Per-Leaf Overrides)
    // ------------------------------------------------------------
    function na_build_leaf_picker(tabId, item) {
        const el = na_el('div', 'na-control-item na-lay-picker',
            '<div class="na-toggle-container"><span class="na-control-label">' + na_escape(item.label || 'Editing') + '</span>' +
            '<div class="na-segmented-toggle">' +
            '<button type="button" class="na-segmented-toggle__option" data-na-side="left">Left Leaf</button>' +
            '<button type="button" class="na-segmented-toggle__option" data-na-side="right">Right Leaf</button>' +
            '</div></div>');
        el.setAttribute('data-na-lay-picker', item.id);
        el.querySelectorAll('[data-na-side]').forEach(button => {
            button.addEventListener('click', () => {
                na_states[tabId].leafSide = button.getAttribute('data-na-side');
                na_refresh_now(tabId);
            });
        });
        return el;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Visibility Tests
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Does an Item Belong to the Active Product
    // ------------------------------------------------------------
    function na_product_ok(item, product) {
        return !item.products || item.products.indexOf(product) !== -1;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Is an Element Shown, Up to (Not Including) a Root
    // ------------------------------------------------------------
    // Shown means: none of the layout's own hide classes, no inline
    // display:none from the system, not an empty material placeholder, and
    // not inside a switch group that is switched off. Tier boxes and
    // collapsed sections do NOT count: an item behind "More" is still shown,
    // just not open.
    function na_is_shown(el, root) {
        if (!el) return false;
        for (let node = el; node && node !== root; node = node.parentElement) {
            if (!node.classList) continue;
            if (node.classList.contains(NA_CLS_PRODUCT_OFF) ||
                node.classList.contains(NA_CLS_DEP_OFF) ||
                node.classList.contains(NA_CLS_SIDE_OFF) ||
                node.classList.contains('na-material-cards-empty')) return false;
            if (node.style && node.style.display === 'none') return false;
            if (node.classList.contains('na-expandable-content') &&
                !node.classList.contains('na-expanded') &&
                !(node.parentElement && node.parentElement.classList.contains('na-lay-flatten'))) return false;
        }
        return true;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Is an Item Shown Right Now (Used by the Search Results)
    // ------------------------------------------------------------
    // Works for an item lent into the results too, where its ancestors are
    // the result card rather than its section.
    // @param {Object} [cfgIn] - Config snapshot, when the caller already holds
    //                           one (the search checks every item in a row)
    function na_is_item_shown(tabId, id, cfgIn) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        const item  = state && state.itemById[id];
        if (!item) return false;
        const cfg     = cfgIn || spec.getConfig() || {};
        const product = state.product;
        if (!na_product_ok(item, product)) return false;
        if (item.showIf && !item.showIf(cfg, product)) return false;
        if (item.inside) {
            const parent = state.itemById[item.inside];
            if (parent && parent.kind === 'switchgroup' && cfg[item.inside] !== true) return false;
            if (parent && !na_is_item_shown(tabId, parent.id, cfg)) return false;
        }
        const el = na_find_item_element(tabId, item);
        if (!el) return false;
        if (na_is_lent(tabId, id)) {
            return el.style.display !== 'none' && !el.classList.contains('na-material-cards-empty');
        }
        const built = state.sections[item.section];
        return na_is_shown(el, built ? built.el : null);
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Refresh
    // -----------------------------------------------------------------------------

    // FUNCTION | Queue a Refresh a Frame From Now
    // ------------------------------------------------------------
    // A slider drag fires a change on every pixel; one refresh per ~frame
    // keeps the summaries and badges current without repeating the work. A
    // timer, not requestAnimationFrame: rAF never fires while the dialog is
    // not painting, and a change Ruby pushes then would leave stale summaries.
    function na_request_refresh(tabId) {
        const state = na_states[tabId];
        if (!state || !state.built || state.refreshQueued) return;
        state.refreshQueued = true;
        window.setTimeout(() => {
            state.refreshQueued = false;
            na_refresh_now(tabId);
        }, 16);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Refresh Classes, Sections, Strip and Summaries Immediately
    // ------------------------------------------------------------
    function na_refresh_now(tabId) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        if (!state || !state.built) return;

        const cfg     = spec.getConfig() || {};
        const product = spec.activeProduct ? spec.activeProduct(cfg) : '';
        state.product = product;

        na_sync_product_strip(tabId, product);
        na_sync_section_order(tabId, product);
        state.items.forEach(item => na_sync_item(tabId, item, cfg, product));
        Object.keys(state.sections).forEach(key => na_sync_section(tabId, key, cfg, product));
        if (typeof spec.onRefresh === 'function') na_call_safely(() => spec.onRefresh(cfg, product));
        state.listeners.forEach(fn => na_call_safely(() => fn(cfg, product)));
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Run a Callback Without Letting It Break the Refresh
    // ------------------------------------------------------------
    function na_call_safely(fn) {
        try { fn(); }
        catch (err) { console.error('[Na__Ui__SectionLayout] callback failed:', err); }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Mark the Active Product Chip
    // ------------------------------------------------------------
    function na_sync_product_strip(tabId, product) {
        const spec = na_specs[tabId];
        const host = spec.productStripId ? document.getElementById(spec.productStripId) : null;
        if (!host) return;
        host.querySelectorAll('[data-na-product]').forEach(button => {
            const active = button.getAttribute('data-na-product') === product;
            button.classList.toggle('na-lay-chip--on', active);
            button.setAttribute('aria-pressed', active ? 'true' : 'false');
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Put Sections in the Active Product's Order
    // ------------------------------------------------------------
    function na_sync_section_order(tabId, product) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        const order = spec.orderFor ? spec.orderFor(product) : spec.sections.map(section => section.key);
        const key   = order.join('|');
        if (key === state.orderKey) return;
        state.orderKey = key;

        const host = document.getElementById(spec.sectionsHostId);
        order.forEach(sectionKey => {
            const built = state.sections[sectionKey];
            if (built) host.appendChild(built.el);
        });
        Object.keys(state.sections).forEach(sectionKey => {
            state.sections[sectionKey].inOrder = order.indexOf(sectionKey) !== -1;
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Bring One Item's Element and Classes Up to Date
    // ------------------------------------------------------------
    function na_sync_item(tabId, item, cfg, product) {
        if (item.inside) return;                                               // <-- Lives inside its switch group
        const state = na_states[tabId];
        const el    = na_find_item_element(tabId, item);
        if (!el) return;

        if (!na_is_lent(tabId, item.id)) {
            const slot = na_slot_for(tabId, item);
            if (slot && el.parentNode !== slot) na_place_section(tabId, item.section);
        }
        na_tag_element(el, item);

        el.classList.toggle(NA_CLS_PRODUCT_OFF, !na_product_ok(item, product));
        el.classList.toggle(NA_CLS_DEP_OFF, !!(item.showIf && !item.showIf(cfg, product)));
        el.classList.toggle(NA_CLS_SIDE_OFF, !!(item.side && item.side !== state.leafSide));

        if (item.kind === 'picker') na_sync_leaf_picker(el, state.leafSide);
        na_sync_picked_name(el);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Show Which Leaf the Picker Is Editing
    // ------------------------------------------------------------
    function na_sync_leaf_picker(el, side) {
        el.querySelectorAll('[data-na-side]').forEach(button => {
            button.classList.toggle('na-segmented-toggle__option--active', button.getAttribute('data-na-side') === side);
        });
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Write the Chosen Swatch's Name Beside a Material Label
    // ------------------------------------------------------------
    // The swatch rows draw small chips with the name as a tooltip; the label
    // carries the chosen one so it reads without hovering.
    function na_sync_picked_name(el) {
        const label = el.querySelector('.na-control-label, .na-lay-block__label');
        const cards = el.querySelector('.na-material-cards-container');
        if (!label || !cards) return;
        const chosen = cards.querySelector('.na-material-card-selected');
        label.setAttribute('data-na-picked', chosen ? (chosen.getAttribute('title') || '') : '');
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Bring One Section Card Up to Date
    // ------------------------------------------------------------
    function na_sync_section(tabId, sectionKey, cfg, product) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        const built = state.sections[sectionKey];
        const def   = built.def;
        const ui    = state.ui;

        const items      = state.items.filter(item => item.section === sectionKey && !item.inside);
        const applicable = items.filter(item => na_product_ok(item, product));
        const sectionOk  = built.inOrder !== false && (!def.products || def.products.indexOf(product) !== -1);
        built.el.hidden  = !sectionOk || applicable.length === 0;
        if (built.el.hidden) return;

        built.titleEl.textContent = na_resolve(def.title, product, cfg) || '';

        const shown = {};
        NA_TIERS.forEach(tier => {
            shown[tier] = applicable.filter(item =>
                item.tier === tier && item.kind !== 'picker' && na_is_shown(na_find_item_element(tabId, item), built.el));
        });
        const offText = def.offNote ? (def.offNote(cfg, product) || '') : '';
        const empty   = (shown[1].length + shown[2].length + shown[3].length) === 0;
        const note    = offText || (empty ? (def.emptyNote ? def.emptyNote(cfg, product) : 'Nothing to set here for this product.') : '');

        const collapsed = ui.collapsed[sectionKey] === true;
        built.head.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
        built.body.hidden    = collapsed;
        built.offNote.hidden = !note;
        built.offNote.textContent = note;
        built.el.classList.toggle('na-lay-sec--off', !!note);

        na_sync_tiers(tabId, built, shown, !!note, cfg, product);
        na_sync_group_visibility(built);

        built.sumEl.textContent = def.summary ? (def.summary(cfg, product) || '') : '';
        const changed = applicable.filter(item => na_is_shown(na_find_item_element(tabId, item), built.el) &&
                                                  na_is_changed(tabId, item.id, cfg, product)).length;
        built.badgeEl.hidden      = changed === 0;
        built.badgeEl.textContent = changed + ' changed';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Open / Shut the More and Advanced Tiers
    // ------------------------------------------------------------
    // The header button opens More when the section has Tier 2 items for this
    // product, or Advanced directly when it only has Tier 3 ones. A shut tier
    // that holds changed values says so, so a change is never out of sight.
    function na_sync_tiers(tabId, built, shown, isOff, cfg, product) {
        const ui        = na_states[tabId].ui;
        const key       = built.key;
        const collapsed = ui.collapsed[key] === true;
        const n2 = shown[2].length;
        const n3 = shown[3].length;
        const role = n2 > 0 ? 'more' : (n3 > 0 ? 'adv' : '');
        built.headRole = role;

        const moreOpen = role === 'more' && ui.more[key] === true;
        const advOpen  = (role === 'adv' || moreOpen) && ui.adv[key] === true;

        built.tierEls[1].hidden = isOff;
        built.tierEls[2].hidden = isOff || !moreOpen;
        built.tierEls[3].hidden = isOff || !advOpen;

        const headOpen = role === 'more' ? moreOpen : advOpen;
        const headHidden = isOff || collapsed || !role;
        const headChanged = role === 'more'
            ? shown[2].concat(shown[3]).filter(item => na_is_changed(tabId, item.id, cfg, product)).length
            : shown[3].filter(item => na_is_changed(tabId, item.id, cfg, product)).length;
        na_paint_tier_button(built.moreBtn, headHidden, headOpen,
            role === 'more' ? (headOpen ? 'Less' : 'More') : (headOpen ? 'Hide Advanced' : 'Advanced'),
            role === 'more' ? n2 : n3, headChanged);

        const advHidden  = isOff || role !== 'more' || !moreOpen || n3 === 0;
        const advChanged = shown[3].filter(item => na_is_changed(tabId, item.id, cfg, product)).length;
        na_paint_tier_button(built.advBtn, advHidden, advOpen, advOpen ? 'Hide Advanced' : 'Advanced', n3, advChanged);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Paint a More / Advanced Button
    // ------------------------------------------------------------
    function na_paint_tier_button(button, hidden, open, label, count, changed) {
        button.hidden = hidden;
        if (hidden) return;
        button.setAttribute('aria-expanded', open ? 'true' : 'false');
        button.querySelector('.na-lay-more__label').textContent = label;
        button.querySelector('em').textContent = open ? '' : '· ' + count;
        const badge = button.querySelector('b');
        badge.hidden = open || changed === 0;
        badge.textContent = changed + ' changed';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Hide Group Headings (and Empty Grids) With Nothing Shown
    // ------------------------------------------------------------
    function na_sync_group_visibility(built) {
        Object.keys(built.slots).forEach(slotKey => {
            const grid = built.slots[slotKey];
            const any  = Array.prototype.some.call(grid.children, child => na_is_shown(child, grid));
            const box  = grid.parentElement && grid.parentElement.classList.contains('na-lay-group') ? grid.parentElement : grid;
            box.hidden = !any;
        });
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Changed Values
    // -----------------------------------------------------------------------------

    // FUNCTION | Has a Setting Moved Off Its Default
    // ------------------------------------------------------------
    // The default comes from the spec, which knows each product's own starting
    // values (a double door opens at 1800 x 2100, not the window's 900 x 1200).
    function na_is_changed(tabId, id, cfg, product) {
        const spec = na_specs[tabId];
        if (!spec || typeof spec.defaultOf !== 'function') return false;
        if (spec.changedIgnore && spec.changedIgnore.indexOf(id) !== -1) return false;
        const fallback = spec.defaultOf(id, product);
        if (fallback === undefined) return false;
        const value = (cfg || spec.getConfig() || {})[id];
        if (value === undefined) return false;
        return !na_same_value(value, fallback);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Compare Two Setting Values Loosely (5 Equals "5")
    // ------------------------------------------------------------
    function na_same_value(a, b) {
        if (a === b) return true;
        if (a === null || b === null) return false;
        if (typeof a !== 'boolean' && typeof b !== 'boolean') {
            const numA = Number(a);
            const numB = Number(b);
            if (String(a).trim() !== '' && String(b).trim() !== '' && isFinite(numA) && isFinite(numB)) {
                return Math.abs(numA - numB) < 1e-6;
            }
        }
        return String(a) === String(b);
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Lending (Search Results) and Revealing (Show in Panel)
    // -----------------------------------------------------------------------------

    // FUNCTION | Lend a Control Into a Search Result Card
    // ------------------------------------------------------------
    // The real control moves into the card, so it can be edited there and
    // keeps every listener. A comment marks where it came from.
    function na_lend(tabId, id, host) {
        const state = na_states[tabId];
        const item  = state && state.itemById[id];
        if (!item || item.kind === 'block' || item.kind === 'picker') return null;
        const el = na_find_item_element(tabId, item);
        if (!el || !el.parentNode || na_is_lent(tabId, id)) return null;

        const marker = document.createComment('na-lay:' + id);
        el.parentNode.insertBefore(marker, el);
        host.appendChild(el);
        el.classList.add(NA_CLS_LENT);
        na_tag_kind(el);
        state.lent.push({ id: id, item: item, marker: marker });
        return el;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Return Every Lent Control to Where It Came From
    // ------------------------------------------------------------
    function na_return_all(tabId) {
        const state = na_states[tabId];
        if (!state) return;
        state.lent.forEach(entry => {
            const el = na_find_item_element(tabId, entry.item);                // <-- May have been re-rendered while lent
            if (el && entry.marker.parentNode) {
                entry.marker.parentNode.insertBefore(el, entry.marker);
                el.classList.remove(NA_CLS_LENT);
            }
            if (entry.marker.parentNode) entry.marker.parentNode.removeChild(entry.marker);
        });
        state.lent = [];
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Is a Control Currently Lent to the Search
    // ------------------------------------------------------------
    function na_is_lent(tabId, id) {
        const state = na_states[tabId];
        return !!state && state.lent.some(entry => entry.id === id);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Open the Path to an Item (Section, Tier, Leaf) and Return It
    // ------------------------------------------------------------
    // @return {Element|null} The item's element when it is shown, otherwise
    //                        its section card (the caller explains why)
    function na_reveal(tabId, id) {
        const state = na_states[tabId];
        const item  = state && state.itemById[id];
        if (!item) return null;
        const target = item.inside ? (state.itemById[item.inside] || item) : item;

        state.ui.collapsed[target.section] = false;
        if (target.tier >= 2) state.ui.more[target.section] = true;
        if (target.tier === 3) state.ui.adv[target.section] = true;
        if (item.side) state.leafSide = item.side;
        na_save_ui(tabId);
        na_refresh_now(tabId);

        const el    = na_find_item_element(tabId, item);
        const built = state.sections[target.section];
        if (el && na_is_item_shown(tabId, id)) return el;
        return built ? built.el : null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Scroll an Element to the Middle of the Visible Area
    // ------------------------------------------------------------
    // The pinned toolbar and preview cover the top of the scroll area, so the
    // target is centred in what is left beneath them.
    function na_scroll_into_view(tabId, el) {
        const spec     = na_specs[tabId];
        const scroller = document.querySelector(spec.scrollerSelector || '.na-main-content');
        if (!scroller || !el) return;
        const sticky       = spec.stickyTopId ? document.getElementById(spec.stickyTopId) : null;
        const pinned       = sticky && window.getComputedStyle(sticky).position === 'sticky';   // <-- Short dialogs let the head scroll away
        const stickyHeight = pinned ? sticky.getBoundingClientRect().height : 0;
        const box          = scroller.getBoundingClientRect();
        const rect         = el.getBoundingClientRect();
        const visibleTop   = box.top + stickyHeight;
        const visibleSpan  = Math.max(80, box.height - stickyHeight);
        scroller.scrollTop += (rect.top - visibleTop) - Math.max(0, (visibleSpan - rect.height) / 2);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Flash an Element So the Eye Finds It
    // ------------------------------------------------------------
    function na_flash(el) {
        if (!el) return;
        el.classList.remove(NA_CLS_FLASH);
        void el.offsetWidth;                                                   // <-- Restart the animation
        el.classList.add(NA_CLS_FLASH);
        window.setTimeout(() => el.classList.remove(NA_CLS_FLASH), 1500);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Describe Where an Item Lives ("Frame & Cill > More > Cill")
    // ------------------------------------------------------------
    function na_item_path(tabId, id, product) {
        const spec  = na_specs[tabId];
        const state = na_states[tabId];
        const item  = state && state.itemById[id];
        if (!item) return '';
        const owner   = item.inside ? (state.itemById[item.inside] || item) : item;
        const section = spec.sections.filter(entry => entry.key === owner.section)[0];
        const cfg     = spec.getConfig() || {};
        const parts   = [section ? na_resolve(section.title, product, cfg) : owner.section];
        const hasTier2 = state.items.some(entry => entry.section === owner.section && entry.tier === 2 &&
                                                   !entry.inside && na_product_ok(entry, product));
        if (owner.tier === 2 || (owner.tier === 3 && hasTier2)) parts.push('More');
        if (owner.tier === 3) parts.push('Advanced');
        if (owner.group) parts.push(owner.group);
        if (item.inside) parts.push(na_item_label(tabId, owner.id));
        if (item.side) parts.push(item.side === 'left' ? 'Left Leaf' : 'Right Leaf');
        return parts.join(' › ');
    }
    // ---------------------------------------------------------------

    // FUNCTION | Read an Item's Label (Spec Override, Else Its On-Screen Label)
    // ------------------------------------------------------------
    function na_item_label(tabId, id) {
        const state = na_states[tabId];
        const item  = state && state.itemById[id];
        if (!item) return id;
        if (item.label) return item.label;
        const el = na_find_item_element(tabId, item);
        if (!el) return id;
        const labelEl = el.querySelector('.na-expandable-title') ||
                        el.querySelector('.na-control-label > span:first-child') ||
                        el.querySelector('.na-control-label');
        const text = labelEl ? (labelEl.getAttribute('data-na-label') || labelEl.textContent) : '';
        return (text || id).trim();
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------

    // -----------------------------------------------------------------------------
    // REGION | Public API
    // -----------------------------------------------------------------------------

    return {
        na_register         : na_register,
        na_mount            : na_mount,
        na_clear            : na_clear,
        na_request_refresh  : na_request_refresh,
        na_refresh_now      : na_refresh_now,
        na_get_spec         : tabId => na_specs[tabId] || null,
        na_get_items        : tabId => (na_states[tabId] ? na_states[tabId].items.slice() : []),
        na_get_item         : (tabId, id) => (na_states[tabId] ? na_states[tabId].itemById[id] || null : null),
        na_get_product      : tabId => (na_states[tabId] ? na_states[tabId].product : null),
        na_is_built         : tabId => !!(na_states[tabId] && na_states[tabId].built),
        na_on_refresh       : (tabId, fn) => { if (na_states[tabId]) na_states[tabId].listeners.push(fn); },
        na_on_place         : (tabId, fn) => { if (na_states[tabId]) na_states[tabId].placeListeners.push(fn); },
        na_find_element     : (tabId, id) => {
            const item = na_states[tabId] && na_states[tabId].itemById[id];
            return item ? na_find_item_element(tabId, item) : null;
        },
        na_is_item_shown    : na_is_item_shown,
        na_is_product_ok    : (tabId, id) => {
            const item = na_states[tabId] && na_states[tabId].itemById[id];
            return !!item && na_product_ok(item, na_states[tabId].product);
        },
        na_is_changed       : na_is_changed,
        na_item_path        : na_item_path,
        na_item_label       : na_item_label,
        na_lend             : na_lend,
        na_return_all       : na_return_all,
        na_is_lent          : na_is_lent,
        na_reveal           : na_reveal,
        na_scroll_into_view : na_scroll_into_view,
        na_flash            : na_flash
    };

    // endregion -------------------------------------------------------------------
})();

window.Na__Ui__SectionLayout = Na__Ui__SectionLayout;
console.log('[NA_UI_SECTION_LAYOUT] Shared section layout module loaded');

/* =============================================================================
   END OF FILE
   ============================================================================= */
