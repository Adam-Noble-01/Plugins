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
    // guides) offer a point near the pointer; the Core draws one marker.
    var na_snapProviders    = [];     // fn(cx, cy) -> { img, screen, kind, label } | null
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
    }

    function Na__ImageViewer__RunOverlayRenderers() {
        for (var i = 0; i < na_overlayRenderers.length; i++) {
            try { na_overlayRenderers[i](na_ctx); }
            catch (e) { /* a feature overlay must never break the base draw */ }
        }
    }

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

            na_canvas.addEventListener('mousedown', function(e) {
                if (!na_panEnabled) return;
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

    // The first provider with a point near (cx, cy), in canvas pixels.
    function Na__ImageViewer__Snap(cx, cy) {
        for (var i = 0; i < na_snapProviders.length; i++) {
            try {
                var hit = na_snapProviders[i](cx, cy);
                if (hit) return hit;
            } catch (e) { /* a snap provider must never break drawing */ }
        }
        return null;
    }

    // SketchUp-like inference marker, drawn above every overlay: a green dot
    // on an endpoint, an X on an intersection, a square on a guide, with a
    // pale tooltip naming it.
    function Na__ImageViewer__DrawSnapMarker() {
        var hit = na_snapMarker;
        if (!hit || !hit.screen || !na_ctx) return;
        var ctx = na_ctx, k = window.devicePixelRatio || 1;
        var x = hit.screen.x, y = hit.screen.y;
        ctx.save();
        ctx.lineCap = 'round';
        if (hit.kind === 'endpoint') {
            ctx.beginPath();
            ctx.arc(x, y, 5 * k, 0, Math.PI * 2);
            ctx.fillStyle = '#21a336'; ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 1.5 * k;
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
        getImageKey      : Na__ImageViewer__ImageKey,
        getImage         : function() { return na_viewer.img; },
        getImageSize     : function() { return { w: na_viewer.imgW, h: na_viewer.imgH }; },
        getZoom          : function() { return na_viewer.zoom; },
        getRotation      : function() { return na_viewer.rotation; },
        getRatio         : function() { return window.devicePixelRatio || 1; },
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
        redo             : Na__ImageViewer__Redo
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Initialisation
    // -------------------------------------------------------------------------

    function Na__ImageViewer__Init() {
        na_canvas   = Na__ImageViewer__El('naImageViewer_canvas');
        na_thumbsEl = Na__ImageViewer__El('naImageViewer_thumbs');
        na_metaEl   = Na__ImageViewer__El('naImageViewer_meta');
        na_ctx      = na_canvas ? na_canvas.getContext('2d') : null;

        Na__ImageViewer__RegisterEvents();
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
