/* The Dimension tool's options in the real dialog, in headless Chromium.
 *
 * node tests/measure_options.ui.test.js <playwright> <chrome.exe> [folder for screenshots]
 *  - D starts a dimension, and drops a half-drawn one
 *  - the options section (its own divider) shows only while Dimension or
 *    Reference is on; Rounding only once the photo has a reference scale
 *  - Rounding cycles Off, 5, 10, 50, 100, 500, 1000 mm, Off (right-click back)
 *    and every new dimension reads a whole number of steps
 *  - Ortho: F8 and the button; Shift is AutoCAD's override (Ortho XOR Shift);
 *    the cursor picks the axis; level/plumb follow the screen on a rotated photo
 *  - the toolbar does not treat a set option as a running tool
 */
'use strict';
var path = require('path');
var harness = require('./perspective_ui_harness.js');
var playwright = require(process.argv[2] || 'playwright');
var CHROME = process.argv[3];
var SHOTS = process.argv[4];

var passes = 0, fails = 0;
function check(name, cond, detail) {
    if (cond) passes++;
    else { fails++; console.log('FAIL  ' + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); }
}

(async function main() {
    var t = await harness.open(playwright, CHROME, 'measure_options');
    var page = t.page, h = t.h;
    // Photo space is centred on the photo: the points below are written from its top-left corner.
    var screenOfCentred = h.screenOf;
    h.screenOf = function(pt) { return screenOfCentred({ x: pt.x - 2016, y: pt.y - 1512 }); };

    function shown(id) { return page.$eval('#naImageViewer_' + id, function(b) { return b.offsetParent !== null; }); }
    function isOn(id) { return page.$eval('#naImageViewer_' + id, function(b) { return b.classList.contains('naImageViewer__Btn--active'); }); }
    function toggled(id) { return page.$eval('#naImageViewer_' + id, function(b) { return b.classList.contains('naImageViewer__Btn--toggled'); }); }
    function opts() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getOptions(); }); }
    function dims() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getDims(); }); }
    function scale() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getScale(); }); }
    function screenDim(d) {
        return page.evaluate(function(d) {
            var c = window.Na__ImageViewer__Core;
            return { a: c.imgToScreen(d.a), b: c.imgToScreen(d.b) };
        }, d);
    }
    async function last() { var all = await dims(); return all[all.length - 1]; }
    function lenMm(d, s) { return Math.hypot(d.b.x - d.a.x, d.b.y - d.a.y) / s.pxPerMm; }
    async function shiftClick(pt, dx, dy) {
        var s = await h.screenOf(pt);
        await page.keyboard.down('Shift');
        await page.mouse.click(s.x + (dx || 0), s.y + (dy || 0));
        await page.keyboard.up('Shift');
    }

    await page.click('#naImageViewer_btnFit');

    // ---- D, and the section hidden until a tool with options is on
    await page.evaluate(function() { window.Na__ImageViewer__ToolbarMenu.open('measure'); });
    check('options hidden with no tool on', !(await shown('toolOptions')) && !(await shown('toolOptionsDivider')));
    await page.keyboard.press('d');
    check('D starts Dimension', await isOn('btnMeasure'));
    check('options shown with Dimension', await shown('toolOptions') && await shown('toolOptionsDivider'));
    check('Ortho shown', await shown('btnOrtho'));
    check('Rounding hidden before a reference', !(await shown('btnRounding')));
    await h.clickImg({ x: 1000, y: 1000 });
    await page.keyboard.press('D');
    await h.clickImg({ x: 1500, y: 1000 });
    check('D drops a half-drawn dimension', (await dims()).length === 0);
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    check('Esc stops Dimension', !(await isOn('btnMeasure')));
    check('options hidden again', !(await shown('toolOptions')));

    // ---- Reference: 2000 image px = 2000 mm (Ortho shown, Rounding not)
    await page.click('#naImageViewer_btnSetRef');
    check('options shown with Reference', await shown('toolOptions'));
    check('Rounding hidden in Reference', !(await shown('btnRounding')));
    await h.clickImg({ x: 800, y: 2600 });
    await h.clickImg({ x: 2800, y: 2600 });
    await page.fill('#naImageViewer_refInput', '2000');
    await page.click('#naImageViewer_refOk');
    var s = await scale();
    check('reference set', s && s.pxPerMm > 0, s);

    // ---- Rounding
    await page.keyboard.press('d');
    check('Rounding shown once the photo has a scale', await shown('btnRounding'));
    var labels = [];
    for (var i = 0; i < 7; i++) {
        await page.click('#naImageViewer_btnRounding');
        labels.push((await opts()).roundingMm + '|' + (await h.text('#naImageViewer_roundingLabel')));
    }
    check('Rounding cycles 5..1000 then Off',
        labels.join(',') === '5|5 mm,10|10 mm,50|50 mm,100|100 mm,500|500 mm,1000|1000 mm,0|Round Off', labels);
    await page.click('#naImageViewer_btnRounding', { button: 'right' });
    check('right-click steps back to 1000', (await opts()).roundingMm === 1000);
    await page.click('#naImageViewer_btnRounding');                       // Off
    await page.click('#naImageViewer_btnRounding');                       // 5
    await page.click('#naImageViewer_btnRounding');                       // 10
    await page.click('#naImageViewer_btnRounding');                       // 50
    check('Rounding 50 shows as set', (await opts()).roundingMm === 50 && await toggled('btnRounding'));
    check('a set option is not a running tool', !(await isOn('btnRounding')));

    var steps = [[50, { x: 1237, y: 1404 }], [100, { x: 2171, y: 1777 }], [500, { x: 1900, y: 2350 }]];
    for (var k = 0; k < steps.length; k++) {
        while ((await opts()).roundingMm !== steps[k][0]) await page.click('#naImageViewer_btnRounding');
        await h.clickImg({ x: 700, y: 1100 });
        await h.clickImg(steps[k][1]);
        var d = await last(), mm = lenMm(d, s);
        check('rounded to ' + steps[k][0] + ' mm', Math.abs(mm / steps[k][0] - Math.round(mm / steps[k][0])) < 1e-6 && mm >= steps[k][0], mm);
        var raw = Math.hypot(steps[k][1].x - 700, steps[k][1].y - 1100) / s.pxPerMm;
        check('nearest step to ' + raw.toFixed(0) + ' mm', Math.abs(mm - raw) <= steps[k][0] / 2 + 6, mm);
    }
    // A short click still gives one whole step
    while ((await opts()).roundingMm !== 500) await page.click('#naImageViewer_btnRounding');
    await h.clickImg({ x: 700, y: 1100 });
    await h.clickImg({ x: 760, y: 1100 });
    check('never less than one step', Math.abs(lenMm(await last(), s) - 500) < 1e-6, lenMm(await last(), s));
    while ((await opts()).roundingMm !== 0) await page.click('#naImageViewer_btnRounding');

    // ---- Ortho: F8, the button, Shift as the override, cursor picks the axis
    check('Ortho starts off', !(await opts()).ortho);
    await page.keyboard.press('F8');
    check('F8 turns Ortho on', (await opts()).ortho && await toggled('btnOrtho'));
    check('hint says Ortho on', /Ortho on/.test(await h.text('#naImageViewer_measureHint')));
    check('Ortho on is not a running tool', !(await isOn('btnOrtho')));
    await h.clickImg({ x: 1000, y: 1000 });
    await h.clickImg({ x: 1900, y: 1150 });
    var sd = await screenDim(await last());
    check('Ortho: mostly across gives level', Math.abs(sd.a.y - sd.b.y) < 0.01 && Math.abs(sd.b.x - sd.a.x) > 100, sd);
    await h.clickImg({ x: 1000, y: 1000 });
    await h.clickImg({ x: 1150, y: 2000 });
    sd = await screenDim(await last());
    check('Ortho: mostly down gives plumb', Math.abs(sd.a.x - sd.b.x) < 0.01, sd);
    await h.clickImg({ x: 1000, y: 1000 });
    await shiftClick({ x: 1900, y: 1300 });
    sd = await screenDim(await last());
    check('Shift with Ortho on frees the line', Math.abs(sd.a.y - sd.b.y) > 20, sd);

    await page.click('#naImageViewer_btnOrtho');
    check('button turns Ortho off', !(await opts()).ortho && !(await toggled('btnOrtho')));
    await h.clickImg({ x: 1000, y: 1000 });
    await h.clickImg({ x: 1900, y: 1300 });
    sd = await screenDim(await last());
    check('Ortho off: free line', Math.abs(sd.a.y - sd.b.y) > 20, sd);
    await h.clickImg({ x: 1000, y: 1000 });
    await shiftClick({ x: 1900, y: 1300 });
    sd = await screenDim(await last());
    check('Shift with Ortho off locks level', Math.abs(sd.a.y - sd.b.y) < 0.01, sd);

    // Ortho and Rounding together
    while ((await opts()).roundingMm !== 100) await page.click('#naImageViewer_btnRounding');
    await page.keyboard.press('F8');
    await h.clickImg({ x: 1000, y: 1000 });
    await h.clickImg({ x: 2333, y: 1100 });
    var both = await last();
    sd = await screenDim(both);
    check('Ortho + Rounding: level and whole', Math.abs(sd.a.y - sd.b.y) < 0.01 && Math.abs(lenMm(both, s) / 100 - Math.round(lenMm(both, s) / 100)) < 1e-6, { sd: sd, mm: lenMm(both, s) });

    // Rotated photo: level on screen, not along the photo's rows
    await page.click('#naImageViewer_btnRotateL');
    await page.evaluate(function() { window.Na__ImageViewer__ToolbarMenu.open('measure'); });
    await h.clickImg({ x: 1500, y: 1500 });
    await h.clickImg({ x: 1600, y: 600 });
    var rot = await last();
    sd = await screenDim(rot);
    check('rotated photo: Ortho is level/plumb on screen', Math.abs(sd.a.y - sd.b.y) < 0.01 || Math.abs(sd.a.x - sd.b.x) < 0.01, sd);
    check('rotated photo: plumb on screen runs along the image rows', Math.abs(rot.a.y - rot.b.y) < 0.5 || Math.abs(rot.a.x - rot.b.x) < 0.5, rot);
    await page.click('#naImageViewer_btnRotateR');

    // F8 works with no tool on, and survives a reload of the options
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    var before = (await opts()).ortho;
    await page.keyboard.press('F8');
    check('F8 with no tool on', (await opts()).ortho === !before);
    await page.keyboard.press('F8');

    var menu = await page.evaluate(function() { return window.Na__ImageViewer__ToolbarMenu.inspect(); });
    check('no tool reported running after Esc', menu.on.length === 0, menu);

    // ---- Save Image: the full-size picture with the dimensions on it
    await page.evaluate(function() { window.__calls.length = 0; });
    var viewBefore = await page.evaluate(function() { var c = window.Na__ImageViewer__Core; return [c.getZoom(), c.getRotation(), c.imgToScreen({ x: 0, y: 0 })]; });
    await page.click('#naImageViewer_btnSaveImage');
    await page.waitForTimeout(300);
    var calls = await page.evaluate(function() { return window.__calls.map(function(c) { return [c[0], typeof c[1] === 'string' ? c[1].length : c[1]]; }); });
    var asked = calls.filter(function(c) { return c[0] === 'read_image_data'; });
    if (asked.length) {
        // As SketchUp's dialog does: the file taints the canvas, Ruby sends its bytes.
        console.log('  the photo tainted the canvas: drawn again from its bytes');
        var file = await page.evaluate(function() { return window.Na__ImageViewer__Core.getImageKey(); });
        var b64 = require('fs').readFileSync(file).toString('base64');
        await page.evaluate(function(a) { window.Na__ImageViewer__OnImageData({ path: a.p, data: 'data:image/png;base64,' + a.d }); }, { p: file, d: b64 });
        await page.waitForTimeout(1500);
    }
    var sent = await page.evaluate(function() {
        var c = window.__calls.filter(function(x) { return x[0] === 'save_dimensioned_image'; });
        return c.length ? c[c.length - 1][1] : null;
    });
    check('Save sends the picture to Ruby', !!sent);
    var viewAfter = await page.evaluate(function() { var c = window.Na__ImageViewer__Core; return [c.getZoom(), c.getRotation(), c.imgToScreen({ x: 0, y: 0 })]; });
    check('the view is unchanged after saving', JSON.stringify(viewBefore) === JSON.stringify(viewAfter), [viewBefore, viewAfter]);
    if (sent) {
        var payload = JSON.parse(sent);
        check('payload names the photo', /measure_options_house\.png$/.test(payload.path), payload.path);
        check('payload keeps .png', payload.ext === '.png', payload.ext);
        var png = harness.decodePng(Buffer.from(payload.data.split(',')[1], 'base64'));
        check('saved at the photo\'s own size', png.w === 4032 && png.h === 3024, [png.w, png.h]);
        function isRed(q) { return q[0] > 190 && q[1] < 90 && q[2] < 90; }
        // The 2000 mm reference runs along photo row 2600 from x 800 to 2800 (kept as a red dimension).
        check('the reference line is on the saved picture', isRed(png.px(1300, 2600)), png.px(1300, 2600));
        check('beside it, the photo', !isRed(png.px(1300, 2750)), png.px(1300, 2750));
        // The level Ortho + Rounding line from (1000, 1000): red all along that row.
        var red = 0;
        for (var x = 1050; x < 2250; x += 10) { if (isRed(png.px(x, 1000))) red++; }
        check('the ortho dimension is on the saved picture', red > 100, red);
        require('fs').writeFileSync(path.join(harness.OUT, 'save_payload.json'), sent);
        await page.evaluate(function() { window.Na__ImageViewer__OnImageSaved({ ok: true, name: 'x__DimensionsAdded__.png', replaced: false }); });
        check('hint says saved', /Saved x__DimensionsAdded__\.png/.test(await h.text('#naImageViewer_measureHint')));
        await page.evaluate(function() { window.Na__ImageViewer__OnImageSaved({ ok: false, error: 'disk full' }); });
        check('hint says why not', /Not saved: disk full/.test(await h.text('#naImageViewer_measureHint')));
        await page.evaluate(function() { window.__calls.length = 0; });
        await page.keyboard.press('Control+s');
        await page.waitForTimeout(300);
        var again = await page.evaluate(function() { return window.__calls.map(function(c) { return c[0]; }); });
        check('Ctrl+S saves too', again.indexOf('read_image_data') !== -1 || again.indexOf('save_dimensioned_image') !== -1, again);
        check('Save Image sits in the status bar', await page.$eval('#naImageViewer_btnSaveImage', function(b) { return !!b.closest('.naImageViewer__StatusBar') && b.offsetParent !== null; }));
    }

    if (SHOTS) {
        await page.keyboard.press('d');
        await page.screenshot({ path: path.join(SHOTS, 'measure_options_bar.png'), clip: { x: 0, y: 0, width: 1600, height: 90 } });
        await page.screenshot({ path: path.join(SHOTS, 'measure_options_full.png') });
        await page.setViewportSize({ width: 820, height: 900 });
        await page.waitForTimeout(250);
        await page.screenshot({ path: path.join(SHOTS, 'measure_options_narrow.png'), clip: { x: 0, y: 0, width: 820, height: 140 } });
    }

    check('no page errors', t.errors.length === 0, t.errors);
    await t.browser.close();
    console.log(passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
