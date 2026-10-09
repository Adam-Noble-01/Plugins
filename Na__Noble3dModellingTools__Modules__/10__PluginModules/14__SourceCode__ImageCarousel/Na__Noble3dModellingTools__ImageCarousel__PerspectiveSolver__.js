// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - PERSPECTIVE SOLVER
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__PerspectiveSolver__.js
// PURPOSE    : Pure maths behind the Perspective Angle tool. Recovers the
//              camera's rotation and focal length from lines drawn along
//              vertical and level edges of a building, then measures pitches
//              and angles as they are on the building, not as they look in
//              the photo.
//
// DESIGN     : No DOM access. Exposed as window.Na__ImageViewer__PerspectiveSolver
//              inside the dialog and as module.exports under node, so the
//              tests can drive it with synthetic photos of known roofs.
//
// MODEL      : - Pinhole camera, principal point at the image centre, square
//                pixels, no lens distortion (phone photos arrive corrected).
//              - Image points are the viewer's image space: pixels from the
//                image centre, y down. A point p looks along the ray
//                (p.x, p.y, f) in camera space (x right, y down, z forward).
//              - World axes follow SketchUp: X red and Y green are level and at
//                90 degrees to each other, Z blue is vertical.
//              - The camera is solved by least squares (Levenberg-Marquardt)
//                over its rotation and log focal length. Each drawn line must
//                point at its axis' vanishing point; the lens setting is a
//                prior on the focal length, so lines that can pin the lens
//                down override it and lines that cannot leave it alone.
//              - A wall or ground measurement intersects the clicked rays
//                with the chosen plane through the world axes. Angles do not
//                depend on how far away the plane is, so no scale is needed.
//              - Uncertainty is Monte Carlo: every clicked point and the lens
//                prior are perturbed, the camera re-solved and the angle
//                re-measured. A seeded generator keeps the reading steady.
//              - Guides are infinite 3D lines through a clicked point along a
//                direction (an axis, a measured slope, a typed pitch). Their
//                image is the line from the direction's vanishing point out
//                through the point, clipped to the photo.
// =============================================================================

(function(root) {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants
    // -------------------------------------------------------------------------

    var NA_FRAME_DIAGONAL_MM  = 43.2666;  // diagonal of a 36 x 24 mm frame (35 mm equivalent)
    var NA_AXIS_NAMES         = ['x', 'y', 'z'];
    var NA_PLANE_NORMAL_AXIS  = { xz: 'y', yz: 'x', xy: 'z' };
    var NA_PLANE_LEVEL_AXIS   = { xz: 'x', yz: 'y' };   // pitch is only defined on walls
    var NA_PLANE_AXES         = { xz: ['x', 'z'], yz: ['y', 'z'], xy: ['x', 'y'] };
    var NA_EDGE_SIGMA_PX      = 0.8;      // how sharply an edge sits in the photo itself
    var NA_CLICK_SIGMA        = 0.6;      // pointer spread, in screen pixels
    var NA_MIN_LINE_PX        = 3;        // shorter lines are ignored
    var NA_MC_TRIALS          = 160;
    var NA_MC_SEED            = 20261009;
    var NA_DEG                = 180 / Math.PI;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Vector Helpers (3D arrays)
    // -------------------------------------------------------------------------

    var na_vec = {
        dot   : function(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; },
        cross : function(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; },
        len   : function(a) { return Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]); },
        add   : function(a, b) { return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]; },
        sub   : function(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; },
        scale : function(a, s) { return [a[0] * s, a[1] * s, a[2] * s]; },
        neg   : function(a) { return [-a[0], -a[1], -a[2]]; },
        unit  : function(a) {
            var n = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
            return n > 1e-300 ? [a[0] / n, a[1] / n, a[2] / n] : [0, 0, 0];
        }
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Small Dense Linear Algebra
    // -------------------------------------------------------------------------

    // Eigen-decomposition of a small symmetric matrix by Jacobi rotations.
    // Returns { values:[...], vectors:[[...]] } with vectors[k] the k-th eigenvector.
    function Na__ImageViewerPerspSolver__SymEig(input) {
        var n = input.length;
        var a = input.map(function(row) { return row.slice(); });
        var v = [];
        for (var i = 0; i < n; i++) {
            v.push([]);
            for (var j = 0; j < n; j++) v[i].push(i === j ? 1 : 0);
        }

        for (var sweep = 0; sweep < 60; sweep++) {
            var off = 0, diag = 0;
            for (var p = 0; p < n; p++) {
                diag += a[p][p] * a[p][p];
                for (var q = p + 1; q < n; q++) off += a[p][q] * a[p][q];
            }
            if (off <= 1e-30 * (diag + 1e-300)) break;

            for (p = 0; p < n; p++) {
                for (q = p + 1; q < n; q++) {
                    if (Math.abs(a[p][q]) < 1e-300) continue;
                    var theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
                    var t = (theta >= 0 ? 1 : -1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
                    var c = 1 / Math.sqrt(t * t + 1);
                    var s = t * c;
                    for (var k = 0; k < n; k++) {
                        var akp = a[k][p], akq = a[k][q];
                        a[k][p] = c * akp - s * akq;
                        a[k][q] = s * akp + c * akq;
                    }
                    for (k = 0; k < n; k++) {
                        var apk = a[p][k], aqk = a[q][k];
                        a[p][k] = c * apk - s * aqk;
                        a[q][k] = s * apk + c * aqk;
                    }
                    for (k = 0; k < n; k++) {
                        var vkp = v[k][p], vkq = v[k][q];
                        v[k][p] = c * vkp - s * vkq;
                        v[k][q] = s * vkp + c * vkq;
                    }
                }
            }
        }

        var values = [], vectors = [];
        for (i = 0; i < n; i++) {
            values.push(a[i][i]);
            var col = [];
            for (j = 0; j < n; j++) col.push(v[j][i]);
            vectors.push(col);
        }
        return { values: values, vectors: vectors };
    }

    // Solve A x = b by Gaussian elimination with partial pivoting; null if singular.
    function Na__ImageViewerPerspSolver__SolveLinear(A, b) {
        var n = b.length;
        var m = A.map(function(row, i) { return row.concat([b[i]]); });
        for (var col = 0; col < n; col++) {
            var piv = col;
            for (var r = col + 1; r < n; r++) {
                if (Math.abs(m[r][col]) > Math.abs(m[piv][col])) piv = r;
            }
            if (Math.abs(m[piv][col]) < 1e-300) return null;
            if (piv !== col) { var tmp = m[piv]; m[piv] = m[col]; m[col] = tmp; }
            for (r = col + 1; r < n; r++) {
                var factor = m[r][col] / m[col][col];
                if (factor === 0) continue;
                for (var k = col; k <= n; k++) m[r][k] -= factor * m[col][k];
            }
        }
        var x = new Array(n);
        for (var i = n - 1; i >= 0; i--) {
            var sum = m[i][n];
            for (var j = i + 1; j < n; j++) sum -= m[i][j] * x[j];
            x[i] = sum / m[i][i];
        }
        return x;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Rotation Frames
    // -------------------------------------------------------------------------
    // A frame is { x:[3], y:[3], z:[3] }: the world axes seen in camera space
    // (the columns of the rotation). It is perturbed on the right by exp([w]x),
    // so every update stays a proper rotation.

    function Na__ImageViewerPerspSolver__RotExp(w) {
        var th2 = w[0] * w[0] + w[1] * w[1] + w[2] * w[2];
        var th  = Math.sqrt(th2);
        var a, b;
        if (th < 1e-6) { a = 1 - th2 / 6; b = 0.5 - th2 / 24; }
        else           { a = Math.sin(th) / th; b = (1 - Math.cos(th)) / th2; }
        var K = [[0, -w[2], w[1]], [w[2], 0, -w[0]], [-w[1], w[0], 0]];
        var E = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
        for (var i = 0; i < 3; i++) {
            for (var j = 0; j < 3; j++) {
                var k2 = K[i][0] * K[0][j] + K[i][1] * K[1][j] + K[i][2] * K[2][j];
                E[i][j] += a * K[i][j] + b * k2;
            }
        }
        return E;
    }

    function Na__ImageViewerPerspSolver__Rotate(frame, w) {
        var E = Na__ImageViewerPerspSolver__RotExp(w);
        var out = {};
        for (var k = 0; k < 3; k++) {
            out[NA_AXIS_NAMES[k]] = [
                E[0][k] * frame.x[0] + E[1][k] * frame.y[0] + E[2][k] * frame.z[0],
                E[0][k] * frame.x[1] + E[1][k] * frame.y[1] + E[2][k] * frame.z[1],
                E[0][k] * frame.x[2] + E[1][k] * frame.y[2] + E[2][k] * frame.z[2]
            ];
        }
        return Na__ImageViewerPerspSolver__Orthonormalise(out);
    }

    function Na__ImageViewerPerspSolver__Orthonormalise(frame) {
        var z = na_vec.unit(frame.z);
        var x = na_vec.unit(na_vec.sub(frame.x, na_vec.scale(z, na_vec.dot(frame.x, z))));
        var y = na_vec.cross(z, x);
        return { x: x, y: y, z: z };
    }

    // Choose the signs a person expects: Z points up the photo, X to its right.
    // Both flips are half turns, so the frame stays right-handed.
    function Na__ImageViewerPerspSolver__CanonicalSigns(frame) {
        var f = { x: frame.x.slice(), y: frame.y.slice(), z: frame.z.slice() };
        if (f.z[1] > 0) { f.z = na_vec.neg(f.z); f.y = na_vec.neg(f.y); }
        if (f.x[0] < 0 || (Math.abs(f.x[0]) < 1e-9 && f.x[2] < 0)) { f.x = na_vec.neg(f.x); f.y = na_vec.neg(f.y); }
        return f;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Lens Conversion (35 mm equivalent <-> pixels)
    // -------------------------------------------------------------------------
    // The 35 mm equivalent focal length is defined on the frame diagonal. A
    // 16:9 or square photo from a phone is a crop of its 4:3 sensor, so the
    // diagonal of that full sensor is used instead of the photo's own.

    function Na__ImageViewerPerspSolver__ReferenceDiagonal(w, h) {
        var longSide  = Math.max(w, h);
        var shortSide = Math.min(w, h) || 1;
        var aspect    = longSide / shortSide;
        if (aspect > 1.6)  return longSide * 1.25;      // 16:9, cropped top and bottom
        if (aspect < 1.15) return longSide * 5 / 3;     // 1:1, cropped at the sides
        return Math.sqrt(w * w + h * h);                // 4:3 and 3:2 frames
    }

    function Na__ImageViewerPerspSolver__LensMmToPx(mm35, w, h) {
        return mm35 * Na__ImageViewerPerspSolver__ReferenceDiagonal(w, h) / NA_FRAME_DIAGONAL_MM;
    }

    function Na__ImageViewerPerspSolver__LensPxToMm(fPx, w, h) {
        return fPx * NA_FRAME_DIAGONAL_MM / Na__ImageViewerPerspSolver__ReferenceDiagonal(w, h);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Point Precision
    // -------------------------------------------------------------------------
    // Each clicked point carries prec: the size of one screen pixel in image
    // pixels when it was placed. Zoomed-out clicks are trusted less.

    function Na__ImageViewerPerspSolver__PointSigma(pt) {
        var prec = (pt && pt.prec > 0) ? pt.prec : 1;
        var click = NA_CLICK_SIGMA * prec;
        return Math.sqrt(NA_EDGE_SIGMA_PX * NA_EDGE_SIGMA_PX + click * click);
    }

    function Na__ImageViewerPerspSolver__LineSigma(line) {
        var sa = Na__ImageViewerPerspSolver__PointSigma(line.a);
        var sb = Na__ImageViewerPerspSolver__PointSigma(line.b);
        return Math.sqrt((sa * sa + sb * sb) / 2);
    }

    function Na__ImageViewerPerspSolver__LineLength(line) {
        var dx = line.b.x - line.a.x, dy = line.b.y - line.a.y;
        return Math.sqrt(dx * dx + dy * dy);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Line Residuals
    // -------------------------------------------------------------------------
    // How far a drawn line misses its axis' vanishing point, in image pixels:
    // the RMS distance of its two ends from the line through its midpoint and
    // the vanishing point. Under click noise sigma this is ~N(0, sigma^2), so
    // residual / sigma is a fair, unit-free score for every line.

    function Na__ImageViewerPerspSolver__LineResidualPx(axisVec, f, line) {
        var vx = f * axisVec[0], vy = f * axisVec[1], vw = axisVec[2];
        var dx = line.b.x - line.a.x, dy = line.b.y - line.a.y;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 1e-9) return 0;
        var mx = (line.a.x + line.b.x) / 2, my = (line.a.y + line.b.y) / 2;
        var ex = vx - vw * mx, ey = vy - vw * my;
        var en = Math.sqrt(ex * ex + ey * ey);
        if (en < 1e-12) return 0;
        var sinA = (dx * ey - dy * ex) / (len * en);
        return (len / Math.SQRT2) * sinA;
    }

    function Na__ImageViewerPerspSolver__Residuals(frame, f, lines, lens) {
        var out = new Array(lines.length + 1);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            out[i] = Na__ImageViewerPerspSolver__LineResidualPx(frame[line.axis], f, line) / line.sigma;
        }
        out[lines.length] = (Math.log(f) - Math.log(lens.fPx)) / lens.sigmaLn;
        return out;
    }

    function Na__ImageViewerPerspSolver__SumSquares(r) {
        var s = 0;
        for (var i = 0; i < r.length; i++) s += r[i] * r[i];
        return s;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Levenberg-Marquardt Refinement
    // -------------------------------------------------------------------------
    // Parameters: a small rotation w (3) applied on the right of the frame and
    // d = change in ln f. Jacobian by central differences (cheap: a few dozen
    // lines at most).

    function Na__ImageViewerPerspSolver__Evaluate(frame, f, p, lines, lens) {
        var fr = Na__ImageViewerPerspSolver__Rotate(frame, [p[0], p[1], p[2]]);
        return Na__ImageViewerPerspSolver__Residuals(fr, f * Math.exp(p[3]), lines, lens);
    }

    function Na__ImageViewerPerspSolver__Jacobian(frame, f, lines, lens) {
        var h = 1e-6;
        var cols = [];
        for (var j = 0; j < 4; j++) {
            var pp = [0, 0, 0, 0], pm = [0, 0, 0, 0];
            pp[j] = h; pm[j] = -h;
            var rp = Na__ImageViewerPerspSolver__Evaluate(frame, f, pp, lines, lens);
            var rm = Na__ImageViewerPerspSolver__Evaluate(frame, f, pm, lines, lens);
            var col = new Array(rp.length);
            for (var i = 0; i < rp.length; i++) col[i] = (rp[i] - rm[i]) / (2 * h);
            cols.push(col);
        }
        return cols; // cols[j][i] = d r_i / d p_j
    }

    function Na__ImageViewerPerspSolver__Normal(cols, r) {
        var JtJ = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];
        var Jtr = [0, 0, 0, 0];
        for (var a = 0; a < 4; a++) {
            for (var i = 0; i < r.length; i++) Jtr[a] += cols[a][i] * r[i];
            for (var b = a; b < 4; b++) {
                var s = 0;
                for (i = 0; i < r.length; i++) s += cols[a][i] * cols[b][i];
                JtJ[a][b] = s;
                JtJ[b][a] = s;
            }
        }
        return { JtJ: JtJ, Jtr: Jtr };
    }

    function Na__ImageViewerPerspSolver__Refine(lines, lens, frame0, f0, maxIter) {
        var frame  = frame0;
        var f      = f0;
        var r      = Na__ImageViewerPerspSolver__Residuals(frame, f, lines, lens);
        var cost   = Na__ImageViewerPerspSolver__SumSquares(r);
        var lambda = 1e-3;

        for (var it = 0; it < maxIter; it++) {
            var cols = Na__ImageViewerPerspSolver__Jacobian(frame, f, lines, lens);
            var ne   = Na__ImageViewerPerspSolver__Normal(cols, r);
            var accepted = false;
            var step = null;

            for (var tries = 0; tries < 10; tries++) {
                var A = ne.JtJ.map(function(row, i) {
                    return row.map(function(v, j) { return i === j ? v + lambda * (v + 1e-9) : v; });
                });
                step = Na__ImageViewerPerspSolver__SolveLinear(A, ne.Jtr.map(function(v) { return -v; }));
                if (!step) { lambda *= 10; continue; }
                var candFrame = Na__ImageViewerPerspSolver__Rotate(frame, [step[0], step[1], step[2]]);
                var candF     = f * Math.exp(step[3]);
                var candR     = Na__ImageViewerPerspSolver__Residuals(candFrame, candF, lines, lens);
                var candCost  = Na__ImageViewerPerspSolver__SumSquares(candR);
                if (isFinite(candCost) && candCost <= cost) {
                    var gain = cost - candCost;
                    frame = candFrame; f = candF; r = candR; cost = candCost;
                    lambda = Math.max(lambda / 3, 1e-12);
                    accepted = true;
                    if (gain <= 1e-12 * (1 + cost)) it = maxIter; // converged
                    break;
                }
                lambda *= 4;
            }
            if (!accepted) break;
            if (step && Math.abs(step[0]) + Math.abs(step[1]) + Math.abs(step[2]) + Math.abs(step[3]) < 1e-11) break;
        }

        return { frame: frame, f: f, cost: cost, residuals: r };
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initial Camera From Vanishing Points
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspSolver__InterpretationNormal(line, f) {
        var ra = [line.a.x, line.a.y, f];
        var rb = [line.b.x, line.b.y, f];
        return na_vec.unit(na_vec.cross(ra, rb));
    }

    // Best common 3D direction of a group of parallel lines for focal length f:
    // the direction most nearly in every line's interpretation plane, each line
    // weighted by how well its angle is known (length^2 / sigma^2).
    function Na__ImageViewerPerspSolver__GroupDirection(group, f) {
        var M = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
        for (var i = 0; i < group.length; i++) {
            var n = Na__ImageViewerPerspSolver__InterpretationNormal(group[i], f);
            var len = Na__ImageViewerPerspSolver__LineLength(group[i]);
            var w = (len * len) / (group[i].sigma * group[i].sigma);
            for (var a = 0; a < 3; a++) {
                for (var b = 0; b < 3; b++) M[a][b] += w * n[a] * n[b];
            }
        }
        var eig = Na__ImageViewerPerspSolver__SymEig(M);
        var best = 0;
        for (var k = 1; k < 3; k++) if (eig.values[k] < eig.values[best]) best = k;
        return na_vec.unit(eig.vectors[best]);
    }

    function Na__ImageViewerPerspSolver__InitialFrame(groups, f) {
        var dir = {}, nrm = {};
        NA_AXIS_NAMES.forEach(function(k) {
            if (groups[k].length >= 2)      dir[k] = Na__ImageViewerPerspSolver__GroupDirection(groups[k], f);
            else if (groups[k].length === 1) nrm[k] = Na__ImageViewerPerspSolver__InterpretationNormal(groups[k][0], f);
        });

        // The axis with the most lines leads (ties: Z, X, Y).
        var order = ['z', 'x', 'y'].sort(function(p, q) { return groups[q].length - groups[p].length; });
        var primary = order[0];
        if (!dir[primary]) return null;

        var frame = {};
        frame[primary] = dir[primary];
        var second = null;
        for (var i = 1; i < order.length && !second; i++) {
            var k = order[i], cand = null;
            if (dir[k]) cand = na_vec.sub(dir[k], na_vec.scale(dir[primary], na_vec.dot(dir[k], dir[primary])));
            else if (nrm[k]) cand = na_vec.cross(dir[primary], nrm[k]);
            if (cand && na_vec.len(cand) > 1e-6) { frame[k] = na_vec.unit(cand); second = k; }
        }
        if (!second) return null;

        if (!frame.z) frame.z = na_vec.cross(frame.x, frame.y);
        if (!frame.x) frame.x = na_vec.cross(frame.y, frame.z);
        if (!frame.y) frame.y = na_vec.cross(frame.z, frame.x);
        return Na__ImageViewerPerspSolver__CanonicalSigns(Na__ImageViewerPerspSolver__Orthonormalise(frame));
    }

    // Focal lengths implied by pairs of groups' vanishing points being at 90
    // degrees: f^2 = -(v1 . v2) with both points measured from the centre.
    function Na__ImageViewerPerspSolver__ClosedFormFocals(groups, w, h) {
        var s = Math.sqrt(w * w + h * h) / 2 || 1000;
        var vps = {};
        NA_AXIS_NAMES.forEach(function(k) {
            if (groups[k].length >= 2) vps[k] = Na__ImageViewerPerspSolver__GroupDirection(groups[k], s);
        });
        var out = [];
        var pairs = [['x', 'y'], ['x', 'z'], ['y', 'z']];
        pairs.forEach(function(pair) {
            var a = vps[pair[0]], b = vps[pair[1]];
            if (!a || !b) return;
            if (Math.abs(a[2]) < 1e-9 || Math.abs(b[2]) < 1e-9) return;
            var f2 = -s * s * (a[0] * b[0] + a[1] * b[1]) / (a[2] * b[2]);
            if (f2 > 0 && isFinite(f2)) out.push(Math.sqrt(f2));
        });
        return out;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Calibration
    // -------------------------------------------------------------------------

    // Generic determinacy rule for the camera rotation: lines on two axes, at
    // least three lines, and two of them on one axis.
    function Na__ImageViewerPerspSolver__NeedText(counts) {
        var total = counts.x + counts.y + counts.z;
        var axes  = (counts.x > 0 ? 1 : 0) + (counts.y > 0 ? 1 : 0) + (counts.z > 0 ? 1 : 0);
        var most  = Math.max(counts.x, counts.y, counts.z);
        if (total === 0) return 'Draw 2 or more verticals and 2 or more level lines on the wall you are measuring.';
        if (axes < 2) {
            if (counts.z > 0) return 'Now draw level lines (red) on the wall you are measuring.';
            return 'Now draw 2 or more verticals (blue): corners, chimney sides, window jambs.';
        }
        if (total < 3 || most < 2) return 'Add one more line: one of the colours needs two.';
        return null;
    }

    function Na__ImageViewerPerspSolver__PrepareLines(lines) {
        var out = [];
        (lines || []).forEach(function(line, i) {
            if (!line || !line.a || !line.b) return;
            if (line.axis !== 'x' && line.axis !== 'y' && line.axis !== 'z') return;
            if (Na__ImageViewerPerspSolver__LineLength(line) < NA_MIN_LINE_PX) return;
            out.push({
                axis  : line.axis,
                a     : { x: line.a.x, y: line.a.y, prec: line.a.prec },
                b     : { x: line.b.x, y: line.b.y, prec: line.b.prec },
                sigma : Na__ImageViewerPerspSolver__LineSigma(line),
                index : i,
                id    : line.id
            });
        });
        return out;
    }

    function Na__ImageViewerPerspSolver__Groups(prepared) {
        var groups = { x: [], y: [], z: [] };
        prepared.forEach(function(line) { groups[line.axis].push(line); });
        return groups;
    }

    // lines : [{ axis:'x'|'y'|'z', a:{x,y,prec}, b:{x,y,prec}, id }]
    // lens  : { fPx:Number, sigmaLn:Number }  (focal length prior)
    // size  : { w, h }  image size in pixels
    function Na__ImageViewerPerspSolver__Calibrate(lines, lens, size) {
        var prepared = Na__ImageViewerPerspSolver__PrepareLines(lines);
        var groups   = Na__ImageViewerPerspSolver__Groups(prepared);
        var counts   = { x: groups.x.length, y: groups.y.length, z: groups.z.length };
        var need     = Na__ImageViewerPerspSolver__NeedText(counts);
        if (need) return { ok: false, need: need, counts: counts };
        if (!lens || !(lens.fPx > 0) || !(lens.sigmaLn > 0)) return { ok: false, need: 'Lens setting is missing.', counts: counts };

        var w = (size && size.w) || 4032, h = (size && size.h) || 3024;
        var starts = [lens.fPx, lens.fPx * 0.8, lens.fPx * 1.25];
        Na__ImageViewerPerspSolver__ClosedFormFocals(groups, w, h).forEach(function(fc) {
            if (fc > lens.fPx * 0.25 && fc < lens.fPx * 4) starts.push(fc);
        });

        var best = null;
        starts.forEach(function(fs) {
            var frame = Na__ImageViewerPerspSolver__InitialFrame(groups, fs);
            if (!frame) return;
            var sol = Na__ImageViewerPerspSolver__Refine(prepared, lens, frame, fs, 60);
            if (isFinite(sol.cost) && (!best || sol.cost < best.cost)) best = sol;
        });
        if (!best) return { ok: false, need: 'These lines do not fix the camera. Spread them out across the photo.', counts: counts };

        // Is the rotation pinned down by the lines (the prior only covers the lens)?
        var cols = Na__ImageViewerPerspSolver__Jacobian(best.frame, best.f, prepared, lens);
        var ne   = Na__ImageViewerPerspSolver__Normal(cols, best.residuals);
        var eig  = Na__ImageViewerPerspSolver__SymEig(ne.JtJ);
        var minEig = Math.min.apply(null, eig.values);
        if (!(minEig > 1e-4)) {
            return { ok: false, need: 'These lines do not fix the camera. Spread them out, or add a line in another direction.', counts: counts };
        }

        var frame = Na__ImageViewerPerspSolver__CanonicalSigns(best.frame);
        var lineCost = 0;
        var lineDiag = prepared.map(function(line, i) {
            var z = best.residuals[i];
            lineCost += z * z;
            return { id: line.id, index: line.index, axis: line.axis, residualPx: z * line.sigma, z: z };
        });

        var redundancy = prepared.length - 3;
        var varianceFactor = redundancy >= 2 ? Math.max(1, best.cost / redundancy) : 1;
        varianceFactor = Math.min(varianceFactor, 100);
        var rmsPx = 0;
        lineDiag.forEach(function(d) { rmsPx += d.residualPx * d.residualPx; });
        rmsPx = Math.sqrt(rmsPx / Math.max(1, lineDiag.length));
        // Flag a line against a robust spread (median absolute score), so one
        // badly drawn line cannot hide itself by inflating the average.
        var absZ = lineDiag.map(function(d) { return Math.abs(d.z); }).sort(function(p, q) { return p - q; });
        var robust = Math.max(1, 1.4826 * absZ[Math.floor(absZ.length / 2)]);
        lineDiag.forEach(function(d) {
            d.flagged = lineDiag.length >= 4 && Math.abs(d.z) / robust > 3.5 && Math.abs(d.residualPx) > 1.5;
        });

        return {
            ok             : true,
            frame          : frame,
            f              : best.f,
            cost           : best.cost,
            lineCost       : lineCost,
            counts         : counts,
            lines          : lineDiag,
            rmsPx          : rmsPx,
            varianceFactor : varianceFactor,
            priorPull      : (Math.log(best.f) - Math.log(lens.fPx)) / lens.sigmaLn,
            lens           : { fPx: lens.fPx, sigmaLn: lens.sigmaLn },
            size           : { w: w, h: h }
        };
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Projection Helpers
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspSolver__Project(cal, X) {
        if (!X || Math.abs(X[2]) < 1e-12) return null;
        return { x: cal.f * X[0] / X[2], y: cal.f * X[1] / X[2] };
    }

    // Homogeneous image point of an axis' vanishing point: { x, y, w }.
    function Na__ImageViewerPerspSolver__VanishingPoint(cal, axis) {
        var a = cal.frame[axis];
        return { x: cal.f * a[0], y: cal.f * a[1], w: a[2] };
    }

    // Where the clicked ray meets the plane through the chosen world axes.
    // The plane sits at unit distance on the side the point is seen on, so
    // two points on opposite sides of the plane's vanishing line are refused.
    function Na__ImageViewerPerspSolver__BackProject(cal, plane, pt) {
        var N = cal.frame[NA_PLANE_NORMAL_AXIS[plane]];
        var r = [pt.x, pt.y, cal.f];
        var d = na_vec.dot(N, r);
        var cosine = d / na_vec.len(r);
        if (!isFinite(cosine) || Math.abs(cosine) < 1e-7) return null;
        return { X: na_vec.scale(r, 1 / Math.abs(d)), side: d > 0 ? 1 : -1 };
    }

    // Image points along an arc on a plane: centre C, from direction A toward
    // direction B (both 3D), radius rho in plane units.
    function Na__ImageViewerPerspSolver__ArcPolyline(cal, C, dirA, dirB, rho, steps) {
        var e1 = na_vec.unit(dirA);
        var perp = na_vec.sub(dirB, na_vec.scale(e1, na_vec.dot(dirB, e1)));
        if (na_vec.len(perp) < 1e-12) return [];
        var e2 = na_vec.unit(perp);
        var sweep = Math.atan2(na_vec.dot(dirB, e2), na_vec.dot(dirB, e1));
        var out = [];
        var n = Math.max(2, steps || 24);
        for (var i = 0; i <= n; i++) {
            var t = sweep * i / n;
            var P = na_vec.add(C, na_vec.add(na_vec.scale(e1, rho * Math.cos(t)), na_vec.scale(e2, rho * Math.sin(t))));
            var p = Na__ImageViewerPerspSolver__Project(cal, P);
            if (p) out.push(p);
        }
        return out;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Measurements
    // -------------------------------------------------------------------------
    // m = { kind:'pitch'|'angle', plane:'xz'|'yz'|'xy', pts:[{x,y,prec}...] }
    //   pitch: two points along a sloping edge; the angle above level.
    //   angle: three points, the middle one the corner.

    function Na__ImageViewerPerspSolver__Raw2d(m) {
        var p = m.pts;
        if (m.kind === 'pitch' && p.length >= 2) {
            return Math.atan2(Math.abs(p[1].y - p[0].y), Math.abs(p[1].x - p[0].x)) * NA_DEG;
        }
        if (m.kind === 'angle' && p.length >= 3) {
            var ux = p[0].x - p[1].x, uy = p[0].y - p[1].y;
            var wx = p[2].x - p[1].x, wy = p[2].y - p[1].y;
            return Math.atan2(Math.abs(ux * wy - uy * wx), ux * wx + uy * wy) * NA_DEG;
        }
        return null;
    }

    function Na__ImageViewerPerspSolver__Measure(cal, m) {
        var out = { ok: false, value: null, raw2d: Na__ImageViewerPerspSolver__Raw2d(m), reason: '' };
        var needPts = m.kind === 'angle' ? 3 : 2;
        if (!m.pts || m.pts.length < needPts) { out.reason = 'points'; return out; }
        if (!cal || !cal.ok) { out.reason = 'uncalibrated'; return out; }
        if (!NA_PLANE_NORMAL_AXIS[m.plane]) { out.reason = 'plane'; return out; }
        if (m.kind === 'pitch' && !NA_PLANE_LEVEL_AXIS[m.plane]) { out.reason = 'pitch-on-ground'; return out; }

        var X = [], side = 0;
        for (var i = 0; i < needPts; i++) {
            var bp = Na__ImageViewerPerspSolver__BackProject(cal, m.plane, m.pts[i]);
            if (!bp || (side && bp.side !== side)) { out.reason = 'horizon'; return out; }
            side = bp.side;
            X.push(bp.X);
        }

        var up = cal.frame.z;
        if (m.kind === 'pitch') {
            var t  = na_vec.sub(X[1], X[0]);
            var tl = na_vec.len(t);
            if (tl < 1e-12) { out.reason = 'short'; return out; }
            out.value = Math.asin(Math.min(1, Math.abs(na_vec.dot(t, up)) / tl)) * NA_DEG;

            // The pitch triangle on the wall: level run from the lower end,
            // then the rise straight up to the upper end.
            var lo = na_vec.dot(X[0], up) <= na_vec.dot(X[1], up) ? 0 : 1;
            var hi = 1 - lo;
            var level = cal.frame[NA_PLANE_LEVEL_AXIS[m.plane]];
            var run   = na_vec.dot(na_vec.sub(X[hi], X[lo]), level);
            var foot  = na_vec.add(X[lo], na_vec.scale(level, run));
            out.draw = {
                lo     : lo,
                hi     : hi,
                X      : X,
                foot   : foot,
                footPt : Na__ImageViewerPerspSolver__Project(cal, foot),
                centre : X[lo],
                dirA   : na_vec.sub(foot, X[lo]),
                dirB   : na_vec.sub(X[hi], X[lo]),
                armLen : Math.min(Math.abs(run), tl)
            };
        } else {
            var u = na_vec.sub(X[0], X[1]);
            var w = na_vec.sub(X[2], X[1]);
            if (na_vec.len(u) < 1e-12 || na_vec.len(w) < 1e-12) { out.reason = 'short'; return out; }
            out.value = Math.atan2(na_vec.len(na_vec.cross(u, w)), na_vec.dot(u, w)) * NA_DEG;
            out.draw = { X: X, centre: X[1], dirA: u, dirB: w, armLen: Math.min(na_vec.len(u), na_vec.len(w)) };
        }
        out.ok = true;
        return out;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Monte Carlo Uncertainty
    // -------------------------------------------------------------------------

    function Na__ImageViewerPerspSolver__Rng(seed) {
        var s = seed >>> 0;
        var spare = null;
        function uniform() {
            s = (s + 0x6D2B79F5) >>> 0;
            var t = s;
            t = Math.imul(t ^ (t >>> 15), t | 1);
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        }
        return {
            gauss: function() {
                if (spare !== null) { var v = spare; spare = null; return v; }
                var u1 = 0;
                while (u1 <= 1e-12) u1 = uniform();
                var u2 = uniform();
                var mag = Math.sqrt(-2 * Math.log(u1));
                spare = mag * Math.sin(2 * Math.PI * u2);
                return mag * Math.cos(2 * Math.PI * u2);
            }
        };
    }

    function Na__ImageViewerPerspSolver__Jitter(pt, k, rng) {
        var s = Na__ImageViewerPerspSolver__PointSigma(pt) * k;
        return { x: pt.x + s * rng.gauss(), y: pt.y + s * rng.gauss(), prec: pt.prec };
    }

    // input: { lines, lens:{fPx, sigmaLn}, size:{w,h}, measurements:[m], trials }
    // Each measurement may carry an id; it seeds that measurement's own noise
    // so adding a second angle does not shift the first one's reading.
    function Na__ImageViewerPerspSolver__Analyse(input) {
        var cal     = Na__ImageViewerPerspSolver__Calibrate(input.lines, input.lens, input.size);
        var meas    = input.measurements || [];
        var results = meas.map(function(m) { return Na__ImageViewerPerspSolver__Measure(cal, m); });
        var trials  = input.trials === undefined ? NA_MC_TRIALS : input.trials;
        if (!cal.ok || !(trials > 0)) return { cal: cal, results: results };

        var k        = Math.sqrt(cal.varianceFactor || 1);
        var prepared = Na__ImageViewerPerspSolver__PrepareLines(input.lines);
        var lineRng  = Na__ImageViewerPerspSolver__Rng(NA_MC_SEED);
        var measRngs = meas.map(function(m, i) {
            return Na__ImageViewerPerspSolver__Rng(NA_MC_SEED + 7919 * ((m.id || i + 1) % 100003));
        });
        var acc = results.map(function() { return { n: 0, ss: 0 }; });
        var lnF = [];

        for (var t = 0; t < trials; t++) {
            var jittered = prepared.map(function(line) {
                var j = {
                    axis : line.axis,
                    a    : Na__ImageViewerPerspSolver__Jitter(line.a, k, lineRng),
                    b    : Na__ImageViewerPerspSolver__Jitter(line.b, k, lineRng)
                };
                j.sigma = line.sigma;
                return j;
            });
            var lensT = { fPx: cal.lens.fPx * Math.exp(cal.lens.sigmaLn * lineRng.gauss()), sigmaLn: cal.lens.sigmaLn };
            var sol   = Na__ImageViewerPerspSolver__Refine(jittered, lensT, cal.frame, cal.f, 15);
            var calT  = { ok: true, frame: Na__ImageViewerPerspSolver__CanonicalSigns(sol.frame), f: sol.f };
            lnF.push(Math.log(sol.f));

            for (var i = 0; i < meas.length; i++) {
                var mRng = measRngs[i];
                var m    = meas[i];
                var mT   = { kind: m.kind, plane: m.plane, pts: m.pts.map(function(p) { return Na__ImageViewerPerspSolver__Jitter(p, k, mRng); }) };
                if (!results[i].ok) continue;
                var r = Na__ImageViewerPerspSolver__Measure(calT, mT);
                if (!r.ok) continue;
                var d = r.value - results[i].value;
                acc[i].n++;
                acc[i].ss += d * d;
            }
        }

        results.forEach(function(res, i) {
            if (!res.ok) return;
            res.sigma         = acc[i].n > 1 ? Math.sqrt(acc[i].ss / acc[i].n) : null;
            res.validFraction = acc[i].n / trials;
        });

        var mean = 0;
        lnF.forEach(function(v) { mean += v; });
        mean /= lnF.length;
        var varLn = 0;
        lnF.forEach(function(v) { varLn += (v - mean) * (v - mean); });
        cal.fSigmaLn = Math.sqrt(varLn / Math.max(1, lnF.length - 1));

        return { cal: cal, results: results };
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Guides
    // -------------------------------------------------------------------------
    // A guide is an infinite 3D line through a clicked point. Every line along
    // direction d runs toward the same vanishing point, so the guide's image
    // is the line through the clicked point and that vanishing point. Points
    // in front of the camera are seen from the vanishing point outward, so a
    // vanishing point inside the photo ends the guide there.

    // Homogeneous image point { x, y, w } toward which lines along d run.
    function Na__ImageViewerPerspSolver__DirectionVanishingPoint(cal, d) {
        return { x: cal.f * d[0], y: cal.f * d[1], w: d[2] };
    }

    // A slope on a wall: deg above level, toward +level (side 1) or -level (side -1).
    function Na__ImageViewerPerspSolver__WallDirection(cal, plane, deg, side) {
        var levelAxis = NA_PLANE_LEVEL_AXIS[plane];
        if (!levelAxis || !cal || !cal.frame) return null;
        var t = deg * Math.PI / 180;
        return na_vec.unit(na_vec.add(na_vec.scale(cal.frame[levelAxis], side * Math.cos(t)), na_vec.scale(cal.frame.z, Math.sin(t))));
    }

    // 3D direction of a measured pitch (from its lower to its upper end).
    function Na__ImageViewerPerspSolver__MeasurementDirection(res) {
        if (!res || !res.ok || !res.draw || !res.draw.X || res.draw.X.length !== 2) return null;
        return na_vec.unit(na_vec.sub(res.draw.X[res.draw.hi], res.draw.X[res.draw.lo]));
    }

    // Parameter range [t0, t1] of the line p + t d inside the photo, or null.
    function Na__ImageViewerPerspSolver__ClipLine(p, d, size) {
        var hw = size.w / 2, hh = size.h / 2;
        var t0 = -Infinity, t1 = Infinity;
        var axes = [[p.x, d.x, hw], [p.y, d.y, hh]];
        for (var i = 0; i < 2; i++) {
            var p0 = axes[i][0], dv = axes[i][1], half = axes[i][2];
            if (Math.abs(dv) < 1e-12) {
                if (p0 < -half || p0 > half) return null;
                continue;
            }
            var ta = (-half - p0) / dv, tb = (half - p0) / dv;
            if (ta > tb) { var swap = ta; ta = tb; tb = swap; }
            if (ta > t0) t0 = ta;
            if (tb < t1) t1 = tb;
        }
        return t1 - t0 > 1e-9 ? [t0, t1] : null;
    }

    // Visible part of the guide through p toward vanishing point vp: { a, b }.
    function Na__ImageViewerPerspSolver__GuideSegment(p, vp, size) {
        if (!p || !vp) return null;
        var dx = vp.x - vp.w * p.x, dy = vp.y - vp.w * p.y;
        if (vp.w < 0) { dx = -dx; dy = -dy; }       // d now points from p toward the vanishing point
        var dl = Math.sqrt(dx * dx + dy * dy);
        if (dl < 1e-12) return null;
        var d = { x: dx / dl, y: dy / dl };
        var span = Na__ImageViewerPerspSolver__ClipLine(p, d, size);
        if (!span) return null;
        var t0 = span[0], t1 = span[1];
        if (Math.abs(vp.w) > 1e-12) {
            var tv = (vp.x / vp.w - p.x) * d.x + (vp.y / vp.w - p.y) * d.y;
            if (tv < t1) t1 = Math.max(tv, t0);
        }
        if (t1 - t0 < 1e-6) return null;
        return { a: { x: p.x + d.x * t0, y: p.y + d.y * t0 }, b: { x: p.x + d.x * t1, y: p.y + d.y * t1 } };
    }

    // A straight guide through two clicked points, across the photo.
    function Na__ImageViewerPerspSolver__FreeSegment(p, q, size) {
        if (!p || !q) return null;
        var dx = q.x - p.x, dy = q.y - p.y;
        var dl = Math.sqrt(dx * dx + dy * dy);
        if (dl < 1e-9) return null;
        var d = { x: dx / dl, y: dy / dl };
        var span = Na__ImageViewerPerspSolver__ClipLine(p, d, size);
        if (!span) return null;
        return { a: { x: p.x + d.x * span[0], y: p.y + d.y * span[0] }, b: { x: p.x + d.x * span[1], y: p.y + d.y * span[1] } };
    }

    function Na__ImageViewerPerspSolver__SegmentIntersection(s1, s2) {
        var rx = s1.b.x - s1.a.x, ry = s1.b.y - s1.a.y;
        var sx = s2.b.x - s2.a.x, sy = s2.b.y - s2.a.y;
        var den = rx * sy - ry * sx;
        if (Math.abs(den) < 1e-9 * (Math.abs(rx) + Math.abs(ry)) * (Math.abs(sx) + Math.abs(sy))) return null;
        var qx = s2.a.x - s1.a.x, qy = s2.a.y - s1.a.y;
        var t = (qx * sy - qy * sx) / den;
        var u = (qx * ry - qy * rx) / den;
        if (t < 0 || t > 1 || u < 0 || u > 1) return null;
        return { x: s1.a.x + t * rx, y: s1.a.y + t * ry };
    }

    // Nearest point on a segment, with its distance.
    function Na__ImageViewerPerspSolver__ClosestOnSegment(p, s) {
        var dx = s.b.x - s.a.x, dy = s.b.y - s.a.y;
        var l2 = dx * dx + dy * dy;
        var t = l2 > 0 ? Math.max(0, Math.min(1, ((p.x - s.a.x) * dx + (p.y - s.a.y) * dy) / l2)) : 0;
        var c = { x: s.a.x + t * dx, y: s.a.y + t * dy };
        return { point: c, dist: Math.sqrt((p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y)) };
    }

    // Which candidate direction is the pointer moving along from the anchor?
    // candidates: [{ vp, ... }]. Lines are undirected, so either way counts.
    // Returns { candidate, angle } within tolDeg, or null.
    function Na__ImageViewerPerspSolver__InferGuide(anchor, pointer, candidates, tolDeg) {
        var mx = pointer.x - anchor.x, my = pointer.y - anchor.y;
        var ml = Math.sqrt(mx * mx + my * my);
        if (ml < 1e-9) return null;
        var best = null, bestAng = tolDeg;
        (candidates || []).forEach(function(c) {
            if (!c || !c.vp) return;
            var dx = c.vp.x - c.vp.w * anchor.x, dy = c.vp.y - c.vp.w * anchor.y;
            var dl = Math.sqrt(dx * dx + dy * dy);
            if (dl < 1e-12) return;
            var ang = Math.acos(Math.min(1, Math.abs(mx * dx + my * dy) / (ml * dl))) * NA_DEG;
            if (ang <= bestAng) { bestAng = ang; best = c; }
        });
        return best ? { candidate: best, angle: bestAng } : null;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Public Surface
    // -------------------------------------------------------------------------

    var api = {
        calibrate      : Na__ImageViewerPerspSolver__Calibrate,
        measure        : Na__ImageViewerPerspSolver__Measure,
        analyse        : Na__ImageViewerPerspSolver__Analyse,
        project        : Na__ImageViewerPerspSolver__Project,
        backProject    : Na__ImageViewerPerspSolver__BackProject,
        vanishingPoint : Na__ImageViewerPerspSolver__VanishingPoint,
        arcPolyline    : Na__ImageViewerPerspSolver__ArcPolyline,
        lensMmToPx     : Na__ImageViewerPerspSolver__LensMmToPx,
        lensPxToMm     : Na__ImageViewerPerspSolver__LensPxToMm,
        pointSigma     : Na__ImageViewerPerspSolver__PointSigma,
        planeAxes      : NA_PLANE_AXES,
        planeLevelAxis : NA_PLANE_LEVEL_AXIS,
        vec            : na_vec,
        // guides
        directionVanishingPoint : Na__ImageViewerPerspSolver__DirectionVanishingPoint,
        wallDirection           : Na__ImageViewerPerspSolver__WallDirection,
        measurementDirection    : Na__ImageViewerPerspSolver__MeasurementDirection,
        guideSegment            : Na__ImageViewerPerspSolver__GuideSegment,
        freeSegment             : Na__ImageViewerPerspSolver__FreeSegment,
        segmentIntersection     : Na__ImageViewerPerspSolver__SegmentIntersection,
        closestOnSegment        : Na__ImageViewerPerspSolver__ClosestOnSegment,
        inferGuide              : Na__ImageViewerPerspSolver__InferGuide,
        // exposed for the tests
        _symEig        : Na__ImageViewerPerspSolver__SymEig,
        _rotExp        : Na__ImageViewerPerspSolver__RotExp
    };

    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.Na__ImageViewer__PerspectiveSolver = api;

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})(typeof window !== 'undefined' ? window : null);
