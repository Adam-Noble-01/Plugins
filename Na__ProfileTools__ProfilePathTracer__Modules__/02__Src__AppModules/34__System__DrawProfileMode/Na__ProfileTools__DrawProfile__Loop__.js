/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - LOOP
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Loop__.js
   NAMESPACE  : window.Na__DrawProfile__Loop
   PURPOSE    : Is the drawing a profile? Finds the one closed outline the
                library can store, says precisely what stops it being one, and
                converts between the drawing and the library's profile data.

   WHAT A PROFILE IS
     The sweep builds one face from one outer loop (Na__Geometry__
     BuildTransformedProfileFace), so a savable drawing is exactly one closed
     outline: every end joined to exactly one other, one piece, never crossing
     itself, enclosing an area. Construction geometry is ignored.

   ANALYSE  ->  { ok, issues[], loop, stats, markers[] }
     issues   { severity:'error'|'warn'|'info', code, message, at:{x,y}, ids }
              errors block saving; each names its fix.
     loop     { points (CCW, arcs divided), curves[{startIndex, segments,
              radius, closed}], order[{id, reversed}], edgeIds[] (the entity
              each outline edge points[i] -> points[i + 1] belongs to) }

   IMPORT / EXPORT
     A library record opens as lines and arcs: Na__Geometry__Curves where the
     profile has it (drawn here), otherwise every run of segments that is an
     exact, evenly divided arc - which is what SketchUp's own arcs leave - is
     recognised as one. Export is the payload the profile writer takes.
     Edge Paint (v1.6.15) travels both ways: each outline edge's and vertex's
     colour id out (edgePaint / vertexPaint), and a profile's edge colours
     (Mesh3D) and vertex sweep colours (Profile2D SweepEdge*) back in.
   ============================================================================= */

(function () {
    'use strict';

    var G = window.Na__DrawProfile__Geom;
    var D = window.Na__DrawProfile__Doc;

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var HEAVY_VERTEX_COUNT = 400;
    var IMPORT_FIT_MM      = 2e-3;
    var IMPORT_STEP_RAD    = 2e-4;
    var REBUILD_FIT_MM     = 0.02;
    var REBUILD_STEP_RAD   = 2e-3;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Analyse
    // -------------------------------------------------------------------------

    function Analyse(doc, config) {
        var cfg = config || window.Na__DrawProfile__Config;
        var tol = cfg.Tol;
        var result = { ok : false, issues : [], loop : null, stats : null, markers : [] };
        var ents = doc.ents.filter(function (e) { return !e.constr; });

        if (!ents.length) {
            Issue(result, 'info', 'empty', 'Nothing drawn yet. Draw the outline with Line, Arc and the modify tools, or load a profile.', null, []);
            return result;
        }

        var circles = ents.filter(function (e) { return e.type === 'circle'; });
        var edges   = ents.filter(function (e) { return e.type !== 'circle'; });

        // A LONE CIRCLE is a profile by itself: a round bar or handrail.
        if (circles.length === 1 && !edges.length) {
            var circle = circles[0];
            var ring = G.Tessellate(circle, cfg.Curves);
            if (G.PolygonArea(ring) < 0) ring.reverse();
            result.loop = {
                points  : ring,
                curves  : [ { startIndex : 0, segments : ring.length, radius : circle.r, closed : true, id : circle.id } ],
                order   : [ { id : circle.id, reversed : false } ],
                edgeIds : ring.map(function () { return circle.id; })
            };
            result.stats = Stats(result.loop, 0, 1);
            result.ok = true;
            return result;
        }

        circles.forEach(function (c) {
            Issue(result, 'error', 'circle', 'A whole circle cannot join the outline. Trim it into an arc, or make it Construction (G).',
                  { x : c.c.x + c.r, y : c.c.y }, [ c.id ]);
        });

        var index = D.VertexIndex({ ents : edges, dims : [] });
        var openEnds = [];
        index.forEach(function (v) {
            if (v.degree === 1) openEnds.push(v);
            else if (v.degree > 2) {
                Issue(result, 'error', 'branch', v.degree + ' edges meet at one point. A profile outline has exactly two at every corner: Trim or delete the extra.',
                      v.p, v.refs.map(function (r) { return r.id; }));
            }
        });

        // OPEN ENDS - with the likely reason, so the message names the fix.
        var reported = new Set();
        openEnds.forEach(function (v) {
            if (reported.has(v.key)) return;
            var gapTo = null, gapD = tol.GapMm;
            openEnds.forEach(function (w) {
                if (w === v || reported.has(w.key)) return;
                var d = G.Dist(v.p, w.p);
                if (d <= gapD) { gapTo = w; gapD = d; }
            });
            if (gapTo) {
                reported.add(v.key); reported.add(gapTo.key);
                Issue(result, 'error', 'gap', 'Two ends miss each other by ' + G.FormatMm(gapD, 3) + ' mm. Heal Gaps joins them.',
                      G.Mid(v.p, gapTo.p), [ v.refs[0].id, gapTo.refs[0].id ]);
                return;
            }
            reported.add(v.key);
            var onEdge = TouchingEdge(edges, v);
            if (onEdge) {
                Issue(result, 'error', 'tee', 'This end stops on the middle of another edge. Split that edge here (U), or Trim the overhang.', v.p, [ v.refs[0].id, onEdge ]);
            } else {
                Issue(result, 'error', 'open', 'Open end: the outline does not close here. Draw on to another end, or Extend / Corner it.', v.p, [ v.refs[0].id ]);
            }
        });

        // PIECES - edges that never meet the rest.
        var pieces = Components(edges, index);
        if (pieces.length > 1) {
            pieces.sort(function (a, b) { return b.length - a.length; });
            pieces.slice(1).forEach(function (piece) {
                var e = edges.filter(function (x) { return x.id === piece[0]; })[0];
                Issue(result, 'error', 'pieces', 'This is a separate piece. A profile is one outline: join it on, delete it, or make it Construction (G).',
                      G.MidPoint(e), piece);
            });
        }

        if (!HasErrors(result) && edges.length) {
            var walked = Walk(edges, index, cfg);
            if (!walked) {
                Issue(result, 'error', 'walk', 'The outline could not be followed round. Check Profile again after healing.', null, []);
            } else {
                Finish(result, walked, cfg, edges);
            }
        }

        result.ok = !HasErrors(result) && !!result.loop;
        return result;
    }

    function Issue(result, severity, code, message, at, ids) {
        result.issues.push({ severity : severity, code : code, message : message, at : at ? { x : at.x, y : at.y } : null, ids : ids || [] });
        if (at) result.markers.push({ code : code, severity : severity, p : { x : at.x, y : at.y } });
    }

    function HasErrors(result) {
        return result.issues.some(function (i) { return i.severity === 'error'; });
    }

    function TouchingEdge(edges, v) {
        for (var i = 0; i < edges.length; i++) {
            var e = edges[i];
            if (e.id === v.refs[0].id) continue;
            var near = G.Nearest(e, v.p);
            if (near.d <= 1e-3 && near.t > 1e-6 && near.t < 1 - 1e-6) return e.id;
        }
        return null;
    }

    function Components(edges, index) {
        var parent = {};
        edges.forEach(function (e) { parent[e.id] = e.id; });
        function find(x) { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; }
        index.forEach(function (v) {
            for (var i = 1; i < v.refs.length; i++) parent[find(v.refs[i].id)] = find(v.refs[0].id);
        });
        var groups = {};
        edges.forEach(function (e) { var r = find(e.id); (groups[r] = groups[r] || []).push(e.id); });
        return Object.keys(groups).map(function (k) { return groups[k]; });
    }

    // Follows the outline from its lowest, then leftmost, corner.
    function Walk(edges, index, cfg) {
        var byId = {};
        edges.forEach(function (e) { byId[e.id] = e; });
        var startV = null;
        index.forEach(function (v) {
            if (!startV || v.p.y < startV.p.y - 1e-9 || (Math.abs(v.p.y - startV.p.y) <= 1e-9 && v.p.x < startV.p.x)) startV = v;
        });
        if (!startV) return null;

        var order = [];
        var used = new Set();
        var key = startV.key;
        for (var guard = 0; guard <= edges.length; guard++) {
            var v = index.get(key);
            var ref = v.refs.filter(function (r) { return !used.has(r.id); })[0];
            if (!ref) break;
            used.add(ref.id);
            var e = byId[ref.id];
            var reversed = ref.end === 'b';
            order.push({ id : e.id, reversed : reversed });
            key = D.KeyOf(reversed ? e.a : e.b);
            if (key === startV.key) break;
        }
        if (used.size !== edges.length || key !== startV.key) return null;
        return order.map(function (o) { return { id : o.id, reversed : o.reversed, e : byId[o.id] }; });
    }

    function Finish(result, walked, cfg, edges) {
        var points = [];
        var curves = [];
        var owners = [];
        var arcCount = 0, lineCount = 0;
        walked.forEach(function (step) {
            var e = step.reversed ? G.Reverse(step.e) : step.e;
            var pts = G.Tessellate(e, cfg.Curves);
            if (e.type === 'arc') {
                arcCount += 1;
                var segs = pts.length - 1;
                if (segs >= 2) curves.push({ startIndex : points.length, segments : segs, radius : G.Radius(e), closed : false, id : step.id });
            } else {
                lineCount += 1;
            }
            for (var i = 0; i < pts.length - 1; i++) { points.push(pts[i]); owners.push(step.id); }
        });

        if (points.length < 3) {
            Issue(result, 'error', 'small', 'The outline needs at least three corners.', null, []);
            return;
        }

        // Crossings first: a figure-of-eight can enclose no NET area, and
        // "it crosses itself here" is the message that names the fix.
        var crossings = G.RingSelfIntersections(points, 12);
        crossings.forEach(function (hit) {
            Issue(result, 'error', 'cross', hit.kind === 'fold'
                ? 'The outline doubles back along itself here. Trim or delete the overlapping edge.'
                : 'The outline crosses itself here. Trim the crossing edges back to where they meet.', hit.p, []);
        });

        var area = G.PolygonArea(points);
        if (Math.abs(area) < 1e-4) {
            if (!crossings.length) Issue(result, 'error', 'area', 'The outline encloses no area.', points[0], []);
            return;
        }
        if (area < 0) {
            var n = points.length;
            points = [ points[0] ].concat(points.slice(1).reverse());
            curves = curves.map(function (c) {
                var start = (n - ((c.startIndex + c.segments) % n)) % n;
                return { startIndex : start, segments : c.segments, radius : c.radius, closed : false, id : c.id };
            });
            // Edge j of the turned loop is edge n - 1 - j of the old one, run backwards.
            var walkedOwners = owners;
            owners = walkedOwners.map(function (unused, j) { return walkedOwners[(n - j - 1 + n) % n]; });
            area = -area;
        }

        var shortCount = 0, firstShort = null;
        for (var k = 0; k < points.length; k++) {
            var d = G.Dist(points[k], points[(k + 1) % points.length]);
            if (d < cfg.Tol.ShortEdgeMm) { shortCount += 1; if (!firstShort) firstShort = points[k]; }
        }
        if (shortCount) {
            Issue(result, 'warn', 'short', shortCount + ' edge(s) shorter than ' + cfg.Tol.ShortEdgeMm + ' mm. They sweep as slivers: delete the vertex or Heal.', firstShort, []);
        }
        if (points.length > HEAVY_VERTEX_COUNT) {
            Issue(result, 'warn', 'heavy', points.length + ' vertices: every one becomes an edge along the whole sweep. Fewer arc segments sweep faster.', null, []);
        }

        result.loop = { points : points, curves : curves, order : walked.map(function (s) { return { id : s.id, reversed : s.reversed }; }), edgeIds : owners };
        result.stats = Stats(result.loop, lineCount, arcCount);
    }

    function Stats(loop, lineCount, arcCount) {
        var pts = loop.points;
        var box = null;
        pts.forEach(function (p) {
            box = G.UnionBox(box, { minX : p.x, minY : p.y, maxX : p.x, maxY : p.y });
        });
        return {
            vertices  : pts.length,
            lines     : lineCount,
            arcs      : arcCount,
            curves    : loop.curves.length,
            area      : Math.abs(G.PolygonArea(pts)),
            perimeter : G.PolygonPerimeter(pts),
            box       : box,
            width     : box ? box.maxX - box.minX : 0,
            height    : box ? box.maxY - box.minY : 0,
            datumInside : G.PointInPolygon({ x : 0, y : 0 }, pts)
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Export (the profile writer's payload)
    // -------------------------------------------------------------------------

    function ExportPayload(analysis, doc) {
        if (!analysis || !analysis.ok || !analysis.loop) return null;
        var round = function (v) { return Math.round(v * 1e6) / 1e6; };
        var paint = ExportPaint(analysis.loop, doc);
        return {
            loop   : analysis.loop.points.map(function (p) { return [ round(p.x), round(p.y) ]; }),
            curves : analysis.loop.curves.map(function (c) {
                return { startIndex : c.startIndex, segments : c.segments, radius : round(c.radius) };
            }),
            annotations : {
                dimensions : (doc.dims || []).map(function (d) {
                    return { a : [ round(d.a.x), round(d.a.y) ], b : [ round(d.b.x), round(d.b.y) ], offset : round(d.off || 0), orient : d.orient || 'aligned' };
                })
            },
            edgePaint   : paint.edges,
            vertexPaint : paint.vertices,
            paintHex    : paint.hex
        };
    }

    // One colour id (or null: unpainted) per outline edge and per outline
    // vertex, and the colour shown for each id used. A divided arc's inner
    // vertices are never painted: they follow the arc.
    function ExportPaint(loop, doc) {
        var byId = {};
        doc.ents.forEach(function (e) { byId[e.id] = e; });
        var edges = (loop.edgeIds || []).map(function (id) { var e = byId[id]; return e && e.paint ? e.paint : null; });
        var vpaint = doc.vpaint || {};
        var vertices = loop.points.map(function (p) { return vpaint[D.KeyOf(p)] || null; });
        var P = window.Na__DrawProfile__Paint;
        var hex = {};
        edges.concat(vertices).forEach(function (id) {
            if (!id || hex[id] || !P || id === P.DEFAULT_ID) return;
            var shown = P.HexOf(id, null);
            if (shown) hex[id] = shown;
        });
        return { edges : edges, vertices : vertices, hex : hex };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Import (a library record -> a drawing)
    // -------------------------------------------------------------------------

    // Returns { doc, arcs, fromCurves, message } or { doc:null, message }.
    function ImportRecord(record) {
        var asset = record && record.profileData && record.profileData.assetData;
        var block = asset && asset.Na__Asset__Profile2D;
        if (!block) return { doc : null, message : 'That profile has no 2D outline to open.' };

        var vertexMap = {};
        (block.Na__Geometry__Vertices || []).forEach(function (v) {
            if (v && v.VertexId !== undefined) vertexMap[String(v.VertexId)] = { x : Number(v.PosY_mm), y : Number(v.PosZ_mm) };
        });
        var face = (block.Na__Geometry__Faces || [])[0];
        var ids = face && Array.isArray(face.OuterLoopVertices) ? face.OuterLoopVertices.map(String) : [];
        var points = [];
        var pointIds = [];
        ids.forEach(function (id) {
            var p = vertexMap[id];
            if (!p || !Number.isFinite(p.x) || !Number.isFinite(p.y)) return;
            var last = points[points.length - 1];
            if (last && G.Same(last, p, 1e-6)) return;
            points.push(p); pointIds.push(id);
        });
        if (points.length > 1 && G.Same(points[0], points[points.length - 1], 1e-6)) { points.pop(); pointIds.pop(); }
        if (points.length < 3) return { doc : null, message : 'That profile\'s outline has fewer than three points.' };

        var runs = RunsFromCurveRecords(block.Na__Geometry__Curves, pointIds, points);
        var fromCurves = runs !== null;
        var paints = RecordPaints(asset, pointIds);
        var doc;
        if (fromCurves && runs.circle) {
            doc = D.Create();
            var round = { type : 'circle', c : runs.circle.c, r : runs.circle.r, segs : points.length };
            var roundPaint = MostUsed(paints.edges);
            if (roundPaint) round.paint = roundPaint;
            D.Add(doc, round);
        } else {
            doc = RingToDoc(points, fromCurves ? runs.list : DetectRuns(points, IMPORT_FIT_MM, IMPORT_STEP_RAD, true), paints);
        }

        ImportDimensions(doc, asset.Na__Asset__Annotations2D);
        D.Heal(doc, 1e-4);
        var arcs = doc.ents.filter(function (e) { return e.type !== 'line'; }).length;
        return {
            doc          : doc,
            arcs         : arcs,
            fromCurves   : fromCurves,
            defaultPaint : paints.usual,
            message      : points.length + ' points opened' + (arcs ? ', ' + arcs + (fromCurves ? ' curve(s) from the profile.' : ' arc(s) recognised.') : '.')
        };
    }

    // A profile's colours along its ring: each ring edge's (the Mesh3D edge
    // between its two vertices), each ring vertex's sweep colour (Profile2D
    // SweepEdge*), and its usual colour - the one most of its edges carry,
    // which an unpainted edge takes when it is saved. Colours met here are
    // remembered, so they show even when the SSOT is out of reach.
    function RecordPaints(asset, pointIds) {
        var P = window.Na__DrawProfile__Paint;
        var mesh = asset && asset.Na__Asset__Mesh3D;
        var byPair = {};
        var tally = {};
        var order = [];
        var hexes = {};
        (mesh && Array.isArray(mesh.Na__Geometry__Edges) ? mesh.Na__Geometry__Edges : []).forEach(function (rec) {
            if (!rec || rec.StartVertex === undefined || rec.EndVertex === undefined) return;
            var id = PaintIdOf(rec.EdgeColourId, rec.EdgeMaterialName);
            var hex = CleanHex(rec.EdgeColourHex);
            byPair[PairKey(String(rec.StartVertex), String(rec.EndVertex))] = id;
            if (id && hex) hexes[id] = hex;
            var style = (id || '') + '|' + (hex || '');
            if (!tally[style]) { tally[style] = 0; order.push(style); }
            tally[style] += 1;
        });
        var block = asset && asset.Na__Asset__Profile2D;
        var sweep = {};
        (block && Array.isArray(block.Na__Geometry__Vertices) ? block.Na__Geometry__Vertices : []).forEach(function (v) {
            if (!v || v.VertexId === undefined) return;
            var id = PaintIdOf(v.SweepEdgeColourId, v.SweepEdgeMaterialName);
            if (!id) return;
            sweep[String(v.VertexId)] = id;
            var hex = CleanHex(v.SweepEdgeColourHex);
            if (hex) hexes[id] = hexes[id] || hex;
        });
        var n = pointIds.length;
        var edges = pointIds.map(function (id, i) { var v = byPair[PairKey(id, pointIds[(i + 1) % n])]; return v || null; });
        var vertices = pointIds.map(function (id) { return sweep[id] || null; });
        var best = null;
        order.forEach(function (style) { if (!best || tally[style] > tally[best]) best = style; });
        var usual = null;
        if (best) {
            var parts = best.split('|');
            usual = { id : parts[0] || null, hex : parts[1] || null };
        }
        if (P) P.Remember(hexes);
        return { edges : edges, vertices : vertices, usual : usual };
    }

    function PairKey(a, b) { return a < b ? a + '|' + b : b + '|' + a; }

    function PaintIdOf(colourId, materialName) {
        var id = String(colourId === undefined || colourId === null ? '' : colourId).trim();
        if (!id) id = String(materialName === undefined || materialName === null ? '' : materialName).trim();
        return id || null;
    }

    function CleanHex(value) {
        var text = String(value === undefined || value === null ? '' : value).trim();
        return /^#[0-9a-f]{6}$/i.test(text) ? text.toUpperCase() : null;
    }

    // The colour most of a run's edges carry (the first, on a tie).
    function MostUsed(list) {
        var tally = {}, best = null;
        (list || []).forEach(function (id) {
            if (!id) return;
            tally[id] = (tally[id] || 0) + 1;
            if (!best || tally[id] > tally[best]) best = id;
        });
        return best;
    }

    // Na__Geometry__Curves -> runs [{ start, segments, arc }] along the ring, or
    // null when the profile has no curve records. A record is only trusted if
    // its ids still run consecutively round the outline and fit one arc.
    function RunsFromCurveRecords(records, pointIds, points) {
        if (!Array.isArray(records) || !records.length) return null;
        var n = points.length;
        var slot = {};
        pointIds.forEach(function (id, i) { slot[id] = i; });
        var list = [];
        var circle = null;
        records.forEach(function (rec) {
            if (!rec || !Array.isArray(rec.VertexIds)) return;
            var slots = rec.VertexIds.map(function (id) { return slot[String(id)]; });
            if (slots.some(function (s) { return s === undefined; })) return;
            if (rec.IsClosed === true && slots.length === n) {
                var ring = slots.map(function (s) { return points[s]; });
                var described = G.DescribeCircle(ring, 0.01, 0.01);
                if (described) circle = described;
                return;
            }
            if (slots.length < 3) return;
            var forward = slots.every(function (s, i) { return i === 0 || ((s - slots[i - 1] + n) % n) === 1; });
            var backward = slots.every(function (s, i) { return i === 0 || ((slots[i - 1] - s + n) % n) === 1; });
            if (!forward && !backward) return;
            if (backward) slots = slots.slice().reverse();
            var arcPts = slots.map(function (s) { return points[s]; });
            var arc = G.DescribeArc(arcPts, 0.01, 0.01);
            if (!arc) return;
            list.push({ start : slots[0], segments : slots.length - 1, sw : arc.sw });
        });
        return { list : list, circle : circle };
    }

    // A ring of points + arc runs -> a document of lines and arcs. paints
    // (optional): { edges:[id per ring edge], vertices:[id per ring point] };
    // an arc takes the colour most of its segments carry, and only points
    // that end an edge keep a vertex colour.
    function RingToDoc(points, runs, paints) {
        var n = points.length;
        var doc = D.Create();
        var edgePaint = paints && Array.isArray(paints.edges) && paints.edges.length === n ? paints.edges : null;
        var vertexPaint = paints && Array.isArray(paints.vertices) && paints.vertices.length === n ? paints.vertices : null;
        var ends = [];
        var runAt = {};
        var covered = new Array(n).fill(false);
        runs.forEach(function (run) {
            var clash = false;
            for (var k = 0; k < run.segments; k++) { if (covered[(run.start + k) % n]) clash = true; }
            if (clash) return;
            for (var j = 0; j < run.segments; j++) covered[(run.start + j) % n] = true;
            runAt[run.start] = run;
        });

        // Begin on an edge no run passes through, so no arc is cut in two.
        var begin = 0;
        for (var b = 0; b < n; b++) {
            var inside = covered[b] && !runAt[b];
            if (!inside) { begin = b; break; }
        }

        var i = 0;
        while (i < n) {
            var at = (begin + i) % n;
            var run = runAt[at];
            if (run) {
                var endAt = (at + run.segments) % n;
                var arc = { type : 'arc', a : G.Copy(points[at]), b : G.Copy(points[endAt]), sw : run.sw, segs : run.segments };
                if (edgePaint) {
                    var covered = [];
                    for (var s = 0; s < run.segments; s++) covered.push(edgePaint[(at + s) % n]);
                    var arcPaint = MostUsed(covered);
                    if (arcPaint) arc.paint = arcPaint;
                }
                D.Add(doc, arc);
                ends.push(at, endAt);
                i += run.segments;
            } else {
                var line = { type : 'line', a : G.Copy(points[at]), b : G.Copy(points[(at + 1) % n]) };
                if (edgePaint && edgePaint[at]) line.paint = edgePaint[at];
                D.Add(doc, line);
                ends.push(at, (at + 1) % n);
                i += 1;
            }
        }
        if (vertexPaint) {
            ends.forEach(function (index) { if (vertexPaint[index]) doc.vpaint[D.KeyOf(points[index])] = vertexPaint[index]; });
        }
        return doc;
    }

    function ImportDimensions(doc, block) {
        var list = block && Array.isArray(block.Na__Annotation__Dimensions) ? block.Na__Annotation__Dimensions : [];
        var index = D.VertexIndex(doc);
        list.forEach(function (rec) {
            var a = { x : Number(rec.StartY_mm), y : Number(rec.StartZ_mm) };
            var b = { x : Number(rec.EndY_mm), y : Number(rec.EndZ_mm) };
            if (![ a.x, a.y, b.x, b.y ].every(Number.isFinite)) return;
            var ka = D.KeyOf(a), kb = D.KeyOf(b);
            doc.dims.push({
                id : D.NewId(doc, 'd'), a : a, b : b,
                ka : index.has(ka) ? ka : null, kb : index.has(kb) ? kb : null,
                off : Number(rec.Offset_mm) || 0,
                orient : [ 'aligned', 'horizontal', 'vertical' ].indexOf(rec.Orientation) >= 0 ? rec.Orientation : 'aligned'
            });
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Arc Recognition
    // -------------------------------------------------------------------------

    // Runs of a closed ring that are arcs: [{ start, segments, sw }]. Greedy
    // from a corner (where the turn changes), taking the longest run of three
    // or more segments that DescribeArc accepts. strictEnds requires the end
    // steps to be as long as the rest, so redrawing the arc gives back the
    // very same points.
    function DetectRuns(points, fitMm, stepRad, strictEnds) {
        var n = points.length;
        if (n < 4) return [];
        var start = CornerIndex(points);
        if (start < 0) return [];
        var ordered = [];
        for (var i = 0; i <= n; i++) ordered.push(points[(start + i) % n]);
        var runs = [];
        var k = 0;
        while (k < n) {
            var best = null;
            for (var j = k + 3; j <= n; j++) {
                var arc = FitRun(ordered.slice(k, j + 1), fitMm, stepRad, strictEnds);
                if (!arc) break;
                best = { end : j, sw : arc.sw };
            }
            if (best) {
                runs.push({ start : (start + k) % n, segments : best.end - k, sw : best.sw });
                k = best.end;
            } else {
                k += 1;
            }
        }
        return runs;
    }

    function FitRun(pts, fitMm, stepRad, strictEnds) {
        var arc = G.DescribeArc(pts, fitMm, stepRad);
        if (!arc) return null;
        if (strictEnds) {
            var c = arc.c;
            var steps = [];
            for (var i = 1; i < pts.length; i++) {
                var a = Math.atan2(pts[i - 1].y - c.y, pts[i - 1].x - c.x);
                var b = Math.atan2(pts[i].y - c.y, pts[i].x - c.x);
                steps.push(G.NormAngle((b - a) * (arc.sw < 0 ? -1 : 1)));
            }
            var first = steps[0];
            if (steps.some(function (s) { return Math.abs(s - first) > stepRad; })) return null;
            if (pts.some(function (p) { return Math.abs(G.Dist(p, c) - arc.r) > fitMm; })) return null;
        }
        return arc;
    }

    // A vertex where the outline's turn changes - an arc never starts in the
    // middle of one. -1 for a ring with no corner at all (a circle).
    function CornerIndex(points) {
        var n = points.length;
        var turns = [];
        var lens = [];
        for (var i = 0; i < n; i++) {
            var p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n];
            var d1 = G.Sub(p1, p0), d2 = G.Sub(p2, p1);
            turns.push(Math.atan2(G.Cross(d1, d2), G.Dot(d1, d2)));
            lens.push(G.Len(d2));
        }
        for (var k = 0; k < n; k++) {
            var prev = (k - 1 + n) % n;
            if (Math.abs(turns[k] - turns[prev]) > 1e-3 || Math.abs(lens[k] - lens[prev]) > 1e-3 * Math.max(1, lens[k])) return k;
        }
        return -1;
    }

    // Turns runs of plain lines joined end to end into arcs where they are
    // one. ids limits it to those lines (all lines when empty). Returns the
    // number of arcs made.
    function RebuildArcs(doc, ids, fitMm) {
        var limit = ids && ids.length ? new Set(ids) : null;
        var fit = Number.isFinite(fitMm) ? fitMm : REBUILD_FIT_MM;
        var qualifies = function (e) { return !!e && e.type === 'line' && !e.constr && (!limit || limit.has(e.id)); };
        var made = 0;
        var visited = new Set();
        doc.ents.filter(qualifies).map(function (e) { return e.id; }).forEach(function (id) {
            if (visited.has(id) || !qualifies(D.Get(doc, id))) return;
            var chain = D.ChainOf(doc, id);
            chain.forEach(function (x) { visited.add(x); });
            var allLines = chain.every(function (x) { return qualifies(D.Get(doc, x)); });

            // A CLOSED RING OF LINES may be a whole circle, or hold arcs that
            // run across the point the chain happens to start at.
            if (allLines && chain.length >= 3) {
                var polyline = ChainPoints(doc, chain);
                if (polyline && G.Same(polyline[0], polyline[polyline.length - 1], 1e-6)) {
                    var ring = polyline.slice(0, -1);
                    var circle = G.DescribeCircle(ring, fit, REBUILD_STEP_RAD);
                    if (circle) {
                        var round = { type : 'circle', c : circle.c, r : circle.r, segs : ring.length };
                        var roundPaint = MostUsed(chain.map(function (x) { var e = D.Get(doc, x); return e ? e.paint : null; }));
                        if (roundPaint) round.paint = roundPaint;
                        D.Remove(doc, chain);
                        D.Add(doc, round);
                        made += 1;
                        return;
                    }
                    DetectRuns(ring, fit, REBUILD_STEP_RAD, false).forEach(function (r) {
                        ReplaceRun(doc, chain, ring, { from : r.start, segments : r.segments, sw : r.sw }, true);
                        made += 1;
                    });
                    return;
                }
            }

            // OTHERWISE each unbroken stretch of qualifying lines on its own.
            var stretches = [];
            var current = [];
            chain.forEach(function (x) {
                if (qualifies(D.Get(doc, x))) { current.push(x); return; }
                if (current.length) stretches.push(current);
                current = [];
            });
            if (current.length) stretches.push(current);
            var closedChain = chain.length > 2 && SharesEnd(D.Get(doc, chain[0]), D.Get(doc, chain[chain.length - 1]));
            if (closedChain && stretches.length > 1 && qualifies(D.Get(doc, chain[0])) && qualifies(D.Get(doc, chain[chain.length - 1]))) {
                stretches[0] = stretches.pop().concat(stretches[0]);
            }
            stretches.forEach(function (stretch) {
                if (stretch.length < 3) return;
                var pts = ChainPoints(doc, stretch);
                if (!pts) return;
                DetectOpenRuns(pts, fit, REBUILD_STEP_RAD).forEach(function (r) {
                    ReplaceRun(doc, stretch, pts, r, false);
                    made += 1;
                });
            });
        });
        D.Heal(doc, 1e-4);
        return made;
    }

    function SharesEnd(e1, e2) {
        if (!e1 || !e2 || e1.type === 'circle' || e2.type === 'circle') return false;
        var k1 = [ D.KeyOf(e1.a), D.KeyOf(e1.b) ], k2 = [ D.KeyOf(e2.a), D.KeyOf(e2.b) ];
        return k1.some(function (k) { return k2.indexOf(k) >= 0; });
    }

    function DetectOpenRuns(pts, fitMm, stepRad) {
        var runs = [];
        var k = 0;
        while (k < pts.length - 1) {
            var best = null;
            for (var j = k + 3; j < pts.length; j++) {
                var arc = G.DescribeArc(pts.slice(k, j + 1), fitMm, stepRad);
                if (!arc) break;
                best = { end : j, sw : arc.sw };
            }
            if (best) { runs.push({ from : k, segments : best.end - k, sw : best.sw }); k = best.end; }
            else k += 1;
        }
        return runs;
    }

    // The points of a chain of lines, in order (ends shared).
    function ChainPoints(doc, chain) {
        var first = D.Get(doc, chain[0]);
        if (chain.length === 1) return [ G.Copy(first.a), G.Copy(first.b) ];
        var second = D.Get(doc, chain[1]);
        var start = (D.KeyOf(first.a) === D.KeyOf(second.a) || D.KeyOf(first.a) === D.KeyOf(second.b)) ? first.b : first.a;
        var pts = [ G.Copy(start) ];
        var cursor = start;
        for (var i = 0; i < chain.length; i++) {
            var e = D.Get(doc, chain[i]);
            var next = D.KeyOf(e.a) === D.KeyOf(cursor) ? e.b : (D.KeyOf(e.b) === D.KeyOf(cursor) ? e.a : null);
            if (!next) return null;
            pts.push(G.Copy(next));
            cursor = next;
        }
        return pts;
    }

    // Removes the lines a run covers and adds the arc in their place.
    function ReplaceRun(doc, chain, pts, run, closed) {
        var n = closed ? pts.length : pts.length - 1;
        var covered = [];
        for (var k = 0; k < run.segments; k++) {
            var i = closed ? (run.from + k) % n : run.from + k;
            var a = pts[i], b = pts[closed ? (i + 1) % n : i + 1];
            chain.forEach(function (id) {
                var e = D.Get(doc, id);
                if (!e) return;
                if ((G.Same(e.a, a) && G.Same(e.b, b)) || (G.Same(e.a, b) && G.Same(e.b, a))) covered.push(id);
            });
        }
        var paint = MostUsed(covered.map(function (id) { var e = D.Get(doc, id); return e ? e.paint : null; }));
        D.Remove(doc, covered);
        var endIndex = closed ? (run.from + run.segments) % n : run.from + run.segments;
        var arc = { type : 'arc', a : G.Copy(pts[run.from]), b : G.Copy(pts[endIndex]), sw : run.sw, segs : run.segments };
        if (paint) arc.paint = paint;
        D.Add(doc, arc);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Selection Import (a face or edges sent from SketchUp)
    // -------------------------------------------------------------------------

    // payload.kind 'face': { loop:[[y,z]], curves:[{startIndex, segments}] }
    // payload.kind 'edges': { segments:[[[y,z],[y,z]]] }
    function ImportSelection(payload) {
        var doc = D.Create();
        var P = window.Na__DrawProfile__Paint;
        if (P && payload.paintHex && typeof payload.paintHex === 'object') P.Remember(payload.paintHex);
        if (payload.kind === 'face') {
            var pts = (payload.loop || []).map(function (p) { return { x : Number(p[0]), y : Number(p[1]) }; });
            if (pts.length < 3) return { doc : null, message : 'The face outline came through empty.' };
            var n = pts.length;
            var facePaints = Array.isArray(payload.edgePaint) && payload.edgePaint.length === n
                ? { edges : payload.edgePaint.map(function (id) { return typeof id === 'string' && id ? id : null; }) }
                : null;
            var runs = [];
            var circle = null;
            (payload.curves || []).forEach(function (c) {
                var start = Number(c.startIndex), segs = Number(c.segments);
                if (!Number.isInteger(start) || !Number.isInteger(segs) || segs < 2) return;
                if (segs >= n) { circle = G.DescribeCircle(pts, 0.01, 0.01); return; }
                var arcPts = [];
                for (var k = 0; k <= segs; k++) arcPts.push(pts[(start + k) % n]);
                var arc = G.DescribeArc(arcPts, 0.01, 0.01);
                if (arc) runs.push({ start : start, segments : segs, sw : arc.sw });
            });
            if (circle) {
                var whole = { type : 'circle', c : circle.c, r : circle.r, segs : n };
                var wholePaint = facePaints ? MostUsed(facePaints.edges) : null;
                if (wholePaint) whole.paint = wholePaint;
                D.Add(doc, whole);
            } else {
                doc = RingToDoc(pts, runs, facePaints);
            }
        } else if (payload.kind === 'edges') {
            (payload.segments || []).forEach(function (seg) {
                var a = { x : Number(seg[0][0]), y : Number(seg[0][1]) }, b = { x : Number(seg[1][0]), y : Number(seg[1][1]) };
                if ([ a.x, a.y, b.x, b.y ].every(Number.isFinite) && G.Dist(a, b) > 1e-6) D.Add(doc, { type : 'line', a : a, b : b });
            });
        }
        D.Heal(doc, 1e-4);
        return { doc : doc, message : payload.statusMessage || '' };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Loop = {
        Analyse : Analyse,
        ExportPayload : ExportPayload,
        ImportRecord : ImportRecord,
        ImportSelection : ImportSelection,
        RebuildArcs : RebuildArcs,
        DetectRuns : DetectRuns,
        RingToDoc : RingToDoc
    };

    // endregion ----------------------------------------------------------------
})();
