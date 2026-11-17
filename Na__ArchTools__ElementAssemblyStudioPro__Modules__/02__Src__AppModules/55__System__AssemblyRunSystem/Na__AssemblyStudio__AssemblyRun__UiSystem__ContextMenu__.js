// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - CONTEXT MENU
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AssemblyRun__UiSystem__ContextMenu__.js
// NAMESPACE  : Na_RunContextMenu (browser global)
// AUTHOR     : Noble Architecture
// PURPOSE    : The dialog's own right-click menu. Takes the place of the
//              browser's (Back, Reload, Print, Inspect), which has no business
//              in a plugin dialog, and gives a panel its own commands: Make
//              Panel Unique, Recode Panel Type, Change to Type.
// CREATED    : 16-Nov-2026 (V2.7.0)
//
// WHAT IT DOES
// - Stops the browser's context menu everywhere in the dialog except inside
//   a text field, where Cut / Copy / Paste are worth keeping.
// - Na_RunContextMenu.na_open(x, y, entries) shows a menu at the pointer.
//   An entry is one of:
//     { heading: 'Panel type A' }                       a title row
//     { label, hint, disabled, run: function () {} }    a command
//     { label, input: { value, placeholder, apply } }   a command that asks for
//                                                       one short text first
//     { label, hint, choices: [{ label, title, run }] } a label with one small
//                                                       button per choice under
//                                                       it (V2.7.2: "Change
//                                                       This Panel to", then
//                                                       each product)
//     { separator: true }
// - It closes on a click elsewhere, Escape, a scroll, or once a command runs.
//
// NAMING CONVENTION:
// - All custom identifiers use Na_ / na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    var Na_RunContextMenu = {};
    var NA_MENU_ID        = 'na-run-menu';
    var NA_EDGE_MARGIN_PX = 8;
    var na_menu_el        = null;

    // -----------------------------------------------------------------------
    // REGION | Building the menu
    // -----------------------------------------------------------------------

    function na_el(tag, className, text) {
        var el = document.createElement(tag);
        if (className) el.className = className;
        if (text !== undefined && text !== null) el.textContent = text;
        return el;
    }

    // HELPER FUNCTION | One Command Row
    // ---------------------------------------------------------------
    function na_command_row(entry) {
        var row = na_el('button', 'na-run-menu__item');
        row.type = 'button';
        row.appendChild(na_el('span', 'na-run-menu__label', entry.label));
        if (entry.hint) row.appendChild(na_el('span', 'na-run-menu__hint', entry.hint));
        if (entry.disabled) {
            row.disabled = true;
            return row;
        }
        row.addEventListener('click', function () {
            if (entry.input) { na_show_input(row, entry); return; }
            Na_RunContextMenu.na_close();
            entry.run();
        });
        return row;
    }

    // HELPER FUNCTION | A Label With a Button per Choice Under It
    // ---------------------------------------------------------------
    // One click picks: a submenu would cost a second aim for six choices.
    function na_choice_row(entry) {
        var row  = na_el('div', 'na-run-menu__choices');
        var head = na_el('div', 'na-run-menu__choices-head');
        head.appendChild(na_el('span', 'na-run-menu__label', entry.label));
        if (entry.hint) head.appendChild(na_el('span', 'na-run-menu__hint', entry.hint));
        row.appendChild(head);

        var list = na_el('div', 'na-run-menu__choice-list');
        (entry.choices || []).forEach(function (choice) {
            var button = na_el('button', 'na-run-menu__choice', choice.label);
            button.type = 'button';
            if (choice.title) button.title = choice.title;
            if (choice.disabled) {
                button.disabled = true;
            } else {
                button.addEventListener('click', function () {
                    Na_RunContextMenu.na_close();
                    choice.run();
                });
            }
            list.appendChild(button);
        });
        row.appendChild(list);
        return row;
    }

    // HELPER FUNCTION | Swap a Command Row for a Short Text Field and OK
    // ---------------------------------------------------------------
    // window.prompt is unreliable in an HtmlDialog, so the question is asked
    // in the menu itself. Enter applies, Escape closes.
    function na_show_input(row, entry) {
        var form  = na_el('div', 'na-run-menu__ask');
        var field = na_el('input', 'na-run-menu__field');
        var ok    = na_el('button', 'na-run-menu__ok', 'OK');
        field.type        = 'text';
        field.value       = entry.input.value || '';
        field.placeholder = entry.input.placeholder || '';
        field.maxLength   = entry.input.maxLength || 6;
        ok.type           = 'button';
        function na_apply() {
            var value = field.value.trim();
            if (!value) { field.focus(); return; }
            Na_RunContextMenu.na_close();
            entry.input.apply(value);
        }
        ok.addEventListener('click', na_apply);
        field.addEventListener('keydown', function (event) {
            if (event.key === 'Enter') { event.preventDefault(); na_apply(); }
        });
        form.appendChild(na_el('span', 'na-run-menu__label', entry.label));
        form.appendChild(field);
        form.appendChild(ok);
        row.parentNode.replaceChild(form, row);
        field.focus();
        field.select();
    }

    // HELPER FUNCTION | Keep the Menu Inside the Dialog
    // ---------------------------------------------------------------
    function na_place(menu, x, y) {
        var width  = menu.offsetWidth;
        var height = menu.offsetHeight;
        var left   = Math.min(x, window.innerWidth  - width  - NA_EDGE_MARGIN_PX);
        var top    = Math.min(y, window.innerHeight - height - NA_EDGE_MARGIN_PX);
        menu.style.left = Math.max(NA_EDGE_MARGIN_PX, left) + 'px';
        menu.style.top  = Math.max(NA_EDGE_MARGIN_PX, top)  + 'px';
    }

    // -----------------------------------------------------------------------
    // REGION | Public API
    // -----------------------------------------------------------------------

    // FUNCTION | Show a Menu at the Pointer
    // ---------------------------------------------------------------
    Na_RunContextMenu.na_open = function (x, y, entries) {
        Na_RunContextMenu.na_close();
        var menu = na_el('div', 'na-run-menu');
        menu.id = NA_MENU_ID;
        menu.setAttribute('role', 'menu');
        (entries || []).forEach(function (entry) {
            if (!entry) return;
            if (entry.separator)    menu.appendChild(na_el('div', 'na-run-menu__sep'));
            else if (entry.heading) menu.appendChild(na_el('div', 'na-run-menu__heading', entry.heading));
            else if (entry.choices) menu.appendChild(na_choice_row(entry));
            else                    menu.appendChild(na_command_row(entry));
        });
        document.body.appendChild(menu);
        na_place(menu, x, y);
        na_menu_el = menu;
    };

    // FUNCTION | Close the Menu (When One Is Open)
    // ---------------------------------------------------------------
    Na_RunContextMenu.na_close = function () {
        if (na_menu_el && na_menu_el.parentNode) na_menu_el.parentNode.removeChild(na_menu_el);
        na_menu_el = null;
    };

    Na_RunContextMenu.na_is_open = function () { return !!na_menu_el; };

    // -----------------------------------------------------------------------
    // REGION | Dialog-wide wiring
    // -----------------------------------------------------------------------

    function na_is_text_field(target) {
        if (!target || !target.tagName) return false;
        var tag = target.tagName.toLowerCase();
        if (tag === 'textarea') return true;
        return tag === 'input' && /^(text|search|number|email|url|tel|password)$/.test(target.type || 'text');
    }

    // The browser's own menu never shows, except in a text field outside our
    // menu. An element that wants our menu handles contextmenu itself first
    // (and calls na_open); this listener then only stops the default.
    document.addEventListener('contextmenu', function (event) {
        if (na_is_text_field(event.target) && !(na_menu_el && na_menu_el.contains(event.target))) return;
        event.preventDefault();
    });

    document.addEventListener('mousedown', function (event) {
        if (na_menu_el && !na_menu_el.contains(event.target)) Na_RunContextMenu.na_close();
    }, true);

    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape' && na_menu_el) Na_RunContextMenu.na_close();
    });

    window.addEventListener('blur',   Na_RunContextMenu.na_close);
    window.addEventListener('resize', Na_RunContextMenu.na_close);
    document.addEventListener('scroll', Na_RunContextMenu.na_close, true);

    window.Na_RunContextMenu = Na_RunContextMenu;
})();
