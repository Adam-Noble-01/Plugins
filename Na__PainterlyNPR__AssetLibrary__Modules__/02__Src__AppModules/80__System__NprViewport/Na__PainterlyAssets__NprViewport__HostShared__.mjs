// =============================================================================
// NA PAINTERLYNPR ASSETS - NPR VIEWPORT - HOST SHARED
// =============================================================================
//
// FILE       : Na__PainterlyAssets__NprViewport__HostShared__.mjs
// NAMESPACE  : Na__NprHost
// MODULE     : NPR Viewport - Host, Shared
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : What both NPR windows' hosts need: the bridge to SketchUp's Ruby
//              (calls out, messages in), whether the engine booted, the part of
//              the engine's settings that is the drawing's look, and a status
//              line laid over the page
// CREATED    : 01-Nov-2026
//
// DESCRIPTION:
// - A HOST IS NOT THE ENGINE. The page these modules run in is PainterlyNPR's
//   own (PainterlyNPR__App__.html from the repo, served by the plugin's local
//   server), and the engine is its own modules, imported here through the
//   import map's "PainterlyNPR/" prefix, as ValeVision AURA imports its pin.
//   Nothing of the engine is copied into the plugin (Adam, 01-Nov-2026: "Do
//   not, under any circumstance, copy the core render engine code into the
//   SketchUp plugin").
// - Engine modules are imported as namespaces, so an engine without one of
//   their exports still loads; each use checks that what it calls is there.
// - Ruby calls in through window.Na__NprHost__Receive(kind, payload); the
//   host calls out through window.sketchup, which SketchUp may bind a moment
//   after the page loads, so a call waits for it.
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Module Imports - the Engine (PainterlyNPR, from the cache)
// -----------------------------------------------------------------------------

    import * as Engine from 'PainterlyNPR/02__AppData/PainterlyNPR__AppData__Engine__.mjs';
    import * as GpuResources from 'PainterlyNPR/21__System__GpuResources/PainterlyNPR__GpuResources__Core__.mjs';

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Constants
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | The Settings Object's Keys That Are the Drawing's Look
    // ------------------------------------------------------------
    // The engine's settings object also holds its camera (SketchUp's, in the
    // viewport), its art direction points (placed on the viewport's sheet) and
    // its placed assets and materials (the model's): those stay each window's.
    const Na__NprHost__LOOK_KEYS     =  ['Seed', 'Sun', 'Style', 'Paper', 'Composition'];
    const Na__NprHost__CALL_TRIES    =  40;                                      // <-- 4 s for SketchUp to bind window.sketchup
    const Na__NprHost__STATUS_FADE   =  4500;
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Bridge to SketchUp
// -----------------------------------------------------------------------------

    // FUNCTION | Call a Ruby Callback (waits for SketchUp to bind it)
    // ------------------------------------------------------------
    function Na__NprHost__Call(name, ...args) {
        let tries  =  0;
        const go   =  () => {
            const fn  =  window.sketchup && window.sketchup[name];
            if (typeof fn === 'function') { fn(...args); return; }
            if (tries++ < Na__NprHost__CALL_TRIES) setTimeout(go, 100);
            else console.warn(`[Na NPR Host] SketchUp never offered ${name}: is this page open outside SketchUp?`);
        };
        go();
    }
    // ------------------------------------------------------------


    // FUNCTION | Hear Ruby: handler(kind, payload) for every message
    // ------------------------------------------------------------
    function Na__NprHost__Listen(handler) {
        window.Na__NprHost__Receive  =  (kind, payload) => {
            try {
                const done  =  handler(kind, payload || {});
                if (done && typeof done.catch === 'function') done.catch((error) => console.error(`[Na NPR Host] ${kind}:`, error));
            } catch (error) {
                console.error(`[Na NPR Host] ${kind}:`, error);
            }
        };
    }
    // ------------------------------------------------------------


    // FUNCTION | Tell Ruby This Window Is Up: { Role, Booted, Error, EngineVersion, SheetMm }
    // ------------------------------------------------------------
    function Na__NprHost__Ready(role) {
        const booted  =  Na__NprHost__Booted();
        Na__NprHost__Call('na_npr_window_ready', JSON.stringify({
            Role          :  role,
            Booted        :  booted.Booted,
            Error         :  booted.Error,
            EngineVersion :  Engine.PainterlyNPR__Engine__ENGINE_VERSION || null,
            SheetMm       :  [Engine.PainterlyNPR__Engine__SHEET_WIDTH_MM, Engine.PainterlyNPR__Engine__SHEET_HEIGHT_MM],
        }));
        return booted;
    }
    // ------------------------------------------------------------


    // FUNCTION | An Action for Ruby: na_npr_window_action(action, json)
    // ------------------------------------------------------------
    function Na__NprHost__Action(action, payload) {
        Na__NprHost__Call('na_npr_window_action', action, JSON.stringify(payload || {}));
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Engine at a Glance
// -----------------------------------------------------------------------------

    // FUNCTION | Did the Engine Boot? { Booted, Error } (its own fallback card says why not)
    // ------------------------------------------------------------
    function Na__NprHost__Booted() {
        const gpu  =  GpuResources.PainterlyNPR__GpuResources__Gpu;
        if (gpu && gpu.Gl) return { Booted: true, Error: null };
        const card    =  document.querySelector('#PainterlyNPR__App__Fallback [data-detail]');
        const detail  =  card && card.textContent.trim();
        return { Booted: false, Error: detail || 'The engine did not start (no WebGL 2 context).' };
    }
    // ------------------------------------------------------------


    // FUNCTION | The Drawing's Look Out of a Settings Object (a copy)
    // ------------------------------------------------------------
    function Na__NprHost__Look(settings) {
        const look  =  {};
        if (!settings || typeof settings !== 'object') return look;
        for (const key of Na__NprHost__LOOK_KEYS) if (settings[key] !== undefined) look[key] = JSON.parse(JSON.stringify(settings[key]));
        return look;
    }
    // ------------------------------------------------------------


    // FUNCTION | The Engine's Sheet Shape (width over height), read from the engine
    // ------------------------------------------------------------
    function Na__NprHost__SheetAspect() {
        const w  =  Number(Engine.PainterlyNPR__Engine__SHEET_WIDTH_MM);
        const h  =  Number(Engine.PainterlyNPR__Engine__SHEET_HEIGHT_MM);
        return w > 0 && h > 0 ? w / h : Math.SQRT2;
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Status Line
// -----------------------------------------------------------------------------

    // FUNCTION | A Status Line Laid Over the Page: { Say(text, level), Clear() }
    // ------------------------------------------------------------
    // level: info (fades), busy (stays, animated), warn and error (stay).
    function Na__NprHost__StatusLine(className) {
        const line   =  document.createElement('div');
        line.className  =  className;
        line.setAttribute('role', 'status');
        line.hidden  =  true;
        document.body.appendChild(line);
        let timer  =  null;
        return {
            Say(text, level) {
                clearTimeout(timer);
                line.textContent    =  String(text || '');
                line.dataset.level  =  level || 'info';
                line.hidden         =  !text;
                if (text && (level || 'info') === 'info') timer = setTimeout(() => { line.hidden = true; }, Na__NprHost__STATUS_FADE);
            },
            Clear() { clearTimeout(timer); line.hidden = true; },
            Element: line,
        };
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Exports
// -----------------------------------------------------------------------------

    export {
        Na__NprHost__Action,
        Na__NprHost__Booted,
        Na__NprHost__Call,
        Na__NprHost__Listen,
        Na__NprHost__Look,
        Na__NprHost__Ready,
        Na__NprHost__SheetAspect,
        Na__NprHost__StatusLine,
    };

// endregion -------------------------------------------------------------------
