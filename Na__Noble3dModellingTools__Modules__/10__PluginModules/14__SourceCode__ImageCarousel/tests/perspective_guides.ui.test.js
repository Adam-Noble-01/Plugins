/* Perspective guides in the real Image Viewer dialog, in headless Chromium.
 *
 * node tests/perspective_guides.ui.test.js <playwright> <chrome.exe>
 * On the synthetic house (true pitch 47.5 degrees), after calibrating:
 *  - a red guide through one window head runs through the other window heads
 *  - the arrow keys lock an axis (and do not change photo); one click places
 *  - a red and a blue guide cross on the window head, and both the guide
 *    tool and the Measure tool snap to that intersection
 *  - a 47.5 degree guide from the eaves runs to the apex
 *  - a guide parallel to the measured pitch keeps its slope lower down
 *  - free guides, selection, Delete, Show guides, Clear, undo and redo
 */
'use strict';
var path = require('path');
var harness = require('./perspective_ui_harness.js');
var playwright = require(process.argv[2] || 'playwright');
var CHROME = process.argv[3];

var passes = 0, fails = 0;
function check(name, cond, detail) {
    if (cond) passes++;
    else { fails++; console.log('FAIL  ' + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); }
}
function guideById(info, id) { return info.guides.filter(function(g) { return g.id === id; })[0]; }
function newest(info) { return info.guides[info.guides.length - 1]; }

(async function main() {
    var t = await harness.open(playwright, CHROME, 'guides');
    var page = t.page, h = t.h, P = t.house.points;
    await h.calibrate();
    check('calibrated', /Calibrated/.test(await h.text('#naImageViewer_perspStatus')));
    // Placing points at fit zoom is quantised to about 4 image px per screen
    // pixel, so a guide is expected within a few pixels of each target.
    var TOL = 6;

    // ---------------------------------------------------------------- T opens the Guide tool
    await page.mouse.move(800, 950);
    await page.keyboard.press('t');
    var info = await h.inspect();
    check('T starts the Guide tool', info.mode === 'guide' && info.guideAxis === 'auto', info.mode);

    // ---------------------------------------------------------------- red guide by inference: window heads line up
    await h.clickImg(P.headL1);
    await h.moveImg(P.headR2);
    info = await h.inspect();
    check('moving along the wall reads the red axis', info.inferred === 'Red axis', info.inferred);
    await h.clickImg(P.headR2);
    info = await h.inspect();
    var red = newest(info);
    check('one red guide placed', info.guideCount === 1 && red && red.dir === 'x', info);
    var dHeads = [P.headL2, P.headR1, P.headR2].map(function(q) { return harness.distToSeg(q, red.seg); });
    console.log('  red guide through the left window head: other heads miss it by ' + dHeads.map(function(d) { return d.toFixed(1); }).join(', ') + ' px');
    check('the red guide runs through every window head on that wall', dHeads.every(function(d) { return d < TOL; }), dHeads);
    check('but not along the side wall, which is green', harness.distToSeg(P.sideHead2, red.seg) > 40, harness.distToSeg(P.sideHead2, red.seg));

    // ---------------------------------------------------------------- arrow locks: blue in one click, photo unchanged
    await page.keyboard.press('ArrowUp');
    info = await h.inspect();
    var meta = await h.text('#naImageViewer_meta');
    check('ArrowUp locks blue and keeps the photo', info.guideAxis === 'z' && /^1\/2/.test(meta), [info.guideAxis, meta]);
    await h.clickImg(P.sillR2);
    info = await h.inspect();
    var blue = newest(info);
    check('one click places a blue guide', info.guideCount === 2 && blue.dir === 'z', info.guideCount);
    var dPlumb = harness.distToSeg(P.headR2, blue.seg);
    console.log('  blue guide through the sill corner: head corner above misses it by ' + dPlumb.toFixed(1) + ' px');
    check('the blue guide runs straight up to the head', dPlumb < TOL, dPlumb);
    await page.keyboard.press('ArrowUp');
    check('ArrowUp again unlocks', (await h.inspect()).guideAxis === 'auto');

    // ---------------------------------------------------------------- green guide along the side wall
    await page.keyboard.press('ArrowLeft');
    await h.clickImg(P.sideHead1);
    info = await h.inspect();
    var green = newest(info);
    var dSide = harness.distToSeg(P.sideHead2, green.seg);
    check('a green guide runs along the side wall at that height', green.dir === 'y' && dSide < TOL, dSide);
    await page.keyboard.press('ArrowDown');
    check('ArrowDown returns to auto', (await h.inspect()).guideAxis === 'auto');

    // ---------------------------------------------------------------- intersection snapping
    var snap = await h.snapAt(P.headR2, 4, 3);
    var snapMiss = snap ? Math.hypot(snap.img.x - P.headR2.x, snap.img.y - P.headR2.y) : null;
    check('the red and blue guides cross on the window head, and it snaps there', snap && snap.kind === 'intersection' && snapMiss < TOL, [snap && snap.kind, snapMiss]);
    var onGuide = await h.snapAt({ x: (red.seg.a.x * 0.3 + red.seg.b.x * 0.7), y: (red.seg.a.y * 0.3 + red.seg.b.y * 0.7) }, 0, 4);
    check('a point near a guide snaps onto it', onGuide && (onGuide.kind === 'guide' || onGuide.kind === 'intersection'), onGuide && onGuide.kind);

    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnMeasure');
    await h.moveImg(P.headR2, 4, 3);
    var marker = await page.evaluate(function() { var m = window.Na__ImageViewer__Core.getSnapMarker(); return m && { kind: m.kind, img: m.img }; });
    check('the Measure tool snaps to the guide intersection', marker && marker.kind === 'intersection', marker);
    await h.clickImg(P.headR2, 4, 3);
    await h.moveImg(P.sillR2, -3, 2);
    await h.clickImg(P.sillR2, -3, 2);
    await page.keyboard.press('Escape');
    var undoLive = await page.$eval('#naImageViewer_btnUndo', function(b) { return !b.disabled; });
    check('a snapped dimension was placed', undoLive);
    await page.keyboard.press('Control+z');
    info = await h.inspect();
    check('Ctrl+Z takes the dimension back, guides stay', info.guideCount === 3, info.guideCount);

    // ---------------------------------------------------------------- a pitch guide hits the apex
    await page.fill('#naImageViewer_perspGuideAngle', '95');
    await page.press('#naImageViewer_perspGuideAngle', 'Enter');
    check('an impossible pitch is refused with the fix named', /not a slope/.test(await h.text('#naImageViewer_perspGuideHint')));
    await page.fill('#naImageViewer_perspGuideAngle', '47.5');
    await page.press('#naImageViewer_perspGuideAngle', 'Enter');
    check('a typed pitch is taken', (await h.inspect()).guideAngle === 47.5);
    await page.mouse.move(800, 950);
    await page.keyboard.press('t');
    await h.clickImg(P.eaves);
    await h.moveImg(P.apexPt);
    info = await h.inspect();
    check('moving up the verge reads the typed pitch', info.inferred === '47.5° on Red wall', info.inferred);
    await h.clickImg(P.apexPt);
    info = await h.inspect();
    var tilt = newest(info);
    var dApex = harness.distToSeg(P.apexPt, tilt.seg);
    console.log('  47.5 degree guide from the eaves corner: apex misses it by ' + dApex.toFixed(1) + ' px');
    check('a guide at the true pitch runs to the apex', tilt.dir === 'tilt' && dApex < TOL, dApex);

    // ---------------------------------------------------------------- parallel to a measured pitch
    await page.fill('#naImageViewer_perspGuideAngle', '');
    await page.press('#naImageViewer_perspGuideAngle', 'Enter');
    await page.click('#naImageViewer_perspPitch');
    await h.clickImg(P.eaves);
    await h.clickImg(P.apexPt);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    await page.keyboard.press('t');
    await h.clickImg(P.lowEaves);
    await h.moveImg(P.lowVerge);
    info = await h.inspect();
    check('moving along the slope reads "Parallel to Pitch 1"', info.inferred === 'Parallel to Pitch 1', info.inferred);
    await h.clickImg(P.lowVerge);
    info = await h.inspect();
    var par = newest(info);
    var dPar = harness.distToSeg(P.lowVerge, par.seg);
    check('the parallel guide keeps the slope lower down the wall', par.dir === 'par' && dPar < TOL, dPar);

    // ---------------------------------------------------------------- free guide
    var anchor = P.sky, freeMade = false;
    await h.clickImg(anchor);
    for (var a = 0; a < 360 && !freeMade; a += 7) {
        var target = { x: anchor.x + 380 * Math.cos(a * Math.PI / 180), y: anchor.y + 380 * Math.sin(a * Math.PI / 180) };
        if (Math.abs(target.x) > 1990 || Math.abs(target.y) > 1490) continue;
        await h.moveImg(target);
        if ((await h.inspect()).inferred === null) { await h.clickImg(target); freeMade = true; }
    }
    info = await h.inspect();
    check('a direction off every axis makes a free guide', freeMade && newest(info).dir === 'free', newest(info) && newest(info).dir);
    var count = info.guideCount;

    // ---------------------------------------------------------------- undo / redo, select, delete
    await page.keyboard.press('Control+z');
    check('Ctrl+Z removes the last guide', (await h.inspect()).guideCount === count - 1);
    await page.keyboard.press('Control+y');
    check('Ctrl+Y brings it back', (await h.inspect()).guideCount === count);
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    check('Esc leaves the Guide tool', (await h.inspect()).mode === null);
    var onRed = { x: red.seg.a.x * 0.12 + red.seg.b.x * 0.88, y: red.seg.a.y * 0.12 + red.seg.b.y * 0.88 };
    await h.clickImg(onRed);
    info = await h.inspect();
    check('clicking a guide selects it', info.selected && info.selected.kind === 'guide' && info.selected.id === red.id, info.selected);
    await page.screenshot({ path: path.join(t.out, 'guides_ui.png') });
    await page.keyboard.press('Delete');
    info = await h.inspect();
    check('Delete removes the selected guide', info.guideCount === count - 1 && !guideById(info, red.id), info.guideCount);

    // ---------------------------------------------------------------- show / hide, clear
    await page.uncheck('#naImageViewer_perspShowGuides');
    info = await h.inspect();
    var hiddenSnap = await h.snapAt(P.headR2, 0, 30);
    check('Show guides off hides them and stops snapping to them', info.guides.length === 0 && (!hiddenSnap || hiddenSnap.kind === 'endpoint'), [info.guides.length, hiddenSnap && hiddenSnap.kind]);
    await page.check('#naImageViewer_perspShowGuides');
    check('and on brings them back', (await h.inspect()).guides.length === count - 1);
    await page.click('#naImageViewer_perspClearGuides');
    check('Clear guides removes them all', (await h.inspect()).guideCount === 0);
    await page.keyboard.press('Control+z');
    check('and Ctrl+Z restores them', (await h.inspect()).guideCount === count - 1);

    // ---------------------------------------------------------------- per photo
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 1008; });
    check('the next photo has no guides', (await h.inspect()).guideCount === 0);
    await page.keyboard.press('ArrowLeft');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 4032; });
    check('coming back shows this photo\'s guides', (await h.inspect()).guideCount === count - 1);
    await page.click('#naImageViewer_perspClose');
    check('guides stay on the photo with the panel closed', (await h.inspect()).guides.length === count - 1);
    await page.screenshot({ path: path.join(t.out, 'guides_closed.png') });

    check('no page errors', t.errors.length === 0, t.errors);
    await t.browser.close();
    console.log('\n' + passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
