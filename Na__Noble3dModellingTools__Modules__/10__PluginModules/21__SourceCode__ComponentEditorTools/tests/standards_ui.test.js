// DOM tests only: no SketchUp process or component files are modified.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { JSDOM } = require(process.env.NA_TEST_JSDOM || 'jsdom');
async function run() {
    const ui = path.resolve(__dirname, '../05__UserInterface');
    const dom = new JSDOM(fs.readFileSync(path.join(ui, 'Na__ComponentEditorTools__UiLayout__.html'), 'utf8'), { runScripts: 'outside-only' });
    const w = dom.window;
    await new Promise(resolve => w.document.addEventListener('DOMContentLoaded', resolve));
    const calls = [];
    w.sketchup = { na_componenteditortools_advanced: raw => calls.push(JSON.parse(raw)) };
    w.eval(fs.readFileSync(path.join(ui, 'Na__ComponentEditorTools__Tab__Advanced__.js'), 'utf8'));
    const el = id => w.document.getElementById('na-advanced-' + id);
    const data = {
        token: 'session', path: 'fixture.skp', modified: false, title: 'Fixture',
        tags: [{ id: 'tag:0', name: 'Layer0', display_name: 'Untagged', default: true, uses: 0 }, { id: 'tag:1', name: '<Legacy tag>', display_name: '<Legacy tag>', uses: 2 }],
        materials: [{ id: 'material:1', name: 'Old paint', display_name: 'Old paint', uses: 3, opacity: 100, color: '#ff0000' }],
        definitions: [], entity_types: { Face: 2 }, entity_count: 2, definition_count: 0, root_count: 1,
        standards: { errors: [], tags: [
            { key: 'walls', name: '10__Walls', group: 'Building', description: 'Wall collection' },
            { key: 'roof', name: '20__Roof', group: 'Building', description: 'Roof collection' }
        ], materials: [{ key: 'glass-id', name: 'MAT101__GenericGlass', group: 'Basic', description: 'Glass recipe' }] }
    };
    const receive = (success = true, message = 'Done') => w.Na__ComponentEditorTools__ReceiveAdvanced({ request_id: calls.at(-1).request_id, success, message, data: success ? data : undefined });
    el('query').click(); assert.equal(calls.at(-1).action, 'query'); receive();
    el('edit').click();
    let picker = w.document.getElementById('na-advanced-standard-tag:1');
    assert.equal(picker.options.length, 3);
    assert.equal(w.document.getElementById('na-advanced-standard-tag:0').disabled, true);
    assert.equal(w.document.querySelector('legacy'), null, 'names are rendered as text');
    picker.value = 'walls'; picker.dispatchEvent(new w.Event('change'));
    let apply = picker.parentElement.querySelector('button');
    assert.equal(apply.disabled, false); apply.click();
    assert.deepEqual(calls.at(-1), { action: 'retag_ssot', token: 'session', request_id: 2, id: 'tag:1', existing_name: '<Legacy tag>', standard_key: 'walls' });
    assert.equal(picker.disabled, true); receive(false, 'Stale query');
    assert.equal(picker.disabled, false); assert.match(el('status').textContent, /Stale query/);
    const search = picker.parentElement.querySelector('input');
    search.value = 'roof'; search.dispatchEvent(new w.Event('input'));
    assert.equal(picker.options.length, 2); assert.equal(picker.options[1].value, 'roof');
    assert.equal(apply.disabled, true, 'filtering out the selected choice disables Apply');
    el('materials').click();
    picker = w.document.getElementById('na-advanced-standard-material:1');
    picker.value = 'glass-id'; picker.dispatchEvent(new w.Event('change')); picker.parentElement.querySelector('button').click();
    assert.equal(calls.at(-1).action, 'swap_material_ssot'); assert.equal(calls.at(-1).standard_key, 'glass-id');
    data.modified = true; receive(); assert.equal(el('save-file').disabled, false);
    assert.match(el('editor-help').textContent, /PBR recipe/);
    console.log('SSOT dropdown UI: 16 assertions passed'); dom.window.close();
}
run().catch(error => { console.error(error); process.exitCode = 1; });
