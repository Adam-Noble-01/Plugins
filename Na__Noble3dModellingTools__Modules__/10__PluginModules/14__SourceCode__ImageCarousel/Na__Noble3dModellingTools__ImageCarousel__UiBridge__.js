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
            if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;

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

    function Na__ImageViewer__OnFolderChosen(list) {
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

    window.Na__ImageViewer__OnFolderChosen = Na__ImageViewer__OnFolderChosen;
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
        for (var i = 0; i < na_imageChangedCbs.length; i++) {
            try { na_imageChangedCbs[i](na_index); }
            catch (e) { /* a feature callback must never break navigation */ }
        }
    }

    window.Na__ImageViewer__Core = {
        getCanvas       : function() { return na_canvas; },
        getCtx          : function() { return na_ctx; },
        getIndex        : function() { return na_index; },
        getRatio        : function() { return window.devicePixelRatio || 1; },
        imgToScreen     : Na__ImageViewer__ImgToScreen,
        screenToImg     : Na__ImageViewer__ScreenToImg,
        requestDraw     : Na__ImageViewer__Draw,
        setPanEnabled   : function(b) { na_panEnabled = !!b; },
        registerOverlay : function(fn) { if (typeof fn === 'function') na_overlayRenderers.push(fn); },
        onImageChanged  : function(fn) { if (typeof fn === 'function') na_imageChangedCbs.push(fn); }
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
