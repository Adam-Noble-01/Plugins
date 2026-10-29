/* Markup tool in the real Image Viewer dialog, in headless Chromium.
 *
 * node tests/markup.ui.test.js <playwright> <chrome.exe>
 * On the synthetic house photo (flat sky above the house, so a mark's colour
 * can be read back from a screenshot):
 *  - the Markup button opens the floating toolbar on the highlighter
 *  - highlighter and pen strokes: colour, size, width in photo pixels, one
 *    stroke per drag, a click is a dot, a straight drag keeps two points
 *  - colours and sizes from the options, P / H / E, Esc stepping back
 *  - the eraser: whole marks (and nothing for a drag that touches none) and
 *    part of a mark, undo and redo, Clear all
 *  - marks pan and zoom with the photo; right-drag pans without leaving the tool
 *  - what is saved to the model (photo pixels, photo size, 0.01 px) and what is
 *    drawn after it is read back (same pixels), in either order of arrival
 *  - per photo, thumbnail dots, a copy of the photo at another size takes the
 *    marks scaled, a photo of another shape does not take them
 *  - tool hand-off, moving the toolbar, the saved notice
 */
'use strict';
var path = require('path');
var fs = require('fs');
var zlib = require('zlib');
var harness = require('./perspective_ui_harness.js');
var playwright = require(process.argv[2] || 'playwright');
var CHROME = process.argv[3];

var passes = 0, fails = 0;
function check(name, cond, detail) {
    if (cond) passes++;
    else { fails++; console.log('FAIL  ' + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); }
}
function slash(p) { return p.split(path.sep).join('/'); }
function near(a, b, tol) { return Math.abs(a - b) <= tol; }

// A screenshot's pixels (8-bit, not interlaced: what Chromium writes).
function decodePng(buf) {
    var pos = 8, w = 0, h = 0, depth = 0, type = 0, idat = [];
    while (pos < buf.length) {
        var len = buf.readUInt32BE(pos), name = buf.toString('ascii', pos + 4, pos + 8), data = buf.slice(pos + 8, pos + 8 + len);
        if (name === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); depth = data[8]; type = data[9]; }
        else if (name === 'IDAT') idat.push(data);
        else if (name === 'IEND') break;
        pos += 12 + len;
    }
    var ch = type === 6 ? 4 : type === 2 ? 3 : 0;
    if (depth !== 8 || !ch) throw new Error('unsupported png ' + depth + '/' + type);
    var raw = zlib.inflateSync(Buffer.concat(idat)), stride = w * ch;
    var out = Buffer.alloc(h * stride), prev = Buffer.alloc(stride);
    for (var y = 0; y < h; y++) {
        var ft = raw[y * (stride + 1)], line = raw.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1)), cur = out.slice(y * stride, (y + 1) * stride);
        for (var x = 0; x < stride; x++) {
            var a = x >= ch ? cur[x - ch] : 0, b = prev[x], c = x >= ch ? prev[x - ch] : 0, v = line[x];
            if (ft === 1) v += a; else if (ft === 2) v += b; else if (ft === 3) v += (a + b) >> 1;
            else if (ft === 4) { var p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); }
            cur[x] = v & 255;
        }
        prev = cur;
    }
    return { w: w, h: h, px: function(x, y) { var i = (Math.round(y) * w + Math.round(x)) * ch; return [out[i], out[i + 1], out[i + 2]]; } };
}

(async function main() {
    var t = await harness.open(playwright, CHROME, 'markup');
    var page = t.page, h = t.h;
    var P1 = slash(path.join(t.out, 'markup_house.png')), P2 = slash(path.join(t.out, 'markup_house_small.png'));
    var W1 = 4032, H1 = 3024, W2 = 1008, H2 = 756;

    function mk() { return page.evaluate(function() { return window.Na__ImageViewer__Markup.inspect(); }); }
    function zoom() { return page.evaluate(function() { return window.Na__ImageViewer__Core.getZoom(); }); }
    function saves() { return page.evaluate(function() { return window.__calls.filter(function(c) { return c[0] === 'markup_save'; }).map(function(c) { return JSON.parse(c[1]); }); }); }
    async function lastSave(photo) {
        var all = (await saves()).filter(function(s) { return s.path === photo; });
        return all[all.length - 1] || null;
    }
    async function settle() {
        await page.evaluate(function() { return new Promise(function(r) { requestAnimationFrame(function() { requestAnimationFrame(r); }); }); });
    }
    async function offCanvas() { await page.mouse.move(5, 5); await settle(); }
    async function canvasBox() {
        return page.$eval('#naImageViewer_canvas', function(el) { var r = el.getBoundingClientRect(); return { x: r.left, y: r.top, width: r.width, height: r.height }; });
    }
    // The canvas as it is shown, to read a colour from.
    async function shot() {
        var box = await canvasBox();
        var png = decodePng(await page.screenshot({ clip: box }));
        return {
            w: png.w, h: png.h,
            at: async function(pt) { var s = await h.screenOf(pt); return png.px(s.x - box.x, s.y - box.y); },
            atScreen: function(x, y) { return png.px(x - box.x, y - box.y); },
            rel: function(x, y) { return png.px(x, y); }
        };
    }
    async function drag(pts, opt) {
        opt = opt || {};
        var s0 = await h.screenOf(pts[0]);
        await page.mouse.move(s0.x, s0.y);
        await page.mouse.down(opt.button ? { button: opt.button } : undefined);
        for (var i = 1; i < pts.length; i++) {
            var s = await h.screenOf(pts[i]);
            await page.mouse.move(s.x, s.y, { steps: opt.steps || 8 });
        }
        if (!opt.hold) await page.mouse.up(opt.button ? { button: opt.button } : undefined);
    }
    // The chosen tool's button toggles its options: press it only when they are shut.
    async function openFlyout(toolButton) {
        if (!(await mk()).flyout) await page.click(toolButton);
    }
    function dist(a, b) { return Math.hypot(a[0] - b[0], a[1] - b[1]); }
    // The sky above the house is #96bee6: a mark over it can be told by its colour.
    var SKY = [150, 190, 230];
    function isSky(px) { return near(px[0], SKY[0], 3) && near(px[1], SKY[1], 3) && near(px[2], SKY[2], 3); }

    // ---------------------------------------------------------------- opening
    var info = await mk();
    check('the toolbar starts closed', !info.active && !info.bar.open);
    check('the photo starts with no marks', info.strokes.length === 0 && !info.marked);
    await page.click('#naImageViewer_btnMarkup');
    info = await mk();
    check('the Markup button opens the toolbar', info.active && info.bar.open);
    check('it opens on the highlighter, as pictured', info.tool === 'hl', info.tool);
    check('the Markup button shows the tool is on', await page.$eval('#naImageViewer_btnMarkup', function(b) { return b.classList.contains('naImageViewer__Btn--active'); }));
    check('Markup owns the canvas', await page.evaluate(function() { return window.Na__ImageViewer__Core.getToolOwner(); }) === 'markup');
    var pill = await page.$eval('#naImageViewer_markupPill', function(el) { var r = el.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
    var box = await canvasBox();
    check('the toolbar floats at the top centre of the photo area', pill.y >= box.y && pill.y < box.y + 30 && near(pill.x + pill.w / 2, box.x + box.width / 2, 2), [pill, box]);
    check('it is a compact pill like the picture', pill.w > 150 && pill.w < 260 && pill.h > 36 && pill.h < 60, pill);
    var chosen = await page.$$eval('.naImageViewer__MarkupTool--active', function(els) { return els.map(function(e) { return e.id; }); });
    check('only the highlighter is chosen', chosen.length === 1 && chosen[0] === 'naImageViewer_markupHl', chosen);
    var buttons = await page.$$eval('#naImageViewer_markupPill button', function(els) { return els.map(function(e) { return e.id; }); });
    check('pen, highlighter, eraser, colours and close', buttons.join() === 'naImageViewer_markupPen,naImageViewer_markupHl,naImageViewer_markupEraser,naImageViewer_markupOptions,naImageViewer_markupDone', buttons);
    await page.mouse.move(5, 5);
    await page.screenshot({ path: path.join(t.out, 'markup_bar.png') });

    // ---------------------------------------------------------------- highlighter
    var Z = await zoom();
    var skyBefore = await (await shot()).at({ x: 400, y: -1400 });
    check('the test spot is plain sky', isSky(skyBefore), skyBefore);
    await drag([{ x: -900, y: -1400 }, { x: 0, y: -1400 }, { x: 900, y: -1400 }]);
    info = await mk();
    check('a drag is one highlighter stroke', info.strokes.length === 1 && info.strokes[0].k === 'hl', info.strokes.length);
    check('in yellow', info.strokes[0].c === '#ffe600', info.strokes[0].c);
    check('24 px wide on screen', near(info.strokes[0].w * Z, 24, 0.6), info.strokes[0].w * Z);
    check('a straight drag keeps two points', info.strokes[0].n === 2, info.strokes[0].n);
    await offCanvas();
    var s = await shot();
    var over = await s.at({ x: 400, y: -1400 });
    console.log('  highlighter over sky: ' + JSON.stringify(over) + ' (sky ' + JSON.stringify(SKY) + ')');
    check('the highlighter tints what is under it', over[2] < skyBefore[2] - 60 && over[0] > skyBefore[0] + 25, over);
    check('and still shows it through', over[1] > 150, over);
    check('nothing is marked beside the stroke', isSky(await s.at({ x: 400, y: -1400 + 300 })) && isSky(await s.at({ x: -1500, y: -1400 })));
    var save = await lastSave(P1);
    check('the stroke is sent to be saved', !!save && save.strokes.length === 1, save && save.strokes.length);
    check('with the photo path and size', save && save.path === P1 && save.w === W1 && save.h === H1, save && [save.path, save.w, save.h]);
    check('in photo pixels from the top-left', save && near(save.strokes[0].p[0], -900 + W1 / 2, 8) && near(save.strokes[0].p[1], -1400 + H1 / 2, 8) && near(save.strokes[0].p[2], 900 + W1 / 2, 8), save && save.strokes[0].p);
    check('with kind, colour and width in photo pixels', save && save.strokes[0].k === 'hl' && save.strokes[0].c === '#ffe600' && near(save.strokes[0].w, 24 / Z, 0.02), save && save.strokes[0]);

    // ---------------------------------------------------------------- colour and size
    await openFlyout('#naImageViewer_markupHl');
    info = await mk();
    check('pressing the chosen tool again opens its options', info.flyout);
    var swatches = await page.$$eval('.naImageViewer__MarkupSwatch', function(els) { return els.map(function(e) { return e.getAttribute('data-value'); }); });
    check('the highlighter offers six colours, yellow first', swatches.length === 6 && swatches[0] === '#ffe600', swatches);
    var sizes = await page.$$eval('.naImageViewer__MarkupSize', function(els) { return els.map(function(e) { return e.getAttribute('data-value'); }); });
    check('and three sizes', sizes.join() === '14,24,40', sizes);
    await page.screenshot({ path: path.join(t.out, 'markup_flyout.png') });
    await page.click('.naImageViewer__MarkupSwatch[data-value="#ff6fb5"]');
    await page.click('.naImageViewer__MarkupSize[data-value="40"]');
    info = await mk();
    check('choosing pink changes the highlighter only', info.hl.colour === '#ff6fb5' && info.hl.size === 40 && info.pen.colour === '#1b1f24' && info.pen.size === 4, [info.hl, info.pen]);
    var iconFill = await page.$eval('.naImageViewer__MarkupHlFill', function(el) { return getComputedStyle(el).fill; });
    check('the highlighter icon shows its colour', iconFill === 'rgb(255, 111, 181)', iconFill);
    await drag([{ x: -900, y: -1200 }, { x: 900, y: -1200 }]);
    info = await mk();
    check('a second stroke in pink, wide', info.strokes.length === 2 && info.strokes[1].c === '#ff6fb5' && near(info.strokes[1].w * Z, 40, 1), info.strokes.map(function(q) { return [q.c, q.w * Z]; }));
    check('drawing closes the options', !info.flyout);

    // ---------------------------------------------------------------- pen, dot
    await page.keyboard.press('p');
    info = await mk();
    check('P chooses the pen', info.tool === 'pen' && !info.flyout, info.tool);
    chosen = await page.$$eval('.naImageViewer__MarkupTool--active', function(els) { return els.map(function(e) { return e.id; }); });
    check('and the pen button is the chosen one', chosen.length === 1 && chosen[0] === 'naImageViewer_markupPen', chosen);
    await drag([{ x: -800, y: -800 }, { x: -400, y: -900 }, { x: 0, y: -750 }, { x: 400, y: -900 }, { x: 800, y: -800 }]);
    info = await mk();
    var pen = info.strokes[2];
    check('a pen stroke, black, 4 px wide', info.strokes.length === 3 && pen.k === 'pen' && pen.c === '#1b1f24' && near(pen.w * Z, 4, 0.2), pen && [pen.k, pen.c, pen.w * Z]);
    check('a wiggly drag keeps the points that carry its shape', pen.n >= 5 && pen.n <= 60, pen.n);
    await offCanvas();
    s = await shot();
    var inkAt = await s.at({ x: -400, y: -900 });
    check('the pen is solid', inkAt[0] < 70 && inkAt[1] < 70 && inkAt[2] < 80, inkAt);
    await h.clickImg({ x: -1500, y: -1000 });
    info = await mk();
    check('a click is a dot', info.strokes.length === 4 && info.strokes[3].n === 1 && info.strokes[3].k === 'pen', info.strokes.length && info.strokes[3] && info.strokes[3].n);
    await offCanvas();
    s = await shot();
    var dotAt = await s.at({ x: -1500, y: -1000 });
    check('and it is drawn', dotAt[0] < 90 && dotAt[2] < 100, dotAt);
    save = await lastSave(P1);
    check('the dot is saved as one point', save.strokes.length === 4 && save.strokes[3].p.length === 2, save.strokes[3]);
    await page.keyboard.press('h');
    info = await mk();
    check('H chooses the highlighter again', info.tool === 'hl');

    // ---------------------------------------------------------------- undo and redo
    await page.keyboard.press('Control+z');
    info = await mk();
    check('Ctrl+Z takes back the last mark', info.strokes.length === 3, info.strokes.length);
    save = await lastSave(P1);
    check('and the model is told', save.strokes.length === 3, save.strokes.length);
    await page.keyboard.press('Control+y');
    info = await mk();
    save = await lastSave(P1);
    check('Ctrl+Y brings it back, in the model too', info.strokes.length === 4 && save.strokes.length === 4, [info.strokes.length, save.strokes.length]);
    check('the viewer\'s own Undo button is live', !(await page.$eval('#naImageViewer_btnUndo', function(b) { return b.disabled; })));

    // ---------------------------------------------------------------- eraser: whole marks
    await page.keyboard.press('e');
    info = await mk();
    check('E chooses the eraser', info.tool === 'eraser' && info.eraser.mode === 'stroke', [info.tool, info.eraser]);
    await openFlyout('#naImageViewer_markupEraser');
    var flyText = await page.$eval('#naImageViewer_markupFlyout', function(el) { return el.textContent; });
    check('its options: what it takes, size, clear all', /Stroke/.test(flyText) && /Part/.test(flyText) && /Clear all markup on this photo/.test(flyText), flyText);
    await page.keyboard.press('Escape');
    info = await mk();
    check('Esc closes the options first', info.active && !info.flyout);
    var before = info.strokes.length;
    await drag([{ x: 1500, y: -1000 }, { x: 1500, y: -800 }]);                       // empty sky
    info = await mk();
    check('rubbing over nothing changes nothing', info.strokes.length === before, info.strokes.length);
    await page.keyboard.press('Control+z');
    info = await mk();
    check('and leaves nothing to undo of its own', info.strokes.length === before - 1 && info.strokes[info.strokes.length - 1].k === 'pen' && info.strokes[info.strokes.length - 1].n > 1, info.strokes.length);
    await page.keyboard.press('Control+y');
    await drag([{ x: -400, y: -1000 }, { x: -400, y: -760 }]);                       // across the wiggly pen stroke
    info = await mk();
    check('the eraser takes the whole mark it touches', info.strokes.length === 3 && !info.strokes.some(function(q) { return q.k === 'pen' && q.n > 1; }), info.strokes.map(function(q) { return q.k + q.n; }));
    check('and only that one', info.strokes.filter(function(q) { return q.k === 'hl'; }).length === 2 && info.strokes.some(function(q) { return q.n === 1; }));
    save = await lastSave(P1);
    check('the model is told', save.strokes.length === 3, save.strokes.length);
    await page.keyboard.press('Control+z');
    info = await mk();
    check('one undo puts it back', info.strokes.length === 4, info.strokes.length);
    await page.keyboard.press('Control+y');
    info = await mk();
    check('one redo takes it away again', info.strokes.length === 3);
    await page.keyboard.press('Control+z');

    // ---------------------------------------------------------------- clear all
    await openFlyout('#naImageViewer_markupEraser');
    await page.click('[data-act="clear"]');
    info = await mk();
    save = await lastSave(P1);
    check('Clear all takes every mark off the photo', info.strokes.length === 0 && !info.marked && save.strokes.length === 0, [info.strokes.length, save && save.strokes.length]);
    await page.keyboard.press('Control+z');
    info = await mk();
    check('and one undo brings them all back', info.strokes.length === 4, info.strokes.length);
    save = await lastSave(P1);
    check('with the model told', save.strokes.length === 4);
    await page.keyboard.press('Control+z');            // the dot
    await page.keyboard.press('Control+z');            // the pen
    await openFlyout('#naImageViewer_markupEraser');
    await page.click('[data-act="clear"]');
    await page.keyboard.press('Escape');

    // ---------------------------------------------------------------- eraser: part of a mark
    await page.keyboard.press('p');
    await drag([{ x: -1000, y: -760 }, { x: 1000, y: -760 }]);
    info = await mk();
    check('one long stroke to rub out part of', info.strokes.length === 1 && info.strokes[0].n === 2, info.strokes.length);
    var long = info.strokes[0];
    await page.keyboard.press('e');
    await openFlyout('#naImageViewer_markupEraser');
    await page.click('[data-act="mode"][data-value="part"]');
    info = await mk();
    check('the eraser can take part of a mark', info.eraser.mode === 'part');
    await page.keyboard.press('Escape');                                              // the options sit over this part of the photo
    await drag([{ x: 200, y: -900 }, { x: 200, y: -620 }]);
    info = await mk();
    check('rubbing across the middle leaves two pieces', info.strokes.length === 2, info.strokes.length);
    var rImg = 14 / Z, reach = long.w / 2 + rImg;
    var left = info.strokes[0], right = info.strokes[1];
    var leftEnd = [left.p[left.p.length - 2], left.p[left.p.length - 1]], rightStart = [right.p[0], right.p[1]];
    console.log('  gap: pieces end at x ' + leftEnd[0].toFixed(1) + ' and start at ' + rightStart[0].toFixed(1) + ' (eraser at 200, reach ' + reach.toFixed(1) + ')');
    check('the left piece stops a reach short of the eraser', near(leftEnd[0], 200 - reach, reach * 0.06 + 2), [leftEnd[0], 200 - reach]);
    check('the right piece starts a reach past it', near(rightStart[0], 200 + reach, reach * 0.06 + 2), [rightStart[0], 200 + reach]);
    check('the outer ends are where they were', near(left.p[0], long.p[0], 1e-6) && near(right.p[right.p.length - 2], long.p[2], 1e-6), [left.p[0], right.p[right.p.length - 2], long.p]);
    check('both pieces keep the pen, colour and width', info.strokes.every(function(q) { return q.k === 'pen' && q.c === long.c && near(q.w, long.w, 1e-9); }));
    await page.keyboard.press('Control+z');
    info = await mk();
    check('one undo mends it', info.strokes.length === 1 && info.strokes[0].n === 2 && near(info.strokes[0].p[0], long.p[0], 1e-6) && near(info.strokes[0].p[2], long.p[2], 1e-6), info.strokes.length);
    await page.keyboard.press('Control+y');
    info = await mk();
    check('and one redo cuts it again', info.strokes.length === 2);
    await drag([{ x: -400, y: -900 }, { x: -400, y: -620 }, { x: 700, y: -620 }, { x: 700, y: -900 }]);   // rub right across both pieces
    info = await mk();
    check('rubbing across each piece again cuts each in two', info.strokes.length === 4, info.strokes.length);
    await page.keyboard.press('Control+z');
    await drag([{ x: -1100, y: -760 }, { x: 1100, y: -760 }]);
    info = await mk();
    check('rubbing along what is left takes all of it', info.strokes.length === 0, info.strokes.length);
    await page.keyboard.press('Control+z');
    await page.keyboard.press('Control+z');
    await page.keyboard.press('Control+z');
    info = await mk();
    check('three undos clear the photo again', info.strokes.length === 0, info.strokes.length);

    // ---------------------------------------------------------------- marks go with the photo
    await page.keyboard.press('h');
    await drag([{ x: -300, y: -1100 }, { x: 300, y: -1100 }]);
    info = await mk();
    var halfPx = info.strokes[info.strokes.length - 1].w * Z / 2;
    await offCanvas();
    var strokeMid = { x: 0, y: -1100 };
    s = await shot();
    var m0 = await h.screenOf(strokeMid);
    var above0 = s.atScreen(m0.x, m0.y - (halfPx + 4));
    check('a point just beside the stroke is clear of it', isSky(above0), above0);
    await page.mouse.move(m0.x, m0.y);
    for (var i = 0; i < 6; i++) await page.mouse.wheel(0, -100);
    await settle();
    var Z2 = await zoom();
    check('the wheel zooms without leaving the tool', Z2 > Z * 1.5 && (await mk()).active, [Z, Z2]);
    var m1 = await h.screenOf(strokeMid);
    check('zooming about the pointer keeps the stroke under it', near(m1.x, m0.x, 2) && near(m1.y, m0.y, 2), [m0, m1]);
    await offCanvas();
    s = await shot();
    var above1 = s.atScreen(m1.x, m1.y - (halfPx + 4));
    check('the stroke has grown with the photo', !isSky(above1) && above1[0] > 175, above1);
    info = await mk();
    var strokes0 = info.strokes.length;
    var c0 = await page.evaluate(function() { var s = window.Na__ImageViewer__Core.imgToScreen({ x: 0, y: 0 }); return { x: s.x, y: s.y }; });
    await drag([{ x: 600, y: -500 }, { x: 640, y: -460 }], { button: 'right' });
    var c1 = await page.evaluate(function() { var s = window.Na__ImageViewer__Core.imgToScreen({ x: 0, y: 0 }); return { x: s.x, y: s.y }; });
    info = await mk();
    check('right-drag pans the photo', Math.hypot(c1.x - c0.x, c1.y - c0.y) > 30, [c0, c1]);
    check('and draws nothing', info.strokes.length === strokes0 && info.active);
    await page.click('#naImageViewer_btnFit');
    await page.keyboard.press('Control+z');

    // ---------------------------------------------------------------- what is saved, and what comes back
    await page.keyboard.press('h');
    await drag([{ x: -900, y: -1400 }, { x: 900, y: -1400 }]);
    await page.keyboard.press('p');
    await drag([{ x: -800, y: -800 }, { x: -400, y: -900 }, { x: 0, y: -750 }, { x: 400, y: -900 }]);
    await h.clickImg({ x: -1500, y: -1000 });
    info = await mk();
    check('three marks on photo one', info.strokes.length === 3, info.strokes.length);
    var photo1 = await lastSave(P1);
    check('saved with their photo\'s size and path', photo1.strokes.length === 3 && photo1.w === W1 && photo1.h === H1 && photo1.path === P1);
    check('every point is inside the photo', photo1.strokes.every(function(q) { return q.p.length % 2 === 0 && q.p.every(function(v, j) { return v >= 0 && v <= (j % 2 ? H1 : W1); }); }));
    check('and kept to 0.01 px', photo1.strokes.every(function(q) { return q.p.every(function(v) { return Math.abs(Math.round(v * 100) / 100 - v) < 1e-9; }); }));
    fs.writeFileSync(path.join(t.out, 'markup_payload.json'), JSON.stringify(photo1));

    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 1008; });
    info = await mk();
    check('the next photo has its own marks: none', info.strokes.length === 0 && !info.marked, info.strokes.length);
    var thumbs = await page.$$eval('.naImageViewer__Thumb', function(els) { return els.map(function(e) { return e.classList.contains('naImageViewer__Thumb--marked'); }); });
    check('photo one\'s thumbnail has a dot, photo two\'s does not', thumbs[0] === true && thumbs[1] === false, thumbs);
    await page.keyboard.press('h');
    await drag([{ x: -300, y: -250 }, { x: 300, y: -250 }]);
    var photo2 = await lastSave(P2);
    check('a mark on photo two is saved under photo two, at its size', photo2 && photo2.path === P2 && photo2.w === W2 && photo2.h === H2 && photo2.strokes.length === 1, photo2 && [photo2.path, photo2.w, photo2.h]);
    check('and photo one\'s is untouched', (await lastSave(P1)).strokes.length === 3);
    thumbs = await page.$$eval('.naImageViewer__Thumb', function(els) { return els.map(function(e) { return e.classList.contains('naImageViewer__Thumb--marked'); }); });
    check('both thumbnails now have dots', thumbs[0] && thumbs[1], thumbs);
    check('and so does the Markup button', await page.$eval('#naImageViewer_btnMarkup', function(b) { return b.classList.contains('naImageViewer__Btn--hasMarkup'); }));
    await page.keyboard.press('ArrowLeft');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 4032; });
    info = await mk();
    check('back on photo one its marks are still there', info.strokes.length === 3, info.strokes.length);

    // The picture to match: marks only, the toolbar closed, the pointer away.
    await page.click('#naImageViewer_markupDone');
    await offCanvas();
    var shown = await shot();
    var shownInfo = await mk();
    var viewMeta = function() { return page.evaluate(function() { var c = window.Na__ImageViewer__Core, s = c.imgToScreen({ x: 0, y: 0 }); return [c.getCanvas().width, c.getCanvas().height, c.getZoom(), s.x, s.y, c.getRotation()]; }); };
    var viewBefore = await viewMeta();
    await page.click('#naImageViewer_btnMarkup');
    await page.keyboard.press('h');
    await page.mouse.move(5, 5);
    await page.screenshot({ path: path.join(t.out, 'markup_marked.png') });
    await page.click('#naImageViewer_markupDone');
    var served = { };
    served[P1] = { w: photo1.w, h: photo1.h, strokes: photo1.strokes };
    served[P2] = { w: photo2.w, h: photo2.h, strokes: photo2.strokes };

    // The model's marks arrive first, then the folder (as Ruby sends them).
    async function reopen(map, order) {
        await page.reload();
        await page.waitForFunction(function() { return !!window.Na__ImageViewer__Markup; });
        if (order !== 'after') await page.evaluate(function(m) { window.Na__ImageViewer__OnMarkupLoaded(m); }, map);
        await page.evaluate(function(list) { window.SKP_onFolderChosen(list); }, [P1, P2]);
        await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 4032; });
        if (order === 'after') await page.evaluate(function(m) { window.Na__ImageViewer__OnMarkupLoaded(m); }, map);
        await settle();
        await page.mouse.move(5, 5);
        await settle();
    }
    await reopen(served);
    info = await mk();
    check('reopened: photo one has its marks back', info.strokes.length === 3 && info.marked, info.strokes.length);
    check('the same kinds, colours and widths', info.strokes.map(function(q) { return q.k + q.c + q.w.toFixed(2); }).join() === shownInfo.strokes.map(function(q) { return q.k + q.c + q.w.toFixed(2); }).join());
    var samePoints = info.strokes.every(function(q, i) { return q.p.length === shownInfo.strokes[i].p.length && q.p.every(function(v, j) { return near(v, shownInfo.strokes[i].p[j], 0.01); }); });
    check('and the same points, to 0.01 px', samePoints);
    var again = await shot();
    check('the view is the same as before', JSON.stringify(await viewMeta()) === JSON.stringify(viewBefore), [viewBefore, await viewMeta()]);
    // Every mark here is in the flat sky above the house, so that band, pixel by
    // pixel, is the marks and nothing else (the browser may sample the house's
    // edges a little differently from one page load to the next).
    var band = 262, diff = 0, total = 0, inked = 0;
    for (var y = 0; y < band; y++) for (var x = 0; x < again.w; x++) {
        var a = shown.rel(x, y), b = again.rel(x, y);
        total++;
        if (!isSky(a)) inked++;
        if (Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]) > 24) diff++;
    }
    console.log('  the sky band has ' + inked + ' marked pixels and differs in ' + diff + ' of ' + total + ' after reopening');
    check('there are marks to compare', inked > 5000, inked);
    check('the marks look as they did, pixel for pixel', diff <= 20, [diff, total]);
    thumbs = await page.$$eval('.naImageViewer__Thumb', function(els) { return els.map(function(e) { return e.classList.contains('naImageViewer__Thumb--marked'); }); });
    check('both thumbnails have dots from the model', thumbs[0] && thumbs[1], thumbs);

    await reopen(served, 'after');
    info = await mk();
    check('marks that arrive after the photo is shown appear at once', info.strokes.length === 3, info.strokes.length);
    check('and are not sent back as if they were new', (await saves()).length === 0, (await saves()).length);

    // A copy of photo one at another size (same shape) takes the marks scaled.
    var copy = {};
    copy[P2] = { w: photo1.w, h: photo1.h, strokes: photo1.strokes };
    await reopen(copy);
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 1008; });
    info = await mk();
    check('a smaller copy of the photo takes the marks', info.strokes.length === 3, info.strokes.length);
    var k = W2 / W1;
    var scaledOk = info.strokes.every(function(q, i) {
        var o = photo1.strokes[i];
        return near(q.w, o.w * k, 0.01) && q.p.every(function(v, j) { return near(v, o.p[j] * k - (j % 2 ? H2 : W2) / 2, 0.02); });
    });
    check('scaled to the copy\'s pixels', scaledOk, info.strokes[0] && info.strokes[0].p.slice(0, 4));
    // A photo of another shape does not.
    var other = {};
    other[P2] = { w: 1000, h: 1000, strokes: photo1.strokes };
    await reopen(other);
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 1008; });
    info = await mk();
    check('a photo of another shape does not take them', info.strokes.length === 0 && info.mismatch && info.mismatch.w === 1000, [info.strokes.length, info.mismatch]);
    thumbs = await page.$$eval('.naImageViewer__Thumb', function(els) { return els.map(function(e) { return e.classList.contains('naImageViewer__Thumb--marked'); }); });
    check('and has no thumbnail dot', thumbs[1] === false, thumbs);

    // ---------------------------------------------------------------- hand-off, Esc, toolbar
    await page.click('#naImageViewer_btnMarkup');
    info = await mk();
    check('Markup opens again', info.active && info.bar.open);
    await page.click('#naImageViewer_btnMeasure');
    info = await mk();
    check('starting Measure ends Markup', !info.active && !info.bar.open && (await page.evaluate(function() { return window.Na__ImageViewer__Core.getToolOwner(); })) === 'measure');
    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnMarkup');
    await page.keyboard.press('c');
    info = await mk();
    check('so does the Count tool', !info.active && (await page.evaluate(function() { return window.Na__ImageViewer__Core.getToolOwner(); })) === 'count');
    await page.keyboard.press('Escape');
    check('the marks stay while another tool is on', (await page.evaluate(function() { return window.Na__ImageViewer__Core.getToolOwner(); })) === null);

    await page.click('#naImageViewer_btnMarkup');
    await page.keyboard.press('h');
    await openFlyout('#naImageViewer_markupHl');
    await page.keyboard.press('Escape');
    info = await mk();
    check('Esc closes the options and keeps the tool', info.active && !info.flyout);
    var s0 = await h.screenOf({ x: -200, y: -250 });
    await page.mouse.move(s0.x, s0.y);
    await page.mouse.down();
    await page.mouse.move(s0.x + 90, s0.y + 10, { steps: 6 });
    check('a stroke is in hand', (await mk()).live);
    await page.keyboard.press('Escape');
    await page.mouse.up();
    info = await mk();
    check('Esc drops the stroke in hand', !info.live && info.strokes.length === 0 && info.active, [info.live, info.strokes.length]);
    await page.keyboard.press('Escape');
    info = await mk();
    check('and the next Esc closes the tool', !info.active && !info.bar.open);

    await page.click('#naImageViewer_btnMarkup');
    var g = await page.$eval('#naImageViewer_markupGrip', function(el) { var r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
    var p0 = await page.$eval('#naImageViewer_markupPill', function(el) { var r = el.getBoundingClientRect(); return { x: r.left, y: r.top }; });
    await page.mouse.move(g.x, g.y);
    await page.mouse.down();
    await page.mouse.move(g.x + 220, g.y + 90, { steps: 6 });
    await page.mouse.up();
    var p1 = await page.$eval('#naImageViewer_markupPill', function(el) { var r = el.getBoundingClientRect(); return { x: r.left, y: r.top }; });
    check('the grip drags the toolbar', near(p1.x - p0.x, 220, 2) && near(p1.y - p0.y, 90, 2) && (await mk()).bar.moved, [p0, p1]);
    check('without drawing', (await mk()).strokes.length === 0);
    await page.mouse.move(g.x + 220, g.y + 90);
    await page.mouse.down();
    await page.mouse.move(-500, -500, { steps: 4 });
    await page.mouse.up();
    var p2 = await page.$eval('#naImageViewer_markupPill', function(el) { var r = el.getBoundingClientRect(); return { x: r.left, y: r.top }; });
    var cb = await canvasBox();
    check('it cannot be dragged out of the photo area', p2.x >= cb.x && p2.y >= cb.y, [p2, cb]);

    // ---------------------------------------------------------------- the saved notice
    await page.evaluate(function() { window.Na__ImageViewer__MarkupOnSaved({ ok: true, saved: [{ key: 'a', written: true }] }); });
    check('"saved" is said quietly', /saved in the model/.test((await mk()).toast), (await mk()).toast);
    await page.evaluate(function() { window.Na__ImageViewer__MarkupOnSaved({ ok: false, path: arguments[0], error: 'too much markup' }); });
    check('a refusal says why', /not saved: too much markup/.test((await mk()).toast), (await mk()).toast);
    check('in the error style', await page.$eval('#naImageViewer_markupToast', function(el) { return el.classList.contains('naImageViewer__MarkupToast--error'); }));

    // A refusal makes the next change send the photo again.
    await page.keyboard.press('Escape');
    await page.click('#naImageViewer_btnMarkup');
    await page.keyboard.press('h');
    await page.evaluate(function() { window.__calls.length = 0; });
    await drag([{ x: -300, y: -250 }, { x: 300, y: -250 }]);
    var sent = (await saves()).length;
    await page.evaluate(function(p) { window.Na__ImageViewer__MarkupOnSaved({ ok: false, path: p, error: 'x' }); }, P2);
    await page.keyboard.press('Control+z');
    await page.keyboard.press('Control+y');
    check('a refused photo is sent again after the next change', (await saves()).length === sent + 2, [sent, (await saves()).length]);

    check('no page errors', t.errors.length === 0, t.errors);
    await t.browser.close();
    console.log('\n' + passes + ' passed, ' + fails + ' failed');
    process.exit(fails ? 1 : 0);
})().catch(function(e) { console.error(e); process.exit(1); });
