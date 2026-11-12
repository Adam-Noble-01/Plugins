/* The 2D Protractor, in headless Chromium.
 *
 * node tests/protractor.ui.test.js <playwright> <chrome.exe> [folder for screenshots]
 *  - P (or the button) starts it, in the Measure row between the dividers
 *  - corner, first line, second line: the angle as drawn, to 0.1 degree
 *  - Ortho (F8) and Shift hold an arm level or plumb from the corner
 *  - points snap onto a dimension's end; the middle button pans throughout
 *  - Esc steps back; select, drag a grip (one undo step, Esc puts it back),
 *    Delete; Clear All takes protractors with dimensions in one undo step
 *  - kept in the model (tool 'protractor') and given back to a fresh dialog
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
function rad(d) { return d * Math.PI / 180; }

(async function main() {
    var t = await harness.open(playwright, CHROME, 'protractor');
    var page = t.page, h = t.h;
    var screenOfCentred = h.screenOf;
    h.screenOf = function(pt) { return screenOfCentred({ x: pt.x - 2016, y: pt.y - 1512 }); };
    function TL(p) { return { x: p.x + 2016, y: p.y + 1512 }; }
    function info() { return page.evaluate(function() { return window.Na__ImageViewer__Protractor.inspect(); }); }
    function hint() { return h.text('#naImageViewer_measureHint'); }
    function isOn(id) { return page.$eval('#naImageViewer_' + id, function(b) { return b.classList.contains('naImageViewer__Btn--active'); }); }
    function along(v, deg, len) { return { x: v.x + Math.cos(rad(deg)) * len, y: v.y - Math.sin(rad(deg)) * len }; }   // photo y runs down
    async function drag(fromTL, toTL, opt) {
        opt = opt || {};
        var a = await h.screenOf(fromTL), b = await h.screenOf(toTL);
        await page.mouse.move(a.x, a.y);
        await page.mouse.down();
        await page.mouse.move(b.x, b.y, { steps: 8 });
        if (opt.beforeUp) await opt.beforeUp();
        await page.mouse.up();
    }

    await page.click('#naImageViewer_btnFit');
    var ratio = await page.evaluate(function() { return window.Na__ImageViewer__Core.getRatio(); });

    // ---- where it sits
    var row = await page.evaluate(function() {
        return Array.prototype.map.call(document.querySelectorAll('[data-toolset="measure"] > *'), function(el) {
            return el.id ? el.id.replace('naImageViewer_', '') : (el.classList.contains('naImageViewer__ToolbarDivider') ? '|' : '?');
        }).filter(function(x) { return x !== '?'; });
    });
    check('the Measure row is grouped: Reference Dimension | Count Spans Count Points | Angle Protractor | Select ...',
        row.join(' ').indexOf('btnSetRef btnMeasure | btnCount btnCountPoints | btnPerspective btnProtractor | btnSelect') === 0, row.join(' '));

    // ---- P starts it; corner, first line, second line
    await page.keyboard.press('p');
    check('P starts the Protractor', (await info()).active && await isOn('btnProtractor'));
    check('the Measure set opens with it', (await page.evaluate(function() { return window.Na__ImageViewer__ToolbarMenu.inspect().open; })) === 'measure');
    check('the hint says what to click', /click the corner/.test(await hint()), await hint());
    var V = { x: 1100, y: 2300 };
    await h.clickImg(V);
    check('after the corner it asks for the first line', (await info()).placing === 1 && /first line/.test(await hint()));
    await h.clickImg(along(V, 0, 1300));
    check('then the second', (await info()).placing === 2 && /second line/.test(await hint()));
    await h.clickImg(along(V, 40, 1300));
    var it = (await info()).items;
    check('a protractor is made', it.length === 1 && (await info()).placing === 0);
    check('it reads 40 degrees (within 0.3)', it.length && Math.abs(it[0].deg - 40) < 0.3, it[0] && it[0].deg);
    check('labelled to 0.1 degree', it.length && /^\d+\.\d°$/.test(it[0].label), it[0] && it[0].label);

    // an obtuse one and its reading
    await h.clickImg({ x: 2600, y: 2300 });
    await h.clickImg(along({ x: 2600, y: 2300 }, 0, 800));
    await h.clickImg(along({ x: 2600, y: 2300 }, 135, 800));
    it = (await info()).items;
    check('it reads past 90: 135 degrees', Math.abs(it[1].deg - 135) < 0.4, it[1].deg);

    // ---- Ortho holds the first arm level; the roof line gives the pitch
    await page.keyboard.press('F8');
    var R = { x: 900, y: 900 };
    await h.clickImg(R);
    await h.clickImg({ x: R.x + 900, y: R.y + 70 });      // a little off level: held level
    await page.keyboard.press('F8');                       // Ortho off for the roof line
    await h.clickImg(along(R, 47.5, 900));
    it = (await info()).items;
    var o = await page.evaluate(function(i) { var c = window.Na__ImageViewer__Core; return [c.imgToScreen(i.v), c.imgToScreen(i.a)]; }, it[2]);
    check('Ortho held the first arm level', Math.abs(o[0].y - o[1].y) < 0.01, o);
    check('and the pitch reads 47.5 (within 0.4)', Math.abs(it[2].deg - 47.5) < 0.4, it[2].deg);
    // Shift with Ortho off holds an arm plumb
    await h.clickImg({ x: 3300, y: 2600 });
    var s0 = await h.screenOf({ x: 3360, y: 1700 });
    await page.keyboard.down('Shift');
    await page.mouse.move(s0.x, s0.y, { steps: 3 });
    await page.mouse.click(s0.x, s0.y);
    await page.keyboard.up('Shift');
    await h.clickImg({ x: 3800, y: 2600 });
    it = (await info()).items;
    o = await page.evaluate(function(i) { var c = window.Na__ImageViewer__Core; return [c.imgToScreen(i.v), c.imgToScreen(i.a)]; }, it[3]);
    check('Shift held the arm plumb', Math.abs(o[0].x - o[1].x) < 0.01, o);
    check('a right angle against the level reads 90 (within 0.4)', Math.abs(it[3].deg - 90) < 0.4, it[3].deg);

    // ---- Esc steps back, then stops
    await h.clickImg({ x: 2000, y: 600 });
    await h.clickImg({ x: 2400, y: 600 });
    await page.keyboard.press('Escape');
    check('Esc takes back the last point', (await info()).placing === 1);
    await page.keyboard.press('Escape');
    check('and the corner', (await info()).placing === 0 && (await info()).active);

    // ---- the middle button pans while placing
    await h.clickImg({ x: 2000, y: 600 });
    var o0 = await page.evaluate(function() { return window.Na__ImageViewer__Core.imgToScreen({ x: 0, y: 0 }); });
    var mp = await h.screenOf({ x: 2000, y: 1500 });
    await page.mouse.move(mp.x, mp.y); await page.mouse.down({ button: 'middle' }); await page.mouse.move(mp.x + 80, mp.y + 40, { steps: 5 }); await page.mouse.up({ button: 'middle' });
    var o1 = await page.evaluate(function() { return window.Na__ImageViewer__Core.imgToScreen({ x: 0, y: 0 }); });
    check('the middle button pans while placing', Math.abs(o1.x - o0.x - 80 * ratio) < 0.5 && (await info()).placing === 1, [o0, o1]);
    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnFit');

    // ---- select, drag a grip, Esc puts it back, Delete
    var first = (await info()).items[0];
    var armMid = TL({ x: (first.v.x + first.a.x) / 2, y: (first.v.y + first.a.y) / 2 });
    await h.clickImg(armMid);
    check('a click on an arm selects it', (await info()).selected === 0 && /selected/.test(await hint()), (await info()).selected);
    var before = (await info()).items[0];
    await drag(TL(before.v), { x: TL(before.v).x - 200, y: TL(before.v).y + 150 });
    var moved = (await info()).items[0];
    check('dragging the corner moves it, the arms\' ends stay', moved.a.x === before.a.x && moved.b.y === before.b.y && Math.abs(moved.v.x - before.v.x + 200) < 6, [moved.v, before.v]);
    check('and the reading changes', Math.abs(moved.deg - before.deg) > 1, [before.deg, moved.deg]);
    await page.keyboard.press('Control+z');
    check('one undo puts it back', JSON.stringify((await info()).items[0]) === JSON.stringify(before));
    await drag(TL(before.b), { x: TL(before.b).x + 300, y: TL(before.b).y + 300 }, { beforeUp: async function() { await page.keyboard.press('Escape'); } });
    check('Esc mid-drag puts it back', JSON.stringify((await info()).items[0]) === JSON.stringify(before));
    await h.clickImg(armMid);
    var n = (await info()).items.length;
    await page.keyboard.press('Delete');
    check('Delete removes the selected protractor', (await info()).items.length === n - 1);
    await page.keyboard.press('Control+z');
    check('undo brings it back', (await info()).items.length === n);

    // ---- snaps onto a dimension's end
    await page.keyboard.press('d');
    await h.clickImg({ x: 400, y: 2800 });
    await h.clickImg({ x: 1200, y: 2800 });
    await page.keyboard.press('Escape');
    var dimEnd = (await page.evaluate(function() { return window.Na__ImageViewer__Measure.getDims(); })).slice(-1)[0].b;
    await page.keyboard.press('p');
    await h.clickImg({ x: TL(dimEnd).x + 4, y: TL(dimEnd).y - 3 });
    await h.clickImg({ x: 1800, y: 2800 });
    await h.clickImg({ x: 1800, y: 2200 });
    var snapped = (await info()).items.slice(-1)[0];
    check('the corner snaps onto a dimension\'s end', snapped.v.x === dimEnd.x && snapped.v.y === dimEnd.y, [snapped.v, dimEnd]);

    // ---- Clear All: dimensions and protractors, one undo step
    var nItems = (await info()).items.length;
    await page.click('#naImageViewer_btnClearDims');
    var nDims = (await page.evaluate(function() { return window.Na__ImageViewer__Measure.getDims(); })).length;
    check('Clear All clears the protractors with the dimensions', (await info()).items.length === 0 && nDims === 0);
    await page.keyboard.press('Control+z');
    check('one undo brings both back', (await info()).items.length === nItems && (await page.evaluate(function() { return window.Na__ImageViewer__Measure.getDims(); })).length === 1);

    // ---- kept in the model
    await page.keyboard.press('p');
    await page.waitForTimeout(700);
    var sent = await page.evaluate(function() {
        return window.__calls.filter(function(c) { return c[0] === 'tool_state_save'; }).map(function(c) { return JSON.parse(c[1]); })
            .filter(function(p) { return p.tool === 'protractor'; });
    });
    var last = sent[sent.length - 1];
    check('the protractors reach Ruby', last && last.state && last.state.items.length === nItems, sent.length);
    var it0 = (await info()).items[0];
    check('in photo pixels from the top-left', last && Math.abs(last.state.items[0].v.x - TL(it0.v).x) < 0.01 && Math.abs(last.state.items[0].v.y - TL(it0.v).y) < 0.01);
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'protractor.png') });
    var readings = (await info()).items.map(function(i) { return i.label; });
    check('no page errors (first dialog)', t.errors.length === 0, t.errors);
    await t.browser.close();

    var t2 = await harness.open(playwright, CHROME, 'protractor_reopen');
    var images = await t2.page.evaluate(function() { return window.Na__ImageViewer__Core.getImages(); });
    var map = { protractor: {} };
    map.protractor[images[0]] = { w: last.w, h: last.h, state: last.state };
    await t2.page.evaluate(function(m) { window.Na__ImageViewer__OnToolStateLoaded(m); }, map);
    var back = await t2.page.evaluate(function() { return window.Na__ImageViewer__Protractor.inspect().items.map(function(i) { return i.label; }); });
    check('a fresh dialog shows them again, reading the same', JSON.stringify(back) === JSON.stringify(readings), [readings, back]);
    check('no page errors (second dialog)', t2.errors.length === 0, t2.errors);
    await t2.browser.close();

    console.log(passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
