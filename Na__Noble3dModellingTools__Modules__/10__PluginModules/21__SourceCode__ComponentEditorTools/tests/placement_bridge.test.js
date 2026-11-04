// The dialog's placement calls, with no browser and no SketchUp process:
//   node tests/placement_bridge.test.js
// Insert At Cursor must paint its status before it calls Ruby, because a big
// library file blocks SketchUp (and so this dialog) for as long as it loads.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const source = fs.readFileSync(path.resolve(__dirname, '../05__UserInterface/Na__ComponentEditorTools__UiBridge__.js'), 'utf8');

function boot(callbacks) {
    const status = { textContent: '', className: '', classList: { add() {} } };
    const frames = [];
    const timers = [];
    const window = {
        sketchup: callbacks,
        requestAnimationFrame: (callback) => frames.push(callback),
        setTimeout: (callback, delay) => timers.push({ callback, delay })
    };
    const document = {
        getElementById: (id) => (id === 'na-component-status' ? status : null),
        addEventListener() {}
    };
    vm.runInNewContext(source, { window, document, console });
    return { window, status, frames, timers };
}

function recording() {
    const calls = { cursor: [], axis: [] };
    return {
        calls,
        callbacks: {
            na_componenteditortools_insert_library_component: (raw) => calls.cursor.push(JSON.parse(raw)),
            na_componenteditortools_insert_at_axis: (raw) => calls.axis.push(JSON.parse(raw))
        }
    };
}

let checks = 0;
function check(label, test) {
    checks += 1;
    try {
        test();
    } catch (error) {
        console.error('FAILED: ' + label);
        throw error;
    }
}

const file = 'D:\\Lib\\Na__CoreLib__3dAssets\\Na__Chair__01.skp';

{
    const { calls, callbacks } = recording();
    const app = boot(callbacks);
    app.window.Na__ComponentEditorTools__InsertLibraryComponent(file);

    check('the status is set at once, naming the file without its folder or .skp', () => {
        assert.equal(app.status.textContent, 'Getting Na__Chair__01 ready...');
    });
    check('Ruby is not called before the paint', () => {
        assert.equal(calls.cursor.length, 0);
        assert.equal(app.frames.length, 1);
        assert.equal(app.timers.length, 0);
    });

    app.frames[0]();
    check('Ruby is not called on the frame itself, which has not painted yet', () => {
        assert.equal(calls.cursor.length, 0);
        assert.equal(app.timers.length, 1);
    });

    app.timers[0].callback();
    check('Ruby is then called once, with the whole path', () => {
        assert.equal(calls.cursor.length, 1);
        assert.equal(calls.cursor[0].path, file);
    });
}

{
    const { callbacks } = recording();
    const app = boot(callbacks);
    app.window.Na__ComponentEditorTools__InsertLibraryComponent('D:/Lib/Sub/Table__02.SKP');
    check('forward slashes and an upper-case extension read the same', () => {
        assert.equal(app.status.textContent, 'Getting Table__02 ready...');
    });
}

{
    const { calls, callbacks } = recording();
    const app = boot(callbacks);
    app.window.Na__ComponentEditorTools__InsertAtAxis(file);
    check('Insert At Axis still calls straight away', () => {
        assert.equal(calls.axis.length, 1);
        assert.equal(calls.axis[0].path, file);
        assert.equal(app.frames.length, 0);
    });
}

{
    const app = boot({});
    app.window.Na__ComponentEditorTools__InsertLibraryComponent(file);
    app.frames[0]();
    app.timers[0].callback();
    check('a missing callback warns on the status bar and does not throw', () => {
        assert.match(app.status.textContent, /callback not available/);
    });
}

console.log('Placement bridge: ' + checks + '/' + checks + ' checks passed.');
