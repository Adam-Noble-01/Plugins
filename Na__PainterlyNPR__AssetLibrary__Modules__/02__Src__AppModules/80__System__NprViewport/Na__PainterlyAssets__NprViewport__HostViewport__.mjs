// =============================================================================
// NA PAINTERLYNPR ASSETS - NPR VIEWPORT - HOST, THE VIEWPORT WINDOW
// =============================================================================
//
// FILE       : Na__PainterlyAssets__NprViewport__HostViewport__.mjs
// NAMESPACE  : Na__NprHost
// MODULE     : NPR Viewport - Host, Viewport
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Turn PainterlyNPR's own app page into SketchUp's NPR Viewport:
//              only the drawing shows; the scene is the model's local GLB cache
//              (fetched file by file, only what changed); the camera is
//              SketchUp's; the look comes from the NPR Parameters window
// CREATED    : 01-Nov-2026
//
// DESCRIPTION:
// - RUNS AFTER THE APP'S OWN INIT (the server adds this module after Init's
//   script; module scripts run in order), so the engine has booted, built its
//   panel and drawn its demo cottage's first preview. The panel stays in the
//   page, hidden: the engine's own controls are what the look moves.
// - THE SCENE is handed over as ValeVision AURA's host hands its project's
//   scene (its Na__EngineHost__Scene__): the scene file's objects in Id order,
//   each GLB read with the engine's GlbRead, each mesh file paired with its
//   linework twin, then the engine's SetBase(GlbBase(source)) and Reload. A
//   GLB is fetched only when its version moved; the rest are kept read.
// - PLACED LIBRARY ASSETS (the plugin's proxies in the model) become the
//   engine's plops through its own MakePlacement from the asset's record in
//   the cached library, then take SketchUp's position, turn and scale.
// - THE CAMERA is SketchUp's eye and target (already in the engine's world)
//   made into the engine's orbit camera; the field of view or ortho height is
//   widened when SketchUp's view is wider than the engine's sheet, so all of
//   SketchUp's view shows. Up is always +Y in the engine (no roll).
// - Nothing in the window takes the mouse or the keyboard: the drawing follows
//   SketchUp, never the other way round.
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Module Imports - the Engine (PainterlyNPR, from the cache) and the Host
// -----------------------------------------------------------------------------

    import * as AppState from 'PainterlyNPR/01__AppCore/PainterlyNPR__AppCore__State__.mjs';
    import * as ScenePackage from 'PainterlyNPR/10__Import__ScenePackage/PainterlyNPR__ScenePackage__Build__.mjs';
    import * as Catalogue from 'PainterlyNPR/16__Scene__AssetLibrary/PainterlyNPR__AssetLibrary__Catalogue__.mjs';
    import * as Placement from 'PainterlyNPR/16__Scene__AssetLibrary/PainterlyNPR__AssetLibrary__Placement__.mjs';
    import * as RenderGraph from 'PainterlyNPR/20__System__RenderGraph/PainterlyNPR__RenderGraph__Graph__.mjs';
    import * as Controls from 'PainterlyNPR/80__System__HudOverlay/PainterlyNPR__Interface__Controls__.mjs';
    import * as SettingsJson from 'PainterlyNPR/85__System__ProjectPersistence/PainterlyNPR__Interface__SettingsJson__.mjs';
    import {
        Na__NprHost__Action,
        Na__NprHost__Listen,
        Na__NprHost__Look,
        Na__NprHost__Ready,
        Na__NprHost__SheetAspect,
        Na__NprHost__StatusLine,
    } from './Na__PainterlyAssets__NprViewport__HostShared__.mjs';

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Constants and State
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | The Camera's Limits
    // ------------------------------------------------------------
    const Na__NprViewport__PITCH_LIMIT   =  89.9;                                // <-- The engine looks at its target with +Y up: never straight down
    const Na__NprViewport__ORTHO_BACK_M  =  300;                                 // <-- An ortho eye stands this far back, so nothing is behind the near clip
    // ------------------------------------------------------------

    // MODULE VARIABLES | The Scene Loaded and the Load in Flight
    // ------------------------------------------------------------
    const Na__NprViewport__State  =  {
        state     :  AppState.PainterlyNPR__AppCore__State,
        glbs      :  new Map(),                                                  // <-- File name -> { Version, Glb } (the engine's GlbRead)
        loaded    :  false,                                                      // <-- The model has replaced the demo cottage
        loading   :  false,
        queued    :  null,                                                       // <-- The newest scene message while one loads
        live      :  true,
        status    :  null,
        pause     :  null,
    };
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Boot
// -----------------------------------------------------------------------------

    // FUNCTION | Take Over the Page: quiet, still, listening, then say ready
    // ------------------------------------------------------------
    function Na__NprViewport__Boot() {
        const S  =  Na__NprViewport__State;
        document.documentElement.classList.add('Na__NprHost', 'Na__NprHost--Viewport', 'Na__NprHost--Waiting');
        S.status  =  Na__NprHost__StatusLine('Na__NprHost__Status');
        S.pause   =  document.createElement('div');
        S.pause.className  =  'Na__NprHost__Paused';
        S.pause.title      =  'Live NPR updates are off: the drawing holds still while you work. Turn them back on with the Live button.';
        S.pause.hidden     =  true;
        document.body.appendChild(S.pause);
        Na__NprViewport__HoldStill();
        Na__NprHost__Listen(Na__NprViewport__Receive);

        const booted  =  Na__NprHost__Ready('viewport');
        if (!booted.Booted) {
            document.documentElement.classList.remove('Na__NprHost--Waiting');       // <-- The engine's own fallback card says why
            return;
        }
        if (typeof RenderGraph.PainterlyNPR__RenderGraph__SetProxy === 'function') RenderGraph.PainterlyNPR__RenderGraph__SetProxy(true);   // <-- No pen and wash for the demo cottage while the model comes
        S.status.Say('Waiting for the SketchUp model', 'busy');
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | No Mouse, No Keys: the drawing follows SketchUp
    // ------------------------------------------------------------
    // Caught before the engine's own handlers (capture, on the window). F5
    // still reloads the page; the engine's keys and its navigation never see it.
    function Na__NprViewport__HoldStill() {
        const stop  =  (event) => { event.stopImmediatePropagation(); if (event.cancelable && event.type !== 'keydown') event.preventDefault(); };
        for (const type of ['pointerdown', 'pointermove', 'pointerup', 'mousedown', 'mouseup', 'click', 'dblclick', 'wheel', 'contextmenu', 'touchstart', 'keyup', 'keypress']) {
            window.addEventListener(type, stop, { capture: true, passive: false });
        }
        window.addEventListener('keydown', (event) => {
            event.stopImmediatePropagation();
            if (event.key !== 'F5') event.preventDefault();
        }, { capture: true });
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Messages From SketchUp
// -----------------------------------------------------------------------------

    // FUNCTION | One Message: scene | camera | settings | live | status
    // ------------------------------------------------------------
    function Na__NprViewport__Receive(kind, payload) {
        const S  =  Na__NprViewport__State;
        if (kind === 'scene') return Na__NprViewport__QueueScene(payload);
        if (kind === 'camera') return Na__NprViewport__Camera(payload);
        if (kind === 'settings') return Na__NprViewport__Settings(payload);
        if (kind === 'status') return S.status.Say(payload.Text, payload.Level);
        if (kind === 'live') {
            S.live  =  payload.On !== false;
            S.pause.hidden  =  S.live;
        }
        return null;
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Scene: the Model's GLB Cache
// -----------------------------------------------------------------------------

    // FUNCTION | Load a Scene Message; a newer one while loading replaces the queued one
    // ------------------------------------------------------------
    async function Na__NprViewport__QueueScene(message) {
        const S  =  Na__NprViewport__State;
        if (S.loading) { S.queued = message; return; }
        S.loading  =  true;
        try {
            await Na__NprViewport__LoadScene(message);
        } catch (error) {
            console.error('[Na NPR Viewport] The scene could not be loaded:', error);
            S.status.Say(`The model could not be drawn: ${error.message}`, 'error');
            Na__NprHost__Action('status', { Text: `NPR Viewport: the model could not be drawn (${error.message}).`, Level: 'error' });
        } finally {
            S.loading  =  false;
        }
        if (S.queued) {
            const next  =  S.queued;
            S.queued  =  null;
            await Na__NprViewport__QueueScene(next);
        }
    }
    // ------------------------------------------------------------


    // FUNCTION | Fetch What Changed, Read It With the Engine, Hand the Engine Its Base
    // ------------------------------------------------------------
    async function Na__NprViewport__LoadScene(message) {
        const S        =  Na__NprViewport__State;
        const started  =  performance.now();
        if (typeof ScenePackage.PainterlyNPR__ScenePackage__SetBase !== 'function' || typeof ScenePackage.PainterlyNPR__ScenePackage__GlbBase !== 'function') {
            throw new Error('this PainterlyNPR has no GLB scenes (SetBase and GlbBase, v0.8.7 on)');
        }
        const base     =  message.Base;
        const response =  await fetch(`${base}${encodeURIComponent(message.SceneFile)}?r=${message.SceneRevision}`, { cache: 'no-store' });
        if (!response.ok) throw new Error(`the scene file answered ${response.status}`);
        const scene    =  await response.json();

        // The files the scene draws or pairs with: each fetched again only when its version moved
        const versions =  new Map((message.Files || []).map((f) => [f.Name, f.Version]));
        const wanted   =  (scene.NprScene__ModelFiles || []).filter((f) => f.ModelFile__Use === 'Draw' || f.ModelFile__Use === 'SourceLinework');
        let fetched    =  0;
        for (const file of wanted) {
            const name     =  file.ModelFile__FileName;
            const version  =  versions.get(name) || 0;
            const held     =  S.glbs.get(name);
            if (held && held.Version === version) continue;
            S.status.Say(`Loading ${name.replace(/__+/g, ' ').replace(/\.glb$/i, '').trim()}`, 'busy');
            const reply  =  await fetch(`${base}${encodeURIComponent(name)}?v=${version}`, { cache: 'no-store' });
            if (!reply.ok) throw new Error(`${name} answered ${reply.status}`);
            S.glbs.set(name, { Version: version, Glb: ScenePackage.PainterlyNPR__ScenePackage__GlbRead(new Uint8Array(await reply.arrayBuffer())) });
            fetched++;
        }
        const names  =  new Set(wanted.map((f) => f.ModelFile__FileName));
        for (const name of [...S.glbs.keys()]) if (!names.has(name)) S.glbs.delete(name);

        // The base in the cottage's place, the model's placed assets on it
        const glbs   =  new Map([...S.glbs].map(([name, held]) => [name, held.Glb]));
        ScenePackage.PainterlyNPR__ScenePackage__SetBase(ScenePackage.PainterlyNPR__ScenePackage__GlbBase(Na__NprViewport__Source(scene, glbs)));
        const plops  =  await Na__NprViewport__Plops(message.Proxies || []);
        S.state.Assets  =  plops.Plops;
        ScenePackage.PainterlyNPR__ScenePackage__Reload(S.state.Assets, S.state.Materials || []);
        RenderGraph.PainterlyNPR__RenderGraph__Bump('Scene');
        if (!S.loaded) {
            S.loaded  =  true;
            document.documentElement.classList.remove('Na__NprHost--Waiting');
            if (typeof RenderGraph.PainterlyNPR__RenderGraph__SetProxy === 'function') RenderGraph.PainterlyNPR__RenderGraph__SetProxy(false);
        }
        RenderGraph.PainterlyNPR__RenderGraph__Request('Navigate');

        const counts  =  ScenePackage.PainterlyNPR__ScenePackage__Scene && ScenePackage.PainterlyNPR__ScenePackage__Scene.Source;
        const ms      =  Math.round(performance.now() - started);
        const note    =  `${counts ? counts.Objects : '?'} objects from ${wanted.filter((f) => f.ModelFile__Kind === 'Mesh').length} model files (${fetched} fetched), ${plops.Plops.length} placed assets, in ${ms} ms.`
                      +  (plops.Missing.length ? ` Not in PainterlyNPR's library yet: ${plops.Missing.join(', ')}.` : '');
        S.status.Say(note, plops.Missing.length ? 'warn' : 'info');
        Na__NprHost__Action('status', { Text: `NPR Viewport: ${note}`, Level: plops.Missing.length ? 'warn' : 'info' });
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Engine's Scene Source From the Scene File (AURA's host makes its own the same way)
    // ------------------------------------------------------------
    // Objects in Id order, each with its file and node; each mesh file paired
    // with its linework twin (the pen's hard edges).
    function Na__NprViewport__Source(scene, glbs) {
        const files  =  scene.NprScene__ModelFiles || [];
        const byId   =  new Map(files.map((f) => [f.ModelFile__Id, f]));
        const twins  =  new Map();
        for (const f of files) {
            const twin  =  f.ModelFile__Kind === 'Mesh' && f.ModelFile__Twin ? byId.get(f.ModelFile__Twin) : null;
            if (twin && glbs.has(twin.ModelFile__FileName)) twins.set(f.ModelFile__FileName, twin.ModelFile__FileName);
        }
        const placement  =  scene.NprScene__ModelPlacement || {};
        return {
            Placement :  { OffsetM: placement.OffsetM || [0, 0, 0], RotationDeg: placement.RotationDeg || 0 },
            Objects   :  (scene.NprScene__Objects || []).map((o) => {
                const file  =  byId.get(o.Object__ModelFile);
                return { Id: o.Object__Id, Name: o.Object__Name, Category: o.Object__Category, Material: o.Object__Material, Role: o.Object__Role,
                         File: file ? file.ModelFile__FileName : '', Node: o.Object__Node, Missing: o.Object__Missing === true || !file };
            }),
            Glbs      :  glbs,
            Twins     :  twins,
        };
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Model's Placed Library Assets as the Engine's Plops: { Plops, Missing }
    // ------------------------------------------------------------
    // Made by the engine's own MakePlacement from the asset's record in the
    // cached library (its recipe and its shape's seed), then put where SketchUp
    // has it: SketchUp's turn and scale stand, never the asset's Facing or jitter.
    async function Na__NprViewport__Plops(proxies) {
        if (!proxies.length || typeof Placement.PainterlyNPR__AssetLibrary__MakePlacement !== 'function') return { Plops: [], Missing: [] };
        await Catalogue.PainterlyNPR__AssetLibrary__LoadCatalogue();
        const library  =  Catalogue.PainterlyNPR__AssetLibrary__Catalogue;
        const plops    =  [];
        const missing  =  new Set();
        for (const proxy of proxies) {
            const asset  =  library && library.ById ? library.ById.get(proxy.AssetId) : null;
            if (!asset) { missing.add(proxy.AssetId); continue; }
            const plop  =  Placement.PainterlyNPR__AssetLibrary__MakePlacement(asset, proxy.PositionM, proxy.Seed >>> 0, proxy.Uid, null);
            plop.Position     =  proxy.PositionM.slice();
            plop.RotationDeg  =  proxy.RotationDeg;
            plop.Scale        =  proxy.Scale;
            plops.push(plop);
        }
        return { Plops: plops, Missing: [...missing] };
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Camera: SketchUp's View in the Engine's Camera
// -----------------------------------------------------------------------------

    // FUNCTION | Look From Where SketchUp Looks
    // ------------------------------------------------------------
    // The engine's camera is an orbit: an eye at Distance from Target, along
    // Yaw (about +Y, 0 looking towards -Z) and Pitch (above the target). Its
    // sheet has the engine's own shape: a wider SketchUp view widens the field
    // of view (or the ortho height) so none of SketchUp's view is lost.
    function Na__NprViewport__Camera(c) {
        const S       =  Na__NprViewport__State;
        const eye     =  c.EyeM;
        const target  =  c.TargetM;
        if (!Array.isArray(eye) || !Array.isArray(target)) return;
        const d       =  [eye[0] - target[0], eye[1] - target[1], eye[2] - target[2]];
        const length  =  Math.hypot(d[0], d[1], d[2]);
        if (!(length > 1e-6)) return;
        const DEG     =  180 / Math.PI;
        const pitch   =  Math.max(-Na__NprViewport__PITCH_LIMIT, Math.min(Na__NprViewport__PITCH_LIMIT, Math.asin(Math.max(-1, Math.min(1, d[1] / length))) * DEG));
        const yaw     =  Math.atan2(d[0], d[2]) * DEG;
        const wider   =  Math.max(1, (Number(c.Aspect) || 1) / Na__NprHost__SheetAspect());
        const camera  =  Object.assign({}, S.state.Camera, { Mode: c.Mode === 'Ortho' ? 'Ortho' : 'Perspective', Yaw: yaw, Pitch: pitch, Target: target.slice() });
        if (camera.Mode === 'Ortho') {
            camera.HalfHeight  =  Number(c.HalfHeightM) * wider;
            camera.Distance    =  Math.max(length, Na__NprViewport__ORTHO_BACK_M);
        } else {
            camera.FovY      =  2 * Math.atan(Math.tan(Number(c.FovYDeg) / 2 / DEG) * wider) * DEG;
            camera.Distance  =  length;
        }
        S.state.Camera        =  camera;
        S.state.CameraPreset  =  'Custom';
        RenderGraph.PainterlyNPR__RenderGraph__Bump('Camera');
        RenderGraph.PainterlyNPR__RenderGraph__Request('Navigate');                // <-- The preview at once, the pen and wash once SketchUp's view rests
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Look: From the NPR Parameters Window
// -----------------------------------------------------------------------------

    // FUNCTION | A Control's Move, or the Whole Look
    // ------------------------------------------------------------
    // A control goes through the engine's own SetControl (only its inputs are
    // bumped). A settings object is put back through the engine's own
    // ApplySettingsJson with this window's camera, points and placed assets
    // kept, and only when it differs from what is drawn.
    function Na__NprViewport__Settings(payload) {
        if (payload.Control && typeof Controls.PainterlyNPR__Interface__SetControl === 'function') {
            Controls.PainterlyNPR__Interface__SetControl(String(payload.Control.Key), Number(payload.Control.Value));
            return;
        }
        if (!payload.Settings || typeof SettingsJson.PainterlyNPR__Interface__ApplySettingsJson !== 'function') return;
        const now   =  SettingsJson.PainterlyNPR__Interface__SettingsObject();
        const look  =  Na__NprHost__Look(payload.Settings);
        if (JSON.stringify(look) === JSON.stringify(Na__NprHost__Look(now))) return;
        SettingsJson.PainterlyNPR__Interface__ApplySettingsJson(JSON.stringify(Object.assign({}, now, look)));
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


    Na__NprViewport__Boot();
