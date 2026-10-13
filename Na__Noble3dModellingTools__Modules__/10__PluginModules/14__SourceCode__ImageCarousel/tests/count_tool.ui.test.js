/* Count tool in the real Image Viewer dialog, in headless Chromium.
 *
 * node tests/count_tool.ui.test.js <playwright> <chrome.exe>
 * On the synthetic house, whose walls have courses every 300 mm:
 *  - C starts the tool; drag a line up the wall, move back along it to
 *    divide it, dial the count with the wheel, click to set it
 *  - Up / Down, typing a number, typed refusals, undo and redo
 *  - a tick dragged onto its course sets the spacing by hand, and Reset
 *  - calibrating the photo turns even spacing into perspective spacing,
 *    with the ticks on the courses
 *  - Set Reference on two of a count's ticks dimensions every part and the
 *    whole; Measure snaps to the ticks
 *  - select, Delete, Clear counts, per photo, tool hand-off, Esc
 */
'use strict';
var path = require('path');
var harness = require('./perspective_ui_harness.js');
var scene = require('./perspective_scene.js');
var playwright = require(process.argv[2] || 'playwright');
var CHROME = process.argv[3];

var passes = 0, fails = 0;
function check(name, cond, detail) {
    if (cond) passes++;
    else { fails++; console.log('FAIL  ' + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); }
}
function dist(p, q) { return Math.hypot(p.x - q.x, p.y - q.y); }

(async function main() {
    var t = await harness.open(playwright, CHROME, 'count');
    var page = t.page, h = t.h, cam = t.house.cam;
    function P(x, y, z) { return scene.project(cam, [x, y, z]); }
    function inspect() { return page.evaluate(function() { return window.Na__ImageViewer__Count.inspect(); }); }
    function zoom() { return page.evaluate(function() { return window.Na__ImageViewer__Core.getZoom(); }); }
    async function dragImg(a, b) {
        var sa = await h.screenOf(a), sb = await h.screenOf(b);
        await page.mouse.move(sa.x, sa.y);
        await page.mouse.down();
        await page.mouse.move(sb.x, sb.y, { steps: 14 });
        await page.mouse.up();
    }
    // Worst miss of a count's ticks from the courses up the line x, from z0.
    function tickMiss(c, x, z0) {
        var w = 0;
        c.ticks.forEach(function(q, j) { w = Math.max(w, dist(q, P(x, 0, z0 + 0.3 * j))); });
        return w;
    }
    async function dialTo(n) {
        var live = (await inspect()).live;
        await page.mouse.wheel(0, -40 * (n - live.n));
        return (await inspect()).live.n;
    }
    // Clicking at fit zoom places a point to a few image pixels.
    var TOL = 6;

    // ---------------------------------------------------------------- C starts the tool
    await page.keyboard.press('c');
    var info = await inspect();
    check('C starts the Count tool', info.active && info.bar.open, info.active);
    check('the bar says what to do first', /Drag from where the first one starts/.test(info.bar.hint), info.bar.hint);
    check('the Count button shows the tool is on', await page.$eval('#naImageViewer_btnCount', function(b) { return b.classList.contains('naImageViewer__Btn--active'); }));

    // ---------------------------------------------------------------- drag a line up the corner, then divide it
    await dragImg(P(8, 0, 0.3), P(8, 0, 4.8));            // 15 courses
    info = await inspect();
    check('dragging a line goes on to dividing it', info.phase === 'divide' && info.live && info.live.n === 1, [info.phase, info.live && info.live.n]);
    check('the bar says to move back along the line', /Move back along the line/.test(info.bar.hint), info.bar.hint);
    await h.moveImg(P(8, 0, 2.55));
    var nHalf = (await inspect()).live.n;
    await h.moveImg(P(8, 0, 1.2));
    var nFifth = (await inspect()).live.n;
    await h.moveImg(P(8, 0, 0.6));
    var nFirst = (await inspect()).live.n;
    console.log('  moving back along the line: halfway ' + nHalf + ', a fifth ' + nFifth + ', the first course ' + nFirst);
    check('halfway along makes two parts', nHalf === 2, nHalf);
    check('a fifth of the way makes five', Math.abs(nFifth - 5) <= 1, nFifth);
    check('the first course makes about fifteen', Math.abs(nFirst - 15) <= 3, nFirst);
    var z0 = await zoom();
    check('the wheel dials the count while dividing', await dialTo(15) === 15);
    check('and does not zoom meanwhile', await zoom() === z0);
    var here = await h.screenOf(P(8, 0, 0.6));
    await page.mouse.click(here.x, here.y);
    info = await inspect();
    var first = info.counts[0];
    check('a click sets the count', info.phase === null && info.counts.length === 1 && first.n === 15 && info.selected === first.id, info);
    check('without calibration the parts are even on the photo', first.spacing === 'even' && info.bar.spacing === 'Even spacing', info.bar.spacing);
    check('and the bar says how to get perspective', /calibrate the photo in Angle/.test(info.bar.hint), info.bar.hint);
    var evenMiss = tickMiss(first, 8, 0.3);
    console.log('  even spacing up the corner: ticks miss the courses by up to ' + evenMiss.toFixed(1) + ' px (courses about ' + (dist(first.a, first.b) / 15).toFixed(0) + ' px apart)');

    // ---------------------------------------------------------------- Up / Down, undo, typing
    await page.keyboard.press('ArrowUp');
    check('Up adds one', (await inspect()).counts[0].n === 16);
    await page.keyboard.press('ArrowDown');
    check('Down takes one away', (await inspect()).counts[0].n === 15);
    await page.keyboard.press('Control+z');
    check('Ctrl+Z steps the count back', (await inspect()).counts[0].n === 16);
    await page.keyboard.press('Control+y');
    check('Ctrl+Y steps it forward', (await inspect()).counts[0].n === 15);
    var meta = await h.text('#naImageViewer_meta');
    await page.keyboard.type('14');
    await page.keyboard.press('Enter');
    info = await inspect();
    check('typing a number sets it', info.counts[0].n === 14, info.counts[0].n);
    check('the digits did not fit or zoom the photo', await h.text('#naImageViewer_meta') === meta);
    await page.keyboard.type('0');
    await page.keyboard.press('Enter');
    info = await inspect();
    check('0 is refused with the fix named', /Type 1 or more/.test(info.bar.error) && info.counts[0].n === 14, info.bar.error);
    await page.fill('#naImageViewer_countInput', '14.5');
    await page.press('#naImageViewer_countInput', 'Enter');
    check('a part of one is refused', /not a whole number\. Type 14 or 15/.test((await inspect()).bar.error));
    await page.fill('#naImageViewer_countInput', '1000');
    await page.press('#naImageViewer_countInput', 'Enter');
    check('too many is refused', /up to 999/.test((await inspect()).bar.error));
    await page.fill('#naImageViewer_countInput', 'x15');
    await page.press('#naImageViewer_countInput', 'Enter');
    info = await inspect();
    check('a good number clears the error', info.counts[0].n === 15 && !info.bar.error, info.bar);

    // ---------------------------------------------------------------- a tick dragged onto its course
    first = (await inspect()).counts[0];
    await dragImg(first.ticks[7], P(8, 0, 0.3 + 0.3 * 7));
    info = await inspect();
    var manualMiss = tickMiss(info.counts[0], 8, 0.3);
    console.log('  tick 7 dragged onto its course: the ticks now miss by up to ' + manualMiss.toFixed(1) + ' px');
    check('a dragged tick sets the spacing by hand', info.counts[0].spacing === 'manual' && info.bar.spacing === 'Spacing set by hand', info.bar.spacing);
    check('and the other ticks follow onto their courses', manualMiss < TOL && manualMiss < evenMiss / 2, [manualMiss, evenMiss]);
    check('the count stays 15', info.counts[0].n === 15);
    check('Reset spacing is offered', await page.$eval('#naImageViewer_countReset', function(b) { return b.style.display !== 'none'; }));
    await page.click('#naImageViewer_countReset');
    check('Reset spacing goes back to even', (await inspect()).counts[0].spacing === 'even');
    await page.screenshot({ path: path.join(t.out, 'count_even.png') });

    // ---------------------------------------------------------------- calibrating turns even spacing into perspective
    await h.calibrate();
    info = await inspect();
    check('drawing calibration lines takes the canvas from Count', !info.active && !info.bar.open, info.active);
    check('the count is now spaced in perspective', info.counts[0].spacing === 'perspective' && info.counts[0].label === 'Blue axis', [info.counts[0].spacing, info.counts[0].label]);
    var perspMiss = tickMiss(info.counts[0], 8, 0.3);
    console.log('  after calibrating: the same ticks miss by up to ' + perspMiss.toFixed(1) + ' px (even ' + evenMiss.toFixed(1) + ' px)');
    check('and its ticks sit on the courses', perspMiss < TOL && perspMiss < evenMiss / 2, [perspMiss, evenMiss]);

    // ---------------------------------------------------------------- a new count in perspective, pointer then wheel
    await page.keyboard.press('Escape');
    await page.keyboard.press('c');
    await h.moveImg(P(4, 0, 0.3));
    await dragImg(P(4, 0, 0.3), P(4, 0, 4.8));
    info = await inspect();
    check('the new line is spaced in perspective while dividing', info.phase === 'divide' && info.live.spacing === 'perspective', info.live && info.live.spacing);
    await h.moveImg(P(4, 0, 0.6));
    nFirst = (await inspect()).live.n;
    console.log('  calibrated: the pointer on the first course reads ' + nFirst);
    check('the pointer on the first course makes about fifteen', Math.abs(nFirst - 15) <= 3, nFirst);
    check('the wheel brings it to fifteen', await dialTo(15) === 15);
    await page.keyboard.press('Enter');
    info = await inspect();
    var second = info.counts[1];
    check('Enter sets it', info.counts.length === 2 && second.n === 15 && info.phase === null, info.counts.length);
    var secondMiss = tickMiss(second, 4, 0.3);
    console.log('  15 courses up the gable in perspective: ticks miss by up to ' + secondMiss.toFixed(1) + ' px');
    check('its ticks sit on the courses', secondMiss < TOL, secondMiss);
    check('the bar names the direction', info.bar.spacing === 'In perspective: Blue axis', info.bar.spacing);

    // ---------------------------------------------------------------- dimensions from Set Reference on two ticks
    check('no dimensions before a reference', !second.dims && info.bar.dims === '', info.bar.dims);
    await page.click('#naImageViewer_btnSetRef');
    check('Set Reference takes the canvas from Count', !(await inspect()).active);
    await h.moveImg(second.ticks[0]);
    await h.clickImg(second.ticks[0]);
    await h.moveImg(second.ticks[4]);
    await h.clickImg(second.ticks[4]);
    await page.fill('#naImageViewer_refInput', '1200');
    await page.click('#naImageViewer_refOk');
    var scale = await page.evaluate(function() { return window.Na__ImageViewer__Measure.getScale(); });
    check('the reference snapped onto the two ticks', !!(scale && scale.ref && dist(scale.ref.a, second.ticks[0]) < 0.01 && dist(scale.ref.b, second.ticks[4]) < 0.01), scale && scale.ref);
    info = await inspect();
    var d2 = info.counts[1].dims, d1 = info.counts[0].dims;
    console.log('  4 courses = 1200 mm: ' + (d2 ? d2.part.toFixed(1) + ' mm each, ' + d2.overall.toFixed(1) + ' mm overall' : 'no dimensions'));
    check('each part is dimensioned', !!d2 && Math.abs(d2.part - 300) < 0.01, d2);
    check('and the whole count', !!d2 && Math.abs(d2.overall - 4500) < 0.1, d2);
    check('read along the count, in perspective', !!d2 && d2.read === 'perspective', d2 && d2.read);
    console.log('  the corner count, read flat from that reference: ' + (d1 ? d1.part.toFixed(1) + ' mm each, ' + d1.overall.toFixed(0) + ' mm overall' : 'none') + ' (true 300 / 4500)');
    // On this steeply seen wall the corner is much nearer the camera than the
    // reference, so a flat reading of it is well out: hence the bar's advice.
    check('a count away from the reference reads it flat, as Measure does', !!d1 && d1.read === 'flat', d1);

    await page.keyboard.press('c');
    var body = { x: (second.ticks[9].x + second.ticks[10].x) / 2, y: (second.ticks[9].y + second.ticks[10].y) / 2 };
    await h.clickImg(body);
    info = await inspect();
    check('clicking a count selects it', info.selected === second.id, info.selected);
    check('the bar gives each part and the whole', info.bar.dims === '300 mm each \u00b7 4500 mm overall', info.bar.dims);
    var btns = await page.evaluate(function() {
        function on(id) { return document.getElementById(id).classList.contains('naImageViewer__Btn--active'); }
        return { count: on('naImageViewer_btnCount'), ref: on('naImageViewer_btnSetRef'), measure: on('naImageViewer_btnMeasure') };
    });
    check('only Count shows as the active tool', btns.count && !btns.ref && !btns.measure, btns);
    await page.screenshot({ path: path.join(t.out, 'count_dims.png') });
    await h.clickImg({ x: (first.ticks[6].x + first.ticks[7].x) / 2, y: (first.ticks[6].y + first.ticks[7].y) / 2 });
    info = await inspect();
    check('a count read flat says how to read it in perspective', info.selected === first.id && /Set Reference on this count/.test(info.bar.hint), info.bar.hint);
    await h.clickImg(body);

    // ---------------------------------------------------------------- Measure snaps to the ticks
    await page.click('#naImageViewer_btnMeasure');
    await h.moveImg(second.ticks[5], 3, 2);
    var marker = await page.evaluate(function() { var m = window.Na__ImageViewer__Core.getSnapMarker(); return m && { kind: m.kind, label: m.label }; });
    check('Measure snaps to a count tick', !!marker && marker.kind === 'division' && marker.label === 'Tick 5', marker);
    await page.keyboard.press('Escape');
    check('the counts stay on the photo under another tool', (await inspect()).counts.length === 2);

    // ---------------------------------------------------------------- Delete, Clear, undo
    await page.keyboard.press('c');
    await h.clickImg(body);
    await page.keyboard.press('Delete');
    check('Delete removes the selected count', (await inspect()).counts.length === 1);
    await page.keyboard.press('Control+z');
    check('Ctrl+Z brings it back', (await inspect()).counts.length === 2);
    await page.click('#naImageViewer_countClear');
    check('Clear counts removes them all', (await inspect()).counts.length === 0);
    await page.keyboard.press('Control+z');
    check('and Ctrl+Z restores them', (await inspect()).counts.length === 2);

    // ---------------------------------------------------------------- per photo
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 1008; });
    check('the next photo has no counts', (await inspect()).counts.length === 0);
    await page.keyboard.press('ArrowLeft');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 4032; });
    check('coming back shows this photo\'s counts', (await inspect()).counts.length === 2);

    // ---------------------------------------------------------------- the wheel zooms when not dividing; Esc steps back
    var zBefore = await zoom();
    var mid = await h.screenOf(P(6, 0, 3));
    await page.mouse.move(mid.x, mid.y);
    await page.mouse.wheel(0, -100);
    check('otherwise the wheel zooms as usual', await zoom() !== zBefore);
    await page.click('#naImageViewer_btnFit');
    await h.clickImg(P(6, 0, 1));
    info = await inspect();
    check('a click on the photo starts a line by clicks', info.phase === 'draw', info.phase);
    await page.keyboard.press('Escape');
    check('Esc drops the unfinished line', (await inspect()).phase === null && (await inspect()).counts.length === 2);
    await page.keyboard.press('Escape');
    check('Esc again leaves the tool', !(await inspect()).active);
    await page.keyboard.press('c');
    check('C starts it again', (await inspect()).active);
    await page.keyboard.press('c');
    check('and C stops it', !(await inspect()).active);

    check('no page errors', t.errors.length === 0, t.errors);
    await t.browser.close();
    console.log('\n' + passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
