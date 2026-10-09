/* Shared set-up for the Perspective Angle browser tests.
 *
 * Assembles the Image Viewer dialog from the module files exactly as the
 * DialogManager does, paints the synthetic house photo, opens the dialog in
 * Chromium with a stand-in for SketchUp's bridge and hands back helpers that
 * click on image-space points.
 */
'use strict';
var path = require('path');
var fs = require('fs');
var scene = require('./perspective_scene.js');

var ROOT = path.resolve(__dirname, '..');
var OUT = path.join(__dirname, 'out');
var PREFIX = 'Na__Noble3dModellingTools__ImageCarousel__';

function slash(p) { return p.split(path.sep).join('/'); }
function part(name) { return fs.readFileSync(path.join(ROOT, PREFIX + name), 'utf8'); }

// Same placeholders, same order as DialogManager.na_render_html (functions keep $ literal).
function assemble(file) {
    var html = part('UiLayout__.html')
        .replace('{{STYLESHEET_CONTENT}}',        function() { return part('Styles__.css'); })
        .replace('{{UI_BRIDGE_SCRIPT}}',          function() { return part('UiBridge__.js'); })
        .replace('{{MEASUREMENT_SCRIPT}}',        function() { return part('Measurement__.js'); })
        .replace('{{PERSPECTIVE_SOLVER_SCRIPT}}', function() { return part('PerspectiveSolver__.js'); })
        .replace('{{PERSPECTIVE_ANGLE_SCRIPT}}',  function() { return part('PerspectiveAngle__.js'); });
    fs.writeFileSync(file, html);
}

async function renderPhoto(browser, house, file, w, h) {
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

async function open(playwright, chrome, name) {
    if (!fs.existsSync(OUT)) fs.mkdirSync(OUT);
    var house = scene.house();
    var dialog = path.join(OUT, name + '_dialog.html');
    var img1 = slash(path.join(OUT, name + '_house.png'));
    var img2 = slash(path.join(OUT, name + '_house_small.png'));
    assemble(dialog);
    var browser = await playwright.chromium.launch(chrome ? { executablePath: chrome, headless: true } : { headless: true });
    await renderPhoto(browser, house, img1, 4032, 3024);
    await renderPhoto(browser, house, img2, 1008, 756);
    var page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
    var errors = [];
    page.on('pageerror', function(e) { errors.push(String(e)); });
    page.on('console', function(m) { if (m.type() === 'error') errors.push(m.text()); });
    await page.addInitScript(function() {
        window.__calls = [];
        window.sketchup = new Proxy({}, {
            get: function(_t, fn) {
                return function(arg) {
                    window.__calls.push([fn, arg]);
                    if (fn === 'request_photo_info') setTimeout(function() { window.Na__ImageViewer__OnPhotoInfo({ path: arg, none: true }); }, 20);
                };
            }
        });
    });
    await page.goto('file:///' + slash(dialog));
    await page.evaluate(function(list) { window.SKP_onFolderChosen(list); }, [img1, img2]);
    await page.waitForFunction(function() { return window.Na__ImageViewer__Core.getImageSize().w === 4032; });

    var h = {
        screenOf: async function(pt) {
            return page.evaluate(function(p) {
                var c = window.Na__ImageViewer__Core, s = c.imgToScreen(p), r = c.getCanvas().getBoundingClientRect(), k = c.getRatio();
                return { x: r.left + s.x / k, y: r.top + s.y / k };
            }, { x: pt.x, y: pt.y });
        },
        clickImg: async function(pt, dx, dy) { var s = await h.screenOf(pt); await page.mouse.click(s.x + (dx || 0), s.y + (dy || 0)); },
        moveImg : async function(pt, dx, dy) { var s = await h.screenOf(pt); await page.mouse.move(s.x + (dx || 0), s.y + (dy || 0), { steps: 6 }); },
        text    : async function(sel) { return page.$eval(sel, function(el) { return el.textContent; }); },
        inspect : async function() { return page.evaluate(function() { return window.Na__ImageViewer__Perspective.inspect(); }); },
        snapAt  : async function(pt, dx, dy) {
            return page.evaluate(function(a) {
                var c = window.Na__ImageViewer__Core, s = c.imgToScreen(a.p), k = c.getRatio();
                return c.snap(s.x + a.dx * k, s.y + a.dy * k);
            }, { p: { x: pt.x, y: pt.y }, dx: dx || 0, dy: dy || 0 });
        },
        drawSegs: async function(btn, segs) {
            await page.click(btn);
            for (var i = 0; i < segs.length; i++) { await h.clickImg(segs[i][0]); await h.clickImg(segs[i][1]); }
            await page.keyboard.press('Escape');
        },
        calibrate: async function() {
            await page.click('#naImageViewer_btnPerspective');
            await page.click('#naImageViewer_btnFit');
            await h.drawSegs('#naImageViewer_perspDrawZ', house.key.verticals);
            await h.drawSegs('#naImageViewer_perspDrawX', house.key.red);
            await h.drawSegs('#naImageViewer_perspDrawY', house.key.green);
            await page.waitForTimeout(400);
        }
    };
    return { browser: browser, page: page, errors: errors, house: house, h: h, out: OUT };
}

// Distance from an image point to a guide's visible segment.
function distToSeg(q, seg) {
    var dx = seg.b.x - seg.a.x, dy = seg.b.y - seg.a.y, l2 = dx * dx + dy * dy;
    var t = l2 > 0 ? Math.max(0, Math.min(1, ((q.x - seg.a.x) * dx + (q.y - seg.a.y) * dy) / l2)) : 0;
    return Math.hypot(q.x - (seg.a.x + t * dx), q.y - (seg.a.y + t * dy));
}

module.exports = { open: open, distToSeg: distToSeg, OUT: OUT };
