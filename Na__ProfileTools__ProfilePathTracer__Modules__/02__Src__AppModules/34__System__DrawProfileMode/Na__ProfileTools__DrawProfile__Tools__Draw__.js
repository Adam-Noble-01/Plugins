/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - TOOLS - SELECT AND DRAW
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Tools__Draw__.js
   NAMESPACE  : window.Na__DrawProfile__Tools  (registry + shared helpers)
   PURPOSE    : The tool registry, the helpers every tool shares, and the tools
                that select and draw: Select (with vertex mode and grips),
                Line, Rectangle, Arc, Circle, Dimension, Measure, Set Datum.

   A TOOL is { id, label, cursor, activate, deactivate, reset, prompt,
   vcbLabel, vcbReading, vcbPreview, onVcb, onMove, onDown, onUp, onDblClick,
   onRightClick, onKey, onUndo, cancel, isPlacing, draw }; every member is
   optional. The editor calls them; `ed` is the editor.

   @delegate  : TrueVision Layout Editor
                35__System__DrawingTools  ShapeTool (click-click lines, close
                                          within 10 px, Enter / double-click /
                                          right-click finish, Backspace pops),
                                          RectangleTool (W x H), DimensionTool
                                          (three clicks, Shift/Ortho H or V)
                37__System__VectorTools   ArcTool (2-point default, centre,
                                          3-point; Ns segments), CircleTool
                30__System__SheetTools    selection modifiers, window vs
                                          crossing, grips, vertex picking
   ============================================================================= */

(function () {
    'use strict';

    var G = window.Na__DrawProfile__Geom;
    var D = window.Na__DrawProfile__Doc;
    var V = window.Na__DrawProfile__View;

    // -------------------------------------------------------------------------
    // REGION | Registry
    // -------------------------------------------------------------------------

    var Tools = {
        list : {},
        Register : function (tool) { Tools.list[tool.id] = tool; return tool; },
        Get : function (id) { return Tools.list[id] || null; }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Shared Helpers
    // -------------------------------------------------------------------------

    var H = {};

    H.Fmt = function (ed, value) { return G.FormatMm(value, ed.settings.Precision); };
    H.Mm = function (ed, value) { return H.Fmt(ed, value) + ' mm'; };

    H.AngleDeg = function (a, b) {
        var deg = G.ToDeg(Math.atan2(b.y - a.y, b.x - a.x));
        return deg < 0 ? deg + 360 : deg;
    };

    // Ctrl adds, Shift toggles, Ctrl+Shift removes, nothing replaces (TV).
    H.Combine = function (current, ids, ev) {
        var next = new Set(current);
        if (ev.ctrl && ev.shift) { ids.forEach(function (id) { next.delete(id); }); return next; }
        if (ev.ctrl) { ids.forEach(function (id) { next.add(id); }); return next; }
        if (ev.shift) { ids.forEach(function (id) { if (next.has(id)) next.delete(id); else next.add(id); }); return next; }
        return new Set(ids);
    };

    // A point from a typed value: absolute [y,z]; across,up or @across,up from
    // the anchor; L<angle; a bare length along the band (the axis lock's axis
    // if one is held; a minus sign turns it round, as in TV).
    H.ResolvePoint = function (ed, parsed, anchor, aim) {
        if (!parsed.ok) return { ok : false, message : parsed.reason === 'unit' ? 'Units are mm, cm or m.' : 'That is not a length or a point.' };
        switch (parsed.type) {
            case 'absolute':
                return { ok : true, p : { x : parsed.x, y : parsed.y } };
            case 'pair':
                if (!anchor) return { ok : true, p : { x : parsed.first, y : parsed.second } };
                return { ok : true, p : { x : anchor.x + parsed.first, y : anchor.y + parsed.second } };
            case 'relative':
                if (!anchor) return { ok : false, message : '@across,up needs a point to measure from. Click the first point, or type Y,Z.' };
                return { ok : true, p : { x : anchor.x + parsed.dx, y : anchor.y + parsed.dy } };
            case 'polar':
                if (!anchor) return { ok : false, message : 'length<angle needs a point to measure from.' };
                var rad = G.ToRad(parsed.deg);
                return { ok : true, p : { x : anchor.x + (parsed.length * Math.cos(rad)), y : anchor.y + (parsed.length * Math.sin(rad)) } };
            case 'length':
                if (!anchor) return { ok : false, message : 'Click the first point before typing a length, or type its Y,Z.' };
                var dir = H.BandDirection(ed, anchor, aim);
                return { ok : true, p : { x : anchor.x + (dir.x * parsed.valueMm), y : anchor.y + (dir.y * parsed.valueMm) } };
            default:
                return { ok : false, message : 'That is not a length or a point.' };
        }
    };

    H.BandDirection = function (ed, anchor, aim) {
        var target = aim || anchor;
        if (ed.axisLock === 'x') return { x : (target.x - anchor.x) < 0 ? -1 : 1, y : 0 };
        if (ed.axisLock === 'y') return { x : 0, y : (target.y - anchor.y) < 0 ? -1 : 1 };
        var d = G.Sub(target, anchor);
        return G.Len(d) > 1e-9 ? G.Unit(d) : { x : 1, y : 0 };
    };

    H.SegmentsTyped = function (ed, parsed, toolId) {
        if (!parsed.ok || parsed.type !== 'segments') return null;
        var max = ed.settings.Curves.MaxSegments;
        if (parsed.count !== 0 && (parsed.count < 2 || parsed.count > max)) {
            return { ok : false, message : 'A curve takes 2 to ' + max + ' segments (0s goes back to automatic).' };
        }
        ed.Memory(toolId).segs = parsed.count;
        return { ok : true, message : parsed.count ? 'Curves from this tool: ' + parsed.count + ' segments.' : 'Curves from this tool: automatic segments.' };
    };

    H.SegmentsNote = function (ed, toolId) {
        var segs = ed.Memory(toolId).segs;
        return segs ? segs + ' segs' : 'auto segs';
    };

    // A drawn line: { type, a, b }, never of no length.
    H.Line = function (a, b) {
        return G.Dist(a, b) > G.SAME_MM ? { type : 'line', a : G.Copy(a), b : G.Copy(b) } : null;
    };

    Tools.H = H;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Select
    // -------------------------------------------------------------------------

    var Select = Tools.Register({
        id : 'select', label : 'Select', cursor : 'default',
        press : null, mode : null,

        activate : function () { this.press = null; this.mode = null; },
        reset : function () { this.press = null; this.mode = null; },

        prompt : function (ed) {
            if (this.mode === 'grip' || this.mode === 'move') return 'Release to drop it. Type a distance for an exact move along the drag, or across,up. Arrows lock an axis.';
            if (this.mode === 'bulge') return 'Drag the arc\'s middle to reshape it. Release to drop.';
            if (ed.vertexMode) {
                return 'VERTEX MODE: click or box vertices (Ctrl adds, Shift toggles), drag one to move them all, type across,up (e.g. 0,10) to move by values, Delete removes, Shift+click an edge adds a vertex. Esc leaves.';
            }
            if (ed.selection.size) return ed.selection.size + ' selected. Drag to move (type across,up for an exact move), drag a grip to stretch, Delete removes, G makes construction, Enter for vertex mode.';
            return 'Click to select, drag a box (to the right: whole items, to the left: anything it touches). Double-click selects a whole outline. Enter: vertex mode.';
        },

        vcbLabel : function (ed) {
            if (this.mode === 'grip' || this.mode === 'move') return 'Distance';
            return ed.HasMovableSelection() ? 'Move by' : '';
        },

        vcbReading : function (ed) {
            if ((this.mode === 'grip' || this.mode === 'move') && this.delta) return H.Fmt(ed, G.Len(this.delta));
            return ed.HasMovableSelection() ? 'across,up' : '';
        },

        vcbPreview : function (ed, text, parsed) {
            if (!parsed.ok) return '';
            if (parsed.type === 'pair' || parsed.type === 'relative') {
                var dx = parsed.type === 'pair' ? parsed.first : parsed.dx, dy = parsed.type === 'pair' ? parsed.second : parsed.dy;
                return '→ move ' + H.Fmt(ed, dx) + ' across, ' + H.Fmt(ed, dy) + ' up';
            }
            if (parsed.type === 'length' && (this.mode === 'grip' || this.mode === 'move')) return '→ ' + H.Mm(ed, parsed.valueMm) + ' along the drag';
            return '';
        },

        onVcb : function (ed, text, parsed) {
            if (!parsed.ok) return { ok : false, message : 'Type across,up (e.g. 0,10) to move by values.' };
            var delta = null;
            if (parsed.type === 'pair') delta = { x : parsed.first, y : parsed.second };
            else if (parsed.type === 'relative') delta = { x : parsed.dx, y : parsed.dy };
            else if (parsed.type === 'length' && (this.mode === 'grip' || this.mode === 'move') && this.delta) {
                var dir = ed.axisLock ? H.BandDirection(ed, { x : 0, y : 0 }, this.delta) : G.Unit(this.delta);
                if (!(G.Len(this.delta) > 0) && !ed.axisLock) return { ok : false, message : 'Drag a little way first, so the move has a direction.' };
                delta = G.Mul(dir, parsed.valueMm);
            }
            if (!delta) return { ok : false, message : 'Type how far across and up, e.g. 0,10 (or use Move, M, for a length along a direction).' };

            if (this.mode === 'grip' || this.mode === 'move') {
                var keys = this.dragKeys;
                var self = this;
                ed.UpdateTransient(function (doc) { self.ApplyDrag(ed, doc, keys, delta); });
                this.FinishDrag(ed, delta);
                return { ok : true, message : 'Moved ' + H.Mm(ed, G.Len(delta)) + '.' };
            }
            if (!ed.HasMovableSelection()) return { ok : false, message : 'Select edges or vertices first, then type across,up.' };
            ed.MoveSelection(delta, 'Move by values');
            return { ok : true, message : 'Moved ' + H.Fmt(ed, delta.x) + ' across, ' + H.Fmt(ed, delta.y) + ' up.' };
        },

        isPlacing : function () { return this.mode === 'grip' || this.mode === 'move'; },

        onMove : function (ed, ev) {
            var press = this.press;
            if (!press || !ed.leftDown) { this.Hover(ed, ev); return; }
            var moved = Math.hypot(ev.sx - press.sx, ev.sy - press.sy);

            if (!this.mode) {
                if (press.grip && moved >= ed.settings.Tol.DragStartPx) this.StartGrip(ed, press.grip);
                else if (press.vertex && moved >= ed.settings.Tol.DragStartPx) this.StartVertexDrag(ed, press.vertex);
                else if (press.hit && press.wasSelected && !ev.alt && moved >= ed.settings.Tol.DragPickedPx) this.StartMove(ed);
                else if ((press.empty || ev.alt || (press.hit && !press.wasSelected)) && moved >= ed.settings.Tol.DragStartPx) this.mode = 'box';
            }

            if (this.mode === 'box') {
                ed.box = { sx0 : press.sx, sy0 : press.sy, sx1 : ev.sx, sy1 : ev.sy, mode : ev.sx < press.sx ? 'crossing' : 'window' };
                return;
            }
            if (this.mode === 'grip' || this.mode === 'move') {
                var pick = ed.Pick(ev, this.anchor, { excludeKeys : this.dragKeys, exclude : this.dragExclude });
                var delta = G.Sub(pick.p, this.anchor);
                this.delta = delta;
                this.lock = pick.lock;
                var keys = this.dragKeys, self = this;
                ed.UpdateTransient(function (doc) { self.ApplyDrag(ed, doc, keys, delta); });
                return;
            }
            if (this.mode === 'bulge') {
                var snap = ed.SnapAt(ev.world, { exclude : new Set([ this.bulgeId ]) });
                ed.snapShown = snap;
                var target = snap.p;
                var id = this.bulgeId;
                ed.UpdateTransient(function (doc) {
                    var e = D.Get(doc, id);
                    if (!e) return;
                    if (e.type === 'circle') { var r = G.Dist(e.c, target); if (r > 1e-6) e.r = r; return; }
                    var arc = G.ArcThrough(e.a, target, e.b);
                    if (arc) e.sw = arc.sw;
                });
            }
        },

        Hover : function (ed, ev) {
            ed.snapShown = null;
            var tolGrip = ed.TolWorld(ed.settings.Tol.GripPx + 1);
            var grip = null;
            ed.gripsToDraw.forEach(function (g) {
                var d = G.Dist(g.p, ev.world);
                if (d <= tolGrip && (!grip || d < grip.d)) grip = { g : g, d : d };
            });
            var hoverKey = grip ? grip.g.key : null;
            var hoverId = null;
            if (!grip) {
                var hit = ed.HitEntity(ev.world);
                hoverId = hit ? hit.id : null;
            }
            if (hoverKey !== ed.hoverKey || hoverId !== ed.hoverId) {
                ed.hoverKey = hoverKey;
                ed.hoverId = hoverId;
                ed.RefreshGrips();
            }
            ed.SetCursor(grip ? 'move' : (hoverId ? 'pointer' : 'default'));
        },

        onDown : function (ed, ev) {
            var press = { sx : ev.sx, sy : ev.sy, world : ev.world, shift : ev.shift, ctrl : ev.ctrl, alt : ev.alt };
            this.mode = null;
            this.delta = null;
            var tolGrip = ed.TolWorld(ed.settings.Tol.GripPx + 1);
            var grip = null;
            ed.gripsToDraw.forEach(function (g) {
                var d = G.Dist(g.p, ev.world);
                if (d <= tolGrip && (!grip || d < grip.d)) grip = { g : g, d : d };
            });
            if (ev.alt) {
                press.empty = true;
            } else if (grip && grip.g.kind === 'bulge') {
                press.grip = grip.g;
            } else if (ed.vertexMode && grip) {
                press.vertex = grip.g.key;
            } else if (grip) {
                press.grip = grip.g;
            } else if (ed.vertexMode && ev.shift && !ev.ctrl) {
                var edge = ed.HitEntity(ev.world, { noDims : true });
                if (edge) {
                    var at = G.Nearest(D.Get(ed.doc, edge.id), ev.world).p;
                    var snap = ed.SnapAt(ev.world, { noTrack : true });
                    var point = snap.snapped && G.Nearest(D.Get(ed.doc, edge.id), snap.p).d < 1e-6 ? snap.p : at;
                    ed.Commit('Add vertex', function (doc) { return { ok : D.SplitAt(doc, edge.id, point).length > 0 }; });
                    ed.vsel.add(D.KeyOf(point));
                    ed.RefreshGrips();
                    ed.Hint('Vertex added.');
                    this.press = null;
                    return;
                }
                press.empty = true;
            } else {
                var hit = ed.HitEntity(ev.world);
                if (hit) { press.hit = hit; press.wasSelected = ed.selection.has(hit.id); }
                else press.empty = true;
            }
            this.press = press;
        },

        // Every drag snaps to the drawing as it was before it, leaving out
        // what the drag moves or stretches (dragExclude), so a corner never
        // snaps to its own preview.
        StartGrip : function (ed, grip) {
            ed.BeginTransient({ snapBase : true });
            if (grip.kind === 'bulge') {
                this.mode = 'bulge';
                this.bulgeId = grip.id;
                return;
            }
            this.mode = 'grip';
            this.anchor = G.Copy(grip.p);
            this.dragKeys = new Set([ grip.key ]);
            this.dragExclude = ed.MovingIds(this.dragKeys, null);
        },

        // Dragging a picked vertex carries every picked vertex (TV Grips).
        StartVertexDrag : function (ed, key) {
            if (!ed.vsel.has(key)) { ed.vsel = new Set([ key ]); }
            var v = D.VertexIndex(ed.doc).get(key);
            if (!v) return;
            ed.BeginTransient({ snapBase : true });
            this.mode = 'grip';
            this.anchor = G.Copy(v.p);
            this.dragKeys = new Set(ed.vsel);
            this.dragExclude = ed.MovingIds(this.dragKeys, null);
        },

        StartMove : function (ed) {
            var snap = ed.SnapAt(this.press.world, { noTrack : true });
            ed.BeginTransient({ snapBase : true });
            this.mode = 'move';
            this.anchor = G.Copy(snap.snapped ? snap.p : this.press.world);
            this.dragKeys = ed.SelectionKeys();
            this.dragExclude = ed.MovingIds(this.dragKeys, ed.selection);
        },

        ApplyDrag : function (ed, doc, keys, delta) {
            if (this.mode === 'move') { ed.MoveSelectionIn(doc, delta); return; }
            D.Translate(doc, keys, delta);
        },

        FinishDrag : function (ed, delta) {
            var label = this.mode === 'move' ? 'Move' : 'Move vertex';
            ed.EndTransient(true, label);
            if (ed.vertexMode && this.dragKeys) {
                var moved = new Set();
                this.dragKeys.forEach(function (k) {
                    var parts = k.split(',');
                    moved.add(D.KeyOf({ x : parseFloat(parts[0]) + delta.x, y : parseFloat(parts[1]) + delta.y }));
                });
                ed.vsel = moved;
            }
            this.mode = null;
            this.press = null;
            this.delta = null;
            this.dragExclude = null;
            ed.axisLock = null;
            ed.RefreshGrips();
            ed.Hint('Moved ' + H.Mm(ed, G.Len(delta)) + ' (' + H.Fmt(ed, delta.x) + ' across, ' + H.Fmt(ed, delta.y) + ' up).');
        },

        onUp : function (ed, ev) {
            var press = this.press;
            if (!press) return;
            if (this.mode === 'grip' || this.mode === 'move') { this.FinishDrag(ed, this.delta || { x : 0, y : 0 }); return; }
            if (this.mode === 'bulge') {
                ed.EndTransient(true, 'Reshape arc');
                this.mode = null; this.press = null;
                ed.RefreshGrips();
                return;
            }
            if (this.mode === 'box') {
                this.FinishBox(ed, press, ev);
                ed.box = null;
                this.mode = null; this.press = null;
                return;
            }
            // A click.
            if (press.vertex) {
                ed.vsel = H.Combine(ed.vsel, [ press.vertex ], ev);
                ed.RefreshGrips();
                ed.Emit('onSelectionChanged');
            } else if (press.hit) {
                ed.SetSelection(Array.from(H.Combine(ed.selection, [ press.hit.id ], ev)));
            } else if (press.empty && !ev.ctrl && !ev.shift) {
                if (ed.vertexMode) { ed.vsel.clear(); ed.RefreshGrips(); ed.Emit('onSelectionChanged'); }
                else ed.ClearSelection();
            }
            this.press = null;
        },

        FinishBox : function (ed, press, ev) {
            var a = V.S2W(ed.view, press.sx, press.sy), b = ev.world;
            var rect = { minX : Math.min(a.x, b.x), minY : Math.min(a.y, b.y), maxX : Math.max(a.x, b.x), maxY : Math.max(a.y, b.y) };
            var mode = ev.sx < press.sx ? 'crossing' : 'window';
            if (ed.vertexMode) {
                var keys = [];
                D.VertexIndex(ed.doc).forEach(function (v) { if (G.PointInRect(v.p, rect)) keys.push(v.key); });
                ed.vsel = H.Combine(ed.vsel, keys, ev);
                ed.RefreshGrips();
                ed.Emit('onSelectionChanged');
                ed.Hint(ed.vsel.size + ' vertex(es) picked.');
                return;
            }
            var ids = [];
            ed.doc.ents.forEach(function (e) { if (G.EntityInRect(e, rect, mode, ed.settings.Curves)) ids.push(e.id); });
            ed.doc.dims.forEach(function (d) {
                var inA = G.PointInRect(d.a, rect), inB = G.PointInRect(d.b, rect);
                if (mode === 'window' ? (inA && inB) : (inA || inB || G.SegmentTouchesRect(d.a, d.b, rect))) ids.push(d.id);
            });
            ed.SetSelection(Array.from(H.Combine(ed.selection, ids, ev)));
        },

        onDblClick : function (ed, ev) {
            var hit = ed.HitEntity(ev.world, { noDims : true });
            if (!hit) return;
            var chain = D.ChainOf(ed.doc, hit.id);
            ed.SetSelection(Array.from(H.Combine(ed.selection, chain, ev)));
            ed.Hint(chain.length + ' edge(s) in that run selected.');
        },

        onKey : function (ed, e) {
            if (e.key === 'Enter' && !this.mode) {
                ed.SetVertexMode(!ed.vertexMode);
                ed.Hint(ed.vertexMode ? 'Vertex mode: pick vertices to move or delete.' : 'Vertex mode off.');
                return true;
            }
            return false;
        },

        cancel : function (ed) {
            if (this.mode === 'grip' || this.mode === 'move' || this.mode === 'bulge') {
                ed.EndTransient(false);
                this.mode = null; this.press = null; this.delta = null;
                ed.RefreshGrips();
                return true;
            }
            if (this.mode === 'box') { ed.box = null; this.mode = null; this.press = null; return true; }
            return false;
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Line (TV ShapeTool)
    // -------------------------------------------------------------------------

    Tools.Register({
        id : 'line', label : 'Line', cursor : 'crosshair',
        pts : [], cur : null, lock : null, redo : [],

        activate : function () { this.pts = []; this.cur = null; this.redo = []; },
        reset : function () { this.pts = []; this.cur = null; this.redo = []; },
        deactivate : function (ed) { this.Finish(ed, true); },

        Anchor : function () { return this.pts.length ? this.pts[this.pts.length - 1] : null; },

        prompt : function () {
            if (!this.pts.length) return 'LINE: click the start point, or type its Y,Z (e.g. 0,0) and Enter.';
            return 'LINE: click the next point. Type a length along the line, across,up (e.g. 50,0) or length<angle. Click the first point to close; Enter, double-click or right-click finishes; Backspace takes the last point back.';
        },
        vcbLabel : function () { return this.pts.length ? 'Length' : 'Start Y,Z'; },
        vcbReading : function (ed) {
            var a = this.Anchor();
            return a && this.cur ? H.Fmt(ed, G.Dist(a, this.cur)) : '';
        },
        vcbPreview : function (ed, text, parsed) {
            if (parsed.ok && parsed.type === 'pair' && !this.pts.length) return '→ start at Y ' + H.Fmt(ed, parsed.first) + ', Z ' + H.Fmt(ed, parsed.second);
            if (parsed.ok && parsed.type === 'length' && this.pts.length) return '→ ' + H.Mm(ed, parsed.valueMm) + ' along the line';
            return '';
        },
        isPlacing : function () { return this.pts.length > 0; },

        onMove : function (ed, ev) {
            var anchor = this.Anchor();
            var exclude = anchor ? new Set([ D.KeyOf(anchor) ]) : null;
            var pick = ed.Pick(ev, anchor, { excludeKeys : exclude });
            var p = pick.p;
            // Closing onto the first point (TV: within 10 px of the RESOLVED point).
            if (this.pts.length >= 3) {
                var first = V.W2S(ed.view, this.pts[0]), here = V.W2S(ed.view, p);
                if (G.Dist(first, here) <= ed.settings.Tol.ClosePx) {
                    p = G.Copy(this.pts[0]);
                    ed.snapShown = { p : p, kind : 'end', label : 'Close', target : 'shape', guides : [] };
                }
            }
            this.cur = p;
            this.lock = pick.lock;
        },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            if (this.cur) this.Place(ed, this.cur);
        },

        Place : function (ed, p) {
            if (!this.pts.length) {
                ed.BeginTransient();
                this.pts = [ G.Copy(p) ];
                this.redo = [];
                return;
            }
            var anchor = this.Anchor();
            if (G.Dist(anchor, p) < 1e-6) return;
            this.pts.push(G.Copy(p));
            this.redo = [];
            this.Apply(ed);
            ed.axisLock = null;
            if (this.pts.length >= 4 && G.Same(p, this.pts[0], 1e-9)) {
                this.Finish(ed, true);
                ed.Hint('Outline closed.');
            }
        },

        Apply : function (ed) {
            var pts = this.pts;
            ed.UpdateTransient(function (doc) {
                for (var i = 1; i < pts.length; i++) {
                    var line = H.Line(pts[i - 1], pts[i]);
                    if (line) D.Add(doc, line);
                }
            });
        },

        Finish : function (ed, keep) {
            if (!this.pts.length) return false;
            ed.EndTransient(keep && this.pts.length >= 2, 'Line');
            this.pts = [];
            this.cur = null;
            this.redo = [];
            ed.axisLock = null;
            return true;
        },

        onDblClick : function (ed) { this.Finish(ed, true); },
        onRightClick : function (ed) { this.Finish(ed, true); },

        onKey : function (ed, e) {
            if (e.key === 'Enter') return this.Finish(ed, true);
            if (e.key === 'Backspace' || e.key === 'Delete') return this.onUndo(ed);
            return false;
        },

        // Mid-draw undo pops the last point; redo puts it back (TV ShapeTool).
        onUndo : function (ed) {
            if (!this.pts.length) return false;
            if (this.pts.length === 1) { ed.EndTransient(false); this.pts = []; return true; }
            this.redo.push(this.pts.pop());
            this.Apply(ed);
            return true;
        },
        onRedo : function (ed) {
            if (!this.pts.length || !this.redo.length) return false;
            this.pts.push(this.redo.pop());
            this.Apply(ed);
            return true;
        },

        cancel : function (ed) { return this.Finish(ed, true); },

        onVcb : function (ed, text, parsed) {
            var resolved = H.ResolvePoint(ed, parsed, this.Anchor(), this.cur);
            if (!resolved.ok) return resolved;
            this.Place(ed, resolved.p);
            this.cur = resolved.p;
            return { ok : true, message : this.pts.length === 1 ? 'Started at Y ' + H.Fmt(ed, resolved.p.x) + ', Z ' + H.Fmt(ed, resolved.p.y) + '.' : '' };
        },

        draw : function (ed, ctx, view) {
            var a = this.Anchor();
            if (!a || !this.cur) return;
            V.DrawBand(view, ed.settings, a, this.cur, this.lock);
            V.DrawLabel(view, this.cur, H.Mm(ed, G.Dist(a, this.cur)) + '  ' + H.Fmt(ed, H.AngleDeg(a, this.cur)) + '°', '#1f2937');
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Rectangle (TV RectangleTool: W x H towards the cursor)
    // -------------------------------------------------------------------------

    Tools.Register({
        id : 'rectangle', label : 'Rectangle', cursor : 'crosshair',
        c1 : null, cur : null,

        activate : function () { this.c1 = null; this.cur = null; },
        reset : function () { this.c1 = null; this.cur = null; },
        prompt : function () {
            return this.c1 ? 'RECTANGLE: click the opposite corner, or type width,height (e.g. 120,40).' : 'RECTANGLE: click the first corner, or type its Y,Z.';
        },
        vcbLabel : function () { return this.c1 ? 'Width,Height' : 'Corner Y,Z'; },
        vcbReading : function (ed) {
            if (!this.c1 || !this.cur) return '';
            return H.Fmt(ed, Math.abs(this.cur.x - this.c1.x)) + ', ' + H.Fmt(ed, Math.abs(this.cur.y - this.c1.y));
        },
        isPlacing : function () { return !!this.c1; },

        onMove : function (ed, ev) {
            this.cur = ed.Pick(ev, null).p;
        },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            if (!this.c1) { this.c1 = G.Copy(this.cur); return; }
            this.Make(ed, this.cur);
        },

        Make : function (ed, c2) {
            var a = this.c1;
            if (Math.abs(c2.x - a.x) < 1e-6 || Math.abs(c2.y - a.y) < 1e-6) { ed.Hint('A rectangle needs width and height.', true); return false; }
            var pts = [ a, { x : c2.x, y : a.y }, c2, { x : a.x, y : c2.y } ];
            ed.Commit('Rectangle', function (doc) {
                for (var i = 0; i < 4; i++) D.Add(doc, H.Line(pts[i], pts[(i + 1) % 4]));
                return { ok : true };
            });
            this.c1 = null;
            return true;
        },

        onVcb : function (ed, text, parsed) {
            if (!this.c1) {
                var start = H.ResolvePoint(ed, parsed, null, null);
                if (!start.ok) return start;
                this.c1 = start.p;
                return { ok : true, message : 'First corner placed.' };
            }
            var pair = window.Na__DrawProfile__Vcb.Pair(text);
            if (!pair.ok) return { ok : false, message : 'Type width,height, e.g. 120,40 (one figure makes a square).' };
            var sx = this.cur && this.cur.x < this.c1.x ? -1 : 1, sy = this.cur && this.cur.y < this.c1.y ? -1 : 1;
            var w = pair.first !== null ? pair.first : Math.abs((this.cur || this.c1).x - this.c1.x);
            var h = pair.second !== null ? pair.second : Math.abs((this.cur || this.c1).y - this.c1.y);
            var made = this.Make(ed, { x : this.c1.x + (sx * w), y : this.c1.y + (sy * h) });
            return made ? { ok : true, message : 'Rectangle ' + H.Fmt(ed, w) + ' x ' + H.Fmt(ed, h) + ' mm.' } : { ok : false, message : 'A rectangle needs width and height.' };
        },

        cancel : function () { if (!this.c1) return false; this.c1 = null; return true; },

        draw : function (ed, ctx, view) {
            if (!this.c1 || !this.cur) return;
            var a = this.c1, c = this.cur;
            [ [ a, { x : c.x, y : a.y } ], [ { x : c.x, y : a.y }, c ], [ c, { x : a.x, y : c.y } ], [ { x : a.x, y : c.y }, a ] ].forEach(function (s) {
                var line = H.Line(s[0], s[1]);
                if (line) V.DrawPreviewEntity(view, ed.settings, line, 'add');
            });
            V.DrawLabel(view, c, H.Fmt(ed, Math.abs(c.x - a.x)) + ' x ' + H.Fmt(ed, Math.abs(c.y - a.y)) + ' mm');
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Arc (TV ArcTool: 2-point default, centre, 3-point)
    // -------------------------------------------------------------------------

    var ARC_MODES = [ '2pt', 'centre', '3pt' ];
    var ARC_MODE_LABELS = { '2pt' : '2-point (ends, then bulge)', 'centre' : 'centre, start, sweep', '3pt' : '3-point (start, through, end)' };

    Tools.Register({
        id : 'arc', label : 'Arc', cursor : 'crosshair',
        step : 0, pts : [], cur : null, preview : null, lastSweep : null, lock : null,

        Mode : function (ed) { return ed.Memory('arc').mode || '2pt'; },
        activate : function () { this.step = 0; this.pts = []; this.cur = null; this.preview = null; this.lastSweep = null; },
        reset : function () { this.activate(); },

        CycleMode : function (ed) {
            var mode = this.Mode(ed);
            var next = ARC_MODES[(ARC_MODES.indexOf(mode) + 1) % ARC_MODES.length];
            ed.Memory('arc').mode = next;
            this.activate();
            ed.Hint('Arc: ' + ARC_MODE_LABELS[next] + '.');
        },
        onRepeatKey : function (ed) { this.CycleMode(ed); },

        prompt : function (ed) {
            var mode = this.Mode(ed);
            var tail = ' (' + H.SegmentsNote(ed, 'arc') + '; Ns sets segments; Tab: ' + ARC_MODE_LABELS[ARC_MODES[(ARC_MODES.indexOf(mode) + 1) % 3]] + ')';
            if (mode === 'centre') {
                return [ 'ARC (centre): click the centre.', 'ARC (centre): click the start point; it sets the radius (or type the radius).', 'ARC (centre): sweep round and click the end, or type the angle in degrees.' ][this.step] + tail;
            }
            if (mode === '3pt') {
                return [ 'ARC (3-point): click the start.', 'ARC (3-point): click a point the arc passes through.', 'ARC (3-point): click the end.' ][this.step] + tail;
            }
            return [ 'ARC: click the start.', 'ARC: click the end (or type the chord length).', 'ARC: pull out the bulge and click, or type the radius (e.g. 20), a bulge (5b) or an angle (90°).' ][this.step] + tail;
        },

        vcbLabel : function (ed) {
            var mode = this.Mode(ed);
            if (mode === 'centre') return [ 'Centre Y,Z', 'Radius', 'Angle' ][this.step];
            if (mode === '3pt') return [ 'Start Y,Z', 'Through', 'End' ][this.step];
            return [ 'Start Y,Z', 'Chord', 'Radius' ][this.step];
        },

        vcbReading : function (ed) {
            var g = this.preview ? G.ArcGeom(this.preview) : null;
            var mode = this.Mode(ed);
            if (this.step === 1 && this.cur && this.pts[0]) return H.Fmt(ed, G.Dist(this.pts[0], this.cur));
            if (this.step === 2 && g) return mode === 'centre' ? H.Fmt(ed, G.ToDeg(Math.abs(g.sw))) : H.Fmt(ed, g.r);
            return '';
        },

        isPlacing : function () { return this.step === 1; },

        onKey : function (ed, e) {
            if (e.key === 'Tab') { this.CycleMode(ed); return true; }
            return false;
        },

        onMove : function (ed, ev) {
            var mode = this.Mode(ed);
            var anchor = this.step === 1 ? this.pts[0] : null;
            var pick = ed.Pick(ev, anchor);
            this.cur = pick.p;
            this.lock = pick.lock;
            this.preview = null;
            if (this.step !== 2) return;

            var segs = ed.Memory('arc').segs || 0;
            if (mode === '2pt') {
                var a = this.pts[0], b = this.pts[1];
                var chord = G.Dist(a, b);
                var s = G.SagittaOf(a, b, this.cur);
                // TV: an exact half circle within 8 px.
                if (Math.abs(Math.abs(s) - (chord / 2)) * ed.view.scale <= ed.settings.Curves.HalfSnapPx) {
                    s = (s < 0 ? -1 : 1) * (chord / 2);
                    ed.snapShown = { p : G.Add(G.Mid(a, b), G.Mul(G.Left(G.Unit(G.Sub(b, a))), s)), kind : 'mid', label : 'Half circle', target : 'shape', guides : [] };
                }
                if (Math.abs(s) > 1e-9) this.preview = { type : 'arc', a : a, b : b, sw : G.SweepFromSagitta(chord, s), segs : segs };
            } else if (mode === 'centre') {
                var c = this.pts[0], start = this.pts[1];
                var r = G.Dist(c, start);
                var a0 = Math.atan2(start.y - c.y, start.x - c.x);
                var sweep = G.CarrySweep(this.lastSweep, a0, Math.atan2(this.cur.y - c.y, this.cur.x - c.x));
                this.lastSweep = sweep;
                if (Math.abs(sweep) > 1e-6) { this.preview = G.ArcFromCentre(c, r, a0, sweep, segs); this.preview.a = G.Copy(start); }
            } else {
                var arc = G.ArcThrough(this.pts[0], this.pts[1], this.cur);
                if (arc) this.preview = { type : 'arc', a : this.pts[0], b : G.Copy(this.cur), sw : arc.sw, segs : segs };
            }
        },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            this.Advance(ed, this.cur);
        },

        Advance : function (ed, p) {
            if (this.step < 2) {
                if (this.step === 1 && G.Dist(this.pts[0], p) < 1e-6) return;
                this.pts.push(G.Copy(p));
                this.step += 1;
                ed.axisLock = null;
                this.lastSweep = null;
                return;
            }
            if (!this.preview) { ed.Hint('Pull the arc out from its chord first.', true); return; }
            this.Commit(ed, this.preview);
        },

        Commit : function (ed, arc) {
            var made = { type : 'arc', a : G.Copy(arc.a), b : G.Copy(arc.b), sw : arc.sw, segs : ed.Memory('arc').segs || 0 };
            ed.Commit('Arc', function (doc) { D.Add(doc, made); return { ok : true }; });
            var g = G.ArcGeom(made);
            ed.Hint('Arc: radius ' + H.Mm(ed, g.r) + ', ' + H.Fmt(ed, G.ToDeg(Math.abs(g.sw))) + '°, ' + G.EntitySegments(made, ed.settings.Curves) + ' segments.');
            this.activate();
        },

        onVcb : function (ed, text, parsed) {
            var typedSegs = H.SegmentsTyped(ed, parsed, 'arc');
            if (typedSegs) { if (this.preview) this.preview.segs = ed.Memory('arc').segs; return typedSegs; }
            var mode = this.Mode(ed);

            if (this.step === 0) {
                var start = H.ResolvePoint(ed, parsed, null, null);
                if (!start.ok) return start;
                this.Advance(ed, start.p);
                return { ok : true };
            }
            if (this.step === 1) {
                if (mode === 'centre' && parsed.ok && (parsed.type === 'length' || parsed.type === 'radius')) {
                    var rr = parsed.valueMm;
                    if (!(rr > 0)) return { ok : false, message : 'A radius has to be above nothing.' };
                    var dir = H.BandDirection(ed, this.pts[0], this.cur);
                    this.Advance(ed, G.Add(this.pts[0], G.Mul(dir, rr)));
                    return { ok : true };
                }
                var end = H.ResolvePoint(ed, parsed, this.pts[0], this.cur);
                if (!end.ok) return end;
                this.Advance(ed, end.p);
                return { ok : true };
            }

            // Step 2: the arc's shape.
            if (mode === 'centre') {
                var deg = parsed.ok ? (parsed.type === 'angle' ? parsed.deg : (parsed.type === 'length' ? parsed.valueMm : null)) : null;
                if (deg === null || !(Math.abs(deg) > 0) || Math.abs(deg) >= 360) return { ok : false, message : 'Type the sweep in degrees, more than 0 and under 360 (e.g. 90).' };
                var c = this.pts[0], s0 = this.pts[1];
                var a0 = Math.atan2(s0.y - c.y, s0.x - c.x);
                var sign = this.lastSweep !== null && this.lastSweep < 0 ? -1 : 1;
                var arcC = G.ArcFromCentre(c, G.Dist(c, s0), a0, sign * G.ToRad(Math.abs(deg)), 0);
                arcC.a = G.Copy(s0);
                this.Commit(ed, arcC);
                return { ok : true };
            }
            if (mode === '3pt') return { ok : false, message : 'Click the end point (only segments, e.g. 12s, can be typed here).' };

            var a = this.pts[0], b = this.pts[1];
            var chord = G.Dist(a, b);
            var side = this.cur ? (G.SagittaOf(a, b, this.cur) < 0 ? -1 : 1) : 1;
            var currentS = this.cur ? Math.abs(G.SagittaOf(a, b, this.cur)) : 0;
            var s = null;
            if (parsed.ok && (parsed.type === 'length' || parsed.type === 'radius' || parsed.type === 'diameter')) {
                var radius = parsed.type === 'diameter' ? parsed.valueMm / 2 : parsed.valueMm;
                if (!(radius >= (chord / 2) - 1e-9)) {
                    return { ok : false, message : 'A ' + H.Mm(ed, radius) + ' radius cannot span this ' + H.Mm(ed, chord) + ' chord: use at least ' + H.Mm(ed, chord / 2) + ' (or type a bulge, e.g. 5b).' };
                }
                s = G.SagittaForRadius(chord, radius, side, currentS > chord / 2);
            } else if (parsed.ok && parsed.type === 'bulge') {
                s = side * Math.abs(parsed.valueMm);
            } else if (parsed.ok && parsed.type === 'angle') {
                if (!(Math.abs(parsed.deg) > 0) || Math.abs(parsed.deg) >= 360) return { ok : false, message : 'An arc sweeps more than 0° and less than 360°.' };
                s = G.SagittaFromSweep(chord, -side * G.ToRad(Math.abs(parsed.deg)));
            } else {
                return { ok : false, message : 'Type the radius (e.g. 20), a bulge (5b), an angle (90°) or segments (12s).' };
            }
            if (!(Math.abs(s) > 1e-9)) return { ok : false, message : 'That arc has no bulge.' };
            this.Commit(ed, { type : 'arc', a : a, b : b, sw : G.SweepFromSagitta(chord, s) });
            return { ok : true };
        },

        cancel : function () {
            if (!this.step) return false;
            this.activate();
            return true;
        },

        draw : function (ed, ctx, view) {
            var mode = this.Mode(ed);
            if (this.step === 1 && this.cur) {
                V.DrawBand(view, ed.settings, this.pts[0], this.cur, this.lock);
                if (mode === 'centre') V.DrawLabel(view, this.cur, 'R ' + H.Mm(ed, G.Dist(this.pts[0], this.cur)));
            }
            if (this.step === 2) {
                if (mode === '2pt') V.DrawBand(view, ed.settings, this.pts[0], this.pts[1], null);
                if (mode === 'centre') { V.DrawBand(view, ed.settings, this.pts[0], this.pts[1], null); V.DrawPointMark(view, this.pts[0], '#2563eb', 3); }
                if (this.preview) {
                    V.DrawPreviewEntity(view, ed.settings, this.preview, 'add');
                    var g = G.ArcGeom(this.preview);
                    if (g) V.DrawLabel(view, this.cur, 'R ' + H.Mm(ed, g.r) + '  ' + H.Fmt(ed, G.ToDeg(Math.abs(g.sw))) + '°  ' + G.EntitySegments(this.preview, ed.settings.Curves) + ' segs');
                }
            }
            this.pts.forEach(function (p) { V.DrawPointMark(view, p, '#2563eb', 2.5); });
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Circle (TV CircleTool)
    // -------------------------------------------------------------------------

    Tools.Register({
        id : 'circle', label : 'Circle', cursor : 'crosshair',
        c : null, cur : null,

        activate : function () { this.c = null; this.cur = null; },
        reset : function () { this.activate(); },
        prompt : function (ed) {
            return (this.c ? 'CIRCLE: click a point on the circle, or type the radius (20), diameter (40d).' : 'CIRCLE: click the centre.') +
                   ' (' + H.SegmentsNote(ed, 'circle') + '; Ns sets segments.) A circle on its own is a round profile; trim it to use part of it.';
        },
        vcbLabel : function () { return this.c ? 'Radius' : 'Centre Y,Z'; },
        vcbReading : function (ed) { return this.c && this.cur ? H.Fmt(ed, G.Dist(this.c, this.cur)) : ''; },

        onMove : function (ed, ev) { this.cur = ed.Pick(ev, null, { from : this.c }).p; },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            if (!this.c) { this.c = G.Copy(this.cur); return; }
            this.Make(ed, G.Dist(this.c, this.cur));
        },

        Make : function (ed, r) {
            if (!(r > 1e-4)) { ed.Hint('A circle needs a radius.', true); return false; }
            var made = { type : 'circle', c : G.Copy(this.c), r : r, segs : ed.Memory('circle').segs || 0 };
            ed.Commit('Circle', function (doc) { D.Add(doc, made); return { ok : true }; });
            ed.Hint('Circle: radius ' + H.Mm(ed, r) + ', ' + G.EntitySegments(made, ed.settings.Curves) + ' segments.');
            this.c = null;
            return true;
        },

        onVcb : function (ed, text, parsed) {
            var typedSegs = H.SegmentsTyped(ed, parsed, 'circle');
            if (typedSegs) return typedSegs;
            if (!this.c) {
                var at = H.ResolvePoint(ed, parsed, null, null);
                if (!at.ok) return at;
                this.c = at.p;
                return { ok : true };
            }
            if (!parsed.ok) return { ok : false, message : 'Type the radius (e.g. 20) or diameter (40d).' };
            var r = parsed.type === 'diameter' ? parsed.valueMm / 2 : ((parsed.type === 'length' || parsed.type === 'radius') ? parsed.valueMm : null);
            if (r === null) return { ok : false, message : 'Type the radius (e.g. 20) or diameter (40d).' };
            return this.Make(ed, Math.abs(r)) ? { ok : true } : { ok : false, message : 'A circle needs a radius.' };
        },

        cancel : function () { if (!this.c) return false; this.c = null; return true; },

        draw : function (ed, ctx, view) {
            if (!this.c || !this.cur) return;
            var r = G.Dist(this.c, this.cur);
            if (r > 1e-6) V.DrawPreviewEntity(view, ed.settings, { type : 'circle', c : this.c, r : r, segs : ed.Memory('circle').segs || 0 }, 'add');
            V.DrawBand(view, ed.settings, this.c, this.cur, null);
            V.DrawLabel(view, this.cur, 'R ' + H.Mm(ed, r));
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Dimension (TV DimensionTool: three clicks)
    // -------------------------------------------------------------------------

    var ORIENTS = [ null, 'aligned', 'horizontal', 'vertical' ];

    Tools.Register({
        id : 'dimension', label : 'Dimension', cursor : 'crosshair',
        step : 0, a : null, b : null, ka : null, kb : null, cur : null, orient : null,

        activate : function (ed) { this.step = 0; this.a = this.b = this.ka = this.kb = this.cur = null; ed.dimPreview = null; },
        reset : function (ed) { this.activate(ed); },

        prompt : function () {
            var mode = this.orient ? this.orient : 'automatic: aligned, or level / plumb with Shift or Ortho';
            return [ 'DIMENSION: click the first point to measure from.', 'DIMENSION: click the second point.', 'DIMENSION: place the line and click, or type its offset (Tab: ' + mode + ').' ][this.step];
        },
        vcbLabel : function () { return this.step === 2 ? 'Offset' : ''; },
        vcbReading : function (ed) { return this.step === 2 && ed.dimPreview ? H.Fmt(ed, Math.abs(ed.dimPreview.off)) : ''; },
        isPlacing : function () { return this.step === 1; },

        KeyAt : function (ed, p) {
            var v = D.VertexIndex(ed.doc).get(D.KeyOf(p));
            return v ? v.key : null;
        },

        Orient : function (ed, ev) {
            if (this.orient) return this.orient;
            if (!(!!ed.settings.Ortho !== !!ev.shift)) return 'aligned';
            // TV OrthoToward: beside the points' box -> vertical, above / below -> horizontal.
            var minX = Math.min(this.a.x, this.b.x), maxX = Math.max(this.a.x, this.b.x);
            var c = this.cur;
            return (c.x < minX || c.x > maxX) ? 'vertical' : 'horizontal';
        },

        onMove : function (ed, ev) {
            if (this.step < 2) {
                this.cur = ed.Pick(ev, this.step === 1 ? this.a : null).p;
                return;
            }
            ed.snapShown = null;
            this.cur = ev.world;
            var orient = this.Orient(ed, ev);
            var sk = V.DimensionSkeleton(this.a, this.b, 0, orient, 0, 0);
            if (!sk) { ed.dimPreview = null; return; }
            var off = G.Dot(G.Sub(this.cur, this.a), sk.perp);
            ed.dimPreview = { id : '__preview', a : this.a, b : this.b, off : off, orient : orient };
        },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            if (this.step === 0) { this.a = G.Copy(this.cur); this.ka = this.KeyAt(ed, this.a); this.step = 1; return; }
            if (this.step === 1) {
                if (G.Dist(this.a, this.cur) < 1e-6) return;
                this.b = G.Copy(this.cur); this.kb = this.KeyAt(ed, this.b); this.step = 2;
                ed.axisLock = null;
                this.onMove(ed, ev);
                return;
            }
            this.Make(ed, ed.dimPreview);
        },

        Make : function (ed, preview) {
            if (!preview || !V.DimensionSkeleton(preview.a, preview.b, 0, preview.orient, 0, 0)) {
                ed.Hint('That dimension measures nothing in that direction. Tab picks another.', true);
                return false;
            }
            var self = this;
            var length = V.DimensionSkeleton(preview.a, preview.b, preview.off, preview.orient, 0, 0).length;
            ed.Commit('Dimension', function (doc) {
                doc.dims.push({ id : D.NewId(doc, 'd'), a : G.Copy(self.a), b : G.Copy(self.b), ka : self.ka, kb : self.kb, off : preview.off, orient : preview.orient });
                return { ok : true };
            });
            ed.Hint('Dimension: ' + H.Mm(ed, length) + '.');
            this.activate(ed);
            return true;
        },

        onKey : function (ed, e) {
            if (e.key !== 'Tab') return false;
            this.orient = ORIENTS[(ORIENTS.indexOf(this.orient) + 1) % ORIENTS.length];
            ed.Hint('Dimension: ' + (this.orient || 'automatic') + '.');
            ed.RefreshPointer();
            return true;
        },

        onVcb : function (ed, text, parsed) {
            if (this.step !== 2 || !ed.dimPreview) return { ok : false, message : 'Pick the two points first; then the offset can be typed.' };
            if (!parsed.ok || parsed.type !== 'length') return { ok : false, message : 'Type how far off the line sits, e.g. 15.' };
            var preview = Object.assign({}, ed.dimPreview);
            preview.off = (preview.off < 0 ? -1 : 1) * Math.abs(parsed.valueMm);
            return this.Make(ed, preview) ? { ok : true } : { ok : false, message : 'No dimension made.' };
        },

        cancel : function (ed) {
            if (!this.step) return false;
            this.activate(ed);
            return true;
        },

        draw : function (ed, ctx, view) {
            if (this.step === 1 && this.cur) {
                V.DrawBand(view, ed.settings, this.a, this.cur, null);
                V.DrawLabel(view, this.cur, H.Mm(ed, G.Dist(this.a, this.cur)));
            }
            if (this.a) V.DrawPointMark(view, this.a, ed.settings.Colours.Dimension, 3);
            if (this.b) V.DrawPointMark(view, this.b, ed.settings.Colours.Dimension, 3);
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Measure
    // -------------------------------------------------------------------------

    Tools.Register({
        id : 'measure', label : 'Measure', cursor : 'crosshair',
        a : null, b : null, cur : null, hoverInfo : null,

        activate : function () { this.a = this.b = this.cur = null; this.hoverInfo = null; },
        reset : function () { this.activate(); },
        prompt : function () {
            if (this.a && !this.b) return 'MEASURE: click the second point.';
            return 'MEASURE: click two points for the distance between them, or hover an edge for its length or radius.';
        },
        isPlacing : function () { return !!this.a && !this.b; },

        onMove : function (ed, ev) {
            var anchor = this.a && !this.b ? this.a : null;
            this.cur = ed.Pick(ev, anchor).p;
            this.hoverInfo = null;
            if (!anchor) {
                var hit = ed.HitEntity(ev.world, { noDims : true });
                if (hit) this.hoverInfo = { id : hit.id, text : DescribeEntity(ed, D.Get(ed.doc, hit.id)), at : ev.world };
            }
        },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            if (!this.a || this.b) { this.a = G.Copy(this.cur); this.b = null; return; }
            if (G.Dist(this.a, this.cur) < 1e-9) return;
            this.b = G.Copy(this.cur);
            ed.axisLock = null;
            var d = G.Sub(this.b, this.a);
            ed.Hint('Distance ' + H.Mm(ed, G.Len(d)) + '   across ' + H.Fmt(ed, d.x) + ', up ' + H.Fmt(ed, d.y) + '   at ' + H.Fmt(ed, H.AngleDeg(this.a, this.b)) + '°', false);
        },

        cancel : function () {
            if (!this.a) return false;
            this.activate();
            return true;
        },

        draw : function (ed, ctx, view) {
            var colour = ed.settings.Colours.Measure;
            if (this.hoverInfo && !this.a) {
                var e = D.Get(ed.doc, this.hoverInfo.id);
                if (e) V.DrawPreviewEntity(view, ed.settings, e, 'held');
                V.DrawLabel(view, this.hoverInfo.at, this.hoverInfo.text, colour);
            }
            if (this.a) {
                var end = this.b || this.cur;
                if (!end) return;
                V.DrawBand(view, ed.settings, this.a, end, null);
                var d = G.Sub(end, this.a);
                V.DrawLabel(view, end, H.Mm(ed, G.Len(d)) + '   Δ ' + H.Fmt(ed, d.x) + ', ' + H.Fmt(ed, d.y) + '   ' + H.Fmt(ed, H.AngleDeg(this.a, end)) + '°', colour);
                V.DrawPointMark(view, this.a, colour, 3);
                if (this.b) V.DrawPointMark(view, this.b, colour, 3);
            }
        }
    });

    function DescribeEntity(ed, e) {
        if (!e) return '';
        if (e.type === 'line') return 'Line ' + H.Mm(ed, G.Length(e)) + ' at ' + H.Fmt(ed, H.AngleDeg(e.a, e.b)) + '°';
        if (e.type === 'circle') return 'Circle R ' + H.Mm(ed, e.r) + ' (Ø ' + H.Fmt(ed, e.r * 2) + '), ' + G.EntitySegments(e, ed.settings.Curves) + ' segs';
        var g = G.ArcGeom(e);
        return 'Arc R ' + H.Mm(ed, g.r) + ', ' + H.Fmt(ed, G.ToDeg(Math.abs(g.sw))) + '°, length ' + H.Mm(ed, G.Length(e)) + ', ' + G.EntitySegments(e, ed.settings.Curves) + ' segs';
    }
    H.DescribeEntity = DescribeEntity;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Set Datum
    // -------------------------------------------------------------------------

    Tools.Register({
        id : 'origin', label : 'Set Datum', cursor : 'crosshair',
        cur : null,

        prompt : function () { return 'SET DATUM: click the point that becomes 0,0 - the insertion point the profile sweeps along the path from. Or type its current Y,Z.'; },
        vcbLabel : function () { return 'Datum Y,Z'; },

        onMove : function (ed, ev) { this.cur = ed.Pick(ev, null).p; },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            this.Move(ed, this.cur);
        },

        Move : function (ed, p) {
            if (Math.abs(p.x) < 1e-9 && Math.abs(p.y) < 1e-9) { ed.Hint('That point is already the datum.'); return; }
            var shift = { x : -p.x, y : -p.y };
            ed.Commit('Set datum', function (doc) {
                var keys = new Set();
                D.VertexIndex(doc).forEach(function (v) { keys.add(v.key); });
                D.Translate(doc, keys, shift);
                doc.dims.forEach(function (d) {
                    if (!d.ka) d.a = G.Add(d.a, shift);
                    if (!d.kb) d.b = G.Add(d.b, shift);
                });
                return { ok : true };
            });
            ed.ZoomExtents(true);
            ed.Hint('Datum moved: the drawing shifted ' + H.Fmt(ed, shift.x) + ' across, ' + H.Fmt(ed, shift.y) + ' up.');
            ed.SetTool('select');
        },

        onVcb : function (ed, text, parsed) {
            var at = H.ResolvePoint(ed, parsed, null, null);
            if (!at.ok) return at;
            this.Move(ed, at.p);
            return { ok : true };
        },

        draw : function (ed, ctx, view) {
            if (this.cur) V.DrawLabel(view, this.cur, 'New 0,0  (now Y ' + H.Fmt(ed, this.cur.x) + ', Z ' + H.Fmt(ed, this.cur.y) + ')', ed.settings.Colours.Datum);
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Tools = Tools;

    // endregion ----------------------------------------------------------------
})();
