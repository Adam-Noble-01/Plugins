/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - EDITOR CORE
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Editor__.js
   NAMESPACE  : window.Na__DrawProfile__Editor
   PURPOSE    : The editor itself: state, the pointer and keyboard pipeline,
                tools, commits and undo, snapping, the measurements box, saved
                settings and the autosaved draft. The tab module builds the
                page around it; the tools do the drawing.

   KEYS (TV Na__Hotkeys__DrawingTabs__ where it has the command)
     V / Space select     L line       R rectangle   A arc        C circle
     M move (Ctrl copy)   Q rotate     Shift+M mirror             S scale
     F offset             T trim       Shift+T extend             K corner
     Shift+F fillet       Shift+C chamfer            U split      D dimension
     Shift+D measure      O set datum  G construction on / off
     Z zoom to fit        Enter        vertex mode (in Select), finish
     Esc cancel           Arrows       lock X / Y while placing, nudge else
     F3 snap   F6 grid   F7 grid snap   F8 or Ctrl+L ortho   F9 drawing axes
     Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z undo, redo   Ctrl+A select all
   ============================================================================= */

(function () {
    'use strict';

    var C   = window.Na__DrawProfile__Config;
    var G   = window.Na__DrawProfile__Geom;
    var D   = window.Na__DrawProfile__Doc;
    var L   = window.Na__DrawProfile__Loop;
    var S   = window.Na__DrawProfile__Snap;
    var V   = window.Na__DrawProfile__View;
    var Vcb = window.Na__DrawProfile__Vcb;

    // -------------------------------------------------------------------------
    // REGION | Settings
    // -------------------------------------------------------------------------

    // What survives a reload of the dialog. Everything else is the config.
    var PERSISTED = [ 'Grid', 'Snap.On', 'Snap.Modes', 'Ortho', 'DrawingAxes', 'ShowSegments', 'ShowLoopInfo', 'Curves.ToleranceMm', 'Defaults' ];

    function DeepCopy(value) { return JSON.parse(JSON.stringify(value)); }

    function GetPath(obj, path) {
        return path.split('.').reduce(function (o, k) { return o === undefined || o === null ? undefined : o[k]; }, obj);
    }

    function SetPath(obj, path, value) {
        var keys = path.split('.');
        var target = obj;
        for (var i = 0; i < keys.length - 1; i++) { target = target[keys[i]]; if (!target) return; }
        target[keys[keys.length - 1]] = value;
    }

    function LoadSettings() {
        var settings = DeepCopy(C);
        try {
            var saved = JSON.parse(window.localStorage.getItem(C.STORAGE_KEY_SETTINGS) || 'null');
            if (saved && typeof saved === 'object') {
                PERSISTED.forEach(function (path) {
                    var value = GetPath(saved, path);
                    if (value === undefined) return;
                    var current = GetPath(settings, path);
                    if (current && typeof current === 'object' && value && typeof value === 'object') {
                        Object.keys(value).forEach(function (k) { if (k in current) current[k] = value[k]; });
                    } else if (typeof current === typeof value) {
                        SetPath(settings, path, value);
                    }
                });
            }
        } catch (err) { /* private mode or bad JSON: the config stands */ }
        return settings;
    }

    function SaveSettings(settings) {
        try {
            var out = {};
            PERSISTED.forEach(function (path) {
                var keys = path.split('.');
                var target = out;
                for (var i = 0; i < keys.length - 1; i++) { target[keys[i]] = target[keys[i]] || {}; target = target[keys[i]]; }
                target[keys[keys.length - 1]] = DeepCopy(GetPath(settings, path));
            });
            window.localStorage.setItem(C.STORAGE_KEY_SETTINGS, JSON.stringify(out));
        } catch (err) { /* ignore */ }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Construction
    // -------------------------------------------------------------------------

    // elements: { stage, canvas, vcbRoot, vcbLabel, vcbInput, vcbHint }
    // hooks:    { onDocChanged, onToolChanged, onSelectionChanged, onSettingsChanged,
    //             onPrompt(text), onCursor(world), onSaveShortcut }
    function Editor(elements, hooks) {
        var self = this;
        this.el = elements;
        this.hooks = hooks || {};
        this.settings = LoadSettings();
        this.doc = D.Create();
        this.history = new D.History(this.settings.Undo.Max);
        this.selection = new Set();
        this.vsel = new Set();
        this.vertexMode = false;
        this.hoverId = null;
        this.hoverKey = null;
        this.snapShown = null;
        this.lastSnap = null;
        this.track = S.CreateState();
        this.axisLock = null;
        this.shift = false; this.ctrl = false; this.alt = false;
        this.cursorWorld = null;
        this.lastEvent = null;
        this.analysis = L.Analyse(this.doc, this.settings);
        this.showIssues = true;
        this.focusIssue = -1;
        this.box = null;
        this.gripsToDraw = [];
        this.dimPreview = null;
        this.hiddenIds = null;
        this.transient = null;
        this.snapBase = null;
        this.active = false;
        this.dirty = false;
        this.base = null;
        this.bind = null;
        this.toolMemory = {};
        this.redrawPending = false;
        this.acquireTimer = null;
        this.draftTimer = null;
        this.pan = null;
        this.rightPress = null;
        this.leftDown = false;

        this.view = V.Create(elements.canvas, this.settings);
        this.vcb = new Vcb.Controller(
            { root : elements.vcbRoot, label : elements.vcbLabel, input : elements.vcbInput, hint : elements.vcbHint },
            { commit : function (text) { return self.VcbCommit(text); }, preview : function (text) { return self.VcbPreview(text); } }
        );
        this.vcb.BindInput();

        this.tool = null;
        this.SetTool('select');
        this.BindEvents();
    }

    Editor.prototype.Emit = function (name, arg) {
        if (typeof this.hooks[name] === 'function') {
            try { this.hooks[name](arg); } catch (err) { console.error('[DrawProfile] hook ' + name + ' failed', err); }
        }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Rendering
    // -------------------------------------------------------------------------

    Editor.prototype.Redraw = function () {
        var self = this;
        if (this.redrawPending) return;
        this.redrawPending = true;
        window.requestAnimationFrame(function () {
            self.redrawPending = false;
            V.Resize(self.view);
            if (!self.view.hasFit && self.view.w > 40 && self.view.h > 40) {
                self.view.hasFit = true;
                self.ZoomExtents(true);
                return;
            }
            V.Render(self.view, self);
        });
    };

    Editor.prototype.ZoomExtents = function (quiet) {
        var box = D.Bbox(this.doc);
        box = G.UnionBox(box, { minX : 0, minY : 0, maxX : 0, maxY : 0 });
        if (box.maxX - box.minX < 20 && box.maxY - box.minY < 20) {
            box = { minX : box.minX - 20, minY : box.minY - 20, maxX : box.maxX + 20, maxY : box.maxY + 20 };
        }
        V.Fit(this.view, box, this.settings);
        if (!quiet) this.Hint('Zoomed to fit the drawing.');
        this.Redraw();
    };

    Editor.prototype.ZoomBy = function (factor) {
        V.ZoomAt(this.view, this.view.w / 2, this.view.h / 2, factor, this.settings);
        this.Redraw();
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Changes, History, Transients
    // -------------------------------------------------------------------------

    // One undo step. fn mutates the document; returning false or { ok:false }
    // rolls it back. Healing runs after every change.
    Editor.prototype.Commit = function (label, fn) {
        var before = D.Serialize(this.doc);
        var result;
        try { result = fn(this.doc); } catch (err) {
            console.error('[DrawProfile] ' + label + ' failed', err);
            result = { ok : false, message : label + ' failed: ' + err.message };
        }
        if (result === false || (result && result.ok === false)) {
            this.doc = D.Deserialize(before);
            this.Changed();
            return result || { ok : false };
        }
        D.Heal(this.doc, this.settings.Tol.SameMm);
        if (D.Serialize(this.doc) !== before) {
            this.history.Push(before, label);
            this.dirty = true;
        }
        this.Changed();
        return result || { ok : true };
    };

    // A change previewed live (a drag): every update starts again from the
    // state before it, and only the end lands as one undo step.
    // options.snapBase: while it runs, snapping reads the drawing as it was
    // before it began, so nothing being dragged snaps to its own preview
    // (TV: the shape being moved is left out of the snap). Drags and the
    // Move / Rotate / Mirror / Scale previews use it; the Line tool does not,
    // as the segments it has placed are real snap targets.
    Editor.prototype.BeginTransient = function (options) {
        this.transient = D.Serialize(this.doc);
        this.snapBase = options && options.snapBase ? D.Deserialize(this.transient) : null;
    };

    Editor.prototype.UpdateTransient = function (fn) {
        if (!this.transient) return;
        this.doc = D.Deserialize(this.transient);
        fn(this.doc);
        this.analysis = L.Analyse(this.doc, this.settings);
        this.Redraw();
    };

    Editor.prototype.EndTransient = function (commit, label) {
        if (!this.transient) return;
        var before = this.transient;
        this.transient = null;
        this.snapBase = null;
        if (!commit) { this.doc = D.Deserialize(before); this.Changed(); return; }
        D.Heal(this.doc, this.settings.Tol.SameMm);
        if (D.Serialize(this.doc) !== before) { this.history.Push(before, label); this.dirty = true; }
        this.Changed();
    };

    Editor.prototype.Changed = function () {
        var self = this;
        var ids = new Set(this.doc.ents.map(function (e) { return e.id; }).concat(this.doc.dims.map(function (d) { return d.id; })));
        this.selection.forEach(function (id) { if (!ids.has(id)) self.selection.delete(id); });
        if (this.vsel.size) {
            var index = D.VertexIndex(this.doc);
            this.vsel.forEach(function (k) { if (!index.has(k)) self.vsel.delete(k); });
        }
        this.analysis = L.Analyse(this.doc, this.settings);
        if (this.focusIssue >= this.analysis.issues.length) this.focusIssue = -1;
        this.ScheduleDraftSave();
        this.RefreshGrips();
        this.Emit('onDocChanged');
        this.Emit('onSelectionChanged');
        this.UpdatePrompt();
        this.Redraw();
    };

    Editor.prototype.Undo = function () {
        if (this.tool && typeof this.tool.onUndo === 'function' && this.tool.onUndo(this)) return;
        if (this.transient) this.EndTransient(false);
        var step = this.history.Undo(D.Serialize(this.doc));
        if (!step) { this.Hint('Nothing to undo.'); return; }
        this.doc = D.Deserialize(step.snapshot);
        this.ResetTool();
        this.Changed();
        this.Hint('Undone: ' + (step.label || 'last change') + '.');
    };

    Editor.prototype.Redo = function () {
        if (this.tool && typeof this.tool.onRedo === 'function' && this.tool.onRedo(this)) return;
        var step = this.history.Redo(D.Serialize(this.doc));
        if (!step) { this.Hint('Nothing to redo.'); return; }
        this.doc = D.Deserialize(step.snapshot);
        this.ResetTool();
        this.Changed();
        this.Hint('Redone: ' + (step.label || 'change') + '.');
    };

    // A new drawing: history starts again, the view fits it.
    Editor.prototype.LoadDocument = function (doc, meta) {
        var info = meta || {};
        this.transient = null;
        this.snapBase = null;
        this.doc = doc || D.Create();
        D.Heal(this.doc, this.settings.Tol.SameMm);
        this.history.Clear();
        this.selection.clear();
        this.vsel.clear();
        this.vertexMode = false;
        this.focusIssue = -1;
        this.base = info.base || null;
        this.dirty = !!info.dirty;
        S.ClearAcquired(this.track);
        this.SetTool('select');
        this.Changed();
        // Fitted on the next frame that has a real size: the tab may still be
        // hidden (no size at all) when a drawing arrives from SketchUp.
        this.view.hasFit = false;
        this.Redraw();
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Draft Autosave
    // -------------------------------------------------------------------------

    Editor.prototype.ScheduleDraftSave = function () {
        var self = this;
        if (this.draftTimer) window.clearTimeout(this.draftTimer);
        this.draftTimer = window.setTimeout(function () { self.SaveDraft(); }, 500);
    };

    Editor.prototype.SaveDraft = function () {
        try {
            window.localStorage.setItem(C.STORAGE_KEY_DRAFT, JSON.stringify({
                doc : JSON.parse(D.Serialize(this.doc)), base : this.base, bind : this.bind, dirty : this.dirty,
                paintDefault : this.paintDefault || null, savedAt : Date.now()
            }));
        } catch (err) { /* storage full or blocked: the draft is a convenience only */ }
    };

    Editor.prototype.ReadDraft = function () {
        try {
            var raw = JSON.parse(window.localStorage.getItem(C.STORAGE_KEY_DRAFT) || 'null');
            if (!raw || !raw.doc) return null;
            return raw;
        } catch (err) { return null; }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tools
    // -------------------------------------------------------------------------

    Editor.prototype.SetTool = function (id) {
        var registry = window.Na__DrawProfile__Tools;
        var next = registry ? registry.Get(id) : null;
        if (!next) return;
        if (this.tool && typeof this.tool.deactivate === 'function') this.tool.deactivate(this);
        if (this.transient) this.EndTransient(false);
        this.vcb.Clear();
        this.vcb.Hint('');
        this.axisLock = null;
        this.box = null;
        this.dimPreview = null;
        this.hiddenIds = null;
        this.snapShown = null;
        S.ClearAcquired(this.track);
        this.tool = next;
        if (typeof next.activate === 'function') next.activate(this);
        this.SetCursor(next.cursor || 'crosshair');
        this.RefreshGrips();
        this.UpdatePrompt();
        this.Emit('onToolChanged', next.id);
        this.Redraw();
    };

    // The active tool back to its first step (after an undo, say).
    Editor.prototype.ResetTool = function () {
        if (this.tool && typeof this.tool.reset === 'function') this.tool.reset(this);
        this.dimPreview = null;
        this.hiddenIds = null;
        this.box = null;
        this.axisLock = null;
    };

    Editor.prototype.Memory = function (toolId) {
        if (!this.toolMemory[toolId]) this.toolMemory[toolId] = {};
        return this.toolMemory[toolId];
    };

    Editor.prototype.SetCursor = function (cursor) {
        if (this.el.canvas) this.el.canvas.style.cursor = cursor || 'crosshair';
    };

    Editor.prototype.UpdatePrompt = function () {
        var tool = this.tool;
        if (!tool) return;
        this.Emit('onPrompt', typeof tool.prompt === 'function' ? tool.prompt(this) : '');
        this.vcb.SetLabel(typeof tool.vcbLabel === 'function' ? tool.vcbLabel(this) : '');
        this.vcb.SetReading(typeof tool.vcbReading === 'function' ? tool.vcbReading(this) : '');
    };

    Editor.prototype.Hint = function (message, isError) {
        this.vcb.Hint(message, isError);
    };

    // Edge Paint: the drawing shows its edge colours instead of the blue
    // linework while the Edge Paint tab is open (paintView), the Paint tool
    // is in hand, or ShowPaint keeps them on everywhere.
    Editor.prototype.PaintView = function () {
        return !!(this.paintView || (this.tool && this.tool.id === 'paint') || this.settings.ShowPaint);
    };

    // The profile's usual colour { id, hex }: what an unpainted edge takes
    // when it is saved (the colour most of the opened profile's edges carry).
    Editor.prototype.PaintDefault = function () {
        return this.paintDefault || { id : null, hex : '#666666' };
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Snapping + Picking
    // -------------------------------------------------------------------------

    // Find the snap for a world point. options: from, exclude, excludeKeys,
    // extra, noTrack.
    Editor.prototype.SnapAt = function (world, options) {
        var o = options || {};
        var result = S.Find({
            doc : this.snapBase || this.doc, scale : this.view.scale, cursor : world, from : o.from || null, settings : this.settings,
            exclude : o.exclude, excludeKeys : o.excludeKeys, extra : o.extra, track : this.track, noTrack : o.noTrack
        });
        this.lastSnap = result;
        this.ScheduleAcquire(result);
        return result;
    };

    // Resting on a point acquires it for tracking (TV: 400 ms).
    Editor.prototype.ScheduleAcquire = function (snap) {
        var self = this;
        if (this.acquireTimer) window.clearTimeout(this.acquireTimer);
        this.acquireTimer = null;
        if (!snap || [ 'end', 'mid', 'int', 'cen', 'quad' ].indexOf(snap.kind) < 0) return;
        this.acquireTimer = window.setTimeout(function () {
            if (self.lastSnap === snap && S.Acquire(self.track, snap, self.settings.Snap.TrackMax)) self.Redraw();
        }, this.settings.Snap.TrackRestMs);
    };

    // A snapped and constrained point: { p, lock, snap }. With an anchor the
    // arrow-key lock and Ortho XOR Shift apply; the snap glyph is shown only
    // where the point really is.
    Editor.prototype.Pick = function (ev, anchor, options) {
        var o = options || {};
        var snap = this.SnapAt(ev.world, { from : anchor || o.from || null, exclude : o.exclude, excludeKeys : o.excludeKeys, extra : o.extra, noTrack : o.noTrack });
        var holdNearest = !!this.settings.Ortho !== !!ev.shift;
        var c = anchor ? S.Constrain(anchor, snap, ev.world, this.axisLock, holdNearest) : { p : G.Copy(snap.p), lock : null };
        this.snapShown = (!c.lock || G.Same(c.p, snap.p, 1e-9)) ? snap : null;
        return { p : c.p, lock : c.lock, snap : snap };
    };

    Editor.prototype.TolWorld = function (px) {
        return px / this.view.scale;
    };

    // The entity or dimension nearest a world point within the hit radius;
    // later-drawn wins a tie (TV). options.types limits entity types,
    // options.noDims skips dimensions, options.exclude skips ids.
    Editor.prototype.HitEntity = function (world, options) {
        var o = options || {};
        var tol = this.TolWorld(o.px || this.settings.Tol.HitPx);
        var best = null;
        var exclude = o.exclude || null;
        for (var i = this.doc.ents.length - 1; i >= 0; i--) {
            var e = this.doc.ents[i];
            if (exclude && exclude.has(e.id)) continue;
            if (o.types && o.types.indexOf(e.type) < 0) continue;
            if (o.noConstruction && e.constr) continue;
            var near = G.Nearest(e, world);
            if (near.d <= tol && (!best || near.d < best.d - 1e-9)) best = { id : e.id, kind : 'ent', d : near.d, t : near.t, p : near.p };
        }
        if (!o.noDims) {
            var self = this;
            this.doc.dims.forEach(function (d) {
                var sk = V.DimensionSkeleton(d.a, d.b, d.off || 0, d.orient, 0, 0);
                if (!sk) return;
                var near = G.Nearest({ type : 'line', a : sk.DS, b : sk.DE }, world);
                var textD = G.Dist(sk.MID, world) - self.TolWorld(14);
                var dist = Math.min(near.d, Math.max(0, textD));
                if (dist <= tol && (!best || dist < best.d)) best = { id : d.id, kind : 'dim', d : dist };
            });
        }
        return best;
    };

    // The vertex location nearest a world point within the grip radius.
    Editor.prototype.HitVertex = function (world, options) {
        var o = options || {};
        var tol = this.TolWorld(o.px || this.settings.Tol.GripPx + 2);
        var best = null;
        D.VertexIndex(this.doc).forEach(function (v) {
            var d = G.Dist(v.p, world);
            if (d <= tol && (!best || d < best.d)) best = { key : v.key, p : v.p, d : d, degree : v.degree, v : v };
        });
        return best;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Selection
    // -------------------------------------------------------------------------

    Editor.prototype.SetSelection = function (ids) {
        this.selection = new Set(ids || []);
        this.RefreshGrips();
        this.Emit('onSelectionChanged');
        this.UpdatePrompt();
        this.Redraw();
    };

    Editor.prototype.SelectAll = function () {
        if (this.vertexMode) {
            var keys = new Set();
            D.VertexIndex(this.doc).forEach(function (v) { keys.add(v.key); });
            this.vsel = keys;
            this.RefreshGrips();
            this.Redraw();
            this.Emit('onSelectionChanged');
            return;
        }
        this.SetSelection(this.doc.ents.map(function (e) { return e.id; }).concat(this.doc.dims.map(function (d) { return d.id; })));
    };

    Editor.prototype.ClearSelection = function () {
        this.selection.clear();
        this.vsel.clear();
        this.RefreshGrips();
        this.Emit('onSelectionChanged');
        this.UpdatePrompt();
        this.Redraw();
    };

    Editor.prototype.SetVertexMode = function (on) {
        this.vertexMode = !!on;
        if (!this.vertexMode) this.vsel.clear();
        if (this.vertexMode && this.selection.size) {
            // Entering vertex mode with edges picked picks their vertices.
            this.vsel = D.KeysOfEntities(this.doc, this.selection);
        }
        this.RefreshGrips();
        this.Emit('onSelectionChanged');
        this.UpdatePrompt();
        this.Redraw();
    };

    // The grips the renderer draws: every vertex in vertex mode, else the
    // ends (and arc bulge handles) of what is selected.
    Editor.prototype.RefreshGrips = function () {
        var grips = [];
        var self = this;
        if (this.vertexMode) {
            D.VertexIndex(this.doc).forEach(function (v) {
                grips.push({ key : v.key, p : v.p, picked : self.vsel.has(v.key), hot : self.hoverKey === v.key, kind : 'vertex' });
            });
        } else if (this.tool && this.tool.id === 'select' && this.selection.size && this.selection.size <= 400) {
            var seen = new Set();
            this.doc.ents.forEach(function (e) {
                if (!self.selection.has(e.id)) return;
                var pts = e.type === 'circle' ? [ e.c ] : [ e.a, e.b ];
                pts.forEach(function (p) {
                    var key = D.KeyOf(p);
                    if (seen.has(key)) return;
                    seen.add(key);
                    grips.push({ key : key, p : p, picked : false, hot : self.hoverKey === key, kind : 'vertex' });
                });
                if (e.type === 'arc') grips.push({ key : 'bulge:' + e.id, id : e.id, p : G.MidPoint(e), hot : self.hoverKey === 'bulge:' + e.id, kind : 'bulge' });
                if (e.type === 'circle') grips.push({ key : 'radius:' + e.id, id : e.id, p : { x : e.c.x + e.r, y : e.c.y }, hot : self.hoverKey === 'radius:' + e.id, kind : 'bulge' });
            });
        }
        this.gripsToDraw = grips;
    };

    // The vertex locations a move of the current selection carries.
    // Read from the drawing before a running drag, so the keys are where the
    // selection started (the same as the fresh copy each preview update is
    // applied to).
    Editor.prototype.SelectionKeys = function () {
        if (this.vertexMode) return new Set(this.vsel);
        return D.KeysOfEntities(this.snapBase || this.doc, this.selection);
    };

    // What a drag moves or stretches, read from the drawing before it: the
    // entities given, and every entity standing on a moving location. Passed
    // as a snap exclusion, so nothing snaps to where it was.
    Editor.prototype.MovingIds = function (keys, ids) {
        var doc = this.snapBase || this.doc;
        var moving = new Set(keys || []);
        if (ids && ids.size) D.KeysOfEntities(doc, ids).forEach(function (k) { moving.add(k); });
        var out = new Set(ids ? Array.from(ids) : []);
        D.EntitiesAt(doc, moving).forEach(function (e) { out.add(e.id); });
        return out;
    };

    Editor.prototype.HasMovableSelection = function () {
        return this.vertexMode ? this.vsel.size > 0 : this.selection.size > 0;
    };

    // Moves the selection (vertices, edges and selected dimensions) by delta,
    // in the document given (the live one by default).
    Editor.prototype.MoveSelectionIn = function (doc, delta) {
        var keys = this.SelectionKeys();
        D.Translate(doc, keys, delta);
        var self = this;
        if (!this.vertexMode) {
            doc.dims.forEach(function (d) {
                if (!self.selection.has(d.id)) return;
                if (!d.ka || !keys.has(d.ka)) d.a = { x : d.a.x + delta.x, y : d.a.y + delta.y };
                if (!d.kb || !keys.has(d.kb)) d.b = { x : d.b.x + delta.x, y : d.b.y + delta.y };
            });
        }
    };

    Editor.prototype.MoveSelection = function (delta, label) {
        var self = this;
        if (!this.HasMovableSelection()) { this.Hint('Select something to move first.', true); return { ok : false }; }
        // The picked vertices are re-keyed BEFORE the commit: the commit drops
        // picks whose location no longer exists, which after a move is all.
        var moved = this.vertexMode ? ShiftKeys(this.vsel, delta) : null;
        var result = this.Commit(label || 'Move', function (doc) { self.MoveSelectionIn(doc, delta); return { ok : true }; });
        if (moved) {
            this.vsel = moved;
            this.RefreshGrips();
            this.Emit('onSelectionChanged');
            this.Redraw();
        }
        return result;
    };

    // Location keys moved by delta.
    function ShiftKeys(keys, delta) {
        var moved = new Set();
        keys.forEach(function (k) {
            var parts = k.split(',');
            moved.add(D.KeyOf({ x : parseFloat(parts[0]) + delta.x, y : parseFloat(parts[1]) + delta.y }));
        });
        return moved;
    }

    Editor.prototype.DeleteSelection = function () {
        var self = this;
        if (this.vertexMode) {
            if (!this.vsel.size) { this.Hint('Pick vertices to delete first.', true); return; }
            var report;
            this.Commit('Delete vertices', function (doc) { report = D.DeleteLocations(doc, self.vsel); return { ok : true }; });
            this.vsel.clear();
            var parts = [];
            if (report.merged) parts.push(report.merged + ' vertex(es) removed, edges joined');
            if (report.removed) parts.push(report.removed + ' end edge(s) removed');
            if (report.skipped) parts.push(report.skipped + ' left: more than two edges meet there');
            this.Hint(parts.join('; ') + '.');
            this.Changed();
            return;
        }
        if (!this.selection.size) { this.Hint('Select something to delete first.', true); return; }
        var count = this.selection.size;
        this.Commit('Delete', function (doc) {
            D.Remove(doc, self.selection);
            doc.dims = doc.dims.filter(function (d) { return !self.selection.has(d.id); });
            return { ok : true };
        });
        this.selection.clear();
        this.Hint(count + ' item(s) deleted.');
        this.Changed();
    };

    Editor.prototype.ToggleConstruction = function () {
        var self = this;
        var ids = Array.from(this.selection).filter(function (id) { return D.Get(self.doc, id); });
        if (!ids.length) { this.Hint('Select edges to make construction (or back) first.', true); return; }
        var makeConstr = ids.some(function (id) { return !D.Get(self.doc, id).constr; });
        this.Commit(makeConstr ? 'Make construction' : 'Make profile edges', function (doc) { D.SetConstruction(doc, ids, makeConstr); return { ok : true }; });
        this.Hint(ids.length + ' edge(s) ' + (makeConstr ? 'made construction: drawn and snapped to, never saved.' : 'back in the profile.'));
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Settings Toggles
    // -------------------------------------------------------------------------

    var TOGGLE_LABELS = {
        'Ortho' : 'Ortho', 'Grid.Show' : 'Grid', 'Grid.Snap' : 'Grid snap', 'Snap.On' : 'Object snap',
        'DrawingAxes' : 'Drawing axes', 'ShowSegments' : 'Segment marks', 'ShowLoopInfo' : 'Vertex numbers', 'ShowPaint' : 'Edge colours everywhere'
    };

    Editor.prototype.ToggleSetting = function (path, value) {
        var next = value === undefined ? !GetPath(this.settings, path) : !!value;
        SetPath(this.settings, path, next);
        SaveSettings(this.settings);
        this.Hint('<' + (TOGGLE_LABELS[path] || path) + ' ' + (next ? 'on' : 'off') + '>');
        this.Emit('onSettingsChanged');
        this.RefreshPointer();
        this.Redraw();
    };

    Editor.prototype.SetSetting = function (path, value) {
        SetPath(this.settings, path, value);
        SaveSettings(this.settings);
        this.Emit('onSettingsChanged');
        this.Changed();
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Measurements Box
    // -------------------------------------------------------------------------

    Editor.prototype.VcbCommit = function (text) {
        var parsed = Vcb.Read(text, { pair : true });
        if (this.tool && typeof this.tool.onVcb === 'function') {
            var result = this.tool.onVcb(this, text, parsed);
            if (result) { this.UpdatePrompt(); return result; }
        }
        return { ok : false, message : 'Nothing is waiting for a value. Pick a tool first.' };
    };

    Editor.prototype.VcbPreview = function (text) {
        var parsed = Vcb.Read(text, { pair : true });
        if (this.tool && typeof this.tool.vcbPreview === 'function') {
            var said = this.tool.vcbPreview(this, text, parsed);
            if (said) return said;
        }
        return DescribeReading(parsed, this.settings.Precision);
    };

    function DescribeReading(parsed, precision) {
        if (!parsed.ok) return parsed.reason === 'unit' ? 'Units: mm, cm or m.' : '';
        var f = function (v) { return G.FormatMm(v, precision); };
        switch (parsed.type) {
            case 'length'   : return '→ ' + f(parsed.valueMm) + ' mm';
            case 'pair'     : return '→ across ' + f(parsed.first) + ', up ' + f(parsed.second) + ' mm';
            case 'relative' : return '→ across ' + f(parsed.dx) + ', up ' + f(parsed.dy) + ' mm from the last point';
            case 'absolute' : return '→ the point Y ' + f(parsed.x) + ', Z ' + f(parsed.y);
            case 'polar'    : return '→ ' + f(parsed.length) + ' mm at ' + f(parsed.deg) + '°';
            case 'segments' : return '→ ' + parsed.count + ' segments';
            case 'radius'   : return '→ radius ' + f(parsed.valueMm) + ' mm';
            case 'diameter' : return '→ diameter ' + f(parsed.valueMm) + ' mm';
            case 'bulge'    : return '→ bulge ' + f(parsed.valueMm) + ' mm';
            case 'angle'    : return '→ ' + f(parsed.deg) + '°';
            case 'array'    : return '→ ' + (parsed.mode === 'divide' ? 'divide into ' : '') + parsed.count + (parsed.mode === 'divide' ? '' : ' copies');
            default         : return '';
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Pointer
    // -------------------------------------------------------------------------

    Editor.prototype.MakeEvent = function (e) {
        var rect = this.el.canvas.getBoundingClientRect();
        var sx = e.clientX - rect.left, sy = e.clientY - rect.top;
        return {
            sx : sx, sy : sy, world : V.S2W(this.view, sx, sy),
            button : e.button, shift : e.shiftKey, ctrl : e.ctrlKey, alt : e.altKey, detail : e.detail
        };
    };

    // Re-runs the tool's move with the last cursor - after a key changes what
    // the cursor means (Shift, an axis lock, a toggle).
    Editor.prototype.RefreshPointer = function () {
        if (!this.lastEvent || !this.tool || typeof this.tool.onMove !== 'function') return;
        var ev = Object.assign({}, this.lastEvent, { shift : this.shift, ctrl : this.ctrl, alt : this.alt });
        this.tool.onMove(this, ev);
        this.UpdatePrompt();
        this.Redraw();
    };

    Editor.prototype.BindEvents = function () {
        var self = this;
        var canvas = this.el.canvas;

        canvas.addEventListener('pointerdown', function (e) {
            if (self.el.stage && typeof self.el.stage.focus === 'function') self.el.stage.focus({ preventScroll : true });
            try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
            var ev = self.MakeEvent(e);
            self.lastEvent = ev;
            self.shift = e.shiftKey; self.ctrl = e.ctrlKey; self.alt = e.altKey;
            if (e.button === 1) { e.preventDefault(); self.pan = { sx : ev.sx, sy : ev.sy }; self.SetCursor('grabbing'); return; }
            if (e.button === 2) { self.rightPress = { sx : ev.sx, sy : ev.sy, moved : false }; return; }
            if (e.button !== 0) return;
            self.leftDown = true;
            if (self.tool && typeof self.tool.onDown === 'function') self.tool.onDown(self, ev);
            self.UpdatePrompt();
            self.Redraw();
        });

        canvas.addEventListener('pointermove', function (e) {
            var ev = self.MakeEvent(e);
            self.cursorWorld = ev.world;
            self.Emit('onCursor', ev.world);
            if (self.pan) {
                V.Pan(self.view, ev.sx - self.pan.sx, ev.sy - self.pan.sy);
                self.pan.sx = ev.sx; self.pan.sy = ev.sy;
                self.Redraw();
                return;
            }
            if (self.rightPress) {
                if (!self.rightPress.moved && Math.hypot(ev.sx - self.rightPress.sx, ev.sy - self.rightPress.sy) > 3) {
                    self.rightPress.moved = true;
                    self.pan = { sx : ev.sx, sy : ev.sy };
                    self.SetCursor('grabbing');
                }
                return;
            }
            self.lastEvent = ev;
            if (self.tool && typeof self.tool.onMove === 'function') self.tool.onMove(self, ev);
            self.UpdatePrompt();
            self.Redraw();
        });

        canvas.addEventListener('pointerup', function (e) {
            try { canvas.releasePointerCapture(e.pointerId); } catch (err) { /* ignore */ }
            var ev = self.MakeEvent(e);
            if (self.pan && (e.button === 1 || (e.button === 2 && self.rightPress))) {
                self.pan = null;
                self.rightPress = null;
                self.SetCursor(self.tool && self.tool.cursor ? self.tool.cursor : 'crosshair');
                return;
            }
            if (e.button === 2) {
                var wasClick = self.rightPress && !self.rightPress.moved;
                self.rightPress = null;
                if (wasClick && self.tool && typeof self.tool.onRightClick === 'function') self.tool.onRightClick(self, ev);
                self.UpdatePrompt();
                self.Redraw();
                return;
            }
            if (e.button !== 0) return;
            self.leftDown = false;
            if (self.tool && typeof self.tool.onUp === 'function') self.tool.onUp(self, ev);
            self.UpdatePrompt();
            self.Redraw();
        });

        canvas.addEventListener('dblclick', function (e) {
            var ev = self.MakeEvent(e);
            if (self.tool && typeof self.tool.onDblClick === 'function') self.tool.onDblClick(self, ev);
            self.UpdatePrompt();
            self.Redraw();
        });

        canvas.addEventListener('wheel', function (e) {
            e.preventDefault();
            var ev = self.MakeEvent(e);
            var delta = e.deltaY * (e.deltaMode === 1 ? 20 : 1);
            V.ZoomAt(self.view, ev.sx, ev.sy, Math.exp(-delta * self.settings.View.WheelFactor), self.settings);
            ev.world = V.S2W(self.view, ev.sx, ev.sy);
            self.lastEvent = ev;
            if (self.tool && typeof self.tool.onMove === 'function') self.tool.onMove(self, ev);
            self.Redraw();
        }, { passive : false });

        canvas.addEventListener('contextmenu', function (e) { e.preventDefault(); });

        canvas.addEventListener('pointerleave', function () {
            if (self.leftDown || self.pan) return;
            self.cursorWorld = null;
            self.snapShown = null;
            self.hoverId = null;
            self.Emit('onCursor', null);
            self.Redraw();
        });

        document.addEventListener('keydown', function (e) { self.OnKeyDown(e); }, true);
        document.addEventListener('keyup', function (e) { self.OnKeyUp(e); }, true);

        if (typeof window.ResizeObserver === 'function' && this.el.stage) {
            new window.ResizeObserver(function () { self.Redraw(); }).observe(this.el.stage);
        }
        window.addEventListener('resize', function () { self.Redraw(); });
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Keyboard
    // -------------------------------------------------------------------------

    function IsTextField(target) {
        if (!target || !target.tagName) return false;
        var tag = target.tagName.toUpperCase();
        if (tag === 'TEXTAREA' || tag === 'SELECT') return true;
        if (tag === 'INPUT') {
            var type = (target.type || 'text').toLowerCase();
            return [ 'checkbox', 'radio', 'button', 'range', 'color' ].indexOf(type) < 0;
        }
        return target.isContentEditable === true;
    }

    Editor.prototype.OnKeyDown = function (e) {
        if (!this.active) return;
        if (e.target === this.el.vcbInput) return;
        if (IsTextField(e.target)) return;
        if (this.hooks.isBlocked && this.hooks.isBlocked()) return;

        this.shift = e.shiftKey; this.ctrl = e.ctrlKey; this.alt = e.altKey;
        var handled = this.HandleKey(e);
        if (handled) { e.preventDefault(); e.stopPropagation(); }
    };

    Editor.prototype.HandleKey = function (e) {
        var key = e.key;

        if (key === 'Shift' || key === 'Control' || key === 'Alt') {
            if (!e.repeat && this.tool && typeof this.tool.onModifier === 'function') this.tool.onModifier(this, key);
            this.RefreshPointer();
            return false;
        }
        if (this.vcb.OnKey(e)) return true;

        if (e.ctrlKey && !e.altKey) {
            var k = key.toLowerCase();
            if (k === 'z' && !e.shiftKey) { this.Undo(); return true; }
            if (k === 'y' || (k === 'z' && e.shiftKey)) { this.Redo(); return true; }
            if (k === 'a') { this.SelectAll(); return true; }
            if (k === 'l') { this.ToggleSetting('Ortho'); return true; }
            if (k === 's') { this.Emit('onSaveShortcut'); return true; }
            return false;
        }

        switch (key) {
            case 'F3': this.ToggleSetting('Snap.On'); return true;
            case 'F6': this.ToggleSetting('Grid.Show'); return true;
            case 'F7': this.ToggleSetting('Grid.Snap'); return true;
            case 'F8': this.ToggleSetting('Ortho'); return true;
            case 'F9': this.ToggleSetting('DrawingAxes'); return true;
            case 'Escape': this.Escape(); return true;
            case 'Tab':
                if (this.tool && typeof this.tool.onKey === 'function') this.tool.onKey(this, e);
                this.UpdatePrompt();
                this.Redraw();
                return true;
            case 'Enter':
                if (this.tool && typeof this.tool.onKey === 'function' && this.tool.onKey(this, e)) { this.UpdatePrompt(); this.Redraw(); return true; }
                return false;
            case 'Delete':
            case 'Backspace':
                if (this.tool && typeof this.tool.onKey === 'function' && this.tool.onKey(this, e)) { this.UpdatePrompt(); this.Redraw(); return true; }
                if (this.tool && this.tool.id === 'select') { this.DeleteSelection(); return true; }
                return false;
            case 'ArrowLeft': case 'ArrowRight': case 'ArrowUp': case 'ArrowDown':
                return this.Arrow(key, e.shiftKey);
            default: break;
        }

        if (e.altKey || key.length !== 1) return false;
        var lower = key.toLowerCase();
        if (lower === 'g') { this.ToggleConstruction(); return true; }
        if (lower === 'z') { this.ZoomExtents(); return true; }
        var toolId = this.settings.Keys[(e.shiftKey ? 'Shift+' : '') + (lower === ' ' ? ' ' : lower)];
        if (!toolId && !e.shiftKey) toolId = this.settings.Keys[lower];
        if (toolId) {
            if (this.tool && this.tool.id === toolId && typeof this.tool.onRepeatKey === 'function') this.tool.onRepeatKey(this);
            else this.SetTool(toolId);
            return true;
        }
        return false;
    };

    // While a point is being placed the arrows lock an axis (Left / Right the
    // X axis, Up / Down the Y axis; the same key again frees it). Otherwise
    // they nudge the selection a millimetre, ten with Shift (TV).
    Editor.prototype.Arrow = function (key, shift) {
        var placing = this.tool && typeof this.tool.isPlacing === 'function' && this.tool.isPlacing(this);
        if (placing) {
            var axis = (key === 'ArrowLeft' || key === 'ArrowRight') ? 'x' : 'y';
            this.axisLock = this.axisLock === axis ? null : axis;
            this.Hint(this.axisLock ? (this.axisLock === 'x' ? '<Locked to the Y axis (across)>' : '<Locked to the Z axis (up)>') : '<Axis lock off>');
            this.RefreshPointer();
            return true;
        }
        if (!this.HasMovableSelection()) return false;
        var step = shift ? this.settings.View.NudgeBigMm : this.settings.View.NudgeMm;
        var delta = { x : 0, y : 0 };
        if (key === 'ArrowLeft') delta.x = -step;
        if (key === 'ArrowRight') delta.x = step;
        if (key === 'ArrowUp') delta.y = step;
        if (key === 'ArrowDown') delta.y = -step;
        this.MoveSelection(delta, 'Nudge');
        this.Hint('Nudged ' + step + ' mm.');
        return true;
    };

    Editor.prototype.OnKeyUp = function (e) {
        if (!this.active) return;
        if (e.key === 'Shift' || e.key === 'Control' || e.key === 'Alt') {
            this.shift = e.shiftKey; this.ctrl = e.ctrlKey; this.alt = e.altKey;
            this.RefreshPointer();
        }
    };

    // Esc: the tool's own step back first; then out of the tool; then out of
    // vertex mode; then the selection goes.
    Editor.prototype.Escape = function () {
        S.ClearAcquired(this.track);
        if (this.axisLock) { this.axisLock = null; this.RefreshPointer(); }
        if (this.tool && typeof this.tool.cancel === 'function' && this.tool.cancel(this)) {
            this.UpdatePrompt();
            this.Redraw();
            return;
        }
        if (this.tool && this.tool.id !== 'select') { this.SetTool('select'); return; }
        if (this.vertexMode) { this.SetVertexMode(false); this.Hint('Vertex mode off.'); return; }
        this.ClearSelection();
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Editor = {
        Create : function (elements, hooks) { return new Editor(elements, hooks); },
        Editor : Editor,
        ShiftKeys : ShiftKeys,
        LoadSettings : LoadSettings,
        SaveSettings : SaveSettings,
        DescribeReading : DescribeReading
    };

    // endregion ----------------------------------------------------------------
})();
