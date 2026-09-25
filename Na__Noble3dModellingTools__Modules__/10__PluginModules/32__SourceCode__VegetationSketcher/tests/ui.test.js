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
      .replaceAll('{{STYLESHEET_CONTENT}}', () => fs.readFileSync(path.join(root, prefix + 'Styles__.css'), 'utf8'))
      .replaceAll('{{UI_BRIDGE_SCRIPT}}', '');
    await page.setContent(html);
    await page.evaluate(fixtures => {
      window.__fixtures = fixtures;
      window.__requests = [];
      window.__autoAck = true;
      window.__state = { settings: fixtures.hedge.settings, session: 'test-session', context: 1,
        target_id: null, target_name: null, limit: 80000, placing: false, live: true, revision: null, tree_types: fixtures.tree_types, shrub_types: fixtures.shrub_types };
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
        if (request.action === 'shrub_type') {
          const previous = state.settings;
          state.settings = { ...window.__fixtures[request.payload.shrub_type === 'generic' ? 'shrub' : request.payload.shrub_type].settings,
            seed: previous.seed, smooth: previous.smooth, vary: previous.vary };
        }
        if (request.action === 'start') { state.placing = true; state.context++; state.target_id = null; }
        if (request.action === 'stop') state.placing = false;
        state.revision = request.revision;
        Na__VegetationSketcher__Receive('state', state);
        const type = state.settings.preset === 'tree' && state.settings.tree_type !== 'generic' ? state.settings.tree_type
          : state.settings.preset === 'shrub' && state.settings.shrub_type !== 'generic' ? state.settings.shrub_type : state.settings.preset;
        Na__VegetationSketcher__Receive('preview', window.__fixtures[type].mesh);
        Na__VegetationSketcher__Receive('ack', { id: request.id, success: true });
      };
      window.sketchup = {
        na_dialog_ready() {
          Na__VegetationSketcher__Receive('state', window.__state);
          Na__VegetationSketcher__Receive('preview', window.__fixtures.hedge.mesh);
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
    await page.waitForFunction(() => !document.getElementById('naVegetation_btnStart').disabled);
    check(await page.locator('#naVegetation_modeLabel').textContent() === 'Create new vegetation', 'empty selection is create mode');
    check(await page.locator('#naVegetation_editControls').isHidden(), 'edit actions hidden without vegetation selection');
    check(await page.locator('#naVegetation_chkSmooth').isChecked(), 'smooth model shading is on by default');
    for (const preset of ['hedge', 'tree', 'shrub']) {
      await page.locator(`[data-preset="${preset}"]`).click();
      await page.waitForFunction(preset => document.querySelector(`[data-preset="${preset}"]`).getAttribute('aria-pressed') === 'true', preset);
      check(await page.evaluate(() => Array.from(document.querySelectorAll('[data-option]')).filter(e => !e.disabled).every(e => e.checkValidity())), preset + ' default controls are valid');
      await page.locator('#naVegetation_btnStart').click();
      await page.waitForFunction(preset => window.__requests.some(r => r.action === 'start' && r.payload.settings.preset === preset), preset);
      const sent = await page.evaluate(() => window.__requests.filter(r => r.action === 'start').at(-1));
      check(sent.payload.settings.length === 3000, preset + ' forwards normal 3000 mm value');
      check(sent.payload.settings.trunk_height === fixtures[preset].settings.trunk_height, preset + ' preserves hidden/preset fields');
      await page.waitForFunction(() => !document.getElementById('naVegetation_btnStop').hidden);
      check(await page.locator('#naVegetation_btnStart').isDisabled(), 'draw mode visibly active');
      await page.locator('#naVegetation_btnStop').click();
      await page.waitForFunction(() => document.getElementById('naVegetation_btnStop').hidden);
    }
    await page.locator('[data-preset="tree"]').click();
    await page.waitForFunction(() => !document.getElementById('naVegetation_selTreeType').disabled);
    for (const type of ['douglas_fir', 'english_oak']) {
      await page.locator('#naVegetation_selTreeType').selectOption(type);
      await page.waitForFunction(type => window.__state.settings.tree_type === type, type);
      check(await page.locator('#naVegetation_inpHeight').inputValue() === String(fixtures[type].settings.height), type + ' loads real-world height');
      check(await page.locator('#naVegetation_selResolution').inputValue() === String(fixtures[type].settings.resolution), type + ' loads a usable full-scale mesh spacing');
      check(await page.locator('#naVegetation_btnStart').isEnabled(), type + ' can plant at its starting scale');
      check(await page.evaluate(() => Array.from(document.querySelectorAll('[data-option]')).filter(e => !e.disabled).every(e => e.checkValidity())), type + ' controls valid');
      check((await page.locator('#naVegetation_treeInfo').textContent()).includes(fixtures.tree_types[type].botanical), type + ' botanical identity visible');
      check((await page.locator('#naVegetation_treeScale').textContent()).includes(String(fixtures[type].settings.height / 1000) + ' m high'), type + ' scale displayed in metres');
      await page.evaluate(() => { document.querySelector('.naVegetation__Body').scrollTop = 0; });
      await page.screenshot({ path: path.join(__dirname, type + '-verified.png') });
      await page.locator('#naVegetation_btnStart').click();
      await page.waitForFunction(() => !document.getElementById('naVegetation_btnStop').hidden);
      check(await page.evaluate(type => window.__requests.filter(r => r.action === 'start').at(-1).payload.settings.tree_type === type, type), type + ' survives Draw collection');
      await page.locator('#naVegetation_btnStop').click();
      await page.waitForFunction(() => document.getElementById('naVegetation_btnStop').hidden);
    }
    await page.locator('#naVegetation_inpHeight').fill('24500.5');
    await page.waitForFunction(() => window.__state.settings.height === 24500.5);
    check(await page.evaluate(() => window.__state.settings.tree_type === 'english_oak'), 'custom size retains oak identity');
    await page.evaluate(() => {
      window.__state = { ...window.__state, context: 55, target_id: '800', target_name: 'Saved Douglas fir', settings: window.__fixtures.douglas_fir.settings, revision: null };
      Na__VegetationSketcher__Receive('state', window.__state);
    });
    check(await page.locator('#naVegetation_selTreeType').inputValue() === 'douglas_fir', 'saved selection restores its species selector');
    await page.locator('#naVegetation_selTreeType').selectOption('english_oak');
    await page.waitForFunction(() => window.__state.settings.tree_type === 'english_oak');
    check(await page.evaluate(() => window.__requests.filter(r => r.action === 'tree_type').at(-1).payload.target_id === '800'), 'species edit carries selected entity identity');
    await page.locator('[data-preset="hedge"]').click();
    await page.waitForFunction(() => document.getElementById('naVegetation_inpTrunkHeight').disabled);
    check(await page.locator('#naVegetation_selTreeType').isDisabled() && await page.locator('#naVegetation_treeTypeSection').isHidden(), 'tree types hidden and disabled for hedge');
    await page.evaluate(() => { document.getElementById('naVegetation_inpTrunkHeight').value = ''; window.__requests = []; });
    await page.locator('#naVegetation_inpLength').fill('3000.5');
    await page.locator('#naVegetation_btnStart').click();
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'start'));
    check(await page.evaluate(() => window.__requests.find(r => r.action === 'start').payload.settings.length === 3000.5), 'decimal length and invalid hidden field do not block Draw');
    await page.waitForFunction(() => !document.getElementById('naVegetation_btnStop').hidden);
    await page.locator('#naVegetation_btnStop').click();
    await page.waitForFunction(() => document.getElementById('naVegetation_btnStop').hidden);
    await page.evaluate(() => { window.__requests = []; });
    await page.locator('#naVegetation_inpWidth').fill('');
    await page.locator('#naVegetation_btnStart').click();
    check(await page.evaluate(() => !window.__requests.some(r => r.action === 'start')), 'empty visible dimension blocks creation');
    check((await page.locator('#naVegetation_status').textContent()).includes('width'), 'invalid visible dimension has a useful message');
    await page.evaluate(() => {
      window.__state = { ...window.__state, settings: window.__fixtures.hedge.settings, context: 100, target_id: '321', target_name: 'Noble Hedge 321', placing: false, revision: null };
      Na__VegetationSketcher__Receive('state', window.__state);
      window.__requests = [];
    });
    check(await page.locator('#naVegetation_editControls').isVisible(), 'selection activates editing controls');
    await page.locator('#naVegetation_inpWidth').fill('1133.5');
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'options'));
    const live = await page.evaluate(() => window.__requests.find(r => r.action === 'options'));
    check(live.payload.target_id === '321' && live.payload.context === 100 && live.payload.settings.width === 1133.5, 'live edit carries exact value and target identity');
    await page.waitForFunction(() => window.__state.settings.width === 1133.5);
    await page.evaluate(() => Na__VegetationSketcher__Receive('viewport', { length: 3456.7, phase: 'Click or release to create', quads: 2100 }));
    check((await page.locator('#naVegetation_viewportState').textContent()).includes('3,456.7'), 'viewport measurements reach the panel');

    // At most one Ruby request in flight. Repeated options are coalesced;
    // selection changes discard queued edits addressed to the old target.
    await page.evaluate(() => { window.__autoAck = false; window.__requests = []; });
    await page.locator('#naVegetation_inpWidth').fill('1200');
    await page.waitForFunction(() => window.__requests.length === 1);
    await page.locator('#naVegetation_inpHeight').fill('1700');
    await page.waitForTimeout(750);
    check(await page.evaluate(() => window.__requests.length === 1), 'bridge waits for acknowledgement');
    await page.evaluate(() => {
      window.__state = { ...window.__state, context: 101, target_id: '654', settings: window.__fixtures.tree.settings, revision: null };
      Na__VegetationSketcher__Receive('state', window.__state);
      Na__VegetationSketcher__Receive('ack', { id: window.__requests[0].id, success: false });
    });
    check(await page.evaluate(() => window.__requests.length === 1), 'stale queued edit is discarded when selection changes');
    await page.evaluate(() => {
      window.__autoAck = true; window.__requests = [];
      window.__state = { ...window.__state, context: 201, target_id: '777', settings: window.__fixtures.corner.settings, revision: null };
      Na__VegetationSketcher__Receive('state', window.__state);
      Na__VegetationSketcher__Receive('preview', window.__fixtures.corner.mesh);
    });
    await page.locator('#naVegetation_chkSmooth').uncheck();
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'options'));
    check(await page.evaluate(() => window.__requests.at(-1).payload.settings.smooth === false), 'shading toggle off reaches model bridge');
    check(await page.evaluate(() => window.__requests.at(-1).payload.settings.path.length === 3), 'shading change preserves drawn corners');
    await page.waitForFunction(() => window.__state.settings.smooth === false);
    await page.locator('#naVegetation_inpLength').fill('9000');
    await page.waitForFunction(() => window.__requests.some(r => r.action === 'options' && r.payload.settings.length === 9000));
    const scaled = await page.evaluate(() => window.__requests.at(-1).payload.settings.path);
    check(scaled[1][0] === 4500 && scaled[2][1] === 4500, 'editing total length scales the saved path without losing its turns');
    await page.waitForFunction(() => window.__state.settings.length === 9000);
    await page.evaluate(() => Na__VegetationSketcher__Receive('preview', window.__fixtures.corner.mesh));
    await page.evaluate(() => {
      document.querySelector('.naVegetation__Body').scrollTop = 0;
      Na__VegetationSketcher__Receive('status', { message: 'Selected hedge loaded. Its corner path is preserved.', variant: 'info' });
    });
    await page.screenshot({ path: path.join(__dirname, 'corner-verified.png') });
    check(errors.length === 0, 'no browser runtime errors: ' + errors.join(', '));
    await page.evaluate(() => {
      window.__state = { ...window.__state, context: 102, target_id: null, settings: window.__fixtures.hedge.settings, revision: null };
      Na__VegetationSketcher__Receive('state', window.__state);
      Na__VegetationSketcher__Receive('preview', window.__fixtures.hedge.mesh);
      Na__VegetationSketcher__Receive('status', { message: 'Ready to create vegetation. No selection is needed.', variant: 'info' });
      document.querySelector('.naVegetation__Body').scrollTop = 0;
    });
    await page.screenshot({ path: path.join(__dirname, 'ui-verified.png') });
    await page.evaluate(() => { window.__requests = []; });
    for (const width of ['810', '820', '830']) {
      await page.locator('#naVegetation_inpWidth').fill(width);
      await page.waitForTimeout(220);
    }
    await page.waitForTimeout(200);
    check(await page.evaluate(() => !window.__requests.some(r => r.action === 'options')), 'continuous edits stay local until the quiet period');
    await page.waitForFunction(() => window.__state.settings.width === 830);
    check(await page.evaluate(() => window.__requests.filter(r => r.action === 'options').length === 1), 'slider/input burst sends only its last value');

    await page.evaluate(() => { window.__autoAck = false; window.__requests = []; });
    await page.locator('#naVegetation_inpWidth').fill('850');
    await page.waitForFunction(() => window.__requests.length === 1);
    await page.locator('#naVegetation_inpHeight').fill('1800');
    await page.waitForTimeout(750);
    await page.locator('#naVegetation_inpHeight').fill('1900');
    await page.evaluate(() => window.__respond(window.__requests[0]));
    check(await page.evaluate(() => window.__requests.length === 1), 'new typing removes an older queued rebuild before its acknowledgement');
    await page.waitForFunction(() => window.__requests.length === 2);
    check(await page.evaluate(() => window.__requests[1].payload.settings.height === 1900), 'latest edit is sent after its own quiet period');
    await page.evaluate(() => { window.__autoAck = true; window.__respond(window.__requests[1]); window.__requests = []; });
    await page.locator('#naVegetation_inpWidth').fill('900');
    await page.locator('#naVegetation_btnStart').click();
    await page.waitForFunction(() => !document.getElementById('naVegetation_btnStop').hidden);
    check(await page.evaluate(() => window.__requests.length === 1 && window.__requests[0].action === 'start' && window.__requests[0].payload.settings.width === 900), 'Draw immediately carries the newest value without a redundant options rebuild');
    check(await page.evaluate(() => window.__requests[0].payload.settings.resolution === 100), 'Draw retains selected final resolution');
    await page.locator('#naVegetation_btnStop').click();
    await page.waitForFunction(() => document.getElementById('naVegetation_btnStop').hidden);
    check(errors.length === 0, 'no browser errors during debounced editing: ' + errors.join(', '));
    await page.locator('[data-preset="shrub"]').click();
    await page.waitForFunction(() => !document.getElementById('naVegetation_selShrubType').disabled);
    const cards = [];
    for (const type of ['spreading','cushion','rounded','loose','upright','arching']) {
      await page.locator('#naVegetation_selShrubType').selectOption(type);
      await page.waitForFunction(type => window.__state.settings.shrub_type === type, type);
      check(await page.locator('#naVegetation_inpHeight').inputValue() === String(fixtures[type].settings.height), type + ' loads height');
      check(await page.evaluate(() => Array.from(document.querySelectorAll('[data-option]')).filter(e => !e.disabled).every(e => e.checkValidity())), type + ' inputs valid');
      check((await page.locator('#naVegetation_shrubInfo').textContent()).length > 20, type + ' describes planting role');
      const preview = await page.locator('#naVegetation_canvasPreview').evaluate(c => c.toDataURL());
      await page.evaluate(type => Na__VegetationSketcher__Receive('preview', window.__fixtures[type].variant), type);
      const variant = await page.locator('#naVegetation_canvasPreview').evaluate(c => c.toDataURL());
      cards.push({ name: fixtures.shrub_types[type].name, height: fixtures[type].settings.height, preview, variant });
    }
    await page.locator('#naVegetation_btnStart').click();
    await page.waitForFunction(() => window.__state.placing);
    check(await page.evaluate(() => window.__requests.at(-1).payload.settings.shrub_type === 'arching'), 'plant carries chosen shrub type');
    await page.locator('#naVegetation_btnStop').click();
    await page.waitForFunction(() => !window.__state.placing);
    await page.locator('[data-preset="tree"]').click();
    await page.waitForFunction(() => window.__state.settings.preset === 'tree');
    check(await page.locator('#naVegetation_selShrubType').isDisabled(), 'shrub selector hidden and disabled outside shrub preset');
    check(errors.length === 0, 'no errors in shrub controls');
    const sheet = await browser.newPage({ viewport: { width: 1380, height: 920 } });
    await sheet.setContent('<html><head><style>body{font:15px Arial;background:#edf0f3;margin:24px;color:#253044}h1{font-size:24px}main{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}article{background:white;padding:16px;border:1px solid #d8dfe6;border-radius:6px}h2{font-size:17px;margin:0 0 5px}p{margin:0;color:#687789}img{width:50%;margin-top:10px}</style></head><body><h1>Noble whitecard planting-bed shrubs</h1><p>Actual mesh previews · two seeds per form · previews fitted individually</p><main></main></body></html>');
    await sheet.evaluate(cards => {
      const main=document.querySelector('main');
      cards.forEach(card => { const article=document.createElement('article'); const h=document.createElement('h2'); h.textContent=card.name; const p=document.createElement('p'); p.textContent=card.height+' mm high'; article.append(h,p); [card.preview,card.variant].forEach(src=>{const img=document.createElement('img');img.src=src;article.append(img);});main.append(article); });
    },cards);
    await sheet.screenshot({path:path.join(__dirname,'shrubs-verified.png'),fullPage:true});
    await sheet.close();
    await page.locator('[data-preset="shrub"]').click();
    await page.waitForFunction(() => window.__state.settings.preset === 'shrub');
    const plantCards=[];
    for (const type of ['daisy_clump','flower_spikes','umbel_clump','tuft_grass','fountain_grass','plume_grass']) {
      await page.locator('#naVegetation_selShrubType').selectOption(type);
      await page.waitForFunction(type => window.__state.settings.shrub_type === type,type);
      check(await page.locator('#naVegetation_selPlantDetail').isVisible() && !await page.locator('#naVegetation_selPlantDetail').isDisabled(),type+' uses plant detail control');
      check(await page.locator('#naVegetation_gridResolution').isHidden(),type+' hides canopy grid control');
      check(await page.locator('#naVegetation_inpHeight').inputValue()===String(fixtures[type].settings.height),type+' loads correct height');
      const preview=await page.locator('#naVegetation_canvasPreview').evaluate(c=>c.toDataURL());
      plantCards.push({name:fixtures.shrub_types[type].name,height:fixtures[type].settings.height,quads:fixtures[type].mesh.requested_quads,preview});
    }
    await page.evaluate(()=>{window.__requests=[];});
    await page.locator('#naVegetation_selPlantDetail').selectOption('low');
    await page.waitForTimeout(300);
    check(await page.evaluate(()=>window.__requests.length===0),'plant detail waits for the quiet period');
    await page.waitForFunction(()=>window.__requests.some(r=>r.action==='options'&&r.payload.settings.plant_detail==='low'));
    check(await page.evaluate(()=>window.__state.settings.plant_detail==='low'),'detail is serialized as a supported string');
    await page.locator('#naVegetation_selPlantDetail').selectOption('high');
    await page.locator('#naVegetation_btnStart').click();
    await page.waitForFunction(()=>window.__state.placing);
    check(await page.evaluate(()=>window.__requests.at(-1).payload.settings.plant_detail==='high'),'plant command carries the newest detail immediately');
    await page.locator('#naVegetation_btnStop').click();
    await page.waitForFunction(()=>!window.__state.placing);
    await page.locator('#naVegetation_selShrubType').selectOption('rounded');
    await page.waitForFunction(()=>window.__state.settings.shrub_type==='rounded');
    check(await page.locator('#naVegetation_plantDetail').isHidden() && await page.locator('#naVegetation_selResolution').isVisible(),'returning to shrub restores quad resolution');
    // Placement variation: its own debounced command, validated before planting.
    await page.evaluate(()=>Na__VegetationSketcher__Receive('state',{...window.__state,placement:{enabled:true,scale_min:90,scale_max:110,height_min:95,height_max:105,rotation:360,lean:0},
      placement_limits:{scale_min:[10,500],scale_max:[10,500],height_min:[25,400],height_max:[25,400],rotation:[0,360],lean:[0,30]}}));
    check(await page.locator('#naVegetation_placementSection').isVisible() && await page.locator('#naVegetation_inpScaleMin').inputValue()==='90','placement ranges shown for plants and loaded from SketchUp');
    await page.evaluate(()=>{window.__requests=[];});
    await page.locator('#naVegetation_inpScaleMin').fill('70');
    await page.locator('#naVegetation_inpLean').fill('6');
    await page.waitForTimeout(300);
    check(await page.evaluate(()=>window.__requests.length===0),'placement edits wait for the quiet period');
    await page.waitForFunction(()=>window.__requests.some(r=>r.action==='placement'));
    const placed=await page.evaluate(()=>window.__requests.filter(r=>r.action==='placement'));
    check(placed.length===1&&placed[0].payload.placement.scale_min===70&&placed[0].payload.placement.lean===6&&placed[0].payload.placement.scale_max===110,'one placement command carries every range');
    check(await page.evaluate(()=>!window.__requests.some(r=>r.action==='options')),'placement edits never send form options or touch selected vegetation');
    await page.evaluate(()=>{window.__requests=[];});
    await page.locator('#naVegetation_inpScaleMin').fill('150');
    await page.locator('#naVegetation_btnStart').click();
    check(await page.evaluate(()=>!window.__requests.some(r=>r.action==='start')),'an inverted size range blocks planting');
    check((await page.locator('#naVegetation_status').textContent()).includes('Minimum size is above maximum size'),'the inverted range message names the fix');
    await page.locator('#naVegetation_inpScaleMin').fill('80');
    await page.locator('#naVegetation_btnStart').click();
    await page.waitForFunction(()=>window.__state.placing);
    const startPlacement=await page.evaluate(()=>window.__requests.find(r=>r.action==='start').payload.placement);
    check(startPlacement&&startPlacement.scale_min===80&&startPlacement.enabled===true,'Plant carries the newest ranges immediately');
    await page.locator('#naVegetation_btnStop').click();
    await page.waitForFunction(()=>!window.__state.placing);
    await page.locator('#naVegetation_chkPlacement').uncheck();
    check(await page.locator('#naVegetation_inpScaleMin').isDisabled()&&await page.locator('#naVegetation_inpLean').isDisabled(),'turning variation off greys the ranges');
    await page.waitForFunction(()=>window.__requests.some(r=>r.action==='placement'&&r.payload.placement.enabled===false));
    await page.locator('#naVegetation_chkPlacement').check();
    await page.evaluate(()=>{const body=document.querySelector('.naVegetation__Body');body.scrollTop=document.getElementById('naVegetation_placementSection').offsetTop-body.offsetTop-12;});
    await page.screenshot({path:path.join(__dirname,'placement-verified.png')});
    await page.locator('[data-preset="hedge"]').click();
    await page.waitForFunction(()=>document.querySelector('[data-preset="hedge"]').getAttribute('aria-pressed')==='true');
    check(await page.locator('#naVegetation_placementSection').isHidden(),'placement ranges hidden for hedges');
    await page.evaluate(()=>{window.__requests=[];});
    await page.locator('#naVegetation_btnStart').click();
    await page.waitForFunction(()=>window.__requests.some(r=>r.action==='start'));
    check(await page.evaluate(()=>!('placement' in window.__requests.find(r=>r.action==='start').payload)),'hedge Draw sends no placement ranges');
    const plants=await browser.newPage({viewport:{width:1380,height:790}});
    await plants.setContent('<html><head><style>body{font:15px Arial;background:#edf0f3;margin:22px;color:#253044}h1{font-size:24px;margin:0 0 6px}main{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-top:18px}article{background:white;padding:14px;border:1px solid #d8dfe6;border-radius:6px}h2{font-size:17px;margin:0 0 6px}p{margin:0;color:#687789}img{width:100%;margin-top:10px}</style></head><body><h1>Noble whitecard flowers &amp; grasses</h1><p>Actual generated meshes · Balanced detail · previews fitted individually</p><main></main></body></html>');
    await plants.evaluate(cards=>{
      cards.forEach(card=>{const box=document.createElement('article'),h=document.createElement('h2'),p=document.createElement('p'),img=document.createElement('img');h.textContent=card.name;p.textContent=card.height+' mm high · '+card.quads+' quads';img.src=card.preview;box.append(h,p,img);document.querySelector('main').append(box);});
    },plantCards);
    await plants.screenshot({path:path.join(__dirname,'flowers-grasses-verified.png'),fullPage:true});
    await plants.close();
    check(errors.length===0,'no browser errors in botanical plant controls: '+errors.join(', '));
    console.log(`PASS: ${checks} Chromium input, creation, selection and bridge checks.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
