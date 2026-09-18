/* Noble scatter: settings stay in HTML until an explicit paint/regenerate action. */
(function () {
    'use strict';
    const el = id => document.getElementById('naScatter_' + id);
    let state = null, sequence = 0, pending = null, timeout = null, readyTimer = null;
    function status(message, error) { el('status').textContent = message; el('status').className = error ? 'error' : ''; }
    function weights() { const out = {}; document.querySelectorAll('[data-weight]').forEach(input => { out[input.dataset.weight] = Number(input.value); }); return out; }
    function labels() {
        const busy = !state || !!pending, painting = state && state.painting;
        const inputs = Array.from(document.querySelectorAll('[data-weight]'));
        const total = inputs.reduce((sum,input) => sum + Math.max(0,Number(input.value) || 0),0);
        inputs.forEach(input => { input.parentElement.nextElementSibling.textContent = total ? (Math.max(0,Number(input.value) || 0)/total*100).toFixed(1) + '%' : '0%'; });
        document.querySelectorAll('[data-weight],[data-scatter]').forEach(input => { input.disabled = busy || painting; });
        el('capture').disabled = busy || painting;
        el('paint').disabled = busy || painting || !total;
        el('finish').hidden = !painting;
        el('finish').disabled = busy;
        el('regenerate').disabled = busy || painting || !state.target_id || !total;
        el('variation').disabled = el('regenerate').disabled;
        el('mode').textContent = !state ? 'Connecting to SketchUp' : painting ? 'Scatter brush active' : state.target_id ? 'Editing selected forest' : 'Create a forest';
        if (state) el('info').textContent = painting ? 'Drag on the target surface. Plants appear when you release the mouse.' : state.target_id ? state.count + ' plants · saved mix and painted area loaded.' : state.selected + ' items selected in SketchUp. Capture your vegetation sources to begin.';
    }
    function renderSources(sources) {
        el('sources').replaceChildren();
        sources.forEach(source => {
            const row = document.createElement('tr'), name = document.createElement('td'), weight = document.createElement('td'), share = document.createElement('td');
            name.textContent = source.name;
            const input = document.createElement('input');
            input.type = 'number'; input.min = '0'; input.max = '100'; input.step = 'any'; input.value = source.weight;
            input.dataset.weight = source.key; input.setAttribute('aria-label', source.name + ' probability weight');
            input.addEventListener('input', labels); weight.append(input); share.className = 'naScatter__Share';
            row.append(name,weight,share); el('sources').append(row);
        });
        el('mix').hidden = !sources.length; el('empty').hidden = !!sources.length;
    }
    function collect() {
        const options = {};
        for (const input of document.querySelectorAll('[data-scatter],[data-weight]')) {
            if (input.type !== 'checkbox' && (input.value.trim() === '' || !Number.isFinite(Number(input.value)) || !input.checkValidity())) {
                status('Enter a valid ' + (input.dataset.scatter || 'source weight').replace(/_/g,' ') + '.',true); input.reportValidity(); return null;
            }
            if (input.dataset.scatter) options[input.dataset.scatter] = input.type === 'checkbox' ? input.checked : Number(input.value);
        }
        if (options.scale_min > options.scale_max) { status('Minimum scale must not exceed maximum scale.',true); return null; }
        return { options, weights: weights() };
    }
    function command(action) {
        if (!state || pending) return;
        const form = ['paint','regenerate','variation'].includes(action) ? collect() : {};
        if (!form) return;
        const request = { id: ++sequence, session: state.session, action, payload: { context: state.context, target_id: state.target_id, ...form } };
        pending = request.id; labels();
        try {
            window.sketchup.na_scatter_event(JSON.stringify(request));
            timeout = setTimeout(() => { status('SketchUp has not acknowledged this action. Wait for it to finish, then reopen the scatter menu.',true); },120000);
        } catch (error) { pending = null; status(error.message,true); labels(); }
    }
    window.Na__VegetationScatter__Receive = function (event,payload) {
        if (event === 'state') {
            const initial = !state;
            state = payload;
            clearTimeout(readyTimer);
            if (payload.load || initial) {
                document.querySelectorAll('[data-scatter]').forEach(input => { if (input.type === 'checkbox') input.checked = payload.options[input.dataset.scatter]; else input.value = payload.options[input.dataset.scatter]; });
                renderSources(payload.sources);
            }
            labels();
        } else if (event === 'status') status(payload.message,payload.error);
        else if (event === 'ack' && payload.id === pending) { clearTimeout(timeout); pending = null; labels(); }
    };
    ['capture','paint','finish','regenerate','variation'].forEach(action => el(action).addEventListener('click',() => command(action)));
    function connect(attempt = 0) {
        if (state) return;
        if (window.sketchup && typeof window.sketchup.na_scatter_ready === 'function') window.sketchup.na_scatter_ready();
        if (attempt < 20) readyTimer = setTimeout(() => connect(attempt+1),400);
        else status('SketchUp connection unavailable. Reopen the scatter menu.',true);
    }
    labels(); connect();
}());
