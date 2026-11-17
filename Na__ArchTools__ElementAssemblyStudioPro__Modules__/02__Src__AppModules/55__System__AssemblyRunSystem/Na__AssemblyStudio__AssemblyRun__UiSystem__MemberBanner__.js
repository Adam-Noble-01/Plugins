// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - MEMBER BANNER
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AssemblyRun__UiSystem__MemberBanner__.js
// NAMESPACE  : Na_RunMemberBanner (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : Says, in whichever tab an element is being edited, that it is a
//              panel of an Assembly Run: "Editing panel type A of ARN001 - 4
//              spans share it, and a change here changes them all". Carries
//              the panel's commands: Make Panel Unique, Recode, Change Type.
// CREATED    : 16-Nov-2026 (V2.7.0)
//
// WHY A BANNER
// - A conservatory has many panels alike. Each span of panel type A is an
//   instance of ONE element, so editing the one selected edits every span of
//   the type. That is the point of a panel type, and the user must be told
//   before changing it, in the tab where the change is made.
//
// RUBY -> JS (Na__AssemblyRunSystem::Na__DialogRouter.na_selection_changed)
//   window.na_setRunMember(json)   { runId, runName, type, leg, span, copies, types,
//                                    product, auto, products: [{ key, label }] }
//   window.na_clearRunMember()
// JS -> RUBY
//   sketchup.na_runMakeUnique / na_runRecode / na_runSetSpanType / na_runSelectRun
//   sketchup.na_runSetSpanProduct / na_runSetTypeProduct   (V2.7.2: another kind
//   of panel for this span, or for every span of its type; built at once)
//
// NAMING CONVENTION:
// - All custom identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Na_RunMemberBanner = {};
    var NA_BAR_ID          = 'na-run-member-bar';
    var NA_HOST_TABS       = ['windows', 'doors', 'cabinets'];                  // <-- Tabs an element is edited in
    var na_member          = null;                                              // <-- The payload last received, or null

    // -----------------------------------------------------------------------
    // REGION | Helpers
    // -----------------------------------------------------------------------

    function na_bar() { return document.getElementById(NA_BAR_ID); }

    function na_send(callback, payload) {
        if (typeof sketchup === 'undefined' || typeof sketchup[callback] !== 'function') {
            console.warn('[Na_RunMemberBanner] sketchup.' + callback + ' unavailable');
            return;
        }
        sketchup[callback](JSON.stringify(payload));
    }

    function na_text(id, value) {
        var el = document.getElementById(id);
        if (el) el.textContent = value;
    }

    // HELPER FUNCTION | "L1S2": the Span's Key as the Run Tab Shows It
    // ---------------------------------------------------------------
    function na_span_key(member) {
        return 'L' + (member.leg + 1) + 'S' + (member.span + 1);
    }

    // -----------------------------------------------------------------------
    // REGION | Commands
    // -----------------------------------------------------------------------

    Na_RunMemberBanner.na_make_unique = function () {
        if (!na_member || na_member.copies < 2) return;
        na_send('na_runMakeUnique', { runId: na_member.runId, leg: na_member.leg, span: na_member.span });
    };

    Na_RunMemberBanner.na_recode = function (code) {
        if (!na_member || !code) return;
        na_send('na_runRecode', { runId: na_member.runId, leg: na_member.leg, span: na_member.span, from: na_member.type, to: code });
    };

    Na_RunMemberBanner.na_set_type = function (code) {
        if (!na_member || !code) return;
        na_send('na_runSetSpanType', { runId: na_member.runId, leg: na_member.leg, span: na_member.span, code: code });
    };

    // Another kind of panel (V2.7.2): this span alone. A span that shares
    // its type takes a new type; one with its type to itself changes it.
    Na_RunMemberBanner.na_set_product = function (product) {
        if (!na_member || !product) return;
        na_send('na_runSetSpanProduct', { runId: na_member.runId, leg: na_member.leg, span: na_member.span, product: product });
    };

    // ... or every span of its type.
    Na_RunMemberBanner.na_set_type_product = function (product) {
        if (!na_member || !product) return;
        na_send('na_runSetTypeProduct', { runId: na_member.runId, leg: na_member.leg, span: na_member.span, code: na_member.type, product: product });
    };

    Na_RunMemberBanner.na_show_run = function () {
        if (na_member) na_send('na_runSelectRun', { runId: na_member.runId });
    };

    // FUNCTION | The Panel's Menu Entries (Also Used by the Banner's Own Buttons)
    // ---------------------------------------------------------------
    Na_RunMemberBanner.na_menu_entries = function () {
        if (!na_member) return [];
        var others = (na_member.types || []).filter(function (code) { return code !== na_member.type; });
        var entries = [
            { heading: 'Panel type ' + na_member.type + '  ·  ' + na_member.runId + ' ' + na_span_key(na_member) },
            { label: 'Make Panel Unique', hint: na_member.copies < 2 ? 'already the only one' : 'a new type, a copy of ' + na_member.type,
              disabled: na_member.copies < 2, run: Na_RunMemberBanner.na_make_unique },
            { label: 'Recode Panel Type…', hint: 'all ' + na_member.copies,
              input: { value: na_member.type, placeholder: 'A, B2, DR1', apply: Na_RunMemberBanner.na_recode } }
        ];
        if (others.length) entries.push({ separator: true });
        others.forEach(function (code) {
            entries.push({ label: 'Change This Panel to Type ' + code, run: function () { Na_RunMemberBanner.na_set_type(code); } });
        });

        // Another kind of panel (V2.7.2), as the Assembly Runs tab's own menu
        // offers it. Here the run is rebuilt at once, as one undo step.
        var shared = na_member.copies > 1;
        var kinds  = (na_member.products || []).filter(function (item) { return item.key !== na_member.product; });
        if (kinds.length) {
            entries.push({ separator: true });
            entries.push({ label: 'Change This Panel to', hint: shared ? 'a new type' : 'type ' + na_member.type + ' changes',
                           choices: kinds.map(function (item) {
                               return { label: item.label, run: function () { Na_RunMemberBanner.na_set_product(item.key); } };
                           }) });
            if (shared && !na_member.auto) {
                entries.push({ label: 'Change All ' + na_member.copies + ' of Type ' + na_member.type + ' to', hint: 'type ' + na_member.type + ' changes',
                               choices: kinds.map(function (item) {
                                   return { label: item.label, run: function () { Na_RunMemberBanner.na_set_type_product(item.key); } };
                               }) });
            }
        }
        entries.push({ separator: true });
        entries.push({ label: 'Show the Run', hint: na_member.runId, run: Na_RunMemberBanner.na_show_run });
        return entries;
    };

    function na_open_menu(event) {
        if (!na_member || typeof Na_RunContextMenu === 'undefined') return;
        event.preventDefault();
        Na_RunContextMenu.na_open(event.clientX, event.clientY, Na_RunMemberBanner.na_menu_entries());
    }

    // -----------------------------------------------------------------------
    // REGION | Ruby -> JS
    // -----------------------------------------------------------------------

    // FUNCTION | The Element Selected Is a Panel of a Run
    // ---------------------------------------------------------------
    window.na_setRunMember = function (json) {
        try { na_member = (typeof json === 'string') ? JSON.parse(json) : json; }
        catch (err) { console.warn('[Na_RunMemberBanner] unreadable member payload', err); return; }
        var bar = na_bar();
        if (!bar || !na_member) return;

        var shared = na_member.copies > 1;
        na_text('na-run-member-code', na_member.type);
        na_text('na-run-member-text', shared
            ? na_member.copies + ' spans of ' + na_member.runId + ' share this panel type: a change here changes them all.'
            : 'The only span of this type in ' + na_member.runId + ' (' + na_span_key(na_member) + ').');
        var unique = document.getElementById('na-run-member-unique');
        if (unique) unique.disabled = !shared;
        bar.classList.remove('na-hidden');
        bar.title = (na_member.runName || na_member.runId) + ' · right-click for the panel\'s commands';
    };

    // FUNCTION | The Selection Is No Panel of a Run
    // ---------------------------------------------------------------
    window.na_clearRunMember = function () {
        na_member = null;
        var bar = na_bar();
        if (bar) bar.classList.add('na-hidden');
    };

    Na_RunMemberBanner.na_get_member = function () { return na_member; };

    // -----------------------------------------------------------------------
    // REGION | Bootstrap
    // -----------------------------------------------------------------------

    // The banner's own buttons, and a right-click on it or on the selected
    // element's strip of any element tab.
    function na_wire() {
        var bar = na_bar();
        if (!bar) return;
        bar.addEventListener('contextmenu', na_open_menu);
        var unique = document.getElementById('na-run-member-unique');
        var more   = document.getElementById('na-run-member-more');
        var show   = document.getElementById('na-run-member-show');
        if (unique) unique.addEventListener('click', Na_RunMemberBanner.na_make_unique);
        if (show)   show.addEventListener('click', Na_RunMemberBanner.na_show_run);
        if (more)   more.addEventListener('click', function (event) {
            var box = more.getBoundingClientRect();
            if (typeof Na_RunContextMenu !== 'undefined') Na_RunContextMenu.na_open(box.left, box.bottom + 4, Na_RunMemberBanner.na_menu_entries());
            event.stopPropagation();
        });
        NA_HOST_TABS.forEach(function (tabId) {
            var strip = document.querySelector('#na-tab-' + tabId + ' .na-selected-strip');
            if (strip) strip.addEventListener('contextmenu', na_open_menu);
        });
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', na_wire);
    else na_wire();

    window.Na_RunMemberBanner = Na_RunMemberBanner;
})();
