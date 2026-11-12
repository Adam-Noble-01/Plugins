/* The Image Viewer's top bar in the real dialog, in headless Chromium.
 *
 * node tests/toolbar.ui.test.js <playwright> <chrome.exe> [folder for screenshots]
 *  - at every window size and in every row, every visible button is wholly on
 *    screen, with a picture and a name to read or hover over
 *  - every tool that was on the old flat bar can still be reached
 *  - home, a toolset, Back, Esc; a set stays open after a press
 *  - running tools: the set shows it holds one, a shortcut opens the tool's set,
 *    leaving a set does not stop its tool, Esc stops the tool before the set
 *  - icons turn white on a button that is on
 *  - the folder button leads only until there are photos
 *  - the canvas keeps its shape when the bar wraps
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

// Sizes: portrait screens, a half-width window, the dialog's smallest, its default, a wide one.
var LABELS_ABOVE = 980;   // the narrow-window breakpoint in Styles.css: names show above it
var SIZES = [[1080, 1920], [981, 1300], [980, 1300], [900, 1400], [861, 1300], [860, 1300], [720, 1280], [640, 600], [1200, 800], [1920, 1080]];
var ROWS = [null, 'view', 'measure'];
var EVERY_TOOL = {
    home: ['btnChoose', 'btnMarkup'],
    view: ['btnFit', 'btnFill', 'btn100', 'btnZoomIn', 'btnZoomOut', 'btnRotateL', 'btnRotateR', 'btnFull'],
    measure: ['btnMeasure', 'btnSetRef', 'btnCount', 'btnCountPoints', 'btnPerspective', 'btnProtractor', 'btnSelect', 'btnDeleteSelected', 'btnClearDims'],
    pins: ['btnPrev', 'btnNext', 'btnUndo', 'btnRedo']
};

(async function main() {
    var t = await harness.open(playwright, CHROME, 'toolbar');
    var page = t.page;

    function menu() { return page.evaluate(function() { return window.Na__ImageViewer__ToolbarMenu.inspect(); }); }
    function visible(id) { return page.$eval('#naImageViewer_' + id, function(b) { return b.offsetParent !== null; }); }
    function isOn(id) { return page.$eval('#naImageViewer_' + id, function(b) { return b.classList.contains('naImageViewer__Btn--active'); }); }
    async function settle() { await page.waitForTimeout(220); }
    async function home() { await page.evaluate(function() { window.Na__ImageViewer__ToolbarMenu.home(); }); }
    // Every visible toolbar button: on screen, clear of the others, with a picture and a name.
    function audit() {
        return page.evaluate(function() {
            var W = document.documentElement.clientWidth, bar = document.getElementById('naImageViewer_toolbar'), bad = [], boxes = [];
            bar.querySelectorAll('button').forEach(function(b) {
                if (b.offsetParent === null) return;
                var r = b.getBoundingClientRect(), name = b.getAttribute('aria-label') || b.id;
                boxes.push({ name: name, r: r });
                if (r.left < 0 || r.right > W) bad.push(name + ' off screen');
                if (r.bottom > bar.getBoundingClientRect().bottom) bad.push(name + ' below the bar');
                var icon = b.querySelector('.naImageViewer__TileIcon svg');
                if (!icon) bad.push(name + ' has no picture');
                else {
                    var q = icon.getBoundingClientRect();
                    if (q.width < 20 || q.height < 20) bad.push(name + ' picture too small');
                }
                if (!b.getAttribute('aria-label') || !b.title) bad.push(name + ' has no name');
                if (r.width < 28 || r.height < 28) bad.push(name + ' too small to press');
            });
            boxes.forEach(function(a, i) {
                boxes.slice(i + 1).forEach(function(b) {
                    if (a.r.left < b.r.right && b.r.left < a.r.right && a.r.top < b.r.bottom && b.r.top < a.r.bottom) bad.push(a.name + ' overlaps ' + b.name);
                });
            });
            return { bad: bad, count: boxes.length, height: bar.offsetHeight, pageScrolls: document.documentElement.scrollWidth > W, labels: !!Array.prototype.some.call(bar.querySelectorAll('.naImageViewer__TileLabel'), function(l) { return l.offsetParent !== null; }) };
        });
    }

    // ------------------------------------------------------------ on opening
    // Before any resize: the viewer sizes its canvas once at start, so the bar must already be its full height.
    var opened = await page.$eval('#naImageViewer_canvas', function(c) { var r = c.getBoundingClientRect(); return { buffer: [c.width, c.height], box: [r.width, r.height] }; });
    check('the photo opens unstretched: the canvas buffer fits its box', opened.buffer[0] === Math.floor(opened.box[0]) && opened.buffer[1] === Math.floor(opened.box[1]), opened);

    // ------------------------------------------------------------ all sizes, all rows
    for (var s = 0; s < SIZES.length; s++) {
        await page.setViewportSize({ width: SIZES[s][0], height: SIZES[s][1] });
        for (var r = 0; r < ROWS.length; r++) {
            await page.evaluate(function(n) { window.Na__ImageViewer__ToolbarMenu.open(n); }, ROWS[r]);
            await settle();
            var tag = SIZES[s].join('x') + ' ' + (ROWS[r] || 'home');
            var a = await audit();
            check(tag + ': every button is whole, separate and named', a.bad.length === 0, a.bad);
            check(tag + ': the page does not scroll sideways', !a.pageScrolls);
            check(tag + ': the bar is not more than two lines', a.height <= 100, a.height);
            if (SIZES[s][0] > LABELS_ABOVE) check(tag + ': with the names showing it fits on one line', a.height <= 60, a.height);
            check(tag + ': names show only where there is room', a.labels === (SIZES[s][0] > LABELS_ABOVE), a.labels);
            if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'bar_' + SIZES[s].join('x') + '_' + (ROWS[r] || 'home') + '.png'), clip: { x: 0, y: 0, width: SIZES[s][0], height: Math.min(a.height + 40, SIZES[s][1]) } });
        }
    }
    await page.setViewportSize({ width: 900, height: 1400 });

    // ------------------------------------------------------------ what shows where
    await home(); await settle();
    var flat = [].concat(EVERY_TOOL.home, EVERY_TOOL.view, EVERY_TOOL.measure, EVERY_TOOL.pins);
    check('all 21 of the old bar\'s tools, Count Points and the Protractor exist', flat.length === 23 && (await page.evaluate(function(ids) { return ids.every(function(i) { return !!document.getElementById('naImageViewer_' + i); }); }, flat)));
    var i;
    for (i = 0; i < EVERY_TOOL.home.length; i++) check(EVERY_TOOL.home[i] + ' is on the home row', await visible(EVERY_TOOL.home[i]));
    for (i = 0; i < EVERY_TOOL.view.length; i++) check(EVERY_TOOL.view[i] + ' is nested at home', !(await visible(EVERY_TOOL.view[i])));
    for (i = 0; i < EVERY_TOOL.measure.length; i++) check(EVERY_TOOL.measure[i] + ' is nested at home', !(await visible(EVERY_TOOL.measure[i])));
    for (i = 0; i < EVERY_TOOL.pins.length; i++) check(EVERY_TOOL.pins[i] + ' is pinned at home', await visible(EVERY_TOOL.pins[i]));

    await page.click('[data-toolset-open="view"]');
    check('the View button opens the View set', (await menu()).open === 'view');
    for (i = 0; i < EVERY_TOOL.view.length; i++) check(EVERY_TOOL.view[i] + ' shows in the View set', await visible(EVERY_TOOL.view[i]));
    check('the home row has gone', !(await visible('btnChoose')) && !(await visible('btnMarkup')));
    for (i = 0; i < EVERY_TOOL.pins.length; i++) check(EVERY_TOOL.pins[i] + ' stays pinned in a set', await visible(EVERY_TOOL.pins[i]));

    var zoom0 = await page.evaluate(function() { return window.Na__ImageViewer__Core.getZoom(); });
    await page.click('#naImageViewer_btnZoomIn');
    check('a nested tool still does its job', (await page.evaluate(function() { return window.Na__ImageViewer__Core.getZoom(); })) > zoom0);
    check('the set stays open after a press', (await menu()).open === 'view');

    await page.click('[data-toolset="view"] [data-toolset-back]');
    check('Back returns home', (await menu()).open === null && await visible('btnMarkup'));

    await page.click('[data-toolset-open="measure"]');
    check('the Measure button opens the Measure set', (await menu()).open === 'measure');
    for (i = 0; i < EVERY_TOOL.measure.length; i++) check(EVERY_TOOL.measure[i] + ' shows in the Measure set', await visible(EVERY_TOOL.measure[i]));
    await page.keyboard.press('Escape');
    check('Esc with no tool on returns home', (await menu()).open === null);

    // ------------------------------------------------------------ running tools
    await page.keyboard.press('c');
    await page.waitForTimeout(30);
    check('the Count shortcut opens the Measure set', (await menu()).open === 'measure');
    check('Count shows it is on', await isOn('btnCount'));
    var ink = await page.$eval('#naImageViewer_btnCount svg', function(el) { return getComputedStyle(el).stroke; });
    check('the icon of a tool that is on turns white', ink === 'rgb(255, 255, 255)', ink);
    var inkOff = await page.$eval('#naImageViewer_btnSelect svg', function(el) { return getComputedStyle(el).stroke; });
    check('a tool that is off keeps the house ink', inkOff === 'rgb(23, 43, 58)', inkOff);

    await page.click('[data-toolset="measure"] [data-toolset-back]');
    check('leaving the set does not stop the tool', await isOn('btnCount'));
    check('and home says the Measure set holds a running tool', (await menu()).holding.join() === 'measure');
    await page.click('[data-toolset-open="view"]');
    await page.click('#naImageViewer_btnFit');
    check('another set can be used while a tool runs', (await menu()).open === 'view' && await isOn('btnCount'));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(30);
    check('Esc stops the tool and leaves the set open', !(await isOn('btnCount')) && (await menu()).open === 'view');
    check('home no longer shows a running tool', (await menu()).holding.length === 0);
    await page.keyboard.press('Escape');
    check('a second Esc returns home', (await menu()).open === null);

    await page.keyboard.press('Shift+C');
    await page.waitForTimeout(30);
    check('the Count Points shortcut opens the Measure set too', (await menu()).open === 'measure' && await isOn('btnCountPoints'));
    check('only its button is on', !(await isOn('btnCount')));
    await page.click('#naImageViewer_btnCount');
    await page.waitForTimeout(30);
    check('the other count button takes over', await isOn('btnCount') && !(await isOn('btnCountPoints')));
    await page.keyboard.press('Escape');
    await page.waitForTimeout(30);
    check('Esc stops counting', !(await isOn('btnCount')) && !(await isOn('btnCountPoints')));
    await page.keyboard.press('Escape');

    await page.click('#naImageViewer_btnMarkup');
    await page.waitForTimeout(30);
    check('Markup runs straight from the home row', await isOn('btnMarkup') && (await menu()).open === null);
    check('its floating toolbar still opens', (await page.evaluate(function() { return window.Na__ImageViewer__Markup.inspect().bar.open; })));
    await page.click('#naImageViewer_btnMarkup');

    await page.click('#naImageViewer_btnPerspective');
    await page.waitForTimeout(60);
    check('Angle opens its panel from the Measure set', await page.$eval('#naImageViewer_perspPanel', function(p) { return p.offsetWidth > 0; }));
    await page.setViewportSize({ width: 640, height: 900 });
    await settle();
    if (SHOTS) await page.screenshot({ path: path.join(SHOTS, 'angle_640x900.png') });
    check('at the smallest window the canvas keeps a usable width beside the panel', await page.$eval('#naImageViewer_canvas', function(c) { return c.getBoundingClientRect().width >= 200; }));
    await page.setViewportSize({ width: 900, height: 1400 });
    await page.click('#naImageViewer_btnPerspective');
    await page.evaluate(function() { window.Na__ImageViewer__ToolbarMenu.home(); });

    // ------------------------------------------------------------ canvas shape on wrap
    await page.setViewportSize({ width: 640, height: 900 });
    await settle();
    var same = async function() {
        return page.$eval('#naImageViewer_canvas', function(c) { var r = c.getBoundingClientRect(); return Math.abs(c.height - Math.floor(r.height * (window.devicePixelRatio || 1))) <= 1; });
    };
    await page.click('[data-toolset-open="view"]');
    await settle();
    check('the canvas keeps its shape in a set at the smallest window', await same());
    await page.click('[data-toolset="view"] [data-toolset-back]');
    await settle();
    check('and back at home', await same());
    await page.setViewportSize({ width: 900, height: 1400 });
    await settle();

    // ------------------------------------------------------------ the folder button
    check('with photos loaded the folder button stands back', !(await page.$eval('#naImageViewer_btnChoose', function(b) { return b.classList.contains('naImageViewer__Btn--primary'); })));
    await page.evaluate(function() { document.getElementById('naImageViewer_thumbs').innerHTML = ''; });
    await page.waitForTimeout(30);
    check('with no photos it leads', await page.$eval('#naImageViewer_btnChoose', function(b) { return b.classList.contains('naImageViewer__Btn--primary'); }));

    check('no page errors', t.errors.length === 0, t.errors);
    await t.browser.close();
    console.log(passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(1); });
