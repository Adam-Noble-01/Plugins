/* Perspective Angle in the real Image Viewer dialog, in headless Chromium.
 *
 * node tests/perspective.ui.test.js <playwright> <chrome.exe>
 * Assembles the dialog from the module files exactly as the DialogManager
 * does, renders two test photos (a 47.5 degree gable seen steeply, so the
 * photo shows about 60 degrees) and clicks the edges a person would. Checks
 * the corrected pitch and apex angle, shared undo with Measure, tool hand-off,
 * handle dragging, lens entry, Esc, per-photo state and Delete. Output and
 * screenshots go to tests/out/.
 */
'use strict';
var path = require('path');
var fs = require('fs');
var playwright = require(process.argv[2] || 'playwright');
var CHROME = process.argv[3];
var scene = require('./perspective_scene.js');
var ROOT = path.resolve(__dirname, '..');
var OUT = path.join(__dirname, 'out');
var PREFIX = 'Na__Noble3dModellingTools__ImageCarousel__';
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT);
function slash(p) { return p.split(path.sep).join('/'); }
function part(name) { return fs.readFileSync(path.join(ROOT, PREFIX + name), 'utf8'); }

// Same placeholders, same order as DialogManager.na_render_html (functions keep $ literal).
var html = part('UiLayout__.html')
    .replace('{{STYLESHEET_CONTENT}}',        function() { return part('Styles__.css'); })
    .replace('{{UI_BRIDGE_SCRIPT}}',          function() { return part('UiBridge__.js'); })
    .replace('{{MEASUREMENT_SCRIPT}}',        function() { return part('Measurement__.js'); })
    .replace('{{PERSPECTIVE_SOLVER_SCRIPT}}', function() { return part('PerspectiveSolver__.js'); })
    .replace('{{PERSPECTIVE_ANGLE_SCRIPT}}',  function() { return part('PerspectiveAngle__.js'); });
fs.writeFileSync(path.join(OUT, 'dialog.html'), html);

var house = scene.house();
var IMG1 = slash(path.join(OUT, 'house.png'));
var IMG2 = slash(path.join(OUT, 'house_small.png'));

// Paint a test photo in the browser and save it as a PNG.
async function renderPhoto(browser, file, w, h) {
    var p = await browser.newPage();
    var data = await p.evaluate(function(args) {
        var c = document.createElement('canvas');
        c.width = args.w; c.height = args.h;
        var g = c.getContext('2d');
        var k = args.w / args.house.w;
        function X(q) { return q.x * k + args.w / 2; }
        function Y(q) { return q.y * k + args.h / 2; }
        g.fillStyle = '#96bee6'; g.fillRect(0, 0, args.w, args.h);
        g.fillStyle = '#608c46'; g.fillRect(0, args.h * 0.62, args.w, args.h);
        args.house.polys.forEach(function(poly) {
            g.beginPath();
            poly.pts.forEach(function(q, i) { if (i) g.lineTo(X(q), Y(q)); else g.moveTo(X(q), Y(q)); });
            g.closePath(); g.fillStyle = poly.fill; g.fill();
        });
        g.lineWidth = 3 * k;
        args.house.lines.forEach(function(l) {
            g.beginPath(); g.moveTo(X(l.a), Y(l.a)); g.lineTo(X(l.b), Y(l.b)); g.strokeStyle = l.color; g.stroke();
        });
        return c.toDataURL('image/png');
    }, { w: w, h: h, house: house });
    fs.writeFileSync(file, Buffer.from(data.split(',')[1], 'base64'));
    await p.close();
}

var passes = 0, fails = 0;
function check(name, cond, detail) {
    if (cond) passes++;
    else { fails++; console.log('FAIL  ' + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); }
}

(async function main() {
    var browser = await playwright.chromium.launch(CHROME ? { executablePath: CHROME, headless: true } : { headless: true });
    await renderPhoto(browser, IMG1, 4032, 3024);
    await renderPhoto(browser, IMG2, 1008, 756);
    var page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
    var errors = [];
    page.on('pageerror', function(e) { errors.push(String(e)); });
    page.on('console', function(m) { if (m.type() === 'error') errors.push(m.text()); });

    await page.addInitScript(function() {
        window.__calls = [];
        window.sketchup = new Proxy({}, {
            get: function(_t, name) {
                return function(arg) {
                    window.__calls.push([name, arg]);
                    if (name === 'request_photo_info') {
                        setTimeout(function() { window.Na__ImageViewer__OnPhotoInfo({ path: arg, none: true }); }, 20);
                    }
                };
            }
        });
    });
    await page.goto('file:///' + slash(path.join(OUT, 'dialog.html')));
    await page.evaluate(function(list) { window.SKP_onFolderChosen(list); }, [IMG1, IMG2]);
    await page.waitForFunction(function() { var s = window.Na__ImageViewer__Core.getImageSize(); return s.w === 4032; });

    var widthBefore = await page.evaluate(function() { return document.getElementById('naImageViewer_canvas').width; });
    await page.click('#naImageViewer_btnPerspective');
    var widthAfter = await page.evaluate(function() { return document.getElementById('naImageViewer_canvas').width; });
    check('panel opens and the canvas gives it room', widthAfter < widthBefore - 200, [widthBefore, widthAfter]);
    await page.click('#naImageViewer_btnFit');

    async function screenOf(pt) {
        return page.evaluate(function(p) {
            var c = window.Na__ImageViewer__Core, s = c.imgToScreen(p), r = c.getCanvas().getBoundingClientRect(), k = c.getRatio();
            return { x: r.left + s.x / k, y: r.top + s.y / k };
        }, { x: pt.x, y: pt.y });
    }
    async function clickImg(pt) { var s = await screenOf(pt); await page.mouse.click(s.x, s.y); }
    async function drawSegs(btn, segs) {
        await page.click(btn);
        for (var i = 0; i < segs.length; i++) { await clickImg(segs[i][0]); await clickImg(segs[i][1]); }
        await page.keyboard.press('Escape');
    }
    async function text(sel) { return page.$eval(sel, function(el) { return el.textContent; }); }
    async function results() {
        return page.$$eval('#naImageViewer_perspResults .naImageViewer__PerspResult', function(rows) {
            return rows.map(function(r) {
                return {
                    name : r.querySelector('.naImageViewer__PerspResultName').textContent,
                    value: parseFloat(r.querySelector('.naImageViewer__PerspResultValue').textContent),
                    pm   : r.querySelector('.naImageViewer__PerspPm').textContent,
                    sub  : r.querySelector('.naImageViewer__PerspResultSub').textContent
                };
            });
        });
    }

    // ---------------------------------------------------------------- uncalibrated reading first
    await page.click('#naImageViewer_perspPitch');
    await clickImg(house.key.verge[0]);
    await clickImg(house.key.verge[1]);
    await page.keyboard.press('Escape');
    var r0 = await results();
    check('an uncalibrated pitch shows the 2D angle', r0.length === 1 && r0[0].pm === '2D' && Math.abs(r0[0].value - 60.5) < 0.6, r0);

    // ---------------------------------------------------------------- calibrate
    await drawSegs('#naImageViewer_perspDrawZ', house.key.verticals);
    check('three verticals counted', (await text('#naImageViewer_perspCountZ')) === '3 lines', await text('#naImageViewer_perspCountZ'));
    var st1 = await text('#naImageViewer_perspStatus');
    check('verticals alone ask for level lines', /level lines/.test(st1), st1);
    await drawSegs('#naImageViewer_perspDrawX', house.key.red);
    var st2 = await text('#naImageViewer_perspStatus');
    check('calibrated after red lines', /Calibrated from 5 lines/.test(st2), st2);
    await page.waitForTimeout(400);
    var r1 = await results();
    var pm1 = parseFloat(r1[0].pm.replace(/[^0-9.]/g, ''));
    console.log('  pitch with verticals + red, auto lens: ' + r1[0].value + ' ' + r1[0].pm + '  (true ' + house.pitch + ', photo ' + r1[0].sub + ')');
    check('the same pitch is now corrected', r1[0].pm !== '2D' && Math.abs(r1[0].value - house.pitch) <= Math.max(pm1, 0.3), r1);

    await drawSegs('#naImageViewer_perspDrawY', house.key.green);
    await page.waitForTimeout(400);
    var r2 = await results();
    var pm2 = parseFloat(r2[0].pm.replace(/[^0-9.]/g, ''));
    console.log('  pitch with green lines added:          ' + r2[0].value + ' ' + r2[0].pm);
    check('green lines keep it within the shown +/-', Math.abs(r2[0].value - house.pitch) <= Math.max(pm2, 0.3), r2);
    var lensInfo = await text('#naImageViewer_perspLensInfo');
    console.log('  lens note: ' + lensInfo);
    check('lens is reported', /mm/.test(lensInfo), lensInfo);

    // ---------------------------------------------------------------- apex angle
    await page.click('#naImageViewer_perspAngle');
    for (var i = 0; i < 3; i++) await clickImg(house.key.apex[i]);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    var r3 = await results();
    var pm3 = parseFloat(r3[1].pm.replace(/[^0-9.]/g, ''));
    console.log('  apex angle: ' + r3[1].value + ' ' + r3[1].pm + '  (true ' + (180 - 2 * house.pitch) + ')');
    check('apex angle = 180 - 2 x pitch', Math.abs(r3[1].value - (180 - 2 * house.pitch)) <= Math.max(pm3, 0.4), r3[1]);

    // ---------------------------------------------------------------- shared undo / redo with Measure
    await page.keyboard.press('Control+z');
    check('Ctrl+Z removes the apex angle', (await results()).length === 1);
    await page.keyboard.press('Control+y');
    check('Ctrl+Y brings it back', (await results()).length === 2);
    await page.click('#naImageViewer_perspPitch');
    await page.click('#naImageViewer_btnMeasure');
    var owner = await page.evaluate(function() { return window.Na__ImageViewer__Core.getToolOwner(); });
    var pitchActive = await page.$eval('#naImageViewer_perspPitch', function(b) { return b.classList.contains('naImageViewer__Btn--active'); });
    check('Measure takes the canvas from the Pitch tool', owner === 'measure' && !pitchActive, [owner, pitchActive]);
    await clickImg({ x: -400, y: 600 });
    await clickImg({ x: 100, y: 650 });
    await page.keyboard.press('Escape');
    var undoEnabled = await page.$eval('#naImageViewer_btnUndo', function(b) { return !b.disabled; });
    check('Undo button live', undoEnabled);
    await page.keyboard.press('Control+z');
    check('first Ctrl+Z undoes the dimension, angles stay', (await results()).length === 2);
    await page.keyboard.press('Control+z');
    check('second Ctrl+Z undoes the apex angle', (await results()).length === 1);
    await page.keyboard.press('Control+y');
    await page.keyboard.press('Control+y');
    check('redo replays both', (await results()).length === 2);

    // ---------------------------------------------------------------- drag a handle
    // The verge's top end sits on the apex angle's corner: select the pitch
    // first so its handle wins.
    await page.click('#naImageViewer_perspResults .naImageViewer__PerspResult');
    var apexBefore = (await results())[1].value;
    var top = await screenOf(house.key.verge[1]);
    var beforeDrag = (await results())[0].value;
    await page.mouse.move(top.x, top.y);
    await page.mouse.down();
    await page.mouse.move(top.x + 30, top.y - 18, { steps: 5 });
    await page.mouse.up();
    await page.waitForTimeout(300);
    var afterDrag = (await results())[0].value;
    check('dragging the verge end changes the pitch', Math.abs(afterDrag - beforeDrag) > 0.5, [beforeDrag, afterDrag]);
    check('the coincident apex corner stays put', Math.abs((await results())[1].value - apexBefore) < 0.05, [apexBefore, (await results())[1].value]);
    await page.keyboard.press('Control+z');
    await page.waitForTimeout(300);
    check('Ctrl+Z puts the dragged point back', Math.abs((await results())[0].value - beforeDrag) < 0.05, [(await results())[0].value, beforeDrag]);

    // ---------------------------------------------------------------- lens entry
    await page.selectOption('#naImageViewer_perspLens', 'custom');
    var inputShown = await page.$eval('#naImageViewer_perspLensMm', function(el) { return el.style.display !== 'none'; });
    check('Other... shows the mm box', inputShown);
    await page.fill('#naImageViewer_perspLensMm', '500000');
    await page.press('#naImageViewer_perspLensMm', 'Enter');
    var refuse = await text('#naImageViewer_perspLensInfo');
    check('an impossible lens is refused with the fix named', /not a camera lens/.test(refuse), refuse);
    await page.fill('#naImageViewer_perspLensMm', '25.8');
    await page.press('#naImageViewer_perspLensMm', 'Enter');
    await page.waitForTimeout(400);
    var setInfo = await text('#naImageViewer_perspLensInfo');
    check('a typed lens is used', /25\.8 mm set/.test(setInfo), setInfo);
    var r4 = await results();
    var pm4 = parseFloat(r4[0].pm.replace(/[^0-9.]/g, ''));
    console.log('  pitch with the true lens set (25.8 mm): ' + r4[0].value + ' ' + r4[0].pm);
    check('true lens: pitch within +/-', Math.abs(r4[0].value - house.pitch) <= Math.max(pm4, 0.3), r4[0]);

    // ---------------------------------------------------------------- Esc behaviour
    await page.click('#naImageViewer_perspPitch');
    await clickImg({ x: 0, y: 0 });
    await page.keyboard.press('Escape');
    var stillPitch = await page.$eval('#naImageViewer_perspPitch', function(b) { return b.classList.contains('naImageViewer__Btn--active'); });
    check('first Esc drops the pending point only', stillPitch);
    await page.keyboard.press('Escape');
    var pitchOff = await page.$eval('#naImageViewer_perspPitch', function(b) { return !b.classList.contains('naImageViewer__Btn--active'); });
    check('second Esc leaves the tool', pitchOff);

    // ---------------------------------------------------------------- guides + screenshot
    await page.check('#naImageViewer_perspGrid');
    await page.click('#naImageViewer_perspResults .naImageViewer__PerspResult');
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(OUT, 'ui_full.png') });

    // ---------------------------------------------------------------- per-image state
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 1008; });
    check('the next photo starts clean', (await results()).length === 0 && (await text('#naImageViewer_perspCountZ')) === 'none yet');
    await page.keyboard.press('ArrowLeft');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 4032; });
    await page.waitForTimeout(300);
    check('coming back restores this photo\'s lines and angles', (await results()).length === 2 && (await text('#naImageViewer_perspCountZ')) === '3 lines');

    // ---------------------------------------------------------------- delete key
    await page.click('#naImageViewer_perspResults .naImageViewer__PerspResult');
    await page.keyboard.press('Delete');
    check('Delete removes the selected angle', (await results()).length === 1);

    // ---------------------------------------------------------------- Ruby bridge calls
    var calls = await page.evaluate(function() { return window.__calls.map(function(c) { return c[0]; }); });
    check('photo info requested from Ruby', calls.indexOf('request_photo_info') >= 0, calls);

    // close the panel: lines hidden, measurements kept
    await page.click('#naImageViewer_perspClose');
    var widthClosed = await page.evaluate(function() { return document.getElementById('naImageViewer_canvas').width; });
    check('closing gives the canvas its width back', widthClosed === widthBefore, [widthClosed, widthBefore]);
    await page.screenshot({ path: path.join(OUT, 'ui_closed.png') });

    check('no page errors', errors.length === 0, errors);
    await browser.close();
    console.log('\n' + passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(2); });
