/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - TOOLS - MODIFY
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Tools__Modify__.js
   NAMESPACE  : window.Na__DrawProfile__Tools  (adds to the registry)
   PURPOSE    : The tools that change what is drawn: Move / Copy (with
                SketchUp's 3x and /3 arrays), Rotate, Mirror, Scale, Offset,
                Trim, Extend, Corner, Fillet, Chamfer and Split. The maths is
                Na__DrawProfile__Ops; these pick, preview and commit.

   @delegate  : TrueVision Layout Editor
                30__System__SheetTools   CopyDrag (Ctrl copies, 3x / /3)
                37__System__VectorTools  TrimTool (Shift swaps Trim and Extend,
                                         fence trim), OffsetTool (side from
                                         the cursor), FilletTool (click a
                                         corner, or the two edges)
                Preview colours          remove #d93025, add #1a73e8, dashed
   ============================================================================= */

(function () {
    'use strict';

    var G   = window.Na__DrawProfile__Geom;
    var D   = window.Na__DrawProfile__Doc;
    var V   = window.Na__DrawProfile__View;
    var Ops = window.Na__DrawProfile__Ops;
    var Tools = window.Na__DrawProfile__Tools;
    var H = Tools.H;

    // -------------------------------------------------------------------------
    // REGION | Shared: a Selection to Work On
    // -------------------------------------------------------------------------

    // The modify tools work on the selection. With nothing selected, the first
    // click picks the edge under the cursor (as SketchUp's Move does).
    function EnsureSelection(ed, ev) {
        if (ed.HasMovableSelection()) return true;
        var hit = ed.HitEntity(ev.world);
        if (!hit) { ed.Hint('Select what to work on first: click it, or drag a box with Select (V).', true); return false; }
        ed.SetSelection([ hit.id ]);
        return true;
    }

    function SelectedEntityIds(ed) {
        return Array.from(ed.selection).filter(function (id) { return !!D.Get(ed.doc, id); });
    }

    function DrawPreview(ed, view, preview) {
        if (!preview) return;
        (preview.remove || []).forEach(function (e) { V.DrawPreviewEntity(view, ed.settings, e, 'remove'); });
        (preview.add || []).forEach(function (e) { V.DrawPreviewEntity(view, ed.settings, e, 'add'); });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Transform Tools (Move, Rotate, Mirror, Scale)
    // -------------------------------------------------------------------------

    // Applies a point map to the selection, as a move or as a copy, in `doc`.
    function ApplyTransform(ed, doc, fn, options) {
        var opts = options || {};
        if (opts.copy && !ed.vertexMode) {
            return D.CopyEntities(doc, SelectedEntityIds(ed), fn, { flips : opts.flips, scale : opts.scale });
        }
        var keys = ed.SelectionKeys();
        D.TransformLocations(doc, keys, fn, { flips : opts.flips, scale : opts.scale });
        if (!ed.vertexMode) {
            doc.dims.forEach(function (d) {
                if (!ed.selection.has(d.id)) return;
                if (!d.ka || !keys.has(d.ka)) d.a = fn(d.a);
                if (!d.kb || !keys.has(d.kb)) d.b = fn(d.b);
            });
        }
        return null;
    }

    // The snap exclusion while a transform previews: what it moves or
    // stretches (nothing for a copy, whose original stays where it is). The
    // preview snaps to the drawing as it was (BeginTransient snapBase).
    function MovingExclusion(ed, copying) {
        if (copying) return null;
        var keys = ed.SelectionKeys();
        return { exclude : ed.MovingIds(keys, ed.vertexMode ? null : ed.selection), excludeKeys : keys };
    }

    function CopyNote(ed, copy) {
        if (ed.vertexMode) return '';
        return copy ? ' (copy: Ctrl to move instead)' : ' (Ctrl to copy)';
    }

    // ---- Move / Copy ------------------------------------------------------

    Tools.Register({
        id : 'move', label : 'Move', cursor : 'crosshair',
        step : 0, base : null, cur : null, lock : null, copy : false, lastCopy : null,

        activate : function () { this.step = 0; this.base = null; this.cur = null; this.copy = false; this.lastCopy = null; },
        reset : function (ed) { if (this.step === 1) ed.EndTransient(false); this.step = 0; this.base = null; },
        deactivate : function (ed) { if (this.step === 1) ed.EndTransient(false); this.step = 0; },

        prompt : function (ed) {
            if (this.step === 0) {
                var lead = ed.HasMovableSelection() ? 'MOVE: click the point to move from' : 'MOVE: click an edge to move (or select first), at the point to move from';
                return lead + CopyNote(ed, this.copy) + (this.lastCopy ? '. Type 3x for more copies, or /3 to divide the distance.' : '.');
            }
            return 'MOVE: click where it goes, or type a distance along the band, across,up, or [Y,Z]' + CopyNote(ed, this.copy) + '. Arrows lock an axis.';
        },
        vcbLabel : function () { return this.step === 1 ? 'Distance' : (this.lastCopy ? 'Array' : ''); },
        vcbReading : function (ed) { return this.step === 1 && this.cur ? H.Fmt(ed, G.Dist(this.base, this.cur)) : ''; },
        isPlacing : function () { return this.step === 1; },

        onModifier : function (ed, key) {
            if (key !== 'Control' || ed.vertexMode) return;
            this.copy = !this.copy;
            ed.Hint(this.copy ? 'Copy: the original stays.' : 'Move.');
            if (this.step === 1) this.Update(ed);
        },

        onMove : function (ed, ev) {
            if (this.step === 0) { this.cur = ed.Pick(ev, null).p; return; }
            var pick = ed.Pick(ev, this.base, MovingExclusion(ed, this.copy && !ed.vertexMode));
            this.cur = pick.p;
            this.lock = pick.lock;
            this.Update(ed);
        },

        Update : function (ed) {
            var delta = G.Sub(this.cur, this.base);
            var copy = this.copy;
            ed.UpdateTransient(function (doc) {
                ApplyTransform(ed, doc, function (p) { return { x : p.x + delta.x, y : p.y + delta.y }; }, { copy : copy });
            });
        },

        onDown : function (ed, ev) {
            if (this.step === 0) {
                if (!EnsureSelection(ed, ev)) return;
                this.base = ed.Pick(ev, null).p;
                this.cur = G.Copy(this.base);
                this.step = 1;
                this.lastCopy = null;
                ed.BeginTransient({ snapBase : true });
                return;
            }
            this.onMove(ed, ev);
            this.Finish(ed, G.Sub(this.cur, this.base));
        },

        Finish : function (ed, delta) {
            var copy = this.copy && !ed.vertexMode;
            var made = null;
            // Picked vertices re-keyed before the commit, which drops picks
            // whose location has gone.
            var movedKeys = ed.vertexMode ? window.Na__DrawProfile__Editor.ShiftKeys(ed.vsel, delta) : null;
            ed.UpdateTransient(function (doc) {
                made = ApplyTransform(ed, doc, function (p) { return { x : p.x + delta.x, y : p.y + delta.y }; }, { copy : copy });
            });
            ed.EndTransient(true, copy ? 'Copy' : 'Move');
            if (copy && made) {
                this.lastCopy = { ids : SelectedEntityIds(ed), delta : delta };
                ed.SetSelection(made);
            } else if (movedKeys) {
                ed.vsel = movedKeys;
                ed.RefreshGrips();
                ed.Emit('onSelectionChanged');
            }
            ed.Hint((copy ? 'Copied ' : 'Moved ') + H.Mm(ed, G.Len(delta)) + ' (' + H.Fmt(ed, delta.x) + ' across, ' + H.Fmt(ed, delta.y) + ' up).');
            this.step = 0;
            ed.axisLock = null;
        },

        onVcb : function (ed, text, parsed) {
            if (this.step === 0) {
                if (this.lastCopy && parsed.ok && parsed.type === 'array') return this.Array(ed, parsed);
                return { ok : false, message : 'Click the point to move from first.' };
            }
            var resolved = H.ResolvePoint(ed, parsed, this.base, this.cur);
            if (!resolved.ok) return resolved;
            this.cur = resolved.p;
            this.Finish(ed, G.Sub(resolved.p, this.base));
            return { ok : true };
        },

        // SketchUp's array, typed straight after a copy (TV CopyDrag).
        Array : function (ed, parsed) {
            var last = this.lastCopy;
            var max = ed.settings.Defaults.ArrayMax;
            if (parsed.count > max) return { ok : false, message : 'At most ' + max + ' copies.' };
            var deltas = [];
            if (parsed.mode === 'times') { for (var k = 2; k <= parsed.count; k++) deltas.push(G.Mul(last.delta, k)); }
            else { for (var j = 1; j < parsed.count; j++) deltas.push(G.Mul(last.delta, j / parsed.count)); }
            if (!deltas.length) return { ok : true, message : 'Nothing more to copy.' };
            ed.Commit('Array', function (doc) {
                deltas.forEach(function (d) { D.CopyEntities(doc, last.ids, function (p) { return { x : p.x + d.x, y : p.y + d.y }; }); });
                return { ok : true };
            });
            this.lastCopy = null;
            return { ok : true, message : parsed.mode === 'times' ? parsed.count + ' copies in all.' : 'Distance divided into ' + parsed.count + '.' };
        },

        cancel : function (ed) {
            if (this.step !== 1) return false;
            ed.EndTransient(false);
            this.step = 0;
            return true;
        },

        draw : function (ed, ctx, view) {
            if (this.step !== 1 || !this.cur) return;
            V.DrawBand(view, ed.settings, this.base, this.cur, this.lock);
            V.DrawPointMark(view, this.base, '#e01b24', 3);
            var d = G.Sub(this.cur, this.base);
            V.DrawLabel(view, this.cur, H.Mm(ed, G.Len(d)) + '   Δ ' + H.Fmt(ed, d.x) + ', ' + H.Fmt(ed, d.y));
        }
    });

    // ---- Rotate -----------------------------------------------------------

    Tools.Register({
        id : 'rotate', label : 'Rotate', cursor : 'crosshair',
        step : 0, c : null, ref : null, cur : null, angle : 0, copy : false,

        activate : function () { this.step = 0; this.c = this.ref = this.cur = null; this.angle = 0; this.copy = false; },
        reset : function (ed) { if (this.step === 2) ed.EndTransient(false); this.activate(); },
        deactivate : function (ed) { if (this.step === 2) ed.EndTransient(false); this.step = 0; },

        prompt : function (ed) {
            return [ 'ROTATE: click the centre to turn about' + CopyNote(ed, this.copy) + '.',
                     'ROTATE: click a point on the line to turn from, or type the angle (degrees, anticlockwise).',
                     'ROTATE: turn to the new angle and click, or type it (Shift / Ortho steps 15°).' ][this.step];
        },
        vcbLabel : function () { return this.step >= 1 ? 'Angle' : ''; },
        vcbReading : function (ed) { return this.step === 2 ? H.Fmt(ed, G.ToDeg(this.angle)) : ''; },

        onModifier : function (ed, key) {
            if (key !== 'Control' || ed.vertexMode) return;
            this.copy = !this.copy;
            ed.Hint(this.copy ? 'Copy: the original stays.' : 'Rotate in place.');
            if (this.step === 2) this.Update(ed);
        },

        onMove : function (ed, ev) {
            if (this.step < 2) { this.cur = ed.Pick(ev, this.step === 1 ? this.c : null).p; return; }
            this.cur = ed.Pick(ev, null, MovingExclusion(ed, this.copy && !ed.vertexMode)).p;
            var a0 = Math.atan2(this.ref.y - this.c.y, this.ref.x - this.c.x);
            var a1 = Math.atan2(this.cur.y - this.c.y, this.cur.x - this.c.x);
            var angle = a1 - a0;
            while (angle > Math.PI) angle -= G.TAU;
            while (angle < -Math.PI) angle += G.TAU;
            if (!!ed.settings.Ortho !== !!ev.shift) angle = G.ToRad(Math.round(G.ToDeg(angle) / 15) * 15);
            this.angle = angle;
            this.Update(ed);
        },

        Update : function (ed) {
            var c = this.c, angle = this.angle, copy = this.copy;
            ed.UpdateTransient(function (doc) {
                ApplyTransform(ed, doc, function (p) { return G.Rotate(p, c, angle); }, { copy : copy });
            });
        },

        onDown : function (ed, ev) {
            if (this.step === 0) {
                if (!EnsureSelection(ed, ev)) return;
                this.c = ed.Pick(ev, null).p;
                this.step = 1;
                return;
            }
            if (this.step === 1) {
                var p = ed.Pick(ev, this.c).p;
                if (G.Dist(p, this.c) < 1e-6) return;
                this.ref = p;
                this.step = 2;
                ed.axisLock = null;
                ed.BeginTransient({ snapBase : true });
                return;
            }
            this.onMove(ed, ev);
            this.Finish(ed);
        },

        Finish : function (ed) {
            var made = null;
            var c = this.c, angle = this.angle, copy = this.copy && !ed.vertexMode;
            ed.UpdateTransient(function (doc) { made = ApplyTransform(ed, doc, function (p) { return G.Rotate(p, c, angle); }, { copy : copy }); });
            ed.EndTransient(true, copy ? 'Rotate copy' : 'Rotate');
            if (made) ed.SetSelection(made);
            ed.Hint((copy ? 'Rotated a copy ' : 'Rotated ') + H.Fmt(ed, G.ToDeg(angle)) + '°.');
            this.activate();
        },

        onVcb : function (ed, text, parsed) {
            if (this.step === 0) return { ok : false, message : 'Click the centre first.' };
            var deg = parsed.ok ? (parsed.type === 'angle' ? parsed.deg : (parsed.type === 'length' ? parsed.valueMm : null)) : null;
            if (deg === null) return { ok : false, message : 'Type the angle in degrees, anticlockwise positive (e.g. 90 or -45).' };
            if (this.step === 1) ed.BeginTransient({ snapBase : true });
            this.step = 2;
            this.ref = this.ref || { x : this.c.x + 1, y : this.c.y };
            this.angle = G.ToRad(deg);
            this.Finish(ed);
            return { ok : true };
        },

        cancel : function (ed) {
            if (!this.step) return false;
            if (this.step === 2) ed.EndTransient(false);
            this.activate();
            return true;
        },

        draw : function (ed, ctx, view) {
            if (this.step >= 1 && this.cur) {
                V.DrawPointMark(view, this.c, '#e01b24', 3);
                V.DrawBand(view, ed.settings, this.c, this.step === 2 ? this.ref : this.cur, null);
            }
            if (this.step === 2 && this.cur) {
                V.DrawBand(view, ed.settings, this.c, this.cur, null);
                V.DrawLabel(view, this.cur, H.Fmt(ed, G.ToDeg(this.angle)) + '°');
            }
        }
    });

    // ---- Mirror -----------------------------------------------------------

    Tools.Register({
        id : 'mirror', label : 'Mirror', cursor : 'crosshair',
        step : 0, a : null, cur : null, lock : null, keep : true,

        activate : function () { this.step = 0; this.a = null; this.cur = null; this.keep = true; },
        reset : function (ed) { if (this.step === 1) ed.EndTransient(false); this.step = 0; this.a = null; },
        deactivate : function (ed) { if (this.step === 1) ed.EndTransient(false); this.step = 0; },

        prompt : function (ed) {
            var keepNote = ed.vertexMode ? '' : (this.keep ? ' The original stays (Ctrl: flip it instead).' : ' The original is flipped (Ctrl: keep it).');
            return (this.step === 0 ? 'MIRROR: click the first point of the mirror line.' : 'MIRROR: click the second point of the mirror line (Shift / Ortho / arrows hold it level or plumb).') + keepNote;
        },
        isPlacing : function () { return this.step === 1; },

        onModifier : function (ed, key) {
            if (key !== 'Control' || ed.vertexMode) return;
            this.keep = !this.keep;
            ed.Hint(this.keep ? 'Mirror copy: the original stays.' : 'Mirror in place: the original is flipped.');
            if (this.step === 1) this.Update(ed);
        },

        onMove : function (ed, ev) {
            var pick = ed.Pick(ev, this.step === 1 ? this.a : null);
            this.cur = pick.p;
            this.lock = pick.lock;
            if (this.step === 1) this.Update(ed);
        },

        Update : function (ed) {
            if (G.Dist(this.a, this.cur) < 1e-9) { ed.UpdateTransient(function () {}); return; }
            var a = this.a, b = this.cur, keep = this.keep && !ed.vertexMode;
            ed.UpdateTransient(function (doc) {
                ApplyTransform(ed, doc, function (p) { return G.MirrorPoint(p, a, b); }, { copy : keep, flips : true });
            });
        },

        onDown : function (ed, ev) {
            if (this.step === 0) {
                if (!EnsureSelection(ed, ev)) return;
                this.a = ed.Pick(ev, null).p;
                this.cur = G.Copy(this.a);
                this.step = 1;
                ed.BeginTransient({ snapBase : true });
                return;
            }
            this.onMove(ed, ev);
            if (G.Dist(this.a, this.cur) < 1e-9) return;
            var made = null;
            var a = this.a, b = this.cur, keep = this.keep && !ed.vertexMode;
            ed.UpdateTransient(function (doc) { made = ApplyTransform(ed, doc, function (p) { return G.MirrorPoint(p, a, b); }, { copy : keep, flips : true }); });
            ed.EndTransient(true, keep ? 'Mirror copy' : 'Mirror');
            if (made) ed.SetSelection(made);
            ed.Hint(keep ? 'Mirrored copy made. Ends that land on the originals join them.' : 'Mirrored.');
            this.step = 0;
            ed.axisLock = null;
        },

        cancel : function (ed) {
            if (this.step !== 1) return false;
            ed.EndTransient(false);
            this.step = 0;
            return true;
        },

        draw : function (ed, ctx, view) {
            if (this.step === 1 && this.cur) {
                V.DrawBand(view, ed.settings, this.a, this.cur, this.lock || 'mirror');
            }
        }
    });

    // ---- Scale ------------------------------------------------------------

    Tools.Register({
        id : 'scale', label : 'Scale', cursor : 'crosshair',
        step : 0, base : null, ref : null, cur : null, factor : 1,

        activate : function () { this.step = 0; this.base = this.ref = this.cur = null; this.factor = 1; },
        reset : function (ed) { if (this.step === 2) ed.EndTransient(false); this.activate(); },
        deactivate : function (ed) { if (this.step === 2) ed.EndTransient(false); this.step = 0; },

        prompt : function () {
            return [ 'SCALE: click the point that stays put.', 'SCALE: click a reference point (its distance from the base is 1), or type the factor.',
                     'SCALE: move to set the new size and click, or type a factor (1.2) or the new length of the reference (120mm).' ][this.step];
        },
        vcbLabel : function () { return this.step >= 1 ? 'Factor' : ''; },
        vcbReading : function (ed) { return this.step === 2 ? H.Fmt(ed, this.factor) : ''; },

        onMove : function (ed, ev) {
            this.cur = ed.Pick(ev, this.step === 1 ? this.base : null, this.step === 2 ? MovingExclusion(ed, false) : null).p;
            if (this.step !== 2) return;
            var d0 = G.Dist(this.base, this.ref), d1 = G.Dist(this.base, this.cur);
            this.factor = d0 > 0 ? d1 / d0 : 1;
            this.Update(ed);
        },

        Update : function (ed) {
            var base = this.base, k = this.factor;
            if (!(k > 1e-6)) return;
            ed.UpdateTransient(function (doc) { ApplyTransform(ed, doc, function (p) { return G.ScaleAbout(p, base, k); }, { scale : k }); });
        },

        onDown : function (ed, ev) {
            if (this.step === 0) {
                if (!EnsureSelection(ed, ev)) return;
                this.base = ed.Pick(ev, null).p;
                this.step = 1;
                return;
            }
            if (this.step === 1) {
                var p = ed.Pick(ev, this.base).p;
                if (G.Dist(p, this.base) < 1e-6) return;
                this.ref = p;
                this.step = 2;
                ed.axisLock = null;
                ed.BeginTransient({ snapBase : true });
                return;
            }
            this.onMove(ed, ev);
            this.Finish(ed);
        },

        Finish : function (ed) {
            if (!(this.factor > 1e-6)) { ed.Hint('A scale factor has to be above nothing.', true); return; }
            this.Update(ed);
            ed.EndTransient(true, 'Scale');
            ed.Hint('Scaled x' + H.Fmt(ed, this.factor) + '.');
            this.activate();
        },

        onVcb : function (ed, text, parsed) {
            if (this.step === 0) return { ok : false, message : 'Click the point that stays put first.' };
            var factor = null;
            if (parsed.ok && parsed.type === 'length') {
                var unitTyped = /[a-z]$/i.test(text.trim());
                if (unitTyped && this.ref) factor = parsed.valueMm / G.Dist(this.base, this.ref);
                else if (unitTyped) return { ok : false, message : 'Click a reference point before typing a new length for it.' };
                else factor = parsed.valueMm;
            }
            if (!(factor > 1e-6)) return { ok : false, message : 'Type a factor above nothing (e.g. 1.2), or the reference\'s new length with its unit (120mm).' };
            if (this.step === 1) { this.ref = { x : this.base.x + 1, y : this.base.y }; ed.BeginTransient({ snapBase : true }); }
            this.step = 2;
            this.factor = factor;
            this.Finish(ed);
            return { ok : true };
        },

        cancel : function (ed) {
            if (!this.step) return false;
            if (this.step === 2) ed.EndTransient(false);
            this.activate();
            return true;
        },

        draw : function (ed, ctx, view) {
            if (this.step >= 1) V.DrawPointMark(view, this.base, '#e01b24', 3);
            if (this.step === 1 && this.cur) V.DrawBand(view, ed.settings, this.base, this.cur, null);
            if (this.step === 2 && this.cur) {
                V.DrawBand(view, ed.settings, this.base, this.cur, null);
                V.DrawLabel(view, this.cur, 'x' + H.Fmt(ed, this.factor));
            }
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Offset (TV OffsetTool: the whole chain, side from the cursor)
    // -------------------------------------------------------------------------

    Tools.Register({
        id : 'offset', label : 'Offset', cursor : 'crosshair',
        sourceId : null, chain : null, preview : null, distance : 0, hoverId : null,

        activate : function () { this.sourceId = null; this.chain = null; this.preview = null; this.hoverId = null; },
        reset : function () { this.activate(); },

        Fixed : function (ed) { return ed.Memory('offset').fixed || 0; },

        prompt : function (ed) {
            var fixed = this.Fixed(ed);
            var how = fixed ? 'Distance ' + H.Mm(ed, fixed) + ' (typed; type 0 to follow the cursor).' : 'Distance follows the cursor; type one to fix it.';
            return this.sourceId ? 'OFFSET: click the side to offset to. ' + how : 'OFFSET: click the edge whose run you want a parallel copy of. ' + how;
        },
        vcbLabel : function () { return 'Distance'; },
        vcbReading : function (ed) { return this.sourceId ? H.Fmt(ed, this.distance) : (this.Fixed(ed) ? H.Fmt(ed, this.Fixed(ed)) : ''); },

        onMove : function (ed, ev) {
            ed.snapShown = null;
            if (!this.sourceId) {
                var hit = ed.HitEntity(ev.world, { noDims : true });
                this.hoverId = hit ? hit.id : null;
                ed.hoverId = this.hoverId;
                return;
            }
            this.UpdatePreview(ed, ev.world);
        },

        UpdatePreview : function (ed, world) {
            var side = Ops.SideOf(this.chain, world);
            var dist = this.Fixed(ed) || side.distance;
            if (!this.Fixed(ed) && ed.settings.Grid.Snap) {
                var step = window.Na__DrawProfile__Snap.GridStep(ed.settings.Grid);
                dist = Math.max(step, Math.round(dist / step) * step);
            }
            this.distance = dist;
            this.sign = side.sign;
            var result = Ops.OffsetChain(ed.doc, this.sourceId, dist * side.sign, { dryRun : true });
            this.preview = result.ok ? result.preview : null;
            this.message = result.ok ? '' : result.message;
        },

        onDown : function (ed, ev) {
            if (!this.sourceId) {
                var hit = ed.HitEntity(ev.world, { noDims : true });
                if (!hit) { ed.Hint('Click an edge to offset.', true); return; }
                this.sourceId = hit.id;
                this.chain = Ops.OrientedChain(ed.doc, hit.id);
                ed.SetSelection(D.ChainOf(ed.doc, hit.id));
                this.UpdatePreview(ed, ev.world);
                return;
            }
            this.UpdatePreview(ed, ev.world);
            this.Apply(ed, this.distance * this.sign);
        },

        Apply : function (ed, signed) {
            var id = this.sourceId;
            var result = ed.Commit('Offset', function (doc) { return Ops.OffsetChain(doc, id, signed, {}); });
            if (!result.ok) { ed.Hint(result.message || 'No offset made.', true); return false; }
            ed.Hint(result.message);
            if (result.ids) ed.SetSelection(result.ids);
            this.activate();
            return true;
        },

        onVcb : function (ed, text, parsed) {
            if (!parsed.ok || parsed.type !== 'length') return { ok : false, message : 'Type the offset distance, e.g. 3.' };
            var dist = Math.abs(parsed.valueMm);
            ed.Memory('offset').fixed = dist;
            if (!dist) return { ok : true, message : 'Offset distance follows the cursor again.' };
            if (this.sourceId) {
                return this.Apply(ed, dist * (this.sign || 1)) ? { ok : true } : { ok : false, message : this.message || 'No offset made.' };
            }
            return { ok : true, message : 'Offset distance ' + H.Mm(ed, dist) + '. Click the edge, then the side.' };
        },

        cancel : function () {
            if (!this.sourceId) return false;
            this.activate();
            return true;
        },

        draw : function (ed, ctx, view) {
            if (this.sourceId && this.chain) this.chain.list.forEach(function (e) { V.DrawPreviewEntity(view, ed.settings, e, 'held'); });
            DrawPreview(ed, view, this.preview);
            if (this.sourceId && ed.cursorWorld) {
                V.DrawLabel(view, ed.cursorWorld, this.preview ? H.Mm(ed, this.distance) : (this.message || ''), this.preview ? '#1f2937' : ed.settings.Colours.IssueError);
            }
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Trim + Extend (TV TrimTool: Shift swaps, fence on bare paper)
    // -------------------------------------------------------------------------

    function MakeTrimExtend(id, label, isTrim) {
        return Tools.Register({
            id : id, label : label, cursor : 'crosshair',
            preview : null, fence : null, cur : null, message : '',

            activate : function () { this.preview = null; this.fence = null; this.message = ''; },
            reset : function () { this.activate(); },

            Mode : function (ev) { return (!!ev.shift) !== isTrim ? 'trim' : 'extend'; },

            prompt : function () {
                if (this.fence) return 'TRIM (fence): click the end of the fence; every edge it crosses loses that span.';
                return isTrim
                    ? 'TRIM: click the part of an edge to cut away, back to where it crosses others. Click bare paper to draw a fence. Shift: Extend.'
                    : 'EXTEND: click near the end of an edge to run it on to the next edge it meets. Shift: Trim.';
            },
            isPlacing : function () { return !!this.fence; },

            onMove : function (ed, ev) {
                ed.snapShown = null;
                this.cur = ev.world;
                this.preview = null;
                this.message = '';
                if (this.fence) {
                    var fence = Ops.TrimFence(ed.doc, this.fence, ev.world, { dryRun : true });
                    this.preview = fence.ok ? fence.preview : null;
                    return;
                }
                var hit = ed.HitEntity(ev.world, { noDims : true });
                ed.hoverId = hit ? hit.id : null;
                if (!hit) return;
                var result = this.Mode(ev) === 'trim'
                    ? Ops.Trim(ed.doc, hit.id, ev.world, { dryRun : true })
                    : Ops.Extend(ed.doc, hit.id, ev.world, ed.settings.Tol.ExtendMaxMm, { dryRun : true });
                if (result.ok) this.preview = result.preview; else this.message = result.message;
            },

            onDown : function (ed, ev) {
                if (this.fence) {
                    var start = this.fence;
                    this.fence = null;
                    var fenced = ed.Commit('Fence trim', function (doc) { return Ops.TrimFence(doc, start, ev.world, {}); });
                    ed.Hint(fenced.message || '', !fenced.ok);
                    return;
                }
                var hit = ed.HitEntity(ev.world, { noDims : true });
                var mode = this.Mode(ev);
                if (!hit) {
                    if (mode === 'trim') { this.fence = G.Copy(ev.world); ed.Hint('Fence started: click its other end.'); }
                    return;
                }
                var maxMm = ed.settings.Tol.ExtendMaxMm;
                var result = ed.Commit(mode === 'trim' ? 'Trim' : 'Extend', function (doc) {
                    return mode === 'trim' ? Ops.Trim(doc, hit.id, ev.world, {}) : Ops.Extend(doc, hit.id, ev.world, maxMm, {});
                });
                ed.Hint(result.message || '', !result.ok);
                this.onMove(ed, ev);
            },

            cancel : function () {
                if (!this.fence) return false;
                this.fence = null;
                return true;
            },

            draw : function (ed, ctx, view) {
                if (this.fence && this.cur) {
                    var s = V.W2S(view, this.fence), t = V.W2S(view, this.cur);
                    ctx.save();
                    ctx.strokeStyle = ed.settings.Colours.PreviewFence;
                    ctx.lineWidth = 2;
                    ctx.setLineDash([ 6, 4 ]);
                    ctx.beginPath(); ctx.moveTo(s.x, s.y); ctx.lineTo(t.x, t.y); ctx.stroke();
                    ctx.restore();
                }
                DrawPreview(ed, view, this.preview);
                if (this.message && this.cur) V.DrawLabel(view, this.cur, this.message, ed.settings.Colours.IssueError);
            }
        });
    }

    MakeTrimExtend('trim', 'Trim', true);
    MakeTrimExtend('extend', 'Extend', false);

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Corner, Fillet, Chamfer (TV FilletTool: a corner, or two edges)
    // -------------------------------------------------------------------------

    // kind 'corner' | 'fillet' | 'chamfer'.
    function MakeCornerTool(id, label, kind) {
        return Tools.Register({
            id : id, label : label, cursor : 'crosshair',
            first : null, preview : null, cornerKey : null, message : '', cur : null,

            activate : function () { this.first = null; this.preview = null; this.cornerKey = null; this.message = ''; },
            reset : function () { this.activate(); },

            Size : function (ed) {
                var mem = ed.Memory(id);
                if (kind === 'fillet') return { r : mem.r !== undefined ? mem.r : ed.settings.Defaults.FilletMm, segs : mem.segs || 0 };
                if (kind === 'chamfer') return { d1 : mem.d1 !== undefined ? mem.d1 : ed.settings.Defaults.ChamferMm, d2 : mem.d2 };
                return {};
            },

            SizeText : function (ed) {
                var size = this.Size(ed);
                if (kind === 'fillet') return 'radius ' + H.Mm(ed, size.r) + ', ' + (size.segs ? size.segs + ' segs' : 'auto segs');
                if (kind === 'chamfer') return H.Fmt(ed, size.d1) + (Number.isFinite(size.d2) ? ' x ' + H.Fmt(ed, size.d2) : '') + ' mm';
                return '';
            },

            prompt : function (ed) {
                var title = label.toUpperCase();
                var size = kind === 'corner' ? '' : ' (' + this.SizeText(ed) + '; type to change' + (kind === 'fillet' ? ', Ns for segments' : ', d1,d2 for unequal') + ')';
                if (this.first) return title + ': click the second edge, on the side to keep.' + size;
                if (kind === 'corner') return 'CORNER: click two edges, each on the side to keep; they run to where they meet.';
                return title + ': click a corner, or two edges on the sides to keep.' + size;
            },
            vcbLabel : function () { return kind === 'fillet' ? 'Radius' : (kind === 'chamfer' ? 'Distance' : ''); },
            vcbReading : function (ed) {
                var size = this.Size(ed);
                if (kind === 'fillet') return H.Fmt(ed, size.r);
                if (kind === 'chamfer') return H.Fmt(ed, size.d1) + (Number.isFinite(size.d2) ? ',' + H.Fmt(ed, size.d2) : '');
                return '';
            },

            Run : function (ed, doc, target, options) {
                var size = this.Size(ed);
                if (target.key) {
                    if (kind === 'fillet') return Ops.FilletAt(doc, target.key, size.r, size.segs, options);
                    if (kind === 'chamfer') return Ops.ChamferAt(doc, target.key, size.d1, size.d2, options);
                    return { ok : false, message : 'Those edges already meet there.' };
                }
                if (kind === 'fillet') return Ops.FilletPair(doc, target.id1, target.p1, target.id2, target.p2, size.r, size.segs, options);
                if (kind === 'chamfer') return Ops.ChamferPair(doc, target.id1, target.p1, target.id2, target.p2, size.d1, size.d2, options);
                return Ops.Corner(doc, target.id1, target.p1, target.id2, target.p2, options);
            },

            // What a click here would do: a corner vertex (fillet / chamfer),
            // or the second of two edges.
            Target : function (ed, ev) {
                if (!this.first && kind !== 'corner') {
                    var v = ed.HitVertex(ev.world, { px : ed.settings.Tol.GripPx + 4 });
                    if (v && v.degree === 2) return { key : v.key, p : v.p };
                }
                var hit = ed.HitEntity(ev.world, { noDims : true, exclude : this.first ? new Set([ this.first.id ]) : null });
                if (!hit) return null;
                if (!this.first) return { pickFirst : true, id : hit.id, p : ev.world };
                return { id1 : this.first.id, p1 : this.first.p, id2 : hit.id, p2 : ev.world };
            },

            onMove : function (ed, ev) {
                ed.snapShown = null;
                this.cur = ev.world;
                this.preview = null;
                this.cornerKey = null;
                this.message = '';
                var target = this.Target(ed, ev);
                ed.hoverId = target && target.id ? target.id : (target && target.id2 ? target.id2 : null);
                if (!target || target.pickFirst) return;
                if (target.key) this.cornerKey = target.key;
                var result = this.Run(ed, ed.doc, target, { dryRun : true });
                if (result.ok) this.preview = result.preview; else this.message = result.message;
            },

            onDown : function (ed, ev) {
                var target = this.Target(ed, ev);
                if (!target) { ed.Hint(kind === 'corner' ? 'Click an edge.' : 'Click a corner, or an edge.', true); return; }
                if (target.pickFirst) {
                    this.first = { id : target.id, p : target.p };
                    ed.SetSelection([ target.id ]);
                    return;
                }
                var self = this;
                var result = ed.Commit(label, function (doc) { return self.Run(ed, doc, target, {}); });
                ed.Hint(result.message || '', !result.ok);
                this.first = null;
                ed.ClearSelection();
                this.onMove(ed, ev);
            },

            onVcb : function (ed, text, parsed) {
                var mem = ed.Memory(id);
                if (kind === 'corner') return { ok : false, message : 'Corner takes no value: click two edges.' };
                if (kind === 'fillet') {
                    var segs = H.SegmentsTyped(ed, parsed, id);
                    if (segs) return segs;
                    if (!parsed.ok || (parsed.type !== 'length' && parsed.type !== 'radius')) return { ok : false, message : 'Type the fillet radius (e.g. 10), or segments (6s).' };
                    if (parsed.valueMm < 0) return { ok : false, message : 'A radius cannot be negative.' };
                    mem.r = parsed.valueMm;
                    return { ok : true, message : 'Fillet radius ' + H.Mm(ed, mem.r) + (mem.r === 0 ? ' (edges simply meet).' : '.') };
                }
                if (parsed.ok && parsed.type === 'pair') {
                    if (!(parsed.first > 0) || !(parsed.second > 0)) return { ok : false, message : 'Both chamfer distances have to be above nothing.' };
                    mem.d1 = parsed.first; mem.d2 = parsed.second;
                    return { ok : true, message : 'Chamfer ' + H.Fmt(ed, mem.d1) + ' x ' + H.Fmt(ed, mem.d2) + ' mm (first along the edge picked first).' };
                }
                if (!parsed.ok || parsed.type !== 'length' || !(parsed.valueMm > 0)) return { ok : false, message : 'Type the chamfer distance (5) or two (5,10).' };
                mem.d1 = parsed.valueMm; mem.d2 = undefined;
                return { ok : true, message : 'Chamfer ' + H.Mm(ed, mem.d1) + '.' };
            },

            cancel : function (ed) {
                if (!this.first) return false;
                this.first = null;
                ed.ClearSelection();
                return true;
            },

            draw : function (ed, ctx, view) {
                if (this.first) {
                    var e = D.Get(ed.doc, this.first.id);
                    if (e) V.DrawPreviewEntity(view, ed.settings, e, 'held');
                }
                if (this.cornerKey) {
                    var v = D.VertexIndex(ed.doc).get(this.cornerKey);
                    if (v) {
                        var s = V.W2S(view, v.p);
                        ctx.save();
                        ctx.strokeStyle = ed.settings.Colours.PreviewAdd;
                        ctx.lineWidth = 2;
                        ctx.beginPath(); ctx.arc(s.x, s.y, 9, 0, G.TAU); ctx.stroke();
                        ctx.restore();
                    }
                }
                DrawPreview(ed, view, this.preview);
                if (this.message && this.cur) V.DrawLabel(view, this.cur, this.message, ed.settings.Colours.IssueError);
            }
        });
    }

    MakeCornerTool('corner', 'Corner', 'corner');
    MakeCornerTool('fillet', 'Fillet', 'fillet');
    MakeCornerTool('chamfer', 'Chamfer', 'chamfer');

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Split (TV Split: at a crossing, a vertex or the click)
    // -------------------------------------------------------------------------

    Tools.Register({
        id : 'split', label : 'Split', cursor : 'crosshair',
        at : null,

        activate : function () { this.at = null; },
        prompt : function () { return 'SPLIT: click a point on an edge to cut it in two there (at a crossing, every edge through it is cut).'; },

        onMove : function (ed, ev) {
            this.at = null;
            var hit = ed.HitEntity(ev.world, { noDims : true });
            ed.hoverId = hit ? hit.id : null;
            if (!hit) { ed.snapShown = null; return; }
            var e = D.Get(ed.doc, hit.id);
            var snap = ed.SnapAt(ev.world, { noTrack : true });
            var onEdge = snap.snapped && G.Nearest(e, snap.p).d < 1e-6;
            this.at = onEdge ? snap.p : G.Nearest(e, ev.world).p;
            ed.snapShown = onEdge ? snap : { p : this.at, kind : 'near', label : 'Split here', target : 'shape', guides : [] };
        },

        onDown : function (ed, ev) {
            this.onMove(ed, ev);
            if (!this.at) { ed.Hint('Click on an edge.', true); return; }
            var at = this.at;
            var result = ed.Commit('Split', function (doc) { return Ops.SplitThrough(doc, at, {}); });
            ed.Hint(result.message || '', !result.ok);
        },

        draw : function (ed, ctx, view) {
            if (this.at) V.DrawPointMark(view, this.at, ed.settings.Colours.PreviewRemove, 4);
        }
    });

    // endregion ----------------------------------------------------------------
})();
