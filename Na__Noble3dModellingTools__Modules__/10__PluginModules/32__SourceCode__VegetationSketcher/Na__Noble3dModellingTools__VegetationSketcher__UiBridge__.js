// =============================================================================
// NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__VegetationSketcher__UiBridge__.js
// NAMESPACE  : window.Na__VegetationSketcher__Receive
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Drive presets, form controls and the canvas preview, then send
//              acknowledged commands to Ruby
// CREATED    : 2026
//
// Form edits wait 650 ms without further input. Repeated options coalesce.
// Draw, Finish and Update carry the current form immediately.
//
// RUBY -> JS : Na__VegetationSketcher__Receive(event, payload)
// JS -> RUBY : sketchup.na_dialog_ready / na_event
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants and Module State
    // -------------------------------------------------------------------------

    var NA_SETTINGS_DEBOUNCE_MS = 650;
    var NA_ACK_TIMEOUT_MS = 45000;
    var NA_CONNECT_RETRY_MS = 400;
    var NA_CONNECT_ATTEMPTS = 20;
    var NA_IMMEDIATE_ACTIONS = ['start', 'stop', 'update', 'variation', 'preset', 'tree_type', 'new', 'load'];
    var NA_CONTEXT_SENSITIVE_ACTIONS = ['options', 'variation', 'update', 'live', 'tree_type'];

    var naState = {
        settings: { preset: 'hedge' },
        mesh: null,
        timer: null,
        yaw: -0.7,
        pitch: 0.38,
        dragging: null,
        limit: 80000,
        placing: false,
        ready: false,
        targetId: null,
        context: null,
        session: null,
        revision: 0,
        sequence: 0,
        inFlight: null,
        pending: [],
        ackTimer: null,
        readyTimer: null,
        validationError: false,
        treeTypes: {}
    };

    var naCanvas = na_el('naVegetation_canvasPreview');
    var naCtx = naCanvas.getContext('2d');

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_el(elementId) {
        return document.getElementById(elementId);
    }

    function na_optionKey(input) {
        return input.getAttribute('data-option');
    }

    function na_optionInputs() {
        return document.querySelectorAll('[data-option]');
    }

    function na_setStatus(message, variant) {
        var statusEl = na_el('naVegetation_status');
        statusEl.textContent = message;
        statusEl.className = 'naVegetation__Status';
        if (variant === 'error') {
            statusEl.classList.add('naVegetation__Status--error');
        } else if (variant === 'success') {
            statusEl.classList.add('naVegetation__Status--success');
        }
    }

    function na_callRuby(callbackName, argumentValue) {
        if (!window.sketchup || typeof window.sketchup[callbackName] !== 'function') {
            throw Error('SketchUp bridge unavailable. Reopen Vegetation Sketcher.');
        }
        if (arguments.length > 1) {
            window.sketchup[callbackName](argumentValue);
        } else {
            window.sketchup[callbackName]();
        }
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Acknowledged Command Bus
    // -------------------------------------------------------------------------

    function na_drain() {
        if (!naState.ready || naState.inFlight || !naState.pending.length) {
            return;
        }
        naState.inFlight = naState.pending.shift();
        try {
            na_callRuby('na_event', JSON.stringify(naState.inFlight));
            naState.ackTimer = setTimeout(function () {
                naState.ready = false;
                naState.pending = [];
                na_setStatus('SketchUp has not acknowledged the command. Wait for SketchUp, then reopen Vegetation Sketcher before retrying.', 'error');
                na_updateLabels();
            }, NA_ACK_TIMEOUT_MS);
        } catch (error) {
            naState.ready = false;
            naState.inFlight = null;
            naState.pending = [];
            na_setStatus(error.message, 'error');
            na_updateLabels();
        }
    }

    function na_command(action, payload) {
        payload = payload || {};
        if (!naState.ready) {
            na_setStatus('Waiting for the SketchUp connection. Reopen the dialog if it does not connect.', 'error');
            return;
        }
        var item = {
            id: ++naState.sequence,
            session: naState.session,
            action: action,
            revision: naState.revision,
            payload: Object.assign({ context: naState.context, target_id: naState.targetId }, payload)
        };
        if (NA_IMMEDIATE_ACTIONS.indexOf(action) !== -1) {
            naState.pending = naState.pending.filter(function (queued) {
                return queued.action !== 'options';
            });
        }
        if (action === 'options' && naState.pending.length && naState.pending[naState.pending.length - 1].action === 'options') {
            naState.pending.pop();
        }
        naState.pending.push(item);
        na_drain();
    }

    function na_collect(interactive) {
        var next = Object.assign({}, naState.settings);
        var inputs = na_optionInputs();
        var i;
        var input;
        var name;
        for (i = 0; i < inputs.length; i++) {
            input = inputs[i];
            if (input.disabled) {
                continue;
            }
            if (input.type !== 'checkbox' && (!input.checkValidity() || input.value.trim() === '' || !Number.isFinite(Number(input.value)))) {
                name = na_optionKey(input).replace(/_/g, ' ');
                naState.validationError = true;
                na_setStatus('Enter a valid ' + name + (input.min && input.max ? ' from ' + input.min + ' to ' + input.max : '') + '.', 'error');
                if (interactive) {
                    input.reportValidity();
                }
                return null;
            }
            next[na_optionKey(input)] = input.type === 'checkbox' ? input.checked : Number(input.value);
        }
        if (next.preset === 'hedge' && next.path && next.length !== naState.settings.length) {
            next.path = na_scalePath(next.path, next.length / naState.settings.length);
        }
        if (naState.validationError) {
            naState.validationError = false;
            na_setStatus('Ready.');
        }
        return next;
    }

    function na_scalePath(path, factor) {
        var origin = path[0];
        return path.map(function (point) {
            return point.map(function (n, i) {
                return i === 2 ? 0 : origin[i] + (n - origin[i]) * factor;
            });
        });
    }

    function na_sendSettings() {
        clearTimeout(naState.timer);
        var value = na_collect();
        if (!value) {
            return;
        }
        naState.settings = value;
        na_command('options', { settings: value });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Labels and Control State
    // -------------------------------------------------------------------------

    function na_metres(n) {
        return (n / 1000).toLocaleString(undefined, { maximumFractionDigits: 3 });
    }

    function na_updateLabels() {
        var settings = naState.settings;
        var species = settings.preset === 'tree' && settings.tree_type && settings.tree_type !== 'generic';
        var tree = naState.treeTypes[settings.tree_type] || {};
        var over = naState.mesh && naState.mesh.requested_quads > naState.limit;

        na_el('naVegetation_softenValue').textContent = na_el('naVegetation_rngSoften').value + '%';
        na_el('naVegetation_randomValue').textContent = na_el('naVegetation_rngRandom').value + ' mm';
        na_updateScopedVisibility(settings.preset);
        na_updatePresetButtons(settings.preset);

        na_el('naVegetation_widthLabel').textContent = settings.preset === 'tree' ? 'Canopy width' : 'Width';
        na_el('naVegetation_treeInfo').textContent = (tree.botanical ? tree.botanical + ' · ' : '') + (tree.description || 'An adjustable rounded whitecard canopy.');
        na_el('naVegetation_softenLabel').textContent = species ? 'Crown rounding' : 'Soften corners';
        na_el('naVegetation_treeScale').textContent = settings.preset === 'tree'
            ? 'Model size: ' + na_metres(settings.height) + ' m high · ' + na_metres(settings.width) + ' × ' + na_metres(settings.depth) + ' m canopy'
            : '';
        na_el('naVegetation_lengthLabel').textContent = settings.path ? 'Total path length' : 'Preview length';
        na_el('naVegetation_dimensionHint').textContent = na_dimensionHint(settings, species);
        na_el('naVegetation_btnStart').textContent = na_startLabel(settings, species, tree);
        na_el('naVegetation_help').textContent = settings.preset === 'hedge'
            ? 'Click corners; Enter, double-click or Finish builds the hedge. Right/Left: red/green. Down: parallel. Up: unlock. Backspace: undo point. Esc: cancel.'
            : 'Click in the model to plant. R: new variation. Esc: finish.';
        na_el('naVegetation_btnStop').hidden = !naState.placing;
        na_el('naVegetation_btnStop').textContent = settings.preset === 'hedge' ? 'Finish hedge' : 'Finish';
        na_el('naVegetation_viewportState').hidden = !naState.placing;
        na_el('naVegetation_btnStart').disabled = !naState.ready || naState.placing || (over && settings.preset !== 'hedge');
        na_el('naVegetation_btnNew').disabled = !naState.ready;
        na_el('naVegetation_btnVariation').disabled = !naState.ready;
        na_el('naVegetation_editControls').hidden = !naState.targetId || naState.placing;
        na_el('naVegetation_btnUpdate').disabled = !naState.ready || !naState.targetId || naState.placing || over;
        na_el('naVegetation_btnLoad').disabled = !naState.ready || !naState.targetId || naState.placing;
        na_el('naVegetation_chkLive').disabled = !naState.ready || !naState.targetId || naState.placing;
        na_el('naVegetation_modeLabel').textContent = !naState.ready
            ? 'Connecting to SketchUp'
            : naState.placing
                ? 'Draw mode active'
                : naState.targetId
                    ? 'Editing selected vegetation'
                    : 'Create new vegetation';
    }

    function na_updateScopedVisibility(preset) {
        var scoped = document.querySelectorAll('[data-for]');
        var i;
        var el;
        var nested;
        var j;
        for (i = 0; i < scoped.length; i++) {
            el = scoped[i];
            el.hidden = el.dataset.for === 'plant' ? preset === 'hedge' : preset !== el.dataset.for;
            nested = el.querySelectorAll('input,select');
            for (j = 0; j < nested.length; j++) {
                nested[j].disabled = el.hidden || !naState.ready;
            }
        }
    }

    function na_updatePresetButtons(preset) {
        var buttons = document.querySelectorAll('[data-preset]');
        var i;
        for (i = 0; i < buttons.length; i++) {
            buttons[i].setAttribute('aria-pressed', String(buttons[i].dataset.preset === preset));
            buttons[i].disabled = !naState.ready;
        }
    }

    function na_dimensionHint(settings, species) {
        if (settings.preset === 'hedge') {
            return settings.path
                ? 'Changing total length scales the saved path, keeping its turns. Width stays independent.'
                : 'Click each corner. Type a length for the next run in SketchUp.';
        }
        if (settings.preset === 'tree') {
            return species
                ? 'Exact overall size, including organic variation. Height includes the trunk; crown base sets the lowest foliage.'
                : 'Height includes the trunk and crown. The trunk extends into the canopy.';
        }
        return 'Width and depth set the footprint. Click to plant at the cursor.';
    }

    function na_startLabel(settings, species, tree) {
        if (naState.placing) {
            return 'Drawing in SketchUp...';
        }
        if (settings.preset === 'hedge') {
            return 'Draw hedge in SketchUp';
        }
        if (settings.preset === 'tree') {
            return 'Plant ' + (species ? tree.name || 'tree' : 'tree') + ' in SketchUp';
        }
        return 'Plant shrub in SketchUp';
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Ruby Event Handlers
    // -------------------------------------------------------------------------

    function na_receive(event, payload) {
        if (event === 'state') {
            na_receiveState(payload);
        } else if (event === 'ack') {
            na_receiveAck(payload);
        } else if (event === 'preview') {
            na_receivePreview(payload);
        } else if (event === 'status') {
            na_setStatus(payload.message, payload.variant);
        } else if (event === 'viewport') {
            na_receiveViewport(payload);
        } else if (event === 'created') {
            na_el('naVegetation_selectionInfo').textContent = payload.name + ' created. Continue planting, or Finish to edit it.';
        }
    }

    function na_receiveState(payload) {
        var changedContext = naState.context !== payload.context;
        var external = payload.revision == null;
        if (changedContext) {
            clearTimeout(naState.timer);
            naState.pending = naState.pending.filter(function (item) {
                return NA_CONTEXT_SENSITIVE_ACTIONS.indexOf(item.action) === -1;
            });
        }
        naState.ready = true;
        clearTimeout(naState.readyTimer);
        naState.context = payload.context;
        naState.targetId = payload.target_id;
        naState.session = payload.session;
        naState.placing = payload.placing;
        naState.settings = payload.settings;
        naState.treeTypes = payload.tree_types || naState.treeTypes;
        naState.limit = payload.limit;
        if (external || changedContext || payload.revision >= naState.revision) {
            na_applySettingsToInputs(payload);
        }
        na_el('naVegetation_chkLive').checked = payload.live;
        na_el('naVegetation_selectionInfo').textContent = na_selectionCopy(payload);
        na_updateLabels();
        na_drain();
    }

    function na_applySettingsToInputs(payload) {
        var inputs = na_optionInputs();
        var i;
        var el;
        var key;
        na_el('naVegetation_selTreeType').value = naState.settings.tree_type || 'generic';
        for (i = 0; i < inputs.length; i++) {
            el = inputs[i];
            key = na_optionKey(el);
            if (el.type === 'checkbox') {
                el.checked = naState.settings[key];
            } else {
                el.value = naState.settings[key];
            }
            if (payload.limits && payload.limits[key]) {
                el.min = payload.limits[key][0];
                el.max = payload.limits[key][1];
            }
        }
    }

    function na_selectionCopy(payload) {
        if (naState.placing) {
            return naState.settings.preset === 'hedge'
                ? 'Click to add connected runs. Finish creates the whole hedge as one component.'
                : 'Move into the model to plant. Finish returns to editing.';
        }
        if (naState.targetId) {
            return payload.target_name + ' · Settings loaded from the model.';
        }
        return 'No selection needed. Draw a new form, or select Noble vegetation to load its settings.';
    }

    function na_receiveAck(payload) {
        if (!naState.inFlight || payload.id !== naState.inFlight.id) {
            return;
        }
        clearTimeout(naState.ackTimer);
        naState.ackTimer = null;
        naState.inFlight = null;
        na_drain();
    }

    function na_receivePreview(payload) {
        var over;
        naState.mesh = payload;
        over = naState.mesh.requested_quads > naState.limit;
        na_el('naVegetation_meshInfo').classList.toggle('naVegetation__Hint--overBudget', over);
        na_el('naVegetation_meshInfo').textContent = naState.mesh.requested_quads.toLocaleString() + ' foliage quads / ' + (naState.mesh.requested_quads * 2).toLocaleString() + ' triangles' +
            (over
                ? '. Choose a coarser resolution or a smaller form (80,000 quad limit).'
                : naState.mesh.viewport_preview
                    ? ' · 50% resolution drawing preview; creation uses your chosen resolution.'
                    : naState.mesh.preview_coarse
                        ? ' · Simplified preview; creation uses your chosen resolution.'
                        : ' · Preview at your chosen resolution.');
        na_updateLabels();
        na_drawPreview();
    }

    function na_receiveViewport(payload) {
        var text = payload.length != null ? payload.length.toLocaleString() + ' mm · ' : '';
        na_el('naVegetation_viewportState').textContent = text + payload.phase + (payload.quads ? ' · ' + payload.quads.toLocaleString() + ' quads' : '');
        na_el('naVegetation_viewportState').classList.toggle('naVegetation__Hint--overBudget', payload.quads > naState.limit);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Preview
    // -------------------------------------------------------------------------

    function na_drawPreview() {
        var rect = naCanvas.getBoundingClientRect();
        var dpr = window.devicePixelRatio || 1;
        var w = rect.width;
        var h = rect.height;
        var projected;
        var polygons;
        naCanvas.width = Math.round(rect.width * dpr);
        naCanvas.height = Math.round(rect.height * dpr);
        naCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
        naCtx.clearRect(0, 0, w, h);
        if (!naState.mesh) {
            return;
        }
        projected = na_projectPoints(w, h);
        na_drawGroundShadow(w, h, projected.spanX * projected.scale);
        polygons = na_collectPolygons(projected.points, projected.scale);
        polygons.sort(function (a, b) { return a.depth - b.depth; });
        na_fillPolygons(polygons);
        if (na_el('naVegetation_chkWire').checked) {
            na_strokeFrontQuads(projected.points);
        }
    }

    function na_projectPoints(w, h) {
        var all = naState.mesh.points.concat(naState.mesh.trunk.points);
        var cy = Math.cos(naState.yaw);
        var sy = Math.sin(naState.yaw);
        var cp = Math.cos(naState.pitch);
        var sp = Math.sin(naState.pitch);
        var min = [Infinity, Infinity, Infinity];
        var max = [-Infinity, -Infinity, -Infinity];
        var center;
        var projected;
        var x0 = Infinity;
        var x1 = -Infinity;
        var y0 = Infinity;
        var y1 = -Infinity;
        var scale;
        all.forEach(function (p) {
            p.forEach(function (n, i) {
                min[i] = Math.min(min[i], n);
                max[i] = Math.max(max[i], n);
            });
        });
        center = min.map(function (n, i) { return (n + max[i]) / 2; });
        projected = all.map(function (p) {
            var x = p[0] - center[0];
            var y = p[1] - center[1];
            var z = p[2] - center[2];
            var a = cy * x - sy * y;
            var b = sy * x + cy * y;
            return [a, sp * b - cp * z, cp * b + sp * z];
        });
        projected.forEach(function (p) {
            x0 = Math.min(x0, p[0]);
            x1 = Math.max(x1, p[0]);
            y0 = Math.min(y0, p[1]);
            y1 = Math.max(y1, p[1]);
        });
        scale = Math.min((w - 38) / Math.max(x1 - x0, 1), (h - 38) / Math.max(y1 - y0, 1));
        projected.forEach(function (p) {
            p[0] = (p[0] - (x0 + x1) / 2) * scale + w / 2;
            p[1] = (p[1] - (y0 + y1) / 2) * scale + h / 2 - 3;
        });
        return { points: projected, spanX: x1 - x0, scale: scale };
    }

    function na_drawGroundShadow(w, h, radiusX) {
        naCtx.fillStyle = 'rgba(45,56,64,.09)';
        naCtx.beginPath();
        naCtx.ellipse(w / 2, h - 17, Math.min(w * 0.35, radiusX * 0.48), 8, 0, 0, Math.PI * 2);
        naCtx.fill();
    }

    function na_collectPolygons(projected, scale) {
        var polygons = [];
        function add(indices, offset) {
            var a = indices.map(function (i) { return projected[i + offset]; });
            var j;
            var tri;
            var u;
            var v;
            var normal;
            var norm;
            var lit;
            var shade;
            for (j = 1; j < a.length - 1; j++) {
                tri = [a[0], a[j], a[j + 1]];
                u = tri[1].map(function (n, k) { return n - tri[0][k]; });
                v = tri[2].map(function (n, k) { return n - tri[0][k]; });
                u[2] *= scale;
                v[2] *= scale;
                normal = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
                norm = Math.hypot.apply(null, normal) || 1;
                lit = Math.abs((normal[0] * -0.3 + normal[1] * -0.65 + normal[2] * 0.7) / norm);
                shade = Math.round(194 + lit * 59);
                polygons.push({ tri: tri, depth: tri.reduce(function (sum, p) { return sum + p[2]; }, 0) / 3, shade: shade });
            }
        }
        naState.mesh.quads.forEach(function (q) { add(q, 0); });
        naState.mesh.trunk.faces.forEach(function (f) { add(f, naState.mesh.points.length); });
        return polygons;
    }

    function na_fillPolygons(polygons) {
        polygons.forEach(function (item) {
            naCtx.beginPath();
            item.tri.forEach(function (p, i) {
                if (i) {
                    naCtx.lineTo(p[0], p[1]);
                } else {
                    naCtx.moveTo(p[0], p[1]);
                }
            });
            naCtx.closePath();
            naCtx.fillStyle = 'rgb(' + item.shade + ',' + item.shade + ',' + item.shade + ')';
            naCtx.fill();
            naCtx.strokeStyle = naCtx.fillStyle;
            naCtx.lineWidth = 0.45;
            naCtx.stroke();
        });
    }

    function na_strokeFrontQuads(projected) {
        naCtx.strokeStyle = 'rgba(65,106,139,.35)';
        naCtx.lineWidth = 0.65;
        naState.mesh.quads.forEach(function (q) {
            var p = q.map(function (i) { return projected[i]; });
            var cross = (p[1][0] - p[0][0]) * (p[2][1] - p[0][1]) - (p[1][1] - p[0][1]) * (p[2][0] - p[0][0]);
            if (cross > 0) {
                return;
            }
            naCtx.beginPath();
            p.forEach(function (v, i) {
                if (i) {
                    naCtx.lineTo(v[0], v[1]);
                } else {
                    naCtx.moveTo(v[0], v[1]);
                }
            });
            naCtx.closePath();
            naCtx.stroke();
        });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Event Binding and Handshake
    // -------------------------------------------------------------------------

    function na_bindControls() {
        na_optionInputs().forEach(function (el) {
            el.addEventListener('input', function () {
                naState.pending = naState.pending.filter(function (item) { return item.action !== 'options'; });
                naState.revision++;
                na_updateLabels();
                clearTimeout(naState.timer);
                naState.timer = setTimeout(na_sendSettings, NA_SETTINGS_DEBOUNCE_MS);
            });
        });
        document.querySelectorAll('[data-preset]').forEach(function (el) {
            el.addEventListener('click', function () {
                clearTimeout(naState.timer);
                naState.revision++;
                na_command('preset', { preset: el.dataset.preset });
            });
        });
        na_el('naVegetation_selTreeType').addEventListener('change', function () {
            clearTimeout(naState.timer);
            naState.revision++;
            na_command('tree_type', { tree_type: na_el('naVegetation_selTreeType').value });
        });
        na_el('naVegetation_btnVariation').addEventListener('click', function () {
            clearTimeout(naState.timer);
            naState.revision++;
            var o = na_collect(true);
            if (o) { na_command('variation', { settings: o }); }
        });
        na_el('naVegetation_btnStart').addEventListener('click', function () {
            clearTimeout(naState.timer);
            var o = na_collect(true);
            if (o) { na_command('start', { settings: o }); }
        });
        na_el('naVegetation_btnStop').addEventListener('click', function () {
            clearTimeout(naState.timer);
            var o = na_collect(true);
            if (o) { na_command('stop', { settings: o }); }
        });
        na_el('naVegetation_btnNew').addEventListener('click', function () {
            clearTimeout(naState.timer);
            naState.revision++;
            na_command('new');
        });
        na_el('naVegetation_btnLoad').addEventListener('click', function () {
            clearTimeout(naState.timer);
            na_command('load');
        });
        na_el('naVegetation_btnUpdate').addEventListener('click', function () {
            clearTimeout(naState.timer);
            var o = na_collect(true);
            if (o) { na_command('update', { settings: o }); }
        });
        na_el('naVegetation_chkLive').addEventListener('change', function () {
            clearTimeout(naState.timer);
            na_command('live', { enabled: na_el('naVegetation_chkLive').checked });
        });
        na_el('naVegetation_chkWire').addEventListener('change', na_drawPreview);
        na_el('naVegetation_btnResetView').addEventListener('click', function () {
            naState.yaw = -0.7;
            naState.pitch = 0.38;
            na_drawPreview();
        });
        naCanvas.addEventListener('pointerdown', function (e) {
            naState.dragging = [e.clientX, e.clientY];
            naCanvas.setPointerCapture(e.pointerId);
        });
        naCanvas.addEventListener('pointermove', function (e) {
            if (!naState.dragging) { return; }
            naState.yaw += (e.clientX - naState.dragging[0]) * 0.01;
            naState.pitch = Math.max(-0.25, Math.min(1.3, naState.pitch + (e.clientY - naState.dragging[1]) * 0.008));
            naState.dragging = [e.clientX, e.clientY];
            na_drawPreview();
        });
        naCanvas.addEventListener('pointerup', function () { naState.dragging = null; });
        naCanvas.addEventListener('pointercancel', function () { naState.dragging = null; });
        new ResizeObserver(na_drawPreview).observe(naCanvas);
    }

    function na_connect(attempt) {
        attempt = attempt || 0;
        if (naState.ready) {
            return;
        }
        if (window.sketchup && typeof window.sketchup.na_dialog_ready === 'function') {
            try {
                window.sketchup.na_dialog_ready();
            } catch (error) {
                na_setStatus(error.message, 'error');
            }
        }
        if (attempt < NA_CONNECT_ATTEMPTS) {
            naState.readyTimer = setTimeout(function () { na_connect(attempt + 1); }, NA_CONNECT_RETRY_MS);
        } else {
            na_setStatus('SketchUp bridge did not connect. Close this dialog, reload Noble 3D Tools, then reopen it.', 'error');
        }
    }

    window.Na__VegetationSketcher__Receive = na_receive;
    window.addEventListener('error', function (event) {
        na_setStatus('Vegetation UI error: ' + event.message, 'error');
    });
    na_bindControls();
    na_updateLabels();
    na_connect();

    // endregion ---------------------------------------------------------------

}());
