/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - UI SYSTEM - MAIN UI LOGIC
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__UiSystem__MainUiLogic__.js
   NAMESPACE  : window.Na__ProfileTools__DrawProfile__Tab
   PURPOSE    : The Draw Profile tab: the page around the editor - the tool
                palette, the top bar, the inspector (properties, profile check,
                grid and snap), the bound-trace strip, and the save / update
                panel - and the round trips to SketchUp.

   JOURNEYS
     Draw a new profile   New -> draw -> Save -> "Save as a new profile".
     Edit a library one   Open -> edit -> Save -> over it (a .bak is kept)
                          or as a new variant.
     Edit a placed trace  Select it in the model -> Edit Profile (Apply tab)
                          or From Model (here) -> its profile opens and the
                          trace is bound -> edit -> Update Trace: saved to the
                          library (new variant or over the original) and the
                          trace rebuilt with it.
     Trace a face         Select a face in the model -> From Model: its outline
                          opens (SketchUp arcs come through as arcs).
     Paint edges          Edge Paint tab (or B): the SSOT edge colours; an
                          edge's colour goes on its lines at the ends and every
                          mitre, a vertex's on the line it sweeps along the path.
   ============================================================================= */

(function () {
    'use strict';

    var C     = window.Na__DrawProfile__Config;
    var G     = window.Na__DrawProfile__Geom;
    var D     = window.Na__DrawProfile__Doc;
    var L     = window.Na__DrawProfile__Loop;
    var V     = window.Na__DrawProfile__View;
    var Ed    = window.Na__DrawProfile__Editor;
    var Tools = window.Na__DrawProfile__Tools;

    var BODY_ID = 'na-draw-profile-tab-body';

    // -------------------------------------------------------------------------
    // REGION | Icons (20 x 20, stroked in currentColor)
    // -------------------------------------------------------------------------

    var ICONS = {
        select    : '<path d="M5 2.8 L5 16 L8.6 12.6 L11.1 17.6 L13.2 16.6 L10.7 11.6 L15.2 11.6 Z" fill="currentColor" stroke="none"/>',
        vertex    : '<path d="M4 15 L10 5 L16 13"/><rect x="2.5" y="13.5" width="3" height="3" fill="#fff"/><rect x="8.5" y="3.5" width="3" height="3" fill="#fff"/><rect x="14.5" y="11.5" width="3" height="3" fill="#fff"/>',
        line      : '<path d="M4 16 L16 4"/><circle cx="4" cy="16" r="1.6" fill="currentColor"/><circle cx="16" cy="4" r="1.6" fill="currentColor"/>',
        rectangle : '<rect x="3.5" y="5.5" width="13" height="9"/>',
        arc       : '<path d="M3.5 15 A8.5 8.5 0 0 1 16.5 15"/><circle cx="3.5" cy="15" r="1.5" fill="currentColor"/><circle cx="16.5" cy="15" r="1.5" fill="currentColor"/>',
        circle    : '<circle cx="10" cy="10" r="6.5"/><circle cx="10" cy="10" r="1" fill="currentColor"/>',
        move      : '<path d="M10 2.5 V17.5 M2.5 10 H17.5 M10 2.5 L7.8 4.7 M10 2.5 L12.2 4.7 M10 17.5 L7.8 15.3 M10 17.5 L12.2 15.3 M2.5 10 L4.7 7.8 M2.5 10 L4.7 12.2 M17.5 10 L15.3 7.8 M17.5 10 L15.3 12.2"/>',
        rotate    : '<path d="M15.6 9.2 A5.8 5.8 0 1 0 13.2 14.4"/><path d="M15.8 4.6 V9.2 H11.2"/>',
        mirror    : '<path d="M10 2.5 V17.5" stroke-dasharray="2 1.6"/><path d="M7.8 5.5 L3.2 14.5 H7.8 Z"/><path d="M12.2 5.5 L16.8 14.5 H12.2 Z"/>',
        scale     : '<rect x="3" y="9" width="8" height="8"/><path d="M7 13 L16 4 M11.2 4 H16 V8.8"/>',
        offset    : '<path d="M3 16 V11 A7 7 0 0 1 10 4 H17"/><path d="M6.2 16 V11 A3.8 3.8 0 0 1 10 7.2 H17" stroke-dasharray="2.2 1.6"/>',
        trim      : '<path d="M11 3 V17"/><path d="M3 10 H11"/><path d="M11 10 H17" stroke-dasharray="1.8 1.6" opacity="0.55"/><path d="M14 7.5 L16.5 12.5 M16.5 7.5 L14 12.5" stroke-width="1.3"/>',
        extend    : '<path d="M16.5 3 V17"/><path d="M3 10 H9"/><path d="M9 10 H15.5" stroke-dasharray="1.8 1.6"/><path d="M13 7.5 L15.5 10 L13 12.5"/>',
        corner    : '<path d="M4.5 17 V4.5 H17"/><circle cx="4.5" cy="4.5" r="1.7" fill="currentColor"/>',
        fillet    : '<path d="M4.5 17 V10.5 A6 6 0 0 1 10.5 4.5 H17"/>',
        chamfer   : '<path d="M4.5 17 V9.5 L9.5 4.5 H17"/>',
        split     : '<path d="M3 14 L8.4 11 M11.6 9.2 L17 6"/><path d="M7.6 6.6 L12.4 13.6" stroke-dasharray="1.6 1.4"/>',
        dimension : '<path d="M3 5.5 V14.5 M17 5.5 V14.5 M3 10 H17 M5.6 7.6 L3 10 L5.6 12.4 M14.4 7.6 L17 10 L14.4 12.4"/>',
        measure   : '<rect x="2.5" y="7" width="15" height="6" rx="1"/><path d="M5.5 7 V9.6 M8.5 7 V10.6 M11.5 7 V9.6 M14.5 7 V10.6"/>',
        origin    : '<path d="M5 5 L15 15 M15 5 L5 15"/><circle cx="10" cy="10" r="2.6" fill="#fff"/>',
        undo      : '<path d="M7.5 4.5 L3.5 8.5 L7.5 12.5"/><path d="M3.5 8.5 H11.5 A4.5 4.5 0 0 1 11.5 17.5 H8"/>',
        redo      : '<path d="M12.5 4.5 L16.5 8.5 L12.5 12.5"/><path d="M16.5 8.5 H8.5 A4.5 4.5 0 0 0 8.5 17.5 H12"/>',
        fit       : '<path d="M3 7 V3 H7 M13 3 H17 V7 M17 13 V17 H13 M7 17 H3 V13"/><rect x="7" y="7" width="6" height="6"/>',
        grid      : '<path d="M3 3 H17 V17 H3 Z M3 7.7 H17 M3 12.3 H17 M7.7 3 V17 M12.3 3 V17"/>',
        gridsnap  : '<path d="M3 3 H17 V17 H3 Z M3 10 H17 M10 3 V17" opacity="0.6"/><circle cx="10" cy="10" r="2.6" fill="currentColor"/>',
        snap      : '<rect x="6.2" y="6.2" width="7.6" height="7.6"/><path d="M10 2 V5 M10 15 V18 M2 10 H5 M15 10 H18"/>',
        ortho     : '<path d="M4 3.5 V16 H16.5"/><path d="M4 11.5 H8.5 V16"/>',
        newdoc    : '<path d="M5 2.5 H12 L16 6.5 V17.5 H5 Z M12 2.5 V6.5 H16"/><path d="M8 12 H13 M10.5 9.5 V14.5"/>',
        model     : '<path d="M10 2.5 L16.5 6 V13.5 L10 17.5 L3.5 13.5 V6 Z M10 9.6 L16.5 6 M10 9.6 L3.5 6 M10 9.6 V17.5"/>',
        check     : '<path d="M4 10.5 L8 14.5 L16 5.5"/>',
        save      : '<path d="M3.5 3.5 H14 L16.5 6 V16.5 H3.5 Z"/><path d="M6.5 3.5 V7.5 H12.5 V3.5 M6.5 16.5 V11.5 H13.5 V16.5"/>',
        panel     : '<rect x="3" y="3.5" width="14" height="13" rx="1.5"/><path d="M12 3.5 V16.5"/>',
        constr    : '<path d="M3 17 L17 3" stroke-dasharray="2.4 2"/>',
        trash     : '<path d="M4 5.5 H16 M8 5.5 V3.5 H12 V5.5 M5.5 5.5 L6.5 17 H13.5 L14.5 5.5"/>',
        heal      : '<path d="M8 12 L12 8"/><path d="M9.6 6.4 L11.6 4.4 A2.8 2.8 0 0 1 15.6 8.4 L13.6 10.4 M10.4 13.6 L8.4 15.6 A2.8 2.8 0 0 1 4.4 11.6 L6.4 9.6"/>',
        arcs      : '<path d="M3 16 L5.5 10.5 L9.5 6.5 L15 4" opacity="0.45"/><path d="M3 16 A14 14 0 0 1 15 4"/>',
        paint     : '<path d="M3.5 9.5 L9 4 L15 9.5 L9.5 15 Z"/><path d="M6.6 6.4 L4.4 4.2"/><path d="M16.6 11.6 C16.6 11.6 18.2 13.9 18.2 15 A1.6 1.6 0 0 1 15 15 C15 13.9 16.6 11.6 16.6 11.6 Z" fill="currentColor" stroke="none"/>'
    };

    function Icon(name) {
        return '<svg class="na-dp-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || '') + '</svg>';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Palette
    // -------------------------------------------------------------------------

    var PALETTE = [
        [ { tool : 'select', icon : 'select', label : 'Select', key : 'V or Space' },
          { cmd : 'vertexMode', icon : 'vertex', label : 'Vertex mode: pick and move vertices', key : 'Enter' } ],
        [ { tool : 'line', icon : 'line', label : 'Line', key : 'L' },
          { tool : 'rectangle', icon : 'rectangle', label : 'Rectangle', key : 'R' },
          { tool : 'arc', icon : 'arc', label : 'Arc (Tab or A again: 2-point, centre, 3-point)', key : 'A' },
          { tool : 'circle', icon : 'circle', label : 'Circle', key : 'C' } ],
        [ { tool : 'move', icon : 'move', label : 'Move (Ctrl: copy; then 3x or /3)', key : 'M' },
          { tool : 'rotate', icon : 'rotate', label : 'Rotate (Ctrl: copy)', key : 'Q' },
          { tool : 'mirror', icon : 'mirror', label : 'Mirror (keeps the original; Ctrl flips it)', key : 'Shift+M' },
          { tool : 'scale', icon : 'scale', label : 'Scale', key : 'S' },
          { tool : 'offset', icon : 'offset', label : 'Offset', key : 'F' } ],
        [ { tool : 'trim', icon : 'trim', label : 'Trim (Shift: Extend; click bare paper for a fence)', key : 'T' },
          { tool : 'extend', icon : 'extend', label : 'Extend (Shift: Trim)', key : 'Shift+T' },
          { tool : 'corner', icon : 'corner', label : 'Corner: two edges run to where they meet', key : 'K' },
          { tool : 'fillet', icon : 'fillet', label : 'Fillet (radius)', key : 'Shift+F' },
          { tool : 'chamfer', icon : 'chamfer', label : 'Chamfer', key : 'Shift+C' },
          { tool : 'split', icon : 'split', label : 'Split an edge', key : 'U' } ],
        [ { tool : 'dimension', icon : 'dimension', label : 'Dimension (audit; Tab: aligned / level / plumb)', key : 'D' },
          { tool : 'measure', icon : 'measure', label : 'Measure', key : 'Shift+D' },
          { tool : 'origin', icon : 'origin', label : 'Set Datum: the insertion point (0,0)', key : 'O' } ],
        [ { tool : 'paint', icon : 'paint', label : 'Edge Paint: click an edge or a vertex (Alt picks a colour up, Shift: all of that colour, Ctrl: the whole outline)', key : 'B' } ]
    ];

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | State
    // -------------------------------------------------------------------------

    var ui = {
        built      : false,
        mounted    : false,
        ed         : null,
        el         : {},
        sideOpen   : true,
        section    : 'props',
        confirm    : null,          // { message, actions:[{label, kind, run}] }
        save       : null,          // the open save panel's state
        busy       : false,         // a save / resolve round trip is in flight
        usage      : {},            // profileKey -> traces using it in the model
        prompt     : '',
        cursor     : null,
        lastSelectionSig : '',
        pendingOpenFromModel : false,
        paletteAsked : false,       // Edge Paint: the SSOT colours requested once per dialog
        // Live: every change rebuilds the bound trace with the drawing as its
        // own local profile (Element Assembly Studio Pro's Live Mode). One
        // update in flight at a time; changes made meanwhile go in the next.
        live       : { on : false, inFlight : false, pending : false, timer : null, state : 'idle', message : '', syncedSig : '', sentSig : '' }
    };

    function Esc(text) {
        return String(text === undefined || text === null ? '' : text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function Fmt(v, places) { return G.FormatMm(v, places === undefined ? 2 : places); }

    function Store() { return window.Na__ProfileTools__ProfileStore || null; }

    function SetSharedStatus(message) {
        if (typeof window.Na__ProfilePathTracer__Ui__SetStatusFromBridge === 'function') window.Na__ProfilePathTracer__Ui__SetStatusFromBridge(message);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Page Template
    // -------------------------------------------------------------------------

    function Template() {
        var palette = PALETTE.map(function (group) {
            return '<div class="na-dp-palette__group">' + group.map(function (item) {
                var attr = item.tool ? 'data-na-dp-tool="' + item.tool + '"' : 'data-na-dp-cmd="' + item.cmd + '"';
                return '<button type="button" class="na-dp-palette__btn" ' + attr + ' title="' + Esc(item.label + ' (' + item.key + ')') + '">' + Icon(item.icon) + '</button>';
            }).join('') + '</div>';
        }).join('');

        return [
            '<div class="na-dp" id="naDp">',
            '  <div class="na-dp-confirm na-hidden" id="naDpConfirm"></div>',
            '  <div class="na-dp-bound na-hidden" id="naDpBound"></div>',
            '  <div class="na-dp-topbar" id="naDpTopbar">',
            '    <div class="na-dp-topbar__group">',
            '      <button type="button" class="na-dp-btn" data-na-dp-cmd="new" title="Start a new, empty drawing">' + Icon('newdoc') + '<span>New</span></button>',
            '      <select class="na-dp-select" id="naDpOpenSelect" title="Open a library profile to edit, or as the start of a new one"></select>',
            '      <button type="button" class="na-dp-btn" data-na-dp-cmd="fromModel" title="Read the model selection: a Profile Trace opens its profile and binds the trace; a face opens its outline">' + Icon('model') + '<span>From Model</span></button>',
            '    </div>',
            '    <div class="na-dp-topbar__group">',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon" data-na-dp-cmd="undo" title="Undo (Ctrl+Z)">' + Icon('undo') + '</button>',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon" data-na-dp-cmd="redo" title="Redo (Ctrl+Y)">' + Icon('redo') + '</button>',
            '    </div>',
            '    <div class="na-dp-topbar__group">',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon na-dp-toggle" data-na-dp-toggle="Grid.Show" title="Show the grid (F6)">' + Icon('grid') + '</button>',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon na-dp-toggle" data-na-dp-toggle="Grid.Snap" title="Snap to the grid (F7)">' + Icon('gridsnap') + '</button>',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon na-dp-toggle" data-na-dp-toggle="Snap.On" title="Object snap (F3)">' + Icon('snap') + '</button>',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon na-dp-toggle" data-na-dp-toggle="Ortho" title="Ortho: hold lines level or plumb (F8, Ctrl+L; Shift does the opposite)">' + Icon('ortho') + '</button>',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon" data-na-dp-cmd="fit" title="Zoom to fit (Z)">' + Icon('fit') + '</button>',
            '    </div>',
            '    <div class="na-dp-topbar__spacer"><span class="na-dp-docname" id="naDpDocName"></span></div>',
            '    <button type="button" class="na-dp-check" id="naDpCheckBadge" data-na-dp-cmd="showCheck" title="Profile Check: is this one closed outline the library can store?"></button>',
            '    <div class="na-dp-topbar__group">',
            '      <button type="button" class="na-dp-btn na-dp-btn--primary" id="naDpSaveBtn" data-na-dp-cmd="save" title="Save to the profile library (Ctrl+S)">' + Icon('save') + '<span>Save</span></button>',
            '      <button type="button" class="na-dp-btn na-dp-btn--icon" data-na-dp-cmd="toggleSide" title="Show or hide the inspector">' + Icon('panel') + '</button>',
            '    </div>',
            '  </div>',
            '  <div class="na-dp-main">',
            '    <div class="na-dp-palette" id="naDpPalette">' + palette + '</div>',
            '    <div class="na-dp-stage" id="naDpStage" tabindex="0">',
            '      <canvas class="na-dp-canvas" id="naDpCanvas"></canvas>',
            '      <div class="na-dp-vcb na-dp-vcb--idle" id="naDpVcb">',
            '        <div class="na-dp-vcb__hint" id="naDpVcbHint"></div>',
            '        <div class="na-dp-vcb__row">',
            '          <span class="na-dp-vcb__label" id="naDpVcbLabel"></span>',
            '          <input class="na-dp-vcb__input" id="naDpVcbInput" type="text" autocomplete="off" spellcheck="false" title="Measurements: just start typing. Enter applies, Esc clears.">',
            '        </div>',
            '      </div>',
            '    </div>',
            '    <aside class="na-dp-side" id="naDpSide">',
            '      <div class="na-dp-side__tabs">',
            '        <button type="button" class="na-dp-side__tab" data-na-dp-section="props">Properties</button>',
            '        <button type="button" class="na-dp-side__tab" data-na-dp-section="check">Check</button>',
            '        <button type="button" class="na-dp-side__tab" data-na-dp-section="settings">Grid &amp; Snap</button>',
            '        <button type="button" class="na-dp-side__tab" data-na-dp-section="paint">Edge Paint</button>',
            '      </div>',
            '      <div class="na-dp-side__body" id="naDpSideBody"></div>',
            '    </aside>',
            '  </div>',
            '  <div class="na-dp-footer">',
            '    <span class="na-dp-footer__prompt" id="naDpPrompt"></span>',
            '    <span class="na-dp-footer__cursor" id="naDpCursor" title="Cursor position in the profile\'s own axes: Y across, Z up, millimetres from the datum"></span>',
            '  </div>',
            '  <div class="na-dp-modal na-hidden" id="naDpModal"></div>',
            '</div>'
        ].join('\n');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Build
    // -------------------------------------------------------------------------

    function Build() {
        var body = document.getElementById(BODY_ID);
        if (!body) return false;
        body.innerHTML = Template();

        [ 'naDp', 'naDpConfirm', 'naDpBound', 'naDpOpenSelect', 'naDpCheckBadge', 'naDpSaveBtn', 'naDpPalette', 'naDpStage', 'naDpCanvas',
          'naDpVcb', 'naDpVcbHint', 'naDpVcbLabel', 'naDpVcbInput', 'naDpSide', 'naDpSideBody', 'naDpPrompt', 'naDpCursor', 'naDpModal' ].forEach(function (id) {
            ui.el[id] = document.getElementById(id);
        });

        ui.sideOpen = window.innerWidth >= 760;
        // The editor fires its hooks while it is still being constructed (its
        // first SetTool); every hook below waits until ui.ed exists.
        var ready = function (fn) { return function (arg) { if (ui.ed) fn(arg); }; };
        ui.ed = Ed.Create({
            stage : ui.el.naDpStage, canvas : ui.el.naDpCanvas,
            vcbRoot : ui.el.naDpVcb, vcbLabel : ui.el.naDpVcbLabel, vcbInput : ui.el.naDpVcbInput, vcbHint : ui.el.naDpVcbHint
        }, {
            onDocChanged      : ready(function () { RenderCheckBadge(); RenderSide(); RenderTopState(); ScheduleLive(); }),
            onSelectionChanged: ready(function () { RenderSideIfSelectionChanged(); }),
            onToolChanged     : ready(function (id) { RenderPalette(); if (id === 'paint') ShowSection('paint'); }),
            onPaintChanged    : ready(function () { if (ui.section === 'paint') RenderSide(); }),
            onPaintNeeded     : ready(function () { ShowSection('paint'); }),
            onSettingsChanged : ready(function () { RenderTopState(); if (ui.section === 'settings') RenderSide(); }),
            onPrompt          : function (text) { if (text !== ui.prompt) { ui.prompt = text; ui.el.naDpPrompt.textContent = text; } },
            onCursor          : function (world) { RenderCursor(world); },
            onSaveShortcut    : ready(function () { OpenSavePanel(); }),
            isBlocked         : function () { return !!ui.save || !!ui.confirm; }
        });

        WireEvents();
        RestoreDraft();
        RenderAll();
        ui.built = true;
        return true;
    }

    function RestoreDraft() {
        var draft = ui.ed.ReadDraft();
        if (!draft || !draft.doc || !Array.isArray(draft.doc.ents) || (!draft.doc.ents.length && !(draft.doc.dims || []).length)) return;
        var doc = D.Deserialize(draft.doc);
        ui.ed.LoadDocument(doc, { base : draft.base || null, dirty : !!draft.dirty });
        ui.ed.paintDefault = draft.paintDefault && typeof draft.paintDefault === 'object' ? draft.paintDefault : null;
        // A binding names traces in the model open at the time: kept across a
        // reload of the dialog, not across days.
        var fresh = Number(draft.savedAt) && (Date.now() - Number(draft.savedAt)) < 8 * 3600 * 1000;
        ui.ed.bind = fresh ? (draft.bind || null) : null;
        ui.ed.Hint('Your last drawing was restored.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Events
    // -------------------------------------------------------------------------

    function WireEvents() {
        var root = ui.el.naDp;

        root.addEventListener('click', function (event) {
            var target = event.target.closest ? event.target.closest('[data-na-dp-tool],[data-na-dp-cmd],[data-na-dp-toggle],[data-na-dp-section],[data-na-dp-issue],[data-na-dp-action]') : null;
            if (!target || !root.contains(target)) return;
            if (target.hasAttribute('data-na-dp-tool')) { ui.ed.SetTool(target.getAttribute('data-na-dp-tool')); FocusStage(); return; }
            if (target.hasAttribute('data-na-dp-toggle')) { ui.ed.ToggleSetting(target.getAttribute('data-na-dp-toggle')); FocusStage(); return; }
            if (target.hasAttribute('data-na-dp-section')) { ui.section = target.getAttribute('data-na-dp-section'); ui.sideOpen = true; RenderSide(); return; }
            if (target.hasAttribute('data-na-dp-issue')) { FocusIssue(parseInt(target.getAttribute('data-na-dp-issue'), 10)); return; }
            if (target.hasAttribute('data-na-dp-action')) { RunAction(target.getAttribute('data-na-dp-action'), target); return; }
            RunCommand(target.getAttribute('data-na-dp-cmd'));
        });

        root.addEventListener('change', function (event) {
            var target = event.target;
            if (target === ui.el.naDpOpenSelect) { var key = target.value; target.value = ''; if (key) OpenLibraryProfile(key); return; }
            if (target.hasAttribute && target.hasAttribute('data-na-dp-field')) { ApplyField(target); return; }
            if (target.hasAttribute && target.hasAttribute('data-na-dp-setting')) { ApplySetting(target); return; }
            // Only a radio or a tick changes what the panel shows; re-drawing it
            // on a text box's change would take focus from the next box clicked.
            if (target.hasAttribute && target.hasAttribute('data-na-dp-save')) {
                ReadSaveForm();
                if (target.type === 'radio' || target.type === 'checkbox') RenderSaveModal();
            }
        });

        root.addEventListener('keydown', function (event) {
            var target = event.target;
            if (target.hasAttribute && (target.hasAttribute('data-na-dp-field') || target.hasAttribute('data-na-dp-setting')) && event.key === 'Enter') {
                event.preventDefault();
                target.blur();
            }
            if (ui.save && event.key === 'Escape') { event.preventDefault(); CloseSavePanel(); }
        });

        // The inspector floats over the stage below 760 px: crossing that line
        // closes it (or opens it again), so a narrowed dialog keeps its canvas.
        var wasWide = window.innerWidth >= 760;
        window.addEventListener('resize', function () {
            var wide = window.innerWidth >= 760;
            if (wide === wasWide) return;
            wasWide = wide;
            ui.sideOpen = wide;
            RenderSide();
            if (ui.ed) ui.ed.Redraw();
        });

        var store = window.Na_AppContext;
        if (store && typeof store.na_subscribe === 'function') {
            store.na_subscribe('na_profiles_changed', function () { RenderOpenSelect(); });
            store.na_subscribe('na_profile_meta_updated', function () { RenderOpenSelect(); RenderBound(); });
        }
    }

    function FocusStage() {
        if (ui.el.naDpStage && typeof ui.el.naDpStage.focus === 'function') ui.el.naDpStage.focus({ preventScroll : true });
    }

    function RunCommand(cmd) {
        var ed = ui.ed;
        switch (cmd) {
            case 'new':        GuardDirty('Start a new drawing? The current one has unsaved changes.', function () { NewDrawing(); }); break;
            case 'fromModel':  FromModel(); break;
            case 'undo':       ed.Undo(); break;
            case 'redo':       ed.Redo(); break;
            case 'fit':        ed.ZoomExtents(); break;
            case 'vertexMode': if (ed.tool.id !== 'select') ed.SetTool('select'); ed.SetVertexMode(!ed.vertexMode); RenderPalette(); break;
            case 'showCheck':  ui.section = 'check'; ui.sideOpen = true; RenderSide(); break;
            case 'save':       OpenSavePanel(); break;
            case 'updateTrace': OpenSavePanel({ apply : true }); break;
            case 'updateLocal': PushLocal({ live : false }); break;
            case 'toggleLive': ToggleLive(); break;
            case 'revertLocal': RevertLocal(); break;
            case 'unbind':     Unbind(); break;
            case 'toggleSide': ui.sideOpen = !ui.sideOpen; RenderSide(); ed.Redraw(); break;
            default: break;
        }
        FocusStage();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Rendering
    // -------------------------------------------------------------------------

    function RenderAll() {
        RenderPalette();
        RenderOpenSelect();
        RenderTopState();
        RenderBound();
        RenderCheckBadge();
        RenderSide();
        RenderConfirm();
    }

    function RenderPalette() {
        if (!ui.el.naDpPalette) return;
        var ed = ui.ed;
        Array.prototype.forEach.call(ui.el.naDpPalette.querySelectorAll('[data-na-dp-tool]'), function (btn) {
            btn.classList.toggle('na-dp-palette__btn--active', btn.getAttribute('data-na-dp-tool') === ed.tool.id);
        });
        var vbtn = ui.el.naDpPalette.querySelector('[data-na-dp-cmd="vertexMode"]');
        if (vbtn) vbtn.classList.toggle('na-dp-palette__btn--active', ed.vertexMode);
    }

    function RenderOpenSelect() {
        var select = ui.el.naDpOpenSelect;
        var store = Store();
        if (!select) return;
        var profiles = store ? store.Na__Store__GetProfiles() || {} : {};
        var keys = Object.keys(profiles);
        var options = [ '<option value="">Open library profile…</option>' ];
        keys.forEach(function (key) {
            var label = store.Na__Store__ProfileLabel(profiles[key]) || key;
            options.push('<option value="' + Esc(key) + '">' + Esc(label) + '</option>');
        });
        select.innerHTML = options.join('');
        select.value = '';
    }

    function RenderTopState() {
        var ed = ui.ed;
        if (!ed) return;
        Array.prototype.forEach.call(ui.el.naDp.querySelectorAll('[data-na-dp-toggle]'), function (btn) {
            var path = btn.getAttribute('data-na-dp-toggle');
            var on = path.split('.').reduce(function (o, k) { return o ? o[k] : undefined; }, ed.settings);
            btn.classList.toggle('na-dp-toggle--on', !!on);
            btn.setAttribute('aria-pressed', on ? 'true' : 'false');
        });
        var saveBtn = ui.el.naDpSaveBtn;
        if (saveBtn) {
            saveBtn.classList.toggle('na-dp-btn--dirty', !!ed.dirty);
            saveBtn.disabled = ui.busy;
        }
        var title = document.getElementById('naDpDocName');
        if (title) {
            title.textContent = DocName() + (ed.dirty ? '  •' : '');
            title.title = ed.dirty ? 'Unsaved changes' : (ed.base ? 'Saved in the library' : 'Not saved yet');
        }
    }

    function DocName() {
        var base = ui.ed && ui.ed.base;
        return base && base.displayName ? base.displayName : 'Untitled drawing';
    }

    var LIVE_TEXT = {
        idle    : '',
        synced  : 'In sync with the model',
        syncing : 'Updating the model…',
        paused  : 'Live paused',
        failed  : 'Not updated'
    };

    function RenderBound() {
        var el = ui.el.naDpBound;
        var ed = ui.ed;
        if (!el || !ed) return;
        var bind = ed.bind;
        if (!bind || !bind.traceIds || !bind.traceIds.length) {
            el.classList.add('na-hidden');
            el.innerHTML = '';
            return;
        }
        var label = bind.traceIds.length === 1 ? bind.traceIds[0] : bind.traceIds.length + ' traces (' + bind.traceIds[0] + ' first)';
        var live = ui.live;
        var liveText = LIVE_TEXT[live.state] || '';
        if (live.message && (live.state === 'paused' || live.state === 'failed')) liveText += ': ' + live.message;
        el.classList.remove('na-hidden');
        el.innerHTML = [
            '<div class="na-dp-bound__body">',
            '  <span class="na-dp-bound__label">Bound Trace</span>',
            '  <span class="na-dp-bound__name">' + Esc(label) + '</span>',
            '  <span class="na-dp-bound__note" title="' + Esc(bind.primaryProfileName || bind.primaryProfileKey || '') + '">uses ' + Esc(bind.primaryProfileName || bind.primaryProfileKey || '—') + '</span>',
            liveText ? '  <span class="na-dp-bound__live na-dp-bound__live--' + live.state + '">' + Esc(liveText) + '</span>' : '',
            '</div>',
            '<button type="button" class="na-dp-btn na-dp-live-toggle' + (live.on ? ' na-dp-live-toggle--on' : '') + '" data-na-dp-cmd="toggleLive" aria-pressed="' + (live.on ? 'true' : 'false') + '"',
            '        title="Live: every change to the drawing rebuilds this trace straight away. This trace only: the library is not touched.">',
            '  <span class="na-dp-live-dot"></span><span>Live</span></button>',
            '<button type="button" class="na-dp-btn na-dp-btn--primary" data-na-dp-cmd="updateLocal"' + (live.inFlight ? ' disabled' : '') + ' title="Rebuild this trace with the drawing. Only this trace changes: the library and every other trace are left alone.">' + Icon('check') + '<span>Update This Trace</span></button>',
            '<button type="button" class="na-dp-btn" data-na-dp-cmd="updateTrace" title="Save the drawing to the profile library (as a new profile or over the original), and put it on this trace if you want">' + Icon('save') + '<span>Save to Library…</span></button>',
            bind.primaryIsLocal ? '<button type="button" class="na-dp-btn" data-na-dp-cmd="revertLocal"' + (live.inFlight ? ' disabled' : '') + ' title="Put the library profile this trace was drawn from back on it, and open that profile here">Revert to Library</button>' : '',
            '<button type="button" class="na-dp-btn" data-na-dp-cmd="unbind" title="Stop editing this trace; the drawing stays">Unbind</button>'
        ].join('');
    }

    function RenderCheckBadge() {
        var badge = ui.el.naDpCheckBadge;
        var ed = ui.ed;
        if (!badge || !ed) return;
        var a = ed.analysis;
        var errors = a.issues.filter(function (i) { return i.severity === 'error'; }).length;
        var warns = a.issues.filter(function (i) { return i.severity === 'warn'; }).length;
        badge.classList.toggle('na-dp-check--ok', a.ok);
        badge.classList.toggle('na-dp-check--bad', !a.ok && errors > 0);
        badge.classList.toggle('na-dp-check--empty', !a.ok && !errors);
        if (a.ok) badge.innerHTML = Icon('check') + '<span>Closed profile · ' + a.stats.vertices + ' vertices' + (warns ? ' · ' + warns + ' note(s)' : '') + '</span>';
        else if (errors) badge.innerHTML = '<span class="na-dp-check__dot"></span><span>' + errors + ' problem' + (errors === 1 ? '' : 's') + ' to fix</span>';
        else badge.innerHTML = '<span>Nothing drawn</span>';
    }

    function RenderCursor(world) {
        var el = ui.el.naDpCursor;
        if (!el) return;
        el.textContent = world ? 'Y ' + Fmt(world.x, 2) + '   Z ' + Fmt(world.y, 2) + ' mm' : '';
    }

    function RenderConfirm() {
        var el = ui.el.naDpConfirm;
        if (!el) return;
        if (!ui.confirm) { el.classList.add('na-hidden'); el.innerHTML = ''; return; }
        el.classList.remove('na-hidden');
        el.innerHTML = '<span class="na-dp-confirm__text">' + Esc(ui.confirm.message) + '</span>' + ui.confirm.actions.map(function (a, i) {
            return '<button type="button" class="na-dp-btn' + (a.kind === 'primary' ? ' na-dp-btn--primary' : (a.kind === 'danger' ? ' na-dp-btn--danger' : '')) + '" data-na-dp-action="confirm:' + i + '">' + Esc(a.label) + '</button>';
        }).join('');
    }

    function Confirm(message, actions) {
        ui.confirm = { message : message, actions : actions.concat([ { label : 'Cancel', run : function () {} } ]) };
        RenderConfirm();
    }

    function GuardDirty(message, proceed) {
        if (!ui.ed.dirty || !HasDrawing()) { proceed(); return; }
        Confirm(message, [ { label : 'Discard it', kind : 'danger', run : proceed } ]);
    }

    function HasDrawing() {
        return ui.ed.doc.ents.length > 0 || ui.ed.doc.dims.length > 0;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Inspector
    // -------------------------------------------------------------------------

    function SelectionSignature() {
        var ed = ui.ed;
        return (ed.vertexMode ? 'v:' + Array.from(ed.vsel).join('|') : 's:' + Array.from(ed.selection).join('|')) + '#' + ed.history.undo.length;
    }

    function RenderSideIfSelectionChanged() {
        var sig = SelectionSignature();
        if (sig === ui.lastSelectionSig) return;
        ui.lastSelectionSig = sig;
        if (ui.section === 'props') RenderSide();
        RenderPalette();
    }

    function RenderSide() {
        var side = ui.el.naDpSide;
        if (!side || !ui.ed) return;
        side.classList.toggle('na-dp-side--closed', !ui.sideOpen);
        Array.prototype.forEach.call(side.querySelectorAll('[data-na-dp-section]'), function (btn) {
            btn.classList.toggle('na-dp-side__tab--active', btn.getAttribute('data-na-dp-section') === ui.section);
        });
        // The Edge Paint tab takes the blue away: the drawing shows its colours.
        var painting = ui.sideOpen && ui.section === 'paint';
        if (!!ui.ed.paintView !== painting) { ui.ed.paintView = painting; ui.ed.Redraw(); }
        if (!ui.sideOpen) return;
        var focus = CaptureFocus(ui.el.naDpSideBody);
        var html = ui.section === 'check' ? CheckHtml() : (ui.section === 'settings' ? SettingsHtml() : (ui.section === 'paint' ? PaintHtml() : PropertiesHtml()));
        ui.el.naDpSideBody.innerHTML = html;
        RestoreFocus(focus);
        ui.lastSelectionSig = SelectionSignature();
    }

    function CaptureFocus(root) {
        var active = document.activeElement;
        if (!active || !root || !root.contains(active) || !active.getAttribute) return null;
        var name = active.getAttribute('data-na-dp-field') || active.getAttribute('data-na-dp-setting');
        return name ? { name : name, start : active.selectionStart, end : active.selectionEnd } : null;
    }

    function RestoreFocus(snapshot) {
        if (!snapshot) return;
        var el = ui.el.naDpSideBody.querySelector('[data-na-dp-field="' + snapshot.name + '"],[data-na-dp-setting="' + snapshot.name + '"]');
        if (!el) return;
        el.focus();
        try { if (snapshot.start !== null) el.setSelectionRange(snapshot.start, snapshot.end); } catch (err) { /* no caret */ }
    }

    function Field(name, label, value, unit, hint) {
        return '<label class="na-dp-field"><span class="na-dp-field__label">' + Esc(label) + '</span>' +
               '<span class="na-dp-field__box"><input class="na-dp-field__input" type="text" data-na-dp-field="' + name + '" value="' + Esc(value) + '"' + (hint ? ' title="' + Esc(hint) + '"' : '') + '>' +
               (unit ? '<span class="na-dp-field__unit">' + unit + '</span>' : '') + '</span></label>';
    }

    function ReadOnly(label, value) {
        return '<div class="na-dp-field na-dp-field--ro"><span class="na-dp-field__label">' + Esc(label) + '</span><span class="na-dp-field__value">' + Esc(value) + '</span></div>';
    }

    function ActionButton(action, icon, label, title, kind) {
        return '<button type="button" class="na-dp-btn na-dp-btn--small' + (kind ? ' na-dp-btn--' + kind : '') + '" data-na-dp-action="' + action + '" title="' + Esc(title || label) + '">' + (icon ? Icon(icon) : '') + '<span>' + Esc(label) + '</span></button>';
    }

    function PropertiesHtml() {
        var ed = ui.ed;
        var out = [];
        if (ed.vertexMode) {
            var count = ed.vsel.size;
            out.push('<h3 class="na-dp-side__title">Vertex Mode</h3>');
            if (!count) {
                out.push('<p class="na-dp-side__note">Click or box vertices to pick them (Ctrl adds, Shift toggles). Drag one to move them all; Shift+click an edge adds a vertex.</p>');
            } else {
                out.push('<p class="na-dp-side__note">' + count + ' vertex(es) picked.</p>');
                if (count === 1) {
                    var key = Array.from(ed.vsel)[0];
                    var v = D.VertexIndex(ed.doc).get(key);
                    if (v) {
                        out.push('<div class="na-dp-field-row">' + Field('vY', 'Y', Fmt(v.p.x, 4), 'mm', 'Across, from the datum') + Field('vZ', 'Z', Fmt(v.p.y, 4), 'mm', 'Up, from the datum') + '</div>');
                    }
                }
                out.push('<div class="na-dp-side__sub">Move by values</div>');
                out.push('<div class="na-dp-field-row">' + Field('moveX', 'Across', '0', 'mm') + Field('moveY', 'Up', '0', 'mm') + '</div>');
                out.push('<div class="na-dp-side__actions">' + ActionButton('moveBy', 'move', 'Move', 'Move the picked vertices by these amounts', 'primary') +
                         ActionButton('delete', 'trash', 'Delete', 'Delete the picked vertices (where two edges meet they become one)') + '</div>');
            }
            out.push('<div class="na-dp-side__actions">' + ActionButton('leaveVertexMode', null, 'Leave vertex mode', 'Back to selecting edges (Esc)') + '</div>');
            return out.join('');
        }

        var ids = Array.from(ed.selection);
        var ents = ids.map(function (id) { return D.Get(ed.doc, id); }).filter(Boolean);
        var dims = ed.doc.dims.filter(function (d) { return ed.selection.has(d.id); });

        if (!ents.length && !dims.length) {
            out.push('<h3 class="na-dp-side__title">Drawing</h3>');
            out.push(ReadOnly('Profile', DocName()));
            out.push(ReadOnly('Edges', ed.doc.ents.length + ' (' + ed.doc.ents.filter(function (e) { return e.type !== 'line'; }).length + ' curved)'));
            out.push(ReadOnly('Dimensions', String(ed.doc.dims.length)));
            out.push('<p class="na-dp-side__note">Click an edge to see and type its length, angle, radius or segments. Double-click selects a whole run. Enter switches to vertex mode.</p>');
            out.push('<div class="na-dp-side__actions">' + ActionButton('rebuildArcs', 'arcs', 'Rebuild Arcs', 'Turn runs of short straight segments that lie on one circle back into arcs') +
                     ActionButton('healGaps', 'heal', 'Heal Gaps', 'Join ends that miss each other by less than ' + ed.settings.Tol.GapMm + ' mm') + '</div>');
            return out.join('');
        }

        if (ents.length === 1 && !dims.length) {
            var e = ents[0];
            if (e.type === 'line') {
                out.push('<h3 class="na-dp-side__title">Line' + (e.constr ? ' <span class="na-dp-tag">construction</span>' : '') + '</h3>');
                out.push('<div class="na-dp-field-row">' + Field('lineLength', 'Length', Fmt(G.Length(e), 4), 'mm', 'Typed lengths keep the start and move the end') + Field('lineAngle', 'Angle', Fmt(AngleDeg(e.a, e.b), 3), '°', 'Anticlockwise from across, about the start') + '</div>');
                out.push('<div class="na-dp-side__sub">Start</div><div class="na-dp-field-row">' + Field('aY', 'Y', Fmt(e.a.x, 4), 'mm') + Field('aZ', 'Z', Fmt(e.a.y, 4), 'mm') + '</div>');
                out.push('<div class="na-dp-side__sub">End</div><div class="na-dp-field-row">' + Field('bY', 'Y', Fmt(e.b.x, 4), 'mm') + Field('bZ', 'Z', Fmt(e.b.y, 4), 'mm') + '</div>');
            } else if (e.type === 'arc') {
                var g = G.ArcGeom(e);
                out.push('<h3 class="na-dp-side__title">Arc' + (e.constr ? ' <span class="na-dp-tag">construction</span>' : '') + '</h3>');
                out.push('<div class="na-dp-field-row">' + Field('arcRadius', 'Radius', Fmt(g.r, 4), 'mm', 'Keeps both ends; the arc bulges more or less') + Field('arcSweep', 'Sweep', Fmt(G.ToDeg(Math.abs(g.sw)), 3), '°') + '</div>');
                out.push('<div class="na-dp-field-row">' + Field('segs', 'Segments', String(e.segs || 0), '', '0 = automatic (' + G.EntitySegments(Object.assign({}, e, { segs : 0 }), ed.settings.Curves) + ' now). Each becomes a vertex of the profile and a welded SketchUp curve.') +
                         ReadOnly('In use', G.EntitySegments(e, ed.settings.Curves) + ' segments') + '</div>');
                out.push(ReadOnly('Length', Fmt(G.Length(e), 3) + ' mm'));
                out.push(ReadOnly('Centre', 'Y ' + Fmt(g.c.x, 3) + ', Z ' + Fmt(g.c.y, 3)));
            } else {
                out.push('<h3 class="na-dp-side__title">Circle' + (e.constr ? ' <span class="na-dp-tag">construction</span>' : '') + '</h3>');
                out.push('<div class="na-dp-field-row">' + Field('circleRadius', 'Radius', Fmt(e.r, 4), 'mm') + Field('segs', 'Segments', String(e.segs || 0), '', '0 = automatic (' + G.EntitySegments(Object.assign({}, e, { segs : 0 }), ed.settings.Curves) + ' now)') + '</div>');
                out.push('<div class="na-dp-side__sub">Centre</div><div class="na-dp-field-row">' + Field('cY', 'Y', Fmt(e.c.x, 4), 'mm') + Field('cZ', 'Z', Fmt(e.c.y, 4), 'mm') + '</div>');
            }
        } else {
            var arcs = ents.filter(function (x) { return x.type !== 'line'; });
            out.push('<h3 class="na-dp-side__title">' + (ents.length + dims.length) + ' selected</h3>');
            out.push(ReadOnly('Lines', String(ents.filter(function (x) { return x.type === 'line'; }).length)));
            out.push(ReadOnly('Arcs / circles', String(arcs.length)));
            if (dims.length) out.push(ReadOnly('Dimensions', String(dims.length)));
            var total = ents.reduce(function (sum, x) { return sum + G.Length(x); }, 0);
            out.push(ReadOnly('Total length', Fmt(total, 3) + ' mm'));
            if (arcs.length) out.push(Field('segs', 'Segments for all ' + arcs.length + ' curves', '', '', 'Type a count and press Enter (0 = automatic)'));
        }

        if (ents.length === 1 && !dims.length && !ents[0].constr && window.Na__DrawProfile__Paint) {
            var P = window.Na__DrawProfile__Paint;
            out.push(ReadOnly('Edge colour', ents[0].paint ? P.NameOf(ents[0].paint) : 'Unpainted (saves as ' + PaintUsualName() + ')'));
        }

        if (dims.length === 1 && !ents.length) {
            var d = dims[0];
            var sk = V.DimensionSkeleton(d.a, d.b, d.off || 0, d.orient, 0, 0);
            out.push('<h3 class="na-dp-side__title">Dimension</h3>');
            out.push(ReadOnly('Measures', sk ? Fmt(sk.length, 3) + ' mm (' + d.orient + ')' : '—'));
            out.push(Field('dimOffset', 'Offset', Fmt(Math.abs(d.off || 0), 3), 'mm'));
        }

        out.push('<div class="na-dp-side__actions">');
        if (ents.length) out.push(ActionButton('construction', 'constr', ents.some(function (x) { return !x.constr; }) ? 'Construction' : 'Profile edge', 'Construction geometry is drawn and snapped to, never saved (G)'));
        if (ents.filter(function (x) { return x.type === 'line'; }).length >= 3) out.push(ActionButton('rebuildArcs', 'arcs', 'Rebuild Arcs', 'Turn selected straight runs that lie on one circle into arcs'));
        out.push(ActionButton('delete', 'trash', 'Delete', 'Delete (Del)'));
        out.push('</div>');
        return out.join('');
    }

    function AngleDeg(a, b) {
        var deg = G.ToDeg(Math.atan2(b.y - a.y, b.x - a.x));
        return deg < 0 ? deg + 360 : deg;
    }

    function CheckHtml() {
        var ed = ui.ed;
        var a = ed.analysis;
        var out = [ '<h3 class="na-dp-side__title">Profile Check</h3>' ];
        if (a.ok) {
            var s = a.stats;
            out.push('<div class="na-dp-verdict na-dp-verdict--ok">' + Icon('check') + '<span>One closed outline: ready to save.</span></div>');
            out.push(ReadOnly('Vertices', s.vertices + ' (' + s.lines + ' line' + (s.lines === 1 ? '' : 's') + ', ' + s.arcs + ' curve' + (s.arcs === 1 ? '' : 's') + ')'));
            out.push(ReadOnly('Size', Fmt(s.width, 2) + ' x ' + Fmt(s.height, 2) + ' mm'));
            out.push(ReadOnly('Area', Fmt(s.area, 1) + ' mm²'));
            out.push(ReadOnly('Perimeter', Fmt(s.perimeter, 2) + ' mm'));
            out.push(ReadOnly('Datum', s.datumInside ? 'inside the outline' : 'outside the outline (the profile sweeps offset from the path)'));
        } else if (!a.issues.length) {
            out.push('<p class="na-dp-side__note">Nothing drawn yet.</p>');
        } else {
            var errors = a.issues.filter(function (i) { return i.severity === 'error'; }).length;
            out.push('<div class="na-dp-verdict na-dp-verdict--bad"><span class="na-dp-check__dot"></span><span>' + (errors ? errors + ' problem(s) stop this saving. Click one to find it.' : 'Not a profile yet.') + '</span></div>');
        }
        var listed = a.issues.filter(function (i) { return i.code !== 'empty'; });
        if (listed.length) {
            out.push('<ul class="na-dp-issues">');
            listed.forEach(function (issue) {
                var index = a.issues.indexOf(issue);
                out.push('<li class="na-dp-issue na-dp-issue--' + issue.severity + (ed.focusIssue === index ? ' na-dp-issue--focus' : '') + '"' + (issue.at ? ' data-na-dp-issue="' + index + '"' : '') + '>' +
                         '<span class="na-dp-issue__dot"></span><span>' + Esc(issue.message) + '</span></li>');
            });
            out.push('</ul>');
        }
        out.push('<div class="na-dp-side__actions">');
        if (a.issues.some(function (i) { return i.code === 'gap'; })) out.push(ActionButton('healGaps', 'heal', 'Heal Gaps', 'Join the ends that miss each other', 'primary'));
        out.push(ActionButton('toggleLoopInfo', null, ed.settings.ShowLoopInfo ? 'Hide vertex numbers' : 'Show vertex numbers', 'Number the outline\'s vertices in the order they are saved, with the way round'));
        out.push(ActionButton('toggleSegments', null, ed.settings.ShowSegments ? 'Hide segment marks' : 'Show segment marks', 'Mark the vertices each curve is divided into'));
        out.push('</div>');
        out.push('<p class="na-dp-side__note">A profile is one closed outline: every end joined to one other, one piece, never crossing itself. Construction edges (dashed) are ignored. Curves are saved as welded SketchUp curves.</p>');
        return out.join('');
    }

    function SettingsHtml() {
        var s = ui.ed.settings;
        var grid = s.Grid;
        var minor = Math.max(grid.MinorMinMm, grid.MajorMm / Math.max(1, grid.Divisions));
        var step = window.Na__DrawProfile__Snap.GridStep(grid);
        var check = function (path, label, on, title) {
            return '<label class="na-dp-check-row"' + (title ? ' title="' + Esc(title) + '"' : '') + '><input type="checkbox" data-na-dp-setting="' + path + '"' + (on ? ' checked' : '') + '><span>' + Esc(label) + '</span></label>';
        };
        var modes = s.Snap.Modes;
        return [
            '<h3 class="na-dp-side__title">Grid</h3>',
            check('Grid.Show', 'Show the grid (F6)', grid.Show),
            check('Grid.Snap', 'Snap to the grid (F7)', grid.Snap),
            check('Grid.ShowMinor', 'Minor grid', grid.ShowMinor !== false),
            '<label class="na-dp-field"><span class="na-dp-field__label">Look</span><select class="na-dp-select na-dp-select--small" data-na-dp-setting="Grid.Type"><option value="lines"' + (grid.Type !== 'points' ? ' selected' : '') + '>Lines</option><option value="points"' + (grid.Type === 'points' ? ' selected' : '') + '>Points</option></select></label>',
            '<div class="na-dp-field-row">' +
                '<label class="na-dp-field"><span class="na-dp-field__label">Major every</span><span class="na-dp-field__box"><input class="na-dp-field__input" type="text" data-na-dp-setting="Grid.MajorMm" value="' + Fmt(grid.MajorMm, 3) + '"><span class="na-dp-field__unit">mm</span></span></label>' +
                '<label class="na-dp-field"><span class="na-dp-field__label">Divisions</span><span class="na-dp-field__box"><input class="na-dp-field__input" type="text" data-na-dp-setting="Grid.Divisions" value="' + grid.Divisions + '"></span></label>' +
            '</div>',
            '<p class="na-dp-side__note">Minor spacing ' + Fmt(minor, 3) + ' mm. Points snap every ' + Fmt(step, 3) + ' mm.</p>',
            '<h3 class="na-dp-side__title">Object Snap</h3>',
            check('Snap.On', 'Snap to the drawing (F3)', s.Snap.On),
            '<div class="na-dp-check-grid">',
            check('Snap.Modes.end', 'Endpoint', modes.end),
            check('Snap.Modes.mid', 'Midpoint', modes.mid),
            check('Snap.Modes.int', 'Intersection', modes.int),
            check('Snap.Modes.cen', 'Centre', modes.cen),
            check('Snap.Modes.quad', 'Quadrant', modes.quad),
            check('Snap.Modes.perp', 'Perpendicular', modes.perp),
            check('Snap.Modes.near', 'Nearest (on an edge)', modes.near),
            '</div>',
            check('Ortho', 'Ortho (F8): hold lines level or plumb', s.Ortho),
            check('DrawingAxes', 'Drawing axes through the cursor (F9)', s.DrawingAxes),
            '<h3 class="na-dp-side__title">Curves</h3>',
            '<label class="na-dp-field"><span class="na-dp-field__label">Automatic segments: the flat of a segment within</span><span class="na-dp-field__box"><input class="na-dp-field__input" type="text" data-na-dp-setting="Curves.ToleranceMm" value="' + Fmt(s.Curves.ToleranceMm, 4) + '"><span class="na-dp-field__unit">mm</span></span></label>',
            '<p class="na-dp-side__note">Rest the cursor on a point for a moment to track level or plumb from it. Arrow keys lock an axis while placing. Hold Shift for the nearer axis.</p>',
            '<div class="na-dp-side__actions">' + ActionButton('resetGrid', null, 'Reset grid', 'Back to 10 mm major, 1 mm minor') + '</div>'
        ].join('');
    }

    function FocusIssue(index) {
        var ed = ui.ed;
        var issue = ed.analysis.issues[index];
        if (!issue || !issue.at) return;
        ed.focusIssue = index;
        var s = V.W2S(ed.view, issue.at);
        V.Pan(ed.view, (ed.view.w / 2) - s.x, (ed.view.h / 2) - s.y);
        if (issue.ids && issue.ids.length) ed.SetSelection(issue.ids.filter(function (id) { return D.Get(ed.doc, id); }));
        ed.Redraw();
        RenderSide();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Inspector Edits
    // -------------------------------------------------------------------------

    function ReadMm(text) {
        var read = window.Na__DrawProfile__Vcb.Length(text);
        return read.ok ? read.valueMm : null;
    }

    function ReadNumber(text) {
        var v = parseFloat(String(text).replace(/[^\d.+-eE]/g, ''));
        return Number.isFinite(v) ? v : null;
    }

    function ApplyField(input) {
        var ed = ui.ed;
        var name = input.getAttribute('data-na-dp-field');
        var text = input.value;
        var ids = Array.from(ed.selection);
        var e = ids.length === 1 ? D.Get(ed.doc, ids[0]) : null;
        var result = null;

        var moveLocation = function (from, to, label) {
            var key = D.KeyOf(from);
            return ed.Commit(label, function (doc) { D.TransformLocations(doc, new Set([ key ]), function () { return { x : to.x, y : to.y }; }); return { ok : true }; });
        };

        switch (name) {
            case 'lineLength': {
                var len = ReadMm(text);
                if (!(len > 0) || !e) { result = { ok : false, message : 'Type a length above nothing.' }; break; }
                var dir = G.Unit(G.Sub(e.b, e.a));
                result = moveLocation(e.b, G.Add(e.a, G.Mul(dir, len)), 'Line length');
                break;
            }
            case 'lineAngle': {
                var deg = ReadNumber(text);
                if (deg === null || !e) { result = { ok : false, message : 'Type an angle in degrees.' }; break; }
                var l = G.Length(e), rad = G.ToRad(deg);
                result = moveLocation(e.b, { x : e.a.x + (l * Math.cos(rad)), y : e.a.y + (l * Math.sin(rad)) }, 'Line angle');
                break;
            }
            case 'aY': case 'aZ': case 'bY': case 'bZ': {
                var value = ReadMm(text);
                if (value === null || !e) { result = { ok : false, message : 'Type a coordinate in mm.' }; break; }
                var end = name.charAt(0);
                var p = G.Copy(e[end]);
                if (name.charAt(1) === 'Y') p.x = value; else p.y = value;
                result = moveLocation(e[end], p, 'Move vertex');
                break;
            }
            case 'arcRadius': {
                var r = ReadMm(text);
                if (!e || e.type !== 'arc') break;
                var chord = G.Dist(e.a, e.b);
                if (!(r >= (chord / 2) - 1e-9)) { result = { ok : false, message : 'The radius has to be at least half the chord, ' + Fmt(chord / 2, 3) + ' mm.' }; break; }
                var s0 = G.SagittaFromSweep(chord, e.sw);
                var major = Math.abs(e.sw) > Math.PI;
                var s1 = G.SagittaForRadius(chord, r, s0 < 0 ? -1 : 1, major);
                var id = e.id;
                result = ed.Commit('Arc radius', function (doc) { D.Get(doc, id).sw = G.SweepFromSagitta(chord, s1); return { ok : true }; });
                break;
            }
            case 'arcSweep': {
                var sweepDeg = ReadNumber(text);
                if (!e || e.type !== 'arc' || sweepDeg === null || !(sweepDeg > 0) || sweepDeg >= 360) { result = { ok : false, message : 'Type a sweep over 0° and under 360°.' }; break; }
                var sign = e.sw < 0 ? -1 : 1, aid = e.id;
                result = ed.Commit('Arc sweep', function (doc) { D.Get(doc, aid).sw = sign * G.ToRad(sweepDeg); return { ok : true }; });
                break;
            }
            case 'segs': {
                var segs = ReadNumber(text);
                var max = ed.settings.Curves.MaxSegments;
                if (segs === null || segs < 0 || (segs > 0 && segs < 2) || segs > max) { result = { ok : false, message : 'Segments: 2 to ' + max + ', or 0 for automatic.' }; break; }
                segs = Math.round(segs);
                var curveIds = ids.filter(function (cid) { var x = D.Get(ed.doc, cid); return x && x.type !== 'line'; });
                result = ed.Commit('Segments', function (doc) {
                    curveIds.forEach(function (cid) { var x = D.Get(doc, cid); x.segs = (x.type === 'circle' && segs > 0 && segs < 3) ? 3 : segs; });
                    return { ok : true };
                });
                if (result.ok) ed.Hint(curveIds.length + ' curve(s): ' + (segs ? segs + ' segments.' : 'automatic segments.'));
                break;
            }
            case 'circleRadius': {
                var cr = ReadMm(text);
                if (!e || !(cr > 0)) { result = { ok : false, message : 'Type a radius above nothing.' }; break; }
                var cid2 = e.id;
                result = ed.Commit('Circle radius', function (doc) { D.Get(doc, cid2).r = cr; return { ok : true }; });
                break;
            }
            case 'cY': case 'cZ': {
                var cv = ReadMm(text);
                if (cv === null || !e) break;
                var c = G.Copy(e.c);
                if (name === 'cY') c.x = cv; else c.y = cv;
                result = moveLocation(e.c, c, 'Move circle');
                break;
            }
            case 'vY': case 'vZ': {
                var vv = ReadMm(text);
                var key = Array.from(ed.vsel)[0];
                var vtx = key ? D.VertexIndex(ed.doc).get(key) : null;
                if (vv === null || !vtx) { result = { ok : false, message : 'Type a coordinate in mm.' }; break; }
                var to = G.Copy(vtx.p);
                if (name === 'vY') to.x = vv; else to.y = vv;
                result = moveLocation(vtx.p, to, 'Move vertex');
                if (result.ok) { ed.vsel = new Set([ D.KeyOf(to) ]); ed.RefreshGrips(); }
                break;
            }
            case 'dimOffset': {
                var off = ReadMm(text);
                var dim = ed.doc.dims.filter(function (x) { return ed.selection.has(x.id); })[0];
                if (off === null || !dim) break;
                var did = dim.id;
                result = ed.Commit('Dimension offset', function (doc) {
                    var target = doc.dims.filter(function (x) { return x.id === did; })[0];
                    target.off = (target.off < 0 ? -1 : 1) * Math.abs(off);
                    return { ok : true };
                });
                break;
            }
            default: return;
        }
        if (result && !result.ok) ed.Hint(result.message || 'Not changed.', true);
        RenderSide();
    }

    function ApplySetting(input) {
        var ed = ui.ed;
        var path = input.getAttribute('data-na-dp-setting');
        if (input.type === 'checkbox') {
            ed.ToggleSetting(path, input.checked);
            RenderSide();
            return;
        }
        if (path === 'Grid.Type') { ed.SetSetting(path, input.value === 'points' ? 'points' : 'lines'); RenderSide(); return; }
        var value = path === 'Grid.Divisions' ? ReadNumber(input.value) : ReadMm(input.value);
        var limits = {
            'Grid.MajorMm'       : [ ed.settings.Grid.MajorMinMm, ed.settings.Grid.MajorMaxMm, 'Major spacing: ' + ed.settings.Grid.MajorMinMm + ' to ' + ed.settings.Grid.MajorMaxMm + ' mm.' ],
            'Grid.Divisions'     : [ 1, ed.settings.Grid.DivisionsMax, 'Divisions: 1 to ' + ed.settings.Grid.DivisionsMax + '.' ],
            'Curves.ToleranceMm' : [ 0.001, 5, 'Curve tolerance: 0.001 to 5 mm.' ]
        }[path];
        if (!limits) return;
        if (value === null || value < limits[0] || value > limits[1]) { ed.Hint(limits[2], true); RenderSide(); return; }
        ed.SetSetting(path, path === 'Grid.Divisions' ? Math.round(value) : value);
        RenderSide();
    }

    function RunAction(action, button) {
        var ed = ui.ed;
        if (action.indexOf('confirm:') === 0) {
            var chosen = ui.confirm && ui.confirm.actions[parseInt(action.split(':')[1], 10)];
            ui.confirm = null;
            RenderConfirm();
            if (chosen && typeof chosen.run === 'function') chosen.run();
            return;
        }
        if (action.indexOf('save:') === 0) { SaveAction(action.split(':')[1], button); return; }
        if (action.indexOf('paint:') === 0) { PaintAction(action.slice(6)); return; }
        switch (action) {
            case 'moveBy': {
                var dx = ReadMm(FieldValue('moveX')), dy = ReadMm(FieldValue('moveY'));
                if (dx === null || dy === null) { ed.Hint('Type across and up in mm.', true); return; }
                ed.MoveSelection({ x : dx, y : dy }, 'Move by values');
                ed.Hint('Moved ' + Fmt(dx) + ' across, ' + Fmt(dy) + ' up.');
                RenderSide();
                return;
            }
            case 'delete': ed.DeleteSelection(); RenderSide(); return;
            case 'leaveVertexMode': ed.SetVertexMode(false); RenderPalette(); RenderSide(); return;
            case 'construction': ed.ToggleConstruction(); RenderSide(); return;
            case 'rebuildArcs': {
                var ids = Array.from(ed.selection);
                var made = 0;
                ed.Commit('Rebuild arcs', function (doc) { made = L.RebuildArcs(doc, ids, null); return { ok : true }; });
                ed.Hint(made ? made + ' arc(s) rebuilt from straight segments.' : 'No run of straight segments here lies on one circle.', !made);
                RenderSide();
                return;
            }
            case 'healGaps': {
                var joined = 0;
                var gap = ed.settings.Tol.GapMm;
                ed.Commit('Heal gaps', function (doc) { joined = D.CloseGaps(doc, gap); return { ok : true }; });
                ed.Hint(joined ? joined + ' gap(s) closed.' : 'No ends miss each other by less than ' + gap + ' mm.', !joined);
                RenderSide();
                return;
            }
            case 'toggleLoopInfo': ed.ToggleSetting('ShowLoopInfo'); RenderSide(); return;
            case 'toggleSegments': ed.ToggleSetting('ShowSegments'); RenderSide(); return;
            case 'resetGrid':
                ed.settings.Grid.MajorMm = C.Grid.MajorMm;
                ed.settings.Grid.Divisions = C.Grid.Divisions;
                ed.settings.Grid.ShowMinor = true;
                ed.SetSetting('Grid.Type', C.Grid.Type);
                RenderSide();
                return;
            default: return;
        }
    }

    function FieldValue(name) {
        var el = ui.el.naDp.querySelector('[data-na-dp-field="' + name + '"]');
        return el ? el.value : '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Opening Drawings
    // -------------------------------------------------------------------------

    function NewDrawing() {
        ui.ed.LoadDocument(D.Create(), { base : null });
        ui.ed.paintDefault = null;
        ui.ed.bind = null;
        ui.ed.SaveDraft();
        RenderAll();
        ui.ed.Hint('New drawing. The orange X is the datum (0,0): the point the profile sweeps along the path from.');
        SetSharedStatus('Draw Profile: new drawing.');
    }

    function BaseFromRecord(record) {
        // A trace's own local profile has no file: it saves to the library only
        // as a new profile, and takes its edge colour from the key it was
        // drawn from (baseKey).
        return {
            profileKey  : record.profileKey,
            sourceFile  : record.sourceFile || '',
            displayName : record.isLocal ? String(record.displayName || 'Local profile').replace(/\s*\(local[^)]*\)\s*$/i, '') + ' (local)' : (record.displayName || record.profileKey),
            shortName   : record.shortName || '',
            isLibrary   : !!record.sourceFile,
            isLocal     : !!record.isLocal,
            baseKey     : record.baseProfileKey || ''
        };
    }

    function OpenRecord(record, keepBind) {
        var imported = L.ImportRecord(record);
        if (!imported.doc) { ui.ed.Hint(imported.message, true); return false; }
        var bind = keepBind ? ui.ed.bind : null;
        ui.ed.LoadDocument(imported.doc, { base : BaseFromRecord(record) });
        ui.ed.paintDefault = imported.defaultPaint || null;
        ui.ed.bind = bind;
        ui.ed.SaveDraft();
        RenderAll();
        ui.ed.Hint(imported.message);
        SetSharedStatus('Draw Profile: opened "' + (record.displayName || record.profileKey) + '". ' + imported.message);
        return true;
    }

    function OpenLibraryProfile(key) {
        var store = Store();
        var record = store ? store.Na__Store__GetProfile(key) : null;
        if (!record) { ui.ed.Hint('That profile is no longer in the library.', true); return; }
        GuardDirty('Open "' + (record.displayName || key) + '"? The current drawing has unsaved changes.', function () {
            OpenRecord(record, !!ui.ed.bind);
        });
    }

    function FromModel() {
        if (ui.busy) return;
        if (!window.Na__DrawProfile__Bridge__ResolveSelection || !window.Na__DrawProfile__Bridge__ResolveSelection()) {
            ui.ed.Hint('SketchUp is not connected: From Model needs the plugin dialog.', true);
            return;
        }
        ui.busy = true;
        RenderTopState();
        ui.ed.Hint('Reading the model selection…');
    }

    function Unbind() {
        StopLive();
        ui.ed.bind = null;
        ui.ed.SaveDraft();
        RenderBound();
        ui.ed.Hint('Unbound. The drawing stays; Save writes to the library only.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | This Trace Only: Update This Trace + Live
    // -------------------------------------------------------------------------

    var LIVE_DEBOUNCE_MS = 200;     // Element Assembly Studio Pro's Live Mode debounce

    function BoundIds() {
        var bind = ui.ed && ui.ed.bind;
        return bind && bind.traceIds && bind.traceIds.length ? bind.traceIds.slice() : null;
    }

    function DocSig() { return D.Serialize(ui.ed.doc); }

    // What the trace's own profile is called: the drawing's name, never a
    // stacked "(local) (local)".
    function LocalName() {
        var base = ui.ed.base;
        var name = base && base.displayName ? String(base.displayName) : 'Drawn profile';
        return name.replace(/\s*\(local[^)]*\)\s*$/i, '');
    }

    function SetLive(state, message) {
        ui.live.state = state;
        ui.live.message = message || '';
        RenderBound();
    }

    function StopLive() {
        if (ui.live.timer) window.clearTimeout(ui.live.timer);
        ui.live.timer = null;
        ui.live.on = false;
        ui.live.pending = false;
        if (!ui.live.inFlight) ui.live.state = 'idle';
    }

    // The trace now shows this drawing, so the drawing IS its profile.
    function MarkSynced(sig) {
        ui.live.syncedSig = sig;
        if (DocSig() === sig) ui.ed.dirty = false;
    }

    function ScheduleLive() {
        if (!ui.live.on || !BoundIds()) return;
        if (ui.live.timer) window.clearTimeout(ui.live.timer);
        ui.live.timer = window.setTimeout(function () {
            ui.live.timer = null;
            PushLocal({ live : true });
        }, LIVE_DEBOUNCE_MS);
    }

    // Sends the drawing to the bound trace(s) as their own profile. Live
    // pushes skip a drawing the model already shows and never queue more than
    // one update behind the one in flight.
    function PushLocal(options) {
        var opts = options || {};
        var ed = ui.ed;
        var ids = BoundIds();
        if (!ids) { ed.Hint('Bind a trace first: select it in the model, then From Model (or Edit Profile on the Apply tab).', true); return; }
        if (!ed.analysis.ok) {
            SetLive(ui.live.on ? 'paused' : 'failed', 'the drawing is not one closed outline (Check lists why)');
            if (!opts.live) ed.Hint('Not updated: the drawing is not one closed outline yet. Check lists what to fix.', true);
            return;
        }
        var sig = DocSig();
        if (opts.live && sig === ui.live.syncedSig) { SetLive('synced'); return; }
        if (ui.live.inFlight) { ui.live.pending = true; return; }
        var payload = L.ExportPayload(ed.analysis, ed.doc);
        var sent = window.Na__DrawProfile__Bridge__ApplyLocal && window.Na__DrawProfile__Bridge__ApplyLocal({
            traceIds : ids, geometry : payload, displayName : LocalName(), live : !!opts.live
        });
        if (!sent) { SetLive('failed', 'SketchUp is not connected'); ed.Hint('SketchUp is not connected: updating the trace needs the plugin dialog.', true); return; }
        ui.live.inFlight = true;
        ui.live.sentSig = sig;
        SetLive('syncing');
    }

    function ToggleLive() {
        var ed = ui.ed;
        var ids = BoundIds();
        if (!ids) { ed.Hint('Live needs a bound trace: select one in the model, then From Model.', true); return; }
        ui.live.on = !ui.live.on;
        if (!ui.live.on) {
            StopLive();
            SetLive(ui.live.syncedSig === DocSig() ? 'synced' : 'idle');
            ed.Hint('Live off. Update This Trace sends the drawing when you choose.');
            return;
        }
        ed.Hint('Live: every change rebuilds ' + (ids.length === 1 ? ids[0] : ids.length + ' traces') + ' as you draw. This trace only; the library is not touched.');
        PushLocal({ live : true });
        RenderBound();
    }

    function RevertLocal() {
        var ed = ui.ed;
        var ids = BoundIds();
        if (!ids || ui.live.inFlight) return;
        if (!window.Na__DrawProfile__Bridge__RevertLocal || !window.Na__DrawProfile__Bridge__RevertLocal({ traceIds : ids })) {
            ed.Hint('SketchUp is not connected.', true);
            return;
        }
        ui.live.inFlight = true;
        SetLive('syncing');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Save / Update Trace Panel
    // -------------------------------------------------------------------------

    function NextVariantCode(baseCode) {
        var store = Store();
        var keys = store ? Object.keys(store.Na__Store__GetProfiles() || {}) : [];
        var stem = String(baseCode || 'PRF_DRAWN').replace(/__V\d{2,}$/, '').replace(/_+$/, '');
        for (var n = 1; n < 1000; n++) {
            var code = stem + '__V' + (n < 10 ? '0' + n : n);
            if (keys.indexOf(code) < 0) return code;
        }
        return stem + '__V' + Date.now();
    }

    function OpenSavePanel(options) {
        var ed = ui.ed;
        if (ui.busy) return;
        var opts = options || {};
        var bound = !!(ed.bind && ed.bind.traceIds && ed.bind.traceIds.length);
        var base = ed.base && ed.base.isLibrary && Store() && Store().Na__Store__GetProfile(ed.base.profileKey) ? ed.base : null;
        var baseRecord = base ? Store().Na__Store__GetProfile(base.profileKey) : null;
        // A trace's local profile has no library file: it is offered as a new
        // variant of the library key it was drawn from.
        var localBase = !base && ed.base && ed.base.isLocal ? ed.base : null;
        var variant = NextVariantCode(base ? base.profileKey : (localBase && localBase.baseKey ? localBase.baseKey : 'PRF_DRAWN'));
        var baseName = base ? (base.displayName || base.profileKey) : (localBase ? LocalName() : '');
        ui.save = {
            mode        : bound ? 'new' : (base ? 'overwrite' : 'new'),
            apply       : bound && (opts.apply !== false),
            keepDatum   : true,
            rebuildOthers : false,
            name        : (base || localBase) ? baseName.replace(/__V\d{2,}$/, '') + '__' + variant.split('__').pop() : '',
            code        : (base || localBase) ? variant : '',
            shortName   : '',
            description : baseRecord ? ((baseRecord.profileData.assetData.Na__Asset__Metadata || {}).Na__Asset__Description || '') : '',
            keywords    : baseRecord && Store() ? Store().Na__Store__ProfileKeywords(baseRecord).join(', ') : '',
            base        : base,
            bound       : bound,
            message     : '',
            pending     : false
        };
        if (base && window.Na__DrawProfile__Bridge__CountUsage) window.Na__DrawProfile__Bridge__CountUsage(base.profileKey);
        RenderSaveModal();
    }

    function CloseSavePanel() {
        ui.save = null;
        RenderSaveModal();
        FocusStage();
    }

    function ReadSaveForm() {
        var modal = ui.el.naDpModal;
        var s = ui.save;
        if (!s || !modal) return;
        var val = function (name) { var el = modal.querySelector('[data-na-dp-save="' + name + '"]'); return el ? el : null; };
        var mode = modal.querySelector('[data-na-dp-save="mode"]:checked');
        if (mode) s.mode = mode.value;
        [ 'name', 'code', 'shortName', 'description', 'keywords' ].forEach(function (k) { var el = val(k); if (el) s[k] = el.value; });
        [ 'apply', 'keepDatum', 'rebuildOthers' ].forEach(function (k) { var el = val(k); if (el) s[k] = el.checked; });
    }

    function RenderSaveModal() {
        var modal = ui.el.naDpModal;
        if (!modal) return;
        var s = ui.save;
        if (!s) { modal.classList.add('na-hidden'); modal.innerHTML = ''; return; }
        var ed = ui.ed;
        var a = ed.analysis;
        var base = s.base;
        var traceLabel = s.bound ? (ed.bind.traceIds.length === 1 ? ed.bind.traceIds[0] : ed.bind.traceIds.length + ' bound traces') : '';
        var others = base && ui.usage[base.profileKey] !== undefined ? ui.usage[base.profileKey] : null;
        var othersAfterBound = others === null ? null : Math.max(0, others - (s.bound && ed.bind.primaryProfileKey === base.profileKey ? ed.bind.traceIds.length : 0));

        var html = [
            '<div class="na-dp-modal__panel" role="dialog" aria-label="Save profile">',
            '  <h3 class="na-dp-modal__title">' + (s.bound && s.apply ? 'Update Trace' : 'Save Profile') + '</h3>',
            a.ok ? '' : '<div class="na-dp-verdict na-dp-verdict--bad"><span class="na-dp-check__dot"></span><span>The drawing is not one closed outline yet: open Check to see what to fix.</span></div>',
            '  <div class="na-dp-radio-group">',
            '    <label class="na-dp-radio"><input type="radio" name="naDpSaveMode" data-na-dp-save="mode" value="new"' + (s.mode === 'new' ? ' checked' : '') + '><span><b>Save as a new profile</b>' + (base ? ' — a variant; "' + Esc(base.displayName) + '" stays as it is' : '') + '</span></label>',
            base ? '    <label class="na-dp-radio"><input type="radio" name="naDpSaveMode" data-na-dp-save="mode" value="overwrite"' + (s.mode === 'overwrite' ? ' checked' : '') + '><span><b>Save over "' + Esc(base.displayName) + '"</b> — the library file is replaced; a .bak of the old one is kept</span></label>' : '',
            '  </div>'
        ];

        if (s.mode === 'new') {
            html.push(
                '  <div class="na-dp-form">',
                '    <label class="na-dp-field"><span class="na-dp-field__label">Profile name</span><input class="na-dp-field__input" type="text" data-na-dp-save="name" value="' + Esc(s.name) + '" placeholder="e.g. Vale__Cornice__Ovolo__h60mm"></label>',
                '    <label class="na-dp-field"><span class="na-dp-field__label">Profile code (file name)</span><input class="na-dp-field__input" type="text" data-na-dp-save="code" value="' + Esc(s.code) + '" placeholder="e.g. PRF90120__Vale__Cornice__Ovolo"></label>',
                '    <label class="na-dp-field"><span class="na-dp-field__label">Short name (optional)</span><input class="na-dp-field__input" type="text" data-na-dp-save="shortName" value="' + Esc(s.shortName) + '" placeholder="What the Gallery shows"></label>',
                '    <label class="na-dp-field"><span class="na-dp-field__label">Description</span><input class="na-dp-field__input" type="text" data-na-dp-save="description" value="' + Esc(s.description) + '"></label>',
                '    <label class="na-dp-field"><span class="na-dp-field__label">Keywords (comma separated)</span><input class="na-dp-field__input" type="text" data-na-dp-save="keywords" value="' + Esc(s.keywords) + '"></label>',
                '  </div>'
            );
        } else if (base) {
            html.push('<p class="na-dp-side__note">Every trace that uses "' + Esc(base.displayName) + '" takes the new shape the next time it rebuilds.' +
                      (othersAfterBound === null ? '' : ' ' + othersAfterBound + ' other trace(s) in this model use it.') + '</p>');
            html.push('<label class="na-dp-check-row"><input type="checkbox" data-na-dp-save="rebuildOthers"' + (s.rebuildOthers ? ' checked' : '') + '><span>Rebuild ' + (othersAfterBound === null ? 'the other traces' : 'the ' + othersAfterBound + ' other trace(s)') + ' in this model that use it now</span></label>');
        }

        if (s.bound) {
            html.push('<div class="na-dp-modal__sep"></div>');
            html.push('<label class="na-dp-check-row"><input type="checkbox" data-na-dp-save="apply"' + (s.apply ? ' checked' : '') + '><span>Put it on <b>' + Esc(traceLabel) + '</b> and rebuild ' + (ed.bind.traceIds.length === 1 ? 'it' : 'them') + '</span></label>');
            if (s.apply && s.mode === 'new') {
                html.push('<label class="na-dp-check-row"><input type="checkbox" data-na-dp-save="keepDatum"' + (s.keepDatum ? ' checked' : '') + '><span>Keep the trace\'s insertion point' + (ed.bind.placement && ed.bind.placement.originOffset ? ' (Y ' + Fmt(ed.bind.placement.originOffset.y) + ', Z ' + Fmt(ed.bind.placement.originOffset.z) + ')' : ' (the profile datum)') + '</span></label>');
            }
        }

        html.push(
            s.message ? '<div class="na-dp-modal__message">' + Esc(s.message) + '</div>' : '',
            '  <div class="na-dp-modal__actions">',
            '    <button type="button" class="na-dp-btn" data-na-dp-action="save:cancel">Cancel</button>',
            '    <button type="button" class="na-dp-btn na-dp-btn--primary" data-na-dp-action="save:go"' + (!a.ok || s.pending ? ' disabled' : '') + '>' +
                 (s.pending ? 'Working…' : (s.bound && s.apply ? 'Save and Update Trace' : (s.mode === 'overwrite' ? 'Save Over It' : 'Save New Profile'))) + '</button>',
            '  </div>',
            '</div>'
        );
        modal.innerHTML = html.join('\n');
        modal.classList.remove('na-hidden');
    }

    function SaveAction(what) {
        if (what === 'cancel') { CloseSavePanel(); return; }
        if (what !== 'go') return;
        ReadSaveForm();
        var ed = ui.ed;
        var s = ui.save;
        if (!s || s.pending) return;
        var payload = L.ExportPayload(ed.analysis, ed.doc);
        if (!payload) { s.message = 'The drawing is not one closed outline yet. Check lists what to fix.'; RenderSaveModal(); return; }

        var styleKey = s.base ? s.base.profileKey : ((ed.base && ed.base.baseKey) || (ed.bind && ed.bind.primaryProfileKey) || '');
        var params = { saveMode : s.mode, geometry : payload, baseProfileKey : styleKey };
        if (s.mode === 'overwrite') {
            if (!s.base) { s.message = 'There is no library profile to save over: save as a new one.'; RenderSaveModal(); return; }
            params.profileKey = s.base.profileKey;
            params.sourceFile = s.base.sourceFile;
            params.rebuildOthers = !!s.rebuildOthers;
        } else {
            if (!s.name.trim()) { s.message = 'Give the new profile a name.'; RenderSaveModal(); return; }
            params.meta = {
                Meta_ProfileName : s.name.trim(),
                Meta_ProfileId : s.code.trim(),
                Meta_ProfileShortName : s.shortName.trim(),
                Meta_Description : s.description,
                Meta_Keywords : s.keywords.split(',').map(function (k) { return k.trim(); }).filter(Boolean)
            };
        }
        if (s.bound && s.apply) {
            params.traceIds = ed.bind.traceIds.slice();
            var targetKey = s.mode === 'overwrite' ? s.base.profileKey : null;
            var sameKey = targetKey && targetKey === ed.bind.primaryProfileKey;
            if (!sameKey) {
                // A different key: say what the datum should be, or the swap
                // engine resets it.
                params.originOffset = (s.mode === 'new' && s.keepDatum && ed.bind.placement) ? (ed.bind.placement.originOffset || null) : null;
            }
        }

        if (!window.Na__DrawProfile__Bridge__Save || !window.Na__DrawProfile__Bridge__Save(params)) {
            s.message = 'SketchUp is not connected: saving needs the plugin dialog.';
            RenderSaveModal();
            return;
        }
        s.pending = true;
        s.message = '';
        ui.busy = true;
        ui.savedSnapshot = D.Serialize(ed.doc);
        ui.lastSaveApplies = !!params.traceIds;
        RenderSaveModal();
        RenderTopState();
        SetSharedStatus('Draw Profile: saving…');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Receivers (from the bridge)
    // -------------------------------------------------------------------------

    function na_receive_selection(payload) {
        ui.busy = false;
        RenderTopState();
        var ed = ui.ed;
        if (!ed) return;
        if (!payload.isResolved) {
            ed.Hint(payload.statusMessage || 'Nothing usable is selected.', true);
            SetSharedStatus('Draw Profile: ' + (payload.statusMessage || 'nothing usable is selected.'));
            return;
        }
        SetSharedStatus('Draw Profile: ' + (payload.statusMessage || ''));

        if (payload.kind === 'trace') {
            if (payload.bind && payload.bind.primaryProfileKey) ui.usage[payload.bind.primaryProfileKey] = payload.keyUsageCount;
            // A newly bound trace never starts in Live: the first push to it
            // is always one the user asked for.
            var bindIt = function (inSync) {
                StopLive();
                ed.bind = payload.bind;
                ui.live.syncedSig = inSync ? DocSig() : '';
                ui.live.state = inSync ? 'synced' : 'idle';
                ed.SaveDraft();
                RenderBound();
            };
            if (!payload.profileRecord) {
                bindIt(false);
                ed.Hint(payload.statusMessage, true);
                return;
            }
            var record = payload.profileRecord;
            var loadIt = function () { OpenRecord(record, false); bindIt(true); ed.Hint(payload.statusMessage); };
            if (ed.dirty && HasDrawing()) {
                Confirm('Open ' + (payload.bind.primaryTraceId || 'the trace') + '\'s profile? Your drawing has unsaved changes.', [
                    { label : 'Open its profile', kind : 'primary', run : loadIt },
                    { label : 'Keep my drawing, bind the trace', run : function () { bindIt(false); ed.Hint('Trace bound; your drawing stays. Update This Trace puts it on the trace.'); } }
                ]);
            } else {
                loadIt();
            }
            return;
        }

        var imported = L.ImportSelection(payload);
        if (!imported.doc) { ed.Hint(imported.message, true); return; }
        var doLoad = function () {
            ed.LoadDocument(imported.doc, { base : null, dirty : true });
            ed.paintDefault = null;
            ed.bind = null;
            ed.SaveDraft();
            RenderAll();
            ed.Hint(payload.statusMessage || 'Selection opened.');
        };
        GuardDirty('Replace your drawing with the selection\'s outline? It has unsaved changes.', doLoad);
    }

    function na_receive_save_result(result) {
        ui.busy = false;
        var ed = ui.ed;
        var s = ui.save;
        SetSharedStatus('Draw Profile: ' + (result.statusMessage || (result.isSaved ? 'saved.' : 'not saved.')));
        if (!result.isSaved) {
            if (s) { s.pending = false; s.message = result.reason || result.statusMessage || 'Not saved.'; RenderSaveModal(); }
            RenderTopState();
            return;
        }
        var store = Store();
        var record = store && store.Na__Store__GetProfile(result.profileKey);
        if (record) ed.base = BaseFromRecord(record);
        if (ui.savedSnapshot === D.Serialize(ed.doc)) ed.dirty = false;
        if (result.bind && result.bind.isBound) ed.bind = result.bind;
        if (result.bind && result.bind.primaryProfileKey) ui.usage[result.bind.primaryProfileKey] = undefined;
        ed.SaveDraft();
        ui.save = null;
        RenderSaveModal();
        RenderAll();
        ed.Hint(result.statusMessage || 'Saved.', ui.lastSaveApplies && result.isApplied === false);
        FocusStage();
    }

    function na_receive_key_usage(payload) {
        if (!payload || !payload.profileKey) return;
        ui.usage[payload.profileKey] = Number(payload.count) || 0;
        if (ui.save) RenderSaveModal();
    }

    // Update This Trace / Live / Revert to Library answered.
    function na_receive_local_result(result) {
        var ed = ui.ed;
        if (!ed) return;
        ui.live.inFlight = false;
        if (result.bind && result.bind.isBound) ed.bind = result.bind;

        if (result.isReverted) {
            if (result.isApplied && result.profileRecord) {
                OpenRecord(result.profileRecord, true);
                MarkSynced(DocSig());
            }
            SetLive(result.isApplied ? 'synced' : 'failed', result.isApplied ? '' : result.statusMessage);
            ed.Hint(result.statusMessage || 'Reverted.', !result.isApplied && !!(result.failures || []).length);
            SetSharedStatus('Draw Profile: ' + (result.statusMessage || ''));
            RenderAll();
            return;
        }

        if (result.isApplied) {
            var ids = BoundIds() || [];
            ed.base = {
                profileKey  : 'LOCAL__' + (ids[0] || ''),
                sourceFile  : '',
                displayName : (result.displayName || LocalName()) + ' (local)',
                isLibrary   : false,
                isLocal     : true,
                baseKey     : ed.bind ? ed.bind.primaryProfileKey : ''
            };
            MarkSynced(ui.live.sentSig);
            ed.SaveDraft();
            SetLive('synced', '');
            if (!result.isLive || (result.failures || []).length) ed.Hint(result.statusMessage, !!(result.failures || []).length);
        } else {
            SetLive('failed', result.statusMessage || 'the trace was not rebuilt');
            ed.Hint(result.statusMessage || 'Not updated.', true);
        }
        SetSharedStatus('Draw Profile: ' + (result.statusMessage || ''));
        RenderTopState();

        if (ui.live.pending) {
            ui.live.pending = false;
            if (ui.live.on) PushLocal({ live : true });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Edge Paint (v1.6.15)
    // -------------------------------------------------------------------------

    function ShowSection(section) {
        if (ui.section === section && ui.sideOpen) { RenderSide(); return; }
        ui.section = section;
        if (window.innerWidth >= 760) ui.sideOpen = true;
        RenderSide();
    }

    function RequestPalette(refresh) {
        var P = window.Na__DrawProfile__Paint;
        ui.paletteAsked = true;
        var sent = window.Na__DrawProfile__Bridge__RequestPalette && window.Na__DrawProfile__Bridge__RequestPalette(!!refresh);
        if (!sent && P) {
            P.SetPalette({ status : 'failed', entries : [], statusMessage : 'SketchUp is not connected.' });
            if (ui.section === 'paint') RenderSide();
        } else if (refresh && ui.ed) {
            ui.ed.Hint('Fetching the edge colours…');
        }
    }

    function na_receive_palette(payload) {
        var P = window.Na__DrawProfile__Paint;
        if (!P || !ui.ed) return;
        P.SetPalette(payload || {});
        var status = P.Status();
        if (status.status === 'failed') ui.ed.Hint('Edge colours not loaded: ' + (status.message || 'the SSOT could not be reached and there is no cached copy.'), true);
        if (ui.section === 'paint') RenderSide();
        ui.ed.UpdatePrompt();
        ui.ed.Redraw();
    }

    function PaintUsualName() {
        var P = window.Na__DrawProfile__Paint;
        var usual = ui.ed.PaintDefault();
        return usual.id ? P.NameOf(usual.id) : 'grey ' + (usual.hex || P.UNPAINTED_HEX);
    }

    function SourceLabel(status) {
        if (status.status === 'url') return 'SSOT';
        if (status.status === 'cache_stale') return 'SSOT, cached copy';
        if (status.status === 'pending') return 'loading';
        return 'not loaded';
    }

    function SwatchSpan(hex, extra) {
        return '<span class="na-dp-swatch' + (extra ? ' ' + extra : '') + '"' + (hex ? ' style="background:' + Esc(hex) + '"' : '') + '></span>';
    }

    function CurrentSwatch(P, current) {
        if (current === null) return SwatchSpan(null, 'na-dp-swatch--none');
        if (current === P.CLEAR) return SwatchSpan(null, 'na-dp-swatch--clear');
        if (current === P.DEFAULT_ID) return SwatchSpan(null, 'na-dp-swatch--default');
        return SwatchSpan(P.HexOf(current));
    }

    function PaintHtml() {
        var ed = ui.ed;
        var P = window.Na__DrawProfile__Paint;
        if (!P) return '<p class="na-dp-side__note">Edge Paint did not load.</p>';
        var current = P.Current();
        var out = [ '<h3 class="na-dp-side__title">Edge Paint</h3>' ];
        out.push('<p class="na-dp-side__note">An <b>edge</b>\'s colour goes on its line at both ends of the trace and at every mitre. A <b>vertex</b>\'s colour goes on the line it sweeps along the path. A vertex left unpainted (ring) follows its edges, the darker where they differ.</p>');

        var currentName = current === null ? 'No colour chosen' : (current === P.CLEAR ? 'Unpainted (takes paint off)' : P.NameOf(current));
        out.push('<div class="na-dp-paint-current">' + CurrentSwatch(P, current) + '<span class="na-dp-paint-current__name">' + Esc(currentName) + '</span>' +
                 (ed.tool.id === 'paint' ? '<span class="na-dp-tag">Paint tool</span>' : ActionButton('paint:tool', 'paint', 'Paint', 'Click edges and vertices with this colour (B)')) + '</div>');

        var status = P.Status();
        out.push('<div class="na-dp-side__sub">Edge colours <span class="na-dp-paint-source na-dp-paint-source--' + Esc(status.status) + '">' + Esc(SourceLabel(status)) + '</span></div>');
        if (!status.count) {
            out.push('<p class="na-dp-side__note">' + (status.status === 'pending' ? 'Loading the edge colours…' : 'The edge colours could not be loaded. ' + Esc(status.message)) + '</p>');
        }
        var groups = {}, order = [];
        P.Palette().forEach(function (entry) {
            if (!groups[entry.series]) { groups[entry.series] = []; order.push(entry.series); }
            groups[entry.series].push(entry);
        });
        order.forEach(function (series) {
            out.push('<div class="na-dp-paint-series">' + Esc(P.SeriesLabel(series)) + '</div><div class="na-dp-swatches">');
            groups[series].forEach(function (entry) {
                var title = entry.name + '  ' + entry.hex + '\n' + entry.material + (entry.description ? '\n' + entry.description : '');
                out.push('<button type="button" class="na-dp-swatch-btn' + (current === entry.id ? ' na-dp-swatch-btn--on' : '') + '" data-na-dp-action="paint:pick:' + Esc(entry.id) + '" title="' + Esc(title) + '" aria-label="' + Esc(entry.name) + '" style="background:' + Esc(entry.hex) + '"></button>');
            });
            out.push('</div>');
        });
        out.push('<div class="na-dp-paint-specials">' +
                 '<button type="button" class="na-dp-paint-special' + (current === P.DEFAULT_ID ? ' na-dp-paint-special--on' : '') + '" data-na-dp-action="paint:pick:' + P.DEFAULT_ID + '" title="SketchUp\'s own edge colour: no material on the line">' + SwatchSpan(null, 'na-dp-swatch--default') + '<span>SketchUp default</span></button>' +
                 '<button type="button" class="na-dp-paint-special' + (current === P.CLEAR ? ' na-dp-paint-special--on' : '') + '" data-na-dp-action="paint:clear" title="Take paint off: an edge takes the profile\'s usual colour, a vertex follows its edges">' + SwatchSpan(null, 'na-dp-swatch--clear') + '<span>Unpainted</span></button>' +
                 '</div>');

        var used = P.Used(ed.doc, ed.PaintDefault());
        if (used.length) {
            out.push('<div class="na-dp-side__sub">In this drawing</div><ul class="na-dp-paint-used">');
            used.forEach(function (row) {
                var counts = [];
                if (row.edges) counts.push(row.edges + ' edge' + (row.edges === 1 ? '' : 's'));
                if (row.vertices) counts.push(row.vertices + ' painted vert' + (row.vertices === 1 ? 'ex' : 'ices'));
                if (row.unpainted) counts.push(row.unpainted + ' following');
                out.push('<li><button type="button" class="na-dp-paint-row" data-na-dp-action="paint:pick:' + Esc(row.id || '') + '" title="Paint with this colour">' +
                         SwatchSpan(row.hex) + '<span class="na-dp-paint-row__name">' + Esc(row.name) + '</span><span class="na-dp-paint-row__count">' + Esc(counts.join(' · ')) + '</span></button></li>');
            });
            out.push('</ul>');
        }
        out.push('<p class="na-dp-side__note">Unpainted edges (white dashes) save as the profile\'s usual colour: ' + Esc(PaintUsualName()) + '.</p>');

        var hasSelection = ed.vertexMode ? ed.vsel.size > 0 : Array.from(ed.selection).some(function (id) { var e = D.Get(ed.doc, id); return e && !e.constr; });
        out.push('<div class="na-dp-side__actions">' +
                 (hasSelection ? ActionButton('paint:selection', 'paint', ed.vertexMode ? 'Paint picked vertices' : 'Paint selection', 'Paint what is selected with this colour', 'primary') : '') +
                 ActionButton('paint:allEdges', null, 'All edges', 'Paint every edge of the outline with this colour') +
                 ActionButton('paint:allVertices', null, 'All vertices', 'Paint every vertex of the outline with this colour') +
                 ActionButton('paint:followEdges', null, 'Vertices follow edges', 'Take the paint off every vertex: each follows its edges again') +
                 '</div>');
        out.push('<label class="na-dp-check-row" title="Show the edge colours on every tab, not only here"><input type="checkbox" data-na-dp-setting="ShowPaint"' + (ed.settings.ShowPaint ? ' checked' : '') + '><span>Show colours on every tab</span></label>');
        out.push('<div class="na-dp-side__actions">' + ActionButton('paint:refresh', null, 'Refresh colours', 'Fetch the edge colours from the SSOT again') + '</div>');
        return out.join('');
    }

    function PaintAction(command) {
        var ed = ui.ed;
        var P = window.Na__DrawProfile__Paint;
        if (!P) return;
        if (command.indexOf('pick:') === 0) {
            var id = command.slice(5);
            P.SetCurrent(id);
            if (ed.tool.id !== 'paint') ed.SetTool('paint');
            ed.UpdatePrompt();
            ed.Hint(id ? P.NameOf(id) + ': click edges and vertices to paint them.' : 'Unpainted: click edges and vertices to take their paint off.');
            RenderSide();
            FocusStage();
            return;
        }
        var count = 0;
        switch (command) {
            case 'clear': PaintAction('pick:'); return;
            case 'tool': ed.SetTool('paint'); RenderSide(); FocusStage(); return;
            case 'refresh': RequestPalette(true); return;
            case 'followEdges':
                count = P.PaintVertices(ed, Object.keys(ed.doc.vpaint || {}), P.CLEAR);
                ed.Hint(count ? count + ' vertex colour(s) taken off: every vertex follows its edges.' : 'No vertex is painted.');
                RenderSide();
                return;
            default: break;
        }
        var colour = P.Current();
        if (colour === null) { ed.Hint('Pick a colour first.', true); return; }
        var name = colour ? P.NameOf(colour) : 'Unpainted';
        switch (command) {
            case 'selection':
                if (ed.vertexMode) {
                    count = P.PaintVertices(ed, Array.from(ed.vsel), colour);
                    ed.Hint(name + ' on ' + count + ' picked vertex(es).');
                } else {
                    count = P.PaintEdges(ed, Array.from(ed.selection), colour);
                    ed.Hint(name + ' on ' + count + ' selected edge(s).');
                }
                break;
            case 'allEdges':
                count = P.PaintEdges(ed, P.OutlineEdgeIds(ed.doc), colour);
                ed.Hint(name + ' on all ' + count + ' edge(s).');
                break;
            case 'allVertices':
                count = P.PaintVertices(ed, P.OutlineVertexKeys(ed.doc), colour);
                ed.Hint(name + ' on all ' + count + ' vertices.');
                break;
            default: return;
        }
        RenderSide();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Lifecycle
    // -------------------------------------------------------------------------

    function na_mount() {
        if (!ui.built && !Build()) return;
        ui.mounted = true;
        ui.ed.active = true;
        RenderAll();
        ui.ed.Redraw();
        if (!ui.paletteAsked) RequestPalette(false);
        if (ui.pendingOpenFromModel) { ui.pendingOpenFromModel = false; FromModel(); }
        window.setTimeout(FocusStage, 0);
    }

    function na_unmount() {
        ui.mounted = false;
        if (ui.ed) {
            ui.ed.active = false;
            ui.ed.SaveDraft();
        }
    }

    // The Apply tab's Edit Profile button: route here and read the selection.
    function na_open_from_model() {
        var router = window.Na_TabRouter;
        if (router && router.na_get_active_tab() !== 'draw-profile') {
            ui.pendingOpenFromModel = true;
            router.na_activateTab('draw-profile');
            return;
        }
        if (!ui.built) { ui.pendingOpenFromModel = true; return; }
        FromModel();
    }

    function na_open_profile(profileKey) {
        var router = window.Na_TabRouter;
        if (router && router.na_get_active_tab() !== 'draw-profile') router.na_activateTab('draw-profile');
        OpenLibraryProfile(profileKey);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__DrawProfile__Tab = {
        na_mount               : na_mount,
        na_unmount             : na_unmount,
        na_open_from_model     : na_open_from_model,
        na_open_profile        : na_open_profile,
        na_receive_selection   : na_receive_selection,
        na_receive_save_result : na_receive_save_result,
        na_receive_key_usage   : na_receive_key_usage,
        na_receive_local_result : na_receive_local_result,
        na_receive_palette     : na_receive_palette,
        na_editor              : function () { return ui.ed; },
        na_live_state          : function () { return ui.live; }
    };

    // endregion ----------------------------------------------------------------
})();
