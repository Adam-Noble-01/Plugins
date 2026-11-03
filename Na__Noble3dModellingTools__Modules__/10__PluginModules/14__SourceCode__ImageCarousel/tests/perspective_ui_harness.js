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
var zlib = require('zlib');
var scene = require('./perspective_scene.js');

var ROOT = path.resolve(__dirname, '..');
var OUT = path.join(__dirname, 'out');
var PREFIX = 'Na__Noble3dModellingTools__ImageCarousel__';
// 15 px over a round 1000: the toolbar's tile row is that much taller than the flat bar was,
// and the suites' photo-space test spots were all chosen for this size of canvas.
var VIEWPORT = { width: 1600, height: 1015 };

function slash(p) { return p.split(path.sep).join('/'); }
function part(name) { return fs.readFileSync(path.join(ROOT, PREFIX + name), 'utf8'); }

// Same placeholders, same order as DialogManager.na_render_html (functions keep $ literal).
function assemble(file) {
    var html = part('UiLayout__.html')
        .replace(/\{\{ICON:(\w+)\}\}/g,           function(_m, name) { return fs.readFileSync(path.join(ROOT, 'UiIcons__MenuIcons__ImageViewer', name + '.svg'), 'utf8'); })
        .replace('{{STYLESHEET_CONTENT}}',        function() { return part('Styles__.css'); })
        .replace('{{UI_BRIDGE_SCRIPT}}',          function() { return part('UiBridge__.js'); })
        .replace('{{TOOLBAR_MENU_SCRIPT}}',       function() { return part('ToolbarMenu__.js'); })
        .replace('{{MARKUP_SCRIPT}}',             function() { return part('MarkupTool__.js'); })
        .replace('{{MEASUREMENT_SCRIPT}}',        function() { return part('Measurement__.js'); })
        .replace('{{PERSPECTIVE_SOLVER_SCRIPT}}', function() { return part('PerspectiveSolver__.js'); })
        .replace('{{PERSPECTIVE_ANGLE_SCRIPT}}',  function() { return part('PerspectiveAngle__.js'); })
        .replace('{{COUNT_TOOL_SCRIPT}}',         function() { return part('CountTool__.js'); });
    fs.writeFileSync(file, html);
}

// A toolbar button may be nested in a toolset: reach it the way a person does,
// through Back and the set's own button, so a suite can simply click its tool.
function reachNestedTools(page) {
    var pageClick = page.click.bind(page);
    page.click = async function(sel, opt) {
        if (/^#naImageViewer_btn/.test(sel)) {
            var route = await page.evaluate(function(s) {
                var el = document.querySelector(s), row = el && el.closest('[data-toolset]');
                return {
                    hidden: !!el && el.offsetParent === null,
                    target: row ? row.getAttribute('data-toolset') : null,
                    open: window.Na__ImageViewer__ToolbarMenu.inspect().open
                };
            }, sel);
            if (route.hidden) {
                if (route.open) await pageClick('[data-toolset="' + route.open + '"] [data-toolset-back]');
                if (route.target) await pageClick('[data-toolset-open="' + route.target + '"]');
            }
        }
        return pageClick(sel, opt);
    };
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
    var page = await browser.newPage({ viewport: VIEWPORT, deviceScaleFactor: 1 });
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

    reachNestedTools(page);

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

// Distance from an image point to a guide's visible segment.
function distToSeg(q, seg) {
    var dx = seg.b.x - seg.a.x, dy = seg.b.y - seg.a.y, l2 = dx * dx + dy * dy;
    var t = l2 > 0 ? Math.max(0, Math.min(1, ((q.x - seg.a.x) * dx + (q.y - seg.a.y) * dy) / l2)) : 0;
    return Math.hypot(q.x - (seg.a.x + t * dx), q.y - (seg.a.y + t * dy));
}

module.exports = { open: open, distToSeg: distToSeg, OUT: OUT, VIEWPORT: VIEWPORT, assemble: assemble, reachNestedTools: reachNestedTools, decodePng: decodePng };
