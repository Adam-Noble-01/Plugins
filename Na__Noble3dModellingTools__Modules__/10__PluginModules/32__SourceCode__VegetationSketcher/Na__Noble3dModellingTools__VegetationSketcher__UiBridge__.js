/* Inlined HtmlDialog bridge; preview vertices come from the actual Ruby mesher. */
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const SETTINGS_DEBOUNCE_MS = 650;
  let settings = { preset: 'hedge' }, mesh = null, timer = null, yaw = -0.7, pitch = 0.38, dragging = null;
  let limit = 80000, placing = false, ready = false, targetId = null, context = null, session = null;
  let revision = 0, sequence = 0, inFlight = null, pending = [], ackTimer = null, readyTimer = null;
  let validationError = false, treeTypes = {};
  const canvas = $('preview'), ctx = canvas.getContext('2d');
  function status(message, variant = 'info') {
    $('status').textContent = message;
    $('status').className = variant;
  }
  function drain() {
    if (!ready || inFlight || !pending.length) return;
    inFlight = pending.shift();
    try {
      if (!window.sketchup || typeof window.sketchup.na_event !== 'function') throw Error('SketchUp bridge unavailable. Reopen Vegetation Sketcher.');
      window.sketchup.na_event(JSON.stringify(inFlight));
      ackTimer = setTimeout(() => {
        ready = false; pending = [];
        status('SketchUp has not acknowledged the command. Wait for SketchUp, then reopen Vegetation Sketcher before retrying.', 'error');
        labels();
      }, 45000);
    } catch (error) {
      ready = false; inFlight = null; pending = [];
      status(error.message, 'error'); labels();
    }
  }
  function command(action, payload = {}) {
    if (!ready) { status('Waiting for the SketchUp connection. Reopen the dialog if it does not connect.', 'error'); return; }
    const item = { id: ++sequence, session, action, revision, payload: Object.assign({ context, target_id: targetId }, payload) };
    // Explicit actions carry the current form. Avoid an obsolete queued rebuild
    // before Draw/Finish/Update or a switch to a different preset/selection.
    if (['start', 'stop', 'update', 'variation', 'preset', 'tree_type', 'new', 'load'].includes(action)) {
      pending = pending.filter(queued => queued.action !== 'options');
    }
    if (action === 'options' && pending.length && pending[pending.length - 1].action === 'options') pending.pop();
    pending.push(item); drain();
  }
  function collect(interactive = false) {
    const next = Object.assign({}, settings);
    for (const input of document.querySelectorAll('[data-option]')) {
      // Preset-only controls are disabled when hidden, and cannot block Draw.
      if (input.disabled) continue;
      if (input.type !== 'checkbox' && (!input.checkValidity() || input.value.trim() === '' || !Number.isFinite(Number(input.value)))) {
        const name = input.id.replace(/_/g, ' ');
        validationError = true;
        status('Enter a valid ' + name + (input.min && input.max ? ' from ' + input.min + ' to ' + input.max : '') + '.', 'error');
        if (interactive) input.reportValidity();
        return null;
      }
      next[input.id] = input.type === 'checkbox' ? input.checked : Number(input.value);
    }
    if (next.preset === 'hedge' && next.path && next.length !== settings.length) {
      const factor = next.length / settings.length, origin = next.path[0];
      next.path = next.path.map(p => p.map((n, i) => i === 2 ? 0 : origin[i] + (n - origin[i]) * factor));
    }
    if (validationError) { validationError = false; status('Ready.'); }
    return next;
  }
  function sendSettings() {
    clearTimeout(timer);
    const value = collect();
    if (!value) return;
    settings = value;
    command('options', { settings: value });
  }
  function labels() {
    $('soften-value').textContent = $('soften').value + '%';
    $('random-value').textContent = $('random').value + ' mm';
    for (const el of document.querySelectorAll('[data-for]')) {
      el.hidden = el.dataset.for === 'plant' ? settings.preset === 'hedge' : settings.preset !== el.dataset.for;
      el.querySelectorAll('input,select').forEach(input => { input.disabled = el.hidden || !ready; });
    }
    for (const button of document.querySelectorAll('[data-preset]')) {
      button.setAttribute('aria-pressed', String(button.dataset.preset === settings.preset)); button.disabled = !ready;
    }
    $('width-label').textContent = settings.preset === 'tree' ? 'Canopy width' : 'Width';
    const species = settings.preset === 'tree' && settings.tree_type && settings.tree_type !== 'generic';
    const tree = treeTypes[settings.tree_type] || {};
    $('tree-info').textContent = (tree.botanical ? tree.botanical + ' · ' : '') + (tree.description || 'An adjustable rounded whitecard canopy.');
    $('soften-label').textContent = species ? 'Crown rounding' : 'Soften corners';
    const metres = n => (n / 1000).toLocaleString(undefined, { maximumFractionDigits: 3 });
    $('tree-scale').textContent = settings.preset === 'tree' ? 'Model size: ' + metres(settings.height) + ' m high · ' + metres(settings.width) + ' × ' + metres(settings.depth) + ' m canopy' : '';
    $('length-label').textContent = settings.path ? 'Total path length' : 'Preview length';
    $('dimension-hint').textContent = settings.preset === 'hedge' ? (settings.path ? 'Changing total length scales the saved path, keeping its turns. Width stays independent.' : 'Click each corner. Type a length for the next run in SketchUp.') : settings.preset === 'tree' ? (species ? 'Exact overall size, including organic variation. Height includes the trunk; crown base sets the lowest foliage.' : 'Height includes the trunk and crown. The trunk extends into the canopy.') : 'Width and depth set the footprint. Click to plant at the cursor.';
    $('start').textContent = placing ? 'Drawing in SketchUp...' : settings.preset === 'hedge' ? 'Draw hedge in SketchUp' : settings.preset === 'tree' ? 'Plant ' + (species ? tree.name || 'tree' : 'tree') + ' in SketchUp' : 'Plant shrub in SketchUp';
    $('help').textContent = settings.preset === 'hedge' ? 'Click corners; Enter, double-click or Finish builds the hedge. Right/Left: red/green. Down: parallel. Up: unlock. Backspace: undo point. Esc: cancel.' : 'Click in the model to plant. R: new variation. Esc: finish.';
    $('stop').hidden = !placing;
    $('stop').textContent = settings.preset === 'hedge' ? 'Finish hedge' : 'Finish';
    $('viewport-state').hidden = !placing;
    const over = mesh && mesh.requested_quads > limit;
    $('start').disabled = !ready || placing || (over && settings.preset !== 'hedge');
    $('new').disabled = !ready;
    $('variation').disabled = !ready;
    $('edit-controls').hidden = !targetId || placing;
    $('update').disabled = !ready || !targetId || placing || over;
    $('load').disabled = !ready || !targetId || placing;
    $('live').disabled = !ready || !targetId || placing;
    $('mode-label').textContent = !ready ? 'Connecting to SketchUp' : placing ? 'Draw mode active' : targetId ? 'Editing selected vegetation' : 'Create new vegetation';
  }
  function receive(event, payload) {
    if (event === 'state') {
      const changedContext = context !== payload.context;
      const external = payload.revision == null;
      if (changedContext) {
        clearTimeout(timer);
        pending = pending.filter(item => !['options', 'variation', 'update', 'live', 'tree_type'].includes(item.action));
      }
      ready = true; clearTimeout(readyTimer);
      context = payload.context; targetId = payload.target_id; session = payload.session; placing = payload.placing;
      settings = payload.settings;
      treeTypes = payload.tree_types || treeTypes;
      limit = payload.limit;
      if (external || changedContext || payload.revision >= revision) {
        $('tree_type').value = settings.tree_type || 'generic';
        for (const el of document.querySelectorAll('[data-option]')) {
          if (el.type === 'checkbox') el.checked = settings[el.id];
          else el.value = settings[el.id];
          if (payload.limits && payload.limits[el.id]) {
            el.min = payload.limits[el.id][0]; el.max = payload.limits[el.id][1];
          }
        }
      }
      $('live').checked = payload.live;
      $('selection-info').textContent = placing ? (settings.preset === 'hedge' ? 'Click to add connected runs. Finish creates the whole hedge as one component.' : 'Move into the model to plant. Finish returns to editing.') : targetId ? payload.target_name + ' · Settings loaded from the model.' : 'No selection needed. Draw a new form, or select Noble vegetation to load its settings.';
      labels();
      drain();
    } else if (event === 'ack') {
      if (!inFlight || payload.id !== inFlight.id) return;
      clearTimeout(ackTimer); ackTimer = null; inFlight = null;
      drain();
    } else if (event === 'preview') {
      mesh = payload;
      const over = mesh.requested_quads > limit;
      $('mesh-info').classList.toggle('over-budget', over);
      $('mesh-info').textContent = mesh.requested_quads.toLocaleString() + ' foliage quads / ' + (mesh.requested_quads * 2).toLocaleString() + ' triangles' + (over ? '. Choose a coarser resolution or a smaller form (80,000 quad limit).' : mesh.viewport_preview ? ' · 50% resolution drawing preview; creation uses your chosen resolution.' : mesh.preview_coarse ? ' · Simplified preview; creation uses your chosen resolution.' : ' · Preview at your chosen resolution.');
      // A long sample can exceed the limit while a shorter drawn hedge fits.
      labels();
      draw();
    } else if (event === 'status') {
      status(payload.message, payload.variant);
    } else if (event === 'viewport') {
      const text = payload.length != null ? payload.length.toLocaleString() + ' mm · ' : '';
      $('viewport-state').textContent = text + payload.phase + (payload.quads ? ' · ' + payload.quads.toLocaleString() + ' quads' : '');
      $('viewport-state').classList.toggle('over-budget', payload.quads > limit);
    } else if (event === 'created') {
      $('selection-info').textContent = payload.name + ' created. Continue planting, or Finish to edit it.';
    }
  }
  function draw() {
    const rect = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(rect.width * dpr); canvas.height = Math.round(rect.height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const w = rect.width, h = rect.height;
    ctx.clearRect(0, 0, w, h);
    if (!mesh) return;
    const all = mesh.points.concat(mesh.trunk.points), cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
    const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
    all.forEach(p => p.forEach((n, i) => { min[i] = Math.min(min[i], n); max[i] = Math.max(max[i], n); }));
    const center = min.map((n, i) => (n + max[i]) / 2);
    function rotate(p) {
      const x = p[0] - center[0], y = p[1] - center[1], z = p[2] - center[2];
      const a = cy * x - sy * y, b = sy * x + cy * y;
      return [a, sp * b - cp * z, cp * b + sp * z];
    }
    const projected = all.map(rotate);
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    projected.forEach(p => { x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]); y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); });
    const scale = Math.min((w - 38) / Math.max(x1 - x0, 1), (h - 38) / Math.max(y1 - y0, 1));
    projected.forEach(p => { p[0] = (p[0] - (x0 + x1) / 2) * scale + w / 2; p[1] = (p[1] - (y0 + y1) / 2) * scale + h / 2 - 3; });
    ctx.fillStyle = 'rgba(45,56,64,.09)'; ctx.beginPath(); ctx.ellipse(w / 2, h - 17, Math.min(w * .35, (x1 - x0) * scale * .48), 8, 0, 0, Math.PI * 2); ctx.fill();
    const polygons = [];
    function add(indices, offset) {
      const a = indices.map(i => projected[i + offset]);
      for (let j = 1; j < a.length - 1; j++) {
        const tri = [a[0], a[j], a[j + 1]], u = tri[1].map((n, k) => n - tri[0][k]), v = tri[2].map((n, k) => n - tri[0][k]);
        // Shade using camera-space geometry before the unequal depth scaling.
        u[2] *= scale; v[2] *= scale;
        const normal = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
        const norm = Math.hypot(...normal) || 1;
        const lit = Math.abs((normal[0]*-.3 + normal[1]*-.65 + normal[2]*.7) / norm);
        const shade = Math.round(194 + lit * 59);
        polygons.push({ tri, depth: tri.reduce((sum,p) => sum+p[2],0)/3, shade });
      }
    }
    mesh.quads.forEach(q => add(q, 0));
    mesh.trunk.faces.forEach(f => add(f, mesh.points.length));
    polygons.sort((a, b) => a.depth - b.depth);
    polygons.forEach(({tri,shade}) => {
      ctx.beginPath(); tri.forEach((p,i) => i ? ctx.lineTo(p[0],p[1]) : ctx.moveTo(p[0],p[1])); ctx.closePath();
      ctx.fillStyle = `rgb(${shade},${shade},${shade})`; ctx.fill();
      ctx.strokeStyle = ctx.fillStyle; ctx.lineWidth = .45; ctx.stroke();
    });
    if ($('wire').checked) {
      // Only front-facing quads, so rear lines do not show through the canopy.
      ctx.strokeStyle = 'rgba(65,106,139,.35)'; ctx.lineWidth = .65;
      mesh.quads.forEach(q => {
        const p = q.map(i => projected[i]);
        const cross = (p[1][0]-p[0][0])*(p[2][1]-p[0][1])-(p[1][1]-p[0][1])*(p[2][0]-p[0][0]);
        if (cross > 0) return;
        ctx.beginPath(); p.forEach((v,i) => i ? ctx.lineTo(v[0],v[1]) : ctx.moveTo(v[0],v[1])); ctx.closePath(); ctx.stroke();
      });
    }
  }
  document.querySelectorAll('[data-option]').forEach(el => el.addEventListener('input', () => {
    // Restart the quiet period on every input, including while Ruby is busy.
    // Never let an older queued slider value escape during a newer drag.
    pending = pending.filter(item => item.action !== 'options');
    revision++; labels(); clearTimeout(timer); timer = setTimeout(sendSettings, SETTINGS_DEBOUNCE_MS);
  }));
  document.querySelectorAll('[data-preset]').forEach(el => el.addEventListener('click', () => { clearTimeout(timer); revision++; command('preset', { preset: el.dataset.preset }); }));
  $('tree_type').addEventListener('change', () => { clearTimeout(timer); revision++; command('tree_type', { tree_type: $('tree_type').value }); });
  $('variation').addEventListener('click', () => { clearTimeout(timer); revision++; const o = collect(true); if (o) command('variation', { settings: o }); });
  $('start').addEventListener('click', () => { clearTimeout(timer); const o = collect(true); if (o) command('start', { settings: o }); });
  $('stop').addEventListener('click', () => { clearTimeout(timer); const o = collect(true); if (o) command('stop', { settings: o }); });
  $('new').addEventListener('click', () => { clearTimeout(timer); revision++; command('new'); });
  $('load').addEventListener('click', () => { clearTimeout(timer); command('load'); });
  $('update').addEventListener('click', () => { clearTimeout(timer); const o = collect(true); if (o) command('update', { settings: o }); });
  $('live').addEventListener('change', () => { clearTimeout(timer); command('live', { enabled: $('live').checked }); });
  $('wire').addEventListener('change', draw);
  $('reset-view').addEventListener('click', () => { yaw = -.7; pitch = .38; draw(); });
  canvas.addEventListener('pointerdown', e => { dragging = [e.clientX, e.clientY]; canvas.setPointerCapture(e.pointerId); });
  canvas.addEventListener('pointermove', e => { if (!dragging) return; yaw += (e.clientX - dragging[0]) * .01; pitch = Math.max(-.25, Math.min(1.3, pitch + (e.clientY - dragging[1]) * .008)); dragging = [e.clientX, e.clientY]; draw(); });
  canvas.addEventListener('pointerup', () => { dragging = null; });
  canvas.addEventListener('pointercancel', () => { dragging = null; });
  new ResizeObserver(draw).observe(canvas);
  window.NaVegetation = { receive };
  window.addEventListener('error', event => status('Vegetation UI error: ' + event.message, 'error'));
  function connect(attempt = 0) {
    if (ready) return;
    if (window.sketchup && typeof window.sketchup.na_ready === 'function') {
      try { window.sketchup.na_ready(); } catch (error) { status(error.message, 'error'); }
    }
    if (attempt < 20) readyTimer = setTimeout(() => connect(attempt + 1), 400);
    else status('SketchUp bridge did not connect. Close this dialog, reload Noble 3D Tools, then reopen it.', 'error');
  }
  labels(); connect();
}());
