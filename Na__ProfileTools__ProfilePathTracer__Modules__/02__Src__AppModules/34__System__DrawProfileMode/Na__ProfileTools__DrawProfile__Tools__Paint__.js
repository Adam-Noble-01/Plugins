/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - TOOLS - EDGE PAINT
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Tools__Paint__.js
   NAMESPACE  : window.Na__DrawProfile__Paint
                (and the 'paint' tool, added to window.Na__DrawProfile__Tools)
   PURPOSE    : Edge Paint (v1.6.15): the edge colours of the SSOT
                (Na__DataLib__CoreIndex__EdgeMaterials), what each edge and
                vertex of the drawing is painted, and the Paint tool (B).

   WHERE A COLOUR GOES IN THE MODEL
     EDGE     its line on the start and end caps and at every mitre: the
              outline of the section wherever the section stands.
     VERTEX   the line it sweeps along the whole path.
     An unpainted edge takes the profile's usual colour (the one most of its
     edges carry). An unpainted vertex follows its two edges, the darker
     where they differ - the rule the sweep itself applies
     (Na__Geometry__ProfileVertexStyles), so what shows here is what the
     model gets.

   WHERE IT IS KEPT
     An edge's colour rides on its entity (e.paint); a vertex's is kept by
     location in doc.vpaint, which Na__DrawProfile__Doc moves with the
     location. Both hold an SSOT id, or 'Default' for SketchUp's own edge
     colour (no material).

   THE TOOL (B), as SketchUp's Paint Bucket
     Click an edge or a vertex to paint it. Shift: everything that colour.
     Ctrl: the whole outline. Alt: pick the colour up instead.
   ============================================================================= */

(function () {
    'use strict';

    var G     = window.Na__DrawProfile__Geom;
    var D     = window.Na__DrawProfile__Doc;
    var V     = window.Na__DrawProfile__View;
    var Tools = window.Na__DrawProfile__Tools;

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var DEFAULT_ID    = 'Default';          // SketchUp's own edge colour: no material
    var DEFAULT_HEX   = '#1A1A1A';          // how SketchUp's default shows here
    var UNPAINTED_HEX = '#666666';          // the writer's colour for an edge nothing paints
    var CLEAR         = '';                 // the tool lays no colour: back to unpainted
    var HEX_PATTERN   = /^#[0-9a-f]{6}$/i;
    var STORAGE_KEY   = 'na-ppt-drawprofile-paint';

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Registry (the SSOT palette, and colours met in profiles)
    // -------------------------------------------------------------------------

    var state = {
        palette : [],           // [{ id, name, material, hex, series, description }]
        status  : 'pending',    // 'url' | 'cache_stale' | 'failed' | 'pending'
        message : '',
        known   : {},           // id -> { hex, name }
        current : null          // what the tool lays down: an id, CLEAR, or null (nothing chosen)
    };

    try {
        var saved = window.localStorage.getItem(STORAGE_KEY);
        if (typeof saved === 'string') state.current = saved;
    } catch (err) { /* storage blocked: the tool starts with nothing chosen */ }

    function SetPalette(payload) {
        var data = payload || {};
        var list = Array.isArray(data.entries) ? data.entries : [];
        state.palette = list.filter(function (e) {
            return e && typeof e.id === 'string' && e.id && HEX_PATTERN.test(String(e.hex || ''));
        }).map(function (e) {
            return {
                id : e.id, name : String(e.name || Pretty(e.id)), material : String(e.material || e.id),
                hex : String(e.hex).toUpperCase(), series : String(e.series || ''), description : String(e.description || '')
            };
        });
        state.status = String(data.status || (state.palette.length ? 'url' : 'failed'));
        state.message = String(data.statusMessage || '');
        state.palette.forEach(function (e) {
            state.known[e.id] = { hex : e.hex, name : e.name };
            if (e.material && e.material !== e.id) state.known[e.material] = { hex : e.hex, name : e.name };
        });
        if (state.current === null && state.palette.length) state.current = state.palette[0].id;
    }

    // Colours a profile or a model face carried: shown even when the SSOT is
    // out of reach. The palette's own colour always wins.
    function Remember(map) {
        if (!map || typeof map !== 'object') return;
        Object.keys(map).forEach(function (id) {
            var hex = String(map[id] || '');
            if (!id || !HEX_PATTERN.test(hex) || state.known[id]) return;
            state.known[id] = { hex : hex.toUpperCase(), name : Pretty(id) };
        });
    }

    function HexOf(id, fallback) {
        if (id === DEFAULT_ID) return DEFAULT_HEX;
        if (id && state.known[id]) return state.known[id].hex;
        return fallback === undefined ? UNPAINTED_HEX : fallback;
    }

    function NameOf(id) {
        if (!id) return 'Unpainted';
        if (id === DEFAULT_ID) return 'SketchUp default';
        return state.known[id] ? state.known[id].name : Pretty(id);
    }

    // MTE103__LineColour__DarkGrey__L40 -> Dark Grey
    function Pretty(id) {
        var text = String(id || '').replace(/^MTE\d+__LineColour__/, '').replace(/__L\d+$/, '').replace(/__/g, ' ');
        return text.replace(/([a-z])([A-Z])/g, '$1 $2').trim() || String(id || '');
    }

    // MTE100__GreyscaleSeries__ -> Greyscale
    function SeriesLabel(series) {
        var text = String(series || '').replace(/^MTE\d+__/, '').replace(/_+$/, '').replace(/Series$/, '');
        return text.replace(/([a-z])([A-Z])/g, '$1 $2').trim() || 'Colours';
    }

    function Current() { return state.current; }

    function SetCurrent(id) {
        state.current = typeof id === 'string' ? id : null;
        try { window.localStorage.setItem(STORAGE_KEY, state.current === null ? '' : state.current); } catch (err) { /* convenience only */ }
    }

    // 0 black .. 1 white. SketchUp's default reads as black, as in the sweep.
    function Luminance(hex, id) {
        if (id === DEFAULT_ID) return 0;
        var m = HEX_PATTERN.test(String(hex || '')) ? String(hex) : null;
        if (!m) return 0;
        var r = parseInt(m.slice(1, 3), 16), g = parseInt(m.slice(3, 5), 16), b = parseInt(m.slice(5, 7), 16);
        return ((0.2126 * r) + (0.7152 * g) + (0.0722 * b)) / 255;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Drawing's Colours
    // -------------------------------------------------------------------------

    // def: the profile's usual colour { id, hex } (Editor.PaintDefault).
    function EdgeId(e, def) {
        return e.paint || (def && def.id) || null;
    }

    function EdgeHex(e, def) {
        if (e.paint) return HexOf(e.paint);
        if (def && def.hex && HEX_PATTERN.test(def.hex)) return def.hex.toUpperCase();
        return def && def.id ? HexOf(def.id) : UNPAINTED_HEX;
    }

    // key -> { key, p, id, hex, explicit } for every vertex of the outline
    // (an end of a non-construction line or arc). An unpainted vertex takes
    // the darker of its edges' colours, as the sweep does.
    function Vertices(doc, def) {
        var byId = {};
        doc.ents.forEach(function (e) { byId[e.id] = e; });
        var vpaint = doc.vpaint || {};
        var out = new Map();
        D.VertexIndex(doc, { construction : false }).forEach(function (v) {
            if (!v.degree) return;
            var own = vpaint[v.key];
            if (own) { out.set(v.key, { key : v.key, p : v.p, id : own, hex : HexOf(own), explicit : true }); return; }
            var best = null;
            v.refs.forEach(function (ref) {
                var e = byId[ref.id];
                if (!e) return;
                var info = { id : EdgeId(e, def), hex : EdgeHex(e, def) };
                if (!best || Luminance(info.hex, info.id) < Luminance(best.hex, best.id) - 1e-9) best = info;
            });
            out.set(v.key, { key : v.key, p : v.p, id : best ? best.id : null, hex : best ? best.hex : UNPAINTED_HEX, explicit : false });
        });
        return out;
    }

    // What the drawing uses: [{ id, hex, name, edges, vertices, unpainted }]
    // most used first. vertices counts painted vertices; unpainted counts the
    // edges that take the usual colour and the vertices that follow edges.
    function Used(doc, def) {
        var rows = {};
        var order = [];
        function row(id, hex) {
            var key = (id || '') + '|' + hex;
            if (!rows[key]) { rows[key] = { id : id, hex : hex, name : NameOf(id), edges : 0, vertices : 0, unpainted : 0 }; order.push(key); }
            return rows[key];
        }
        doc.ents.forEach(function (e) {
            if (e.constr) return;
            var r = row(EdgeId(e, def), EdgeHex(e, def));
            r.edges += 1;
            if (!e.paint) r.unpainted += 1;
        });
        Vertices(doc, def).forEach(function (v) {
            var r = row(v.id, v.hex);
            if (v.explicit) r.vertices += 1; else r.unpainted += 1;
        });
        return order.map(function (k) { return rows[k]; }).sort(function (a, b) { return (b.edges + b.vertices) - (a.edges + a.vertices); });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Painting (each one undo step)
    // -------------------------------------------------------------------------

    function PaintEdges(ed, ids, colour) {
        var list = (ids || []).filter(Boolean);
        if (!list.length) return 0;
        var count = 0;
        ed.Commit(colour ? 'Paint edges' : 'Clear edge paint', function (doc) {
            list.forEach(function (id) {
                var e = D.Get(doc, id);
                if (!e || e.constr) return;
                if (colour) e.paint = colour; else delete e.paint;
                count += 1;
            });
            return { ok : true };
        });
        return count;
    }

    function PaintVertices(ed, keys, colour) {
        var list = (keys || []).filter(Boolean);
        if (!list.length) return 0;
        ed.Commit(colour ? 'Paint vertices' : 'Clear vertex paint', function (doc) {
            doc.vpaint = doc.vpaint || {};
            list.forEach(function (key) { if (colour) doc.vpaint[key] = colour; else delete doc.vpaint[key]; });
            return { ok : true };
        });
        return list.length;
    }

    function OutlineEdgeIds(doc) {
        return doc.ents.filter(function (e) { return !e.constr; }).map(function (e) { return e.id; });
    }

    function OutlineVertexKeys(doc) {
        var keys = [];
        D.VertexIndex(doc, { construction : false }).forEach(function (v) { if (v.degree) keys.push(v.key); });
        return keys;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Paint Tool
    // -------------------------------------------------------------------------

    function DescribeTarget(target) {
        return target.kind === 'vertex' ? 'vertex' : 'edge';
    }

    function Colour() {
        return state.current === null ? null : state.current;
    }

    Tools.Register({
        id : 'paint', label : 'Edge Paint', cursor : 'default',
        target : null,

        activate : function () { this.target = null; },
        reset : function () { this.target = null; },
        deactivate : function (ed) { this.target = null; ed.hoverId = null; ed.hoverKey = null; },

        prompt : function () {
            var colour = Colour();
            var what = colour === null ? 'pick a colour in Edge Paint first' : (colour === CLEAR ? 'taking paint off' : NameOf(colour));
            return 'EDGE PAINT (' + what + '): click an edge (its line at the ends and every mitre) or a vertex (the line it sweeps along the path). Shift: everything that colour. Ctrl: the whole outline. Alt: pick a colour up.';
        },

        // The vertex under the cursor wins over the edge it ends.
        Pick : function (ed, ev) {
            var tol = ed.TolWorld(ed.settings.Tol.GripPx + 2);
            var best = null;
            D.VertexIndex(ed.doc, { construction : false }).forEach(function (v) {
                if (!v.degree) return;
                var d = G.Dist(v.p, ev.world);
                if (d <= tol && (!best || d < best.d)) best = { kind : 'vertex', key : v.key, p : v.p, d : d };
            });
            if (best) return best;
            var hit = ed.HitEntity(ev.world, { noDims : true });
            var e = hit ? D.Get(ed.doc, hit.id) : null;
            return e && !e.constr ? { kind : 'edge', id : e.id } : null;
        },

        onMove : function (ed, ev) {
            var target = this.Pick(ed, ev);
            this.target = target;
            ed.hoverId = target && target.kind === 'edge' ? target.id : null;
            ed.hoverKey = target && target.kind === 'vertex' ? target.key : null;
            ed.SetCursor(target ? 'pointer' : 'default');
        },

        onDown : function (ed, ev) {
            var target = this.Pick(ed, ev);
            this.target = target;
            if (!target) { ed.Hint('Click an edge or a vertex of the outline. Construction edges are never painted.', true); return; }
            var def = ed.PaintDefault();

            if (ev.alt) {
                var picked = target.kind === 'edge' ? (D.Get(ed.doc, target.id) || {}).paint : (ed.doc.vpaint || {})[target.key];
                SetCurrent(picked || CLEAR);
                ed.Hint('Picked up ' + (picked ? NameOf(picked) : 'no paint (unpainted)') + ' from that ' + DescribeTarget(target) + '.');
                ed.Emit('onPaintChanged');
                return;
            }

            var colour = Colour();
            if (colour === null) { ed.Hint('Pick a colour in the Edge Paint tab first.', true); ed.Emit('onPaintNeeded'); return; }

            // As SketchUp's Paint Bucket: clicking into the selection paints all of it.
            var count;
            if (target.kind === 'edge') {
                var ids = [ target.id ];
                if (ev.ctrl) ids = OutlineEdgeIds(ed.doc);
                else if (!ev.shift && !ed.vertexMode && ed.selection.has(target.id) && ed.selection.size > 1) ids = Array.from(ed.selection);
                else if (ev.shift) {
                    var clicked = D.Get(ed.doc, target.id);
                    var like = EdgeId(clicked, def) + '|' + EdgeHex(clicked, def);
                    ids = ed.doc.ents.filter(function (e) { return !e.constr && (EdgeId(e, def) + '|' + EdgeHex(e, def)) === like; }).map(function (e) { return e.id; });
                }
                count = PaintEdges(ed, ids, colour);
                ed.Hint((colour ? NameOf(colour) + ' on ' : 'Paint taken off ') + count + ' edge(s)' + (colour ? ': their lines at the ends and every mitre.' : ': they take the profile\'s usual colour.'));
            } else {
                var keys = [ target.key ];
                if (ev.ctrl) keys = OutlineVertexKeys(ed.doc);
                else if (!ev.shift && ed.vertexMode && ed.vsel.has(target.key) && ed.vsel.size > 1) keys = Array.from(ed.vsel);
                else if (ev.shift) {
                    var all = Vertices(ed.doc, def);
                    var own = all.get(target.key);
                    keys = [];
                    all.forEach(function (v) { if (own && v.explicit === own.explicit && v.id === own.id && v.hex === own.hex) keys.push(v.key); });
                }
                count = PaintVertices(ed, keys, colour);
                ed.Hint((colour ? NameOf(colour) + ' on ' : 'Paint taken off ') + count + ' vertex(es)' + (colour ? ': the lines they sweep along the path.' : ': they follow their edges again.'));
            }
            ed.Emit('onPaintChanged');
        },

        draw : function (ed, ctx, view) {
            var target = this.target;
            if (!target) return;
            var colour = Colour();
            var hex = colour ? HexOf(colour) : '#94A3B8';
            ctx.save();
            if (target.kind === 'vertex') {
                var s = V.W2S(view, target.p);
                ctx.beginPath();
                ctx.arc(s.x, s.y, 8, 0, G.TAU);
                ctx.fillStyle = hex;
                ctx.fill();
                ctx.lineWidth = 2;
                ctx.strokeStyle = '#0F172A';
                ctx.stroke();
            } else {
                var e = D.Get(ed.doc, target.id);
                if (e) {
                    var pts = G.Tessellate(e, ed.settings.Curves);
                    var trace = function () {
                        ctx.beginPath();
                        pts.forEach(function (p, i) { var q = V.W2S(view, p); if (i === 0) ctx.moveTo(q.x, q.y); else ctx.lineTo(q.x, q.y); });
                        if (e.type === 'circle') ctx.closePath();
                    };
                    ctx.lineCap = 'round';
                    ctx.lineJoin = 'round';
                    trace(); ctx.strokeStyle = 'rgba(15, 23, 42, 0.4)'; ctx.lineWidth = 9; ctx.stroke();
                    trace(); ctx.strokeStyle = hex; ctx.lineWidth = 5.5; ctx.stroke();
                }
            }
            ctx.restore();
        }
    });

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Paint = {
        DEFAULT_ID : DEFAULT_ID, DEFAULT_HEX : DEFAULT_HEX, UNPAINTED_HEX : UNPAINTED_HEX, CLEAR : CLEAR,
        SetPalette : SetPalette, Remember : Remember,
        Palette : function () { return state.palette.slice(); },
        Status : function () { return { status : state.status, message : state.message, count : state.palette.length }; },
        HexOf : HexOf, NameOf : NameOf, Pretty : Pretty, SeriesLabel : SeriesLabel,
        Current : Current, SetCurrent : SetCurrent, Luminance : Luminance,
        EdgeId : EdgeId, EdgeHex : EdgeHex, Vertices : Vertices, Used : Used,
        PaintEdges : PaintEdges, PaintVertices : PaintVertices,
        OutlineEdgeIds : OutlineEdgeIds, OutlineVertexKeys : OutlineVertexKeys
    };

    // endregion ----------------------------------------------------------------
})();
