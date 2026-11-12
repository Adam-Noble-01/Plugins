// =============================================================================
// NA NOBLE3D MODELLING TOOLS - IMAGE VIEWER - UI BRIDGE
//
// FILE       : Na__Noble3dModellingTools__ImageCarousel__UiBridge__.js
// PURPOSE    : Canvas image viewer logic and Ruby-JS bridge handlers
// =============================================================================

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var na_images  = [];
    var na_index   = -1;
    var na_isWin   = navigator.platform.toLowerCase().indexOf('win') !== -1;

    var na_viewer = {
        img       : new Image(),
        imgW      : 0,
        imgH      : 0,
        zoom      : 1,
        baseZoom  : 1,
        rotation  : 0,
        offX      : 0,
        offY      : 0,
        isPanning : false,
        startX    : 0,
        startY    : 0
    };

    var na_canvas   = null;
    var na_ctx      = null;
    var na_thumbsEl = null;
    var na_metaEl   = null;

    // Extension hooks consumed by separate feature files (e.g. Measurement).
    var na_panEnabled       = true;   // gate for pan; features may suppress it
    var na_overlayRenderers = [];     // fn(ctx) called after the image is drawn
    var na_imageChangedCbs  = [];     // fn(index) called after a new image loads

    // Shared by the feature files: one tool owns the canvas at a time, and one
    // undo history (per image) covers every feature's drawings.
    var na_toolOwner        = null;   // { name, release }
    var na_historyProviders = [];     // { name, snapshot(key), restore(key, snap) }
    var na_historyCbs       = [];     // fn(reason) after 'push' | 'undo' | 'redo'
    var na_undoByKey        = {};     // image key -> [ snapshot ]
    var na_redoByKey        = {};
    var NA_HISTORY_LIMIT    = 50;

    // Snapping shared by the drawing tools: providers (the Perspective Angle
    // guides, the Count tool's ticks) offer a point near the pointer; the
    // Core picks one and draws its marker.
    var na_snapProviders    = [];     // fn(cx, cy) -> { img, screen, kind, label } | null

    // Keeping the tools' work in the model (ToolStatePersistence.rb). A tool
    // registers { serialise(key, conv) -> state|null, materialise(key, state, conv) };
    // the Core sends a photo's state a moment after the picture settles (and at
    // once before another photo or folder), converts points to photo pixels
    // from the top-left and back, and scales a smaller copy's.
    var na_persisters       = {};     // tool name -> provider
    var na_persistSent      = {};     // tool name -> image key -> last JSON given to (or read from) Ruby
    var na_persistStored    = {};     // tool name -> image key -> the model's entry, until the photo is shown
    var na_persistJob       = null;   // { key, w, h } waiting to be sent
    var na_persistTimer     = null;
    var NA_PERSIST_DELAY_MS = 350;
    var NA_ASPECT_TOL       = 0.01;
    var na_snapMarker       = null;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Element Helper
    // -------------------------------------------------------------------------

    function Na__ImageViewer__El(id) {
        return document.getElementById(id);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Path Utilities
    // -------------------------------------------------------------------------

    function Na__ImageViewer__PathToFileURL(p) {
        var prefix = na_isWin ? 'file:///' : 'file://';
        return encodeURI(prefix + p);
    }

    function Na__ImageViewer__ToNativePath(p) {
        return na_isWin ? p.replace(/\//g, String.fromCharCode(92)) : p;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Canvas Rendering
    // -------------------------------------------------------------------------

    function Na__ImageViewer__ResizeCanvas() {
        if (!na_canvas) return;
        var rect  = na_canvas.getBoundingClientRect();
        var ratio = window.devicePixelRatio || 1;
        na_canvas.width  = Math.max(1, Math.floor(rect.width  * ratio));
        na_canvas.height = Math.max(1, Math.floor(rect.height * ratio));
        na_ctx.setTransform(1, 0, 0, 1, 0, 0);
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__Draw() {
        if (!na_ctx || !na_canvas) return;
        var w = na_canvas.width;
        var h = na_canvas.height;
        na_ctx.clearRect(0, 0, w, h);
        if (!na_viewer.img || !na_viewer.img.complete || !na_viewer.imgW) return;

        na_ctx.save();
        na_ctx.translate(w / 2 + na_viewer.offX, h / 2 + na_viewer.offY);
        na_ctx.rotate(na_viewer.rotation);
        na_ctx.scale(na_viewer.zoom, na_viewer.zoom);
        na_ctx.drawImage(na_viewer.img, -na_viewer.imgW / 2, -na_viewer.imgH / 2);
        na_ctx.restore();

        Na__ImageViewer__RunOverlayRenderers();
        Na__ImageViewer__DrawSnapMarker();
        if (!na_exportRatio) Na__ImageViewer__PersistSchedule();
    }

    function Na__ImageViewer__RunOverlayRenderers() {
        for (var i = 0; i < na_overlayRenderers.length; i++) {
            try { na_overlayRenderers[i](na_ctx); }
            catch (e) { /* a feature overlay must never break the base draw */ }
        }
    }

    // The photo at its own size, with every overlay drawn on it, onto a fresh
    // canvas. The view is swapped for the photo's own frame (zoom 1, no
    // rotation, centred) while the overlays draw, so they need no export code
    // of their own; getRatio() returns a size so lines and labels read on the
    // full-size picture as they do on screen at fit. The view comes back as
    // it was, whatever happens. `source` may be another Image of the same
    // photo (a data URL when the file itself would taint the canvas).
    var na_exportRatio = 0;

    function Na__ImageViewer__RenderExport(source) {
        var img = source || na_viewer.img;
        var W   = na_viewer.imgW, H = na_viewer.imgH;
        if (!img || !W || !H) return null;

        var out = document.createElement('canvas');
        out.width  = W;
        out.height = H;
        var octx = out.getContext('2d');

        var kept = {
            canvas: na_canvas, ctx: na_ctx, marker: na_snapMarker,
            zoom: na_viewer.zoom, rotation: na_viewer.rotation, offX: na_viewer.offX, offY: na_viewer.offY
        };
        try {
            na_canvas = out;
            na_ctx    = octx;
            na_snapMarker      = null;
            na_viewer.zoom     = 1;
            na_viewer.rotation = 0;
            na_viewer.offX     = 0;
            na_viewer.offY     = 0;
            na_exportRatio     = Math.max(1, Math.max(W, H) / 1200);

            octx.drawImage(img, 0, 0, W, H);
            Na__ImageViewer__RunOverlayRenderers();
        } finally {
            na_canvas = kept.canvas;
            na_ctx    = kept.ctx;
            na_snapMarker      = kept.marker;
            na_viewer.zoom     = kept.zoom;
            na_viewer.rotation = kept.rotation;
            na_viewer.offX     = kept.offX;
            na_viewer.offY     = kept.offY;
            na_exportRatio     = 0;
            Na__ImageViewer__Draw();
        }
        return out;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Keeping The Tools' Work In The Model
    // -------------------------------------------------------------------------

    function Na__ImageViewer__Round3(v) { return Math.round(v * 1000) / 1000; }

    // Converters for a photo of size w x h, and a stored size sw x sh (k = w / sw).
    function Na__ImageViewer__PersistConv(w, h, k) {
        var hw = w / 2, hh = h / 2;
        k = k || 1;
        return {
            k    : k,
            // viewer image space (centred) -> photo pixels from the top-left
            pt   : function(p) { var r = { x: Na__ImageViewer__Round3(p.x + hw), y: Na__ImageViewer__Round3(p.y + hh) }; if (typeof p.prec === 'number') r.prec = p.prec; return r; },
            // homogeneous vanishing point (x, y, w), same move
            vp   : function(v) { return { x: v.x + hw * v.w, y: v.y + hh * v.w, w: v.w }; },
            // and back, scaled to this photo
            unpt : function(p) {
                var x = Number(p && p.x), y = Number(p && p.y);
                if (!isFinite(x) || !isFinite(y)) return null;
                var r = { x: x * k - hw, y: y * k - hh };
                if (typeof p.prec === 'number' && isFinite(p.prec)) r.prec = p.prec * k;
                return r;
            },
            unvp : function(v) {
                var x = Number(v && v.x), y = Number(v && v.y), ww = Number(v && v.w);
                if (!isFinite(x) || !isFinite(y) || !isFinite(ww)) return null;
                return { x: x * k - hw * ww, y: y * k - hh * ww, w: ww };
            }
        };
    }

    function Na__ImageViewer__PersistSchedule() {
        var key = Na__ImageViewer__ImageKey();
        if (!key || !na_viewer.imgW || !Object.keys(na_persisters).length) return;
        if (na_persistJob && na_persistJob.key !== key) Na__ImageViewer__PersistFlush();
        na_persistJob = { key: key, w: na_viewer.imgW, h: na_viewer.imgH };
        clearTimeout(na_persistTimer);
        na_persistTimer = setTimeout(Na__ImageViewer__PersistFlush, NA_PERSIST_DELAY_MS);
    }

    // Send what changed for the photo waiting, now.
    function Na__ImageViewer__PersistFlush() {
        clearTimeout(na_persistTimer);
        na_persistTimer = null;
        var job = na_persistJob;
        na_persistJob = null;
        if (!job) return;
        var conv = Na__ImageViewer__PersistConv(job.w, job.h, 1);
        Object.keys(na_persisters).forEach(function(name) {
            var state = null;
            try { state = na_persisters[name].serialise(job.key, conv); }
            catch (e) { return; }
            var sent   = na_persistSent[name] || (na_persistSent[name] = {});
            var stored = na_persistStored[name] || {};
            if (state === null || state === undefined) {
                if (stored[job.key]) return;           // the model's, not shown yet: leave it
                if (!sent[job.key]) return;            // nothing there before either
                state = null;
            }
            var text = JSON.stringify({ tool: name, path: job.key, w: job.w, h: job.h, state: state });
            if (sent[job.key] === text) return;
            if (state === null && sent[job.key] === 'null') return;
            sent[job.key] = state === null ? 'null' : text;
            if (window.sketchup && typeof window.sketchup.tool_state_save === 'function') {
                window.sketchup.tool_state_save(text);
            }
        });
    }

    // A photo is showing: hand each tool the model's work for it, if it has none.
    function Na__ImageViewer__PersistMaterialise(key) {
        if (!key || !na_viewer.imgW) return;
        Object.keys(na_persisters).forEach(function(name) {
            var stored = na_persistStored[name];
            var entry  = stored && stored[key];
            if (!entry) return;
            var provider = na_persisters[name];
            var sw = Number(entry.w), sh = Number(entry.h), k;
            if (!(sw > 0) || !(sh > 0)) { delete stored[key]; return; }
            if (sw === na_viewer.imgW && sh === na_viewer.imgH) k = 1;
            else if (Math.abs(sw / sh - na_viewer.imgW / na_viewer.imgH) <= NA_ASPECT_TOL * (sw / sh)) k = na_viewer.imgW / sw;
            else return;                               // another shape: left in the model

            var conv = Na__ImageViewer__PersistConv(na_viewer.imgW, na_viewer.imgH, k);
            try {
                var has = provider.serialise(key, Na__ImageViewer__PersistConv(na_viewer.imgW, na_viewer.imgH, 1));
                if (has === null || has === undefined) provider.materialise(key, entry.state, conv);
            } catch (e) { /* a tool's restore must never break the viewer */ }
            delete stored[key];
            try {
                var now = provider.serialise(key, Na__ImageViewer__PersistConv(na_viewer.imgW, na_viewer.imgH, 1));
                (na_persistSent[name] || (na_persistSent[name] = {}))[key] = now === null || now === undefined ? 'null'
                    : JSON.stringify({ tool: name, path: key, w: na_viewer.imgW, h: na_viewer.imgH, state: now });
            } catch (e) { /* ignore */ }
        });
    }

    // Ruby's answer to a folder choice: { tool: { path: { w, h, state } } }.
    function Na__ImageViewer__OnToolStateLoaded(map) {
        if (!map || typeof map !== 'object') return;
        Object.keys(map).forEach(function(name) {
            var byPath = map[name];
            if (!byPath || typeof byPath !== 'object') return;
            var stored = na_persistStored[name] || (na_persistStored[name] = {});
            Object.keys(byPath).forEach(function(path) { if (byPath[path] && byPath[path].state) stored[path] = byPath[path]; });
        });
        if (na_viewer.imgW) {
            Na__ImageViewer__PersistMaterialise(Na__ImageViewer__ImageKey());
            Na__ImageViewer__Draw();
        }
    }

    var na_persistLastSaved = null;
    window.Na__ImageViewer__OnToolStateLoaded = Na__ImageViewer__OnToolStateLoaded;
    window.Na__ImageViewer__ToolStateOnSaved  = function(result) { na_persistLastSaved = result || null; };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Coordinate Transforms (image-space <-> canvas pixels)
    // -------------------------------------------------------------------------

    function Na__ImageViewer__ImgToScreen(pt) {
        if (!na_canvas) return { x: 0, y: 0 };
        var w   = na_canvas.width;
        var h   = na_canvas.height;
        var cos = Math.cos(na_viewer.rotation);
        var sin = Math.sin(na_viewer.rotation);
        var sx  = pt.x * na_viewer.zoom;
        var sy  = pt.y * na_viewer.zoom;
        return {
            x: (w / 2 + na_viewer.offX) + (sx * cos - sy * sin),
            y: (h / 2 + na_viewer.offY) + (sx * sin + sy * cos)
        };
    }

    function Na__ImageViewer__ScreenToImg(cx, cy) {
        if (!na_canvas) return { x: 0, y: 0 };
        var w   = na_canvas.width;
        var h   = na_canvas.height;
        var x   = cx - (w / 2 + na_viewer.offX);
        var y   = cy - (h / 2 + na_viewer.offY);
        var cos = Math.cos(-na_viewer.rotation);
        var sin = Math.sin(-na_viewer.rotation);
        return {
            x: (x * cos - y * sin) / na_viewer.zoom,
            y: (x * sin + y * cos) / na_viewer.zoom
        };
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | View Transform Controls
    // -------------------------------------------------------------------------

    function Na__ImageViewer__Fit() {
        if (!na_viewer.imgW || !na_viewer.imgH || !na_canvas) return;
        var w = na_canvas.width;
        var h = na_canvas.height;
        var s = Math.min(w / na_viewer.imgW, h / na_viewer.imgH);
        na_viewer.baseZoom = s;
        na_viewer.zoom     = s;
        na_viewer.rotation = 0;
        na_viewer.offX     = 0;
        na_viewer.offY     = 0;
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__Fill() {
        if (!na_viewer.imgW || !na_viewer.imgH || !na_canvas) return;
        var w = na_canvas.width;
        var h = na_canvas.height;
        na_viewer.baseZoom = Math.min(w / na_viewer.imgW, h / na_viewer.imgH);
        na_viewer.zoom     = Math.max(w / na_viewer.imgW, h / na_viewer.imgH);
        na_viewer.rotation = 0;
        na_viewer.offX     = 0;
        na_viewer.offY     = 0;
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__ActualSize() {
        na_viewer.zoom = 1;
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__RotateLeft() {
        na_viewer.rotation -= Math.PI / 2;
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__RotateRight() {
        na_viewer.rotation += Math.PI / 2;
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__ZoomAt(cx, cy, factor) {
        if (!na_canvas) return;
        var w   = na_canvas.width;
        var h   = na_canvas.height;
        var x   = cx - (w / 2 + na_viewer.offX);
        var y   = cy - (h / 2 + na_viewer.offY);
        var cos = Math.cos(-na_viewer.rotation);
        var sin = Math.sin(-na_viewer.rotation);
        var img = Na__ImageViewer__ScreenToImg(cx, cy);

        na_viewer.zoom = Math.max(0.05, Math.min(40, na_viewer.zoom * factor));

        var nx = img.x * na_viewer.zoom;
        var ny = img.y * na_viewer.zoom;
        na_viewer.offX -= (nx - (x * cos - y * sin));
        na_viewer.offY -= (ny - (x * sin + y * cos));
        Na__ImageViewer__Draw();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Image Loading and Navigation
    // -------------------------------------------------------------------------

    function Na__ImageViewer__LoadAt(i) {
        if (i < 0 || i >= na_images.length) return;
        Na__ImageViewer__PersistFlush();
        na_index = i;
        na_snapMarker = null;

        na_viewer.img  = new Image();
        na_viewer.imgW = 0;
        na_viewer.imgH = 0;

        na_viewer.img.onload = function() {
            na_viewer.imgW = na_viewer.img.naturalWidth;
            na_viewer.imgH = na_viewer.img.naturalHeight;
            Na__ImageViewer__Fit();
            Na__ImageViewer__UpdateStatus();
            Na__ImageViewer__HighlightThumb();
            Na__ImageViewer__PersistMaterialise(Na__ImageViewer__ImageKey());
            Na__ImageViewer__FireImageChanged();
        };

        na_viewer.img.onerror = function() {
            if (na_metaEl) na_metaEl.textContent = 'Failed to load image (format may be unsupported)';
        };

        na_viewer.img.src = Na__ImageViewer__PathToFileURL(na_images[na_index]);
    }

    function Na__ImageViewer__Next() {
        if (!na_images.length) return;
        Na__ImageViewer__LoadAt((na_index + 1) % na_images.length);
    }

    function Na__ImageViewer__Prev() {
        if (!na_images.length) return;
        Na__ImageViewer__LoadAt((na_index - 1 + na_images.length) % na_images.length);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Thumbnail Sidebar
    // -------------------------------------------------------------------------

    function Na__ImageViewer__RenderThumbs() {
        if (!na_thumbsEl) return;
        na_thumbsEl.innerHTML = '';
        na_images.forEach(function(p, i) {
            var card = document.createElement('div');
            card.className = 'naImageViewer__Thumb';

            var img    = document.createElement('img');
            img.className = 'naImageViewer__ThumbImg';
            img.loading   = 'lazy';
            img.src       = Na__ImageViewer__PathToFileURL(p);
            img.onerror   = function() { card.classList.add('naImageViewer__Thumb--hidden'); };

            var cap    = document.createElement('div');
            cap.className   = 'naImageViewer__ThumbCaption';
            cap.textContent = p.split('/').pop();

            card.appendChild(img);
            card.appendChild(cap);
            card.addEventListener('click', function() { Na__ImageViewer__LoadAt(i); });
            na_thumbsEl.appendChild(card);
        });
        Na__ImageViewer__HighlightThumb();
    }

    function Na__ImageViewer__HighlightThumb() {
        if (!na_thumbsEl) return;
        var all = na_thumbsEl.querySelectorAll('.naImageViewer__Thumb');
        for (var i = 0; i < all.length; i++) {
            all[i].classList.toggle('naImageViewer__Thumb--active', i === na_index);
        }
        var active = all[na_index];
        if (active) active.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Status Bar
    // -------------------------------------------------------------------------

    function Na__ImageViewer__UpdateStatus() {
        if (!na_metaEl) return;
        if (na_index < 0) {
            na_metaEl.textContent = 'No folder selected';
            return;
        }
        var name  = na_images[na_index].split('/').pop();
        var zoom  = Math.round(na_viewer.zoom * 100);
        var dims  = na_viewer.imgW + '\u00d7' + na_viewer.imgH;
        na_metaEl.textContent = (na_index + 1) + '/' + na_images.length + '  \u2022  ' + name + '  \u2022  ' + dims + '  \u2022  ' + zoom + '%';
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Clipboard Helper
    // -------------------------------------------------------------------------

    function Na__ImageViewer__CopyToClipboard(text) {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.left     = '-9999px';
        ta.style.top      = '0';
        ta.setAttribute('readonly', 'readonly');
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); } catch (e) { /* noop */ }
        document.body.removeChild(ta);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Event Registration
    // -------------------------------------------------------------------------

    function Na__ImageViewer__RegisterEvents() {
        var btnPrev    = Na__ImageViewer__El('naImageViewer_btnPrev');
        var btnNext    = Na__ImageViewer__El('naImageViewer_btnNext');
        var btnFit     = Na__ImageViewer__El('naImageViewer_btnFit');
        var btnFill    = Na__ImageViewer__El('naImageViewer_btnFill');
        var btn100     = Na__ImageViewer__El('naImageViewer_btn100');
        var btnZoomIn  = Na__ImageViewer__El('naImageViewer_btnZoomIn');
        var btnZoomOut = Na__ImageViewer__El('naImageViewer_btnZoomOut');
        var btnRotateL = Na__ImageViewer__El('naImageViewer_btnRotateL');
        var btnRotateR = Na__ImageViewer__El('naImageViewer_btnRotateR');
        var btnFull    = Na__ImageViewer__El('naImageViewer_btnFull');
        var btnReveal  = Na__ImageViewer__El('naImageViewer_btnReveal');
        var btnCopy    = Na__ImageViewer__El('naImageViewer_btnCopy');
        var btnUndo    = Na__ImageViewer__El('naImageViewer_btnUndo');
        var btnRedo    = Na__ImageViewer__El('naImageViewer_btnRedo');

        if (btnUndo)    btnUndo.addEventListener('click',    Na__ImageViewer__Undo);
        if (btnRedo)    btnRedo.addEventListener('click',    Na__ImageViewer__Redo);

        if (btnPrev)    btnPrev.addEventListener('click',    Na__ImageViewer__Prev);
        if (btnNext)    btnNext.addEventListener('click',    Na__ImageViewer__Next);
        if (btnFit)     btnFit.addEventListener('click',     Na__ImageViewer__Fit);
        if (btnFill)    btnFill.addEventListener('click',    Na__ImageViewer__Fill);
        if (btn100)     btn100.addEventListener('click',     Na__ImageViewer__ActualSize);

        if (btnZoomIn)  btnZoomIn.addEventListener('click',  function() { Na__ImageViewer__ZoomAt(na_canvas ? na_canvas.width / 2 : 0, na_canvas ? na_canvas.height / 2 : 0, 1.2); });
        if (btnZoomOut) btnZoomOut.addEventListener('click', function() { Na__ImageViewer__ZoomAt(na_canvas ? na_canvas.width / 2 : 0, na_canvas ? na_canvas.height / 2 : 0, 1 / 1.2); });

        if (btnRotateL) btnRotateL.addEventListener('click', Na__ImageViewer__RotateLeft);
        if (btnRotateR) btnRotateR.addEventListener('click', Na__ImageViewer__RotateRight);

        if (btnFull) {
            btnFull.addEventListener('click', function() {
                if (!document.fullscreenElement) {
                    if (document.documentElement.requestFullscreen) document.documentElement.requestFullscreen();
                } else {
                    if (document.exitFullscreen) document.exitFullscreen();
                }
            });
        }

        if (btnReveal) {
            btnReveal.addEventListener('click', function() {
                var p = na_images[na_index];
                if (p && window.sketchup && window.sketchup.open_in_os) {
                    window.sketchup.open_in_os(p);
                }
            });
        }

        if (btnCopy) {
            btnCopy.addEventListener('click', function() {
                var p = na_images[na_index];
                if (!p) return;
                Na__ImageViewer__CopyToClipboard(Na__ImageViewer__ToNativePath(p));
                if (window.sketchup && window.sketchup.copy_path) {
                    window.sketchup.copy_path(p);
                }
            });
        }

        if (na_canvas) {
            na_canvas.addEventListener('wheel', function(e) {
                e.preventDefault();
                var factor = e.deltaY < 0 ? 1.1 : 0.9;
                var ratio  = window.devicePixelRatio || 1;
                Na__ImageViewer__ZoomAt(e.offsetX * ratio, e.offsetY * ratio, factor);
            }, { passive: false });

            na_canvas.addEventListener('mouseleave', function() {
                if (!na_snapMarker) return;
                na_snapMarker = null;
                Na__ImageViewer__Draw();
            });

            // The middle button always pans, whatever tool is drawing (a tool that
            // turns panning off only takes the left button). No autoscroll.
            // A tool holding the canvas (claimTool) always keeps the left button,
            // whatever another tool's setPanEnabled last said: one tool's refresh
            // must never hand the left drag back to panning under another.
            na_canvas.addEventListener('mousedown', function(e) {
                var middle = e.button === 1;
                if (middle) e.preventDefault();
                if ((!na_panEnabled || na_toolOwner) && !middle) return;
                na_viewer.isPanning = true;
                na_viewer.startX    = e.clientX;
                na_viewer.startY    = e.clientY;
            });
        }

        window.addEventListener('mousemove', function(e) {
            if (!na_viewer.isPanning) return;
            var ratio    = window.devicePixelRatio || 1;
            na_viewer.offX  += (e.clientX - na_viewer.startX) * ratio;
            na_viewer.offY  += (e.clientY - na_viewer.startY) * ratio;
            na_viewer.startX = e.clientX;
            na_viewer.startY = e.clientY;
            Na__ImageViewer__Draw();
        });

        window.addEventListener('mouseup', function() {
            na_viewer.isPanning = false;
        });

        // A middle press must not start the browser's autoscroll anywhere over the photo.
        if (na_canvas) na_canvas.addEventListener('auxclick', function(e) { if (e.button === 1) e.preventDefault(); });

        window.addEventListener('resize', Na__ImageViewer__ResizeCanvas);

        window.addEventListener('keydown', function(e) {
            if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT')) return;

            var ctrlOrCmd = e.ctrlKey || e.metaKey;
            var lowerKey  = e.key ? e.key.toLowerCase() : '';
            if (ctrlOrCmd && lowerKey === 'z' && !e.shiftKey) {
                e.preventDefault();
                Na__ImageViewer__Undo();
                return;
            }
            if (ctrlOrCmd && (lowerKey === 'y' || (lowerKey === 'z' && e.shiftKey))) {
                e.preventDefault();
                Na__ImageViewer__Redo();
                return;
            }

            if      (e.key === 'ArrowRight')                       Na__ImageViewer__Next();
            else if (e.key === 'ArrowLeft')                        Na__ImageViewer__Prev();
            else if (e.key === '0')                                Na__ImageViewer__Fit();
            else if (e.key === '1')                                Na__ImageViewer__ActualSize();
            else if (e.key.toLowerCase() === 'r' && !e.shiftKey)  Na__ImageViewer__RotateLeft();
            else if (e.key.toLowerCase() === 'r' &&  e.shiftKey)  Na__ImageViewer__RotateRight();
            else if (e.key.toLowerCase() === 'f') {
                if (!document.fullscreenElement) {
                    if (document.documentElement.requestFullscreen) document.documentElement.requestFullscreen();
                } else {
                    if (document.exitFullscreen) document.exitFullscreen();
                }
            }
            else if (e.key === '+' || e.key === '=') Na__ImageViewer__ZoomAt(na_canvas ? na_canvas.width / 2 : 0, na_canvas ? na_canvas.height / 2 : 0, 1.1);
            else if (e.key === '-')                  Na__ImageViewer__ZoomAt(na_canvas ? na_canvas.width / 2 : 0, na_canvas ? na_canvas.height / 2 : 0, 1 / 1.1);
        });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Ruby-to-JS Data In
    // -------------------------------------------------------------------------

    function Na__ImageViewer__ShowRestoreNote(text) {
        var el = Na__ImageViewer__El('naImageViewer_restoreNote');
        if (!el) return;
        el.textContent = text || '';
        el.classList.toggle('naImageViewer__RestoreNote--visible', !!text);
    }

    function Na__ImageViewer__OnFolderChosen(list) {
        Na__ImageViewer__PersistFlush();
        Na__ImageViewer__ShowRestoreNote('');
        if (!list || !list.length) {
            na_images = [];
            na_index  = -1;
            if (na_thumbsEl) na_thumbsEl.innerHTML = '';
            if (na_metaEl)   na_metaEl.textContent  = list ? 'No supported images found in selected folder' : 'No folder selected';
            if (na_ctx && na_canvas) na_ctx.clearRect(0, 0, na_canvas.width, na_canvas.height);
            return;
        }
        na_images = list;
        Na__ImageViewer__RenderThumbs();
        Na__ImageViewer__LoadAt(0);
    }

    window.Na__ImageViewer__OnFolderChosen  = Na__ImageViewer__OnFolderChosen;
    window.Na__ImageViewer__ShowRestoreNote = Na__ImageViewer__ShowRestoreNote;
    window.SKP_onFolderChosen = function(list) {
        window.Na__ImageViewer__PendingFolderList = list;
        Na__ImageViewer__OnFolderChosen(list);
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Core API For Feature Files
    // -------------------------------------------------------------------------
    // A minimal, generic surface so separate feature files (e.g. the Measurement
    // overlay) can hook into the viewer without the base bridge knowing about
    // them. Registered overlays draw after the image; features toggle pan and
    // request redraws through here so the transform math stays single-sourced.

    function Na__ImageViewer__FireImageChanged() {
        Na__ImageViewer__SyncHistoryButtons();
        for (var i = 0; i < na_imageChangedCbs.length; i++) {
            try { na_imageChangedCbs[i](na_index); }
            catch (e) { /* a feature callback must never break navigation */ }
        }
    }

    // Features keep their drawings per image path rather than per list index,
    // so choosing another folder never shows one photo's lines on another.
    function Na__ImageViewer__ImageKey() {
        return (na_index >= 0 && na_images[na_index]) ? na_images[na_index] : '';
    }

    // One feature owns the canvas at a time; claiming it releases the last owner.
    function Na__ImageViewer__ClaimTool(name, releaseFn) {
        if (na_toolOwner && na_toolOwner.name === name) return;
        na_snapMarker = null;
        var previous = na_toolOwner;
        na_toolOwner = { name: name, release: typeof releaseFn === 'function' ? releaseFn : function() {} };
        if (!previous) return;
        try { previous.release(); }
        catch (e) { /* a feature release must never block the new tool */ }
    }

    function Na__ImageViewer__ReleaseTool(name) {
        if (na_toolOwner && na_toolOwner.name === name) {
            na_toolOwner  = null;
            na_snapMarker = null;
        }
    }

    // The best point any provider offers near (cx, cy), in canvas pixels: an
    // endpoint, tick or intersection before a point that is merely on a
    // guide, then the nearest.
    function Na__ImageViewer__Snap(cx, cy) {
        var best = null, bestRank = Infinity, bestD = Infinity;
        for (var i = 0; i < na_snapProviders.length; i++) {
            try {
                var hit = na_snapProviders[i](cx, cy);
                if (!hit || !hit.screen) continue;
                var rank = hit.kind === 'guide' ? 1 : 0;
                var d    = Math.sqrt((hit.screen.x - cx) * (hit.screen.x - cx) + (hit.screen.y - cy) * (hit.screen.y - cy));
                if (rank < bestRank || (rank === bestRank && d < bestD)) { best = hit; bestRank = rank; bestD = d; }
            } catch (e) { /* a snap provider must never break drawing */ }
        }
        return best;
    }

    // SketchUp-like inference marker, drawn above every overlay: a green dot
    // on an endpoint, a teal dot on a count's tick, an X on an intersection,
    // a square on a guide, with a pale tooltip naming it.
    function Na__ImageViewer__DrawSnapMarker() {
        var hit = na_snapMarker;
        if (!hit || !hit.screen || !na_ctx) return;
        var ctx = na_ctx, k = window.devicePixelRatio || 1;
        var x = hit.screen.x, y = hit.screen.y;
        ctx.save();
        ctx.lineCap = 'round';
        if (hit.kind === 'endpoint' || hit.kind === 'division') {
            ctx.beginPath();
            ctx.arc(x, y, 5 * k, 0, Math.PI * 2);
            ctx.fillStyle = hit.kind === 'division' ? '#00838f' : '#21a336'; ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 1.5 * k;
            ctx.fill(); ctx.stroke();
        } else if (hit.kind === 'intersection') {
            [['#ffffff', 4], ['#1b1f24', 1.8]].forEach(function(pen) {
                ctx.beginPath();
                ctx.moveTo(x - 5 * k, y - 5 * k); ctx.lineTo(x + 5 * k, y + 5 * k);
                ctx.moveTo(x + 5 * k, y - 5 * k); ctx.lineTo(x - 5 * k, y + 5 * k);
                ctx.strokeStyle = pen[0]; ctx.lineWidth = pen[1] * k;
                ctx.stroke();
            });
        } else {
            ctx.beginPath();
            ctx.rect(x - 3.5 * k, y - 3.5 * k, 7 * k, 7 * k);
            ctx.fillStyle = '#1b1f24'; ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 1.5 * k;
            ctx.fill(); ctx.stroke();
        }
        if (hit.label) {
            ctx.font = (11 * k) + 'px "Segoe UI", Arial, sans-serif';
            ctx.textBaseline = 'middle';
            var tw = ctx.measureText(hit.label).width, bx = x + 12 * k, by = y + 16 * k, bh = 18 * k;
            ctx.beginPath();
            ctx.rect(bx, by - bh / 2, tw + 10 * k, bh);
            ctx.fillStyle = '#fffbd6'; ctx.strokeStyle = '#8a8466'; ctx.lineWidth = 1 * k;
            ctx.fill(); ctx.stroke();
            ctx.fillStyle = '#1b1f24';
            ctx.fillText(hit.label, bx + 5 * k, by + 0.5 * k);
        }
        ctx.restore();
    }

    // Shared undo history. Each feature registers how to snapshot and restore
    // its own state for an image; every change snapshots all of them first.
    function Na__ImageViewer__HistorySnapshot(key) {
        var snap = {};
        for (var i = 0; i < na_historyProviders.length; i++) {
            var p = na_historyProviders[i];
            try { snap[p.name] = p.snapshot(key); }
            catch (e) { snap[p.name] = null; }
        }
        return snap;
    }

    function Na__ImageViewer__HistoryRestore(key, snap) {
        for (var i = 0; i < na_historyProviders.length; i++) {
            var p = na_historyProviders[i];
            try { p.restore(key, snap ? snap[p.name] : null); }
            catch (e) { /* one feature's restore must not stop the others */ }
        }
    }

    function Na__ImageViewer__FireHistoryChanged(reason) {
        Na__ImageViewer__SyncHistoryButtons();
        for (var i = 0; i < na_historyCbs.length; i++) {
            try { na_historyCbs[i](reason); }
            catch (e) { /* a feature callback must never break undo */ }
        }
    }

    function Na__ImageViewer__PushHistory() {
        var key = Na__ImageViewer__ImageKey();
        if (!key) return;
        if (!na_undoByKey[key]) na_undoByKey[key] = [];
        na_undoByKey[key].push(Na__ImageViewer__HistorySnapshot(key));
        if (na_undoByKey[key].length > NA_HISTORY_LIMIT) na_undoByKey[key].shift();
        na_redoByKey[key] = []; // a fresh action invalidates the redo history
        Na__ImageViewer__FireHistoryChanged('push');
    }

    function Na__ImageViewer__Undo() {
        var key   = Na__ImageViewer__ImageKey();
        var stack = na_undoByKey[key];
        if (!key || !stack || !stack.length) return;
        if (!na_redoByKey[key]) na_redoByKey[key] = [];
        na_redoByKey[key].push(Na__ImageViewer__HistorySnapshot(key));
        Na__ImageViewer__HistoryRestore(key, stack.pop());
        Na__ImageViewer__FireHistoryChanged('undo');
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__Redo() {
        var key   = Na__ImageViewer__ImageKey();
        var stack = na_redoByKey[key];
        if (!key || !stack || !stack.length) return;
        if (!na_undoByKey[key]) na_undoByKey[key] = [];
        na_undoByKey[key].push(Na__ImageViewer__HistorySnapshot(key));
        Na__ImageViewer__HistoryRestore(key, stack.pop());
        Na__ImageViewer__FireHistoryChanged('redo');
        Na__ImageViewer__Draw();
    }

    function Na__ImageViewer__SyncHistoryButtons() {
        var key     = Na__ImageViewer__ImageKey();
        var btnUndo = Na__ImageViewer__El('naImageViewer_btnUndo');
        var btnRedo = Na__ImageViewer__El('naImageViewer_btnRedo');
        if (btnUndo) btnUndo.disabled = !(na_undoByKey[key] && na_undoByKey[key].length);
        if (btnRedo) btnRedo.disabled = !(na_redoByKey[key] && na_redoByKey[key].length);
    }

    window.Na__ImageViewer__Core = {
        getCanvas        : function() { return na_canvas; },
        getCtx           : function() { return na_ctx; },
        getIndex         : function() { return na_index; },
        getImages        : function() { return na_images.slice(); },
        getImageKey      : Na__ImageViewer__ImageKey,
        getImage         : function() { return na_viewer.img; },
        getImageSize     : function() { return { w: na_viewer.imgW, h: na_viewer.imgH }; },
        getZoom          : function() { return na_viewer.zoom; },
        getRotation      : function() { return na_viewer.rotation; },
        getRatio         : function() { return na_exportRatio || window.devicePixelRatio || 1; },
        renderExport     : Na__ImageViewer__RenderExport,
        isExporting      : function() { return na_exportRatio > 0; },
        imgToScreen      : Na__ImageViewer__ImgToScreen,
        screenToImg      : Na__ImageViewer__ScreenToImg,
        requestDraw      : Na__ImageViewer__Draw,
        resize           : Na__ImageViewer__ResizeCanvas,
        panBy            : function(dx, dy) { na_viewer.offX += dx; na_viewer.offY += dy; Na__ImageViewer__Draw(); },
        setPanEnabled    : function(b) { na_panEnabled = !!b; },
        registerOverlay  : function(fn) { if (typeof fn === 'function') na_overlayRenderers.push(fn); },
        onImageChanged   : function(fn) { if (typeof fn === 'function') na_imageChangedCbs.push(fn); },
        claimTool        : Na__ImageViewer__ClaimTool,
        releaseTool      : Na__ImageViewer__ReleaseTool,
        getToolOwner     : function() { return na_toolOwner ? na_toolOwner.name : null; },
        registerHistory  : function(name, provider) {
            if (provider && typeof provider.snapshot === 'function' && typeof provider.restore === 'function') {
                na_historyProviders.push({ name: String(name), snapshot: provider.snapshot, restore: provider.restore });
            }
        },
        onHistoryChanged : function(fn) { if (typeof fn === 'function') na_historyCbs.push(fn); },
        registerSnap     : function(fn) { if (typeof fn === 'function') na_snapProviders.push(fn); },
        snap             : Na__ImageViewer__Snap,
        setSnapMarker    : function(hit) { na_snapMarker = hit || null; },
        getSnapMarker    : function() { return na_snapMarker; },
        pushHistory      : Na__ImageViewer__PushHistory,
        undo             : Na__ImageViewer__Undo,
        redo             : Na__ImageViewer__Redo,
        setThumbsFolded  : Na__ImageViewer__SetThumbsFolded,
        registerPersist  : function(name, provider) {
            if (provider && typeof provider.serialise === 'function' && typeof provider.materialise === 'function') na_persisters[String(name)] = provider;
        },
        persistNow       : function() { Na__ImageViewer__PersistSchedule(); Na__ImageViewer__PersistFlush(); },
        persistSaved     : function() { return na_persistLastSaved; }
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    // The thumbnail strip folds away for more photo. Open by default; the
    // choice is remembered where the dialog allows storage.
    var NA_STORE_THUMBS_FOLDED = 'Na__ImageViewer__ThumbsFolded';

    function Na__ImageViewer__SetThumbsFolded(folded) {
        var main = document.querySelector('.naImageViewer__Main');
        var btn  = Na__ImageViewer__El('naImageViewer_thumbsFold');
        if (!main) return;
        main.classList.toggle('naImageViewer__Main--thumbsFolded', !!folded);
        if (btn) {
            var label = folded ? 'Show the thumbnails' : 'Hide the thumbnails';
            btn.setAttribute('aria-expanded', folded ? 'false' : 'true');
            btn.setAttribute('aria-label', label);
            btn.title = label;
        }
        try { if (window.localStorage) window.localStorage.setItem(NA_STORE_THUMBS_FOLDED, folded ? '1' : '0'); } catch (_e) { /* session only */ }
        Na__ImageViewer__ResizeCanvas();
        if (!folded) Na__ImageViewer__HighlightThumb();
    }

    // The strip's scrollbar shows only while it is in use: pointer over it, or scrolling.
    function Na__ImageViewer__InitQuietScrollbar() {
        var el = na_thumbsEl, timer = null, over = false;
        if (!el) return;
        function set(on) { if (el.classList.contains('naImageViewer__Thumbs--inUse') !== on) el.classList.toggle('naImageViewer__Thumbs--inUse', on); }
        el.addEventListener('mouseenter', function() { over = true; set(true); });
        el.addEventListener('mouseleave', function() { over = false; if (!timer) set(false); });
        el.addEventListener('scroll', function() {
            set(true);
            clearTimeout(timer);
            timer = setTimeout(function() { timer = null; if (!over) set(false); }, 900);
        }, { passive: true });
    }

    function Na__ImageViewer__InitThumbsFold() {
        var btn = Na__ImageViewer__El('naImageViewer_thumbsFold');
        if (!btn) return;
        var folded = false;
        try { folded = !!window.localStorage && window.localStorage.getItem(NA_STORE_THUMBS_FOLDED) === '1'; } catch (_e) { folded = false; }
        btn.addEventListener('click', function() {
            var main = document.querySelector('.naImageViewer__Main');
            Na__ImageViewer__SetThumbsFolded(!(main && main.classList.contains('naImageViewer__Main--thumbsFolded')));
        });
        if (folded) Na__ImageViewer__SetThumbsFolded(true);
    }

    function Na__ImageViewer__Init() {
        na_canvas   = Na__ImageViewer__El('naImageViewer_canvas');
        na_thumbsEl = Na__ImageViewer__El('naImageViewer_thumbs');
        na_metaEl   = Na__ImageViewer__El('naImageViewer_meta');
        na_ctx      = na_canvas ? na_canvas.getContext('2d') : null;

        Na__ImageViewer__RegisterEvents();
        Na__ImageViewer__InitThumbsFold();
        Na__ImageViewer__InitQuietScrollbar();
        Na__ImageViewer__ResizeCanvas();
        Na__ImageViewer__UpdateStatus();

        if (window.Na__ImageViewer__PendingFolderList) {
            Na__ImageViewer__OnFolderChosen(window.Na__ImageViewer__PendingFolderList);
        } else if (window.sketchup && window.sketchup.dialog_ready) {
            // Ask Ruby for this model's remembered folder, if it has one.
            window.sketchup.dialog_ready();
        }
    }

    // Defensive init: if DOMContentLoaded already fired (readyState is 'interactive'
    // or 'complete' — typical for inline scripts at bottom of body), run immediately.
    // Otherwise wait for the event. Handles both CEF and standard browser behaviour.
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ImageViewer__Init);
    } else {
        Na__ImageViewer__Init();
    }

    // endregion ---------------------------------------------------------------

    // =============================================================================
    // END OF FILE
    // =============================================================================

})();
