/* The thumbnail strip folds away, in headless Chromium.
 *
 * node tests/thumbs_fold.ui.test.js <playwright> <chrome.exe> [folder for screenshots]
 *  - open by default; the tab folds it and the photo takes the room
 *  - the tab unfolds it again; the choice is remembered on the next open
 *  - the canvas keeps the photo's pixels square through a fold
 *  - the strip's scrollbar is thin, without arrows, and clear unless the
 *    pointer is over the strip or it is scrolling
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
    var t = await harness.open(playwright, CHROME, 'thumbs_fold');
    var page = t.page;
    function state() {
        return page.evaluate(function() {
            var thumbs = document.getElementById('naImageViewer_thumbs'), btn = document.getElementById('naImageViewer_thumbsFold');
            var c = window.Na__ImageViewer__Core.getCanvas(), r = c.getBoundingClientRect();
            return { thumbsShown: thumbs.offsetParent !== null, expanded: btn.getAttribute('aria-expanded'), label: btn.title,
                     canvasLeft: Math.round(r.left), canvasW: Math.round(r.width), pxW: c.width, tabW: Math.round(btn.getBoundingClientRect().width) };
        });
    }

    // Plenty of photos, so the strip scrolls
    await page.evaluate(function() {
        var list = window.Na__ImageViewer__Core.getImages(), many = [];
        for (var i = 0; i < 12; i++) many.push(list[i % list.length] + (i > 1 ? '?copy=' + i : ''));
        window.SKP_onFolderChosen(many);
    });
    await page.waitForTimeout(600);

    var open = await state();
    check('open by default', open.thumbsShown && open.expanded === 'true' && open.label === 'Hide the thumbnails', open);
    check('the tab is a slim strip', open.tabW >= 10 && open.tabW <= 16, open.tabW);
    var scrolls = await page.$eval('#naImageViewer_thumbs', function(el) { return el.scrollHeight > el.clientHeight; });
    check('the strip scrolls with this many photos', scrolls);
    var barW = await page.$eval('#naImageViewer_thumbs', function(el) { return el.offsetWidth - el.clientWidth - 2; });   // less the 1 px border, each side counted once
    check('the scrollbar is thin', barW <= 7, barW);

    function inUse() { return page.$eval('#naImageViewer_thumbs', function(el) { return el.classList.contains('naImageViewer__Thumbs--inUse'); }); }
    await page.mouse.move(900, 500);
    await page.waitForTimeout(100);
    check('the scrollbar is clear while the strip is not in use', !(await inUse()));
    await page.mouse.move(100, 300);
    check('it shows with the pointer over the strip', await inUse());
    await page.mouse.wheel(0, 300);
    await page.mouse.move(900, 500);
    check('and while it is still scrolling', await inUse());
    await page.waitForTimeout(1200);
    check('then it goes', !(await inUse()));

    if (SHOTS) {
        await page.mouse.move(900, 500);
        await page.waitForTimeout(150);
        await page.screenshot({ path: path.join(SHOTS, 'thumbs_idle.png'), clip: { x: 0, y: 60, width: 260, height: 500 } });
        await page.mouse.move(100, 300);
        await page.waitForTimeout(150);
        await page.screenshot({ path: path.join(SHOTS, 'thumbs_hover.png'), clip: { x: 0, y: 60, width: 260, height: 500 } });
    }

    await page.click('#naImageViewer_thumbsFold');
    await page.waitForTimeout(150);
    var folded = await state();
    check('the tab folds the strip away', !folded.thumbsShown && folded.expanded === 'false' && folded.label === 'Show the thumbnails', folded);
    check('the photo takes the room', folded.canvasW > open.canvasW + 150 && folded.canvasLeft < open.canvasLeft, [open, folded]);
    check('the canvas follows its new size', folded.pxW === folded.canvasW, folded);
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'thumbs_folded.png'), clip: { x: 0, y: 0, width: 800, height: 400 } });

    // Remembered on the next open of the dialog
    await page.reload();
    await page.waitForTimeout(400);
    var again = await state();
    check('folded is remembered next time', !again.thumbsShown && again.expanded === 'false', again);
    await page.click('#naImageViewer_thumbsFold');
    await page.waitForTimeout(150);
    var unfolded = await state();
    check('the tab opens it again', unfolded.thumbsShown && unfolded.expanded === 'true', unfolded);
    await page.reload();
    await page.waitForTimeout(400);
    check('open is remembered too', (await state()).thumbsShown);

    check('no page errors', t.errors.length === 0, t.errors);
    await t.browser.close();
    console.log(passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
