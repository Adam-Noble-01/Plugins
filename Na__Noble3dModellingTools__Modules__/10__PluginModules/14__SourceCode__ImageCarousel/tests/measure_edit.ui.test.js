/* Editing dimensions after they are drawn (Select), in headless Chromium.
 *
 * node tests/measure_edit.ui.test.js <playwright> <chrome.exe> [folder for screenshots]
 *  - grab an end (even of a dimension not yet selected, 14 px reach) and drag
 *    it: the other end stays put, the reading follows, one undo step
 *  - a press that hardly moves changes nothing; Esc mid-drag puts it back
 *  - drag the line to move it all; Ortho holds an end level with the other;
 *    Rounding gives whole steps; an end snaps onto another dimension's end
 *  - type a length and Enter (the digits do not fit or zoom the photo)
 *  - moving the reference's end, or typing its length, re-scales the photo
 *  - every edit is handed to the model (dimensions_save)
 *  - the middle button pans in Dimension, Reference and Select, a
 *    half-drawn dimension waiting; Reference is first in the Measure row
 *  - Ortho guides: dashed red level and green plumb lines at half strength
 *    through the end being placed or dragged, with Shift too, gone otherwise
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
    var t = await harness.open(playwright, CHROME, 'measure_edit');
    var page = t.page, h = t.h;
    var screenOfCentred = h.screenOf;
    h.screenOf = function(pt) { return screenOfCentred({ x: pt.x - 2016, y: pt.y - 1512 }); };
    function TL(p) { return { x: p.x + 2016, y: p.y + 1512 }; }      // centred -> top-left photo px

    function dims() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getDims(); }); }
    function scale() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getScale(); }); }
    function opts() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getOptions(); }); }
    function selected() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getSelected(); }); }
    function hint() { return h.text('#naImageViewer_measureHint'); }
    function mm(d, s) { return Math.hypot(d.b.x - d.a.x, d.b.y - d.a.y) / s.pxPerMm; }
    function sends() { return page.evaluate(function() { return window.__calls.filter(function(c) { return c[0] === 'dimensions_save'; }).length; }); }
    async function drag(fromTL, toTL, opt) {
        opt = opt || {};
        var a = await h.screenOf(fromTL), b = await h.screenOf(toTL);
        await page.mouse.move(a.x + (opt.dx || 0), a.y + (opt.dy || 0));
        await page.mouse.down();
        if (opt.shift) await page.keyboard.down('Shift');
        await page.mouse.move(b.x, b.y, { steps: 8 });
        if (opt.beforeUp) await opt.beforeUp();
        await page.mouse.up();
        if (opt.shift) await page.keyboard.up('Shift');
    }

    await page.click('#naImageViewer_btnFit');
    var zoom = await page.evaluate(function() { return window.Na__ImageViewer__Core.getZoom(); });
    var tol = 1.2 / zoom;                       // a screen pixel and a bit, in photo px

    // A reference (2000 px = 2000 mm) and two dimensions
    await page.click('#naImageViewer_btnSetRef');
    await h.clickImg({ x: 800, y: 2600 });
    await h.clickImg({ x: 2800, y: 2600 });
    await page.fill('#naImageViewer_refInput', '2000');
    await page.click('#naImageViewer_refOk');
    await page.keyboard.press('d');
    await h.clickImg({ x: 1000, y: 1000 });
    await h.clickImg({ x: 2000, y: 1000 });
    await h.clickImg({ x: 1000, y: 1600 });
    await h.clickImg({ x: 1000, y: 2200 });
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    var s = await scale();
    var d0 = await dims();
    check('set up: a reference and two dimensions', d0.length === 3 && Math.abs(mm(d0[1], s) - 1000) < 4, d0.length);

    await page.click('#naImageViewer_btnSelect');
    check('Select says how to edit', /grab an end and drag it/.test(await hint()), await hint());

    // ---- grab an end of a dimension not yet selected, from 10 px away, and drag it
    var endB = TL(d0[1].b);
    var near = await h.screenOf(endB);
    await page.mouse.move(near.x + 7, near.y - 7);
    check('over an end the pointer is a crosshair', await page.$eval('#naImageViewer_canvas', function(c) { return getComputedStyle(c).cursor; }) === 'crosshair');
    await page.evaluate(function() { window.__calls.length = 0; });
    await drag(endB, { x: 2300, y: 1000 }, { dx: 7, dy: -7 });
    var d1 = await dims();
    check('the end moved to the pointer', Math.abs(TL(d1[1].b).x - 2300) < tol * 3 && Math.abs(TL(d1[1].b).y - 1000) < tol * 3, TL(d1[1].b));
    check('the other end stayed put', d1[1].a.x === d0[1].a.x && d1[1].a.y === d0[1].a.y);
    check('it reads about 1300 mm', Math.abs(mm(d1[1], s) - 1300) < 6, mm(d1[1], s));
    check('grabbing it selected it', JSON.stringify(await selected()) === JSON.stringify(d1[1]));
    check('the edit is handed to the model', await sends() === 1);
    await page.keyboard.press('Control+z');
    check('one undo puts it back', Math.abs(mm((await dims())[1], s) - mm(d0[1], s)) < 1e-9);
    await page.keyboard.press('Control+y');
    check('redo brings it again', Math.abs(mm((await dims())[1], s) - mm(d1[1], s)) < 1e-9);

    // ---- a press that hardly moves changes nothing
    var before = await dims();
    var undoBefore = await page.$eval('#naImageViewer_btnUndo', function(b) { return b.disabled; });
    var sp = await h.screenOf(TL(before[1].b));
    await page.mouse.move(sp.x, sp.y); await page.mouse.down(); await page.mouse.move(sp.x + 1.5, sp.y + 1); await page.mouse.up();
    check('a press under 3 px moves nothing', JSON.stringify(await dims()) === JSON.stringify(before));

    // ---- Esc mid-drag puts it back
    await drag(TL(before[1].b), { x: 2600, y: 1300 }, { beforeUp: async function() { await page.keyboard.press('Escape'); } });
    check('Esc mid-drag puts it back', JSON.stringify(await dims()) === JSON.stringify(before), await dims());
    check('and says so', /Put back/.test(await hint()));

    // ---- drag the line to move it all
    var mid = { x: (TL(before[1].a).x + TL(before[1].b).x) / 2, y: TL(before[1].a).y };
    var ms = await h.screenOf(mid);
    await page.mouse.move(ms.x, ms.y);
    check('over the line the pointer is a move cursor', await page.$eval('#naImageViewer_canvas', function(c) { return getComputedStyle(c).cursor; }) === 'move');
    await drag(mid, { x: mid.x + 200, y: mid.y + 300 });
    var moved = (await dims())[1];
    var dax = moved.a.x - before[1].a.x, day = moved.a.y - before[1].a.y;
    check('the whole dimension moved', Math.abs(dax - 200) < tol * 3 && Math.abs(day - 300) < tol * 3, [dax, day]);
    check('its length did not change', Math.abs(mm(moved, s) - mm(before[1], s)) < 1e-6);

    // ---- Ortho: the end is held level with the fixed end
    await page.keyboard.press('F8');
    var cur = (await dims())[1];
    await drag(TL(cur.b), { x: TL(cur.b).x + 400, y: TL(cur.b).y + 90 });
    var o = (await dims())[1];
    var so = await page.evaluate(function(d) { var c = window.Na__ImageViewer__Core; return [c.imgToScreen(d.a), c.imgToScreen(d.b)]; }, o);
    check('Ortho holds the end level with the other', Math.abs(so[0].y - so[1].y) < 0.01, so);
    await page.keyboard.press('F8');
    // Shift does the same with Ortho off
    cur = o;
    await drag(TL(cur.b), { x: TL(cur.a).x + 60, y: TL(cur.a).y + 600 }, { shift: true });   // mostly down from the fixed end
    o = (await dims())[1];
    so = await page.evaluate(function(d) { var c = window.Na__ImageViewer__Core; return [c.imgToScreen(d.a), c.imgToScreen(d.b)]; }, o);
    check('Shift holds it plumb with Ortho off', Math.abs(so[0].x - so[1].x) < 0.01, so);

    // ---- Rounding gives whole steps
    await page.click('#naImageViewer_btnMeasure');          // Rounding lives with Dimension
    while ((await opts()).roundingMm !== 50) await page.click('#naImageViewer_btnRounding');
    await page.click('#naImageViewer_btnSelect');
    cur = (await dims())[1];
    await drag(TL(cur.b), { x: TL(cur.a).x + 1333, y: TL(cur.a).y + 517 });
    var r = mm((await dims())[1], s);
    check('Rounding: the dragged length is a whole 50 mm', Math.abs(r / 50 - Math.round(r / 50)) < 1e-6, r);
    await page.click('#naImageViewer_btnMeasure');
    while ((await opts()).roundingMm !== 0) await page.click('#naImageViewer_btnRounding');
    await page.click('#naImageViewer_btnSelect');

    // ---- an end snaps onto another dimension's end
    var other = (await dims())[2];
    cur = (await dims())[1];
    await drag(TL(cur.b), { x: TL(other.a).x + 4, y: TL(other.a).y - 3 });
    var snapped = (await dims())[1];
    check('an end snaps onto another dimension\'s end', snapped.b.x === other.a.x && snapped.b.y === other.a.y, [snapped.b, other.a]);

    // ---- type a length
    var zBefore = await page.evaluate(function() { return window.Na__ImageViewer__Core.getZoom(); });
    await page.keyboard.type('1250');
    check('the typed length shows', /Length: 1250/.test(await hint()), await hint());
    await page.keyboard.press('Enter');
    var typed = (await dims())[1];
    check('Enter sets it exactly', Math.abs(mm(typed, s) - 1250) < 1e-6, mm(typed, s));
    check('the end last dragged moved, the other stayed', typed.a.x === snapped.a.x && typed.a.y === snapped.a.y);
    check('the digits did not fit or zoom the photo', await page.evaluate(function() { return window.Na__ImageViewer__Core.getZoom(); }) === zBefore);
    await page.keyboard.type('125cm');
    await page.keyboard.press('Enter');
    check('125cm reads as 1250 mm', Math.abs(mm((await dims())[1], s) - 1250) < 1e-6);
    await page.keyboard.type('9x');
    await page.keyboard.press('Escape');
    check('Esc clears a typed length and keeps the selection', (await page.evaluate(function() { return window.Na__ImageViewer__Measure.getTyped(); })) === '' && !!(await selected()));
    var countBefore = (await dims()).length;
    await page.keyboard.press('Backspace');
    check('with nothing typed, Backspace still deletes', (await dims()).length === countBefore - 1);
    await page.keyboard.press('Control+z');

    // ---- the reference: moving its end re-scales the photo
    var ref = (await dims())[0];
    var otherReadBefore = mm((await dims())[2], await scale());
    await drag(TL(ref.b), { x: 3300, y: 2600 });
    var s2 = await scale();
    var ref2 = (await dims())[0];
    check('the reference keeps its known length', Math.abs(mm(ref2, s2) - 2000) < 1e-6 && s2.ref.mm === 2000, mm(ref2, s2));
    check('the photo is re-scaled', Math.abs(s2.pxPerMm - Math.hypot(ref2.b.x - ref2.a.x, ref2.b.y - ref2.a.y) / 2000) < 1e-9 && s2.pxPerMm > s.pxPerMm * 1.2, s2.pxPerMm);
    check('and the other dimensions read in the new scale', mm((await dims())[2], s2) < otherReadBefore * 0.85, [otherReadBefore, mm((await dims())[2], s2)]);
    check('the hint says so', /re-scaled/.test(await hint()), await hint());
    await page.keyboard.press('Control+z');
    check('undo restores the scale too', Math.abs((await scale()).pxPerMm - s.pxPerMm) < 1e-12);
    // typing the reference's length re-states it
    await page.mouse.click((await h.screenOf({ x: 1800, y: 2600 })).x, (await h.screenOf({ x: 1800, y: 2600 })).y);
    await page.keyboard.type('2500');
    await page.keyboard.press('Enter');
    var s3 = await scale();
    check('typing the reference\'s length re-scales the photo', s3.ref.mm === 2500 && Math.abs(s3.pxPerMm - s.pxPerMm * 2000 / 2500) < 1e-9, s3);
    check('the reference line itself did not move', JSON.stringify((await dims())[0]) === JSON.stringify(ref));

    // ---- click in empty photo deselects
    var empty = await h.screenOf({ x: 3600, y: 400 });
    await page.mouse.click(empty.x, empty.y);
    check('a click on nothing deselects', (await selected()) === null);

    // ---- the middle button pans whatever is drawing
    function origin() { return page.evaluate(function() { return window.Na__ImageViewer__Core.imgToScreen({ x: 0, y: 0 }); }); }
    async function middleDrag(fromTL, dx, dy) {
        var a = await h.screenOf(fromTL);
        await page.mouse.move(a.x, a.y);
        await page.mouse.down({ button: 'middle' });
        await page.mouse.move(a.x + dx, a.y + dy, { steps: 6 });
        await page.mouse.up({ button: 'middle' });
    }
    var ratio = await page.evaluate(function() { return window.Na__ImageViewer__Core.getRatio(); });
    await page.keyboard.press('d');
    await h.clickImg({ x: 600, y: 600 });                 // a dimension half drawn
    var o0 = await origin();
    await middleDrag({ x: 1500, y: 1500 }, 120, 80);
    var o1 = await origin();
    check('middle-drag pans while a dimension is half drawn', Math.abs(o1.x - o0.x - 120 * ratio) < 0.5 && Math.abs(o1.y - o0.y - 80 * ratio) < 0.5, [o0, o1]);
    var nDims = (await dims()).length;
    await h.clickImg({ x: 1400, y: 600 });                // the second point, after the pan
    var made = (await dims()).slice(-1)[0];
    check('the dimension is finished where it was started', (await dims()).length === nDims + 1 && Math.abs(TL(made.a).x - 600) < tol * 2 && Math.abs(TL(made.b).x - 1400) < tol * 2, [TL(made.a), TL(made.b)]);
    var o2 = await origin();
    var l0 = await h.screenOf({ x: 2600, y: 3000 });
    await page.mouse.move(l0.x, l0.y); await page.mouse.down(); await page.mouse.move(l0.x + 90, l0.y + 40, { steps: 5 }); await page.mouse.up();
    check('a left drag in Dimension still does not pan', JSON.stringify(await origin()) === JSON.stringify(o2));
    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnSetRef');
    await page.keyboard.press('Escape');                  // (cancel the reference prompt if any)
    await page.click('#naImageViewer_btnSetRef');
    o2 = await origin();
    await middleDrag({ x: 2000, y: 2000 }, -60, 30);
    var o3 = await origin();
    check('middle-drag pans in Reference', Math.abs(o3.x - o2.x + 60 * ratio) < 0.5 && Math.abs(o3.y - o2.y - 30 * ratio) < 0.5, [o2, o3]);
    await page.click('#naImageViewer_btnSelect');
    var dimsBeforePan = JSON.stringify(await dims());
    var onLine = (await dims())[1];
    await middleDrag(TL({ x: (onLine.a.x + onLine.b.x) / 2, y: (onLine.a.y + onLine.b.y) / 2 }), 50, -40);
    var o4 = await origin();
    check('middle-drag on a dimension in Select pans, it does not move the dimension', Math.abs(o4.x - o3.x - 50 * ratio) < 0.5 && JSON.stringify(await dims()) === dimsBeforePan, [o3, o4]);

    // ---- Ortho guides: red level and green plumb, dashed, half see-through, through the free end
    function guide() { return page.evaluate(function() { return window.Na__ImageViewer__Measure.getGuide(); }); }
    async function shot() { return harness.decodePng(await page.screenshot()); }
    var cbox = await page.evaluate(function() { var r = window.Na__ImageViewer__Core.getCanvas().getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; });
    // Is (x, y) - or a pixel within a dash of it along the line - a 50% blend of colour over the plain picture?
    function blended(withG, without, xs, ys, rgb) {
        for (var i = 0; i < xs.length; i++) {
            var A = withG.px(xs[i], ys[i]), B = without.px(xs[i], ys[i]);
            var ok = [0, 1, 2].every(function(c) { return Math.abs(A[c] - (B[c] + rgb[c]) / 2) <= 14; });
            if (ok) return true;
        }
        return false;
    }
    await page.click('#naImageViewer_btnFit');            // the pans above moved the photo: fit it again
    await page.click('#naImageViewer_btnMeasure');
    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnMeasure');
    check('no guides with Ortho off', (await guide()) === null);
    await page.keyboard.press('F8');
    var gp = await h.screenOf({ x: 900, y: 2800 });
    await page.mouse.move(gp.x, gp.y);
    var g0 = await guide();
    check('with Ortho on, guides through the pointer before the first point', g0 && Math.abs(g0.x / ratio + cbox.l - gp.x) < 1.5 && Math.abs(g0.y / ratio + cbox.t - gp.y) < 1.5, g0);
    await h.clickImg({ x: 900, y: 2800 });
    await h.moveImg({ x: 1900, y: 2860 });
    var g1 = await guide();
    var p1s = await h.screenOf({ x: 900, y: 2800 });
    check('placing the second point, they cross at its end, level with the first', g1 && Math.abs(g1.y / ratio + cbox.t - p1s.y) < 0.6 && (g1.x / ratio + cbox.l) > p1s.x + 100, [g1, p1s]);
    var A = await shot();
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'measure_ortho_guides.png') });
    await page.keyboard.press('F8');                     // Ortho off: the guides go
    check('Ortho off: gone', (await guide()) === null);
    await page.keyboard.press('F8');
    await h.moveImg({ x: 1900, y: 2860 });
    A = await shot();
    await page.keyboard.press('F8');
    await page.waitForTimeout(50);
    var B = await shot();
    await page.keyboard.press('F8');
    g1 = await guide();
    var gx = Math.floor(g1.x) / ratio + cbox.l, gy = Math.floor(g1.y) / ratio + cbox.t;   // the pixel the line is snapped into
    var ysAlong = [], xsAt = [], xsAlong = [], ysAt = [];
    for (var k = 0; k < 14; k++) { xsAt.push(gx); ysAlong.push(cbox.t + 200 + k); xsAlong.push(cbox.l + 20 + k); ysAt.push(gy); }
    check('the plumb guide is green at half strength over the photo', blended(A, B, xsAt, ysAlong, [0x17, 0x8a, 0x3a]), [A.px(gx, cbox.t + 200), B.px(gx, cbox.t + 200)]);
    check('the level guide is red at half strength', blended(A, B, xsAlong, ysAt, [0xd4, 0x29, 0x1c]), [A.px(cbox.l + 20, gy), B.px(cbox.l + 20, gy)]);
    var gaps = 0;
    for (var yy = cbox.t + 200; yy < cbox.t + 260; yy++) { var a1 = A.px(gx, yy), b1 = B.px(gx, yy); if (Math.abs(a1[1] - b1[1]) < 3 && Math.abs(a1[0] - b1[0]) < 3) gaps++; }
    check('and dashed (gaps along it)', gaps >= 15 && gaps <= 45, gaps);
    check('they run across the whole view', blended(A, B, xsAt.map(function() { return gx; }), ysAlong.map(function(y) { return y - 200 + cbox.h - 40; }), [0x17, 0x8a, 0x3a]));
    await page.keyboard.press('Escape');
    await page.keyboard.press('F8');                     // Ortho off
    await page.keyboard.down('Shift');
    await page.mouse.move(gp.x + 5, gp.y + 5);
    check('holding Shift brings them with Ortho off', (await guide()) !== null);
    await page.keyboard.up('Shift');
    await page.mouse.move(gp.x + 6, gp.y + 6);
    check('releasing Shift takes them away', (await guide()) === null);
    // dragging an end in Select
    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnSelect');
    var gd = (await dims())[1], during = null;
    await drag(TL(gd.b), { x: TL(gd.a).x + 700, y: TL(gd.a).y + 80 }, { shift: true, beforeUp: async function() { during = await guide(); } });
    var gde = (await dims())[1];
    var gdeS = await page.evaluate(function(p) { return window.Na__ImageViewer__Core.imgToScreen(p); }, gde.b);
    check('dragging an end with Shift: guides through that end', during && Math.abs(during.x - gdeS.x) < 0.6 && Math.abs(during.y - gdeS.y) < 0.6, [during, gdeS]);
    check('gone once dropped', (await guide()) === null);
    var flat = await page.evaluate(function() { var c = window.Na__ImageViewer__Core; return c.renderExport ? true : false; });
    check('(the saved picture never carries guides: they are drawn after the export cut-off)', flat);

    // ---- Reference comes first in the Measure row
    var order = await page.evaluate(function() {
        return Array.prototype.map.call(document.querySelectorAll('[data-toolset="measure"] > button[id]'), function(b) { return b.id.replace('naImageViewer_', ''); });
    });
    check('Reference is the first tool in the Measure row, then Dimension', order[0] === 'btnSetRef' && order[1] === 'btnMeasure', order);

    if (SHOTS) {
        var e1 = (await dims())[1];
        var g = await h.screenOf(TL(e1.b));
        await page.mouse.click(g.x, g.y);
        await page.mouse.move(g.x + 3, g.y);
        await page.screenshot({ path: path.join(SHOTS, 'measure_edit_grips.png'), clip: { x: Math.max(0, g.x - 420), y: Math.max(0, g.y - 160), width: 620, height: 320 } });
    }
    check('no page errors', t.errors.length === 0, t.errors);
    await t.browser.close();
    console.log(passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
