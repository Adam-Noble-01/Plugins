// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - PERSPECTIVE ANGLE FEATURE
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__PerspectiveAngle__.js
// PURPOSE    : Measure roof pitches and angles on a photo as they are on the
//              building, not as they look in the picture. The photo is first
//              calibrated by drawing lines along vertical edges (blue) and
//              level edges (red, plus green on a wall at 90 degrees if
//              visible). The solver recovers the camera tilt, turn and lens,
//              then each pitch or angle is measured on the chosen wall or on
//              the ground, with a +/- worked out from the clicks themselves.
//
// DESIGN     : Self-contained feature file, like the Measurement overlay. It
//              talks to the viewer only through window.Na__ImageViewer__Core
//              (drawing, shared undo history, active-tool hand-off) and does
//              its maths through window.Na__ImageViewer__PerspectiveSolver.
//              State is kept per image path for the session.
//
// INTERACTION: Toolbar "Angle" opens the side panel. Pick a line colour or a
//              measuring tool, then click on the photo. Drag on the photo to
//              pan and scroll to zoom without leaving the tool; a magnifier
//              follows the pointer. Drag any handle to refine a point. Click a
//              line or angle to select it; Delete removes it, Esc steps back.
//              Guides (T, like SketchUp's Tape Measure): click a point, move
//              along a direction and click; the guide is an infinite 3D line
//              drawn in perspective. Arrow keys lock red, green or blue as in
//              SketchUp. Points snap to guide intersections, endpoints and
//              guides, here and in the Measure tool.
// =============================================================================

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Guard - require the viewer Core API and the solver
    // -------------------------------------------------------------------------

    var na_core   = window.Na__ImageViewer__Core;
    var na_solver = window.Na__ImageViewer__PerspectiveSolver;
    if (!na_core || !na_solver) { return; }
    if (typeof na_core.registerHistory !== 'function' || typeof na_core.claimTool !== 'function') { return; }

    var na_vec = na_solver.vec;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var NA_TOOL_NAME       = 'perspective';
    var NA_AXES            = ['z', 'x', 'y'];
    var NA_AXIS_COLOR      = { z: '#1a5fd0', x: '#d4291c', y: '#178a3a' };
    var NA_AXIS_NAME       = { z: 'Vertical', x: 'Red', y: 'Green' };
    var NA_MEAS_COLOR      = '#8e24aa';
    var NA_RAW_COLOR       = '#9a6700';   // a reading not yet corrected for perspective
    var NA_SELECT_COLOR    = '#f5a623';
    var NA_HALO_COLOR      = 'rgba(255, 255, 255, 0.9)';
    var NA_LABEL_TEXT      = '#ffffff';
    var NA_FONT_PX         = 12;
    var NA_HANDLE_PX       = 4.5;
    var NA_HIT_PX          = 9;
    var NA_DRAG_START_PX   = 4;
    var NA_LOUPE_RADIUS_PX = 66;
    var NA_LOUPE_GAIN      = 4;
    var NA_ARC_RADIUS_PX   = 34;
    var NA_MC_DELAY_MS     = 140;
    var NA_PLANE_NAME      = { xz: 'Red wall', yz: 'Green wall', xy: 'Ground' };
    var NA_GUIDE_COLOR     = { x: '#d4291c', y: '#178a3a', z: '#1a5fd0', par: '#d500a5', tilt: '#d500a5', free: '#3a4652' };
    var NA_GUIDE_AXIS_NAME = { x: 'Red axis', y: 'Green axis', z: 'Blue axis' };
    var NA_GUIDE_DASH      = [10, 6];
    var NA_SNAP_PX         = 8;     // endpoints and intersections
    var NA_ON_GUIDE_PX     = 6;
    var NA_INFER_DEG       = 10;    // how near an axis the pointer must move
    var NA_INFER_MIN_PX    = 14;    // pointer travel before a direction is read
    var NA_GUIDE_KEYS      = { ArrowRight: 'x', ArrowLeft: 'y', ArrowUp: 'z', ArrowDown: 'auto' };

    // Lens priors: how sure the tool is of the focal length before the lines
    // have their say. Auto covers a phone's main camera (24-26 mm).
    var NA_AUTO_LENS_MM    = 25;
    var NA_AUTO_LENS_SIGMA = 0.12;
    var NA_SET_LENS_SIGMA  = 0.02;
    var NA_EXIF_LENS_SIGMA = 0.01;
    var NA_LENS_PRESETS    = ['13', '24', '26', '48', '52', '77', '120'];

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Feature State
    // -------------------------------------------------------------------------

    var na_stateByKey    = {};    // image key -> { lines:[], meas:[], guides:[], lens:{ mode, mm, userSet } }
    var na_analysisByKey = {};    // image key -> solver output + { prior, mc } (derived, never undone)
    var na_photoInfo     = {};    // image key -> lens data read from the file by Ruby
    var na_nextId        = 1;
    var na_panelOpen     = false;
    var na_mode          = null;  // 'z' | 'x' | 'y' | 'pitch' | 'angle' | 'guide' | null
    var na_pending       = [];    // points of the item being drawn, image space
    var na_cursor        = null;  // pointer in canvas pixels while it is over the canvas
    var na_press         = null;  // a mouse press that may become a click, a pan or a drag
    var na_drag          = null;  // { ref, moved } while a handle is dragged
    var na_selected      = null;  // { kind:'line'|'meas'|'guide', id }
    var na_plane         = 'xz';
    var na_showGrid      = false; // vanishing-direction fans over the photo
    var na_showGuideLines = true; // the guides themselves (and snapping to them)
    var na_guideAxis     = 'auto';// 'auto', or a locked 'x' | 'y' | 'z'
    var na_guideAngle    = null;  // typed pitch for angled guides, degrees
    var na_guideAngleError = '';
    var na_snap          = null;  // where the pointer has snapped, while placing points
    var na_inferred      = null;  // the direction a new guide is following
    var na_lastLens      = { mode: 'auto', mm: 26 };
    var na_lensError     = '';
    var na_lensEditing   = false; // the custom focal length box is open
    var na_mcTimer       = null;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Handles
    // -------------------------------------------------------------------------

    var na_canvas      = null;
    var na_wrap        = null;
    var na_panel       = null;
    var na_btnToggle   = null;
    var na_btnClose    = null;
    var na_btnDraw     = {};
    var na_btnClearAx  = {};
    var na_countEl     = {};
    var na_lensSelect  = null;
    var na_lensInput   = null;
    var na_lensInfo    = null;
    var na_statusEl    = null;
    var na_planeBtns   = [];
    var na_btnPitch    = null;
    var na_btnAngle    = null;
    var na_toolHint    = null;
    var na_resultsEl   = null;
    var na_gridBox     = null;
    var na_btnClearAll = null;
    var na_btnGuide    = null;
    var na_guideAxisBtns = [];
    var na_guideAngleInput = null;
    var na_guideHint   = null;
    var na_showGuidesBox = null;
    var na_guideCount  = null;
    var na_btnClearGuides = null;

    function Na__ImageViewerPerspective__El(id) {
        return document.getElementById(id);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Per-Image State And History
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__Key() {
        return na_core.getImageKey();
    }

    function Na__ImageViewerPerspective__DefaultLens(key) {
        var info = na_photoInfo[key];
        if (info && info.focal35 > 0) return { mode: 'exif', mm: info.focal35, userSet: false };
        return { mode: na_lastLens.mode, mm: na_lastLens.mm, userSet: false };
    }

    function Na__ImageViewerPerspective__State(key) {
        if (!na_stateByKey[key]) {
            na_stateByKey[key] = { lines: [], meas: [], guides: [], lens: Na__ImageViewerPerspective__DefaultLens(key) };
        }
        return na_stateByKey[key];
    }

    function Na__ImageViewerPerspective__LensOf(key) {
        var st = na_stateByKey[key];
        return st ? st.lens : Na__ImageViewerPerspective__DefaultLens(key);
    }

    function Na__ImageViewerPerspective__ClonePoint(p) {
        return { x: p.x, y: p.y, prec: p.prec };
    }

    function Na__ImageViewerPerspective__CloneGuide(g) {
        var c = { id: g.id, dir: g.dir, p: Na__ImageViewerPerspective__ClonePoint(g.p) };
        if (g.q)  c.q  = Na__ImageViewerPerspective__ClonePoint(g.q);
        if (g.vp) c.vp = { x: g.vp.x, y: g.vp.y, w: g.vp.w };
        if (g.measId !== undefined) c.measId = g.measId;
        if (g.plane) { c.plane = g.plane; c.deg = g.deg; c.side = g.side; }
        return c;
    }

    function Na__ImageViewerPerspective__CloneState(st) {
        return {
            guides : (st.guides || []).map(Na__ImageViewerPerspective__CloneGuide),
            lines : st.lines.map(function(l) {
                return { id: l.id, axis: l.axis, a: Na__ImageViewerPerspective__ClonePoint(l.a), b: Na__ImageViewerPerspective__ClonePoint(l.b) };
            }),
            meas  : st.meas.map(function(m) {
                return { id: m.id, kind: m.kind, plane: m.plane, pts: m.pts.map(Na__ImageViewerPerspective__ClonePoint) };
            }),
            lens  : { mode: st.lens.mode, mm: st.lens.mm, userSet: !!st.lens.userSet }
        };
    }

    function Na__ImageViewerPerspective__Snapshot(key) {
        var st = na_stateByKey[key];
        return st ? Na__ImageViewerPerspective__CloneState(st) : null;
    }

    function Na__ImageViewerPerspective__Restore(key, snap) {
        if (snap) na_stateByKey[key] = Na__ImageViewerPerspective__CloneState(snap);
        else      delete na_stateByKey[key];
        delete na_analysisByKey[key];
        na_pending = [];
        na_drag    = null;
        na_press   = null;
        if (na_selected && !Na__ImageViewerPerspective__FindItem(na_selected.kind, na_selected.id)) na_selected = null;
    }

    function Na__ImageViewerPerspective__OnHistoryChanged(reason) {
        if (reason !== 'undo' && reason !== 'redo') return;
        var key = Na__ImageViewerPerspective__Key();
        if (key && na_stateByKey[key]) Na__ImageViewerPerspective__Analyse(key, true);
        Na__ImageViewerPerspective__RefreshPanel();
    }

    function Na__ImageViewerPerspective__FindItem(kind, id) {
        var st = na_stateByKey[Na__ImageViewerPerspective__Key()];
        if (!st) return null;
        var list = kind === 'line' ? st.lines : kind === 'guide' ? (st.guides || []) : st.meas;
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return null;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Analysis (solver calls)
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__LensPrior(key) {
        var lens = Na__ImageViewerPerspective__LensOf(key);
        var info = na_photoInfo[key] || {};
        var size = na_core.getImageSize();
        var mm, sigma, source;
        if (lens.mode === 'exif' && info.focal35 > 0) {
            mm = info.focal35; sigma = NA_EXIF_LENS_SIGMA; source = 'exif';
        } else if (lens.mode === 'auto' || lens.mode === 'exif' || !(lens.mm > 0)) {
            mm = NA_AUTO_LENS_MM; sigma = NA_AUTO_LENS_SIGMA; source = 'auto';
        } else {
            mm = lens.mm; sigma = NA_SET_LENS_SIGMA; source = 'set';
        }
        return { fPx: na_solver.lensMmToPx(mm, size.w || 4032, size.h || 3024), sigmaLn: sigma, mm: mm, source: source };
    }

    // withMc = true runs the Monte Carlo for the +/-; false is the quick
    // solve used while the pointer moves (the last +/- is kept meanwhile).
    function Na__ImageViewerPerspective__Analyse(key, withMc) {
        var st   = na_stateByKey[key];
        var size = na_core.getImageSize();
        if (!st || !size.w || !size.h) { delete na_analysisByKey[key]; return null; }

        var prior = Na__ImageViewerPerspective__LensPrior(key);
        var out   = na_solver.analyse({
            lines        : st.lines,
            lens         : { fPx: prior.fPx, sigmaLn: prior.sigmaLn },
            size         : size,
            measurements : st.meas,
            trials       : withMc ? undefined : 0
        });
        out.prior = prior;
        out.mc    = !!withMc;

        var previous = na_analysisByKey[key];
        if (!withMc && previous && previous.results) {
            out.results.forEach(function(res, i) {
                var m = st.meas[i];
                previous.results.forEach(function(old, j) {
                    if (old && old.id === m.id && old.sigma) { res.sigma = old.sigma; res.validFraction = old.validFraction; res.stale = true; }
                });
            });
            if (previous.cal && previous.cal.fSigmaLn && out.cal.ok) out.cal.fSigmaLn = previous.cal.fSigmaLn;
        }
        out.results.forEach(function(res, i) { res.id = st.meas[i].id; });
        na_analysisByKey[key] = out;
        return out;
    }

    function Na__ImageViewerPerspective__ScheduleMc(key) {
        if (na_mcTimer) clearTimeout(na_mcTimer);
        na_mcTimer = setTimeout(function() {
            na_mcTimer = null;
            if (na_drag || key !== Na__ImageViewerPerspective__Key()) return;
            Na__ImageViewerPerspective__Analyse(key, true);
            Na__ImageViewerPerspective__RefreshPanel();
            na_core.requestDraw();
        }, NA_MC_DELAY_MS);
    }

    // Something on this image changed: quick solve now, +/- shortly after.
    function Na__ImageViewerPerspective__Changed(key) {
        Na__ImageViewerPerspective__Analyse(key, false);
        Na__ImageViewerPerspective__ScheduleMc(key);
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__Analysis() {
        return na_analysisByKey[Na__ImageViewerPerspective__Key()] || null;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Formatting
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__Deg(v) {
        return (Math.round(v * 10) / 10).toFixed(1) + '\u00b0';
    }

    // The +/- shown is two standard deviations (about 95 %), never below 0.1.
    function Na__ImageViewerPerspective__HalfWidth(res) {
        if (!res || !res.ok || !res.sigma) return null;
        return Math.max(0.1, Math.ceil(res.sigma * 2 * 10) / 10);
    }

    function Na__ImageViewerPerspective__Quality(res) {
        var hw = Na__ImageViewerPerspective__HalfWidth(res);
        if (hw === null) return '';
        if (res.validFraction !== undefined && res.validFraction < 0.9) return 'weak';
        if (hw <= 1)  return 'good';
        if (hw <= 3)  return 'fair';
        return 'weak';
    }

    function Na__ImageViewerPerspective__LineName(line, st) {
        var n = 0;
        for (var i = 0; i < st.lines.length; i++) {
            if (st.lines[i].axis === line.axis) n++;
            if (st.lines[i].id === line.id) break;
        }
        return NA_AXIS_NAME[line.axis] + ' ' + n;
    }

    function Na__ImageViewerPerspective__MeasName(m, st) {
        var n = 0;
        for (var i = 0; i < st.meas.length; i++) {
            if (st.meas[i].kind === m.kind) n++;
            if (st.meas[i].id === m.id) break;
        }
        return (m.kind === 'pitch' ? 'Pitch ' : 'Angle ') + n;
    }

    function Na__ImageViewerPerspective__LineDiag(an, id) {
        if (!an || !an.cal || !an.cal.ok) return null;
        for (var i = 0; i < an.cal.lines.length; i++) if (an.cal.lines[i].id === id) return an.cal.lines[i];
        return null;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Drawing Primitives
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__ToScreen(p) {
        return na_core.imgToScreen(p);
    }

    function Na__ImageViewerPerspective__StrokePath(ctx, ratio, pts, color, widthPx, dash, selected) {
        if (pts.length < 2) return;
        ctx.save();
        ctx.lineCap  = 'round';
        ctx.lineJoin = 'round';
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
        ctx.setLineDash([]);
        ctx.strokeStyle = selected ? NA_SELECT_COLOR : NA_HALO_COLOR;
        ctx.lineWidth   = (widthPx + (selected ? 4 : 2.5)) * ratio;
        ctx.stroke();
        if (dash) ctx.setLineDash(dash.map(function(d) { return d * ratio; }));
        ctx.strokeStyle = color;
        ctx.lineWidth   = widthPx * ratio;
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerPerspective__DrawHandle(ctx, ratio, p, color) {
        ctx.save();
        ctx.beginPath();
        ctx.arc(p.x, p.y, NA_HANDLE_PX * ratio, 0, Math.PI * 2);
        ctx.fillStyle   = color;
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth   = 1.2 * ratio;
        ctx.fill();
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerPerspective__DrawLabel(ctx, ratio, x, y, text, color, align) {
        ctx.save();
        ctx.font         = '600 ' + (NA_FONT_PX * ratio) + 'px "Segoe UI", Arial, sans-serif';
        ctx.textBaseline = 'middle';
        ctx.textAlign    = 'center';
        var padX = 6 * ratio, padY = 3 * ratio;
        var tw   = ctx.measureText(text).width;
        var bw   = tw + padX * 2;
        var bh   = NA_FONT_PX * ratio + padY * 2;
        var left = align === 'left' ? x : x - bw / 2;
        var r    = 3 * ratio;
        ctx.beginPath();
        ctx.moveTo(left + r, y - bh / 2);
        ctx.lineTo(left + bw - r, y - bh / 2);
        ctx.quadraticCurveTo(left + bw, y - bh / 2, left + bw, y - bh / 2 + r);
        ctx.lineTo(left + bw, y + bh / 2 - r);
        ctx.quadraticCurveTo(left + bw, y + bh / 2, left + bw - r, y + bh / 2);
        ctx.lineTo(left + r, y + bh / 2);
        ctx.quadraticCurveTo(left, y + bh / 2, left, y + bh / 2 - r);
        ctx.lineTo(left, y - bh / 2 + r);
        ctx.quadraticCurveTo(left, y - bh / 2, left + r, y - bh / 2);
        ctx.closePath();
        ctx.fillStyle   = color;
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)';
        ctx.lineWidth   = 1 * ratio;
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = NA_LABEL_TEXT;
        ctx.fillText(text, left + bw / 2, y + ratio * 0.5);
        ctx.restore();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Overlay Rendering
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__Render(ctx) {
        var key = Na__ImageViewerPerspective__Key();
        if (!ctx || !key) return;
        var st    = na_stateByKey[key];
        var an    = na_analysisByKey[key] || null;
        var ratio = na_core.getRatio();

        if (na_panelOpen && na_showGrid && an && an.cal && an.cal.ok) Na__ImageViewerPerspective__DrawGrid(ctx, ratio, an.cal);
        if (st && na_showGuideLines) Na__ImageViewerPerspective__DrawUserGuides(ctx, ratio, st, an);
        if (st) {
            if (na_panelOpen) {
                st.lines.forEach(function(line) { Na__ImageViewerPerspective__DrawRefLine(ctx, ratio, line, st, an); });
            }
            st.meas.forEach(function(m, i) {
                Na__ImageViewerPerspective__DrawMeasurement(ctx, ratio, m, an && an.results ? an.results[i] : null, an ? an.cal : null);
            });
        }
        if (na_panelOpen) {
            Na__ImageViewerPerspective__DrawPending(ctx, ratio, an);
            Na__ImageViewerPerspective__DrawLoupe(ctx, ratio, st);
        }
    }

    function Na__ImageViewerPerspective__DrawRefLine(ctx, ratio, line, st, an) {
        var a        = Na__ImageViewerPerspective__ToScreen(line.a);
        var b        = Na__ImageViewerPerspective__ToScreen(line.b);
        var color    = NA_AXIS_COLOR[line.axis];
        var diag     = Na__ImageViewerPerspective__LineDiag(an, line.id);
        var flagged  = !!(diag && diag.flagged);
        var selected = !!(na_selected && na_selected.kind === 'line' && na_selected.id === line.id);

        Na__ImageViewerPerspective__StrokePath(ctx, ratio, [a, b], color, selected ? 2.6 : 2, flagged ? [7, 4] : null, selected);
        Na__ImageViewerPerspective__DrawHandle(ctx, ratio, a, color);
        Na__ImageViewerPerspective__DrawHandle(ctx, ratio, b, color);

        if (flagged || selected) {
            var text = Na__ImageViewerPerspective__LineName(line, st);
            if (diag) text += flagged ? ' \u00b7 ' + Math.abs(diag.residualPx).toFixed(1) + ' px off' : ' \u00b7 fits ' + Math.abs(diag.residualPx).toFixed(1) + ' px';
            Na__ImageViewerPerspective__DrawLabel(ctx, ratio, (a.x + b.x) / 2, (a.y + b.y) / 2 - 14 * ratio, text, color);
        }
    }

    // Arc in the measured plane, sized to about NA_ARC_RADIUS_PX on screen.
    function Na__ImageViewerPerspective__ArcPoints(cal, draw) {
        var C  = draw.centre;
        var ua = na_vec.unit(draw.dirA);
        var step = draw.armLen * 0.01;
        if (!(step > 0)) return [];
        var c0 = na_solver.project(cal, C);
        var c1 = na_solver.project(cal, na_vec.add(C, na_vec.scale(ua, step)));
        if (!c0 || !c1) return [];
        var imgPerUnit = Math.sqrt((c1.x - c0.x) * (c1.x - c0.x) + (c1.y - c0.y) * (c1.y - c0.y)) / step;
        if (!(imgPerUnit > 0)) return [];
        var wantImg = NA_ARC_RADIUS_PX * na_core.getRatio() / na_core.getZoom();
        var rho = Math.min(wantImg / imgPerUnit, draw.armLen * 0.6);
        return na_solver.arcPolyline(cal, C, draw.dirA, draw.dirB, rho, 28);
    }

    function Na__ImageViewerPerspective__DrawMeasurement(ctx, ratio, m, res, cal) {
        var pts      = m.pts.map(Na__ImageViewerPerspective__ToScreen);
        var ok       = !!(res && res.ok);
        var color    = ok ? NA_MEAS_COLOR : NA_RAW_COLOR;
        var selected = !!(na_selected && na_selected.kind === 'meas' && na_selected.id === m.id);

        Na__ImageViewerPerspective__StrokePath(ctx, ratio, pts, color, selected ? 2.8 : 2.4, null, selected);

        var labelAt = null;
        if (ok && res.draw) {
            if (m.kind === 'pitch' && res.draw.footPt) {
                var foot = Na__ImageViewerPerspective__ToScreen(res.draw.footPt);
                Na__ImageViewerPerspective__StrokePath(ctx, ratio, [pts[res.draw.lo], foot, pts[res.draw.hi]], color, 1.4, [6, 4], false);
            }
            var arc = Na__ImageViewerPerspective__ArcPoints(cal, res.draw).map(Na__ImageViewerPerspective__ToScreen);
            if (arc.length >= 2) {
                Na__ImageViewerPerspective__StrokePath(ctx, ratio, arc, color, 1.8, null, false);
                var mid    = arc[Math.floor(arc.length / 2)];
                var centre = pts[m.kind === 'pitch' ? res.draw.lo : 1];
                var dx = mid.x - centre.x, dy = mid.y - centre.y, dl = Math.sqrt(dx * dx + dy * dy) || 1;
                labelAt = { x: mid.x + dx / dl * 30 * ratio, y: mid.y + dy / dl * 16 * ratio };
            }
        }
        if (!labelAt) {
            var at = m.kind === 'angle' ? pts[1] : { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2 };
            labelAt = { x: at.x + 26 * ratio, y: at.y - 16 * ratio };
        }

        if (na_panelOpen) pts.forEach(function(p) { Na__ImageViewerPerspective__DrawHandle(ctx, ratio, p, color); });

        var text;
        if (ok) {
            var hw = Na__ImageViewerPerspective__HalfWidth(res);
            text = Na__ImageViewerPerspective__Deg(res.value) + (hw !== null ? ' \u00b1' + hw.toFixed(1) + '\u00b0' : '');
        } else if (res && res.raw2d !== null && res.raw2d !== undefined) {
            text = Na__ImageViewerPerspective__Deg(res.raw2d) + ' 2D';
        } else {
            text = '\u2026';
        }
        Na__ImageViewerPerspective__DrawLabel(ctx, ratio, labelAt.x, labelAt.y, text, selected ? '#b36b00' : color);
    }

    // The pointer, or the point it has snapped to, while placing points.
    function Na__ImageViewerPerspective__CursorScreen() {
        if (!na_cursor || (na_press && na_press.panning)) return null;
        return na_snap ? na_snap.screen : na_cursor;
    }

    function Na__ImageViewerPerspective__DrawPending(ctx, ratio, an) {
        if (!na_mode) return;
        if (na_mode === 'guide') { Na__ImageViewerPerspective__DrawGuidePreview(ctx, ratio, an); return; }
        var color = NA_AXIS_COLOR[na_mode] || NA_MEAS_COLOR;
        var pts   = na_pending.map(Na__ImageViewerPerspective__ToScreen);
        var cur   = Na__ImageViewerPerspective__CursorScreen();
        if (cur) pts.push(cur);
        if (pts.length >= 2) Na__ImageViewerPerspective__StrokePath(ctx, ratio, pts, color, 1.8, [6, 5], false);
        na_pending.forEach(function(p) { Na__ImageViewerPerspective__DrawHandle(ctx, ratio, Na__ImageViewerPerspective__ToScreen(p), color); });

        if ((na_mode === 'pitch' || na_mode === 'angle') && cur) {
            var need = na_mode === 'angle' ? 3 : 2;
            if (na_pending.length !== need - 1) return;
            var m = { kind: na_mode, plane: na_plane, pts: na_pending.concat([na_core.screenToImg(cur.x, cur.y)]) };
            var r = na_solver.measure(an && an.cal && an.cal.ok ? an.cal : null, m);
            var text = r.ok ? Na__ImageViewerPerspective__Deg(r.value) : (r.raw2d !== null ? Na__ImageViewerPerspective__Deg(r.raw2d) + ' 2D' : '');
            if (text) Na__ImageViewerPerspective__DrawLabel(ctx, ratio, cur.x + 16 * ratio, cur.y - 24 * ratio, text, r.ok ? NA_MEAS_COLOR : NA_RAW_COLOR, 'left');
        }
    }

    // Perspective grid: faint lines toward the vanishing points of the
    // selected plane's two axes. If they run with the brick courses and the
    // vertical edges, the calibration is right.
    function Na__ImageViewerPerspective__DrawGrid(ctx, ratio, cal) {
        var plane = na_plane;
        if (na_selected && na_selected.kind === 'meas') {
            var m = Na__ImageViewerPerspective__FindItem('meas', na_selected.id);
            if (m) plane = m.plane;
        }
        var size = na_core.getImageSize();
        var hw = size.w / 2, hh = size.h / 2;
        var corners = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]].map(function(c) { return na_core.imgToScreen({ x: c[0], y: c[1] }); });

        ctx.save();
        ctx.beginPath();
        ctx.moveTo(corners[0].x, corners[0].y);
        for (var i = 1; i < 4; i++) ctx.lineTo(corners[i].x, corners[i].y);
        ctx.closePath();
        ctx.clip();
        na_solver.planeAxes[plane].forEach(function(axis) {
            var segs = Na__ImageViewerPerspective__FanSegments(na_solver.vanishingPoint(cal, axis), size, 18);
            ctx.beginPath();
            segs.forEach(function(s) {
                var a = na_core.imgToScreen(s.a), b = na_core.imgToScreen(s.b);
                ctx.moveTo(a.x, a.y);
                ctx.lineTo(b.x, b.y);
            });
            ctx.globalAlpha = 0.45;
            ctx.strokeStyle = NA_AXIS_COLOR[axis];
            ctx.lineWidth   = 1 * ratio;
            ctx.stroke();
        });
        ctx.restore();
    }

    // Image-space segments fanning from a homogeneous vanishing point across
    // the photo (parallel lines when the point is very far away).
    function Na__ImageViewerPerspective__FanSegments(vp, size, count) {
        var hw = size.w / 2, hh = size.h / 2;
        var diag = Math.sqrt(size.w * size.w + size.h * size.h);
        var out = [];
        var far = Math.abs(vp.w) < 1e-12 || Math.sqrt(vp.x * vp.x + vp.y * vp.y) / Math.abs(vp.w) > 40 * diag;
        var i;

        if (far) {
            var dl = Math.sqrt(vp.x * vp.x + vp.y * vp.y) || 1;
            var dx = vp.x / dl, dy = vp.y / dl, px = -dy, py = dx;
            var ext = Math.abs(px) * hw + Math.abs(py) * hh;
            for (i = 1; i < count; i++) {
                var t = -ext + 2 * ext * i / count;
                out.push({ a: { x: px * t - dx * diag, y: py * t - dy * diag }, b: { x: px * t + dx * diag, y: py * t + dy * diag } });
            }
            return out;
        }

        var X = vp.x / vp.w, Y = vp.y / vp.w;
        var reach = Math.sqrt(X * X + Y * Y) + diag;
        var lo = Infinity, hi = -Infinity;
        var base = Math.atan2(-Y, -X);
        if (Math.abs(X) <= hw && Math.abs(Y) <= hh) {
            lo = -Math.PI; hi = Math.PI; count *= 2;
        } else {
            [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]].forEach(function(c) {
                var d = Math.atan2(c[1] - Y, c[0] - X) - base;
                while (d > Math.PI)  d -= 2 * Math.PI;
                while (d < -Math.PI) d += 2 * Math.PI;
                lo = Math.min(lo, d);
                hi = Math.max(hi, d);
            });
        }
        for (i = 1; i < count; i++) {
            var ang = base + lo + (hi - lo) * i / count;
            out.push({ a: { x: X, y: Y }, b: { x: X + Math.cos(ang) * reach, y: Y + Math.sin(ang) * reach } });
        }
        return out;
    }

    // A magnifier beside the pointer while placing or dragging a point.
    function Na__ImageViewerPerspective__DrawLoupe(ctx, ratio, st) {
        var target = null;
        if (na_drag && na_drag.moved) target = Na__ImageViewerPerspective__ToScreen(Na__ImageViewerPerspective__RefPoint(na_drag.ref));
        else if (na_mode) target = Na__ImageViewerPerspective__CursorScreen();
        if (!target) return;

        var img  = na_core.getImage();
        var size = na_core.getImageSize();
        if (!img || !img.complete || !size.w) return;

        var R    = NA_LOUPE_RADIUS_PX * ratio;
        var w    = na_canvas.width, h = na_canvas.height;
        var off  = R + 26 * ratio;
        var lx   = target.x - off, ly = target.y - off;
        if (lx - R < 6 * ratio) lx = target.x + off;
        if (ly - R < 6 * ratio) ly = target.y + off;
        if (lx + R > w - 6 * ratio) lx = target.x - off;
        if (ly + R > h - 6 * ratio) ly = target.y - off;

        var gain = Math.min(12, Math.max(1.5, na_core.getZoom() * NA_LOUPE_GAIN));
        var ip   = na_core.screenToImg(target.x, target.y);

        ctx.save();
        ctx.beginPath();
        ctx.arc(lx, ly, R, 0, Math.PI * 2);
        ctx.closePath();
        ctx.fillStyle = '#20242a';
        ctx.fill();
        ctx.clip();
        ctx.translate(lx, ly);
        ctx.rotate(na_core.getRotation());
        ctx.scale(gain, gain);
        ctx.translate(-ip.x, -ip.y);
        ctx.imageSmoothingEnabled = gain < 3;
        ctx.drawImage(img, -size.w / 2, -size.h / 2);

        // Lines inside the loupe, drawn in image space at a hairline width.
        ctx.lineCap = 'round';
        ctx.lineWidth = 1.4 * ratio / gain;
        if (st) {
            st.lines.forEach(function(line) {
                ctx.strokeStyle = NA_AXIS_COLOR[line.axis];
                ctx.beginPath(); ctx.moveTo(line.a.x, line.a.y); ctx.lineTo(line.b.x, line.b.y); ctx.stroke();
            });
            st.meas.forEach(function(m) {
                ctx.strokeStyle = NA_MEAS_COLOR;
                ctx.beginPath();
                m.pts.forEach(function(p, i) { if (i) ctx.lineTo(p.x, p.y); else ctx.moveTo(p.x, p.y); });
                ctx.stroke();
            });
            var loupeGuides = Na__ImageViewerPerspective__VisibleGuides(st, na_analysisByKey[Na__ImageViewerPerspective__Key()] || null, null);
            ctx.setLineDash([6 / gain * ratio, 4 / gain * ratio]);
            loupeGuides.forEach(function(v) {
                ctx.strokeStyle = Na__ImageViewerPerspective__GuideColor(v.guide);
                ctx.beginPath(); ctx.moveTo(v.seg.a.x, v.seg.a.y); ctx.lineTo(v.seg.b.x, v.seg.b.y); ctx.stroke();
            });
            ctx.setLineDash([]);
        }
        if (na_mode && na_pending.length) {
            ctx.strokeStyle = na_mode === 'guide' ? NA_GUIDE_COLOR.free : (NA_AXIS_COLOR[na_mode] || NA_MEAS_COLOR);
            ctx.setLineDash([6 / gain * ratio, 4 / gain * ratio]);
            ctx.beginPath();
            na_pending.forEach(function(p, i) { if (i) ctx.lineTo(p.x, p.y); else ctx.moveTo(p.x, p.y); });
            ctx.lineTo(ip.x, ip.y);
            ctx.stroke();
        }
        ctx.restore();

        ctx.save();
        ctx.beginPath();
        ctx.arc(lx, ly, R, 0, Math.PI * 2);
        ctx.lineWidth   = 3 * ratio;
        ctx.strokeStyle = 'rgba(0, 0, 0, 0.45)';
        ctx.stroke();
        ctx.lineWidth   = 1.6 * ratio;
        ctx.strokeStyle = '#ffffff';
        ctx.stroke();
        var gap = 5 * ratio, arm = 16 * ratio;
        [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(function(d) {
            ctx.beginPath();
            ctx.moveTo(lx + d[0] * gap, ly + d[1] * gap);
            ctx.lineTo(lx + d[0] * arm, ly + d[1] * arm);
            ctx.lineWidth = 3 * ratio; ctx.strokeStyle = 'rgba(0, 0, 0, 0.55)'; ctx.stroke();
            ctx.lineWidth = 1.2 * ratio; ctx.strokeStyle = '#ffffff'; ctx.stroke();
        });
        ctx.restore();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Guides
    // -------------------------------------------------------------------------
    // A guide is an infinite 3D line through a clicked point: along the red,
    // green or blue axis, parallel to a measured pitch, at a typed pitch on a
    // wall, or (before calibration) straight through two clicked points. Its
    // direction is re-read from the calibration whenever it is drawn, so it
    // follows the photo as lines are added; the vanishing point at creation is
    // kept for when the calibration is lost.

    function Na__ImageViewerPerspective__GuideLabel(g, st) {
        if (NA_GUIDE_AXIS_NAME[g.dir]) return NA_GUIDE_AXIS_NAME[g.dir];
        if (g.dir === 'par') {
            var m = null;
            if (st) st.meas.forEach(function(x) { if (x.id === g.measId) m = x; });
            return 'Parallel to ' + (m ? Na__ImageViewerPerspective__MeasName(m, st) : 'a pitch');
        }
        if (g.dir === 'tilt') return Na__ImageViewerPerspective__Deg(g.deg) + ' on ' + NA_PLANE_NAME[g.plane];
        return 'Free guide';
    }

    function Na__ImageViewerPerspective__GuideColor(g) {
        return NA_GUIDE_COLOR[g.dir] || NA_GUIDE_COLOR.free;
    }

    function Na__ImageViewerPerspective__MeasResult(an, st, measId) {
        if (!an || !an.results || !st) return null;
        for (var i = 0; i < st.meas.length; i++) if (st.meas[i].id === measId) return an.results[i] || null;
        return null;
    }

    // The guide's vanishing point from the current calibration, else the one
    // kept when it was made.
    function Na__ImageViewerPerspective__GuideVp(g, an, st) {
        var cal = an && an.cal && an.cal.ok ? an.cal : null;
        if (cal && NA_GUIDE_AXIS_NAME[g.dir]) return na_solver.vanishingPoint(cal, g.dir);
        if (cal && g.dir === 'tilt') {
            var d = na_solver.wallDirection(cal, g.plane, g.deg, g.side);
            if (d) return na_solver.directionVanishingPoint(cal, d);
        }
        if (cal && g.dir === 'par') {
            var dir = na_solver.measurementDirection(Na__ImageViewerPerspective__MeasResult(an, st, g.measId));
            if (dir) return na_solver.directionVanishingPoint(cal, dir);
        }
        return g.vp || null;
    }

    function Na__ImageViewerPerspective__GuideSegment(g, an, st, size) {
        if (g.dir === 'free') return na_solver.freeSegment(g.p, g.q, size);
        return na_solver.guideSegment(g.p, Na__ImageViewerPerspective__GuideVp(g, an, st), size);
    }

    // Guides on this photo with their visible segments (image space).
    function Na__ImageViewerPerspective__VisibleGuides(st, an, exclude) {
        var out = [];
        var size = na_core.getImageSize();
        if (!st || !na_showGuideLines || !size.w) return out;
        (st.guides || []).forEach(function(g) {
            if (exclude && exclude.item === g) return;
            var seg = Na__ImageViewerPerspective__GuideSegment(g, an, st, size);
            if (seg) out.push({ guide: g, seg: seg });
        });
        return out;
    }

    // Directions a new guide can follow from its first point.
    function Na__ImageViewerPerspective__GuideCandidates(an, st) {
        var cal = an && an.cal && an.cal.ok ? an.cal : null;
        if (!cal) return [];
        var out = ['x', 'y', 'z'].map(function(axis) {
            return { dir: axis, label: NA_GUIDE_AXIS_NAME[axis], vp: na_solver.vanishingPoint(cal, axis) };
        });
        if (st) st.meas.forEach(function(m, i) {
            if (m.kind !== 'pitch') return;
            var d = na_solver.measurementDirection(an.results ? an.results[i] : null);
            if (d) out.push({ dir: 'par', measId: m.id, label: 'Parallel to ' + Na__ImageViewerPerspective__MeasName(m, st), vp: na_solver.directionVanishingPoint(cal, d) });
        });
        if (na_guideAngle && na_solver.planeLevelAxis[na_plane]) {
            [1, -1].forEach(function(side) {
                var d = na_solver.wallDirection(cal, na_plane, na_guideAngle, side);
                if (d) out.push({ dir: 'tilt', plane: na_plane, deg: na_guideAngle, side: side,
                    label: Na__ImageViewerPerspective__Deg(na_guideAngle) + ' on ' + NA_PLANE_NAME[na_plane], vp: na_solver.directionVanishingPoint(cal, d) });
            });
        }
        return out;
    }

    function Na__ImageViewerPerspective__InferAt(anchor, pointerImg, an, st) {
        var inf = na_solver.inferGuide(anchor, pointerImg, Na__ImageViewerPerspective__GuideCandidates(an, st), NA_INFER_DEG);
        return inf ? inf.candidate : null;
    }

    function Na__ImageViewerPerspective__GuideFromCandidate(c, anchor) {
        var g = { dir: c.dir, p: anchor, vp: { x: c.vp.x, y: c.vp.y, w: c.vp.w } };
        if (c.dir === 'par') g.measId = c.measId;
        if (c.dir === 'tilt') { g.plane = c.plane; g.deg = c.deg; g.side = c.side; }
        return g;
    }

    // Dashed like a SketchUp guide, each dash with a light halo.
    function Na__ImageViewerPerspective__DrawGuideLine(ctx, ratio, seg, color, widthPx, selected) {
        var a = Na__ImageViewerPerspective__ToScreen(seg.a), b = Na__ImageViewerPerspective__ToScreen(seg.b);
        ctx.save();
        ctx.lineCap = 'butt';
        ctx.setLineDash(NA_GUIDE_DASH.map(function(d) { return d * ratio; }));
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.strokeStyle = selected ? NA_SELECT_COLOR : 'rgba(255, 255, 255, 0.75)';
        ctx.lineWidth   = (widthPx + (selected ? 3 : 2)) * ratio;
        ctx.stroke();
        ctx.strokeStyle = color;
        ctx.lineWidth   = widthPx * ratio;
        ctx.stroke();
        ctx.restore();
    }

    function Na__ImageViewerPerspective__DrawUserGuides(ctx, ratio, st, an) {
        var visible = Na__ImageViewerPerspective__VisibleGuides(st, an, null);
        visible.forEach(function(v) {
            var selected = !!(na_selected && na_selected.kind === 'guide' && na_selected.id === v.guide.id);
            Na__ImageViewerPerspective__DrawGuideLine(ctx, ratio, v.seg, Na__ImageViewerPerspective__GuideColor(v.guide), selected ? 1.8 : 1.3, selected);
        });
        if (!na_panelOpen) return;
        visible.forEach(function(v) {
            [v.guide.p, v.guide.q].forEach(function(pt) {
                if (!pt) return;
                var s = Na__ImageViewerPerspective__ToScreen(pt);
                ctx.save();
                ctx.beginPath();
                ctx.arc(s.x, s.y, 3.5 * ratio, 0, Math.PI * 2);
                ctx.fillStyle   = '#ffffff';
                ctx.strokeStyle = Na__ImageViewerPerspective__GuideColor(v.guide);
                ctx.lineWidth   = 1.6 * ratio;
                ctx.fill();
                ctx.stroke();
                ctx.restore();
            });
        });
    }

    // While the Guide tool is active: the guide the next click would make.
    function Na__ImageViewerPerspective__DrawGuidePreview(ctx, ratio, an) {
        var cur = Na__ImageViewerPerspective__CursorScreen();
        if (!cur) return;
        var key = Na__ImageViewerPerspective__Key();
        var st  = key ? na_stateByKey[key] : null;
        var curImg = na_core.screenToImg(cur.x, cur.y);
        var preview = null, label = '';
        if (na_guideAxis !== 'auto') {
            if (an && an.cal && an.cal.ok) {
                preview = { dir: na_guideAxis, p: curImg, vp: na_solver.vanishingPoint(an.cal, na_guideAxis) };
                label = NA_GUIDE_AXIS_NAME[na_guideAxis];
            }
        } else if (na_pending.length === 1) {
            var a  = na_pending[0];
            var as = Na__ImageViewerPerspective__ToScreen(a);
            if (na_inferred) {
                preview = Na__ImageViewerPerspective__GuideFromCandidate(na_inferred, a);
                label = na_inferred.label;
            } else if (Math.sqrt((as.x - cur.x) * (as.x - cur.x) + (as.y - cur.y) * (as.y - cur.y)) >= NA_INFER_MIN_PX * ratio) {
                preview = { dir: 'free', p: a, q: curImg };
                label = 'Free guide';
            }
            Na__ImageViewerPerspective__StrokePath(ctx, ratio, [as, cur], NA_GUIDE_COLOR.free, 1, null, false);
            Na__ImageViewerPerspective__DrawHandle(ctx, ratio, as, NA_GUIDE_COLOR.free);
        }
        if (preview) {
            var seg = Na__ImageViewerPerspective__GuideSegment(preview, an, st, na_core.getImageSize());
            if (seg) Na__ImageViewerPerspective__DrawGuideLine(ctx, ratio, seg, Na__ImageViewerPerspective__GuideColor(preview), 2, false);
        }
        if (label) Na__ImageViewerPerspective__DrawLabel(ctx, ratio, cur.x + 16 * ratio, cur.y - 24 * ratio, label, preview ? Na__ImageViewerPerspective__GuideColor(preview) : NA_GUIDE_COLOR.free, 'left');
    }

    // Snap targets near a canvas point: endpoints, guide points and
    // intersections (guide with guide, guide with a drawn line) first, then
    // the nearest point on a guide. exclude is a handle being dragged; its
    // item is left out so it cannot snap to itself.
    function Na__ImageViewerPerspective__SnapAt(cx, cy, exclude) {
        var key = Na__ImageViewerPerspective__Key();
        var st  = key ? na_stateByKey[key] : null;
        if (!st) return null;
        var an    = na_analysisByKey[key] || null;
        var ratio = na_core.getRatio();
        var skip  = exclude ? exclude.item : null;
        var best = null, bestD = NA_SNAP_PX * ratio;
        function offer(img, kind, label) {
            var s = na_core.imgToScreen(img);
            var d = Math.sqrt((s.x - cx) * (s.x - cx) + (s.y - cy) * (s.y - cy));
            if (d <= bestD) { bestD = d; best = { img: { x: img.x, y: img.y }, screen: s, kind: kind, label: label }; }
        }

        var drawn = [];   // segments of drawn lines and measurements, for crossings with guides
        st.meas.forEach(function(m) {
            if (m === skip) return;
            m.pts.forEach(function(q) { offer(q, 'endpoint', 'Endpoint'); });
            for (var i = 0; i + 1 < m.pts.length; i++) drawn.push({ a: m.pts[i], b: m.pts[i + 1] });
        });
        if (na_panelOpen) st.lines.forEach(function(l) {
            if (l === skip) return;
            offer(l.a, 'endpoint', 'Endpoint');
            offer(l.b, 'endpoint', 'Endpoint');
            drawn.push({ a: l.a, b: l.b });
        });

        var guides = Na__ImageViewerPerspective__VisibleGuides(st, an, exclude);
        guides.forEach(function(v) {
            offer(v.guide.p, 'endpoint', 'Guide point');
            if (v.guide.q) offer(v.guide.q, 'endpoint', 'Guide point');
        });
        for (var i = 0; i < guides.length; i++) {
            for (var j = i + 1; j < guides.length; j++) {
                var x = na_solver.segmentIntersection(guides[i].seg, guides[j].seg);
                if (x) offer(x, 'intersection', 'Intersection');
            }
            for (var k = 0; k < drawn.length; k++) {
                var y = na_solver.segmentIntersection(guides[i].seg, drawn[k]);
                if (y) offer(y, 'intersection', 'Intersection');
            }
        }
        if (best) return best;

        var img = na_core.screenToImg(cx, cy);
        var on = null, onD = NA_ON_GUIDE_PX * ratio;
        guides.forEach(function(v) {
            var c = na_solver.closestOnSegment(img, v.seg).point;
            var s = na_core.imgToScreen(c);
            var d = Math.sqrt((s.x - cx) * (s.x - cx) + (s.y - cy) * (s.y - cy));
            if (d <= onD) { onD = d; on = { img: c, screen: s, kind: 'guide', label: 'On guide' }; }
        });
        return on;
    }

    // Snap points offered through the Core, for the Measure tool and anyone
    // else placing points on the photo.
    function Na__ImageViewerPerspective__ProvideSnap(cx, cy) {
        return Na__ImageViewerPerspective__SnapAt(cx, cy, null);
    }

    function Na__ImageViewerPerspective__UsesSnap(mode) {
        return mode === 'guide' || mode === 'pitch' || mode === 'angle';
    }

    // Snap and read the guide direction at the pointer.
    function Na__ImageViewerPerspective__UpdateSnap() {
        var mine = Na__ImageViewerPerspective__Interactive() && !!na_mode;
        na_snap = mine && na_cursor && Na__ImageViewerPerspective__UsesSnap(na_mode) && !(na_press && na_press.panning)
            ? Na__ImageViewerPerspective__SnapAt(na_cursor.x, na_cursor.y, null) : null;
        if (mine && typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(na_snap);

        na_inferred = null;
        if (na_mode !== 'guide' || na_guideAxis !== 'auto' || na_pending.length !== 1) return;
        var cur = Na__ImageViewerPerspective__CursorScreen();
        if (!cur) return;
        var a = Na__ImageViewerPerspective__ToScreen(na_pending[0]);
        if (Math.sqrt((cur.x - a.x) * (cur.x - a.x) + (cur.y - a.y) * (cur.y - a.y)) < NA_INFER_MIN_PX * na_core.getRatio()) return;
        var key = Na__ImageViewerPerspective__Key();
        na_inferred = Na__ImageViewerPerspective__InferAt(na_pending[0], na_core.screenToImg(cur.x, cur.y), na_analysisByKey[key] || null, na_stateByKey[key] || null);
    }

    function Na__ImageViewerPerspective__PlaceGuidePoint(key) {
        var an = na_analysisByKey[key] || null;
        var st = na_stateByKey[key] || null;
        var anchor = na_pending[0];
        var guide;
        if (na_guideAxis !== 'auto') {
            if (!(an && an.cal && an.cal.ok)) {
                na_pending = [];
                Na__ImageViewerPerspective__ShowGuideHint('Calibrate the photo (step 1) before locking a guide to an axis. Auto still makes straight guides.');
                na_core.requestDraw();
                return;
            }
            guide = { dir: na_guideAxis, p: anchor, vp: na_solver.vanishingPoint(an.cal, na_guideAxis) };
        } else if (na_pending.length < 2) {
            Na__ImageViewerPerspective__RefreshPanel();
            na_core.requestDraw();
            return;
        } else {
            var c = Na__ImageViewerPerspective__InferAt(anchor, na_pending[1], an, st);
            guide = c ? Na__ImageViewerPerspective__GuideFromCandidate(c, anchor) : { dir: 'free', p: anchor, q: na_pending[1] };
        }
        na_core.pushHistory();
        guide.id = na_nextId++;
        Na__ImageViewerPerspective__State(key).guides.push(guide);
        na_pending  = [];
        na_inferred = null;
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__SetGuideAxis(axis) {
        na_guideAxis = axis;
        na_inferred  = null;
        if (axis !== 'auto') na_pending = [];
        if (na_mode !== 'guide') Na__ImageViewerPerspective__SetMode('guide');
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    // A bare number is a pitch in degrees, as for the Pitch tool; level and
    // plumb guides are the axes, so 0 and 90 are refused with that named.
    function Na__ImageViewerPerspective__ParseGuideAngle(raw) {
        var s = String(raw === undefined || raw === null ? '' : raw).trim().toLowerCase().replace(/\s+/g, '').replace(/(\u00b0|degrees|degree|deg)$/, '');
        if (!s) return { ok: true, deg: null };
        if (!/^[0-9]*\.?[0-9]+$/.test(s)) return { ok: false, message: 'Type a pitch in degrees, e.g. 45, or leave it empty.' };
        var deg = parseFloat(s);
        if (!(deg > 0 && deg < 90)) {
            return { ok: false, message: deg + '\u00b0 is not a slope. Type 1 to 89, e.g. 45; level and plumb guides are the Red, Green and Blue axes.' };
        }
        return { ok: true, deg: deg };
    }

    function Na__ImageViewerPerspective__OnGuideAngleCommit() {
        if (!na_guideAngleInput) return;
        var parsed = Na__ImageViewerPerspective__ParseGuideAngle(na_guideAngleInput.value);
        na_guideAngleInput.classList.toggle('naImageViewer__PerspInput--error', !parsed.ok);
        na_guideAngleError = parsed.ok ? '' : parsed.message;
        if (parsed.ok) na_guideAngle = parsed.deg;
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__ClearGuides() {
        var key = Na__ImageViewerPerspective__Key();
        var st  = na_stateByKey[key];
        if (!st || !st.guides || !st.guides.length) return;
        na_core.pushHistory();
        st.guides = [];
        if (na_selected && na_selected.kind === 'guide') Na__ImageViewerPerspective__Select(null);
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__ShowGuideHint(text) {
        if (!na_guideHint) return;
        na_guideHint.textContent = text || '';
        na_guideHint.dataset.sticky = text ? '1' : '';
    }

    function Na__ImageViewerPerspective__GuideHintText() {
        if (na_guideAngleError) return na_guideAngleError;
        if (na_mode !== 'guide') return 'Guides show whether window heads, sills and eaves line up, and give dimensions something to snap to. Press T or click Guide.';
        var an = Na__ImageViewerPerspective__Analysis();
        if (!(an && an.cal && an.cal.ok)) return 'Calibrate the photo (step 1) for red, green and blue guides. Until then two clicks make a straight guide through both points.';
        if (na_guideAxis !== 'auto') return 'Click a point to put a ' + NA_GUIDE_AXIS_NAME[na_guideAxis].toLowerCase() + ' guide through it. \u2193 or Auto unlocks.';
        if (na_pending.length) return 'Move along the direction you want and click. Esc cancels.';
        return 'Click a point, move along a direction and click again: the guide follows red, green or blue, a measured pitch, or the pitch typed above. Arrow keys lock an axis: \u2192 red, \u2190 green, \u2191 blue, \u2193 auto.';
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Hit Testing
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__RefPoint(ref) {
        return ref.kind === 'meas' ? ref.item.pts[ref.index] : ref.item[ref.end];
    }

    function Na__ImageViewerPerspective__SetPoint(ref, pt) {
        if (ref.kind === 'meas') ref.item.pts[ref.index] = pt;
        else                     ref.item[ref.end] = pt;
    }

    // Nearest handle under the pointer. Where handles coincide (a verge end
    // on an apex corner), the selected item's handle wins, then the newest.
    function Na__ImageViewerPerspective__HitHandle(p) {
        var st = na_stateByKey[Na__ImageViewerPerspective__Key()];
        if (!st) return null;
        var tolerance = NA_HIT_PX * na_core.getRatio();
        var best = null, bestD = tolerance, bestSelected = false;
        function consider(pt, ref) {
            var s = Na__ImageViewerPerspective__ToScreen(pt);
            var d = Math.sqrt((s.x - p.x) * (s.x - p.x) + (s.y - p.y) * (s.y - p.y));
            if (d > tolerance) return;
            var selected = !!(na_selected && na_selected.kind === ref.kind && na_selected.id === ref.item.id);
            if (bestSelected && !selected) return;
            if (selected && !bestSelected) { bestD = d; best = ref; bestSelected = true; return; }
            if (d <= bestD) { bestD = d; best = ref; }
        }
        st.meas.forEach(function(m) {
            m.pts.forEach(function(pt, i) { consider(pt, { kind: 'meas', item: m, index: i }); });
        });
        st.lines.forEach(function(l) {
            consider(l.a, { kind: 'line', item: l, end: 'a' });
            consider(l.b, { kind: 'line', item: l, end: 'b' });
        });
        if (na_showGuideLines) (st.guides || []).forEach(function(g) {
            consider(g.p, { kind: 'guide', item: g, end: 'p' });
            if (g.q) consider(g.q, { kind: 'guide', item: g, end: 'q' });
        });
        return best;
    }

    function Na__ImageViewerPerspective__DistanceToSegment(p, a, b) {
        var dx = b.x - a.x, dy = b.y - a.y;
        var l2 = dx * dx + dy * dy;
        var t  = l2 > 0 ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)) : 0;
        var ex = p.x - (a.x + t * dx), ey = p.y - (a.y + t * dy);
        return Math.sqrt(ex * ex + ey * ey);
    }

    function Na__ImageViewerPerspective__HitItem(p) {
        var st = na_stateByKey[Na__ImageViewerPerspective__Key()];
        if (!st) return null;
        var best = null, bestD = NA_HIT_PX * na_core.getRatio();
        st.meas.forEach(function(m) {
            var s = m.pts.map(Na__ImageViewerPerspective__ToScreen);
            for (var i = 0; i + 1 < s.length; i++) {
                var d = Na__ImageViewerPerspective__DistanceToSegment(p, s[i], s[i + 1]);
                if (d <= bestD) { bestD = d; best = { kind: 'meas', id: m.id }; }
            }
        });
        st.lines.forEach(function(l) {
            var d = Na__ImageViewerPerspective__DistanceToSegment(p, Na__ImageViewerPerspective__ToScreen(l.a), Na__ImageViewerPerspective__ToScreen(l.b));
            if (d <= bestD) { bestD = d; best = { kind: 'line', id: l.id }; }
        });
        if (best) return best;
        // Guides cross the whole photo, so they come last.
        Na__ImageViewerPerspective__VisibleGuides(st, na_analysisByKey[Na__ImageViewerPerspective__Key()] || null, null).forEach(function(v) {
            var d = Na__ImageViewerPerspective__DistanceToSegment(p, Na__ImageViewerPerspective__ToScreen(v.seg.a), Na__ImageViewerPerspective__ToScreen(v.seg.b));
            if (d <= bestD) { bestD = d; best = { kind: 'guide', id: v.guide.id }; }
        });
        return best;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Modes, Selection And Editing
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__IsAxisMode(mode) {
        return mode === 'z' || mode === 'x' || mode === 'y';
    }

    // Another tool (e.g. Measure) took the canvas: stop drawing, keep the lines.
    function Na__ImageViewerPerspective__Release() {
        na_mode     = null;
        na_pending  = [];
        na_press    = null;
        na_drag     = null;
        na_selected = null;
        na_snap     = null;
        na_inferred = null;
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__Interactive() {
        if (!na_panelOpen) return false;
        var owner = na_core.getToolOwner();
        return !owner || owner === NA_TOOL_NAME;
    }

    function Na__ImageViewerPerspective__SetMode(mode) {
        if (!Na__ImageViewerPerspective__Key()) {
            Na__ImageViewerPerspective__ShowToolHint('Choose a folder of photos first.');
            return;
        }
        if (na_mode === mode) mode = null;
        if (mode === 'pitch' && na_plane === 'xy') {
            na_plane = 'xz';
            Na__ImageViewerPerspective__ShowToolHint('Pitch is measured on a wall, so the Red wall is selected.');
        }
        na_mode    = mode;
        na_pending = [];
        na_snap    = null;
        na_inferred = null;
        if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
        if (mode) na_core.claimTool(NA_TOOL_NAME, Na__ImageViewerPerspective__Release);
        else if (!na_selected) na_core.releaseTool(NA_TOOL_NAME);
        Na__ImageViewerPerspective__UpdateCursor(null);
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__Select(kind, id) {
        na_selected = kind ? { kind: kind, id: id } : null;
        if (kind === 'meas') {
            var m = Na__ImageViewerPerspective__FindItem('meas', id);
            if (m) na_plane = m.plane;
        }
        if (na_selected) na_core.claimTool(NA_TOOL_NAME, Na__ImageViewerPerspective__Release);
        else if (!na_mode) na_core.releaseTool(NA_TOOL_NAME);
    }

    function Na__ImageViewerPerspective__CurrentPrec() {
        return na_core.getRatio() / (na_core.getZoom() || 1);
    }

    function Na__ImageViewerPerspective__PlacePoint(p) {
        var key = Na__ImageViewerPerspective__Key();
        if (!key || !na_mode) return;
        var ratio = na_core.getRatio();
        var ip    = na_core.screenToImg(p.x, p.y);
        var size  = na_core.getImageSize();
        if (Math.abs(ip.x) > size.w / 2 || Math.abs(ip.y) > size.h / 2) {
            Na__ImageViewerPerspective__ShowToolHint('Click on the photo itself.');
            return;
        }
        var last = na_pending[na_pending.length - 1];
        if (last) {
            var ls = Na__ImageViewerPerspective__ToScreen(last);
            if (Math.sqrt((ls.x - p.x) * (ls.x - p.x) + (ls.y - p.y) * (ls.y - p.y)) < 3 * ratio) return;
        }
        na_pending.push({ x: ip.x, y: ip.y, prec: Na__ImageViewerPerspective__CurrentPrec() });
        if (na_mode === 'guide') { Na__ImageViewerPerspective__PlaceGuidePoint(key); return; }

        var need = na_mode === 'angle' ? 3 : 2;
        if (na_pending.length < need) {
            Na__ImageViewerPerspective__RefreshToolHint();
            na_core.requestDraw();
            return;
        }

        na_core.pushHistory();
        var st = Na__ImageViewerPerspective__State(key);
        var item;
        if (Na__ImageViewerPerspective__IsAxisMode(na_mode)) {
            item = { id: na_nextId++, axis: na_mode, a: na_pending[0], b: na_pending[1] };
            st.lines.push(item);
            na_selected = { kind: 'line', id: item.id };
        } else {
            item = { id: na_nextId++, kind: na_mode, plane: na_plane, pts: na_pending.slice(0, need) };
            st.meas.push(item);
            na_selected = { kind: 'meas', id: item.id };
        }
        na_pending = [];
        Na__ImageViewerPerspective__Changed(key);
    }

    function Na__ImageViewerPerspective__DeleteSelected() {
        var key = Na__ImageViewerPerspective__Key();
        var st  = na_stateByKey[key];
        if (!st || !na_selected) return;
        var sel = na_selected;
        na_core.pushHistory();
        if (sel.kind === 'line')       st.lines  = st.lines.filter(function(l) { return l.id !== sel.id; });
        else if (sel.kind === 'guide') st.guides = (st.guides || []).filter(function(g) { return g.id !== sel.id; });
        else                           st.meas   = st.meas.filter(function(m) { return m.id !== sel.id; });
        Na__ImageViewerPerspective__Select(null);
        Na__ImageViewerPerspective__Changed(key);
    }

    function Na__ImageViewerPerspective__DeleteMeasurement(id) {
        var key = Na__ImageViewerPerspective__Key();
        var st  = na_stateByKey[key];
        if (!st) return;
        na_core.pushHistory();
        st.meas = st.meas.filter(function(m) { return m.id !== id; });
        if (na_selected && na_selected.kind === 'meas' && na_selected.id === id) Na__ImageViewerPerspective__Select(null);
        Na__ImageViewerPerspective__Changed(key);
    }

    function Na__ImageViewerPerspective__ClearAxis(axis) {
        var key = Na__ImageViewerPerspective__Key();
        var st  = na_stateByKey[key];
        if (!st || !st.lines.some(function(l) { return l.axis === axis; })) return;
        na_core.pushHistory();
        st.lines = st.lines.filter(function(l) { return l.axis !== axis; });
        if (na_selected && na_selected.kind === 'line' && !Na__ImageViewerPerspective__FindItem('line', na_selected.id)) Na__ImageViewerPerspective__Select(null);
        Na__ImageViewerPerspective__Changed(key);
    }

    function Na__ImageViewerPerspective__ClearAll() {
        var key = Na__ImageViewerPerspective__Key();
        var st  = na_stateByKey[key];
        if (!st || (!st.lines.length && !st.meas.length && !(st.guides && st.guides.length))) return;
        na_core.pushHistory();
        st.lines  = [];
        st.meas   = [];
        st.guides = [];
        na_pending = [];
        Na__ImageViewerPerspective__Select(null);
        Na__ImageViewerPerspective__Changed(key);
    }

    function Na__ImageViewerPerspective__SetPlane(plane) {
        na_plane = plane;
        var key = Na__ImageViewerPerspective__Key();
        if (na_selected && na_selected.kind === 'meas') {
            var m = Na__ImageViewerPerspective__FindItem('meas', na_selected.id);
            if (m && m.plane !== plane) {
                na_core.pushHistory();
                m.plane = plane;
                Na__ImageViewerPerspective__Changed(key);
                return;
            }
        }
        if (na_mode === 'pitch' && plane === 'xy') {
            Na__ImageViewerPerspective__ShowToolHint('Pitch is measured on a wall. Use Angle on the ground.');
        }
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Lens Setting
    // -------------------------------------------------------------------------

    // A bare number is the 35 mm-equivalent focal length in mm, as phone
    // specs quote it. Anything that cannot be a lens is refused, not clamped.
    function Na__ImageViewerPerspective__ParseLensMm(raw) {
        var s = String(raw === undefined || raw === null ? '' : raw).trim().toLowerCase().replace(/\s+/g, '');
        var m = s.match(/^([0-9]*\.?[0-9]+)(mm)?$/);
        if (!m) return { ok: false, message: 'Type the 35 mm-equivalent focal length, e.g. 26.' };
        var mm = parseFloat(m[1]);
        if (!(mm >= 8 && mm <= 800)) {
            return { ok: false, message: mm + ' mm is not a camera lens. Type the 35 mm equivalent, e.g. 13, 26 or 77.' };
        }
        return { ok: true, mm: mm };
    }

    function Na__ImageViewerPerspective__OnLensSelect() {
        var key = Na__ImageViewerPerspective__Key();
        if (!key || !na_lensSelect) return;
        var v  = na_lensSelect.value;
        var st = Na__ImageViewerPerspective__State(key);
        na_lensError = '';
        if (v === 'custom') {
            na_lensEditing = true;
            if (na_lensInput) {
                na_lensInput.style.display = '';
                na_lensInput.value = st.lens.mm > 0 ? String(st.lens.mm) : '';
                na_lensInput.focus();
                na_lensInput.select();
            }
            Na__ImageViewerPerspective__RefreshPanel();
            return;
        }
        na_lensEditing = false;
        na_core.pushHistory();
        if (v === 'auto' || v === 'exif') st.lens = { mode: v, mm: st.lens.mm, userSet: true };
        else                              st.lens = { mode: 'preset', mm: parseFloat(v), userSet: true };
        na_lastLens = { mode: st.lens.mode === 'exif' ? 'auto' : st.lens.mode, mm: st.lens.mm };
        Na__ImageViewerPerspective__Changed(key);
    }

    function Na__ImageViewerPerspective__OnLensInputCommit() {
        var key = Na__ImageViewerPerspective__Key();
        if (!key || !na_lensInput) return;
        var parsed = Na__ImageViewerPerspective__ParseLensMm(na_lensInput.value);
        if (!parsed.ok) {
            na_lensError = parsed.message;
            na_lensInput.classList.add('naImageViewer__PerspInput--error');
            Na__ImageViewerPerspective__RefreshPanel();
            return;
        }
        na_lensError = '';
        na_lensEditing = false;
        na_lensInput.classList.remove('naImageViewer__PerspInput--error');
        var st = Na__ImageViewerPerspective__State(key);
        if (st.lens.mode === 'custom' && st.lens.mm === parsed.mm) { Na__ImageViewerPerspective__RefreshPanel(); return; }
        na_core.pushHistory();
        st.lens = { mode: 'custom', mm: parsed.mm, userSet: true };
        na_lastLens = { mode: 'custom', mm: parsed.mm };
        Na__ImageViewerPerspective__Changed(key);
    }

    // Ruby reads the photo's own lens data (EXIF) when the file has any.
    function Na__ImageViewerPerspective__RequestPhotoInfo() {
        var key = Na__ImageViewerPerspective__Key();
        if (!key || na_photoInfo[key]) return;
        if (!window.sketchup || typeof window.sketchup.request_photo_info !== 'function') return;
        na_photoInfo[key] = { pending: true };
        window.sketchup.request_photo_info(key);
    }

    function Na__ImageViewerPerspective__OnPhotoInfo(info) {
        if (!info || !info.path) return;
        var key = String(info.path);
        na_photoInfo[key] = info;
        var st = na_stateByKey[key];
        if (info.focal35 > 0 && st && !st.lens.userSet) {
            st.lens = { mode: 'exif', mm: info.focal35, userSet: false };
            if (key === Na__ImageViewerPerspective__Key()) Na__ImageViewerPerspective__Changed(key);
        }
        if (key === Na__ImageViewerPerspective__Key()) Na__ImageViewerPerspective__RefreshPanel();
    }

    window.Na__ImageViewer__OnPhotoInfo = Na__ImageViewerPerspective__OnPhotoInfo;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Panel
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__SetPanelOpen(open) {
        na_panelOpen = !!open;
        if (na_panel)     na_panel.classList.toggle('naImageViewer__PerspPanel--open', na_panelOpen);
        if (na_btnToggle) na_btnToggle.classList.toggle('naImageViewer__Btn--active', na_panelOpen);
        if (!na_panelOpen) {
            na_mode = null;
            na_pending = [];
            na_selected = null;
            na_core.releaseTool(NA_TOOL_NAME);
            Na__ImageViewerPerspective__UpdateCursor(null);
        } else {
            Na__ImageViewerPerspective__RequestPhotoInfo();
        }
        if (typeof na_core.resize === 'function') na_core.resize();
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__ShowToolHint(text) {
        if (na_toolHint) {
            na_toolHint.textContent = text || '';
            na_toolHint.dataset.sticky = text ? '1' : '';
        }
    }

    function Na__ImageViewerPerspective__RefreshToolHint() {
        if (na_guideHint) {
            if (na_guideHint.dataset.sticky === '1') na_guideHint.dataset.sticky = '';
            else na_guideHint.textContent = Na__ImageViewerPerspective__GuideHintText();
        }
        if (!na_toolHint) return;
        if (na_toolHint.dataset.sticky === '1') { na_toolHint.dataset.sticky = ''; return; }
        var text = '';
        if (na_mode === 'z')          text = 'Click both ends of a vertical edge. Keep adding; Esc to stop.';
        else if (na_mode === 'x')     text = 'Click both ends of a level edge on the wall you are measuring. Keep adding; Esc to stop.';
        else if (na_mode === 'y')     text = 'Click both ends of a level edge on the wall at 90\u00b0. Keep adding; Esc to stop.';
        else if (na_mode === 'pitch') text = na_pending.length ? 'Now click the other end of the slope.'
            : 'Click both ends of a straight sloping edge. On a verge, follow where the tiles meet the brickwork: seen from the side, the skyline can be the roof behind it.';
        else if (na_mode === 'angle') text = ['Click the end of the first arm.', 'Now click the corner.', 'Now click the end of the second arm.'][Math.min(2, na_pending.length)];
        else if (na_mode === 'guide') text = '';
        else                          text = 'Drag a handle to refine a point. Click a line, angle or guide to select it.';
        if (na_mode && na_mode !== 'guide') text += ' Drag to pan, scroll to zoom.';
        na_toolHint.textContent = text;
    }

    function Na__ImageViewerPerspective__RefreshPanel() {
        if (!na_panel) return;
        var key  = Na__ImageViewerPerspective__Key();
        var st   = key ? na_stateByKey[key] : null;
        var an   = key ? na_analysisByKey[key] : null;
        var lens = key ? Na__ImageViewerPerspective__LensOf(key) : na_lastLens;

        NA_AXES.forEach(function(axis) {
            var n = st ? st.lines.filter(function(l) { return l.axis === axis; }).length : 0;
            if (na_countEl[axis]) {
                na_countEl[axis].textContent = n ? (n === 1 ? '1 line' : n + ' lines') : (axis === 'y' ? 'optional' : 'none yet');
                na_countEl[axis].classList.toggle('naImageViewer__PerspCount--done', axis === 'y' ? n >= 1 : n >= 2);
            }
            if (na_btnDraw[axis])    na_btnDraw[axis].classList.toggle('naImageViewer__PerspGroupBtn--active', na_mode === axis);
            if (na_btnClearAx[axis]) na_btnClearAx[axis].disabled = !n;
        });

        Na__ImageViewerPerspective__RefreshLens(key, lens, an);
        Na__ImageViewerPerspective__RefreshStatus(key, st, an);

        na_planeBtns.forEach(function(btn) {
            btn.classList.toggle('naImageViewer__PerspSegBtn--active', btn.getAttribute('data-plane') === na_plane);
        });
        if (na_btnPitch) na_btnPitch.classList.toggle('naImageViewer__Btn--active', na_mode === 'pitch');
        if (na_btnAngle) na_btnAngle.classList.toggle('naImageViewer__Btn--active', na_mode === 'angle');
        Na__ImageViewerPerspective__RefreshToolHint();
        Na__ImageViewerPerspective__RefreshResults(st, an);
        if (na_gridBox) na_gridBox.checked = na_showGrid;

        var guideCount = st && st.guides ? st.guides.length : 0;
        if (na_btnGuide) na_btnGuide.classList.toggle('naImageViewer__Btn--active', na_mode === 'guide');
        na_guideAxisBtns.forEach(function(btn) {
            btn.classList.toggle('naImageViewer__PerspSegBtn--active', btn.getAttribute('data-guide-axis') === na_guideAxis);
        });
        if (na_guideCount) {
            na_guideCount.textContent = guideCount ? (guideCount === 1 ? '1 guide' : guideCount + ' guides') : 'none yet';
            na_guideCount.classList.toggle('naImageViewer__PerspCount--done', guideCount > 0);
        }
        if (na_btnClearGuides) na_btnClearGuides.disabled = !guideCount;
        if (na_showGuidesBox) na_showGuidesBox.checked = na_showGuideLines;
        if (na_guideAngleInput && document.activeElement !== na_guideAngleInput && !na_guideAngleError) {
            na_guideAngleInput.value = na_guideAngle ? String(na_guideAngle) : '';
        }
    }

    function Na__ImageViewerPerspective__RefreshLens(key, lens, an) {
        if (!na_lensSelect) return;
        var info = key ? na_photoInfo[key] : null;
        var exifOption = na_lensSelect.querySelector('option[value="exif"]');
        if (exifOption) {
            exifOption.disabled = !(info && info.focal35 > 0);
            exifOption.textContent = info && info.focal35 > 0 ? 'From the photo (' + info.focal35 + ' mm)'
                : (info && info.pending ? 'From the photo (reading\u2026)' : 'From the photo (no lens data)');
        }

        var value = 'auto';
        if (na_lensEditing) value = 'custom';
        else if (lens.mode === 'exif' && info && info.focal35 > 0) value = 'exif';
        else if (lens.mode === 'preset' && NA_LENS_PRESETS.indexOf(String(lens.mm)) >= 0) value = String(lens.mm);
        else if (lens.mode === 'custom' || lens.mode === 'preset') value = 'custom';
        if (na_lensSelect.value !== value && document.activeElement !== na_lensSelect) na_lensSelect.value = value;
        if (na_lensInput) {
            var showInput = na_lensSelect.value === 'custom';
            na_lensInput.style.display = showInput ? '' : 'none';
            if (showInput && document.activeElement !== na_lensInput && lens.mm > 0 && !na_lensError) na_lensInput.value = String(lens.mm);
        }
        if (!na_lensInfo) return;

        if (na_lensError) { na_lensInfo.textContent = na_lensError; na_lensInfo.className = 'naImageViewer__PerspNote naImageViewer__PerspNote--warn'; return; }

        var prior = key ? Na__ImageViewerPerspective__LensPrior(key) : null;
        var size  = na_core.getImageSize();
        var text  = '', warn = false;
        if (!prior) {
            text = 'Assumes a phone\u2019s main camera (24\u201326 mm) until you choose.';
        } else if (prior.source === 'exif') {
            text = 'From the photo: ' + info.focal35 + ' mm' + (info.model ? ' (' + [info.make, info.model].filter(Boolean).join(' ') + ')' : '') + '.';
        } else if (prior.source === 'auto') {
            text = 'Auto: assumes a phone\u2019s main camera (24\u201326 mm).';
            if (an && an.cal && an.cal.ok && an.cal.fSigmaLn && size.w) {
                var solvedMm = na_solver.lensPxToMm(an.cal.f, size.w, size.h);
                if (an.cal.fSigmaLn < 0.6 * prior.sigmaLn) {
                    text = 'Auto: the lines solve the lens at ' + solvedMm.toFixed(1) + ' mm \u00b1' + (2 * solvedMm * an.cal.fSigmaLn).toFixed(1) + '.';
                } else {
                    text += ' The lines cannot pin it down here; choose the lens if you know it.';
                }
            }
            if (info && info.none) text += ' (No lens data in this file.)';
        } else {
            text = prior.mm + ' mm set.';
            if (an && an.cal && an.cal.ok && Math.abs(an.cal.priorPull) > 3 && size.w) {
                warn = true;
                text += ' Your lines suggest about ' + na_solver.lensPxToMm(an.cal.f, size.w, size.h).toFixed(0) +
                    ' mm: check the lens, that the photo is not cropped, and that green lines are on a wall at 90\u00b0 to the red.';
            }
        }
        na_lensInfo.textContent = text;
        na_lensInfo.className = 'naImageViewer__PerspNote' + (warn ? ' naImageViewer__PerspNote--warn' : '');
    }

    function Na__ImageViewerPerspective__RefreshStatus(key, st, an) {
        if (!na_statusEl) return;
        var cls = 'naImageViewer__PerspStatus', text;
        if (!key) {
            text = 'Choose a folder of photos first.';
        } else if (!an || !an.cal) {
            text = 'Draw 2 or more verticals and 2 or more level lines on the wall you are measuring.';
        } else if (!an.cal.ok) {
            text = an.cal.need;
        } else {
            var n = an.cal.lines.length;
            text = '\u2713 Calibrated from ' + n + ' lines. They agree to ' + an.cal.rmsPx.toFixed(1) + ' px.';
            cls += ' naImageViewer__PerspStatus--ok';
            var flagged = an.cal.lines.filter(function(d) { return d.flagged; });
            if (flagged.length && st) {
                var worst = flagged.sort(function(p, q) { return Math.abs(q.residualPx) - Math.abs(p.residualPx); })[0];
                var line  = Na__ImageViewerPerspective__FindItem('line', worst.id);
                text = (line ? Na__ImageViewerPerspective__LineName(line, st) : 'A line') + ' is ' + Math.abs(worst.residualPx).toFixed(1) +
                    ' px off the others. Redraw it on a true ' + (worst.axis === 'z' ? 'vertical' : 'level') + ' edge, or delete it.';
                cls = 'naImageViewer__PerspStatus naImageViewer__PerspStatus--warn';
            }
        }
        na_statusEl.textContent = text;
        na_statusEl.className = cls;
    }

    function Na__ImageViewerPerspective__RefreshResults(st, an) {
        if (!na_resultsEl) return;
        if (!st || !st.meas.length) {
            na_resultsEl.innerHTML = '<div class="naImageViewer__PerspEmpty">No pitches or angles on this photo yet.</div>';
            return;
        }
        var html = '';
        st.meas.forEach(function(m, i) {
            var res      = an && an.results ? an.results[i] : null;
            var selected = !!(na_selected && na_selected.kind === 'meas' && na_selected.id === m.id);
            var value, pm = '', pmClass = '', sub;
            if (res && res.ok) {
                var hw = Na__ImageViewerPerspective__HalfWidth(res);
                value = Na__ImageViewerPerspective__Deg(res.value);
                pm = hw !== null ? '\u00b1' + hw.toFixed(1) + '\u00b0' : '\u00b1\u2026';
                pmClass = 'naImageViewer__PerspPm--' + (Na__ImageViewerPerspective__Quality(res) || 'pending');
                sub = NA_PLANE_NAME[m.plane] + ' \u00b7 photo shows ' + Na__ImageViewerPerspective__Deg(res.raw2d);
                if (Na__ImageViewerPerspective__Quality(res) === 'weak') sub += ' \u00b7 uncertain: spread the lines wider, or use a photo that faces this wall more squarely';
            } else {
                value = res && res.raw2d !== null && res.raw2d !== undefined ? Na__ImageViewerPerspective__Deg(res.raw2d) : '\u2026';
                pm = '2D';
                pmClass = 'naImageViewer__PerspPm--raw';
                var reason = res ? res.reason : 'uncalibrated';
                if (reason === 'horizon')              sub = NA_PLANE_NAME[m.plane] + ' \u00b7 these points straddle this plane\u2019s horizon: check the plane';
                else if (reason === 'pitch-on-ground') sub = 'Pitch needs a wall: choose Red wall or Green wall';
                else                                   sub = 'Not corrected yet: calibrate the photo (step 1)';
            }
            html += '<div class="naImageViewer__PerspResult' + (selected ? ' naImageViewer__PerspResult--selected' : '') + '" data-id="' + m.id + '">' +
                '<div class="naImageViewer__PerspResultTop">' +
                '<span class="naImageViewer__PerspResultName">' + Na__ImageViewerPerspective__MeasName(m, st) + '</span>' +
                '<span class="naImageViewer__PerspResultValue">' + value + '</span>' +
                '<span class="naImageViewer__PerspPm ' + pmClass + '">' + pm + '</span>' +
                '<button class="naImageViewer__PerspIconBtn" data-del="' + m.id + '" title="Delete">\u00d7</button>' +
                '</div>' +
                '<div class="naImageViewer__PerspResultSub">' + sub + '</div>' +
                '</div>';
        });
        na_resultsEl.innerHTML = html;
    }

    function Na__ImageViewerPerspective__OnResultsClick(e) {
        var del = e.target.closest ? e.target.closest('[data-del]') : null;
        if (del) {
            Na__ImageViewerPerspective__DeleteMeasurement(parseInt(del.getAttribute('data-del'), 10));
            return;
        }
        var row = e.target.closest ? e.target.closest('[data-id]') : null;
        if (!row) return;
        var id = parseInt(row.getAttribute('data-id'), 10);
        var already = na_selected && na_selected.kind === 'meas' && na_selected.id === id;
        Na__ImageViewerPerspective__Select(already ? null : 'meas', already ? null : id);
        Na__ImageViewerPerspective__RefreshPanel();
        na_core.requestDraw();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Interaction
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__CanvasPoint(e) {
        var rect  = na_canvas.getBoundingClientRect();
        var ratio = na_core.getRatio();
        return {
            x      : (e.clientX - rect.left) * ratio,
            y      : (e.clientY - rect.top) * ratio,
            inside : e.clientX >= rect.left && e.clientX <= rect.right && e.clientY >= rect.top && e.clientY <= rect.bottom
        };
    }

    function Na__ImageViewerPerspective__UpdateCursor(p) {
        if (!na_canvas) return;
        var cursor = '';
        if (na_panelOpen && Na__ImageViewerPerspective__Interactive()) {
            if (na_drag) cursor = 'grabbing';
            else if (p && Na__ImageViewerPerspective__HitHandle(p)) cursor = 'move';
            else if (na_mode) cursor = 'crosshair';
        }
        if (na_canvas.style.cursor !== cursor) na_canvas.style.cursor = cursor;
    }

    // Capture phase on the canvas wrapper: runs before the viewer's own pan
    // handler, so a press on a handle or in a drawing mode is ours.
    function Na__ImageViewerPerspective__OnMouseDown(e) {
        if (e.target !== na_canvas || !Na__ImageViewerPerspective__Interactive()) return;
        if (!Na__ImageViewerPerspective__Key()) return;
        var p   = Na__ImageViewerPerspective__CanvasPoint(e);
        var hit = e.button === 0 ? Na__ImageViewerPerspective__HitHandle(p) : null;

        if (hit || na_mode) {
            e.stopPropagation();
            e.preventDefault();
        }
        na_press = {
            x       : e.clientX,
            y       : e.clientY,
            lastX   : e.clientX,
            lastY   : e.clientY,
            button  : e.button,
            handle  : hit,
            passive : !hit && !na_mode,  // no tool: the viewer pans, a still click selects
            panning : !hit && !!na_mode && e.button !== 0,
            moved   : false
        };
    }

    function Na__ImageViewerPerspective__OnMouseMove(e) {
        if (!na_canvas) return;
        var p = Na__ImageViewerPerspective__CanvasPoint(e);
        var key = Na__ImageViewerPerspective__Key();

        if (na_press) {
            var dist = Math.sqrt((e.clientX - na_press.x) * (e.clientX - na_press.x) + (e.clientY - na_press.y) * (e.clientY - na_press.y));
            if (dist > NA_DRAG_START_PX) na_press.moved = true;

            if (na_press.handle && na_press.moved && !na_drag) {
                na_core.pushHistory();
                na_drag = { ref: na_press.handle, moved: true };
                Na__ImageViewerPerspective__Select(na_press.handle.kind, na_press.handle.item.id);
            }
            if (!na_press.handle && !na_press.passive && (na_press.panning || na_press.moved)) {
                na_press.panning = true;
                var ratio = na_core.getRatio();
                na_core.panBy((e.clientX - na_press.lastX) * ratio, (e.clientY - na_press.lastY) * ratio);
            }
            na_press.lastX = e.clientX;
            na_press.lastY = e.clientY;
        }

        if (na_drag) {
            // Guide points and measured points snap while dragged; calibration
            // lines must follow the photo's own edges, so they never do.
            var dragSnap = na_drag.ref.kind !== 'line' ? Na__ImageViewerPerspective__SnapAt(p.x, p.y, na_drag.ref) : null;
            var ip = dragSnap ? dragSnap.img : na_core.screenToImg(p.x, p.y);
            if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(dragSnap);
            Na__ImageViewerPerspective__SetPoint(na_drag.ref, { x: ip.x, y: ip.y, prec: Na__ImageViewerPerspective__CurrentPrec() });
            na_cursor = p.inside ? p : null;
            if (key) Na__ImageViewerPerspective__Analyse(key, false);
            Na__ImageViewerPerspective__RefreshPanel();
            Na__ImageViewerPerspective__UpdateCursor(p);
            na_core.requestDraw();
            return;
        }

        var wasOver = !!na_cursor;
        na_cursor = (na_panelOpen && e.target === na_canvas) ? p : null;
        Na__ImageViewerPerspective__UpdateSnap();
        Na__ImageViewerPerspective__UpdateCursor(na_cursor);
        if (na_panelOpen && (na_mode || wasOver !== !!na_cursor)) na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__OnMouseUp(e) {
        var press = na_press;
        na_press = null;
        var key = Na__ImageViewerPerspective__Key();

        if (na_drag) {
            na_drag = null;
            if (typeof na_core.setSnapMarker === 'function') na_core.setSnapMarker(null);
            if (key) Na__ImageViewerPerspective__Changed(key);
            Na__ImageViewerPerspective__UpdateCursor(na_cursor);
            return;
        }
        if (!press || e.target !== na_canvas || !Na__ImageViewerPerspective__Interactive()) return;
        var p = Na__ImageViewerPerspective__CanvasPoint(e);

        if (press.handle && !press.moved) {
            // A click on a handle: snap a new point onto it while drawing,
            // otherwise select what it belongs to.
            if (na_mode) Na__ImageViewerPerspective__PlacePoint(Na__ImageViewerPerspective__ToScreen(Na__ImageViewerPerspective__RefPoint(press.handle)));
            else {
                Na__ImageViewerPerspective__Select(press.handle.kind, press.handle.item.id);
                Na__ImageViewerPerspective__RefreshPanel();
                na_core.requestDraw();
            }
            return;
        }
        if (press.passive) {
            if (press.moved || press.button !== 0) return;
            var hit = Na__ImageViewerPerspective__HitItem(p);
            Na__ImageViewerPerspective__Select(hit ? hit.kind : null, hit ? hit.id : null);
            Na__ImageViewerPerspective__RefreshPanel();
            na_core.requestDraw();
            return;
        }
        if (press.panning || press.moved || press.button !== 0) return;
        var snapUp = Na__ImageViewerPerspective__UsesSnap(na_mode) ? Na__ImageViewerPerspective__SnapAt(p.x, p.y, null) : null;
        Na__ImageViewerPerspective__PlacePoint(snapUp ? snapUp.screen : p);
        Na__ImageViewerPerspective__UpdateSnap();
    }

    function Na__ImageViewerPerspective__OnMouseLeave() {
        if (na_drag) return;
        na_cursor   = null;
        na_snap     = null;
        na_inferred = null;
        if (na_panelOpen) na_core.requestDraw();
    }

    function Na__ImageViewerPerspective__OnKeyDown(e) {
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        if (!na_panelOpen) return;

        if (e.key === 'Escape') {
            if (na_drag) return;
            if (na_pending.length) {
                na_pending = [];
                Na__ImageViewerPerspective__RefreshPanel();
                na_core.requestDraw();
            } else if (na_mode) {
                Na__ImageViewerPerspective__SetMode(null);
            } else if (na_selected) {
                Na__ImageViewerPerspective__Select(null);
                Na__ImageViewerPerspective__RefreshPanel();
                na_core.requestDraw();
            }
            return;
        }
        if ((e.key === 'Delete' || e.key === 'Backspace') && na_selected && Na__ImageViewerPerspective__Interactive()) {
            e.preventDefault();
            Na__ImageViewerPerspective__DeleteSelected();
            return;
        }
        // T, as SketchUp's Tape Measure: the Guide tool.
        if ((e.key === 't' || e.key === 'T') && !e.ctrlKey && !e.metaKey && !e.altKey) {
            e.preventDefault();
            Na__ImageViewerPerspective__SetMode('guide');
        }
    }

    // Capture phase, ahead of the viewer: while the Guide tool is active the
    // arrow keys lock an axis, as in SketchUp, instead of changing photo.
    function Na__ImageViewerPerspective__OnKeyCapture(e) {
        if (!na_panelOpen || na_mode !== 'guide') return;
        var tag = e.target && e.target.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
        var axis = NA_GUIDE_KEYS[e.key];
        if (!axis || e.ctrlKey || e.metaKey || e.altKey) return;
        e.preventDefault();
        e.stopPropagation();
        Na__ImageViewerPerspective__SetGuideAxis(axis === na_guideAxis ? 'auto' : axis);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspective__Init() {
        na_canvas      = na_core.getCanvas();
        na_wrap        = na_canvas ? na_canvas.parentElement : null;
        na_panel       = Na__ImageViewerPerspective__El('naImageViewer_perspPanel');
        na_btnToggle   = Na__ImageViewerPerspective__El('naImageViewer_btnPerspective');
        na_btnClose    = Na__ImageViewerPerspective__El('naImageViewer_perspClose');
        na_lensSelect  = Na__ImageViewerPerspective__El('naImageViewer_perspLens');
        na_lensInput   = Na__ImageViewerPerspective__El('naImageViewer_perspLensMm');
        na_lensInfo    = Na__ImageViewerPerspective__El('naImageViewer_perspLensInfo');
        na_statusEl    = Na__ImageViewerPerspective__El('naImageViewer_perspStatus');
        na_btnPitch    = Na__ImageViewerPerspective__El('naImageViewer_perspPitch');
        na_btnAngle    = Na__ImageViewerPerspective__El('naImageViewer_perspAngle');
        na_toolHint    = Na__ImageViewerPerspective__El('naImageViewer_perspToolHint');
        na_resultsEl   = Na__ImageViewerPerspective__El('naImageViewer_perspResults');
        na_gridBox     = Na__ImageViewerPerspective__El('naImageViewer_perspGrid');
        na_btnClearAll = Na__ImageViewerPerspective__El('naImageViewer_perspClearAll');
        na_btnGuide    = Na__ImageViewerPerspective__El('naImageViewer_perspGuide');
        na_guideAngleInput = Na__ImageViewerPerspective__El('naImageViewer_perspGuideAngle');
        na_guideHint   = Na__ImageViewerPerspective__El('naImageViewer_perspGuideHint');
        na_showGuidesBox = Na__ImageViewerPerspective__El('naImageViewer_perspShowGuides');
        na_guideCount  = Na__ImageViewerPerspective__El('naImageViewer_perspGuideCount');
        na_btnClearGuides = Na__ImageViewerPerspective__El('naImageViewer_perspClearGuides');
        if (!na_canvas || !na_panel || !na_btnToggle) return;

        var axisIds = { z: 'Z', x: 'X', y: 'Y' };
        NA_AXES.forEach(function(axis) {
            na_btnDraw[axis]    = Na__ImageViewerPerspective__El('naImageViewer_perspDraw' + axisIds[axis]);
            na_btnClearAx[axis] = Na__ImageViewerPerspective__El('naImageViewer_perspClear' + axisIds[axis]);
            na_countEl[axis]    = Na__ImageViewerPerspective__El('naImageViewer_perspCount' + axisIds[axis]);
            if (na_btnDraw[axis])    na_btnDraw[axis].addEventListener('click', function() { Na__ImageViewerPerspective__SetMode(axis); });
            if (na_btnClearAx[axis]) na_btnClearAx[axis].addEventListener('click', function() { Na__ImageViewerPerspective__ClearAxis(axis); });
        });
        na_planeBtns = Array.prototype.slice.call(na_panel.querySelectorAll('[data-plane]'));
        na_planeBtns.forEach(function(btn) {
            btn.addEventListener('click', function() { Na__ImageViewerPerspective__SetPlane(btn.getAttribute('data-plane')); });
        });
        na_guideAxisBtns = Array.prototype.slice.call(na_panel.querySelectorAll('[data-guide-axis]'));
        na_guideAxisBtns.forEach(function(btn) {
            btn.addEventListener('click', function() { Na__ImageViewerPerspective__SetGuideAxis(btn.getAttribute('data-guide-axis')); });
        });

        na_core.registerOverlay(Na__ImageViewerPerspective__Render);
        na_core.registerHistory(NA_TOOL_NAME, {
            snapshot : Na__ImageViewerPerspective__Snapshot,
            restore  : Na__ImageViewerPerspective__Restore
        });
        na_core.onHistoryChanged(Na__ImageViewerPerspective__OnHistoryChanged);
        if (typeof na_core.registerSnap === 'function') na_core.registerSnap(Na__ImageViewerPerspective__ProvideSnap);
        na_core.onImageChanged(function() {
            na_lensEditing = false;
            na_lensError   = '';
            na_snap        = null;
            na_inferred    = null;
            na_pending  = [];
            na_drag     = null;
            na_press    = null;
            na_selected = null;
            if (!na_mode) na_core.releaseTool(NA_TOOL_NAME);
            var key = Na__ImageViewerPerspective__Key();
            var an  = key ? na_analysisByKey[key] : null;
            if (key && na_stateByKey[key] && (!an || !an.mc)) Na__ImageViewerPerspective__Analyse(key, true);
            if (na_panelOpen) Na__ImageViewerPerspective__RequestPhotoInfo();
            Na__ImageViewerPerspective__RefreshPanel();
        });

        if (na_wrap) na_wrap.addEventListener('mousedown', Na__ImageViewerPerspective__OnMouseDown, true);
        window.addEventListener('mousemove', Na__ImageViewerPerspective__OnMouseMove);
        window.addEventListener('mouseup', Na__ImageViewerPerspective__OnMouseUp);
        window.addEventListener('keydown', Na__ImageViewerPerspective__OnKeyDown);
        window.addEventListener('keydown', Na__ImageViewerPerspective__OnKeyCapture, true);
        na_canvas.addEventListener('mouseleave', Na__ImageViewerPerspective__OnMouseLeave);

        na_btnToggle.addEventListener('click', function() { Na__ImageViewerPerspective__SetPanelOpen(!na_panelOpen); });
        if (na_btnClose)    na_btnClose.addEventListener('click', function() { Na__ImageViewerPerspective__SetPanelOpen(false); });
        if (na_btnPitch)    na_btnPitch.addEventListener('click', function() { Na__ImageViewerPerspective__SetMode('pitch'); });
        if (na_btnAngle)    na_btnAngle.addEventListener('click', function() { Na__ImageViewerPerspective__SetMode('angle'); });
        if (na_btnClearAll) na_btnClearAll.addEventListener('click', Na__ImageViewerPerspective__ClearAll);
        if (na_resultsEl)   na_resultsEl.addEventListener('click', Na__ImageViewerPerspective__OnResultsClick);
        if (na_gridBox) {
            na_gridBox.addEventListener('change', function() {
                na_showGrid = !!na_gridBox.checked;
                na_core.requestDraw();
            });
        }
        if (na_btnGuide) na_btnGuide.addEventListener('click', function() { Na__ImageViewerPerspective__SetMode('guide'); });
        if (na_btnClearGuides) na_btnClearGuides.addEventListener('click', Na__ImageViewerPerspective__ClearGuides);
        if (na_showGuidesBox) {
            na_showGuidesBox.addEventListener('change', function() {
                na_showGuideLines = !!na_showGuidesBox.checked;
                if (!na_showGuideLines && na_selected && na_selected.kind === 'guide') Na__ImageViewerPerspective__Select(null);
                Na__ImageViewerPerspective__RefreshPanel();
                na_core.requestDraw();
            });
        }
        if (na_guideAngleInput) {
            na_guideAngleInput.addEventListener('keydown', function(ev) {
                // Enter commits and hands the keys back to the photo, as SketchUp's
                // measurements box does, so T and the arrow keys work straight away.
                if (ev.key === 'Enter') { ev.preventDefault(); Na__ImageViewerPerspective__OnGuideAngleCommit(); if (!na_guideAngleError) na_guideAngleInput.blur(); }
                else if (ev.key === 'Escape') {
                    ev.preventDefault();
                    na_guideAngleError = '';
                    na_guideAngleInput.classList.remove('naImageViewer__PerspInput--error');
                    na_guideAngleInput.blur();
                    Na__ImageViewerPerspective__RefreshPanel();
                }
                ev.stopPropagation();
            });
            na_guideAngleInput.addEventListener('change', Na__ImageViewerPerspective__OnGuideAngleCommit);
        }
        if (na_lensSelect) na_lensSelect.addEventListener('change', Na__ImageViewerPerspective__OnLensSelect);
        if (na_lensInput) {
            na_lensInput.addEventListener('keydown', function(ev) {
                if (ev.key === 'Enter')       { ev.preventDefault(); Na__ImageViewerPerspective__OnLensInputCommit(); }
                else if (ev.key === 'Escape') { ev.preventDefault(); na_lensError = ''; na_lensEditing = false; na_lensInput.blur(); Na__ImageViewerPerspective__RefreshPanel(); }
                ev.stopPropagation();
            });
            na_lensInput.addEventListener('change', Na__ImageViewerPerspective__OnLensInputCommit);
        }

        Na__ImageViewerPerspective__RefreshPanel();
    }

    // Read-only view of the current photo's guides, for the browser tests.
    window.Na__ImageViewer__Perspective = {
        inspect: function() {
            var key = Na__ImageViewerPerspective__Key();
            var st  = key ? na_stateByKey[key] : null;
            var an  = key ? na_analysisByKey[key] : null;
            return {
                mode       : na_mode,
                guideAxis  : na_guideAxis,
                guideAngle : na_guideAngle,
                showGuides : na_showGuideLines,
                inferred   : na_inferred ? na_inferred.label : null,
                snap       : na_snap ? { kind: na_snap.kind, img: na_snap.img } : null,
                selected   : na_selected ? { kind: na_selected.kind, id: na_selected.id } : null,
                guideCount : st && st.guides ? st.guides.length : 0,
                guides     : Na__ImageViewerPerspective__VisibleGuides(st, an, null).map(function(v) {
                    return { id: v.guide.id, dir: v.guide.dir, label: Na__ImageViewerPerspective__GuideLabel(v.guide, st), p: v.guide.p, seg: v.seg };
                })
            };
        }
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ImageViewerPerspective__Init);
    } else {
        Na__ImageViewerPerspective__Init();
    }

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})();
