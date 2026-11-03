// =============================================================================
// NA PAINTERLYNPR ASSETS - NPR VIEWPORT - HOST, EDITING
// =============================================================================
//
// FILE       : Na__PainterlyAssets__NprViewport__HostEditing__.mjs
// NAMESPACE  : Na__NprEdit
// MODULE     : NPR Viewport - Host, Editing
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : PainterlyNPR's own Assets drawer and art direction points in the
//              NPR Viewport: a menu folded away each side of the drawing, and
//              everything they do kept in the SketchUp model
// CREATED    : 03-Nov-2026 (v0.4.0)
//
// DESCRIPTION:
// - Adam, 03-Nov-2026: "Add art control points system and a in engine assets /
//   materials system in the SketchUp Plugin ... Collapsed by default to keep the
//   SketchUp NPR Viewer clean and lightweight but you can pop each side open and
//   resize the menus if needed ... DO NOT REINVENT THE WHEEL ... never duplicate
//   code". So NOTHING HERE IS A COPY: the drawer and its Materials toggle, the
//   drop, the brush, the Move Tool, the right-click menu, the point editor and
//   its parameter mapping, the fold buttons and the drag handles are all the
//   engine's, built by its own Init in this page, from the repo. This module
//   only folds them away, keeps the camera SketchUp's, and listens.
// - THE CAMERA STAYS SKETCHUP'S: the engine's own view lock holds its navigation
//   still, so a press on the sheet is still a press (a point placed, a plop
//   dropped, a click selected) and never an orbit. The lock's keys and the
//   engine's other camera and work mode keys are kept from it.
// - THE MODEL IS THE TRUTH. Every change the engine makes to its placed assets
//   and materials is told to OnAssetsChanged, and compared here with what the
//   model last held: what moved goes to Ruby as one batch (Na__ModelEdits), one
//   undo step. The engine's own draw is the instant preview; the next scene from
//   the model replaces it. Each scene says which batches it shows (EditsThrough):
//   while one is still on its way the page keeps its own lists.
// - A MATERIAL GIVEN TO THE MODEL'S OWN GEOMETRY is painted in the model, and the
//   engine reads the paint from the GLB (its swatch's class): so the assignment
//   is only a preview, dropped once a scene shows the batch. Its ray is where the
//   pointer was, or, given from a menu with no pointer on the drawing, a point on
//   what it was given to. A material given to a plop's part is kept on the proxy
//   instance and given back to the engine with every scene.
// - THE POINTS ARE THE ENGINE'S, as its settings object serialises them, so every
//   value of every type (and any added to the repo later) is kept with nothing
//   changed here. One set a SketchUp scene. An object-anchored point's PaperMm
//   moves with the camera, so it does not count as a change.
// - Undo and redo are SketchUp's: Ctrl + Z here, and the engine's menu, ask for
//   them, and what they took back returns as a new scene and a new set of points.
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Module Imports - the Engine (PainterlyNPR, from the cache)
// -----------------------------------------------------------------------------

    import * as AppState from 'PainterlyNPR/01__AppCore/PainterlyNPR__AppCore__State__.mjs';
    import * as ScenePackage from 'PainterlyNPR/10__Import__ScenePackage/PainterlyNPR__ScenePackage__Build__.mjs';
    import * as MaterialFaces from 'PainterlyNPR/17__Scene__MaterialAssignment/PainterlyNPR__MaterialAssignment__Faces__.mjs';
    import * as MaterialLibrary from 'PainterlyNPR/17__Scene__MaterialAssignment/PainterlyNPR__MaterialAssignment__Library__.mjs';
    import * as CameraRig from 'PainterlyNPR/70__Camera__ViewTypes/PainterlyNPR__CameraRig__Camera__.mjs';
    import * as CameraControls from 'PainterlyNPR/80__System__HudOverlay/PainterlyNPR__Interface__CameraControls__.mjs';
    import * as Dom from 'PainterlyNPR/80__System__HudOverlay/PainterlyNPR__Interface__Dom__.mjs';
    import * as Folds from 'PainterlyNPR/80__System__HudOverlay/PainterlyNPR__Interface__Folds__.mjs';
    import * as AssetDrawer from 'PainterlyNPR/82__Hud__AssetCatalogue/PainterlyNPR__Interface__AssetDrawer__.mjs';
    import * as SceneMenus from 'PainterlyNPR/83__Hud__SceneEditing/PainterlyNPR__SceneEdit__Menus__.mjs';
    import * as SceneSelection from 'PainterlyNPR/83__Hud__SceneEditing/PainterlyNPR__SceneEdit__Selection__.mjs';
    import * as SettingsJson from 'PainterlyNPR/85__System__ProjectPersistence/PainterlyNPR__Interface__SettingsJson__.mjs';

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Constants and State
// -----------------------------------------------------------------------------

    // MODULE CONSTANTS | Timing, the Engine's Lines Nobody Needs, and the Keys It Keeps
    // ------------------------------------------------------------
    const Na__NprEdit__POINTS_MS   =  300;                                       // <-- The points are kept once the page is still this long
    const Na__NprEdit__RAY_BACK_M  =  0.25;                                      // <-- A ray from a menu starts this far off the surface it looks for
    const Na__NprEdit__SAID_MS     =  6000;                                      // <-- What a batch did stays this long: the sync it brings about has its own lines, a moment later
    const Na__NprEdit__PROGRESS    =  /^(Refin|Navigation preview|Proxy mode|Building the first|View (un)?locked|The view is locked)/;   // <-- The render graph's own progress, and the lock SketchUp's camera holds
    const Na__NprEdit__KEYS        =  new Set(['Escape', 'Delete', 'Backspace', 'Enter', 'Tab', 'Shift', 'Control', 'Alt', 'Meta', '[', ']', '{', '}', 'h', 'H', 'm', 'M', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End', 'PageUp', 'PageDown', ' ']);   // <-- The drawer's, the points' and the Move Tool's, a slider's and a drag handle's
    const Na__NprEdit__CTRL_KEYS   =  new Set(['c', 'C', 'v', 'V', 'd', 'D', 'a', 'A', 'x', 'X']);   // <-- Copy and paste a point, copy a plop
    // ------------------------------------------------------------

    // MODULE VARIABLES | What the Model Last Held, What Is on Its Way
    // ------------------------------------------------------------
    const Na__NprEdit__State  =  {
        hooks        :  null,                                                    // <-- { Say(text, level, holdMs), Action(name, payload) }
        ready        :  false,
        loaded       :  false,                                                   // <-- The model's scene has replaced the demo cottage
        applying     :  false,                                                   // <-- This module is changing the engine's lists: not a new edit
        project      :  '',
        seq          :  0,
        pending      :  [],                                                      // <-- Batches no scene has shown yet
        plops        :  new Map(),                                               // <-- Uid -> the plop as the model holds it
        parts        :  new Map(),                                               // <-- Uid -> JSON of what its parts were given
        paints       :  new Map(),                                               // <-- A preview assignment's Uid -> the batch that painted it
        pick         :  null,                                                    // <-- What the last press on the drawing landed on
        drop         :  null,                                                    // <-- The ray of a card being let go, for this event only
        pointsSet    :  'working',                                               // <-- The set on the sheet
        pointsProject:  '',                                                      // <-- The model that set belongs to
        pointsSent   :  '[]',                                                    // <-- What the model holds of it
        pointsTimer  :  null,
        pointsWaiting:  null,                                                    // <-- A set that came before the model did
        exportBack   :  null,                                                    // <-- The sheet's own points, while NPR Export draws a scene's
    };
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Boot
// -----------------------------------------------------------------------------

    // FUNCTION | Give the Engine's Interface Its Places: true when it can be edited
    // ------------------------------------------------------------
    function Na__NprEdit__Boot(hooks) {
        const S  =  Na__NprEdit__State;
        S.hooks  =  hooks;
        if (!Na__NprEdit__EngineHasAll()) {
            document.documentElement.classList.add('Na__NprHost--NoMenus');
            console.warn('[Na NPR Viewport] This PainterlyNPR lacks part of the drawer or the points: Reload Remote Plugin Files gets its latest.');
            return false;
        }
        Na__NprEdit__Menus();
        Na__NprEdit__StatusStandIn();
        CameraControls.PainterlyNPR__Interface__ToggleViewLock(true, true);
        Na__NprEdit__WireKeys();
        Na__NprEdit__WatchPointer();
        Na__NprEdit__WatchPoints();
        AssetDrawer.PainterlyNPR__Interface__OnAssetsChanged(Na__NprEdit__AssetsChanged);
        SceneMenus.PainterlyNPR__SceneEdit__Wire({                               // <-- A second wiring, for its History seam: its listeners read what they did and stand aside
            History : {
                Label : () => 'in SketchUp',
                Undo  : () => hooks.Action('undo'),
                Redo  : () => hooks.Action('redo'),
            },
        });
        window.addEventListener('beforeunload', (event) => event.stopImmediatePropagation(), { capture: true });   // <-- The engine's "Leave site?" is for a drawing only it holds: this one is in the model
        S.ready  =  true;
        return true;
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | Is All of It in This Engine? (imported as namespaces, so an older one still loads)
    // ------------------------------------------------------------
    function Na__NprEdit__EngineHasAll() {
        return [
            AssetDrawer.PainterlyNPR__Interface__AssetsChanged,
            AssetDrawer.PainterlyNPR__Interface__OnAssetsChanged,
            AssetDrawer.PainterlyNPR__Interface__SetAssetDrawer,
            CameraControls.PainterlyNPR__Interface__ToggleViewLock,
            CameraRig.PainterlyNPR__CameraRig__Unproject,
            Folds.PainterlyNPR__Interface__SetFold,
            MaterialFaces.PainterlyNPR__MaterialAssignment__Corners,
            MaterialFaces.PainterlyNPR__MaterialAssignment__FaceTriangles,
            MaterialFaces.PainterlyNPR__MaterialAssignment__ResolveObject,
            MaterialFaces.PainterlyNPR__MaterialAssignment__Triangles,
            MaterialLibrary.PainterlyNPR__MaterialAssignment__Give,
            SceneMenus.PainterlyNPR__SceneEdit__Wire,
            SceneSelection.PainterlyNPR__SceneEdit__PickAt,
            SceneSelection.PainterlyNPR__SceneEdit__Select,
            SceneSelection.PainterlyNPR__SceneEdit__Selected,
            SettingsJson.PainterlyNPR__Interface__ApplySettingsJson,
            SettingsJson.PainterlyNPR__Interface__SettingsObject,
        ].every((fn) => typeof fn === 'function') && !!Dom.PainterlyNPR__Interface__Ui;
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Menus: Folded Away, Each the Engine's Own
// -----------------------------------------------------------------------------

    // FUNCTION | Both Folded Whenever the Window Opens; the Panel Is Art Direction Alone
    // ------------------------------------------------------------
    // Neither fold is remembered as folded, so the widths the engine remembers
    // are all that carries over. While the panel is out its Art direction section
    // is open, which is what shows the points on the sheet (Ui.ActiveTab); folded,
    // they leave the sheet with it.
    function Na__NprEdit__Menus() {
        const Ui    =  Dom.PainterlyNPR__Interface__Ui;
        const root  =  Ui.Root;
        Folds.PainterlyNPR__Interface__SetFold('Panel', true, false);
        AssetDrawer.PainterlyNPR__Interface__SetAssetDrawer(false, false);
        for (const button of document.querySelectorAll('[data-assets-factory], [data-materials-factory]')) {
            const section  =  button.closest('section');
            if (section) section.remove();                                       // <-- The factory writes through PainterlyNPR's own server: this window has none
        }

        const art    =  document.querySelector('.PainterlyNPR__Section[data-panel="ArtDirection"]');
        const title  =  art ? art.querySelector('.PainterlyNPR__Section__Title') : null;
        const label  =  title ? title.textContent.trim() : '';
        const head   =  document.querySelector('.PainterlyNPR__PanelHead__Title');
        const tab    =  document.querySelector('.PainterlyNPR__Unfold--panel');
        if (label && head) head.textContent = label;
        if (label && tab) { tab.textContent = `‹ ${label}`; tab.title = `Show ${label.toLowerCase()}: the points on this drawing`; }

        const follow  =  () => {
            const out  =  !root.classList.contains('PainterlyNPR--foldPanel');
            if (art && art.open !== out) art.open = out;
            if (!out && Ui.Placing) {
                Ui.Placing  =  null;
                root.classList.remove('PainterlyNPR--placing');
            }
        };
        new MutationObserver(follow).observe(root, { attributes: true, attributeFilter: ['class'] });
        follow();
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Engine's Status Line, Through the Window's Own
    // ------------------------------------------------------------
    // Ui.Status is the seam every wrapper has (a stand-in): what the engine says
    // to the person reaches the status line laid over the drawing, its render
    // progress does not. The element keeps every line: NPR Export reads it.
    function Na__NprEdit__StatusStandIn() {
        const Ui    =  Dom.PainterlyNPR__Interface__Ui;
        const real  =  Ui.Status;
        Ui.Status   =  {
            get textContent() { return real ? real.textContent : ''; },
            set textContent(text) {
                if (real) real.textContent = text;
                const line  =  String(text || '');
                if (!line || Na__NprEdit__PROGRESS.test(line)) return;
                Na__NprEdit__State.hooks.Say(line, /^Error\b/.test(line) ? 'error' : 'info', 1);   // <-- The person just did something: this line is the answer, whatever was holding the line
            },
        };
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | Only the Editing Keys Reach the Engine; Ctrl + Z and Ctrl + Y Are SketchUp's
    // ------------------------------------------------------------
    // Caught before the engine's own handlers (capture, on the window). Typing in
    // a field keeps every key. F5 still reloads the page.
    function Na__NprEdit__WireKeys() {
        window.addEventListener('keydown', (event) => {
            const focus   =  document.activeElement;
            const typing  =  !!focus && (/^(TEXTAREA|SELECT)$/.test(focus.tagName) || (focus.tagName === 'INPUT' && focus.type !== 'range') || focus.isContentEditable);
            if (event.key === 'F5') { event.stopImmediatePropagation(); return; }
            if (typing) return;
            const held    =  event.ctrlKey || event.metaKey;
            const key     =  String(event.key).toLowerCase();
            if (held && (key === 'z' || key === 'y')) {
                event.stopImmediatePropagation();
                event.preventDefault();
                if (!event.repeat) Na__NprEdit__State.hooks.Action(key === 'y' || event.shiftKey ? 'redo' : 'undo');
                return;
            }
            if (held ? Na__NprEdit__CTRL_KEYS.has(event.key) : Na__NprEdit__KEYS.has(event.key)) return;
            event.stopImmediatePropagation();
            event.preventDefault();
        }, { capture: true });
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Where the Pointer Is: the Rays Ruby Needs
// -----------------------------------------------------------------------------

    // FUNCTION | Keep What the Pointer Landed On, Before the Engine Acts On It
    // ------------------------------------------------------------
    // A press on the drawing (a brush's click, a right click before its menu), and
    // a card or a swatch let go over it. Read in the capture phase: the engine's
    // own handlers make their change later in the same event.
    function Na__NprEdit__WatchPointer() {
        const S      =  Na__NprEdit__State;
        const sheet  =  document.getElementById('PainterlyNPR__App__Sheet');
        const root   =  Dom.PainterlyNPR__Interface__Ui.Root;
        const pick   =  (event) => {
            const landed  =  SceneSelection.PainterlyNPR__SceneEdit__PickAt(event.clientX, event.clientY);
            if (landed) S.pick = landed;
        };
        const drop   =  (event) => {
            S.drop  =  Na__NprEdit__RayAt(event.clientX, event.clientY);
            setTimeout(() => { S.drop = null; }, 0);                             // <-- For this event only: a later copy of a plop has no pointer
        };
        window.addEventListener('pointerdown', (event) => {
            if (sheet && sheet.contains(event.target)) pick(event);
            if (root.classList.contains('PainterlyNPR--placingAsset')) drop(event);
        }, { capture: true });
        window.addEventListener('pointerup', (event) => {
            if (!root.classList.contains('PainterlyNPR--draggingAsset')) return;
            pick(event);
            drop(event);
        }, { capture: true });
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Camera's Ray Under a Point of the Page: { OriginM, DirM }, or null off the sheet
    // ------------------------------------------------------------
    function Na__NprEdit__RayAt(clientX, clientY) {
        const canvas  =  Dom.PainterlyNPR__Interface__Ui.Canvas;
        const camera  =  CameraRig.PainterlyNPR__CameraRig__Camera;
        if (!canvas || !camera) return null;
        const rect  =  canvas.getBoundingClientRect();
        if (clientX < rect.left || clientX > rect.right || clientY < rect.top || clientY > rect.bottom) return null;
        const x  =  ((clientX - rect.left) / rect.width) * camera.Width;
        const y  =  (1 - (clientY - rect.top) / rect.height) * camera.Height;
        const a  =  CameraRig.PainterlyNPR__CameraRig__Unproject(x, y, 1);
        const b  =  CameraRig.PainterlyNPR__CameraRig__Unproject(x, y, 2);
        const d  =  [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
        const n  =  Math.hypot(d[0], d[1], d[2]);
        return n > 0 ? { OriginM: a, DirM: d.map((v) => v / n) } : null;
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Ray for a Material Given: Where the Pointer Was, Else a Point on What It Was Given To
    // ------------------------------------------------------------
    // A press on the object itself: the engine's own pick, which starts just
    // short of the surface, so nothing the drawing does not show gets in the way.
    function Na__NprEdit__PaintRay(assignment) {
        const pick  =  Na__NprEdit__State.pick;
        if (pick && !pick.Sky && pick.Key === assignment.Object) return { OriginM: pick.Origin, DirM: pick.Dir };
        const scene   =  ScenePackage.PainterlyNPR__ScenePackage__Scene;
        const object  =  scene ? MaterialFaces.PainterlyNPR__MaterialAssignment__ResolveObject(scene, assignment.Object) : null;
        if (!object) return null;
        const face       =  assignment.Target === 'Face' ? MaterialFaces.PainterlyNPR__MaterialAssignment__FaceTriangles(scene, object.Id, assignment.Face) : null;
        const triangles  =  face ? face.Triangles : (MaterialFaces.PainterlyNPR__MaterialAssignment__Triangles(scene).get(object.Id) || []);
        if (!triangles.length) return null;
        const corners  =  MaterialFaces.PainterlyNPR__MaterialAssignment__Corners(scene.Vertices, triangles[0]);
        const offset   =  triangles[0] * 24;
        const normal   =  [scene.Vertices[offset + 3], scene.Vertices[offset + 4], scene.Vertices[offset + 5]];
        const centre   =  [0, 1, 2].map((axis) => (corners[0][axis] + corners[1][axis] + corners[2][axis]) / 3);
        return { OriginM: centre.map((v, axis) => v + normal[axis] * Na__NprEdit__RAY_BACK_M), DirM: normal.map((v) => -v) };
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Engine Changed Its Lists: What Moved Goes to the Model
// -----------------------------------------------------------------------------

    // FUNCTION | Hear Every Change, Whoever Made It in the Engine (its drawer, a drop, the brush, its menu, its Move Tool)
    // ------------------------------------------------------------
    function Na__NprEdit__AssetsChanged() {
        const S  =  Na__NprEdit__State;
        if (S.applying) return;
        const edits  =  Na__NprEdit__Diff();
        if (edits.length) {
            S.seq += 1;
            S.pending.push(S.seq);
        }
        Na__NprEdit__Remember(S.seq);
        if (edits.length) S.hooks.Action('modelEdits', { Seq: S.seq, Edits: edits });
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Engine's Lists Against What the Model Last Held: the Batch of Edits
    // ------------------------------------------------------------
    function Na__NprEdit__Diff() {
        const S      =  Na__NprEdit__State;
        const state  =  AppState.PainterlyNPR__AppCore__State;
        const edits  =  [];
        const here   =  new Set();
        for (const plop of state.Assets) {
            here.add(plop.Uid);
            const was   =  S.plops.get(plop.Uid);
            const pose  =  { Uid: plop.Uid, AssetId: plop.AssetId, Name: plop.Name, PositionM: plop.Position, RotationDeg: plop.RotationDeg, Scale: plop.Scale };
            if (!was) {
                edits.push(Object.assign({ Kind: 'Add', ShapeSeed: plop.Seed, Ray: S.drop }, pose));
                S.drop  =  null;
            } else if (Na__NprEdit__PlopKey(was) !== Na__NprEdit__PlopKey(plop)) {
                edits.push(Object.assign({ Kind: 'Pose' }, was.Seed !== plop.Seed ? { ShapeSeed: plop.Seed } : {}, pose));
            }
        }
        for (const [uid, was] of S.plops) if (!here.has(uid)) edits.push({ Kind: 'Remove', Uid: uid, Name: was.Name });

        const parts  =  Na__NprEdit__PartsOf(state.Materials);
        for (const plop of state.Assets) {
            const given  =  parts.get(plop.Uid) || '[]';
            if (given !== (S.parts.get(plop.Uid) || '[]')) edits.push({ Kind: 'PlopMaterials', Uid: plop.Uid, Name: plop.Name, Materials: JSON.parse(given) });
        }
        for (const assignment of state.Materials) {
            if (assignment.Object[0] !== '#' || S.paints.has(assignment.Uid)) continue;
            const scene   =  ScenePackage.PainterlyNPR__ScenePackage__Scene;
            const object  =  scene ? MaterialFaces.PainterlyNPR__MaterialAssignment__ResolveObject(scene, assignment.Object) : null;
            edits.push({ Kind: 'Paint', Uid: assignment.Uid, Target: assignment.Target, Material: assignment.Material, Name: object ? object.Name : assignment.Object, Ray: Na__NprEdit__PaintRay(assignment) });
        }
        return edits;
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | What the Model Now Holds, as Far as This Page Knows
    // ------------------------------------------------------------
    // seq: the batch a preview assignment first seen now went in.
    function Na__NprEdit__Remember(seq) {
        const S      =  Na__NprEdit__State;
        const state  =  AppState.PainterlyNPR__AppCore__State;
        S.plops  =  new Map(state.Assets.map((plop) => [plop.Uid, { AssetId: plop.AssetId, Name: plop.Name, Position: plop.Position.slice(), RotationDeg: plop.RotationDeg, Scale: plop.Scale, Seed: plop.Seed }]));
        S.parts  =  Na__NprEdit__PartsOf(state.Materials);
        const paints  =  new Map();
        for (const assignment of state.Materials) {
            if (assignment.Object[0] === '#') paints.set(assignment.Uid, S.paints.has(assignment.Uid) ? S.paints.get(assignment.Uid) : seq);
        }
        S.paints  =  paints;
    }

    function Na__NprEdit__PlopKey(plop) {
        return JSON.stringify([plop.AssetId, plop.Position, plop.RotationDeg, plop.Scale, plop.Seed]);
    }

    // Uid -> JSON of what its parts were given, in the order given
    function Na__NprEdit__PartsOf(assignments) {
        const rows  =  new Map();
        for (const assignment of assignments) {
            if (assignment.Object[0] === '#') continue;
            const [uid, part]  =  assignment.Object.split('.');
            if (!rows.has(uid)) rows.set(uid, []);
            rows.get(uid).push({ Part: part, Face: assignment.Target === 'Face' ? assignment.Face : null, Material: assignment.Material });
        }
        return new Map([...rows].map(([uid, list]) => [uid, JSON.stringify(list)]));
    }
    // ------------------------------------------------------------


    // FUNCTION | The Scene Rebuilt From the Engine's Lists: By Its Own Hand, Not Told On as an Edit
    // ------------------------------------------------------------
    function Na__NprEdit__Rebuild() {
        const S  =  Na__NprEdit__State;
        if (typeof AssetDrawer.PainterlyNPR__Interface__AssetsChanged !== 'function') return;
        S.applying  =  true;
        try {
            AssetDrawer.PainterlyNPR__Interface__AssetsChanged();
        } finally {
            S.applying  =  false;
        }
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Model Answers: a Batch Made, a Scene Sent
// -----------------------------------------------------------------------------

    // FUNCTION | A Batch Was Made: { Seq, Placed, Poses, FailedPlops, FailedPaints, Said, Level }
    // ------------------------------------------------------------
    // A new plop takes its proxy's persistent id for its Uid at once (its strokes
    // are seeded by it, so the rebuild now is the one that lasts) and the proxy's
    // pose, standing on what the pointer landed on. What failed comes back out of
    // the engine's lists. Everything else is only rounding, adopted quietly.
    function Na__NprEdit__Edited(reply) {
        const S      =  Na__NprEdit__State;
        const state  =  AppState.PainterlyNPR__AppCore__State;
        if (!S.ready) return;
        let rebuild   =  false;
        let reselect  =  null;
        const selected  =  SceneSelection.PainterlyNPR__SceneEdit__Selected();
        for (const [uid, pose] of Object.entries(reply.Placed || {})) {
            const plop  =  state.Assets.find((candidate) => candidate.Uid === uid);
            if (!plop) continue;
            state.Materials  =  state.Materials.map((a) => (a.Object.split('.')[0] === uid ? Object.assign({}, a, { Object: `${pose.Uid}.${a.Object.split('.')[1]}` }) : a));
            plop.Uid  =  pose.Uid;
            Na__NprEdit__Adopt(plop, pose);
            rebuild   =  true;
            if (selected && selected.Kind === 'Plop' && selected.Uid === uid) reselect = pose.Uid;
        }
        for (const [uid, pose] of Object.entries(reply.Poses || {})) {
            const plop  =  state.Assets.find((candidate) => candidate.Uid === uid || candidate.Uid === pose.Uid);
            if (!plop) continue;
            if (!Na__NprEdit__SamePose(plop, pose)) rebuild = true;
            Na__NprEdit__Adopt(plop, pose);
        }
        const failedPlops  =  new Set(reply.FailedPlops || []);
        const lostAdds     =  [...failedPlops].filter((uid) => !/^S\d+$/.test(uid));
        if (lostAdds.length) {
            state.Assets     =  state.Assets.filter((plop) => !lostAdds.includes(plop.Uid));
            state.Materials  =  state.Materials.filter((a) => !lostAdds.includes(a.Object.split('.')[0]));
            rebuild  =  true;
        }
        if (Array.isArray(reply.FailedPaints) && reply.FailedPaints.length) {
            state.Materials  =  state.Materials.filter((a) => !reply.FailedPaints.includes(a.Uid));
            rebuild  =  true;
        }
        if (rebuild) Na__NprEdit__Rebuild();
        Na__NprEdit__Remember(reply.Seq);
        if (reselect) SceneSelection.PainterlyNPR__SceneEdit__Select({ Kind: 'Plop', Uid: reselect }, true);
        if (lostAdds.length !== failedPlops.size) S.hooks.Action('refresh');     // <-- A proxy that has gone: the model's own list puts the drawing right
        if (Array.isArray(reply.Said) && reply.Said.length) S.hooks.Say(reply.Said.join(' '), reply.Level || 'info', Na__NprEdit__SAID_MS);
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | A Proxy's Pose on Its Plop, and Whether It Differs by More Than Rounding
    // ------------------------------------------------------------
    function Na__NprEdit__Adopt(plop, pose) {
        plop.Position     =  pose.PositionM.slice();
        plop.RotationDeg  =  pose.RotationDeg;
        plop.Scale        =  pose.Scale;
    }

    function Na__NprEdit__SamePose(plop, pose) {
        const turn  =  Math.abs(plop.RotationDeg - pose.RotationDeg) % 360;
        return [0, 1, 2].every((axis) => Math.abs(plop.Position[axis] - pose.PositionM[axis]) < 0.002)
            && Math.min(turn, 360 - turn) < 0.06
            && Math.abs(plop.Scale - pose.Scale) < 0.002;
    }
    // ------------------------------------------------------------


    // FUNCTION | A Scene From the Model: Its Plops and Materials Into the Engine's Lists; true When They Changed
    // ------------------------------------------------------------
    // plops: made by the engine's own MakePlacement, each at SketchUp's pose.
    // proxies: the scene's own, for what their parts were given. through: the last
    // batch the scene shows. While a later batch is on its way the page's own plops
    // stand, and the scene that batch brings about follows. A preview assignment
    // goes once its batch is shown: the GLB holds the paint now.
    function Na__NprEdit__TakeScene(plops, proxies, through, project) {
        const S      =  Na__NprEdit__State;
        const state  =  AppState.PainterlyNPR__AppCore__State;
        if (!S.ready) {
            state.Assets  =  plops;
            return true;
        }
        if (project !== S.project) {
            S.project  =  project;                                               // <-- Another model came to the front: nothing of the last one's stands
            S.pending  =  [];
            S.paints   =  new Map();
            S.pick     =  null;
        }
        const upTo     =  Number(through) || 0;
        S.pending      =  S.pending.filter((seq) => seq > upTo);
        const current  =  state.Materials || [];
        const previews =  current.filter((a) => a.Object[0] === '#' && (S.paints.get(a.Uid) || 0) > upTo);
        let changed    =  false;
        if (S.pending.length) {
            const kept  =  current.filter((a) => a.Object[0] !== '#').concat(previews);
            changed     =  kept.length !== current.length;
            state.Materials  =  kept;
        } else {
            let given  =  previews;
            for (const proxy of proxies) {
                for (const part of Array.isArray(proxy.Materials) ? proxy.Materials : []) {
                    given  =  MaterialLibrary.PainterlyNPR__MaterialAssignment__Give(given, { Object: `${proxy.Uid}.${part.Part}`, Face: part.Face == null ? null : part.Face }, part.Material).List;
                }
            }
            changed  =  !Na__NprEdit__SamePlops(state.Assets, plops) || !Na__NprEdit__SameGiven(current, given);
            if (changed) {
                state.Assets     =  plops;
                state.Materials  =  given;
            }
        }
        Na__NprEdit__Remember(0);
        return changed;
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | The Same Plops and the Same Materials, Whatever Their Order and Rounding
    // ------------------------------------------------------------
    function Na__NprEdit__SamePlops(now, next) {
        if (now.length !== next.length) return false;
        const byUid  =  new Map(now.map((plop) => [plop.Uid, plop]));
        return next.every((plop) => {
            const held  =  byUid.get(plop.Uid);
            return !!held && held.AssetId === plop.AssetId && held.Seed === plop.Seed && Na__NprEdit__SamePose(held, { PositionM: plop.Position, RotationDeg: plop.RotationDeg, Scale: plop.Scale });
        });
    }

    function Na__NprEdit__SameGiven(now, next) {
        const words  =  (list) => list.map((a) => `${a.Object}|${a.Target}|${a.Face}|${a.Material}`).sort().join('\n');
        return words(now) === words(next);
    }
    // ------------------------------------------------------------


    // FUNCTION | The Model's First Scene Is in the Engine: the Points That Waited for It
    // ------------------------------------------------------------
    function Na__NprEdit__SceneLoaded() {
        const S  =  Na__NprEdit__State;
        S.loaded  =  true;
        if (!S.ready || !S.pointsWaiting) return;
        const set  =  S.pointsWaiting;
        S.pointsWaiting  =  null;
        Na__NprEdit__ShowSet(set);
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Art Control Points: Kept in the Model, One Set a Scene
// -----------------------------------------------------------------------------

    // FUNCTION | A Set From the Model: Its Scene Selected, an Undo, the Window Opened
    // ------------------------------------------------------------
    // set: { Key, Name, Points, Sheet, Project }. Anything not yet kept goes to the
    // set it was made in first, then this one takes the sheet.
    function Na__NprEdit__Points(set) {
        const S  =  Na__NprEdit__State;
        if (!S.ready) return;
        if (!S.loaded) { S.pointsWaiting = set; return; }                        // <-- Their objects are not in the engine until the model is
        Na__NprEdit__SavePoints();
        Na__NprEdit__ShowSet(set);
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | Put a Set on the Sheet, Through the Engine's Own Settings
    // ------------------------------------------------------------
    function Na__NprEdit__ShowSet(set) {
        const S     =  Na__NprEdit__State;
        const list  =  Array.isArray(set.Points) ? set.Points : [];
        S.pointsSet      =  String(set.Key || 'working');
        S.pointsProject  =  String(set.Project || '');
        if (Na__NprEdit__PointsKey(list) !== Na__NprEdit__PointsKey(Na__NprEdit__PointsNow())) Na__NprEdit__SetPoints(list, set.Sheet);
        S.pointsSent  =  Na__NprEdit__PointsKey(Na__NprEdit__PointsNow());
    }

    function Na__NprEdit__SetPoints(list, sheet) {
        const now  =  SettingsJson.PainterlyNPR__Interface__SettingsObject();
        SettingsJson.PainterlyNPR__Interface__ApplySettingsJson(JSON.stringify(Object.assign({}, now, { ArtDirectionPoints: list, Sheet: sheet || now.Sheet })));
    }

    function Na__NprEdit__PointsNow() {
        return SettingsJson.PainterlyNPR__Interface__SettingsObject().ArtDirectionPoints || [];
    }

    // What counts as a change: an object-anchored point's place on the paper moves with the camera
    function Na__NprEdit__PointsKey(list) {
        return JSON.stringify(list.map((point) => (point.Anchor === 'Object' && point.World ? Object.assign({}, point, { PaperMm: null }) : point)));
    }
    // ------------------------------------------------------------


    // HELPER FUNCTION | Hear the Page Being Used; Once It Is Still, Keep the Points If They Moved
    // ------------------------------------------------------------
    function Na__NprEdit__WatchPoints() {
        const soon  =  () => {
            const S  =  Na__NprEdit__State;
            clearTimeout(S.pointsTimer);
            S.pointsTimer  =  setTimeout(Na__NprEdit__SavePoints, Na__NprEdit__POINTS_MS);
        };
        for (const type of ['pointerup', 'keyup', 'change', 'input', 'click']) window.addEventListener(type, soon, { passive: true });
    }

    function Na__NprEdit__SavePoints() {
        const S  =  Na__NprEdit__State;
        clearTimeout(S.pointsTimer);
        S.pointsTimer  =  null;
        if (!S.ready || !S.loaded || S.exportBack) return;
        const settings  =  SettingsJson.PainterlyNPR__Interface__SettingsObject();
        const list      =  settings.ArtDirectionPoints || [];
        const key       =  Na__NprEdit__PointsKey(list);
        if (key === S.pointsSent) return;
        S.pointsSent  =  key;
        S.hooks.Action('points', { Project: S.pointsProject, Key: S.pointsSet, Points: list, Sheet: settings.Sheet });
    }
    // ------------------------------------------------------------


    // FUNCTION | NPR Export: a Scene's Points for Its Picture, the Sheet's Own Back After
    // ------------------------------------------------------------
    function Na__NprEdit__ExportPoints(set) {
        const S  =  Na__NprEdit__State;
        if (!S.ready) return;
        Na__NprEdit__SavePoints();
        if (!S.exportBack) S.exportBack = { Points: Na__NprEdit__PointsNow() };
        Na__NprEdit__SetPoints(Array.isArray(set.Points) ? set.Points : [], set.Sheet);
    }

    function Na__NprEdit__ExportPointsDone() {
        const S     =  Na__NprEdit__State;
        const back  =  S.exportBack;
        S.exportBack  =  null;
        if (!back) return;
        Na__NprEdit__SetPoints(back.Points, null);
        S.pointsSent  =  Na__NprEdit__PointsKey(Na__NprEdit__PointsNow());
    }
    // ------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Module Exports
// -----------------------------------------------------------------------------

    export {
        Na__NprEdit__Boot,
        Na__NprEdit__Edited,
        Na__NprEdit__ExportPoints,
        Na__NprEdit__ExportPointsDone,
        Na__NprEdit__Points,
        Na__NprEdit__Rebuild,
        Na__NprEdit__SceneLoaded,
        Na__NprEdit__TakeScene,
    };

// endregion -------------------------------------------------------------------
