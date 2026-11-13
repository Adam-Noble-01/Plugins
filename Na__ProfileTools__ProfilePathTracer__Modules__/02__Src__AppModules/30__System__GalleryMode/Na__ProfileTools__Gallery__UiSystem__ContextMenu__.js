/* =============================================================================
   NA PROFILE TOOLS - GALLERY MODE - UI SYSTEM - CONTEXT MENU
   =============================================================================
   FILE       : Na__ProfileTools__Gallery__UiSystem__ContextMenu__.js
   NAMESPACE  : window.Na__ProfileTools__Gallery__ContextMenu
   PURPOSE    : The right-click menu on a Gallery card (v1.6.18). Each item opens
                a tab with THAT profile already chosen and the job started:

                  Apply Profile To Selection  Apply Profile, Use current selection,
                                              Generate: previews the profile along
                                              the edges selected in the model
                  Create Profile Interactive  Apply Profile, Interactive path
                                              picking, Generate: the trace tool
                  -------------------------
                  Edit Profile Information    Edit Profile (names, keywords, datum)
                  Edit Profile Geometry       Draw Profile, the 2D editor

   WHY        : A card click picks the profile and routes to Apply Profile, and
                the user still had to set the path mode and press Generate, or
                find the Edit and Draw tabs and check they showed the right
                profile. The menu names what can be done to THIS profile and does
                all of it in one go (Adam, 13-Nov-2026: "an intuitive pathway").

   OWNS NOTHING
                Every item calls the tab that does the work: Apply Profile's
                na_start_from_gallery, the store and router for Edit Profile, Draw
                Profile's na_open_profile. This file only builds, places and
                closes the menu, so each journey still has one implementation.

   A RIGHT-CLICK DOES NOT SELECT
                The card is outlined while its menu is open, but the store only
                changes when an item runs: dismissing the menu leaves every tab
                exactly as it was.
   ============================================================================= */

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var NA_MENU_ID           = 'na-gallery-ctx-menu';
    var NA_TARGET_CLASS      = 'na-gallery-card--ctxTarget';
    var NA_VIEWPORT_MARGIN   = 4;      // px kept clear of the dialog edge

    var na_menu_el     = null;         // the open menu, or null
    var na_target_key  = '';           // profile key the open menu acts on
    var na_target_card = null;         // card outlined while the menu is open

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Collaborators
    // -------------------------------------------------------------------------

    function na_store()    { return window.Na__ProfileTools__ProfileStore || null; }
    function na_router()   { return window.Na_TabRouter || null; }
    function na_swap()     { return window.Na__ProfileTools__SwapController || null; }
    function na_apply()    { return window.Na__ProfileTools__ApplyProfile__Tab || null; }
    function na_draw()     { return window.Na__ProfileTools__DrawProfile__Tab || null; }
    function na_edit()     { return window.Na__ProfileTools__EditProfile__Tab || null; }

    function na_status(message) {
        if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__SetStatus(message);
        }
    }

    function na_escape(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function na_label(profileKey) {
        var store  = na_store();
        var record = store ? store.Na__Store__GetProfile(profileKey) : null;
        if (!record) return profileKey || '';
        return store.Na__Store__ProfileLabel(record) || profileKey;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Line Icons (16 px, stroke only, currentColor)
    // -------------------------------------------------------------------------

    // Linework in the house manner: round caps and joins, no fills, so each
    // icon takes the item's text colour (navy, accent on hover, grey disabled).
    var NA_ICON_PATHS = {
        // A run of selected edges: the polyline the profile will follow, its
        // end vertices marked the way a selection shows them.
        'apply-selection':
            '<path d="M2.5 12.5 L6.5 7.5 L10 9.5 L13.5 4"/>' +
            '<rect x="1" y="11" width="3" height="3" rx="0.4"/>' +
            '<rect x="12" y="2.5" width="3" height="3" rx="0.4"/>',
        // A path being clicked out: two placed waypoints and the pen still drawing.
        'apply-interactive':
            '<path d="M2 14 L5.5 9.5 L8.5 11"/>' +
            '<circle cx="5.5" cy="9.5" r="0.9"/>' +
            '<path d="M8.5 11 L13.6 5.9 L11.6 3.9 L6.5 9 Z"/>' +
            '<path d="M12.4 3.1 L14.4 5.1"/>',
        // Information: the profile's names, keywords and datum.
        'edit-info':
            '<circle cx="8" cy="8" r="6.2"/>' +
            '<path d="M8 7.3 V11.4"/>' +
            '<path d="M8 4.7 V4.75"/>',
        // Geometry: a moulding section with handles on its vertices.
        'edit-geometry':
            '<path d="M3 13.5 V2.5 H7 C7 6 9 7.5 13 7.5 V13.5 Z"/>' +
            '<rect x="1.8" y="1.3" width="2.4" height="2.4" rx="0.3"/>' +
            '<rect x="11.8" y="6.3" width="2.4" height="2.4" rx="0.3"/>'
    };

    function na_icon(action) {
        return '<svg class="na-gallery-ctx-menu__icon" viewBox="0 0 16 16" aria-hidden="true" ' +
               'fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">' +
               (NA_ICON_PATHS[action] || '') + '</svg>';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Menu Items
    // -------------------------------------------------------------------------

    // Built per open, because what is available depends on the moment: a trace
    // mid-rebuild blocks the Apply items, and a missing tab module (a failed
    // script after a reload) greys its item instead of letting it fail silently.
    function na_build_items() {
        var swap      = na_swap();
        var isBusy    = !!(swap && swap.Na__Swap__IsBusy());
        var isBound   = !!(swap && (swap.Na__Swap__IsBound() || swap.Na__Swap__IsArmed()));
        var hasApply  = !!(na_apply() && typeof na_apply().na_start_from_gallery === 'function');
        var hasDraw   = !!(na_draw() && typeof na_draw().na_open_profile === 'function');
        var hasEdit   = !!na_edit();

        var applyBlock = isBusy   ? 'A trace is rebuilding. Wait for it to finish.'
                       : !hasApply ? 'The Apply Profile tab is not loaded. Reload the plugin, then reopen the dialog.'
                       : '';
        var unbindNote = isBound ? ' The trace bound to Apply Profile is unbound first (the model is not changed).' : '';

        return [
            {
                action   : 'apply-selection',
                label    : 'Apply Profile To Selection',
                disabled : applyBlock,
                title    : 'Opens Apply Profile with this profile on Use current selection and previews it along the edges ' +
                           'selected in the model. Nothing is built until you Commit.' + unbindNote
            },
            {
                action   : 'apply-interactive',
                label    : 'Create Profile Interactive',
                disabled : applyBlock,
                title    : 'Opens Apply Profile with this profile and starts the interactive trace tool: click the path ' +
                           'out in the viewport.' + unbindNote
            },
            { separator : true },
            {
                action   : 'edit-info',
                label    : 'Edit Profile Information',
                disabled : hasEdit ? '' : 'The Edit Profile tab is not loaded. Reload the plugin, then reopen the dialog.',
                title    : 'Opens this profile in Edit Profile: name, short name, keywords, description, datum and file.'
            },
            {
                action   : 'edit-geometry',
                label    : 'Edit Profile Geometry',
                disabled : hasDraw ? '' : 'The Draw Profile editor is not loaded. Reload the plugin, then reopen the dialog.',
                title    : 'Opens this profile in the Draw Profile 2D editor. Save writes it back to the library.'
            }
        ];
    }

    function na_build_menu_html(profileKey) {
        var rows = na_build_items().map(function (item) {
            if (item.separator) return '<div class="na-gallery-ctx-menu__sep" role="separator"></div>';
            var isDisabled = !!item.disabled;
            return [
                '<button type="button" class="na-gallery-ctx-menu__item" role="menuitem"',
                '        data-na-ctx-action="' + item.action + '"',
                '        title="' + na_escape(isDisabled ? item.disabled : item.title) + '"',
                isDisabled ? ' disabled aria-disabled="true"' : '',
                '>',
                na_icon(item.action),
                '<span class="na-gallery-ctx-menu__label">' + na_escape(item.label) + '</span>',
                '</button>'
            ].join('');
        }).join('');

        return '<div class="na-gallery-ctx-menu__head">' + na_escape(na_label(profileKey)) + '</div>' + rows;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Placement
    // -------------------------------------------------------------------------

    // At the cursor, flipped to the cursor's other side when it would run off
    // the right or bottom edge, then clamped, so the whole menu is always on
    // screen however small the dialog is.
    function na_place(menuEl, clientX, clientY) {
        menuEl.style.left = '0px';
        menuEl.style.top  = '0px';

        var width   = menuEl.offsetWidth;
        var height  = menuEl.offsetHeight;
        var viewW   = window.innerWidth  || document.documentElement.clientWidth;
        var viewH   = window.innerHeight || document.documentElement.clientHeight;
        var margin  = NA_VIEWPORT_MARGIN;

        var left = clientX;
        var top  = clientY;
        if (left + width  > viewW - margin) left = clientX - width;
        if (top  + height > viewH - margin) top  = clientY - height;
        left = Math.max(margin, Math.min(left, viewW - width  - margin));
        top  = Math.max(margin, Math.min(top,  viewH - height - margin));

        menuEl.style.left = Math.round(left) + 'px';
        menuEl.style.top  = Math.round(top)  + 'px';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Open / Close
    // -------------------------------------------------------------------------

    function Na__CtxMenu__Open(clientX, clientY, profileKey, cardEl) {
        Na__CtxMenu__Close();

        var store = na_store();
        if (!profileKey || !store || !store.Na__Store__GetProfile(profileKey)) return false;

        var menuEl = document.createElement('div');
        menuEl.id        = NA_MENU_ID;
        menuEl.className = 'na-gallery-ctx-menu';
        menuEl.setAttribute('role', 'menu');
        menuEl.setAttribute('tabindex', '-1');
        menuEl.setAttribute('aria-label', 'Profile actions');
        menuEl.innerHTML = na_build_menu_html(profileKey);
        document.body.appendChild(menuEl);

        na_menu_el     = menuEl;
        na_target_key  = profileKey;
        na_target_card = cardEl || null;
        if (na_target_card) na_target_card.classList.add(NA_TARGET_CLASS);

        na_place(menuEl, clientX, clientY);

        menuEl.addEventListener('click', na_on_menu_click);
        menuEl.addEventListener('contextmenu', na_on_menu_contextmenu);
        document.addEventListener('mousedown', na_on_document_mousedown, true);
        document.addEventListener('keydown',   na_on_document_keydown,   true);
        document.addEventListener('scroll',    Na__CtxMenu__Close,       true);
        window.addEventListener('resize', Na__CtxMenu__Close);
        window.addEventListener('blur',   Na__CtxMenu__Close);

        // The menu itself takes focus, not its first item: opened by the mouse,
        // nothing should look hovered yet. The arrow keys move onto the items.
        try { menuEl.focus(); } catch (err) { /* focus is a nicety */ }
        return true;
    }

    function Na__CtxMenu__Close() {
        if (!na_menu_el) return;

        var menuEl = na_menu_el;
        na_menu_el = null;

        menuEl.removeEventListener('click', na_on_menu_click);
        menuEl.removeEventListener('contextmenu', na_on_menu_contextmenu);
        document.removeEventListener('mousedown', na_on_document_mousedown, true);
        document.removeEventListener('keydown',   na_on_document_keydown,   true);
        document.removeEventListener('scroll',    Na__CtxMenu__Close,       true);
        window.removeEventListener('resize', Na__CtxMenu__Close);
        window.removeEventListener('blur',   Na__CtxMenu__Close);

        if (menuEl.parentNode) menuEl.parentNode.removeChild(menuEl);
        if (na_target_card) na_target_card.classList.remove(NA_TARGET_CLASS);
        na_target_card = null;
        na_target_key  = '';
    }

    function Na__CtxMenu__IsOpen() { return !!na_menu_el; }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Menu Events
    // -------------------------------------------------------------------------

    function na_on_menu_click(evt) {
        var btn = evt.target.closest ? evt.target.closest('[data-na-ctx-action]') : null;
        if (!btn || btn.disabled) return;
        evt.stopPropagation();

        var action     = btn.getAttribute('data-na-ctx-action');
        var profileKey = na_target_key;
        // Closed first: an action routes to another tab, and the Gallery's
        // unmount must not find a menu still pointing at a card it is clearing.
        Na__CtxMenu__Close();
        Na__CtxMenu__Run(action, profileKey);
    }

    // No browser menu on top of ours.
    function na_on_menu_contextmenu(evt) { evt.preventDefault(); }

    // Capture phase, so a press anywhere else closes the menu before that
    // element reacts. A right press on another card closes this one and the
    // Gallery's contextmenu handler then opens that card's.
    function na_on_document_mousedown(evt) {
        if (na_menu_el && na_menu_el.contains(evt.target)) return;
        Na__CtxMenu__Close();
    }

    function na_enabled_items() {
        if (!na_menu_el) return [];
        return Array.prototype.filter.call(
            na_menu_el.querySelectorAll('.na-gallery-ctx-menu__item'),
            function (btn) { return !btn.disabled; }
        );
    }

    // Captured and stopped, so while the menu is open its keys never reach the
    // Apply tab's live-tool hotkeys or a focused search box. Enter and Space
    // press the focused item through the button's own behaviour.
    function na_on_document_keydown(evt) {
        if (!na_menu_el) return;
        var key = evt.key;

        if (key === 'Escape') {
            evt.preventDefault();
            evt.stopPropagation();
            Na__CtxMenu__Close();
            return;
        }

        if (key === 'Tab') {
            evt.preventDefault();
            evt.stopPropagation();
            Na__CtxMenu__Close();
            return;
        }

        if (key !== 'ArrowDown' && key !== 'ArrowUp' && key !== 'Home' && key !== 'End') return;
        evt.preventDefault();
        evt.stopPropagation();

        var items = na_enabled_items();
        if (items.length === 0) return;
        var index = items.indexOf(document.activeElement);

        if (key === 'Home')           index = 0;
        else if (key === 'End')       index = items.length - 1;
        else if (key === 'ArrowDown') index = index < 0 ? 0 : (index + 1) % items.length;
        else                          index = index < 0 ? items.length - 1 : (index - 1 + items.length) % items.length;

        items[index].focus();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Actions
    // -------------------------------------------------------------------------

    // Public, so another surface (a keyboard shortcut, an agent test) can run
    // the same four journeys without opening the menu.
    function Na__CtxMenu__Run(action, profileKey) {
        var store = na_store();
        if (!store || !store.Na__Store__GetProfile(profileKey)) {
            na_status('That profile is no longer in the library.');
            return false;
        }

        var label = na_label(profileKey);

        switch (action) {
            case 'apply-selection':
            case 'apply-interactive': {
                var apply = na_apply();
                if (!apply || typeof apply.na_start_from_gallery !== 'function') {
                    na_status('The Apply Profile tab is not loaded. Reload the plugin, then reopen the dialog.');
                    return false;
                }
                return apply.na_start_from_gallery(profileKey, action === 'apply-selection' ? 'selection' : 'interactive');
            }

            case 'edit-info': {
                var router = na_router();
                if (!router || !na_edit()) {
                    na_status('The Edit Profile tab is not loaded. Reload the plugin, then reopen the dialog.');
                    return false;
                }
                // navigate: false, or the Gallery's own selection handler would
                // route to Apply Profile first.
                store.Na__Store__SetSelected(profileKey, { navigate: false });
                router.na_activateTab('edit-profile');
                na_status('Editing the information of "' + label + '".');
                return true;
            }

            case 'edit-geometry': {
                var draw = na_draw();
                if (!draw || typeof draw.na_open_profile !== 'function') {
                    na_status('The Draw Profile editor is not loaded. Reload the plugin, then reopen the dialog.');
                    return false;
                }
                // Selected in the store as well, so Apply and Edit agree with
                // what is open in the editor when the user moves on to them.
                store.Na__Store__SetSelected(profileKey, { navigate: false });
                // unbind: this edits the LIBRARY profile. A trace the editor
                // was bound to must not take the next change.
                draw.na_open_profile(profileKey, { unbind: true });
                return true;
            }

            default:
                return false;
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__Gallery__ContextMenu = {
        Na__CtxMenu__Open   : Na__CtxMenu__Open,
        Na__CtxMenu__Close  : Na__CtxMenu__Close,
        Na__CtxMenu__IsOpen : Na__CtxMenu__IsOpen,
        Na__CtxMenu__Run    : Na__CtxMenu__Run
    };

    // endregion ----------------------------------------------------------------
})();
