// =============================================================================
// NA PAINTERLYNPR ASSETS - NPR VIEWPORT - HOST, THE PARAMETERS WINDOW
// =============================================================================
//
// FILE       : Na__PainterlyAssets__NprViewport__HostParameters__.mjs
// NAMESPACE  : Na__NprHost
// MODULE     : NPR Viewport - Host, Parameters
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Turn PainterlyNPR's own app page into SketchUp's NPR Parameters
//              window: the engine's own panel, every section, group, slider,
//              menu, preset and hint it has, whose every change moves the NPR
//              Viewport's drawing; with Live, Refresh and Reload Remote Plugin
//              Files above it
// CREATED    : 01-Nov-2026
//
// DESCRIPTION:
// - THE PANEL IS THE ENGINE'S (built by its own BuildPanel from its own panel
//   config, wired by its own Wire), so a control added to PainterlyNPR shows
//   here at the next Reload Remote Plugin Files, with nothing changed in the
//   plugin. Only the sections that act on this window's own sheet are hidden:
//   the camera (the viewport's is SketchUp's), art direction (its points are
//   placed on a drawing) and export.
// - THIS PAGE'S OWN ENGINE IS KEPT QUIET: the work mode Proxy (no pen and wash)
//   and a small sheet, so it holds the settings and costs little.
// - WHAT MOVES THE VIEWPORT: a slider's move goes at once as that control (the
//   engine's SetControl there, only its inputs bumped); after any change the
//   settings object's look (seed, sun, style, paper, composition) goes too,
//   when it differs from the last sent, and Ruby keeps it for the project.
// - The look Ruby hands over (the project's, or the viewport's) is put into
//   this page's engine with the engine's own ApplySettingsJson.
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Module Imports - the Engine (PainterlyNPR, from the cache) and the Host
// -----------------------------------------------------------------------------

    import * as RenderGraph from 'PainterlyNPR/20__System__RenderGraph/PainterlyNPR__RenderGraph__Graph__.mjs';
    import * as GpuResources from 'PainterlyNPR/21__System__GpuResources/PainterlyNPR__GpuResources__Core__.mjs';
    import * as SettingsJson from 'PainterlyNPR/85__System__ProjectPersistence/PainterlyNPR__Interface__SettingsJson__.mjs';
    import {
        Na__NprHost__Action,
        Na__NprHost__Listen,
        Na__NprHost__Look,
        Na__NprHost__Ready,
        Na__NprHost__StatusLine,
    } from './Na__PainterlyAssets__NprViewport__HostShared__.mjs';

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Constants and State
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | Timing, the Quiet Engine and the Icons
    // ------------------------------------------------------------
    const Na__NprParams__CONTROL_MS   =  50;                                     // <-- A dragged slider reaches the viewport at most this often
    const Na__NprParams__LOOK_MS      =  220;                                    // <-- The whole look follows once the panel is still this long
    const Na__NprParams__QUIET_SCALE  =  0.2;                                    // <-- This page's own sheet: a fifth of the engine's, never drawn
    const Na__NprParams__ICONS        =  '/host/01__AppAssets__PainterlyAssets/';
    // ------------------------------------------------------------

    // MODULE VARIABLES | What Was Sent, and the Header
    // ------------------------------------------------------------
    const Na__NprParams__State  =  {
        lastLook   :  '',
        lookTimer  :  null,
        control    :  { timer: null, last: 0, pending: null },
        live       :  null,
        status     :  null,
        head       :  null,
    };
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Boot
// -----------------------------------------------------------------------------

    // FUNCTION | Take Over the Page: the header, a quiet engine, the panel watched, then ready
    // ------------------------------------------------------------
    function Na__NprParams__Boot() {
        const S  =  Na__NprParams__State;
        document.documentElement.classList.add('Na__NprHost', 'Na__NprHost--Parameters');
        const root  =  document.getElementById('PainterlyNPR__App__Root');
        if (root) root.classList.remove('PainterlyNPR--foldPanel');                 // <-- A panel folded on another day opens unfolded here
        S.head    =  Na__NprParams__Header();
        S.status  =  Na__NprHost__StatusLine('Na__NprParams__Status');
        S.head.querySelector('.Na__NprParams__StatusHome').appendChild(S.status.Element);
        Na__NprHost__Listen(Na__NprParams__Receive);

        const booted  =  Na__NprHost__Ready('parameters');
        if (!booted.Booted) {
            S.status.Say(`PainterlyNPR could not start in SketchUp's browser: ${booted.Error}`, 'error');
            return;
        }
        Na__NprParams__Quiet();
        Na__NprParams__Watch();
        S.lastLook  =  JSON.stringify(Na__NprHost__Look(SettingsJson.PainterlyNPR__Interface__SettingsObject()));
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | This Page's Engine Holds the Settings, It Does Not Draw
    // ------------------------------------------------------------
    function Na__NprParams__Quiet() {
        try {
            if (typeof RenderGraph.PainterlyNPR__RenderGraph__SetProxy === 'function') RenderGraph.PainterlyNPR__RenderGraph__SetProxy(true);
            if (typeof GpuResources.PainterlyNPR__GpuResources__SetScale === 'function') {
                GpuResources.PainterlyNPR__GpuResources__SetScale(Na__NprParams__QUIET_SCALE);   // <-- Its targets a twenty-fifth of the size: the GPU's memory is the viewport's
                RenderGraph.PainterlyNPR__RenderGraph__Bump('Size');
            }
        } catch (error) {
            console.warn('[Na NPR Parameters] The page\'s own engine could not be made quiet:', error);
        }
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Header: Live, Refresh, the Viewport, Reload Remote Plugin Files, the Status
    // ------------------------------------------------------------
    function Na__NprParams__Header() {
        const head  =  document.createElement('header');
        head.className  =  'Na__NprParams__Head';
        head.innerHTML  =  `
            <div class="Na__NprParams__TitleRow">
                <span class="Na__NprParams__Title">NPR Parameters</span>
                <span class="Na__NprParams__Model" data-na="model"></span>
            </div>
            <div class="Na__NprParams__Buttons">
                <button type="button" class="Na__NprParams__Live" data-na="live" aria-pressed="true" title="Live NPR updates: the viewport follows SketchUp's camera and every change to the model. Off: it holds still while you work.">
                    <img alt="" draggable="false" data-na="liveIcon" src="${Na__NprParams__ICONS}Na__PainterlyAssets__Toolbar__NprLiveOn__.svg"><span data-na="liveText">Live</span>
                </button>
                <button type="button" class="Na__NprParams__Button" data-na-action="refresh" title="Check every part of the model now and redraw, live or not">Refresh</button>
                <button type="button" class="Na__NprParams__Button" data-na-action="openViewport" title="Open the NPR Viewport">Viewport</button>
                <button type="button" class="Na__NprParams__Button" data-na-action="reloadRemote" title="Download PainterlyNPR's latest commit from GitHub again, then reload both NPR windows">Reload Remote Plugin Files</button>
            </div>
            <div class="Na__NprParams__StatusHome"></div>
            <div class="Na__NprParams__Engine" data-na="engine"></div>`;
        document.body.insertBefore(head, document.body.firstChild);
        head.querySelector('[data-na="live"]').addEventListener('click', () => Na__NprHost__Action('toggleLive'));
        for (const button of head.querySelectorAll('[data-na-action]')) button.addEventListener('click', () => Na__NprHost__Action(button.dataset.naAction));
        return head;
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Panel Watched: What Moves Goes to the Viewport
// -----------------------------------------------------------------------------

    // FUNCTION | Hear Every Change the Panel Makes (after the engine's own handlers ran)
    // ------------------------------------------------------------
    function Na__NprParams__Watch() {
        const panel  =  document.querySelector('.PainterlyNPR__Main') || document.body;
        panel.addEventListener('input', (event) => {
            const key  =  event.target && event.target.dataset ? event.target.dataset.control : null;
            if (key) Na__NprParams__SendControl(key, Number(event.target.value));
            Na__NprParams__LookSoon();
        });
        for (const type of ['change', 'click', 'keyup', 'pointerup']) panel.addEventListener(type, Na__NprParams__LookSoon);
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | One Control's Value, at Most Every CONTROL_MS (the last one always goes)
    // ------------------------------------------------------------
    function Na__NprParams__SendControl(key, value) {
        if (!Number.isFinite(value)) return;
        const C    =  Na__NprParams__State.control;
        C.pending  =  { Key: key, Value: value };
        const wait =  Na__NprParams__CONTROL_MS - (performance.now() - C.last);
        if (C.timer) return;
        C.timer  =  setTimeout(() => {
            C.timer  =  null;
            C.last   =  performance.now();
            const send  =  C.pending;
            C.pending   =  null;
            if (send) Na__NprHost__Action('parameters', { Control: send });
        }, Math.max(0, wait));
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Whole Look, Once the Panel Is Still and Only When It Moved
    // ------------------------------------------------------------
    function Na__NprParams__LookSoon() {
        const S  =  Na__NprParams__State;
        clearTimeout(S.lookTimer);
        S.lookTimer  =  setTimeout(() => {
            const look  =  Na__NprHost__Look(SettingsJson.PainterlyNPR__Interface__SettingsObject());
            const json  =  JSON.stringify(look);
            if (json === S.lastLook) return;
            S.lastLook  =  json;
            Na__NprHost__Action('parameters', { Settings: look });
        }, Na__NprParams__LOOK_MS);
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Messages From SketchUp
// -----------------------------------------------------------------------------

    // FUNCTION | One Message: settings | live | status
    // ------------------------------------------------------------
    function Na__NprParams__Receive(kind, payload) {
        const S  =  Na__NprParams__State;
        if (kind === 'status') return S.status.Say(payload.Text, payload.Level);
        if (kind === 'live') return Na__NprParams__ShowLive(payload);
        if (kind === 'settings' && payload.Settings && typeof SettingsJson.PainterlyNPR__Interface__ApplySettingsJson === 'function') {
            const now   =  SettingsJson.PainterlyNPR__Interface__SettingsObject();
            const look  =  Na__NprHost__Look(payload.Settings);
            S.lastLook  =  JSON.stringify(look);                                 // <-- What came from Ruby is not sent back
            if (S.lastLook !== JSON.stringify(Na__NprHost__Look(now))) SettingsJson.PainterlyNPR__Interface__ApplySettingsJson(JSON.stringify(Object.assign({}, now, look)));
        }
        return null;
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Live Button, the Model's Name and Which Engine Runs
    // ------------------------------------------------------------
    function Na__NprParams__ShowLive(payload) {
        const head  =  Na__NprParams__State.head;
        const on    =  payload.On !== false;
        const live  =  head.querySelector('[data-na="live"]');
        live.setAttribute('aria-pressed', on ? 'true' : 'false');
        head.querySelector('[data-na="liveIcon"]').src  =  `${Na__NprParams__ICONS}Na__PainterlyAssets__Toolbar__NprLive${on ? 'On' : 'Off'}__.svg`;
        head.querySelector('[data-na="liveText"]').textContent  =  on ? 'Live' : 'Paused';
        head.querySelector('[data-na="model"]').textContent  =  payload.Model || '';
        const engine  =  payload.Engine;
        head.querySelector('[data-na="engine"]').textContent  =  !engine ? '' : engine.source === 'override'
            ? `PainterlyNPR from a local folder (${engine.folder})`
            : `PainterlyNPR ${engine.appVersion} (${engine.branch || 'main'} at ${engine.commit}), from GitHub ${String(engine.fetchedIso || '').slice(0, 10)}`;
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


    Na__NprParams__Boot();
