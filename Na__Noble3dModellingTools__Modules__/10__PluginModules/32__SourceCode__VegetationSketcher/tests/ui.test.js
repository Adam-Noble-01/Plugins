/* Real Chromium HTML validation and JS bridge contract tests. */
const { chromium } = require(process.argv[2] || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const prefix = 'Na__Noble3dModellingTools__VegetationSketcher__';
const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures.json'), 'utf8'));
let checks = 0;
function check(value, message) { assert.ok(value, message); checks++; }

(async () => {
  const browser = await chromium.launch({ headless: true, ...(process.argv[3] ? { executablePath: process.argv[3] } : {}) });
  try {
    const page = await browser.newPage({ viewport: { width: 510, height: 900 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const html = fs.readFileSync(path.join(root, prefix + 'UiLayout__.html'), 'utf8')
      .replace('{{STYLESHEET_CONTENT}}', fs.readFileSync(path.join(root, prefix + 'Styles__.css'), 'utf8'))
      .replace('{{UI_BRIDGE_SCRIPT}}', '');
    await page.setContent(html);
    await page.evaluate(fixtures => {
      window.__fixtures = fixtures;
      window.__requests = [];
      window.__autoAck = true;
      window.__state = { settings: fixtures.hedge.settings, session: 'test-session', context: 1,
        target_id: null, target_name: null, limit: 80000, placing: false, live: true, revision: null, tree_types: fixtures.tree_types };
      window.__respond = request => {
        const state = window.__state;
        if (request.payload.settings) state.settings = request.payload.settings;
        if (request.action === 'preset') {
          state.settings = window.__fixtures[request.payload.preset].settings;
          state.context++; state.target_id = null;
        }
        if (request.action === 'tree_type') {
          const previous = state.settings;
          state.settings = { ...window.__fixtures[request.payload.tree_type === 'generic' ? 'tree' : request.payload.tree_type].settings,
            seed: previous.seed, smooth: previous.smooth, vary: previous.vary };
        }
        if (request.action === 'start') { state.placing = true; state.context++; state.target_id = null; }
        if (request.action === 'stop') state.placing = false;
        state.revision = request.revision;
        window.NaVegetation.receive('state', state);
        const type = state.settings.preset === 'tree' && state.settings.tree_type !== 'generic' ? state.settings.tree_type : state.settings.preset;
        window.NaVegetation.receive('preview', window.__fixtures[type].mesh);
        window.NaVegetation.receive('ack', { id: request.id, success: true });
      };
      window.sketchup = {
        na_ready() {
          window.NaVegetation.receive('state', window.__state);
          window.NaVegetation.receive('preview', window.__fixtures.hedge.mesh);
        },
        na_event(raw) {
          const request = JSON.parse(raw);
          window.__requests.push(request);
          // HtmlDialog callbacks are asynchronous; this emulates that boundary.
          if (window.__autoAck) setTimeout(() => window.__respond(request), 5);
        }
      };
    }, fixtures);
    await page.addScriptTag({ content: fs.readFileSync(path.join(root, prefix + 'UiBridge__.js'), 'utf8') });
    await page.waitForFunction(() => !document.getElementById('start').disabled);
    check(await page.locator('#mode-label').textContent() === 'Create new vegetation', 'empty selection is create mode');
    check(await page.locator('#edit-controls').isHidden(), 'edit actions hidden without vegetation selection');
    check(await page.locator('#smooth').isChecked(), 'smooth model shading is on by default');
    for (const preset of ['hedge', 'tree', 'shrub']) {
      await page.locator(`[data-preset="${preset}"]`).click();
      await page.waitForFunction(preset => document.querySelector(`[data-preset="${preset}"]`).getAttribute('aria-pressed') === 'true', preset);
      check(await page.evaluate(() => Array.from(document.querySelectorAll('[data-option]')).filter(e => !e.disabled).every(e => e.checkValidity())), preset + ' default controls are valid');
      await page.locator('#start').click();
      await page.waitForFunction(preset => window.__requests.some(r => r.action === 'start' && r.payload.settings.preset === preset), preset);
      const sent = await page.evaluate(() => window.__requests.filter(r => r.action === 'start').at(-1));
      check(sent.payload.settings.length === 3000, preset + ' forwards normal 3000 mm value');
      check(sent.payload.settings.trunk_height === fixtures[preset].settings.trunk_height, preset + ' preserves hidden/preset fields');
      await page.waitForFunction(() => !document.getElementById('stop').hidden);
      check(await page.locator('#start').isDisabled(), 'draw mode visibly active');
      await page.locator('#stop').click();
      await page.waitForFunction(() => document.getElementById('stop').hidden);
    }
    await page.locator('[data-preset="tree"]').click();
    await page.waitForFunction(() => !document.getElementById('tree_type').disabled);
    for (const type of ['douglas_fir', 'english_oak']) {
      await page.locator('#tree_type').selectOption(type);
      await page.waitForFunction(type => window.__state.settings.tree_type === type, type);
      check(await page.locator('#height').inputValue() === String(fixtures[type].settings.height), type + ' loads real-world height');
      check(await page.locator('#resolution').inputValue() === String(fixtures[type].settings.resolution), type + ' loads a usable full-scale mesh spacing');
      check(await page.locator('#start').isEnabled(), type + ' can plant at its starting scale');
      check(await page.evaluate(() => Array.from(document.querySelectorAll('[data-option]')).filter(e => !e.disabled).every(e => e.checkValidity())), type + ' controls valid');
      check((await page.locator('#tree-info').textContent()).includes(fixtures.tree_types[type].botanical), type + ' botanical identity visible');
      check((await page.locator('#tree-scale').textContent()).includes(String(fixtures[type].settings.height / 1000) + ' m high'), type + ' scale displayed in metres');
      await page.evaluate(() => { document.querySelector('main').scrollTop = 0; });
      await page.screenshot({ path: path.join(__dirname, type + '-verified.png') });
      await page.locator('#start').click();
      await page.waitForFunction(() => !document.getElementById('stop').hidden);
      check(await page.evaluate(type => window.__requests.filter(r => r.action === 'start').at(-1).payload.settings.tree_type === type, type), type + ' survives Draw collection');
      await page.locator('#stop').click();
      await page.waitForFunction(() => document.getElementById('stop').hidden);
    }
    await page.locator('#height').fill('24500.5');
    await page.waitForFunction(() => window.__state.settings.height === 24500.5);
    check(await page.evaluate(() => window.__state.settings.tree_type === 'english_oak'), 'custom size retains oak identity');
    await page.evaluate(() => {
      window.__state = { ...window.__state, context: 55, target_id: '800', target_name: 'Saved Douglas fir', settings: window.__fixtures.douglas_fir.settings, revision: null };
      window.NaVegetation.receive('state', window.__state);
    });
    check(await page.locator('#tree_type').inputValue() === 'douglas_fir', 'saved selection restores its species selector');
    await page.locator('#tree_type').selectOption('english_oak');
    await page.waitForFunction(() => window.__state.settings.tree_type === 'english_oak');
    check(await page.evaluate(() => window.__requests.filter(r => r.action === 'tree_type').at(-1).payload.target_id === '800'), 'species edit carries selected entity identity');
    await page.locator('[data-preset="hedge"]').click();
    await page.waitForFunction(() => document.getElementById('trunk_height').disabled);
    check(await page.locator('#tree_type').isDisabled() && await page.locator('#tree-type-section').isHidden(), 'tree types hidden and disabled for hedge');
    await page.evaluate(() => { document.getElementById('trunk_height').value = ''; window.__requests = []; });
    await page.locator('#length').fill('3000.5');
    await page.locator('#start').click();
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'start'));
    check(await page.evaluate(() => window.__requests.find(r => r.action === 'start').payload.settings.length === 3000.5), 'decimal length and invalid hidden field do not block Draw');
    await page.waitForFunction(() => !document.getElementById('stop').hidden);
    await page.locator('#stop').click();
    await page.waitForFunction(() => document.getElementById('stop').hidden);
    await page.evaluate(() => { window.__requests = []; });
    await page.locator('#width').fill('');
    await page.locator('#start').click();
    check(await page.evaluate(() => !window.__requests.some(r => r.action === 'start')), 'empty visible dimension blocks creation');
    check((await page.locator('#status').textContent()).includes('width'), 'invalid visible dimension has a useful message');
    await page.evaluate(() => {
      window.__state = { ...window.__state, settings: window.__fixtures.hedge.settings, context: 100, target_id: '321', target_name: 'Noble Hedge 321', placing: false, revision: null };
      window.NaVegetation.receive('state', window.__state);
      window.__requests = [];
    });
    check(await page.locator('#edit-controls').isVisible(), 'selection activates editing controls');
    await page.locator('#width').fill('1133.5');
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'options'));
    const live = await page.evaluate(() => window.__requests.find(r => r.action === 'options'));
    check(live.payload.target_id === '321' && live.payload.context === 100 && live.payload.settings.width === 1133.5, 'live edit carries exact value and target identity');
    await page.waitForFunction(() => window.__state.settings.width === 1133.5);
    await page.evaluate(() => window.NaVegetation.receive('viewport', { length: 3456.7, phase: 'Click or release to create', quads: 2100 }));
    check((await page.locator('#viewport-state').textContent()).includes('3,456.7'), 'viewport measurements reach the panel');

    // At most one Ruby request in flight. Repeated options are coalesced;
    // selection changes discard queued edits addressed to the old target.
    await page.evaluate(() => { window.__autoAck = false; window.__requests = []; });
    await page.locator('#width').fill('1200');
    await page.waitForFunction(() => window.__requests.length === 1);
    await page.locator('#height').fill('1700');
    await page.waitForTimeout(750);
    check(await page.evaluate(() => window.__requests.length === 1), 'bridge waits for acknowledgement');
    await page.evaluate(() => {
      window.__state = { ...window.__state, context: 101, target_id: '654', settings: window.__fixtures.tree.settings, revision: null };
      window.NaVegetation.receive('state', window.__state);
      window.NaVegetation.receive('ack', { id: window.__requests[0].id, success: false });
    });
    check(await page.evaluate(() => window.__requests.length === 1), 'stale queued edit is discarded when selection changes');
    await page.evaluate(() => {
      window.__autoAck = true; window.__requests = [];
      window.__state = { ...window.__state, context: 201, target_id: '777', settings: window.__fixtures.corner.settings, revision: null };
      window.NaVegetation.receive('state', window.__state);
      window.NaVegetation.receive('preview', window.__fixtures.corner.mesh);
    });
    await page.locator('#smooth').uncheck();
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'options'));
    check(await page.evaluate(() => window.__requests.at(-1).payload.settings.smooth === false), 'shading toggle off reaches model bridge');
    check(await page.evaluate(() => window.__requests.at(-1).payload.settings.path.length === 3), 'shading change preserves drawn corners');
    await page.waitForFunction(() => window.__state.settings.smooth === false);
    await page.locator('#length').fill('9000');
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'options' && r.payload.settings.length === 9000));
    const scaled = await page.evaluate(() => window.__requests.at(-1).payload.settings.path);
    check(scaled[1][0] === 4500 && scaled[2][1] === 4500, 'editing total length scales the saved path without losing its turns');
    await page.waitForFunction(() => window.__state.settings.length === 9000);
    await page.evaluate(() => window.NaVegetation.receive('preview', window.__fixtures.corner.mesh));
    await page.evaluate(() => {
      document.querySelector('main').scrollTop = 0;
      window.NaVegetation.receive('status', { message: 'Selected hedge loaded. Its corner path is preserved.', variant: 'info' });
    });
    await page.screenshot({ path: path.join(__dirname, 'corner-verified.png') });
    check(errors.length === 0, 'no browser runtime errors: ' + errors.join(', '));
    await page.evaluate(() => {
      window.__state = { ...window.__state, context: 102, target_id: null, settings: window.__fixtures.hedge.settings, revision: null };
      window.NaVegetation.receive('state', window.__state);
      window.NaVegetation.receive('preview', window.__fixtures.hedge.mesh);
      window.NaVegetation.receive('status', { message: 'Ready to create vegetation. No selection is needed.', variant: 'info' });
      document.querySelector('main').scrollTop = 0;
    });
    await page.screenshot({ path: path.join(__dirname, 'ui-verified.png') });
    await page.evaluate(() => { window.__requests = []; });
    for (const width of ['810', '820', '830']) {
      await page.locator('#width').fill(width);
      await page.waitForTimeout(220);
    }
    await page.waitForTimeout(200);
    check(await page.evaluate(() => !window.__requests.some(r => r.action === 'options')), 'continuous edits stay local until the quiet period');
    await page.waitForFunction(() => window.__state.settings.width === 830);
    check(await page.evaluate(() => window.__requests.filter(r => r.action === 'options').length === 1), 'slider/input burst sends only its last value');

    await page.evaluate(() => { window.__autoAck = false; window.__requests = []; });
    await page.locator('#width').fill('850');
    await page.waitForFunction(() => window.__requests.length === 1);
    await page.locator('#height').fill('1800');
    await page.waitForTimeout(750);
    await page.locator('#height').fill('1900');
    await page.evaluate(() => window.__respond(window.__requests[0]));
    check(await page.evaluate(() => window.__requests.length === 1), 'new typing removes an older queued rebuild before its acknowledgement');
    await page.waitForFunction(() => window.__requests.length === 2);
    check(await page.evaluate(() => window.__requests[1].payload.settings.height === 1900), 'latest edit is sent after its own quiet period');
    await page.evaluate(() => { window.__autoAck = true; window.__respond(window.__requests[1]); window.__requests = []; });
    await page.locator('#width').fill('900');
    await page.locator('#start').click();
    await page.waitForFunction(() => !document.getElementById('stop').hidden);
    check(await page.evaluate(() => window.__requests.length === 1 && window.__requests[0].action === 'start' && window.__requests[0].payload.settings.width === 900), 'Draw immediately carries the newest value without a redundant options rebuild');
    check(await page.evaluate(() => window.__requests[0].payload.settings.resolution === 100), 'Draw retains selected final resolution');
    await page.locator('#stop').click();
    await page.waitForFunction(() => document.getElementById('stop').hidden);
    check(errors.length === 0, 'no browser errors during debounced editing: ' + errors.join(', '));
    console.log(`PASS: ${checks} Chromium input, creation, selection and bridge checks.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
