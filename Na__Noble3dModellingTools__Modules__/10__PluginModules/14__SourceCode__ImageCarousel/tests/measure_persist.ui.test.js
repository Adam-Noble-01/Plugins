/* Dimensions kept in the model: the dialog side, in headless Chromium.
 *
 * node tests/measure_persist.ui.test.js <playwright> <chrome.exe>
 *  - every change (reference, add, delete, clear, undo, redo) hands the photo's
 *    dimensions to Ruby (dimensions_save), in photo pixels from the top-left
 *  - a fresh dialog given the model's dimensions shows them again: the same
 *    lines, the same scale, the same readings; a smaller copy of the photo
 *    takes them scaled; loading them sends nothing back
 * Leaves the real payload in tests/out/dims_payload.json for
 *   python tests/run_ruby_checks.py tests/dimension_persistence.rb.test
 */
'use strict';
var path = require('path');
var fs = require('fs');
var harness = require('./perspective_ui_harness.js');
var playwright = require(process.argv[2] || 'playwright');
var CHROME = process.argv[3];

var passes = 0, fails = 0;
function check(name, cond, detail) {
    if (cond) passes++;
    else { fails++; console.log('FAIL  ' + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); }
}

function withTopLeft(h) {
    var screenOfCentred = h.screenOf;
    h.screenOf = function(pt) { return screenOfCentred({ x: pt.x - 2016, y: pt.y - 1512 }); };
}
function sends(page) {
    return page.evaluate(function() {
        return window.__calls.filter(function(c) { return c[0] === 'dimensions_save'; }).map(function(c) { return JSON.parse(c[1]); });
    });
}
function readings(page) {
    return page.evaluate(function() {
        var m = window.Na__ImageViewer__Measure, s = m.getScale();
        return m.getDims().map(function(d) { var px = Math.hypot(d.b.x - d.a.x, d.b.y - d.a.y); return s ? px / s.pxPerMm : px; });
    });
}

(async function main() {
    // ---- 1. draw, and watch what goes to Ruby
    var t = await harness.open(playwright, CHROME, 'measure_persist');
    var page = t.page, h = t.h;
    withTopLeft(h);
    await page.click('#naImageViewer_btnFit');
    await page.evaluate(function() { window.__calls.length = 0; });

    await page.click('#naImageViewer_btnSetRef');
    await h.clickImg({ x: 800, y: 2600 });
    await h.clickImg({ x: 2800, y: 2600 });
    await page.fill('#naImageViewer_refInput', '2000');
    await page.click('#naImageViewer_refOk');
    var s = await sends(page);
    check('setting the reference is sent', s.length === 1 && s[0].scale && s[0].scale.ref && s[0].scale.ref[4] === 2000, s);
    check('in photo pixels from the top-left, with the photo size', s[0].w === 4032 && s[0].h === 3024 && Math.abs(s[0].dims[0][1] - 2600) < 4 && Math.abs(s[0].dims[0][3] - 2600) < 4, s[0]);
    check('the photo is named by its path', /measure_persist_house\.png$/.test(s[0].path), s[0].path);

    await page.keyboard.press('d');
    await h.clickImg({ x: 1000, y: 1000 });
    await h.clickImg({ x: 2200, y: 1000 });
    await h.clickImg({ x: 1000, y: 1200 });
    await h.clickImg({ x: 1000, y: 2200 });
    s = await sends(page);
    check('each dimension is sent', s.length === 3 && s[2].dims.length === 3, s.map(function(x) { return x.dims.length; }));

    await page.keyboard.press('Control+z');
    s = await sends(page);
    check('undo is sent', s.length === 4 && s[3].dims.length === 2, s.length);
    await page.keyboard.press('Control+y');
    s = await sends(page);
    check('redo is sent', s.length === 5 && s[4].dims.length === 3, s.length);
    var kept = s[4];
    var before = await readings(page);
    var beforeDims = await page.evaluate(function() { return window.Na__ImageViewer__Measure.getDims(); });
    var beforeScale = await page.evaluate(function() { return window.Na__ImageViewer__Measure.getScale(); });

    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnSelect');
    var mid = { x: 1600, y: 1000 };
    await h.clickImg(mid);
    await page.keyboard.press('Delete');
    s = await sends(page);
    check('deleting a dimension is sent', s[s.length - 1].dims.length === 2, s[s.length - 1].dims.length);
    await page.keyboard.press('Control+z');
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');

    // the second photo (1008 x 756): its own entry
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(300);
    await page.click('#naImageViewer_btnFit');
    await page.keyboard.press('d');
    var c = await page.evaluate(function() { var r = window.Na__ImageViewer__Core.getCanvas().getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
    await page.mouse.click(c.x - 100, c.y);
    await page.mouse.click(c.x + 100, c.y);
    s = await sends(page);
    check('the other photo is sent on its own, at its own size', /measure_persist_house_small\.png$/.test(s[s.length - 1].path) && s[s.length - 1].w === 1008 && !s[s.length - 1].scale, s[s.length - 1]);
    await page.click('#naImageViewer_btnClearDims');
    s = await sends(page);
    check('Clear All is sent, empty', s[s.length - 1].dims.length === 0 && !s[s.length - 1].scale, s[s.length - 1]);
    var nSends = s.length;
    await page.click('#naImageViewer_btnClearDims');
    check('the same again is not sent twice', (await sends(page)).length === nSends);

    fs.writeFileSync(path.join(harness.OUT, 'dims_payload.json'), JSON.stringify(kept));
    check('no page errors (first dialog)', t.errors.length === 0, t.errors);
    await t.browser.close();

    // ---- 2. a fresh dialog, given what the model holds
    var t2 = await harness.open(playwright, CHROME, 'measure_persist_reopen');
    page = t2.page;
    await page.click('#naImageViewer_btnFit');
    var images = await page.evaluate(function() { return window.Na__ImageViewer__Core.getImages(); });
    var stored = { w: kept.w, h: kept.h, dims: kept.dims, scale: kept.scale };   // the shape LoadForPaths returns
    var map = {};
    map[images[0]] = stored;
    map[images[1]] = stored;                                                      // same shape, a quarter the size
    await page.evaluate(function() { window.__calls.length = 0; });
    await page.evaluate(function(m) { window.Na__ImageViewer__OnDimensionsLoaded(m); }, map);

    var afterDims = await page.evaluate(function() { return window.Na__ImageViewer__Measure.getDims(); });
    var afterScale = await page.evaluate(function() { return window.Na__ImageViewer__Measure.getScale(); });
    var worst = 0;
    afterDims.forEach(function(d, i) {
        var b = beforeDims[i];
        worst = Math.max(worst, Math.abs(d.a.x - b.a.x), Math.abs(d.a.y - b.a.y), Math.abs(d.b.x - b.b.x), Math.abs(d.b.y - b.b.y));
    });
    check('the dimensions come back', afterDims.length === 3, afterDims.length);
    check('on the same points (within 0.001 px)', worst <= 0.0011, worst);
    check('with the same scale and reference', afterScale && Math.abs(afterScale.pxPerMm - beforeScale.pxPerMm) < 1e-9 && afterScale.unit === beforeScale.unit && afterScale.ref && afterScale.ref.mm === 2000, [afterScale, beforeScale]);
    var after = await readings(page);
    check('reading the same lengths', after.length === before.length && after.every(function(v, i) { return Math.abs(v - before[i]) < 0.01; }), [before, after]);
    check('the reference button shows the photo has a scale', await page.$eval('#naImageViewer_btnSetRef', function(b) { return b.classList.contains('naImageViewer__Btn--hasScale'); }));
    check('loading sends nothing back', (await sends(page)).length === 0);

    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(300);
    var small = await readings(page);
    var smallScale = await page.evaluate(function() { return window.Na__ImageViewer__Measure.getScale(); });
    check('a quarter-size copy takes them scaled', small.length === 3 && Math.abs(smallScale.pxPerMm - beforeScale.pxPerMm / 4) < 1e-9, smallScale);
    check('and reads the same lengths', small.every(function(v, i) { return Math.abs(v - before[i]) < 0.01; }), [before, small]);
    check('still nothing sent back', (await sends(page)).length === 0);

    // A different shape stays in the model, untouched
    await page.evaluate(function(p) {
        var m = {}; m[p] = { w: 1000, h: 1000, dims: [[0, 0, 100, 0]] };
        window.Na__ImageViewer__OnDimensionsLoaded(m);
    }, images[0]);
    check('no page errors (second dialog)', t2.errors.length === 0, t2.errors);
    await t2.browser.close();

    console.log(passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
