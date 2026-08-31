/* =============================================================================
   NA PROFILE TOOLS - GALLERY MODE - UI SYSTEM - MAIN UI LOGIC
   =============================================================================
   FILE       : Na__ProfileTools__Gallery__UiSystem__MainUiLogic__.js
   NAMESPACE  : window.Na__ProfileTools__Gallery__Tab
   PURPOSE    : Gallery tab — SVG-thumbnail card grid, keyword-prioritised search,
                thumbnail-size cycling, profile selection routing.
                Implements the Na_TabRouter mount/unmount contract.

   SWAP MODE  : While Na__ProfileTools__SwapController is armed, this grid is a
                replacement picker rather than a selector — a banner names the
                bound trace and a card click swaps that trace's profile in the
                model instead of routing to Apply Profile. Everything else about
                the grid (search, sizing, thumbnails) behaves identically, so
                there is only one place to learn how to find a profile.
   ============================================================================= */

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var NA_BODY_ID        = 'na-tab-gallery-body';
    var NA_GRID_ID        = 'na-gallery-grid';
    var NA_SEARCH_ID      = 'na-gallery-search';
    var NA_SIZE_BTN_ID    = 'na-gallery-size-btn';
    var NA_SWAP_BTN_ID    = 'na-gallery-swap-btn';
    var NA_SWAP_CANCEL_ID = 'na-gallery-swap-cancel';
    var NA_SIZE_CLASSES   = ['na-gallery-grid--sm', 'na-gallery-grid--idx'];
    var NA_SIZE_LABELS    = ['Small', 'Index'];

    var na_size_index     = 0;
    var na_search_query   = '';
    var na_is_mounted     = false;
    var na_is_subscribed  = false;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_body()       { return document.getElementById(NA_BODY_ID); }
    function na_grid()       { return document.getElementById(NA_GRID_ID); }
    function na_search_el()  { return document.getElementById(NA_SEARCH_ID); }

    function na_swap()       { return window.Na__ProfileTools__SwapController || null; }
    function na_is_armed()   { var s = na_swap(); return !!(s && s.Na__Swap__IsArmed()); }

    function na_escape(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Toolbar HTML
    // -------------------------------------------------------------------------

    function Na__Gallery__BuildToolbarHtml() {
        var sizeLabel = NA_SIZE_LABELS[na_size_index];
        var isArmed   = na_is_armed();
        return [
            '<div class="na-gallery-toolbar">',
            '  <input id="' + NA_SEARCH_ID + '"',
            '         class="na-gallery-search"',
            '         type="text"',
            '         placeholder="Search profiles..."',
            '         value="' + na_search_query.replace(/"/g, '&quot;') + '">',
            '  <button id="' + NA_SWAP_BTN_ID + '" class="na-gallery-swap-btn naButtonSecondary"',
            '          title="Select a placed Profile Trace in the model, then click this to swap its profile for one picked here">',
            isArmed ? '&#9679; Picking…' : '&#8646; Swap Profile',
            '  </button>',
            '  <button id="' + NA_SIZE_BTN_ID + '" class="na-gallery-size-btn naButtonSecondary"',
            '          title="Cycle thumbnail size">',
            '    ' + sizeLabel,
            '  </button>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Swap Banner HTML
    // -------------------------------------------------------------------------

    // Only rendered while armed. It has to say WHICH trace is about to change,
    // because the next click is a destructive rebuild in the model and the
    // grid otherwise looks identical to its ordinary browsing state.
    function Na__Gallery__BuildSwapBannerHtml() {
        var swap = na_swap();
        if (!swap || !swap.Na__Swap__IsArmed()) return '';

        var state = swap.Na__Swap__GetState();
        var noun  = state.traceCount > 1 ? (state.traceCount + ' traces') : 'trace';

        return [
            '<div class="na-gallery-swap-banner">',
            '  <div class="na-gallery-swap-banner__text">',
            '    <span class="na-gallery-swap-banner__lead">Swapping ' + noun + '</span>',
            '    <span class="na-gallery-swap-banner__trace">' + na_escape(swap.Na__Swap__TraceLabel()) + '</span>',
            '    <span class="na-gallery-swap-banner__hint">Click a profile below to rebuild with it.</span>',
            '  </div>',
            '  <button id="' + NA_SWAP_CANCEL_ID + '" class="naButtonSecondary na-gallery-swap-banner__cancel">Cancel</button>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Grid Render
    // -------------------------------------------------------------------------

    function Na__Gallery__RenderGrid() {
        var grid = na_grid();
        if (!grid) return;

        var store    = window.Na__ProfileTools__ProfileStore;
        var renderer = window.Na__ProfileTools__Gallery__CardRenderer;
        if (!store || !renderer) {
            grid.innerHTML = '<div class="na-gallery-empty">Gallery data unavailable.</div>';
            return;
        }

        var profiles    = store.Na__Store__GetProfiles();
        var selectedKey = store.Na__Store__GetSelectedKey();
        var items       = renderer.Na__Card__FilterAndSort(profiles, na_search_query);

        if (items.length === 0) {
            grid.innerHTML = '<div class="na-gallery-empty">' +
                (na_search_query ? 'No profiles match &ldquo;' + na_search_query + '&rdquo;.' : 'No profiles loaded.') +
                '</div>';
            return;
        }

        grid.innerHTML = items.map(function (item) {
            return renderer.Na__Card__Build(item.record, item.key === selectedKey);
        }).join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Full Re-render (toolbar + grid)
    // -------------------------------------------------------------------------

    function Na__Gallery__Render() {
        var body = na_body();
        if (!body) return;

        var armedClass = na_is_armed() ? ' na-gallery-grid--swapArmed' : '';

        body.innerHTML = [
            Na__Gallery__BuildToolbarHtml(),
            Na__Gallery__BuildSwapBannerHtml(),
            '<div id="' + NA_GRID_ID + '" class="na-gallery-grid ' + NA_SIZE_CLASSES[na_size_index] + armedClass + '"></div>'
        ].join('');

        Na__Gallery__RenderGrid();
        Na__Gallery__AttachToolbarEvents();
        Na__Gallery__AttachCardEvents();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Card Events
    // -------------------------------------------------------------------------

    function Na__Gallery__AttachCardEvents() {
        var grid = na_grid();
        if (!grid) return;

        grid.addEventListener('click', function (evt) {
            var card = evt.target.closest ? evt.target.closest('[data-na-profile-key]') : Na__Gallery__FindCard(evt.target);
            if (!card) return;

            var key = card.getAttribute('data-na-profile-key');
            if (!key) return;

            var store = window.Na__ProfileTools__ProfileStore;
            var swap  = na_swap();

            // Armed: the click is a swap instruction, not a selection. The
            // store is still updated (navigate off) so every other tab shows
            // the profile the trace is being rebuilt with; the SwapController
            // owns the routing once Ruby reports back.
            if (swap && swap.Na__Swap__IsArmed()) {
                if (swap.Na__Swap__IsBusy()) return;
                if (store) store.Na__Store__SetSelected(key, { navigate: false });
                swap.Na__Swap__ApplyProfile(key);
                return;
            }

            if (store) {
                store.Na__Store__SetSelected(key, { navigate: true });
            }
        });
    }

    function Na__Gallery__FindCard(el) {
        while (el && el !== document.body) {
            if (el.getAttribute && el.getAttribute('data-na-profile-key')) return el;
            el = el.parentNode;
        }
        return null;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Toolbar Events
    // -------------------------------------------------------------------------

    function Na__Gallery__AttachToolbarEvents() {
        var searchEl = na_search_el();
        if (searchEl) {
            searchEl.addEventListener('input', function () {
                na_search_query = searchEl.value || '';
                Na__Gallery__RenderGrid();
                Na__Gallery__AttachCardEvents();
            });
        }

        var sizeBtn = document.getElementById(NA_SIZE_BTN_ID);
        if (sizeBtn) {
            sizeBtn.addEventListener('click', function () {
                na_size_index = (na_size_index + 1) % NA_SIZE_CLASSES.length;
                var grid = na_grid();
                if (grid) {
                    NA_SIZE_CLASSES.forEach(function (cls) { grid.classList.remove(cls); });
                    grid.classList.add(NA_SIZE_CLASSES[na_size_index]);
                }
                sizeBtn.textContent = NA_SIZE_LABELS[na_size_index];
            });
        }

        var swapBtn = document.getElementById(NA_SWAP_BTN_ID);
        if (swapBtn) {
            swapBtn.addEventListener('click', function () {
                var swap = na_swap();
                if (!swap) return;
                // Already armed — a second click re-reads the model selection,
                // which is how you retarget without leaving the Gallery.
                swap.Na__Swap__RequestBind();
            });
        }

        var cancelBtn = document.getElementById(NA_SWAP_CANCEL_ID);
        if (cancelBtn) {
            cancelBtn.addEventListener('click', function () {
                var swap = na_swap();
                if (swap) swap.Na__Swap__CancelArm();
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Store Subscriptions
    // -------------------------------------------------------------------------

    function Na__Gallery__OnProfilesChanged() {
        if (!na_is_mounted) return;
        Na__Gallery__Render();
    }

    // Arming, cancelling and finishing a swap all change the toolbar label and
    // the banner, so the whole panel is rebuilt rather than patched.
    function Na__Gallery__OnSwapStateChanged() {
        if (!na_is_mounted) return;
        Na__Gallery__Render();
    }

    function Na__Gallery__OnSelectedChanged(payload) {
        if (!na_is_mounted) return;
        var grid = na_grid();
        if (!grid) return;

        var cards = grid.querySelectorAll('[data-na-profile-key]');
        for (var i = 0; i < cards.length; i++) {
            var isSelected = cards[i].getAttribute('data-na-profile-key') === payload.key;
            cards[i].classList.toggle('na-gallery-card--selected', isSelected);
        }

        if (payload.navigate && window.Na_TabRouter) {
            var activeTab = window.Na_TabRouter.na_get_active_tab();
            if (activeTab === 'gallery') {
                window.Na_TabRouter.na_activateTab('apply-profile');
            }
        }
    }

    function Na__Gallery__OnMetaUpdated(payload) {
        if (!na_is_mounted) return;
        var grid = na_grid();
        if (!grid) return;

        var renderer = window.Na__ProfileTools__Gallery__CardRenderer;
        var store    = window.Na__ProfileTools__ProfileStore;
        if (!renderer || !store) return;

        var card = grid.querySelector('[data-na-profile-key="' + payload.key + '"]');
        if (!card) return;

        var selectedKey = store.Na__Store__GetSelectedKey();
        var newCardHtml = renderer.Na__Card__Build(payload.record, payload.key === selectedKey);
        var temp = document.createElement('div');
        temp.innerHTML = newCardHtml;
        var newCard = temp.firstChild;
        if (newCard) {
            card.parentNode.replaceChild(newCard, card);
            Na__Gallery__AttachCardEvents();
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle
    // -------------------------------------------------------------------------

    function na_mount() {
        na_is_mounted = true;

        var appCtx = window.Na_AppContext;
        if (appCtx && !na_is_subscribed) {
            na_is_subscribed = true;
            appCtx.na_subscribe('na_profiles_changed',     Na__Gallery__OnProfilesChanged);
            appCtx.na_subscribe('na_selected_changed',     Na__Gallery__OnSelectedChanged);
            appCtx.na_subscribe('na_profile_meta_updated', Na__Gallery__OnMetaUpdated);
            appCtx.na_subscribe('na_swap_state_changed',   Na__Gallery__OnSwapStateChanged);
        }

        Na__Gallery__Render();
    }

    function na_unmount() {
        na_is_mounted = false;
        var body = na_body();
        if (body) body.innerHTML = '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__Gallery__Tab = {
        na_mount:   na_mount,
        na_unmount: na_unmount
    };

    // endregion ----------------------------------------------------------------
})();
