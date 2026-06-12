// =============================================================================
// NA NOBLE3D MODELLING TOOLS - PNG TO LINEWORK - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__PngToLinework__UiBridge__.js
// NAMESPACE  : window.Na__PngToLinework__* (Ruby-facing entry points)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Wire the dialog controls to the trace engine and SVG preview,
//              enforce the edge-count crash guard, and round-trip to Ruby.
// CREATED    : 2026
//
// RUBY -> JS : Na__PngToLinework__SetSourceImage(payload)
//              Na__PngToLinework__SetStatus(message, success)
// JS -> RUBY : sketchup.na_dialog_ready / na_choose_png / na_create_linework
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants and Module State
    // -------------------------------------------------------------------------

    var NA_MAX_EDGE_COUNT     = 50000;                                        // <-- Mirrored hard guard in the Ruby GeometryBuilder
    var NA_WARN_EDGE_COUNT    = 20000;
    var NA_RETRACE_DEBOUNCE   = 150;                                          // <-- Keeps slider scrubbing fast and forgiving

    var sourceImage   = null;                                                 // <-- { dataUri, fileName, pixelWidth, pixelHeight }
    var decodedImage  = null;
    var traceResult   = null;
    var retraceTimer  = null;
    var firstRender   = true;

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_el(id) { return document.getElementById(id); }

    // HELPER FUNCTION | Read the Current Control Values as Trace Options
    // ------------------------------------------------------------
    function na_readControls() {
        return {
            realWidthMm    : Math.max(parseFloat(na_el('naPng_realWidth').value) || 1000, 10),
            minSegmentMm   : Math.max(parseFloat(na_el('naPng_minSegment').value) || 5, 0.25),
            minPathLengthMm: Math.max(parseFloat(na_el('naPng_minPathLength').value) || 0, 0),
            vertexMergeMm  : Math.max(parseFloat(na_el('naPng_vertexMerge').value) || 0, 0),
            alphaThreshold : Math.min(Math.max(parseInt(na_el('naPng_alphaThreshold').value, 10) || 128, 1), 254),
            traceMode      : na_el('naPng_traceMode').value,
            plane          : na_el('naPng_plane').value,
            showSource     : na_el('naPng_showSource').checked
        };
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Set the Footer Status Bar Message
    // ------------------------------------------------------------
    function na_setStatus(message, success) {
        var statusEl = na_el('naPng_status');
        if (!statusEl) { return; }
        statusEl.textContent = message;
        statusEl.className = 'naPngTrace__StatusText' + (success === false ? ' naPngTrace__StatusText--error' : '');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Send a Log Line to the Ruby Console
    // ------------------------------------------------------------
    function na_log(message) {
        if (window.sketchup && window.sketchup.na_js_log) {
            window.sketchup.na_js_log(String(message));
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ruby-Facing Entry Points
    // -------------------------------------------------------------------------

    // FUNCTION | Receive the Source Image Pushed from Ruby
    // ------------------------------------------------------------
    window.Na__PngToLinework__SetSourceImage = function (payload) {
        sourceImage  = payload;
        decodedImage = null;
        traceResult  = null;
        firstRender  = true;

        na_el('naPng_fileName').textContent = payload.fileName + '  (' + payload.pixelWidth + ' x ' + payload.pixelHeight + ' px)';
        na_setStatus('Decoding ' + payload.fileName + '...', true);

        window.Na__PngToLinework__TraceEngine.na_decodeImage(payload.dataUri)
            .then(function (decoded) {
                if (!window.Na__PngToLinework__TraceEngine.na_hasAlphaVariation(decoded.imageData)) {
                    na_setStatus('This PNG is fully opaque - no transparent background found. Choose a proper transparent-background PNG.', false);
                    na_el('naPng_btnCreate').disabled = true;
                    return;
                }
                decodedImage = decoded;
                if (decoded.wasDownscaled) {
                    na_log('Image downscaled to ' + decoded.width + 'x' + decoded.height + ' px for tracing.');
                }
                na_scheduleRetrace();
            })
            .catch(function (error) {
                na_setStatus('PNG decode failed: ' + error.message, false);
            });
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive a Status Message Pushed from Ruby
    // ------------------------------------------------------------
    window.Na__PngToLinework__SetStatus = function (message, success) {
        na_setStatus(message, success);
    };
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Trace Orchestration
    // -------------------------------------------------------------------------

    // FUNCTION | Schedule a Debounced Re-Trace After Control Changes
    // ------------------------------------------------------------
    function na_scheduleRetrace() {
        if (retraceTimer) { clearTimeout(retraceTimer); }
        retraceTimer = setTimeout(na_retrace, NA_RETRACE_DEBOUNCE);
    }
    // ------------------------------------------------------------

    // FUNCTION | Run the Full Trace Pipeline and Refresh the Preview
    // ------------------------------------------------------------
    function na_retrace() {
        if (!decodedImage) { return; }

        var options = na_readControls();
        na_setStatus('Tracing...', true);

        setTimeout(function () {                                              // <-- Let the status paint before the heavy work
            try {
                traceResult = window.Na__PngToLinework__TraceEngine.na_trace(decodedImage, options);
                na_renderPreview(options);
                na_updateStats(options);
            } catch (error) {
                na_setStatus('Trace failed: ' + error.message, false);
                na_log('Trace error: ' + (error.stack || error.message));
            }
        }, 10);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Push the Trace Result into the SVG Preview
    // ------------------------------------------------------------
    function na_renderPreview(options) {
        window.Na__PngToLinework__SvgPreview.na_render(traceResult, {
            showSource    : options.showSource,
            sourceDataUri : sourceImage ? sourceImage.dataUri : null
        });

        if (firstRender) {
            window.Na__PngToLinework__SvgPreview.na_resetView();
            firstRender = false;
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Refresh the Stats Readout and Edge-Count Guard
    // ------------------------------------------------------------
    function na_updateStats(options) {
        var stats        = traceResult.stats;
        var derivedH     = decodedImage ? (decodedImage.height * traceResult.mmPerPx) : 0;
        var createButton = na_el('naPng_btnCreate');

        na_el('naPng_statPaths').textContent    = String(stats.polylineCount);
        na_el('naPng_statVertices').textContent = String(stats.vertexCount);
        na_el('naPng_statEdges').textContent    = String(stats.segmentCount);
        na_el('naPng_statScale').textContent    = traceResult.mmPerPx.toFixed(2) + ' mm/px';
        na_el('naPng_statSize').textContent     = Math.round(options.realWidthMm) + ' x ' + Math.round(derivedH) + ' mm';

        var edgesEl = na_el('naPng_statEdges');
        edgesEl.className = 'naPngTrace__StatValue';

        if (stats.segmentCount === 0) {
            createButton.disabled = true;
            na_setStatus('No linework traced - try lowering the alpha threshold or the minimum segment length.', false);
        } else if (stats.segmentCount > NA_MAX_EDGE_COUNT) {
            createButton.disabled = true;
            edgesEl.className += ' naPngTrace__StatValue--error';
            na_setStatus('Edge count ' + stats.segmentCount + ' exceeds the ' + NA_MAX_EDGE_COUNT + ' safety limit. Increase the minimum segment length.', false);
        } else {
            createButton.disabled = false;
            if (stats.segmentCount > NA_WARN_EDGE_COUNT) {
                edgesEl.className += ' naPngTrace__StatValue--warn';
                na_setStatus('Trace complete - ' + stats.segmentCount + ' edges is heavy; consider a larger minimum segment length.', true);
            } else {
                na_setStatus('Trace complete. Adjust controls or press Create & Place.', true);
            }
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Actions to Ruby
    // -------------------------------------------------------------------------

    // FUNCTION | Send the Traced Polylines to Ruby for Building and Placement
    // ------------------------------------------------------------
    function na_createAndPlace() {
        if (!traceResult || !traceResult.stats.segmentCount) { return; }

        var options = na_readControls();
        var rounded = traceResult.polylines.map(function (polyline) {
            return polyline.map(function (point) {
                return [Math.round(point[0] * 100) / 100, Math.round(point[1] * 100) / 100];
            });
        });

        var payload = {
            plane     : options.plane,
            fileName  : sourceImage ? sourceImage.fileName : 'PngLinework',
            polylines : rounded
        };

        if (window.sketchup && window.sketchup.na_create_linework) {
            na_setStatus('Building SketchUp linework...', true);
            window.sketchup.na_create_linework(JSON.stringify(payload));
        } else {
            na_setStatus('SketchUp bridge unavailable (browser preview mode).', false);
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Control Wiring
    // -------------------------------------------------------------------------

    // FUNCTION | Attach All Control and Button Listeners
    // ------------------------------------------------------------
    function na_attachListeners() {
        ['naPng_realWidth', 'naPng_minSegment', 'naPng_minPathLength', 'naPng_vertexMerge', 'naPng_alphaThreshold'].forEach(function (id) {
            na_el(id).addEventListener('input', function () {
                na_syncSliderPair(id);
                na_scheduleRetrace();
            });
        });

        ['naPng_minSegmentSlider', 'naPng_minPathLengthSlider', 'naPng_vertexMergeSlider', 'naPng_alphaThresholdSlider'].forEach(function (id) {
            na_el(id).addEventListener('input', function () {
                var pairedInput = na_el(id.replace('Slider', ''));
                pairedInput.value = na_el(id).value;
                na_scheduleRetrace();
            });
        });

        ['naPng_traceMode', 'naPng_plane'].forEach(function (id) {
            na_el(id).addEventListener('change', na_scheduleRetrace);
        });

        na_el('naPng_showSource').addEventListener('change', function () {
            if (traceResult) { na_renderPreview(na_readControls()); }
        });

        na_el('naPng_btnChoose').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_choose_png) { window.sketchup.na_choose_png(''); }
        });

        na_el('naPng_btnResetView').addEventListener('click', function () {
            window.Na__PngToLinework__SvgPreview.na_resetView();
        });

        na_el('naPng_btnCreate').addEventListener('click', na_createAndPlace);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Mirror a Number Input Back onto Its Paired Slider
    // ------------------------------------------------------------
    function na_syncSliderPair(inputId) {
        var slider = na_el(inputId + 'Slider');
        if (slider) { slider.value = na_el(inputId).value; }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Boot
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        window.Na__PngToLinework__SvgPreview.na_init('naPng_svg', 'naPng_svgWrapper');
        na_attachListeners();
        na_setStatus('Waiting for image...', true);

        if (window.sketchup && window.sketchup.na_dialog_ready) {
            window.sketchup.na_dialog_ready('');                              // <-- Ask Ruby to push the pre-selected image
        }
    });

    // endregion ---------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
