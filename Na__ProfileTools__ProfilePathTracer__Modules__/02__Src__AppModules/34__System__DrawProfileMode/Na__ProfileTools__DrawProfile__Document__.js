/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - DOCUMENT
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Document__.js
   NAMESPACE  : window.Na__DrawProfile__Doc
   PURPOSE    : What the Draw Profile editor holds, and every change made to it:
                entities and audit dimensions, vertex locations, healing, and
                the snapshot history behind undo and redo.

   THE DOCUMENT
     { ents : [entity + { id, constr, paint }], dims : [dimension],
       vpaint : { location key : colour id }, nextId }
     Entities are those of Na__DrawProfile__Geom. constr marks construction
     geometry: drawn and snapped to, never part of the profile.
     Edge Paint (v1.6.15): an edge's colour rides on the entity (paint), so a
     split, trim, copy or move keeps it; a vertex's is kept by location in
     vpaint and goes where its location goes (TransformLocations, copies,
     healing). A location nothing stands on any more drops its colour.
     A dimension is { id, a, b, ka, kb, off, orient } - two measured points,
     the vertex locations they were taken from (so a dimension follows its
     vertices when they move), a signed offset and 'aligned' | 'horizontal' |
     'vertical'.

   VERTICES ARE LOCATIONS, NOT RECORDS
     Two entities are joined when an end of each sits at the same point - as
     in SketchUp, where edges meeting at a point share a vertex. Healing makes
     ends within a hair of each other exactly equal, so a location can be
     keyed by its coordinates. Moving a location moves every end standing on
     it, which is why moving one edge of a closed profile stretches its
     neighbours instead of tearing the outline open.

   HISTORY
     One snapshot (the whole document as JSON) per committed change, as the
     TrueVision editor's History does; a profile is small enough for that to
     cost nothing.
   ============================================================================= */

(function () {
    'use strict';

    var G = window.Na__DrawProfile__Geom;

    // -------------------------------------------------------------------------
    // REGION | Create / Copy / Serialise
    // -------------------------------------------------------------------------

    function Create() {
        return { ents : [], dims : [], vpaint : {}, nextId : 1 };
    }

    function Serialize(doc) {
        return JSON.stringify({ ents : doc.ents, dims : doc.dims, vpaint : doc.vpaint || {}, nextId : doc.nextId });
    }

    function Deserialize(text) {
        var raw = typeof text === 'string' ? JSON.parse(text) : text;
        var doc = Create();
        if (!raw || typeof raw !== 'object') return doc;
        doc.ents = Array.isArray(raw.ents) ? raw.ents.filter(IsUsableEntity) : [];
        doc.dims = Array.isArray(raw.dims) ? raw.dims.filter(function (d) { return d && IsPoint(d.a) && IsPoint(d.b); }) : [];
        doc.ents.forEach(function (e) { if (typeof e.paint !== 'string' || !e.paint) delete e.paint; });
        if (raw.vpaint && typeof raw.vpaint === 'object') {
            Object.keys(raw.vpaint).forEach(function (key) {
                if (typeof raw.vpaint[key] === 'string' && raw.vpaint[key]) doc.vpaint[key] = raw.vpaint[key];
            });
        }
        doc.nextId = Number.isFinite(raw.nextId) ? raw.nextId : 1;
        var maxId = 0;
        doc.ents.concat(doc.dims).forEach(function (item) {
            var num = parseInt(String(item.id || '').replace(/^\D+/, ''), 10);
            if (Number.isFinite(num) && num > maxId) maxId = num;
        });
        doc.nextId = Math.max(doc.nextId, maxId + 1);
        return doc;
    }

    function IsPoint(p) {
        return !!p && Number.isFinite(p.x) && Number.isFinite(p.y);
    }

    function IsUsableEntity(e) {
        if (!e || typeof e !== 'object') return false;
        if (e.type === 'line') return IsPoint(e.a) && IsPoint(e.b);
        if (e.type === 'arc') return IsPoint(e.a) && IsPoint(e.b) && Number.isFinite(e.sw) && e.sw !== 0;
        if (e.type === 'circle') return IsPoint(e.c) && Number.isFinite(e.r) && e.r > 0;
        return false;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Entities
    // -------------------------------------------------------------------------

    function NewId(doc, prefix) {
        var id = (prefix || 'e') + doc.nextId;
        doc.nextId += 1;
        return id;
    }

    function Add(doc, e) {
        if (!e.id || Get(doc, e.id)) e.id = NewId(doc, 'e');
        if (e.constr !== true) delete e.constr;
        doc.ents.push(e);
        return e.id;
    }

    function Get(doc, id) {
        for (var i = 0; i < doc.ents.length; i++) if (doc.ents[i].id === id) return doc.ents[i];
        return null;
    }

    function IndexOf(doc, id) {
        for (var i = 0; i < doc.ents.length; i++) if (doc.ents[i].id === id) return i;
        return -1;
    }

    function Remove(doc, ids) {
        var drop = ToSet(ids);
        var before = doc.ents.length;
        doc.ents = doc.ents.filter(function (e) { return !drop.has(e.id); });
        return before - doc.ents.length;
    }

    // Swaps one entity for the given pieces, in its place in the drawing
    // order. The first piece keeps the id; construction and paint carry over.
    function Replace(doc, id, pieces) {
        var index = IndexOf(doc, id);
        if (index < 0) return [];
        var old = doc.ents[index];
        var made = [];
        var items = (pieces || []).filter(Boolean).map(function (piece, k) {
            piece.id = k === 0 ? old.id : NewId(doc, 'e');
            if (old.constr) piece.constr = true;
            if (old.paint && !piece.paint) piece.paint = old.paint;
            made.push(piece.id);
            return piece;
        });
        Array.prototype.splice.apply(doc.ents, [ index, 1 ].concat(items));
        return made;
    }

    function ToSet(ids) {
        if (ids instanceof Set) return ids;
        return new Set(Array.isArray(ids) ? ids : (ids ? [ ids ] : []));
    }

    function Bbox(doc, options) {
        var box = null;
        var withConstr = !options || options.construction !== false;
        doc.ents.forEach(function (e) {
            if (!withConstr && e.constr) return;
            box = G.UnionBox(box, G.Bbox(e));
        });
        if (!options || options.dims !== false) {
            doc.dims.forEach(function (d) {
                box = G.UnionBox(box, { minX : Math.min(d.a.x, d.b.x), minY : Math.min(d.a.y, d.b.y), maxX : Math.max(d.a.x, d.b.x), maxY : Math.max(d.a.y, d.b.y) });
            });
        }
        return box;
    }

    function SetConstruction(doc, ids, flag) {
        var set = ToSet(ids);
        var count = 0;
        doc.ents.forEach(function (e) {
            if (!set.has(e.id)) return;
            if (flag) e.constr = true; else delete e.constr;
            count += 1;
        });
        return count;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Vertex Locations
    // -------------------------------------------------------------------------

    function KeyOf(p) {
        return p.x.toFixed(6) + ',' + p.y.toFixed(6);
    }

    // Map key -> { key, p, refs:[{id, end}], degree, centres:[id] }.
    // degree counts line and arc ends only; a circle's centre is a handle,
    // not a joint. options.construction false leaves construction out.
    function VertexIndex(doc, options) {
        var map = new Map();
        var withConstr = !options || options.construction !== false;
        function slot(p) {
            var key = KeyOf(p);
            var v = map.get(key);
            if (!v) { v = { key : key, p : { x : p.x, y : p.y }, refs : [], degree : 0, centres : [] }; map.set(key, v); }
            return v;
        }
        doc.ents.forEach(function (e) {
            if (!withConstr && e.constr) return;
            if (e.type === 'circle') { slot(e.c).centres.push(e.id); return; }
            var va = slot(e.a); va.refs.push({ id : e.id, end : 'a' }); va.degree += 1;
            var vb = slot(e.b); vb.refs.push({ id : e.id, end : 'b' }); vb.degree += 1;
        });
        return map;
    }

    // Every location an entity set stands on: line and arc ends, circle centres.
    function KeysOfEntities(doc, ids) {
        var set = ToSet(ids);
        var keys = new Set();
        doc.ents.forEach(function (e) {
            if (!set.has(e.id)) return;
            if (e.type === 'circle') { keys.add(KeyOf(e.c)); return; }
            keys.add(KeyOf(e.a)); keys.add(KeyOf(e.b));
        });
        return keys;
    }

    // The entities standing on any of the given locations.
    function EntitiesAt(doc, keys) {
        var set = keys instanceof Set ? keys : new Set(keys);
        return doc.ents.filter(function (e) {
            if (e.type === 'circle') return set.has(KeyOf(e.c));
            return set.has(KeyOf(e.a)) || set.has(KeyOf(e.b));
        }).map(function (e) { return e.id; });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Transforming Locations (move, rotate, mirror, scale, stretch)
    // -------------------------------------------------------------------------

    // Moves every end standing on one of `keys` through fn. An arc with both
    // ends moved keeps its sweep, turned round for a mirror (options.flips);
    // with one end moved it keeps its sweep and so stays an arc through its new
    // ends. A circle whose centre moves keeps its radius, times options.scale.
    // Dimensions taken from a moved location follow it.
    function TransformLocations(doc, keys, fn, options) {
        var set = keys instanceof Set ? keys : new Set(keys);
        var opts = options || {};
        var moved = 0;
        var movedTo = {};
        doc.ents.forEach(function (e) {
            if (e.type === 'circle') {
                if (!set.has(KeyOf(e.c))) return;
                e.c = fn(e.c);
                if (Number.isFinite(opts.scale)) e.r = e.r * Math.abs(opts.scale);
                moved += 1;
                return;
            }
            var keyA = KeyOf(e.a), keyB = KeyOf(e.b);
            var ka = set.has(keyA), kb = set.has(keyB);
            if (!ka && !kb) return;
            if (ka) { e.a = fn(e.a); movedTo[keyA] = KeyOf(e.a); }
            if (kb) { e.b = fn(e.b); movedTo[keyB] = KeyOf(e.b); }
            if (e.type === 'arc' && ka && kb && opts.flips) e.sw = -e.sw;
            moved += 1;
        });
        MoveVertexPaint(doc, movedTo);
        doc.dims.forEach(function (d) {
            var changed = false;
            if (d.ka && set.has(d.ka)) { d.a = fn(d.a); d.ka = KeyOf(d.a); changed = true; }
            if (d.kb && set.has(d.kb)) { d.b = fn(d.b); d.kb = KeyOf(d.b); changed = true; }
            if (changed && opts.flips) d.off = -d.off;
        });
        return moved;
    }

    function Translate(doc, keys, delta) {
        return TransformLocations(doc, keys, function (p) { return { x : p.x + delta.x, y : p.y + delta.y }; });
    }

    // Painted vertices go where their location went. Lifted off first, then
    // set down, so locations that swap (a mirror) keep their own colours.
    function MoveVertexPaint(doc, movedTo) {
        if (!doc.vpaint) return;
        var carried = [];
        Object.keys(movedTo).forEach(function (from) {
            if (doc.vpaint[from] === undefined) return;
            carried.push([ movedTo[from], doc.vpaint[from] ]);
            delete doc.vpaint[from];
        });
        carried.forEach(function (item) { doc.vpaint[item[0]] = item[1]; });
    }

    // Copies of entities, mapped by fn (new ids, nothing shared with the
    // originals until healing joins ends that land on one another).
    function CopyEntities(doc, ids, fn, options) {
        var set = ToSet(ids);
        var opts = options || {};
        var made = [];
        var copiedPaint = [];
        doc.ents.slice().forEach(function (e) {
            if (!set.has(e.id)) return;
            var copy = G.MapEntity(e, fn, opts.flips, opts.scale);
            delete copy.id;
            if (e.constr) copy.constr = true;
            if (e.type !== 'circle' && doc.vpaint) {
                [ [ e.a, copy.a ], [ e.b, copy.b ] ].forEach(function (pair) {
                    var paint = doc.vpaint[KeyOf(pair[0])];
                    if (paint) copiedPaint.push([ KeyOf(pair[1]), paint ]);
                });
            }
            made.push(Add(doc, copy));
        });
        copiedPaint.forEach(function (item) { doc.vpaint[item[0]] = item[1]; });
        return made;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Deleting and Splitting
    // -------------------------------------------------------------------------

    // Deletes vertex locations the way deleting a polyline point does: where
    // two edges meet they become one straight edge between their far ends; a
    // lone end takes its edge with it. Where more than two meet it is left,
    // and counted, because there is no single edge to make of it.
    function DeleteLocations(doc, keys) {
        var report = { merged : 0, removed : 0, skipped : 0 };
        (keys instanceof Set ? Array.from(keys) : keys).forEach(function (key) {
            var index = VertexIndex(doc);
            var v = index.get(key);
            if (!v) return;
            if (v.degree === 0 && v.centres.length) { report.removed += Remove(doc, v.centres); return; }
            if (v.degree === 1) { report.removed += Remove(doc, [ v.refs[0].id ]); return; }
            if (v.degree === 2 && v.refs[0].id !== v.refs[1].id) {
                var e1 = Get(doc, v.refs[0].id), e2 = Get(doc, v.refs[1].id);
                var far1 = v.refs[0].end === 'a' ? e1.b : e1.a;
                var far2 = v.refs[1].end === 'a' ? e2.b : e2.a;
                Remove(doc, [ e1.id, e2.id ]);
                if (G.Dist(far1, far2) > G.SAME_MM) {
                    var line = { type : 'line', a : G.Copy(far1), b : G.Copy(far2) };
                    if (e1.constr && e2.constr) line.constr = true;
                    if (e1.paint || e2.paint) line.paint = e1.paint || e2.paint;
                    Add(doc, line);
                }
                report.merged += 1;
                return;
            }
            report.skipped += 1;
        });
        return report;
    }

    // Cuts an entity in two at a point on it. A circle is opened there into one
    // arc of all but nothing - so it is cut at the point and its opposite side
    // instead, giving two half circles.
    function SplitAt(doc, id, p) {
        var e = Get(doc, id);
        if (!e) return [];
        var t = G.ParamOf(e, p);
        if (e.type === 'circle') {
            var opposite = (t + 0.5) % 1;
            var first = G.Part(e, t, opposite), second = G.Part(e, opposite, t);
            return first && second ? Replace(doc, id, [ first, second ]) : [];
        }
        if (t <= 1e-9 || t >= 1 - 1e-9) return [];
        var pieceA = G.Part(e, 0, t), pieceB = G.Part(e, t, 1);
        if (!pieceA || !pieceB) return [];
        pieceA.b = G.Copy(p); pieceB.a = G.Copy(p);
        return Replace(doc, id, [ pieceA, pieceB ]);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Healing
    // -------------------------------------------------------------------------

    // Run after every change. Ends (and circle centres) within `tol` of each
    // other are made exactly equal, so joins are exact; what has no length
    // left is removed, and so is an exact duplicate of another entity.
    function Heal(doc, tol) {
        var tolerance = Number.isFinite(tol) ? tol : 1e-4;
        var cell = tolerance * 4;
        var buckets = new Map();
        var report = { unified : 0, degenerate : 0, duplicates : 0 };

        function canonical(p) {
            var cx = Math.floor(p.x / cell), cy = Math.floor(p.y / cell);
            for (var dx = -1; dx <= 1; dx++) {
                for (var dy = -1; dy <= 1; dy++) {
                    var list = buckets.get((cx + dx) + ':' + (cy + dy));
                    if (!list) continue;
                    for (var i = 0; i < list.length; i++) {
                        var q = list[i];
                        if (Math.abs(q.x - p.x) <= tolerance && Math.abs(q.y - p.y) <= tolerance) {
                            if (q.x !== p.x || q.y !== p.y) report.unified += 1;
                            return { x : q.x, y : q.y };
                        }
                    }
                }
            }
            var key = cx + ':' + cy;
            if (!buckets.has(key)) buckets.set(key, []);
            buckets.get(key).push({ x : p.x, y : p.y });
            return { x : p.x, y : p.y };
        }

        doc.ents.forEach(function (e) {
            if (e.type === 'circle') { e.c = canonical(e.c); return; }
            e.a = canonical(e.a);
            e.b = canonical(e.b);
        });
        doc.dims.forEach(function (d) {
            d.a = canonical(d.a); d.b = canonical(d.b);
            if (d.ka) d.ka = KeyOf(d.a);
            if (d.kb) d.kb = KeyOf(d.b);
        });

        var seen = new Set();
        doc.ents = doc.ents.filter(function (e) {
            var degenerate = false;
            if (e.type === 'line') degenerate = G.Dist(e.a, e.b) <= tolerance;
            else if (e.type === 'arc') degenerate = G.Dist(e.a, e.b) <= tolerance || !(Math.abs(e.sw) > 1e-9) || Math.abs(e.sw) >= G.TAU - 1e-9;
            else degenerate = !(e.r > tolerance);
            if (degenerate) { report.degenerate += 1; return false; }

            var signature = Signature(e);
            if (seen.has(signature)) { report.duplicates += 1; return false; }
            seen.add(signature);
            return true;
        });
        HealVertexPaint(doc, tolerance);
        return report;
    }

    // A painted vertex stays on its vertex through the unify above; paint on
    // a location no edge ends on any more is dropped.
    function HealVertexPaint(doc, tolerance) {
        if (!doc.vpaint) { doc.vpaint = {}; return; }
        var keys = Object.keys(doc.vpaint);
        if (!keys.length) return;
        var live = new Map();
        doc.ents.forEach(function (e) {
            if (e.type === 'circle') return;
            live.set(KeyOf(e.a), e.a);
            live.set(KeyOf(e.b), e.b);
        });
        keys.forEach(function (key) {
            if (live.has(key)) return;
            var paint = doc.vpaint[key];
            delete doc.vpaint[key];
            var parts = key.split(',');
            var p = { x : parseFloat(parts[0]), y : parseFloat(parts[1]) };
            var reach = Math.max(tolerance * 4, 1e-5);
            var near = null;
            live.forEach(function (q, k) {
                if (!near && Math.abs(q.x - p.x) <= reach && Math.abs(q.y - p.y) <= reach && doc.vpaint[k] === undefined) near = k;
            });
            if (near) doc.vpaint[near] = paint;
        });
    }

    // The same whichever way round an edge was drawn.
    function Signature(e) {
        var flag = e.constr ? 'c' : 'p';
        if (e.type === 'circle') return 'C|' + KeyOf(e.c) + '|' + e.r.toFixed(6) + '|' + flag;
        var ka = KeyOf(e.a), kb = KeyOf(e.b);
        if (e.type === 'line') return 'L|' + (ka < kb ? ka + '|' + kb : kb + '|' + ka) + '|' + flag;
        var forward = ka < kb;
        var sweep = (forward ? e.sw : -e.sw).toFixed(9);
        return 'A|' + (forward ? ka + '|' + kb : kb + '|' + ka) + '|' + sweep + '|' + flag;
    }

    // Ends of DIFFERENT entities closer than `gapMm` but not joined are
    // pulled together, to their middle. For an imported or hand-built outline
    // whose corners miss by a whisker. Returns how many joins were made.
    function CloseGaps(doc, gapMm) {
        var index = VertexIndex(doc, { construction : false });
        var open = [];
        index.forEach(function (v) { if (v.degree === 1) open.push(v); });
        var joined = 0;
        var used = new Set();
        open.forEach(function (v) {
            if (used.has(v.key)) return;
            var best = null, bestD = gapMm;
            open.forEach(function (w) {
                if (w === v || used.has(w.key) || w.refs[0].id === v.refs[0].id) return;
                var d = G.Dist(v.p, w.p);
                if (d <= bestD) { best = w; bestD = d; }
            });
            if (!best) return;
            var meet = G.Mid(v.p, best.p);
            var pair = new Set([ v.key, best.key ]);
            TransformLocations(doc, pair, function () { return { x : meet.x, y : meet.y }; });
            used.add(v.key); used.add(best.key);
            joined += 1;
        });
        return joined;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Chains
    // -------------------------------------------------------------------------

    // The run of entities joined end to end with `id`, through locations
    // where exactly two of them meet: the whole outline, for a closed one.
    // Returns ids in order. Construction is only followed from construction.
    function ChainOf(doc, id) {
        var start = Get(doc, id);
        if (!start || start.type === 'circle') return start ? [ start.id ] : [];
        var index = VertexIndex(doc);
        var order = [ start.id ];
        var seen = new Set(order);

        function walk(fromKey, sink) {
            var key = fromKey;
            for (var guard = 0; guard < 100000; guard++) {
                var v = index.get(key);
                if (!v || v.degree !== 2) return;
                var next = v.refs.filter(function (ref) { return !seen.has(ref.id); })[0];
                if (!next) return;
                var e = Get(doc, next.id);
                if (!!e.constr !== !!start.constr) return;
                seen.add(e.id);
                sink(e.id);
                key = next.end === 'a' ? KeyOf(e.b) : KeyOf(e.a);
            }
        }
        walk(KeyOf(start.b), function (eid) { order.push(eid); });
        walk(KeyOf(start.a), function (eid) { order.unshift(eid); });
        return order;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | History
    // -------------------------------------------------------------------------

    function History(max) {
        this.max = max || 120;
        this.undo = [];
        this.redo = [];
    }

    History.prototype.Push = function (snapshot, label) {
        this.undo.push({ snapshot : snapshot, label : label || '' });
        if (this.undo.length > this.max) this.undo.shift();
        this.redo.length = 0;
    };

    // Returns the snapshot to restore, or null. The current state goes on the
    // other stack so the step can be walked back.
    History.prototype.Undo = function (current) {
        var step = this.undo.pop();
        if (!step) return null;
        this.redo.push({ snapshot : current, label : step.label });
        return step;
    };

    History.prototype.Redo = function (current) {
        var step = this.redo.pop();
        if (!step) return null;
        this.undo.push({ snapshot : current, label : step.label });
        return step;
    };

    History.prototype.Clear = function () {
        this.undo.length = 0;
        this.redo.length = 0;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Doc = {
        Create : Create, Serialize : Serialize, Deserialize : Deserialize, IsUsableEntity : IsUsableEntity,
        NewId : NewId, Add : Add, Get : Get, IndexOf : IndexOf, Remove : Remove, Replace : Replace, ToSet : ToSet,
        Bbox : Bbox, SetConstruction : SetConstruction,
        KeyOf : KeyOf, VertexIndex : VertexIndex, KeysOfEntities : KeysOfEntities, EntitiesAt : EntitiesAt,
        TransformLocations : TransformLocations, Translate : Translate, CopyEntities : CopyEntities,
        DeleteLocations : DeleteLocations, SplitAt : SplitAt, Heal : Heal, CloseGaps : CloseGaps, ChainOf : ChainOf,
        History : History
    };

    // endregion ----------------------------------------------------------------
})();
