/* Counts and Angle work kept in the model: the dialog side, in headless Chromium.
 *
 * node tests/tool_state_persist.ui.test.js <playwright> <chrome.exe>
 *  - calibrating the photo (Angle lines) and setting a count each reach Ruby
 *    (tool_state_save) a moment later, in photo pixels from the top-left
 *  - a change is sent before another photo is shown; nothing is sent twice
 *  - a fresh dialog given the model's state shows the same count, spaced in
 *    the same perspective (the Angle lines solved again), ticks within 0.01 px
 *  - a quarter-size copy takes it scaled, a hand-set vanishing point included
 *  - undo back to nothing removes it; loading sends nothing back
 * Leaves the payloads in tests/out/tool_state_payload.json for
 *   python tests/run_ruby_checks.py tests/tool_state_persistence.rb.test
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

function sends(page, tool) {
    return page.evaluate(function(tool) {
        return window.__calls.filter(function(c) { return c[0] === 'tool_state_save'; })
            .map(function(c) { return JSON.parse(c[1]); })
            .filter(function(p) { return !tool || p.tool === tool; });
    }, tool || null);
}
function counts(page) { return page.evaluate(function() { return window.Na__ImageViewer__Count.inspect().counts; }); }
function worstTick(a, b) {
    var w = 0;
    a.forEach(function(c, i) {
        c.ticks.forEach(function(t, j) { var u = b[i].ticks[j]; w = Math.max(w, Math.abs(t.x - u.x), Math.abs(t.y - u.y)); });
    });
    return w;
}

(async function main() {
    // ---- 1. calibrate and count, watch what goes to Ruby
    var t = await harness.open(playwright, CHROME, 'tool_state');
    var page = t.page, h = t.h, house = t.house;
    await page.evaluate(function() { window.__calls.length = 0; });
    await h.calibrate();
    await page.waitForTimeout(700);
    var angle = await sends(page, 'angle');
    check('the Angle lines reach Ruby', angle.length >= 1 && angle[angle.length - 1].state.lines.length >= 6, angle.length && angle[angle.length - 1].state.lines.length);
    var last = angle[angle.length - 1];
    check('with the photo and its size', /tool_state_house\.png$/.test(last.path) && last.w === 4032 && last.h === 3024, [last.path, last.w, last.h]);
    var line0 = last.state.lines[0];
    var src0  = house.key.verticals[0];
    check('points in photo pixels from the top-left', Math.abs(line0.a.x - (src0[0].x + 2016)) < 4 && Math.abs(line0.a.y - (src0[0].y + 1512)) < 4, [line0.a, src0[0]]);

    await page.keyboard.press('Escape');
    await page.keyboard.press('c');
    var v = house.key.verticals[0];
    await h.clickImg(v[0]);
    await h.clickImg(v[1]);
    await page.keyboard.type('12');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(700);
    var cs = await sends(page, 'count');
    check('the count reaches Ruby once it is set', cs.length >= 1 && cs[cs.length - 1].state.counts.length === 1 && cs[cs.length - 1].state.counts[0].n === 12, cs.map(function(p) { return p.state && p.state.counts.length; }));
    var nBefore = (await sends(page)).length;
    await page.waitForTimeout(700);
    check('nothing more is sent while nothing changes', (await sends(page)).length === nBefore);

    var before = await counts(page);
    check('the count is spaced in perspective', before.length === 1 && before[0].spacing === 'perspective', before[0] && before[0].spacing);

    // A change just before moving on is sent at once
    await page.keyboard.press('ArrowUp');           // 13, with the count still selected
    await page.keyboard.press('ArrowRight');        // the next photo, straight away
    await page.waitForTimeout(100);
    cs = await sends(page, 'count');
    check('a change is sent before another photo is shown', cs[cs.length - 1].state.counts[0].n === 13, cs[cs.length - 1].state.counts[0].n);
    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(700);
    before = await counts(page);
    var payload = { count: (await sends(page, 'count')).pop(), angle: (await sends(page, 'angle')).pop() };
    check('kept as 13', payload.count.state.counts[0].n === 13 && before[0].n === 13, [payload.count.state.counts[0].n, before[0].n]);
    var N = 13;
    fs.writeFileSync(path.join(harness.OUT, 'tool_state_payload.json'), JSON.stringify(payload));
    check('no page errors (first dialog)', t.errors.length === 0, t.errors);
    await t.browser.close();

    // ---- 2. a fresh dialog, given what the model holds
    var t2 = await harness.open(playwright, CHROME, 'tool_state_reopen');
    page = t2.page;
    var images = await page.evaluate(function() { return window.Na__ImageViewer__Core.getImages(); });
    function stored(p) { return { w: p.w, h: p.h, state: p.state }; }
    // the quarter-size copy: the same count, with a hand-set vanishing point
    var small = JSON.parse(JSON.stringify(payload.count.state));
    var a = small.counts[0].a, b = small.counts[0].b;
    var vpTL = { x: (a.x + (b.x - a.x) * 3) * 2, y: (a.y + (b.y - a.y) * 3) * 2, w: 2 };      // homogeneous, 3x along the line
    small.counts[0].vp = vpTL;
    var map = { count: {}, angle: {} };
    map.count[images[0]] = stored(payload.count);
    map.angle[images[0]] = stored(payload.angle);
    map.count[images[1]] = { w: 4032, h: 3024, state: small };
    await page.evaluate(function() { window.__calls.length = 0; });
    await page.evaluate(function(m) { window.Na__ImageViewer__OnToolStateLoaded(m); }, map);
    await page.waitForTimeout(800);

    var after = await counts(page);
    check('the count comes back', after.length === 1 && after[0].n === N && after[0].kind === before[0].kind, after);
    check('spaced in the same perspective (the Angle lines solved again)', after[0] && after[0].spacing === 'perspective' && after[0].label === before[0].label, after[0] && [after[0].spacing, after[0].label]);
    check('its ticks within 0.01 px', after.length === 1 && worstTick(before, after) < 0.01, worstTick(before, after));
    check('loading sends nothing back', (await sends(page)).length === 0, (await sends(page)).map(function(p) { return p.tool; }));

    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(800);
    var q = await counts(page);
    check('the quarter-size copy takes the count', q.length === 1 && q[0].n === N && q[0].manual, q[0] && [q[0].n, q[0].manual]);
    if (q.length) {
        var ea = { x: (a.x / 4) - 504, y: (a.y / 4) - 378 }, eb = { x: (b.x / 4) - 504, y: (b.y / 4) - 378 };
        check('its ends scaled to the copy', Math.abs(q[0].a.x - ea.x) < 0.01 && Math.abs(q[0].b.y - eb.y) < 0.01, [q[0].a, ea, q[0].b, eb]);
        // A vanishing point 3x along the line: the ticks crowd toward it, the same at any size.
        var ta = q[0].ticks, L = Math.hypot(eb.x - ea.x, eb.y - ea.y);
        var first = Math.hypot(ta[1].x - ta[0].x, ta[1].y - ta[0].y), lastGap = Math.hypot(ta[N].x - ta[N - 1].x, ta[N].y - ta[N - 1].y);
        check('the hand-set vanishing point came through (spans shrink toward it)', first > lastGap * 1.2 && Math.abs(Math.hypot(ta[N].x - ta[0].x, ta[N].y - ta[0].y) - L) < 0.01, [first, lastGap]);
    }
    check('still nothing sent back', (await sends(page)).length === 0);

    // Undo back to nothing removes it from the model
    await page.keyboard.press('ArrowLeft');
    await page.waitForTimeout(500);
    await page.keyboard.press('c');
    await page.evaluate(function() { window.__calls.length = 0; });
    var sel = after[0];
    // the count is selected by a click on its line
    var mid = { x: (sel.a.x + sel.b.x) / 2, y: (sel.a.y + sel.b.y) / 2 };
    var s = await page.evaluate(function(p) { var c = window.Na__ImageViewer__Core, q = c.imgToScreen(p), r = c.getCanvas().getBoundingClientRect(), k = c.getRatio(); return { x: r.left + q.x / k, y: r.top + q.y / k }; }, mid);
    await page.mouse.click(s.x, s.y);
    await page.keyboard.press('Delete');
    await page.waitForTimeout(700);
    var gone = await sends(page, 'count');
    check('deleting the last count sends an empty state', gone.length === 1 && gone[0].state === null, gone);
    check('the Angle work is not touched', (await sends(page, 'angle')).length === 0);
    check('no page errors (second dialog)', t2.errors.length === 0, t2.errors);
    await t2.browser.close();

    console.log(passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
